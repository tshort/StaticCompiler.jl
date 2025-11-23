#!/usr/bin/env julia

# Test Suite for StaticCompiler.jl Enhancements
#
# Tests all the new features added to StaticCompiler.jl:
# - Integrated verification
# - C header generation
# - Compilation templates
# - Package-level compilation

using Test
using StaticCompiler
using StaticTools

println("=" ^ 70)
println("StaticCompiler.jl Enhancement Test Suite")
println("=" ^ 70)
println()

# Test output directory
test_output = mktempdir()
println("Test output directory: $test_output")
println()

# ============================================================================
# Test 1: Basic Compilation (Baseline)
# ============================================================================

@testset "Basic Compilation" begin
    println("Test 1: Basic Compilation")

    function test_basic()
        println(c"Hello from test")
        return 0
    end

    output_dir = joinpath(test_output, "basic")
    mkpath(output_dir)

    # Test executable compilation
    exe_path = compile_executable(test_basic, (), output_dir, "test_basic")
    @test isfile(exe_path)
    @test filesize(exe_path) > 0

    # Test shared library compilation
    lib_path = compile_shlib(test_basic, (), output_dir; filename="test_basic_lib")
    @test isfile(lib_path)
    @test filesize(lib_path) > 0

    println("  Basic compilation works")
    println()
end

# ============================================================================
# Test 2: Integrated Verification
# ============================================================================

@testset "Integrated Verification" begin
    println("Test 2: Integrated Verification")

    # Good function (should pass)
    function good_func(x::Int)
        return x * 2
    end

    # Problematic function (might have lower score)
    function problematic_func(x)  # Abstract type
        arr = []  # Heap allocation
        push!(arr, x)
        return arr[1]
    end

    output_dir = joinpath(test_output, "verification")
    mkpath(output_dir)

    # Test that verification works
    @test_nowarn begin
        compile_executable(good_func, (Int,), output_dir, "good",
                          verify=true, min_score=80)
    end

    # Test custom threshold
    @test_nowarn begin
        compile_executable(good_func, (Int,), output_dir, "good_strict",
                          verify=true, min_score=95)
    end

    # Test that verification can detect issues
    # (might pass or fail depending on actual score, but should not error)
    try
        compile_executable(problematic_func, (Any,), output_dir, "problematic",
                          verify=true, min_score=90)
    catch e
        # Expected to possibly fail verification
        @test contains(string(e), "verification") || contains(string(e), "score")
    end

    println("  Verification system works")
    println()
end

# ============================================================================
# Test 3: C Header Generation
# ============================================================================

@testset "C Header Generation" begin
    println("Test 3: C Header Generation")

    function add_numbers(a::Int, b::Int)
        return a + b
    end

    function multiply(a::Float64, b::Float64)
        return a * b
    end

    output_dir = joinpath(test_output, "headers")
    mkpath(output_dir)

    # Test header generation for single function
    lib_path = compile_shlib(add_numbers, (Int, Int), output_dir;
                            filename="math",
                            generate_header=true)

    header_path = joinpath(output_dir, "math.h")
    @test isfile(header_path)

    header_content = read(header_path, String)
    @test contains(header_content, "int64_t")  # C type mapping
    @test contains(header_content, "#ifndef")  # Header guard
    @test contains(header_content, "extern")   # C linkage

    # Test header generation for multiple functions
    lib_path = compile_shlib([(add_numbers, (Int, Int)),
                              (multiply, (Float64, Float64))],
                            output_dir;
                            filename="multimath",
                            generate_header=true)

    multiheader_path = joinpath(output_dir, "multimath.h")
    @test isfile(multiheader_path)

    println("  Header generation works")
    println()
end

# ============================================================================
# Test 4: Compilation Templates
# ============================================================================

@testset "Compilation Templates" begin
    println("Test 4: Compilation Templates")

    function template_test(n::Int)
        result = 0
        for i in 1:n
            result += i
        end
        return result
    end

    output_dir = joinpath(test_output, "templates")
    mkpath(output_dir)

    # Test each template
    templates = [:embedded, :performance, :portable, :debugging, :production, :default]

    for tmpl in templates
        exe_path = compile_executable(template_test, (Int,), output_dir,
                                      "test_$(tmpl)",
                                      template=tmpl)
        @test isfile(exe_path)
    end

    # Test template with overrides
    exe_path = compile_executable(template_test, (Int,), output_dir,
                                  "test_override",
                                  template=:embedded,
                                  min_score=85)  # Override default 90
    @test isfile(exe_path)

    # Test template introspection
    @test length(list_templates()) == 6
    @test :embedded in list_templates()

    tmpl = get_template(:embedded)
    @test tmpl.name == :embedded
    @test tmpl.params.verify == true
    @test tmpl.params.min_score == 90

    println("  All templates work")
    println()
end

# ============================================================================
# Test 5: Package-Level Compilation
# ============================================================================

