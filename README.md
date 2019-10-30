# StaticCompiler

[![Build Status](https://travis-ci.com/tshort/StaticCompiler.jl.svg?branch=master)](https://travis-ci.com/tshort/StaticCompiler.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/tshort/StaticCompiler.jl?svg=true)](https://ci.appveyor.com/project/tshort/StaticCompiler-jl)
[![Codecov](https://codecov.io/gh/tshort/StaticCompiler.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/tshort/StaticCompiler.jl)
[![Coveralls](https://coveralls.io/repos/github/tshort/StaticCompiler.jl/badge.svg?branch=master)](https://coveralls.io/github/tshort/StaticCompiler.jl?branch=master)

This is an experimental package to compile Julia code to standalone libraries. A system image is not needed. It is also meant for cross compilation, so Julia code can be compiled for other targets, including WebAssembly and embedded targets. 

Long term, a better approach may be to use Julia's standard compilation techniques with "tree shaking" to generate a reduced system image (see [here](https://github.com/JuliaLang/julia/issues/33670)). 

This package uses the [LLVM package](https://github.com/maleadt/LLVM.jl) to generate code in the same fashion as [CUDAnative](https://github.com/JuliaGPU/CUDAnative.jl).

Some of the key details of this approach are:

* **ccalls and cglobal** -- When Julia compiles code CUDAnative style, `ccall` and `cglobal` references get compiled to a direct pointer. `StaticCompiler` converts these to symbol references for later linking. For `ccall` with a tuple call to a symbol in a library, `Cassette` is used to convert that to just a symbol reference (no dynamic library loading).

* **Global variables** -- A lot of code gets compiled with global variables, and these get compiled to a direct pointer. `StaticCompiler` includes a basic serialize/deserialize approach. Right now, this is fairly basic, and it takes shortcuts for some objects by swapping in wrong types. This can work because many times, the objects are not really used in the code. Finding the global variable can be a little tricky because the pointer is converted to a Julia object with `unsafe_pointer_to_objref`, and that segfaults for some addresses. How to best handle cases like that is still to be determined.

* **Initialization** -- If libjulia is used, some init code needs to be run to set up garbage collection and other things. For this, a basic `blank.ji` file is used to feed `jl_init_with_image`.

The API still needs work, but here is the general approach right now:

```julia
using StaticCompiler
m = irgen(cos, Tuple{Float64})
fix_globals!(m)
optimize!(m)
write(m, "cos.bc")
write_object(m, "cos.o")
```

`cos.o` should contain a function called `cos`. From there, you need to convert to link as needed with `libjulia`. 

See the `test` directory for more information and types of code that currently run. The most advanced example that works is a call to an ODE solution using modified code from [ODE.jl](https://github.com/JuliaDiffEq/ODE.jl). For information on compiling and linking to an executable, see [test/standalone-exe.jl](./blob/master/test/standalone-exe.jl).

## Known limitations

* It won't work for recursive code. Jameson's [codegen-norecursion](https://github.com/JuliaLang/julia/tree/jn/codegen-norecursion) should fix that when merged.

* `cfunction` is not supported.

* Generic code that uses `jl_apply_generic` does not work. One strategy for this is to use Cassette to swap out known code that uses dynamic calls. Another approach is to write something like `jl_apply_generic` to implement dynamic calls.

* The use of Cassette makes it more difficult for Julia to infer some things, and only type-stable code can be statically compiled with this approach.

* It's only been tested on Linux.

Finally, this whole approach is young and likely brittle. Do not expect it to work for your code.
