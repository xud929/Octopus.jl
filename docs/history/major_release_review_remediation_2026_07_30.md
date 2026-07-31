# Major-Release Review and Remediation Record - 2026-07-30

## Executive Summary

This record closes the independent pre-release review performed in the
2026-07-30 session. The review covered the reachable Julia implementation under
`src/`, its CPU-threaded and CUDA paths, public construction/registry behavior,
tests, validation programs, examples, and code-facing theory documentation.
Generated result data were treated as evidence, not as source implementation.
No MPI or OpenMP implementation is present in the reviewed source tree; the
parallel review therefore covered Julia threading, task concurrency, and CUDA.

**Recommendation before remediation: Major Revision Required.**

The initial tree contained silent scientific-correctness failures in analytic
Gaussian fields and moment reductions, dimensionally invalid numerical
fallbacks, a singular GaussianPIC reference path, lost absolute turn state,
unchecked non-symplectic linear maps, shared mutable solver workspaces, excessive
CUDA workspace retention, and inconsistent radiation controls.

**Recommendation after remediation: Accept with Minor Revision.**

All identified implementation issues were fixed, tested, committed separately,
and pushed to `main`. The final tree passes the complete package suite and the
targeted scientific validation matrix listed below. "Minor Revision" is retained
because publication-grade use still requires study-specific convergence,
independent external-code comparison, and hardware coverage beyond the one
available NVIDIA GPU. Those are validation scope limits, not known open defects
in the remediated code.

| Assessment | Before | After |
| --- | ---: | ---: |
| Production readiness | 55% | 86% |
| Scientific reproducibility | 68% | 89% |
| Technical debt | High | Medium |
| Review confidence | - | High (94%) |

The post-remediation scores do not mean that every physical model is universally
validated. PIC remains a conventional non-symplectic discretization, boxed
spectral accuracy remains domain- and resolution-dependent, and CUDA atomic
deposition can differ at roundoff level across executions.

## Scope and Method

The review used four complementary checks:

1. Line-by-line inspection of algorithms, boundary handling, numerical scales,
   method dispatch, cache ownership, and CPU/CUDA parity.
2. Independent re-derivation of the near-round Gaussian transition, moment
   identities, covariance rank criterion, radiation equilibrium noise, and
   canonical symplectic condition.
3. Deterministic regressions targeting the discovered failures, followed by the
   complete package test suite.
4. End-to-end validation and A/B timing with the strong-strong example,
   `MomentObserver`, luminosity output, CPU threads, and CUDA.

The primary hardware used for CUDA validation was an NVIDIA RTX 4500 Ada
Generation GPU. Julia 1.12 and `JULIA_NUM_THREADS=4` were used for the final
validation commands unless a recorded production benchmark states otherwise.

## Finding Status

| ID | Original severity | Finding | Status | Commit |
| --- | --- | --- | --- | --- |
| M1 | Major | Round/near-round analytic Gaussian instability | Resolved | `12dca5a`, `4d48f88`, `4ed17df`, `5d31308` |
| M2 | Major | Catastrophic cancellation in strong-strong moments | Resolved | `ee16bc4` |
| M3 | Major | Machine epsilon used as a physical length | Resolved | `567db53` |
| M4 | Major | Singular GaussianPIC control-variate reference | Resolved | `5f9f17f` |
| M5 | Major | Task execution reset the absolute turn | Resolved | `bcb7e36` |
| M6 | Major | `Linear6D` accepted non-symplectic maps | Resolved | `66a3648` |
| M7 | Major | Shared spectral workspaces were not reentrant | Resolved | `ec86c34` |
| P1 | Moderate | CUDA PIC retained every wavefront size | Resolved | `a3d3b62` |
| N1 | Moderate | Radiation method/flag and input semantics disagreed | Resolved | `855dd90` |

No identified major, moderate, or minor implementation issue remains open at
the end of this session.

## 1. Major Issues

### M1. Round and Near-Round Gaussian Evaluation

