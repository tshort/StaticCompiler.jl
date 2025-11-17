# Compiler Analysis Guide

## Overview

StaticCompiler.jl provides five powerful analysis functions to help diagnose compilation issues and guide optimization efforts before attempting static compilation. These tools inspect Julia's typed intermediate representation (IR) to identify potential problems.

## The Five Analysis Functions

### 1. Escape Analysis (`analyze_escapes`)

**Purpose**: Identifies heap allocations and stack promotion opportunities.

**What it detects**:
- Allocations that escape to the heap
- Allocations that could be promoted to the stack
- Estimated memory savings from optimization

**Example**:
```julia
using StaticCompiler

function process_data(n::Int)
    temp = zeros(n)  # Heap allocation
    return sum(temp)
end

report = analyze_escapes(process_data, (Int,))
println("Total allocations: ", length(report.allocations))
println("Stack-promotable: ", report.promotable_allocations)
println("Potential savings: ", report.potential_savings_bytes, " bytes")
```

**Key fields**:
- `allocations`: Vector of all detected allocation sites
- `promotable_allocations`: Count of allocations that could move to stack
- `potential_savings_bytes`: Estimated memory savings

**Static compilation implications**: Heap allocations require Julia's GC and will fail in static compilation. Look for high counts of `allocations` that cannot be eliminated.

---

### 2. Monomorphization Analysis (`analyze_monomorphization`)

**Purpose**: Detects abstract types that need type specialization.

**What it detects**:
- Abstract type parameters in function signatures
- Type instability that prevents specialization
- Opportunities for concrete type instantiation

**Example**:
```julia
# Abstract type - won't compile statically
function process_abstract(x::Number)
    return x * 2
end

report = analyze_monomorphization(process_abstract, (Number,))
println("Has abstract types: ", report.has_abstract_types)
println("Can monomorphize: ", report.can_fully_monomorphize)
println("Specialization factor: ", report.specialization_factor)

# Concrete type - ready for static compilation
function process_concrete(x::Int)
    return x * 2
end

report2 = analyze_monomorphization(process_concrete, (Int,))
println("Has abstract types: ", report2.has_abstract_types)  # false
```

**Key fields**:
- `has_abstract_types`: Boolean indicating presence of abstract types
- `abstract_parameters`: Details about each abstract type parameter
- `optimization_opportunities`: Number of types needing specialization
- `can_fully_monomorphize`: Whether full specialization is possible
- `specialization_factor`: Ratio of concrete to total types (1.0 = fully concrete)

**Static compilation implications**: Abstract types require runtime type information and dynamic dispatch, which aren't available in static compilation. Aim for `has_abstract_types = false`.

---

### 3. Devirtualization Analysis (`analyze_devirtualization`)

**Purpose**: Finds dynamic dispatch sites that could be optimized.

**What it detects**:
- Virtual method calls (runtime dispatch)
- Calls that could be resolved at compile time
- Polymorphic call sites

**Example**:
```julia
abstract type Shape end
struct Circle <: Shape
    radius::Float64
end

area(c::Circle) = 3.14159 * c.radius^2

function process_shape(s::Shape)
    return area(s)  # Dynamic dispatch
end

report = analyze_devirtualization(process_shape, (Circle,))
println("Total dynamic calls: ", report.total_dynamic_calls)
println("Devirtualizable: ", report.devirtualizable_calls)
println("Call sites: ", length(report.call_sites))
```

**Key fields**:
- `call_sites`: Vector of all dynamic call sites
- `total_dynamic_calls`: Count of runtime-dispatched calls
- `devirtualizable_calls`: Calls that could be statically resolved
- `total_call_sites`: Total number of call sites analyzed
- `virtual_call_sites`: Count of polymorphic calls

**Static compilation implications**: Dynamic dispatch requires Julia's runtime method table. High `total_dynamic_calls` indicates functions that may not compile statically.

---

### 4. Constant Propagation Analysis (`analyze_constants`)

**Purpose**: Identifies constant folding and dead code elimination opportunities.

**What it detects**:
- Expressions that can be evaluated at compile time
- Constants that could be folded
- Dead code that could be eliminated

**Example**:
```julia
function compute(x::Int)
    a = 2 + 3      # Constant expression
    b = x * a       # Mix of constant and variable
    c = 100 / 10   # Another constant
    return b + c
end

report = analyze_constants(compute, (Int,))
println("Constants found: ", length(report.constants_found))
println("Foldable expressions: ", report.foldable_expressions)
println("Code reduction: ", report.code_reduction_potential_pct, "%")
```

