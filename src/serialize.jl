
"""
A context structure for holding state related to serializing Julia
objects. A key component is an `IOBuffer` used to hold the serialized
result.
"""
struct SerializeContext
    io::IOBuffer
    store::Dict{Any,Any}   # Meant to map Julia object to variable name
    init::Vector{Any}      # Expressions to run initially
end
SerializeContext(io::IOBuffer = IOBuffer()) = SerializeContext(io, Dict(), Vector{Expr}())

const _td = IdDict(
    Any => :jl_any_type,
    Float64 => :jl_float64_type,
    Float32 => :jl_float32_type,
    Int64 => :jl_int64_type,
    Int32 => :jl_int32_type,
    Int16 => :jl_int16_type,
    Int8 => :jl_int8_type,
    UInt64 => :jl_uint64_type,
    UInt32 => :jl_uint32_type,
    UInt16 => :jl_uint16_type,
    UInt8 => :jl_uint8_type,
    Cint => :jl_int32_type,
    Cvoid => :jl_any_type,
    Array => :jl_array_type,
    Array{Any,1} => :jl_array_any_type,
    Array{Int32,1} => :jl_array_int32_type,
    Array{UInt8,1} => :jl_array_uint8_type,
    ErrorException => :jl_errorexception_type,
    DataType => :jl_datatype_type,
    UnionAll => :jl_unionall_type,
    Union => :jl_union_type,
    Core.TypeofBottom => :jl_typeofbottom_type,
    TypeVar => :jl_tvar_type,
)

const _t = IdDict()

for (t,s) in _td
    _t[t] = :(unsafe_load(cglobal($(QuoteNode(s)), Type)))
end

const _gd = IdDict(
    Core => :jl_core_module,
    Main => :jl_main_module,
    nothing => :jl_nothing,
    () => :jl_emptytuple,
    Core.svec() => :jl_emptysvec,
    UndefRefError() => :jl_undefref_exception,
)

const _g = IdDict()

for (x,s) in _gd
    _g[x] = :(unsafe_load(cglobal($(QuoteNode(s)), Any)))
end

"""
    serialize(ctx::SerializeContext, x)

Serialize `x` into the context object `ctx`. `ctx.io` is the `IOBuffer` where the
serialized results are stored. Get the result with `take!(ctx.io)`.

This function returns an expression that will deserialize the object. Several `serialize`
methods can be called recursively to build up deserialization code for nested objects.
The expression returned is meant to be `eval`ed into a function that can be called
to do the serialization.

The deserialization code should be pretty low-level code that can be compiled
relatively easily. It especially shouldn't use global variables.

Serialization / deserialization code can use `ctx` to hold state information.

Some simple types like boxed variables do not need to write anything to `ctx.io`.
They can return an expression that directly creates the object.
"""
function serialize(ctx::SerializeContext, @nospecialize(x))
    haskey(_g, x) && return _g[x]
    # TODO: fix this major kludge.
    if nfields(x) > 0
        return Expr(:tuple, (serialize(ctx, getfield(x,i)) for i in 1:nfields(x))...)
    end
    return :(unsafe_load(cglobal(:jl_emptytuple, Any)))
end

function serialize(ctx::SerializeContext, @nospecialize(t::DataType))
    if haskey(_t, t)
        return _t[t]
    elseif haskey(ctx.store, t)
        return ctx.store[t]
    else
        # primary = unwrap_unionall(t.wrapper)
        name = gensym(Symbol(:type, "-", t.name.name))
        ctx.store[t] = name
        e = quote
            $name = let
                local tn    = $(serialize(ctx, t.name))
                # names = $(serialize(ctx, t.names))
                local super = $(serialize(ctx, t.super))
                local parameters = $(serialize(ctx, t.parameters))
                local types = $(serialize(ctx, t.types))
                local ndt = ccall(:jl_new_datatype, Any,
                            (Any, Any, Any, Any, Any, Any, Cint, Cint, Cint),
                            tn, tn.module, super, parameters, #=names=# unsafe_load(cglobal(:jl_any_type, Any)), types,
                            $(t.abstract), $(t.mutable), $(t.ninitialized))
                # tn.wrapper = ndt.name.wrapper
                # ccall(:jl_set_const, Cvoid, (Any, Any, Any), tn.module, tn.name, tn.wrapper)
                ndt
                # ty = tn.wrapper
                # $(ctx.types[string(t)]) = ndt
                # hasinstance = serialize(ctx, )
                # $(if isdefined(primary, :instance) && !isdefined(t, :instance)
                #     # use setfield! directly to avoid `fieldtype` lowering expecting to see a Singleton object already on ty
                #     :(Core.setfield!(ty, :instance, ccall(:jl_new_struct, Any, (Any, Any...), ty)))
                # end)
            end
        end
        push!(ctx.init, e)
        return name
    end
end

