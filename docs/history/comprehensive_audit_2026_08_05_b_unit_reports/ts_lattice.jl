@testset "PIC green_type=:lattice" begin
    # The lattice Green function inverts the five-point discrete Laplacian exactly
    # instead of discretizing the continuum -ln r. Derivation and measurements:
    # docs/theory/pic_free_space_kernels.md Section 3.4.
    nx = ny = 32

    # (a) the kernel must reproduce -ln r away from the origin, with the additive
    #     gauge constant C = gamma + (3/2)ln2 for the isotropic lattice
    tab = Octopus._pic_lattice_green_table(nx, ny, 1.0)
    at(m) = tab[m + 2nx + 1, 2ny + 1]
    C = -at(8) - log(8.0)
    @test isapprox(C, 0.5772156649015329 + 1.5 * log(2.0); atol=2e-3)
    for m in (12, 16)
        @test isapprox(at(m), -(log(m) + C); atol=5e-3)
    end
    # nearest neighbour is the exact lattice value 1/4 (in the 2pi convention)
    @test isapprox(abs(at(1)), pi / 2; rtol=1e-5)

    # (b) it depends only on the aspect ratio, not the absolute spacing -- this is
    #     what makes one cached table serve every slice pair
    g1 = Matrix{Float64}(undef, 2nx, 2ny)
    g2 = Matrix{Float64}(undef, 2nx, 2ny)
    Octopus._pic_green_lattice!(g1, 0.0, 0.0, 0.0, 0.0, 1.0e-4, 5.0e-5, nx, ny)
    Octopus._pic_green_lattice!(g2, 0.0, 0.0, 0.0, 0.0, 2.0e-4, 1.0e-4, nx, ny)
    @test g1 == g2                       # same rho => same table, exactly

    # (c) reaches its runtime consumer: a different kernel must change the answer
    sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
    mk() = begin
        set_global_rng!(seed=91, method=:philox)
        e = Beam(3000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.7),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(3000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.9),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        (e, p)
    end
    run(gt) = begin
        e, p = mk()
        l = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=gt), e, p, CPUThreadsBackend)
        (l, vcat(coordinate_arrays(e)...))
    end
    l_int, c_int = run(:integrated)
    l_lat, c_lat = run(:lattice)
    @test all(isfinite, c_lat) && isfinite(l_lat)
    @test c_int != c_lat                                   # reaches the consumer
    @test isapprox(l_lat, l_int; rtol=1e-3)                # same physics

    # (d) rejected cleanly rather than silently ignored
    @test_throws ArgumentError PICPoissonSolver(green_type=:bogus)

    # (d2) the EXPERIMENTAL label is part of the contract with users: :lattice is
    #      1.74x slower and ~645 MB at grid 128, so the option metadata (which
    #      solver_help renders) must keep saying so.
    @test occursin("EXPERIMENTAL", solver_option_schema(PICPoissonSolver).green_type.meaning)

    # (e) CPU/CUDA parity on every execution route
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        mkp(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(3000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(3000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        for kw in (NamedTuple(), (green_cache=:none,), (cuda_indexed_wavefront=false,),
                   (cuda_wavefront_fft=false,), (batch_mode=:sequential,))
            # The CPU reference must use the SAME options: green_cache and batch_mode
            # change the grid on both backends, so a fixed-default reference would be
            # comparing two different configurations.
            e0, p0 = mkp(CPUThreadsBackend)
            collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=:lattice, kw...),
                     e0, p0, CPUThreadsBackend)
            ref = flat(e0)
            e2, p2 = mkp(CUDAExecutionPolicy())
            collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=:lattice, kw...),
                     e2, p2, CUDABackend)
            @test maximum(abs.(flat(e2) .- ref)) < 1e-13
        end
    end
end
