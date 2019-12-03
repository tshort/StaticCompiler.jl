
include("jlrun.jl")



mutable struct AAA
    aaa::Int
    bbb::Int
end
@noinline ssum(x) = x.aaa + x.bbb
fstruct(x) = ssum(AAA(x, 99))
@test fstruct(10) == @jlrun fstruct(10)

module ZZ
mutable struct AAA
    aaa::Int
    bbb::Int
end
@noinline ssum(x) = x.aaa + x.bbb
fstruct(x) = ssum(AAA(x, 99))
end # module
ffstruct(x) = ZZ.fstruct(x)
@test ffstruct(10) == @jlrun ffstruct(10)

const ag = Ref(0x80808080)
jglobal() = ag
@show bg = @jlrun jglobal()
# @test jglobal()[] == bg[]      # Something's broken with mutable's

arraysum(x) = sum([x, 1])
# @test arraysum(6) == @jlrun arraysum(6)

fsin(x) = sin(x)
@test fsin(0.5) == @jlrun fsin(0.5)

fccall() = ccall(:jl_ver_major, Cint, ())
@test fccall() == @jlrun fccall()

fcglobal() = cglobal(:jl_n_threads, Cint)
@test fcglobal() == @jlrun fcglobal()

const sv = Core.svec(1,2,3,4)
fsv() = sv
@test fsv() == @jlrun fsv()

const arr = [9,9,9,9]
farray() = arr
@show @jlrun farray()
@show farray()
# @test farray() == @jlrun farray()

@noinline f0(x) = 3x
@noinline fop(f, x) = 2f(x)
funcall(x) = fop(f0, x)
@test funcall(2) == @jlrun funcall(2)

hi() = print(Core.stdout, 'X')
@jlrun hi()

hello() = print(Core.stdout, "Hello world...\n")
@jlrun hello()

function gx(i)
    a = 2.0:0.1:10.0
    @inbounds i > 3 ? a[1] : a[5]
end

@test gx(4) == @jlrun gx(4)

fsimple() = [0:.001:2;][end]

@test fsimple() == @jlrun fsimple()

@noinline function fsym(x; l = :hello, s = :x)
    s == :asdf ? x : 2x
end
gsym(x) = fsym(x, l = :hello, s = :asdf) + 1
@test gsym(3) == @jlrun gsym(3)
