# Example 14: Complete Development Workflow
#
# This example demonstrates a complete development workflow using
# all the enhanced features of StaticCompiler.jl together in a
# realistic scenario.
#
# Scenario: Building a signal processing library for embedded systems

using StaticCompiler
using StaticTools

println("=" ^ 70)
println("Example 14: Complete Development Workflow")
println("=" ^ 70)
println()
println("Scenario: Building a signal processing library for embedded systems")
println()

# ============================================================================
# Part 1: Module Definition
# ============================================================================

println("Part 1: Defining the Signal Processing Module")
println("-" ^ 70)
println()

module SignalProcessing
    export moving_average, find_peaks, normalize

    """
    Calculate moving average of a signal.

    C signature: double moving_average(double* data, int n, int window)
    """
    function moving_average(data::Ptr{Float64}, n::Int, window::Int)
        if n < window || window <= 0
            return 0.0
        end

        total = 0.0
        for i in 0:window-1
            total += unsafe_load(data, i+1)
        end

        return total / window
    end

    """
    Find peaks in a signal (values greater than threshold).

    C signature: int find_peaks(double* data, int n, double threshold, int* peaks)
    """
    function find_peaks(data::Ptr{Float64}, n::Int, threshold::Float64,
                       peaks::Ptr{Int})
        count = 0

        for i in 0:n-1
            val = unsafe_load(data, i+1)
            if val > threshold
                unsafe_store!(peaks, i, count+1)
                count += 1
            end
        end

        return count
    end

    """
    Normalize signal to [0, 1] range.

    C signature: void normalize(double* data, int n, double* output)
    """
    function normalize(data::Ptr{Float64}, n::Int, output::Ptr{Float64})
        # Find min and max
        min_val = unsafe_load(data, 1)
        max_val = min_val

        for i in 1:n-1
            val = unsafe_load(data, i+1)
            if val < min_val
                min_val = val
            end
            if val > max_val
                max_val = val
            end
        end

        # Normalize
        range = max_val - min_val
        if range > 0.0
            for i in 0:n-1
                val = unsafe_load(data, i+1)
                normalized = (val - min_val) / range
                unsafe_store!(output, normalized, i+1)
            end
        end

        return nothing
    end

    # Internal helper (not exported)
    function _validate_input(data::Ptr{Float64}, n::Int)
        return n > 0
    end
end

println("SignalProcessing module defined")
println()
println("Exported functions:")
println("  • moving_average(Ptr{Float64}, Int, Int) → Float64")
println("  • find_peaks(Ptr{Float64}, Int, Float64, Ptr{Int}) → Int")
println("  • normalize(Ptr{Float64}, Int, Ptr{Float64}) → Nothing")
println()

# ============================================================================
# Part 2: Development Phase - Analysis and Iteration
# ============================================================================

println()
println("Part 2: Development Phase - Code Quality Analysis")
println("-" ^ 70)
println()

println("Step 2.1: Analyzing code with debugging template")
println()

# Define signatures
signatures = Dict(
    :moving_average => [(Ptr{Float64}, Int, Int)],
    :find_peaks => [(Ptr{Float64}, Int, Float64, Ptr{Int})],
    :normalize => [(Ptr{Float64}, Int, Ptr{Float64})]
)

output_dir_dev = mktempdir()

try
    # Compile with debugging template for development
    lib_path = compile_package(SignalProcessing, signatures,
                               output_dir_dev, "signal_dev",
                               template=:debugging,
                               verify=true,
                               export_analysis=true)

    println()
    println("Development build successful!")
    println("   Library: $lib_path")
    println()

    # Check for analysis report
    analysis_path = joinpath(output_dir_dev, "signal_dev_analysis.json")
    if isfile(analysis_path)
        println("Detailed analysis report: $analysis_path")
        println()
    end

catch e
    println("Error during development build: $e")
    println()
end

# ============================================================================
# Part 3: Testing Phase - Portable Build
# ============================================================================

println()
println("Part 3: Testing Phase - Portable Build for Multiple Platforms")
println("-" ^ 70)
println()

output_dir_test = mktempdir()

try
    println("Compiling with :portable template for compatibility testing...")
    println()

    lib_path = compile_package(SignalProcessing, signatures,
                               output_dir_test, "signal_test",
                               template=:portable,
                               verify=true,
                               generate_header=true)

    println()
    println("Test build successful!")
    println("   Library: $lib_path")
    println()

    # Show generated header
    header_path = joinpath(output_dir_test, "signal_test.h")
    if isfile(header_path)
        println("Generated C header:")
        println("-" ^ 70)
        header_content = read(header_path, String)
        # Show just the function declarations
        for line in split(header_content, '\n')
            if contains(line, "signalprocessing_") && contains(line, "(")
                println("  " * strip(line))
            end
        end
        println("-" ^ 70)
        println()
    end

