function relocation_table!(mod)
    i64 = LLVM.IntType(64; ctx=LLVM.context(mod))
    jl_t = LLVM.PointerType(LLVM.StructType(LLVM.LLVMType[]; ctx=LLVM.context(mod)))
    d = Dict{String, Any}()
    
    for func ∈ LLVM.functions(mod), bb ∈ LLVM.blocks(func), inst ∈ LLVM.instructions(bb)
        if isa(inst, LLVM.LoadInst) && occursin("inttoptr", string(inst)) 
            get_pointers!(d, mod, inst)
        elseif isa(inst, LLVM.StoreInst) && occursin("inttoptr", string(inst)) 
            @debug "Relocating StoreInst" inst
            get_pointers!(d, mod, inst)
        elseif inst isa LLVM.RetInst && occursin("inttoptr", string(inst))
            op = LLVM.Value(LLVM.API.LLVMGetOperand(inst, 0))
            if isa(op, LLVM.ConstantExpr)
                @debug "Relocating RetInst inttoptr" inst op
                op1 = LLVM.Value(LLVM.API.LLVMGetOperand(op, 0))
                ptr = Ptr{Cvoid}(convert(Int, op1))
                val = unsafe_pointer_to_objref(ptr) 

                gv_name = GPUCompiler.safe_name(String(gensym(repr(Core.Typeof(val)))))
                
                gv = LLVM.GlobalVariable(mod, jl_t, gv_name)
                LLVM.extinit!(gv, true)
                LLVM.API.LLVMSetOperand(inst, 0, gv)

                d[gv_name] = val
            end
        elseif isa(inst, LLVM.BitCastInst) && occursin("inttoptr", string(inst)) 
            op = LLVM.Value(LLVM.API.LLVMGetOperand(inst, 0))
            get_pointers!(d, mod, inst)
        elseif isa(inst, LLVM.CallInst)
            @debug "Relocating CallInst" inst LLVM.operands(inst)
            dest = LLVM.called_value(inst)
            if occursin("inttoptr", string(dest)) && length(LLVM.operands(dest)) > 0
                @debug "Relocating CallInst inttoptr" dest LLVM.operands(dest) LLVM.operands(inst)
                ptr_arg = first(LLVM.operands(dest))
                ptr_val = convert(Int, ptr_arg)
                ptr = Ptr{Cvoid}(ptr_val)

                frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), ptr, 0)
                if length(frames) >= 1
                    fn, file, line, linfo, fromC, inlined = last(frames)
                    fn = string(fn)
                    if ptr == cglobal(:jl_alloc_array_1d)
                        fn = "jl_alloc_array_1d"
                    end
                    if ptr == cglobal(:jl_alloc_array_2d)
                        fn = "jl_alloc_array_2d"
                    end
                    if ptr == cglobal(:jl_alloc_array_3d)
                        fn = "jl_alloc_array_3d"
                    end
                    if ptr == cglobal(:jl_new_array)
                        fn = "jl_new_array"
                    end
                    if ptr == cglobal(:jl_array_copy)
                        fn = "jl_array_copy"
                    end
                    if ptr == cglobal(:jl_alloc_string)
                        fn = "jl_alloc_string"
                    end
                    if ptr == cglobal(:jl_in_threaded_region)
                        fn = "jl_in_threaded_region"
                    end
                    if ptr == cglobal(:jl_enter_threaded_region)
                        fn = "jl_enter_threaded_region"
                    end
                    if ptr == cglobal(:jl_exit_threaded_region)
                        fn = "jl_exit_threaded_region"
                    end
                    if ptr == cglobal(:jl_set_task_tid)
                        fn = "jl_set_task_tid"
                    end
                    if ptr == cglobal(:jl_new_task)
                        fn = "jl_new_task"
                    end
                    if ptr == cglobal(:malloc)
                        fn = "malloc"
                    end
                    if ptr == cglobal(:memmove)
                        fn = "memmove"
                    end
                    if ptr == cglobal(:jl_array_grow_beg)
                        fn = "jl_array_grow_beg"
                    end
                    if ptr == cglobal(:jl_array_grow_end)
                        fn = "jl_array_grow_end"
                    end
                    if ptr == cglobal(:jl_array_grow_at)
                        fn = "jl_array_grow_at"
                    end
                    if ptr == cglobal(:jl_array_del_beg)
                        fn = "jl_array_del_beg"
                    end
                    if ptr == cglobal(:jl_array_del_end)
                        fn = "jl_array_del_end"
                    end
                    if ptr == cglobal(:jl_array_del_at)
                        fn = "jl_array_del_at"
                    end
                    if ptr == cglobal(:jl_array_ptr)
                        fn = "jl_array_ptr"
                    end
                    if ptr == cglobal(:jl_value_ptr)
                        fn = "jl_value_ptr"
                    end
                    if ptr == cglobal(:jl_get_ptls_states)
                        fn = "jl_get_ptls_states"
                    end
                    if ptr == cglobal(:jl_gc_add_finalizer_th)
                        fn = "jl_gc_add_finalizer_th"
                    end
                    if ptr == cglobal(:jl_symbol_n)
                        fn = "jl_symbol_n"
                    end
                end

                if length(fn) > 1 && fromC                    
                    mod = LLVM.parent(LLVM.parent(LLVM.parent(inst)))
                    lfn = LLVM.API.LLVMGetNamedFunction(mod, fn)

                    if lfn == C_NULL
                        lfn = LLVM.API.LLVMAddFunction(mod, fn, LLVM.API.LLVMGetCalledFunctionType(inst))
                    else
                        lfn = LLVM.API.LLVMConstBitCast(lfn, LLVM.PointerType(LLVM.FunctionType(LLVM.API.LLVMGetCalledFunctionType(inst))))
                    end
                    LLVM.API.LLVMSetOperand(inst, LLVM.API.LLVMGetNumOperands(inst)-1, lfn)
                end
            end
            get_pointers!(d, mod, inst)
        end
    end
    d
