# Crab-cavity noise neighbour audit: fix batch 2 (2026-10-16)

**Status:** landed 2026-10-16/17 on `crab-noise-audit` (four unit commits, four merges, three integration commits and this record's commit), gated 2026-10-17 in both CPU arms with CUDA active, the arms one after the other; push pending the owner's word; CI on the push.

**Scope.** The second owner-decided batch on the 2026-10-16 neighbour audit's
ledger ([the audit](audit_crab_cavity_noise_neighbours_2026_10_16.md);
[batch 1](crab_cavity_noise_audit_fixes_2026_10_16.md), pushed as ac3fbb2):
the three owner decisions the first batch had left open, then the seventeen
small rows the audit priced and did not fix, plus the three small follow-ups
the first batch's units surfaced. Owner instruction: "Start the three owner
decisions now, then rest." Method as in batch 1: the protocol's fix phase
(reproduce first; a regression test shown red on the unfixed tree; a
neighbour re-walk per fix), four parallel units in their own worktrees,
integrated on `crab-noise-audit`, gated as one batch.

## 1 Owner decisions (2026-10-16, this session)

1. **A partial `/turn_modulation` slot after a mid-write error** (the stage
   3-4 audit's U5-2, restored by the audit's U8-9): the reader reports, no
   rollback. The writer creates each slot group's cursor before its rows, the
   public readers recognise a partial slot and report it by name instead of
   erroring, an append onto such a file is refused by name, and the design
   note documents the partial slot as the crash artefact it is. Rolling back
   (deleting the half-created group, which HDF5 does not reclaim and which
   can itself fail) and documenting only were offered and declined.
2. **The frozen stage 0 record** (U8-7): an addendum, the convention its
   siblings follow, appended to
   [`crab_cavity_noise_relative_strength_2026_10_15.md`](crab_cavity_noise_relative_strength_2026_10_15.md)
   (pushed as c070750, CI run 454 green); the body stays verbatim.
3. **Float32 beams through every element kind** (batch 1's unit D measured
   every kind narrowing on the CPU and twelve of thirty-one failing at CUDA
   device compile): one rule, refuse every mismatch. Every kind declares its
   parameter type as the required beam type, so a Float32 beam needs Float32
   elements everywhere; kinds without a typed constructor form get one; the
   Float32 tests and examples that relied on narrowing are rebuilt with
   Float32 elements. Converting to the beam's precision at compile, refusing
   only the CUDA-failing kinds, and keeping the narrowing documented were
   offered and declined.

## 2 Units and what landed

Each unit reproduced its defects on the unfixed tree ac3fbb2 first, wrote its
regression testset and showed it red there, fixed, re-ran its targeted
testsets and the source sweeps, re-walked the call sites, and committed on
its branch; the integrator merged the branches onto `crab-noise-audit`. Unit
reports and logs: `result/audit_crab_noise_2026_10_16/fixes/` (git-ignored
scratch; the numbers are quoted here).

### Unit E: the artifact's receipts, vocabularies and the partial slot (S4-1 / S4-2 / S4-3 / S4-10, S4-5 / S4-8 / S4-9, S5-7, batch 1's registration point, decision 1, U9-5)

Branch `fix-artifact-receipts`, commit c2c3228. Reproduced on ac3fbb2: no
receipt carried any artifact option under `TrackingTask`, the strong-strong
output receipt carried the request, the observers' declared `:observer_output`
receipt was never recorded, `tracking_task_option_schema()` lacked `artifact`
and `loss_report`; four hand copies of the slot-kind vocabulary; the
non-HDF5 append surfaced HDF5's message; a refused writer stayed registered.
Landed: the artifact records its own `:run_artifact_output` receipt once per
`execute!` after its last refusal (task kind, path, `append` beside
`continued`, `capacity`, `record_turn_modulation` beside `recording`,
`execution`), true under both task kinds because the artifact is one object
two kinds carry; each kind records its output receipt after the prepare
(`:tracking_output`, new: artifact, channels, `loss_report`;
`:strong_strong_output`, moved after the prepare); `tracking_task_option_schema`
gains `artifact` and `loss_report`; the snapshot, BPM and moment receipts
carry the fields their metadata names; the option-to-receipt pairing is
derived (`_output_receipt_gaps`, `src/contracts/Contracts.jl`) and checked by
the effectiveness contract under both kinds. Vocabularies: `_rule_kind`
declared on the rule TYPES so `_turn_rule_kinds()` derives the set from the
`AbstractTurnRule` tree, the reader warning by name on a kind outside it; one
table `_RA_GROUPS` from which `_RA_KINDS` and the named kinds derive; the
`:turn_modulation` receipt pinned at all three levels. Decision 1: each slot
group carries a cursor `elements_valid_through` (0 before the first element
group, advanced after each complete element, series dataset included);
readers read a partial slot as far as the cursor with one warning and never
error; `append=true` onto such a file is refused by name; documented in the
record design note. `HDF5.ishdf5` probed before an append open; the
in-process registry written after the prepare body's last refusal (the lock
stays first); the recorder's buffers `sizehint!`ed. Testset "Run artifact
receipts and slots: resolved output receipts for both task kinds, derived
vocabularies, the non-HDF5 append refusal, a partial slot reported by the
reader": red on ac3fbb2 10 pass, 6 fail, 7 error of 23; green after 204 of
204. Targeted: the receipt, effectiveness and artifact testsets green (among
them the kernel-boundary effectiveness 57 on CUDA, the element-parameter and
solver-option effectiveness contracts), `validate_configuration_metadata()`
true, `validate(PublicConfigurationEffectivenessContract())` passed with no
output-receipt gap, snapshot unchanged, sweeps green. Open: the BPM's eleven
`:bpm_reading` options still have no receipt (row 28's schema-driven sweep);
the MPI lane's non-root branch was read, not run (the gate's full lane covers
it).

