# U54: validation: consistency, effectiveness and small studies (20 scripts)

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683 (read-only; no repository
file was modified and git was never run in the tree). Scratch:
`result/comprehensive_audit_2026_10_18/probes/U54/` (all paths below that are relative are
relative to the repository root; probe logs are named by script).

## Region

The unit plan's title says 22 scripts; its list names 20, and the 20 total the plan's 1551
lines, so 20 is the region. Every file was read in full, line by line.

| file | lines |
|---|---|
| `validation/beam_optics_interface_consistency.jl` | 1-81 |
| `validation/crossing_luminosity_anchor.jl` | 1-113 |
| `validation/emit_xcode.jl` | 1-66 |
| `validation/lambda_flat_converged.jl` | 1-128 |
| `validation/lambda_round_converged.jl` | 1-30 |
| `validation/moment_observer_backend_consistency.jl` | 1-61 |
| `validation/pic_slice_boundary_jitter.jl` | 1-129 |
| `validation/public_configuration_effectiveness.jl` | 1-28 |
| `validation/soft_gaussian_pic_comparison.jl` | 1-117 |
| `validation/strong_beam_kick_fingerprint.jl` | 1-94 |
| `validation/strong_strong_diagnostics_consistency.jl` | 1-45 |
| `validation/strong_strong_gaussian_backend_consistency.jl` | 1-53 |
| `validation/strong_strong_luminosity_schedule_output.jl` | 1-49 |
| `validation/strong_strong_observer_plan_consistency.jl` | 1-66 |
| `validation/strong_strong_pic_cache_backend_consistency.jl` | 1-65 |
| `validation/strong_strong_pic_extreme_benchmark.jl` | 1-126 |
| `validation/tracking_context_policy_consistency.jl` | 1-125 |
| `validation/tracking_task_turn_update.jl` | 1-55 |
| `validation/tune_estimator_calibration.jl` | 1-38 |
| `validation/twiss_dispersion_route_dump.jl` | 1-82 |

Total: 1551 lines.

## Provenance

READ line by line: the 20 files above in full. For comparison (read, not audited):
`validation/README.md` lines 25-50, 238-246, 355-370, 600-640, 668-720, 745-790, 815-835,
950-975, 1838-1860, 1873-1932 (every passage naming a script of the region);
`docs/history/weak_strong_allocation_2026_09_04.md` lines 196-235 (the committed fingerprint
digests); the previous audit's `U25_report.md` sections 3 and 5 and lead U25-10, and the
U24/U25 rows of its `LEAD_INDEX.md`; `test/examples/strong_strong_tracking.jl` lines 370-380,
408-424, 508-524, 1063-1095 (the harness the benchmark includes). Definition sites of every
helper the scripts call were located by grep and the signatures read: `_standard_gaussian_rep`
(src/beam/Beam.jl:162), `Beam` (Beam.jl:512, 572, 618), `_resolve_execution_policy` (:337),
`_with_execution_policy` (:466), `Base.getindex(::Phase6DRep)` (:184);
`_contract_backends_available` (src/contracts/Contracts.jl:1252), `_require_gpu_contract`
(:1285), `_gpu_skip_or_error` (:1294), `_contract_default_initial_rep` (:1304),
`_contract_rep_for_backend` (:1318/1322), `_contract_coordinate_metrics` (:1329),
`_strong_strong_contract_base_beams` (:1406), `_strong_strong_contract_beam` (:1440/1445),
`ContractResult` (:25), the two strong-strong contracts (:90, :127), the effectiveness
contract's skip branch (:759-763); `_moment_observer_row` (src/tasks/BeamObservers.jl:1062),
`MomentObserver` (:658, :711), `should_run` (:76-82), `ScheduledObserver` (:131),
`observe!`/`apply_action!` three-argument forms (:844, :929), `BPMObserver`
(src/tasks/BPMObserver.jl:130), `Base.read(::TaskOutput, ::Symbol; ...)`
(src/tasks/RunArtifact.jl:1948), `TrackingTask` (src/tasks/Tasks.jl:220), `StrongStrongTask`
(src/tasks/strongstrong/interface.jl:2388), `StrongStrongDiagnostics` (:326-342),
`_CUDA_PIC_LAUNCH_FAMILIES` (:91), `collide!` four- and five-argument forms (:523,
pic_cpu.jl:1, pic_cuda.jl:94/6486/6489), `_strong_strong_luminosity_evaluated` (:3084-3085),
`configuration_report(::PICPoissonSolver; ...)` (:1730), `solver_configuration` (:483, :1561),
PIC/Gaussian solver keywords (:899-902, :1136-1144, :1423-1438), `longitudinal_slices` and the
boundary extrema (src/tasks/strongstrong/slicing.jl:51, 160-161, 466-467), `ThinStrongBeam`
and `hvoffset` (src/elements/strong_beam.jl:212-219, 260, 514-525, 1801),
`ThinCrabCavitySpec{N}` and its kick (src/elements/crab_cavity.jl:4, 135-137),
`ChromaticityKickSpec` (src/elements/chromaticity_kick.jl:17, 226-227), `LumpedRadSpec`
(src/elements/radiation.jl:398), `Linear6D`/`Matrix` (src/elements/linear6d.jl:96-99),
`CUDALaunchConfig`/`CUDAExecutionPolicy` (src/policies/Policies.jl:332-361),
`execution_receipts`/`with_execution_audit` (:171/181), the receipt consumers
`:cuda_fused_launch` (src/track/phase6d_track.jl:359), `:cuda_radiation_compatibility_launch`
(src/track/radiation_track.jl:54), `:isolated_tracking` (src/tasks/Tasks.jl:2426), the
constants `RE`, `EMASS_EV`, `ME0 = EMASS_EV`, `PMASS_EV` (src/constants/Constants.jl:11-20),
and the Twiss helpers (`_identity_contract_*`, `_symplectic_inverse`,
`_graph_invariance_residual`, `_kappa_route`, `determined_value`, `is_determined`).

