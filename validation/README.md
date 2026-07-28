# Validation Scripts

Validation scripts are developer-facing numerical checks. They may use internal
helpers to test implementation details and should not be treated as public API
examples.

The fast, CPU-only package regression suite is separate from these scientific
validations and benchmarks:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Public Configuration Effectiveness

`public_configuration_effectiveness.jl` checks that registered public
configuration reaches real runtime consumers. It exercises CPU logical-worker
counts, fused CUDA thread/block sweeps, CUDA device mismatch rejection, all
CUDA PIC launch families, optimized wavefront and non-default sequential PIC
branches, schedules, buffers, inherited/inactive reports, and pre-mutation
configuration rejection. CUDA-unavailable runs are reported as skipped.

```bash
julia --threads=4 --project=. validation/public_configuration_effectiveness.jl
```

`tracking_context_policy_consistency.jl` verifies that radiation stays on the
context-aware fused path, CUDA launch geometry does not change counter-RNG
samples, and weak-strong luminosity diagnostics isolate exactly once per turn.

```bash
julia --threads=4 --project=. validation/tracking_context_policy_consistency.jl
```

## PIC Gaussian Field

`pic_gaussian_field_validation.jl` compares the PIC transverse field from a
deterministic Gaussian source distribution with the Bassetti-Erskine
soft-Gaussian kick.

Run the default detailed cases:

```bash
julia --project=. validation/pic_gaussian_field_validation.jl
```

Run a summary-only random sweep:

```bash
OCTOPUS_PIC_VALIDATION_RANDOM_CASES=100 \
OCTOPUS_PIC_VALIDATION_WRITE_CASE_DATA=false \
julia --project=. validation/pic_gaussian_field_validation.jl
```

Outputs are written to `result/`. Relative error is normalized by
`max_grid(|K_exact|)` for each case.

This is an accuracy-characterization study, not an exact-agreement gate. PIC
has finite-particle, grid, deposition, and domain-truncation error, so the
script reports the observed distribution and worst case without imposing one
universal pass/fail tolerance.

The implemented `PICPoissonSolver` optimizations (Green-FFT reuse, workspace
buffers, slice-pair Green cache, CUDA overlap/compact/indexed paths) are recorded
in `../docs/history/strong_strong_pic_optimization_history.md`; open items are in `../docs/todo.md`.

## Gaussian-Subtracted PIC Field

`gaussian_pic_field_validation.jl` compares the `GaussianPICPoissonSolver`
transverse field against Bassetti-Erskine and against plain PIC at a fixed grid,
using a deterministic Gaussian quantile source (no shot noise) so the metric
isolates the *systematic* grid-discretization error the subtraction removes.

```bash
julia --project=. validation/gaussian_pic_field_validation.jl
```

It sweeps aspect ratios (round to 25:1) and grids (48/64/128) and reports the
normalized median/max kick error for both solvers plus the hybrid/PIC gain. The
hybrid error is nearly grid-independent; at grid 48 it matches or beats plain PIC
at grid 128 (median gain 9-20x at coarse grids, 2.6-4.1x at 128). Reference
model `gaussian_beambeam_kick`; error normalized by `max_grid(|K_exact|)`. See
`docs/theory/gaussian_subtracted_pic_solver.md`.

## Gaussian-Subtracted PIC Bi-Gaussian Fairness

`gaussian_pic_bigaussian_validation.jl` is the fair, non-Gaussian test: a
bi-Gaussian source (dominant + offset perturbation) with an exact analytic field
(superposition of two Bassetti-Erskine kicks). The hybrid subtracts only a single
Gaussian fitted to the combined moments, so the perturbation lands in the grid
residual.

```bash
julia --project=. validation/gaussian_pic_bigaussian_validation.jl
```

The hybrid is never worse than plain PIC and beats it ~2-3x for near-Gaussian
sources, degrading gracefully toward parity as the perturbation grows. The
weakest gain is a diagonally offset perturbation (x-y coupling the uncoupled
subtraction cannot remove), motivating the coupled/rotated subtraction branch.

