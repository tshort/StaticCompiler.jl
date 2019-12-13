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
