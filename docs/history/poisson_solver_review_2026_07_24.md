# Poisson-Solver Review — 2026-07-24

A full review of the four strong-strong Poisson solvers: consistency between
source, docstrings and documentation; re-derivation of every theory note against
the implementation; a comparison with open-source practice; per-phase profiling on
CPU and CUDA; 200-turn production runs of every solver branch; and an error
analysis against analytic reference distributions.

Machine: 128-core host, NVIDIA RTX 4500 Ada (24 GB), Julia 1.12.4, 8 CPU threads
unless stated. Reference case throughout: `examples/strong_strong_tracking.jl`
(10 GeV e- x 275 GeV p, 12.5 mrad crab crossing, 15 normal-quantile slices).

---

## 0. Executive summary

**One real physics bug found and fixed.** The `SpectralPoissonSolver` field
normalization was an *empirically fitted* constant carrying a spurious mesh
dependence. The beam-beam coupling therefore depended on the grid, and refining
the mesh did **not** converge to the correct force. Both constants are now
derived in closed form (Section 2.2).

**Three broken-plumbing bugs found and fixed** (Section 1): the developer harness
could not be run at all from its own documented command; four driver scripts
silently drove the wrong example; and the solver-selection variable silently fell
back to PIC.

**Two documentation claims were measurably wrong** and are corrected in place: the
hybrid solver's per-particle cost (Section 2.3) and the spectral solver's
accuracy/throughput advantage over PIC (Section 2.2).

**Headline recommendation** (Section 3): measure multi-turn artificial emittance
growth per solver. The production case is many turns in a ring, where correlated
PIC noise accumulates; single-turn field error — the only thing currently
validated — is not the figure of merit, and Section 6.4 shows that below ~1e5
macroparticles per slice the solver choice does not affect the field at all.

> **Correction (added after review).** An earlier draft made replacing the
> Hockney–Eastwood kernel with Vico–Greengard–Ferrando the headline
> recommendation, on the grounds that PIC's error "stops converging above grid
> 128". That evidence does not survive scrutiny and the recommendation is
> **withdrawn for the production regime** — see Section 3.3, which documents the
> three follow-up experiments that overturned it. Short version: swapping
> Octopus's integrated log kernel for a crude node-sampled one changes the
> round-beam field error by **0%**, so the kernel is not the error bottleneck
> there and replacing it buys nothing. VGF remains worth evaluating for
> high-aspect-ratio beams only, where kernel quality does measurably matter.

**Measured results that change existing guidance:**

| finding | evidence |
| --- | --- |
| The Gaussian-subtracted hybrid costs **~2x PIC at production size**, not the 1.2-1.6x on record — the recorded ratio was measured at 1/5 production size, and the extra cost scales with particle count. At production, `pic128` is 2x faster than `gpic64` *and* better converged. | Section 5.2(3) |
| The soft-Gaussian solver returns a luminosity **1.1% high** versus converged PIC — its Gaussian-slice approximation, visible in an observable. | Section 5.2(2) |
| The hybrid is nevertheless the **most accurate mesh solver at every aspect ratio**, and grid-independently so (hybrid@48 beats PIC@256 at 11:1). | Section 6.2 |
| **Below ~1e5 macroparticles per slice the mesh-solver choice stops mattering** — shot noise dominates and PIC, the hybrid, and spectral agree within ~7% at 1e4 (3.56e-3 to 3.84e-3). | Section 6.4 |
| `green_type=:standard` is **17x worse in p95** than `:integrated` at 25:1 aspect ratio — but **identical (1.00x) for round beams**. Kernel quality matters only at high aspect ratio. | Sections 6.2, 3.3 |
| TSC deposition helps the **hybrid** consistently but never helps plain PIC. | Section 6.2 |
| All four CUDA PIC execution options are worth **2.3x-3.3x** and change no physics. | Section 5.2(1) |
| The largest single CPU cost in PIC is **slice gather/copy (35%)**, which CUDA already avoids and CPU does not. | Section 4.3(1) |
| The solver cost ranking **inverts between CPU and CUDA**: spectral `(127,383)` is 2.3x *faster* than PIC on CPU and 1.78x *slower* on CUDA; the hybrid is +25% on CPU and +97% on CUDA. Platform must be stated with any cost claim. | Sections 5.2, 5.4 |

---

## 1. Source / documentation / docstring consistency

### 1.1 Bugs found and fixed

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | **high** | `test/examples/*.jl` compute the package path as `@__DIR__/../src/Octopus.jl`, but they live two levels deep, so this resolves to `test/src/Octopus.jl`. The documented command `julia --project=. test/examples/strong_strong_tracking.jl` fails outright with `SystemError`. | path corrected to `../../src` |
| 2 | **high** | `validation/strong_strong_pic_extreme_benchmark.jl`, `validation/strong_strong_diagnostics_benchmark.jl`, `profiling/profile_strong_strong_cuda.jl`, `profiling/profile_soft_gaussian.jl` set ~15 `OCTOPUS_*` toggles and then `include` **`examples/strong_strong_tracking.jl`** — the *clean* example, which since commit `8cb1fca` reads no environment variables at all. All four silently ran a fixed 200-macroparticle 2-turn CPU case instead of the configured benchmark. | retargeted to `test/examples/strong_strong_tracking.jl` |
| 3 | **high** | Those same scripts set `OCTOPUS_POISSON_SOLVER`, which nothing reads; the harness reads `OCTOPUS_SOLVER`. `profile_soft_gaussian.jl` therefore profiled PIC, not the soft-Gaussian solver. | renamed to `OCTOPUS_SOLVER` |
| 4 | medium | `OCTOPUS_SOLVER` was documented as `pic \| spectral \| gaussian` but only branched on `"spectral"`; `gaussian` silently fell back to PIC, and `gaussian_pic` was unreachable. This violates the AGENTS.md rule "Do not accept silently ignored non-default requests". | all four solvers selectable; unknown name now errors |
| 5 | **high** | `SpectralPoissonSolver` field scale was a fitted constant with a spurious grid dependence — see Section 2.2. | derived constants |
| 6 | medium | `GaussianPICPoissonSolver`'s `coupling_tol` is stored, validated, and reported, but **never read by any runtime code** — the coupled (rotated) subtraction of the theory note's §7 does not exist, so any finite value was silently ignored. Same AGENTS.md violation as bug 4. `configuration_report` also contained dead code (`x == Inf ? :resolved : :resolved`). | a finite `coupling_tol` now throws with a pointer to §7; the option reports as `:inactive_dependency` |
| 7 | low | `batch_mode` is consumed **only** by the CUDA paths (`pic_cuda.jl`, `gaussian_pic_cuda.jl`); the CPU path merely validates it and always uses collision-time order. Both solver schemas nevertheless declared it supported on `CPUThreadsBackend`, so `configuration_report` marked a non-default CPU value `:resolved` and `_preflight_solver_configurations!` issued no warning. | `supported_backends=(CUDABackend,)` on both schemas; it now reports `:inactive_backend` on CPU |

Bugs 1–3 are all fallout from the docs/examples reshuffle in commits
`8cb1fca`/`b547e17`. Nothing in the test suite exercises those scripts, which is
why they rotted silently.

### 1.2 Consistency checks that passed

- `validate_element_metadata()`, `validate_configuration_metadata()`, and
  `validate(PublicConfigurationEffectivenessContract())` all pass.
- `docs/registry_snapshot.md` is byte-identical to a fresh
  `write_registry_snapshot()` — genuinely up to date.
- Every solver's `solver_option_schema` matches its struct fields and constructor
  defaults (enforced by `validate_configuration_metadata`).
- Baseline `Pkg.test()` passes before and after every change in this review.

### 1.3 Documentation inconsistencies corrected

- **Option names.** `docs/theory/gaussian_subtracted_pic_solver.md` documented
  `gaussian_subtract_margin_sigma`, `gaussian_subtract_neutralize`,
  `gaussian_subtract_coupling_tol`. The implementation went a different route — a
  separate `GaussianPICPoissonSolver` type composing a `PICPoissonSolver`, with
  fields `margin_sigma`, `neutralize`, `coupling_tol`. Corrected.
  `docs/todo.md` step 1 still describes the abandoned "add a mode to
  `PICPoissonSolver`" design and should be read as historical.
- **Coupled branch.** Section 7 of the same note reads as if the coupled
  (rotated) subtraction exists. It does not; the branch is now explicitly marked
  NOT YET IMPLEMENTED.
- **Conventions.** Section 1 of that note simultaneously asserted
  `dp = -grad(phi)` and `dp = 2*kbb*E`, which cannot both hold. Rewritten to
  separate the physical potential (`lap(phi)=rho`) from the PIC grid potential
  (`phi_PIC = -2*pi*phi`) and to derive the factor 2 rather than assert it.

---

## 2. Theory re-derivation versus implementation

Every formula in `docs/theory/` was re-derived from scratch and checked against
the code numerically. Script: `verify_derivations.jl` (methodology reproduced in
Section 8).

### 2.1 What is correct

| Checked quantity | Result |
|---|---|
| `beam_beam_longitudinal_kick.md` §4.2 `dpz = ½F·C_u + ¼H_U:A_u` vs `_cp_covariance_kick` | matches |
| Bassetti–Erskine Hessian `U_xx`,`U_yy` vs central finite differences of the implemented kick (round, 2:1, 11:1, 25:1, 20 sample points) | worst relative error **1.1e-8** (finite-difference limited) |
| Poisson consistency `U_xx + U_yy = -4*pi*kbb*rho_unit` | worst relative error **3.7e-15** |
| `_round_gaussian_hessian` `f`, `f'` derivatives | exact |
| Round/elliptic branch continuity of `gaussian_beambeam_kick` | error scales linearly with `(sigx-sigy)/sigx`, no jump |
| `K(-r) = -K(r)` and axis-swap symmetry | exact to 0.0 |
| `GaussianPICPoissonSolver` covariance `pz` term vs the soft-Gaussian `_cp_covariance_kick` | **bit-identical** (0.0 relative) |
| erf-integrated CIC/TSC node profiles (§5 of the hybrid note) vs `_gpic_gaussian_profile!` | algebraically identical; TSC `sigma→0` limit reproduces the discrete weights (1/8, 3/4, 1/8) |
| PIC `kbb` convention vs soft-Gaussian `kbb` | consistent: both give `dp = kbb_phys * w_slice * K_BE` |
| Hybrid analytic add-back amplitude (`½ N_s`, not `N_s`) | correct in code; the **doc** had the factor 2 wrong (now fixed) |

The synchro-beam longitudinal-kick note is, as far as this review can determine,
correct and correctly implemented. The sign conventions are subtle
(`StrongTransverseMoments` stores raw covariances and applies `S = -u` inside
`_transport_transverse_moments`) but they are internally consistent, and the
hybrid solver's independent re-derivation of the same term agrees bit-for-bit.

### 2.2 The spectral normalization bug (fixed)

`spectral.jl` carried

```julia
const _SPECTRAL_FIELD_C0_GRID = -25.72     # fitted
const _SPECTRAL_FIELD_C0_FREE = 12.518     # fitted
scale = _SPECTRAL_FIELD_C0_GRID * Nx * Ny / (2(Nx+1) * 2(Ny+1))
```

described in-source as "fixed by a least-squares fit of the field onto the
analytic normalized kick".

**Derivation.** The mode solve returns the continuum coefficients of the
potential solving `lap(phi) = rho` for a unit-charge source, so
`phi = ln(r)/(2*pi)` and `E = -grad(phi) = -r_hat/(2*pi*r)`. The caller applies
the physical `kbb * w_slice` exactly as `GaussianPoissonSolver` does, so the
returned field must be in the Bassetti–Erskine convention,
`K_BE -> 2*r_hat/r`, i.e.

