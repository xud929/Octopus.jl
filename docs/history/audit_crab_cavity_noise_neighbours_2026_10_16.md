# Targeted neighbour audit: the crab and RF cavity noise campaign (2026-10-16)

> **Status: Phase 0 declared 2026-10-16, reading units and seam passes in
> flight; findings, coverage ledger, test report and change log are filled
> as the units report and the auditor reproduces their leads. A scoped pass
> under `docs/comprehensive_audit.md` ("The targeted neighbour audit"), not
> a full pass.** Owner request 2026-10-16: "fan-out subagents to do the
> neighbour audit for crab cavity/RF cavity noises, following the protocol
> in comprehensive_audit.md".

## 1 Declared scope (Phase 0)

**Subject.** The campaign that followed the last neighbour audit (the
39-lead audit that closed turn-modulation stages 3 and 4, pushed as
6995151 on 2026-10-13): 17 commits, `6995151..3126908`, 30 files,
+14814/-284 lines, landed between 2026-10-14 and 2026-10-16 and recorded in
`crab_cavity_noise_validation_2026_10_14.md`,
`crab_cavity_noise_mpi_benchmark_2026_10_14.md`,
`crab_cavity_noise_relative_strength_2026_10_15.md`,
`turn_modulation_record_2026_10_15.md` and
`spectral_turn_table_2026_10_16.md`. Each batch had a diff-scoped review;
none had the neighbour re-walk. The audit reads HEAD = 3126908 in the main
checkout; any fix lands in the worktree `.claude/worktrees/audit-A`
(branch `crab-noise-audit`).

**Regions, depth and reader.** Line by line, one reading unit each,
sub-agents reading, the auditor reproducing every lead before it becomes a
finding:

