@testset "CUDA PIC parity across every execution route" begin
    # Two bugs found by sweeping the option space rather than by reading:
    #
    # 1. green_cache=:slice_pair (the DEFAULT) was applied by only two of the five
    #    CUDA interaction routes. batch_mode=:sequential, cuda_batch_fft=false and
    #    cuda_wavefront_fft=false solved on the unexpanded grid while the CPU
    #    expanded by 1+slice_pair_green_growth, giving 4.7e-6 coordinate error.
    #
    # 2. The luminosity was computed asynchronously but consumed AFTER the kicks,
    #    which rewrite the slice coordinates in place. It is a data dependency, not
    #    a completion wait. _cuda_pic_interaction_pair_batched_fft! reached the
    #    kicks fastest and read post-kick coordinates, giving a deterministic
    #    1.8e-4 luminosity error; the other routes were correct only by timing.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        mk(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(5000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(5000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        run_cuda(; kw...) = begin
            e, p = mk(CUDAExecutionPolicy())
            l = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CUDABackend)
            (l, flat(e))
        end
        e0, p0 = mk(CPUThreadsBackend)
        lum_cpu = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64)), e0, p0, CPUThreadsBackend)
        ref = flat(e0)

        # every CUDA execution route, all at the default green_cache=:slice_pair
        routes = (
            NamedTuple(),
            (cuda_indexed_wavefront=false,),
            (cuda_wavefront_fft=false,),
            (cuda_batch_fft=false,),
            (cuda_async=false,),
            (batch_mode=:sequential,),
        )
        for kw in routes
            l, c = run_cuda(; kw...)
            @test maximum(abs.(c .- ref)) < 1e-13          # bug 1
            @test isapprox(l, lum_cpu; rtol=1e-11)         # bug 2
        end
    else
        @test_skip "CUDA device not available"
    end
end
