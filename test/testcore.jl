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
end

@testset "Array allocations" begin
    function f(N)
        v = Vector{Float64}(undef, N)
        for i ∈ eachindex(v)
            v[i] = i*i
        end
        v
    end
    _, path = compile(f, (Int,))
    @test remote_load_call(path, 5) == [1.0, 4.0, 9.0, 16.0, 25.0]
end

# This is also a good test of loading and storing from the same object
@testset "Load & Store Same object" begin
    global const x = Ref(0)
    counter() = x[] += 1
    _, path = compile(counter, ())
    @spawnat 2 global counter = load_function(path)
    @test fetch(@spawnat 2 counter()) == 1
    @test fetch(@spawnat 2 counter()) == 2
end

# This is also a good test of loading and storing from the same object
counter = let x = Ref(0)
    () -> x[] += 1
end
@testset "Closures" begin
    #this currently segfaults during compilation
    @test_skip begin
        _, path = compile(counter, ())
        @spawnat 2 global counter_comp = load_function(path)
        @test fetch(@spawnat 2 counter_comp()) == 1
        @test fetch(@spawnat 2 counter_comp()) == 2
    end
end


@testset "Error handling" begin
    _, path = compile(sqrt, (Int,))
    tsk = @spawnat 2 begin
        try
            load_function(path)(-1)
        catch e;
            e
        end
    end
    @test fetch(tsk) isa DomainError
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
    # Works locally for me, but not on CI. Need some improvements to pointer relocation to be robust.
    @test_skip remote_load_call(path, a) == 5.0
    @test mydot_compiled(a) ≈ 5.0

    # This will need some more work apparently
    @test_skip begin
        _, path = compile((*), (Matrix{Float64}, Matrix{Float64}))
        A, B = rand(10, 11), rand(11, 12)
        @test remote_load_call(path, A, B) ≈ A * B
    end
end


@testset "Strings" begin
    function hello(name)
        "Hello, " * name * "!"
    end
    hello_compiled, path = compile(hello, (String,))
    @test remote_load_call(path, "world") == "Hello, world!"

    # We'll need to be able to relocate a bunch of UV stuff for this, and deal with dynamic dispatch.
    @test_skip begin
        function hello(N)
            println("Hello World $N")
            N
        end

        hello_compiled, path = compile(hello, (Int,))
        @test_skip remote_load_call(path, 1) == 1
    end
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

@testset "Standalone Dylibs" begin
    # Test function
    # (already defined)
    # fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)

    #Compile dylib
    name = "julia_" * repr(fib)
    filepath = compile_shlib(fib, (Int,), "./", name)
    @test occursin("fib.$(Libdl.dlext)", filepath)

    # Open dylib
    ptr = Libdl.dlopen(filepath, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, name)
    @test fptr != C_NULL
    @test ccall(fptr, Int, (Int,), 10) == 55
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


    @inline function _puts(s::Ptr{UInt8}) # Can't use Base.println because it allocates
        Base.llvmcall(("""
        ; External declaration of the puts function
        declare i32 @puts(i8* nocapture) nounwind

        define i32 @main(i64) {
        entry:
           %ptr = inttoptr i64 %0 to i8*
           %status = call i32 (i8*) @puts(i8* %ptr)
           ret i32 %status
        }
        """, "main"), Int32, Tuple{Ptr{UInt8}}, s)
    end

    @inline function print_args(argc::Int, argv::Ptr{Ptr{UInt8}})
        for i=1:argc
            # Get pointer
            p = unsafe_load(argv, i)
            # Print string at pointer location (which fortunately already exists isn't tracked by the GC)
            _puts(p)
        end
        return 0
    end

    filepath = compile_executable(print_args, (Int, Ptr{Ptr{UInt8}}), tempdir())

    r = run(`$filepath Hello, world!`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0

    # Compile a function that definitely fails
    @inline foo_err() = UInt64(-1)
    filepath = compile_executable(foo_err, (), tempdir())
    @test isfile(filepath)
    status = -1
    try
        status = run(`filepath`)
    catch
        @info "foo_err: Task failed successfully!"
    end
    @test status === -1

end

@noinline square(n) = n*n

function squaresquare(n)
    square(square(n))
end

function squaresquaresquare(n)
    square(squaresquare(n))
end

@testset "Multiple Function Dylibs" begin
    funcs = [(squaresquare,(Float64,)), (squaresquaresquare,(Float64,))]
    filepath = compile_shlib(funcs, demangle=true)

    ptr = Libdl.dlopen(filepath, Libdl.RTLD_LOCAL)

    fptr2 = Libdl.dlsym(ptr, "squaresquare")
    @test ccall(fptr2, Float64, (Float64,), 10.) == squaresquare(10.)

    fptr = Libdl.dlsym(ptr, "squaresquaresquare")
    @test ccall(fptr, Float64, (Float64,), 10.) == squaresquaresquare(10.)
    #Compile dylib
end
