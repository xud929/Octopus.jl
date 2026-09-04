# Tracking Methods, Solvers, Policies, and Public Options

Route here from the `AGENTS.md` task table for anything that adds or changes a
tracking method, a strong-strong Poisson solver, an execution policy, or any
public configuration field or keyword (solver options, task options,
observers, schedules, buffers, backend launch configuration).

## The rule every public option obeys

A new public configuration field lands together with its runtime consumer,
its structured metadata, its invalid and inactive behavior, and an
effectiveness test that observes the value at the consumer boundary. Storing,
documenting, or returning a value from a configuration helper is not evidence
that it is applied. A non-default request the code ignores is a defect: honor
it or reject it, never accept it silently. Where a setting can also arrive
ambiently (a process-global launch configuration, an environment variable),
assert on what the run recorded, make the assertion conditional on the
recorded request, and add an anti-vacuity check that at least one path
carried it.

## Tracking methods

1. Define the method type in `src/knowledge/Methods.jl` as a subtype of
   `AbstractTrackingMethod`.
2. Declare which element specs support it, in their `@element_spec` blocks.
3. Add method-specific runtime data if needed.
4. Add element-specific tracking implementations beside the affected element.
5. Add validation contracts or contract tolerances appropriate for the method.
6. Update registry and API docs if the method is public.

## Solvers

All strong-strong solvers share the `collide!` interface, the kick-scale and
luminosity conventions, and the synchro-beam longitudinal map;
`solver_help(SolverType)` lists each one's options. Numerical configuration
intrinsic to a solver lives with the solver. A solver's options are public
configuration and follow the rule above, and the CPU and CUDA paths of one
solver must agree to the tolerance its backend-consistency contract states.
Derivations go in `../theory/`; the current implementation is described in
`../current_runtime.md`.

## Execution policies

Policies decide how to run; contracts verify whether the result is
acceptable. Do not use policies as validation substitutes, and do not add a
policy type the runtime cannot execute. `PlaceholderPolicy` is the
non-executable sentinel used by examples and metadata (`backend_type` and
`execute!` raise on it); it is not a way to reserve a future policy. A policy
that needs a weak dependency keeps its type and serial fallback in core and
puts only the dependency-bound methods in `ext/`.

1. Put the policy type in `src/policies/`. Keep its fields about execution
   decisions, not element physics; document defaults and units in the
   docstring.
2. Add helper methods such as backend selection only when generally
   meaningful. Update task execution only if the policy changes workflow
   behavior.
3. Add `policy_option_schema(::Type{NewPolicy})` in `src/policies/Policies.jl`
   with a runtime `consumer` for every option, and export it: the suite
   checks exports by module name ("every public configuration schema is
   exported").
4. Add the policy's block to `validate_configuration_metadata()` in
   `src/tasks/strongstrong/interface.jl`. The validator enumerates policy
   types by hand (an open `../todo.md` row); its tree guard names any
   concrete policy that has no block.
5. Add coverage beside "The placeholder and deprecated policies actually run"
   and "Configuration rejection" in `test/runtests.jl`.

## Finish

`validate_configuration_metadata()` and
`validate(PublicConfigurationEffectivenessContract())`, then the full gate
(`development_workflow.md`). The effectiveness contract runs in a heavyweight
section the fast lane skips, so a fast-lane green says nothing about it.
Public options are a full-gate class: the recorded failure shape is a pin that
passes alone and fails in the suite.
