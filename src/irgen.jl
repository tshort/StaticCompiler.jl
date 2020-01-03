
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
    irgen(func, tt; optimize = true, overdub = true, module_setup = (m) -> nothing)

Generates Julia IR targeted for static compilation.
`ccall` and `cglobal` uses have pointer references changed to symbols
meant to be linked with libjulia and other libraries.
If `overdub == true` (the default), Cassette is used to swap out
`ccall`s with a tuple of library and symbol.
`module_setup` is an optional function to control setup of modules. It takes an LLVM
module as input.
"""
function irgen(@nospecialize(func), @nospecialize(tt); optimize = true, overdub = true, module_setup = (m) -> nothing)
    # get the method instance
    isa(func, Core.Builtin) && error("function is not a generic function")
    world = typemax(UInt)
    gfunc = overdub ? (args...) -> Cassette.overdub(ctx, func, args...) : func
    meth = which(gfunc, tt)
    sig_tt = Tuple{typeof(gfunc), tt.parameters...}
    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
                      (Any, Any), sig_tt, meth.sig)::Core.SimpleVector

    if VERSION >= v"1.2.0-DEV.320"
        meth = Base.func_for_method_checked(meth, ti, env)
    else
        meth = Base.func_for_method_checked(meth, ti)
    end

    linfo = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
                  (Any, Any, Any, UInt), meth, ti, env, world)

    current_method = nothing
    last_method_instance = nothing
    call_stack = Vector{Core.MethodInstance}()
    global method_map = Dict{String,Core.MethodInstance}()
    global dependencies = MultiDict{Core.MethodInstance,LLVM.Function}()
    # set-up the compiler interface
    function hook_module_setup(ref::Ptr{Cvoid})
        ref = convert(LLVM.API.LLVMModuleRef, ref)
        module_setup(LLVM.Module(ref))
        println("module setup")
    end
    function hook_raise_exception(insblock::Ptr{Cvoid}, ex::Ptr{Cvoid})
        insblock = convert(LLVM.API.LLVMValueRef, insblock)
        ex = convert(LLVM.API.LLVMValueRef, ex)
        raise_exception(BasicBlock(insblock), Value(ex))
    end
    function postprocess(ir)
        # get rid of jfptr wrappers
        for llvmf in functions(ir)
            startswith(LLVM.name(llvmf), "jfptr_") && unsafe_delete!(ir, llvmf)
        end

        return
    end
    function hook_module_activation(ref::Ptr{Cvoid})
        println("mod activation")
        ref = convert(LLVM.API.LLVMModuleRef, ref)
        global ir = LLVM.Module(ref)
        postprocess(ir)

        # find the function that this module defines
        llvmfs = filter(llvmf -> !isdeclaration(llvmf) &&
                                 linkage(llvmf) == LLVM.API.LLVMExternalLinkage,
                        collect(functions(ir)))
        llvmf = nothing
        if length(llvmfs) == 1
            llvmf = first(llvmfs)
        elseif length(llvmfs) > 1
            llvmfs = filter!(llvmf -> startswith(LLVM.name(llvmf), "julia_"), llvmfs)
            if length(llvmfs) == 1
                llvmf = first(llvmfs)
            end
        end
        @show name(llvmf)
        insert!(dependencies, last_method_instance, llvmf)
        method_map[name(llvmf)] = current_method
    end
    function hook_emit_function(method_instance, code, world)
        @show method_instance
        push!(call_stack, method_instance)
        # @show code
    end
    function hook_emitted_function(method, code, world)
        @show current_method = method
        last_method_instance = pop!(call_stack)
        # @show code
        # dump(method, maxdepth=2)
        # global mymeth = method
    end
    
    params = Base.CodegenParams(cached=false,
                                track_allocations=false,
                                code_coverage=false,
                                static_alloc=false,
                                prefer_specsig=true,
                                module_setup=hook_module_setup,
                                module_activation=hook_module_activation,
                                raise_exception=hook_raise_exception,
                                emit_function=hook_emit_function,
                                emitted_function=hook_emitted_function,
                                )

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
    cache = Dict{String,String}()
    for called_method_instance in keys(dependencies)
        llvmfs = dependencies[called_method_instance]

        # link the first module
        llvmf = popfirst!(llvmfs)
        llvmfn = LLVM.name(llvmf)
        link!(mod, LLVM.parent(llvmf))
        # process subsequent duplicate modules
        for dup_llvmf in llvmfs
            if Base.JLOptions().debug_level >= 2
                # link them too, to ensure accurate backtrace reconstruction
                link!(mod, LLVM.parent(dup_llvmf))
            else
                # don't link them, but note the called function name in a cache
                dup_llvmfn = LLVM.name(dup_llvmf)
                cache[dup_llvmfn] = llvmfn
            end
        end
    end
    # resolve function declarations with cached entries
    for llvmf in filter(isdeclaration, collect(functions(mod)))
        llvmfn = LLVM.name(llvmf)
        if haskey(cache, llvmfn)
            def_llvmfn = cache[llvmfn]
            replace_uses!(llvmf, functions(mod)[def_llvmfn])
            unsafe_delete!(LLVM.parent(llvmf), llvmf)
        end
    end
    # rename functions to something easier to decipher
    # especially helps with overdubbed functions
    for (fname, mi) in method_map
        @show fname
        id = split(fname, "_")[end]
        @show basename = mi.def.name
        args = join(collect(mi.specTypes.parameters)[2:end], "_")
        if basename == :overdub  # special handling for Cassette
            basename = mi.specTypes.parameters[3]
            args = join(collect(mi.specTypes.parameters)[4:end], "_")
        end
        @show newname = join([basename, args, id], "_")
        if haskey(functions(mod), fname)
            # name!(functions(mod)[fname], newname)
        end
    end

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