## Gaussian-Subtracted PIC Optimization History

`../docs/history/strong_strong_gaussian_pic_optimization_history.md` is the dated developer log
of the `GaussianPICPoissonSolver` CPU/CUDA implementation and the CUDA throughput
campaign (sequential vs non-indexed vs indexed wavefront paths, the moment-
reduction and Green-build fixes, and the CPU/CUDA bit-parity story). The CUDA
indexed wavefront path reaches GaussianPIC@128 ~1.6x PIC and GaussianPIC@64 ~1.2x
PIC@128 at equal-or-better accuracy. CPU/CUDA parity is guarded by the "CUDA
GaussianPIC solver matches CPU" testset in `test/runtests.jl`.

## Spectral Sine-Series Poisson Field

`spectral_poisson_field_validation.jl` validates the spectral sine-series 2D
Poisson solver (see `../docs/theory/spectral_sine_poisson_solver.md`) against the exact
Bassetti-Erskine field, for both the grid (DST) and grid-free variants, and
records how accuracy scales with the domain size and the mode/grid resolution.
It also runs the PIC solver on the same cases for a shape-accuracy comparison.
For `method=:grid`, `grid=(Nx,Ny)` means both the interior mesh and retained
sine-mode count. For `method=:grid_free`, the same setting means retained
direct mode counts only; no particle-deposition mesh is used.

```bash
julia --project=. validation/spectral_poisson_field_validation.jl
```

Outputs `result/spectral_poisson_field_validation.tsv`. Like the PIC field study
this is a characterization, not a fixed pass/fail gate; the measured domain-size
and thin-direction scaling laws and the recommended parameter choices are
summarized in the doc.

`strong_strong_spectral_comparison.jl` runs deterministic production-shaped
live-beam collisions with Gaussian, PIC, spectral grid, and optionally spectral
grid-free solvers. It records complete-turn timing, luminosity, final beam
moments, and particle-coordinate differences against PIC.

```bash
OCTOPUS_SPECTRAL_COMPARE_N=20000 \
OCTOPUS_SPECTRAL_COMPARE_GRID=128,1024 \
julia --project=. validation/strong_strong_spectral_comparison.jl
```

Outputs are written as TSV files under
`result/strong_strong_spectral_comparison*`. Set
`OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda` for CUDA runs; grid-free is CPU-only.
`OCTOPUS_SPECTRAL_COMPARE_GRID` is a mesh-and-mode shape for the grid solver,
while `OCTOPUS_SPECTRAL_COMPARE_FREE_GRID` is a direct mode-count shape for the
grid-free solver.

## Counter RNG

`counter_rng_validation.jl` checks the Philox-based stateless counter RNG used
for current stochastic beam initialization and tracking. It reports basic
uniform and normal statistics, component correlation, neighboring-particle
correlation, and reproducibility checks.

Run the default one-million-sample check:

```bash
julia --project=. validation/counter_rng_validation.jl
```

Run a smaller check:

```bash
OCTOPUS_RNG_VALIDATION_N=200000 \
julia --project=. validation/counter_rng_validation.jl
```

Compare the SplitMix64-backed functions:

```bash
OCTOPUS_RNG_VALIDATION_BACKEND=splitmix \
julia --project=. validation/counter_rng_validation.jl
```

Optionally write a CSV summary:

```bash
OCTOPUS_RNG_VALIDATION_WRITE_CSV=true \
julia --project=. validation/counter_rng_validation.jl
```

## Tracking Backend Consistency

`tracking_backend_consistency.jl` runs `ElementTrackingBackendConsistencyContract` on
a deterministic mixed tracking line, including stochastic `LumpedRad`. It
always runs CPU/CPU and runs CPU/GPU when CUDA is visible or explicitly
requested.

The CPU/CPU result is a same-process deterministic repeatability check. For the
current fused elementwise tracking path, exact zero error is expected because
each particle is independent and stochastic samples are keyed by particle
index, turn, seed, and `rng_id`. It is not a single-thread versus multi-thread
comparison; Julia thread count is fixed when the process starts and is reported
as `cpu_threads` in the contract metrics.

