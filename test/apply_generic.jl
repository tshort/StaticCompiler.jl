
struct A end
struct B end
struct C end
struct D end
struct E end

f(::A) = 1
f(::B) = 2
f(::C) = 3
f(::D) = 4
f(::E) = 5

function dispatch(list)
    s = 0
    @inbounds for item in list  # @inbounds not necessary (it's just to simplify the result of `@code_warntype dispatch(list)`)
        if item isa A
            s += f(item)        # this f gets compile-time dispatched (and inlined, since it's simple)
        else
            s += f(item)::Int   # this call to f is compile-time dispatched if `item` is inferrable, runtime otherwise
        end
    end
    return s
end

function f_apply_generic(@nospecialize x)
    x isa A && return invoke(f, Tuple{A}, x)
    x isa B && return invoke(f, Tuple{B}, x)
    x isa C && return invoke(f, Tuple{C}, x)
    x isa D && return invoke(f, Tuple{D}, x)
    x isa E && return invoke(f, Tuple{E}, x)
end

function dispatch2(list)
    s = 0
    @inbounds for item in list  # @inbounds not necessary (it's just to simplify the result of `@code_warntype dispatch(list)`)
        if item isa A
            s += f_apply_generic(item)        # this f gets compile-time dispatched (and inlined, since it's simple)
        else
            s += f_apply_generic(item)::Int   # this call to f is compile-time dispatched if `item` is inferrable, runtime otherwise
        end
    end
    return s
end

lista_inf = [A() for i = 1:10]
lista_any = Any[A() for i = 1:10]
listc_inf = [C() for i = 1:10]
listc_any = Any[C() for i = 1:10]

m = irgen(dispatch, Tuple{Array{Any,1}})
m2 = irgen(dispatch2, Tuple{Array{Any,1}})