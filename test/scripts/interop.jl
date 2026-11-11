using StaticCompiler
using StaticTools

function interop(argc, argv)
    # On Linux, `libm.so` is typically a linker script (or absent), so use the versioned soname
    lib = StaticTools.dlopen(@static(Sys.islinux() ? c"libm.so.6" : c"libm"))
    printf(lib)
    sin = StaticTools.dlsym(lib, c"sin")
    printf(sin)
    x = @ptrcall sin(5.0::Float64)::Float64
    printf(x)
    newline()
    StaticTools.dlclose(lib)
end

# Attempt to compile
path = compile_executable(interop, (Int64, Ptr{Ptr{UInt8}}), "./", cflags=`-ldl -lm`)
