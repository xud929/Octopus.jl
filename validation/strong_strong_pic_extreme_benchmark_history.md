# Strong-Strong PIC Extreme Benchmark History

This tracked log records reproducible decisions from
`strong_strong_pic_extreme_benchmark.jl`. Generated per-turn TSV files remain
under the gitignored `result/` directory; the final-ten samples needed to audit
each decision are preserved here.

## Correctness investigation: observer-dependent tracking

The original throughput runs below used the no-observer fast path and are not
valid performance references. The strong-strong plan cache was keyed only by
active-hook state, so the post-collision block could reuse the cached
pre-collision tracking plan when both blocks had no active hooks. Adding a
read-only moment observer changed the hook key and accidentally selected the
correct post-collision plan. CUDA PIC scatter kernels also returned before the
current stream completed writing slice coordinates back to both beams. Moment
collection synchronized the device and accidentally supplied that missing
collision-to-post-tracking dependency.

The corrected implementation keys plans by both block index and active-hook
state and completes PIC scatter at the collision boundary. The two independent
beam segments remain concurrent on separate CUDA streams. At the 2.56M/1M
target size, the corrected compact no-observer path matches the observer path
after 30 turns to printed precision:

- electron RMS: `(94.638, 238.960, 9.136, 182.090, 7001.506, 549.834) μm`;
- proton RMS: `(95.191, 118.929, 8.553, 117.836, 59999.998, 660.000) μm`.

This also resolves the previously reported approximately 8% compact/indexed
proton horizontal-size discrepancy. With both paths fixed at
`slice_pair_green_growth=0.25` and `slice_pair_green_min_ratio=0.50`, compact
and indexed execution both give `95.190997 μm` after 30 turns. The earlier
difference was caused by the wrong cached lattice block and incomplete PIC
scatter ordering; it was not an indexed-wavefront physics effect.

The corrected compact final-ten mean was `0.640772 s/turn`. Re-establish the
reference and repeat every optimization candidate after this correctness fix;
the earlier compact/indexed speed comparisons remain historical diagnostics,
not acceptance evidence.

## Corrected campaign at commit `ccf7986`

| Experiment | Final-ten mean (s) | Median (s) | Std. dev. (s) | Decision |
|---|---:|---:|---:|---|
| Compact run 1 | 0.646808 | 0.645930 | 0.013405 | Corrected reference |
| Compact run 2 | 0.646160 | 0.644931 | 0.012159 | Corrected reference |
| Compact run 3 | 0.641565 | 0.639978 | 0.009943 | Corrected reference |
| Indexed run 1 | 0.363715 | 0.357408 | 0.020322 | Accepted candidate |
| Indexed run 2 | 0.360489 | 0.356433 | 0.013188 | Accepted candidate |
| Indexed run 3 | 0.357806 | 0.352789 | 0.012514 | Accepted candidate |
| Indexed, Green growth 0.50 run 1 | 0.343047 | 0.342410 | 0.001693 | Rejected: physical grid occupancy |
| Indexed, Green growth 0.50 run 2 | 0.353744 | 0.353382 | 0.001940 | Rejected: physical grid occupancy |
| Indexed, Green growth 0.50 run 3 | 0.346404 | 0.345885 | 0.003296 | Rejected: physical grid occupancy |
| Indexed, Green growth 0.75 | 0.357228 | 0.357017 | 0.002114 | Rejected: slower than 0.50 |
| Indexed, Green growth 0.625 | 0.357695 | 0.356790 | 0.002663 | Rejected: slower than 0.50 |

The corrected compact median-of-means is `0.646160 s/turn`. Indexed wavefront
reduces this to `0.360489 s/turn`, a 44.2% reduction and 1.79x throughput.
Unlike the invalid earlier campaign, compact and indexed execution now produce
the same 30-turn RMS values to printed precision. The indexed 30-turn CPU/CUDA
contract passed with maximum coordinate error `4.90e-16`, luminosity relative
error `3.30e-15`, and identical cache histories.

Increasing `slice_pair_green_growth` from 0.25 to 0.50 on the indexed baseline
reduced the median-of-means to `0.346404 s/turn`, a further 3.9%, and passed the
numerical backend contract. It is nevertheless rejected: the enlarged cached
grids contain too many empty cells and violate the required physical grid
occupancy. Subsequent optimization rounds fix growth at 0.25 and minimum ratio
at 0.50.

Growth `0.75` was rejected after one run because its `0.357228 s/turn` mean
was 3.1% slower than the diagnostic growth-0.50 median-of-means.
The midpoint probe at growth `0.625` was likewise rejected at
`0.357695 s/turn`.

