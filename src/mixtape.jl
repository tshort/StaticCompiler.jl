
using LLVM
using LLVM.Interop
using MacroTools: @capture, 
                  postwalk, 
                  rmlines, 
                  unblock
using CodeInfoTools
using CodeInfoTools: resolve
using Core: MethodInstance, 
            CodeInstance,
            CodeInfo
using Core.Compiler: WorldView,
                     NativeInterpreter,
                     InferenceResult,
                     coverage_enabled,
                     copy_exprargs,
                     convert_to_ircode,
                     slot2reg,
                     compact!,
                     ssa_inlining_pass!,
#                     getfield_elim_pass!,
                     adce_pass!,
                     type_lift_pass!,
                     verify_ir,
                     verify_linetable

using GPUCompiler: cached_compilation, 
                   FunctionSpec

import GPUCompiler: AbstractCompilerTarget,
                    NativeCompilerTarget,
                    AbstractCompilerParams,
                    CompilerJob,
                    julia_datalayout,
                    llvm_machine,
                    llvm_triple

import Core.Compiler: InferenceState,
                      InferenceParams,
                      AbstractInterpreter,
                      OptimizationParams,
                      InferenceState,
                      OptimizationState,
                      get_world_counter,
                      get_inference_cache,
                      lock_mi_inference,
                      unlock_mi_inference,
                      code_cache,
                      optimize,
                      may_optimize,
                      may_compress,
                      may_discard_trees,
                      add_remark!

#####
##### Exports
#####

export CompilationContext, 
       NoContext,
       allow, 
       transform 

#####
##### Compilation context
#####

# User-extended context allows parametrization of the pipeline through
# our subtype of AbstractInterpreter
abstract type CompilationContext end

struct NoContext <: CompilationContext end

@doc(
"""
    abstract type CompilationContext end

Parametrize the Mixtape pipeline by inheriting from `CompilationContext`. Similar to the context objects in [Cassette.jl](https://julia.mit.edu/Cassette.jl/stable/contextualdispatch.html). By using the interface methods [`transform`](@ref) and [`optimize!`](@ref) -- the user can control different parts of the compilation pipeline.
""", CompilationContext)

transform(ctx::CompilationContext, b) = b
transform(ctx::CompilationContext, b, sig) = transform(ctx, b)

@doc(
"""
    transform(ctx::CompilationContext, b::Core.CodeInfo)::Core.CodeInfo
    transform(ctx::CompilationContext, b::Core.CodeInfo, sig::Tuple)::Core.CodeInfo

User-defined transform which operates on lowered `Core.CodeInfo`. There's two versions: (1) ignores the signature of the current method body under consideration and (2) provides the signature as `sig`.

Transforms might typically follow a simple "swap" format using `CodeInfoTools.Builder`:

```julia
function transform(::MyCtx, src)
    b = CodeInfoTools.Builder(b)
    for (k, st) in b
        b[k] = swap(st))
    end
    return CodeInfoTools.finish(b)
end
```

but more advanced formats are possible. For further utilities, please see [CodeInfoTools.jl](https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl).
""", transform)

optimize!(ctx::CompilationContext, b) = julia_passes!(b)

@doc(
"""
    optimize!(ctx::CompilationContext, b::OptimizationBundle)::Core.Compiler.IRCode

User-defined transform which operates on inferred IR provided by an [`OptimizationBundle`](@ref) instance.

The fallback implementation is:
```julia
optimize!(ctx::CompilationContext, b::OptimizationBundle) = julia_passes!(b)
```
which runs a set of standard (and required) Julia passes to the lowered and inferred `Core.Compiler.IRCode`.

!!! warning
    If you overload this method, _you are responsible for the optimization pass_! This means that you should know what you're doing (in general), and you will likely also want to call `julia_passes!` yourself. Be aware of this -- or else you'll receive verification errors on `Core.Compiler.IRCode`.
""", optimize!)

allow(f::C, args...) where {C <: CompilationContext} = false
function allow(ctx::CompilationContext, mod::Module, fn, args...)
    return allow(ctx, mod) || allow(ctx, fn, args...)
end

@doc(
"""
    allow(f::CompilationContext, args...)::Bool

Determines whether the user-defined [`transform`](@ref) and [`optimize!`](@ref) are allowed to look at a lowered `Core.CodeInfo` or `Core.Compiler.IRCode` instance.

The user is allowed to greenlight modules:

```julia
allow(::MyCtx, m::Module) == m == SomeModule
```

or even specific signatures

```julia
allow(::MyCtx, fn::typeof(rand), args...) = true
```
""", allow)