### Unit G: elements, scripts and the harness (U1-2, U2-4, S2-1, S4-7, U7-3 / U7-4, U6-6, S3-3)

Branch `fix-elements-validation`, commit e9a3c3d. Reproduced on ac3fbb2: the
crab cavity's `realize` and `update` allocated 2176 and 1360 B at 33 or more
harmonics (the `(dphi..., d...)` splat past `max_tuple_splat = 32`, through
`_apply_iterate`); the shared drift's `z` update off the closed formula by
94.8 ulp on the probe particle and by 6469 ulp at worst over 101 particles
and three lengths; the backend-consistency script with no modulated cavity;
the registry snapshot without the catalogue; the `CRAB-NOISE` line's 34
fields all echoes of the parsed variables and no device field; the MPI
harness testset's hand-copied seed; the ownership tripwire deriving wrappers
by the field name `inner`. Landed: `_slot_concat` replaces the splat (0 B at
N = 16 to 64); the drift forms its `z` excess cancellation-free, `z - ((1 +
pz)/ps0 - 1) L` with `px^2 + py^2` fused through `fma` so CPU and CUDA round
alike (`_pt2_fused`): worst 0.50 ulp over the sweep, the thick RF cavity's
`z` 94.8 to 1.20 ulp with `pz` unchanged, pinned at 1 ulp against BigFloat
for the drift and 4 ulp for the thick cavity; the `Patch` element, which
carried its own copy of the drift formula, now forms both excesses the same
way (bitwise equal to `DriftSpec`, the reference particle exactly `z = 0`);
two pins that moved were re-walked and re-derived: the surveyed-cavity
CPU/CUDA pin had held "bit for bit" for `z` only while the kick's `pz`
already differed by 1 ulp through `sin` (now: first pass bitwise, 64 turns
within 16 ulp) and the `Patch` testset. The backend-consistency script gains
a modulated crab and a modulated RF cavity (white and table rules): CPU/CPU
0, CPU/GPU 6.3e-16. `example_catalog()` feeds `build_registry`, the snapshot
and `summarize_registry().examples` (five entries, regenerated snapshot
committed). The harness reads `kbb_scale`, `radiation`, `chrom`,
`table_file` and `seed` back from the receipts and the artifact, says so in
its header, prints `device=<n|NA>`, and refuses `OCTOPUS_CUDA_DEVICE` without
the GPU switch; the validation's parser and `verify_receipt` follow; the
2-turn CPU line differs from before only by the device field. Each harness
exposes `HARNESS_DEFAULT_SEED`, the MPI testset derives it (the pin's
message names the seed). The ownership tripwire derives the wrapper set from
the `AbstractTrackOp` subtypes that forward `track_particle`, pinned both
ways. Testset "Elements and scripts follow-ups: the crab cavity's realize and
update at forty harmonics, the drift's z update, the catalogue in the
snapshot, the harness's readbacks and device, the derived default seed, the
ownership tripwire by forwarding": red on ac3fbb2 33 pass, 40 fail of 73;
green after 73 of 73 (72 in the suite). Targeted: twenty symplectic, drift,
snapshot, registry and harness testsets green, the Patch, curved, lattice-cell
and PTC sets green after the Patch change, `SymplecticityContract` passed,
the harness on CPU and CUDA, sweeps green, a fast lane on the unit's tree
green (327 rows). Open: the curved drift, `_lattice_bend` and the solenoid
keep `z + L - ...` forms of the same cancellation class (a new row); which
cross-backend quantities are bitwise and which are 1-ulp class is nowhere
stated (a note for the owner); the MPI harness children ran only in the
gate's full lane.

