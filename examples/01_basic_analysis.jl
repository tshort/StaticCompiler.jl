# Example 1: Basic Compiler Analysis
# This example shows how to use the compiler analysis tools to diagnose issues

using StaticCompiler

println("="^70)
println("BASIC COMPILER ANALYSIS EXAMPLE")
println("="^70)
println()

# Example 1: Function with abstract types (won't compile)
println("Example 1: Abstract Type Detection")
println("-"^70)

function process_number(x::Number)  # Abstract type!
    return x * 2 + 1
end

report = analyze_monomorphization(process_number, (Number,))
println("Has abstract types: ", report.has_abstract_types)
println("Can monomorphize: ", report.can_fully_monomorphize)
println("Abstract parameters found: ", length(report.abstract_parameters))
for param in report.abstract_parameters
    println("  - Parameter $(param.position): $(param.type)")
end
println()

# Example 2: Function with heap allocation (won't compile)
println("Example 2: Heap Allocation Detection")
println("-"^70)

function sum_array(n::Int)
    arr = zeros(n)  # Heap allocation!
    return sum(arr)
end

report = analyze_escapes(sum_array, (Int,))
println("Total allocations: ", length(report.allocations))
println("Promotable to stack: ", report.promotable_allocations)
println("Potential savings: ", report.potential_savings_bytes, " bytes")
for alloc in report.allocations
    println("  - $(alloc.location): escapes=$(alloc.escapes), can_promote=$(alloc.can_promote)")
end
println()

# Example 3: Function with dynamic dispatch (performance issue)
println("Example 3: Dynamic Dispatch Detection")
println("-"^70)

abstract type Shape end
struct Circle <: Shape
    radius::Float64
end

area(c::Circle) = 3.14159 * c.radius^2

function process_shape(s::Shape)
    return area(s)
end

report = analyze_devirtualization(process_shape, (Circle,))
println("Total dynamic calls: ", report.total_dynamic_calls)
println("Devirtualizable calls: ", report.devirtualizable_calls)
println("Call sites: ", length(report.call_sites))
println()

# Example 4: Function ready for static compilation
println("Example 4: Ready for Static Compilation ✓")
println("-"^70)

function compute_fast(x::Int, y::Int)
    return x * y + x - y
end

ma = analyze_monomorphization(compute_fast, (Int, Int))
ea = analyze_escapes(compute_fast, (Int, Int))
da = analyze_devirtualization(compute_fast, (Int, Int))

println("✓ Abstract types: ", !ma.has_abstract_types)
println("✓ Allocations: ", length(ea.allocations))
println("✓ Dynamic calls: ", da.total_dynamic_calls)
println()
println("This function is ready for static compilation!")
println()

println("="^70)
println("To compile the ready function:")
println("  compile_shlib(compute_fast, (Int, Int), \"./\", \"compute_fast\")")
println("="^70)
