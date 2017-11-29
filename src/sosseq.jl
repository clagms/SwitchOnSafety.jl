function candidates(s::AbstractDiscreteSwitchedSystem, l, curstate)
    switchings(s, l, curstate, false)
end
#function candidates(s::AbstractContinuousSwitchedSystem, l, curstate)
#    modes(s, curstate, false)
#end

function best_dynamic(s::AbstractSwitchedSystem, μs, p::AbstractPolynomial, l, curstate)
    function rating(dyn)
        soslf = soslyapforward(s, p, dyn)
        μ = measurefor(μs, dyn)
        dot(μ, soslf)
    end
    dyns = candidates(s, l, curstate)
    sdyns = start(dyns)
    if done(dyns, sdyns)
        error("$curstate does not have any incoming path of length $l.")
    else
        best_dyn, sdyns = next(dyns, sdyns)
        best = rating(best_dyn)
        while !done(dyns, sdyns)
            dyn, sdyns = next(dyns, sdyns)
            cur = rating(dyn)
            if cur > best
                best = cur
                best_dyn = dyn
            end
        end
        best_dyn
    end
end

function sosbuilditeration(s::AbstractDiscreteSwitchedSystem, seq, μs, p_k, l, Δt, curstate, iter)
    best_dyn = best_dynamic(s, μs, p_k, l, curstate)

    curstate = state(s, best_dyn.seq[1], false)
    prepend!(seq, best_dyn)
    x = variables(p_k)
    iter+l, curstate, soslyapforward(s, p_k, best_dyn)
end

#function sosbuilditeration(s::AbstractContinuousSwitchedSystem, seq, μs, p_prev, l, Δt, curstate, iter)
#    dyn = best_dynamic(s, μs, p_prev, l, curstate)
#    ub = Δt
#    x = variables(p_prev)
#    p_cur = p_prev(integratorfor(s, (dyn, ub)) * x, x)
#    best_dyn = best_dynamic(s, μs, p_cur, l, curstate)
#    if best_dyn != dyn
#        lb = 0
#        while ub-lb > 1e-5
#            mid = (lb+ub)/2
#            p_cur = p_prev(integratorfor(s, (dyn, mid)) * x, x)
#            best_dyn = best_dynamic(s, μs, p_cur, l, curstate)
#            if best_dyn == dyn
#                lb = mid
#            else
#                ub = mid
#            end
#        end
#    end
#
#    p_cur = p_prev(integratorfor(s, (dyn, ub)) * x, x)
#    if iter > 1 && dyn == seq.seq[iter-1][1] && duration(@view seq.seq[1:(iter-1)]) < 1000# && ub < 1e-3
#        seq.seq[iter-1] = (dyn, seq.seq[iter-1][2]+ub)
#    else
#        push!(seq, (dyn, ub))
#        curstate = state(s, dyn, false)
#        iter += 1
#    end
#    iter, curstate, p_cur
#end

# Extracting trajectory from Lyapunov
function sosbuildsequence(s::AbstractSwitchedSystem, d::Integer; solver=()->nothing, v_0=:Random, p_0=:Random, l::Integer=1, Δt::Float64=1., niter::Integer=42, tol=1e-5)
    lyap = getlyap(s, d; solver=solver, tol=tol)

    if v_0 == :Random
        curstate = rand(states(s))
    else
        if !(v_0 in states(s))
            throw(ArgumentError("Invalid v_0=$v_0"))
        end
        curstate = v_0
    end

    if p_0 == :Primal
        p_0 = lyap.primal[curstate]
    elseif p_0 == :Random
        Z = monomials(variables(s, curstate), d)
        p_0 = randsos(Z, monotype=:Gram, r=1)
    end # otherwise p_0 is assumed to be an sos polynomial given by the user
    p_0 = polynomial(p_0)

    p_k = p_0
    seq = switchingsequence(s, niter, curstate)

    iter = 1
    while iter <= niter
        iter, curstate, p_k = sosbuilditeration(s, seq, lyap.dual, p_k, l, Δt, curstate, iter)
        # Avoid having it go to zero
        p_k /= p_k(variables(p_k) => ones(Int, nvariables(p_k)))
    end
    @assert seq.len == length(seq.seq)
    seq
end
