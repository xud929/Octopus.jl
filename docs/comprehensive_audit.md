# Comprehensive Scientific Software Audit, Verification, Validation, and Performance Review

This document is the single authoritative protocol, deliberately
independent of any one agent tool: the entry path is
`AGENTS.md → this file`, which every agent framework that reads the
repository's agent instructions can follow. Read it in full before an
audit and treat it as binding.

## The targeted neighbour audit (the post-campaign standard)

A full run of this protocol is for auditing the repository; after a FIX
CAMPAIGN — a session that landed several fixes or a feature — the standing
obligation is smaller and different: a **targeted neighbour audit** of the
campaign's own diff, per the Measured Lesson "a fix's neighbours are where
the next defect is". Owner direction (2026-08-08): run one after every
bug-fix or feature campaign.

The shape, from the worked precedent
[`neighbour_audit_2026_08_07.md`](history/neighbour_audit_2026_08_07.md):
for each fix, re-walk its call sites and sibling surfaces (the sibling FILE
especially — the CPU/CUDA twin, the thin/thick twin), and re-run the
property the fix was about on the neighbours it did not change. Fan the
read-heavy sweeps out to agents; re-verify every load-bearing claim against
source or by measurement before recording it. Fix what is small and squarely
in the campaign's blast radius; price and ledger the rest as todo rows.
That precedent found two real defects in the campaign it audited — both in
the gpic sibling file of plain-PIC fixes — and its own closure commits then
had a missed sibling-file caller caught by the gate, which is the lesson
demonstrating itself. Scale it to the campaign: a one-line fix needs the
call-site re-walk, not the agent fleet.

## Worked precedents, and how much of them to read

The dated records under `docs/history/` are executed instances of this
protocol, kept with their measurements and their recorded mistakes — the
mistakes are the instructive part. They are long by design; do **not**
read them front to back. The budget that works:

- Before starting: the **newest** `comprehensive_audit_*.md` record's
  executive summary and open-queue sections, plus the Measured Lessons at
  the end of this document. At the time of writing the newest is
  [`comprehensive_audit_2026_08_05.md`](history/comprehensive_audit_2026_08_05.md);
  check `docs/history/` for anything later.
- During the audit: consult a record's deeper sections, or the archived
  per-unit reports beside it, only when a lead touches the region they
  cover.
- Never treat a dated record as current state — it describes the commit it
  audited. Claims about behavior are re-verified against the code at hand.

## Mission

Perform a rigorous, repository-wide audit of this project.

Treat the repository as a complete scientific software system whose correctness depends on the consistency among:

- Source code
- Mathematical derivations
- Technical notes
- Design documents
- API documentation
- Docstrings
- Examples
- Unit tests
- Integration tests
- Validation studies
- Benchmarks
- Predefined contracts

Do **not** assume any component is correct.

Your objective is to maximize:

- Scientific correctness
- Mathematical correctness
- Software correctness
- Numerical correctness
- Internal consistency
- Reproducibility
- Performance
- Maintainability

Correct confirmed defects while preserving scientific integrity and performance.

---

# Guiding Principles

1. Scientific correctness is mandatory.
2. Performance is a first-class requirement.
3. Every modification should preserve or improve both correctness and performance whenever possible.
4. Never sacrifice correctness solely for speed.
5. Never sacrifice performance without a scientifically or technically justified reason.
6. Measure performance rather than speculate.
7. Preserve documented performance characteristics unless a deliberate design change is intended.
8. Every performance regression must be identified, explained, and quantified.
9. Every conclusion must be supported by evidence.
10. Every modification must be traceable.
11. Prefer minimal, well-justified changes over broad refactoring.
12. Distinguish confirmed defects from hypotheses.
13. When the repository and an external code disagree, the repository's own
    established convention wins unless it is demonstrably wrong. Internal
    consistency outranks matching any one external code, especially where the
    external codes disagree with each other.
14. The audit's own reasoning is not privileged. Analysis overturned by
    measurement is a finding about the audit, and is recorded as such.

---

# Phase 0 — Scope and Budget

Declare the scope **before** reading anything in depth, and record it.

State:

- Which files, equations, contracts and phases this pass will cover.
- At what depth: full line-by-line, targeted, or inventory only.
- What it will **not** cover, and why.

