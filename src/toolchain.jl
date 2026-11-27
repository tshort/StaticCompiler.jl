## Linking: how the object code of a target becomes an executable or a shared library

@doc """
    Toolchain

How a target is linked. [`link`](@ref) and [`output_name`](@ref) have a method for each type; new targets (another system, another kind of executable) are new types with those two methods.
`Driver` (a C compiler that compiles and links, as before) is the default, [`LLD`](@ref) links objects by itself (for a Linux or WebAssembly target that the host's compiler can not link for).
Give a target its toolchain by `StaticTarget(...; toolchain = ...)` or `set_toolchain!`.
""" Toolchain

"""
    Driver(cc::Cmd)

Link by a C compiler driver (`clang` by default): the driver compiles what it is given, objects or LLVM IR (`.ll`), and links it. This is how executables and shared libraries were made before toolchains,
and it still is for the host and for any target that has a driver of its own (`set_compiler!`).
"""
struct Driver <: Toolchain
    cc::Cmd
    builtins::Bool
end
Driver(cc::Cmd; builtins::Bool = false) = Driver(cc, builtins)
Driver(cc::AbstractString; builtins::Bool = false) = Driver(`$cc`; builtins)
Base.:(==)(a::Driver, b::Driver) = a.cc == b.cc && a.builtins == b.builtins

"""
    LLD(flavor; sysroot = nothing, dynamic_linker = nothing, libs = ["c", "m", "dl"], flags = ``, builtins = true)

Link objects with the `lld` that Julia has, without a C compiler or its driver. `flavor` is `:gnu` (ELF, Linux: the start files and the libraries of the C library are in `sysroot`, a directory that has the `lib` of a glibc,
which the `Glibc_jll` artifact of the target's platform is) or `:wasm` (WebAssembly: a `.wasm` module that exports the entry point and imports the rest). `flags` are added to the command of the linker. With `builtins`, the object has the definitions of what the code generator calls and no library of the toolchain has (`__udivti3`, `__extendhfsf2`, ...: see [`add_builtins!`](@ref)).
Nothing makes a `main`: the object has one (see the `main_wrapper` of [`generate_obj`](@ref); [`generate_executable`](@ref) asks for it when the toolchain is not a `Driver`).
"""
struct LLD <: Toolchain
    flavor::Symbol
    sysroot::Union{String,Nothing}
    dynamic_linker::Union{String,Nothing}
    libs::Vector{String}
    flags::Cmd
    builtins::Bool
end
function LLD(flavor::Symbol; sysroot = nothing, dynamic_linker = nothing, libs = ["c", "m", "dl"], flags = ``, builtins::Bool = true)
    flavor in (:gnu, :wasm) || throw(ArgumentError("the flavor of `LLD` is `:gnu` or `:wasm`, not `$(repr(flavor))`"))
    return LLD(flavor, isnothing(sysroot) ? nothing : String(sysroot), isnothing(dynamic_linker) ? nothing : String(dynamic_linker), String.(libs), flags isa Cmd ? flags : `$flags`, builtins)
end

# (what a toolchain is made from: a toolchain, or the C compiler of a `Driver`)
as_toolchain(x::Toolchain) = x
as_toolchain(x::Cmd) = Driver(x)
as_toolchain(x::AbstractString) = Driver(x)
as_toolchain(::Nothing) = nothing


"""
    output_name(toolchain, target, name; kind = :executable) -> String

The file name of what is made from `name` for the target: `name.exe` for a Windows executable, `name.wasm` for WebAssembly, the shared library extension of the target for `kind = :shared`.
"""
output_name(::Toolchain, target, name::AbstractString; kind::Symbol = :executable) =
    kind === :shared ? "$name.$(dlext(target))" : iswindows(target) ? "$name.exe" : String(name)
output_name(tc::LLD, target, name::AbstractString; kind::Symbol = :executable) =
    tc.flavor === :wasm ? "$name.wasm" : kind === :shared ? "$name.so" : String(name)

# whether the objects that the toolchain links need the builtins in them (`add_builtins!`)
uses_builtins(tc::Union{Driver,LLD}) = tc.builtins
uses_builtins(::Union{Toolchain,Nothing}) = false

"""
    glibc_sysroot(platform_or_triple_or_target) -> String

The directory of the C library of a Linux target (for `LLD(:gnu; sysroot = ...)`): the artifact of `Glibc_jll` for its architecture, which is fetched if it is not there, for any host.
Needs `using Glibc_jll, Pkg`.
"""
function glibc_sysroot end

# The toolchain of a target: its own, or the default: the host's C compiler driver
default_toolchain(::StaticTarget) = Driver(clang())
toolchain(target::StaticTarget) = something(target.toolchain, default_toolchain(target))

# Generally prefer Clang_jll clang (which should probably be at least as new as Julia's LLVM)
# and fall back to the system one on platforms where Clang_jll is not available or not expected to work
function clang()
    Clang_jll.is_available() || return `clang` # Fall back to system clang if Clang_jll is not available
    cmd = Clang_jll.clang()
    # Clang_jll may not know where to find the macOS SDK (e.g. for `-lSystem`)
    if Sys.isapple() && !haskey(ENV, "SDKROOT") 
        isnothing(Sys.which("xcrun")) && return `clang` # Fall back to system clang if we can't figure out the SDK path
        cmd = addenv(cmd, "SDKROOT" => readchomp(`xcrun --show-sdk-path`))
    end
    return cmd
end


## lld

# the directory of a sysroot that has the start files of the C library
function crt_directory(sysroot::AbstractString)
    for d in ("lib", "usr/lib", "lib64", "usr/lib64", "usr/lib/aarch64-linux-gnu", "usr/lib/x86_64-linux-gnu", "lib/aarch64-linux-gnu", "lib/x86_64-linux-gnu")
        isfile(joinpath(sysroot, d, "crt1.o")) && return joinpath(sysroot, d)
    end
    throw(ArgumentError("`$sysroot` has no `crt1.o`: the `sysroot` of a `:gnu` `LLD` is a directory that has the `lib` of a glibc (the `Glibc_jll` artifact for the platform of the target is one)"))
end

# the loader that a program of the architecture asks for, where it is on the system that it runs on
function default_dynamic_linker(target::StaticTarget)
    a = llvm_family(first(split(target_triple(target), '-')))
    a == "x86" && return "/lib64/ld-linux-x86-64.so.2"
    a == "aarch64" && return "/lib/ld-linux-aarch64.so.1"
    throw(ArgumentError("no dynamic linker is known for $(target_triple(target)): give `dynamic_linker` to `LLD`"))
end