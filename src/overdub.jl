# Implements contextual dispatch through Cassette.jl

using Cassette

##
# Convert two-arg `ccall` to single arg.
##
function transform(ctx, ref)
    CI = ref.code_info
    ismatch = x -> begin
        Base.Meta.isexpr(x, :foreigncall) &&
        Base.Meta.isexpr(x.args[1], :call)
    end
    replace = x -> begin
        y = Expr(x.head, Any[x.args[1].args[2], x.args[2:end]...])
        Expr(x.head, x.args[1].args[2], x.args[2:end]...)
    end
    Cassette.replace_match!(replace, ismatch, CI.code)
    return CI
end

const Pass = Cassette.@pass transform

Cassette.@context Ctx
const ctx = Cassette.disablehooks(Ctx(pass = Pass))

###
# Rewrite functions
###

#@inline Cassette.overdub(ctx::Ctx, ::typeof(+), a::T, b::T) where T<:Union{Float32, Float64} = add_float_contract(a, b)

contextualize(f::F) where F = (args...) -> Cassette.overdub(ctx, f, args...)
