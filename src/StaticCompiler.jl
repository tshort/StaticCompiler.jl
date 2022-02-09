module StaticCompiler

using GPUCompiler: GPUCompiler
using LLVM: LLVM
using Libdl: Libdl
using Base: RefValue
using Serialization: serialize, deserialize
using Clang_jll: clang

export compile, load_function, compile_executable
export native_code_llvm, native_code_typed, native_llvm_module

"""
    compile(f, types, path::String = tempname()) --> (compiled_f, path)

   !!! Warning: this will fail on programs that heap allocate any memory tracked by the GC, or have dynamic dispatch !!!

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
├── obj.o
└── obj.so

0 directories, 3 files
````
* `obj.so` (or `.dylib` on MacOS) is a shared object file that can be linked to in order to execute your
compiled julia function.
* `obj.cjl` is a serialized `LazyStaticCompiledFunction` object which will be deserialized and instantiated
with `load_function(path)`. `LazyStaticcompiledfunction`s contain the requisite information needed to link to the
`obj.so` inside a julia session. Once it is instantiated in a julia session (i.e. by
`instantiate(::LazyStaticCompiledFunction)`, this happens automatically in `load_function`), it will be of type
`StaticCompiledFunction` and may be called with arguments of type `types` as if it were a function with a
single method (the method determined by `types`).
"""
function compile(f, _tt, path::String = tempname();  name = GPUCompiler.safe_name(repr(f)), kwargs...)
    tt = Base.to_tuple_type(_tt)
    isconcretetype(tt) || error("input type signature $_tt is not concrete")

    rt = only(native_code_typed(f, tt))[2]
    isconcretetype(rt) || error("$f on $_tt did not infer to a concrete type. Got $rt")

    # Would be nice to use a compiler pass or something to check if there are any heap allocations or references to globals
    # Keep an eye on https://github.com/JuliaLang/julia/pull/43747 for this

    f_wrap!(out::Ref, args::Ref{<:Tuple}) = (out[] = f(args[]...); nothing)

    generate_shlib(f_wrap!, Tuple{RefValue{rt}, RefValue{tt}}, path, name; kwargs...)

    lf = LazyStaticCompiledFunction{rt, tt}(Symbol(f), path, name)
    cjl_path = joinpath(path, "obj.cjl")
    serialize(cjl_path, lf)
    (; f = instantiate(lf), path=abspath(path))
end

"""
    load_function(path) --> compiled_f

load a `StaticCompiledFunction` from a given path. This object is callable.
"""
load_function(path) = instantiate(deserialize(joinpath(path, "obj.cjl")) :: LazyStaticCompiledFunction)

struct LazyStaticCompiledFunction{rt, tt}
    f::Symbol
    path::String
    name::String
end

function instantiate(p::LazyStaticCompiledFunction{rt, tt}) where {rt, tt}
    StaticCompiledFunction{rt, tt}(p.f, generate_shlib_fptr(p.path::String, p.name))
end

struct StaticCompiledFunction{rt, tt}
    f::Symbol
    ptr::Ptr{Nothing}
end

function Base.show(io::IO, f::StaticCompiledFunction{rt, tt}) where {rt, tt}
    types = [tt.parameters...]
    print(io, String(f.f), "(", join(("::$T" for T ∈ tt.parameters), ',')  ,") :: $rt")
end

function (f::StaticCompiledFunction{rt, tt})(args...) where {rt, tt}
    Tuple{typeof.(args)...} == tt || error("Input types don't match compiled target $((tt.parameters...,)). Got arguments of type $(typeof.(args))")
    out = RefValue{rt}()
    refargs = Ref(args)
    ccall(f.ptr, Nothing, (Ref{rt}, Ref{tt}), out, refargs)
    out[]
end

instantiate(f::StaticCompiledFunction) = f


"""
```julia
compile_executable(f, types::Tuple, path::String, name::String=repr(f); filename::String=name, kwargs...)
```
Attempt to compile a standalone executable that runs function `f` with a type signature given by the tuple of `types`.

### Examples
```julia
julia> using StaticCompiler

julia> function puts(s::Ptr{UInt8}) # Can't use Base.println because it allocates
           Base.llvmcall((\"""
           ; External declaration of the puts function
           declare i32 @puts(i8* nocapture) nounwind

           define i32 @main(i8*) {
           entry:
               %call = call i32 (i8*) @puts(i8* %0)
               ret i32 0
           }
           \""", "main"), Int32, Tuple{Ptr{UInt8}}, s)
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
"/Users/foo/code/StaticCompiler.jl/print_args"

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
"/Users/foo/code/StaticCompiler.jl/hello"

shell> ./hello
Hello, world!
```
"""
function compile_executable(f, _tt=(), path::String="./", name=GPUCompiler.safe_name(repr(f)); filename=name, kwargs...)
    tt = Base.to_tuple_type(_tt)
    tt == Tuple{} || tt == Tuple{Int, Ptr{Ptr{UInt8}}} || error("input type signature $_tt must be either () or (Int, Ptr{Ptr{UInt8}})")

    rt = only(native_code_typed(f, tt))[2]
    # Warning instead of error because return values are probably going to be ignored anyways
    isconcretetype(rt) || @warn "$f$_tt did not infer to a concrete type. Got $rt."

    # Would be nice to use a compiler pass or something to check if there are any heap allocations or references to globals
    # Keep an eye on https://github.com/JuliaLang/julia/pull/43747 for this

    generate_executable(f, tt, path, name, filename; kwargs...)

    joinpath(abspath(path), filename)