EXECUTED (all with `julia --startup-file=no --project=<tree> --threads=4`, CUDA active, one
RTX 4500 Ada; logs in `probes/U54/<name>.log`, each ending in `exit=<code>`):

| script | how | result |
|---|---|---|
| `strong_beam_kick_fingerprint.jl` | as is | exit 0; nine `BR` lines reproduce the 2026-09-04 record bit for bit (digests and `last_luminosity`); the tenth prints `BR gsb hirata hvoffset ERROR MethodError: no method matching get(::Tuple{Float64, Float64}, ::Symbol, ::Symbol)` |
| `tune_estimator_calibration.jl` | as is | `n_trials=500  median=4.8e-6  p95=6.5e-6  max=0.0078`, exit 0 |
| `tracking_task_turn_update.jl` | as is | `max_abs_error = 0.0`, passed, exit 0 |
| `strong_strong_luminosity_schedule_output.jl` | as is | `ip1 = (turn=[0,100,200], value=[1.0,NaN,201.0])`, `ip2 = (..., [1001.0,1101.0,1201.0])`, passed, exit 0 |
| `strong_strong_diagnostics_consistency.jl` | as is | passed, exit 0 |
| `beam_optics_interface_consistency.jl` | as is | CPUThreadsBackend and CUDABackend both "passed", ChromaticityKickSpec passed, exit 0 |
| `strong_strong_observer_plan_consistency.jl` | as is | `CPUThreadsBackend: max errors = 0.0, 0.0`, `CUDABackend: max errors = 0.0, 0.0`, exit 0 |
| `tracking_context_policy_consistency.jl` | as is | "passed" with CUDA present (all four CUDA assertions silent), exit 0 |
| `moment_observer_backend_consistency.jl` | as is | **exit 1**: `ArgumentError: the standalone moment file writer was retired (2026-08-18)` at line 42 |
| `strong_strong_gaussian_backend_consistency.jl` | as is | `status = passed`, `backend_b = CUDABackend`, `max_abs_error = 1.515e-17`, `global_rel_error = 6.48e-16`, `max_component_rel_error = 2.82e-10`, `max_component_rel_scale = 4.93e-10`, `max_allowed_ratio = 1.515e-7`, `luminosity_rel_error = 4.15e-16`, exit 0 |
| `strong_strong_pic_cache_backend_consistency.jl` | as is (CIC, INHERIT) | `status = passed`, `backend_b = CUDABackend`, `cache_histories_match = true`, cpu/gpu cache history `(17, 18, 1)`, `max_abs_error = 6.15e-17`, `luminosity_rel_error = 5.20e-15`, `slice_pair_luminosity_records_compared = 18`, exit 0 |
| `public_configuration_effectiveness.jl` | as is | `status = passed`, `cuda_status = passed`, seven PIC families observed, `unknown_beam_keyword_rejected = true`, exit 0; plus two counter-RNG "already held" warnings from the contract's fixtures |
| `soft_gaussian_pic_comparison.jl` | as is (1e5, 15 slices, 128^2) | `luminosity_relative_difference = 8.53e-4`, soft 0.015 s / PIC 0.212 s, exit 0 |
| `twiss_dispersion_route_dump.jl` | `OUT.tsv` in scratch | `1005 route rows over 201 row-producing fixtures (227 in the list); arm native host sapphirerapids`, exit 0; `probes/U54/route_dump.tsv` |
| `pic_slice_boundary_jitter.jl` | byte-identical copy behind a pre-included `Main.Octopus`, `OCTOPUS_JITTER_NPART=20000 OCTOPUS_JITTER_TURNS=8` | four rows written to `probes/result/pic_slice_boundary_jitter.tsv`; outer boundaries finite (0.294/0.100 electron, 0.087/0.246 proton, per sigma_z), exit 0 |
| `lambda_round_converged.jl` (and through it `lambda_flat_converged.jl`) | `OCTOPUS_LFC_TURNS=128 OCTOPUS_LFC_NMACRO=4000 OCTOPUS_LFC_SEEDS=20260727 OCTOPUS_LFC_OUT=<scratch>` | `Lambda_x = 0.8791`, `Lambda_y = 1.1492` (reduced settings, not converged; API exercised), TSV written, exit 0 |
| `crossing_luminosity_anchor.jl` | byte-identical copy behind a pre-included `Main.Octopus` (outputs to `probes/result/lum_anchor/`) | `phi = 2.5`, `R continuous = 0.37137`, `R discrete-15 = 0.36926`, `R code no-crab = 0.37195`, `R code crab = 1.0`, `code/discrete (no-crab) = 1.0073`, exit 0 |

