# Crab-cavity noise neighbour audit: the owner-decided fix batch (2026-10-16)

**Status:** landed 2026-10-16 on `crab-noise-audit` (four unit commits, three merges, the seam repair 4a982b8 and this record's commit), gated the same day in both CPU arms with CUDA active, the arms one after the other; push pending the owner's word; CI on the push.

**Scope.** The open items the owner picked from the 2026-10-16 neighbour
audit ([`audit_crab_cavity_noise_neighbours_2026_10_16.md`](audit_crab_cavity_noise_neighbours_2026_10_16.md),
section 8) after it was pushed as 8ace18b: the artifact's cross-process
exclusion (S5-2), seed provenance (U3-2, S5-4), the unwarned correlated noise
(U1-6 / S3-2 / U3-3 / U7-2 / S5-3 and S1-1 / S1-2 / S1-5 / S1-6 / S1-7, with
the pre-existing rows 34 and 38), and the Float32 policy of the modulated
cavities and the radiation element (U2-1 / S2-2 / S2-3, S1-9). Owner
instruction: "following the comprehensive audit rules to fix these terms,
then retire them from the todo list". Method: the protocol's fix phase
(reproduce first; a regression test shown red on the unfixed tree; a
neighbour re-walk per fix), run as four parallel units in their own
worktrees, integrated on `crab-noise-audit`, gated as one batch.

## 1 Owner decisions (2026-10-16, this session)

1. **Exclusion (S5-2):** a sidecar lock file `<path>.lock` (host, pid, time,
   task kind), created exclusively, taken for fresh and append opens,
   released at finalize and on the crash path; a second writer is refused by
   name; no automatic stale-lock takeover (NFS, other hosts). Readers never
   take the lock and stay allowed: measured before the decision, a second
   process reading an artifact while the writer held it open through a
   30-second window saw the last flushed state (2880 of 3000 series rows, the
   ledger's `current_turn` at 2881) and the public reader returned normally;
   nine reads in two scenarios, no error, the writer undisturbed
   (`result/audit_crab_noise_2026_10_16/auditor/probe_rw_reader.log`,
   `probe_rw_reader2.log`). That works because HDF5's own file lock is not
   enforced across processes on this NFSv3 mount, which is also why two
   writers were not excluded; it is best-effort (no SWMR), and the cursors
   say what to trust. The readers become lock-aware (one `@info` naming the
   writer, one retry on an HDF5 open error).
2. **Seed change between windows (U3-2):** warn at `execute!` by name (both
   seeds, that the table was synthesised at compile, how to regenerate); the
   resolved spectral table stays frozen. Re-synthesis and refusal were
   offered and declined.
3. **Precision (U2-1 / S2-2 / S2-3 / S1-9):** Float64 floor for the
   cavities (a Float32 frequency promotes like every other element's
   parameters); a beam whose element type differs from a cavity's or the
   radiation element's parameter type is refused at compile by name (CUDA
   failed to compile, CPU narrowed silently). Converting to the beam's
   precision was offered and declined.
4. **Stream ids (S1-1 / S1-2 / S1-5 / S1-6 / S1-7, rows 34 and 38):** one
   `rng_id` policy for every consumer: 0 assigns a fresh stream, ids are
   `UInt64`, the registry remembers the ids it auto-assigned; an explicit
   claim of an auto-assigned id and one explicit id shared across classes
   WARN at construction (refusal offered and declined); explicit reuse of
   one id by one class stays silent (the reproducibility handle).

## 2 Units and what landed

Each unit reproduced its defect on the unfixed tree 8ace18b first, wrote its
regression testset and showed it red there, fixed, re-ran the targeted
testsets and the source sweeps, re-walked the call sites, and committed on
its branch; the integrator merged the branches onto `crab-noise-audit`. Unit
reports and logs: `result/audit_crab_noise_2026_10_16/fixes/` (git-ignored
scratch; the numbers are quoted here).

### Unit A: the artifact's exclusion and seed provenance (S5-2, S5-4)

Branch `fix-artifact-lock`, commit 02312b8. Reproduced: two cross-process
writers on one path both "SUCCEEDED", the file afterwards unreadable, the
race lost 400 rows; no attribute or receipt anywhere named the seed.
Landed in `src/tasks/RunArtifact.jl`: the sidecar lock (`_ra_take_lock!` with
`O_CREAT | O_EXCL`, one line `host= pid= since= task=`, taken before `h5open`
for fresh and append opens, released after the close on every success and
crash path; the refusal names the lock, the held line and the remedy; a lock
that vanished or was retaken while held warns and is left alone); the
lock-aware reader `_ra_open` (one `@info` per writer and process naming the
writer and the cursors, one retry of a failed open, then a by-name error),
used by the artifact readers and the four `MomentOutput` reads; the ledger's
six columns as ONE table `_RA_LEDGER_COLUMNS` (creation, row append,
continue-check, reader) with `rng_seed::UInt64` and `rng_method::String`
appended per `execute!`; `append=true` onto a ledger lacking a column refused
by name (the file predates the columns); old files still read, the missing
columns as `nothing`. Both task kinds pass their kind into the lock line.
Testset "Run artifact exclusion and seed provenance: the sidecar lock,
lock-aware readers, the ledger's rng columns": a child process holds the
path, the second writer is refused with either `append`, the reader reads
under the lock with the `@info`, the lock is gone after finalize, a prepare
refusal, a failed open and both tasks' crash paths, two windows with a seed
and method change read back `[21, 22]` and `["philox", "splitmix"]`, the
pre-column file is refused and left as found. Red on 8ace18b: 16 pass, 11
fail, 13 error of 40; green after: 56 of 56. Targeted: every artifact
testset green (luminosity channel 83, realised record 268, provenance 127,
audit testset 36, loss accounting 19, crashed execute! 11, BPM artifact 5,
second live writer 2, moment reader 2); sweeps green after a first red
(`Core.Box` from a comprehension assigned on two branches, replaced by a
loop); `validate_configuration_metadata()` true; snapshot unchanged. Found
and left (pre-existing): an artifact refused inside the prepare body still
registers in the in-process path registry.

### Unit B: seed drift and equal digests at `execute!` (U3-2; U1-6 / S3-2 / U3-3 / U7-2 / S5-3)

Branch `fix-seed-digest`, commit 74696a6. Reproduced on 8ace18b: no warning
for a seed change between windows (the table's series unchanged, the
canonical name the only evidence) and none for a `SpectralNoise` beside its
offline twin (equal digests, correlation 1.0). Landed: `TurnTable` gains
`resolved_seed` (`nothing` for every constructor-built table, set only by
`_resolve_turn_rule`; type-stable, host-only, the turn loop untouched);
`_warn_resolved_seed_drift` at every `execute!` of both task kinds after the
window check (one `@warn` naming each table's element, slot, synthesis seed
and digest, the global seed, that the series are unchanged, and how to
re-synthesise); `_warn_resolved_duplicate_tables` at the compile-cache fill
(for the strong-strong task at the fill that leaves both caches current)
over `_resolved_table_slots` of every line: a digest on two or more distinct
modulated elements warns once per digest with both sites named, one table on
two slots of one element stays silent (D4), one spec placed twice is worded
as a placement; the generic walk `_each_modulated` is registered in the
suite's wrapper-walk tripwire. The harness (U7-2) synthesises its spectral
tables over `max(turns, 256)` turns: at the 2-turn smoke size the unfixed
run had 16 few-bins warnings and three of four phase and strength slots
with identical digests, the fixed run has zero warnings and eight distinct
digests; the 2-turn `CRAB-NOISE` line changes in its realised fields only
(`eps_x_first` 1.1289026e-8 to 1.1288905e-8, `lumi_mean` 1.0798483e30 to
1.0798527e30, the `rms_*` fields from exactly sigma to partial-period
values), runs of 256 turns or more are bitwise unchanged. Testset "Turn
modulation at execute!: the global-seed drift warning for resolved spectral
tables and the equal-digest check over the resolved line": red on 8ace18b
24 pass, 8 fail (the missing warnings and field); green after 44 of 44. The
S5-1 pin (audit testset (f)) and the producer testset's seed-change window
now expect the warning. Targeted: 14 turn-modulation testsets green (2220
passes), sweeps green. Open: a pair the constructor already names (one spec
placed twice, two offline copies) is named again at compile, two warnings
for one cause, stated in both docstrings.

### Unit D: the precision policy (U2-1 / S2-2 / S2-3, S1-9)

Branch `fix-precision`, commit 5e847b9. Reproduced on 8ace18b:
`ThinCrabCavitySpec{2}(1.0f8; strengthX=(1.0, 0.5))` stored `(1.0f0, 0.5f0)`
and compiled to a Float32 element; a Float32 beam through a Float64 RF
cavity or `LumpedRadSpec` ran on the CPU with the coordinates narrowed on
store and failed on CUDA with an `InvalidIRError`; a Float32 crab cavity
disagreed CPU/CUDA by 6 to 68 Float32 ulp with no pin. The sibling rule, read
from the constructors: an explicit `Spec{T}` stores `T`, the untyped form
floors at Float64 (`_linear_map_eltype`). Landed: `ThinCrabCavitySpec{N}`
promotes `frequency`, `strengthX`, `strengthY` and `phase` over the Float64
floor and `ThinCrabCavitySpec{N,T}` is the deliberately typed form; a trait
`_required_beam_eltype` (`src/track/Track.jl`, `nothing` for a plain element)
declared by the two cavities and the radiation element, read once by
`_check_beam_eltype` at `_runtime_entries` (every call with a representation,
cached entries included) and per strong-strong line, refusing by name with
the element kind, both types and the kind's own remedy; the RF cavity's
unreachable "Float64 table on a Float32 cavity" direction documented; the
`?@element_spec` checklist gained the numeric-type item. Measured for the
record (every registry example, one turn, Float32 beam): CPU 31 of 31 kinds
run with the coordinates narrowed on store; CUDA 19 run and 12 fail at device
compile (drift, quadrupole, sextupole, octupole, multipole, sbend, `:line`,
both strong beams, the accelerating cavity, the RF cavity, radiation), so
the by-name refusal for the three kinds is a special case among the kinds;
recorded in `docs/current_runtime.md`, and an owner item below. Testset
"Precision policy of the modulated cavities and the radiation element: the
Float64 floor and the by-name refusal of a mismatched beam": red on 8ace18b 3
pass, 34 fail, 2 error; green after 100 of 100; the Float64 digests of the
three kinds bitwise equal to the unfixed tree's (crab `0x492c1c30b5967ac6`, RF
`0xbbbff952530665cc`, radiation `0x09802b6943e3e9c6`, printed, not pinned);
the typed Float32 crab cavity agrees CPU/CUDA within 2.0 Float32 ulp
(pinned at 1024). Targeted: 27 named testsets (20 green, 7 runner artefacts
that passed in the fast lane), `validation/tracking_backend_consistency.jl`
with the GPU contract required 6 of 6, `validate_element_metadata()`, both
`element_help` forms, snapshot unchanged, sweeps green, a fast lane on the
unit's tree green (323 rows). Open, for the owner: whether to generalise the
refusal to the other nine CUDA-failing kinds (the Lorentz boost still types
itself from its angle); the silent CPU narrowing of the other kinds stands.

