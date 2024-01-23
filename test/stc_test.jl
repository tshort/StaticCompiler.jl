using StaticCompiler
using StaticTools

const con = 1

struct A
  f::Int
end

mutable struct B
  f::Int

  function B(c::Int)
    d = c*c
    new(d)
  end

end

hello() = println(c"Hello world!")

# function calls
function main_function()
  vars_strings_print()
  printtofile()
  more_complex_datatypes()
  shellcommands()
  readfiles()
  controlflow()
end

@inline function vars_strings_print()
  println(c"\nvars_strings_print:\n")
  a = 1
  n = 1.4
  b = :b    
  s = c"abcde"
  t = s[1:3]  
  u = copy(s)
  v = view(s,1:3)
  w = s * c"rte"
  sm = m"abcd"
  tm = sm[1:3]
  um = copy(sm)
  vm = view(sm,1:3)
  wm = sm * c"rte"
  printf(c"b: :")
  if b == :b
    printf(c"b")
  else
    printf(c"other")
  end
  newline()
  printf(c"a: %d\n", a)
  printf(c"n: %g\n", n)
  #bs = StaticString(string(b))
  #println(c"b:")
  #printf(bs)
  #newline()
  printf(c"s: ")
  println(s)
  printf(c"t: ")
  println(t)
  printf(c"u: ")
  println(u)
  printf(c"v: ")
  println(v)
  printf(c"w: ")
  println(w)
  printf(c"sm: ")
  println(sm)
  printf(c"tm: ")
  println(tm)
  printf(c"um: ")
  println(um)
  printf(c"vm: ")
  println(vm)
  printf(c"wm: ")
  println(wm)
  free(sm)
end

@inline function printtofile()
  printf(c"\nprinttofile:\n")
  a = 1
  n = 1.4
  s = c"abcdef"
  fp = fopen(c"C:/jul/staticcompiler/testfile.txt",c"w")
  printf(fp, c"a: %d\n", a)
  printf(fp, c"n: %g\n", n)
  printf(fp, c"n: %f\n", n)
  printf(fp, (c"s: ",s, c"\n"))
  fclose(fp)
end

# Arrays, Matrices, Tuples, Structs, Constants, NamedTuples
@inline function more_complex_datatypes()
  println(c"\nmore_complex_datatypes:\n")
  a = 1:5
  b = a*2
  c = a[1]
  d = a[1:3]

  e = StackArray{Int64}(undef, 20)
  e[1:end] = 1
  f = reshape(e, 5, 4)
  g = StackMatrix{Int64}(undef, 2, 3) 
  # compile error in LLVM IR
  #g[:] = [1,2,3,4,5,6]
  h = sfill(4,2,3)
  i = sones(2,3)
  j = szeros(2,3)

  k = MallocArray{Int64}(undef, 20)
  k[1:end] = 1
  l = reshape(k, 5, 4)
  m = mfill(4, 11,10)
  n = mones(2,3)
  o = mzeros(2,3)

  p = MallocMatrix{Int64}(undef, 2, 3) 
  # compile error in LLVM IR
  #g[:] = [1,2,3,4,5,6]
  q = mfill(4,2,3)
  r = mones(2,3)
  s = mzeros(2,3)

  t = MallocVector{Float64}(undef, 2)
  fill!(p, 2)

  println(c"a:")
  printf(a)
  println(c"b:")
  printf(b)
  printf(c"c: %d\n", c)
  println(c"d:")
  printf(d)
  println(c"e:")
  printf(e)
  println(c"g:")
  printf(g)
  println(c"h:")
  printf(h)
  println(c"i:")
  printf(i)
  println(c"j:")
  printf(j)
  println(c"k:")
  printf(k)
  println(c"l:")
  printf(l)
  println(c"m:")
  printf(m)
  println(c"n:")
  printf(n)
  println(c"o:")
  printf(o)
  println(c"p:")
  printf(p)
  println(c"q:")
  printf(q)
  println(c"r:")
  printf(r)
  println(c"s:")
  printf(s)
  println(c"t:")
  printf(t)

  free(k)
  # compile error:  `arrays_matrices_tuples_tests()` did not infer to a concrete type. Got `Union{}`
  #free(l)
  free(m)
  free(n)
  free(o)
  free(p)
  free(q)
  free(r)
  free(s)
  free(t)

  # tuples
  u = (1,2,3)
  v = first(u)
  w = last(u)
  println(c"tuples:")
  printf(u)
  for i in 1:length(u)
    printf(u[i])
  end
  newline()
  printf(c"\nv: %d\n", v)
  printf(c"w: %d\n", w)
