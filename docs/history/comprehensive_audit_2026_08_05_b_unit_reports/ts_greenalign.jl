@testset "Green-cache expansion preserves the grid alignment its kernels require" begin
    # `_pic_expand_grid_by` scales `width` with the node count fixed, so the cell
    # size grows while the origin separation does not: an exact k-cell separation
    # became k/(1+growth) cells. `:lattice` is tabulated by INTEGER separation and
    # `_pic_green_lattice!` rounded silently, so the cached Green function was that
    # of a source displaced by the residual -- measured 0.400 cells at the default
    # growth of 0.25, on both CPU and CUDA, which is why the parity test agreed.
    nx = ny = 64
    seps(s, sg, fg) = begin
        hx = sg.width / (nx - 1); hy = sg.height / (ny - 1)
        ((fg.x0 - sg.x0) / hx, (fg.y0 - sg.y0) / hy)
    end
    frac(v) = abs(v - round(v))

    for gt in (:lattice, :standard, :integrated)
        s = PICPoissonSolver(; grid=(nx, ny), green_type=gt)
        sg, fg = Octopus._pic_interaction_grids(s, -3.0e-4, 2.5e-4, -2.0e-5, 3.0e-5,
                                                   -1.0e-4, 4.0e-4, -4.0e-5, 1.0e-5)
        dx0, dy0 = seps(s, sg, fg)
        # what _pic_interaction_grids guarantees: integer for :lattice/:integrated,
        # a deliberate half cell for :standard
        want = gt === :standard ? 0.5 : 0.0
        @test frac(dx0 - want) < 1e-9
        @test frac(dy0 - want) < 1e-9

        sgE = Octopus._pic_expand_grid_by(sg, 1.25)
        fgE = Octopus._pic_expand_grid_by(fg, 1.25)
        # the expansion on its own destroys it -- this is the defect, kept as the
        # negative control so the test below cannot pass vacuously
        dxE, _ = seps(s, sgE, fgE)
        @test frac(dxE - want) > 0.1

        sgA, fgA = Octopus._pic_realign_expanded_grids(gt, sgE, fgE, nx, ny)
        dxA, dyA = seps(s, sgA, fgA)
        if gt === :integrated
            # deliberately untouched: its kernel is evaluated at real coordinates,
            # and moving the default mesh would change results that carry no defect
            @test (sgA.x0, fgA.x0) == (sgE.x0, fgE.x0)
        else
            @test frac(dxA - want) < 1e-9
            @test frac(dyA - want) < 1e-9
        end
    end

    # `_pic_green_lattice!` now refuses a fractional separation instead of rounding
    let s = PICPoissonSolver(; grid=(nx, ny), green_type=:lattice)
        sg, fg = Octopus._pic_interaction_grids(s, -3.0e-4, 2.5e-4, -2.0e-5, 3.0e-5,
                                                   -1.0e-4, 4.0e-4, -4.0e-5, 1.0e-5)
        hx = sg.width / (nx - 1); hy = sg.height / (ny - 1)
        g = Matrix{Float64}(undef, 2nx, 2ny)
        @test Octopus._pic_green_lattice!(g, fg.x0, fg.y0, sg.x0, sg.y0, hx, hy, nx, ny) === g
        @test_throws ArgumentError Octopus._pic_green_lattice!(
            g, fg.x0 + 0.4 * hx, fg.y0, sg.x0, sg.y0, hx, hy, nx, ny)
    end

    # end to end: the combination that carried the defect is the DEFAULT cache
    sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
    mk() = begin
        set_global_rng!(seed=91, method=:philox)
        e = Beam(2000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.7),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(2000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.9),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        (e, p)
    end
    for gt in (:lattice, :standard, :integrated)
        e, p = mk()
        l = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=gt,
                                        green_cache=:slice_pair), e, p, CPUThreadsBackend)
        @test isfinite(l) && all(isfinite, vcat(coordinate_arrays(e)...))
    end
end
