"""
    Retarget(triple, cpu, features, llc)

What a target needs to be made for by retargeting: Julia's code generation makes the code for the host (`tm` of the target is the host's), and its IR gets the `triple` (see [`retarget!`](@ref)); the object is then made
for the `triple`, with `cpu` and `features`, by the code generator of Julia's LLVM if it has one for it, and else by the external `llc` (which has to be of the LLVM version that Julia has), if there is one.
"""
struct Retarget
    triple::String
    cpu::String
    features::String
    llc::Union{Cmd,Nothing}
end

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

If Julia's LLVM has no code generator for the target (x86-64 where LLVM has only AArch64 and WebAssembly, say), the target is made anyway, as a `Retarget` (the field `retarget`): IR can be made for it
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
    toolchain::Union{Toolchain,Nothing} # How the target is linked (a `Driver` of a target-specific compiler, an `LLD`, ...), else the default of `default_toolchain`
    retarget::Union{Retarget,Nothing} # A target that the code is made for as for the host and then retargeted (see `Retarget`), else nothing
    julia_runtime::Bool
end
StaticTarget(platform, tm, compiler, julia_runtime) = StaticTarget(platform, tm, as_toolchain(compiler), nothing, julia_runtime) # (`compiler`: the C compiler of a `Driver`, as the field was)
StaticTarget() = StaticTarget(HostPlatform(), LLVM.host_cpu_name(), LLVM.host_cpu_features())

# The target for a platform or a triple, with the generic CPU of its architecture unless `cpu` and `features` say otherwise. 
# If Julia's LLVM has no code generator for it, then the target is a `Retarget`, `tm` is the host's, and the target is a `Retarget`: 
# Then the object is made by `llc` (the keyword `llc`, a `Cmd` or a path).
# `retarget = true` makes such a target for any triple, with the generic CPU of the host 
#  (or `retarget = host_target`, a `StaticTarget` of the host, with its machine).
function StaticTarget(target::Union{Platform,AbstractString}, cpu::AbstractString = "", features::AbstractString = ""; toolchain = nothing, retarget::Union{Bool,StaticTarget} = false, llc = nothing)
    init_llvm_targets()
    platform = target isa Platform ? target : tryparse(Platform, target)
    triple = target isa Platform ? clean_triple(target) : String(target)
    retargeted = Retarget(LLVM.normalize(triple), cpu, features, llc === nothing ? nothing : llc isa Cmd ? llc : `$llc`)
    retarget === false || return StaticTarget(platform, retarget isa StaticTarget ? retarget.tm : host_generic_machine(), as_toolchain(toolchain), retargeted, false)
    tm = try
        LLVM.TargetMachine(LLVM.Target(triple = triple), triple; cpu, features)
    catch err
        # (`ArgumentError`: "No available targets are compatible with triple")
        err isa ArgumentError || rethrow()
        return StaticTarget(platform, host_generic_machine(), as_toolchain(toolchain), retargeted, false)
    end
    return StaticTarget(platform, tm, as_toolchain(toolchain), nothing, false)
end
clean_triple(platform::Platform) = arch(platform) * os_str(platform) * libc_str(platform)

# The code generators of every target that Julia's LLVM has, which are not all there until they are initialized (GPUCompiler does it when it first compiles, which is after a target is made)
const LLVM_TARGETS_INITIALIZED = Ref(false)
function init_llvm_targets()
    LLVM_TARGETS_INITIALIZED[] && return
    LLVM.InitializeAllTargetInfos()
    LLVM.InitializeAllTargets()
    LLVM.InitializeAllTargetMCs()
    LLVM.InitializeAllAsmPrinters()
    LLVM.InitializeAllAsmParsers()
    LLVM_TARGETS_INITIALIZED[] = true
    return
end

# The host's target machine without its CPU and its features, which are not those of another architecture's code (and not to be in its IR)
host_generic_machine() = LLVM.TargetMachine(LLVM.Target(triple = LLVM.default_triple()), LLVM.default_triple())

