# Octopus.jl

Octopus is a Julia accelerator simulation framework focused on agent-readable
physics metadata, explicit tracking workflows, and CPU/CUDA execution paths.

The current code supports:

- flexible accelerator element specs with constructor help and metadata queries;
- 6D particle/beam tracking on CPU threads and CUDA;
- weak-strong and strong-strong beam-beam examples;
- four strong-strong Poisson solvers: soft-Gaussian, PIC, spectral sine-series,
  and the Gaussian-subtracted PIC hybrid;
- counter-based random numbers for reproducible CPU/GPU tracking;
- validation scripts for RNG, backend consistency, and PIC field accuracy.

## Quick Start

From the repository root:

```bash
julia --project=.
```

```julia
include("src/Octopus.jl")
using .Octopus

build_registry()
element_help(:thin_crab_cavity)
```

## Examples

The examples are clean, production-shaped precedents. Each has a small
`config` block at the top (`use_gpu`, `turns`, macroparticle counts) that you
edit — there are no environment variables. Run them from the project root:

```bash
julia --project=. examples/weak_strong_tracking.jl
julia --project=. examples/strong_strong_tracking.jl
```

Set `use_gpu = true` in the `config` block to run on CUDA. The strong-strong
example builds a `PICPoissonSolver` and shows the soft-Gaussian, spectral, and
Gaussian-subtracted-PIC solvers as commented alternatives (they share the same
interface — see `?AbstractPoissonSolver`).

For developing or A/B-testing the solvers, `test/examples/` holds configurable
harnesses of the same two cases that expose solver selection, CUDA launch
tuning, per-phase timing, and diagnostic/output switches through `OCTOPUS_*`
environment variables:

```bash
OCTOPUS_USE_GPU=1 OCTOPUS_SOLVER=pic OCTOPUS_TURNS=100 \
julia --project=. test/examples/strong_strong_tracking.jl
```

## Validation

Run the fast CPU-only package regression suite:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Scientific accuracy studies, backend consistency checks, and production-size
benchmarks remain separate scripts under `validation/`.

```bash
julia --project=. validation/counter_rng_validation.jl
julia --project=. validation/symplecticity_validation.jl
julia --project=. validation/high_energy_weakstrong_limit.jl
OCTOPUS_RUN_GPU_CONTRACT=0 julia --project=. validation/tracking_backend_consistency.jl
```

CUDA backend validation requires a working CUDA.jl environment:

```bash
OCTOPUS_RUN_GPU_CONTRACT=1 julia --project=. validation/tracking_backend_consistency.jl
julia --threads=4 --project=. validation/strong_strong_pic_cache_backend_consistency.jl
```

## Documentation Map

- `AGENTS.md`: development rules for human and AI collaborators.
- `docs/README.md`: **index of every document in `docs/`** (categorized:
  entry-point/generated, theory notes, planning) — start here.
- `docs/public_api.md`: entry points to public docstrings and metadata queries.
- `docs/current_runtime.md`: current runtime/backend behavior.
- `docs/registry_snapshot.md`: generated registry snapshot.
- `docs/todo.md`: forward-looking plan (open items per solver).
- `docs/theory/`: physics/method theory notes (synchro-beam longitudinal kick,
  weak-strong source model, spectral solver, Gaussian-subtracted PIC solver).
- `docs/history/`: dated records of implemented work (optimization and benchmark
  histories, audits).
- `examples/`: runnable case-law examples.
- `profiling/`: focused runtime profiling scripts.
- `validation/`: numerical-check scripts and backend-consistency tests.

## Notes

Generated simulation output is ignored by Git. Local results are written under
`result/` by the examples.
