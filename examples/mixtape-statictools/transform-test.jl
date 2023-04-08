using CodeInfoTools
using MacroTools
using StaticTools


swap(e) = e

function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        @show s
        s isa String && return StaticTools.StaticString(tuple(codeunits(s)..., 0x00))
        return s
    end
    return new
end

function transform(src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

function stringfun(s1, s2)
    return s1 * s2
end

function teststring()
    return stringfun("ab", "c") == "abc"
end

ci = code_info(teststring)
cit = transform(ci)

