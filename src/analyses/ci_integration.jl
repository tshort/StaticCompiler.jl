# CI/CD Integration Helpers
# Tools for integrating compiler analysis into continuous integration pipelines

"""
    generate_ci_report(results::Dict{Symbol, CompilationReadinessReport}, output_path::String)

Generate a CI-friendly report from batch analysis results.

Creates both a human-readable markdown report and a machine-readable JSON summary.

# Arguments
- `results`: Dictionary of analysis reports from batch_check
- `output_path`: Base path for output files (will create .md and .json files)

# Example
```julia
julia> results = batch_check([(func1, (Int,)), (func2, (Float64,))])
julia> generate_ci_report(results, "analysis_report")
# Creates: analysis_report.md, analysis_report.json
```
"""
function generate_ci_report(results::Dict{Symbol, CompilationReadinessReport}, output_path::String)
    # Calculate summary statistics
    total = length(results)
    ready = count(r -> r.ready_for_compilation, values(results))
    avg_score = total > 0 ? round(Int, sum(r.score for r in values(results)) / total) : 0

    # Collect all issues
    all_issues = String[]
    for report in values(results)
        append!(all_issues, report.issues)
    end
    issue_counts = Dict{String, Int}()
    for issue in all_issues
        issue_counts[issue] = get(issue_counts, issue, 0) + 1
    end

    # Sort by score
    sorted = sort(collect(results), by=x->x[2].score, rev=true)

    # Generate Markdown report
    md_path = output_path * ".md"
    open(md_path, "w") do io
        println(io, "# Compiler Analysis Report")
        println(io)
        println(io, "Generated: $(now())")
        println(io)

        # Summary
        println(io, "## Summary")
        println(io)
        println(io, "- **Total Functions**: $total")
        println(io, "- **Ready for Compilation**: $ready ($ready/$total, $(round(Int, ready/total*100))%)")
        println(io, "- **Average Score**: $avg_score/100")
        println(io)

        # Status badges
        status = ready == total ? "✅ All Ready" : ready >= total/2 ? "⚠️ Partially Ready" : "❌ Not Ready"
        println(io, "**Status**: $status")
        println(io)

        # Function details
        println(io, "## Function Analysis")
        println(io)
        println(io, "| Function | Score | Status | Issues |")
        println(io, "|----------|-------|--------|--------|")

        for (name, report) in sorted
            status_icon = report.ready_for_compilation ? "✅" : "❌"
            issues_str = isempty(report.issues) ? "-" : join(report.issues, ", ")
            println(io, "| `$name` | $(report.score)/100 | $status_icon | $issues_str |")
        end
        println(io)

        # Issue summary
        if !isempty(issue_counts)
            println(io, "## Common Issues")
            println(io)
            for (issue, count) in sort(collect(issue_counts), by=x->x[2], rev=true)
                println(io, "- **$issue**: $count function(s)")
            end
            println(io)
        end

        # Recommendations
        println(io, "## Recommendations")
        println(io)
        if ready == total
            println(io, "✅ All functions are ready for compilation!")
        else
            println(io, "Focus on fixing:")
            println(io)
            for (name, report) in sorted
                if !report.ready_for_compilation && report.score < 80
                    println(io, "### `$name` (Score: $(report.score)/100)")
                    for issue in report.issues
                        println(io, "- $issue")
                    end
                    println(io)
                end
            end
        end
    end

    # Generate JSON summary
    json_path = output_path * ".json"
    summary_data = Dict(
        "timestamp" => string(now()),
        "total_functions" => total,
        "ready_functions" => ready,
        "average_score" => avg_score,
        "pass_rate" => round(ready/total*100, digits=2),
        "functions" => Dict(
            string(name) => Dict(
                "score" => report.score,
                "ready" => report.ready_for_compilation,
                "issues" => report.issues
            )
            for (name, report) in results
        ),
        "issue_summary" => issue_counts
    )

    open(json_path, "w") do io
        JSON.print(io, summary_data, 2)
    end

    println("✅ CI report generated:")
    println("   Markdown: $md_path")
    println("   JSON:     $json_path")

    return (md_path, json_path)
end

