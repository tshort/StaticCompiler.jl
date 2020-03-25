
struct LLVMNativeCode    # thin wrapper
    p::Ptr{Cvoid}
end


"""
Returns an LLVMNativeCode object for the function call `f` with TupleTypes `tt`.
"""
function raise_exception(insblock::BasicBlock, ex::Value)
end

# const jlctx = Ref{LLVM.Context}()

# function __init__()
#     jlctx[] = LLVM.Context(convert(LLVM.API.LLVMContextRef,
#                                    cglobal(:jl_LLVMContext, Nothing)))
# end

"""
    irgen(func, tt; 
          optimize = true, 
          optimize_llvm = true, 
          fix_globals = true, 
          overdub = true, 
          module_setup = (m) -> nothing)

Generates Julia IR targeted for static compilation.
`ccall` and `cglobal` uses have pointer references changed to symbols
meant to be linked with libjulia and other libraries.

`optimize` controls Julia-side optimization. `optimize_llvm` controls 
optimization on the LLVM side.

If `overdub == true` (the default), Cassette is used to swap out
`ccall`s with a tuple of library and symbol.

`module_setup` is an optional function to control setup of modules. It takes an LLVM
module as input.
"""
function irgen(@nospecialize(func), @nospecialize(tt); 
               optimize = true, 
               optimize_llvm = true, 
               fix_globals = true, 
               overdub = false, 
               module_setup = (m) -> nothing)

    # get the method instance
    isa(func, Core.Builtin) && error("function is not a generic function")
    world = typemax(UInt)
    gfunc = overdub ? (args...) -> Cassette.overdub(ctx, func, args...) : func
    meth = which(gfunc, tt)
    sig_tt = Tuple{typeof(gfunc), tt.parameters...}
    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
                      (Any, Any), sig_tt, meth.sig)::Core.SimpleVector
    meth = Base.func_for_method_checked(meth, ti, env)
    method_instance = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
                  (Any, Any, Any, UInt), meth, ti, env, world)

    # set-up the compiler interface
    params = Base.CodegenParams(track_allocations=false,
                                code_coverage=false,
                                static_alloc=false,
                                prefer_specsig=true,
                                gnu_pubnames=false)
    native_code = ccall(:jl_create_native, Ptr{Cvoid},
                        (Vector{Core.MethodInstance}, Base.CodegenParams),
                        [method_instance], params)
    @assert native_code != C_NULL
    llvm_mod_ref = ccall(:jl_get_llvm_module, LLVM.API.LLVMModuleRef,
                         (Ptr{Cvoid},), native_code)
    @assert llvm_mod_ref != C_NULL
    mod = LLVM.Module(llvm_mod_ref)

    for llvmf in functions(mod)
        startswith(LLVM.name(llvmf), "jfptr_") && unsafe_delete!(mod, llvmf)
        startswith(LLVM.name(llvmf), "julia_") && LLVM.linkage!(llvmf, LLVM.API.LLVMExternalLinkage)
    end

    definitions = Iterators.filter(f->!isdeclaration(f), collect(functions(mod)))

    for f in definitions
        if startswith(LLVM.name(f), string("julia_", nameof(gfunc), "_"))
            LLVM.name!(f, string(nameof(func)))
            linkage!(f, LLVM.API.LLVMExternalLinkage)
        end
    end

    d = find_ccalls(gfunc, tt)
    fix_ccalls!(mod, d)
    if fix_globals
        fix_globals!(mod)
    end
    if optimize_llvm
        optimize!(mod)
    end
    return mod
end


