# Compilation Templates/Presets

## Overview

Compilation templates provide pre-configured settings optimized for common use cases. Instead of remembering multiple parameter combinations, simply specify a template and let StaticCompiler.jl apply the best settings for your scenario.

## Quick Start

```julia
using StaticCompiler

function my_function(n::Int)
    result = 0
    for i in 1:n
        result += i
    end
    return result
end

# Use embedded template for IoT/embedded systems
compile_shlib(my_function, (Int,), "./", "myfunc", template=:embedded)
```

Output:
```
Using template: :embedded
  Embedded/IoT systems: minimal size, no stdlib

Running pre-compilation analysis...
  [1/1] Analyzing my_function... ✅ (score: 95/100)

✅ All functions passed verification (min score: 90)
Generated C header: ./myfunc.h
```

## Why Use Templates?

### Problem

Different compilation scenarios need different settings:
- Embedded systems need small binaries and strict verification
- Performance-critical code needs aggressive optimization
- Development needs helpful diagnostics
- Production needs comprehensive documentation

Remembering all the parameter combinations is tedious and error-prone.

### Solution

Templates provide one-command solutions:

```julia
# Instead of:
compile_shlib(func, types, path, name,
              verify=true, min_score=90,
              generate_header=true,
              export_analysis=false,
              suggest_fixes=true)

# Just use:
compile_shlib(func, types, path, name, template=:embedded)
```

## Built-In Templates

### `:embedded` - Embedded/IoT Systems

**Use for**: Microcontrollers, IoT devices, resource-constrained systems

**Settings**:
- `verify = true` - Ensure code quality
- `min_score = 90` - Strict verification (embedded must be reliable)
- `generate_header = true` - C integration is common
- `export_analysis = false` - Save space
- `suggest_fixes = true` - Help fix issues

**Example**:
```julia
compile_shlib(sensor_read, (Int,), "./", "sensor", template=:embedded)
```

**When to use**:
- Compiling for ARM microcontrollers
- Building firmware components
- Creating IoT device libraries
- Any size-constrained environment

### `:performance` - Maximum Performance

**Use for**: HPC, computation-heavy workloads, servers

**Settings**:
- `verify = true` - Ensure optimization potential
- `min_score = 85` - High quality bar
- `generate_header = true` - For benchmarking harness
- `export_analysis = false` - Not needed for perf
- `suggest_fixes = true` - Optimize further

**Example**:
```julia
compile_shlib(matrix_multiply, (Ptr{Float64}, Ptr{Float64}, Int),
              "./", "blas", template=:performance)
```

**When to use**:
- Scientific computing
- ML inference engines
- Game physics engines
- Real-time processing

### `:portable` - Broad Compatibility

**Use for**: Distribution, unknown target systems

**Settings**:
- `verify = true` - Catch compatibility issues
- `min_score = 75` - More permissive
- `generate_header = true` - Standard interface
- `export_analysis = false` - Not needed for distribution
- `suggest_fixes = true` - Help improve

**Example**:
```julia
compile_shlib(crypto_hash, (Ptr{UInt8}, Int), "./", "hash",
              template=:portable)
```

**When to use**:
- Distributing binary libraries
- Supporting multiple platforms
- Legacy system compatibility
- Public API libraries

### `:debugging` - Development/Debugging

**Use for**: Development, troubleshooting, learning

**Settings**:
- `verify = true` - Find issues early
- `min_score = 70` - Permissive (allow experimentation)
- `generate_header = true` - Easy testing from C
- `export_analysis = true` - Detailed diagnostics
- `suggest_fixes = true` - Learn best practices

**Example**:
```julia
compile_shlib(experimental_func, (Int,), "./", "test",
              template=:debugging)
```

**When to use**:
- Prototyping new functionality
- Learning StaticCompiler.jl
- Debugging compilation issues
- Exploring code quality

### `:production` - Production Deployment

**Use for**: Production releases, deployments

**Settings**:
- `verify = true` - Enforce quality
- `min_score = 90` - Very strict
- `generate_header = true` - API documentation
- `export_analysis = true` - Audit trail
- `suggest_fixes = true` - Continuous improvement

