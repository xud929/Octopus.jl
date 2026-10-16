# S2 -- seam pass: CPU/CUDA twin implementations and thread-count invariance

Reading unit S2 of the comprehensive audit of the crab cavity noise campaign,
2026-10-16. Repository `/cfs/ad/dxu/Library/Julia/Octopus`, main checkout at
`3126908` (working tree clean but for the untracked
`docs/history/audit_crab_cavity_noise_neighbours_2026_10_16.md`). Machine:
acnlinj4-class node, 128 cores, NVIDIA RTX 4500 Ada (shared during the run
with another process holding 11.9 GB, so every device-memory number below is
per process, not global), julia 1.12.4, CUDA.jl 6.3.1, FFTW.jl 1.10.0.
Scratch: `result/audit_crab_noise_2026_10_16/S2/` (probe scripts `p*.jl`,
their logs `p*.log`, the artifacts they wrote). Nothing under `src/`,
`test/`, `docs/` or `validation/` was modified.

## 1. Region and provenance

Read line by line (R) and executed (X):

| participant | file(s) | R/X |
|---|---|---|
| the wrapper, the rules, the hook, the slot protocol, the walks | `src/elements/turn_modulated.jl` (all 1671 lines) | R |
| the crab cavity's kick, container, `_realize_draws`, wrap | `src/elements/crab_cavity.jl` (all 461 lines) | R, X |
| the RF cavity's kick, container, `_realize_draws`, wrap | `src/elements/rf_cavity.jl` 1-600 (the thin cavity and its modulation block; the accelerating cavity 600-833 skimmed for its "no rule" declaration) | R, X |
| the device conversion and the CPU/CUDA `track!` routes | `src/track/phase6d_track.jl` 1-135, 180-448 | R, X |
| the weak-strong `execute!`, both turn loops, the plan segments, the segment executor, the survey rebind, the runtime-entry cache | `src/tasks/Tasks.jl` 630-760, 960-1260, 1300-1324, 1486-1497, 1615-1680, 1820-1978 | R, X |
| the recorder | `src/tasks/RunArtifact.jl` 14-50, 536-640 | R, X |
| the worker partition, the isolated luminosity fold, the moment row | `src/policies/Policies.jl` 1236-1278; `src/track/strong_beam_track.jl` 55-150; `src/tasks/BeamObservers.jl` 1039-1062, 1225-1261 | R |
| the backend-consistency script and its contract | `validation/tracking_backend_consistency.jl` (all 313 lines); `validate(::ElementTrackingBackendConsistencyContract)` in `src/contracts/Contracts.jl` | R, X |
| the testsets named in the brief | `test/runtests.jl` 8052-8230 ("effectiveness at the kernel boundary ..."), 15016-15114 (the `Core.Box` sweep and its allowlist), 15116-15230 (thread-count invariance), 17316-17517 (the one-particle probe), 22923-23117 ("CPU/CUDA identity and the device conversion"); `test/turn_modulation_probe.jl` (all 543 lines) | R, X (the sweep re-run; the probe harness driven) |
| references | `docs/design/turn_modulation.md` sections 3, 4.2-4.5, 8-9; `docs/history/turn_modulation_record_2026_10_15.md` section 2; `docs/current_runtime.md` "Current Backends" and "Current GPU Validation Notes"; `docs/design/testing_lanes.md` (all); `docs/design/turn_modulation_record.md` 250-290; `docs/history/crab_cavity_noise_mpi_benchmark_2026_10_14.md` (the identity verdicts) | R |

Probe scripts, all in the scratch directory and all re-runnable from the
project root with `julia --project=. --threads=4 <script>` unless a thread
count is part of the measurement:

- `p1_rules_cpu_cuda.jl` + `p1_schedule.jl` (hypothesis 1, crab cavity, four rule kinds, CPU and CUDA);
  `p1b_rf_cpu_cuda.jl` (hypotheses 1 and 7, RF cavity);
