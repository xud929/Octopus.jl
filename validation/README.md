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

## Spectral Sine-Series Poisson Field

`spectral_poisson_field_validation.jl` validates the spectral sine-series 2D
Poisson solver (see `../docs/spectral_sine_poisson_solver.md`) against the exact
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
[`weak_strong_6d_model.md`](weak_strong_6d_model.md).

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
[`strong_strong_gaussian_optimization.md`](strong_strong_gaussian_optimization.md).
Dated soft-Gaussian optimization experiments, including rejected and reverted
attempts, are logged in
[`strong_strong_gaussian_optimization_history.md`](strong_strong_gaussian_optimization_history.md).

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
default is the production flat-beam setting `(128,1024)`; the grid-free direct
reference defaults to `(48,48)`. Set `OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1` to
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
`strong_strong_pic_extreme_benchmark_history.md`. Generated timing TSV files
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
`strong_strong_diagnostics_benchmark_history.md`.

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
