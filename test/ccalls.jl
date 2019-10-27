
include("jlrun.jl")

# d = find_ccalls(Threads.nthreads, Tuple{})
# d = find_ccalls(time, Tuple{})
# d = find_ccalls(muladd, Tuple{Array{Float64,2},Array{Float64,2},Array{Float64,2}})

@testset "ccalls" begin
    f1() = ccall(:usleep, Int, (Int,), 11)
    f2() = ccall(:usleep, Int, (Int, Int), 21, 22)
    f3() = ccall(:usleep, Int, (Int, Int, Int), 31, 32, 33)
    m1 = irgen(f1, Tuple{})
    m2 = irgen(f2, Tuple{})
    m3 = irgen(f3, Tuple{})
    LLVM.verify(m1)
    LLVM.verify(m2)
    LLVM.verify(m3)
end


function f()
    n = Int(unsafe_load(cglobal(:jl_n_threads, Cint)))
    return 2n
end

@testset "cglobal" begin
    m = irgen(f, Tuple{})
    @test f() == @jlrun f()
end
