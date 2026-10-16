# S5 — seam pass: producer-consumer protocol pairs (epochs, windows, caches, seeds)

Comprehensive audit of the crab-cavity noise campaign, reading unit S5.
Repository: Octopus, main checkout `/cfs/ad/dxu/Library/Julia/Octopus` at
`3126908` (tree unchanged by this unit; `git status` shows only the auditor's
untracked `docs/history/audit_crab_cavity_noise_neighbours_2026_10_16.md`).
Julia 1.12, `--project=.` `--threads=4`, CUDA active on the box (one RTX 4500
Ada); every probe below ran on CPU threads unless stated. HDF5 library 2.1.1
(HDF5.jl 0.17), `HDF5_USE_FILE_LOCKING` unset, `result/` on NFS.
Scratch (probe scripts, their `.log`s and `.h5` outputs):
`result/audit_crab_noise_2026_10_16/S5/`. Every claim below is a LEAD for the
auditor, not a finding.

## Region and provenance

Read line by line (the seam participants):

- `src/tasks/RunArtifact.jl` 1-1439 (whole file: recorder, artifact, prepare,
  provenance writer, series, flushes, finalize, probe binding, readers).
- `src/tasks/Tasks.jl` 380-470 (the two sharing warnings), 625-1236 (`execute!`,
  the crash path, `_execute_tracking_task!`, both turn loops, finalize order),
  1290-1402 (`_runtime_entries`, `_ensure_loss_record!`, `_bind_apertures`).
- `src/tasks/strongstrong/interface.jl` 2325-2350, 2455-2730, 2500-2600,
  2820-2900, 3120-3150 (the task struct, `execute!`, preflight, receipts,
  prepare/finalize, the turn loop, the block cache).
- `src/elements/turn_modulated.jl` 225-300, 380-540, 690-845, 1055-1200,
  1415-1671 (TurnTable, digest, spectral synthesis, `SpectralNoise`,
  `_resolve_turn_rule`, window check, the walks, the receipt builders).
- `src/elements/crab_cavity.jl` 350-461, `src/elements/rf_cavity.jl` 500-560
  (`_turn_modulation_wrap`), `src/elements/aperture.jl` 130-150,
  `src/beam/*` (`struct Phase6DRep`, line 45), `src/math/counter_rng.jl` 20-60,
  `src/knowledge/Knowledge.jl` 140-205, `src/elements/beam_line.jl` 70-90,
  `src/tasks/BeamObservers.jl` 128-175, 208-227, 365-395, `src/policies/Policies.jl`
  (the `_mp_is_root` sites), `ext/OctopusMPIExt.jl` (grep only).
- `test/runtests.jl` 15686-15806 (the example testset and its cleanup),
  16705-16800 and 16900-17010 (the recorder testset), 20155-20260 (the harness
  MPI testset), 11395-11560 (the SpectralNoise tests); `test/turn_modulation_probe.jl`
  1-80; `test/examples/crab_cavity_noise.jl` 190-235, 400-470, 590-640,
  1100-1200; `examples/crab_cavity_noise.jl` 105-185, 290-345, 560-720.
- Reference: `docs/design/run_artifact.md` (whole), `turn_modulation.md` 4.4-4.5,
  5.6, `spectral_turn_table.md` 85-310 (D1-D11 and the dated remarks),
  `turn_modulation_record.md` sections 4-6 and 9, `docs/todo.md` rows 30-31.

Executed (scripts in the scratch directory, logs beside them):
`p1_window.jl`, `p1f_ss.jl`, `p2_seed.jl`, `p2d_mech.jl`, `p2e_mech2.jl`,
`p2f_lossreset.jl`, `p3_append.jl`, `p3b_open_handles.jl` (+ `hold_open.jl`,
`race_writer.jl`), `p3c_labels.jl`, `p3d_phantom.jl`, `p4_capacity.jl`,
`p4b_kill.jl` (invalid: killed the child during JIT before the file existed;
superseded), `p4c_kill.jl` (+ `kill_child.jl`), `p5_warnings.jl`; the clean
example `examples/crab_cavity_noise.jl` once at its defaults (`p6_example.log`;
its one output file and the seed directory it created were removed afterwards);
the harness on two MPICH ranks with a per-rank `OCTOPUS_RESULT_DIR`
(`p7_rank_wrapper.sh`, `p7_mpi.log`, `p7/`).