**Key fields**:
- `constants_found`: Vector of compile-time constants
- `foldable_expressions`: Count of expressions that could be pre-computed
- `constant_locations`: Source locations of constants
- `code_reduction_potential_pct`: Estimated code size reduction

**Static compilation implications**: Better constant propagation leads to smaller, faster code. High reduction potential suggests optimization opportunities.

---

### 5. Lifetime Analysis (`analyze_lifetimes`)

**Purpose**: Tracks memory allocation lifetimes and detects potential leaks.

**What it detects**:
- Manual memory allocations (malloc)
- Allocations without corresponding frees
- Potential double-free errors
- Proper allocation/deallocation pairs

**Example**:
```julia
using StaticTools

function process_with_malloc(n::Int)
    arr = MallocArray{Int}(undef, n)  # Manual allocation
    # ... use arr ...
    # Missing: free(arr)
    return 0
end

report = analyze_lifetimes(process_with_malloc, (Int,))
println("Allocations: ", length(report.allocations))
println("Potential leaks: ", report.potential_leaks)
println("Properly freed: ", report.proper_frees)
println("Allocations freed: ", report.allocations_freed)
```

**Key fields**:
- `allocations`: Vector of all malloc/allocation sites
- `potential_leaks`: Allocations without matching frees
- `potential_double_frees`: Frees without matching allocations
- `proper_frees`: Correctly paired allocations/frees
- `allocations_freed`: Count of allocations with proper cleanup

**Static compilation implications**: Manual memory management is required in static compilation. Ensure `potential_leaks = 0` and all allocations are properly freed.

---

## Typical Workflow

### Step 1: Initial Analysis

Run all five analyses on your function:

```julia
using StaticCompiler

function my_function(x::Int)
    # Your code here
end

println("=== Escape Analysis ===")
ea = analyze_escapes(my_function, (Int,))
println("Allocations: ", length(ea.allocations))

println("\n=== Monomorphization ===")
ma = analyze_monomorphization(my_function, (Int,))
println("Abstract types: ", ma.has_abstract_types)

println("\n=== Devirtualization ===")
da = analyze_devirtualization(my_function, (Int,))
println("Dynamic calls: ", da.total_dynamic_calls)

println("\n=== Constant Propagation ===")
ca = analyze_constants(my_function, (Int,))
println("Foldable expressions: ", ca.foldable_expressions)

println("\n=== Lifetime Analysis ===")
la = analyze_lifetimes(my_function, (Int,))
println("Potential leaks: ", la.potential_leaks)
```

### Step 2: Identify Blockers

Check for issues that will prevent static compilation:

1. **Abstract types** (`ma.has_abstract_types = true`)
   - Replace with concrete types
   - Add type parameters and instantiate explicitly

2. **Heap allocations** (`length(ea.allocations) > 0`)
   - Use StaticArrays for small, fixed-size arrays
   - Use MallocArray for dynamic allocations
   - Avoid standard Julia Arrays

3. **Dynamic dispatch** (`da.total_dynamic_calls > 0`)
   - Use concrete types instead of abstract types
   - Add type annotations to eliminate ambiguity

4. **Memory leaks** (`la.potential_leaks > 0`)
   - Add `free()` calls for all `malloc()` allocations
   - Use Bumper.jl for automatic arena allocation

### Step 3: Iterate and Optimize

After making changes, re-run analyses to verify improvements:

```julia
# After modifications
ea2 = analyze_escapes(my_function, (Int,))
println("Allocations reduced: ", length(ea.allocations) - length(ea2.allocations))

ma2 = analyze_monomorphization(my_function, (Int,))
println("Now concrete: ", !ma2.has_abstract_types)
```

### Step 4: Attempt Compilation

Once all analyses show good results:

```julia
compile_shlib(my_function, (Int,), "./", "my_function")
```

---

## Common Patterns and Solutions

### Pattern 1: Abstract Type Parameters

**Problem**:
```julia
function process(x::Number)  # Abstract!
    return x * 2
end
```

**Solution**:
```julia
function process(x::T) where {T<:Number}  # Parameterized
    return x * 2
end

# Or use concrete type directly:
function process(x::Int)
    return x * 2
end
```

### Pattern 2: Array Allocations

**Problem**:
```julia
function compute(n::Int)
    result = zeros(n)  # Heap allocation!
    return sum(result)
end
```

**Solution A** (Fixed size):
```julia
using StaticArrays

function compute()
    result = @SVector zeros(10)  # Stack allocated
    return sum(result)
end
```

