# Quick Analysis Utilities
# Convenience functions for running multiple analyses at once

using Dates
import JSON

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

"""
    verify_compilation_readiness(f::Function, types::Tuple; threshold::Int=80, verbose::Bool=true) -> Bool

Check if a function is ready for compilation and warn if not.

Returns `true` if the function is ready (score >= threshold), `false` otherwise.
If `verbose=true`, prints warnings about issues found.

# Example
```julia
julia> if verify_compilation_readiness(my_func, (Int,))
           compile_shlib(my_func, (Int,), "./")
       end
```
"""
function verify_compilation_readiness(f::Function, types::Tuple; threshold::Int=80, verbose::Bool=true)
    report = quick_check(f, types)

    if report.score >= threshold
        verbose && println("✅ $(report.function_name) is ready for compilation (score: $(report.score)/100)")
        return true
    else
        if verbose
            println("⚠️  $(report.function_name) may not compile successfully (score: $(report.score)/100)")
            println("   Issues found:")
            for issue in report.issues
                println("     • $issue")
            end
            println("   Use quick_check() for detailed analysis or force=true to compile anyway")
        end
        return false
    end
end

"""
    compare_reports(old::CompilationReadinessReport, new::CompilationReadinessReport)

Compare two compilation readiness reports and show improvements or regressions.

# Example
```julia
julia> old_report = quick_check(my_func, (Int,))
julia> # ... make improvements ...
julia> new_report = quick_check(my_func, (Int,))
julia> compare_reports(old_report, new_report)
```
"""
function compare_reports(old::CompilationReadinessReport, new::CompilationReadinessReport)
    println("="^70)
    println("COMPILATION READINESS COMPARISON: $(new.function_name)")
    println("="^70)
    println()

    # Score comparison
    score_diff = new.score - old.score
    score_arrow = score_diff > 0 ? "⬆" : score_diff < 0 ? "⬇" : "➡"
    score_color = score_diff > 0 ? "✅" : score_diff < 0 ? "❌" : "➡️"

    println("Score Change: $(old.score)/100 → $(new.score)/100 ($score_arrow $(abs(score_diff)))")
    println("Status: $score_color")
    println()

    # Readiness status
    if !old.ready_for_compilation && new.ready_for_compilation
        println("🎉 Function is now ready for compilation!")
    elseif old.ready_for_compilation && !new.ready_for_compilation
        println("⚠️  Function was ready but now has issues")
    end
    println()

    # Issue comparison
    println("Issue Changes:")
    old_issues = Set(old.issues)
    new_issues = Set(new.issues)

    fixed_issues = setdiff(old_issues, new_issues)
    new_problems = setdiff(new_issues, old_issues)
    remaining = intersect(old_issues, new_issues)

    if !isempty(fixed_issues)
        println("  ✅ Fixed:")
        for issue in fixed_issues
            println("     • $issue")
        end
    end

    if !isempty(new_problems)
        println("  ❌ New problems:")
        for issue in new_problems
            println("     • $issue")
        end
    end

    if !isempty(remaining)
        println("  ⚠️  Still present:")
        for issue in remaining
            println("     • $issue")
        end
    end

    if isempty(old_issues) && isempty(new_issues)
        println("  No issues in either version ✅")
    end

    println()

    # Detailed metric changes
    println("Detailed Changes:")

    # Monomorphization
    if old.monomorphization.has_abstract_types != new.monomorphization.has_abstract_types
        status = new.monomorphization.has_abstract_types ? "❌ Introduced" : "✅ Removed"
        println("  Abstract types: $status")
    end

    # Allocations
    old_allocs = length(old.escape_analysis.allocations)
    new_allocs = length(new.escape_analysis.allocations)
    if old_allocs != new_allocs
        diff = new_allocs - old_allocs
        symbol = diff > 0 ? "❌ +" : "✅ "
        println("  Allocations: $old_allocs → $new_allocs ($symbol$diff)")
    end

    # Dynamic calls
    old_calls = old.devirtualization.total_dynamic_calls
    new_calls = new.devirtualization.total_dynamic_calls
    if old_calls != new_calls
        diff = new_calls - old_calls
        symbol = diff > 0 ? "❌ +" : "✅ "
        println("  Dynamic calls: $old_calls → $new_calls ($symbol$diff)")
    end

    # Memory leaks
    old_leaks = old.lifetime_analysis.potential_leaks
    new_leaks = new.lifetime_analysis.potential_leaks
    if old_leaks != new_leaks
        diff = new_leaks - old_leaks
        symbol = diff > 0 ? "❌ +" : "✅ "
        println("  Memory leaks: $old_leaks → $new_leaks ($symbol$diff)")
    end

    println()
    println("="^70)
end

"""
    export_report(report::CompilationReadinessReport, filename::String)

Export a compilation readiness report to a JSON file for later comparison.

# Example
```julia
julia> report = quick_check(my_func, (Int,))
julia> export_report(report, "baseline_report.json")
```
"""
function export_report(report::CompilationReadinessReport, filename::String)
    # Create a serializable dictionary
    data = Dict(
        "function_name" => string(report.function_name),
        "ready_for_compilation" => report.ready_for_compilation,
        "score" => report.score,
        "issues" => report.issues,
        "timestamp" => string(now()),
        "metrics" => Dict(
            "has_abstract_types" => report.monomorphization.has_abstract_types,
            "specialization_factor" => report.monomorphization.specialization_factor,
            "allocations" => length(report.escape_analysis.allocations),
            "promotable_allocations" => report.escape_analysis.promotable_allocations,
            "dynamic_calls" => report.devirtualization.total_dynamic_calls,
            "devirtualizable_calls" => report.devirtualization.devirtualizable_calls,
            "foldable_expressions" => report.constant_propagation.foldable_expressions,
            "potential_leaks" => report.lifetime_analysis.potential_leaks,
            "proper_frees" => report.lifetime_analysis.proper_frees
        )
    )

    # Write to JSON file
    open(filename, "w") do io
        JSON.print(io, data, 2)
    end

    println("✅ Report exported to $filename")
end

"""
    import_report_summary(filename::String) -> Dict

Import a previously exported compilation readiness report summary.

Returns a dictionary with the report data. Use this for comparison or tracking progress.

# Example
```julia
julia> old_data = import_report_summary("baseline_report.json")
julia> new_report = quick_check(my_func, (Int,))
julia> println("Score improved by: ", new_report.score - old_data["score"])
```
"""
function import_report_summary(filename::String)
    data = JSON.parsefile(filename)
    println("✅ Loaded report for $(data["function_name"]) (score: $(data["score"])/100)")
    return data
end

# Export new functions
export quick_check, CompilationReadinessReport
export print_readiness_report, batch_check, print_batch_summary
export verify_compilation_readiness, compare_reports
export export_report, import_report_summary
