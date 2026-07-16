# TODO

## Task Diagnostics API

Move runtime diagnostic controls into explicit task configuration.

Current state:

- Some diagnostics are controlled by environment variables read inside runtime
  code, for example `OCTOPUS_CUDA_MEMORY_LOG_EVERY`.
- This is convenient for shell and batch runs, but hidden from constructors,
  docstrings, notebooks, and API discovery.

Target design:

- Define diagnostics as task-level options, for example
  `StrongStrongTask(...; memory_log_every=100)`.
- Keep environment variables only in examples as command-line convenience
  adapters.
- Examples should parse environment variables and pass explicit task options.
- Runtime code should prefer task fields over direct `ENV` reads.

This keeps the public API discoverable while preserving convenient command-line
usage for long tracking runs.

## CUDA PIC Green Cache Follow-Up

Production default:

- Use `PICPoissonSolver(green_cache=:none)` for CUDA PIC production runs.
- In the `strong_strong_tracking.jl` example, keep
  `OCTOPUS_PIC_GREEN_CACHE=none` as the recommended setting.

Discovery from July 2026 CUDA benchmarks:

- `green_cache=:exact` had essentially no hits for evolving slice-pair
  geometries and was slower than no cache.
- Coverage-based `green_cache=:grid_template` was correct but did not reduce
  total Green-build cost. It created many templates, churned under bounded
  capacity, and increased lookup/preparation overhead.
- Binning width/height reduced the number of cache bins, but source-field
  relative geometry still produced many Green FFT builds. Green time remained
  comparable to `green_cache=:none`.
- Current conclusion: persistent Green FFT caching is experimental and should
  not be used for production until a future validation/performance study shows
  a clear wall-time improvement at acceptable physics error.

Future experiments:

- Revisit quantized source-field relative geometry only if Green construction
  again becomes dominant after prepare/gather/scatter improvements.
- Compare cache modes against `green_cache=:none` with the same initial beams,
  same turns, luminosity/RMS validation, cache hit/build counts, and wall time.
- Keep cache capacity bounded to avoid long-run GPU memory growth.
