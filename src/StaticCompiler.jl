module StaticCompiler
using InteractiveUtils
using GPUCompiler: GPUCompiler
using LLVM
using LLVM.Interop
using LLVM: API
using Libdl: Libdl, dlsym, dlopen
using Base: RefValue
using Serialization: serialize, deserialize
using Clang_jll: clang
using LLD_jll: lld
using StaticTools
using StaticTools: @symbolcall, @c_str, println


export compile, load_function, compile_shlib, compile_executable, compile_wasm
export native_code_llvm, native_code_typed, native_llvm_module, native_code_native
export @device_override, @print_and_throw

include("mixtape.jl")
include("interpreter.jl")
include("target.jl")
include("pointer_patching.jl")
include("code_loading.jl")
include("optimize.jl")
include("quirks.jl")

fix_name(f::Function) = fix_name(repr(f))
fix_name(s) = String(GPUCompiler.safe_name(s))

"""
    compile(f, types, path::String = tempname()) --> (compiled_f, path)

   !!! Warning: this will fail on programs that have dynamic dispatch !!!

Statically compile the method of a function `f` specialized to arguments of the type given by `types`.

This will create a directory at the specified path (or in a temporary directory if you exclude that argument)
that contains the files needed for your static compiled function. `compile` will return a
`StaticCompiledFunction` object and `obj_path` which is the absolute path of the directory containing the
compilation artifacts. The `StaticCompiledFunction` can be treated as if it is a function with a single
method corresponding to the types you specified when it was compiled.

To deserialize and instantiate a previously compiled function, simply execute `load_function(path)`, which
returns a callable `StaticCompiledFunction`.

### Example:

Define and compile a `fib` function:
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
julia> fib
ERROR: UndefVarError: fib not defined

julia> using StaticCompiler

julia> fib_compiled = load_function("fib.cjl")
fib(::Int64) :: Int64

julia> fib_compiled(10)
55
```
Tada!

### Details:

Here is the structure of the directory created by `compile` in the above example:
```julia
shell> tree fib
path
├── obj.cjl
└── obj.o

0 directories, 3 files
````
* `obj.o` contains statically compiled code in the form of an LLVM generated object file.
* `obj.cjl` is a serialized `LazyStaticCompiledFunction` object which will be deserialized and instantiated
with `load_function(path)`. `LazyStaticcompiledfunction`s contain the requisite information needed to link to the
`obj.o` inside a julia session. Once it is instantiated in a julia session (i.e. by
`instantiate(::LazyStaticCompiledFunction)`, this happens automatically in `load_function`), it will be of type
`StaticCompiledFunction` and may be called with arguments of type `types` as if it were a function with a
single method (the method determined by `types`).
"""
function compile(f, _tt, path::String = tempname();
                 mixtape = NoContext(),
                 name = fix_name(f),
                 filename = "obj",
                 strip_llvm = false,
                 strip_asm  = true,
                 opt_level=3,
                 kwargs...)

    tt = Base.to_tuple_type(_tt)
    isconcretetype(tt) || error("input type signature $_tt is not concrete")

    rt = last(only(native_code_typed(f, tt, mixtape = mixtape)))
    isconcretetype(rt) || error("$f on $_tt did not infer to a concrete type. Got $rt")
    f_wrap!(out::Ref, args::Ref{<:Tuple}) = (out[] = f(args[]...); nothing)
    _, _, table = generate_obj_for_compile(f_wrap!, Tuple{RefValue{rt}, RefValue{tt}}, false, path, name; mixtape = mixtape, opt_level, strip_llvm, strip_asm, filename, kwargs...)

    lf = LazyStaticCompiledFunction{rt, tt}(Symbol(f), path, name, filename, table)
    cjl_path = joinpath(path, "$filename.cjl")
    serialize(cjl_path, lf)

    (; f = instantiate(lf), path=abspath(path))
end

