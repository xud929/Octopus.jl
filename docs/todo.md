# TODO

## Spectral Sine-Series Poisson Solver

**Status (2026-07-23): production-ready 6D solver, correctness-validated against
PIC and CUDA-optimized to PIC-level throughput.** `SpectralPoissonSolver` is
implemented, registered, validated, and optimized on both CPU and CUDA. It is a
documented (commented) option in `examples/strong_strong_tracking.jl`. Recommended
CUDA production setting for the ~11:1 flat beams: **`grid=(127, 383)`,
`domain_factor=8`, `method=:grid`** (odd sizes are intentional: a grid dimension
`N` gives a DST/DCT extension `2(N+1)`, so `N=2^k-1` is FFT-optimal). At this grid
the 6D CUDA solver reaches parity with (or beats) PIC at ~1e6 particles/beam,
down from 6.05x slower at `(128,1024)/16`, with the kick matching PIC to ~1% on
both beams in x/y/z. See the optimization history for the campaign.

**Correctness note (2026-07-23):** the grid-path longitudinal `pz` kick was found
~2x too large (the on-mesh potential reconstruction carried a factor 2 relative to
the field because both shared one fitted `scale`); fixed with an explicit `1/2` in
`Phig` on CPU and CUDA. The grid `pz` kick now matches PIC to ~0.5% and grid-free
to ~1%. See the optimization history for the derivation and regression guards. In the grid solver this means both a `128x1024` interior mesh and
a `128x1024` sine-mode expansion; in `method=:grid_free`, the same option is a
direct mode-count tuple and no mesh is used. Transverse-kick headline numbers: kick matches the analytic
soft-Gaussian solver to ~0.2% (round) / ~0.4% (production flat); transverse-only
CPU 2.0 s/turn (100k/beam, 15 slices, 8 threads); transverse-only CUDA 0.62
s/turn at 2.56M/beam, ~4x faster than PIC on GPU. The default
`longitudinal_kick=true` path now applies the PIC-style synchro-beam drift and
potential-difference `pz` kick on CPU and CUDA; see the dated optimization
history for current 6D timing and solver-difference records.

References: method + measured accuracy in `docs/spectral_sine_poisson_solver.md`;
performance + validation history in
`validation/strong_strong_spectral_optimization_history.md`; reference field
implementations in `validation/spectral_poisson_field_validation.jl`. Code:
`src/tasks/strongstrong/spectral.jl` (CPU) and `spectral_cuda.jl` (CUDA).

The longitudinal synchro-beam kick and midpoint luminosity refinement are now
complete and validated against PIC. Remaining Open items are performance/accuracy
refinements.

### Open (priority order)

The full 6D map needs **four** source-boundary spectral solves per slice pair
(left/right x two directions). The CUDA 6D path has been optimized to PIC-level
throughput at production scale (see the 2026-07-23 CUDA campaign in the
optimization history: rfft DST/DCT, fused build/extract kernels, right-sized
FFT-friendly grid, drift-folded deposit). The **CPU** 6D path has not had the same
campaign and remains the top open performance item.

1. **CPU 6D performance campaign (top open item).** The CPU `longitudinal_kick=true`
   grid path never got the throughput campaign the CUDA path did. Measured baseline
   (20k/beam, 15 slices, `grid=(128,1024)/16`, 8 threads, one turn): spectral 6D
   `5.06 s/turn` vs PIC `4.23` and Gaussian `0.15` (see the 2026-07-23 6D-map entry
   in the optimization history). Concrete plan:
   - **Easy win first: adopt the smaller FFT-friendly grid.** The CUDA campaign
     showed `(128,1024)/16` is heavily over-resolved; `(127,383)/domain_factor=8`
     matches PIC to ~1% on both beams in x/y/z. That is ~2.7x fewer transform points
     in the thin direction and should transfer directly to CPU (FFTW `r2r` cost
     scales with the transform length, and `2(N+1)` is a power of two at
     `N=2^k-1`). Re-benchmark CPU 6D at `(127,383)/8` before anything deeper.
   - Then profile complete 6D turns and attack the dominant costs (deposit, the
     four `r2r` transforms/mode-multiplies per pair, interpolation/scatter,
     luminosity, worker sync, allocation). Note the CPU path already uses FFTW `r2r`
     RODFT00 (a real DST), so it does **not** carry the complex-extension overhead
     the CUDA path had — the "rfft" win there is CUDA-specific and not applicable.
   - Structural levers: reduce redundant transforms (share `DST_x(philm)` between
     the potential and Ey, as the CUDA path now does — 7 transforms/solve, not 8),
     preallocate the L/R potential/field output buffers (the allocating
     `_spectral_field_grid_potential!` still returns fresh arrays per solve), and
     fold the drift into the deposit to avoid the drifted-source snapshots. The CPU
     collide already parallelizes over dependency-safe collision wavefronts with a
     per-worker workspace pool; the remaining win is per-solve transform/allocation
     cost, not scheduling.
   - Gate any change on complete-turn A/B timing plus the CPU accuracy-vs-PIC and
     CPU/CUDA parity tests (both already in `test/runtests.jl`).
