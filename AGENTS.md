# Octopus Agent Entry Point

Octopus is an AI-native accelerator physics framework. It does not replace
MAD-X, Bmad, Elegant, Xsuite, or SciBmad; it is a platform where AI can be a
first-class developer while rigorous accelerator physics validation stays
central. The current physics focus is beam-beam collisions: strong-strong
(two live beams, sliced, with a Poisson solve per slice pair) and weak-strong
6D tracking against a rigid Gaussian beam, on CPU threads or CUDA. The root
`README.md` is the physics-level overview and owns the solver roster.

This file works the way Octopus itself does: classify the requested
operation, select the applicable method and policy, and require the
appropriate contracts before accepting the result. It carries only what
must not drift: the invariants, the source map, the routing table, the
authorization rule, the verification matrix, and the definition of done.
Procedures live in `docs/guides/`; changing facts live in generated
registries and `docs/history/`. Do not read the source tree or every linked
document by default; read what the matching rows name.

## Invariants

Each was paid for in a recorded session; the evidence is in the "Measured
Lessons" of `docs/comprehensive_audit.md` and in `docs/experiences.md`, which
also records what is deliberately not being done. Read `docs/experiences.md`
before the first edit.

- A check only counts while it executes. Skips are visible, an unrun check is
  not a pass, and "green" names the testsets that ran.
- A fix has a blast radius you did not measure. Before changing acceptance
  or rejection semantics, find every contract and test probing the old
  behavior.
- A fix's neighbours are where the next defect is. Re-walk the call sites and
  sibling files a fix touched, re-run its property on what it did not change,
  and end every fix or feature campaign with a targeted neighbour audit.
- A configuration you set is not a configuration the code read. Assert what
  the run recorded. A silently ignored non-default request is a defect.
- Every public option lands with its runtime consumer, structured metadata,
  invalid and inactive behavior, and an effectiveness test at the consumer
  boundary.
- Every branch reachable from a CUDA kernel compiles as device IR, throws
  included, so their messages stay static.
- Do not hand-copy knowledge (case lists, solver enumerations, spec tables,
  launch sites): derive it from one source and add a coverage tripwire. When
  a symbol, arity, or launch site changes, grep the whole `src/` tree.
- Loud beats silent. Dropped charge, dropped rows, skipped checks, and
  ignored configuration warn, throw, or are documented as inert.
- Prefer physics-level agreement to bitwise equality; state every tolerance.
- Commit what a future session needs: reports, harnesses, provenance, and the
  numbers behind a claim land in the same commit as the claim, never only in
  a scratchpad or the git-ignored `result/`.
- Contracts verify; policies only decide how to run. Never claim a contract,
  analysis, policy, or keyword before its implementation exists.
- The spec layer (physics meaning, metadata) and the runtime layer (execution
  data) stay separate; runtime representations may change.

## Architecture and Source Map

Physics, then the Knowledge Layer, then implementation, then contracts, then
validated software. The Core Objects are `ElementSpec`, `TrackingMethod`,
`ExecutionPolicy`, `Contract`, `Analysis`, `Example`, and `Task`; each has an
exported `Abstract<Name>` supertype in `src/knowledge/Knowledge.jl`, and
`summarize_registry()` lists every category's concrete members, strong-strong
solvers included. An element flows from `ElementSpec{kind}` through a
`TrackingMethod` and an `ExecutionPolicy` into `compile_runtime`. Execution
choices belong to policies; numerics intrinsic to a solver belong to it.

One public module, `src/Octopus.jl`, holds the dependency-ordered include
list; element files are included from `src/elements/Elements.jl`. No internal
submodules. Every directory under `src/` has a bullet below; the suite checks.

- `src/elements/`: element specs, runtime maps, element tracking.
- `src/track/`: generic tracking infrastructure only.
- `src/policies/`: execution policies and their option schemas.
- `src/contracts/`: contract types and `validate` implementations.
- `src/analysis/`: analysis types (placeholder-only today).
- `src/tasks/`: workflow composition and execution; `strongstrong/` holds the
  solvers and the configuration validator.
- `src/constants/`: shared physical constants, units documented.
- `src/beam/`: `BeamParams`, `Phase6DRep`, `Beam`, accessors, statistics.
- `src/knobs/`: the knob system; design note `docs/knob_control.md`.
- `src/knowledge/`: `ElementSpec`, `ElementMeta`, schemas, abstract roots.
- `src/registry/`: the reflection registry and the generated snapshot.
- `src/math/`: shared numerics with no accelerator semantics.
- `src/examples/`: the `Example` objects and the examples catalogue.
- `ext/`: package extensions for the `[weakdeps]`, the one sanctioned
  boundary outside the module; core keeps a serial passthrough.
- `test/runtests.jl`: the single suite. `test/examples/`: developer harnesses.
  `examples/`: clean precedents. `validation/`: numerical checks and their
  `README.md`. `profiling/`: opt-in benchmark drivers. `result/`: git-ignored
  run output, never evidence.
- `docs/`: `theory/` derives, `design/` decides, `guides/` instructs,
  `history/` records (frozen: add, never rewrite); `docs/README.md` indexes
  all of it. `.github/workflows/ci.yml`: the CPU-only CI gate.

## Task Routing

Classify the work before reading broadly. Apply every matching row when a
task spans categories; cite a row by its task label. Read only what the
matching rows name, not every referenced document. When directions conflict,
the more specialized protocol controls, while the Invariants and the
Verification Matrix always remain in force. Guides live in `docs/guides/`.

