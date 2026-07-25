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

## 2026-07-20 index-only spatial binning

An experimental path generated centroid-plane cell keys for each beam and
slice pair, sorted only the temporary CUDA index list, and reused that ordering
for the left- and right-plane CIC deposits. Canonical particle arrays and IDs
were never reordered. Key generation and GPU `sortperm` were included in
complete-turn timing.

One target-size 30-turn run was sufficient for each configuration because all
were decisive regressions relative to the accepted `0.31573 s/turn` reference:

| Bin size | Final-ten mean (s/turn) | Change |
|---|---:|---:|
| `1x1` cells | 0.65147 | 106.3% slower |
| `2x2` cells | 0.64291 | 103.6% slower |
| `4x4` cells | 0.64611 | 104.6% slower |

The `1x1` candidate passed the three-turn backend contract with maximum
coordinate error `1.03e-16`, luminosity relative error `3.12e-15`, and
identical cache history. All three runs reproduced the accepted electron and
proton RMS values. The failure is performance, not accuracy: comparison sorting
costs more than the entire unbinned turn and cannot be recovered by locality in
the existing atomic deposition kernel.

No spatial-binning code or solver option was retained. Revisit only as a
combined linear-time histogram/prefix index builder plus tiled/shared-memory
deposition experiment; continue to preserve canonical particle storage and
immutable IDs.

Post-revert verification confirmed no source or dependency diff from commit
`7fa9c42`. Three target-size final-ten means were `0.31600`, `0.31832`, and
`0.31752 s/turn`; the median `0.31752 s/turn` is within 0.57% of the accepted
`0.31573 s/turn` result. The repeated 30-turn contract passed with maximum
coordinate error `5.54e-16`, luminosity relative error `2.35e-14`, and identical
cache history `(476, 18, 46)`.

## 2026-07-20 launch and deposition experiments

Each candidate preserved canonical particle storage and immutable IDs. CUDA
Graph capture around the indexed kick passed the short backend contract, but
changing wavefront sizes required graph updates or re-instantiation. Three
target means (`0.31380`, `0.31562`, `0.31663 s/turn`) showed no gain over the
`0.31573 s/turn` reference, so the graph path was removed. Removing the explicit
indexed-kick stream synchronization also passed the contract but measured
`0.31639 s/turn`; it too was removed. An earlier synchronization experiment in
the inactive compact path was classified as a no-op control and not retained.

The accepted deposition change combines the left and right endpoint deposits
for one beam into one CUDA kernel. It reduces deposition launches from 900 to
450 per turn while retaining the same CIC/TSC weights and atomic additions on
separate charge planes. The three target-size final-ten means were `0.29801`,
`0.29816`, and `0.30495 s/turn`; their median is `0.29816 s/turn`, 5.57% below
the fused-bounds reference. The short backend contract passed with maximum
coordinate error `1.15e-16`, luminosity relative error `3.66e-15`, and identical
cache history. Electron and proton RMS values were unchanged.

A five-turn Nsight Systems trace (`/tmp/octopus-pic-fused-plane.nsys-rep` on
the benchmark host) measured paired deposition at `27.17 ms/turn` over 450
launches, down from `38.95 ms/turn` over 900 launches. The indexed kick remains
the leading kernel family at about `74.66 ms/turn`; bounds reductions account
for about `42.38 ms/turn`.

Fusing both beams and all four endpoint planes into one launch passed the short
contract but regressed to `0.30032 s/turn`, so it was reverted. Removing the
paired kernel's grid-stride loop also passed the contract (`9.18e-17` maximum
coordinate error, `5.15e-15` luminosity relative error), but three means of
`0.30571`, `0.30484`, and `0.30231 s/turn` were slower and the loop was restored.
A 128-thread launch specialization did not complete reliably and produced no
valid timing, so it was not retained.

The new deposition profile does not justify a histogram/prefix/scatter and
tiled shared-memory implementation: that design requires several full index
passes and launches to replace a stage now taking about 9% of total turn time.
Physical SoA sorting is consequently also rejected at this stage; it was
conditional on the linear-time binned design being insufficient and would add
sorting cost while making canonical ordering harder to audit. Reconsider both
only if a future profile again identifies deposition as a leading cost.

The independent `strong_strong_diagnostics_consistency.jl` check passed. An
initial final-contract attempt hung in indexed luminosity deposition. Review
found that the later grid-stride-loop experiment had removed
`index += stride` from the legacy single-plane luminosity kernel and its broad
revert had inserted that increment in the indexed kick kernel. The target
benchmark disables luminosity and preceded this faulty experimental revert, so
its accepted paired-plane timing was unaffected. Both control-flow changes were
restored exactly to the preceding implementation, leaving only the intended
paired-plane deposition diff.

