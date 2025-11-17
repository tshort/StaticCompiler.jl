# Safe compilation with automatic verification
# Integrates analysis checks with compilation process

# Note: These functions need to access the parent module's compile functions
# They will be available after the Analyses module is included in StaticCompiler

"""
    safe_compile_shlib(f::Function, tt::Tuple, path::String, name::String;
                       threshold::Int=80, force::Bool=false, export_report::Bool=true)

Safely compile a function to a shared library with automatic readiness verification.

# Arguments
- `f::Function`: Function to compile
- `tt::Tuple`: Argument type tuple
- `path::String`: Output directory
- `name::String`: Library name
- `threshold::Int=80`: Minimum readiness score required (0-100)
- `force::Bool=false`: Skip verification and compile anyway
- `export_report::Bool=true`: Export analysis report to JSON

# Returns
- Path to compiled library if successful
- `nothing` if verification fails and `force=false`

# Example
```julia
julia> lib_path = safe_compile_shlib(my_func, (Int,), "./", "my_func",
                                      threshold=90)
✅ my_func is ready for compilation (score: 95/100)
Compiling...
✅ Compilation successful
"./my_func.so"
```
"""
function safe_compile_shlib(f::Function, tt::Tuple, path::String, name::String;
                            threshold::Int=80, force::Bool=false, export_report::Bool=true)
    fname = nameof(f)

    # Run analysis
    println("Analyzing $fname...")
    report = quick_check(f, tt)

    # Export report if requested
    if export_report
        report_path = joinpath(path, "$(name)_analysis.json")
        try
            export_report(report, report_path)
        catch e
            @warn "Could not export analysis report" exception=e
        end
    end

    # Check readiness
    if !force
        if report.score < threshold
            println()
            println("❌ Compilation aborted: score $(report.score)/100 below threshold $threshold/100")
            println()
            println("Issues found:")
            for issue in report.issues
                println("  • $issue")
            end
            println()
            println("Options:")
            println("  1. Fix the issues above (recommended)")
            println("  2. Lower threshold: safe_compile_shlib(..., threshold=$(report.score))")
            println("  3. Force compilation: safe_compile_shlib(..., force=true)")
            println()
            println("💡 Run suggest_optimizations($fname, $tt) for fix suggestions")
            println()
            return nothing
        end

        println("✅ $fname is ready for compilation (score: $(report.score)/100)")
    else
        println("⚠️  Forcing compilation (score: $(report.score)/100)")
        if !isempty(report.issues)
            println("   Issues present:")
            for issue in report.issues
                println("     • $issue")
            end
        end
    end

    # Attempt compilation
    println()
    println("Compiling $fname to shared library...")
    try
        lib_path = compile_shlib(f, tt, path, name)
        println("✅ Compilation successful: $lib_path")
        println()

        # Print final summary
        println("="^70)
        println("COMPILATION SUMMARY")
        println("="^70)
        println("Function:       $fname")
        println("Readiness:      $(report.score)/100")
        println("Status:         ✅ Compiled")
        println("Library:        $lib_path")
        if export_report
            println("Analysis:       $(joinpath(path, "$(name)_analysis.json"))")
        end
        println("="^70)
        println()

        return lib_path
    catch e
        println("❌ Compilation failed!")
        println()
        println("Error: $e")
        println()
        println("This might be due to:")
        if report.score < 90
            println("  • Low compilation readiness score ($(report.score)/100)")
        end
        if report.monomorphization.has_abstract_types
            println("  • Abstract types in function signature")
        end
        if length(report.escape_analysis.allocations) > 0
            println("  • Heap allocations")
        end
        println()
        println("💡 Run suggest_optimizations($fname, $tt) for help")
        println()

        rethrow(e)
    end
end

"""
    safe_compile_executable(f::Function, tt::Tuple, path::String, name::String;
                            threshold::Int=80, force::Bool=false, export_report::Bool=true)

Safely compile a function to an executable with automatic readiness verification.

Similar to `safe_compile_shlib` but creates a standalone executable.

# Example
```julia
julia> exe_path = safe_compile_executable(main, (), "./", "myapp",
                                          threshold=95)
```
"""
function safe_compile_executable(f::Function, tt::Tuple, path::String, name::String;
                                 threshold::Int=80, force::Bool=false, export_report::Bool=true)
    fname = nameof(f)

    # Run analysis
    println("Analyzing $fname...")
    report = quick_check(f, tt)

    # Export report if requested
    if export_report
        report_path = joinpath(path, "$(name)_analysis.json")
        try
            export_report(report, report_path)
        catch e
            @warn "Could not export analysis report" exception=e
        end
    end

    # Check readiness
    if !force
        if report.score < threshold
            println()
            println("❌ Compilation aborted: score $(report.score)/100 below threshold $threshold/100")
            println()
            println("Issues found:")
            for issue in report.issues
                println("  • $issue")
            end
            println()
            println("💡 Run suggest_optimizations($fname, $tt) for fix suggestions")
            println()
            return nothing
        end

        println("✅ $fname is ready for compilation (score: $(report.score)/100)")
    else
        println("⚠️  Forcing compilation (score: $(report.score)/100)")
    end

    # Attempt compilation
    println()
    println("Compiling $fname to executable...")
    try
        exe_path = compile_executable(f, tt, path, name)
        println("✅ Compilation successful: $exe_path")
        println()

        return exe_path
    catch e
        println("❌ Compilation failed: $e")
        println()
        println("💡 Run suggest_optimizations($fname, $tt) for help")
        println()

        rethrow(e)
    end
end

export safe_compile_shlib, safe_compile_executable
