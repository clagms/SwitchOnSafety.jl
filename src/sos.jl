using JuMP
using PolyJuMP
using SumOfSquares
using MathProgBase

using MathOptInterface
const MOI = MathOptInterface

export getlyap, soslyap, soslyapb, sosbuildsequence

# Storing the Lyapunov
function setlyap!(s, lyap::Lyapunov)
    d = lyap.d
    lyaps = getlyaps(s)
    if length(lyaps) < d
        sizehint!(lyaps, d)
        while length(lyaps) < d
            push!(lyaps, nothing)
        end
    end
    lyaps[d] = lyap
end
function getlyap(s::AbstractSwitchedSystem, d::Int; solver=()->nothing, tol=1e-5)
    lyaps = getlyaps(s)
    if d > length(lyaps) || isnull(lyaps[d])
        soslyapb(s, d, solver=solver, tol=1e-5, cached=true)
    end
    get(lyaps[d])
end

function getsoslyapinitub(s::AbstractDiscreteSwitchedSystem, d::Integer)
    #_, sosub = pradiusb(s, 2*d)
    #sosub
    Inf
end
#function getsoslyapinitub(s::AbstractContinuousSwitchedSystem, d::Integer)
#    Inf
#end

function getsoslyapinit(s, d)
    lyaps = getlyaps(s)
    if d <= length(lyaps) && !isnull(lyaps[d])
        lyap = get(lyaps[d])
        lyap.soslb, lyap.dual, lyap.sosub, lyap.primal
    else
        # The SOS ub is greater than the JSR hence also greater than any of its lower bound.
        # Hence getlb(s) can be used as an initial lowerbound
        getlb(s), nothing, getsoslyapinitub(s, d), nothing
    end
end

# Building the Lyapunov constraints
function soslyapforward(s::AbstractDiscreteSwitchedSystem, p::Polynomial, path)
    xin = _variables(s, source(s, path))
    xout = _variables(s, target(s, path))
    p(xout => dynamicfort(s, path) * vec(xin))
end
#function soslyapforward(s::AbstractContinuousSwitchedSystem, p::Polynomial, mode::Int)
#    x = variables(p)
#    dot(differentiate(p, x), dynamicfor(s, mode) * x)
#end
soslyapscaling(s::AbstractDiscreteSwitchedSystem, γ, d) = γ^(2*d)
#soslyapscaling(s::AbstractContinuousSwitchedSystem, γ, d) = 2*d*γ
function soslyapconstraint(s::AbstractSwitchedSystem, model::JuMP.Model, p, edge, d, γ)
    getid(x) = x.id
    @constraint model soslyapforward(s, lyapforout(p, edge), edge) <= soslyapscaling(s, γ, d) * lyapforin(p, edge)
end
function soslyapconstraints(s::AbstractSwitchedSystem, model::JuMP.Model, p, d, γ)
    [soslyapconstraint(s, model, p, t, d, γ) for t in transitions(s)]
end
measurefor(μs, s::DiscreteSwitchedLinearSystem, t) = μs[t]
measurefor(μs, s::ConstrainedDiscreteSwitchedLinearSystem, t) = μs[sosdata(s).eid[t]]

function buildlyap(model::JuMP.Model, x::Vector{PolyVar{true}}, d::Int)
    Z = monomials(x, 2*d)
    p = (@variable model [1] Poly(Z))[1]
    @constraint model p >= sum(x.^(2*d))
    p
end
lyapforin(p::Vector, mode::Int) = p[1]
lyapforout(p::Vector, mode::Int) = p[1]
lyapforin(p::Vector, edge::LightGraphs.Edge) = p[edge.src]
lyapforout(p::Vector, edge::LightGraphs.Edge) = p[edge.dst]

function isinfeasible(status::Tuple{MOI.TerminationStatusCode, MOI.ResultStatusCode, MOI.ResultStatusCode})
    status[3] == MOI.InfeasibilityCertificate
end
function isfeasible(status::Tuple{MOI.TerminationStatusCode, MOI.ResultStatusCode, MOI.ResultStatusCode})
    status[2] == MOI.FeasiblePoint
end
function isdecided(status::Tuple{MOI.TerminationStatusCode, MOI.ResultStatusCode, MOI.ResultStatusCode})
    return isinfeasible(status) || isfeasible(status)
end

# Solving the Lyapunov problem
function soslyap(s::AbstractSwitchedSystem, d, γ; solver=()->nothing)
    model = SOSModel(solver=solver)
    p = [buildlyap(model, _variables(s, v), d) for v in states(s)]
    cons = soslyapconstraints(s, model, p, d, γ)
    # I suppress the warning "Not solved to optimality, status: Infeasible"
    #status = solve(model, suppress_warnings=true)
    #@constraint(model, sum(sum(coefficients(lyap)) for lyap in p))
    solve(model)
    status = (JuMP.terminationstatus(model),
              JuMP.primalstatus(model),
              JuMP.dualstatus(model))
    if isinfeasible(status)
        #println("Infeasible $γ")
        @assert !isfeasible(status)
        status, nothing, JuMP.resultdual.(cons)
    elseif isfeasible(status)
        #println("Feasible $γ")
        status, JuMP.resultvalue.(p), nothing
    else
        @assert !isdecided(status)
        status, nothing, nothing
    end
end

function increaselb(s::AbstractDiscreteSwitchedSystem, lb, step)
    lb *= step
end

soschecktol(soslb, sosub) = sosub - soslb
soschecktol(s::AbstractDiscreteSwitchedSystem, soslb, sosub) = soschecktol(log(soslb), log(sosub))
#soschecktol(s::AbstractContinuousSwitchedSystem, soslb, sosub) = soschecktol(soslb, sosub)

