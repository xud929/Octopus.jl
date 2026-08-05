# U21 Report — validation/ remainder (commit dbefe42)

## Coverage
Read line-by-line: slice_longitudinal_zscan.jl (618), high_energy_weakstrong_limit.jl (420),
generate_ptc_reference.jl (396), gaussian_slicing_convergence.jl (286),
strong_strong_spectral_comparison.jl (276), slice_interpolation_emittance_growth.jl (239)
+ _summary (116), lattice_cells.jl (235), pic_option_consistency.jl (233) + _summary (137),
symplecticity_validation.jl (196), tracking_backend_consistency.jl (168),
strong_strong_pic_extreme_benchmark.jl, crossing_luminosity_anchor.jl,
beam_optics_interface_consistency.jl, strong_strong_pic_cache_backend_consistency.jl,
strong_strong_observer_plan_consistency.jl, tracking_task_turn_update.jl,
strong_strong_gaussian_backend_consistency.jl, strong_strong_luminosity_schedule_output.jl,
strong_strong_diagnostics_consistency.jl, moment_observer_backend_consistency.jl,
public_configuration_effectiveness.jl, tune_estimator_calibration.jl, validation/README.md,
validation/reference/ptc_madx_5.03.06.tsv (header + case census). Cross-checked against
src/contracts/Contracts.jl (SymplecticityContract, HighEnergyWeakStrongLimitContract,
PTCConsistencyContract), src/tasks/strongstrong/{interface,pic_cpu}.jl, test/runtests.jl,
.github/workflows/ci.yml, AGENTS.md, paper/README.md, result/ artifacts. No repository file
modified. No long script executed (probes were grep/read + result-file inspection only).

## Assert-vs-print census
Mechanically FAIL on regression (error() gates): high_energy_weakstrong_limit (3 of 4
computed verdicts), symplecticity_validation, tracking_backend_consistency,
beam_optics_interface_consistency, strong_strong_pic_cache_backend_consistency,
strong_strong_gaussian_backend_consistency, strong_strong_observer_plan_consistency,
strong_strong_diagnostics_consistency, strong_strong_luminosity_schedule_output (exact
row match incl. evaluated NaN), tracking_task_turn_update (bitwise),
moment_observer_backend_consistency (CUDA-mandatory), public_configuration_effectiveness
(fails only on :failed; :skipped passes by design, matching README).
Print/TSV only (human must read): slice_longitudinal_zscan, gaussian_slicing_convergence,
strong_strong_spectral_comparison, slice_interpolation_emittance_growth (+summary),
pic_option_consistency (+summary), crossing_luminosity_anchor, tune_estimator_calibration,
strong_strong_pic_extreme_benchmark, lattice_cells (asserts only stable-point existence).

## Leads

### U21-1 [medium] validation/README.md — two committed scripts have no README entry
`crossing_luminosity_anchor.jl` and `tune_estimator_calibration.jl` appear nowhere in
validation/README.md, yet both are git-tracked and cited as manuscript evidence by
paper/README.md:177,186. crossing_luminosity_anchor's outputs (result/lum_anchor/*.lum,
printed Piwinski R ratios) are documented nowhere.
Repro: `grep -c crossing_luminosity_anchor validation/README.md` → 0.

### U21-2 [medium] high_energy_weakstrong_limit.jl:392-419 — spectral model verdict never asserted
`spectral_model_passed` is computed (lines 232-233, 392-393) with env-tunable tolerances
(`OCTOPUS_HIGH_ENERGY_SPECTRAL_MODEL_LUM_RTOL`/`SIZE_RTOL`, lines 48-51, default 0.08),
but the main block (414-420) errors only on `gaussian_passed`, `pic_passed`,
`spectral_limit_passed`. A spectral-solver model regression of any size prints and exits 0.
The suite's HighEnergyWeakStrongLimitContract (Contracts.jl:1254+) contains no spectral
cases at all, so this comparison is asserted nowhere. Env names ("RTOL") imply gating.
Repro: read lines 414-420; grep spectral in Contracts.jl:1308-1400.

### U21-3 [medium] lattice_cells.jl:199-224 — metrics and contract results printed, never gated
Symplecticity residual, invariant drift, and both
ElementTrackingBackendConsistencyContract results (cpu/cpu, cpu/cuda) are printed and
written to result/lattice_cells.tsv but never checked; `cpu.status === :failed` still
exits 0. Only "no stable working point" (line 178) errors. This also weakens U21-5: the
only standalone script exercising magnet backend consistency is non-gating.
Repro: read lines 210-224 — no `passed(...) || error` anywhere.

