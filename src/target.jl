"""
    Machine(triple, cpu, features)

A machine that code is made for: the LLVM `triple`, the `cpu` (`""` for a generic cpu of a given architecture) and the cpu `features` (`"+neon,-sve"`, ...).
"""
struct Machine
    triple::String
    cpu::String
    features::String
end

"""
```julia
    StaticTarget() # Native target
    StaticTarget(platform_or_triple) # Specific target with generic CPU (a `Base.BinaryPlatforms.Platform` or a triple string)
    StaticTarget(platform_or_triple, cpu::String) # Specific target with specific CPU
    StaticTarget(platform_or_triple, cpu::String, features::String) # Specific target with specific CPU and features
    StaticTarget(target::StaticTarget; toolchain, llc, julia_runtime, can_throw) # A copy with some of those changed
```
A target for the compilation: what the program is made for (`machine`, the triple, the CPU and the features), how it is linked (`toolchain`), and what the compiled code may do (`julia_runtime`, `can_throw`).
By default `StaticTarget()` is the native target. The keywords of the constructors are

* `toolchain`: how the target is linked: a [`CCToolchain`](@ref) (a C compiler: a `String` or a `Cmd` is the compiler of one) or an [`LLDToolchain`](@ref); the default is the host's `clang`.
* `julia_runtime = false`: whether the code may call the runtime of Julia.
* `can_throw = true`: whether the code may throw errors (a function that cannot, is compiled without the machinery for it).
* `retarget = false`, `llc = nothing`: see below.

Beware that currently the compilation assumes that the code is on the host so platform specific code like:
```julia
    Sys.isapple() ...
```
does not behave as expected.

**Retargeting.** Julia's code generation makes the IR for the `machine` of the target, unless the target is retargeted. If the target is not the host's (`retarget = true`, or `retarget = host`, a `StaticTarget` whose machine is
the one to make the IR for; and always where Julia's LLVM has no code generator for the target: x86-64 on a build of Julia that has only AArch64 and WebAssembly, say), the IR is made for the host and then given the target's triple, without
the host's CPU or features (see [`retarget!`](@ref)): IR can be made for it (`generate_ir`, `emit_llvm_only = true`, `llvm_to_clang = true`), and the object is made by the code generator of Julia's LLVM if it has one for the triple, else by the external `llc`
(a `Cmd` or a path, of the LLVM version that Julia has), or `clang`.

The fields can be set (`set_compiler!`, `set_toolchain!`, `set_runtime!`), and the copy constructor makes a changed copy, which leaves the original as it was: `StaticTarget(target; toolchain = CCToolchain("/opt/homebrew/bin/aarch64-unknown-linux-gnu-gcc"))`.
"""
mutable struct StaticTarget
    machine::Machine # What the program is made for
    codegen::Union{Machine,Nothing} # What Julia's code generation makes the IR for if the target is retargeted (see above), and else `nothing`: the IR is made for `machine`
    toolchain::Union{Toolchain,Nothing} # How the target is linked, else the default of `default_toolchain`
    llc::Union{Cmd,Nothing} # The `llc` that makes the objects of a retargeted target that Julia's LLVM has no code generator for
    julia_runtime::Bool
    can_throw::Bool
end
StaticTarget() = StaticTarget(HostPlatform(), LLVM.host_cpu_name(), LLVM.host_cpu_features())

# The target for a platform or a triple, with the generic CPU of its architecture unless `cpu` and `features` say otherwise.
# `retarget = true` makes the IR for the generic CPU of the host (or `retarget = host_target`, a `StaticTarget` of the host: the machine of that one).
function StaticTarget(target::Union{Platform,AbstractString}, cpu::AbstractString = "", features::AbstractString = "";
        toolchain = nothing,
        retarget::Union{Bool,StaticTarget} = false,
        llc = nothing,
        julia_runtime::Bool = false,
        can_throw::Bool = true,
    )
    init_llvm_targets()
    triple = LLVM.normalize(llvm_triple(target isa Platform ? clean_triple(target) : String(target)))
    machine = Machine(triple, cpu, features)
    codegen = retarget isa StaticTarget ? retarget.machine : retarget || !julia_llvm_has(triple) ? host_generic_machine() : nothing
    return StaticTarget(machine, codegen, as_toolchain(toolchain), as_llc(llc), julia_runtime, can_throw)
