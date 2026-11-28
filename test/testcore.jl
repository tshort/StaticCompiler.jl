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
    # The code is made for the host: only the platform is considered, and not every LLVM has the code generator of each platform
    t(p) = StaticCompiler.StaticTarget(p; retarget = true)
    # Ensure we are checking the target, no the host
    @test StaticCompiler.iswindows(t(Platform("x86_64", "windows"))) && !StaticCompiler.isapple(t(Platform("x86_64", "windows")))
    @test StaticCompiler.isapple(t(Platform("aarch64", "macos"))) && !StaticCompiler.iswindows(t(Platform("aarch64", "macos")))
    @test !StaticCompiler.iswindows(t(Platform("aarch64", "linux"))) && !StaticCompiler.isapple(t(Platform("aarch64", "linux")))
    # A triple that `Platform` does not parse
    wasm = StaticCompiler.StaticTarget("wasm32-unknown-unknown", "generic", "")
    @test isnothing(tryparse(Platform, "wasm32-unknown-unknown")) && !StaticCompiler.iswindows(wasm) && !StaticCompiler.isapple(wasm)
end

@testset "LLVM IR as text" begin
    ir = StaticCompiler.generate_ir(fib, Tuple{Int})
    @test ir isa String && occursin("define", ir) && occursin("fib", ir) && occursin("target triple", ir)
    path, ir_path = StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibir"; emit_llvm_only = true)
    @test isfile(ir_path) && occursin("define", read(ir_path, String))
end

@testset "A target that Julia's LLVM has no code generator for" begin
    triple = "x86_64-unknown-linux-gnu"
    ir_target = StaticCompiler.StaticTarget(triple; retarget = true)
    @test StaticCompiler.target_triple(ir_target) == triple && StaticCompiler.needs_ir(ir_target) == !StaticCompiler.julia_llvm_has(triple)
    @test occursin("--target=$triple", string(StaticCompiler.clang_target_flags(ir_target)))
    ir = StaticCompiler.generate_ir(fib, Tuple{Int}; target = ir_target)
    @test occursin("target triple = \"$triple\"", ir) && !occursin("target datalayout", ir) && !occursin("target-cpu", ir) && !occursin("target-features", ir)
    # (an object is made if Julia's LLVM has the code generator, and is refused if it has not and no `llc` is given)
    if StaticCompiler.julia_llvm_has(triple)
        _, obj = StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibobj"; target = ir_target)
        @test read(obj, 4) == UInt8[0x7f, 0x45, 0x4c, 0x46] # ELF
    else
        @test_throws ArgumentError StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibobj"; target = ir_target)
    end
    path, ir_path = StaticCompiler.generate_obj(((fib, Tuple{Int}),), mktempdir(), "fibir"; target = ir_target, emit_llvm_only = true)
    @test occursin("target triple = \"$triple\"", read(ir_path, String))
    # the host's own target is untouched
    host = StaticCompiler.StaticTarget()
    @test !StaticCompiler.is_retargeted(host) && StaticCompiler.needs_ir(host) == Sys.iswindows()
    @test isempty(StaticCompiler.clang_target_flags(host))
    # (what the host is is found from its triple, however it is spelled: `Platform` does not parse the Windows triple that LLVM has)
    @test StaticCompiler.triple_os("x86_64-w64-windows-gnu") == StaticCompiler.triple_os("x86_64-pc-windows-msvc") == StaticCompiler.triple_os("x86_64-w64-mingw32") == :windows
    @test StaticCompiler.triple_os("arm64-apple-macosx11.0.0") == StaticCompiler.triple_os("aarch64-apple-darwin22.6.0") == :apple && StaticCompiler.triple_os("aarch64-unknown-linux-gnu") == :linux && StaticCompiler.triple_os("wasm64-unknown-unknown") == :other
    @test StaticCompiler.triple_arch("arm64-apple-darwin") == StaticCompiler.triple_arch("aarch64-unknown-linux-gnu") == "aarch64" && StaticCompiler.triple_arch("amd64-pc-windows-msvc") == "x86_64"
    @test isempty(StaticCompiler.clang_target_flags(StaticCompiler.StaticTarget(LLVM.default_triple())))
    @test !isempty(StaticCompiler.clang_target_flags(StaticCompiler.StaticTarget("wasm64-unknown-unknown")))
    for other in ("x86_64-w64-windows-gnu", "aarch64-unknown-linux-gnu", "x86_64-apple-macosx11.0.0")
        t = StaticCompiler.StaticTarget(other; retarget = true)
        @test occursin("--target=", string(StaticCompiler.clang_target_flags(t)))
    end
    # where there is no code generator for the triple, the constructors make such a target
    for t in ("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu", "riscv64-unknown-linux-gnu")
        has_backend = try; LLVM.Target(triple = t); true; catch; false; end
        has_backend || @test StaticCompiler.is_retargeted(StaticCompiler.StaticTarget(t, "generic", "")) && StaticCompiler.target_triple(StaticCompiler.StaticTarget(t, "generic", "")) == LLVM.normalize(t)
    end
