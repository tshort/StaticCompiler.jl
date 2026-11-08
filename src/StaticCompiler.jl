module StaticCompiler
using InteractiveUtils
using GPUCompiler: GPUCompiler
using LLVM, LLVM.IR, LLVM.Passes
using Libdl: Libdl, dlsym, dlopen
using Base: RefValue
using Serialization: serialize, deserialize
using Clang_jll: Clang_jll
using LLD_jll: lld
using StaticTools
using StaticTools: @symbolcall, @c_str, println
using Core: MethodTable
using Base:BinaryPlatforms.Platform, BinaryPlatforms.HostPlatform, BinaryPlatforms.arch, BinaryPlatforms.os_str, BinaryPlatforms.libc_str
using Base:BinaryPlatforms.platform_dlext
export load_function, compile_shlib, compile_executable
export static_code_llvm, static_code_typed, static_llvm_module, static_code_native
export @device_override, @print_and_throw
export StaticTarget

include("quirks.jl")
include("target.jl")
include("pointer_warning.jl")
include("dllexport.jl")

fix_name(f::Function) = fix_name(string(nameof(f)))
fix_name(s) = String(GPUCompiler.safe_name(s))

# Generally prefer Clang_jll clang (which should probably be at least as new as Julia's LLVM)
# and fall back to the system one on platforms where Clang_jll is not available or not expected to work
function clang()
    Clang_jll.is_available() || return `clang` # Fall back to system clang if Clang_jll is not available
    cmd = Clang_jll.clang()
    # Clang_jll may not know where to find the macOS SDK (e.g. for `-lSystem`)
    if Sys.isapple() && !haskey(ENV, "SDKROOT") 
        isnothing(Sys.which("xcrun")) && return `clang` # Fall back to system clang if we can't figure out the SDK path
        cmd = addenv(cmd, "SDKROOT" => readchomp(`xcrun --show-sdk-path`))
    end
    return cmd
end

# shared library extension of the target (that of the host, unless cross-compiling)
dlext(target::StaticTarget) = isnothing(target.platform) ? Libdl.dlext : platform_dlext(target.platform)


# Check that `f(types...)` is compilable to a native entry point, returning the tuple type of `types`
function check_signature(f, types; target::StaticTarget=StaticTarget(), kwargs...)
    tt = Base.to_tuple_type(types)
    isconcretetype(tt) || error("input type signature `$types` is not concrete")

    rt = last(only(static_code_typed(f, tt; target, kwargs...)))
    isconcretetype(rt) || error("`$f$types` did not infer to a concrete type. Got `$rt`")
    nativetype = isprimitivetype(rt) || isa(rt, Ptr)
    nativetype || @warn "Return type `$rt` of `$f$types` does not appear to be a native type. Consider returning only a single value of a native machine type (i.e., a single float, int/uint, bool, or pointer). \n\nIgnoring this warning may result in Undefined Behavior!"
    return tt
end

