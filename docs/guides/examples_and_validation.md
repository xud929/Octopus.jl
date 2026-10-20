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
never in `examples/`. A `config` field or an `OCTOPUS_*` variable that the
chosen mode cannot read is refused by name (an `execution` symbol outside the
documented four, `ranks` outside `:multiprocess`, `gpu_device` off CUDA,
`threads` on CUDA; a CUDA launch variable without `OCTOPUS_USE_GPU=1`, a
timing path without the recording switch): a configuration you set is not a
configuration the code read, and the 2026-10-18 audit found `execution = :gpu`
running on CPU threads with exit 0 (F-204, F-205).

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
- A script that requires a CUDA device, or whose CUDA leg can be required
  with `OCTOPUS_REQUIRE_GPU_CONTRACT=1`, carries one `GATE-CUDA-ARM:` header
  line naming a reduced size (its own environment overrides or key=value
  arguments, `@TMP@` for a scratch directory), the verdict substring its
  stdout prints, and the files
  it writes under the repository; the gate's CUDA arm testset derives the
  list from the scripts' CUDA refusals and fails by name on a CUDA-capable
  script without the line (`validation/README.md`, "The gate's CUDA arm").
  CI has no GPU, so that testset is the only place such a script executes.
- A script's header lists every environment variable it reads, and the list
  is held to the body at load: the `let` block that compares the header's
  `OCTOPUS_*` names with the body's string literals (the pattern of
  `profiling/benchmark_strong_strong_pic.jl`, carried by the three harnesses
  under `test/examples/`). A set variable the script does not read is
  refused by name, never dropped: the crab-cavity harness is the template.

## Finish

The example runs, or the validation script runs and its summary is recorded;
then the full gate (`development_workflow.md`) before the commit that carries
the claim.
