# Strong-Strong PIC Solver — Optimization History

Historical record of `PICPoissonSolver` optimizations. These were tracked as a
roadmap in the former `pic_solver_improvement_plan.md` (now removed); the items below are
implemented and now recorded here (the source is the authority — this file only
preserves the rationale and decisions). Open items that were never implemented
moved to `docs/todo.md`. Benchmark decisions from the extreme-scale runs live in
`strong_strong_pic_extreme_benchmark_history.md`; field-accuracy validation is in
`pic_gaussian_field_validation.jl`.

`PICPoissonSolver` solves the 2D transverse open-boundary Poisson problem for
strong-strong slice interactions: drift the source slice to the field slice's
left/right longitudinal boundaries, deposit (`:CIC`/`:TSC`), solve by zero-padded
FFT convolution with a logarithmic Green function, build finite-difference
transverse fields, and interpolate the left/right fields onto each field particle
by longitudinal position.

## Completed

- **Green-FFT reuse.** The left and right source-boundary solves of one directed
  slice interaction share the source grid, field grid, spacing, and Green
  function, so `fft(green)` is computed once and reused. Implemented on CPU and
  CUDA (the CUDA path builds the Green function on the GPU and reuses the cached
  Green FFT).
- **CPU workspace buffers.** The CPU path reuses the charge grid, thread-local
  deposit grids, complex spectral work array, Green construction/FFT buffers, the
  left/right `phi/Ex/Ey` field arrays, and luminosity deposition grids across all
  directed slice interactions, with in-place FFTW plans stored in the workspace.
  `StrongStrongTask` retains the workspace across turns; standalone `collide!`
  uses temporary state. Drifted source coordinates are deposited directly with no
  separate source-boundary coordinate arrays.
- **Slice-pair Green cache.** `green_cache=:slice_pair` (production default) keeps
  two reusable Green FFTs per slice pair, one per beam-beam direction, enlarges
  rebuilt grids by a configurable factor, and reuses an entry only when the
  current source/field domains fit inside the cached grids. CPUThreads and CUDA
  share the `:none`/`:slice_pair` API; `:none` is the uncached physics reference.
  Generic exact-geometry and grid-template caches were removed after July 2026
  CUDA benchmarks showed no wall-time benefit. Checked by
  `StrongStrongPICBackendConsistencyContract`.
- **Overlapped CUDA field solves.** The four source-boundary solves of a slice
  pair are independent and run on separate CUDA streams (`cuda_async=true`;
  `false` disables for comparison).
- **Compact CUDA slice buffers.** CUDA slicing compacts each slice mask into a GPU
  index vector; the collision reuses those index vectors for compact
  gather/scatter, bounding peak memory by the active slice pair. Temporary arrays
  are reclaimed adaptively (default: check every 16 slice-pairs, reclaim below 12%
  free memory).
- **Indexed CUDA collision path** (was "two-state indexed" in the plan). The
  default `cuda_indexed_wavefront` path avoids compact gather/scatter by operating
  through slice index vectors while preserving the two-direction pre-collision
  semantics (both beams read the pre-collision opposing slice). This is the fast
  production path and is CPU/CUDA bit-parity. (The plain-sequential path's
  source/field aliasing was a separate bug, fixed 2026-07-24 — see
  `strong_strong_gaussian_pic_optimization_history.md`.)
- **Spectral sine-series alternative.** `SpectralPoissonSolver` (a Dirichlet-box
  DST/DCT solver, no doubled grid, no zero mode) was added as an alternative to
  the Green-function convolution; theory and measured accuracy are in
  `docs/theory/spectral_sine_poisson_solver.md`, history in
  `strong_strong_spectral_optimization_history.md`.

## Validating PIC solver changes

Run after any PIC field/deposit/Green/cache change:

```bash
julia --project=. validation/pic_gaussian_field_validation.jl
OCTOPUS_PIC_VALIDATION_RANDOM_CASES=100 OCTOPUS_PIC_VALIDATION_WRITE_CASE_DATA=false \
  julia --project=. validation/pic_gaussian_field_validation.jl
OCTOPUS_SOLVER=pic julia --project=. examples/strong_strong_tracking.jl
OCTOPUS_USE_GPU=1 OCTOPUS_SOLVER=pic julia --project=. examples/strong_strong_tracking.jl
OCTOPUS_USE_GPU=1 OCTOPUS_SOLVER=pic OCTOPUS_CUDA_PIC_ASYNC=0 \
  julia --project=. examples/strong_strong_tracking.jl
```

Track median / p95 / maximum normalized field error and representative CPU/CUDA
wall time.
