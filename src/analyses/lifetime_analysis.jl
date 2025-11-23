# Lifetime Analysis
# Analyzes manual memory management (malloc/free) for correctness

"""
    AllocationSite

Information about a manual allocation site.
"""
struct AllocationSite
    location::String
    type::Symbol  # :malloc, :calloc, etc.
    freed::Bool
    potential_leak::Bool
    potential_double_free::Bool
end

"""
    LifetimeAnalysisReport

Report from lifetime analysis showing manual memory management issues.
"""
struct LifetimeAnalysisReport
    allocations::Vector{AllocationSite}
    potential_leaks::Int
    potential_double_frees::Int
    proper_frees::Int
    function_name::Symbol
    allocations_freed::Int
end

"""
    analyze_lifetimes(f::Function, types::Tuple)

Analyze manual memory management in function `f` with argument types `types`.
Detects potential memory leaks and double-frees.

Returns a `LifetimeAnalysisReport` containing:
- `allocations`: Vector of allocation sites
- `potential_leaks`: Count of allocations that might not be freed
- `potential_double_frees`: Count of potential double-free issues
- `proper_frees`: Count of properly managed allocations
- `function_name`: Name of analyzed function

# Example
```julia
using StaticTools

function process(n::Int)
    arr = MallocArray{Float64}(n)
    result = sum(arr)
    free(arr)
    return result
end

report = analyze_lifetimes(process, (Int,))
println("Potential leaks: \$(report.potential_leaks)")
println("Proper frees: \$(report.proper_frees)")
```
"""
function resolve_ir_value(ir, value)
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

function analyze_lifetimes(f::Function, types::Tuple)
    fname = nameof(f)
    allocations = AllocationSite[]
    leak_count = 0
    double_free_count = 0
    proper_count = 0

    try
        # Get typed IR
        typed_code = code_typed(f, types, optimize = false)

        if !isempty(typed_code)
            ir, return_type = first(typed_code)

            # Track allocation -> free pairs
            allocation_vars = Dict{Any, Int}()  # var => allocation_index
            freed_vars = Set{Any}()

            # Also track previous statement to detect constructor patterns
            prev_stmt = nothing

            for (idx, stmt) in enumerate(ir.code)
                # Detect MallocArray-like type constructors
                # Pattern: Core.apply_type(MallocArray, T) followed by constructor call
                if isa(stmt, Expr) && stmt.head == :call
                    if length(stmt.args) >= 2 && stmt.args[1] == GlobalRef(Core, :apply_type)
                        # Check if it's MallocArray or similar
                        if length(stmt.args) >= 2
                            type_arg = resolve_ir_value(ir, stmt.args[2])
                            if isa(type_arg, GlobalRef) && occursin("Malloc", string(type_arg.name))
                                prev_stmt = idx  # Remember this for next iteration
                            end
                        end
                    end
                end

                # Check if current statement might be calling the type from prev_stmt
                if !isnothing(prev_stmt) && isa(stmt, Expr) && idx != prev_stmt
                    alloc_idx = length(allocations) + 1
                    allocation_vars[idx] = alloc_idx
                    allocation_vars[Core.SSAValue(idx)] = alloc_idx
                    if length(stmt.args) >= 1 && stmt.args[1] isa Core.SlotNumber
                        allocation_vars[stmt.args[1]] = alloc_idx
                    end

                    # Constructor call - record as allocation
                    alloc_site = AllocationSite(
                        "line $idx",
                        :malloc_array,
                        false,  # Not freed yet
                        true,   # Assume leak until proven otherwise
                        false   # No double free
                    )
                    push!(allocations, alloc_site)
                    leak_count += 1
                    prev_stmt = nothing  # Reset
                end

                if isa(stmt, Expr) && stmt.head == :call && length(stmt.args) >= 1
                    func = stmt.args[1]

                    # Check for allocation functions
                    if is_allocation_call(func)
                        alloc_idx = length(allocations) + 1

                        # Record allocation
                        # The result is assigned to the SSA value at this index
                        allocation_vars[idx] = alloc_idx
                        allocation_vars[Core.SSAValue(idx)] = alloc_idx

                        alloc_site = AllocationSite(
                            "line $idx",
                            get_allocation_type(func),
                            false,  # Not freed yet
                            true,   # Assume leak until proven otherwise
                            false   # No double free
                        )
                        push!(allocations, alloc_site)
                        leak_count += 1
                    end

                    # Check for free calls
                    if is_free_call(func) && length(stmt.args) >= 2
                        freed_var = stmt.args[2]

                        # Try to trace back to allocation
                        if haskey(allocation_vars, freed_var)
                            alloc_idx = allocation_vars[freed_var]

                            if freed_var in freed_vars
                                # Potential double free!
                                allocations[alloc_idx] = AllocationSite(
                                    allocations[alloc_idx].location,
                                    allocations[alloc_idx].type,
                                    true,
                                    false,
                                    true  # Double free detected
                                )
                                double_free_count += 1
                            else
                                # Proper free
                                allocations[alloc_idx] = AllocationSite(
                                    allocations[alloc_idx].location,
                                    allocations[alloc_idx].type,
                                    true,   # Freed
                                    false,  # No leak
                                    false   # No double free
                                )
                                leak_count -= 1
                                proper_count += 1
                                push!(freed_vars, freed_var)
                            end
                        end
                    end
                end
            end
        end

    catch e
        @debug "Lifetime analysis failed for $fname" exception = e
    end

    return LifetimeAnalysisReport(
        allocations,
        max(0, leak_count),
        double_free_count,
        proper_count,
        fname,
        proper_count  # allocations_freed is same as proper_frees
    )
