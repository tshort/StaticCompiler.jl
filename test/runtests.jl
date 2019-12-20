using StaticCompiler
using Test
using LLVM
using Libdl

# dep: ]add Formatting
include("../helpers/src/CompilerUtils.jl")
# to init submodule:
# git submodule update --init --recursive
# to update submodule reference:
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