#####
##### Utilities
#####

function get_methodinstance(@nospecialize(sig))
    ms = Base._methods_by_ftype(sig, 1, Base.get_world_counter())
    @assert length(ms) == 1
    m = ms[1]
    mi = ccall(:jl_specializations_get_linfo,
               Ref{MethodInstance}, (Any, Any, Any),
               m[3], m[1], m[2])
    return mi
end

function infer(interp, fn, t::Type{T}) where T <: Tuple
    mi = get_methodinstance(Tuple{typeof(fn), t.parameters...})
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi)
    @assert(haskey(interp.code, mi))
    ci = getindex(interp.code, mi)
    if ci !== nothing && ci.inferred === nothing
        ci.inferred = src
    end
    return mi
end

#####
##### Interpreter
#####

# Based on: https://github.com/Keno/Compiler3.jl/blob/master/exploration/static.jl

# Holds its own cache.
struct StaticInterpreter{I, C} <: AbstractInterpreter
    code::Dict{MethodInstance, CodeInstance}
    inner::I
    messages::Vector{Tuple{MethodInstance, Int, String}}
    optimize::Bool
    ctx::C
end

function StaticInterpreter(; ctx = NoContext(), opt = false)
    return StaticInterpreter(Dict{MethodInstance, CodeInstance}(),
                             NativeInterpreter(), 
                             Tuple{MethodInstance, Int, String}[],
                             opt,
                             ctx)
end

