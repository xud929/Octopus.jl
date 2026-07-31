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
- [`knob_control.md`](knob_control.md) — design note for the knob subsystem
  (`@knob`/`@knob_expr`): parameters as stored expression trees validated at
  definition time, typed knobs and plain-assignment namespace access,
  reading knob/expression values (`knob_value`, live standalone expressions),
  evaluation at `compile_runtime`, epoch-based task recompilation, the native
  symbolic derivative, and the optional Symbolics.jl adapter.

## Theory / method notes (the physics "Knowledge Layer")

Self-contained derivations behind the accelerator-physics methods. They are
reference material, not API docs; the implementing code links back to them.

- [`beam_beam_longitudinal_kick.md`](theory/beam_beam_longitudinal_kick.md) — the
  synchro-beam 6D longitudinal kick: moving source centroid, transported
  covariance, principal-axis rotation, virtual drift, and the slingshot term.
- [`weak_strong_6d_model.md`](theory/weak_strong_6d_model.md) — the weak-strong source
  model: which source moments enter the kick formulas and how a continuous 6D
  Gaussian is sliced longitudinally.
- [`gaussian_longitudinal_slicing.md`](theory/gaussian_longitudinal_slicing.md) —
  where to put longitudinal slices and what charge to give them: slicing as
  Gaussian quadrature, full derivations of the five Furman prescriptions
  (equal spacing, equal charge with median or centroid node, $\sqrt{\rho}$
  weights, minimum CDF mismatch), reference values with a published-table
  erratum, moment-fidelity ranking, the measurement that equal-charge slicing is
  tail-limited to **first order** (85% of the error in two semi-infinite bins,
  because $\int\mathrm dz/\lambda$ diverges for a Gaussian) and that this carries
  over to the physical metric, the slicing-as-integrator view separating
  quadrature error from splitting error — with the verified virtual-drift group
  structure and why high-order composition is therefore closed — the "how many
  slices" criterion and why it does not transfer to weakly damped hadron rings,
  rules outside that set (Gauss–Hermite, the Xsuite modes, observable-matched
  quadrature), and the measured EIC ranking of every implemented rule.
- [`lattice_hamiltonian_and_conventions.md`](theory/lattice_hamiltonian_and_conventions.md) —
  reference for lattice-magnet tracking: the curvilinear Hamiltonian, the four
  longitudinal conventions (MAD-X/PTC, SixTrack, Forest/PTC `TIME=FALSE`, Bmad)
  with the exact conversions and which code uses which, the multipole strength
  definitions ($n!$ expansion, $K_n$ versus relative $b_n$/$a_n$), the verified
  exact drift and exact sector bend with independent frame curvature $h$ and
  dipole strength $b_0$, the removable singularities that force small-parameter
  branches, **the fringe-field maps decoded from the PTC source** (three
  independent mechanisms, the Forest–Milutinović multipole fringe as an exact
  point transformation, the six-component dipole face, the SAD cubic most codes
  omit), and the PTC flag set a benchmark contract must pin.
- [`near_round_bassetti_erskine_switch.md`](theory/near_round_bassetti_erskine_switch.md)
  — near-round analytic Gaussian evaluation: invariant anisotropy, the
  fixed-interval field integral and third-order potential expansion,
  precision-scaled smooth blending, the stable near-axis evaluator, and the
  recorded CPU/CUDA continuity experiment.
- [`node_interaction_grid.md`](theory/node_interaction_grid.md) — what
  `interaction_grid = :node` is for and why it works: the mesh is a step function
  of `z` under per-slice-pair sizing, the algorithm is already `C^0` and only the
  mesh spoils it, indexing by interpolation node restores it exactly, why the
  longitudinal kick forces a third plane (averages tolerate independent errors,
  differences do not), and why sharing node planes is rejected on
  self-consistency grounds.
- [`slice_longitudinal_interpolation.md`](theory/slice_longitudinal_interpolation.md) —
  smoothness of the sliced beam-beam kick (`slice_interpolation`,
  `interaction_grid`): why the transverse kick is $C^0$ across slice boundaries
  but the longitudinal kick is a discontinuous sawtooth, the implementation-level
  continuity breakers, the separation of interpolation error from slicing error,
  the three-node quadratic extension, and the measured finding that field
  accuracy does **not** predict emittance growth here.
- [`spectral_sine_poisson_solver.md`](theory/spectral_sine_poisson_solver.md) —
  `SpectralPoissonSolver`: Dirichlet-box double sine-series Poisson solve, DST/DCT
  discrete form, CUDA notes, open-boundary discussion, and measured accuracy.