The corrected indexed asynchronous diagnostic profile at growth 0.50 reports preparation
at approximately `0.125 s`, fields at `0.119 s`, and kick at `0.081 s` per
turn. Indexed execution eliminates compact gather/scatter. Deposition is only
about `0.043 s`, so physical particle sorting is not the next justified
optimization. Field sub-timers overlap in async mode and are diagnostic rather
than additive. The detailed synchronized profiler disables async/indexed
execution and therefore describes the compact fallback, not this baseline.

Corrected final-ten samples, ordered from turn 20 through turn 29:

- Compact run 1: `0.640266723, 0.633268193, 0.629664634, 0.646410789, 0.645448770, 0.649555652, 0.640743974, 0.655508951, 0.677937162, 0.649273063`
- Compact run 2: `0.641229891, 0.642924667, 0.630125469, 0.646936338, 0.647175537, 0.649001622, 0.642110460, 0.637891998, 0.676865031, 0.647343463`
- Compact run 3: `0.638788632, 0.641127342, 0.627488158, 0.643933601, 0.634777967, 0.645386233, 0.638148894, 0.639099428, 0.666042149, 0.640856639`
- Indexed run 1: `0.353928510, 0.353031328, 0.360406864, 0.355092307, 0.357436242, 0.363211093, 0.359584582, 0.356199142, 0.420883978, 0.357379226`
- Indexed run 2: `0.350254776, 0.351407095, 0.357738723, 0.352167037, 0.353959763, 0.366927313, 0.362929297, 0.355127559, 0.394862073, 0.359516450`
- Indexed run 3: `0.353007197, 0.350309850, 0.361443709, 0.348771350, 0.352248798, 0.359694331, 0.357264003, 0.351311725, 0.391434909, 0.352570560`
- Indexed, Green growth 0.50 run 1: `0.342527042, 0.341814285, 0.341916783, 0.342293921, 0.342038429, 0.347480572, 0.343099068, 0.343841121, 0.343299734, 0.342160231`
- Indexed, Green growth 0.50 run 2: `0.353875549, 0.354006936, 0.352962988, 0.352061959, 0.351921729, 0.358901034, 0.353341927, 0.353383792, 0.353380616, 0.353607871`
- Indexed, Green growth 0.50 run 3: `0.347680298, 0.346488766, 0.345730390, 0.346040298, 0.344418047, 0.354673358, 0.341921528, 0.346610196, 0.345671840, 0.344809015`
- Indexed, Green growth 0.75: `0.358864831, 0.356528868, 0.355776701, 0.353523535, 0.357505111, 0.358558730, 0.356247517, 0.355443580, 0.360551524, 0.359275039`
- Indexed, Green growth 0.625: `0.355968677, 0.355454314, 0.356516802, 0.355914349, 0.355446293, 0.364180354, 0.358576587, 0.358828837, 0.357064014, 0.358996716`

## Benchmark protocol

- CUDA `Float64`, CIC deposition, `(128, 128)` physical grid.
- 2,560,000 electron and 1,000,000 proton macroparticles.
- 15 longitudinal slices per beam, wavefront scheduling, asynchronous field
  solves, batched wavefront FFT, and persistent slice-pair Green cache.
- 30 continuous turns. Turns 0-19 are warm-up; turns 20-29 form the measured
  sample. The primary result is the arithmetic mean of those final 10 turns.
- Run the complete process three times for accepted changes and compare the
  median of the three final-ten means.
- Moment and luminosity-file output are disabled during throughput runs.
- A candidate must improve complete-turn time and pass
  `StrongStrongPICBackendConsistencyContract`. Long-run beam RMS and luminosity
  sensitivity are additional physics gates before changing production defaults.

## Environment

Recorded 2026-07-18:

- Repository reference commit before this campaign: `1f8a513`.
- GPU: NVIDIA RTX 4500 Ada Generation, 24,570 MiB.
- NVIDIA driver: 580.119.02; power limit: 210 W.
- Julia: 1.12.4.
- CUDA driver API reported by CUDA.jl: 13.3.0.
- CUDA runtime reported by CUDA.jl: 13.0.0.
- Nsight Systems and Nsight Compute were not installed. Phase diagnosis used
  Octopus' synchronized CUDA PIC timers and was kept separate from throughput
  timing.

## Summary and decisions

