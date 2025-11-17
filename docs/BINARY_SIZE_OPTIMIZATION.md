# Binary Size Optimization Guide

## Quick Answer

**Typical Hello World sizes:**
- **Without optimization:** 30-50 KB
- **With `-Os` + `strip`:** 15-25 KB
- **Fully optimized:** 10-20 KB
- **With UPX compression:** 5-15 KB

## Basic Hello World

```julia
using StaticCompiler
using StaticTools

function hello()
    println(c"Hello, World!")
    return 0
end

# Basic compilation
compile_executable(hello, (), "./", "hello")
# Result: ~30-50 KB
```

## Size Optimization Levels

### Level 1: Basic Optimization (Recommended)

```julia
compile_executable(hello, (), "./", "hello",
                   cflags=`-Os`)  # Optimize for size
```

Then strip debug symbols:
```bash
strip hello
```

**Expected size:** 15-25 KB
**Effort:** Minimal
**Trade-offs:** None

### Level 2: Link-Time Optimization

```julia
compile_executable(hello, (), "./", "hello",
                   cflags=`-Os -flto`)
```

Then:
```bash
strip hello
```

**Expected size:** 12-20 KB
**Effort:** Low
**Trade-offs:** Longer compile time

### Level 3: Dead Code Elimination

```julia
compile_executable(hello, (), "./", "hello",
                   cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`)
