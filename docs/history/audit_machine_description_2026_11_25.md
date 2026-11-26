# Scoped neighbour audit of the machine-description campaign (stages 2 to 4 and the reference batch), 2026-11-25

> **Status: closed 2026-11-25 (the record commit that follows the unit commits on `main`). The post-campaign
> standard of [`../comprehensive_audit.md`](../comprehensive_audit.md) ("The
> targeted neighbour audit", owner direction 2026-08-08; `AGENTS.md`, "A fix's
> neighbours are where the next defect is") applied to the machine-description
> campaign recorded in
> [`machine_description_stage2_2026_11_25.md`](machine_description_stage2_2026_11_25.md),
> [`machine_description_reference_2026_11_25.md`](machine_description_reference_2026_11_25.md),
> [`machine_description_stage3_2026_11_25.md`](machine_description_stage3_2026_11_25.md) and
> [`machine_description_stage4_2026_11_25.md`](machine_description_stage4_2026_11_25.md),
> conducted by the stage-5 session on 2026-11-25 with two reading units (U1,
> unit B: the lattice, machine, codec and task-constructor layer; U2, unit C:
> the artifact, observer, schedule, solver and reference-reader layer), 18
> leads, 10 confirmed findings (5 fixed in the batch, 4 ledgered as todo rows
> with their price, 1 carried owner item), 1 unconfirmed owner question, 1
> clean sweep made permanent as a tripwire, 8 refuted or clean by
> measurement; reproductions re-run before recording (each unit's probe logs
> and its red-then-green extracted runs, named in section 5); the gate
> numbers are in the commit messages of the stage-5 tail (the fold's record
> commit and the unit commits 3504192, 0600139, 3bb1800) and in the
> stage record
> [`machine_description_stage5_2026_11_25.md`](machine_description_stage5_2026_11_25.md).**
> Unit reports:
> [`audit_machine_description_2026_11_25_unit_reports/U1_report.md`](audit_machine_description_2026_11_25_unit_reports/U1_report.md)
> and
> [`audit_machine_description_2026_11_25_unit_reports/U2_report.md`](audit_machine_description_2026_11_25_unit_reports/U2_report.md),
> the queue's file:line ground truth (their pointers are of the tree
> 5efe850, the stage-4 tree plus the stage-5 skeleton; the Repro line is the
> durable identity of each lead).

## 1 Executive summary and repository

Tree audited: the stage-4 tree, 1c7ca22 on `main` (pushed 2026-11-25 21:08
EST), read by the units as 5efe850 on their branches (the stage-4 tree, aea4173
being the pre-gate commit of the byte-identical tree, plus the stage-5
skeleton: the `with_overrides` docstring and stubs, the `[MD5-A]`, `[MD5-B]`
and `[MD5-C]` test anchors, no behaviour; unit B's fixes are 37441bf on
md5-B and unit C's 71567d6 on md5-C, replayed onto `main` as 0600139 and
3bb1800). The campaign's commit
range is 2bfab81 (the design note) to 1c7ca22 (the stage-4 record), four
batches recorded the same day: stage 2 added `Lattice`, `ReferenceParticle`,
the `@elements` block and the friendly constructors' knob expressions
(D3, D7, D9, D10, D12 as acceptance, D15 for `TrackingTask` and `analyze`);
the reference batch made `Beam` and the two cavities take `reference =
ReferenceParticle`; stage 3 added `Machine`, the two `StrongStrongTask`
machine forms, the one-turn-matrix forwards and the parity driver
`profiling/machine_description_parity.jl` (D5, the machine half of D7,
D15); stage 4 added the TOML codec (`write_machine`, `read_machine`,
`machine_toml`, `parse_machine`, `src/lattice/toml.jl` and
`toml_hooks.jl`), the artifact's `machine_toml` and `machine_sha256`
columns with `/machine_tables`, and the tasks' `machine` field (D13, D14).
Stage 5 itself (`with_overrides`, D11, unit A) is the batch this audit
rides with, not the batch it audits; its agreement with the guards the
audit changed is noted where it arises.

Findings by severity: one Major (C-1, `AtTurns` compared by identity, so
two independently built solvers scheduling luminosity on equal turn sets
were refused as differently configured; fixed), four Moderate (B-2 with
B-9, a placement override on a hook or collision-marker placement stored,
epoch-bumping, read by no compile and round-tripping through the snapshot,
fixed on the in-place route, the writer and the reader; B-10, an undeclared
override key stored by the placement route and written into a snapshot the
reader refused, fixed; C-2, a lattice whose observers had run no longer
`==` its pristine twin, fixed; C-5, the derived strong-strong kick scale
zero for a zero `r0`, `charge` or `mc2` with only `E0` refused, a carried
owner item), five Minor (B-5, an unknown `StrongStrongTask` keyword naming
the private builder, fixed; B-1b, a `StrongStrongCollision` in a
`TrackingTask` line dying at the first turn with a raw `MethodError`,
ledgered; B-6a, a reloaded `:lumped_radiation` or `:linear6d` spec's
explicit stream id not re-claimed in the reading process, ledgered; C-3,
416 bytes per `execute!` call of a placement-spelled line at a named site,
ledgered with its cure; C-6, a non-digit moment name's message and
`EveryNSteps` printing `stop = typemax(Int)`, ledgered), one Unconfirmed
(B-11, a `BigFloat` override on a typed element narrowed silently at
compile, the convention the suite pins, an owner question). B-6e made a
clean registration sweep permanent as a derived tripwire; B-12 is by design
(the exported-API testset asserts the generator, "Architecture integrity"
the file). Refuted or clean by measurement: B-1 (every walker that can
meet a `LineEntry` wrapping a non-element child, enumerated), B-3 (an
override-only knob makes the task knob-dependent and recompiles at the
epoch), B-4 (every `_element_tuple` call site and the one-turn-matrix
helpers go through the one-lattice door), B-7 (`_lattice_knob_roots`'
narrowing, no caller builds a nested or duplicated root tuple), B-8 (the
fixtures' explicit stream ids), B-6b/c/d (the codec's `Float32`, `Dict` and
`Symbol` seams), C-4 (the artifact's machine readers on a continued,
retuned or multi-rank file).

