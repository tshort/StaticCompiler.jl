# The C library of a Linux target, for linking by `LLDToolchain(:gnu; sysroot)`: the artifact of `Glibc_jll` for the platform of the target, fetched for any host.
module StaticCompilerGlibcExt

using StaticCompiler: StaticCompiler, StaticTarget
using Glibc_jll: Glibc_jll
using Pkg: Pkg
using Base.BinaryPlatforms: Platform, arch

function StaticCompiler.glibc_sysroot(platform::Platform)
    platform = Platform(arch(platform), "linux"; libc = "glibc") # (the one that `Glibc_jll` has: of the architecture)
    toml = joinpath(dirname(dirname(pathof(Glibc_jll))), "Artifacts.toml")
    meta = Pkg.Artifacts.artifact_meta("Glibc", toml; platform)
    meta === nothing && throw(ArgumentError("`Glibc_jll` has no artifact for $platform"))
    Pkg.Artifacts.ensure_artifact_installed("Glibc", meta, toml; platform)
    return Pkg.Artifacts.artifact_path(Base.SHA1(meta["git-tree-sha1"]))
end

function StaticCompiler.glibc_sysroot(triple::AbstractString)
    platform = tryparse(Platform, triple)
    platform === nothing && throw(ArgumentError("`$triple` is not a triple of a platform that has a glibc"))
    return StaticCompiler.glibc_sysroot(platform)
end

StaticCompiler.glibc_sysroot(target::StaticTarget) = StaticCompiler.glibc_sysroot(StaticCompiler.target_triple(target))

end
