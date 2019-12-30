"""
    @extern(fun, returntype, argtypes, args...)

Creates a call to an external function meant to be included at link time. 
Use the same conventions as `ccall`.
    
This transforms into the following `ccall`:

    ccall("extern fun", llvmcall, returntype, argtypes, args...)
"""
macro extern(name, rettyp, argtyp, args...)
    externfun = string("extern ", name isa AbstractString || name isa Symbol ? name : name.value)
    Expr(:call, :ccall, externfun, esc(:llvmcall), esc(rettyp), 
         Expr(:tuple, esc.(argtyp.args)...), esc.(args)...)
end

