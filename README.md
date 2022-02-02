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
@ccall $fptr(2::Int)::Int 

# do this in one step (this time with a temporary shared library)
fptr = generate_shlib_fptr(f, (Int,))
@ccall $fptr(2::Int)::Int 
```

## Approach

This package uses the [GPUCompiler package](https://github.com/JuliaGPU/GPUCompiler.jl) to generate code.

## Limitations 

* This package currently requires that you have `gcc` installed and in your system's `PATH`. This is probably pretty easy to fix, we only use `gcc` for linking. In theory Clang_jll or LLVM_full_jll should be able to do this, and be managed through Julia's package manager. 
* No heap allocations (e.g. creating an array or a string) are allowed inside a statically compiled function body. If you try to run such a function, you will get a segfault.
**  It's sometimes possible you won't get a segfault if you define and run the function in the same session, but trying to call the compiled function in a new julia session will definitely segfault. 
* Lots of other limitations too. E.g. there's an example in tests/runtests.jl where summing a vector of `Complex{Float32}` is fine, but segfaults on `Complex{Float64}`.

