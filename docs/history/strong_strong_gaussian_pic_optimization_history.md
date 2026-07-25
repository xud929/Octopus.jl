# GaussianPICPoissonSolver — Optimization History

Dated developer log of the `GaussianPICPoissonSolver` implementation and its CUDA
performance campaign. Method and accuracy theory are in
`docs/theory/gaussian_subtracted_pic_solver.md`; accuracy validation is in
`validation/gaussian_pic_field_validation.jl` and
`validation/gaussian_pic_bigaussian_validation.jl`.

Benchmarks below are single-collision wall time (15 slices, CIC, 512k e- /
256k p, RTX 4500 Ada), the same shape as the production case. "PIC" is the
production `PICPoissonSolver` (indexed wavefront, batched FFT). Ratios are the
portable metric; absolute times are workstation-GPU (weak FP64).

## 2026-07-24 — CPU implementation

- `GaussianPICPoissonSolver{T} <: AbstractPoissonSolver` composing
  `PICPoissonSolver` plus `margin_sigma`, `neutralize`, `coupling_tol`
  (`src/tasks/strongstrong/gaussian_pic.jl`). Reuses PIC slicing, integrated-log
  Green FFT + slice-pair cache, interpolation, and luminosity unchanged.
- Deposits particles, subtracts the erf-integrated reference Gaussian on the grid
  (node-centered CIC/TSC moment integrals), solves the residual with the shared
  Green FFT, and adds the exact Bassetti-Erskine transverse field back per
  particle. Longitudinal: residual grid potential-difference kick + the
  soft-Gaussian covariance-transport and centroid terms (reusing the existing
  Hessian helpers).
- Validated: full `test/runtests.jl` green; single-Gaussian field accuracy 2.6x
  (grid 128) to 20x (grid 48) better than PIC systematically; bi-Gaussian fair
  test shows a graceful 1.4-2.6x with no regression; the systematic gain washes
  into the shot-noise floor at production statistics per collision but persists
  as the coherent bias reduction.

## 2026-07-24 — CUDA implementation and performance campaign

### Correctness first: sequential and non-indexed wavefront paths

- First CUDA path mirrored the plain sequential PIC interaction with the Gaussian
  subtraction injected before the FFT (device outer-product subtract; erf node
  profiles built on the host and uploaded — **no device `erf` needed**, and
  `CUDA.erf` is not available in-kernel) and the Bassetti-Erskine add-back in the
  kick kernel (reusing `_cuda_gaussian_beambeam_kick` and `_gpic_cov_pz`).
- **Sequential CPU/CUDA divergence (investigated).** The plain sequential CUDA
  PIC path is only ~1e-3 consistent with CPU, while the wavefront path is
  bit-parity (~1e-15). Isolation showed the grids are identical
  (`_cuda_pic_cached_interaction_grids` returns the raw grids) and the Green FFT
  matches; the ~1e-3 is intrinsic to the non-wavefront PIC primitives, not the
  Gaussian additions (gpic sequential error 2.9e-3 ≈ PIC sequential 3.1e-3, i.e.
  the additions add nothing). Rather than chase it, the fix was to build gpic on
  the **wavefront** path, which is bit-parity *and* fast — resolving parity and
  speed together.
- Non-indexed wavefront path: added an optional `gpic_subtract` argument to the
  shared `_cuda_pic_solve_wavefront_fields_batched_fft!` (subtracts
  `amp[p]*gx[i,p]*gy[j,p]` from each charge plane before the batched FFT; a no-op
  for plain PIC), reused the fused on-device Green build, and kicked with the
  Bassetti-Erskine add-back. **Result: CPU/CUDA bit-parity (lum 2e-16, coords
  5.6e-13).** Parity is ~1e-13 rather than ~1e-15 because the slice moments use a
  parallel reduction (different summation order than the CPU sequential sum);
  this is well within the 1e-10 backend-consistency contract.

### Throughput campaign (grid 128, vs PIC 0.23 s)

| change | s/collision | note |
| --- | ---: | --- |
| non-indexed wavefront, per-pair Green FFT | 0.65 | fresh Green per pair |
| fused on-device Green (`green12=green21=nothing`) | 0.57 | reuse PIC's batched Green build |
| tuple-`mapreduce` moments (broadcast add) | 0.65 | broadcast-over-tuple reduction is ~50x slow on CUDA |
| explicit unrolled 10-tuple add (one sync) | 0.54 | fast single-sync moment reduction |
| async luminosity (separate stream) | 0.57 | overlap; small effect (profiling had inflated it) |
| **indexed wavefront path** | **0.37** | **no gather/scatter — the decisive win** |

