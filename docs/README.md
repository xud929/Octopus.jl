# Octopus `docs/` Index

This is the map of every document in `docs/`. It exists so each document is
findable and its role is unambiguous. Per `AGENTS.md`, the **source code plus
docstrings plus the generated registry** are the primary API reference; the files
here are entry points, generated/volatile-runtime notes, physics/method theory
notes, and the forward plan — not duplicated API reference.

Categories:

## Entry points and generated reference

- [`public_api.md`](public_api.md) — a map to the public docstrings and metadata
  queries (`element_help`, `solver_help`, `?TrackingTask`, ...). The docstrings
  themselves are the API; this file only routes you to the right help query.
- [`registry_snapshot.md`](registry_snapshot.md) — **generated** inventory of all
  public architecture objects. Regenerate with `write_registry_snapshot()` after
  public objects change; do not hand-edit.
- [`current_runtime.md`](current_runtime.md) — **volatile** implementation details
  (particle representation, tracking-kernel interface) that are expected to
  evolve and are not permanent architecture.

## Theory / method notes (the physics "Knowledge Layer")

Self-contained derivations behind the accelerator-physics methods. They are
reference material, not API docs; the implementing code links back to them.

- [`beam_beam_longitudinal_kick.md`](theory/beam_beam_longitudinal_kick.md) — the
  synchro-beam 6D longitudinal kick: moving source centroid, transported
  covariance, principal-axis rotation, virtual drift, and the slingshot term.
- [`weak_strong_6d_model.md`](theory/weak_strong_6d_model.md) — the weak-strong source
  model: which source moments enter the kick formulas and how a continuous 6D
  Gaussian is sliced longitudinally.
- [`spectral_sine_poisson_solver.md`](theory/spectral_sine_poisson_solver.md) —
  `SpectralPoissonSolver`: Dirichlet-box double sine-series Poisson solve, DST/DCT
  discrete form, CUDA notes, open-boundary discussion, and measured accuracy.
- [`pic_free_space_kernels.md`](theory/pic_free_space_kernels.md) —
  `PICPoissonSolver` field solve: the second- and fourth-order on-mesh gradient
  stencils (`field_derivative`), the node-sampled vs cell-integrated free-space
  kernels (`green_type`), and the Vico-Greengard-Ferrando truncated kernel —
  derived, measured, and rejected for this solver.
- [`gaussian_subtracted_pic_solver.md`](theory/gaussian_subtracted_pic_solver.md) —
  `GaussianPICPoissonSolver`: control-variate hybrid (analytic Gaussian + PIC
  residual), the `erf` deposition integrals, domain-margin sizing, the coupling
  switch, and measured accuracy (incl. the bi-Gaussian fairness test).

## Planning

- [`todo.md`](todo.md) — the single forward-looking plan (open items and
  implementation/validation/performance plans per solver).

## Development history and records (`history/`)

Dated records of implemented work — optimization campaigns, benchmark decisions,
and audits. The source code is the authority; these preserve the rationale.
Forward-looking (not-yet-done) items live in `todo.md`, not here.

- Solver optimization histories:
  [`strong_strong_pic_optimization_history.md`](history/strong_strong_pic_optimization_history.md),
  [`strong_strong_gaussian_pic_optimization_history.md`](history/strong_strong_gaussian_pic_optimization_history.md),
  [`strong_strong_spectral_optimization_history.md`](history/strong_strong_spectral_optimization_history.md),
  [`strong_strong_gaussian_optimization_history.md`](history/strong_strong_gaussian_optimization_history.md),
  [`strong_strong_gaussian_optimization.md`](history/strong_strong_gaussian_optimization.md)
  (soft-Gaussian audit).
- Benchmark histories:
  [`strong_strong_pic_extreme_benchmark_history.md`](history/strong_strong_pic_extreme_benchmark_history.md),
  [`strong_strong_diagnostics_benchmark_history.md`](history/strong_strong_diagnostics_benchmark_history.md).
- Audits / change records:
  [`public_configuration_audit.md`](history/public_configuration_audit.md),
  [`weak_strong_6d_model_validation.md`](history/weak_strong_6d_model_validation.md),
  [`poisson_solver_review_2026_07_24.md`](history/poisson_solver_review_2026_07_24.md)
  (full review of all four Poisson solvers: consistency audit, theory
  re-derivation, open-source comparison, per-phase profiling, 200-turn production
  runs, and error analysis).

## Where other documentation lives

- **API details** → source docstrings (`?PICPoissonSolver`, `solver_help(...)`,
  `element_help(...)`), routed by `public_api.md`.
- **Numerical checks and their run commands** → `validation/README.md` (the
  scripts themselves live in `validation/`).
- **Runnable precedents** → self-documenting top-of-file comments in `examples/`.
- **Development rules for humans and AI agents** → `AGENTS.md`.
