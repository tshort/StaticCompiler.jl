# Monomorphization Analysis
# Analyzes abstract type parameters that could be specialized

"""
    AbstractParameterInfo

Information about an abstract type parameter.
"""
struct AbstractParameterInfo
    position::Int
    type::Type
    is_abstract::Bool
end

"""
    MonomorphizationReport

Report from monomorphization analysis showing abstract types.
"""
struct MonomorphizationReport
    has_abstract_types::Bool
    function_name::Symbol
    abstract_parameters::Vector{AbstractParameterInfo}
    optimization_opportunities::Int
    can_fully_monomorphize::Bool
    specialization_factor::Float64
end

"""
    analyze_monomorphization(f::Function, types::Tuple)

Analyze whether function `f` with argument types `types` uses abstract types
that could benefit from monomorphization (specialization).

Returns a `MonomorphizationReport` containing:
- `has_abstract_types`: Whether abstract types were found
- `function_name`: Name of analyzed function
- `abstract_parameters`: List of abstract type parameters
- `optimization_opportunities`: Count of parameters that could be specialized

# Example
```julia
function process(x::Number)
    return x * 2
end

report = analyze_monomorphization(process, (Number,))
if report.has_abstract_types
    println("Function uses abstract types and could be specialized")
end
```
"""
function analyze_monomorphization(f::Function, types::Tuple)
    fname = nameof(f)
    abstract_params = AbstractParameterInfo[]

    # Analyze each input type
    for (i, T) in enumerate(types)
        is_abstract = isabstracttype(T)

        if is_abstract
            push!(abstract_params, AbstractParameterInfo(i, T, true))
        else
            # Check for nested abstract types (e.g., Vector{Number})
            nested_abstracts = find_nested_abstract_types(T)
            for abstract_type in nested_abstracts
                push!(abstract_params, AbstractParameterInfo(i, abstract_type, true))
            end
        end
    end

    has_abstract = !isempty(abstract_params)
    opportunities = length(abstract_params)

    # Determine if can fully monomorphize
    # Can monomorphize if all abstract types can be replaced with concrete ones
    can_monomorphize = has_abstract  # If has abstract types, it CAN be monomorphized

    # Specialization factor: ratio of concrete to total types
    # 1.0 means fully concrete, 0.0 means fully abstract
    total_params = length(types)
    specialization = if total_params > 0
        (total_params - opportunities) / total_params
    else
        1.0  # No parameters means fully specialized
    end

    return MonomorphizationReport(
        has_abstract,
        fname,
        abstract_params,
        opportunities,
        can_monomorphize,
        specialization
    )
end

"""
    find_nested_abstract_types(T::Type) -> Vector{Type}

Recursively find all abstract types nested within a type's parameters.
"""
function find_nested_abstract_types(T::Type)
    abstract_types = Type[]

    if T isa DataType && !isempty(T.parameters)
        for param in T.parameters
            if param isa Type
                if isabstracttype(param)
                    push!(abstract_types, param)
                end
                # Recursively check nested parameters
                append!(abstract_types, find_nested_abstract_types(param))
            end
        end
    end

    return abstract_types
end

"""
    isabstracttype(T) -> Bool

Check if type T is abstract (including checking for abstract type parameters).
"""
function isabstracttype(T)
    # Use Base's implementation for all types
    # UnionAll and Union are considered abstract
    if T isa UnionAll
        return true
    elseif T isa Union
        return true
    else
        return Base.isabstracttype(T)
    end
end

# Export the analysis function
export analyze_monomorphization, MonomorphizationReport, AbstractParameterInfo