### Unit C: one `rng_id` policy (S1-1 / S1-2 / S1-5 / S1-6 / S1-7; rows 34 and 38)

Branch `fix-rng-policy`, commit 80cf952. Reproduced on 8ace18b with the S1
probes: `BPMObserver(rng_id=0)` drew on stream 0; a raw `:lumped_radiation`
spec without an id drew on stream 0; a Beam's auto id 7 and
`LumpedRadSpec(rng_id=7)` shared their cells silently; `BPMObserver(rng_id =
typemax(UInt64))` was an `InexactError`. Landed in `src/math/counter_rng.jl`:
beside the atomic high-water counter a holder table `_RNG_ID_HOLDERS` under a
lock; `next_rng_id!(; consumer)` (a CAS loop that throws by name when
exhausted) records an auto holder; `claim_rng_id!(id; consumer)` raises the
counter and warns once per (id, class) when the id is held by an
auto-assigned consumer or by an explicit consumer of another class,
same-class repeats silent (the reproducibility handle), 0 refused as "not a
stream"; `reset_rng_id_counter!` forgets the holders; a new `Octopus.__init__`
empties the holders the `@element_spec` examples claim at precompile. The
four claim sites name their class (`:beam`, `:lumped_radiation`,
`:turn_rule`, `:bpm_observer`; a tripwire greps every claim call for
`consumer=` and pins the derived class set). `BPMObserver`: field `UInt64`,
keyword `rng_id::Integer = 0`, 0 a fresh stream at construction, the option
metadata `(UInt64, UInt64(0))`. `:lumped_radiation` reaching `compile_runtime`
with 0 is refused by name rather than assigned there (a knob recompile would
move the stream mid-run). Testset "One rng_id policy: zero assigns a fresh
stream everywhere, ids are UInt64, the registry warns on an explicit claim of
an auto-assigned id and on cross-class sharing": red on 8ace18b 12 pass, 20
fail, 2 error; green after 34 of 34. Targeted: eleven stream-related
testsets green (among them the BPM noise keys, 2015 passes), the audit
testset, the turn-modulation family, both validators, snapshot unchanged,
sweeps green after a first `Core.Box` in `next_rng_id!` (refactored into
`_issue_rng_id!`); a no-abort full lane on the unit's tree green, 338 rows,
with 17 registry warnings from literal ids claimed across unrelated testsets
after they had been auto-assigned (legitimate under the policy; four strict
silence pins moved to fresh ids above the counter). A lesson in
`docs/experiences.md`. Open: the holder table grows with the process; an
explicit `typemax(UInt64)` exhausts the automatic sequence by design; row 40
(negative ids) untouched.

