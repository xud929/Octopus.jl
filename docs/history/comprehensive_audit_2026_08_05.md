# Comprehensive Audit — 2026-08-05 (full re-read)

**Status: COMPLETE.** Phase 16 halt reached: final full suite at the closing commit — **137 top-level testsets, zero failures, CUDA half active**, all five new audit testsets green (solenoid 9/9, Philox KAT 4/4, wrappers/streams/apertures 5/5, append protocol 8/8, CUDA pz/:node 11/11). One driving
session under [`docs/comprehensive_audit.md`](../comprehensive_audit.md).

## 1a. Executive summary

Full 50,330-line re-read at the owner's direction, one day after the
2026-08-03/04 audit closed. Every line of `src/`, `test/`, `examples/`,
`validation/`, and `ext/` was read — 21 briefed sub-agent units plus
auditor-direct reads, provenance ledgered per unit — and **20 findings were
confirmed, fixed, negative-controlled, and committed (F1–F20)**, none
Critical, four Major:

- **F2**: the h≠0 sweep asserted 1e-12 on its own documented 1.1e-9 floor,
  failing deterministically and **aborting every full-suite run since
  `baf0255`** — ~4,660 test lines (the CUDA half, examples, append
  testsets) had not executed in any full run, and the interim "full suite
  green" claims were false. The prior audit's first rule — correct checks,
  never executed — reproduced at HEAD within a day.
- **F11**: `interaction_grid=:node` silently degraded to `:slice_pair` on
  every non-indexed CUDA wavefront sub-route (1.2e-2 coordinate shift), and
  `pic_timing_detail=true` alone rerouted execution — a diagnostic changing
  physics by 8.9e-3. Now refused statically and at runtime.
- **F16**: the RF cavity's slip factor is `α_c` alone — the `−1/γ₀²`
  velocity-slip term structurally cannot enter a path-length-convention
  ring anywhere but the cavity's conversion, which omits it (1.84× ν_s
  error at 2.5 GeV proton, wrong transition side when `α_c < 1/γ₀²`). A
  Knowledge-Layer defect faithfully implemented; boundary documented, fix
  priced with Scope B's survey channel.
- **F17**: every straight solenoid was un-differentiable (complex-typed
  body), and `curved=false` tracked a silent non-gradient kick at 2.5e-3 on
  the solenoid while the LatticeMagnet kept the curvature its own warning
  said was ignored. Real-arithmetic transcription verified bit-identical;
  `curved=false` now equals `h=0` exactly.

The other sixteen: the append/restart protocol rebuilt against torn writes,
silent wipes, non-atomic rewrites, and ordering (F1/F3–F9); the gathered
CUDA routes' missing-pz crash (F10); two RNG-leaking contracts (F12);
context-dropping element wrappers, correlated radiation streams, and a
silent out-of-bounds loss-counter write (F13–F15); `:node`+`:quadratic`
silent ignore (F18); a Philox implementation nothing pinned, now KAT-gated
(F19); and CUDA test gates that reported green on CPU (F20).

Clean results are results: the Bassetti-Erskine/synchro-beam physics core,
the spectral twins, the GaussianPIC twins, the registry/metadata layer, the
knob engine, Philox, the constants, the examples layer, and the PTC
provenance chain all audited sound, most with independent-reference
measurements recorded in §7a/unit reports. A ~40-item priced open queue
(§7) and four new `todo.md` rows carry the honest remainder.

- Commit under audit: `6a3f39ab71a2f076e2c0964a8c014d8e4140b88b` (clean tree).
- Environment: Linux 5.14.0-570.21.1.el9_6, Julia 1.12.4, 128 cores, 503 GB RAM,
  NVIDIA RTX 4500 Ada (24 GB, driver 580.119.02, CUDA 13.0) — GPU checks run for
  real, not skipped.
- Prior audit: [`comprehensive_audit_2026_08_04.md`](comprehensive_audit_2026_08_04.md)
  (parts 1–9). This pass re-reads everything regardless of prior coverage, at the
  human owner's explicit direction; the prior ledger is used only to sharpen
  hypotheses, never to skip a line.

## 0. Declared scope

Line-by-line coverage of every Julia source line at the audited commit:

| tree | lines | treatment |
|---|---|---|
| `src/` | 32,915 | line-by-line, every file |
| `test/` | 8,608 | line-by-line (tests are claims; circularity and never-failing guards are in scope) |
| `examples/` | 712 | line-by-line + executed |
| `validation/` | 8,076 | line-by-line + executed where runtime permits (the two known >420 s scripts get a longer cap or an honest skip) |
| `ext/` | 19 | line-by-line |

Plus: all contracts run and checked that they prove what they claim (Phase 7);
full suite with `--threads=4` on CPU+CUDA (Phase 8); every example executed
(Phase 10); targeted independent derivation (Phase 5/12) of equations the prior
ledger does **not** record as independently derived, and spot re-derivation of a
sample it does; docs checked for consistency against source (Phase 6) — theory
notes are checked where implementing code cites them, not re-derived front to
back where already recorded as derived (each such reliance is noted in the
ledger).

**Not covered, and why:** the Bmad reference case for
`misalign_convention=:bmad` (blocked on an external tool; stays on `todo.md`);
`docs/history/` archives as such (records of past states, not claims about
current code — consulted, not audited); `Manifest.toml` / dependency internals.

## 0a. Method (binding for this pass)

- One driving session; sub-agents multiply reading bandwidth only. **A sub-agent
  claim is a lead, not a finding** (measured series survival ~60%); the auditor
  reproduces every lead before it enters Findings, and no sub-agent ever fixes.
- Behavioural fingerprint captured **before the first source modification**;
  every fix carries a negative control (stash-based or marker-injection per the
  recorded workflow — never `git checkout` over uncommitted state).
- Fix while the reproduction is live; ledger, `todo.md`, and fix land in the
  same commit.
- Corrections to this audit's own analysis are recorded beside the original
  claim, not over it.

## 0b. Reading units and assignment

Provenance: **auditor** = read directly in this session's driving context;
**agent** = briefed sub-agent line-by-line read (lead-generating only).
Status moves pending → reading → reported → **verified** (auditor has
disposed of every lead from that unit).

