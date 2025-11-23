using StaticCompiler
using StaticTools

function maybe_throw(argc::Int, argv::Ptr{Ptr{UInt8}})
    printf(c"Argument count is %d:\n", argc)
    argc > 1 || return printf(stderrp(), c"Too few command-line arguments\n")
    n = argparse(Int64, argv, 2)            # First command-line argument
    printf((c"Input:\n", n, c"\n"))
    printf(c"\nAttempting to represent input as UInt64:\n")
    x = UInt64(n)
    return printf(x)
end

# Attempt to compile
target = StaticTarget()
StaticCompiler.set_runtime!(target, true)
path = compile_executable(maybe_throw, (Int64, Ptr{Ptr{UInt8}}), "./"; target = target)
