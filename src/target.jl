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
    # dummy methods
    signal_exception() = return
    # HACK: if malloc returns 0 or traps, all calling functions (like jl_box_*)
    #       get reduced to a trap, which really messes with our test suite.
    malloc(sz) = Ptr{Cvoid}(Int(0xDEADBEEF))
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end

struct StaticCompilerParams <: GPUCompiler.AbstractCompilerParams end

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any,StaticCompilerParams}) = StaticRuntime
GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{NativeCompilerTarget}) = true

function native_job(@nospecialize(func), @nospecialize(types); kernel::Bool=false, name=GPUCompiler.safe_name(repr(func)), kwargs...)
    source = GPUCompiler.FunctionSpec(func, Base.to_tuple_type(types), kernel, name)
    target = NativeCompilerTarget()
    params = StaticCompilerParams()
    GPUCompiler.CompilerJob(target, source, params), kwargs
end