- **Severity:** Major, resolved.
- **Files:** `src/elements/strong_beam.jl`,
  `src/track/strong_beam_track.jl`,
  `src/tasks/strongstrong/gaussian_pic.jl`,
  `src/tasks/strongstrong/gaussian_pic_cuda.jl`.
- **Functions:** round radial factor, Bassetti-Erskine field/response
  evaluators, near-round potential/force evaluator, coupled Gaussian consumers.
- **Explanation:** The round formula evaluated `1 - exp(-u)` directly and lost
  the force near the axis. The elliptical formula becomes ill-conditioned as
  the two covariance eigenvalues approach equality, while the former fixed
  threshold selected a hard round/flat branch without a precision or response
  error derivation. The uncoupled and coupled paths also used different
  anisotropy measures. A generic fallback assigned uncalibrated behavior to
  arbitrary `AbstractFloat` types.
- **Why it matters:** A zero or inaccurate core gradient changes the linear
  beam-beam tune shift. A hard or inconsistent switch can inject force,
  Hessian, and longitudinal-kick artifacts as beam aspect ratio evolves.
- **Suggested fix:** Use `expm1` and a core series for the round factor; use
  invariant covariance anisotropy; derive a precision-scaled overlap; blend at
  potential level so force and covariance response remain consistent; reject
  numeric types without a validated calibration.
- **Implemented fix:** The code now uses a third-order near-round potential
  expansion, quintic blend, a separate error-balanced near-axis series, and
  calibrated conditioning factors 64 (`Float64`) and 8 (`Float32`). Unsupported
  floating types raise an explicit error. The full derivation is in
  `docs/theory/near_round_bassetti_erskine_switch.md`.
- **Verification:** The final sweep measured maximum transition force relative
  errors `4.7557e-6` (`Float32`) and `6.1096e-12` (`Float64`), natural-scale
  response errors `1.4771e-5` and `3.1170e-11`, and core-gradient errors at the
  respective arithmetic floors. The `Float64` six-dimensional symplectic
  residual was `1.6001e-10`. CUDA natural-scale differences were `1.0541e-5`
  (`Float32`) and `1.9150e-11` (`Float64`).

### M2. Unstable Strong-Strong Moment Reductions

- **Severity:** Major, resolved.
- **Files:** `src/tasks/strongstrong/slicing.jl`,
  `src/tasks/strongstrong/gaussian_pic.jl`,
  `src/tasks/strongstrong/gaussian_pic_cuda.jl`,
  `src/tasks/strongstrong/pic_cpu.jl`,
  `src/tasks/strongstrong/pic_cuda.jl`.
- **Functions:** CPU slice moments, fused CUDA Gaussian moments,
  GaussianPIC source moments, PIC sigma-extent reductions.
- **Explanation:** Variance and covariance were formed from raw moments such as
  `E[x^2] - E[x]^2`. For `1e8 +/- 1` in `Float64`, the implementation returned
  zero variance instead of one.
- **Why it matters:** Silent loss of spread can collapse a Gaussian source,
  corrupt coupled covariance and longitudinal response, or choose the wrong
  `grid_extent=:sigma` mesh.
- **Suggested fix:** Preserve parallel reductions while shifting every sample
  by one in-sample anchor before accumulating first and second products.
- **Implemented fix:** CPU chunks and CUDA blocks now accumulate shifted
  moments with a common anchor. The final variance/covariance subtraction occurs
  at the physical spread scale and uses `muladd` where supported. Welford was
  rejected because its loop-carried dependency would degrade the existing CPU
  vector and GPU reduction structure.
- **Verification:** Exact cancellation regressions recover the constructed
  variances and covariances in `Float32` and `Float64`; 96 CPU and 48 CUDA
  assertions were added. Production 200-turn A/B runs with per-turn HDF5 moments
  measured PIC `0.28825 -> 0.28627 s/turn` mean and Gaussian
  `0.24769 -> 0.24910 s/turn` mean. State differences were at roundoff scale.
  See `docs/history/stable_strong_strong_moments_2026_07_30.md`.

