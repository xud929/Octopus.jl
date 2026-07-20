# TODO

## 1. Complete 2D PIC CUDA Optimization

Goal: improve target-size strong-strong PIC throughput without changing
particle identity or weakening physics validation.

Reference case:

- CUDA `Float64`, CIC, `(128,128)` grid, `15x15` slice pairs.
- 2,560,000 electron and 1,000,000 proton macroparticles.
- 30 turns; compare the final-ten mean across at least three runs.
- Fixed cache settings: `slice_pair_green_min_ratio=0.50` and
  `slice_pair_green_growth=0.25`.
- Fast path: wavefront scheduling, asynchronous/batched FFT fields,
  slice-pair Green cache, and indexed wavefront tracking.

Remaining work:

1. Revisit the indexed longitudinal kick after Nsight Compute counters become
   available. Removing its redundant grid-stride loop reduced allocation from
   150 to 134 registers/thread and improved complete-turn time by 1.6%, but it
   remains the hottest individual kernel.
2. Investigate launch/synchronization reduction or CUDA Graph capture for the
   stable wavefront shape, including graph-update cost when cached grids change.
3. Revisit spatial binning only with a linear-time histogram/prefix builder and
   tiled/shared-memory deposition as one measured design. GPU comparison-sort
   index lists were rejected for `1x1`, `2x2`, and `4x4` bins because total-turn
   time more than doubled. Keep canonical particle arrays and IDs unchanged.
4. Test physical SoA sorting only if the combined linear-time bin/tile design is
   still insufficient. Keep immutable particle IDs and include sorting cost.
5. Choose later kernel fusion, launch tuning, FFT, or overlap work
   strictly from the latest profile.
6. Finish with the target-size 30-turn benchmark, backend contract, identity
   checks, and a longer physics regression.

Acceptance gates:

- Change one optimization variable at a time and retain only total-turn gains.
- Use complete-turn timing for throughput; detailed synchronized phase timing
  is diagnostic only.
- Preserve `StrongStrongPICBackendConsistencyContract` and compare coordinates,
  luminosity, RMS moments, slice populations, losses, and cache history.
- Never key diagnostics, stochastic behavior, or comparisons by mutable storage
  position.
- Record hardware/software versions, commit, solver/task settings, individual
  final-ten samples, memory use, and validation residuals.

Current accepted result: indexed wavefront, the simplified kick kernel, and
fused source/field bounds reductions reduced the corrected target-case median
final-ten mean from `0.6462` to `0.3157 s/turn` (51.1%, 2.05x). The latest
30-turn backend contract passed with maximum coordinate error `7.20e-16`,
luminosity relative error `1.55e-14`, and identical cache history.

The 2026-07-20 Nsight Systems profile is recorded in
`validation/strong_strong_pic_extreme_benchmark_history.md`. Nsight Compute
hardware counters remain permission-gated on the benchmark host
(`ERR_NVGPUCTRPERM`); do not infer measured bandwidth, atomic contention, or
achieved occupancy from that run.

Do not use results from commit `1f8a513`: that path had an incorrect no-observer
lattice block and a missing PIC scatter stream-completion boundary. Growth
values `0.50`, `0.625`, and `0.75` were rejected; `0.50` was faster but did not
meet the physical-domain requirement.

## 2. Reuse PIC Density Grids for Luminosity

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
