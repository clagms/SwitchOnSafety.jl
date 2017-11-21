using LightGraphs
export sosextractcycle, extractatomic

#function dist(X, Y)
#    maximum(x -> abs(x[1] - x[2]) / max(x[1], x[2]), zip(X, Y))
#end

function findapprox(a, x, tol)
    _a(i) = dot(a[i][1], x)
    for i in eachindex(a)
        #if dist # isapprox(a[i][1], x, rtol=tol) # rtol is too restrictive since [0.999, 0.001] should be the same as [0.999, 0.002] but rtol says no
        if isapprox(_a(i), 1., rtol=tol)
            return i
        end
    end
    return 0
end

function pushapprox!(a, x, id, tol)
    i = findapprox(a, x, tol)
    if iszero(i)
        push!(a, (x, id))
        id
    else
        a[i][2]
    end
end

function extractatomic(s::AbstractDiscreteSwitchedSystem, d, t, ranktol, dual=getlyap(s, d).dual)
    σ = symbol(s, t)
    μ = measurefor(dual, s, t)
    X = monomials(variables(μ), d)
    ν = matmeasure(μ, X)
    extractatoms(ν, ranktol)
end

function extractstates(args...)
    atoms = extractatomic(args...)
    if isnull(atoms)
        Vector{Float64}[]
    else
        get(atoms).support
    end
end

function startstates(s::AbstractDiscreteSwitchedSystem, edgestates, G, B, disttol)
    a = Tuple{Vector{Float64}, Int}[]
    for (t, states) in edgestates
        for x in states
            x /= norm(x)
            i = pushapprox!(a, x, length(G)+1, disttol)
            σ = symbol(s, t)
            if i == length(G)+1
                push!(G, [(σ, t)])
                push!(B, x)
            else
                push!(G[i], (σ, t))
            end
        end
    end
    a
end

# Atom extraction
function sosextractcycle(s::AbstractDiscreteSwitchedSystem, dual, d::Integer; ranktols=1e-5, disttols=1e-5)
    smp = Nullable{periodicswitchingtype(s)}(nothing)
    for ranktol in ranktols
        # This part is the more costly since it does atom extraction
        # It is run only once for each disttols which is nice
        edgestates = map(u -> map(t -> (t, extractstates(s, d, t, ranktol, dual)), out_transitions(s, u)), states(s))

        for disttol in disttols
            G = Vector{Tuple{Int, transitiontype(s)}}[] # G[u] = list of edges (σ, v) going out of u
            B = Vector{Float64}[] # B[u] = values of the state at node u
            GB = map(u -> startstates(s, edgestates[u], G, B, disttol), states(s))

            # Try grouping with different distances

            g = DiGraph(length(G))
            w = fill(Inf, nv(g), nv(g))
            ij2t = Dict{NTuple{2, Int}, transitiontype(s)}()
            for u in eachindex(G)
                x = B[u]
                for (σ, t) in G[u]
                    y = dynamicforσ(s, σ) * x
                    λ = norm(y)
                    y /= λ
                    j = findapprox(GB[target(s, t)], y, disttol)
                    if !iszero(j)
                        v = GB[target(s, t)][j][2]
                        add_edge!(g, u, v)
                        # we use a minimum cycle arithmetic mean algo but we need the maximum cycle geometric mean
                        w[u, v] = -log(λ)
                        ij2t[(u, v)] = t
                    end
                end
            end

            c, λmin = karp_minimum_cycle_mean(g, w)

            if !isempty(c)
                period = map(i -> ij2t[(c[i], c[(i % length(c)) + 1])], eachindex(c))

                newsmp = periodicswitching(s, period)
                notifyperiodic!(s, newsmp)
                if isnull(smp) || isbetter(newsmp, get(smp))
                    smp = Nullable{periodicswitchingtype(s)}(newsmp)
                end
            end
        end
    end

    if !isnull(smp)
        updatesmp!(s, get(smp))
    end

    smp
end
function sosextractcycle(s::AbstractDiscreteSwitchedSystem, d::Integer; solver=()->nothing, tol=1e-5, ranktols=tol, disttols=tol)::Nullable{periodicswitchingtype(s)}
    lyap = getlyap(s, d; solver=solver, tol=tol)
    sosextractcycle(s, lyap.dual, d; ranktols=ranktols, disttols=disttols)
end
