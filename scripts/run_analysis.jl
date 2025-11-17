#!/usr/bin/env julia

# Quick analysis script for StaticCompiler.jl
# Run with: julia scripts/run_analysis.jl

using Pkg
Pkg.activate(".")
using StaticCompiler

println("="^70)
println("StaticCompiler.jl - Project Analysis")
println("="^70)
println()

# Configure analysis here
# Replace with your actual module name
const MODULE_TO_ANALYZE = :StaticCompiler
const QUALITY_THRESHOLD = 70

try
    println("Analyzing module: $MODULE_TO_ANALYZE")
    println("Quality threshold: $QUALITY_THRESHOLD/100")
    println()

    # Run module-wide analysis
    analysis = analyze_module(eval(MODULE_TO_ANALYZE),
                             threshold=QUALITY_THRESHOLD,
                             verbose=true)

    # Generate reports
    results = analysis[:results]
    timestamp = replace(string(now()), ":" => "-")

    println()
    println("Generating reports...")

    # Generate CI reports
    report_path = "reports/analysis_$(timestamp)"
    mkpath("reports")
    generate_ci_report(results, report_path)

    println("✅ Reports generated:")
    println("   Markdown: $(report_path).md")
    println("   JSON:     $(report_path).json")
    println()

    # Check quality gate
    summary = analysis[:summary]

    if summary[:average_score] >= QUALITY_THRESHOLD
        println("✅ Analysis PASSED - Quality threshold met")
        exit(0)
    else
        println("⚠️  Analysis WARNING - Quality below threshold")
        println("   Current: $(summary[:average_score])/100")
        println("   Required: $QUALITY_THRESHOLD/100")
        exit(1)
    end

catch e
    println("❌ Error during analysis:")
    println(e)
    exit(1)
end
