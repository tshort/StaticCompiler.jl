@static if isdefined(Base.Experimental, Symbol("@overlay"))
    Base.Experimental.@MethodTable(method_table)
    Base.Experimental.@MethodTable(empty_table)
else
    const method_table = nothing
end

"""
```julia
@device_override old_bad_method(arg1::Type1, arg2::Type2) = new_good_method(arg1, arg2)
```
Override a non-static-compilable method (e.g. `old_bad_method(::Type1, ::Type2)`)
with a more compileable replacement.
### Examples
```
@device_override @noinline Core.throw_inexacterror(f::Symbol, ::Type{T}, val) where {T} =
    @print_and_throw c"Inexact conversion"
```
"""
macro device_override(ex)
    code = quote
        $Base.Experimental.@overlay($StaticCompiler.method_table, $ex)
    end
    return esc(code)
end

macro print_and_throw(err)
    quote
        println($err)
        libcexit(Int32(1))
    end
end
libcexit(x::Int32) =  @symbolcall exit(x::Int32)::Nothing

# error.jl
@device_override @noinline Base.error(::AbstractString) =
    @print_and_throw c"error() called"
@device_override @noinline Base.error(::Vararg{Any}) =
    @print_and_throw c"error() called"

# tuple.jl and essentials.jl
@device_override @noinline Base.first(::Tuple{}) =
    @print_and_throw c"Tuple must be non-empty"
@device_override @noinline Base.tail(::Tuple{}) =
    @print_and_throw c"Cannot call tail on an empty tuple"

# reduce.jl
@device_override @noinline Base._empty_reduce_error() =
    @print_and_throw c"Reducing over an empty collection is not allowed"

# char.jl
@device_override @noinline Base.throw_code_point_err(u::Integer) =
    @print_and_throw c"Invalid Unicode code point"
@device_override @noinline Base.throw_invalid_char(c::AbstractChar) =
    @print_and_throw c"Invalid character"

# math.jl
@device_override @noinline Base.Math.throw_complex_domainerror(f::Symbol, x) =
    @print_and_throw c"This operation requires a complex input to return a complex result"
@device_override @noinline Base.Math.throw_exp_domainerror(x) =
    @print_and_throw c"Exponentiation yielding a complex result requires a complex argument"
@device_override @noinline Base.Math.throw_complex_domainerror_neg1(f::Symbol, x) =
    @print_and_throw c"This operation requires a complex input to return a complex result"

# intfuncs.jl
@device_override @noinline Base.throw_domerr_powbysq(::Any, p) =
    @print_and_throw c"Cannot raise an integer to a negative power"
@device_override @noinline Base.__throw_gcd_overflow(a, b) =
    @print_and_throw c"gcd overflow"

# checked.jl
@device_override @noinline Base.Checked.throw_overflowerr_binaryop(op, x, y) =
    @print_and_throw c"Binary operation overflowed"
@device_override @noinline Base.Checked.throw_overflowerr_negation(x) =
    @print_and_throw c"Negation overflowed"
@device_override function Base.Checked.checked_abs(x::Base.Checked.SignedInt)
    r = ifelse(x < 0, -x, x)
    r < 0 && @print_and_throw(c"Checked arithmetic: cannot compute |x|")
    r
end

# boot.jl
@device_override @noinline Core.throw_inexacterror(f::Symbol, ::Type{T}, val) where {T} =
    @print_and_throw c"Inexact conversion"

# float.jl: conversions of floats to integers throw an `InexactError` if out of range or inexact
for Ti in (Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128),
    Tf in (Float16, Float32, Float64)
    # the bounds are checked as in Base
    if Ti <: Unsigned || sizeof(Ti) < sizeof(Tf)
        inrange_round = :($(Tf(typemin(Ti)) - one(Tf)) < x < $(Tf(typemax(Ti)) + one(Tf)))
        inrange = :($(Tf(typemin(Ti))) <= x < $(Tf(typemax(Ti)) + one(Tf)))
    else
        inrange_round = inrange = :($(Tf(typemin(Ti))) <= x < $(Tf(typemax(Ti))))
    end
    @eval begin
        @device_override function Base.round(::Type{$Ti}, x::$Tf, ::RoundingMode{:ToZero})
            $inrange_round || @print_and_throw c"Inexact conversion"
            unsafe_trunc($Ti, x)
        end
        @device_override function (::Type{$Ti})(x::$Tf)
            ($inrange && isinteger(x)) || @print_and_throw c"Inexact conversion"
            unsafe_trunc($Ti, x)
        end
    end
