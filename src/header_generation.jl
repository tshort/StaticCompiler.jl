# Automatic C Header Generation
# Generates C/C++ headers for compiled Julia functions

"""
    julia_to_c_type(jltype::Type) -> String

Convert a Julia type to its C equivalent for header generation.

# Supported Types
- Integer types: Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64
- Floating point: Float32, Float64
- Bool: bool (requires stdbool.h)
- Pointers: Ptr{T} -> T*
- Void: Nothing/Cvoid -> void

# Examples
```julia
julia> julia_to_c_type(Int64)
"int64_t"

julia> julia_to_c_type(Float64)
"double"

julia> julia_to_c_type(Ptr{UInt8})
"uint8_t*"
```
"""
function julia_to_c_type(jltype::Type)
    # Handle pointer types
    if jltype <: Ptr
        # Extract the pointed-to type
        param = Base.unwrap_unionall(jltype).parameters[1]
        if param === Cvoid || param === Nothing
            return "void*"
        else
            base_type = julia_to_c_type(param)
            return base_type * "*"
        end
    end

    # Map Julia types to C types
    type_map = Dict{Type, String}(
        # Signed integers
        Int8    => "int8_t",
        Int16   => "int16_t",
        Int32   => "int32_t",
        Int64   => "int64_t",
        Int     => sizeof(Int) == 8 ? "int64_t" : "int32_t",

        # Unsigned integers
        UInt8   => "uint8_t",
        UInt16  => "uint16_t",
        UInt32  => "uint32_t",
        UInt64  => "uint64_t",
        UInt    => sizeof(UInt) == 8 ? "uint64_t" : "uint32_t",

        # Floating point
        Float32 => "float",
        Float64 => "double",

        # Boolean
        Bool    => "bool",

        # Void/Nothing
        Nothing => "void",
        Cvoid   => "void",
    )

    # Look up the type
    if haskey(type_map, jltype)
        return type_map[jltype]
    end

    # Handle parametric types by checking supertype
    for (jl_t, c_t) in type_map
        if jltype <: jl_t
            return c_t
        end
    end

    # Default fallback - warn the user
    @warn "Unsupported type $jltype, using void*" maxlog=1
    return "void*"
end

"""
    generate_function_declaration(fname::String, argtypes::Tuple, rettype::Type;
                                   demangle::Bool=true) -> String

Generate a C function declaration for a Julia function.

# Arguments
- `fname::String`: Function name
- `argtypes::Tuple`: Tuple of argument types
- `rettype::Type`: Return type
- `demangle::Bool=true`: If false, prepend "julia_" to name

# Returns
String containing the C function declaration.

# Example
```julia
julia> generate_function_declaration("my_func", (Int, Float64), Float64)
"double my_func(int64_t arg0, double arg1);"
```
"""
function generate_function_declaration(fname::String, argtypes::Tuple, rettype::Type;
                                       demangle::Bool=true)
    # Add julia_ prefix if not demangled
    c_fname = demangle ? fname : "julia_$fname"

    # Convert return type
    c_rettype = julia_to_c_type(rettype)

    # Convert argument types
    if length(argtypes) == 0
        # No arguments - use (void) in C
        args_str = "void"
    else
        args = String[]
        for (i, argtype) in enumerate(argtypes)
            c_type = julia_to_c_type(argtype)
            # Argument names: arg0, arg1, arg2, ...
            push!(args, "$c_type arg$(i-1)")
        end
        args_str = join(args, ", ")
    end

    return "$c_rettype $c_fname($args_str);"
end

