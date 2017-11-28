using MultivariatePolynomials
using JuMP

using RecipesBase

export Ellipsoid

struct Ellipsoid{T}
    Q::Matrix{T}
    c::Vector{T}
end

@recipe function f(ell::Ellipsoid)
    @assert Base.LinAlg.checksquare(ell.Q) == 2
    αs = linspace(0, 2π, 1024)
    ps = [[cos(α), sin(α)] for α in αs]
    r = [sqrt(dot(p, ell.Q * p)) for p in ps]
    seriestype --> :shape
    legend --> false
    ell.c[1] .+ cos.(αs) ./ r, ell.c[2] .+ sin.(αs) ./ r
end

struct LiftedEllipsoid{T}
    P::Matrix{T}
end

function LiftedEllipsoid(ell::Ellipsoid)
    md = ell.Q*ell.c
    δ = ell.c'*md-1
    d = -md
    D = ell.Q
    P = [δ d'
         d D]
    LiftedEllipsoid(P)
end

Base.convert(::Type{Ellipsoid{T}}, ell::LiftedEllipsoid) where T = convert(Ellipsoid{T}, Ellipsoid(ell))
function Ellipsoid(ell::LiftedEllipsoid)
    # P is
    # λ * [c'Qc-1  -c'Q
    #         -Qc   Q]
    # Let P be [β b'; b B]
    # We have
    # β = λ c'Qc - λ
    # b = -λ Qc <=> Q^{-1/2}b = -λ Q^{1/2} c
    # hence
    # λ c'Qc = β + λ
    # λ^2 c'Qc = b'Q^{-1}b = λ b'B^{-1}b <=> λ c'Qc = b'B^{-1}b
    # Hence λ = b'B^{-1}b - β
    n = LinAlg.checksquare(ell.P)-1
    ix = 1+(1:n)
    β = ell.P[1, 1]
    b = ell.P[1, ix]
    B = ell.P[ix, ix]
    λ = dot(b, B \ b) - β
    c = -(B \ b)
    Q = B / λ
    Ellipsoid(Q, c)
end

@recipe function f(ell::LiftedEllipsoid)
    Ellipsoid(ell)
end

abstract type QuadCone{T, P, S} end

struct CenterPoint{T}
    h::Vector{T}
end
struct CenterQuadCone{T, P<:AbstractPolynomial{T}, S} <: QuadCone{T, P, S}
    p::P
    Q::Matrix{S}
    h::Vector{Float64} # h is the center
    H::Matrix{Float64}
    vol::S
end
CenterQuadCone(p::P, Q::Matrix{S}, c, H, vol::S) where {T, P<:AbstractPolynomial{T}, S} = CenterQuadCone{T, P, S}(p, Q, c, H, vol)
JuMP.resultvalue(p::CenterQuadCone) = CenterQuadCone(JuMP.resultvalue(p.p), JuMP.resultvalue.(p.Q), p.h, p.H, JuMP.resultvalue(p.vol))
_β(h::CenterPoint{T}) where T = -one(T)
_b(h::CenterPoint{T}) where T = zeros(T, length(h.h))
QuadCone(p, Q, b, β, h::CenterPoint, H, vol) = CenterQuadCone(p, Q, h.h, H, vol)

samecenter(l1::CenterQuadCone, l2::CenterQuadCone) = l1.h == l2.h

struct InteriorPoint{T}
    h::Vector{T}
end
struct InteriorQuadCone{T, P<:AbstractPolynomial{T}, S} <: QuadCone{T, P, S}
    p::P
    Q::Matrix{S}
    b::Vector{S}
    β::S
    h::Vector{Float64} # h is an interior point
    H::Matrix{Float64}
    vol::S
end
InteriorQuadCone(p::P, Q::Matrix{S}, b::Vector{S}, β::S, c, H, vol::S) where {T, P<:AbstractPolynomial{T}, S} = InteriorQuadCone{T, P, S}(p, Q, b, β, c, H, vol)
JuMP.resultvalue(p::InteriorQuadCone) = InteriorQuadCone(JuMP.resultvalue(p.p), JuMP.resultvalue.(p.Q), JuMP.resultvalue.(p.b), JuMP.resultvalue(p.β), p.h, p.H, JuMP.resultvalue(p.vol))
_β(h::InteriorPoint) = @variable m
_b(h::InteriorPoint) = @variable m [1:length(h.h)]
QuadCone(p, Q, b, β, h::InteriorPoint, H, vol) = InteriorQuadCone(p, Q, b, β, h.h, H, vol)

samecenter(l1, l2) = false

function getp(m::Model, h, y, cone)
    n = length(y)-1
    #β = 1.#@variable m lowerbound=0.
    β = _β(h)
    b = _b(h)
    #@constraint m b .== 0
    Q = @variable m [1:n, 1:n] Symmetric
    @constraint m y' * [β+1 b'; b Q] * y in cone
    H = householder([1; h.h]) # We add 1, for z
    P = [β b'
         b Q]
    HPH = H * P * H
    p = y' * _HPH(Q, b, β, H) * y
    vol = @variable m
    #@constraint m vol <= trace Q
    @constraint m [vol; [Q[i, j] for j in 1:n for i in 1:j]] in MOI.RootDetConeTriangle(n)
    QuadCone(p, Q, b, β, h, H, vol)
    #@constraint m sum(Q) == 1 # dehomogenize
    #@variable m L[1:n, 1:n]
    #@variable m λinv[1:(n-1)] >= 0
    #@SDconstraint m [Q  L
    #                 L' diagm([λinv; -1])] ⪰ 0
    #QuadCone(x' * Q * x, Q, L, λinv)
end

function lyapconstraint(is, N, s, ps, i, l, y, t, m, λuser)
    σ = symbol(s.automaton, t)
    startp = lhs(l[i].p, y, s.resetmaps[σ])
    v = target(s, t)
    E = s.resetmaps[σ].E
    newp = ATrp(_p(v, N, y, l, is, ps), y, E)
    if v in N && samecenter(l[i], l[v])
        expr = newp - startp
        1.
    else
        if λuser === nothing
            λ = @variable m lowerbound=0
        else
            λ = λuser
        end
        expr = λ * newp - startp
        @constraint m expr in cone
        λ
    end
end

ellipsoid(p::QuadCone{T, P, JuMP.Variable}) where {T, P<:AbstractPolynomial{T}} = ellipsoid(JuMP.resultvalue(p))

function _HPH(D, d, δ, H)
    P = [δ d'
         d D]
    HPH = H * P * H
end
_HPH(p::CenterQuadCone) = _HPH(p.Q, zeros(size(p.Q, 1)), -1., p.H)
_HPH(p::InteriorQuadCone) = _HPH(p.Q, p.b, p.β, p.H)
function ellipsoid(p::QuadCone)
    LiftedEllipsoid(inv(_HPH(p)))
end
