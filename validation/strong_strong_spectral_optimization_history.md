# Spectral Solver Optimization & Validation History

Chronological record of the `SpectralPoissonSolver` build-out, with measured
evidence. See `docs/spectral_sine_poisson_solver.md` for the method and
`src/tasks/strongstrong/spectral.jl` / `spectral_cuda.jl` for the code.

## 2026-07-23: fix grid longitudinal-potential factor of 2

The grid-path `pz` (synchro-beam) kick was ~2x too large. The on-mesh potential
`Phig` is reconstructed with a 2D DST (FFTW `RODFT00`, factor 2 per dimension =
factor 4), while each field component carries a factor 2 (one DST plus one
zero-padded DCT whose explicit `/2` nets to `1x` on the derivative dimension).
Sharing the single fitted `scale` between potential and field therefore left the
potential a factor 2 too large relative to `E = -grad(phi)`, so the
potential-difference `pz` kick (`kbb * (phiL - phiR) * hzi`) was doubled. Fixed by
folding an explicit `1/2` into `Phig` on both CPU
(`_spectral_field_grid_potential!`) and CUDA (`_cuda_spectral_field_potential!`).

The transverse (`px`, `py`) kick was never affected (it does not use `Phig`), and
`longitudinal_kick=false` is byte-identical. The grid-free path was already
correct (it evaluates the sine/cosine series directly with matching signs, no
DST normalization factor). Evidence after the fix:

- `E = -grad(phi)` finite-difference consistency: grid ratio `Ex/(-dPhi/dx)`
  moved from `0.487` to `0.974` (residual is grid/CIC discretization); grid-free
  stayed at `1.000`.
- Isolated `rms(pz_after - pz_before)` vs PIC on a 5-slice flat case at
  `grid=(128,1024)`: grid/PIC `1.001` (e), `0.995` (p); before the fix these were
  ~2x. Grid-free converged to PIC as its mode count grew (`48x48` -> `0.84`/`0.66`;
  `64x256` -> `0.997`/`0.992`), confirming the same normalization.
- CUDA 6D vs CPU 6D on a 3-slice flat case: max relative coordinate error
  `1.2e-14`, luminosity ratio `1.0`.

Regression guards added: a CPU round-beam `rms(dpz)` vs PIC check (`rtol=0.05`)
in the "Spectral synchro-beam longitudinal map is finite" testset, and the CUDA
parity testset now runs both `longitudinal_kick=false` and `true`. The earlier
coordinate-delta tables did not catch this because total `pz` is dominated by the
initial energy spread (`~1e-3`), which masks a 2x error in the `~1e-8` kick.

## 2026-07-23: high-energy weak-strong limit for spectral grid and grid-free

`validation/high_energy_weakstrong_limit.jl` now includes spectral-specific
high-energy checks. The electron beam energy is set to `1e100 GeV`, making its
kick negligible. Each spectral strong-strong run is compared against a separate
frozen-source spectral weak-strong reference that applies only the electron
source field to the proton beam. This isolates the high-energy limit from the
expected grid/model difference relative to the analytic soft-Gaussian
weak-strong reference.

Production CPU run, `20k/beam`, five slices, PIC grid `96x96`, spectral grid
`128x1024`, grid-free direct modes `48x48`, 8 Julia threads:

| solver | luminosity | frozen-source luminosity | limit lum rel err | proton limit max abs | electron max abs change | Gaussian-ref lum rel err | Gaussian-ref size rel err |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Gaussian | 9.513905885442607e29 | same analytic reference | 0 | 5.42e-20 | 5.42e-20 | 0 | 0 |
| PIC `96x96` | 9.485268272757882e29 | analytic reference | n/a | n/a | n/a | 3.01e-3 | 8.50e-5 |
| spectral grid `128x1024` | 9.482692778262468e29 | 9.482692778262469e29 | 1.48e-16 | 2.17e-19 | 5.42e-20 | 3.28e-3 | 6.68e-5 |
| spectral grid-free `48x48` | 9.453190104201961e29 | 9.453190104201960e29 | 1.49e-16 | 5.42e-20 | 5.42e-20 | 6.38e-3 | 1.83e-3 |

Optional CUDA spectral grid check on the same case passed against the CPU
frozen-source spectral reference: luminosity matched exactly at printed
precision, proton limit max-absolute difference was `2.17e-19`, and electron
max-absolute change was `8.13e-20`. Grid-free remains CPU-only.

## 2026-07-23: full 6D synchro-beam map and comparison harness

