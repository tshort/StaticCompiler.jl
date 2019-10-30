include("./jlrun.jl")

using Formatting

# Definitions of functions to compile
twox(x) = 2x

const aa = [4, 5]
arrayfun(x) = x + aa[1] + aa[2]

jsin(x) = sin(x)

function arridx(i)
    a = collect(1.0:0.1:10.0)
    @inbounds i > 3 ? a[1] : a[5]
end

fsimple() = [0:.001:2;][end]

include("ode.jl")
fode() = ode23s((t,y)->2.0t^2, 0.0, [0:.001:2;], initstep = 1e-4)[2][end]

# Functions to compile and arguments to pass
funcs = [
    (twox, Tuple{Int}, 4),
    (arrayfun, Tuple{Int}, 4),
    (jsin, Tuple{Float64}, 0.5),
    (arridx, Tuple{Int}, 4),
    (fsimple, Tuple{}, ()),
    (fode, Tuple{}, ()),         # Broken on Julia v1.2.0; works on Julia v1.3.0-rc3
]

Ctemplate = """
#include <stdio.h> 
#include <julia.h> 

extern CRETTYPE FUNNAME(CARGTYPES);
extern void jl_init_with_image(const char *, const char *);
extern void jl_init_globals(void);

int main()
{
   jl_init_with_image(".", "blank.ji");
   jl_init_globals();
   printf("RETFORMAT", FUNNAME(FUNARG));
   jl_atexit_hook(0);
   return 0;
}
"""

Cmap = Dict(
    Cint => "int",
    Clong => "long",
    Cdouble => "double",
    Nothing => "void",
)
Cformatmap = Dict(
    Cint => "%d",
    Clong => "%ld",
    Cdouble => "%e",
)

totext(x) = string(x)
totext(x::Nothing) = ""
totext(x::Tuple{}) = ""

cd(mkpath("standalone")) do
    # create `blank.ji` for initialization
    julia_path = joinpath(Sys.BINDIR, Base.julia_exename())
    base_dir = dirname(Base.find_source_file("sysimg.jl"))
    wd = pwd()
    open(println, "blank.jl", "w")
    cd(base_dir) do
        run(`$(julia_path) --output-ji $(wd)/blank.ji $(wd)/blank.jl`)
    end
    
    dir = @__DIR__
    bindir = string(Sys.BINDIR, "/../tools")
    bindir = string(Sys.BINDIR)
    
    for (func, tt, val) in funcs
        fname = nameof(func)
        rettype = Base.return_types(func, tt)[1]
        argtype = length(tt.types) > 0 ? tt.types[1] : Nothing
        fmt = Cformatmap[rettype]
        Ctxt = foldl(replace, 
                     (
                      "FUNNAME" => fname, 
                      "CRETTYPE" => Cmap[rettype], 
                      "RETFORMAT" => fmt, 
                      "CARGTYPES" => Cmap[argtype], 
                      "FUNARG" => totext(val),
                     ), 
                     init = Ctemplate)
        write("$fname.c", Ctxt)
        m = StaticCompiler.irgen(func, tt)
        StaticCompiler.fix_globals!(m)
        StaticCompiler.optimize!(m)
        # show_inttoptr(m)
        # @show m
        write(m, "$fname.bc")
        write_object(m, "$fname.o")
        run(`gcc -shared -fpic $fname.o -o lib$fname.so`)
        run(`gcc -c -std=gnu99 -I$bindir/../include/julia -DJULIA_ENABLE_THREADING=1 -fPIC $fname.c`)
        run(`gcc -o $fname $fname.o -L$dir/standalone -L$bindir/../lib -Wl,--unresolved-symbols=ignore-in-object-files -Wl,-rpath,'.' -Wl,-rpath,$bindir/../lib -ljulia -l$fname`)
        @test Formatting.sprintf1(fmt, func(val...)) == read(`./$fname`, String)
    end
end
