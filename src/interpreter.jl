## interpreter

using Core.Compiler:
    AbstractInterpreter, InferenceResult, InferenceParams, InferenceState, MethodInstance, OptimizationParams, WorldView, get_world_counter
using GPUCompiler:
    @safe_debug, AbstractCompilerParams, CompilerJob, methodinstance, CodeInstance, inference_params, optimization_params
using CodeInfoTools
using CodeInfoTools: resolve


const HAS_INTEGRATED_CACHE = GPUCompiler.HAS_INTEGRATED_CACHE
@static if HAS_INTEGRATED_CACHE
    const CodeCache = Nothing

else
    using GPUCompiler: CodeCache
end

# https://github.com/JuliaGPU/GPUCompiler.jl/src/jlgen.jl8#L322
# as from struct GPUInterpreter <: CC.AbstractInterpreter 
struct StaticInterpreter <: AbstractInterpreter
    # The world age we're working inside of
    world::UInt
    method_table::Union{Nothing,Core.MethodTable}

    @static if HAS_INTEGRATED_CACHE
        token::Any
    else
        code_cache::CodeCache # global cache
    end

    # Cache of inference results for this particular interpreter
    local_cache::Vector{InferenceResult}

    # Parameters for inference and optimization
    inf_params::InferenceParams
    opt_params::OptimizationParams
    # token_or_cache = token::Any, code_cache::CodeCache
    function StaticInterpreter(world::UInt, mt::Union{Nothing,Core.MethodTable}, token_or_cache, ip::InferenceParams, op::OptimizationParams)
        @assert world <= Base.get_world_counter()
        # mt = get_method_table_view(world, mt)
        local_cache = Vector{Core.Compiler.InferenceResult}() # Initially empty cache
        return new(world, mt, token_or_cache, local_cache, ip, op)
    end
end

Core.Compiler.InferenceParams(interp::StaticInterpreter) = interp.inf_params
Core.Compiler.OptimizationParams(interp::StaticInterpreter) = interp.opt_params
GPUCompiler.get_inference_world(interp::StaticInterpreter) = interp.world
Core.Compiler.get_inference_cache(interp::StaticInterpreter) = interp.local_cache
@static if HAS_INTEGRATED_CACHE
    Core.Compiler.cache_owner(interp::StaticInterpreter) = interp.token
else
    Core.Compiler.code_cache(interp::StaticInterpreter) = WorldView(interp.code_cache, interp.world)
end

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
    world = get_world_counter(interp)
    src = @static if VERSION >= v"1.10.0-DEV.873"
        Core.Compiler.retrieve_code_info(result.linfo, world)
    else
        Core.Compiler.retrieve_code_info(result.linfo)
    end
    mi = result.linfo
    src = custom_pass!(interp, result, mi, src)
    src === nothing && return @static if VERSION < v"1.11"
        Core.Compiler.maybe_validate_code(result.linfo, src, "lowered")
    else
        Core.Compiler.validate_code_in_debug_mode(result.linfo, src, "lowered")
    end
    return InferenceState(result, src, cache, interp)
end

Core.Compiler.may_optimize(interp::StaticInterpreter) = true
Core.Compiler.may_compress(interp::StaticInterpreter) = true
Core.Compiler.may_discard_trees(interp::StaticInterpreter) = true
Core.Compiler.verbose_stmt_info(interp::StaticInterpreter) = false

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
    cache::CodeCache
end

function StaticCompilerParams(; opt=false,
    optlevel=Base.JLOptions().opt_level,
    cache=CodeCache()
)
    return StaticCompilerParams(opt, optlevel, cache)
end
