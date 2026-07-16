# PIC Solver Improvement Plan

This plan tracks near-term improvements for `PICPoissonSolver`. It is a
developer roadmap, not public API documentation.

## Current Solver

`PICPoissonSolver` implements a 2D transverse open-boundary Poisson solve for
strong-strong slice interactions:

1. Drift source particles to the left and right longitudinal boundaries of the
   field slice.
2. Deposit the source slice on a transverse mesh with `:CIC` or `:TSC`.
3. Solve open-boundary Poisson by zero-padded FFT convolution.
4. Build finite-difference transverse fields.
5. Interpolate left/right fields to each field particle according to its
   longitudinal position.

The Gaussian validation in `validation/pic_gaussian_field_validation.jl`
compares this field against the Bassetti-Erskine kick.

## Priorities

### 1. Reuse Green-function FFTs

For one directed slice interaction, the left and right source-boundary solves
share the same source grid, field grid, spacing, and Green function. Compute
`fft(green)` once and reuse it for both source deposits.

Expected effect: reduce CPU FFT setup work and one Green matrix construction
per directed slice interaction without changing physics.

Status: implemented for the CPU path and CUDA path. The CUDA path builds the
Green function directly on the GPU and reuses the cached Green FFT.

### 2. Add CPU workspace buffers

Introduce internal reusable buffers for:

- charge grid
- potential grid
- Green function and Green FFT
- `phi`, `Ex`, `Ey`
- temporary source boundary coordinates

Expected effect: reduce allocation pressure during long multi-slice tracking.

Status: partially implemented. The CPU path now reuses the charge grid,
thread-local deposit grids, complex spectral work array, Green construction
buffer, Green FFT buffer, and left/right `phi/Ex/Ey` field arrays across all
directed slice interactions in one `collide!` call. It also reuses temporary
source-boundary coordinate arrays and luminosity deposition grids. In-place
FFTW plans are stored in the workspace and reused for the CPU convolution.

### 3. Cache Green FFTs Across Compatible Interactions

Cache Green FFTs by a geometry key:

```text
green_type, nx, ny, source_grid, field_grid, hx, hy, eltype
```

Use exact keys only at first. Approximate or rounded geometry keys should wait
until a validation contract defines acceptable error.

Status: implemented for exact geometry reuse through
`PICPoissonSolver(green_cache=:exact)`. CUDA uses an exact GPU Green FFT cache
and builds missed Green functions on the GPU. An experimental CPU template
cache is also available through `PICPoissonSolver(green_cache=:grid_template)`.
The template cache stores shifted source/field grid templates and reuses a
template only when a translated copy can cover the current source and field
domains with stencil margin. On CUDA, `:grid_template` currently falls back to
the exact GPU cache. The CUDA exact cache is bounded by
`OCTOPUS_CUDA_PIC_GREEN_CACHE_MAX_ENTRIES` and defaults to 256 entries; evicted
entries are rebuilt exactly. The default remains `:none`.

### 4. Overlap Independent CUDA PIC Field Solves

For one slice-pair collision, the four source-boundary field solves are
independent:

- beam 1 source at beam 2 left boundary
- beam 1 source at beam 2 right boundary
- beam 2 source at beam 1 left boundary
- beam 2 source at beam 1 right boundary

Launch those solves on separate CUDA streams, synchronize, then apply the two
field-particle kick kernels.

Status: implemented for CUDA PIC. Set `OCTOPUS_CUDA_PIC_ASYNC=0` to disable
this path for debugging or performance comparison.

### 4.1 Use Compact CUDA Slice Buffers

For each CUDA PIC slice-pair collision, gather the two active longitudinal
slices into compact GPU coordinate buffers, compute fields and kicks on those
buffers, then scatter the updated slices back immediately. This keeps peak
memory bounded by the active slice-pair instead of retaining all slices for the
whole collision. The compact PIC buffers store `x`, `px`, `y`, `py`, and `z`;
`pz` stays in the full beam because this interaction does not read or modify it.

Status: implemented for CUDA PIC. CUDA slicing now compacts each slice mask into
a GPU index vector during slicing, and the PIC collision reuses those index
vectors for compact gather/scatter. Slice centers, weights, and boundaries
remain small host-side metadata values.

CUDA PIC temporary arrays are reclaimed adaptively during long collisions. The
default checks memory pressure every 16 slice-pairs and reclaims only when free
GPU memory is below 12% of total memory. `OCTOPUS_CUDA_PIC_RECLAIM_EVERY`
enables fixed-interval cleanup for debugging or constrained-memory runs.

### 5. Improve GPU Deposition

Current CUDA PIC deposition is correctness-oriented and uses atomics. Candidate
improvements:

- sort or bin particles by cell, then segmented reduce
- per-block shared-memory tile accumulation followed by global reduction
- split dense slices into grid tiles to reduce atomic contention

Each approach must be checked against the Gaussian validation before replacing
the current path.

### 6. Add Green-function Variants

Evaluate additional 2D open-boundary Green functions:

- current cell-integrated Green function
- standard sampled Green function
- lattice Green function

Any new variant should be selected by `green_type` and covered by validation
sweeps over round and high-aspect-ratio beams.

## Validation Requirements

Every solver change should run:

```bash
julia --project=. validation/pic_gaussian_field_validation.jl
OCTOPUS_PIC_VALIDATION_RANDOM_CASES=100 \
OCTOPUS_PIC_VALIDATION_WRITE_CASE_DATA=false \
julia --project=. validation/pic_gaussian_field_validation.jl
OCTOPUS_POISSON_SOLVER=PIC julia --project=. examples/strong_strong_tracking.jl
OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_GREEN_CACHE=grid_template \
julia --project=. examples/strong_strong_tracking.jl
OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_GREEN_CACHE=exact \
julia --project=. examples/strong_strong_tracking.jl
OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_GREEN_CACHE=exact \
OCTOPUS_CUDA_PIC_ASYNC=0 julia --project=. examples/strong_strong_tracking.jl
```

Track at least:

- median normalized field error
- p95 normalized field error
- maximum normalized field error
- wall time for representative CPU and CUDA runs when CUDA is available
