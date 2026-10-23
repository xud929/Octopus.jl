# Validation Scripts

Validation scripts are developer-facing numerical checks. They may use internal
helpers to test implementation details and should not be treated as public API
examples.

The package regression suite is separate from these scientific validations
and benchmarks. Plain `Pkg.test` at `--threads=4` is the full gate and
`lane=fast` is a development checkpoint; the commands are in `AGENTS.md`
(Verification Matrix) and `docs/guides/development_workflow.md`.

## The gate's CUDA arm (CUDA-requiring scripts)

CI has no GPU, so a script that requires a CUDA device is run by nobody unless
the GPU machine's gate runs it: three committed scripts died on the 2026-08-18
retirement of a constructor and nothing executing noticed for two months
(comprehensive audit 2026-10-18, A-4, F-200, F-236). Since 2026-10-20 the full
lane's last testset, "CUDA-requiring validation scripts run in the gate's CUDA
arm" (`test/runtests.jl`), runs every CUDA-capable script of `validation/` and
`profiling/` in a subprocess at a reduced size when the test process has a
device, and records a visible skip naming them when it has none (CI). The
subprocess loads Octopus as a package (`-L` with `using Octopus`, so each
script's `isdefined(Main, :Octopus)` guard skips the source include) with the
gate's own flags (`--check-bounds=yes`) and thread count.

The list is derived, not kept: a script is CUDA-capable when its code carries a
`CUDA.functional() || error/return` refusal, the `OCTOPUS_REQUIRE_GPU_CONTRACT`
parser `Octopus._require_gpu_contract()`, a leg behind
`_contract_backends_available(CUDABackend)`, or a harness include that defaults
`OCTOPUS_USE_GPU` to 1. Every such script carries one machine-readable header
line that the testset reads,

```text
GATE-CUDA-ARM: env K=V ... ; verdict "<substring of its stdout>" [; outputs <repo-relative path> ...]
GATE-CUDA-ARM: args k=v ... ; verdict "<substring of its stdout>"
GATE-CUDA-ARM: excluded -- <reason>
```

whose `env` is the reduced size and the switch that selects or requires the
CUDA leg (`args` instead for a driver that takes key=value arguments; `@TMP@`
in a value is a fresh temporary directory, removed after the run), whose
`verdict` must appear in the run's output beside exit 0, and whose
`outputs` must exist after the run and are removed by the testset so a gate run
leaves nothing beside a study's files. A CUDA-capable script without the line
fails the testset by name; a run line on a script with no marker fails as
stale; an `excluded` line is printed, so an exclusion is a decision on record
(today the two CUPTI profiler wrappers, `profiling/profile_strong_strong_cuda.jl`
and `profiling/cuda_device_profile.jl`, which need the external profiler and
read nothing a gate could assert). The testset also fails by name on a derived
script this section does not list, so the table below cannot drift from the
derivation. The script's own
switch for insisting on its CUDA leg is `OCTOPUS_REQUIRE_GPU_CONTRACT=1`
(`lattice_cells.jl` and `near_round_gaussian_transition.jl` honour it since
2026-10-20, `public_configuration_effectiveness.jl` since 2026-10-22 -- it
printed `status = skipped` and exited 0 under the flag, audit F-243/U54-4;
`tracking_backend_consistency.jl` and the other contract runners did).

Reduced sizes and wall times as the testset measured them on 2026-10-20
(RTX 4500 Ada, the owner's 12 GB kernel resident, `--check-bounds=yes`,
`--threads=4`, 4 scripts at a time on the 128-core node, one package load
of about 15 s in every figure; a script's wall is its own process's, under that
concurrency). The arm's wall was 407.1 s (6 min 47 s) for 18 scripts whose own
times sum to 1482.1 s; the budget rule in `AGENTS.md` is ten minutes for the
whole arm:

| script | reduced size (the header's `env`) | wall |
|---|---|---|
| `beam_optics_interface_consistency.jl` | require the GPU leg | 23.3 s |
| `eic_emittance_benchmark.jl` | 2 turns, 2000 per beam, CUDA | 89.6 s |
| `high_energy_weakstrong_limit.jl` | 4000 particles, 3 slices, grid 48, spectral (63,255), CUDA spectral leg | 73.7 s |
| `lattice_cells.jl` | 512 particles, 2 turns, 200 drift turns, GPU leg required | 184.6 s |
| `moment_observer_backend_consistency.jl` | 20000 particles | 13.4 s |
| `near_round_gaussian_transition.jl` | the full sweep, parity required | 70.6 s |
| `pic_option_consistency.jl` | GPU, 4 turns, 2000 particles, grid 32, 5 slices, tag `cuda_arm_gate` | 90.2 s |
| `public_configuration_effectiveness.jl` | the contract's own fixtures, GPU leg required (joined 2026-10-22; measured alone, not under the arm's concurrency) | 209 s |
| `soft_gaussian_pic_comparison.jl` | 4000 particles, 5 slices, grid 32 | 62.9 s |
| `strong_strong_diagnostics_benchmark.jl` | 4000 per beam, 12 turns, mode `both` | 91.6 s |
| `strong_strong_gaussian_backend_consistency.jl` | 1000 particles, 1 turn, GPU leg required | 70.0 s |
| `strong_strong_observer_plan_consistency.jl` | 1024 particles, GPU leg required | 42.3 s |
| `strong_strong_pic_cache_backend_consistency.jl` | 1000 particles, 2 turns (the cache contract refuses one: nothing is reused), GPU leg required | 92.5 s |
| `strong_strong_pic_extreme_benchmark.jl` | 4000 per beam, 20 turns | 86.3 s |
| `strong_strong_spectral_comparison.jl` | CUDA, 4000 particles, 2 turns, 5 slices, grid (64,256) | 94.9 s |
| `tracking_backend_consistency.jl` | 2000 particles, GPU legs required | 132.0 s |
| `tracking_context_policy_consistency.jl` | GPU legs required | 41.2 s |
| `profiling/benchmark_strong_strong_pic.jl` | 2000 per beam, grid 32, 5 slices, 1 turn, 1 repeat | 120.6 s |
| `profiling/crab_cavity_noise_backends.jl` | crab harness, 2000 macroparticles, 30 turns, arms `threads:4` and `cuda` | 102.4 s |

The two benchmarks' timings at these sizes are run receipts, not performance
records. The arm's total above is the 2026-10-20 measurement of 18 scripts;
the nineteenth, the effectiveness script, adds its own time and has not been
re-measured under the arm.

## Near-Round Gaussian Transition

`near_round_gaussian_transition.jl` validates the precision-scaled smooth
transition between the near-round potential expansion and the elliptical
Bassetti-Erskine evaluator. It compares force and principal covariance
response with the fixed-interval Gaussian integral, checks exact flat-beam core
gradients, estimates value and first-derivative gaps at both blend endpoints,
measures six-dimensional symplecticity, and checks CPU/CUDA parity when CUDA
is available.

Gated, with the bounds and their derivation in the script's main block: the
Float64 force and response relative errors, the observed/nominal conditioning
ratio of both types, and -- since 2026-10-20 (comprehensive audit 2026-10-18,
F-238; three of about fifteen metrics were gated and the rest printed) -- the
Float64 core-gradient error, the 6D symplectic residual and all eight endpoint
continuity gaps, which are the only instrument that sees the first and last
few percent of the blend interval. The script then re-feeds the recorded x1.1
evaluator defect (Phase 12 of `docs/comprehensive_audit.md`) over a mid-blend
window and over both endpoint windows and requires the metrics to see it, on
every run. `OCTOPUS_NEAR_ROUND_DEFECT=mid|inner_edge|outer_edge` injects the
same defect into the main sweeps so a gate can be shown red;
`OCTOPUS_REQUIRE_GPU_CONTRACT=1` makes a missing device fail the parity leg.

```bash
julia --project=. validation/near_round_gaussian_transition.jl
OCTOPUS_NEAR_ROUND_DEFECT=inner_edge julia --project=. validation/near_round_gaussian_transition.jl   # exits 1 at the inner continuity gate
```

The derivation, implementation constants, and recorded reference run are in
`../docs/theory/near_round_bassetti_erskine_switch.md`.

## Public Configuration Effectiveness

`public_configuration_effectiveness.jl` checks that registered public
configuration reaches real runtime consumers. It exercises CPU logical-worker
counts, fused CUDA thread/block sweeps, CUDA device mismatch rejection, all
CUDA PIC launch families, optimized wavefront and non-default sequential PIC
branches, schedules, buffers, inherited/inactive reports, and pre-mutation
configuration rejection. CUDA-unavailable runs are reported as skipped, and
under `OCTOPUS_REQUIRE_GPU_CONTRACT=1` a skip is an error with exit 1 (the
sibling contract scripts' switch; until 2026-10-22 this script printed
`status = skipped` and exited 0 under it -- audit F-243/U54-4). Receipt, fix
batch 4: with CUDA hidden and the flag set, the pre-fix script exits 0 on
`status = skipped`, the fixed one exits 1 naming the flag; with the device,
`cuda_status = passed` in 209 s under the gate's flags; of the two "already
held" counter-RNG warnings the 2026-10-18 audit saw (U54-10, = F-49, fix
batch 2) one remains in every run's output -- `rng_id 1, claimed explicitly by
a beam consumer, is already held in this process by a bpm_observer consumer`
(`src/math/counter_rng.jl:280`), raised by the contract's own fixtures, a
`src/contracts` matter outside this batch's scripts and reported as a lead.

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

`data/gaussian_pic_field_validation_summary.tsv` in the paper repository
(https://github.com/xud929/2026_octopus_cpc; Figure 2) carries 24
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
`OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda` for CUDA runs; grid-free and the
field micro-profile are CPU-only, and on CUDA the summary says both were NOT
run (`free_grid = requested ... but NOT RUN`, `field_microprofile_rows = none`)
where it used to print the request flag as if the arm had run (comprehensive
audit 2026-10-18, F-227); the gate's CUDA arm runs the CUDA backend at 4000
particles. `OCTOPUS_SPECTRAL_COMPARE_GRID` is a mesh-and-mode shape for the
grid solver, while `OCTOPUS_SPECTRAL_COMPARE_FREE_GRID` is a direct mode-count
shape for the grid-free solver.

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
generator at the smaller `N` this file recommends (U25-3). Every bound is six
sigma of the statistic's own sampling sd and is printed beside the value: the
means and correlations `1/sqrt(N)`, the normal variance `sqrt(2/N)`, the
uniform variance `sqrt((mu_4 - sigma^4)/N) = 1/sqrt(180 N)` (mu_4 = 1/80,
sigma^2 = 1/12), and the three tail fractions `P(|N| > 2, 3, 4)` their
binomial sd `sqrt(p (1 - p)/N)` with `p` from the package's normal CDF. Until
2026-10-22 the uniform-variance bound was the normal-case `sqrt(2/N)` scaled by
the variance -- 1.58 times too loose, a 9.5-sigma gate called six -- and the
tail fractions were printed "expected about ..." and never judged, so a
generator with clipped tails passed (comprehensive audit 2026-10-18, F-209:
U40-6, U40-7). Receipt, fix batch 4 at `N = 200000`: `counter RNG validation
passed` with the uniform variance `0.083248` against `1/12` within `1.0e-3`
and the tails `0.04548 / 0.002615 / 4.0e-5` against `0.04550 / 0.00270 /
6.33e-5` within their bounds; the same run with the normal generator clipped
at `|x| <= 3` FAILS the two outer tails (the pre-fix script passed it), and
with the uniform variance inflated by 1.6 % FAILS the variance bound at
`1.25e-3` against `1.0e-3` (the pre-fix bound was `1.58e-3`; it passed).

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

## Strong-Beam Kick Fingerprint

`strong_beam_kick_fingerprint.jl` is a refactor guard for the weak-strong kick
chain: nine strong-beam configurations (every virtual-drift model, coupled
moments, nonzero centre/angle/curvature, a 6x6 covariance with crab slope)
tracked two turns through both loop copies, printing an order-sensitive
digest of every coordinate and the luminosity. Run it on two checkouts
(`OCT_ROOT` selects the second) and diff the `BR` lines; equal lines mean no
bit moved. Same-machine, same-Julia-build comparisons only. Added with
multi-process step 1 (2026-09-04), where it showed the slice-carrier change
bit-identical on every branch the production line does not exercise.

## Tracking Backend Consistency

`tracking_backend_consistency.jl` runs `ElementTrackingBackendConsistencyContract`
on a deterministic tracking line that carries **every element kind declaring
that contract** (30 at the 2026-10-18 count; the script's own coverage
tripwire holds the number, this page used to say 29): the whole thick-magnet
family, every thin element, patch, marker, aperture, both cavities, and
stochastic `LumpedRad`. It always runs CPU/CPU and runs CPU/GPU when CUDA is
visible or explicitly requested; the gate's CUDA arm runs it with the GPU
legs required at 2000 particles.

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
`:thin_accelerating_cavity` is single-pass by contract (`execute!` refuses a
window that re-traverses it), so it rides its own one-turn line after the
multi-turn checks rather than the shared line; the coverage tripwire counts
both lines. It had sat in the multi-turn line since 2026-08-14, which made the
script's default two-turn run throw at its first `validate` until the
2026-09-04 neighbour audit ran it as a targeted check (the fix's blast radius
was not re-walked over the validations that construct cavities -- the second
time for this script).

The two cavity kinds ride the multi-turn line twice: bare, and with
turn-by-turn modulation rules -- a `WhiteNoise` on a fixed stream id beside a
`TurnTable` of exactly the run's turn count, on the crab cavity and on the RF
cavity -- so the `TurnModulated` wrap, its device conversion and the per-turn
host `update_line` are on the path of both arms. Until the 2026-10-16
neighbour audit (S2-1) no case here carried a rule, and the device conversion
the crab-noise campaign added was verified by the suite's identity testset
only. A second tripwire, derived from the element schemas (every kind with a
`phase_noise` parameter), fails the run if a modulatable kind compiles to no
wrapper, so the cases cannot quietly revert to covering the wrap by name.
Measured 2026-10-16 (N = 10000, 2 turns, CUDA active): CPU/CPU `max_abs_error`
0 and CPU/GPU 6.3e-16 (`max_component_rel_error` 8.9e-12 against the 1e-10
tolerance), against 5.3e-16 for the same line before the modulated cases
joined it: the rules add nothing to the agreement class.

After the composed-line contracts the script checks EVERY instance of its
lines alone against the kind's declared cross-backend rounding class
(`_cross_backend_rounding`, `CrossBackendRounding` in `src/track/Track.jl`;
fix I of the 2026-10-16 neighbour audit, 2026-10-17): the instance is tracked
on the CPU twice (bitwise in every coordinate, the determinism check) and on
the CPU against CUDA, and a coordinate the class declares bitwise -- never
written, or written through single IEEE operations or arithmetic exact under
any FMA fusion -- must agree to the bit, while a coordinate of the ulp class
must agree within the declared bound in ulps of the coordinate's scale over
the beam. The composed line keeps its one tolerance because it mixes every
kind; the per-kind table is where each declaration meets its measurement, and
a violation fails the run by name. The script's header states the rule (the
device fuses `a*b + c` into one FMA where the host rounds twice, and its libm
differs on transcendentals), `docs/current_runtime.md` "Current Backends"
carries the resulting table of what is bitwise, and the suite's
"Cross-backend rounding classes" testset measures the registry examples the
same way. Measured 2026-10-17 (N = 10000, 2 turns, CUDA active): every
instance within its class; the printed table is the record.

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

## Turn Modulation Spectra

`turn_modulation_spectra.jl` is test 9 of `docs/design/turn_modulation.md`
(section 8): the shipped stochastic turn-modulation rules, `WhiteNoise` and
the Voss-McCartney `PinkNoise`, have the spectra the note's section 5.5
measured, and the pink rule is stateless. Both sequences go through the
public path a run tracks -- a `ThinCrabCavitySpec{1}` carrying the rule as
`phase_noise`, compiled with `compile_runtime` and realised once per absolute
turn with `realize`, as `update` does inside `execute!` -- so the sequence is
exactly the one a tracking run would apply. The power per octave band of the
periodogram (bins `2^i .. 2^(i+1) - 1` of the mean-subtracted sequence),
normalised to the top octave, is printed as the note's table, each band
labelled by its bin frequencies `(2^i - 1)/N .. (2^(i+1) - 2)/N` in `f_rev`
units (the labels printed until 2026-10-13 were one bin high, `2^i/N ..
2^(i+1)/N`; no verdict reads them -- neighbour audit, U7-5); the two lowest
bands (2 and 4 bins) are printed but excluded from every slope, as the note
says.

Verdicts, all required for PASS: the least-squares slope of `log2(power)` per
octave over the trusted bands is `+1 ± 0.15` for white and `0 ± 0.2` for
pink (the note's test 9 tolerances; the construction's ripple, about a factor
1.3 across twelve octaves in the note's table and `0.738` to `1.241` of the
top octave for the shipped rule at 65536 turns, is band-to-band scatter the
fit averages); the pink sequence's rms about zero for `sigma = 1` lies in
`[0.8, 1.25]` (the script's own bound: the K octave generators are
independent unit normals, so the expectation of `rms^2` is exactly 1 at any
length, but the slow generators take one or two values in a run and the
sample rms of one run scatters with a one-sigma of 7.6 % at 65536 turns and
14.7 % at 16384, `Var[rms^2] = (2/(K^2 N)) sum_k min(2^k, N) (2K - 1 - 2k)`
-- the `min` because a generator slower than the run holds one value; with
`2^k` alone the form is valid while `2^(K-1) <= N` and reads 15.3 % at 16384,
and the "13.8 %" written here, in the script's header and in the suite's twin
until 2026-10-22 was the value of neither (audit F-209/U40-8) -- with a heavy
upper tail; the rms distribution is skewed, so half the sd of `rms^2`
overstates it: Monte Carlo over 8192 synthetic streams gives 13.3 % at 16384
(`result/fix_batch4_2026_10_22/probes/VA/probe_pink_rms_sigma.log`) and 5.6 %
of streams outside the band (0.6 % at 65536 turns, 2048 streams, 2026-10-13);
measured `0.9054` at 65536 turns and `0.8799` at 16384, both deterministic at
seed 42); and the
pink offset on one turn computed alone from a fresh compile equals the
sequence's entry exactly. Beside the rms the script prints the sample
standard deviation about the run's mean with its expectation
`E[s^2] = (N/(N-1)) (1 - (1/K) sum_k min(2^k, N)/N)` (generator `k`
contributes `2^k/N` to the variance of the mean while `2^k <= N` and exactly
1 once `2^k > N`, its single value being removed by the mean): `0.9375` at
65536 turns, `0.8126` (std `0.9014`) at 16384, Monte Carlo `0.8125 ± 0.0027`;
the form `1 - (2^K - 1)/(K N)` printed until 2026-10-13 charged generator 15
with 2 instead of 1 and gave `0.7500` (std `0.8660`) at 16384, the number
the stage-1 record's section 8 quotes (neighbour audit, U7-3). Not a
verdict. The
note's own slope definition (the two-endpoint change over all bands; `+1.09`
white and `-0.11` pink in the note's table, `+0.991` and `+0.049` for the
shipped rules at 65536 turns) is printed for comparison and not judged: its
endpoints are the untrusted bands. Measured 2026-10-12 under the rules'
counter-RNG component band (`_RULE_COMPONENT_BASE`): `white_slope=0.9839
pink_slope=0.0102 white_rms=0.9966 pink_rms=0.9054` at 65536 turns and
`white_slope=0.9573 pink_slope=-0.0389 white_rms=0.9908 pink_rms=0.8799` at
16384, both `stateless=true verdict=PASS`.

Run with the note's size (65536 turns, seed 42):

```bash
julia --project=. validation/turn_modulation_spectra.jl
```

Run the suite's reduced size:

```bash
OCTOPUS_SPECTRA_TURNS=16384 OCTOPUS_SPECTRA_SEED=42 \
julia --project=. validation/turn_modulation_spectra.jl
```

`OCTOPUS_SPECTRA_TURNS` must be a power of two of at least 1024 (whole octave
bands). The last line is machine-readable,

```
TM-SPECTRA white_slope=<v> pink_slope=<v> white_rms=<v> pink_rms=<v> stateless=<bool> turns=<N> seed=<s> verdict=PASS|FAIL
```

and the exit status is 1 on any failed verdict. When the git-ignored
`result/` directory exists under the project root, the band table is also
written to `result/turn_modulation_spectra.tsv` (never evidence; the
committed record is `docs/history/turn_modulation_stage1_2026_10_12.md`,
section 8). The suite runs a reduced-size twin, 16384 turns with the same
rules, seed and estimator and the script's slope tolerances, in the testset
"Turn modulation: white and pink spectra"; its pink rms bound is that size's
own quantile bound, `[0.75, 1.6]` (below the Monte-Carlo 0.1 % quantile of
the rms, `0.779`, and above its 99.5 % quantile, `1.538`; 7 of 2048 streams
outside, against 120 for `[0.8, 1.25]` at 16384 turns), stated at the test
with the keying pinned bitwise beside it.

## Crab Cavity Noise Response

`crab_cavity_noise_response.jl` is the numerical study behind
`examples/crab_cavity_noise.jl`: the EIC weak-strong crab-crossing case of
`examples/weak_strong_tracking.jl` with turn-by-turn RF phase and amplitude
noise on both proton crab cavities (`tccb` before the IP, `tcca` after it)
at the owner's production point -- phase rms 10 urad and relative amplitude
rms 1e-4 per active harmonic (1 and 2), each cavity on independent streams,
the strength rule's relative sigma `1e-4` scaling both planes of the
harmonic as `S (1 + d)` (the shipped semantics since 2026-10-15, record
`docs/history/crab_cavity_noise_relative_strength_2026_10_15.md`). Reference model:
`docs/theory/crab_cavity_noise_response.md` (section 6 the predicted rates,
section 7 the plan this script executes, section 8 the interpretations it
adopts); the rules' own contracts are `docs/design/turn_modulation.md`,
sections 5.1, 5.2, 5.5 and 5.6. The script answers the example's three
questions in six parts, selected by the first argument, with `key=value`
overrides after it (every key with its default is in the file header). The
parts that run the harness parse its `CRAB-NOISE` line and check its
READBACKS against the request: `chrom`, `kbb_scale` and `radiation` are read
by the harness from the compiled line the task tracked, `seed` from the
artifact's `/execution` ledger and `device` from the `:cuda_device` receipt
(an index under `gpu=1`, `NA` under `gpu=0`, required either way), so the
check compares what ran with what was asked rather than the request with
itself (2026-10-16 neighbour audit, U7-3 and U7-4):

1. Do the rules generate the specified noise? Part `noise` (CPU, about two
   and a half minutes after the load, the three spectral cases included):
   the sequences a run would apply, produced the way
   a run produces them -- a `ThinCrabCavitySpec{3}` with the example's
   strengths compiled into a `TurnModulated` and realised by the pure
   `Octopus.update` hook on every absolute turn, seed 123456789, the
   example's stream ids 11, 12, 14, 15 (tccb) and 21, 22, 24, 25 (tcca) --
   for 65536 turns by default. Metrics, each printed PASS/FAIL with its
   number: the sample rms against sigma (white and table within
   `3 sqrt(1/(2N))`, 0.83 % at 65536; pink judged on the slot realised over
   `long_turns` (default 2^20) turns against the two-sided 99 % band of the
   construction's rms over `rms_streams` (default 4096) synthetic streams of
   that length (owner decision 2026-10-14), the N-turn rms -- whose one-sigma
   from `Var[rms^2]/sigma^4 = (2/(K^2 N)) sum_k 2^k (2K - 1 - 2k)` is 7.65 %
   at K = 16 and N = 65536 -- printed as INFO with its Monte Carlo two-sided
   p-value from 2048 reference streams); the pink
   cells rebuilt bitwise from the counter RNG and its distinct generator
   draws unit-normal within `3 sqrt(2/M)`; the mean within three times its
   own one-sigma (pink: `sigma^2 (2^K - 1)/(K N)`, not `sigma^2/N`); the
   octave-band spectrum as `turn_modulation_spectra.jl` measures it (white
   and table slope `+1 +- 0.15` per octave, pink `0 +- 0.2` and the band
   shape against 2048 synthetic Voss-McCartney streams, chi-square at
   99.9 %); the pairwise independence of the eight active slots (`|rho| <=
   3 se` at lag 0, se from Bartlett's formula for pink, `1/sqrt(N)` for
   white); the strength rule applied as the relative factor of 2026-10-15,
   `strengthX == S (1 + d)` and `strengthY === 0.0` bitwise on every turn
   and the factor recovered from the realised strengths within 4 ulp of the
   rule's value (the additive-era item "equal on both planes" is the frozen
   2026-10-14 record's); harmonic 3
   and the base element untouched bitwise; the `scale` factor exact to
   1e-12; the table realised bitwise from its record, and its digest, name
   and length in the artifact provenance of a short CPU `TrackingTask` run.
   Two items added since. `recorded` (2026-10-15, the recorder of
   `docs/design/turn_modulation_record.md`): per rule a CPU `TrackingTask`
   of the two cavities alone tracks the 65536 turns with the artifact's
   `record_turn_modulation = true`, and every active slot's recorded
   `series`, read back through `turn_modulation_provenance(path)`, equals
   the hook's replay bitwise for white, pink and table (and, for the table
   rule, the record's first 65536 entries as well), the artifacts
   `noise_recorded_<rule>.h5`. `spectral` (2026-10-16; the producer and the
   consumer together, `docs/design/spectral_turn_table.md` section 6 check
   7): three cases, the `:flat` preset over the narrow band (3e-3, 4e-3)
   cycles per turn and the `:pink` preset over (2^-14, 1/2) with fixed bin
   amplitudes, and `:flat` over the narrow band with Rayleigh amplitudes;
   per case the eight slots carry `SpectralNoise` rules on the example's
   stream ids through the same CPU task with the record on, and per slot the
   recorded series equals the library factory's own table for the global
   seed, the rule's `rng_id` and its slot (phase harmonic i is slot i,
   strength harmonic i slot 3 + i) bitwise, the provenance carrying kind
   `:table`, the digest, the canonical name and the length; the periodogram
   of the recorded series over the analytic `c^2 S(f_k)` equals the preset's
   shape within 1e-10 relative on every band bin with fixed amplitudes
   (every out-of-band bin, DC included, below 1e-12 of the band peak and
   the rms within 1e-12 of sigma), and with Rayleigh amplitudes the band
   mean lies within `5/sqrt(K)` of 1, the rms within `5/(2 sqrt(K))` of
   sigma, the sample variance of the K ratios is at least 0.1 (fixed
   amplitudes give exactly 0, the anti-vacuity of the statistical pins) and
   the out-of-band bins are as before; below K = 8 bins the Rayleigh
   statistics are a counted FAIL naming the bin count; the artifacts
   `noise_recorded_spectral_<preset>_<amplitudes>.h5`.
2. What is the beam-beam response? Parts `pilot` and `sweep` (GPU), which
   run the harness `test/examples/crab_cavity_noise.jl` as a subprocess per
   case and parse its final `CRAB-NOISE` line after checking that the
   receipt states the requested configuration (rule, scale, turns,
   macroparticles, `kbb_scale`, radiation, the effective sigmas, the
   chromaticity, the table file's digests). Estimators from the artifact's
   `/moments/weak_beam`: the raw action `J_raw`, the central emittance
   `eps_c` and the centroid action `J_c` per plane, each fit by least
   squares over turns `[n0, T]` (n0 = 2000) after subtracting the no-noise
   baseline with the same seed, as rates relative to the design emittances
   (1.128e-8 m horizontal, 1.004e-9 m vertical); the luminosity's mean and
   relative trend over the same window. `pilot` calibrates (white at scale
   100 and 30, the baseline drift, a `kbb = 0` case, the ms per turn at the
   sweep's size and the projected wall clock); `sweep` runs every row of the
   theory note's section 7 sweep table by default -- B0, W1-W3, P1, T2, A4,
   A4s, A2, A05, AP1, AT1, C0, C1, C2, T1, the order of the script's
   `SWEEP_CASES` from which the default `cases=` list is derived -- and the
   optional C3 on request through `cases=` (1e5 turns, 2^17 for the pink
   runs, 2.5e4 for A4 and A2, 1.25e4 for A4s; 1e6 macroparticles; radiation
   off; moment step 1), one TSV row per case, resumable. Until 2026-10-22 the
   default was a hand-typed list of 14 without A05, A2 and A4s, so a default
   sweep could not deliver acceptance item 2 for amplitude noise and `report`
   ended PASS on 49 checks instead of 60 (comprehensive audit 2026-10-18,
   F-209/U40-12; fix batch 4, D13). Part `tablefile` writes W1's realised offsets as the harness's
   `OCTOPUS_TABLE_FILE` for T1 (exact Float64 round-trip, FNV-1a digests
   printed); part `control` is the sharp linear check of C1, the recorded
   centroid against the realisation-aware prediction propagated through the
   linear maps, PASS within 1 % of its rms excursion.
3. How do the rules compare? Part `report` on a sweep TSV: the theory
   note's acceptance items 1-8, each PASS/FAIL with its number and
   tolerance -- the W1, W2, W3, A05, A1, A2, T2 and AT1 horizontal rates
   within a factor 1.25 of the reference (`ref_*` times s^2; the references
   are overridable arguments whose defaults are the note's section 6 values,
   1.72e-7 per turn for phase white in x and 1.10e-6 for amplitude white in
   x; `ref_amp_white_y` is retired and refused, the vertical rates under
   amplitude noise being the beam-beam coupling alone, printed as INFO) and
   the B0 slope below 5 % of the s = 1 prediction; the s^2 exponent within
   0.1 (phase from W1-W3, amplitude from A05, A1, A2; A4 and A4s are INFO at
   the small-growth regime's edge); P1/W1 and AP1/A1 within 25 % of the pink
   ratio 0.15 in x (the y ratio printed against 0.17 as INFO); T1 equal to
   W1 to 1e-10 relative on every moment column; `eps_c` growing at least 0.8
   of `J_raw` with the second-half `J_c` below 10 % of the growth (the
   colliding runs' vertical rates printed, the plane mapping judged on the
   C1 and C2 controls at 5 % of the predicted x rate); the C1 and C2
   controls; the fit quality (two-half slopes within 20 % of the rate,
   residual rms below 5 % of the growth). The falsifiers are printed by name
   when they trigger; no verdict uses a constant that is not printed
   (brought current 2026-10-22 with the script's `report` header; audit
   F-208). The four reference numbers are declared once, in the script's
   `REPORT_REFERENCE_DEFAULTS` (the note's sections 6 and 5.2); the header's
   usage lines are held to the code at load -- every part compares each
   documented `key=value` default with the one its code supplied and refuses
   a disagreement, a documented key it does not read or a read key the header
   omits, printing a receipt line (`options: part report reads 18 keys; the
   header's 14 documented defaults equal the code's`) -- and the suite holds
   the declaration to the note's own text and the header's `cases=` list to
   the sweep table (testset "Elements and scripts follow-ups", part 4b; fix
   batch 4, D13). The summary line counts the items a TSV could not deliver:
   `CRAB-NOISE-REPORT checks=60 failed=0 not_evaluated=0 verdict=PASS` on
   the 2026-10-15 sweep (S0B, 18 rows) and `checks=49 failed=0
   not_evaluated=5 verdict=PASS` on the same TSV cut to the former
   14-case default (fix batch 4 receipts, `result/fix_batch4_2026_10_22/probes/VA/`).

Run from the project root (`artifact_dir` should be a local disk: the
per-turn observer write on a networked filesystem dominates a long run):

```bash
julia --project=. validation/crab_cavity_noise_response.jl noise
julia --project=. validation/crab_cavity_noise_response.jl tablefile
julia --project=. validation/crab_cavity_noise_response.jl pilot gpu=1 threads=4 artifact_dir=/local/scratch
julia --project=. validation/crab_cavity_noise_response.jl sweep tag=<tag> gpu=1 threads=4 artifact_dir=/local/scratch
julia --project=. validation/crab_cavity_noise_response.jl report tsv=result/crab_noise/sweep_<tag>.tsv
julia --project=. validation/crab_cavity_noise_response.jl control tsv=result/crab_noise/sweep_<tag>.tsv case=C1
```

Outputs under `out=` (default `result/crab_noise/` under the project root,
git-ignored, never evidence): `noise_summary.tsv`, `noise_correlations.tsv`,
`noise_pink_bands.tsv`, `noise_table_provenance.h5`, `noise_recorded_<rule>.h5`
and `noise_recorded_spectral_<preset>_<amplitudes>.h5` from `noise`;
`W1_realised_offsets*.tsv` from `tablefile`; `pilot.tsv`, `sweep_<tag>.tsv`
and `control_<case>_centroid.tsv`, the subprocess logs under `logs/` and the
artifact copies under `artifacts/`. Each judging part ends with one
machine-readable line (`CRAB-NOISE-RULES`, `CRAB-NOISE-REPORT` with its
`not_evaluated` count, `CRAB-NOISE-CONTROL`, each `... verdict=PASS|FAIL`) and
exits 1 on any FAIL. In `noise_pink_bands.tsv` the column `judged` marks
exactly the bands the pink band-shape chi-square sums (the trusted bands below
the normaliser, whose own z is NaN: a zero deviation over a zero sd); it was
named `trusted` and flagged the normaliser too until 2026-10-22 (audit
F-209/U40-14).
The committed record with the measured numbers is
`docs/history/crab_cavity_noise_validation_2026_10_14.md`.

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
weak-strong reference built from the same slice arithmetic (so its luminosity
agreement is a same-arithmetic identity, as the contract docstring says),
compares PIC to the same reference with grid/model tolerances, and verifies
that spectral grid and grid-free strong-strong maps collapse to frozen-source
spectral weak-strong references. Every arm asserts that the infinite-energy
electron beam came out unchanged (the Gaussian arm reported that number without
a gate and the PIC arm had no electron check until 2026-10-20; comprehensive
audit 2026-10-18, F-239). The spectral grid default is `(127,1023)` -- the
earlier `(128,1024)` at the odd sizes the solver's DST rule asks for, which
made every default run emit four "DST slow" warnings; the recommended
production grid is `(127,383)` with `domain_factor=8`, see
`?SpectralPoissonSolver`, while this script keeps `domain_factor=16` for its
model-error record; the grid-free direct reference defaults to `(48,48)`. Set
`OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1` to also check the CUDA spectral grid path
when CUDA is functional; the gate's CUDA arm runs that leg at a reduced size.

```bash
julia --project=. validation/high_energy_weakstrong_limit.jl
OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1 julia --project=. validation/high_energy_weakstrong_limit.jl
```

`symplecticity_validation.jl` computes finite-difference Jacobians for the
cases `SymplecticityContract` declares -- derived from the contract, not
copied (27 at the 2026-10-18 count: the linear maps, both strong beams, every
thick magnet, the thin kickers, the marker, both cavities) -- and reports
`norm(J' * S * J - S, Inf)`. A structural tripwire in the script and the
contract requires every registered kind declaring `Symplectic6DMap` to have a
case (0 uncovered of 22 at that count). (This entry said "12 cases", "7 of the
22 registered kinds" and "the thin kickers, marker and thin RF cavity by
neither" from the 2026-08-05_b audit's U24-3 until 2026-10-20, describing the
coverage before the repairs that audit prompted; comprehensive audit
2026-10-18, F-229.)

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
task diagnostics leaves both beams exactly unchanged through a REAL collision
-- the CPU PIC solver on the Gaussian contract's beams (2048 macroparticles,
3 slices, a 32x32 grid, two turns) -- and that the diagnostics observed it:
complete-turn timings populated, the slice-pair Green cache history non-empty,
the structured summary carrying the configuration. Until 2026-10-22 the solver
was a no-op (`collide!` returning 0.0), so nothing the diagnostics wrap did
any work and the equality could not fail on the defect it names (audit
F-243/U54-8). Receipt, fix batch 4: `coordinates equal across diagnostics on a real CPU PIC collision; turn timings = 2; slice-pair cache history (hits, misses, evictions) = (0, 18, 18)`; a mirror whose
diagnostics-enabled run perturbs the collision (a 64x64 grid) fails
`diagnostics changed beam-1 coordinates`, and a mirror on the old no-op solver
fails the new anti-vacuity guard (`the collision is a no-op and this check is
vacuous`). The per-phase PIC timing sink is a CUDA diagnostic and stays empty
on the CPU solver, which the script states rather than counts.

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
and `pic_extreme_summary.tsv` -- the provenance record carrying the git commit
(of this script's tree, whatever the working directory), GPU and driver, and
the resolved CUDA launch configuration. The second file was undocumented
(2026-08-05_b audit, U25-8). Since 2026-10-22 the summary's `precision`, `grid`
and `slices_per_beam` rows are read off the solver the run used instead of
being typed (`Float64`, `128x128`, `15` were string literals; audit
F-243/U54-5), and `OCTOPUS_USE_GPU=0` or an `OCTOPUS_SOLVER` other than `pic`
is refused by name before the harness runs: a CPU override used to run the
whole workload and then die at the summary's `CUDA.name(CUDA.device())`
(U54-3). Receipt, fix batch 4 at the gate's reduced size: 4000 macroparticles per beam, 20 turns on the RTX 4500 Ada, 130 s wall with the package load under `--check-bounds=yes`, the summary reading `precision Float64`, `grid 128x128`, `slices_per_beam 15` off the solver and the tree's own commit; the pre-fix script under `OCTOPUS_USE_GPU=0` at toy size (2000/1000 macroparticles, 20 turns) printed its steady-state mean and then died with `UndefVarError: CUDA`, as the audit described.

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
moment path with the same tracking and diagnostic workload; its summary records
`cuda_pic_launch_families = not applicable` where the PIC-family solvers record
one `cuda_pic_<family>_threads` pair per launch family (until 2026-10-20 the
Gaussian mode errored at that loop AFTER the measured run; comprehensive audit
2026-10-18, F-207). The summary's `turns` row is the effective run length and
`git_commit` is read from this tree. Production-size diagnostic benchmarks are
manual runs; the gate's CUDA arm runs this script at 4000 particles per beam
for 12 turns in mode `both`.

Outputs, under `result/`: `pic_diagnostics_<mode>_turn_times.tsv` and
`pic_diagnostics_<mode>_summary.tsv`. The tracking harness this script includes
also writes the run artifact `test/result/<seed>/pic_hcc.h5` in every mode
except `baseline` and `luminosity` -- `/luminosity/ip` in `luminosity_io`/
`both`, `/moments/electron` and `/moments/proton` in `moments`/`both` (outputs
unnamed here until the 2026-08-05_b audit, U25-8; seed-directory layout since
2026-08-11; one-artifact layout since 2026-08-18).

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

Since 2026-10-19 its two observers are artifact views constructed by name
(`MomentObserver(; name = ...)`); the script calls the reduction directly and
binds no artifact, so it still writes nothing. It had been dead on the
retired `MomentObserver(path)` constructor since 2026-08-18 (comprehensive
audit 2026-10-18, A-4) while the check it wraps kept passing: a CUDA-only
script is run by nothing but the GPU machine's gate, so a constructor
retirement must re-walk `validation/` and `profiling/` (the suite's
"No committed script constructs a retired observer or task spelling"
testset now scans them for the retired spellings, and since 2026-10-20 the
gate's CUDA arm runs this script, at 20000 particles, with every other
CUDA-requiring script -- the section at the top of this page).

`strong_strong_luminosity_schedule_output.jl` verifies that the run
artifact's per-collision luminosity channels omit unscheduled turns while
preserving all scheduled results, including an evaluated `NaN`, each channel
on its own turn axis:

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
remains -- which is what separates it from the slicing error. Four further
passes measure the transverse jump that grid construction introduces, one per
`grid_mode` value of `_jumps.tsv`: `per_slice_grid` (production's per-field-slice
grids), `source_slice_grid` (sized from the source slice instead),
`node_grid` (one grid per shared node, `_pic_node_grid!`) and
`node_source_evolution` (the physical residual the node grid leaves); the
script header explains each. (This entry described "a second pass" until
2026-10-20; comprehensive audit 2026-10-18, F-225.)

For a flat beam `Delta p_y` is the observable that matters: `E_y` varies on the
scale `sigma_y << sigma_x`, so its curvature in the drift variable is larger by
roughly the aspect ratio.

```bash
julia --threads=4 --project=. validation/slice_longitudinal_zscan.jl
OCTOPUS_ZSCAN_SOURCE_SLICES=4,6 julia --threads=4 --project=. validation/slice_longitudinal_zscan.jl
```

Overrides: `OCTOPUS_ZSCAN_NPART`, `OCTOPUS_ZSCAN_GRID`, `OCTOPUS_ZSCAN_NSLICES`
(at least 3, the number of adjacent field slices swept; a smaller value is
refused by name where it used to die with a raw `BoundsError`),
`OCTOPUS_ZSCAN_DEPOSIT`, and `OCTOPUS_ZSCAN_SOURCE_SLICES` (the source slices to
scan; the default derives the centre and one off-centre slice from the slice
count, `(4, 5)` for 7). The theory note's section 10 tables record source
slices 4 and 6, and slice 6 had no committed setting that reached it between
the 2026-08-05 U24-8 fix and 2026-10-20 (comprehensive audit 2026-10-18,
F-224): the second command above reproduces those rows. The same `nslices >= 3`
rule holds for `gaussian_pic_zscan.jl`'s `OCTOPUS_GPIC_ZSCAN_NSLICES`.

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
`emittance_growth_summary.tsv` (per-arm aggregate). The default tag is
`<scheme>_n<nslices>_<deposit>[_<gridmode>]_s<seed>`, the grid mode named
when it is not `slice_pair`: until 2026-10-20 both non-default grid modes
mapped to one literal `_srcgrid`, so arms F and G at one seed overwrote each
other silently and the aggregator could not notice (comprehensive audit
2026-10-18, F-224). The meta row carries `dropped_particles`, the charge the
interaction mesh dropped over the run (summed from the solver's own warnings;
the `:node` and `:source_slice` arms do not guarantee coverage), and the
aggregate reports its total per arm beside the rates (F-225).

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
longitudinal slice boundaries (docs/history/todo_ledger_archive.md, slice-interpolation item 5): the
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
(comma list from `gaussian,pic,gaussian_pic`). Each solver case writes one run
artifact, `result/coherent_modes_<kind>.h5`, overwritten on each run, holding
the two beams' barycenters as `/moments/beam1` and `/moments/beam2` (read
back with `MomentOutput(path; name = "beam1")`). Artifact form since
2026-10-19: the script had been dead on the retired `MomentObserver(path)`
writer since 2026-08-18 (comprehensive audit 2026-10-18, F-236), the same
class as `moment_observer_backend_consistency.jl` above.

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

