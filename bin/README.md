# StaticCompiler.jl Command-Line Tools

This directory contains command-line utilities for StaticCompiler.jl.

## Main Tools

### `staticcompile` - Main Compilation Tool

Compile Julia functions to standalone binaries or shared libraries.

**Basic Usage:**
```bash
# Compile a function to executable
./staticcompile hello.jl main

# Compile to shared library
./staticcompile --shlib mylib.jl compute

# Use a template for common scenarios
./staticcompile --template embedded sensor.jl read_sensor
```

**Common Options:**
- `--shlib, -s`: Compile to shared library instead of executable
- `--output, -o NAME`: Specify output name
- `--template, -t NAME`: Use compilation template
- `--verify, -v`: Enable pre-compilation verification
- `--generate-header, -H`: Generate C header file
- `--strip`: Strip debug symbols after compilation
- `--cflags FLAGS`: Custom compiler flags

**Templates:**
- `embedded`: For IoT/embedded systems (small size, strict verification)
- `performance`: For HPC (maximum speed)
- `portable`: For distribution (broad compatibility)
- `debugging`: For development (helpful diagnostics)
- `production`: For releases (strict quality, full docs)
- `default`: Balanced default settings

**Examples:**

```bash
# Embedded system with size optimization
./staticcompile --template embedded --strip -o sensor sensor.jl read_sensor

# HPC with custom optimization
./staticcompile --template performance --cflags "-O3 -march=native" compute.jl matrix_mul

# Production release with header
./staticcompile --template production --generate-header -o mylib mylib.jl api_handler

# Development with detailed analysis
./staticcompile --template debugging --export-analysis test.jl experimental_func
```

**Package Compilation:**

Compile entire modules/packages:

```bash
# Create signatures.json first
cat > signatures.json << 'EOF'
{
    "add": [["Int", "Int"]],
    "multiply": [["Float64", "Float64"]]
}
EOF

# Compile package
./staticcompile --package --signatures signatures.json MyModule.jl --output mylib
```

**Help:**
```bash
./staticcompile --help              # Show all options
./staticcompile --list-templates    # List available templates
./staticcompile --show-template embedded  # Show template details
./staticcompile --version           # Show version
```

## Utility Scripts

### `analyze-code` - Code Quality Analysis

Analyze Julia code before compilation:

```bash
./analyze-code myfunction.jl main
```

Shows:
- Escape analysis (heap allocations)
- Type stability
- Dynamic dispatch locations
- Optimization opportunities

### `optimize-binary` - Binary Size Optimization

Automated binary size optimization:

```bash
# Compile and optimize
./optimize-binary hello.jl main

# With UPX compression
./optimize-binary --upx hello.jl main

# Show size progression
./optimize-binary --verbose hello.jl main
```

### `generate-header` - C Header Generation

Generate C header for existing compiled library:

```bash
./generate-header mylib.so myfunction Int,Int
```

### `quick-compile` - Quick Development Compilation

Fast compilation for development/testing:

```bash
./quick-compile test.jl main
# Equivalent to: staticcompile --template debugging test.jl main
```

## Installation

Add this directory to your PATH:

```bash
# In your ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/staticcompiler.jl/bin"
```

Then you can use the tools from anywhere:

```bash
staticcompile --template embedded my_project.jl main
```

## Integration with Build Systems

### Makefile

```makefile
CC = gcc
JULIA = julia
STATICCOMPILE = staticcompile

all: myapp

myapp: src/main.jl
	$(STATICCOMPILE) --template production --strip -o $@ $< main

clean:
	rm -f myapp
```

### CMake

```cmake
find_program(STATICCOMPILE staticcompile)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/myapp
    COMMAND ${STATICCOMPILE} --template production --strip
            -o ${CMAKE_BINARY_DIR}/myapp ${CMAKE_SOURCE_DIR}/src/main.jl main
    DEPENDS ${CMAKE_SOURCE_DIR}/src/main.jl
)
```

### Shell Script

```bash
#!/bin/bash
# build.sh

set -e

echo "Building project..."

# Compile main application
staticcompile --template production --strip -o bin/myapp src/main.jl main

# Compile library
staticcompile --shlib --template production --generate-header \
    -o lib/mylib src/mylib.jl compute

echo "Build complete!"
```

## Troubleshooting

### "Function not found"

Ensure the function is defined in the source file and the name matches exactly (case-sensitive).

### "Template not found"

Use `--list-templates` to see available templates. Template names are symbols like `:embedded`, not strings.

### "Permission denied"

Make scripts executable:
```bash
chmod +x bin/*
```

### "Julia command not found"

Ensure Julia is in your PATH:
```bash
which julia
# If not found, add Julia to PATH or use full path in shebang
```

## See Also

- [Main Documentation](../README.md)
- [Examples](../examples/)
- [Binary Size Optimization Guide](../docs/BINARY_SIZE_OPTIMIZATION.md)
- [Compilation Templates Guide](../docs/COMPILATION_TEMPLATES.md)
