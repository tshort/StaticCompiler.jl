# Helpers
Note that the helpers defined here are used in tests, and they are useful to test out code in the REPL.

```julia
twox(x) = 2x
# run code in the REPL
@jlrun twox(3)
# compile to an executable in a `standalone` directory
exegen([ (twox, Tuple{Int}, 4) ])
```

These are not meant to be a permanent part of the API. They are just for testing.


```@index
```

```@autodocs
Modules = [StaticCompiler]
Pages   = ["helpers.jl", "jlrun.jl", "juliaconfig.jl", "standalone-exe.jl"]
```