end


module TestRuntime
    # dummy methods
    signal_exception() = return
    # HACK: if malloc returns 0 or traps, all calling functions (like jl_box_*)
    #       get reduced to a trap, which really messes with our test suite.
    malloc(sz) = Ptr{Cvoid}(Int(0xDEADBEEF))
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end

struct TestCompilerParams <: GPUCompiler.AbstractCompilerParams end
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any,TestCompilerParams}) = TestRuntime


function native_job(@nospecialize(func), @nospecialize(types); kernel::Bool=false, name=GPUCompiler.safe_name(repr(func)), kwargs...)
    source = GPUCompiler.FunctionSpec(func, Base.to_tuple_type(types), kernel, name)
    target = GPUCompiler.NativeCompilerTarget(always_inline=true)
    params = TestCompilerParams()
    GPUCompiler.CompilerJob(target, source, params), kwargs
end


"""
```julia
generate_shlib(f, tt, path::String, name::String, filenamebase::String="obj"; kwargs...)
```
Low level interface for compiling a shared object / dynamically loaded library
 (`.so` / `.dylib`) for function `f` given a tuple type `tt` characterizing
the types of the arguments for which the function will be compiled.

See also `StaticCompiler.generate_shlib_fptr`.

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

julia> path, name = StaticCompiler.generate_shlib(test, Tuple{Int64}, "./test")
("./test", "test")

shell> tree \$path
./test
|-- obj.o
`-- obj.so

0 directories, 2 files

julia> test(100_000)
5.256496109495593

julia> ccall(StaticCompiler.generate_shlib_fptr(path, name), Float64, (Int64,), 100_000)
5.256496109495593
```
"""
function generate_shlib(f, tt, path::String = tempname(), name = GPUCompiler.safe_name(repr(f)), filenamebase::String="obj"; kwargs...)
    mkpath(path)
    obj_path = joinpath(path, "$filenamebase.o")
    lib_path = joinpath(path, "$filenamebase.$(Libdl.dlext)")
    open(obj_path, "w") do io
        job, kwargs = native_job(f, tt; name, kwargs...)
        obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)

        write(io, obj)
        flush(io)

        # Pick a Clang
        cc = Sys.isapple() ? `cc` : clang()
        # Compile!
        run(`$cc -shared -o $lib_path $obj_path`)
    end
    path, name
end


function generate_shlib_fptr(f, tt, path::String=tempname(), name = GPUCompiler.safe_name(repr(f)), filenamebase::String="obj"; temp::Bool=true, kwargs...)
    generate_shlib(f, tt, path, name; kwargs...)
    lib_path = joinpath(abspath(path), "$filenamebase.$(Libdl.dlext)")
    ptr = Libdl.dlopen(lib_path, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, "julia_$name")
    @assert fptr != C_NULL
    if temp
        atexit(()->rm(path; recursive=true))
    end
    fptr
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
function generate_shlib_fptr(path::String, name, filenamebase::String="obj")
    lib_path = joinpath(abspath(path), "$filenamebase.$(Libdl.dlext)")
    ptr = Libdl.dlopen(lib_path, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, "julia_$name")
    @assert fptr != C_NULL
    fptr
end

"""
```julia
generate_executable(f, tt, path::String, name, filename=string(name); kwargs...)
```
Attempt to compile a standalone executable that runs `f`.

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

julia> path, name = StaticCompiler.generate_executable(test, Tuple{Int64}, "./scratch")
```
"""
function generate_executable(f, tt, path::String = tempname(), name = GPUCompiler.safe_name(repr(f)), filename::String=string(name); kwargs...)
    mkpath(path)
    obj_path = joinpath(path, "$filename.o")
    exec_path = joinpath(path, filename)
    open(obj_path, "w") do io
        job, kwargs = native_job(f, tt; name, kwargs...)
        obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)
        entry = "_julia_$name"

        write(io, obj)
        flush(io)

        # Pick a compiler
        cc = Sys.isapple() ? `cc` : `gcc`
        # Compile!
        run(`$cc -e $entry -o $exec_path $obj_path`)
    end
    path, name
end

function native_code_llvm(@nospecialize(func), @nospecialize(types); kwargs...)
    job, kwargs = native_job(func, types; kwargs...)
    GPUCompiler.code_llvm(stdout, job; kwargs...)
end

function native_code_typed(@nospecialize(func), @nospecialize(types); kwargs...)
    job, kwargs = native_job(func, types; kwargs...)
    GPUCompiler.code_typed(job; kwargs...)
end

# Return an LLVM module
function native_llvm_module(f, tt, name = GPUCompiler.safe_name(repr(f)); kwargs...)
    job, kwargs = native_job(f, tt; name, kwargs...)
    m, _ = GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false)
    return m
end

end # module
