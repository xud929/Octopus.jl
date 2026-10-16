# U4 report: the strong-strong turn loop and the turn-modulation recorder (EXECUTED unit)

Audit of the crab-cavity-noise campaign, 2026-10-16. Repository: Octopus, main
checkout `/cfs/ad/dxu/Library/Julia/Octopus` at `3126908`. Machine: Xeon Gold
6430, RTX 4500 Ada (CUDA active), julia 1.12.4, MPICH 5.0.1 through the
default environment's MPI.jl (`mpiexec` =
`~/.julia/artifacts/8bd6881e43b97a8d20af0db9dbda166281c02323/bin/mpiexec`).
Scratch: `result/audit_crab_noise_2026_10_16/U4/` (git-ignored; 92 files, 15 MB:
the probe scripts, every run's `.h5`, `.jld2` and `.log`, every comparison
log). Nothing in the repository was modified.

## Region

`src/tasks/strongstrong/interface.jl`, the campaign diff `6995151..3126908`
(62 insertions, 13 deletions) and its neighbours, every line read:

- `validate_configuration_metadata()` RunArtifact block (2063-2075)
- `configuration_report(::StrongStrongTask, ...)` output entry (2346-2371)
- `StrongStrongTask` constructor, the duplicate-stream call over both lines (2383-2420)
- `execute!(::StrongStrongTask, ...)` and the scope comment (2463-2500)
- `_execute_strong_strong_task!`: the `:strong_strong_output` receipt (2619-2624),
  the provenance, `prepare_run_artifact!` with `turn_modulation_columns` (2664-2673),
  the observer prepare, the try/finally (2594-2729)
- `_execute_strong_strong_turns!`: the per-beam sinks, the ledger stamp, begin/end turn (2797-2890)
- `_execute_strong_strong_segment_pair!` / `_strong_strong_segment_streams` /
  `_execute_strong_strong_segment!` (3076-3122), `_strong_strong_physics_line` (3245-3251)

Read for the seams the loop crosses (not audited as regions): `src/tasks/RunArtifact.jl`
(the `TurnModulationRecorder`, `prepare_run_artifact!`, `_ra_create_turn_modulation_series!`,
`_turn_modulation_sink`, `_record_turn_draws!`, `_tm_begin_turn!`/`_tm_end_turn!`,
`_ra_flush_turn_modulation!`, `_ra_flush_luminosity!`, `_ra_push_probe_rows!`,
`finalize_run_artifact!`, the readers `_ra_tm_series`/`read(::TaskOutput)`),
`src/tasks/Tasks.jl` 1828-1882 (`_execute_tracking_plan_turn!` with `sink`) and
426-470 (the duplicate warnings), `src/elements/turn_modulated.jl` 960-1030 and
1340-1415 (`_turn_offset`, the recording hook), `src/elements/crab_cavity.jl`
305-355 and `src/elements/rf_cavity.jl` 470-505 (slot numbering),
`src/policies/Policies.jl` 500-545 and 924-990 (`_mp_is_root`, the shards).
Reference documents read: `docs/design/turn_modulation_record.md` sections 8-9,
`docs/design/run_artifact.md` (schema, options, crash recovery, execution
diagnostics), `docs/current_runtime.md` backends and GPU notes,
`docs/design/testing_lanes.md` section 3, `docs/design/multi_process_policy.md`
consistency table (1100-1121), `docs/history/turn_modulation_record_2026_10_15.md`
(the two "not verified" statements, lines 188-191 and 544-546), the suite's
"The run artifact records the realised turn modulation" (test/runtests.jl
16745-17330) and the MPI launcher testset (19334-19680).

## Provenance

