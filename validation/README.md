# Validation Scripts

Validation scripts are developer-facing numerical checks. They may use internal
helpers to test implementation details and should not be treated as public API
examples.

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

## Counter RNG

`counter_rng_validation.jl` checks the Philox-based stateless counter RNG used
for future stochastic tracking kernels. It reports basic uniform and normal
statistics, component correlation, neighboring-particle correlation, and
reproducibility checks.

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

`tracking_task_turn_update.jl` checks that `TrackingTask` applies
turn-dependent runtime updates in the no-hook fast path. It compares a
turn-signaled weak-strong line with and without a no-op observer.

```bash
julia --project=. validation/tracking_task_turn_update.jl
```

## Strong-Strong PIC Cache Backend Consistency

`strong_strong_pic_cache_backend_consistency.jl` runs
`StrongStrongPICBackendConsistencyContract`. It checks persistent slice-pair
cache reuse, identical CPU/CUDA cache histories, both final beam states, and
luminosity.

```bash
julia --threads=4 --project=. validation/strong_strong_pic_cache_backend_consistency.jl
```

## Strong-Strong Gaussian Backend Consistency

`strong_strong_gaussian_backend_consistency.jl` runs
`StrongStrongGaussianBackendConsistencyContract`. It compares both final beam
states and luminosity between the CPU and CUDA soft-Gaussian solvers.

```bash
julia --threads=4 --project=. validation/strong_strong_gaussian_backend_consistency.jl
```

## Strong-Strong Observer Plan Consistency

`strong_strong_observer_plan_consistency.jl` verifies that inserting a
read-only observer after a collision does not change either beam. It guards
the block-aware strong-strong plan cache.

```bash
julia --threads=4 --project=. validation/strong_strong_observer_plan_consistency.jl
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