- `p2_large_table_cuda.jl`, `p2b_update_cost.jl`, `p2c_execute_wall.jl`, `p2d_memory_control.jl` (hypothesis 2);
- `p3_float32_cuda.jl` (hypothesis 3);
- `p4_all.sh` driving `p4_threads_run.jl` at `--threads=1|4|8`, the example harness `test/examples/crab_cavity_noise.jl` at 10000 macroparticles, and `p4_compare.jl`; `p4d_fused_lumi.jl` at `--threads=1|4|8` (hypothesis 4);
- `p5_device_compile.jl` (hypothesis 5, with the `Core.Box` sweep);
- the shipped `validation/tracking_backend_consistency.jl` and `p6_modulated_contract.jl` (hypothesis 6);
- `p7_fused_cuda_launch.jl` (hypothesis 7).

## 2. The seam as the code has it

The order on every turn of the weak-strong task is: host-side `update_line`
with the recording sink, store the rebuilt tuple back into the segment's
`Ref`, then the tracking call, which on CUDA converts the tuple for the
device at the `@cuda` launch.

- General loop (an artifact, observers, actions or line hooks present):
  `Tasks.jl:1121-1123` brackets `_execute_tracking_plan_turn!(rep, plan,
  policy, ctx; sink=_tm_sink)` with `_tm_begin_turn!` / `_tm_end_turn!`;
  `Tasks.jl:1847-1853` (`FusedSegment`): `elems = update_line(segment.elements[],
  ctx, sink)`, `segment.elements[] = elems`, `_track_fused_runtime!(rep, elems,
  policy, ctx, stream)` -> `track!(rep, elems, 1, policy, ctx)`
  (`Tasks.jl:1934/1936`, one turn) -> `_cuda_launch_track_policy!`
  (`phase6d_track.jl:332-348`) -> `@cuda ... cuda_track_kernel!(rep, elems, 1,
  ctx)`; `@cuda` converts `elems` with `cudaconvert`, which recurses through
  the tuple via `Adapt.adapt_structure`, and `phase6d_track.jl:238-242` drop
  `TurnModulated` to `w.inner` and descend `CompositeLine`, `MisalignedElement`,
  `RefTilted`. `LuminousFusedSegment` (`Tasks.jl:1855-1861`) has the same
  order and is CPU-only (`:fused` on a device is refused at `Tasks.jl:1073`).
- Fast loop (a bare task): `Tasks.jl:1239-1240`, `runtime_elems =
  update_line(runtime_elems, ctx)` then `track!(rep, runtime_elems, 1, policy,
  ctx)`; the plain hook, no sink, because the predicate at `Tasks.jl:975-976`
  requires `task.artifact === nothing`.
- The recorder (`RunArtifact.jl:561-595`) is fed from `update(w, ctx, sink)`
  (`turn_modulated.jl:1367-1374`) with the very `draws` tuple `_realize_draws`
  built the realised element from; it never reads device memory and flushes
  through HDF5 on the host; the device launch is asynchronous, which is safe
  because nothing on the host path reads the device after the launch except
  observers, which synchronise on the same stream.
- Every `track!` call in the task layer passes exactly one turn (grep: lines
  1240, 1934, 1936, 1946, 1948), so the kernel's internal multi-turn loop
  (`cuda_track_kernel!`, `phase6d_track.jl:257-284`) is reached from a task
  with `turns = 1` only; a bare `track!(rep, line, turns)` through a wrapper
  runs the nominal `inner` for every turn by design D5 (measured, section 3.7).
- The plan cache is emptied whenever the runtime entries recompile
  (`Tasks.jl:1321`), so a cached segment can never realise from a stale
  `base` or a stale resolved spectral table after a knob or seed-driven
  recompile (the seam I went looking for in the cache; closed in code).

## 3. Hypotheses and measurements

### 3.1 Host-side ordering and the recorder (hypothesis 1)

