# TODO

## 1. Reuse PIC Density Grids for Luminosity

Goal: replace the independent common-grid luminosity deposition with a
validated overlap between the two PIC density grids. This uses a luminosity
overlap/transfer kernel, not the Poisson Green function.

1. Document and benchmark the current centroid-plane common-grid algorithm.
   Compare centered, offset, unequal, round, and flat Gaussian beams with the
   analytic overlap while sweeping resolution, padding, separation, aspect
   ratio, slices, and macroparticles.
2. Derive the CIC cross-grid overlap
   `L = sum(q1[i] * G_lum[i,j] * q2[j], i, j)` for different origins and cell
   sizes. Use compact support to implement a sparse/local transfer; treat TSC
   separately.
3. Add one centroid-plane deposition per beam and slice pair to the batched PIC
   stage. Reuse particle indices, valid bounds, workspaces, and scheduling, but
   keep these densities separate from the four endpoint force planes.
4. Apply `G_lum` between the centroid-plane grids. Do not infer exact
   centroid-plane density by interpolating endpoint grids; evaluate that only
   as a separately labeled approximation.
5. Validate every slice-pair contribution and total luminosity against both the
   existing method and analytic Gaussian results on CPU and CUDA.
6. Benchmark deposition, transfer-kernel construction/cache, and overlap cost.
   Cache keys must include both grid origins, spacings, dimensions, and basis.
7. Review WarpX collider luminosity diagnostics and beam-beam implementation:
   <https://warpx.readthedocs.io/en/26.07/usage/parameters.html> and
   <https://arxiv.org/abs/2405.09583>.

Do not change the Poisson Green function or force calculation in this task.
