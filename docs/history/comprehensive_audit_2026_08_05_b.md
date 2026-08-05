# Comprehensive Audit — 2026-08-05_b (second full re-read, same day)

**Status: IN PROGRESS.** This file is written incrementally, as the protocol
requires ("Checkpoint to disk continuously, not at the end"). Sections below
are filled as they are established; anything not yet established says so.

## 1a. Executive summary

Second full re-read at the owner's direction, uniform depth, one day after the
first closed. **Its justification is the 63 commits and +9,125/−775 lines that
had landed since the prior pass's declared commit** — that delta *is* the prior
audit's own fix campaign and queue-closure session, i.e. the code written in
response to findings, which no audit had since read. Measured Lesson 2 says a
fix's blast radius includes dimensions nothing measures; this pass is that
lesson applied to a whole campaign, and it paid.

26 briefed reading units plus auditor-direct seam passes over 53,472 Julia
lines. **Four findings confirmed by auditor reproduction, two of them fixed and
negative-controlled:**

- **F2 [Major, FIXED]** — an `execute!` that threw during observer preparation
  **destroyed luminosity history it had never written to**: 3 rows → 0 in
  replace mode, 5 → 2 in append. The prior audit's U4-4 fix had moved the
  `.lum` prepare *ahead* of the observers, which only reversed the truncation
  window. Now planned-then-committed with the observers validating in between:
  3 → 3 and 5 → 5.
- **F4 [Major, FIXED]** — the curved solenoid's implicit-midpoint stage had no
  convergence check. At its **own default `nst`**, an ordinary detector
  solenoid (`ks = 20 m⁻¹`, `L = 5 m`) gave symplectic residual **7.197 — or
  NaN — in silence**. The 16-sweep count had been argued sufficient "for every
  step count" from a table measured at a single point; the fixed-point map
  contracts at rate `q = L·ks/2nst`, so that argument was always about `q`, not
  `nst`. Now throws with a concrete `nst` at `q ≥ 1` and warns above 0.1,
  silent and bit-unchanged in the documented regime.
- **F1 [Major, open]** — the per-pair luminosity trace is populated on **1 of 6
  CUDA PIC routes** (CPU: all of them), while the scalar luminosity agrees to
  ~1e-15 everywhere, which is why nothing caught it. The consuming contract
  gates on `batch_mode == :wavefront`, so under `:sequential` it reports
  `passed` with `records_compared = 0` — **a contract passing by comparing an
  empty set**. Found independently by two units reading disjoint regions.
- **A-1 [Moderate, open]** — auditor-direct: a `StrongStrongTask` has no loss
  accounting at all. The same aperture that makes a `TrackingTask` print a
  per-collimator summary kills 3,793 of 4,000 particles here with only
  `count_dead` available, which makes `allow_lost_particles`' own documented
  cross-check impossible to perform.

**A correction against the audit itself (C-1)** is recorded beside the finding
it corrects: the seam pass began from a "strong-strong kills silently"
hypothesis that measurement refuted — the solver fails fast with a detailed,
actionable diagnostic. Filing it would have been a Major against correct code.

**Clean is a result, and most of the repository is.** The physics core held
again, this time against references built fresh rather than inherited: Philox
against KAT vectors fetched this session and an independently written
implementation using the *upstream* key schedule; Faddeeva against 4096-bit
BigFloat (worst 3.09e-13); beam moments against BigFloat (means exact to 0.0);
the Hirata boost against an independent transcription (≤5.42e-20); 124
symplecticity configurations at ≤9e-15; the spectral solve against an
independent continuum mode sum (≤2.3e-15); CPU↔CUDA parity across a full 64/64
sub-route matrix at 8.99e-17. `_needs_curved_potential` was shown to be
*exactly* the Cauchy-Riemann condition by total enumeration. The prior pass's
U11-1 walker split is genuinely fixed — 13 independent walkers agree on a
three-deep nested line.

**The honest remainder** is a priced queue of ~90 agent leads with
reproductions (§7), 7 of them Major candidates, none auditor-verified. Its
header says so in terms, because the series' measured agent survival rate is
~60% in four distinct miss shapes. The single most alarming candidate: the
CUDA spectral dropped-charge tripwire appears to report **exactly zero in the
blow-up regime it exists for**, through a float cancellation — an instrument
that has never been shown the disease at full strength.

- Commit under audit: `7de4d8132111c902f823da47323aaa496d674201` (clean tree at start).
- Protocol: [`docs/comprehensive_audit.md`](../comprehensive_audit.md).
- Role: maintainer agent, at the owner's direction.
- Prior full pass: [`comprehensive_audit_2026_08_05.md`](comprehensive_audit_2026_08_05.md)
  (declared commit `6a3f39ab`), itself one day after
  [`comprehensive_audit_2026_08_04.md`](comprehensive_audit_2026_08_04.md).

## 0. Declared scope

**Uniform-depth full re-read of every Julia line in the repository**, at the
owner's explicit direction, regardless of prior coverage. The prior ledgers are
used only to sharpen hypotheses, never to skip a line.