### M3. Dimensionless Epsilon Used as a Physical Scale

- **Severity:** Major, resolved.
- **Files:** `src/tasks/strongstrong/interface.jl`,
  `src/tasks/strongstrong/pic_cpu.jl`,
  `src/tasks/strongstrong/pic_cuda.jl`,
  `src/tasks/strongstrong/spectral.jl`,
  `src/tasks/strongstrong/spectral_cuda.jl`.
- **Functions:** solver constructors, PIC adaptive grids and Green self-cell,
  spectral domain construction, Gaussian minimum sigma handling.
- **Explanation:** Machine epsilon was used as a fallback transverse size or
  domain width. Epsilon is dimensionless and changes with arithmetic precision;
  it cannot define a physical beam length.
- **Why it matters:** Results for degenerate distributions depended on `Float32`
  versus `Float64` for a reason unrelated to beam physics, and tiny artificial
  domains could amplify fields or create invalid cell areas.
- **Suggested fix:** Default to no artificial physical floor, expose physical
  lower bounds with units inherited from particle coordinates, and reject a
  degenerate problem when the data and user input provide no valid scale.
- **Implemented fix:** `min_sigma`, `min_transverse_extent`, and
  `min_domain_halfwidth` are explicit validated user inputs with zero defaults.
  The node-sampled Green self-cell uses the analytic finite-cell average instead
  of an epsilon radius.
- **Verification:** New constructor, zero-width, and CPU/CUDA tests pass.
  `validation/high_energy_weakstrong_limit.jl` passes for Gaussian, PIC, and both
  spectral formulations; the final PIC luminosity error was `0.0030101`, and
  both spectral strong/frozen-source limits agreed below `3e-16` relative.

### M4. Singular GaussianPIC Reference

- **Severity:** Major, resolved.
- **Files:** `src/tasks/strongstrong/gaussian_pic.jl`,
  `src/tasks/strongstrong/gaussian_pic_cuda.jl`.
- **Functions:** `_gpic_correlation`,
  `_gpic_coupled_covariance_resolved`, `_gpic_control_variate_mode`,
  CPU and CUDA directed interaction paths.
- **Explanation:** Positive marginal variances were treated as sufficient for a
  coupled Gaussian reference. A rank-one covariance has positive marginals but
  zero conditional variance, making the conditional subtraction singular.
  Zero-width and too-small samples were not handled consistently on every route.
- **Why it matters:** The residual grid can receive unresolved narrow structure
  while the analytic add-back becomes singular, producing non-finite or
  route-dependent fields.
- **Suggested fix:** Decide one mode per directed interaction and fall back to
  ordinary PIC whenever the analytic reference is undefined.
- **Implemented fix:** The coupled reference requires
  `1 - rho^2 > sqrt(eps(T))`, evaluated with `muladd`. Too few particles,
  non-finite/zero marginal widths, or unresolved covariance select ordinary
  PIC on CPU and every CUDA route. The sequential fallback preserves the
  configured Green cache.
- **Verification:** 19 CPU and 49 CUDA singular-reference assertions pass.
  `gaussian_pic_field_validation.jl` and
  `gaussian_pic_bigaussian_validation.jl` reproduce the documented accuracy
  tables. A 200-turn timing comparison changed by `+0.331%` mean and `-0.133%`
  median, within observed noise; moment files remained valid.

### M5. Absolute Turn State Was Lost Across `execute!`

- **Severity:** Major, resolved.
- **Files:** `src/tasks/Tasks.jl`,
  `src/tasks/strongstrong/interface.jl`.
- **Functions:** `TrackingTask`, `StrongStrongTask`, and both `execute!`
  workflows.
- **Explanation:** Each invocation restarted the local turn at zero. Schedules,
  output turn labels, counter-RNG inputs, and diagnostics therefore differed
  between a continuous run and checkpoint-style chunked execution.
