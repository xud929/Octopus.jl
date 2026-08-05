using Test, Octopus, LinearAlgebra
println("CUDA functional = ", Octopus._HAS_CUDA && Octopus.CUDA.functional())
@testset "Lattice cells track and stay symplectic" begin
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    track(cell, u) = foldl((c, e) -> e(c...), cell; init=u)
    function jac(cell, u0)
        J = zeros(6, 6)
        for j in 1:6
            u = ComplexF64[u0...]
            u[j] += 1e-30im
            J[:, j] = imag.(collect(track(cell, Tuple(u)))) ./ 1e-30
        end
        return J
    end
    q(k, L=0.3) = compile_runtime(QuadrupoleSpec(L=L, kn=(0.0, k), nst=4, integrator_order=4))
    d(L) = compile_runtime(DriftSpec(L=L))
    b(L, ang) = compile_runtime(SBendSpec(L=L, h=ang / L, b0=ang / L, nst=4, integrator_order=4))
    sx(k2) = compile_runtime(SextupoleSpec(L=0.2, kn=(0.0, 0.0, k2), nst=4, integrator_order=4))

    fodo = (q(1.6), d(1.2), q(-1.6), d(1.2))
    dba = (q(-1.1, 0.25), d(0.6), b(1.0, 0.20), d(0.6), q(1.5, 0.35),
           d(0.6), b(1.0, 0.20), d(0.6), q(-1.1, 0.25))
    tba = (q(-1.0, 0.25), d(0.5), b(0.9, 0.14), d(0.5), q(0.9), d(0.5), b(0.9, 0.14),
           d(0.5), q(0.9), d(0.5), b(0.9, 0.14), d(0.5), q(-1.0, 0.25))

    u0 = (1.0e-4, 2.0e-5, -0.8e-4, -1.5e-5, 0.0, 0.0)
    for (name, cell) in (("FODO", fodo), ("DBA", dba), ("TBA", tba),
                         ("FODO+sext", (fodo..., sx(8.0))),
                         ("DBA+sext", (dba..., sx(8.0))),
                         ("TBA+sext", (tba..., sx(8.0))))
        J = jac(cell, u0)
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-12
        # Linearly stable in both planes, i.e. a usable cell rather than an
        # arbitrary sequence of elements.
        @test abs(J[1, 1] + J[2, 2]) < 2
        @test abs(J[3, 3] + J[4, 4]) < 2
        # Bounded over many turns.
        u = u0
        for _ in 1:200
            u = track(cell, u)
        end
        @test all(isfinite, u)
        @test maximum(abs, collect(u)[1:4]) < 1.0e-2
    end

    # Composed lines must be backend-consistent, not just single elements.
    for (name, cell) in (("FODO", fodo), ("DBA+sext", (dba..., sx(8.0))))
        r = validate(ElementTrackingBackendConsistencyContract(;
            line=cell, n_particles=512, turns=2,
            backend_a=CPUThreadsBackend, backend_b=CPUThreadsBackend,
            atol=1.0e-12, rtol=1.0e-12))
        @test passed(r)
        gpu = validate(ElementTrackingBackendConsistencyContract(;
            line=cell, n_particles=512, turns=2,
            backend_a=CPUThreadsBackend, backend_b=CUDABackend,
            atol=1.0e-10, rtol=1.0e-10))
        @test gpu.status in (:passed, :skipped)
    end

    # A counter-RNG element must COMPILE in the fused CUDA kernel. Every
    # stochastic draw funnels through octopus_uint64, whose unknown-method
    # throw as first written (2026-08-05 hygiene sweep, U15-4) interpolated
    # the code into the message — a heap string, invalid device IR — so any
    # line containing a stochastic element failed cuda_track_kernel!
    # compilation outright, and nothing here tracked one to notice. Caught by
    # the U21-5 validation-line extension; the message is static now, and
    # this pins the whole class: compile, run, and agree with the CPU.
    lumped = LumpedRadSpec{Float64}(;
        damping_turns=(4000.0, 4000.0, 2000.0), beta=(0.8, 0.072, 90.0),
        alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), rng_id=103)
    stochastic_gpu = validate(ElementTrackingBackendConsistencyContract(;
        line=(lumped,), n_particles=256, turns=2,
        backend_a=CPUThreadsBackend, backend_b=CUDABackend,
        atol=1.0e-10, rtol=1.0e-10))
    @test stochastic_gpu.status in (:passed, :skipped)
end
