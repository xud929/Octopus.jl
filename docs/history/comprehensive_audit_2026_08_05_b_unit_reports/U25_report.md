# U25 Report — validation/ backend-consistency, PIC-option and benchmark scripts

Reading unit U25 of the 2026-08-05_b comprehensive audit.

## Provenance and environment

- Repository: `/cfs/ad/dxu/Library/Julia/Octopus`, HEAD `c55d2e0`
  (`audit(2026-08-05_b): first four confirmed findings, with their reproductions`);
  the brief named `7de4d81`, which is two commits back — the orchestrator committed
  in the meantime. **The working tree was not clean while this unit ran**: the
  orchestrator's in-flight fix to `src/tasks/strongstrong/interface.jl`
  (luminosity plan/commit split, F2) was present and uncommitted for every run
  below. Every strong-strong run in this report therefore exercised that edit.
- Julia 1.12.4; NVIDIA RTX 4500 Ada (24.5 GB), CUDA 13.0, ~4 GB in use by other
  processes throughout. **The box was shared with ~19 other audit agents** (19
  concurrent `julia` processes observed); every wall-clock number below is
  therefore contaminated and is reported only as evidence that a run completed.
- No repository file was modified. All probes, scripts and output live in
  `/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`.
- **Output redirection.** Most scripts in this region write to `<repo>/result/`.
  To keep the repository untouched *and* to avoid colliding with the other
  agents' runs, every script was executed from a **copy** in a scratch run-root
  (`scratchpad/audit/runroot/validation/`) whose siblings `src/`, `examples/`
  and `test/examples/` are symlinks back to the repository and whose `result/`
  and `test/result/` are real scratch directories. Because every script resolves
  its output directory from `@__DIR__`, this redirects all output into scratch
  while executing byte-identical script text against the real source tree. The
  Julia environment was the real project (`--project=<repo>`), and the working
  directory was the repository so that `git rev-parse HEAD` inside the benchmark
  scripts resolved correctly. Verified: the only file the repository gained
  during this unit was nothing — `git status --porcelain` shows only the
  orchestrator's `interface.jl` modification, before and after.
  (One accident to record: an early malformed shell command created three
  self-referential symlinks `src/src`, `test/test`, `examples/examples` inside
  the repository. They were detected within one tool call and removed;
  `git status` is clean of them.)

## Coverage

Read line by line, every line of every file: `pic_option_consistency.jl` (233),
`tracking_backend_consistency.jl` (214), `pic_option_consistency_summary.jl` (151),
`pic_slice_boundary_jitter.jl` (129), `strong_strong_diagnostics_benchmark.jl` (123),
`counter_rng_validation.jl` (121), `tracking_context_policy_consistency.jl` (120),
`soft_gaussian_pic_comparison.jl` (117), `strong_strong_pic_extreme_benchmark.jl` (107),
`crossing_luminosity_anchor.jl` (99), `beam_optics_interface_consistency.jl` (79),
`strong_strong_pic_cache_backend_consistency.jl` (63),
`strong_strong_observer_plan_consistency.jl` (62), `tracking_task_turn_update.jl` (55),
`strong_strong_gaussian_backend_consistency.jl` (51),
`strong_strong_luminosity_schedule_output.jl` (47),
`strong_strong_diagnostics_consistency.jl` (45),
`moment_observer_backend_consistency.jl` (42),
`public_configuration_effectiveness.jl` (28), `tune_estimator_calibration.jl` (27),
`README.md` (890).

Read for cross-checking (not audited): `src/contracts/Contracts.jl` (the four
contracts these scripts run, `_contract_coordinate_metrics`,
`_contract_default_initial_rep`), `src/math/counter_rng.jl`,
`src/elements/aperture.jl`, `src/tasks/strongstrong/interface.jl` (slicing methods,
`_CUDA_PIC_LAUNCH_FAMILIES`, solver options), `src/tasks/strongstrong/pic_cuda.jl`
(node/wavefront route), `test/examples/strong_strong_tracking.jl` (result-dir and
timing-path handling), `test/runtests.jl:3873` (the Philox KAT testset),
`AGENTS.md`, `docs/comprehensive_audit.md` (Measured Lessons),
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U21_report.md`, and
`git diff 6a3f39ab HEAD -- validation/`.

**Executed** (all 20 region scripts were run; see the GPU table): 12 GPU-leg runs,
9 CPU runs, 1 tripwire demonstration, 4 dedicated probes. Nothing in this region
was left unrun.
