module StaticCompiler

export irgen, fix_globals!, optimize!

import Libdl

using LLVM
using LLVM.Interop
using TypedCodeUtils
import TypedCodeUtils: reflect, filter, lookthrough, canreflect,
                       DefaultConsumer, Reflection, Callsite,
                       identify_invoke, identify_call, identify_foreigncall,
                       process_invoke, process_call
using MacroTools


include("serialize.jl")
include("utils.jl")
include("ccalls.jl")
include("globals.jl")
include("overdub.jl")
include("irgen.jl")

end # module
