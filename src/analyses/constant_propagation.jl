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
    ssa_constants = Dict{Int, Bool}()
    slot_constants = Dict{Int, Bool}()

    try
        # Get typed IR
        typed_code = code_typed(f, types, optimize = false)

        if !isempty(typed_code)
            ir, return_type = first(typed_code)

            total_statements = length(ir.code)

            # Scan for constant values and foldable expressions
            for (idx, stmt) in enumerate(ir.code)
                is_constant_stmt = false

                # Check for literal constants
                if is_constant_value(stmt)
                    is_constant_stmt = true
                    push!(constants, ConstantInfo(stmt, "line $idx", true))
                    foldable_count += 1

                    # Track slot reads so downstream SSA values know the slot value
                elseif stmt isa Core.SlotNumber
                    is_constant_stmt = get(slot_constants, stmt.id, false)

                    # Check for expressions with constant operands
                elseif isa(stmt, Expr)
                    if is_foldable_expression(stmt, ir, ssa_constants, slot_constants)
                        is_constant_stmt = true
                        push!(constants, ConstantInfo(stmt, "line $idx", true))
                        foldable_count += 1
                    end
                end

                # Mark the SSA value produced by this statement
                ssa_constants[idx] = is_constant_stmt
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
        @debug "Constant propagation analysis failed for $fname" exception = e
    end

    # Return empty report on failure
    return ConstantPropagationReport(constants, foldable_count, 0.0, fname)
end

"""
    is_constant_value(stmt) -> Bool

Check if a statement represents a constant value.
"""
function is_constant_value(stmt)
    stmt = stmt isa Core.Const ? stmt.value : stmt

    # Literal numbers, strings, symbols
    return isa(stmt, Number) || isa(stmt, String) || isa(stmt, Symbol) ||
        isa(stmt, Bool) || isa(stmt, Nothing) ||
        (isa(stmt, QuoteNode) && isa(stmt.value, Union{Number, String, Symbol}))
end

"""
    is_foldable_expression(expr::Expr, ir, ssa_constants, slot_constants) -> Bool

Check if an expression can be folded at compile time.
"""
function is_foldable_expression(expr::Expr, ir, ssa_constants, slot_constants)
    # Handle assignment expressions
    if expr.head == :(=) && length(expr.args) >= 2
        rhs = expr.args[2]
        rhs_constant = is_constant_reference(rhs, ir, ssa_constants, slot_constants) ||
            (isa(rhs, Expr) && is_foldable_call(rhs, ir, ssa_constants, slot_constants))

        if expr.args[1] isa Core.SlotNumber
            slot_constants[expr.args[1].id] = rhs_constant
        end

        return rhs_constant
    end

    # Direct call expressions
    if expr.head == :call
        return is_foldable_call(expr, ir, ssa_constants, slot_constants)
    end

    return false
end

"""
    resolve_value(ir, value)

Resolve SSAValue and Core.Const wrappers to the underlying value.
"""
function resolve_value(ir, value)
    current = value
    while true
        if current isa Core.Const
            current = current.value
        elseif current isa Core.SSAValue
            current = ir.code[current.id]
        else
            return current
        end
    end
    return
end

"""
    is_constant_reference(arg, ir, ssa_constants, slot_constants) -> Bool

Check if an argument is a constant or a reference to a constant.
"""
function is_constant_reference(arg, ir, ssa_constants, slot_constants)
    resolved = resolve_value(ir, arg)

    if is_constant_value(resolved)
        return true
    elseif resolved isa Core.SSAValue
        return get(ssa_constants, resolved.id, false)
    elseif resolved isa Core.SlotNumber
        return get(slot_constants, resolved.id, false)
    end

    return false
end

"""
    is_foldable_function(func, ir, ssa_constants, slot_constants) -> Bool

Check if a function is pure and foldable.
"""
function is_foldable_function(func, ir, ssa_constants, slot_constants)
    resolved = resolve_value(ir, func)

    if resolved isa GlobalRef
        fname = resolved.name
        # Common foldable functions
        return fname in (
            :+, :-, :*, :/, :^, :<, :>, :<=, :>=, :(==), :(!=),
            :abs, :sqrt, :sin, :cos, :log, :exp,
            :min, :max, :div, :rem, :mod,
        )
    elseif resolved isa Core.SSAValue
        return is_foldable_function(resolved, ir, ssa_constants, slot_constants)
    end

    return false
end

"""
    is_foldable_call(expr::Expr, ir, ssa_constants, slot_constants) -> Bool

Check if a call expression can be folded.
"""
function is_foldable_call(expr::Expr, ir, ssa_constants, slot_constants)
    if expr.head == :call && length(expr.args) >= 2
        func = expr.args[1]

        # Check if it's a foldable function (arithmetic, comparison, etc.)
        if is_foldable_function(func, ir, ssa_constants, slot_constants)
            # Check if all arguments are constants or constant references
            args_foldable = all(arg -> is_constant_reference(arg, ir, ssa_constants, slot_constants), expr.args[2:end])
            return args_foldable
        end
    end

    return false
end

# Export the analysis function
export analyze_constants, ConstantPropagationReport, ConstantInfo
