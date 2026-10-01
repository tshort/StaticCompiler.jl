function locate_pointers_and_runtime_calls(mod)
    i64 = LLVM.IntType(64)
    # d = IdDict{Any, Tuple{String, LLVM.GlobalVariable}}()
    for func ∈ mod.functions, bb ∈ func.blocks, inst ∈ bb.instructions
        warned = false
        if isa(inst, LLVM.LoadInst) && occursin("inttoptr", string(inst))
            warned = inspect_pointers(mod, inst)
        elseif isa(inst, LLVM.StoreInst) && occursin("inttoptr", string(inst))
            @debug "Inspecting StoreInst" inst
            warned = inspect_pointers(mod, inst)
        elseif inst isa LLVM.RetInst && occursin("inttoptr", string(inst))
            @debug "Inspecting RetInst" inst inst.operands
            warned = inspect_pointers(mod, inst)
        elseif isa(inst, LLVM.BitCastInst) && occursin("inttoptr", string(inst))
            @debug "Inspecting BitCastInst" inst inst.operands
            warned = inspect_pointers(mod, inst)
        elseif isa(inst, LLVM.CallInst)
            @debug "Inspecting CallInst" inst inst.operands
            dest = inst.called_operand
            if occursin("inttoptr", string(dest)) && length(dest.operands) > 0
                @debug "Inspecting CallInst inttoptr" dest dest.operands inst.operands
                ptr_arg = first(dest.operands)
                ptr_val = convert(Int, ptr_arg)
                ptr = Ptr{Cvoid}(ptr_val)

                frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), ptr, 0)
                
                data_warnings(inst, frames)
                warned = true
            end
        end
        if warned
            lines = split(string(func),"\n")
            @warn("LLVM function generated warnings due to raw pointers embedded in the code. This will likely cause errors or undefined behaviour.",
                  func = join(lines[1:min(20, end)], "\n")) # just print the first 20 lines
        end
    end
end

function inspect_pointers(mod, inst)
    warned = false
    jl_t = (LLVM.StructType(LLVM.LLVMType[]))
    for (i, arg) ∈ enumerate(inst.operands)
        if occursin("inttoptr", string(arg)) && arg isa LLVM.ConstantExpr
            op1 = arg.operands[1]
            if op1 isa LLVM.ConstantExpr
                op1 = op1.operands[1]
            end
            ptr = Ptr{Cvoid}(convert(Int, op1))
            frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), ptr, 0)
            data_warnings(inst, frames)
            warned = true
        end
    end
    warned
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





