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

*Pending — no lead has been verified yet. Nothing enters this section until the
auditor has reproduced it.*

## 5. Corrections to this audit's own analysis

*Pending.*

## 6. Test, contract, validation, and execution log

*Pending.*

## 7. Open queue — dispositioned, priced, with reproductions

*Pending.*

## 8. Change log

*Pending.*