| unit | files (lines) | reader | status |
|---|---|---|---|
| U1 | `src/tasks/strongstrong/pic_cuda.jl` 1–3000 | agent | reported (3 leads; U1-1→F11 fixed, U1-2 open, U1-3 open) |
| U2 | `src/tasks/strongstrong/pic_cuda.jl` 3000–5966 | agent | reported (3 leads; U2-1→F10 fixed). Auditor provenance, honestly: the launch/extract/scatter/route regions (~250 lines) were auditor-read during the F10/F11 fixes; the 5490–5966 moment/kick kernel bodies remain agent-read, backed by U2's bit-reproduction checks and the auditor's measured CPU parity (7.2e-15..1.4e-14) |
| U3 | `src/contracts/Contracts.jl` (2,544) | agent | reported (10 leads; §7) |
| U4 | `src/tasks/strongstrong/interface.jl` (2,310) | agent (+auditor for the `luminosity_append` delta) | reported (4 leads, 2 observations; §7) |
| U5 | `src/tasks/strongstrong/pic_cpu.jl` (1,902) + `slicing.jl` (715) | agent | reported (8 leads; §7) |
| U6 | `src/tasks/BeamObservers.jl` (1,582) + `BPMObserver.jl` (324) + `Tasks.jl` (827) | agent (+auditor for the `append` delta) | reported (6 leads; §7) |
| U7 | `src/elements/strong_beam.jl` (1,547) + `src/track/strong_beam_track.jl` (495) + `src/tasks/strongstrong/gaussian.jl` (195) | agent | reported (5 leads; §7) |
| U8 | `src/tasks/strongstrong/gaussian_pic.jl` (869) + `gaussian_pic_cuda.jl` (1,232) — twin pair, parity brief | agent | reported (1 doc lead; clean) |
| U9 | `src/tasks/strongstrong/spectral.jl` (1,148) + `spectral_cuda.jl` (806) — twin pair, parity brief | agent | reported (clean; 4 minor/known items) |
| U10 | `src/elements/lattice_magnets.jl` (1,222) + `solenoid.jl` (436) + `linear6d.jl` (306) + `linear_maps.jl` (236) | agent | reported (11 leads; §7) |
| U11 | `src/elements/beam_line.jl` (587) + `aperture.jl` (583) + `thin_elements.jl` (346) + `radiation.jl` (313) + `misalignment.jl` (293) | agent | reported (12 leads; §7) |
| U12 | small elements + `src/track/` | agent | reported (5 leads incl. the RF slip-factor Major; longitudinal conversions verified to 3.9e-17; refuted inherited perf item 4 with numbers) |
| U13 | knowledge/registry/policies | agent | reported (6 leads; registry snapshot byte-fresh, all policy fields consumed) |
| U14 | knobs + Symbolics ext | agent | reported (7 leads; epochs verified on all 11 mutation paths, derivative verified on 9 shapes) |
| U15 | Beam/math/constants | agent | reported (7 leads; Philox bit-exact vs all 3 official KAT vectors, constants ≤0.47 ulp vs CODATA-2022, beam_statistics 4.8e-14 vs BigFloat) |
| U16 | `test/runtests.jl` 1–3800 | agent | reported (6 leads; 60 testsets audited, 10 strong-tests verified) |
| U17 | `test/runtests.jl` 3800–EOF | agent | reported (8 leads; 75 testsets audited, 10 strong-tests verified) |
| U18 | `test/examples/` + `examples/` | agent | reported (6 leads; all five scripts executed clean, pair-consistency verified bit-identical) |
| U19 | `validation/` coherent-modes cluster | agent | reported (10 leads incl. the stale theory-note table (HIGH) and the stale no-detached-mode claim; harmonic self-check binds, BB3D provenance reproduced) |
| U20 | `validation/` field cluster | agent | reported (8 leads, print-only/header-drift class; no bitrot, no circularity, all recorded numbers reproduce) |
| U21 | `validation/` remainder | agent | reported (13 leads incl. print-only gates and the lexicographic PTC-table pick; PTC provenance chain verified intact 55==55==55) |
| U22 | Post-audit delta: the four commits after `f55cf82` (diffs in `BeamObservers.jl`, `interface.jl`, `test/runtests.jl`, `examples/knob_control.jl`) | **auditor** | all four diffs read + flush/prepare context; produced F1, A-1, A-4, A-5 |
| U23 | Seam-class passes over the seam map (§3) | **auditor** | done — §3 records each seam class, its coverage, and the defects found on it |

## 1. Inherited open queue (from the prior audit, to disposition this pass)

1. Two `validation/` scripts that exceeded the prior 420 s cap — re-run with a
   longer cap.
2. `AbstractGPUExecutionPolicy` and `ElementParameterEffectivenessContract`
   lack docstrings (AGENTS.md requires them).
3. `beam_statistics` covariance loop computes all 36 entries of a symmetric
   matrix — unmeasured performance hypothesis.
4. `Patch._patch_map` rotation recompute — **REFUTED with numbers by U12**:
   11.059 vs 11.057 ns/particle hoisted (ratio 1.0002 over 1e7 iterations);
   LLVM hoists the pure computation. Closed, no fix warranted.
5. Metadata validator remainder: defaults-vs-constructor, declared-parameter-
   is-read, and `validate_configuration_metadata`'s hardcoded type enumeration.

## 2. Traceability matrix

Traceability held up better than any prior pass expected: every physics
feature audited traces Requirement → theory note → equation → implementation
→ test → (usually) validation. The verified chains, with the strongest link
named: lattice magnets (note §4-6 → `lattice_magnets.jl` → PTC contract with
committed reference, provenance chain 55==55==55 cases, MAD-X 5.03.06+flags
recorded — U10/U21); solenoid (note → map → RK4-independent testset at 1e-12
— U10/U17); Bassetti-Erskine (note → four branches → independent 96-pt and
200k-pt quadrature at ≤2.5e-14 — U7); slicing (note incl. published-table
erratum → seven rules → Furman Table 1 at ≤5e-7 — U7); spectral solver (note
→ both backends → continuum mode sum at ≤3.7e-15 — U9); GaussianPIC (note →
twins → quadrature/closed-form at documented tolerances — U8); Philox (spec →
implementation → now the Random123 KAT gate — U15/F19); longitudinal
conventions (note §2 → `longitudinal.jl` → 12 round trips at ≤3.9e-17 —
U12). **Broken links found and dispositioned:** the RF cavity chain's
note→code link carried the same defect at both ends (F16); the coherent-mode
note's §3 table no longer traces to what the code produces (U19-1, priced);
three contracts trace to no runner (U3-6/U21-13, priced); two validation
"references" are local reimplementations rather than the production objects
they claim to validate (U20-2/U20-4, priced).

## 3. Seam map

The seam classes, their participants, and who covered them this pass:

- **CPU↔CUDA twins** (`pic_cpu`↔`pic_cuda`, `gaussian_pic`↔`_cuda`,
  `spectral`↔`_cuda`, `strong_beam_track` host↔device): U8/U9 parity-briefed
  side-by-side reads plus the auditor's measured parity on newly-unlocked
  routes (7.2e-15..1.4e-14). Defects found ON this seam: F10 (5-field slice
  vs unconditional marshal), F11 (route-dependent :node), U2-2 (equal_area
  membership drift, open), U7-2 (luminosity turns-accumulation, open),
  U15-3 (cutoff clip-vs-resample, open). The seam-defect clustering the
  protocol predicts held.
- **Producer↔consumer protocols** (append/restart for .lum + MomentObserver;
  knob/spec epochs; loss-record lifecycle): auditor-direct (U22 + fix
  packages 2/5) and U4/U6/U14. Defects: F1/F3/F4/F5/F7/F9, U6-2 (open),
  U14-1 (open), U13-2 (open).
- **Declared schema ↔ runtime consumer**: U3/U13 enumerations plus
  effectiveness contracts. Defects: F18, U3-4/U3-5 (open), U11-3/U11-4
  (open), the unknown-kwarg acceptance family (U3-10/U13-1, open).
- **Multiple walkers over one structure** (line expansion/survey/aperture
  binding/observer collection): U11 enumerated every walker; the T3 pin
  holds for the bound pair; U11-1/U11-8 (nested-line survey and
  composite-aperture attribution, open) sit exactly on the unbound edge of
  that seam; F14's new collector deliberately walks deeper than the binder
  and says so.
- **Element wrappers ↔ context path** (a seam this audit ADDS to the map):
  the generic ctx fallback silently un-contexts any wrapper that forgets to
  forward — F13 fixed the three known wrappers; the class is worth a
  lowered-code-style sweep if new wrappers appear.

## 4. Findings

