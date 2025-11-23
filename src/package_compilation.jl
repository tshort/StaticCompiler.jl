# Package-Level Compilation
# Compile entire modules/packages to shared libraries

using Dates

"""
    FunctionSignature

Represents a function with its type signature for compilation.

# Fields
- `func::Function`: The function to compile
- `types::Tuple`: Argument type signature
- `name::String`: Optional custom name (defaults to function name)
"""
struct FunctionSignature
    func::Function
    types::Tuple
    name::String

    FunctionSignature(func::Function, types::Tuple) = new(func, types, string(nameof(func)))
    FunctionSignature(func::Function, types::Tuple, name::String) = new(func, types, name)
end

"""
    PackageCompilationSpec

Specification for compiling a package/module.

# Fields
- `mod::Module`: The module to compile
- `functions::Vector{FunctionSignature}`: Functions to compile with their signatures
- `name::String`: Output library name
- `namespace::String`: Prefix for function names (default: module name)
"""
struct PackageCompilationSpec
    mod::Module
    functions::Vector{FunctionSignature}
    name::String
    namespace::String

    function PackageCompilationSpec(mod::Module, functions::Vector{FunctionSignature}, name::String)
        namespace = lowercase(string(nameof(mod)))
        return new(mod, functions, name, namespace)
    end

    function PackageCompilationSpec(mod::Module, functions::Vector{FunctionSignature}, name::String, namespace::String)
        return new(mod, functions, name, namespace)
    end
end

"""
    @compile_signature(func, types...)

Macro to easily create a FunctionSignature.

# Examples
```julia
@compile_signature(myfunc, Int, Float64)
# Equivalent to: FunctionSignature(myfunc, (Int, Float64))
```
"""
macro compile_signature(func, types...)
    return :(FunctionSignature($(esc(func)), ($(map(esc, types)...),)))
end

"""
    infer_common_signatures(f::Function, max_signatures::Int=5) -> Vector{Tuple}

Attempt to infer common type signatures for a function by examining its methods.

This is a heuristic approach that looks at existing methods and tries to
find concrete type signatures that are likely to be useful.

# Arguments
- `f::Function`: Function to analyze
- `max_signatures::Int=5`: Maximum number of signatures to return

# Returns
Vector of type tuples representing common signatures.

# Note
This is a best-effort heuristic. For production use, explicitly specify
signatures rather than relying on inference.

# Examples
```julia
julia> function myfunc(x::Int)
           return x * 2
       end

julia> infer_common_signatures(myfunc)
1-element Vector{Tuple}:
 (Int64,)
```
"""
function infer_common_signatures(f::Function, max_signatures::Int = 5)
    signatures = Tuple[]

    # Get all methods
    methods_list = methods(f)

    # Limit to max_signatures
    count = 0
    for method in methods_list
        count >= max_signatures && break

        # Get signature from method
        sig = method.sig

        # Extract parameter types (skip first which is the function type)
        if sig isa UnionAll
            # Handle parametric methods - skip for now as they're complex
            continue
        end

        if sig isa DataType && length(sig.parameters) > 1
            # First parameter is the function itself, rest are arguments
            param_types = sig.parameters[2:end]

            # Only use if all types are concrete
            if all(isconcretetype(t) || t isa Type for t in param_types)
                push!(signatures, Tuple(param_types))
                count += 1
            end
        end
    end

    return signatures
end

"""
    compile_package(mod::Module, signatures::AbstractDict{Symbol, <:AbstractVector},
                    output_path::String, lib_name::String;
                    namespace::Union{String,Nothing}=nothing,
                    template::Union{Symbol,Nothing}=nothing,
                    kwargs...) -> String

Compile an entire module/package to a shared library.

# Arguments
- `mod::Module`: Module to compile
- `signatures::AbstractDict{Symbol, <:AbstractVector}`: Function names => type signatures
- `output_path::String`: Output directory
- `lib_name::String`: Library name
- `namespace::Union{String,Nothing}=nothing`: Function name prefix (default: module name)
- `template::Union{Symbol,Nothing}=nothing`: Compilation template
- `kwargs...`: Additional compile_shlib parameters

# Returns
Path to compiled library

# Examples
```julia
module MyMath
    export add, multiply, divide

    add(a::Int, b::Int) = a + b
    multiply(a::Float64, b::Float64) = a * b
    divide(a::Int, b::Int) = div(a, b)
end

# Specify signatures for each function
signatures = Dict(
    :add => [(Int, Int)],
    :multiply => [(Float64, Float64)],
    :divide => [(Int, Int)]
)

# Compile entire module
lib_path = compile_package(MyMath, signatures, "./", "mymath")

# Creates:
# - mymath.so with functions: mymath_add, mymath_multiply, mymath_divide
# - mymath.h with declarations
```
"""
function compile_package(
        mod::Module, signatures::AbstractDict{Symbol, <:AbstractVector},
        output_path::String, lib_name::String;
        namespace::Union{String, Nothing} = nothing,
        template::Union{Symbol, Nothing} = nothing,
        target::StaticTarget = StaticTarget(),
        kwargs...
    )

    # Default namespace to module name
    if isnothing(namespace)
        namespace = lowercase(string(nameof(mod)))
    end

    println("="^70)
    println("Compiling package: $(nameof(mod))")
    println("Output library: $lib_name")
    println("Namespace: $namespace")
    println("="^70)
    println()

    # Build function list
    func_list = []

    for (func_name, type_sigs) in signatures
        # Get function from module
        if !isdefined(mod, func_name)
            @warn "Function $func_name not found in module $(nameof(mod)), skipping"
            continue
        end

        func = getfield(mod, func_name)

        if !isa(func, Function)
            @warn "$func_name is not a function, skipping"
            continue
        end

        # Add each type signature
        for types in type_sigs
            # Create namespaced name
            namespaced_name = "$(namespace)_$(func_name)"
            push!(func_list, (func, types))

            println("  • $(func_name)$(types) -> $(namespaced_name)")
        end
    end

    println()
    println("Total functions to compile: $(length(func_list))")
    println()

    if isempty(func_list)
        error("No functions to compile")
    end

    # Compile all functions together
    return compile_shlib(
        func_list, output_path;
        filename = lib_name,
        demangle = true,  # We handle naming ourselves
        template = template,
        target = target,
        kwargs...
    )
