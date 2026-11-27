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
using Base: BinaryPlatforms.Platform, BinaryPlatforms.HostPlatform
using Base: BinaryPlatforms.platform_dlext, BinaryPlatforms.arch, BinaryPlatforms.os, BinaryPlatforms.os_str, BinaryPlatforms.libc_str
export load_function, compile_shlib, compile_executable
export static_code_llvm, static_code_typed, static_llvm_module, static_code_native
export @device_override, @print_and_throw
export StaticTarget, Driver, LLD

abstract type Toolchain end # (the field of `StaticTarget`; see toolchain.jl)

include("quirks.jl")
include("target.jl")
include("toolchain.jl")
include("builtins.jl")
include("llvm.jl")

fix_name(f::Function) = fix_name(string(nameof(f)))
fix_name(s) = String(GPUCompiler.safe_name(s))

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
    llvm_to_clang = needs_ir(target),       # default: whether the target needs it (Windows, or cross-target absent from Julia's LLVM)
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
        llvm_to_clang = needs_ir(target),
        kwargs...
    )

    (f, types) = funcs[1]
    tt = check_signature(f, types; target, kwargs...)
    isexecutableargtype = tt == Tuple{} || tt == Tuple{Int, Ptr{Ptr{UInt8}}}
    isexecutableargtype || @warn "input type signature $types should be either `()` or `(Int, Ptr{Ptr{UInt8}})` for standard executables"

    generate_executable(funcs, path, name, filename; target, demangle, cc, cflags, llvm_to_clang, kwargs...)
    joinpath(abspath(path), output_name(isnothing(cc) ? toolchain(target) : Driver(cc), target, filename))
end