"""
```julia
compile_executable(f::Function, types::Tuple, [path::String=pwd()], [name::String=string(nameof(f))];
    filename::String=name,
    also_expose = [],
    target::StaticTarget=StaticTarget(),
    cc = nothing,                           # Compiler, may specify to override defaults
    cflags = ``,                            # Specify libraries you would like to link against, and other compiler options here
    llvm_to_clang = Sys.iswindows(),
    method_table = StaticCompiler.method_table,
    llvm_postprocess = nothing,
    kwargs...
)
    
```
Attempt to compile a standalone executable that runs function `f` with a type signature given by the tuple of `types`.
If there are extra methods you would like to protect from name mangling in the produced binary for whatever reason,
you can provide them as a vector of tuples of functions and types, i.e. `[(f1, types1), (f2, types2), ...]`

The `llvm_postprocess` keyword, if given, allows users to specify a function that will be called on each `LLVM.Module` 
that is generated, before it is checked and compiled, and may modify it in place 
(for instance, to define the runtime functions that the code calls).

Other keywords will be forwarded to `static_job`. This may include `params`, which if given, 
is a `GPUCompiler.AbstractCompilerParams` object (default `StaticCompilerParams()`) which
is passed to `GPUCompiler.CompilerConfig`. 

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
function compile_executable(f::Function, types=(), path::String=pwd(), name=fix_name(f);
                            also_expose=Tuple{Function, Tuple{DataType}}[], 
                            kwargs...)
    compile_executable(vcat([(f, types)], also_expose), path, name; kwargs...)
end

function compile_executable(funcs::Union{Array,Tuple}, path::String=pwd(), name=fix_name(first(first(funcs)));
        filename::String = name,
        target::StaticTarget=StaticTarget(),
        demangle = true,
        cc = nothing,
        cflags = ``,
        llvm_to_clang = Sys.iswindows(),
        kwargs...
    )

    (f, types) = funcs[1]
    tt = check_signature(f, types; target, kwargs...)
    isexecutableargtype = tt == Tuple{} || tt == Tuple{Int, Ptr{Ptr{UInt8}}}
    isexecutableargtype || @warn "input type signature $types should be either `()` or `(Int, Ptr{Ptr{UInt8}})` for standard executables"

    generate_executable(funcs, path, name, filename; target, demangle, cc, cflags, llvm_to_clang, kwargs...)
    Sys.iswindows() && (filename *= ".exe")
    joinpath(abspath(path), filename)
end

"""
```julia
compile_shlib(f::Function, types::Tuple, [path::String=pwd()], [name::String=string(nameof(f))];
    filename::String=name,
    target::StaticTarget=StaticTarget(),
    demangle=true,
    cc = nothing,   # Compiler, may specify to override defaults
    cflags = ``,    # Specify libraries you would like to link against, and other compiler options here
    llvm_to_clang = Sys.iswindows(),
    method_table = StaticCompiler.method_table,
    kwargs...)

compile_shlib(funcs::Array, [path::String=pwd()];
    filename="libfoo",
    target::StaticTarget=StaticTarget(),
    cc = nothing,   # Compiler, may specify to override defaults
    cflags = ``,    # Specify libraries you would like to link against, and other compiler options here
    llvm_to_clang = Sys.iswindows(),
    method_table = StaticCompiler.method_table,
    kwargs...)
```
As `compile_executable`, but compiling to a standalone `.dylib`/`.so` shared library.

Arguments and returned values from `compile_shlib` must be native objects such as `Int`, `Float64`, or `Ptr`. They cannot be things like `Tuple{Int, Int}` because that is not natively sized. Such objects need to be passed by reference instead of by value.

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
function compile_shlib(f::Function, types=(), path::String=pwd(), name=fix_name(f);
        filename = name,
        kwargs...
    )
    compile_shlib(((f, types),), path; filename, kwargs...)
end
# As above, but taking an array of functions and returning a single shlib
function compile_shlib(funcs::Union{Array,Tuple}, path::String=pwd();
        filename = "libfoo",
        target::StaticTarget=StaticTarget(),
        demangle = true,
        cc = nothing,
        cflags = ``,
        llvm_to_clang = Sys.iswindows(),
        kwargs...
    )
    for (f, types) in funcs
        check_signature(f, types; target, kwargs...)
    end

    generate_shlib(funcs, path, filename; target, demangle, cc, cflags, llvm_to_clang, kwargs...)

    joinpath(abspath(path), filename * "." * dlext(target))
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

    generate_shlib(f, tt, path, name, filename; kwargs...)
    fptr = generate_shlib_fptr(path, name, filename)
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
                             target::StaticTarget=StaticTarget(),
                             demangle = true,
                             cc = nothing,
                             cflags = ``,
                             llvm_to_clang::Bool = Sys.iswindows(),
                             kwargs...
                            )
    # Choice of compiler
    isnothing(cc) && (cc = isnothing(target.compiler) ? clang() : `$(target.compiler)`)

    # Prepare objects or (if llvm_to_clang is set) IR
    exec_path = joinpath(path, filename)
    _, obj_or_ir_path = generate_obj(funcs, path, filename; demangle, target, emit_llvm_only=llvm_to_clang, kwargs...)

    # Update paths and flags given options
    fn = demangle ? "$name" : "julia_$name"
    Sys.iswindows() && (exec_path *= ".exe")
    llvm_to_clang && (cflags = `-Wno-override-module $cflags`)

    # Compile!
    if Sys.isapple() && !llvm_to_clang
        # Apple no longer uses _start, so we can just specify a custom entry
        run(`$cc -e _$fn $cflags $obj_or_ir_path -o $exec_path`)
    else
        # Write a minimal wrapper to avoid having to specify a custom entry
        wrapper_path = joinpath(path, "wrapper$(rand(UInt)).c")
        f = open(wrapper_path, "w")
        print(f, """int $fn(int argc, char** argv);
        void* __stack_chk_guard = (void*) $(rand(UInt) >> 1);

        int main(int argc, char** argv)
        {
            return $fn(argc, argv);
        }""")
        close(f)

        # Depending on whether llvm_to_clang is set, 
        # this may either be compiling from LLVM IR or just linking object files
        run(`$cc $wrapper_path $cflags $obj_or_ir_path -o $exec_path`)

        # Clean up
        rm(wrapper_path)
    end
    return path, name