InferenceParams(si::StaticInterpreter) = InferenceParams(si.inner)
OptimizationParams(si::StaticInterpreter) = OptimizationParams(si.inner)
get_world_counter(si::StaticInterpreter) = get_world_counter(si.inner)
get_inference_cache(si::StaticInterpreter) = get_inference_cache(si.inner)
lock_mi_inference(si::StaticInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(si::StaticInterpreter, mi::MethodInstance) = nothing
code_cache(si::StaticInterpreter) = si.code
Core.Compiler.get(a::Dict, b, c) = Base.get(a, b, c)
Core.Compiler.get(a::WorldView{<:Dict}, b, c) = Base.get(a.cache,b,c)
Core.Compiler.haskey(a::Dict, b) = Base.haskey(a, b)
Core.Compiler.haskey(a::WorldView{<:Dict}, b) =
Core.Compiler.haskey(a.cache, b)
Core.Compiler.setindex!(a::Dict, b, c) = setindex!(a, b, c)
Core.Compiler.may_optimize(si::StaticInterpreter) = si.optimize
Core.Compiler.may_compress(si::StaticInterpreter) = false
Core.Compiler.may_discard_trees(si::StaticInterpreter) = false
@static if VERSION >= v"1.7.0-DEV.577"
    Core.Compiler.verbose_stmt_info(interp::StaticInterpreter) = false
end
function Core.Compiler.add_remark!(si::StaticInterpreter, sv::InferenceState, msg)
    push!(si.messages, (sv.linfo, sv.currpc, msg))
end

#####
##### Pre-inference
#####

function resolve_generic(a)
    if a isa Type && a <: Function && isdefined(a, :instance)
        return a.instance
    else
        return resolve(a)
    end
end

function custom_pass!(interp::StaticInterpreter, result::InferenceResult, mi::Core.MethodInstance, src)
    src === nothing && return src
    mi.specTypes isa UnionAll && return src
    sig = Tuple(mi.specTypes.parameters)
    as = map(resolve_generic, sig)
    if allow(interp.ctx, mi.def.module, as...)
        src = transform(interp.ctx, src, sig)
    end
    return src
end

function InferenceState(result::InferenceResult, cached::Bool, interp::StaticInterpreter)
    src = Core.Compiler.retrieve_code_info(result.linfo)
    mi = result.linfo
    src = custom_pass!(interp, result, mi, src)
    src === nothing && return nothing
    Core.Compiler.validate_code_in_debug_mode(result.linfo, src, "lowered")
    return InferenceState(result, src, cached, interp)
end

#####
##### Julia optimization pipeline
#####

@static if VERSION >= v"1.7.0-DEV.662"
    using Core.Compiler: finish as _finish
else
    function _finish(interp::AbstractInterpreter, 
            opt::OptimizationState,
            params::OptimizationParams, ir, @nospecialize(result))
        return Core.Compiler.finish(opt, params, ir, result)
    end
end

struct OptimizationBundle
    ir::Core.Compiler.IRCode
    sv::OptimizationState
end
get_ir(b::OptimizationBundle) = b.ir
get_state(b::OptimizationBundle) = b.sv

@doc(
"""
    struct OptimizationBundle
        ir::Core.Compiler.IRCode
        sv::OptimizationState
    end
    get_ir(b::OptimizationBundle) = b.ir
    get_state(b::OptimizationBundle) = b.sv

Object which holds inferred `ir::Core.Compiler.IRCode` and a `Core.Compiler.OptimizationState`. Provided to the user through [`optimize!`](@ref), so that the user may plug in their own optimizations.
""", OptimizationBundle)

function julia_passes!(ir::Core.Compiler.IRCode, ci::CodeInfo, 
        sv::OptimizationState)
    ir = compact!(ir)
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
    ir = compact!(ir)
    # ir = getfield_elim_pass!(ir)
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    return ir
end

julia_passes!(b::OptimizationBundle) = julia_passes!(b.ir, b.sv.src, b.sv)

# function optimize(interp::StaticInterpreter, opt::OptimizationState,
#         params::OptimizationParams, result::InferenceResult)
#         #params::OptimizationParams, @nospecialize(result))
#     nargs = Int(opt.nargs) - 1
#     mi = opt.linfo
#     meth = mi.def
#     preserve_coverage = coverage_enabled(opt.mod)
#     ir = convert_to_ircode(opt.src, copy_exprargs(opt.src.code), preserve_coverage, nargs, opt)
#     ir = slot2reg(ir, opt.src, nargs, opt)
#     b = OptimizationBundle(ir, opt)
#     ir :: Core.Compiler.IRCode = optimize!(interp.ctx, b)
#     verify_ir(ir)
#     verify_linetable(ir.linetable)
#     return _finish(interp, opt, params, ir, result)
# end

#####
##### FunctionGraph
#####

abstract type FunctionGraph end

struct StaticSubGraph <: FunctionGraph
    code::Dict{MethodInstance, Any}
    instances::Vector{MethodInstance}
    entry::MethodInstance
end

entrypoint(ssg::StaticSubGraph) = ssg.entry

get_codeinstance(ssg::StaticSubGraph, mi::MethodInstance) = getindex(ssg.code, mi)

function get_codeinfo(code::Core.CodeInstance)
    ci = code.inferred
    if ci isa Vector{UInt8}
        return Core.Compiler._uncompressed_ir(code, ci)
    else
        return ci
    end
end

function get_codeinfo(graph::StaticSubGraph, 
        cursor::MethodInstance)
    return get_codeinfo(get_codeinstance(graph, cursor))
end

function analyze(@nospecialize(f), tt::Type{T}; 
        ctx = NoContext(), opt = false) where T <: Tuple
    si = StaticInterpreter(; ctx = ctx, opt = opt)
    mi = infer(si, f, tt)
    si, StaticSubGraph(si.code, collect(keys(si.code)), mi)
end

#####
##### LLVM optimization pipeline
#####

function optimize!(tm, mod::LLVM.Module)
    ModulePassManager() do pm
        add_library_info!(pm, triple(mod))
        add_transform_info!(pm, tm)
        propagate_julia_addrsp!(pm)
        scoped_no_alias_aa!(pm)
        type_based_alias_analysis!(pm)
        basic_alias_analysis!(pm)
        cfgsimplification!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        mem_cpy_opt!(pm)
        always_inliner!(pm)
        alloc_opt!(pm)
        instruction_combining!(pm)
        cfgsimplification!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        instruction_combining!(pm)
        jump_threading!(pm)
        instruction_combining!(pm)
        reassociate!(pm)
        early_cse!(pm)
        alloc_opt!(pm)
        loop_idiom!(pm)
        loop_rotate!(pm)
        lower_simdloop!(pm)
        licm!(pm)
        loop_unswitch!(pm)
        instruction_combining!(pm)
        ind_var_simplify!(pm)
        loop_deletion!(pm)
        alloc_opt!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        instruction_combining!(pm)
        gvn!(pm)
        mem_cpy_opt!(pm)
        sccp!(pm)
        instruction_combining!(pm)
        jump_threading!(pm)
        dead_store_elimination!(pm)
        alloc_opt!(pm)
        cfgsimplification!(pm)
        loop_idiom!(pm)
        loop_deletion!(pm)
        jump_threading!(pm)
        aggressive_dce!(pm)
        instruction_combining!(pm)
        barrier_noop!(pm)
        lower_exc_handlers!(pm)
        gc_invariant_verifier!(pm, false)
        late_lower_gc_frame!(pm)
        final_lower_gc!(pm)
        lower_ptls!(pm, #=dump_native=# false)
        cfgsimplification!(pm)
        instruction_combining!(pm) # Extra for Enzyme
        run!(pm, mod)
    end
end

#####
##### Entry codegen with cached compilation
#####

# Interpreter holds the cache.
function cache_lookup(si::StaticInterpreter, mi::MethodInstance,
        min_world, max_world)
    Base.get(si.code, mi, nothing)
end

# Mostly from GPUCompiler. 
# In future, try to upstream any requires changes.
function codegen(job::CompilerJob)
    f = job.source.f
    tt = job.source.tt
    opt = job.params.opt
    si, ssg = analyze(f, tt; 
                      ctx = job.params.ctx, opt = opt) # Populate local cache.
    world = get_world_counter(si)
    λ_lookup = (mi, min, max) -> cache_lookup(si, mi, min, max)
    lookup_cb = @cfunction($λ_lookup, Any, (Any, UInt, UInt))
    params = Base.CodegenParams(; 
                                track_allocations = false, 
                                code_coverage     = false,
                                prefer_specsig    = true,
                                gnu_pubnames      = false,
                                lookup            = Base.unsafe_convert(Ptr{Nothing}, lookup_cb))

    GC.@preserve lookup_cb begin
        native_code = if VERSION >= v"1.8.0-DEV.661"
            ccall(:jl_create_native, Ptr{Cvoid},
                  (Vector{MethodInstance}, Ptr{Base.CodegenParams}, Cint),
                  [ssg.entry], Ref(params), #=extern policy=# 1)
        else
            ccall(:jl_create_native, Ptr{Cvoid},
                  (Vector{MethodInstance}, Base.CodegenParams, Cint),
                  [ssg.entry], params, #=extern policy=# 1)
        end
        # native_code = ccall(:jl_create_native, 
        #                     Ptr{Cvoid},
        #                     (Vector{MethodInstance}, 
        #                      Base.CodegenParams, Cint), 
        #                     [ssg.entry],
        #                     params, 1) # = extern policy = #
        @assert native_code != C_NULL
        llvm_mod_ref = ccall(:jl_get_llvm_module, 
                             LLVM.API.LLVMModuleRef, 
                             (Ptr{Cvoid},),
                             native_code)
        @assert llvm_mod_ref != C_NULL
        llvm_mod = LLVM.Module(llvm_mod_ref)
    end
    code = cache_lookup(si, ssg.entry, world, world)
    llvm_func_idx = Ref{Int32}(-1)
    llvm_specfunc_idx = Ref{Int32}(-1)
    ccall(:jl_get_function_id, 
          Nothing, 
          (Ptr{Cvoid}, Any, Ptr{Int32}, Ptr{Int32}),
          native_code, code, llvm_func_idx, llvm_specfunc_idx)
    @assert llvm_specfunc_idx[] != -1
    @assert llvm_func_idx[] != -1
    llvm_func_ref = ccall(:jl_get_llvm_function, 
                          LLVM.API.LLVMValueRef,
                          (Ptr{Cvoid}, UInt32), 
                          native_code, 
                          llvm_func_idx[] - 1)
    @assert llvm_func_ref != C_NULL
    llvm_func = LLVM.Function(llvm_func_ref)
    llvm_specfunc_ref = ccall(:jl_get_llvm_function, 
                              LLVM.API.LLVMValueRef,
                              (Ptr{Cvoid}, UInt32), 
                              native_code, 
                              llvm_specfunc_idx[] - 1)
    @assert llvm_specfunc_ref != C_NULL
    llvm_specfunc = LLVM.Function(llvm_specfunc_ref)
    triple!(llvm_mod, llvm_triple(job.target))
    if julia_datalayout(job.target) !== nothing
        datalayout!(llvm_mod, julia_datalayout(job.target))
    end
    # rename and process the entry point
    #             LLVM.name(LLVM.Function(llvm_func_ref))
    # entry = functions(llvm_mod)[llvm_specfunc]
    LLVM.name!(llvm_specfunc, GPUCompiler.safe_name(string("julia_", job.source.name)))
    return llvm_mod
end

struct MixtapeCompilerTarget <: AbstractCompilerTarget end

llvm_triple(::MixtapeCompilerTarget) = Sys.MACHINE

function get_llvm_optlevel(opt_level::Int)
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end
    return optlevel
end

struct MixtapeCompilerParams <: AbstractCompilerParams
    opt::Bool
    optlevel::Int
    ctx::CompilationContext
end

function MixtapeCompilerParams(; opt = false, 
        optlevel = Base.JLOptions().opt_level, 
        ctx = NoContext())
    return MixtapeCompilerParams(opt, optlevel, ctx)
end