sosshift(s::AbstractDiscreteSwitchedSystem, b, shift) = exp(log(b) + shift)
#sosshift(s::AbstractContinuousSwitchedSystem, b, shift) = b + shift

function sosmid(soslb, sosub, step)
    if isfinite(soslb) && isfinite(sosub)
        mid = (soslb + sosub) / 2
    elseif isfinite(soslb)
        mid = soslb + step
    elseif isfinite(sosub)
        mid = sosub - step
    else
        mid = 0
    end
end
usestep(soslb, sosub) = isfinite(soslb) ⊻ isfinite(sosub)
sosmid(s::AbstractDiscreteSwitchedSystem, soslb, sosub, step) = exp(sosmid(log(soslb), log(sosub), step))
usestep(s::AbstractDiscreteSwitchedSystem, soslb, sosub) = usestep(log(soslb), log(sosub))
#sosmid(s::AbstractContinuousSwitchedSystem, soslb, sosub, step) = sosmid(soslb, sosub, step)

function soslb2lb(s::AbstractDiscreteSwitchedSystem, soslb, d)
    n = maximum(statedim.(s, states(s)))
    η = min(ρA(s), binomial(n+d-1, d))
    soslb / η^(1/(2*d))
end
#soslb2lb(s::AbstractContinuousSwitchedSystem, soslb, d) = -Inf

# Binary Search
function soslyapbs(s::AbstractSwitchedSystem, d::Integer, soslb, dual, sosub, primal; solver=()->nothing, tol=1e-5, step=.5, ranktols=tol, disttols=tol)
    while soschecktol(s, soslb, sosub) > tol
        mid = sosmid(s, soslb, sosub, step)
        status, curprimal, curdual = soslyap(s, d, mid, solver=solver)
        if !isdecided(status)
            if usestep(s, soslb, sosub)
                step *= 2
                continue
            end
            # If mid-tol/2 and mid+tol/2 also Stall, there would be an interval of length tol of Stall -> impossible to satisfy requirements
            # the distance between soslb and mid is at least tol/2.
            # Sometimes, mid is far from soslb and is at a point where the solver Stall even if it is far from the optimum point.
            # In that case, it is better to take (mid + soslb)/2
            midlb = min(sosmid(s, soslb, mid, step), sosshift(s, mid, -tol/2))
            # If mid-tol/2 is too close to soslb, we would not make progress!
            # So we ensure we make a progress of at least tol/8. If dual is nothing, then that would still be progress to find a dual
            if dual !== nothing
                midlb = max(midlb, sosshift(s, soslb, tol/8))
            end
            statuslb, curprimallb, curduallb = soslyap(s, d, midlb, solver=solver)
            if isdecided(statuslb)
                mid = midlb
                status = statuslb
                curprimal = curprimallb
                curdual = curduallb
            else
                midub = max(sosmid(s, mid, sosub, step), sosshift(s, mid, tol/2))
                if primal !== nothing
                    midub = min(midub, sosshift(s, sosub, -tol/8))
                end
                statusub, curprimalub, curdualub = soslyap(s, d, midub, solver=solver)
                if isdecided(statusub)
                    mid = midub
                    status = statusub
                    curprimal = curprimalub
                    curdual = curdualub
                end
            end
        end
        if isinfeasible(status)
            dual = curdual
            sosextractcycle(s, dual, d, ranktols=ranktols, disttols=disttols)
            soslb = mid
        elseif isfeasible(status)
            if !(curprimal === nothing) # FIXME remove
                primal = curprimal
            end
            sosub = mid
        else
            warn("Solver returned with status : $statuslb for γ=$midlb, $status for γ=$mid and $statusub for γ=$midub. Stopping bisection with $(soschecktol(s, soslb, sosub)) > $tol (= tol)")
            break
        end
    end
    soslb, dual, sosub, primal
end

# Obtaining bounds with Lyapunov
function soslyapb(s::AbstractSwitchedSystem, d::Integer; solver=()->nothing, tol=1e-5, cached=true, kws...)
    soslb, dual, sosub, primal = soslyapbs(s::AbstractSwitchedSystem, d::Integer, getsoslyapinit(s, d)...; solver=solver, tol=tol, kws...)
    if cached
        if primal === nothing
            if isfinite(sosub)
                status, primal, _ = soslyap(s, d, sosub, solver=solver)
                @assert isfeasible(status)
                @assert primal !== nothing
            else
                error("Bisection ended with infinite sosub=$sosub")
            end
        end
        if dual === nothing
            if isfinite(soslb)
                status, _, dual = soslyap(s, d, soslb, solver=solver)
                if !isinfeasible(status)
                    soslb = sosshift(s, soslb, -tol)
                    status, _, dual = soslyap(s, d, soslb, solver=solver)
                    if !isinfeasible(status)
                        warn("We ignore getlb and start from scratch. tol was probably set too small and soslb is too close to the JSR so soslb-tol is too close to the JSR")
                        soslb = 0. # FIXME fix for continuous
                    end
                    soslb, dual, sosub, primal = soslyapbs(s::AbstractSwitchedSystem, d::Integer, soslb, dual, sosub, primal; solver=solver, tol=tol, kws...)
                    @assert dual !== nothing
                end
            else
                error("Bisection ended with infinite soslb=$soslb")
            end
        end
        setlyap!(s, Lyapunov(d, soslb, dual, sosub, primal))
    end
    ub = sosub
    lb = soslb2lb(s, soslb, d)
    updateb!(s, lb, ub)
end
