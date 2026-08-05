@testset "grid_extent is rejected, not ignored, where no estimator runs" begin
    # `grid_extent` is consumed by `_pic_axis_extent`, which only the per-slice-pair
    # sizing path calls. `:source_slice` sizes from `_pic_union_bounds` and `:node`
    # from `_pic_build_node_grids!`, both plain min/max -- so a non-default value was
    # accepted and produced BIT-IDENTICAL results. Same class as the hybrid solver's
    # dropped `grid_extent` (audit part 2 S8), and rejected the same way.
    for ig in (:node, :source_slice)
        @test_throws ArgumentError PICPoissonSolver(interaction_grid=ig, grid_extent=:sigma)
        @test PICPoissonSolver(interaction_grid=ig).grid_extent === :extrema
        @test PICPoissonSolver(interaction_grid=ig, grid_extent=:extrema).interaction_grid === ig
    end
    # the mode that DOES read it keeps working -- otherwise the check above would
    # pass by forbidding the option outright
    @test PICPoissonSolver(interaction_grid=:slice_pair, grid_extent=:sigma).grid_extent === :sigma
end
