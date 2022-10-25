using StaticCompiler
using StaticTools

function print_args(argc::Int, argv::Ptr{Ptr{UInt8}})
    printf(c"Argument count is %d:\n", argc)
    for i=1:argc
        # iᵗʰ input argument string
        pᵢ = unsafe_load(argv, i) # Get pointer
        strᵢ = MallocString(pᵢ) # Can wrap to get high-level interface
        println(strᵢ)
        # No need to `free` since we didn't allocate this memory
    end
    newline()
    println(c"Testing string indexing and substitution")
    m = m"Hello world!"
    println(m[1:5])
    println(m)
    m[7:11] = c"there"
    println(m)
    free(m)

    s = m"Hello world!"
    println(s[1:5])
    println(s)
    s[7:11] = c"there"
    println(s)

    println(c"That was fun, see you next time!")
    return 0
end

# Attempt to compile
path = compile_cosmopolitan(print_args, (Int64, Ptr{Ptr{UInt8}}), "./")
