module StaticCompiler

using GPUCompiler: GPUCompiler
using LLVM: LLVM
using Libdl: Libdl


export generate_shlib, generate_shlib_fptr, compile, native_code_llvm, native_code_typed, native_llvm_module

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
    open(path, "w") do io
        job, kwargs = native_job(f, tt; name, kwargs...)
        obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)
        
        write(io, obj)
        flush(io)
        run(`gcc -shared -o $path.$(Libdl.dlext) $path`)
        rm(path)
    end
    path, name
end

function generate_shlib_fptr(f, tt, path::String=tempname(), name = GPUCompiler.safe_name(repr(f)); temp::Bool=true, kwargs...)
    generate_shlib(f, tt, path, name; kwargs...)
    ptr = Libdl.dlopen("$(abspath(path)).$(Libdl.dlext)", Libdl.RTLD_LOCAL)
    fptr = Libdl.dlsym(ptr, "julia_$name")
    @assert fptr != C_NULL
    if temp
        atexit(()->rm("$path.$(Libdl.dlext)"))
    end
    fptr
end

function generate_shlib_fptr(path::String, name)
    ptr = Libdl.dlopen("$(abspath(path)).$(Libdl.dlext)", Libdl.RTLD_LOCAL)
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
