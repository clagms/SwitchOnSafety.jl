export pradius, pradiusb

function pradiusk(As, p, k, pnorm)
    mean(map(A->norm(A, pnorm)^p, As))^(1/(p*k))
end

function checkeven(p, algo::Type{Val{A}}) where A
    if !iseven(p)
        throw(ArgumentError("Odd p is not supported yet for pradius computation with $A algorithm"))
    end
end

function pradius(s::DiscreteSwitchedLinearSystem, p, lift::Function; pnorm=Inf, ɛ=1e-2, forceub=false)
    ρpmpp = ρ(sum((rm -> lift(rm.A, p)).(s.resetmaps)))
    if forceub
        ρpmpp^(1/p)
    else
        (ρpmpp / ρA(s))^(1/p)
    end
end

function kozyakinlift(s, t, A)
    kron(sparse([source(s, t)], [target(s, t)], [1]), A[symbol(s, t)])
end
function pradius(s::ConstrainedDiscreteSwitchedLinearSystem, p, lift::Function; pnorm=Inf, ɛ=1e-2, forceub=false)
    Alifted = (A -> lift(A, p)).(s.resetmaps)
    ρpmpp = ρ(sum(kozyakinlift(s, t, Alifted) for t in transitions(s)))
    if forceub
        ρpmpp^(1/p)
    else
        (ρpmpp / ρA(s))^(1/p)
    end
end

function pradius(s::AbstractDiscreteSwitchedSystem, p, algo::Type{Val{:VeroneseLift}}; pnorm=Inf, ɛ=1e-2, forceub=false)
    checkeven(p, algo)
    pradius(s, p, veroneselift, pnorm=pnorm, ɛ=ɛ, forceub=forceub)
end
kroneckerlift(A::AbstractMatrix, p::Integer) = kronpow(veroneselift(A, 2), div(p, 2))
function pradius(s::AbstractDiscreteSwitchedSystem, p, algo::Type{Val{:KroneckerLift}}; pnorm=Inf, ɛ=1e-2, forceub=false)
    checkeven(p, algo)
    pradius(s, p, kroneckerlift, pnorm=pnorm, ɛ=ɛ, forceub=forceub)
end

function pradius(s::DiscreteSwitchedLinearSystem, p, algo::Type{Val{:BruteForce}}; pnorm=Inf, ɛ=1e-2, forceub=false)
    As = map(rm -> rm.A, s.resetmaps)
    Ascur = As
    ρp = Float64[]
    m = ntransitions(s)
    k = 0
    while k < 2 || !isapprox(ρp[end-1], ρp[end], rtol=ɛ)
        k += 1
        l = length(Ascur)
        Asnew = similar(Ascur, l * m)
        for (i,A) in enumerate(As)
            for (j,B) in enumerate(Ascur)
                Asnew[(i-1)*l+j] = A*B
            end
        end
        Ascur = Asnew
        push!(ρp, pradiusk(Ascur, p, k, pnorm))
    end
    if forceub
        ρp[end] * length(As)^(1/p)
    else
        ρp[end]
    end
end

# The Inf- and 1-norm of a matrices are easier to compute than the 2-norm
function pradius(s::AbstractDiscreteSwitchedSystem, p, algo::Symbol=:VeroneseLift; pnorm=Inf, ɛ=1e-2, forceub=false)
    pradius(s, p, Val{algo}, pnorm=pnorm, ɛ=ɛ, forceub=forceub)
end

function pradiusb(s::DiscreteSwitchedLinearSystem, p, algo::Symbol=:VeroneseLift)
    @assert algo in [:VeroneseLift, :KroneckerLift] "p-radius algo needs to be exact to compute bounds on JSR"
    ρpmp = pradius(s, p, algo, forceub=true)
    ρp = ρpmp / ρA(s)^(1/p)
    updateb!(s, ρp, ρpmp)
end
