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
  branches, the pole-face geometry (`ROT_XZ` derived as a frame rotation,
  `WEDGE` as the thin-sliver limit of the exact bend), **the fringe-field maps
  decoded from the PTC source** (three
  independent mechanisms, the Forest–Milutinović multipole fringe as an exact
  point transformation, the six-component dipole face, the SAD cubic most codes
  omit), and the PTC flag set a benchmark contract must pin. Implemented by
  the `:drift`/`:quadrupole`/`:sextupole`/`:octupole`/`:multipole`/`:sbend`
  elements and checked by `PTCConsistencyContract` against a committed MAD-X
  reference table.
- [`solenoid.md`](theory/solenoid.md) — the exact solenoid map plus superimposed multipoles, derived before
  implementation. The first Octopus element whose **transverse canonical momenta
  stop being the physical ones inside the magnet**, because a longitudinal field
  has a transverse vector potential. Shows the textbook entrance/exit fringe
  kicks are not a separate model but the canonical$\leftrightarrow$kinetic
  conversion forced by $\hat a$ jumping at a hard edge; derives the closed-form
  map from the conserved $p_s$ (rotation of the kinetic momentum by $k_s L/p_s$,
  displacement along the Larmor *half*-angle — the factor-of-two trap); shows it
  reduces to Octopus's own exact drift at $k_s=0$ **to roundoff**, which is why
  the paraxial matrix is rejected rather than reused. Includes the numerical
  verification of every claim, and the consequences for splitting, diagnostics
  and misalignment. Implemented as `SolenoidSpec`, PTC-validated to 4.9e-13
  including both polarities and the Strang-split multipole variant. Section 12
  surveys what PTC, Bmad and Elegant actually do (all hard-edge; only Elegant's
  `MAPSOLENOID` is soft, and it is a field-map integrator). Section 13's
  curved-frame closure is **withdrawn** -- see `todo.md`.
- [`aperture_and_particle_loss.md`](theory/aperture_and_particle_loss.md) —
  design note for aperture and particle loss, surveying MAD-X, Bmad, Xsuite and
  Elegant from source: the shapes all four converge on, whether the aperture is
  an attribute of every element or a separate element, and how each records a
  loss (Xsuite and Bmad set a state code, Elegant compacts the array and reuses
  the dead particle's own slots for the loss position, MAD-X mostly analyses
  rather than kills). Assesses NaN-as-loss-marker honestly -- it propagates for
  free and needs no new array, but erases where and why, poisons every
  reduction, and collides with the existing non-finite guards that currently
  mean "bug". Resolves that objection by having the aperture *log* `(particle, turn)` through
  `TrackingContext` like an observer, so NaN only marks the particle dead, and
  records why per-element loss attribution stays out of reach without a
  different phase-space representation. Confirms a predicate can live in
  `ElementSpec.params` and states what it must be for the GPU. Design only; no
  implementation yet.
- [`misalignment_and_patch_maps.md`](theory/misalignment_and_patch_maps.md) —
  design note for misalignments, rotations and the patch element, comparing
  PTC's factorization (four exact one-parameter Euclidean maps, `ROT_YZ`/
  `ROT_XZ`/`ROT_XY`/`TRANS`, with entry and exit patches computed independently
  from surveyed frames) against Bmad's (one $3\times3$ rotation applied to
  position and momentum plus a single exact drift onto the displaced plane,
  referenced to the element centre, with `bend_shift` for curved frames). States
  why the exit patch is **not** the inverse of the entry patch for a bend --
  invisible on a straight magnet, wrong at first order on every bend in a ring --
  and recommends Bmad's factorization with PTC's bookkeeping. The **patch** half
  is now implemented as `PatchSpec` (`src/elements/patch.jl`) -- a *deliberate*
  frame change, distinct from a misalignment in that the new frame persists
  instead of being restored. Misalignments themselves are implemented, and the
  rotation *order* is now pinned: both compositions are selected by
  `misalign_convention`, with `:madx` agreeing with PTC at 4.96e-13 on the
  all-six case, so bend misalignments are no longer blocked. Sections 6a and 6b
  add the design-orbit roll `ref_tilt` -- a vertical bend is `ref_tilt = pi/2` --
  and the third face of the same convention split, which frame an alignment
  error is quoted in once the orbit is rolled.
- [`beam_line_composition.md`](theory/beam_line_composition.md) — design report
  for a beam line, read against MAD-X, Bmad, elegant, Accelerator Toolbox and
  JuAcc. Why every one of them separates the composition *language* from the
  flat expanded lattice; why reflection is order-only and is **not** element
  reversal; why physical assemblies (a RHIC CQS module, a cryostat) are the real
  requirement behind nested sequences and are better served by per-placement
  provenance than by a live tree; one XPath-shaped selector instead of a family
  of lookup functions; and why a line is an `ElementSpec` rather than a new core
  object — which makes assembly misalignment fall out of `_misalignment_wrap`
  for free. **Implemented** as `src/elements/beam_line.jl`; the metadata
  registration is the one piece still outstanding.
- [`bpm_measurement_model.md`](theory/bpm_measurement_model.md) — what a beam
  position monitor *reads* as opposed to what the beam *is*: the error model
  (body offset, roll, gain, readout bias, resolution noise) read from AT,
  MAD-X and Bmad source, why the reading reduces exactly to MAD-X's
  `(1+MSCAL)x + MRE`, and the measurement that settles the architecture — a
  misaligned zero-length element returns its input bit for bit, so a BPM offset
  cannot live in a tracking map and a BPM is an observer bound to a position
  rather than an element.
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
  [`ref_tilt_2026_08_02.md`](history/ref_tilt_2026_08_02.md)
  (rolling a bend's design orbit plane, so a vertical bend becomes expressible:
  the conjugation map, why it is tracking-complete without a survey, the five
  PTC cases, and the measurement that overturned the predicted composition
  order — MAD-X quotes an alignment error in the *unrolled* frame),
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
