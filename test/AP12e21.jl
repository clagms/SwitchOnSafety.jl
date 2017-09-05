# Example 2.1 of
# A. Ahmadi, and P. Parrilo
# "Joint spectral radius of rank one matrices and the maximum cycle mean problem."
# CDC, 731-733, 2012.
# The JSR is 1

@testset "[AP12] Example 2.1" begin
    for solver in sdp_solvers
        println("  > With solver $(typeof(solver))")
        tol = 1e-4
        for d in 1:3
            # Get a fresh system to discard lyapunovs, smp and sets lb to 0
            s = DiscreteSwitchedSystem([[0 1; 0 0], [0 0; 1 0]])
            smp = DiscretePeriodicSwitching(s, [1, 2])
            @test smp.growthrate == 1

            lb, ub = soslyapb(s, d, solver=solver, tol=tol)
            @test lb ≈ 1 / 2^(1/(2*d)) rtol=tol
            @test ub ≈ 1 rtol=tol

            @test s.lb == 1.
            @test !isnull(s.smp)
            @test get(s.smp) == smp

            cyc = sosextractcycle(s, d)
            @test !isnull(cyc)
            @test get(cyc) == smp

            seq = sosbuildsequence(s, d, p_0=:Primal)
            psw = findsmp(seq)
            @test !isnull(psw)
            @test get(psw).growthrate == 1
        end
    end
end
