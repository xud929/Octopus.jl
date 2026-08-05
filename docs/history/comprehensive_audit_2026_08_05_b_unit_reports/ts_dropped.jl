@testset "Dropped PIC charge reaches a reader" begin
    # `_PICCPUWorkspace.dropped` documented itself as "Never silent", `grid_extent`'s
    # option metadata promises out-of-range particles are "dropped and counted", and
    # validation/README.md says the count must stay at zero in production. The
    # counter was incremented in `_pic_interaction!` and read by NOTHING in the
    # repository -- the one validation script with a `dropped` column recomputes its
    # own from `_pic_axis_extent`.
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
    run(; kw...) = begin
        e, p = mk()
        collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CPUThreadsBackend)
    end
    # the default covers every particle by construction, so it must stay silent
    @test_logs run()
    @test_logs run(grid_extent=:extrema)
    # a deliberately under-covering estimator must not be silent, and the
    # count it reports must be a real one — the bare (:warn,) pin passed
    # with any message carrying any count (2026-08-05 audit, U17-8)
    dropped_logs, _ = Test.collect_test_logs() do
        run(grid_extent=:sigma, grid_extent_sigma=1.5)
    end
    dropped_warns = [l for l in dropped_logs
                     if occursin("dropped particles", string(l.message))]
    @test !isempty(dropped_warns)
    @test all(l -> l.kwargs[:dropped] isa Integer && l.kwargs[:dropped] > 0,
              dropped_warns)

    # and the count is against the MESH, not the estimator box: the mesh carries
    # 1.5 cells of margin, so a particle in the margin is interpolated, not dropped
    @test Octopus._pic_count_outside_box([0.5, 1.5, 2.5], [1.5, 1.5, 1.5],
                                         1.0, 2.0, 1.0, 2.0) == 2
    @test Octopus._pic_count_outside_box([1.0, NaN, 2.0], [1.5, 1.5, 1.5],
                                         1.0, 2.0, 1.0, 2.0) == 1
    # per PARTICLE, not per axis: a corner escapee — outside in both x and y —
    # used to increment the counter by 2 (2026-08-05 audit, U5-6)
    @test Octopus._pic_count_outside_box([5.0], [5.0], 1.0, 2.0, 1.0, 2.0) == 1
    # the drifted variant counts each source particle once, however many of the
    # sL/sR deposit planes (or axes) miss the box (2026-08-05 audit, U5-5/U5-6)
    @test Octopus._pic_count_outside_box_drifted(
        [1.5], [10.0], [1.5], [10.0], 0.1, -0.1, 1.0, 2.0, 1.0, 2.0) == 1

    # SOURCE-side drops are counted too: under grid_extent = :sigma a source
    # outlier's charge is dropped by the deposit's zero-weight branch, and that
    # used to leave dropped == 0 with ~1 particle-charge silently missing from
    # the field (2026-08-05 audit, U5-5).
    let nx = 32, ny = 32
        solver = PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, grid=(nx, ny),
                                  green_cache=:none, grid_extent=:sigma,
                                  grid_extent_sigma=2.0)
        nsrc = 4001
        sx = [i <= 2000 ? -1.0e-4 : 1.0e-4 for i in 1:4000]
        push!(sx, 3.0e-3)                        # one source outlier at ~30 sigma
        sy = [isodd(i) ? -1.0e-4 : 1.0e-4 for i in 1:nsrc]
        source = (x=sx, px=zeros(nsrc), y=sy, py=zeros(nsrc),
                  z=zeros(nsrc), pz=zeros(nsrc))
        nf = 1000
        fx = [isodd(i) ? -1.0e-4 : 1.0e-4 for i in 1:nf]
        fy = [i % 4 < 2 ? -1.0e-4 : 1.0e-4 for i in 1:nf]
        field = (x=fx, px=zeros(nf), y=fy, py=zeros(nf), z=zeros(nf), pz=zeros(nf))
        param = (weight=1.0, lb=-1.0e-3, center=0.0, rb=1.0e-3)
        ws = Octopus._pic_cpu_workspace(Float64, nx, ny)
        ws.dropped[] = 0
        Octopus._pic_interaction!(solver, source, param, field, param, 1.0e-6,
                                  ws, nothing, nothing)
        @test ws.dropped[] == 1                          # was 0
        @test isapprox(nsrc - sum(ws.charge), 1.0; atol=1e-9)  # the missing charge
    end
end
