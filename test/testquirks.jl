# Functions that can throw errors which need the Julia runtime to be thrown, unless StaticCompiler
# overrides them (see src/quirks.jl). These need to be defined globally due to
# https://github.com/JuliaLang/julia/issues/40990
quirk_div(x::Int, y::Int) = div(x, y)
quirk_rem(x::Int, y::Int) = rem(x, y)
quirk_mod(x::Int, y::Int) = mod(x, y)
quirk_fld(x::Int, y::Int) = fld(x, y)
quirk_cld(x::Int, y::Int) = cld(x, y)
quirk_divrem(x::Int, y::Int) = first(divrem(x, y))
quirk_udiv(x::UInt, y::UInt) = div(x, y)
quirk_urem(x::UInt, y::UInt) = rem(x, y)
quirk_i32div(x::Int32, y::Int32) = div(x, y)
quirk_i128div(x::Int, y::Int) = div(Int128(x) << 70, Int128(y)) % Int
quirk_i128rem(x::Int, y::Int) = rem(Int128(x) << 70 + 5, Int128(y)) % Int
quirk_u128rem(x::UInt, y::UInt) = rem(UInt128(x) << 70 + 5, UInt128(y)) % UInt
quirk_int(x::Float64) = Int(x)
quirk_trunc(x::Float64) = trunc(Int, x)
quirk_round(x::Float64) = round(Int, x)
quirk_floor(x::Float64) = floor(Int, x)
quirk_ceil(x::Float64) = ceil(Int, x)
quirk_u8(x::Float64) = UInt8(x)
quirk_i32(x::Float32) = Int32(x)
quirk_acos(x::Float64) = acos(x)
quirk_char(x::Int) = Int(Char(x))
quirk_rational(x::Int, y::Int) = (x // y).num

# the same, but triggering the error
quirk_divzero(argc::Int, argv::Ptr{Ptr{UInt8}}) = div(argc, argc - 1)
quirk_remzero(argc::Int, argv::Ptr{Ptr{UInt8}}) = rem(argc, argc - 1)
quirk_divovf(argc::Int, argv::Ptr{Ptr{UInt8}}) = div(typemin(Int) + argc - 1, -argc)
quirk_i128zero(argc::Int, argv::Ptr{Ptr{UInt8}}) = div(Int128(argc), Int128(argc - 1)) % Int
quirk_inexact(argc::Int, argv::Ptr{Ptr{UInt8}}) = Int(argc + 0.5)
quirk_acoserr(argc::Int, argv::Ptr{Ptr{UInt8}}) = round(Int, acos(argc + 1.0))
quirk_emptyfirst(argc::Int, argv::Ptr{Ptr{UInt8}}) = (first(()); 0)
quirk_error(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc > 0 && error("bad"); 0)

@testset "Overridden error paths" begin
    workdir = mktempdir()

    # The functions link without the Julia runtime and agree with Base when no error is thrown
    funcs = [(quirk_div, (Int, Int)), (quirk_rem, (Int, Int)), (quirk_mod, (Int, Int)),
             (quirk_fld, (Int, Int)), (quirk_cld, (Int, Int)), (quirk_divrem, (Int, Int)),
             (quirk_udiv, (UInt, UInt)), (quirk_urem, (UInt, UInt)), (quirk_i32div, (Int32, Int32)),
             (quirk_i128div, (Int, Int)), (quirk_i128rem, (Int, Int)), (quirk_u128rem, (UInt, UInt)),
             (quirk_int, (Float64,)), (quirk_trunc, (Float64,)), (quirk_round, (Float64,)),
             (quirk_floor, (Float64,)), (quirk_ceil, (Float64,)), (quirk_u8, (Float64,)),
             (quirk_i32, (Float32,)), (quirk_acos, (Float64,)), (quirk_char, (Int,)),
             (quirk_rational, (Int, Int))]
    path = compile_shlib(funcs, workdir; filename="libquirks")
    lib = Libdl.dlopen(path, Libdl.RTLD_LOCAL)
    sym(f) = Libdl.dlsym(lib, string(nameof(f)))

    xs = (-7, -1, 0, 1, 5, 123456789, typemax(Int))
    ys = (-3, -1, 1, 2, 7, typemax(Int))
    for f in (quirk_div, quirk_rem, quirk_mod, quirk_fld, quirk_cld, quirk_divrem),
        x in xs, y in ys
        @test ccall(sym(f), Int, (Int, Int), x, y) == f(x, y)
    end
    # `rem` and `mod` by -1 are fine even for typemin
    @test ccall(sym(quirk_rem), Int, (Int, Int), typemin(Int), -1) == 0
    @test ccall(sym(quirk_mod), Int, (Int, Int), typemin(Int), -1) == 0
    for x in UInt.((0, 1, 7)) ∪ typemax(UInt), y in UInt.((1, 2, 7)) ∪ typemax(UInt)
        @test ccall(sym(quirk_udiv), UInt, (UInt, UInt), x, y) == quirk_udiv(x, y)
        @test ccall(sym(quirk_urem), UInt, (UInt, UInt), x, y) == quirk_urem(x, y)
    end
    for f in (quirk_i128div, quirk_i128rem), x in xs, y in ys
        @test ccall(sym(f), Int, (Int, Int), x, y) == f(x, y)
    end
    for x in UInt.((0, 1, 7)) ∪ typemax(UInt), y in UInt.((1, 2, 7)) ∪ typemax(UInt)
        @test ccall(sym(quirk_u128rem), UInt, (UInt, UInt), x, y) == quirk_u128rem(x, y)
    end
    @test ccall(sym(quirk_i32div), Int32, (Int32, Int32), Int32(-9), Int32(2)) == -4
    for x in (-2.5, -1.5, -0.0, 0.0, 0.4, 0.5, 1.5, 2.5, 3.7, -3.7, 1e10, -1e10)
        for f in (quirk_trunc, quirk_round, quirk_floor, quirk_ceil)
            @test ccall(sym(f), Int, (Float64,), x) == f(x)
        end
    end
    for x in (-3.0, 0.0, 7.0, 1e10)
        @test ccall(sym(quirk_int), Int, (Float64,), x) == Int(x)
    end
    @test ccall(sym(quirk_u8), UInt8, (Float64,), 200.0) == 200
    @test ccall(sym(quirk_i32), Int32, (Float32,), -5f0) == -5
    @test ccall(sym(quirk_acos), Float64, (Float64,), 0.5) == acos(0.5)
    @test ccall(sym(quirk_char), Int, (Int,), 0x41) == 0x41
    @test ccall(sym(quirk_rational), Int, (Int, Int), 6, 4) == 3
    Libdl.dlclose(lib)

    # The errors exit with a message instead
    function run_quirk(f)
        path = compile_executable(f, (Int, Ptr{Ptr{UInt8}}), workdir)
        proc = open(ignorestatus(`$path`))
        out = read(proc, String)
        wait(proc)
        proc.exitcode, out
    end
    for (f, msg) in ((quirk_divzero, "Integer division error"), (quirk_remzero, "Integer division error"),
                     (quirk_divovf, "Integer division error"), (quirk_i128zero, "Integer division error"), (quirk_inexact, "Inexact conversion"),
                     (quirk_acoserr, "domain"), (quirk_emptyfirst, "Tuple must be non-empty"),
                     (quirk_error, "error() called"))
        code, out = run_quirk(f)
        @test code == 1
        @test occursin(msg, out)
    end
end
