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

## Design notes (architecture decisions)

Records of *which* design was chosen among alternatives that achieve similar
physics, and why — the decision layer between the theory notes (which derive
what is true) and the source (which implements what was chosen). A design note
cites the theory it builds on and the alternatives it rejected; it does not
duplicate derivations. (`knob_control.md` above is also a design note; it
predates this folder and stays top-level because `AGENTS.md` links it.)

- [`testing_lanes.md`](design/testing_lanes.md) — the fast development lane
  (`Pkg.test(test_args=["lane=fast"])`): the measured time split behind the 13
  guarded heavyweight sections, the loud-skip accounting rules, and the
  decision matrix for change classes where only the full gate (CUDA active)
  counts. The fast lane is a checkpoint, never a finish line.
- [`multi_process_policy.md`](design/multi_process_policy.md) — the
  multi-process execution policy: why the resolved state is a slot on the CPU
  policy rather than a wrapper around it, why resolution is pure while
  activation reads the communicator, the six-function collective seam and its
  rank-ordered folds, the determinism that buys at fixed and at varying rank
  counts, and what step 3 must still choose.
- [`run_artifact.md`](design/run_artifact.md) — the one-output-file-per-task
  design (2026-08-18, decided, implementation on the ledger): the
  probe/channel split, per-producer groups with independent turn axes (which
  dissolve the mixed-IP row-drop machinery), name identities from provenance
  paths, the three buffer shapes behind one protocol, the device-write
  constraints, capacity posture, crash-recovery cursor, live text mirror,
  and the migration order behind the current APIs.
- [`survey_and_reference_channel.md`](design/survey_and_reference_channel.md) —
  the channel telling a runtime element its place on the reference trajectory:
  static survey values (`s_elem`, later `P0`) baked at compile via the line
  walk, the dynamic part from `TrackingContext.turn`, loud refusal without
  context; the rejected alternatives (seventh coordinate, slip-in-every-map,
  context-resident `s`/`P0`, stored per-element reference, time-dependent
  kernels); the taxonomy of reference-energy change (single-pass, multipass,
  ramping-as-knob-epochs); and where Octopus follows versus departs from
  Bmad's bookkeeping-plus-rampers strategy. Prerequisite design for the F16
  velocity-slip fix and RF Scope B.

## Development guides (`guides/`)

Procedures, one per task class, routed from the Task Routing table in
`AGENTS.md`. The root file keeps invariants and routing; these keep the steps.

- [`guides/development_workflow.md`](guides/development_workflow.md) — the
  environment, the two load modes, the commands, the single-testset probe
  recipe, lanes and the gate, where output goes, committing, reporting.
- [`guides/elements.md`](guides/elements.md) — adding or changing an element:
  the two-layer design, the repository wiring around the `@element_spec`
  checklist, and the tests and tripwires that fail the gate when missed.
- [`guides/configuration.md`](guides/configuration.md) — tracking methods,
  solvers, execution policies, and every public option: the consumer rule,
  the schema and validator hooks, the effectiveness contract.
- [`guides/contracts_and_analyses.md`](guides/contracts_and_analyses.md) —
  contracts (attachment, `:skipped`, blast radius, the backend-consistency
  scripts) and the placeholder-only state of analyses.
- [`guides/examples_and_validation.md`](guides/examples_and_validation.md) —
  `examples/`, the `test/examples/` harnesses, the examples catalogue,
  validation scripts, and run output versus the tracked record.
- [`guides/documentation.md`](guides/documentation.md) — docstrings as the
  authority, generated and volatile documents, the `docs/` taxonomy, the
  index, and what `AGENTS.md` itself may carry.

## Theory / method notes (the physics "Knowledge Layer")

Self-contained derivations behind the accelerator-physics methods. They are
reference material, not API docs; the implementing code links back to them.

- [`arc_survey_and_velocity_slip.md`](theory/arc_survey_and_velocity_slip.md) —
  what the survey coordinate is (arc length; bend `L` *is* the arc, so
  curvature changes nothing; the patch and kept-whole-line caveats), why the
  convention-#3 path deficit does not slip with velocity while arrival time
  does, the symplectic z-shift form of the cavity's slip correction with the
  exact cancellation-free `g(δ)`, and the two measured wrong forms kept as
  negative results. Physics behind the survey channel and the F16 closure.