**Solution B** (Dynamic size):
```julia
using StaticTools

function compute(n::Int)
    result = MallocArray{Float64}(undef, n)  # Manual management
    # ... compute ...
    s = sum(result)
    free(result)  # Important!
    return s
end
```

### Pattern 3: String Operations

**Problem**:
```julia
function greet(name::String)  # Julia String allocates!
    return "Hello, " * name
end
```

**Solution**:
```julia
using StaticTools

function greet()
    return println(c"Hello, World!")  # Static string
end
```

### Pattern 4: Dynamic Dispatch

**Problem**:
```julia
abstract type Animal end
struct Dog <: Animal end

function speak(a::Animal)  # Will dispatch dynamically
    bark(a)
end
```

**Solution**:
```julia
# Use concrete types directly
function speak(d::Dog)
    bark(d)
end

# Or use @device_override for compile-time dispatch
```

---

## Best Practices

1. **Run analyses early and often** - Catch issues before spending time on complex refactoring

2. **Focus on the biggest issues first**:
   - Abstract types (prevents compilation entirely)
   - Heap allocations (causes runtime failures)
   - Memory leaks (causes crashes)
   - Dynamic dispatch (performance issues)

3. **Use specialized tools**:
   - `Cthulhu.jl` for deep IR inspection
   - `@code_warntype` for type stability
   - StaticCompiler analyses for compilation readiness

4. **Document assumptions**: If your code requires specific type constraints for static compilation, document them clearly

5. **Test incrementally**: Compile and test small functions before moving to complex ones

---

## Interpreting Results

### Good Static Compilation Candidates

```
✅ analyze_monomorphization: has_abstract_types = false
✅ analyze_escapes: allocations = [] or all promotable
✅ analyze_devirtualization: total_dynamic_calls = 0
✅ analyze_lifetimes: potential_leaks = 0
✅ analyze_constants: high code_reduction_potential_pct (optional)
```

### Warning Signs

```
⚠️  Abstract types present
⚠️  Multiple heap allocations
⚠️  High dynamic call count
⚠️  Memory leaks detected
```

### Blockers

```
🛑 has_abstract_types = true AND can_fully_monomorphize = false
🛑 Heap allocations with no stack promotion path
🛑 Unmatched malloc/free pairs
```

---

## Advanced Usage

### Batch Analysis

Analyze multiple functions at once:

```julia
functions_to_check = [
    (func1, (Int,)),
    (func2, (Float64,)),
    (func3, (Int, Int))
]

for (f, types) in functions_to_check
    println("\nAnalyzing $(nameof(f))...")
    ma = analyze_monomorphization(f, types)
    if ma.has_abstract_types
        println("  ⚠️  Abstract types detected")
    else
        println("  ✅ Ready for compilation")
    end
end
```

### Custom Reporting

Create custom reports combining multiple analyses:

```julia
function compilation_readiness_report(f, types)
    ma = analyze_monomorphization(f, types)
    ea = analyze_escapes(f, types)
    da = analyze_devirtualization(f, types)
    la = analyze_lifetimes(f, types)
    
    score = 0
    score += ma.has_abstract_types ? 0 : 25
    score += length(ea.allocations) == 0 ? 25 : 0
    score += da.total_dynamic_calls == 0 ? 25 : 0
    score += la.potential_leaks == 0 ? 25 : 0
    
    return (
        ready = score == 100,
        score = score,
        issues = [
            ma.has_abstract_types && "Abstract types",
            length(ea.allocations) > 0 && "Heap allocations",
            da.total_dynamic_calls > 0 && "Dynamic dispatch",
            la.potential_leaks > 0 && "Memory leaks"
        ] |> filter(!isnothing)
    )
end
```

---

## Troubleshooting

### "My function passes all analyses but still won't compile"

- Check dependencies: Do called functions also pass analysis?
- Look for hidden global variables
- Verify all types are truly concrete (use `isconcretetype()`)

### "Analysis shows no issues but runtime fails"

- Memory leaks may not cause immediate failure
- Check for use-after-free with valgrind
- Verify pointer arithmetic is correct

### "Too many false positives in analysis"

- Analyses are conservative and may flag safe code
- Use `@device_override` for known-safe patterns
- Consider manual review of flagged code

---

## Additional Resources

- [StaticCompiler.jl README](../../README.md) - Main documentation
- [StaticTools.jl](https://github.com/brenhinkeller/StaticTools.jl) - Essential tools for static compilation
- [Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl) - IR introspection
- [GPUCompiler.jl](https://github.com/JuliaGPU/GPUCompiler.jl) - Underlying compilation framework