- **Why it matters:** `execute!(turns=7)` and `execute!(turns=3)` followed by
  `execute!(turns=4)` were not the same stochastic experiment. This invalidates
  reproducible restart and can overwrite or duplicate scheduled observations.
- **Suggested fix:** Store the next absolute turn on each task, advance it only
  after successful completion, and provide an explicit restart override.
- **Implemented fix:** Both tasks own `next_turn::Ref{Int64}`.
  `start_turn=nothing` continues automatically; a nonnegative `start_turn`
  explicitly resets checkpoint/restart position. Negative inputs and overflow
  are rejected.
- **Verification:** Seven-turn continuous and `3+4` chunked stochastic
  `TrackingTask` states are bit-identical. Six-turn continuous and `2+4`
  strong-strong collision/radiation states are bit-identical. Output schedules
  and observer turn labels use absolute turns. A 200-turn Gaussian timing check
  changed `-0.104%` mean and `-0.078%` median.

### M6. `Linear6D` Accepted Non-Symplectic Matrices

- **Severity:** Major, resolved.
- **Files:** `src/elements/linear6d.jl`.
- **Functions:** `Linear6DSpec`, `Linear6D`, raw `ElementSpec` normalization.
- **Explanation:** Any finite 6x6 matrix could be compiled under
  `Symplectic6DMap`, including determinant-one matrices that violate
  `M' J M = J`. Raw Julia matrices were also flattened in column-major order
  where the parameter normalization expected row-major ordering.
- **Why it matters:** A matrix labeled symplectic could create artificial
  emittance change and invalidate conservation arguments without warning.
- **Suggested fix:** Reject non-symplectic matrices at both friendly and runtime
  construction boundaries and normalize raw matrix layout explicitly.
- **Implemented fix:** The canonical residual is checked with a componentwise
  forward-error bound proportional to the actual matrix-product magnitude.
  This accepts valid reciprocal scalings without using an excessively loose
  global norm. Non-finite and non-symplectic matrices are rejected, including
  raw-spec bypasses.
- **Verification:** 17 new `Float32`/`Float64` assertions cover identity,
  reciprocal scaling, canonical shear, determinant-one noncanonical shear, raw
  specs, and coupled optics. Final finite-difference validation reports
  `1.5021e-13` residual against `5e-7` tolerance.

### M7. Solver Workspace Reentrancy and Device Ownership

- **Severity:** Major, resolved.
- **Files:** `src/tasks/strongstrong/spectral.jl`,
  `src/tasks/strongstrong/spectral_cuda.jl`,
  `src/tasks/strongstrong/pic_cuda.jl`.
- **Functions:** CPU/CUDA spectral workspace acquisition/release and CUDA PIC
  task workspace keying.
- **Explanation:** Cached mutable spectral workspaces could be handed to
  concurrent executions. CUDA cache identity omitted device id, so a task reused
  after a device change could retain arrays, streams, and plans from the old
  device.
- **Why it matters:** Concurrent writes can race silently. Cross-device reuse
  can fail at launch or operate on the wrong CUDA context.
- **Suggested fix:** Lease workspaces exclusively and include device identity in
  every persistent CUDA workspace key.
- **Implemented fix:** CPU and CUDA spectral caches are exclusive lease pools.
  CUDA release records an event on the active stream; the next borrower waits
  from its own stream without a host-wide synchronization. PIC task keys include
  current device id.
- **Verification:** Two simultaneous CPU spectral collisions acquire distinct
  workspaces and match sequential references (29 assertions). CUDA lease and
  device-key tests pass (8 assertions), and all 39 CUDA spectral parity checks
  pass. A 200-turn spectral benchmark changed `+0.109%` mean and `+0.021%`
  median, with identical final RMS/moment file sizes.

## 2. Moderate Issues

### P1. CUDA PIC Wavefront Cache Retained Every Batch Size

- **Severity:** Moderate performance/robustness issue, resolved.
- **Files:** `src/tasks/strongstrong/pic_cuda.jl`,
  `src/tasks/strongstrong/gaussian_pic_cuda.jl`.