Run the default check:

```bash
julia --project=. validation/tracking_backend_consistency.jl
```

Request CPU/GPU explicitly:

```bash
OCTOPUS_RUN_GPU_CONTRACT=1 \
julia --project=. validation/tracking_backend_consistency.jl
```

Require CPU/GPU to run rather than skip:

```bash
OCTOPUS_RUN_GPU_CONTRACT=1 \
OCTOPUS_REQUIRE_GPU_CONTRACT=1 \
julia --project=. validation/tracking_backend_consistency.jl
```

Adjust problem size or tolerances:

```bash
OCTOPUS_CONTRACT_N=100000 \
OCTOPUS_CONTRACT_TURNS=5 \
OCTOPUS_CONTRACT_ATOL=1e-10 \
OCTOPUS_CONTRACT_RTOL=1e-10 \
julia --project=. validation/tracking_backend_consistency.jl
```

## TrackingTask Turn Updates

`tracking_task_turn_update.jl` checks that `TrackingTask` applies an explicit
turn-dependent source-modulation action identically with and without a no-op
observer. The action owns the schedule state; the collision element remains a
fixed physical source model.

```bash
julia --project=. validation/tracking_task_turn_update.jl
```

## Weak–Strong Six-Dimensional Source

The coupled-covariance audit, limiting-case coverage, CPU/CUDA parity, and
performance regression measurements are recorded in
[`weak_strong_6d_model_validation.md`](../docs/history/weak_strong_6d_model_validation.md).

## Beam Optics Interface Consistency

`beam_optics_interface_consistency.jl` checks the shared three-plane
`beta`/`alpha` Beam interface, exact compatibility with legacy two-component
alpha input when `alpha_z=0`, sigma/emittance equivalence, longitudinal
covariance, and CPU/CUDA agreement.

```bash
julia --project=. validation/beam_optics_interface_consistency.jl
```

## Strong-Strong PIC Cache Backend Consistency

`strong_strong_pic_cache_backend_consistency.jl` runs
`StrongStrongPICBackendConsistencyContract`. It checks persistent slice-pair
cache reuse, identical CPU/CUDA cache histories, both final beam states, the
complete turn luminosity series, and every nonempty wavefront slice-pair
contribution. The default deposition method is CIC; set
`OCTOPUS_CACHE_CONTRACT_DEPOSIT_METHOD=TSC` to exercise the public TSC path.

```bash
julia --threads=4 --project=. validation/strong_strong_pic_cache_backend_consistency.jl

OCTOPUS_CACHE_CONTRACT_DEPOSIT_METHOD=TSC \
    julia --threads=4 --project=. validation/strong_strong_pic_cache_backend_consistency.jl
```

Set `OCTOPUS_CACHE_CONTRACT_LUMINOSITY_DEPOSIT_METHOD=INHERIT`, `CIC`, or
`TSC` to cover inherited and explicit luminosity deposition independently of
the force deposition method.

## PIC Gaussian Luminosity Quadrature

`pic_gaussian_luminosity_validation.jl` checks CIC and TSC deposited-grid
luminosity against the analytic overlap of centered, offset, unequal, round,
and flat Gaussian beams. It sweeps grid resolution and grid-edge padding using
deterministic Halton-Gaussian macroparticles. The reported grid sum is a
convergent quadrature, not an exact finite-particle-shape overlap.

The analytic comparison characterizes convergence rather than enforcing exact
agreement. The script strictly gates only agreement between the production
luminosity implementation and the independently assembled discrete
quadrature.

```bash
julia --project=. validation/pic_gaussian_luminosity_validation.jl
```

## Strong-Strong Gaussian Backend Consistency

`strong_strong_gaussian_backend_consistency.jl` runs
`StrongStrongGaussianBackendConsistencyContract`. It compares both final beam
states and luminosity between the CPU and CUDA soft-Gaussian solvers.

