# U40: validation: crab-cavity noise, turn-modulation spectra, counter RNG, diagnostics benchmark

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Unit brief:
`result/comprehensive_audit_2026_10_18/plan/U40.md`. Every claim below is a LEAD, not a finding.

## Region

| file | lines | read |
|---|---|---|
| `validation/crab_cavity_noise_response.jl` | 1-2388 | line by line |
| `validation/turn_modulation_spectra.jl` | 1-225 | line by line |
| `validation/counter_rng_validation.jl` | 1-170 | line by line |
| `validation/strong_strong_diagnostics_benchmark.jl` | 1-165 | line by line |

2948 lines, all read. References read for the comparison the brief asks for:
`docs/theory/crab_cavity_noise_response.md` 1-784 (whole),
`docs/history/crab_cavity_noise_validation_2026_10_14.md` 1-560 (whole),
`validation/README.md` 186-245, 365-600, 786-820 (the four scripts' sections).
Cross-file reads kept to the seams the scripts name (grep and short excerpts, not audited):
`test/examples/crab_cavity_noise.jl` (the CRAB-NOISE line, lines 680-695, 795-830, 995-1050, the
table-file reader's labels), `src/elements/turn_modulated.jl` (156, 167, 1080-1115),
`src/math/counter_rng.jl` 665-690, `src/tasks/strongstrong/interface.jl` 85-100 and 1725-1810,
`src/tasks/strongstrong/gaussian_pic.jl` 150-175, `src/policies/Policies.jl` 332-370,
`test/examples/strong_strong_tracking.jl` (400, 638-700, 848, 1063-1095), `test/runtests.jl`
12272-12400 (the spectra twin), `.gitignore`, `result/crab_noise/S0B/RUNLOG.txt` and the
`SOURCE.txt` of the merged sweep TSV.

## Provenance

READ (above). EXECUTED, all from the scratch directory
`result/comprehensive_audit_2026_10_18/probes/U40/` with `out=` or a script copy keeping every
write inside it (verified: no `result/turn_modulation_spectra.tsv` appeared; `probes/result` does
not exist); each log is in that directory:

| probe | command (driver file) | result |
|---|---|---|
| `arith.log` | `probe_arith.jl` (no package) | header constants recomputed, see Clean |
| `noise.log` | part `noise` at its defaults, `out=probes/U40/noise_out` (`drive_noise.jl`) | `CRAB-NOISE-RULES turns=65536 checks=273 failed=0 verdict=PASS`, wall 126.6 s after the load |
| `report.log` | part `report` on `result/crab_noise/S0B/sweep_rel_plus_phase_2026_10_14.tsv` (`drive_report.jl`) | `CRAB-NOISE-REPORT checks=60 failed=0 verdict=PASS`, 23.4 s; every printed number equals the 2026-10-15 RUNLOG's and the records' |
| `control.log` | part `control` on the same TSV with `out=` naming a directory that does not exist (`drive_control.jl`) | `PASS C1 centroid ... 3.12e-05`, then `SystemError: opening file .../control_C1_centroid.tsv`, exit 1, no `CRAB-NOISE-CONTROL` line (LEAD U40-1) |
| `control2.log` | the same with the directory pre-created | `CRAB-NOISE-CONTROL ... deviation=3.116e-5 correlation=0.99999999958 verdict=PASS`; `CRAB-NOISE-CONTROL-COVARIANCE checks=3 failed=0 verdict=PASS` (C2 x ratio 1.0057, y difference 3.16e-15 of the x slope), 20.8 s |
| `report_typo.log`, `report_tolratio.log` | `report ... tol_ration=0.01` and `report ... tol_ratio=0.01` (`drive_report_args.jl`) | misspelled key: `checks=60 failed=0 PASS`, exit 0, no warning; real key: `checks=60 failed=1 FAIL`, exit 1 (LEAD U40-2) |
| `tablefile_bogus.log` | `tablefile bogus_key=1 turnz=8 turns=16 path=... out=...` | runs to `CRAB-NOISE-TABLEFILE`, exit 0; unconsumed keys `bogus_key`, `turnz` never mentioned (LEAD U40-2) |
| `report_default_cases.log` | `report` on the merged TSV filtered to the 14 default `cases=` (A05, A2, A4s, C3 removed) | `NOTE amplitude white A05, A1, A2 ...: fewer than two resolved points`; `checks=49 failed=0 verdict=PASS` (LEAD U40-12) |
| `spectra.log` | `turn_modulation_spectra.jl` from a scratch copy, defaults (`drive_spectra.jl`) | `TM-SPECTRA white_slope=0.9839 pink_slope=0.0102 white_rms=0.9966 pink_rms=0.9054 stateless=true turns=65536 seed=42 verdict=PASS`, 4.6 s |
| `rng.log` | `counter_rng_validation.jl`, defaults, no CSV (`drive_rng.jl`) | KAT true; passed; tails 45145/2619/56 against 45500/2700/63 (z = -1.7, -1.6, -0.9), 1.3 s |
| `pink_mc.log` | `probe_pink_mc.jl`: 8192 synthetic Voss-McCartney streams | sd(rms/sigma) 0.1344 at N = 16384 (formula 0.1531, min(2^k, N) form 0.1466), 0.0738 at 65536 (formula 0.0765); fraction outside [0.8, 1.25]: 5.9 % and 0.46 % (LEAD U40-8) |
| `gaussian_families.log` | `probe_gaussian_families.jl` | `configuration_report(GaussianPoissonSolver(); policy=CUDAExecutionPolicy(), backend=CUDABackend)`: 15 entries, all seven `cuda_pic_<family>_threads` missing; PIC: 36 entries, none missing (LEAD U40-3) |

Not executed: parts `pilot` and `sweep` (GPU subprocess runs of hours), `strong_strong_diagnostics_benchmark.jl` (production GPU workload that writes under the repository's `result/` and `test/result/`), the suite's spectra twin.

## Leads

### LEAD U40-1 [Moderate, confidence high] validation/crab_cavity_noise_response.jl:2247
Claim: Part `control` never creates its output directory, so `out=<a directory that does not exist yet>` crashes it after the centroid verdict and before the covariance verdicts and both machine-readable lines.
Mechanism: `run_noise_part`, `run_tablefile_part`, `run_pilot_part` and `run_sweep_part` call `mkpath(OUT_DIR)` (lines 705, 1565, 1583, 1650); `run_control_part` (2118) does not, and writes `control_<case>_centroid.tsv` through `open(out_path, "w")` at 2247-2248, which throws `SystemError` when the directory is absent. The covariance test (acceptance 7), its `CRAB-NOISE-CONTROL-COVARIANCE` line and even the centroid test's own `CRAB-NOISE-CONTROL` line are never reached; the exit is an uncaught exception, not a counted FAIL. The header says `out` applies to "every part"; the part only ever worked because `sweep` had created the default directory first.
Repro: `julia --project=. validation/crab_cavity_noise_response.jl control tsv=result/crab_noise/S0B/sweep_rel_plus_phase_2026_10_14.tsv out=/tmp/u40_absent_dir` prints `PASS C1 centroid ... rms deviation 3.12e-05` and then `ERROR: LoadError: SystemError: opening file ".../control_C1_centroid.tsv"` (exit 1, no `CRAB-NOISE-CONTROL` line); after `mkdir -p /tmp/u40_absent_dir` the same command ends `CRAB-NOISE-CONTROL-COVARIANCE checks=3 failed=0 verdict=PASS` (probes/U40/control.log, control2.log).

### LEAD U40-2 [Moderate, confidence high] validation/crab_cavity_noise_response.jl:450
Claim: Every part accepts any `key=value` override without checking that the key is consumed, so a misspelled tolerance or reference silently keeps its default and the verdict is taken on a number the operator did not set.
Mechanism: `OPTS` is a `Dict` filled from `ARGS[2:end]` (450-455) and `opt`/`opt_int`/`opt_float` are `get(OPTS, key, default)`; no part compares `keys(OPTS)` with the keys it read and nothing is printed for a leftover key (defect class 5; "a silently ignored non-default request is a defect"). The report's 15 reference and tolerance keys are exactly the ones an operator retypes by hand.
Repro: `julia --project=. validation/crab_cavity_noise_response.jl report tsv=result/crab_noise/S0B/sweep_rel_plus_phase_2026_10_14.tsv tol_ration=0.01` ends `CRAB-NOISE-REPORT checks=60 failed=0 verdict=PASS` (exit 0, the key never mentioned); the same with `tol_ratio=0.01` ends `checks=60 failed=1 verdict=FAIL` (P1/W1 at 0.935 of rho_bar). `... tablefile bogus_key=1 turnz=8 turns=16 path=/tmp/t.tsv out=/tmp` runs to `CRAB-NOISE-TABLEFILE` with exit 0 (probes/U40/report_typo.log, report_tolratio.log, tablefile_bogus.log).

### LEAD U40-3 [Moderate, confidence high] validation/strong_strong_diagnostics_benchmark.jl:147
Claim: The documented `OCTOPUS_SOLVER=gaussian` mode cannot finish on the GPU: after the whole measured run the launch-family loop errors because the Gaussian solver's `configuration_report` carries no `cuda_pic_<family>_threads` entries, and the summary TSV is never written.
Mechanism: lines 137-157 run for any `CUDAExecutionPolicy` (the default `OCTOPUS_USE_GPU=1`) and demand one `cuda_pic_<family>_threads` entry per member of `Octopus._CUDA_PIC_LAUNCH_FAMILIES` from `configuration_report(solver; policy, backend=CUDABackend)`, calling `error(...)` otherwise. Only the PIC report (`src/tasks/strongstrong/interface.jl:1730`, its `selected_backend === CUDABackend` block) and the GaussianPIC report that forwards it emit those entries; the `GaussianPoissonSolver` method (interface.jl:1775) does not. The U25-6 fix ("derive the family list and refuse to skip one") assumed a PIC solver and so reinstated the pattern U25-5 and U25-15 were fixed for: a crash after the workload is paid for. The header (line 19) and `validation/README.md:801` advertise the mode; `docs/history/strong_strong_diagnostics_benchmark_history.md` has no gaussian row.
Repro: `julia --project=. -e 'using Octopus; e = configuration_report(GaussianPoissonSolver(); policy=CUDAExecutionPolicy(), backend=CUDABackend); println(count(x -> startswith(string(x.name), "cuda_pic_"), e), " of ", length(e))'` prints `0 of 15` (the PIC solver: 7 of 36), so `OCTOPUS_SOLVER=gaussian OCTOPUS_USE_GPU=1 julia --project=. validation/strong_strong_diagnostics_benchmark.jl` must end in `CUDA PIC launch family gather_scatter is in Octopus._CUDA_PIC_LAUNCH_FAMILIES but configuration_report did not report cuda_pic_gather_scatter_threads` after the 200 turns (probes/U40/gaussian_families.log; the full run itself was not executed).

### LEAD U40-4 [Moderate, confidence high] validation/README.md:558
Claim: The README's description of part `report` (and parts of its `noise` and `sweep` paragraphs) states verdicts and defaults the script no longer has.
Mechanism: lines 558-567 say the "W1, W2, W3, A1 (x and y), A4, T2 and AT1 rates" are judged within a factor 1.25 with defaults "1.10e-6 and 9.5e-7 for amplitude white in x and y", "P1/W1 and AP1/A1 within 25 % of the pink ratios 0.15 (x) and 0.17 (y)" and "no vertical growth under phase noise" as a verdict. The script makes A1's y, AP1/A1's y and the colliding runs' vertical rates INFO (items 1b, 3, 5), judges the plane mapping on C1 and C2 only, lists A4 as INFO at the regime's edge, and refuses `ref_amp_white_y` outright ("retired 2026-10-15"), so a reader who passes the README's 9.5e-7 gets an error. Line 548's sweep list ("B0, W1-W3, P1, T1, T2, A1, A4, AP1, AT1, C0, C1, C2 and the optional C3") omits A05, A2 and A4s, which items (1) and (2) read; line 488 describes the pink rms item as "within ... 23 %" at N while the verdict is the 2^20-turn 99 % Monte Carlo band and the N-turn value is INFO. Defect class 14 (documentation as claims); the README is the user-facing statement of what this validation verifies.
Repro: `julia --project=. validation/crab_cavity_noise_response.jl report tsv=result/crab_noise/S0B/sweep_rel_plus_phase_2026_10_14.tsv ref_amp_white_y=9.5e-7` → `ERROR: ref_amp_white_y is retired (2026-10-15)`; `grep -n "A1 (x and y)\|9.5e-7 for amplitude\|0.17 (y); T1\|so 23 %" validation/README.md` → 558, 561, 564, 488 present at 24e8683.

### LEAD U40-5 [Minor, confidence med] validation/strong_strong_diagnostics_benchmark.jl:126
Claim: With `OCTOPUS_TURNS` pre-set in the environment, the summary's `turns` row and the printed sample window report the script's own `OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS`, not the turn count the harness tracked.
Mechanism: `turns` (line 41) feeds `OCTOPUS_TURNS` only when that variable is unset (72-74); the U25-5 guard (84-91) reads the effective value but only to prevent the BoundsError; line 114 prints `turns - sample_turns : turns - 1` and line 126 records `"turns" => turns`, while `sample = timings[(end - sample_turns + 1):end]` (102) is the last window of the EFFECTIVE run. The summary's provenance then names a configuration the run did not use (class 11).
Repro: `OCTOPUS_TURNS=300 OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS=200 julia --project=. validation/strong_strong_diagnostics_benchmark.jl` (any particle counts) → summary row `turns	200` and `sample_turns = 100:199` while the harness ran 300 turns and the sampled window is turns 200-299. Read-derived, not executed (GPU production size; writes under the repository's `result/` and `test/result/`).

### LEAD U40-6 [Minor, confidence high] validation/counter_rng_validation.jl:132
Claim: The uniform-variance tolerance is derived with the normal-distribution relation and is 1.58 times too loose, so the "6 sigma" gate on the uniform variance is a 9.5-sigma gate.
Mechanism: the sd of a sample variance is `sqrt((mu4 - sigma^4)/N)`; for U(0,1), mu4 = 1/80 and sigma^2 = 1/12 give 0.0745/sqrt(N); the script's `6 * (1/12) * sqrt(2/N)` (0.1179/sqrt(N) per sigma) is the normal-case `sqrt(2/N)` scaled by the variance, which the comment "scaled by the uniform variance" presents as the derivation. No false fail follows; the tolerance is not what its comment says it is (class 8).
Repro: `julia -e 'N=1e6; println(sqrt((1/80 - 1/144)/N), " ", (1/12)*sqrt(2/N))'` → `7.454e-5 1.179e-4`; Monte Carlo sd of `var(rand(1_000_000))` over 200 draws 6.87e-5 (probes/U40/arith.log).

### LEAD U40-7 [Minor, confidence high] validation/counter_rng_validation.jl:109
Claim: The three tail fractions are printed with "expected about" but never enter `ok`, although the header (lines 31-32) counts "the tail fractions" among the moment checks.
Mechanism: lines 84-86 compute `tail2`, `tail3`, `tail4`; 107-109 print them; 135-141 gate the means, variances, correlations and the three boolean checks only. A generator with clipped or inflated tails (a truncated inverse CDF, a Box-Muller with a bad logarithm) passes this script (unit hypothesis 1: print-only threshold).
Repro: `julia --project=. validation/counter_rng_validation.jl | grep "P(|N|"` → three lines ending in "expected about ...", no PASS/FAIL; measured at N = 1e6: 45145, 2619, 56 against 45500, 2700, 63 (binomial sd 208, 52, 8; z = -1.7, -1.6, -0.9), so a 6-sigma gate would pass today (probes/U40/rng.log).

### LEAD U40-8 [Minor, confidence high] validation/turn_modulation_spectra.jl:48
Claim: The header's "13.8 % at 16384" is not the value of the formula it attributes it to, and that formula is quoted outside its validity (it needs 2^(K-1) <= N).
Mechanism: `Var[rms^2] = (2/(K^2 N)) sum_k 2^k (2K - 1 - 2k)` counts N/2^k independent values per generator; at N = 16384 generator 15 (2^15 > N) holds one value, so its diagonal term is 2/K^2, half of what the formula charges. The formula gives 15.3 % for the one-sigma of the rms at 16384, the corrected form (min(2^k, N)) 14.7 %, and the Monte Carlo 13.4 % (the rms distribution is skewed, so half the sd of rms^2 overstates it); 13.8 % matches none of the three. The suite's testset comment repeats the sentence ("13.8 %, Monte Carlo 13.4 %"). No verdict reads the number; at 65536 the formula (7.65 %) and the Monte Carlo (7.4 %) agree, as the header's 7.6 % says.
Repro: `julia result/comprehensive_audit_2026_10_18/probes/U40/probe_pink_mc.jl` → `N = 16384: MC sd(rms/sigma) = 0.1344 ... formula 0.1531; formula with min(2^k, N) 0.1466`; `N = 65536: MC 0.0738, formula 0.0765` (probes/U40/pink_mc.log).

### LEAD U40-9 [Minor, confidence high] validation/turn_modulation_spectra.jl:82
Claim: The header says the suite twin runs "16384 turns, same rules, seed and tolerances" while the same header (51-52), the README (447-452) and the testset itself give the twin its own pink rms bound [0.75, 1.6] instead of the script's [0.8, 1.25].
Mechanism: two sentences of one header disagree on which tolerances are shared; only the slope tolerances are.
Repro: `grep -n "same rules, seed and tolerances\|own quantile bound" validation/turn_modulation_spectra.jl` → 82 and 52; `grep -n "0.75 <= sp_rms" test/runtests.jl` → the twin's bound.

### LEAD U40-10 [Minor, confidence high] validation/crab_cavity_noise_response.jl:1160
Claim: The script says the campaign plan is "committed with the record" (`result/crab_noise/D1/plan.md`), but `result/` is git-ignored and no `plan.md` exists under `docs/`.
Mechanism: `.gitignore` line 16 ignores `result/`; the theory note (591-592) likewise defers to "the detailed plan ... kept with the campaign record (`plan.md`)", and the committed record `docs/history/crab_cavity_noise_validation_2026_10_14.md` contains no plan file. The document a reader is pointed to for the sweep's design is not in the repository (invariant: commit what a future session needs; class 14).
Repro: `find docs -name plan.md | wc -l` → 0; `grep -n "^result/" .gitignore` → 16; `ls result/crab_noise/D1/plan.md` exists only on this machine.

### LEAD U40-11 [Minor, confidence high] docs/theory/crab_cavity_noise_response.md:667
Claim: The theory note's section 7 acceptance list and sweep table differ from what the script enforces: item 2 names "(and A1, A4)" for the amplitude exponent while the script fits A05, A1, A2 (cases the note's table does not list), and item 6's "J_raw - eps_c = J_c turn by turn" is only printed (`identity_max`, INFO), never judged.
Mechanism: the script evolved (A4 at 39 % growth became INFO, A05 and A2 were added, the identity holds only to first order in J_c/eps_c) and the frozen history records explain why, but the note is the live reference and still states the old plan (unit hypotheses 1 and 2; class 14).
Repro: `grep -n "(and A1, A4)\|turn by turn" docs/theory/crab_cavity_noise_response.md` → 667 and item 6; `grep -c "A05" docs/theory/crab_cavity_noise_response.md` → 0; `grep -n "identity max" validation/crab_cavity_noise_response.jl` → one INFO printf (2031), no `verdict!`.

### LEAD U40-12 [Minor, confidence high] validation/crab_cavity_noise_response.jl:1201
Claim: The default `cases=` order omits A05, A2 and A4s, so a default sweep cannot yield acceptance item 2 for amplitude noise or the A05 and A2 rate items; `report` then prints NOTEs, counts 49 checks instead of 60 and still ends PASS.
Mechanism: `SWEEP_DEFAULT_ORDER` lists 14 cases; `exponent(["A05", "A1", "A2"], ...)` (1902-1905) needs two resolved points and otherwise `note(...)`s and returns without counting; `within_factor` for A05 and A2 does the same. The NOTE lines are visible, but the header's acceptance (2) names the amplitude exponent as a verdict that the default run cannot deliver ("an unrun check is not a pass").
Repro: `awk -F'\t' 'NR==1 || ($1!="A05" && $1!="A2" && $1!="A4s" && $1!="C3")' result/crab_noise/S0B/sweep_rel_plus_phase_2026_10_14.tsv > /tmp/default.tsv; julia --project=. validation/crab_cavity_noise_response.jl report tsv=/tmp/default.tsv` → `NOTE  amplitude white A05, A1, A2 (small-growth set): fewer than two resolved points` and `CRAB-NOISE-REPORT checks=49 failed=0 verdict=PASS` against `checks=60` on the full TSV (probes/U40/report_default_cases.log).

### LEAD U40-13 [Minor, confidence high] validation/crab_cavity_noise_response.jl:1848
Claim: Report labels hard-code turn counts ("A2 amplitude white x (s = 2, 25000 turns)"; `(("A4s", 12500), ("A4", 25000))` at 1849) although every row carries `turns`, so a `turns_a4=` or `turns_a4s=` override mislabels the lines.
Mechanism: hand-copied constants beside the derived quantity (class 2); the INFO loop's `T` is used only in the label while the growth percentage is computed from the row's `t_first`/`t_last`.
Repro: `grep -n "25000 turns\|(\"A4s\", 12500)" validation/crab_cavity_noise_response.jl` → 1848, 1849; a sweep run with `turns_a4=20000` still reports "25000 turns" in its A2 and A4 lines.

### LEAD U40-14 [Minor, confidence high] validation/crab_cavity_noise_response.jl:853
Claim: `noise_pink_bands.tsv` flags the top octave as `trusted = true` and writes `z = NaN` for it, while the verdict excludes that band (the normaliser) from its chi-square.
Mechanism: the TSV's `trusted` column is `i >= first_trusted` (853) but the verdict sums `z[first_trusted:end-1]` (855); the top band's reference sd is 0 by construction, so its z is 0/0. Two descriptions of one band set disagree in a deliverable (class 3, cosmetic).
Repro: `julia --project=. validation/crab_cavity_noise_response.jl noise out=/tmp/u40_noise; grep -c NaN /tmp/u40_noise/noise_pink_bands.tsv` → 8 (one per pink slot), each row `band 14 ... NaN true` (probes/U40/noise_out/noise_pink_bands.tsv).

### LEAD U40-15 [Minor, confidence med] validation/strong_strong_diagnostics_benchmark.jl:123
Claim: The summary's `git_commit` is `git rev-parse HEAD` in the caller's working directory, so a launch from outside the project root either crashes after the measured run or records another repository's commit.
Mechanism: the command is not anchored to the script's tree (`git -C $(dirname @__DIR__)`); the header's "Run from the project root" is the only guard, and the failure, when it comes, comes after the 200 turns (classes 6 and 11).
Repro: `cd /tmp && julia --project=/cfs/ad/dxu/Library/Julia/Octopus /cfs/ad/dxu/Library/Julia/Octopus/validation/strong_strong_diagnostics_benchmark.jl` → after the run, `fatal: not a git repository` and a `ProcessFailedException` at line 123 (read-derived, not executed).

## Clean

Sound, with the evidence:

- Hypothesis 1 (enforced vs print-only). In all three judging parts every `verdict!` increments `failed` and the part ends `exit(1)` on `failed > 0` (noise 1154, report 2076, control 2373); the INFO items are exactly the ones the header declares INFO (pink N-turn rms; 1b; AP1/A1 y; A4/A4s; the pink runs' two-half and residual items; amplitude y fit quality; C2's first-moment x; C3). Measured: `tol_ratio=0.01` turned P1/W1 into a counted FAIL with exit 1. `ref_y_over_x_phase` is explicit (`nothing` unless supplied; the report prints "(no ref_y_over_x_phase supplied)") and enters INFO lines only, as the header says. The report is reproducible: `checks=60 failed=0` on the merged TSV with every printed number equal to the 2026-10-15 RUNLOG's and the records' (W1 1.026, W2 1.035, W3 1.024, A1 0.936, A05 0.909, A2 0.950, T2 1.022, AT1 0.987; exponents 1.996 and 2.038; P1/W1 0.935, AP1/A1 1.000; T1 == W1 bitwise; C1 eps_c 0.0078 of the prediction, y 2.7e-14; C2 y 9.7e-16; centroid actions 5.3e-11 and 2.5e-31); the RUNLOG's (8b) NaN defect is fixed on this tree (A1 1.138, AP1 1.099). Part `noise` reproduces `checks=273 failed=0` in 126.6 s (header: "about two and a half minutes"), with the recorded pink long-window values 1.013, 0.979, 0.995, 1.030, 1.007, 0.959, 1.024, 0.979, the 1.3425 slot (p < 0.0005) and the independence worst |rho|/se 1.98, 1.91, 2.39; the spectral cases K = 66 and 32765 with periodogram errors at 1e-14 to 1e-16 and out-of-band power at 1e-32 of the peak. Part `control` reproduces the centroid deviation 3.12e-5 (correlation 0.99999999958; shifted alignment 1.3132) and the covariance ratio 1.0057 (x) with y bit-identical to C0.
- Hypothesis 2 (theory vs script). Reference defaults equal section 6 (1.72e-7, 1.10e-6, 0.15, 0.17); scaling is s^2 (4x, 16x, 0.25x); tol_rate 1.25 is stricter than the note's factor 1.3; the pink acceptance band [0.75, 1.25] rho_bar = [0.1125, 0.1875] matches the note's "[0.11, 0.19]"; `beam_beam_xi` reproduces 0.01166/0.01173 and the band 0.35 xi; the centroid kick `-s_i[<cos> sin(dphi) + <sin>(cos(dphi) - 1)]/(ik)` is the exact bunch average of `sin(ikz + dphi) - sin(ikz)`; the covariance linearisation's c_i = <cos(ikz)> is the regression coefficient of `sin(ikz)/(ik)` on z for Gaussian z (unexplained variance printed 0.06 % and 1.00 %); the relative strength semantics are the note's 3.2: sigma handed over directly, `strengthX == S (1 + d)` and `strengthY === 0.0` asserted bitwise on every turn at scales 1 and 10, the recovered factor within 0.97 ulp(1); `realised_band_ratio`'s weights `S_X,i^2 c_i^2 sigma_z^2` agree with the note's `<sin^2(ikz)>/(ik)^2` to 0.15 % (i = 1) and 1.0 % (i = 2), INFO only. The linear maps in `control` match the harness's `Linear6DSpec` constructions (crab beta_y 100 m, dmu (pi/2, 0, 0), tunes (0.228, 0.210, -0.01), zero alpha, coupling and dispersion; harness 999-1050).
- Hypothesis 3 (headers run as written). The header's `noise`, `tablefile`, `report` and `control` commands and the README's copies ran with their documented keys; every key named in the header is read by `opt*` with the documented default (checked key by key for all six parts); `turn_modulation_spectra.jl` and `counter_rng_validation.jl` ran at their defaults with the documented environment knobs; the spectra numbers equal the README's (0.9839, 0.0102, 0.9966, 0.9054).
- Header constants recomputed from their formulas (probes/U40/arith.log): pink rms one-sigma 7.65 % (65536) and 1.91 % (2^20), sigma_mean 0.25 sigma, Wilson-Hilferty 31.4 for 11 bands (exact 31.26), white rms tolerance 0.83 %, M = 131070 distinct pink draws with 3 sqrt(2/M) = 1.17 %, E[s^2] 0.9375 and 0.8126 (std 0.9014), band bins 66 and 32765.
- Seams checked by grep: `_RULE_COMPONENT_BASE = 1024`, `_PINK_COMPONENT_STRIDE = 64` and the white/pink `_turn_offset` keying as the header states (turn_modulated.jl 156, 167, 1085-1108); `counter_normal(seed, turn, rng_id, particle_index, component, T)` as called; the harness receipt prints `chrom=<x>,<y>` as floats, `kbb_scale=<float>`, `device=`, which `verify_receipt` and `baseline_for` parse; table-file column labels `<cavity>_phase_noise_<i>` match the harness reader; `assert_harness_exports`/`HARNESS_EXPORTS`, `turn_timings`, `_CUDA_PIC_LAUNCH_FAMILIES`, `CUDALaunchConfig.threads/.blocks` exist; the benchmark's effective-turn guard (U25-5) is present and the family loop is correct for the PIC solver (7 of 36 entries).
- Statistics in `noise`: Bartlett's se reproduces 1/sqrt(N) for white pairs (0.0039) and 0.058 for pink; the pink p-value is two-sided over 2048 streams; the chi-square shape test excludes the two untrusted bands and the normaliser; the Rayleigh anti-vacuity pin (variance >= 0.1) measured 0.62 to 1.8.
- Style only (no lead): two report labels exceed `rpad(50)` so the value abuts the label ("judges (1b)y J_raw rate"); `case_row`'s re-read path records `load_at_launch = NA` although the log's first line holds the value (1529); `bartlett_se` takes a square root that could go negative for strongly anticorrelated pairs (unreachable here); the exponent's printed `+- 0.000` is the formal weighted-fit error with the residual-based se, a lower bound as the header says.

## Unchecked

- Parts `pilot` and `sweep` were not executed (GPU subprocess runs of 1.5 to 6 hours); their receipt verification (`verify_receipt`, `verify_table_digests`, the resumption rules) was read, not exercised, beyond the recorded S0B/I2 runs whose TSVs and artifacts the `report`/`control` probes consumed.
- `strong_strong_diagnostics_benchmark.jl` was not executed (production-size GPU workload; writes under the repository's `result/` and `test/result/`): LEADs U40-3, U40-5 and U40-15 rest on reading plus the `configuration_report` probe.
- The `noise` part's `turns=`, `table_turns=`, `long_turns=`, `rms_streams=`, `scale_check=` overrides and the `K < 8` Rayleigh FAIL branch were not exercised (defaults only).
- The suite's spectra twin ("Turn modulation: white and pink spectra") was not run; its tolerances were compared by reading only.
- The harness `test/examples/crab_cavity_noise.jl`, `src/elements/turn_modulated.jl` and the strong-strong harness are outside the region; only the lines the scripts depend on were read.
