using StaticCompiler
using StaticTools

function rand_matrix(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    # Manually fil matrix
    M = MallocArray{Float64}(undef, rows, cols)
    rng = static_rng()
    @inbounds for i in 1:rows
        for j in 1:cols
            M[i, j] = rand(rng)
        end
    end
    printf(M)
    return free(M)
end

# Attempt to compile
# cflags=`-lm`: need to explicitly include libm math library on linux
path = compile_executable(rand_matrix, (Int64, Ptr{Ptr{UInt8}}), "./", cflags = `-lm`)