#=
  # named tuples
  n = (:a => 1, :b=> 2)
  println((c"n[1][2]:",n[1][2],"c\n"))
  m = (a=1,b=2)
  printf((c"m.a:",m.a,c"\n"))
  
  # constants
  printf(c"con: %d\n", c)

  # structs
  a = A(1)
  printf(c"a.f: %d\n", a.f)
  b = B(2)
  printf(c"b.f: %d\n", b.f)


=#
end

# shell commands
@inline function shellcommands()
  printf(c"\nshellcommands:\n")
  msg = m"cd"
  StaticTools.system(msg)
  free(msg)
  msg = c"cd"
  StaticTools.system(msg)
  msg = c"echo hello world!"
  StaticTools.system(msg)
end

# read from files
@inline function readfiles()
  println(c"\nreadfiles:\n")
  name, mode = m"testfile.txt", m"r"
  fp = fopen(name, mode)
  b = ftell(fp)
  str = MallocString(undef, 100)
  d = gets!(str, fp)
  e = str[1]
  f = ftell(fp)
  g = frewind(fp)
  h = readline!(str, fp)
  printf(c"str after readline!:")
  printf(str)  
  i = str[1] 
  j = fseek(fp, -2, SEEK_CUR)
  k = gets!(str, fp)
  printf(c"str after gets!:")
  printf(str) 
  l = str[1]
  free(str)
  m = frewind(fp)
  n = getc(fp)
  o = getc(fp)
  p = read(fp, UInt8)
  q = frewind(fp)
  str = readline(fp)
  printf(c"str after readline:")
  printf(str) 
  r = str[1]
  free(str)
  fclose(fp)

  str = read(c"testfile.txt", MallocString)
  println(c"str after read:")
  printf(str)

  fread!(str, c"testfile.txt") # == strc
  free(str)

  free(name)
  free(mode)

  printf(c"b: %d\n", b)
  println(c"d:")
  printf(d)
  println(c"\ne:")
  printf(e)
  printf(c"\nf: %d\n", f) 
  printf(c"g: %d\n", g) 
  println(c"h:")
  printf(h)
  println(c"i:")
  printf(i)
  println(c"\nj:")
  printf(j)
  println(c"\nk:")
  printf(k)
  println(c"\nl:")
  printf(l)
  println(c"\nm:")
  printf(m)
  println(c"\nn:")
  printf(n)
  println(c"\no:")
  printf(o)
  println(c"\np:")
  printf(p)
  println(c"\nq:")
  printf(q)
  println(c"\nr:")
  printf(r)
end

# control flow
@inline function controlflow()
  println(c"\ncontrolflow:\n")
  for i in 1:5
    if i==2
      continue
    end
    if i==4
      break
    end
    printf(c"i: %d\n", i)
  end
  j = 0
  while j<4
    j += 1
    printf(c"j: %d\n", j)
  end
  a = 2
  if a==1
    println(c"a is 1")
  elseif a==2
    println(c"a is 2")
  else
    println(c"a is neither 1 nor 2")
  end
  b = a==2 ? 1 : 3
  printf(c"b: %d\n", b)  
  # compile error 
  #try
  #   g
  #catch
  #  a = 1
  #end
end


# Attempt to compile
compile_executable(main_function, (), "C:\\jul\\staticcompiler")
