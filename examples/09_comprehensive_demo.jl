# Example 9: Comprehensive Feature Demonstration
# This example showcases ALL features of the compiler analysis infrastructure

using StaticCompiler
using StaticTools

println("="^70)
println("COMPREHENSIVE COMPILER ANALYSIS DEMONSTRATION")
println("="^70)
println()
println("This example demonstrates all features:")
println("  1. Core analysis functions")
println("  2. Quick check and batch analysis")
println("  3. Optimization suggestions")
println("  4. Safe compilation")
println("  5. Report tracking and comparison")
println("  6. CI/CD integration")
println("  7. Module scanning")
println("  8. Performance caching")
println("  9. Benchmarking")
println(" 10. Interactive features")
println()
println("="^70)
println()

# Define example functions
function optimized_func(a::Int, b::Int)
    return a + b
end

function needs_work(x::Number)  # Abstract type
    arr = zeros(5)  # Allocation
    return sum(arr) + x
end

function fibonacci(n::Int)
    if n <= 1
        return n
    end
    a, b = 0, 1
    for i in 2:n
        a, b = b, a + b
    end
    return b
end

# ============================================================================
println("SECTION 1: Core Analysis Functions")
println("="^70)
println()

println("1.1 Individual Analyses")
println("-"^70)

ma = analyze_monomorphization(optimized_func, (Int, Int))
println("Monomorphization: Abstract types = $(ma.has_abstract_types)")

ea = analyze_escapes(optimized_func, (Int, Int))
println("Escape Analysis: Allocations = $(length(ea.allocations))")

da = analyze_devirtualization(optimized_func, (Int, Int))
println("Devirtualization: Dynamic calls = $(da.total_dynamic_calls)")

ca = analyze_constants(optimized_func, (Int, Int))
println("Constants: Foldable = $(ca.foldable_expressions)")

la = analyze_lifetimes(optimized_func, (Int, Int))
println("Lifetimes: Potential leaks = $(la.potential_leaks)")
println()

# ============================================================================
println("SECTION 2: Quick Check and Batch Analysis")
println("="^70)
println()

println("2.1 Quick Check")
println("-"^70)
report = quick_check(optimized_func, (Int, Int))
println("Score: $(report.score)/100")
println("Ready: $(report.ready_for_compilation)")
println()

println("2.2 Batch Analysis")
println("-"^70)
functions_to_check = [
    (optimized_func, (Int, Int)),
    (needs_work, (Number,)),
    (fibonacci, (Int,))
]

results = batch_check(functions_to_check)
println("Analyzed $(length(results)) functions")
for (name, rep) in sort(collect(results), by=x->x[2].score, rev=true)
    status = rep.ready_for_compilation ? "✅" : "❌"
    println("  $status $name: $(rep.score)/100")
end
println()

# ============================================================================
println("SECTION 3: Optimization Suggestions")
println("="^70)
println()

println("Getting suggestions for problematic function...")
suggest_optimizations(needs_work, (Number,))
println()

# ============================================================================
println("SECTION 4: Safe Compilation")
println("="^70)
println()

println("Attempting safe compilation of fibonacci...")
lib_path = safe_compile_shlib(fibonacci, (Int,), tempdir(), "fib_demo",
                               threshold=80, export_report=false)

if lib_path !== nothing
    println("✅ Successfully compiled")
else
    println("⚠️  Compilation skipped (quality too low)")
end
println()

# ============================================================================
println("SECTION 5: Report Tracking and Comparison")
println("="^70)
println()

println("5.1 Export Report")
println("-"^70)
baseline_report = quick_check(needs_work, (Number,))
export_report(baseline_report, tempdir() * "/baseline_demo.json")
println()

println("5.2 Track Quality Over Time")
println("-"^70)
track_quality_over_time(optimized_func, (Int, Int),
                       tempdir() * "/quality_demo.json")
println()

println("5.3 Compare Reports")
println("-"^70)
improved_report = quick_check(fibonacci, (Int,))
compare_reports(baseline_report, improved_report)
println()

# ============================================================================
println("SECTION 6: CI/CD Integration")
println("="^70)
println()

println("6.1 Generate CI Report")
println("-"^70)
generate_ci_report(results, tempdir() * "/ci_demo")
println()

println("6.2 Quality Gate Check")
println("-"^70)
passed = check_quality_gate(results,
                            min_ready_percent=60,
                            min_avg_score=65,
                            exit_on_fail=false)