`SpectralPoissonSolver` now has a public `longitudinal_kick` option. The default
`true` path applies the same slice-boundary synchro-beam structure as the PIC
solver: source slices are drifted to the field-slice left/right collision planes,
the spectral potential and transverse fields are evaluated at both planes, field
particles receive the longitudinally interpolated transverse kick plus the
potential-difference `pz` kick, and the virtual drift is reversed.
`longitudinal_kick=false` retains the original transverse-only spectral map for
validation and speed comparisons.

The full 6D luminosity path now uses the same midpoint convention as PIC: both
slices are drifted to their common collision midpoint before the density-overlap
integral. The transverse-only comparison path keeps the original x/y overlap so
its kick and luminosity remain order-independent. The comparison harness
`validation/strong_strong_spectral_comparison.jl` records per-solver timing,
luminosity, final beam moments, and particle-coordinate differences against PIC
under `result/strong_strong_spectral_*`.

Production-shaped CPU baseline before the 6D change, `20k/beam`, 15 slices,
`grid=(128,1024)`, `domain_factor=16`, one collision turn, 8 Julia threads:

| solver | s/turn | allocated | final luminosity |
| --- | ---: | ---: | ---: |
| Gaussian | 0.154 | 15.4 MB | 1.0277e30 |
| PIC `(128,128)` | 4.216 | 972 MB | 1.0240e30 |
| spectral grid, transverse-only | 1.897 | 483 MB | 1.0481e30 |

After the 6D change on the same CPU case:

| solver | s/turn | allocated | final luminosity |
| --- | ---: | ---: | ---: |
| Gaussian | 0.154 | 15.4 MB | 1.0277e30 |
| PIC `(128,128)` | 4.229 | 972 MB | 1.0240e30 |
| spectral grid 6D `(128,1024)` | 5.064 | 590 MB | 1.0194e30 |

The CPU grid path is now slower than PIC for this small-particle benchmark
because the full synchro-beam map needs four spectral source-boundary solves per
slice pair. The mode-Green and FFTW plans are still reused across slice pairs:
the extra cost is real field/potential work, not Green recomputation. The CPU
6D implementation parallelizes over dependency-safe collision wavefronts, with
one grid workspace per logical worker.

CUDA `20k/beam`, 15 slices, `grid=(128,1024)`:

| solver | s/turn | allocated | final luminosity |
| --- | ---: | ---: | ---: |
| Gaussian | 0.0111 | 0.9 MB | 1.0277e30 |
| PIC `(128,128)` | 0.2315 | 35.4 MB | 1.0240e30 |
| spectral grid 6D `(128,1024)` | 1.332 | 91.0 MB | 1.0194e30 |

CPU/CUDA spectral 6D agreement on a 512-particle, three-slice smoke case was at
roundoff: luminosity matched to `4e-16` relative and maximum coordinate
differences were `<= 9e-19`.

Coordinate and moment comparison for the `20k/beam` CPU run:

- spectral grid versus PIC final luminosity: `-0.45%`;
- Gaussian versus PIC final luminosity: `+0.36%`;
- spectral grid versus PIC beam-1 relative coordinate RMS deltas:
  `x 4.96e-4`, `px 8.47e-3`, `y 5.95e-3`, `py 9.75e-3`, `pz 1.46e-6`;
- spectral grid versus PIC beam-2 relative coordinate RMS deltas:
  `x 4.40e-5`, `px 1.22e-3`, `y 5.66e-4`, `py 1.60e-3`, `pz 7.42e-7`.

Grid-free performance was optimized by replacing scalar particle/mode loops with
harmonic recurrence for sine/cosine bases and dense matrix products for the mode
coefficients and field evaluation. On the smaller measured case (`2k/beam`, 15
slices, grid path `(64,512)`, grid-free `(48,48)`, one 6D CPU turn), grid-free
ran in `0.209 s/turn`; the previous transverse-only scalar grid-free baseline on
the same `48x48` direct-mode setting was `0.452 s/turn`, so the direct reference
path is substantially faster despite now doing the full 6D map. It remains a
reference path, not a production flat-beam setting.

Rejected CUDA optimization: batching the four source-boundary spectral solves
inside each slice pair as a `Nx x Ny x 4` cuFFT stack was slower (`1.467 s/turn`)
than the individual cached-workspace solves (`1.332 s/turn`) on the 20k/beam
case. The likely cause is inefficient small 3D batched transform/layout overhead
at this batch size. A future CUDA optimization should batch across an entire
collision wavefront, not just the four solves within one pair, and should be
accepted only after complete-turn A/B timing and CPU/CUDA parity checks.

## Accuracy validation (vs soft-Gaussian analytic kick)

