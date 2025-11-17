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

end # module
