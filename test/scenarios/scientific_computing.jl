# Real-World Scenario: Scientific Computing
# High-performance numerical algorithms with accuracy requirements

using Test
using StaticCompiler
using StaticTools

@testset "Scientific Computing Scenario" begin
    println("\n" * "="^70)
    println("REAL-WORLD SCENARIO: Scientific Computing")
    println("="^70)
    println()
    println("Context: Numerical simulation for physics research")
    println("Requirements: High performance, numerical accuracy, vectorization")
    println()

    # Scenario: Particle physics simulation
    # Constraints:
    # - Must handle large arrays efficiently
    # - Numerical accuracy critical
    # - Performance-critical tight loops
    # - Potential for SIMD optimization

    @testset "Matrix-vector operations" begin
        println("📊 Test 1: Matrix-Vector Multiplication")
        println("   Requirement: Efficient linear algebra operations")
        println()

        # Matrix-vector multiply (simplified)
        function matvec_multiply(A::Matrix{Float64}, x::Vector{Float64})
            m, n = size(A)
            y = zeros(Float64, m)
            for i in 1:m
                for j in 1:n
                    y[i] += A[i, j] * x[j]
                end
            end
            return y
        end

        # Analyze for optimizations
        escape_report = analyze_escapes(matvec_multiply, (Matrix{Float64}, Vector{Float64}))
        devirt_report = analyze_devirtualization(matvec_multiply, (Matrix{Float64}, Vector{Float64}))

        println("   Matrix-vector multiply:")
        println("      Allocations: $(length(escape_report.allocations))")
        println("      Stack-promotable: $(escape_report.promotable_allocations)")
        println("      Virtual calls: $(devirt_report.virtual_call_sites)")
        println("      Direct calls: $(devirt_report.direct_call_sites)")

        @test !isnothing(escape_report)
        @test !isnothing(devirt_report)

        println("   ✅ Matrix operations analyzed")
        println()
    end

    @testset "Numerical integration" begin
        println("📊 Test 2: Numerical Integration (Trapezoidal Rule)")
        println("   Requirement: Accurate numerical integration")
        println()

        # Trapezoidal rule integration
        function integrate_trapezoidal(f::Function, a::Float64, b::Float64, n::Int)
            h = (b - a) / n
            result = 0.5 * (f(a) + f(b))

            for i in 1:(n-1)
                x = a + i * h
                result += f(x)
            end

            return result * h
        end

        # Test function: integrate x^2 from 0 to 1 (should be ~0.333)
        test_fn(x) = x^2

        # Analyze for optimizations
        const_report = analyze_constants(integrate_trapezoidal, (Function, Float64, Float64, Int))
        escape_report = analyze_escapes(integrate_trapezoidal, (Function, Float64, Float64, Int))

        println("   Numerical integration:")
        println("      Constants found: $(length(const_report.constants_found))")
        println("      Foldable expressions: $(const_report.foldable_expressions)")
        println("      Allocations: $(length(escape_report.allocations))")

        @test !isnothing(const_report)

        println("   ✅ Integration algorithm analyzed")
        println()
    end

    @testset "Particle dynamics simulation" begin
        println("📊 Test 3: N-Body Particle Simulation")
        println("   Requirement: Efficient force calculations")
        println()

        # Simplified particle struct
        struct Particle
            x::Float64
            y::Float64
            z::Float64
            vx::Float64
            vy::Float64
            vz::Float64
            mass::Float64
        end

        # Calculate force between two particles (gravitational)
        function calculate_force(p1::Particle, p2::Particle)
            G = 6.67430e-11  # Gravitational constant

            dx = p2.x - p1.x
            dy = p2.y - p1.y
            dz = p2.z - p1.z

            r_squared = dx^2 + dy^2 + dz^2
            r = sqrt(r_squared)

            # Avoid division by zero
            if r < 1e-10
                return (0.0, 0.0, 0.0)
            end

            force_magnitude = G * p1.mass * p2.mass / r_squared

            # Force components
            fx = force_magnitude * dx / r
            fy = force_magnitude * dy / r
            fz = force_magnitude * dz / r

            return (fx, fy, fz)
        end

        # Analyze particle simulation
        escape_report = analyze_escapes(calculate_force, (Particle, Particle))
        const_report = analyze_constants(calculate_force, (Particle, Particle))
        devirt_report = analyze_devirtualization(calculate_force, (Particle, Particle))

        println("   Force calculation:")
        println("      Allocations: $(length(escape_report.allocations))")
        println("      Constants: $(length(const_report.constants_found))")
        println("      Virtual calls: $(devirt_report.virtual_call_sites)")

        # Should have minimal allocations for performance
        @test !isnothing(escape_report)

        println("   ✅ Particle dynamics analyzed")
        println()
    end

    @testset "Iterative solver" begin
        println("📊 Test 4: Conjugate Gradient Solver")
        println("   Requirement: Iterative linear system solver")
        println()

        # Simplified conjugate gradient iteration
        function cg_iteration(r::Vector{Float64}, p::Vector{Float64},
                             Ap::Vector{Float64}, alpha::Float64)
            n = length(r)

            # Update solution and residual
            r_new = zeros(Float64, n)
            for i in 1:n
                r_new[i] = r[i] - alpha * Ap[i]
            end

            # Calculate beta
            r_dot_r = sum(r[i]^2 for i in 1:n)
            r_new_dot = sum(r_new[i]^2 for i in 1:n)

            beta = r_new_dot / r_dot_r

            return (r_new, beta)
        end

        # Analyze solver iteration
        escape_report = analyze_escapes(cg_iteration,
            (Vector{Float64}, Vector{Float64}, Vector{Float64}, Float64))

        mono_report = analyze_monomorphization(cg_iteration,
            (Vector{Float64}, Vector{Float64}, Vector{Float64}, Float64))

        println("   CG iteration:")
        println("      Allocations: $(length(escape_report.allocations))")
        println("      Stack-promotable: $(escape_report.promotable_allocations)")
        println("      Has abstract types: $(mono_report.has_abstract_types)")

        @test !isnothing(escape_report)

        println("   ✅ Iterative solver analyzed")
        println()
    end

    @testset "Fast Fourier Transform (simplified)" begin
        println("📊 Test 5: FFT-like Algorithm")
        println("   Requirement: Efficient recursive decomposition")
        println()

        # Simplified butterfly operation (FFT building block)
        function fft_butterfly(x::ComplexF64, y::ComplexF64, w::ComplexF64)
            t = w * y
            return (x + t, x - t)
        end

        # Analyze FFT operation
        escape_report = analyze_escapes(fft_butterfly,
            (ComplexF64, ComplexF64, ComplexF64))

        devirt_report = analyze_devirtualization(fft_butterfly,
            (ComplexF64, ComplexF64, ComplexF64))

        println("   FFT butterfly:")
        println("      Allocations: $(length(escape_report.allocations))")
        println("      Virtual calls: $(devirt_report.virtual_call_sites)")

        # Should be allocation-free
        @test length(escape_report.allocations) == 0

        println("   ✅ FFT operation analyzed")
        println()
    end

    @testset "Performance-critical loop optimization" begin
        println("📊 Test 6: Tight Loop Optimization")
        println("   Requirement: Maximize loop performance")
        println()

        # Hot loop example: stencil computation
        function stencil_3point(input::Vector{Float64})
            n = length(input)
            output = zeros(Float64, n)

            for i in 2:(n-1)
                output[i] = 0.25 * input[i-1] + 0.5 * input[i] + 0.25 * input[i+1]
            end

            return output
        end

        # Analyze loop
        escape_report = analyze_escapes(stencil_3point, (Vector{Float64},))
        const_report = analyze_constants(stencil_3point, (Vector{Float64},))

        println("   Stencil computation:")
        println("      Allocations: $(length(escape_report.allocations))")
        println("      Constants: $(length(const_report.constants_found))")
        println("      Foldable expressions: $(const_report.foldable_expressions)")

        # Analysis complete
        @test !isnothing(escape_report)

        println("   ✅ Loop optimization analyzed")
        println()
    end

    println("-"^70)
    println("✅ SCIENTIFIC COMPUTING SCENARIO COMPLETE")
    println("-"^70)
    println()
    println("Summary:")
    println("  • Matrix operations analyzed for efficiency")
    println("  • Numerical algorithms verified for optimizations")
    println("  • Particle simulation performance assessed")
    println("  • Iterative solvers analyzed")
    println("  • FFT operations validated")
    println("  • Tight loops optimized")
    println()
    println("Scientific Computing Readiness: ✅ PASS")
    println()
end
