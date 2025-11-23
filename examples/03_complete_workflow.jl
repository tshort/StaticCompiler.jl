# Example 3: Complete Static Compilation Workflow
# This example shows the full process from analysis to compilation

using StaticCompiler
using StaticTools

println("="^70)
println("COMPLETE STATIC COMPILATION WORKFLOW")
println("="^70)
println()

# Step 1: Start with a function you want to compile
println("STEP 1: Initial Function")
println("-"^70)

function fibonacci(n::Int)
    if n <= 1
        return n
    end
    return fibonacci(n - 1) + fibonacci(n - 2)
end

println("Target function: fibonacci(n::Int)")
println()

# Step 2: Run all analyses
println("STEP 2: Analyze the Function")
println("-"^70)

println("Running analyses...")
ma = analyze_monomorphization(fibonacci, (Int,))
ea = analyze_escapes(fibonacci, (Int,))
da = analyze_devirtualization(fibonacci, (Int,))
ca = analyze_constants(fibonacci, (Int,))
la = analyze_lifetimes(fibonacci, (Int,))

# Check results
println("\nAnalysis Results:")
println("  Monomorphization:")
println("    OK Abstract types: ", ma.has_abstract_types ? "YES" : "NO")
println("    OK Specialization factor: ", round(ma.specialization_factor, digits = 2))

println("  Escape Analysis:")
println("    OK Allocations: ", length(ea.allocations) == 0 ? "None" : "$(length(ea.allocations))")

println("  Devirtualization:")
println("    OK Dynamic calls: ", da.total_dynamic_calls == 0 ? "None" : " $(da.total_dynamic_calls)")

println("  Lifetime:")
println("    OK Memory leaks: ", la.potential_leaks == 0 ? "None" : "$(la.potential_leaks)")

# Determine if ready
ready = !ma.has_abstract_types &&
    length(ea.allocations) == 0 &&
    la.potential_leaks == 0

println("\nCompilation Readiness: ", ready ? "READY" : "NOT READY")
println()

if ready
    # Step 3: Compile to shared library
    println("STEP 3: Compile to Shared Library")
    println("-"^70)

    try
        path = compile_shlib(fibonacci, (Int,), tempdir(), "fibonacci")
        println("Compilation successful!")
        println("   Library: $path")
        println()

        # Step 4: Test the compiled function
        println("STEP 4: Test Compiled Function")
        println("-"^70)

        # Load and call
        using Libdl
        lib = dlopen(path)
        fib_ptr = dlsym(lib, "fibonacci")

        println("Testing fibonacci(10)...")
        result_julia = fibonacci(10)
        result_compiled = @ccall $fib_ptr(10::Int)::Int

        println("  Julia result:    $result_julia")
        println("  Compiled result: $result_compiled")
        println("  Match: ", result_julia == result_compiled ? "YES" : "NO")
        println()

        # Cleanup
        dlclose(lib)
        rm(path, force = true)

    catch e
        println("Compilation failed:")
        println("   ", e)
        println()
    end
else
    println("STEP 3: Fix Issues")
    println("-"^70)
    println("Before compiling, you need to address:")

    if ma.has_abstract_types
        println("  Abstract types - use concrete types")
    end

    if length(ea.allocations) > 0
        println("  Heap allocations - use stack or manual memory")
    end

    if la.potential_leaks > 0
        println("  Memory leaks - add free() calls")
    end
    println()
end

# Advanced example: With manual memory management
println("="^70)
println("ADVANCED: Function with Manual Memory")
println("="^70)
println()

function sum_squares_manual(n::Int)
    # Allocate array manually
    arr = MallocArray{Int}(undef, n)

    # Fill with squares
    for i in 1:n
        arr[i] = i * i
    end

    # Compute sum
    result = 0
    for i in 1:n
        result += arr[i]
    end

    # Free memory
    free(arr)

    return result
end

println("Analyzing sum_squares_manual...")
ma = analyze_monomorphization(sum_squares_manual, (Int,))
ea = analyze_escapes(sum_squares_manual, (Int,))
la = analyze_lifetimes(sum_squares_manual, (Int,))

println("  Abstract types: ", !ma.has_abstract_types ? "NO" : "YES")
println("  Heap allocations: ", length(ea.allocations))
println("  Memory leaks: ", la.potential_leaks == 0 ? "None" : "$(la.potential_leaks)")
println()

if !ma.has_abstract_types && la.potential_leaks == 0
    println("This function is ready for static compilation!")
    println("   (despite using manual memory management)")
    println()

    try
        path = compile_shlib(sum_squares_manual, (Int,), tempdir(), "sum_squares")
        println("Compilation successful!")
        println("   Library: $path")

        # Test it
        using Libdl
        lib = dlopen(path)
        func_ptr = dlsym(lib, "sum_squares_manual")

        result_julia = sum_squares_manual(10)
        result_compiled = @ccall $func_ptr(10::Int)::Int

        println("\nTesting sum_squares_manual(10):")
        println("  Julia result:    $result_julia")
        println("  Compiled result: $result_compiled")
        println("  Match: ", result_julia == result_compiled ? "YES" : "NO")

        dlclose(lib)
        rm(path, force = true)
    catch e
        println("Error: ", e)
    end
end

println()
println("="^70)
println("WORKFLOW SUMMARY")
println("="^70)
println("1. Write your function with concrete types")
println("2. Run compiler analyses to check readiness")
println("3. Fix any issues identified by analyses")
println("4. Compile to shared library or executable")
println("5. Test the compiled function")
println("="^70)
