# Constant Propagation Analysis
# Analyzes constant values and foldable expressions

"""
    ConstantInfo

Information about a constant value found in the code.
"""
struct ConstantInfo
    value::Any
    location::String
    is_foldable::Bool
end

"""
    ConstantPropagationReport

Report from constant propagation analysis showing optimization opportunities.
"""
struct ConstantPropagationReport
    constants_found::Vector{ConstantInfo}
    foldable_expressions::Int
    code_reduction_potential_pct::Float64
    function_name::Symbol
end

"""
    analyze_constants(f::Function, types::Tuple)

Analyze constant values and foldable expressions in function `f` with argument types `types`.

Returns a `ConstantPropagationReport` containing:
- `constants_found`: Vector of constant values detected
- `foldable_expressions`: Count of expressions that could be folded at compile time
- `code_reduction_potential_pct`: Estimated percentage of code that could be eliminated
- `function_name`: Name of analyzed function

# Example
```julia
const FACTOR = 42

function compute(x::Int)
    y = FACTOR * 2  # Constant foldable
    return x + y
end

report = analyze_constants(compute, (Int,))
println("Found \$(report.foldable_expressions) foldable expressions")
println("Potential code reduction: \$(report.code_reduction_potential_pct)%")
```
"""
function analyze_constants(f::Function, types::Tuple)
    fname = nameof(f)
    constants = ConstantInfo[]
    foldable_count = 0

    try
        # Get typed IR
        typed_code = code_typed(f, types, optimize=false)

        if !isempty(typed_code)
            ir, return_type = first(typed_code)

            total_statements = length(ir.code)

            # Scan for constant values and foldable expressions
            for (idx, stmt) in enumerate(ir.code)
                # Check for literal constants
                if is_constant_value(stmt)
                    const_info = ConstantInfo(
                        stmt,
                        "line $idx",
                        true
                    )
                    push!(constants, const_info)
                    foldable_count += 1
                end

                # Check for expressions with constant operands
                if isa(stmt, Expr)
                    if is_foldable_expression(stmt, ir)
                        foldable_count += 1

                        # Try to extract constant value
                        const_info = ConstantInfo(
                            stmt,
                            "line $idx",
                            true
                        )
                        push!(constants, const_info)
                    end
                end
            end

            # Calculate code reduction potential
            reduction_pct = if total_statements > 0
                (foldable_count / total_statements) * 100.0
            else
                0.0
            end

            return ConstantPropagationReport(
                constants,
                foldable_count,
                reduction_pct,
                fname
            )
        end

    catch e
        @debug "Constant propagation analysis failed for $fname" exception=e
    end

    # Return empty report on failure
    return ConstantPropagationReport(constants, foldable_count, 0.0, fname)
end

"""
    is_constant_value(stmt) -> Bool

Check if a statement represents a constant value.
"""
function is_constant_value(stmt)
    # Literal numbers, strings, symbols
    return isa(stmt, Number) || isa(stmt, String) || isa(stmt, Symbol) ||
           isa(stmt, Bool) || isa(stmt, Nothing) ||
           (isa(stmt, QuoteNode) && isa(stmt.value, Union{Number, String, Symbol}))
end

"""
    is_foldable_expression(expr::Expr, ir) -> Bool

Check if an expression can be folded at compile time.
"""
function is_foldable_expression(expr::Expr, ir)
    # Handle assignment expressions
    if expr.head == :(=) && length(expr.args) >= 2
        rhs = expr.args[2]
        if isa(rhs, Expr)
            return check_foldable_call(rhs, ir)
        end
        return is_constant_value(rhs)
    end

    # Direct call expressions
    if expr.head == :call
        return check_foldable_call(expr, ir)
    end

    return false
end

"""
    check_foldable_call(expr::Expr, ir) -> Bool

Check if a call expression can be folded.
"""
function check_foldable_call(expr::Expr, ir)
    if expr.head == :call && length(expr.args) >= 2
        func = expr.args[1]

        # Check if it's a foldable function (arithmetic, comparison, etc.)
        if is_foldable_function(func)
            # Check if all arguments are constants or constant references
            args_foldable = all(arg -> is_constant_or_ref(arg, ir), expr.args[2:end])
            return args_foldable
        end
    end

    return false
end

"""
    is_foldable_function(func) -> Bool

Check if a function is pure and foldable.
"""
function is_foldable_function(func)
    if isa(func, GlobalRef)
        fname = func.name
        # Common foldable functions
        return fname in (:+, :-, :*, :/, :^, :<, :>, :<=, :>=, :(==), :(!=),
                         :abs, :sqrt, :sin, :cos, :log, :exp,
                         :min, :max, :div, :rem, :mod)
    end
    return false
end

"""
    is_constant_or_ref(arg, ir) -> Bool

Check if an argument is a constant or reference to a constant.
"""
function is_constant_or_ref(arg, ir)
    # Direct constant
    if is_constant_value(arg)
        return true
    end

    # SSA value reference - would need to trace back
    # For simplicity, assume SSA values might not be constant
    return false
end

# Export the analysis function
export analyze_constants, ConstantPropagationReport, ConstantInfo
