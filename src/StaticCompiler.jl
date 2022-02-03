module StaticCompiler

using GPUCompiler: GPUCompiler
using LLVM: LLVM
using Libdl: Libdl
using Base: RefValue
using Serialization: serialize, deserialize
using Clang_jll: clang

export compile, load_function
export native_code_llvm, native_code_typed, native_llvm_module

"""
    compile(f, types, path::String = tempname()) --> (compiled_f, path)

   !!! Warning: this will fail on programs that heap allocate any memory, or have dynamic dispatch !!!

Statically compile the method of a function `f` specialized to arguments of the type given by `types`. 

This will create a directory at the specified path with a shared object file (i.e. a `.so` or `.dylib`), 
and will save a `LazyStaticCompiledFunction` object in the same directory with the extension `.cjl`. This 
`LazyStaticCompiledFunction` can be deserialized with `load_function(path)`. Once it is instantiated in 
a julia session, it will be of type `StaticCompiledFunction` and may be called with arguments of type 
`types` as if it were a function with a single method (the method determined by `types`).

`compile` will return an already instantiated `StaticCompiledFunction` object and `obj_path` which is the 
location of the directory containing the compilation artifacts.

Example:

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
julia> using StaticCompiler

julia> fib
ERROR: UndefVarError: fib not defined

julia> fib_compiled = load_function("fib.cjl")
fib(::Int64) :: Int64

julia> fib_compiled(10)
55
```
Tada!
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
    (; f = instantiate(lf), path)
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

function generate_shlib(f, tt, path::String = tempname(), name = GPUCompiler.safe_name(repr(f)); kwargs...)
    mkpath(path)
    obj_path = joinpath(path, "obj")
    lib_path = joinpath(path, "obj.$(Libdl.dlext)")
    open(obj_path, "w") do io
        job, kwargs = native_job(f, tt; name, kwargs...)
        obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)
        
        write(io, obj)
        flush(io)
        try
            clang() do exe
                run(pipeline(`$exe -shared -o $lib_path $obj_path`, stdout=devnull)) #get rid of devnull for debugging
            end
        catch e;
            # if Clang_jll fails, check if gcc is available
            run(`gcc -shared -o $lib_path $obj_path`)
        end
    end
    path, name
end

function generate_shlib_fptr(f, tt, path::String=tempname(), name = GPUCompiler.safe_name(repr(f)); temp::Bool=true, kwargs...)
    generate_shlib(f, tt, path, name; kwargs...)
    lib_path = joinpath(abspath(path), "obj.$(Libdl.dlext)")
    ptr = Libdl.dlopen("$(abspath(path)).$(Libdl.dlext)", Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, "julia_$name")
    @assert fptr != C_NULL
    if temp
        atexit(()->rm(path; recursive=true))
    end
    fptr
end

function generate_shlib_fptr(path::String, name)
    lib_path = joinpath(abspath(path), "obj.$(Libdl.dlext)")
    ptr = Libdl.dlopen(lib_path, Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, "julia_$name")
    @assert fptr != C_NULL
    fptr
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
