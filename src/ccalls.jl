
"""
    find_ccalls(f, tt)

Returns a `Dict` mapping function addresses to symbol names for all `ccall`s and
`cglobal`s called from the method. This descends into other invocations
within the method.
"""
find_ccalls(@nospecialize(f), @nospecialize(tt)) = find_ccalls(reflect(f, tt))

function find_ccalls(ref::Reflection)
    result = Dict{Ptr{Nothing}, Symbol}()
    idx = VERSION > v"1.2" ? 5 : 4
    foreigncalls = TypedCodeUtils.filter((c) -> lookthrough((c) -> c.head === :foreigncall && !(c.args[idx] isa QuoteNode && c.args[idx].value == :llvmcall), c), ref.CI.code)
    # foreigncalls = TypedCodeUtils.filter((c) -> lookthrough((c) -> c.head === :foreigncall, c), ref.CI.code)
    for fc in foreigncalls
        sym = getsym(fc[2].args[1])
        address = eval(:(cglobal($(sym))))
        result[address] = Symbol(sym isa Tuple ? sym[1] : sym.value)
    end
    cglobals = TypedCodeUtils.filter((c) -> lookthrough(c -> c.head === :call && iscglobal(c.args[1]), c), ref.CI.code)
    for fc in cglobals
        sym = getsym(fc[2].args[2])
        address = eval(:(cglobal($(sym))))
        result[address] = Symbol(sym isa Tuple ? sym[1] : sym.value)
    end
    invokes = TypedCodeUtils.filter((c) -> lookthrough(identify_invoke, c), ref.CI.code)
    invokes = map((arg) -> process_invoke(DefaultConsumer(), ref, arg...), invokes)
    for fi in invokes
        canreflect(fi) || continue
        merge!(result, find_ccalls(reflect(fi)))
    end
    return result
end

getsym(x) = x
getsym(x::String) = QuoteNode(Symbol(x))
getsym(x::QuoteNode) = x
getsym(x::Expr) = eval.((x.args[2], x.args[3]))

iscglobal(x) = x == cglobal || x isa GlobalRef && x.name == :cglobal


"""
    fix_ccalls!(mod::LLVM.Module, d)

Replace function addresses with symbol names in `mod`. The symbol names are
meant to be linked to `libjulia` or other libraries.
`d` is a `Dict` mapping a function address to symbol name for `ccall`s.
"""
function fix_ccalls!(mod::LLVM.Module, d)
    for fun in functions(mod), blk in blocks(fun), instr in instructions(blk)
        if instr isa LLVM.CallInst
            dest = called_value(instr)
            if dest isa ConstantExpr && occursin("inttoptr", string(dest))
                argtypes = [llvmtype(op) for op in operands(instr)]
                nargs = length(parameters(eltype(argtypes[end])))
                # num_extra_args = 1 + length(collect(eachmatch(r"jl_roots", string(instr))))
                ptr = Ptr{Cvoid}(convert(Int, first(operands(dest))))
                if haskey(d, ptr)
                    s = string(d[ptr])
                    if s in (name(g) for g in functions(mod))
                        @show functions(mod)[s]
                        replace_uses!(dest, functions(mod)[s])
                    else
                        newdest = LLVM.Function(mod, s, LLVM.FunctionType(llvmtype(instr), argtypes[1:nargs]))
                        LLVM.linkage!(newdest, LLVM.API.LLVMExternalLinkage)
                        replace_uses!(dest, newdest)
                    end
                end
            end
        elseif instr isa LLVM.LoadInst && occursin("inttoptr", string(instr))
            for op in operands(instr)
                lastop = op
                if occursin("inttoptr", string(op))
                    if occursin("addrspacecast", string(op)) || occursin("getelementptr", string(op))
                        @show op = first(operands(op))
                    end
                    first(operands(op)) isa LLVM.ConstantInt || continue
                    ptr = Ptr{Cvoid}(convert(Int, first(operands(op))))
                    if haskey(d, ptr)
                        s = string(d[ptr])
                        if s in (name(g) for g in globals(mod))
                            newdest = globals(mod)[s]
                            if addrspace(llvmtype(instr)) != addrspace(llvmtype(newdest))
                                newdest = ConstantExpr(LLVM.API.LLVMConstAddrSpaceCast(LLVM.ref(newdest), LLVM.ref(llvmtype(instr))))
                            end
                            replace_uses!(op, newdest)
                        else
                            newdest = GlobalVariable(mod, llvmtype(instr), s)
                            LLVM.linkage!(newdest, LLVM.API.LLVMExternalLinkage)
                            replace_uses!(op, newdest)
                        end
                    end
                end
            end
        end
    end
end
