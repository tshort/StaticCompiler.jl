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

# the operands of `inst` that may be pointers to julia data or runtime functions
pointer_operands(inst) = ()
pointer_operands(inst::Union{LLVM.LoadInst, LLVM.StoreInst, LLVM.RetInst, LLVM.BitCastInst}) = inst.operands
pointer_operands(inst::LLVM.CallInst) = (inst.called_operand,)

isinttoptr(x) = x isa LLVM.ConstantExpr && occursin("inttoptr", string(x))

# the address embedded in an `inttoptr` constant, or `nothing` if it is not a known constant
function constant_address(x)
    op = x.operands[1]
    if op isa LLVM.ConstantExpr
        op = op.operands[1]
    end
    op isa LLVM.ConstantInt ? convert(Int, op) : nothing
end

# warn if `operand` of `inst` is a raw pointer, returning whether it was
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