end

"""
    is_allocation_call(func) -> Bool

Check if a function call is a memory allocation.
"""
function is_allocation_call(func)
    if isa(func, GlobalRef)
        fname = func.name
        return fname in (:malloc, :calloc, :MallocArray, :MallocVector, :MallocMatrix)
    end

    # Check for type constructors (MallocArray{T})
    if isa(func, Type)
        type_name = string(func)
        return occursin("Malloc", type_name)
    end

    return false
end

"""
    is_free_call(func) -> Bool

Check if a function call is a memory free.
"""
function is_free_call(func)
    if isa(func, GlobalRef)
        fname = func.name
        return fname in (:free, :free!, :c_free, :libc_free)
    end
    return false
end

"""
    get_allocation_type(func) -> Symbol

Get the type of allocation from the function.
"""
function get_allocation_type(func)
    if isa(func, GlobalRef)
        return func.name
    elseif isa(func, Type)
        return :malloc_array
    else
        return :unknown
    end
end

"""
    suggest_lifetime_improvements(report::LifetimeAnalysisReport)

Suggest improvements for lifetime management based on analysis report.
Returns a vector of suggestions (strings).
"""
function suggest_lifetime_improvements(report::LifetimeAnalysisReport)
    suggestions = String[]

    # Check for allocations without corresponding frees
    for alloc in report.allocations
        if !alloc.freed
            push!(suggestions, "Add free() for allocation at $(alloc.location)")
        end
    end

    return suggestions
end

"""
    insert_auto_frees(report::LifetimeAnalysisReport)

Generate automatic free insertions based on lifetime analysis.
Returns a vector of suggested free insertion points.
"""
function insert_auto_frees(report::LifetimeAnalysisReport)
    auto_frees = []

    # Find allocations that need frees (not freed and potential leak)
    for alloc in report.allocations
        if !alloc.freed && alloc.potential_leak
            push!(auto_frees, (location = alloc.location, type = alloc.type))
        end
    end

    return auto_frees
end

# Export the analysis function
export analyze_lifetimes, LifetimeAnalysisReport, AllocationSite
export suggest_lifetime_improvements, insert_auto_frees
