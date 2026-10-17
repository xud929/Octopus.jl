# Adding or Changing an Element

Route here from the `AGENTS.md` task table. The metadata checklist itself
lives in the `@element_spec` docstring (`?@element_spec`, or
`src/knowledge/Knowledge.jl` at "Validation checklist"); this guide owns the
repository wiring around it and the design rules the checklist assumes.
Physics derivations belong in `../theory/`, design decisions in `../design/`.

## Two-layer design

Every element distinguishes a spec layer (physics meaning, metadata,
supported methods, contracts, analyses, examples) from a runtime layer
(compact data for efficient execution on a specific method and policy):

```text
ElementSpec{kind} -> TrackingMethod -> ExecutionPolicy -> compile_runtime -> Runtime object
```

Execution choices such as backend and parallelism belong to policies, not to
the spec. Numerical configuration intrinsic to a solver (strong-strong
longitudinal slicing, for example) belongs with that solver. Runtime
representations are implementation details and may change: do not assume the
current particle representation, backend, or kernel interface is permanent,
and record details likely to change in `../current_runtime.md`, not in the
docstrings of public objects.

## Steps

1. Put the element in `src/elements/` and add the file to the include list in
   `src/elements/Elements.jl`, in dependency order. (`src/Octopus.jl` includes
   subsystems; element files are included from `Elements.jl`.)
2. Use `ElementSpec{kind}` for the public spec and provide a friendly
   constructor such as `MyElementSpec(...)` that builds it. Register metadata
   with one `@element_spec begin ... end` block and follow the docstring's
   validation checklist. The query functions (`parameter_schema`,
   `example_spec`, `construction_help`, `physics_keywords`, `runtime_type`)
   derive from that one `ElementMeta`; do not scatter metadata across
   methods.
   - A second friendly constructor that builds an already-registered kind
     (`RBendSpec` builds `:sbend`) is not covered by the block. Call
     `register_friendly_alias!(T, :kind)` after it, or `element_help(T)`,
     `required_contracts(T)` and `supported_tracking_methods(T)` answer empty
     for a validated element.
3. Attach contracts through the block's `contracts = [...]` field only when a
   runnable `validate(...)` path exists; use an empty list otherwise.
   Declare `TwissDispersionAnalysis` on a kind that tracks with
   `Symplectic6DMap` and not `NonSymplectic6DMap` (`:line` is the one union;
   the suite's set tripwires derive the required set from the tracking
   methods); keep not-yet-implemented analyses behind
   `PlaceholderAnalysis`. Do not claim
   contracts, analyses, policies, or keywords before the implementation
   exists.
4. Decide which tracking methods the element supports; users and agents
   discover this through `supported_tracking_methods`. If the kind lists
   `Symplectic6DMap`, add a case to `_symplecticity_contract_cases()` in
   `src/contracts/Contracts.jl`: the suite asserts that no kind declares the
   contract without a case.
5. Define compact runtime data only when execution requires it, and connect
   specs to it through `runtime_type` and `compile_runtime`.
6. Keep element-specific tracking implementations beside the element. The
   current convention is
   `track_particle(TrackingMethod, runtime_element, coords...)`. Every branch
   reachable from a CUDA kernel must compile as device IR, throws included, so
   their messages stay static.
   - Numeric type, ONE rule for every kind (owner decision 2026-10-16): the
     compile constructor builds the runtime in `numeric_type(spec)`. The
     untyped friendly constructor stores its inputs as given, so that is the
     promotion of the stored parameters over a `Float64` floor -- a `Float32`
     input gives a `Float64` element, a dual or complex input widens it,
     nothing narrows. Every kind has a typed form: `abstract type MySpec{T}`,
     the untyped method `MySpec(; numeric_type=nothing, kwargs...)` routing
     `numeric_type=T` to `(::Type{MySpec{T}})(; kwargs...)`, which stores
     `_typed_spec_params(T; kwargs...)` (the floating-point inputs as `T` and
     `numeric_type = T`; the `@element_spec` docstring shows the pair); the
     untyped form stores no type -- one that builds through its typed form
     drops the stored type again (`_floor_form`), so a dual or BigFloat placed
     later by a knob or a placement override still widens the element. Splice
     `_PLACEMENT_PARAMS...` into the schema (or `numeric_type=
     _PLACEMENT_PARAMS.numeric_type`) and mention `numeric_type` in the
     `construction_help`; `validate_element_metadata` checks both. The runtime
     struct carries `T<:Number` as its ONE numeric type parameter: that is
     what `_required_beam_eltype` (`src/track/Track.jl`) derives, so a task
     refuses a beam of another element type by name, with the remedy naming
     the kind's typed form from the registry (`_typed_form_names`); a kind
     whose typed form the keyword spelling would hide owns a
     `_beam_eltype_remedy` method (the crab cavity's `{N,T}`). The suite's
     "One precision rule" testset pins the derived set against the registry
     both ways and runs every kind's `Float32` form on both backends; a new
     kind that departs from the pattern fails there by name
     (`../current_runtime.md` "Current Backends" carries the measurement).
7. Confirm `element_help(MyElementSpec)` and `element_help(:my_element)` give a
   useful summary, and run `validate_element_metadata()`.
8. Add a testset in `test/runtests.jl` (the suite is a single file; element
   testsets sit near "Thin elements, markers and RBEND"). If the element adds
   differentiable parameters, raise the `metrics[:checked] >=` ratchet in the
   "Element parameter effectiveness" testset; it never fails on its own when
   parameters are added.
9. Regenerate `docs/registry_snapshot.md` with `write_registry_snapshot()`,
   and add or update examples, docs, and contracts if public behavior changes
   (`examples_and_validation.md`, `documentation.md`).

## Finish

`validate_element_metadata()`, both `element_help` forms, the registry
snapshot, a `TrackingTask` smoke run, and the full gate
(`development_workflow.md`). Element kernels, `compile_runtime`, and
coordinate conversions are a full-gate class: the physics contracts and the
backend-consistency checks are skipped by the fast lane.
