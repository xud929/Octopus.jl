# Public Configuration Audit

This audit records the configuration-effectiveness review associated with the
policy-centered execution refactor. A setting is effective only when validation
can observe it at its runtime consumer; constructor storage, help output, and
timing differences are not sufficient evidence.

## Disposition

| Surface | Settings reviewed | Disposition and evidence |
| --- | --- | --- |
| CPU execution policy | `threads` | Implemented as a validated logical-worker count. Tracking, slicing, Gaussian collision, CPU PIC deposition, reductions, and workspace keys use the resolved count. `:cpu_logical_workers` receipts are contractual evidence. |
| CUDA execution policy | `device`, fused `threads`, fused `blocks` | Implemented. Device is resolved from and checked against storage before mutation. Fused launches report actual geometry; `blocks=:auto` uses compiled-kernel occupancy and particle coverage. |
| Deprecated GPU/backend APIs | `GPUExecutionPolicy`, backend-tag `track!`, CUDA launch keywords | Compatibility-only. They resolve one concrete policy and enter the canonical implementation; mixed old/new controls are rejected by method signatures. |
| CUDA PIC launch configuration | gather/scatter, deposition, kick, field, spectral, Green, luminosity threads | Implemented through `CUDAPICLaunchConfig`. Missing values inherit the CUDA policy. Each family emits a kernel-consumer receipt. Luminosity reduction width is power-of-two validated and included in its workspace key. cuFFT launch selection is library-managed and is not exposed. |
| PIC numerical/physics solver | grid, force/luminosity deposition, Green type/cache/growth/ratio, longitudinal kick, batch and CUDA algorithm flags, luminosity grid/schedule, slicing | Verified consumers in CPU/CUDA PIC paths. Structured reports distinguish inheritance, inactive backends, and disabled dependencies. Constructor-invalid methods and grid sizes are rejected before execution. |
| Gaussian solver | kick overrides, luminosity scale, slicing, `min_sigma`, luminosity sampling beam, centroid controls | Structured metadata added; inherited slicing is retained separately from requested overrides. Invalid `min_sigma` and luminosity sampling choices are rejected. |
| Longitudinal slicing | slice count, method, resolution, center convention, specified positions | Structured metadata and reports added. Constructor validation rejects unsupported or inconsistent values. CPU worker policy reaches threaded slicing consumers. |
| Strong-strong diagnostics | turn timing, memory logging, PIC timing/detail, cache statistics, NVTX | All fields have structured metadata and are recorded when the task activates diagnostic execution. Backend-inapplicable values report inactive rather than applied. |
| Tracking and strong-strong tasks | policy, hook schedules, collision solvers, luminosity path, compatibility aliases | Task reports include resolved policy, schedules/observers, diagnostics, output status, and every collision solver. Both beam lines are zipped during preflight; mismatched solver objects and invalid backend configuration fail before line tracking. Deprecated `seed`, `record_turn_times`, and old backend adapters remain compatibility-only. |
| Schedules and output observers | turn schedules, moment selections, capacities, snapshot counts/append mode, luminosity paths | Structured reports added. Validation observes schedule decisions and output capacities at runtime. Zero capacity reports disabled; invalid capacities/counts are rejected. |
| Beam construction | physical beam parameters and initialization maps | Unknown trailing keywords now fail instead of being silently discarded. Policy-controlled initialization maps use the same tracking policy. |
| Element-spec extra keywords | descriptive metadata | Intentionally retained as spec-layer metadata, not described as runtime configuration. Runtime maps consume only declared physics parameters. |
| Environment variables | example and validation drivers | No runtime source reads environment variables. Drivers may translate shell inputs into explicit constructors; environment variables are not a second production control path. |

## Automated enforcement

- `validate_configuration_metadata()` checks schema completeness, constructor
  defaults, applicability, dependencies, and declared consumers.
- `PublicConfigurationEffectivenessContract` sweeps CPU logical workers at 1,
  an intermediate count, and the full pool; sweeps fused CUDA threads at 64,
  128, 256, and 512 with explicit and automatic blocks; and perturbs CUDA PIC,
  schedule, capacity, and device settings. It checks actual consumer receipts,
  unchanged deterministic physics, and pre-mutation rejection of an invalid
  inherited PIC reduction width.
- `validation/public_configuration_effectiveness.jl` is the reusable driver.
- `AGENTS.md` requires a runtime consumer, metadata, inactive/error semantics,
  and an effectiveness test in the same change as every new public setting.

CUDA-unavailable runs are reported as skipped after CPU/schema checks; they are
never reported as complete passes.
