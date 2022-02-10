"""
    load_function(path) --> compiled_f

load a `StaticCompiledFunction` from a given path. This object is callable.
"""
function load_function(path; filename="obj")
    instantiate(deserialize(joinpath(path, "$filename.cjl")))
end

struct LazyStaticCompiledFunction{rt, tt}
    f::Symbol
    path::String
    name::String
    filename::String
    reloc::Dict{String,Any}
end

function instantiate(p::LazyStaticCompiledFunction{rt, tt}) where {rt, tt}
    # LLVM.load_library_permantly(dirname(Libdl.dlpath(Libdl.dlopen("libjulia"))))
    lljit = LLVM.LLJIT(;tm=LLVM.JITTargetMachine())
    jd = LLVM.JITDylib(lljit)
    flags = LLVM.API.LLVMJITSymbolFlags(LLVM.API.LLVMJITSymbolGenericFlagsExported, 0)
    ofile = LLVM.MemoryBufferFile(joinpath(p.path, "$(p.filename).o")) #$(Libdl.dlext)

    
    # Set all the uninitialized global variables to point to julia values from the relocation table
    for (name, val) ∈ p.reloc
        address = LLVM.API.LLVMOrcJITTargetAddress(reinterpret(UInt, pointer_from_objref(val)))
        symbol = LLVM.API.LLVMJITEvaluatedSymbol(address, flags)
        gv = LLVM.API.LLVMJITCSymbolMapPair(LLVM.mangle(lljit, name), symbol)
        mu = absolute_symbols(Ref(gv)) 
        LLVM.define(jd, mu)       
    end
    # consider switching to one mu for all gvs instead of one per gv.
    # I tried that already, but I got an error saying 
    # JIT session error: Symbols not found: [ __Type_Vector_Float64___274 ]


    # Link to libjulia
    prefix = LLVM.get_prefix(lljit)
    dg = LLVM.CreateDynamicLibrarySearchGeneratorForProcess(prefix)
    LLVM.add!(jd, dg)
    
    LLVM.add!(lljit, jd, ofile)
    fptr = pointer(LLVM.lookup(lljit, "julia_" * p.name))
    
    StaticCompiledFunction{rt, tt}(p.f, fptr, lljit, p.reloc)
end

struct StaticCompiledFunction{rt, tt}
    f::Symbol
    ptr::Ptr{Nothing}
    jit::LLVM.LLJIT
    reloc::Dict{String, Any}
end

function Base.show(io::IO, f::StaticCompiledFunction{rt, tt}) where {rt, tt}
    types = [tt.parameters...]
    print(io, String(f.f), "(", join(("::$T" for T ∈ tt.parameters), ',')  ,") :: $rt")
end

function (f::StaticCompiledFunction{rt, tt})(args...) where {rt, tt}
    Tuple{typeof.(args)...} == tt || error("Input types don't match compiled target $((tt.parameters...,)). Got arguments of type $(typeof.(args))")
    out = RefValue{rt}()
    refargs = Ref(args)
    ccall(f.ptr, Nothing, (Ptr{rt}, Ref{tt}), pointer_from_objref(out), refargs)
    out[]
end

instantiate(f::StaticCompiledFunction) = f
