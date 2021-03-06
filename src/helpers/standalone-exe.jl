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

# "signed" is removed from signed types
# duplicates will remove automatically
Cmap = Dict(
    Cchar => "char",                #Int8
    Cuchar => "unsigned char",      #UInt8
    Cshort => "short",              #Int16
    # Cstring =>
    Cushort => "unsigned short",    #UInt16
    Cint => "int",                  #Int32
    Cuint => "unsigned int",        #UInt32
    Clong => "long",                #Int32
    Culong => "unsigned long",      #UInt32
    Clonglong => "long long",       #Int64
    Culonglong => "unsigned long long", #UInt64
    # Cintmax_t => "intmax_t",        #Int64
    # Cuintmax_t => "uintmax_t",      #UInt64
    # Csize_t => "size_t",            #UInt
    # Cssize_t => "ssize_t",          #Int
    # Cptrdiff_t => "ptrdiff_t",      #Int
    # Cwchar_t => "wchar_t",          #Int32
    # Cwstring =>
    Cfloat => "float",              #Float32
    Cdouble => "double",            #Float64
    Nothing => "void",
)

Cformatmap = Dict(
    Cchar => "%c",                  #Int8
    # Cuchar => "unsigned char",    #UInt8
    # Cshort => "short",            #Int16
    Cstring => "%s",
    # Cushort => "unsigned short",  #UInt16
    Cint => "%d",  #"i"             #Int32
    Cuint => "%u",                  #UInt32
    Clong => "%ld",                 #Int32
    # Culong => "unsigned long",    #UInt32
    Clonglong => "%lld",            #Int64
    # Culonglong => "unsigned long long", #UInt64
    # Cintmax_t => "intmax_t",      #Int64
    # Cuintmax_t => "uintmax_t",    #UInt64
    # Csize_t => "size_t",          #UInt
    # Cssize_t => "ssize_t",        #Int
    # Cptrdiff_t => "ptrdiff_t",    #Int
    # Cwchar_t => "wchar_t",        #Int32
    # Cwstring =>
    # Cfloat => "%f",               #Float32
    Cdouble => "%f", #%e            #Float64
)

"""
converts to text. returns "" for Nothing and empty Tuple.
"""
totext(x) = string(x)
totext(x::Nothing) = ""
totext(x::Tuple{}) = ""

"""
Makes standalone executable.
"""
function exegen(funcalls)

    cd(mkpath("standalone")) do
        # create `blank.ji` for initialization
        julia_path = joinpath(Sys.BINDIR, Base.julia_exename())
        base_dir = dirname(Base.find_source_file("sysimg.jl"))
        wd = pwd()
        open(println, "blank.jl", "w")
        cd(base_dir) do
            run(`$(julia_path) --output-ji $(wd)/blank.ji $(wd)/blank.jl`)
        end

        dir = pwd()
        standalonedir = dir
        bindir = string(Sys.BINDIR)
        libdir = joinpath(dirname(Sys.BINDIR), "lib")
        includedir = joinpath(dirname(Sys.BINDIR), "include", "julia")
        if Sys.iswindows()
            for fn in readdir(bindir)
                if splitext(fn)[end] == ".dll"
                    cp(joinpath(bindir, fn), fn, force = true)
                end
            end
        end

        flags = join((cflags(), ldflags(), ldlibs()), " ")
        flags = Base.shell_split(flags)
        wrapper = joinpath(@__DIR__, "embedding_wrapper.c")
        if Sys.iswindows()
            rpath = ``
        elseif Sys.isapple()
            rpath = `-Wl,-rpath,'@executable_path' -Wl,-rpath,'@executable_path/../lib'`
        else
            rpath = `-Wl,-rpath,\$ORIGIN:\$ORIGIN/../lib`
        end

        for (func, tt, val) in funcalls
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
            # StaticCompiler.show_inttoptr(m)
            # @show m
            dlext = Libdl.dlext
            exeext = Sys.iswindows() ? ".exe" : ""
            if Sys.isapple()
                o_file = `-Wl,-all_load $fname.o`
            else
                o_file = `-Wl,--whole-archive $fname.o -Wl,--no-whole-archive`
            end
            extra = Sys.iswindows() ? `-Wl,--export-all-symbols` : ``
            write(m, "$fname.bc")
            write_object(m, "$fname.o")

            run(`$shellcmd -shared -fpic -L$libdir -o lib$fname.$dlext $o_file  -Wl,-rpath,$libdir -ljulia $extra`)
            run(`$shellcmd -c -std=gnu99 -I$includedir -DJULIA_ENABLE_THREADING=1 -fPIC $fname.c`)
            #run(`$shellcmd -o $fname $fname.o -L$libdir -L$standalonedir -Wl,--unresolved-symbols=ignore-in-object-files -Wl,-rpath,'.' -Wl,-rpath,$libdir -ljulia -l$fname -O2 $rpath $flags`)
            run(`$shellcmd -o $fname $fname.o -L$libdir -L$standalonedir -Wl,-rpath,'.' -Wl,-rpath,$libdir -ljulia -l$fname -O2 $rpath $flags`)
        end
    end

end