"""
    generate_header_content(funcs::Vector{Tuple}, filename::String;
                            demangle::Bool=true,
                            include_extern_c::Bool=true,
                            comment::String="") -> String

Generate complete C header file content for multiple functions.

# Arguments
- `funcs::Vector{Tuple}`: Vector of (name, argtypes, rettype) tuples
- `filename::String`: Base filename (without extension) for include guard
- `demangle::Bool=true`: Whether function names are demangled
- `include_extern_c::Bool=true`: Include extern "C" wrapper for C++
- `comment::String=""`: Optional header comment

# Returns
String containing complete header file content with:
- Include guards
- Required includes (stdint.h, stdbool.h)
- extern "C" wrapper (if requested)
- Function declarations
"""
function generate_header_content(funcs::Vector, filename::String;
                                 demangle::Bool=true,
                                 include_extern_c::Bool=true,
                                 comment::String="")
    # Generate include guard name
    guard_name = uppercase(replace(filename, r"[^A-Za-z0-9_]" => "_")) * "_H"

    lines = String[]

    # Header comment
    if !isempty(comment)
        push!(lines, "/* $comment */")
        push!(lines, "")
    end

    # Include guard start
    push!(lines, "#ifndef $guard_name")
    push!(lines, "#define $guard_name")
    push!(lines, "")

    # Required includes
    push!(lines, "/* Required includes */")
    push!(lines, "#include <stdint.h>")
    push!(lines, "#include <stdbool.h>")
    push!(lines, "")

    # extern "C" wrapper for C++ compatibility
    if include_extern_c
        push!(lines, "#ifdef __cplusplus")
        push!(lines, "extern \"C\" {")
        push!(lines, "#endif")
        push!(lines, "")
    end

    # Function declarations
    push!(lines, "/* Function declarations */")
    for (fname, argtypes, rettype) in funcs
        decl = generate_function_declaration(fname, argtypes, rettype; demangle)
        push!(lines, decl)
    end
    push!(lines, "")

    # Close extern "C" wrapper
    if include_extern_c
        push!(lines, "#ifdef __cplusplus")
        push!(lines, "}")
        push!(lines, "#endif")
        push!(lines, "")
    end

    # Include guard end
    push!(lines, "#endif /* $guard_name */")

    return join(lines, "\n")
end

"""
    write_header_file(path::String, filename::String, content::String)

Write a C header file to disk.

# Arguments
- `path::String`: Directory path
- `filename::String`: Base filename (without .h extension)
- `content::String`: Header file content

# Returns
Path to the generated header file.
"""
function write_header_file(path::String, filename::String, content::String)
    header_path = joinpath(path, "$filename.h")
    open(header_path, "w") do io
        write(io, content)
    end
    return header_path
end

"""
    generate_c_header(funcs::Union{Array,Tuple}, path::String, filename::String;
                      demangle::Bool=true,
                      include_extern_c::Bool=true,
                      verbose::Bool=false) -> String

High-level interface: Generate C header for compiled Julia functions.

This function analyzes the provided Julia functions and generates a complete
C header file that can be used to call the functions from C/C++/Rust code.

# Arguments
- `funcs::Union{Array,Tuple}`: Array of (function, types) tuples
- `path::String`: Output directory
- `filename::String`: Base filename (without extension)
- `demangle::Bool=true`: Whether function names are demangled
- `include_extern_c::Bool=true`: Include extern "C" for C++ compatibility
- `verbose::Bool=false`: Print detailed information

# Returns
Path to the generated header file.

# Example
```julia
julia> using StaticCompiler

julia> function add(a::Int, b::Int)
           return a + b
       end

julia> function multiply(a::Float64, b::Float64)
           return a * b
       end

julia> funcs = [(add, (Int, Int)), (multiply, (Float64, Float64))]

julia> compile_shlib(funcs, "./", filename="math", generate_header=true)
Generated header: ./math.h

julia> # Now you can #include "math.h" from C/C++
```
"""
function generate_c_header(funcs::Union{Array,Tuple}, path::String, filename::String;
                          demangle::Bool=true,
                          include_extern_c::Bool=true,
                          verbose::Bool=false)
    # Prepare function information
    func_info = Tuple{String, Tuple, Type}[]

    for func in funcs
        f, types = func
        fname = string(nameof(f))

        # Get return type by type inference
        tt = Base.to_tuple_type(types)
        try
            # Use static_code_typed to get inferred return type
            typed = static_code_typed(f, tt)
            rettype = last(only(typed))

            push!(func_info, (fname, types, rettype))

            if verbose
                println("  $fname$types -> $rettype")
            end
        catch e
            @warn "Could not infer return type for $fname$types, skipping" exception=e
        end
    end

    # Generate header content
    comment = "Automatically generated C header for Julia functions"
    content = generate_header_content(func_info, filename;
                                     demangle, include_extern_c, comment)

    # Write to file
    header_path = write_header_file(path, filename, content)

    if verbose
        println("Generated C header: $header_path")
        println()
        println("Header preview:")
        println("-"^70)
        for (i, line) in enumerate(split(content, "\n"))
            if i <= 25  # Show first 25 lines
                println(line)
            end
        end
        if count(==('\n'), content) > 25
            println("... ($(count(==('\n'), content) - 25) more lines)")
        end
    end

    return header_path
end

export julia_to_c_type, generate_function_declaration
export generate_header_content, write_header_file
export generate_c_header
