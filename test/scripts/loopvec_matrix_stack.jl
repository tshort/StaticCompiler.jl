using StaticCompiler
using StaticTools
using LoopVectorization

@inline function mul!(C::StackArray, A::StackArray, B::StackArray)
    @turbo for n ∈ indices((C,B), 2), m ∈ indices((C,A), 1)
        Cmn = zero(eltype(C))
        for k ∈ indices((A,B), (2,1))
            Cmn += A[m,k] * B[k,n]
        end
        C[m,n] = Cmn
    end
    return C
end

function loopvec_matrix_stack()
    rows = 10
    cols = 5

    # LHS
    A = StackArray{Float64}(undef, rows, cols)
    @turbo for i ∈ axes(A, 1)
        for j ∈ axes(A, 2)
           A[i,j] = i*j
        end
    end

    # RHS
    B = StackArray{Float64}(undef, cols, rows)
    @turbo for i ∈ axes(B, 1)
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
target = StaticTarget()
StaticCompiler.set_runtime!(target, true)
path = compile_executable(loopvec_matrix_stack, (), "./"; target=target)
