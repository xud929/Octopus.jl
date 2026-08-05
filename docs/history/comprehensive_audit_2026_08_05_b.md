# Comprehensive Audit — 2026-08-05_b (second full re-read, same day)

**Status: IN PROGRESS.** This file is written incrementally, as the protocol
requires ("Checkpoint to disk continuously, not at the end"). Sections below
are filled as they are established; anything not yet established says so.

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

*Pending — built once unit reports land.*

## 3. Seam map

*Pending — auditor passes (U27).*

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

*Pending.*

## 8. Change log

*Pending.*
