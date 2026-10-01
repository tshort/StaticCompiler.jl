# Test that we can compile an object to wasm
# WebAssemblyCompiler.jl is a better tool for this, but this exercises the cross compilation pipeline

using StaticCompiler
using LLVM
LLVM.InitializeAllTargets()
LLVM.InitializeAllTargetInfos()
LLVM.InitializeAllAsmPrinters()
LLVM.InitializeAllAsmParsers()
LLVM.InitializeAllTargetMCs()

fib(n) = n <= 1 ? n : fib(n - 1) + fib(n - 2)

target=StaticTarget("wasm32","","")

StaticCompiler.generate_obj(fib, Tuple{Int64}, "./test", target=target)
