# Project-Wide Scanning Utilities
# Tools for discovering and analyzing all functions in a module or project

"""
    scan_module(mod::Module; include_base::Bool=false, min_methods::Int=1) -> Vector{Function}

Scan a module and return all user-defined functions.

# Arguments
- `mod::Module`: Module to scan
- `include_base::Bool=false`: Include Base module functions (usually not desired)
- `min_methods::Int=1`: Minimum number of methods a function must have

# Returns
Vector of Function objects found in the module

# Example
```julia
julia> funcs = scan_module(MyPackage)
julia> println("Found \$(length(funcs)) functions")
```
"""
function scan_module(mod::Module; include_base::Bool = false, min_methods::Int = 1)
    functions = Function[]

    for name in names(mod; all = true, imported = false)
        # Skip internal names and non-exported symbols
        if startswith(string(name), "#") || startswith(string(name), "@")
            continue
        end

        try
            obj = getfield(mod, name)

            # Check if it's a function
            if obj isa Function
                # Get parent module
                parent_mod = parentmodule(obj)

                # Skip Base functions unless requested
                if !include_base && (parent_mod === Base || parent_mod === Core)
                    continue
                end

                # Check method count
                method_count = length(methods(obj))
                if method_count >= min_methods
                    push!(functions, obj)
                end
            end
        catch
            # Skip if we can't access the object
            continue
        end
    end

    return unique(functions)
end

"""
    scan_module_with_types(mod::Module; include_base::Bool=false) -> Vector{Tuple{Function, Vector{Tuple}}}

Scan a module and return functions with their method signatures.

# Returns
Vector of tuples: (Function, Vector of argument type tuples)

# Example
```julia
julia> func_types = scan_module_with_types(MyPackage)
julia> for (func, signatures) in func_types
           println("\$func has \$(length(signatures)) methods")
       end
```
"""
function scan_module_with_types(mod::Module; include_base::Bool = false)
    functions = scan_module(mod; include_base = include_base)
    func_with_types = Tuple{Function, Vector{Tuple}}[]

    for func in functions
        signatures = Tuple[]

        for m in methods(func)
            # Extract parameter types
            sig = m.sig

            if sig isa DataType
                # Get parameter types (skip first parameter which is the function itself)
                params = sig.parameters
                if length(params) > 1
                    # Skip the function type itself
                    types = Tuple(params[2:end])
                    push!(signatures, types)
                end
            end
        end

        if !isempty(signatures)
            push!(func_with_types, (func, signatures))
        end
    end

    return func_with_types
end

