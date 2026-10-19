# U42: validation: Twiss acceptance windows, cells, identities, lattice cells, survey reference, symplecticity, backend consistency

Reading unit U42 of the 2026-10-18 comprehensive audit. Tree: `/cfs/ad/dxu/Library/Julia/Octopus`
at 24e8683, read-only. Every claim below is a LEAD, not a finding. Hypotheses briefed: (1) derived
vs copied case lists and coverage tripwires; (2) the backend-consistency script's per-kind arm
(every registry kind, classes from the declarations, GPU leg forced on where required); (3)
acceptance windows derived by a mechanism, not fitted.

## Region

All seven files, every line (2667 lines):

| file | lines | read | executed |
|---|---|---|---|
| `validation/twiss_dispersion_acceptance_windows.jl` | 743 | 1-743 | yes (native arm, output to scratch) |
| `validation/twiss_benchmark_cells.jl` | 536 | 1-536 | yes (`write_benchmark_maps` to scratch, diffed) |
| `validation/twiss_dispersion_identities.jl` | 281 | 1-281 | yes (scratch copy; exit 1, see U42-2) |
| `validation/lattice_cells.jl` | 279 | 1-279 | yes, twice (CUDA active; CPU-only with the GPU leg required) |
| `validation/generate_madx_survey_reference.jl` | 160 | 1-160 | yes (scratch copy, MAD-X 5.03.06; diffed against the committed table) |
| `validation/symplecticity_validation.jl` | 196 | 1-196 | yes (all three legs plus a cross-check against the contract) |
| `validation/tracking_backend_consistency.jl` | 472 | 1-472 | yes (package mode, CUDA active, all arms) |