@testset "Package-Level Compilation" begin
    println("Test 5: Package-Level Compilation")

    # Define a test module
    module TestMath
        export add, subtract, multiply

        function add(a::Int, b::Int)
            return a + b
        end

        function subtract(a::Int, b::Int)
            return a - b
        end

        function multiply(x::Float64, y::Float64)
            return x * y
        end

        # Not exported
        function internal_func(x::Int)
            return x * 2
        end
    end

    output_dir = joinpath(test_output, "package")
    mkpath(output_dir)

    signatures = Dict(
        :add => [(Int, Int)],
        :subtract => [(Int, Int)],
        :multiply => [(Float64, Float64)]
    )

    # Test basic package compilation
    lib_path = compile_package(TestMath, signatures, output_dir, "testmath")
    @test isfile(lib_path)

    # Test package compilation with template
    lib_path = compile_package(TestMath, signatures, output_dir, "testmath_prod",
                               template=:production)
    @test isfile(lib_path)

    # Test with custom namespace
    lib_path = compile_package(TestMath, signatures, output_dir, "testmath_ns",
                               namespace="tm")
    @test isfile(lib_path)

    # Test compile_package_exports
    lib_path = compile_package_exports(TestMath, signatures, output_dir, "testmath_exp")
    @test isfile(lib_path)

    println("  Package compilation works")
    println()
end

# ============================================================================
# Test 6: Integration - All Features Together
# ============================================================================

@testset "Integration - All Features" begin
    println("Test 6: Integration Test - All Features Together")

    module IntegrationTest
        export process_data

        function process_data(data::Ptr{Float64}, n::Int)
            total = 0.0
            for i in 0:n-1
                total += unsafe_load(data, i+1)
            end
            return total / n
        end
    end

    output_dir = joinpath(test_output, "integration")
    mkpath(output_dir)

    signatures = Dict(
        :process_data => [(Ptr{Float64}, Int)]
    )

    # Use all features together:
    # - Package compilation
    # - Template
    # - Verification
    # - Header generation
    # - Custom namespace
    lib_path = compile_package(IntegrationTest, signatures, output_dir, "integration",
                               template=:production,
                               verify=true,
                               generate_header=true,
                               namespace="it")

    @test isfile(lib_path)

    # Check header was generated
    header_path = joinpath(output_dir, "integration.h")
    @test isfile(header_path)

    header_content = read(header_path, String)
    @test contains(header_content, "it_")  # Custom namespace

    println("  All features work together")
    println()
end

# ============================================================================
# Test 7: Binary Size Optimization Flags
# ============================================================================

@testset "Binary Size Optimization" begin
    println("Test 7: Binary Size Optimization")

    function size_test()
        println(c"Size test")
        return 0
    end

    output_dir = joinpath(test_output, "size")
    mkpath(output_dir)

    # Compile with different optimization levels
    exe_basic = compile_executable(size_test, (), output_dir, "size_basic")
    exe_os = compile_executable(size_test, (), output_dir, "size_os",
                               cflags=`-Os`)
    exe_optimized = compile_executable(size_test, (), output_dir, "size_opt",
                                      cflags=`-Os -flto`)

    @test isfile(exe_basic)
    @test isfile(exe_os)
    @test isfile(exe_optimized)

    # Size comparison (optimized should generally be smaller or equal)
    size_basic = filesize(exe_basic)
    size_os = filesize(exe_os)
    size_optimized = filesize(exe_optimized)

    @test size_basic > 0
    @test size_os > 0
    @test size_optimized > 0

    println("  Size comparison:")
    println("    Basic: $(round(size_basic/1024, digits=1)) KB")
    println("    -Os: $(round(size_os/1024, digits=1)) KB")
    println("    -Os -flto: $(round(size_optimized/1024, digits=1)) KB")
    println("  Optimization flags work")
    println()
end

# ============================================================================
# Test 8: Runtime Requirement Detection
# ============================================================================

@testset "Runtime Requirement Detection" begin
    # Ensures runtime-dependent code errors when runtime linking is disabled
    println("Test 8: Runtime Requirement Detection")

    output_dir = joinpath(test_output, "runtime_guard")
    mkpath(output_dir)

    f(a::Int, b::Int) = div(a, b)
    target = StaticTarget()
    err = @test_throws ErrorException compile_shlib(f, (Int, Int), output_dir, "div_no_runtime"; target=target)
    @test occursin("runtime symbols", sprint(showerror, err))

    println("  Runtime guard works")
    println()
end

# ============================================================================
# Test 9: Error Handling
# ============================================================================

@testset "Error Handling" begin
    println("Test 9: Error Handling")

    output_dir = joinpath(test_output, "errors")
    mkpath(output_dir)

    # Test unknown template
    @test_throws Exception compile_executable(
        x -> x,
        (Int,),
        output_dir,
        "test",
        template=:nonexistent
    )

    # Test invalid min_score
    @test_throws Exception compile_executable(
        x -> x,
        (Int,),
        output_dir,
        "test",
        verify=true,
        min_score=150  # Invalid: > 100
    )

    println("  Error handling works")
    println()
end

# ============================================================================
# Summary
# ============================================================================

println("=" ^ 70)
println("Test Suite Complete")
println("=" ^ 70)
println()

println("All enhancements tested:")
println("  Basic compilation (baseline)")
println("  Integrated verification")
println("  C header generation")
println("  Compilation templates (6 templates)")
println("  Package-level compilation")
println("  Integration (all features together)")
println("  Binary size optimization")
println("  Runtime requirement guard")
println("  Error handling")
println()

println("Test output directory: $test_output")
println()

println("All tests passed! ")
println()
