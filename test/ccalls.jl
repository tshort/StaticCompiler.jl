
include("jlrun.jl")

# d = find_ccalls(Threads.nthreads, Tuple{})
# d = find_ccalls(time, Tuple{})
# d = find_ccalls(muladd, Tuple{Array{Float64,2},Array{Float64,2},Array{Float64,2}})

f1() = ccall(:jl_errno, Int, (Int,), 11)
f2() = ccall(:jl_errno, Int, (Int, Int), 21, 22)
f3() = ccall(:jl_errno, Int, (Int, Int, Int), 31, 32, 33)

@testset "ccalls" begin
    m1 = irgen(f1, Tuple{})
    m2 = irgen(f2, Tuple{})
    m3 = irgen(f3, Tuple{})
    LLVM.verify(m1)
    LLVM.verify(m2)
    LLVM.verify(m3)
    @test f1() == @jlrun f1()
    @test f2() == @jlrun f2()
    @test f3() == @jlrun f3()
end


function f()
    n = Int(unsafe_load(cglobal(:jl_n_threads, Cint)))
    return 2n
end

@testset "cglobal" begin
    m = irgen(f, Tuple{})
    LLVM.verify(m)
    @test f() == @jlrun f()
end

@testset "extern" begin
    f() = @extern(:time, Cvoid, (Ptr{Cvoid},), C_NULL)
    m = irgen(f, Tuple{})
    LLVM.verify(m)
    @test "time" in [name(f) for f in LLVM.functions(m)]
end