2. **Further CUDA 6D throughput (lower priority; parity already reached).** Two
   larger, higher-risk transform rewrites were deferred: a Makhoul-style N-point
   real transform (removes the `2(N+1)` extension, ~halving each transform) and L/R
   complex-packing (halves the transform count). Take these only with complete-turn
   A/B timing and the CPU/CUDA 6D parity test, and only if a decisive sub-PIC margin
   is wanted at small particle counts (parity is already reached at ~1e6/beam).
3. Adaptive spectral Dirichlet-box strategy: the current spectral kick solve uses
  one shared global square box for both source and field beams across all slice
  pairs. This is conservative and keeps DST/DCT plans and workspaces simple, but
  it can leave many empty cells/modes for individual slice-pair solves. Explore a
  slice-pair or wavefront adaptive box that remains much larger than the local
  source/field particle domain, e.g. `max(domain_factor * local_sigma_max,
  extrema_margin * local_extrema_max)` with a floor from the full-beam RMS. Unlike
  PIC, the spectral Dirichlet box must not tightly wrap particles because
  `phi=0` at the boundary changes the physics; accuracy must be checked against
  Gaussian/PIC comparisons and the high-energy weak-strong limit. Reuse the PIC
  `green_cache=:slice_pair` design as the implementation pattern: fixed
  `grid=(Nx,Ny)` keeps transform plans reusable, while mode-Green arrays
  `1/(alpha_l^2+beta_m^2)` are cached by slice-pair or quantized box size with
  min-ratio/growth-style rebuild controls.
4. Grid-free spectral performance campaign: keep the direct-mode solver as a
  serious optimized reference path, not just a correctness fallback. Profile and
  optimize the harmonic recurrence, dense mode products, allocation reuse, and
  slice-pair scheduling for representative mode counts such as `48x48`. Note that
  grid-free needs `~64x256` modes (not `48x48`) to resolve the ~11:1 flat beam's
  `pz` kick to ~1% of PIC, so the representative flat-beam reference is heavier
  than the round-beam case.
5. Optional precision refinement: TSC field interpolation (or a finer mesh) to
  close the round-beam gap between the interpolated on-mesh result (~2.7e-3) and
  the per-point analytic (~1.6e-3).

### Completed

- CUDA 6D throughput campaign: rfft-based DST/DCT (real extension, ~2.6x/transform,
  bit-identical), fused 2D-indexed build/extract kernels with folded scaling,
  preallocated L/R output buffers, drift-folded deposit (no drifted-source arrays),
  shared DST_x(philm) (7 transforms/solve), and a right-sized FFT-friendly grid
  (`N=2^k-1` so the `2(N+1)` extension is a power of two). Brought the 6D CUDA grid
  solver from 6.05x slower than PIC to parity (~1x) at 1e6/beam with unchanged ~1%
  accuracy and preserved CPU/CUDA parity (~1e-14). New recommended production grid
  `(127,383)/d=8`. See the optimization history for measurements.
- Grid longitudinal-potential factor-of-2 fix (CPU and CUDA): the on-mesh
  potential `Phig` needed an explicit `1/2` (2D DST reconstruction carries factor
  4, each field component factor 2, sharing one fitted `scale`). Before the fix the
  grid `pz` kick was ~2x too large. After: grid `pz` matches PIC to ~0.5%,
  grid-free to ~1%, and `E = -grad(phi)` finite-difference consistency holds.
  Guarded by a CPU round-beam `rms(dpz)`-vs-PIC test and by the CUDA parity test
  now covering `longitudinal_kick=true`. Removed the dead CPU
  `_spectral_midpoint_luminosity_pair` helpers (superseded by
  `_spectral_midpoint_source` + `_spectral_luminosity_pair`).
- Full 6D synchro-beam map (CPU and CUDA): `longitudinal_kick=true` drifts source
  slices to field-slice boundaries, interpolates left/right spectral fields,
  applies the potential-difference `pz` kick, and reverses the field-particle
  virtual drift. `longitudinal_kick=false` keeps the original transverse-only map.
- Midpoint density-overlap luminosity for the full 6D path: both slices are
  drifted to the common collision midpoint before the spectral/PIC-style density
  overlap. The transverse-only comparison path keeps its original order-
  independent x/y overlap.
- Solver-comparison harness:
  `validation/strong_strong_spectral_comparison.jl` records timing, luminosity,
  final beam moments, and particle-coordinate differences against PIC/Gaussian
  references under `result/strong_strong_spectral_*`.
- Grid-free performance pass: direct mode coefficients and field evaluation now
  use harmonic recurrence plus dense matrix products, cutting the measured
  48x48 direct-mode reference case while preserving the grid-free API.
- Density-overlap luminosity (CPU and CUDA): CIC-deposit both source slices on a
  shared grid, sum the product, scale `npart1*npart2/(nmacro1*nmacro2)` over the
  cell area. Matches `_pic_luminosity!` to machine precision on identical inputs and
  agrees with PIC/Gaussian to ~4% on the production beams.