"""
```julia
compile_shlib(f::Function, types::Tuple, [path::String=pwd()], [name::String=string(nameof(f))];
    filename::String=name,
    target::StaticTarget=StaticTarget(),
    demangle=true,
    cc = nothing,   # Compiler, may specify to override defaults
    cflags = ``,    # Specify libraries you would like to link against, and other compiler options here
    llvm_to_clang = needs_ir(target),     # default: whether the target needs it (Windows, or cross-target absent from Julia's LLVM)
    method_table = StaticCompiler.method_table,
    kwargs...)

compile_shlib(funcs::Array, [path::String=pwd()];
    filename="libfoo",
    target::StaticTarget=StaticTarget(),
    cc = nothing,   # Compiler, may specify to override defaults
    cflags = ``,    # Specify libraries you would like to link against, and other compiler options here
    llvm_to_clang = needs_ir(target),     # default: whether the target needs it (Windows, or cross-target absent from Julia's LLVM)
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
        llvm_to_clang = needs_ir(target),
        kwargs...
    )
    for (f, types) in funcs
        check_signature(f, types; target, kwargs...)
    end

    generate_shlib(funcs, path, filename; target, demangle, cc, cflags, llvm_to_clang, kwargs...)

    joinpath(abspath(path), output_name(isnothing(cc) ? toolchain(target) : Driver(cc), target, filename; kind = :shared))
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
                             llvm_to_clang::Bool = needs_ir(target),
                             kwargs...
                            )
    # How it is linked: what `cc` says, or the toolchain of the target
    tc = isnothing(cc) ? toolchain(target) : Driver(cc)

    # Prepare objects or (if llvm_to_clang is set) IR. A linker that is not a compiler driver is given an object that has a `main`
    fn = demangle ? "$name" : "julia_$name"
    main_wrapper = tc isa Driver ? nothing : fn
    _, obj_or_ir_path = generate_obj(funcs, path, filename; demangle, target, emit_llvm_only=llvm_to_clang, main_wrapper, kwargs...)

    # Link!
    exec_path = joinpath(path, output_name(tc, target, filename))
    link(tc, target, [obj_or_ir_path], exec_path; kind = :executable, entry = fn, cflags)
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
        llvm_to_clang::Bool = needs_ir(target),
        kwargs...
    )
    # How it is linked: what `cc` says, or the toolchain of the target
    tc = isnothing(cc) ? toolchain(target) : Driver(cc)

    # Prepare objects or (if llvm_to_clang is set) IR
    lib_path = joinpath(path, output_name(tc, target, filename; kind = :shared))
    _, obj_or_ir_path = generate_obj(funcs, path, filename; demangle, target, emit_llvm_only=llvm_to_clang,
                                     dllexport=iswindows(target), kwargs...)

    # Link!
    link(tc, target, [obj_or_ir_path], lib_path; kind = :shared, cflags)

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
        retarget!(m, target)
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

If `main_wrapper` is the name of one of the functions, the object will be given a `main` that calls it, 
possibly preceeded by any code added by `main_prologue(builder, mod)`.

`llvm_finalize(mod)`, if given, is called on the whole module when complete.
"""
function generate_obj(funcs::Union{Array,Tuple}, path::String = tempname(), filenamebase::String="obj";
                        target::StaticTarget=StaticTarget(),
                        demangle = true,
                        emit_llvm_only = false,
                        dllexport = false,
                        main_wrapper = nothing,
                        main_prologue = nothing,
                        llvm_postprocess = nothing,
                        llvm_finalize = nothing,
                        kwargs...)
    f, tt = funcs[1]
    mkpath(path)
    if emit_llvm_only # (Required on Windows)
        ir_path = joinpath(path, "$filenamebase.ll")
        write(ir_path, generate_ir(funcs; demangle, target, dllexport, main_wrapper, main_prologue, llvm_postprocess, llvm_finalize, kwargs...))
        return path, ir_path
    end
    can_emit_object(target) || throw(ArgumentError("no object can be made for $(target_triple(target)) here: Julia's LLVM has no code generator for it, and no `llc` is given (`StaticTarget(...; llc)`). Use `emit_llvm_only = true` (or `generate_ir`) and give the IR to a compiler that has one"))
    # compile and generate code in one context, which the module can't outlive
    GPUCompiler.JuliaContext() do context
      @dispose mod=compile_llvm_module(funcs; demangle, target, llvm_postprocess, kwargs...) begin
        dllexport && add_dllexport!(mod, funcs; demangle)
        isnothing(main_wrapper) || add_main_wrapper!(mod, main_wrapper, target; prologue = main_prologue)
        uses_builtins(target.toolchain) && add_builtins!(mod, target_triple(target))
        isnothing(llvm_finalize) || llvm_finalize(mod)
        obj_path = joinpath(path, "$filenamebase.o")
        if isnothing(target.retarget)
            fakejob, _ = static_job(f, tt; target, kwargs...)
            obj, _ = GPUCompiler.emit_asm(fakejob, mod, LLVM.CodeGenFileType.Object)
        else
            obj = emit_object(mod, target) # (by the code generator of the target, which is not the host's)
        end
        open(obj_path, "w") do io
            write(io, obj)
        end
        return path, obj_path
      end
    end
end

"""
```julia
generate_ir(funcs::Union{Array,Tuple}; target::StaticTarget=StaticTarget(), demangle=true, dllexport=false, llvm_postprocess=nothing, kwargs...) -> String
generate_ir(f, tt; kwargs...) -> String
```
The LLVM IR (as text) of the functions that `generate_obj` would compile to an object file, for tools that take IR instead (a downstream package that makes the object or
the executable of a target by itself, for example): nothing is written to the file system, and the module (which cannot outlive its context) is not returned.
"""
function generate_ir(funcs::Union{Array,Tuple}; target::StaticTarget=StaticTarget(), demangle = true, dllexport = false, main_wrapper = nothing, main_prologue = nothing, llvm_postprocess = nothing, llvm_finalize = nothing, kwargs...)
    GPUCompiler.JuliaContext() do context
      @dispose mod=compile_llvm_module(funcs; demangle, target, llvm_postprocess, kwargs...) begin
        dllexport && add_dllexport!(mod, funcs; demangle)
        isnothing(main_wrapper) || add_main_wrapper!(mod, main_wrapper, target; prologue = main_prologue)
        uses_builtins(target.toolchain) && add_builtins!(mod, target_triple(target))
        isnothing(llvm_finalize) || llvm_finalize(mod)
        return string(mod)
      end
    end
