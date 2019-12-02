include("jlrun.jl")

# @testset "serialize" begin
#     ctx = StaticCompiler.SerializeContext()
#     a = Any["abcdg", ["hi", "bye"], 3333, Int32(44), 314f0, 3.14, (1, 3.3f0), Core.svec(9.9, 9), :sym, :sym, :a]
#     e = StaticCompiler.serialize(ctx, a)
#     g = eval(:(Vptr -> $e))
#     v = take!(ctx.io)
#     GC.enable(false)
#     res = g(pointer(v))
#     GC.enable(true)
#     @test res == a
# end


# const a = ["abcdg", "asdfl", 123, 3.14, ["a", "asdf"], (1, 3.63), [1, 3.63]]
const a = ["abcdg", "asdxf"]
const b = "B"
const x = [1.33, 35.0]
const xi = [3, 5]

f(x) = @inbounds a[1][3] > b[1] ? 2x : x
g(i) = @inbounds x[1] > x[2] ? 2i : i
h(i) = @inbounds xi[1] == 3 ? i : 2i

@testset "globals" begin
    @test f(3) == @jlrun f(3)
    @test g(3) == @jlrun g(3)
    @test h(3) == @jlrun h(3)
end

f() = Complex{Float64}
g(@nospecialize(x)) = isa(x, Number) ? 1 : 0

@testset "type" begin
    @test string(@jlrun f()) == "Complex{Float64}"
    res = g(4.0im)
end
