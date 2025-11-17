# GitHub Actions Workflow Examples

This directory contains example GitHub Actions workflows demonstrating how to integrate StaticCompiler.jl's compiler analysis tools into your CI/CD pipeline.

## Available Examples

### compiler-analysis-example.yml

**Purpose**: Analyze specific functions in your codebase

**Features**:
- Batch analysis of specified functions
- Quality gate enforcement
- Automatic PR comments with results
- Artifact upload for reports
- GitHub Actions annotations for issues

**Usage**:
1. Copy to your repository's `.github/workflows/` directory
2. Customize the `functions_to_analyze` list
3. Adjust quality thresholds as needed

**Triggers**:
- Push to main/develop branches
- Pull requests to main branch

### module-analysis-example.yml

**Purpose**: Analyze an entire module for comprehensive quality tracking

**Features**:
- Module-wide function discovery and analysis
- Quality tracking over time
- Weekly scheduled runs
- Historical quality reporting
- Detailed GitHub Actions summaries

**Usage**:
1. Copy to your repository's `.github/workflows/` directory
2. Replace `YourModule` with your module name
3. Adjust quality thresholds (default: 75% ready, 70/100 avg score)

**Triggers**:
- Push to main branch
- Pull requests to main branch
- Weekly schedule (Sunday midnight)

## Configuration Options

### Quality Gate Thresholds

```julia
check_quality_gate(results,
                   min_ready_percent=80,  # Minimum % of functions ready
                   min_avg_score=70,      # Minimum average score
                   exit_on_fail=true)     # Exit with code 1 on failure
```

### Annotation Thresholds

```julia
annotate_github_actions(results,
                        error_threshold=50,    # Scores below 50 = error
                        warning_threshold=80)  # Scores below 80 = warning
```

### Caching

Both examples use `batch_check_cached()` for performance. The cache is automatically managed but you can customize TTL:

```julia
results = batch_check_cached(functions, ttl=600.0)  # 10 minutes
```

## Integration Best Practices

### 1. Start with Function-Level Analysis

Begin with `compiler-analysis-example.yml` to analyze critical functions:

```julia
# Focus on public API functions first
functions_to_analyze = [
    (compile_shlib, (Function, Tuple, String, String)),
    (compile_executable, (Function, Tuple, String, String)),
    # Add your critical functions
]
```

### 2. Graduate to Module-Level

Once individual functions are optimized, use `module-analysis-example.yml` for comprehensive tracking.

### 3. Set Realistic Thresholds

Start with achievable thresholds and gradually increase:

```julia
# Initial thresholds (easier)
min_ready_percent=60
min_avg_score=60

# Target thresholds (stricter)
min_ready_percent=80
min_avg_score=75
```

### 4. Use PR Comments for Visibility

The example workflows automatically comment on PRs with analysis results, making it easy for reviewers to see compilation readiness.

### 5. Track Quality Over Time

The module analysis example saves historical data:

```bash
quality-history/
  2024-01-01.json
  2024-01-08.json
  2024-01-15.json
```

This enables trend analysis and regression detection.

## Example PR Comment

When you push a PR, you'll see comments like:

```markdown
# 🔍 Compiler Analysis Summary

- **Total Functions**: 15
- **Ready for Compilation**: 12/15 (80%)
- **Average Score**: 85/100

## Function Status

| Function | Score | Status |
|----------|-------|--------|
| `compile_shlib` | 95/100 | ✅ |
| `compile_executable` | 92/100 | ✅ |
| `problematic_func` | 45/100 | ❌ |

See full report in artifacts.
```

## Customization Examples

### Only Run on Specific Paths

```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'Project.toml'
```

### Different Thresholds per Branch

```yaml
- name: Check quality (main branch)
  if: github.ref == 'refs/heads/main'
  run: |
    check_quality_gate(results, min_ready_percent=90, min_avg_score=80)

- name: Check quality (develop branch)
  if: github.ref == 'refs/heads/develop'
  run: |
    check_quality_gate(results, min_ready_percent=70, min_avg_score=65)
```

### Slack Notifications

```yaml
- name: Notify Slack on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Compiler analysis failed: ${{ github.event.pull_request.html_url }}"
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

## Troubleshooting

### Issue: "Module not found"

**Solution**: Ensure your module is properly loaded:

```julia
using Pkg
Pkg.activate(".")
using YourPackage
analyze_module(YourPackage)
```

### Issue: "Quality gate always failing"

**Solution**: Run analysis locally first to set appropriate thresholds:

```julia
using StaticCompiler
results = batch_check([...])
println("Current pass rate: ", count(r -> r.ready_for_compilation, values(results)) / length(results) * 100)
```

### Issue: "Analysis too slow"

**Solution**: Use caching and reduce scope:

```julia
# Use caching
results = batch_check_cached(functions)

# Or analyze subset
functions = functions[1:10]  # Analyze top 10 functions
```

## Advanced Features

### Compare PR vs Main

```yaml
- name: Analyze PR branch
  run: |
    results_pr = batch_check(functions)

- name: Checkout main
  uses: actions/checkout@v3
  with:
    ref: main

- name: Analyze main branch
  run: |
    results_main = batch_check(functions)

- name: Compare
  run: |
    # Compare and report differences
    compare_results(results_main, results_pr)
```

### Matrix Testing

```yaml
strategy:
  matrix:
    julia-version: ['1.9', '1.10']

steps:
  - name: Analyze with Julia ${{ matrix.julia-version }}
    run: |
      julia --project=. analysis.jl
```

## Resources

- [StaticCompiler.jl Documentation](https://github.com/tshort/StaticCompiler.jl)
- [Compiler Analysis Guide](../docs/guides/COMPILER_ANALYSIS_GUIDE.md)
- [Examples Directory](../examples/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## Support

For issues or questions:
1. Check the [examples](../examples/) directory
2. Review the [compiler analysis guide](../docs/guides/COMPILER_ANALYSIS_GUIDE.md)
3. Open an issue on GitHub
