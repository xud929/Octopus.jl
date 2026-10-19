# U6: interface.jl (strong-strong task, options, caches)

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every claim
below is a LEAD, not a finding. Dates: read and probed 2026-10-18/19.

## Region

- `src/tasks/strongstrong/interface.jl`, lines 1-3432 (the whole file; 3432 lines), read line by line.

Cross-file material consulted only to settle what the region depends on (not audited): `src/tasks/Tasks.jl`
`_runtime_entries`/`_bind_apertures`/`_bind_survey`/`_validate_reference_chain` (1647-1720, 1786-1880,
1972-2010, 2027-2050), `tracking_task_option_schema` (281-330); `src/beam/Beam.jl` `_resolve_execution_policy`
and `configuration_report(policy, rep)` (337-372, 476-500); `src/policies/Policies.jl` audit API (95-200);
`src/elements/rf_cavity.jl` (55-70, 112-122, 418-445); `src/elements/aperture.jl` (199-235, 283-300, 473-500);
`src/tasks/strongstrong/slicing.jl` (120-165); `src/contracts/Contracts.jl` (3660-3685, 3743-3775);
`docs/design/multi_process_policy.md` (112-140), `docs/design/run_artifact.md` (52-66); the previous audit's
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U5_report.md` lead list (U5-1..U5-15).

## Provenance

READ (line by line, in these chunks): interface.jl 1-400, 401-800, 801-1200, 1201-1600, 1601-1840,
1841-2050, 2051-2500, 2501-2950, 2951-3432.

EXECUTED (scratch: `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U6/`,
each `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`, logs beside the scripts):

- `p1_rf_survey_twin.jl` (p1.log): compiled `ThinRFCavity` through `TrackingTask` vs `_split_strong_strong_line`:
  every field equal except `ds_turn` = 100.0 (TrackingTask) vs NaN (strong-strong). Control `(ip, dr)` vs `(dr)`,
  one turn, same `rng_id`: max|dz| = 0.0, max|dpz| = 0.0. With the cavity: max|dz| = 0.19856538602380028,
  max|dpz| = 0.011184750063824226 (sigma_z = 1e-2). Harmon cavity: TrackingTask ran; StrongStrongTask refused
  with "ThinRFCavitySpec(harmon=...) has no frequency until a task line's circumference resolves it; compile
  through a TrackingTask, or give frequency= for standalone use". (The script's last section aborted on my own
  inconsistent beta0/gamma0 pair; redone in p7.)
- `p2_aperture_record.jl` (p2.log): strong-strong compiled `Aperture` record type `Nothing`, `element_id = 0`;
  TrackingTask compiled record `LossRecord{Vector{Int32},Nothing,Vector{String}}`, `element_id = 1`.
  `hasmethod(loss_record, (StrongStrongTask,)) = false`. Default policy: refused at the first collision with
  "non-finite particle coordinate(s) detected ... 2 of 8 macroparticles ... Inspect upstream tracking for the
  source of the divergence". Inside `allow_lost_particles`: 2 of 8 NaN, no count, no warning; artifact
  top-level groups `["execution", "luminosity"]` (no `/losses`); constructor log records: 0. The same beam
  through `TrackingTask((ap,))`: `loss_summary` = 2 dead, 2 logged, 0 unattributed, by_aperture [2] "COLL_A".
- `p3_knob_invalidation.jl` (p3.log): `_has_knob_parameters((ip, qf)) = true`, `((ip, d2)) = false`; after
  `set_knob!` cache1 recompiled (kepoch 0 -> 1), cached-vs-fresh max|dx| = 0.0, max|dpx| = 0.0, positive control
  old-vs-new max|dpx| = 1.2307740544975144e-7; after `set_param!(d2, :L, 2.0)` cache2 recompiled (sepoch 0 -> 1),
  cached-vs-fresh beam-2 max|dx| = 0.0; plan_cache2 size 1 (line 2's leading block is empty, so one plan);
  `configuration_report(task, ...)` leaves a current cache object identical.
- `p4_receipts.jl` (p4.log): duplicate probe name under an artifact: refused ("duplicate probe name "X" under
  /moments"), receipts recorded for the refused run = `[:strong_strong_diagnostics, :run_artifact_output,
  :strong_strong_output]`, `:strong_strong_output` values `(artifact = ".../u6_p4_dup.h5", channels = ["ip"])`,
  `next_turn = 0`, artifact handle closed. Normal run with `CPUThreadsExecutionPolicy(threads=2)` and
  `GaussianPoissonSolver(batch_mode=:sequential)`: `cpu_logical_workers => (workers = 2, pool_threads = 4)`,
  `gaussian_pair_schedule => (batch_mode = :sequential, requested = :sequential, pairs = 9, ...)`,
  `pic_luminosity_schedule => (turn = 0, evaluated = true, schedule = :every_turn)` (in a Gaussian-only run).
  Inferred policy report: `[(:threads, :auto, 4, :resolved)]`. Schedule memo: task A turn 0 -> 1 predicate call,
  task B turn 0 (same `PredicateSchedule` object) -> 0 calls.
- `p5_static_checks.jl` (p5.log): `validate_configuration_metadata() = true`; both `default_poisson_solver=A`
  and `poisson_solver=B` -> stored solver is B (true); ACCEPTED: `PICPoissonSolver(grid_extent=:sigma,
  grid_extent_sigma=Inf)`, `(slice_pair_green_growth=Inf)`, `(grid_quantize=Inf)`, `(kbb2=Inf)`,
  `GaussianPoissonSolver(kbb1=NaN)`, `(luminosity_scale=-1.0)`; refused: `slice_pair_green_growth=NaN`,
  `min_transverse_extent=Inf`, `min_sigma=Inf`; unknown keywords -> `MethodError` (task and solver);
  task schema keys `(:artifact,)`; public keywords `[:policy, :seed, :default_poisson_solver, :poisson_solver,
  :luminosity_path, :luminosity_append, :luminosity, :artifact, :diagnostics, :record_turn_times]`;
  `CPUThreadsExecutionPolicy().threads = :auto`; `GPUExecutionPolicy().threads = 256, .blocks = 256`;
  slicing report marks `resolution`/`positions` `:inactive_dependency` under `:equal_width` and `:equal_count`;
  Gaussian docstring signature block does not list `luminosity_schedule`.
- `p6_cuda_launch_cost.jl` (p6.log, CUDA functional): `_resolve_cuda_pic_configuration` 1.7 us / 1600 B per
  call with a `CUDAPICLaunchConfig`, 0.76 us / 80 B without; `_with_solver_execution_configuration`
  1.85 us / 2208 B and 0.82 us / 688 B.
- `p7_followups.jl` (p7.log): two ring cavities from e0 = 1 GeV and 2 GeV: TrackingTask refused ("cavity
  reference chain broken at the ring cavity at s = 200.0"), StrongStrongTask ACCEPTED and tracked one turn
  (z finite). `loss_summary(rep, ::StrongStrongTask)` dispatches to `loss_summary(rep::Phase6DRep, record)`
  (aperture.jl:669) and throws `MethodError: no method matching loss_counts(::StrongStrongTask...)`.
  Downstream fate of the accepted non-finite options (two turns, 256 particles, grid 16x16, 2 slices):
  `grid_extent_sigma=Inf` -> ERROR "non-finite value detected ... but all ... coordinates ... are finite";
  `slice_pair_green_growth=Inf`, `grid_quantize=Inf`, `kbb2=Inf` -> ERROR "non-finite particle coordinate(s)
  detected in the source/field particles"; `kbb1=NaN` -> same ERROR after 129/256 of beam 1 were already NaN;
  `luminosity_scale=-1.0` -> ran silently, `/luminosity/ip` values `[-2.16e10, -1.10e9]`.
- `p8_duplicate_labels.jl` (p8.log): two collisions labelled `:ip` in each line with an artifact -> refused by
  `HDF5.API.H5Error: Error creating group /luminosity/ip ... name already exists`.

## Leads

### LEAD U6-1 [Major, confidence high] src/tasks/strongstrong/interface.jl:3270-3287
Claim: the strong-strong line compile never binds the survey channel, so a `ThinRFCavity` in a `StrongStrongTask` line tracks the bare-compile `ds_turn = NaN` (s = 0 boundary) model while the identical line through `TrackingTask` tracks the slip-corrected one, and the two tasks disagree on `z`/`pz` after one turn.
Mechanism: `_split_strong_strong_line` calls only `_append_runtime_line!` per element; the `TrackingTask` compile (`_runtime_entries`, src/tasks/Tasks.jl:1665-1668) follows that with `_bind_apertures`, `_bind_survey` and `_validate_reference_chain`. `_bind_survey` is what replaces the NaN `ds_turn` of `ThinRFCavity(spec)` (rf_cavity.jl:418-430) with the arc from the previous kick; `_rf_kick` adds `ds_turn * g(pz)` to `z` only when `ds_turn` is finite (rf_cavity.jl:150-156). The cavity's own docstring says the finite value "is bound by `_bind_survey` when a task compiles the line" -- a `StrongStrongTask` is a task, and it does not. The `harmon=` form, whose frequency only the bind can resolve, refuses in a strong-strong line with "compile through a TrackingTask", which names the gap but does not close it; the `frequency=` form tracks silently with the other model. No test, harness or ledger row pairs an RF cavity with a strong-strong line (grep of test/runtests.jl, test/examples/, validation/, docs/todo.md, docs/experiences.md); the survey design note never mentions strong-strong. Out of the three briefed hypotheses (it is the compile step itself, not its cache).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p1_rf_survey_twin.jl` -> `ds_turn TrackingTask=100.0 StrongStrong=NaN`; control `max|dz| = 0.0`; cavity `max|dz| = 0.19856538602380028`, `max|dpz| = 0.011184750063824226` (sigma_z = 1e-2).

