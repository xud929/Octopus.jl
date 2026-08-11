# Validation Scripts

Validation scripts are developer-facing numerical checks. They may use internal
helpers to test implementation details and should not be treated as public API
examples.

The fast, CPU-only package regression suite is separate from these scientific
validations and benchmarks:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Near-Round Gaussian Transition

`near_round_gaussian_transition.jl` validates the precision-scaled smooth
transition between the near-round potential expansion and the elliptical
Bassetti-Erskine evaluator. It compares force and principal covariance
response with the fixed-interval Gaussian integral, checks exact flat-beam core
gradients, estimates value and first-derivative gaps at both blend endpoints,
measures six-dimensional symplecticity, and reports CPU/CUDA parity when CUDA
is available.

```bash
julia --project=. validation/near_round_gaussian_transition.jl
```

The derivation, implementation constants, and recorded reference run are in
`../docs/theory/near_round_bassetti_erskine_switch.md`.

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

# The committed paper table needs a WIDER grid sweep than the default:
OCTOPUS_GPIC_GRIDS=48,64,96,128,192,256 \
    julia --project=. --threads=4 validation/gaussian_pic_field_validation.jl
```

`paper/data/gaussian_pic_field_validation_summary.tsv` (Figure 2) carries 24
rows at 48/64/96/128/192/256, which the default 12-row sweep cannot produce.
That override was recorded nowhere until the 2026-08-05_b audit (U23-10), so the
frozen figure could not be regenerated from the committed defaults.

It sweeps aspect ratios (round to 25:1) and grids (48/64/128 by default) and reports the
normalized median/max kick error for both solvers plus the hybrid/PIC gain. The
hybrid error is nearly grid-independent; at grid 48 it matches or beats plain PIC
at grid 128 (median gain 9-20x at coarse grids, 2.6-4.1x at 128). Reference
model `gaussian_beambeam_kick`; error normalized by `max_grid(|K_exact|)`. See
`docs/theory/gaussian_subtracted_pic_solver.md`.

Characterization, not a gate: it reports the error tables and exits zero
regardless. Its "hybrid" is also a **local reimplementation** of the
subtraction — `PICPoissonSolver` plus the integrated-log Green convolution
and hand-coded erf moments, never a `GaussianPICPoissonSolver` object — so
it validates the algorithm, not the production wiring; the z-scan below is
the study that drives the production internals (2026-08-05 audit, U20).

## Gaussian-Subtracted PIC Bi-Gaussian Fairness

`gaussian_pic_bigaussian_validation.jl` is the fair, non-Gaussian test: a
bi-Gaussian source (dominant + offset perturbation) with an exact analytic field
(superposition of two Bassetti-Erskine kicks). The hybrid subtracts only a single
Gaussian fitted to the combined moments, so the perturbation lands in the grid
residual.

```bash
julia --project=. validation/gaussian_pic_bigaussian_validation.jl
```

The hybrid is never worse than plain PIC IN THE MEDIAN (its worst-point error
can exceed PIC's -- measured max_gain 0.9957; U23-12) and beats it ~2-3x for near-Gaussian
sources, degrading gracefully toward parity as the perturbation grows. The
weakest gain is the FAR x-only perturbation at 1.4x, with the diagonally offset
(coupled) case next at 1.5x -- distance from the core shrinks the gain, and x-y
coupling is a smaller second effect (2026-08-05_b audit, U23-5). The
coupled/rotated subtraction branch is motivated structurally: it is the only
mechanism that removes a sigma_xy residual at all.

Characterization, not a gate, and the same local-reimplementation caveat as
the field study above: the "hybrid" here is assembled from `PICPoissonSolver`
and hand-coded moments, not the production `GaussianPICPoissonSolver`
(2026-08-05 audit, U20).

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
for current stochastic beam initialization and tracking. It runs the
Random123 known-answer vectors for philox4x32-10 first, then reports basic
uniform and normal statistics, component correlation, neighboring-particle
correlation, and reproducibility checks.

**Read the two halves differently.** The known-answer check is the generator
anchor: it drives the production block function and either reproduces the
upstream vectors bit-for-bit or fails. The moment and correlation checks are a
*statistics* test and cannot stand in for it — measured, a Philox4x32 with the
Weyl key bump removed and a 3-round variant both pass every moment bound
comfortably (2026-08-05_b audit, U25-2). The same known-answer gate runs in
`test/runtests.jl` ("Philox4x32-10 matches the Random123 known-answer
vectors"); both call `Octopus.philox4x32_self_test()`, so there is one copy of
the vectors and one driver under test.

The moment tolerances scale as `1/sqrt(N)` (6σ), so every `N` below is a valid
run; they were fixed constants calibrated to `N = 1e6` and failed a healthy
generator at the smaller `N` this file recommends (U25-3).

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

`tracking_backend_consistency.jl` runs `ElementTrackingBackendConsistencyContract`
on a deterministic tracking line that carries **every element kind declaring
that contract** -- 29 of them: the whole thick-magnet family, every thin
element, patch, marker, aperture, RF cavity, and stochastic `LumpedRad`. It
always runs CPU/CPU and runs CPU/GPU when CUDA is visible or explicitly
requested.

The line is not a hand-picked sample, and must not become one again. It carried
11 kinds while 18 declaring kinds went untracked (2026-08-05 audit, U21-5), so
the script now ends with a **declaration-coverage tripwire**: a kind that
declares the contract and is missing from the line fails the run by name. Adding
a kind to the contract therefore obliges you to add it here, which is the point
-- this entry described the 11-kind version until the 2026-08-05_b audit
(U25-13).

Two coverage limits are worth knowing. `:aperture` is in the line by name only:
the committed limits are 1 m against a beam of ~1e-4 m, so no particle can ever
reach it, and it cannot be tightened, because `_aperture_kill` writes `NaN` into
all six coordinates and the contract's comparator turns `NaN` into a failure
even when both backends lose the same particles identically (U25-4). `:marker`
is a documented no-op, so covering it by name is all there is to cover.

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
OCTOPUS_CONTRACT_SEED=123456789 \
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
alpha input when `alpha_z=0`, sigma/emittance equivalence, and longitudinal
covariance.

It runs that same set of checks **on each backend separately**, on CUDA as well
when a device is available. It does not compare CPU arrays against CUDA arrays:
`check_backend(CPUThreadsBackend)` and `check_backend(CUDABackend)` are two
independent calls, and no value from one is ever held against the other. This
entry used to claim "and CPU/CUDA agreement", which it never did
(2026-08-05_b audit, U25-7). Cross-backend agreement for *tracking* is covered
by `tracking_backend_consistency.jl` and the
`StrongStrongPICBackendConsistencyContract`.

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
luminosity implementation and a locally assembled discrete quadrature.

That quadrature is **not** independent of production — it calls the same
`_pic_deposit!` — so what the gate pins is the *interface*: the padding algebra,
the mesh extent and the normalization around the shared deposit. It is described
that way deliberately. It was previously called "independently assembled", and
the copy had also gone stale: it summed the pre-U5-8 truncated `1:nx, 1:ny`
extent while production had moved to the full `(nx+1) x (ny+1)`, so the gate
could not detect the defect U5-8 recorded, and a regression that re-truncated
production would have made the two agree *better*. The committed cases hid it
because none put both beams' extreme particles on the same mesh edge; the
`identical_edge_probe` case exists to make sure one always does (2026-08-05_b
audit, U23-1).

```bash
julia --project=. validation/pic_gaussian_luminosity_validation.jl
```

## Strong-Strong Gaussian Backend Consistency

`strong_strong_gaussian_backend_consistency.jl` runs
`StrongStrongGaussianBackendConsistencyContract`. It compares both final beam
states and luminosity between the CPU and CUDA soft-Gaussian solvers.

**Which number to read.** `max_component_rel_error` is a *pointwise* ratio:
each particle-coordinate difference divided by that component's own magnitude.
A coordinate near a zero crossing therefore inflates it without any
disagreement, which is why `max_component_rel_scale` is reported alongside --
the magnitude the ratio was divided by. A representative CPU/CUDA run gives

    max_abs_error           1.5e-17     round-off on coordinates of order 1e-3
    global_rel_error        6.5e-16     the same difference against the beam scale
    max_component_rel_error 2.8e-10     pointwise ratio, and
    max_component_rel_scale 4.9e-10       what it was divided by
    max_allowed_ratio       1.5e-7      the actual pass/fail test, must be <= 1

`global_rel_error` is the honest summary and `max_allowed_ratio <= 1` is the
criterion (`diff <= atol + rtol * scale`, so the absolute floor governs near
zero). CPU and GPU reduce beam moments in different orders, so exact bitwise
agreement is not expected here as it is for the elementwise fused tracking path.

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
gate. **It requires a CUDA device** and errors out immediately without one --
the timings it reports are CUDA timings (2026-08-05_b audit, U25-9).

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

`symplecticity_validation.jl` computes finite-difference Jacobians for the 12
cases `SymplecticityContract` declares -- which it derives rather than copies --
and reports `norm(J' * S * J - S, Inf)`. That is **not** every six-dimensional
symplectic runtime map: it covers 7 of the 22 registered kinds declaring
`Symplectic6DMap`, plus the beam-beam and Lorentz maps. The thick lattice-magnet
family is covered against PTC instead (a different claim), and the thin kickers,
marker and thin RF cavity by neither. See the script header. (This entry read
"for all current six-dimensional symplectic runtime maps" until the 2026-08-05_b
audit counted it, U24-3.)

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

Outputs, under `result/`: `pic_extreme_turn_times.tsv` (per-turn wall times)
and `pic_extreme_summary.tsv` -- the provenance record carrying the git commit,
GPU and driver, and the resolved CUDA launch configuration. The second file was
undocumented (2026-08-05_b audit, U25-8).

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
`both`. Set `OCTOPUS_SOLVER=gaussian` to benchmark the soft-Gaussian source
moment path with the same tracking and diagnostic workload. Production-size
diagnostic benchmarks are manual runs and are not part of the fast package
test suite.

Outputs, under `result/`: `pic_diagnostics_<mode>_turn_times.tsv` and
`pic_diagnostics_<mode>_summary.tsv`. The tracking harness this script includes
also writes `test/result/<seed>/pic_hcc.lum` (`luminosity_io`, `both`) and
`test/result/<seed>/pic_hcc.ele.h5` / `pic_hcc.pro.h5` (`moments`, `both`) --
none of which this entry named (2026-08-05_b audit, U25-8; seed-directory
layout since 2026-08-11).

Tracked results, accuracy checks, and accepted/rejected experiments are in
`../docs/history/strong_strong_diagnostics_benchmark_history.md`.

`moment_observer_backend_consistency.jl` directly compares every default
first- and second-order moment produced by the CPU and CUDA reduction paths.
**It requires a CUDA device** and errors out immediately without one -- it
compares two backends, so there is nothing for it to do on a CPU-only machine
(2026-08-05_b audit, U25-9):

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
(per-boundary discontinuities), `_cells.tsv` (per-source-slice mesh cell
sizes, per-slice-pair vs shared, with worst width/height ratios).

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

An arm is the *full* set of recorded run conditions. `scheme`, `nslices`,
`deposit` and `gridmode` name the arm; every other recorded condition
(`npart`, `turns`, `grid`, `solver`) defines the block it is compared within,
and each arm is measured only against the baseline of its own block. Vertical
growth scales roughly as `1/npart`, so pooling across particle counts inflates
the baseline spread and moves every reported separation — that is a defect this
script had (audit lead U24-1) and now cannot have, because a condition column
joins the grouping key automatically. Two rows sharing a seed *and* all
conditions make the seed spread undefined, so the script errors and names them
rather than averaging.

The `emittance_growth_` prefix is the arm script's namespace. Runs that are not
its products — a modified solver, a repeated seed, a scratch probe — must use a
different prefix.

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

Note that this script computes its own `dropped` column from `_pic_axis_extent`;
it does **not** read `_PICCPUWorkspace.dropped`. Until the 2026-08-03 part-3
audit that runtime counter was written and read by nothing, so a run that lost
charge said so nowhere. `collide!` now warns whenever it is non-zero, which is
the signal to trust in an ordinary run.

```bash
julia --threads=4 --project=. validation/pic_grid_extent_stability.jl
```

Outputs `result/pic_grid_extent_stability.tsv`. Characterization, not a
gate: the script writes the table and exits zero — the "must stay at zero"
expectation above is enforced at runtime by `collide!`'s dropped-charge
warning and by the suite's dropped-charge testsets, not by this script
(2026-08-05 audit, U20).

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
Outputs `result/pic_slice_boundary_jitter.tsv`. Characterization, not a
gate: the jitter is quantified, not bounded (2026-08-05 audit, U20).

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

The script itself CHARACTERIZES — it prints Lambda per solver and exits
zero without comparing to the literature band; the gate lives in the suite:
a reduced-settings version of this check runs there as
`validate(CoherentModePhysicsContract())` — a per-solver physics gate: the
PIC-based solvers must land in the Vlasov band, and the suite asserts that
the soft-Gaussian solver *fails* it (a moment closure cannot carry the
pi mode beyond the rigid value; the failure is the documented model
limitation, not a defect). The symplecticity and high-energy weak-strong
scripts are likewise mirrored by `SymplecticityContract` and
`HighEnergyWeakStrongLimitContract` (2026-08-05 audit, U19-4).

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
truncation (with the corrected erfcx spectral kernel the two agree to 1-2%
wherever a discrete pi mode exists; an earlier Gaussian-suppressed kernel
was wrong and the "10-25% truncation error" once claimed here is
retracted). `coherent_mode_scans.jl` measures the physical 2D Yokoya factor
with the production PIC solver versus flatness (Y = 1.19 round rising to
~1.25-1.27 flat, inside the literature band 1.2-1.33) and versus xi
(xi-independent to ~1% for xi <= 0.01). `plot_coherent_mode_theory.py`
renders result/yokoya_vs_aspect.png, yokoya_vs_xi.png, and
eic_coherent_modes.png from the TSVs.

All four coherent-mode scripts on this page (the simulation driver above,
the two theory companions, the EIC comparison and the BeamBeam3D anchor)
characterize: they write tables and print diagnostics without exiting
nonzero on a physics disagreement. The Vlasov script's numbered self-checks
print PASS/FAIL and warn which rows are then unusable; its one hard stop is
the kernel-sign criterion, whose failure poisons every table (2026-08-05
audit, U19-4/9/10).

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

  NOTE (2026-07): the xi normalization was corrected. The reduction had been
  normalizing its kick to its OWN averaged curvature, which forces u(0)=1
  whatever the kernel does and inflates Lambda by (sqrt2 r + 1)/(r + 1)
  (1.21 at round beams). It now normalizes to the analytic on-axis gradient
  1/[sigma_i(sigma_i+sigma_o)] that defines xi, in BOTH the matrix solve and
  the particle solver. Self-check 4 reports u(0) and fails if the circular
  normalization returns. Round-beam Lambda: 1.40 before, 1.162 after, against
  a measured 2D 1.206.

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
Outputs `result/gaussian_pic_zscan_summary.tsv`. Characterization, not a
gate — but unlike the two hybrid field studies above, this one drives the
production GaussianPIC internals (`_gpic_solve_drifted_field!`,
`_gpic_source_moments`) rather than a local reimplementation (2026-08-05
audit, U20).

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

Overrides: `OCTOPUS_OPT_TAG`, `OCTOPUS_OPT_TURNS`, `OCTOPUS_OPT_NPART`
(or `OCTOPUS_OPT_NPART_E` / `OCTOPUS_OPT_NPART_P` separately),
`OCTOPUS_OPT_GRID`, `OCTOPUS_OPT_NSLICES`, `OCTOPUS_OPT_INTERACTION_GRID`,
`OCTOPUS_OPT_SLICE_INTERP`, `OCTOPUS_OPT_DEPOSIT`, `OCTOPUS_OPT_EXTENT`,
`OCTOPUS_OPT_QUANTIZE`, `OCTOPUS_OPT_DUMP_TURNS`, `OCTOPUS_OPT_TIMING_FROM`,
`OCTOPUS_OPT_BACKEND`, `OCTOPUS_OPT_BATCH_MODE`, `OCTOPUS_OPT_CUDA_ASYNC`.

**Hold batching fixed before comparing GPU costs.** On the GPU,
`interaction_grid=:node` and `slice_interpolation=:quadratic` each also switch
`batch_mode` to `:sequential` and turn `cuda_async` off unless you override
them, so such an arm's `mean_turn_s` is the option's cost *plus* the cost of
losing batching. Measured at 2000 particles on a 32x32 grid: 0.0940 s/turn for
`:node` with the auto-downgrade against 0.0641 s/turn with
`OCTOPUS_OPT_BATCH_MODE=wavefront OCTOPUS_OPT_CUDA_ASYNC=true` -- a third of the
apparent cost was the batching. The run warns when this fires and records both
effective values in `meta.tsv` (2026-08-05_b audit, U25-1).

Outputs, under `result/`: `pic_option_<tag>.tsv` (per-turn luminosity and
moments), `pic_option_<tag>.coords.tsv` (coordinates at the dump turns),
`pic_option_<tag>.meta.tsv` (one row of options, effective batching, timing),
and `pic_option_<tag>.lum` (the task's own luminosity file, rewritten each turn
and read back for the series). The summary script writes
`result/pic_option_consistency_summary.tsv`, and refuses to compare an arm
whose particle count, turn count, grid, slice count or timing window differs
from its baseline -- it names the mismatch instead (U25-8, U25-11).

Outputs under `result/`: `pic_option_<tag>.tsv` (per-turn series),
`.coords.tsv` (coordinate dumps), `.meta.tsv` (options and timing),
`pic_option_consistency_summary.tsv` (cross-option comparison).

## Gaussian Longitudinal Slicing Convergence

`gaussian_slicing_convergence.jl` ranks every `slice_method` of
`GaussianStrongBeamSpec` at EIC weak-strong parameters and simultaneously
verifies the implementations: a rule that is wrong does not converge to the same
limit as the others, so agreement at large `ns` is the check.

It reports Furman's `Q` (Eq. 10 of LBL-37680) against an `ns = 601` reference —
Ref. [1]'s own "algorithm #4 at 300 kicks" reference is circular, scoring every
rule against the asymptote of its own family. The reference is qualified by its
**own** residual, estimated by Richardson extrapolation from three solves at
`ns/2`, `ns` and `2*ns`; that residual is the resolution floor. A cross-family
comparison is printed for context but is not the floor — at `ns = 601` it is
dominated by the comparison rule's own residual. Alongside `Q` it reports
the tracking-free second-moment deficit and its tail/interior split, because
comparing the two fitted orders is what decides whether the binding error is
node placement or the splitting.

Both collision directions are run; the governing hourglass ratio
`sigma_z,strong / beta*_weak` differs by an order of magnitude between them.

```bash
julia --project=. validation/gaussian_slicing_convergence.jl
```

Outputs under `result/`: `gaussian_slicing_convergence.tsv` (Q and moment
deficit per rule/ns/direction), `gaussian_slicing_tail_split.tsv`.

Derivation: `../docs/theory/gaussian_longitudinal_slicing.md`. Recorded run and
conclusions: `../docs/history/gaussian_slicing_convergence_2026_07_31.md`.

## PTC Reference and Lattice Cells

`generate_ptc_reference.jl` drives MAD-X/PTC to produce the table that
`PTCConsistencyContract` checks against. It needs MAD-X on `PATH`; the contract
does not, because the table is committed. The PTC flag set is pinned
(`TIME=false`, `EXACT=true`, `MODEL=1`, plus `METHOD`/`NST` per case) --
`EXACT=false` is MAD-X's default and silently selects the expanded Hamiltonian,
which would validate the wrong model. PTC's `T` column is negated on write,
because its longitudinal variable is conjugate to `delta` with the opposite
orientation.

The 55 cases cover drift, quadrupole (normal and skew), sextupole, octupole,
general multipole, sector bend and combined-function bend at both integrator
orders, RBEND, thin multipoles and solenoids, plus pole-face angles
(`sbend_edge`, `cfbend_edge`, `sbend_fint`), the hard-edge multipole fringe
(`quadrupole_fringe`, `multipole_fringe`, `sbend_fringe`, `cfbend_fringe`),
misalignments through `EALIGN` + `ptc_align` (`quad_mis_*`, `sext_mis_dx`,
`cfbend_mis_*`) and the design-orbit roll (`sbend_reftilt*`, `cfbend_reftilt*`,
`rbend_reftilt*`), the last of these swept over a spread of roll angles from
1e-3 through pi, both signs and both quadrants.

The misalignment cases require `misalign_convention=:madx`: MAD-X references a
misalignment to the entrance frame and composes the three rotations
intrinsically as `R_z R_x R_y`, while Octopus defaults to Bmad's centre
reference and fixed-axis `R_y R_x R_z`. A single rotation cannot tell the two
apart, so `quad_mis_all` and `cfbend_mis_all` set all six degrees of freedom at
once, which is what pins the order. The misaligned-bend cases must also set
`bend_model=:drift_kick`, since PTC runs `MODEL=1`; comparing an exact-splitting
bend produces an O(1e-3) residual that mimics a wrong exit patch.

The `reftilt` cases pin a keyword *meaning*, not only a map: MAD-X's `tilt` on a
bend rolls the design orbit and is Octopus's `ref_tilt`, while Octopus's `tilt`
is the body roll MAD-X sets with `EALIGN, dpsi`. `sbend_reftilt_vertical` is a
literal `pi/2` — a vertical bend. The last two carry a roll *and* a
misalignment, which is the only configuration in which the frame an alignment
error is quoted in becomes observable; every candidate convention agrees when
just one of the two is nonzero, and all of them are symplectic, so neither the
one-at-a-time cases nor a symplecticity check can substitute. The `rbend_reftilt*`
cases repeat this through the RBEND path, which reaches the sector map by adding
`angle/2` to each pole face — a conversion the roll has to survive rather than be
assumed to. See `docs/history/ref_tilt_2026_08_02.md`.

Two traps are pinned in the script's header comment and are worth repeating.
The fringe is enabled **per element** with `permfringe=true`, never with
`ptc_setswitch, fringe=true`: the global switch ends with
`default = intstate; call update_states`, so after `ptc_create_layout` it
silently reverts `TIME` to true and changes the longitudinal variable, while
before `ptc_create_layout` the layout resets it and the fringe never runs. And
the fringe cases must set `highest_fringe=2` on the Octopus side, because that
is PTC's `HIGHEST_FRINGE` default and Octopus deliberately does not cap by
default.

```bash
julia --project=. validation/generate_ptc_reference.jl
```

`lattice_cells.jl` builds FODO, DBA and TBA cells from those magnets and checks
that they compose into working lattices: one-turn symplecticity by complex step,
linear stability in both planes, Courant-Snyder invariant drift measured on
momentum, and CPU/CUDA tracking consistency. Quadrupole strengths are found by a
stability scan rather than hand-tuned, and the chosen working point is reported.

```bash
julia --project=. validation/lattice_cells.jl
```

Overrides: `OCTOPUS_LATTICE_N`, `OCTOPUS_LATTICE_TURNS`, `OCTOPUS_LATTICE_LONG`.
Outputs `result/lattice_cells.tsv`. Derivations for every map:
`../docs/theory/lattice_hamiltonian_and_conventions.md`.

## Paper Anchors

Two paper-cited scripts. They were committed and cited with no README entry at
all until the 2026-08-05 audit (U21-1), and the entries added then sat at the
tail of the PTC/lattice section above with no metric and no outputs
(2026-08-05_b audit, U25-12).

`crossing_luminosity_anchor.jl` anchors the crossing-angle luminosity reduction
against the closed-form geometric factor, through the Lorentz boost pair.
Symmetric Gaussian beams with the hourglass suppressed (`beta* >> sigma_z`) and
a tiny bunch charge so beam-beam is negligible; three configurations -- head-on,
half-crossing 12.5 mrad without crabs, and the same with ideal crabs.

Reference model: the continuous Piwinski factor `R = 1/sqrt(1 + phi^2)`, and the
15-quantile-slice discrete sum, which isolates slicing error from the geometric
factor. Error metric: relative difference of the measured luminosity ratio
against each reference.

```bash
julia --startup-file=no --project=. validation/crossing_luminosity_anchor.jl
```

Outputs, under `result/lum_anchor/`: `lum_headon.lum`, `lum_crossing.lum`,
`lum_crab.lum`. `paper/data/crossing_lum_anchor.tsv` is a hand-transcribed copy
for the paper.

`tune_estimator_calibration.jl` calibrates the coherent-mode tune estimator's
Hann-window plus parabolic peak interpolation on synthetic two-tone signals
mimicking sigma/pi dipole spectra, where the true tunes are known by
construction.

Error metric: median, p95 and maximum of `|Q_hat - Q_1|` over 500 trials.
Writes no files -- the calibration table is the printed output.

```bash
julia --startup-file=no --project=. validation/tune_estimator_calibration.jl
```
