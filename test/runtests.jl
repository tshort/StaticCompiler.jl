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

@testset "Recursion" begin
    fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)
    # This works on the REPL but fails here
    @test_skip ccall(generate_shlib_fptr(fib, (Int,)), Int, (Int,), 10) == 55
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

    arr = collect(1:10)
    function array_sum(n, A)
        s = zero(eltype(A))
        for i in 1:n
            s += A[i]
        end
        s
    end

    #This segfaults, not sure if this is how you pass around arrays
    @test_skip ccall(generate_shlib_fptr(array_sum, (Csize_t, Ptr{Float64})), Int, (Csize_t, Ptr{Float64}), length(arr), arr) == 55

end

# Just to call external libraries
@testset "BLAS" begin
    function mydot(N) 
        a = Float64.(1:N)
        BLAS.dot(N, a, 1, a, 1)
    end
    @test_skip ccall(generate_shlib_fptr(mydot, (Int,)), Float64, (Int,), 2) == 5.
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