After that correction, the 30-turn backend contract passed with maximum
coordinate error `8.14e-16`, luminosity relative error `1.85e-14`, and identical
CPU/CUDA cache history `(476, 18, 46)`. The contract used the required Green
cache settings (`slice_pair_green_min_ratio=0.50`,
`slice_pair_green_growth=0.25`).

## 2026-07-20 luminosity-inclusive timing

The accepted target case was repeated with luminosity evaluated every turn
(`pic_luminosity_every=1`) while luminosity file output and moments remained
disabled. Thus the measurement includes luminosity calculation but excludes
disk-I/O cost. Three 30-turn runs gave final-ten means of `0.39798`, `0.39873`,
and `0.39621 s/turn`; the median is `0.39798 s/turn`. Relative to the
luminosity-disabled `0.29816 s/turn` median, evaluating luminosity every turn
adds about `0.09982 s/turn` or 33.5% to complete-turn time.

For an I/O-inclusive comparison, the same case was run for 200 turns and
turns 100--199 were averaged. Luminosity was evaluated and written every turn;
electron and proton moments were reduced every turn and written through the
default capacity-100 HDF5 buffers. The solver-only and luminosity-compute
controls used one run each. Three complete-diagnostics runs were used, with
their median reported below.

| Configuration | Last-100 mean (s/turn) | Last-100 median (s/turn) | Change from solver-only |
|---|---:|---:|---:|
| Solver only | 0.30318 | 0.30305 | reference |
| Luminosity calculation only | 0.38607 | 0.38575 | +27.3% |
| Luminosity file + both moment files | 0.38737 | 0.38727 | +27.8% |

The three full-diagnostics last-100 means were `0.38737`, `0.38394`, and
`0.40217 s/turn`. This spread is much larger than the difference between the
single luminosity-only control and the median full-diagnostics run, so the
incremental cost of luminosity text I/O, two GPU moment reductions, and the two
buffered HDF5 outputs is unresolved within timing noise in this comparison.
The final files contained 200 luminosity records and both capacity-100 moment
buffers were exercised. Repeat the solver-only and luminosity-only controls
three times before assigning a percentage to the incremental diagnostic cost.

## 2026-07-20 longitudinal-kick cost control

The target-size, luminosity-disabled benchmark was repeated with only
`longitudinal_kick=false`. Three 30-turn final-ten means were `0.28439`,
`0.28555`, and `0.28488 s/turn`; their median is `0.28488 s/turn`. Relative to
the physics-enabled `0.29816 s/turn` reference, disabling the longitudinal
part saves `0.01328 s/turn` (4.45%). This is a timing control with different
physics, not an optimization candidate. It also confirms that the previously
profiled `74.7 ms/turn` kick-kernel family includes the transverse kick and
field interpolation rather than representing longitudinal work alone.

## 2026-07-20 TSC backend contract

`StrongStrongPICBackendConsistencyContract` now accepts `deposit_method`, and
the reusable validation script maps
`OCTOPUS_CACHE_CONTRACT_DEPOSIT_METHOD=CIC|TSC` to that option. The 30-turn TSC
contract passed with maximum coordinate error `3.91e-16`, luminosity relative
error `4.15e-15`, and identical CPU/CUDA cache history `(475, 18, 47)`. This
closes the validation-coverage gap for the paired-plane TSC deposition branch;
the default contract remains CIC.

## 2026-07-20 centroid-plane luminosity optimization

PIC luminosity now has an independent
`luminosity_deposit_method::Union{Nothing,Symbol}` option. `nothing` inherits
the force `deposit_method`; explicit `:CIC` or `:TSC` changes luminosity only.
The option is present in structured solver metadata, the strong-strong example
and notebook, validation contracts, and benchmark summaries. The force solve,
Poisson Green function, centroid-plane definition, and canonical particle IDs
were not changed.

The original indexed CUDA luminosity path performed two bounds reductions and
two deposits for every active pair, then sent every `(cell,pair)` product to a
single global `Float64` atomic. Changes were tested one at a time:

| Trial | 30-turn final-ten result (s/turn) | Decision |
|---|---:|---|
| Previous luminosity reference | `0.39798` median of three means | reference |
| Flattened indices + global atomic device bounds | `0.70461` mean | rejected |
| Flattened indices + block-local device bounds + product array | `0.39056` mean | rejected |
| Flattened indices + block-local bounds + hierarchical overlap | `0.38891` mean, `0.38664` median | rejected |
| Pairwise bounds/deposition + hierarchical overlap | `0.36217`, `0.36307`, `0.38090` means | accepted |

