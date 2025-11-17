#!/usr/bin/env julia

# Binary Size Analysis for StaticCompiler.jl
# Demonstrates hello world compilation and size optimization techniques

using StaticCompiler
using StaticTools

println("="^70)
println("Binary Size Analysis - Hello World")
println("="^70)
println()

# ============================================================================
# Basic Hello World
# ============================================================================

function hello_basic()
    println(c"Hello, World!")
    return 0
end

println("Compiling basic hello world...")
output_dir = mktempdir()

try
    # Compile basic version
    exe_path = compile_executable(hello_basic, (), output_dir, "hello_basic")

    if isfile(exe_path)
        size_bytes = filesize(exe_path)
        size_kb = round(size_bytes / 1024, digits=1)

        println("✅ Compiled: $exe_path")
        println("   Size: $size_kb KB ($size_bytes bytes)")
        println()
    end
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# What Contributes to Binary Size?
# ============================================================================

println("="^70)
println("WHAT AFFECTS BINARY SIZE?")
println("="^70)
println()

println("1. Julia Runtime Components")
println("   • Type information and metadata")
println("   • Runtime type checking code")
println("   • Exception handling infrastructure")
println()

println("2. Standard Library Dependencies")
println("   • Any Base functions used")
println("   • String handling")
println("   • I/O functions")
println()

println("3. Compilation Settings")
println("   • Debug symbols")
println("   • Optimization level")
println("   • Link-time optimization")
println()

println("4. Your Code")
println("   • Function complexity")
println("   • Number of functions")
println("   • Inlining decisions")
println()

# ============================================================================
# Size Optimization Techniques
# ============================================================================

println("="^70)
println("SIZE OPTIMIZATION TECHNIQUES")
println("="^70)
println()

println("TECHNIQUE 1: Use StaticTools (already doing this)")
println("-"^70)
println("✓ c\"...\" for static strings (no heap allocation)")
println("✓ println() from StaticTools (minimal I/O)")
println("✓ No dynamic allocations")
println()

println("Current approach:")
println("""
    using StaticTools
    function hello()
        println(c"Hello, World!")  # ← StaticString, stack-allocated
        return 0
    end
""")
println()

println("TECHNIQUE 2: Strip Debug Symbols")
println("-"^70)
println("Debug symbols can significantly increase size.")
println()
println("After compilation, run:")
println("  strip hello_basic")
println("  # Can reduce size by 30-50%")
println()

# Demonstrate if strip is available
strip_test_path = joinpath(output_dir, "hello_basic")
if isfile(strip_test_path) && Sys.which("strip") !== nothing
    original_size = filesize(strip_test_path)

    # Make a copy to strip
    stripped_path = joinpath(output_dir, "hello_stripped")
    cp(strip_test_path, stripped_path)

    try
        run(`strip $stripped_path`)
        stripped_size = filesize(stripped_path)

        reduction = round((1 - stripped_size/original_size) * 100, digits=1)
        original_kb = round(original_size / 1024, digits=1)
        stripped_kb = round(stripped_size / 1024, digits=1)

        println("Example:")
        println("  Original: $original_kb KB")
        println("  Stripped: $stripped_kb KB")
        println("  Reduction: $reduction%")
        println()
    catch e
        println("(strip command not available or failed)")
        println()
    end
end

println("TECHNIQUE 3: Compiler Optimization Flags")
println("-"^70)
println("Use cflags to control optimization:")
println()
println("For size optimization:")
println("""
    compile_executable(hello, (), "./", "hello",
                       cflags=`-Os`)  # Optimize for size
""")
println()
println("  -Os  : Optimize for size")
println("  -O2  : Optimize for speed (may increase size)")
println("  -O3  : Aggressive optimization (larger)")
println()

println("TECHNIQUE 4: Link-Time Optimization (LTO)")
println("-"^70)
println("LTO can eliminate unused code across compilation units:")
println()
println("""
    compile_executable(hello, (), "./", "hello",
                       cflags=`-flto -Os`)
""")
println()

println("TECHNIQUE 5: Minimize Dependencies")
println("-"^70)
println("Avoid using Base functions that pull in large dependencies:")
println()
println("❌ Avoid:")
println("  • println(\"...\")  # Base.println pulls in I/O")
println("  • String manipulation (uses Base)")
println("  • Complex math functions")
println()
println("✓ Use:")
println("  • StaticTools.println(c\"...\")  # Minimal")
println("  • StaticTools functions")
println("  • Custom implementations")
println()

println("TECHNIQUE 6: Function Inlining Control")
println("-"^70)
println("Control what gets inlined:")
println()
println("""
    @inline function small_func()
        # Force inlining (reduces calls, may increase size)
    end

    @noinline function large_func()
        # Prevent inlining (reduces duplication)
    end
""")
println()

println("TECHNIQUE 7: Dead Code Elimination")
println("-"^70)
println("Ensure unused code is eliminated:")
println()
println("""
    compile_executable(hello, (), "./", "hello",
                       cflags=`-fdata-sections -ffunction-sections -Wl,--gc-sections`)
""")
println()
println("  -fdata-sections       : Separate data sections")
println("  -ffunction-sections   : Separate function sections")
println("  -Wl,--gc-sections     : Garbage collect unused sections")
println()