The implementation audit, public-code comparison, correctness findings, and
CPU/CUDA performance measurements are recorded in
[`strong_strong_gaussian_optimization.md`](../docs/history/strong_strong_gaussian_optimization.md).
Dated soft-Gaussian optimization experiments, including rejected and reverted
attempts, are logged in
[`strong_strong_gaussian_optimization_history.md`](../docs/history/strong_strong_gaussian_optimization_history.md).

```bash
julia --threads=4 --project=. validation/strong_strong_gaussian_backend_consistency.jl
```

`soft_gaussian_pic_comparison.jl` characterizes the intentional model
difference between soft-Gaussian and PIC using identical cloned live beams. It
reports luminosity, final six-dimensional RMS sizes, particle-coordinate RMS
differences, and synchronized CUDA timings. The comparison is not an equality
gate.

```bash
julia --project=. validation/soft_gaussian_pic_comparison.jl
OCTOPUS_SOFT_SIGMA_XY=true julia --project=. validation/soft_gaussian_pic_comparison.jl
```

`high_energy_weakstrong_limit.jl` checks the limiting case where the electron
energy is effectively infinite, so the electron beam is a frozen source. It
compares the soft-Gaussian strong-strong collision to an explicit frozen-source
weak-strong reference, compares PIC to the same reference with grid/model
tolerances, and verifies that spectral grid and grid-free strong-strong maps
collapse to frozen-source spectral weak-strong references. The spectral grid
default is `(128,1024)` (the earlier flat-beam setting; the currently
recommended production grid is `(127,383)` with `domain_factor=8`, see
`?SpectralPoissonSolver`); the grid-free direct reference defaults to
`(48,48)`. Set `OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1` to
also check the CUDA spectral grid path when CUDA is functional.

```bash
julia --project=. validation/high_energy_weakstrong_limit.jl
OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1 julia --project=. validation/high_energy_weakstrong_limit.jl
```

`symplecticity_validation.jl` computes finite-difference Jacobians for all
current six-dimensional symplectic runtime maps and reports
`norm(J' * S * J - S, Inf)`.

```bash
julia --project=. validation/symplecticity_validation.jl
```

## Strong-Strong Observer Plan Consistency

`strong_strong_observer_plan_consistency.jl` verifies that inserting a
read-only observer after a collision does not change either beam. It guards
the block-aware strong-strong plan cache.

```bash
julia --threads=4 --project=. validation/strong_strong_observer_plan_consistency.jl
```

## Strong-Strong Diagnostics Consistency

`strong_strong_diagnostics_consistency.jl` verifies that enabling observational
task diagnostics leaves both beams exactly unchanged and that complete-turn
timings and the structured diagnostics summary are populated correctly.

```bash
julia --threads=4 --project=. validation/strong_strong_diagnostics_consistency.jl
```

## Strong-Strong PIC Extreme CUDA Benchmark

`strong_strong_pic_extreme_benchmark.jl` runs the frozen production-size CUDA
reference with 2.56M electrons, 1M protons, a 128×128 grid, and 15 slices per
beam. It runs 30 turns and reports the mean, median, minimum, standard
deviation, and individual timings for the final 10 turns. Moment and luminosity
file output are disabled in the timed region.

```bash
julia --project=. validation/strong_strong_pic_extreme_benchmark.jl
```

Tracked run-by-run results, commands, validation gates, and decisions are in
`../docs/history/strong_strong_pic_extreme_benchmark_history.md`. Generated timing TSV files
under `result/` remain intentionally gitignored.

## Strong-Strong Diagnostic Output Benchmark

`strong_strong_diagnostics_benchmark.jl` holds the fastest validated PIC
solver configuration fixed while measuring no output, luminosity computation,
luminosity text output, moment HDF5 output, and both diagnostics. The default
run is 200 turns and measures turns 100-199.

```bash
julia --project=. validation/strong_strong_diagnostics_benchmark.jl
```

Select another measurement mode with
`OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=luminosity`, `luminosity_io`, `moments`, or
`both`. Production-size diagnostic benchmarks are manual runs and are not part
of the fast package test suite.

