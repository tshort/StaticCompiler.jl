using StaticCompiler
using StaticTools
using LoopVectorization

@inline function mul!(C::MallocArray, A::MallocArray, B::MallocArray)
    @turbo for n ∈ indices((C,B), 2), m ∈ indices((C,A), 1)
        Cmn = zero(eltype(C))
        for k ∈ indices((A,B), (2,1))
            Cmn += A[m,k] * B[k,n]
        end
        C[m,n] = Cmn
    end
    return C
end

function loopvec_matrix(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    # LHS
    A = MallocArray{Float64}(undef, rows, cols)
    @turbo for i ∈ axes(A, 1)
        for j ∈ axes(A, 2)
           A[i,j] = i*j
        end
    end

    # RHS
    B = MallocArray{Float64}(undef, cols, rows)
    @turbo for i ∈ axes(B, 1)
        for j ∈ axes(B, 2)
           B[i,j] = i*j
        end
    end

    # # Matrix multiplication
    C = MallocArray{Float64}(undef, cols, cols)
    mul!(C, B, A)

    # Print to stdout
    printf(C)
    # Also print to file
    printdlm(c"table.tsv", C, '\t')
    fwrite(c"table.b", C)
    # Clean up matrices
    free(A)
    free(B)
    free(C)
end

# Attempt to compile
path = compile_executable(loopvec_matrix, (Int64, Ptr{Ptr{UInt8}}), "./")
