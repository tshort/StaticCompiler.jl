# Example 11: Automatic C Header Generation
#
# This example demonstrates the automatic C header generation feature that
# makes compiled Julia functions immediately usable from C, C++, and Rust.
#
# With generate_header=true, StaticCompiler automatically creates a .h file
# containing proper C function declarations for all compiled functions.

using StaticCompiler

println("="^70)
println("Example 11: Automatic C Header Generation")
println("="^70)
println()

# ============================================================================
# Section 1: Basic Header Generation
# ============================================================================

println("Section 1: Basic Header Generation")
println("-"^70)
println()

# A simple function to compile
function add_numbers(a::Int, b::Int)
    return a + b
end

println("Example 1a: Compiling with header generation")
println()

output_dir = mktempdir()
try
    lib_path = compile_shlib(add_numbers, (Int, Int), output_dir, "add",
                             generate_header=true)

    println("Library compiled: $lib_path")
    println()

    # Read and display the generated header
    header_path = joinpath(output_dir, "add.h")
    if isfile(header_path)
        println("Generated header content:")
        println("="^70)
        println(read(header_path, String))
        println("="^70)
    end
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 2: Multiple Functions with Different Types
# ============================================================================

println()
println("Section 2: Multiple Functions with Different Types")
println("-"^70)
println()

# Various functions with different type signatures

function add_int(a::Int, b::Int)
    return a + b
end

function multiply_float(a::Float64, b::Float64)
    return a * b
end

function compute_square(x::Float32)
    return x * x
end

function is_positive(x::Int)
    return x > 0
end

# Note: This would need Ptr{UInt8} to compile successfully
# For demonstration, we'll show what the header would look like
function process_pointer(ptr::Ptr{Float64})
    return unsafe_load(ptr)
end

println("Example 2a: Batch compilation with header generation")
println()

output_dir2 = mktempdir()

# Functions that will compile successfully
functions = [
    (add_int, (Int, Int)),
    (multiply_float, (Float64, Float64)),
    (compute_square, (Float32,)),
    (is_positive, (Int,))
]

try
    lib_path = compile_shlib(functions, output_dir2,
                             filename="mathlib",
                             generate_header=true)

    println("Library compiled: $lib_path")
    println()

    # Display the generated header
    header_path = joinpath(output_dir2, "mathlib.h")
    if isfile(header_path)
        println("Generated header for multiple functions:")
        println("="^70)
        println(read(header_path, String))
        println("="^70)
    end
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 3: Type Mapping Reference
# ============================================================================

println()
println("Section 3: Julia to C Type Mapping")
println("-"^70)
println()

println("Julia Type          | C Type")
println("-"*19 * "|" * "-"*20)
println("Int8                | int8_t")
println("Int16               | int16_t")
println("Int32               | int32_t")
println("Int64               | int64_t")
println("UInt8               | uint8_t")
println("UInt16              | uint16_t")
println("UInt32              | uint32_t")
println("UInt64              | uint64_t")
println("Float32             | float")
println("Float64             | double")
println("Bool                | bool")
println("Ptr{T}              | T*")
println("Nothing/Cvoid       | void")
println()

# ============================================================================
# Section 4: Using Generated Headers from C
# ============================================================================

println()
println("Section 4: Using Generated Headers from C")
println("-"^70)
println()

println("Once you have generated a header, you can use it from C/C++:")
println()

c_example = """
// example.c
#include <stdio.h>
#include "mathlib.h"  // Generated header

int main() {
    // Call Julia functions from C
    int64_t sum = add_int(10, 20);
    printf("10 + 20 = %ld\\n", sum);

    double product = multiply_float(3.14, 2.0);
    printf("3.14 * 2.0 = %f\\n", product);

    float square = compute_square(5.0f);
    printf("5.0^2 = %f\\n", square);

    bool is_pos = is_positive(-5);
    printf("-5 is positive: %d\\n", is_pos);

    return 0;
}
"""

println(c_example)
println()

println("Compile and link:")
println("  gcc example.c -L. -lmathlib -o example")
println("  ./example")
println()

# ============================================================================
# Section 5: C++ Compatibility
# ============================================================================

println()
println("Section 5: C++ Compatibility")
println("-"^70)
println()

println("The generated headers include extern \"C\" wrappers,")
println("making them compatible with C++ code:")
println()

cpp_example = """
// example.cpp
#include <iostream>
#include "mathlib.h"  // Works in C++ too!

int main() {
    int64_t result = add_int(42, 58);
    std::cout << "42 + 58 = " << result << std::endl;

    return 0;
}
"""

println(cpp_example)
println()

