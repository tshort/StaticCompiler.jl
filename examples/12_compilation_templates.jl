# Example 12: Compilation Templates/Presets
#
# This example demonstrates the compilation templates feature that provides
# pre-configured settings for common compilation scenarios.
#
# Templates make it easy to compile for different use cases without needing
# to remember all the parameter combinations.

using StaticCompiler

println("="^70)
println("Example 12: Compilation Templates/Presets")
println("="^70)
println()

# ============================================================================
# Section 1: Listing Available Templates
# ============================================================================

println("Section 1: Available Templates")
println("-"^70)
println()

println("List all template names:")
templates = list_templates()
for tmpl in templates
    println("  • :$tmpl")
end
println()

println("Detailed information:")
println()
show_all_templates()
println()

# ============================================================================
# Section 2: Template Details
# ============================================================================

println()
println("Section 2: Inspecting Template Settings")
println("-"^70)
println()

println("Example: Show embedded template")
println()
show_template(:embedded)
println()

println("Example: Show performance template")
println()
show_template(:performance)
println()

# ============================================================================
# Section 3: Using Templates Directly
# ============================================================================

println()
println("Section 3: Using Templates with compile_shlib")
println("-"^70)
println()

# A simple function for demonstration
function calculate_sum(n::Int)
    result = 0
    for i in 1:n
        result += i
    end
    return result
end

println("Example 3a: Compiling with :embedded template")
println()

output_dir1 = mktempdir()
try
    lib_path = compile_shlib(calculate_sum, (Int,), output_dir1, "calc_embedded",
                             template=:embedded)
    println("✅ Compiled: $lib_path")
    println()
catch e
    println("Error: $e")
    println()
end

println("Example 3b: Compiling with :performance template")
println()

output_dir2 = mktempdir()
try
    lib_path = compile_shlib(calculate_sum, (Int,), output_dir2, "calc_perf",
                             template=:performance)
    println("✅ Compiled: $lib_path")
    println()
catch e
    println("Error: $e")
    println()
end

println("Example 3c: Compiling with :debugging template")
println()

output_dir3 = mktempdir()
try
    lib_path = compile_shlib(calculate_sum, (Int,), output_dir3, "calc_debug",
                             template=:debugging)
    println("✅ Compiled: $lib_path")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 4: Template Overrides
# ============================================================================

println()
println("Section 4: Overriding Template Parameters")
println("-"^70)
println()

println("Templates can be customized by passing explicit parameters")
println("that override the template defaults.")
println()

output_dir4 = mktempdir()

println("Example: Use :embedded but lower the score threshold")
println()

try
    # Embedded template normally has min_score=90
    # We override it to 80
    lib_path = compile_shlib(calculate_sum, (Int,), output_dir4, "calc_custom",
                             template=:embedded,
                             min_score=80)  # Override template default

    println("✅ Successfully used template with custom override")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 5: compile_with_template Function
# ============================================================================

println()
println("Section 5: Using compile_with_template")
println("-"^70)
println()

println("Alternative API: compile_with_template for more explicit usage")
println()

output_dir5 = mktempdir()

try
    lib_path = compile_with_template(:production, calculate_sum, (Int,),
                                      output_dir5, "calc_production")
    println("✅ Compiled using compile_with_template")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 6: Batch Compilation with Templates
# ============================================================================

println()
println("Section 6: Batch Compilation with Templates")
println("-"^70)
println()

function add_numbers(a::Int, b::Int)
    return a + b
end

function multiply_numbers(a::Int, b::Int)
    return a * b
end

functions = [
    (add_numbers, (Int, Int)),
    (multiply_numbers, (Int, Int)),
    (calculate_sum, (Int,))
]

output_dir6 = mktempdir()

println("Example: Compile multiple functions with :production template")
println()

try
    lib_path = compile_shlib(functions, output_dir6,
                             filename="math_ops",
                             template=:production)
    println("✅ Batch compiled with production template")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 7: Template Comparison
# ============================================================================

println()
println("Section 7: Comparing Template Behavior")
println("-"^70)
println()

println("Template            | Verify | Min Score | Export | Header")
println("-"*19 * "|" * "-"*8 * "|" * "-"*11 * "|" * "-"*8 * "|" * "-"*8)

for template_name in list_templates()
    tmpl = get_template(template_name)
    params = tmpl.params
    println(rpad(":$template_name", 20), "|",
            rpad("  $(params.verify)", 8), "|",
            rpad("  $(params.min_score)", 11), "|",
            rpad("  $(params.export_analysis)", 8), "|",
            "  $(params.generate_header)")
end
println()

# ============================================================================
# Section 8: Workflow Examples
# ============================================================================