All five coherent-mode scripts on this page (the simulation driver above,
the two theory companions, the EIC comparison and the BeamBeam3D anchor)
characterize: they write tables and print diagnostics without exiting
nonzero on a physics disagreement. The Vlasov script's numbered self-checks
print PASS/FAIL and warn which rows are then unusable, and the run FAILS at
its end -- after every table is written and flagged -- if any self-check
failed or any aspect row is not a mode (U22-11; `OCTOPUS_VLASOV_ALLOW_SELF_CHECK_FAILURE=1`
reduces that to a warning); the kernel-sign criterion stops it at once. (This
paragraph said "all four" of five and "its one hard stop" until 2026-10-20;
comprehensive audit 2026-10-18, F-239.) For unequal beams the asymmetric
normaliser uses each source's own other-plane sigma, as `xi_bb` does; until
2026-10-20 it used the rms mean of both beams' sigmas, which inflated the
electron's effective detuning on the EIC y plane by about 5 % and deflated the
proton's by about 5 % while the tunes shifts were built with the source's
sizes (F-237); the symmetric scans are unchanged.

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

`gaussian_pic_zscan.jl` completes docs/history/todo_ledger_archive.md item 4a: the frozen longitudinal
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
and `pic_option_<tag>.h5` (the task's run artifact in append mode, whose
`/luminosity/ip` series is read back per turn). The summary script writes
`result/pic_option_consistency_summary.tsv`, and refuses to compare an arm
whose particle count, turn count, grid, slice count or timing window differs
from its baseline -- it names the mismatch instead (U25-8, U25-11).
`OCTOPUS_OPT_BACKEND=gpu` without a functional device is refused by name
before any work (it used to die at the first device allocation). The gate's
CUDA arm runs the GPU backend under the tag `cuda_arm_gate` at 2000 particles
and removes its files, so a gate run never sits beside a study's arms.

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