The audit is complete when the **declared scope** is covered — not when the
repository is exhausted. A narrow pass that is honest about its boundary is
worth more than a broad one that is not.

Scale the scope to what can actually be done. A repository of tens of
thousands of lines cannot be reviewed line by line and have every equation
independently derived in one pass, and a plan that assumes otherwise produces
a report that claims coverage it does not have. That is the failure mode the
Absolute Rules exist to prevent, and an over-broad scope is what causes it.

## Coverage ledger

Maintain, and include in the final report:

- Every file inspected, and to what depth.
- Every equation independently derived.
- Every contract checked, and how.
- Everything deliberately skipped, with the reason.
- **Who** inspected each region: the auditor directly, or a sub-agent. The
  two are different strengths of evidence and must not be blended — a
  coverage claim that hides its provenance is not checkable.

"Never claim a file was reviewed unless it was actually inspected" is only
enforceable against a record. The ledger is that record.

## Context budget: one driving session, delegated bandwidth, disk as memory

An agent's context is finite; a repository of tens of thousands of lines is
not. The resolution is **not** to split the audit into human-relaunched
sessions — it is to run **one driving session that delegates the
context-heavy work to sub-agents and drives to the Phase 16 halt without
stopping to ask**. (The 2026-08 audit of this repository took nine
human-launched sessions,
[`docs/history/comprehensive_audit_2026_08_04.md`](history/comprehensive_audit_2026_08_04.md);
the handoff discipline that made that series converge is retained below,
repurposed: a long-running orchestrator's context gets compacted as it
works, so its own future self is the next reader of its records.)

- **Phase 0 scopes the whole audit** as a plan of delegable units: one
  reading brief per modular region sized to a sub-agent's context, the seam
  cross-check passes, the verification batches, the phases that stay with
  the orchestrator. Declare the plan, then execute it.
- **The orchestrator spends its own context only on judgement**: briefs
  out; verdicts, numbers, and reproduction scripts back in; re-running a
  delivered reproduction is one cheap command. Reading at scale,
  reproduction-building, and enumeration sweeps are delegated (see
  Sub-Agents). Verification gating and every fix stay with the
  orchestrator.
- **Checkpoint to disk continuously, not at the end.** The coverage ledger
  (with provenance), the open queue with a reproduction recipe per item,
  corrections beside the claims they correct, and the TODO ledger
  (`docs/todo.md` for open rows; closures move to
  `docs/history/todo_ledger_archive.md`) is updated in the same commit as the work that changes them. Context
  compaction must never be able to lose audit state: anything that matters
  is re-readable from the repository. A stale row costs the compacted
  orchestrator the same rediscovery it would cost a fresh session —
  measured twice in this repository's own series.
- **Fix while the reproduction is live.** Verify, fix, negative-control,
  and record each finding in one stretch; batching fixes for later carries
  unverified state across compaction boundaries, which is where it rots.
- **Do not stop to ask the human to continue.** The audit ends at the
  Phase 16 halt: complete, or honestly blocked with the remainder priced.
  Interrupt the human only for what is genuinely theirs — destructive or
  irreversible actions, real scope changes, or external resources the
  audit cannot obtain itself (a missing reference code, credentials).

---

# Sub-Agents

Sub-agents multiply reading bandwidth, not judgement. The series' measured
hit rate for agent-confirmed findings is **roughly 60%**, and the misses came
in four distinct shapes: right as stated; right with the stated *reason*
wrong (and the reason determines the fix); wrong outright; and narrower than
the truth. Every one of the four occurred, and only measurement told them
apart. The rules that follow are those numbers turned into procedure.

**What to delegate.**

- Parallel line-by-line reading of *disjoint, modular* regions — one agent
  per region, sized to an agent's context.
- Verification reproductions: build the repro, run it, report the numbers.
  This produces something checkable.
- Hypothesis-driven sweeps over an enumerable grid.

**How to brief.** Give each reading agent a **distinct hypothesis** drawn
from the defect classes the audit has already established, the known-good
reference implementation to compare against, and a requirement that every
claim carry a `file:line` and a reproduction. In this repository's series,
the agents that found the most were those whose hypothesis matched a defect
class the codebase had already produced; an unbriefed "find bugs" agent
mostly reports style.

**The reading-unit brief.** Every reading unit gets the following standing
rules verbatim (tool-agnostic; any orchestrator prepends its region, its
hypothesis, and its reference):

