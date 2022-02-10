using StaticCompiler
using Test
using Libdl
using LinearAlgebra
using LoopVectorization
using ManualMemory
using StrideArraysCore
using Distributed

addprocs(1)
@everywhere using StaticCompiler

remote_load_call(path, args...) = fetch(@spawnat 2 load_function(path)(args...))

@testset "Basics" begin

    simple_sum(x) = x + one(typeof(x))

    # This probably needs a macro
    for T ∈ (Int, Float64, Int32, Float32, Int16, Float16)
        _, path, = compile(simple_sum, (T,))
        @test remote_load_call(path, T(1)) == T(2)
    end
end


fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2) # This needs to be defined globally due to https://github.com/JuliaLang/julia/issues/40990

@testset "Recursion" begin
    _, path = compile(fib, (Int,))
    @test remote_load_call(path, 10) == fib(10)

    # Trick to work around #40990
    _fib2(_fib2, n) = n <= 1 ? n : _fib2(_fib2, n-1) + _fib2(_fib2, n-2)
    fib2(n) = _fib2(_fib2, n)

    _, path = compile(fib2, (Int,))
    @test remote_load_call(path, 20) == fib(20)
    #@test compile(fib2, (Int,))[1](20) == fib(20)
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
    _, path = compile(sum_first_N_int, (Int,))
    @test remote_load_call(path, 10) == 55

    function sum_first_N_float64(N)
        s = Float64(0)
        for a in 1:N
            s += Float64(a)
        end
        s
    end
    _, path = compile(sum_first_N_float64, (Int,))
    @test remote_load_call(path, 10) == 55.

    function sum_first_N_int_inbounds(N)
        s = 0
        @inbounds for a in 1:N
            s += a
        end
        s
    end
    _, path = compile(sum_first_N_int_inbounds, (Int,))
    @test remote_load_call(path, 10) == 55

    function sum_first_N_float64_inbounds(N)
        s = Float64(0)
        @inbounds for a in 1:N
            s += Float64(a)
        end
        s
    end
    _, path = compile(sum_first_N_float64_inbounds, (Int,))
    @test remote_load_call(path, 10) == 55.
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
    for T ∈ (Int, Complex{Float32}, Complex{Float64})
        _, path = compile(array_sum, (Int, Vector{T}))
        @test remote_load_call(path, 10, T.(1:10)) == T(55)
    end

    # @test (10, Int.(1:10)) == 55
    # @test compile(array_sum, (Int, Vector{Complex{Float32}}))[1](10, Complex{Float32}.(1:10)) == 55f0 + 0f0im
    # @test compile(array_sum, (Int, Vector{Complex{Float64}}))[1](10, Complex{Float64}.(1:10)) == 55f0 + 0f0im
end


# Julia wants to treat Tuple (and other things like it) as plain bits, but LLVM wants to treat it as something with a pointer.
# We need to be careful to not send, nor receive an unwrapped Tuple to a compiled function.
# The interface made in `compile` should handle this fine.
@testset "Send and receive Tuple" begin
    foo(u::Tuple) = 2 .* reverse(u) .- 1

    _, path = compile(foo, (NTuple{3, Int},))
    @test remote_load_call(path, (1, 2, 3)) == (5, 3, 1)
end


# Just to call external libraries
@testset "BLAS" begin
    function mydot(a::Vector{Float64})
        N = length(a)
        BLAS.dot(N, a, 1, a, 1)
    end
    a = [1.0, 2.0]
    mydot_compiled, path = compile(mydot, (Vector{Float64},))
    @test_skip remote_load_call(path, a) == 5.0 # this needs a relocatable pointer to work
    @test mydot_compiled(a) == 5.0
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

    C = Array{Float64}(undef, 10, 12)
    A = rand(10, 11)
    B = rand(11, 12)

    _, path = compile(mul!, (Matrix{Float64}, Matrix{Float64}, Matrix{Float64},))
    # remote_load_call(path, C, A, B) This won't work because @spawnat copies C
    C .= fetch(@spawnat 2 (load_function(path)(C, A, B); C))
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
    _, path = compile(f, (Int,))
    @test remote_load_call(path, 20) == 20
end

@testset "Standalone Executables" begin
    # Minimal test with no `llvmcall`
    @inline function foo()
        v = 0.0
        n = 1000
        for i=1:n
            v += sqrt(n)
        end
        return 0
    end

    filepath = compile_executable(foo, (), tempdir())

    r = run(`$filepath`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0

    @static if VERSION>v"1.8.0-DEV" # The llvmcall here only works on 1.8+
        @inline function puts(s::Ptr{UInt8}) # Can't use Base.println because it allocates
            Base.llvmcall(("""
            ; External declaration of the puts function
            declare i32 @puts(i8* nocapture) nounwind

            define i32 @main(i8*) {
            entry:
               %call = call i32 (i8*) @puts(i8* %0)
               ret i32 0
            }
            """, "main"), Int32, Tuple{Ptr{UInt8}}, s)
        end

        @inline function print_args(argc::Int, argv::Ptr{Ptr{UInt8}})
            for i=1:argc
                # Get pointer
                p = unsafe_load(argv, i)
                # Print string at pointer location (which fortunately already exists isn't tracked by the GC)
                puts(p)
            end
            return 0
        end

        filepath = compile_executable(print_args, (Int, Ptr{Ptr{UInt8}}), tempdir())

        r = run(`$filepath Hello, world!`);
        @test isa(r, Base.Process)
        @test r.exitcode == 0
    end
end
# data structures, dictionaries, tuples, named tuples
