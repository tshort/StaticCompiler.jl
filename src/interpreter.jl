## interpreter

using Core.Compiler:
    AbstractInterpreter, InferenceResult, InferenceParams, InferenceState, MethodInstance, OptimizationParams, WorldView
using GPUCompiler:
    @safe_debug, AbstractCompilerParams, CompilerJob, methodinstance, CodeInstance, inference_params, optimization_params, get_inference_world
using CodeInfoTools
using CodeInfoTools: resolve


struct StaticInterpreter <: AbstractInterpreter
    # The world age we're working inside of
    world::UInt
    method_table::Union{Nothing,Core.MethodTable}

    token::Any

    # Cache of inference results for this particular interpreter
    local_cache::Vector{InferenceResult}

    # Parameters for inference and optimization
    inf_params::InferenceParams
    opt_params::OptimizationParams
    function StaticInterpreter(world::UInt, mt::Union{Nothing,Core.MethodTable}, token_or_cache, ip::InferenceParams, op::OptimizationParams)
        @assert world <= Base.get_world_counter()
        local_cache = Vector{Core.Compiler.InferenceResult}() # Initially empty cache
        return new(world, mt, token_or_cache, local_cache, ip, op)
    end
end

Core.Compiler.InferenceParams(interp::StaticInterpreter) = interp.inf_params
Core.Compiler.OptimizationParams(interp::StaticInterpreter) = interp.opt_params
GPUCompiler.get_inference_world(interp::StaticInterpreter) = interp.world
Core.Compiler.get_inference_cache(interp::StaticInterpreter) = interp.local_cache
Core.Compiler.cache_owner(interp::StaticInterpreter) = interp.token

# No need to do any locking since we're not putting our results into the runtime cache
Core.Compiler.lock_mi_inference(interp::StaticInterpreter, mi::MethodInstance) = nothing
Core.Compiler.unlock_mi_inference(interp::StaticInterpreter, mi::MethodInstance) = nothing

function Core.Compiler.add_remark!(interp::StaticInterpreter, sv::InferenceState, msg)
    @safe_debug "Inference remark during static compilation of $(sv.linfo): $msg"
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
    return src
end

function Core.Compiler.InferenceState(result::InferenceResult, cache::Symbol, interp::StaticInterpreter)
    world = get_inference_world(interp)
    src = Core.Compiler.retrieve_code_info(result.linfo, world)
    mi = result.linfo
    src = custom_pass!(interp, result, mi, src)
    src === nothing && return Core.Compiler.maybe_validate_code(result.linfo, src, "lowered")
    return InferenceState(result, src, cache, interp)
end

Core.Compiler.may_optimize(interp::StaticInterpreter) = true
Core.Compiler.may_compress(interp::StaticInterpreter) = true
Core.Compiler.may_discard_trees(interp::StaticInterpreter) = true
if isdefined(Core.Compiler, :verbose_stmt_inf)
    Core.Compiler.verbose_stmt_info(interp::StaticInterpreter) = false
end

if isdefined(Base.Experimental, Symbol("@overlay"))
    using Core.Compiler: OverlayMethodTable
    Core.Compiler.method_table(interp::StaticInterpreter) =
            OverlayMethodTable(interp.world, interp.method_table)
else
    Core.Compiler.method_table(interp::StaticInterpreter, sv::InferenceState) =
        WorldOverlayMethodTable(interp.world)
end

# semi-concrete interepretation is broken with overlays (JuliaLang/julia#47349)
function Core.Compiler.concrete_eval_eligible(interp::StaticInterpreter,
    @nospecialize(f), result::Core.Compiler.MethodCallResult, arginfo::Core.Compiler.ArgInfo)
    ret = @invoke Core.Compiler.concrete_eval_eligible(interp::AbstractInterpreter,
        f::Any, result::Core.Compiler.MethodCallResult, arginfo::Core.Compiler.ArgInfo)
    ret === false && return nothing
    return ret
end

struct StaticCompilerParams <: AbstractCompilerParams
    opt::Bool
    optlevel::Int
end

function StaticCompilerParams(; opt=false,
    optlevel=Base.JLOptions().opt_level
)
    return StaticCompilerParams(opt, optlevel)
end
