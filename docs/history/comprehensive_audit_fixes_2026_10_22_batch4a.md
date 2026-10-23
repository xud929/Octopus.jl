# Comprehensive-audit fix batch 4a (2026-10-22): the documentation-drift row

**Status:** complete 2026-10-22: the row's 98 markdown items swept through four units in one worktree (87 done, one partial pending a run, three found already fixed at HEAD, one deferred, the rest the integrator's or the owner's), the fast lane on the final tree green (section 3), the push authorized in advance by the owner (2026-10-22, "continue and push when appropriate"); the `.jl` halves are batch 4b's.

Batch 4a of the 2026-10-18 comprehensive audit's fix campaign
([`comprehensive_audit_2026_10_18.md`](comprehensive_audit_2026_10_18.md); batch 1 is
[`comprehensive_audit_fixes_2026_10_19.md`](comprehensive_audit_fixes_2026_10_19.md), batch 2
[`comprehensive_audit_fixes_2026_10_20_batch2.md`](comprehensive_audit_fixes_2026_10_20_batch2.md),
batch 3 with its 3b addendum [`comprehensive_audit_fixes_2026_10_21_batch3.md`](comprehensive_audit_fixes_2026_10_21_batch3.md)).
It closes the row "Documentation drift: notes, design notes, index, ledgers" (F-208, F-230, F-234,
F-19, F-64, F-65, F-136, F-180, F-231, F-233, F-235, F-241, F-242) in its markdown-only part, which is
the row's bulk: the audit's section 7b priced it as "small each, one sweep". Two of the thirteen ids
were already closed when the batch began (F-19 by batch 3's unit E, F-136 by batch 3's unit K: the
record's section 7b had assigned each to two rows at once and the range rows were fixed first).
Every lead whose fix touches a `.jl` file, a script or the suite is deferred to batch 4b and listed
in section 5, so this batch's diff names only `.md` files and its gate is the fast lane on the final
tree (the matrix's markdown-only class).

## 1 Method

- **A read-only extraction first.** Two agents read the record and the fix records without editing
  the tree: the first mapped every finding of the two batch-4 rows to its state at HEAD (165 Minor
  ids: 81 closed by batches 1 to 3, 34 named by other open rows, 50 open; the documentation row's 13
  ids with two already closed; stale F-id pointers in five other open rows; the record's own
  arithmetic), the second expanded the row's grouped findings through the unit reports (U13, U22,
  U40, U46 to U52, U55) into 98 numbered markdown items in 43 files, each with the current text
  quoted at HEAD, the evidence checked statically, and a proposed replacement, plus 13 `.jl` leads
  deferred and 4 `.jl` leads already fixed by batch 3. About a third of the record's line numbers
  had drifted; every lead but two was re-located (the multi-process note's "five superseded
  paragraphs" have no per-unit anchor beyond two; one lead's text was already gone).
- **Four sweep units in one worktree.** `fix4-docs-sweep` cut from main at 3056167 (batch 3b's
  push). Each unit owned a disjoint file set and edited in place without committing: T1 the
  beam-beam, crab, spectral and Twiss theory notes with `validation/README.md`; T2 the geometry and
  lattice theory notes; D the design notes, the guides, `current_runtime.md`, `public_api.md` and
  the audit protocol; L the root README, the index, `experiences.md`, the ledger's pointer hygiene
  and the one frozen-record addendum. The integrator reviewed the whole diff and committed once.
- **Rules that bound the sweep** (`result/`'s brief, not tracked): markdown only, no Julia run
  (evidence is static: the source read, call sites counted), `result/` is never evidence (a claim
  resting on it names the committed carrier or says it has none), a count the suite derives is
  stated by its derivation or dropped, status banners and pointers become dated statements naming
  what landed and the record that holds it, design notes are living documents edited in place with
  the date and the record (AGENTS.md: only `history/` is frozen), `docs/history/` records change by
  addendum only.
- **Owner decisions.** Five items were not factual corrections; the integrator applied stated
  defaults and reports them (section 4). AGENTS.md, the owner's file, was not edited.

## 2 Units and what landed

### Unit T1: the beam-beam, crab, spectral and Twiss theory notes; `validation/README.md` (F-208, F-230, F-231, F-242)

Thirteen files, 27 items: 25 done, 1 partial, 1 deferred. The Bassetti-Erskine display of
`gaussian_subtracted_pic_solver.md` (F-230) was verified against the kernel before the swap:
`_elliptic_gaussian_kick_principal` (`src/elements/strong_beam.jl`, the `sig1 >= sig2` branch)
assigns `K_x = imag(ret)` and `K_y = real(ret)`, and the far field `w(z) -> i/(sqrt(pi) z)` gives the
real part `2y/r^2`, so the display now reads `K_y + i K_x` with the function named. Claims resting on
`paper/data/*.tsv` are retracted in place (the directory is not in the tree and no committed script
produces the numbers); the lattice-kernel "re-measured with that documented harness" claim is
re-pointed; the rigid-bunch statement, the node-grid remedies, the `eta` convention, the spectral note's
section 15 future tense, the stale cost table and the `_pic_validate` name are corrected to the code.
`crab_cavity_noise_response.md`: the doubling-time column low by `ln 2` (two further rows of the same
table had the same defect and were fixed with it), the approximate residual-rms column, section 4.5's
pointer to the owner row the 2026-10-18 decision closed, and the sweep plan and acceptance list the
script replaced (A05/A1/A2; `SWEEP_DEFAULT_ORDER` omits A05, A2 and A4s, so `validation/README.md`
now says they run on request through `cases=` rather than listing them as default cases).
`twiss_dispersion.md`: the "gated" forced-4D/6D distinction and the unverified MAD-X `deltap` clause
qualified. Partial: the near-round note's harness maxima (U46-1) cite the committed 2026-10-18
re-run (Float32 5.4797e-6 on the Sapphire Rapids host, CUDA active) in a dated paragraph and the
section 11 bound with margin; the table itself still needs
`validation/near_round_gaussian_transition.jl` on a host whose identity and libm are recorded.
Deferred: the hand-copied prediction defaults of the crab script (D13).

### Unit T2: the geometry and lattice theory notes (F-233, F-241; F-180's and F-233's `.jl` halves deferred)

Nine files, 22 items: 18 done, 1 deferred with its pin (D18), 2 already fixed at HEAD by batch 3's unit H (the SAD cubic's
`1/(1+delta)`, F-164 = U48-5, c7f5757, whose residual `h^2`-for-`b^2` symbol (the kernel's `c3 = b * b / (72 * fg) / p` is the field) is deferred with the F-164 testset's pin of the `h^2` strings, D18 -- the fast lane's first run on this tree failed exactly there, 2 of 8; the solenoid
note's sqrt-guard paragraph, 092263b), 1 qualified from a static read. Status banners became dated
statements: `floor_plan_survey.md` ("written BEFORE the implementation": derivation 2026-08-14, verified
at implementation the same day, `survey`/`FloorFrame` and `MADXSurveyConsistencyContract` named),
`arc_survey_and_velocity_slip.md` ("remains future work"), `rf_cavity_and_reference_energy.md`
("question 3 remains open" against its own struck-through settlement, the dangling `todo.md` pointer,
the over-claimed section 8), `bpm_measurement_model.md` ("no naming scheme": `BPMObserver(name; ...)`
and the artifact group `/bpm/<name>`), `misalignment_and_patch_maps.md` (the recommended factorisation
the implementation did not take; the `:madx` convention paragraph), `aperture_and_particle_loss.md`.
Evidence corrections against the worklist: the 2026-08-14 orientation note of the archive is the record
for the floor-plan and `harmon` landings (the neighbour audit of that day does not mention them); the
arc-survey probe number quoted to U49's full digit; an uncarried `5e-13` replaced by
`PTCConsistencyContract`'s `default_atol = 1e-11`; the conventions note's ulp attribution read from the
suite's pinned literals (the curved-drift z pin is 4 ulp at `h = 1e-3` and 16 at `h = 0.35`, so 4.7
belongs to `h = 0.35`). Section 4 holds the three not-planned decisions.

### Unit D: design notes, guides, `current_runtime.md`, `public_api.md`, the audit protocol (F-64, F-65, F-234's protocol half, F-235)

Thirteen files, 24 items, all done. `run_artifact.md`'s schema table now documents what the writer
stamps (`/luminosity/<label>`: `label`, `rows_valid_through_turn`; probes: `name`,
`rows_valid_through_turn`, and `s` only when line-placed; no provenance attribute anywhere; F-64) with a
dated note under the table, and `/elapsed_time`, which the artifact does not write either (the
`MomentOutput` reader refuses it and points to `read(TaskOutput(path), :execution)`), is stated so; the
concurrent-reader number cited from `result/` is struck and a committed harness named as owed (F-65),
the prose record of the 2026-10-16 crab-noise fixes cited; the decided-but-never-implemented probe
`name` default (U51-3) is struck with a dated note (`BPMObserver`'s `name` is positional with default
`"bpm"`; the other two observers require it). `multi_process_policy.md`: "Lifting the ceiling" sits
above the 4g series, the task-held 32-rank number on the 64x64 mesh is 47.4 ms (39.7 ms is the 63x63
mesh); the all-sum count per collide carries the worklist's interim qualification (a static count of
`_mp_allsum!` call sites, 33, is not the per-collide number the text carries; the run is owed, section
8). `testing_lanes.md` and `development_workflow.md`: the retired "before every commit" rule becomes
the Definition of Done's "before every push" (owner decision 2026-09-04); the heavyweight-section count
derives itself (17 distinct `_lane_gate` titles at HEAD; the text says how to count). `configuration.md`'s
"by hand (an open row)" for a closed row; `twiss_dispersion_analysis.md`'s `resolution_chord` 1e-4
design default against the shipped 1e-3, with the history pointer; `survey_and_reference_channel.md`'s
status line, the `_requires_tracking_context` statements, and the U51-11 precision-pin bullet (not gone
at HEAD, as the worklist believed; marked superseded); `public_api.md` gains `survey`, `FloorFrame` and
`with_index_offset` (exported, documented, omitted); `current_runtime.md`'s `TrackingContext` field
list gains `index_offset` and its per-turn hook paragraph no longer contradicts itself.

### Unit L: the root README, the index, `experiences.md`, the ledger's pointers, the frozen record's addendum (F-234, F-235, the pointer hygiene)

25 items: 19 done, 6 skipped (the two AGENTS.md items report-only, section 4; the record's index entry
and the row's state cell, the integrator's with this record; one already fixed at HEAD; one note on a
frozen file). Root README: the push rule, the grid and cost citation split between the theory note and
the 2026-07-23 record, "two cases" for the three catalogued harnesses (of five examples). `docs/README.md`:
Scope B landed 2026-08-14 and the F16 slip closed the same day, `run_artifact.md` implemented
2026-08-18, the lane-gate count derived (13 at 2026-08-13; 17 `_lane_gate` titles at 2026-10-22), the
newest neighbour audits, `gpic_wobble_capture_2026_08_19.txt` indexed beside its `.md` sibling, "243
findings, 13 Major" corrected to 244 and 15. `experiences.md`: the lesson describing ledger state that
ended 2026-09-07, the measured-false `get_extension` sentence corrected with the retraction and the U55
probe cited, and one preamble sentence for the six lesson-only numbers (section 4). `docs/todo.md`: the
stale F-id pointers in the Twiss, artifact, MPI and two instrument rows marked closed with their batch
and unit, the campaign row's "243 findings" corrected. The audit record's addendum (frozen file, add
only) quotes the lines verified: the Totals paragraph's "14 Major" lists fifteen ids; the by-tag census
is 15 Major, 64 Moderate, 165 Minor = 244, F-1 to F-244 each once; the fourteen section-7b Major rows
are the source of "13" and "14"; F-7 (the stale CUDA validation script) was closed by batch 1's unit X
with the id named nowhere; F-243's `hvoffset` item was closed by batch 3's unit I.

### The integrator

The addendum's record name; six same-defect neighbours the units listed but did not own by paragraph:
`current_runtime.md`'s per-turn rebuild (the `@generated` `_update_line_unrolled` since 2026-10-16, not
`ntuple(..., Val(N))`), `coherent_beam_beam_modes.md`'s two "committed archive/spectra" phrasings (the
2026-08-05 `result/` archive, not committed), `solenoid.md`'s "written before the implementation" banner
and its "a patch element does not exist yet" paragraph (`PatchSpec` since 2026-08-02; the note's
"Section 7.5" is section 7), `beam_line_composition.md`'s "observers have no identity scheme". The
`.jl` leads already fixed by batch 3, named here so no 4b unit re-finds them: F-233/U49-2 and U49-4
(`floor_plan.jl`'s `survey` docstring and header, unit K), F-241/U48-11 (= F-134, unit K),
F-231/U46-8's code side (= F-119, unit I, 32b2b57).

## 3 Verification

- **Static, by the units** (no Julia run in the sweep): every replacement asserted exactly one anchor
  occurrence; the suite's content tripwires that read these documents were grepped on the edited tree
  (`current_runtime.md`'s backends section; `run_artifact.md`'s ledger column names, rule kinds and
  forbidden phrasings; `turn_modulation_record.md`'s shared terms; `multi_process_policy.md`'s "one per
  DIRECTION" with the two F-19 phrasings absent); the docs-index rule re-run over `docs/` (0 unindexed
  `.md`, 0 dangling index targets); `docs/registry_snapshot.md` untouched; the diff names 41 `.md` files
  and nothing else (the markdown-only class of the matrix).
- **The gate**: the fast lane's first run on the sweep's tree was red at one testset, unit H's F-164 tripwire pinning the conventions note's `h^2` strings that unit T2 had corrected to `b^2` (2 of 8; the record's D18 defers the coupled change); the symbol reverted, the second run green: exit 0, 398 summaries, 0 Test Failed, 0 Error During Test, 17 LANE SKIP lines, no unindexed document (`fast_lane_wt_b4a_final2.log`, 22:07:13 to 22:53:04, 46 min under a load of 32), run on this tree before this sentence was filled in.
- **Arithmetic re-done by the units**: the centred rms of the crab note (0.0421/0.1539 against the
  quadratic 0.0434/0.1735), `f_rev = 78196.75 Hz` and the `ln 2` doubling times, the 244/15 census.

## 4 Owner decisions applied as the integrator's defaults

| Item | Decision needed | Default applied |
|---|---|---|
| AGENTS.md matrix row "validation, study, or benchmark ... full, before the commit carrying the claim" (U52-1) | the owner's file | untouched; after this batch it is the last "before the commit" in the markdown (the suite banner's copies are 4b's). Proposed: "before the push carrying the claim", the Definition of Done's rule. |
| AGENTS.md's one date, "(owner decision 2026-09-04)" in the Definition of Done (U52-5) | the owner's file | untouched. Options: replace the date with a pointer to `docs/experiences.md`'s process habits, or amend the invariants-only decision to allow decision dates. |
| `run_artifact.md` schema attributes the writer never stamps (F-64) | document the writer or change it | documented the writer as it is, dated; the writer-side change stays an option. |
| `run_artifact.md` concurrent-reader number from `result/` (F-65) | strike, keep qualified, or harness | struck; a committed harness named as owed (no todo row carries it yet: the run-artifact niceties row takes the clause, section 6). |
| `run_artifact.md` "probe `name` defaults to its provenance path" (U51-3) | implement or strike | struck with a dated note (never implemented, never ledgered). |
| Open items in three theory notes with no todo rows (conventions note section 8: a VA/VS utility, the measured `curved_order` default; the RF note: a PTC case for the accelerating cavity; the solenoid note: a misaligned-solenoid reference case) | rows or not planned | recorded as not planned, dated, in the notes' status lines. |
| Six lesson-only numbers in `experiences.md` (U55-7) | preamble or per-number qualifiers | one preamble sentence. |
| Minor: the root README's grid citation `(127,383)/8` against the spectral record's `(128,1024)/16`; the Twiss row's pointer to F-172 | which to cite; retire the row | kept the pair that matches the example and the record's measurement; the pointer corrected, the row kept (its open thirds are semantic). |

## 5 Deferred to batch 4b (every lead whose fix touches a `.jl`, a script or the suite)

| # | id | file | lead | 4b unit |
|---|---|---|---|---|
| D1 | F-180 / U22-5 | `src/analysis/dispersion_routes.jl:58` | "by twelve decades either way" is 2.4 decades on the rejected side | TW |
| D2 | F-180 / U22-6 | `src/analysis/degenerate_dispersion.jl:61` | the `_CLUSTER_FRAME_N4_MULTIPLIER` window edge omits its factor ten | TW |
| D3 | F-180 / U22-7 | `src/analysis/dispersion_routes.jl:849` | the branch-check floor's underived `max(1, ||M||_F)` | TW |
| D4 | F-180 / U22-8 | `src/analysis/dispersion_routes.jl:456` | `tau_s` documented as `2 cos mu_s`, is `Re(rho + 1/rho)` for a blocked cluster | TW |
| D5 | F-231 / U46-9 | `src/elements/strong_beam.jl:67, 269` | two docstrings write the Hirata energy term as `S/2 (px^2 + py^2)`; the kernel has `/4` | TR |
| D6 | F-231 / U46-10 | `src/tasks/strongstrong/pic_cpu.jl:2552` | the removed `:quantile` estimator still listed | SS |
| D7 | F-233 / U49-14 | `src/elements/patch.jl:6, 303` | "Section 7.5" of a note that has no 7.x heading | TR |
| D8 | F-233 / U49-7 | `src/elements/rf_cavity.jl:963` | "symplectic after undoing the rescale ... pinned": only `det(J) ~ rho^3` is pinned | TR |
| D9 | F-235 / U51-2, U52-3 | `test/runtests.jl:8, 38657` | the fast lane's closing banner still says "before any commit" | TS |
| D10 | F-235 / U52-13 (= F-149) | `test/runtests.jl` ~214-232 | the docs-index check is `.md`-only and matches basenames as substrings | TS |
| D11 | F-241 / U48-8 | `test/runtests.jl`, the solenoid transverse pin | `transverse_ulps <= 64` holds for the suite's seed only (110, 215 under other seeds) | TS |
| D12 | F-241 / U48-9 | `test/runtests.jl`, the solenoid `L = 0` identity | the bitwise pin holds for 44 % of random particles | TS |
| D13 | F-242 / U50-7 | `validation/crab_cavity_noise_response.jl:23, 1794-1801` | hand-copied prediction defaults with no tripwire; `SWEEP_DEFAULT_ORDER` omits A05, A2, A4s | VA |
| D14 | F-242 / U50-6 | `src/elements/strong_beam.jl:1376-1378` | the `deltap` clause propagated verbatim | TR |
| D17 | F-231 / U46-7 (option) | `validation/gaussian_slicing_convergence.jl:99` | add 1, 4, 11 to `ns_list` so the slicing note's cells reproduce | VA |
| D18 | F-241 / U48-5 residual | `docs/theory/lattice_hamiltonian_and_conventions.md` 6.3.1 and `test/runtests.jl`, the F-164 testset | the SAD cubic is written with `h^2` where the kernel (`c3 = b * b / (72 * fg) / p`) and the testset's own comment have the field `b^2`; the testset pins the `h^2` strings, so note and pin change together | TR or TS |

Also for 4b, found by the sweep: `test/examples/weak_strong_tracking.jl:175-177` repeats the false
"`OctopusMPIExt` under `using Octopus`" sentence (needs "followed by `using MPI`"); `docs/design/testing_lanes.md:46`'s
"exactly the 13 measured heavyweights" is a hand-copied count in a dated history sentence (left as history).

## 6 Ledger

Batch 3b (unit H and the straight drift's radicand) was pushed as 3056167 on 2026-10-22 at 21:16; its CI run 469
completed green at 22:02 (the batch 3 record is frozen, so this record carries that result).

The documentation-drift row moves to `todo_ledger_archive.md` with its closing measurements; the
campaign pointer row records batch 4a and what is left for the owner; the Minor pointer row stays open
for batch 4b, and the run-artifact niceties row and the multi-process row each take one clause for a
debt this batch could only name (the concurrent-reader harness; the per-collide `_mp_allsum!` count at
the 4g configuration). The record's index entry is beside batch 3's. The audit record's addendum is the
frozen file's only change. `docs/experiences.md` gains one lesson (section 7).

## 7 Lessons recorded

**A status banner is a dated claim.** "Written before the implementation", "remains future work",
"question 3 remains open", "does not exist yet", "remains design only": every one was true the day it was
written and false by the audit, and none said when it was written or what would retire it. The sweep
made each a dated statement naming what landed and the record that holds the measurement; a banner that
cannot name its retirement condition is a pointer to a row, or it is not written. Its sibling: a count
the suite derives (heavyweight sections, findings, Major rows) is stated by its derivation or dropped --
three hand-copied counts disagreed with the tree by two to four.

## 8 Not verified

- Three items need a run the sweep did not make and carry the worklist's qualifying text instead: the
  per-collide `_mp_allsum!` count of the multi-process note (`_mp_collective_times` at the 4g
  configuration), the near-round note's harness maxima table (`validation/near_round_gaussian_transition.jl`
  on a recorded host), and the conventions note's ulp attribution beyond what the suite's pinned
  literals say.
- Two leads were not located at HEAD: the record's "five superseded-behaviour paragraphs" of the
  multi-process note have no per-unit anchor beyond two (both fixed); U51-11's text the worklist thought
  gone was found and marked superseded by unit D.
- The two AGENTS.md items are the owner's (section 4). Nothing in `src/`, `test/`, `validation/*.jl`
  or the snapshot changed; the `.jl` leads are section 5's.
