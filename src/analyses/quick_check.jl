# Quick Analysis Utilities
# Convenience functions for running multiple analyses at once

"""
    CompilationReadinessReport

Comprehensive report combining results from all analysis functions.
"""
struct CompilationReadinessReport
    function_name::Symbol
    ready_for_compilation::Bool
    score::Int  # 0-100
    issues::Vector{String}
    
    # Individual reports
    monomorphization::MonomorphizationReport
    escape_analysis::EscapeAnalysisReport
    devirtualization::DevirtualizationReport
    constant_propagation::ConstantPropagationReport
    lifetime_analysis::LifetimeAnalysisReport
end

"""
    quick_check(f::Function, types::Tuple) -> CompilationReadinessReport

Run all compiler analyses on a function and return a comprehensive readiness report.

This convenience function runs all five analysis functions and combines the results
into a single report with a compilation readiness assessment.

# Example
```julia
julia> function my_func(x::Int)
           return x * 2
       end

julia> report = quick_check(my_func, (Int,))

julia> if report.ready_for_compilation
           compile_shlib(my_func, (Int,), "./")
       else
           println("Issues found: ", report.issues)
       end
```
"""
function quick_check(f::Function, types::Tuple)
    fname = nameof(f)
    
    # Run all analyses
    ma = analyze_monomorphization(f, types)
    ea = analyze_escapes(f, types)
    da = analyze_devirtualization(f, types)
    ca = analyze_constants(f, types)
    la = analyze_lifetimes(f, types)
    
    # Identify issues
    issues = String[]
    score = 100
    
    if ma.has_abstract_types
        push!(issues, "Contains abstract types")
        score -= 40
    end
    
    num_allocs = length(ea.allocations)
    if num_allocs > 0
        push!(issues, "$num_allocs heap allocation(s)")
        score -= min(num_allocs * 10, 30)
    end
    
    if da.total_dynamic_calls > 5
        push!(issues, "$(da.total_dynamic_calls) dynamic dispatch sites")
        score -= min(da.total_dynamic_calls, 20)
    end
    
    if la.potential_leaks > 0
        push!(issues, "$(la.potential_leaks) potential memory leak(s)")
        score -= la.potential_leaks * 10
    end
    
    score = max(0, score)
    ready = isempty(issues)
    
    return CompilationReadinessReport(
        fname,
        ready,
        score,
        issues,
        ma,
        ea,
        da,
        ca,
        la
    )
end

"""
    print_readiness_report(report::CompilationReadinessReport)

Print a formatted compilation readiness report.
"""
function print_readiness_report(report::CompilationReadinessReport)
    println("="^70)
    println("COMPILATION READINESS REPORT: $(report.function_name)")
    println("="^70)
    println()
    
    # Status
    status_icon = report.ready_for_compilation ? "✅" : "❌"
    status_text = report.ready_for_compilation ? "READY" : "NOT READY"
    println("Status: $status_icon $status_text")
    println("Score:  $(report.score)/100")
    println()
    
    # Issues
    if !isempty(report.issues)
        println("Issues Found:")
        for issue in report.issues
            println("  • $issue")
        end
        println()
    end
    
    # Detailed breakdown
    println("Detailed Analysis:")
    println("  Monomorphization:")
    println("    Abstract types: ", report.monomorphization.has_abstract_types ? "❌ YES" : "✅ NO")
    println("    Specialization: ", round(report.monomorphization.specialization_factor * 100, digits=1), "%")
    
    println("  Escape Analysis:")
    println("    Allocations: ", length(report.escape_analysis.allocations))
    println("    Stack-promotable: ", report.escape_analysis.promotable_allocations)
    
    println("  Devirtualization:")
    println("    Dynamic calls: ", report.devirtualization.total_dynamic_calls)
    println("    Devirtualizable: ", report.devirtualization.devirtualizable_calls)
    
    println("  Constant Propagation:")
    println("    Foldable expressions: ", report.constant_propagation.foldable_expressions)
    println("    Code reduction: ", round(report.constant_propagation.code_reduction_potential_pct, digits=1), "%")
    
    println("  Lifetime Analysis:")
    println("    Potential leaks: ", report.lifetime_analysis.potential_leaks)
    println("    Proper frees: ", report.lifetime_analysis.proper_frees)
    
    println()
    
    # Recommendations
    if !report.ready_for_compilation
        println("Recommendations:")
        if report.monomorphization.has_abstract_types
            println("  • Replace abstract types with concrete types")
        end
        if length(report.escape_analysis.allocations) > 0
            println("  • Use StaticArrays or MallocArray instead of standard arrays")
        end
        if report.devirtualization.total_dynamic_calls > 5
            println("  • Use concrete types to enable compile-time dispatch")
        end
        if report.lifetime_analysis.potential_leaks > 0
            println("  • Add free() calls for manual memory allocations")
        end
        println()
    end
    
    println("="^70)
end

"""
    batch_check(functions::Vector) -> Dict

Run quick_check on multiple functions and return results.

# Example
```julia
julia> results = batch_check([
           (func1, (Int,)),
           (func2, (Float64,)),
           (func3, (Int, Int))
       ])

julia> for (name, report) in results
           if report.ready_for_compilation
               println("✅ \$name is ready")
           end
       end
```
"""
function batch_check(functions::Vector)
    results = Dict{Symbol, CompilationReadinessReport}()
    
    for (f, types) in functions
        report = quick_check(f, types)
        results[report.function_name] = report
    end
    
    return results
end

"""
    print_batch_summary(results::Dict{Symbol, CompilationReadinessReport})

Print a summary of batch analysis results.
"""
function print_batch_summary(results::Dict{Symbol, CompilationReadinessReport})
    println("="^70)
    println("BATCH ANALYSIS SUMMARY")
    println("="^70)
    println()
    
    total = length(results)
    ready = count(r -> r.ready_for_compilation, values(results))
    
    println("Total functions: $total")
    println("Ready for compilation: $ready ($ready/$total)")
    println()
    
    # Sort by score
    sorted = sort(collect(results), by=x->x[2].score, rev=true)
    
    println("Function Rankings:")
    for (i, (name, report)) in enumerate(sorted)
        status = report.ready_for_compilation ? "✅" : "❌"
        bar_len = div(report.score, 2)
        bar = "█"^bar_len * "░"^(50-bar_len)
        separator = "│"
        println("$i. $status $(rpad(string(name), 25)) $separator$bar$separator $(report.score)/100")
    end
    
    println()
    println("="^70)
end

# Export new functions
export quick_check, CompilationReadinessReport
export print_readiness_report, batch_check, print_batch_summary