end

@testset "Toolchains" begin
    using Base.BinaryPlatforms
    host = StaticCompiler.StaticTarget()
    # the default is the host's C compiler driver, and `set_compiler!` is a driver
    @test StaticCompiler.toolchain(host) isa StaticCompiler.CCToolchain
    t = StaticCompiler.StaticTarget(host; toolchain = "mycc")
    @test t.toolchain == StaticCompiler.CCToolchain(`mycc`) && StaticCompiler.toolchain(t).cc == `mycc`
    t2 = StaticCompiler.StaticTarget(t; toolchain = `othercc`); @test t2.toolchain.cc == `othercc` && t.toolchain.cc == `mycc` # (a copy: the original is as it was)
    t3 = StaticCompiler.StaticTarget(t; toolchain = StaticCompiler.LLDToolchain(:wasm)); @test t3.toolchain isa StaticCompiler.LLDToolchain
    # (and the setters change a target in place)
    StaticCompiler.set_compiler!(t, "othercc"); @test t.toolchain.cc == `othercc` && t2.toolchain.cc == `othercc`
    StaticCompiler.set_toolchain!(t, StaticCompiler.LLDToolchain(:wasm)); @test t.toolchain isa StaticCompiler.LLDToolchain
    StaticCompiler.set_runtime!(t, true); @test t.julia_runtime
    # what the compiled code may do is the target's, and is passed to the compiler
    @test host.can_throw && !host.julia_runtime && !StaticCompiler.StaticTarget(host; can_throw = false).can_throw && StaticCompiler.StaticTarget(host; julia_runtime = true).julia_runtime
    job(target) = StaticCompiler.static_job(fib, Tuple{Int}; target)
    @test StaticCompiler.GPUCompiler.can_throw(job(host)) && !StaticCompiler.GPUCompiler.can_throw(job(StaticCompiler.StaticTarget(host; can_throw = false)))
    @test !StaticCompiler.GPUCompiler.uses_julia_runtime(job(host)) && StaticCompiler.GPUCompiler.uses_julia_runtime(job(StaticCompiler.StaticTarget(host; julia_runtime = true)))
    @test_throws ArgumentError StaticCompiler.LLDToolchain(:macho)
    # (the names of what is made)
    drv = StaticCompiler.CCToolchain(`cc`)
    win = StaticCompiler.StaticTarget(Platform("x86_64", "windows"); retarget = true)
    @test StaticCompiler.output_name(drv, host, "prog") == (Sys.iswindows() ? "prog.exe" : "prog")
    @test StaticCompiler.output_name(drv, win, "prog") == "prog.exe" && StaticCompiler.output_name(drv, win, "lib"; kind = :shared) == "lib.dll"
    @test StaticCompiler.output_name(StaticCompiler.LLDToolchain(:wasm), host, "prog") == "prog.wasm"
    @test StaticCompiler.output_name(StaticCompiler.LLDToolchain(:gnu), host, "prog") == "prog" && StaticCompiler.output_name(StaticCompiler.LLDToolchain(:gnu), win, "lib"; kind = :shared) == "lib.so" # (ELF, on any host)
    # a target made with a toolchain
    @test StaticCompiler.StaticTarget("wasm32", "", ""; toolchain = StaticCompiler.LLDToolchain(:wasm)).toolchain isa StaticCompiler.LLDToolchain

    # `main` made in IR: the executable runs without a C wrapper
    dir = mktempdir()
    hello_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 41) % Int
    # (made and linked as the library does for the host: as IR where the host needs it, as on Windows)
    _, obj = StaticCompiler.generate_obj(((hello_main, Tuple{Int,Ptr{Ptr{UInt8}}}),), dir, "hm"; main_wrapper = "hello_main", emit_llvm_only = StaticCompiler.needs_ir(host))
    ir = StaticCompiler.generate_ir(((hello_main, Tuple{Int,Ptr{Ptr{UInt8}}}),); main_wrapper = "hello_main")
    @test occursin(r"define i32 @main\(i32", ir)
    driver = StaticCompiler.toolchain(host)
    exe = joinpath(dir, StaticCompiler.output_name(driver, host, "hm_exe"))
    StaticCompiler.link(driver, host, [obj], exe; entry = nothing) # (`main` is in the object)
    @test run(ignorestatus(`$exe`)).exitcode == 42 # (argc is 1)
    @test_throws ArgumentError StaticCompiler.generate_ir(((hello_main, Tuple{Int,Ptr{Ptr{UInt8}}}),); main_wrapper = "nothing_here")

    # linking by `lld`: a WebAssembly module (nothing outside of Julia is needed), and the refusals that say what is missing
    wasm_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 41) % Int
    wasm = StaticCompiler.StaticTarget("wasm64-unknown-unknown"; toolchain = StaticCompiler.LLDToolchain(:wasm))
    wasm_path = compile_executable(wasm_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "wasm_main"; target = wasm)
    @test endswith(wasm_path, "wasm_main.wasm") && read(wasm_path, 4) == UInt8[0x00, 0x61, 0x73, 0x6d]
    linux = StaticCompiler.StaticTarget("aarch64-unknown-linux-gnu"; toolchain = StaticCompiler.LLDToolchain(:gnu))
    @test_throws ArgumentError compile_executable(wasm_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "no_sysroot"; target = linux) # (the C library is the target's: `sysroot`)
    @test_throws ArgumentError StaticCompiler.link(StaticCompiler.LLDToolchain(:gnu; sysroot = mktempdir()), linux, [obj], joinpath(dir, "x"); entry = "main") # (a sysroot that has no `crt1.o`)
    @test_throws ArgumentError StaticCompiler.link(StaticCompiler.LLDToolchain(:wasm), wasm, [joinpath(dir, "a.ll")], joinpath(dir, "x")) # (`lld` links objects, not IR)
