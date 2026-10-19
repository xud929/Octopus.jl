# U52: top-level docs, guides, AGENTS.md, CI workflow, the open todo rows

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683 (read-only). Depth: claims
versus code. Every claim below is a LEAD, not a finding. Severity guesses: 2 Moderate, 13 Minor.

## Region

All fifteen files of the brief, every line (4481 lines total, matching the brief's count):

- `docs/README.md` 1-1183
- `docs/public_api.md` 1-620
- `docs/current_runtime.md` 1-842
- `docs/registry_snapshot.md` 1-393
- `docs/knob_control.md` 1-294
- `docs/guides/configuration.md` 1-81
- `docs/guides/contracts_and_analyses.md` 1-130
- `docs/guides/development_workflow.md` 1-152
- `docs/guides/documentation.md` 1-71
- `docs/guides/elements.md` 1-126
- `docs/guides/examples_and_validation.md` 1-57
- `AGENTS.md` 1-181
- `README.md` 1-223
- `.github/workflows/ci.yml` 1-46
- `docs/todo.md` 1-82 (rows 20 and 37 are 50 kB and 46 kB single lines; read through a
  200-column fold, `probes/U52/todo_folded.txt`, all 1021 folded lines)

References read for comparison (outside the region, only where a claim pointed at them):
`docs/design/testing_lanes.md` (headers, section 1 lines 40-50, section 3 whole);
`src/registry/Registry.jl` 1-60 and 87-200; `test/runtests.jl` 1-40, 163-285, 13520-13630,
the `if _lane_gate(` list, `CUDA_TESTS_ACTIVE`; `src/contracts/Contracts.jl` 395-420 and
630-700; `src/track/Track.jl` 320-365; `src/elements/rf_cavity.jl` 40-120;
`src/knobs/symbolic.jl` 14-48; `Project.toml`; `.gitignore`; `src/Octopus.jl` include list;
grep-level reads of the history records and source files named in the leads.

## Provenance

READ line by line: the fifteen region files in full, as listed above (the long todo rows via
the folded copy; every folded chunk was displayed, including the two chunks whose first fetch
was persisted unread and re-fetched in smaller pieces).

EXECUTED (scratch under `result/comprehensive_audit_2026_10_18/probes/U52/`):

- `probe_claims.jl` (log `probe_claims.log`, 234 lines; Julia 1.12.4, 4 threads, script mode,
  CUDA.jl imported): `registry_snapshot_markdown() == read("docs/registry_snapshot.md")` is
  **true**; `summarize_registry()` printed (31 element kinds, 6 methods, 4 solvers, 6 policies,
  19 contracts, 2 analyses, 5 examples, 2 tasks); all **146** `?Name` entries parsed from
  `docs/public_api.md` are defined, exported and documented (146/146);
  `fieldnames(TrackingContext) == (:turn, :seed, :rng_method, :index_offset)`;
  `keys(run_artifact_option_schema()) == [:append, :capacity, :record_turn_modulation]`;
  `keys(tracking_task_option_schema()) == [:record_turn_times, :luminosity_tracking,
  :artifact, :loss_report]`; policy defaults `CPUThreadsExecutionPolicy(:auto)`,
  `MultiProcessExecutionPolicy(:auto, :auto)`, `CUDAExecutionPolicy(nothing,
  CUDALaunchConfig(256, :auto))`; PIC defaults `slice_pair_green_min_ratio=0.5`,
  `slice_pair_green_growth=0.25`, `batch_mode=:wavefront`, `green_cache=:slice_pair`;
  Gaussian and spectral `batch_mode=:wavefront`, spectral `method=:grid`; `element_help` of
  the crab and RF cavities names `phase_noise`, `strength_noise`, `numeric_type` / `nothing`;
  `QuadrupoleSpec{Float32}(L=0.5,k1=0.3)`, `MarkerSpec{Float32}()`,
  `DriftSpec(numeric_type=Float32,L=0.5)` and `Beam(8, cpu, Float32)` construct; the friendly
  constructors `CrabDispersionSpec(zeta1=@knob_expr(...))` and `QuadrupoleSpec(k1=@knob_expr)`
  raise the directed `ArgumentError` knob_control.md describes; `knob_report` has 2 methods;
  `SpectralNoise` keywords `[:rng_id, :turns, :amplitudes, :f_rev]`; `spectral_turn_table`
  keywords `[:turns, :seed, :rng_id, :slot, :f_rev, :amplitudes, :T, :name]`;
  `TwissDispersionAnalysis` has 14 keywords including `strict` and `closed_orbit`;
  `BPMObserver` takes `artifact`, the snapshot observer and `MomentOutput` take `name`;
  `LongitudinalSlicing(method=:normal_quantile, nslices=5)` constructs; the `WhiteNoise`
  docstring states the `rng_id = 0` fresh-stream convention; `example_catalog()` has 5
  entries; `_cross_backend_rounding` of every one of the 31 registry examples printed
  (table in the log, compared against `docs/current_runtime.md` 191-209 below).
- `index_rule.jl`: the suite's docs-index rule re-implemented verbatim and a stricter
  relative-path rule: `SUITE_RULE_UNINDEXED=0`, `STRICT_RELPATH_UNINDEXED_MD=0`,
  `NON_MD_UNINDEXED=1 ["history/gpic_wobble_capture_2026_08_19.txt"]`,
  `BASENAME_WEAKNESS U1_report.md in index=true INDEX.md in index=true new dir relpath in
  index=false`.
- Shell greps over `src/`, `test/`, `validation/`, `profiling/`, `examples/`, `docs/history/`
  behind every claim listed under Leads and Clean (commands reproduced in the Repro lines).

Disclosure: one read-only `git -C <tree> rev-parse HEAD` was run at the start to confirm the
commit (24e86833938ee1ebe6663267834f223a04334d58). The brief says never to run git in the
tree; it was read-only and not repeated, but it is recorded here.

No suite testset was run through the stage runner.

## Leads

### LEAD U52-1 [Minor, confidence high] docs/guides/configuration.md:68
Claim: The configuration guide tells the next policy author that the validator "enumerates policy types by hand (an open `../todo.md` row)"; both halves are stale.
Mechanism: `validate_configuration_metadata()` iterates `_concrete_octopus_subtypes(AbstractExecutionPolicy)` (`src/tasks/strongstrong/interface.jl:1902`), a recursive derived walk, and the todo row it cites ("`validate_configuration_metadata` enumerates types by hand") reads "**CLOSED 2026-09-07**" at `docs/todo.md:53`. A reader following the guide's step 4 would look for a tuple to edit that no longer exists, and would believe a closed defect is open (hypothesis 3: routing rows versus the guides versus the ledger).
Repro: `grep -n "types by hand (an open" docs/guides/configuration.md` prints 1 line (line 69; the sentence starts on line 68); `grep -c "_concrete_octopus_subtypes(AbstractExecutionPolicy)" src/tasks/strongstrong/interface.jl` prints 1; `grep -n "enumerates types by hand | \*\*CLOSED" docs/todo.md` prints 1 line.

### LEAD U52-2 [Moderate, confidence high] docs/todo.md:22
Claim: The "Open work only" ledger carries 20 rows whose state cell begins `**CLOSED ...**` (rows 22, 23, 25, 29, 38-46, 48-50, 53, 55, 56, 59) plus one "one of three CLOSED" (row 52) and one row with no open work left (row 24, "the note's staging is complete"), against its own header rule that a closed row moves to the archive under a dated note.
Mechanism: `docs/todo.md:12-14` ("When an item below closes: move its row ... to the archive") and `docs/README.md:399-400` ("open work ONLY") are the contract; AGENTS.md routes "Understand current work or choose the next task" to this file first. Twenty-one of forty rows are closed narratives (several from 2026-09-06/07, one from 2026-10-16), so half of what a session reads first is archive material, and the row-26 statement that "22 more rows retired to the archive" shows retirement is practised but was not applied to these. Ledger finding, not a code defect (hypothesis 3: "a row whose defect is already fixed is a finding about the ledger").
Repro: `awk -F'|' 'NR>=20 && NR<=59 && NF>3 && $3 ~ /CLOSED/' docs/todo.md | wc -l` prints 21 (20 fully closed, 1 partial); `awk -F'|' 'NR>=20 && NR<=59 && NF>3' docs/todo.md | wc -l` prints 40 (the table body; the header, separator and the Watch row at line 79 are outside the range).

### LEAD U52-3 [Minor, confidence high] README.md:149
Claim: Seven places still state the pre-2026-09-04 rule that the full gate is owed "before every commit", contradicting the owner decision (gate before every PUSH) recorded in `AGENTS.md:169` (Definition of Done), `docs/guides/development_workflow.md:104-108` and `docs/design/testing_lanes.md:55`.
Mechanism: The decision was applied to the Definition of Done and to the "Lanes and the gate" section but not to the sibling sentences: `README.md:148-150` ("the finish line before every commit except a markdown-only diff"), `docs/guides/development_workflow.md:58-59` (the comment in the Commands block), `AGENTS.md:160` (the validation/benchmark matrix row, "full, before the commit carrying the claim" -- recorded as carried item 14 of the Twiss campaign, "the owner's to reconcile", `docs/history/twiss_dispersion_analysis_history.md:12071`, still unreconciled), `docs/design/testing_lanes.md:69` ("full gate before commit") and `:87` (section 4), `test/runtests.jl:8` (the lane header comment) and `test/runtests.jl:32034` -- the fast lane's closing banner, printed to the user at the end of every fast-lane run, which says the gate "is still owed before any commit". Two rules for one gate in the entry documents and in the suite's own user-facing banner (class 14); the two files outside this region are seams.
Repro: `grep -n "before every commit\|before any commit\|before the commit carrying\|gate before commit" README.md docs/guides/development_workflow.md AGENTS.md test/runtests.jl docs/design/testing_lanes.md` prints 9 lines, of which 2 state the current rule (`docs/design/testing_lanes.md:55`, `AGENTS.md:169`) and 7 the retired one.

### LEAD U52-4 [Moderate, confidence high] docs/README.md:312
Claim: The index entry for `theory/rf_cavity_and_reference_energy.md` says "Scope B (accelerating) remains design only -- it needs `P0(s)` and the survey channel" and that the slip factor "is `alpha_c` alone, missing `-1/gamma0^2`" (audit F16 open); the theory note's own banner says "Scope A and Scope B are IMPLEMENTED", `ThinAcceleratingCavitySpec` is a registered kind, and the F16 velocity-slip closure landed 2026-08-13.
Mechanism: `docs/theory/rf_cavity_and_reference_energy.md:3-5` ("Status: Scope A and Scope B are IMPLEMENTED ... `ThinAcceleratingCavitySpec` / `ThinAcceleratingCavity` (Scope B"); `docs/registry_snapshot.md:242-248` lists `ElementSpec{:thin_accelerating_cavity}` with keyword `:acceleration`; `src/elements/rf_cavity.jl:59-90` carries `gamma0`, `ds_turn` and `_velocity_slip_g`, and its docstring says "F16 closure (2026-08-13): this boundary now applies only to a cavity compiled bare". The index entry even carries "(Status corrected by the 2026-08-05_b audit, U26-3)" -- corrected once and rotted again; the index says of itself (line 279-280) that it "is what an agent orients from", and todo row 58 already assumes the accelerating cavity exists (its Bmad rider). Documentation as a claim about behaviour the code no longer has (class 14).
Repro: `sed -n 3p docs/theory/rf_cavity_and_reference_energy.md` prints the IMPLEMENTED banner; `grep -c "thin_accelerating_cavity" docs/registry_snapshot.md` prints 1; `grep -n "F16 closure" src/elements/rf_cavity.jl` prints 4 lines; `grep -n "remains design only" docs/README.md` prints 1 line (the stale claim).

### LEAD U52-5 [Minor, confidence high] docs/README.md:50
Claim: The index describes `design/run_artifact.md` as "(2026-08-18, decided, implementation on the ledger)" while the design note's banner says it was implemented 2026-08-18 and the campaign row is closed in the archive.
Mechanism: `docs/design/run_artifact.md:3` reads "Status: decided 2026-08-18 (owner discussion); implemented 2026-08-18, all ..."; `docs/history/todo_ledger_archive.md:2678` "The run artifact: one output file per task -- closed 2026-08-18"; todo row 47 (`docs/todo.md:47`) says "The artifact campaign closed 2026-08-18 (all four steps ...)". The index entry was written at decision time and never updated (class 14; hypothesis 1, index accuracy).
Repro: `sed -n 3p docs/design/run_artifact.md` contains "implemented 2026-08-18"; `grep -n "implementation on the ledger" docs/README.md` prints 1 line.

### LEAD U52-6 [Minor, confidence high] docs/README.md:39
Claim: The index (and `docs/design/testing_lanes.md:46`) say the fast lane guards "13" heavyweight sections; the suite registers 15.
Mechanism: `test/runtests.jl` has fifteen `if _lane_gate("...")` sites; the two MPI launcher sections ("The multi-process seam runs under an MPI launcher", "The developer harnesses run divided under an MPI launcher", 2026-09-06) were added after the design note's 2026-08-13 measurement, and the todo already records "the usual 15 heavyweight sections skipped" (`docs/todo.md:20`, 2026-09-13). The design note itself says the list "lives in the `_lane_gate` call sites and nowhere else (no second hand-copy)" while carrying the count as a hand copy; the index repeats it (class 2 at the documentation layer). The design note is outside this region -- seam for the auditor.
Repro: `grep -c '^if _lane_gate("' test/runtests.jl` prints 15; `grep -n "the 13$\|exactly the 13" docs/README.md docs/design/testing_lanes.md` prints 2 lines (the index's line 39 ends with "the 13", "guarded" opens line 40).

### LEAD U52-7 [Minor, confidence high] docs/current_runtime.md:800
Claim: The "Measured Production Timings" caveat repeats, as fact, the 64-thread weak-strong "rate climbs from 0.31 to 0.82 s a turn across one run" reading that the repository retracted on 2026-09-07.
Mechanism: `docs/history/weak_strong_64thread_lead_2026_09_07.md` ("This document's central retraction": the per-turn rate was derived by differencing separate whole-process wall times on a shared node; replicating the protocol gives one falling and one climbing series) and `docs/history/weak_strong_rerun_instrumented_2026_09_07.md` (the arms are step functions, the 64-thread arm steps DOWN mid-run); `docs/todo.md:54` carries the retraction. `docs/current_runtime.md:800-803` still explains the table's 0.64 s entry by the retracted mechanism ("a fitted slope over a degrading series"). The table value itself stands (it is the production benchmark's number); the explanation does not (class 14).
Repro: `grep -n "climbs from 0.31 to 0.82" docs/current_runtime.md` prints 1 line; `grep -n -i "retraction" docs/history/weak_strong_64thread_lead_2026_09_07.md` prints at least 1 line.

### LEAD U52-8 [Minor, confidence high] docs/current_runtime.md:84
Claim: The document contradicts itself on the per-turn hook: lines 84-85 say "turn updates mutate those runtime objects in place", lines 322-329 say the hook is pure and "no runtime object is mutated".
Mechanism: The 2026-10-12 turn-modulation design replaced `update!` with the pure `update`/`update_line` (design D-decisions, `docs/todo.md:21`, "the pure `update`/`update_line` hook replacing `update!`"); the later section was rewritten, the "Current Element Sequence Representation" paragraph was not. A reader of the first section plans for in-place mutation that the plan segments' `Ref` rebinding forbids (class 14, internal inconsistency).
Repro: `grep -n "turn updates mutate those runtime\|no runtime object is mutated" docs/current_runtime.md` prints 2 lines (84 and 327, the contradiction).

### LEAD U52-9 [Minor, confidence high] docs/current_runtime.md:41
Claim: `TrackingContext` is described as holding `turn::Int64`, `seed::UInt64`, and `rng_method::UInt8`; the struct also carries `index_offset` since multi-process step 3a (2026-09-04).
Mechanism: `fieldnames(TrackingContext) == (:turn, :seed, :rng_method, :index_offset)` (probe); `docs/todo.md:37` ("`TrackingContext` carries an `index_offset` so the counter RNG keys on the GLOBAL particle index") and `docs/history/multi_process_step3a_2026_09_04.md`. The field is the one that makes the counter RNG shard-invariant, so the omission matters to anyone reasoning about reproducibility across ranks from this document (hypothesis 2: runtime-doc statements versus code).
Repro: `julia --project=. -e 'include("src/Octopus.jl"); using .Octopus; println(fieldnames(TrackingContext))'` prints 4 fields including `:index_offset`; `sed -n '41,42p' docs/current_runtime.md` names 3.

### LEAD U52-10 [Minor, confidence high] docs/todo.md:57
Claim: The row's named example -- "`loss_report` is exactly that: ... absent from `tracking_task_option_schema()`" -- is false at HEAD; the schema carries `loss_report` (and `artifact`), as `docs/public_api.md:200-201` already says.
Mechanism: `keys(tracking_task_option_schema()) == [:record_turn_times, :luminosity_tracking, :artifact, :loss_report]` (probe); `src/tasks/Tasks.jl:272-273` describes the two keywords' past state in the past tense. The row's general premise survives in a narrower form: `validate_configuration_metadata()` still checks only `Set(keys(tracking_task_option_schema())) ⊆ Set(fieldnames(TrackingTask))` (`src/tasks/strongstrong/interface.jl:2059`), so a public field without an entry is still invisible; the row should say so without the fixed example (hypothesis 3).
Repro: `julia --project=. -e 'include("src/Octopus.jl"); using .Octopus; println(:loss_report in keys(tracking_task_option_schema()))'` prints true; `grep -n "absent from \`tracking_task_option_schema()\`" docs/todo.md` prints 1 line.

### LEAD U52-11 [Minor, confidence high] docs/todo.md:28
Claim: The row states that "no contract reads the `:strong_strong_output` receipt" and that "nothing sweeps `run_artifact_option_schema()`"; both are false at HEAD, and the row's own residual is stated only inside the contract's docstring.
Mechanism: `src/contracts/Contracts.jl:399-420` defines `_output_receipt_gaps`, "DERIVED from the metadata" over `[:RunArtifact => run_artifact_option_schema(), :TrackingTask => ..., ...]` (lines 645-650), requiring every option whose consumer is an output receipt to be carried by that receipt; lines 655-669 read `:run_artifact_output` (`append`, `continued`, `capacity`, `record_turn_modulation`, `recording`), `:tracking_output` and `:strong_strong_output` (`channels`). The docstring (lines 417-419) names what is left ("options whose consumer is not an output receipt (`:bpm_reading` ...) ... belong to the schema-driven sweep of `docs/todo.md` row 28"), so the open remainder is narrower than the row claims and the row was not updated when the 2026-10-16 fix batch landed the sweep (hypothesis 3).
Repro: `grep -n "strong_strong_output\|run_artifact_option_schema" src/contracts/Contracts.jl` prints 4 lines; `grep -n "no contract reads the \`:strong_strong_output\`" docs/todo.md` prints 1 line.

### LEAD U52-12 [Minor, confidence high] README.md:66
Claim: The spectral-solver paragraph cites `docs/theory/spectral_sine_poisson_solver.md` for the recommended flat-beam grid "(127,383) with `domain_factor=8`" and "~1.4x PIC cost"; the theory note contains neither number, which live in the history record (`docs/history/strong_strong_spectral_optimization_history.md:103-104` and `:127`).
Mechanism: The README's own rule (`README.md:7-9`) is that dated measurements live in `docs/history/`, so the citation points a reader at the derivation note for a benchmark decision it does not record; the history record also carries a competing "Recommended production setting: grid = (128, 1024), domain_factor = 16" at line 322 (both under 2026-07-23 headings; the frozen record is outside this region -- seam), so the README's number has a record but not the one cited (class 14: numbers with a mis-targeted citation).
Repro: `grep -c "383\|domain_factor" docs/theory/spectral_sine_poisson_solver.md` prints 0; `grep -n "(127, 383)\|(127,383)" docs/history/strong_strong_spectral_optimization_history.md` prints 4 lines.

### LEAD U52-13 [Minor, confidence high] docs/README.md:3
Claim: The index claims to be "the map of every document in `docs/`", but `docs/history/gpic_wobble_capture_2026_08_19.txt` is not in it, and the suite's index check cannot see that or a worse case: it covers `.md` files only and matches by basename substring, so a new `U1_report.md` or `INDEX.md` in an undeclared directory passes as indexed.
Mechanism: `test/runtests.jl` ~214-232: `endswith(f, ".md") || continue` and `occursin(f, index)` with `f` the file name, not its path; `docs/README.md` already contains the substrings `U1_report.md` (twiss unit reports) and `INDEX.md` (crab-noise bundle), so any future file of those names anywhere under `docs/` satisfies the rule, defeating the wholesale-marker discipline the testset was rebuilt for (class 13, an instrument that cannot see the defect it names; out of hypothesis for the test-quality half). The `.txt` evidence file is cited only from `docs/todo.md:59`.
Repro: `julia --startup-file=no result/comprehensive_audit_2026_10_18/probes/U52/index_rule.jl` prints `NON_MD_UNINDEXED=1 ["history/gpic_wobble_capture_2026_08_19.txt"]` and `BASENAME_WEAKNESS U1_report.md in index=true INDEX.md in index=true new dir relpath in index=false`; durable form: `grep -c gpic_wobble_capture docs/README.md` prints 0 and `grep -c 'endswith(f, ".md") || continue' test/runtests.jl` prints 1.

### LEAD U52-14 [Minor, confidence high] docs/guides/development_workflow.md:25
Claim: The guide lists the test-only dependencies as `ForwardDiff`, `Symbolics`, `Logging`, `MPI`, `MPICH_jll`; `Project.toml`'s test target also carries `Printf` (added 2026-09-14 for the dry-run testset that includes `validation/twiss_dispersion_identities.jl`).
Mechanism: `Project.toml` `[targets] test = ["Test", "ForwardDiff", "Symbolics", "Logging", "MPI", "MPICH_jll", "Printf"]` with the explanatory comment above it; `docs/todo.md:20` records "`Printf` becomes a test dependency". A developer stacking a scratch environment per the guide's step 3 ("Iterating on one testset") from this list lacks `Printf` for that testset (class 2, a hand copy of the target list).
Repro: `grep -n '^test = ' Project.toml` prints a line containing `"Printf"`; `grep -c Printf docs/guides/development_workflow.md` prints 0.

### LEAD U52-15 [Minor, confidence high] README.md:136
Claim: The root README says `test/examples/` holds "configurable harnesses of the same two cases"; there are three harnesses, the third (`crab_cavity_noise.jl`) since 2026-10-14.
Mechanism: `ls test/examples/` lists `crab_cavity_noise.jl`, `strong_strong_tracking.jl`, `weak_strong_tracking.jl`; `docs/todo.md:22` records the harness landing and `docs/registry_snapshot.md:331` the catalogued example it pairs with. The README's Examples section was not revisited when the third pair landed (class 14).
Repro: `ls test/examples/*.jl | wc -l` prints 3; `grep -n "same two cases" README.md` prints 1 line.

## Clean

Checked and found sound, with what was compared:

- **Registry snapshot freshness** (hypothesis 1): `registry_snapshot_markdown()` regenerated in
  script mode equals the committed `docs/registry_snapshot.md` byte for byte
  (`SNAPSHOT_EQUAL=true`). The 31 kinds, 6 methods, 4 solvers, 6 policies, 19 contracts,
  2 analyses, 5 catalogue entries and 2 tasks it lists match `summarize_registry()`.
- **Index completeness** (hypothesis 1): under the suite's own rule and under a stricter
  relative-path rule, 0 of the 461 non-checkpoint `.md` files under `docs/` are unindexed; the
  three `indexed-wholesale` markers name existing directories; all 8 design notes, 21 theory
  notes and 6 guides have entries. (Only the one `.txt` evidence file is outside the index,
  U52-13.) The `.ipynb_checkpoints/` directories under `docs/` and `src/` are gitignored
  (`.gitignore`) and skipped by both the index check and the source-map check.
- **public_api.md names** (hypothesis 2): 146 of 146 `?Name` entries defined, exported and
  documented. Keyword surfaces match the prose: `SpectralNoise`, `spectral_turn_table`
  (including `slot`, `amplitudes`, `f_rev`, `T`, `name`), `RunArtifact` (`append`, `capacity`,
  `record_turn_modulation`), `BPMObserver(...; artifact=)`, `CoordinateSnapshotObserver(;
  name=)`, `MomentOutput(path; name=)`, `TwissDispersionAnalysis(strict=, closed_orbit=)` (14
  options), `Beam(n, policy, Float32)`, the typed element forms, `LongitudinalSlicing(method=
  :normal_quantile)`. The lock (`<path>.lock`, `src/tasks/RunArtifact.jl:141,485,599`), the
  ledger's `rng_seed`/`rng_method` columns (`:465`, `:704-705`) and the PARTIAL slot cursor
  `elements_valid_through` (`:101`) exist as described. `validation/
  soft_gaussian_pic_comparison.jl` exists.
- **current_runtime.md backend and default claims** (hypothesis 2): policy defaults, PIC
  (`0.50`/`0.25`, `:wavefront`, `:slice_pair`), Gaussian and spectral `:wavefront` defaults match;
  the CUDA PIC pool cleanup "every 16 slice-pairs, below 12%" is `check_every=16,
  threshold=0.12` (`src/tasks/strongstrong/pic_cuda.jl:814`); `_SPECTRAL_SLICED_LOOP`,
  `-expm1`, `GPUExecutionPolicy` as listed policy, `test/nightly_suite.sh`, the harness
  environment variables (`OCTOPUS_PIC_LONGITUDINAL_KICK`, `OCTOPUS_PIC_LUMINOSITY_EVERY`,
  `OCTOPUS_PIC_SLICE_PAIR_GREEN_*`, `OCTOPUS_PIC_BATCH_MODE`, and the refused `OCTOPUS_MP`)
  are read by `test/examples/strong_strong_tracking.jl`; `OCTOPUS_BENCH_MPI` by
  `profiling/benchmark_track_cpu.jl`; "Current Limitations" (no automatic `validate`/`analyze`
  in `execute!`) agrees with `src/tasks/Tasks.jl` and `StrongStrong.jl` (no such calls).
- **The rounding-class table after 2026-10-18** (hypothesis 2): the prose of
  `docs/current_runtime.md:191-209` was compared with `_cross_backend_rounding` of all 31
  registry examples (probe table): marker and aperture every coordinate untouched; straight
  drift momenta untouched, x/y/z ulp 8; thin dipole/quadrupole and the three kickers px/py
  bitwise; accelerating cavity px/py bitwise with z/pz ulp 128; damping-only radiation all
  bitwise; dispersion maps and the identity matrix return untouched coordinates; pz untouched
  through every magnet, the solenoid and the patch; bounds 4 (thin multipole/sextupole,
  xy_coupling), 8 (chromaticity kick, dispersion maps, crab and RF cavities, round thin strong
  beam, patch, drift), 32 (straight magnets with content, the `:line` example), 64 (round
  Gaussian strong beam; the curved frame without pole faces), 128 (solenoid; accelerating
  cavity), 16384 (both Lorentz boosts) -- every stated class and bound agrees, including the
  unit-K values (bend 64, solenoid 128). The line composition rule is the members' maximum
  (`src/track/Track.jl:343-360`), as todo row 36 states. The 2026-10-18 fix record names
  measurements (630 vs 2048, 2-3 vs 8) and no class change, consistent with the prose.
  Not measured here: the non-registry shapes (elliptic strong beam 2048, pole-face bend 8192,
  misalignment 1024).
- **knob_control.md** versus code: the friendly constructors refuse a knob expression with the
  directed error the note describes (`knob_control.md:123-128` is TRUE, despite the 2026-10-16
  "stores its inputs as given" precision rule); the three node types, `list_knobs`,
  `knob_epoch`, `reset_knobs!`, `knob_to_expr`/`knob_expression` exist and are exported;
  `knob_report` has the two methods of section 2a; the script-mode Symbolics activation is the
  include at the bottom of `src/knobs/symbolic.jl` (`_HAS_SYMBOLICS_SCRIPT_MODE`, line 329-335)
  as both the note and the workflow guide say.
- **AGENTS.md routing and source map** (hypothesis 3): all six guides the routing table names
  exist; every top-level `src/` directory (13 plus `tasks/strongstrong`) has a bullet, and the
  suite derives the list from `readdir` (`test/runtests.jl:259-267`); `summarize_registry()`
  lists the strong-strong solvers; the Core Objects' abstract roots are in
  `src/knowledge/Knowledge.jl` as stated; the matrix is a superset of
  `docs/design/testing_lanes.md` section 3 (the extra rows -- element metadata, examples,
  validation, read-only -- contradict nothing there, apart from the timing clause of U52-3).
- **ci.yml versus testing_lanes.md** (hypothesis 3): the workflow runs the default (full) lane
  at `--threads=4` on `ubuntu-latest` with a floating `'1.12'`, CPU only; the design note's
  section 3 says CI has no GPU and the full gate with CUDA active is local-only; the suite's
  default lane is `full` and an unknown lane errors (`test/runtests.jl:13-20`); CUDA testsets
  are gated by `CUDA_TESTS_ACTIVE = _HAS_CUDA && CUDA.functional()` (`:132`), as the workflow
  guide says. The workflow's "CI segfault" tally row exists (`docs/todo.md:79`).
- **Guides versus code**: `_HAS_CUDA` in `src/beam/Beam.jl:9`; `register_friendly_alias!`
  (`Knowledge.jl:495`); `_symplecticity_contract_cases` (`Contracts.jl:1781`); the testsets
  "The placeholder and deprecated policies actually run", "Configuration rejection", "every
  public configuration schema is exported", "Thin elements, markers and RBEND", "Element
  parameter effectiveness" (with its `metrics[:checked] >= 530` ratchet), "One precision rule",
  "Cross-backend rounding classes" exist; `src/contracts/mpi_pic_consistency_child.jl` exists;
  `TwissExternalReferenceContract(; tolerance_scale)` and the `mpiexec` keyword exist;
  `src/analysis/twiss_dispersion_type.jl` is included before `src/elements/Elements.jl` and the
  ForwardDiff rules at the bottom of `src/Octopus.jl`; the placeholder-analysis kind list in
  `contracts_and_analyses.md:95-97` (8 kinds) equals the snapshot's `PlaceholderAnalysis` set,
  and the 23 declaring kinds are the complement; the index walk, snapshot compare and source-map
  tripwires sit in "Architecture integrity" (`:163`) before the first `_lane_gate`, so the fast
  lane does run them (documentation.md:66-67 holds).
- **README numbers with records**: 0.310 s/turn (`strong_strong_spectral_optimization_history.md:10,126`);
  0.324 s/turn as "mean over 60-120" of a 120-turn CUDA run is the archive's 0.3238
  (`todo_ledger_archive.md:335-337`); the soft-Gaussian "~0.23 s/turn" is the 0.2280 row of
  `strong_strong_gaussian_optimization_history.md:30` (the production benchmark's 0.239 is the
  later, consistent number); the gpic "48x48 matches plain PIC at 128^2" is
  `gaussian_subtracted_pic_solver.md:689`; the six paper scripts, `profiling/cuda_device_profile.jl`,
  the four listed validation scripts and `validation/README.md`'s "Paper Reproduction Drivers"
  section exist; `OCTOPUS_RUN_GPU_CONTRACT` is read by `validation/tracking_backend_consistency.jl`.
- **Open todo rows whose premise holds at HEAD** (hypothesis 3), each with the line that
  shows it: 27 (the stateless-rule tripwire, `test/runtests.jl:11086`); 30 (examples' `result_dir`
  default `result/<seed>` with no environment switch, `examples/*.jl:47,71,178`; the harnesses
  read `OCTOPUS_RESULT_DIR`); 31 (receipt entries carry `element = string(nameof(typeof(w.base)))`
  only, `src/elements/turn_modulated.jl:1660,1693`); 32 (premise true; the `WhiteNoise`
  docstring now states the `rng_id = 0` convention, so the row's first remedy is partly done --
  noted, not a lead); 33 (`_masked_global_sum` in `_moment_observer_row`, `BeamObservers.jl:1079,1303`);
  34 (`_mp_rank()` answers 0 outside a scope, `Policies.jl:538`); 36 (max-of-members rule,
  `Track.jl:343`); 47 (`strong_beam_<i>` labels, `Tasks.jl:1357,1483`); 51 (no
  `default_provenance` in `src/`); 54 (no `FFTW.set_num_threads` in `src/` or `profiling/`);
  53's closure (derived walks, `interface.jl:1902-2249`).

## Unchecked

- `docs/current_runtime.md:37-39` ("`TrackingTask` normalizes compiled runtime output to a flat
  tuple"): not traced through `_runtime_entries`; with `CompositeLine` wrappers the tuple is not
  flat in the literal sense. Style-level; left unverified.
- `docs/current_runtime.md:452-453` (`:grid_free` CPU-only) and `:617-621` (CUDA equal-count
  slicing by host-side sort): the option metadata lists both backends for `method`; the
  `sortperm` at `slicing.jl:448-453` was seen but not confirmed to be the CUDA route. Not probed.
- The strong-strong solver internals of `docs/current_runtime.md:434-747` (cuFFT stack shapes,
  compact versus indexed buffers, stream ordering) were read against the prose only; apart from
  the defaults and the pool-cleanup constants nothing there was executed.
- The ulp bounds of non-registry shapes (elliptic strong beam 2048, pole-face bend 8192,
  misalignment 1024): relied on `docs/history/beam_beam_fixes_2026_10_18.md`, not re-measured.
- `docs/knob_control.md` semantics beyond names and the friendly-constructor refusal (operator
  whitelist, `pi`/`NaN` name rejection, cycle detection, non-smooth derivative refusals): not
  probed.
- The per-record one-paragraph summaries of the 100+ history entries in `docs/README.md`
  419-1173 were read but compared with their records only where a lead pointed (U52-4, U52-5,
  U52-7, U52-12); the rest are unverified summaries.
- todo rows 35 (a quiet-machine benchmark) and 58 (Bmad reference cases) have premises that
  cannot be checked against this tree.
- No suite testset was executed through the stage runner; the gate itself was not run.
- `docs/design/testing_lanes.md`, `docs/experiences.md` and `docs/comprehensive_audit.md` are
  outside the region and were consulted only where a lead needed them (seams noted in U52-3,
  U52-6, U52-12).
