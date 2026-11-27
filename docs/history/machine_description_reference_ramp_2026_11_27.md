# Machine description follow-ups, batch C: the reference ramp (2026-11-27)

The record of the ramp campaign: ruling R7 of
[`../design/machine_description_followups.md`](../design/machine_description_followups.md)
(section 3, "Batch C"), the theory note
[`../theory/reference_ramp.md`](../theory/reference_ramp.md) written first
(commit `2ea0709`, markdown only, its own fast lane) and the implementation
the same day, in one commit after it. The owner's four physics choices of the
day are in the note's section 5; the note's "Implemented:" paragraphs state
where the landed code departs from its first text.

## 1. What landed

- `src/tasks/ReferenceRamp.jl` (new): `ReferenceRamp(program; reference,
  start_turn=0, name="", companions=())`, an `AbstractBeamAction` placed LAST
  in the line. The program is the total reference energy per turn in eV,
  content-addressed by its SHA-256 (the snapshot's bulk-table digest); the
  reference is the lattice's `ReferenceParticle`, whose energy must be a bare
  knob reference in any of the four spellings, and the action assigns that
  knob in its own spelling. At the end of turn `n` the action applies the
  boundary map of the note's section 2 on the representation's own arrays
  (`px .*= rho`, `py .*= rho`, `pz .= fma.(rho, pz, rho - 1)`) when the
  program's energy for turn `n + 1` differs from the knob's, then
  `set_knob!`; companion knob programs (`synchronous_phase_program` builds
  the RF phase one) are assigned at the same boundaries and set to the first
  turn's value as a window starts. `action_option_schema` (the action twin of
  the observer and schedule schemas), the compile check
  (`_check_reference_ramp_placement`: last, one, `AlwaysSchedule`, not beside
  a `PhaseSpaceReset` or particle tunes), the run check
  (`_check_reference_ramp_run`: the lattice's reference, every ring cavity's
  `beta0` and `strength` as knob expressions, the knob at the program's
  first-turn value; then the companions), the window start
  (`_start_reference_ramp!`: the steps count, the no-step warning, the
  `:reference_ramp` receipt), the task-level refusal (`_push_task_hook!`) and
  the knob-root sites of the hook (`_knob_binding_sites!`).
- `src/tasks/Tasks.jl`: `_runtime_entries` runs the placement check once per
  compile; `_execute_tracking_task!` runs the run check before the artifact
  opens, the window start after the per-run receipts, and its turn loop
  carries the one extension of the note: after the task-level actions,
  `ramp !== nothing && _runtime_entries_stale(task)` recompiles the line
  through the compile cache (which empties the plan cache) and re-derives
  the physics line, the hook entries and the strong-beam list under fresh
  `live_*` names (no closure captures them; the `Core.Box` sweep is green);
  `:reference_ramp_recompiles` after the loop counts the recompiles.
- `src/elements/beam_line.jl`: the knob-root walk (`_knob_binding_sites!`)
  descends a hook placed through a `LineEntry` by the hook's own method, so
  a ramp's reference and companion knobs are binding sites of the line (D7)
  and a companion outside the roots is refused by the `Lattice`.
- `src/lattice/toml_hooks.jl`: the codec, `type = "ReferenceRamp"`,
  `reference` the reference table, `start_turn`, `name` when given,
  `program = { sha256, length }` as a bulk table, `companions` an array of
  `{ knob, program = { sha256, length } }`; registered, with the decoder's
  refusals by name. `src/lattice/toml.jl`: the digest scan
  (`_toml_collect_digests!`) recognises any inline table with a 64-hex
  `sha256`, typed object or bare program table, so the sidecar and the
  artifact's `/machine_tables` are read for the ramp's tables.
