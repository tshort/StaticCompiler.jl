using StaticCompiler
using StaticTools

function interop(argc, argv)
    lib = StaticTools.dlopen(c"libm")
    printf(lib)
    sin = StaticTools.dlsym(lib, c"sin")
    printf(sin)
    x = @ptrcall sin(5.0::Float64)::Float64
    printf(x)
    newline()
    StaticTools.dlclose(lib)
end

# Attempt to compile
path = compile_executable(interop, (Int64, Ptr{Ptr{UInt8}}), "./", c_flags=`-ldl -lm`)
