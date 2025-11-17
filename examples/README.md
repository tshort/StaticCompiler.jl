# StaticCompiler.jl Examples

This directory contains practical examples demonstrating how to use StaticCompiler.jl's compiler analysis tools and static compilation features.

## Running the Examples

Each example can be run with:

```bash
julia --project=.. 01_basic_analysis.jl
```

(The `--project=..` ensures the example uses the StaticCompiler.jl project from the parent directory)

## Example Files

### 01_basic_analysis.jl

**What it teaches**: How to use the five compiler analysis functions

Demonstrates:
- Detecting abstract types with `analyze_monomorphization`
- Finding heap allocations with `analyze_escapes`
- Identifying dynamic dispatch with `analyze_devirtualization`
- Checking constant propagation opportunities with `analyze_constants`
- Detecting memory leaks with `analyze_lifetimes`

Run this first to understand what each analysis function does.

### 02_fixing_issues.jl

**What it teaches**: Common problems and their solutions

Shows before/after comparisons for:
- Converting abstract types to concrete types
- Replacing heap allocations with stack allocations
- Using StaticTools strings instead of Julia Strings
- Eliminating dynamic dispatch
- Fixing memory leaks

Run this to learn how to fix issues identified by the analyses.

### 03_complete_workflow.jl

**What it teaches**: End-to-end static compilation workflow

Demonstrates:
- Running all analyses on a target function
- Interpreting the results
- Compiling to a shared library
- Loading and testing the compiled function
- Manual memory management with MallocArray

Run this to see the complete process from analysis to working compiled code.

### 04_analyze_project.jl

**What it teaches**: Analyzing multiple functions systematically

Demonstrates:
- Batch analysis of multiple functions
- Scoring compilation readiness
- Generating summary reports
- Prioritizing which functions to fix first
- Issue breakdown and recommendations

Run this to learn how to analyze an entire project and prioritize fixes.

### 05_quick_check.jl

**What it teaches**: Using the quick_check convenience function

Demonstrates:
- Single-function analysis with `quick_check()`
- Automatic readiness scoring
- Formatted report printing
- Batch analysis with `batch_check()`
- Integration with compilation workflow

Run this to learn the fastest way to check compilation readiness.

### 06_advanced_workflow.jl

**What it teaches**: Advanced analysis features for production workflows

Demonstrates:
- Pre-compilation verification with `verify_compilation_readiness()`
- Exporting analysis reports to JSON with `export_report()`
- Comparing multiple versions with `compare_reports()`
- Importing saved reports with `import_report_summary()`
- Tracking optimization progress over time

Run this to learn how to integrate analysis into your development workflow.

### 07_macros_and_suggestions.jl

**What it teaches**: Convenience macros and automatic optimization suggestions

Demonstrates:
- `@analyze` macro for inline analysis
- `@check_ready` macro for quick verification
- `@quick_check` macro for silent analysis
- `@suggest_fixes` macro for optimization suggestions
- `suggest_optimizations()` for detailed fix recommendations
- `safe_compile_shlib()` for verified compilation
- Quality thresholds and force compilation

Run this to learn the fastest ways to analyze and get actionable fix suggestions.

## Quick Start

If you're new to static compilation with Julia, follow this path:

1. **Start with**: `01_basic_analysis.jl`
   - Learn what each analysis function tells you
   - Understand which issues block compilation

2. **Then try**: `02_fixing_issues.jl`
   - See how to fix common problems
   - Learn the patterns for static-friendly code

3. **Then run**: `03_complete_workflow.jl`
   - See the complete compilation process
   - Test a real compiled function

4. **For projects**: `04_analyze_project.jl`
   - Analyze multiple functions at once
   - Get prioritized recommendations
   - See which functions are ready to compile

## Common Patterns

### For Fixed-Size Arrays

```julia
using StaticArrays

function process_fixed()
    arr = @SVector zeros(10)  # Stack allocated
    return sum(arr)
end
```

### For Dynamic Arrays

```julia
using StaticTools

function process_dynamic(n::Int)
    arr = MallocArray{Float64}(undef, n)
    # ... use arr ...
    free(arr)  # Don't forget!
    return 0
end
```

### For Concrete Types

```julia
# ❌ Abstract type - won't compile
function bad(x::Number)
    return x * 2
end

# ✅ Concrete type - will compile
function good(x::Int)
    return x * 2
end
```

### For Strings

```julia
using StaticTools

# ❌ Julia String - won't compile
function bad()
    println("Hello")
end

# ✅ Static string - will compile
function good()
    println(c"Hello")
    return 0
end
```

## Troubleshooting

### "Function won't compile"

1. Run `analyze_monomorphization(f, types)` - check for abstract types
2. Run `analyze_escapes(f, types)` - check for heap allocations
3. Run `analyze_lifetimes(f, types)` - check for memory leaks

### "Compiled function crashes"

1. Check for use-after-free bugs
2. Verify all malloc calls have matching free calls
3. Ensure pointer arithmetic is correct

### "Analysis shows no issues but compilation fails"

1. Check dependencies - do called functions also pass analysis?
2. Look for hidden global variables
3. Try using `@device_override` for problematic functions

## Additional Resources

- [Main README](../README.md) - Package documentation
- [Compiler Analysis Guide](../docs/guides/COMPILER_ANALYSIS_GUIDE.md) - Detailed analysis documentation
- [StaticTools.jl](https://github.com/brenhinkeller/StaticTools.jl) - Essential companion package
- [Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl) - For deep IR inspection

## Contributing Examples

Have a good example? Contributions are welcome! Please ensure your example:

1. Has clear comments explaining what it demonstrates
2. Shows both problematic and corrected code when applicable
3. Uses `println` to show analysis results
4. Follows the existing formatting style
