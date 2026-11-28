## Linking: how the object code of a target becomes an executable or a shared library

@doc """
    Toolchain

How a target is linked. [`link`](@ref) and [`output_name`](@ref) have a method for each type; new targets (another system, another kind of executable) are new types with those two methods.
`CCToolchain` (a C compiler that compiles and links, as before) is the default, [`LLDToolchain`](@ref) links objects by itself (for a Linux or WebAssembly target that the host's compiler can not link for).
Give a target its toolchain by `StaticTarget(...; toolchain = ...)` (or `StaticTarget(target; toolchain = ...)`, a copy that has another).
""" Toolchain

"""
    CCToolchain(cc::Cmd)

Link by a C compiler driver (`clang` by default): the driver compiles what it is given, objects or LLVM IR (`.ll`), and links it. This is how executables and shared libraries were made before toolchains,
and it still is for the host and for any target that has a driver of its own (`StaticTarget(...; toolchain = CCToolchain(cc))`).
"""
struct CCToolchain <: Toolchain
    cc::Cmd
    builtins::Bool
end
CCToolchain(cc::Cmd; builtins::Bool = false) = CCToolchain(cc, builtins)
CCToolchain(cc::AbstractString; builtins::Bool = false) = CCToolchain(`$cc`; builtins)
Base.:(==)(a::CCToolchain, b::CCToolchain) = a.cc == b.cc && a.builtins == b.builtins

"""
    LLDToolchain(flavor; sysroot = nothing, dynamic_linker = nothing, libs = nothing, flags = ``, builtins = true)

Link objects with the `lld` that Julia has, without a C compiler or its driver. `flavor` is
* `:gnu`: ELF for Linux. The start files and the libraries of the C library are in `sysroot`, a directory that has the `lib` of a glibc (the `Glibc_jll` artifact provides one). See [`glibc_sysroot`](@ref).
* `:darwin`: Mach-O for macOS. `sysroot` is the SDK (by default that of Xcode `xcrun --show-sdk-path`); where the host has none, an SDK must be given. See [`macos_sdk`](@ref).
* `:mingw`: PE for Windows, with the libraries of MinGW-w64 in `sysroot` (the `Mingw_jll` artifact provides one). See [`mingw_sysroot`](@ref).
* `:wasm`: WebAssembly, a `.wasm` module that exports the entry point and imports the rest.

`libs` are the libraries that are linked with (the defaults are those of the flavor), and `flags` are added to the command of the linker. With `builtins`, the object has the definitions of what the code generator calls and no library of the toolchain has (`__udivti3`, `__extendhfsf2`, ...: see [`add_builtins!`](@ref)).
Nothing makes a `main`: the object has one (see the `main_wrapper` of [`generate_obj`](@ref); [`generate_executable`](@ref) asks for it when the toolchain is not a `CCToolchain`).
"""
struct LLDToolchain <: Toolchain
    flavor::Symbol
    sysroot::Union{String,Nothing}
    dynamic_linker::Union{String,Nothing}
    libs::Vector{String}
    flags::Cmd
    builtins::Bool
end
# the libraries that a flavor of `LLDToolchain` links with, if none are given
const DEFAULT_LLD_LIBS = Dict(:gnu => ["c", "m", "dl", "pthread"], # (`dl` and `pthread` are libraries of their own before glibc 2.34, and empty ones in it)
                               :darwin => ["System"], :wasm => String[],
                              :mingw => ["mingw32", "mingwex", "moldname", "msvcrt", "advapi32", "shell32", "user32", "kernel32"])

function LLDToolchain(flavor::Symbol; sysroot = nothing, dynamic_linker = nothing, libs = nothing, flags = ``, builtins::Bool = true)
    flavor in keys(DEFAULT_LLD_LIBS) || throw(ArgumentError("the flavor of `LLDToolchain` is `:gnu`, `:darwin`, `:mingw` or `:wasm`, not `$(repr(flavor))`"))
    libs === nothing && (libs = DEFAULT_LLD_LIBS[flavor])
    return LLDToolchain(flavor, isnothing(sysroot) ? nothing : String(sysroot), isnothing(dynamic_linker) ? nothing : String(dynamic_linker), String.(libs), flags isa Cmd ? flags : `$flags`, builtins)
end

# Ensure toolchain is either a Toolchain or Nothing
as_toolchain(x::Toolchain) = x
as_toolchain(x::Cmd) = CCToolchain(x)
as_toolchain(x::AbstractString) = CCToolchain(x)
as_toolchain(::Nothing) = nothing


