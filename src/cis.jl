using SemialgebraicSets
using Polyhedra

export getis, fillis!, algebraiclift

function algebraiclift(s::DiscreteLinearControlSystem{T, MT, FullSpace}) where {T, MT}
    n = statedim(s)
    z = find(i -> iszero(sum(abs.(s.B[i,:]))), 1:n)
    # TODO ty - 1//2y^3 + 3//1xy + 2//1yhe affine space may not be parallel to classical axis
    DiscreteLinearAlgebraicSystem(s.A[z, :], (eye(n))[z, :])
end
algebraiclift(s::DiscreteIdentitySystem) = s
algebraiclift(S::AbstractVector) = algebraiclift.(S)
algebraiclift(S::ConstantVector) = ConstantVector(algebraiclift(first(S)), length(S))
function algebraiclift(h::HybridSystem)
    HybridSystem(h.automaton, algebraiclift(h.modes), h.invariants, h.guards, algebraiclift(h.resetmaps), h.switchings)
end

function r(A::Matrix{T}, c::Vector{T}=zeros(T, size(A, 1))) where T
    [one(T) zeros(T, 1, size(A, 2))
     c A]
end

"""
    householder(x)

Householder reflection
```math
I - 2 v v^T / (v^T v)
```
It is symmetric and orthogonal.
"""
function householder(x)
    y = copy(x)
    t = LinAlg.reflector!(y)
    v = [1; y[2:end]]
    eye(length(x)) - t * v * v'
end

using DynamicPolynomials
using MultivariatePolynomials
using PolyJuMP
using SumOfSquares
using MathOptInterface
const MOI = MathOptInterface
using JuMP
using LightGraphs
function ATrp(p, x, A)
    B = r(A)'
    y = x[1:size(B, 2)]
    p(x => B * y)
end
# If Re is a vector not constant, I would be comparing dummy variables of different meaning
function lhs(p, x, Re::DiscreteLinearAlgebraicSystem)
    ATrp(p, x, Re.A)
end

const DTAHAS = HybridSystem{<:AbstractAutomaton, DiscreteIdentitySystem, <:HRep, FullSpace, <:DiscreteLinearAlgebraicSystem}
function _vars(s::DTAHAS)
    @polyvar x[1:statedim(s, 1)] z
    [z; x]
end
function _p(q, N, y, l, is, ps, h)
    if q in N
        l[q].p
    else
        if isnull(ps[q])
            le = LiftedEllipsoid(is[q])
            Pd = inv(le.P)
            H = _householder(h[q])
            HPdH = H * Pd * H
            # HPdH is not like a solution what would be obtained by solving the program
            # since the λ computed for unlifting it is maybe not one.
            # Therefore, the S-procedure's λ for the constraints will be different.
            B, b, β, λ = Bbβλ(HPdH)
            ps[q] = Nullable(y' * _HPH(B/λ, b/λ, β/λ, H) * y)
        end
        get(ps[q])
    end
end

function fillis!(is, N, s::DTAHAS, solver, h=map(cv->InteriorPoint(cv[1]), chebyshevcenter.(s.invariants)); y=_vars(s), ps=fill(Nullable{polynomialtype(y, Float64)}(), length(is)), cone=SOSCone(), λ=Dict{transitiontype(s), Float64}(), enabled = 1:nstates(s), detcone = contains(string(solver()), "SCS") ? MOI.LogDetConeTriangle : MOI.RootDetConeTriangle)
    n = nstates(s)
    m = SOSModel(solver=solver)
    l = Dict(u => getp(m, h[u], y, cone, detcone) for u in N)

    @objective m Max sum(p -> p.vol, values(l))

    λouts = Dict{transitiontype(s), JuMP.AffExpr}()

    for q in N
        # Constraint 1
        NN = length(out_transitions(s, q))
        for t in out_transitions(s, q)
            λin = get(λ, t, nothing)
            if target(s, t) in enabled
                λouts[t] = lyapconstraint(v -> _p(v, N, y, l, is, ps, h), N, s, l, y, t, m, cone, λin)
            end
        end
        # Constraint 2
        #@SDconstraint m differentiate(p[q], x, 2) >= 0
        # Constraint 3
        for hs in ineqs(s.invariants[q])
            @constraint m l[q].p(y => [-hs.β; hs.a]) <= 0
        end
    end

    JuMP.solve(m)

    if MOI.canget(m, MOI.SolveTime())
        @show MOI.get(m, MOI.SolveTime())
    end

    @show JuMP.terminationstatus(m)
    @show JuMP.primalstatus(m)
    @show JuMP.dualstatus(m)

    @show JuMP.objectivevalue(m)

    for (t, λout) in λouts
        println("λ for $t is $(JuMP.resultvalue.(λout))")
    end

    for q in N
        lv = JuMP.resultvalue(l[q])
        ps[q] = Nullable(lv.p)
        is[q] = ellipsoid(lv)
    end
end

function getis(s::DTAHAS, args...; kws...)
    nmodes = nstates(s)
    is = Vector{Ellipsoid{Float64}}(nmodes)
    fillis!(is, 1:nmodes, s, args...; kws...)
    is
end

const UnboundedControl = DiscreteLinearControlSystem{<:Any,<:Any,FullSpace}

function fillis!(is, N, s::HybridSystem{<:AbstractAutomaton, DiscreteIdentitySystem, <:HRep, FullSpace, <:UnboundedControl}, args...; kws...)
    fillis!(is, N, algebraiclift(s), args...; kws...)
end
function getis(s::HybridSystem{<:AbstractAutomaton, DiscreteIdentitySystem, <:HRep, FullSpace, <:UnboundedControl}, args...; kws...)
    getis(algebraiclift(s), args...; kws...)
end
