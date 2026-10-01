# export the compiled entry points from a Windows DLL
function add_dllexport!(mod::LLVM.Module, funcs; demangle=true)
    for (f, _) in funcs
        name_f = (demangle ? "" : "julia_") * fix_name(f)
        llvmf = get(mod.functions, name_f, nothing)
        if llvmf !== nothing && !isdeclaration(llvmf)
            llvmf.dllstorage = LLVM.DLLStorageClass.Export
        end
    end
end