- **Functions:** `_cuda_pic_wavefront_workspace!`,
  `_cuda_pic_wavefront_node_workspace!`,
  `_cuda_pic_reserve_wavefront_workspaces!`.
- **Explanation:** A 15-slice collision cached exact arrays for all 15 frontier
  sizes. Retained storage scaled with the sum of frontier sizes, approximately
  quadratic in slice count, instead of the maximum active frontier.
- **Why it matters:** The default 128x128 case retained about 0.8 GiB in these
  entries alone and increased allocator pressure. Larger grids/slice counts
  could exhaust device memory.
- **Suggested fix:** Reserve a single maximum-capacity buffer per layout and
  pass exact-shape prefix views to unchanged kernels and FFT calls.
- **Implemented fix:** One standard workspace is retained, plus one node
  workspace only for node/quadratic paths. Exact prefix views preserve the FFT
  batch shape and operation order. Capacity changes synchronize only when an
  existing live allocation must be replaced.
- **Verification:** Cache entries fell from 15 to 1 for the production-shaped
  15-slice run. First-turn CUDA pool use fell from `1.181 GiB` to
  `551.7 MiB`; reserved memory fell from `1.562 GiB` to `960 MiB`. In a matched
  50-turn A/B, turns 11-50 improved from `0.132725/0.129246` mean/median to
  `0.124088/0.120888 s`, about 6.5%. Moment histories differed by at most
  `5.44e-18` absolute and luminosity by `4.09e-13` relative.

### N1. Radiation Method and Flag Semantics

- **Severity:** Moderate scientific-configuration issue, resolved.
- **Files:** `src/elements/radiation.jl`,
  `src/track/radiation_track.jl`.
- **Functions:** `LumpedRad`, `_track_lumped_rad_particle`,
  method-specific CPU/context dispatch, legacy CUDA radiation tracking.
- **Explanation:** `Damping6DMap()` could force damping even when
  `is_damping=false`, while its early return inspected unrelated stored flags.
  Invalid damping times silently disabled the element. Excitation used
  `sqrt(1 - exp(-1/tau)^2)`, which suffers cancellation and becomes zero for
  long `Float32` damping times.
- **Why it matters:** Configuration did not reliably describe applied physics,
  bad inputs could turn radiation off silently, and low-precision equilibrium
  noise was biased.
- **Suggested fix:** Make method tags strict component masks, preserve enable
  flags inside the mask, reject invalid inputs, and compute the variance with
  `expm1`.
- **Implemented fix:** `Radiation6DMap` permits both components,
  `Damping6DMap` only damping, and `Diffusion6DMap` only excitation.
  `is_damping`/`is_excitation` then enable the permitted component. Damping
  turns must be positive (`Inf` is the exact no-damping limit); optics and
  transforms must be finite; beta must be positive; sigma signs must
  consistently enable or disable excitation. Noise uses
  `sqrt(-expm1(-2/tau))`.
- **Verification:** 18 new semantic/numerical assertions pass, including the
  `Float32 tau=1e8` case where damping rounds to one but excitation remains
  `1.4142136e-4`. CPU/GPU tracking consistency passes with global relative
  error `9.4224e-16`. The isolated 500k-particle CUDA radiation kernel changed
  only `+0.011%` in median time. A 200-turn strong-strong A/B differed by at
  most `1.04e-15` in moment data and `4.34e-11` in luminosity.

## 3. Minor Issues

No separate minor defect remains open. Two minor correctness details were fixed
inside the major work:

- Raw `Linear6D` Julia matrices now use the intended row-major parameter order.
- Near-round evaluation now raises for uncalibrated floating types instead of
  guessing thresholds; validated `Float32` and `Float64` consumers are
  unaffected.

## 4. Performance Opportunities

These are measured or documented opportunities, not release-blocking defects.

### CUDA PIC Deposition

- **Severity:** Opportunity.
- **File/function:** `src/tasks/strongstrong/pic_cuda.jl`, atomic deposition
  kernels.
