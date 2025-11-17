# Integrated Pre-Compilation Verification

## Overview

StaticCompiler.jl now includes **integrated pre-compilation verification** that automatically analyzes your code quality before compilation. Simply add `verify=true` to your compilation calls!

## Quick Start

```julia
using StaticCompiler

function my_function(n::Int)
    result = 0
    for i in 1:n
        result += i
    end
    return result
end

# Compile with automatic verification
compile_shlib(my_function, (Int,), "./", "myfunc", verify=true)
```

Output:
```
Running pre-compilation analysis...

  [1/1] Analyzing my_function... ✅ (score: 95/100)

✅ All functions passed verification (min score: 80)
```

## Why Use Integrated Verification?

### Problem

Without verification, you might spend time compiling code that:
- Has heap allocations that prevent static compilation
- Uses abstract types that cause runtime overhead
- Has dynamic dispatch that hurts performance
- Contains memory leaks or lifetime issues

You only discover these issues **after** compilation fails or produces slow code.

### Solution

Integrated verification analyzes your code **before** compilation and:
- ✅ Prevents compilation of problematic code
- ✅ Provides detailed feedback about issues
- ✅ Suggests specific fixes
- ✅ Saves development time
- ✅ Enforces quality standards

## API Reference

### compile_shlib with verification

```julia
compile_shlib(f::Function, types::Tuple, path::String, name::String;
    verify::Bool=false,           # Enable pre-compilation verification
    min_score::Int=80,            # Minimum quality score (0-100)
    suggest_fixes::Bool=true,     # Show optimization suggestions on failure
    export_analysis::Bool=false,  # Export analysis report to JSON
    # ... other standard parameters
)
```

### compile_executable with verification

```julia
compile_executable(f::Function, types::Tuple, path::String, name::String;
    verify::Bool=false,           # Enable pre-compilation verification
    min_score::Int=80,            # Minimum quality score (0-100)
    suggest_fixes::Bool=true,     # Show optimization suggestions on failure
    export_analysis::Bool=false,  # Export analysis report to JSON
    # ... other standard parameters
)
```

## Parameters

### `verify::Bool=false`

Enable automatic code quality analysis before compilation.

- `false` (default): No verification, compile immediately (original behavior)
- `true`: Analyze code first, only compile if quality threshold is met

**When to use:**
- Development: Catch issues early
- CI/CD: Enforce quality gates
- Production builds: Ensure high quality

### `min_score::Int=80`

Minimum readiness score required for compilation (0-100 scale).

**Recommended thresholds:**
- `70`: Permissive (development/prototyping)
- `80`: Balanced (default, good for most cases)
- `90`: Strict (production/critical code)
- `95`: Very strict (embedded/performance-critical)

### `suggest_fixes::Bool=true`

Show function names for getting optimization suggestions when verification fails.

Example output when `true`:
```
💡 Get optimization suggestions:
   suggest_optimizations(my_function, (Int,))
```

### `export_analysis::Bool=false`

Export detailed analysis report to JSON file alongside compiled output.

**File naming:** `{function_name}_analysis.json`

**Contents:**
- Readiness score
- Detailed findings from all analyses
- Issues and recommendations
- Timestamp and metadata

**Use cases:**
- Documentation
- CI/CD artifact storage
- Historical tracking
- Debugging compilation issues

## Usage Examples

### Example 1: Basic Verification

```julia
using StaticCompiler

function sum_range(n::Int)
    total = 0
    for i in 1:n
        total += i
    end
    return total
end

# Compile with default verification (min_score=80)
lib_path = compile_shlib(sum_range, (Int,), "./", "sum", verify=true)
```

### Example 2: Custom Quality Threshold

```julia
# Strict quality requirements for production
lib_path = compile_shlib(my_func, (Int,), "./", "myfunc",
                         verify=true,
                         min_score=95)  # Require excellent score
```

### Example 3: Development Mode (Permissive)

```julia
# Allow lower scores during development
lib_path = compile_shlib(prototype_func, (Int,), "./", "proto",
                         verify=true,
                         min_score=70)  # Lower threshold
```

### Example 4: Export Analysis Reports

```julia
# Export reports for documentation/tracking
lib_path = compile_shlib(my_func, (Int,), "./", "myfunc",
                         verify=true,
                         export_analysis=true)  # Creates myfunc_analysis.json
```

### Example 5: Batch Compilation

```julia
# Verify multiple functions at once
functions = [
    (func1, (Int,)),
    (func2, (Float64,)),
    (func3, (Int, Int))
]

lib_path = compile_shlib(functions, "./",
                         filename="mylib",
                         verify=true,
                         min_score=85)
```

