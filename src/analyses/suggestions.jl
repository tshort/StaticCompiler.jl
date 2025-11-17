# Automatic optimization suggestions
# Provides specific code improvement recommendations

"""
    suggest_optimizations(f::Function, types::Tuple)

Analyze a function and provide specific, actionable optimization suggestions.

Returns a vector of suggestion strings with code examples.

# Example
```julia
julia> suggest_optimizations(my_func, (Number,))
```
"""
function suggest_optimizations(f::Function, types::Tuple)
    report = quick_check(f, types)
    suggestions = String[]

    println("="^70)
    println("OPTIMIZATION SUGGESTIONS: $(report.function_name)")
    println("="^70)
    println()
    println("Current Score: $(report.score)/100")
    println()

    if report.ready_for_compilation && report.score >= 95
        println("✅ Function is well-optimized! No major issues found.")
        println()
        println("="^70)
        return suggestions
    end

    suggestion_count = 0

    # Check for abstract types
    if report.monomorphization.has_abstract_types
        suggestion_count += 1
        println("$suggestion_count. Abstract Type Parameters")
        println("   " * "─"^66)
        println("   Issue: Function uses abstract types, preventing specialization")
        println()
        println("   ❌ Current (likely):")
        println("      function $(report.function_name)(x::Number)")
        println("          # ...")
        println("      end")
        println()
        println("   ✅ Fix Option 1 - Use concrete types:")
        println("      function $(report.function_name)(x::Int)")
        println("          # ...")
        println("      end")
        println()
        println("   ✅ Fix Option 2 - Use type parameters:")
        println("      function $(report.function_name)(x::T) where {T<:Number}")
        println("          # ...")
        println("      end")
        println()
        push!(suggestions, "Replace abstract types with concrete types or type parameters")
    end

    # Check for allocations
    alloc_count = length(report.escape_analysis.allocations)
    if alloc_count > 0
        suggestion_count += 1
        println("$suggestion_count. Heap Allocations ($alloc_count found)")
        println("   " * "─"^66)
        println("   Issue: Function allocates on the heap, slowing execution")
        println()

        # Check if it's array-related
        if any(contains(string(a), "Array") for a in report.escape_analysis.allocations)
            println("   ❌ Current (likely uses Array):")
            println("      function $(report.function_name)(n)")
            println("          arr = zeros(n)  # Heap allocation!")
            println("          # ...")
            println("      end")
            println()
            println("   ✅ Fix Option 1 - Use StaticArrays for fixed size:")
            println("      using StaticArrays")
            println("      function $(report.function_name)()")
            println("          arr = @SVector zeros(10)  # Stack allocation!")
            println("          # ...")
            println("      end")
            println()
            println("   ✅ Fix Option 2 - Use MallocArray for dynamic size:")
            println("      using StaticTools")
            println("      function $(report.function_name)(n)")
            println("          arr = MallocArray{Float64}(undef, n)")
            println("          # ... use arr ...")
            println("          free(arr)  # Don't forget!")
            println("          # ...")
            println("      end")
            println()
        end
        push!(suggestions, "Replace heap allocations with stack or manual memory management")
    end

    # Check for dynamic dispatch
    if report.devirtualization.total_dynamic_calls > 0
        dispatch_count = report.devirtualization.total_dynamic_calls
        suggestion_count += 1
        println("$suggestion_count. Dynamic Dispatch ($dispatch_count call sites)")
        println("   " * "─"^66)
        println("   Issue: Runtime method resolution prevents inlining/optimization")
        println()
        println("   Common causes:")
        println("   • Abstract type parameters")
        println("   • Type-unstable code (variable types change)")
        println("   • Missing type annotations")
        println()
        println("   ✅ Fixes:")
        println("      1. Add concrete type annotations")
        println("      2. Use type parameters: function f(x::T) where {T}")
        println("      3. Check with @code_warntype to find type instabilities")
        println()
        push!(suggestions, "Reduce dynamic dispatch by using concrete types")
    end

    # Check for memory leaks
    if report.lifetime_analysis.potential_leaks > 0
        leak_count = report.lifetime_analysis.potential_leaks
        suggestion_count += 1
        println("$suggestion_count. Potential Memory Leaks ($leak_count found)")
        println("   " * "─"^66)
        println("   Issue: Memory allocated but not freed")
        println()
        println("   ❌ Current:")
        println("      function $(report.function_name)(n)")
        println("          arr = MallocArray{Float64}(undef, n)")
        println("          # ... use arr ...")
        println("          return result  # LEAK: arr not freed!")
        println("      end")
        println()
        println("   ✅ Fix:")
        println("      function $(report.function_name)(n)")
        println("          arr = MallocArray{Float64}(undef, n)")
        println("          # ... use arr ...")
        println("          result = compute_result(arr)")
        println("          free(arr)  # ✅ Freed!")
        println("          return result")
        println("      end")
        println()
        push!(suggestions, "Add free() calls for all MallocArray allocations")
    end

    # Priority recommendations
    if suggestion_count > 0
        println()
        println("="^70)
        println("PRIORITY ORDER")
        println("="^70)
        println("1. Fix abstract types first (biggest impact)")
        println("2. Eliminate heap allocations")
        println("3. Reduce dynamic dispatch")
        println("4. Fix memory leaks")
        println()
        println("After each fix, re-run quick_check() to verify improvements.")
    end

    println("="^70)

    return suggestions
end

"""
    suggest_optimizations_batch(functions::Vector)

Provide optimization suggestions for multiple functions.

# Example
```julia
julia> suggest_optimizations_batch([
           (func1, (Int,)),
           (func2, (Float64,))
       ])
```
"""
function suggest_optimizations_batch(functions::Vector)
    println("="^70)
    println("BATCH OPTIMIZATION SUGGESTIONS")
    println("="^70)
    println()

    all_suggestions = Dict{Symbol, Vector{String}}()

    for (f, types) in functions
        fname = nameof(f)
        report = quick_check(f, types)

        if !report.ready_for_compilation || report.score < 95
            println("Function: $fname (score: $(report.score)/100)")
            println()
            suggestions = suggest_optimizations(f, types)
            all_suggestions[fname] = suggestions
            println()
        end
    end

    if isempty(all_suggestions)
        println("✅ All functions are well-optimized!")
    else
        println()
        println("="^70)
        println("SUMMARY: $(length(all_suggestions)) function(s) need optimization")
        println("="^70)
    end

    return all_suggestions
end

export suggest_optimizations, suggest_optimizations_batch