The accepted run medians were `0.36050`, `0.36026`, and `0.37638 s/turn`;
their median is `0.36050 s/turn`, 9.42% below the previous `0.39798 s/turn`
luminosity reference. Relative to the `0.29816 s/turn` solver-only reference,
the measured luminosity increment falls from about `0.09982` to `0.06234
s/turn`, a 37.5% reduction. The losing batched paths were removed: copying
slice index vectors and constructing segmented bounds cost more than the saved
launches. The reusable wavefront `Q1/Q2` grids remain, but bounds and deposits
stay pair-specific.

The retained overlap kernel produces one block-local partial sum for each
grid tile and slice pair; CUDA's final device reduction transfers only the
completed luminosity scalar. A five-turn Nsight Systems 2026.3.1 trace at
`/tmp/octopus-pic-lum-hierarchical.nsys-rep` measured this partial-sum kernel
at only `0.254 ms/turn`. Luminosity deposition remained about `29.72 ms/turn`,
and its two bounds-reduction kernel families totaled about `31.18 ms/turn`.
The indexed longitudinal kick remained the largest kernel family at about
`74.71 ms/turn`. These values are kernel-duration sums and do not include host
launch/synchronization cost or account for concurrency.

The analytic Gaussian luminosity validation covers five centered/offset,
equal/unequal, round/flat cases; CIC/TSC; 32--256 grids; three edge paddings;
and 20k, 100k, and 400k deterministic Halton-Gaussian macroparticles. At 400k
particles and a 256×256 grid, the worst case relative errors were `3.84e-4`
for CIC and `5.77e-4` for TSC. The production interface and independently
assembled validation quadrature agreed within `9.32e-15`. These are
convergence tests of the deposited-grid quadrature, not claims that a finite
particle basis has the exact continuous Gaussian overlap.

All four 30-turn force/luminosity combinations passed the CPU/CUDA backend
contract: inherited CIC, inherited TSC, CIC force with explicit TSC
luminosity, and TSC force with explicit CIC luminosity. Every turn's
luminosity and all 270 nonempty slice-pair contributions were compared. The
worst total-luminosity relative error was `4.51e-14`, the worst slice-pair
relative error was `3.45e-13`, the worst final coordinate error was `6.38e-16`,
and CPU/CUDA cache histories were identical (`(476, 18, 46)` for CIC force and
`(475, 18, 47)` for TSC).

Three final 200-turn all-output runs evaluated and wrote luminosity every turn
and reduced/wrote both moment streams with capacity 100. All three outputs
contained 200 records and no luminosity was `NaN`. For turns 100--199, the run
means were `0.39013`, `0.37029`, and `0.39211 s/turn`; their median was
`0.39013 s/turn`. The corresponding run medians were `0.38921`, `0.36891`, and
`0.39142 s/turn`, with median `0.38921 s/turn`.

The previous full-output run means were `0.38737`, `0.38394`, and `0.40217
s/turn`, with median `0.38737 s/turn`. The new median-of-means is 0.71% slower,
while the new mean-of-means is 0.82% faster than that previous median. Both
differences are much smaller than the observed run-to-run spread. Therefore,
these unmatched full-run aggregates do not resolve the luminosity optimization;
the follow-up controlled comparison below supersedes that conclusion.

### Controlled 200-turn follow-up

A follow-up used the same 200-turn driver and turns 100--199 for every measured
window. Two optimized luminosity-compute-only runs measured `0.36320` and
`0.36230 s/turn`. A detached worktree at the pre-optimization commit `dead820`
then measured `0.39555 s/turn` with the original global-atomic reduction and
otherwise identical inputs. The accepted hierarchical reduction therefore
saved `0.03325 s/turn`, or 8.4% of complete-turn time, in a direct A/B. Final
beam RMS coordinates agreed to roundoff.

The optimized luminosity-file-only follow-up measured `0.36658 s/turn`, only
`0.00428 s/turn` above the adjacent compute-only run. An earlier file-only run
measured `0.38326 s/turn`, but its timing changed abruptly within the run; this
and the `0.37029`--`0.39211 s/turn` spread of the three earlier all-output runs
show an uncontrolled slow timing regime whose variation is much larger than
the actual text-output cost. The luminosity file remains open and buffered for
the complete task; it is not reopened per turn.

