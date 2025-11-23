# Compilation Templates/Presets
# Pre-configured settings for common compilation scenarios

"""
    CompilationTemplate

A named set of compilation parameters optimized for specific use cases.

# Fields
- `name::Symbol`: Template name (e.g., :embedded, :performance)
- `description::String`: Human-readable description
- `params::NamedTuple`: Compilation parameters
"""
struct CompilationTemplate
    name::Symbol
    description::String
    params::NamedTuple
end

"""
    BUILTIN_TEMPLATES

Dictionary of built-in compilation templates for common scenarios.

# Available Templates

## `:embedded` - Embedded/IoT Systems
Optimized for minimal binary size and no external dependencies.
- Small binaries (<100KB typical)
- No standard library dependencies
- Static linking
- Size optimization
- Use for: IoT devices, microcontrollers, resource-constrained systems

## `:performance` - Maximum Performance
Optimized for execution speed, larger binaries acceptable.
- Aggressive optimization
- Verification enabled (ensure quality)
- Header generation for benchmarking
- Use for: HPC, computation-heavy workloads, servers

## `:portable` - Broad Compatibility
Conservative settings for maximum portability.
- Standard optimization level
- Compatible with older systems
- Minimal assumptions
- Use for: Distribution, unknown target systems

## `:debugging` - Development/Debugging
Optimized for debugging and development.
- Verification enabled with lower threshold
- Analysis export for diagnostics
- Helpful error messages
- Use for: Development, troubleshooting, learning

## `:production` - Production Deployment
Balanced settings for production use.
- Strict verification (high quality bar)
- Header generation for API clarity
- Analysis export for documentation
- Use for: Production deployments, releases

## `:default` - Balanced Default
Standard balanced settings (current StaticCompiler defaults).
- No verification
- No header generation
- Standard compilation
- Use for: General purpose, when you know your code is good
"""
const BUILTIN_TEMPLATES = Dict{Symbol, CompilationTemplate}(
    :embedded => CompilationTemplate(
        :embedded,
        "Embedded/IoT systems: minimal size, no stdlib",
        (
            verify = true,
            min_score = 90,  # Strict - embedded must be clean
            suggest_fixes = true,
            export_analysis = false,
            generate_header = true,  # For integration with C
            # Future: optimize_for_size, strip_debug, etc.
        )
    ),

    :performance => CompilationTemplate(
        :performance,
        "Maximum performance: aggressive optimization",
        (
            verify = true,
            min_score = 85,  # High quality for performance
            suggest_fixes = true,
            export_analysis = false,
            generate_header = true,  # For benchmarking harness
        )
    ),

    :portable => CompilationTemplate(
        :portable,
        "Broad compatibility: conservative settings",
        (
            verify = true,
            min_score = 75,  # More permissive
            suggest_fixes = true,
            export_analysis = false,
            generate_header = true,
        )
    ),

    :debugging => CompilationTemplate(
        :debugging,
        "Development/debugging: helpful diagnostics",
        (
            verify = true,
            min_score = 70,  # Permissive for development
            suggest_fixes = true,
            export_analysis = true,  # Export for analysis
            generate_header = true,
        )
    ),

    :production => CompilationTemplate(
        :production,
        "Production deployment: strict quality, full documentation",
        (
            verify = true,
            min_score = 90,  # Very strict for production
            suggest_fixes = true,
            export_analysis = true,  # Keep records
            generate_header = true,  # API documentation
        )
    ),

    :default => CompilationTemplate(
        :default,
        "Balanced default: standard StaticCompiler behavior",
        (
            verify = false,
            min_score = 80,
            suggest_fixes = true,
            export_analysis = false,
            generate_header = false,
        )
    ),
)

"""
    get_template(name::Symbol) -> CompilationTemplate

Get a built-in compilation template by name.

# Arguments
- `name::Symbol`: Template name (:embedded, :performance, :portable, :debugging, :production, :default)

# Returns
The requested CompilationTemplate

# Throws
ArgumentError if template name is not recognized

# Examples
```julia
julia> template = get_template(:embedded)

julia> template.description
"Embedded/IoT systems: minimal size, no stdlib"

julia> template.params
(verify = true, min_score = 90, ...)
```
"""
function get_template(name::Symbol)
    if !haskey(BUILTIN_TEMPLATES, name)
        available = join(sort(collect(keys(BUILTIN_TEMPLATES))), ", :")
        throw(ArgumentError("Unknown template :$name. Available templates: :$available"))
    end
    return BUILTIN_TEMPLATES[name]
end

"""
    list_templates() -> Vector{Symbol}

List all available built-in template names.

# Returns
Vector of template names

# Examples
```julia
julia> list_templates()
6-element Vector{Symbol}:
 :debugging
 :default
 :embedded
 :performance
 :portable
 :production
```
"""
function list_templates()
    return sort(collect(keys(BUILTIN_TEMPLATES)))
