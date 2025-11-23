# Example 13: Package-Level Compilation
#
# This example demonstrates package-level compilation, which allows
# compiling entire modules/packages to shared libraries instead of
# individual functions.
#
# This is much more convenient for building complete libraries from
# Julia packages.

using StaticCompiler

println("="^70)
println("Example 13: Package-Level Compilation")
println("="^70)
println()

# ============================================================================
# Section 1: Creating a Simple Package/Module
# ============================================================================

println("Section 1: Defining a Module to Compile")
println("-"^70)
println()

# Define a simple math module
module SimpleMath
    export add, subtract, multiply, divide_int

    function add(a::Int, b::Int)
        return a + b
    end

    function subtract(a::Int, b::Int)
        return a - b
    end

    function multiply(a::Float64, b::Float64)
        return a * b
    end

    function divide_int(a::Int, b::Int)
        return div(a, b)
    end

    # Private function (not exported)
    function internal_helper(x::Int)
        return x * 2
    end
end

println("Module SimpleMath defined with 4 exported functions:")
println("  • add(Int, Int)")
println("  • subtract(Int, Int)")
println("  • multiply(Float64, Float64)")
println("  • divide_int(Int, Int)")
println()

# ============================================================================
# Section 2: Basic Package Compilation
# ============================================================================

println()
println("Section 2: Compiling the Entire Module")
println("-"^70)
println()

# Specify type signatures for each function
signatures = Dict(
    :add => [(Int, Int)],
    :subtract => [(Int, Int)],
    :multiply => [(Float64, Float64)],
    :divide_int => [(Int, Int)]
)

println("Compiling SimpleMath module...")
println()

output_dir1 = mktempdir()

try
    lib_path = compile_package(SimpleMath, signatures, output_dir1, "simplemath")

    println()
    println("Package compiled successfully!")
    println("   Library: $lib_path")
    println()

    # Check what was created
    header_path = joinpath(output_dir1, "simplemath.h")
    if isfile(header_path)
        println("Generated header file:")
        println(read(header_path, String))
    end
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 3: Function Naming and Namespaces
# ============================================================================

println()
println("Section 3: Understanding Function Naming")
println("-"^70)
println()

println("By default, compiled functions use the module name as a namespace:")
println()
println("  Julia: SimpleMath.add(a, b)")
println("  C:     simplemath_add(a, b)")
println()
println("This prevents name collisions when compiling multiple modules.")
println()

# Custom namespace
output_dir2 = mktempdir()

println("Example: Custom namespace")
try
    lib_path = compile_package(
        SimpleMath, signatures, output_dir2, "math",
        namespace = "mymath"
    )

    println()
    println("Compiled with custom namespace 'mymath'")
    println("   Functions: mymath_add, mymath_subtract, ...")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 4: Compiling Only Exported Functions
# ============================================================================

println()
println("Section 4: Compiling Only Exported Functions")
println("-"^70)
println()

println("The compile_package_exports() function automatically")
println("filters to only exported functions:")
println()

output_dir3 = mktempdir()

try
    # This will only compile exported functions
    lib_path = compile_package_exports(
        SimpleMath, signatures,
        output_dir3, "exports_only"
    )

    println("Compiled only exported functions")
    println("   (internal_helper was skipped)")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 5: Multiple Type Signatures
# ============================================================================

println()
println("Section 5: Multiple Signatures per Function")
println("-"^70)
println()

println("You can compile multiple type signatures for the same function:")
println()

# Module with polymorphic functions
module PolyMath
    export compute

    compute(x::Int) = x * 2
    compute(x::Float64) = x * 2.0
    compute(x::Int, y::Int) = x + y
end

# Compile all variants
poly_signatures = Dict(
    :compute => [
        (Int,),           # compute(Int)
        (Float64,),       # compute(Float64)
        (Int, Int),        # compute(Int, Int)
    ]
)

output_dir4 = mktempdir()

try
    lib_path = compile_package(
        PolyMath, poly_signatures,
        output_dir4, "polymath"
    )

    println("Compiled 3 variants of compute function")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 6: Using Templates with Package Compilation
# ============================================================================

println()
println("Section 6: Package Compilation with Templates")
println("-"^70)
println()

println("Templates work seamlessly with package compilation:")
println()

output_dir5 = mktempdir()

try
    lib_path = compile_package(
        SimpleMath, signatures,
        output_dir5, "simplemath_prod",
        template = :production
    )

    println("Compiled with :production template")
    println("   All functions verified with strict quality standards")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 7: Macro-Based Compilation
# ============================================================================

println()
println("Section 7: Using the @compile_package Macro")
println("-"^70)
println()

println("The @compile_package macro provides a convenient syntax:")
println()

# Note: This is demonstration syntax - may not run without proper module setup
println("Example syntax:")
println()
println(
    """
        @compile_package SimpleMath "./build" "simplemath" begin
            add => [(Int, Int)]
            subtract => [(Int, Int)]
            multiply => [(Float64, Float64)]
        end
    """
)
println()

# ============================================================================
# Section 8: Real-World Example - Statistics Module
# ============================================================================

println()
println("Section 8: Real-World Example - Statistics Module")
println("-"^70)
println()

