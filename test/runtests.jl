using StaticCompiler
using Test
using LLVM
using Libdl

# dep: ]add Formatting
include("../helpers/src/CompilerUtils.jl")
# to update:
# git submodule update --remote --merge
using Main.CompilerUtils

cd(@__DIR__)
@testset "ccalls" begin
    include("ccalls.jl")
end

@testset "globals" begin
    include("globals.jl")
end

@testset "others" begin
    include("others.jl")
end

@testset "standalone" begin
    include("standalone-exe.jl")
end
