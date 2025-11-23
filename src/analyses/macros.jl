# Macro utilities for inline analysis
# Convenience macros for quick analysis during development

"""
    @analyze function_call

Analyze a function call and print a quick readiness report.

# Example
```julia
julia> @analyze compute_fast(10, 20)
======================================================================
COMPILATION READINESS REPORT: compute_fast
======================================================================
Status: READY
Score:  100/100
...
======================================================================

Result: 200
```
"""
macro analyze(expr)
    if expr.head == :call
        func = expr.args[1]
        args = expr.args[2:end]

        # Build type tuple from arguments
        types_expr = Expr(:tuple, [:(typeof($arg)) for arg in args]...)

        return quote
            local result = $(esc(expr))
            local func_ref = $(esc(func))
            local types = $types_expr

            println()
            report = quick_check(func_ref, types)
            print_readiness_report(report)
            println()
            println("Result: ", result)
            println()

            result
        end
    else
        error("@analyze requires a function call expression")
    end
end

"""
    @check_ready function_name(arg_types...)

Check if a function is ready for compilation with the given argument types.
Returns true/false and prints a summary.

# Example
```julia
julia> @check_ready my_function(Int, Float64)
my_function is ready for compilation (score: 95/100)
true
```
"""
macro check_ready(expr)
    if expr.head == :call
        func = expr.args[1]
        types_tuple = Expr(:tuple, expr.args[2:end]...)

        return quote
            local func_ref = $(esc(func))
            local types = $types_tuple
            verify_compilation_readiness(func_ref, types)
        end
    else
        error("@check_ready requires a function call with types, e.g., @check_ready func(Int, Float64)")
    end
end

"""
    @quick_check function_name(arg_types...)

Run quick_check and return the report without printing.

# Example
```julia
julia> report = @quick_check my_function(Int, Float64)
julia> println("Score: ", report.score)
Score: 95
```
"""
macro quick_check(expr)
    if expr.head == :call
        func = expr.args[1]
        types_tuple = Expr(:tuple, expr.args[2:end]...)

        return quote
            local func_ref = $(esc(func))
            local types = $types_tuple
            quick_check(func_ref, types)
        end
    else
        error("@quick_check requires a function call with types")
    end
end

"""
    @suggest_fixes function_name(arg_types...)

Analyze a function and provide specific optimization suggestions with code examples.

# Example
```julia
julia> @suggest_fixes problematic_func(Number)
Found 2 issues:
1. Abstract type parameter
   Fix: Change `function problematic_func(x::Number)` to `function problematic_func(x::T) where {T<:Number}`
...
```
"""
macro suggest_fixes(expr)
    if expr.head == :call
        func = expr.args[1]
        types_tuple = Expr(:tuple, expr.args[2:end]...)

        return quote
            local func_ref = $(esc(func))
            local types = $types_tuple
            suggest_optimizations(func_ref, types)
        end
    else
        error("@suggest_fixes requires a function call with types")
    end
end

export @analyze, @check_ready, @quick_check, @suggest_fixes
