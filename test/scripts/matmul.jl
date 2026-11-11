using StaticCompiler
using StaticTools

function matmul(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    A = MallocArray{Float64}(undef, rows, cols)
    @inbounds for i ∈ axes(A, 1)
        for j ∈ axes(A, 2)
           A[i,j] = i*j
        end
    end

    B = MallocArray{Float64}(undef, cols, rows)
    @inbounds for i ∈ axes(B, 1)
        for j ∈ axes(B, 2)
           B[i,j] = i*j
        end
    end

    # Matrix multiplication
    C = B * A

    # Print to stdout
    printf(C)
    # Also print to file
    printdlm(c"table.tsv", C, '\t')
    fwrite(c"table.b", C)
    # Clean up matrices
    free(A)
    free(B)
    # free(C)
end

# Attempt to compile
path = compile_executable(matmul, (Int64, Ptr{Ptr{UInt8}}), "./")