"""
    check_quality_gate(results::Dict{Symbol, CompilationReadinessReport};
                       min_ready_percent::Int=80,
                       min_avg_score::Int=70) -> Bool

Check if analysis results meet quality gate criteria for CI/CD.

Returns `true` if criteria are met, `false` otherwise.
Exits with code 1 if criteria not met (useful for CI).

# Arguments
- `results`: Dictionary of analysis reports from batch_check
- `min_ready_percent`: Minimum percentage of functions that must be ready (default 80%)
- `min_avg_score`: Minimum average score across all functions (default 70/100)

# Example
```julia
julia> results = batch_check([(func1, (Int,)), (func2, (Float64,))])
julia> check_quality_gate(results, min_ready_percent=90, min_avg_score=80)
```
"""
function check_quality_gate(results::Dict{Symbol, CompilationReadinessReport};
                           min_ready_percent::Int=80,
                           min_avg_score::Int=70,
                           exit_on_fail::Bool=true)
    total = length(results)
    ready = count(r -> r.ready_for_compilation, values(results))
    ready_percent = round(Int, ready / total * 100)
    avg_score = round(Int, sum(r.score for r in values(results)) / total)

    println()
    println("="^70)
    println("QUALITY GATE CHECK")
    println("="^70)
    println()
    println("Criteria:")
    println("  Ready functions: $ready_percent% (minimum: $min_ready_percent%)")
    println("  Average score:   $avg_score/100 (minimum: $min_avg_score/100)")
    println()

    ready_pass = ready_percent >= min_ready_percent
    score_pass = avg_score >= min_avg_score

    if ready_pass && score_pass
        println("✅ QUALITY GATE PASSED")
        println()
        println("="^70)
        return true
    else
        println("❌ QUALITY GATE FAILED")
        println()

        if !ready_pass
            println("  ❌ Ready percentage too low: $ready_percent% < $min_ready_percent%")
            println("     Functions not ready: $(total - ready)/$total")
        else
            println("  ✅ Ready percentage acceptable: $ready_percent%")
        end

        if !score_pass
            println("  ❌ Average score too low: $avg_score < $min_avg_score")
            failing = [name for (name, report) in results if report.score < min_avg_score]
            println("     Functions below threshold: $(length(failing))")
        else
            println("  ✅ Average score acceptable: $avg_score")
        end

        println()
        println("="^70)

        if exit_on_fail
            println()
            println("Exiting with code 1 (quality gate failed)")
            exit(1)
        end

        return false
    end
end

"""
    generate_github_actions_summary(results::Dict{Symbol, CompilationReadinessReport})

Generate a summary for GitHub Actions workflow.

Writes to \$GITHUB_STEP_SUMMARY if available, otherwise prints to stdout.

# Example
```julia
julia> results = batch_check([(func1, (Int,)), (func2, (Float64,))])
julia> generate_github_actions_summary(results)
```
"""
function generate_github_actions_summary(results::Dict{Symbol, CompilationReadinessReport})
    total = length(results)
    ready = count(r -> r.ready_for_compilation, values(results))
    avg_score = round(Int, sum(r.score for r in values(results)) / total)

    # Generate markdown summary
    summary = """
    # 🔍 Compiler Analysis Summary

    - **Total Functions**: $total
    - **Ready for Compilation**: $ready/$total ($(round(Int, ready/total*100))%)
    - **Average Score**: $avg_score/100

    ## Function Status

    | Function | Score | Status |
    |----------|-------|--------|
    """

    sorted = sort(collect(results), by=x->x[2].score, rev=true)
    for (name, report) in sorted
        icon = report.ready_for_compilation ? "✅" : "❌"
        summary *= "| `$name` | $(report.score)/100 | $icon |\n"
    end

    # Write to GitHub Actions summary if available
    github_summary_file = get(ENV, "GITHUB_STEP_SUMMARY", nothing)

    if github_summary_file !== nothing
        open(github_summary_file, "a") do io
            println(io, summary)
        end
        println("✅ GitHub Actions summary written to \$GITHUB_STEP_SUMMARY")
    else
        println(summary)
        println()
        println("ℹ️  Set \$GITHUB_STEP_SUMMARY to write to GitHub Actions")
    end
end

"""
    annotate_github_actions(results::Dict{Symbol, CompilationReadinessReport};
                            error_threshold::Int=50,
                            warning_threshold::Int=80)

Create GitHub Actions annotations for functions with issues.

Generates error annotations for functions below error_threshold,
and warning annotations for functions below warning_threshold.

# Example
```julia
julia> results = batch_check([(func1, (Int,)), (func2, (Float64,))])
julia> annotate_github_actions(results)
```
"""
function annotate_github_actions(results::Dict{Symbol, CompilationReadinessReport};
                                error_threshold::Int=50,
                                warning_threshold::Int=80)
    annotations = 0

    for (name, report) in results
        if report.score < error_threshold
            # Error annotation
            println("::error::Function $name has low compilation readiness (score: $(report.score)/100). Issues: $(join(report.issues, ", "))")
            annotations += 1
        elseif report.score < warning_threshold
            # Warning annotation
            println("::warning::Function $name may have compilation issues (score: $(report.score)/100). Issues: $(join(report.issues, ", "))")
            annotations += 1
        end
    end

    if annotations == 0
        println("✅ No issues to annotate (all functions have good scores)")
    else
        println("ℹ️  Created $annotations annotation(s) for GitHub Actions")
    end

    return annotations
end

export generate_ci_report, check_quality_gate
export generate_github_actions_summary, annotate_github_actions