end
# A copy with some changes
StaticTarget(target::StaticTarget; toolchain = target.toolchain, llc = target.llc, julia_runtime::Bool = target.julia_runtime, can_throw::Bool = target.can_throw, codegen::Union{Machine,Nothing} = target.codegen) =
    StaticTarget(target.machine, codegen, as_toolchain(toolchain), as_llc(llc), julia_runtime, can_throw)

# Ensure llc is either a Cmd or Nothing
as_llc(::Nothing) = nothing
as_llc(llc::Cmd) = llc
as_llc(llc::AbstractString) = `$llc`

"""
```julia
set_compiler!(target::StaticTarget, compiler)
```
Set the C compiler that links the target (a `String` or a `Cmd`): its toolchain becomes a [`CCToolchain`](@ref) of it. For example:
```julia
set_compiler!(StaticTarget("aarch64-unknown-linux-gnu"), "/opt/homebrew/bin/aarch64-unknown-linux-gnu-gcc")
```
"""
set_compiler!(target::StaticTarget, compiler::Union{AbstractString,Cmd}) = (target.toolchain = CCToolchain(compiler); target)

"""
```julia
set_toolchain!(target::StaticTarget, toolchain::Toolchain)
```
Set how the target is linked: a [`CCToolchain`](@ref) (a C compiler) or an [`LLDToolchain`](@ref) (`lld` and the C library of a sysroot).
"""
set_toolchain!(target::StaticTarget, tc::Toolchain) = (target.toolchain = tc; target)

"Set whether the code of the target may call the runtime of Julia."
set_runtime!(target::StaticTarget, julia_runtime::Bool) = (target.julia_runtime = julia_runtime; target)

clean_triple(platform::Platform) = arch(platform) * os_str(platform) * libc_str(platform)
# To emit a COFF object, LLVM seems to want `x86_64-w64-windows-gnu` in place of `x86_64-w64-mingw32`
llvm_triple(triple::AbstractString) = replace(String(triple), r"-mingw(?:32|64)$" => "-windows-gnu")

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

# The host's machine without its CPU and its features, which are not those of another architecture's code (and not to be in its IR)
host_generic_machine() = Machine(LLVM.default_triple(), "", "")

# The triple that the target is for
target_triple(target::StaticTarget) = target.machine.triple

# Whether the IR is made for another machine (the host's) than the target's, and retargeted (see `retarget!`)
is_retargeted(target::StaticTarget) = !isnothing(target.codegen)

# The machine that Julia's code generation makes the IR for
codegen_machine(target::StaticTarget) = something(target.codegen, target.machine)


# Default to native
struct StaticCompilerTarget{MT} <: GPUCompiler.AbstractCompilerTarget
    triple::String
    cpu::String
    features::String
    julia_runtime::Bool
    can_throw::Bool
    method_table::MT
end

# Both `opt` and `optlevel` seem to be unused in current GPUCompiler versions,
# so this particular implementation is somewhat vestigial, but could be expanded in the future
struct StaticCompilerParams <: GPUCompiler.AbstractCompilerParams
    opt::Bool
    optlevel::Int
end
function StaticCompilerParams(; opt=false,
        optlevel=Base.JLOptions().opt_level
    )
    return StaticCompilerParams(opt, optlevel)
end

module RuntimeStubs
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
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = RuntimeStubs
GPUCompiler.can_throw(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = job.config.target.can_throw
GPUCompiler.uses_julia_runtime(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget}) = job.config.target.julia_runtime
GPUCompiler.method_table(@nospecialize(job::GPUCompiler.CompilerJob{<:StaticCompilerTarget})) = job.config.target.method_table


