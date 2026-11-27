## The LLVM module on its way from Julia's code generation to an object, in order

function locate_pointers_and_runtime_calls(mod)
    for func ∈ mod.functions, bb ∈ func.blocks, inst ∈ bb.instructions
        @debug "Inspecting instruction" inst
        warned = false
        for operand ∈ pointer_operands(inst)
            warned |= inspect_pointer(inst, operand)
        end
        if warned
            lines = split(string(func),"\n")
            @warn("LLVM function generated warnings due to raw pointers embedded in the code. This will likely cause errors or undefined behaviour.",
                  func = join(lines[1:min(20, end)], "\n")) # just print the first 20 lines
        end
    end
end

# The operands of `inst` that may be pointers to julia data or runtime functions
pointer_operands(inst) = ()
pointer_operands(inst::Union{LLVM.LoadInst, LLVM.StoreInst, LLVM.RetInst, LLVM.BitCastInst}) = inst.operands
pointer_operands(inst::LLVM.CallInst) = (inst.called_operand,)

isinttoptr(x) = x isa LLVM.ConstantExpr && occursin("inttoptr", string(x))

# The address embedded in an `inttoptr` constant, or `nothing` if it is not a known constant
function constant_address(x)
    op = x.operands[1]
    if op isa LLVM.ConstantExpr
        op = op.operands[1]
    end
    op isa LLVM.ConstantInt ? convert(Int, op) : nothing
end

# Warn if `operand` of `inst` is a raw pointer, returning whether it was
function inspect_pointer(inst, operand)
    isinttoptr(operand) || return false
    address = constant_address(operand)
    if isnothing(address)
        @warn("Found pointer reference to an unknown address", "llvm instruction" = inst)
    else
        frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), Ptr{Cvoid}(address), 0)
        data_warnings(inst, frames)
    end
    return true
end

data_warnings(inst, frames) = for frame ∈ frames
    fn, file, line, linfo, fromC, inlined = frame
    @warn("Found pointer references to julia data",
          "llvm instruction" = inst,
          name = fn,
          file = file,
          line = line,
          fromC = fromC,
          inlined = inlined)
end

# The IR of a target that requires retargeting (`target.retarget`) gets the triple of the target, 
# no data layout (the code generator that makes the object has the target's), 
# and no attributes that name the host's CPU and features. 
# IR that has intrinsics of the host's architecture is refused.
function retarget!(mod::LLVM.Module, target::StaticTarget)
    isnothing(target.retarget) && return mod
    triple = target.retarget.triple
    family = llvm_family(first(split(triple, '-')))
    for f in LLVM.functions(mod)
        m = match(r"^llvm\.(aarch64|arm|x86|wasm)\.", LLVM.name(f))
        isnothing(m) || m.captures[1] == family || throw(ArgumentError("the program uses `$(LLVM.name(f))`, an intrinsic of the code generator of the host's architecture: it can not be made for $triple"))
        attrs = LLVM.function_attributes(f)
        for kind in ("target-cpu", "target-features", "tune-cpu")
            delete!(attrs, kind)
        end
    end
    LLVM.triple!(mod, triple)
    LLVM.datalayout!(mod, "")
    return mod
end

# `int main(int argc, char **argv)` that calls the function `entry` of the module
# Includes `__stack_chk_guard`, which a C library that expect one needs somewhere. 
# A module that has no `entry` is refused.
# `prologue(builder, mod)`, if given, adds to the start of `main`, before the call.
function add_main_wrapper!(mod::LLVM.Module, entry::AbstractString, target::StaticTarget; prologue = nothing)
    haskey(LLVM.functions(mod), entry) || throw(ArgumentError("the module has no function `$entry` to be called by `main`"))
    f = LLVM.functions(mod)[entry]
    i32, ptr = LLVM.IntType(32), LLVM.PointerType()
    fty = LLVM.function_type(f)
    nparams = length(LLVM.parameters(fty))
    nparams in (0, 2) || throw(ArgumentError("`$entry` takes nothing or an `argc` and an `argv`, not $nparams arguments"))
    haskey(LLVM.functions(mod), "main") && throw(ArgumentError("the module has a `main` already"))
    main = LLVM.Function(mod, "main", LLVM.FunctionType(i32, [i32, ptr]))
    LLVM.@dispose builder = LLVM.IRBuilder() begin
        LLVM.position!(builder, LLVM.at_end(LLVM.BasicBlock(main, "entry")))
        isnothing(prologue) || prologue(builder, mod) # (what the program does before its entry point is called)
        args = LLVM.Value[]
        if nparams == 2
            argc_type, argv_type = LLVM.parameters(fty)
            argc, argv = LLVM.parameters(main)
            push!(args, LLVM.sext!(builder, argc, argc_type)) # (an `Int`, usually: `argc` is 32 bits)
            push!(args, argv)
        end
        r = LLVM.call!(builder, fty, f, args)
        rty = LLVM.return_type(fty)
        result = if rty isa LLVM.VoidType
            LLVM.ConstantInt(i32, 0)
        elseif rty isa LLVM.IntegerType
            LLVM.width(rty) > 32 ? LLVM.trunc!(builder, r, i32) : LLVM.width(rty) < 32 ? LLVM.zext!(builder, r, i32) : r
        else
            LLVM.ConstantInt(i32, 0) # (what is not an integer is not an exit status)
        end
        LLVM.ret!(builder, result)
    end
    triple = target_triple(target)
    if !(isapple(target) || startswith(triple, "wasm") || iswindows(target)) && !haskey(LLVM.globals(mod), "__stack_chk_guard")
        guard = LLVM.GlobalVariable(mod, ptr, "__stack_chk_guard")
        LLVM.initializer!(guard, LLVM.const_inttoptr(LLVM.ConstantInt(LLVM.IntType(64), rand(UInt) >> 1), ptr))
    end
    return mod