Code: as in section 2. Measurement, `p1_rules_cpu_cuda.jl` (the suite's
one-particle probe harness with its spec builder and replay overridden to
four rule kinds; a 3-harmonic crab cavity, one particle at randomised offsets,
64 turns, `MomentObserver` every turn, `record_turn_modulation = true`;
schedule H1 phase table / strength spectral, H2 spectral / table, H3 white /
pink, ALL phase [pink, spectral, white] / strength [white, table, spectral];
base seed `0x5252202610160001`, per-verification seeds in `p1.log`):

| backend | verifications | C1 record on vs off | C2 steps differ from | C3 predicted-from-record vs observed | series vs CPU | rows vs CPU |
|---|---|---|---|---|---|---|
| CPU threads (4) | 4/4 PASS | bitwise, every column | turn 0 (px and pz; py bitwise) | 0 ulp px and pz on all four; free-running chain 0 | - | - |
| CUDA | 4/4 PASS | bitwise | turn 0 | px 4, 0, 0, 1 ulp of the state (H1, H2, H3, ALL); pz 0 ulp; excess beyond one state ulp relative to the kick: 2.057e-16 (H1), 0, 0, 0; pin 1e-14 | bitwise, all four kinds | max abs 1.36e-20 (H1), 0 = bitwise (H2, H3), 4.34e-19 (ALL) |

The record's section 2.2 numbers for white and pink (excess <= 2.0e-16 of
the kick on px, 0 on pz; rows 4.3e-19 apart at most) are reproduced here for
the table and the spectral kinds as well. The naive step difference reads
16-34 ulp of the px kick and 1.0e3-4.1e3 of the pz kick on both backends,
the state's rounding, as the record says.

