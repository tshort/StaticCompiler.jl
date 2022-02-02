module StaticCompiler

using GPUCompiler: GPUCompiler
using LLVM: LLVM
using Libdl: Libdl


export generate_shlib, generate_shlib_fptr, compile

module TestRuntime
    # dummy methods
    signal_exception() = return
    malloc(sz) = C_NULL
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return

    # for validation
    sin(x) = Base.sin(x)
end

struct TestCompilerParams <: GPUCompiler.AbstractCompilerParams end
GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any,TestCompilerParams}) = TestRuntime

# const linker = Sys.isunix() ? "ld.lld" : Sys.isapple() ? "ld64.lld" : "lld-link"

function generate_shlib(f, tt, path::String = tempname(), name = GPUCompiler.safe_name(repr(f)))
    open(path, "w") do io
        target = GPUCompiler.NativeCompilerTarget(;always_inline=true)
        source = GPUCompiler.FunctionSpec(f, Base.to_tuple_type(tt), false, name)
        params = TestCompilerParams()
        job = GPUCompiler.CompilerJob(target, source, params)
        obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)
        write(io, obj)
        flush(io)
        # run(`$(Clang_jll.PATH[])/clang -shared -o $path.$(Libdl.dlext) $path`)
        run(`gcc -shared -o $path.$(Libdl.dlext) $path`)
        rm(path)
    end
    path, name
end
function generate_shlib_fptr(f, tt, path::String=tempname(), name = GPUCompiler.safe_name(repr(f)); temp::Bool=true)
    generate_shlib(f, tt, path, name)
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

# Return an LLVM module
function compile(f, tt, name = GPUCompiler.safe_name(repr(f)))
    target = GPUCompiler.NativeCompilerTarget(;reloc=LLVM.API.LLVMRelocPIC, extern=true)
    source = GPUCompiler.FunctionSpec(f, Base.to_tuple_type(tt), false, name)
    params = TestCompilerParams()
    job = GPUCompiler.CompilerJob(target, source, params)
    m, _ = GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false)
    return m
end


end # module
