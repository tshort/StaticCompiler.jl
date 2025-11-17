# Devirtualization Analysis
# Analyzes dynamic dispatch that could be devirtualized

"""
    CallSiteInfo

Information about a dynamic dispatch call site.
"""
struct CallSiteInfo
    function_name::Symbol
    location::String
    num_targets::Int
    can_devirtualize::Bool
end

"""
    DevirtualizationReport

Report from devirtualization analysis showing dynamic dispatch opportunities.
"""
struct DevirtualizationReport
    call_sites::Vector{CallSiteInfo}
    total_dynamic_calls::Int
    devirtualizable_calls::Int
    function_name::Symbol
    total_call_sites::Int
    virtual_call_sites::Int
end

"""
    analyze_devirtualization(f::Function, types::Tuple)

Analyze dynamic dispatch in function `f` with argument types `types` to find
opportunities for devirtualization (eliminating virtual calls).

Returns a `DevirtualizationReport` containing:
- `call_sites`: Vector of dynamic call sites found
- `total_dynamic_calls`: Count of all dynamic dispatches
- `devirtualizable_calls`: Count that could be devirtualized
- `function_name`: Name of analyzed function

# Example
```julia
abstract type Animal end
struct Dog <: Animal end

bark(x::Animal) = "woof"

function process(a::Animal)
    return bark(a)  # Dynamic dispatch
end

report = analyze_devirtualization(process, (Dog,))
println("Found \$(report.total_dynamic_calls) dynamic calls")
```
"""
function analyze_devirtualization(f::Function, types::Tuple)
    fname = nameof(f)
    call_sites = CallSiteInfo[]

    try
        # Get typed IR
        typed_code = code_typed(f, types, optimize=false)

        if !isempty(typed_code)
            ir, return_type = first(typed_code)

            # Scan for invoke and call expressions
            for (idx, stmt) in enumerate(ir.code)
                if isa(stmt, Expr) && stmt.head == :call && length(stmt.args) >= 1
                    func = stmt.args[1]

                    # Check if this is a potentially dynamic call
                    # (calls to methods that could have multiple implementations)
                    if isa(func, GlobalRef) || isa(func, Symbol)
                        call_name = isa(func, GlobalRef) ? func.name : func

                        # Count potential method implementations
                        # For concrete types, dispatch can often be resolved statically
                        # For abstract types, dispatch remains dynamic
                        num_targets = estimate_method_targets(call_name, types)

                        if num_targets > 1
                            # Potentially dynamic call
                            can_devirt = all_types_concrete(types)

                            push!(call_sites, CallSiteInfo(
                                call_name,
                                "line $idx",
                                num_targets,
                                can_devirt
                            ))
                        end
                    end
                end
            end
        end

    catch e
        @debug "Devirtualization analysis failed for $fname" exception=e
    end

    total_calls = length(call_sites)
    devirt_calls = count(c -> c.can_devirtualize, call_sites)

    # Calculate total call sites and virtual call sites
    total_call_sites = total_calls
    virtual_call_sites = count(c -> c.num_targets > 1, call_sites)

    return DevirtualizationReport(call_sites, total_calls, devirt_calls, fname, total_call_sites, virtual_call_sites)
end

"""
    estimate_method_targets(func_name::Symbol, types::Tuple) -> Int

Estimate the number of potential method targets for a function call.
"""
function estimate_method_targets(func_name::Symbol, types::Tuple)
    # Conservative estimate
    # In a real implementation, we'd query the method table
    return 2  # Assume multiple possibilities
end

"""
    all_types_concrete(types::Tuple) -> Bool

Check if all types in the tuple are concrete (non-abstract).
"""
function all_types_concrete(types::Tuple)
    return all(T -> isconcretetype(T), types)
end

# Export the analysis function
export analyze_devirtualization, DevirtualizationReport, CallSiteInfo
