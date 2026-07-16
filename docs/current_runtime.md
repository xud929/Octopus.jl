# Current Runtime Notes

This document describes the current implementation details. These details are
allowed to evolve and should not be treated as permanent architecture.

## Current Particle Representation

The current executable examples use `Phase6DRep`, a structure-of-arrays
representation for six-dimensional coordinates:

```text
(x, px, y, py, z, pz)
```

Other representations may be added later.

## Current Tracking Interface

The current `Symplectic6DMap` tracking primitive is:

```julia
track_particle(Symplectic6DMap, elem, x, px, y, py, z, pz)
```

It receives one particle as `(x, px, y, py, z, pz)` and returns the updated
six-tuple. Runtime elements are callable and delegate to this primitive today.
`src/track/` owns the current fusion helpers. Concrete element-specific
implementations live with their element definitions under `src/elements/`.
Future tracking methods may introduce different primitives.

## Current Element Sequence Representation

Element sequences are currently represented as tuples and passed through
`fusedTrack`. `fusedTrack` recursively expands nested tuples of callable
runtime elements.

`TrackingTask` normalizes compiled runtime output to a flat tuple before
execution, so future `compile_runtime` methods may return either one runtime
object or a tuple of runtime objects.

`TrackingContext` is currently an immutable, `isbits` execution context with
`turn::Int64`, `seed::UInt64`, and `rng_method::UInt8`. It snapshots the
Octopus global RNG state when constructed. Use `with_turn(ctx, turn)` to create
a copy with a different turn value; this keeps future scalar context fields
localized to one helper. The old coordinate-only fused tracking API is still
supported:

```julia
fusedTrack(elems, x, px, y, py, z, pz)
```

The context-aware overload is:

```julia
fusedTrack(ctx, elems, particle_id, x, px, y, py, z, pz)
```

Runtime tracking objects may overload:

```julia
elem(ctx, particle_id, x, px, y, py, z, pz)
```

Deterministic runtime objects fall back to their existing coordinate-only
callable method. `LumpedRad` uses this context-aware path for stochastic
excitation with `ctx.seed`, `ctx.turn`, its element `rng_id`, and
`particle_id`, allowing task-driven CPU and CUDA tracking to share one
counter-RNG interface.

Line-level observers/actions are compiled into the task runtime line. Active
plans are cached by scheduled hook activity, so inactive hooks do not break
fusion and large lines do not need to be fully replanned every turn. Cached
plans store references to runtime elements; turn updates mutate those runtime
objects in place.

This is an implementation strategy, not a permanent user-facing lattice model.

## Current Spec Representation

Public element constructors currently return `ElementSpec{kind}` values with a
`Dict{Symbol,Any}` parameter store. This keeps the spec layer flexible enough to
carry descriptive fields such as aperture, alignment, errors, and metadata.

Runtime element objects remain compact typed structs compiled from specs through
`compile_runtime`.

Element metadata is currently registered through declarative `ElementMeta`
records, normally via `@element_spec begin ... end`. The public query functions
such as `parameter_schema`, `example_spec`, `construction_help`, and
`element_help` read from that metadata registry.

## Current Backends

The current backend tags are:

- `CPUThreadsBackend`
- `CUDABackend`

Current task execution infers the backend from the beam or phase-space
representation storage. An explicit task policy is accepted as a consistency
assertion and must match that storage.

`GPUExecutionPolicy()` keeps the current CUDA device. Use
`GPUExecutionPolicy(device=N)` to call `CUDA.device!(N)` before GPU allocation
or task execution. The examples expose the same choice through
`OCTOPUS_CUDA_DEVICE=N` when `OCTOPUS_USE_GPU=1`.

## Current Counter RNG

`counter_philox4x32`, `counter_uint64`, `counter_uniform01`,
`counter_normal_pair`, and `counter_normal` provide a stateless counter-based
RNG for future stochastic tracking kernels. The current implementation uses
Philox4x32-10 plus Box-Muller normal generation. Values are keyed by:

```text
seed, turn, rng_id, particle_index, component
```

`rng_id` separates independent stochastic elements or streams. Internally,
`particle_index` and `turn` form the Philox counter, while `seed`, `rng_id`,
and `component` are mixed into the Philox key. The API is designed for CPU and
CUDA device code and avoids dependence on CPU thread count or CUDA block/thread
layout. `set_global_rng!(seed=..., method=...)` sets the Octopus global RNG
state, and `TrackingContext()` snapshots that state for stochastic runtime
elements.

Beam initialization uses the Octopus global counter RNG by default when `rng`
is omitted. The beam `rng_id` selects the consumer stream; `rng_id=0`
auto-assigns one with `next_rng_id!()`. Passing an explicit `rng` uses that
external RNG for convenience and ignores `rng_id` with a warning if nonzero. In
the current CUDA implementation, Octopus counter-RNG beam initialization
generates host values and transfers them to GPU storage.

