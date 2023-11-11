using Test
using StaticCompiler
using Libdl
using LinearAlgebra
using LoopVectorization
using ManualMemory
using Distributed
using StaticTools
using StrideArraysCore
using MacroTools
using LLD_jll
using Bumper

addprocs(1)
@everywhere using StaticCompiler, StrideArraysCore

const GROUP = get(ENV, "GROUP", "All")

if GROUP == "Core" || GROUP == "All"
    include("testcore.jl")
end

if GROUP == "Integration" || GROUP == "All"
    include("testintegration.jl")
end