**Example**:
```julia
compile_shlib(api_handler, (Ptr{UInt8},), "./", "api",
              template=:production)
```

**When to use**:
- Production releases
- Customer-facing APIs
- Mission-critical systems
- Regulated industries

### `:default` - Balanced Default

**Use for**: General purpose when you know code is good

**Settings**:
- `verify = false` - Trust your code
- `min_score = 80` - N/A (verification disabled)
- `generate_header = false` - Manual if needed
- `export_analysis = false` - Not needed
- `suggest_fixes = true` - N/A

**Example**:
```julia
compile_shlib(well_tested_func, (Int,), "./", "func", template=:default)
```

**When to use**:
- Code already thoroughly tested
- Quick iterations
- Internal tools
- When you know what you're doing

## API Reference

### compile_shlib with Templates

```julia
compile_shlib(f::Function, types::Tuple, path::String, name::String;
    template::Union{Symbol,Nothing}=nothing,
    # ... other parameters can override template
)
```

The `template` parameter applies pre-configured settings. Explicit parameters override template defaults.

### compile_with_template

Alternative explicit API:

```julia
compile_with_template(template::Symbol, f::Function, types::Tuple,
                      path::String, name::String;
                      custom_params::NamedTuple=NamedTuple(),
                      kwargs...)
```

**Arguments**:
- `template::Symbol`: Template name
- `f, types, path, name`: Same as compile_shlib
- `custom_params`: Override specific template parameters
- `kwargs`: Additional compile_shlib parameters

**Example**:
```julia
compile_with_template(:embedded, myfunc, (Int,), "./", "myfunc",
                      custom_params=(min_score=95,))
```

### Template Introspection

```julia
# List all templates
templates = list_templates()  # [:debugging, :default, :embedded, ...]

# Get template details
template = get_template(:embedded)
template.name          # :embedded
template.description   # "Embedded/IoT systems: minimal size, no stdlib"
template.params        # (verify=true, min_score=90, ...)

# Show template info
show_template(:embedded)

# Show all templates
show_all_templates()

# Apply template with overrides
params = apply_template(:embedded, (min_score=95,))
```

## Usage Examples

### Example 1: Quick Template Selection

```julia
# Development
compile_shlib(func, types, "./", "name", template=:debugging)

# Testing
compile_shlib(func, types, "./", "name", template=:portable)

# Production
compile_shlib(func, types, "./", "name", template=:production)
```

### Example 2: Template with Overrides

```julia
# Use embedded template but customize threshold
compile_shlib(func, types, "./", "name",
              template=:embedded,
              min_score=95)  # Override: stricter than template's 90
```

### Example 3: Batch Compilation

```julia
functions = [
    (func1, (Int,)),
    (func2, (Float64,)),
    (func3, (Int, Int))
]

# Compile all with production settings
compile_shlib(functions, "./",
              filename="mylib",
              template=:production)
```

### Example 4: Programmatic Template Use

```julia
# Get template and inspect
tmpl = get_template(:performance)
println("Using: $(tmpl.description)")

# Apply with custom overrides
params = apply_template(:performance, (export_analysis=true,))

# Compile with merged parameters
compile_shlib(func, types, "./", "name"; params...)
```

### Example 5: Project-Wide Configuration

```julia
# config.jl
const PROJECT_TEMPLATE = :production
const CUSTOM_OVERRIDES = (min_score=95, export_analysis=true)

# build.jl
include("config.jl")

function build_library(func, types, name)
    compile_shlib(func, types, "./build", name,
                  template=PROJECT_TEMPLATE,
                  CUSTOM_OVERRIDES...)
end
```

## Template Selection Guide

### By Use Case

| Use Case | Template | Reason |
|----------|----------|--------|
| Arduino/ESP32 | `:embedded` | Small size, reliability |
| ML Inference | `:performance` | Speed critical |
| CLI Tool | `:portable` | Wide compatibility |
| Prototype | `:debugging` | Fast iteration |
| SaaS API | `:production` | Quality + docs |
| Research | `:default` | Flexibility |

### By Priority