end


"""
```julia
generate_shlib(f::Function, tt, [path::String], [name], [filename]; kwargs...)
generate_shlib(funcs::Array, [path::String], [filename::String]; demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
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
function generate_shlib(f::Function, tt, path::String=tempname(), name=fix_name(f), filename=name; target=StaticTarget(), kwargs...)
    generate_shlib(((f, tt),), path, filename; target, kwargs...)
end
# As above, but taking an array of functions and returning a single shlib
function generate_shlib(funcs::Union{Array,Tuple}, path::String=tempname(), filename::String="libfoo";
        target::StaticTarget=StaticTarget(),
        demangle = true,
        cc = nothing,
        cflags = ``,
        llvm_to_clang::Bool = Sys.iswindows(),
        kwargs...
    )
    # Choice of compiler
    isnothing(cc) && (cc = isnothing(target.compiler) ? clang() : `$(target.compiler)`)

    # Prepare objects or (if llvm_to_clang is set) IR
    lib_path = joinpath(path, "$filename.$(dlext(target))")
    _, obj_or_ir_path = generate_obj(funcs, path, filename; demangle, target, emit_llvm_only=llvm_to_clang,
                                     dllexport=Sys.iswindows(), kwargs...)
                                     
    # Compile!
    llvm_to_clang && (cflags = `-Wno-override-module $cflags`)
    run(`$cc -shared $cflags $obj_or_ir_path -o $lib_path `)

    return path, filename
end

function static_code_llvm(@nospecialize(func), @nospecialize(types); target::StaticTarget=StaticTarget(), llvm_postprocess=nothing, kwargs...)
    job, kwargs = static_job(func, types; target, kwargs...)
    GPUCompiler.code_llvm(stdout, job; libraries=false, kwargs...)
end

function static_code_typed(@nospecialize(func), @nospecialize(types); target::StaticTarget=StaticTarget(), llvm_postprocess=nothing, kwargs...)
    job, kwargs = static_job(func, types; target, kwargs...)
    GPUCompiler.code_typed(job; kwargs...)
end

function static_code_native(@nospecialize(f), @nospecialize(tt), fname=fix_name(f); target::StaticTarget=StaticTarget(), llvm_postprocess=nothing, kwargs...)
    job, kwargs = static_job(f, tt; name=fname, target, kwargs...)
    GPUCompiler.code_native(stdout, job; libraries=false, kwargs...)
end

const CONTEXT_DOC = """
The module belongs to the active thread-safe context, so call this function in a
`GPUCompiler.JuliaContext() do ctx ... end` block, and dispose of the module (or hand it to an
operation that consumes it, like `LLVM.link!(dst, mod)`) before the block ends. Without an
active thread-safe context, a new one is created for the module, which is never disposed of
(i.e., every such call leaks a context)."""

"""
```julia
static_llvm_module(f, tt, name=fix_name(f); demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
```
Compile the method of `f` for the argument types `tt` to an `LLVM.Module`, which the caller
owns.

$CONTEXT_DOC
"""
function static_llvm_module(f, tt, name=fix_name(f); demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
    with_module_context() do
        compile_llvm_module(f, tt, name; demangle, target, kwargs...)
    end
end

"""
```julia
static_llvm_module(funcs::Union{Array,Tuple}; demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
```
Compile the methods of an array of tuples `(f, tt)` of functions and argument types to a
single `LLVM.Module`, which the caller owns.

