# Example 2: Fixing Common Compilation Issues
# This example shows before/after comparisons for common problems

using StaticCompiler
using StaticArrays
using StaticTools

println("="^70)
println("FIXING COMPILATION ISSUES - BEFORE & AFTER")
println("="^70)
println()

# Problem 1: Abstract Types
println("Problem 1: Abstract Type Parameters")
println("-"^70)

# ❌ BEFORE: Won't compile
function process_bad(x::Number)
    return x * 2
end

report_bad = analyze_monomorphization(process_bad, (Number,))
println("❌ BEFORE:")
println("   Has abstract types: ", report_bad.has_abstract_types)
println()

# ✅ AFTER: Will compile
function process_good(x::Int)
    return x * 2
end

report_good = analyze_monomorphization(process_good, (Int,))
println("✅ AFTER:")
println("   Has abstract types: ", report_good.has_abstract_types)
println()

# Problem 2: Heap Allocations
println("Problem 2: Heap Allocations")
println("-"^70)

# ❌ BEFORE: Won't compile (dynamic allocation)
function sum_bad(n::Int)
    arr = zeros(n)
    return sum(arr)
end

report_bad = analyze_escapes(sum_bad, (Int,))
println("❌ BEFORE:")
println("   Allocations: ", length(report_bad.allocations))
println()

# ✅ AFTER: Will compile (stack allocated, fixed size)
function sum_good()
    arr = @SVector zeros(10)  # Stack allocated
    return sum(arr)
end

report_good = analyze_escapes(sum_good, ())
println("✅ AFTER:")
println("   Allocations: ", length(report_good.allocations))
println()

# Alternative: Manual memory management
function sum_manual(n::Int)
    arr = MallocArray{Float64}(undef, n)
    fill!(arr, 0.0)
    s = sum(arr)
    free(arr)  # Important!
    return s
end

report_manual = analyze_lifetimes(sum_manual, (Int,))
println("✅ ALTERNATIVE (manual memory):")
println("   Potential leaks: ", report_manual.potential_leaks)
println()

# Problem 3: String Allocations
println("Problem 3: String Operations")
println("-"^70)

# ❌ BEFORE: Won't compile (String allocates)
function greet_bad(name::String)
    return "Hello, " * name
end

println("❌ BEFORE:")
println("   Uses Julia String (heap allocated)")
println()

# ✅ AFTER: Will compile (static string)
function greet_good()
    println(c"Hello, World!")
    return 0
end

println("✅ AFTER:")
println("   Uses StaticTools string (stack allocated)")
println()

# Problem 4: Dynamic Dispatch
println("Problem 4: Dynamic Dispatch")
println("-"^70)

abstract type Animal end
struct Dog <: Animal 
    name::String
end
struct Cat <: Animal
    name::String  
end

# ❌ BEFORE: Dynamic dispatch
function speak_bad(a::Animal)
    return "Animal speaks"
end

report_bad = analyze_devirtualization(speak_bad, (Dog,))
println("❌ BEFORE:")
println("   Dynamic calls: ", report_bad.total_dynamic_calls)
println()

# ✅ AFTER: Direct dispatch
function speak_good(d::Dog)
    return "Woof!"
end

report_good = analyze_devirtualization(speak_good, (Dog,))
println("✅ AFTER:")
println("   Dynamic calls: ", report_good.total_dynamic_calls)
println()

# Problem 5: Memory Leaks
println("Problem 5: Memory Leaks")
println("-"^70)

# ❌ BEFORE: Memory leak
function allocate_bad(n::Int)
    arr = MallocArray{Float64}(undef, n)
    # Forgot to free!
    return 0
end

report_bad = analyze_lifetimes(allocate_bad, (Int,))
println("❌ BEFORE:")
println("   Potential leaks: ", report_bad.potential_leaks)
println()

# ✅ AFTER: Proper cleanup
function allocate_good(n::Int)
    arr = MallocArray{Float64}(undef, n)
    # ... use arr ...
    free(arr)  # Don't forget!
    return 0
end

report_good = analyze_lifetimes(allocate_good, (Int,))
println("✅ AFTER:")
println("   Potential leaks: ", report_good.potential_leaks)
println()

# Summary
println("="^70)
println("KEY TAKEAWAYS:")
println("="^70)
println("1. Use concrete types (Int, Float64) instead of abstract (Number, Real)")
println("2. Use StaticArrays for fixed-size arrays")
println("3. Use MallocArray for dynamic sizes (remember to free!)")
println("4. Use StaticTools strings instead of Julia Strings")
println("5. Avoid abstract type parameters that cause dynamic dispatch")
println("6. Always pair malloc with free")
println("="^70)