println()
println("Section 8: Recommended Workflows")
println("-"^70)
println()

println("Development workflow:")
println("  1. Prototype: template=:debugging (permissive, helpful)")
println("  2. Testing: template=:default (balanced)")
println("  3. Pre-release: template=:portable (compatibility)")
println("  4. Production: template=:production (strict, documented)")
println()

println("Deployment scenarios:")
println("  • Embedded/IoT: template=:embedded")
println("  • High-performance computing: template=:performance")
println("  • Library distribution: template=:portable")
println("  • Internal tools: template=:default")
println()

# ============================================================================
# Section 9: Creating Custom Templates
# ============================================================================

println()
println("Section 9: Custom Template Patterns")
println("-"^70)
println()

println("While built-in templates cover common cases, you can")
println("create your own parameter sets for specific needs:")
println()

# Example: Custom configuration for a specific project
MY_PROJECT_CONFIG = (
    verify = true,
    min_score = 88,
    suggest_fixes = true,
    export_analysis = true,
    generate_header = true
)

println("Custom configuration example:")
for (key, value) in pairs(MY_PROJECT_CONFIG)
    println("  $key = $value")
end
println()

output_dir7 = mktempdir()

println("Using custom configuration:")
try
    lib_path = compile_shlib(calculate_sum, (Int,), output_dir7, "custom",
                             MY_PROJECT_CONFIG...)
    println("✅ Compiled with custom configuration")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 10: Template + Other Features
# ============================================================================

println()
println("Section 10: Combining Templates with Other Features")
println("-"^70)
println()

println("Templates work seamlessly with other compile_shlib features:")
println()

output_dir8 = mktempdir()

println("Example: Template + custom compiler flags")
try
    lib_path = compile_shlib(calculate_sum, (Int,), output_dir8, "combined",
                             template=:performance,
                             cflags=`-O3`)  # Additional optimization
    println("✅ Template combined with custom cflags")
    println()
catch e
    println("Error: $e")
    println()
end

# ============================================================================
# Section 11: Understanding Template Output
# ============================================================================

println()
println("Section 11: What Templates Enable")
println("-"^70)
println()

println(":embedded template enables:")
println("  ✓ Code quality verification (min_score=90)")
println("  ✓ C header generation (for integration)")
println("  ✓ Strict standards (for embedded reliability)")
println()

println(":performance template enables:")
println("  ✓ Code quality verification (min_score=85)")
println("  ✓ C header generation (for benchmarking)")
println("  ✓ Focus on speed over size")
println()

println(":debugging template enables:")
println("  ✓ Permissive verification (min_score=70)")
println("  ✓ Analysis export (for diagnostics)")
println("  ✓ C header generation")
println("  ✓ Helpful suggestions")
println()

println(":production template enables:")
println("  ✓ Strict verification (min_score=90)")
println("  ✓ Complete documentation (headers + reports)")
println("  ✓ Quality enforcement")
println()

# ============================================================================
# Section 12: Programmatic Template Access
# ============================================================================

println()
println("Section 12: Programmatic Template Access")
println("-"^70)
println()

println("Templates can be inspected programmatically:")
println()

embedded_template = get_template(:embedded)
println("Template name: $(embedded_template.name)")
println("Description: $(embedded_template.description)")
println("Parameters:")
for (key, value) in pairs(embedded_template.params)
    println("  $key: $value")
end
println()

println("Apply template with custom overrides:")
custom_params = apply_template(:embedded, (min_score=95, export_analysis=true))
println("Resulting parameters:")
for (key, value) in pairs(custom_params)
    println("  $key: $value")
end
println()

# ============================================================================
# Summary
# ============================================================================

println()
println("="^70)
println("SUMMARY")
println("="^70)
println()
println("Compilation templates provide pre-configured settings for:")
println()
println("✓ :embedded   - IoT/embedded systems (small, strict)")
println("✓ :performance - HPC/computation (fast, optimized)")
println("✓ :portable    - Broad compatibility (conservative)")
println("✓ :debugging   - Development (helpful, permissive)")
println("✓ :production  - Deployment (strict, documented)")
println("✓ :default     - Standard behavior")
println()
println("Benefits:")
println("  • No need to remember parameter combinations")
println("  • Consistent settings across projects")
println("  • Best practices built-in")
println("  • Easy to customize (override specific params)")
println("  • Faster development workflow")
println()
println("Usage:")
println("  compile_shlib(func, types, path, name, template=:embedded)")
println()
println("  compile_with_template(:performance, func, types, path, name)")
println()
println("  # Override template defaults")
println("  compile_shlib(func, types, path, name,")
println("                template=:embedded, min_score=95)")
println()
println("="^70)
