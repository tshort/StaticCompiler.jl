struct GlobalsContext
    invokes::Set{Any}
end
GlobalsContext() = GlobalsContext(Set())


"""
    fix_globals!(mod::LLVM.Module)

Replace function addresses in `mod` with references to global data structures.
For each global variable, two LLVM global objects are created:

* `jl.global.data` -- An LLVM 'i8' vector holding a serialized version of the Julia object.
* `jl.global` -- A pointer to the unserialized Julia object.

The `inttopt` with the function address is replaced by `jl.global`.

A function `jl_init_globals` is added to `mod`. This function deserializes the data in
`jl.global.data` and updates `jl.global`.
"""

_opcode(x::LLVM.ConstantExpr) = LLVM.API.LLVMGetConstOpcode(LLVM.ref(x))

function fix_globals!(mod::LLVM.Module)
    # Create a `jl_init_globals` function.
    jl_init_globals_func = LLVM.Function(mod, "jl_init_globals",
                                         LLVM.FunctionType(julia_to_llvm(Cvoid), LLVMType[]))
    jl_init_global_entry = BasicBlock(jl_init_globals_func, "entry", context(mod))

    # Definitions for utility functions
    func_type = LLVM.FunctionType(julia_to_llvm(Any), LLVMType[LLVM.PointerType(julia_to_llvm(Int8))])
    deserialize_funs = Dict()

    uint8_t = julia_to_llvm(UInt8)

    ctx = SerializeContext()
    es = []
    objs = Set()
    gptridx = Dict()
    instrs = []
    gptrs = []
    j = 1   # counter for position in gptridx
    Builder(context(mod)) do builder
        toinstr!(x) = x
        function toinstr!(x::LLVM.ConstantExpr)
            if _opcode(x) == LLVM.API.LLVMAddrSpaceCast
                val = toinstr!(first(operands(x)))
                ret = addrspacecast!(builder, val, llvmtype(x))
                return ret
            elseif _opcode(x) == LLVM.API.LLVMGetElementPtr
                ops = operands(x)
                val = toinstr!(first(ops))
                ret = gep!(builder, val, [ops[i] for i in 2:length(ops)])
                return ret
            elseif _opcode(x) == LLVM.API.LLVMBitCast
                ops = operands(x)
                val = toinstr!(first(ops))
                ret = pointercast!(builder, val, llvmtype(x))
                return ret
            elseif _opcode(x) == LLVM.API.LLVMIntToPtr
                ptr = Ptr{Any}(convert(Int, first(operands(x))))
                obj = unsafe_pointer_to_objref(ptr)
                if !in(obj, objs)
                    push!(es, serialize(ctx, obj))
                    push!(objs, obj)
                    # Create pointers to the data.
                    gptr = GlobalVariable(mod, julia_to_llvm(Any), "jl.global")
                    linkage!(gptr, LLVM.API.LLVMInternalLinkage)
                    LLVM.API.LLVMSetInitializer(LLVM.ref(gptr), LLVM.ref(null(julia_to_llvm(Any))))
                    push!(gptrs, gptr)
                    gptridx[obj] = j
                    j += 1
                end
                gptr = gptrs[gptridx[obj]]
                gptr2 = load!(builder, gptr)
                ret = pointercast!(builder, gptr2, llvmtype(x))
                return ret
            end
            return x
        end
        for fun in functions(mod)
            if startswith(LLVM.name(fun), "jfptr")
                unsafe_delete!(mod, fun)
                continue
            end

            for blk in blocks(fun), instr in instructions(blk)
                # Set up functions to walk the operands of the instruction
                # and convert appropriate ConstantExpr's to instructions.
                # Look for `LLVMIntToPtr` expressions.
                position!(builder, instr)
                ops = operands(instr)
                N = opcode(instr) == LLVM.API.LLVMCall ? length(ops) - 1 : length(ops)
                if opcode(instr) == LLVM.API.LLVMCall && name(last(operands(instr))) == "jl_type_error"
                    continue
                end
                for i in 1:N
                    try
                        if opcode(instr) == LLVM.API.LLVMPHI
                            position!(builder, last(instructions(LLVM.incoming(instr)[i][2])))
                        end
                        ops[i] = toinstr!(ops[i])
                    catch x
                    end
                end
            end
        end
    end
    nglobals = length(es)
    #@show mod
    #verify(mod)
    for i in 1:nglobals
        # Assign the appropriate function argument to the appropriate global.
        es[i] = :(unsafe_store!($((Symbol("global", i))), $(es[i])))
    end
    # Define the deserializing function.
    fune = quote
        function _deserialize_globals(Vptr, $((Symbol("global", i) for i in 1:nglobals)...))
            $(ctx.init...)
            $(es...)
            return
        end
    end
    # @show fune
    # Execute the deserializing function.
    deser_fun = eval(fune)
    v = take!(ctx.io)
    gv_typ = LLVM.ArrayType(uint8_t, length(v))
    data = LLVM.GlobalVariable(mod, gv_typ, "jl.global.data")
    linkage!(data, LLVM.API.LLVMExternalLinkage)
    constant!(data, true)
    LLVM.API.LLVMSetInitializer(LLVM.ref(data),
                                LLVM.API.LLVMConstArray(LLVM.ref(uint8_t),
                                                        [LLVM.ref(ConstantInt(uint8_t, x)) for x in v],
                                                        UInt32(length(v))))
    Builder(context(mod)) do builder
        dataptr = gep!(builder, data, [ConstantInt(0, context(mod)), ConstantInt(0, context(mod))])

        # Create the Julia object from `data` and include that in `init_fun`.
        position!(builder, jl_init_global_entry)
        gfunc_type = LLVM.FunctionType(julia_to_llvm(Cvoid),
                                       LLVMType[LLVM.PointerType(julia_to_llvm(Int8)),
                                                Iterators.repeated(LLVM.FunctionType(julia_to_llvm(Any)), nglobals)...])
        deserialize_globals_func = LLVM.Function(mod, "_deserialize_globals", gfunc_type)
        LLVM.linkage!(deserialize_globals_func, LLVM.API.LLVMExternalLinkage)
        for i in 1:nglobals
            # The following fix is to match the argument types which are an integer, not a %jl_value_t**.
            gptrs[i] = LLVM.ptrtoint!(builder, gptrs[i], julia_to_llvm(Csize_t))
        end
        LLVM.call!(builder, deserialize_globals_func, LLVM.Value[dataptr, gptrs...])
        ret!(builder)
    end
    tt = Tuple{Ptr{UInt8}, Iterators.repeated(Ptr{Any}, nglobals)...}
    deser_mod = irgen(deser_fun, tt, overdub = false)
    d = find_ccalls(deser_fun, tt)
    fix_ccalls!(deser_mod, d)
    # rename deserialization function to "_deserialize_globals"
    fun = first(filter(x -> LLVM.name(x) == "_deserialize_globals", functions(deser_mod)))[2]
    # LLVM.name!(fun, "_deserialize_globals")
    linkage!(fun, LLVM.API.LLVMExternalLinkage)
    # link into the main module
    LLVM.link!(mod, deser_mod)
    return
end
