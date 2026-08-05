@testset "CUDA GaussianPIC honours green_cache=:slice_pair" begin
    # Regression. GaussianPIC's three CUDA routes used to ignore green_cache
    # entirely: only the CPU expanded each slice-pair grid by
    # (1 + slice_pair_green_growth), so the two backends solved on different
    # (both valid) grids and agreed only to ~3e-6 at the DEFAULT settings --
    # green_cache=:slice_pair is the default. Diagnosed by setting growth=0.0,
    # which made the CPU expansion a no-op and restored 5e-17 parity, proving the
    # discrepancy was the missing expansion and not floating-point drift.
    #
    # The cache must be applied AFTER _cuda_gpic_augment_prep, which recomputes
    # the grid from the margin-enlarged source bounds; caching before it would be
    # silently discarded.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
        mk(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(6000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(6000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        run_both(; kw...) = begin
            e1, p1 = mk(CPUThreadsBackend)
            l1 = collide!(GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e1, p1, CPUThreadsBackend)
            e2, p2 = mk(CUDAExecutionPolicy())
            l2 = collide!(GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e2, p2, CUDABackend)
            d = max(maximum(abs.(flat(e1) .- flat(e2))), maximum(abs.(flat(p1) .- flat(p2))))
            (d, l1, l2, flat(e2))
        end

        # all three CUDA routes, at the default green_cache
        d_idx, l1, l2, cu_default = run_both()
        @test d_idx < 1e-14
        @test isapprox(l1, l2; rtol=1e-12)

        d_noidx, _, _, _ = run_both(cuda_indexed_wavefront=false)
        @test d_noidx < 1e-14

        # also a regression for the sequential route calling the field kernel with
        # the pre-field_derivative arity, which made it fail to compile at all
        d_seq, _, _, _ = run_both(batch_mode=:sequential)
        @test d_seq < 1e-14

        # coupled branch on top of the cache
        d_cp, _, _, _ = run_both(coupling_tol=0.0)
        @test d_cp < 1e-14

        # effectiveness: the growth factor must reach its CUDA consumer, i.e. a
        # different expansion must produce a different (still valid) answer, and
        # growth=0 must reproduce the uncached grid.
        _, _, _, cu_growth = run_both(slice_pair_green_growth=0.75)
        @test cu_default != cu_growth
        _, _, _, cu_zero = run_both(slice_pair_green_growth=0.0)
        _, _, _, cu_none = run_both(green_cache=:none)
        # Not bitwise: with the cache enabled the Green FFT comes from the
        # per-pair cached builder, with :none from the fused batched build inside
        # the solve, so they differ in the last ulp. The GRID is what must match,
        # and a wrong grid shows up at ~1e-3 relative (that was the original bug).
        @test maximum(abs.(cu_zero .- cu_none)) <= 1e-13 * maximum(abs, cu_none)
    else
        @test_skip "CUDA device not available"
    end
end
