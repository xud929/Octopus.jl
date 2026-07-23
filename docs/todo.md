# TODO

## Spectral Sine-Series Poisson Solver

See `docs/spectral_sine_poisson_solver.md` for the method and measured accuracy,
and `validation/spectral_poisson_field_validation.jl` for the reference field
implementations. The algorithmic core is validated; the remaining work is the
solver integration.

### Open

- **Flat-beam wide-component kick bias.** In the aligned round-beam test the
  spectral kick matches the soft-Gaussian solver to ~0.2% (both variants), but for
  a 5:1 flat beam the wide-direction kick (`Ex`) is ~9% low while the thin
  direction (`Ey`) is ~0.7% high. It plateaus at ~0.91 and does **not** close with
  finer/anisotropic grids (256x768, 384x768), so it is a geometry-dependent
  component bias, not a resolution effect. Production beams are ~11:1 flat, so this
  must be understood before the solver is used for physics. Suspect the on-mesh
  DST/DCT derivative or the square-box mode spectrum interacting with beam
  anisotropy; the least-squares shape validation hid it by fitting a single scale.
- Density-overlap luminosity: replace the placeholder in `_spectral_collide!`
  (currently `sum_ij weight_i weight_j klum1`) with a real transverse
  density-overlap integral, matching the PIC luminosity convention.
- Caching (spectral analog of the PIC slice-pair Green cache, lighter; see
  `docs/spectral_sine_poisson_solver.md` Section 17): cache FFTW DST/DCT plans per
  `(Nx, Ny)` and the diagonal mode-Green array `G_lm = 1/(alpha_l^2 + beta_m^2)`
  per domain. Basis is domain-independent at grid nodes; `G_lm` rescales by `s^2`
  under uniform domain scaling and is an O(Nx*Ny) recompute otherwise. Prefer a
  fixed domain over the run. No shifted Green function is needed (single box holds
  both source and field; offsets are absorbed into deposition).
- Implement CUDA `collide!` for the grid path: cuFFT DST (symmetric extension)
  and the DCT cosine-derivative, batched over slice pairs following the Gaussian
  and PIC wavefront pattern; no zero mode and no doubled grid. Grid-free CUDA is
  optional (the recurrence-based mode sums are parallel but the mode count limits
  it for flat beams).
- Add `StrongStrongSpectralBackendConsistencyContract` (CPU/CUDA coordinate and
  luminosity agreement) and wire it into `test/runtests.jl`. Add a single
  high-energy-limit collision check against the soft-Gaussian solver, which must
  match as it does for PIC/Gaussian.
- Profile the spectral solver at production scale (2.56M/1.024M, 15 slices) on
  CPU and CUDA. Compare **grid versus grid-free** complete-turn time head to head,
  and both against PIC, then optimize; record the runs in a dated
  `validation/strong_strong_spectral_optimization_history.md`.
- Optional precision refinement: TSC field interpolation (or a finer mesh) to
  close the round-beam gap between the interpolated on-mesh result (~2.7e-3) and
  the per-point analytic (~1.6e-3).
- Optional: circular (Fourier-Bessel) domain variant for round beams, per
  `docs/spectral_sine_poisson_solver.md` Section 12.

### Completed

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
