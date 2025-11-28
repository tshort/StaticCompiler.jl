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
    ex = macroexpand(__module__, ex)
    if Meta.isexpr(ex, :call)
        @show ex = eval(ex)
        error()
    end
    code = quote
        $Base.Experimental.@overlay($StaticCompiler.method_table, $ex)
    end
    return esc(code)
end

macro print_and_throw(err)
    quote
        printf($err)
        libcexit(Int32(1))
    end
end
libcexit(x::Int32) =  @symbolcall exit(x::Int32)::Nothing

# math.jl
@device_override @noinline Base.Math.throw_complex_domainerror(f::Symbol, x) =
    @print_and_throw c"This operation requires a complex input to return a complex result"
@device_override @noinline Base.Math.throw_exp_domainerror(x) =
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
@device_override @noinline Base.Checked.throw_overflowerr_negation(x) =
    @print_and_throw c"Negation overflowed"
@device_override function Base.Checked.checked_abs(x::Base.Checked.SignedInt)
    r = ifelse(x < 0, -x, x)
    r < 0 && @print_and_throw(c"checked arithmetic: cannot compute |x|")
    r
end

# boot.jl
@device_override @noinline Core.throw_inexacterror(f::Symbol, ::Type{T}, val) where {T} =
    @print_and_throw c"Inexact conversion"

@device_override @noinline Base.throw_boundserror(A, I) =
    @print_and_throw c"Out-of-bounds array access"

# trig.jl
@device_override @noinline Base.Math.sincos_domain_error(x) =
    @print_and_throw c"sincos(x) is only defined for finite x."

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
