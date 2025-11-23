using StaticCompiler
using StaticTools

function times_table(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    M = MallocArray{Int64}(undef, rows, cols)
    @inbounds for i in 1:rows
        for j in 1:cols
            M[i, j] = i * j
        end
    end
    # Print to stdout
    printf(M)
    # Also print to file
    fwrite(c"table.b", M)
    printdlm(c"table.tsv", M)
    # Clean up matrix
    return free(M)
end

# Attempt to compile
target = StaticTarget()
StaticCompiler.set_runtime!(target, true)
path = compile_executable(times_table, (Int64, Ptr{Ptr{UInt8}}), "./"; target = target)