"""
```julia
generate_obj_for_compile(f, tt, path::String = tempname(), name = fix_name(f), filenamebase::String="obj";
            \tmixtape = NoContext(),
            \tstrip_llvm = false,
            \tstrip_asm = true,
            \ttarget = (),
            \topt_level = 3,
            \tkwargs...)
```
Low level interface for compiling object code (`.o`) for for function `f` given
a tuple type `tt` characterizing the types of the arguments for which the
function will be compiled.

`mixtape` defines a context that can be used to transform IR prior to compilation using
[Mixtape](https://github.com/JuliaCompilerPlugins/Mixtape.jl) features.

`target` can be used to change the output target. This is useful for compiling to WebAssembly and embedded targets.
This is a named tuple with fields `triple`, `cpu`, and `features` (each of these are strings).
The defaults compile to the native target.

### Examples
```julia
julia> fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)
fib (generic function with 1 method)

julia> path, name, table = StaticCompiler.generate_obj_for_compile(fib, Tuple{Int64}, "./test")
("./test", "fib", IdDict{Any, String}())

shell> tree \$path
./test
└── obj.o

0 directories, 1 file
```
"""
function generate_obj_for_compile(f, tt, external = true, path::String = tempname(), name = fix_name(f), filenamebase::String="obj";
                        mixtape = NoContext(),
                        strip_llvm = false,
                        strip_asm = true,
                        opt_level = 3,
                        remove_julia_addrspaces = false,
                        target = (),
                        kwargs...)
    mkpath(path)
    obj_path = joinpath(path, "$filenamebase.o")
    #Get LLVM to generated a module of code for us. We don't want GPUCompiler's optimization passes.
    params = StaticCompilerParams(opt = true, mixtape = mixtape, optlevel = Base.JLOptions().opt_level)
    config = GPUCompiler.CompilerConfig(NativeCompilerTarget(target...), params, name = name, kernel = false)
    job = GPUCompiler.CompilerJob(GPUCompiler.methodinstance(typeof(f), tt), config)

    mod, meta = GPUCompiler.JuliaContext() do context
        GPUCompiler.codegen(:llvm, job; strip=strip_llvm, only_entry=false, validate=false, optimize=false, ctx=context)
    end

    # Use Enzyme's annotation and optimization pipeline
    annotate!(mod)
    tm = GPUCompiler.llvm_machine(external ? ExternalNativeCompilerTarget(target...) : NativeCompilerTarget(target...))
    optimize!(mod, tm)

    # Scoop up all the pointers in the optimized module, and replace them with unitialized global variables.
    # `table` is a dictionary where the keys are julia objects that are needed by the function, and the values
    # of the dictionary are the names of their associated LLVM GlobalVariable names.
    table = relocation_table!(mod)

    # Now that we've removed all the pointers from the code, we can (hopefully) safely lower all the instrinsics
    # (again, using Enzyme's pipeline)
    post_optimize!(mod, tm; remove_julia_addrspaces)

    # Make sure we didn't make any glaring errors
    LLVM.verify(mod)

    # Compile the LLVM module to native code and save it to disk
    obj, _ = GPUCompiler.emit_asm(job, mod; strip=strip_asm, validate=false, format=LLVM.API.LLVMObjectFile)
    open(obj_path, "w") do io
        write(io, obj)
    end
    path, name, table
end

"""
```julia
compile_executable(f::Function, types::Tuple, path::String, [name::String=repr(f)];
    filename::String=name,
    cflags=``, # Specify libraries you would like to link against, and other compiler options here
    also_expose=[],
    kwargs...
)
```
Attempt to compile a standalone executable that runs function `f` with a type signature given by the tuple of `types`.
If there are extra methods you would like to protect from name mangling in the produced binary for whatever reason,
you can provide them as a vector of tuples of functions and types, i.e. `[(f1, types1), (f2, types2), ...]`

### Examples
```julia
julia> using StaticCompiler

julia> function puts(s::Ptr{UInt8}) # Can't use Base.println because it allocates.
           # Note, this `llvmcall` requires Julia 1.8+
           Base.llvmcall((\"\"\"
           ; External declaration of the puts function
           declare i32 @puts(i8* nocapture) nounwind

           define i32 @main(i8*) {
           entry:
               %call = call i32 (i8*) @puts(i8* %0)
               ret i32 0
           }
           \"\"\", "main"), Int32, Tuple{Ptr{UInt8}}, s)
       end
puts (generic function with 1 method)

julia> function print_args(argc::Int, argv::Ptr{Ptr{UInt8}})
           for i=1:argc
               # Get pointer
               p = unsafe_load(argv, i)
               # Print string at pointer location (which fortunately already exists isn't tracked by the GC)
               puts(p)
           end
           return 0
       end

julia> compile_executable(print_args, (Int, Ptr{Ptr{UInt8}}))
""/Users/user/print_args""

shell> ./print_args 1 2 3 4 Five
./print_args
1
2
3
4
Five
```
```julia
julia> using StaticTools # So you don't have to define `puts` and friends every time

julia> hello() = println(c"Hello, world!") # c"..." makes a stack-allocated StaticString

julia> compile_executable(hello)
"/Users/cbkeller/hello"

shell> ls -alh hello
-rwxr-xr-x  1 user  staff    33K Mar 20 21:11 hello

shell> ./hello
Hello, world!
```
"""
function compile_executable(f::Function, types=(), path::String="./", name=fix_name(f);
                            also_expose=Tuple{Function, Tuple{DataType}}[],
                            kwargs...)
    compile_executable(vcat([(f, types)], also_expose), path, name; kwargs...)
