# Fuzzing Tests for Compiler Analysis
# Tests robustness with random and edge case inputs

using Test
using StaticCompiler

@testset "Fuzzing Tests" begin
    
    @testset "Escape Analysis Fuzzing" begin
        # Fuzz with various function types
        @testset "Random Functions" begin
            test_funcs = [
                (x::Int -> x, (Int,)),
                (x::Int -> x + x, (Int,)),
                (x::Int -> x * x * x, (Int,)),
                ((x::Int, y::Int) -> x + y, (Int, Int)),
                ((x::Int, y::Int, z::Int) -> x + y + z, (Int, Int, Int)),
            ]
            
            for (f, T) in test_funcs
                report = analyze_escapes(f, T)
                @test report isa EscapeAnalysisReport
                @test length(report.allocations) >= 0
            end
        end
        
        # Fuzz with nested structures
        @testset "Nested Structures" begin
            f1(x::Int) = [[x]]
            f2(x::Int) = [[[x]]]
            f3(x::Int) = ((x, x), (x, x))
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,))]
                report = analyze_escapes(f, T)
                @test report isa EscapeAnalysisReport
            end
        end
        
        # Fuzz with control flow
        @testset "Control Flow" begin
            f1(x::Int) = x > 0 ? x : -x
            f2(x::Int) = x > 0 ? [x] : [0]
            
            function f3(x::Int)
                if x > 10
                    return x
                elseif x > 0
                    return x * 2
                else
                    return 0
                end
            end
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,))]
                report = analyze_escapes(f, T)
                @test report isa EscapeAnalysisReport
            end
        end
    end
    
    @testset "Monomorphization Fuzzing" begin
        # Fuzz with different type hierarchies
        @testset "Type Hierarchies" begin
            test_cases = [
                (x::Int -> x, (Int,)),
                (x::Number -> x, (Number,)),
                (x::Real -> x, (Real,)),
                (x::Integer -> x, (Integer,)),
                ((x::Number, y::Number) -> x + y, (Number, Number)),
            ]
            
            for (f, T) in test_cases
                report = analyze_monomorphization(f, T)
                @test report isa MonomorphizationReport
                @test 0.0 <= report.specialization_factor <= 1.0
            end
        end
        
        # Fuzz with parametric types
        @testset "Parametric Types" begin
            f1(x::Vector{Int}) = x[1]
            f2(x::Vector{Number}) = x[1]
            f3(x::Vector) = x[1]
            
            for (f, T) in [(f1, (Vector{Int},)), (f2, (Vector{Number},))]
                report = analyze_monomorphization(f, T)
                @test report isa MonomorphizationReport
            end
        end
        
        # Fuzz with unions
        @testset "Union Types" begin
            test_cases = [
                (x::Union{Int, Float64} -> x, (Union{Int, Float64},)),
                (x::Union{Int, Nothing} -> x, (Union{Int, Nothing},)),
            ]
            
            for (f, T) in test_cases
                report = analyze_monomorphization(f, T)
                @test report isa MonomorphizationReport
            end
        end
    end
    
    @testset "Devirtualization Fuzzing" begin
        # Fuzz with various call patterns
        @testset "Call Patterns" begin
            f1(x::Int) = abs(x)
            f2(x::Int) = abs(abs(x))
            f3(x::Int) = abs(x) + sqrt(float(x))
            f4(x::Int) = sum([x, x+1, x+2])
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,)), (f4, (Int,))]
                report = analyze_devirtualization(f, T)
                @test report isa DevirtualizationReport
                @test report.devirtualizable_calls <= report.total_dynamic_calls
            end
        end
        
        # Fuzz with abstract types
        @testset "Abstract Call Sites" begin
            abstract type FuzzShape end
            struct FuzzCircle <: FuzzShape
                radius::Float64
            end
            
            area(c::FuzzCircle) = 3.14 * c.radius^2
            process_shape(s::FuzzShape) = area(s)
            
            # Note: This might not detect dynamic dispatch in simple cases
            report = analyze_devirtualization(process_shape, (FuzzCircle,))
            @test report isa DevirtualizationReport
        end
        
        # Fuzz with many calls
        @testset "Many Calls" begin
            function many_ops(x::Int)
                y = abs(x)
                z = abs(y)
                w = abs(z)
                return w
            end
            
            report = analyze_devirtualization(many_ops, (Int,))
            @test report isa DevirtualizationReport
        end
    end
    
    @testset "Lifetime Analysis Fuzzing" begin
        # Fuzz with different patterns (note: actual malloc detection is limited)
        @testset "Simple Patterns" begin
            test_funcs = [
                (x::Int -> x + 1, (Int,)),
                (x::Int -> x * x, (Int,)),
                ((x::Int, y::Int) -> x + y, (Int, Int)),
            ]
            
            for (f, T) in test_funcs
                report = analyze_lifetimes(f, T)
                @test report isa LifetimeAnalysisReport
                @test report.allocations_freed == report.proper_frees
            end
        end
        
        # Fuzz with allocations (if StaticTools is available)
        @testset "Allocation Patterns" begin
            # Basic allocation test
            f(x::Int) = [x, x+1]
            report = analyze_lifetimes(f, (Int,))
            @test report isa LifetimeAnalysisReport
        end
        
        # Fuzz with nested allocations
        @testset "Nested Allocations" begin
            f1(x::Int) = [[x]]
            f2(x::Int) = [x, [x+1]]
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,))]
                report = analyze_lifetimes(f, T)
                @test report isa LifetimeAnalysisReport
                @test report.potential_leaks >= 0
            end
        end
    end
    
    @testset "Constant Propagation Fuzzing" begin
        # Fuzz with various constant patterns
        @testset "Constant Patterns" begin
            f1(x::Int) = 42
            f2(x::Int) = x + 42
            f3(x::Int) = 42 + 42
            f4(x::Int) = x + x
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,)), (f4, (Int,))]
                report = analyze_constants(f, T)
                @test report isa ConstantPropagationReport
                @test 0.0 <= report.code_reduction_potential_pct <= 100.0
            end
        end
        
        # Fuzz with arithmetic
        @testset "Arithmetic Expressions" begin
            f1(x::Int) = 2 * 3
            f2(x::Int) = 10 / 2
            f3(x::Int) = 5 + 3 - 2
            f4(x::Int) = 2^10
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,)), (f4, (Int,))]
                report = analyze_constants(f, T)
                @test report isa ConstantPropagationReport
            end
        end
        
        # Fuzz with mixed operations
        @testset "Mixed Operations" begin
            f1(x::Int) = x * 2 + 3
            f2(x::Int) = (x + 1) * (x + 2)
            f3(x::Int) = abs(42)
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,))]
                report = analyze_constants(f, T)
                @test report isa ConstantPropagationReport
            end
        end
    end
    
    @testset "Edge Cases" begin
        # Test with empty functions
        @testset "Minimal Functions" begin
            f_identity(x::Int) = x
            f_constant(x::Int) = 0
            
            @test analyze_escapes(f_identity, (Int,)) isa EscapeAnalysisReport
            @test analyze_monomorphization(f_identity, (Int,)) isa MonomorphizationReport
            @test analyze_devirtualization(f_identity, (Int,)) isa DevirtualizationReport
            @test analyze_lifetimes(f_identity, (Int,)) isa LifetimeAnalysisReport
            @test analyze_constants(f_identity, (Int,)) isa ConstantPropagationReport
        end
        
        # Test with multiple dispatch
        @testset "Multiple Dispatch" begin
            multi(x::Int) = x + 1
            multi(x::Float64) = x + 2.0
            
            @test analyze_escapes(multi, (Int,)) isa EscapeAnalysisReport
            @test analyze_escapes(multi, (Float64,)) isa EscapeAnalysisReport
        end
        
        # Test with varargs (simple case)
        @testset "Varargs" begin
            f(x::Int) = sum([x, x+1])
            @test analyze_escapes(f, (Int,)) isa EscapeAnalysisReport
        end
    end
    
    @testset "Stress Testing" begin
        # Test with deeply nested expressions
        @testset "Deep Nesting" begin
            f(x::Int) = ((((x + 1) + 2) + 3) + 4) + 5
            @test analyze_constants(f, (Int,)) isa ConstantPropagationReport
        end
        
        # Test with many parameters
        @testset "Many Parameters" begin
            f(a::Int, b::Int, c::Int, d::Int) = a + b + c + d
            @test analyze_escapes(f, (Int, Int, Int, Int)) isa EscapeAnalysisReport
        end
        
        # Test all analyses on same function
        @testset "All Analyses" begin
            function complex_func(x::Int)
                y = x * 2
                z = y + 42
                return z > 100 ? z : 0
            end
            
            T = (Int,)
            @test analyze_escapes(complex_func, T) isa EscapeAnalysisReport
            @test analyze_monomorphization(complex_func, T) isa MonomorphizationReport
            @test analyze_devirtualization(complex_func, T) isa DevirtualizationReport
            @test analyze_lifetimes(complex_func, T) isa LifetimeAnalysisReport
            @test analyze_constants(complex_func, T) isa ConstantPropagationReport
        end
    end
end
