# Spectral Solver Optimization & Validation History

Chronological record of the `SpectralPoissonSolver` build-out, with measured
evidence. See `docs/spectral_sine_poisson_solver.md` for the method and
`src/tasks/strongstrong/spectral.jl` / `spectral_cuda.jl` for the code.

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
