# Soft-Gaussian Solver Audit and Optimization

Date: 2026-07-21

## Reference implementations

The audit compared the Octopus sliced soft-Gaussian map against:

- Hirata, Moshammer, and Ruggiero's canonical synchro-beam map,
  *Part. Accel.* 40 (1993), 205-228.
- Xsuite/Xfields `BeamBeamBiGaussian3D`, commit
  `a9a44039e1fc8054aaf7a676089b8e61ccb8bd15`.
- BeamBeam3D V1.0, commit
  `50d01d81b003405ffd80a52f2c35284e846bf63d`.

Xsuite transports the source covariance to the per-particle collision point,
evaluates the Bassetti-Erskine field and its Gaussian-size derivatives, and
applies both the transverse-momentum slingshot and covariance-dependent
longitudinal terms. BeamBeam3D's `scatter2dgauss` independently confirms the
slingshot update

```text
delta pz = (px_new^2 + py_new^2 - px_old^2 - py_old^2) / 4.
```

Stable source links:

- <https://github.com/xsuite/xfields/blob/a9a44039e1fc8054aaf7a676089b8e61ccb8bd15/xfields/beam_elements/beambeam_src/beambeam3d.h#L208-L321>
- <https://github.com/xsuite/xfields/blob/a9a44039e1fc8054aaf7a676089b8e61ccb8bd15/xfields/fieldmaps/bigaussian_src/compute_gx_gy.h>
- <https://github.com/beam-beam/BeamBeam3D/blob/50d01d81b003405ffd80a52f2c35284e846bf63d/V1.0/DepoScat.f90#L1903-L1940>
- <https://research.kek.jp/people/dmzhou/BeamPhysics/SAD/Beam-beam_Hirata-1992.pdf>

The complete sign-convention and Hamiltonian derivation shared with the
weak-strong map is documented in
[`../docs/beam_beam_longitudinal_kick.md`](../docs/beam_beam_longitudinal_kick.md).

## Correctness findings

The transverse Bassetti-Erskine field, charge/energy scaling, slice weights,
per-particle collision point, transported uncoupled covariance, collision
ordering, and luminosity normalization agree with the reference model under
Octopus's opposing-beam coordinate convention.

The solver now uses the same collision-point map as the weak-strong element.
For each field particle it applies the selected physical virtual drift, the
collision-point Gaussian kick, the moving-centroid and covariance derivative
terms, and the inverse virtual drift. This also corrected the round-beam
covariance Hessian in the former soft-Gaussian implementation.

The longitudinal update contains:

1. the before/after transverse-momentum slingshot;
2. the moving source-centroid term; and
3. the derivative of the transported source covariance, including a zero
   derivative when `min_sigma` clamps the RMS size.

`GaussianPoissonSolver(longitudinal_kick=true)` is the corrected default.
`longitudinal_kick=false` preserves the former transverse-only map for
controlled compatibility comparisons. A zero-width source with
`min_sigma=0` now produces a finite zero kick instead of a luminosity `NaN`.

`virtual_drift=:hirata`, `:chromatic`, and `:exact` use the same named physical
Hamiltonians as weak-strong tracking. `include_sigma_xy=true` measures all ten
independent entries of the slice covariance in `(x, px, y, py)`, transports
them to each collision point, rotates the field into the instantaneous
principal axes, and includes both eigenvalue and rotation derivatives in the
longitudinal kick. The default `false` is a compile-time-specialized uncoupled
path.

## Performance changes

CUDA previously scanned the full beam for every slice pair, rebuilt a mask,
performed eleven independent full-array reductions per source slice, launched
both kick kernels across all particles, and reduced two full luminosity arrays
although only one sampling beam was selected.

The optimized CUDA path:

- reuses the slice index vectors already produced by longitudinal slicing;
- fuses ten transverse moment sums into one indexed block-reduction kernel;
- launches kicks only over the active slice particles;
- computes and reduces luminosity only for the selected sampling beam; and
- groups causally ready, non-overlapping slice pairs into wavefronts;
- captures all live source moments before each wavefront's kicks;
- reduces all moment partials with one device reduction and one host transfer
  per wavefront; and
- reduces luminosity once per wavefront rather than once per slice pair.

The CPU path retains strict collision-time ordering and particle-level
threading. The CUDA wavefront scheduler is valid for live moments because each
batch is a dependency-ready matching: no slice appears twice, and all moments
are captured before any kick in the batch. Thus disjoint pair maps commute
without changing any slice's collision history. `batch_mode=:sequential`
remains available as a reference path.

