workdir = tempdir()



fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2) # This needs to be defined globally due to https://github.com/JuliaLang/julia/issues/40990

@testset "Standalone Dylibs" begin
    # Test function
    # (already defined)
    # fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)

    #Compile dylib
    name = string(nameof(fib))  # Use nameof instead of repr to get just "fib" instead of "Main.fib"
    filepath = compile_shlib(fib, (Int,), workdir, name, demangle=true)
    @test occursin("fib.$(Libdl.dlext)", filepath)
    # Open dylib manually
    ptr = Libdl.dlopen(filepath, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, name)
    @test fptr != C_NULL
    @test ccall(fptr, Int, (Int,), 10) == 55
    Libdl.dlclose(ptr)

    # As above, but without demangling
    filepath = compile_shlib(fib, (Int,), workdir, name, demangle=false)
    ptr = Libdl.dlopen(filepath, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, "julia_"*name)
    @test fptr != C_NULL
    @test ccall(fptr, Int, (Int,), 10) == 55
    Libdl.dlclose(ptr)
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

    filepath = compile_executable(foo, (), workdir, demangle=false)
    r = run(`$filepath`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0

    filepath = compile_executable(foo, (), workdir, demangle=true)
    r = run(`$filepath`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0

    filepath = compile_executable(foo, (), workdir, llvm_to_clang=true)
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

    filepath = compile_executable(print_args, (Int, Ptr{Ptr{UInt8}}), workdir, demangle=false)
    r = run(`$filepath Hello, world!`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0

    filepath = compile_executable(print_args, (Int, Ptr{Ptr{UInt8}}), workdir, demangle=true)
    r = run(`$filepath Hello, world!`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0

    filepath = compile_executable(print_args, (Int, Ptr{Ptr{UInt8}}), workdir, llvm_to_clang=true)
    r = run(`$filepath Hello, world!`);
    @test isa(r, Base.Process)
    @test r.exitcode == 0


    # Test that StaticCompiler properly rejects functions with bad type inference
    @inline foo_err() = UInt64(-1)
    # This should fail at compile time because foo_err() infers to Union{}
    @test_throws ErrorException compile_executable(foo_err, (), workdir, demangle=true)

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
    filepath = compile_shlib(funcs, workdir, demangle=true)

    ptr = Libdl.dlopen(filepath, Libdl.RTLD_LOCAL)

    fptr2 = Libdl.dlsym(ptr, "squaresquare")
    @test ccall(fptr2, Float64, (Float64,), 10.) == squaresquare(10.)

    fptr = Libdl.dlsym(ptr, "squaresquaresquare")
    @test ccall(fptr, Float64, (Float64,), 10.) == squaresquaresquare(10.)
    #Compile dylib
end


# Overlays

module SubFoo

rand(args...) = Base.rand(args...)

function f()
    x = rand()
    y = rand()
    return x + y
end

end

@device_override SubFoo.rand() = 2

# Lets test having another method table around
Base.Experimental.@MethodTable AnotherTable
Base.Experimental.@overlay AnotherTable SubFoo.rand() = 3

@testset "Overlays" begin
    Libdl.dlopen(compile_shlib(SubFoo.f, (), workdir)) do lib
        fptr = Libdl.dlsym(lib, "f")
        @test @ccall($fptr()::Int) == 4
    end
    Libdl.dlopen(compile_shlib(SubFoo.f, (), workdir; method_table=AnotherTable)) do lib
        fptr = Libdl.dlsym(lib, "f")
        @test @ccall($fptr()::Int) == 6
    end
end
