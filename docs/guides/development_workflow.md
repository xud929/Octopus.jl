# Development Workflow

The inner loop, the gates, and the commit discipline for any change to
Octopus. `AGENTS.md` routes here from every task row; this guide owns the
procedure. The lane design and the measurements behind it are in
[`../design/testing_lanes.md`](../design/testing_lanes.md); the lessons behind
the rules are in [`../experiences.md`](../experiences.md).

## Environment

- Julia 1.12 (`Project.toml` `[compat]`; CI floats on the 1.12 series).
- On a fresh checkout run once:

  ```bash
  julia --project=. -e 'using Pkg; Pkg.instantiate()'
  ```

  `Manifest.toml` is tracked, so this reproduces the exact environment.
- CUDA.jl is a hard dependency that imports without a GPU. `Octopus._HAS_CUDA`
  (`src/beam/Beam.jl`) means "CUDA.jl imported", not "a device exists"; the
  suite gates its CUDA testsets behind `_HAS_CUDA && CUDA.functional()`, and
  contracts that need a device report `status=:skipped` rather than passing.
  GPU-box specifics (the untracked `LocalPreferences.toml` that selects the
  CUDA runtime, device diagnostics) are in `../current_runtime.md`.
- Test-only dependencies (`ForwardDiff`, `Symbolics`, `Logging`) are listed
  under `[targets]` in `Project.toml`; a plain `--project=.` session does not
  have them.
- `ext/` holds the package extensions for the `[weakdeps]` (`ForwardDiff`,
  `Symbolics`). They activate only in package mode (next section).

## Two load modes

Script mode is `include("src/Octopus.jl"); using .Octopus`; the examples, the
validation scripts, and probes use it. Package mode is `using Octopus`;
`Pkg.test` and users use it. Only package mode activates the `ext/`
extensions. Script mode reaches the same shared code through explicit
includes at the bottom of `src/Octopus.jl` (the ForwardDiff rules) and in
`src/knobs/symbolic.jl` (the Symbolics adapter). A probe that passes in one
mode has not verified the other.

## Commands

```bash
# smoke: the package loads and the registry answers (script mode)
julia --startup-file=no --project=. -e 'include("src/Octopus.jl"); using .Octopus; println(summarize_registry())'

# fast lane: a development checkpoint, never the finish line
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(test_args=["lane=fast"], julia_args=["--threads=4"])'

# full gate at CI settings: the finish line before every commit, except a
# diff that `git diff --name-only` shows to be markdown-only (AGENTS.md matrix)
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'

# backend consistency: after changing generic, fused, stochastic or CUDA
# tracking, or an element implementation the contract covers
julia --project=. validation/tracking_backend_consistency.jl
```

Four threads are deliberate: `CPUThreadsExecutionPolicy` takes a serial fast
path with one worker, so a single-threaded run never exercises the concurrent
code. For anything CUDA-reachable or concurrency-related the full gate must
run on a GPU machine with CUDA active; CI has no GPU, so a green CI is a claim
about the CPU testsets only.

REPL-level checks, from a session in either mode:

| after changing | run |
|---|---|
| element metadata | `validate_element_metadata()` |
| public configuration: policies, solver and task options, observers, schedules, buffers, launch configuration | `validate_configuration_metadata()` and `validate(PublicConfigurationEffectivenessContract())` |
| any public architecture object | `write_registry_snapshot()`; the suite compares the committed snapshot with the generated one |

## Iterating on one testset

The suite is one file, `test/runtests.jl`, selected only by lane; there is no
`only=` filter (`../design/testing_lanes.md`, section 5). The recorded probe
workflow:

1. Probes are scratch `.jl` files, not `-e` one-liners, kept outside the
   repository or under the git-ignored `result/`.
2. To iterate on a testset, copy its `@testset` block plus any file-level
   helpers it uses (`_HAS_CUDA`, `_lane_gate`, shared constants) into a
   scratch file that starts `using Octopus, Test`, and run it in package mode
   with `julia --project=. --threads=4 scratch.jl`, so it takes the same
   extension branches the suite does.
3. If the block needs a test-only dependency, stack a scratch environment that
   holds it: `JULIA_LOAD_PATH="<repo>:<scratch-env>:@stdlib"`.
4. A standalone-green probe is reported as standalone. It never substitutes
   for the fast lane, and the fast lane never substitutes for the gate.

## Lanes and the gate

The fast lane skips the registered heavyweight sections, prints one loud
`LANE SKIP` line per skipped section, and ends with a banner naming what it
owes; an unknown lane name is an error. Green fast runs accumulate no
authority: the full gate runs on the final tree before every commit, with one
derived exception. When `git diff --name-only` lists only `.md` files and none
of them is `docs/registry_snapshot.md`, the fast lane on the final tree is the
gate, because it already runs every docs check the suite has. The change
classes, each paid for by a recorded incident, are the matrix in
`../design/testing_lanes.md`, section 3; `AGENTS.md` carries the compact
form.

## Where output goes

- `result/` is git-ignored scratch for run output (summary tables, per-run
  provenance). Avoid dense per-case data by default for large sweeps.
- Anything a claim rests on is committed with the claim: dated records under
  `../history/` (a dated note for a one-off study, the campaign's existing
  `*_history.md` for an ongoing one), reference tables under
  `validation/reference/`, audit reports named as `../comprehensive_audit.md`
  prescribes. Index every new document in `../README.md`.
- Nothing scheduled or unattended writes to shared history
  (`../experiences.md`, "Standing decisions"); benchmark and nightly scripts
  are opt-in per machine.

## Committing

- Subject: `type(scope): lower-case summary`, as `git log` shows (`fix`,
  `docs`, `feat`, `test`, `audit`, `perf`, `refactor`, `ci`, `build`). The body
  says what changed, why, and which full-gate run it rode; a docs-only commit
  names the gate it rides.
- Write the message to a file and use `git commit -F <file>`: backticks in
  `git commit -m` are shell-substituted (`../experiences.md`, "Mechanics that
  bit more than once").
- Never force-push, `reset --hard`, or `checkout` over uncommitted work; a
  careless checkout once destroyed uncommitted fixes
  (`../history/comprehensive_audit_2026_08_04.md`, "A careless git
  checkout"). Files under `../history/` are frozen records: add new ones,
  never rewrite old ones.
- Run the gate the matrix names on the final tree, not on the tree the work
  started from.

## Reporting

Name the lane every test claim refers to. List every check that was skipped
or could not run (no GPU, a missing external tool) instead of folding it into
"green". Say what was not verified. A number a decision rests on goes in the
tracked record, not only in the message.