Tracked results, accuracy checks, and accepted/rejected experiments are in
`../docs/history/strong_strong_diagnostics_benchmark_history.md`.

`moment_observer_backend_consistency.jl` directly compares every default
first- and second-order moment produced by the CPU and CUDA reduction paths:

```bash
julia --project=. validation/moment_observer_backend_consistency.jl
```

`strong_strong_luminosity_schedule_output.jl` verifies that luminosity files
omit unscheduled turns while preserving all scheduled results, including an
evaluated `NaN`, and that the header identifies collision columns:

```bash
julia --project=. validation/strong_strong_luminosity_schedule_output.jl
```

## Slice Longitudinal Interpolation z-Scan

`slice_longitudinal_zscan.jl` measures how much error the *longitudinal*
reconstruction of the slice field contributes to `Delta p_x`, `Delta p_y` and
`Delta p_z`, and how discontinuous the kick is across a field-slice boundary.

A source slice and a test particle's `(x, y, px, py)` are frozen; `z` is swept
finely across several field slices. The reference is a per-particle exact solve
at each sample's own collision point `sigma(z) = (c - z)/2`. The two-node
(`slice_interpolation=:linear`) and three-node (`:quadratic`) schemes are
compared against it on the **same** grid, deposition and Green kernel, so the
transverse PIC error cancels and only the longitudinal interpolation error
remains -- which is what separates it from the slicing error. A second pass
repeats `:linear` with per-slice grids to measure the transverse jump that
grid resizing introduces.

For a flat beam `Delta p_y` is the observable that matters: `E_y` varies on the
scale `sigma_y << sigma_x`, so its curvature in the drift variable is larger by
roughly the aspect ratio.

```bash
julia --threads=4 --project=. validation/slice_longitudinal_zscan.jl
```

Outputs under `result/`: `slice_longitudinal_zscan.tsv` (per-sample curves,
plot ready), `_summary.tsv` (per component and scheme), `_jumps.tsv`
(per-boundary discontinuities).

Derivation, error constants and the measured first-run results are in
`../docs/theory/slice_longitudinal_interpolation.md`; the change record is in
`../docs/history/slice_longitudinal_interpolation_record.md`.

## Slice Interpolation Emittance Growth

`slice_interpolation_emittance_growth.jl` decides whether the slice-boundary kick
discontinuity measured by the z-scan actually moves a physics observable, or is a
field-accuracy artefact with no dynamical consequence.

The setup is built so that *all* vertical emittance growth is numerical: head-on
collision, linear one-turn maps, no chromaticity, no dispersion, and **no
radiation damping or excitation**, leaving the Poisson solver as the only
non-symplectic element. Arms compare `slice_interpolation`, `deposit_method`,
`interaction_grid`, and the "just add slices" alternative.

Because shot noise alone drives growth, each arm runs at several seeds and an arm
is judged different only when the seed means separate by more than the seed
spread. `boundary_cross_fraction` is reported as a validity check: if particles do
not change slice index between turns, the discontinuity is never sampled.

One arm/seed:

```bash
OCTOPUS_EMIT_SCHEME=quadratic OCTOPUS_EMIT_SEED=1 \
  julia --threads=8 --project=. validation/slice_interpolation_emittance_growth.jl
```

Overrides: `OCTOPUS_EMIT_SCHEME`, `OCTOPUS_EMIT_NSLICES`, `OCTOPUS_EMIT_DEPOSIT`,
`OCTOPUS_EMIT_GRIDMODE`, `OCTOPUS_EMIT_SEED`, `OCTOPUS_EMIT_TURNS`,
`OCTOPUS_EMIT_NPART`, `OCTOPUS_EMIT_GRID`, `OCTOPUS_EMIT_TAG`.

Aggregate all completed arms (seed means, spreads, and separation from baseline):

```bash
julia --project=. validation/slice_interpolation_emittance_growth_summary.jl
```

Outputs under `result/`: `emittance_growth_<tag>.tsv` (per-turn emittances),
`emittance_growth_<tag>.meta.tsv` (one summary row per run), and
`emittance_growth_summary.tsv` (per-arm aggregate).

