# TODO

## Task Diagnostics API

Move runtime diagnostic controls into explicit task configuration.

Current state:

- `StrongStrongTask(...; record_turn_times=true)` now records synchronized
  complete-turn timings, discoverable through `turn_timings(task)`. The
  strong-strong example maps `OCTOPUS_RECORD_TURN_TIMES` into this explicit
  task option.
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

## 2D PIC Extreme CUDA Performance Investigation

Goal: maximize strong-strong 2D PIC throughput on CUDA without weakening
physics validation or changing a particle's persistent identity from turn to
turn. Use the existing implementation as the reference and change only one
optimization variable in each experiment.

Relevant precedents:

- WarpX enables periodic particle sorting on GPUs to improve memory locality.
  Its CUDA default sorts every four steps, and its documentation recommends
  sorting by deposition cell when many particles occupy each cell. WarpX also
  keeps a separate global `idcpu` identifier created with the particle, so
  storage order and particle identity are distinct concepts:
  <https://warpx.readthedocs.io/en/26.04/usage/parameters.html> and
  <https://warpx.readthedocs.io/en/25.11/developers/particles.html>.
- AMReX exposes cell/bin particle sorting and recommends structure-of-arrays
  storage for accelerator execution:
  <https://amrex-codes.github.io/amrex/docs_html/Particle.html>.
- NVIDIA recommends coalesced global-memory access, profiling before
  optimization, and CUDA event timing for device work. cuFFT plans should be
  reused, batched transforms should use contiguous device-resident data, and
  power-of-two dimensions are favorable:
  <https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/> and
  <https://docs.nvidia.com/cuda/cufft/>.

### Rules and acceptance gates

- Preserve an immutable particle ID for the full run. Sorting or binning may
  change execution/storage order, but never identity. Diagnostics, stochastic
  counters, checkpoints, and comparisons must use the persistent ID rather
  than the current array position. Prefer an index/permutation view over
  physically reordering the canonical beam arrays for the first experiments.
- Change one optimization at a time from the current accepted implementation.
  Keep a change only when repeated measurements improve the primary timing
  observable without failing correctness gates; otherwise revert it before
  testing the next idea.
- Preserve `StrongStrongPICBackendConsistencyContract`. Run it after every
  candidate change and again after every accepted change. Also compare against
  the frozen CUDA reference using persistent-ID-aligned coordinates,
  luminosity, beam RMS moments, slice populations, and lost-particle counts.
- Record the GPU model, driver, CUDA/CUDA.jl versions, Julia version, precision,
  clocks/power mode when available, git commit, solver settings, and all
  environment/task options with every result.
- Do not combine per-subphase diagnostic synchronization overhead with the
  throughput result. Synchronize once at each complete-turn boundary and time
  the end-to-end turn through the task API. Run synchronized phase timers and
  Nsight Systems/Compute separately to explain the result.

### Step 1: freeze and measure the current fastest reference

Create a dedicated validation/benchmark driver derived from
`examples/strong_strong_tracking.jl`, with no moment-file output in the timed
region and the following fixed production-size case:

- CUDA, `Float64`, `PICPoissonSolver`, CIC deposition.
- 2,560,000 electron macroparticles and 1,000,000 proton macroparticles.
- `(128, 128)` transverse grid and `15 × 15` longitudinal slice pairs.
- Current fastest accepted configuration: wavefront scheduling, asynchronous
  field solves, wavefront batched FFTs, persistent slice-pair Green cache, and
  the current compact gather/scatter path. Record every toggle explicitly.
- Run 30 turns by default (20 is acceptable for constrained tests). Treat the
  first 20 as warm-up and use the arithmetic mean of the final 10 turn times as
  the primary observable. Also report median, minimum, standard deviation, and
  all individual final-ten values. Repeat the complete process at least three
  times and use the median of the three final-ten means for comparisons.

Record end-to-end time per turn and a non-overlapping phase breakdown that
sums to the same total:

- slicing and collision schedule;
- gather/bin/index preparation;
- bounds, grid, and Green-cache preparation;
- charge deposition;
- forward/inverse FFT and Green convolution;
- field derivative/interpolation;
- particle kick;
- luminosity;
- scatter/reorder;
- allocation/reclaim and unavoidable synchronization.

The current `OCTOPUS_CUDA_PIC_TIMING_DETAIL=1` path synchronizes subphases and
disables normal asynchronous overlap, so use it only as a diagnostic reference.
Use task-level complete-turn timing and NVTX instrumentation to measure normal
asynchronous execution without changing its internal production schedule. Save
a compact machine-readable summary under `result/`; do not save dense particle
data for every turn.

Before optimization, rerun the reference until variance is understood and
confirm that initialization, compilation, cuFFT planning, cache construction,
and output I/O are excluded from the final-ten steady-state observable.

### Step 2: profile the reference

