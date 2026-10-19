# U51: design notes as claims about the code

## Region

Tree `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Eight design notes, 4660 lines,
every line read:

| file | lines |
|---|---|
| `docs/design/multi_process_policy.md` | 1-1215 |
| `docs/design/turn_modulation.md` | 1-850 |
| `docs/design/twiss_dispersion_analysis.md` | 1-628 |
| `docs/design/spectral_turn_table.md` | 1-569 |
| `docs/design/run_artifact.md` | 1-543 |
| `docs/design/turn_modulation_record.md` | 1-440 |
| `docs/design/survey_and_reference_channel.md` | 1-313 |
| `docs/design/testing_lanes.md` | 1-102 |

Depth: claims-vs-code. Hypotheses briefed: (1) every decided item implemented as decided or
marked deferred in the ledger, every staged stage landed or honestly open; (2) schemas and
dataset names declared by the notes versus the code's writers and readers; (3)
`testing_lanes.md` section 3 versus the suite's lane gates and the CI workflow.

## Provenance

READ line by line: the eight files above in full. Reference code read in full:
`src/tasks/RunArtifact.jl` 1-2070 (the writer, the recorder, the lock, the readers),
`.github/workflows/ci.yml` 1-46, `test/runtests.jl` 1-30 (the lane preamble), 32015-32035
(the banner), 21115-21135 (the conditional MPI-arm gate), 20455-20480 and 20955-20985 (the
design-note pins). Reference code read by targeted excerpt (grep plus `sed` ranges, not whole
files): `src/elements/turn_modulated.jl` (rule structs, constructor checks, `update`/`update_line`,
`_update_line_unrolled` 1540-1600, spectral factory and keys, `_resolve_turn_rule`),
`src/tasks/Tasks.jl` (`_fast_tracking_path` 1250-1252, `_runtime_entries` 1647-1670, receipts
1290-1382, `_warn_resolved_duplicate_tables`, `_warn_resolved_seed_drift`),
`src/tasks/BeamObservers.jl` (705-725, 840-905), `src/tasks/BPMObserver.jl` 305-320,
`src/policies/Policies.jl` (policy structs, the seam, `_record_collective!`),
`ext/OctopusMPIExt.jl` (seam methods, `_MP_ALLSUM_SCATTER_MIN`), `src/tasks/strongstrong/`
(`interface.jl` `_solver_divides`, `slicing.jl` 660-690, `spectral.jl`, `spectral_sliced.jl`,
`pic_cpu_sliced.jl` receipts), `src/analysis/twiss_dispersion_analysis.jl` 430-440,
`src/analysis/mode_clusters.jl` 81, `src/elements/rf_cavity.jl` (slip, accelerating cavity),
`src/track/phase6d_track.jl` 218-263, `src/contracts/Contracts.jl` (`_output_receipt_gaps`),
`docs/history/twiss_dispersion_analysis_history.md` (stage 9 section 14931, Part D 2690-2725),
`docs/history/turn_modulation_record_2026_10_15.md` 180-200, `docs/todo.md` rows 20-51,
`validation/README.md`, `test/examples/crab_cavity_noise.jl` (toggles), `test/nightly_suite.sh` 117.

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U51/`):

- `twiss_schema_probe.jl` (log `twiss_schema_probe.log`, exit 0): loads Octopus and prints
  `analysis_option_schema(TwissDispersionAnalysis)` defaults, the 15 exports the twiss status
  paragraph names, the per-spec declared analyses, `run_artifact_option_schema()`, four
  `RunArtifact` refusals and the no-name observer constructors. Numbers: `resolution_chord`
  default `0.001`; all 15 names defined and exported; TWISS_KINDS 23 (22 element kinds plus
  `:line`), PLACEHOLDER_KINDS 8, OTHER 0; `append=false, capacity=64,
  record_turn_modulation=false`, all three `consumer=run_artifact_output category=output`;
  `record_turn_modulation=1`, `append=1`, `capacity=0`, `capacity=true` each refused with an
  `ArgumentError` naming the keyword and the value; `MomentObserver()` and
  `CoordinateSnapshotObserver()` raise `UndefKeywordError: keyword argument name not assigned`.
