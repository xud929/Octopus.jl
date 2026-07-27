# Octopus.jl

Octopus is a Julia accelerator simulation framework focused on agent-readable
physics metadata, explicit tracking workflows, and CPU/CUDA execution paths.
The current work concentrates on two areas: **strong-strong beam-beam
simulation with a particle-in-cell (PIC) solver** and **weak-strong 6D
beam-beam tracking**. Every capability below is enforced by an executable
contract, a validation script, or a theory note in `docs/theory/`; dated
measurements live in `docs/history/`.

## Strong-strong beam-beam (PIC)

Two live beams collide through longitudinal slicing and a Poisson solve per
directed slice pair, with the full 6D synchro-beam map (virtual drifts and the
potential-difference longitudinal kick — `docs/theory/beam_beam_longitudinal_kick.md`).

- `PICPoissonSolver`: CIC/TSC deposition, open-boundary integrated-log Green
  FFT with a persistent slice-pair cache, second/fourth-order field
  derivatives, linear/quadratic longitudinal slice interpolation, and the
  interaction-grid program (`:slice_pair`/`:source_slice`/`:node` meshes,
  robust extent estimators, grid quantization) that removes the slice-boundary
  kick discontinuity (`docs/theory/slice_longitudinal_interpolation.md`,
  `node_interaction_grid.md`).
- Production CUDA path (indexed wavefront, batched FFTs): ≈0.3 s/turn at the
  production EIC-like case — 2.56M electron / 1.024M proton macroparticles,
  15 slices, 128×128 grid — on a workstation RTX 4500 Ada
  (`docs/history/strong_strong_pic_optimization_history.md`).
- CPU and CUDA agree to tolerance on coordinates, luminosity, and Green-cache
  history, enforced by `StrongStrongPICBackendConsistencyContract`; every
  public solver option is verified to reach its runtime consumer by
  `PublicConfigurationEffectivenessContract` — no silently ignored settings.
- Field accuracy is validated against the exact Bassetti-Erskine field across
  round-to-25:1 aspect ratios, and multi-turn artificial emittance growth has
  been measured per solver and grid at production statistics
  (`docs/history/poisson_solver_review_2026_07_24.md`).
- Non-finite coordinates fail fast at the solver chokepoints on both backends,
  with turn/slice/particle identification.

Three further solvers share the same `collide!` interface and serve as
cross-checks and accuracy tools: the sliced soft-Gaussian (Bassetti-Erskine)
solver, the spectral sine-series solver (`docs/theory/spectral_sine_poisson_solver.md`),
and the Gaussian-subtracted PIC hybrid, whose systematic field error at a
48×48 grid matches plain PIC at 128×128
(`docs/theory/gaussian_subtracted_pic_solver.md`).

## Weak-strong tracking

Single-beam 6D tracking against a rigid Gaussian strong beam
(`ThinStrongBeam` / sliced `GaussianStrongBeam`):

- the complete synchro-beam longitudinal kick, including moving-centroid,
  transported-covariance (`σ_xy` and its collision-point derivative), and
  principal-axis-rotation terms, with three selectable virtual-drift
  Hamiltonians (`:hirata`, `:chromatic`, `:exact`) and explicitly-unsafe
  frozen variants for regression diagnostics only;
- sliced sources built from a full 6×6 Gaussian covariance by *conditional*
  slicing, so crab dispersion moves slice centroids while momentum dispersion
  widens the within-slice covariance (`docs/theory/weak_strong_6d_model.md`);
- ring elements for a complete collider model: linear 6D optics, thin
  multi-harmonic crab cavities, Hirata crossing-angle Lorentz boosts,
  chromaticity kicks, and lumped radiation damping/excitation driven by a
  stateless Philox counter RNG — bit-reproducible across CPU thread counts and
  CUDA launch geometries;
- validated by finite-difference symplecticity checks
  (`validation/symplecticity_validation.jl`), the high-energy limit in which
  the strong-strong solvers collapse onto the weak-strong reference
  (`validation/high_energy_weakstrong_limit.jl`), and the CPU/CUDA
  `ElementTrackingBackendConsistencyContract`.

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