"""
    output_name(toolchain, target, name; kind = :executable) -> String

The file name of what is made from `name` for the target: `name.exe` for a Windows executable, `name.wasm` for WebAssembly, the shared library extension of the target for `kind = :shared`.
"""
output_name(::Toolchain, target, name::AbstractString; kind::Symbol = :executable) =
    kind === :shared ? "$name.$(dlext(target))" : iswindows(target) ? "$name.exe" : String(name)
output_name(tc::LLDToolchain, target, name::AbstractString; kind::Symbol = :executable) =
    tc.flavor === :wasm ? "$name.wasm" :
    tc.flavor === :darwin ? (kind === :shared ? "$name.dylib" : String(name)) :
    tc.flavor === :mingw ? (kind === :shared ? "$name.dll" : "$name.exe") :
    kind === :shared ? "$name.so" : String(name)

# whether the objects that the toolchain links need the builtins in them (`add_builtins!`)
uses_builtins(tc::Union{CCToolchain,LLDToolchain}) = tc.builtins
uses_builtins(::Union{Toolchain,Nothing}) = false

"""
    glibc_sysroot(platform_or_triple_or_target) -> String

The directory of the C library of a Linux target (for `LLDToolchain(:gnu; sysroot = ...)`): the artifact of `Glibc_jll` for its architecture, which is fetched if it is not there, for any host. Needs `using Glibc_jll, Pkg`.

**Which glibc** is the version of the `Glibc_jll` of the environment (see [`glibc_version`](@ref)), and a program that is linked with it needs that glibc or a newer one where it runs. The newest, 2.35, which is the default,
makes programs that need glibc 2.34 or newer (Ubuntu 22.04, Debian 12, ...): they do not run on older systems (Ubuntu 20.04, RHEL 8, ...). To make programs that run on older ones, pin an older `Glibc_jll` in the environment
(`Pkg.add(name = "Glibc_jll", version = "2.17")`, or in `[compat]`): 2.17.1 has x86-64, i686 and ppc64le, and 2.19.1 also aarch64, armv7l and armv6l, and programs that are linked with them need only glibc 2.17.
What a newer glibc has is not there to link with: the functions that were added after the pinned version (`posix_spawn_file_actions_addchdir_np` of 2.29, for example) are undefined symbols.
"""
function glibc_sysroot end

"""
    glibc_version(sysroot) -> Union{VersionNumber,Nothing}

The version of the glibc that a sysroot has (`nothing` if it has none that is known): the version that programs that are linked with it need, or a newer one, where they run. It is read from the banner of its `libc.so.6`.
"""
function glibc_version(sysroot::AbstractString)
    libc = try; joinpath(crt_directory(sysroot), "libc.so.6"); catch; return nothing; end
    isfile(libc) || return nothing
    bytes = read(libc)
    marker = Vector{UInt8}("release version ")
    i = findfirst(marker, bytes)
    i === nothing && return nothing
    text = String(bytes[last(i)+1:min(end, last(i) + 16)])
    m = match(r"^(\d+)\.(\d+)", text)
    return m === nothing ? nothing : VersionNumber(parse(Int, m.captures[1]), parse(Int, m.captures[2]))
end

"""
    mingw_sysroot(platform_or_triple_or_target) -> String

The directory of the MinGW-w64 libraries of a Windows target (for `LLDToolchain(:mingw; sysroot = ...)`): the artifact of `Mingw_jll` for its architecture, which is fetched if it is not there, for any host.
Needs `using Mingw_jll, Pkg`.
"""
function mingw_sysroot end

"""
    macos_sdk() -> String

The SDK of macOS that a program for macOS is linked with (for `LLDToolchain(:darwin; sysroot = ...)`, which uses it when it has no `sysroot`): the environment variable `SDKROOT`, or that of Xcode (`xcrun --show-sdk-path`) on a Mac.
Where the host has neither, the SDK is given to `LLDToolchain` as `sysroot`: Apple's license has it used on Apple hardware, and a copy of one has to be provided (for example `MacOSX11.3.sdk.tar.xz` of
[phracker/MacOSX-SDKs](https://github.com/phracker/MacOSX-SDKs), which BinaryBuilder uses).
"""
function macos_sdk()
    haskey(ENV, "SDKROOT") && return ENV["SDKROOT"]
    sdk = xcode_sdk()
    isnothing(sdk) || return sdk
    throw(ArgumentError("no SDK of macOS is known: give `sysroot = ...` to `LLDToolchain(:darwin)` (the directory of an SDK, like `MacOSX11.3.sdk`), or set `SDKROOT`"))
