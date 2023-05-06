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

## Guide for Package Authors

To enable code to be statically compiled, consider the following:

* Use type-stable code.

* Use Tuples, NamedTuples, StaticArrays, and other types where appropriate. These allocate on the stack and don't use Julia's heap allocation.

* Avoid Julia's internal allocations. That means don't bake in use of Arrays or Strings or Dicts. Types from StaticTools can help, like StaticStrings and MallocArrays.

* If need be, manage memory manually, using `malloc` and `free`. This works with StaticTools.MallocString and StaticTools.MallocArray.

* Don't use global variables that need to be allocated and initialized. Instead of global variables, use context structures that have an initialization function. It is okay to use global Tuples or NamedTuples as the use of these should be baked into compiled code.

* Use context variables to store program state, inputs, and outputs. Parameterize these typese as needed, so your code can handle normal types (Arrays) and static-friendly types (StaticArrays, MallocArrays, or StrideArrays). The SciML ecosystem does this well ([example](https://github.com/SciML/OrdinaryDiffEq.jl/blob/e7f045950615352ddfcb126d13d92afd2bad05e4/src/integrators/type.jl#L82)). Use of these context variables also enables allocations and initialization to be centralized, so these could be managed by the calling routines in Julia, Python, JavaScript, or other language.

* If your code needs an array as a workspace, instead of directly creating it, create it as a function argument (where it could default to a standard array creation). That code could be statically compiled if that function argument is changed to a MallocArray or another static-friendly alternative. 

* Use [Bumper.jl](https://github.com/MasonProtter/Bumper.jl) to avoid allocations in some loops.

## Guide for Statically Compiling Code

If you're trying to statically compile generic code, you may run into issues if that code uses features not supported by StaticCompiler. One option is to change the code you're calling using the tips above. If that is not easy, you may by able to compile it anyway. One option is to use method overrides to change what methods are called. Another option is to use the Mixtape feature to change problematic code as part of compilation. For example, you could convert all Strings to StaticStrings.

[Cthulhu](https://github.com/JuliaDebug/Cthulhu.jl) is a great help in digging into code, finding type instabilities, and finding other sources of code that may break static compilation.

## Foreign Function Interfacing

Because Julia objects follow C memory layouts, compiled libraries should be usable from most languages that can interface with C. For example, results should be usable with Python's [CFFI](https://cffi.readthedocs.io/en/latest/) package.

For WebAssembly, interface helpers are available at [WebAssemblyInterfaces](https://github.com/tshort/WebAssemblyInterfaces.jl).