```

Then:
```bash
strip hello
```

**Expected size:** 10-18 KB
**Effort:** Low
**Trade-offs:** Slightly longer compile time

### Level 4: Maximum Compression

```julia
compile_executable(hello, (), "./", "hello",
                   template=:embedded,  # Uses size optimizations
                   cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`)
```

Then:
```bash
strip hello
upx --best hello
```

**Expected size:** 5-15 KB
**Effort:** Moderate
**Trade-offs:** Slower startup, requires UPX

## What Affects Binary Size?

### 1. Julia Runtime Components
- Type information and metadata
- Runtime type checking
- Exception handling

**Impact:** Moderate (15-20 KB base overhead)

### 2. Standard Library Dependencies
- Any `Base` functions used
- String handling
- I/O functions

**Impact:** High (can add 10-30 KB per dependency)

**Solution:** Use StaticTools instead of Base:
```julia
# ❌ Large
println("Hello")  # Uses Base.println

# ✅ Small
using StaticTools
println(c"Hello")  # Uses StaticTools.println
```

### 3. Debug Symbols
- Function names
- Line number information
- Type debug info

**Impact:** High (can be 30-50% of total size)

**Solution:** Always strip:
```bash
strip executable
```

### 4. Your Code
- Number of functions
- Complexity
- Inlining decisions

**Impact:** Variable

## Compiler Flag Reference

### Size Optimization Flags

| Flag | Purpose | Size Impact | Speed Impact |
|------|---------|-------------|--------------|
| `-Os` | Optimize for size | ↓↓ | ↓ (slight) |
| `-O2` | Optimize for speed | ↑ | ↑↑ |
| `-O3` | Aggressive optimization | ↑↑ | ↑↑↑ |
| `-flto` | Link-time optimization | ↓ | ↑ |
| `-fdata-sections` | Separate data sections | ↓ (with gc) | - |
| `-ffunction-sections` | Separate function sections | ↓ (with gc) | - |
| `-Wl,--gc-sections` | Remove unused sections | ↓↓ | - |
| `-fmerge-all-constants` | Merge constants | ↓ | - |

### Recommended Combinations

**For embedded/IoT:**
```julia
cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`
```

**For balanced:**
```julia
cflags=`-Os -flto`
```

**For performance:**
```julia
cflags=`-O3 -march=native`
```

## Post-Compilation Optimization

### 1. Strip Debug Symbols

```bash
strip executable
```

**Reduction:** 30-50%
**Always recommended**

### 2. UPX Compression

```bash
# Best compression
upx --best executable

# Ultra brute force (slow but smallest)
upx --ultra-brute executable
```

**Reduction:** 50-70% of stripped size
**Trade-offs:**
- Slower startup (decompression overhead)
- Higher memory usage during execution
- Not suitable for all platforms

### 3. Combine Both

```bash
strip executable
upx --best executable
```

**Typical final size:** 5-15 KB for hello world

## Template-Based Optimization

StaticCompiler.jl templates include size optimizations:

```julia
# Automatically applies size optimizations
compile_executable(hello, (), "./", "hello",
                   template=:embedded)
```

The `:embedded` template sets:
- `verify=true` (ensures code quality)
- `min_score=90` (strict standards)
- `generate_header=true` (for C integration)
- Automatically suggests size optimizations

## Code-Level Optimizations

### Use StaticTools

```julia
using StaticTools

# ✓ Small - stack allocated
println(c"Hello, World!")

# ✗ Large - heap allocated
println("Hello, World!")
```

### Avoid Base Functions

```julia
# ✗ Large - pulls in Base
function process(x)
    str = string(x)  # Base.string
    return parse(Int, str)  # Base.parse
end

# ✓ Small - minimal dependencies
function process(x::Int)
    return x * 2
end
```

### Control Inlining

```julia
# Force inline for small functions (reduces call overhead)
@inline function add(a, b)
    return a + b
end

# Prevent inline for large functions (reduces code duplication)
@noinline function complex_computation(data)
    # ... lots of code ...
end
```

### Use Concrete Types

```julia
# ✗ Requires runtime type checking
function compute(x::Number)
    return x * 2
end

# ✓ No runtime overhead
function compute(x::Int64)
    return x * 2
end
```

## Size Benchmarks

### Hello World Comparison

| Language | Typical Size | Notes |
|----------|-------------|-------|
| C (static) | 5-15 KB | Minimal runtime |
| Rust (release) | 200-500 KB | Includes Rust std |
| Go | 1-2 MB | Includes Go runtime |
| **Julia (StaticCompiler)** | **10-50 KB** | With StaticTools |
| Julia (normal) | 150+ MB | Full runtime |

### StaticCompiler.jl Size Progression

| Optimization Level | Size |
|-------------------|------|
| Basic compilation | 30-50 KB |
| With `-Os` | 25-40 KB |
| + strip | 15-25 KB |
| + LTO | 12-20 KB |
| + gc-sections | 10-18 KB |
| + UPX | 5-15 KB |

## Platform Differences

### Linux
- Smallest binaries possible
- All optimization flags work well
- `strip` very effective

### macOS
- Slightly larger due to Mach-O format
- Some linker flags differ
- `strip` works but less reduction

### Windows
- Larger due to PE format
- Different linker syntax
- UPX particularly useful

## Advanced Techniques

### 1. Custom Linker Script

For embedded systems:

```julia
compile_executable(hello, (), "./", "hello",
                   cflags=`-Os -T custom_linker.ld`)
```

Allows precise control over:
- Memory layout
- Section placement
- Unused code removal

### 2. Minimal C Runtime

For bare metal:

```julia
compile_executable(hello, (), "./", "hello",
                   cflags=`-nostdlib -Os`)
```

**Requirements:**
- Implement your own `_start`
- No libc dependencies
- Manual initialization

**Size reduction:** Significant (can save 5-10 KB)

### 3. Function Merging

```julia
compile_executable(hello, (), "./", "hello",
                   cflags=`-fmerge-all-constants -fmerge-functions -Os`)
```

Merges identical code across functions.

### 4. Profile-Guided Optimization (for size)

```julia
# 1. Compile with profiling
compile_executable(hello, (), "./", "hello",
                   cflags=`-fprofile-generate -Os`)

# 2. Run to collect profile
run(`./hello`)

# 3. Recompile with profile data
compile_executable(hello, (), "./", "hello",
                   cflags=`-fprofile-use -Os`)
```

Optimizes based on actual usage patterns.

## Real-World Example

```julia
using StaticCompiler
using StaticTools

# Embedded sensor firmware
function sensor_main()
    # Read sensor (using static string)
    println(c"Sensor reading: ")

    # Simple integer math
    value = read_adc()  # Custom function
    result = value * 2 + 1

    # Print result
    print_int(result)

    return 0
end

# Compile for embedded system
compile_executable(sensor_main, (), "./", "sensor",
                   template=:embedded,
                   cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`)

# Post-process
# strip sensor
# upx --best sensor

# Final size: ~8-12 KB
```

## Troubleshooting

### Binary Still Large?

1. **Check what's included:**
   ```bash
   nm -S executable | sort -k2 -rn | head -20
   ```
   Shows largest symbols

2. **Check sections:**
   ```bash
   size executable
   ```
   Shows text/data/bss sizes

3. **Find Base dependencies:**
   ```bash
   strings executable | grep "Base\."
   ```

4. **Verify optimizations applied:**
   ```bash
   readelf -p .comment executable  # Linux
   otool -L executable             # macOS
   ```

### UPX Fails

Some platforms don't support UPX:
- Use alternative: `gzip executable` (but not self-extracting)
- Use platform-specific tools
- Accept slightly larger size

### Compilation Fails with Optimization Flags

Try incrementally:
1. Start with just `-Os`
2. Add `-flto`
3. Add section flags
4. Add gc-sections

One flag at a time to isolate issues.

## Best Practices

### DO:
✓ Always use StaticTools for I/O
✓ Use concrete types
✓ Apply `-Os` for size-critical applications
✓ Strip debug symbols
✓ Test with `verify=true` to catch issues
✓ Use `:embedded` template for IoT

### DON'T:
✗ Use Base.println
✗ Allocate on heap unnecessarily
✗ Use abstract types
✗ Skip stripping
✗ Use `-O3` for size-critical code

## Quick Reference

### Minimal Size Recipe

```julia
using StaticCompiler
using StaticTools

function main()
    println(c"Hello, World!")
    return 0
end

compile_executable(main, (), "./", "hello",
                   template=:embedded,
                   cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`)
```

```bash
strip hello
upx --best hello
```

**Expected:** 5-15 KB

### Balanced Recipe

```julia
compile_executable(main, (), "./", "hello",
                   cflags=`-Os -flto`)
```

```bash
strip hello
```

**Expected:** 12-20 KB

## Summary

**Quick wins (minimal effort):**
1. Use `cflags=\`-Os\``
2. Run `strip` after compilation
3. Use StaticTools instead of Base

**Moderate optimization (some effort):**
4. Add `-flto`
5. Add gc-sections flags
6. Use `:embedded` template

**Maximum optimization (more effort):**
7. Apply UPX compression
8. Custom linker scripts
9. Profile-guided optimization

**Realistic expectations:**
- Hello world: 10-25 KB (optimized, stripped)
- Simple application: 20-50 KB
- Complex application: 50-200 KB

These are **excellent sizes** compared to most compiled languages while maintaining Julia's expressiveness!