Follow-up probes (scripts in `probes/U54/`):

| probe | purpose | result |
|---|---|---|
| `moment_probe.jl` | the dead script's body with `MomentObserver(; name=...)` | `columns = 28`, `max_abs_error = 1.99e-17`, `max_rel_error = 1.67e-13`, `rtol = 5e-12`, `passed = true` |
| `public_conf_nocuda_require.log` | the script under `CUDA_VISIBLE_DEVICES= OCTOPUS_REQUIRE_GPU_CONTRACT=1` | `status = skipped`, `cuda_status = skipped`, `exit=0` |
| `harness_cpu_probe.jl` | the benchmark's include path under `OCTOPUS_USE_GPU=0`, toy size | `policy type = CPUThreadsExecutionPolicy`, `isdefined(Main, :CUDA) = false`, the benchmark's line 76 throws `UndefVarError: CUDA not defined in Main` |
| `beam_optics_elementwise_probe.jl` | the elementwise picture behind line 58's norm-wise `isapprox` | all six coordinates bitwise equal between sigma- and emittance-built beams |

Not executed: `emit_xcode.jl` (4096 turns x 1e5 macroparticles x 2 aspects with no override; every
call it makes is shared with `lambda_flat_converged.jl`, which ran) and
`strong_strong_pic_extreme_benchmark.jl` as a whole (it shells out to `git rev-parse HEAD` in the
tree, which the brief forbids me, and is a production-size GPU run; its include path, exported
names and CPU-override failure were probed at toy size instead).

## Leads

### LEAD U54-1 [Major, confidence high] validation/moment_observer_backend_consistency.jl:42
Claim: The script has been un-runnable since 2026-08-18: `MomentObserver(tempname() * ".h5")` hits the retired positional-path constructor and throws before any comparison, while `validation/README.md` lines 817-824 still present it as the live CPU/CUDA moment-reduction check.
Mechanism: `src/tasks/BeamObservers.jl:658-661` turns the positional-path form into `ArgumentError("the standalone moment file writer was retired (2026-08-18): construct MomentObserver(; name=..., ...)")`; nothing in `test/runtests.jl` or `.github/workflows/ci.yml` runs this script, so the retirement left it dead and no one has run it since (defect classes 1 and 14; hypothesis 1, a stale API call in a small script nobody re-runs). The instrument underneath still works: `probes/U54/moment_probe.jl` replaces lines 42-43 with `MomentObserver(; name="u54_cpu")` / `(; name="u54_gpu")` and keeps everything else, giving 28 columns, `max_abs_error = 1.99e-17`, `max_rel_error = 1.67e-13` against `rtol = 5e-12`, `passed = true` (the 2026-08-06 numbers), so the fix is the constructor line and the README stays true once it runs.
Repro: `julia --project=. validation/moment_observer_backend_consistency.jl; echo $?` -> `ERROR: LoadError: ArgumentError: the standalone moment file writer was retired (2026-08-18) ...` at line 42, exit 1 (expected: the printed table and exit 0); `julia --project=. result/comprehensive_audit_2026_10_18/probes/U54/moment_probe.jl` -> `passed = true`.

