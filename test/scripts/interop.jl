using StaticCompiler
using StaticTools

function interop(argc, argv)
    lib = StaticTools.dlopen(c"libm")
    sin = StaticTools.dlsym(lib, c"sin")
    StaticTools.dlclose(lib)
    return 0
end

# Attempt to compile
path = compile_executable(interop, (Int64, Ptr{Ptr{UInt8}}), "./", cflags = `-ldl -lm`)
