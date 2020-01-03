module StaticCompiler

export irgen, write_object, fix_globals!, optimize!, @extern

import Libdl

using LLVM
using LLVM.Interop
using TypedCodeUtils
import TypedCodeUtils: reflect, lookthrough, canreflect,
                       DefaultConsumer, Reflection, Callsite,
                       identify_invoke, identify_call, identify_foreigncall,
                       process_invoke, process_call
using MacroTools
using DataStructures: MultiDict


include("serialize.jl")
include("utils.jl")
include("ccalls.jl")
include("globals.jl")
include("overdub.jl")
include("irgen.jl")
include("extern.jl")

end # module