# The triple that the target is for: the one of its `Retarget`, else the one of its target machine
target_triple(target::StaticTarget) = isnothing(target.retarget) ? LLVM.triple(target.tm) : target.retarget.triple

"""
```julia
set_compiler!(target::StaticTarget, compiler::String)
```
Set the compiler for cross compilation. For example:
```julia
set_compiler!(StaticTarget(parse(Platform,"aarch64-gnu-linux")), "/opt/homebrew/bin/aarch64-elf-gcc")
```
"""
set_compiler!(target::StaticTarget, compiler::Union{AbstractString,Cmd}) = (target.toolchain = Driver(compiler))

"""
```julia
set_toolchain!(target::StaticTarget, toolchain::Toolchain)
```
Set how the target is linked: a [`Driver`](@ref) (a C compiler) or an [`LLD`](@ref) (`lld` and the C library of a sysroot).
"""
set_toolchain!(target::StaticTarget, tc::Toolchain) = (target.toolchain = tc)

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


function GPUCompiler.llvm_machine(target::StaticCompilerTarget)
    triple = GPUCompiler.llvm_triple(target)

    t = LLVM.Target(triple=triple)

    tm = LLVM.TargetMachine(t, triple; target.cpu, target.features, reloc=LLVM.RelocMode.PIC)
    LLVM.asm_verbosity!(tm, true)

    return tm
end
GPUCompiler.llvm_triple(target::StaticCompilerTarget) = target.triple
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

## The target

# Whether or not Julia's LLVM has the code generator for the triple
julia_llvm_has(triple::AbstractString) = (init_llvm_targets(); try; LLVM.Target(; triple = String(triple)); true; catch; false; end)

# Whether an object can be made for the target here: always if target=host, and for a `Retarget` if Julia's LLVM or an `llc` has the code generator
can_emit_object(target::StaticTarget) = isnothing(target.retarget) || julia_llvm_has(target.retarget.triple) || !isnothing(target.retarget.llc)

# Make any OS-specific choices on the basis of the target, not the host
iswindows(target::StaticTarget) = isnothing(target.platform) ? occursin(r"windows|mingw|msvc|cygwin"i, target_triple(target)) : Sys.iswindows(target.platform)
isapple(target::StaticTarget) = isnothing(target.platform) ? occursin(r"apple|darwin|macos"i, target_triple(target)) : Sys.isapple(target.platform)

# The shared library extension of the target (that of the host, unless cross-compiling)
dlext(target::StaticTarget) = isnothing(target.platform) ? Libdl.dlext : platform_dlext(target.platform)

# Whether the IR has to go through an external compiler (`clang`, `llc`) to be an object: on Windows (always), or where Julia's LLVM has no code generator for the target
# (An `LLD` links objects, which IR is not: for it an object that cannot be made says so, by `generate_obj`, and does not go on as IR.)
needs_ir(target::StaticTarget) = (iswindows(target) || !can_emit_object(target)) && !(target.toolchain isa LLD)

# `clang` makes code for its own host unless it is told the target (it replaces the triple of the IR, which `-Wno-override-module` hides)
function clang_target_flags(target::StaticTarget)
    host = HostPlatform()
    foreign = !isnothing(target.retarget) || (!isnothing(target.platform) && (arch(target.platform) != arch(host) || os(target.platform) != os(host)))
    return foreign ? `--target=$(target_triple(target))` : ``
end

# The family that an architecture's intrinsics (`llvm.<family>.`) are named by
llvm_family(arch::AbstractString) = startswith(arch, "aarch64") || startswith(arch, "arm64") ? "aarch64" : startswith(arch, "arm") ? "arm" : arch in ("x86_64", "i686", "i386", "x86") ? "x86" : startswith(arch, "wasm") ? "wasm" : arch
