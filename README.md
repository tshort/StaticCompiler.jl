# StaticCompiler

[![CI](https://github.com/tshort/StaticCompiler.jl/workflows/CI/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci.yml)
[![CI (Integration)](https://github.com/tshort/StaticCompiler.jl/workflows/CI%20(Integration)/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-integration.yml)
[![CI (Julia nightly)](https://github.com/tshort/StaticCompiler.jl/workflows/CI%20(Julia%20nightly)/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-julia-nightly.yml)
[![CI (Integration nightly)](https://github.com/tshort/StaticCompiler.jl/workflows/CI%20(Integration%20nightly)/badge.svg)](https://github.com/tshort/StaticCompiler.jl/actions/workflows/ci-integration-nightly.yml)
[![Coverage](https://codecov.io/gh/tshort/StaticCompiler.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/tshort/StaticCompiler.jl)

This is an experimental package to compile Julia code to standalone libraries. A system image is not needed.

## Installation and Usage

```julia
using Pkg
Pkg.add("StaticCompiler")
```

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

See the file `tests/runtests.jl` for some examples of functions that work with static compilation (and some that don't,
marked with `@test_skip`)

## Approach

This package uses the [GPUCompiler package](https://github.com/JuliaGPU/GPUCompiler.jl) to generate code.

## Limitations

* GC-tracked allocations and global variables do work with `compile`, but the way they are implemented is brittle and can be dangerous. Allocate with care.
* GC-tracked allocations and global variables do *not* work with `compile_executable` (yet).
* Type unstable code is not yet supported.
* Doesn't currently work on Windows.
* If you find any other limitations, let us know. There's probably lots.