"""
    optimize!(mod::LLVM.Module)

Optimize the LLVM module `mod`. Crude for now.
Returns nothing.
"""
function optimize!(mod::LLVM.Module)

    for llvmf in functions(mod)
        startswith(LLVM.name(llvmf), "jfptr_") && unsafe_delete!(mod, llvmf)
        startswith(LLVM.name(llvmf), "julia_") && LLVM.linkage!(llvmf, LLVM.API.LLVMExternalLinkage)
    end
    # triple = "wasm32-unknown-unknown-wasm"
    # triple!(mod, triple)
    # datalayout!(mod, "e-m:e-p:32:32-i64:64-n32:64-S128")
    # LLVM.API.@apicall(:LLVMInitializeWebAssemblyTarget, Cvoid, ())
    # LLVM.API.@apicall(:LLVMInitializeWebAssemblyTargetMC, Cvoid, ())
    # LLVM.API.@apicall(:LLVMInitializeWebAssemblyTargetInfo, Cvoid, ())
    triple = "i686-pc-linux-gnu"
    tm = TargetMachine(Target(triple), triple)

    # ModulePassManager() do pm
    #     # add_library_info!(pm, triple(mod))
    #     add_transform_info!(pm, tm)
    #     ccall(:jl_add_optimization_passes, Cvoid,
    #           (LLVM.API.LLVMPassManagerRef, Cint, Cint),
    #           LLVM.ref(pm), Base.JLOptions().opt_level, 1)

    #     dead_arg_elimination!(pm)
    #     global_optimizer!(pm)
    #     global_dce!(pm)
    #     strip_dead_prototypes!(pm)

    #     run!(pm, mod)
    # end
    # mod

    ModulePassManager() do pm
        # initialize!(pm)
        ccall(:jl_add_optimization_passes, Cvoid,
                (LLVM.API.LLVMPassManagerRef, Cint, Cint),
                LLVM.ref(pm), Base.JLOptions().opt_level, #=lower_intrinsics=# 1)
                # LLVM.ref(pm), Base.JLOptions().opt_level, #=lower_intrinsics=# 0)
        run!(pm, mod)
    end
    ModulePassManager() do pm
        # initialize!(pm)

        # lower intrinsics
        # add!(pm, FunctionPass("LowerGCFrame", lower_gc_frame!))
        aggressive_dce!(pm) # remove dead uses of ptls
        # add!(pm, ModulePass("LowerPTLS", lower_ptls!))

        # the Julia GC lowering pass also has some clean-up that is required
        late_lower_gc_frame!(pm)

        run!(pm, mod)
    end


end

## lowering intrinsics

# lower object allocations to to PTX malloc
#
# this is a PoC implementation that is very simple: allocate, and never free. it also runs
# _before_ Julia's GC lowering passes, so we don't get to use the results of its analyses.
# when we ever implement a more potent GC, we will need those results, but the relevant pass
# is currently very architecture/CPU specific: hard-coded pool sizes, TLS references, etc.
# such IR is hard to clean-up, so we probably will need to have the GC lowering pass emit
# lower-level intrinsics which then can be lowered to architecture-specific code.
function lower_gc_frame!(fun::LLVM.Function)
    mod = LLVM.parent(fun)
    changed = false

    # plain alloc
    if haskey(functions(mod), "julia.gc_alloc_obj")
        alloc_obj = functions(mod)["julia.gc_alloc_obj"]
        alloc_obj_ft = eltype(llvmtype(alloc_obj))
        T_prjlvalue = return_type(alloc_obj_ft)
        T_pjlvalue = convert(LLVMType, Any, true)

        for use in uses(alloc_obj)
            call = user(use)::LLVM.CallInst

            # decode the call
            ops = collect(operands(call))
            sz = ops[2]

            # replace with PTX alloc_obj
            let builder = Builder(JuliaContext())
                position!(builder, call)
                ptr = call!(builder, Runtime.get(:gc_pool_alloc), [sz])
                replace_uses!(call, ptr)
                dispose(builder)
            end

            unsafe_delete!(LLVM.parent(call), call)

            changed = true
        end

    end

    # we don't care about write barriers
    if haskey(functions(mod), "julia.write_barrier")
        barrier = functions(mod)["julia.write_barrier"]

        for use in uses(barrier)
            call = user(use)::LLVM.CallInst
            unsafe_delete!(LLVM.parent(call), call)
            changed = true
        end

    end

    return changed
end

# lower the `julia.ptls_states` intrinsic by removing it, since it is GPU incompatible.
#
# this assumes and checks that the TLS is unused, which should be the case for most GPU code
# after lowering the GC intrinsics to TLS-less code and having run DCE.
#
# TODO: maybe don't have Julia emit actual uses of the TLS, but use intrinsics instead,
#       making it easier to remove or reimplement that functionality here.
function lower_ptls!(mod::LLVM.Module)
    changed = false

    if haskey(functions(mod), "julia.ptls_states")
        ptls_getter = functions(mod)["julia.ptls_states"]

        for use in uses(ptls_getter)
            val = user(use)
            if !isempty(uses(val))
                error("Thread local storage is not implemented")
            end
            unsafe_delete!(LLVM.parent(val), val)
            changed = true
        end

     end

    return changed
end


function write_object(mod::LLVM.Module, path)
    host_triple = triple()
    host_t = Target(host_triple)
    TargetMachine(host_t, host_triple, "", "", LLVM.API.LLVMCodeGenLevelDefault, LLVM.API.LLVMRelocPIC) do tm
        emit(tm, mod, LLVM.API.LLVMObjectFile, path)
    end
end


# @generated function malloc(sz::Csize_t)
#     T_pint8 = LLVM.PointerType(LLVM.Int8Type(JuliaContext()))
#     T_size = convert(LLVMType, Csize_t)
#     T_ptr = convert(LLVMType, Ptr{Cvoid})

#     # create function
#     llvm_f, _ = create_function(T_ptr, [T_size])
#     mod = LLVM.parent(llvm_f)

#     # get the intrinsic
#     # NOTE: LLVM doesn't have void*, Clang uses i8* for malloc too
#     intr = LLVM.Function(mod, "malloc", LLVM.FunctionType(T_pint8, [T_size]))
#     # should we attach some metadata here? julia.gc_alloc_obj has the following:
#     #let attrs = function_attributes(intr)
#     #    AllocSizeNumElemsNotPresent = reinterpret(Cuint, Cint(-1))
#     #    packed_allocsize = Int64(1) << 32 | AllocSizeNumElemsNotPresent
#     #    push!(attrs, EnumAttribute("allocsize", packed_allocsize, JuliaContext()))
#     #end
#     #let attrs = return_attributes(intr)
#     #    push!(attrs, EnumAttribute("noalias", 0, JuliaContext()))
#     #    push!(attrs, EnumAttribute("nonnull", 0, JuliaContext()))
#     #end

#     # generate IR
#     Builder(JuliaContext()) do builder
#         entry = BasicBlock(llvm_f, "entry", JuliaContext())
#         position!(builder, entry)

#         ptr = call!(builder, intr, [parameters(llvm_f)[1]])

#         jlptr = ptrtoint!(builder, ptr, T_ptr)

#         ret!(builder, jlptr)
#     end

#     call_function(llvm_f, Ptr{Cvoid}, Tuple{Csize_t}, :((sz,)))
# end