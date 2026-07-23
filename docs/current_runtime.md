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

## Crossing-Angle Coordinate Maps

`LorentzBoostSpec` and `RevLorentzBoostSpec` compile with
`NonSymplectic6DMap()`, not `Symplectic6DMap()`. Hirata's forward and reverse
crossing-angle transformations are an exact inverse pair, but in the tracked
accelerator coordinates their Jacobian determinants are respectively
`sec(angle)^3` and `cos(angle)^3`. They are therefore tagged
`:quasi_symplectic` and validated by their determinant and inverse relation,
rather than by the standalone canonical-symplectic criterion. See
`docs/beam_beam_longitudinal_kick.md` for the collision model and
`validation/symplecticity_validation.jl` for the executable check.

## Current Backends

The current backend tags are:

- `CPUThreadsBackend`
- `CUDABackend`

Current task execution infers a default execution policy from beam or
phase-space storage. A supplied policy selects execution for that storage; it
does not migrate arrays. Storage/backend and CUDA-device mismatches are rejected
before tracking mutates the beam.

Use `CPUThreadsExecutionPolicy(threads=:auto)` for CPU storage. An explicit
integer is an Octopus logical-worker limit within Julia's default thread pool
and must not exceed `Threads.nthreads(:default)`.

Use `CUDAExecutionPolicy(device=nothing,
launch=CUDALaunchConfig(threads=256, blocks=:auto))` for CUDA storage.
`device=nothing` resolves from particle storage. Fused tracking resolves
`:auto` blocks from compiled-kernel occupancy and particle coverage; an integer
block count remains available for reproducible tuning. PIC-family thread
overrides live separately in `CUDAPICLaunchConfig` on `PICPoissonSolver`.
`GPUExecutionPolicy` remains only as a deprecated CUDA compatibility adapter.

For example, keep fused tracking at 256 threads with automatic blocks while
testing only PIC deposition at 128 threads:

```julia
policy = CUDAExecutionPolicy(
    launch=CUDALaunchConfig(threads=256, blocks=:auto),
)
solver = PICPoissonSolver(
    backend_configurations=(
        CUDAPICLaunchConfig(deposition_threads=128),
    ),
)
```

Unset PIC-family fields inherit `policy.launch.threads`. PIC block counts stay
topology-derived, and cuFFT remains library-managed. A CUDA PIC configuration
on CPU storage is reported as inactive and a non-default request warns before
tracking begins.

The public direct-tracking form is:

```julia
track!(rep, runtime_line, turns; policy=policy, context=TrackingContext())
```

`TrackingContext` carries turn and counter-RNG state. It does not select an
execution backend or launch geometry. `TrackingTask` and `StrongStrongTask`
resolve one policy at execution entry and propagate it through fused,
isolated, two-stream, and collision execution.

Use `configuration_report` to inspect requested and resolved policy, solver,
task, schedule, observer, and diagnostic settings. Reports distinguish
inheritance and inactive settings from resolution. For validation,
`with_execution_audit` records receipts at the actual worker, kernel, schedule,
buffer, solver, and output consumers without enabling production-time
synchronization.

## Current Counter RNG

`counter_philox4x32`, `counter_uint64`, `counter_uniform01`,
`counter_normal_pair`, and `counter_normal` provide a stateless counter-based
RNG for stochastic beam initialization and tracking kernels such as
`LumpedRad`. The current implementation uses
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

Beam optics use three-plane tuples `beta=(beta_x,beta_y,beta_z)` and
`alpha=(alpha_x,alpha_y,alpha_z)`, consistently with `Linear6DSpec` and
`LumpedRadSpec`. Sigma-based and emittance-based initialization apply the same
Twiss correlation in all three planes. A two-component Beam `alpha` remains a
temporary compatibility input and implies `alpha_z=0`. `ChromaticityKickSpec`
accepts either two- or three-plane optics tuples but consumes only their first
two components: its transverse phase advances depend on `pz`, while its `z`
update completes the six-dimensional symplectic map.

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
Use `LongitudinalSlicing(method=:normal_quantile, nslices=N)` for
equal-probability normal-distribution quantile boundaries based on the current
longitudinal mean/rms; this replaces manually constructing Gaussian
`positions`. A solver `slicing=...` value applies to both beams, while
`slicing1=...` and `slicing2=...` allow different slicing configurations for
beam 1 and beam 2.

Runtime observation is explicit and task-scoped. Pass
`diagnostics=StrongStrongDiagnostics(...)` to `StrongStrongTask`; controls
cover complete-turn timing, CUDA memory logging, PIC phase timing, Green-cache
statistics, and NVTX ranges. Read structured results with `turn_timings`,
`pic_phase_timings`, or `diagnostic_summary`. Detailed PIC phase timing inserts
synchronization and is not a production throughput measurement. Environment
variables in the shell example are convenience adapters; library runtime code
does not read them.