function serialize(ctx::SerializeContext, tn::Core.TypeName)
    haskey(ctx.store, tn) && return ctx.store[tn]
    name = gensym(Symbol(:typename, "-", tn.name))
    ctx.store[tn] = name
    e = quote
        $name = ccall(:jl_new_typename_in, Ref{Core.TypeName}, (Any, Any),
            #   $(serialize(ctx, tn.name)), Main  #=__deserialized_types__ =# )
              $(serialize(ctx, tn.name)), unsafe_load(cglobal(:jl_main_module, Any))  #=__deserialized_types__ =# )
    end
    push!(ctx.init, e)
    return name
end

function serialize(ctx::SerializeContext, mi::Core.MethodInstance)
    return :(unsafe_load(cglobal(:jl_emptytuple, Any)))
end

function serialize(ctx::SerializeContext, x::String)
    advance!(ctx.io)
    v = Vector{UInt8}(x)
    ioptr = ctx.io.ptr
    write(ctx.io, v)
    quote
        unsafe_string(Vptr + $(ioptr - 1), $(length(v)))
    end
end

function serialize(ctx::SerializeContext, x::Symbol)
    haskey(ctx.store, x) && return ctx.store[x]
    name = gensym(Symbol(:symbol, "-", x))
    ctx.store[x] = name
    e = quote
        $name = ccall(:jl_symbol_n, Any, (Ptr{UInt8}, Csize_t), $(serialize(ctx, string(x))), $(length(string(x))))
        # ccall(:jl_set_global, Cvoid, (Any, Any, Any), unsafe_load(cglobal(:jl_main_module, Any)), $(QuoteNode(name)), x)
    end
    push!(ctx.init, e)
    return name
end



# Define functions that return an expression. Example:
#    serialize(ctx::SerializeContext, x::Int) = :(ccall(:jl_box_int64, Any, (Int,), $x))
for (fun, type) in (:jl_box_int64 => Int64,     :jl_box_int32 => Int32,    :jl_box_int8 => Int16,    :jl_box_int8 => Int8,
                    :jl_box_uint64 => UInt64,   :jl_box_uint32 => UInt32,  :jl_box_uint8 => UInt16,  :jl_box_uint8 => UInt8,
                    :jl_box_voidpointer => Ptr{Cvoid},
                    :jl_box_float64 => Float64, :jl_box_float32 => Float32)
    @eval serialize(ctx::SerializeContext, x::$type) = Expr(:call, :ccall, QuoteNode($(QuoteNode(fun))), Any, Expr(:tuple, $type), x)
end
serialize(ctx::SerializeContext, x::Char) = :(ccall(:jl_box_char, Any, (UInt32,), $x))
serialize(ctx::SerializeContext, x::Bool) = :(ccall(:jl_box_bool, Any, (UInt8,), $x))

function serialize(ctx::SerializeContext, a::Tuple)
    length(a) == 0 && return :(unsafe_load(cglobal(:jl_emptytuple, Any)))
    Expr(:tuple, (serialize(ctx, x) for x in a)...)
end

function serialize(ctx::SerializeContext, a::Core.SimpleVector)
    length(a) == 0 && return :(unsafe_load(cglobal(:jl_emptysvec, Any)))
    Expr(:call, Expr(:., :Core, QuoteNode(:svec)), (serialize(ctx, x) for x in a)...)
end

advance!(io) = write(io, repeat('\0', -rem(io.ptr - 1, 8, RoundUp)))  # Align data to 8 bytes

function serialize(ctx::SerializeContext, a::Array{T,N}) where {T,N}
    elty = eltype(a)
    aty = typeof(a)
    dims = size(a)
    atys = serialize(ctx, aty)
    if isbitstype(elty)
        advance!(ctx.io)
        ioptr = ctx.io.ptr
        write(ctx.io, a)
        if N == 1
            advance!(ctx.io)
            ioptr = ctx.io.ptr
            write(ctx.io, a)
            quote
                p = Vptr + $ioptr - 1
                ccall(:jl_ptr_to_array_1d, $aty, (Any, Ptr{Cvoid}, Csize_t, Cint), $atys, p, $(length(a)), false)
            end
        else
            dms = serialize(ctx, dims)
            advance!(ctx.io)
            ioptr = ctx.io.ptr
            write(ctx.io, a)
            quote
                p = Vptr + $ioptr - 1
                ccall(:jl_ptr_to_array, $aty, (Any, Ptr{Cvoid}, Any, Int32), $atys, p, $dms, false)
            end
        end
    else
        idx = Int[]
        e = Array{Any}(undef, length(a))
        @inbounds for i in eachindex(a)
            if isassigned(a, i)
                e[i] = serialize(ctx, a[i])
                push!(idx, i)
            end
        end
        aname = gensym()
        resulte = [quote
            # $aname = Array{$elty, $(length(dims))}(undef, $dims)
            $aname = ccall(:jl_new_array, $aty, (Any, Any), $atys, $(serialize(ctx, dims)))
        end]
        for i in idx
            push!(resulte, quote
                # unsafe_store!(pointer($aname), $(e[i]), $i)
                unsafe_store!(convert(Ptr{Any}, pointer($aname)), $(e[i]), $i)
                # unsafe_store!(convert(Ptr{Csize_t}, pointer($aname)), pointer_from_objref($(e[i])), $i)
                # @inbounds $aname[$i] = $(e[i])
            end)
        end
        push!(resulte, :($aname = $aname))
        Expr(:block, resulte...)
    end
end