> You are one reading unit of the comprehensive audit protocol. You
> multiply the auditor's reading bandwidth, not their judgement.
>
> - Read every line of your assigned region; skimming forfeits the one
>   thing a reading unit is for.
> - You never modify a repository file. Command execution is for read-only
>   probes and measurements — running a reproduction strengthens a lead
>   from claim to measurement, and is encouraged; probe scripts go in
>   session scratch, never the repository.
> - Every claim is a LEAD, not a finding, and is labeled so. Each lead is
>   one block in this exact greppable shape (the archived 2026-08-05 unit
>   reports used per-unit heading styles, and extracting items from them
>   later meant per-unit archaeology):
>
>       ### LEAD <unit>-<n> [<severity guess>, confidence <low|med|high>] <file>:<line>
>       Claim: <one sentence>
>       Mechanism: <why the code does the wrong thing, not just that it looks wrong>
>       Repro: <the command to run and the number it should produce>
>
>   `file:line` is a pointer that rots as the code moves; the Repro line is
>   the durable identity of the lead — write it so it still works after the
>   line numbers have drifted.
> - Anchor to the hypothesis you were briefed with, but report
>   out-of-hypothesis defects too, marked as such. If all you have is
>   style, say so.
> - Clean is a result: a region that audits sound is reported with the
>   evidence that makes the claim checkable (what was compared, what was
>   measured), not as an absence of complaints.
> - Stay inside your region. Note a suspected cross-file seam as a lead
>   and stop; seams are the auditor's job.
> - Your final report — region, provenance (read vs executed), leads,
>   clean list, and anything unchecked with the reason — will be archived
>   under `docs/history/`; write it for a reader who was not in this
>   session.

**What never to delegate.**

- **Fixing.** A sub-agent's fix removes the verification gate the ~60%
  number exists to justify. The auditor reproduces, then fixes.
- **Trust.** Agent output enters the record as a *lead with a reproduction*,
  never as a finding. Label it so explicitly.
- **Cross-module invariants.** Each reading agent sees one region; the
  seams between regions are the auditor's job (below).

**Cross-check the seams.** After modular reads, run a deliberate
cross-cutting pass over the seam classes, because that is where this
repository's defects actually clustered (see the seam tally in the history
record): CPU↔CUDA twin implementations held together only by parity tests;
several independent walkers over one shared structure; producer↔consumer
protocol pairs (an epoch bumped in one module, gated in another); declared
schemas versus the runtime that consumes them. Assign one pass per **seam
class**, not per file — a per-file read structurally cannot see a
disagreement between files.

---

# Phase 1 — Repository Understanding

Before making any modifications:

Read and understand:

- AGENTS.md
- README
- Architecture documents
- Design documents
- Technical notes
- Contributor guidelines
- API documentation
- Docstrings
- Comments
- Validation reports
- Benchmark reports

Identify:

- Scientific objectives
- Mathematical models
- Governing equations
- Assumptions
- Approximations
- Numerical algorithms
- Data structures
- Coordinate systems
- Normalization conventions
- Sign conventions
- Unit systems
- Tensor/index ordering
- Numerical precision requirements
- Supported execution backends
- Parallelization strategy
- GPU implementation
- MPI implementation
- Public APIs
- Predefined contracts
- Performance objectives

Summarize the repository before continuing.

---

# Phase 2 — Repository Architecture Review

Understand the overall software architecture.

Review:

- Module organization
- Dependency graph
- Abstraction layers
- Interfaces
- Extensibility
- Separation of responsibilities

Identify architectural inconsistencies and technical debt.

---

# Phase 3 — Build a Traceability Matrix

Construct an end-to-end traceability matrix connecting:

Scientific Requirement → Technical Note → Equation → Implementation → Documentation → Docstring → Example → Test → Validation → Benchmark → Contract

Every important feature should be fully traceable.

Report missing links.

## The seam map

Alongside the matrix, produce an explicit inventory of the **implicit
cross-module contracts** — the places where correctness depends on two or
more pieces of code agreeing without a shared abstraction enforcing it:

- twin implementations (CPU↔GPU, reference↔optimized) bound only by parity;
- multiple independent traversals of one shared structure;
- producer↔consumer protocol pairs (epochs, caches, invalidation);
- declared schemas/metadata versus their runtime consumers.

