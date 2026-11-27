workdir = tempdir()

fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2) # This needs to be defined globally due to https://github.com/JuliaLang/julia/issues/40990

@testset "Standalone Dylibs" begin
    # Test function
    # (already defined)
    # fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)

    #Compile dylib
    name = string(nameof(fib)) # repr(fib)
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


    @inline function _puts(s::Ptr{UInt8})
        Base.llvmcall(("""
        ; External declaration of the puts function
        declare i32 @puts(i8* nocapture) nounwind

        define i32 @main(i8* %str) #0 {
        entry:
           %status = call i32 (i8*) @puts(i8* %str)
           ret i32 %status
        }

        attributes #0 = { alwaysinline nounwind ssp uwtable }
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


    # Compile a function that definitely fails
    @inline foo_err() = UInt64(-1)
    filepath = compile_executable(foo_err, (), workdir, demangle=true)
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

@testset "The target is not the host" begin
    using Base.BinaryPlatforms
    # The target machine is the host's: only the platform is considered, and not every LLVM has the code generator of each platform
    t(p) = StaticCompiler.StaticTarget(p, StaticCompiler.StaticTarget().tm, nothing, false)
    # Ensure we are checking the target, no the host
    @test StaticCompiler.iswindows(t(Platform("x86_64", "windows"))) && !StaticCompiler.isapple(t(Platform("x86_64", "windows")))
    @test StaticCompiler.isapple(t(Platform("aarch64", "macos"))) && !StaticCompiler.iswindows(t(Platform("aarch64", "macos")))
    @test !StaticCompiler.iswindows(t(Platform("aarch64", "linux"))) && !StaticCompiler.isapple(t(Platform("aarch64", "linux")))
    # A triple that `Platform` does not parse
    wasm = StaticCompiler.StaticTarget("wasm32-unknown-unknown", "generic", "")
    @test isnothing(wasm.platform) && !StaticCompiler.iswindows(wasm) && !StaticCompiler.isapple(wasm)
end

@testset "LLVM IR as text" begin
    ir = StaticCompiler.generate_ir(fib, Tuple{Int})
    @test ir isa String && occursin("define", ir) && occursin("fib", ir) && occursin("target triple", ir)
    path, ir_path = StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibir"; emit_llvm_only = true)
    @test isfile(ir_path) && occursin("define", read(ir_path, String))
end

@testset "A target that Julia's LLVM has no code generator for" begin
    triple = "x86_64-unknown-linux-gnu"
    ir_target = StaticCompiler.StaticTarget(tryparse(Base.BinaryPlatforms.Platform, triple), StaticCompiler.host_generic_machine(), nothing, triple, false)
    @test StaticCompiler.target_triple(ir_target) == triple && StaticCompiler.needs_ir(ir_target)
    @test occursin("--target=$triple", string(StaticCompiler.clang_target_flags(ir_target)))
    ir = StaticCompiler.generate_ir(fib, Tuple{Int}; target = ir_target)
    @test occursin("target triple = \"$triple\"", ir) && !occursin("target datalayout", ir) && !occursin("target-cpu", ir) && !occursin("target-features", ir)
    @test_throws ArgumentError StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibobj"; target = ir_target)
    path, ir_path = StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibir"; target = ir_target, emit_llvm_only = true)
    @test occursin("target triple = \"$triple\"", read(ir_path, String))
    # the host's own target is untouched
    host = StaticCompiler.StaticTarget()
    @test isnothing(host.ir_triple) && StaticCompiler.needs_ir(host) == Sys.iswindows()
    @test isempty(StaticCompiler.clang_target_flags(host))
    # where there is no code generator for the triple, the constructors make such a target
    for t in ("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu", "riscv64-unknown-linux-gnu")
        has_backend = try; LLVM.Target(triple = t); true; catch; false; end
        has_backend || @test StaticCompiler.StaticTarget(t, "generic", "").ir_triple == LLVM.normalize(t)
    end
end
