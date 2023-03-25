libcexit(x::Int32) =  @symbolcall exit(x::Int32)::Nothing
macro print_and_throw(err)
    quote
        println($err)
        libcexit(Int32(1))
    end
end

# math.jl
@device_override @noinline Base.Math.throw_complex_domainerror(f::Symbol, x) =
    @print_and_throw c"This operation requires a complex input to return a complex result"
@device_override @noinline Base.Math.throw_exp_domainerror(f::Symbol, x) =
    @print_and_throw c"Exponentiation yielding a complex result requires a complex argument"

# intfuncs.jl
@device_override @noinline Base.throw_domerr_powbysq(::Any, p) =
    @print_and_throw c"Cannot raise an integer to a negative power"
@device_override @noinline Base.throw_domerr_powbysq(::Integer, p) =
    @print_and_throw c"Cannot raise an integer to a negative power"
@device_override @noinline Base.throw_domerr_powbysq(::AbstractMatrix, p) =
    @print_and_throw c"Cannot raise an integer to a negative power"
@device_override @noinline Base.__throw_gcd_overflow(a, b) =
    @print_and_throw c"gcd overflow"

# checked.jl
@device_override @noinline Base.Checked.throw_overflowerr_binaryop(op, x, y) =
    @print_and_throw c"Binary operation overflowed"
@device_override @noinline Base.Checked.throw_overflowerr_negation(op, x, y) =
    @print_and_throw c"Negation overflowed"
@device_override function Base.Checked.checked_abs(x::Base.Checked.SignedInt)
    r = ifelse(x < 0, -x, x)
    r < 0 && @print_and_throw(c"checked arithmetic: cannot compute |x|")
    r
end

# boot.jl
@device_override @noinline Core.throw_inexacterror(f::Symbol, ::Type{T}, val) where {T} =
    @print_and_throw c"Inexact conversion"

# abstractarray.jl
@device_override @noinline Base.throw_boundserror(A, I) =
    @print_and_throw c"Out-of-bounds array access"

# trig.jl
@device_override @noinline Base.Math.sincos_domain_error(x) =
    @print_and_throw c"sincos(x) is only defined for finite x."