`GaussianPoissonSolver` uses a sliced soft-Gaussian field approximation. For
each slice pair, the source slice is represented by its transverse Gaussian
moments at the slice center; each field particle uses a per-particle drifted
source moment at its own collision point. It does not use left/right
field-slice boundary interpolation. The longitudinal kick, virtual-drift
Hamiltonians, moving-centroid term, slingshot contribution, and coupled
`sigma_xy` derivative are derived in
`docs/beam_beam_longitudinal_kick.md`.
`GaussianPoissonSolver(batch_mode=:wavefront)` is the default CUDA scheduler.
It groups dependency-ready non-overlapping slice pairs, reduces all active
source moments in one wavefront, then launches independent slice kicks. Set
`batch_mode=:sequential` for the one-pair-at-a-time fallback. Set
`include_sigma_xy=true` when the full coupled transverse source covariance,
including the longitudinal derivative of the rotated principal axes, is part
of the model.

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
`PICPoissonSolver(batch_mode=:wavefront)` is the default slice-pair schedule
and groups ready, non-overlapping
slice-pairs with `collision_pair_batches`. In CUDA PIC, wavefront mode gathers
every active slice in a batch, solves all `4 * batch_size` source-boundary
field problems in one batched cuFFT stack, applies the non-overlapping kicks,
then scatters the batch back before moving to the next dependency frontier.
Use `PICPoissonSolver(batch_mode=:sequential)` for the one-pair-at-a-time
fallback.
`PICPoissonSolver(luminosity_schedule=EveryNSteps(step=N))` computes PIC
luminosity only on scheduled turns while still applying beam-beam kicks every
turn. Use `AtTurns(Int[])` to disable luminosity computation. Skipped
luminosity evaluations return `NaN` internally, but `StrongStrongTask` omits
those turns from its luminosity file. An evaluated result that is genuinely
`NaN` is still written. In `examples/strong_strong_tracking.jl`, use
`OCTOPUS_PIC_LUMINOSITY_EVERY=N`; `0` disables luminosity computation.
PIC luminosity deposits both slices at their common centroid plane and
evaluates `sum(Q1 .* Q2) / (hx * hy)`. Set
`luminosity_deposit_method=:CIC` or `:TSC` to select its deposition method;
the default `nothing` inherits the force `deposit_method`. A
`luminosity_grid=nothing` setting inherits the force-grid dimensions but uses
a separate luminosity workspace. The CUDA indexed wavefront path retains one
3D luminosity-grid pair per active wavefront and
uses block-local overlap sums followed by a final device reduction, avoiding
contention on one global scalar. Bounds and deposits remain pair-specific
because flattening slice index vectors and segmented device bounds were slower
in the production-size benchmark.
If a diagnostic run produces a zero-width field slice, the current
implementation uses equal left/right interpolation weights for that slice
and sets its longitudinal potential-gradient scale to zero instead of dividing
by zero.
For CPU threaded execution, PIC deposition uses per-thread local charge grids
followed by a deterministic reduction, avoiding concurrent writes to the same
grid cell. In `StrongStrongTask`, the CPU path retains its PIC workspace and
slice-pair Green cache in the task runtime cache across turns. Standalone
`collide!` calls use temporary per-call state. The CPU workspace reuses a
charge-grid, spectral work array, in-place FFTW plans, and left/right field
arrays across all directed slice interactions. It computes virtual-drifted
source bounds in the source scan and deposits drifted source coordinates
directly, avoiding separate source left/right coordinate arrays. It also reuses the
Green-function FFT between the left and right source-boundary solves within
one directed slice interaction. `PICPoissonSolver(green_cache=:slice_pair)`
enables a slice-pair cache keyed by slice-pair and direction. It stores two
Green FFTs per slice-pair, one for each beam-beam direction, and reuses each
Green for the left and right source-boundary charge solves when the current
source and field domains still fit inside the cached grids. The default is
`green_cache=:slice_pair`; use `green_cache=:none` for an uncached reference.
Set `StrongStrongDiagnostics(cache_stats=true)` to print cache hits, misses,
and hit rate for PIC runs.

CPU execution supports the implemented slicing methods. CUDA execution supports
the same public slicing methods for `GaussianPoissonSolver` and
`PICPoissonSolver`; equal-area uses GPU mask/count reductions with host-side
boundary interpolation, and equal-count currently uses host-side sorting to
construct boundaries before returning to GPU reductions and kick kernels.

