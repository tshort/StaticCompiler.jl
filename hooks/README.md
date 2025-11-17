# Git Hooks for Compiler Analysis

This directory contains git hooks that integrate compiler analysis into your development workflow.

## Available Hooks

### pre-commit

Runs compiler analysis before each commit to catch issues early.

**Features**:
- Analyzes configured functions before commit
- Caching for fast execution (typically < 1 second)
- Configurable quality thresholds
- Strict mode to block commits
- Clear error messages with fix suggestions

**Installation**:

```bash
# Install the hook
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**Configuration**:

Edit `.git/hooks/pre-commit` to customize:

```julia
# Quality thresholds
const MIN_SCORE = 70           # Minimum average score (0-100)
const MIN_READY_PERCENT = 60   # Minimum % ready for compilation
const STRICT_MODE = false      # true = block commits, false = warn only

# Functions to check
functions_to_check = [
    (my_critical_function, (Int, Int)),
    (another_function, (Float64,)),
]
```

**Usage**:

Once installed, the hook runs automatically on every commit:

```bash
$ git commit -m "Add new feature"
🔍 Running compiler analysis pre-commit check...

Analyzing 3 function(s)...

======================================================================
PRE-COMMIT ANALYSIS RESULTS
======================================================================

Total functions:  3
Ready:            3/3 (100%)
Average score:    95/100

======================================================================

✅ Pre-commit check PASSED
```

**Bypass Hook** (not recommended):

If you need to commit despite warnings:

```bash
git commit --no-verify -m "WIP: experimental code"
```

## Configuration Examples

### Strict Mode for Production

Require high quality before commits:

```julia
const MIN_SCORE = 85
const MIN_READY_PERCENT = 80
const STRICT_MODE = true  # Block commits if quality too low
```

### Lenient Mode for Development

Allow commits with warnings:

```julia
const MIN_SCORE = 60
const MIN_READY_PERCENT = 50
const STRICT_MODE = false  # Just warn, don't block
```

### Critical Functions Only

Only check your most important functions:

```julia
functions_to_check = [
    (compile_shlib, (Function, Tuple, String, String)),
    (compile_executable, (Function, Tuple, String, String)),
]
```

## Performance

The pre-commit hook uses `batch_check_cached()` which caches analysis results:

- **First run**: ~0.5-1.0 seconds per function
- **Subsequent runs**: ~0.01 seconds (cached)
- **Cache TTL**: 5 minutes

This means the hook is very fast for typical commit workflows.

## Troubleshooting

### Hook not running

```bash
# Check if hook is installed
ls -la .git/hooks/pre-commit

# Check if executable
chmod +x .git/hooks/pre-commit
```

### Hook too slow

```bash
# Reduce number of functions to check
# Or increase cache TTL in the hook
```

### False positives

```bash
# Adjust thresholds to match your codebase
const MIN_SCORE = 70  # Lower threshold
```

## Integration with Team Workflow

### For New Projects

Start with lenient thresholds and gradually increase:

```julia
# Week 1
const MIN_SCORE = 50
const STRICT_MODE = false

# Week 2
const MIN_SCORE = 60
const STRICT_MODE = false

# Week 3+
const MIN_SCORE = 75
const STRICT_MODE = true
```

### For Existing Projects

Analyze current state first:

```julia
# Check current quality
using StaticCompiler
results = batch_check(all_your_functions)
current_avg = sum(r.score for r in values(results)) / length(results)
println("Current average: $current_avg")

# Set threshold slightly below current
const MIN_SCORE = current_avg - 5
```

## Advanced Usage

### Per-Branch Configuration

Different thresholds for different branches:

```julia
branch = strip(read(`git branch --show-current`, String))

if branch == "main"
    const MIN_SCORE = 90
    const STRICT_MODE = true
elseif branch == "develop"
    const MIN_SCORE = 70
    const STRICT_MODE = false
else  # feature branches
    const MIN_SCORE = 60
    const STRICT_MODE = false
end
```

### Conditional Checks

Only check functions that changed:

```julia
# Get changed files
changed_files = split(read(`git diff --cached --name-only`, String), '\n')

# Only analyze if .jl files changed
if any(endswith(f, ".jl") for f in changed_files)
    # Run analysis
    results = batch_check_cached(functions_to_check)
else
    # Skip analysis
    println("No Julia files changed, skipping analysis")
    exit(0)
end
```

## Best Practices

1. **Start Lenient**: Begin with low thresholds and `STRICT_MODE = false`
2. **Gradual Improvement**: Increase thresholds over time as code improves
3. **Critical Functions**: Focus on functions that will be compiled
4. **Cache Awareness**: Hook is fast due to caching, but cache expires in 5 minutes
5. **Team Agreement**: Agree on thresholds as a team
6. **Documentation**: Document your thresholds in team wiki

## See Also

- [Compiler Analysis Guide](../docs/guides/COMPILER_ANALYSIS_GUIDE.md)
- [CI/CD Integration](.github/workflows/README.md)
- [Examples](../examples/)