end

"""
    show_template(name::Symbol)

Display detailed information about a compilation template.

# Arguments
- `name::Symbol`: Template name

# Examples
```julia
julia> show_template(:embedded)
Template: embedded
Description: Embedded/IoT systems: minimal size, no stdlib

Settings:
  verify = true
  min_score = 90
  suggest_fixes = true
  export_analysis = false
  generate_header = true
```
"""
function show_template(name::Symbol)
    template = get_template(name)

    println("Template: ", template.name)
    println("Description: ", template.description)
    println()
    println("Settings:")
    for (key, value) in pairs(template.params)
        println("  $key = $value")
    end
    return
end

"""
    show_all_templates()

Display information about all available templates.
"""
function show_all_templates()
    templates = sort(collect(values(BUILTIN_TEMPLATES)), by = t -> t.name)

    println("Available Compilation Templates")
    println("="^70)
    println()

    for template in templates
        println(":" * string(template.name))
        println("  ", template.description)
        println()
    end

    println("Use get_template(:name) to get template parameters")
    return println("Use show_template(:name) for detailed settings")
end

"""
    apply_template(name::Symbol, custom_params::NamedTuple) -> NamedTuple

Apply a template and optionally override specific parameters.

# Arguments
- `name::Symbol`: Template name
- `custom_params::NamedTuple`: Custom parameters to override template defaults

# Returns
NamedTuple with merged parameters (template + custom overrides)

# Examples
```julia
julia> params = apply_template(:embedded, (min_score=95,))
(verify = true, min_score = 95, suggest_fixes = true, ...)

julia> params = apply_template(:performance, (export_analysis=true,))
(verify = true, min_score = 85, export_analysis = true, ...)
```
"""
function apply_template(name::Symbol, custom_params::NamedTuple = NamedTuple())
    template = get_template(name)
    # Merge template params with custom overrides
    return merge(template.params, custom_params)
end

"""
    compile_with_template(template::Symbol, f::Function, types::Tuple,
                          path::String, name::String;
                          custom_params::NamedTuple=NamedTuple(),
                          kwargs...)

Compile using a predefined template, optionally overriding specific parameters.

This is a convenience function that applies a template and calls compile_shlib.

# Arguments
- `template::Symbol`: Template name (:embedded, :performance, etc.)
- `f::Function`: Function to compile
- `types::Tuple`: Argument types
- `path::String`: Output directory
- `name::String`: Library name
- `custom_params::NamedTuple`: Override template parameters
- `kwargs...`: Additional compile_shlib parameters

# Examples
```julia
# Use embedded template with defaults
julia> compile_with_template(:embedded, myfunc, (Int,), "./", "myfunc")

# Use performance template, but lower the score threshold
julia> compile_with_template(:performance, myfunc, (Int,), "./", "myfunc",
                              custom_params=(min_score=75,))

# Use debugging template
julia> compile_with_template(:debugging, myfunc, (Int,), "./", "myfunc")
```
"""
function compile_with_template(
        template::Symbol, f::Function, types::Tuple,
        path::String, name::String;
        custom_params::NamedTuple = NamedTuple(),
        kwargs...
    )
    # Get template parameters
    params = apply_template(template, custom_params)

    # Display template info
    template_obj = get_template(template)
    println("Using template: :$(template)")
    println("  ", template_obj.description)
    println()

    # Compile with template parameters
    return compile_shlib(f, types, path, name; params..., kwargs...)
end

"""
    compile_with_template(template::Symbol, funcs::Vector, path::String;
                          filename::String="libfoo",
                          custom_params::NamedTuple=NamedTuple(),
                          kwargs...)

Compile multiple functions using a predefined template.

# Arguments
- `template::Symbol`: Template name
- `funcs::Vector`: Vector of (function, types) tuples
- `path::String`: Output directory
- `filename::String`: Library filename
- `custom_params::NamedTuple`: Override template parameters
- `kwargs...`: Additional compile_shlib parameters

# Examples
```julia
functions = [(f1, (Int,)), (f2, (Float64,))]

# Production build with strict verification
julia> compile_with_template(:production, functions, "./",
                              filename="mylib")

# Embedded build
julia> compile_with_template(:embedded, functions, "./",
                              filename="embedded_lib")
```
"""
function compile_with_template(
        template::Symbol, funcs::Vector, path::String;
        filename::String = "libfoo",
        custom_params::NamedTuple = NamedTuple(),
        kwargs...
    )
    # Get template parameters
    params = apply_template(template, custom_params)

    # Display template info
    template_obj = get_template(template)
    println("Using template: :$(template)")
    println("  ", template_obj.description)
    println()

    # Compile with template parameters
    return compile_shlib(funcs, path; filename, params..., kwargs...)
end

# Export public API
export CompilationTemplate, BUILTIN_TEMPLATES
export get_template, list_templates, show_template, show_all_templates
export apply_template, compile_with_template
