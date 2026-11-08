using StaticCompiler
using StaticTools

function matmul_stack()
    rows = 10
    cols = 5

    A = szeros(rows, cols)
    @inbounds for i ∈ axes(A, 1)
        for j ∈ axes(A, 2)
           A[i,j] = i*j
        end
    end

    B = szeros(cols, rows)
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
    
    return Int32(0)
end

# Attempt to compile
path = compile_executable(matmul_stack, (), "./")