println("Compile with C++:")
println("  g++ example.cpp -L. -lmathlib -o example")
println("  ./example")
println()

# ============================================================================
# Section 6: Rust FFI Compatibility
# ============================================================================

println()
println("Section 6: Rust FFI Compatibility")
println("-"^70)
println()

println("You can also call Julia functions from Rust using the generated types:")
println()

rust_example = """
// lib.rs
extern "C" {
    fn add_int(a: i64, b: i64) -> i64;
    fn multiply_float(a: f64, b: f64) -> f64;
    fn compute_square(x: f32) -> f32;
    fn is_positive(x: i64) -> bool;
}

fn main() {
    unsafe {
        let sum = add_int(10, 20);
        println!("10 + 20 = {}", sum);

        let product = multiply_float(3.14, 2.0);
        println!("3.14 * 2.0 = {}", product);

        let square = compute_square(5.0);
        println!("5.0^2 = {}", square);

        let is_pos = is_positive(-5);
        println!("-5 is positive: {}", is_pos);
    }
}
"""

println(rust_example)
println()

# ============================================================================
# Section 7: Combined with Verification
# ============================================================================

println()
println("Section 7: Combined with Verification")
println("-"^70)
println()

println("You can use header generation together with verification:")
println()

function fast_multiply(a::Int, b::Int)
    return a * b
end

output_dir3 = mktempdir()

try
    lib_path = compile_shlib(fast_multiply, (Int, Int), output_dir3, "fast",
                             verify=true,          # Verify code quality
                             min_score=80,
                             generate_header=true) # Generate header

    println("Function verified and compiled with header")
    println()

    header_path = joinpath(output_dir3, "fast.h")
    if isfile(header_path)
        println("Generated header:")
        println(read(header_path, String))
    end
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 8: Function Name Mangling
# ============================================================================

println()
println("Section 8: Function Name Mangling")
println("-"^70)
println()

println("By default, demangle=true removes the 'julia_' prefix.")
println("Set demangle=false to keep it:")
println()

output_dir4 = mktempdir()

function my_function(x::Int)
    return x * 2
end

try
    # With demangle=true (default)
    lib1 = compile_shlib(my_function, (Int,), output_dir4, "demangled",
                         filename="demangled",
                         demangle=true,
                         generate_header=true)

    header1 = joinpath(output_dir4, "demangled.h")
    if isfile(header1)
        content1 = read(header1, String)
        println("With demangle=true:")
        for line in split(content1, "\n")
            if contains(line, "my_function")
                println("  $line")
            end
        end
    end
    println()

    # With demangle=false
    lib2 = compile_shlib(my_function, (Int,), output_dir4, "mangled",
                         filename="mangled",
                         demangle=false,
                         generate_header=true)

    header2 = joinpath(output_dir4, "mangled.h")
    if isfile(header2)
        content2 = read(header2, String)
        println("With demangle=false:")
        for line in split(content2, "\n")
            if contains(line, "julia_my_function") || contains(line, "my_function")
                println("  $line")
            end
        end
    end
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 9: Programmatic Header Generation
# ============================================================================

println()
println("Section 9: Programmatic Header Generation")
println("-"^70)
println()

println("You can also generate headers programmatically:")
println()

# Example of using the API directly
funcs_for_header = [
    (add_int, (Int, Int)),
    (multiply_float, (Float64, Float64))
]

output_dir5 = mktempdir()

try
    # First compile
    lib_path = compile_shlib(funcs_for_header, output_dir5,
                             filename="mylib",
                             generate_header=false)  # Don't auto-generate

    # Then generate header manually with custom options
    header_path = generate_c_header(funcs_for_header, output_dir5, "mylib",
                                    demangle=true,
                                    include_extern_c=true,
                                    verbose=true)

    println()
    println("Manually generated header: $header_path")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Summary
# ============================================================================

println()
println("="^70)
println("SUMMARY")
println("="^70)
println()
println("C Header Generation makes Julia functions accessible from:")
println("  OK C")
println("  OK C++")
println("  OK Rust")
println("  OK Any language with C FFI")
println()
println("Key features:")
println("  • Automatic type mapping (Julia → C)")
println("  • Include guards and proper headers")
println("  • extern \"C\" for C++ compatibility")
println("  • Works with single or multiple functions")
println("  • Respects demangle setting")
println("  • Combines with verification")
println()
println("Usage:")
println("  compile_shlib(func, types, path, name, generate_header=true)")
println()
println("Supported types:")
println("  • Integers: Int8, Int16, Int32, Int64 (+ unsigned)")
println("  • Floats: Float32, Float64")
println("  • Bool")
println("  • Pointers: Ptr{T}")
println()
println("="^70)