| unit | region | hypothesis (the campaign's own defect classes) |
|---|---|---|
| U1 | `src/elements/turn_modulated.jl` | a keyed-RNG consumer omitting a dimension; constant-propagation allocation hidden by homogeneous pins; hand-copied lists; content-keyed warnings; docstring drift |
| U2 | `src/elements/crab_cavity.jl`, `src/elements/rf_cavity.jl` | twin drift between the two cavities (relative semantics, resolution sites, metadata, help); CUDA-reachable branches with interpolated messages |
| U3 | `src/tasks/Tasks.jl` | sink plumbing and turn alignment in every loop path; the fast-loop predicate; the warnings' per-element semantics; the runtime cache identity against the spectral re-synthesis |
| U4 | `src/tasks/strongstrong/interface.jl` (executed) | per-beam sinks and the ledger stamp order; rank 0 under MPI; the output receipt's consumers; the strong-strong recorder on CUDA, never run before this audit |
| U5 | `src/tasks/RunArtifact.jl` (executed) | protocol pairs: append and restart with recording, capacity boundaries, pre-change and torn files, the toc, the phantom ledger row |
| U6 | the campaign's testsets in `test/runtests.jl`, `test/turn_modulation_probe.jl` | test quality: circular checks, pins that cannot fail, silent CUDA skips, pinned digests, unstated tolerance envelopes |
| U7 | `examples/crab_cavity_noise.jl`, `test/examples/crab_cavity_noise.jl`, `profiling/crab_cavity_noise_backends.jl`, `validation/crab_cavity_noise_response.jl` (executed) | a configuration set but not read; the CRAB-NOISE line's parsers; the stream-id schemes; header claims against code |
| U8 | the campaign's documents | superseded paragraphs left standing; status drift across records, notes, index and todo; the traceability matrix |
| S1 | the counter-RNG key space (executed) | every consumer enumerated; disjointness or documented sharing shown by measurement |
| S2 | the CPU/CUDA twin and thread count for the recorder and the spectral rule (executed) | host-side ordering, device conversion of large tables, thread-count invariance, device compilability |
| S3 | the walkers over the line (after the unit reads) | a walker that forgets a wrapper: recorder columns, provenance, ids and tables disagreeing |
| S4 | declared schemas and metadata against their consumers | a declared consumer that never carries the value; derived against hand-written lists |
| S5 | producer-consumer protocol pairs | the table window check against a second `execute!`; the resolution epoch against the global seed; append mode with recording |

**Not covered, and why.** The crab cavity kick kernel itself, the
beam-beam solvers, the Twiss analysis and the PIC family: unchanged by the
campaign and audited by the full passes; the theory note's physics
derivations beyond their consistency with the shipped semantics (section
4.5's vertical response stays an owner item). Phases 1-3 are taken from
the campaign's design notes and records rather than re-derived; Phase 5
(mathematical verification) covers only the spectral synthesis
normalisation and the relative strength semantics, the two equations the
campaign introduced.

**Phase 8 baseline.** The two-arm gate of c3c6c2c (336 testsets, 150700
assertions per arm, CUDA active, arms sequential) and CI runs 455-458 are
the "what ran" record at HEAD; the audit re-runs targeted testsets for its
reproductions and, after any fix, the gate in the worktree.

**Phase 13 baseline fingerprint.** Captured before the first modification:
the harness's `CRAB-NOISE` lines for every rule at 2 turns on CPU (bitwise
fields), the one-particle probe's recorded series digests, and the
validation noise part's printed numbers; stored under
`result/audit_crab_noise_2026_10_16/fingerprint/` and quoted here when a
fix lands.

**Deliverables.** This report; the unit reports archived beside it under
`audit_crab_cavity_noise_neighbours_2026_10_16_unit_reports/`; the
`docs/README.md` index entry; one `docs/todo.md` row per confirmed finding
not fixed in the audit, and the row carrying the open-queue pointer.

## 2 Coverage ledger

Every number below is taken from the unit report named in the row (the reports are archived verbatim beside this report in `audit_crab_cavity_noise_neighbours_2026_10_16_unit_reports/`). Lead totals are `grep -c '^### LEAD'` on each report; the severity split is the first token of each lead header's bracket. "Not stated" marks what a report does not say. Line numbers in the "Files read" column are the ranges the report itself names; a file count in parentheses is the report's own line count for that file.

| Unit | Assigned region | Files read (paths, with line counts if the report states them) | Probes (count and directory) | Leads (total, split by severity) | Not read / not covered (the report's own statement) |
|---|---|---|---|---|---|
| U1 | `src/elements/turn_modulated.jl` | `src/elements/turn_modulated.jl` lines 1-1671, every line (1671 lines); seams read for the region's promises, not audited: `src/math/counter_rng.jl` 1-300, `src/elements/crab_cavity.jl` 46-75 and 300-470, `src/elements/rf_cavity.jl` 269-333 and 470-600, `src/tasks/RunArtifact.jl` 40-62 and 553-600, `src/tasks/Tasks.jl` (eleven named ranges), `src/track/Track.jl` 1-33, `src/beam/Beam.jl` 128-167, `src/elements/beam_line.jl` 630-660 and 741, `test/runtests.jl` fixtures (six ranges), `docs/design/spectral_turn_table.md` 108-140, 183-196, 265-310; the campaign diff (987 lines) saved as `U1/campaign_diff.patch` | `U1/`: 12 probe scripts (probe_alloc, probe_alloc2, probe_hetero, probe_confirm, probe_composite, probe_bigN, probe_slope at 1 and 4 threads, probe_cost, probe_window, probe_slots, probe_spectral, probe_parity) plus the shared helper `alloc_helpers.jl`, a log beside each; no GPU used | 8: 1 high, 2 medium, 5 low | "identical on every backend" not measured on CUDA (no GPU in this session); the pre-F1 `slot = 0` bitwise claim uncheckable (no pre-F1 commit); the SpectralNoise recompile triggers and the shared-id warning's scope across two beams (Tasks.jl, outside the region); U1-3's mechanism inside the general loop (outside the region); the recorder's own protocol exercised only through hand-built sinks, not through the artifact |
| U2 | `src/elements/crab_cavity.jl` and `src/elements/rf_cavity.jl` | both in full, every line: `src/elements/crab_cavity.jl` (461 lines), `src/elements/rf_cavity.jl` (833 lines); the campaign diff of both (151 insertions, 54 deletions); seams read as context only: `src/elements/turn_modulated.jl` (four ranges), `src/knowledge/Knowledge.jl` 660-690 and 1360-1405, `src/track/phase6d_track.jl` 190-245 and 270-330, `src/track/longitudinal.jl` (three ranges), `src/elements/lattice_magnets.jl` 118-135, `src/tasks/RunArtifact.jl` (grep), `src/contracts/Contracts.jl` 2895-2909; `test/runtests.jl` (five ranges); docs: theory 3.2, `turn_modulation.md` s10, `turn_modulation_record.md` D3-D8, the relative-strength record in full, `public_api.md` 260-275 and 340-352, todo row 21 | `U2/`: 4 scripts (probe_u2 [1086 pass, 6 fail, each explained], probe_u2_device_throw, probe_u2_attrib, probe_u2_slots) with logs; CUDA active (RTX 4500 Ada) | 4: 3 low, 1 info | the internals the region only calls (`_turn_offset` keying, `_spectral_table` synthesis, the recorder's HDF5 layout, `_survey_rebind(::TurnModulated)`, the device `adapt_structure` chain: other units' regions); ForwardDiff dual derivatives through `_realize_draws` not measured; the suite itself not run; `OffsetArray` inputs to `_rule_tuple`/`_harmonic_tuple` not exercised |
| U3 | `src/tasks/Tasks.jl` | `src/tasks/Tasks.jl` in full, 1978 lines, line by line (five chunks, no skipping), with emphasis on the campaign diff (+78/-16); seams read, not audited: `src/tasks/RunArtifact.jl`, `src/elements/turn_modulated.jl`, `src/elements/crab_cavity.jl` (named functions), `src/tasks/strongstrong/interface.jl` (2400, 2584-2592, 2639-2644, 2669-2672, 2832-2882, 3109-3122), `src/knobs/Knobs.jl`, `src/knowledge/Knowledge.jl`, `src/elements/beam_line.jl`, `src/math/counter_rng.jl`, `src/track/Track.jl`; docs: `turn_modulation.md` 4.4-4.5, `turn_modulation_record.md` D1-D10 and s9, `spectral_turn_table.md` s3, the 2026-10-15 record s4 | `U3/`: 6 scripts (p1_alignment, p2_warnings, p3_recompile, p4_crash, p5_seed, p6_receipt_before_refusal) plus the prelude `u3_common.jl`, matching logs and `*_<pid>.h5` artifacts; CPU threads plus one CUDA arm | 6: 5 low, 1 low-medium | multi-rank execution (no `mpiexec` launched; read only); the strong-strong loop body beyond call signatures and sink forwarding (another unit's region); stateful rules (none shipped); Float32 lines, `GaussianStrongBeam` in the isolated/luminous paths, the `:fused`-on-CUDA refusal (read only); the HDF5 extent arithmetic beyond capacity 2 and 64; the suite's gate not run |
| U4 | the strong-strong turn loop and the turn-modulation recorder: `src/tasks/strongstrong/interface.jl`, the campaign diff 6995151..3126908 (62 insertions, 13 deletions) and its neighbours | `src/tasks/strongstrong/interface.jl`, every line of the named ranges 2063-2075, 2346-2371, 2383-2420, 2463-2500, 2594-2729, 2797-2890, 3076-3122, 3245-3251 (whole-file line count not stated); seams read, not audited: `src/tasks/RunArtifact.jl` (recorder, flushes, finalize, readers), `src/tasks/Tasks.jl` 1828-1882 and 426-470, `src/elements/turn_modulated.jl` 960-1030 and 1340-1415, `src/elements/crab_cavity.jl` 305-355, `src/elements/rf_cavity.jl` 470-505, `src/policies/Policies.jl` 500-545 and 924-990; docs: `turn_modulation_record.md` s8-9, `run_artifact.md`, `current_runtime.md`, `testing_lanes.md` s3, `multi_process_policy.md` 1100-1121, the 2026-10-15 record 188-191 and 544-546; `test/runtests.jl` 16745-17330 and 19334-19680 | `U4/`: 6 scripts (u4_fixture, u4_run, u4_compare, u4_compare_shards, u4_read_torn, u4_dupwarn) driving about 20 runs (cpu64, cuda64, cpu64t2, cpu64c24, cpu64b1, cpu64b2, cpu64post, cuda64post, cpu64split, cpu64off, cuda64off, cpu1, stop40, hard45, hard45lum, mpi1, mpi2, mpi4); the directory holds 92 files, 15 MB; CUDA active; MPICH `mpiexec` | 2: 2 low | the PIC, Gaussian-PIC and spectral solvers' loops with the recorder (same loop; the solvers are other units' and the suite's); a multi-GPU (`device=N`) run (one device); the `record_turn_times=true` interplay not run; a hard kill between a flush turn's luminosity flush and its series flush (stated from the code only); the full gate not run |
| U5 | `src/tasks/RunArtifact.jl` | `src/tasks/RunArtifact.jl` in full, every line (1439 lines), campaign diff +487/-34; context, not audited: `src/tasks/Tasks.jl` 1030-1135, `src/tasks/strongstrong/interface.jl` 2596-2730, 2820-2890 and 2063-2075, `src/elements/turn_modulated.jl` 1554-1630, the two `:observer_output` receipt sites, `test/runtests.jl` 16533-17316, `docs/design/run_artifact.md`, `turn_modulation_record.md` s4-6 and 9, the run-artifact paragraphs of `public_api.md`, two `docs/todo.md` rows | `U5/`: 9 probe scripts (probe_h1_append, probe_h2_capacity, probe_h3_miscount, probe_h4_ledger with `h4_child.jl`, probe_h5_compat, probe_h6_phantom, probe_h7_schema, probe_h8_hdf5, probe_followup) plus `probe_common.jl`, logs `probe_*.log`; CPU threads only, one process (no `mpiexec`), no CUDA run | 10: 2 medium, 7 low, 1 info | the MPI posture (recorder on rank 0 only; no `mpiexec` run, read only); the CUDA arm (no device run); a kill landing inside an HDF5 write (one `kill -9` sample only); the `_realize_draws` draw order against `columns[k].active` (cross-file contract, pinned in turn_modulated.jl); the fast loop's exclusion from recording (read only); a real `h5ls` while a writer holds the file (a second Julia process stood in) |
| U6 | Phase 9 test quality: the campaign's testsets in `test/runtests.jl` and `test/turn_modulation_probe.jl` | the diff 6995151..3126908 of `test/runtests.jl` (2133 patch lines, saved as `U6/runtests_diff.patch`), every line, plus the current text of the 12 testsets named in the brief by range (8052-8268, 9940-10622, 10740-11271, 11272-11576, 11794-12210, 15690-15805, 16533-16743, 16745-17315, 17316-17517, 17519-17601, 20129-20258, 22923-23117) and `test/turn_modulation_probe.jl` (543 lines) | `U6/`: preambles `preamble_*.jl` (gate-closed and injections A-E; exact count not stated), `measure_check1.jl`, `runtests_diff.patch`; 10 executions logged through `result/gates/turnmod/stage3_run_testsets.jl` (baseline, gate closed, injections A-E, two standalone two-rank children, measure_check1); CUDA active; MPI from the default environment | 7: 6 low, 1 information | the example testset and the two MPI sections not re-executed (10-12 min each; their gate rows and assertion arithmetic verified instead); `test/examples/crab_cavity_noise.jl` (1409 lines) not read (outside the region); injections applied in the parent only, the mpiexec child always unpatched; the fast lane not run end to end (membership derived from the `_lane_gate` sites) |
| U7 | the crab cavity noise example, harness, benchmark driver and validation study | in full, every line: `examples/crab_cavity_noise.jl` (866), `test/examples/crab_cavity_noise.jl` (1409), `profiling/crab_cavity_noise_backends.jl` (753), `validation/crab_cavity_noise_response.jl` (2365), `validation/README.md` 418-549, `src/examples/Examples.jl` 88-107; mechanism reads outside the region: `src/elements/turn_modulated.jl` (key layout 96-159, spectral 300-530, named functions), `src/tasks/Tasks.jl` 375-460, `src/tasks/RunArtifact.jl`, `src/elements/radiation.jl` 100-116, `src/elements/crab_cavity.jl` 285-320, `examples/weak_strong_tracking.jl` 104-118, four history records (ranges), `public_api.md` 283-300 | `U7/`: `probe_*.jl` (probe_records [170 assertions], probe_effects, probe_arith, probe_misc named; total script count not stated), `run_rules.sh`, `run_batch2.sh`; about 25 runs under `runs/`, `example/`, `driver/`, `tablefile/` and `noise_part.log` (four rules, CUDA, two MPI ranks, probes A-E and D2, three effect runs, tablefile feedback, five example variants, driver dry run and resume, validation part `noise` 273/273); 16 threads; CUDA active (GPU shared); MPICH_jll | 7: 1 low-medium, 5 low (one tagged "low (documentation)"), 1 info | the production benchmark (N = 1e5/1e6, 2000 turns, six arms) not re-run (dry run only); parts pilot, sweep, report, control not run, tablefile at 8 turns only; the driver's `load=include` mode and the harness in script mode not run; the Rayleigh K < 8 FAIL path, Float32 lines, the `f_rev` band form, a custom spectrum not exercised; the harness refusals read, not executed; the GPU shared with another process, so no timing is a measurement |
| U8 | the campaign's documents (Phases 3 and 6) | in full, line by line: `docs/theory/crab_cavity_noise_response.md` (770), `docs/design/turn_modulation_record.md` (405), `docs/design/spectral_turn_table.md` (529), the five history records `crab_cavity_noise_validation_2026_10_14.md` (560), `crab_cavity_noise_mpi_benchmark_2026_10_14.md` (424), `crab_cavity_noise_relative_strength_2026_10_15.md` (356), `turn_modulation_record_2026_10_15.md` (578), `spectral_turn_table_2026_10_16.md` (895), `docs/todo.md` rows 18-41, `docs/guides/documentation.md` (71); as scoped by the brief: `docs/design/turn_modulation.md` 1-35, 549-647, 746-786 plus its whole campaign diff (91+/16-), `docs/design/run_artifact.md` 18-32 and 90-280, `docs/public_api.md` 28-48, 118-130, 195-380, `docs/README.md` 83-135, 369-392, 432-545, `docs/experiences.md` 1465-1607, `docs/history/turn_modulation_stages3_4_2026_10_13.md` 216-703; for hypothesis 6 `src/elements/crab_cavity.jl` 1-40, 80-95, 150-190, 285-461 | no probe scripts stated: read-only `git log`/`git diff` on every cited sha, greps over `src/`, `test/runtests.jl`, `validation/`, `examples/`, `profiling/`, hand arithmetic (section B); no Julia process, no validation run, no CI query (`gh` not installed, no network) | 18: 14 low, 4 info | CI runs 449, 451, 454, 455, 457 (and 456, 458) not queried; the validation and benchmark numbers not re-run; the gate logs under `result/gates/` not opened; `docs/history/turn_modulation_stage1_2026_10_12.md` not read (outside the region); `validation/README.md` grepped for superseded wording only; `docs/design/turn_modulation.md` sections 1-4, 5.1-5.5, 7-9 not re-read (outside the scoped parts); docstring rendering not run; todo rows 37, 38, 41 checked by grep only |
| U9 | localisation of lead U1-3: the general turn loop's per-turn allocation (`src/tasks/Tasks.jl`, the recorder seam in `src/tasks/RunArtifact.jl`) | every line of the named ranges: `src/tasks/Tasks.jl` 38-60, 178-215, 657-800, 970-1180, 1215-1245, 1280-1325, 1618-1720, 1780-1900, 1925-1978; `src/tasks/RunArtifact.jl` 15-50, 150-192, 504-660; `src/track/phase6d_track.jl` 1-120; `src/track/fused_track.jl` 100-140; `src/policies/Policies.jl` 188-215 and 1236-1275; `src/tasks/BeamObservers.jl` 150-200 and 375-402; `src/elements/turn_modulated.jl` 1390-1420; `test/runtests.jl` 7899-8010 and 10025-10085; `examples/crab_cavity_noise.jl` 155-185, 236-340, 655-700; `docs/design/turn_modulation.md` 640-720; `docs/design/turn_modulation_record.md` 380-395; U1's report, `probe_slope.jl`, `alloc_helpers.jl` and their logs; Base `tuple.jl` 31-35 and 71-75 | `U9/`: 8 scripts (probe_split, probe_pieces, probe_loop, probe_allocs [Profile.Allocs], probe_fix, probe_fix2, probe_example, probe_timing) plus the re-run of U1's `probe_slope.jl` (`step1_probe_slope_t1.log`), logs beside; `--threads=1`; CPU threads policy except the example's `:auto` (CUDA); the proposed fix evaluated by `include_string` only, never written to source | 6: 2 medium, 4 low | four threads not re-measured (one thread only; U1's four-thread column cited); the strong-strong loop (U9-3) not measured, outside the region; the CUDA general loop not measured separately (only the example's `:auto` run); the fix not run through the suite |
| S1 | seam: the counter-RNG key `(seed, method_code, turn, rng_id, particle_index, component)` of `src/math/counter_rng.jl` and every consumer of it in `src/` and `ext/` | in full, every line: `src/math/counter_rng.jl` (431 lines); by range: `src/elements/turn_modulated.jl` 90-230, 365-435, 480-530, 560-660, 690-730, 795-1010, 1150-1190, 1465-1495; `src/beam/Beam.jl` 110-180 and 555-640; `src/tasks/BPMObserver.jl` 90-245 and 395-430; `src/elements/radiation.jl` 1-60, 120-135, 160-290; `src/tasks/Tasks.jl` 216-234, 310-470, 965-990, 1085-1100, 1905-1925; `src/track/Track.jl` 1-60; `src/track/phase6d_track.jl` 20-60, 255-300, 357-420; `src/track/radiation_track.jl` 1-90; `src/track/strong_beam_track.jl` 70-90 and 125-140; `src/policies/Policies.jl` 705-782 and 925-985; `src/tasks/strongstrong/interface.jl` 2388-2412, 2680-2692, 2825-2845; `src/knowledge/Knowledge.jl` 55-85; `src/elements/aperture.jl` 40-56; `src/contracts/Contracts.jl` 3540-3560; seven reference documents by range; suite anchors `test/runtests.jl` (five ranges), `test/mpi_seam_check_fixture.jl` 30-70, the probe header; a whole-tree grep of every draw name, id claim and `rand`/`randn` in `src/` and `ext/` | `S1/`: 6 scripts (probe_cells_registry, probe_registry_tail, probe_backends, probe_mixed_precision, probe_strongstrong_warning, tripwire_prototype), logs beside; CUDA active | 9: 7 low (one tagged "low (documentation)", one "out of hypothesis, low"), 2 info | MPI at two or more ranks not launched (the suite's fixtures cited); `ext/OctopusMPIExt.jl` and the other extensions grepped for RNG usage (none), not read line by line; files outside the seam read at their call sites and plumbing only (`Tasks.jl`, `interface.jl`, `Policies.jl`, `phase6d_track.jl` not read in full); whether the suite pins the spectral table's method independence or `BPMObserver(rng_id=0)` grepped, not exhaustively traced; the mixed-precision failure (S1-9) measured on one element kind only |
| S2 | seam: CPU/CUDA twin implementations and thread-count invariance | line by line: `src/elements/turn_modulated.jl` (all 1671 lines), `src/elements/crab_cavity.jl` (all 461), `src/elements/rf_cavity.jl` 1-600 (600-833 skimmed), `src/track/phase6d_track.jl` 1-135 and 180-448, `src/tasks/Tasks.jl` 630-760, 960-1260, 1300-1324, 1486-1497, 1615-1680, 1820-1978, `src/tasks/RunArtifact.jl` 14-50 and 536-640, `src/policies/Policies.jl` 1236-1278, `src/track/strong_beam_track.jl` 55-150, `src/tasks/BeamObservers.jl` 1039-1062 and 1225-1261, `validation/tracking_backend_consistency.jl` (all 313), `validate(::ElementTrackingBackendConsistencyContract)` in `src/contracts/Contracts.jl`, `test/runtests.jl` 8052-8230, 15016-15114, 15116-15230, 17316-17517, 22923-23117, `test/turn_modulation_probe.jl` (all 543); six reference documents | `S2/`: 15 scripts (p1_rules_cpu_cuda, p1_schedule, p1b_rf_cpu_cuda, p2_large_table_cuda, p2b_update_cost, p2c_execute_wall, p2d_memory_control, p3_float32_cuda, p4_all.sh, p4_threads_run, p4_compare, p4d_fused_lumi, p5_device_compile, p6_modulated_contract, p7_fused_cuda_launch) plus the shipped backend-consistency script run whole and the `Core.Box` sweep re-run; logs `p*.log`; threads 1, 4 and 8; CUDA active (GPU shared) | 3: 1 medium, 2 low | the strong-strong loop's host-side placement (`interface.jl:3120`, the beam-2 recorder; outside the brief's weak-strong seam); the MPI execution policy arm (outside the brief); thread counts above 8 and the CPU `:fused` route on a device (refused by design); a Float32 RF cavity on CUDA with the four rule kinds (no Float32 RF runtime exists, S2-2); `validation/moment_observer_backend_consistency.jl` (not a campaign participant); occupancy-cache keying (`phase6d_track.jl:316`) read, not measured |
| S3 | seam: every walker over a compiled line (or the spec line it compiles from) that looks for turn-modulated elements | every line of the named ranges: `src/elements/turn_modulated.jl` 700-1000, 1090-1320, 1320-1760; `src/tasks/Tasks.jl` 130-232, 300-590, 590-740, 940-1260, 1260-1500, 1560-1880; `src/tasks/RunArtifact.jl` 286-600; `src/tasks/strongstrong/interface.jl` 2370-2410, 2570-2700, 2800-2900, 3090-3290; `src/elements/beam_line.jl` 54-200, 240-420, 620-760; `src/elements/crab_cavity.jl` 186-240 and 340-470; `src/elements/rf_cavity.jl` 376-600; `src/knowledge/Knowledge.jl` 1005-1035 and 1370-1410; `src/knobs/Knobs.jl` 1025-1095; `src/tasks/BeamObservers.jl` 228-262; `test/runtests.jl` 8215-8245, 10220-10335, 10536-10625, 15016-15120, 16755-16835, 17040-17100, 17519-17640; four reference documents | `S3/`: 4 scripts (probe_walkers [log of 371 lines], probe_followup, repro_s3_1, repro_s3_2), logs beside; one CUDA arm executed | 3: 2 low, 1 info | an `IsolatedSegment` between modulated elements in a weak-strong task not executed; a CUDA strong-strong arm not executed (CPU strong-strong and CUDA weak-strong were); MPI with more than one rank not executed; the suite's tripwire testsets read, not run (their product recomputed in the probe); the probe rule is a session type, the artifact runs used shipped rules only |
| S4 | seam: declared schemas and metadata (option schemas, ParamMeta, help, receipts, snapshot) versus the runtime that consumes them | in full: `src/tasks/RunArtifact.jl` (1439 lines), `src/examples/Examples.jl` (whole); by block or range: the ParamMeta/construction_help/docstring/rule-coercion/wrap/slot blocks of `src/elements/crab_cavity.jl` and `src/elements/rf_cavity.jl`; the rule types, `_rule_kind`, `_turn_rule_names`, `_push_rule_slot!` and the provenance and columns walks of `src/elements/turn_modulated.jl`; `src/policies/Policies.jl` 1-70; `src/knowledge/Knowledge.jl` (ParamMeta, `validate_element_metadata`, `_check_declared_defaults!`, both `element_help` forms); `src/tasks/strongstrong/interface.jl` (task schemas, validator blocks, the `:strong_strong_output` receipt, the report entry); `src/tasks/Tasks.jl` (schema, report, receipt site, `_turn_modulation_entries`); `src/tasks/BeamObservers.jl`, `src/tasks/BPMObserver.jl` (schemas, receipt sites); `src/contracts/Contracts.jl` 195-720 plus `DEFAULT_INACTIVE_ELEMENT_PARAMS`/`_perturb_candidates`; `src/registry/Registry.jl` 1-190; `test/runtests.jl` 10355-10560, 16740-16960, 17020-17100; six documents plus the example and harness headers and todo rows 28, 61, 63 (other line counts not stated) | `S4/`: 6 scripts (probe_receipts, probe_fifth_rule, probe_schema, probe_kinds, probe_request_vs_resolved, probe_cuda), logs beside; CUDA functional | 10: 2 medium-low, 8 low | the suite's F4 testset not run with the injected rule (its assertions replicated in-process); `validate(PublicConfigurationEffectivenessContract())` not executed (its RunArtifact use read: `capacity=2` through MomentObserver receipts only); the MPI arm (rank-0-only recorder) not executed, read only; the cross-file seams S4-3 and S4-10 left to the auditor |
| S5 | seam: producer-consumer protocol pairs (epochs, windows, caches, seeds) between the rules, the task loops and the run artifact | line by line: `src/tasks/RunArtifact.jl` 1-1439 (whole file); `src/tasks/Tasks.jl` 380-470, 625-1236, 1290-1402; `src/tasks/strongstrong/interface.jl` 2325-2350, 2455-2730, 2500-2600, 2820-2900, 3120-3150; `src/elements/turn_modulated.jl` 225-300, 380-540, 690-845, 1055-1200, 1415-1671; `src/elements/crab_cavity.jl` 350-461; `src/elements/rf_cavity.jl` 500-560; `src/elements/aperture.jl` 130-150; `src/beam/*` (the `Phase6DRep` struct, line 45); `src/math/counter_rng.jl` 20-60; `src/knowledge/Knowledge.jl` 140-205; `src/elements/beam_line.jl` 70-90; `src/tasks/BeamObservers.jl` 128-175, 208-227, 365-395; `src/policies/Policies.jl` (the `_mp_is_root` sites); `ext/OctopusMPIExt.jl` (grep only); `test/runtests.jl` 15686-15806, 16705-16800, 16900-17010, 20155-20260, 11395-11560; `test/turn_modulation_probe.jl` 1-80; `test/examples/crab_cavity_noise.jl` 190-235, 400-470, 590-640, 1100-1200; `examples/crab_cavity_noise.jl` 105-185, 290-345, 560-720; five reference documents | `S5/`: 14 probe scripts (p1_window, p1f_ss, p2_seed, p2d_mech, p2e_mech2, p2f_lossreset, p3_append, p3b_open_handles, p3c_labels, p3d_phantom, p4_capacity, p4b_kill [invalid, superseded], p4c_kill, p5_warnings) plus the helpers `hold_open.jl`, `race_writer.jl`, `kill_child.jl`; the clean example once at its defaults (`p6_example.log`); the harness on two MPICH ranks (`p7_rank_wrapper.sh`, `p7_mpi.log`, `p7/`); CPU threads except the example's `:auto`; HDF5 2.1.1 on NFS | 7: 1 high, 1 medium, 5 low | CUDA arms of every seam (all probes on CPU threads; the example's `:auto` was the one CUDA execution); apertures in strong-strong lines and the strong-strong loss accounting across windows; a weak-strong line with a strong beam for the luminosity-flush/recorder-flush/ledger interplay (measured in the strong-strong task only); the two-concurrent-suites race not re-run; `HDF5.API.h5p_get_file_locking` not queryable (the locking behaviour measured instead); the `p4b_kill.jl` trials invalid, superseded by `p4c_kill.jl` |

Totals: 100 leads across the fourteen reports: 2 high (U1-1, S5-1), 8 medium (U1: 2, U5: 2, U9: 2, S2: 1, S5: 1), 2 medium-low (S4-1, S4-2), 2 low-medium (U3-2, U7-1), 75 low, 11 info or information (U2: 1, U5: 1, U6: 1, U7: 1, U8: 4, S1: 2, S3: 1).

Counting note: `grep -o '\[[a-z]*,'` on the lead headers matches the plain tags only; six headers carry a tag it misses and were classified by hand from their text: U3-2 `[low-medium, ...]`, U7-1 `[low-medium, ...]`, S4-1 and S4-2 `[medium-low, ...]` (kept as written), U7-5 and S1-4 `[low (documentation), ...]` (counted as low), S1-9 `[out of hypothesis, low, ...]` (counted as low). Every total above equals `grep -c '^### LEAD'` on the file.

### Reports that disclose a gap

Every report carries a coverage statement (files read, probes and where they live, what was not read). Three admit a partial read inside their declared region; the rest declare their unread items as outside the region.

- **S2** (in region): "`src/elements/rf_cavity.jl` 1-600 (the thin cavity and its modulation block; the accelerating cavity 600-833 skimmed for its 'no rule' declaration)". The one file of a region that was skimmed rather than read.
- **S1** (in region; the seam is declared as every consumer in `src/` and `ext/`): "`ext/OctopusMPIExt.jl` and the other extensions: grepped for RNG usage (none); not read line by line", and "Files outside the seam were read at their call sites and plumbing only (`Tasks.jl`, `interface.jl`, `Policies.jl`, `phase6d_track.jl` are not read in full)".
- **S5** (in its reading list): "`ext/OctopusMPIExt.jl` (grep only)" stands among the files read; everything else in its list is a named range read line by line.
- **U4** (scope statement, not a skip): "every line read" applies to the eight named ranges of `interface.jl`; the report does not claim or state the whole file's coverage.
- Out-of-region non-reads volunteered by their reports (not gaps in the assigned region, listed so the auditor can judge the boundary): **U6** "The `test/examples/crab_cavity_noise.jl` harness (1409 lines) was not read: outside the region"; **U8** "`docs/history/turn_modulation_stage1_2026_10_12.md` is outside the region and was not read; `validation/README.md` was grepped for superseded wording only (U8-12), not read in full" and "`docs/design/turn_modulation.md` outside the diff and sections 5.6, 6 and 10 (sections 1-4, 5.1-5.5, 7-9) was not re-read for this unit"; **U9** "The strong-strong loop (U9-3): not measured, outside the region".
- Statements that leave a number unstated: **U7** names four `probe_*.jl` scripts but not their total; **U6** does not count its `preamble_*.jl` files; **U8** ran no scripts (git, grep and hand arithmetic only); **S4** states a line count for `RunArtifact.jl` only and lists the other files by block.


## 3 Findings

Leads become findings only after the auditor reproduces them; each finding
carries the unit's lead id, the reproduction, the severity (Phase 17) and
the disposition (fixed here, todo row, or withdrawn with the reason).
Areas inspected and found sound are listed with what was compared.
Working queue, checkpointed as the audit proceeds (unit reports under
`result/audit_crab_noise_2026_10_16/` until archived beside this report;
"auditor" means reproduced by the orchestrator's own run, log under
`result/audit_crab_noise_2026_10_16/auditor/`):

| lead | claim | status | disposition |
|---|---|---|---|
| U5-1 | the ledger's `current_turn`/`elapsed` are stamped only by the luminosity flush and finalize; a killed weak-strong run shows `-1` with 70080 rows on file; docstrings and `run_artifact.md` promise "every flush" | CONFIRMED by auditor (`repro_U5-1.log`: probe-row flush -1, series flush -1, luminosity flush 3, killed file -1 with 70080 rows) | Medium; FIXED in the worktree: `_ra_stamp_ledger!` called by every flush (luminosity, probe rows, series: the recorder now holds its artifact through `AbstractRunArtifact`) and by finalize; the weak-strong loop assigns `current_turn` at the top of the turn as the strong-strong loop has since 2026-08-19 (U4 confirmed that ordering was deliberate, so the strong-strong loop is unchanged); docstrings reconciled; regression testset (c); probe 2/2 red on 3126908, green after |
| U5-2 | strong-strong `prepare_observers!` runs after `prepare_run_artifact!` outside the `try`, so a duplicate probe name leaves the artifact open, the task and the path wedged; the weak-strong twin closes | CONFIRMED by auditor (`repro_U5-2.log`: `art.file === nothing` false, open files 1, recorders held 2, second execute! "already open"; TrackingTask true/0) | Medium; FIXED in the worktree: the strong-strong `prepare_observers!` block is wrapped in try/catch that finalizes the artifact and rethrows; regression testset (d) on both task kinds; probe 3/3 red on 3126908, green after |
| U5-3, U5-6 | the torn-file refusal creates the slot group before the check; the phantom ledger row | reproduced by U5, internal-only paths | Low; FIXED in the worktree: `_ra_validate_turn_modulation!` runs every writer refusal before the ledger row is appended and before the first group is created (the message names both column-walk counts, U5-4) |
| U5-4, U5-5, U5-7..10 | message count; no kwargs-vs-schema tripwire; capacity's consumer; "backend" column claim; raw KeyError on append without `/execution`; one-sided short-series warning | U5 | Low; FIXED in the worktree: the kwargs-versus-schema pin (U5-5), an append on a file without `/execution` refused by name (U5-9), the long-series side of the warning (U5-10); `capacity`'s consumer and the "backend" column claim go to the docs and the rows |
| U3-1 | `seed=` keyword warns "deprecated" and the value is ignored (coordinates identical for any seed) | U3, measured | Low; FIXED in the worktree: `ArgumentError` naming `set_global_rng!(seed=...)` on both task kinds (no caller in the repository passed the keyword); regression testset (a); probe 2/2 red on 3126908, green after |
| U3-2 | a `set_global_rng!` between two `execute!` calls leaves a resolved spectral table under the old seed with no warning while white and pink follow | design-accepted (D11), measured | owner item: a warning at `execute!` when a resolved table's seed differs from the global seed, or a re-synthesis switch |
| U3-3 | a `SpectralNoise` and an offline table with equal (seed, rng_id, slot) on two elements: equal digests, no warning (the digest warning runs before resolution) | U3, measured | Low; todo row (the warning would have to run after compile) |
| U3-4 | stamp order differs between the two loops (series through t, ledger t-1 on an observer throw) | U3, measured | folded into U5-1's one semantic |
| U3-5 | the fast-loop predicate is hand-copied in two places | U3 | Low; FIXED in the worktree: `_fast_tracking_path(task, runtime_entries)` feeds the receipt and the branch |
| U3-6 | the `:turn_modulation` receipt is recorded before three refusals | U3, pre-existing shape | Low; todo row |
| U6-1 | the realised-record testset and the probe compare the record with `_turn_offset`, the hook's own function; a keying injection passes them while other testsets catch it | U6, injection E | Low; fix: an `octopus_normal`-anchored pin per live slot |
| U6-2 | every MPI arm degrades to `@test_broken false`, and the launcher call `MPICH_jll.mpiexec(exe -> exe)` is deprecated (the gate log carries the warning): a future removal turns three arms Broken with the gate green | U6, gate log native:1093 | Low now, the "never executed" class in waiting; FIXED in the worktree: the three launcher calls use the non-do-block `MPICH_jll.mpiexec()` (JLLWrappers' current API); the gate record quotes the Broken column |
| U6-3..7 | child load path binds the default-env MPI in the runner; `∪` for `vcat`; residuals unquoted; a hand-copied harness seed; pins without recorded negative controls | U6 | Low; small test edits; U6's injections become the controls' record |
| U2-1 | crab numeric type fixed by `frequency` alone, narrowing Float64 strengths to Float32 (the RF promotes over all parameters) | U2, measured, pre-existing | todo row (owner: the promotion rule) |
| U2-2, U8-10 | `ThinCrabCavitySpec`/`ThinRFCavitySpec` docstrings list three rules; the tripwire gates help and ParamMeta only | U2, U8 | Low; fix: docstrings and the tripwire |
| U2-3 | knob x relative strength rule correct but unpinned (crab strength knob, RF knob+rule) | U2, measured | Low; tests |
| U2-4 | RF L != 0: `_lattice_drift`'s cancellation, 67.7 ulps in z, CPU == CUDA | U2, measured, pre-existing, out of region | todo row (physically negligible) |
| S1-1, S1-2 | `BPMObserver(rng_id=0)` and a radiation spec reaching compile with id 0 draw on stream 0 while the metadata says 0 auto-assigns | S1, measured, pre-existing | todo rows |
| S1-3 | `StrongStrongTask` never calls `_warn_duplicate_radiation_streams`; the comment says "stays ledgered" but no row exists | S1, measured | Low; FIXED in the worktree: `StrongStrongTask` calls `_warn_duplicate_radiation_streams` over both lines; regression testset (b); probe 1/1 red on 3126908, green after |
| S1-4..8 | method code is not a key dimension (design-stated); cross-class cell sharing under one explicit id measured (todo row 38 to name the spectral class); cross-task same id unwarned; BPM id narrowing; deprecated single-element CUDA radiation kernel | S1 | docs and rows |
| S1-9 | Float32 beam through a Float64 `LumpedRadSpec`: CPU narrows silently, CUDA `InvalidIRError` | S1, measured, out of hypothesis, pre-existing | todo row |
| U8-1..18 | documentary drift: stale status lines, the D7 name template without `slot=`, "seed and stream" in the README, stage 2 "not implemented", the owner item U5-2 missing from todo, row 26 not closed, superseded numbers | U8 | Low; fixed in the closure commit |
| U1-1 | `update_line`'s `ntuple` closure loses constant propagation once a line holds about four distinct element types with two or more wrapped (three with the sink): 246 kB per turn plain and 129 kB with the sink on a 40-element four-type line, 204 kB with the sink on a three-wrapped line, the result inferring as `NTuple{40, Union{...}}`; the suite's two-type fixture sat below the threshold | CONFIRMED by auditor (`repro_U1-1.log`: the U1 table reproduced; `repro_U1-1_wt.log`: every shape 0 B and concrete after the fix) | High; FIXED in the worktree: `update_line` unrolls with literal indices (`_update_line_unrolled`, the `_slot_values` precedent); a heterogeneous-line pin on both hooks joins the rules testset |
| U1-3 | with recording on, `execute!` allocates about 98 kB per turn on the suite's two-type fixture and about 200 kB per turn on an eight-type line with NO modulated element, while `update_line` alone is 0 B | CONFIRMED by auditor (`repro_U1-3.log`: 3200 / 199728 / 98415 B per turn recording against -472 plain); LOCALISED by U9 (leads U9-1, U9-2): not the recorder but the general turn loop's `_active_plan_key`, whose per-turn `for entry in entries` over the heterogeneous isbits entries tuple boxes the WHOLE tuple once per element, plus the `get!(plan_cache, key) do` closure copying the tuple; FIXED: the hook entries are hoisted once per `execute!` (`_line_hook_entries`), the key reads the hooks vector only, the cache is probed with `get`/`setindex!`; after: 448 / 448 / 1071 B per turn at 1 thread (`auditor/probe_slope_wt_after_t1.log` against U1's `probe_slope_t1.log`), excess over the fast path 448 B per turn at 4 threads against 206,845 unfixed (`auditor/pin_u1_3_wt_v3.log`, `pin_u1_3_main_v3.log`) | Medium; fixed in `src/tasks/Tasks.jl`; pin: audit testset section (g), the `execute!`-level slope on a heterogeneous line with an artifact that U9-6 found missing |
| U9-1 | the plan key's per-turn walk over the heterogeneous entries tuple (185.9 of the 199.7 kB per turn on the eight-type line) | CONFIRMED by auditor (the U1-3 reproduction; U9's `probe_pieces.log`, `probe_fix2.log`) | Medium; FIXED with U1-3 |
| U9-2 | the `get!(plan_cache, key) do` closure captures the entries tuple by value, 2 x sizeof(entries) per turn | CONFIRMED by auditor (U9's `probe_fix2.log`: the closure is the whole 3.2 kB per turn of the one-type line) | Low; FIXED with U1-3 (`get`/`setindex!`) |
| U9-3 | the strong-strong segment loop pays the same plan-key walk and closure per block per beam per turn (seam, unmeasured by U9) | CONFIRMED and MEASURED by auditor (`auditor/probe_ss_slope_before.log`: 713 kB per turn on a nine-type pair against 226 kB on a one-type pair, 300 particles, 1 thread); the allocation profile (`auditor/probe_ss_allocs.log`) found a second per-turn copy: every `blocks[j]` read of the heterogeneous blocks TUPLE boxed a copy of the block with its entries inline (about 56 kB per turn on two 41-element lines); FIXED: `StrongStrongBlock` carries its hooks resolved at compilation, `_execute_strong_strong_segment!` takes the block and probes the cache without a closure, the blocks are a `Vector{Any}` read once per turn; after: 283 kB per turn (`probe_ss_slope_after.log`), excess over a one-type pair of the SAME length 29.8 kB per turn at 4 threads (`pin_u1_3_wt_v3.log`) where the remainder is the larger per-element worker closures of the bigger elements (`Policies.jl:1271`), not a tuple walk | Medium; fixed in `src/tasks/strongstrong/interface.jl`; pin: audit testset section (g) |
| U9-4 | the once-per-`execute!` walks over heterogeneous tuples (`_physics_line`, `_strong_beams_of`, the turn-modulation walks, `prepare_line_observers!`, `_finalize_line_observers!`, the strong-strong `_strong_strong_physics_line` and `_line_observers`) box the whole tuple per element, about 1.1 MB per call on the eight-type line | NOT REPRODUCED separately (the mechanism is U9-1's; the strong-strong profile shows the sites at 85 kB per call) | Low; LEDGERED: harmless for one long call, a cost only for turn-by-turn or short-chunk execution; todo row |
| U9-5 | the recorder's row buffers grow by doubling (`Float64[]` without `sizehint!`), about 580 B per turn averaged, the one cost the recording switch itself adds | NOT REPRODUCED separately (U1's fixture: 1071 against 448 B per turn with and without a modulated element after the fix) | Low; LEDGERED with the numbers; a `sizehint!(buf, capacity * ncols)` is the fix, not taken here because it needs its own hook-level pin |
| U9-6 | no existing pin could catch U9-1 or U9-2: the only `execute!`-level allocation pin uses a one-element line and compares `record_turn_times` on against off on the same loop | CONFIRMED by auditor (the pin in `TrackingTask records per-turn timings on BOTH of its turn loops` is as described) | Low; FIXED: audit testset section (g) pins the slope of `execute!` on an eight-type line with an artifact against the fast path (40 kB bound, 206,845 unfixed, 448 fixed) and the strong-strong nine-type pair against a one-type pair of the same length (100 kB bound) |
| U1-2 | crab cavities of 33 or more harmonics allocate 1.1-2.6 kB per realise (the `(dphi..., d...)` splat beyond `max_tuple_splat`), 0 at 32 | U1, measured; the pink stride bound admits at most 32 harmonics with a pink rule, white-only lines may exceed it | Low; todo row |
| U1-4, U1-5, U1-7, U1-8 | the `:rayleigh` docstring quotes `0` where the code passes `slot`; the ids collector's docstring omits SpectralNoise; a custom spectrum labelled with a preset's name takes the preset's canonical name; `TurnTable.offsets` is mutable after its digest | U1 | Low; docstrings in the closure commit; the name clash and the mutable offsets as todo rows |
| U1-6, S3-2, U3-3, U7-2 | a `SpectralNoise` and an offline table with equal (seed, rng_id, slot) on two elements give identical offsets with neither warning (the ids walk sees no id on the table, the digest walk no digest before resolution); the harness at its 2-turn default hits it across cavities | U1, S3, U3, U7, measured | Low; one todo row: an execute!-time digest check over the resolved provenance entries |
| U4-2 | `docs/current_runtime.md` claims "bit for bit" luminosity without scope; the measured parity across rank counts is 3.4e-15 (bitwise at one rank) | U4, measured; and a correction to the audit's own brief, which repeated the unscoped claim | Low; docs |
| U7-1 | the shipped radiation element is inert in effect (`damping_turns = 1e100`, excitation 1.4e-50; moments bitwise identical with radiation on and off), while three headers call it "a stochastic drive" | U7, measured | Low; headers corrected; the configuration is the owner's (inherited from the weak-strong example) |
| U7-3, U7-4, S4-1, S4-2, S4-3 | CRAB-NOISE fields that are echoes of the request (kbb_scale, radiation, chrom, table_file, seed); `OCTOPUS_CUDA_DEVICE` recorded nowhere; the artifact options' declared consumers unreachable from `TrackingTask`; `:strong_strong_output` carries the request, not the resolution (append on a fresh path, record on an unmodulated line); the snapshot observer's receipt never emitted | U7, S4, measured | Low; todo rows (Lesson 11 shape) |
| S4-6 | `RunArtifact(capacity=true)` accepted as 1; `append=1` refused by a TypeError not naming the keyword | S4, measured | Low; FIXED in the worktree: `append` and `capacity` refused by name for non-Bool and Bool-or-non-integer values; pinned |
| S4-5, S4-8, S4-9, S4-10, U5-5 | kind vocabulary hand-copied in four places; `_RA_KINDS` without a tripwire; the receipt shapes unpinned; `TrackingTask`'s `artifact` keyword without a schema entry (todo row 63); no kwargs-versus-schema tripwire for `RunArtifact` | S4, U5 | Low; the kwargs tripwire in this batch, the rest todo rows |
| S3-1 | an aperture inside a bare `BeamLine` placed in a task tuple compiles whole and the hidden-aperture collector stays silent, so its losses are unattributed | S3, measured, out of hypothesis, pre-existing | Low; todo row |
| S2-1 | the backend-consistency script carries no modulated cavity; a modulated-line contract passes at 6.6e-18 | S2, measured | Low; todo row (coverage extension) |
| S2-2, S2-3 | the RF cavity's runtime is Float64 regardless of the spec (a Float32 beam narrows silently on CPU and fails on CUDA with `InvalidIRError`); the crab cavity narrows to Float32 from its frequency: the two kinds disagree on what a Float32 line is | S2, measured, pre-existing | todo rows (owner: the precision policy) |
| S5-1 | the loss record's owner is a `WeakRef` to the immutable `Phase6DRep`, cleared at the first GC between two `execute!` calls: the next call reallocates the record (cumulative counts zeroed, earlier losses "unattributed" with a false warning, wrong `/losses`) and recompiles the line, re-synthesising every spectral table under the then-current seed | CONFIRMED by auditor (`repro_S5-1a.log`, `repro_S5-1b.log`: owner CLEARED after `GC.gc`, `owner_is_rep = false`, table name seed 21 -> 22) | High; FIXED in the worktree: the owner key is the beam's first coordinate array (storage the user's beam holds); regression (f) in the audit testset: counts [1] -> [2], no warning, identical digests and `seed=21` across a GC and a seed change between windows |
| S5-2 | no cross-process exclusion on the artifact file: two concurrent writers both "finish" with one run's output lost; HDF5 locking inert on this NFS; the registry guard is per process | S5, measured | Medium; todo row (owner: a lock-file sentinel or a documented single-writer rule) |
| S5-4 | the artifact and the receipts record no global seed or RNG method; white and pink series are unattributable from the file; a table name can say `seed=2` while white columns were drawn under seed 3 | S5, measured | Low; todo row (owner: ledger columns `rng_seed`, `rng_method` per `execute!`) |
| S5-5, S5-6, U8-16 | the observer-registry warning claims a truncation append mode does not do; the shared-id warning over-claims "identical draws" for different slots or table lengths; both warnings say "different elements" when one spec is placed twice | S5, U8 | Low; the first two reworded in the worktree; the third a todo row |
| S5-7 | `append=true` on a non-HDF5 file surfaces HDF5's own message | S5 | Low; todo row |
| docs (U8-1..18, U7-1, U7-5, U7-6, U5-8, U4-2, U2-2) | the documentary corrections | prepared as `docs_fixes.py` by a sub-agent (32 exact replacements, dry-run checked), reviewed by the auditor and applied to the worktree | FIXED in the worktree; the three contradictory sentences of the frozen spectral record (U8-8) are recorded here, not edited |
| traceability (U8) | no capability has a contract; the spectral rule has no theory section; the probe and the MPI arm have no validation item; pink, table and spectral have no benchmark | U8 | recorded as remaining risks; owner items |

### 3.1 Confirmed findings fixed in this batch

Every fix below was preceded by the auditor's own reproduction (the named
log under `result/audit_crab_noise_2026_10_16/auditor/`, git-ignored, the
numbers quoted here) and is pinned by a regression test shown to fail on the
pre-fix tree 3126908 (`regressions_probe.jl`: 8 of 10 red on 3126908, 10 of
10 green on the fixed tree; `pin_u1_3_probe.jl`: 2 of 2 red, then green).

1. **U1-1 [high] `update_line` allocated on heterogeneous lines.**
   `ntuple(i -> f(line[i]), Val(N))` loses constant propagation of the index
   once the line tuple holds two or more element types, so the pure per-turn
   rebuild boxed every element: 246 kB and 174 kB per turn on the two four-type
   modulated fixtures of U1's `probe_slope_t1.log` (0 B on homogeneous lines,
   which is all the suite pinned). Fix: `_update_line_unrolled`, a
   `@generated` unroll with literal indices (`src/elements/turn_modulated.jl`).
   After: -472 B per turn (noise floor) on every fixture. Pin: the
   heterogeneous-line zero-allocation block in "Turn modulation: rules,
   wrapper and the pure hook" (40 elements, four types, both hooks).
   Reproduction `repro_U1-1.log`, `repro_U1-1_wt.log`.
2. **S5-1 [high] the loss record's owner was a `WeakRef` to an immutable.**
   `WeakRef(rep)` on the immutable `Phase6DRep` is cleared at the first GC, so
   a second window reallocated the record (counts `[1]` again, the earlier
   loss "unattributed" with a warning) and recompiled the line, which gave a
   `SpectralNoise` table a new seed between windows. Fix: the owner key is
   the beam's first coordinate array, storage the user's beam holds
   (`src/tasks/Tasks.jl`). Pin: audit testset (f): counts `[1] -> [2]`, no
   warning, the same record, summary (2, 2, 0), equal spectral digests and
   `seed=21` across a GC and a seed change. Reproduction `repro_S5-1a.log`,
   `repro_S5-1b.log`.
3. **U1-3 / U9-1 / U9-2 / U9-3 [medium] the per-turn plan key walked the
   heterogeneous entries tuple.** Not the recorder (U1's hypothesis) but the
   general turn loop's `_active_plan_key`: `for entry in entries` over the
   heterogeneous isbits entries tuple boxes the WHOLE tuple once per element
   (quadratic in the line length), and the `get!(plan_cache, key) do` closure
   copied the tuple again; 199,728 B per turn on an eight-type line of 40
   elements with an artifact, 98,415 on the suite's two-type fixture, against
   -472 on the fast path (`repro_U1-3.log`; U9 `probe_pieces.log`,
   `probe_fix2.log`). The strong-strong loop paid the same per block per beam
   AND re-copied each block at every `blocks[j]` read of its heterogeneous
   blocks tuple (the allocation profile `probe_ss_allocs.log`): 713 kB per
   turn on a nine-type pair against 226 kB on a one-type pair
   (`probe_ss_slope_before.log`). Fix: the hook entries are resolved once per
   `execute!` (`_line_hook_entries`) or per block compilation
   (`StrongStrongBlock.hooks`), the key reads the hooks only, the cache is
   probed with `get`/`setindex!`, the blocks are a `Vector{Any}` read once
   per turn (`src/tasks/Tasks.jl`, `src/tasks/strongstrong/interface.jl`).
   After: 448 B per turn over the fast path on the eight-type line at 1 and
   at 4 threads (206,845 unfixed), 29.8 kB over a one-type pair of the same
   length for the strong-strong nine-type pair (352,725 unfixed), the
   remainder being the larger per-element worker closures of the bigger
   elements (`Policies.jl:1271`), not a tuple walk. Pin: audit testset (g)
   (bounds 40 kB and 100 kB; `pin_u1_3_main_v3.log` red, `pin_u1_3_wt_v3.log`
   green).
4. **U5-1 (= U4-1, U3-4) [medium] the `/execution` ledger was persisted by
   the luminosity flush and finalize only.** A weak-strong run without a
   strong beam, or a strong-strong run with a sparse luminosity schedule,
   killed mid-way left `current_turn` at the nothing-known sentinel while
   the series and probe groups held thousands of rows. Fix:
   `_ra_stamp_ledger!` is called by every flush (luminosity, probe rows,
   series: the recorder holds its artifact through `AbstractRunArtifact`)
   and by finalize; the weak-strong loop assigns `current_turn` at the top of
   the turn as the strong-strong loop has since 2026-08-19
   (`src/tasks/RunArtifact.jl`, `src/tasks/Tasks.jl`). Pin: audit testset
   (c): probe-row flush -> 3, series flush -> 5, luminosity -> 7, finalize
   -> 9. Reproduction `repro_U5-1.log`.
5. **U5-2 [medium] the strong-strong artifact stayed open after a prepare
   refusal.** A duplicate observer name refused in `prepare_observers!` left
   the HDF5 file open and the task unusable. Fix: the scoped block finalizes
   the artifact and rethrows (`src/tasks/strongstrong/interface.jl`). Pin:
   audit testset (d), both task kinds. Reproduction `repro_U5-2.log`.
6. **Low, fixed.** U3-1 the retired `seed` keyword (ignored after a
   deprecation warning) now refuses by name on both task kinds, naming
   `set_global_rng!` (pin (a)); U3-5 one predicate `_fast_tracking_path`
   shared by the receipt and the branch; S1-3 the radiation duplicate-stream
   warning spans both strong-strong lines (pin (b)); U6-2 three
   `MPICH_jll.mpiexec(exe -> exe)` -> `mpiexec()` in the suite; S4-6
   `RunArtifact` refuses a non-Bool `append` and a Bool or non-integer
   `capacity` by name, U5-5 the constructor keywords are pinned against
   `run_artifact_option_schema()` (pin (e)); U5-3 / U5-4 / U5-6 every writer
   refusal runs before the ledger row and before the first group
   (`_ra_validate_turn_modulation!`, the message names both counts); U5-9
   `append` onto a file without `/execution` refused by name; U5-10 the
   long-series side of the capacity warning; S5-5 / S5-6 the registry and
   shared-id warnings reworded; U6-4 `vcat`, not `∪`, in the provenance
   replay pin; U6-5 the check-1 envelope on the record; U7-7 what a resolved
   spectral slot reads back as (`docs/public_api.md`); U7-1 the example,
   harness and profiling headers (radiation inert at 1e100 damping turns);
   U7-6 the `PinkNoise` docstring's variance numbers; S4-4 the cavity
   docstrings name `SpectralNoise`; U8-1..6, U8-8, U8-10..15, U8-17, U8-18
   the thirty-two documentation corrections of `docs_fixes.py` (theory note
   sections 8 and 4.5, `turn_modulation.md` sections 4.4 and 10,
   `turn_modulation_record.md` status, `spectral_turn_table.md` D7 `slot=<s>`,
   section 3 heading and section 4 cost, the README entries, `todo.md` rows
   21-26, `validation/README.md`, `run_artifact.md`, `current_runtime.md`).

### 3.2 Confirmed leads priced and ledgered

Twenty-four `docs/todo.md` rows (opened 2026-10-16, each citing its leads)
plus the open-queue pointer row carry: U1-2; U1-6 / S3-2 / U3-3 / U7-2 /
S5-3; U1-7 / U1-8; U2-1 / S2-2 / S2-3 (owner); S1-9; U2-4; U3-2 (owner);
U3-6; S1-1 / S1-2 / S1-5 / S1-6 / S1-7; S2-1; S3-1; S3-3; S4-1 / S4-2 / S4-3 /
S4-10; S4-5 / S4-8 / S4-9; S4-7; U7-3 / U7-4; S5-2 (medium, owner); S5-4
(owner); S5-7; U8-16; U9-4 / U9-5; U6-6; U8-9 (restoring the stage 3-4
audit's U5-2 owner item); U8-7 (owner: a frozen record).

### 3.3 Leads closed without a change

S1-8 (the deprecated CUDA radiation kernel agrees with the fused one; not a
defect), U6-7 (information: the campaign's records lack defect-targeted
negative controls; this audit's pins all have one, section 6), U8-14 and
U8-17 (the closed rows' forward text, rewritten with the docs batch), U4-2
(the luminosity rtol statement, corrected in `docs/current_runtime.md`),
U9-6 (fixed by pin (g)). The queue table above records each lead's
disposition; the unit reports beside this record carry the full claims.

## 4 Corrections to the audit's own analysis

- The brief to U4 said the luminosity reduction is "bitwise across ranks".
  U4 measured and corrected it: bitwise at one rank, `rtol = 1e-12` across
  rank counts; `docs/current_runtime.md` now says so.
- U1-3's hypothesis named the recorder. U9 localised the cost to the general
  turn loop's plan key (the recorder's own cost is about 600 B per turn,
  U9-5), and the auditor's allocation profile of the strong-strong twin
  found a second mechanism U9 had not claimed: the `blocks[j]` copy of a
  heterogeneous blocks tuple. U9-3 was filed "unmeasured"; it is measured
  here (713 against 226 kB per turn).
- The first strong-strong pin design compared the nine-type pair with a
  one-element pair; its residual (90 kB per turn at 4 threads) was the
  per-element worker overhead of 40 more elements, not the defect. The pin
  compares pairs of the same length.
- Lesson for the protocol's catalogue: a runtime-indexed `tuple[j]` and a
  `for x in tuple` over a heterogeneous isbits tuple box a copy of the whole
  tuple or element per access; per-block runtime data belongs in a `Vector`
  or in a `@generated` unroll, and `get!(dict, key) do` captures by value.

## 5 Formula and contract verification

The spectral synthesis normalisation (D5) and the relative strength
semantics (`S (1 + d)`), independently derived; every contract the
campaign touched (`PublicConfigurationEffectivenessContract`, the
provenance and recorder tests, the probe).

- **D5 scale (U6).** `sigma N / sqrt(2 sum_interior a_k^2 + a_Nyquist^2)`
  re-derived from the design note, never read from the code; on the
  testset's own tables the check-1 pins hold with an envelope of four or
  more orders: flat `rms_rel` 2.2e-16, `periodogram_rel` 8.9e-16,
  out-of-band 6.6e-32, DC 1.5e-33; pink -1.2e-15, 1.5e-14, 3.4e-33, 5.0e-35
  (now on the record in the testset's comment).
- **Relative strength semantics (U2, U7).** `strengthX (1 + d)`,
  `strengthY (1 + d)`, `V (1 + d)`: both planes carry the same factor and
  `strengthY` stays 0 on a horizontal cavity, CPU and CUDA bitwise; the
  thick RF path's `z` agrees with the closed formula to 67.7 ulp, the gap
  being the shared drift's `z + L - (1 + pz)/ps0 L` cancellation (U2-4, row).
- **Counter-RNG key layout (S1).** Under one explicit `rng_id` and one seed
  the spectral class shares cells with the three older classes exactly as
  the layout comment predicts (S1-5, measured 64/64 bitwise against the
  `Beam`'s raw normals); the rules band `_RULE_COMPONENT_BASE + slot` and
  the spectral cells (turn = slot, particle = bin) are as documented.
- **Pink noise variance (U7-6).** The `PinkNoise` docstring's numbers were
  re-derived and corrected.
- **Luminosity (U4).** Bitwise at one rank; `rtol = 1e-12` across rank
  counts (the correction above).
- **Contracts and validators** on the fixed tree
  (`auditor/snapshot_metadata_wt.log`): `validate_element_metadata()`
  passed, `validate_configuration_metadata()` true, the registry snapshot
  regenerated equal to the tracked file, both cavity help forms name
  `SpectralNoise`. `validate(PublicConfigurationEffectivenessContract())`
  runs in the full lane only and is covered by the gate of section 6.

## 6 Test, validation and performance report

**Targeted checks on the fixed tree** (worktree `audit-A`, 4 threads, the
stage runner cutting testsets by title; `auditor/testsets_fix1..7.log`):

- The audit's own testset "Neighbour audit 2026-10-16: the ledger stamps at
  every flush, a prepare refusal closes the artifact, the seed keyword
  refuses, radiation streams span both strong-strong lines": 36 of 36.
- "Turn modulation: rules, wrapper and the pure hook" (with the new
  heterogeneous-line pins), "The run artifact records the realised turn
  modulation", "The run artifact records turn-modulation provenance",
  "Spectral turn table: the producer through the consumer and the recorder",
  "Loss accounting reports itself", "Turn modulation: the strong-strong
  window and receipt", "luminosity_tracking selects the route and both give
  the same number", "The fused route carries luminosity through every
  wrapper", "A wrapped strong beam cannot silently lose its luminosity",
  "TrackingTask records per-turn timings on BOTH of its turn loops", "CPU
  strong-strong collide allocation does not scale with the pair count",
  "Solver equality is by configuration", "A strong-strong task under the
  multi-process policy is the task it composes", "Strong-strong slicing
  reduces the whole beam", "Strong-strong shifted moments preserve small
  spreads", "Spectral luminosity_schedule reaches its runtime consumer", "The
  gaussian solver takes the luminosity schedule (reporting-only)",
  "High-energy weak-strong strong-strong limit", "Flipping
  gaussian_when_luminosity moves luminosity and nothing else": green
  (`testsets_fix7.log`).
- Five cut testsets could not run under the runner for reasons that are the
  runner's, not the tree's: "A solver hidden under an abstract intermediate
  fails the validator" (its child uses `dirname(@__DIR__)` as the project
  root, which is the suite's `test/` parent only inside `Pkg.test`), "The
  run artifact carries the strong-strong luminosity channel" (81 of 82, the
  one error `LedgerPeekObserver` defined outside the cut block),
  "StrongStrongTask chunking preserves stochastic physics" and
  "Strong-strong physical parameter validation" (`test_beam`), "Lost
  particles cannot influence a strong-strong collision" (`with_logger`).
  They ran in the full lane of the gate below.
- Negative controls: `regressions_probe.jl` on 3126908 8 of 10 red, on the
  fixed tree 10 of 10 green (U5-1, U5-2, U3-1, S1-3); `pin_u1_3_probe.jl` on
  3126908 both pins red (excess 206,845 and 352,725 B per turn), on the
  fixed tree both green (448 and 29,754); the heterogeneous `update_line`
  pins red on 3126908 (`repro_U1-1.log`), green after (`repro_U1-1_wt.log`).
- The source sweeps (the `_st6_pin_lines`, `Core.Box` and detached-docstring
  sweeps, extracted): `result/gates/turnmod/sweeps_audit_fix1..6.log`; fix1
  failed on a detached docstring introduced by the `AbstractRunArtifact`
  placement (moved), fix2-fix6 green, fix6 on the final test and source
  tree.
- Snapshot and validators: `auditor/snapshot_metadata_wt.log` (section 5).

**Performance** (1 thread unless stated; `auditor/probe_slope_wt_after_t1.log`,
`probe_slope_wt_after_t4.log`, `probe_ss_slope_after.log`):

| line (40 elements, 4 particles) | path | before, B per turn | after |
|---|---|---|---|
| 40 x crab{1} (one type) | recording | 3,200 | 448 |
| crab{1..8} cycled (eight types) | recording | 199,728 | 448 |
| crab{1} white + dispersion (the fixture, two types) | recording | 98,415 | 1,071 |
| crab white, dispersion, RF white, coupling (four types, two modulated) | plain / recording | 246,183 / 248,351 | -473 / 1,071 |
| crab white, crab (nothing, pink), RF table, dispersion (four types, three modulated) | plain / recording | 173,831 / 336,039 | -473 / 1,367 |
| strong-strong nine-type pair + linear map, 300 particles | artifact | 713,349 | 283,142 (one-type pair: 226,189 before, 230,530 after) |

**Fingerprint (Phase 13).** The harness's `CRAB-NOISE` line for each of the
four rules (white, pink, table, spectral) at 2 turns, 10000 macroparticles,
seed 123456789, radiation on, CPU threads, re-run on the fixed tree
(`result/audit_crab_noise_2026_10_16/fingerprint_after/`) against the
baseline captured on 3126908 before the first modification
(`fingerprint/crab_noise_lines.txt`): every field other than the artifact
path and the three wall-time fields is identical for all four rules
(emittances first and last, luminosity mean, the realised offset rms per
slot, spectrum, band, amplitudes). The fixes changed no physics: the
allocation fixes are pure restructurings of the turn loops, the ledger and
artifact fixes touch persistence only, and the loss-owner fix changes
behaviour only across a GC between windows, which the 2-turn runs do not
exercise (the audit testset's section (f) pins that case).

**Gate.** The full two-arm gate on the worktree's final source and test
tree (the native arm, then `OPENBLAS_CORETYPE=Haswell julia -C haswell`,
run one after the other in one worktree, 4 threads, CUDA active; logs
`result/gates/turnmod/full_gate_native_audit_gateA.log` and
`full_gate_avx2_audit_gateA.log`): both arms exit 0 with 337 testset summary
rows and 150,713 passing tests each, no failure, no error, no lane-skip
banner (the full lane: the examples, the effectiveness contracts and the
CUDA testsets ran; 38 CUDA-named rows in each arm), 51 minutes per arm
(11:12-12:03 and 12:03-12:54 EDT). The fast lane ran green before the gate
on the same tree (`fast_lane_audit_fastA.log`, 322 rows) and again on the
final tree after this record's markdown-only completion
(`fast_lane_audit_fastB.log`). Not verified: nothing the matrix names for
this batch's classes is left unrun; CI (CPU only) runs on the push.

## 7 Change log

Source (`src/`):

- `tasks/Tasks.jl`: `_line_hook_entries`, the hooks-vector `_active_plan_key`
  (the Tuple method forwards), the hoisted hooks and the closure-free cache
  probe in the general turn loop; `current_turn` assigned at the top of the
  turn; the loss-record owner key; the `seed` keyword refused by name;
  `_fast_tracking_path`; the shared-id warning reworded.
- `tasks/strongstrong/interface.jl`: `StrongStrongBlock` carries `hooks`,
  the blocks are a `Vector{Any}`, `_execute_strong_strong_segment!` and the
  pair take the block and probe the cache without a closure, each block read
  once per turn; the radiation duplicate-stream warning over both lines; the
  `prepare_observers!` block finalizes the artifact on a refusal; the `seed`
  keyword refused.
- `tasks/RunArtifact.jl`: `AbstractRunArtifact`, the recorder's `owner`,
  `_ra_stamp_ledger!` at every flush, `_ra_validate_turn_modulation!` before
  the ledger row and the first group, the constructor's by-name refusals,
  `append` onto a file without `/execution` refused, the long-series warning.
- `elements/turn_modulated.jl`: `_update_line_unrolled`; the `PinkNoise`
  docstring. `elements/crab_cavity.jl`, `elements/rf_cavity.jl`: docstrings.
- `tasks/BeamObservers.jl`: the registry warning reworded.

Tests (`test/runtests.jl`): the heterogeneous-line pins in "Turn modulation:
rules, wrapper and the pure hook"; the audit testset (a)-(g); `vcat` in the
replay pin; the check-1 envelope; `mpiexec()` three times.

Documentation: `docs/theory/crab_cavity_noise_response.md`,
`docs/design/turn_modulation.md`, `docs/design/turn_modulation_record.md`,
`docs/design/spectral_turn_table.md`, `docs/design/run_artifact.md`,
`docs/current_runtime.md`, `docs/public_api.md`, `docs/README.md` (the
entries and this record's), `docs/todo.md` (rows 21-26 corrected, 25 rows
opened), `validation/README.md`; the headers of `examples/crab_cavity_noise.jl`,
`test/examples/crab_cavity_noise.jl`, `profiling/crab_cavity_noise_backends.jl`.

Records: this report; the fourteen unit reports under
`audit_crab_cavity_noise_neighbours_2026_10_16_unit_reports/` with their
`INDEX.md`.

## 8 Remaining risks and the open queue

The open queue is the 2026-10-16 block of `docs/todo.md` rows (section 3.2),
headed by the pointer row "Crab-cavity / RF-cavity noise neighbour audit: the
open queue". Risks the batch leaves:

- **The strong-strong blocks are now boxed** (`Vector{Any}`): one dynamic
  dispatch per block per turn into the specialised segment, on the CPU and
  CUDA paths alike. The CUDA path is exercised by the gate's CUDA-active
  arms and the backend-consistency scripts; nothing else changed on it.
- **Once-per-`execute!` tuple walks** (U9-4) remain: about 1.1 MB per call
  on an eight-type line of 40 elements, a cost for turn-by-turn drivers.
- **Owner decisions pending:** the cross-process exclusion of the artifact
  (S5-2, medium), a `SpectralNoise` table that does not follow a seed change
  (U3-2), the ledger's seed columns (S5-4), the modulated elements' precision
  policy (U2-1 / S2-2 / S2-3), the frozen stage 0 record's status (U8-7),
  the partial-slot rollback (U8-9 restoring U5-2 of the stage 3-4 audit).
- **Negative controls in the campaign's records** (U6-7): several earlier
  pins have only the feature-absent red; this audit's pins each have a
  defect-targeted red on 3126908, quoted in section 6.
- **The two concurrent suites race** (row 31) stands; the gate's arms ran
  sequentially in one worktree.
- **Not audited:** the Twiss analysis, the knob system, the multi-process
  policy beyond the two seams S4 and S5 touched, the CUDA kernels' numerics
  (only the device conversion of the two cavities, through the identity
  testset), as section 1 declared.

---

**Added after the push (2026-10-16).** Pushed as 8ace18b (origin/main, 13:3x
EDT, on the owner's word); CI run 459 (GitHub Actions, the CPU full lane,
ubuntu-latest) completed green at 14:26 EDT. The owner then opened the fix
batch for the section 8 items; its record is
[`crab_cavity_noise_audit_fixes_2026_10_16.md`](crab_cavity_noise_audit_fixes_2026_10_16.md).