end

@testset "Builtins and the start of main" begin
    # what a program needs that a C runtime library has: found by what the IR says, for the target
    i128ir = "define i128 @f(i128 %a, i128 %b) {\n %r = udiv i128 %a, %b\n ret i128 %r\n}\n"
    halfir = "define float @g(half %a) {\n %r = fpext half %a to float\n ret float %r\n}\n"
    @test StaticCompiler.needed_builtins(i128ir, "aarch64-unknown-linux-gnu") == [:LINUX_INT128_BUILTINS]
    @test isempty(StaticCompiler.needed_builtins(i128ir, "aarch64-apple-macosx11.0.0")) # (macOS has them in its C library)
    @test StaticCompiler.needed_builtins("", "x86_64-w64-windows-gnu") == [:MINGW_X64_BUILTINS] && StaticCompiler.needed_builtins("", "x86_64-w64-mingw32") == [:MINGW_X64_BUILTINS] # (the runtime of MinGW has to have the probe of the stack)
    @test isempty(StaticCompiler.needed_builtins("", "x86_64-unknown-linux-gnu")) && occursin("___chkstk_ms:", StaticCompiler.add_builtins("", "x86_64-w64-windows-gnu"))
    @test StaticCompiler.needed_builtins(halfir, "x86_64-unknown-linux-gnu") == [:X86_HALF_BUILTINS]
    @test StaticCompiler.needed_builtins(halfir, "wasm64-unknown-unknown") == [:WASM_HALF_BUILTINS]
    @test isempty(StaticCompiler.needed_builtins(halfir, "aarch64-unknown-linux-gnu")) # (the CPU converts)
    # (the same by the instructions of a module, which is not printed to be searched; and a name that says `half` is not a `half`)
    namedir = "define i32 @half(i32 %a) {\n %r = add i32 %a, 1\n ret i32 %r\n}\n"
    LLVM.@dispose ctx = LLVM.Context() begin
        needed(ir, triple) = (mod = parse(LLVM.Module, ir); try; StaticCompiler.needed_builtins(mod, triple); finally; LLVM.dispose(mod); end)
        @test needed(i128ir, "aarch64-unknown-linux-gnu") == [:LINUX_INT128_BUILTINS] && isempty(needed(i128ir, "aarch64-apple-macosx11.0.0"))
        @test needed(halfir, "x86_64-unknown-linux-gnu") == [:X86_HALF_BUILTINS] && needed(halfir, "wasm64-unknown-unknown") == [:WASM_HALF_BUILTINS]
        @test isempty(needed(halfir, "aarch64-unknown-linux-gnu")) && isempty(needed(namedir, "wasm64-unknown-unknown"))
        @test needed("", "x86_64-w64-windows-gnu") == [:MINGW_X64_BUILTINS]
    end
    # (a target that has a toolchain of its own is not given the default, which finds `clang` and the SDK)
    own = StaticCompiler.LLDToolchain(:gnu; sysroot = "/nonexistent")
    @test StaticCompiler.toolchain(StaticCompiler.StaticTarget("aarch64-unknown-linux-gnu"; toolchain = own, retarget = true)) === own
    @test occursin("@__udivti3", StaticCompiler.add_builtins(i128ir, "aarch64-unknown-linux-gnu")) && StaticCompiler.add_builtins(halfir, "aarch64-unknown-linux-gnu") == halfir
    # a toolchain asks for them: `lld` links nothing else, a compiler driver brings its runtime library
    @test StaticCompiler.uses_builtins(StaticCompiler.LLDToolchain(:gnu)) && !StaticCompiler.uses_builtins(StaticCompiler.LLDToolchain(:gnu; builtins = false))
    @test !StaticCompiler.uses_builtins(StaticCompiler.CCToolchain(`cc`)) && StaticCompiler.uses_builtins(StaticCompiler.CCToolchain(`cc`; builtins = true))

    # the IR of a program for Linux made with them (and with `retarget`: the code is the host's, the target is Linux)
    div128(a::Int, b::Int) = (UInt128(a) ÷ UInt128(b)) % Int
    tc = StaticCompiler.LLDToolchain(:gnu; sysroot = "/nonexistent")
    target = StaticCompiler.StaticTarget("aarch64-unknown-linux-gnu"; toolchain = tc, retarget = true)
    @test StaticCompiler.target_triple(target) == "aarch64-unknown-linux-gnu" && StaticCompiler.is_retargeted(target) && target.codegen.cpu in ("", "generic")
    ir = StaticCompiler.generate_ir(div128, Tuple{Int,Int}; target)
    @test occursin("target triple = \"aarch64-unknown-linux-gnu\"", ir) && occursin(r"define [^\n]*@__udivti3", ir) && !occursin("target datalayout", ir)
    # (linked into the module of a target that is not retargeted, which has a data layout: with no warning of different layouts)
    arch = String(first(split(LLVM.default_triple(), '-')))
    plain = StaticCompiler.StaticTarget("$arch-unknown-linux-gnu"; toolchain = StaticCompiler.LLDToolchain(:gnu; sysroot = "/nonexistent"))
    plain_ir = @test_logs min_level = Base.CoreLogging.Warn StaticCompiler.generate_ir(div128, Tuple{Int,Int}; target = plain)
    @test occursin(r"define [^\n]*@__udivti3", plain_ir) && occursin("target datalayout", plain_ir)
    ir = StaticCompiler.generate_ir(div128, Tuple{Int,Int}; target = StaticCompiler.StaticTarget("aarch64-unknown-linux-gnu"; toolchain = StaticCompiler.LLDToolchain(:gnu; builtins = false), retarget = true))
    @test !occursin("@__udivti3", ir)

    # what the start of `main` does first (the program of a collector that looks at the stack from its top: `main` stores it)
    hello_start(argc::Int, argv::Ptr{Ptr{UInt8}}) = argc % Int
    prologue(builder, mod) = (LLVM.call!(builder, LLVM.FunctionType(LLVM.VoidType(), LLVM.LLVMType[]), LLVM.Function(mod, "static_start_mark", LLVM.FunctionType(LLVM.VoidType(), LLVM.LLVMType[]))); nothing)
    ir = StaticCompiler.generate_ir(((hello_start, Tuple{Int,Ptr{Ptr{UInt8}}}),); main_wrapper = "hello_start", main_prologue = prologue)
    @test occursin(r"define i32 @main\(i32[^\n]*\{\nentry:\n  call void @static_start_mark\(\)", ir) # (first in `main`)