Output:
```
Running pre-compilation analysis...

  [1/3] Analyzing func1... ✅ (score: 92/100)
  [2/3] Analyzing func2... ✅ (score: 88/100)
  [3/3] Analyzing func3... ❌ (score: 75/85)

❌ Pre-compilation verification failed!

1 function(s) below minimum score (85):

  • func3(Int64, Int64): score 75/85
    - Found 2 heap allocations
    - Dynamic dispatch at 1 location

💡 Get optimization suggestions:
   suggest_optimizations(func3, (Int, Int))
```

### Example 6: CI/CD Integration

```julia
#!/usr/bin/env julia

using StaticCompiler

# Load your functions
include("src/myproject.jl")

# Compile with quality gate
try
    lib_path = compile_shlib(critical_function, (Int,), "./build", "output",
                             verify=true,
                             min_score=85,
                             export_analysis=true)
    println("✅ Build succeeded: $lib_path")
    exit(0)
catch e
    println("❌ Build failed: $e")
    exit(1)
end
```

## Comparison with safe_compile_* Functions

StaticCompiler.jl provides three approaches to compilation:

### 1. Standard Compilation (No Verification)

```julia
compile_shlib(func, types, path, name)
```

**Pros:**
- Fast (no analysis overhead)
- Simple API

**Cons:**
- No quality checks
- May compile problematic code
- Issues discovered late

**Use when:** You're confident the code is optimized

### 2. Explicit Safe Compilation

```julia
safe_compile_shlib(func, types, path, name, threshold=80)
```

**Pros:**
- Clear intent (separate function name)
- Detailed user feedback
- Comprehensive error messages

**Cons:**
- Different API than standard compilation
- Must explicitly choose between safe/unsafe

**Use when:** You want explicit "safe" vs "unsafe" distinction

### 3. Integrated Verification (NEW)

```julia
compile_shlib(func, types, path, name, verify=true)
```

**Pros:**
- Same API as standard compilation
- Just add one parameter
- Works with existing code
- Backward compatible (verify=false by default)
- Works with batch compilation
- Customizable behavior

**Cons:**
- Slight performance overhead (analysis time)

**Use when:** You want convenience + safety (recommended!)

## Workflow Recommendations

### Development Workflow

```julia
# Phase 1: Initial Development (permissive)
compile_shlib(func, types, "./build", "func",
              verify=true,
              min_score=70)

# Phase 2: Testing (balanced)
compile_shlib(func, types, "./build", "func",
              verify=true,
              min_score=80)

# Phase 3: Production (strict)
compile_shlib(func, types, "./build", "func",
              verify=true,
              min_score=90,
              export_analysis=true)
```

### CI/CD Workflow

```yaml
# .github/workflows/build.yml
- name: Build with quality gate
  run: |
    julia --project=. -e '
      using StaticCompiler
      include("src/main.jl")
      compile_shlib(my_function, (Int,), "./artifacts", "mylib",
                    verify=true,
                    min_score=85,
                    export_analysis=true)
    '

- name: Upload analysis report
  uses: actions/upload-artifact@v3
  with:
    name: analysis-report
    path: ./artifacts/*_analysis.json
```

### Team Workflow

Set project-wide standards:

```julia
# config/compilation_settings.jl
const COMPILATION_CONFIG = (
    verify = true,
    min_score = 85,
    export_analysis = true
)

# src/build.jl
using StaticCompiler
include("../config/compilation_settings.jl")

function build_library()
    compile_shlib(my_func, (Int,), "./build", "mylib";
                  COMPILATION_CONFIG...)
end
```

## Understanding Scores

The readiness score (0-100) is calculated based on multiple analyses:

### Score Breakdown

- **95-100**: Excellent
  - No allocations
  - No abstract types
  - No dynamic dispatch
  - Optimal constant propagation
  - No lifetime issues

- **85-94**: Good
  - Minimal issues
  - Safe for production
  - Minor optimizations possible

- **75-84**: Acceptable
  - Some issues present
  - May compile successfully
  - Performance may be suboptimal

- **60-74**: Problematic
  - Significant issues
  - Compilation may fail
  - Needs optimization

- **Below 60**: Poor
  - Major issues
  - Likely compilation failure
  - Requires significant work

### What Affects Score

Each analysis contributes to the overall score:

1. **Escape Analysis** (25%)
   - Heap allocations
   - Non-static array usage
   - String allocations

2. **Monomorphization** (20%)
   - Abstract type parameters
   - Type instabilities
   - Union types

3. **Devirtualization** (20%)
   - Dynamic dispatch sites
   - Abstract function calls
   - Runtime method lookup

