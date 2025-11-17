# Compiler Analysis Infrastructure for StaticCompiler.jl
# Provides optimization analysis and reporting capabilities

module Analyses

# Include all analysis modules
include("escape_analysis.jl")
include("monomorphization_analysis.jl")
include("devirtualization_analysis.jl")
include("constant_propagation.jl")
include("lifetime_analysis.jl")

# Re-export all analysis functions and types
export analyze_escapes, EscapeAnalysisReport, AllocationInfo
export analyze_monomorphization, MonomorphizationReport, AbstractParameterInfo
export analyze_devirtualization, DevirtualizationReport, CallSiteInfo
export analyze_constants, ConstantPropagationReport, ConstantInfo
export analyze_lifetimes, LifetimeAnalysisReport, AllocationSite

end # module
