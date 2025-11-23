using StaticCompiler
using StaticTools
using LoopVectorization

@inline function mul!(C::MallocArray, A::MallocArray, B::MallocArray)
    @turbo for n in axes(C, 2), m in axes(C, 1)
        Cmn = zero(eltype(C))
        for k in indices((A, B), (2, 1))
            Cmn += A[m, k] * B[k, n]
        end
        C[m, n] = Cmn
    end
    return C
end

function loopvec_matrix(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    # LHS
    A = MallocArray{Float64}(undef, rows, cols)
    @turbo for i in axes(A, 1)
        for j in axes(A, 2)
            A[i, j] = i * j
        end
    end

    # RHS
    B = MallocArray{Float64}(undef, cols, rows)
    @turbo for i in axes(B, 1)
        for j in axes(B, 2)
            B[i, j] = i * j
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
    return free(C)
end

# Attempt to compile
target = StaticTarget()
StaticCompiler.set_runtime!(target, true)
path = compile_executable(loopvec_matrix, (Int64, Ptr{Ptr{UInt8}}), "./"; target = target)
