using StaticCompiler
using StaticTools

function stack_times_table()
    a = StackArray{Int64}(undef, 5, 5)
    for i ∈ axes(a,1)
        for j ∈ axes(a,2)
            a[i,j] = i*j
        end
    end
    print(a)
    fwrite(c"table.b", a)
    GC.@preserve a printdlm(c"table.tsv", a)

    # Test reinterpreting
    println(c"\nThe same array, reinterpreted as Int32:")
    GC.@preserve a print(reinterpret(Int32, a))
end

path = compile_executable(stack_times_table, (), "./")
