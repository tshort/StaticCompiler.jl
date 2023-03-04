## interpreter

using Core.Compiler:
    AbstractInterpreter, InferenceResult, InferenceParams, InferenceState, MethodInstance, OptimizationParams, WorldView
using GPUCompiler:
    @safe_debug, AbstractCompilerParams, CodeCache, CompilerJob, FunctionSpec
using CodeInfoTools
using CodeInfoTools: resolve

struct StaticInterpreter{C} <: AbstractInterpreter
    global_cache::CodeCache
    method_table::Union{Nothing,Core.MethodTable}

    # Cache of inference results for this particular interpreter
    local_cache::Vector{InferenceResult}
    # The world age we're working inside of
    world::UInt

    # Parameters for inference and optimization
    inf_params::InferenceParams
    opt_params::OptimizationParams

    # Mixtape context
    ctx::C

    function StaticInterpreter(cache::CodeCache, mt::Union{Nothing,Core.MethodTable}, world::UInt, ip::InferenceParams, op::OptimizationParams, ctx)
        @assert world <= Base.get_world_counter()

        return new{typeof(ctx)}(
            cache,
            mt,

            # Initially empty cache
            Vector{InferenceResult}(),

            # world age counter
            world,

            # parameters for inference and optimization
            ip,
            op,

            # Mixtape context
            ctx
        )
    end
end


Core.Compiler.InferenceParams(interp::StaticInterpreter) = interp.inf_params
Core.Compiler.OptimizationParams(interp::StaticInterpreter) = interp.opt_params
Core.Compiler.get_world_counter(interp::StaticInterpreter) = interp.world
Core.Compiler.get_inference_cache(interp::StaticInterpreter) = interp.local_cache
Core.Compiler.code_cache(interp::StaticInterpreter) = WorldView(interp.global_cache, interp.world)

# No need to do any locking since we're not putting our results into the runtime cache
Core.Compiler.lock_mi_inference(interp::StaticInterpreter, mi::MethodInstance) = nothing
Core.Compiler.unlock_mi_inference(interp::StaticInterpreter, mi::MethodInstance) = nothing

function Core.Compiler.add_remark!(interp::StaticInterpreter, sv::InferenceState, msg)
    @safe_debug "Inference remark during  static compilation of $(sv.linfo): $msg"
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
    # @show interp.ctx, mi
    if allow(interp.ctx, mi.def.module, as...)
        src = transform(interp.ctx, src, sig)
    end
    return src
end

function InferenceState(result::InferenceResult, cache::Symbol, interp::StaticInterpreter)
    src = Core.Compiler.retrieve_code_info(result.linfo)
    mi = result.linfo
    src = custom_pass!(interp, result, mi, src)
    src === nothing && return nothing
    Core.Compiler.validate_code_in_debug_mode(result.linfo, src, "lowered")
    return InferenceState(result, src, cache, interp)
end

Core.Compiler.may_optimize(interp::StaticInterpreter) = true
Core.Compiler.may_compress(interp::StaticInterpreter) = true
Core.Compiler.may_discard_trees(interp::StaticInterpreter) = true
if VERSION >= v"1.7.0-DEV.577"
Core.Compiler.verbose_stmt_info(interp::StaticInterpreter) = false
end

if isdefined(Base.Experimental, Symbol("@overlay"))
using Core.Compiler: OverlayMethodTable
if v"1.8-beta2" <= VERSION < v"1.9-" || VERSION >= v"1.9.0-DEV.120"
Core.Compiler.method_table(interp::StaticInterpreter) =
    OverlayMethodTable(interp.world, interp.method_table)
else
Core.Compiler.method_table(interp::StaticInterpreter, sv::InferenceState) =
    OverlayMethodTable(interp.world, interp.method_table)
end
else
Core.Compiler.method_table(interp::StaticInterpreter, sv::InferenceState) =
    WorldOverlayMethodTable(interp.world)
end

# semi-concrete interepretation is broken with overlays (JuliaLang/julia#47349)
@static if VERSION >= v"1.9.0-DEV.1248"
function Core.Compiler.concrete_eval_eligible(interp::StaticInterpreter,
    @nospecialize(f), result::Core.Compiler.MethodCallResult, arginfo::Core.Compiler.ArgInfo)
    ret = @invoke Core.Compiler.concrete_eval_eligible(interp::AbstractInterpreter,
        f::Any, result::Core.Compiler.MethodCallResult, arginfo::Core.Compiler.ArgInfo)
    ret === false && return nothing
    return ret
end
end

struct StaticCompilerParams <: AbstractCompilerParams
    opt::Bool
    optlevel::Int
    ctx::CompilationContext
end

function StaticCompilerParams(; opt = false, 
        optlevel = Base.JLOptions().opt_level, 
        ctx = NoContext())
    return StaticCompilerParams(opt, optlevel, ctx)
end

