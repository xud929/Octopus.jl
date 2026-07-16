# Octopus Agent Entry Point

Octopus is an AI-native accelerator physics framework. Its goal is not to
replace existing accelerator codes such as MAD-X, Bmad, Elegant, Xsuite, or
SciBmad. Its goal is to build a scientific software platform where AI can be a
first-class developer while rigorous accelerator physics validation remains
central.

Octopus is developed by humans and AI agents, so architectural intent must stay
explicit in source, docstrings, examples, contracts, and generated registries.
The codebase should be self-describing enough that an agent can extend it
without reverse-engineering the whole implementation.

Do not read the entire source tree by default. Read only the documents and files
related to the task.

## Agent Role

Before changing files, an agent must know its role. If the human has not
specified one, ask which role applies:

- **User agent**: may inspect files, run commands, execute examples/notebooks,
  and explain results. Must not edit source files or add new project files.
- **Developer agent**: may add new files and generated artifacts when requested,
  but must not edit existing project files.
- **Maintainer agent**: may add, edit, rename, or remove project files as needed
  for the requested task.

If a requested task exceeds the current role, stop and ask the human to confirm
an elevated role before making file changes.

## How To Orient

- For current public objects, read `docs/registry_snapshot.md` or run
  `summarize_registry()`.
- For stable API usage, read `docs/public_api.md`, then use Julia help on the
  referenced docstrings.
- For element construction help, use `element_help()` or
  `element_help(MyElementSpec)`.
- For developing a new accelerator element type, read `?ElementSpec`,
  `?@element_spec`, and existing element source files.
- For executable workflow patterns, read `?TrackingTask`, `?ScheduledObserver`,
  `?ScheduledAction`, examples, or the relevant notebook.
- For realistic simulation precedents, inspect the files in `examples/`.
  Each stable example should explain its purpose, structure, inputs, outputs,
  and run command in a concise top-of-file comment.
- For current runtime details, read `docs/current_runtime.md`.

## Guiding Principle

Do not merely use AI to write accelerator code. Design the codebase so its
architecture is explicit enough for AI collaboration.

The durable architecture is:

```text
Physics
    ↓
Knowledge Layer
    ↓
Implementation
    ↓
Physics Contracts
    ↓
Validated Scientific Software
```

AI models will change. The knowledge architecture should remain useful.

## Architectural Rules

- Element specs describe physics meaning and metadata.
- Tracking methods describe numerical algorithms.
- Execution policies describe how computation is run.
- Physics contracts define correctness checks.
- Analyses define post-processing.
- Examples define curated precedents.
- Tasks compose workflows.
- Task hooks handle scheduled diagnostics and turn-level orchestration outside
  accelerator element sequences.
- Runtime representations are implementation details and may change.

Do not assume the current particle representation, backend, or tracking kernel
interface is permanent.

## Core Objects

The first-class architecture objects are:

- `ElementSpec`
- `TrackingMethod`
- `ExecutionPolicy`
- `PhysicsContract`
- `Analysis`
- `Example`
- `Task`

These are architectural concepts, not incidental implementation details.

## Two-Layer Element Design

Every element should distinguish:

- Spec layer: physics meaning, metadata, supported methods,
  contracts, analyses, examples.
- Runtime layer: compact data needed for efficient execution on a specific
  method and policy.

The intended flow is:

```text
ElementSpec{kind}
    ↓
TrackingMethod
    ↓
ExecutionPolicy
    ↓
compile_runtime
    ↓
Runtime object
```

Execution choices such as backend and parallel execution belong to policies,
not to the element's physics spec. Numerical configuration that is intrinsic to
a solver, such as strong-strong longitudinal slicing, belongs with that solver.

## Self-Describing Source

The source code should be the main source of truth. Prefer:

```text
Source code + docstrings + reflection + curated examples
```

over large external metadata hierarchies.

Reflection-generated registries should answer questions such as:

- Which element specs exist?
- Which tracking methods support this spec?
- Which contracts apply?
- Which analyses exist?
- Which examples should an agent imitate?

## Contracts Versus Policies

Policies decide how to run. Contracts verify whether the result is acceptable.

Do not use policies as validation substitutes.

Do not add speculative policy types. Keep a policy only when the runtime can
execute it, or use `PlaceholderPolicy` to document an intentionally unfinished
execution choice. Slicing, MPI, and accuracy-tolerance policies should be added
only when their execution behavior and validation contracts exist.

## Source Ownership

Octopus uses one public Julia module in `src/Octopus.jl`. That file defines the
dependency-ordered `include` list. Do not create internal Octopus submodules or
make source files depend on parent-module imports unless there is a clear,
documented boundary that justifies the extra module layer.

- `src/elements/`: accelerator element specs, element-specific runtime maps, and
  element-specific tracking implementations.
- `src/track/`: generic tracking infrastructure only.
- `src/policies/`: execution policy types and policy helpers.
- `src/contracts/`: validation contract types and contract execution.
- `src/analysis/`: analysis types and analysis execution.
- `src/tasks/`: workflow composition and task execution. Large task
  implementations may use task-owned subdirectories with a short entry file,
  but should not introduce a new Julia module boundary.
- `src/constants/`: shared physical constants with units documented.
- `docs/`: short entry-point, generated, or volatile-runtime notes. Detailed
  API guidance belongs in docstrings.
- `examples/`: runnable workflow scripts. Each example is self-describing; do
  not create a separate markdown page for each example.