catch e
    println("Error during test build: $e")
    println()
end

# ============================================================================
# Part 4: Production Phase - Optimized Embedded Build
# ============================================================================

println()
println("Part 4: Production Phase - Embedded System Build")
println("-" ^ 70)
println()

output_dir_prod = mktempdir()

try
    println("Compiling for embedded system with size optimization...")
    println()

    # Use embedded template with aggressive size optimization
    lib_path = compile_package(SignalProcessing, signatures,
                               output_dir_prod, "signal",
                               template=:embedded,
                               cflags=`-Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections`,
                               generate_header=true,
                               namespace="sp")  # Short namespace for embedded

    println()
    println("Production build successful!")
    println("   Library: $lib_path")
    println()

    if isfile(lib_path)
        size_bytes = filesize(lib_path)
        size_kb = round(size_bytes / 1024, digits=1)
        println("   Size: $size_kb KB ($size_bytes bytes)")
        println()

        # Try to strip
        if Sys.which("strip") !== nothing
            stripped_path = lib_path * ".stripped"
            cp(lib_path, stripped_path)
            run(`strip $stripped_path`)

            stripped_size = filesize(stripped_path)
            stripped_kb = round(stripped_size / 1024, digits=1)
            reduction = round((1 - stripped_size/size_bytes) * 100, digits=1)

            println("   After strip: $stripped_kb KB (-$reduction%)")
            println()
        end
    end

    # Show generated header with custom namespace
    header_path = joinpath(output_dir_prod, "signal.h")
    if isfile(header_path)
        println("Production header with 'sp_' namespace:")
        println("-" ^ 70)
        header_content = read(header_path, String)
        for line in split(header_content, '\n')
            if contains(line, "sp_") && contains(line, "(")
                println("  " * strip(line))
            end
        end
        println("-" ^ 70)
        println()
    end

catch e
    println("Error during production build: $e")
    println()
end

# ============================================================================
# Part 5: Performance Build - HPC Version
# ============================================================================

println()
println("Part 5: Performance Build - HPC Version")
println("-" ^ 70)
println()

output_dir_perf = mktempdir()

try
    println("Compiling for maximum performance...")
    println()

    lib_path = compile_package(SignalProcessing, signatures,
                               output_dir_perf, "signal_fast",
                               template=:performance,
                               cflags=`-O3 -march=native -ffast-math`,
                               generate_header=true)

    println()
    println("Performance build successful!")
    println("   Library: $lib_path")
    println()

catch e
    println("Error during performance build: $e")
    println()
end

# ============================================================================
# Part 6: Integration Example - C Usage
# ============================================================================

println()
println("Part 6: C Integration Example")
println("-" ^ 70)
println()

c_example = """
#include \"signal.h\"
#include <stdio.h>

int main() {
    // Sample data
    double data[] = {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0};
    int n = 8;

    // Calculate moving average (window = 3)
    double avg = sp_moving_average(data, n, 3);
    printf(\"Moving average: %f\\n\", avg);

    // Find peaks above threshold
    int peaks[8];
    int peak_count = sp_find_peaks(data, n, 5.0, peaks);
    printf(\"Peaks found: %d\\n\", peak_count);

    // Normalize data
    double normalized[8];
    sp_normalize(data, n, normalized);

    printf(\"Normalized: \");
    for (int i = 0; i < n; i++) {
        printf(\"%f \", normalized[i]);
    }
    printf(\"\\n\");

    return 0;
}

// Compile with:
// gcc -o signal_demo signal_demo.c signal.so -Wl,-rpath,.
"""

println("Example C code using the compiled library:")
println("-" ^ 70)
println(c_example)
println("-" ^ 70)
println()

# ============================================================================
# Part 7: Workflow Summary
# ============================================================================

println()
println("=" ^ 70)
println("Complete Workflow Summary")
println("=" ^ 70)
println()

println("Development Workflow Demonstrated:")
println()

println("1. Module Definition")
println("   - Defined SignalProcessing module with 3 exported functions")
println("   - Used concrete types for C interoperability")
println("   - Documented C signatures in docstrings")
println()

println("2. Development Build (:debugging template)")
println("   - Pre-compilation verification enabled")
println("   - Detailed analysis report exported")
println("   - Helpful diagnostics for iteration")
println()

