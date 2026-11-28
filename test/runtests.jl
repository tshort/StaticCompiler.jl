using Test
using StaticCompiler
using Libdl
using LinearAlgebra
using LoopVectorization
using ManualMemory
using Distributed
using StaticTools
# using StrideArraysCore
using LLD_jll
using LLVM
using Glibc_jll, Mingw_jll, Pkg # (the extensions that have the C libraries of a Linux and a Windows target)
using Bumper

addprocs(1)
@everywhere using StaticCompiler, StrideArraysCore

const GROUP = get(ENV, "GROUP", "All")

if GROUP == "Core" || GROUP == "All"
   include("testcore.jl")
   include("testquirks.jl")
end

if GROUP == "Integration" || GROUP == "All"
    include("testintegration.jl")
end
