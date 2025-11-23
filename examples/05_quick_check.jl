# Example 5: Using quick_check for Fast Analysis
# This example shows the convenience quick_check function

using StaticCompiler

println("="^70)
println("QUICK CHECK UTILITY - FAST ANALYSIS")
println("="^70)
println()

# Define some test functions
function good_func(x::Int, y::Int)
    return x + y
end

function bad_func_abstract(x::Number)
    return x * 2
end

function bad_func_alloc(n::Int)
    arr = zeros(n)
    return sum(arr)
end

function marginal_func(x::Int)
    # Has some dynamic calls but might be acceptable
    return abs(x) + abs(x+1)
end

println("Example 1: Quick check on ready function")
println("-"^70)

report = quick_check(good_func, (Int, Int))
print_readiness_report(report)

println("\nExample 2: Quick check on function with issues")
println("-"^70)

report = quick_check(bad_func_abstract, (Number,))
print_readiness_report(report)

println("\nExample 3: Batch analysis of multiple functions")
println("-"^70)

functions = [
    (good_func, (Int, Int)),
    (bad_func_abstract, (Number,)),
    (bad_func_alloc, (Int,)),
    (marginal_func, (Int,))
]

results = batch_check(functions)
print_batch_summary(results)

println("\nExample 4: Using quick_check in decision logic")
println("-"^70)

function check_and_compile(f, types, path="./")
    report = quick_check(f, types)
    
    if report.ready_for_compilation
        println("$(report.function_name) is ready (score: $(report.score)/100)")
        println("   Attempting compilation...")
        try
            lib_path = compile_shlib(f, types, path, string(report.function_name))
            println("   Compiled successfully: $lib_path")
            return true
        catch e
            println("   Compilation failed: $e")
            return false
        end
    else
        println("$(report.function_name) is not ready (score: $(report.score)/100)")
        println("   Issues:")
        for issue in report.issues
            println("     • $issue")
        end
        return false
    end
end

# Try to compile good_func
println("\nAttempting to compile good_func:")
success = check_and_compile(good_func, (Int, Int), tempdir())

if success
    println("\nFunction compiled and ready to use!")
else
    println("\nFunction needs fixes before compilation")
end

println()
println("="^70)
println("KEY BENEFITS OF QUICK_CHECK:")
println("="^70)
println("• Single function call instead of 5 separate analyses")
println("• Combined readiness score (0-100)")
println("• Automatic issue detection and reporting")
println("• Works with batch_check for project-wide analysis")
println("• Print functions for formatted output")
println("="^70)