end

@testset "Objects by retargeting" begin
    # the object of the code generator of Julia's LLVM, for a triple that is not the host's (the host's architecture, for another system), made from IR that has the host's code
    host_triple = "$(first(split(LLVM.default_triple(), '-')))-unknown-linux-gnu"
    target = StaticCompiler.StaticTarget(host_triple; retarget = true)
    @test StaticCompiler.can_emit_object(target)
    obj = StaticCompiler.emit_object(StaticCompiler.generate_ir(fib, Tuple{Int}; target), target)
    @test obj[1:4] == UInt8[0x7f, 0x45, 0x4c, 0x46] # ELF (and not the host's format)

    # where Julia's LLVM has no code generator, the `llc` of the target makes the object: here a script that stands for it (the arguments that it is given, and a file that it writes)
    if !Sys.iswindows()
        dir = mktempdir()
        fake = joinpath(dir, "fakellc")
        write(fake, "#!/bin/sh\necho \"\$@\" > $(joinpath(dir, "args"))\nout=\nwhile [ \$# -gt 0 ]; do if [ \"\$1\" = -o ]; then out=\$2; fi; shift; done\nprintf OBJECT > \"\$out\"\n")
        chmod(fake, 0o755)
        noisa = StaticCompiler.StaticTarget("fakearch64-unknown-linux-gnu", "mycpu", "+feat"; llc = fake)
        @test !StaticCompiler.julia_llvm_has("fakearch64-unknown-linux-gnu") && StaticCompiler.can_emit_object(noisa) && !StaticCompiler.needs_ir(noisa)
        @test String(StaticCompiler.emit_object("define void @f() {\n ret void\n}\n", noisa)) == "OBJECT"
        args = read(joinpath(dir, "args"), String)
        @test occursin("-mtriple=fakearch64-unknown-linux-gnu", args) && occursin("-mcpu=mycpu", args) && occursin("-mattr=+feat", args) && occursin("-filetype=obj", args)
        # (no `llc`: only the IR can be made)
        without = StaticCompiler.StaticTarget("fakearch64-unknown-linux-gnu")
        @test !StaticCompiler.can_emit_object(without) && StaticCompiler.needs_ir(without)
        @test_throws ArgumentError StaticCompiler.emit_object("define void @f() {\n ret void\n}\n", without)
    end