| Priority | Template |
|----------|----------|
| Size | `:embedded` |
| Speed | `:performance` |
| Compatibility | `:portable` |
| Quality | `:production` |
| Learning | `:debugging` |
| Simplicity | `:default` |

### By Stage

| Development Stage | Template |
|------------------|----------|
| Prototyping | `:debugging` |
| Alpha Testing | `:default` |
| Beta Testing | `:portable` |
| Release Candidate | `:production` |
| Production | `:production` |
| Embedded Release | `:embedded` |

## Overriding Template Defaults

Templates can be customized by passing explicit parameters:

```julia
# Template provides defaults
compile_shlib(func, types, "./", "name", template=:embedded)
# Uses: verify=true, min_score=90, generate_header=true, ...

# Override specific parameters
compile_shlib(func, types, "./", "name",
              template=:embedded,
              min_score=85,          # Override: lower threshold
              export_analysis=true)  # Override: enable export
```

**Override precedence**:
1. Explicit parameters (highest priority)
2. Template parameters
3. Function defaults (lowest priority)

## Comparison Matrix

### Settings by Template

| Template | Verify | Min Score | Export Analysis | Generate Header | Best For |
|----------|--------|-----------|-----------------|-----------------|----------|
| `:embedded` | ✓ | 90 | ✗ | ✓ | IoT, Embedded |
| `:performance` | ✓ | 85 | ✗ | ✓ | HPC, Speed |
| `:portable` | ✓ | 75 | ✗ | ✓ | Distribution |
| `:debugging` | ✓ | 70 | ✓ | ✓ | Development |
| `:production` | ✓ | 90 | ✓ | ✓ | Releases |
| `:default` | ✗ | N/A | ✗ | ✗ | General |

### Trade-offs

**Strict Templates (`:embedded`, `:production`)**:
- ✓ High quality guarantee
- ✓ Fewer surprises
- ✗ May reject acceptable code
- ✗ Longer development cycle

**Permissive Templates (`:debugging`, `:portable`)**:
- ✓ Faster iteration
- ✓ More forgiving
- ✗ May allow suboptimal code
- ✗ Quality varies

## Workflow Recommendations

### Development Workflow

```julia
# Phase 1: Prototype (permissive)
compile_shlib(func, types, "./", "func", template=:debugging)

# Phase 2: Refine (balanced)
compile_shlib(func, types, "./", "func", template=:default)

# Phase 3: Pre-release (strict)
compile_shlib(func, types, "./", "func", template=:production)
```

### Multi-Platform Workflow

```julia
# Local development (fast iteration)
compile_shlib(func, types, "./", "func", template=:debugging)

# CI builds (compatibility testing)
compile_shlib(func, types, "./", "func", template=:portable)

# Release builds (quality assurance)
compile_shlib(func, types, "./", "func", template=:production)
```

### Team Workflow

```julia
# Team standard in config file
const TEAM_TEMPLATE = :production
const TEAM_THRESHOLD = 88

# Every developer uses same standard
function team_compile(func, types, name)
    compile_shlib(func, types, "./build", name,
                  template=TEAM_TEMPLATE,
                  min_score=TEAM_THRESHOLD)
end
```

## Best Practices

### 1. Choose the Right Template

Match template to your actual use case:

```julia
# ✅ Good
compile_shlib(sensor_func, types, "./", "sensor", template=:embedded)

# ❌ Bad - using wrong template
compile_shlib(sensor_func, types, "./", "sensor", template=:debugging)
```

### 2. Override Conservatively

Only override when necessary:

```julia
# ✅ Good - override for good reason
compile_shlib(func, types, "./", "name",
              template=:embedded,
              min_score=95)  # Project requires higher bar

# ❌ Bad - defeating template purpose
compile_shlib(func, types, "./", "name",
              template=:production,
              verify=false,          # Defeats purpose
              generate_header=false)  # Just use :default
```

### 3. Document Your Choice

```julia
# ✅ Good - document why
# Using embedded template because deploying to ESP32
# with 512KB flash constraint
compile_shlib(iot_func, types, "./", "iot", template=:embedded)

# ❌ Bad - no context
compile_shlib(iot_func, types, "./", "iot", template=:embedded)
```