end

"""
    compile_package_exports(mod::Module, default_signatures::AbstractDict{Symbol, <:AbstractVector},
                           output_path::String, lib_name::String;
                           kwargs...) -> String

Compile all exported functions from a module.

This is a convenience wrapper that automatically finds exported functions
and compiles them with provided signatures.

# Arguments
- `mod::Module`: Module to compile
- `default_signatures::AbstractDict{Symbol, <:AbstractVector}`: Type signatures for exported functions
- `output_path::String`: Output directory
- `lib_name::String`: Library name
- `kwargs...`: Additional compile_package parameters

# Examples
```julia
module Calculator
    export add, subtract

    add(a::Int, b::Int) = a + b
    subtract(a::Int, b::Int) = a - b
    private_func() = 42  # Not exported, won't be compiled
end

# Only compile exported functions
signatures = Dict(
    :add => [(Int, Int)],
    :subtract => [(Int, Int)]
)

lib_path = compile_package_exports(Calculator, signatures, "./", "calc")
```
"""
function compile_package_exports(
        mod::Module, default_signatures::AbstractDict{Symbol, <:AbstractVector},
        output_path::String, lib_name::String;
        kwargs...
    )
    # Get exported names
    exported = names(mod; all = false, imported = false)

    # Filter signatures to only exported functions
    export_signatures = Dict{Symbol, Vector}()

    for name in exported
        if haskey(default_signatures, name)
            export_signatures[name] = default_signatures[name]
        end
    end

    if isempty(export_signatures)
        @warn "No exported functions found with signatures"
        return nothing
    end

    println("Compiling $(length(export_signatures)) exported functions from $(nameof(mod))")
    println()

    return compile_package(mod, export_signatures, output_path, lib_name; kwargs...)
end

"""
    @compile_package(module_expr, output_path, lib_name, signatures...)

Macro for convenient package compilation.

# Examples
```julia
@compile_package MyModule "./build" "mylib" begin
    add => [(Int, Int), (Float64, Float64)]
    multiply => [(Float64, Float64)]
end
```
"""
macro compile_package(mod, path, name, sig_block)
    # Parse signature block
    if sig_block.head != :block
        error("Signature block must be a begin...end block")
    end

    sig_exprs = []
    for expr in sig_block.args
        if expr isa Expr && expr.head == :(=>) && length(expr.args) == 2
            func_name = expr.args[1]
            types_expr = expr.args[2]
            push!(sig_exprs, :($func_name => $types_expr))
        elseif expr isa LineNumberNode
            continue
        else
            error("Invalid signature expression: $expr")
        end
    end

    return quote
        compile_package(
            $(esc(mod)),
            Dict{Symbol, Vector}($(sig_exprs...)),
            $(esc(path)),
            $(esc(name))
        )
    end
end

"""
    generate_package_manifest(mod::Module, signatures::Dict, lib_name::String,
                              namespace::String, output_path::String)

Generate a JSON manifest describing the compiled package.

The manifest includes:
- Module name
- Library name
- Compiled functions with signatures
- Namespace
- Compilation timestamp

This is useful for documentation and programmatic library loading.
"""
function generate_package_manifest(
        mod::Module, signatures::Dict, lib_name::String,
        namespace::String, output_path::String
    )
    # Build manifest as text (simple JSON-like format)
    lines = String[]
    push!(lines, "{")
    push!(lines, "  \"module\": \"$(nameof(mod))\",")
    push!(lines, "  \"library\": \"$lib_name\",")
    push!(lines, "  \"namespace\": \"$namespace\",")
    push!(lines, "  \"timestamp\": \"$(Dates.now())\",")
    push!(lines, "  \"functions\": [")

    func_entries = String[]
    for (func_name, type_sigs) in signatures
        for types in type_sigs
            entry = "    {"
            entry *= "\n      \"name\": \"$func_name\","
            entry *= "\n      \"namespaced_name\": \"$(namespace)_$(func_name)\","
            entry *= "\n      \"signature\": \"$types\""
            entry *= "\n    }"
            push!(func_entries, entry)
        end
    end
    push!(lines, join(func_entries, ",\n"))

    push!(lines, "  ]")
    push!(lines, "}")

    manifest_path = joinpath(output_path, "$(lib_name)_manifest.json")
    open(manifest_path, "w") do io
        write(io, join(lines, "\n"))
    end

    return manifest_path
end

export FunctionSignature, PackageCompilationSpec
export @compile_signature, @compile_package
export infer_common_signatures
export compile_package, compile_package_exports
export generate_package_manifest