end

# array shapes
@device_override @noinline Base.Broadcast.throwdm(axdest, axsrc) =
    @print_and_throw c"Destination axes are not compatible with source axes"
@device_override @noinline Base.throw_setindex_mismatch(X, I) =
    @print_and_throw c"Tried to assign the wrong number of elements"
@device_override @noinline Base.throw_checksize_error(A, sz) =
    @print_and_throw c"Output array is the wrong size"
@device_override @noinline Base.throw_eachindex_mismatch_indices(::IndexStyle, inds...) =
    @print_and_throw c"All inputs to eachindex must have the same indices"
@device_override @noinline Base._throw_argerror(s) =
    @print_and_throw c"Invalid argument"
@device_override @noinline Base.throw_boundserror(A, I) =
    @print_and_throw c"Out-of-bounds array access"

# used by `checkbounds` on recent Julia versions (nightly / 1.15+)
@static if isdefined(Base, :_throw_boundserror_indices)
    @device_override @noinline Base._throw_boundserror_indices(A) =
        @print_and_throw c"Out-of-bounds array access"
    @device_override @noinline Base._throw_boundserror_indices(A, i1, I...) =
        @print_and_throw c"Out-of-bounds array access"
end

# trig.jl
@device_override @noinline Base.Math.sincos_domain_error(x) =
    @print_and_throw c"sincos(x) is only defined for finite x."
# the trig domain error helpers differ between Julia versions
for f in (:sin_domain_error, :cos_domain_error, :tan_domain_error, :throw_finite_domainerror)
    isdefined(Base.Math, f) && @eval @device_override @noinline Base.Math.$f(x) =
        @print_and_throw c"Trigonometric functions are only defined for finite x."
end
for f in (:asin_domain_error, :acos_domain_error, :acosh_domain_error, :atanh_domain_error)
    isdefined(Base.Math, f) && @eval @device_override @noinline Base.Math.$f(x) =
        @print_and_throw c"Inverse (hyperbolic) trigonometric function called outside of its domain."
end

# int.jl: the checked integer division intrinsics throw a `DivideError` from the generated
# code, so check the arguments ourselves and use the unchecked intrinsics
@device_override function Base.div(x::T, y::T) where {T<:Base.BitSigned}
    y == 0 && @print_and_throw c"Integer division error"
    y == -1 && x == typemin(T) && @print_and_throw c"Integer division error"
    Core.Intrinsics.sdiv_int(x, y)
end
@device_override function Base.div(x::T, y::T) where {T<:Base.BitUnsigned}
    y == 0 && @print_and_throw c"Integer division error"
    Core.Intrinsics.udiv_int(x, y)
end
@device_override function Base.rem(x::T, y::T) where {T<:Base.BitSigned}
    y == 0 && @print_and_throw c"Integer division error"
    y == -1 ? zero(T) : Core.Intrinsics.srem_int(x, y)
end
@device_override function Base.rem(x::T, y::T) where {T<:Base.BitUnsigned}
    y == 0 && @print_and_throw c"Integer division error"
    Core.Intrinsics.urem_int(x, y)
end

# rational.jl
@device_override @noinline Base.__throw_rational_argerror_zero(T) =
    @print_and_throw c"Invalid rational: zero//zero"
@device_override @noinline Base.__throw_negate_unsigned() =
    @print_and_throw c"Cannot negate unsigned number"
@device_override @noinline Base.__throw_rational_numerator_typemin(T) =
    @print_and_throw c"Rational numerator is typemin"


@static if isdefined(StaticTools, :Bumper)
    Bumper = StaticTools.Bumper
    @device_override @noinline Bumper.AllocBufferImpl.oom_error() =
        @print_and_throw c"alloc: Buffer out of memory. This might be a sign of a memory leak."
    @device_override @noinline Bumper.Internals.esc_err() =
        @print_and_throw c"Tried to return a PtrArray from a `no_escape` block. If you really want to do this, evaluate Bumper.allow_ptrarray_to_escape() = true"

    # Just to make the compiler's life a little easier, let's not make it fetch and elide the current task
    # since tasks don't actually exist on-device.
    @device_override Bumper.Internals.get_task() = 0
end