### Unit H: one precision rule for every kind (decision 3)

Branch `fix-precision-all`, commit b754439, 28 files. Reproduced on ac3fbb2
with batch 1's probe: a Float32 beam through the Float64 registry example of
each kind ran narrowed on the CPU for 28 kinds and was refused for 3; on CUDA
18 ran narrowed, 10 failed at device compile, 3 were refused. Landed, derived
rather than declared: every runtime struct with numeric parameters carries one
`T <: Number` type parameter and `_required_beam_eltype` reads it
(wrappers and `CompositeLine` answer with what they hold); every kind has a
typed form `Spec{T}(...)` and `Spec(; numeric_type = T, ...)`, storing
`numeric_type = T`, which `numeric_type(spec)` returns and every compile
constructor builds in, while the untyped forms store no type so duals and
`BigFloat` still widen; the one key is declared once in `_PLACEMENT_PARAMS`
(alternatives Float64 and Float32, so the effectiveness contract checks it:
500 to 530 checked); the refusal names the kind's typed forms from the
registry; wraps are built in their subject's type; the Lorentz boost and the
aperture follow the floor. The typed Float32 strong beams did not compile on
CUDA until the kick's and virtual drifts' literals were formed in the working
type and the soft-Gaussian call sites passed the solver's working type
explicitly, which restored the pinned Float32 CPU/CUDA bit-identity exactly to
the unfixed tree's numbers. Testset "One precision rule: every element kind
declares its beam type, a mismatched beam is refused by name on both
backends, and every kind has a typed form": red on ac3fbb2 48 pass, 95 fail,
12 error; green after 627 of 627, CUDA active. After, over the 31 kinds with
a Float32 beam: the Float64 example refused by name on CPU and CUDA for 30
kinds (the marker, with no numeric parameter, runs), the Float32 typed form
runs on both backends for 31 of 31, no `InvalidIRError` anywhere. No test
outside the two precision testsets built a Float32 beam through a line; the
Float32 cell envelope is printed and pinned at ten times the measurement
(against Float64 5.0e-6 transverse and 1.35e-4 in `z`, the drift's `1/ps - 1`
cancellation; CPU against CUDA 2.6e-6 and 9.2e-5). Targeted: 31 kinds'
`validate_element_metadata()` and both `element_help` forms, snapshot
unchanged, the effectiveness contract (530 checked, none ignored), the
backend-consistency script 6 of 6, 29 CPU and 25 CUDA testsets green, sweeps
green, a fast lane on the unit's tree green (327 rows). Open: the Float32
envelope is a property of Float32 tracking the user should know
(`docs/current_runtime.md` says so); an untyped marker in a Float32 line
keeps Float64 frame changes (it has no numeric parameter).