### LEAD U54-2 [Minor, confidence high] validation/strong_beam_kick_fingerprint.jl:71
Claim: The tenth configuration, `hvoffset=(1.0e-6, -2.0e-6)`, is malformed, so the per-slice `hvoffset` branch the header (lines 2-6) lists among the branches this instrument fingerprints has never produced a digest; the committed record and the README count "nine" and file the error as out of scope.
Mechanism: `GaussianStrongBeamSpec` documents `hvoffset` as "optional Dict with dim, coef, frequency, harmonics" (`src/elements/strong_beam.jl:1801`) and `compile_runtime` reads it with `get(hvoffset, :dim, :x)` (`strong_beam.jl:514-519`); a tuple has no `get(::Tuple, ::Symbol, ::Symbol)`, hence the `MethodError` that the script's `try/catch` at line 90 prints as `BR gsb hirata hvoffset ERROR`. The `_crab_offsets` slice-offset branch (`strong_beam.jl:517`) therefore sits outside the refactor guard, and because the guard is a diff of `BR` lines between two trees, an identical error on both sides reads as "no change". Seam, out of my region: the spec accepts the wrong shape silently at construction and fails only at compile time with a bare `MethodError` rather than a shaped `ArgumentError` naming the Dict keys (`strong_beam.jl:514-519`).
Repro: `julia --startup-file=no --project=. validation/strong_beam_kick_fingerprint.jl | grep -c '^BR .* ERROR'` -> 1 (expected 0); the other nine `BR` lines reproduce `docs/history/weak_strong_allocation_2026_09_04.md` lines 215-223 bit for bit on this machine (`probes/U54/fingerprint.log`).

### LEAD U54-3 [Minor, confidence high] validation/strong_strong_pic_extreme_benchmark.jl:76
Claim: Lines 76-78 call `CUDA.name(CUDA.device())`, `CUDA.driver_version()` and `CUDA.runtime_version()` unconditionally, but the harness binds `CUDA` only under `if use_gpu` (`test/examples/strong_strong_tracking.jl:416-419`), so the CPU override the header says the script accepts (`OCTOPUS_USE_GPU=0`, "the same environment variables accepted by `test/examples/strong_strong_tracking.jl`") completes the measured run and then dies with `UndefVarError` before the provenance summary is written: the U25-15 failure shape (fail at the end of a production-size run) in another guise.
Mechanism: the summary vector (lines 73-98) is built after the run; the GPU-only rows are gated at line 99 (`policy isa CUDAExecutionPolicy`) but lines 76-78 are not. Measured through the benchmark's own include path at toy size (`probes/U54/harness_cpu_probe.jl`): `isdefined(Main, :CUDA) = false`, and the verbatim line 76 throws `UndefVarError: CUDA not defined in Main`. Related, same block: line 74 reads `git rev-parse HEAD` from the caller's working directory, so a launch from outside the project root records a foreign commit or errors after the run (the header does say "run from the project root").
Repro: `OCTOPUS_USE_GPU=0 OCTOPUS_TURNS=20 OCTOPUS_N_MACRO_ELE=2000 OCTOPUS_N_MACRO_PRO=1000 julia --project=. validation/strong_strong_pic_extreme_benchmark.jl` -> `UndefVarError: CUDA` after the 20 turns (expected: an upfront refusal of the CPU override, or a summary with the GPU rows omitted).

### LEAD U54-4 [Minor, confidence med] validation/public_configuration_effectiveness.jl:27
Claim: With CUDA hidden and `OCTOPUS_REQUIRE_GPU_CONTRACT=1`, the script prints `status = skipped` and exits 0, so the one flag the repository offers to make a GPU skip fatal silently does nothing here, while both sibling contract scripts honour it.
Mechanism: the contract returns `ContractResult(:skipped, "CPU configuration checks passed; CUDA effectiveness was skipped: ...")` (`src/contracts/Contracts.jl:759-763`); the script errors only on `:failed` and never calls `Octopus._require_gpu_contract()`. The previous audit filed this as "by design (documented)", but the U25-10 fix text now copied into `strong_strong_gaussian_backend_consistency.jl:29-31` and `strong_strong_pic_cache_backend_consistency.jl:39-41` defines "a flag that silently does nothing" as the defect shape, and this is the only contract-running script in the directory left out. Measured: `probes/U54/public_conf_nocuda_require.log` lines 2, 8, 28.
Repro: `CUDA_VISIBLE_DEVICES= OCTOPUS_REQUIRE_GPU_CONTRACT=1 julia --threads=4 --project=. validation/public_configuration_effectiveness.jl; echo $?` -> `status = skipped`, `cuda_status = skipped`, exit 0 (expected: a nonzero exit under the require flag).