- Shell measurements on the tree: `grep -o '_lane_gate("[^"]*"' test/runtests.jl | sort -u | wc -l`
  = 16; the gated line ranges (15 `if`/`end` pairs: 13948-14136, 14502-14554, 15662-15714,
  15932-16036, 16738-16866, 17589-17704, 23018-23811, 23813-23960, 24154-24361, 24733-24826,
  28323-28371, 30602-30698, 30896-30988, 31101-31176, 31567-31639, plus the inline arm at 21125);
  an `awk` map of every `.md`-reading line of the suite onto those ranges (18 lines, all
  ungated); `grep -rn "execution_elapsed\|execution_start_turn" src/` = 0 lines;
  `grep -c "27 columns\|216 bytes" docs/design/run_artifact.md` = 0; `grep -n "_ra_stamp_ledger!("
  src/tasks/RunArtifact.jl` = call sites at 1090, 1113, 1146, 1260, 1388.

## Leads

### LEAD U51-1 [Minor, confidence high] docs/design/testing_lanes.md:46
Claim: The note's present-tense count of lane-gated sections ("exactly the 13 measured heavyweights", "the 13-guard mechanism" at line 97, "171 of 184 testsets" at line 43) is a hand copy that has drifted: the suite has 16 distinct `_lane_gate` titles.
Mechanism: Section 2 says the list "lives in the `_lane_gate` call sites and nowhere else (no second hand-copy)", but the count itself is a second copy; three sections registered after 2026-08-13 (the two MPI launcher sections and the probe's two-rank arm, among others) moved the number and the note's "renewed by measurement" membership judgement has no updated record. A reader using section 2 as the precedent for "does a new testset belong behind a gate" works from a stale population.
Repro: `grep -o '_lane_gate("[^"]*"' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | sort -u | wc -l` prints 16; `grep -n "exactly the 13\|13-guard\|171 of 184" docs/design/testing_lanes.md` prints three lines.

### LEAD U51-2 [Minor, confidence high] docs/design/testing_lanes.md:87
Claim: Section 4 rule 3 says the full gate runs "before every commit outside the derived markdown-only class", contradicting section 3 of the same note (line 55: "before any push", owner decision 2026-09-04) and AGENTS.md; the suite's fast-lane banner (`test/runtests.jl:32034`, "still owed before any commit") and the lane preamble comment (`test/runtests.jl:8`) print the superseded rule.
Mechanism: The 2026-09-04 owner decision was applied to section 3 and to AGENTS.md but not to section 4 or to the two strings in `runtests.jl`; every fast run therefore prints a policy statement the owner retired, and the note disagrees with itself about the one rule it exists to state (hypothesis 3).
Repro: `grep -n "before any commit\|before every commit\|before any push" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/testing_lanes.md /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl /cfs/ad/dxu/Library/Julia/Octopus/AGENTS.md` shows "commit" at testing_lanes.md:55 (as history), :87, runtests.jl:8, :32034 and "push" at testing_lanes.md:55 and AGENTS.md.

### LEAD U51-3 [Minor, confidence high] docs/design/run_artifact.md:119
Claim: The decided rule "Every probe takes a `name`, defaulting to its beam-line provenance path (`ARC1/CQS[3]` -- machinery that exists)" and the schema line `/moments/IP6 ... attrs: name, s, provenance path` (line 92) are neither implemented nor listed among the deferred niceties in `docs/todo.md` row "Run-artifact niceties deferred at step 4".
Mechanism: `MomentObserver(; name::AbstractString, ...)` and `CoordinateSnapshotObserver(; name::AbstractString, ...)` (`src/tasks/BeamObservers.jl:711, 765`) make `name` a required keyword with no default, and `_ra_bind_probe!` (`src/tasks/RunArtifact.jl`) stamps `name`, `s`, `column_names` and `rows_valid_through_turn` only, no provenance attribute; the todo row's "Remaining" list names only the weak-strong channel labels and the live text mirror, so this decided item is in neither the code nor the ledger (hypotheses 1 and 2).
Repro: `grep -n "NO_NAME" /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U51/twiss_schema_probe.log` shows both constructors raising `UndefKeywordError`; `grep -n "_ra_set_attr!(g, \"" /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/RunArtifact.jl` lists no provenance attribute; `grep -n -i "provenance path" /cfs/ad/dxu/Library/Julia/Octopus/docs/todo.md` prints nothing.

### LEAD U51-4 [Minor, confidence high] docs/design/run_artifact.md:196
Claim: The turn-modulation series paragraph states that a `TrackingTask` without strong beams writes the ledger's `current_turn` "to the file only at finalize"; since the 2026-10-16 neighbour audit every flush stamps it.
Mechanism: `_ra_stamp_ledger!` is called from the luminosity flush, the probe-row push, the series flush and finalize (`src/tasks/RunArtifact.jl:1090, 1113, 1146, 1260, 1388`), and `src/tasks/Tasks.jl:1471` assigns `art.current_turn` at the top of every turn; the code's own docstrings (`_ra_stamp_ledger!`, `turn_modulation_provenance`) describe the current behaviour and name the 2026-10-16 change, while the design note still describes the behaviour before it (hypothesis 2, class 14).
Repro: `grep -n "_ra_stamp_ledger!(" /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/RunArtifact.jl` prints five lines (four call sites and the definition); `grep -n "only at finalize" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/run_artifact.md` prints line 196.

### LEAD U51-5 [Minor, confidence med] docs/design/run_artifact.md:488
Claim: The execution-diagnostics paragraph describes an "interim fix already landed on the moment files", the datasets `/execution_elapsed` and `/execution_start_turn` "created on demand for older files", which no writer or reader in `src/` carries.
Mechanism: The standalone moment writers were retired at step 4 (the note's own status paragraph) and the per-execution ledger became `/execution` with `_RA_LEDGER_COLUMNS`; the paragraph is written in the present tense ("its overhead is one tiny dataset write per flush, so it needs no switch") about machinery that no longer exists, and only the scalar `/elapsed_time` of the legacy `MomentOutput` reader survives (`src/tasks/BeamObservers.jl:1522`).
Repro: `grep -rn "execution_elapsed\|execution_start_turn" /cfs/ad/dxu/Library/Julia/Octopus/src/` prints nothing; `grep -n "execution_elapsed" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/run_artifact.md` prints line 488.

### LEAD U51-6 [Minor, confidence high] docs/design/turn_modulation_record.md:219
Claim: The cost table's row "the example's moments table for comparison | 27 columns, about 216 bytes per turn | `run_artifact.md`" cites a source that carries neither number.
Mechanism: The citation column is the table's provenance for each figure; `run_artifact.md` contains no "27 columns" and no "216 bytes" (the 27-moment default is recorded elsewhere, in `docs/todo.md` row "Observer declared defaults are unchecked"), so the number has no committed source where the note says it has one (class 14).
Repro: `grep -c "27 columns\|216 bytes" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/run_artifact.md` prints 0; `grep -n "27 columns" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/turn_modulation_record.md` prints line 219.

### LEAD U51-7 [Minor, confidence high] docs/design/turn_modulation.md:360
Claim: Section 4.4's "The `ntuple(..., Val(N))` form is load-bearing" and its `update_line` sketch (line 351) describe a form the code replaced on 2026-10-16; the note records only the earlier `_slot_draws` unroll (section 7) and not the `update_line` one.
Mechanism: `src/elements/turn_modulated.jl:1557-1573` defines `update_line` as `_update_line_unrolled`, a `@generated` literal-index unroll, with the comment that the `ntuple(i -> ..., Val(N))` closure form "allocated 130-435 kB per turn once a line held about four distinct element types with two or more wrapped" (neighbour audit U1-1); the design note's load-bearing claim is now the opposite of what the code says about that form (class 14).
Repro: `grep -n "_update_line_unrolled\|ntuple(i -> ..., Val(N))" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/turn_modulated.jl` shows the generated form and the comment; `grep -n "form is load-bearing" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/turn_modulation.md` prints line 360.

### LEAD U51-8 [Minor, confidence med] docs/design/spectral_turn_table.md:190
Claim: The D5 "after landing" remark keys the Rayleigh moduli as `octopus_normal_pair(seed, RNG_PHILOX, 0, rng_id, k, 2)` (turn field 0), while the code and the later F1 remark (line 134) key on the slot.
Mechanism: `src/elements/turn_modulated.jl:566` calls `octopus_normal_pair(seed, RNG_PHILOX, slot, rng_id, k, 2, Float64)`; the D5 remark predates review F1 and was not re-issued with it as the D7 template was, so the note carries two keyings of one quantity and the one under the decision that defines the amplitude model is the stale one (hypothesis 2).
Repro: `grep -n "octopus_normal_pair(" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/turn_modulated.jl` shows `slot` in the turn field; `grep -n "RNG_PHILOX, 0, rng_id, k, 2" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/spectral_turn_table.md` prints line 190.

### LEAD U51-9 [Minor, confidence high] docs/design/twiss_dispersion_analysis.md:183
Claim: The option table declares `resolution_chord` default `1e-4` and the "Default value" paragraph (lines 428-445) promises "If the bracket does not contain `1e-4`, the measured value wins and this paragraph records the change"; the code's default is `1e-3` and the paragraph records nothing.
Mechanism: `src/analysis/mode_clusters.jl:81` has `const _DEFAULT_RESOLUTION_CHORD = 1.0e-3`, the schema declares that constant, and the campaign history's Part D (`docs/history/twiss_dispersion_analysis_history.md:2690-2725`) records the frozen value with its margins; the body was frozen instead of amended, so the note's table states a default ten times smaller than the one shipped, against the note's own sentence about where the change would be recorded (hypothesis 1; the authoritative docstring and metadata are consistent with the code, which is why this is Minor).
Repro: `grep -n "_DEFAULT_RESOLUTION_CHORD *=" /cfs/ad/dxu/Library/Julia/Octopus/src/analysis/mode_clusters.jl` prints `1.0e-3`; `grep -n "OPT resolution_chord" .../probes/U51/twiss_schema_probe.log` prints `default=0.001`; `grep -n "1e-4" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/twiss_dispersion_analysis.md` prints lines 183, 428, 436, 445.

### LEAD U51-10 [Minor, confidence high] docs/design/twiss_dispersion_analysis.md:42
Claim: The status paragraph says it is "the only place in the note that tracks implementation status" and stops at Staging item 8, while the frozen body carries dated implementation edits (line 376: `_kappa_route` re-derived 2026-09-14; line 380: `_INVARIANCE_RESIDUAL_CAP`, stage 9, 2026-09-16; line 506: catalogue-derived example list since 2026-10-14; line 608: owner decision 2026-10-18) and stage 9 is absent from the status.
Mechanism: The history has a stage 9 section ("## 2026-09-16: stage 9, the post-campaign targeted neighbour audit", line 14931) whose fix the body already cites, so the paragraph that claims to be the sole status tracker is behind the body it says is frozen; a reader cannot tell from the note which stage the implementation is at (hypothesis 1, "every stage landed or honestly open").
Repro: `grep -n "stage 9\|2026-10-18\|2026-10-14\|re-derived 2026-09-14\|only place in the note" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/twiss_dispersion_analysis.md` prints lines 42, 376, 380, 506, 608; `grep -n "^## 2026-09-16: stage 9" /cfs/ad/dxu/Library/Julia/Octopus/docs/history/twiss_dispersion_analysis_history.md` prints line 14931.

### LEAD U51-11 [Minor, confidence high] docs/design/survey_and_reference_channel.md:3
Claim: The status line reads "design, pre-implementation (2026-08-13)" although the body records the implementation (line 64 "Refinement at implementation (2026-08-14, Scope B)", line 124 "Correction (2026-08-14, at implementation)") and the code carries both consumers.
Mechanism: `src/elements/rf_cavity.jl` holds the slip-corrected symplectic z-shift (`_velocity_slip_g`, lines 64-118) and `ThinAcceleratingCavitySpec` (line 2, 697), and `docs/theory/arc_survey_and_velocity_slip.md` exists; sections 3b and 7 still describe the superseded design (the cavity "declares `_requires_tracking_context`", the "precision pin at large turn numbers") which the body's own correction says no longer exists. The status line is the one field a reader checks first and it is wrong by the note's own content (hypothesis 1).
Repro: `grep -n "Status:" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/survey_and_reference_channel.md` prints "pre-implementation"; `grep -n "slip-corrected\|_velocity_slip_g\|ThinAcceleratingCavitySpec" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/rf_cavity.jl | head` shows the landed code.

### LEAD U51-12 [Minor, confidence med] docs/design/multi_process_policy.md:927
Claim: "At thirty-two ranks, more ranks than slices, it turns back up to 227 ms; that regime is a todo row, not a claim" stands as a measurement while the same note withdraws that series (lines 806-815: taken through the bare `collide!` entry that rebuilt every buffer per call, "the 'the curve turns up past thirty-two ranks' conclusion drawn from it does not survive") and later measures 37.4 ms at thirty-two ranks (the table under "Lifting the ceiling").
Mechanism: The 4g scaling paragraph (451/497/372/230/130/74/227 ms) was left in place when the "Lifting the ceiling" section withdrew the bare-entry numbers and called 227 ms "the pushed baseline" (line 898); a reader of the global-scalars section alone takes a withdrawn figure and a withdrawn conclusion as current (class 14).
Repro: `grep -n "227 ms\|WITHDRAWN\|turns back up" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/multi_process_policy.md` prints lines 806, 850, 898, 927.

### LEAD U51-13 [Minor, confidence low] docs/design/multi_process_policy.md:1027
Claim: The note says folding `longitudinal_slices`'s per-slice all-sums into one vector all-sum "takes the collide to 35" all-sums; the code comment at the fold says "The count is now 12".
Mechanism: `src/tasks/strongstrong/slicing.jl:665-688` documents the same change ("of the 91 all-sums a divided spectral collide issued, 72 were here ... The count is now 12") and issues two vector all-sums (`members`, `zsums`); the two texts give different post-fold counts for what reads as the same collide, and neither says which collide configuration it counted, so one of the two numbers is stale or they count different things without saying so (class 14).
Repro: `grep -n "collide to 35" /cfs/ad/dxu/Library/Julia/Octopus/docs/design/multi_process_policy.md` prints line 1027; `sed -n '672,676p' /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/slicing.jl` prints "The count / is now 12."

## Clean

What was compared against what, and what was measured. Every claim below was checked against
the code or the suite named; no claim rests on the note alone.

**testing_lanes.md against `test/runtests.jl` and `.github/workflows/ci.yml` (hypothesis 3).**
Section 1: the lane preamble (`runtests.jl:13-28`) errors on an unknown lane name and on
multiple `lane=` arguments, defaults to `full`, prints `LANE SKIP [lane]: name` per gate and
the banner naming every skipped section (`32028-32034`), as stated. The structural tripwires
the note says the fast lane keeps are all outside the gated ranges: "Architecture integrity"
(163), the `Core.Box` sweep (16915), the method-overwrite guard (17787), the knob round-trip
(30434), and every `validate_element_metadata()` / `validate_configuration_metadata()` call
(170, 7174, 10885-10886, 12883-12884, 14714, 16129, 17767-17784). Section 3 rows:
`validate(PublicConfigurationEffectivenessContract())` sits at 24277 inside the gated
"Contract coverage guards" (24154-24361), "Physics contracts" is gated (30602), the in-suite
CPU/CUDA comparisons are gated (28323, 31567), as the rows claim. The markdown-only row's
premise holds and is stronger than stated: all 18 lines of the suite that read a `.md` file
(the snapshot compare 189-190, the docs-index tripwire 215-233, the AGENTS.md source-map
tripwire 263, the `current_runtime.md` pin 13824, the design-note pins 20462, 20791, 20965)
are ungated, so a fast run executes every docs check; the note's "the only docs checks the
suite has" names two of them (stale enumeration, conclusion unchanged). CI runs
`Pkg.test(julia_args=["--threads=4"])` on `ubuntu-latest`, Julia `'1.12'`, no GPU, as the
note says; `test/nightly_suite.sh:117` runs the same plain `Pkg.test`, so "`lane=full` (the
default -- plain `Pkg.test`, CI, the nightly script)" holds. The conditional gate at 21125
(`@isdefined(_lane_gate) ? _lane_gate(...) : true`) runs the arm when the title-cut runner
lacks the preamble, a loud rather than silent fallback.

**run_artifact.md against `src/tasks/RunArtifact.jl` (hypothesis 2).** Constructor keywords,
defaults and refusals match the note and were measured (probe: four refusals, each an
`ArgumentError` naming keyword and value). `run_artifact_option_schema()` is exported with
three `:output` options naming `:run_artifact_output` (probe). Dataset layout matches the
schema block: `/luminosity/<label>` holds extendable `turns`/`values` with `label` and
`rows_valid_through_turn`; `/moments|snapshot|bpm/<name>` hold `data` (chunk `(256, ncols)`),
`column_names`, `name`, `s`, the cursor (`_ra_bind_probe!`; `_RA_GROUPS` refuses any other
named kind); `/losses` is rewritten whole with the `write_loss_record` layout; `/execution`
holds exactly `_RA_LEDGER_COLUMNS` = start_turn, turns, current_turn, elapsed, rng_seed,
rng_method, and the suite pins that this note names each (20462-20463, verified: all six
appear in backticks). `/turn_modulation/<slot>` carries `element_count` and
`elements_valid_through` (created at 0, advanced per element), element groups with `element`,
`beam`, `slot_count`, slot groups with `index`, `kind`, `rng_id`, `digest`, `name`, `length`
and `nominal_*`, the `series` dataset chunked `(256, ncols)` with `columns`, `first_turn`,
`turns`, created inside the per-element loop with `series=(first_turn, planned_turns)`;
`state` is reserved (`_RA_TM_STATE`), skipped by the readers' count, returned as `nothing`.
Reader shapes match: `nominal`, `series` (column, or row count in the table of contents),
`first_turn`/`turns` per element, `state = nothing`; torn-by-name cases and the partial-slot
warning read as described; `_ra_check_partial_slots` refuses `append=true` onto a partial slot.
The sidecar lock: `<path>.lock`, `JL_O_CREAT | JL_O_EXCL`, the line
`host= pid= since= task=`, taken before `h5open` for fresh and continued opens, released
after close in `finalize_run_artifact!` and on every prepare refusal and failed open,
refusal message naming the lock, its line and the remedy, no automatic takeover; `_ra_open`
emits one `@info` per (path, lock line) per process and retries the open once. Receipts:
`:run_artifact_output` carries `task, artifact, append, continued, capacity,
record_turn_modulation, recording, execution`, recorded after the last refusal and at the
non-root early return; `:tracking_output` carries `artifact, channels, loss_report`
(`Tasks.jl:1297, 1376`); the three probes' receipts carry `name/moments/capacity`,
`name/npart/captured`, `artifact/capacity` (`BeamObservers.jl:847-850, 899-901`,
`BPMObserver.jl:311-313`); `_output_receipt_gaps` exists (`Contracts.jl:421`) and is run over
the three fixtures (652-654); the suite derives the `:output` consumer set and checks a
`_record_execution!` site per consumer (20576-20582). The `:artifact` report entry is
`:unresolved` iff `append` or `record_turn_modulation` is requested (`_ra_artifact_entry`),
with the quoted ", recording the turn-modulation series" prefix. The per-observer `capacity`
keyword survives only as a throwing migration error (`BeamObservers.jl:711-716`), so "retired
with the writers" holds; `_fast_tracking_path` includes `task.artifact === nothing`
(`Tasks.jl:1250-1252`), so "the fast loop is never taken with an artifact" holds. The quoted
timing numbers (0.276/0.298 s, +11.2 us, 158607/295778 bytes) are in the committed record
`docs/history/turn_modulation_record_2026_10_15.md:195-197`. Deferred items the note names
are in the ledger: the luminosity groups' `s` attribute, the weak-strong label names and the
live text mirror are `docs/todo.md` row 47 "Run-artifact niceties deferred at step 4".
`with_execution_audit(f, audit)` takes no keywords (`Policies.jl:181`), so D2 holds trivially.
No defect was found in `RunArtifact.jl` itself (read in full); one caveat for the auditor: the
recorder's "met exactly once" check (`_record_turn_draws!`, `_tm_end_turn!`) is a count
check, not an identity check -- column order rests on the provenance walk and the hook walk
both following tuple order (`_update_line_unrolled` evaluates in index order, the docstring
says so), and `_ra_validate_turn_modulation!` pins per-element active counts at prepare.

**turn_modulation_record.md against the code (hypotheses 1 and 2).** D1-D10 as built: the
recorder (`TurnModulationRecorder`, `_turn_modulation_sink`, `_tm_begin_turn!`,
`_tm_end_turn!`, `_ra_flush_turn_modulation!`, `sizehint!` buffers), the shared evaluation
(`_realize_draws` / `realize` / `_slot_nominals` / `_turn_modulation_columns!`,
`turn_modulated.jl:1237-1394, 1912`), the tripwire that the three per-container methods are
declared on one set (`runtests.jl:11083`), the recording hook `update(elem, ctx, sink)` with
`nothing` as the plain form (1488-1509). Section 6.1: `test/turn_modulation_probe.jl` exists
and the testset "Turn modulation: the one-particle probe verifies the loop per harmonic"
(20996) carries the two-rank arm behind its own gate (21125). Section 7 stage 2 landed:
`OCTOPUS_RECORD_TURN_MODULATION` in `test/examples/crab_cavity_noise.jl` (234, 340, 359),
`record_turn_modulation = true` in `examples/crab_cavity_noise.jl:322`, the validation
reading `turn_modulation_provenance` (`validation/crab_cavity_noise_response.jl:170-178`).
D10's hand-over row exists (`docs/todo.md` row 27, "Stateful turn-modulation rules").

**turn_modulation.md against the code (hypothesis 1).** D1-D8 and section 4.3 as built:
`TurnModulated{E,R}` with `base`, `inner`, `rule` (`turn_modulated.jl:1426-1431`); the
constructor validates labels (empty, `'/'`, unique; 1318-1326) and the `PinkNoise` slot cap
(`_PINK_COMPONENT_STRIDE = 64`, `_RULE_COMPONENT_BASE = 1024`); `Adapt.adapt_structure`
methods on `TurnModulated`, `CompositeLine`, `MisalignedElement`, `RefTilted`
(`phase6d_track.jl:260-263`); the wrapper joins `_inner_method` (1461),
`_hidden_strong_beam_count` (`Tasks.jl:2295`), `_descend_strong_beams!`
(`strong_beam_track.jl:22`), `_survey_rebind` (1953) and `_aperture_rebind` (1837);
`update!` has no remaining call in `src/`; `TurnTable` holds `offsets, digest, name,
resolved_seed` with the length and finiteness checks (289-299) and the window check
`first_turn + nturns <= length(rule.offsets)` (1202). Section 8's nine tests have their
testsets (8052, 10391, 11311, 12272, 12488, 26625 and the part (k) stateless tripwire at
11086, the derived wrapper set at 10358-10378, zero-allocation and type pins at 10491-10587,
knob composition at 8058/8255, the Float32 table refusal at 12520/13071/13377); test 9's
script `validation/turn_modulation_spectra.jl` exists with the stated tolerances
(`WHITE_SLOPE_TOL = 0.15`, pink 0.2) and its README section (`validation/README.md:370-442`).
The owed quiet-machine benchmark and the `rng_id = 0` ordering are open ledger rows
(`docs/todo.md` rows 35 and 32). The snapshot lists `TurnModulated` among the runtime
wrappers (`registry_snapshot.md:393`); the rule names appear only in the example catalogue's
object list (332), consistent with "the snapshot lists only `TurnModulated`" as a registry
object.

**spectral_turn_table.md against the code (hypothesis 1).** `SpectralNoise(sigma, band,
spectrum; rng_id=0, turns, amplitudes=:fixed, f_rev=nothing)` (864) and
`spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id, slot=0, f_rev=nothing, ...)`
(748), both exported (line 1); `_SPECTRAL_PRESETS` is the one table the docstring derives
from (340-346); the canonical name has the D7 fields in order including `slot=` and
`amplitudes=` (449-450); the refusals of D6 and its remarks (turns >= 2, no bin, `applicable`,
a spectrum vanishing on every bin, a preset's name on a custom spectrum) and the fewer-than-32
warning through a `warn` flag (484-528); the phase and pair keys carry `slot` (563, 566);
`_warn_resolved_duplicate_tables` runs from both task kinds (`Tasks.jl:612, 1675`;
`interface.jl:3263`) and `_warn_resolved_seed_drift` at both execute paths (`Tasks.jl:565,
957`); the "third recompile trigger" is the `crecord === record` term of the compile cache
(`Tasks.jl:1660-1661`). The section 6 checks have testsets (11427 with the owner's generator
at 11602, 11962, 18861); the harness toggles `OCTOPUS_SPECTRUM`, `OCTOPUS_BAND`,
`OCTOPUS_SPECTRAL_AMPLITUDES` exist; the example's `:spectral` rule and the validation's
spectral case exist; `docs/public_api.md` carries both names; the ledger row is closed
(`docs/todo.md` row 25).

**twiss_dispersion_analysis.md against the code (hypothesis 1).** All fifteen names the
status paragraph lists are defined and exported (probe); the nine files it names exist; the
declaration rule yields 23 specs with `TwissDispersionAnalysis` (22 kinds plus `:line`) and
8 with `PlaceholderAnalysis`, none with neither (probe), matching "22 linear-map kinds plus
`:line`" and "eight kinds without an analysis"; the option table's other thirteen defaults
match `analysis_option_schema(TwissDispersionAnalysis)` (probe: `:auto`, `nothing`, `:error`,
`:require`, `nothing`, `0.0`, `:auto`, `:max_signed_z_area`, `:auto`, the five routes, 50,
`nothing`, `true`). The status paragraph's own list of body facts it leaves stale (five
versus eight placeholder kinds, "Octopus has none of this yet") is accurate.

**survey_and_reference_channel.md against the code.** The two dated body corrections (lines
64, 124) describe what landed: the symplectic z-shift with the cancellation-free `g(delta)`
(`rf_cavity.jl:64-118`), the declare-and-check energy survey with `ThinAcceleratingCavitySpec`
(`rf_cavity.jl:2, 697-698`), and the theory note `docs/theory/arc_survey_and_velocity_slip.md`.

**multi_process_policy.md against the policies, the seam, the extension and the solvers.**
`MultiProcessExecutionPolicy(; threads=:auto, ranks=:auto)` (`Policies.jl:310`) and the slot
`multi_process::Union{Nothing,MultiProcessRequest,MultiProcessContext}` on
`ResolvedCPUExecutionPolicy` (416-418); every seam function of the table has a core
passthrough (`_mp_allsum!`, `_mp_lane_fold!`, `_mp_allminmax`, `_mp_allmin!/_mp_allmax!`,
`_mp_bcast!/_mp_bcast`, `_mp_gather_rows`, `_mp_exchange_columns`, `_mp_isend` and the
rank queries, 537-1084) and an `MPI.Comm` method in `ext/OctopusMPIExt.jl` (47-242),
including `_mp_test_all`, `_mp_wait_any` and the tag upper bound; `_MP_ALLSUM_SCATTER_MIN =
2048` (ext 74), `Comm_dup` cached (42), `MPI.Init(threadlevel = :funneled)` (41);
`_record_collective!` asks both questions (`_ON_SPAWNED_WORKER[] || Threads.threadid() != 1`,
`Policies.jl:574`) and records `:multi_process_collective` (587); the communicator receipt
is `:multi_process_communicator` (`Beam.jl:446`); `_solver_divides` is `false` for
`AbstractPoissonSolver` and `true` for the four divided solvers (`interface.jl:2526-2528`,
`gaussian_pic.jl:132`, `spectral.jl:242`); the 4d-4h names exist (`pic_cpu_sliced.jl`,
`spectral_sliced.jl`, `_SPECTRAL_SLICED_LOOP`, `_spectral_collide_dataflow!`,
`_pic_df_predecessors`, `_spectral_sliced_solvers`, `_spectral_slice_pair_positions`,
`_pic_sliced_migrate_pair_in`), `pic_cpu_divided.jl` is gone as the note says it was retired,
`_spectral_note_grid_size` starts at 48 points (`spectral.jl:431-433`), both sliced collides
record `exchange=:sliced, schedule=loop`; `StrongStrongPICMultiProcessConsistencyContract` and
`src/contracts/mpi_pic_consistency_child.jl` exist; `_REDUCTION_CHUNKS = 64`,
`_PIC_DEPOSIT_CHUNKS = 16`, `_SLICE_FOLD_LANES = 4096`; `MPI` is a weakdep with
`OctopusMPIExt` (`Project.toml:18-26`); the ranks-greater-than-slices regime is an open ledger
row (`docs/todo.md` row 37); the two MPI launcher sections are full-lane gated (23018, 23813)
as "lane-gated" says.

## Unchecked

- The lane mechanism was not executed (no `lane=fast` or `lane=fats` run; a fast run takes
  about ten minutes and a `Pkg.test` spawn is not a short probe). The preamble, the gates
  and the banner were verified by reading; the lane's measured timings in section 2 of the
  note are dated 2026-08-13 and were not re-measured.
- The multi-process note's numerical claims (timings, scaling tables, parity classes, the
  collective counts other than the one in LEAD U51-13) were not re-measured: they are
  multi-rank benchmarks that take minutes to hours and belong to their history records. The
  step 4d-4h protocol details (tags, stages, buffer rules, owner deals) were checked for the
  existence of the named functions, not compared with the code stage by stage.
- The reference files were consulted claim by claim, not read whole, except `RunArtifact.jl`
  and the `runtests.jl` excerpts listed under Provenance: `interface.jl` (3432 lines),
  `turn_modulated.jl` (1974), `Tasks.jl`, `Policies.jl`, the extension and the solver files
  were not read line by line. Defects in those files outside the notes' claims are not
  covered by this unit.
- The twiss note's frozen body (pipeline tolerances, fixture table, back-transformation
  table) was not compared with the kernels beyond the option table and the declaration rule;
  the note itself says the implementation's amendments live in the campaign history, and that
  history (15000+ lines) was consulted only for stage 9 and the chord default.
- Cross-file seam, noted and not pursued: `docs/README.md` carries status descriptions of
  the twiss note ("stages 1 to 8", line 56-59; "stages 1 to 7", line 176-180) and of the
  survey note (the pre-correction design: "the dynamic part from `TrackingContext.turn`,
  loud refusal", line 75-78) that are stale in the same way as LEAD U51-10 and U51-11;
  `docs/README.md` is outside this unit's region.
- No MPI or CUDA probe was run; nothing in the eight notes' claims that this unit could
  check needed a device or a launcher.