end

function compile_executable(funcs::Union{Array,Tuple}, path::String="./", name=fix_name(first(first(funcs)));
        filename = name,
        demangle = true,
        cflags = ``,
        kwargs...
    )

    (f, types) = funcs[1]
    tt = Base.to_tuple_type(types)
    isexecutableargtype = tt == Tuple{} || tt == Tuple{Int, Ptr{Ptr{UInt8}}}
    isexecutableargtype || @warn "input type signature $types should be either `()` or `(Int, Ptr{Ptr{UInt8}})` for standard executables"

    rt = last(only(native_code_typed(f, tt; kwargs...)))
    isconcretetype(rt) || error("`$f$types` did not infer to a concrete type. Got `$rt`")
    nativetype = isprimitivetype(rt) || isa(rt, Ptr)
    nativetype || @warn "Return type `$rt` of `$f$types` does not appear to be a native type. Consider returning only a single value of a native machine type (i.e., a single float, int/uint, bool, or pointer). \n\nIgnoring this warning may result in Undefined Behavior!"

    generate_executable(funcs, path, name, filename; demangle, cflags, kwargs...)
    joinpath(abspath(path), filename)
end

"""
```julia
compile_shlib(f::Function, types::Tuple, [path::String="./"], [name::String=repr(f)]; filename::String=name, cflags=``, kwargs...)
compile_shlib(funcs::Array, [path::String="./"]; filename="libfoo", demangle=true, cflags=``, kwargs...)
```
As `compile_executable`, but compiling to a standalone `.dylib`/`.so` shared library.

If `demangle` is set to `false`, compiled function names are prepended with "julia_".

### Examples
```julia
julia> using StaticCompiler, LoopVectorization

julia> function test(n)
                  r = 0.0
                  @turbo for i=1:n
                      r += log(sqrt(i))
                  end
                  return r/n
              end
test (generic function with 1 method)

julia> compile_shlib(test, (Int,))
"/Users/user/test.dylib"

julia> test(100_000)
5.2564961094956075

julia> ccall(("test", "test.dylib"), Float64, (Int64,), 100_000)
5.2564961094956075
```
"""
function compile_shlib(f::Function, types=(), path::String="./", name=fix_name(f);
        filename=name,
        kwargs...
    )
    compile_shlib(((f, types),), path; filename, kwargs...)
end
# As above, but taking an array of functions and returning a single shlib
function compile_shlib(funcs::Union{Array,Tuple}, path::String="./";
        filename = "libfoo",
        demangle = true,
        cflags = ``,
        kwargs...
    )
    for func in funcs
        f, types = func
        tt = Base.to_tuple_type(types)
        isconcretetype(tt) || error("input type signature `$types` is not concrete")

        rt = last(only(native_code_typed(f, tt)))
        isconcretetype(rt) || error("`$f$types` did not infer to a concrete type. Got `$rt`")
        nativetype = isprimitivetype(rt) || isa(rt, Ptr)
        nativetype || @warn "Return type `$rt` of `$f$types` does not appear to be a native type. Consider returning only a single value of a native machine type (i.e., a single float, int/uint, bool, or pointer). \n\nIgnoring this warning may result in Undefined Behavior!"
    end

    generate_shlib(funcs, true, path, filename; demangle, cflags, kwargs...)

    joinpath(abspath(path), filename * "." * Libdl.dlext)