| Experiment | Final-ten mean (s) | Median (s) | Std. dev. (s) | Decision |
|---|---:|---:|---:|---|
| Compact wavefront run 1 | 0.537874 | 0.534424 | 0.010097 | Reference |
| Compact wavefront run 2 | 0.550272 | 0.541896 | 0.026719 | Reference |
| Compact wavefront run 3 | 0.544909 | 0.534650 | 0.022267 | Reference |
| Indexed wavefront run 1 | 0.348564 | 0.344454 | 0.011329 | Accepted performance candidate |
| Indexed wavefront run 2 | 0.346097 | 0.341279 | 0.010198 | Accepted performance candidate |
| Indexed wavefront run 3 | 0.351976 | 0.350563 | 0.009471 | Accepted performance candidate |
| Compact, Green growth 0.50 | 0.546049 | 0.547171 | 0.010764 | Rejected: no improvement |
| Indexed, 128 threads | 0.348679 | 0.344937 | 0.011450 | Rejected: indistinguishable from 256 |
| Indexed, 512 threads | n/a | n/a | n/a | Rejected: launch exceeds register limit |
| Final indexed confirmation | 0.349591 | 0.345857 | 0.011790 | Confirmed candidate result |
| No beam-beam collision | 0.022069 | n/a | n/a | Optics/crab closure control passed |

The median compact reference is `0.544909 s/turn`. The median indexed result is
`0.348564 s/turn`, a 36.0% time reduction and 1.56x throughput improvement.

The indexed path remains opt-in. At target size, changing CUDA deposition order
produced visible 30-turn RMS sensitivity relative to compact execution,
including approximately 8% in proton horizontal RMS. This does not invalidate
the backend contract, but it requires longer statistical beam-evolution and
luminosity studies before the indexed reduction order becomes the production
default.

The target-size no-collision control retained the complete crab-cavity,
Lorentz-boost/reverse-boost, one-turn, chromaticity, and electron-radiation
lines while removing only `StrongStrongCollision`. After 30 turns, proton
horizontal RMS was `94.990 μm` versus the configured `95 μm`; electron
horizontal RMS was `106.053 μm` versus `106 μm`. The large horizontal growth in
the collision runs therefore does not originate from an unclosed crab/linear
transport sequence.

## Final-ten samples

All values are seconds, ordered from turn 20 through turn 29.

- Compact run 1: `0.533189456, 0.551143345, 0.529089607, 0.535401077, 0.558674242, 0.526062977, 0.533886633, 0.534960649, 0.542612688, 0.533714384`
- Compact run 2: `0.531648995, 0.553089224, 0.528735940, 0.536285145, 0.556777273, 0.526545792, 0.534797192, 0.547506808, 0.613571911, 0.573758032`
- Compact run 3: `0.598978518, 0.560782580, 0.525626147, 0.533627407, 0.556764739, 0.527550004, 0.534430899, 0.533422698, 0.543043083, 0.534868925`
- Indexed run 1: `0.344651798, 0.371299555, 0.332861279, 0.347563612, 0.361409166, 0.344255365, 0.342403469, 0.342346388, 0.356966010, 0.341887816`
- Indexed run 2: `0.338348236, 0.364037597, 0.338309512, 0.344049538, 0.360745121, 0.342001791, 0.338774134, 0.340555252, 0.356340504, 0.337810305`
- Indexed run 3: `0.346165560, 0.375022969, 0.344033439, 0.351889019, 0.354570038, 0.349237478, 0.343681547, 0.354176012, 0.357089521, 0.343894014`
- Green growth 0.50: `0.562772457, 0.542328104, 0.538290843, 0.555513610, 0.545363842, 0.550192575, 0.550415885, 0.548978149, 0.522593778, 0.544036015`
- Indexed 128 threads: `0.341625045, 0.370637359, 0.332868812, 0.348180844, 0.358466882, 0.345555478, 0.340133982, 0.344319152, 0.361744056, 0.343253857`
- Final indexed confirmation: `0.341320221, 0.375601272, 0.335273235, 0.347849917, 0.359220379, 0.344794748, 0.346920180, 0.341873818, 0.358879580, 0.344181083`

## Commands

Compact reference, repeated three times with distinct timing output paths:

```bash
OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=0 \
OCTOPUS_TURN_TIMING_PATH=result/pic_extreme_compact_run1.tsv \
julia --project=. validation/strong_strong_pic_extreme_benchmark.jl
```

Indexed candidate, repeated three times:

```bash
OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=1 \
OCTOPUS_TURN_TIMING_PATH=result/pic_extreme_indexed_run1.tsv \
julia --project=. validation/strong_strong_pic_extreme_benchmark.jl
```

