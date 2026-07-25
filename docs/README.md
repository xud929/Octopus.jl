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

- [`beam_beam_longitudinal_kick.md`](beam_beam_longitudinal_kick.md) — the
  synchro-beam 6D longitudinal kick: moving source centroid, transported
  covariance, principal-axis rotation, virtual drift, and the slingshot term.
- [`weak_strong_6d_model.md`](weak_strong_6d_model.md) — the weak-strong source
  model: which source moments enter the kick formulas and how a continuous 6D
  Gaussian is sliced longitudinally.
- [`spectral_sine_poisson_solver.md`](spectral_sine_poisson_solver.md) —
  `SpectralPoissonSolver`: Dirichlet-box double sine-series Poisson solve, DST/DCT
  discrete form, CUDA notes, open-boundary discussion, and measured accuracy.
- [`gaussian_subtracted_pic_solver.md`](gaussian_subtracted_pic_solver.md) —
  `GaussianPICPoissonSolver`: control-variate hybrid (analytic Gaussian + PIC
  residual), the `erf` deposition integrals, domain-margin sizing, the coupling
  switch, and measured accuracy (incl. the bi-Gaussian fairness test).

## Planning

- [`todo.md`](todo.md) — the single forward-looking plan (open items and
  implementation/validation/performance plans per solver).

## Where other documentation lives

- **API details** → source docstrings (`?PICPoissonSolver`, `solver_help(...)`,
  `element_help(...)`), routed by `public_api.md`.
- **Completed-work history / optimization campaigns** →
  `validation/*_optimization_history.md` (PIC, spectral, soft-Gaussian,
  Gaussian-subtracted PIC, diagnostics) and the `### Completed` sections of
  `todo.md`.
- **Numerical checks and their run commands** → `validation/README.md`.
- **Runnable precedents** → self-documenting top-of-file comments in `examples/`.
- **Development rules for humans and AI agents** → `AGENTS.md`.
</content>