# ============================================================================
# Practical Size Comparison
# ============================================================================

println("="^70)
println("PRACTICAL SIZE COMPARISON")
println("="^70)
println()

# Different versions
versions = [
    ("Basic", hello_basic, (), Dict()),
    ("With -Os", hello_basic, (), Dict(:cflags => `-Os`)),
    ("With LTO", hello_basic, (), Dict(:cflags => `-flto -Os`)),
]

println("Compiling different optimization levels...")
println()

results = []

for (name, func, types, kwargs) in versions
    output_subdir = joinpath(output_dir, replace(name, " " => "_"))
    mkpath(output_subdir)

    try
        exe_path = compile_executable(func, types, output_subdir, "hello"; kwargs...)

        if isfile(exe_path)
            size_bytes = filesize(exe_path)
            size_kb = round(size_bytes / 1024, digits=1)

            push!(results, (name, size_kb, size_bytes))
            println("  $name: $size_kb KB")
        end
    catch e
        println("  $name: Failed ($e)")
    end
end

println()

# ============================================================================
# Size Benchmarks (Typical Ranges)
# ============================================================================

println("="^70)
println("TYPICAL SIZE RANGES")
println("="^70)
println()

println("For a minimal \"Hello, World\" executable:")
println()
println("  Without optimization:     30-50 KB")
println("  With -Os:                 25-40 KB")
println("  With -Os + strip:         15-25 KB")
println("  With -Os + LTO + strip:   10-20 KB")
println()

println("For comparison with other languages:")
println()
println("  C (static):               ~5-15 KB")
println("  Rust (release):           ~200-500 KB")
println("  Go:                       ~1-2 MB")
println("  Julia (StaticCompiler):   ~15-50 KB")
println()

println("Note: Sizes vary by platform, compiler version, and exact code.")
println()

# ============================================================================
# Advanced Size Reduction
# ============================================================================

println("="^70)
println("ADVANCED SIZE REDUCTION TECHNIQUES")
println("="^70)
println()

println("1. UPX Compression")
println("-"^70)
println("UPX can compress executables (self-extracting):")
println()
println("  upx --best hello")
println("  # Can achieve 50-70% compression")
println()
println("Trade-offs:")
println("  ✓ Smaller on disk")
println("  ✓ Smaller for distribution")
println("  ✗ Slower startup (decompression)")
println("  ✗ Higher memory usage during execution")
println()

println("2. Custom Linker Scripts")
println("-"^70)
println("For embedded systems, use custom linker scripts")
println("to control memory layout and remove unused sections.")
println()

println("3. Minimal C Runtime")
println("-"^70)
println("For embedded systems, use a minimal C runtime:")
println()
println("""
    compile_executable(func, types, "./", "hello",
                       cflags=`-nostdlib -Os`)
""")
println()
println("Requires implementing _start and avoiding libc.")
println()

println("4. Function Merging")
println("-"^70)
println("Let the compiler merge identical functions:")
println()
println("""
    compile_executable(func, types, "./", "hello",
                       cflags=`-fmerge-all-constants -Os`)
""")
println()

# ============================================================================
# Recommendations by Use Case
# ============================================================================

println("="^70)
println("RECOMMENDATIONS BY USE CASE")
println("="^70)
println()

println("Embedded/IoT (size critical):")
println("  compile_executable(func, types, \"./\", \"app\",")
println("                     template=:embedded,")
println("                     cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`)")
println("  Then: strip app && upx --best app")
println()

println("Desktop/Server (balanced):")
println("  compile_executable(func, types, \"./\", \"app\",")
println("                     template=:default,")
println("                     cflags=`-O2`)")
println("  Then: strip app")
println()

println("HPC/Performance (size not critical):")
println("  compile_executable(func, types, \"./\", \"app\",")
println("                     template=:performance,")
println("                     cflags=`-O3 -march=native`)")
println()

# ============================================================================
# Summary
# ============================================================================

println("="^70)
println("SUMMARY")
println("="^70)
println()

if !isempty(results)
    println("Your hello world results:")
    for (name, size_kb, size_bytes) in results
        println("  $name: $size_kb KB")
    end
    println()
end

println("Key takeaways:")
println("  ✓ Use StaticTools for minimal I/O")
println("  ✓ Apply -Os for size optimization")
println("  ✓ Strip debug symbols after compilation")
println("  ✓ Use -flto for link-time optimization")
println("  ✓ Use --gc-sections to remove unused code")
println("  ✓ Consider UPX for distribution")
println()

println("Expected range for optimized hello world:")
println("  10-25 KB (with all optimizations)")
println()

println("For smallest possible size:")
println("  1. Use StaticTools")
println("  2. Compile with: cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`")
println("  3. Run: strip executable")
println("  4. Run: upx --best executable")
println("  5. Result: ~5-15 KB")
println()

println("="^70)