module SimpleStats
    export mean, variance, std_dev

    function mean(data::Ptr{Float64}, n::Int)
        total = 0.0
        for i in 0:(n - 1)
            total += unsafe_load(data, i + 1)
        end
        return total / n
    end

    function variance(data::Ptr{Float64}, n::Int)
        m = mean(data, n)
        sum_sq = 0.0
        for i in 0:(n - 1)
            val = unsafe_load(data, i + 1)
            sum_sq += (val - m)^2
        end
        return sum_sq / n
    end

    function std_dev(data::Ptr{Float64}, n::Int)
        return sqrt(variance(data, n))
    end
end

stats_signatures = Dict(
    :mean => [(Ptr{Float64}, Int)],
    :variance => [(Ptr{Float64}, Int)],
    :std_dev => [(Ptr{Float64}, Int)]
)

output_dir6 = mktempdir()

println("Compiling SimpleStats module...")
try
    lib_path = compile_package(
        SimpleStats, stats_signatures,
        output_dir6, "stats",
        template = :performance,
        generate_header = true
    )

    println()
    println("Statistics library compiled!")
    println()

    # Show the generated header
    header_path = joinpath(output_dir6, "stats.h")
    if isfile(header_path)
        println("Generated C header (stats.h):")
        println("-"^70)
        println(read(header_path, String))
        println("-"^70)
    end
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 9: Comparison with Function-by-Function
# ============================================================================

println()
println("Section 9: Package vs. Function-by-Function Compilation")
println("-"^70)
println()

println("Function-by-Function (tedious):")
println(
    """
        compile_shlib(add, (Int, Int), "./", "add")
        compile_shlib(subtract, (Int, Int), "./", "subtract")
        compile_shlib(multiply, (Float64, Float64), "./", "multiply")
        compile_shlib(divide_int, (Int, Int), "./", "divide_int")
        # 4 separate libraries!
    """
)
println()

println("Package Compilation (convenient):")
println(
    """
        compile_package(SimpleMath, signatures, "./", "simplemath")
        # One library with all functions!
    """
)
println()

# ============================================================================
# Section 10: Best Practices
# ============================================================================

println()
println("Section 10: Best Practices for Package Compilation")
println("-"^70)
println()

println("1. Use meaningful module names")
println("   OK module MathOps")
println("   FAIL module M")
println()

println("2. Export only the public API")
println("   OK Keep internal helpers private")
println()

println("3. Use consistent type signatures")
println("   OK All Int or all Int64, not mixed")
println()

println("4. Document expected C usage")
println("   OK Add doc strings with C examples")
println()

println("5. Use templates for consistency")
println("   OK template=:production for releases")
println()

println("6. Choose meaningful library names")
println("   OK libmyproject_math.so")
println("   FAIL liblib.so")
println()

# ============================================================================
# Section 11: Workflow Example
# ============================================================================

println()
println("Section 11: Typical Development Workflow")
println("-"^70)
println()

println("Step 1: Develop your module in Julia")
println("  module MyLibrary")
println("      export func1, func2, func3")
println("      # ... implementation ...")
println("  end")
println()

println("Step 2: Define type signatures")
println("  signatures = Dict(")
println("      :func1 => [(Int,)],")
println("      :func2 => [(Float64, Float64)],")
println("      :func3 => [(Ptr{UInt8}, Int)]")
println("  )")
println()

println("Step 3: Compile for development")
println("  compile_package(MyLibrary, signatures, \"./\", \"mylib\",")
println("                  template=:debugging)")
println()

println("Step 4: Test from C/Julia")
println("  # Test the compiled library")
println()

println("Step 5: Compile for production")
println("  compile_package(MyLibrary, signatures, \"./dist\", \"mylib\",")
println("                  template=:production)")
println()

# ============================================================================
# Section 12: Integration with Build Systems
# ============================================================================

println()
println("Section 12: Build System Integration")
println("-"^70)
println()

println("Package compilation works well with build scripts:")
println()

build_script_example = """
# build.jl
using StaticCompiler

include(\"src/MyModule.jl\")

signatures = Dict(
    :func1 => [(Int,)],
    :func2 => [(Float64,)]
)

# Development build
if get(ENV, \"BUILD_TYPE\", \"dev\") == \"dev\"
    compile_package(MyModule, signatures, \"./build\", \"mylib\",
                    template=:debugging)
# Production build
else
    compile_package(MyModule, signatures, \"./dist\", \"mylib\",
                    template=:production)
end
"""

println(build_script_example)
println()

# ============================================================================
# Summary
# ============================================================================

println()
println("="^70)
println("SUMMARY")
println("="^70)
println()
println("Package-level compilation allows you to:")
println()
println("OK Compile entire modules/packages at once")
println("OK Avoid tedious function-by-function compilation")
println("OK Automatic namespace management")
println("OK Generate complete libraries with headers")
println("OK Use templates for consistent quality")
println("OK Create reusable components")
println()
println("Key functions:")
println("  compile_package(module, signatures, path, name)")
println("  compile_package_exports(module, signatures, path, name)")
println("  @compile_package macro")
println()
println("Naming:")
println("  Julia: MyModule.myfunc()")
println("  C:     mymodule_myfunc()")
println()
println("Use cases:")
println("  • Building Julia packages as C libraries")
println("  • Creating FFI interfaces")
println("  • Distributing reusable components")
println("  • Embedded system libraries")
println()
println("="^70)