end

# Export the compiled entry points from a Windows DLL
function add_dllexport!(mod::LLVM.Module, funcs; demangle=true)
    for (f, _) in funcs
        name_f = (demangle ? "" : "julia_") * fix_name(f)
        llvmf = get(mod.functions, name_f, nothing)
        if llvmf !== nothing && !isdeclaration(llvmf)
            llvmf.dllstorage = LLVM.DLLStorageClass.Export
        end
    end
end

## Generating object files from LLVM

"""
    emit_object(mod::LLVM.Module, target::StaticTarget) -> Vector{UInt8}
    emit_object(ir::AbstractString, target::StaticTarget) -> Vector{UInt8}

The object file (the bytes) of the IR, which was made for the host and retargeted (see [`Retarget`](@ref) and [`retarget!`](@ref)), for the target: by the code generator of Julia's LLVM if it has one for the
triple, and else by the `llc` of the target. The CPU and the features are those of the `Retarget`, and the code is position independent (WebAssembly: static).
"""
function emit_object(mod::LLVM.Module, target::StaticTarget)
    r = target.retarget
    isnothing(r) && throw(ArgumentError("only the objects of a target that is made for by retargeting are made by `emit_object` (see `Retarget`)"))
    julia_llvm_has(r.triple) || return emit_object_llc(string(mod), r)
    tm = LLVM.TargetMachine(LLVM.Target(; triple = r.triple), r.triple; cpu = r.cpu, features = r.features, opt_level = LLVM.API.LLVMCodeGenLevelDefault,
                            reloc = startswith(r.triple, "wasm") ? LLVM.API.LLVMRelocStatic : LLVM.API.LLVMRelocPIC)
    try
        return LLVM.emit(tm, mod, LLVM.API.LLVMObjectFile)
    finally
        LLVM.dispose(tm)
    end
end
function emit_object(ir::AbstractString, target::StaticTarget)
    r = target.retarget
    isnothing(r) && throw(ArgumentError("only the objects of a target that is made for by retargeting are made by `emit_object` (see `Retarget`)"))
    julia_llvm_has(r.triple) || return emit_object_llc(ir, r)
    LLVM.@dispose ctx = LLVM.Context() begin
        mod = parse(LLVM.Module, ir)
        try
            return emit_object(mod, target)
        finally
            LLVM.dispose(mod)
        end
    end
end

# Emit the object file via `llc`, if it has a code generator that Julia's LLVM has not
function emit_object_llc(ir::AbstractString, r::Retarget)
    isnothing(r.llc) && throw(ArgumentError("no object can be made for $(r.triple): Julia's LLVM has no code generator for it, and no `llc` is given (`StaticTarget(...; llc = ...)`, of the LLVM version that Julia has, with the code generator for it). The IR can be made (`generate_ir`, `emit_llvm_only = true`)"))
    dir = mktempdir()
    try
        ll, obj = joinpath(dir, "module.ll"), joinpath(dir, "module.o")
        write(ll, ir)
        run(`$(r.llc) -O2 -filetype=obj -mtriple=$(r.triple) -mcpu=$(isempty(r.cpu) ? "generic" : r.cpu) -mattr=$(r.features) -relocation-model=pic $ll -o $obj`)
        return read(obj)
    finally
        rm(dir; recursive = true, force = true)
    end
end