```
K_BE = -4*pi*E
```

FFTW's `RODFT00` and `REDFT00` each carry a factor 2, so the `:grid` chain
produces `Exg = 2*scale*E`, giving **`scale = -2*pi`** exactly; the `:grid_free`
direct sum gives `Ex = -scale*E`, giving **`scale = +4*pi`** exactly. Neither
depends on `Nx, Ny`.

**Measurement.** Least-squares scale needed to match the exact Bassetti–Erskine
field for a deterministic Gaussian quantile source (`domain_factor = 16`);
0 means the normalization is exactly right:

| mesh | fitted constant (before) | derived constant (after) |
| --- | ---: | ---: |
| 64 x 64 | +4.9e-2 | +4.1e-2 |
| 128 x 128 | +2.3e-3 | +9.9e-3 |
| 256 x 256 | −1.3e-2 | +1.9e-3 |
| 511 x 511 | −1.9e-2 | **−5.4e-5** |
| grid_free 48 x 48 | +3.3e-3 | **−5.1e-4** |

The "before" column is the bug in one line: the error bottoms out around
128 x 128 (where the constant was calibrated) and then gets **worse** with
refinement, converging to a ~2% coupling error. The "after" column converges
monotonically to zero. Independently, the `:grid_free` fitted constant `12.518`
is 0.39% below the exact `4*pi = 12.5664`.

**Consequences.**

1. The beam-beam coupling strength depended on `grid`. Changing the mesh changed
   the physical force, so grid-convergence studies were measuring the wrong
   thing.
2. Part of the repeatedly reported "spectral matches PIC/analytic to ~1% at
   production settings" was this normalization error, not the macroparticle
   graininess floor it was attributed to.

**Why it was never caught.** Every spectral accuracy check in the repository —
including `validation/spectral_poisson_field_validation.jl` and the
`test/runtests.jl` accuracy testsets — normalizes the residual **after removing a
least-squares constant**, and is therefore structurally blind to an error in the
overall coupling. Confirmed: re-running that validation after the fix reproduces
its historical numbers unchanged.

**Guard added.** A new `test/runtests.jl` testset, "Spectral field absolute
normalization is derived, not fitted", checks the required scale *without*
removing any constant (fails at 0.982 with the old constant, passes at 1.001
with the derived one) and asserts that refining the mesh moves the required
correction toward 1, not away from it.

**Doc claims corrected.** `docs/theory/spectral_sine_poisson_solver.md` §13
claimed the CUDA spectral path is "about 4x faster than the PIC CUDA path"; that
came from an isolated collide-only loop which inflates PIC by churning its
adaptive Green cache, and the project's own `todo.md` already records ~1.4x
*slower* through the full beamline. §16 claimed the solver is "clearly better for
flat beams" than PIC; that comparison removes the least-squares constant, and
Section 6 below shows the ranking reverses once the actual coupling is included.
Both are now qualified in place, and a new §18 records the derivation.

### 2.3 Hybrid-solver cost claim corrected

`gaussian_subtracted_pic_solver.md` §9 claimed the per-particle Bassetti–Erskine
add-back is "comparable to the grid interpolation it runs alongside". Measured
per directed slice-pair interaction at the production case:

| term | time |
| --- | ---: |
| erf profile build `g_x,g_y` | 2.8e-5 s |
| grid subtraction | 1.1e-5 s |
| slice moments | 3.2e-4 s |
| **Bassetti–Erskine add-back (2/field particle)** | **2.68e-2 s** |
| PIC field interpolation + kick (comparison) | 2.4e-3 s |
| whole PIC(128,128) interaction (comparison) | 2.5e-2 s |

The two grid terms are negligible exactly as claimed, but the analytic add-back
is ~11x the interpolation and roughly **doubles** the CPU cost of an interaction.
Corrected in place.

---

## 3. Comparison with open-source practice, and recommendations

### 3.1 Where Octopus sits

| code | transverse field solve | notes |
| --- | --- | --- |
| **Octopus `PICPoissonSolver`** | Hockney–Eastwood zero-padded FFT with an *integrated* (cell-averaged) log Green function, adaptive per-slice-pair box, cached Green FFT | |
| **BeamBeam3D** (Qiang, Furman, Ryne) | same Hockney family, plus a **shifted** Green function so the mesh need only cover the larger of the two beams | the reference implementation for strong-strong colliders; Octopus already cites it |
| **Xsuite / PyHEADTAIL-PyPIC** | FFT Poisson solver with **Integrated Green Functions**, uniform rectangular grid | same algorithmic family as Octopus |
| **Octopus `SpectralPoissonSolver`** | Dirichlet-box double sine series (DST-I) | uncommon for beam-beam; the Dirichlet box is an approximation to open BC |
| **Octopus `GaussianPICPoissonSolver`** | control-variate / delta-f hybrid | genuinely uncommon in accelerator codes; closest relatives are delta-f gyrokinetics (Parker & Lee) |

So Octopus's PIC core is squarely mainstream, and its `green_type=:integrated`
default matches the Xsuite/PyPIC choice. The shifted Green function of
BeamBeam3D is *already* effectively present: `_pic_align_grid_origins` plus the
separate source/field grid origins in `_pic_green!` implement exactly the
shifted-kernel idea.

### 3.2 Recommendations for the production case (multi-turn circular collider)

Ordered by expected value.

**(1) Measure multi-turn artificial emittance growth. Highest value.** Moved to
the top after the analysis in Section 3.3 removed the case for a kernel change.
Details in item (2) below, which is unchanged.

**(2) The multi-turn noise question, in detail.** The production use case is
many turns in a ring, which is precisely where PIC noise is known to accumulate
into *artificial* emittance growth: the particles' phase-space rotation
correlates the numerical noise turn to turn and enhances the growth
(Kesting & Franchetti derive a scaling law for it). Two concrete follow-ups:
  - Run the existing solvers with the beam-beam kick on but the *physics*
    switched off (or at very low `kbb`) for a few thousand turns and measure the
    emittance growth floor per solver and per grid. That number, not the
    single-turn field error of Section 6, is the figure of merit for the
    production case.
  - Note that `GaussianPICPoissonSolver` should be *structurally* better here:
    the coherent field is analytic, so the grid only carries the small residual,
    and the noise-driven part of the force is proportional to the residual
    amplitude. Section 6 confirms the systematic gain; the multi-turn noise gain
    is the claim worth measuring next.

**(3) Symplectic PIC is the principled fix.** Qiang's symplectic PIC model
(PRAB 21, 054201) shows that a conventional (non-symplectic) PIC gives a
*different* emittance growth than the symplectic gridless reference, and that the
non-symplectic result only converges to it as the step size shrinks. Octopus
already cares about symplecticity elsewhere (`validation/symplecticity_validation.jl`,
the `NonSymplectic6DMap` classification of the Lorentz crossing maps), so this is
consistent with the existing architecture rather than a new concern.

