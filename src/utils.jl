
function julia_to_llvm(@nospecialize x)
    isboxed = Ref{UInt8}()
    # LLVMType(ccall(:jl_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Ref{UInt8}), x, isboxed))    # noserialize
    LLVMType(ccall(:jl_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Ref{UInt8}), x, isboxed))  # julia v1.1.1
end

const jl_value_t_ptr = julia_to_llvm(Any)
const jl_value_t = eltype(jl_value_t_ptr)
# const jl_value_t_ptr_ptr = LLVM.PointerType(jl_value_t_ptr)
# # cheat on these for now:
# const jl_datatype_t_ptr = jl_value_t_ptr
# const jl_unionall_t_ptr = jl_value_t_ptr
# const jl_typename_t_ptr = jl_value_t_ptr
# const jl_sym_t_ptr = jl_value_t_ptr
# const jl_svec_t_ptr = jl_value_t_ptr
# const jl_module_t_ptr = jl_value_t_ptr
# const jl_array_t_ptr = jl_value_t_ptr
#
# const bool_t  = julia_to_llvm(Bool)
# const int8_t  = julia_to_llvm(Int8)
# const int16_t = julia_to_llvm(Int16)
# const int32_t = julia_to_llvm(Int32)
# const int64_t = julia_to_llvm(Int64)
# const uint8_t  = julia_to_llvm(UInt8)
# const uint16_t = julia_to_llvm(UInt16)
# const uint32_t = julia_to_llvm(UInt32)
# const uint64_t = julia_to_llvm(UInt64)
# const float_t  = julia_to_llvm(Float32)
# const double_t = julia_to_llvm(Float64)
# const float32_t = julia_to_llvm(Float32)
# const float64_t = julia_to_llvm(Float64)
# const void_t    = julia_to_llvm(Nothing)
# const size_t    = julia_to_llvm(Int)
#
# const int8_t_ptr  = LLVM.PointerType(int8_t)
# const void_t_ptr  = LLVM.PointerType(void_t)

function module_setup(mod::LLVM.Module)
#    triple!(mod, "wasm32-unknown-unknown-wasm")
#    datalayout!(mod, "e-m:e-p:32:32-i64:64-n32:64-S128")
end

llvmmod(native_code) =
    LLVM.Module(ccall(:jl_get_llvm_module, LLVM.API.LLVMModuleRef,
                      (Ptr{Cvoid},), native_code.p))

function Base.write(mod::LLVM.Module, path::String)
    open(io -> write(io, mod), path, "w")
end


walk(f, x) = true
# walk(f, x::Instruction) = foreach(c->walk(f,c), operands(x))
# walk(f, x::Instruction) = f(x) || foreach(c->walk(f,c), operands(x))
walk(f, x::ConstantExpr) = f(x) || foreach(c->walk(f,c), operands(x))
