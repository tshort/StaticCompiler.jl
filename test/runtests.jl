using Test
using StaticCompiler
using Libdl
using LinearAlgebra
using LoopVectorization
using ManualMemory
using Distributed
using StaticTools
using StrideArraysCore
using CodeInfoTools
using MacroTools
using LLD_jll

addprocs(1)
@everywhere using StaticCompiler, StrideArraysCore

const GROUP = get(ENV, "GROUP", "All")

@static if GROUP == "Core" || GROUP == "All"
    include("testcore.jl")
end

@static if GROUP == "Integration" || GROUP == "All"
    include("testintegration.jl")
end
