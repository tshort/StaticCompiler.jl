using Test
using StaticCompiler
using Libdl
using LinearAlgebra
using LoopVectorization
using ManualMemory
using Distributed
using StaticTools
using StrideArraysCore
addprocs(1)
@everywhere using StaticCompiler, StrideArraysCore

const GROUP = get(ENV, "GROUP", "All")

@static if GROUP == "Core" || GROUP == "All"
    include("testcore.jl")
end

@static if GROUP == "Integration" || GROUP == "All"
    include("testexecutables.jl")
end

@static if (GROUP == "Integration" || GROUP == "All") && Sys.ARCH == :x86_64
    include("testcosmopolitan.jl")
end