- **Explanation:** Dense PIC remains dominated by atomic deposit and FFT work.
- **Why it matters:** Contention grows with particles per cell and limits GPU
  scaling.
- **Suggested improvement:** Evaluate binned or tiled charge deposition against
  the existing CPU/CUDA parity and emittance-growth validations. Accept only
  after complete-turn timing; kernel-only timing is insufficient.

### CUDA Node-Grid Throughput

- **Severity:** Opportunity.
- **File/function:** CUDA node interaction-grid wavefront preparation and field
  solve.
- **Explanation:** Node mode performs more mesh/field work than the default
  slice-pair mode and remains the leading CUDA performance item in
  `docs/todo.md`.
- **Why it matters:** It limits practical use of the smoother node formulation
  in long strong-strong studies.
- **Suggested improvement:** Reuse node meshes/Green stacks more aggressively
  without changing the documented longitudinal consistency constraints.

### CUDA Pool and Green-Cache Residency

- **Severity:** Opportunity.
- **File/function:** CUDA PIC temporary arrays and slice-pair Green cache.
- **Explanation:** The wavefront leak-like retention is fixed, but the CUDA
  memory pool deliberately reserves freed blocks and persistent Green entries
  can still occupy several GiB during a long adaptive run.
- **Why it matters:** Reserved memory is reusable by Octopus but may reduce
  coexistence with other GPU workloads.
- **Suggested improvement:** Add live-versus-reserved telemetry and a
  user-selectable memory budget/reclaim policy before changing the current
  throughput-oriented default.

### Monolithic CUDA PIC Compilation

- **Severity:** Opportunity.
- **File/function:** `src/tasks/strongstrong/pic_cuda.jl`.
- **Explanation:** The file contains execution routing, caching, bounds,
  deposition, Green construction, FFT, luminosity, kick, diagnostics, and
  Gaussian helpers.
- **Why it matters:** Review and compilation changes have a broad surface, and
  route parity is difficult to reason about locally.
- **Suggested improvement:** Split by stable ownership boundaries after this
  release, preserving internal APIs and route-sweep tests.

## 5. Maintainability Suggestions

1. Keep physical floors named with their coordinate units and never replace
   missing physics with machine epsilon.
2. Centralize covariance rank/positive-definiteness checks when another solver
   needs the same criterion; avoid premature abstraction before that second use.
3. Add an explicit internal workspace interface (`reserve`, `borrow`, `release`)
   shared in naming, not necessarily implementation, across PIC and spectral
   solvers.
4. Keep method tags and boolean feature controls orthogonal: the method defines
   allowed physics; flags enable allowed components.
5. Preserve per-finding benchmark records under `docs/history` and keep
   forward-looking work only in `docs/todo.md`.
6. Continue route-sweep CUDA tests whenever an option is added; several prior
   defects occurred because only the default route consumed a flag.

## 6. Missing Tests and Residual Validation Risk

### Actual Multi-GPU Migration

- **Severity:** Residual test gap.
- **File/function:** CUDA spectral/PIC runtime workspace caches.
- **Explanation:** Device id is tested in keys, but only one physical CUDA
  device was available.
- **Why it matters:** Driver/context behavior during real task migration cannot
  be established by synthetic ids.
- **Suggested test:** Reuse one task across two installed devices and run
  simultaneous solver executions on both.

### Long-Run Memory Plateau

- **Severity:** Residual test gap.
- **File/function:** CUDA allocator, Green cache, FFT plans.
- **Explanation:** Short and 200-turn runs completed, but no automated
  thousands-of-turn assertion distinguishes live allocations from pool
  reservation.
- **Why it matters:** Memory behavior is a production operational constraint.
- **Suggested test:** Record live, pool-used, pool-reserved, cache entries, and
  rebuild counts over a fixed long run with a defined plateau criterion.

### Independent Physics Reference