## 3 Verification

**Per unit, before integration** (section 2): each regression testset red on
8ace18b for the defect's reason and green after; the unit's targeted
testsets, the source sweeps, the validators and the snapshot; unit D's
backend-consistency script with the GPU contract; units C and D each ran a
fast lane on their own tree (338 and 323 rows, green).

**Integration** (branch `crab-noise-audit`, merges ca5127d, 560fb74, 8cb0074
over 02312b8, then 4a982b8): three merges needed additive conflict
resolution (the compile-cache fill in `Tasks.jl`, where unit B's digest
check precedes unit D's beam-type return; the strong-strong preflight, where
unit D's refusal precedes unit B's drift warning; the suite's wrapper-walk
list; the `LumpedRadSpec` docstring; two adjacent new testsets). The
resolution of the adjacent testsets dropped unit B's closing `end`, which the
stage runner reported as a `ParseError` on the merged tree and 4a982b8
repaired with no test content changed. Smokes on the merged tree: units A+B
(5 testsets), A+B+D (7), A+B+C+D (12, including "Architecture integrity") all
green after the repair; sweeps green (`sweeps_audit_fixbatch1/2.log`); fast
lane green (`fast_lane_audit_fastC.log`, 326 rows, 16 heavyweight sections
skipped loudly).

