# Automatic C Header Generation

## Overview

StaticCompiler.jl can automatically generate C header files (`.h`) for your compiled Julia functions, making them immediately usable from C, C++, Rust, and any other language with C FFI support.

## Quick Start

```julia
using StaticCompiler

function add(a::Int, b::Int)
    return a + b
end

# Compile with automatic header generation
compile_shlib(add, (Int, Int), "./", "add", generate_header=true)
```

This creates two files:
- `add.so` (or `add.dylib` on macOS): The compiled library
- `add.h`: The C header file

The generated `add.h` contains:
```c
#ifndef ADD_H
#define ADD_H

/* Required includes */
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Function declarations */
int64_t add(int64_t arg0, int64_t arg1);

#ifdef __cplusplus
}
#endif

#endif /* ADD_H */
```

## Why Use Header Generation?

### Problem

After compiling Julia code to a shared library, using it from other languages requires:
1. Manually determining the C function signature
2. Writing the header file by hand
3. Keeping the header in sync with the Julia code
4. Remembering the correct C types for each Julia type

This is error-prone and time-consuming.

### Solution

Automatic header generation:
- ✅ Generates correct C signatures automatically
- ✅ Maps Julia types to appropriate C types
- ✅ Creates proper include guards
- ✅ Adds extern "C" for C++ compatibility
- ✅ Keeps header in sync with compiled code
- ✅ Saves time and prevents errors

## API Reference

### compile_shlib with Header Generation

```julia
compile_shlib(f::Function, types::Tuple, path::String, name::String;
    generate_header::Bool=false,  # Enable automatic header generation
    demangle::Bool=true,          # Control function naming
    # ... other standard parameters
)
```

### generate_c_header (Manual)

For more control, generate headers manually:

```julia
generate_c_header(funcs::Array, path::String, filename::String;
    demangle::Bool=true,
    include_extern_c::Bool=true,
    verbose::Bool=false
) -> String
```

Returns the path to the generated header file.

### julia_to_c_type (Type Mapping)

Convert Julia types to C types:

```julia
julia_to_c_type(::Type{Int64})    # -> "int64_t"
julia_to_c_type(::Type{Float64})  # -> "double"
julia_to_c_type(::Type{Ptr{UInt8}})  # -> "uint8_t*"
```

## Type Mapping

### Supported Types

| Julia Type | C Type | Header | Notes |
|------------|--------|--------|-------|
| `Int8` | `int8_t` | `stdint.h` | 8-bit signed |
| `Int16` | `int16_t` | `stdint.h` | 16-bit signed |
| `Int32` | `int32_t` | `stdint.h` | 32-bit signed |
| `Int64` | `int64_t` | `stdint.h` | 64-bit signed |
| `Int` | `int64_t` or `int32_t` | `stdint.h` | Platform dependent |
| `UInt8` | `uint8_t` | `stdint.h` | 8-bit unsigned |
| `UInt16` | `uint16_t` | `stdint.h` | 16-bit unsigned |
| `UInt32` | `uint32_t` | `stdint.h` | 32-bit unsigned |
| `UInt64` | `uint64_t` | `stdint.h` | 64-bit unsigned |
| `UInt` | `uint64_t` or `uint32_t` | `stdint.h` | Platform dependent |
| `Float32` | `float` | Built-in | 32-bit float |
| `Float64` | `double` | Built-in | 64-bit float |
| `Bool` | `bool` | `stdbool.h` | Boolean |
| `Ptr{T}` | `T*` | Depends on `T` | Pointer to `T` |
| `Ptr{Cvoid}` | `void*` | Built-in | Void pointer |
| `Nothing` | `void` | Built-in | Return type only |
| `Cvoid` | `void` | Built-in | Return type only |

### Unsupported Types

Complex types that don't have direct C equivalents:
- `String` (use `Ptr{UInt8}` instead)
- `Array` (use `Ptr{T}` instead)
- `Tuple` (pass by reference or flatten)
- Custom structs (define equivalent C struct)
- Union types (not representable in C)

For unsupported types, a warning is issued and `void*` is used as a fallback.

## Usage Examples

### Example 1: Single Function

```julia
using StaticCompiler

function factorial(n::Int)
    result = 1
    for i in 2:n
        result *= i
    end
    return result
end

compile_shlib(factorial, (Int,), "./", "factorial", generate_header=true)
```

Generated header:
```c
int64_t factorial(int64_t arg0);
```

### Example 2: Multiple Functions

```julia
functions = [
    (add, (Int, Int)),
    (subtract, (Int, Int)),
    (multiply, (Int, Int)),
    (divide, (Int, Int))
]

compile_shlib(functions, "./",
              filename="math",
              generate_header=true)
```

Generated header:
```c
int64_t add(int64_t arg0, int64_t arg1);
int64_t subtract(int64_t arg0, int64_t arg1);
int64_t multiply(int64_t arg0, int64_t arg1);
int64_t divide(int64_t arg0, int64_t arg1);
```

