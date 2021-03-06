export permanent, veroneselift

using Combinatorics

function permanent(A)
    n = LinAlg.checksquare(A)
    sum(σ -> prod(i -> A[i,σ[i]], 1:n), permutations(1:n))
end

function μ(combi)
    prod = 1
    last = 0
    cur = 1
    for i in combi
        if i == last
            cur += 1
        else
            prod *= factorial(cur)
            last = i
            cur = 1
        end
    end
    prod *= factorial(cur)
end

function veroneselift(A::AbstractMatrix, d::Integer)
    d > 0 || throw(ArgumentError("d should be a positive integer"))

    n = LinAlg.checksquare(A)
    N = binomial(n+d-1, d)

    Ad = Matrix{Float64}(N, N)

    for (i,α) in enumerate(with_replacement_combinations(1:n, d))
        for (j,β) in enumerate(with_replacement_combinations(1:n, d))
            Ad[i, j] = permanent(A[α, β]) / sqrt(μ(α) * μ(β))
        end
    end

    Ad
end
