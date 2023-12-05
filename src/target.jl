@static if isdefined(Base.Experimental, Symbol("@overlay"))
    Base.Experimental.@MethodTable(method_table)
else
    const method_table = nothing
end

"""
```julia
    StaticTarget() # Native target
    StaticTarget(platform::Base.BinaryPlatforms.Platform) # Specific target with generic CPU
    StaticTarget(platform::Platform, cpu::String) # Specific target with specific CPU
    StaticTarget(platform::Platform, cpu::String, features::String) # Specific target with specific CPU and features
```
Struct that defines a target for the compilation
Beware that currently the compilation assumes that the code is on the host so platform specific code like:
```julia
    Sys.isapple() ...
```
does not behave as expected.
By default `StaticTarget()` is the native target.

For cross-compilation of executables and shared libraries, one also needs to call `set_compiler!` with the path to a valid C compiler
for the target platform. For example, to cross-compile for aarch64 using a compiler from homebrew, one can use:
```julia
    set_compiler!(StaticTarget(parse(Platform,"aarch64-gnu-linux")), "/opt/homebrew/bin/aarch64-unknown-linux-gnu-gcc")
```
"""
mutable struct StaticTarget
    platform::Union{Platform,Nothing}
    tm::LLVM.TargetMachine
    compiler::Union{String,Nothing}
end

clean_triple(platform::Platform) = arch(platform) * os_str(platform) * libc_str(platform)
StaticTarget() = StaticTarget(HostPlatform(), unsafe_string(LLVM.API.LLVMGetHostCPUName()), unsafe_string(LLVM.API.LLVMGetHostCPUFeatures()))
StaticTarget(platform::Platform) = StaticTarget(platform, LLVM.TargetMachine(LLVM.Target(triple = clean_triple(platform)), clean_triple(platform)), nothing)
StaticTarget(platform::Platform, cpu::String) = StaticTarget(platform, LLVM.TargetMachine(LLVM.Target(triple = clean_triple(platform)), clean_triple(platform), cpu), nothing)
StaticTarget(platform::Platform, cpu::String, features::String) = StaticTarget(platform, LLVM.TargetMachine(LLVM.Target(triple = clean_triple(platform)), clean_triple(platform), cpu, features), nothing)

function StaticTarget(triple::String, cpu::String, features::String)
    platform = tryparse(Platform, triple)
    StaticTarget(platform, LLVM.TargetMachine(LLVM.Target(triple = triple), triple, cpu, features), nothing)
end

"""
Set the compiler for cross compilation
    ```julia
    set_compiler!(StaticTarget(parse(Platform,"aarch64-gnu-linux")), "/opt/homebrew/bin/aarch64-elf-gcc")
```
"""
set_compiler!(target::StaticTarget, compiler::String) = (target.compiler = compiler)

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
        $Base.Experimental.@overlay($StaticCompiler.method_table, $ex)
    end
    return esc(code)
end

# Default to native
struct StaticCompilerTarget{MT} <: GPUCompiler.AbstractCompilerTarget
    triple::String
    cpu::String
    features::String
    method_table::MT
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


GPUCompiler.llvm_triple(target::StaticCompilerTarget) = target.triple

function GPUCompiler.llvm_machine(target::StaticCompilerTarget)
    triple = GPUCompiler.llvm_triple(target)

    t = LLVM.Target(triple=triple)

    tm = LLVM.TargetMachine(t, triple, target.cpu, target.features, reloc=LLVM.API.LLVMRelocPIC)
    GPUCompiler.asm_verbosity!(tm, true)

    return tm
end

GPUCompiler.runtime_slug(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = "static_$(job.config.target.cpu)-$(hash(job.config.target.features))"

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = StaticRuntime
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:StaticCompilerTarget, StaticCompilerParams}) = StaticRuntime


GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget, StaticCompilerParams}) = true
GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = true

GPUCompiler.get_interpreter(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget, StaticCompilerParams}) =
    StaticInterpreter(job.config.params.cache, GPUCompiler.method_table(job), job.world,
                        GPUCompiler.inference_params(job), GPUCompiler.optimization_params(job))
GPUCompiler.ci_cache(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget, StaticCompilerParams}) = job.config.params.cache
GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget})) = job.config.target.method_table


function static_job(@nospecialize(func::Function), @nospecialize(types::Type);
        name = fix_name(func),
        kernel::Bool = false,
        target::StaticTarget = StaticTarget(),
        method_table=method_table,
        kwargs...
    )
    source = methodinstance(typeof(func), Base.to_tuple_type(types))
    tm = target.tm
    gputarget = StaticCompilerTarget(LLVM.triple(tm), LLVM.cpu(tm), LLVM.features(tm), method_table)
    params = StaticCompilerParams()
    config = GPUCompiler.CompilerConfig(gputarget, params, name = name, kernel = kernel)
    StaticCompiler.CompilerJob(source, config), kwargs
end
function static_job(@nospecialize(func), @nospecialize(types);
    name = fix_name(func),
    kernel::Bool = false,
    target::StaticTarget = StaticTarget(),
    method_table=method_table,
    kwargs...
)
    source = methodinstance(typeof(func), Base.to_tuple_type(types))
    tm = target.tm
    gputarget = StaticCompilerTarget(LLVM.triple(tm), LLVM.cpu(tm), LLVM.features(tm), method_table)
    params = StaticCompilerParams()
    config = GPUCompiler.CompilerConfig(gputarget, params, name = name, kernel = kernel)
    StaticCompiler.CompilerJob(source, config), kwargs
end