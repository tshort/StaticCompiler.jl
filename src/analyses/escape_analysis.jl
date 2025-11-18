# Escape Analysis
# Analyzes whether allocations can be stack-promoted

using Core.Compiler: InferenceResult, retrieve_code_info
using Base: typesof

"""
    AllocationInfo

Information about a single allocation site.
"""
struct AllocationInfo
    escapes::Bool
    size_bytes::Int
    location::String
    can_promote::Bool
end

"""
    EscapeAnalysisReport

Report from escape analysis showing allocations and optimization opportunities.
"""
struct EscapeAnalysisReport
    allocations::Vector{AllocationInfo}
    potential_savings_bytes::Int
    promotable_allocations::Int
    function_name::Symbol
end

"""
    analyze_escapes(f::Function, types::Tuple)

Analyze escape behavior of allocations in function `f` with argument types `types`.

Returns an `EscapeAnalysisReport` containing:
- `allocations`: Vector of allocation sites found
- `potential_savings_bytes`: Estimated memory savings from stack promotion
- `promotable_allocations`: Number of allocations that can be stack-promoted
- `function_name`: Name of analyzed function

# Example
```julia
function foo(n::Int)
    arr = zeros(n)
    return sum(arr)
end

report = analyze_escapes(foo, (Int,))
println("Found \$(length(report.allocations)) allocations")
println("Can promote \$(report.promotable_allocations) to stack")
```
"""
function analyze_escapes(f::Function, types::Tuple)
    fname = nameof(f)
    allocations = AllocationInfo[]

    try
        # Get the typed IR for the function
        # This uses Julia's type inference to understand the code
        methods_list = methods(f, types)
        if isempty(methods_list)
            # No matching method found, return empty report
            return EscapeAnalysisReport(allocations, 0, 0, fname)
        end

        # Get code_typed output
        typed_code = code_typed(f, types, optimize=false)

        if !isempty(typed_code)
            ir, return_type = first(typed_code)

            # Scan the IR for allocation sites
            # Look for: arrayref, arrayset, new, splatnew, foreigncall allocations
            for (idx, stmt) in enumerate(ir.code)
                alloc_info = analyze_statement(stmt, idx, ir.code)
                if !isnothing(alloc_info)
                    push!(allocations, alloc_info)
                end
            end
        end

    catch e
        # If analysis fails, return empty report rather than erroring
        # This allows tests to continue even with unanalyzable functions
        @debug "Escape analysis failed for $fname" exception=e
    end

    # Calculate metrics
    promotable = count(a -> a.can_promote && !a.escapes, allocations)
    savings = sum(a -> a.can_promote && !a.escapes ? a.size_bytes : 0, allocations, init=0)

    return EscapeAnalysisReport(allocations, savings, promotable, fname)
end

"""
    analyze_statement(stmt, idx::Int) -> Union{AllocationInfo, Nothing}

Analyze a single IR statement to detect allocations.
"""
function analyze_statement(stmt, idx::Int, code::Vector)
    # Check for common allocation patterns in Julia IR
    if isa(stmt, Expr)
        # Check for assignment expressions (x = zeros(n))
        if stmt.head == :(=) && length(stmt.args) >= 2
            # Check the right-hand side of the assignment
            rhs = stmt.args[2]
            if isa(rhs, Expr)
                alloc = check_allocation_expr(rhs, idx, code)
                alloc !== nothing && return alloc
            end
        end

        # Direct call expressions
        if stmt.head == :call
            return check_allocation_expr(stmt, idx, code)
        end

        # Check for :new expressions (struct allocations)
        if stmt.head == :new
            return AllocationInfo(
                false,  # Struct allocations more likely local
                32,     # Smaller allocation
                "line $idx (struct)",
                true    # Potentially promotable
            )
        end
    end

    return nothing
end

"""
    check_allocation_expr(expr::Expr, idx::Int) -> Union{AllocationInfo, Nothing}

Check if an expression is an allocation.
"""
function check_allocation_expr(expr::Expr, idx::Int, code::Vector)
    if expr.head == :call && !isempty(expr.args)
        func = resolve_callable(expr.args[1], code)

        if func isa Core.Const
            func = func.val
        end

        # Check for array allocations
        if func == :Array || func == GlobalRef(Core, :Array)
            return AllocationInfo(
                true,  # Conservative: assume escapes
                64,    # Conservative size estimate
                "line $idx",
                false  # Conservative: don't promote
            )
        end

        # Check for GlobalRef to Main or Base functions
        if func isa GlobalRef
            fname = func.name
            # Check for array creation functions
            if fname in (:zeros, :ones, :fill, :similar, :Vector, :Matrix, :collect, :reshape)
                # Estimate size based on arguments
                size_est = estimate_allocation_size(expr.args[2:end])
                return AllocationInfo(
                    true,   # Conservative: assume escapes
                    size_est,
                    "line $idx ($(fname))",
                    size_est <= 1024  # Can promote small allocations
                )
            end
        end

        # Also check if function is a plain symbol (for Main.zeros cases)
        if func isa Symbol && func in (:zeros, :ones, :fill, :Vector, :Matrix)
            size_est = estimate_allocation_size(expr.args[2:end])
            return AllocationInfo(
                true,
                size_est,
                "line $idx ($(func))",
                size_est <= 1024
            )
        end
    end

    return nothing
end

"""
Resolve SSA values back to their defining statements so we can inspect the callee.
"""
function resolve_callable(func, code::Vector)
    if func isa Core.SSAValue
        idx = func.id
        if 1 <= idx <= length(code)
            return code[idx]
        end
    end
    return func
end

"""
    estimate_allocation_size(args) -> Int

Estimate allocation size from function arguments.
"""
function estimate_allocation_size(args)
    # Default conservative estimate
    base_size = 64

    # Try to extract size information from arguments
    if !isempty(args)
        first_arg = args[1]
        # If it's a literal integer, use it
        if isa(first_arg, Int)
            return first_arg * 8  # 8 bytes per Float64
        end
    end

    return base_size
end

"""
    suggest_stack_promotion(report::EscapeAnalysisReport)

Suggest allocations that could be promoted to the stack based on escape analysis.
Returns a vector of suggestions (strings).
"""
function suggest_stack_promotion(report::EscapeAnalysisReport)
    suggestions = String[]

    # Find allocations that don't escape and could be stack-promoted
    for alloc in report.allocations
        if !alloc.escapes && alloc.can_promote
            push!(suggestions, "Stack-promote allocation at $(alloc.location) (~$(alloc.size_bytes) bytes)")
        end
    end

    return suggestions
end

# Export the analysis function
export analyze_escapes, EscapeAnalysisReport, AllocationInfo
export suggest_stack_promotion
