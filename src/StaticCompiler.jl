module StaticCompiler

import GPUCompiler
import LLVM
import LLVM_full_jll
import Libdl

export generate_shlib_fptr, compile

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

const linker = Sys.isunix() ? "ld.lld" : Sys.isapple() ? "ld64.lld" : "lld-link"

function generate_shlib_fptr(f, tt, name = GPUCompiler.safe_name(repr(f)))
    mktemp() do path, io
        target = GPUCompiler.NativeCompilerTarget(;reloc=LLVM.API.LLVMRelocPIC, extern=true)
        source = GPUCompiler.FunctionSpec(f, Base.to_tuple_type(tt), false, name)
        params = TestCompilerParams()
        job = GPUCompiler.CompilerJob(target, source, params)
        obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)
        write(io, obj)
        flush(io)
        run(`$(StaticCompiler.LLVM_full_jll.PATH)/$linker -shared -o $path.$(Libdl.dlext) $path`)
        ptr = Libdl.dlopen("$path.$(Libdl.dlext)", Libdl.RTLD_LOCAL)
        fptr = Libdl.dlsym(ptr, "julia_$name")
        @assert fptr != C_NULL
        atexit(()->rm("$path.$(Libdl.dlext)"))
        fptr
    end
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
