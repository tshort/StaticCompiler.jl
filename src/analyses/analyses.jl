# Compiler Analysis Infrastructure for StaticCompiler.jl
# Provides optimization analysis and reporting capabilities

module Analyses

# Include all analysis modules
include("escape_analysis.jl")
include("monomorphization_analysis.jl")
include("devirtualization_analysis.jl")
include("constant_propagation.jl")
include("lifetime_analysis.jl")
include("quick_check.jl")
include("suggestions.jl")
include("macros.jl")
include("ci_integration.jl")
include("project_scanner.jl")
include("caching.jl")

# Re-export all analysis functions and types
export analyze_escapes, EscapeAnalysisReport, AllocationInfo
export analyze_monomorphization, MonomorphizationReport, AbstractParameterInfo
export analyze_devirtualization, DevirtualizationReport, CallSiteInfo
export analyze_constants, ConstantPropagationReport, ConstantInfo
export analyze_lifetimes, LifetimeAnalysisReport, AllocationSite

# Re-export quick check utilities
export quick_check, CompilationReadinessReport
export print_readiness_report, batch_check, print_batch_summary
export verify_compilation_readiness, compare_reports
export export_report, import_report_summary

# Re-export optimization suggestions
export suggest_optimizations, suggest_optimizations_batch

# Re-export macros
export @analyze, @check_ready, @quick_check, @suggest_fixes

# Re-export CI/CD integration
export generate_ci_report, check_quality_gate
export generate_github_actions_summary, annotate_github_actions

# Re-export project scanning
export scan_module, scan_module_with_types
export analyze_module, compare_modules

# Re-export caching
export quick_check_cached, batch_check_cached
export clear_analysis_cache!, cache_stats, prune_cache!
export with_cache

end # module