- [`floor_plan_survey.md`](theory/floor_plan_survey.md) — the global-geometry
  survey (MAD-X `SURVEY`): frame propagation `(V, W)`, the per-element
  geometric maps (bends in the `ref_tilt`-rolled plane, patches through the
  shared `_patch_rotation`, misalignments deliberately excluded), the
  measured MAD-X angle conventions with the `tilt = 0.3` extraction anchor,
  the gimbal edge, and the measured `angle_s`-vs-`srotation` roll inversion.
  Written before the implementation, per owner direction; every convention
  is measured, not assumed.
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
  curved-frame closure is **withdrawn** -- see the record in
  [`history/todo_ledger_archive.md`](history/todo_ledger_archive.md).
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
  `ElementSpec.params` and states what it must be for the GPU. **Implemented**
  as `ApertureSpec` + `LossRecord` (`src/elements/aperture.jl`): the loss
  summary fires automatically at the end of every `execute!`, per-collimator,
  and warns whenever `unattributed != 0` — including for a line with no
  aperture at all. Public surface `loss_records`, `loss_counts`,
  `loss_summary`, `write_loss_record`, `read_loss_record`; see
  `docs/public_api.md` §Particle Loss. (Status corrected by the 2026-08-05_b
  audit, U26-3 — the note itself was never updated after the element shipped,
  and this index is what an agent orients from.)
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
- [`rf_cavity_and_reference_energy.md`](theory/rf_cavity_and_reference_energy.md) —
  design note for the RF cavity, and the prior question of whether Octopus needs
  a reference particle. It does not: the reference is bookkeeping, not a tracked
  object, because the coordinates are *defined against* it. What acceleration
  needs instead is a reference-energy profile along the line — the energy survey,
  structurally the same object as `s_positions`. Reads Bmad, MAD-X, elegant and
  AT: why Bmad's `rfcavity`/`lcavity` split is not redundancy (the two use
  different trig functions, so `phi0 = 0` means "no acceleration" in one and "on
  crest" in the other), the four mutually incompatible phase conventions, and why
  an energy kick needs a beta factor to become a `pz` kick in our convention.
  **Scope A implemented** as `ThinRFCavitySpec` (`src/elements/rf_cavity.jl`,
  kind `:thin_rf_cavity`, in the registry snapshot): thin, one localised kick,
  non-accelerating, `L` buying drift space only. **Scope B (accelerating)
  remains design only** — it needs `P0(s)` and the survey channel. One model
  boundary is open and documented at both ends: the slip factor is `alpha_c`
  alone, missing `-1/gamma0^2`, because a runtime element has no channel to its
  accumulated reference path (audit F16; 1.84x nu_s error at 2.5 GeV proton /
  alpha_c = 0.2, negligible at EIC-class gamma0). (Status corrected by the
  2026-08-05_b audit, U26-3.)
- [`beam_line_composition.md`](theory/beam_line_composition.md) — design report
  for a beam line, read against MAD-X, Bmad, elegant, Accelerator Toolbox and
  JuAcc. Why every one of them separates the composition *language* from the
  flat expanded lattice; why reflection is order-only and is **not** element
  reversal; why physical assemblies (a RHIC CQS module, a cryostat) are the real
  requirement behind nested sequences and are better served by per-placement
  provenance than by a live tree; one XPath-shaped selector instead of a family
  of lookup functions; and why a line is an `ElementSpec` rather than a new core
  object — which makes assembly misalignment fall out of `_misalignment_wrap`
  for free. **Implemented** as `src/elements/beam_line.jl`.
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

- [`todo.md`](todo.md) — open work ONLY: the live rows, the open study
  questions, and the CI flake-tally watch.
- [`experiences.md`](experiences.md) — the recurring lessons the completed
  work taught, distilled and grounded in their incidents, plus the standing
  deliberately-not-being-done decisions. Read it before starting a campaign.