### Unit F: tasks, walks and warnings (U3-6, U8-16 with batch 1's double warning, S3-1, U1-7 / U1-8, U9-4, batch 1's registry follow-ups with row 40)

Branch `fix-tasks-walks`, commit e984040. Reproduced on ac3fbb2: the
`:turn_modulation` and `:tracking_turn_timing` receipts recorded before the
three refusals; "on different elements" for one spec placed twice and two
warnings for one cause; the hidden-aperture warning silent for an aperture
inside a bare `BeamLine` in a task tuple; a preset's name accepted on a custom
spectrum and the table's offsets mutable after construction; the eleven
once-per-`execute!` walks at 185-206 kB each on the eight-type line (1.25 MB
per fast-path call, 1.82 MB per general-path call); the registry's 132.6 B
per automatic assignment and `typemax`'s exhaustion; a negative id an
`InexactError`. Landed: `_record_tracking_receipts!` records both receipts
after the refusals on both task kinds (a refused run leaves none); the
duplicate-stream warning counts placements and the resolved-line check skips
the pairs the constructor reported (the spectral-beside-offline-twin case
warns exactly once); the hidden-aperture walk descends bare `BeamLine`s and
the kill is attributed; preset labels on custom functors refused by name and
the table holds a private copy of its offsets; the walks unrolled with
literal indices: each walk 0-32 B, the fast path 1,245,392 to 97,792 B and
the general path 1,820,560 to 103,632 B per `execute!`, the strong-strong
line walks 38,736 to 12,064 (its result tuple) and 26,704 to 32 B, pinned
with stated margins; the registry keeps a fixed 64 kB ring for automatic ids
plus one entry per distinct explicit id (0 B per automatic assignment), the
automatic sequence skips explicit claims instead of jumping past them so
`typemax(UInt64)` stays claimable, a negative or non-integer id is refused by
name (`LumpedRadSpec` no longer converts before the registry). Consequences
owned: batch 1's unit B pin now expects silence at `execute!` for a spec
placed twice, unit C's pins follow the skip semantics, and the suite's
fresh-id convention became `Octopus._unheld_rng_id(...)` at its four sites
because the counter no longer jumping past claims made two testsets' ids
collide (a lesson in `docs/experiences.md`). Testset "Tasks and turn
modulation follow-ups: receipts after the refusals, one warning per cause,
apertures inside a bare line, frozen tables and preset names,
once-per-execute! walks, the stream registry's bounds": red on ac3fbb2 42
pass, 46 fail, 6 error of 94; green after 108 of 108, CUDA active. Targeted:
the turn-modulation family, the stream testsets, the aperture testsets,
"Architecture integrity" and the fused CUDA moment row green, sweeps green.
Open: `_strong_strong_physics_line` still boxes its 42 result elements (12 kB
per call); beyond 65536 automatic assignments an explicit claim of an old
automatic id warns without the holder's class (the message says so).

## 3 Verification

**Per unit, before integration** (section 2): each regression testset red on
ac3fbb2 for the defects' reasons and green after; the units' targeted
testsets, the source sweeps, the validators and the snapshot (regenerated by
unit G for the catalogue); unit G's and H's backend-consistency script runs
with the GPU contract; units G and H each ran a fast lane on their own tree
(327 rows, green).