println("3. Testing Build (:portable template)")
println("   - Verified cross-platform compatibility")
println("   - Generated C header for integration testing")
println("   - More permissive verification for broader compatibility")
println()

println("4. Production Build (:embedded template)")
println("   - Strict verification (min_score=90)")
println("   - Aggressive size optimization flags")
println("   - Custom namespace for embedded systems")
println("   - Stripped binary for deployment")
println()

println("5. Performance Build (:performance template)")
println("   - Aggressive optimization (-O3 -march=native)")
println("   - Fast math optimizations")
println("   - Optimized for HPC workloads")
println()

println("6. Integration")
println("   - Generated C headers for all builds")
println("   - Example C code demonstrating usage")
println("   - Ready for deployment in multiple scenarios")
println()

# ============================================================================
# Part 8: CLI Workflow Alternative
# ============================================================================

println()
println("Part 8: Alternative CLI Workflow")
println("-" ^ 70)
println()

println("All of the above can be done via command-line tools:")
println()

println("Development:")
println("  ./bin/analyze-code signal.jl moving_average")
println("  ./bin/quick-compile signal.jl moving_average")
println()

println("Testing:")
println("  ./bin/staticcompile --shlib --template portable \\")
println("      --generate-header signal.jl moving_average")
println()

println("Production (embedded):")
println("  ./bin/optimize-binary --level aggressive \\")
println("      --output sensor signal.jl sensor_read")
println("  ./bin/optimize-binary --upx --verbose \\")
println("      signal.jl sensor_read")
println()

println("Production (package compilation):")
println("  ./bin/staticcompile --package --signatures signatures.json \\")
println("      --template embedded --namespace sp \\")
println("      --output signal SignalProcessing.jl")
println()

println("Batch compilation:")
println("  ./bin/batch-compile build_config.json")
println()

# ============================================================================
# Part 9: Best Practices Demonstrated
# ============================================================================

println()
println("Part 9: Best Practices Demonstrated")
println("-" ^ 70)
println()

println("OK Use concrete types (Ptr{Float64}, Int, not Number)")
println("OK Export only public API (internal helpers private)")
println("OK Document C signatures in docstrings")
println("OK Use templates for different build stages")
println("OK Enable verification during development")
println("OK Generate headers for C integration")
println("OK Apply size optimization for embedded")
println("OK Use custom namespaces to avoid collisions")
println("OK Strip binaries for production")
println("OK Export analysis during development")
println()

# ============================================================================
# Part 10: Deployment Scenarios
# ============================================================================

println()
println("Part 10: Deployment Scenarios")
println("-" ^ 70)
println()

println("Embedded System (ARM Cortex-M):")
println("  Template: :embedded")
println("  Flags: -Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections")
println("  Post: strip + upx")
println("  Result: ~10-20 KB library")
println()

println("Server/HPC (x86_64):")
println("  Template: :performance")
println("  Flags: -O3 -march=native -ffast-math")
println("  Post: None (size not critical)")
println("  Result: Maximum performance")
println()

println("Distribution (Multi-platform):")
println("  Template: :portable")
println("  Flags: -O2 (no -march)")
println("  Post: strip")
println("  Result: Broad compatibility")
println()

println("Commercial Product:")
println("  Template: :production")
println("  Flags: -O2 -flto")
println("  Post: strip")
println("  Result: Quality + docs + audit trail")
println()

# ============================================================================
# Summary
# ============================================================================

println()
println("=" ^ 70)
println("WORKFLOW COMPLETE")
println("=" ^ 70)
println()

println("This example demonstrated:")
println("  OK Package-level compilation")
println("  OK All six compilation templates")
println("  OK Pre-compilation verification")
println("  OK C header generation")
println("  OK Custom namespaces")
println("  OK Size optimization")
println("  OK Multiple build configurations")
println("  OK C integration")
println("  OK CLI tool workflow")
println("  OK Best practices")
println()

println("Next steps:")
println("  1. Adapt this workflow to your project")
println("  2. Choose appropriate template for your use case")
println("  3. Use CLI tools for automation")
println("  4. Set up build scripts (see bin/batch-compile)")
println("  5. Integrate with your build system")
println()

println("See also:")
println("  • docs/COMPILATION_TEMPLATES.md")
println("  • docs/INTEGRATED_VERIFICATION.md")
println("  • docs/C_HEADER_GENERATION.md")
println("  • docs/BINARY_SIZE_OPTIMIZATION.md")
println("  • bin/README.md")
println()

println("=" ^ 70)