# The `GPUCompiler.CompilerJob` of `func` for the argument types `types`,
# for the codegen machine of `target`, with its `julia_runtime` and `can_throw`, and the `method_table`.
# Other keywords (`name`, `strip`, `validate`, ...) are those of `GPUCompiler.CompilerConfig`.
# `params` is the `GPUCompiler.AbstractCompilerParams` of the job. Other packages may pass a type of their own, 
# to specialize GPUCompiler's functions (`inference_params`, `optimize!`, ...) for their compilations only, 
# without adding methods for `StaticCompilerTarget` and `StaticCompilerParams`, which are ours. 
# All the methods above are for any `params`.
function static_job(@nospecialize(func), @nospecialize(types);
    name = fix_name(func),
    kernel::Bool = false,
    target::StaticTarget = StaticTarget(),
    params::GPUCompiler.AbstractCompilerParams = StaticCompilerParams(),
    method_table = method_table,
    kwargs...
)
    source = GPUCompiler.methodinstance(typeof(func), Base.to_tuple_type(types))
    codegen = codegen_machine(target)
    gputarget = StaticCompilerTarget(codegen.triple, codegen.cpu, codegen.features, target.julia_runtime, target.can_throw, method_table)
    config = GPUCompiler.CompilerConfig(gputarget, params; name, kernel, kwargs...)
    return GPUCompiler.CompilerJob(source, config)
end

## The target

# Determine whether or not Julia's LLVM has the code generator for the triple
function julia_llvm_has(triple::AbstractString)
    init_llvm_targets()
    try
        LLVM.Target(; triple = String(triple))
        return true
    catch err
        # (`ArgumentError`: "No available targets are compatible with triple")
        err isa ArgumentError || rethrow()
        return false
    end
end

# Whether an object can be made for the target here: always if the code is made for it, and if it is retargeted, if Julia's LLVM or an `llc` has its code generator
can_emit_object(target::StaticTarget) = !is_retargeted(target) || julia_llvm_has(target_triple(target)) || !isnothing(target.llc)

# Make any OS-specific choices on the basis of the target, not the host
iswindows(target::StaticTarget) = occursin(r"windows|mingw|msvc|cygwin"i, target_triple(target))
isapple(target::StaticTarget) = occursin(r"apple|darwin|macos"i, target_triple(target))

# The shared library extension of the target
dlext(target::StaticTarget) = isapple(target) ? "dylib" : iswindows(target) ? "dll" : "so"

# Whether the IR has to go through an external compiler (`clang`, `llc`) to be an object: on Windows (always), or where Julia's LLVM has no code generator for the target
# (An `LLDToolchain` links objects, which IR is not: for it an object that cannot be made says so, by `generate_obj`, and does not go on as IR.)
needs_ir(target::StaticTarget) = (iswindows(target) || !can_emit_object(target)) && !(target.toolchain isa LLDToolchain)

# The architecture and the operating system that a triple says (not by `Platform`, which does not parse every triple that LLVM has: `x86_64-w64-windows-gnu`, `wasm64-unknown-unknown`)
triple_arch(triple::AbstractString) = (arch = String(first(split(triple, '-'))); arch in ("arm64", "aarch64") ? "aarch64" : arch in ("amd64", "x86_64") ? "x86_64" : arch)
triple_os(triple::AbstractString) = occursin(r"windows|mingw|msvc|cygwin"i, triple) ? :windows : occursin(r"apple|darwin|macos"i, triple) ? :apple : occursin("linux", triple) ? :linux : :other

# `clang` makes code for its own host unless it is told the target (it replaces the triple of the IR, which `-Wno-override-module` hides)
function clang_target_flags(target::StaticTarget)
    triple, host = target_triple(target), LLVM.default_triple()
    foreign = is_retargeted(target) || triple_arch(triple) != triple_arch(host) || triple_os(triple) != triple_os(host)
    return foreign ? `--target=$triple` : ``
end

# The family that an architecture's intrinsics (`llvm.<family>.`) are named by
llvm_family(arch::AbstractString) = startswith(arch, "aarch64") || startswith(arch, "arm64") ? "aarch64" : startswith(arch, "arm") ? "arm" : arch in ("x86_64", "i686", "i386", "x86") ? "x86" : startswith(arch, "wasm") ? "wasm" : arch