**F2 (Major, auditor-confirmed, FIXED).** `test/runtests.jl:2939-2942` (the
h≠0 sweep, `baf0255`): the solenoid content loop includes the empty content —
the pure curved solenoid at `nst=4` — under the 1e-12 tolerance, while the
testset's own comment and its dedicated pair (`< 1.0e-8` at nst=4, `< 1.0e-12`
at nst=16) document that configuration's implicit-midpoint floor at 1.1e-9.
Probe (`scratchpad/F2_solenoid_residual_probe.jl`): empty content
`1.1121181016539064e-9` — bit-identical across calls, equal to the suite
failure's value to 17 digits; all nine non-empty contents 8.7e-15..1.0e-14;
nst=16 `1.1e-16`. The failure is deterministic, so **every genuine full-suite
run since `baf0255` has failed and aborted at this testset** (top-level
testsets abort the script on their `TestSetException`), leaving everything
after `runtests.jl:2953` — the CUDA half, the examples testset, both append
testsets, ~4,660 lines — unexecuted; the "full suite green at --threads=4"
claims in `80cadbf`/`6a3f39a` cannot have come from a full run of this exact
tree. The prior audit's own first rule — checks that exist, are correct, and
are never executed — reproduced at HEAD within a day. Fix: the loop skips the
empty content (asserted by the dedicated pair); coverage lost: none. The
sweep's discriminating power is unchanged (instrument negative control at
`runtests.jl:2915` still reproduces the recorded 2.5e-3 defect).

**Fix package 2 (F1, F3–F9), verified:** all seven new behaviors PASS on the
fixed tree (`scratchpad/fixpkg_probe.jl`); negative control (both source
files stashed, tests kept): the five new behaviors FAIL pre-fix — the two
pre-fix PASSes are expected (mid-file corruption already threw an accidental
`ArgumentError` from `parse`; the wipe *result* is deliberately unchanged,
only made loud). Fingerprint after the package: **bit-identical** to the
baseline.

**F3 (Moderate, auditor-reproduced from U4-1/U6-1, fixed as docs+warning).**
`luminosity_append`/`MomentObserver(append=true)` promised "a second task
sharing the path and a process restart pick up where the file ends"; in fact
the resume point is the caller's `start_turn`, and a fresh task without it
executes from turn 0 — which, under the (correct) idempotence rule, silently
destroyed the entire file (reproduced: 3 rows destroyed; a `turns=0` no-op
wiped a 10-row file to header-only). Disposition: the idempotence rule and
the replace behavior are kept (auto-resume would silently mislabel physics
for a fresh-beam user — worse than loud replacement); both docstrings now
state the `start_turn` requirement, and a total replacement warns once,
naming the remedy. Chose Phase-15 conservatism over a semantics change.

**F4 (Moderate, from U4-2, fixed).** The append-mode .lum prepare rewrote the
file in place after `readlines` — a kill in the window lost the whole
history. Now writes to `path * ".prepare.tmp"` and `mv`s over.

**F5 (Low, from U4-4, fixed).** The .lum prepare (with its append-mode
refusals) ran *after* `prepare_observers!`, so a refused header left
companion moment tables already truncated. Hoisted above observer
preparation in `_execute_strong_strong_task!`.

**F6 (Minor, A-4, fixed).** `BeamObservers.jl:1092` threw
`BoundsError("<message>")` — the message string becomes the "accessed
object". Now a directed `error(...)` with both counts.

**F7 (Minor, A-5, fixed).** `MomentObserver(append=true)` onto a zero-byte
leftover file died with "unable to determine if ... is accessible in the
HDF5 format" (captured pre-fix). Now `filesize > 0` gates continuation, so
the leftover is replaced fresh, matching the .lum twin.

**F8 (Minor, U6-3, fixed).** The `BeamSwapAction(provider)` docstring sat
detached between the struct and an unrelated `observe!` method. Moved onto
the struct.

**F9 (Low, U6-6, fixed).** The binary `BeamMomentObserver` flush wrote the
incremented record count *before* the rows (a crash left count > rows; and a
count-last variant with `seekend` would strand orphans mid-file). Rows now
land at the offset the count implies, then the count updates — orphans from
a crash are overwritten by the next flush, and the on-disk count never
exceeds the rows on disk. U6-4's stale closing docstring paragraph fixed in
the same file.

**F10 (Moderate, auditor-reproduced from U2-1, FIXED).**
`pic_cuda.jl` `_cuda_pic_extract_slice` built 5-field slices when
`longitudinal_kick=false` while the quadratic/node kick launchers marshal
`.pz` unconditionally (their kernels guard the pz WRITE by the flag): every
gathered CUDA route crashed at argument marshalling — reproduced as
`FieldError: type NamedTuple has no field pz` on
`cuda_indexed_wavefront=false` + `:quadratic` + `longitudinal_kick=false`,
a configuration that passes validation and runs clean on CPU. (The agent's
claimed `cuda_async=false` variant was in fact guarded by the existing
`:quadratic` gate — narrower than claimed, the classic pattern.) Fix: the
extractor always gathers all six coordinates; the store path still scatters
pz only when the longitudinal kick is active, so the extra plane is
read-only. Verified post-fix: all three formerly-crashing routes run with
CPU parity 7.2e-15..1.4e-14; indexed-route regression guards unchanged.
Pinned by a new CUDA testset at 1e-13.

**F11 (Major, auditor-reproduced from U1-1, FIXED).** `interaction_grid=:node`
silently degraded to `:slice_pair` on every non-indexed CUDA wavefront
sub-route (node caches prebuilt, never read there): off-route node-vs-slice_pair
maxdiff 2.5e-15 (pure ordering noise — node dropped) vs 1.2e-2 on the honored
route; and `pic_timing_detail=true` alone knocked the route off the async
path, moving physics by 8.9e-3 under `:node` (2e-15 under `:slice_pair`) — a
diagnostic changing tracking results, against `interface.jl`'s own rule. Fix:
the static gate (`_require_cuda_pic_options`) now requires the full indexed
flag set for `:node`+`:wavefront`, and a runtime guard at route resolution
refuses the detailed-timing degradation with a directed message naming the
sequential alternative. All four flag combos + the runtime case refuse with
`ArgumentError`; the honored routes are regression-guarded. Pinned by the
same CUDA testset.

**F12 (Moderate, auditor-reproduced from U3-1, FIXED).**
`HighEnergyWeakStrongLimitContract` and `CoherentModePhysicsContract` seeded
the global RNG and never restored it (probe: seeds `0x123456789abcdef` and
`20260727` left behind), while every other RNG-touching contract in
`Contracts.jl` saves/restores — the exact mechanism of the recorded
SolverOption suite failure. Both validates now wrap their bodies in the
file's own `try/finally` restore idiom; probe re-run shows LEAKED=false for
both. U3-2 fixed alongside: the symplecticity docstring advertised
`default_tolerance=5.0e-7` while the struct default is `5.0e-8` (the fix
had landed in code only).

**F13 (Moderate, auditor-reproduced from U11-5, FIXED).**
`MisalignedElement`, `RefTilted`, and `CompositeLine` defined no
context-aware call, so the generic `AbstractTrackOp` fallback (Track.jl)
dropped the `TrackingContext` and a wrapped `LumpedRad` silently fell back
to its stateful contextless RNG — measured |dx| = 1.4e-4 between two
identical executions; determinism and CPU/CUDA identity lost for any
misaligned/rolled/composite-wrapped stochastic element. All three wrappers
now forward ctx (frame changes and roll conjugation preserved around the
inner ctx call); post-fix bit-repeatable (|dx| = 0.0). Negative control:
FAILs with the sources stashed.

**F14 (Moderate, auditor-reproduced from U11-6, mitigated as a loud
warning).** The radiation RNG key is (seed, method, turn, `elem.rng_id`,
particle, component) and `LumpedRadSpec` auto-assigns one `rng_id` per spec
OBJECT — so placing one spec twice (unavoidable syntax under `BeamLine`
repetition) draws identical noise at both placements: two kicks measured
exactly 2× one; excitation variance grows quadratically, not linearly.
Full fix needs per-placement identity, which intersects the owner-deferred
observer-identity scheme (`todo.md`) — so the audit action is a
task-construction warning (walks tuples, vectors, `LineEntry`s, and nested
`:line` specs) naming the remedy, plus the todo pointer. Negative control:
FAILs pre-fix.

