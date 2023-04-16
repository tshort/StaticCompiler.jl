# StaticCompiler

[![CI](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci.yml)
[![CI (Integration)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-integration.yml/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-integration.yml)
[![CI (Julia nightly)](https://github.com/tshort/StaticCompiler.jl/workflows/CI%20(Julia%20nightly)/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-julia-nightly.yml)
[![CI (Integration nightly)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-integration-nightly.yml/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-integration-nightly.yml)
[![Coverage](https://codecov.io/gh/tshort/StaticCompiler.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/tshort/StaticCompiler.jl)

This is an experimental package to compile Julia code to standalone libraries. A system image is not needed.

## Installation and Usage
Installation is the same as any other registered Julia package
```julia
using Pkg
Pkg.add("StaticCompiler")
```

There are two main ways to use this package:

### Linked compilation
The first option is via the `compile` function, which can be used when you want to compile a Julia function for later use from within Julia:
```julia
julia> using StaticCompiler

julia> fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)
fib (generic function with 1 method)

julia> fib_compiled, path = compile(fib, Tuple{Int}, "fib")
(f = fib(::Int64) :: Int64, path = "fib")

julia> fib_compiled(10)
55
```
Now we can quit this session and load a new one where `fib` is not defined:
```julia
julia> using StaticCompiler

julia> fib
ERROR: UndefVarError: fib not defined

julia> fib_compiled = load_function("fib")
fib(::Int64) :: Int64

julia> fib_compiled(10)
55
```
See the file `tests/runtests.jl` for some examples of functions that work with `compile` (and some that don't, marked with `@test_skip`).

### Standalone compilation
The second way to use this package is via the `compile_executable` and `compile_shlib` functions, for when you want to compile a Julia function to a native executable or shared library for use from outside of Julia:
```julia
julia> using StaticCompiler, StaticTools

julia> hello() = println(c"Hello, world!")
hello (generic function with 1 method)

julia> compile_executable(hello, (), "./")
"/Users/user/hello"

shell> ls -alh hello
-rwxrwxr-x. 1 user user 8.4K Oct 20 20:36 hello

shell> ./hello
Hello, world!
```
This latter approach comes with substantially more limitations, as you cannot rely on `libjulia` (see, e.g., [StaticTools.jl](https://github.com/brenhinkeller/StaticTools.jl) for some ways to work around these limitations).

The low-level function `StaticCompiler.generate_obj` (not exported) generates object files. This can be used for more control of compilation. This can be used to cross-compile to other targets.

### Mixtape

This feature allows one to change functionality when statically compiling. This uses code and API from [Mixtape](https://github.com/JuliaCompilerPlugins/Mixtape.jl) to transform lowered code much like [Cassette](https://github.com/JuliaLabs/Cassette.jl).

To use the Mixtape feature, define a `CompilationContext` struct and pass this to any of the compilation functions with the `mixtape` keyword. Define `transform` and `allow` functions for this `CompilationContext` to define the transformation to be done.

See [here](https://github.com/tshort/StaticCompiler.jl/blob/master/test/testintegration.jl#L329) for an example.

## Approach

This package uses the [GPUCompiler package](https://github.com/JuliaGPU/GPUCompiler.jl) to generate code.

## Limitations

* GC-tracked allocations and global variables do work with `compile`, but the way they are implemented is brittle and can be dangerous. Allocate with care.
* GC-tracked allocations and global variables do *not* work with `compile_executable` or `compile_shlib`. This has some interesting consequences, including that all functions _within_ the function you want to compile must either be inlined or return only native types (otherwise Julia would have to allocate a place to put the results, which will fail).
* Since error handling relies on libjulia, you can only throw errors from standalone-compiled (`compile_executable` / `compile_shlib`) code if an explicit overload has been defined for that particular error with `@device_override` (see [quirks.jl](src/quirks.jl)).
* Type instability. Type unstable code cannot currently be statically compiled via this package.
* Doesn't work on Windows. PRs welcome.
