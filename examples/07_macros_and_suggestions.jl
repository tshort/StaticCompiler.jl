# Example 7: Macros and Automatic Suggestions
# This example shows the convenience macros and optimization suggestion features

using StaticCompiler
using StaticTools

println("="^70)
println("MACROS AND AUTOMATIC OPTIMIZATION SUGGESTIONS")
println("="^70)
println()

# Example 1: Using the @analyze macro for inline analysis
println("Example 1: @analyze macro - Analyze function calls inline")
println("-"^70)
println()

# Good function - ready for compilation
function multiply_numbers(a::Int, b::Int)
    return a * b
end

println("Analyzing good function with @analyze:")
result = @analyze multiply_numbers(10, 20)
println("Function executed and returned:", result)
println()

# Example 2: Using @check_ready for quick verification
println("Example 2: @check_ready macro - Quick verification")
println("-"^70)
println()

function add_values(x::Int, y::Int)
    return x + y
end

println("Checking if function is ready:")
ready = @check_ready add_values(Int, Int)
println("Ready status:", ready)
println()

# Example 3: @quick_check for silent analysis
println("Example 3: @quick_check macro - Get report without printing")
println("-"^70)
println()

function compute_square(n::Int)
    return n * n
end

report = @quick_check compute_square(Int)
println("Got report silently, score:", report.score)
println("Ready for compilation:", report.ready_for_compilation)
println()

# Example 4: Problematic function - get suggestions
println("Example 4: @suggest_fixes - Automatic optimization suggestions")
println("-"^70)
println()

# Function with issues
function calculate_mean(values::Vector{Number})  # Abstract type!
    sum = 0.0
    for v in values  # Heap allocation!
        sum += v
    end
    return sum / length(values)
end

println("Getting suggestions for problematic function:")
@suggest_fixes calculate_mean(Vector{Number})
println()

# Example 5: suggest_optimizations function
println("Example 5: suggest_optimizations() - Detailed suggestions")
println("-"^70)
println()

function process_data(n::Number)  # Abstract type
    result = zeros(5)  # Heap allocation
    for i in 1:5
        result[i] = n * i
    end
    return sum(result)
end

suggest_optimizations(process_data, (Number,))
println()

# Example 6: Batch suggestions
println("Example 6: suggest_optimizations_batch() - Multiple functions")
println("-"^70)
println()

function bad_func1(x::Real)  # Abstract
    return x * 2
end

function bad_func2(n::Int)
    arr = zeros(n)  # Allocation
    return sum(arr)
end

function good_func(x::Int)  # Good!
    return x * 3
end

suggestions = suggest_optimizations_batch([
    (bad_func1, (Real,)),
    (bad_func2, (Int,)),
    (good_func, (Int,))
])
println()

# Example 7: safe_compile_shlib - Safe compilation with verification
println("Example 7: safe_compile_shlib() - Safe compilation")
println("-"^70)
println()

# Good function
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

println("Attempting safe compilation (threshold=80):")
lib_path = safe_compile_shlib(fibonacci, (Int,), tempdir(), "fibonacci_safe",
                               threshold=80, export_report=true)

if lib_path !== nothing
    println("\n✅ Library created:", lib_path)
end
println()

# Example 8: safe_compile with low threshold
println("Example 8: safe_compile with problematic function")
println("-"^70)
println()

function not_ready_func(x::Number)  # Abstract type
    arr = zeros(10)  # Allocation
    return sum(arr) + x
end

println("Attempting safe compilation (will fail):")
result = safe_compile_shlib(not_ready_func, (Number,), tempdir(), "not_ready",
                            threshold=90, export_report=false)

if result === nothing
    println("Compilation was prevented due to low score ✅")
end
println()

# Example 9: Force compilation
println("Example 9: Force compilation despite warnings")
println("-"^70)
println()

println("Forcing compilation with force=true:")
try
    lib_path = safe_compile_shlib(not_ready_func, (Number,), tempdir(), "forced",
                                  threshold=90, force=true, export_report=false)
    println("Forced compilation succeeded (may have issues at runtime)")
catch e
    println("Even forced compilation failed due to fundamental issues")
end
println()

println("="^70)
println("FEATURE SUMMARY")
println("="^70)
println()
println("Macros for Convenience:")
println("  @analyze func(args...)        - Analyze and execute")
println("  @check_ready func(Types...)   - Quick readiness check")
println("  @quick_check func(Types...)   - Get report silently")
println("  @suggest_fixes func(Types...) - Get optimization suggestions")
println()
println("Suggestion Functions:")
println("  suggest_optimizations(f, types)       - Detailed suggestions")
println("  suggest_optimizations_batch(funcs)    - Batch suggestions")
println()
println("Safe Compilation:")
println("  safe_compile_shlib(...)     - Compile with verification")
println("  safe_compile_executable(...) - Compile executable with verification")
println()
println("Benefits:")
println("  ✅ Prevent compilation failures")
println("  ✅ Get specific fix suggestions")
println("  ✅ Track analysis reports")
println("  ✅ Set quality thresholds")
println("="^70)
