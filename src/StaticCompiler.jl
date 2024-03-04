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
using Core: MethodTable
using Base:BinaryPlatforms.Platform, BinaryPlatforms.HostPlatform, BinaryPlatforms.arch, BinaryPlatforms.os_str, BinaryPlatforms.libc_str
using Base:BinaryPlatforms.platform_dlext
export load_function, compile_shlib, compile_executable
export static_code_llvm, static_code_typed, static_llvm_module, static_code_native
export @device_override, @print_and_throw
export StaticTarget

include("interpreter.jl")
include("target.jl")
include("pointer_warning.jl")
include("quirks.jl")

fix_name(f::Function) = fix_name(string(nameof(f)))
fix_name(s) = String(GPUCompiler.safe_name(s))


"""
```julia
compile_executable(f::Function, types::Tuple, path::String, [name::String=string(nameof(f))];
    filename::String=name,
    cflags=``, # Specify libraries you would like to link against, and other compiler options here
    also_expose=[],
    target::StaticTarget=StaticTarget(),
    method_table=StaticCompiler.method_table,
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
function compile_executable(f::Function, types=(), path::String=pwd(), name=fix_name(f);
                            also_expose=Tuple{Function, Tuple{DataType}}[], target::StaticTarget=StaticTarget(),
                            kwargs...)
    compile_executable(vcat([(f, types)], also_expose), path, name; target, kwargs...)
end

function compile_executable(funcs::Union{Array,Tuple}, path::String=pwd(), name=fix_name(first(first(funcs)));
        filename = name,
        demangle = true,
        cflags = ``,
        target::StaticTarget=StaticTarget(),
        kwargs...
    )

    (f, types) = funcs[1]
    tt = Base.to_tuple_type(types)
    isexecutableargtype = tt == Tuple{} || tt == Tuple{Int, Ptr{Ptr{UInt8}}}
    isexecutableargtype || @warn "input type signature $types should be either `()` or `(Int, Ptr{Ptr{UInt8}})` for standard executables"

    rt = last(only(static_code_typed(f, tt; target, kwargs...)))
    isconcretetype(rt) || error("`$f$types` did not infer to a concrete type. Got `$rt`")
    nativetype = isprimitivetype(rt) || isa(rt, Ptr)
    nativetype || @warn "Return type `$rt` of `$f$types` does not appear to be a native type. Consider returning only a single value of a native machine type (i.e., a single float, int/uint, bool, or pointer). \n\nIgnoring this warning may result in Undefined Behavior!"

    generate_executable(funcs, path, name, filename; demangle, cflags, target, kwargs...)
    joinpath(abspath(path), filename)
end

"""
```julia
compile_shlib(f::Function, types::Tuple, [path::String=pwd()], [name::String=string(nameof(f))];
    filename::String=name,
    cflags=``,
    method_table=StaticCompiler.method_table,
    target::StaticTarget=StaticTarget(),
    kwargs...)

compile_shlib(funcs::Array, [path::String=pwd()];
    filename="libfoo",
    demangle=true,
    cflags=``,
    method_table=StaticCompiler.method_table,
    target::StaticTarget=StaticTarget(),
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
        filename=name,
        target::StaticTarget=StaticTarget(),
        kwargs...
    )
    compile_shlib(((f, types),), path; filename, target, kwargs...)
end
# As above, but taking an array of functions and returning a single shlib
function compile_shlib(funcs::Union{Array,Tuple}, path::String=pwd();
        filename = "libfoo",
        demangle = true,
        cflags = ``,
        target::StaticTarget=StaticTarget(),
        kwargs...
    )
    for func in funcs
        f, types = func
        tt = Base.to_tuple_type(types)
        isconcretetype(tt) || error("input type signature `$types` is not concrete")

        rt = last(only(static_code_typed(f, tt; target, kwargs...)))
        isconcretetype(rt) || error("`$f$types` did not infer to a concrete type. Got `$rt`")
        nativetype = isprimitivetype(rt) || isa(rt, Ptr)
        nativetype || @warn "Return type `$rt` of `$f$types` does not appear to be a native type. Consider returning only a single value of a native machine type (i.e., a single float, int/uint, bool, or pointer). \n\nIgnoring this warning may result in Undefined Behavior!"
    end

    generate_shlib(funcs, path, filename; demangle, cflags, target, kwargs...)

    joinpath(abspath(path), filename * "." * Libdl.dlext)
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
                             target::StaticTarget=StaticTarget(),
                             llvm_to_clang = Sys.iswindows(),
                             kwargs...
                             )
    exec_path = joinpath(path, filename)
    _, obj_or_ir_path = generate_obj(funcs, path, filename; emit_llvm_only=llvm_to_clang, demangle, target, kwargs...)
    # Pick a compiler
    if !isnothing(target.compiler)
        cc = `$(target.compiler)`
    else
        cc = Sys.isapple() ? `cc` : clang()
    end

    # Compile!
    if Sys.isapple() && !llvm_to_clang
        # Apple no longer uses _start, so we can just specify a custom entry
        entry = demangle ? "_$name" : "_julia_$name"
        run(`$cc -e $entry $cflags $obj_or_ir_path -o $exec_path`)
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
        if llvm_to_clang # (required on Windows)
            # Use clang (llc) to generate an executable from the LLVM IR
            if Sys.iswindows()
              run(`cmd \c clang -Wno-override-module $wrapper_path $obj_or_ir_path -o $exec_path`)      
            else
              run(`$(clang()) -Wno-override-module $wrapper_path $obj_or_ir_path -o $exec_path`)      
            end
        else
            run(`$cc $wrapper_path $cflags $obj_or_ir_path -o $exec_path`)
        end
            
        # Clean up
        rm(wrapper_path)
    end
    path, name
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
        demangle = true,
        cflags = ``,
        target::StaticTarget=StaticTarget(),
        kwargs...
    )
    if !isnothing(target.platform)
        lib_path = joinpath(path, "$filename.$(platform_dlext(target.platform))")
    else
        lib_path = joinpath(path, "$filename.$(Libdl.dlext)")
    end

    _, obj_path = generate_obj(funcs, path, filename; target, demangle, kwargs...)
    # Pick a Clang
    if !isnothing(target.compiler)
        cc = `$(target.compiler)`
    else
        cc = Sys.isapple() ? `cc` : clang()
    end
    # Compile!
    run(`$cc -shared $cflags $obj_path -o $lib_path `)

    path, name
end

function static_code_llvm(@nospecialize(func), @nospecialize(types); target::StaticTarget=StaticTarget(), kwargs...)
    job, kwargs = static_job(func, types; target, kwargs...)
    GPUCompiler.code_llvm(stdout, job; libraries=false, kwargs...)
end

function static_code_typed(@nospecialize(func), @nospecialize(types); target::StaticTarget=StaticTarget(), kwargs...)
    job, kwargs = static_job(func, types; target, kwargs...)
    GPUCompiler.code_typed(job; kwargs...)
end

function static_code_native(@nospecialize(f), @nospecialize(tt), fname=fix_name(f); target::StaticTarget=StaticTarget(), kwargs...)
    job, kwargs = static_job(f, tt; fname, target, kwargs...)
    GPUCompiler.code_native(stdout, job; libraries=false, kwargs...)
end

# Return an LLVM module
function static_llvm_module(f, tt, name=fix_name(f); demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
    if !demangle
        name = "julia_"*name
    end
    job, kwargs = static_job(f, tt; name, target, kwargs...)
    m = GPUCompiler.JuliaContext() do context
        m, _ = GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false, libraries=false)
        locate_pointers_and_runtime_calls(m)
        m
    end
    return m
end

#Return an LLVM module for multiple functions
function static_llvm_module(funcs::Union{Array,Tuple}; demangle=true, target::StaticTarget=StaticTarget(), kwargs...)
    f,tt = funcs[1]
    mod = GPUCompiler.JuliaContext() do context
        name_f = fix_name(f)
        if !demangle
            name_f = "julia_"*name_f
        end
        job, kwargs = static_job(f, tt; name = name_f, target, kwargs...)
        mod,_ = GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false, libraries=false)
        if length(funcs) > 1
            for func in funcs[2:end]
                f,tt = func
                name_f = fix_name(f)
                if !demangle
                    name_f = "julia_"*name_f
                end
                job, kwargs = static_job(f, tt; name = name_f, target, kwargs...)
                tmod,_ = GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false, libraries=false)
                link!(mod,tmod)
            end
        end
        locate_pointers_and_runtime_calls(mod)
        mod
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
generate_obj(f, tt, path::String = tempname(), filenamebase::String="obj";
             target::StaticTarget=StaticTarget(),
             demangle = true,
             strip_llvm = false,
             strip_asm  = true,
             opt_level = 3,
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
```julia
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
             demangle =false,
             strip_llvm = false,
             strip_asm  = true,
             opt_level=3,
             kwargs...)