| Task | Read first | Guide | Finish with |
|---|---|---|---|
| Understand current work or choose the next task | `docs/todo.md`; `docs/experiences.md` whole | read-only | none; an opened or closed row changes with its work |
| Run an example, harness, or script and explain the result | the script's header and `config`; the run-artifact reader in `docs/public_api.md` | read-only | none; report what the run recorded, not what you passed |
| Audit, correctness review, or post-campaign neighbour audit | `docs/comprehensive_audit.md` in full | the protocol itself | the protocol's report, index entry, and `docs/todo.md` rows |
| Diagnose or fix a defect | the owning `src/` file and its CPU/CUDA or thin/thick twin; the `@testset`s by name; `docs/comprehensive_audit.md` "Fix Confirmed Defects" | `development_workflow.md` | a regression test shown to fail unfixed; the neighbour audit; the matrix |
| Add or modify an element | the `?@element_spec` checklist; a sibling element and its theory note | `elements.md` | `validate_element_metadata()`; the matrix |
| Add or modify a tracking method | `?AbstractTrackingMethod`; `src/knowledge/Methods.jl` | `configuration.md` | `validation/tracking_backend_consistency.jl`; the matrix |
| Add or modify a solver, policy, or public option | the runtime consumer; `?ConfigurationOptionMeta`; `solver_help()`; `docs/design/run_artifact.md` for output options | `configuration.md` | `validate_configuration_metadata()`; the effectiveness contract; the matrix |
| Add or modify a contract or analysis | `src/contracts/Contracts.jl`; the specs that attach it | `contracts_and_analyses.md` | the contract's own `validate` run; the matrix |
| Change CUDA-reachable or concurrent code | `docs/design/testing_lanes.md` section 3; `docs/current_runtime.md` backends and GPU notes | `development_workflow.md` | the backend-consistency scripts; the matrix, CUDA active |
| Perform scientific validation or a numerical study | the owning theory note via `docs/README.md`; `validation/README.md`; the campaign's history file | `examples_and_validation.md` | the script reproduces; the record committed; the matrix |
| Add or modify an example | the closest example and its harness where one exists; `example_catalog` | `examples_and_validation.md` | the script runs; the catalogue entry; the matrix |
| Benchmark, profile, or optimize | the `profiling/` driver header (fixed point, digest); the campaign history | `development_workflow.md` | baseline first; before/after time, allocation, digest recorded; the matrix |
| Change public documentation or APIs | the docstrings; `docs/public_api.md`; `docs/README.md` | `documentation.md` | the index entry; the snapshot; the matrix |
| Finish and commit any change | `development_workflow.md`, "Committing" | `development_workflow.md` | the gate the matrix names, on the final tree; ledger updates in the same commit |

## Change Authorization

The request determines whether files may change; this file determines how.
Explanation and review requests are read-only unless the request asks for
changes. An audit writes the deliverables its protocol requires and runs its
fixing phases only when the request authorizes edits; otherwise each
confirmed finding becomes a `docs/todo.md` row. Stop and ask before anything
irreversible: discarding uncommitted work, rewriting git history, altering an
existing record under `docs/history/`. In a non-interactive, scheduled, or
cloud run with no human to ask, work read-only and report the edits an
attended session would have made. Nothing unattended writes shared history.

## Verification Matrix

```bash
# fast lane: a development checkpoint, never the finish line
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(test_args=["lane=fast"], julia_args=["--threads=4"])'
# full gate at CI settings: the finish line for every class but one
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
```

The full gate is the finish line for every class below except the first,
whose membership is read from `git diff --name-only`, never claimed. The
fast lane skips heavyweight sections loudly and earns no authority
elsewhere. CI has no GPU, so green CI covers CPU testsets only. Targeted
checks run before the gate, never instead of it. Receipts:
`docs/design/testing_lanes.md`, section 3.

| Change class | Targeted checks | Gate |
|---|---|---|
| markdown only: the diff names only `.md` files and not `docs/registry_snapshot.md` | the index entry | fast lane on the final tree |
| docs plus anything else: a `.jl` comment, the CI workflow, the snapshot | the index entry; the snapshot unchanged | full |
| element spec, metadata, help output | `validate_element_metadata()`; both `element_help` forms; the snapshot | full |
| element kernels, `compile_runtime`, coordinate conversions | `validation/tracking_backend_consistency.jl`; the symplecticity case | full |
| public configuration: policies, solver and task options, observers, schedules, launch config | `validate_configuration_metadata()`; `validate(PublicConfigurationEffectivenessContract())`, full lane only | full |
| contracts, tolerances, acceptance or rejection, aperture and loss | every probing test found first; the contract's own `validate` | full |
| symbol removal or rename, arity, launch sites | a repo-wide `src/` grep | full |
| CUDA-reachable code | every branch compiles as device IR; the backend-consistency scripts | full, CUDA active, on a GPU machine |
| concurrency surfaces: worker closures, reductions, chunk grids, counter RNG | the `Core.Box` tripwire; thread-count invariance | full, at four threads |
| examples | the script runs; the catalogue entry | full; example execution is full-lane only |
| validation, study, or benchmark | the script reproduces; the record is committed | full, before the commit carrying the claim |
| test infrastructure: lanes, gates, `test/runtests.jl` | the skip banner still appears | full |
| read-only work | report the recorded configuration and every skipped check | none |

## Definition of Done

- The gate the matrix names ran on the final tree, CUDA active where the
  matrix requires it; the report names the lane, lists every skipped or
  unrunnable check, and states what was not verified.
- Every new public option has its effectiveness test, every new public object
  is in `docs/registry_snapshot.md`, every new document is in `docs/README.md`.
- `docs/todo.md`, `docs/history/`, and `docs/experiences.md` changed in the
  same commit as the work they describe; the numbers behind claims are
  committed.
- A fix or feature campaign ended with a targeted neighbour audit.
- The commit subject is `type(scope): lower-case summary`; the body names
  what changed, why, and the gate run; the message went through
  `git commit -F <file>`.