**F15 (Moderate, auditor-reproduced from U11-7, FIXED).** `_aperture_bump!`
indexed `counts[id]` under `@inbounds` with the unbound-placement default
`element_id = 0` — a silent out-of-bounds write (reproduced: particle
killed, counts unmoved, loss invisible to `loss_records`). Both backend
methods now guard `1 <= id <= length(counts)` and skip the bump — the kill
stands and the loss surfaces through the existing dead-vs-logged
unattributed warning. The negative control is inherently unobservable (the
pre-fix behavior was undefined memory writes that happened to leave the
same visible state), recorded as such; the guard is justified by the
mechanism, and the new test pins the now-defined behavior.

**F16 (Major, auditor-derived and reproduced from U12-1; model boundary
documented, code fix priced on `todo.md`).** The RF cavity's conversion to
TIME_ENERGY is called with arc position `s = 0` — `_rf_kick` has no channel
to its accumulated reference path — so its `z1` is `z/β`, not the full
`-cΔt = z/β + s(1/β₀ − 1/β)`. The auditor re-derived the conversion from
first principles (it matches `longitudinal.jl:179` exactly) and confirmed
the omitted term is the velocity slip, which in convention #3 can enter
ONLY here: a ring closed by this cavity has slip factor `α_c`, missing
`−1/γ₀²`. Reproduced: ν_s matches the `η=α_c` analytic at ratio 1.0007 and
misses the true-η value by 1.8403× (2.5 GeV proton, α_c=0.2); the missing
phase slope equals `k·C/(β₀γ₀²)` to 15 digits; the transition side is wrong
whenever `α_c < 1/γ₀²`. Negligible at the ultrarelativistic parameters all
committed checks ran at — which is why they passed; the theory note's own
§7 criterion (ν_s against the FULL η) was the missing check, and **the
note's own Step-0 example makes the same `s=0` call while flagging the `s`
trap a paragraph later** — a Knowledge-Layer defect faithfully implemented.
Disposition (Phase 15): the honest fix needs the arc/survey channel Scope B
already needs for `P0(s)` — priced as a new `todo.md` row; the false "no
approximation" docstring claim is corrected, the model boundary is now
stated on the element (docstring + construction_help + ParamMeta) and in
the note (correction block beside the original). Fixed alongside: U12-2
(the `k*z + phase` docstring claim — actual argument is `k*z₁ + phase`,
coinciding with ThinCrabCavity only at β=1) and U12-3 (`voltage` +
explicit `beta0`/`gamma0` silently overwrote the explicit values — now a
directed refusal, verified).

**F17 (High, auditor-reproduced from U10-1/2/3/4, FIXED).** Four related
solenoid/magnet defects. (1) Every STRAIGHT solenoid was a `MethodError`
under a ForwardDiff coordinate Jacobian — the body was complex-typed
(`complex(x, y)` has no Dual method) and `_curv_sin` was strict `(::T,::T)`
with a coordinate-dependent kappa; invisible to the h≠0 sweep, which only
exercises curved solenoids, and to the parameter-derivative sweep, whose
duals arrive matched. Fix: the map is a real-arithmetic transcription of
the complex closed form — verified **bit-identical** over a 42-point
(ks, L, coords) grid — and `_curv_sin`/`_curv_vers` promote through their
product. Post-fix: complex-step and ForwardDiff agree (dx/dx =
0.8826462496730979 both routes); straight-solenoid symplecticity residual
1.8e-16..5.6e-16. (2) `Solenoid(spec)` promoted only (L, ks, h), so dual
multipole strengths died in conversion — promotion now spans the strength
tuples (derivative measured finite). (3) `curved=false` stored the RAW h:
the psi table was gated on `hc=0` while `_sol_kick` received `elem.h≠0` —
a silent non-gradient at |J′SJ−S| = 2.50e-3 (k0s) / 2.5e-5 (k1). The
runtime now stores the curvature it tracks with; curved=false equals the
h=0 control exactly (6.3e-11 = FD floor, identical). (4) The LatticeMagnet
had the OPPOSITE defect: it resolved `curved` AFTER building the psi table
and stored raw h, so the body kept the curvature its own warning said was
ignored (1.6e-7 vs a real h=0 track) — resolution hoisted above every
consumer, `hc` stored; curved=false now equals h=0 **exactly** (0.0).
Fingerprint bit-identical after the whole package (the default
`curved=true` path stores `hc == h`). Pinned by a new testset.

**F18 (Medium, double-sourced U1-2/U5-3, FIXED).**
`slice_interpolation = :quadratic` under `interaction_grid = :node` was
accepted and bit-identically ignored on BOTH backends (the parity contract
shared the blind spot; found independently by two readers, reproduced by
the U5 probe: ndiff = 0 vs a 10,000-value control). `_validate_pic_solver`
now refuses the combination with a directed message, the same policy as
its `grid_extent` precedent; composing them is future work for the
node-interaction-grid program. Verified: refusal fires at collide,
`:node`+`:linear` unaffected.

**F19 (Medium, from U15-1/U19-5, FIXED).** Nothing pinned the Philox
IMPLEMENTATION: the RNG validation script measures only moments and passed
a Weyl-bump-removed Philox and a 3-round variant. The suite now carries the
three upstream Random123 `kat_vectors` for philox4x32-10, driven exactly as
`counter_philox4x32` drives the round loop (U15 verified the current
implementation bit-exact against them; the testset makes that permanent).

**F20 (Medium, from U17-1, FIXED).** Three CUDA-gated testsets reported a
green `@test true` on CPU-only hosts — a pass that asserts nothing, against
the file's own honest-skip rule — now `@test_skip "CUDA device not
available"`; the header's stale "nine gated testsets" inventory corrected
(24+ in the back half alone). Gated sets with no else-branch still vanish
silently; noted in the header for new tests.

**F1 (Moderate, auditor-confirmed, FIXED in package 2).**
`src/tasks/strongstrong/interface.jl:1991-1992`
(`_prepare_strong_strong_luminosity_file!`): a torn last line from a
hard-killed writer whose turn field is a prefix of the true turn ("1" from
"12") parses as a smaller turn, slips under the `< first_turn` drop on the
retry, and is kept forever — the file then carries two rows labelled turn 1
(one with the wrong field count), violating the function's own "a file
carrying two rows for one turn is corrupt for every reader" docstring.
Reproduced: `scratchpad/A2_lum_torn_write_probe.jl` — retry threw nothing;
final turn column `[0..11, 1, 12, 13]`; duplicated labels `["1"]`; field
counts `[2, 1]`. Independently found by sub-agent U4 (U4-3). The HDF5
MomentObserver twin is crash-safe here by `record_count` ordering
(`BeamObservers.jl:1088-1103`, verified sound).

## 5. Corrections to this audit's own analysis

- **U2-1's `cuda_async=false` variant was wrong**: that route is guarded by
  the existing `:quadratic` gate (my GPU run got the directed refusal, not
  the crash). The lead was right in mechanism and wrong in one of its two
  claimed reachable routes — recorded, and the narrower truth is what F10
  fixed.
- **The A-2 "mid-file corruption refused" check does not discriminate**:
  pre-fix code also threw `ArgumentError` (from `parse`, accidentally). The
  five other package-2 behaviors carry the negative control; this one is
  guarded by message content only.
- **F15's negative control is unobservable in principle**: the pre-fix
  behavior was an out-of-bounds write whose visible state happened to match
  the fixed behavior. Recorded rather than manufactured.
- **Fingerprint scope**: the baseline is CPU-only by design; CUDA-touching
  fixes (F10/F11) were instead gated by measured cross-backend parity. A
  future audit wanting a CUDA fingerprint should capture one before its
  first CUDA fix.
- **Agent-lead survival**: 21 briefed units produced ~120 leads; every lead
  the auditor acted on reproduced (with one variant narrowed, above), and
  none of the ~90 as-yet-unfixed leads has been contradicted — but they
  remain LEADS (≈60% historical survival) until reproduced; §7 marks the
  auditor-reproduced subset explicitly.

