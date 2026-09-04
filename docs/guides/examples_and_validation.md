# Examples, Harnesses, and Validation Scripts

Route here from the `AGENTS.md` task table for `examples/`, `test/examples/`,
and `validation/`.

## Examples are precedents

`examples/` holds clean, production-shaped workflow scripts: the precedents
future users and agents imitate. Each is self-describing. A concise
top-of-file comment states purpose, structure, inputs, outputs, and the run
command, and a small `config` block replaces environment variables. Do not
create one markdown page per example; document reusable API concepts in
general docs instead.

`test/examples/` holds configurable developer harnesses of the same
workflows, exposing solver selection, launch tuning, diagnostics, and A/B
toggles through `OCTOPUS_*` environment variables. Each harness cites its
clean counterpart in `examples/` and vice versa. Exploratory toggles go here,
never in `examples/`.

Adding or changing an example:

1. Start from the closest existing example and its paired harness.
2. Keep stable public workflows in `examples/`; keep A/B controls and
   environment-driven diagnostics in `test/examples/`.
3. Register the script in the examples catalogue (`example_catalog` in
   `src/examples/Examples.jl`); the suite derives the expected set from the
   files under `examples/` and fails on an uncatalogued script.
4. Run the affected example before completion, and update examples whenever
   a public API they use changes.

## Validation scripts are checks, not examples

`validation/` holds developer-facing numerical checks: analytic comparisons,
regression checks against reference tables, and implementation diagnostics.
They may use internal helpers. Each script's top-of-file comment states the
reference model, the error metric, the tolerance, the configuration, the
inputs and outputs, and the run command; the same facts go into the tracked
record of the result.

- Run output (summary tables, per-run provenance) goes under `result/`, which
  is git-ignored and regenerable; avoid dense per-case data by default for
  large sweeps.
- Whatever a claim relies on is committed with it. The tracked record of a
  validation or benchmark campaign goes in `../history/` (a dated note for a
  one-off study, the campaign's `*_history.md` for an ongoing one), indexed in
  `../README.md`; reference tables go in `validation/reference/`.
- Narrative records (histories, audits) belong in `../history/`, not in
  `validation/`.
- Add every reusable script to `validation/README.md` with its reference
  model, metric, and run command.

## Finish

The example runs, or the validation script runs and its summary is recorded;
then the full gate (`development_workflow.md`) before the commit that carries
the claim.