### LEAD U54-5 [Minor, confidence med] validation/strong_strong_pic_extreme_benchmark.jl:79
Claim: `precision` ("Float64"), `grid` ("128x128") and `slices_per_beam` ("15") are hand-typed into the provenance summary although the harness publishes the values that shaped the run (`input.solver.pic_grid`, `input.slicing.zslice`, the beams' element type), so a change to the harness defaults would be recorded wrongly with nothing to notice.
Mechanism: lines 79, 83 and 88 are string literals; the same script's lines 106-112 explain, for the launch-family list, why a hand-maintained copy of something that can change has nothing to keep it honest (Measured Lesson 4). The values live at `test/examples/strong_strong_tracking.jl:371` (`zslice = 15`) and `:376` (`pic_grid = (128, 128)`), reachable through `input`, which the script already asserts the harness exports (line 55) and already reads for `deposit_method` (line 84). Class 2.
Repro: `grep -n '"128x128"\|=> "15"\|=> "Float64"' validation/strong_strong_pic_extreme_benchmark.jl` -> three literal rows; `grep -n "zslice = \|pic_grid = " test/examples/strong_strong_tracking.jl` -> the published values they shadow (expected: the summary derives them from `input`).

### LEAD U54-6 [Minor, confidence high] validation/emit_xcode.jl:9
Claim: `emit_xcode.jl` (line 9) and `lambda_flat_converged.jl` (line 22) include `src/Octopus.jl` without the `isdefined(Main, :Octopus)` guard that U25-14 put on every other script in `validation/`, so neither can be included after a sibling in one process (how the audit harnesses drive the directory) without re-evaluating the package, and `lambda_flat_converged.jl` additionally redefines top-level `const`s on a second include.
Mechanism: both arrived with the 2026-08-12 migration from `paper/`, after the U25-14 sweep; the crossing anchor's header (lines 19-21) states the convention they break. The third unguarded file, `strong_beam_kick_fingerprint.jl:30`, is unguarded on purpose (it selects the tree through `OCT_ROOT`) and is not part of this claim. Header nits in the same pair: `lambda_flat_converged.jl:19` quotes a run command without the `validation/` prefix, so it fails from the project root the header names, and `lambda_round_converged.jl:15` cites `data/lambda_round_converged.tsv`, a path that exists only in the external paper repository (`data/` does not exist in this tree).
Repro: `for f in validation/*.jl; do grep -q 'src", "Octopus.jl"' $f && ! grep -q 'isdefined(Main, :Octopus)' $f && echo $f; done` -> `emit_xcode.jl`, `lambda_flat_converged.jl`, `strong_beam_kick_fingerprint.jl` (expected: the fingerprint only).

### LEAD U54-7 [Minor, confidence med] validation/tune_estimator_calibration.jl:16
Claim: The estimator the calibration certifies is a hand copy: the same nine-line Hann-window plus parabolic-interpolation function exists in six validation files (`coherent_beam_beam_modes_beambeam3d`, `coherent_beam_beam_modes`, `coherent_mode_scans`, `coherent_mode_vlasov_theory`, `lambda_flat_converged`, `tune_estimator_calibration`) with no shared definition and no drift tripwire, so the calibration binds only to its own copy.
Mechanism: `lambda_flat_converged.jl:36-37` says "Identical estimator to validation/coherent_mode_scans.jl", a claim maintained by hand (I diffed those two bodies: identical today; the four others are outside my region and were only counted). Class 2. Measured aside for the reader of the paper-cited figures: the calibration's `max = 0.0078` is the tone separation itself, i.e. a wrong-peak event when the secondary amplitude `r` approaches 1 (line 30 draws `r` in [0.1, 1.0)), not estimator resolution; median 4.8e-6 and p95 6.5e-6 are the resolution.
Repro: `grep -l '0.5 \* (y1 - y3) / d\|0.5\*(y1-y3)/d' validation/*.jl | wc -l` -> 6 (expected: one definition, or a drift tripwire); `julia --startup-file=no --project=. validation/tune_estimator_calibration.jl` -> `n_trials=500  median=4.8e-6  p95=6.5e-6  max=0.0078`.

### LEAD U54-8 [Minor, confidence med] validation/strong_strong_diagnostics_consistency.jl:16
Claim: (out of hypothesis) the "observational diagnostics do not change tracked coordinates" gate runs against a no-op Poisson solver, so every diagnostic that could plausibly perturb coordinates (PIC phase timing, cache statistics, memory logging around the solver) has nothing to instrument, and the exact-equality check cannot fail on the defect it names; line 44 even asserts `isempty(pic_phase_timings(task))`.
Mechanism: `StrongStrongDiagnostics(record_turn_times=true, cache_stats=true)` wraps the solver call, and `collide!` returning `0.0` (lines 16-18) leaves the wrapped region with no particle work, so plain-versus-observed equality holds by construction (class 13: a test never shown to fail on its defect). The `turn_timings` and `diagnostic_summary` structural checks (lines 42-43) are real. The sibling scripts already build the contract's beams; a `PICPoissonSolver` on them would make the coordinate half bite at similar cost.
Repro: `grep -n "DiagnosticsNoopPoissonSolver\|pic_phase_timings" validation/strong_strong_diagnostics_consistency.jl` -> the solver is a no-op (lines 16-18, 23) and line 44 asserts no PIC phase ran (expected: a solver with a PIC phase so the gate has something to catch).

### LEAD U54-9 [Minor, confidence low] validation/crossing_luminosity_anchor.jl:113
Claim: The four paper drivers in this region (crossing anchor, tune calibration, lambda round/flat, `emit_xcode`) print their error metrics and record nothing in this repository, so the README's "error metric" statements for them have no committed numbers to compare against; today's run puts the no-crab code/discrete ratio at 1.0073 and the crab ratio at 1.0, with no bound and no in-repo record of either.
Mechanism: the README (lines 1875-1932) documents them as characterization and points to hand-transcribed copies in the external paper repository, but the repository's own rule is that the numbers behind a claim land with the claim; as written, nothing in-repo would notice if a refactor moved 1.0073 to 1.05 (class 14; hypothesis 2, print-only). The physics of the anchor checks out by hand and by measurement: the 15-quantile slice centers (lines 102-104) are the truncated-normal means, the pair factor `exp(-(tan theta (z1-z2))^2/(4 sigma_x^2))` is the right symmetric-slice reduction, the crab strength `tan(theta)/sqrt(beta_crab beta*)` matches the cavity kick `px -= strengthX sin(kz)/k` (`src/elements/crab_cavity.jl:135`), and `R code crab = 1.0` confirms the sign convention.
Repro: `julia --startup-file=no --project=. validation/crossing_luminosity_anchor.jl | tail -3` -> `R code crab = 1.0`, `code/discrete (no-crab) = 1.0073`; `grep -rn "1.0073\|code/discrete" docs/ validation/README.md` -> no committed record (expected: a committed TSV or a bounded ratio).

### LEAD U54-10 [Minor, confidence med] src/contracts/Contracts.jl:759 (seam, reached from validation/public_configuration_effectiveness.jl:18)
Claim: Running the effectiveness contract emits two warnings, "rng_id 1 (and 2), claimed explicitly by a beam consumer, is already held in this process by a bpm_observer consumer", raised by the contract's own fixtures, so a validation run warns about itself and would mask the same warning from a real misconfiguration.
Mechanism: inside the contract a BPM observer is constructed first (auto-assigned ids 1 and 2) and beams are then built with explicit `rng_id=1` and `2` while the registry counter stands at 3 (`src/math/counter_rng.jl:280`, warning text in `probes/U54/public_configuration_effectiveness.log`). Whether the two consumer classes actually share key regions is the auditor's question; the noise is measured. Cross-file seam, noted and stopped.
Repro: `julia --threads=4 --project=. validation/public_configuration_effectiveness.jl 2>&1 | grep -c "already held in this process"` -> 2 (expected 0).

## Clean

Hypothesis 1, current interface. 15 of the 20 scripts ran end to end on 24e8683 (table above),
two of them at reduced settings through their own environment knobs; every helper symbol the 20
scripts call was found at its definition site with the arity and keywords the scripts use
(Provenance list), including the four-argument `collide!` the soft/PIC comparison calls directly
(`pic_cuda.jl:94, 6486`), the `Beam{B,P,R}(params, rep)` positional form it hand-builds
(`Beam.jl:512`), the three-argument `observe!`/`apply_action!` hooks, `ThinStrongBeam(spec)`
with mutable `xo`/`yo`, `BPMObserver(name)`, `ScheduledObserver(observer)`, `read(TaskOutput,
:luminosity; name)`, `Phase6DRep[i]`, the two- and three-plane `ChromaticityKickSpec` inputs,
and every PIC/Gaussian solver keyword the scripts pass (`cuda_async`, `cuda_batch_fft`,
`cuda_wavefront_fft`, `cuda_indexed_wavefront`, `green_cache`, `longitudinal_kick`,
`batch_mode`, `include_sigma_xy`, `virtual_drift`). The single stale call is U54-1.

Hypothesis 1, documented or orphaned. All 20 scripts are named in `validation/README.md` (line
map: 604/619, 1875/1887, 1928, 1917, 1917, 817/824, 952-973, 31/39, 704-713, 242, 759/764,
672/701, 827/833, 749/754, 624-635, 769-785, 42/47, 359/365, 1896/1905, 1840/1858); a by-hand
sweep found every `.jl` in `validation/` named in the README. None of the 20 is run by
`test/runtests.jl` or `.github/workflows/ci.yml` (grep); they are hand-run instruments.

Hypothesis 2, enforced versus print-only (read from the code, confirmed by the runs):

| script | enforced | print-only |
|---|---|---|
| beam_optics_interface_consistency | exact `==` (legacy vs three-plane; vs the sigma reference; untouched coordinates; ChromaticityKick); `rtol=2eps` sigma-vs-emittance; `rtol=atol=4eps` alpha_z | none |
| moment_observer_backend_consistency | `rtol=5e-12`, `atol=1e-18` elementwise; CUDA presence | none (dead at line 42, U54-1) |
| public_configuration_effectiveness | `validate_configuration_metadata()`; contract `:failed` | `:skipped` exits 0 (U54-4) |
| strong_strong_diagnostics_consistency | exact array equality; `length(turn_timings)==2`; summary identity; no PIC phases | none (vacuous coordinate half, U54-8) |
| strong_strong_gaussian_backend_consistency | contract `rtol=luminosity_rtol=1e-10`; skip plus require flag | none |
| strong_strong_luminosity_schedule_output | exact turn axes `[0,100,200]`; exact values including the evaluated NaN | none |
| strong_strong_observer_plan_consistency | `atol=0`, `rtol=1e-12` both beams, both backends | none |
| strong_strong_pic_cache_backend_consistency | contract `rtol=luminosity_rtol=1e-10`, cache histories; skip plus require flag | none |
| tracking_context_policy_consistency | CPU fast/planned `==0`; CUDA launch geometry `==0`; CPU/CUDA `1e-10/1e-10`; receipt presence/absence; `count(:isolated_tracking)==2`; luminosity turn axes equal | luminosity values are not compared across backends (turn axes only, lines 118-121) |
| tracking_task_turn_update | `max_abs_error == 0` | none |
| strong_beam_kick_fingerprint | none in-process (a diff between two trees) | all digests |
| strong_strong_pic_extreme_benchmark | `length(timings) >= 20`; `only(filter(...))` per launch family; `assert_harness_exports` | all timings (benchmark) |
| soft_gaussian_pic_comparison | CUDA presence | every physics number (documented as not an equality gate) |
| crossing_luminosity_anchor, tune_estimator_calibration, lambda_*, emit_xcode, pic_slice_boundary_jitter, twiss_dispersion_route_dump | none | everything (documented as characterization or raw material; U54-9) |

Hypothesis 2, GPU legs. With CUDA present every GPU leg in the region ran and said so:
`beam_optics` printed `CUDABackend: shared beam optics interface passed`; `observer_plan`
printed `CUDABackend: max errors = 0.0, 0.0`; `context_policy` passed with its four CUDA
assertions silent; the Gaussian and PIC contracts reported `backend_b = CUDABackend`;
`public_configuration_effectiveness` reported `cuda_status = passed` with all seven PIC families
(`deposition, field, gather_scatter, green, kick, luminosity, spectral`); `soft_gaussian_pic`
and `moment_observer` hard-require CUDA (the latter dies earlier, U54-1). Skips are visible:
three scripts route the no-CUDA branch through `_gpu_skip_or_error` (read; `Contracts.jl:1294`),
two contract scripts honour `_require_gpu_contract()`; the exception is U54-4.

Hypothesis 2, receipts over inputs. `tracking_context_policy_consistency.jl` asserts what the
run recorded, not what was passed: consumer `:cuda_fused_launch` present (recorded at
`src/track/phase6d_track.jl:359`), `:cuda_radiation_compatibility_launch` absent (still
recorded at `src/track/radiation_track.jl:54`, so the negative check is not vacuous),
`:isolated_tracking` counted twice over two turns (`src/tasks/Tasks.jl:2426`). The benchmark's
summary mixes inputs (env strings for particle counts, batch mode, green cache, ratios) with
resolved values (the launch families from `configuration_report`, the resolved luminosity
deposition); the slice-pair ratio pair is safe because the harness gives the `OCTOPUS_PIC_`
name precedence over the `OCTOPUS_CUDA_PIC_` fallback (`strong_strong_tracking.jl:520-524`),
so the recorded value is the applied one. All 18 defaults the benchmark sets are read by the
harness (grep of every name).

Hypothesis 3, the fingerprint baseline. Committed: `docs/history/weak_strong_allocation_2026_09_04.md`
lines 215-223 (nine fused and elementwise digests with `last_luminosity`). Current: all nine
reproduce bit for bit on this machine today (fused == elementwise in every row; `0x3c2539886fc466cc`,
`0x468ae12e3031c761`, `0x4b7f7c4427139cef`, `0x207f794bee948635`, `0x07924aad54ff3430`,
`0x916e923e7500920c`, `0xb0954daa5a1f7bb1`, `0xd1be3017925fab6d`, `0x1e7f20e493485293`;
luminosities identical to the record). Compared by nobody: no suite or CI reference; the
header's protocol is a diff between two checkouts, and the record is a frozen history file. The
coverage hole is U54-2.

Physics and arithmetic checked by hand. Crossing anchor: quantile edges and truncated-normal
centers, pair reduction factor, Piwinski `phi = tan(theta) sigma_z/sigma_x`, crab strength
versus the cavity kick (`R code crab = 1.0` measured). Lambda scripts: `npart` from `xi_x`,
`xi_y` for the narrow plane, sigma (`x1+x2`) and pi (`x1-x2`) mode assignment, parabolic
interpolation `0.5 (y1-y3)/(y1-2y2+y3)` with `rfft` bin `(k-1)/n`. Constants: `ME0 == EMASS_EV`,
so `r0 = RE` for electrons and `RE m_e/m_p` for protons as the scripts intend. Slicing: the
outermost boundaries are the live z extrema under both methods (`slicing.jl:160-161, 466-467`),
so the jitter script's standard deviations are finite (measured 0.294/0.100 and 0.087/0.246 per
sigma_z at reduced settings), consistent with the README's "pinned to single extreme
macroparticles". Schedule script: the generic `_strong_strong_luminosity_evaluated` fallback is
`true` (`interface.jl:3084`) and the script's override is what makes skipped turns leave no
row, which the measured axes `[0, 100, 200]` and the retained evaluated NaN confirm.