Read for comparison, not audited: `src/contracts/Contracts.jl` 922-965 (the backend contract's
`validate`), 1252-1325 (`_contract_backends_available`, `_require_gpu_contract`, `_contract_policy`,
`_contract_default_initial_rep`, `_contract_rep_for_backend`), 1690-1990 (`SymplecticityContract`,
`_symplecticity_contract_cases`, its `validate`), 2650-2800 (`MADXSurveyConsistencyContract`);
`src/track/Track.jl` 160-460 (`CrossBackendRounding`, `_rounding_class`, `_cross_backend_rounding`,
`_cross_backend_agreement`, `_cross_backend_violations`, `_cross_backend_summary`);
`src/knowledge/Knowledge.jl` 296-310 (`ElementMeta`), 446, 616-624, 680-681, 893-901;
`test/runtests.jl` 4425, 4829, 4911, 5055, 5181, 5208-5232, 5432-5700 (the `c` values), 6292-6330
(the identities dry-run testset), 13817-13829, 24733-24734, 29201-29215 (the suite's symplecticity
leg); `validation/README.md` 252-356, 728-746, 1217-1319, 1324, 1709-1837;
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U24_report.md` (leads U24-2..U24-7) and
`U25_report.md` (U25-4, U25-10, U25-13); `docs/history/twiss_dispersion_analysis_history.md`
12298-12299, 13296-13312, 14872-14890; `docs/todo.md` row 20 (grep for `c_scaling_invariance`);
`docs/history/crab_cavity_noise_audit_fixes_batch3_2026_10_17.md` (grep for the per-kind table).

## Provenance

READ line by line: the seven region files in full (ranges above) and the comparison ranges listed.

EXECUTED (scratch: `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U42/`;
all probes package mode, `--project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4`, Julia 1.11 series
as installed; nothing written to the tree, the two scripts that write `result/` were copied under
`probes/U42/tree/validation/` so their `result/` resolves to `probes/U42/tree/result/`):

- `run_tbc.jl` -> `tbc.log`: `validation/tracking_backend_consistency.jl` at its defaults (N = 10000,
  2 turns, seed 123456789, philox), CUDA functional, 122.3 s, exit 0. CPU/CPU composed line:
  `max_abs_error` 0.0 over 60000 coordinates. CPU/GPU composed line: `max_abs_error`
  9.714e-17, `global_rel_error` 4.497e-15, `max_component_rel_error` 8.099e-12 (tolerance 1e-10).
  Accelerating-cavity single pass CPU/GPU: 6.830e-18 / 1.099e-11. Aperture arm: 6725 of 10000
  particles killed on both backends (40350 slots lost on both, 19650 compared, `lost_one_backend` 0),
  CPU/CPU and CPU/GPU. Per-kind arm: 34 instances within their declared classes on CPU/CPU and
  CPU/GPU; the largest measured ulps-of-scale against the declared bound: `lorentz_boost` px 1312
  / 16384, `rev_lorentz_boost` px 1311 / 16384, `sbend` px 1419.56, x 1050, py 142, y 55 / 8192,
  `thin_strong_beam` px 411.75, py 330.93 / 2048, `gaussian_strong_beam` px 313, py 236.19 / 2048,
  `thin_strong_beam (misaligned)` px 366, py 164.25 / 2048, `thin_accelerating_cavity` pz 31.5 /
  128, `quadrupole (misaligned)` x 10 / 32, `multipole (misaligned)` y 8 / 32, `solenoid` px 7 /
  128, `sextupole (misaligned)` x 5 / 1024, `drift` x 3 / 64, `chromaticity_kick` x, px 3 / 8;
  `octupole` and every thin kick bitwise on all six coordinates.
- `symp_probe.jl` -> `symp.log`: the script's three legs. 27 cases, all passed; linear maps
  1.3e-13 to 4.2e-13, `ThinStrongBeam` 7.9077e-8 (identical to 7 digits for the three virtual
  drifts), `GaussianStrongBeam` 4.240e-8, `Solenoid` 5.41e-13, `SolenoidCurvedMultipole` 2.12e-10,
  `Drift` 1.30e-12, `Quadrupole` 3.43e-13, `Sextupole` 7.50e-13, `Octupole` 1.81e-13, `Multipole`
  6.19e-13, `SBend` 7.63e-12, `ThinRFCavity` 4.88e-14, the seven thin kicks and `Marker` 1.32e-13.
  Coverage tripwire: `kinds_declaring_without_case` = 0 over 22 `Symplectic6DMap` kinds. Lorentz:
  forward det 1.0001500137505905 (expected 1.000150013751004), reverse 0.9998500087495594
  (expected 0.9998500087497458), inverse residual 8.27e-19, determinant error 4.13e-13. Cross-check:
  the script's 27 residuals are bitwise equal to `validate(SymplecticityContract()).metrics`
  (27 of 27) and so are both Lorentz metrics. `DEFAULT_STEP == contract.step` (3e-7),
  `DEFAULT_TOL == contract.default_tolerance` (1e-11). Legend probe for backend script line 460:
  `marker` prints `uuuuuu` where `_cross_backend_summary` marks `------`; `patch` prints `uuuuuu`
  for `uuuuu-`; `thin_quadrupole` prints `ububuu` for `-b-b--`.
- `bench_cells_probe.jl` -> `bench_cells.log`, `twiss_benchmark_maps_regen.tsv`, and the shell diff
  (`committed_rows.tsv`, `regen_rows.tsv`): `write_benchmark_maps` regenerated in 19.4 s, 66 lines
  both; header line 3 differs; 14 of 45 data rows differ: U2, K2, B4, B4K, G6, T6, B5, each in
  `bare` and `task`, max |delta| 6.661e-16 (m52 of the U2 family), 7.772e-16 (m56 of K2/B4K
  task), 2.442e-15 (m16 of G6); the 31 other rows (S0, U1, K1, R_*, Rd_*, W1, W2, D6_*, D8_*,
  F8) are bitwise identical. `TwissDispersionIdentityContract().dense_maps` = 20 = the module's
  `CONTRACT_DENSE_MAPS`; `dense_maps_4d` = 5 = `CONTRACT_DENSE_MAPS_4D`. (The probe file itself
  has a soft-scope bug after its key lines; the row-level comparison was done with `paste`/`awk`.)
- `run_lattice.jl` -> `lattice.log` (CUDA active, defaults N = 4096, 4 turns, LONG = 2000),
  185.0 s, exit 0, all gates green: working points FODO kq = 1.60, DBA kf = 1.50 kd = -1.10, TBA
  kf = 0.90 kd = -1.00; symplectic residuals 1.33e-15, 1.22e-15, 4.44e-16, 4.44e-16, 1.89e-15,
  1.67e-15 (gate 5e-7); |tr| 0.0066 to 1.5510; invariant drifts 3.56e-9, 8.29e-4, 9.39e-5,
  7.24e-4, 7.35e-5, 1.40e-3 (gate 5e-3; identical to the U24 figures of 2026-08-05); CPU/CUDA
  max |delta| 4.879e-19, 5.421e-19, 5.204e-18 x4 (atol 1e-10). `lattice_nogpu_require.log`:
  `CUDA_VISIBLE_DEVICES="" OCTOPUS_REQUIRE_GPU_CONTRACT=1 OCTOPUS_LATTICE_LONG=50
  OCTOPUS_LATTICE_N=256 OCTOPUS_LATTICE_TURNS=1`: exit 0 in 32.1 s, `cpu/cuda skipped` for all six
  cells, closing line "all cells gated: symplectic, linearly stable, invariant-conserving, and
  backend-consistent".
- `run_ident.jl` -> `ident.log`, `tree/result/twiss_dispersion_identities.tsv` (59 rows): the
  identities script at its defaults (seed 20260911, 200 + 20 maps): exit 1,
  "`c_scaling_invariance` on F6a dense 6x6 map 98: value 6.706850093838689e-12 exceeds c eps kappa
  = 6.031398639102667e-12" (ratio 1.111989, c = 8); `TW-TENTH above_tenth=20 above_quarter=8
  above_half=2 above_one=1 of 57`; `TW-DIAG expected=17 silent=0`; `TW-KINDS declaring=23
  analyzed=18 refused=5 failed_example=0 without_result=0 without_example=0`; `TW-PINS
  dense6_unresolved=0 dense4_skipped=0 verdicts_consistent=249 verdicts_inconsistent=0
  absolute_pins_checked=3`; normalizer ratios 5.3359 (pin 64) and 5.4372 (pin 32); `TW-DIGEST
  0x5c85f01a66ae5777` (the history's last recorded native digest is 0xecc3e19b276694c4; the map-98
  value and floor are digit-for-digit the recorded ones).
- the acceptance-windows driver from the tree with its three arguments explicit and the output in
  scratch -> `acceptance.log`, `acceptance_windows.md` (352 lines), exit 0: `c_coast [0, 2.183e7]
  inside (64)`, `c_coef [3.764, 1.546e8] inside (64)`, `c_ell [28.28, 1.998e8] inside (64)`,
  `c_graph [2.591, 6.212e10] inside (64)`, `c_inv [53.41, 0.3602] EMPTY (256)`,
  `c_inv_unconditioned [1.571e5, 7.131] EMPTY (256)`, `c_iso [0, 1.759e11] inside (64)`, `c_ohmi
  [43.95, 2.252e13] inside (64)`, `c_sep [10.26, 5138] inside (256)`, `c_stop [5.793, Inf] inside
  (16)`, `c_tie [38.20, 1.234e11] inside (64)`, `c_triple [9.139, 450.3] inside (64)`; section 3:
  17/17 families green below c and red above it; oracle table: 34/39 maps within 2e-10 by the
  default longitudinal rule, 39/39 with the certified index (the default differs on 5 of 36 bunched
  maps).
- the survey generator copied to `tree/validation/` and run with cwd `madx_run/` (MAD-X 5.03.06 at
  `/usr/local/bin/madx`) -> `madx_gen.log`, `tree/validation/reference/survey_madx_5.03.06.tsv`:
  byte-identical to the committed `validation/reference/survey_madx_5.03.06.tsv` (`diff` exit 0,
  `survey_diff.txt` empty); no stray files in the cwd.
- `small_probe.jl` -> `small_probe.log`: 30 registered kinds declare
  `ElementTrackingBackendConsistencyContract` (31 registered specs; only `:line` does not); the
  kinds with a `phase_noise` parameter are `thin_crab_cavity` and `thin_rf_cavity`; bare
  `QuadrupoleSpec/SextupoleSpec/MultipoleSpec` compile to `LatticeMagnet` with bound 32, the
  script's instances compile to `MisalignedElement` with bounds 32 / 1024 / 32;
  `_require_gpu_contract()` reads only the environment; `twiss_benchmark_cells.jl` has 536 lines.

## Leads

### LEAD U42-1 [Minor, confidence high] validation/README.md:733
Claim: the README's entry for `symplecticity_validation.jl` describes the coverage the script had before the 2026-08-05_b repairs ("the 12 cases", "7 of the 22 registered kinds", "the thin kickers, marker and thin RF cavity by neither"), and two other hand-copied counts in the same file are stale as well.
Mechanism: hand-copied knowledge (class 14 / class 2): the contract's list grew from 12 to 27 cases and the structural tripwire now reports 0 uncovered of 22 `Symplectic6DMap` kinds (measured), but README 733-741 still states the old gap and even points the reader to "the script header", whose own paragraph (script lines 13-21) says the "no case here" wording was stale from the audit until 2026-09-16 -- the README was not swept. In the same way README 255-256 says the backend-consistency line carries "every element kind declaring that contract -- 29 of them" while 30 kinds declare it (the single-pass `thin_accelerating_cavity` joined on 2026-08-14), and README 1324 gives `twiss_benchmark_cells.jl` as "533 lines" (536). None of the three has a tripwire; the suite's docs checks (13817-13829) look for symbol names, not counts.
Repro: `grep -n "12 cases\|7 of the 22\|by neither\|29 of them\|533 lines" validation/README.md` -> 5 hits; `julia --project=. -e 'using Octopus; println(length(Octopus._symplecticity_contract_cases()), " ", validate(SymplecticityContract()).metrics[:kinds_declaring_without_case]); println(count(T -> (m = Octopus._element_meta_or_nothing(T); m !== nothing && any(C -> C === ElementTrackingBackendConsistencyContract, m.contracts)), Octopus.registered_element_specs()))'` -> `27 0` and `30`; `wc -l validation/twiss_benchmark_cells.jl` -> 536.

### LEAD U42-2 [Minor, confidence high] validation/twiss_dispersion_identities.jl:277
Claim: the documented default run of the identities script exits 1 on 24e8683 (`c_scaling_invariance` on dense map 98 at 1.112 of its frozen multiplier), a ledgered owner-decided state that the README entry a reader follows does not mention.
Mechanism: the multipliers are frozen on the contract's 20 + 5 maps while the script runs 200 + 20 (header lines 26-34), map 98 exceeds c = 8 by 11 % (6.70685e-12 against 6.03140e-12, digit-for-digit the value the history records), and the gate at line 277 correctly errors. `docs/todo.md` row 20 and the history (14872-14890) carry it as "native red on `c_scaling_invariance` (map 98) stays until items 6/12" by the owner's 2026-09-14 decision to keep the freezing set; but `validation/README.md` 1709-1756 presents the exit only as a possibility ("can put a row ... over it (the gate then exits non-zero naming the row)"), so a developer running the documented command on main gets a red run with no pointer to the decision. The Haswell arm is recorded exit 0 (not re-measured here). Class 14 (documentation as claims) on top of a correctly executing gate; reported because the brief asks for the measured state of every documented check.
Repro: `julia --project=. validation/twiss_dispersion_identities.jl` -> exit 1 with "identity c_scaling_invariance on F6a dense 6x6 map 98: value 6.706850093838689e-12 exceeds c eps kappa = 6.031398639102667e-12" and `TW-TENTH ... above_one=1 of 57`; `grep -n "c_scaling_invariance" docs/todo.md` -> the row that ledgers it.

### LEAD U42-3 [Minor, confidence high] validation/twiss_benchmark_cells.jl:503
Claim: `write_benchmark_maps` no longer reproduces the committed `validation/reference/twiss_benchmark_maps.tsv`: its header text changed after the table was committed and the seven sector-bend fixtures differ at roundoff, so the committed Octopus side of the external Twiss benchmarks is stale against the tree that carries it.
Mechanism: the module is the table's producer ("producer: validation/twiss_benchmark_cells.jl write_benchmark_maps (Octopus tree of the commit that carries this file)", line 508) but nothing regenerates or re-diffs it; header line 3 (the consumers sentence) was edited in the module without regenerating (committed: "consumers: validation/twiss_madx_benchmark.jl, validation/twiss_xsuite_benchmark.jl; documented for, not read by, validation/twiss_ptc_benchmark.jl"; module now: "consumers: validation/twiss_xsuite_benchmark.jl (by sha256 against its sidecar); documented for, not read by, validation/twiss_madx_benchmark.jl and validation/twiss_ptc_benchmark.jl, which rebuild the maps from this module"), and the 2026-10-17 unit-K re-forming of the sector-bend body moved every U2-based row (U2, K2, B4, B4K, G6, T6, B5; bare and task; 14 of 45 rows) by 6.7e-16 to 2.4e-15 absolute while the 31 bend-free rows stayed bitwise. Physically nothing changed; but the xsuite consumer pins this table by sha256 against a sidecar, so the committed numbers are the pre-unit-K maps and the next regeneration breaks the pin (class 14 / class 7: a committed artifact whose producer drifted).
Repro: `julia --project=. -e 'using Octopus; include("validation/twiss_benchmark_cells.jl"); write_benchmark_maps("/tmp/maps.tsv")'` then `diff validation/reference/twiss_benchmark_maps.tsv /tmp/maps.tsv | wc -l` -> non-zero; `paste <(grep -v "^#" validation/reference/twiss_benchmark_maps.tsv) <(grep -v "^#" /tmp/maps.tsv) | awk -F'\t' 'NR>1{n=42;w=0;for(j=7;j<=n;j++){d=$j-$(j+n);if(d<0)d=-d;if(d>w)w=d} if(w>0) print $1,$2,w}'` -> 14 rows, max 2.442e-15 (G6).

### LEAD U42-4 [Minor, confidence high] validation/tracking_backend_consistency.jl:460
Claim: in the CPU-only branch of the per-kind arm the "declared" legend prints the first character of the class symbol, so `:untouched` and `:ulp` are both `u`, contradicting the legend the arm prints at line 418 and the `-` that `_cross_backend_summary` uses.
Mechanism: `join((string(getfield(class, k))[1] for k in Octopus._COORDINATE_NAMES))` maps `:untouched -> 'u'`, `:ulp -> 'u'`, `:bitwise -> 'b'`, while line 418 promises "u (ulp), b (bitwise), - (untouched)" and `Track.jl:442` `mark(c)` implements that promise for the GPU branch. On a CPU-only run the all-untouched marker reads `uuuuuu`, i.e. as all-ulp, and a mixed kind such as `patch` (`uuuuu-`) becomes indistinguishable from an all-ulp one. Print-only, but it is the one line a CPU-only CI log carries about the declarations (class 14).
Repro: `julia --project=. -e 'using Octopus; c = Octopus._cross_backend_rounding(compile_runtime(MarkerSpec())); println(join((string(getfield(c, k))[1] for k in Octopus._COORDINATE_NAMES)), " vs ", join((getfield(c,k) === :ulp ? "u" : getfield(c,k) === :bitwise ? "b" : "-" for k in Octopus._COORDINATE_NAMES)))'` -> `uuuuuu vs ------`.

### LEAD U42-5 [Minor, confidence high] validation/tracking_backend_consistency.jl:182
Claim: the per-kind table, advertised as "where each declaration meets its measurement", carries no bare quadrupole, sextupole or multipole: all three ride only as `MisalignedElement` wrappers, whose class is the wrapper's, so the bare `LatticeMagnet` declarations of those kinds are measured by the script against a wrapper bound (sextupole: 1024 instead of the declared 32).
Mechanism: lines 182-186 give the quadrupole `x_offset=1.0e-4`, the sextupole `tilt=0.01` and the multipole `y_offset=1.0e-4`, chosen for parity coverage of the frame wrappers; `compile_runtime` returns `MisalignedElement` for all three (the log tags them "(misaligned)"), and `_cross_backend_rounding(::MisalignedElement)` is `_rounding_written_over(inner, written, bound, why)` with the larger of the two bounds (Track.jl 315-319). The per-kind arm therefore never evaluates `_cross_backend_rounding(::LatticeMagnet)` for a quadrupole, sextupole or multipole on its 10000-particle beam; the only measurement of those bare declarations is the suite's registry-example testset (400 particles, 3 turns). Drift, octupole, sbend and solenoid are bare. Hypothesis 2 ("classes consumed from the declarations"): consumed, but for three kinds through the wrapper's declaration.
Repro: `julia --project=. validation/tracking_backend_consistency.jl | grep -E "^  (quadrupole|sextupole|multipole)"` -> exactly three rows, each tagged `(misaligned)`, none bare; `julia --project=. -e 'using Octopus; println(Octopus._cross_backend_rounding(compile_runtime(SextupoleSpec(L=0.25, k2=6.0, nst=2))).ulp_bound, " ", Octopus._cross_backend_rounding(compile_runtime(SextupoleSpec(L=0.25, k2=6.0, nst=2, tilt=0.01))).ulp_bound)'` -> `32 1024`.

### LEAD U42-6 [Minor, confidence high] validation/symplecticity_validation.jl:34
Claim: `DEFAULT_STEP` (3e-7) and `DEFAULT_TOL` (1e-11) are literal mirrors of `SymplecticityContract().step` and `.default_tolerance` with no tripwire, the very pattern the file's own U24-7 comment (lines 95-101) says it removed for the Lorentz leg.
Mechanism: lines 34 and 41 parse an environment variable with a hard-coded default and the comment at 40 says "Kept equal to the SymplecticityContract floor so the two stay mirrors of each other"; `_SYMP_CONTRACT_DEFAULTS` (line 102) already exists and the Lorentz defaults read it (105-108), so the two remaining literals could read `.step` and `.default_tolerance` the same way. They agree today (measured); a contract change moves the suite's leg (runtests 29210 passes `step=3.0e-7` explicitly, another copy) and this script apart silently (class 2).
Repro: `grep -n '"3e-7"\|"1e-11"\|lorentz_angle=_SYMP' validation/symplecticity_validation.jl; grep -n "step::Float64 = \|default_tolerance::Float64 = " src/contracts/Contracts.jl` -> two literals beside two derived defaults; `julia --project=. -e 'using Octopus; c = SymplecticityContract(); println(c.step, " ", c.default_tolerance)'` -> `3.0e-7 1.0e-11`.

### LEAD U42-7 [Minor, confidence high] validation/symplecticity_validation.jl:83
Claim: the "one case list, two independent evaluators" claim overstates: the script's finite-difference Jacobian and symplectic form are verbatim copies of the contract's, so a defect in the shared differentiation hides itself in both.
Mechanism: `finite_difference_jacobian6` (52-64) and `symplectic_form6` (43-50) are line-for-line `_contract_fd_jacobian6` (Contracts.jl 1767-1779) and `_symplectic_form6` (1758-1765) with the same relative step rule `h = step * max(abs(q), 1)` and the same central difference; the measurement confirms it: all 27 residuals and both Lorentz metrics are bitwise equal to the contract's. Independence would need a different route (complex step, `one_turn_matrix`, or the analytic Jacobian the linear maps expose). Class 13 (a sweep whose instrument is not independent of what it checks) and class 14 (the comment claims independence).
Repro: `diff <(sed -n '52,64p' validation/symplecticity_validation.jl) <(sed -n '1767,1779p' src/contracts/Contracts.jl)` -> only the signature line differs; `probes/U42/symp.log` "residuals bitwise equal to the contract's: 27 of 27".

### LEAD U42-8 [Minor, confidence med] src/contracts/Contracts.jl:1814 (seam: the table `validation/symplecticity_validation.jl:135` judges by)
Claim: the six original symplecticity cases and the Lorentz determinant check carry tolerances 3e5x to 1e7x above their measured residuals, against the contract's own "~100x the measured residual" rule for the fifteen cases added later.
Mechanism: measured at the default step, `Linear6D` 1.50e-13 against 5e-8 (3.3e5x), `CrabDispersion`/`XYCoupling` 1.32e-13 against 5e-8 (3.8e5x), `ThinCrabCavity` 1.32e-13 against 5e-7 (3.8e6x), `ChromaticityKick` 4.16e-13 against 5e-6 (1.2e7x), `Solenoid` 5.41e-13 against 5e-7 (9.2e5x); the Lorentz determinant error 4.13e-13 against `lorentz_determinant_tolerance` 2e-7 (4.8e5x) and the inverse residual 8.3e-19 against 1e-10. The contract's comment (1861-1865) sets the newer cases at ~100x their floor so they "can actually catch a break"; a linear-map coefficient defect at the 1e-7 level, or a boost angle off by 1e-4 relative (det moves by ~3e-8), passes the older rows. Class 8 (tolerances resting far from their floor). The beam-beam rows (0.08-0.16 of tolerance, truncation-dominated) are not part of this lead. Out of region; the script mirrors the table.
Repro: `julia --project=. probes/U42/symp_probe.jl` ratio table (`residual/tol` 3.0e-6, 2.64e-6, 3.61e-6, 2.64e-6, 2.64e-7, 8.33e-8, 1.08e-6 for the seven rows named); `grep -n "tolerance=5.0e-8\|tolerance=5.0e-7\|tolerance=5.0e-6\|lorentz_determinant_tolerance::Float64" src/contracts/Contracts.jl`.

### LEAD U42-9 [Minor, confidence high] validation/lattice_cells.jl:219
Claim: the script cannot require its CUDA leg: with `OCTOPUS_REQUIRE_GPU_CONTRACT=1` and no device it exits 0, prints `cpu/cuda skipped` for every cell, and still closes with "all cells gated: ... and backend-consistent".
Mechanism: `validate(ElementTrackingBackendConsistencyContract)` returns `:skipped` from `_contract_backends_available` (Contracts.jl 922-930) without consulting `_require_gpu_contract()`; the gate at line 276 accepts `"skipped"`; the script never reads the variable itself and the closing message (278-279) is unconditional. The skip is visible in the table and the TSV but not assertable, the U25-10 shape the backend-consistency script closed for itself (its lines 318-319, 338, 382, 432-433). Hypothesis 2's "GPU leg forced on where CUDA is required" does not hold for this script.
Repro: `CUDA_VISIBLE_DEVICES="" OCTOPUS_REQUIRE_GPU_CONTRACT=1 OCTOPUS_LATTICE_LONG=50 OCTOPUS_LATTICE_N=256 OCTOPUS_LATTICE_TURNS=1 julia --project=. validation/lattice_cells.jl; echo $?` -> six `cpu/cuda skipped   max|Δ| = n/a` rows, the "backend-consistent" closing line, exit 0 (measured 32.1 s; `probes/U42/lattice_nogpu_require.log`).

### LEAD U42-10 [Minor, confidence high] validation/lattice_cells.jl:262
Claim: the one-turn symplecticity gate of 5e-7 sits 2.6e8x to 1.1e9x above the residuals the complex-step `one_turn_matrix` Jacobian actually produces (4.4e-16 to 1.9e-15), a finite-difference-era number left in place when the instrument became exact.
Mechanism: the header (15-16) says the residual comes from the helper's complex-step linearization, and measured residuals are at roundoff for all six cells; the threshold is the literal from the U21-3 gate, unexplained, next to a drift threshold the comment (255-259) defends as "from measurement, not taste". A composed cell whose map lost symplecticity at the 1e-8 level (an integrator or kick term that is no longer Hamiltonian in one element) passes this gate and relies on the 2000-turn drift (whose sensitivity floor is ~1e-3 for the sextupole cells). Class 8.
Repro: `julia --project=. validation/lattice_cells.jl | sed -n '/symplectic/,/^$/p'` -> residual column 1.33e-15, 1.22e-15, 4.44e-16, 4.44e-16, 1.89e-15, 1.67e-15 against `r[3] <= 5.0e-7`.

### LEAD U42-11 [Minor, confidence med] validation/twiss_dispersion_acceptance_windows.jl:567
Claim: section 3's "test c beside it" column is a set of hand-copied literals (1024, 2048, 64, 16, 64, 64, 64, 64, 64, 64, 64, 4, 4, 4096, 16, 1) with no tripwire to the suite's `c_route`, `c_agree`, `c_cubic`, `c_eta` and the `16 * eps()` / `64 * eps()` / `4 * eps()` bounds of the canonical-separation and coasting testsets.
Mechanism: the header says the fixture builders are "extracted from test/runtests.jl by NAME at run time (never copied by hand)", which is true of the builders; the `c` values that decide the table's "red > c" column are typed in (`fam!(..., 1024, ...)`, `fam!(..., 2048, ...)`, ...). I checked nine of the seventeen against the suite (runtests 4425 `c_route = 1024.0; c_agree = 2048.0; c_cubic = 64.0`, 5055 `c_eta = 4096.0`, 5181 `1024 * eps()`, 5470 `16 * eps()`, 5432-5700 `64 * eps()`, 4829 `4 * eps()`, 4911 the DBA FD tolerance, 5208-5232 `16 * eps()`): all agree today; a re-pinned suite `c` would leave the table judging against the old one and nothing would report it (class 2). The constants of section 2 are read from the source (`Octopus._GRAPH_SINGULARITY_MULTIPLIER` etc., 520-531) and are not part of this lead.
Repro: `grep -n 'fam!("' validation/twiss_dispersion_acceptance_windows.jl | grep -o ', [0-9]*,' | sort | uniq -c` against `grep -n "c_route = \|c_agree = \|c_cubic = \|c_eta = " test/runtests.jl`.

### LEAD U42-12 [Minor, confidence low] validation/twiss_dispersion_acceptance_windows.jl:329 (out of hypothesis; seam with src/analysis)
Claim: the c_inv labelling keys on `occursin("another branch", r.detail)`, a free-text coupling to the message built at `src/analysis/dispersion_routes.jl:853`, which the analysis itself also matches on (`src/analysis/twiss_dispersion_analysis.jl:1192`).
Mechanism: three sites agree on a phrase inside a human-readable `detail` string; rewording the message moves every other-branch graph from `unl!` to `rej!` in this driver (shrinking the c_inv window's rejected edge, currently 3.602 from a stalled iterate) and changes the analysis's own branch at 1192, with no test naming the phrase. Class 2/3 (independent walkers over one string).
Repro: `grep -rn "another branch" src/analysis/*.jl validation/twiss_dispersion_acceptance_windows.jl` -> 853, 1192, 329, 330.

### LEAD U42-13 [Minor, confidence low] validation/twiss_benchmark_cells.jl:352 (out of hypothesis)
Claim: `CONTRACT_DENSE_MAPS = 20` and `CONTRACT_DENSE_MAPS_4D = 5` copy the identity contract's struct defaults instead of reading `TwissDispersionIdentityContract().dense_maps` / `.dense_maps_4d`, and the 4x4 draws depend on the 6x6 count.
Mechanism: `dense_maps()` (364-377) draws the 6x6 maps first and the 4x4 maps after them from one `MersenneTwister(20260911)` "in the contract's own draw order", so a changed 6x6 default in the contract silently makes D8_1..3 different matrices here while the comment still says they "equal the suite's". Equal today (measured 20 / 5); class 2.
Repro: `grep -n "CONTRACT_DENSE_MAPS" validation/twiss_benchmark_cells.jl; julia --project=. -e 'using Octopus; c = TwissDispersionIdentityContract(); println(c.dense_maps, " ", c.dense_maps_4d)'` -> `20 5`.

### LEAD U42-14 [Minor, confidence low] validation/generate_madx_survey_reference.jl:124 (out of hypothesis)
Claim: if the MAD-X banner regex does not match, the generator writes `survey_madx_unknown.tsv`, which the contract's numeric-version sort ranks below every versioned file, so a regenerated reference is silently ignored by the contract; the write is also non-atomic.
Mechanism: `version = "unknown"` (124) is only replaced when `match(r"MAD-X (\d+\.\d+\.\d+)", log)` succeeds (140-141), the file name is built from it (149), and `_madx_survey_reference_path` (Contracts.jl 2726-2736) sorts by the integer runs of the file name, where `[]` (no digits) sorts first and `last(...)` keeps the old versioned table; the generator's `wrote ...unknown.tsv` is the only trace. The table is written with `open(ref, "w")` (150-156), not the partial-then-`mv` pattern of `write_reference_table` (twiss_benchmark_cells.jl 429-455) and the PTC generator, so an interrupted run leaves a truncated committed-path file. Class 6/7; low likelihood (the 5.03.06 banner matched here).
Repro: `julia -e 'natkey(f) = [something(tryparse(Int, m.match), 0) for m in eachmatch(r"\d+", f)]; println(last(sort(["survey_madx_unknown.tsv", "survey_madx_5.03.06.tsv"]; by=natkey)))'` -> `survey_madx_5.03.06.tsv`.

### LEAD U42-15 [Minor, confidence low] validation/twiss_dispersion_identities.jl:202 (out of hypothesis)
Claim: the `TW-DIAG` and `TW-KINDS` machine lines print `0` for any metric key the contract result lacks, so a contract that stopped writing `diagnostics_expected` or `kinds_declaring` would print `expected=0 silent=0` / `declaring=0 ...` and look green in the record these lines feed.
Mechanism: `get(m, :diagnostics_expected, 0)` and friends (202-209) default to zero; the file treats the same situation loudly elsewhere (`identity_slugs` errors on a missing identity key, `TW-PINS` prints `NA`), and the docstring justifies the defaults by the `IDENT_DRY_RUN` fake. The gate (277) is the contract's status, so the run's verdict is unaffected; the printed census is what the freezing-set record hand-reads (class 6, print-only).
Repro: in the suite's dry-run pattern (runtests 6302-6312) call `report_identities` on a fake whose metrics lack `:diagnostics_expected` and `:kinds_declaring` -> `TW-DIAG expected=0 silent=0 []` and `TW-KINDS declaring=0 ...` with no warning.

## Clean

- Hypothesis 1, symplecticity: the case list IS the contract's (`symplecticity_cases() = Octopus._symplecticity_contract_cases()`, line 93); the structural declaration-vs-case tripwire executes through `run_symplecticity_coverage` (metric `kinds_declaring_without_case` = 0 over the 22 `Symplectic6DMap` kinds, measured), and `validate(::SymplecticityContract)` derives the obligation from `meta.tracking_methods` and `meta.runtime_type` (Contracts.jl 1969-1977), not from `meta.contracts`. The probe point and the Lorentz angle/tolerances are read from the contract (`SYMPLECTICITY_PROBE_POINT`, `_SYMP_CONTRACT_DEFAULTS`). The suite's leg (runtests 29201-29215) no longer overrides `default_tolerance` (U24-6 closed; U24-3, U24-4, U24-5, U24-7 closed as well). 27 of 27 cases pass with the residuals listed under Provenance; the "27" in the script header and the contract docstring is correct today.
- Hypothesis 2, backend consistency: `meta.contracts` is `Vector{DataType}`, so the coverage tripwire's `C === ElementTrackingBackendConsistencyContract` is live (30 declaring kinds, all present across the two lines; `:line` is the only registered kind that does not declare); the wrap tripwire derives its set from `parameter_schema` (`thin_crab_cavity`, `thin_rf_cavity`, both wrapped in the line). The require path errors at four sites (318-319, 338, 382, 432-433) and the auto path ran the GPU leg on this machine. `_cross_backend_rounding(::AbstractTrackOp)` throws (no silent default); the wrappers delegate (`TurnModulated` through `_rounding_through`, `MisalignedElement`/`RefTilted` through `_rounding_written_over`, `CompositeLine` through the tuple composition). `_contract_rep_for_backend` copies on both backends, so the per-kind CPU/CPU pair compares two tracked copies, not one object. `_cross_backend_agreement` counts NaN/NaN as agreement (`===`) and `compared`, and `_cross_backend_violations` refuses an empty comparison, so the killing-aperture case (6725 of 10000 killed, 3275 survivors compared) is a real check. The measured per-kind table is within every declared bound with the margins listed under Provenance; the composed-line CPU/GPU agreement is 9.7e-17 absolute.
- Hypothesis 3, acceptance windows: the windows are produced by one stated rule (`window_lines`, 485-516: 10x the worst accepted ratio to 1/10 of the best rejected, direction by constant type) over labelled fixtures whose names the code builds; the source constants are read at run time (520-531), not copied. Measured on 24e8683: every constant inside its window except `c_inv` (EMPTY, accepted extreme 5.341, rejected extreme 3.602) -- exactly the README's statement, including its two edge figures; section 3 17/17 families green below c and red above it; the oracle table 34/39 by the default longitudinal rule and 39/39 with the certified index, as the design narrative says. The fixture builders are extracted from `test/runtests.jl` by name and fail loudly when missing (`definition_lines`, 30-36). The driver is a measurement, not a gate, by its own line 14 and the README; it writes only its output file.
- `lattice_cells.jl`: all four declared metrics are gated (U24-2 closed), the three NaN paths of `invariant_drift` are caught by `isfinite` (269), the `+sext` variants are re-tested for stability (263-268); the drifts measured today equal the 2026-08-05 figures the threshold comment quotes; the working points the scan picks (FODO 1.60, DBA 1.50/-1.10, TBA 0.90/-1.00) match the numbers the suite and `twiss_benchmark_cells.jl` copy; CPU/CUDA parity 5.2e-18 against atol 1e-10. The drift instrument's sensitivity: a uniform per-turn dissipation delta gives ~4000 delta over 2000 turns, so the 5e-3 cap sees delta > 1.3e-6 while the one-turn gate (even at 5e-7) sees delta > 2.5e-7 -- the two instruments overlap, the drift catching only position- or amplitude-dependent defects.
- `generate_madx_survey_reference.jl`: the regenerated table is byte-identical to the committed one (MAD-X 5.03.06 on this machine); the nine deck cases are the nine contract fixtures and the contract's `untested = setdiff(keys(lines), keys(table))` check (Contracts.jl 2765-2768) makes the "twinning by eye" count-checked; `set, format = "22.16e"` keeps full precision; `$START`/`$END` rows are dropped; the rbend chord fold (2.020986251) is pinned by the `rbend_chord` case at deviation 0.
- `twiss_benchmark_cells.jl`: both beam pins hold at construction (asserted); `convert_map` implements the stated law `Sh(u) J0 F M F^-1 J0^-1` with the correct branch per code and target; `write_reference_table` is atomic; the 31 bend-free rows of the maps table reproduce bitwise; the contract defaults it copies are equal today.
- `twiss_dispersion_identities.jl`: slugs come from `Octopus._IDENTITY_CONTRACT_SLUGS`, the multipliers from the contract instance, a missing identity key errors by name (126-134), the gate is the contract's status (277) and it fired (U42-2); the census of the run: 57 identities, 17 of 17 expected diagnostics fired, 23 declaring kinds (18 analyzed, 5 refused), 249 consistent verdicts, 0 inconsistent.
- The REQUIRE and auto semantics of `tracking_backend_consistency.jl` are as the README documents them (an explicit `OCTOPUS_RUN_GPU_CONTRACT=1` without REQUIRE skips visibly); the single-pass and aperture arms refuse to go vacuous (343-344, 393-399). Style only: the `rpad(label, 36)` at 457/460 is one character short for `thin_accelerating_cavity (single pass)`, so that row's columns run together.

## Unchecked

- The Haswell arm (`OPENBLAS_CORETYPE=Haswell julia -C haswell`) of the identities and acceptance-windows drivers was not run; the history records it exit 0 for the identities script. Only the native arm's digest (0x5c85f01a66ae5777) is reported.
- The suite testsets that mirror this region ("Cross-backend rounding classes ...", "Lattice cells track and stay symplectic", "Physics contracts", the identities dry run, the stage 6 contract testset) were not run through the stage runner; the scripts themselves were run instead.
- The consumers of `twiss_benchmark_cells.jl` (`twiss_madx_benchmark.jl`, `twiss_ptc_benchmark.jl`, `twiss_xsuite_benchmark.jl`, the generators) are outside the region; whether U42-3's roundoff drift is within their tolerances was not measured (it is 1e-15-level on O(1) entries).
- The CUDA correctness of the declared classes beyond the script's own measurement (the kernels, the `MisalignedElement` and `TurnModulated` wrappers) was not read; `_rounding_written_over`'s `written` sets per wrapper were not checked against the kernels.
- Seam not pursued: `:line` (`BeamLine`) is the one registered kind that declares no backend-consistency contract, so no script in this region tracks a `BeamLine` on CUDA; whether the suite does was not checked.
- The twelve kappa derivations behind the acceptance windows and the identity contract's `_default_identity_multipliers` are in `src/analysis` / `src/contracts/twiss_dispersion_identity.jl`, outside the region; the windows were checked as produced, not re-derived.
- `bench_cells_probe.jl` has a soft-scope bug in its last block (it prints the header/data verdicts, then errors); the row-level comparison in this report comes from the shell diff of the same two files, kept beside it.
