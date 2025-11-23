# Visualization Tools for Benchmark Results
# Simple text-based visualization for benchmark data

using Dates

"""
    plot_size_reduction(results::Dict)

Generate a text-based chart showing binary size reduction across optimizations.
"""
function plot_size_reduction(results::Dict)
    println("\n" * "="^70)
    println("BINARY SIZE REDUCTION BY OPTIMIZATION")
    println("="^70)
    println()

    # Extract size reduction data
    data = []
    for (opt, metrics) in results
        if haskey(metrics, "size_reduction_pct")
            push!(data, (opt, metrics["size_reduction_pct"]))
        end
    end

    # Sort by reduction percentage
    sort!(data, by=x->x[2], rev=true)

    # Find max value for scaling
    max_reduction = maximum(x[2] for x in data)
    scale = 50 / max_reduction  # Scale to 50 characters wide

    # Plot
    for (opt, reduction) in data
        bar_length = Int(round(reduction * scale))
        bar = "█" ^ bar_length
        pct_str = lpad("$(round(reduction, digits=1))%", 6)
        opt_str = rpad(opt, 25)
        println("  $opt_str │$bar $pct_str")
    end

    println()
    println("="^70)
    println()
end

"""
    plot_performance_improvement(results::Dict)

Generate a text-based chart showing performance improvements.
"""
function plot_performance_improvement(results::Dict)
    println("\n" * "="^70)
    println("PERFORMANCE IMPROVEMENT BY OPTIMIZATION")
    println("="^70)
    println()

    # Extract performance data
    data = []
    for (opt, metrics) in results
        if haskey(metrics, "speedup")
            push!(data, (opt, metrics["speedup"]))
        elseif haskey(metrics, "time_reduction_pct")
            speedup = 100.0 / (100.0 - metrics["time_reduction_pct"])
            push!(data, (opt, speedup))
        end
    end

    # Sort by speedup
    sort!(data, by=x->x[2], rev=true)

    # Plot
    for (opt, speedup) in data
        bar_length = Int(round((speedup - 1.0) * 10))  # Scale relative to 1x
        bar = "█" ^ min(bar_length, 50)
        speedup_str = lpad("$(round(speedup, digits=2))x", 8)
        opt_str = rpad(opt, 25)
        println("  $opt_str │$bar $speedup_str")
    end

    println()
    println("="^70)
    println()
end

"""
    plot_optimization_trends(history::Vector{Dict})

Plot trends over time from historical benchmark data.
"""
function plot_optimization_trends(history::Vector{Dict})
    println("\n" * "="^70)
    println("OPTIMIZATION PERFORMANCE TRENDS")
    println("="^70)
    println()

    if isempty(history)
        println("  No historical data available")
        println()
        return
    end

    # Extract metrics over time
    timestamps = [h["timestamp"] for h in history]
    println("  Time range: $(first(timestamps)) → $(last(timestamps))")
    println("  Data points: $(length(history))")
    println()

    # Simple trend indicator
    if length(history) >= 2
        first_perf = get(history[1], "overall_performance", 0.0)
        last_perf = get(history[end], "overall_performance", 0.0)

        if last_perf > first_perf
            trend = "↗ IMPROVING"
            pct = ((last_perf - first_perf) / first_perf) * 100
        elseif last_perf < first_perf
            trend = "↘ DEGRADING"
            pct = ((first_perf - last_perf) / first_perf) * 100
        else
            trend = "→ STABLE"
            pct = 0.0
        end

        println("  Overall trend: $trend ($(round(abs(pct), digits=1))%)")
    end

    println()
    println("="^70)
    println()
end

"""
    plot_regression_analysis(baseline::Dict, current::Dict)

Visualize regression analysis comparing current results with baseline.
"""
function plot_regression_analysis(baseline::Dict, current::Dict)
    println("\n" * "="^70)
    println("REGRESSION ANALYSIS")
    println("="^70)
    println()

    regressions = []
    improvements = []
    stable = []

    # Compare metrics
    for (key, current_value) in current
        if haskey(baseline, key)
            baseline_value = baseline[key]

            if baseline_value > 0
                pct_change = ((current_value - baseline_value) / baseline_value) * 100.0

                if pct_change > 5.0
                    push!(regressions, (key, pct_change))
                elseif pct_change < -5.0
                    push!(improvements, (key, abs(pct_change)))
                else
                    push!(stable, key)
                end
            end
        end
    end

    # Display results
    if !isempty(regressions)
        println("  REGRESSIONS ($(length(regressions))):")
        for (metric, pct) in regressions
            println("     • $metric: $(round(pct, digits=1))% worse")
        end
        println()
    end

    if !isempty(improvements)
        println("  IMPROVEMENTS ($(length(improvements))):")
        for (metric, pct) in improvements
            println("     • $metric: $(round(pct, digits=1))% better")
        end
        println()
    end

    if !isempty(stable)
        println("  OK STABLE ($(length(stable)) metrics)")
        println()
    end

    # Summary
    total = length(regressions) + length(improvements) + length(stable)
    status = if isempty(regressions)
        "PASS - No regressions detected"
    elseif length(regressions) < total / 10  # Less than 10% regressed
        " WARNING - Minor regressions"
    else
        "FAIL - Significant regressions"
    end

    println("  Status: $status")
    println()
    println("="^70)
    println()
end

"""
    generate_benchmark_report(results::Dict; output_file=nothing)

Generate a comprehensive benchmark report.
"""
function generate_benchmark_report(results::Dict; output_file=nothing)
    report = IOBuffer()

    # Header
    println(report, "="^70)
    println(report, "BENCHMARK REPORT")
    println(report, "="^70)
    println(report)
    println(report, "Generated: $(Dates.now())")
    println(report, "Julia Version: $(VERSION)")
    println(report)

    # Summary statistics
    println(report, "SUMMARY")
    println(report, "-"^70)

    total_tests = length(results)
    println(report, "  Total optimizations tested: $total_tests")

    if haskey(results, "overall_performance")
        println(report, "  Overall performance: $(results["overall_performance"])")
    end

    println(report)

    # Detailed results
    println(report, "DETAILED RESULTS")
    println(report, "-"^70)

    for (opt, metrics) in sort(collect(results), by=x->x[1])
        println(report, "  $opt:")
        for (metric, value) in metrics
            value_str = if value isa Number
                round(value, digits=2)
            else
                value
            end
            println(report, "    • $metric: $value_str")
        end
        println(report)
    end

    println(report, "="^70)

    # Output
    report_text = String(take!(report))

    if !isnothing(output_file)
        open(output_file, "w") do f
            write(f, report_text)
        end
        println("Report saved to: $output_file")
    else
        println(report_text)
    end

    return report_text
end

# Export functions
export plot_size_reduction, plot_performance_improvement, plot_optimization_trends
export plot_regression_analysis, generate_benchmark_report
