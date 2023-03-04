Base.@kwdef struct NativeCompilerTarget <: GPUCompiler.AbstractCompilerTarget
    cpu::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUName())
    features::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUFeatures())
end

GPUCompiler.llvm_triple(::NativeCompilerTarget) = Sys.MACHINE

function GPUCompiler.llvm_machine(target::NativeCompilerTarget)
    triple = GPUCompiler.llvm_triple(target)

    t = LLVM.Target(triple=triple)

    tm = LLVM.TargetMachine(t, triple, target.cpu, target.features, reloc=LLVM.API.LLVMRelocPIC)
    GPUCompiler.asm_verbosity!(tm, true)

    return tm
end

GPUCompiler.runtime_slug(job::GPUCompiler.CompilerJob{NativeCompilerTarget}) = "native_$(job.target.cpu)-$(hash(job.target.features))"

module StaticRuntime
    # the runtime library
    signal_exception() = return
    malloc(sz) = ccall("extern malloc", llvmcall, Csize_t, (Csize_t,), sz)
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end

# struct StaticCompilerParams <: GPUCompiler.AbstractCompilerParams end

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any,StaticCompilerParams}) = StaticRuntime
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{NativeCompilerTarget}) = StaticRuntime
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{NativeCompilerTarget, StaticCompilerParams}) = StaticRuntime

GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{<:Any,StaticCompilerParams}) = true
GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{NativeCompilerTarget, StaticCompilerParams}) = true
GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{NativeCompilerTarget}) = true

function native_job(@nospecialize(func), @nospecialize(types), @nospecialize(ctx); kernel::Bool=false, name=GPUCompiler.safe_name(repr(func)), kwargs...)
    source = GPUCompiler.FunctionSpec(func, Base.to_tuple_type(types), kernel, name)
    target = NativeCompilerTarget()
    params = StaticCompilerParams(ctx = ctx)
    StaticCompiler.CompilerJob(target, source, params), kwargs
end


StaticCompilerJob = CompilerJob{NativeCompilerTarget,StaticCompilerParams}

function GPUCompiler.get_interpreter(job::StaticCompilerJob)
    StaticInterpreter(GPUCompiler.ci_cache(job), GPUCompiler.method_table(job), job.source.world, GPUCompiler.inference_params(job), GPUCompiler.optimization_params(job), job.params.ctx)    
end