- `src/tasks/strongstrong/interface.jl`: `_split_strong_strong_line` refuses
  a ramp by name (the owner's scope choice); `validate_configuration_metadata`
  walks the concrete `AbstractBeamAction`s (one schema each, every option
  with a consumer, `BeamSwapAction` exempt by name) and checks the ramp's
  defaults against a constructed default ramp.
- `src/Octopus.jl`: the include after `tasks/ParticleTunes.jl`.
- `test/runtests.jl`: four testsets "Reference ramp: ..." (targets 1, 3a and
  4 of the note, the refusals, the snapshot and the metadata, the CUDA twin)
  and the ramp instances in the codec roster tripwire (MD4-B).
  `validation/reference_ramp.jl` (new; targets 2 and 3b and the recompile
  cost), `validation/README.md`, `docs/public_api.md`,
  `docs/registry_snapshot.md` (regenerated: `ReferenceRamp`,
  `action_option_schema`, `synchronous_phase_program`), the theory note's
  "Implemented:" paragraphs, the follow-ups note's statuses, `docs/README.md`,
  `docs/todo.md` (row 22 and the ramp's follow-ups row), `docs/experiences.md`
  (three lessons).

## 2. The theory note's targets, measured

Red first: the four testsets against the main checkout at `2ea0709`
(`ReferenceRamp` undefined; `result/gates/ramp/red/batch_c_red.log`).

**Target 1, adiabatic damping, exact** (suite): 10,000 Gaussian particles
through a linear 4D rotation (beta 10 m and 5 m, tunes 0.31 and 0.27) with
`R56 = -alpha_c C`, a 10-step staircase of 10 MeV every 10 turns from 2.5
GeV: `epsilon_x P0`, `epsilon_y P0` and the longitudinal covariance
determinant times `P0^2` constant to better than 1e-12 at every recorded
turn; the knob ends on the program's last entry; one window of 100 turns is
the ten chunked windows bit for bit; a flat program is the identity bit for
bit, moves no epoch and warns once ("steps nothing in this window").

**Target 2, the synchrotron tune follows the program**
(`validation/reference_ramp.jl`, `result/gates/ramp/validation_run.log`): the
F16 ring, 2.5 to 3.5 GeV over 10,000 turns, `phi_s = asin(0.5)`, a particle
at `delta = 1e-4`; the tune of each 2,000-turn window (Hann-windowed DTFT,
the F16 testset's estimator) against the linearised one-turn map at the
window's mid-turn energy:

| window (turns) | E0 mid [GeV] | eta mid | nu_s measured | nu_s predicted | ratio |
|---|---|---|---|---|---|
| 0-1999 | 2.6000 | 0.0698 | 9.191396e-04 | 9.222243e-04 | 0.99666 |
| 2000-3999 | 2.8000 | 0.0877 | 9.794190e-04 | 9.862813e-04 | 0.99304 |
| 4000-5999 | 3.0000 | 0.1022 | 1.018387e-03 | 1.020169e-03 | 0.99825 |
| 6000-7999 | 3.2000 | 0.1140 | 1.038478e-03 | 1.036673e-03 | 1.00174 |
| 8000-9999 | 3.4000 | 0.1238 | 1.046288e-03 | 1.042536e-03 | 1.00360 |

Worst `|ratio - 1|` 7.0e-3 against the 1% tolerance; the window tunes differ
by 1.14 along the ramp (the note expected "near 1.2": the exact `acos` form of
the map, not the square-root approximation, is what the script compares
against, and the two windows' ratio is 1.138 in either form). The knob ends
at 3.5 GeV, the program's last entry.

**Target 3a, the fixed point** (suite, 200 turns; the script, 10,000 turns):
the particle at the origin stays within `4.2e-12` m in `z` and `1.1e-15` in
`delta` over the full ramp (tolerance 1e-9 each); on CUDA the same ring gives
the same bound. **Target 3b, bucket motion** (the script): with the phase
held at zero, a particle launched 0.5 m from `z1 = C asin(dE/qV)/(2 pi h) =
8.333 m` oscillates about it; the mean `z` per window:

| window (turns) | mean z [m] | mean z / z1 | z range [m] |
|---|---|---|---|
| 0-1999 | 8.29909 | 0.99589 | 7.8119 .. 8.8511 |
| 2000-3999 | 8.33301 | 0.99996 | 7.7951 .. 8.8716 |
| 4000-5999 | 8.34107 | 1.00093 | 7.7861 .. 8.8823 |
| 6000-7999 | 8.35020 | 1.00202 | 7.7812 .. 8.8881 |
| 8000-9999 | 8.35759 | 1.00291 | 7.7790 .. 8.8917 |

Worst `|mean z / z1 - 1|` 4.1e-3 against the 1% tolerance.

**Target 4, effectiveness and refusals** (suite): the `:reference_ramp`
receipt per `execute!` (digest, knob, key, window, the energies at its ends,
the steps, the companions), `:reference_ramp_recompiles` after the window (0
on a line with no knob-dependent element, 99 for 100 steps on the ramped
ring), the `:hook_schedule` receipt active on every turn; twenty-eight
refusals by name (construction, placement, task-level hook, `PhaseSpaceReset`
and particle tunes, the kept-whole sub-line, the plain-number cavity, the
knob off the program, the lattice reference mismatch, the companion outside
the knob roots, the strong-strong task) and the well-formed controls in both
spellings.

**The backends** (suite): the boundary map on a 256-particle beam through a
zero-length drift and four steps is bit for bit the same on CPU threads and
CUDA (two multiplications and one `fma` per particle); the ramped ring on
CUDA keeps the fixed point to 1e-9.

**The recompile cost** (the script, one particle, one thread, 2,000 turns,
the program stepping every turn against a flat program):

| line | s/turn, stepping | s/turn, flat | overhead per step [s] |
|---|---|---|---|
| F16 ring (4 entries) | 5.781e-05 | 2.722e-06 | 5.509e-05 |
| 40-cell FODO + cavity (162 entries) | 4.707e-03 | 4.286e-05 | 4.664e-03 |

The step recompiles the whole line (the compile cache's unit) and rebuilds
the plans; a selective recompile is the follow-up (section 6).

## 3. Decisions, and the departures from the note's first text

- **The program holds at its ends** rather than refusing a window it does
  not cover (the note's first target 4 wanted the turn table's refusal): a
  flat top is physics, and a continued run past the program is the stored
  beam. A window that reaches no step of any program warns once by name.
- **The energy spelling.** The table stores energies; the action converts to
  the knob's key (`E0`, `p0c`, `gamma0`, `brho`) at each assignment by the
  reference's own formulas, so the receipt and the snapshot carry energies.
- **Companions** were not in the note's first route; the owner's choice 3
  (the RF phase the user's through a knob program) needs a knob program
  assigned at the same boundary, and one object placed last keeps the
  placement rule simple.
- **The whole-line recompile.** The note's first text said the plain-number
  magnets "are not rebuilt"; the compile cache rebuilds the line as a unit,
  measured above, and the selective recompile is deferred by decision.
- **MPI at one rank.** The note's first text claimed the map on "the three
  backends"; a run divided across ranks refuses line actions by the standing
  rule, the ramp included, so the map reaches MPI at one rank only. Lifting
  the refusal for the ramp (rank-local by construction) waits for a two-rank
  parity run.
- **The companions are set before the artifact's snapshot** (the lesson in
  `docs/experiences.md`): found by the snapshot testset, which read the
  declared value back from the embedded snapshot while the run tracked with
  the program's.
- **`steps` and `recompiles` are two receipts.** The window's 100 boundaries
  step 100 times; 99 recompiles follow inside the window; both are reported.
- **The flexible `TurnTable` was not reused** for the program: its
  modulation semantics (offsets, `resolved_seed`, the device drop) are not
  the ramp's; the program is a `Vector{Float64}` with the codec's digest.

## 4. The neighbour audit (scoped to the touched sites)

Re-walked after the fix-and-feature work: (a) every read of
`runtime_entries`, `runtime_elems`, `hook_entries` and `strong_beams` inside
the turn loop moved to the `live_*` bindings (the plan build, the plan key,
the luminosity push); the prologue's bindings (the observers' prepare, the
channel labels, the `finally` finalization of the line observers) keep the
first compile's entries, which wrap the same observer objects a recompile
re-wraps, so prepare and finalize see one observer. (b) `_bind_line_entries`
on a recompile re-attaches the SAME loss record (identity-keyed) and
re-assigns the aperture ids in the same order; `_warn_resolved_duplicate_tables`
dedups through `task.reported_sharing`. (c) The knob-root walk's new
hook arm delegates every non-element placement to the generic method, which
returns the sites untouched for observers and markers (no behaviour change
without a ramp). (d) The digest scan's generalisation matches the
`TurnTable` object as before and the bare program table; no other `sha256`
key exists in the format. (e) `_reject_unsharded_tracking_features` counts
the ramp as a line action (refused under more than one rank, by design for
now); `PhaseSpaceReset` and particle tunes refuse line actions at their own
sites, and the placement check refuses the ramp beside them earlier, at
compile. (f) `classify_task_hooks` is shared with the strong-strong task, so
a ramp handed as a task-level hook there is refused by the task-level
message before the compile's. (g) The fast-path predicate is untouched: a
line with a ramp has a hook and takes the general loop. (h) Known
limitation, carried in the todo row: the turn-modulation recorder's nominal
columns are those of the window's first compile. Not verified by the suite:
a `Float32` representation through the map (`_ramp_rescale!` casts `rho` to
the coordinates' element type; no Float32 line was tracked with a ramp).

## 5. Verification

- Extracted before the lane: the four testsets, the codec roster tripwire,
  "Every export is documented", "No docstring is detached by comment lines",
  "No method grows a Core.Box outside the argued allowlist": green.
- `validate_configuration_metadata()` true (in the testset); the registry
  snapshot regenerated and pinned by the suite.
- The CPU fingerprints of the four shipped examples against the batch B
  baseline (`result/gates/md5/compare/post.log`, the recipe of the stage 3
  record at the weak-strong, strong-strong, crab-noise and DBA sizes it
  states): all 20 rows identical on CPU threads
  (`result/gates/ramp/fingerprint_cpu.log`); the examples have no ramp, so
  the general turn loop's rebinding under fresh names changed nothing they
  track.
- The fast lane on the worktree (a checkpoint, 01:38-02:20 EST,
  `result/gates/ramp/fast_lane_wt.log`): green, 498 rows, 160,083 pass. It
  did NOT run the four new testsets: they had been inserted inside the
  lane-gated block of "Machine description: the effectiveness contract's
  expression arm" (its skip banner names that testset alone), which the
  extracted runs could not show. Moved out of the block before the gate;
  the full gate and the fast lane on the committed tree ran them
  (the four rows above; the fast lane's numbers go to the next ledger touch, as the batch B record's did).
- The full gate at CI settings, CUDA active, on the final tree:
  green: exit 0, 519 rows, 163,630 pass, no failure or error, no lane skip, the
  CUDA arm's 225 checks included (02:22:40 to 04:02:50 EST 2026-11-27, 100
  min, `result/gates/ramp/full_gate_native.log`, on the tree
  `3a917f67da3b8e43e14025100eb3d8d65dd9ecc3` of `result/gates/ramp/gated_tree.txt`,
  which is this commit's tree but for this record's filled placeholders).
- The theory note's own gate (markdown only): the fast lane on the main
  checkout, green, 498 rows, 160,079 pass (00:42-01:23 EST), pushed as
  `2ea0709`; its CI run 497 (id 45952502520) completed success, 06:32:22 to
  07:35:07 UTC 2026-11-27 (62 min 45 s), the Julia 1.12 CPU full-lane job
  green.

## 6. Open items carried

The ramp's follow-ups row in `docs/todo.md`: the selective recompile of the
knob-dependent entries alone (the 4.7 ms per step above), the ramp under
more than one MPI rank, the strong-strong ramp, and the recorder's stale
nominal columns; transition crossing stays out of scope (the note's section
5). The previous pushes' ledgers: CI run 496 (`b00c586`, batch B) completed
success at 05:15:52 UTC 2026-11-27 (the Julia 1.12 CPU full-lane job green).
