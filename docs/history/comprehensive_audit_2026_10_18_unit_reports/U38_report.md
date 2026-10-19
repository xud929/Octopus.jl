# U38: test/examples/ + examples/

Reading unit of the comprehensive audit protocol (`docs/comprehensive_audit.md`), tree
`/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Hypotheses briefed:
(1) harness <-> example identity, every `OCTOPUS_*` toggle effective (assert what the run
recorded), the catalogue entry matches the script; (2) examples as documentation: stale API
usage, parameters that silently fall back, printed claims with no check behind them.
Every claim below is a LEAD, not a finding. Julia 1.12, one RTX 4500 Ada (every probe ran on
CPU threads; no probe needed the device).

## Region

| File | Lines | Depth |
|---|---|---|
| `test/examples/crab_cavity_noise.jl` | 1554 | every line |
| `test/examples/strong_strong_tracking.jl` | 1094 | every line |
| `test/examples/weak_strong_tracking.jl` | 551 | every line |
| `examples/crab_cavity_noise.jl` | 873 | every line |
| `examples/weak_strong_tracking.jl` | 392 | every line |
| `examples/strong_strong_tracking.jl` | 362 | every line |
| `examples/knob_control.jl` | 200 | every line |
| `examples/twiss_dispersion_dba_ring.jl` | 191 | every line |

Total 5217 lines, all read line by line (the crab harness in four cuts, 1-400 / 401-800 /
801-1180 / 1181-1554; the strong-strong harness in three, 1-360 / 361-720 / 721-1094).

References read: `docs/guides/examples_and_validation.md` (whole), `src/examples/Examples.jl`
(whole), the previous audit's `U21_report.md` (lead headers, and leads U21-18/19/20/23/24 in
full where a lead below touches them).

Cross-read for verification only (stopped at the seam, not audited): `src/tasks/strongstrong/
interface.jl` 116-165 (`CUDAPICLaunchConfig`), 326-350 (`StrongStrongDiagnostics`), 1380-1520
(`PICPoissonSolver` struct and constructor defaults), 1669-1672 (`cuda_indexed_wavefront`
schema); `src/tasks/strongstrong/gaussian_pic.jl` 94-150 (`GaussianPICPoissonSolver`
forwards `kwargs...` to `PICPoissonSolver`); `src/tasks/strongstrong/spectral.jl` grep of
`domain_factor`, `method`, `field_precision`; `src/policies/Policies.jl` 327-368
(`CUDALaunchConfig`, `CUDAExecutionPolicy` defaults); `src/beam/Beam.jl` 440-450 (the
`:multi_process_communicator` receipt fields); `src/tasks/Tasks.jl` 92-99, 232-282, 1283,
1353-1358 (positional `strong_beam_<i>` luminosity labels); `src/tasks/RunArtifact.jl`
245, 1823-1915 (`turn_modulation_provenance`); `src/elements/crab_cavity.jl` grep of
`phase_noise` (`()` accepted as all-inactive); `src/analysis/twiss_dispersion_analysis.jl`
1377-1488 (residuals and `_analysis_verdict`); `test/runtests.jl` 11250-11300, 15750-15780,
17590-17700 ("Every example script runs against the current interface"), 18205-18230,
23810-23870 (the MPI harness testset), 30260-30285, 30397-30403.

## Provenance

READ line by line: the eight region files in full (ranges above).

EXECUTED (scripts and logs under `result/comprehensive_audit_2026_10_18/probes/U38/`; every
harness run redirected with `OCTOPUS_RESULT_DIR` into that directory, every example run
through a scratch COPY with its `include` path made absolute and its `result_dir` redirected,
so nothing was written into the tree):

- `p1_gpic_dropped_options.jl` / `p1.log`: the strong-strong harness `include`d with
  `OCTOPUS_SOLVER=gaussian_pic OCTOPUS_TURNS=1 OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD=TSC
  OCTOPUS_PIC_LUMINOSITY_GRID=64,64 OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO=0.9
  OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH=0.7`, then the solver's fields read through
  `HARNESS_EXPORTS`. Exit 0. The dump printed `pic_slice_pair_green_min_ratio = 0.9`,
  `pic_slice_pair_green_growth = 0.7`, `pic_luminosity_grid = (64, 64)`,
  `pic_luminosity_deposit_method = TSC`; the solver held 0.5, 0.25, `nothing`, `nothing`;
  `pic_luminosity_deposit_method_resolved = CIC`.
- `p2.log`: the strong-strong harness with `OCTOPUS_ELECTRON_ENERGY_GEV=Inf OCTOPUS_TURNS=1`.
  Exit 1 from the LIBRARY: `ArgumentError: beam1 E0 must be finite and nonzero when kbb1 is
  not specified; got Inf` -- the harness's own finiteness clause did not fire.
- `p4_weak_strong_execution_typo.jl` / `p4.log`: a scratch copy of
  `examples/weak_strong_tracking.jl` with `execution = :gpu` (a symbol outside the four the
  comment lists), `turns = 1`, `n_macro = 200`. Exit 0, `execution policy =
  CPUThreadsExecutionPolicy`, an artifact written.
- `p5_gated_variables.jl` / `p5.log`: the strong-strong harness on CPU with
  `OCTOPUS_CUDA_DEVICE=7 OCTOPUS_CUDA_THREADS=2048 OCTOPUS_CUDA_BLOCKS=banana OCTOPUS_RANKS=16
  OCTOPUS_TURN_TIMING_PATH=<scratch>/p5_should_not_exist.tsv
  OCTOPUS_CUDA_PIC_DEPOSITION_THREADS=512 OCTOPUS_TURNS=1`. Exit 0, `policy =
  CPUThreadsExecutionPolicy(:auto)`, `solver.backend_configurations = ()`, timing file
  written = false, no message about any of the six.
- `p6_moment_capacity_negative.jl` / `p6.log`: the strong-strong harness with
  `OCTOPUS_MOMENT_CAPACITY=-7 OCTOPUS_TURNS=1`; result in LEAD U38-6.
- `p7_crab_example_rule_{none,table,pink,spectral}.jl` / `p7_<rule>.log`: four scratch
  copies of `examples/crab_cavity_noise.jl` differing from the example only in
  `rule = :<rule>` and `n_macro = 200` (2 turns, `:auto` chose CUDA). All four exit 0:
  `:none` prints "turn_modulation receipt = none recorded" and "(no modulated element in the
  line: nothing recorded)"; `:table` prints eight provenance rows with digest, name
  (`tccb_phase_noise[1]_synthetic_white`, ...) and length 1048576; `:pink` prints `pink,
  rng_id = 11, 12, 14, 15` per cavity; `:spectral` prints the factory's canonical names
  (`spectral(pink; sigma=1.0e-5, band=1.52587890625e-5..0.5, turns=1048576,
  seed=123456789, rng_id=11, slot=1, amplitudes=fixed)`, slots 1, 2, 4, 5) and the
  partial-period "no pin" row text. Result: the Clean list and LEAD U38-11.
- `twiss.log`: `examples/twiss_dispersion_dba_ring.jl` run as committed (it writes no files).
  Exit 0; run 1 `status = degraded` (uncertified longitudinal selection, canonical eigenvalue
  index 1), run 2 `status = passed`; tunes, dispersion, h, configuration report, three normal
  modes, matched rms sizes and nine residuals printed, every residual below its tolerance.
- `p3_diffs.log`, `p3b_block_diffs.log`: comment-stripped diffs of the `input` blocks and of
  the element-construction sections (`wb = input.weak_beam` .. `line_specs`) across the
  weak-strong family and of the `input` blocks of the strong-strong pair.
- `p8_timing_path_resolution.log`: a package-free `julia -e` evaluating the three harnesses'
  relative-path expressions for `OCTOPUS_TURN_TIMING_PATH`.
- Header-vs-code `OCTOPUS_*` name sets of each harness (`comm` over `grep -o`), inline.

## Leads

### LEAD U38-1 [Moderate, confidence high] test/examples/strong_strong_tracking.jl:679-694
Claim: with `OCTOPUS_SOLVER=gaussian_pic` the harness parses `OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO`, `OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH`, `OCTOPUS_PIC_LUMINOSITY_GRID` and `OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD`, prints them in its configuration dump as applied, and never passes them to the solver.
Mechanism: the `gaussian_pic` branch builds `GaussianPICPoissonSolver(; slicing, luminosity_scale, grid, deposit_method, green_type, green_cache, longitudinal_kick, batch_mode, cuda_*, luminosity_schedule, backend_configurations)` and omits `slice_pair_green_min_ratio`, `slice_pair_green_growth`, `luminosity_grid`, `luminosity_deposit_method`, although `GaussianPICPoissonSolver{T}(; kwargs...)` forwards every keyword to `PICPoissonSolver{T}` and accepts all four (`src/tasks/strongstrong/gaussian_pic.jl:94-96`); the `pic` branch (696-715) passes them. The dump at 1002-1018 is gated on `solver isa Union{PICPoissonSolver,GaussianPICPoissonSolver}`, so for `gaussian_pic` it prints the harness variables, which hold the requested values, not the solver's -- the U21-20 class ("a configuration dump that lists what was NOT applied") in the one branch that fix did not reach. The line `pic_luminosity_deposit_method_resolved` (1024-1028) exposes the contradiction on the same screen (`TSC` requested, `CIC` resolved); nothing refuses.
Repro: `OCTOPUS_RESULT_DIR=/tmp/u38 OCTOPUS_SOLVER=gaussian_pic OCTOPUS_TURNS=1 OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD=TSC OCTOPUS_PIC_LUMINOSITY_GRID=64,64 OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO=0.9 OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH=0.7 julia --project=. test/examples/strong_strong_tracking.jl` prints `pic_slice_pair_green_min_ratio = 0.9`, `pic_luminosity_grid = (64, 64)`, `pic_luminosity_deposit_method = TSC` and `pic_luminosity_deposit_method_resolved = CIC`, exit 0; `include` the harness and read `solver.pic.slice_pair_green_min_ratio` (0.5), `solver.pic.slice_pair_green_growth` (0.25), `solver.pic.luminosity_grid` (`nothing`), `solver.pic.luminosity_deposit_method` (`nothing`) -- measured, `probes/U38/p1.log`.

### LEAD U38-2 [Moderate, confidence high] examples/weak_strong_tracking.jl:166-199
Claim: in the two older clean examples a `config.execution` outside the four documented symbols, or a `config.ranks` / `config.gpu_device` / `config.threads` the chosen mode never reads, is silently accepted and the run falls back to CPU threads -- the precedent users imitate silently drops a non-default request.
Mechanism: `cuda_ok` is set only when `execution` is `:auto` or `:cuda`; the policy `if` tests `=== :multiprocess`, then `cuda_ok`, then falls to `CPUThreadsExecutionPolicy` for EVERY other value, so `:gpu`, `:thread`, `:CUDA` all run on CPU threads with exit 0 and the "execution policy = CPUThreadsExecutionPolicy" line as the only trace. `config.ranks` is read only under `:multiprocess`, `config.gpu_device` only under a functional CUDA device, `config.threads` only off CUDA; set elsewhere they are configuration nothing read. `examples/strong_strong_tracking.jl:158-191` is the same code. `examples/crab_cavity_noise.jl:367-374` already validates `execution` and refuses an unread `ranks` ("a configuration nothing read, which this repository counts as a defect"), so the fix landed in the newest sibling only; none of the three guards `gpu_device` or `threads`. Class 5/11 and the sibling-drift rule.
Repro: copy `examples/weak_strong_tracking.jl`, set `execution = :gpu`, run it: prints `execution policy = CPUThreadsExecutionPolicy` and exits 0 (measured, `probes/U38/p4.log`, with `turns = 1`, `n_macro = 200`); `sed -n '166,199p' examples/weak_strong_tracking.jl` shows no `else error(...)` arm; `grep -n "config.ranks ===\|config.execution in" examples/*.jl` matches only `crab_cavity_noise.jl`.

### LEAD U38-3 [Moderate, confidence high] test/examples/strong_strong_tracking.jl:420-450
Claim: six `OCTOPUS_*` variables of the strong-strong harness are read only inside a branch whose switch is off by default, so a set value is silently ignored -- including values that would be refused if read -- while the harness's own guard for the same class (718-744) covers only the solver-mismatch case.
Mechanism: `OCTOPUS_CUDA_DEVICE`, `OCTOPUS_CUDA_THREADS`, `OCTOPUS_CUDA_BLOCKS` are read inside `if use_gpu` (421-425); `OCTOPUS_RANKS` inside `if use_mpi` (440); `OCTOPUS_TURN_TIMING_PATH` inside `if record_turn_times` (955); the seven `OCTOPUS_CUDA_PIC_*_THREADS` are parsed and range-checked (571-580) and then dropped on CPU by `cuda_pic_backend_configurations = use_gpu ? (cuda_pic_launch,) : ()` (581). The weak-strong harness has the same shape for `OCTOPUS_CUDA_DEVICE` (300), `OCTOPUS_RANKS` (315) and `OCTOPUS_TURN_TIMING_PATH` (522). The crab harness refuses each of these by name when its switch is off (623-639, 774-779) and says why ("a set variable nothing reads is the config-that-was-never-read defect class"); `OCTOPUS_RANKS=16` under a launcher with the MPI switch off is the "P whole simulations on one artifact path" case that header names.
Repro: `OCTOPUS_RESULT_DIR=/tmp/u38 OCTOPUS_TURNS=1 OCTOPUS_CUDA_DEVICE=7 OCTOPUS_CUDA_THREADS=2048 OCTOPUS_CUDA_BLOCKS=banana OCTOPUS_RANKS=16 OCTOPUS_TURN_TIMING_PATH=/tmp/u38/never.tsv OCTOPUS_CUDA_PIC_DEPOSITION_THREADS=512 julia --project=. test/examples/strong_strong_tracking.jl` exits 0 on `CPUThreadsExecutionPolicy(:auto)`, writes no `/tmp/u38/never.tsv`, builds `solver.backend_configurations == ()`, and prints nothing about any of the six (`banana` would be a `parse(Int, ...)` error if read) -- measured, `probes/U38/p5.log`.

### LEAD U38-4 [Minor, confidence high] test/examples/strong_strong_tracking.jl:961-967
Claim: one variable, `OCTOPUS_TURN_TIMING_PATH`, has three resolution rules and three TSV layouts across the three harnesses, and the strong-strong header misdescribes its own.
Mechanism: strong-strong resolves a relative path as `joinpath(@__DIR__, "..", path)`, i.e. against `test/`, while its header (82-83) says "resolves against `test/result/`" -- true only for the documented example `result/pic_turn_times.tsv` because that path begins with `result/`; the weak-strong (527) and crab (1246-1247) harnesses resolve against the repository root (`joinpath(@__DIR__, "..", "..", path)`) and say so. The files differ too: strong-strong writes `turn - 1` (0-based) in two columns (969-973), weak-strong writes 1-based `i` in two columns (529-533), the crab harness 1-based with a third `max_over_ranks_seconds` column (1249-1253); the stdout line is `join(timings, ',')` in one and the printed vector in the other two. One quantity, three conventions (class 9); a consumer that reads the TSV of one harness misreads the next.
Repro: `julia -e 'd="<repo>/test/examples"; println(normpath(joinpath(d,"..","x.tsv"))); println(normpath(joinpath(d,"..","..","x.tsv")))'` gives `<repo>/test/x.tsv` and `<repo>/x.tsv` (measured, `probes/U38/p8_timing_path_resolution.log`); `grep -n 'turn - 1\|println(io, i, "\\t"' test/examples/*.jl` shows the two turn conventions.

### LEAD U38-5 [Minor, confidence high] test/examples/strong_strong_tracking.jl:460-466
Claim: `_energy_env`'s finiteness clause is dead code (`||` where `&&` was meant), so `OCTOPUS_ELECTRON_ENERGY_GEV=Inf` passes the harness's own validation and is caught only downstream by the library.
Mechanism: `(isfinite(gev) || gev > 0) || error("... must be a positive number of GeV ...")` is false only for `NaN`; for `Inf` the second disjunct is true, the following `gev > 0` check passes, and `Inf * 1e9` reaches `Beam(...; E0 = Inf)`. The library refuses it (`beam1 E0 must be finite and nonzero when kbb1 is not specified`), so the outcome is loud, but the harness message the U21-22 fix added never fires for the case it names, and the harness's `electron_energy_GeV = Inf` dump line is never reached to say what was asked.
Repro: `OCTOPUS_RESULT_DIR=/tmp/u38 OCTOPUS_ELECTRON_ENERGY_GEV=Inf OCTOPUS_TURNS=1 julia --project=. test/examples/strong_strong_tracking.jl` exits 1 with the library's `ArgumentError`, not the harness's "must be a positive number of GeV" (measured, `probes/U38/p2.log`); `julia -e 'f(g) = (isfinite(g) || g > 0); println(f(Inf), " ", f(NaN), " ", f(-5.0))'` prints `true false true`.

### LEAD U38-6 [Minor, confidence high] test/examples/strong_strong_tracking.jl:567-570
Claim: a negative `OCTOPUS_MOMENT_CAPACITY` is neither refused nor applied: the moments stay on and the artifact is built with the default capacity.
Mechanism: `moment_capacity == 0` folds into `disable_moments`; `artifact_capacity = moment_capacity > 0 ? moment_capacity : input.output.capacity` replaces every other non-positive value by 1024 and the dump prints no capacity line, so the request vanishes without a word (class 5/11; the same variable's zero case was U21-19).
Repro: `OCTOPUS_RESULT_DIR=/tmp/u38 OCTOPUS_MOMENT_CAPACITY=-7 OCTOPUS_TURNS=1 julia --project=. test/examples/strong_strong_tracking.jl` exits 0 and prints both `electron moments = ...:/moments/electron` and `proton moments = ...` paths; `include` the harness and read `task.artifact.capacity` -- 1024, not -7 and not a refusal (measured, `probes/U38/p6.log`).

### LEAD U38-7 [Minor, confidence high] test/examples/weak_strong_tracking.jl:1-90
Claim: the weak-strong harness header documents eight `OCTOPUS_*` variables and omits three it reads -- `OCTOPUS_RESULT_DIR`, `OCTOPUS_RECORD_TURN_TIMES`, `OCTOPUS_TURN_TIMING_PATH`; the strong-strong header's "Further switches ... all read below" list (77-89) omits `OCTOPUS_RESULT_DIR`.
Mechanism: the U18-2 / U21-23 fix listed every switch by name in the strong-strong header; the weak-strong twin received the switches (2026-09-06) with read-site comments only, and the strong-strong list predates `OCTOPUS_RESULT_DIR`'s arrival at its read site (317). Documentation as claims (class 14); the crab harness header lists every variable it reads (checked, empty both ways).
Repro: `f=test/examples/weak_strong_tracking.jl; comm -13 <(sed -n '1,90p' $f | grep -o 'OCTOPUS_[A-Z_]*' | sort -u) <(sed -n '91,$p' $f | grep -o 'OCTOPUS_[A-Z_]*' | sort -u)` prints the three names; the same with `1,200p` / `201,$p` on the strong-strong harness prints `OCTOPUS_RESULT_DIR` (plus the comment fragment `OCTOPUS_CUDA_PIC_`).

### LEAD U38-8 [Minor, confidence high] test/examples/strong_strong_tracking.jl:164-168
Claim: the header presents `OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=1` as the way to "test the indexed CUDA wavefront path", but 1 is the default, so the documented command changes nothing and the A/B value is 0.
Mechanism: the harness default is `env_bool("OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT", true)` (531) and the solver schema default is `true` (`src/tasks/strongstrong/interface.jl:1669`); the three neighbouring switches (148-158) are correctly documented as "Disable ... =0". A reader following the header believes they exercised an alternative route and ran the default (class 14).
Repro: `grep -n "INDEXED_WAVEFRONT" test/examples/strong_strong_tracking.jl` shows `=1` in the header and `true` as the default at the read site; `grep -n -A1 "cuda_indexed_wavefront = SolverOptionMeta" src/tasks/strongstrong/interface.jl` shows `true`.

### LEAD U38-9 [Minor, confidence med] examples/strong_strong_tracking.jl:94
Claim: the strong-strong example's `input` hand-copies derived quantities -- the crab strengths repeat `12.5e-3`, `150.0 * 0.55`, `1300.0 * 0.8` (94, 113-117) and the longitudinal betas repeat `0.7e-2 / 5.5e-4`, `6.0e-2 / 6.6e-4` (88, 90, 107, 109) -- so editing `input.crossing_angle` (79) leaves the crab kicks at 12.5 mrad and editing `sigma[3]` leaves `beta_z` behind.
Mechanism: the comment at 73-78 warns that the factor of two in the crossing angle "is the classic beam-beam error" and then the angle is written four times; the weak-strong trio derive the kick once (`cckick = tan(opt.crossing_angle) / sqrt(wb.beta_x * opt.crab_beta_x)`) and `examples/knob_control.jl` exists to demonstrate the one-knob pattern for exactly this quantity. The harness twin (342, 361-365, 336-338, 355-357) carries the same copies. Class 2, out of hypothesis 1's letter but in hypothesis 2's spirit (a precedent that teaches the drift).
Repro: `grep -c "12.5e-3" examples/strong_strong_tracking.jl` prints 4 (one field, three copies); `grep -n "0.7e-2 / 5.5e-4\|6.0e-2 / 6.6e-4" examples/strong_strong_tracking.jl` prints four lines.

### LEAD U38-10 [Minor, confidence med] examples/crab_cavity_noise.jl:170-172
Claim: the physics identity the headers promise ("Everything but `crab_noise` reproduces the weak-strong example's case, numbers unchanged"; each harness "the same case") holds today but rests on five hand-copied `input` blocks with no tripwire; the suite runs each script and compares none of them.
Mechanism: the weak-strong example, its harness, the crab example and the crab harness each carry the full `weak_beam`/`optics`/`crab_cavity`/`strong_beam`/`radiation`/`output` block; comment-stripped diffs show zero physics differences today (`p3b_block_diffs.log`: the `input` blocks differ only in `case_name`/`result_dir`/`seed`/env plumbing and the `crab_noise` block; the construction sections of the weak-strong pair are identical, the crab pair differs only in the noise builders, `kbb_scale`, the radiation toggle). Nothing holds them together: "Every example script runs against the current interface" (`test/runtests.jl:17590`) asserts exit 0 per script, so one block drifting is six green runs away from the U21-24 class the headers already record once. The strong-strong pair's `input` blocks are likewise identical except for harness-only fields.
Repro: `blk() { awk '/^input = \(/{p=1} p{print} p&&/^\)/{exit}' "$1" | sed 's/#.*$//' | grep -v '^\s*$'; }; diff <(blk examples/weak_strong_tracking.jl) <(blk test/examples/weak_strong_tracking.jl)` prints two lines (`result_dir`, `seed`) today; `grep -rn "weak_strong_tracking.jl\|input\.weak_beam" test/runtests.jl | grep -c diff` prints 0.

### LEAD U38-11 [Minor, confidence med] examples/crab_cavity_noise.jl:453
Claim: the crab example's documented non-default rules (`:none`, `:pink`, `:table`, `:spectral`) and their readback branches (the `:table` provenance fields at 768-770, the `n_rows == 0` path at 849) are executed by nothing committed: the suite runs the example at its default (`:white`) and `validation/crab_cavity_noise_response.jl` drives the HARNESS, not the example.
Mechanism: `test/runtests.jl:17665-17668` runs each catalogued example with an empty environment, and the example takes no environment by design; `grep -rn OCTOPUS_NOISE_RULE test/runtests.jl validation/*.jl` finds the harness's switch only. The example is the catalogued precedent for "three verification questions ... through one switch", so a reader changing that one line is the first to execute the branch (class 13). Executed in this unit (probe P7): all four branches run to exit 0 today and print what their comments promise (digest/name/length for `:table`, canonical spectral names with slot indices 1, 2, 4, 5 and rng_ids 11, 12, 14, 15 as the comment at 444-446 derives, the `:none` "nothing recorded" line), so this is a coverage gap, not a present breakage.
Repro: `grep -n "rule = :" examples/crab_cavity_noise.jl` (one line, `:white`); `grep -rn "crab_cavity_noise.jl" test/runtests.jl validation/*.jl | grep -v "test/examples"` shows the example is referenced only by the catalogue runner; the four `probes/U38/p7_<rule>.log` files hold the measured runs.

## Clean

- Harness <-> example identity (hypothesis 1), measured by comment-stripped diffs
  (`p3b_block_diffs.log`): weak-strong example vs harness, `input` blocks identical but for
  `result_dir`/`seed`, construction sections identical (empty diff); weak-strong example vs
  crab example, identical but for `case_name`, the added `crab_noise` block and
  `record_turn_modulation = true`, construction identical but for the noise builders and
  `ThinCrabCavitySpec{N_harmonics}` with the two noise keywords; crab example vs crab harness,
  identical physics with the env plumbing, `kbb_scale` on `kbb`, and the radiation toggle as
  the only differences; strong-strong example vs harness `input` blocks identical except
  harness-only fields (`default_demo_macroparticles`, `pic_luminosity_deposit_method =
  nothing`, `min_sigma`, `luminosity_scale = nothing`). The strong-strong harness's default
  solver equals the example's: every keyword it adds (`batch_mode = :wavefront`, the four
  `cuda_*` flags `true`, `luminosity_schedule/grid/deposit_method = nothing`,
  `backend_configurations = ()`) is the `PICPoissonSolver` constructor default
  (`interface.jl` 1418-1483), and `CUDALaunchConfig(threads = 256, blocks = :auto)` is
  `CUDAExecutionPolicy`'s default launch (`Policies.jl` 348, 368).
- The catalogue (`src/examples/Examples.jl`) names five scripts, all present; the suite derives
  the expected set from `examples/` in both directions (`runtests.jl` 15770-15774,
  17616-17625) and runs every catalogued example and every harness under
  `test/examples/` in a subprocess (17632-17700), harnesses with `OCTOPUS_RESULT_DIR` and a
  must-have-written check. Catalogue claims measured: the twiss entry ("the default run is
  :degraded ..., the certified second run is :passed and prints tunes, dispersions, normal
  modes, matched beam sizes and the residual checks") reproduced exactly (`twiss.log`); the
  crab entry's "record_turn_modulation option on, as its default run has it" matches line 322.
- `/luminosity/strong_beam_1`, promised by three headers, is the positional label the task
  assigns (`Tasks.jl:1353-1357`, `string("strong_beam_", i)`), read by the suite at
  `runtests.jl:18222`; `/luminosity/ip` is the collision's name.
- API usage checked against the current constructors and readers: `PICPoissonSolver` keywords
  incl. `green_cache ∈ (:none, :slice_pair)`, `luminosity_schedule`; the commented
  alternatives in the example (`GaussianPoissonSolver(; slicing, longitudinal_kick)`,
  `SpectralPoissonSolver(; grid, domain_factor, method = :grid, longitudinal_kick)`,
  `GaussianPICPoissonSolver(; grid, longitudinal_kick)`) all exist with those keywords;
  `field_precision ∈ (:double, :single)`; `StrongStrongDiagnostics(; record_turn_times,
  memory_log_every, pic_timing, pic_timing_detail, cache_stats, nvtx)`;
  `CUDAPICLaunchConfig` range-checks 1:1024 (so the header's "parsed, range-checked" is true);
  `TrackingTask(; record_turn_times)` and `turn_timings`; `RunArtifact(; capacity,
  record_turn_modulation)`; the `:multi_process_communicator` receipt carries `nranks, rank,
  requested_ranks, resolved_by, threads` (`Beam.jl:446-448`) as the crab scripts read;
  `turn_modulation_provenance` returns an empty vector for an unmodulated run (docstring,
  `RunArtifact.jl:1888-1891`) and its slot fields `slot, kind, rng_id, digest, name, length,
  nominal, series` are the ones the two crab scripts read; `ThinCrabCavitySpec` accepts
  `phase_noise = ()` as all-inactive (`crab_cavity.jl:326`).
- The crab harness: every `OCTOPUS_*` it reads is in its header and every header name is read
  (empty `comm` both ways); every switch-gated variable is refused by name when its switch is
  off; the summary line's `chrom`, `kbb_scale`, `radiation`, `seed`, `ranks`, `threads`,
  `device`, `record` are readbacks checked against the request (1485-1510, 1169-1207).
- The crab example's four non-default rule paths (`:none`, `:table`, `:pink`, `:spectral`)
  execute against the current interface and read back what their comments promise (probe P7,
  four exit-0 runs; the `:spectral` canonical names carry `seed=123456789`, `rng_id` 11/12/14/15
  and `slot` 1/2/4/5, matching the explicit-id scheme the script derives at 439-450). The gap
  is only that nothing committed runs them (LEAD U38-11).
- `_rms_label` / shard labelling in both tracking examples and harnesses; `OCTOPUS_MP` refused
  on presence in all three harnesses; `env_bool` one grammar in all three.
- The strong-strong harness fixes recorded by U21 are in place and verified by reading:
  `policy = policy` at the task (U21-17), the `_moment_status` written-not-configured report
  (U21-19), PIC-family lines gated on the PIC-family solvers (U21-20, except the `gaussian_pic`
  gap of U38-1), `_grid_env` arity errors (U21-21), positive-energy check (U21-22, except the
  dead clause of U38-5), the header listing (U21-23), the removed dead `n_macro`/`total_turns`
  fields (U21-24), `coordinate_arrays` (U21-25), `OCTOPUS_RESULT_DIR` (U21-27).
- `examples/twiss_dispersion_dba_ring.jl:190` prints every residual as `value <= tol`
  unconditionally, but the claim has a check behind it: `_analysis_verdict`
  (`twiss_dispersion_analysis.jl:1477-1486`) turns any excess into `:failed` with a named
  failure, and the script prints `status` and every `failures` entry first (136-142). In the
  measured run all nine residuals were below tolerance by 3 to 27 orders.
- `examples/knob_control.jl:185-191` prints a symbolic derivative beside a finite difference
  without comparing them; the mechanism is pinned in the suite (`runtests.jl:30397-30403`,
  `≈`), so this is presentation, not an unchecked claim. `@knob pro.crab_harmonics::Int = 2`
  is read by nothing but its own print (129): a typed-knob demonstration, noted as style.
- Line order and placement: both tracking examples and their harnesses place the same elements
  in the same order (crab transport, boost pair, collision/strong beam, one-turn, chromaticity,
  radiation on the electron/weak side only, observer last); the knob example's trim override
  indexes placement 3, which is `qd` in `(qf, d, qd, d)`.

## Unchecked

- No probe ran on CUDA or under MPI: the `:cuda` / `:multiprocess` arms of the three examples
  and the `OCTOPUS_USE_GPU` / `OCTOPUS_USE_MPI` arms of the three harnesses were read, not
  executed (the suite's MPI harness testset and the previous campaigns cover them; this unit's
  budget went to the CPU-reachable toggles). The crab example's `:multiprocess` readback
  (708-726) was checked against the receipt's field names only.
- `OCTOPUS_TABLE_FILE` (crab harness 838-888) was read, not fed a file.
- The example runner's cleanup logic (`runtests.jl:17640-17700`) was read for what it executes,
  not audited (another unit's region).
- Whether `validation/strong_strong_diagnostics_benchmark.jl` or
  `validation/strong_strong_pic_extreme_benchmark.jl` parse the strong-strong TSV (LEAD U38-4's
  consumer side) was not checked: a cross-file seam, left to the auditor.
