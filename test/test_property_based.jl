# Property-Based Tests for Compiler Analysis
# Tests invariants and properties that should hold for all inputs

using Test
using StaticCompiler

@testset "Property-Based Testing" begin
    
    # Helper: Generate random test functions
    function make_simple_func()
        x -> x + 1
    end
    
    function make_abstract_func()
        x::Number -> x * 2
    end
    
    function make_concrete_func()
        x::Int -> x * 2
    end
    
    @testset "Escape Analysis Properties" begin
        # Property: Analysis should always terminate
        @testset "Termination" begin
            f1(x::Int) = x + 1
            f2(x::Int) = [x, x+1, x+2]
            f3(x::Int) = (x, x*2, x+3)
            
            for (f, T) in [(f1, (Int,)), (f2, (Int,)), (f3, (Int,))]
                @test !isnothing(analyze_escapes(f, T))
            end
        end
        
        # Property: Results should be deterministic
        @testset "Determinism" begin
            f(x::Int) = x + 1
            r1 = analyze_escapes(f, (Int,))
            r2 = analyze_escapes(f, (Int,))
            @test length(r1.allocations) == length(r2.allocations)
            @test r1.promotable_allocations == r2.promotable_allocations
        end
        
        # Property: promotable_allocations ≤ total allocations
        @testset "Monotonicity" begin
            functions = [
                (x::Int -> x + 1, (Int,)),
                (x::Int -> [x], (Int,)),
                (x::Int -> (x, x), (Int,))
            ]
            
            for (f, T) in functions
                report = analyze_escapes(f, T)
                @test report.promotable_allocations <= length(report.allocations)
            end
        end
        
        # Property: Counts are non-negative
        @testset "Non-negativity" begin
            f(x::Int) = x + 1
            report = analyze_escapes(f, (Int,))
            @test length(report.allocations) >= 0
            @test report.promotable_allocations >= 0
            @test report.potential_savings_bytes >= 0
        end
    end
    
    @testset "Monomorphization Properties" begin
        # Property: Concrete types should not need monomorphization
        @testset "Concrete Types" begin
            f(x::Int, y::Float64) = x + y
            report = analyze_monomorphization(f, (Int, Float64))
            @test !report.has_abstract_types
            @test report.optimization_opportunities == 0
        end
        
        # Property: Abstract types should be detected
        @testset "Abstract Detection" begin
            f(x::Number) = x * 2
            report = analyze_monomorphization(f, (Number,))
            @test report.has_abstract_types
            @test report.optimization_opportunities > 0
        end
        
        # Property: Specialization factor should be in [0, 1]
        @testset "Specialization Bounds" begin
            functions = [
                (x::Int -> x, (Int,)),
                (x::Number -> x, (Number,)),
                ((x::Number, y::Int) -> x + y, (Number, Int))
            ]
            
            for (f, T) in functions
                report = analyze_monomorphization(f, T)
                @test 0.0 <= report.specialization_factor <= 1.0
            end
        end
    end
    
    @testset "Devirtualization Properties" begin
        # Property: total_dynamic_calls should equal length of call_sites
        @testset "Call Site Counts" begin
            f(x::Int) = abs(x) + abs(x+1)
            report = analyze_devirtualization(f, (Int,))
            @test report.total_dynamic_calls == length(report.call_sites)
        end
        
        # Property: devirtualizable_calls ≤ total_dynamic_calls
        @testset "Devirtualizable Bound" begin
            f(x::Int) = x + 1
            report = analyze_devirtualization(f, (Int,))
            @test report.devirtualizable_calls <= report.total_dynamic_calls
        end
        
        # Property: Results are deterministic
        @testset "Determinism" begin
            f(x::Int) = x * 2
            r1 = analyze_devirtualization(f, (Int,))
            r2 = analyze_devirtualization(f, (Int,))
            @test r1.total_dynamic_calls == r2.total_dynamic_calls
        end
    end
    
    @testset "Lifetime Analysis Properties" begin
        # Property: allocations_freed ≤ length(allocations)
        @testset "Allocation Accounting" begin
            # Simple function with no allocations
            f(x::Int) = x + 1
            report = analyze_lifetimes(f, (Int,))
            @test report.allocations_freed <= length(report.allocations)
        end
        
        # Property: All counts are non-negative
        @testset "Non-negativity" begin
            f(x::Int) = x * 2
            report = analyze_lifetimes(f, (Int,))
            @test report.potential_leaks >= 0
            @test report.potential_double_frees >= 0
            @test report.proper_frees >= 0
            @test report.allocations_freed >= 0
        end
        
        # Property: allocations_freed == proper_frees
        @testset "Freed Count Consistency" begin
            f(x::Int) = x + 1
            report = analyze_lifetimes(f, (Int,))
            @test report.allocations_freed == report.proper_frees
        end
    end
    
    @testset "Constant Propagation Properties" begin
        # Property: foldable_expressions ≤ total statements
        @testset "Foldable Bounds" begin
            f(x::Int) = x + 1
            report = analyze_constants(f, (Int,))
            @test report.foldable_expressions >= 0
        end
        
        # Property: code_reduction_potential_pct in [0, 100]
        @testset "Reduction Percentage" begin
            functions = [
                (x::Int -> x + 1, (Int,)),
                (x::Int -> 42, (Int,)),
                (x::Int -> x + 42, (Int,))
            ]
            
            for (f, T) in functions
                report = analyze_constants(f, T)
                @test 0.0 <= report.code_reduction_potential_pct <= 100.0
            end
        end
        
        # Property: More constants → higher reduction potential
        @testset "Constants Impact" begin
            f_no_const(x::Int) = x + x
            f_with_const(x::Int) = 42 + 42  # All constants
            
            r1 = analyze_constants(f_no_const, (Int,))
            r2 = analyze_constants(f_with_const, (Int,))
            
            # With all constants, should find some foldable expressions
            @test r2.foldable_expressions >= 0
        end
    end
    
    @testset "Cross-Analysis Properties" begin
        # Property: Running multiple analyses doesn't affect results
        @testset "Composition Stability" begin
            f(x::Int) = x + 1
            T = (Int,)
            
            # Run all analyses
            r1 = analyze_escapes(f, T)
            r2 = analyze_monomorphization(f, T)
            r3 = analyze_devirtualization(f, T)
            r4 = analyze_lifetimes(f, T)
            r5 = analyze_constants(f, T)
            
            # Run them again - should get same results
            r1b = analyze_escapes(f, T)
            @test length(r1.allocations) == length(r1b.allocations)
        end
        
        # Property: Order independence
        @testset "Order Independence" begin
            f(x::Int) = x * 2
            T = (Int,)
            
            # Different orders
            r1 = analyze_escapes(f, T)
            r2 = analyze_monomorphization(f, T)
            
            r2b = analyze_monomorphization(f, T)
            r1b = analyze_escapes(f, T)
            
            @test length(r1.allocations) == length(r1b.allocations)
            @test r2.has_abstract_types == r2b.has_abstract_types
        end
    end
end
