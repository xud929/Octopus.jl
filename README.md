# Octopus.jl

Octopus is a Julia accelerator simulation framework focused on agent-readable
physics metadata, explicit tracking workflows, and CPU/CUDA execution paths.

The current code supports:

- flexible accelerator element specs with constructor help and metadata queries;
- 6D particle/beam tracking on CPU threads and CUDA;
- weak-strong and strong-strong beam-beam examples;
- Gaussian and PIC strong-strong Poisson solvers;
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

Run a small CPU weak-strong example:

```bash
OCTOPUS_TURNS=1 OCTOPUS_N_MACRO=100 \
julia --project=. examples/weak_strong_tracking.jl
```

Run a small CPU strong-strong PIC example:

```bash
OCTOPUS_TURNS=1 OCTOPUS_N_MACRO=100 OCTOPUS_POISSON_SOLVER=PIC \
julia --project=. examples/strong_strong_tracking.jl
```

Run the CUDA strong-strong PIC example:

```bash
OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC \
julia --project=. examples/strong_strong_tracking.jl
```

Select a specific CUDA device by adding `OCTOPUS_CUDA_DEVICE=N`, for example
`OCTOPUS_CUDA_DEVICE=1`.

`PICPoissonSolver` uses the longitudinal/Hirata-style kick by default. Disable
it for a transverse-only benchmark with:

```bash
OCTOPUS_PIC_LONGITUDINAL_KICK=0
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
- `docs/public_api.md`: entry points to public docstrings and metadata queries.
- `docs/current_runtime.md`: current runtime/backend behavior.
- `docs/beam_beam_longitudinal_kick.md`: derivation of weak-strong and
  soft-Gaussian longitudinal kicks, virtual drifts, and the slingshot effect.
- `docs/registry_snapshot.md`: generated registry snapshot.
- `docs/pic_solver_improvement_plan.md`: PIC solver optimization notes.
- `examples/`: runnable case-law examples.
- `profiling/`: focused runtime profiling scripts.
- `validation/`: numerical checks and backend consistency tests.

## Notes

Generated simulation output is ignored by Git. Local results are written under
`result/` by the examples.
