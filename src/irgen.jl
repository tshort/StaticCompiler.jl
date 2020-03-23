
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

    ModulePassManager() do pm
        # add_library_info!(pm, triple(mod))
        add_transform_info!(pm, tm)
        ccall(:jl_add_optimization_passes, Cvoid,
              (LLVM.API.LLVMPassManagerRef, Cint, Cint),
              LLVM.ref(pm), Base.JLOptions().opt_level, 1)

        dead_arg_elimination!(pm)
        global_optimizer!(pm)
        global_dce!(pm)
        strip_dead_prototypes!(pm)

        run!(pm, mod)
    end
    mod
end

function write_object(mod::LLVM.Module, path)
    host_triple = triple()
    host_t = Target(host_triple)
    TargetMachine(host_t, host_triple, "", "", LLVM.API.LLVMCodeGenLevelDefault, LLVM.API.LLVMRelocPIC) do tm
        emit(tm, mod, LLVM.API.LLVMObjectFile, path)
    end
end
