"""
```julia
    StaticTarget() # Native target
    StaticTarget(platform_or_triple) # Specific target with generic CPU (a `Base.BinaryPlatforms.Platform` or a triple string)
    StaticTarget(platform_or_triple, cpu::String) # Specific target with specific CPU
    StaticTarget(platform_or_triple, cpu::String, features::String) # Specific target with specific CPU and features
```
Struct that defines a target for the compilation
Beware that currently the compilation assumes that the code is on the host so platform specific code like:
```julia
    Sys.isapple() ...
```
does not behave as expected.
By default `StaticTarget()` is the native target.

If Julia's LLVM has no code generator for the target (x86-64 where LLVM has only AArch64 and WebAssembly, say), the target is made anyway, with `ir_triple` set: IR can be made for it
(`generate_ir`, `emit_llvm_only = true`, `llvm_to_clang = true`: the IR has the target's triple and no host CPU or features), and an external `clang` or `llc` that has the code generator makes the object.

For cross-compilation of executables and shared libraries, one also needs to call `set_compiler!` with the path to a valid C compiler
for the target platform. For example, to cross-compile for aarch64 using a compiler from homebrew, one can use:
```julia
    set_compiler!(StaticTarget(parse(Platform,"aarch64-gnu-linux")), "/opt/homebrew/bin/aarch64-unknown-linux-gnu-gcc")
```
"""
mutable struct StaticTarget
    platform::Union{Platform,Nothing}
    tm::LLVM.TargetMachine
    compiler::Union{String,Nothing} # A target-specific compiler, else nothing
    ir_triple::Union{String,Nothing} # A target that requires us to output IR only, else nothing
    julia_runtime::Bool
end
StaticTarget(platform, tm, compiler, julia_runtime) = StaticTarget(platform, tm, compiler, nothing, julia_runtime)
StaticTarget() = StaticTarget(HostPlatform(), LLVM.host_cpu_name(), LLVM.host_cpu_features())

# The target for a platform or a triple, with the generic CPU of its architecture unless `cpu` and `features` say otherwise. Julia's LLVM may have no code generator for it: then `ir_triple` is set, `tm`
# is the host's, and only IR can be made (see above).
function StaticTarget(target::Union{Platform,AbstractString}, cpu::AbstractString = "", features::AbstractString = "")
    platform = target isa Platform ? target : tryparse(Platform, target)
    triple = target isa Platform ? clean_triple(target) : String(target)
    tm = try
        LLVM.TargetMachine(LLVM.Target(triple = triple), triple; cpu, features)
    catch err
        # (`ArgumentError`: "No available targets are compatible with triple")
        err isa ArgumentError || rethrow()
        return StaticTarget(platform, host_generic_machine(), nothing, LLVM.normalize(triple), false)
    end
    return StaticTarget(platform, tm, nothing, nothing, false)
end
clean_triple(platform::Platform) = arch(platform) * os_str(platform) * libc_str(platform)

# the host's target machine without its CPU and its features, which are not those of another architecture's code (and not to be in its IR)
host_generic_machine() = LLVM.TargetMachine(LLVM.Target(triple = LLVM.default_triple()), LLVM.default_triple())

"The triple that the target is for: the one of its IR if it has no code generator in Julia's LLVM, and else the one of its target machine"
target_triple(target::StaticTarget) = something(target.ir_triple, LLVM.triple(target.tm))

"""
```julia
set_compiler!(target::StaticTarget, compiler::String)
```
Set the compiler for cross compilation. For example:
```julia
set_compiler!(StaticTarget(parse(Platform,"aarch64-gnu-linux")), "/opt/homebrew/bin/aarch64-elf-gcc")
```
"""
set_compiler!(target::StaticTarget, compiler::String) = (target.compiler = compiler)

set_runtime!(target::StaticTarget, julia_runtime::Bool) = (target.julia_runtime = julia_runtime)

# Default to native
struct StaticCompilerTarget{MT} <: GPUCompiler.AbstractCompilerTarget
    triple::String
    cpu::String
    features::String
    julia_runtime::Bool
    method_table::MT
end

struct StaticCompilerParams <: GPUCompiler.AbstractCompilerParams
    opt::Bool
    optlevel::Int
end

function StaticCompilerParams(; opt=false,
    optlevel=Base.JLOptions().opt_level
)
    return StaticCompilerParams(opt, optlevel)
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

    tm = LLVM.TargetMachine(t, triple; target.cpu, target.features, reloc=LLVM.RelocMode.PIC)
    LLVM.asm_verbosity!(tm, true)

    return tm
end

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = StaticRuntime


GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = true

GPUCompiler.uses_julia_runtime(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = job.config.target.julia_runtime
GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget})) = job.config.target.method_table


# `params` is the `GPUCompiler.AbstractCompilerParams` of the job. Other packages can pass a type of their own, to
# specialize GPUCompiler's functions (`inference_params`, `optimize!`, ...) for their compilations only, without
# adding methods for `StaticCompilerTarget` and `StaticCompilerParams`, which are ours. All the methods above
# are for any `params`.
function static_job(@nospecialize(func), @nospecialize(types);
    name = fix_name(func),
    kernel::Bool = false,
    target::StaticTarget = StaticTarget(),
    params::GPUCompiler.AbstractCompilerParams = StaticCompilerParams(),
    method_table = method_table,
    kwargs...
)
    source = GPUCompiler.methodinstance(typeof(func), Base.to_tuple_type(types))
    tm = target.tm
    gputarget = StaticCompilerTarget(tm.triple, tm.cpu, tm.features, target.julia_runtime, method_table)
    config = GPUCompiler.CompilerConfig(gputarget, params; name, kernel, kwargs...)
    return GPUCompiler.CompilerJob(source, config), Dict{}()
end
