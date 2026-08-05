@testset "Source and field grids keep equal extent, which the field derivative assumes" begin
    # `E = -grad(phi)` is differenced with a cell size taken from the SOURCE grid
    # (pic_cpu.jl `_pic_solve_drifted_field_with_green_fft!` passes
    # `source_grid.width/(nx-1)` into `_pic_field!`), while `phi` is interpolated on
    # the FIELD grid (`_pic_interpolate_kick` uses `grid.width/(nx-1)`). Those agree
    # only because `_pic_interaction_grids` returns the same width/height for both
    # grids, differing in origin alone.
    #
    # That is an unstated invariant of exactly the shape audit part 3's S14 turned
    # out to be: established by one function, silently depended on by another. And
    # it is worse than S14 in one respect -- BOTH backends take the spacing from the
    # source grid, so a divergence would make them wrong identically and CPU/CUDA
    # parity could not see it. Hence a direct test of the invariant rather than of
    # any output.
    # Deterministic sweep rather than a seeded RNG: the claim is about an
    # invariant, so exhausting the option cross-product is both reproducible and
    # more pointed than sampling. Boxes are deliberately asymmetric between the
    # source and field beams, which is the case where equal extents are least
    # obvious -- `_pic_interaction_grids` takes the max span per axis.
    boxes = (
        (-1.0e-3, 1.0e-3, -1.0e-4, 1.0e-4, -2.0e-3, 2.0e-3, -3.0e-4, 3.0e-4),
        (-3.0e-4, 2.5e-4, -2.0e-5, 3.0e-5, -1.0e-4, 4.0e-4, -4.0e-5, 1.0e-5),
        (0.0, 5.0e-3, 0.0, 1.0e-5, -5.0e-3, 0.0, -1.0e-5, 0.0),
        (-7.0e-6, 7.0e-6, -9.0e-3, 9.0e-3, -1.0e-6, 1.0e-6, -1.0e-2, 1.0e-2),
    )
    for gt in (:integrated, :standard, :lattice),
        q in (0.0, 0.125),
        mte in ((0.0, 0.0), (2.0e-3, 2.0e-4)),
        b in boxes

        s = PICPoissonSolver(; grid=(64, 64), green_type=gt,
                               grid_quantize=q, min_transverse_extent=mte)
        sxmin, sxmax, symin, symax, fxmin, fxmax, fymin, fymax = b
        sg, fg = Octopus._pic_interaction_grids(s, sxmin, sxmax, symin, symax,
                                                   fxmin, fxmax, fymin, fymax)
        # (a) as produced
        @test sg.width == fg.width
        @test sg.height == fg.height
        # (b) after the Green cache's expansion, which scales both by one factor
        es = Octopus._pic_expand_grid_by(sg, 1.25)
        ef = Octopus._pic_expand_grid_by(fg, 1.25)
        @test es.width == ef.width
        @test es.height == ef.height
        # (c) after the part-3 realignment, which must move origins only
        ra, rb = Octopus._pic_realign_expanded_grids(gt, es, ef, 64, 64)
        @test ra.width == rb.width
        @test ra.height == rb.height
        @test ra.width == es.width && rb.width == ef.width
    end
    # negative control: the equality is a real constraint, not trivially
    # true. The old form asserted sg.width != fg.width * 1.01, which only
    # excludes width == 0 (2026-08-05 audit, U17-8). The real control: the
    # two beams' raw spans genuinely differ, so equal produced widths mean
    # the shared max-span rule did the work, not identical inputs.
    let s = PICPoissonSolver(; grid=(64, 64))
        sxmin, sxmax, symin, symax = -1e-3, 1e-3, -1e-4, 1e-4
        fxmin, fxmax, fymin, fymax = -2e-3, 2e-3, -3e-4, 3e-4
        @test (sxmax - sxmin) != (fxmax - fxmin)
        @test (symax - symin) != (fymax - fymin)
        sg, fg = Octopus._pic_interaction_grids(s, sxmin, sxmax, symin, symax,
                                                   fxmin, fxmax, fymin, fymax)
        @test sg.width == fg.width
        @test sg.height == fg.height
        @test sg.width > 0 && sg.height > 0
    end
end