end

"""
```julia
compile_wasm(f::Function, types::Tuple, [path::String="./"], [name::String=repr(f)]; filename::String=name, flags=``, kwargs...)
compile_wasm(funcs::Union{Array,Tuple}, [path::String="./"]; filename="libfoo", demangle=true, flags=``, kwargs...)
```
As `compile_shlib`, but compiling to a WebAssembly library.

If `demangle` is set to `false`, compiled function names are prepended with "julia_".
```
"""
function compile_wasm(f::Function, types=();
        path::String = "./",
        filename = fix_name(f),
        flags = ``,
        kwargs...
    )
    tt = Base.to_tuple_type(types)
    obj_path, name = generate_obj_for_compile(f, tt, true, path, filename; target = (triple = "wasm32-unknown-wasi", cpu = "", features = ""), remove_julia_addrspaces = true, kwargs...)
    run(`$(lld()) -flavor wasm --no-entry --export-all $flags $obj_path/obj.o -o $path/$name.wasm`)
    joinpath(abspath(path), filename * ".wasm")
end
function compile_wasm(funcs::Union{Array,Tuple};
        path::String="./",
        filename="libfoo",
        flags=``,
        kwargs...
    )
    obj_path, name = generate_obj(funcs, true; target = (triple = "wasm32-unknown-wasi", cpu = "", features = ""), remove_julia_addrspaces = true, kwargs...)
    run(`$(lld()) -flavor wasm --no-entry --export-all $flags $obj_path/obj.o -o $path/$filename.wasm`)
    joinpath(abspath(path), filename * ".wasm")
end

"""
```julia
generate_shlib_fptr(path::String, name)
```
Low level interface for obtaining a function pointer by `dlopen`ing a shared
library given the `path` and `name` of a `.so`/`.dylib` already compiled by
`generate_shlib`.

See also `StaticCompiler.generate_shlib`.

### Examples
```julia
julia> function test(n)
           r = 0.0
           for i=1:n
               r += log(sqrt(i))
           end
           return r/n
       end
test (generic function with 1 method)

julia> path, name = StaticCompiler.generate_shlib(test, Tuple{Int64}, "./test");

julia> test_ptr = StaticCompiler.generate_shlib_fptr(path, name)
Ptr{Nothing} @0x000000015209f600

julia> ccall(test_ptr, Float64, (Int64,), 100_000)
5.256496109495593

julia> @ccall \$test_ptr(100_000::Int64)::Float64 # Equivalently
5.256496109495593

julia> test(100_000)
5.256496109495593
```
"""
function generate_shlib_fptr(path::String, name, filename::String=name)
    lib_path = joinpath(abspath(path), "$filename.$(Libdl.dlext)")
    ptr = Libdl.dlopen(lib_path, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, name)
    @assert fptr != C_NULL
    fptr
end
# As above, but also compile (maybe remove this method in the future?)
function generate_shlib_fptr(f, tt, path::String=tempname(), name=fix_name(f), filename::String=name;
                            temp::Bool=true,
                            kwargs...)

    generate_shlib(f, tt, false, path, name; kwargs...)
    lib_path = joinpath(abspath(path), "$filename.$(Libdl.dlext)")
    ptr = Libdl.dlopen(lib_path, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, name)
    @assert fptr != C_NULL
    if temp
        atexit(()->rm(path; recursive=true))
    end
    fptr
end