| tree | lines | treatment |
|---|---|---|
| `src/` | 34,726 | line-by-line, every file |
| `test/` | 9,773 | line-by-line (tests are claims; circularity and never-failing guards are in scope) |
| `validation/` | 7,891 | line-by-line + executed, GPU legs forced on |
| `examples/` | 712 | line-by-line + executed |
| `ext/` | 66 | line-by-line |
| `docs/` (excl. `history/`, `todo.md`) | ~2,300 + 17 theory notes | checked as claims about the code |
| **total Julia** | **53,472** | |

Plus: contracts run and checked that they prove what they claim (Phase 7); full
suite at CI settings on CPU+CUDA with the exit code recorded, not piped
(Phase 8); every example executed (Phase 10); independent derivation of the
equations the prior ledgers do not record as independently derived (Phases
5/12); seam-class cross-check passes by the auditor directly (Phase 3).

### Why a second full pass one day after the first

Not redundancy. The prior pass declared commit `6a3f39ab`; **HEAD is 63
commits and +9,125/−775 lines beyond it**. Those commits are the prior audit's
own fix campaign and queue-closure session — the code written *in response to*
findings, which no audit has since read. The largest deltas land exactly where
this repository's defects historically cluster:

| file | delta since audited commit |
|---|---|
| `test/runtests.jl` | +1,294 |
| `src/tasks/BeamObservers.jl` | +331 |
| `src/tasks/strongstrong/interface.jl` | +247 |
| `src/tasks/strongstrong/spectral_cuda.jl` | +188 |
| `validation/generate_ptc_reference.jl` | +168/−… |
| `src/tasks/strongstrong/pic_cpu.jl` | +161 |
| `src/tasks/strongstrong/pic_cuda.jl` | +155 |
| `test/nightly_suite.sh` | +71 (entirely new) |

Measured Lesson 2 is precisely that a fix's blast radius includes dimensions
nothing measures; Measured Lesson 9 is that the final gate catches what
targeted verification cleared. A fix campaign that has never been audited is
therefore the highest-prior-probability region in the repository, and this pass
weights its reading time accordingly **without** narrowing the declared scope
below the whole repository.

**Not covered, and why:** the Bmad reference case for
`misalign_convention=:bmad` (blocked on an external tool not installed here;
stays on `todo.md`); `docs/history/` archives as such (records of past states,
consulted not audited); `Manifest.toml` and dependency internals; PTC/MAD-X
regeneration if those tools are absent on this machine (the committed
reference's internal consistency is checked instead, and the substitution is
recorded).

## 0a. Method (binding for this pass)

- One driving session. Sub-agents multiply reading bandwidth only. **A
  sub-agent claim is a LEAD, not a finding** (measured series survival ~60%,
  in four distinct miss shapes); the auditor reproduces every lead before it
  enters Findings, and **no sub-agent ever applies a fix**.
- Behavioural fingerprint captured **before the first source modification**
  (section 0c).
- Fix while the reproduction is live; ledger, `todo.md`, and fix land in the
  same commit.
- Corrections to this audit's own analysis are recorded **beside** the original
  claim, never over it.
- Every reading unit received the standing brief verbatim from the protocol,
  prepended with its region, a distinct hypothesis drawn from the established
  defect classes, and its reference implementation.

## 0b. Reading units and assignment

Provenance: **auditor** = read directly in this session's driving context;
**agent** = briefed sub-agent line-by-line read (lead-generating only).
Status moves pending → reading → reported → **verified** (auditor has disposed
of every lead from that unit).

