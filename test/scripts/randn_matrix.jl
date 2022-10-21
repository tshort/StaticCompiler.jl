using StaticCompiler
using StaticTools

function randn_matrix(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    M = MallocArray{Float64}(undef, rows, cols)
    rng = MarsagliaPolar(static_rng())
    @inbounds for i=1:rows
        for j=1:cols
            M[i,j] = randn(rng)
        end
    end
    printf(M)
    free(M)
end

# Attempt to compile
# cflags=`-lm`: need to explicitly include libm math library on linux
path = compile_executable(randn_matrix, (Int64, Ptr{Ptr{UInt8}}), "./", cflags=`-lm`)