RF cavity, `p1b_rf_cpu_cuda.jl` (one particle, 64 turns, each kind on the
phase and on the strength, record on): record on vs off bitwise on both
backends for all four kinds; the `execute!` run equals a hand-realised
per-turn reference on the SAME backend bitwise (`realize(w.rule, w.base,
TrackingContext(turn=t))` on the task-compiled, survey-bound wrapper, tracked
one turn through bare `track!`) for all four kinds on CPU and on CUDA (D8
for the second element kind); the recorded series bitwise across backends;
CPU against CUDA coordinates 3.469e-18 apart at most, modulated and nominal
alike (the modulation adds no backend discrepancy); modulated against
nominal differ on z and pz from the first turn (pz gaps 1.6e-7 white, 3.3e-6
pink, 2.9e-6 table, 1.5e-10 spectral at the probe's sigmas).

### 3.2 Large tables on the device (hypothesis 2)

`p2_large_table_cuda.jl`, `p2d_memory_control.jl` (n = 10000 on the device,
a crab cavity with a 2^20-entry `TurnTable`, 8 MiB on the host):

- CUDA.jl pool bytes allocated around compile plus one turn: 0; around 200
  further turns: 0. The same for a resolved `SpectralNoise` of 2^20 turns
  (synthesis 0.407 s on this machine; compiled rule `TurnTable{Float64}` of
  length 1048576).
- The process's device memory (`nvidia-smi --query-compute-apps`): 226 ->
  246 MiB at the FIRST compile of the session for the unmodulated line as
  well (the kernel module load), then +0 MiB for the white rule, the 2^20
  table and a 2^24 table (128 MiB on the host), each with 0 pool bytes.
- The kernel argument (`CUDA.cudaconvert` of the compiled line) is 64 bytes,
  `Tuple{ThinCrabCavity{1,Symplectic6DMap,Float64}, CrabDispersion{...}}`,
  for a 2^10 and for a 2^20 table alike; `isbits(line) = false`,
  `isbits(converted) = true`.

Per-turn cost, `p2b_update_cost.jl` (inside a function, every iteration's
result consumed; the first attempt let LLVM delete the loop and read 0.3 ns):
host `update_line` per turn, crab / RF cavity: table 1.4 / 1.4 ns, white
118 / 93 ns, pink (16 octaves) 799 / 851 ns, 0 bytes allocated in every case;
one CUDA fused launch and run of one turn at n = 10000: 6.8 us; `execute!`
wall per turn at n = 10000 over 2000 turns, `p2c_execute_wall.jl`, alternating
the three rules three times: 7.0 us for table, white and pink alike in
rounds 2 and 3 (round 1: 25.5, 11.8, 11.9 us, warm-up). The host-side lookup
is 2e-4 (table) to 0.12 (pink) of a 10000-particle device turn.

### 3.3 Float32 lines on CUDA (hypothesis 3)

`p3_float32_cuda.jl`. The crab cavity narrows: `ThinCrabCavitySpec{1}(394.0f6;
...)` compiles to `ThinCrabCavity{1,Symplectic6DMap,Float32}` (its `T` is
`typeof(float(frequency))`, `crab_cavity.jl:134`). On it:

| rule | compile | realised type | draws | CPU and CUDA run | series CPU vs CUDA | coordinates CPU vs CUDA (modulated; nominal line bitwise) |
|---|---|---|---|---|---|---|
| `WhiteNoise(1e-2)` (Float64 sigma) | accepted, sigma promoted at realisation | same as base | `Tuple{Float32,Float32}` | both, kick 3.5e-6 | bitwise | 7.3e-12 abs = 32 Float32 ulp |
| `PinkNoise(1e-2)` | accepted | same | Float32 | both, kick 5.4e-5 | bitwise | 1.5e-11 = 68 ulp |
| `TurnTable(Float32[...])` | accepted | same | Float32 | both, kick 6.6e-6 | bitwise | 7.3e-12 = 24 ulp |
| `TurnTable(Float64[...])` | REFUSED: "phase_noise[1]: a Float64 turn table on a Float32 cavity is refused rather than promoted; convert the table to Float32" | - | - | - | - | - |
| `SpectralNoise(...)` | accepted, resolves to `TurnTable{Float32}` | same | Float32 | both, kick 7.4e-9 | bitwise | 1.1e-11 = 6 ulp |

The RF cavity does NOT narrow: `ThinRFCavitySpec(197.0f6; voltage=1.0f6,
e0=275.0f9, mc2=Float32(PMASS_EV))` stores Float32 parameters but
`ThinRFCavity(spec)` takes `T = numeric_type(spec)` (`rf_cavity.jl:357`),
and `numeric_type` folds the parameters onto a `Float64` default
(`Knowledge.jl:675-677`), the documented floor (`linear_maps.jl:17-28`:
"Float64 is a FLOOR ... Float32 still land on Float64"). Consequences
measured: a Float64 table on the "Float32" RF cavity is ACCEPTED
(`TurnModulated{ThinRFCavity{..., Float64}, RFCavityNoise{Nothing,
TurnTable{Float64}}}`), a Float32 table is refused; a Float32 beam through it
RUNS on CPU (coordinates stay Float32, the Float64 kick narrowed on every
store) and FAILS on CUDA with `InvalidIRError ... call to jl_f_tuple ...
ijl_get_nth_field_checked` for the nominal and the white-noise line alike,
while the same Float32 beam through a Float64 CRAB cavity runs on both
backends. See leads S2-2 and S2-3.

### 3.4 Thread-count invariance at 1, 4 and 8 threads (hypothesis 4)

The claim found: `docs/history/crab_cavity_noise_mpi_benchmark_2026_10_14.md`,
"Thread count alone (one process, another OCTOPUS_CPU_THREADS) is bitwise"
(threads:8 and threads:32 against threads:16: "whole output bitwise
identical"); the design note's section 8 ("the rebuild is thread-count
invariant by construction"); the fixed 64-chunk fold of the luminosity
(`strong_beam_track.jl:59-97`, `Tasks.jl:1904-1930`) and the serial moment
sum (`_masked_global_sum`, one serial sum per rank). Pin: bitwise.

- (a) The recorded series and the moment rows of the four-kind one-particle
  probe at `--threads=1|4|8` with `CPUThreadsExecutionPolicy(threads=T)`
  (`p4_threads_run.jl`): PASS at every T on all four verifications; the
  FNV-1a digests of the series (`dphi`, `d`) and of the rows (`px`, `pz`,
  `x`) are identical across T (`p4_compare.jl`, section 3.4b below for the
  verdict line).
- (b) The 10000-particle weak-strong run of the campaign's harness
  (`test/examples/crab_cavity_noise.jl`, 64 turns, both crab cavities
  modulated on two harmonics each, radiation on, isolated luminosity route;
  white and spectral at T = 1, 4, 8; pink and table at T = 1, 8): see the
  P4b verdict lines appended at the end of this section.
- (c) The spectral synthesis: `FFTW.get_num_threads() = 1` at every julia
  thread count; `spectral_turn_table(:pink, 1e-5, (2^-16, 0.5); turns=2^20,
  seed=42, rng_id=1)` digest `d355ed141c7a0fb6` (fixed) and
  `8e28e14275dde703` (rayleigh), and a `SpectralNoise` resolved at compile
  under seed `0x5eed` digest `710b12bc7a432461`, identical at
  `--threads=1|4|8`.
- (d) The `:fused` luminosity route, which the example does not take
  (`p4d_fused_lumi.jl`: two modulated cavities carrying all four kinds, a
  thin strong beam, a moment observer, 10000 particles, 64 turns,
  `luminosity_tracking = :fused`, record on): at T = 1, 4, 8 the receipt
  names `route = fused` and 64 logical workers (the chunk grid), and the
  luminosity series (`367a256497dd9f2c`, 64 rows, mean 7.8506e10), the
  moments table (`db9c3715ed9fe7cf`) and the recorded series
  (`617455871796fa66`, 384 values) carry one digest each at every T.

P4b verdict lines (from `p4_all.log`, `p4_compare.jl`):

```
S2-P4a/c summaries bitwise identical across threads (series, rows, spectral digests): true   [T = 1, 4, 8]
S2-P4b white    T=1 vs T=4: luminosity_bitwise=true (64 rows) moments_bitwise=true (max_abs_gap 0.000e+00, 29 columns) series_bitwise=true (8 slots x 64 turns)
S2-P4b white    T=1 vs T=8: luminosity_bitwise=true (64 rows) moments_bitwise=true (max_abs_gap 0.000e+00, 29 columns) series_bitwise=true (8 slots x 64 turns)
S2-P4b pink     T=1 vs T=8: luminosity_bitwise=true (64 rows) moments_bitwise=true (max_abs_gap 0.000e+00, 29 columns) series_bitwise=true (8 slots x 64 turns)
S2-P4b table    T=1 vs T=8: luminosity_bitwise=true (64 rows) moments_bitwise=true (max_abs_gap 0.000e+00, 29 columns) series_bitwise=true (8 slots x 64 turns)
S2-P4b spectral T=1 vs T=4: luminosity_bitwise=true (64 rows) moments_bitwise=true (max_abs_gap 0.000e+00, 29 columns) series_bitwise=true (8 slots x 64 turns)
S2-P4b spectral T=1 vs T=8: luminosity_bitwise=true (64 rows) moments_bitwise=true (max_abs_gap 0.000e+00, 29 columns) series_bitwise=true (8 slots x 64 turns)
```

The harness's own per-run checks passed at every T (each white series' rms
inside its 1 +- 0.44 band at 64 turns; eight active slots per run; the
`:turn_modulation` receipt `first_turn = 0, turns = 64`). The documented
bitwise claim holds for every rule kind at 1, 4 and 8 logical workers
(`CPUThreadsExecutionPolicy(threads=T)` paired with `--threads=T`), on the
isolated route (the harness) and on the fused route (P4d).

### 3.5 Device compilability (hypothesis 5)

`p5_device_compile.jl`: for the crab cavity (2 harmonics, each kind on one
phase and one strength slot; a 4-harmonic container mixing all four kinds; a
misaligned and tilted spectral cavity; a table cavity inside a kept-whole
`BeamLine`) and the RF cavity (each kind on phase and strength; a misaligned
pink cavity), the task-compiled line was updated on the host and
`CUDA.@cuda launch=false cuda_track_kernel!(rep, line, 1, ctx)` and its
context-free sibling compiled in 12 of 12 cases; the converted argument was
isbits and held no wrapper in every case, the element type the bare cavity
(`ThinCrabCavity{N,...}`, `ThinRFCavity{...}`, or the frame wrapper /
`CompositeLine` around it). The bare multi-turn `track!` through the wrapper
on CUDA equals the nominal line bitwise (D5). An RF cavity inside a
kept-whole `BeamLine` is refused by the survey binder before any launch
("the survey walk found 0 thin_rf_cavity spec(s) but the compiled line
contains 1"), the documented behaviour.

Device-reachable throws: `rf_cavity.jl:141` (`_rf_kick`, static message,
compiled above); the crab cavity's `track_particle` has none; the
`BoundsError`s at `crab_cavity.jl:254-276` are host `getindex` methods; the
rules' `_turn_offset` methods are host-side and static (`turn_modulated.jl:
972-974`, the `checkbounds` at 1009). No interpolated message is reachable
from the kernel.

The `Core.Box` sweep re-run over the current method table with the suite's
allowlist: 3775 methods swept, 0 offenders, 5 boxes all on the allowlist
(`read_beam_coordinates`, `validate`, `GaussianStrongBeam`,
`_activate_symbolics_adapter!`, `_contract_default_initial_rep`), none in
`turn_modulated.jl`, `crab_cavity.jl`, `rf_cavity.jl`, `Tasks.jl`,
`RunArtifact.jl` or `phase6d_track.jl`.

### 3.6 The backend-consistency script (hypothesis 6)

The shipped script, run whole (`p6a_validation_script.log`, N = 10000,
2 turns, atol = rtol = 1e-10): CPU/CPU max_abs 0; CPU/GPU max_abs
5.256e-16, max_component_rel 1.19e-10 (within the 1e-10 + 1e-10 combined
tolerance, max_allowed_ratio 5.2e-6), 60000 coordinates compared, passed;
the accelerating-cavity arm 6.83e-18; the aperture arm 40350 of 60000 slots
killed on both backends identically, 19650 compared at 0. Its line carries
`ThinCrabCavitySpec{2}` and `ThinRFCavitySpec` WITHOUT any rule (grep
`phase_noise|strength_noise` in the script: no match), so the script never
exercises `TurnModulated` or its device conversion (lead S2-1). The contract
itself tracks through `execute!`, so it would: `p6_modulated_contract.jl`
(the script's crab cavity with white and pink on the phases and a table and
a spectral rule on the strengths, two RF cavities with spectral/table and
pink/white): CPU/CPU 0; CPU/GPU max_abs 6.627e-18, global_rel 5.5e-16,
passed; the same line with every rule removed: 6.627e-18, so the modulation
contributes nothing to the backend gap.

### 3.7 The fused CUDA path (hypothesis 7)

There is no multi-turn fused kernel on a task route: the segment executor and
the fast loop launch one turn per call (section 2). `p7_fused_cuda_launch.jl`
(n = 1024 on the device, 8 turns, crab and RF cavities with each kind): the
`:cuda_fused_launch` receipts count 8 per `execute!` on both loops (fast
`fast_path = true`, general `false`), 1024 particles per launch; the fast
loop equals the hand-realised per-turn device reference bitwise in all 8
cases; the general loop equals the fast loop bitwise in all 8; a bare
multi-turn `track!(rep, line, 8)` differs from the `execute!` run (gaps
4.0e-9 to 4.8e-6), the nominal element for every turn by D5. The fused
LUMINOSITY route cannot reach a device (`Tasks.jl:1073` refuses it), and the
turn-modulated element is never baked into a kernel: the kernel argument is
rebuilt and converted at every launch.

## 4. Leads

### LEAD S2-1 [low, confidence high] validation/tracking_backend_consistency.jl:82
Claim: the backend-consistency script the Verification Matrix names for CUDA-reachable element code covers neither cavity with a rule, so the campaign's device conversion is outside the script and verified by the suite's identity testset only.
Mechanism: the script's line builds `ThinCrabCavitySpec{2}(197.0e6; strengthX, strengthY, phase)` and `ThinRFCavitySpec(197.0e6; strength, beta0, gamma0)` with no `phase_noise`/`strength_noise`, so `_turn_modulation_wrap` returns the bare cavities and `TurnModulated`, `Adapt.adapt_structure` and the per-turn `update_line` are never on the path; the contract tracks through `execute!`, so adding a rule would exercise them at no change to the contract.
Repro: `grep -n "phase_noise\|strength_noise" validation/tracking_backend_consistency.jl` prints nothing; `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S2/p6_modulated_contract.jl` prints `CPU/GPU modulated line: status=passed` with `max_abs_error = 6.627185779317646e-18`, equal to the quiet line's.

### LEAD S2-2 [medium, confidence high] src/elements/rf_cavity.jl:357
Claim: an RF cavity declared with Float32 parameters compiles to a Float64 runtime, so the documented "Float64 table on a Float32 cavity" refusal is unreachable for it, and a Float32 beam through it compiles and silently narrows on CPU but fails on CUDA with an `InvalidIRError`.
Mechanism: `ThinRFCavity(spec)` takes `T = numeric_type(spec)`, which folds the parameters onto a `Float64` default (`src/knowledge/Knowledge.jl:675-677`), so `T` is never `Float32`; `_check_rule_numeric_type` then compares a Float64 table against `Float64` and accepts it, while a Float32 table is refused. On a `Phase6DRep{CuArray{Float32}}` the kernel's `fusedTrack` through `_rf_kick` sees Float32 coordinates and Float64 element fields; the `if _has_survey(elem) z += ... end` branch (`rf_cavity.jl:154-157`) gives `z` a branch-dependent type, the result tuple becomes dynamic (`jl_f_tuple`) and the device compile fails, where the CPU path converts on every store (`Beam.jl:187`) without a word. No guard at `execute!` compares the storage eltype with the elements' numeric type (grep `eltype(rep` in `Tasks.jl`: only the luminosity partials).
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S2/p3_float32_cuda.jl` prints `rf32 spec: strength param type = Float32, numeric_type(spec) = Float64, compiled runtime = ThinRFCavity{Symplectic6DMap, Float64}`, `rf32 + Float64 table -> accepted`, `rf32 (Float64 runtime) on a Float32 beam, cpu nominal: ran`, `... cuda nominal: FAILED: InvalidIRError`.

### LEAD S2-3 [low, confidence medium] src/elements/crab_cavity.jl:134
Claim: the crab cavity narrows to Float32 from a Float32 frequency, against the Float64-floor policy every other element follows, so the two modulated kinds disagree on what a "Float32 line" is, and the Float32 CPU/CUDA agreement of a modulated crab cavity (up to 68 Float32 ulp) is pinned nowhere.
Mechanism: `ThinCrabCavity(spec)` derives `T = typeof(float(frequency))` from one parameter rather than through `numeric_type(spec)`; `src/elements/linear_maps.jl:17-28` records the decision that narrowing "stays behind the explicit `Spec{Float32}` form, because the symplecticity tolerances downstream are calibrated per precision", and `ThinCrabCavitySpec` has no `{T}` form, so a Float32 argument narrows silently. On CUDA a modulated Float32 crab cavity differs from the CPU by 7.3e-12 to 1.5e-11 absolute (6 to 68 Float32 ulp of the coordinate) while the nominal Float32 line is bitwise across backends: the realised nonzero phase routes the device through FMA contraction and libdevice `sinf`/`cosf`, the Float64 mechanism the identity testset documents, two orders larger in Float32 and with no documented tolerance. Out of the campaign's own changes (the constructor predates it) but inside hypothesis 3.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S2/p3_float32_cuda.jl` prints `crab32 spec: frequency param type = Float32, numeric_type(spec) = Float64, compiled runtime = ThinCrabCavity{1, Symplectic6DMap, Float32}` and `crab32 pink cpu-vs-cuda: series_bitwise=true coords_bitwise=false max_abs_gap=1.455e-11 max_ulps32=68.0 (nominal line gap 0.000e+00)`.

No other defect was found in the region; the two Float32 leads are the only
ones that touch behaviour, and both are pre-existing element properties that
the campaign's refusal and its "Float32 line" wording inherit.

## 5. Clean, with the evidence

- Ordering of update, conversion and recording on the CUDA route: read in
  code (section 2) and measured (3.1): the recorded series is bitwise across
  CPU and CUDA for white, pink, table and spectral on the crab and the RF
  cavity; the device run equals the hand-realised per-turn device reference
  bitwise for every kind on both cavities; the predicted rows from the record
  are within 4 ulp of px (excess 2.06e-16 of the kick) on CUDA and 0 ulp on
  CPU, inside the record's pins.
- No device copy of a table: 0 pool bytes at compile and per turn for 2^20
  and 2^24 tables and for a resolved 2^20 spectral table; 64-byte kernel
  argument independent of the table length; process device memory unchanged
  after the first module load (3.2).
- Per-turn host cost negligible against the launch: 1.4 ns (table) to 0.85
  us (pink) against 6.8 us per device turn at n = 10000; `execute!` wall 7.0
  us per turn for all three rules (3.2).
- Thread-count invariance at 1, 4, 8: the probe's series and rows, the
  spectral digests, the `:fused` route's luminosity, moments and series are
  bitwise (3.4; the harness arms in the P4b lines).
- Device compilability: 12 of 12 realised lines compile, every converted
  argument isbits and wrapper-free; no interpolated throw reachable from a
  kernel; `Core.Box` sweep 3775 methods, 0 offenders (3.5).
- The shipped backend-consistency script passes (CPU/GPU 5.26e-16 on its
  full line) and the modulated-line contract passes at 6.63e-18, equal to
  the quiet line (3.6).
- One launch per turn on both loops, the fused tuple rebuilt and converted
  at every launch, no multi-turn kernel reachable from a task; the plan cache
  emptied on recompile (2, 3.7).
- The `_survey_rebind(::TurnModulated)` resets `inner` to the rebound `base`
  (`Tasks.jl:1494-1497`), and the RF cavity's realised element carries the
  survey fields verbatim (`rf_cavity.jl:493-495`): the P1b hand-realised
  reference built from the task-compiled wrapper matched `execute!` bitwise.

## 6. Not checked, and why

- The strong-strong loop's host-side placement (`src/tasks/strongstrong/
  interface.jl:3120`, the second caller of the segment executor, and the
  beam-2 recorder): outside the brief's weak-strong seam.
- The MPI execution policy arm: outside the brief (threads and CUDA only).
- Thread counts above 8 and the CPU `:fused` route on a device (refused by
  design, so there is nothing to run).
- A Float32 RF cavity on CUDA with the four rule kinds: no Float32 RF
  runtime exists (lead S2-2), so the matrix cell cannot be filled.
- `validation/moment_observer_backend_consistency.jl`: not a campaign
  participant; the moment reduction's CPU/CUDA agreement entered only through
  the probes' rows (3.469e-18 to 4.34e-19 on one particle).
- Occupancy-cache keying (`phase6d_track.jl:316`, `typeof(elems)` of the
  unconverted tuple): read, judged consistent (the converted type is a
  function of it), not measured.
