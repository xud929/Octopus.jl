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

The corrected compact final-ten mean was `0.640772 s/turn`. Re-establish the
reference and repeat every optimization candidate after this correctness fix;
the earlier compact/indexed speed comparisons remain historical diagnostics,
not acceptance evidence.

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
