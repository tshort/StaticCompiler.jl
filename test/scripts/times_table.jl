using StaticCompiler
using StaticTools

function times_table(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = parse(Int64, argv, 2)            # First command-line argument
    cols = parse(Int64, argv, 3)            # Second command-line argument

    M = MallocArray{Int64}(undef, rows, cols)
    @inbounds for i=1:rows
        for j=1:cols
           M[i,j] = i*j
        end
    end
    # Print to stdout
    printf(M)
    # Also print to file
    fp = fopen(c"table.tsv",c"w")
    printf(fp, M)
    fclose(fp)
    # Clean up matrix
    free(M)
end

# Attempt to compile
path = compile_executable(times_table, (Int64, Ptr{Ptr{UInt8}}), "./")