Green-cache growth experiment, based on compact execution:

```bash
OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=0 \
OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH=0.50 \
OCTOPUS_TURN_TIMING_PATH=result/pic_extreme_green_growth_050_run1.tsv \
julia --project=. validation/strong_strong_pic_extreme_benchmark.jl
```

Indexed 30-turn backend consistency gate:

```bash
OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=1 \
OCTOPUS_CACHE_CONTRACT_TURNS=30 \
OCTOPUS_REQUIRE_GPU_CONTRACT=1 \
julia --threads=4 --project=. \
validation/strong_strong_pic_cache_backend_consistency.jl
```

No-collision optics/crab closure control:

```bash
OCTOPUS_USE_GPU=1 \
OCTOPUS_POISSON_SOLVER=PIC \
OCTOPUS_DISABLE_COLLISION=1 \
OCTOPUS_TURNS=30 \
OCTOPUS_N_MACRO_ELE=2560000 \
OCTOPUS_N_MACRO_PRO=1000000 \
OCTOPUS_DISABLE_LUMINOSITY_OUTPUT=1 \
OCTOPUS_DISABLE_MOMENTS=1 \
julia --project=. examples/strong_strong_tracking.jl
```

That contract passed with maximum coordinate error `5.68e-16`, luminosity
relative error `2.72e-14`, and identical CPU/CUDA cache history. A final repeat
also passed with maximum coordinate error `6.78e-16` and luminosity relative
error `2.12e-14`.

## Profile observations

The compact steady synchronized profile reported approximately `0.834 s/turn`
under diagnostic synchronization, led by FFT, Green work, preparation, and
scatter. This is not comparable to unsynchronized throughput timing.

The indexed asynchronous diagnostic profile reported approximately:

- preparation: 0.149 s;
- fields: 0.106 s;
- kick: 0.080 s;
- FFT sub-timer: 0.062 s;
- deposition sub-timer: 0.042 s.

Because deposition alone is not the leading cost after indexed execution,
physical particle sorting is not the next justified change. Re-profile before
revisiting bin sorting, shared-memory deposition, or physical SoA reordering.

## 2026-07-20 accepted-reference Nsight profile

The accepted indexed-wavefront reference at commit `480ec6b` was traced for
five target-size turns with luminosity and moment output disabled. The machine
used an NVIDIA RTX 4500 Ada Generation (24 GiB), driver `580.119.02`, CUDA
toolkit `13.0`, CUDA.jl `6.2.1`, Julia `1.12.4`, Nsight Systems `2026.3.1`, and
Nsight Compute `2026.2.1`. Turns 2--5 were used as the steady interval; turn 1
included Julia/CUDA compilation and cache setup.

The steady turns took `0.5615`, `0.4473`, `0.4337`, and `0.4753 s`. Summed
kernel durations were approximately `0.263 s/turn`; this sum is diagnostic and
does not account for concurrent execution. The leading steady GPU kernels were:

| Kernel family | Time/turn (ms) | Kernel time | Launches/turn |
|---|---:|---:|---:|
| indexed longitudinal kick | 74.98 | 28.49% | 225 |
| grid partial reduction | 71.74 | 27.26% | 1,876 |
| indexed drifted-plane deposition | 38.95 | 14.80% | 900 |
| line tracking | 26.74 | 10.16% | 4 |
| batched/vector FFT | 13.59 | 5.17% | 71.5 |
| regular FFT | 13.20 | 5.02% | 71.5 |

The indexed longitudinal kick is therefore the hottest individual kernel. It
used 150 registers/thread with 256-thread blocks. On this GPU (65,536 registers
and 1,536 threads per SM), register demand permits only one such block per SM,
or about 16.7% theoretical thread occupancy. This is a launch-resource estimate,
not Nsight Compute's measured achieved occupancy. The grid reductions are a
nearly equal aggregate target, but no single reduction launch dominates.

Across the full trace, including setup, CUDA API time was led by stream
synchronization (9,927 calls, 515 ms), followed by module loading (setup only),
device-to-host asynchronous copies (4,876 calls, 157 ms), and kernel-launch
calls (20,231 calls, 149 ms). The gap between complete-turn time and summed GPU
kernel duration makes launch/synchronization orchestration another measured
optimization target.

Nsight Compute attached to a representative target-size kick launch, but the
driver has `RmProfilingAdminOnly=1` and rejected hardware-counter collection
with `ERR_NVGPUCTRPERM`. Consequently this experiment did not measure achieved
occupancy, memory bandwidth, stall reasons, or atomic contention. Those metrics
must be collected after an administrator enables performance-counter access;
they must not be inferred from the Systems trace.

