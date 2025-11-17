# Example 10: Integrated Pre-Compilation Verification
#
# This example demonstrates the new `verify=true` parameter that integrates
# automatic code analysis directly into compile_shlib and compile_executable.
#
# This is more convenient than using safe_compile_* functions since you can
# just add `verify=true` to your existing compilation calls.

using StaticCompiler
using StaticTools

println("="^70)
println("Example 10: Integrated Pre-Compilation Verification")
println("="^70)
println()

# ============================================================================
# Section 1: Basic Integrated Verification
# ============================================================================

println("Section 1: Basic Integrated Verification")
println("-"^70)
println()

# A simple, well-optimized function that should pass verification
function simple_sum(n::Int)
    result = 0
    for i in 1:n
        result += i
    end
    return result
end

println("Example 1a: Compiling with verification (should pass)")
println()

# Compile with verification - this will automatically analyze the function
# before compilation and only compile if the score is >= 80
try
    lib_path = compile_shlib(simple_sum, (Int,), tempdir(), "simple_sum",
                             verify=true)  # Enable automatic verification
    println("Success! Compiled to: $lib_path")
    println()
catch e
    println("Failed: $e")
    println()
end

# ============================================================================
# Section 2: Custom Score Thresholds
# ============================================================================

println()
println("Section 2: Custom Score Thresholds")
println("-"^70)
println()

println("Example 2a: Setting a high quality threshold (min_score=95)")
println()

try
    lib_path = compile_shlib(simple_sum, (Int,), tempdir(), "simple_sum_strict",
                             verify=true,
                             min_score=95)  # Require very high quality
    println("Success! Function meets high standards.")
    println()
catch e
    println("Function didn't meet the threshold:")
    println(e)
    println()
end

# ============================================================================
# Section 3: Detecting Problematic Code
# ============================================================================

println()
println("Section 3: Detecting Problematic Code")
println("-"^70)
println()

# A function with heap allocations (will have lower score)
function allocating_function(n::Int)
    arr = Float64[i for i in 1:n]  # Heap allocation!
    return sum(arr)
end

println("Example 3a: Attempting to compile problematic code")
println()

try
    lib_path = compile_shlib(allocating_function, (Int,), tempdir(), "bad_func",
                             verify=true,
                             min_score=80)
    println("Success (unexpectedly)!")
    println()
catch e
    println("Verification correctly prevented compilation!")
    println()
end

# ============================================================================
# Section 4: Exporting Analysis Reports
# ============================================================================

println()
println("Section 4: Exporting Analysis Reports")
println("-"^70)
println()

println("Example 4a: Compiling with report export")
println()

report_dir = mktempdir()
try
    lib_path = compile_shlib(simple_sum, (Int,), report_dir, "simple_sum_report",
                             verify=true,
                             export_analysis=true)  # Export JSON report

    println("Compiled successfully!")
    println("Analysis report saved to: $report_dir")

    # Check if report exists
    report_file = joinpath(report_dir, "simple_sum_analysis.json")
    if isfile(report_file)
        println("✅ Report file exists: $report_file")
        println("   Size: $(filesize(report_file)) bytes")
    end
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 5: Batch Compilation with Verification
# ============================================================================

println()
println("Section 5: Batch Compilation with Verification")
println("-"^70)
println()

# Multiple functions to compile together
function add_ints(a::Int, b::Int)
    return a + b
end

function multiply_ints(a::Int, b::Int)
    return a * b
end

function subtract_ints(a::Int, b::Int)
    return a - b
end

println("Example 5a: Batch compilation with verification")
println()

funcs = [
    (add_ints, (Int, Int)),
    (multiply_ints, (Int, Int)),
    (subtract_ints, (Int, Int))
]

try
    lib_path = compile_shlib(funcs, tempdir(),
                             filename="math_ops",
                             verify=true,        # Verify all functions
                             min_score=80)
    println("All functions passed and compiled successfully!")
    println("Library: $lib_path")
    println()
catch e
    println("One or more functions failed verification")
    println()
