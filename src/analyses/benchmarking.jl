# Benchmarking and Performance Comparison Tools
# Compare analysis results and compilation performance over time

"""
    BenchmarkResult

Stores benchmarking data for a function analysis or compilation.
"""
struct BenchmarkResult
    function_name::Symbol
    timestamp::String
    analysis_time::Float64  # seconds
    compilation_time::Float64  # seconds (if compiled)
    compilation_success::Bool
    score::Int
    ready::Bool
    issues::Vector{String}
    metadata::Dict{String, Any}
end

"""
    benchmark_analysis(f::Function, types::Tuple; samples::Int=5) -> Dict

Benchmark the analysis performance for a function.

Runs analysis multiple times and reports statistics.

# Arguments
- `f::Function`: Function to benchmark
- `types::Tuple`: Argument type tuple
- `samples::Int=5`: Number of samples to take

# Returns
Dictionary with timing statistics (min, max, mean, median, std)

# Example
```julia
julia> stats = benchmark_analysis(my_func, (Int,), samples=10)
julia> println("Mean time: \$(stats[:mean])s")
```
"""
function benchmark_analysis(f::Function, types::Tuple; samples::Int=5)
    fname = nameof(f)

    println("Benchmarking analysis of $fname...")
    println("Samples: $samples")
    println()

    times = Float64[]

    # Warmup
    quick_check(f, types)

    # Collect samples
    for i in 1:samples
        start_time = time()
        report = quick_check(f, types)
        elapsed = time() - start_time
        push!(times, elapsed)

        print("  Sample $i/$samples: $(round(elapsed * 1000, digits=2))ms\r")
    end
    println()

    # Calculate statistics
    sorted_times = sort(times)
    n = length(times)

    mean_time = sum(times) / n
    median_time = n % 2 == 0 ? (sorted_times[div(n, 2)] + sorted_times[div(n, 2) + 1]) / 2 : sorted_times[div(n, 2) + 1]
    std_time = sqrt(sum((t - mean_time)^2 for t in times) / n)

    stats = Dict(
        :function => fname,
        :samples => samples,
        :min => minimum(times),
        :max => maximum(times),
        :mean => mean_time,
        :median => median_time,
        :std => std_time,
        :times => times
    )

    println()
    println("Results:")
    println("  Min:    $(round(stats[:min] * 1000, digits=2))ms")
    println("  Max:    $(round(stats[:max] * 1000, digits=2))ms")
    println("  Mean:   $(round(stats[:mean] * 1000, digits=2))ms")
    println("  Median: $(round(stats[:median] * 1000, digits=2))ms")
    println("  Std:    $(round(stats[:std] * 1000, digits=2))ms")
    println()

    return stats
end

"""
    benchmark_compilation(f::Function, types::Tuple, path::String, name::String;
                         samples::Int=3) -> Dict

Benchmark the compilation performance for a function.

# Arguments
- `f::Function`: Function to compile
- `types::Tuple`: Argument type tuple
- `path::String`: Output directory
- `name::String`: Library name
- `samples::Int=3`: Number of compilation attempts

# Returns
Dictionary with compilation timing statistics

# Example
```julia
julia> stats = benchmark_compilation(my_func, (Int,), "/tmp", "my_lib")
julia> println("Mean compilation time: \$(stats[:mean])s")
```
"""
function benchmark_compilation(f::Function, types::Tuple, path::String, name::String;
                               samples::Int=3)
    fname = nameof(f)

    println("Benchmarking compilation of $fname...")
    println("Samples: $samples")
    println()

    times = Float64[]
    successes = 0

    for i in 1:samples
        # Clean up previous compilation
        lib_file = joinpath(path, "$(name).so")
        isfile(lib_file) && rm(lib_file)

        start_time = time()
        try
            compile_shlib(f, types, path, name)
            elapsed = time() - start_time
            push!(times, elapsed)
            successes += 1
            println("  Sample $i/$samples: $(round(elapsed, digits=2))s ")
        catch e
            elapsed = time() - start_time
            push!(times, elapsed)
            println("  Sample $i/$samples: $(round(elapsed, digits=2))s (failed)")
        end
    end
    println()

    if isempty(times)
        println(" No successful compilations")
        return Dict(:success => false)
    end

    mean_time = sum(times) / length(times)

    stats = Dict(
        :function => fname,
        :samples => samples,
        :successes => successes,
        :success_rate => successes / samples,
        :min => minimum(times),
        :max => maximum(times),
        :mean => mean_time,
        :times => times
    )

    println("Results:")
    println("  Success rate: $successes/$samples ($(round(successes/samples*100, digits=1))%)")
    println("  Min time:     $(round(stats[:min], digits=2))s")
    println("  Max time:     $(round(stats[:max], digits=2))s")
    println("  Mean time:    $(round(stats[:mean], digits=2))s")
    println()

    return stats
end