end

function get_pointers!(d, mod, inst)
    jl_t = LLVM.PointerType(LLVM.StructType(LLVM.LLVMType[]; ctx=LLVM.context(mod)))
    for (i, arg) ∈ enumerate(LLVM.operands(inst))
        if occursin("inttoptr", string(arg)) && arg isa LLVM.ConstantExpr
            op1 = LLVM.Value(LLVM.API.LLVMGetOperand(arg, 0))
            ptr = Ptr{Cvoid}(convert(Int, op1))

            frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), ptr, 0)
            if length(frames) >= 1
                fn, file, line, linfo, fromC, inlined = last(frames)
                if isempty(String(fn)) || fn == :jl_system_image_data
                    val = unsafe_pointer_to_objref(ptr) 
                    gv_name = GPUCompiler.safe_name(String(gensym(repr(Core.Typeof(val)))))
            
                    gv = LLVM.GlobalVariable(mod, jl_t, gv_name)
                    LLVM.extinit!(gv, true)
                    LLVM.API.LLVMSetOperand(inst, i-1, gv)
                
                    d[gv_name] = val
                else
                    @warn "Found data we don't know how to relocate" frames
                end
            end
        end
    end
end



function absolute_symbols(symbols)
    ref = LLVM.API.LLVMOrcAbsoluteSymbols(symbols, length(symbols))
    LLVM.MaterializationUnit(ref)
end

function pointer_patching_diff(mod::LLVM.Module, path1=tempname(), path2=tempname(); show_reloc_table=false)
    s1 = string(mod)
    write(path1, s1)
    
    d = StaticCompiler.relocation_table!(mod)
    if show_reloc_table
        @show d
    end
    
    s2 = string(mod)
    write(path2, s2)

    run(`diff $p1 $p2`)
end