end
generate_ir(f, tt; kwargs...) = generate_ir(((f, tt),); kwargs...)


"""
    link(toolchain, target, inputs::Vector{String}, output::String; kind = :executable, entry = nothing, cflags = ``) -> path

Link the `inputs` (object files, or LLVM IR files if the toolchain is a `Driver`) 
into an executable (`kind = :executable`) or shared library (`kind = :shared`), and return its path. 

If given, `entry` is the name of the function that an executable runs (`int f(int argc, char **argv)`); 
with `entry = nothing` the inputs define `main` already, and are linked as they are.
"""
function link(tc::Driver, target::StaticTarget, inputs::Vector{String}, output::String; kind::Symbol = :executable, entry = nothing, cflags = ``)
    # Link using a C compiler driver
    cc = tc.cc
    # (IR, which `clang` compiles itself: it is told what the target is, as it replaces the triple of the IR by the host's)
    ir = any(endswith(".ll"), inputs)
    ir && (cflags = `-Wno-override-module $(clang_target_flags(target)) $cflags`)
    if kind === :shared
        run(`$cc -shared $inputs $cflags -o $output`)
    elseif isnothing(entry)
        run(`$cc $inputs $cflags -o $output`) # (`main` is in the inputs)
    elseif isapple(target) && !ir
        # Apple no longer uses _start, so we can just specify a custom entry
        run(`$cc -e _$entry $inputs $cflags -o $output`)
    else
        # Write a minimal wrapper to avoid having to specify a custom entry
        wrapper_path = joinpath(dirname(output), "wrapper$(rand(UInt)).c")
        write(wrapper_path, """int $entry(int argc, char** argv);
        void* __stack_chk_guard = (void*) $(rand(UInt) >> 1);

        int main(int argc, char** argv)
        {
            return $entry(argc, argv);
        }""")
        try
            # (compiling from LLVM IR, or just linking object files, depending on the inputs)
            run(`$cc $wrapper_path $inputs $cflags -o $output`)
        finally
            rm(wrapper_path; force = true)
        end
    end
    return output
end
function link(tc::LLD, target::StaticTarget, inputs::Vector{String}, output::String; kind::Symbol = :executable, entry = nothing, cflags = ``)
    # Link using an LLD driver
    any(endswith(".ll"), inputs) && throw(ArgumentError("`LLD` links objects, not LLVM IR: make the objects (the target has to be one that Julia's LLVM has the code generator for)"))
    if tc.flavor === :gnu
        sysroot = tc.sysroot
        isnothing(sysroot) && throw(ArgumentError("linking for $(target_triple(target)) needs the C library of the target: give `sysroot = ...` to `LLD(:gnu; ...)`"))
        dir = crt_directory(sysroot)
        libs = ["-l$l" for l in tc.libs]
        if kind === :shared
            run(`$(lld()) -flavor gnu -shared -o $output $inputs -L$dir $libs $(tc.flags) $cflags`)
        else
            loader = something(tc.dynamic_linker, default_dynamic_linker(target))
            run(`$(lld()) -flavor gnu -o $output -dynamic-linker $loader $(joinpath(dir, "crt1.o")) $(joinpath(dir, "crti.o")) $inputs -L$dir $libs $(joinpath(dir, "crtn.o")) $(tc.flags) $cflags`)
        end
    else # :wasm
        kind === :shared && throw(ArgumentError("a shared library for WebAssembly is not supported"))
        bits = startswith(target_triple(target), "wasm64") ? "-mwasm64" : "-mwasm32"
        run(`$(lld()) -flavor wasm $bits --no-entry --export=main --export-memory --allow-undefined -o $output $inputs $(tc.flags) $cflags`)
    end
    return output
end

end # module
