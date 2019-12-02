# Adapted from: https://github.com/JuliaDiffEq/ODE.jl/blob/8954872f956116e78b6c04690f899fe2db696b4e/src/ODE.jl#L84-L360
# MIT license
# Copyright (c) 2009-2015: various contributors: https://github.com/JuliaLang/ODE.jl/contributors

using LinearAlgebra

function hinit(F, x0, t0::T, tend, p, reltol, abstol) where T
    # Returns first step, direction of integration and F evaluated at t0
    tdir = sign(tend-t0)
    tdir==0 && error("Zero time span")
    tau = max(reltol*norm(x0, Inf), abstol)
    d0 = norm(x0, Inf)/tau
    f0 = F(t0, x0)
    d1 = norm(f0, Inf)/tau
    if d0 < 1e-5 || d1 < 1e-5
        h0 = 1e-6
    else
        h0 = 0.01*(d0/d1)
    end
    h0 = convert(T,h0)
    # perform Euler step
    x1 = x0 + tdir*h0*f0
    f1 = F(t0 + tdir*h0, x1)
    # estimate second derivative
    d2 = norm(f1 - f0, Inf)/(tau*h0)
    if max(d1, d2) <= 1e-15
        h1 = max(T(10)^(-6), T(10)^(-3)*h0)
    else
        pow = -(2 + log10(max(d1, d2)))/(p + 1)
        h1 = 10^pow
    end
    h1 = convert(T,h1)
    return tdir*min(100*h0, h1, tdir*(tend-t0)), tdir, f0
end

function fdjacobian(F, x::Number, t)
    ftx = F(t, x)

    # The 100 below is heuristic
    dx = (x .+ (x==0))./100
    dFdx = (F(t,x+dx)-ftx)./dx

    return dFdx
end

function fdjacobian(F, x, t)
    ftx = F(t, x)
    lx = max(length(x),1)
    dFdx = zeros(eltype(x), lx, lx)
    for j = 1:lx
        # The 100 below is heuristic
        dx = zeros(eltype(x), lx)
        dx[j] = (x[j] .+ (x[j]==0))./100
        dFdx[:,j] = (F(t,x+dx)-ftx)./dx[j]
    end
    return dFdx
end

# ODE23S  Solve stiff systems based on a modified Rosenbrock triple
# (also used by MATLAB's ODE23s); see Sec. 4.1 in
#
# [SR97] L.F. Shampine and M.W. Reichelt: "The MATLAB ODE Suite," SIAM Journal on Scientific Computing, Vol. 18, 1997, pp. 1–22
#
# supports keywords: points = :all | :specified (using dense output)
#                    jacobian = G(t,y)::Function | nothing (FD)
function ode23s(F, y0, tspan;
                reltol = 1.0e-5, abstol = 1.0e-8,
                jacobian=nothing,
                points=:all,
                norm=LinearAlgebra.norm,
                minstep=abs(tspan[end] - tspan[1])/1e18,
                maxstep=abs(tspan[end] - tspan[1])/2.5,
                initstep=0.)

    # select method for computing the Jacobian
    if typeof(jacobian) == Function
        jac = jacobian
    else
        # fallback finite-difference
        jac = (t, y)->fdjacobian(F, y, t)
    end

    # constants
    d = 1/(2 + sqrt(2))
    e32 = 6 + sqrt(2)


    # initialization
    t = tspan[1]

    tfinal = tspan[end]

    h = initstep
    if h == 0.
        # initial guess at a step size
        h, tdir, F0 = hinit(F, y0, t, tfinal, 3, reltol, abstol)
    else
        tdir = sign(tfinal - t)
        F0 = F(t,y0)
    end
    h = tdir * min(abs(h), maxstep)

    y = y0
    tout = [t]         # first output time
    yout = [deepcopy(y)]        # first output solution

    J = jac(t,y)    # get Jacobian of F wrt y
# Core.print(t, " ", tfinal, " ", minstep, " ", h)
    while abs(t - tfinal) > 0 && minstep < abs(h)
        if abs(t-tfinal) < abs(h)
            h = tfinal - t
        end

        if size(J,1) == 1
            W = I - h*d*J
        else
            # note: if there is a mass matrix M on the lhs of the ODE, i.e.,
            #   M * dy/dt = F(t,y)
            # we can simply replace eye(J) by M in the following expression
            # (see Sec. 5 in [SR97])

            W = lu( I - h*d*J )
        end

        # approximate time-derivative of F
        T = h*d*(F(t + h/100, y) - F0)/(h/100)

        # modified Rosenbrock formula
        k1 = W\(F0 + T)
        F1 = F(t + 0.5*h, y + 0.5*h*k1)
        k2 = W\(F1 - k1) + k1
        ynew = y + h*k2
        F2 = F(t + h, ynew)
        k3 = W\(F2 - e32*(k2 - F1) - 2*(k1 - F0) + T )

        err = (abs(h)/6)*norm(k1 - 2*k2 + k3) # error estimate
        delta = max(reltol*max(norm(y),norm(ynew)), abstol) # allowable error

        # check if new solution is acceptable
        if  err <= delta

            # # if points==:specified || points==:all
            #     # only points in tspan are requested
            #     # -> find relevant points in (t,t+h]
            #     for toi in tspan[(tspan.>t) .& (tspan.<=t+h)]
            #         # rescale to (0,1]
            #         s = (toi-t)/h

            #         # use interpolation formula to get solutions at t=toi
            #         push!(tout, toi)
            #         push!(yout, y + h*( k1*s*(1-s)/(1-2*d) + k2*s*(s-2*d)/(1-2*d)))
            #     end
            #     # Core.print("First\n")
            # # end
            # if points==:all
            if (tout[end]!=t+h)
            #     # add the intermediate points
                push!(tout, t + h)
                push!(yout, ynew)
            end

            # update solution
            t = t + h
            y = ynew

            F0 = F2         # use FSAL property
            J = jac(t,y)    # get Jacobian of F wrt y
                            # for new solution
        end

        # update of the step size
        h = tdir*min( maxstep, abs(h)*0.8*(delta/err)^(1/3) )
    end

    return tout, yout
end


# fode() = ode23s((t,y)->2.0t^2, 0.0, Float64[0:.001:2;], initstep = 1e-4)[2][end]
# fode() = ode23s((t,y)->2.0t^2, 0.0, [0:.001:2;], initstep = 1e-4)[2][end]

# @show fode()