## PIC Grid Extent Stability

`pic_grid_extent_stability.jl` quantifies why the interaction mesh jitters. Under
the default `grid_extent=:extrema` the mesh size is a *sample extremum*, which is
`O(1)`-noisy; `:sigma` uses a second moment, whose noise is `O(1/sqrt(n))`. The
metric is the relative variation of the box, both across slices within a turn and
across turns for a fixed slice, since the mesh discontinuity is proportional to it.

`dropped` must stay at zero for a production setting: dropping a fraction `f` of
charge at radius `R` costs a field error `~ f*(sigma/R)`, so even `1e-3` is the
same order as the discontinuity the estimators are meant to remove.

```bash
julia --threads=4 --project=. validation/pic_grid_extent_stability.jl
```

Outputs `result/pic_grid_extent_stability.tsv`.

## PIC Slice Boundary Jitter

`pic_slice_boundary_jitter.jl` quantifies the per-turn re-slicing jitter of the
longitudinal slice boundaries (docs/todo.md, slice-interpolation item 5): the
boundaries are rebuilt every turn from the instantaneous z distribution, so a
deterministic interpolation error becomes a fluctuating one — a mechanism the
frozen-slicing z-scan cannot see. The strong-strong example beams are tracked
through a PIC collision plus one-turn maps, and every boundary/center is
recorded each turn under both `:equal_area` and `:normal_quantile` slicing.

The error metric is the standard deviation over turns divided by the beam z
rms. First-run headline (100k macroparticles, 15 slices, 64 turns): the
**outermost boundaries** — pinned to single extreme macroparticles — jitter at
**0.13–0.17 sigma_z** turn-to-turn under both methods, while the internal
boundaries jitter at ~0.003 sigma_z under `:equal_area` and 1.6x (electron
beam) to 13x (proton beam) less under `:normal_quantile`.

```bash
julia --threads=8 --project=. validation/pic_slice_boundary_jitter.jl
```

Overrides: `OCTOPUS_JITTER_NPART`, `OCTOPUS_JITTER_TURNS`,
`OCTOPUS_JITTER_NSLICES`, `OCTOPUS_JITTER_GRID`, `OCTOPUS_JITTER_SEED`.
Outputs `result/pic_slice_boundary_jitter.tsv`.

## Coherent Beam-Beam Modes (sigma/pi Split, Yokoya Factor)

`coherent_beam_beam_modes.jl` is the community-standard physics acceptance
test for strong-strong field solvers: two identical round e+e- beams collide
at one IP (single slice, no crossing angle, rigid linear lattice), beam 1 is
launched with a 0.1-sigma dipole offset, and the sigma/pi coherent mode tunes
are extracted from 8192-turn centroid FFTs (sum and difference signals,
Hann-windowed, interpolated peaks). The Yokoya factor
`Lambda = (Q_pi - Q_sigma)/xi` discriminates how much self-consistent
distribution dynamics the solver captures: rigid/moment-closure models
underestimate it (rigid = 1), while the Vlasov value is 1.2-1.3 depending on
the beam-size aspect ratio, with round beams at ~1.2 (Yokoya & Koiso, Part.
Accel. 27 (1990) 181; Herr & Pieloni, arXiv:1601.05235; same method as the
RHIC BeamBeam3D studies, arXiv:1410.5623).

First-run headline (8192 turns, 100k macroparticles/beam, xi = 0.005,
Qx/Qy = 0.31/0.32): the sigma mode sits at the bare tune to < 4e-6 in every
run; the soft-Gaussian solver gives **Lambda = 1.096/1.101** (x/y, the
moment-closure underestimate), while **PIC gives 1.199/1.206** and
**Gaussian-subtracted PIC 1.200/1.207** — both inside the Vlasov band at the
round-beam value, agreeing with each other to ~4e-6 in tune. This is the
solver-family split the theory predicts: the pi-mode excess over the rigid
value is carried entirely by distribution-shape feedback, which only the
PIC-based solvers represent.

