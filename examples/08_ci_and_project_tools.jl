# Example 8: CI/CD Integration and Project-Wide Tools
# This example shows caching, CI/CD helpers, and project scanning

using StaticCompiler
using StaticTools

println("="^70)
println("CI/CD INTEGRATION AND PROJECT-WIDE TOOLS")
println("="^70)
println()

# Define some example functions
function fast_add(a::Int, b::Int)
    return a + b
end

function fast_multiply(a::Int, b::Int)
    return a * b
end

function slow_process(x::Number)  # Abstract type - problematic
    return x * 2
end

function allocating_func(n::Int)
    arr = zeros(n)  # Heap allocation
    return sum(arr)
end

function good_fibonacci(n::Int)
    if n <= 1
        return n
    end
    a, b = 0, 1
    for i in 2:n
        a, b = b, a + b
    end
    return b
end

# Example 1: Caching - Speed up repeated analysis
println("Example 1: Analysis Caching")
println("-"^70)
println()

println("First analysis (no cache):")
@time report1 = quick_check_cached(fast_add, (Int, Int))
println("Score: $(report1.score)/100")
println()

println("Second analysis (from cache - should be faster):")
@time report2 = quick_check_cached(fast_add, (Int, Int))
println("Score: $(report2.score)/100")
println()

# Check cache stats
stats = cache_stats()
println("Cache statistics:")
println("  Entries: $(stats[:entries])")
println("  Memory:  $(stats[:memory]) MB")
println()

# Example 2: Batch analysis with caching
println("Example 2: Batch Analysis with Caching")
println("-"^70)
println()

functions_to_analyze = [
    (fast_add, (Int, Int)),
    (fast_multiply, (Int, Int)),
    (slow_process, (Number,)),
    (allocating_func, (Int,)),
    (good_fibonacci, (Int,)),
]

println("Analyzing $(length(functions_to_analyze)) functions with caching...")
results = batch_check_cached(functions_to_analyze)

println("\nResults:")
for (name, report) in sort(collect(results), by = x -> x[2].score, rev = true)
    status = report.ready_for_compilation ? "" : ""
    println("  $status $name: $(report.score)/100")
end
println()

# Example 3: Generate CI report
println("Example 3: Generate CI Report")
println("-"^70)
println()

println("Generating CI-friendly reports...")
report_path = tempdir() * "/analysis_report"
md_path, json_path = generate_ci_report(results, report_path)

println("\nReading generated markdown report:")
println()
md_content = read(md_path, String)
# Print first 30 lines
lines = split(md_content, '\n')
for (i, line) in enumerate(lines[1:min(30, length(lines))])
    println(line)
end
if length(lines) > 30
    println("... ($(length(lines) - 30) more lines)")
end
println()

# Example 4: Quality gate check
println("Example 4: Quality Gate Check")
println("-"^70)
println()

println("Checking if code meets quality standards...")
passed = check_quality_gate(
    results,
    min_ready_percent = 60,
    min_avg_score = 70,
    exit_on_fail = false
)

if passed
    println("Would allow deployment ")
else
    println("Would block deployment ")
end
println()

# Example 5: GitHub Actions integration
println("Example 5: GitHub Actions Integration")
println("-"^70)
println()

println("Generating GitHub Actions summary...")
generate_github_actions_summary(results)
println()

println("Creating annotations for problematic functions...")
count = annotate_github_actions(results, error_threshold = 50, warning_threshold = 80)
println()

# Example 6: Module scanning (using a simple test module)
println("Example 6: Project/Module Scanning")
println("-"^70)
println()

# Create a small test module
println("Creating test module with functions...")

module TestModule
    function func1(x::Int)
        return x * 2
    end

    function func2(x::Number)  # Abstract
        return x + 1
    end

    function func3(a::Int, b::Int)
        return a + b
    end
end

println("Scanning TestModule...")
functions = scan_module(TestModule)
println("Found $(length(functions)) functions:")
for func in functions
    println("  - $(nameof(func))")
end
println()

# Analyze the entire module
println("Analyzing entire module...")
module_analysis = analyze_module(TestModule, threshold = 80, verbose = false)

println("\nModule Analysis Summary:")
println("  Total functions:     $(module_analysis[:summary][:total])")
println("  Ready:               $(module_analysis[:summary][:ready])")
println("  Average score:       $(module_analysis[:summary][:average_score])/100")
println("  Problematic:         $(length(module_analysis[:problematic]))")
println()

# Example 7: Cache management
println("Example 7: Cache Management")
println("-"^70)
println()

println("Current cache stats:")
stats = cache_stats()
println("  Entries: $(stats[:entries])")
println("  Memory:  $(stats[:memory]) MB")
println("  Oldest:  $(round(stats[:oldest], digits = 1))s ago")
println("  Newest:  $(round(stats[:newest], digits = 1))s ago")
println()

println("Clearing cache...")
cleared = clear_analysis_cache!()
println()

# Example 8: Using with_cache for automatic cleanup
println("Example 8: Automatic Cache Cleanup")
println("-"^70)
println()

println("Running analysis with automatic cache management...")
result = with_cache(ttl = 300.0) do
    # Analysis work happens here
    report = quick_check_cached(good_fibonacci, (Int,))
    return report.score
end

println("Result: $result/100")
println("Cache automatically pruned after execution")
println()

println("="^70)
println("FEATURE SUMMARY")
println("="^70)
println()
println("Caching:")
println("  quick_check_cached()  - Cache analysis results")
println("  batch_check_cached()  - Batch with caching")
println("  cache_stats()         - View cache statistics")
println("  clear_analysis_cache!() - Clear cache")
println("  with_cache()          - Auto-pruning wrapper")
println()
println("CI/CD Integration:")
println("  generate_ci_report()  - Create MD/JSON reports")
println("  check_quality_gate()  - Enforce quality standards")
println("  generate_github_actions_summary() - GH Actions integration")
println("  annotate_github_actions() - Create GH annotations")
println()
println("Project Scanning:")
println("  scan_module()         - Find all functions in module")
println("  analyze_module()      - Analyze entire module")
println("  compare_modules()     - Compare two modules")
println()
println("Benefits:")
println("  Faster repeated analysis (caching)")
println("  CI/CD integration (quality gates)")
println("  Project-wide analysis (find all functions)")
println("  Automated reporting (MD, JSON, GitHub)")
println("="^70)