- `validation/`: developer-facing numerical validation scripts. These may use
  internal helpers and should state the reference model, error metric, output
  files, and run command.
- `notebook/`: executable demonstrations and experiments.

## Updating Elements

When adding or changing an accelerator element:

1. Put the element in `src/elements/`.
2. Use `ElementSpec{kind}` for the public spec object when the element may need
   descriptive fields beyond runtime tracking parameters.
3. Provide a friendly constructor such as `MyElementSpec(...)` that builds the
   flexible `ElementSpec{kind}`.
4. Register metadata with one `@element_spec begin ... end` block. Use the field
   name `friendly_constructor`, not `friendly`.
5. Attach concrete contracts only when a runnable `validate(...)` path exists.
   Use an empty contract list for unvalidated elements. Keep not-yet-implemented
   analysis declarations behind `PlaceholderAnalysis`; do not claim real
   analyses until they exist.
6. Decide which tracking method or tracking methods the element type supports. Users and
   agents discover this through `supported_tracking_methods`.
7. Confirm `element_help(MyElementSpec)` and `element_help(:my_element)` give a
   useful summary.
8. Define compact runtime data only when execution requires it.
9. Connect specs to runtime data through `runtime_type` and `compile_runtime`.
10. Keep element-specific tracking implementations with the element. The current
    convention is `track_particle(TrackingMethod, runtime_element, coords...)`.
    Put implementation details in `docs/current_runtime.md` when they are likely
    to change.
11. Add or update examples, docs, and contracts if public behavior changes.

## Metadata Principles

- Humans maintain one declarative metadata block per public element.
- Use `@element_spec` and `ParamMeta`; avoid scattering element metadata across
  many methods.
- Use `friendly_constructor`, not `friendly`, in metadata declarations.
- Query functions such as `parameter_schema`, `example_spec`,
  `construction_help`, `physics_keywords`, and `runtime_type` should derive from
  `ElementMeta`.
- Run `validate_element_metadata()` after changing element metadata.
- Regenerate `docs/registry_snapshot.md` with `write_registry_snapshot()` after
  public architecture objects change.
- Do not claim real contracts, analyses, policies, or keywords before the
  implementation exists. Omit contract metadata until a real contract exists;
  use placeholders only for explicitly unfinished analysis or policy concepts.
- Generated docs, notebooks, and agent help should derive from the metadata
  registry whenever practical.

## Updating Tracking Methods

When adding a new numerical method:

1. Define the method type in the knowledge/method layer.
2. Declare which element specs support it.
3. Add method-specific runtime data if needed.
4. Add element-specific tracking implementations beside the affected element.
5. Add validation contracts or contract tolerances appropriate for the method.
6. Update registry/API docs if the method is public.

## Updating Policies

When adding an execution policy:

1. Put the policy type in `src/policies/`.
2. Keep policy fields about execution decisions, not element physics.
3. Add helper methods such as backend selection only when generally meaningful.
4. Update task execution only if the policy changes workflow behavior.
5. Document defaults and units in docstrings.

## Updating Contracts

When adding a validation rule:

1. Put the contract in `src/contracts/`.
2. Return `ContractResult` from `validate`.
3. Use `status=:skipped` for unavailable resources such as a missing CUDA
   device; do not report an unrun check as passed.
4. State numerical tolerances explicitly.
5. Prefer physics-level agreement criteria over bitwise equality.
6. Attach the contract to relevant specs through `required_contracts`.

`TrackingBackendConsistencyContract` is the first general implementation
contract. Run `validation/tracking_backend_consistency.jl` after changing
generic tracking, fused tracking, stochastic tracking, CUDA tracking, or an
element implementation used by that script.

## Updating Analyses

When adding an analysis:

1. Put the analysis type and execution API in `src/analysis/`.
2. Attach it to relevant specs through `supported_analyses`.
3. Provide a small executable example if the output is user-facing.

## Updating Examples

Examples are architectural precedents, not scratch work. Agents and human users
should inspect example source files directly and read the top-of-file comment
before reusing a pattern.

- Put exploratory work in notebooks.
- Promote stable examples into dedicated example files.
- Keep reference examples small, executable, and tied to public APIs.
- Put the example purpose, structure, input/output summary, and run command in a
  concise top-of-file comment.
- Do not create one markdown page per example. Use general workflow docs only
  when documenting reusable API concepts across examples.
- Update examples when public APIs change.

## Updating Validations

Validations are correctness checks, not user workflow examples.

- Put analytic comparisons, numerical regression checks, and implementation
  diagnostics in `validation/`.
- Keep a concise top-of-file comment with the reference model, error metric,
  inputs, outputs, and run command.
- It is acceptable for validation scripts to use internal helpers when the goal
  is to test an implementation detail.
- Save summaries under `result/`; avoid writing dense per-case data by default
  for large sweeps.
- Update `validation/README.md` when adding a reusable validation script.

## Documentation Rules

- Public architecture APIs need docstrings.
- New public objects should appear in `docs/registry_snapshot.md`.
- New or changed workflows should update source docstrings and examples.
- New or changed numerical checks should update validation scripts or their
  README entry.
- Runtime-specific details should go in `docs/current_runtime.md`, not here.
- Do not duplicate large source explanations in markdown.

## Minimal Verification

From the project root:

```bash
julia --startup-file=no -e 'include("src/Octopus.jl"); using .Octopus; println(summarize_registry())'
```

Run a task or notebook relevant to the change. Use CUDA validation only when the
task touches GPU execution and a GPU is visible to Julia.