What moved: five refusals and two equalities, no numeric path. The
in-place override route gained two guards (`_reject_hook_placement_override`,
`_reject_undeclared_override`) and the codec's line table two refusals to
match (B-2, B-10); the three public `StrongStrongTask` forms refuse an
unknown keyword by their own name from a roster read off the builder's
method (B-5); `AtTurns` compares, hashes and `isequal`s by its set (C-1);
`_lattice_structurally_equal` compares an observer that has an
`observer_option_schema` by the schema's values, the configuration view the
snapshot writes (C-2); one suite probe that wrote an undeclared `k1` on a
reversed drift placement as a write-isolation check writes the placement
key `x_offset` and asserts the same property (B-10's blast radius). What
the fingerprints show unchanged: `[the examples' fingerprint rows against
the stage-4 baseline, re-run on the final tree by the orchestrator: CPU
identical / CUDA within the floor, from result/gates/md5/compare/]`; the
units' behavioural fingerprint of the region is the stage-3/4 compiled-
runtime pins re-run green extracted on the fixed trees (section 5).

## 2 Declared scope and coverage ledger

Declared before the units read in depth (the operating brief of the day,
section 5): the diff of the four batches, for each landed symbol its call
sites and sibling files, plus the entry points the records hand over
(stage 3: `_machine_only_lattice`, the two machine forms of
`StrongStrongTask`, `_element_tuple(::Machine)`, the one-turn-matrix
forwards; stage 4: `_ra_machine_snapshot`, `_ra_write_machine_tables!`,
`_ra_machine_text`, `_strong_strong_machine`, `_task_machine`, the codec's
encoder/decoder pairs, `_toml_emit`, the option codec, the
`MomentObserver(; moments)` route; the stage-5 targets: `_element_tuple`'s
callers, the two task constructors, the placement-override guards and the
knob epoch; the reference batch's `Beam` and cavity `reference =` readers),
one cross-cutting pass per seam class. Depth per region: full
line-by-line, targeted (the named symbol and its direct callers), or
inventory (enumerated, read for one property).

| Unit | Responsibility | Inspected by | Depth | Evidence |
|---|---|---|---|---|
| U1 | `src/lattice/Lattice.jl`, `Machine.jl`, `elements_macro.jl`, `toml.jl`, `toml_hooks.jl`; `_element_tuple` and its six call sites in `src/tasks/Tasks.jl`; the `TrackingTask` constructor's machine path and `_task_machine`; the `StrongStrongTask` machine forms, `_strong_strong_task`, `_strong_strong_machine`, `_split_strong_strong_line`, `_append_strong_strong_line!` (`src/tasks/strongstrong/interface.jl`); the placement-override guards and `setproperty!(::LineEntry)` (`src/elements/beam_line.jl`); the knob epoch's readers (`_has_knob_parameters`, `knob_epoch`, `_spec_epoch`) | unit B (agent), by reading and by script-mode probes on the unfixed tree; the orchestrator's reproduction the stage's nine testsets and the campaign's neighbours re-run extracted by the orchestrator on the folded tree (`result/gates/md5/extracted_checks.log`, every block green), the examples' fingerprints re-run | full on the guard family, the codec's line and element tables and value seams, the constructors' doors; targeted on every walker that can meet a `LineEntry` (enumerated by grep) and on the derived machine's roots; inventory on the suite's explicit stream ids and on `elements_macro.jl` (no lead opened) | `U1_report.md` (leads B-1 to B-12, the clean-regions list with a line per walker); probe logs `probe_unfixed.log`, `probe2_unfixed.log`, `probe3.log`, `probe4.log`, `probe5.log`; red runs `red_run.log`, `red_run2.log`; green runs `green_run.log`, `green_run2.log`; the four testsets under `[MD5-B]` |
| U2 | `src/tasks/RunArtifact.jl` (the ledger columns, `_ra_machine_snapshot`, `_ra_write_machine_tables!`, `_ra_check_ledger_columns`, `_ra_contents`, the machine readers); `src/tasks/BeamObservers.jl` (the four schedules, `schedule_option_schema`, `ScheduledObserver`, `MomentObserver` and its `moments` route); `src/tasks/BPMObserver.jl` (state fields); `interface.jl` (`solver_configuration`, `_collision_solver`, the preflights, the schedule and observer walks of `validate_configuration_metadata`); `slicing.jl` (`_strong_strong_kbb1/2`); `Tasks.jl` (`_runtime_entries`, `_execute_tracking_window!`, `_has_accelerating_cavity`); `src/beam/Beam.jl` (`_beam_params`); `src/elements/rf_cavity.jl` (`_fold_reference`, `_check_voltage_route_keywords`); `Lattice.jl`'s equality walker (one branch); the example's `write_machine` rank guard; the parity driver's weak-strong case | unit C (agent), by reading, script-mode probes and an allocation measurement on the unfixed tree; the orchestrator's reproduction the stage's nine testsets and the campaign's neighbours re-run extracted by the orchestrator on the folded tree (`result/gates/md5/extracted_checks.log`, every block green), the examples' fingerprints re-run | full on the schedule family, the equality walker's observer branch and the artifact's machine readers; measurement on the per-`execute!` allocation; by reading on the kick-scale derivation and the cavity readers; inventory on the flat reference spellers (the D12 list) | `U2_report.md` (leads C-1 to C-6, the clean regions); `probe_unfixed.log`, `alloc.log`; red run `red_L1_L2.log`; green runs `green_all.log`, `green_prelude.log`; the two testsets under `[MD5-C]` |

The logs named above are the units' scratch files of the day
(`/tmp/claude-dxu/md5/{B,C}/`), quoted line by line in the unit reports;
`[copied beside the unit reports by the fold, or not: the orchestrator's
call]`.

Not covered, with the reason: the element kernels and the contracts' physics
(no batch of the campaign changed a kernel; the fingerprints are the
receipt); the MPI arm of the example's `write_machine` guard beyond reading
(rank 0 under `Main.MPI`, the harness precedent); the CUDA and MPI arms of
C-3 (the walk runs before the policy is activated, backend-independent; the
stage-3 record measured the same order there); `with_overrides` itself
(unit A's new code, not part of the audited batches: read by U1 for its
refusal wording only, its agreement with the in-place guards pinned by
unit A's tests and by B-2's merge note); the stage records' committed
baseline harnesses (`result/gates/md3`, `md4` compare scripts) were not
re-run by the units, whose fixes add refusals and change no numeric path:
the stage-3/4 compiled-runtime pins ran green extracted on the fixed trees
as the region's behavioural fingerprint, and the examples' fingerprints are
re-run on the final tree by the orchestrator (2026-11-25 21:42 to 21:50 EST, `result/gates/md5/compare/`: all twenty CPU hashes identical to the stage-4 tree's, the fourteen deterministic CUDA rows identical, the six strong-strong CUDA rows inside the same-tree noise: luminosity 1.2e-11 to 2.2e-11 across the trees against 1.3e-11 and 2.2e-11 same-tree, electron moments up to 4.3e-09 against 3.9e-09 and 3.2e-09, proton moments up to 1.1e-09 against 1.2e-09 and 1.0e-09, every table bit-identical on CPU); the multi-line `Beam(...)`
constructions of the suite and the contracts for C-5's blast radius (an
instrumented one-process count was not run on the shared machine, the
finding being an owner item the reference batch already carried); the
`validation/`, `profiling/` and `examples/` scripts for the D12 inventory
(they call `Beam`, which takes `reference =`); a `Dict`-valued element
parameter through the codec (no kind's example holds one, B-6c); two suite
blocks naming `AtTurns` that cannot run extracted ("Non-finite coordinates
fail fast at solver chokepoints", "The run artifact's row cursor ..."):
left to the full gate, neither probes schedule equality.

One pass per seam class: encoder <-> decoder (U1: B-2, B-6, B-10, the line
and element tables and the value rules both ways), declared schema <->
runtime consumer (U2: C-6, the validators before and after; U1: B-10, the
spec route's declared keys against the placement route's acceptance),
several walkers over one line structure (U1: B-1, every `LineEntry`
walker enumerated; U2: C-2, the equality walker), producer <-> consumer
epoch (U1: B-3, an override-only knob through the epoch; U2: C-4, the
artifact's per-`execute!` snapshot of a retuned knob).

## 3 Traceability and reviewed decisions

Each decision of `../design/machine_description.md` the campaign implemented,
the neighbour the audit re-walked for it, and the test, contract or
fingerprint that pins it (suite titles are `test/runtests.jl` testsets;
counts are the units' extracted runs on their fixed trees).

| Decision | Neighbour re-walked | Pinned by |
|---|---|---|
| D3 `Lattice` as a record with its tripwires and structural equality | `_lattice_check_entry_eltype` (B-11: a `BigFloat` override on a typed element narrows at compile, the pinned convention; unchanged); `_lattice_structurally_equal` (C-2: observers compared by their option-schema view; fixed); `_lattice_knob_roots` (B-7: the nested and duplicate refusals, no caller builds either; clean) | "Machine description: a Lattice wraps a line and is accepted where the line is" (42); "... lattice equality is structural and the record prints" (24); "... the numeric-type tripwire follows the compile rule" (the typed-element convention at its lines 20655-20660); "Machine description audit: a lattice whose observers have run is still equal to its pristine twin" (6) |
| D5 `Machine` as a namespace of lattices by name | the six `_element_tuple` call sites, `_collect_contracts`/`_collect_analyses` as keyword defaults run on the raw argument, the one-turn-matrix helpers' `Machine` methods, `_task_machine` after the door (B-4: every route through `_machine_only_lattice`; clean); the derived two-lattice machine's shared roots (B-7: a subset of validated roots, computed after the overlap pre-check; clean) | "Machine description: a Machine holds lattices by name and the implicit one-lattice machine equals the explicit one"; "... a one-lattice machine is accepted where a line is and a machine of several is refused by name"; "... the task records the machine it was given, by spelling" (20) |
| D7 the knob-root tripwire, both halves | `_strong_strong_machine`'s overlap pre-check and `Machine(...)`'s refusal (B-7, measured on roots `md5b_a` and `md5b_a.x`); an override-only knob through `_has_knob_parameters(::LineEntry)`, the `TrackingTask` cache gate and the strong-strong gate (B-3: knob-dependent, recompiled at the epoch, bitwise back after reset; clean) | "... the knob-root tripwire refuses a dependency outside the declared roots" (20493 pins the nested refusal); "... the machine-level knob-root tripwire refuses an undeclared shared root and overlapping roots"; the F-130 testset (31396) and T1 (23707) for the override knob's epoch |
| D9 `@elements` | `elements_macro.jl` at inventory depth only (U1's region; no lead opened) | the stage-2 pins "Machine description: every registered kind expands through @elements, derived from the registry" and "... the @elements block builds the hand-written lattice" (not re-run by the audit) |
| D10 the friendly constructors accept knob expressions | the override route of a knob expression only (B-3: `compile_runtime(::LineEntry)` merges overrides before `resolve_knobs`) | "Machine description: the friendly constructors accept knob expressions (D10)" and "... the effectiveness contract's expression arm" (stage 2's pins, not re-run by the audit); the F-130 and T1 pins above |
| D11 `with_overrides` (stage 5, unit A) | the in-place route's guards the derived route mirrors: after B-2 and B-10 the four routes (in place, derived, writer, reader) refuse a hook or collision-marker placement key and an undeclared key alike; B-9 corrected the wording (a marker is an `ElementSpec{:marker}` with declared keys) in the stage-3 record's lead and in unit A's docstring; the fold did not take B-2's merge note (`_overrides_check_key` calling `_reject_hook_placement_override` rather than carrying its own test) | "Machine description: with_overrides derives a lattice without touching the source" (28); "... with_overrides refuses by name" (22); "... the derived lattice's snapshot shows the overrides as placement data" (10); the B-2 and B-10 testsets below for the in-place twin |
| D12 as acceptance (`ReferenceParticle`; `Beam` and the cavities' `reference =`) | the cavity readers' twins `_fold_reference` and `_check_voltage_route_keywords`, one `_rf_cavity_params` for both forms, and `_beam_params` (C-5: every clash refused by name; clean by reading); the kick-scale derivation `_strong_strong_kbb1/2` (C-5: three zero factors behind one `E0` refusal; carried owner item); the inventory of flat spellers without a `reference =` form for the compile-path campaign (C-5) | the reference batch's refusal pins (its record, section 3; not re-run by the audit); the owner item in `../todo.md` |
| D13 the TOML snapshot | the value seams (B-6: `rng_id` read back as `Int` and not re-claimed for element specs, B-6a ledgered; `Float32` re-narrowing by the element's `numeric_type`, clean; `Dict` both ways, unexercised; `Symbol` by one hint function on both sides, clean; the include-time registration of methods and enums, B-6e tripwire); the line table's override members (B-2, B-10: the writer refuses what no compile reads and what the reader would refuse; the reader refuses `overrides` on a non-element member) | the stage-4 round-trip testsets (47, 226, 162, 91; 87, 18, re-run green by the units); "Machine description audit: every tracking method and enum of the module is a registered snapshot object type" (injection-verified); the B-2 and B-10 testsets (the writer and reader arms) |
| D14 the artifact embedding | `_ra_check_ledger_columns` in `_RA_PREPARE_CHECKS` on every continued or fresh file, `_ra_contents` skipping `/machine_tables`, `_ra_machine_snapshot` in every `prepare_run_artifact!`, `save_run_artifact`'s byte copy, `parse_machine` looking up only referenced digests, the example's rank-0 guard (C-4: the continuation refusal, the table of contents, `:all`, a retuned knob's second row, the memory-to-disk save; clean) | "Machine description: the run artifact embeds the machine snapshot and reads it back" (38); "... the task records the machine it was given, by spelling" (20); the probe's `L4` lines in `U2_report.md` |
| D15 the tasks and analyses take a lattice or a machine | the constructors' doors (B-4); the public `StrongStrongTask` forms' keyword surface (B-5: the private builder named by `MethodError`; fixed with a roster read from the builder's method); every walker over the placement tuple (B-1: enumerated with its treatment of a wrapped hook or marker; clean, B-1b ledgered); the solver pairing by configuration (C-1: `AtTurns` by identity; fixed); the per-`execute!` cavity walk (C-3: 416 B at `_has_accelerating_cavity(task.elements)`; ledgered) | "Machine description: StrongStrongTask takes a machine and compiles the runtime the tuple spelling compiles"; "Machine description audit: StrongStrongTask refuses an unknown keyword by its own name on the line and machine forms"; "Machine description audit: AtTurns compares by its set, so independently built solvers scheduling the same turns pair" (9); "Solver equality is by configuration" (re-run green) |

The stage-4 record's owner calls were reviewed and left as they stand: a
machine the codec cannot snapshot warns at prepare and records an empty
`machine_toml` (no lead found a run it stops or a reader it misleads: C-4);
the derived two-lattice machine is `nothing` without a warning where no
machine can hold the pair (B-7 measured it and found the design as recorded;
the owner question stays in `../todo.md`).

## 4 Findings

Vocabulary: a unit's claim is a lead until reproduced; a finding is
confirmed with a severity, refuted by measurement, or Unconfirmed (code left
unchanged). The file:line pointers are of the tree 5efe850 before the fixes;
the Repro column is the lead's durable identity (the unit reports quote each
command's output line by line).

| Id | Severity | Disposition | file:line | Repro | Fix or todo pointer |
|---|---|---|---|---|---|
| B-1 | — | refuted by reading and measurement: every walker that can meet a `LineEntry` wrapping a non-element child unwraps or steps over it (the list in `U1_report.md`, "Clean regions") | `src/tasks/Tasks.jl:2525`, `interface.jl:3937` and the sites listed | `probe.jl` / `probe2.jl` lines `L1`: `s_positions`, `survey`, `knob_report`, `TrackingTask` construction and `_runtime_entries` over a line holding a hook placement with overrides, all `ACCEPTED` | none |
| B-1b | Minor | confirmed, ledgered: a `StrongStrongCollision` in a `TrackingTask` line dies at the first turn with `MethodError: objects of type StrongStrongCollision{Nothing} are not callable`, identical on the placement and the tuple spelling (pre-existing: `_runtime_or_existing(element) = element` pushes the marker as a physics entry) | `src/tasks/Tasks.jl:2012` | `probe2.jl` `L1`: `execute!(TrackingTask(BeamLine("KM", d, ip, qf)))` and the tuple `(d, ip, qf)` | `../todo.md`, the carried row: a by-name refusal `_runtime_or_existing(::StrongStrongCollision)` in `interface.jl` naming `StrongStrongTask` as the remedy, plus a test; about five lines |
| B-2 (B-9 the same finding) | Moderate | confirmed and fixed: `entry.k = v` on a hook or collision-marker placement was stored, bumped the spec epoch, was read by no compile (a `schedule = EveryNSteps(step=7)` override compiled the spec's `step=2`), was written by the snapshot and read back; a direct `compile_runtime(entry)` then died on `kind(::ScheduledObserver)` | `src/elements/beam_line.jl:76-85`; `src/lattice/toml.jl:945-953`, `1018-1033` | `probe.jl` `L2`: `line[2].name = "x"` on a `ScheduledObserver` placement -> `ACCEPTED`, `overrides = Dict(:name => "x")`, epoch +1; `machine_toml` prints `overrides = { ... }` on the hook member and `parse_machine` reads it back | 0600139: `_reject_hook_placement_override` first in `setproperty!(::LineEntry, ...)`; `_toml_line_table` refuses a hand-built hook or marker member carrying overrides; `_toml_decode_line` refuses `overrides` on a non-element member; test "Machine description audit: a placement override on a hook or marker placement is refused by name on every route" (red in `red_run.log`) |
| B-3 | — | refuted by measurement: an override-only knob makes `_has_knob_parameters(elements)` true, a retune moves the tracked coordinates (max abs dx 1.2350627114862866e-3), the retuned run equals a task built fresh, the reset reproduces the first run bitwise | `src/elements/beam_line.jl:203-205`, `src/tasks/Tasks.jl:2062-2078` | `probe.jl` `L3`: `ring[1].x_offset = @knob_expr(md5b_ov.dx)`, track, `md5b_ov.dx = 1e-3`, track again | none (pinned by F-130 at 31396 and T1 at 23707) |
| B-4 | — | refuted by reading and measurement: all six `_element_tuple` call sites dispatch on the argument; `_collect_contracts(mach)` (a keyword default run before the body) refuses with the door's message; `one_turn_matrix(mach)` refuses through `_linearizable(::Machine)` naming itself | `src/tasks/Tasks.jl:287, 1023, 1029, 2249`; `interface.jl:2643` | `probe2.jl` `L4`: `TrackingTask(mach)`, `_collect_contracts(mach)`, `one_turn_matrix(mach)` on a two-lattice machine refuse naming the machine, its lattices and the remedy; a one-lattice machine returns | none |
| B-5 | Minor | confirmed and fixed: all four public `StrongStrongTask` forms raised `MethodError: no method matching _strong_strong_task(...; md5b_bogus::Int64)` while `TrackingTask` names itself | `interface.jl:2620, 2742, 2746` | `probe.jl` `L5`: `StrongStrongTask((ip, l6a), (ip, l6b); md5b_bogus=1)` and the three other forms, the message's first line | 0600139: `_strong_strong_refuse_unknown_keywords(kwargs)` first in the three public forms, the roster `_STRONG_STRONG_KEYWORDS` read from `Base.kwarg_decl(only(methods(_strong_strong_task)))` (ten names, measured); test "Machine description audit: StrongStrongTask refuses an unknown keyword by its own name on the line and machine forms" (red in `red_run.log`: 8 failed, 1 errored) |
| B-6a | Minor | confirmed, ledgered: `rng_id` of a `LumpedRadSpec` stores `UInt64`, prints decimal, reads back as `Int` by the kind's `ParamMeta` default (`isequal`, every consumer converts), and the reader does not re-claim an element spec's explicit id: a text edited to the fresh id 1000001 decodes with `_rng_id_held == false` (the flexible form has no per-kind claim; the hook and rule decoders do claim) | `src/lattice/toml.jl:556`; `radiation.jl:97, 480`; `linear6d.jl:597` | `probe.jl` `L6`: the stored and reloaded `rng_id`, the held state after decode | `../todo.md`, the carried row: a per-kind consumer class the reader can pass to `claim_rng_id!` (beside the kind's `rng_id` `ParamMeta`, or derived from the friendly constructors' call sites) and one call in `_toml_decode_element`; a test that a reloaded explicit id is held and that a reload onto another class's id warns; a metadata decision |
| B-6b/c/d | — | clean by reading: floats re-narrowed by the element's `numeric_type` (toml.jl:561, 833-842; the rules' `sigma` likewise); `Dict` written with sorted string keys and rebuilt with `Symbol` keys when the hint's default is a `Dict{Symbol}` (unexercised: 0 of 32 kinds' examples hold one); `Symbol` keys decided by `_toml_element_hint` on both sides, no schema declares a `Symbol`/`String` union | `toml.jl:530-538, 561, 612-614, 775`; `toml_hooks.jl:645-666` | `probe2.jl` `L6`: the Dict sweep over `ELEMENT_META_BY_KIND` (0 of 32) | none |
| B-6e | — | clean sweep made permanent: toml.jl registers tracking methods and enums by `subtypes` at include time and the stage-4 roster tripwire derives neither (an `Enum` fails its `isstructtype` arm); today complete, 6 methods and 1 enum of 31 object types | `src/lattice/toml.jl:758-763`; `test/runtests.jl:21649` | `probe2.jl` `L6`: the registered methods and enums | 0600139: test "Machine description audit: every tracking method and enum of the module is a registered snapshot object type", injection-verified in the test |
| B-7 | — | refuted by measurement: lattices rooted `md5b_a` and `md5b_a.x` give `_strong_strong_machine == nothing` and `StrongStrongTask(l7a, l7b).machine == nothing` (the stage-4 design), `Machine(...)` refuses by name; two lattices declaring `(md5b_a, md5b_b)` in either order share both; no caller builds a nested or duplicated root tuple | `src/lattice/Lattice.jl:214-260`; `interface.jl:2718-2727` | `probe.jl` `L7` | none (20493 pins the refusal) |
| B-8 | — | refuted by reading: no explicit stream id of the machine-description testsets is claimed by two consumer classes; 4113 is shared on purpose under `@test_logs`; 4112's cross-block reuse (a `Float32` `Beam` at 15119, a `Float64` beam at 21180) is same-class, silent by the owner's 2026-10-16 policy, and the two never meet in one task | `src/math/counter_rng.jl:254-262`; the ids listed in `U1_report.md` | `grep -n "rng_id" test/runtests.jl` over the blocks 20340-22190, 25186-25470, 43478-43900 | none |
| B-10 | Moderate | confirmed and fixed: `entry.bogus = 1` was stored by the placement route where the spec route refuses the key by name, the compile warned "stored as descriptive metadata only", the writer printed `overrides = { bogus = 1 }` and the reader refused it: a snapshot that could not be read back | `src/elements/beam_line.jl:76-85`; `src/lattice/toml.jl:945-953` | `probe3.jl` / `probe4.jl` lines `b`: spec route `ArgumentError: element kind :quadrupole has no parameter bogus; valid parameters: ...`; placement route `ACCEPTED`; `parse_machine` refuses `unknown override key "bogus"` | 0600139: `_reject_undeclared_override` last in the guard order (declared parameter, `_PLACEMENT_PARAM_KEYS`, or a key the spec already stores; a kind without metadata keeps the acceptance); `_toml_line_table` refuses an undeclared override key by name; the reflection test's write-isolation probe writes `x_offset` instead of `k1`; test "Machine description audit: an undeclared placement override key is refused by name where the spec route refuses it and is never written" (red in `red_run2.log`: 4 failed of 8) |
| B-11 | Unconfirmed | code left unchanged, owner question: `QuadrupoleSpec(; numeric_type=Float64, ...)` with `lt[1].L = big"0.30000000000000000001"` passes `Lattice(...)` and compiles `L = 0.3` (the override narrowed to `Float64`), the convention the suite pins for typed elements (20655-20660: a `Float64` literal on a `DriftSpec{Float32}` compiles to `0.7f0`); the untyped twin is refused by the lattice | `src/lattice/Lattice.jl`, `_lattice_check_params_eltype` (the early return) | `probe4.jl` line `c` | `../todo.md`, the carried row: convert (as pinned) or refuse a wider-than-`T` scalar override on a typed element; if refused, a second check in `_lattice_check_entry_eltype` over `getfield(entry, :overrides)`, about six lines, the pinned test's wording and a red-first test |
| B-12 | — | by design, reported: "Every exported API name appears in the registry snapshot" reads the generated text, so it passed on unit A's tree while the committed file lacked `with_overrides`; "Architecture integrity" compares the generated text with the file (49 of 50 on the unit trees, the two differing lines both the `with_overrides` export) and is the staleness tripwire; the fold regenerates the file | `test/runtests.jl:32357`; `[Architecture integrity]:28` | `probe5.jl`: the generated and committed snapshots differ in 2 of 481 lines | none; the regenerated snapshot in the fold's record commit the record commit that follows them |
| C-1 | Major | confirmed and fixed: `AtTurns` holds a `Set{Int}` and defined no `==`, so `AtTurns(Set([1,2])) == AtTurns(Set([1,2]))` was `false`, `solver_configuration` of two solvers scheduling luminosity on equal turn sets compared unequal and `_collision_solver` refused the pair as "different Poisson solver configurations" (Gaussian and PIC alike; the `EveryNSteps` control paired) | `src/tasks/BeamObservers.jl:57`; `interface.jl:3989-3991` | `probe.jl` lines `L1`: the three `false`s and the `ArgumentError` | 3bb1800 (71567d6 on md5-C): `Base.:(==)`, `isequal` and `hash` on `AtTurns` by its set, the `LongitudinalSlicing` precedent; test "Machine description audit: AtTurns compares by its set, so independently built solvers scheduling the same turns pair" (red in `red_L1_L2.log`) |
| C-2 | Moderate | confirmed and fixed: `_lattice_structurally_equal` walked every field of an in-line observer, and `MomentObserver` (buffer, capacity, length, record count, initialized flag, scratch, artifact handle and key), `BPMObserver` (its readings) and `CoordinateSnapshotObserver` (its handle) keep run state in the object, so `la == lb` was `true` pristine and `false` after one `execute!` | `src/lattice/Lattice.jl:492` (the struct walk at its tail) | `probe.jl` lines `L2`: `pristine la == lb: true`, `after one execute! la == lb: false` with the differing fields listed | 3bb1800: one branch in the walker, an `AbstractBeamObserver` whose type has an `observer_option_schema` method compares by the schema's values (the configuration view the snapshot writes, D6), an observer without one by its fields as before; `hash(::Lattice)` never read hook state; test "Machine description audit: a lattice whose observers have run is still equal to its pristine twin" (red in `red_L1_L2.log`) |
| C-3 | Minor | confirmed as a per-call bookkeeping of 416 B at a named site and refuted as a per-turn cost, ledgered: every `execute!` whose window is longer than one turn or starts after turn 0 re-walks `task.elements` through `_collect_spec_s!` to decide whether the line holds an accelerating cavity; for a `LineEntry` the placement's spec is `Any`-typed, so `kind(spec)`, `getparam(entry, :L, 0.0)` and `_placement_length_value` allocate per placement; the tuple route pays the same walk statically typed | `src/tasks/Tasks.jl:1151` (`_has_accelerating_cavity(task.elements)` in `_execute_tracking_window!`), via `Tasks.jl:864-889`, `Knowledge.jl:750`, `beam_line.jl:189` | `probe_alloc.jl` (the parity driver's weak-strong case as literals, CPU, 2000 macroparticles, three warm-ups): `@allocated execute!(task, beam; turns=1)` tuple 53248 B, lattice 53664 B, machine 53664 B (+416 B; +416 B again at `turns=3` and `10`, the control 0 B) | `../todo.md`, the carried row: cache the accelerating-cavity flag per compilation beside the runtime cache tuple (both routes gain: 576 B per call for the tuple too) |
| C-4 | — | clean by measurement and reading: the continuation refusal runs on every continued or fresh file before the row is appended (a mixed file cannot exist); `read(out, :all)` carries no `:machine_tables` and no `:machine` while the table of contents lists the group as digest => length; the per-`execute!` snapshot records a knob retuned between two `execute!`s in its own row; `save_run_artifact` copies the image byte for byte; the example's `write_machine` is gated on rank 0 | `src/tasks/RunArtifact.jl:1510, 2634, 3112, 3167, 3255, 3348`; `examples/strong_strong_tracking.jl:412` | `probe.jl` lines `L4`: `rows: 2`, `text1 != text2: true`, `row1 has 1.5`, `row2 has 2.5`, `toc keys: ["execution", "luminosity"]`, `read(:machine; slot=1) == row1: true` | none |
| C-5 | Moderate | confirmed by reading, carried owner item (since the reference batch; unchanged here): `_strong_strong_kbb1 = charge1 * charge2 * r0_1 * npart_2 * mc2_1 / E0_1` refuses only `E0`; `charge`, `mc2` and `r0` default to 0 in `_beam_params`, so any of the three missing zeroes the kick silently (`kbb2` likewise): three factors, not one; the inventory of flat reference spellers without a `reference =` form for the D12 compile-path campaign is in `U2_report.md` (`BeamParams`, `rf_strength`, `particle_beta`, `convert_longitudinal`, `_extref_convert`, the cavities' stored `beta0`/`gamma0` pair) | `src/tasks/strongstrong/slicing.jl:115-129`; `src/beam/Beam.jl:50-55, 1253-1260` | by reading; blast radius by grep: 96 `kbb1=` overrides in the suite (never derive), 5 single-line `Beam(...E0=...)` constructions without `r0` (5 with), 0 in `Contracts.jl` | `../todo.md`, the carried row: one preflight in `_preflight_solver_kbb` (interface.jl:3379) naming the zero factor(s) of a derived `kbb`, then a run of every strong-strong testset and contract to find fixtures deriving a zero on purpose (an instrumented one-process count prices it exactly) |
| C-6 | Minor | the validators agree (`validate_configuration_metadata()` true before and after); the duplicate's silent deduplication is the documented canonicalisation; a name with a non-digit power falls through to `parse(Int, ...)` whose message names neither the moment nor the observer, ledgered; `EveryNSteps` prints `stop = 9223372036854775807` for "no stop", carried as the stage-4 record states it | `src/tasks/BeamObservers.jl:593-606` (via 809-826) | `probe.jl` lines `L6`: `non-digit name: ArgumentError: invalid base 10 digit 'a'`; `EveryNSteps() stop printed by the codec: true` | `../todo.md`, the carried row: a `tryparse` in `Moment(::AbstractString)` naming the text (two lines; `Moment` predates the campaign, every caller's message would change); the `stop`: a typed default on the schema entry (`Option{Int}` with `nothing` for unbounded, or a `print_default = false` flag), metadata, not the codec |

Clean regions, with the evidence that makes "clean" checkable, are in
the unit reports under that heading: U1 lists every `LineEntry` walker
with its line and its treatment, the six `_element_tuple` call sites and
the one-turn-matrix helpers, `_lattice_knob_roots`' three callers, the
codec's `Symbol` seam and the explicit stream ids by block; U2 lists the
artifact's machine readers by probe line, the schedule family beyond
`AtTurns` (`EveryNSteps`, `AlwaysSchedule` value-equal, `PredicateSchedule`
by `===`, right), the `moments` route's refusals, the cavity readers, the
solver pairing's other arms (a genuine schedule mismatch still refuses; a
solver without a schema still falls back to identity, interface.jl:3975-3999
unchanged) and `hash(::Lattice)`'s consistency with the new `==`. A clean
result is a result: each line names the command and the number.

Corrections to the audit's own analysis (the original claim beside the
correction):

- The stage-3 record and unit A's first docstring said "a marker has no
  parameters" and the derived route's docstring refused "a key on a
  placement whose spec is not an `ElementSpec` (a hook ... or a marker)".
  Corrected by B-9: the element kind `:marker` is an `ElementSpec{:marker}`
  with declared keys (`name`, the placement keys) and keeps taking
  overrides; the class without parameters is "an in-line hook or a
  collision marker" (`StrongStrongCollision <: AbstractOctopusObject`),
  which the new messages name; a marker's `L` is refused by the
  declared-key table, not by "not an `ElementSpec`". Unit A's docstrings
  were aligned the same day (its commit message).
- The stage-4 record said "decoding re-claims explicit stream ids
  silently". Corrected by B-6a: true for the hooks and rules (their
  decoders call the claiming constructors), not for the `:lumped_radiation`
  and `:linear6d` element specs, which the flexible form rebuilds without a
  per-kind claim; a reloaded spec's stream can coincide silently with an id
  the reading process issues.
- The stage-3 record carried "about 410 bytes per `execute!` call that
  placement-spelled lines allocate over the bare tuple (per call, not per
  turn; site untraced)". Measured by C-3: 416 B per call, at
  `_has_accelerating_cavity(task.elements)` in `_execute_tracking_window!`,
  constant at 1, 3 and 10 turns; the tuple route pays 576 B for the same
  walk statically typed (the profiler's attribution; `@allocated` is the
  authoritative difference).
- Unit A's `_overrides_check_key` docstring (written against the stage-4
  tree) states that its hook-placement and undeclared-key refusals are "two
  refusals the in-place route does not make today (stage-3 lead; the audit
  of stage 5 decides whether it should)". The audit decided it should, and
  B-2 and B-10 made the in-place route, the writer and the reader refuse
  them; after the fold the sentence describes history, `[aligned at the
  fold / left for the next docs touch: the orchestrator's call]`.
- The stage-3 and stage-4 carried row said "a placement override written on
  a marker or a hook has nothing to land on and is not refused". Corrected
  by B-2 and B-9 together: it was stored, bumped the epoch and round-tripped
  (worse than "not refused"), and the class is the in-line hook and the
  collision marker, not the element kind `:marker`.

## 5 Verification of the fixes

Formula verification: none in scope (no batch of the campaign and no fix of
the audit changes a physics expression; the kick-scale derivation of C-5
was read, not changed).

Contracts: `validate_configuration_metadata()` returned `true` before and
after unit C's fixes (U2 probe `L6`; the validator block "The validators
check every key ..." 590 of 590 in `green_all.log`, with
`validate_configuration_metadata()` inside) and after unit B's (its
`green_run2.log`, the same block); `validate_element_metadata()` and both
`element_help` forms `[on the folded tree: the orchestrator's extracted
checks, result/gates/md5/extracted_checks.log]`; the Physics contracts and
`PublicConfigurationEffectivenessContract` run inside the full gate, whose
counts are in the commit messages of the stage-5 tail. No contract's
tolerance, acceptance or rejection changed; the acceptances that changed
(B-2, B-5, B-10, C-1, C-2) were grepped for every test probing the old
behaviour first (Lesson 2), listed per lead in the unit reports: one probe
found (B-10's `ri[1].k1 = 9.9`), retargeted to the same property.

Tests, all extracted in package mode at four threads
(`test/run_extracted_testsets.jl`), the lane the brief names for a unit;
the full gate on the final tree is the orchestrator's and its lane,
counts and skips are in the commit messages. Regression tests shown to
fail unfixed, each for the defect's reason:

- B-2: "Machine description audit: a placement override on a hook or marker
  placement is refused by name on every route" RED on the unfixed tree
  (`red_run.log`: `ACCEPTED` where the refusal is asserted, the overrides
  stored, the epoch 2 against 0, the writer and reader accepting), GREEN
  after, 11 of 11 (`green_run.log`, `green_run2.log`).
- B-5: "Machine description audit: StrongStrongTask refuses an unknown
  keyword by its own name on the line and machine forms" RED
  (`red_run.log`: 8 failed, 1 errored on the absent roster), GREEN after,
  12 of 12.
- B-10: "Machine description audit: an undeclared placement override key is
  refused by name where the spec route refuses it and is never written" RED
  on the tree without this fix (`red_run2.log`: 4 failed of 8, the key
  stored and the writer printing it), GREEN after, 8 of 8
  (`green_run2.log`); the reader's refusal and the spec route's message are
  its anti-vacuity arms.
- B-6e: "Machine description audit: every tracking method and enum of the
  module is a registered snapshot object type" passed on the unfixed tree,
  3 of 3 (a tripwire over a sweep found clean), and carries its own
  injection arm.
- C-1 and C-2: "Machine description audit: AtTurns compares by its set, so
  independently built solvers scheduling the same turns pair" and "Machine
  description audit: a lattice whose observers have run is still equal to
  its pristine twin" both FAILED on 5efe850 plus the two testsets
  (`red_L1_L2.log`: the identity assertions, the `solver_configuration`
  equality and the two pairings refused as "different Poisson solver
  configurations"; `la == lb && Machine(la) == Machine(lb) && task.machine
  == Machine(lb)` false after the run), both PASS on the fixed tree (9 of 9,
  6 of 6, `green_all.log`).

Neighbour testsets re-run green after the fixes: unit B's `green_run2.log`
(the four unit testsets 11, 12, 3 and 8 of as many; 27 neighbour blocks,
listed with their counts in `U1_report.md`, "Commands run", item 10: the
override routes, the guard family, the codec's stage-4 testsets 47, 226,
91, 87, 18, 38 and 20, the stage-3
constructor pins "StrongStrongTask takes a machine and compiles the runtime
the tuple spelling compiles" and "the strong-strong example's machine
round-trips and the reloaded task compiles the tuple spelling's runtime",
the reflection testset "Nested lines have length, reflection keeps state,
folded sugar is rejected everywhere" with `using Logging` as the runner's
prelude, and the sweeps "Every export is documented" 1, "No docstring is
detached by comment lines" 11, "No method grows a Core.Box outside the
argued allowlist" 5); unit C's `green_all.log` (19 blocks: the two new
testsets, "Solver equality is by configuration", "The gaussian solver
takes the luminosity schedule (reporting-only)", "Spectral
luminosity_schedule reaches its runtime consumer", "High-energy
weak-strong strong-strong limit", the eight "Machine description:"
testsets that compare lattices, machines or round trips, "Observer schema
keys must name public fields", "The validators check every key ..." 590,
the three sweeps) and `green_prelude.log` ("A scheduled hook that cannot
fire warns, for every hook kind at every placement" 33, "A strong-strong
line's scheduled hook that cannot fire warns, as the tracking task's does"
5, with the suite's file-level helpers as the prelude). Unit A's three
testsets 28, 22 and 10 of as many with the six neighbours and the sweeps
(its commit message). Skipped or unrunnable extracted, left to the gate,
listed visibly: "Particle tunes: fixed-label symplecticity ..." (errors on
a file-level helper the runner does not evaluate; unit B), "Non-finite
coordinates fail fast at solver chokepoints" and "The run artifact's row
cursor ..." (file-level helpers beyond the prelude; unit C; both name
`AtTurns` as a schedule only); "Architecture integrity" 49 of 50 on every
unit tree by the skeleton's `with_overrides` export alone (B-12),
regenerated at the fold.

Validation: no script of `validation/` is in scope. The examples'
fingerprints against the stage-4 baseline (the stage-4 record's
`result/gates/md4/compare/` runs): `[to be re-run on the final tree by the
orchestrator: CPU rows identical / CUDA rows within the floor, with the
numbers in the stage-5 record's section 3]`. The behavioural fingerprint
the units did run after their fixes: the stage-3 and stage-4 compiled-
runtime pins (the two titles above) green extracted, pinning that the
guards and the two equalities moved no compiled runtime.

Performance: C-3's trace, `probe_alloc.jl` at four threads (the parity
driver's weak-strong case as literals, CPU, 2000 macroparticles, three
warm-ups): `@allocated execute!(task, beam; turns=1)` tuple 53248 B,
control 53248 B, lattice 53664 B, machine 53664 B, +416 B; +416 B again at
`turns=3` and `turns=10` with the control 0 B; `Profile.Allocs` at
`sample_rate=1` attributes 800 B to the placement route against 576 B to
the tuple route for the same walk. No fix of the audit touched a hot path
(five refusals at construction or write, two equalities), so nothing else
was timed.

Change log (every modification -> finding id; why the old was wrong, why
the new is right):

- `src/elements/beam_line.jl`, `_reject_hook_placement_override` first in
  `setproperty!(::LineEntry, ...)` -> B-2/B-9. Old: a key on a hook or
  collision-marker placement was stored and bumped the epoch though no
  compile reads it. New: refused by name with the remedy (configure the
  object at its construction), nothing stored, the epoch untouched; the
  derived route refuses the same.
- `src/lattice/toml.jl`, `_toml_line_table` refuses a hand-built hook or
  marker member carrying overrides; `_toml_decode_line` refuses `overrides`
  on a non-element member -> B-2. Old: written and rebuilt silently. New:
  the writer and reader agree with the two in-memory routes.
- `src/elements/beam_line.jl`, `_reject_undeclared_override` last in the
  guard order -> B-10. Old: the placement route stored a key the spec route
  refuses, read by nothing. New: the exact condition of the spec route
  (declared parameter, placement key, or a key the spec already stores; a
  kind without metadata keeps the acceptance), naming the kind, the key and
  the valid parameters; the older guards keep their messages.
- `src/lattice/toml.jl`, `_toml_line_table` refuses an undeclared override
  key by name -> B-10. Old: a snapshot the reader refused. New: the twin of
  the element table's stored-key rule.
- `test/runtests.jl`, the reflection testset's write-isolation probe
  `ri[1].k1 = 9.9` -> `x_offset` -> B-10's blast radius. Old: the probe
  relied on the acceptance the fix removes. New: a placement key, the same
  no-write-through property asserted.
- `src/tasks/strongstrong/interface.jl`,
  `_strong_strong_refuse_unknown_keywords` and `_STRONG_STRONG_KEYWORDS` ->
  B-5. Old: a `MethodError` naming the private builder. New: the public
  constructor's name and the keyword roster, read from the builder's method
  (never hand-copied); the retired keywords stay in the roster and keep
  their own precise refusals.
- `test/runtests.jl`, the derived registration tripwire -> B-6e. Old: a
  later tracking method or enum would be refused loudly at write but no test
  would say why. New: the sweep is permanent and injection-verified.
- `src/tasks/BeamObservers.jl`, `==`, `isequal`, `hash` on `AtTurns` -> C-1.
  Old: identity on a mutable field. New: by the set, the `LongitudinalSlicing`
  precedent; no site compared schedules by identity on purpose.
- `src/lattice/Lattice.jl`, the observer branch of
  `_lattice_structurally_equal` -> C-2. Old: run state inside the object
  decided equality. New: the configuration view the snapshot writes (D6)
  for an observer with an `observer_option_schema`, the field walk for one
  without; the unit's round-trip fidelity for the three schema observers
  narrows from all fields to the schema keys, which is what the codec
  writes; `hash` consistent.

## 6 Remaining risks and owner items

Open leads priced as `../todo.md` rows (the carried row of the
machine-description campaign):

- B-1b [Minor]: a `StrongStrongCollision` in a `TrackingTask` line (either
  spelling) dies at the first turn with a raw `MethodError`; a by-name
  refusal in `_runtime_or_existing` naming `StrongStrongTask`, about five
  lines plus a test.
- B-6a [Minor]: a reloaded `:lumped_radiation` or `:linear6d` spec's
  explicit stream id is not re-claimed in the reading process (and reads
  back as `Int`); a per-kind consumer class the reader passes to
  `claim_rng_id!` (a metadata decision: beside the kind's `rng_id`
  `ParamMeta` or derived from the friendly constructors' call sites), one
  call in `_toml_decode_element`, two tests.
- C-3 [Minor]: 416 B per `execute!` call of a placement-spelled line at
  `_has_accelerating_cavity(task.elements)`; cache the flag per compilation
  beside the runtime cache tuple (the tuple route's 576 B go with it).
- C-6 [Minor]: `Moment(::AbstractString)`'s non-digit message (`tryparse`
  naming the text, two lines, every caller's message changes); `EveryNSteps`
  printing `stop = typemax(Int)` and the marker forms of `Linear6DSpec`'s
  tuples, cured by a type or typed default on the schema entry or
  `ParamMeta`, not by the codec.

Owner items:

- C-5 [Moderate, carried since the reference batch]: a strong-strong `Beam`
  built without `r0`, `charge` or `mc2` derives a zero kick scale silently;
  refuse the zero factor(s) by name at `_preflight_solver_kbb`, after a count
  of the fixtures that derive a zero on purpose; or derive `r0` in the D12
  compile-path campaign, whose inventory of flat spellers U2 lists.
- B-11 [Unconfirmed]: a wider-than-`T` scalar override on a typed element
  is converted at compile (the suite's pinned convention) rather than
  refused at the lattice (the typed constructors' rule for a wider table);
  convert or refuse is the owner's rule, about six lines if refused.
- The stage-4 calls, unchanged: a machine the codec cannot snapshot warns
  at prepare and records an empty `machine_toml`; the derived two-lattice
  machine is `nothing` without a warning where no machine can hold the
  pair; whether the machine should hold beam definitions (stage 3); the
  shipped strong-strong example's `rng_id = 2` warning (its own small
  batch, the fingerprints move); a reloaded knob root is a namespace, not
  a bound constant; a solver or rule of another numeric type than its
  lattice is refused at write.
- B-2's merge note: `_overrides_check_key` (unit A) can call
  `_reject_hook_placement_override` rather than carry its own test of the
  same condition, left as a follow-up (the derived route checks the same conditions through the codec's one key table and the guard family's two functions, both derived from the element metadata; one call in place of the copy is a tidy-up with unit A's message pins to move, priced at a few lines).

Risks to know, not findings: `_STRONG_STRONG_KEYWORDS` is read through
`Base.kwarg_decl`, `Base`-internal (present since 1.0, `base/methodshow.jl:80`
in 1.12.4); a Julia upgrade that renames it fails the `const` at include
time, loudly. A `Dict`-valued element parameter has never gone through the
codec in a test (no kind's example holds one); the per-kind round trip
would exercise it the day one does. The `runtime_variants` lesson of the
LinearOptics audit stands (every reader of a kind's declared parameters is
found by grep, not enumerated by a tripwire); this audit's walker
enumeration (B-1) is likewise a grep, recorded line by line, not a tripwire.