"""
```julia
generate_executable(f, tt, path::String, name, filename=string(name); kwargs...)
```
Attempt to compile a standalone executable that runs `f`.
Low-level interface; you should generally use `compile_executable` instead.

### Examples
```julia
julia> using StaticCompiler, StaticTools

julia> hello() = println(c"Hello, world!")

julia> path, name = StaticCompiler.generate_executable(hello, Tuple{}, "./")
("./", "hello")

shell> ./hello
Hello, world!
```
"""
generate_executable(f, tt, args...; kwargs...) = generate_executable(((f, tt),), args...; kwargs...)
function generate_executable(funcs::Union{Array,Tuple}, path=tempname(), name=fix_name(first(first(funcs))), filename=name;
                             demangle = true,
                             cflags = ``,
                             kwargs...
                             )
    lib_path = joinpath(path, "$filename.$(Libdl.dlext)")
    exec_path = joinpath(path, filename)
    external = true
    _, obj_path = generate_obj(funcs, external, path, filename; demangle, kwargs...)
    # Pick a compiler
    cc = Sys.isapple() ? `cc` : clang()
    # Compile!
    if Sys.isapple()
        # Apple no longer uses _start, so we can just specify a custom entry
        entry = demangle ? "_$name" : "_julia_$name"
        run(`$cc -e $entry $cflags $obj_path -o $exec_path`)
    else
        fn = demangle ? "$name" : "julia_$name"
        # Write a minimal wrapper to avoid having to specify a custom entry
        wrapper_path = joinpath(path, "wrapper.c")
        f = open(wrapper_path, "w")
        print(f, """int $fn(int argc, char** argv);
        void* __stack_chk_guard = (void*) $(rand(UInt) >> 1);

        int main(int argc, char** argv)
        {
            $fn(argc, argv);
            return 0;
        }""")
        close(f)
        run(`$cc $wrapper_path $cflags $obj_path -o $exec_path`)
        # Clean up
        run(`rm $wrapper_path`)
    end
    path, name
end


"""
```julia
generate_shlib(f::Function, tt, [external::Bool=true], [path::String], [name], [filename]; kwargs...)
generate_shlib(funcs::Array, [external::Bool=true], [path::String], [filename::String]; demangle=true, kwargs...)
```
Low level interface for compiling a shared object / dynamically loaded library
 (`.so` / `.dylib`) for function `f` given a tuple type `tt` characterizing
the types of the arguments for which the function will be compiled.

If `demangle` is set to `false`, compiled function names are prepended with "julia_".

### Examples
```julia
julia> using StaticCompiler, LoopVectorization

julia> function test(n)
           r = 0.0
           @turbo for i=1:n
               r += log(sqrt(i))
           end
           return r/n
       end
test (generic function with 1 method)

julia> path, name = StaticCompiler.generate_shlib(test, Tuple{Int64}, true, "./example")
("./example", "test")

shell> tree \$path
./example
|-- test.dylib
`-- test.o
0 directories, 2 files

julia> test(100_000)
5.2564961094956075

julia> ccall(("test", "example/test.dylib"), Float64, (Int64,), 100_000)
5.2564961094956075
```
"""
function generate_shlib(f::Function, tt, external::Bool=true, path::String=tempname(), name=fix_name(f), filename=name; kwargs...)
    generate_shlib(((f, tt),), external, path, filename; kwargs...)
end
# As above, but taking an array of functions and returning a single shlib
function generate_shlib(funcs::Union{Array,Tuple}, external::Bool=true, path::String=tempname(), filename::String="libfoo";
        demangle = true,
        cflags = ``,
        kwargs...
    )

    lib_path = joinpath(path, "$filename.$(Libdl.dlext)")

    _, obj_path = generate_obj(funcs, external, path, filename; demangle, kwargs...)
    # Pick a Clang
    cc = Sys.isapple() ? `cc` : clang()
    # Compile!
    run(`$cc -shared $cflags $obj_path -o $lib_path `)

    path, name
end

function native_code_llvm(@nospecialize(func), @nospecialize(types); kwargs...)
    job, kwargs = native_job(func, types, true; kwargs...)
    GPUCompiler.code_llvm(stdout, job; kwargs...)
end

function native_code_typed(@nospecialize(func), @nospecialize(types); kwargs...)
    job, kwargs = native_job(func, types, true; kwargs...)
    GPUCompiler.code_typed(job; kwargs...)
end

function native_code_native(@nospecialize(f), @nospecialize(tt), fname=fix_name(f); kwargs...)
    job, kwargs = native_job(f, tt, true; fname, kwargs...)
    GPUCompiler.code_native(stdout, job; kwargs...)
end

# Return an LLVM module
function native_llvm_module(f, tt, name=fix_name(f); demangle, kwargs...)
    if !demangle
        name = "julia_"*name
    end
    job, kwargs = native_job(f, tt, true; name, kwargs...)
    m, _ = GPUCompiler.JuliaContext() do context
        GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false, ctx=context)
    end
    return m
