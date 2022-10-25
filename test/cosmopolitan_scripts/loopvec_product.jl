using StaticCompiler
using StaticTools
using LoopVectorization

function loopvec_product(argc::Int, argv::Ptr{Ptr{UInt8}})
    argc == 3 || return printf(stderrp(), c"Incorrect number of command-line arguments\n")
    rows = argparse(Int64, argv, 2)            # First command-line argument
    cols = argparse(Int64, argv, 3)            # Second command-line argument

    s = 0
    @turbo for i=1:rows
        for j=1:cols
           s += i*j
        end
    end
    # Print result to stdout
    printf(s)
    # Also print to file
    fp = fopen(c"product.tsv",c"w")
    printf(fp, s)
    fclose(fp)
end

# Attempt to compile
path = compile_cosmopolitan(loopvec_product, (Int64, Ptr{Ptr{UInt8}}), "./")