### Example 3: Different Types

```julia
function compute(a::Float64, b::Float32, c::Int, d::Bool)
    return Float64(a + b + c + (d ? 1.0 : 0.0))
end

compile_shlib(compute, (Float64, Float32, Int, Bool), "./", "compute",
              generate_header=true)
```

Generated header:
```c
double compute(double arg0, float arg1, int64_t arg2, bool arg3);
```

### Example 4: Pointer Types

```julia
function sum_array(arr::Ptr{Float64}, n::Int)
    total = 0.0
    for i in 0:n-1
        total += unsafe_load(arr, i+1)
    end
    return total
end

compile_shlib(sum_array, (Ptr{Float64}, Int), "./", "sum_array",
              generate_header=true)
```

Generated header:
```c
double sum_array(double* arg0, int64_t arg1);
```

### Example 5: Void Return Type

```julia
function print_number(n::Int)
    println(n)
    return nothing
end

compile_shlib(print_number, (Int,), "./", "print",
              generate_header=true)
```

Generated header:
```c
void print_number(int64_t arg0);
```

## Using from C

### Basic Example

Julia code:
```julia
# math.jl
using StaticCompiler

function add(a::Int, b::Int)
    return a + b
end

compile_shlib(add, (Int, Int), "./", "math", generate_header=true)
```

C code:
```c
// main.c
#include <stdio.h>
#include "math.h"

int main() {
    int64_t result = add(10, 20);
    printf("10 + 20 = %ld\n", result);
    return 0;
}
```

Compile and run:
```bash
gcc main.c -L. -lmath -o main
./main
# Output: 10 + 20 = 30
```

### Working with Pointers

Julia code:
```julia
function sum_array(ptr::Ptr{Float64}, n::Int)
    total = 0.0
    for i in 0:n-1
        total += unsafe_load(ptr, i+1)
    end
    return total
end

compile_shlib(sum_array, (Ptr{Float64}, Int), "./", "array",
              generate_header=true)
```

C code:
```c
#include <stdio.h>
#include "array.h"

int main() {
    double arr[] = {1.0, 2.0, 3.0, 4.0, 5.0};
    double sum = sum_array(arr, 5);
    printf("Sum: %f\n", sum);
    return 0;
}
```

## Using from C++

The generated headers include `extern "C"` blocks for C++ compatibility.

C++ code:
```cpp
// main.cpp
#include <iostream>
#include "math.h"

int main() {
    int64_t result = add(42, 58);
    std::cout << "42 + 58 = " << result << std::endl;
    return 0;
}
```

Compile:
```bash
g++ main.cpp -L. -lmath -o main
./main
```

### C++ Wrapper Class

```cpp
class MathLib {
private:
    // Constructor private - all functions are static
    MathLib() = delete;

public:
    static int64_t add(int64_t a, int64_t b) {
        return ::add(a, b);  // Call C function
    }

    static int64_t multiply(int64_t a, int64_t b) {
        return ::multiply(a, b);
    }
};

int main() {
    auto result = MathLib::add(10, 20);
    std::cout << result << std::endl;
    return 0;
}
```

## Using from Rust

Rust FFI example:

```rust
// lib.rs
use std::os::raw::c_longlong;

#[link(name = "math")]
extern "C" {
    fn add(a: c_longlong, b: c_longlong) -> c_longlong;
    fn multiply(a: c_longlong, b: c_longlong) -> c_longlong;
}

fn main() {
    unsafe {
        let sum = add(10, 20);
        println!("10 + 20 = {}", sum);

        let product = multiply(10, 20);
        println!("10 * 20 = {}", product);
    }
}
```

Build with Cargo:
```toml
# Cargo.toml
[package]
name = "julia-example"
version = "0.1.0"

[dependencies]

[build-dependencies]
```

```bash
cargo build
cargo run
```

## Function Name Mangling

By default, `demangle=true` removes the `julia_` prefix from function names:

```julia
# With demangle=true (default)
compile_shlib(myfunc, (Int,), "./", "lib",
              demangle=true,
              generate_header=true)
# Generated header: int64_t myfunc(int64_t arg0);

# With demangle=false
compile_shlib(myfunc, (Int,), "./", "lib",
              demangle=false,
              generate_header=true)
# Generated header: int64_t julia_myfunc(int64_t arg0);
```

The `generate_header` parameter automatically respects the `demangle` setting.

## Advanced Features

### Manual Header Generation

Generate headers separately from compilation:

```julia
using StaticCompiler

# Compile library
lib_path = compile_shlib(funcs, "./", filename="mylib")

# Generate header later
header_path = generate_c_header(funcs, "./", "mylib",
                                demangle=true,
                                include_extern_c=true,
                                verbose=true)
```

### Custom Header Content

For full control, use the lower-level functions:

