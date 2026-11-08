using StaticCompiler
using StaticTools

function iterate()
    if startswith(c"foobar", c"foo")
        printf(c"We have iterated!\n")
        return Int32(0)
    end
    return Int32(1)
end

# Attempt to compile
path = compile_executable(iterate, (), "./")