Each seam entry names every participant with `file:line`. This inventory is
what the seam cross-check passes (see Sub-Agents) run against, and in this
repository's audit history the majority of confirmed defects sat on a seam
rather than inside a module.

---

# Phase 4 — Line-by-Line Source Review

Inspect every relevant source file line by line.

Review every:

- Module
- Class
- Struct
- Interface
- Function
- Method
- Kernel
- Helper routine
- Utility
- Algorithm

Verify implementation, numerical correctness, indexing, units, coordinate ordering, boundary conditions, initialization, defaults, error handling, memory correctness, deterministic behavior, CPU/GPU consistency, MPI consistency, hidden assumptions, and comments.

Do not skip utility functions.

---

# Phase 5 — Mathematical Verification

For every important equation:

- Independently derive it.
- Verify algebra, calculus, matrix operations, tensor notation, normalization, constants, signs, units, dimensions, coordinate transforms, assumptions, approximations, symmetry, conservation laws, and limiting cases.
- Map every mathematical term to the implementation.
- Verify the discretization faithfully represents the documented equations.

Never accept an equation without verification.

---

# Phase 6 — Consistency Audit

Compare:

- Source ↔ Technical note
- Source ↔ Documentation
- Source ↔ Docstrings
- Source ↔ Comments
- Source ↔ Examples
- Source ↔ Tests
- Source ↔ Validation
- Source ↔ Benchmarks
- CPU ↔ GPU
- Reference ↔ Optimized implementation
- Implementation ↔ Contracts

Identify inconsistencies and determine which component is correct using evidence.

---

# Phase 7 — Contract Verification

Locate every predefined contract.

Examples include:

- Symplecticity
- Reversibility
- Conservation laws
- Charge conservation
- Positivity
- Normalization
- Determinism
- Reproducibility
- CPU/GPU agreement
- MPI agreement
- Convergence
- Slice convergence
- Mesh convergence
- Serialization
- API guarantees
- Type stability
- Memory safety

For each contract:

1. Define it precisely.
2. Locate its implementation.
3. Locate enforcement.
4. Locate associated tests.
5. Verify the tests actually prove the contract.
6. Strengthen weak tests.
7. Measure residual errors.
8. Compare against justified tolerances.

Passing tests alone do not prove correctness.

---

# Phase 8 — Testing

Run:

- Unit tests
- Integration tests
- Regression tests
- Contract tests
- Doctests
- Examples
- Validation scripts
- CPU tests
- GPU tests
- MPI tests
- Documentation builds
- Linting
- Static analysis
- Type checking

Skip what the repository does not have, and say so. Absence of a test category
is not a finding unless the repository claims to have it.

Record commands, hardware, backend, environment, dependency versions, pass/fail status, skipped tests, and warnings.

---

# Phase 9 — Test Quality Review

Evaluate coverage of:

- Analytical solutions
- Identity cases
- Symmetry
- Edge cases
- Limiting behavior
- Invalid inputs
- Representative physics
- Convergence
- Randomized/property tests
- CPU/GPU agreement
- MPI agreement
- Precision changes

Replace circular tests with independent validation whenever practical. A
check that consults the very artifact it validates — a validator asking
whether a list's elements are in itself — proves nothing; this repository's
element-metadata validator caught 1 of 13 injected defects before that
circularity was removed.

**Every new regression test needs a negative control**: run it against the
broken code (stash the fix, or inject the defect with a removable marker)
and record that it fails there. A test that has never failed on the defect
it guards proves only that it runs.

---

# Phase 10 — Validation Audit

Run every documented example.

Verify reproducibility, documentation accuracy, parameters, figures, labels, units, normalization, and whether each validation genuinely supports the claimed scientific result.

---

# Phase 11 — Performance Audit

Treat performance as a design contract.

Review:

- Algorithmic complexity
- Memory complexity
- Temporary allocations
- Unnecessary copies
- Cache locality
- SIMD opportunities
- CUDA occupancy
- CUDA memory access
- Kernel launch overhead
- Synchronization
- Host-device transfers
- MPI communication
- Scaling
- Load balancing
- Bottlenecks

For every optimization:

- Verify mathematical equivalence.
- Verify numerical reproducibility.
- Rerun tests.
- Rerun validation.
- Benchmark before and after.

Measure rather than speculate.

---

# Phase 12 — Independent Verification