**Integration** (branch `crab-noise-audit`, merges of c2c3228, e9a3c3d,
b754439 and e984040 over ac3fbb2; two conflicts resolved additively in the
last merge: the `LumpedRadSpec` constructor, where unit F's integer check
precedes unit H's numeric-type stamp, and the fast path of
`_execute_tracking_task!`, where unit E's output receipt precedes unit F's
receipts-after-the-refusals helper). Three interactions appeared only on the
merged tree and were fixed in integration commits: unit H's
`_numeric_type_parameter` searched `T.parameters` at run time, which unit
F's once-per-execute! walk pin measured at 5 kB per call (now `@generated`,
a constant per concrete type); unit E's effectiveness fixture built its BPM
with a bare `next_rng_id!() + 1_000_000`, which unit C's claim-site tripwire
refuses and unit F's skipping counter made unsafe (now `_unheld_rng_id`
above the counter); unit H's structural pin enumerated the suite's own
fixture ops from unit G in the one suite process (now scoped to
package-defined types; a lesson in `docs/experiences.md`). Two stale
comments followed the moved receipts. Smokes on the merged tree: E+G (the
2-turn harness ran), E+G+H, E+F+G+H (twelve testsets, then the five
affected ones after the fixes), all green except the stage runner's known
artefact (suite-level helpers outside a cut block); sweeps green
(`sweeps_audit_fixbatch3/5.log`; `fixbatch4` red on a comment of mine that
detached a docstring, moved); fast lanes `fastE` (red on the fixture
enumeration above) and `fastF` (green, 330 rows, 16 heavyweight sections
skipped loudly).

**Gate** (the matrix's classes for this batch: public configuration, element
specs and compile, CUDA-reachable code, contracts and refusals, examples and
validation scripts): the full two-arm gate on the final source and test
tree, arms one after the other in one worktree, 4 threads, CUDA active
(`result/gates/turnmod/full_gate_native_audit_gateC.log`,
`full_gate_avx2_audit_gateC.log`): native arm exit 0, 345 testset summary
rows, 151,986 passing tests, no failure, no error, no lane-skip banner, 39
CUDA-named rows, 25 registry warnings from literal stream ids claimed across
unrelated testsets (the policy, legitimate), 23:59-00:55 EDT; AVX2 arm
(`OPENBLAS_CORETYPE=Haswell julia -C haswell`): exit 0 as well, the same 345 rows, 151,986 passing tests, no failure, no error, no skip banner, 39 CUDA-named rows, the same 25 registry warnings, 00:55-01:51 EDT (2026-10-17). The fast
lane ran again on the final tree after this record's markdown completion:
green (`fast_lane_audit_fastG.log`). Not verified: CI (CPU only) runs on the push.

## 4 Ledger

- `docs/todo.md`: twenty-two rows retired to
  [`todo_ledger_archive.md`](todo_ledger_archive.md) under "Rows retired by
  the crab-cavity noise audit fix batch 2 — closed 2026-10-16", each with its
  closing measurements: the three owner decisions (the partial slot, the
  frozen record, the Float32 kinds), the audit's seventeen small rows (U1-2;
  U1-7 / U1-8; U2-4; U3-6; S2-1; S3-1; S3-3; S4-1 / S4-2 / S4-3 / S4-10;
  S4-5 / S4-8 / S4-9; S4-7; U7-3 / U7-4; S5-7; U8-16; U9-4 / U9-5; U6-6; the
  restored U5-2 of the stage 3-4 audit; U8-7), the first batch's three
  follow-ups (the refused-in-prepare registration, the double warning, the
  registry's memory and `typemax`) and the pre-existing row 40 (negative
  ids). Four rows opened from what the units found and left: the curved
  drift, bend and solenoid keeping the cancelling form; which cross-backend
  quantities are bitwise (owner note); the strong-strong physics-line result
  boxing; the untyped marker in a Float32 line (information). The pointer
  row records the batch. After this batch the audit's open queue is the
  pointer row and these four.
- `docs/README.md`: this record indexed beside the audit's and batch 1's.
- `docs/experiences.md`: unit F's lesson (the fresh-id convention under the
  skipping counter).
- The batch 1 record and the frozen stage 0 record carry their addenda; their
  bodies are unchanged.

---

**Added after the push (2026-10-17).** Pushed as c061088 (origin/main, on the
owner's word); CI run 461 (GitHub Actions, the CPU full lane) completed green
at 13:09 EDT. The owner then opened batch 3 for the four follow-up rows; its
record is
[`crab_cavity_noise_audit_fixes_batch3_2026_10_17.md`](crab_cavity_noise_audit_fixes_batch3_2026_10_17.md).