**The decisive lever is the indexed wavefront path.** PIC's speed comes from
operating directly through slice **index** vectors (no compact gather/scatter):
measured PIC non-indexed 0.80 s vs PIC indexed 0.23 s (3.4x). gpic on the
non-indexed path was stuck at ~0.57 s regardless of grid (overhead-bound, not
FFT-bound). Porting gpic to the indexed path required:

- **Batched per-slice moments on device**, reusing the soft-Gaussian moment
  kernels (`_cuda_launch_gaussian_moment_partials!` +
  `_cuda_gaussian_reduce_partials_kernel!` + `_cuda_gaussian_moments_from_sums`)
  which read through `idx` — no gather. One reduction + one host copy per
  wavefront instead of per-pair syncs.
- **Reusing the batched-bounds prepare** (`_cuda_pic_prepare_interaction_wavefront_indexed!`)
  and re-finishing grids with the `margin_sigma`-enlarged source box on the host
  (the prep already returns `source_bounds`/`field_bounds`), so no prepare fork.
- An **indexed pair kick** (`_cuda_gpic_kick_pair_indexed_*_kernel!`) that applies
  the residual grid kick + Bassetti-Erskine add-back to both directed slices via
  index, with the per-direction Gaussian parameters passed as an isbits
  NamedTuple.

### Current status (indexed wavefront default)

| solver | grid | s/collision | vs PIC 128 | accuracy |
| --- | --- | ---: | ---: | --- |
| PIC | 128 | 0.23 | 1.0x | baseline |
| **GaussianPIC** | 128 | **0.37** | 1.6x | ~2.6x better systematic field |
| **GaussianPIC** | 64 | **0.28** | 1.2x | ≈ PIC@128 systematic accuracy |

Because the hybrid's systematic field error is nearly grid-independent
(`gaussian_pic_field_validation.jl`: hybrid@48 ≈ PIC@128), **GaussianPIC@64 at
0.28 s is comparable to PIC@128 at 0.23 s with equal-or-better accuracy**, and
GaussianPIC@128 (0.37 s, 1.6x) gives the maximal accuracy margin. Both CUDA
wavefront paths (indexed default, non-indexed fallback) are CPU/CUDA bit-parity
and covered by the `test/runtests.jl` "CUDA GaussianPIC solver matches CPU"
testset.

### 2026-07-24 — sequential CUDA divergence root-caused and fixed

The ~1e-3 CPU/CUDA divergence on the plain-sequential path (seen in both PIC and
GaussianPIC) was root-caused to a real correctness bug, not float noise. The
plain-sequential collide kicked direction 1's **field slice in place**, then used
that already-kicked slice as direction 2's **source** for deposition (and stored
/ took luminosity from post-kick coordinates). The CPU and batched CUDA paths
preserve the two-direction semantics — both directed kicks read the *unkicked*
opposing slice, because CPU uses `field = copy(coord)` and the batched paths
deposit all sources before any kick. The plain-sequential path aliased source and
field.

Fix: give each direction a separate pre-collision source and kicked-field buffer
(`_cuda_pic_copy_coords` / `_cuda_pic_write_coords!` in `pic_cuda.jl`, and the
analogous copy in `gaussian_pic_cuda.jl`). After the fix the sequential path is
**bit-parity** with CPU: PIC sequential 1.2e-15 (lum) / 1.2e-12 (coords),
GaussianPIC sequential 2.1e-16 / 5.7e-13 — matching the wavefront paths.

Separately fixed a pre-existing `UndefVarError: rep` in the validation-only
helper `_cuda_pic_solve_field_with_green_fft` (referenced a nonexistent `rep`
instead of the `x` argument), which had made the standalone CUDA field-solve
helper unusable.

### Remaining levers (not yet pursued)

- The grid-128 gap to PIC (0.14 s) is the host-side erf profile build
  (`nplanes x grid` evaluations, serial) plus the extra per-particle
  Bassetti-Erskine/covariance work in the kick. The profile build could move to a
  device kernel with an in-kernel erf approximation (or overlap on a side stream);
  the kick cost is inherent to the analytic add-back (comparable to the
  soft-Gaussian solver's per-particle cost).
- `grid=48` shows a timing anomaly (slower than 64), likely a non-FFT-friendly
  transform size; grid 64 is the recommended production point.
- The coupled (rotated) subtraction branch (`coupling_tol < Inf`) is still
  unimplemented; the CUDA path is always-uncoupled like the CPU path.