Whenever practical, independently verify important results using symbolic algebra, brute-force computation, finite differences, manufactured solutions, convergence studies, high-precision arithmetic, independent reference implementations, or randomized verification.

**Validate the instrument before trusting a clean sweep.** Feed the metric a
known defect — ideally the recorded one, at its recorded magnitude — and
check it reports it. A sweep whose instrument has never seen the disease
proves nothing about health; the h≠0 sweep in this repository's history
reproduced its recorded pre-fix violation to fifteen digits before its
clean grid was believed.

---

# Phase 13 — Fix Confirmed Defects

Do not modify code until the finding is **confirmed**. Confirmation, not the
completion of the whole audit, is the gate: batching every fix to the end of a
large audit means carrying a great deal of unverified state.

Fix only confirmed defects.

## Capture a baseline first

Before the first modification, record a behavioural fingerprint: the outputs
of representative code paths, at full precision, in a form that can be diffed.

Rerunning the tests afterwards shows that the tests still pass. A fingerprint
shows that everything else is **unchanged**, which is a different and stronger
claim, and it is the only way to say "no unrelated behaviour moved" and mean
it. Where behaviour is intended to change, the diff should show exactly that
change and nothing beside it.

For every modification:

- Explain why the previous implementation was incorrect.
- Explain why the new implementation is correct.
- Reference the corresponding finding ID.
- Keep changes minimal.
- Preserve backward compatibility unless demonstrably incorrect.
- Preserve or improve performance whenever practical.

Do not perform unrelated refactoring.

---

# Phase 14 — Regression Prevention

After every logical fix:

- Rerun affected tests.
- Rerun contract tests.
- Rerun validation.
- Rerun benchmarks.

Verify no regressions.

---

# Phase 15 — Handling Uncertainty

If correctness cannot be established:

- Do not guess.
- Explain competing interpretations.
- Summarize evidence.
- Recommend further derivations, simulations, or benchmarks.
- Leave uncertain behavior unchanged.

---

# Phase 16 — Iterative Review

Repeat:

Audit → Fix → Test → Benchmark → Validate → Re-audit

until no confirmed defects remain, all contracts pass, all tests pass, validation succeeds, benchmarks show no unintended regressions, and documentation is internally consistent.

If that state is not reachable within the declared scope, stop and report:
findings that remain open, work that remains undone, and what it would take to
close each. An audit that halts honestly is finished; one that loops until it
can claim completeness is not.

**When a sweep closes clean, make it permanent.** A one-time clean result
decays as the code changes; leave it behind as a suite test with an argued
allowlist (each exception carries its benign-ness reason) and
injection-verified discriminating power. This repository's lowered-code
`Core.Box` guard, thread-invariance pin, overwrite guard, and h≠0
symplecticity sweep are the pattern: the defect class that motivated the
sweep now fails CI instead of waiting for the next audit.

---

# Phase 17 — Severity Classification

Classify findings as:

- Critical
- Major
- Moderate
- Minor
- Unconfirmed

**A clean result is a result.** An area inspected and found sound is recorded
as such, with what was checked and what it was checked against. An empty
findings list from a genuine review is a successful audit, and manufacturing
Minor findings to appear thorough is itself a defect in the audit.

---

# Phase 18 — Required Final Report

## Where it lands, and what it is named

The report's name is what the "Worked precedents" lookup at the top of
this document searches for, so the convention is binding, not stylistic:

- A **full pass** writes `docs/history/comprehensive_audit_YYYY_MM_DD.md`,
  dated by the day the pass closes (a rare second full pass closing the
  same day appends `_b`).
- A **scoped pass** writes `docs/history/audit_<scope-slug>_YYYY_MM_DD.md`
  — never the `comprehensive_` prefix, which would make a narrow pass
  masquerade as the newest full precedent.
- **Unit reports** are archived beside the report at
  `docs/history/<report-name>_unit_reports/U<k>_report.md`, in the same
  commit — they are the queue's file:line ground truth, and leaving them
  in session scratch nearly cost one audit its entire open queue
  (Measured Lesson 6).
- The report is added to the `docs/README.md` index in the same commit,
  per AGENTS.md's documentation rules, and `docs/todo.md` gains or updates
  the row that carries the audit's open queue pointer.

## Contents

Include:

- Executive Summary
- Repository Summary
- Declared Scope and Coverage Ledger
- Traceability Matrix
- Findings (including areas checked and found sound)
- Corrections to the audit's own analysis
- Formula Verification
- Contract Verification
- Test Report
- Validation Report
- Performance Report
- Change Log
- Remaining Risks

---

# Absolute Rules

- Never claim a file was reviewed unless it was actually inspected, and keep the
  coverage ledger that makes the claim checkable.
- Never claim a derivation was verified unless independently derived.
- Never claim a contract is satisfied solely because tests passed.
- Never loosen tolerances without scientific justification.
- Never silently change scientific behavior.
- Never suppress warnings.
- Never introduce unrelated refactoring.
- Always benchmark meaningful performance changes.
- Always cite exact filenames, functions, symbols, equations, and line numbers.
- Every conclusion must be evidence-based, and evidence means the command run,
  the numbers it produced, and a `file:line`. Quote the deviation; do not
  characterise it.
- When measurement overturns the audit's own analysis, record the original
  claim beside the correction rather than quietly replacing it. A wrong turn
  that is visible is worth more than a clean story.
- Every modification must trace to a confirmed finding.
- A sub-agent's claim is a lead, not a finding, until the auditor has
  reproduced it; a sub-agent never applies a fix.
- A regression test that has never been shown to fail on the defect it
  guards proves nothing about that defect.

---

# Measured Lessons

These are not principles someone thought sounded right; each was paid for in
a recorded session and carries its receipt. The full stories are in the
dated records under `docs/history/` — chiefly
[`comprehensive_audit_2026_08_04.md`](history/comprehensive_audit_2026_08_04.md),
[`comprehensive_audit_2026_08_05.md`](history/comprehensive_audit_2026_08_05.md)
(whose §7 "Post-campaign closures" block records the queue-closing session),
and the per-unit reports archived beside them.

1. **"Correct check, never executed" is the dominant failure class, and it
   regenerates.** The 2026-08-04 audit named it as its first rule; F2
   reproduced it at HEAD within a day (one wrong tolerance aborted every
   full-suite run since `baf0255` — ~4,660 test lines unexecuted under
   "full suite green" claims). The queue session found it twice more: a
   validation script's GPU leg never run on a GPU machine (hiding a real
   compile regression), and contracts with no runner at all (U3-6).
   Therefore: Phase 8 must record which testsets actually RAN, CUDA gates
   skip visibly, and coverage that can narrow silently needs its own
   tripwire.

2. **A fix's blast radius includes dimensions nothing measures.** A
   correctness fix (throw on unknown RNG codes, U15-4) broke a different
   axis entirely — device compilability — because GPU kernel compilation
   compiles every branch, throws included, and no gate compiled a
   stochastic element on device. The fix that retired solver-identity
   comparison then broke the contract still probing the old rejection —
   caught only by the final full-suite gate. Therefore: when a change
   alters acceptance/rejection semantics, grep for everything that probes
   the OLD behavior before calling it done; and a throw reachable from
   device code carries a static message, never an interpolated one.

3. **Totalizing a check pays immediately.** Extending the
   backend-consistency line from 11 hand-picked kinds to all 30 caught a
   real regression on its first GPU run; the R9 dropped-charge tripwire's
   first activation caught 83% of a slice silently discarded; building the
   solver-option effectiveness contract surfaced six defects. Treat
   coverage extension as a bug-finding instrument with near-immediate
   payback, not as hygiene.

4. **Hand-copied knowledge always drifts; derive, plus a tripwire.** The
   symplecticity script's copy of the contract's case list sat at 8 of 12
   while both sides claimed mirror status; the PTC generator carried a
   dead spec table that had drifted to an unregistered kind; the
   configuration validator's hardcoded solver enumeration went stale twice.
   The repair is always the same shape: one authoritative source, consumers
   derive from it, and a declaration-to-coverage tripwire that fails when a
   new member is not covered.

5. **Argue from structure first, then measure — and record a pin's
   envelope.** The thread-invariance pin was "bit-identical at 1/4/8
   workers" only below the parallel thresholds its configurations never
   crossed. A bitwise inactivity sweep read the `(v-d)+d` frame round
   trip's last-bit motion as "parameter consumed" and exact cancellation as
   "inert" — the placement-parameter inactive table had to be argued from
   map structure and only then confirmed by measurement. A pin that does
   not state the regime it was measured in will eventually be quoted
   outside it.