end

@testset "Linking for Linux from any host" begin
    # the C library of the target (fetched for any host), and a program for it linked by `lld` alone
    # (for the architecture of the host: the code generator for it is in Julia's LLVM wherever it is)
    host_arch = String(first(split(LLVM.default_triple(), '-')))
    triple = "$host_arch-unknown-linux-gnu"
    sysroot = StaticCompiler.glibc_sysroot(triple)
    @test isfile(joinpath(sysroot, "lib", "crt1.o")) || isfile(joinpath(StaticCompiler.crt_directory(sysroot), "crt1.o"))
    @test StaticCompiler.glibc_sysroot(Base.BinaryPlatforms.Platform(host_arch, "linux"; libc = "glibc")) == sysroot
    # the version of the glibc is the version of the `Glibc_jll` that is in the environment (pinning it chooses the glibc)
    v = StaticCompiler.glibc_version(sysroot)
    @test v isa VersionNumber && (v.major, v.minor) == (pkgversion(Glibc_jll).major, pkgversion(Glibc_jll).minor)
    @test isnothing(StaticCompiler.glibc_version(mktempdir())) # (a directory that has none)
    lin_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 41) % Int
    target = StaticCompiler.StaticTarget(triple; toolchain = StaticCompiler.LLDToolchain(:gnu; sysroot))
    # An object that cannot be made is refused, before the linker is asked for it
    nobackend = StaticCompiler.StaticTarget("fakearch64-unknown-linux-gnu"; toolchain = StaticCompiler.LLDToolchain(:gnu; sysroot))
    @test_throws ArgumentError compile_executable(lin_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "nobackend"; target = nobackend)
    div128(a::Int, b::Int) = (UInt128(a) ÷ UInt128(b)) % Int
    exe = compile_executable(lin_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "lin_main"; target)
    @test read(exe, 4) == UInt8[0x7f, 0x45, 0x4c, 0x46] # ELF
    lib = compile_shlib(lin_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "lin_lib"; target)
    @test endswith(lib, ".so") && read(lib, 4) == UInt8[0x7f, 0x45, 0x4c, 0x46]
    # (and the builtins that an `lld` link has not: a division of `i128` links)
    @test isfile(compile_shlib(div128, (Int, Int), mktempdir(), "div128"; target))