```
Low level interface for compiling object code (`.o`) for an array of Tuples
(f, tt) where each function `f` and tuple type `tt` determine the set of methods
which will be compiled.

`target` can be used to change the output target. This is useful for compiling to WebAssembly and embedded targets.
This is a struct of the type StaticTarget()
The defaults compile to the native target.
"""
function generate_obj(funcs::Union{Array,Tuple}, path::String = tempname(), filenamebase::String="obj";
                        demangle = true,
                        strip_llvm = false,
                        strip_asm = true,
                        opt_level = 3,
                        target::StaticTarget=StaticTarget(),
                        emit_llvm_only = Sys.iswindows(),
                        kwargs...)
    f, tt = funcs[1]
    mkpath(path)
    mod = static_llvm_module(funcs; demangle, kwargs...)

    if emit_llvm_only # (Required on Windows)
      ir_path = joinpath(path, "$filenamebase.ll")
      open(ir_path, "w") do io
        write(io, string(mod))
      end
      return path, ir_path
    else
      obj_path = joinpath(path, "$filenamebase.o")
      obj = GPUCompiler.JuliaContext() do ctx
          fakejob, _ = static_job(f, tt; target, kwargs...)
          obj, _ = GPUCompiler.emit_asm(fakejob, mod; strip=strip_asm, validate=false, format=LLVM.API.LLVMObjectFile)
          obj
      end
      open(obj_path, "w") do io
          write(io, obj)
      end
      return path, obj_path
    end
end

end # module