Each probe's command is `julia --project=/cfs/ad/dxu/Library/Julia/Octopus
--threads=4 result/audit_crab_noise_2026_10_16/S5/<script>.jl`; the quoted
numbers are what the logs hold.

## Leads

### LEAD S5-1 [high, confidence high] src/tasks/Tasks.jl:1348
Claim: `_ensure_loss_record!` identifies the beam that owns the loss record through `WeakRef(rep)` on the IMMUTABLE `Phase6DRep`, so any garbage collection between two `execute!` calls on the same beam clears the owner and the next call reallocates the record — zeroing the cumulative loss counts, reporting the earlier losses as "unattributed" with a false warning, writing a wrong `/losses` group, and (the seam this unit was briefed on) recompiling the line so every `SpectralNoise` table is re-synthesised under whatever global seed is then in force, against the documented "not the table until the next compile".
Mechanism: `Phase6DRep` is a `struct` (src/beam, line 45: immutable, six array fields). `execute!(task, rep)` and `execute!(task, beam)` (which passes `beam.rep`) hand the value to `_ensure_loss_record!` re-boxed per call; `task.loss_owner[] = WeakRef(rep)` (Tasks.jl:1361) weakly references THAT box, which nothing else holds, so a GC clears it while the value stays alive (demonstrated in plain Julia: `mk(x) = WeakRef(x); function g(); s = S([1]); w = mk(s); GC.gc(true); (w.value === s, w.value) end` → `(false, nothing)` for an immutable `S`, `(true, ...)` for a mutable one). `fits` (Tasks.jl:1348) then fails on `task.loss_owner[].value === rep`, a fresh `LossRecord` (counts zero, empty slots) replaces the cumulative one, and `_runtime_entries` (Tasks.jl:1310) sees `crecord !== record`, recompiles, empties `plan_cache` and re-runs `_resolve_turn_rule` under `global_rng_seed()`. In a run chunked over many `execute!` calls a GC is certain, so the loss accounting of every aperture line is wrong in practice and the suite's two-window tests pass only because no GC fell between their windows. The strong-strong task is NOT reached by this mechanism (its block cache keys on the two epochs only, interface.jl:3134-3138).
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S5/p2f_lossreset.jl` → `[artifact, GC between] record reallocated: true; counts after w1 = Int32[1]; after w2 = Int32[1]; summary w2 (dead, logged, unattributed) = (2, 1, 1); warnings w2: ["particles were lost with no aperture responsible..."]; /losses after w2: aperture_counts=[1] rows=1 summary=(dead=2, logged=1, unattributed=1)` against `[artifact, no GC] counts after w2 = Int32[2]; summary w2 = (2, 2, 0); warnings w2: Any[]; /losses aperture_counts=[2] rows=2`. The seam-2 symptom: `p2e_mech2.jl` → `[no probe, record on, GC between] ... GC forced: owner=CLEARED; fits terms before w2: (owner_is_rep = false, counts_len = true, matches_rep = true, slots_vs_want = true, slot_width = true) ... => RECOMPILED` (the table's canonical name reads `seed=22` after a `set_global_rng!(seed=22)` with no knob, spec or beam change; `seed=21` in the no-GC variant). First seen without a forced GC in `p2d_mech.jl` `[aperture, artifact]` (the allocation of the recording run triggered one).

### LEAD S5-2 [medium, confidence high] src/tasks/RunArtifact.jl:316
Claim: Across processes the artifact has no exclusion at all: a second process opens a path another process holds (for reading or writing) with `append=false` or `append=true` and succeeds, two processes writing one path concurrently both finish with one run's output silently gone, and a stale writer handle's close corrupts the file; HDF5's advisory file locking is inert on this NFS, and the only guard (`_register_observer_path!`, BeamObservers.jl:208) is an in-process `Dict`.
Mechanism: `prepare_run_artifact!` does `HDF5.h5open(art.path, fresh ? "w" : "r+")` with no lock file and no probe of other openers; the in-process registry cannot see another process; `h5open(path, "w")` succeeded in a second process while a first held `"r+"` (p3c). With the holder's `"r+"` handle closed AFTER the other process had truncated and rewritten the file, the holder's cached metadata lands on the new file.
Repro: `p3b_open_handles.jl` → `cross-process held 'r+', append=false: SUCCEEDED (ledger start_turn=[0] turns=[2] ...); cross-process held 'r+', append=true: SUCCEEDED (ledger start_turn=[0, 0] ...); file afterwards UNREADABLE: HDF5.API.H5Error: Error opening object /turn_modulation/2 ... len not positive after adjustment for EOA`; `3g two processes writing ONE path ... writer 1 finished; writer 2 finished; race file: ledger start_turn=[0] turns=[400] current_turn=[399]; moments rows: 400` (one writer's 400 rows gone, neither writer errored). `p3c_labels.jl` → `second process h5open(path, "w") while another holds "r+": SUCCEEDED (no effective lock)`. The in-process case IS refused (p3b 3e: `unable to truncate a file which is already open`, `file is already open for read-only`). Related, not identical, to the open todo row on the concurrent-suite cleanup race (that row is about unlinking an open file; this is about two writers).

### LEAD S5-3 [low, confidence high] src/elements/turn_modulated.jl:1497
Claim: Both sharing checks run on the SPEC layer before resolution, so a `SpectralNoise(rng_id = k)` on one cavity and an offline `spectral_turn_table(seed = <the global seed>, rng_id = k, slot = <that slot>)` on another resolve to IDENTICAL tables (correlation 1.0, equal digests in the receipt and in the artifact) with no warning at construction and none at `execute!`.
Mechanism: `_collect_turn_modulation_ids!` reads `rng_id` fields (a `TurnTable` has none) and `_collect_turn_tables!` reads `digest` fields (a `SpectralNoise` has none until `_resolve_turn_rule` runs at compile); nothing re-checks digests over the compiled `runtime_elems`, where both are `TurnTable`s. D11's "the equal-digest warning being its sharing check" (for the factory) and "the task constructor's shared-id warning" (for the rule) each cover one side; the cross product has neither. A post-compile digest walk in `execute!` would close it.
Repro: `p5_warnings.jl` → `5d ... warnings at construction: Any[]; resolved digests equal (identical offsets, fully correlated): true; correlation = 1.0; execute! warnings: Any[]; artifact digests: UInt64[0x1a01aea63f8a2dbb, 0x1a01aea63f8a2dbb]; series equal: true`.

### LEAD S5-4 [low, confidence high] src/tasks/RunArtifact.jl:451
Claim: Nothing in the artifact, and no receipt other than the table rule's canonical `name`, records the global RNG seed or method, so after a `set_global_rng!` between windows the file's only seed mention (the table's `seed=2`) contradicts the seed that drew the same slot group's white columns (3), and nothing in the file can say so; a white/pink `series` cannot be regenerated or attributed from the file alone.
Mechanism: `_turn_modulation_entries` carries `rng_id`, `digest`, `name`, `length` per slot and the writer stores exactly those plus the nominals; `global_rng_seed()`/`global_rng_method()` are read by `_turn_offset` through the context on every turn and recorded nowhere (grep: no `global_rng_seed()` call in `src/tasks/`, `src/policies/`, `src/knobs/`). The table ignores the method as well (Philox hard-coded, D4), so a `method = :splitmix` run's white columns and its table columns answer to different generators with nothing in the name saying which.
Repro: `p2_seed.jl` → `white column of slot 2 == seed-3 replay: true; == seed-2 replay: false; table column of slot 2 == seed-2 table[5:8]: true; attributes mentioning 'seed' (name or string value): String[]; receipts whose values mention 'seed' or 'rng': [:turn_modulation]; ... recompile under :splitmix: name ... seed=3 ...; digest == philox seed-3 table: true`.

### LEAD S5-5 [low, confidence high] src/tasks/BeamObservers.jl:215
Claim: The documented restart workflow — a new task continuing an `append=true` artifact while the previous task's artifact object is still live in the process — emits the U7-10 warning "a second live observer is initializing an output path ... this initialization truncates the first observer's rows ... Give each observer its own path", which is false for `append=true` (nothing is truncated beyond the replay rule) and speaks of observers.
Mechanism: `prepare_run_artifact!` registers the path by artifact identity on its first prepare (RunArtifact.jl:318) and the registry warns on any second live registrant regardless of `append`; the same task continuing is silent.
Repro: `p1_window.jl` section 1c (the warning header in `p1_window.log`) and `p3_append.jl` → `Z (third writer, append=true, a NEW task so first_turn = 0) warnings: ["a second live observer is initializing an output path ... truncat"]; Z continuing: warnings = Any[]`.

### LEAD S5-6 [low, confidence high] src/tasks/Tasks.jl:431 (out of hypothesis: pre-existing wording, measured on white too)
Claim: The shared-`rng_id` warning states "their per-turn draws are identical (fully correlated noise)", but the draws coincide only when the SLOTS coincide: the same id on different slots of two elements gives independent draws (white) or independent tables (spectral), and two spectral rules with one id but different `turns` give different tables; the message over-claims in all three cases.
Mechanism: the counter-RNG key and the spectral key both carry the slot (`octopus_normal(seed, method, turn, rng_id, slot, ...)`, `octopus_uniform01(seed, RNG_PHILOX, slot, rng_id, k, 1)`); the collector compares ids per element without the slot.
Repro: `p5_warnings.jl` → `5f ... warnings: ["... share an rng_id ..."]; resolved digests equal: false; correlation = -0.0092`; `5g ... white draws identical across the two elements: false; correlation = 0.0136; same slot (1 and 1): identical: true`; `5e ... resolved digests equal: false (lengths 64, 128)`.

### LEAD S5-7 [low, confidence high] src/tasks/RunArtifact.jl:340
Claim: `append=true` onto an existing file that is not HDF5 surfaces HDF5's own "unable to determine if ... is accessible in the HDF5 format (file may not exist)" rather than the by-name refusal written for it ("is not a run artifact (no /luminosity group). Use a new path."), which is unreachable because `h5open(path, "r+")` throws first.
Mechanism: the `haskey(file, "luminosity")` check sits after the open; a zero-byte file is treated as fresh by design (`filesize(art.path) == 0`), measured.
Repro: `p3_append.jl` → `non-artifact file: unable to determine if .../p3_notart.h5 is accessible in the HDF5 format (file may not exist); zero-byte file with append=true: treated as fresh, ledger start_turn=[0] turns=[1]`.

### Confirmation of an open todo row (no new lead)
`p3d_phantom.jl` → a direct `prepare_run_artifact!(art, String[], 2, 2; turn_modulation=prov)` with default empty columns is refused by name after the ledger append: `ledger rows: 2 (phantom row); provenance slots: [1]`. Unreachable through `execute!`, as the row says; still present at `3126908`.

## Documented seams measured, no lead

- Checkpoint restore under `append=true` (`p1_window.jl` 1c): the `series` datasets are never replayed, so slot 1 (turns 0-4) and slot 4 (turns 4-6) both hold turns 4, 5, 6 (`series rows per absolute turn across slots, where > 1: [(4, 2), (5, 2), (6, 2)]`) while `/moments/m` was replayed to one row per turn (`[0, 1, 2, 3, 4, 5, 6]`). As `run_artifact.md` states ("chunked and repositioned runs stack one dataset per execution slot"); a reader joining series to probe rows by turn must choose a slot.
- A refused strong-strong window still records the `:strong_strong_diagnostics` and `:strong_strong_output` receipts (`p1f_ss.jl` 1f-ii) — the U4-3 owner item named in the code comment at interface.jl:2475-2487.
- Under MPI the non-root rank creates the seed DIRECTORY (`mkpath` on every rank, harness line 1037) and writes no file: `p7/rank_1/123456789/` exists and is empty; `p7/rank_0/123456789/crab_noise_white_x1.h5` is the one artifact (`p7_mpi.log`: `mpi_rank = 0 of 2`, `mpi_rank = 1 of 2`, `rank 1 of 2: shard tracked; rank 0 holds the artifact`, exit 0).
- Hard kill (`p4c_kill.jl`, three trials, killed 8 s after the file appeared): the file is readable, `series rows=512` (a multiple of 64 = `capacity`), `moments rows=512`, `moments cursor=511`, `ledger current_turn=[-1]` — the `TrackingTask` writes `current_turn` only at finalize, as `run_artifact.md` says ("the rows decide"); the reader warns `holds 512 recorded turn(s) of the 100000`.

## Clean (what was compared, what was measured)

Seam 1, the TurnTable window check: `p1_window.jl`, `p1f_ss.jl`. A 12-entry table on `strength_noise[2]`: windows 0-4 and 5-9 on one task give receipts `(0, 5)`, `(5, 5)`, `task.next_turn = 10`, ledger `start_turn=[0, 5]`, series attributes `first_turn/turns` equal to the receipts, slot-2 series `== table[6:10]`. The third window 10-12 is refused by name before anything: `ledger rows before/after refusal: 2/2; task.next_turn = 10; artifact file handle open: false`; then 10-11 runs (`== table[11:12]`) and turn 12 is refused. The second window's `first_turn` is the task's `next_turn` counter (not the ledger, not the caller). A restore `start_turn=4, turns=3` on a new task reads entries 5-7 (`== table[5:7]`), `t2.next_turn = 7`; an overrunning restore is refused with no row and `next_turn` still 0. `append=false` recreates the file with the continued `first_turn` (`start_turn=[4]`). Strong-strong: the same table on beam 1 refuses 4-7 with `in beam 1's line: ...`, `ledger rows 1/1`, `next_turn = 4`, handle closed; the 4-5 window records `== table[5:6]`; capacity 2 over 4 turns gives 4 luminosity rows, 4 series rows per beam, `current_turn=[3]`.

Seam 2, SpectralNoise resolution (apart from S5-1 and S5-4): `p2_seed.jl`. The table takes the seed in force at the FIRST `execute!` (`set_global_rng!(seed=2)` after construction: name `seed=2`, digest equals `spectral_turn_table(...; seed=2, rng_id=11, slot=1)`, not seed 1). `set_global_rng!(seed=3)` between windows with no recompile: `digest unchanged: true`, the white column equals the seed-3 replay bitwise and not the seed-2 one, the table column equals the seed-2 table's entries 5-8. A spec-epoch bump (`c.phase = (0.1, 0.2)`) recompiles: window 3's name reads `seed=3`, `artifact slot3 digest == seed-3: true; slot3 series == seed-3 table[9:12]: true; slot2 digest still seed-2: true`, the recorder's column set unchanged across the three slots. The plan cache is emptied at every recompile (read: Tasks.jl:1321, interface.jl:3145). The loss-record identity trigger exists as documented (`p2d_mech.jl`: a second rep recompiles under the new seed) — its failure mode is S5-1.

Seam 3, append (apart from S5-2, S5-5, S5-7): `p3_append.jl`, `p3c_labels.jl`. Four `append=true` runs with (cA, recording off), (cB, on), (cA + cB, on), (unmodulated, on) stack as slots 1-3 with element counts 1, 1, 2 and `series` `nothing`/3/3 rows, the unmodulated run writing no slot group; ledger `start_turn=[0, 3, 6, 9]`. A luminosity-label mismatch is refused by name with no ledger row and the handle closed; a stranger `/turn_modulation/2` group is refused before the row (`ledger rows: 1`), and the reader refuses that file as torn by name. Two live tasks on one path in one process: the second is warned (U7-10) and `append=false` destroys the first's rows (ledger `[0]`), `append=true` continues (ledger `[0, 0]`, probe rows replayed, the first slot's series retained).

Seam 4, capacity and flushes: `p4_capacity.jl`, `p4c_kill.jl`. At capacity 8: 5, 8, 9, 16 turns write exactly 5, 8, 9, 16 series rows and moment rows, `current_turn` 4, 7, 8, 15. Capacity 1 and 1000 give series bitwise equal to capacity 8. A caught exception at turn 11 of 16 leaves 11 complete series and moment rows (the catch path's `finalize_run_artifact!` flushes complete rows — better than the documented "through the last flush"), ledger `current_turn=[10]`, `next_turn` not advanced, handle closed, reader warning `holds 11 recorded turn(s) of the 16`. `finalize_run_artifact!` twice is a no-op. A retry on `append=true` from turn 0 appends slot 2 with 16 rows beside the retained 11-row slot and replays the probe rows to one per turn. The hard-kill result is above.

Seam 5, the warnings (apart from S5-3, S5-6): `p5_warnings.jl`. One explicit id on two cavities warns at construction and resolves to equal digests (5a); an offline pair warns on the digest (5b); different ids with the same seed/band/spectrum do not warn, digests differ, correlation 0.31 (bound `4/sqrt(2K)` = 0.53 at K = 29 flat bins) (5c); one `SpectralNoise` object on two cavities warns (5h); the strong-strong constructor repeats all three answers over both lines (5i).

Seam 6, the example testset's cleanup (read; one example run): the testset (`test/runtests.jl` 15756-15788) removes exactly the files each run printed as `artifact = <path>` and only when the path is `result/<digits>/<file>` directly under the repository's `result/`; removes a seed directory it created once empty; asserts `leftover == String[]` (new files under seed directories that no run recorded) and that no new seed directory remains. It asserts nothing about files outside that layout. The example at its defaults (`p6_example.log`: `CUDAExecutionPolicy (auto)`, 2 turns, 10000 macroparticles) created `result/123456789/` and wrote exactly one file, `crab_noise_white_x1.h5` (133168 bytes), as its header's OUTPUTS line documents (`result/<seed>/<case_name>.h5`, lines 111-112). `result/` is NFS (`stat -f`), so the todo row's silly-rename mechanism applies. A per-process directory would change that documented path for every example (and the crab-noise, weak-strong and strong-strong headers), so it needs the documented switch the row proposes (the harnesses' `OCTOPUS_RESULT_DIR` precedent, `result_dir = get(ENV, "OCTOPUS_RESULT_DIR", ...)` at harness line 606).

Seam 7, `OCTOPUS_RESULT_DIR` under MPI: measured above — rank 0 writes the one file into its directory; rank 1's directory holds no file.

## Unchecked, with the reason

- CUDA arms of every seam: all probes ran on CPU threads (the example's `:auto` run was the one CUDA execution); the recorder is host-side on CUDA by design, so the seams are not expected to differ, but this unit did not measure it.
- Apertures in strong-strong lines and the strong-strong task's loss accounting across windows: its block cache has no loss-record key (read), so S5-1's mechanism does not apply there; not probed.
- A weak-strong line (a strong beam inside a `TrackingTask`) for the luminosity-flush/recorder-flush/ledger interplay: measured only in the strong-strong task (`p1f_ss.jl`).
- The two-concurrent-suites race itself was not re-run (the todo row records it; this unit read the cleanup and ran the example once).
- `HDF5.API.h5p_get_file_locking` could not be queried (`H5P_FILE_ACCESS_DEFAULT` not exported by HDF5.jl's API); the locking behaviour was measured instead (S5-2).
- `p4b_kill.jl`'s two trials are invalid (the child was killed during JIT, before `prepare_run_artifact!`, so no file existed); `p4c_kill.jl` supersedes them.
