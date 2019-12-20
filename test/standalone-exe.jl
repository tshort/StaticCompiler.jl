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

CompilerUtils.exegen(funcs, test = true)
