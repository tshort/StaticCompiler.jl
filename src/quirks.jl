macro print_and_throw(err)
    quote
        println(err)
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
    r = ifelse(x<0, -x, x)
    r<0 && @print_and_throw(c"checked arithmetic: cannot compute |x|")
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


# range.jl
@static if VERSION >= v"1.7-"
    @eval begin
        @device_override function Base.StepRangeLen{T,R,S,L}(ref::R, step::S, len::Integer,
                                                             offset::Integer=1) where {T,R,S,L}
            if T <: Integer && !isinteger(ref + step)
                @print_and_throw(c"StepRangeLen{<:Integer} cannot have non-integer step")
            end
            len = convert(L, len)
            len >= zero(len) || @print_and_throw(c"StepRangeLen length cannot be negative")
            offset = convert(L, offset)
            L1 = oneunit(typeof(len))
            L1 <= offset <= max(L1, len) || @print_and_throw(c"StepRangeLen: offset must be in [1,...]")
            $(
                Expr(:new, :(StepRangeLen{T,R,S,L}), :ref, :step, :len, :offset)
            )
        end
    end
else
    @device_override function Base.StepRangeLen{T,R,S}(ref::R, step::S, len::Integer,
                                                       offset::Integer=1) where {T,R,S}
        if T <: Integer && !isinteger(ref + step)
            @print_and_throw(c"StepRangeLen{<:Integer} cannot have non-integer step")
        end
        len >= 0 || @print_and_throw(c"StepRangeLen length cannot be negative")
        1 <= offset <= max(1,len) || @print_and_throw(c"StepRangeLen: offset must be in [1,...]")
        new(ref, step, len, offset)
    end
end


# fastmath.jl
@static if VERSION <= v"1.7-"
## prevent fallbacks to libm
    for f in (:acosh, :asinh, :atanh, :cbrt, :cosh, :exp2, :expm1, :log1p, :sinh, :tanh)
        f_fast = Base.FastMath.fast_op[f]
        @eval begin
            @device_override Base.FastMath.$f_fast(x::Float32) = $f(x)
            @device_override Base.FastMath.$f_fast(x::Float64) = $f(x)
        end
    end
end
