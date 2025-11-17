# Example 4: Analyzing Multiple Functions in a Project
# This example shows how to analyze an entire project systematically

using StaticCompiler

println("="^70)
println("PROJECT-WIDE ANALYSIS TOOL")
println("="^70)
println()

# Define a set of functions you want to check for static compilation
# In a real project, these would be in your actual codebase

# Function 1: Simple math (should compile)
function compute_area(width::Float64, height::Float64)
    return width * height
end

# Function 2: Has abstract types (won't compile)
function process_value(x::Number)
    return x^2 + 2x + 1
end

# Function 3: Uses allocations (won't compile)
function sum_range(n::Int)
    nums = collect(1:n)
    return sum(nums)
end

# Function 4: Complex but valid (should compile)
function factorial_iter(n::Int)
    result = 1
    for i in 2:n
        result *= i
    end
    return result
end

# Function 5: With conditional logic (should compile)
function clamp_value(x::Int, min_val::Int, max_val::Int)
    if x < min_val
        return min_val
    elseif x > max_val
        return max_val
    else
        return x
    end
end

# List of functions to analyze
functions_to_check = [
    ("compute_area", compute_area, (Float64, Float64)),
    ("process_value", process_value, (Number,)),
    ("sum_range", sum_range, (Int,)),
    ("factorial_iter", factorial_iter, (Int,)),
    ("clamp_value", clamp_value, (Int, Int, Int)),
]

# Analysis results storage
results = []

println("Analyzing $(length(functions_to_check)) functions...")
println()

# Analyze each function
for (name, func, types) in functions_to_check
    println("Checking: $name")
    println("-"^70)
    
    # Run all analyses
    ma = analyze_monomorphization(func, types)
    ea = analyze_escapes(func, types)
    da = analyze_devirtualization(func, types)
    la = analyze_lifetimes(func, types)
    
    # Determine compilation readiness
    issues = String[]
    
    if ma.has_abstract_types
        push!(issues, "Abstract types")
    end
    
    if length(ea.allocations) > 0
        push!(issues, "$(length(ea.allocations)) heap allocation(s)")
    end
    
    if da.total_dynamic_calls > 3  # Some dynamic calls are OK
        push!(issues, "$(da.total_dynamic_calls) dynamic calls")
    end
    
    if la.potential_leaks > 0
        push!(issues, "$(la.potential_leaks) memory leak(s)")
    end
    
    # Calculate readiness score
    score = 100
    score -= ma.has_abstract_types ? 40 : 0
    score -= min(length(ea.allocations) * 10, 30)
    score -= min(da.total_dynamic_calls * 2, 20)
    score -= la.potential_leaks * 10
    score = max(0, score)
    
    ready = isempty(issues)
    
    # Display results
    if ready
        println("  ✅ READY (score: $score/100)")
    else
        println("  ❌ NOT READY (score: $score/100)")
        for issue in issues
            println("     • $issue")
        end
    end
    
    # Store results
    push!(results, (
        name = name,
        ready = ready,
        score = score,
        issues = issues,
        abstract_types = ma.has_abstract_types,
        allocations = length(ea.allocations),
        dynamic_calls = da.total_dynamic_calls,
        leaks = la.potential_leaks
    ))
    
    println()
end

# Generate summary report
println("="^70)
println("SUMMARY REPORT")
println("="^70)
println()

ready_count = count(r -> r.ready, results)
total_count = length(results)

println("Functions analyzed: $total_count")
println("Ready for compilation: $ready_count ($ready_count/$total_count)")
println("Need fixes: $(total_count - ready_count)")
println()

# Show ready functions
ready_funcs = filter(r -> r.ready, results)
if !isempty(ready_funcs)
    println("✅ READY FOR COMPILATION:")
    for r in ready_funcs
        println("   • $(r.name) (score: $(r.score)/100)")
    end
    println()
end

# Show functions needing work
not_ready = filter(r -> !r.ready, results)
if !isempty(not_ready)
    println("❌ NEED FIXES:")
    for r in not_ready
        println("   • $(r.name) (score: $(r.score)/100)")
        for issue in r.issues
            println("     - $issue")
        end
    end
    println()
end

# Priority ranking
println("="^70)
println("PRIORITY RANKING (by score)")
println("="^70)
sorted_results = sort(results, by=r->r.score, rev=true)

for (i, r) in enumerate(sorted_results)
    status = r.ready ? "✅" : "❌"
    bar_len = div(r.score, 2)  # Scale to 50 chars
    bar = "█"^bar_len * "░"^(50-bar_len)
    println("$i. $status $(rpad(r.name, 20)) │$bar│ $(r.score)/100")
end
println()

# Issue statistics
println("="^70)
println("ISSUE BREAKDOWN")
println("="^70)

abstract_count = count(r -> r.abstract_types, results)
alloc_count = count(r -> r.allocations > 0, results)
dispatch_count = count(r -> r.dynamic_calls > 3, results)
leak_count = count(r -> r.leaks > 0, results)

total_issues = abstract_count + alloc_count + dispatch_count + leak_count

if total_issues > 0
    println("Total issues found: $total_issues")
    println()
    println("By category:")
    println("  • Abstract types:     $abstract_count")
    println("  • Heap allocations:   $alloc_count")
    println("  • Dynamic dispatch:   $dispatch_count")
    println("  • Memory leaks:       $leak_count")
else
    println("✅ No issues found! All functions ready for compilation.")
end
println()

# Recommendations
println("="^70)
println("RECOMMENDATIONS")
println("="^70)

if abstract_count > 0
    println("📝 Abstract Types ($abstract_count functions):")
    println("   Replace abstract types (Number, Real) with concrete types (Int, Float64)")
    println("   Or use type parameters: function f(x::T) where {T<:Number}")
    println()
end

if alloc_count > 0
    println("📝 Heap Allocations ($alloc_count functions):")
    println("   • Use StaticArrays for fixed-size arrays")
    println("   • Use MallocArray for dynamic sizes (remember to free!)")
    println("   • Consider Bumper.jl for arena allocation")
    println()
end

if dispatch_count > 0
    println("📝 Dynamic Dispatch ($dispatch_count functions):")
    println("   Use concrete types to enable compile-time method resolution")
    println()
end

if leak_count > 0
    println("📝 Memory Leaks ($leak_count functions):")
    println("   Add free() calls for all MallocArray allocations")
    println()
end

println("="^70)
println("Next steps:")
println("1. Fix high-priority functions (highest scores)")
println("2. Address one issue type at a time")
println("3. Re-run analysis after each fix")
println("4. Compile ready functions with compile_shlib()")
println("="^70)
