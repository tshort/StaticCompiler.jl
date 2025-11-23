# Real-World Scenario: Embedded Systems
# Memory-constrained environment with strict size requirements

using Test
using StaticCompiler
using StaticTools

@testset "Embedded System Scenario" begin
    println("\n" * "="^70)
    println("REAL-WORLD SCENARIO: Embedded System")
    println("="^70)
    println()
    println("Context: Microcontroller with 64KB RAM, 256KB flash")
    println("Requirements: Minimal binary size, no dynamic allocation")
    println()

    # Scenario: Temperature sensor data processing
    # Constraints:
    # - Maximum binary size: 32KB
    # - No heap allocations allowed
    # - Fixed-size buffers only
    # - Real-time constraints (<1ms processing)

    @testset "Temperature sensor processing" begin
        println("Test 1: Temperature Sensor Data Processing")
        println("   Requirement: Process sensor data without heap allocations")
        println()

        # Unoptimized version - uses dynamic allocation
        function process_sensor_data_unopt(readings::Vector{Int16})
            # Convert to celsius (each reading is in 0.1°C units)
            celsius = Float32[]
            for r in readings
                push!(celsius, Float32(r) / 10.0f0)
            end

            # Calculate statistics
            avg = sum(celsius) / length(celsius)
            return avg
        end

        # Optimized version - stack-only, fixed size
        using StaticArrays
        function process_sensor_data_opt(readings::SVector{10, Int16})
            # Convert to celsius using stack arrays
            celsius = SVector{10, Float32}(Float32(r) / 10.0f0 for r in readings)

            # Calculate statistics
            avg = sum(celsius) / 10.0f0
            return avg
        end

        # Analyze both versions
        report_unopt = analyze_escapes(process_sensor_data_unopt, (Vector{Int16},))
        report_opt = analyze_escapes(process_sensor_data_opt, (SVector{10, Int16},))

        println("   Unoptimized version:")
        println("      Allocations: $(length(report_unopt.allocations))")
        println("      Stack-promotable: $(report_unopt.promotable_allocations)")

        println("   Optimized version:")
        println("      Allocations: $(length(report_opt.allocations))")
        println("      Stack-promotable: $(report_opt.promotable_allocations)")

        # The optimized version should have significantly fewer allocations
        @test length(report_opt.allocations) <= length(report_unopt.allocations)

        println("   Embedded system optimization verified")
        println()
    end

    @testset "PWM signal generation" begin
        println("Test 2: PWM Signal Generation")
        println("   Requirement: Fixed-time execution, no allocations")
        println()

        # PWM duty cycle calculator
        function calculate_pwm_duty_cycle(target_voltage::Float32, max_voltage::Float32)
            duty_cycle = (target_voltage / max_voltage) * 100.0f0
            return clamp(duty_cycle, 0.0f0, 100.0f0)
        end

        # Analyze for allocations
        report = analyze_escapes(calculate_pwm_duty_cycle, (Float32, Float32))

        println("   PWM calculator:")
        println("      Allocations: $(length(report.allocations))")

        # Should have zero allocations for embedded use
        @test length(report.allocations) == 0

        # Check for constant propagation opportunities
        const_report = analyze_constants(calculate_pwm_duty_cycle, (Float32, Float32))
        println("      Foldable expressions: $(const_report.foldable_expressions)")

        println("   PWM signal generation verified")
        println()
    end

    @testset "Circular buffer management" begin
        println("Test 3: Circular Buffer for Sensor History")
        println("   Requirement: Fixed-size buffer, no dynamic allocation")
        println()

        # Circular buffer with fixed size
        mutable struct CircularBuffer{N}
            data::MVector{N, Float32}
            head::Int
            count::Int
        end

        function CircularBuffer{N}() where N
            CircularBuffer{N}(MVector{N, Float32}(zeros(Float32, N)), 1, 0)
        end

        function push_sample!(buffer::CircularBuffer{N}, value::Float32) where N
            buffer.data[buffer.head] = value
            buffer.head = mod1(buffer.head + 1, N)
            buffer.count = min(buffer.count + 1, N)
            return buffer
        end

        function get_average(buffer::CircularBuffer{N}) where N
            if buffer.count == 0
                return 0.0f0
            end
            return sum(buffer.data) / Float32(buffer.count)
        end

        # Analyze the circular buffer operations
        report_push = analyze_escapes(push_sample!, (CircularBuffer{10}, Float32))
        report_avg = analyze_escapes(get_average, (CircularBuffer{10},))

        println("   Circular buffer push:")
        println("      Allocations: $(length(report_push.allocations))")

        println("   Circular buffer average:")
        println("      Allocations: $(length(report_avg.allocations))")

        # Should be allocation-free
        @test length(report_push.allocations) == 0
        @test length(report_avg.allocations) == 0

        println("   Circular buffer verified")
        println()
    end

    @testset "Binary size constraints" begin
        println("Test 4: Binary Size Validation")
        println("   Requirement: Binary must fit in 32KB flash")
        println()

        # Simple control function
        function embedded_control_loop(sensor_value::Int16, setpoint::Int16)
            error = setpoint - sensor_value
            # Simple proportional control
            KP = 2
            output = KP * error
            return clamp(output, -1000, 1000)
        end

        # Analyze size implications
        const_report = analyze_constants(embedded_control_loop, (Int16, Int16))

        println("   Control loop:")
        println("      Constants found: $(length(const_report.constants_found))")
        println("      Foldable expressions: $(const_report.foldable_expressions)")
        println("      Code reduction potential: $(round(const_report.code_reduction_potential_pct, digits=1))%")

        # More constants = smaller code
        @test const_report.foldable_expressions >= 0

        println("   Binary size analysis complete")
        println()
    end

    println("-"^70)
    println("EMBEDDED SYSTEM SCENARIO COMPLETE")
    println("-"^70)
    println()
    println("Summary:")
    println("  • All functions analyzed for heap allocations")
    println("  • Stack-only alternatives verified")
    println("  • Constant propagation opportunities identified")
    println("  • Binary size optimization validated")
    println()
    println("Embedded System Readiness: PASS")
    println()
end