- **Severity:** Residual scientific validation gap.
- **File/function:** Complete weak-strong and strong-strong workflows.
- **Explanation:** Current validation is strong against analytic limits and
  internal CPU/CUDA references, but this session did not run an independent
  external accelerator code or experimental benchmark.
- **Why it matters:** Shared modeling assumptions can survive internal parity
  checks.
- **Suggested test:** Archive matched decks and compare luminosity, coherent
  modes, equilibrium sizes, and emittance evolution with an independent code.

### Statistical Ensemble Coverage

- **Severity:** Residual scientific validation gap.
- **File/function:** noisy PIC long-term dynamics.
- **Explanation:** Deterministic and selected multi-turn runs do not establish
  confidence intervals for every production observable.
- **Why it matters:** Small solver biases can be hidden by macroparticle noise.
- **Suggested test:** Predeclare multi-seed convergence studies across particle
  count, grid, slices, cache modes, and timestep/model choices.

### Platform Breadth

- **Severity:** Residual portability gap.
- **File/function:** package-wide numerical and performance behavior.
- **Explanation:** Final GPU validation used one NVIDIA architecture; no AMD GPU
  backend exists, and MPI/OpenMP are not implemented.
- **Why it matters:** Performance and some floating-point ordering conclusions
  are hardware-specific.
- **Suggested test:** Add another NVIDIA architecture and CPU architecture to
  release CI. Do not claim MPI/OpenMP support until those backends exist.

## 7. Documentation Review

The current documentation is unusually strong for a scientific code:

- Public architecture is generated in `docs/registry_snapshot.md`.
- Runtime details are separated in `docs/current_runtime.md`.
- Solver mathematics and validation assumptions are recorded under
  `docs/theory`.
- Executable validation commands and expected interpretation live in
  `validation/README.md`.
- Optimization and review history are preserved without turning history files
  into the forward plan.

Changes in this session added the complete near-round derivation, stable-moment
record, physical-scale semantics, GaussianPIC rank fallback, task turn-state
semantics, symplectic matrix requirements, workspace/cache ownership, and
radiation semantics.

The main remaining documentation need is an external reproducibility package:
versioned environment, hardware/driver metadata, matched independent-code decks,
and archived expected statistical intervals for headline research results.

## 8. Security and Robustness

Octopus is a local scientific library rather than a network service, so the
primary risks are invalid numerical input, resource exhaustion, and silent
scientific corruption rather than remote attack.

Improvements in this session reject non-finite/invalid radiation inputs,
non-symplectic matrices, unsupported float calibrations, undefined physical
scales, and singular Gaussian references. Task state advances only on successful
completion, and workspace ownership is explicit.

Residual operational risks are user-selected output paths overwriting files,
large grids/slice counts exhausting host or device memory, and CUDA atomic
roundoff nondeterminism. No unchecked C pointer arithmetic or manual resource
ownership was found in the reviewed Julia source. HDF5 and CUDA resources are
owned by their Julia libraries; errors propagate rather than being ignored.

## 9. Architecture Assessment

Positive architecture:

- Specs, runtime elements, execution policies, tasks, observers, and solver
  contracts are distinct layers.
- CPU and CUDA implementations share public solver semantics.
- Counter-based RNG separates stochastic identity from execution order.
- Solver option schemas expose defaults, dependencies, and backend scope.
- Validation scripts are executable research records rather than prose-only
  claims.

Remaining debt:

- CUDA PIC is too large and route-dense.
- Several internal caches use heterogeneous `Dict{Any,Any}` storage.
- Performance evidence is stored across several history files rather than one
  machine-readable benchmark database.
- Conventional PIC is not symplectic; this is a model limitation, not an
  implementation labeling bug.

## 10. Final Validation Matrix