Enabling the existing `OCTOPUS_CUDA_NVTX=1` diagnostic exposed a stale API use:
CUDA.jl no longer provides `CUDA.NVTX`. The diagnostic now uses the direct
`NVTX.jl` dependency. This affects profiler annotation only, not tracking
physics or the default production path.

## 2026-07-20 indexed-kick experiments

Each proposal was applied independently to the accepted reference. Complete
turn timing used three 30-turn target-size runs and the final-ten mean unless a
clear regression justified stopping after the first run. The fresh unchanged
baseline means were `0.36360`, `0.35659`, and `0.36379 s/turn`; their median was
`0.36360 s/turn`.

| Proposal | Final-ten means (s/turn) | Accuracy | Decision |
|---|---|---|---|
| Two single-beam kernels per pair | `0.36473`, `0.36619`, `0.36342` | contract passed | Rejected: 0.3% slower median |
| One launch with beam-partitioned blocks | `0.35690`, `0.36341`, `0.36203` | contract passed | Rejected: 0.43% gain, within timing noise |
| Value-specialized CIC/TSC dispatch | n/a | compiler failed | Rejected: Julia/LLVM compilation segfault |
| Explicit CIC wrapper kernel | `0.40313` | contract passed | Rejected: 10.9% slower; further repeats stopped |
| Precomputed pair-invariant reciprocals | `0.36398`, `0.36223`, `0.36277` | contract passed | Rejected: 0.23% gain, within timing noise |
| Remove redundant kick grid-stride loop | `0.36118`, `0.35608`, `0.35779` | contract passed | **Accepted: 1.60% faster median** |
| Accepted loop removal plus 128 threads | `0.36421` | contract passed | Rejected: slower; further repeats stopped |

The accepted kernel is launched with `cld(max(length(idx1), length(idx2)),
256)` blocks, so each thread can visit at most one indexed particle in either
beam. Removing the unreachable second loop iteration preserves particle order,
field interpolation, kick arithmetic, and beam ordering. It changes neither
particle storage nor IDs.

The retained median final-ten mean is `0.35779 s/turn`, 1.60% below the fresh
baseline. The median of the per-run final-ten medians improves from `0.35847`
to `0.35327 s/turn` (1.45%). The three-turn backend contract reported maximum
coordinate error `1.03e-16`, luminosity relative error `2.85e-15`, and identical
CPU/CUDA cache histories.

The final 30-turn backend contract also passed with maximum coordinate error
`8.20e-16`, luminosity relative error `1.69e-14`, and identical cache history
`(476, 18, 46)`. The independent diagnostics consistency check passed.

A follow-up five-turn Nsight Systems trace measured 134 registers/thread, down
from 150, with the same 256-thread block size. The kick averaged `332.2 us` per
launch versus `333.8 us` in the preceding trace. It remains limited to one
resident block per SM, so the next optimization target moves to the nearly tied
grid-reduction aggregate until hardware counters can guide a deeper kick
rewrite.

## 2026-07-20 fused bounds reductions

The indexed preparation originally reduced source and field bounds separately
in each interaction direction: four logical reductions per slice pair. The
accepted implementation reduces each beam once and returns its source and field
bounds together as an eight-value tuple. The same componentwise `min`/`max`
definitions, indexed particles, drift equations, and grid/cache construction
are retained.

Against the retained kick-loop baseline median of `0.35779 s/turn`, three
target-size 30-turn runs reported final-ten means of `0.31573`, `0.31822`, and
`0.31542 s/turn`. Their median is `0.31573 s/turn`, an 11.75% time reduction and
1.13x throughput improvement. Electron and proton RMS values remained
consistent with the reference runs.

The follow-up Nsight Systems trace reduced `partial_mapreduce_grid` launches
from approximately 1,886 to 946 per turn and aggregate reduction time from
about `72.7` to `42.3 ms/turn`. The indexed longitudinal kick is again the
dominant measured kernel family at about `74.6 ms/turn`; further custom bounds
reduction work is therefore deferred.

The three-turn backend contract passed with maximum coordinate error
`8.83e-17`, luminosity relative error `5.42e-15`, and identical cache history.
The final 30-turn contract passed with maximum coordinate error `7.20e-16`,
luminosity relative error `1.55e-14`, and identical cache history
`(476, 18, 46)`. Diagnostics consistency also passed.
