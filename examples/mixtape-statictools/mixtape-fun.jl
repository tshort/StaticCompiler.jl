# module X

using StaticCompiler
using CodeInfoTools
using MacroTools
using StaticTools

struct MyMix <: CompilationContext end

swap(e) = e

function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        s isa String && return StaticTools.StaticString(tuple(codeunits(s)..., 0x00))
        return s
    end
    return new
end

function StaticCompiler.transform(::MyMix, src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

StaticCompiler.allow(ctx::MyMix, m::Module) = m == SubFoo

module SubFoo

function stringfun(s1, s2)
    return s1 * s2
end

function teststring()
    return stringfun("ab", "c") == "abc"
end

end

ci = code_info(SubFoo.teststring)
cit = transform(MyMix(),ci)

_, path = compile(SubFoo.teststring, (), MyMix())
@show load_function(path)()

# end
