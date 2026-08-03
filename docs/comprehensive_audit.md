# Comprehensive Scientific Software Audit, Verification, Validation, and Performance Review

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

"Never claim a file was reviewed unless it was actually inspected" is only
enforceable against a record. The ledger is that record.

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

Replace circular tests with independent validation whenever practical.

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