A final optimized run with luminosity output and both capacity-100 moment files
measured `0.36965 s/turn`. It wrote all 200 luminosities and both 200-record
moment streams. Thus the luminosity computation gain is real and remains
visible with all outputs enabled. The earlier apparent masking resulted from
comparing unmatched noisy runs, not from moment diagnostics or loss of the
kernel improvement. The machine-level cause of the historical slow regime was
not captured and remains unresolved.

Follow-up telemetry did not support the initial GPU-clock or NUMA hypotheses.
An instrumented slow run measured `0.39244 s/turn`, while active SM clocks
remained at 2670--2685 MHz, temperature at 43--56 degrees C, power near 104 W
against a 210 W limit, and no thermal or power throttle reason was active.
However, polling `nvidia-smi` every 200 ms itself perturbed the run, so that
sample cannot identify the historical cause. Clean full-output runs pinned to
the GPU-local NUMA node 0 and remote node 1 measured `0.36899` and `0.37007
s/turn`, respectively, ruling out remote NUMA placement as the source of the
approximately `0.392 s/turn` regime. No competing CUDA process or process I/O
wait was observed during the investigation.

Future optimization comparisons should use paired old/new runs with fixed CPU
affinity and should record low-overhead machine telemetry. High-frequency
`nvidia-smi` sampling must not be used inside the timed experiment.

The target-size TSC timing used the otherwise unchanged fastest configuration:
CUDA `Float64`, `(128,128)` grid, `15x15` slice pairs, indexed wavefront,
slice-pair Green cache, growth `0.25`, minimum ratio `0.50`, and luminosity and
moments disabled. Three final-ten means were `0.33362`, `0.33209`, and
`0.33135 s/turn`; their median is `0.33209 s/turn`. The matching CIC median is
`0.29816 s/turn`, so TSC costs `0.03393 s/turn` or 11.4% more. CIC remains the
fastest and default configuration; selecting TSC is an accuracy/shape-function
choice rather than a performance optimization.

A separate production-size 30-turn physics comparison enabled luminosity every
turn and both capacity-100 moment observers from identical initial beams. CIC
and TSC are not expected to be bitwise equivalent because they use different
particle shape functions. Their luminosity series differed by at most `2.24e-4`
relative (0.0224%); the final-turn difference was `3.23e-6` relative. The
largest final RMS difference was `1.73e-4` relative (0.0173%) for the electron
horizontal-momentum size and `4.36e-5` (0.00436%) across proton RMS components.
Across all first- and second-order moment columns, the largest column-normalized
differences were 0.62% for electrons and 0.50% for protons, both in small cross
correlations rather than beam sizes. Thus the methods give similar aggregate
observables for this 30-turn case, but they are distinct numerical models and
should not be required to agree at backend-consistency tolerances.

## 2026-07-21 policy-interface performance gate

The execution-policy refactor made CPU logical-worker limits, CUDA fused launch
geometry, and seven CUDA PIC thread families reach their actual consumers. It
did not change the PIC physics defaults: CIC, the 128 x 128 force/luminosity
grid, 15 x 15 slice pairs, indexed wavefront, asynchronous batched/wavefront
FFT, slice-pair Green cache, minimum ratio 0.50, growth 0.25, and longitudinal
kick all remained fixed. Runs used Julia's four-thread default pool and were
pinned to NUMA node 0.

Fresh pre-refactor 200-turn controls at commit `e5e92fc`, using turns 100--199,
were `0.30524 s/turn` solver-only, `0.38455 s/turn` with luminosity calculation,
and `0.38140 s/turn` with luminosity file plus both capacity-100 moment files.
The full-output control was a single noisy run and is reported as context, not
as a paired estimate.

Three post-refactor 30-turn solver-only runs compared automatic fused blocks
with the reproducible legacy 256-block setting. The final-ten mean medians were
`0.30918 s/turn` for `blocks=:auto` and `0.31345 s/turn` for `blocks=256`.
Automatic occupancy/particle-coverage resolution is therefore retained as the
new default; it was 1.36% faster in this A/B. The explicit setting remains
available through `CUDALaunchConfig`.

PIC thread families were then changed one at a time from inherited 256 threads
to 128. These screening trials did not justify a default change:

| Only 128-thread family | Final-ten mean (s/turn) | Decision |
| --- | ---: | --- |
| gather/scatter | 0.30806 | retained interface, no default change |
| deposition | 0.31042 | retained interface, no default change |
| kick/interpolation | 0.30679 | retained interface, no default change |
| field derivative | 0.31096 | retained interface, no default change |
| spectral multiply | 0.31311 | retained interface, no default change |
| Green construction | 0.30944 | retained interface, no default change |