### U21-4 [medium] symplecticity coverage claim stale; header tol stale
README.md ("computes finite-difference Jacobians for all current six-dimensional
symplectic runtime maps") and the script's "checks runtime maps that are registered as
Symplectic6DMap" are false since the lattice-magnet family landed: drift, quadrupole,
sextupole, octupole, multipole, sbend, rbend, solenoid, thin multipole all default to
Symplectic6DMap (src/knowledge/Methods.jl:61) and none appear in
symplecticity_validation.jl:117-126 nor _symplecticity_contract_cases()
(Contracts.jl:1171-1199, docstring enumerates only 6+2). Partial mitigation:
lattice_cells.jl measures composed-cell J'SJ-S (not gated, U21-3); no coverage at all for
solenoid/rbend/thin-multipole/misalignment/reftilt paths. Additionally
symplecticity_validation.jl:11 advertises `OCTOPUS_SYMPLECTICITY_TOL=5e-7` while the code
default (line 35) is 5e-8 (residue of the S3 tolerance fix). Also the script's case list
(8) and the contract's (10, adds ThinStrongBeamChromatic/Exact) are no longer mirrors.
Repro: diff case names; grep "5e-7" validation/symplecticity_validation.jl.

### U21-5 [medium] tracking_backend_consistency.jl line predates the magnet family
The mixed line (lines 70-126: Linear6D, CrabDispersion, MomentumDispersion, XYCoupling,
LorentzBoost pair, ThinCrabCavity, ChromaticityKick, ThinStrongBeam, GaussianStrongBeam,
LumpedRad) contains no LatticeMagnet, solenoid, or thin multipole, though AGENTS.md:297
names this script as the post-change check and every magnet spec declares
ElementTrackingBackendConsistencyContract (src/elements/lattice_magnets.jl:993+).
Magnet coverage exists only in test/runtests.jl:3738-3749 (FODO, DBA+sext; GPU allowed
:skipped) and lattice_cells.jl (not gated, U21-3).
Repro: grep -c "Spec" validation/tracking_backend_consistency.jl vs element list.

### U21-6 [medium] generate_ptc_reference.jl — `Case.octopus` is dead and diverges from the real specs
The `octopus::Dict` field (line 84; docstring line 74 "names the spec keywords the
contract will build from") is never written to the TSV nor read anywhere — the writer
loop (385-394) uses only name and coordinates. The authoritative specs live separately in
Contracts.jl `_ptc_reference_specs()` (1568-1750), and several script dicts contradict
them (e.g. "quadrupole_fringe" dict `(:kind=>:quadrupole,:L=>0.4)` vs real spec with
k1=1.7, fringe=:multipole, highest_fringe=2; every sbend dict omits
bend_model/bend_fringe). Divergence hazard: a case added to the script but not to the
contract dict yields table rows that are SILENTLY skipped (Contracts.jl:1787
`haskey(specs, name) || continue`); only the reverse direction (spec w/o rows) fails
(1799-1809). Repro: grep -n "case.octopus" validation/generate_ptc_reference.jl → only
constructors.

### U21-7 [minor] PTC table selection and empty per-case atol
Contracts.jl:1762 `last(sort(files))` picks the reference lexicographically: MAD-X
"5.10.x" would sort BEFORE "5.09.x", and any second committed table is silently shadowed
with no warning. `_PTC_DEFAULT_ATOL` (1752) is an empty Dict although the contract
docstring (1556-1559) points to "per-case defaults below". Provenance itself is sound:
header records version+flags, filename carries version, and the machine's madx (5.03.06)
matches the committed table; regeneration at the same version overwrites in place so git
diff notices value drift.

### U21-8 [minor] slice_longitudinal_zscan.jl — undocumented 4th output; dead helper
Writes `_cells.tsv` (line 608, and result/slice_longitudinal_zscan_cells.tsv exists) but
both its own docstring (68-72) and README (Outputs list) name only .tsv/_summary/_jumps.
`lagrange3` (141) is defined and never used.

### U21-9 [minor] pic_option_consistency_summary.jl:105-127 — strict check mixes beams, wrong normalization
The coordinate comparison pools beam 1 (electron) and beam 2 (proton) rows into one
per-turn vector (`byturn` keyed by `k[1]` only, line 119) and normalizes both by
hardcoded electron sigmas `sigx, sigy = 106.0e-6, 9.5e-6` (109); proton rows should use
95/8.5 um. The advertised "catches a systematic per-particle bias" metric is therefore
beam-blind and mildly mis-scaled. Also runs without a "base"/"base_c" tag are silently
dropped from the table (line 87).

### U21-10 [flag] Long/GPU scripts — do not run
- slice_interpolation_emittance_growth.jl: recorded 817 s for ONE arm/seed
  (result/emittance_growth_linear_n15_cic_s1.meta.tsv, elapsed_s=816.96, 800 turns);
  default 600 turns is ~600 s; full study is many arms x seeds. >420 s confirmed.
- pic_option_consistency.jl: recorded 0.34-1.45 s/turn x 200 turns per arm
  (result/pic_option_*.meta.tsv) plus package load; heavier arms (quad 1.32, node 1.45
  s/turn) reach ~300-380 s compute alone — the second known-long one; the README
  workflow requires several arms per comparison.
- strong_strong_pic_extreme_benchmark.jl: CUDA-required (2.56M macroparticles), includes
  test/examples/strong_strong_tracking.jl and reads leaked globals (task, input, solver,
  policy) from it; cannot run here.
- moment_observer_backend_consistency.jl:13 hard-errors without CUDA (no :skipped path,
  unlike every sibling backend script).

### U21-11 [minor] gaussian_slicing_convergence.jl — "correctness check" is print-only; dead config
Self-described as "the correctness check for the slice_method implementations" (lines
4-6) but contains no assertion — agreement at large ns must be read by a human. Dead
config field `ns_crosscheck` (88) is never used. Uses Random.Xoshiro randn (195) rather
than the project counter RNG, so recorded values are Julia-version-dependent (all other
scripts here seed philox).

### U21-12 [info] paper/data/crossing_lum_anchor.tsv is hand-transcribed
The script prints R values and writes only .lum files under result/lum_anchor/; the paper
TSV naming it as source (paper/README.md:177) was assembled by hand — no
machine-reproducible path from script to paper artifact.

### U21-13 [medium, confirms U3-6] Contracts whose only runner is a validation script
- PublicConfigurationEffectivenessContract: run ONLY by
  validation/public_configuration_effectiveness.jl (repo-wide grep; nothing in src/ use,
  test/, examples/). CI (.github/workflows/ci.yml) runs only Pkg.test → never exercised
  automatically; on a CUDA-less runner it would be :skipped anyway.
- StrongStrongPICBackendConsistencyContract: only
  validation/strong_strong_pic_cache_backend_consistency.jl.
- StrongStrongGaussianBackendConsistencyContract: validated only by
  validation/strong_strong_gaussian_backend_consistency.jl (other scripts borrow its
  base-beam builders without validating).
All three skip without CUDA, so nothing anywhere runs them to completion except a manual
GPU-machine invocation.

## Sound (verified, no action)
- PTC provenance chain: 55 script cases == 55 table cases == 55 contract specs (diffed);
  header records MAD-X 5.03.06 + flag set (TIME/EXACT/MODEL); machine madx matches;
  contract fails loudly when a declared spec has no table rows; rbarc=false, permfringe
  per-element, and T-negation match the theory-note traps as README describes.
- Theory-doc recorded z-scan numbers reproduce current result TSV (src 4 Δp_y: peak
  1.0e-5, lin 2.3e-9, quad 3.2e-10, gain 7.3 == 7.28 in
  result/slice_longitudinal_zscan_summary.tsv).
- RNG hygiene: every script seeds deterministically (philox with explicit seeds; the two
  Julia-RNG exceptions noted in U21-11 and moment_observer's MersenneTwister are seeded).
- All ~40 internal helper symbols used by the include-based scripts still exist in src;
  the zscan `_pic_interaction!(…, ws, nothing, nothing)` call is valid (cache isa-check
  tolerates nothing); spectral comparison already migrated to `_spectral_field_ws`.
- pic_option_consistency's read-one-luminosity-row assumption still holds:
  StrongStrongTask default `luminosity_append=false` rewrites per execute!, and the
  parser takes the last data row anyway.
- Output discipline: every writer targets result/ (mkpath'd) or tempname(); non-CIC
  z-scan runs use a distinct file stem; extreme-benchmark summary records git commit,
  GPU, driver, and resolved launch config.
- strong_strong_luminosity_schedule_output's expected rows match the documented contract
  (scheduled turns only, evaluated NaN preserved, collision-column header).
- symplecticity default floor 5e-8 mirrors SymplecticityContract (S3 fix present in both);
  tolerances now bind (declared per-case values >= floor).
- tracking_backend_consistency CPU/CPU bitwise rationale matches the fused-path design;
  REQUIRE_GPU semantics correct (skip -> error only when required).
- beam_optics_interface_consistency asserts exact equality / 2-4 eps bounds — binding.