EXECUTED. Every claim below carries a run. The probe fixture
(`U4/u4_fixture.jl`) builds two beams (4096 electrons at 10 GeV, 3072 protons at
275 GeV, `set_global_rng!(seed=0x4a4e, method=:philox)`, `rng_id` 1 and 2),
beam 1's line `(one-turn Linear6D, ThinCrabCavitySpec{2} with phase_noise[1] =
WhiteNoise(1e-2; rng_id=11) and strength_noise[1] = WhiteNoise(1e-3; rng_id=13),
ThinRFCavitySpec with phase_noise = WhiteNoise(1e-2; rng_id=21) and
strength_noise = PinkNoise(1e-3; rng_id=22, octaves=4), MomentObserver "m1",
StrongStrongCollision(:ip), Linear6D)`, beam 2's line `(Linear6D,
ThinCrabCavitySpec{1} with WhiteNoise rng_id 12 / 14, MomentObserver "m2", ip,
Linear6D)`, the default `GaussianPoissonSolver()`,
`RunArtifact(path; capacity=16, record_turn_modulation=true)`, 64 turns under
`with_execution_audit`. The driver `U4/u4_run.jl <cpu|cuda|mpi> <tag> key=value...`
runs it and dumps the artifact (series per slot through
`turn_modulation_provenance`, luminosity, moments, ledger, the two receipts)
and the final coordinates to `<tag>.jld2`; `U4/u4_compare.jl` compares two
dumps and the reference against the hook's own replay
(`Octopus._turn_offset(rule, TrackingContext(turn=t), slot, Float64)[1]`, the
global seed reset first, slot numbers as the containers hand them: crab phase
harmonic i = slot i, crab strength harmonic i = slot N+i, RF phase 1 /
strength 2); `U4/u4_compare_shards.jl` concatenates the ranks' final shards;
`U4/u4_read_torn.jl` reads a stopped run's file through the three public
reader paths and counts warnings; `U4/u4_dupwarn.jl` probes the constructor's
warnings. "bitwise" below means `all(a .=== b)` with equal sizes.

Commands (all from the U4 scratch directory, `J = julia --project=/cfs/ad/dxu/Library/Julia/Octopus --startup-file=no`):

| run | command | wall (execute!) |
|---|---|---|
| cpu64 | `J --threads=4 u4_run.jl cpu cpu64 turns=64 capacity=16` | 17.1 s |
| cuda64 | `J --threads=4 u4_run.jl cuda cuda64 turns=64 capacity=16` | 45.7 s |
| cpu64t2 | `J --threads=2 u4_run.jl cpu cpu64t2` | - |
| cpu64c24 | `J --threads=4 u4_run.jl cpu cpu64c24 capacity=24` | 19.4 s |
| cpu64b1 | `J --threads=4 u4_run.jl cpu cpu64b1 beam2_modulated=0` | - |
| cpu64b2 | `J --threads=4 u4_run.jl cpu cpu64b2 beam1_modulated=0 rf=0` | - |
| cpu64post / cuda64post | `... u4_run.jl cpu|cuda cpu64post|cuda64post post_ip=1` (a second modulated crab after the IP in both lines, rng 15/16 and 17/18) | 18.2 s / 44.3 s |
| cpu64split | `... u4_run.jl cpu cpu64split split=2 append=1` (two `execute!` of 32 turns on one appended artifact) | - |
| cpu64off / cuda64off | `... u4_run.jl cpu|cuda ... record=0` | - |
| cpu1 | `... u4_run.jl cpu cpu1 turns=1` | - |
| stop40 | `... u4_run.jl cpu stop40 stop_turn=40` (a `BeamSwapAction` after beam 1's modulated elements throws at turn 40) | - |
| hard45 | `... u4_run.jl cpu hard45 stop_turn=45 hard_exit=1` (the action calls `_exit(3)` at turn 45) | exit 3 |
| hard45lum | `... hard45lum stop_turn=45 hard_exit=1 lum_step=100` (luminosity_schedule = EveryNSteps(start=0, step=100)) | exit 3 |
| mpi1 / mpi2 / mpi4 | `mpiexec -n 1|2|4 J --threads=4|2|2 u4_run.jl mpi mpi1|mpi2|mpi4` (`MultiProcessExecutionPolicy(threads=:auto)`) | 17.6 / 17.6 / 18.3 s |

Comparisons: `J u4_compare.jl <ref> <other> [post_ip=1] [turns= slot= t0=]`,
logs `cmp_*.log`; `J u4_compare_shards.jl cpu64 mpi2 2` / `mpi4 4`;
`J u4_read_torn.jl stop40|hard45|hard45lum`; `J --threads=4 u4_dupwarn.jl`.

## Leads

### LEAD U4-1 [low, confidence high] src/tasks/RunArtifact.jl:608 (`_ra_flush_turn_modulation!`) and :870 (`_ra_push_probe_rows!`), the seam of the ledger stamp at src/tasks/strongstrong/interface.jl:2846
Claim: the `/execution` ledger's live-progress columns (`current_turn`, `elapsed`) are persisted only by the luminosity flush and by finalize, so a strong-strong run with a sparse luminosity schedule that is killed leaves the ledger at the nothing-known sentinel while the turn-modulation series and the moment groups hold tens of flushed turns, contradicting `docs/design/run_artifact.md` ("CURRENT TURN and elapsed updated at every flush", Execution diagnostics) and the `read(::TaskOutput, kind)` docstring (RunArtifact.jl:1308, "`current_turn`/`elapsed` updated at every flush").
Mechanism: the loop stamps `art.current_turn` in memory before each turn (interface.jl:2846); the only writers of `ex["current_turn"]` are `_ra_flush_luminosity!` (RunArtifact.jl:656) and `finalize_run_artifact!` (:764). The series flush fired by `_tm_end_turn!` every `capacity` turns and the probe-row flush (`_ra_push_probe_rows!`) write their rows and cursors and `HDF5.flush` the file but never the ledger slot, so on disk the ledger's progress is the turn of the last LUMINOSITY flush, which with `luminosity_schedule = EveryNSteps(step=100)` over 64 turns is never. Reporting only: the `append=true` resume truncates by each group's `rows_valid_through_turn`, not by the ledger, so no rows are lost or mixed; the narrower reader docstring at RunArtifact.jl:1257-1259 ("persisted at the luminosity flushes") already describes this behaviour, the two broader statements do not. Cross-file seam: the flush functions are RunArtifact.jl's, noted here and stopped.
Repro: `cd result/audit_crab_noise_2026_10_16/U4 && julia --project=../../.. --threads=4 u4_run.jl cpu hard45lum stop_turn=45 hard_exit=1 lum_step=100; julia --project=../../.. u4_read_torn.jl hard45lum` prints `raw ledger: ... current_turn=[-1] elapsed=[0.0]`, `raw luminosity: rows=0`, `raw series /turn_modulation/1/{1,2,3}: size=(32, 2)`, `raw moments/m1: rows=32 ... rows_valid_through_turn=31`; the control `hard45` (every-turn luminosity, same kill) prints `current_turn=[31]` with every group through 31.

### LEAD U4-2 [low, confidence med] docs/current_runtime.md:142-146 (out of hypothesis: documentation scope)
Claim: the sentence "a divided run reproduces the undivided one bit for bit in the tracked beam and in the luminosity series" states no scope, and for a strong-strong task across rank counts it is false as written; the design's own table (`docs/design/multi_process_policy.md`:1102-1104) separates tracking (bitwise at every rank count) from strong-strong collides (bitwise at ONE rank, the parity class across counts).
Mechanism: the soft-Gaussian kick is formed from slice moments that are rank-ordered partial sums, so the kicked coordinates and the luminosity differ by the accumulation difference across rank counts; the paragraph sits under `MultiProcessExecutionPolicy` in "Current Backends" after "A tracking task is divided by...", and its measured numbers are the weak-strong crab-noise benchmark's, so a strong-strong reader can over-read it. Measured here: luminosity max relative difference 3.43e-15 (2 ranks vs the single process), 2.42e-15 (2 vs 4 ranks); final coordinates differ by at most 1.11e-16 (z) / 3.1e-18 (px); the 1-rank MPI run is bitwise in every column, as the campaign's literal requirement states and the suite pins (rtol 1e-12 across counts).
Repro: `julia --project=../../.. u4_compare.jl cpu64 mpi2` prints `lum values bitwise: false  maxrel=3.431949186065202e-15`; `u4_compare.jl cpu64 mpi1` prints `lum values bitwise: true`, `final coords ... bitwise=Bool[1, 1, 1, 1, 1, 1]`.

No other lead. The region audits sound against hypotheses 1, 2, 3 and 5; hypothesis 4's exact window is stated below and its one defect is LEAD U4-1.

## Clean list, with the evidence

**(1) The strong-strong recorder on CUDA (first run of this path; the two records said "not verified").** `cmp_cpu64_cuda64.log`: the six series (`1/1/phase_noise[1]`, `1/1/strength_noise[1]`, `1/2/phase_noise`, `1/2/strength_noise`, `1/3/phase_noise[1]`, `1/3/strength_noise[1]`), 64 rows each, bitwise identical CPU vs CUDA and each bitwise equal to the rule replay; the element metadata (beam tags 1,1,2; kinds white/white/white/pink/white/white; rng_ids 11,13,21,22,12,14; `first_turn=0`, `turns=64`) identical; the `:turn_modulation` receipt values identical (`repr` equality); the `:strong_strong_output` values identical except the path (`(artifact, append=false, record_turn_modulation=true)`, one receipt per `execute!`); luminosity 64 rows, turns equal, max relative difference 2.43e-15 against the documented `StrongStrongGaussianBackendConsistencyContract` tolerance 1e-10; moments 56 columns, worst absolute difference 7.6e-17 (`m1/m000020`), 2 columns bitwise (the turn columns); final coordinates differ by at most 2.9e-16 (beam 1 z) and 4.0e-17 (beam 2 z). With the second modulated crab after the IP (`cmp_cpu64post_cuda64post.log`): ten series bitwise CPU vs CUDA and against the replay, luminosity maxrel 2.67e-15, coordinates <= 3.1e-16. On/off on the device (`cmp_cuda64_cuda64off.log`): luminosity, all 56 moment columns and all 12 coordinate arrays bitwise with `record_turn_modulation` true and false, the off run's readers returning `series === nothing` (dumped as empty). The two-stream path (`_execute_strong_strong_segment_pair!` CUDA branch, `streams[1]`/`streams[2]`) therefore records host-side in line order per beam, as the comment says. CUDA at this size is 2.6x slower than four CPU threads (45.7 s vs 17.1 s, compile included), expected at 7k particles.

**(2) Per-beam sinks when the beams interleave block by block.** Capacity 16 over 64 turns (4 flushes) and capacity 24 (2 flushes plus a 16-row tail): every series, the luminosity and the moments bitwise between the two (`cmp_cpu64_cpu64c24.log`); 1 turn with capacity 16 (tail flush only): 1 row per series, equal to the replay (`cpu1`). No value shared between any two series (the compare's cross-series scan printed no WARNING line), so no row crossed beams. Two modulated elements of beam 1 and one of beam 2 before the IP plus one each after it (`post_ip=1`, blocks 1 and 2 both carrying modulated elements, the recorder meeting beam 1's crab, RF, post-crab = provenance 1,2,3 and beam 2's crab, post-crab = 4,5): all ten series equal the replay with the right rng_ids (15/16 on `1/3`, 17/18 on `1/5`). ONE beam modulated, either beam (`cpu64b1`: beam 2 plain; `cpu64b2`: beam 1 plain, no RF): the provenance holds exactly the modulated beam's groups (4 series tagged beam 1; 2 series tagged beam 2), each equal to the replay, zero log records (a `TestLogger` around construction and the run), the configuration report naming the recording. Thread count: 4 threads vs 2 threads bitwise in every column (`cmp_cpu64_cpu64t2.log`). Two windows on one appended artifact (`split=2 append=1`): ledger `start_turn=[0,32] turns=[32,32] current_turn=[31,63]`, slot 1's series = replay(0:31), slot 2's = replay(32:63) with `first_turn=32, turns=32` attributes, luminosity (64 rows), moments and final coordinates bitwise with the single 64-turn run, two `:strong_strong_output` receipts, the report saying "continuing the run artifact at ..., recording the turn-modulation series" (`cmp_split_slot1.log`, `cmp_split_slot2.log`).

**(3) MPI at 1, 2 and 4 ranks (`MultiProcessExecutionPolicy`).** Rank 0 writes once: `execution_slot = 1` on rank 0 and 0 on every other rank, one ledger row, 64 luminosity rows, 64 moment rows per probe. Non-root ranks hold no recorder: the in-scope probe (`prepare_run_artifact!` on a fresh artifact inside `_with_execution_policy`/`_with_beam_shards`) reports on rank 0 `recorders=2, has_file=true, sink1=true, sink2=true, recorder_beams=[1,2], recorder_keys=[["turn_modulation/1/1","turn_modulation/1/2"],["turn_modulation/1/3"]]` and on every other rank `recorders=0, has_file=false, sink1=false, sink2=false` (2 and 4 ranks; `cmp_shards_mpi2.log`, `cmp_shards_mpi4.log`). Shards: 2 ranks `b1=(0|2048)/4096, b2=(0|1536)/3072`; 4 ranks offsets 0,1024,2048,3072 and 0,768,1536,2304. The six series bitwise equal to the single-process run at 1, 2 and 4 ranks and the `:turn_modulation` receipt identical. One rank: luminosity, moments and both beams' coordinates bitwise with the single process (the campaign's literal requirement). Two and four ranks: luminosity maxrel 3.43e-15 / coordinates <= 1.11e-16 (2 ranks), 2.42e-15 between 2 and 4 ranks, the parity class the design table and the suite's rtol 1e-12 state -- NOT bitwise, see LEAD U4-2 for the sentence that implies otherwise.

**(4) The ledger window.** Read from the code: within turn N, `art.current_turn = N` is assigned in memory (2846) before `_tm_begin_turn!` (2847-2848); each block then runs beam 1's segment (the hook appends the turn's draws to beam 1's buffers, in line order) and beam 2's; a collision pushes the luminosity row and, on the 16th pending row, `_ra_flush_luminosity!` persists rows through N, `rows_valid_through_turn = N`, `current_turn = N` and `elapsed`; after the last block `_tm_end_turn!(sink, N)` counts the row and, on the 16th, appends the series rows through N. So a hard kill between the luminosity flush and the series flush of a flush turn (N = 15, 31, ...) leaves ledger N, luminosity through N, series through N - 16; a hard kill elsewhere leaves every group at the last flush boundary; an exception during turn N (any producer, any rank) runs the finally path, whose finalize writes the series' complete rows through N - 1, the pending luminosity rows and `current_turn = N`. Measured: soft stop at turn 40 (`read_stop40.log`): ledger `current_turn=[40]`, luminosity rows 40 (through 39), each series `(40, 2)`, moments through 39 -- "ledger at N, rows through N-1" as the brief put it; hard kill at turn 45 with every-turn luminosity (`read_hard45.log`): ledger 31, luminosity through 31, series `(32, 2)`, moments through 31; hard kill with a sparse luminosity schedule: LEAD U4-1. The readers on such files: `turn_modulation_provenance`, `read(TaskOutput, :turn_modulation)` and `read(TaskOutput)` each return the rows as they stand with exactly one warning per element group (3 per read here: "/turn_modulation/1/k/series holds 40 recorded turn(s) of the 64 its turns attribute declares (first_turn 0): ..."), `first_turn=0, turns=64` on each element entry; `read(:execution)`, `read(:luminosity)`, `read(:moments)` read without warning; the HDF5 file of a hard-killed process opened and read normally in all three cases (flushed at every batch). No reader cross-checks the ledger against the series row count.

**(5) The receipt's new field.** `grep -rn strong_strong_output src/ test/ validation/ examples/ ext/ profiling/`: the producer `interface.jl:2619`, the schema declarations `RunArtifact.jl:223,244` and `interface.jl:1848`, the report entry `interface.jl:2367`; readers only in `test/runtests.jl:17027-17052`, which filter by `r.consumer === :strong_strong_output` and read `.values.record_turn_modulation`, `.artifact`, `.append` by name (`propertynames(orc_on) == (:artifact, :append, :record_turn_modulation)` additionally pins the field order -- a names-tuple pin, not a positional read). No contract reads the receipt: `src/contracts/Contracts.jl` pins `RunArtifact` only through `capacity = 2` in the `:observer_output` receipts (538-551), the open `docs/todo.md` row (line 28) says so. The receipt is recorded per `execute!` on every rank before the preflight refusals (documented owner item U4-3 of 2026-10-13). Measured values: `(artifact = path, append = false, record_turn_modulation = true)` for the recording runs, `record_turn_modulation = false` for `record=0`, `append = true` twice for the split run.

**Neighbours.** `_warn_duplicate_turn_modulation_streams((line_tuple1..., line_tuple2...))` spans both lines (`dupwarn.log`): distinct ids -> 0 warnings; the same `rng_id` on beam 1's and beam 2's cavity -> 1 warning naming `rng_ids = [0x0b]`; the same id on two slots of ONE cavity -> 0 (slot-independent by design); equal `TurnTable` digests on both beams -> 1 warning naming both sites; distinct digests -> 0; beam 1's RF cavity sharing an id with beam 2's crab -> 1. `configuration_report` output entry: `:resolved`, "rewriting|continuing the run artifact at <path>, recording the turn-modulation series" (recording runs), no "recording" clause with the switch off. Call sites: `_execute_strong_strong_segment_pair!`, `_execute_strong_strong_segment!`, `_execute_strong_strong_turns!`, `_execute_strong_strong_task!` are called from interface.jl only (grep over src/, test/, validation/, profiling/, ext/), so the arity change left no stale caller. The ledger stamp and `_tm_*` calls run on non-root ranks too, harmlessly (`art.current_turn = 63` on every rank after the run, no file, sinks `nothing`).

## Unchecked, with the reason

- The PIC, Gaussian-PIC and spectral solvers' turn loops with the recorder: the recorder sits outside the collision and the loop is the same, so the soft-Gaussian run covers the region; the solvers' own backend consistency is other units' and the suite's.
- A multi-GPU (`device=N`) run: one device on this machine.
- `record_turn_times=true` interplay (the `_tm_end_turn!` runs before the per-turn `CUDA.synchronize`): host-side only, no correctness path; not run.
- A hard kill DURING the window between a flush turn's luminosity flush and its series flush (the one case where the ledger exceeds the series rows): too narrow to time from an action; the window is stated from the code, and the stop40/hard45 measurements bracket it.
- The full gate was not run by this unit (read-only audit; nothing changed).