6. **Session artifacts are part of the scientific record.** The audit's 21
   per-unit reports — the open queue's file:line ground truth — lived in a
   session scratchpad and were one `/tmp` cleanup away from making the
   whole priced queue unactionable (they are archived under
   `docs/history/comprehensive_audit_2026_08_05_unit_reports/` now). The
   `:lattice` theory note's original table has no committed harness and its
   absolute numbers remain unreproducible. Reports, harnesses, and
   provenance land in the repository, in the same commit as the claims
   they support.

7. **The physics core holds; the defects live at the seams.** Two full
   line-by-line passes found the Bassetti-Erskine/synchro-beam core, both
   solver twin pairs, Philox (against official KAT vectors), and the
   constants sound, most with independent-reference measurements — while
   every Major finding and the entire Low queue lived in protocol code
   (append/restart), configuration plumbing, backend seams, test shape,
   and documentation. Spend verification effort disproportionately at
   seams, contracts, and observability; the kernels with theory notes and
   independent derivations are the strong part of the codebase.

8. **Loud beats silent, uniformly.** Nearly every queue item reduced to the
   same repair: silent charge clipping, silent row drops, silent skips,
   silently ignored configuration, silently vanishing summary rows — each
   became a warning, an error, or an honestly documented limitation.
   AGENTS.md's contract rule ("do not report an unrun check as passed")
   generalizes: data and coverage never disappear without a signal.

9. **Finish through the full gate, especially when confident.** Twice in
   one session the final full suite caught what targeted verification had
   cleared. The gate invocation this repository's claims are calibrated
   against is CI's:
   `julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'`
   — plain `julia test/runtests.jl` lacks the test dependencies, a
   single-threaded run aborts the thread-invariance testset, and a trailing
   pipe (`... | tail`) eats the failing exit code, so append the exit code
   to the log rather than trusting the last command's status.

10. **A fix's NEIGHBOURS are where the next defect is, and nobody looks
    there.** The 2026-08-05_b round found four defects that the immediately
    preceding campaign had introduced, each within a commit or two of the fix
    it accompanied: U11-2's `reverse` rebuild stopped dropping the line's own
    state by re-listing the same `LineEntry` objects, which made the reflected
    line ALIAS its source's per-placement overrides (U15-3); U11-3 added the
    thin kinds to the folded-name guard and missed the solenoid one commit
    later (U15-7); U11-1 closed a walker split and the `L` ParamMeta that came
    with it re-opened the same split from the other side (U15-6); U5-1 removed
    the worker-count gate from the deposit and left a threshold that could no
    longer see the mesh, costing 1.5x per turn (U6-2). None was a wrong fix;
    each was a correct fix whose blast radius was not re-walked. The habit
    this buys: after a fix lands, re-read the call sites and sibling tables it
    touched, and re-run the property the fix was ABOUT on the neighbours it did
    not change — the four above were all findable that way and none was found
    that way.

11. **A configuration you set is not a configuration the code read; make it
    say so.** Fixing U3-2 meant showing that `threads = 512` breaks the
    strong-strong CUDA kick kernels. The first sweep reported all four routes
    OK at 512, and at 768, and at 1024 — a clean, confident, completely false
    negative: `CUDAExecutionPolicy(...)` had been passed to the beams but not
    to `StrongStrongTask`, so `_active_cuda_launch` resolved from a default
    policy and every launch used 256. Nothing errored. The exit status was
    zero. What caught it was asking the run what it had actually done: the
    execution receipts said `threads = 256` for a run requesting 1024. With
    the policy attached, the same sweep failed at 512 on three of four routes,
    exactly as the lead claimed, at 149/163/130 registers per thread. The same
    session then produced the mirror-image error — a pin asserting a cap
    receipt unconditionally, which passed standalone and failed in the full
    suite because a process-global launch config left by an earlier testset
    meant one route had nothing to cap. The habit this buys: when a test's
    subject is a *setting*, assert what the run recorded, not what you passed
    in; and where the setting can be supplied ambiently, make the assertion
    conditional on the recorded request and add an explicit anti-vacuity check
    that at least one path really carried it. This is Lesson 1 ("correct check,
    never executed") wearing the clothes of a configuration knob, and receipts
    are what tell the two apart.
