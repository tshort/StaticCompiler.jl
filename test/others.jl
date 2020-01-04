mutable struct AAA
    aaa::Int
    bbb::Int
end
@noinline ssum(x) = x.aaa + x.bbb
fstruct(x) = ssum(AAA(x, 99))
@test (@jlrun fstruct(10)) == fstruct(10)

module ZZ
mutable struct AAA
    aaa::Int
    bbb::Int
end
@noinline ssum(x) = x.aaa + x.bbb
fstruct(x) = ssum(AAA(x, 99))
end # module
ffstruct(x) = ZZ.fstruct(x)
@test (@jlrun ffstruct(10)) == ffstruct(10)

const ag = Ref(0x80808080)
jglobal() = ag
@show bg = (@jlrun jglobal())
# @test jglobal()[] == bg[]      # Something's broken with mutable's

arraysum(x) = sum([x, 1])
# @test arraysum(6) == @jlrun arraysum(6)

fsin(x) = sin(x)
@test (@jlrun fsin(0.5)) == fsin(0.5)

fccall() = ccall(:jl_ver_major, Cint, ())
@test (@jlrun fccall()) == fccall()

fcglobal() = cglobal(:jl_n_threads, Cint)
@test (@jlrun fcglobal()) == fcglobal()

const sv = Core.svec(1,2,3,4)
fsv() = sv
@test (@jlrun fsv()) == fsv()

const arr = [9,9,9,9]
farray() = arr
@show (@jlrun farray())
@show farray()
# @test farray() == @jlrun farray()

@noinline f0(x) = 3x
@noinline fop(f, x) = 2f(x)
funcall(x) = fop(f0, x)
@test (@jlrun funcall(2)) == funcall(2)

hi() = print(Core.stdout, 'X')
@jlrun hi()

hello() = print(Core.stdout, "Hello world...\n")
@jlrun hello()

function gx(i)
    a = 2.0:0.1:10.0
    @inbounds i > 3 ? a[1] : a[5]
end

@test (@jlrun gx(4)) == gx(4)

fsimple() = [0:.001:2;][end]

@test (@jlrun fsimple()) == fsimple()

@noinline function fsym(x; l = :hello, s = :x)
    s == :asdf ? x : 2x
end
gsym(x) = fsym(x, l = :hello, s = :asdf) + 1
@test (@jlrun gsym(3)) == gsym(3)