### LEAD U6-2 [Major, confidence high] src/tasks/strongstrong/interface.jl:3270-3287 (task fields 2329-2352)
Claim: a `StrongStrongTask` has no loss record, so an aperture in either line compiles kill-only (`record::Nothing`, `element_id = 0`): particles it kills are uncounted, unattributed, absent from the artifact, and reported by the solver's default fail-fast as an upstream divergence.
Mechanism: the TrackingTask compile sizes a `LossRecord` per representation and binds every aperture to it (`_ensure_loss_record!`, `_bind_apertures`, Tasks.jl:1652, 1666); the strong-strong compile does neither and the task type carries no `loss_record` field, so `Aperture{F,M,Nothing}` takes the kill-only `track_particle` (aperture.jl:289-296). Consequences measured: 2 of 8 particles placed outside `x_limit` become NaN with no count and no warning at construction or execution; the artifact carries `["execution", "luminosity"]` only, though the task schema's `artifact` meaning (interface.jl:1844) calls it "THE luminosity/loss/probe output"; `loss_record` has no method for the task and `loss_summary(rep, task)` falls into the `(rep, record)` method and throws a `MethodError` on `loss_counts(::StrongStrongTask)`; without `allow_lost_particles` the first collision throws "non-finite particle coordinate(s) ... Inspect upstream tracking for the source of the divergence" for a kill the user configured. The docstring at :2565 ("apertures divide (3c)") describes a feature the task does not have. Class 6 (silent degradation: dropped particles with no accounting) and class 14 (claims). Hypothesis 2's "loss record" invalidation path has nothing to invalidate here.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p2_aperture_record.jl` -> `strong-strong compiled Aperture: record type = Nothing, element_id = 0`; `hasmethod(loss_record, (StrongStrongTask,)) = false`; `beam1 NaN x after one turn: 2 of 8`; `artifact top-level groups: ["execution", "luminosity"]`; `constructor log records: 0`; then `p7_followups.jl` -> `loss_summary(b1.rep, ss) -> throws: MethodError: no method matching loss_counts(::StrongStrongTask...`.

### LEAD U6-3 [Moderate, confidence high] src/tasks/strongstrong/interface.jl:3270-3287
Claim: the reference-chain check that refuses two cavities declaring inconsistent references in one line runs only for `TrackingTask`, so a strong-strong line accepts and tracks the "two-E0" lattice the theory note calls unrepresentable.
Mechanism: `_validate_reference_chain(task.elements)` is called from `_runtime_entries` (Tasks.jl:1668) and nowhere in the strong-strong compile path; the strong-strong preflight (:2646-2665) runs the turn-window, beam-eltype and seed-drift walks but not this one. Same omission family as U6-1; listed separately because the fix is a separate call.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p7_followups.jl` -> `TrackingTask: refused: ... cavity reference chain broken at the ring cavity at s = 200.0`; `StrongStrongTask: ACCEPTED (tracked one turn, z finite = true)`.

### LEAD U6-4 [Moderate, confidence high] src/tasks/strongstrong/interface.jl:3024,3049-3082
Claim: `_LUM_SCHEDULE_MEMO` is one process-global slot keyed by `(objectid(schedule), turn)` and never by task or `execute!`, so a second task that shares a schedule object inherits the first task's verdict at the same turn without consulting the schedule and without recording a receipt.
Mechanism: the memo hit at :3054-3056 returns before `should_run` and before `_record_execution!`; the slot is never cleared at `execute!` entry. The comment at :3044-3048 accepts sharing WITHIN one turn of one task ("two solvers sharing one schedule object still owe the same answer"); across tasks a stateful `PredicateSchedule` (the case the memo was written for, U5-2) now sees one of its two tasks skip it, and the receipt-based effectiveness evidence for that task is missing. Also survives `execute!(...; start_turn=...)` repositioning onto the memoised turn. Class 7 (cache not invalidated on every producer path). Trigger is narrow (one schedule object in two tasks, same turn number), hence Moderate rather than Major.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p4_receipts.jl` -> `predicate calls: task A turn 0 -> 1; task B turn 0 (same schedule object) -> 0`.

### LEAD U6-5 [Moderate, confidence high] src/tasks/strongstrong/interface.jl:2707-2712 (comment and placement)
Claim: the `:strong_strong_output` receipt (with `:strong_strong_diagnostics`) is recorded for a run that the observers' prepare then refuses, contradicting the comment beside it ("a prepare refusal leaves no output receipt claiming a run").
Mechanism: the S4-2 move put the receipt after `prepare_run_artifact!` but before the `prepare_observers!` block at :2720-2733, whose refusals (duplicate probe name, continued-group column mismatch) close the artifact and rethrow with no turn run; the receipt saying `channels = ["ip"]` stays in the audit. The diagnostics receipt's early position is a recorded owner item (U4-3); the output receipt's half-move and the comment's claim are not. Class 11 (receipts must record what ran) and 14. Cross-file seam: `:run_artifact_output` is likewise recorded by the artifact's own prepare before the observers refuse (src/tasks/RunArtifact.jl); noted, not audited.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p4_receipts.jl` -> `refused: true :: ArgumentError: duplicate probe name "X"`; `receipts recorded for the refused run: [:strong_strong_diagnostics, :run_artifact_output, :strong_strong_output]`; `count(:strong_strong_output) = 1`; `task.next_turn after refusal = 0`.

### LEAD U6-6 [Minor, confidence high] src/tasks/strongstrong/interface.jl:2388-2414 (docstring 2282-2284, schema 1839-1853)
Claim: `poisson_solver` silently overrides `default_poisson_solver` when both are passed, is absent from the task docstring (which instead advertises the retired `luminosity=nothing` keyword), and like `policy`, `diagnostics` and `record_turn_times` has no entry in `strong_strong_task_option_schema`, whose subset tripwire (:2047) cannot see an undeclared keyword.
Mechanism: `solver = poisson_solver === nothing ? default_poisson_solver : poisson_solver` drops a non-default `default_poisson_solver` with no warning (hypothesis 1: a request not honoured and not refused); the docstring signature at :2282-2284 lists `luminosity=nothing`, which :2420-2426 throws on, and omits `poisson_solver`, `diagnostics`, `record_turn_times`; the previous audit's U5-4 listed the uncovered keywords and the fix added the subset check only. Class 5 and 14.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p5_static_checks.jl` -> `default_poisson_solver=A AND poisson_solver=B given -> stored solver is B: true`; `StrongStrongTask schema keys: (:artifact,)`; `StrongStrongTask docstring signature line: ["StrongStrongTask(line1, line2; policy=nothing,", "default_poisson_solver=GaussianPoissonSolver(),"]` and the next line of that docstring reads `luminosity=nothing, artifact=nothing)`.

### LEAD U6-7 [Minor, confidence high] src/tasks/strongstrong/interface.jl:1471-1475,1453-1455,1474-1475,991-992
Claim: the solver constructors accept non-finite `grid_extent_sigma`, `slice_pair_green_growth`, `grid_quantize`, `kbb1`/`kbb2` and a negative `luminosity_scale`, while the sibling options `min_sigma` and `min_transverse_extent` refuse non-finite values; the accepted ones fail at the first collision with a message that blames upstream tracking, or (for `luminosity_scale`) write negative luminosity rows silently.
Mechanism: the checks are `T(x) > 0`, `>= 0` or none, which `Inf` passes and `NaN` fails only by accident of comparison; `_optional_solver_value` converts `kbb*`/`luminosity_scale` with no check. Downstream the only tripwire is `_nonfinite_coordinate_error`, whose text ("Inspect upstream tracking for the source of the divergence") is wrong about the cause, and for `kbb1=NaN` beam 1 is already half NaN when it fires. Class 5/6, cheap to close at construction as `min_sigma` does (:1010-1012).
Repro: `p5_static_checks.jl` -> the six `ACCEPTED` lines; `p7_followups.jl` -> `Gaussian kbb1=NaN -> ERROR: ... non-finite particle coordinate(s) ... | NaN x in beam1: 129/256`; `Gaussian luminosity_scale=-1.0 -> ran silently | luminosity rows: (turn = [0, 1], value = [-2.1612337715934696e10, -1.1005267944793425e9])`.

### LEAD U6-8 [Minor, confidence high] src/tasks/strongstrong/interface.jl:1100-1102,1680-1681,3049-3050,3087-3088
Claim: `luminosity_schedule` on both the Gaussian and PIC schemas declares the verbatim-dump consumer `:solver_runtime` (the default), the state the file's own U4-6 note (:1079-1095) says `batch_mode` had to be fixed out of, and the Gaussian solver's consult emits its receipts under the PIC name `:pic_luminosity_schedule`.
Mechanism: `_luminosity_schedule_evaluated` takes `consumer::Symbol=:pic_luminosity_schedule`; spectral passes its own name, the Gaussian gate at :3088 passes none, so a Gaussian-only run records `pic_luminosity_schedule` receipts and no receipt named for the solver whose option it certifies. Effectiveness is separately pinned by the contract's two-collision observable (Contracts.jl:3660-3685), so this is receipt naming and metadata, not an ineffective option.
Repro: `p4_receipts.jl` -> `pic_luminosity_schedule [CPUThreadsBackend] => (turn = 0, evaluated = true, schedule = :every_turn)` in a run whose only solver is `GaussianPoissonSolver`; `grep -n "luminosity_schedule=SolverOptionMeta" src/tasks/strongstrong/interface.jl` shows neither entry names a consumer.

### LEAD U6-9 [Minor, confidence high] src/tasks/strongstrong/interface.jl:1914-1916,1930-1933
Claim: `validate_configuration_metadata` compares the CPU policy's `threads` default and the legacy GPU policy's `threads`/`blocks` defaults to literals (`:auto`, `256`) rather than to the constructed objects, so a constructor-default change on those three passes undetected.
Mechanism: the function's own comment (:2034-2042) states the rule ("a CONSTRUCTED task, not a second copy of the defaults") and the multi-process and CUDA blocks beside these follow it; `CPUThreadsExecutionPolicy()` and `GPUExecutionPolicy()` both construct and expose the fields. Class 13 (the previous U5-14 catalogued the uneven default checks; these two were not in its list).
Repro: `p5_static_checks.jl` -> `CPUThreadsExecutionPolicy().threads = :auto; schema default = :auto`; `GPUExecutionPolicy().threads = 256, .blocks = 256`; `sed -n '1914,1916p;1930,1933p' src/tasks/strongstrong/interface.jl` shows the literals.

### LEAD U6-10 [Minor, confidence high] src/tasks/strongstrong/interface.jl:3316-3328,2695-2706
Claim: two collisions carrying the same label are not refused by name; with an artifact the run dies inside the HDF5 library ("Links/Object already exists") and without one the two share a channel identity silently.
Mechanism: `_validate_strong_strong_blocks` checks that line 1 and line 2 pair label for label but not that labels are unique; `labels` (:2695-2696) is then handed to `prepare_run_artifact!`, whose group creation is the first thing that notices. Cross-file seam (src/tasks/RunArtifact.jl owns the group creation); the by-name refusal belongs to the walk here that already owns the pairing message.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U6/p8_duplicate_labels.jl` -> `refused: HDF5.API.H5Error: Error creating group /luminosity/ip ... name already exists`.

### LEAD U6-11 [Minor, confidence high] src/tasks/strongstrong/interface.jl:891-902
Claim: the `GaussianPoissonSolver` docstring signature block omits `luminosity_schedule`, which the constructor (:1007) takes and the body (:942-947) documents. Documentation-as-claims only (class 14); style-level.
Mechanism: the signature was not updated when the keyword landed 2026-08-19.
Repro: `p5_static_checks.jl` -> `GaussianPoissonSolver docstring signature mentions luminosity_schedule in its signature block: false`.

## Clean

Hypothesis 1 (schema <-> consumer):
- `validate_configuration_metadata()` returns `true` on this tree (p5), so every declared default equals its
  constructor's for the surfaces it builds objects for, and every schema key is a field.
- Every `PICPoissonSolver` and `GaussianPoissonSolver` option has a runtime read outside interface.jl
  (grep of `.<name>` over src/, excluding schema/report reads): e.g. `deposit_method` 46, `batch_mode` 36,
  `virtual_drift` 25, `green_type` 15, `grid_extent` 15, `interaction_grid` 12, `cuda_async` 11,
  `slice_pair_green_growth` 8, `field_derivative` 3, `grid_extent_sigma` 2, `kbb1`/`kbb2` 2 each,
  `include_sigma_xy` as the `Coupled` type parameter; `luminosity_grid` and `luminosity_deposit_method` are
  read through `_pic_luminosity_grid` (14 callers) and `_pic_luminosity_deposit_method` (7 callers).
- Unknown keywords are refused (`MethodError`) on `StrongStrongTask`, `GaussianPoissonSolver`; the retired
  `seed`, `luminosity`, `luminosity_path`, `luminosity_append` throw by name (:2410-2426).
- `configuration_report(::LongitudinalSlicing)` marks `resolution` inactive unless `:equal_area`, and the one
  consumer of `resolution` is `_longitudinal_slices_equal_area` (slicing.jl:137-141); `positions` inactive
  unless `:specified` (p5).
- `_pic_option_active` implements every declared PIC dependency (`grid_extent_sigma`, `batch_mode` via
  `_pic_batchable`, the two Green-cache ratios, the three `cuda_*` chains) -- compared entry by entry against
  the `dependencies=` tuples at :1617-1673.
- `_solver_divides` and `_strong_strong_luminosity_evaluated` have methods for all four solvers
  (gaussian_pic.jl:132/200, spectral.jl:242/330), so the `true` fallback at :3084 never produces NaN rows.

Hypothesis 2 (compiled-blocks cache):
- Knob-epoch invalidation on the knob-dependent line only and spec-epoch invalidation (`set_param!`) on a
  knob-free line both recompile and give results bitwise identical to a fresh task (0.0) with a positive control
  of 1.23e-7 (p3). `_has_knob_parameters` sees through the `StrongStrongCollision` marker. The plan caches are
  emptied at the refill (:3253) and the `StrongStrongBlocks` physics/observer tuples are rebuilt with the blocks.
- `configuration_report(task, b1, b2)` reuses a current cache object (p3) and has no other side effect.
- Policy change: `_split_strong_strong_line` takes no policy input and the compiled entries are the spec
  compile's host objects, so no cache key is needed for it (read, not measured; the plan key at :3226 matches
  the TrackingTask key shape at Tasks.jl:1456).
- The one-slot memo within a single task: gate and solver agree, one evaluation and one receipt per
  (schedule, turn) (p4 normal run).

Hypothesis 3 (receipts):
- `cpu_logical_workers` records `workers = 2` for `threads=2` with a 4-thread pool; `gaussian_pair_schedule`
  records `batch_mode = :sequential, requested = :sequential` for the sequential request; the inferred-policy
  report resolves against the representation (`(:threads, :auto, 4, :resolved)`, Beam.jl:476) rather than
  echoing the default object (p4).
- The failure path of `_execute_strong_strong_task!`: on the observers' refusal the artifact handle is closed
  and `next_turn` unchanged (p4); the `finally` ordering (observers flushed, then artifact closed, neither
  replacing the original error) read sound.
- CUDA PIC launch resolution per collision: 1.7 us / 1600 B with a config, 0.76 us / 80 B without (p6) --
  not a per-particle or per-element scaling cost; not a lead.
- Previous audit's U5-1..U5-15 against this file: all addressed in the text read (U5-2 memo, U5-4 constructed
  task, U5-5 `grid_extent_sigma`, U5-6 schema-less solver identity, U5-7/8 guard and preflight resolution,
  U5-11 export, U5-12 aliases, U5-14 CUDAPICLaunchConfig default check, U5-15 docstring), except the two
  literal comparisons now in U6-9 which U5-14 did not list.

## Unchecked

- MPI-divided behaviour (`_reject_undivided_solver`, `_reject_unsharded_strong_strong_features`, the
  `_mp_bcast` in `_luminosity_schedule_evaluated`, shard offsets at :2866-2867): read only; no `mpiexec` run.
- `_resolve_cuda_pic_configuration`'s device-maximum refusal and `_cuda_pic_threads`' receipts under a task on
  CUDA: not executed (only the host-side cost in p6); CUDA-side consequences of U6-1/U6-2 not run.
- `_nonfinite_coordinate_error`'s CUDA host-copy branch and the `bad == 0` message: read only (the
  `grid_extent_sigma=Inf` case in p7 did exercise the `bad == 0` branch on CPU).
- The site that throws the harmon refusal quoted in U6-1 lies outside the region (not in rf_cavity.jl or
  src/track/ by grep); not located.
- Whether the strong-strong omission of `_bind_survey`/`_bind_apertures`/`_validate_reference_chain` is a
  recorded decision: no row found in docs/todo.md or docs/experiences.md and no mention in the survey design
  note; treated as a gap, not a decision.
- `_execute_strong_strong_segment_pair!` stream synchronisation and NVTX ranges on CUDA: read only.
