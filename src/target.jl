Base.@kwdef struct NativeCompilerTarget <: GPUCompiler.AbstractCompilerTarget
    cpu::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUName())
    features::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUFeatures())
end

Base.@kwdef struct ExternalNativeCompilerTarget <: GPUCompiler.AbstractCompilerTarget
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

struct StaticCompilerParams <: GPUCompiler.AbstractCompilerParams end

for target in (:NativeCompilerTarget, :ExternalNativeCompilerTarget)
    @eval begin
        GPUCompiler.llvm_triple(::$target) = Sys.MACHINE

        function GPUCompiler.llvm_machine(target::$target)
            triple = GPUCompiler.llvm_triple(target)

            t = LLVM.Target(triple=triple)

            tm = LLVM.TargetMachine(t, triple, target.cpu, target.features, reloc=LLVM.API.LLVMRelocPIC)
            GPUCompiler.asm_verbosity!(tm, true)

            return tm
        end

        GPUCompiler.runtime_slug(job::GPUCompiler.CompilerJob{$target}) = "native_$(job.target.cpu)-$(hash(job.target.features))"

        GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{$target}) = StaticRuntime
        GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{$target, StaticCompilerParams}) = StaticRuntime


        GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{$target, StaticCompilerParams}) = true
        GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{$target}) = true
    end
end

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any,StaticCompilerParams}) = StaticRuntime
GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{<:Any,StaticCompilerParams}) = true

GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{ExternalNativeCompilerTarget})) = method_table
GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{ExternalNativeCompilerTarget, StaticCompilerParams})) = method_table

function native_job(@nospecialize(func::Function), @nospecialize(types::Type);
        name = GPUCompiler.safe_name(repr(func)),
        libjulia::Bool = true,
        kernel::Bool = false,
        kwargs...
    )
    source = GPUCompiler.FunctionSpec(func, types, kernel, name)
    target = libjulia ? NativeCompilerTarget() : ExternalNativeCompilerTarget()
    params = StaticCompilerParams()
    GPUCompiler.CompilerJob(target, source, params), kwargs
end