| Validation | Final result |
| --- | --- |
| Complete `test/runtests.jl` | All testsets passed, including CPU and CUDA |
| Near-round transition | Passed for `Float32`/`Float64`, CPU/CUDA |
| Finite-difference symplecticity | All listed maps passed |
| `Linear6D` residual | `1.5021e-13` vs `5e-7` tolerance |
| Tracking CPU/CPU | Exact (`global_rel_error=0`) |
| Tracking CPU/CUDA | `global_rel_error=9.4224e-16`, passed |
| Tracking context/policy consistency | Passed |
| GaussianPIC analytic field table | Reproduced |
| GaussianPIC bi-Gaussian table | Reproduced |
| Spectral Poisson field/convergence table | Reproduced |
| Strong-strong diagnostics consistency | Passed |
| High-energy weak-strong limit | Gaussian, PIC, spectral grid/grid-free passed |
| 200-turn strong-strong output | Completed with 200 moment/luminosity records |

The final 200-turn radiation A/B used the full example physics, 20k
macroparticles per beam, 15 slices, 128x128 PIC, per-turn luminosity, and two
HDF5 moment observers. The maximum moment-data difference was `1.04e-15`
absolute. A whole-run timing offset was observed between sequential processes,
but an isolated same-size radiation-kernel benchmark measured only `+0.011%`;
the offset is therefore not attributed to the radiation change.

## 11. Positive Aspects

- Mathematical conventions are documented and cross-linked to implementations.
- Analytic, PIC, spectral, and Gaussian-subtracted solvers provide useful
  independent comparisons.
- CPU/CUDA parity coverage is broad and includes non-default routes.
- Counter RNG makes stochastic chunk/restart equivalence testable.
- Tests include non-finite, zero-width, rank-deficient, near-axis, near-round,
  coupled, and high-energy limits.
- The project records rejected optimizations and limitations, reducing the risk
  that future maintainers repeat invalid conclusions.
- Performance decisions are generally made from complete-turn measurements
  with diagnostics enabled, not isolated kernel timing alone.

## 12. Top 10 Highest-Priority Improvements

1. **Resolved:** stabilize the round Gaussian near-axis field.
2. **Resolved:** replace the hard near-round switch with a derived smooth
   potential-level transition.
3. **Resolved:** stabilize every strong-strong variance/covariance reduction.
4. **Resolved:** remove dimensionless epsilon from physical length defaults.
5. **Resolved:** fall back safely from undefined GaussianPIC references.
6. **Resolved:** preserve absolute turn/RNG/schedule state across task chunks.
7. **Resolved:** reject non-symplectic `Linear6D` matrices.
8. **Resolved:** make CPU/CUDA solver workspaces exclusive and device-aware.
9. **Resolved:** bound CUDA wavefront storage and make radiation semantics
   explicit.
10. **Pending validation program:** establish an archived independent-code,
    multi-seed, multi-resolution reference for headline production studies.

## 13. Commit Ledger

| Commit | Change |
| --- | --- |
| `12dca5a` | Stabilize round Gaussian near-axis kick |
| `4d48f88` | Derive near-round switch estimate |
| `4ed17df` | Implement smooth near-round transition |
| `5d31308` | Reject uncalibrated floating types |
| `ee16bc4` | Stabilize strong-strong moment reductions |
| `567db53` | Replace machine-epsilon physical scales |
| `5f9f17f` | Fall back from singular GaussianPIC references |
| `bcb7e36` | Preserve absolute turns across task execution |
| `66a3648` | Reject non-symplectic `Linear6D` matrices |
| `ec86c34` | Isolate solver workspaces across executions |
| `a3d3b62` | Bound CUDA PIC wavefront workspaces |
| `855dd90` | Make radiation component semantics explicit |

Every commit above was pushed to `main` after its focused tests and validation
passed.

## Final Assessment

- **Estimated technical debt:** Medium.
- **Estimated production readiness:** 86%.
- **Estimated scientific reproducibility:** 89%.
- **Suitability for high-impact accelerator-physics research:** Suitable as a
  validated research engine when each study supplies solver convergence,
  macroparticle/statistical uncertainty, and independent model checks. It should
  not be treated as a parameter-free source of publication truth.
- **Overall confidence in this review:** High (94%). Confidence is limited
  primarily by single-GPU hardware access and the absence of an external-code
  replication in this session.
