@testset "CUDA GaussianPIC coupled subtraction matches CPU" begin
    # The coupled branch is implemented on the CPU path and on the default CUDA
    # indexed-wavefront route. This testset uses green_cache=:none; the
    # slice-pair cache is covered separately by "CUDA GaussianPIC honours
    # green_cache=:slice_pair" below.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        mk(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(8000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(8000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        for lk in (true, false), tol in (Inf, 0.0)
            solver() = GaussianPICPoissonSolver(slicing=sl, grid=(64, 64), green_cache=:none,
                                                coupling_tol=tol, longitudinal_kick=lk)
            ec, pc = mk(CPUThreadsBackend); lc = collide!(solver(), ec, pc, CPUThreadsBackend)
            eg, pg = mk(CUDAExecutionPolicy()); lg = collide!(solver(), eg, pg, CUDABackend)
            @test isapprox(flat(ec), flat(eg); rtol=1e-10, atol=1e-14)
            @test isapprox(flat(pc), flat(pg); rtol=1e-10, atol=1e-14)
            @test isapprox(lc, lg; rtol=1e-10)
        end
        # a finite coupling_tol must actually change the CUDA result
        sl2 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        eu, pu = mk(CUDAExecutionPolicy())
        collide!(GaussianPICPoissonSolver(slicing=sl2, grid=(64,64), green_cache=:none,
                                          coupling_tol=Inf), eu, pu, CUDABackend)
        ecp, pcp = mk(CUDAExecutionPolicy())
        collide!(GaussianPICPoissonSolver(slicing=sl2, grid=(64,64), green_cache=:none,
                                          coupling_tol=0.0), ecp, pcp, CUDABackend)
        @test flat(eu) != flat(ecp)
        # the two CUDA routes that do not implement coupling must refuse, not ignore
        eb, pb = mk(CUDAExecutionPolicy())
        @test_throws ArgumentError collide!(
            GaussianPICPoissonSolver(slicing=sl2, grid=(64,64), coupling_tol=0.0,
                                     cuda_indexed_wavefront=false), eb, pb, CUDABackend)
    end
end