$CONTEXT_DOC
"""
function static_llvm_module(funcs::Union{Array,Tuple}; demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
    with_module_context() do
        compile_llvm_module(funcs; demangle, target, kwargs...)
    end
end

# call `f` with the plain context of the active thread-safe context active, or of a new
# thread-safe context that is never disposed of, so that the modules `f` returns stay valid
function with_module_context(f)
    ts_ctx = LLVM.ts_context(; throw_error=false)
    ts_ctx === nothing || return context!(f, LLVM.context(ts_ctx))
    ts_ctx = GPUCompiler.JuliaContext() # activates it
    ret = try
        context!(f, LLVM.context(ts_ctx))
    catch
        # nothing was returned that could use the context
        dispose(ts_ctx)
        rethrow()
    end
    LLVM.deactivate(ts_ctx)
    return ret
end

# compile to a module in the active (Julia) context, which must outlive the module
function compile_llvm_module(f, tt, name=fix_name(f); 
        target::StaticTarget=StaticTarget(), 
        demangle=true, 
        strip=true,
        only_entry=false, 
        validate=false, 
        libraries=false, 
        llvm_postprocess=nothing, 
        kwargs...,
    )
    if !demangle
        name = "julia_"*name
    end
    job, kwargs = static_job(f, tt; name, target, strip, only_entry, validate, libraries, kwargs...)
    m, _ = GPUCompiler.compile(:llvm, job; kwargs...)
    try
        isnothing(llvm_postprocess) || llvm_postprocess(m)
        locate_pointers_and_runtime_calls(m)
    catch
        dispose(m)
        rethrow()
    end
    return m
end

function compile_llvm_module(funcs::Union{Array,Tuple}; kwargs...)
    (f, tt), rest... = funcs
    mod = compile_llvm_module(f, tt; kwargs...)
    try
        for (f, tt) in rest
            # consumes the module, also when linking fails
            link!(mod, compile_llvm_module(f, tt; kwargs...))
        end
        run!(MergeFunctionsPass(), mod)
    catch
        dispose(mod)
        rethrow()
    end
    return mod
end

"""
```julia
generate_obj(f, tt, path::String = tempname(), filenamebase::String="obj";
             target::StaticTarget=StaticTarget(),
             demangle = true,
             kwargs...)
```
Low level interface for compiling object code (`.o`) for for function `f` given
a tuple type `tt` characterizing the types of the arguments for which the
function will be compiled.

`target` can be used to change the output target. This is useful for compiling to WebAssembly and embedded targets.
This is a struct of the type StaticTarget()
The defaults compile to the native target.

If `demangle` is set to `false`, compiled function names are prepended with "julia_".

### Examples
```
julia> fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)
fib (generic function with 1 method)

julia> path, name, table = StaticCompiler.generate_obj(fib, Tuple{Int64}, "./test")
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
generate_obj(funcs::Union{Array,Tuple}, path::String = tempname(), filenamebase::String="obj";
             target::StaticTarget=StaticTarget(),
             demangle = false,
             emit_llvm_only = false,
             dllexport = false,
             kwargs...)
```
Low level interface for compiling object code (`.o`) for an array of Tuples
(f, tt) where each function `f` and tuple type `tt` determine the set of methods
which will be compiled.

`target` can be used to change the output target. This is useful for compiling to WebAssembly and embedded targets.
This is a struct of the type StaticTarget()
The defaults compile to the native target.

If `dllexport` is set, the functions are exported from a Windows DLL.
"""
function generate_obj(funcs::Union{Array,Tuple}, path::String = tempname(), filenamebase::String="obj";
                        target::StaticTarget=StaticTarget(),
                        demangle = true,
                        emit_llvm_only = false,
                        dllexport = false,
                        llvm_postprocess = nothing,
                        kwargs...)
    f, tt = funcs[1]
    mkpath(path)
    # compile and generate code in one context, which the module can't outlive
    GPUCompiler.JuliaContext() do context
      @dispose mod=compile_llvm_module(funcs; demangle, target, llvm_postprocess, kwargs...) begin
        dllexport && add_dllexport!(mod, funcs; demangle)
        if emit_llvm_only # (Required on Windows)
          ir_path = joinpath(path, "$filenamebase.ll")
          open(ir_path, "w") do io
            write(io, string(mod))
          end
          return path, ir_path
        else
          obj_path = joinpath(path, "$filenamebase.o")
          fakejob, _ = static_job(f, tt; target, kwargs...)
          obj, _ = GPUCompiler.emit_asm(fakejob, mod, LLVM.CodeGenFileType.Object)
          open(obj_path, "w") do io
              write(io, obj)
          end
          return path, obj_path
        end
      end
    end
end

end # module
