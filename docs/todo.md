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

- A slice-pair CUDA Green cache is available as
  `PICPoissonSolver(green_cache=:slice_pair)` or
  `OCTOPUS_PIC_GREEN_CACHE=slice_pair` in the strong-strong example. It keys each
  cached Green FFT by `(slice_i, slice_j, direction)`, stores two Greens per
  slice-pair, rebuilds an enlarged grid when the current source/field domains
  no longer fit or become too small relative to the cached grid, and reuses
  cached FFTs across turns. Treat this as an experiment until long-run timings
  show a clear gain over `green_cache=:none` with wavefront Green FFT enabled.
- Revisit quantized source-field relative geometry only if Green construction
  again becomes dominant after prepare/gather/scatter improvements.
- Compare cache modes against `green_cache=:none` with the same initial beams,
  same turns, luminosity/RMS validation, cache hit/build counts, and wall time.
- Keep cache capacity bounded to avoid long-run GPU memory growth.

## CUDA PIC Two-State Indexed Path

Current CUDA PIC uses compact slice buffers. This preserves the collision
semantics clearly: both directions of a slice-pair read old coordinates, then
the updated compact slices are scattered back.

Future optimization:

- Keep full-size old/new coordinate states on GPU.
- For each wavefront, read active slice-pairs from the old state and write
  updated active slices into the new state by original particle index.
- Avoid per-slice compact gather/scatter where possible.
- Preserve the same two-direction collision semantics: a slice-pair must not
  use coordinates already modified by the opposite direction in the same
  pair.

This should only replace the compact path after a validation run confirms
luminosity, RMS moments, and backend consistency against the compact
implementation.