Tolerance semantics. `beam_optics_interface_consistency.jl:58` broadcasts `isapprox` over the
6-tuple of arrays, which is a norm-wise test per coordinate (a single element may move by
`2 eps sqrt(N) = 2.8e-14` of the coordinate's norm, sixty-four times looser than an elementwise
`2 eps`); measured today the two constructions are bitwise equal in all six coordinates, so the
looseness is inert. Line 63 is atol-dominated (`8.9e-16` against a `pz` norm of 0.043, i.e.
`2e-14` relative) and strict. The moment script's `isapprox.` is over scalar rows and is
elementwise as intended.

Twiss route dump. Runs on the current analysis API (`analyze`, `matrix_scaled`,
`physical.tunes`, `dispersion.routes/primary`, `Determined` accessors, `_kappa_route` with a
`Determined` condition): 1005 rows over 201 row-producing fixtures (the 200 dense maps plus the
D12 weak cavity, the other 26 fixtures adding no row as the header says); `recomputed_normalized`
equals the reported `normalized` in every row (string compare at `%.6e`); no accepted (`:none`)
row has `ratio > 256`; 41 rejected rows sit below 256, the documented trace-residual case; one
`singular_coefficient` row.

README accuracy for the region. The Gaussian contract's representative table (README lines
676-684) matches today's run digit for digit (`1.5e-17`, `6.5e-16`, `2.8e-10`, `4.9e-10`,
`1.5e-7`); the fingerprint entry's "nine configurations" matches the nine that run; the PIC cache
entry's `LUMINOSITY_DEPOSIT_METHOD` control is documented in the README but missing from the
script header's "Controls" list (lines 12-18), a header nit only. `StrongStrongDiagnostics`
defaults are all `false` (`interface.jl:335-340`), so the "disabled versus enabled" pair in the
diagnostics script is a real pair (its vacuity is the solver, U54-8).

