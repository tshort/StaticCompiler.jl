using StaticCompiler
using Test
using LLVM
using Libdl

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
