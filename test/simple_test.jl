using StaticCompiler
using StaticTools

hello() = println(c"Hello world!")
hello()

# Attempt to compile
compile_executable(hello, (), "C:\\jul\\JulWork\\parajul")
