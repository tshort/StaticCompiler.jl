using StaticCompiler
using Test
using Libdl
using LinearAlgebra

@testset "Basics" begin

    simple_sum(x) = x + one(typeof(x))

    # This probably needs a macro
    @test ccall(generate_shlib_fptr(simple_sum, (Int,)), Int, (Int,), 1) == Int(2)
    @test ccall(generate_shlib_fptr(simple_sum, (Float64,)), Float64, (Float64 ,), 1) == Float64(2)

    @test ccall(generate_shlib_fptr(simple_sum, (Int32,)), Int32, (Int32,), 1) == Int32(2)
    @test ccall(generate_shlib_fptr(simple_sum, (Float32,)), Float32, (Float32 ,), 1) == Float16(2)

    @test ccall(generate_shlib_fptr(simple_sum, (Int16,)), Int16, (Int16,), 1) == Int16(2)
    @test ccall(generate_shlib_fptr(simple_sum, (Float16,)), Float16, (Float16 ,), 1) == Float16(2)

end

fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2) # for some reason, if this is defined in the testset, it segfaults

@testset "Recursion" begin
    # This works on the REPL but fails here
    fib_ptr = generate_shlib_fptr(fib, (Int,))
    @test @ccall( $fib_ptr(10::Int) :: Int ) == 55
end

# Call binaries for testing
# @testset "Generate binary" begin
#     fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)
#     libname = tempname() 
#     generate_shlib(fib, (Int,), libname)
#     ptr = Libdl.dlopen(libname * "." * Libdl.dlext, Libdl.RTLD_LOCAL)
#     fptr = Libdl.dlsym(ptr, "julia_fib")
#     @assert fptr != C_NULL
#     # This works on REPL
#     @test_skip ccall(fptr, Int, (Int,), 10) == 55
# end


@testset "Loops" begin
    function sum_first_N_int(N)
        s = 0
        for a in 1:N
            s += a
        end
        s
    end
    @test ccall(generate_shlib_fptr(sum_first_N_int, (Int,)), Int, (Int,), 10) == 55

    function sum_first_N_float64(N)
        s = Float64(0)
        for a in 1:N
            s += Float64(a)
        end
        s
    end
    @test ccall(generate_shlib_fptr(sum_first_N_float64, (Int,)), Float64, (Int,), 10) == 55.

    function sum_first_N_int_inbounds(N)
        s = 0
        @inbounds for a in 1:N
            s += a
        end
        s
    end
    @test ccall(generate_shlib_fptr(sum_first_N_int_inbounds, (Int,)), Int, (Int,), 10) == 55


    function sum_first_N_float64_inbounds(N)
        s = Float64(0)
        @inbounds for a in 1:N
            s += Float64(a)
        end
        s
    end
    @test ccall(generate_shlib_fptr(sum_first_N_float64_inbounds, (Int,)), Float64, (Int,), 10) == 55.

end

# Arrays with different input types Int32, Int64, Float32, Float64, Complex?
@testset "Arrays" begin
    function array_sum(n, A)
        s = zero(eltype(A))
        for i in 1:n
            s += A[i]
        end
        s
    end
    
    array_sum_ptr = generate_shlib_fptr(array_sum, Tuple{Int, Vector{Int}})
    @test ( @ccall $array_sum_ptr(10::Int, collect(1:10)::Vector{Int})::Int ) == 55

    # this will segfault on my machine if I use 64 bit complex numbers!
    array_sum_complex_ptr = generate_shlib_fptr(array_sum, Tuple{Int, Vector{Complex{Float32}}})
    @test ( @ccall $array_sum_complex_ptr(2::Int, [1f0+im, 1f0-im]::Vector{Complex{Float32}})::Complex{Float32} ) ≈ 2.0

    #This will segfault 
    array_sum_complex64_ptr = generate_shlib_fptr(array_sum, Tuple{Int, Vector{Complex{Float642}}})
    @test_skip ( @ccall $array_sum_complex_ptr(2::Int, [1.0+im, 1.0-im]::Vector{Complex{Float64}})::Complex{Float64} ) ≈ 2.0 
end

# Just to call external libraries
@testset "BLAS" begin
    function mydot(a::Vector{Float64})
        N = length(a)
        BLAS.dot(N, a, 1, a, 1)
    end
    a = [1.0, 2.0]
    mydot_ptr = generate_shlib_fptr(mydot, Tuple{Vector{Float64}})
    @test @ccall( $mydot_ptr(a::Vector{Float64})::Float64 ) == 5.0
end


@testset "Hello World" begin
    function hello(N)
        println("Hello World $N")
        N
    end
    # How do I test this?
    # Also ... this segfaults
    @test_skip ccall(generate_shlib_fptr(hello, (Int,)), Int, (Int,), 1) == 1
end


# data structures, dictionaries, tuples, named tuples
# passing pointers?
# @inbounds LoopVectorization