CUDA `GaussianPoissonSolver` mirrors the no-interpolation soft-Gaussian path.
CUDA `PICPoissonSolver` uses atomic grid deposition, CUDA FFT convolution, GPU
Green-function construction, GPU finite-difference field construction, and GPU
interpolation/kick kernels. CUDA PIC computes drifted source/field bounding
boxes with fused CUDA reductions and computes drifted source coordinates
directly in the deposition kernel. Within one directed slice interaction, CUDA
PIC builds one Green FFT and reuses it for the left and right source-boundary
solves, matching the CPU implementation and the
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
`(2nx, 2ny, 4 * batch_size)` for the current dependency frontier. Use
`PICPoissonSolver(cuda_wavefront_fft=false)` to fall back from
wavefront-level batching to per-pair batched FFTs, or
`PICPoissonSolver(cuda_batch_fft=false)` to fall back to the previous
four-stream field-solve path. The default CUDA PIC indexed wavefront path skips
compact slice gather/scatter. It
computes drifted bounds from full beam arrays using slice index vectors,
deposits directly from those indexed particles into the wavefront charge stack,
keeps the same large batched charge FFT and Green FFT path, and applies kicks
back to the original beam arrays by particle index after the fields are solved.
The corrected 30-turn compact/indexed comparison agrees to printed precision.
Use `PICPoissonSolver(cuda_indexed_wavefront=false)` to keep the compact path
as a production comparison switch.
The CUDA PIC
workspace reuses its field streams, luminosity stream, synchronization event,
charge grids, batched charge/field arrays, wavefront charge/field-array cache,
and luminosity grids through the `StrongStrongTask` runtime cache across turns.
`green_cache=:slice_pair` is the only persistent PIC Green FFT cache mode. Its
reuse defaults are `slice_pair_green_min_ratio=0.50` and
`slice_pair_green_growth=0.25`, matching the July 2026 long-run timing tests
that kept rebuilds low. Define them directly in the solver, for example
`PICPoissonSolver(green_cache=:slice_pair, slice_pair_green_min_ratio=0.50,
slice_pair_green_growth=0.20)`. The strong-strong example also maps
`OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO` and
`OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH` into these constructor keywords for
command-line convenience. Use
`green_cache=:slice_pair` for the default persistent task cache. Solver option
scope, defaults, and dependencies are available
programmatically through `solver_option_schema(PICPoissonSolver)` and as a
readable summary through `solver_help(PICPoissonSolver)`. Use
`solver_configuration(solver)` or `solver_help(solver)` to inspect configured
values and resolved inherited luminosity settings. CUDA-only options are
explicitly marked with `supported_backends=(CUDABackend,)`.
CPU/CUDA
consistency is covered by `StrongStrongPICBackendConsistencyContract`; the
cache remains an accuracy/performance tradeoff relative to an uncached solve,
so compare luminosity, RMS, cache hit/build counts, and wall time against
`green_cache=:none` for new production studies. In CUDA wavefront mode with
`green_cache=:none`, PIC also
builds the wavefront Green functions as a two-plane-per-slice-pair stack and
runs a batched Green FFT. The charge FFT and inverse FFT are already batched
over the wavefront charge stack.
Standalone
`collide!(solver, beam1, beam2, CUDABackend)` calls still allocate a temporary
workspace for that call.
The luminosity grid deposition/reduction reads only the old compact slice
buffers. In CUDA wavefront mode, scheduled luminosity uses the validated
per-pair formula. Luminosity runs synchronously because measured Julia
task/stream overhead outweighed the available overlap on the tested path.
Compact slice operations use mask-free CUDA
kernels and reuse fixed-size PIC grid work buffers within a collision.
Stream/event ordering replaces the previous global synchronization before
launching independent field solves. Set
`PICPoissonSolver(cuda_async=false)` to use the sequential CUDA PIC path.
Set `OCTOPUS_PIC_BATCH_MODE=wavefront` in the strong-strong example to run the
CUDA PIC wavefront scheduler, or pass `batch_mode=:wavefront` directly to
`PICPoissonSolver`.
CUDA PIC performs adaptive CUDA memory-pool cleanup for temporary arrays. By
default, it checks memory pressure every 16 slice-pairs and reclaims only when
free GPU memory is below 12% of total memory.
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
For multi-GPU runs, place each beam on the intended device and use
`CUDAExecutionPolicy(device=N)`. The requested device must match every
coordinate array in the tracked representation.

## Current Limitations

- Contract execution is not yet automatic in `execute!`.
- Analyses are defined architecturally but not yet executed by tasks.
- `Phase6DRep` is the only implemented particle representation.
- Strong-strong CUDA equal-count slicing currently constructs boundaries with
  a host-side sort.
