
struct LLVMNativeCode    # thin wrapper
    p::Ptr{Cvoid}
end

function xlinfo(f, tt)
    # get the method instance
    world = typemax(UInt)
    g = (args...) -> Cassette.overdub(ctx, f, args...)
    meth = which(g, tt)
    sig_tt = Tuple{typeof(g), tt.parameters...}
    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
                      (Any, Any), sig_tt, meth.sig)::Core.SimpleVector

    if VERSION >= v"1.2.0-DEV.320"
        meth = Base.func_for_method_checked(meth, ti, env)
    else
        meth = Base.func_for_method_checked(meth, ti)
    end
    
    return ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
                 (Any, Any, Any, UInt), meth, ti, env, world)
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
    irgen(func, tt; optimize = true, overdub = true)

Generates Julia IR targeted for static compilation.
`ccall` and `cglobal` uses have pointer references changed to symbols
meant to be linked with libjulia and other libraries.
If `overdub == true` (the default), Cassette is used to swap out 
`ccall`s with a tuple of library and symbol.
"""
function irgen(@nospecialize(func), @nospecialize(tt); optimize = true, overdub = true)
    # get the method instance
    isa(func, Core.Builtin) && error("function is not a generic function")
    world = typemax(UInt)
    gfunc = overdub ? (args...) -> Cassette.overdub(ctx, func, args...) : func
    meth = which(gfunc, tt)
    sig_tt = Tuple{typeof(gfunc), tt.parameters...}
    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
                      (Any, Any), sig_tt, meth.sig)::Core.SimpleVector
    meth = Base.func_for_method_checked(meth, ti)
    linfo = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
                  (Any, Any, Any, UInt), meth, ti, env, world)

    # set-up the compiler interface
    function hook_module_setup(ref::Ptr{Cvoid})
        ref = convert(LLVM.API.LLVMModuleRef, ref)
        module_setup(LLVM.Module(ref))
    end
    function hook_raise_exception(insblock::Ptr{Cvoid}, ex::Ptr{Cvoid})
        insblock = convert(LLVM.API.LLVMValueRef, insblock)
        ex = convert(LLVM.API.LLVMValueRef, ex)
        raise_exception(BasicBlock(insblock), Value(ex))
    end
    dependencies = Vector{LLVM.Module}()
    function hook_module_activation(ref::Ptr{Cvoid})
        ref = convert(LLVM.API.LLVMModuleRef, ref)
        push!(dependencies, LLVM.Module(ref))
    end
    params = Base.CodegenParams(cached=false,
                                track_allocations=false,
                                code_coverage=false,
                                static_alloc=false,
                                prefer_specsig=true,
                                module_setup=hook_module_setup,
                                module_activation=hook_module_activation,
                                raise_exception=hook_raise_exception)

    # get the code
    global mod = let
        ref = ccall(:jl_get_llvmf_defn, LLVM.API.LLVMValueRef,
                    (Any, UInt, Bool, Bool, Base.CodegenParams),
                    linfo, world, #=wrapper=#false, #=optimize=#false, params)
        if ref == C_NULL
            # error(jlctx[], "the Julia compiler could not generate LLVM IR")
        end

        llvmf = LLVM.Function(ref)
        LLVM.parent(llvmf)
    end

    # the main module should contain a single jfptr_ function definition,
    # e.g. jlcall_kernel_vadd_62977

    # definitions = filter(f->!isdeclaration(f), functions(mod))
    definitions = Iterators.filter(f->!isdeclaration(f), collect(functions(mod)))
    # definitions = collect(functions(mod))
    wrapper = let
        fs = collect(Iterators.filter(f->startswith(LLVM.name(f), "jfptr_"), definitions))
        @assert length(fs) == 1
        fs[1]
    end

    # the jlcall wrapper function should point us to the actual entry-point,
    # e.g. julia_kernel_vadd_62984
   entry_tag = let
       m = match(r"jfptr_(.+)_\d+", LLVM.name(wrapper))
       @assert m != nothing
       m.captures[1]
   end
   unsafe_delete!(mod, wrapper)
   entry = let
       re = Regex("julia_$(entry_tag)_\\d+")
       llvmcall_re = Regex("julia_$(entry_tag)_\\d+u\\d+")
       fs = collect(Iterators.filter(f->occursin(re, LLVM.name(f)) &&
                              !occursin(llvmcall_re, LLVM.name(f)), definitions))
       if length(fs) != 1
           compiler_error(func, tt, cap, "could not find single entry-point";
                          entry=>entry_tag, available=>[LLVM.name.(definitions)])
       end
       fs[1]
   end

   LLVM.name!(entry, string(nameof(func)))

    # link in dependent modules
    link!.(Ref(mod), dependencies)

    # clean up incompatibilities
#    for llvmf in functions(mod)
#        # only occurs in debug builds
#        delete!(function_attributes(llvmf), EnumAttribute("sspreq", 0, jlctx[]))
#
#        # make function names safe for ptxas
#        # (LLVM ought to do this, see eg. D17738 and D19126), but fails
#        # TODO: fix all globals?
#        llvmfn = LLVM.name(llvmf)
#        if !isdeclaration(llvmf)
#            llvmfn′ = safe_fn(llvmf)
#            if llvmfn != llvmfn′
#                LLVM.name!(llvmf, llvmfn′)
#            end
#        end
#    end
    d = find_ccalls(gfunc, tt)
    fix_ccalls!(mod, d)
    #@show mod
    mod
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