```julia
using StaticCompiler

# Prepare function information
func_info = [
    ("add", (Int, Int), Int),
    ("multiply", (Float64, Float64), Float64)
]

# Generate header content
content = generate_header_content(func_info, "mylib",
                                 demangle=true,
                                 include_extern_c=true,
                                 comment="My custom library")

# Write to file
write_header_file("./", "mylib", content)
```

### Type Inspection

Check how Julia types map to C:

```julia
using StaticCompiler

julia_to_c_type(Int64)           # "int64_t"
julia_to_c_type(Float32)         # "float"
julia_to_c_type(Bool)            # "bool"
julia_to_c_type(Ptr{UInt8})      # "uint8_t*"
julia_to_c_type(Ptr{Ptr{Float64}})  # "double**"
```

## Integration with Other Features

### With Verification

```julia
compile_shlib(func, types, "./", "name",
              verify=true,           # Pre-compilation checks
              min_score=85,
              generate_header=true)  # Generate header
```

### With Analysis Export

```julia
compile_shlib(func, types, "./", "name",
              export_analysis=true,  # Export JSON report
              generate_header=true)  # Generate C header
```

## Best Practices

### 1. Use Concrete Types

```julia
# Good
function add(a::Int64, b::Int64)
    return a + b
end

# Bad - abstract types
function add(a::Integer, b::Integer)
    return a + b
end
```

### 2. Use Pointers for Arrays

```julia
# Good
function sum(arr::Ptr{Float64}, n::Int)
    total = 0.0
    for i in 0:n-1
        total += unsafe_load(arr, i+1)
    end
    return total
end

# Bad - Julia Array type
function sum(arr::Vector{Float64})
    return sum(arr)
end
```

### 3. Return Native Types

```julia
# Good
function compute(x::Int) -> Int
    return x * 2
end

# Avoid - complex return types
function compute(x::Int) -> Tuple{Int, Int}
    return (x, x*2)
end
```

### 4. Document Units and Constraints

Add comments to your Julia functions:

```julia
"""
Process temperature data.

# C Interface
- temp: Temperature in Celsius (double)
- Returns: Temperature in Fahrenheit (double)
"""
function celsius_to_fahrenheit(temp::Float64)
    return temp * 9.0/5.0 + 32.0
end
```

### 5. Version Your Headers

When distributing libraries:

```c
/* mylib.h - Version 1.2.3 */
#define MYLIB_VERSION_MAJOR 1
#define MYLIB_VERSION_MINOR 2
#define MYLIB_VERSION_PATCH 3
```

## Troubleshooting

### Issue: Unsupported Type Warning

**Symptom:**
```
Warning: Unsupported type MyCustomType, using void*
```

**Solution:**
Use only supported primitive types. For complex types:
- Pass by pointer: `Ptr{MyType}`
- Flatten into multiple arguments
- Define equivalent C struct

### Issue: Wrong Function Signature

**Symptom:**
Generated header has incorrect types.

**Solution:**
1. Check your Julia type annotations are concrete
2. Verify return type is inferrable
3. Use `@code_typed` to check inferred types

```julia
@code_typed my_function(1, 2)
```

### Issue: Linker Errors

**Symptom:**
```
undefined reference to `my_function'
```

**Solution:**
1. Check function name matches (consider `demangle` setting)
2. Ensure library is in linker path: `-L./`
3. Link library: `-lmylib`
4. On macOS, use `install_name_tool` if needed

### Issue: Header Not Generated

**Symptom:**
No `.h` file created.

**Solution:**
1. Ensure `generate_header=true` is set
2. Check for errors in compilation
3. Verify write permissions in output directory
4. Look for warnings in output

## Platform-Specific Notes

### Linux

```bash
gcc main.c -L. -lmylib -o main
LD_LIBRARY_PATH=. ./main
```

### macOS

```bash
clang main.c -L. -lmylib -o main
DYLD_LIBRARY_PATH=. ./main
```

### Windows

```cmd
clang main.c -L. -lmylib -o main.exe
set PATH=%PATH%;.
main.exe
```

## Examples

See `examples/11_c_header_generation.jl` for comprehensive examples demonstrating:
- Basic header generation
- Multiple functions
- Different type mappings
- C/C++/Rust usage examples
- Integration with verification
- Name mangling options

## See Also

- [StaticCompiler.jl Documentation](../README.md)
- [Integrated Verification](./INTEGRATED_VERIFICATION.md)
- [FFI Best Practices](./FFI_BEST_PRACTICES.md)

## Summary

Automatic C header generation makes Julia functions immediately accessible from any language with C FFI:

```julia
# Just add generate_header=true
compile_shlib(func, types, "./", "name", generate_header=true)
```

**Benefits:**
- Automatic type mapping
- Proper C header structure
- C++ compatibility
- Saves time
- Prevents errors
- Keeps headers in sync

**Supported:**
- All primitive types (integers, floats, bools)
- Pointer types
- Multiple functions
- Custom naming (demangle option)
