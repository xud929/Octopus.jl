@testset "CUDA GaussianPIC emits PIC phase timing records" begin
    # Regression: pic_timing=true produced an empty pic_phase_timings for
    # GaussianPIC, because its CUDA routes never built a timing object and
    # passed `nothing` down every shared PIC helper. Plain PIC always worked.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
        build(solver) = begin
            set_global_rng!(seed=7, method=:philox)
            be = Beam(4000, CUDAExecutionPolicy(), Float64; beta=(0.55, 0.056, 12.7),
                alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
                rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            bp = Beam(4000, CUDAExecutionPolicy(), Float64; beta=(0.8, 0.072, 90.9),
                alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
                rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            L6(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                             alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
            ip = StrongStrongCollision(:ip; poisson_solver=solver)
            task = StrongStrongTask((ip, L6((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))),
                                    (ip, L6((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)));
                                    diagnostics=StrongStrongDiagnostics(pic_timing=true))
            (be, bp, task)
        end

        be, bp, task = build(GaussianPICPoissonSolver(; slicing=sl, grid=(32, 32)))
        execute!(task, be, bp; turns=1)
        rec = pic_phase_timings(task)
        @test !isempty(rec)                                   # the actual regression
        r = rec[end]
        @test r.measured_total > 0
        @test r.interaction > 0
        # the two GaussianPIC-specific phases must be populated, not just present
        @test r.gpic_moments > 0
        @test r.gpic_profiles > 0
        # they are nested inside :interaction and must not inflate the total
        @test r.measured_total >= r.interaction

        # plain PIC still works and leaves the GaussianPIC-only counters at zero
        be2, bp2, task2 = build(PICPoissonSolver(; slicing=sl, grid=(32, 32)))
        execute!(task2, be2, bp2; turns=1)
        rec2 = pic_phase_timings(task2)
        @test !isempty(rec2)
        @test rec2[end].gpic_moments == 0
        @test rec2[end].gpic_profiles == 0
    else
        @test_skip "CUDA device not available"
    end
end