**(4) Keep the spectral solver as a cross-check; stop optimizing it.** Its
thin-axis mode count grows linearly with the aspect ratio (the note's own §16), it
needs ~1000 modes for sub-1% at 25:1, and it is the least accurate solver measured
in Section 6 at production settings once the coupling is no longer fitted away. On
CUDA it is 1.78x PIC's turn time at the recommended grid (Section 5.1); on CPU it
is *faster* than PIC at that grid, but at materially worse field accuracy, so that
is not a reason to prefer it either. Its real value is as an independent
cross-check with a completely different discretization error — a good reason to
keep it, and a poor reason to invest further. The "CPU 6D performance campaign"
listed in `todo.md` as the top open item rests on a measurement at the
over-resolved `(128,1024)/16` grid and should be demoted (done).

**(5) Cheap, contained wins already visible in the profiles** — see Section 4.3.

**(6) If field accuracy is the goal, the cheapest real win is the field
gradient, not the kernel.** See Section 3.3.

### 3.3 Withdrawn: the case for replacing the Hockney kernel

An earlier draft of this review recommended swapping the Hockney-Eastwood
free-space convolution for the Vico-Greengard-Ferrando truncated kernel, arguing
that PIC's p95/max error "stops converging above grid 128 — the Hockney
signature". Three follow-up experiments overturned that argument. They are
recorded here because the conclusion matters more than the original claim.

**Experiment 1 — is the saturation real, or a test artifact?** The deterministic
quantile lattice has a hard edge at 3.02 sigma, and the original measurement
evaluated the field out to +-4 sigma, i.e. *outside* the source, near the box
boundary where `_pic_field!` falls back to one-sided differences. Repeating on
nested windows (round beam, median error):

| window | 64² | 128² | 256² | 512² |
| --- | ---: | ---: | ---: | ---: |
| +-1 sigma | 4.21e-3 | 9.77e-4 | 2.29e-4 | 1.72e-4 |
| +-2 sigma | 3.03e-3 | 7.50e-4 | 2.03e-4 | 1.90e-4 |
| +-3 sigma | 1.17e-3 | 5.02e-4 | 2.51e-4 | 3.76e-4 |
| +-4 sigma (outside source) | 7.98e-4 | 4.07e-4 | 2.78e-4 | 2.52e-4 |

The outer-window degradation *is* partly an edge artifact, but the stall persists
at +-1 sigma. What survives is that 64 -> 128 -> 256 converges at ~4.3x per
doubling — **clean second order** — and then flattens at 512, where the grid cell
(0.0125 sigma) approaches the lattice spacing of the deterministic source
(~0.0063 sigma) and the test itself stops being well posed. So the saturation is
not established as a property of the solver, and second-order convergence is the
*expected* behaviour of Hockney **and** of CIC deposition alike. This experiment
cannot attribute the error to either.

**Experiment 2 — which component actually dominates?** Swap the kernel and change
nothing else. `green_type=:integrated` (cell-averaged log) versus `:standard`
(node-sampled log) are substantially different kernels of different accuracy:

| case | 48² | 64² | 128² | 256² |
| --- | ---: | ---: | ---: | ---: |
| round | 0.98x | 0.97x | **1.00x** | 0.98x |
| 5:1 | 0.98x | 0.99x | 1.08x | 1.18x |
| 11:1 (production) | 1.18x | 1.20x | 1.47x | 1.70x |
| 25:1 | 2.97x | 2.20x | 3.11x | 2.75x |
| bi-Gaussian (all four) | — | — | 0.96-0.98x | — |
| randomly sampled (1e4-1e6) | — | 1.00x | 1.00x | — |

(ratio = standard / integrated median error; 1.00x means the kernel is irrelevant)

**For round beams, mild aspect ratios, bi-Gaussian sources, and every
realistically sampled case, two quite different kernels give the same answer to
within 0-2%.** The free-space kernel contributes essentially none of the error in
that regime, so a third, better kernel cannot help there. Kernel quality only
becomes significant as the beam flattens (1.5-1.7x at the production 11:1, up to
3.1x at 25:1).

**Experiment 3 — is it the field gradient?** `_pic_field!` takes the gradient of
phi with second-order central differences. Replacing it with a fourth-order stencil,
changing nothing else (round beam, +-2 sigma):

| grid | 2nd-order median | 4th-order median | gain |
| --- | ---: | ---: | ---: |
| 64² | 3.03e-3 | 1.83e-3 | 1.65x |
| 128² | 7.50e-4 | 4.66e-4 | 1.61x |
| 256² | 2.03e-4 | 1.69e-4 | 1.20x |

Real, but partial. So the round-beam PIC error budget is roughly **kernel ~0%,
finite-difference gradient ~40%, deposition and interpolation the remainder**
(and TSC does not improve the last part — Section 6.2 — because it trades
interpolation error for extra smoothing).

**Conclusions.**

1. **The VGF recommendation is withdrawn for round and mild-aspect beams.** It
   targets the only component measured to contribute nothing.
2. **VGF is still worth evaluating for flat beams**, where the kernel demonstrably
   matters (3.1x at 25:1). Note that Octopus already uses the integrated kernel,
   which captures most of that gain; VGF's *marginal* benefit over IGF will be
   smaller than IGF's over the naive kernel, and should be measured before being
   assumed.
3. **The cheapest genuine accuracy win is a fourth-order gradient in
   `_pic_field!`** — ~1.6x median at production grids, ~10 lines, no new FFT, no
   change to the cache or the CUDA structure. That is now the recommended field-
   accuracy item, ahead of any kernel work.
4. **None of this moves the needle at production statistics.** Section 6.4 shows
   that at 1e5-1e6 macroparticles per slice the shot-noise floor is at or above
   the systematic error for every solver. Field-accuracy work has limited payoff
   until the multi-turn noise question (item 1) is answered.

**Methodological note.** The original claim came from reading a p95/max column
across a grid sweep without a controlled experiment isolating the component
blamed. The kernel A/B in Experiment 2 was already present in the Section 6 data
and would have contradicted the claim immediately had it been checked first.

---

## 4. Per-phase profiling

### 4.1 Method

Each leaf phase is timed in isolation for one representative directed slice-pair
interaction at the production case (2.56M e- / 1.024M p, 15 normal-quantile
slices, so ~170k e- and ~68k p per slice), then scaled by the 450 directed
interactions in a turn (225 slice pairs x 2 directions).

Two caveats, both stated rather than hidden:

- The measurement uses the electron slice as source and the proton slice as
  field. In a real turn half the interactions have those roles reversed, so
  source-side phases (bounds scan, deposit) are over-weighted and field-side
  phases (interpolation, Bassetti–Erskine add-back) are *under*-weighted by up to
  ~2.5x. The add-back conclusion is therefore conservative.
- `green_fft` is timed as a build. With the default `green_cache=:slice_pair`
  most interactions hit the cache, so its amortized share is smaller than shown;
  the `:none` column of Section 5 measures the difference end to end.

### 4.2 CPU breakdown, per directed interaction and per turn

All times in seconds. "per turn" = per-interaction x 450.

**PIC, `grid=(128,128)`, CIC, `green_type=:integrated`**

| phase | per interaction | per turn | share |
| --- | ---: | ---: | ---: |
| slice extract + copy | 8.79e-3 | 3.955 | **34.9%** |
| source bounds scan | 3.22e-4 | 0.145 | 1.3% |
| Green kernel + FFT (build) | 5.45e-3 | 2.454 | 21.6% |
| deposition (2 boundaries) | 3.23e-3 | 1.454 | 12.8% |
| Poisson FFT convolution (2) | 2.61e-3 | 1.174 | 10.4% |
| field finite difference (2) | 1.43e-4 | 0.065 | 0.6% |
| interpolate + kick | 2.40e-3 | 1.078 | 9.5% |
| luminosity | 2.25e-3 | 1.010 | 8.9% |
| **total** | **2.52e-2** | **11.33** | |

**PIC branch variants** (same layout, totals only)

| branch | per turn | vs default |
| --- | ---: | ---: |
| `(128,128)` CIC integrated | 11.33 | 1.00x |
| `(128,128)` TSC integrated | 14.21 | 1.25x |
| `(128,128)` CIC standard | 9.37 | 0.83x |
| `(64,64)` CIC integrated | 7.94 | 0.70x |
| `(256,256)` CIC integrated | 27.75 | 2.45x |

At `(256,256)` the Green build plus the Poisson FFT are 65% of the cost; at
`(64,64)` the slice extract alone is 53%.

**Gaussian-subtracted PIC — the phases it adds on top of PIC**

| phase | per interaction | per turn | share of the extra |
| --- | ---: | ---: | ---: |
| slice moments | 3.2e-4 | 0.146 | 1.2% |
| erf profile `g_x,g_y` | 2.8e-5 | 0.013 | 0.1% |
| grid subtraction | 1.1e-5 | 0.005 | 0.0% |
| **Bassetti-Erskine add-back** | 2.68e-2 | **12.05** | **98.7%** |
| **total extra** | 2.71e-2 | **12.21** | |

The extra is essentially all analytic add-back, and it is as large as the entire
PIC(128,128) interaction it augments. It is independent of the grid (identical at
`(64,64)`, `(128,128)`, CIC and TSC), which is exactly why the hybrid's economics
are "coarser grid at equal accuracy", not "free accuracy".

**Spectral, `method=:grid`**

| phase | (127,383) d=8 | (128,1024) d=16 | (127,127) d=16 |
| --- | ---: | ---: | ---: |
| drifted-source snapshot | 0.426 | 0.423 | 0.427 |
| deposition | 1.233 | 1.244 | 1.215 |
| forward DST | 0.556 | 5.799 | 0.171 |
| mode division | 0.032 | 0.095 | 0.010 |
| **field reconstruction (5 transforms)** | **1.832** | **16.807** | 0.505 |
| interpolate + kick | 0.660 | 0.662 | 0.662 |
| luminosity | 1.113 | 1.168 | 1.086 |
| **total** | **5.85** | **26.20** | **4.08** |

These exclude the slice extract/copy (~3.96 s/turn), which the spectral 6D path
also pays. The reconstruction share (31% / 64% / 12%) is the "7 transforms per
solve" cost the optimization history already identified, and it is what makes
`(128,1024)` uncompetitive.

**Soft-Gaussian**

| phase | per interaction | per turn | share |
| --- | ---: | ---: | ---: |
| slice moments | 1.14e-3 | 0.513 | 8.2% |
| per-particle kick + luminosity | 1.28e-2 | 5.769 | 91.8% |
| **total** | 1.40e-2 | **6.28** | |

### 4.3 What the profile says

1. **The single largest CPU cost in PIC is not physics — it is slice gathering.**
   `_pic_extract_slice` plus `_pic_copy_coords` allocate and copy six `Float64`
   vectors per slice and are called for both the source and the field slice of
   every directed interaction: ~35% of the cost at `(128,128)`, 53% at `(64,64)`.
   The CUDA path already solved exactly this problem — `cuda_indexed_wavefront`
   works through slice index vectors without gathering or reordering canonical
   particle storage — and it is the default there. **There is no CPU equivalent.**
   Porting the indexed approach to the CPU interaction is the single highest-value
   CPU optimization available, and it benefits PIC, GaussianPIC, and the spectral
   6D path alike (all three call the same two helpers).

2. **Luminosity is ~9-19% of the cost and is computed every turn by default.**
   `luminosity_schedule=EveryNSteps(step=10)` is already implemented and exposed
   on `PICPoissonSolver`; it is simply not the default. For production multi-turn
   runs where luminosity is a diagnostic rather than the observable of interest,
   this is free money.

   **Resolved after review.** Originally only `PICPoissonSolver` and
   `GaussianPICPoissonSolver` had the option. Measuring the two that lacked it
   settled what to do with each:

   | solver | luminosity cost | action |
   | --- | ---: | --- |
   | `SpectralPoissonSolver` | ~11% of a turn (separate density-overlap deposit) | **option added**, CPU + CUDA |
   | `GaussianPoissonSolver` | **0%** (−3.7%, i.e. noise) | deliberately **not** added |

   The soft-Gaussian luminosity is a by-product of the kick: `_cp_covariance_kick`
   computes the Gaussian density factor unconditionally because the `pz` term needs
   `expterm`, and the `COMPUTE_LUMINOSITY` flag gates only one multiply. Adding a
   schedule there would be a knob that does nothing, which AGENTS.md explicitly
   warns against; the omission is now documented in `?AbstractPoissonSolver` as
   intentional rather than left looking like an oversight.

   An earlier draft of this section put spectral's luminosity share at 19%. That
   compared it against a phase sum that excluded the slice extract/copy the
   spectral 6D path also pays; the corrected share is ~11%.

3. **`green_type=:standard` is cheaper to build (0.89 vs 2.45 s/turn) and much
   less accurate for flat beams** (Section 6: 17x worse p95 at 25:1). The
   docstring's "the integrated Green function is the robust default" understates
   this; it should say the standard kernel is unsuitable for high-aspect-ratio
   beams.

4. **TSC costs +25% on CPU and buys nothing for plain PIC** (Section 6 shows
   `pic_TSC` is not better than `pic_CIC`) — **but it is consistently the best
   option for the hybrid** (`gpic_TSC` beats `gpic_CIC` at almost every grid and
   aspect ratio). That interaction is not documented anywhere.

5. **The `bounds_scan` is negligible (1.3%)**, contradicting an initial suspicion.
   Worth recording because the loop *looks* expensive (a serial 8-way min/max over
   every source particle) but is memory-bandwidth bound and cheap in context.

### 4.4 CUDA breakdown

From the built-in `StrongStrongDiagnostics(pic_timing=true, pic_timing_detail=true)`
path at production size, steady-state turn, 225 slice pairs. **Read these as
shares, not absolute times**: `pic_timing_detail` synchronizes every subphase and
disables the async overlap, so the total (0.89 s) is ~3x the production turn time
(0.318 s). That is documented behaviour of the diagnostic, and it is what makes
the attribution meaningful — each phase's serialized cost becomes visible.

| phase | (128,128) | (256,256) | `green_cache=:none` |
| --- | ---: | ---: | ---: |
| slicing | 1.0% | 0.7% | 0.9% |
| gather | 4.0% | 2.8% | 4.9% |
| prepare source bounds | 8.0% | 5.9% | 7.7% |
| prepare field bounds | 7.8% | 5.7% | 7.5% |
| deposition | 3.1% | 2.1% | 3.0% |
| Green kernel build | 9.3% | **18.3%** | **15.6%** |
| Green FFT | 9.1% | 8.8% | 3.4% |
| **field FFT** | **31.9%** | **36.7%** | **32.2%** |
| field derivative | 1.0% | 1.0% | 0.9% |
| kick | 3.0% | 2.4% | 2.8% |
| luminosity | 10.7% | 7.7% | 10.2% |
| scatter | 11.1% | 7.8% | 10.7% |
| *(serialized total)* | 0.889 s | 1.270 s | 0.933 s |

Observations:

1. **The FFT convolution dominates on GPU (32-37%)**, where on CPU it was only
   10%. The GPU has already optimized away the data movement that dominates the
   CPU (gather 4.0% + scatter 11.1%, against ~35% for the CPU slice extract),
   leaving the transform as the wall. Note this says where the *time* goes, not
   where the *error* goes: Section 3.3 shows the kernel contributes ~0% of the
   round-beam error, so "better accuracy at equal FFT count" is not obtainable by
   changing the kernel in that regime.
2. **Bounds preparation is 15.8% on GPU** (source + field) against 1.3% on CPU —
   an inversion worth noting. The GPU pays for a batched reduction where the CPU
   pays a cheap streaming scan.
3. **The Green cache saves what it claims.** Disabling it moves the Green kernel
   build from 9.3% to 15.6% of a larger total; end to end with async enabled
   (Section 5.1) that is 0.318 -> 0.372 s/turn, 1.17x.
4. **Luminosity is 10.7% on GPU too**, computed every turn by default —
   reinforcing the `luminosity_schedule` recommendation.
5. **`GaussianPICPoissonSolver` emits no CUDA phase records at all.** Requesting
   `pic_timing=true` on the hybrid yields turn times but an empty
   `pic_phase_timings(task)`. The option is accepted and silently does nothing for
   that solver — the same class of issue as bug 4 in Section 1.1, though only a
   diagnostic. `SpectralPoissonSolver` has no CUDA phase instrumentation either.
6. The `(64,64)` run recorded a one-off 0.64 s allocator `reclaim` event (42% of
   that turn) and is excluded from the table as an artifact, not a phase cost.

---

## 5. 200-turn production runs

Every branch of every solver, 200 turns of the full example beamline (crab
cavities, Lorentz boost pair, one-turn optics, chromaticity, radiation damping for
the electrons), with luminosity and moment observers active every turn. Reported
values are the mean over **turns 100-200** (steady state); `std` is over the same
window.

### 5.1 CUDA, full production size

**CUDA (RTX 4500 Ada), 2.56M e- / 1.024M p, mean over turns 100-200**

| solver / branch | s/turn | std | vs PIC(128) | luminosity (cm^-2 s^-1) | e- rms x (m) | e- rms y (m) | p rms x (m) | p rms y (m) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Soft-Gaussian** | | | | | | | | |
| batch_mode=:wavefront (default) | 0.2369 | 0.0010 | 0.74x | 1.1117e+30 | 9.4910e-05 | 9.1836e-06 | 9.4940e-05 | 8.4889e-06 |
| batch_mode=:sequential | 0.3105 | 0.0154 | 0.98x | 1.1117e+30 | 9.4910e-05 | 9.1836e-06 | 9.4940e-05 | 8.4889e-06 |
| include_sigma_xy=true | 0.2684 | 0.0011 | 0.84x | 1.1117e+30 | 9.4910e-05 | 9.1837e-06 | 9.4940e-05 | 8.4889e-06 |
| longitudinal_kick=false | 0.2212 | 0.0006 | 0.70x | 1.1117e+30 | 9.4910e-05 | 9.1836e-06 | 9.4940e-05 | 8.4889e-06 |
| **PIC** | | | | | | | | |
| grid=(128,128) CIC integrated cache=:slice_pair (default) | 0.3181 | 0.0048 | 1.00x | 1.0988e+30 | 9.4724e-05 | 9.1743e-06 | 9.4980e-05 | 8.4926e-06 |
| grid=(128,128) cache=:none | 0.3719 | 0.0131 | 1.17x | 1.0989e+30 | 9.4711e-05 | 9.1737e-06 | 9.4989e-05 | 8.4925e-06 |
| deposit_method=:TSC | 0.3367 | 0.0052 | 1.06x | 1.0982e+30 | 9.4739e-05 | 9.1737e-06 | 9.4976e-05 | 8.4926e-06 |
| green_type=:standard | 0.3317 | 0.1255 | 1.04x | 1.0981e+30 | 9.4726e-05 | 9.1960e-06 | 9.4983e-05 | 8.4922e-06 |
| batch_mode=:sequential | 0.8556 | 0.0309 | 2.69x | 1.0989e+30 | 9.4711e-05 | 9.1737e-06 | 9.4989e-05 | 8.4925e-06 |
| longitudinal_kick=false | 0.2735 | 0.0501 | 0.86x | 1.0988e+30 | 9.4724e-05 | 9.1743e-06 | 9.4980e-05 | 8.4926e-06 |
| grid=(64,64) | 0.2520 | 0.0045 | 0.79x | 1.0945e+30 | 9.4844e-05 | 9.1740e-06 | 9.4935e-05 | 8.4929e-06 |
| grid=(256,256) | 0.4739 | 0.0423 | 1.49x | 1.0998e+30 | 9.4717e-05 | 9.1751e-06 | 9.4995e-05 | 8.4924e-06 |
| cuda_indexed_wavefront=false | 0.7313 | 0.0587 | 2.30x | 1.0988e+30 | 9.4724e-05 | 9.1743e-06 | 9.4980e-05 | 8.4926e-06 |
| cuda_wavefront_fft=false | 0.8139 | 0.1447 | 2.56x | 1.0989e+30 | 9.4711e-05 | 9.1737e-06 | 9.4989e-05 | 8.4925e-06 |
| cuda_batch_fft=false | 0.9226 | 0.1830 | 2.90x | 1.0989e+30 | 9.4711e-05 | 9.1737e-06 | 9.4989e-05 | 8.4925e-06 |
| cuda_async=false | 1.0531 | 0.2053 | 3.31x | 1.0989e+30 | 9.4711e-05 | 9.1737e-06 | 9.4989e-05 | 8.4925e-06 |
| **Gaussian-subtracted PIC** | | | | | | | | |
| grid=(64,64) (recommended setting) | 0.6259 | 0.0084 | 1.97x | 1.0956e+30 | 9.4709e-05 | 9.1733e-06 | 9.4985e-05 | 8.4920e-06 |
| grid=(128,128) | 0.7187 | 0.0648 | 2.26x | 1.0990e+30 | 9.4694e-05 | 9.1745e-06 | 9.4997e-05 | 8.4922e-06 |
| neutralize=false | 0.6891 | 0.0067 | 2.17x | 1.0990e+30 | 9.4694e-05 | 9.1745e-06 | 9.4997e-05 | 8.4922e-06 |
| margin_sigma=0 | 0.7264 | 0.0065 | 2.28x | 1.0990e+30 | 9.4701e-05 | 9.1747e-06 | 9.4997e-05 | 8.4922e-06 |
| deposit_method=:TSC | 0.8042 | 0.0035 | 2.53x | 1.0984e+30 | 9.4700e-05 | 9.1750e-06 | 9.4996e-05 | 8.4922e-06 |
| **Spectral** | | | | | | | | |
| grid=(127,383) d=8 (recommended setting) | 0.5670 | 0.0218 | 1.78x | 1.0988e+30 | 9.4718e-05 | 9.1824e-06 | 9.4988e-05 | 8.4923e-06 |
| grid=(128,1024) d=16 | 0.8821 | 0.0225 | 2.77x | 1.0960e+30 | 9.4924e-05 | 9.2475e-06 | 9.4960e-05 | 8.4921e-06 |
| grid=(127,127) d=16 | 0.5295 | 0.0291 | 1.66x | 1.0770e+30 | 9.4680e-05 | 9.2308e-06 | 9.4901e-05 | 8.4957e-06 |
| grid=(127,383) d=8 longitudinal_kick=false | 0.4839 | 0.0560 | 1.52x | 1.1307e+30 | 9.5191e-05 | 9.8343e-06 | 9.4972e-05 | 8.4792e-06 |
| field_precision=:single | 0.3958 | 0.0031 | 1.24x | 1.0988e+30 | 9.4729e-05 | 9.1791e-06 | 9.4986e-05 | 8.4923e-06 |


### 5.2 What the CUDA runs show

1. **All four CUDA PIC execution options are real and large, and none of them
   changes the physics.** Disabling them costs 2.3x-3.3x, and every disabled
   variant reproduces the enabled one's luminosity to 5 digits and both beams'
   rms to 5 digits:

   | disabled option | s/turn | vs default |
   | --- | ---: | ---: |
   | `cuda_async=false` | 1.0531 | 3.31x |
   | `cuda_batch_fft=false` | 0.9226 | 2.90x |
   | `cuda_wavefront_fft=false` | 0.8139 | 2.56x |
   | `batch_mode=:sequential` | 0.8556 | 2.69x |
   | `cuda_indexed_wavefront=false` | 0.7313 | 2.30x |
   | *(all enabled, default)* | 0.3181 | 1.00x |

   This is a clean validation of every branch: pure-performance options that are
   bit-consistent in the observable. It also quantifies the value of
   `cuda_indexed_wavefront` (2.3x) — the optimization that has no CPU counterpart
   (Section 4.3).

2. **Luminosity converges with grid, and the numbers identify each solver's
   systematic bias:**

   | solver | luminosity (cm^-2 s^-1) | vs converged PIC(256) |
   | --- | ---: | ---: |
   | PIC (64,64) | 1.0945e30 | -0.5% |
   | PIC (128,128) | 1.0988e30 | -0.1% |
   | PIC (256,256) | 1.0998e30 | (reference) |
   | GaussianPIC (64,64) | 1.0956e30 | -0.4% |
   | GaussianPIC (128,128) | 1.0990e30 | -0.1% |
   | Spectral (127,383)/d8 | 1.0988e30 | -0.1% |
   | Spectral (127,127)/d16 | 1.0770e30 | **-2.1%** |
   | Soft-Gaussian | 1.1117e30 | **+1.1%** |

   - The **soft-Gaussian solver is 1.1% high**. That is its physical
     approximation showing up in an observable: it forces every slice to be
     Gaussian, so it cannot represent the beam-beam-induced non-Gaussian core
     that reduces overlap. This is the clearest quantitative statement in the
     review of what the grid solvers buy.
   - **Spectral at `(127,127)/d16` is 2.1% low** — the thin direction is
     unresolved, exactly as Section 6.2 predicts. At the recommended `(127,383)/d8`
     it lands on the PIC value.
   - **`longitudinal_kick=false` changes luminosity by +2.9%** for spectral
     (1.1307e30) — a genuine physics difference, not a numerical one, and a
     reminder that the transverse-only branches are comparison tools rather than
     production settings.

3. **The Gaussian-subtracted hybrid costs ~2x PIC at production size, not the
   1.2-1.6x on record.** `gpic128` is 0.719 s vs `pic128` 0.318 s (2.26x);
   `gpic64` is 0.626 s vs `pic128` 0.318 s (1.97x). The
   `strong_strong_gaussian_pic_optimization_history.md` ratios (1.6x and 1.2x)
   were measured at **512k/256k**, one fifth of production. The extra cost is the
   per-field-particle Bassetti-Erskine add-back, which scales with particle count
   while the grid work does not — so the ratio necessarily degrades with beam size.
   **The practical consequence: at production size, `pic128` dominates `gpic64`
   outright — it is 2x faster *and* returns the better-converged luminosity.** The
   hybrid's case now rests entirely on its systematic field accuracy (Section 6),
   which is real and large, and on the multi-turn-noise argument that has not yet
   been measured (Section 3.2).

4. **`field_precision=:single` delivers 1.43x on spectral** (0.396 vs 0.567 s) with
   identical luminosity to 4 digits. The docstring's "not intended for production"
   is a defensible position, but the measured cost of that position is now on
   record.

5. **`green_type=:standard` shows a 26x larger turn-time variance** (std 0.126 vs
   0.005 s) at the same mean. Combined with its flat-beam accuracy collapse
   (Section 6.2), there is no configuration in which it is the right choice for
   this case.

### 5.3 CPU, 1/10 production size

Full production size is impractical on CPU for 22 branches x 200 turns, so the CPU
sweep uses 256k e- / 102.4k p (1/10). The grid work is unchanged by that scaling
while the particle work shrinks by 10x, so **CPU and CUDA rows are not directly
comparable to each other**; compare within a column.

**Timing caveat — the `s/turn` column of the 200-turn table is contended.** The
22-branch sweep was executed as four concurrent 8-thread groups. The control pair
`pic128_cic_int_cache` and `pic128_sequential` is the *identical* code path on CPU
(`batch_mode` is CUDA-only; see bug 7) yet differs by 24% there. Luminosity and
moment columns are deterministic and unaffected, so the 200-turn table below is
authoritative for **physics** but not for **timing**.

A separate **uncontended serial pass** (one job at a time, 60 turns, mean over
turns 30-60) was therefore run for the branches whose cost ordering matters. Its
control pair differs by only 4.8%, confirming the contention diagnosis and setting
a ~5% noise floor:

| branch | s/turn (serial) | vs PIC(128) | s/turn (contended) |
| --- | ---: | ---: | ---: |
| soft-Gaussian | 0.965 | 0.18x | 0.714 |
| **PIC (128,128)** | **5.312** | **1.00x** | 6.543 |
| PIC (128,128) `batch_mode=:sequential` *(control — identical CPU code)* | 5.570 | 1.05x | 5.260 |
| PIC (64,64) | 3.931 | 0.74x | 4.754 |
| GaussianPIC (64,64) | 6.662 | 1.25x | 6.678 |
| GaussianPIC (128,128) | 7.940 | 1.49x | 7.784 |
| Spectral (127,383)/d8 | 2.301 | 0.43x | 1.843 |
| Spectral (127,127)/d16 | 1.468 | 0.28x | 0.776 |

**Use the serial column for CPU cost claims.** The 60-turn window is less
JIT-settled than the 200-turn one, so absolute values run a little high; the
ratios are the meaningful output.

**CPU (8 threads), 256k e- / 102.4k p, mean over turns 100-200**

| solver / branch | s/turn | std | vs PIC(128) | luminosity (cm^-2 s^-1) | e- rms x (m) | e- rms y (m) | p rms x (m) | p rms y (m) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Soft-Gaussian** | | | | | | | | |
| batch_mode=:wavefront (default) | 0.7138 | 0.0987 | 0.11x | 1.1112e+30 | 9.4993e-05 | 9.1658e-06 | 9.4840e-05 | 8.5151e-06 |
| batch_mode=:sequential | 0.7260 | 0.0700 | 0.11x | 1.1112e+30 | 9.4993e-05 | 9.1658e-06 | 9.4840e-05 | 8.5151e-06 |
| include_sigma_xy=true | 0.7165 | 0.0689 | 0.11x | 1.1112e+30 | 9.4978e-05 | 9.1675e-06 | 9.4840e-05 | 8.5150e-06 |
| longitudinal_kick=false | 0.6994 | 0.0538 | 0.11x | 1.1112e+30 | 9.4993e-05 | 9.1658e-06 | 9.4840e-05 | 8.5151e-06 |
| **PIC** | | | | | | | | |
| grid=(128,128) CIC integrated cache=:slice_pair (default) | 6.5431 | 0.6039 | 1.00x | 1.0972e+30 | 9.4795e-05 | 9.1997e-06 | 9.4988e-05 | 8.5060e-06 |
| grid=(128,128) cache=:none | 6.4327 | 0.8520 | 0.98x | 1.0969e+30 | 9.4867e-05 | 9.2014e-06 | 9.5004e-05 | 8.5061e-06 |
| deposit_method=:TSC | 6.2835 | 0.2411 | 0.96x | 1.0969e+30 | 9.4778e-05 | 9.1920e-06 | 9.4986e-05 | 8.5058e-06 |
| green_type=:standard | 6.1881 | 0.4141 | 0.95x | 1.0964e+30 | 9.4802e-05 | 9.2236e-06 | 9.4992e-05 | 8.5056e-06 |
| batch_mode=:sequential | 5.2598 | 0.2782 | 0.80x | 1.0972e+30 | 9.4795e-05 | 9.1997e-06 | 9.4988e-05 | 8.5060e-06 |
| longitudinal_kick=false | 4.9604 | 0.1602 | 0.76x | 1.0972e+30 | 9.4795e-05 | 9.1995e-06 | 9.4988e-05 | 8.5059e-06 |
| grid=(64,64) | 4.7535 | 0.5324 | 0.73x | 1.0952e+30 | 9.4717e-05 | 9.1789e-06 | 9.4938e-05 | 8.5068e-06 |
| grid=(256,256) | 15.6453 | 0.5007 | 2.39x | 1.0972e+30 | 9.4917e-05 | 9.2173e-06 | 9.5005e-05 | 8.5053e-06 |
| **Gaussian-subtracted PIC** | | | | | | | | |
| grid=(64,64) (recommended setting) | 6.6781 | 0.3445 | 1.02x | 1.0961e+30 | 9.4692e-05 | 9.1930e-06 | 9.4974e-05 | 8.5053e-06 |
| grid=(128,128) | 7.7840 | 0.3066 | 1.19x | 1.0976e+30 | 9.4694e-05 | 9.2049e-06 | 9.4991e-05 | 8.5056e-06 |
| neutralize=false | 8.0609 | 0.2970 | 1.23x | 1.0976e+30 | 9.4694e-05 | 9.2049e-06 | 9.4991e-05 | 8.5056e-06 |
| margin_sigma=0 | 8.2266 | 0.1121 | 1.26x | 1.0974e+30 | 9.4762e-05 | 9.2087e-06 | 9.4993e-05 | 8.5055e-06 |
| deposit_method=:TSC | 8.4132 | 0.4062 | 1.29x | 1.0973e+30 | 9.4720e-05 | 9.2096e-06 | 9.4985e-05 | 8.5055e-06 |
| **Spectral** | | | | | | | | |
| grid=(127,383) d=8 (recommended setting) | 1.8427 | 0.0546 | 0.28x | 1.0976e+30 | 9.4843e-05 | 9.1833e-06 | 9.4996e-05 | 8.5068e-06 |
| grid=(128,1024) d=16 | 8.7359 | 0.4349 | 1.34x | 1.0985e+30 | 9.4721e-05 | 9.1769e-06 | 9.4959e-05 | 8.5071e-06 |
| grid=(127,127) d=16 | 0.7757 | 0.0532 | 0.12x | 1.0775e+30 | 9.4667e-05 | 9.2296e-06 | 9.4893e-05 | 8.4782e-06 |
| grid=(127,383) d=8 longitudinal_kick=false | 0.5285 | 0.0338 | 0.08x | 1.1288e+30 | 9.5403e-05 | 9.8942e-06 | 9.5005e-05 | 8.4984e-06 |
| method=:grid_free (48,48) (CPU only) | 8.4251 | 0.1529 | 1.29x | 1.0597e+30 | 9.4552e-05 | 9.2756e-06 | 9.4863e-05 | 8.4790e-06 |

### 5.4 What the CPU runs show

Only conclusions that clear the ~25% contention floor:

1. **Spectral at the recommended `(127,383)/d=8` is 2.3x faster than PIC(128,128)
   on CPU** (2.30 vs 5.31 s/turn, serial) — the opposite of the CUDA ordering,
   where it is 1.78x *slower*. The reason is visible in Section 4.2: on CPU, PIC
   pays a large slice-gather and Green-FFT cost that spectral partly avoids, while
   on GPU those are already cheap and spectral's 7 transforms per solve dominate.
   **This invalidates the premise of the "CPU 6D spectral performance campaign"
   listed as the top open item in `todo.md`** — that item was measured at the
   over-resolved `(128,1024)/16` grid, which is 1.34x PIC here.
2. **The hybrid is substantially more competitive on CPU than on GPU, but it is
   not free anywhere.** Serial: `gpic64` is 1.25x PIC(128) on CPU against 1.97x on
   CUDA; `gpic128` is 1.49x against 2.26x. (The contended run put `gpic64` at
   1.02x — that was contention noise, and the serial pass corrects it.) The
   explanation is the same: the per-particle Bassetti-Erskine add-back is a large
   fraction of a *fast* GPU baseline and a smaller fraction of a *slow* CPU one.
   The practical reading is a platform-dependent trade rather than a verdict:
   - **On CPU**, `gpic64` costs +25% over `pic128` and buys ~4x lower systematic
     field error at 11:1 (Section 6.2: 2.4e-4 vs 9.7e-4). That is a defensible
     trade.
   - **On CUDA**, the same accuracy costs +97%, and `pic128` additionally returns
     the better-converged luminosity. There the trade is much weaker.
3. **`grid=(256,256)` costs 2.4x `(128,128)`** and buys no measurable luminosity
   change at this beam size, consistent with the CUDA runs.
4. **`method=:grid_free` is not a production path**: 8.43 s/turn (1.29x PIC) and a
   luminosity 3.4% below the converged value (1.0597e30 vs 1.0972e30) because 48x48
   modes cannot resolve the 11:1 beams — the same failure Section 6.2 measures in
   the field error.
5. Luminosity agrees with the CUDA runs to ~0.1-0.2% for every solver, confirming
   that the 10x macroparticle reduction does not bias the observable at this level.
6. **The hybrid's own knobs barely matter at production settings.** `neutralize`,
   `margin_sigma`, and `deposit_method` span 7.78-8.41 s/turn (inside the
   contention floor, so unrankable on cost) and 1.0973-1.0976e30 in luminosity —
   a 0.03% spread. That is the expected result at `margin_sigma=5`, where the
   subtracted Gaussian leaks only ~1e-6 of its mass and neutralization has almost
   nothing left to correct: these knobs are insurance for tighter boxes, not
   tuning parameters. The same holds on CUDA (Section 5.1).


---

## 6. Error analysis against analytic distributions

### 6.1 Method

Per-point transverse-kick error `|K_num - K_exact|` normalized by `max|K_exact|`
over an 81x81 field grid spanning +-4 sigma; median / p95 / max reported.
Reference is the exact Bassetti-Erskine field, by superposition for the
bi-Gaussian sources.

**No least-squares constant is removed.** This is the "as used" error, and it
differs deliberately from `validation/spectral_poisson_field_validation.jl` and
`validation/gaussian_pic_field_validation.jl`, which both calibrate out an overall
constant and therefore cannot see a coupling error (Section 2.2).

Three source families:

- **A. deterministic Gaussian quantile lattice** (400x400 = 160k points) — the
  systematic grid-discretization error with shot noise removed;
- **B. deterministic bi-Gaussian** — the fair test, since the hybrid can only
  subtract a *single* Gaussian fitted to the combined moments;
- **C. randomly sampled Gaussian** at 1e4 / 1e5 / 1e6 macroparticles — separates
  the shot-noise floor from the grid error.

### 6.2 A. Systematic error, deterministic Gaussian source (median)

| solver | grid | round | 5:1 | 11:1 (production e-) | 25:1 |
| --- | --- | ---: | ---: | ---: | ---: |
| soft-Gaussian | -- | 6.3e-5 | 4.1e-4 | 4.8e-4 | 5.1e-4 |
| PIC CIC | 48² | 1.1e-3 | 2.8e-3 | 3.4e-3 | 4.0e-3 |
| PIC CIC | 64² | 8.0e-4 | 1.8e-3 | 2.5e-3 | 2.9e-3 |
| PIC CIC | 128² | 4.1e-4 | 7.1e-4 | 9.7e-4 | 1.2e-3 |
| PIC CIC | 256² | 2.8e-4 | 4.0e-4 | 4.9e-4 | 7.6e-4 |
| PIC CIC standard-Green | 48² | 1.1e-3 | 2.8e-3 | 4.0e-3 | **1.2e-2** |
| **hybrid CIC** | 48² | 1.6e-4 | 2.1e-4 | 2.4e-4 | 3.2e-4 |
| **hybrid CIC** | 64² | 1.6e-4 | 2.0e-4 | 2.4e-4 | 3.2e-4 |
| **hybrid CIC** | 128² | 1.8e-4 | 2.6e-4 | 3.0e-4 | 4.5e-4 |
| **hybrid TSC** | 64² | 1.6e-4 | 1.9e-4 | **1.7e-4** | **1.6e-4** |
| spectral `:grid` | (127,127)/d16 | 1.2e-3 | 4.2e-3 | 1.5e-2 | -- |
| spectral `:grid` | (127,383)/d8 | 5.8e-3 | 2.2e-3 | 3.9e-3 | 5.3e-3 |
| spectral `:grid` | (128,1024)/d16 | -- | -- | 3.5e-3 | 4.4e-3 |
| spectral `:grid_free` | 48x48/d16 | 3.6e-4 | 1.8e-2 | 4.7e-2 | 7.4e-2 |

Findings:

1. **The hybrid is the most accurate mesh solver at every aspect ratio, and its
   error is essentially grid-independent** (1.6e-4 to 4.5e-4 across 48²-256²).
   The doc's headline claim — hybrid at 48-64 matches or beats PIC at 128 — is
   confirmed and if anything understated: hybrid@48 beats PIC@256 at 11:1
   (2.4e-4 vs 4.9e-4).
2. **TSC is the better deposition for the hybrid, though not for plain PIC.**
   `gpic_TSC` wins at nearly every grid/aspect ratio (best overall: 1.6e-4 at
   25:1, 64²), while `pic_TSC` is never better than `pic_CIC`. Undocumented.
3. **`green_type=:standard` collapses for flat beams**: at 25:1/48² the median is
   3x worse and the p95 is **17x** worse (1.9e-1 vs 1.1e-2) than `:integrated`.
   The docstring should say this outright.
4. **PIC's tail error stops converging above grid 128.** Round-beam p95:
   1.4e-2 (48²) -> 7.4e-3 (64²) -> 2.0e-3 (128²) -> **2.5e-3 (256²)**; max
   1.7e-2 -> 9.0e-3 -> 3.7e-3 -> **5.0e-3**. Same at 11:1 (max 1.2e-2 at 128²
   -> 1.8e-2 at 256²). This is the second-order Hockney-Eastwood signature and is
   the concrete motivation for recommendation (1) in Section 3.2.
5. **Spectral is the least accurate solver at production settings** once the
   coupling is not fitted away: at 11:1 the recommended `(127,383)/d8` gives
   3.9e-3 median against PIC(128)'s 9.7e-4 and the hybrid's 3.0e-4. The
   round-beam `(127,383)/d8` number (5.8e-3) is worse than `(127,127)/d16`
   because `domain_factor=8` is too small a Dirichlet box for a round beam — the
   box, not the mesh, dominates there.
6. **`:grid_free` is excellent for round beams (3.6e-4, better than PIC@128) and
   unusable for flat ones** (7.4e-2 at 25:1) — 48 modes cannot resolve the thin
   axis, exactly as the theory note's flat-beam caveat predicts.

### 6.3 B. Bi-Gaussian source (grid 128², median)

| source | soft-Gaussian | PIC CIC | hybrid CIC | hybrid/PIC gain |
| --- | ---: | ---: | ---: | ---: |
| +20% at (1.5,0)sigma | 6.0e-3 | 4.6e-4 | 2.5e-4 | 1.8x |
| +30% narrow at (1.5,0)sigma | 4.9e-3 | 3.3e-4 | 2.1e-4 | 1.6x |
| +20% at (2,2)sigma (coupled) | 5.3e-2 | 4.4e-4 | 4.0e-4 | 1.1x |
| +10% far at (3,0)sigma | 3.2e-2 | 5.3e-4 | 4.7e-4 | 1.1x |

1. **The soft-Gaussian solver degrades by 1-2 orders of magnitude** on
   non-Gaussian sources (up to 5.3e-2), which is the entire reason the grid
   solvers exist. Worth stating plainly: for a Gaussian source it is the *most*
   accurate solver in the suite (6.3e-5), and for a perturbed one it is by far the
   worst.
2. **The hybrid degrades gracefully to parity with PIC**, never worse — the
   doc's claim, confirmed. The weakest case is the diagonally offset (coupled)
   perturbation, which is precisely what the unimplemented rotated subtraction of
   §7 would recover.

### 6.4 C. Shot-noise floor versus systematic floor (round beam, median)

| n_macro | soft-Gaussian | PIC 64² | PIC 128² | hybrid 64² | hybrid 128² | spectral (127,127) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1e4 | 2.2e-3 | 3.6e-3 | 3.8e-3 | 3.6e-3 | 3.8e-3 | 3.7e-3 |
| 1e5 | 9.3e-4 | 1.3e-3 | 1.2e-3 | 1.1e-3 | 1.1e-3 | 1.6e-3 |
| 1e6 | 3.5e-4 | 7.9e-4 | 4.8e-4 | **4.5e-4** | 4.6e-4 | 1.2e-3 |
| deterministic (systematic floor) | 6.3e-5 | 8.0e-4 | 4.1e-4 | 1.6e-4 | 1.8e-4 | 1.2e-3 |

1. **At 1e4 macroparticles every mesh solver gives the same answer** (3.56e-3 to
   3.84e-3, a ~7% spread that is itself sampling scatter). The choice among PIC,
   the hybrid, and spectral is irrelevant below ~1e5 macroparticles per slice;
   shot noise dominates completely. This is the most practically useful number in
   the review — it says where solver quality starts to matter at all. (The
   soft-Gaussian solver is the exception at 2.18e-3: it fits moments rather than
   resolving the sampled density, so it is *less* noise-sensitive on a genuinely
   Gaussian source — and correspondingly blind on a non-Gaussian one, Section 6.3.)
2. **At 1e6 the hybrid at 64² already matches PIC at 128²** (4.5e-4 vs 4.8e-4) —
   the claimed "coarser mesh at equal accuracy" result, reproduced under random
   sampling rather than a quantile lattice.
3. **The shot-noise contribution is separable**: PIC@128 gives 4.8e-4 at 1e6
   against a 4.1e-4 systematic floor, so noise adds ~2.5e-4 in quadrature. The
   hybrid's systematic floor (1.8e-4) is already well below the 1e6 shot-noise
   floor, which is exactly the caveat the theory note makes: **the hybrid's gain
   is in the coherent field, and single-turn per-particle kick errors barely
   improve.** Whether that coherent gain converts into better multi-turn dynamics
   is the open question flagged in Section 3.2(2).

---

## 7. Differences versus other codes and papers, and open items

### 7.1 Where Octopus differs from published practice

Flagged as requested, whether or not action is implied.

1. **Hockney-Eastwood versus Vico-Greengard-Ferrando.** Octopus, Xsuite/PyPIC and
   BeamBeam3D all use the Hockney family. The published position since 2021 is
   that VGF should replace it — same cost, spectral instead of second-order
   convergence. Octopus's measured tail-error saturation above grid 128
   (Section 6.2) is consistent with that critique. **This is a difference from
   current best practice, not from current common practice.**
2. **Shifted Green function.** BeamBeam3D's headline algorithmic contribution is a
   *shifted* Green function so the mesh covers only the larger beam, enabling
   accurate long-range parasitic collisions. Octopus already has the equivalent
   (separate source/field grid origins in `_pic_green!`, aligned by
   `_pic_align_grid_origins`), so there is no gap here — but the theory notes never
   say so, and a reader comparing against Qiang et al. would not know.
3. **The control-variate hybrid has no accelerator-physics precedent.** The
   nearest published relatives are delta-f particle methods in gyrokinetics
   (Parker & Lee 1993, already cited). Section 6 supports the idea strongly; it is
   an original contribution and should be presented as one.
4. **The Dirichlet-box spectral solver is unusual for beam-beam.** Open-boundary
   Hockney/VGF is the norm precisely because the 2D log potential does not decay.
   The measured domain-size sensitivity (Section 6.2, finding 5) is the reason.
5. **Symplecticity of the field solve.** Qiang's symplectic PIC (PRAB 21, 054201)
   shows that conventional PIC and a symplectic gridless reference give *different*
   emittance growth. All four Octopus solvers are conventional in this sense. The
   project already tracks symplecticity of the *maps*
   (`validation/symplecticity_validation.jl`, `NonSymplectic6DMap`); the field
   solve is not covered by that machinery.

### 7.2 Open items

| item | status |
| --- | --- |
| Coupled (rotated) Gaussian subtraction, `coupling_tol < Inf` | unimplemented; Section 6.3 shows this is exactly the weakest hybrid case |
| Multi-turn artificial emittance growth per solver | **not measured**; this is the real production figure of merit and the most valuable follow-up |
| Fourth-order gradient in `_pic_field!` | recommended (~1.6x median field accuracy, ~10 lines, no new FFT); Section 3.3 |
| VGF Green kernel as a third `green_type` | **downgraded** — withdrawn for round/mild beams (kernel contributes ~0% of the error there); evaluate for high aspect ratio only |
| CPU indexed-slice path (no gather/copy) | recommended, not implemented; ~35% of CPU PIC cost |
| `luminosity_schedule` on `SpectralPoissonSolver` | **IMPLEMENTED** (CPU + CUDA, 32-assertion effectiveness test). `GaussianPoissonSolver` deliberately left without it — measured 0% cost, see Section 4.3(2) |
| PIC p95/max error saturating above grid 128 | **attribution retracted** (Section 3.3): partly a hard-edge/box-boundary artifact of the test, and the kernel is measurably not responsible |
| `_spectral_box` sizes the Dirichlet box from **undrifted** beam coordinates, then deposits **drifted** slices; `_spectral_field_grid!` silently drops out-of-box particles | not triggered at production settings (drift adds ~90 um to a 619 um extent inside an 848 um half-box) but unguarded — a smaller `domain_factor` or longer bunch would silently lose charge |
| `docs/todo.md` "CPU 6D spectral performance campaign" listed as the top open item | should be demoted: Section 5 measures spectral `(127,383)/d8` as *faster* than PIC(128) on CPU, and Section 6 shows it is the least accurate solver at production settings |
| `docs/todo.md` internal contradiction: the hybrid section says "CUDA path is the remaining work" in one paragraph and "CUDA path complete and optimized" in the next | corrected |

---

## 8. Reproduction

All measurements in this review are reproducible from the repository. The
throwaway drivers used here live outside the repo; the equivalent in-repo commands
are:

```bash
# consistency and metadata
julia --project=. -e 'include("src/Octopus.jl"); using .Octopus;
    validate_element_metadata(); validate_configuration_metadata();
    validate(PublicConfigurationEffectivenessContract()); write_registry_snapshot()'

# full regression suite, including the new absolute-normalization guard
julia --threads=8 --project=. -e 'using Pkg; Pkg.test()'

# solver selection now works for all four (previously only pic/spectral)
OCTOPUS_SOLVER=gaussian_pic OCTOPUS_TURNS=1 OCTOPUS_N_MACRO=800 \
  julia --project=. test/examples/strong_strong_tracking.jl

# 200-turn production run, CUDA
OCTOPUS_USE_GPU=1 OCTOPUS_SOLVER=pic OCTOPUS_TURNS=200 \
  OCTOPUS_N_MACRO_ELE=2560000 OCTOPUS_N_MACRO_PRO=1024000 \
  OCTOPUS_RECORD_TURN_TIMES=1 \
  julia --project=. test/examples/strong_strong_tracking.jl

# CUDA per-phase breakdown
OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_PIC_TIMING=1 OCTOPUS_CUDA_PIC_TIMING_DETAIL=1 \
  julia --project=. test/examples/strong_strong_tracking.jl

# field accuracy
julia --project=. validation/gaussian_pic_field_validation.jl
julia --project=. validation/gaussian_pic_bigaussian_validation.jl
julia --project=. validation/spectral_poisson_field_validation.jl
julia --project=. validation/pic_gaussian_field_validation.jl
```

Note that the last three calibrate out a least-squares constant and so cannot
reproduce Section 6's absolute numbers; the "as used" metric of Section 6.1 is
the difference.

CPU timing comparisons must be run **one job at a time**. Running several
multi-threaded Octopus jobs concurrently inflates per-turn times by up to 24% and
does so unevenly across configurations (Section 5.3).

The four driver scripts fixed in Section 1.1 (bugs 2-3) are now functional again:

```bash
julia --project=. validation/strong_strong_pic_extreme_benchmark.jl
julia --project=. validation/strong_strong_diagnostics_benchmark.jl
julia --project=. profiling/profile_strong_strong_cuda.jl
julia --project=. profiling/profile_soft_gaussian.jl
```

---

## 9. References consulted

Beyond the references already carried by the theory notes (Bassetti-Erskine 1980;
Hockney & Eastwood 1981; Hirata, Moshammer & Ruggiero 1993; Parker & Lee 1993;
Qiang, Furman & Ryne 2004; Leunissen, Schmidt & Ripken 2000; Xu et al. 2024):

1. J. Qiang, M. A. Furman, R. D. Ryne, "A parallel particle-in-cell model for
   beam-beam interaction in high energy ring colliders", *J. Comput. Phys.* 198
   (2004) 278 — the shifted Green function and the BeamBeam3D architecture.
   <https://amac.lbl.gov/~jiqiang/beambeam3d.pdf>
2. J. Qiang, M. A. Furman, R. D. Ryne, "Strong-strong beam-beam simulation using a
   Green function approach", *Phys. Rev. ST Accel. Beams* **5**, 104402 (2002).
   <https://journals.aps.org/prab/abstract/10.1103/PhysRevSTAB.5.104402>
3. F. Vico, L. Greengard, M. Ferrando, "Fast convolution with free-space Green's
   functions", *J. Comput. Phys.* 323 (2016) 191. <https://arxiv.org/pdf/1604.03155>
4. J. Zou, E. Kim, A. J. Cerfon, "FFT-based free space Poisson solvers: why
   Vico-Greengard-Ferrando should replace Hockney-Eastwood" (2021).
   <https://arxiv.org/abs/2103.08531>
5. "A Massively Parallel Performance Portable Free-space Spectral Poisson Solver"
   (2024) — DCT reformulation bringing VGF to Hockney-level cost/memory.
   <https://arxiv.org/html/2405.02603>
6. J. Qiang, "A symplectic particle-in-cell model for space-charge beam dynamics
   simulation", *Phys. Rev. Accel. Beams* **21**, 054201 (2018).
   <https://arxiv.org/abs/1801.05288>
7. F. Kesting, G. Franchetti, "Propagation of numerical noise in particle-in-cell
   tracking", *Phys. Rev. ST Accel. Beams* **18**, 114201 (2015) — correlated PIC
   noise and artificial emittance growth over many turns.
   <https://arxiv.org/pdf/1503.04646>
8. G. Iadarola et al., "Xsuite: an integrated beam physics simulation framework"
   (2023) — FFT Poisson solver with integrated Green functions, from
   PyHEADTAIL-PyPIC. <https://arxiv.org/pdf/2310.00317>,
   <https://xsuite.readthedocs.io/en/latest/beambeam.html>


---

# Follow-up — 2026-07-25

Second pass: implement the accepted recommendations, close what can be closed,
measure the multi-turn figure of merit the first pass left open, and re-read the
source. Everything below is new work on top of the review above; where it
supersedes an earlier number, that is stated.

## 10. Changes made

| change | kind | default behaviour |
| --- | --- | --- |
| `field_derivative=:second\|:fourth` on `PICPoissonSolver` | new option | `:second`, **bit-identical** to all earlier results |
| `luminosity_schedule` on `SpectralPoissonSolver` (CPU + CUDA) | new option | `nothing`, every turn — unchanged |
| `_spectral_box_drifted` for the spectral 6D box | bug fix | unchanged at the recommended `domain_factor=8` |
| `coupling_tol` finite values now throw | bug fix | default `Inf` unchanged |
| `batch_mode` declared CUDA-only | metadata fix | no numerical change |

### 10.1 Fourth-order field gradient (opt-in)

`_pic_field!` takes `E = -grad(phi)` on the mesh. The default two-point central
stencil is `O(h^2)`; `field_derivative=:fourth` uses

    E_x = [ (phi[i+2] - phi[i-2]) + 8*(phi[i-1] - phi[i+1]) ] / (12h)

in the interior, falling back to the second-order form on the first ring inside
the boundary and the existing one-sided formulas on the boundary itself. Verified
`O(h^4)` (16x error reduction per halving against an analytic function, versus 4x
for the current stencil).

Implemented on CPU and in **all three** CUDA kernels (single, batched, wavefront),
since the flag would otherwise be silently ignored on some execution paths.
Inherited by `GaussianPICPoissonSolver` through composition.

Measured static field error (round beam, +-2 sigma, median, deterministic source):

| grid | `:second` | `:fourth` | gain |
| --- | ---: | ---: | ---: |
| 64² | 3.03e-3 | 1.83e-3 | 1.65x |
| 128² | 7.50e-4 | 4.66e-4 | 1.61x |
| 256² | 2.03e-4 | 1.69e-4 | 1.20x |

Verified: default == `:second` bit-for-bit; `:fourth` changes the result (so the
option reaches its consumer); CPU/CUDA agree to 7e-17 in coordinates and 1e-15 in
luminosity for **both** settings.

**It does not help multi-turn noise** — see Section 11. It improves the coherent
field only, which is exactly what the theory predicts, and is therefore worth
enabling for field-accuracy studies and not worth enabling for its own sake.

## 11. Multi-turn artificial emittance growth

The first pass called this the real production figure of merit and did not measure
it. Now measured.

**Method.** Full example beamline, CUDA, production statistics (2.56M e- /
1.024M p), 15 slices. The electron radiation damping time is scaled from 4000 to
**100 turns** and the run is **1000 turns = 10 damping times**, so the electron
beam reaches its damping/excitation equilibrium. The **proton beam has no
radiation element in this lattice**, so it is undamped and integrates whatever
noise the solver injects — that is the sensitive channel. A no-collision control
gives the pure-lattice baseline. Emittance is the rms
`sqrt(<x^2><px^2> - <x px>^2)`, sampled every 25 turns.

| config | proton eps_x total | proton eps_y total | electron eps_x equilibrium |
| --- | ---: | ---: | ---: |
| no collision (control) | **-0.000%** | +0.000% | 1.64e-07 |
| soft-Gaussian (analytic) | **+0.405%** | +0.896% | 1.80e-08 |
| PIC (64,64) | **+1.101%** | +4.276% | 2.04e-08 |
| PIC (128,128) | +0.637% | +4.065% | 2.00e-08 |
| PIC (128,128) `:fourth` | +0.689% | +4.154% | 2.00e-08 |
| PIC (256,256) | +0.697% | +4.186% | 1.99e-08 |
| GaussianPIC (64,64) TSC | +0.639% | +5.121% | 1.96e-08 |
| GaussianPIC (128,128) | +0.617% | +4.473% | 1.98e-08 |
| Spectral (127,383)/d8 | +0.748% | +3.631% | 2.00e-08 |

**Findings.**

1. **The control is flat to 1e-10 per turn.** The lattice, observers, and
   emittance machinery contribute nothing, so the metric is clean.
2. **The soft-Gaussian solver is the low-noise reference.** It computes the field
   from slice moments, so it carries essentially no grid noise; its +0.405% is
   the *physical* beam-beam response plus the settling transient. Every grid
   solver's excess over it is the numerical contribution.
3. **`grid=(64,64)` is measurably unsafe.** It is the only configuration whose
   proton emittance is still *rising* at the end of the run (1.0046 -> 1.0053 ->
   1.0070 -> 1.0110 over the last quarter) rather than plateauing. Every other
   configuration flattens by turn ~300. This is the clearest practical result in
   the review: **the static field error of a coarse grid understates its
   multi-turn cost.**
4. **At `grid >= 128` the solvers are indistinguishable on this metric.** PIC128,
   PIC256, GaussianPIC64, GaussianPIC128 and spectral all land in +0.62-0.75%
   (x). Refining beyond 128 buys nothing dynamically, which is a stronger
   statement than the luminosity convergence in Section 5.2.
5. **`field_derivative=:fourth` does not reduce noise growth** (+0.689% versus
   +0.637%, i.e. no improvement, within scatter). Expected: the fourth-order
   stencil removes systematic truncation error, and multi-turn growth is driven
   by macroparticle shot noise, which it cannot touch. This is a useful negative
   result — it means the option should not be sold as a dynamics improvement.
6. **The hybrid at 64 matches plain PIC at 128** dynamically (+0.639% versus
   +0.637%), reproducing in the dynamic metric the "coarser mesh at equal
   quality" claim that Section 6 established statically.

**Caveats, stated rather than buried.** These are single-seed runs with no error
bars. The x-plane ordering among the `>= 128` configurations (0.617-0.748%) is
**not resolvable** at one seed, and the y-plane spread (3.6-5.1%) is wider still
and should not be used to rank solvers. Only two statements survive that
limitation: the control is flat, and `grid=(64,64)` is worse and still growing.
Repeating with 3-5 seeds per configuration would be needed to rank the rest.

## 12. Recommendation: which PIC configuration to use

For the production case (10 GeV e- x 275 GeV p, ~11:1 flat beams, 15 slices,
CUDA, >= 1e5 macroparticles per slice):

> **`PICPoissonSolver(grid=(128,128), deposit_method=:CIC,
> green_type=:integrated, green_cache=:slice_pair)` with the CUDA execution
> options at their defaults.**

The reasoning, from the measurements rather than from preference:

| criterion | why (128,128) wins |
| --- | --- |
| multi-turn noise (Section 11) | not measurably worse than anything else, including PIC256 and both hybrids; `(64,64)` **is** measurably worse |
| luminosity convergence (5.2) | -0.1% against PIC(256,256); `(64,64)` is -0.5% |
| cost (5.1) | 0.318 s/turn — 1.5x cheaper than PIC256, 2.0x cheaper than GaussianPIC64, 1.8x cheaper than spectral |
| kernel choice (3.3, 6.2) | `:integrated` matters at 11:1 (1.5x better than `:standard`) and costs nothing |
| deposition | CIC; TSC costs +25% and does not help plain PIC |

**When to deviate:**

- **`GaussianPICPoissonSolver(grid=(64,64), deposit_method=:TSC)`** if the
  *coherent* field matters — low macroparticle counts, tune-shift or
  field-quality studies. It is 3-4x more accurate statically (Section 6.2) at
  equal dynamic quality. Cost: 2.0x on CUDA but only **1.25x on CPU**, so it is a
  much easier trade on CPU.
- **`field_derivative=:fourth`** for field-accuracy studies (1.6x lower median
  field error, ~free). Not for dynamics.
- **`SpectralPoissonSolver`** as an independent cross-check with completely
  different discretization error — not as a production solver (least accurate
  statically at production settings, 1.8x PIC's cost on CUDA).
- **Never `green_type=:standard`** for flat beams (17x worse p95 at 25:1).
- **Never `grid=(64,64)`** for long runs, on the evidence of Section 11.

## 13. Open items after this pass

| item | status |
| --- | --- |
| Fourth-order gradient | **done** (opt-in, CPU + 3 CUDA kernels, tested) |
| `luminosity_schedule` on spectral | **done** (CPU + CUDA, tested) |
| Spectral 6D box vs drifted source | **done** (guard + test) |
| Multi-turn emittance growth | **done** — but single-seed; needs 3-5 seeds to rank the `>= 128` configurations |
| `coupling_tol` / `batch_mode` silently ignored | **done** |
| Coupled (rotated) Gaussian subtraction | **open** — a genuine feature, not a defect; Section 6.3 shows it is exactly the weakest hybrid case |
| VGF Green kernel | **open, downgraded** — withdrawn for round/mild beams (Section 3.3); evaluate for flat beams only |
| CPU indexed-slice path | **open** — ~35% of CPU PIC cost; deliberately not attempted here because it is a pure-performance refactor of hot code with real regression risk, and this pass prioritised correctness |
| Emittance growth with error bars | **new open item** from Section 11 |

## 14. Source review coverage

Read in full and checked against the implementation: `interface.jl`, `pic_cpu.jl`,
`gaussian.jl`, `gaussian_pic.jl`, `spectral.jl`, `strong_beam.jl`, `slicing.jl`,
`SpecialMath.jl`, `radiation.jl`, `lorentz_boost.jl`, `crab_cavity.jl`, plus the
field/kick/box regions of `pic_cuda.jl` and `spectral_cuda.jl`.

New numerical checks run in this pass, all passing:

| check | result |
| --- | --- |
| Lorentz boost forward∘reverse round trip | 3.7e-11 relative |
| Boost Jacobian determinants | `sec^3` / `cos^3` as documented; product = 1 |
| Faddeeva CUDA approximation vs exact `erfcx` over the beam-beam regime | worst **3.1e-13** |
| `Linear6D` symplecticity | 1.1e-16 |
| CIC/TSC assignment weights, partition of unity and node base index | exact |
| Gaussian slice centres (conditional mean between quantiles) | formula correct |
| `_longitudinal_slices_equal_area` interpolation | correct |
| Crab cavity map derives from a single Hamiltonian | symplectic |

**Not exhaustively read:** the bulk of `pic_cuda.jl` (4396 lines) and
`gaussian_pic_cuda.jl` (825 lines). Claiming a line-by-line review of those would
overstate what was done; the practical guard there is the CPU/CUDA parity suite,
which covers every solver and now both `field_derivative` settings.


---

# Follow-up 2 — 2026-07-25 (test record)

Test runs behind the second follow-up pass. Derivations for the features below
live in `docs/theory/`: the coupled subtraction in
[`gaussian_subtracted_pic_solver.md`](../theory/gaussian_subtracted_pic_solver.md)
Section 7, and the gradient stencils plus the free-space kernels in the new
[`pic_free_space_kernels.md`](../theory/pic_free_space_kernels.md).

## 15. Coupled (rotated) Gaussian subtraction — implemented and tested

Implemented on the CPU path (CUDA raises rather than silently running the
uncoupled subtraction). Default `coupling_tol = Inf` is unchanged and
bit-identical.

**Test 15.1 — deposition against brute-force 2D quadrature.** Worst relative node
error of the deposited reference Gaussian, against direct 2D integration of the
tilted Gaussian times the same assignment function:

| $r_{xy}$ | uncoupled | coupled CIC | coupled TSC |
| ---: | ---: | ---: | ---: |
| 0.05 | 8.9e-2 | **7.7e-5** | **7.2e-5** |
| 0.20 | 4.8e-1 | **4.6e-3** | **4.4e-3** |
| 0.50 | 3.3e0 | 1.2e-1 | 1.1e-1 |

A first attempt had TSC *worse* than uncoupled (1.7e-1 against 8.5e-2). Component
testing isolated the cause to a sign error in the TSC mean-derivative
$g'=\int GW'$ — the assignment-weighted moments were already exact to 1e-15 and
CIC was already correct. After the fix all four derivatives match numerical
differentiation to ~1e-7 (finite-difference limited) for both methods.

**Test 15.2 — total field against the exact rotated Bassetti-Erskine field.**
Median relative kick error, grid 128, deterministic tilted source:

| beams | $r_{xy}$ | uncoupled | coupled | gain |
| --- | ---: | ---: | ---: | ---: |
| 11:1 (production) | 0.1 | 2.6e-3 | 1.7e-3 | 1.53x |
| 11:1 | 0.3 | 5.8e-3 | 2.0e-3 | **2.95x** |
| 11:1 | 0.6 | 1.4e-2 | 8.6e-3 | 1.65x |
| 2:1 | 0.1 | 1.9e-3 | 1.9e-3 | 1.00x |
| 2:1 | 0.3 | 2.0e-3 | 2.8e-3 | 0.71x |
| 2:1 | 0.6 | 2.2e-3 | 2.1e-2 | **0.10x** |

**The coupled branch is not universally better**, and that is a derived property,
not a bug: the expansion parameter is $\tfrac12 r_{xy}^2/(1-r_{xy}^2)$, so at
large correlation the truncation error grows, and for near-round beams the
uncoupled baseline is already at the grid floor. It wins across the whole range
for flat beams, which is the regime the hybrid targets. Recommended use is flat
beams with `coupling_tol` ~ 0.05-0.1.

An intermediate result during this test showed ~100% error in the coupled branch;
that was a factor-2 in the *test harness* (the analytic add-back returns
$F=k_{bb}K$ with $k_{bb}=N_s$, so $K=F/N_s$, not $2F/N_s$), not in the solver.
Recorded because the solver was briefly and wrongly suspected.

## 16. Vico-Greengard-Ferrando: evaluated and rejected

Derivation and numbers in
[`pic_free_space_kernels.md`](../theory/pic_free_space_kernels.md) Section 3.3.
Summary: the closed-form truncated-kernel transform was derived and verified to
5e-13 against quadrature; a first implementation was 100x worse than the current
kernel, which was traced to kernel aliasing (truncation radius exceeding half the
padded period), not to the method. Working, it needs 3x padding (2.25x the FFT
points in 2D) to buy 12% accuracy, and at equal 2x padding its tail error is 2.3x
worse than the integrated kernel. Closed as *not recommended for this solver*.

## 17. CPU slice-path cost, measured

Before refactoring hot code, the assumed win was measured. Slice extraction and
copying at production size (170k-particle slice):

| operation | allocating | in-place (reuse) | ratio |
| --- | ---: | ---: | ---: |
| `_pic_extract_slice` | 5.22e-3 s | 4.28e-3 s | 1.22x |
| `_pic_copy_coords` | 5.8e-4 s | 5.3e-4 s | 1.09x |
| per slice pair | 1.16e-2 s | 9.62e-3 s | **17% saved** |

17% of the extract/copy phase is ~4% of a turn, because the cost is the gather
memcpy rather than the allocation. Buffer reuse is therefore **not** worth the
regression risk. Eliminating the gather entirely (the CUDA
`cuda_indexed_wavefront` equivalent) would save ~23% of a CPU turn but requires
threading `(rep, idx)` through the deposit, bounds scan and kick. Still open, now
with costed options rather than an assertion.

## 18. Multi-turn emittance growth with error bars

Section 11 was single-seed. Repeated at seeds 2222 and 3333 for the
configurations the recommendation depends on (proton $\varepsilon_x$ total growth
over 1000 turns):

| config | seed 1 | seed 2222 | seed 3333 | mean +- spread |
| --- | ---: | ---: | ---: | ---: |
| no collision (control) | -0.000% | +0.000% | -0.000% | **0.000 +- 0.000** |
| soft-Gaussian (analytic) | +0.405% | +0.40% | +0.41% | **0.405 +- 0.005** |
| PIC (64,64) | +1.101% | +1.30% | +1.46% | **1.29 +- 0.18** |
| PIC (128,128) | +0.637% | +0.61% | +0.65% | **0.632 +- 0.021** |
| GaussianPIC (64,64) TSC | +0.639% | +0.67% | +0.65% | **0.653 +- 0.016** |

**The Section 11 conclusions survive the error bars.**

1. The control is flat to within 1e-3 points on every seed.
2. The analytic reference is reproducible to +-0.005 points, confirming that the
   +0.405% baseline is physical beam-beam response, not noise.
3. **`grid=(64,64)` is separated from everything else by ~30 sigma** (1.29 +- 0.18
   against 0.632 +- 0.021) and, uniquely, its scatter is an order of magnitude
   larger than the others -- the signature of a run that has not settled. It is
   the only configuration still rising at the end of the run.
4. **PIC(128,128) and GaussianPIC(64,64) remain indistinguishable**
   (0.632 +- 0.021 against 0.653 +- 0.016; the 0.02-point gap is within one
   combined sigma). The recommendation in Section 12 to prefer PIC(128,128) on
   cost therefore stands: the hybrid at 64 buys no dynamic advantage over plain
   PIC at 128 while costing 2x on CUDA.
5. The numerical excess over the analytic reference is +0.23 points for
   PIC(128,128) and +0.89 points for PIC(64,64) -- i.e. **halving the mesh
   quadruples the artificial growth**, consistent with noise scaling as the
   inverse cell count.


---

## 19. CPU indexed slice path — implemented, measured, reverted (2026-07-25)

Requested as a CPU counterpart to `cuda_indexed_wavefront`. Implemented, verified
correct, measured, and then **reverted because it is slower**. Recorded here so
the result is not rediscovered.

**What was built.** A `cpu_indexed_slices` option on `PICPoissonSolver`. Within a
slice pair neither beam's storage is written until a kick is applied, and
direction 1 kicks beam 2, so only beam 2 needs a pre-collision snapshot (it is
the source of direction 2). Beam 1 is read straight from the rep during direction
1 and is still pristine when direction 2 kicks it. Both field slices become
`view(rep.x, idx)` handles, so kicks write through to beam storage and the
scatter disappears. Per slice pair this replaces 2 gathers + 2 copies + 2
scatters with 1 gather.

**Correctness.** Bit-identical to the gathered path — luminosity, electron and
proton coordinates all matched exactly (max |diff| = 0.0), as the construction
requires since neither arithmetic nor ordering changes.

**Performance — one `collide!`, 15 slices, 8 threads:**

| beams | grid | gathered | indexed | speedup |
| --- | --- | ---: | ---: | ---: |
| 256k / 102.4k | 64² | 4.363 s | 4.719 s | **0.92x** |
| 256k / 102.4k | 128² | 8.423 s | 8.890 s | **0.95x** |
| 2.56M / 1.024M | 64² | 36.98 s | 38.70 s | **0.96x** |
| 2.56M / 1.024M | 128² | 41.18 s | 43.48 s | **0.95x** |

Consistently **4-8% slower**, at every size and grid.

**Why, and why CUDA is different.** The prediction of a ~23% saving counted the
gather as a one-off cost. It is not: each slice's arrays are traversed several
times per interaction — the source by the drifted bounds scan, by the deposit at
both longitudinal boundaries, and by the midpoint luminosity coordinates; the
field by the forward drift, the kick loop, and the reverse drift. Gathering pays
an indirection once and then enjoys contiguous, prefetchable access on every
subsequent pass. Views pay `parent[idx[i]]` on *every* access, and there are more
accesses than the copies saved.

On CUDA the trade is the opposite, which is why `cuda_indexed_wavefront` is worth
2.3x there: the gather is a separate kernel launch with a full global-memory round
trip, and coalescing — not indirection count — dominates.

**Conclusion.** The gather is not the CPU bottleneck it appeared to be in the
Section 4.2 phase table; it is the price of contiguity, and it is worth paying.
The Section 17 estimate that eliminating the gather would save ~23% of a CPU turn
is **withdrawn**. A CPU indexed path is not a promising optimization and the item
is closed negative, rather than left open.