## Validation

The public backend contract passed for 100,000 particles, 15 slices per beam,
and one turn:

| Metric | Result |
|---|---:|
| maximum absolute coordinate difference | `1.03948e-17` |
| maximum component relative error | `2.69058e-9` |
| luminosity relative error | `2.73872e-16` |

The fast package tests also cover the slingshot/source-centroid identity, a
finite-difference six-dimensional symplectic Jacobian check with transported
source covariance, the default-on compatibility switch, and the zero-width
finite-result case on CPU and CUDA.

The revised wavefront path passed a 20,000-particle, two-turn public CPU/CUDA
contract with maximum absolute coordinate error `1.998e-17` and luminosity
relative error `2.745e-16`. Direct tests of all three virtual drifts, with and
without the coupled covariance, had maximum absolute coordinate errors below
`1.7e-18`. A fixed-source limiting test verifies that the soft-Gaussian
one-particle map is identical to `ThinStrongBeam` for every physical drift.

For a four-turn production CUDA compatibility run, the optimized
`longitudinal_kick=false` path reproduced the pre-change electron and proton
RMS values to the printed precision (the largest printed discrepancy was
`2e-21`). This separates the performance rewrite from the intentional physics
correction.

## Benchmarks

Hardware: NVIDIA RTX 4500 Ada Generation, Float64. Production CUDA case:
2,560,000 electron macroparticles, 1,000,000 proton macroparticles, 15 slices
per beam, with luminosity evaluated every turn. Complete-turn timings include
one synchronization at each turn boundary.

| CUDA path | Steady sample | Seconds/turn | Relative |
|---|---:|---:|---:|
| pre-change transverse-only | last 3 of 4 | `3.57311` mean | `1.00x` |
| optimized transverse-only | last 3 of 4 | `0.30018` mean | `11.90x` |
| optimized corrected map | last 10 of 30 | `0.31538` mean, `0.30875` median | `11.33x` vs pre-change |

The corrected 30-turn production result ended with:

```text
electron rms = [9.494596546823183e-5, 2.3845087926347322e-4,
                9.13576848040937e-6, 1.8217428587967554e-4,
                7.001506154634315e-3, 5.49833995631348e-4]
proton rms   = [9.507189052683736e-5, 1.1898796046340674e-4,
                8.551751527411296e-6, 1.1775430762611756e-4,
                5.999995871942329e-2, 6.600004473067212e-4]
```

The four-thread CPU audit used 256,000 electron and 100,000 proton
macroparticles. Last-five means were `0.82007` seconds/turn before the change
and `0.79022` seconds/turn with the corrected map. The added physics therefore
did not degrade measured CPU throughput; the observed improvement was `3.8%`.
After adding the typed virtual-drift/coupling interface, a repeat of the same
case measured `0.80737` s/turn over the last five turns (individual samples
`0.76916`--`0.83138` s). This is `2.2%` above the earlier corrected-map sample
and inside the observed run-to-run timing spread; no material CPU regression
was resolved. The drift, coupling, longitudinal, and luminosity choices are
type-specialized outside the particle loop.

On the same RTX 4500 Ada GPU, a 300,000-particle-per-beam, 15-slice isolated
collision benchmark measured `0.07711` s mean (`0.07319` s median) for
`batch_mode=:sequential` and `0.06430` s mean (`0.06424` s median) for
`:wavefront`: a `16.6%` mean speedup (`12.2%` by median). The optional coupled
path retains the same scheduling and specialized moment/kick kernels.

## Soft-Gaussian versus PIC characterization

`soft_gaussian_pic_comparison.jl` applies one identical collision to cloned
live beams. With 100,000 particles per beam, 15 slices, and a 128 x 128 CIC
PIC mesh, the uncoupled soft solver differed from PIC by `8.531e-4` in
luminosity. Final transverse RMS-size relative differences were between
`6.71e-6` and `3.47e-4`; longitudinal RMS sizes agreed below `1.54e-9` relative.
The measured collision times were `0.0587` s for soft-Gaussian and `0.2012` s
for PIC.

Enabling `include_sigma_xy` changed the soft/PIC luminosity discrepancy to
`8.426e-4`; transverse RMS-size discrepancies remained below `3.46e-4`.
These are characterization results, not an equality gate: PIC retains sampled
non-Gaussian slice structure and mesh error, while the soft solver replaces
each slice by its measured Gaussian covariance.