Aligned Gaussian beams, kick compared to `GaussianPoissonSolver` (physical `kbb`
convention, identical across Gaussian/PIC/spectral).

| case | grid | metric | spectral | notes |
| --- | --- | --- | --- | --- |
| round 1:1 | 128² (grid), 64² (grid-free) | median kick ratio | 0.998–1.000 | both variants |
| round, `domain_factor` 10–16 | 128² | median ratio | within 0.3% | drift at larger `d` is fixed-grid resolution loss |
| flat 5:1 | 128×512 | median ratio | 0.995 | after the square-box fix (was 0.936 plateau) |
| flat ~11:1 (production) | 128×1024 | median ratio | 1.004 / 0.998 | `N_thin ~ 5*d*sigma_x/sigma_y` |

The **square Dirichlet box** (sized to `sigma_max` in both directions) is
essential for flat beams: an anisotropic box (`Ly ~ d*sigma_y`) clips the wide
field and biases the wide-direction kick by ~9% at 5:1 (~20% at 11:1),
independent of grid refinement. Fixed in `_spectral_box`.

### Production grid selection (~11:1 beams)

Convergence vs a fine spectral reference (256×3072), relrms of the kick:

| grid | relrms vs fine (px / py) | vs Gaussian graininess (px / py) |
| --- | --- | --- |
| 64×512 | 0.035 / 0.077 | 0.029 / 0.061 |
| 96×768 | 0.017 / 0.037 | 0.011 / 0.046 |
| 128×768 | 0.010 / 0.030 | 0.007 / 0.048 |
| 128×1024 | 0.010 / 0.021 | 0.007 / 0.051 |
| 128×1536 | 0.009 / 0.014 | 0.007 / 0.054 |

**Recommended production setting: grid = (128, 1024), domain_factor = 16.** `px`
is grid-converged to ~1% (at the ~0.7% particle-graininess floor); `py` grid error
(~2%) is already well under the ~5% physical graininess floor, so refining further
does not improve the physics. `Nx = 128` gives ~4 mesh points per `sigma_x`;
`Ny = 1024` follows `N_thin ~ 5*d*(sigma_x/sigma_y)`.

## Luminosity

Density-overlap integral mirroring PIC (CIC deposit both source slices, sum
product, scale `npart1*npart2/(nmacro1*nmacro2)` over the cell area). Per-pair
function matches `_pic_luminosity!` to machine precision on identical inputs;
full-collision luminosity agrees with PIC and Gaussian to ~4% (residual is
deposition detail — sources are not drifted to the collision midpoint).

## CPU performance (100k/beam, 15 slices, grid 128×1024)

| step | s/turn | note |
| --- | --- | --- |
| baseline (allocating) | 9.7 | ~18 MiB allocation per field solve |
| + cached buffers/plans | 8.4 | per-solve allocation 18 MiB -> 105 KiB; matches reference to 5e-16 |
| + field-slice parallelism (8 threads) | 2.04 | 4.1x; results bit-consistent across thread counts |

FFTW multithreading was tried and **rejected** (0.019 -> 0.28 s/solve — pathological
on this transform size); single-thread FFTW per solve with parallelism across the
~450 field solves is the right structure.

## CUDA performance (grid 128×1024, 15 slices)

cuFFT has no native DST/DCT; both are built from complex FFTs of symmetric
extensions (odd -> `-imag` for DST-I, even -> `real` for DCT-I), verified to
machine precision against FFTW. One in-place FFT plan per dimension serves both.

| scale | spectral CUDA | PIC CUDA (wavefront) | speedup |
| --- | --- | --- | --- |
| 500k/beam | 0.53 s/turn | 2.12 s/turn | 4.0x |
| 2.56M/beam (production) | 0.62 s/turn | — | — |

Spectral is **~4x faster than PIC on GPU** at matched grid resolution (no
zero-padding, no Green-function convolution — just DST + per-mode divide + DCT
derivative), while also more accurate on flat beams. CPU/CUDA agreement is
machine-precision (kicks 4e-16, luminosity 9e-16) since the algorithm and particle
data match.

Field solves dominate the GPU turn (~77%; luminosity ~16%). A buffer-reuse pass
(reusing device Exg/Eyg/luminosity buffers instead of per-pair allocation) showed
**no measured speedup** (0.55 vs 0.53 s/turn — CUDA's memory pool already makes the
allocations cheap and the FFT compute dominates) and was reverted to keep the code
simple. Further speedup would require batching the many small FFTs across slice
pairs; given the existing 4x lead over PIC, this was judged past the point of clear
benefit.