The symmetric configuration is deliberate: the Vlasov band applies to equal
beams with equal tunes and equal xi. The asymmetric EIC production case has
no single theory Lambda (its modes are eigenvectors of a coupled asymmetric
system); run it only as a demonstration.

A reduced-settings version of this check runs in the regression suite as
`validate(CoherentModePhysicsContract())` — a per-solver physics gate: the
PIC-based solvers must land in the Vlasov band, and the suite asserts that
the soft-Gaussian solver *fails* it (a moment closure cannot carry the
pi mode beyond the rigid value; the failure is the documented model
limitation, not a defect). The symplecticity and high-energy weak-strong
scripts are likewise mirrored by `SymplecticityContract` and
`HighEnergyWeakStrongLimitContract`.

```bash
julia --threads=8 --project=. validation/coherent_beam_beam_modes.jl
```

Overrides: `OCTOPUS_CBB_TURNS`, `OCTOPUS_CBB_N_MACRO`, `OCTOPUS_CBB_SOLVERS`
(comma list from `gaussian,pic,gaussian_pic`). Moment files are written under
`result/` and overwritten on each run.

**Theory companions.**
`coherent_mode_vlasov_theory.jl` derives the sigma/pi mode structure from
linearized Vlasov theory (standalone; docs/theory/coherent_beam_beam_modes.md
holds the derivation): the m=1 eigenproblem with the flatness-dependent
1D-reduced kernel, validated by a translation-invariance check (sigma mode at
Q0 to ~1e-5 xi) and an exact harmonic-interaction limit (Y = 2), plus a
spectral 1D particle simulation of the *same model* that referees the m=1
truncation. `coherent_mode_scans.jl` measures the physical 2D Yokoya factor
with the production PIC solver versus flatness (Y = 1.19 round rising to
~1.25-1.27 flat, inside the literature band 1.2-1.33) and versus xi
(xi-independent to ~1% for xi <= 0.01). `plot_coherent_mode_theory.py`
renders result/yokoya_vs_aspect.png, yokoya_vs_xi.png, and
eic_coherent_modes.png from the TSVs.

```bash
julia --project=. validation/coherent_mode_vlasov_theory.jl
julia --threads=8 --project=. validation/coherent_mode_scans.jl
/usr/local/anaconda3/bin/python3 validation/plot_coherent_mode_theory.py
```

**EIC comparison.**
`coherent_mode_eic_comparison.jl` runs the EIC-like head-on equivalent
(production constants, single slice, rigid lattice) through the real PIC
solver and compares both beams' centroid spectra with the coupled Vlasov
mode analysis. First run: x-plane responses confined to the two separated
theory continua and Landau-damped (decoherence ~48/~112 turns for e/p);
y-plane — where the electron continuum swallows the proton tune — both
beams lock onto one narrow persistent line at the proton bare tune with no
measurable decoherence over 4096 turns, the p-dominated collective mode the
theory flagged as marginal. Overlay figure: `result/eic_mode_comparison.png`.

```bash
julia --threads=8 --project=. validation/coherent_mode_eic_comparison.jl
```

**Cross-code anchor (BeamBeam3D).**
`coherent_beam_beam_modes_beambeam3d.jl` analyzes the same physics case run
through BeamBeam3D (Qiang, Furman, Ryne — the reference PIC strong-strong
code, github.com/beam-beam/BeamBeam3D, built from source with gfortran +
OpenMPI), using the identical spectral estimator on its `fort.24/25/34/35`
centroid histories. First-run comparison at identical settings (8192 turns,
100k macroparticles/beam, 128x128 grid, xi = 0.005):
**BeamBeam3D Lambda = 1.197/1.210 (x/y)** against Octopus PIC 1.199/1.206 and
GaussianPIC 1.200/1.207 — agreement to ~0.003 in Lambda (~1e-5 in tune, the
resolution limit of the analysis), with the sigma mode at the bare tune to
< 4e-6 in both codes. The input deck lives in the BeamBeam3D checkout under
`coherent_modes/`; the script takes the run directory as an argument or via
`OCTOPUS_BB3D_RUNDIR`.

