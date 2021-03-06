using StaticCompiler
using Test



@testset "basics" begin
    f1(x) = x+1
    @test ccall(generate_shlib_fptr(f1, (Int,)), Int, (Int,), 1) == 2
end