4. **Constant Propagation** (20%)
   - Compile-time constants
   - Loop bounds
   - Optimization opportunities

5. **Lifetime Analysis** (15%)
   - Memory leaks
   - Dangling pointers
   - Allocation/free balance

## Troubleshooting

### Verification Takes Too Long

```julia
# Option 1: Use cached analysis
using StaticCompiler

# First call analyzes
compile_shlib(func, types, "./", "name", verify=true)

# Subsequent calls use cache (if function unchanged)
compile_shlib(func, types, "./", "name", verify=true)  # Fast!
```

```julia
# Option 2: Disable verification for large batches
if length(functions) > 50
    # Skip verification for very large batches
    compile_shlib(functions, "./", verify=false)
else
    compile_shlib(functions, "./", verify=true)
end
```

### Low Score But Compiles Successfully

This can happen because:
- Analysis is conservative (may flag false positives)
- Some issues don't prevent compilation, just affect performance

**Solutions:**
```julia
# Option 1: Lower threshold if false positives
compile_shlib(func, types, "./", "name", verify=true, min_score=70)

# Option 2: Review suggestions to see if they apply
suggest_optimizations(func, types)

# Option 3: Use safe_compile_* with force=true
safe_compile_shlib(func, types, "./", "name", force=true)
```

### Verification Fails But Should Pass

```julia
# Get detailed report
report = quick_check(func, types)
print_readiness_report(report)

# Check specific analyses
escape_report = analyze_escapes(func, types)
mono_report = analyze_monomorphization(func, types)
# ... etc

# Export full report for inspection
export_report(report, "debug_report.json")
```

## Performance Considerations

### Analysis Overhead

Typical analysis times:
- Small function: 10-100ms
- Medium function: 100ms-1s
- Large function: 1-5s
- Batch (10 functions): 1-10s

**Mitigation:**
- Use caching for repeated analysis
- Only verify during development/CI
- Disable for quick iteration

### Caching

Analysis results are automatically cached:

```julia
# First call: ~500ms (analysis + compilation)
compile_shlib(func, types, "./", "name", verify=true)

# Second call: ~50ms (cached analysis + compilation)
compile_shlib(func, types, "./", "name", verify=true)

# Cache is invalidated if function changes
```

Cache management:
```julia
using StaticCompiler

# Clear all cached results
clear_analysis_cache!()

# View cache statistics
stats = cache_stats()
println("Cache hits: $(stats.hits)")
println("Cache misses: $(stats.misses)")
```

## Best Practices

### 1. Enable Verification in Development

```julia
# Always verify during development
compile_shlib(func, types, "./", "name", verify=true)
```

### 2. Use Appropriate Thresholds

```julia
# Development: Be permissive
verify=true, min_score=70

# Production: Be strict
verify=true, min_score=90
```

### 3. Export Reports for CI/CD

```julia
# Keep historical record
compile_shlib(func, types, "./", "name",
              verify=true,
              export_analysis=true)
```

### 4. Review Suggestions When Failing

```julia
try
    compile_shlib(func, types, "./", "name", verify=true)
catch e
    # Get actionable suggestions
    suggest_optimizations(func, types)
end
```

### 5. Use Batch Verification Wisely

```julia
# Verify all functions at once for consistent quality
compile_shlib(multiple_functions, "./",
              verify=true,
              min_score=85)
```

## Migration Guide

### From Standard Compilation

Before:
```julia
compile_shlib(func, types, "./", "name")
```

After:
```julia
compile_shlib(func, types, "./", "name", verify=true)
```

### From safe_compile_* Functions

Before:
```julia
safe_compile_shlib(func, types, "./", "name", threshold=85)
```

After:
```julia
compile_shlib(func, types, "./", "name", verify=true, min_score=85)
```

Both approaches work! Use whichever you prefer:
- `safe_compile_*`: Explicit "safe" intent, verbose output
- `verify=true`: Integrated, concise, flexible

## See Also

- [Analysis Infrastructure Guide](./ANALYSIS_INFRASTRUCTURE.md)
- [Optimization Suggestions](./examples/03_optimization_suggestions.jl)
- [CI/CD Integration](./examples/08_ci_and_project_tools.jl)
- [Safe Compilation](./examples/06_safe_compilation.jl)

## Summary

Integrated verification makes it trivial to ensure code quality:

```julia
# Just add verify=true!
compile_shlib(func, types, path, name, verify=true)
```

**Benefits:**
- Prevents problematic compilations
- Provides actionable feedback
- Saves development time
- Enforces quality standards
- Works seamlessly with existing code

**Recommended for:**
- All production builds
- CI/CD pipelines
- Team development
- Learning StaticCompiler.jl
