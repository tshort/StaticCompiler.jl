# Tiny Binary Generation Guide

**StaticCompiler.jl** now supports generating minimal-size standalone executables through a comprehensive size optimization system.

## Quick Start

The easiest way to create tiny binaries is using the `:tiny` template:

```julia
using StaticCompiler

function myfunc(x::Int)::Int
    return x * 2
end

# ONE COMMAND!
compile_executable(myfunc, (Int,), "./output", "myapp"; template=:tiny)
```

**That's it!** This single command automatically applies all size optimizations.

## Size Reduction Results

| Binary Type | Typical Size | With `:tiny` | Reduction |
|-------------|--------------|--------------|-----------|
| Hello World | 2-5 MB | 300-800 KB | 70-90% |
| Simple Math | 4-6 MB | 500 KB-1 MB | 75-90% |
| With I/O | 5-8 MB | 1-2 MB | 60-80% |

**Example:** A 2.5 MB executable reduces to 300 KB (88% smaller!)

## How It Works

The `:tiny` template combines three optimization phases:

### Phase 1: Compiler Flags
- Size optimization (`-Os`)
- Link-time optimization (`-flto`)
- Function/data sections for dead code elimination
- Stack protector removal
- Unwind table removal

### Phase 2: Post-Build Processing
- Symbol stripping (removes debugging info)
- Optional UPX compression
- Size reporting

### Phase 3: Quality Assurance
- Code verification (min_score=85)
- Optimization suggestions
- Ensures tiny binaries are also robust

## Usage Examples

### 1. Basic - Use the Template

```julia
compile_executable(myfunc, (), "./output", "myapp"; template=:tiny)
```

Output:
```
Using template: :tiny
  Tiny binaries: maximum size reduction (Phase 1+2 optimizations)

Running pre-compilation analysis...
  [1/1] Analyzing myfunc... ✅ (score: 92/100)

✅ All functions passed verification (min score: 85)

Binary: ./output/myapp
Original size: 2.5 MB
  Stripped symbols
  After stripping: 750 KB (saved 1.75 MB, 70.0%)
Final size: 750 KB
Total reduction: 1.75 MB (70.0%)
```

### 2. With UPX Compression

```julia
compile_executable(myfunc, (), "./output", "myapp";
    template=:tiny,
    compress=true)  # Requires UPX installation
```

Additional 50-70% size reduction on top of stripping!

### 3. Aggressive Optimization

```julia
# Maximum size reduction (may affect compatibility)
cflags = get_size_optimization_flags(aggressive=true)

compile_executable(myfunc, (), "./output", "myapp";
    template=:tiny,
    cflags=cflags)  # Override with aggressive flags
```

Aggressive mode adds:
- `-fno-exceptions`
- `-fno-rtti`
- `-fomit-frame-pointer`
- `-fmerge-all-constants`

### 4. Manual Configuration

Full control over every parameter:

```julia
cflags = get_size_optimization_flags()
ldflags = get_size_optimization_ldflags()

compile_executable(myfunc, (), "./output", "myapp";
    cflags=cflags,
    ldflags=ldflags,
    strip_symbols=true,
    compress=true,
    report_size=true,
    verify=true,
    min_score=90)
```

### 5. Post-Process Existing Binary

Already have a compiled binary? Optimize it:

```julia
postprocess_binary!("./myapp";
    strip_symbols=true,
    compress=true,
    report_size=true)
```

## API Reference

### Templates

**`:tiny`** - Tiny binaries (recommended)
- Size optimization enabled
- Symbol stripping enabled
- Quality verification enabled
- Size reporting enabled

**Other templates:**
- `:embedded` - IoT/embedded systems (strict verification)
- `:performance` - Maximum speed
- `:production` - Production deployment
- `:default` - Standard settings

### Size Optimization Functions

#### `get_size_optimization_flags(; aggressive=false)`

Returns compiler flags for size reduction.

**Arguments:**
- `aggressive::Bool=false` - Use aggressive optimization (may affect compatibility)

**Returns:**
- `Vector{String}` - Compiler flags

**Example:**
```julia
flags = get_size_optimization_flags()
# ["-Os", "-flto", "-ffunction-sections", ...]

aggressive_flags = get_size_optimization_flags(aggressive=true)
# [..., "-fno-exceptions", "-fno-rtti", ...]
```

#### `get_size_optimization_ldflags()`

Returns platform-specific linker flags for size reduction.

**Returns:**
- `Vector{String}` - Linker flags (platform-specific)

**Platform Flags:**
- **macOS:** `-Wl,-dead_strip`, `-Wl,-dead_strip_dylibs`, `-Wl,-no_compact_unwind`
- **Linux:** `-Wl,--gc-sections`, `-Wl,--strip-all`, `-Wl,--as-needed`
- **Windows:** `/OPT:REF`, `/OPT:ICF`

**Example:**
```julia
ldflags = get_size_optimization_ldflags()
# macOS: ["-Wl,-dead_strip", ...]
# Linux: ["-Wl,--gc-sections", ...]
```

#### `postprocess_binary!(path; kwargs...)`

Post-process a compiled binary to reduce size.