SplitMix64-backed comparison functions are also exposed as `splitmix_uint64`,
`splitmix_uniform01`, `splitmix_normal_pair`, and `splitmix_normal`. They use
the same counter tuple and are intended for validation and benchmarking against
Philox, not as the preferred production stochastic-tracking backend.

CUDA/cuRAND also provides Philox generators. Octopus currently uses its own
small Philox mapping for task-driven stochastic tracking so the same
`seed, turn, rng_id, particle_index, component` tuple is available in CPU and
CUDA fused kernels. A future CUDA-native Philox path may be useful for faster
GPU-only beam generation or stochastic workflows, but it should come with an
explicit reproducibility contract before replacing the current default.

## Current Strong-Strong Solver

`StrongStrongTask` tracks two live beams through ordinary tracking lines that
contain matching `StrongStrongCollision` markers. Internally, each line is split
at those markers so ordinary elements before, between, and after collisions can
still use fused tracking plans.

On CUDA, matching non-collision line segments for beam 1 and beam 2 are launched
on separate CUDA streams and synchronized before the next
`StrongStrongCollision`. The collision remains the synchronization point:
pre-collision tracking for the two beams may overlap, then the solver runs only
after both beams reach the collision marker. CPU execution remains sequential.

The implemented solvers are `GaussianPoissonSolver` and `PICPoissonSolver`.
Both slice the beams longitudinally, order slice-pair collisions by collision
time, apply kicks to both live beams, and return a luminosity estimate.
Use `LongitudinalSlicing(method=:gaussian, nslices=N)` for Gaussian
equal-probability quantile boundaries; this replaces manually constructing
Gaussian `positions`. A solver `slicing=...` value applies to both beams, while
`slicing1=...` and `slicing2=...` allow different slicing configurations for
beam 1 and beam 2.

`GaussianPoissonSolver` uses a sliced soft-Gaussian field approximation. For
each slice pair, the source slice is represented by its transverse Gaussian
moments at the slice center; each field particle uses a per-particle drifted
source moment at its own collision point. It does not use left/right
field-slice boundary interpolation.

`PICPoissonSolver` deposits particles onto a transverse grid, solves the open
2D Poisson problem with zero-padded FFT convolution, interpolates the grid
field back to particles, and supports `:CIC` and `:TSC` deposition. For each
directed source-field slice interaction, PIC evaluates the source slice at the
field slice left and right longitudinal boundaries, then interpolates the kick
for each field particle according to its own longitudinal coordinate. Each beam
alternates as source and field for every slice pair.
By default PIC applies the transverse kick, the potential-difference
longitudinal kick, and the matching virtual-drift `pz` terms used by the
Hirata-map form of the PIC algorithm. Set
`PICPoissonSolver(longitudinal_kick=false)`, or
`OCTOPUS_PIC_LONGITUDINAL_KICK=0` in the strong-strong example, to use a
transverse-only map.
`PICPoissonSolver(batch_mode=:sequential)` is the default slice-pair schedule.
`PICPoissonSolver(batch_mode=:wavefront)` groups ready, non-overlapping
slice-pairs with `collision_pair_batches`. In CUDA PIC, wavefront mode gathers
every active slice in a batch, solves all `4 * batch_size` source-boundary
field problems in one batched cuFFT stack, applies the non-overlapping kicks,
then scatters the batch back before moving to the next dependency frontier.
If a diagnostic run produces a zero-width field slice, the current
implementation uses equal left/right interpolation weights for that slice
instead of dividing by zero.
For CPU threaded execution, PIC deposition uses per-thread local charge grids
followed by a deterministic reduction, avoiding concurrent writes to the same
grid cell. The CPU path reuses a charge-grid, spectral work array, in-place
FFTW plans, and left/right field-array workspace across all directed slice
interactions in one collision call. It computes virtual-drifted source bounds
in the source scan and deposits drifted source coordinates directly, avoiding
separate source left/right coordinate arrays. It also reuses the
Green-function FFT between the left and right source-boundary solves within
one directed slice interaction. `PICPoissonSolver(green_cache=:exact)` enables
a deterministic CPU cache for identical source/field Green FFT geometries.
`PICPoissonSolver(green_cache=:grid_template)` enables an experimental CPU
template cache that reuses shifted source/field grid templates when a
translated template covers the current source and field domains. The default is
`green_cache=:none`. Set `OCTOPUS_PIC_CACHE_STATS=1` to print cache hits,
misses, and hit rate for PIC runs.

CPU execution supports the implemented slicing methods. CUDA execution supports
the same public slicing methods for `GaussianPoissonSolver` and
`PICPoissonSolver`; equal-area uses GPU mask/count reductions with host-side
boundary interpolation, and equal-count currently uses host-side sorting to
construct boundaries before returning to GPU reductions and kick kernels.

