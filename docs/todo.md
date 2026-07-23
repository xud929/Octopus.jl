# TODO

## Spectral Sine-Series Poisson Solver

See `docs/spectral_sine_poisson_solver.md` for the method and measured accuracy,
and `validation/spectral_poisson_field_validation.jl` for the reference field
implementations. The algorithmic core is validated; the remaining work is the
solver integration.

### Open

- Add `SpectralPoissonSolver{T} <: AbstractPoissonSolver` (new
  `src/tasks/strongstrong/spectral.jl`). Options: `slicing` (+ `slicing1/2`),
  physical-units `kbb1/kbb2`, `luminosity_scale`, `domain_factor`, transverse
  grid `(Nx, Ny)` with an anisotropy rule `N_thin ~ 5*d*(sigma_large/sigma_small)`,
  `deposit_method`, `longitudinal_kick`, `batch_mode`. Register structured option
  metadata and a runtime consumer for every field.
- Pin the absolute field-solve normalization so a physical `kbb` reproduces the
  Bassetti-Erskine kick (validation currently uses least-squares shape
  calibration). Keep the kbb convention consistent with `GaussianPoissonSolver`,
  `PICPoissonSolver`, and `ThinStrongBeam` (physical units; divide by the source
  macroparticle count internally, as the PIC path does).
- Implement CPU `collide!(solver::SpectralPoissonSolver, beam1, beam2,
  CPUThreadsBackend)`: slice both beams, loop slice pairs in collision order,
  deposit each source slice, solve the field with the on-mesh spectral-derivative
  pipeline (DST deposit -> mode solve -> DST/DCT derivative -> interpolate), kick
  the opposing field slice in both directions, accumulate luminosity. Reuse the
  shared `_strong_strong_*` slicing/kbb/luminosity helpers.
- Implement CUDA `collide!` for the same path: cuFFT DST (symmetric extension)
  and the DCT cosine-derivative, batched over slice pairs following the Gaussian
  and PIC wavefront pattern; no zero mode and no doubled grid.
- Add `StrongStrongSpectralBackendConsistencyContract` (CPU/CUDA coordinate and
  luminosity agreement) and wire it into `test/runtests.jl`. Add a single
  high-energy-limit collision check against the soft-Gaussian solver, which must
  match as it does for PIC/Gaussian.
- Profile the spectral solver at production scale (2.56M/1.024M, 15 slices) on
  CPU and CUDA, compare complete-turn time to PIC, then optimize; record the runs
  in a dated `validation/strong_strong_spectral_optimization_history.md`.
- Optional precision refinement: TSC field interpolation (or a finer mesh) to
  close the round-beam gap between the interpolated on-mesh result (~2.7e-3) and
  the per-point analytic (~1.6e-3).
- Optional: circular (Fourier-Bessel) domain variant for round beams, per
  `docs/spectral_sine_poisson_solver.md` Section 12.

### Completed

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