end

# The SDK of Xcode (`xcrun --show-sdk-path`), or `nothing` where there is none (not a Mac, or no Xcode or Command Line Tools: `xcrun` fails). Asked once: the command takes some milliseconds,
# and a compile asks for it several times (the selected Xcode does not change in a session; `SDKROOT` is read each time, and is not what is remembered).
const XCODE_SDK = Ref{Union{String,Nothing}}()
const XCODE_SDK_KNOWN = Ref(false)
function xcode_sdk()
    if !XCODE_SDK_KNOWN[]
        XCODE_SDK[] = if Sys.isapple() && !isnothing(Sys.which("xcrun"))
            errors = IOBuffer()
            try
                String(strip(read(pipeline(`xcrun --show-sdk-path`; stderr = errors), String)))
            catch err
                err isa ProcessFailedException || rethrow()
                @warn """`xcrun --show-sdk-path` failed, so the SDK of macOS cannot be found, and programs for macOS cannot be linked with it.
                    $(strip(String(take!(errors))))
                    To fix this, do one of:
                      * install the Command Line Tools: run `xcode-select --install` in a terminal
                      * select an installed Xcode: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
                      * point `SDKROOT` at an SDK, e.g. `ENV["SDKROOT"] = "/path/to/MacOSX11.3.sdk"` (or pass `sysroot = ...` to `LLDToolchain(:darwin)`)
                    Meanwhile the system `clang` is used, with whatever SDK it finds itself. (This warning is shown once.)""" maxlog = 1
                nothing
            end
        else
            nothing
        end
        XCODE_SDK_KNOWN[] = true
    end
    return XCODE_SDK[]
end

# the version of an SDK, which is in its `SDKSettings.json` (and `plist`)
function sdk_version(sdk::AbstractString)
    for file in ("SDKSettings.json", "SDKSettings.plist")
        path = joinpath(sdk, file)
        isfile(path) || continue
        m = match(r"\"Version\"\s*:\s*\"(\d+(?:\.\d+)*)\"|<key>Version</key>\s*<string>(\d+(?:\.\d+)*)</string>", read(path, String))
        m === nothing || return something(m.captures[1], m.captures[2])
    end
    return "11.0"
end

# The toolchain of a target: its own, or the default: the host's C compiler driver
default_toolchain(::StaticTarget) = CCToolchain(clang())
toolchain(target::StaticTarget) = isnothing(target.toolchain) ? default_toolchain(target) : target.toolchain # (not `something`, which would find the default, and run `xcrun`, whatever the target has)

# Generally prefer Clang_jll clang (which should probably be at least as new as Julia's LLVM)
# and fall back to the system one on platforms where Clang_jll is not available or not expected to work
function clang()
    Clang_jll.is_available() || return `clang` # Fall back to system clang if Clang_jll is not available
    cmd = Clang_jll.clang()
    # Clang_jll may not know where to find the macOS SDK (e.g. for `-lSystem`)
    if Sys.isapple() && !haskey(ENV, "SDKROOT")
        sdk = xcode_sdk()
        isnothing(sdk) && return `clang` # Fall back to system clang if we can't figure out the SDK path
        cmd = addenv(cmd, "SDKROOT" => sdk)
    end
    return cmd
end


## lld

# the directory of a sysroot that has the start files of the C library
function crt_directory(sysroot::AbstractString)
    for d in ("lib", "usr/lib", "lib64", "usr/lib64", "usr/lib/aarch64-linux-gnu", "usr/lib/x86_64-linux-gnu", "lib/aarch64-linux-gnu", "lib/x86_64-linux-gnu")
        isfile(joinpath(sysroot, d, "crt1.o")) && return joinpath(sysroot, d)
    end
    throw(ArgumentError("`$sysroot` has no `crt1.o`: the `sysroot` of a `:gnu` `LLDToolchain` is a directory that has the `lib` of a glibc (the `Glibc_jll` artifact for the platform of the target is one)"))
end

# the loader that a program of the architecture asks for, where it is on the system that it runs on
function default_dynamic_linker(target::StaticTarget)
    a = llvm_family(first(split(target_triple(target), '-')))
    a == "x86" && return "/lib64/ld-linux-x86-64.so.2"
    a == "aarch64" && return "/lib/ld-linux-aarch64.so.1"
    throw(ArgumentError("no dynamic linker is known for $(target_triple(target)): give `dynamic_linker` to `LLDToolchain`"))
end