CUDA `GaussianPoissonSolver` mirrors the no-interpolation soft-Gaussian path.
CUDA `PICPoissonSolver` uses atomic grid deposition, CUDA FFT convolution, GPU
Green-function construction, GPU finite-difference field construction, and GPU
interpolation/kick kernels. CUDA PIC currently computes drifted source/field
bounding boxes with broadcasted temporary arrays followed by CUDA reductions;
the generic fused `mapreduce` version was rejected because it introduced too
many small reductions in this hot path. Source deposition computes drifted
coordinates directly in the deposition kernel. `green_cache=:exact` caches
exact GPU Green FFTs.
On CUDA, `green_cache=:grid_template` currently falls back to the same exact GPU
cache; the approximate template matching remains CPU-only. The CUDA exact Green
cache is bounded by `OCTOPUS_CUDA_PIC_GREEN_CACHE_MAX_ENTRIES` and defaults to
256 entries; evicted entries are rebuilt exactly when needed. Within one
directed slice interaction, CUDA PIC builds one Green FFT and reuses it for the
left and right source-boundary solves, matching the CPU implementation and the
reference PIC algorithm. For each slice-pair, CUDA slicing builds per-slice GPU
index vectors. The CUDA PIC path
uses those indices to gather the two active slices into compact GPU coordinate
buffers for that slice-pair, then scatters the updated slices back immediately.
This keeps peak memory bounded by the active slice-pair instead of retaining all
slices for the whole collision. For the default longitudinal PIC map, compact
PIC buffers store `x`, `px`, `y`, `py`, `z`, and `pz` so the field-particle
longitudinal kick can be scattered back. If
`PICPoissonSolver(longitudinal_kick=false)` is used, the CUDA compact buffers
omit `pz`. In sequential PIC mode, each slice-pair solves the four independent
source-boundary field problems as one batched cuFFT over a `(2nx, 2ny, 4)`
charge stack. In wavefront PIC mode, the stack grows to
`(2nx, 2ny, 4 * batch_size)` for the current dependency frontier. Set
`OCTOPUS_CUDA_PIC_WAVEFRONT_FFT=0` to fall back from wavefront-level batching
to per-pair batched FFTs, or `OCTOPUS_CUDA_PIC_BATCH_FFT=0` to fall back to the
previous four-stream field-solve path for timing comparisons. The CUDA PIC
workspace reuses its field streams, luminosity stream, synchronization event,
charge grids, batched charge/field arrays, wavefront charge/field-array cache,
and luminosity grids through the `StrongStrongTask` runtime cache across turns.
Standalone
`collide!(solver, beam1, beam2, CUDABackend)` calls still allocate a temporary
workspace for that call.
The luminosity grid
deposition/reduction for that slice-pair is launched on a separate stream
because it reads only the old compact slice buffers. Compact slice operations
use mask-free CUDA kernels and reuse fixed-size PIC grid work buffers within a
collision. Stream/event ordering replaces the previous global synchronization
before launching independent field solves. Set
`OCTOPUS_CUDA_PIC_ASYNC=0` to use the sequential CUDA PIC path for debugging.
Set `OCTOPUS_PIC_BATCH_MODE=wavefront` in the strong-strong example to run the
CUDA PIC wavefront scheduler, or pass `batch_mode=:wavefront` directly to
`PICPoissonSolver`.
CUDA PIC performs adaptive CUDA memory-pool cleanup for temporary arrays. By
default, it checks memory pressure every 16 slice-pairs and reclaims only when
free GPU memory is below 12% of total memory. Use
`OCTOPUS_CUDA_PIC_RECLAIM_CHECK_EVERY` and
`OCTOPUS_CUDA_PIC_RECLAIM_FREE_FRACTION` to tune the adaptive path. Setting
`OCTOPUS_CUDA_PIC_RECLAIM_EVERY` enables fixed-interval cleanup in slice-pairs;
`OCTOPUS_CUDA_PIC_RECLAIM_EVERY=0` disables explicit cleanup.
This CUDA PIC path is still dominated by deposition and FFT costs for dense
beams; binned or tiled deposition may be needed later to reduce atomic
contention.

## Current GPU Validation Notes

CUDA validation requires a GPU that is visible to the Julia process. In some
execution environments, CUDA.jl may be installed while no device is visible.

Useful diagnostics:

```julia
import CUDA
CUDA.functional()
CUDA.has_cuda_gpu()
```

and, from the shell:

```bash
nvidia-smi
```

If `CUDA.functional()` is false or `nvidia-smi` cannot see a device, report the
environment limitation instead of treating it as an Octopus tracking failure.
For multi-GPU runs, select a device with `GPUExecutionPolicy(device=N)` or the
example environment variable `OCTOPUS_CUDA_DEVICE=N`.

## Current Limitations

- Contract execution is not yet automatic in `execute!`.
- Analyses are defined architecturally but not yet executed by tasks.
- `Phase6DRep` is the only implemented particle representation.
- Strong-strong CUDA equal-count slicing currently constructs boundaries with
  a host-side sort.