The 61 cases cover drift, quadrupole (normal and skew), sextupole, octupole,
general multipole, sector bend and combined-function bend at both integrator
orders, RBEND, thin multipoles and solenoids; the curved-potential channels
(`cfbend_quad_heavy` at the polygon benchmark's working point, `cfbend_skew`
for the curved skew quadrupole, and `cfbend_k3`/`cfbend_k5` with orders above
K3 reaching PTC through EFCOMP field errors, whose `dkn`/`dks` are INTEGRATED
strengths -- the k3 attribute ceiling is MAD-X's element surface, not PTC's,
and a pure `b0 = 0` curved quadrupole has NO MAD-X 5.03.06 spelling because
SBEND's `k0` is measured ignored by its PTC translation); plus pole-face angles
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

`generate_madx_survey_reference.jl` drives MAD-X `SURVEY` to produce the
table that `MADXSurveyConsistencyContract` checks BOTH surveys against —
the arc walker (`s_positions`, placement lengths, `total_length`) and the
floor plan (`survey`: global `X, Y, Z` and `theta, phi, psi`,
`docs/theory/floor_plan_survey.md`) — element for element across nested,
reflected (`reverse` vs `-half`), heavily curved, vertical-bend
(`ref_tilt` ↔ MAD-X `tilt`), patch-rotation (`angle_s = +a` twins
`srotation, angle = -a`, the measured U16-5 roll inversion; `angle_y`
twins `yrotation` directly), and cavity-bearing fixture lines. Reference model: MAD-X's own `LINE` expansion
and its `S` column (end-of-element arc length); error metric: absolute
deviation, atol 1e-12; output: `validation/reference/survey_madx_<ver>.tsv`,
committed so the contract needs no MAD-X. Bend `L` is the ARC in both codes
for SBEND; MAD-X's RBEND (`RBARC=true` default) instead treats its stated
`L` as the chord and surveys the computed arc (measured: `L=2, angle=0.5`
surveys `2.0209862506105356`), while `RBendSpec` keeps `L` as the arc — a
deliberate one-length-rule feature, bridged by
`RBendSpec(chord=..., angle=...)`, which folds the chord to the arc at
construction. The `rbend_faces` fixture sidesteps the difference (SBEND +
half-angle faces); the `rbend_chord` fixture meets it head on (a true MAD-X
rbend vs the chord fold; deviation 0.0 at full TFS precision). Physics note:
`docs/theory/arc_survey_and_velocity_slip.md`.

```bash
julia --project=. validation/generate_madx_survey_reference.jl
```

`lattice_cells.jl` builds FODO, DBA and TBA cells from those magnets and checks
that they compose into working lattices: one-turn symplecticity from the
`one_turn_matrix` helper's complex-step Jacobian,
linear stability in both planes, Courant-Snyder invariant drift measured on
momentum, and CPU/CUDA tracking consistency. Quadrupole strengths are found by a
stability scan rather than hand-tuned, and the chosen working point is reported.

```bash
julia --project=. validation/lattice_cells.jl
OCTOPUS_REQUIRE_GPU_CONTRACT=1 julia --project=. validation/lattice_cells.jl
```

Overrides: `OCTOPUS_LATTICE_N`, `OCTOPUS_LATTICE_TURNS`, `OCTOPUS_LATTICE_LONG`,
and `OCTOPUS_REQUIRE_GPU_CONTRACT=1`, under which a skipped CPU/CUDA leg fails
the run instead of printing `cpu/cuda skipped` and closing with
"backend-consistent" (which it did until 2026-10-20; comprehensive audit
2026-10-18, F-229); the closing line now says which legs ran. The gate's CUDA
arm runs it with the leg required. Outputs `result/lattice_cells.tsv`.
Derivations for every map:
`../docs/theory/lattice_hamiltonian_and_conventions.md`.

## Twiss Benchmark Against MAD-X Twiss

**Script:** validation/twiss_madx_benchmark.jl (consumer) and
validation/generate_madx_twiss_reference.jl (generator).
**Shared fixture module:** validation/twiss_benchmark_cells.jl.
**Committed tables:** validation/reference/twiss_madx_5.03.06.tsv (92 lines: a
67-line header, one column row, 24 data rows, 56 columns) and
validation/reference/twiss_benchmark_maps.tsv (66 lines: a 20-line header, one
column row, 45 data rows, 42 columns).

**External tool:** MAD-X 5.03.06 (binary at /usr/local/bin/madx, overridable),
run only by the generator. The consumer reads the two committed tables and
never calls MAD-X, so the suite runs on a machine without it; the generator is
rerun only to re-freeze the tables (see Overrides), and in regenerate mode it
compares every cell of a fresh run against the committed file
(MADX-REGENERATE-DIFF differing_cells=0 on both arms, EXIT=0; the lines
are quoted in the history section named below).

**The shared fixture module.** validation/twiss_benchmark_cells.jl is the one
place the fixtures live: it builds each cell for Octopus (bare and task compile
modes), writes the MAD-X and PTC sequence text, and exports the Octopus one-turn
maps into twiss_benchmark_maps.tsv, which only the Xsuite benchmark reads (the
MAD-X and PTC scripts rebuild the maps from the module; the table documents them,
stage 9). Fixtures (from the maps table header, lines 1-20): S0 (a pure drift,
degenerate, the slip witness), U1 and U2 (uncoupled FODO cells, U2 with
dispersion), K1 (a skew-quadrupole coupled cell, K_TILT 0.05), K2 (a coupled
cell with dispersion), R_0 and R_pi4 (rolled FODO, the theory's section 13.10
family; R_pi4 has no periodic MAD-X solution), the Rd_ family (near-degenerate
cells Rd_1e-3, Rd_1e-6), D6_3 and D8_3 (definite degenerate fixtures at
tolerance class TOL-F), W1 and W2 (thin-kick witnesses), B4, B4K (6D cells with
a cavity) and G6_2.0MV, G6_0.2MV (6D cells at strength V/E_total
0.00066666666666666664 for the 2.0 MV cell; the header records that the twin
M65 sits 1.9e-9 relative below the PTC beam value). All Octopus maps are
symplectic to 6.6770871777275224e-15 at most (measured 2026-09-15 on the
fixture module's own check, history section).

**Flags used by the generator** (from the MAD-X table header, lines 1-12):
option, -echo -info -warn; beam pinned at beta0 0.9498330546994187 (the
campaign's beam pin; header vs pin residual over all rows
1.1102230246251565e-16, consumer run line 2, quoted in the history
section); rbarc=false; set, format="22.16e"; use, period=cell; twiss with
betx=1 bety=1 rmatrix for the non-periodic witnesses and twiss rmatrix for the
periodic cells; deltap=+-0.0001 for the finite-difference dispersion witness.
S0 and W2 have no periodic file and R_pi4 has no periodic solution; those rows
are witnesses, not gated.

**Measured conventions** (all from the MAD-X table header and the
generator run whose lines the history section quotes). MAD-X's sixth coordinate is (T, PT) in the time-like
sense with the canonical pair scaled by beta0, and its RE_56 does not carry the
Octopus slip term. The conversion law the consumer applies is
M_oct = Sh(-C/gamma0^2) . J0 . M_madx . J0^-1 with J0 = diag(1,1,1,1,beta0,
1/beta0) and no reflection (F = I). Numbers that pin it: the S0 witness RE56 is
1.0842277723823459 against the analytic drift formula, difference 0; the W2
sign witness is 5.5511151231257827e-17 in the chosen sense and
0.40000533333615529 in the other; the U2 finite-difference dispersion divided
by DX gives 0.94983305085229297 against the pinned beta0 0.94983305469941881,
difference 3.8471258401173714e-09 (the deltap step's truncation, so the FD
witness is recorded, not gated); the U2 partnership witness
converted_(5,6)_vs_octopus_bare_(5,6) reads -0.081412323090219285 against
-0.081412323096546585, difference 6.3272997952168453e-12 (consumer run line
25); and the K1 block entries r11..r22 are 0.86201121670608871,
-0.020416340718808941, -0.19140492597569572, 1.0534161426817839 (generator run),
matched by the consumer at TOL-A (consumer run lines 114-115).

**Metric and tolerance classes.** Each gated line prints
TW-MADX <fixture> <quantity> <octopus> <external> <|diff|> <tol> <class>
PASS|FAIL. TOL-A is 1e-12 relative on Twiss functions (1e-13 absolute on cos
mu and sin mu), e.g. TW-MADX K1 ET_bety 38.365210045104469 38.365210045102693
1.7763568394002505e-12 9.9999999999999998e-13 TOL-A PASS (consumer run line
108); TOL-B is 1e-12 relative on beta0*DX; TOL-E is the fitted convergence
order 4.0 +- 0.3 of the nst ladder (4, 8, 16, 32, 64) together with a frozen
nst=64 cap, e.g. TW-MADX-ORDER U1 4.0013414895306783 (line 161) with the model
residual at nst=64 2.0827214952667816e-10 (line 160), U2 3.9988016758485325,
K1 4.0004537849572168, K2 3.9987980534024454 (lines 169, 177, 185); TOL-F is
1e-10 absolute on the degenerate fixture, e.g. TW-MADX R_0
exported_cos_mu_vs_theory_13.10_constant 0.97440039720586424
0.97440039720586435 1.1102230246251565e-16 (line 187; the anchor is
computed in the script from the fixture's own L=0.2, k=+-1 and drift 1.0 by
rolled_exact_anchor, never a pinned digit, and the exact q row agrees to
8.3266726846886741e-17, line 188). The run ends with
TW-MADX-DIGEST <rows> <fails> <worst ratio>; the committed run prints
TW-MADX-DIGEST 387 0 0.40503179603364126 (line 365) on both arms and exits 0.
Counts after the review fix: 98 gated rows, 121 WITNESS lines, 110 RECORDED
lines (history section, benchmark A).

**Recorded, not gated** (consumer run): the Rd_1e-6 fixture (analyze returns
:failed; its E7 residual 1.785672875796623e-9 against the Rd_1e-3 value
3.009598136315693e-12) and the nst=32 U2 and K2 residuals
1.2613734057254078e-08 and 1.2555206652109518e-08 against the 1e-9 model
tolerance, which is why only nst=64 is capped.

**Injected defects** (stage 8 decision D16): OCTOPUS_STAGE8_DEFECT=drop_J omits the
beta0 scaling J0 and prints TW-MADX-DIGEST 35 4 10605609037863.729 with EXIT=1
(drop_J run, quoted in the history section; the partnership witness reads
-0.034559825812292666 against -0.081412323096546585); transpose_R transposes
the coupling block and prints TW-MADX K1 r12 -0.19140492597569261
-0.020416340718808941 0.17098858525688368 ... FAIL and TW-MADX-DIGEST 387 2
170988585256.88458 with EXIT=1 (transpose_R run, quoted in the history section).

**Run** (from the repository root; the consumer first, then the generator,
which needs MAD-X):

```bash
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/twiss_madx_benchmark.jl
env CUDA_VISIBLE_DEVICES="" OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. validation/twiss_madx_benchmark.jl
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/generate_madx_twiss_reference.jl
env CUDA_VISIBLE_DEVICES="" OCTOPUS_STAGE8_REGENERATE=1 julia --project=. validation/generate_madx_twiss_reference.jl
```

**Overrides:**

- OCTOPUS_STAGE8_DEFECT=none|drop_J|transpose_R (consumer; default none).
- OCTOPUS_STAGE8_REGENERATE=1 (generator; compare a fresh MAD-X run cell by
  cell against the committed table instead of writing it; prints
  MADX-REGENERATE-DIFF differing_cells=N).
- OCTOPUS_MADX (generator; the MAD-X binary, default /usr/local/bin/madx).
- OCTOPUS_STAGE8_WORKDIR (generator; scratch directory, default
  result/twiss_madx_reference_work).

**Outputs:** the consumer writes result/twiss_madx_benchmark.tsv (one row per
printed line) and prints the TW-MADX lines with the digest and EXIT code; the
generator writes validation/reference/twiss_madx_5.03.06.tsv (or, in
regenerate mode, only the diff line; validation/reference/twiss_benchmark_maps.tsv
is written by `write_benchmark_maps` of validation/twiss_benchmark_cells.jl) and its 183 MADX-GATE self-checks (table header line 22).

**Theory and design:** ../docs/theory/twiss_dispersion.md section 12.2 items 1,
2, 3 and 9 (the requirements this benchmark discharges against MAD-X) and
section 13.10 (the rolled FODO constant); ../docs/design/twiss_dispersion_analysis.md
(Staging item 8); ../docs/history/twiss_dispersion_analysis_history.md
(the 2026-09-15 stage 8 benchmark A section).

## Twiss Benchmark Against PTC ptc_twiss

**Script:** validation/twiss_ptc_benchmark.jl (consumer) and
validation/generate_ptc_twiss_reference.jl (generator); fixtures
from validation/twiss_benchmark_cells.jl and the maps table
validation/reference/twiss_benchmark_maps.tsv.
**Committed table:** validation/reference/ptc_twiss_madx_5.03.06.tsv (27
lines: a 16-line header, one column row, 10 data rows, 91 columns; header
line 16 "columns: 91").

**External tool:** MAD-X 5.03.06 with its PTC library (PTC-VERSION 5.03.06, the
generator's first printed line, quoted in the history section), run by the
generator only. The consumer reads the committed table, so the
suite does not need PTC; regenerate mode reruns PTC and compares
(TW-PTC-REGEN-DIGEST header_lines=16 cells=910 differing=0 PASS, quoted in
the history section).

**Flags** (table header line 4, stage 8 decision D4): ptc_create_layout with model=1,
method=6, nst=10, exact=true; ptc_twiss with time=false, icase=6, closed
orbit on. The method=2 orbit-artifact ladder recorded in header line 5
(fitted order 1.9858063694406614 against 2.0 +- 0.2) is the reason method=6
was chosen.

**Measured conventions.** With time=false PTC's sixth pair is (s-ell, delta)
in the reversed orientation of Octopus's (ell-s, delta): the reader applies
F = diag(1,1,1,1,-1,1), M_oct = F . M_ptc . F^-1, with no beta0 scaling
(J0 = I) and no slip shear (u = 0), because PTC time=false is the partner of
the Octopus BARE compile (header line 13). The table is committed as PTC
prints it (stage 8 decision D7); the reader flips. Numbers that pin the convention
(consumer run, quoted in the history section): the symplectic residual of the B4 map before F is
1.4176806664743553 and after F 4.6629367034256575e-15; the ALFA33 sign under
PTC's T convention on B4 reads 0.14225874842551697 against
0.14225874842495717, difference 5.5980220459161956e-13 (line 127); the
S0 witness RE56 is exactly 0 (S0_RE56_zero 0) and S0_RE12 at pt=1e-3 is
9.990009990009991 (generator witnesses, history section).

**The PTC internal proton mass (stage 8 decision D19) and the twin rule.** The W1 thin-cavity
witness M65_flipped_vs_formula_at_header_beta0 misses by 3.4670291637617368e-10
(0.185846588444706 against 0.18584658879140892, consumer run line 24; header
line 14 "misses by 3.467e-10 and is recorded, not gated; gated witnesses that
missed: none"). The measured cause is PTC's internal proton mass
0.938272081358 GeV (header line 10; TW-PTC-NOTE W1 D19 line), which shifts
the effective beam to PTC_BETA0 = 0.94983305558539111 and PTC_GAMMA0 =
3.1973667975476534 (header - ptc = -8.8597229552789258e-10 on beta0). The
twin rule (header line 11): the 6D gated comparisons build the Octopus twin
of each cavity cell at the PTC effective beam with g6_strength = V/E_total =
0.00066666666666666664, and the gated twin rows then agree to
1.1102230246251565e-16 on B4 M65 (0.18584658844470611 against
0.185846588444706, line 114), 4.3368086899420177e-19 on G6_2.0MV and
5.4210108624275222e-20 on G6_0.2MV (lines 182, 213). The header beta0 itself
matches the pin to 1.1102230246251565e-16 (S0_beta0_header_vs_pin
0.94983305469941881 0.9498330546994187, line 10). The BETA_jk index order is
j = plane, k = mode (header line 15, where the wrong order misses by
2.4808469094089958 on B4K and 4.7146912630910229 on K2).

**Fixtures:** builders from validation/twiss_benchmark_cells.jl; the ten
table rows U1, U2, K2, B4, B4K, G6_2.0MV, G6_0.2MV
plus the witnesses S0, S0_pt (pt = 1e-3) and W1 (thin cavity); the method=2
ladder is header line 5 of the table, not a row
(TW-PTC table table_rows_present 10 10 0 0 TOL-C PASS, line 8).

**Metric and tolerance classes.** Lines print TW-PTC <fixture> <quantity>
<octopus> <external> <|diff|> <tol> <class> PASS|FAIL. TOL-C is 1e-9
relative on the 6D Twiss functions (1e-10 absolute on cos mu, 1e-12 on the
symplectic residual), e.g. B4 BETA22 8.4062705380446641 8.4062705380116149
3.304911899704166e-11 and G6_0.2MV BETA33 117.96964928170352
117.96964928121247 4.9105608468380524e-10; TOL-E is the fitted order 4.0 +-
0.3 over nst (4, 8, 16, 32, 64) with a frozen nst=64 cap: TW-PTC-ORDER U1
3.9571693644344288, U2 3.9789324501096024, K2 3.9789636821507823, B4
3.9764988582412593, B4K 3.9766859084864121, G6_2.0MV and G6_0.2MV
3.9481404510869567 (lines 244-310, all PASS), and TW-PTC-NOTE ladder:
largest nst=64 residual 5.0524842989951857e-09 against the frozen
LADDER_CAP_64 8.4916074172269873e-09 (line 316). The committed run prints
TW-PTC-DIGEST 257 0 0.59499739575161859 (line 317, identical on the
haswell arm) and exits 0. The DISP1 rows are recorded, e.g. B4
0.73354515845480206 against 0.73354515845480184.

**Injected defects** (stage 8 decision D16): OCTOPUS_STAGE8_DEFECT=drop_F skips the
reflection and prints TW-PTC-DIGEST 180 30 2824760677698.0918 with exit 1
(drop_F run line 272, quoted in the history section; the first red line is
W1_M65_flipped_vs_strength_k_over_PTC_BETA0^2 -0.185846588444706
0.18584658844470603 0.37169317688941206 FAIL); cavity_57MV builds the twin at
the wrong voltage and prints TW-PTC-DIGEST 257 14 92923294.222352341 with
exit 1 (cavity_57MV run line 334, history section; W1 twin 0.17655425902247079
FAIL at line 21).

**Run** (from the repository root; consumer, then generator, which needs
MAD-X with PTC):

```bash
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/twiss_ptc_benchmark.jl
env CUDA_VISIBLE_DEVICES="" OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. validation/twiss_ptc_benchmark.jl
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/generate_ptc_twiss_reference.jl
env CUDA_VISIBLE_DEVICES="" OCTOPUS_STAGE8_REGENERATE=1 julia --project=. validation/generate_ptc_twiss_reference.jl
```

**Overrides:**

- OCTOPUS_STAGE8_DEFECT=none|drop_F|cavity_57MV (consumer; default none).
- OCTOPUS_STAGE8_PTC_TABLE (consumer; an alternative table path).
- OCTOPUS_STAGE8_REGENERATE=1 (generator; rerun PTC and diff against the
  committed table; prints TW-PTC-REGEN-DIGEST).
- OCTOPUS_MADX (generator; default /usr/local/bin/madx).
- OCTOPUS_STAGE8_WORKDIR (generator; scratch directory).

**Outputs:** the consumer writes result/twiss_ptc_benchmark.tsv and prints
the TW-PTC lines, the identity line (julia 1.12.4, host, OPENBLAS_CORETYPE
and cpu_target), the ladder note and the digest; the generator writes
validation/reference/ptc_twiss_madx_5.03.06.tsv with its 16-line header
(flags, beam, PTC-effective beam, twin rule, conversion, witness ledger) or the
regenerate digest.

**Theory and design:** ../docs/theory/twiss_dispersion.md section 12.2 items
5 and 7 (full 6D normalization against an independent 6D code) and section
4 (the (ell-s, delta) pair); ../docs/design/twiss_dispersion_analysis.md
(Staging item 8); ../docs/history/twiss_dispersion_analysis_history.md (the
2026-09-15 stage 8 benchmark B section, which records the W1 miss and D19).

## Twiss Benchmark Against Xsuite

**Script:** validation/twiss_xsuite_benchmark.jl (consumer) and
validation/generate_xsuite_twiss_reference.py (generator);
fixtures from validation/twiss_benchmark_cells.jl through the maps table
validation/reference/twiss_benchmark_maps.tsv.
**Committed table:** validation/reference/xsuite_twiss_xtrack_0.112.0.tsv
(2881 lines: a 23-line header, one column row, 2857 data rows in long form
layer/fixture/compile/quantity/value) with the sidecar
validation/reference/xsuite_twiss_provenance.txt (34 lines).

**External tool:** xtrack 0.112.0 with xobjects 0.6.10, xpart 0.23.18, numpy
2.4.6 on python 3.11.5 (table header tool line), run by the python generator
only, in a pinned virtual environment under the git-ignored result/ tree (the
sidecar records the interpreter path and the pinned commit
384952bcb2cd44b500b341b87436f3b1cf3bc817). The consumer is pure Julia and
reads the committed table and sidecar, so the suite needs no python; the
generator's regenerate mode diffs a fresh xtrack run against the committed
table (REGEN-DIGEST cells 2857 differing 0 header_lines_differing 0, rc=0,
quoted in the history section).

**Provenance gate.** The sidecar records the generator's sha256
0db216a66bf09efeb0325e59880b858cd2ab2b9ba793940275b05d047d26662f and the
input maps table's sha256
5417a9a604123973f0320b4f7d756923d4ab5d48a1beedcb4cfab91226f278f7; the
consumer recomputes the maps table's digest and gates TW-XSUITE-WITNESS
maps_table_sha256_matches_sidecar 1 1 0 PASS (consumer run line 6). The
sidecar is written only by the generator: any re-freeze of the maps table
(as the benchmark B rework and the final fix did) turns this line red until
the generator is rerun, which is what happened on 2026-09-15 and was
resolved by the re-freeze recorded in the history section.

**Flags** (table header): xtrack Line.twiss on the exported one-turn map
with finite-difference steps dx 1e-6, dpx 1e-7, dy 1e-6, dpy 1e-7, dzeta
1e-5, ddelta 1e-6; beam mass0 938.27208943e6 eV, p0c 2.8494991640982566e9
eV (the campaign pin: header_beta0_vs_pin 0.94983305469941881
0.9498330546994187 1.1102230246251565e-16 PASS, consumer run line 2); the
xtrack FutureWarning on the deprecated call is recorded in the header;
XSUITE_ALLOW_KERNEL_COMPILATION=1 is exported for the CPU kernels.

**Measured conventions.** Xsuite's sixth pair (zeta, delta) is Octopus's
(ell-s, delta) with no reflection and no beta0 scaling (J0 = I, F = I); the
only conversion is the slip shear Sh(-C/gamma0^2), which pairs xtrack with
the Octopus TASK compile. Numbers: S0_r56_vs_L_over_gamma0sq
0.97817168361909312 against 0.97817168200370863, difference
1.6153844928368244e-09 (line 7, TOL-D relative); W1_r65_vs_minus_octopus_m65
-0.18584658855011466 against -0.18584658879140895, difference
2.4129429010422143e-10 (line 20); the generator's rotation witness
rot_s_rad_vs_SRotation_sandwich_maxabs 8.2399365108898337e-18 and the U2 sign
witness R40/R41 -1 -1 (the GEN-WITNESS lines of the generator freeze, quoted
in the history section; 11 witnesses, 0 failing). The (X2) readout form is selected by the internal
(T15) lambda, form 2 on Rd_1e-3, D6_3 and D8_3, with |lambda_internal - g|
at worst 4.2743586448068527e-13, and physical_h_vs_det(U_ls) holds to
1.6819878823071122e-14 (history section, benchmark C).

**Fixtures:** builders from validation/twiss_benchmark_cells.jl, read
through the maps table; the C1 layer (normalizer and dispersion on U1, U2, K1, K2,
R_0, Rd_1e-3, D6_3, D8_3 at TOL-A for the dispersion rows, a recorded plan
deviation from TOL-D), the C2 layer (rows 5-6 of the normalized one-turn map
at TOL-D with the nst ladder) and the C3 layer (the T6 6D cell against the
Octopus longitudinal mode; gated, stage 8 decision D5 branch (a)): T6 witnesses r55
1 against 0.99999999999999978, r56 0.43212780506815801 against
0.43212780995540045 (4.8872424440737916e-09), r65 -0.18584658855011463
against -0.18584658879140895 (2.4129431785979705e-10), r66
0.91969052150635877 against 0.91969052059788692 (9.0847185330034108e-10),
all PASS (lines 1021-1025); the T6 longitudinal mode is certified at
0.14974352568848381 against 0.14974352201203292 (lines 389, 1028). Rd_1e-6
is recorded, not gated.

**Metric and tolerance classes.** TW-XSUITE <fixture> <quantity> <octopus>
<external> <|diff|> <tol> <class> PASS|FAIL; TOL-D is 1e-7 relative on the
xtrack rows 5-6; TOL-E is the fitted order 4.0 +- 0.3 with the frozen
nst=64 cap min(10 x 2.3920456726500561e-09, 1e-8) = 1e-8: TW-XSUITE-ORDER
U1 4.0013416877743504, U2 3.7026980631203243, K1 4.00046327507245, K2
3.7049247094295761 with nst=64 model residuals 2.0827201074880008e-10,
2.3920456726500561e-09, 3.4805491821998658e-12, 2.3805526438991365e-09
(lines 699-828). The worst gated ratio is the U2 fitted order,
TW-XSUITE-WORST C2 U2 model_fitted_order diff=0.29730193687967565
bound=0.29999999999999999 TOL-E (line 1063; 0.9 percent of margin, an owner
item). The committed run prints TW-XSUITE-DIGEST 1060 0 0.99100645626558559
and TW-XSUITE-NOTE digest gated=623 recorded=357 defect=none PASS (lines
1064-1065, identical on the haswell arm) with rc=0. Of the 623 gated rows,
20 (the C1 lines named zeta_dx_vs_xtrack_dx_zeta_4d(0_vs_0), one per
fixture and compile mode) assert a structural zero on both sides and can
never fail; the name declares it.

**Injected defect** (stage 8 decision D16): OCTOPUS_STAGE8_DEFECT=drop_shear omits
Sh(-C/gamma0^2); the C2 rows_cols_5_6_maxscaled_nst64 lines fail on all
eight fixtures (U1 0.2934515050746257, U2 0.51354012806127169, K1 and the
R_/Rd_ family 0.23476120405192902, K2 0.5135401282209735) and the run prints
TW-XSUITE-DIGEST 1060 8 5135401.2822097354 with rc=1
(drop_shear run: the eight FAIL rows at lines 702, 743, 784, 826, 868, 909,
950 and 1005, the digest at 1079-1082; quoted in the history section).

**Run** (from the repository root; consumer, then generator, which needs
the pinned xtrack environment):

```bash
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/twiss_xsuite_benchmark.jl
env CUDA_VISIBLE_DEVICES="" OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. validation/twiss_xsuite_benchmark.jl
env XSUITE_ALLOW_KERNEL_COMPILATION=1 <python-with-xtrack-0.112.0> validation/generate_xsuite_twiss_reference.py
env XSUITE_ALLOW_KERNEL_COMPILATION=1 OCTOPUS_STAGE8_REGENERATE=1 <python-with-xtrack-0.112.0> validation/generate_xsuite_twiss_reference.py
```

**Overrides:**

- OCTOPUS_STAGE8_DEFECT=none|drop_shear (consumer; default none).
- OCTOPUS_STAGE8_REGENERATE=1 (generator; diff a fresh run against the
  committed table; prints REGEN-DIGEST).
- OCTOPUS_STAGE8_PYTHON (documentation only: the interpreter recorded in the
  sidecar; the generator is run with whichever python carries xtrack
  0.112.0).

**Outputs:** the consumer writes result/twiss_xsuite_benchmark.tsv and
prints the TW-XSUITE lines, the WORST line, the digest and rc; the generator
writes validation/reference/xsuite_twiss_xtrack_0.112.0.tsv and
validation/reference/xsuite_twiss_provenance.txt (generator and maps table
sha256, interpreter, package versions, pinned commit) with its GEN-WITNESS
and GEN-DIGEST lines.

**Theory and design:** ../docs/theory/twiss_dispersion.md section 12.2 item 7
(the Ohmi and Xsuite conventions, (X2) after coordinate conversion) and
item 3; ../docs/design/twiss_dispersion_analysis.md (Staging item 8);
../docs/history/twiss_dispersion_analysis_history.md (the 2026-09-15 stage 8
benchmark C section).

### The suite contract on the committed tables

`TwissExternalReferenceContract` (src/contracts/twiss_external_reference.jl)
is the light suite twin of the three benchmarks above. Its `validate` reads
four committed tables from validation/reference/ -- the newest
twiss_madx_<v>.tsv, ptc_twiss_madx_<v>.tsv, xsuite_twiss_xtrack_<v>.tsv and
the Octopus maps twiss_benchmark_maps.tsv -- and re-runs every convention row
whose two sides both sit in a table: the external optics against `analyze` of
the converted external map (or of the Octopus map xtrack was handed), at the
tolerance classes of the scripts. No MAD-X, PTC or python runs and no fixture
is compiled; a missing table gives `:skipped` naming its generator. The twin
rows, the nst ladders (TOL-E), the rolled-family anchors and the recorded
rows stay in the three scripts of this README.

## Twiss and Dispersion Identities

`twiss_dispersion_identities.jl` checks the tagged Twiss and dispersion
identities of the theory note ((E3), (E7), (E8), (I1), (M2)-(M5), (D3), (D8),
(D14), (D17), (D24), (K1), (K4), (K5), (K7), (K8), (K12)-(K14), (O1)-(O5), (X2);
the contract's row table names every slug) through
`analyze` on the DBA cell (element tuple and `BeamLine`), the detuned FODO,
DBA + RF, DBA + RF + thin crab, manufactured dense 6x6 and 4x4 maps, the
manufactured coasting map and the declaring kinds' metadata examples: the
reported residual triples re-judged on their values, the kernel residuals the
analysis does not surface, and the identities recomputed in the caller's
coordinates, each against `c eps kappa` with kappa the conditioning of the
quantity compared. It also counts that every expected diagnostic of the
design's verification table that `analyze` can reach fires (a silent one
fails; the two kernel-level ones, the isotropic graph and the false graph,
are not reachable and are recorded as such) and that every element kind
declaring the analysis has an example and analyzes it or refuses it for the
documented closed-orbit reason.

```bash
julia --project=. validation/twiss_dispersion_identities.jl
```

Overrides: `OCTOPUS_TWISS_IDENTITY_SEED` (default 20260911),
`OCTOPUS_TWISS_IDENTITY_MAPS` (dense 6x6 maps, default 200),
`OCTOPUS_TWISS_IDENTITY_MAPS4` (dense 4x4 maps, default 20).
Outputs `result/twiss_dispersion_identities.tsv` (one row per identity: slug,
max ratio, max value, multiplier, the fixture that attained the maximum; then
two `normalizer_u6_*` rows) and prints one `TW-IDENT` line per identity, two
`TW-NORMALIZER` lines (the analysis's U_6 reconstruction and U_6
symplecticity residuals at multiplier 1 against the suite's pins; reported,
not gated), one `TW-TENTH` line (the machine count of identity rows above
one tenth, one quarter, one half and one of their frozen multiplier, the
rows above one tenth named; reported, not gated), `TW-DIAG`, `TW-KINDS`,
`TW-PINS` (the fixture-set coverage pins) and
a bitwise `TW-DIGEST` of the identity maxima so two CPU arms can be diffed.
The multipliers are frozen on the contract's default 20 + 5 maps (the
freezing set, kept by owner decision 2026-09-14 with the M3 table in hand);
the script's larger set can put a row above one tenth of its budget or, on a
map that exposes an analysis defect, over it (the gate then exits non-zero
naming the row). It DOES on the current tree: the documented default run
exits 1 on `c_scaling_invariance` (dense 6x6 map 98 at 1.11 of its frozen
multiplier, the native arm; the Haswell arm is recorded exit 0), the ledgered
state the owner kept with the freezing set (`docs/todo.md`, the
`c_scaling_invariance` row; comprehensive audit 2026-10-18, A-1 / F-229), so
a red default run on `main` is the recorded state, not a regression, until
that row closes. Derivations:
`../docs/theory/twiss_dispersion.md`; the design and its verification table:
`../docs/design/twiss_dispersion_analysis.md`. The script runs the contract
once and prints its metrics: the contract `TwissDispersionIdentityContract` is
the suite's copy; the record of the two CPU arms (the digests, the rows above
one tenth, and any failing row by name) is in
`../docs/history/twiss_dispersion_analysis_history.md`.

## Twiss and Dispersion Acceptance Windows

`twiss_dispersion_acceptance_windows.jl` is the measurement driver behind the
acceptance multipliers of the dispersion routes and the canonical separation:
the `c` of the `c eps kappa` and `c rho_M1 ...` floors in
`src/analysis/dispersion_routes.jl` (`c_graph`, `c_iso`, `c_coef`, `c_inv`,
`c_stop`, `c_coast`, `c_tie`) and `src/analysis/canonical_separation.jl`
(`c_sep`, `c_triple`, `c_ell`, `c_ohmi`), plus the informational
`c_inv_unconditioned` (`c_inv` with the route's amplification factor dropped
from its kappa). It writes a markdown table of four sections: (1) the oracle
agreement table, every route of `_dispersion_routes` on the 39 oracle maps of
the canonical-dispersion note against the note's own reference graphs, zeta,
eta and h at the design's `2e-10`; (2) every multiplier's window by the
one-tenth / ten rule, one sub-section per constant with the two extremes named
by the fixture that attains them, its `window [low, high]; source value
inside: <bool>` line (or `is EMPTY`) and a summary table; (3) the rejected
side of every `c eps kappa` check family of the dispersion-routes and
canonical-separation testsets (17 families: the route triples and agreement,
the coasting, covariance, scaling back-transformation, Ohmi and DBA rows among
them), the test's `c` beside each ratio; (4) the paper cross-checks (the crab
eta_+, the N15 / N17 controls, the DBA coasting eta). After the file is
written the driver prints one `window <constant>: [low, high] inside <bool>
(source <c>)` line per constant (`EMPTY` in place of `inside <bool>`) to
standard output, so a run's log carries the twelve windows; they are not in
the table.

The one-tenth / ten rule has two directions. For a residual-type constant
(`c_inv`, `c_inv_unconditioned`, `c_stop`, `c_coast`, `c_sep`, `c_triple`) the
guarded quantity must stay small: every accepted ratio at multiplier 1 must
stay below `c / 10` and every rejected ratio must exceed `10 c`, so the window
is `[10 * accepted extreme, rejected extreme / 10]`. For a floor-type constant
(`c_graph`, `c_iso`, `c_coef`, `c_tie`, `c_ell`, `c_ohmi`) the guarded
quantity must stay large: every accepted ratio must exceed `10 c` and every
rejected ratio must stay below `c / 10`, so the window is `[10 * rejected
extreme, accepted extreme / 10]`. A window is `EMPTY` when the fixtures on
both sides are closer than a factor 100 (the driver's own wording); an edge
with no fixture is open. Every landed multiplier is a power of two, measured
in both CPU arms (the native one and `OPENBLAS_CORETYPE=Haswell julia -C
haswell`) and sitting inside its window, except `c_inv`, whose window is EMPTY
on its rejected side: under the kappa re-derived 2026-09-14 (`_kappa_route`,
the history's kappa_route section) the accepted extreme is 5.34 | 5.28, a
converged fixed-point iterate bounded by `c_stop`, and the smallest rejected
ratio 3.60 is a stalled iterate rejected by the `converged` flag, not by the
floor; the floor alone rejects only the driver's two synthetic guard graphs,
the false and the zero graph, far above the edge, so no fixture sits near its
rejecting edge (carried), and 256 stays until the owner decides from the
measurement. The identity contract's freezing rule `c = max(8, 2^ceil(log2(10
max(ratio_native, ratio_haswell))))` does not apply to these constants. A
kappa changes only when its derivation is found wrong, never to fit a window.

The fixture builders are the suite's own `_st3_` / `_st4_` helpers, extracted
from `test/runtests.jl` by NAME at run time (the definitions from `const
_ST4_SEED` to the first `Dispersion routes:` testset, plus the named `_st3_`
helpers): renaming one of them breaks this script loudly, never silently.

```bash
julia --startup-file=no --project=. validation/twiss_dispersion_acceptance_windows.jl
```

Optional positional arguments: the oracle maps TSV, the reference TSV and the
output file; defaults, from the repository root,
`validation/reference/twiss_oracle_maps.tsv`,
`validation/reference/twiss_oracle_reference.tsv` and
`result/twiss_dispersion_acceptance_windows.md` (the table's header names the
two inputs relative to the repository root, so the header is the same on every
checkout). The maps TSV holds the 39 maps (24 dense, 7 prescribed-h, 3
coasting, 4 repeated-betatron and 1 defective spectator), replayed once from
the canonical-dispersion note's own `verify_dispersion.py` fixture loop with
its seed and draw order, every map passed through the note's `check_map`;
entries are exact binary64 reprs. The reference TSV holds their graph, zeta,
eta and h, dumped once by the same helpers.
`validation/reference/twiss_oracle_reference_provenance.txt` is that dump's
log kept verbatim: its first line is the dump's own summary (naming the file
by its pre-tracking name), then the seed, the python / numpy / scipy versions,
the helper's sha256 and its `check_map` counts, shared by both dumps; the
driver prints those last three lines in the table's header. The record of
every measurement (the stage 4a table of 2026-09-12 and the re-measurements
since) is in `../docs/history/twiss_dispersion_analysis_history.md`; the
derivations are in `../docs/theory/twiss_dispersion.md` and the design's
verification table in `../docs/design/twiss_dispersion_analysis.md`.

## Twiss and Dispersion Route Dump

`twiss_dispersion_route_dump.jl` is the raw material behind the (I1) route
acceptance floor of `src/analysis/dispersion_routes.jl` (`_kappa_route`,
re-derived 2026-09-14; the kappa_route section of the history): one TSV row
per FORMED dispersion route over the identity contract's 6x6 matrix fixtures
(the 200 dense maps; the tuple and BeamLine fixtures, the 4x4 maps and the
coasting map add no row) plus the identity contract's D12 weak-cavity map, each through
`analyze` with the default scaling, in whichever CPU arm the caller sets.
A row carries the route's status and `converged` flag, its normalized and
raw (I1) residuals, the three normalizer terms, the scaled matrix's and the
graph's norms, the reported `coefficient_condition`, the trace residual, the
canonical area, the tunes, the verdict, the residual recomputed here (it must
equal the reported one), `kappa_route` on the same matrix with the reported
condition, and the multiplier-1 ratio `normalized / (eps kappa_route)`: an
accepted row sits below `c_inv` = 256, a graph this floor rejected sits above
it, and a converged iterate the trace-residual branch check rejected can sit
below it. Run from the repository root:

```bash
julia --startup-file=no --project=. --threads=4 validation/twiss_dispersion_route_dump.jl OUT.tsv
```

It prints one line naming the output file, the row and fixture counts and the
arm's host. The stage 4a driver above measures the `c_inv` window itself; this
dump is what a reader recomputes it from offline, and its 2026-09-14 reading
(1005 rows per arm, statuses identical in both arms, no accepted row above
ratio 3.49, the weak cavity's five routes accepted) is in the kappa_route
section of `../docs/history/twiss_dispersion_analysis_history.md`.

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

Outputs, under `result/lum_anchor/`: the run artifacts `lum_headon.h5`,
`lum_crossing.h5`, `lum_crab.h5` (`/luminosity/ip` channels).
`data/crossing_lum_anchor.tsv` in the paper repository
(https://github.com/xud929/2026_octopus_cpc) is a hand-transcribed copy for
the paper.

`tune_estimator_calibration.jl` calibrates the coherent-mode tune estimator's
Hann-window plus parabolic peak interpolation on synthetic two-tone signals
mimicking sigma/pi dipole spectra, where the true tunes are known by
construction.

Error metric: median, p95 and maximum of `|Q_hat - Q_1|` over 500 trials.
Writes no files -- the calibration table is the printed output.

```bash
julia --startup-file=no --project=. validation/tune_estimator_calibration.jl
```

## Paper Reproduction Drivers (migrated from `paper/`, 2026-08-12)

Six paper-cited measurement scripts moved here when the reproduction package
became its own repository (https://github.com/xud929/2026_octopus_cpc, which
archives their frozen outputs and the manuscript). They live in `validation/`
because each is a reusable correctness measurement, not merely a figure
feeder; their run commands and reference models are in their headers. All
write TSVs under `result/`.

- `lambda_round_converged.jl` / `lambda_flat_converged.jl` — the Yokoya
  factors of Table 2 re-measured at converged settings (8192 turns, 1e5
  macroparticles/beam, three seeds), round (aspect 1.0) and flat (r = 0.09),
  against the m=1 Vlasov matrix of `coherent_mode_vlasov_theory.jl`. The
  round script sets the aspect and includes the flat one, so they move as a
  pair.
- `eic_emittance_benchmark.jl` — the EIC cross-code emittance benchmark
  against BeamBeam3D (Table 3): head-on, crossing angle AND both crab
  families zeroed, 15 slices, 128^2 mesh, damping shortened to 400 turns.
  The BeamBeam3D decks and outputs are archived in the paper repository
  under `data/bb3d_decks/`. Its `MESHSCAN` receipt compares the final
  emittances with the pre-run ones (both sides were the final state until
  2026-10-20, so the four percentages were 0.0 by construction;
  comprehensive audit 2026-10-18, F-237), and its header lists every variable
  it reads under a load-time check (it carried the strong-strong harness's
  header verbatim; F-239). The gate's CUDA arm runs it at 2 turns of 2000
  per beam.
- `emit_xcode.jl` — per-turn geometric emittance at the coherent-mode
  benchmark point, for overlay on BeamBeam3D `fort.24`.
- `noise_floor_meshswap.jl` — plain PIC at 64^2 against the hybrid at 128^2
  at the production 11:1 aspect; also regenerates Table 1
  (`flat_beam_noise_floor.tsv`) bit-for-bit with `picgrid`/`hybgrid` at the
  production assignment. Its round-beam correctness gate COMPARES since
  2026-10-20: the deterministic row against the review's Section 6.4 C
  columns for this mesh assignment, within half a unit in the reference's
  second significant figure, exit 1 naming the column otherwise (the "gate"
  was a println quoting the other assignment's columns; comprehensive audit
  2026-10-18, F-226).
- `kick_decomposition.jl` — the systematic/fluctuation decomposition of the
  flat-beam kick error (Sec. 4.1), with the Rademacher-bootstrap bias floor;
  realization and bootstrap counts from `OCTOPUS_KD_R` / `OCTOPUS_KD_NBOOT`,
  the seed from `OCTOPUS_KD_SEED`; the output is
  `result/kick_decomposition_R<R>[_seed<seed>].tsv` (the name carried a
  hard-coded `R100` whatever `R` was, and the file carried a 160-line dead
  copy of the mesh-swap script under that script's header until 2026-10-20;
  comprehensive audit 2026-10-18, F-226, F-227).

The CUDA device-time decomposition driver (`cuda_device_profile.jl`, Table 6)
moved to `profiling/` — it is a performance harness, not a validation.
