@static if isdefined(Base.Experimental, Symbol("@overlay"))
    Base.Experimental.@MethodTable(method_table)
else
    const method_table = nothing
end

const overrides = quote end

"""
```julia
@device_override old_bad_method(arg1::Type1, arg2::Type2) = new_good_method(arg1, arg2)
```
Override a non-static-compilable method (e.g. `old_bad_method(::Type1, ::Type2)`)
with a more compileable replacement.
### Examples
```
@device_override @noinline Core.throw_inexacterror(f::Symbol, ::Type{T}, val) where {T} =
    @print_and_throw c"Inexact conversion"
```
"""
macro device_override(ex)
    ex = macroexpand(__module__, ex)
    if Meta.isexpr(ex, :call)
        @show ex = eval(ex)
        error()
    end
    code = quote
        $GPUCompiler.@override(StaticCompiler.method_table, $ex)
    end
    if isdefined(Base.Experimental, Symbol("@overlay"))
        return esc(code)
    else
        push!(overrides, code)
        return
    end
end

Base.@kwdef struct NativeCompilerTarget <: GPUCompiler.AbstractCompilerTarget
    triple::String=Sys.MACHINE
    cpu::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUName())
    features::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUFeatures())
end

Base.@kwdef struct ExternalNativeCompilerTarget <: GPUCompiler.AbstractCompilerTarget
    triple::String=Sys.MACHINE
    cpu::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUName())
    features::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUFeatures())
end

module StaticRuntime
    # the runtime library
    signal_exception() = return
    malloc(sz) = ccall("extern malloc", llvmcall, Csize_t, (Csize_t,), sz)
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end

for target in (:NativeCompilerTarget, :ExternalNativeCompilerTarget)
    @eval begin
        GPUCompiler.llvm_triple(target::$target) = target.triple

        function GPUCompiler.llvm_machine(target::$target)
            triple = GPUCompiler.llvm_triple(target)

            t = LLVM.Target(triple=triple)

            tm = LLVM.TargetMachine(t, triple, target.cpu, target.features, reloc=LLVM.API.LLVMRelocPIC)
            GPUCompiler.asm_verbosity!(tm, true)

            return tm
        end

        GPUCompiler.runtime_slug(job::GPUCompiler.CompilerJob{$target}) = "native_$(job.config.target.cpu)-$(hash(job.config.target.features))"

        GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{$target}) = StaticRuntime
        GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{$target, StaticCompilerParams}) = StaticRuntime


        GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{$target, StaticCompilerParams}) = true
        GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{$target}) = true

        GPUCompiler.get_interpreter(job::GPUCompiler.CompilerJob{$target, StaticCompilerParams}) =
            StaticInterpreter(job.config.params.cache, GPUCompiler.method_table(job), job.world,
                              GPUCompiler.inference_params(job), GPUCompiler.optimization_params(job),
                              job.config.params.mixtape)
        GPUCompiler.ci_cache(job::GPUCompiler.CompilerJob{$target, StaticCompilerParams}) = job.config.params.cache
    end
end

GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{ExternalNativeCompilerTarget})) = method_table
GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{ExternalNativeCompilerTarget, StaticCompilerParams})) = method_table

function native_job(@nospecialize(func::Function), @nospecialize(types::Type), external::Bool;
        mixtape = NoContext(),
        name = fix_name(func),
        kernel::Bool = false,
        target = (),
        kwargs...
    )
    source = methodinstance(typeof(func), Base.to_tuple_type(types))
    target = external ? ExternalNativeCompilerTarget(;target...) : NativeCompilerTarget(;target...)
    params = StaticCompilerParams(mixtape = mixtape)
    config = GPUCompiler.CompilerConfig(target, params, name = name, kernel = kernel)
    StaticCompiler.CompilerJob(source, config), kwargs
end

function native_job(@nospecialize(func), @nospecialize(types), external; mixtape = NoContext(), kernel::Bool=false, name=fix_name(repr(func)), target = (), kwargs...)
    source = methodinstance(typeof(func), Base.to_tuple_type(types))
    target = external ? ExternalNativeCompilerTarget(;target...) : NativeCompilerTarget(;target...)
    params = StaticCompilerParams(mixtape = mixtape)
    config = GPUCompiler.CompilerConfig(target, params, name = name, kernel = kernel)
    GPUCompiler.CompilerJob(source, config), kwargs
end