## 6. Test, contract, validation, and execution log

- **Suite run 1** (Phase 8): `julia --startup-file=no --project=. -e
  Pkg.test(julia_args=["--threads=4"])` at `6a3f39a`, background task. Result:
  **aborted** at "Curved frame x transverse field" (31/32 passed; the F2
  failure), after 40 top-level testset summaries. All testsets after
  `runtests.jl:2953` unexecuted in this invocation. Rerun after the F2 fix.
- **Fingerprint baseline** (Phase 13 gate): `scratchpad/fingerprint.jl` →
  `fp_run1.txt`, 57 lines, CPU-only: per-kind tracked coordinates for every
  registered element spec (zero throws), `:equal_area`/`:equal_count` slice
  objects, 2-turn strong-strong minis on all four solvers (.lum rows +
  coordinate sums, both beams), `beam_statistics`. Two runs **bit-identical**;
  sha256 `d6ab7170f3a2c62d83bcbadbd3476019829b3ddab28f1a90e22b47586cfb3520`.
  Captured before the first source modification of this audit.
- **Suite run 2** (Phase 8, at `13c2733`): full `Pkg.test` `--threads=4`,
  GPU active: **132 top-level testsets, zero failures, exit 0** — the first
  complete suite run since `baf0255`; the CUDA half, examples testset, and
  both append testsets all executed.
- **Final suite run** (Phase 14/16 gate, at the closing tree): full
  `Pkg.test` `--threads=4`, GPU active — **137 top-level testsets, zero
  failures, exit 0**; the five testsets this audit added all ran and passed.
