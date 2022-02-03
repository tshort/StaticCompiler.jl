using StaticCompiler
using Test
using Libdl
using LinearAlgebra
using LoopVectorization
using ManualMemory
using StrideArraysCore

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


fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2) # This needs to be defined globally due to https://github.com/JuliaLang/julia/issues/40990

@testset "Recursion" begin
    fib_ptr = generate_shlib_fptr(fib, (Int,))
    @test @ccall( $fib_ptr(10::Int) :: Int ) == 55

    # Trick to work around #40990
    _fib2(_fib2, n) = n <= 1 ? n : _fib2(_fib2, n-1) + _fib2(_fib2, n-2)
    fib2(n) = _fib2(_fib2, n)

    fib2_ptr = generate_shlib_fptr(fib2, (Int,))
    @test @ccall( $fib2_ptr(20::Int) :: Int ) == 6765
    
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
    array_sum_complex64_ptr = generate_shlib_fptr(array_sum, Tuple{Int, Vector{Complex{Float64}}})
    @test_skip ( @ccall $array_sum_complex_ptr(2::Int, [1.0+im, 1.0-im]::Vector{Complex{Float64}})::Complex{Float64} ) ≈ 2.0 
end


# Julia wants to treat Tuple (and other things like it) as plain bits, but LLVM wants to treat it as something with a pointer.
# We need to be careful to not send, nor receive an unwrapped Tuple to a compiled function
@testset "Send and receive Tuple" begin
    foo(u::Tuple) = 2 .* reverse(u) .- 1 # we can't just compile this as is. 

    # Make a mutating function that places the output into a Ref for the caller to grab:
    foo!(out::Ref{<:Tuple}, u::Tuple) = (out[] = foo(u); return nothing)

    foo_ptr = generate_shlib_fptr(foo!, Tuple{Base.RefValue{NTuple{3, Int}}, NTuple{3, Int}})
    out = Ref{NTuple{3, Int}}()
    # we wrap u in a ref when we send it to the binary because LLVM expects that :(
    u = Ref((1, 2, 3))
    (@ccall $foo_ptr(out::Ref{NTuple{3, Int}}, u::Ref{NTuple{3, Int}}) :: Nothing)

    @test out[] == foo(u[])
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

# I can't beleive this works.
@testset "LoopVectorization" begin
    function mul!(C, A, B)
        # note: @tturbo does NOT work
        @turbo for n ∈ indices((C,B), 2), m ∈ indices((C,A), 1)
            Cmn = zero(eltype(C))
            for k ∈ indices((A,B), (2,1))
                Cmn += A[m,k] * B[k,n]
            end
            C[m,n] = Cmn
        end
    end
    mul_ptr! = generate_shlib_fptr(mul!, Tuple{Matrix{Float64}, Matrix{Float64}, Matrix{Float64}})
    
    C = Array{Float64}(undef, 10, 12)
    A = rand(10, 11)
    B = rand(11, 12)

    @ccall $mul_ptr!(C::Matrix{Float64}, A::Matrix{Float64}, B::Matrix{Float64}) :: Nothing
    @test C ≈ A*B
end

# This is a trick to get stack allocated arrays inside a function body (so long as they don't escape).
# This lets us have intermediate, mutable stack allocated arrays inside our 
@testset "Alloca" begin
    function f(N)
        # this can hold at most 100 Int values, if you use it for more, you'll segfault
        buf = ManualMemory.MemoryBuffer{100, Int}(undef)
        GC.@preserve buf begin
            # wrap the first N values in a PtrArray
            arr = PtrArray(pointer(buf), (N,))
            arr .= 1 # mutate the array to be all 1s
            sum(arr) # compute the sum. It is very imporatant that no references to arr escape the function body
        end
    end
    
    fptr = generate_shlib_fptr(f, Tuple{Int})
    @test (@ccall $fptr(20::Int) :: Int) == 20
    
end 


# data structures, dictionaries, tuples, named tuples
