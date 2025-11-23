# Analysis Result Caching
# Cache analysis results to speed up repeated checks

# Global cache
const ANALYSIS_CACHE = Dict{UInt64, Tuple{CompilationReadinessReport, Float64}}()
const CACHE_TTL = 300.0  # 5 minutes default TTL

"""
    cache_key(f::Function, types::Tuple) -> UInt64

Generate a cache key for a function and its argument types.
"""
function cache_key(f::Function, types::Tuple)
    # Create a hash from function name and type signature
    return hash((nameof(f), types))
end

"""
    quick_check_cached(f::Function, types::Tuple; ttl::Float64=$CACHE_TTL) -> CompilationReadinessReport

Run quick_check with caching support.

Cached results are reused if they're less than `ttl` seconds old.

# Arguments
- `f::Function`: Function to analyze
- `types::Tuple`: Argument type tuple
- `ttl::Float64`: Time-to-live for cache entries in seconds (default: 300)

# Example
```julia
julia> report = quick_check_cached(my_func, (Int,))  # Runs analysis
julia> report = quick_check_cached(my_func, (Int,))  # Uses cache (fast!)
```
"""
function quick_check_cached(f::Function, types::Tuple; ttl::Float64=CACHE_TTL)
    key = cache_key(f, types)
    current_time = time()

    # Check cache
    if haskey(ANALYSIS_CACHE, key)
        cached_report, cached_time = ANALYSIS_CACHE[key]

        # Check if cache is still valid
        if current_time - cached_time < ttl
            return cached_report
        end
    end

    # Cache miss or expired - run analysis
    report = quick_check(f, types)

    # Store in cache
    ANALYSIS_CACHE[key] = (report, current_time)

    return report
end

"""
    batch_check_cached(functions::Vector; ttl::Float64=$CACHE_TTL) -> Dict

Run batch_check with caching support.

# Arguments
- `functions`: Vector of (Function, Tuple) pairs
- `ttl::Float64`: Time-to-live for cache entries in seconds

# Example
```julia
julia> results = batch_check_cached([
           (func1, (Int,)),
           (func2, (Float64,))
       ])
```
"""
function batch_check_cached(functions::Vector; ttl::Float64=CACHE_TTL)
    results = Dict{Symbol, CompilationReadinessReport}()

    for (f, types) in functions
        report = quick_check_cached(f, types; ttl=ttl)
        results[report.function_name] = report
    end

    return results
end

"""
    clear_analysis_cache!()

Clear all cached analysis results.

# Example
```julia
julia> clear_analysis_cache!()
Cache cleared (removed 15 entries)
```
"""
function clear_analysis_cache!()
    count = length(ANALYSIS_CACHE)
    empty!(ANALYSIS_CACHE)
    println("Cache cleared (removed $count entries)")
    return count
end

"""
    cache_stats() -> Dict

Get statistics about the analysis cache.

Returns a dictionary with:
- `:entries`: Number of cached entries
- `:oldest`: Age of oldest entry in seconds
- `:newest`: Age of newest entry in seconds
- `:memory`: Approximate memory usage in MB

# Example
```julia
julia> stats = cache_stats()
julia> println("Cache has \$(stats[:entries]) entries")
```
"""
function cache_stats()
    if isempty(ANALYSIS_CACHE)
        return Dict(
            :entries => 0,
            :oldest => 0.0,
            :newest => 0.0,
            :memory => 0.0
        )
    end

    current_time = time()
    ages = [current_time - cached_time for (_, cached_time) in values(ANALYSIS_CACHE)]

    # Estimate memory (rough approximation)
    # Each report is roughly 1KB
    memory_mb = length(ANALYSIS_CACHE) * 1024 / (1024 * 1024)

    return Dict(
        :entries => length(ANALYSIS_CACHE),
        :oldest => maximum(ages),
        :newest => minimum(ages),
        :memory => round(memory_mb, digits=2)
    )
end

"""
    prune_cache!(max_age::Float64=$CACHE_TTL)

Remove cache entries older than max_age seconds.

# Arguments
- `max_age::Float64`: Maximum age in seconds (default: CACHE_TTL)

# Returns
Number of entries removed

# Example
```julia
julia> removed = prune_cache!(600.0)  # Remove entries older than 10 minutes
Pruned 5 expired entries
```
"""
function prune_cache!(max_age::Float64=CACHE_TTL)
    current_time = time()
    to_remove = UInt64[]

    for (key, (_, cached_time)) in ANALYSIS_CACHE
        if current_time - cached_time > max_age
            push!(to_remove, key)
        end
    end

    for key in to_remove
        delete!(ANALYSIS_CACHE, key)
    end

    if !isempty(to_remove)
        println("Pruned $(length(to_remove)) expired entries")
    end

    return length(to_remove)
end

"""
    with_cache(f::Function; ttl::Float64=$CACHE_TTL)

Execute a function with automatic cache pruning.

Prunes the cache before and after execution.

# Example
```julia
julia> with_cache(ttl=600.0) do
           # Your analysis code here
           results = batch_check_cached(my_functions)
       end
```
"""
function with_cache(f::Function; ttl::Float64=CACHE_TTL)
    prune_cache!(ttl)
    try
        result = f()
        return result
    finally
        prune_cache!(ttl)
    end
end

export quick_check_cached, batch_check_cached
export clear_analysis_cache!, cache_stats, prune_cache!
export with_cache
