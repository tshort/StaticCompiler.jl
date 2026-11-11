using StaticCompiler
using StaticTools

@inline function mul!(C::StackArray, A::StackArray, B::StackArray)
    @inbounds for n ∈ axes(C, 2), m ∈ axes(C, 1)
        Cmn = zero(eltype(C))
        for k ∈ axes(A, 2)
            Cmn += A[m,k] * B[k,n]
        end
        C[m,n] = Cmn
    end
    return C
end

function inbounds_matrix_stack()
    rows = 10
    cols = 5

    # LHS
    A = StackArray{Float64}(undef, rows, cols)
    @inbounds for i ∈ axes(A, 1)
        for j ∈ axes(A, 2)
           A[i,j] = i*j
        end
    end

    # RHS
    B = StackArray{Float64}(undef, cols, rows)
    @inbounds for i ∈ axes(B, 1)
        for j ∈ axes(B, 2)
           B[i,j] = i*j
        end
    end

    # # Matrix multiplication
    C = StackArray{Float64}(undef, cols, cols)
    mul!(C, B, A)

    # Print to stdout
    printf(C)
    # Also print to file
    fp = fopen(c"table.tsv",c"w")
    printf(fp, C)
    fclose(fp)
end

# Attempt to compile
path = compile_executable(inbounds_matrix_stack, (), "./")