"""
    analyze_module(mod::Module; threshold::Int=80, include_base::Bool=false) -> Dict

Analyze all functions in a module and return summary.

# Arguments
- `mod::Module`: Module to analyze
- `threshold::Int=80`: Compilation readiness threshold
- `include_base::Bool=false`: Include Base module functions

# Returns
Dictionary containing:
- `:results`: Batch analysis results
- `:summary`: Summary statistics
- `:problematic`: Functions below threshold

# Example
```julia
julia> analysis = analyze_module(MyPackage, threshold=90)
julia> println("Analyzed \$(length(analysis[:results])) functions")
julia> println("Problematic: \$(length(analysis[:problematic]))")
```
"""
function analyze_module(mod::Module; threshold::Int = 80, include_base::Bool = false, verbose::Bool = true)
    if verbose
        println("="^70)
        println("MODULE ANALYSIS: $mod")
        println("="^70)
        println()
        println("Scanning for functions...")
    end

    func_types = scan_module_with_types(mod; include_base = include_base)

    if verbose
        println("Found $(length(func_types)) functions with analyzable signatures")
        println()
        println("Analyzing functions...")
        println()
    end

    # Prepare for batch analysis
    analysis_list = Tuple{Function, Tuple}[]

    for (func, signatures) in func_types
        # Analyze first signature of each function
        if !isempty(signatures)
            push!(analysis_list, (func, signatures[1]))
        end
    end

    # Run batch analysis
    results = batch_check(analysis_list)

    # Calculate statistics
    total = length(results)
    ready = count(r -> r.ready_for_compilation, values(results))
    avg_score = total > 0 ? round(Int, sum(r.score for r in values(results)) / total) : 0

    # Find problematic functions
    problematic = Dict{Symbol, CompilationReadinessReport}()
    for (name, report) in results
        if report.score < threshold
            problematic[name] = report
        end
    end

    if verbose
        println()
        println("="^70)
        println("ANALYSIS SUMMARY")
        println("="^70)
        println()
        println("Total functions analyzed: $total")
        println("Ready for compilation:    $ready ($ready/$total)")
        println("Average score:            $avg_score/100")
        println("Below threshold ($threshold): $(length(problematic))")
        println()

        if !isempty(problematic)
            println("Functions needing attention:")
            for (name, report) in sort(collect(problematic), by = x -> x[2].score)
                println("  • $name (score: $(report.score)/100)")
                for issue in report.issues
                    println("    - $issue")
                end
            end
        end

        println()
        println("="^70)
    end

    return Dict(
        :results => results,
        :summary => Dict(
            :total => total,
            :ready => ready,
            :average_score => avg_score,
            :pass_rate => ready / total * 100
        ),
        :problematic => problematic,
        :all_functions => func_types
    )
end

"""
    compare_modules(mod1::Module, mod2::Module; threshold::Int=80) -> Dict

Compare compiler readiness between two modules.

Useful for comparing before/after refactoring or different implementations.

# Example
```julia
julia> comparison = compare_modules(MyPackageV1, MyPackageV2)
julia> println("Improvement: \$(comparison[:improvement])%")
```
"""
function compare_modules(mod1::Module, mod2::Module; threshold::Int = 80, verbose::Bool = true)
    if verbose
        println("="^70)
        println("MODULE COMPARISON")
        println("="^70)
        println()
        println("Analyzing $mod1...")
    end

    analysis1 = analyze_module(mod1; threshold = threshold, verbose = false)

    if verbose
        println("Analyzing $mod2...")
    end

    analysis2 = analyze_module(mod2; threshold = threshold, verbose = false)

    # Calculate improvements
    score1 = analysis1[:summary][:average_score]
    score2 = analysis2[:summary][:average_score]
    score_diff = score2 - score1

    ready1 = analysis1[:summary][:pass_rate]
    ready2 = analysis2[:summary][:pass_rate]
    ready_diff = ready2 - ready1

    if verbose
        println()
        println("="^70)
        println("COMPARISON RESULTS")
        println("="^70)
        println()
        println("Module 1 ($mod1):")
        println("  Average score: $score1/100")
        println("  Ready rate:    $(round(ready1, digits = 1))%")
        println()
        println("Module 2 ($mod2):")
        println("  Average score: $score2/100")
        println("  Ready rate:    $(round(ready2, digits = 1))%")
        println()
        println("Change:")

        score_arrow = score_diff > 0 ? "⬆" : score_diff < 0 ? "⬇" : "➡"
        ready_arrow = ready_diff > 0 ? "⬆" : ready_diff < 0 ? "⬇" : "➡"

        println("  Score:  $score_arrow $(abs(score_diff)) points")
        println("  Ready:  $ready_arrow $(round(abs(ready_diff), digits = 1))%")
        println()

        if score_diff > 0 && ready_diff > 0
            println("Module 2 shows improvement!")
        elseif score_diff < 0 || ready_diff < 0
            println(" Module 2 shows regression")
        else
            println("->  No significant change")
        end

        println()
        println("="^70)
    end

    return Dict(
        :module1 => analysis1,
        :module2 => analysis2,
        :score_improvement => score_diff,
        :ready_improvement => ready_diff
    )
end

export scan_module, scan_module_with_types
export analyze_module, compare_modules