Use Nsight Systems to locate synchronization gaps, launch overhead, transfers,
and lost overlap. Use Nsight Compute on the dominant deposition, preparation,
and kick kernels to record achieved memory bandwidth, global-load efficiency,
atomic throughput/contention, occupancy, register pressure, and shared-memory
use. Confirm with measurements whether deposition and FFT are still dominant
at the target particle counts before selecting the first optimization.

### Step 3: test spatial bin indices without reordering particles

Build cell or small-tile keys and compact bin offsets/particle-index lists on
the GPU. Use the lists for deposition and field interpolation while leaving
the canonical coordinate arrays and persistent IDs unchanged. Compare bin
sizes such as `1×1`, `2×2`, and `4×4` cells one at a time, including the cost
of key generation, histogram/prefix sum, and index construction in the timed
turn. Test rebuilding every turn first; only test reuse/update intervals after
particle cell-crossing statistics justify it.

Accept this direction only if total steady-state turn time improves, not merely
the deposition kernel. Verify that every ID appears exactly once and maps to
the same physical particle before and after every turn.

### Step 4: test tiled/shared-memory deposition

Starting from the best accepted bin-index implementation, test one deposition
kernel that accumulates a tile in shared memory and flushes reduced values to
global memory. Sweep one tile/block configuration at a time. Measure reduced
global atomic traffic against added binning, shared-memory, occupancy, and
flush costs. Preserve CIC weights and boundary behavior exactly.

### Step 5: test physical particle sorting only if needed

If index-only binning cannot provide adequate locality, test physical SoA
sorting as a separate experiment. Add an immutable `UInt64` particle-ID array
and permute it with every coordinate component. Diagnostics must either emit
the ID or restore ID order through an inverse permutation. RNG keys must use
the persistent ID, never the post-sort storage index. Measure sorting cost and
test sorting every 1, 2, 4, and 8 turns independently; keep sorting only when
its amortized total-turn benefit exceeds the cost and all identity checks pass.

### Step 6: optimize the remaining measured bottlenecks

After deposition/locality work, choose the next item strictly from the latest
profile and test only one at a time:

- fuse compatible bounds, preparation, interpolation, or kick kernels to
  reduce full-array traffic and launch overhead;
- improve coalescing and eliminate temporary gather/scatter arrays where the
  persistent-ID and two-direction collision semantics remain explicit;
- tune CUDA block size, register pressure, and launch geometry per dominant
  kernel;
- verify cuFFT plan/workspace reuse, contiguous batch layout, batch size, and
  stream assignment; retain the `(256, 256)` padded FFT shape implied by the
  `(128, 128)` physical grid unless a measured alternative is faster and
  physically equivalent;
- test CUDA Graph capture only if launch/synchronization overhead is material;
- test overlap of preparation, Green-cache work, luminosity, and field solves
  only when dependencies permit it.

Treat reduced or mixed precision as a separate physics study, not a routine
performance optimization. It requires explicit tolerances and agreement for
coordinates, luminosity, RMS moments, and long-run beam evolution.

### Step 7: consolidate each accepted improvement

For every accepted change, record before/after final-ten timing, phase timing,
speedup, memory use, profile counters, and validation residuals. Update the
frozen reference commit/configuration to the accepted version, then begin the
next single-change experiment from that state. Finish with a 30-turn target-size
run, the standard CPU/CUDA backend contract, persistent-ID invariance checks,
and a longer physics regression before making the optimized path the default.

### Accepted-results log

- Corrected reference commit `ccf7986`, NVIDIA RTX 4500 Ada, CUDA `Float64`, 30
  turns: compact final-ten means are `0.6468`, `0.6462`, and `0.6416`
  seconds/turn; median-of-means `0.6462` seconds/turn.
- Accepted corrected indexed wavefront candidate: `0.3637`, `0.3605`, and
  `0.3578` seconds/turn; median-of-means `0.3605`, a 44.2% reduction and 1.79x
  throughput. Compact and indexed 30-turn RMS values agree to printed
  precision. The 30-turn backend contract passed with maximum coordinate error
  `4.90e-16`, luminosity relative error `3.30e-15`, and identical cache history.
- Rejected indexed `slice_pair_green_growth=0.50` despite its timing improvement:
  the enlarged cached grids contain too many empty cells and do not meet the
  physical-model requirement. Fix subsequent rounds at
  `slice_pair_green_growth=0.25` and `slice_pair_green_min_ratio=0.50`.
- Rejected `slice_pair_green_growth=0.75`: `0.3572` seconds/turn, 3.1% slower
  than the diagnostic growth-0.50 median-of-means.
- Rejected midpoint `slice_pair_green_growth=0.625`: `0.3577` seconds/turn.
- Corrected async profile at the diagnostic growth-0.50 configuration:
  preparation `~0.125 s`,
  fields `~0.119 s`, kick `~0.081 s`, and deposition `~0.043 s`. Indexed
  execution eliminates compact gather/scatter; sorting is not the next target.
- All results from commit `1f8a513` are historical only: the no-observer path
  reused the wrong lattice block and PIC scatter lacked a stream-completion
  boundary. Repeat old candidate conclusions before using them.