## Unchecked

- `emit_xcode.jl` was not executed (4096 turns x 1e5 macroparticles x two aspects, no reduction
  knob); its API surface is the same as `lambda_flat_converged.jl`'s, which ran, but its own
  emittance bookkeeping (lines 42-49) was only read.
- `strong_strong_pic_extreme_benchmark.jl` was not executed as a whole: it runs `git rev-parse
  HEAD` in the tree (line 74) and is a production-size GPU benchmark. Its include path, exported
  names and the CPU-override failure were probed at toy size; the CUDA-side provenance block
  (lines 99-119) was read, not run.
- The PIC cache contract's TSC arm and explicit `CIC`/`TSC` luminosity-deposition arms, the soft/PIC
  comparison with `OCTOPUS_SOFT_SIGMA_XY=true`, and the jitter and lambda scripts at their
  documented (converged) settings were not run; numbers quoted for them are at reduced settings
  and exercise the interface, not the physics claims.
- Negative controls for the three `_gpu_skip_or_error` scripts with CUDA hidden and
  `OCTOPUS_REQUIRE_GPU_CONTRACT=1` were not run (the helper was read at `Contracts.jl:1294`);
  only the effectiveness script was run hidden (U54-4).
- Of the six estimator copies (U54-7) only the two inside my region were diffed against each
  other and against `coherent_mode_scans.jl`; the other three files are outside the region.
- The previous audit's U24 report was consulted only through its `LEAD_INDEX` rows (its region was
  other scripts); U25 was read in the sections named under Provenance, not in full.
- The `hvoffset` construction-time acceptance (U54-2's seam) and the contract's self-warning
  (U54-10) are cross-file seams noted for the auditor, not investigated.