- [`history/todo_ledger_archive.md`](history/todo_ledger_archive.md) — the
  complete pre-restructure TODO, frozen verbatim: every closed row, campaign
  narrative, measurement and corrected wrong turn, with U-numbers intact so
  code and test comments citing a "todo row" resolve here.

## Review process

- [`comprehensive_audit.md`](comprehensive_audit.md) — the protocol for a
  repository-wide audit: declare a scope and keep a coverage ledger (phase 0),
  then work through architecture, traceability, source, derivations,
  contracts, tests, validation and performance. The Absolute Rules at the end
  are the part that matters: a file is not reviewed until it is inspected, a
  contract is not satisfied because its tests passed, and an area found sound
  is a result worth recording.

## Development history and records (`history/`)

Dated records of implemented work — optimization campaigns, benchmark decisions,
and audits. The source code is the authority; these preserve the rationale.
Forward-looking (not-yet-done) items live in `todo.md`, not here; the
frozen pre-2026-08-16 TODO ledger is [`todo_ledger_archive.md`](history/todo_ledger_archive.md).

- Solver optimization histories:
  [`strong_strong_pic_optimization_history.md`](history/strong_strong_pic_optimization_history.md),
  [`strong_strong_gaussian_pic_optimization_history.md`](history/strong_strong_gaussian_pic_optimization_history.md),
  [`strong_strong_spectral_optimization_history.md`](history/strong_strong_spectral_optimization_history.md),
  [`strong_strong_gaussian_optimization_history.md`](history/strong_strong_gaussian_optimization_history.md),
  [`strong_strong_gaussian_optimization.md`](history/strong_strong_gaussian_optimization.md)
  (soft-Gaussian audit),
  [`cpu_threading_2026_08_09.md`](history/cpu_threading_2026_08_09.md)
  (the CPU-threading campaign on the 128-thread/64-core box: what was serial
  and why, the per-fix measurements with their bitwise-parity digests, and the
  machine-level findings — idle-thread spin, GC share, and why a pool wider
  than the data's parallelism costs rather than pays),
  [`multi_process_tracking_scaling_2026_09_04.md`](history/multi_process_tracking_scaling_2026_09_04.md)
  (the rank-by-thread scaling the campaign exists for: processes beat threads
  1.9x at the same width, 61.9x at 64 ranks x 2 threads, binding worth 4% in
  speed but cutting the rank spread 35% to 5%, and why no code change
  followed),
  [`multi_process_step3a_2026_09_04.md`](history/multi_process_step3a_2026_09_04.md)
  (a tracking task divided across ranks: the chunk-aligned shard rule and why
  it is derived rather than stored, global-index keying for the random
  streams, why a beam is drawn whole and sliced, and the bitwise agreement
  measured at 1, 2 and 4 ranks with radiation on),
  [`mpi_environment_2026_09_04.md`](history/mpi_environment_2026_09_04.md)
  (which MPI runtime an Octopus process carries, decided by test: MPICH_jll
  by default because the installed HDF5_jll already links it, a system MPI as
  a two-preference opt-in; corrects the Phase 0 "load-order lock" to the
  narrower thing it is, and records why the tracked Manifest cannot be
  re-resolved on this box),
  [`multi_process_phase0_2026_08_19.md`](history/multi_process_phase0_2026_08_19.md)
  (Phase 0 of the multi-process mixed policy, single-node scope: the first
  weak-strong thread-scaling curve — allocation/GC-bound, 1.282 GiB/turn,
  optimum 16 threads — the on-box MPI P x T matrix at the production point
  (PIC 8x8 socket-bound 1.86x over 1x16; socket binding alone 17–22%), the
  MPI-over-Distributed decision with its measured collective costs, and the
  two environment traps — the HDF5_jll MPI-variant flip and the
  MPIPreferences load-order lock — that Phase 1 must resolve),
  [`weak_strong_allocation_2026_09_04.md`](history/weak_strong_allocation_2026_09_04.md)
  (multi-process step 1: the weak-strong per-particle allocation localised to
  the sliced strong beam's per-slice `mutable struct` -- 7 x 192 B = 1344 B
  per particle per turn, all but the per-call constants of 1.282 GiB/turn --
  and removed with an
  isbits slice carrier; the before/after thread curve at the production point,
  the unmoved digest, the pin shown to fail unfixed, the neighbour audit),
  [`weak_strong_cuda_luminosity_2026_08_11.md`](history/weak_strong_cuda_luminosity_2026_08_11.md),
  [`paper_package_migration_2026_08_12.md`](history/paper_package_migration_2026_08_12.md)
  (the `paper/` reproduction package moved to its own public repository —
  what went where, the hard-coded-path finding in the claim verifier, and
  the supersession relationship to the frozen submission snapshot),
  [`neighbour_audit_2026_08_18.md`](history/neighbour_audit_2026_08_18.md)
  (over the curved-girder and luminosity-unification series plus the owner's
  production verification: a misaligned parent of a rolled sub-line crashed
  on a missing `_inner_method` twin, and a nested sub-line's `ref_tilt` was
  invisible to both geometry walkers while tracking rolled it -- both fixed
  and pinned against the flat spellings at 0.0),
  [`neighbour_audit_2026_08_18_b.md`](history/neighbour_audit_2026_08_18_b.md)
  (over the run-artifact step-4 campaign -- writer retirement, the
  `TaskOutput` reader, capacity unification: the weak-strong finalize-order
  twin verified clean after the strong-strong bug the example testset
  caught, eight stale-prose sites narrating the retired text machinery
  fixed in place, orphan and retired-symbol sweeps clean, and the
  gate-verdict lesson recurring as a masked wrapper exit code),
  [`neighbour_audit_2026_08_16.md`](history/neighbour_audit_2026_08_16.md)
  (over the keystone/U9-2/PTC/U4-1/restructure series plus a repository
  findability pass: `alternatives` was machine-readable but invisible in
  `element_help`, a docstring contradicted its own one-commit-old repair, a
  stale PTC case count, ~45 moved-ledger references swept, and the frozen
  archive's 47 relative links retargeted; solver-option contract and solenoid
  checked clean),
  [`neighbour_audit_2026_08_14_b.md`](history/neighbour_audit_2026_08_14_b.md)
  (second same-day audit, over the floor-plan/ledger/wiring series: the
  accelerating kind lacked the hidden-cavity tripwire its ring sibling had
  — probed, fixed, pinned; the patch's geometric step and tracking map
  verified as one transformation at 7e-18 in both conventions and pinned;
  the wrong-probe parallax detour kept as the instructive part),
  [`neighbour_audit_2026_08_14.md`](history/neighbour_audit_2026_08_14.md)
  (targeted neighbour audit of the survey/velocity-slip/Scope-B campaign:
  campaign-wide properties re-run at final HEAD — MAD-X survey deviation
  0.0, backend consistency 2.8e-16, the F16 ring physics — the per-fix
  walks with their probes, one fixed finding (the wrapper-recursion refusal
  had landed without a pin), and the priced/ledgered remainder),
  [`neighbour_audit_2026_08_11.md`](history/neighbour_audit_2026_08_11.md)
  (the campaign's targeted neighbour audit: the bitwise pin re-run at final
  HEAD, the no-full-array-D2H property walked to every per-turn diagnostic
  surface — two ledgered findings, the legacy moment observers and BPM path
  mode, both the campaign's own defect class alive in unchanged siblings —
  and the gate-verdict process lesson)
  (why 20–55% GPU utilization at 1M weak-strong particles was a duty-cycle
  symptom, not kernel quality: the per-turn 8 MB host-side luminosity
  reduction and CuArray churn removed — device reduction + per-element buffer
  reuse, coordinates pinned bit-identical, luminosity within 1 ulp, ~2.2×
  projected at the A100 production point; also the repair of the
  backend-consistency validation script the U14-4 invariant had silently
  broken).
- Benchmark histories:
  [`cpu_benchmark_history.tsv`](history/cpu_benchmark_history.tsv)
  (one appended row per solver per run of
  `profiling/nightly_benchmark.sh` — datetime, commit, host, thread count,
  median/min/max s/collide, GC seconds, CPU seconds, thread utilisation,
  allocation and the coordinate digest. It is the *timing* half of the
  performance guard: the suite asserts allocation, because a wall-clock bound
  in `runtests.jl` would abort the whole gate on one flake, so a kernel that
  gets slower without allocating shows up here as a trend instead. The runner
  ships INERT and is opt-in per machine — scheduled long-running jobs are not
  permitted on the 128-thread box, the same directive that removed the nightly
  suite gate on 2026-08-07),
  [`solver_matrix_2026_08_08.md`](history/solver_matrix_2026_08_08.md)
  (every solver × both backends × both precisions at the production point,
  one protocol: timing, physics agreement, the CPU-Float32 grid-typing
  regression it caught and the fix, and the 16-thread CPU baselines the
  thread-optimization campaign starts from),
  [`strong_strong_pic_extreme_benchmark_history.md`](history/strong_strong_pic_extreme_benchmark_history.md),
  [`strong_strong_diagnostics_benchmark_history.md`](history/strong_strong_diagnostics_benchmark_history.md).
- Audits / change records:
  [`neighbour_audit_2026_08_10.md`](history/neighbour_audit_2026_08_10.md)
  (second pass over the CPU-threading campaign, end to end: verifies
  structurally — not just by digest — that no interaction writes its source,
  which is what the in-place slice kick rests on; re-runs the digest property on
  all four solvers; walks the three shared surfaces the campaign changed out to
  their CUDA and sibling users; and records a runner that reported success on a
  total failure, plus an orphan sweep of its own that reported thirteen false
  positives),
  [`neighbour_audit_2026_08_09.md`](history/neighbour_audit_2026_08_09.md)
  (targeted neighbour audit of the CPU-threading campaign — organised around
  what concurrent pair batching newly makes load-bearing rather than around the
  diff: slice-index disjointness, the global lattice-Green memo, workspace
  exclusivity, and the pool-vs-policy worker count; includes the measured
  negative result on per-batch worker allocation),
  [`neighbour_audit_2026_08_07.md`](history/neighbour_audit_2026_08_07.md)
  (targeted post-campaign audit of the 2026-08-07 ten-fix session's blast
  radius — "a fix's neighbours are where the next defect is", applied to the
  campaign that re-learned it: two neighbour defects fixed in the closing
  commit, six more verified, priced and opened as todo rows, and the swept
  surfaces recorded clean),
  [`comprehensive_audit_2026_08_04.md` part 1](history/comprehensive_audit_2026_08_04.md#part-1)
  (repository audit against the Phase 0-18 protocol: **seven confirmed defects
  fixed**, every one of them with a passing test asserting the right invariant.
  Three are concurrency bugs invisible to a single-threaded suite — the aperture
  loss counter under-reporting by 53% at eight workers, and **two instances of
  one Julia closure-capture trap** that silently corrupted the DEFAULT
  `:equal_area` slice boundaries and the strong-strong luminosity accumulator on
  any multi-threaded run. Read §3 for the mechanism (`if` does not open a scope
  in Julia, `for` does, so a name shared between a `do` block and its enclosing
  function is one `Core.Box` shared by every spawned worker) and for why the
  sweep must search lowered code rather than text. The other two are
  curved-frame kicks that are not gradients, governed by the Cauchy-Riemann
  condition `Im f == 0` derived there. Carries an explicit coverage ledger
  recording that only ~19% of `src/` was read line by line and that every CUDA
  path is unaudited),
  [`comprehensive_audit_2026_08_04.md` part 2](history/comprehensive_audit_2026_08_04.md#part-2)
  (second pass, resuming that handoff's priority order: **thirteen confirmed
  defects fixed**, none of them a physics error -- five over the declared scope,
  eight more surfaced by building the solver-option contract the first pass had
  identified as missing. **It opens with a "Start here" block naming the three
  sections a new session should read and the ones to skip; follow it rather than
  reading either audit front to back.** Where part 1 found code that was wrong
  under threads, this pass found **configuration that was accepted, reported as
  active, and never used** — `GaussianPICPoissonSolver` silently discarded every
  CUDA launch override *and* the policy thread count, because it composes a
  `PICPoissonSolver` rather than subtyping it and the installer tested `isa`,
  while `configuration_report` reported the discarded value as `resolved`. Read
  §1 for the sibling rule to part 1's — audit for values that are *declared and
  never read* — and §13.3 for the missing `SolverOptionEffectivenessContract`
  that would have caught two of the first five mechanically -- it was then built
  in that same session, and finding the rest is what took the count to thirteen. Also: all three named
  virtual drifts measured symplectic with an unsafe-drift negative control, the
  Bassetti-Erskine kick verified against brute-force integration across all four
  branches at ~5e-14, and `beam_statistics` measured and made 39.8% faster
  bit-identically. Coverage ledger: ~21% of `src/` this session, ~46% across
  both),
  [`comprehensive_audit_2026_08_04.md` part 3](history/comprehensive_audit_2026_08_04.md#part-3)
  (third pass, scoped to `src/tasks/strongstrong/pic_cpu.jl` read in full —
  the CPU reference every parity contract validates the CUDA paths against.
  **Three confirmed defects fixed, and the headline one is the scenario that
  scoping warned about**: the default Green cache expands the mesh with the node
  count fixed, which changes the cell size and destroys the integer-cell
  alignment `green_type = :lattice` is tabulated by, so the kernel was that of a
  source **displaced by 0.400 cells** — and both backends expanded identically,
  so CPU/CUDA parity passed at 1e-13 on the displaced field while the only
  analytic field validation bypasses the cache entirely. Read §1 for the third
  rule in the series, after part 1's "checks never executed" and part 2's "values
  never read": **audit for invariants one function establishes and another
  quietly breaks.** Also: a `dropped`-particle counter written by one line and
  read by nothing under a "Never silent" comment, and `grid_extent` accepted and
  bit-identically ignored under two of three mesh modes. §7 keeps two hypotheses
  this pass raised and its own measurements refuted, including a loop-order
  "optimization" that measured 0.99x. The luminosity path is verified against the
  closed-form Gaussian overlap with clean second-order convergence.
  **§10 is a same-day follow-up** that closed the one question the handoff left
  open and found a fourth, larger defect doing it: the lattice Green function's
  periodic box was sized in *index* units, so at the 11:1 production aspect ratio
  `:lattice` was **10.3x worse** than the default kernel it exists to improve on,
  and got *worse* with grid refinement. Read §10.6 — the same blind spot, a check
  that cannot distinguish anything at aspect ratio 1, has now produced two
  separate defects in this one file),
  [`comprehensive_audit_2026_08_04.md` part 4](history/comprehensive_audit_2026_08_04.md#part-4)
  (fourth pass, `pic_cuda.jl` l. 1-2260 read in full plus three whole-file sweeps.
  **Zero defects, and that is the result** — the pass tested a specific hypothesis
  carried over from part 3, that the CUDA path had inherited more of the CPU's
  defects the way it inherited S14, and the hypothesis failed. Read §1 for the
  map it followed: parity is *strong* wherever the two backends compute something
  independently and *blind* wherever they share a mistake, so every check that
  could be anchored to an external reference was — the CUDA luminosity against the
  closed-form Gaussian overlap at three aspect ratios, the duplicated device
  weight functions against their CPU twins over 200,000 randomised samples. Also
  closes the then-standing ledger item on CUDA concurrency (archived): a `Core.Box` census over
  288 methods, clean. §4 is the most useful section — three claims this pass made
  and then withdrew, including a beam-swap that came within one step of being
  filed as a Major finding on the production route and was simply a misreading of
  an argument list ordered by two opposite conventions.
  **§7-8 extend the pass to the field solvers**, taking `pic_cuda.jl` to 60%
  covered and still zero defects. That region was settled by *measurement* rather
  than by reading a plane layout: the layout is CUDA-only, so parity is decisive
  there, and it measures 1e-15 against a 1e-5 signal — 10 orders of discriminating
  power where the suite asserts only 1e-11. §8 adds two non-defect findings, both
  fixed and both of the shape every confirmed defect in parts 3-4 had — a correct
  result resting on something unstated: an invariant the field derivative depends
  on that no test asserted, and a suite that reports green while silently skipping
  every GPU test on a GPU-less CI),
  [`comprehensive_audit_2026_08_04.md` part 5](history/comprehensive_audit_2026_08_04.md#part-5)
  (fifth pass, the CUDA **device kernels** l. 3470-5040, taking `pic_cuda.jl` to
  ~87% covered. **One confirmed defect, S18 — and it is part 2's S1 all over
  again**: `CUDAPICLaunchConfig` is completely inert on a bare `collide!`,
  measured at **0** `:cuda_pic_launch` receipts against **12** for the identical
  solver through a `StrongStrongTask`, with the device max-threads validation
  skipped alongside. Unlike S1 it is not a bug in any function -- the
  configuration is inert because of *where resolution lives*, and nothing on the
  `collide!` path was obliged to notice. Read §4 for the tree-reduction analysis:
  at 100 threads the luminosity reduction silently drops 36 of 100 elements, the
  two `ispow2` guards that prevent it were **exercised by no test at all**, and on
  the bare path the invariant is held only by an unasserted literal sitting in a
  different function from both guards. §6 corrects part 1's record, which named
  two of the three exits from `_cuda_pic_threads` and omitted the one S18 lives
  in. §2 is candid that most of this region was read by sub-agents rather than by
  me, and which conclusions rest on measurement instead),
  [`comprehensive_audit_2026_08_04.md` part 6](history/comprehensive_audit_2026_08_04.md#part-6)
  (sixth pass, ~5,000 lines across `slicing.jl`, the CUDA slicing and Gaussian
  sequential paths, `BeamObservers.jl`, `Knobs.jl`+`symbolic.jl` and
  `spectral_cuda.jl`, read by five sub-agents on disjoint regions.
  **This pass found more than the previous three combined, and most of it is
  deliberately NOT fixed.** Two were reproduced and fixed: **S20**, the CUDA
  spectral Dirichlet box ignoring `allow_lost_particles` and sizing itself
  **100x** too large from dead particles — every slice pair then saw a different
  mesh — and S19, a diagnostic that reported "0 of N macroparticles have a
  non-finite coordinate", asserting what its own scan had just disproved. Eight
  more (§5) are recorded with reproductions and left unverified, headed by CUDA
  `:equal_count` slicing that is not equal-count when z has ties (27% error in a
  slice weight, and slice weights multiply `kbb` directly). Read **§6** for why
  the line falls there: agent output is a lead, not a finding, and this session's
  measured hit rate is ~60% — several agent claims dissolved on checking, and one
  was *broader* than reported, which is the argument for re-deriving rather than
  trusting. The ledger is explicit that `spectral.jl` remains **completely
  unaudited** after its agent was stopped mid-read — a claim §0's own history
  note then corrects: the agent resumed and finished, so the file IS covered),
  [`comprehensive_audit_2026_08_04.md` part 7](history/comprehensive_audit_2026_08_04.md#part-7)
  (seventh pass, the last ~4,100 unaudited lines — `gaussian_pic.jl`,
  `gaussian_pic_cuda.jl`, `Tasks.jl`+`BPMObserver.jl`, `Knowledge.jl`+
  `Registry.jl` — read by four sub-agents; **with this pass every line of
  `src/` has been read by someone**, with provenance kept explicit. 26 claimed
  findings, deliberately recorded as a QUEUE rather than a findings list
  because none was independently verified, headed by an unchecked
  `@inbounds`/`CUDA.@atomic` write past the end of a loss-count vector and a
  knob epoch that never fires for `BeamLine` tasks. The metadata-lie
  hypothesis landed hardest: the element validator caught **1 of 13 injected
  defects**, and `RBendSpec` — exported, PTC-validated — had no `ElementMeta`
  at all, so `element_help` confidently reported no contracts and an invented
  kind),
  [`comprehensive_audit_2026_08_04.md` part 8](history/comprehensive_audit_2026_08_04.md#part-8)
  (eighth pass: the verify-and-fix phase part 7's queue was written for.
  **T1, T3, T4, T5, K1, G1 all reproduced and fixed**, each with a negative
  control showing the new test fails on the pre-fix source, under a
  behavioural fingerprint that is bit-identical except the intended
  `element_help(RBendSpec)` change. Two corrections to the queue's own
  analysis: the T-items' "one root cause" was really two mechanisms, and G1
  hit every non-Float64 rep, not only mixed precision. §5 records two defects
  in the session's own probes — a closure that silently swallowed the very
  `BoundsError` the probe existed to catch is the one to remember),
  [`comprehensive_audit_2026_08_04.md` part 9](history/comprehensive_audit_2026_08_04.md#part-9)
  (ninth pass: everything left in the queue except two performance items --
  24 findings from parts 6 and 7 verified and settled. T6's crashed-`execute!`
  now delivers its loss artifacts and retries without duplicate turn labels;
  T2's backend-blind loss record reallocates; the BPM noise key is pure and
  per-reading; the metadata validator now compiles every example to a declared
  runtime type, and the injected liar that once validated clean fails on three
  counts; the Symbolics adapter finally activates in package mode via a
  `[weakdeps]` extension. Sections 3-4 are the pass's own discovery: the
  spectral Dirichlet box is sized pre-collision while deposits happen after
  intra-collision kicks, and the new dropped-charge tripwire immediately
  caught **83% of a slice silently discarded** under strong kicks -- with the
  same overflow reaching `:grid_free` as a silent -1x mirror, now guarded.
  Section 6 records this session's own errors, including a `git checkout`
  that destroyed uncommitted fixes. A same-day follow-up in Section 7
  closed R8 and R12 as well -- the CUDA :equal_area histogram 18x faster
  via one atomic kernel pass, bit-identical to a per-bin-mask oracle, and
  the transverse spectral path down from 2*n1*n2 to n1+n2 solves with
  kicks captured bit-identical -- so the parts 6-7 queue is fully closed),
  [`comprehensive_audit_2026_08_05.md`](history/comprehensive_audit_2026_08_05.md)
  (full 50,330-line re-read at `6a3f39a`, one driving session: every `src/`,
  `test/`, `examples/`, `validation/` line read (21 briefed agent units +
  auditor-direct reads, provenance ledgered), **20 findings fixed (F1–F20)**
  — headed by a test tolerance that had aborted every full-suite run since
  `baf0255` (masking the CUDA half, examples, and append testsets), a torn-
  write/append protocol rebuilt against crash cases, `interaction_grid=:node`
  silently degrading on CUDA with a diagnostic flag changing physics, the
  straight solenoid un-differentiable and `curved=false` non-gradient, the
  RF cavity's slip factor missing `-1/γ₀²` (model boundary now documented,
  fix priced), context-dropping element wrappers, and a Philox
  implementation nothing pinned (now KAT-gated). Carries the full coverage
  ledger with per-unit provenance, the seam map, corrections to the audit's
  own analysis, and a ~40-item priced open queue; the 21 per-unit agent
  reports the queue's file:line details live in are archived beside it under
  [`comprehensive_audit_2026_08_05_unit_reports/`](history/comprehensive_audit_2026_08_05_unit_reports/)
  — they were session-scratch until the post-campaign queue session found
  the queue unactionable without them),
  [`comprehensive_audit_2026_08_05_b.md`](history/comprehensive_audit_2026_08_05_b.md)
  (second full re-read the same day, at `7de4d81`, uniform depth at the
  owner's direction. Its reason for existing: the prior pass declared commit
  `6a3f39ab`, and HEAD was **63 commits and +9,125/−775 lines** beyond it —
  the prior audit's own fix campaign and queue-closure session, i.e. the code
  written *in response to* findings, which no audit had since read, with the
  largest deltas in `test/runtests.jl` (+1,294), `BeamObservers.jl` (+331),
  `interface.jl` (+247) and an entirely new `test/nightly_suite.sh`.
  Per-unit agent reports and the pre-modification behavioural fingerprint
  harness plus its baseline are archived beside it under
  [`comprehensive_audit_2026_08_05_b_unit_reports/`](history/comprehensive_audit_2026_08_05_b_unit_reports/)),
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
- **Development rules for humans and AI agents** → `AGENTS.md` (invariants,
  task routing, verification matrix) and the guides in `guides/`.