- [`pic_free_space_kernels.md`](theory/pic_free_space_kernels.md) —
  `PICPoissonSolver` field solve: the second- and fourth-order on-mesh gradient
  stencils (`field_derivative`), the node-sampled vs cell-integrated free-space
  kernels (`green_type`, including the **experimental** `:lattice` variant —
  flat-beam field-accuracy studies only, not production), and the
  Vico-Greengard-Ferrando truncated kernel —
  derived, measured, and rejected for this solver.
- [`gaussian_subtracted_pic_solver.md`](theory/gaussian_subtracted_pic_solver.md) —
  `GaussianPICPoissonSolver`: control-variate hybrid (analytic Gaussian + PIC
  residual), the `erf` deposition integrals, domain-margin sizing, the coupling
  switch, and measured accuracy (incl. the bi-Gaussian fairness test).
- [`coherent_beam_beam_modes.md`](theory/coherent_beam_beam_modes.md) — the
  sigma/pi coherent dipole modes and the Yokoya factor: rigid model,
  linearized-Vlasov m=1 eigenproblem with the flatness-dependent 1D-reduced
  kernel (translation/harmonic-limit self-checks), an exact particle referee
  of the same model that *measures* the truncation error, the measured 2D
  Y-versus-flatness and Y-versus-xi scans, and the coupled asymmetric
  (EIC-like) mode analysis.

## Planning

- [`todo.md`](todo.md) — the single forward-looking plan (open items and
  implementation/validation/performance plans per solver). The interaction-grid
  determination program (phases 0-4), non-finite coordinate detection, and the
  CUDA `:quadratic` wavefront port are complete; the leading open threads are
  the outer-boundary re-slicing jitter (now quantified) and the remaining CUDA
  `:node` performance budget.

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
  [`gaussian_slicing_convergence_2026_07_31.md`](history/gaussian_slicing_convergence_2026_07_31.md)
  (all five Furman slicing rules plus Gauss-Hermite implemented and ranked at EIC
  weak-strong parameters; algorithm #5 shown to need no optimizer; Gauss-Hermite
  measured to *lose* despite moment exactness; high-order composition closed),
  [`slice_longitudinal_interpolation_record.md`](history/slice_longitudinal_interpolation_record.md)
  (sliced beam-beam kick smoothness: derivation, frozen z-scan field accuracy,
  multi-turn emittance-growth measurement, the `slice_interpolation` and
  `interaction_grid` options, and why field accuracy did not predict dynamics),
  [`major_release_review_remediation_2026_07_30.md`](history/major_release_review_remediation_2026_07_30.md)
  (complete pre-release finding disposition: analytic Gaussian stability,
  moment reductions, physical scale handling, GaussianPIC rank fallback,
  absolute turn state, symplectic matrix validation, concurrent workspaces,
  CUDA memory retention, radiation semantics, and final validation results),
  [`stable_strong_strong_moments_2026_07_30.md`](history/stable_strong_strong_moments_2026_07_30.md)
  (stable shifted CPU/CUDA variance and covariance reductions, cancellation
  regression coverage, and 200-turn production performance measurements),
  [`public_configuration_audit.md`](history/public_configuration_audit.md),
  [`weak_strong_6d_model_validation.md`](history/weak_strong_6d_model_validation.md),
  [`poisson_solver_review_2026_07_24.md`](history/poisson_solver_review_2026_07_24.md)
  (full review of all four Poisson solvers: consistency audit, theory
  re-derivation, open-source comparison, per-phase profiling, 200-turn production
  runs, and error analysis),
  [`full_review_2026_07_26.md`](history/full_review_2026_07_26.md)
  (line-by-line source review of the whole tree, theory re-derivation of every
  code-facing formula, cross-file consistency audit and fixes, full
  contract/test run, plus four completed todo items: non-finite fail-fast
  detection, the CUDA `:quadratic` batched-route port, the re-slicing jitter
  quantification, and the corrected hybrid z-scan).

## Where other documentation lives

- **API details** → source docstrings (`?PICPoissonSolver`, `solver_help(...)`,
  `element_help(...)`), routed by `public_api.md`.
- **Numerical checks and their run commands** → `validation/README.md` (the
  scripts themselves live in `validation/`).
- **Runnable precedents** → self-documenting top-of-file comments in `examples/`.
- **Development rules for humans and AI agents** → `AGENTS.md`.