end

# ============================================================================
# Section 6: Executable Compilation with Verification
# ============================================================================

println()
println("Section 6: Executable Compilation with Verification")
println("-"^70)
println()

function hello_main()
    println(c"Hello from verified executable!")
    return 0
end

println("Example 6a: Compiling executable with verification")
println()

try
    exe_path = compile_executable(hello_main, (), tempdir(), "hello_verified",
                                  verify=true,
                                  min_score=75)
    println("Executable compiled successfully!")
    println("Path: $exe_path")
    println()
catch e
    println("Failed: $e")
    println()
end

# ============================================================================
# Section 7: Comparison with safe_compile_* Functions
# ============================================================================

println()
println("Section 7: Comparison of Approaches")
println("-"^70)
println()

println("Approach 1: Original (no verification)")
println("  compile_shlib(func, types, path, name)")
println()

println("Approach 2: Explicit safe compilation")
println("  safe_compile_shlib(func, types, path, name, threshold=80)")
println()

println("Approach 3: Integrated verification (NEW!)")
println("  compile_shlib(func, types, path, name, verify=true)")
println()

println("Benefits of integrated verification:")
println("  ✓ More convenient - just add verify=true")
println("  ✓ Works with existing code")
println("  ✓ Customizable thresholds")
println("  ✓ Optional report export")
println("  ✓ Works with batch compilation")
println("  ✓ Backward compatible (verify=false by default)")
println()

# ============================================================================
# Section 8: Verification with Optimization Suggestions
# ============================================================================

println()
println("Section 8: Getting Optimization Suggestions")
println("-"^70)
println()

# A function that could be improved
function suboptimal_function(x::Float64)
    # Using Any type (bad for performance)
    temp::Any = x * 2.0
    return Float64(temp)
end

println("Example 8a: Verification with suggestions")
println()

try
    compile_shlib(suboptimal_function, (Float64,), tempdir(), "suboptimal",
                  verify=true,
                  min_score=90,
                  suggest_fixes=true)  # Show suggestions on failure
catch e
    println("Verification failed with suggestions")
    println()

    # Now get detailed suggestions
    println("Getting detailed optimization suggestions...")
    println()
    suggestions = suggest_optimizations(suboptimal_function, (Float64,))
    # Suggestions will be printed automatically
end

# ============================================================================
# Section 9: Production Workflow Example
# ============================================================================

println()
println("Section 9: Recommended Production Workflow")
println("-"^70)
println()

println("Step 1: Development - Use verify=true with lower threshold")
println("  compile_shlib(func, types, path, name, verify=true, min_score=70)")
println()

println("Step 2: Testing - Use moderate threshold")
println("  compile_shlib(func, types, path, name, verify=true, min_score=80)")
println()

println("Step 3: Production - Use high threshold with reports")
println("  compile_shlib(func, types, path, name,")
println("                verify=true,")
println("                min_score=90,")
println("                export_analysis=true)")
println()

println("Step 4: CI/CD - Enforce quality gates")
println("  compile_shlib(func, types, path, name, verify=true, min_score=85)")
println()

# ============================================================================
# Summary
# ============================================================================

println()
println("="^70)
println("SUMMARY")
println("="^70)
println()
println("The integrated verification feature makes it easy to ensure code")
println("quality without changing your existing compilation workflow.")
println()
println("Key benefits:")
println("  1. Prevents compilation of problematic code")
println("  2. Catches issues early in development")
println("  3. Provides actionable feedback")
println("  4. Integrates seamlessly with existing code")
println("  5. Configurable quality thresholds")
println("  6. Optional detailed reports")
println()
println("Usage:")
println("  # Enable verification")
println("  compile_shlib(func, types, path, name, verify=true)")
println()
println("  # Custom threshold")
println("  compile_shlib(func, types, path, name, verify=true, min_score=90)")
println()
println("  # With report export")
println("  compile_shlib(func, types, path, name, verify=true, export_analysis=true)")
println()
println("="^70)