"""
    compare_performance(old_func::Function, new_func::Function, types::Tuple;
                       samples::Int=10) -> Dict

Compare analysis performance between two function versions.

Useful for tracking optimization impact.

# Example
```julia
julia> comparison = compare_performance(old_version, new_version, (Int,))
julia> println("Speedup: \$(comparison[:speedup])x")
```
"""
function compare_performance(old_func::Function, new_func::Function, types::Tuple;
                            samples::Int=10)
    println("="^70)
    println("PERFORMANCE COMPARISON")
    println("="^70)
    println()

    old_name = nameof(old_func)
    new_name = nameof(new_func)

    # Benchmark old version
    println("Benchmarking $old_name (old version)...")
    old_stats = benchmark_analysis(old_func, types; samples=samples)

    println()

    # Benchmark new version
    println("Benchmarking $new_name (new version)...")
    new_stats = benchmark_analysis(new_func, types; samples=samples)

    # Compare
    speedup = old_stats[:mean] / new_stats[:mean]
    improvement = (1 - new_stats[:mean] / old_stats[:mean]) * 100

    println()
    println("="^70)
    println("COMPARISON RESULTS")
    println("="^70)
    println()
    println("Old ($old_name):")
    println("  Mean: $(round(old_stats[:mean] * 1000, digits=2))ms")
    println()
    println("New ($new_name):")
    println("  Mean: $(round(new_stats[:mean] * 1000, digits=2))ms")
    println()

    if speedup > 1.0
        println("Improvement: $(round(improvement, digits=1))% faster ($(round(speedup, digits=2))x speedup)")
    elseif speedup < 1.0
        println(" Regression: $(round(-improvement, digits=1))% slower ($(round(1/speedup, digits=2))x slowdown)")
    else
        println("->  No significant change")
    end
    println()
    println("="^70)

    return Dict(
        :old_name => old_name,
        :new_name => new_name,
        :old_mean => old_stats[:mean],
        :new_mean => new_stats[:mean],
        :speedup => speedup,
        :improvement_percent => improvement,
        :old_stats => old_stats,
        :new_stats => new_stats
    )
end

"""
    track_quality_over_time(f::Function, types::Tuple, history_file::String)

Track function quality metrics over time.

Appends current analysis results to a history file for trend tracking.

# Arguments
- `f::Function`: Function to track
- `types::Tuple`: Argument type tuple
- `history_file::String`: Path to history JSON file

# Example
```julia
julia> track_quality_over_time(my_func, (Int,), "quality_history.json")
Quality tracked: score 85/100
   History file: quality_history.json
```
"""
function track_quality_over_time(f::Function, types::Tuple, history_file::String)
    fname = nameof(f)

    # Run analysis
    report = quick_check(f, types)

    # Create history entry
    entry = Dict(
        "timestamp" => string(now()),
        "function" => string(fname),
        "score" => report.score,
        "ready" => report.ready_for_compilation,
        "issues" => report.issues,
        "metrics" => Dict(
            "has_abstract_types" => report.monomorphization.has_abstract_types,
            "allocations" => length(report.escape_analysis.allocations),
            "dynamic_calls" => report.devirtualization.total_dynamic_calls,
            "potential_leaks" => report.lifetime_analysis.potential_leaks
        )
    )

    # Load existing history
    history = if isfile(history_file)
        JSON.parsefile(history_file)
    else
        []
    end

    # Append new entry
    push!(history, entry)

    # Save updated history
    open(history_file, "w") do io
        JSON.print(io, history, 2)
    end

    println("Quality tracked: score $(report.score)/100")
    println("   History file: $history_file")
    println("   Total entries: $(length(history))")

    # Show trend if we have enough data
    if length(history) >= 2
        scores = [h["score"] for h in history]
        recent_trend = scores[end] - scores[end-1]

        if recent_trend > 0
            println("   Recent trend: ⬆ +$recent_trend points")
        elseif recent_trend < 0
            println("   Recent trend: ⬇ $recent_trend points")
        else
            println("   Recent trend: ➡ no change")
        end
    end

    println()

    return entry
end

"""
    plot_quality_history(history_file::String)

Display quality trends from a history file.

Shows score progression over time (text-based visualization).

# Example
```julia
julia> plot_quality_history("quality_history.json")
```
"""
function plot_quality_history(history_file::String)
    if !isfile(history_file)
        println("History file not found: $history_file")
        return
    end

    history = JSON.parsefile(history_file)

    if isempty(history)
        println("No history data found")
        return
    end

    println("="^70)
    println("QUALITY HISTORY")
    println("="^70)
    println()

    # Extract data
    timestamps = [h["timestamp"] for h in history]
    scores = [h["score"] for h in history]

    println("Function: $(history[1]["function"])")
    println("Entries: $(length(history))")
    println()

    # Simple text-based plot
    max_score = maximum(scores)
    min_score = minimum(scores)

    println("Score Progression:")
    println()

    for (i, (ts, score)) in enumerate(zip(timestamps, scores))
        # Truncate timestamp
        date_str = split(ts, 'T')[1]

        # Create bar
        bar_len = div(score, 2)  # Scale to 50 chars max
        bar = "█"^bar_len

        # Trend indicator
        trend = ""
        if i > 1
            diff = score - scores[i-1]
            trend = diff > 0 ? " ⬆" : diff < 0 ? " ⬇" : " ➡"
        end

        println("$date_str  $bar  $score/100$trend")
    end

    println()

    # Statistics
    println("Statistics:")
    println("  Current: $(scores[end])/100")
    println("  Best:    $max_score/100")
    println("  Worst:   $min_score/100")
    println("  Average: $(round(Int, sum(scores) / length(scores)))/100")

    if length(scores) >= 2
        total_change = scores[end] - scores[1]
        println("  Change:  $(total_change > 0 ? "+" : "")$total_change points")
    end

    println()
    println("="^70)
end

export benchmark_analysis, benchmark_compilation, compare_performance
export track_quality_over_time, plot_quality_history
export BenchmarkResult