**Arguments:**
- `binary_path::String` - Path to binary
- `strip_symbols::Bool=true` - Remove debugging symbols
- `compress::Bool=false` - Compress with UPX (requires UPX)
- `upx_args::Vector{String}=["--best", "--lzma"]` - UPX arguments
- `report_size::Bool=true` - Print size comparison

**Returns:**
- `(original_size::Int, final_size::Int, reduction_pct::Float64)`

**Example:**
```julia
postprocess_binary!("./myapp";
    strip_symbols=true,
    compress=true,
    report_size=true)
```

Output:
```
Binary: ./myapp
Original size: 2.5 MB
  Stripped symbols
  After stripping: 800 KB (saved 1.7 MB, 68.0%)
  After UPX compression: 300 KB (saved 500 KB, 62.5%)
Final size: 300 KB
Total reduction: 2.2 MB (88.0%)
```

#### `format_bytes(n::Integer)`

Format byte count as human-readable string.

**Example:**
```julia
format_bytes(1024)      # "1.0 KB"
format_bytes(1500000)   # "1.4 MB"
format_bytes(1024^3)    # "1.0 GB"
```

### Compilation Parameters

All these parameters work with `compile_executable()`:

**Size Optimization (Phase 1):**
- `cflags` - Compiler flags (Cmd, String, or Vector{String})
- `ldflags` - Linker flags (Cmd, String, or Vector{String})

**Post-Processing (Phase 2):**
- `strip_symbols::Bool=false` - Strip debugging symbols
- `compress::Bool=false` - UPX compression
- `upx_args::Vector{String}` - Custom UPX arguments
- `report_size::Bool=false` - Show size comparison

**Quality Assurance:**
- `verify::Bool=false` - Verify code quality
- `min_score::Int=80` - Minimum quality score (0-100)
- `suggest_fixes::Bool=true` - Show optimization suggestions
- `export_analysis::Bool=false` - Export analysis report

## Platform Support

### Symbol Stripping

| Platform | Command | Status |
|----------|---------|--------|
| macOS | `strip` | ✅ Built-in |
| Linux | `strip` | ✅ Built-in |
| Windows | `strip` | ⚠️ Optional (MinGW/Cygwin) |

### UPX Compression

UPX must be installed separately:

**macOS:**
```bash
brew install upx
```

**Linux:**
```bash
sudo apt-get install upx-ucl  # Debian/Ubuntu
sudo yum install upx          # RHEL/CentOS
```

**Windows:**
Download from: https://upx.github.io/

## Best Practices

### 1. Start with `:tiny` Template

Always start with the template - it provides optimal defaults:

```julia
compile_executable(func, types, path, name; template=:tiny)
```

### 2. Enable Compression if Available

If UPX is installed, enable compression for maximum reduction:

```julia
compile_executable(func, types, path, name;
    template=:tiny,
    compress=true)
```

### 3. Use Aggressive Mode Cautiously

Aggressive optimization may reduce compatibility:

```julia
# Only for controlled environments
cflags = get_size_optimization_flags(aggressive=true)
```

### 4. Verify Code Quality

The `:tiny` template enables verification by default (min_score=85). For production:

```julia
compile_executable(func, types, path, name;
    template=:tiny,
    min_score=90)  # Stricter verification
```

### 5. Check Platform Support

Test on target platform before deployment:
- Symbol stripping may not be available on all Windows systems
- UPX may not support all executable formats

## Troubleshooting

### "strip command not found" (Windows)

Install MinGW or Cygwin, or disable stripping:

```julia
compile_executable(func, types, path, name;
    template=:tiny,
    strip_symbols=false)  # Disable stripping
```

### "UPX not found"

Install UPX or disable compression:

```julia
compile_executable(func, types, path, name;
    template=:tiny,
    compress=false)  # Already the default
```

### Binary Still Large

1. Check if verification is failing (code quality issues)
2. Try aggressive mode
3. Ensure no unnecessary dependencies
4. Use StaticTools.jl for I/O instead of Base functions

### Compatibility Issues with Aggressive Mode

If aggressive mode causes issues:

```julia
# Use non-aggressive (default)
compile_executable(func, types, path, name; template=:tiny)
```

## Examples

See comprehensive examples in:
- `examples/tiny_binaries.jl` - Full examples suite
- `examples/hello_tiny.jl` - Minimal hello world

## Performance Impact

Size optimization has minimal performance impact:

| Optimization | Size Reduction | Performance Impact |
|--------------|----------------|-------------------|
| `-Os` | 30-40% | ~5% slower than `-O3` |
| `-flto` | 10-20% | 0-5% faster (whole-program) |
| Symbol stripping | 40-60% | **No impact** (runtime) |
| UPX compression | 50-70% | ~10-20% slower startup |

**Recommendation:** Use `:tiny` for deployment, standard flags for development.

## Summary

**Three ways to create tiny binaries:**

1. **Easiest:** `template=:tiny` (one command)
2. **Custom:** Use size optimization functions directly
3. **Post-process:** Apply `postprocess_binary!()` to existing binaries

**Expected results:**
- 70-90% size reduction
- Minimal performance impact
- Cross-platform compatibility
- Production-ready quality verification

Start with `:tiny` template and customize as needed!
