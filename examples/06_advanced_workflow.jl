# Example 6: Advanced Analysis Workflow
# This example shows verification, comparison, and export/import features

using StaticCompiler
using StaticTools

println("="^70)
println("ADVANCED ANALYSIS WORKFLOW")
println("="^70)
println()

# Define a function with issues
function calculate_sum_v1(n::Number)  # Abstract type
    result = zeros(n)  # Heap allocation
    for i in 1:n
        result[i] = i
    end
    return sum(result)
end

# Example 1: Verification before compilation
println("Example 1: Verify compilation readiness")
println("-"^70)

println("\nChecking v1 (has issues):")
is_ready = verify_compilation_readiness(calculate_sum_v1, (Int,))
println()

# Get baseline report and export it
println("Example 2: Export baseline report")
println("-"^70)

baseline = quick_check(calculate_sum_v1, (Int,))
export_report(baseline, tempdir() * "/baseline_report.json")
println()

# Improve the function - remove abstract type
function calculate_sum_v2(n::Int)  # Concrete type!
    result = zeros(n)  # Still has heap allocation
    for i in 1:n
        result[i] = i
    end
    return sum(result)
end

println("Example 3: Compare improvements")
println("-"^70)

improved_v2 = quick_check(calculate_sum_v2, (Int,))
compare_reports(baseline, improved_v2)
println()

# Further improvement - use static allocation
function calculate_sum_v3(n::Int)
    # Use StaticTools for manual memory management
    result = MallocArray{Float64}(undef, n)
    for i in 1:n
        result[i] = i
    end
    total = 0.0
    for i in 1:n
        total += result[i]
    end
    free(result)
    return total
end

println("Example 4: Track progress across versions")
println("-"^70)

improved_v3 = quick_check(calculate_sum_v3, (Int,))
compare_reports(improved_v2, improved_v3)
println()

# Final version - optimal
function calculate_sum_v4(n::Int)
    # Mathematical formula - no allocations!
    return Float64(n * (n + 1) / 2)
end

println("Example 5: Final optimization")
println("-"^70)

final_version = quick_check(calculate_sum_v4, (Int,))
compare_reports(improved_v3, final_version)
println()

# Export final report
export_report(final_version, tempdir() * "/final_report.json")
println()

# Show compilation verification
println("Example 6: Verify and compile final version")
println("-"^70)

if verify_compilation_readiness(calculate_sum_v4, (Int,), threshold = 90)
    println("\nCompiling optimized function...")
    try
        lib_path = compile_shlib(calculate_sum_v4, (Int,), tempdir(), "calculate_sum")
        println("Compilation successful: $lib_path")
    catch e
        println("Compilation failed: $e")
    end
else
    println("\nFunction needs more optimization")
end
println()

# Load and compare reports
println("Example 7: Load and compare saved reports")
println("-"^70)

println("\nLoading baseline report:")
baseline_data = import_report_summary(tempdir() * "/baseline_report.json")

println("\nLoading final report:")
final_data = import_report_summary(tempdir() * "/final_report.json")

println("\nProgress Summary:")
println("   Initial score: $(baseline_data["score"])/100")
println("   Final score:   $(final_data["score"])/100")
println("   Improvement:   +$(final_data["score"] - baseline_data["score"]) points")
println()

println("   Initial issues:")
for issue in baseline_data["issues"]
    println("     • $issue")
end
println()

if isempty(final_data["issues"])
    println("   Final issues:  None!")
else
    println("   Final issues:")
    for issue in final_data["issues"]
        println("     • $issue")
    end
end
println()

println("="^70)
println("WORKFLOW SUMMARY")
println("="^70)
println("1. verify_compilation_readiness() - Check before compiling")
println("2. export_report() - Save analysis results")
println("3. compare_reports() - Track improvements")
println("4. import_report_summary() - Load saved reports")
println()
println("This workflow helps you:")
println("• Track optimization progress over time")
println("• Compare different implementations")
println("• Maintain compilation quality standards")
println("• Document improvements for team review")
println("="^70)
