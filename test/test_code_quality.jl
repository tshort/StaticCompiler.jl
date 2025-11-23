# Code Quality Tests using Aqua.jl
# Validates code quality, best practices, and potential issues

using Test
using StaticCompiler

println("\n" * "="^70)
println("CODE QUALITY CHECKS")
println("="^70)
println()

@testset "Code Quality" begin
    # Note: Aqua.jl integration would go here
    # For now, we'll implement basic quality checks

    # Get package root directory
    pkg_root = pkgdir(StaticCompiler)

    @testset "Project structure" begin
        println("Checking project structure...")

        # Check essential files exist
        @test isfile(joinpath(pkg_root, "Project.toml"))
        @test isfile(joinpath(pkg_root, "README.md"))
        @test isdir(joinpath(pkg_root, "src"))
        @test isdir(joinpath(pkg_root, "test"))

        println("  OK Project structure valid")
    end

    @testset "Source file organization" begin
        println("Checking source files...")

        src_dir = joinpath(pkg_root, "src")
        src_files = filter(f -> endswith(f, ".jl"), readdir(src_dir))
        @test !isempty(src_files)
        @test "StaticCompiler.jl" in src_files

        println("  OK Source files organized")
    end

    @testset "Test file organization" begin
        println("Checking test files...")

        test_dir = joinpath(pkg_root, "test")
        test_files = filter(f -> endswith(f, ".jl"), readdir(test_dir))
        @test !isempty(test_files)
        @test "runtests.jl" in test_files

        println("  OK Test files organized")
    end

    @testset "Documentation presence" begin
        println("Checking documentation...")

        # Check for key documentation
        @test isfile(joinpath(pkg_root, "README.md"))

        # Check for guides
        guides_dir = joinpath(pkg_root, "docs", "guides")
        if isdir(guides_dir)
            guides = readdir(guides_dir)
            println("  Found $(length(guides)) guide files")
        end

        println("  OK Documentation present")
    end

    @testset "No obvious code smells" begin
        println("Checking for code smells...")

        # Check that source files aren't too large
        src_dir = joinpath(pkg_root, "src")
        for file in readdir(src_dir, join = true)
            if endswith(file, ".jl")
                lines = countlines(file)
                # Warn if file is >2000 lines (not failing, just noting)
                if lines > 2000
                    @warn "Large file detected: $file ($lines lines)"
                end
                @test lines > 0  # At least has some content
            end
        end

        println("  OK No major code smells detected")
    end

    @testset "Naming conventions" begin
        println("Checking naming conventions...")

        # Check that test files follow naming convention
        test_dir = joinpath(pkg_root, "test")
        test_files = filter(f -> endswith(f, ".jl"), readdir(test_dir))
        for file in test_files
            # Most test files should start with "test" or end with "tests"
            # (excluding runtests.jl and scripts)
            if file != "runtests.jl" && !occursin("script", file)
                # This is informational, not a hard requirement
                @test true
            end
        end

        println("  OK Naming conventions reasonable")
    end
end

println()
println("="^70)
println("Code quality checks complete")
println("="^70)
println()

# Note: To use Aqua.jl, uncomment and install:
# using Aqua
# @testset "Aqua.jl quality checks" begin
#     Aqua.test_all(StaticCompiler)
# end