## Gaussian-Subtracted PIC z-Scan

`gaussian_pic_zscan.jl` completes docs/todo.md item 4a: the frozen longitudinal
z-scan through the hybrid solver's **own** solve path
(`_gpic_solve_drifted_field!`: deposit, erf Gaussian subtraction, residual
Green-FFT solve, plus the analytic Bassetti-Erskine add-back blended with the
production zL/zR weights). The earlier attempt used the raw PIC path and never
exercised the control variate.

First-run results (grid 64, CIC, 7 slices, 200k macroparticles), transverse
components: on one **common grid** the hybrid's longitudinal interpolation
error and boundary jump equal pure PIC's — the analytic term carries the full
field's z-curvature, so the reconstruction error is a property of the total
field. On **per-slice-pair meshes** (identical boxes for both solvers,
including the hybrid margin) the mesh-resizing jump falls by 2.8x in x but only
**1.10x in y**, against the ~11x the residual-fraction argument predicted: the
deposited residual (`||dQ||/||Q|| = 0.088` here) is mostly shot noise at these
statistics, and the noise field's mesh dependence does not scale with the
smooth-residual amplitude. The prediction is therefore **refuted for the
flat-beam-critical vertical component**.

```bash
julia --threads=4 --project=. validation/gaussian_pic_zscan.jl
```

Overrides: `OCTOPUS_GPIC_ZSCAN_NPART`, `OCTOPUS_GPIC_ZSCAN_GRID`,
`OCTOPUS_GPIC_ZSCAN_NSLICES`, `OCTOPUS_GPIC_ZSCAN_DEPOSIT`.
Outputs `result/gaussian_pic_zscan_summary.tsv`.

## PIC Option Consistency and Cost

`pic_option_consistency.jl` runs the crab-crossing EIC case of
`examples/strong_strong_tracking.jl` -- same beam parameters, crab cavities,
Lorentz boost pair, one-turn optics, chromaticity and electron radiation -- for
many turns under one PIC option set, and records enough to compare option sets
against each other.

The options change the discretization deliberately, so they are **not** expected
to agree bit-for-bit. What is checked is that they agree to the accuracy the
discretization implies and that none drifts away over many turns. Three levels of
evidence, in increasing strictness:

1. luminosity per turn (coarsest integral observable);
2. beam moments per turn, which respond to per-particle errors that cancel in the
   luminosity;
3. per-particle coordinates at selected turns -- the strict check, which catches a
   systematic per-particle bias hiding inside an unchanged luminosity. Use a small
   `OCTOPUS_OPT_NPART` for this.

Timing is the mean wall time over `OCTOPUS_OPT_TIMING_FROM..OCTOPUS_OPT_TURNS`,
excluding early turns so compilation and cache warm-up are not counted.

```bash
OCTOPUS_OPT_TAG=node OCTOPUS_OPT_INTERACTION_GRID=node \
  julia --threads=6 --project=. validation/pic_option_consistency.jl
julia --project=. validation/pic_option_consistency_summary.jl
```

Overrides: `OCTOPUS_OPT_TAG`, `OCTOPUS_OPT_TURNS`, `OCTOPUS_OPT_NPART`,
`OCTOPUS_OPT_GRID`, `OCTOPUS_OPT_NSLICES`, `OCTOPUS_OPT_INTERACTION_GRID`,
`OCTOPUS_OPT_SLICE_INTERP`, `OCTOPUS_OPT_DEPOSIT`, `OCTOPUS_OPT_EXTENT`,
`OCTOPUS_OPT_QUANTIZE`, `OCTOPUS_OPT_DUMP_TURNS`, `OCTOPUS_OPT_TIMING_FROM`,
`OCTOPUS_OPT_BACKEND`.

Outputs under `result/`: `pic_option_<tag>.tsv` (per-turn series),
`.coords.tsv` (coordinate dumps), `.meta.tsv` (options and timing),
`pic_option_consistency_summary.tsv` (cross-option comparison).
