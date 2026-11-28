# The libraries of MinGW-w64 for a Windows target, for linking by `LLDToolchain(:mingw; sysroot)`: the artifact of `Mingw_jll` for the architecture of the target, fetched for any host (it is the start files and the
# libraries of the C runtime and of Windows, which are data: the artifact is listed for Windows platforms, and is the same wherever it is fetched).
module StaticCompilerMingwExt

using StaticCompiler: StaticCompiler, StaticTarget
using Mingw_jll: Mingw_jll
using Pkg: Pkg
using Base.BinaryPlatforms: Platform, arch

function StaticCompiler.mingw_sysroot(platform::Platform)
    platform = Platform(arch(platform), "windows") # (the one that `Mingw_jll` has: of the architecture)
    toml = joinpath(dirname(dirname(pathof(Mingw_jll))), "Artifacts.toml")
    meta = Pkg.Artifacts.artifact_meta("Mingw", toml; platform)
    meta === nothing && throw(ArgumentError("`Mingw_jll` has no artifact for $platform (it has x86_64 and i686)"))
    Pkg.Artifacts.ensure_artifact_installed("Mingw", meta, toml; platform)
    return Pkg.Artifacts.artifact_path(Base.SHA1(meta["git-tree-sha1"]))
end

function StaticCompiler.mingw_sysroot(triple::AbstractString)
    # (`Platform` parses `x86_64-w64-mingw32`, and not `x86_64-w64-windows-gnu`, the name that LLVM has for it: the architecture is what it is for)
    occursin(r"mingw|windows", triple) || throw(ArgumentError("`$triple` is not a triple of a platform of Windows"))
    arch = String(first(split(triple, '-'))) # (`Platform` takes a `String`)
    return StaticCompiler.mingw_sysroot(Platform(arch == "amd64" ? "x86_64" : arch, "windows"))
end

StaticCompiler.mingw_sysroot(target::StaticTarget) = StaticCompiler.mingw_sysroot(StaticCompiler.target_triple(target))

end
