# StaticCompiler

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tshort.github.io/StaticCompiler.jl/dev)
[![Build Status](https://travis-ci.com/tshort/StaticCompiler.jl.svg?branch=master)](https://travis-ci.com/tshort/StaticCompiler.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/tshort/StaticCompiler.jl?svg=true)](https://ci.appveyor.com/project/tshort/StaticCompiler-jl)
[![Codecov](https://codecov.io/gh/tshort/StaticCompiler.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/tshort/StaticCompiler.jl)
[![Coveralls](https://coveralls.io/repos/github/tshort/StaticCompiler.jl/badge.svg?branch=master)](https://coveralls.io/github/tshort/StaticCompiler.jl?branch=master)

This is an experimental package to compile Julia code to standalone libraries. A system image is not needed. It is also meant for cross compilation, so Julia code can be compiled for other targets, including WebAssembly and embedded targets.

## Installation and Usage

```julia
using Pkg
Pkg.add(PackageSpec( url = "https://github.com/tshort/StaticCompiler.jl", rev = "master"))
```

```julia
using StaticCompiler
f(x) = 2x

# compile `f` and return an LLVM module
m = compile(f, (Int,))

# compile `f` and write to a shared library ("f.so" or "f.dll")
generate_shlib(f, (Int,), "libf")
# find a function pointer for this shared library 
fptr = generate_shlib_fptr("libf", "f")
ccall(fptr, Int, (Int,), 2)

# do this in one step (this time with a temporary shared library)
fptr = generate_shlib_fptr(f, (Int,))
ccall(fptr, Int, (Int,), 2)

```

## Approach

This package uses the [GPUCompiler package](https://github.com/JuliaGPU/GPUCompiler.jl) to generate code.