The apparent gather/scatter and kick gains are smaller than the unchanged-run
spread, so all PIC families continue to inherit 256 threads. For luminosity,
three 200-turn runs at 128 threads had a median last-100 mean of `0.38695
s/turn`, versus `0.38789 s/turn` at inherited 256 threads. The 0.24% difference
is likewise unresolved and the default was not changed.

The final 200-turn production matrix was:

| Configuration | Three last-100 means (s/turn) | Median (s/turn) |
| --- | --- | ---: |
| solver only | 0.30722, 0.30782, 0.30772 | 0.30772 |
| luminosity calculation only | 0.39296, 0.36592, 0.38789 | 0.38789 |
| luminosity file + both moment files | 0.39778, 0.36503, 0.36700 | 0.36700 |

Every full-output run wrote 200 luminosity records and 200 records to each
moment file. The previously documented fast/slow machine regimes remain
visible, especially in luminosity workloads; no performance conclusion is
drawn from the ordering of unmatched modes. The median solver and luminosity
results are within the observed pre-refactor variability, and the full-output
median agrees with the prior optimized `0.36965 s/turn` result.

Correctness gates passed after the timing study. CPU worker counts 1, 2, and 4
were bitwise identical. CUDA fused tracking at 64, 128, 256, and 512 threads,
with explicit and automatic blocks, was bitwise identical. Radiation and
weak-strong fast/planned paths passed; Gaussian strong-strong passed; CIC, TSC,
and mixed force/luminosity PIC contracts passed with identical cache histories.
All seven PIC launch-family overrides emitted consumer receipts, and invalid
storage, device, worker, and inherited PIC launch configurations were rejected
before particle mutation.

## 2026-07-21 two-level wavefront bounds reduction

The indexed CUDA wavefront path previously called CUDA.jl's generic
`mapreduce` twice per slice pair and transferred each completed extrema tuple
to the host before preparing the next pair. The retained implementation queues
one indexed scan per beam and pair, writes 64 block-local extrema tuples into a
reusable wavefront buffer, reduces all partials in one final kernel per
wavefront, and transfers the completed bounds matrix once. Grid construction,
slice-pair cache coverage and size checks, drift equations, and componentwise
`min`/`max` definitions are unchanged. The CPU path is untouched.

When luminosity is requested, the scan also returns the exact centroid-plane
extrema. The luminosity path reuses those results instead of scanning both
beams a second time. Solver-only launches use the eight-value force kernel, so
they do not carry the four additional luminosity extrema or their register
cost.

An initial one-kernel implementation atomically accumulated every block's
`Float64` extrema. It passed the backend contract but regressed to `0.31991
s/turn`; diagnostic bounds time was about `65--71 ms/turn`. Restricting the
scan to 32 blocks reduced bounds time to about `45--49 ms/turn` but remained
too close to the generic reduction. It was rejected. The retained two-level
design removes the global extrema atomics and measured about `38.6--39.1
ms/turn` for the force bounds scan in synchronized phase diagnostics.

The production-size solver-only reference after the numerical edge fixes had
three final-ten means of `0.31004`, `0.30899`, and `0.30969 s/turn`, with a
median of `0.30969 s/turn`. The retained implementation produced `0.28302`,
`0.28534`, and `0.28753 s/turn`; its median is `0.28534 s/turn`, a 7.86% time
reduction and 1.09x throughput improvement. The matching luminosity-enabled
runs were `0.31535`, `0.31893`, and `0.32351 s/turn`, with a median of `0.31893
s/turn`. This is 12.23% below the immediately preceding 30-turn luminosity
control of `0.36335 s/turn`; that comparison has one control run, so the
three-run optimized spread is retained alongside it rather than implying a
paired three-run estimate.

All four CPU/CUDA force/luminosity method combinations passed: inherited CIC,
inherited TSC, CIC force with TSC luminosity, and TSC force with CIC
luminosity. Across them, the maximum final-coordinate absolute error was
`8.62e-17`, total-luminosity relative error was `9.05e-15`, slice-pair
luminosity relative error was `5.92e-14`, and CPU/CUDA cache histories were
identical. A separate production 30-turn output comparison against the
immediately preceding CUDA implementation found a maximum luminosity relative
difference of `1.12e-15`; every final electron and proton RMS component agreed
to about `1.5e-15` relative or better. The general tracking backend validation
and full package test suite also passed.