end

@testset "The finished module" begin
    # `llvm_finalize` is called on the module as it is made into an object, or written: after the retargeting and the `main`
    fin_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 1) % Int
    seen = String[]
    finalize(mod) = (push!(seen, string(LLVM.triple(mod), " ", haskey(LLVM.functions(mod), "main"))); LLVM.name!(first(f for f in LLVM.functions(mod) if LLVM.name(f) == "main"), "main2"); nothing)
    ir = StaticCompiler.generate_ir(((fin_main, Tuple{Int,Ptr{Ptr{UInt8}}}),); main_wrapper = "fin_main", llvm_finalize = finalize,
                                    target = StaticCompiler.StaticTarget("aarch64-unknown-linux-gnu"; retarget = true))
    @test seen == ["aarch64-unknown-linux-gnu true"] && occursin("@main2", ir)
end

@testset "Mach-O and PE: LLDToolchain for macOS and Windows" begin
    # the flavors, what they link with, and what they make
    @test StaticCompiler.LLDToolchain(:darwin).libs == ["System"] && StaticCompiler.LLDToolchain(:gnu).libs == ["c", "m", "dl", "pthread"] && isempty(StaticCompiler.LLDToolchain(:wasm).libs)
    @test "kernel32" in StaticCompiler.LLDToolchain(:mingw).libs && "mingw32" in StaticCompiler.LLDToolchain(:mingw).libs && StaticCompiler.LLDToolchain(:mingw; libs = ["a"]).libs == ["a"]
    @test_throws ArgumentError StaticCompiler.LLDToolchain(:coff)
    host = StaticCompiler.StaticTarget()
    out(flavor, name; kind = :executable) = StaticCompiler.output_name(StaticCompiler.LLDToolchain(flavor), host, name; kind)
    @test out(:darwin, "p") == "p" && out(:darwin, "l"; kind = :shared) == "l.dylib" # (whatever the host is)
    @test out(:mingw, "p") == "p.exe" && out(:mingw, "l"; kind = :shared) == "l.dll"
    @test out(:gnu, "p") == "p" && out(:gnu, "l"; kind = :shared) == "l.so" && out(:wasm, "p") == "p.wasm"

    # the SDK of macOS: the environment's, or Xcode's on a Mac, and else it has to be given
    withenv("SDKROOT" => "/some/sdk") do
        @test StaticCompiler.macos_sdk() == "/some/sdk"
    end
    withenv("SDKROOT" => nothing) do
        if Sys.isapple() && !isnothing(Sys.which("xcrun"))
            @test isdir(StaticCompiler.macos_sdk())
        else
            @test_throws ArgumentError StaticCompiler.macos_sdk()
        end
    end
    sdk = mktempdir()
    @test StaticCompiler.sdk_version(sdk) == "11.0" # (without `SDKSettings.json`)
    write(joinpath(sdk, "SDKSettings.json"), """{"CanonicalName":"macosx14.2","Version":"14.2","DisplayName":"macOS 14.2"}""")
    @test StaticCompiler.sdk_version(sdk) == "14.2"

    # `mingw_sysroot`: the triples that it takes, and the refusals that come before the artifact (150 MB) is fetched, which `test/cross/matrix.jl` does
    @test_throws ArgumentError StaticCompiler.mingw_sysroot("aarch64-w64-mingw32") # (`Mingw_jll` has x86_64 and i686)
    @test_throws ArgumentError StaticCompiler.mingw_sysroot("aarch64-w64-windows-gnu")
    @test_throws ArgumentError StaticCompiler.mingw_sysroot("x86_64-unknown-linux-gnu") # (not Windows)
    @test_throws ArgumentError StaticCompiler.mingw_sysroot(StaticCompiler.StaticTarget("aarch64-w64-mingw32"; retarget = true))

    # a MinGW-w64 root has the start files in its `lib`, and one without them is refused (what `Mingw_jll`'s artifact is: fetched by the matrix of `test/cross`, which is 150 MB)
    root = mktempdir()
    mkpath(joinpath(root, "lib")); touch(joinpath(root, "lib", "crt2.o"))
    @test StaticCompiler.mingw_directory(root) == joinpath(root, "lib")
    @test_throws ArgumentError StaticCompiler.mingw_directory(mktempdir())
    obj = joinpath(mktempdir(), "x.o"); touch(obj)
    windows = StaticCompiler.StaticTarget("x86_64-w64-mingw32"; retarget = true)
    @test_throws ArgumentError StaticCompiler.link(StaticCompiler.LLDToolchain(:mingw), windows, [obj], joinpath(dirname(obj), "x.exe")) # (no libraries)
    @test_throws ArgumentError StaticCompiler.link(StaticCompiler.LLDToolchain(:mingw; sysroot = mktempdir()), windows, [obj], joinpath(dirname(obj), "x.exe")) # (no start files)
    @test_throws ArgumentError StaticCompiler.link(StaticCompiler.LLDToolchain(:mingw; sysroot = root), StaticCompiler.StaticTarget("riscv64-w64-mingw32"; retarget = true), [obj], joinpath(dirname(obj), "x.exe")) # (no machine of PE for it)

    # Check that windows target is compiling the correct executable types
    arch = String(first(split(LLVM.default_triple(), '-')))
    for triple in ("$arch-w64-mingw32", "$arch-w64-windows-gnu")
        t = StaticCompiler.StaticTarget(triple)
        @test StaticCompiler.target_triple(t) == "$arch-w64-windows-gnu" && StaticCompiler.iswindows(t)
        win_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 41) % Int
        _, obj = StaticCompiler.generate_obj(((win_main, Tuple{Int,Ptr{Ptr{UInt8}}}),), mktempdir(), "o"; target = t, main_wrapper = "win_main")
        head = read(obj, 2)
        @test head != UInt8[0x7f, 0x45] && head == (arch == "x86_64" ? UInt8[0x64, 0x86] : UInt8[0x64, 0xaa])
    end
    @test StaticCompiler.target_triple(StaticCompiler.StaticTarget("$arch-w64-mingw32"; retarget = true)) == "$arch-w64-windows-gnu"

    # a program for macOS made with `lld` alone, and run (on an Apple Silicon Mac: the code generator for its architecture is in Julia's LLVM, and it runs)
    if Sys.isapple() && Sys.ARCH === :aarch64 && !isnothing(Sys.which("xcrun"))
        mac_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 41) % Int
        target = StaticCompiler.StaticTarget("aarch64-apple-macosx11.0.0"; toolchain = StaticCompiler.LLDToolchain(:darwin))
        exe = compile_executable(mac_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "mac_main"; target)
        @test success(`file $exe`) && occursin("Mach-O 64-bit executable arm64", read(`file $exe`, String))
        @test run(ignorestatus(`$exe`)).exitcode == 42
        @test success(`codesign -v $exe`) # (`lld` signs it: arm64 macOS will not run one that is not signed)
        lib = compile_shlib(mac_main, (Int, Ptr{Ptr{UInt8}}), mktempdir(), "mac_lib"; target)
        @test endswith(lib, ".dylib") && occursin("shared library arm64", read(`file $lib`, String))
    end
end