### 4. Use Templates Consistently

```julia
# ✅ Good - consistent across project
for (func, types, name) in project_functions
    compile_shlib(func, types, "./", name, template=:production)
end

# ❌ Bad - inconsistent quality
compile_shlib(func1, types1, "./", "f1", template=:debugging)
compile_shlib(func2, types2, "./", "f2", template=:production)
compile_shlib(func3, types3, "./", "f3")  # No template
```

### 5. Evolve Templates with Project

```julia
# Early development
compile_shlib(func, types, "./", "name", template=:debugging)

# As project matures
compile_shlib(func, types, "./", "name", template=:default)

# For release
compile_shlib(func, types, "./", "name", template=:production)
```

## Advanced Usage

### Custom Template Configurations

While you can't add new templates (currently), you can create reusable configurations:

```julia
# Define project-specific settings
const EMBEDDED_STRICT = (
    verify = true,
    min_score = 95,  # Stricter than :embedded's 90
    generate_header = true,
    export_analysis = true,  # Unlike :embedded
    suggest_fixes = true
)

# Use consistently
compile_shlib(func, types, "./", "name"; EMBEDDED_STRICT...)
```

### Conditional Templates

```julia
# Choose template based on environment
template = get(ENV, "BUILD_TYPE", "development") == "production" ?
           :production : :debugging

compile_shlib(func, types, "./", "name", template=template)
```

### Template Composition

```julia
# Start with template, selectively override
base_params = apply_template(:performance, (export_analysis=true,))

# Add project-specific settings
final_params = merge(base_params, (cflags=`-march=native`,))

# Compile
compile_shlib(func, types, "./", "name"; final_params...)
```

## Troubleshooting

### Issue: Template Too Strict

**Symptom**:
```
❌ Compilation aborted: function failed verification (score < 90)
```

**Solutions**:
1. Fix the code (recommended)
2. Use a more permissive template
3. Override min_score

```julia
# Option 2: More permissive template
compile_shlib(func, types, "./", "name", template=:portable)  # min_score=75

# Option 3: Override threshold
compile_shlib(func, types, "./", "name", template=:embedded, min_score=85)
```

### Issue: Template Too Permissive

**Symptom**: Code compiles but has quality issues in production.

**Solution**: Use stricter template or raise threshold.

```julia
# Use stricter template
compile_shlib(func, types, "./", "name", template=:production)

# Or override threshold
compile_shlib(func, types, "./", "name", template=:default,
              verify=true, min_score=90)
```

### Issue: Unknown Template

**Error**:
```
ArgumentError: Unknown template :custom. Available templates: :debugging, ...
```

**Solution**: Use a built-in template name.

```julia
# ❌ Bad
compile_shlib(func, types, "./", "name", template=:custom)

# ✅ Good
compile_shlib(func, types, "./", "name", template=:production)
```

## Examples

See `examples/12_compilation_templates.jl` for comprehensive examples including:
- Listing and inspecting templates
- Using each template
- Overriding template parameters
- Batch compilation with templates
- Custom configurations
- Workflow patterns

## See Also

- [Integrated Verification](./INTEGRATED_VERIFICATION.md)
- [C Header Generation](./C_HEADER_GENERATION.md)
- [StaticCompiler.jl Documentation](../README.md)

## Summary

Compilation templates simplify StaticCompiler.jl usage:

```julia
# One parameter, optimal settings
compile_shlib(func, types, "./", "name", template=:embedded)
```

**Benefits**:
- No parameter memorization
- Best practices built-in
- Consistent settings
- Easy customization
- Faster workflow

**Choose template by**:
- Use case (embedded, HPC, etc.)
- Development stage (prototype, production)
- Priority (size, speed, quality)

**Six built-in templates**:
- `:embedded` - Small, strict, for IoT
- `:performance` - Fast, optimized, for HPC
- `:portable` - Compatible, for distribution
- `:debugging` - Helpful, permissive, for development
- `:production` - Strict, documented, for releases
- `:default` - Balanced, for general use
