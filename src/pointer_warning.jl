function locate_pointers_and_runtime_calls(mod)
    i64 = LLVM.IntType(64)
    # d = IdDict{Any, Tuple{String, LLVM.GlobalVariable}}()
    for func ∈ LLVM.functions(mod), bb ∈ LLVM.blocks(func), inst ∈ LLVM.instructions(bb)
        warned = false
        if isa(inst, LLVM.LoadInst) && occursin("inttoptr", string(inst))
            warned = inspect_pointers(mod, inst)
        elseif isa(inst, LLVM.StoreInst) && occursin("inttoptr", string(inst))
            @debug "Inspecting StoreInst" inst
            warned = inspect_pointers(mod, inst)
        elseif inst isa LLVM.RetInst && occursin("inttoptr", string(inst))
            @debug "Inspecting RetInst" inst LLVM.operands(inst)
            warned = inspect_pointers(mod, inst)
        elseif isa(inst, LLVM.BitCastInst) && occursin("inttoptr", string(inst))
            @debug "Inspecting BitCastInst" inst LLVM.operands(inst)
            warned = inspect_pointers(mod, inst)
        elseif isa(inst, LLVM.CallInst)
            @debug "Inspecting CallInst" inst LLVM.operands(inst)
            dest = LLVM.called_operand(inst)
            if occursin("inttoptr", string(dest)) && length(LLVM.operands(dest)) > 0
                @debug "Inspecting CallInst inttoptr" dest LLVM.operands(dest) LLVM.operands(inst)
                ptr_arg = first(LLVM.operands(dest))
                ptr_val = convert(Int, ptr_arg)
                ptr = Ptr{Cvoid}(ptr_val)

                frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), ptr, 0)
                
                data_warnings(inst, frames)
                warned = true
            end
        end
        if warned
            @warn("LLVM function generated warnings due to raw pointers embedded in the code. This will likely cause errors or undefined behaviour.",
                  func = func)
        end
    end
end

function inspect_pointers(mod, inst)
    warned = false
    jl_t = (LLVM.StructType(LLVM.LLVMType[]))
    for (i, arg) ∈ enumerate(LLVM.operands(inst))
        if occursin("inttoptr", string(arg)) && arg isa LLVM.ConstantExpr
            op1 = LLVM.Value(LLVM.API.LLVMGetOperand(arg, 0))
            if op1 isa LLVM.ConstantExpr
                op1 = LLVM.Value(LLVM.API.LLVMGetOperand(op1, 0))
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

llvmeltype(x::LLVM.Value) = eltype(LLVM.value_type(x))




