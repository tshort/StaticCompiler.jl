using StaticCompiler
using StaticTools
using LoopVectorization

const STACK_ROWS = 10
const STACK_COLS = 5

@inline function mul!(C::MallocArray, A::MallocArray, B::MallocArray)
    @turbo for n ∈ axes(C, 2), m ∈ axes(C, 1)
        Cmn = zero(eltype(C))
        for k ∈ indices((A,B), (2,1))
            Cmn += A[m,k] * B[k,n]
        end
        C[m,n] = Cmn
    end
    return C
end

function loopvec_matrix_stack()
    # LHS
    A = MallocArray{Float64}(undef, STACK_ROWS, STACK_COLS)
    @turbo for i ∈ axes(A, 1)
        for j ∈ axes(A, 2)
           A[i,j] = i*j
        end
    end

    # RHS
    B = MallocArray{Float64}(undef, STACK_COLS, STACK_ROWS)
    @turbo for i ∈ axes(B, 1)
        for j ∈ axes(B, 2)
           B[i,j] = i*j
        end
    end

    # # Matrix multiplication
    C = MallocArray{Float64}(undef, STACK_COLS, STACK_COLS)
    mul!(C, B, A)

    # Print to stdout
    printf(C)
    # Also print to file
    printdlm(c"table.tsv", C, '\t')
    fwrite(c"table.b", C)
    free(A); free(B); free(C)
end

# Attempt to compile with runtime linked
target = StaticTarget()
StaticCompiler.set_runtime!(target, true)
path = compile_executable(loopvec_matrix_stack, (), "./"; target=target)