end

#Return an LLVM module for multiple functions
function native_llvm_module(funcs::Union{Array,Tuple}; demangle=true, kwargs...)
    f,tt = funcs[1]
    mod = native_llvm_module(f,tt; demangle, kwargs...)
    if length(funcs) > 1
        for func in funcs[2:end]
            f,tt = func
            tmod = native_llvm_module(f,tt; demangle, kwargs...)
            link!(mod,tmod)
        end
    end
    # Just to be sure
    for (modfunc, func) in zip(functions(mod), funcs)
        fname = name(modfunc)
        expectedname = (demangle ? "" : "julia_") * fix_name(func)
        d = prefixlen(fname) - prefixlen(expectedname) + 1
        if d > 1
            name!(modfunc,fname[d:end])
        end
    end
    LLVM.ModulePassManager() do pass_manager #remove duplicate functions
        LLVM.merge_functions!(pass_manager)
        LLVM.run!(pass_manager, mod)
    end
    return mod
end

function prefixlen(s)
    m = match(r"^(?:julia_)+", s)
    if m isa RegexMatch
        length(m.match)
    else
        0
    end
end

"""
```julia
generate_obj(f, tt, external::Bool, path::String = tempname(), filenamebase::String="obj";
             mixtape = NoContext(),
             target = (),
             demangle = true,
             strip_llvm = false,
             strip_asm  = true,
             opt_level = 3,
             kwargs...)
```
Low level interface for compiling object code (`.o`) for for function `f` given
a tuple type `tt` characterizing the types of the arguments for which the
function will be compiled.

`mixtape` defines a context that can be used to transform IR prior to compilation using
[Mixtape](https://github.com/JuliaCompilerPlugins/Mixtape.jl) features.

`target` can be used to change the output target. This is useful for compiling to WebAssembly and embedded targets.
This is a named tuple with fields `triple`, `cpu`, and `features` (each of these are strings).
The defaults compile to the native target.

If `demangle` is set to `false`, compiled function names are prepended with "julia_".

### Examples
```julia
julia> fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)
fib (generic function with 1 method)

julia> path, name, table = StaticCompiler.generate_obj_for_compile(fib, Tuple{Int64}, "./test")
("./test", "fib", IdDict{Any, String}())

shell> tree \$path
./test
└── obj.o

0 directories, 1 file
```
"""
function generate_obj(f, tt, args...; kwargs...)
    generate_obj(((f, tt),), args...; kwargs...)
end


"""
```julia
generate_obj(funcs::Union{Array,Tuple}, external::Bool, path::String = tempname(), filenamebase::String="obj";
             mixtape = NoContext(),
             target = (),
             demangle =false,
             strip_llvm = false,
             strip_asm  = true,
             opt_level=3,
             kwargs...)
```
Low level interface for compiling object code (`.o`) for an array of Tuples
(f, tt) where each function `f` and tuple type `tt` determine the set of methods
which will be compiled.

`mixtape` defines a context that can be used to transform IR prior to compilation using
[Mixtape](https://github.com/JuliaCompilerPlugins/Mixtape.jl) features.

`target` can be used to change the output target. This is useful for compiling to WebAssembly and embedded targets.
This is a named tuple with fields `triple`, `cpu`, and `features` (each of these are strings).
The defaults compile to the native target.
"""
function generate_obj(funcs::Union{Array,Tuple}, external::Bool, path::String = tempname(), filenamebase::String="obj";
                        demangle = true,
                        strip_llvm = false,
                        strip_asm = true,
                        opt_level = 3,
                        kwargs...)
    f, tt = funcs[1]
    mkpath(path)
    obj_path = joinpath(path, "$filenamebase.o")
    fakejob, kwargs = native_job(f, tt, external; kwargs...)
    mod = native_llvm_module(funcs; demangle, kwargs...)
    obj, _ = GPUCompiler.emit_asm(fakejob, mod; strip=strip_asm, validate=false, format=LLVM.API.LLVMObjectFile)
    open(obj_path, "w") do io
        write(io, obj)
    end
    path, obj_path
end

end # module