println()

println("6.3 GitHub Actions Integration")
println("-"^70)
generate_github_actions_summary(results)
annotate_github_actions(results, error_threshold=50, warning_threshold=80)
println()

# ============================================================================
println("SECTION 7: Module Scanning")
println("="^70)
println()

# Create a test module
module DemoModule
    func1(x::Int) = x * 2
    func2(a::Int, b::Int) = a + b
    func3(x::Number) = x + 1  # Abstract type
end

println("Scanning DemoModule...")
functions = scan_module(DemoModule)
println("Found $(length(functions)) functions")
println()

println("Analyzing entire module...")
module_analysis = analyze_module(DemoModule, threshold=80, verbose=false)
println("Summary:")
println("  Total: $(module_analysis[:summary][:total])")
println("  Ready: $(module_analysis[:summary][:ready])")
println("  Score: $(module_analysis[:summary][:average_score])/100")
println()

# ============================================================================
println("SECTION 8: Performance Caching")
println("="^70)
println()

println("8.1 First Analysis (no cache)")
println("-"^70)
@time report1 = quick_check_cached(optimized_func, (Int, Int))
println()

println("8.2 Second Analysis (from cache)")
println("-"^70)
@time report2 = quick_check_cached(optimized_func, (Int, Int))
println()

println("8.3 Cache Statistics")
println("-"^70)
stats = cache_stats()
println("Entries: $(stats[:entries])")
println("Memory:  $(stats[:memory]) MB")
println()

# ============================================================================
println("SECTION 9: Benchmarking")
println("="^70)
println()

println("9.1 Benchmark Analysis Performance")
println("-"^70)
bench_stats = benchmark_analysis(optimized_func, (Int, Int), samples=5)
println()

println("9.2 Track Quality History")
println("-"^70)
history_file = tempdir() * "/history_demo.json"

# Add multiple entries
for i in 1:3
    track_quality_over_time(optimized_func, (Int, Int), history_file)
    sleep(0.1)  # Small delay between entries
end
println()

println("9.3 Plot Quality History")
println("-"^70)
plot_quality_history(history_file)
println()

# ============================================================================
println("SECTION 10: Interactive Features")
println("="^70)
println()

println("10.1 Interactive Functions")
println("-"^70)
println("Note: start_interactive() launches an interactive REPL")
println("      Try: julia -e 'using StaticCompiler; start_interactive()'")
println()

println("10.2 Programmatic Interactive Use")
println("-"^70)
interactive_report = interactive_analyze(fibonacci, (Int,))
println("Interactive analysis score: $(interactive_report.score)/100")
println()

# ============================================================================
println("="^70)
println("DEMONSTRATION COMPLETE")
println("="^70)
println()

println("Summary of Demonstrated Features:")
println()
println("✅ Core Analysis (5 functions)")
println("   - Monomorphization, Escape, Devirtualization")
println("   - Constant Propagation, Lifetime")
println()
println("✅ Convenience Layer")
println("   - quick_check, batch_check")
println("   - Formatted reporting")
println()
println("✅ Optimization")
println("   - Automatic suggestions with code examples")
println("   - Before/after comparisons")
println()
println("✅ Safe Compilation")
println("   - Automatic verification before compilation")
println("   - Configurable thresholds")
println()
println("✅ Report Management")
println("   - Export/import JSON")
println("   - Compare versions")
println("   - Track history")
println()
println("✅ CI/CD Integration")
println("   - Quality gates")
println("   - GitHub Actions support")
println("   - Report generation")
println()
println("✅ Project Tools")
println("   - Module scanning")
println("   - Module-wide analysis")
println()
println("✅ Performance")
println("   - Result caching (10-100x speedup)")
println("   - Cache management")
println()
println("✅ Benchmarking")
println("   - Performance analysis")
println("   - Quality tracking")
println("   - Historical visualization")
println()
println("✅ Interactive")
println("   - REPL mode")
println("   - Session management")
println()
println("="^70)
println()
println("For more information:")
println("  - Comprehensive Guide: docs/guides/COMPILER_ANALYSIS_GUIDE.md")
println("  - Examples: examples/")
println("  - CI/CD Integration: .github/workflows/README.md")
println("  - Pre-commit Hooks: hooks/README.md")
println()
println("="^70)