- **Fix-package probe log**: packages 2–8 each verified by a standalone
  probe on the fixed tree and (where observable) a stash-based negative
  control on the pre-fix tree; fingerprint re-diffed bit-identical after
  packages 2, 5 (implied by 7's run), and 7.
- **GPU verifications** (`scratchpad/gpu_verify_u21_u11.jl`,
  `gpu_fixverify_f10_f11.jl`): pre-fix U2-1 FieldError and U1-1 node-drop
  measurements; post-fix parity and refusal matrix (see F10/F11).

## 7. Open queue — dispositioned, priced, with reproductions

### Fix campaign disposition (2026-08-05, follow-on session)

The owner directed a fix campaign over this queue. Closed, each with
reproduction → fix → verification (numbers in the commit messages):

- **U7-2** CUDA weak-strong luminosity per-turn reset (`e4fc840`; parity
  0.0/1.2e-16 at turns=3, CUDA-gated pin).
- **U6-2** replay-discard for all four remaining observer formats
  (`ef31a61`; four-format testset).
- **U5-1/2 + U16-3** count-invariant reductions: fixed chunk grids, path
  choice by data size only (`95334bf`; 1/4/8 workers bit-identical incl.
  spectral luminosity at 0 ulp, zero measured cost, pin extended above the
  thresholds).
- **U7-1** OctopusForwardDiffExt: Faddeeva holomorphic rule + calibration
  pass-through (`1e58d43`; FD agreement 6.8e-5, dual-Jacobian symplectic to
  4.5e-12).
- **U3-3/4/5/6/7/9, U13-3/4, U16-2, U21-7** contract-coverage package
  (`e6ea0f2`; solenoid symplecticity cases + declaration tripwire
  (injection-verified), type-tree completeness guards, GaussianPIC/BPM/task
  schemas, broken-baseline reporting — which immediately exposed and fixed
  three kinds with no keyword constructor form; sweep now 244/0/0).
- **U3-10/U13-1/U13-2** unknown-key warning at the construction choke
  point, placement keys bind everywhere, epoch-carrying `set_param!`
  (`a477f7d`).
- **U11-1/2/3/4/8** nested-line length in every walker, state-preserving
  reverse, thin-kind folded-sugar rejection on both paths, hidden-aperture
  warning (`2d7cff9`).
- **U19-1/2/3** coherent-modes tables regenerated from current code; the
  detached y-mode conclusion corrected beside the original; u>1 regime
  flagged (`22c97e7`).
- **U14-1..7 + A-1** knob package (merge `a5c3e27`: registry atomicity on
  every throw path, total string round-trip incl. NaN/Inf and left-nested
  `^`, named-constant knob names refused, widened directed errors, public
  `knob_symbolics_available()`).
- **U17-2/3/5, U16-1/4/5, U2-2** test-quality package (merge `bbd9247`:
  kick-level spectral-vs-BE assertions that fail zero/double/flip on both
  beams, per-family corpse-semantics pins, CUDA histogram membership
  unified to the CPU rule — 2138/260000 divergent bins → 0).
- **U1-3, U21-2, U21-3** CUDA workspace key completeness; two validation
  scripts gain their gates (`9c2f2fd` neighborhood).
- **Hygiene sweep** (`a5d8609`): U15-4/5/6/7 RNG oddments and directed
  refusals; U12-4/5; U3-8; and the doc-drift batch U9-3, U11-10/11/12,
  U13-5 (named)/6, U18-1/2/4/6, U19-6/8, U20-3/8, U21-1; U15-2/3 recorded
  as accepted limitations at their sites.
- **U5-5/6/7/8, U10-5/6/7** deposit-edge and series numerics (merge
  `0de6b87`): source-side drop counting, per-particle escapee counting, CIC
  boundary-node weights (both backends, transcription-swept 0 mismatches),
  full-extent luminosity sums (TSC deficit 8.0e-5 → 4e-16), and the three
  series/cancellation rewrites verified against BigFloat (`_curv_vers`
  5.9e-9 → 1.5e-17 at the old seam; `_sol_log_over_h` d/dh 1.5e-8 →
  ≤3.2e-14; `_wedge` 2.8e-10 → 2.5e-20 at b1=1e-8). Campaign fingerprint:
  bit-identical except the one intended line — the `:sbend` example moved
  ~7e-16 absolute, inside the widened `_curv_vers` series window, with the
  PTC contract unchanged at 55/55, worst 5.0e-13.

**Campaign gate:** final full suite at the closing commit — **147
top-level testsets, zero failures, CUDA half active** (137 pre-campaign).
The shakeout getting there is itself part of the record: five in-suite
failures, every one either a strengthened check catching a campaign change
(the `:line` survey-`L` correctly flagged as never reaching the tracking
map → documented-inactive; the nested-Hessian bit-exact symmetry broken at
4.3e-19 by the higher-order series → principled tolerance) or a
campaign-test defect (worker counts above the suite pool; a log-kwarg
regex; and the type-tree guards flagging the suite's own Main-defined
scaffolding types — now scoped to Octopus-defined types,
hostile-subtype-verified).

**Still open after the campaign, priced:** U9-1 (port the R9 dropped-charge
tripwire to the three CUDA spectral deposits — GPU kernel work), U9-2 (R12
transverse pre-solve hoist on CUDA — perf only, doubly non-default),
U13-2-completion (declare placement params per-kind in schemas, with the
per-kind inactive entries that zero-length elements then need),
U13-5-full (the 76/335 undocumented-exports sweep beyond the named ones),
U17-6/7/8 and U16-6 (minor test-shape items), U19-4/9/10 (print-only
gates in characterization scripts documented as such; SIGN_KERNEL
auto-selection), U20-1/2/4/5/6/7 (validation scripts that characterize
rather than gate — README frames them so), U21-4/5/6 (symplecticity script
mirror, backend-consistency element-list refresh, PTC generate-path dead
field), U21-8/9/11/12 and U18-3/5 (small doc/output-discipline items),
U2-3 (1-ulp TSC w3 note), and the two U4 observations (mixed-IP schedule
row semantics; `_collision_solver` identity comparison). None is
correctness-critical; each carries its file:line in the unit reports.

### Post-campaign closures (2026-08-05, audit-queue session)

- **U9-1** R9 dropped-charge tripwire ported to all three CUDA spectral
  deposit kernels (`9f5accf`). Clipped weight is counted inside the deposit
  kernels (a subset-sum difference in matching term order -- exactly 0.0
  with no atomic when nothing clips) because a per-solve grid total would
  synchronize the stream; one aggregate warning per collision, flushed from
  a one-element device accumulator. Verified: 1.0 exactly per fully-out
  particle through each kernel, all-inside control exactly 0.0, the CPU R9
  configuration warns through the CUDA 6D path (aggregate fraction 0.097
  vs CPU per-solve 0.83/0.34), parity unchanged (coords <= 6.2e-18, lum
  2.1e-16), cost within noise at 200k/15 slices/grid 128. The transverse
  path cannot clip -- it never moves x/y inside a collision -- which is
  why the CPU R9 suite case (and the new CUDA one) fires only through the
  6D map.



Every item below survived to the end of this pass unfixed, with its severity
and what closing it takes. Items marked ✔ were auditor-reproduced; the rest
are agent leads with recorded reproductions.

**Medium-high / physics or determinism:**
- ✔ **Thread-count invariance above the parallel thresholds** (U5-1/2,
  U16-3, triple-sourced): the part-9 "bit-identical at 1/4/8 workers" claim
  was true only below `_PIC_PARALLEL_DEPOSIT_MIN=4096` (the pin used 500 —
  1500/beam over 3 slices); above it, chunk-ordered deposit and moment
  reductions differ across worker counts (coords ≤2.5e-15, moments to
  131,072 ulps). Roundoff-scale, but the recorded claim is now corrected
  here and in `todo.md`; the decision (count-invariant fixed-chunk
  reduction vs re-scoping the pin) is the owner's, priced in `todo.md`.
- **U7-2**: CUDA weak-strong kernels SUM luminosity across turns while the
  CPU stores the final turn (~N× divergence of `last_luminosity`); backend
  contract compares coordinates only. GPU repro recipe in U7's report.
- **U6-2**: `LuminosityObserver`/`JLD2BeamMomentObserver`/
  `BeamMomentObserver`/`CoordinateSnapshotObserver` have no replayed-window
  discard (retry duplicates turn labels) — the idempotence protocol exists
  only for `MomentObserver` and the .lum path. Probe recorded.
- **U7-1**: elliptical (η≠0) Bassetti-Erskine kick throws under ForwardDiff
  (`_near_round_conditioning_factor`, `_erfcx` lack Dual paths) —
  same family as F17 but needs a derivative rule, not a transcription.
- **U19-1/U19-2 (doc-High)**: coherent-modes note §3 table is
  pre-normalization-fix data; the "no detached EIC y-mode" claim is stale
  against the current eigen-solve. Needs re-runs to regenerate — priced,
  not guessed.

**Medium / correctness-adjacent and validator gaps:** U3-3 (solenoid
declares SymplecticityContract; contract case list lacks it; no
declaration↔case tripwire), U3-4 (+U13 detail: `validate_configuration_
metadata` misses GaussianPICPoissonSolver, BPMObserver, any task-level
schema; second hand-copied solver list at `Contracts.jl:2188`), U3-6/U21-13
(PublicConfigurationEffectiveness + both strong-strong backend-consistency
contracts executed by no test and no CI), U3-10/U13-1/U11-9 (unknown
keywords accepted by all 32 friendly constructors; out-of-schema keys can
change physics — `QuadrupoleSpec(e1=0.2)` shifts tracking 7.7e-7; choke
point characterized in U13's report), U13-2 (params read by compile are
rejected by the documented `spec.param=` binding; the `spec.params[:k]=`
escape hatch skips the `_SPEC_EPOCH` bump), U13-3 (empty `tracking_methods`
silently disables three validator checks; `:line` live instance), U14-1
(knob retype-before-throw mutates cached value without epoch bump), U14-2
(`^` string round-trip), U17-2 (spectral-vs-BE proton assertion passes with
the kick zeroed/doubled/flipped), U17-3 (corpse semantics differ Gaussian
vs PIC, 2.6% luminosity, unpinned), U16-2 (a "must be able to fail" control
that cannot fail), U16-5 (bare `catch` swallows AD-sweep regressions),
U15-3 (cutoff clip-vs-resample between backends, atoms at the cutoff),
U19-3 (detuning u>1 unphysical and grid-dependent in archived bands).

**Low / hygiene, docs, dead code** (full detail in unit reports):
U1-3, U2-2, U2-3, U3-5/7/8/9, U5-5/6/7/8, U9-1..4, U10-5/6/7/8/9/11,
U11-1/2/3/4/8/10/11/12, U12-4/5 (+two cross-file notes), U13-4/5/6,
U14-3..7 (incl. the public `knob_symbolics_available()` query that would
retire A-1), U15-2/4/5/6/7, U16-1/4/6, U17-4..8, U18-1..6, U19-4..10,
U20-1..8, U21-1..12, A-1.

## 7a. Historical lead queue (as first recorded)

Wave 1 is fully reported (U1–U6; full agent reports under
`scratchpad/reports/`). Open leads by unit, severity-ordered; ✔ marks
auditor-reproduced items promoted to Findings.

From U1 (pic_cuda.jl 1–3000):

- **U1-1 (HIGH).** `interaction_grid=:node` silently falls back to
  per-slice-pair meshes on every CUDA wavefront sub-route except the
  fully-indexed one; with all-default flags,
  `StrongStrongDiagnostics(pic_timing_detail=true)` flips `use_async` off
  and thereby **changes tracking results** — a diagnostic changing physics,
  against `interface.jl:293-296`'s own rule. CPU-side gate confirmed by
  agent run (9/10 accepted combos drop `:node`); GPU half needs the card.
- **U1-2 (Medium)** = U5-3: `slice_interpolation=:quadratic` accepted and
  bit-identically ignored under `interaction_grid=:node` on BOTH backends
  (double-sourced by two independent agents; parity shares the mistake).
- U1-3 (Low): `_cuda_pic_workspace!` cache key omits
  green_cache/min_ratio/growth (CPU keys them) — reproducibility drift only.

From U2 (pic_cuda.jl 3000–5966; the 5490–5966 Gaussian kernels read):

- **U2-1 (Medium).** Gathered CUDA kick launchers marshal `out.pz`
  unconditionally while `_cuda_pic_extract_slice` omits `pz` when
  `longitudinal_kick=false`: every gathered route should crash with "type
  NamedTuple has no field pz" on a documented config. GPU verify queued.
- U2-2 (Low): `:equal_area` bin membership CPU (division+clamp) vs CUDA
  (edge comparisons): 0.82% different-bin + dropped orphans on quantized z.
- U2-3 (info): TSC `w3 = 1-w1-w2` vs closed form, 1 ulp.

From U3 (Contracts.jl):

- **U3-1 (Medium).** `HighEnergyWeakStrongLimitContract` and
  `CoherentModePhysicsContract` set the global RNG and never restore
  (the other four RNG-touching contracts save/restore).
- **U3-3 (Medium).** Solenoid declares `SymplecticityContract` but the
  contract's hand-enumerated case list has no solenoid; no
  declaration↔case tripwire.
- **U3-4 (Medium).** `validate_configuration_metadata` hardcoded lists
  stale: `GaussianPICPoissonSolver` absent (margin_sigma/neutralize/
  coupling_tol unchecked), `BPMObserver` absent, no task-level schema
  (`luminosity_append` has NO schema entry), and `Contracts.jl:2188` is a
  second hand-copy of the solver list. Extends inherited item 5.
- **U3-6 (Medium).** `PublicConfigurationEffectivenessContract` and both
  strong-strong backend-consistency contracts are executed by no test and
  no CI — the "correct check, never executed" class at contract level.
- **U3-10 (Medium).** Friendly constructors accept unknown keywords and
  wrong types silently end-to-end (`QuadrupoleSpec(this_keyword_does_not_exist=1.0)`
  constructs, compiles, tracks) — a typo'd physics parameter is silently
  ignored. Mechanism is in the element layer; handed to U10's territory.
- U3-5 (Low-Med): `append`/`luminosity_append` outside every effectiveness
  contract (mitigated by direct unit tests). U3-7 (Med-Low): element
  parameter contract turns a throwing baseline into a silent skip, guarded
  only by a zero-headroom count pin. U3-2/U3-8/U3-9 (Low): docstring
  tolerance mismatch 5e-7 vs 5e-8; vacuous `:cuda_pic_launch` receipt
  check; `_PTC_DEFAULT_ATOL` permanently empty vs docstring.

From U5 (pic_cpu.jl + slicing.jl):

- **U5-1/U5-2 (Medium).** Thread-count invariance fails above
  `_PIC_PARALLEL_DEPOSIT_MIN=4096` (chunk-ordered deposit and
  transverse-moment reductions): 74,882/90,000 coordinate values differ
  1-vs-4 workers (max 2.5e-15), moments to 131,072 ulps; the part-9
  "bit-identical everywhere" pin used 500/slice and never entered this
  regime — **the recorded claim was true only below the threshold.**
- U5-5 (Med-Low): under `grid_extent=:sigma`, source particles dropped by
  the deposit are uncounted (1.0 particle-charge missing, `dropped==0`,
  no warning) — the "Never silent" contract is half-covered. U5-6 (Low):
  both-axes escapee counted twice. U5-7 (Low): CIC weight at in-range
  `u==n-1` puts full charge one cell inward (CPU and CUDA identical —
  parity-invisible). U5-8 (Low): TSC top-edge deposit excluded from the
  luminosity overlap sum, 8.0e-5 relative deficit.

From U6 (observers + Tasks.jl):

- **U6-2 (Medium).** `LuminosityObserver`/`JLD2BeamMomentObserver`/
  `BeamMomentObserver`/`CoordinateSnapshotObserver` have no replayed-window
  discard: a crashed `execute!` retry yields duplicated turn labels
  ([0,1,2,0,1,2,3,4,5]); a fresh process truncates. The append/idempotence
  protocol exists only for `MomentObserver` and the .lum path.

From U7 (strong-beam stack; **the physics core audits clean** — term-for-term
theory mapping, 200k-point quadrature at ≤2.5e-14, Furman erratum verified):

- **U7-1 (Medium).** ForwardDiff Dual through any elliptical (η≠0)
  Bassetti-Erskine kick throws in `_near_round_conditioning_factor`
  (`strong_beam.jl:746-757`), contradicting the T<:Number AD design comment
  at :188-191.
- U7-2 (Low-Med): CUDA weak-strong kernels SUM luminosity over turns while
  CPU stores the final turn — `last_luminosity` diverges ~N× for turns>1;
  the backend contract compares coordinates only.
- U7-3 (Low): `slice_center` without `slice_weight` silently discarded.
  U7-4 (Low): `:equal_width` without `slice_width` throws
  `MethodError(Float64(::Nothing))`. U7-5 (Low): slicing theory note still
  documents `:equal_area` as default; code default is `:sqrt_density`.

From U8 (GaussianPIC twins; **clean** — S1 verified end-to-end, all 27
options traced across the composition seam, erf profiles ≤3.9e-14 vs
quadrature, neutralization exact):

- U8-1 (Low, doc): theory note §7.5 claims the coupled branch is CPU-only;
  the CUDA indexed route implements it (solver docstring is correct).

From U9 (spectral twins; **clean** — continuum-mode-sum anchor re-earned at
≤3.7e-15, S20/R2/R7/R9/R10/R12 fixes verified, Core.Box allowlist re-derived
TRUE): U9-1 (Minor): the R9 dropped-charge tripwire is CPU-only — all three
CUDA spectral deposits still clip silently. U9-2: R12 hoist CPU-only
(perf, doubly non-default). U9-3/U9-4: comment/doc nuances.

From U10 (lattice magnet stack; the exact bend/drift/fringe algebra audits
clean to generating-function level):

- **U10-1 (High).** `solenoid.jl:237` `_curv_sin(kappa/2, L)` strict
  `(::T,::T)` with coordinate-dependent kappa: the straight solenoid
  MethodErrors under ForwardDiff coordinate Jacobians (the h≠0 sweep only
  exercises curved solenoids, so it cannot see this).
- **U10-3 (Medium).** `curved=false` with stored `h≠0`: the psi table is
  gated on `hc=0` but `_sol_kick` receives `elem.h≠0` → non-gradient kick,
  |J′SJ−S| = 2.50e-3 — the original F2-class magnitude, silently.
- U10-4 (Low): LatticeMagnet `curved=false` does the OPPOSITE (keeps
  curvature, warns it is ignored — the warning is false by 1.6e-7).
- U10-2 (Med): `Solenoid(spec)` promotes over (L,ks,h) only — Dual multipole
  strengths die. U10-5/6/7 (Low): series-branch boundary errors
  (`_curv_vers` 5.9e-9, `_sol_log_over_h` derivative 1.5e-8, `_wedge`
  cancellation ∝1/b1). U10-8/9 (doc): theory-note fringe equations not
  symplectically consistent as written; contradictory kill-flag claims.
  U10-10 (info): unknown-kwarg mechanism characterized — out-of-schema
  keys can CHANGE PHYSICS (`QuadrupoleSpec(e1=0.2)` shifts tracking 7.7e-7).
  U10-11 (Low): linear6d validator orders on T → Complex MethodError.

From U11 (aperture/beam_line/thin/radiation/misalignment):

- **U11-5 (Med-High).** `MisalignedElement`/`RefTilted`/`CompositeLine`
  wrappers drop `TrackingContext`: wrapped stochastic radiation silently
  uses `Random.randn()` — determinism and CPU/CUDA identity lost.
- **U11-6 (Medium).** The radiation RNG key lacks placement identity: two
  placements of one `LumpedRadSpec` draw identical noise (2 kicks = exactly
  2× one; variance 4× not 2×).
- **U11-7 (Medium).** `aperture.jl:334-342` loss_record with defaulted
  `element_id=0`: `@inbounds counts[0]+=1` is a silent out-of-bounds write;
  the loss is invisible.
- U11-1/2/3/4 (Med): BeamLine own-state nested line counts L=0 in surveys;
  `reverse` drops own state; folded-override guard omits thin kinds;
  post-construction `setproperty!` stored-never-read. U11-8 (Low-Med):
  composite-line aperture losses unattributed. U11-9..12 (Low/doc).

From U12/U13/U14/U16/U17/U18 (wave 3; full lists in the unit reports):

- **U12-1 (Major, physics).** `_rf_kick` omits the path-length `s` term in
  both longitudinal conversions: the RF slip factor becomes `alpha_c`
  instead of `eta = alpha_c − 1/gamma0²` — measured 1.84× tune error at
  2.5 GeV proton, wrong transition side when `alpha_c < 1/gamma0²`.
  Auditor derivation pending (the stated reason must be checked, not just
  the discrepancy).
- **U17-1 (Medium).** CUDA gating in the suite's back half reports green
  on CPU (`else @test true` at three sites; 14 testsets vanish without a
  skip marker) — the honest-skip rule broken. **U17-2 (Med-High).**
  The spectral-vs-BE kick testset passes with the kick zeroed, doubled, or
  sign-flipped on the proton side (rms of final momenta, atol 0.03 vs a
  4.8% signal). U17-3 (Med): corpse-handling semantics differ between
  Gaussian (renormalizes to live charge) and PIC (reduces charge), 2.6%
  luminosity, pinned nowhere.
- **U16-3 (Med-High)** = U5-1/2 third source: the thread-invariance pin
  (n=1500) sits below both 4096 parallel thresholds; at n=15000 the pinned
  invariant is false. U16-2: a "contract must be able to fail" control
  that cannot fail.
- U13-2 (Med): params read by `compile_runtime` (x_offset in 17/30 kinds,
  ref_tilt in 29/30) are rejected by the documented `spec.param=` binding
  path, and the recommended `spec.params[:key]=` escape hatch skips the
  `_SPEC_EPOCH` bump. U13-1 (Med): unknown keywords accepted by all 32
  friendly constructors (mechanism + choke point characterized). U13-3
  (Med): empty `tracking_methods` silently disables three validator checks
  (`:line` is the live instance). U13-4/5/6 (Low).
- U14-1 (Med): `@knob dep::T` retypes and converts a cached value BEFORE
  its own rejection throw (no epoch bump). U14-2 (Med): left-nested `^`
  breaks the string↔expression round-trip (64 vs 512). U14-3..7 (Low).
- U18-1 (Med): the strong-strong harness's solver-swap instructions are
  stale (uncommenting yields dead code). U18-2..6 (Low): env-var header
  omissions, repo-root `result/` writes from the suite, comment drift.

From U4 (reported; agent report at `scratchpad/reports/U4_report.md`):

- **U4-1 (HIGH, unverified by auditor).** `interface.jl:1717-1722,1854-1855,
  1991-1992`: `luminosity_append` continuation state is *not* in the file —
  `first_turn` comes from the fresh task's `next_turn` Ref (0), so a second
  task sharing the path or a process restart *without explicit `start_turn`*
  silently truncates all prior rows (agent measured a 10-row file wiped);
  docstring and commit message promise the opposite. MomentObserver shares
  the trap. Repro: `scratchpad/U4/u4_1_restart_truncation.jl`.
- **U4-2 (Medium, auditor-confirmed by inspection).** `interface.jl:1986,
  1993-1998`: append-mode prepare rewrites the whole file non-atomically
  (`readlines` → `open(path, "w")`) on every continuation; a kill in that
  window loses the entire history the flag exists to preserve. The HDF5 twin
  shrinks in place with no such window.
- **U4-4 (Low, unverified).** `interface.jl:1885-1888` vs `1987-1990`:
  observer tables are truncated before the .lum header guard can refuse, so
  an aborted execute! leaves the two companion outputs diverged.
- U4 observations (dispositions pending): mixed-IP luminosity schedule drops
  sibling IPs' evaluated values for that row (`interface.jl:2052`);
  `_collision_solver` compares solvers by identity (`interface.jl:2281`).

From the auditor's own U22 read:

- **A-1 (Minor).** `examples/knob_control.jl:151` gates on the internal
  `Octopus._symbolics_adapter_active()` — a public example teaching an
  internal call (AGENTS.md: examples tie to public APIs).
- **A-4 (Minor, confirmed by read).** `BeamObservers.jl:1092`:
  `throw(BoundsError("MomentObserver received more records than planned"))`
  abuses `BoundsError` (first field is the accessed object) — displays as
  "attempt to access String".
- **A-5 (Minor).** `BeamObservers.jl:961` continue path: `append=true` onto
  an existing **zero-byte** file (crash at create, `touch`) hits a raw HDF5
  open error instead of a directed refusal; the .lum twin checks
  `filesize(path) == 0` explicitly.

U4 sound-areas (agent-verified, provenance: agent): option→consumer tracing
complete (no stored-and-never-read option in `interface.jl`); knob/spec-epoch
gate matches `Tasks.jl:529` across task families; no `Core.Box` captures; the
luminosity schedule dispatch is specialized by all three grid solvers.

## 8. Change log

| file | change | finding |
|---|---|---|
| `test/runtests.jl` | h≠0 solenoid loop skips the empty content (pure case asserted by its dedicated pair) | F2 |
| `src/tasks/strongstrong/interface.jl` | `_prepare_strong_strong_luminosity_file!`: torn-last-line drop with warning, mid-file corruption refusal, total-wipe warning, atomic tmp+mv rewrite, corrected docstring; prepare hoisted above `prepare_observers!` | F1, F3, F4, F5 |
| `src/tasks/BeamObservers.jl` | append docstrings corrected (+stale closing paragraph), total-wipe warning in `_moment_append_continue!`, zero-byte file initializes fresh, `error(...)` instead of `BoundsError`, `BeamSwapAction` docstring attached, binary flush writes rows before count at counted offset | F3, F6, F7, F8, F9 |
| `test/runtests.jl` | new testset: torn writes dropped, corruption refused, wipes loud, zero-byte fresh-init (negative control: five behaviors fail with the two source files stashed) | F1, F3, F7 |
| `src/tasks/strongstrong/pic_cuda.jl` | `_cuda_pic_extract_slice` always gathers all six coordinates; runtime route guard refuses `:node` off the indexed wavefront sub-route | F10, F11 |
| `src/tasks/strongstrong/pic_cpu.jl` | `_require_cuda_pic_options` `:node` gate requires the full indexed wavefront flag set | F11 |
| `test/runtests.jl` | CUDA testset: gathered routes carry pz (parity pinned at 1e-13; measured 7.2e-15..1.4e-14), `:node` degradation refused statically and at runtime | F10, F11 |
| `src/contracts/Contracts.jl` | RNG save/restore in the two leaking validates; docstring tolerance 5.0e-7 → 5.0e-8 | F12 |
| `src/elements/misalignment.jl`, `ref_tilt.jl`, `beam_line.jl` | ctx-forwarding call operators on the three wrappers | F13 |
| `src/tasks/Tasks.jl` | `_warn_duplicate_radiation_streams` at task construction (walks nested `:line` specs) | F14 |
| `src/elements/aperture.jl` | bounds guard in both `_aperture_bump!` methods | F15 |
| `test/runtests.jl` | testset: wrapper ctx repeatability, duplicate-stream warning, unbound-aperture defined behavior | F13, F14, F15 |
| `src/elements/rf_cavity.jl` | model boundary documented (`_rf_kick`, spec docstring, ParamMeta, construction_help); voltage+explicit-beta0 refusal | F16, U12-2, U12-3 |
| `docs/theory/rf_cavity_and_reference_energy.md` | F16 correction block beside the Step-0 example that carried the defect | F16 |
| `docs/todo.md` | new open row: RF velocity-slip term, folded into the Scope-B survey channel | F16 |
| `src/elements/solenoid.jl` | real-arithmetic `_solenoid_map` (bit-identical transcription); promotion over multipole strengths; runtime stores `hc` | F17 |
| `src/elements/lattice_magnets.jl` | `_curv_sin`/`_curv_vers` promote through the product; `curved` resolved before the psi table; runtime stores `hc` | F17 |
| `test/runtests.jl` | testset: straight-solenoid Jacobians at machine epsilon, dual multipole parameter, curved=false equals h=0 exactly on both elements | F17 |
| `src/tasks/strongstrong/pic_cpu.jl` | `_validate_pic_solver` refuses `:node` + `:quadratic` | F18 |
| `test/runtests.jl` | Philox4x32-10 Random123 known-answer testset | F19 |
| `test/runtests.jl` | three `@test true` CUDA gates → `@test_skip`; header inventory corrected | F20 |
| `docs/theory/gaussian_longitudinal_slicing.md` | default-rule table row corrected (`:sqrt_density`, was `:equal_area`) | U7-5 |
| `docs/theory/gaussian_subtracted_pic_solver.md` | §7.5 coupled-branch backend claim corrected beside the original | U8-1 |