| unit | region (lines) | reader | hypothesis briefed | status |
|---|---|---|---|---|
| U1 | `pic_cuda.jl` 1–2000 | agent | twin divergence; device-IR compilability; kernel indexing/launch | reading |
| U2 | `pic_cuda.jl` 2000–4000 | agent | silent option degradation (F11 class); silent charge loss; equal_area membership drift | reading |
| U3 | `pic_cuda.jl` 4000–6009 | agent | moment/kick kernel numerics (**the prior pass's honest remainder, 5490–5966**); reduction-order dependence | reading |
| U4 | `Contracts.jl` (2,715) | agent | circular checks; hand-copied enumerations vs derived; contracts with no runner; skipped-reported-as-passed | reading |
| U5 | `interface.jl` (2,509) | agent | declared-schema ↔ runtime-consumer; unknown-kwarg acceptance; declared-but-unread options | reading |
| U6 | `pic_cpu.jl` + `slicing.jl` (2,724) | agent | thread/chunk-count invariance **above** the parallel thresholds; dropped charge; slicing edge cases | reading |
| U7 | `BeamObservers.jl` + `BPMObserver.jl` (2,185) | agent | append/restart protocol; four-format replay-discard by crash-retry probe; torn writes; silent row loss | reading |
| U8 | `strong_beam.jl` + `strong_beam_track.jl` + `gaussian.jl` (2,279) | agent | Bassetti-Erskine branch-boundary continuity; differentiability (U7-1); luminosity accumulation (U7-2) | reading |
| U9 | `lattice_magnets.jl` + `solenoid.jl` + `linear6d.jl` + `linear_maps.jl` (2,389) | agent | measured symplecticity sweep; cancellation-free small-argument helpers; type genericity; F17 bit-identity | reading |
| U10 | `gaussian_pic.jl` + `gaussian_pic_cuda.jl` (2,101) | agent | twin pair, parity brief; subtracted-model consistency; **prior pass's agent-only remainder** | reading |
| U11 | `spectral.jl` + `spectral_cuda.jl` (2,064) | agent | twin pair; the **unaudited** R9 tripwire and R12 hoist CUDA ports; independent mode-sum check | reading |
| U12 | knowledge/registry/policies/`Octopus.jl`/constants (1,977) | agent | metadata-validator blind spots by **injection**; CODATA constants; snapshot freshness; unconsumed policy fields | reading |
| U13 | `Knobs.jl` + `symbolic.jl` + `Tasks.jl` + `ext/` (2,302) | agent | epoch invalidation on every mutation path; both weakdep load modes; swallowed hook exceptions | reading |
| U14 | `Beam.jl` + `math/` + `track/` (2,083) | agent | Philox vs official KAT; RNG stream independence; Faddeeva accuracy; longitudinal round trips | reading |
| U15 | `beam_line.jl` + `aperture.jl` + `thin_elements.jl` + `radiation.jl` + `misalignment.jl` (2,282) | agent | **multiple walkers over one structure** on a nested line (U11-1/U11-8); loss attribution; wrapper→context forwarding | reading |
| U16 | small elements + `examples/` (1,885) | agent | F16 slip-factor boundary honesty + independent 1.84× reproduction; boost invertibility; identity limits; examples executed | reading |
| U17 | `test/runtests.jl` 1–2200 | agent | checks that never execute; circular tests; tests that never failed on their defect | reading |
| U18 | `test/runtests.jl` 2200–4400 | agent | same, plus the permanent sweep testsets' derived-vs-copied case lists and injection-verified power | reading |
| U19 | `test/runtests.jl` 4400–6600 | agent | same, plus **CUDA gates run for real** and verified to report skipped (not passed) without a GPU | reading |
| U20 | `test/runtests.jl` 6600–8759 | agent | same; this is the region that went dark under F2, and holds the campaign's new testsets | reading |
| U21 | `test/examples/` + `nightly_suite.sh` (1,085) | agent | harness↔example bit-identity; every `OCTOPUS_*` toggle effective; **nightly gate's exit-code and FAIL-row behaviour** | queued |
| U22 | `validation/` coherent-mode cluster (1,309) | agent | reference independence vs local reimplementation; regenerated table reproduces; independent Yokoya check | queued |
| U23 | `validation/` field cluster (2,183) | agent | instrument validation by injection; **enforced vs print-only thresholds**; header drift | queued |
| U24 | `validation/` remainder A (2,719) | agent | PTC provenance chain; symplecticity case list derived-vs-copied; print-only gates | queued |
| U25 | `validation/` remainder B (2,013) + README | agent | **GPU legs forced on** (the recorded never-run class); coverage tripwires; README accuracy | queued |
| U26 | `docs/` as claims about the code | agent | note↔implementation consistency; orphan numbers with no committed harness; index completeness; snapshot byte-diff | queued |
| U27 | Seam-class cross-check passes (§3) | **auditor** | never delegated | pending |
| U28 | Phase 7 contract execution, Phase 8 full gate, Phase 10 examples | **auditor** | never delegated | pending |

## 0c. Behavioural fingerprint (captured before the first modification)

Harness: `fingerprint.jl` (archived beside this report in the unit-report
directory). It emits **1,495 full-precision (`%.17e`) values**, one per line,
greppable and diffable:

1. **Per element kind, in isolation** — each of the 29 registered kinds in the
   canonical line applies to the same 8 hand-written deterministic particles
   (no RNG in the initial state, so a diff is the map's and not the
   generator's), one turn, all six coordinates. This localises any diff to a
   single element rather than to a composed line.
2. **The composed line**, three turns.
3. **Beam statistics** on a seeded 4,096-particle beam: means, rms,
   emittances, the full 6×6 covariance, and the x–z / y–z covariances.

The particle set deliberately includes an exactly on-axis particle, a
large-amplitude particle, and both signs of every coordinate, so branch
boundaries are exercised.

**Determinism verified**: two independent runs are byte-identical. A
fingerprint that is not reproducible is not a fingerprint, so this was checked
before the baseline was trusted.

Baseline: `baseline.txt`, captured at `7de4d81` with a clean tree, exit 0, no
stderr.

## 1. Inherited open queue (to disposition this pass)

From `docs/todo.md` and the prior report's §7:

1. **RF cavity velocity-slip term (F16)** — open by design; needs the
   arc/survey channel that RF Scope B also needs. This pass verifies the model
   boundary is honestly documented at both ends and reproduces the 1.84×
   independently (U16).
2. **Bmad reference cases for `misalign_convention=:bmad`** — blocked on an
   external tool. Code↔note internal consistency is checked instead (U15).
3. **Metadata validator remainder** — defaults-vs-constructor,
   declared-parameter-is-read, and `validate_configuration_metadata`'s
   hardcoded type enumeration. Measured by injection this pass (U12), and the
   hardcoded solver list at `Contracts.jl:2188` re-derived (U4).
4. **`:lattice` at grid 128** — the cap binds (`rho=11` wants 88×, gets 64×)
   and it lands at par with `:integrated` rather than the note's claimed 1.48×
   better. Note honesty checked (U26).

## 2. Traceability matrix

Requirement → note → equation → implementation → test → validation, with the
strongest link named and the number that anchors it. Chains **re-verified by
independent computation this pass**, not inherited:

| feature | anchor measured this pass |
|---|---|
| Philox counter RNG | KAT vectors **fetched this session** from the DEShaw repository and an independent implementation written with the *upstream* key schedule (bump before rounds 2..R) — textually different from Octopus's — agreeing on all three official vectors, then 20,004 tuples with 0 mismatches. Round-count sensitivity proves 10 means 10 (R=8/9/11/12 all differ). |
| Bassetti-Erskine / Faddeeva | vs `Complex{BigFloat}` at 4096 bits, cross-validated to 1.09e-96: **global worst 3.09e-13**. The 32 Weideman coefficients regenerated from the FFT construction: worst difference 7.79e-15, and using exact coefficients moves `w` by ≤1.05e-14, 30× below the method's own error. |
| beam statistics | vs BigFloat on the same 10⁶ points: means **0.0 absolute**, covariance 6.46e-14, emittance 5.51e-14, fourth central 2.20e-16, `rms == sqrt(diag(cov))` bitwise. Population (`/n`) convention confirmed uniform across all 12 other moment sites. |
| lattice magnets | 124 symplecticity configurations × 2 amplitudes by exact ForwardDiff: every residual ≤9e-15 except the curved solenoid's, which falls monotonically with `nst`. `_needs_curved_potential` shown to be **exactly** the Cauchy-Riemann condition by total enumeration of orders 0–6 normal+skew, with a measured non-gradient behind every `true` and 0.0 behind the one `false`. Forest-Ruth coefficients exact; measured convergence 2.00 and 4.00. |
| solenoid | F17's real-arithmetic transcription verified bitwise against the complex predecessor across **200,175 comparisons, 0 mismatches**, so the PTC validation is preserved rather than re-established. `curved=false ≡ h=0` exactly, not to a tolerance. |
| longitudinal conventions | all eight conversion methods re-derived from `Δt = ℓ/(βc) − s/(β₀c)`; 12 ordered pairs × 3 energies × 2 arc positions at ≤4.8e-16. |
| Lorentz boost | independent transcription of the published Hirata map reproduces the code to **≤5.42e-20**; `det J(fwd)·det J(rev) − 1 ≤ 4.44e-16`. |
| chromaticity kick | matches an independent Hamiltonian-flow derivation **bit for bit** (time-1 flow of `h = 2πξ p_z J`); action preserved exactly (0.0). |
| CPU↔CUDA PIC | 48-cell option matrix at ≤1.6e-16 relative, plus a full **64/64** sub-route matrix at 8.99e-17. |
| small-argument helpers | vs 400-bit BigFloat: `_curv_sin`, `_curv_vers`, `_atan_over`, `_sol_log_over_h` all ≤9.4e-17 across h = 1e-1…0. Both recorded 1/x cancellations measurably gone (`_wedge` flat in `b1` to 1e-14; `_lattice_bend` linear to the floor). |

**Broken links found this pass:** the RF cavity note still asserts in §4/§9 the
cross-element phase identity its element now disclaims (U16-2) and its F16
correction cites the wrong section (U16-1); the `SymplecticityContract`
declaration↔coverage tripwire can see exactly **one** kind, `:solenoid`, so it
is a near-tautology (U16-9); the lattice-magnet schemas under-declare what the
compile actually reads, so the consumed⇒declared direction has no tripwire
anywhere (U9-2).

## 3. Seam map

Participants and who covered each class. Defect clustering held again: **every
§4 finding sits on a seam**, none inside a kernel.

- **CPU↔CUDA twins** (`pic_cpu`↔`pic_cuda`, `gaussian_pic`↔`_cuda`,
  `spectral`↔`_cuda`, host↔device moment reductions). Covered by U1/U2/U3
  (parity-briefed) plus the auditor's F1 reproduction. Defects on this seam:
  **F1** (per-pair trace on 1 of 6 routes); U3-1 (moments depend on launch
  grid where the CPU twin was rewritten to forbid exactly that); U3-3 (CIC
  hand-unrolled in transposed nesting — 22.5% of interpolations differ in the
  last bits); U3-4 and U6-6 (`Float32` beams: the twins pick their working
  type differently); U6-7 (slice boundaries/centres differ by up to 48,247
  ulps although membership is identical everywhere).
- **Producer↔consumer protocols** (`.lum` and moment append/restart; knob and
  spec epochs; loss-record lifecycle). Covered auditor-direct plus U5/U7/U13.
  Defects: **F2**, **F3**, U7-1/U7-2, U13-1 (epoch not bumped on a type-only
  change), U15-5 (loss record reused across beams).
- **Declared schema ↔ runtime consumer.** Covered by U5/U9/U12. Defects: U5-3,
  U5-4 (no key-completeness tripwire for the task schema), U5-5, **U9-2**.
- **Multiple walkers over one structure** (line expansion, survey, aperture
  binding, observer collection). Covered by U15, which enumerated all of them
  and ran a three-deep nested line: **13 walkers agree** — U11-1 refuted at
  HEAD, i.e. genuinely fixed. Residual: U15-6 (declaring `L` on `:line`
  re-opens the split for a user-set value), U15-2 (a misaligned line
  containing a bend is surveyed straight).
- **Element wrappers ↔ context path.** `grep "inner::"` returns exactly two
  wrappers repo-wide plus `CompositeLine`; **all three forward context**, so
  F13 is closed for every wrapper that exists. New defect on the same seam:
  U15-4 (the context-*free* path borrows one method for every op) and U15-1
  (the same loop is not device-compilable).
- **Task-type asymmetry** (a seam this pass ADDS to the map): machinery that
  exists for `TrackingTask` and simply has no counterpart on
  `StrongStrongTask`. **A-1** is the instance — apertures compile and kill in
  a strong-strong line, with no loss record, no summary, and a `loss_summary`
  that fails from deep inside. Worth a sweep: anything `Tasks.jl` does at
  `execute!` boundaries that `interface.jl` does not.

## 4. Findings

Nothing enters this section until the auditor has reproduced it. Each finding
records the reproduction command and the numbers it produced on this machine.

### F1 [Major] Per-pair luminosity trace is empty on 5 of 6 CUDA PIC routes, and the contract that consumes it is disarmed by construction

**Independently found by two units reading disjoint regions** (U1-1 over
`pic_cuda.jl` 1–2000, U2-1 over 2000–4000), then reproduced by the auditor.

`_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` is pushed to on the CPU side from the single
generic pair loop (`pic_cpu.jl:114–119`), so every CPU route populates it by
construction. On CUDA the only `push!` lives in
`_cuda_pic_wavefront_luminosity_indexed` (`pic_cuda.jl:3672–3686`), reachable
only from the fully-indexed wavefront sub-route.

Auditor reproduction (4 slices ⇒ 16 pairs), `probe_sink.jl`:

| route | scalar luminosity | sink records |
|---|---|---|
| CPU sequential | 5.756043461949609e14 | **16** |
| CPU wavefront | 5.756043461949609e14 | **16** |
| CUDA sequential `cuda_async=false` | 5.756043461949634e14 | **0** |
| CUDA sequential `cuda_async=true` | 5.756043461949622e14 | **0** |
| CUDA wavefront, full indexed (default) | 5.756043461949619e14 | **16** |
| CUDA wavefront `cuda_indexed_wavefront=false` | 5.756043461949624e14 | **0** |
| CUDA wavefront `cuda_wavefront_fft=false` | 5.756043461949621e14 | **0** |
| CUDA wavefront `cuda_async=false` | 5.756043461949621e14 | **0** |

The **scalar luminosity is correct on every route** (agreement to ~1e-15), so
this is an observability and contract-coverage defect, not a physics one — which
is precisely why nothing caught it.

Two aggravating factors, both from U2-1:

- `pic_timing_detail = true` — a *pure diagnostic* — forces `use_async=false`
  and hence `use_indexed_wavefront=false`, so enabling one diagnostic silently
  deletes a different diagnostic's entire output, on the default route. This is
  the F11 family (a diagnostic changing execution) in observability form; the
  F11 fix throws for `interaction_grid=:node` under the same cascade but leaves
  default `:slice_pair` to lose its trace in silence.
- `StrongStrongPICBackendConsistencyContract` gates the whole per-pair
  comparison on `batch_mode == :wavefront` (`Contracts.jl:867–876`), so under
  `:sequential` it reports `records_compared = 0` and `passed = true` **having
  compared nothing** — a contract that passes by comparing an empty set. The
  suite's only invocation (`test/runtests.jl:3786`) uses default flags, so the
  per-pair check has never covered any route but the indexed one.

This is Measured Lesson 1 ("a correct check that never executes") and Lesson 8
("loud beats silent") in one defect, on the CPU↔CUDA twin seam.

### F2 [Major] An `execute!` that fails during observer preparation destroys the luminosity history it never wrote to

`interface.jl:2015–2025`. Found by U5-1, reproduced by the auditor with
`u5_p3_ordering.jl`.

The prior audit's U4-4 fix moved `_prepare_strong_strong_luminosity_file!`
*before* `prepare_observers!` to stop a `.lum` refusal leaving a truncated
moment table. That reversed the truncation window rather than closing it: both
preparers commit destructively before either has validated, so
`_moment_append_continue!` (`BeamObservers.jl:1265–1271`) refusing a mismatched
moment selection now happens *after* the `.lum` has already been rewritten.

Measured:

- **replace mode** (the default): 3 rows of real luminosity history before →
  `execute!` throws `ArgumentError` → **0 rows after**. The entire history is
  gone, destroyed by a run that tracked nothing.
- **append mode**, `start_turn=2`: 5 rows before → throws → **2 rows after**.

No ordering closes this; it needs a validate-all-then-commit-all split. The
suite pins only the one direction (`runtests.jl:3983–3987`), which is why the
reversal read as a fix.

### F3 [Moderate] The luminosity schedule is evaluated twice per collision per turn, so a stateful predicate makes every written row `NaN`

`interface.jl:2217–2218`. Found by U5-2, reproduced by the auditor with
`u5_p4_schedule.jl`.

The file-writing gate calls `_strong_strong_luminosity_evaluated(solver, ctx)`
→ `should_run`; the collide path then calls `_pic_compute_luminosity(solver,
ctx)` which calls `should_run` again. Nothing shares the first answer with the
second. `should_run(::PredicateSchedule, ctx)` is `Bool(schedule.predicate(ctx))`
— an arbitrary public user function.

Measured, 4 turns / 1 collision: **8 predicate invocations** where one per turn
would be 4; and every written row is `NaN`:

```
turn	ip
0	NaN
1	NaN
2	NaN
3	NaN
```

The gate says "evaluated" while the solver returns `NaN`, producing exactly the
confusion `interface.jl:1130–1137` says must not happen — `NaN` is reserved
there for "evaluated and numerically failed".

### A-1 [Moderate] A `StrongStrongTask` has no loss accounting at all, and `loss_summary` on one fails from deep inside

**Auditor-direct** (seam pass U27), not from any unit — it is a disagreement
*between* files, which a per-file read structurally cannot see.

`Tasks.jl:614` binds apertures to a per-beam `LossRecord` and `execute!`
reconciles two independent loss counts, warning whenever `unattributed != 0`.
`_bind_apertures` has exactly one call site in the repository, and the
strong-strong path is not it: `_strong_strong_runtime_blocks`
(`interface.jl:2397–2415`) builds blocks with no record, and
`interface.jl` mentions neither `aperture` nor `loss_record` anywhere.

Measured (`seam_aperture_ss.jl`, `seam_aperture_ss2.jl`), same aperture, same
beam, 4,000 particles:

| | strong-strong | tracking (control) |
|---|---|---|
| particles killed | 3,793 | 3,399 |
| automatic summary on `execute!` | **none** | `loss summary: 3399 of 4000 particles lost (601 live)` / `tight_collimator 3399` |
| per-collimator attribution | **none** — `aperture_names`: no method | yes |
| `loss_summary(rep, task)` | `MethodError` for `loss_counts(::StrongStrongTask)` | works |
| total available | `count_dead(rep)` = 3793 | yes |

Only the *total* is recoverable. `loss_summary(rep, ::StrongStrongTask)`
dispatches through the `::Any` fallback at `aperture.jl:593` — treating the task
as a loss record — and then fails on an inner `loss_counts` `MethodError`
rather than saying the operation is unsupported.

This matters specifically because `allow_lost_particles`' own docstring
prescribes the cross-check "Compare `count_dead` against the losses your lattice
can account for; a gap means the old meaning still applies somewhere" — and for
a `StrongStrongTask` the lattice-accountable losses are exactly what is
unavailable, so the documented procedure cannot be performed. No test in the
suite places an aperture in a strong-strong line (0 testsets mention both).

Scope note: the *physics* is correct and separately verified — a dead particle
joins no slice under any of the five slicing methods and reaches no grid cell,
"verified bit-exact against a beam that omits it"
(`docs/theory/aperture_and_particle_loss.md:380–385`). The defect is
observability, not the beam-beam result.

## 5. Corrections to this audit's own analysis

Recorded beside the original claim, never over it, per the Absolute Rules.

### C-1 — The auditor's "strong-strong kills silently" hypothesis was wrong, and measurement said so

**Original claim** (auditor, seam pass U27): since `interface.jl` never binds a
`LossRecord` and `Aperture{Nothing}` "kills without recording", a strong-strong
line containing an aperture would kill particles silently — the "loud beats
silent" class.

**Refuted by measurement.** The first probe never reached a silent kill: the
solver threw before any mutation, with a diagnostic naming the collision, the
turn, the count (`3399 of 4000`), the first offending index, the *mechanism*
("they previously poisoned the whole CUDA charge grid through the atomic
deposit, or threw an unlocated InexactError on CPU"), and the supported remedy
(`allow_lost_particles`). That is the fail-fast rule working exactly as
designed. A second probe error — my own beams had `E0 = 0.0` — was likewise
caught precisely rather than absorbed.

What survived is narrower and different in kind: not a silent kill, but a
**missing accounting path** once the user has explicitly opted into
`allow_lost_particles` (finding A-1). The original framing would have filed a
Major against correct code.

## 6. Test, contract, validation, and execution log

*Pending.*

## 7. Open queue — dispositioned, priced, with reproductions

**Read this header before using the queue.** Every row below is an
**agent-reported LEAD with a reproduction, not an auditor-verified finding**.
The series' measured survival rate for agent leads is ~60%, in four distinct
miss shapes (right as stated; right with the *reason* wrong, and the reason
determines the fix; wrong outright; narrower than the truth). Only the items
in §4 have been reproduced by the auditor. Treat a row as "worth one
reproduction", not as a defect.

The `file:line` in each row rots; the Repro line in the archived unit report
is the durable identity. Full mechanisms, measurements and repro commands are
in `comprehensive_audit_2026_08_05_b_unit_reports/U<k>_report.md`.

### Major-severity leads (reproduce these first)

| id | region | claim, with the number that makes it checkable |
|---|---|---|
| U6-1 | `pic_cpu.jl:608` | Under `interaction_grid = :node` and `:source_slice` the dropped-charge tripwire is **structurally unreachable**: both counting calls sit inside `if ge !== :extrema`, and `_validate_pic_solver` *rejects* any non-`:extrema` extent for exactly those two modes. Measured on an EIC-like flat pair: 2 of 1,800,000 source deposits outside the turn-start mesh, 2.0 particle-charges lost, `workspace.dropped[] == 0`, no warning. Negative control in the same run: 0 outside a mesh rebuilt at collision — so the escape is intra-turn motion, the R9 mechanism exactly. Synthetic sweep reaches 47% of deposits once the excursion exceeds the 1.5-cell margin. |
| U6-2 | `pic_cpu.jl:1338`, constants at `interface.jl:568` | **Performance regression from the thread-invariance fix.** With the worker-count gate removed, `length(x) >= 4096` alone routes to the fixed 16-chunk deposit, whose cost has a grid-sized, n-independent term. Measured: grid 128, n=4096 → serial 0.048 ms vs threaded 1.599 ms (**33×** slower), at 1 *and* 8 workers. End-to-end, a **5% increase in particle count** buys 1.078 → 1.614 s/turn (**1.50×**) at grid 64 and 4.252 → 6.463 s/turn at grid 128. Break-even is ~40k/slice at grid 32 and >200k at grid 128; the threshold is 4,096 everywhere. |
| U13-2 | `Tasks.jl:391` | An exception raised inside `execute!`'s failure-path loss report **replaces the original tracking exception**; `rethrow()` is never reached. Measured: real error `"REAL_TRACKING_ERROR"` surfaces as `HDF5.API.H5Error`, `occursin("REAL_TRACKING_ERROR", msg) == false`. |
| U13-3 | `Tasks.jl:519` | Same shape via `finally`: an exception from `finalize_observers!` replaces the in-flight tracking exception, so a broken observer finalizer hides the physics error that stopped the run. Measured: `FINALIZER_ERROR` surfaces, the real error does not. |
| U14-1 | `phase6d_track.jl:304` | The contextless CUDA `track!` builds a fresh `TrackingContext()` **inside** its own turn loop, so every turn of a stochastic element draws at turn 0. Measured at 16 turns: `var(x) = 0.502832` vs correct `0.031669` (**15.73×**), `max|x₁₆ − 16·x₁| = 8.88e-16`, `corr(x₁₆, x₁) = 1.0000000000`. The F14/U7-2 shape on the turn axis; the CPU sibling does not have it and no shipped test exercises it. |
| U14-2 | `counter_rng.jl` / `Beam.jl` | Explicit `rng_id`s never advance the atomic auto counter, and beams, radiation and BPMs share one `(seed, turn, rng_id, particle, component)` lattice. Measured: `Beam(...; rng_id=1)` plus an auto-assigned `LumpedRadSpec` in a fresh session → auto id = 1, draws **bitwise identical for all 20,000 particles**, corr = 1.000000. `_warn_duplicate_radiation_streams` sees only radiation-vs-radiation. Shipped configs are disjoint by hand, not by construction. |
| U15-1 | `beam_line.jl:568` | A kept-whole line (girder/cryostat) — this file's flagship feature — **fails to compile for CUDA** whenever its member runtimes are not all one concrete type, i.e. every realistic assembly. Both `CompositeLine` call methods walk `elem.ops` with a runtime `for`, which lowers to `ijl_get_nth_field_checked` and has no device implementation. Measured: `InvalidIRError`; a homogeneous ops tuple runs and is bit-identical to CPU (0.0). |

### Moderate and Low leads, by region

Recorded in full in the unit reports; the headline of each:

- **U1** (`pic_cuda.jl` 1–2000): workspace cache key still omits `interaction_grid` where the CPU key carries it (inert today); one hardcoded `threads = 256` bypassing `CUDAPICLaunchConfig` and its receipts — the only such launch in 6,009 lines; a dead `longitudinal_kick` parameter and an unreachable kernel left by the F10 fix; CUDA per-pair records stamped `turn = -1`.
- **U2** (2000–4000): node-indexed wavefront solves the two longitudinal planes even when `longitudinal_kick=false` (measured 4.8% recoverable where sibling routes recover ~37%).
- **U5** (`interface.jl`): `luminosity_append` declares a consumer whose receipt does not carry it; the task schema has **no key-completeness tripwire** (6 of 8 public keywords have no schema entry); `grid_extent_sigma` reported `:resolved` where it is provably inert; a differently-configured user solver silently accepted and discarded; mixed-schedule dropped-row warning capped at `maxlog=4` while the drops continue; partial `.lum` truncation warns only when *every* row goes.
- **U7** (`BeamObservers.jl`): **JLD2 flush is `delete!`-then-write** — a deterministic mid-window death leaves a readable file with no `/data` key, the entire history gone (binary and HDF5 survive the same test); JLD2 file size quadratic (2,000 turns → 961 MB / 19.5 s vs binary 544 KB / 0.043 s); `MomentOutputFile` dispatches on *extension*, fabricating rows with duplicate turn labels from an HDF5 written to `m.dat`; `_discard_replayed_snapshots!` truncates to preserve foreign records then reopens `"w"` and destroys them; `BPMObserver` copies all six CUDA arrays to host per reading (76.8 ms vs 0.456 ms, **168×**) against a docstring premising hundreds of BPMs per turn.
- **U9** (lattice magnets): the per-kind schemas **under-declare what `_lattice_magnet` reads** (21 keys for drift, 15 for quad/sext/oct/multipole, 2 for sbend), so the new unknown-parameter warning tells users a key "is NOT being tracked" about keys that change tracking by up to **5.79e-2**. `ElementParameterEffectivenessContract` checks declared⇒consumed; the reverse has no tripwire. Also `Linear6D`'s symplecticity validator orders on `T` rather than `real(T)` (Complex dies), and `nst` ParamMeta declares default 1 where the curved compile default is 16.
- **U13** (knobs): `@knob p::T` whose converted value is `isequal` to the old one changes the declared type without bumping the epoch, so live tasks keep compiling at the old numeric type; `knob_expression(string(e)) == e` fails for 6 of 50 nestings, 4 of them turning finite values into `Inf`; a knob-valued `:L` makes every `execute!` with a `loss_log` throw *after* tracking completes.
- **U14** (`Beam`/math/track): `_delta_from_pt`'s `sqrt` throws `DomainError` for a sub-rest-energy particle, unmaskable by `allow_lost_particles`, and on CUDA kills the whole launch.
- **U15** (elements): a misaligned line containing a bend is surveyed as **straight**, so its exit patch is wrong at first order (measured exactly `dx·θ`, 1.9864e-4 at θ=0.198); `reverse` now **aliases** placements, so an override on the reversed line moves the source; the context-free call path borrows the *first* op's tracking method for every op, so a mixed-method assembly throws where the context path tracks fine; the task loss record is reused for any rep of the same size and backend, giving `unattributed = -1` and a false warning.
- **U16** (small elements/examples): `_patch_reference_length` returns the projected displacement while the on-axis particle traverses the unprojected one, so a patch with both `dz` and a transverse rotation breaks its own documented exact-inverse identity by `dz·(cos θ − 1)` (measured −1.943472629195586e-5 vs predicted −1.9434726291969184e-5); patch and misalignment apply the shared rotation matrix in **opposite senses**; theory note §4/§9 still assert the phase identity the element now disclaims.
- **U17/U19** (test suite): a `_curv_vers` seam bound sits **1.7× from red** on sub-ulp `cos` rounding, and a failure there drops ~7,150 later lines; the only `else`-less CUDA gate in its region reports `Total 0` on a GPU-free host — neither pass nor skip; the lost-particle charge-semantics pin covers 2 of 5 solver configurations, omitting the two a reader would most likely guess wrong; the Spectral arm of the corpse testset runs with 21–100% of source charge clipped and **exhausts the process-wide `maxlog=8` budget of the R9 tripwire**, silencing it for the rest of the run.

### Inherited items, dispositioned

- **F16 RF velocity slip** — remains open by design. **Independently reproduced this pass** (U16, from a from-scratch ring and a ForwardDiff one-turn eigenvalue, no FFT): `map / analytic(true η) = 1.8402652626158156` against the recorded 1.84×, and the wrong-transition-side case reproduces at `α_c = 0.05 < 1/γ₀²`. Documented at both ends; three documentation gaps filed (U16-1/2/3). Nothing silently relies on the wrong behaviour, but the one check that would catch it is blind by construction — its toy ring uses a free hand-chosen `M[5,6]`, never derived from `α_c` and `γ₀`.
- **Bmad reference cases** — still blocked on an external tool. Code↔note internal consistency verified clean this pass (`max|W_bmad − R_y R_x R_z| = 0.0`).
- **Metadata validator remainder** — U9-2 gives it a sharp new instance (consumed⇒declared has no tripwire anywhere).

## 8. Change log

| finding | file | change |
|---|---|---|
| F2 | `src/tasks/strongstrong/interface.jl` | `_prepare_strong_strong_luminosity_file!` split into `_plan_strong_strong_luminosity_file` (validate, no writes) and `_commit_strong_strong_luminosity_file!`, with `prepare_observers!` between them; warnings moved to the committer so they cannot describe a state that does not exist; residual window documented |
| F4 | `src/elements/solenoid.jl` | `_SOL_MIDPOINT_CONTRACTION` added; `Solenoid` now throws at contraction factor ≥ 1 with a concrete `nst` and warns above 0.1; construction-time only, kernel unchanged |
| — | `docs/history/…_b.md`, `…_b_unit_reports/` | this report, the fingerprint harness and baseline, every unit report, every probe script |
| — | `docs/README.md` | index entry |