**Gate** (the matrix's classes for this batch: public configuration,
CUDA-reachable code, contracts and refusals, element compile): the full
two-arm gate on the final source and test tree, arms one after the other in
one worktree, 4 threads, CUDA active
(`result/gates/turnmod/full_gate_native_audit_gateB.log`,
`full_gate_avx2_audit_gateB.log`): native arm exit 0, 341 testset summary rows,
150,982 passing tests, no failure, no error, no lane-skip banner, 39
CUDA-named rows, 17 registry warnings from literal stream ids claimed across
unrelated testsets (unit C's policy, legitimate), 15:48-16:45 EDT; AVX2 arm
(`OPENBLAS_CORETYPE=Haswell julia -C haswell`): exit 0 as well, the same 341 rows, 150,982 passing tests, no failure, no error, no skip banner, 39 CUDA-named rows, the same 17 registry warnings, 16:45-17:44 EDT. The fast
lane ran again on the final tree after this record's markdown completion:
green (`fast_lane_audit_fastD.log`). Not verified: CI (CPU only) runs on the push.

## 4 Ledger

- `docs/todo.md`: nine rows retired to
  [`todo_ledger_archive.md`](todo_ledger_archive.md) under "Rows retired by
  the crab-cavity noise audit fix batch — closed 2026-10-16", each with its
  closing measurements: the artifact's exclusion (S5-2) and seed provenance
  (S5-4); the resolved spectral table and the seed change (U3-2); the
  execute!-time equal-digest check (U1-6 / S3-2 / U3-3 / U7-2 / S5-3); one
  `rng_id` policy (S1-1 / S1-2 / S1-5 / S1-6 / S1-7) with the pre-existing
  rows 34 (explicit id after a fresh one) and 38 (BPM and radiation sharing
  an id); the crab cavity's numeric type (U2-1 / S2-2 / S2-3); Float32 beams
  through radiating elements (S1-9). Four rows opened from what the units
  found and left: the other element kinds under a Float32 beam (owner), the
  refused-in-prepare artifact's registration, the double warning for one
  cause, the stream-id registry's memory and `typemax`. The pointer row
  records the batch.
- `docs/README.md`: this record indexed beside the audit's.
- `docs/experiences.md`: unit C's lesson (a process-wide registry makes a
  strict silence pin order-dependent) and the audit's lesson on heterogeneous
  tuples.
- The audit record carries an addendum (pushed as 8ace18b, CI run 459 green,
  this batch opened); its body is unchanged.