- CPU caching + parallelism: reusable per-worker workspace pool (deposit/mode/
  derivative buffers + FFTW plans, mode-Green recomputed only when the box changes),
  cutting per-solve allocation ~18 MiB -> 105 KiB; collision parallelized over field
  slices. 100k/beam, 15 slices, grid 128x1024: 9.7 -> 2.0 s/turn (~4.1x on 8
  threads), bit-consistent across thread counts.
- CUDA `collide!` for the grid path (`spectral_cuda.jl`): DST-I/DCT-I built from
  complex cuFFT of symmetric extensions (verified to machine precision vs FFTW),
  one in-place plan per dimension, cached workspace, custom deposit/interp-scatter/
  luminosity kernels. Agrees with the CPU path to ~4e-16 (kicks) and ~9e-16
  (luminosity); 0.62 s/turn at 2.56M/beam, ~4x faster than PIC CUDA at matched grid.
- Validation tests in `test/runtests.jl`: spectral-vs-Gaussian accuracy (both
  variants, round beam, <3%) and CPU/CUDA consistency (rtol 1e-9).
- Production parameter selection: grid `(128, 1024)`, `domain_factor=16` for ~11:1
  beams (grid-converged kick to ~1%, at the graininess floor). See the dated
  `validation/strong_strong_spectral_optimization_history.md`.

### Completed (solver core)

- `SpectralPoissonSolver{T} <: AbstractPoissonSolver`
  (`src/tasks/strongstrong/spectral.jl`): auto-registered, structured option
  schema (`slicing`/`slicing1`/`slicing2`, physical `kbb1`/`kbb2`,
  `luminosity_scale`, `grid`, `domain_factor`, `method`), both `:grid` (CIC deposit
  -> 2D DST -> mode solve -> on-mesh DST/DCT derivative -> interpolate) and
  `:grid_free` (direct converged mode sums) field solves, and a transverse CPU
  `collide!` over slice pairs in collision order.
- Field-solve normalization pinned to physical units. The source deposit is
  normalized to unit charge inside the field solve, so the field is the
  per-unit-charge Bassetti-Erskine field and the caller applies physical
  `kbb * slice_weight` **identically to `GaussianPoissonSolver`** (no `/n_macro`;
  kbb means the same across Gaussian/PIC/spectral). Two separately pinned scale
  constants: grid folds in the DST inverse-normalization and grows with mode count;
  grid-free uses a mode-count-independent constant (the direct sum is converged).
  Verified: round-beam kick matches the soft-Gaussian solver to ~0.2% for both
  variants, and stays within ~0.3% across `domain_factor` 10-16 (drift at larger
  `d` is fixed-grid resolution loss, not normalization).
- Flat-beam box fix. `_spectral_box` was sizing the Dirichlet box anisotropically
  (`Ly ~ d*sigma_y`), which clips the wide field of a flat beam (its transverse
  field extends on the `sigma_large` scale in both directions) and biased the
  wide-direction kick by ~9% at 5:1 (plateauing, not a resolution effect). Fixed
  to a square box sized to `sigma_max` in both directions, matching the docs and
  the earlier validation, with the thin direction resolved by the grid (`Ny`).
  Verified against the soft-Gaussian solver: flat 5:1 now matches to ~0.5% at
  `(128,512)`, and the production ~11:1 flat beam matches to ~0.4% at `(128,1024)`
  (`N_thin ~ 5*d*sigma_x/sigma_y`); round-beam accuracy is unchanged.
- Derivation of the 2D Fourier sine-series Poisson solver, discrete DST/FFT form,
  open-boundary discussion, circular/elliptical generalization, and correctness
  checks (manufactured band-limited solution recovered to 1e-15).
- Accuracy validation against Bassetti-Erskine for round and flat beams, with
  domain-size and thin-direction scaling regressions and parameter-selection
  guidance (domain `d ~ 12-16*max(sigma)`; anisotropic grid).
- Grid and grid-free variants with a computational-complexity comparison
  (grid/DST is 100-1000x faster than grid-free).
- Exact spectral field derivative: 2-3x more accurate than finite differences;
  the solver beats PIC on flat beams (25:1 median ~30% lower, max ~3x better) and
  ties on round.
- Fast on-mesh spectral-derivative field pipeline (O(Nx*Ny*log)) validated to
  retain the accuracy advantage at ~4x lower cost than PIC. The DST-I mesh cosine
  derivative equals a zero-padded DCT-I (verified to machine precision).

## Earlier Completed

- Soft-Gaussian CUDA optimization (host-sync removal, device moments, fused
  wavefront launches): 0.2778 -> 0.2280 s/turn, bit-identical. See
  `validation/strong_strong_gaussian_optimization_history.md`.
- PIC `kbb1/kbb2` override switched to physical units, consistent across all
  solvers and frozen-beam elements.
- Strong-strong example and task notebook default to the PIC solver with the
  soft-Gaussian solver as a commented alternative.
- Lorentz crossing maps classified as Hirata quasi-symplectic (`NonSymplectic6DMap`).
