# U7 (EXECUTED): the crab cavity noise example, harness, benchmark driver and validation study

Reading unit U7 of the comprehensive audit of the crab cavity noise campaign.
Repository `/cfs/ad/dxu/Library/Julia/Octopus` at `3126908` (main), read in
place; no repository file was modified. Julia 1.12.4, host acnlinj4 (128
cores, one RTX 4500 Ada with 11.9 GB held by another process throughout),
MPICH_jll 5.0.1 `mpiexec` through `MPI.mpiexec()`. Every run wrote under
`result/audit_crab_noise_2026_10_16/U7/` (`OCTOPUS_RESULT_DIR` set per run;
the driver's `out=` and the validation's `out=` likewise), nothing under the
repository's `result/<seed>/`. Scratch probes: `U7/probe_*.jl`,
`U7/run_rules.sh`, `U7/run_batch2.sh`; their outputs `U7/*.out`, logs under
`U7/runs/`, `U7/example/`, `U7/driver/`, `U7/noise_part.log`,
`U7/tablefile/`.

## Region and provenance

Read in full, every line (the campaign diff `6995151..3126908` is the whole
of each file; all four are new in the campaign):

- `examples/crab_cavity_noise.jl` (866 lines)
- `test/examples/crab_cavity_noise.jl` (1409)
- `profiling/crab_cavity_noise_backends.jl` (753)
- `validation/crab_cavity_noise_response.jl` (2365)
- `validation/README.md` lines 418-549 ("Crab Cavity Noise Response")
- `src/examples/Examples.jl` lines 88-107 (the catalogue entry)

Read for mechanism (outside the region, not audited line by line):
`src/elements/turn_modulated.jl` (key layout 96-159, `WhiteNoise`,
`TurnTable`, the spectral plan/synthesis 300-530, `spectral_turn_table`,
`SpectralNoise`, `_resolve_turn_rule`, `PinkNoise`, `_collect_turn_modulation_ids!`,
`_collect_turn_tables!`), `src/tasks/Tasks.jl` 375-460 (the shared-id and
equal-digest warnings), `src/tasks/RunArtifact.jl` (what the provenance and
the `/execution` ledger record), `src/elements/radiation.jl` 100-116,
`src/elements/crab_cavity.jl` 285-320, `examples/weak_strong_tracking.jl`
104-118; the records `docs/history/crab_cavity_noise_validation_2026_10_14.md`,
`crab_cavity_noise_mpi_benchmark_2026_10_14.md`,
`crab_cavity_noise_relative_strength_2026_10_15.md` (136-150, 236-248),
`spectral_turn_table_2026_10_16.md` (570-632), and the example paragraph of
`docs/public_api.md` (283-300).

Executed (every command exit 0 unless stated; all in package mode
`julia --project=. --threads=16 -e 'using Octopus; include(<file>)'`, which the
harness header sanctions):

| run | what | key numbers |
|---|---|---|
| `runs/white`, `pink`, `table`, `spectral` | the harness at 2 turns, 10000 macroparticles, record on, one per rule | 4 x exit 0; 34-field `CRAB-NOISE` lines |
| `runs/cuda_white` | `OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_DEVICE=0` | `threads=NA`, receipt `backend = CUDABackend`; series bitwise == CPU; luminosity vs CPU max rel 3.9e-16 |
| `runs/mpi2_white` | `mpiexec -n 2`, `OCTOPUS_USE_MPI=1 OCTOPUS_RANKS=2 OCTOPUS_CPU_THREADS=4`, `--threads=4` | `ranks=2 threads=4`; luminosity bitwise == CPU; series bitwise == CPU; eps_x_last 1.1291200672864344e-8 vs 1.1291200672864306e-8 (fold bound) |
| `runs/probeA..E, probeD2` | one non-default value per toggle (hypothesis i) | `probe_records.jl`: 170 assertions, ALL OK |
| `runs/eff_norad`, `eff_kbb0`, `eff_chrom0` | the echo-only toggles against `runs/white` | radiation: bitwise identical (lead U7-1); kbb, chrom: 27 of 28 moment columns differ |
| `tablefile/` + `runs/tf_white`, `tf_table` | validation part `tablefile` at 8 turns fed back through `OCTOPUS_TABLE_FILE` | 28 moment columns, luminosity and all recorded series bitwise equal |
| `example/default.log` | `examples/crab_cavity_noise.jl` unmodified but for `result_dir` (`:auto` chose CUDA) | the printed rms table as the header describes |
| `example/{pink,table,spectral,spectral64}.log` | sed copies of the example (`rule`, `execution = :threads`; `spectral64`: `turns = table_turns = 64`, band `(1/16, 1/2)`) | pink "no pin"; table band 1 +- 0.5; spectral partial period "no pin"; spectral64 ratio 1.0 exactly |
| `driver/` | `profiling/crab_cavity_noise_backends.jl harness=crab n_macro=1000 turns=25 skip=20 arms=threads:4,mpi:2x4,cuda baseline=threads:4 tag=u7dry`, then the same command again (resume) | 3 rows; MPI luminosity bitwise, moments worst `m000010` 7.9e-13; CUDA 8.2e-16; resume skips 3 and reprints the table |
| `noise_part.log` | `validation/crab_cavity_noise_response.jl noise out=<U7>/noise_part` | `CRAB-NOISE-RULES turns=65536 checks=273 failed=0 verdict=PASS`; 2 min 17 s wall including the 27 s package load |
| `probe_arith.out`, `probe_misc.out` | the arithmetic of the printed bands and header numbers; the CUDA configuration report; pink one-sigma Monte Carlo | below |

## Leads

### LEAD U7-1 [low-medium, confidence high] test/examples/crab_cavity_noise.jl:193
Claim: The `OCTOPUS_RADIATION` toggle (and the example's radiation element) has no effect on any output: the lumped radiation element of this case is numerically inert, so "radiation on" is not a stochastic drive and the header's "with 0 the lumped radiation element is omitted from the line, so the only stochastic drive is the crab noise" (also `profiling/crab_cavity_noise_backends.jl:18` and the 2026-10-14 benchmark record's "with radiation excitation on") describes a difference that does not exist.
Mechanism: `examples/crab_cavity_noise.jl:288-296` (and the harness at 678-686) take `damping_turns = (1e100, 1e100, 1e100)`, `is_damping = false`, `is_excitation = true` from the weak-strong example. `LumpedRadSpec` (`src/elements/radiation.jl:110-113`) evaluates the excitation scale as `sqrt(-expm1(-2/tau)) = 1.4e-50`; the kick added to coordinates of order 1e-4 is ~1e-54, far below half an ulp (7e-21), so every coordinate is unchanged while six normals per particle per turn are drawn and discarded. The element is present, read and applied, and changes nothing; the toggle is read and omits an element that does nothing. Cross-file seam: `examples/weak_strong_tracking.jl:110-113` carries the same block without saying it is inert.
Repro: run the harness twice at 2 turns, `OCTOPUS_NOISE_RULE=white` with and without `OCTOPUS_RADIATION=0` (same `OCTOPUS_SEED`), then compare every `/moments/weak_beam` column and `/luminosity/strong_beam_1` of the two artifacts (`U7/probe_effects.jl`): expected "28 columns bitwise, 0 differ; luminosity bitwise = true", while the same comparison with `OCTOPUS_KBB_SCALE=0` or `OCTOPUS_CHROMATICITY=0,0` differs in 27 columns. In Julia: `sqrt(-expm1(-2/1e100))` is `1.4142135623730951e-50`.

### LEAD U7-2 [low, confidence high] test/examples/crab_cavity_noise.jl:481
Claim: Under `OCTOPUS_NOISE_RULE=spectral` at the suite-sized default of 2 turns the harness's spectral tables degenerate to one Nyquist bin and three of the four phase slots across the TWO cavities carry identical tables, with no equal-digest warning.
Mechanism: the harness ties `table_turns = turns` (line 481) for the spectral rule as for the synthetic table. At N = 2 the band `(2^-16, 1/2)` holds the single bin k = 1 (Nyquist), whose entry is real with the sign of `cos(phi_k)` (`src/elements/turn_modulated.jl:518-519`), so the table is `[+sigma, -sigma]` or `[-sigma, +sigma]`: two possible tables per sigma. In `runs/spectral.log` tccb phase 1, tccb phase 2 and tcca phase 2 all carry digest `0x9b13117e35e38739`, the three matching strength slots `0x8fd5a304a854ae11`. `_warn_duplicate_turn_tables` cannot fire: `_collect_turn_tables!` (turn_modulated.jl:1505) walks the SPECS, where a `SpectralNoise` has no `digest` field (the tables exist only after `_resolve_turn_rule` at compile), so equal resolved tables are never seen; the shared-id warning does not apply (the ids 11, 12, 22 differ). The few-bins warning does fire, sixteen times (eight from the harness's own `spectral_turn_table` reference build, eight from the `SpectralNoise` constructors). The example is not affected: its `table_turns = 1_048_576` is independent of `turns`.
Repro: `OCTOPUS_NOISE_RULE=spectral julia --project=. test/examples/crab_cavity_noise.jl` (2 turns) and read the eight provenance digests printed under "turn_modulation provenance": expect only two distinct digests among the four phase slots and two among the four strength slots and no "same digest" warning; or `spectral_turn_table(:pink, 1e-5, (1/2^16, 0.5); turns = 2, seed = 123456789, rng_id = id, slot = s)` for `(id, s)` in `(11,1), (12,2), (22,2)`: all three return `[-1.0e-5, 1.0e-5]` (`U7/probe_arith.out`, section "spectral N=2").

### LEAD U7-3 [low, confidence high] test/examples/crab_cavity_noise.jl:1387
Claim: `kbb_scale=`, `radiation=`, `chrom=`, `table_file=` and `seed=` in the `CRAB-NOISE` line are echoes of the harness's parsed variables, not readbacks of anything the run recorded, so `verify_receipt` in `validation/crab_cavity_noise_response.jl:1352-1393` ("the receipt must state the requested configuration: a configuration you set is not one the code read") is, for those fields, an echo check.
Mechanism: the line is built from `kbb_scale`, `use_radiation`, `chromaticity`, `cn.table_file`, `input.seed` (lines 1387-1393), the same variables the specs were built from; the artifact's `/execution` ledger holds `(start_turn, turns, current_turn, elapsed)` only (`read(out, :execution)`), no element list and no spec parameters, so nothing in the output can show the kick strength, the chromaticity or the line's element set that ran. The fields that ARE readbacks are `ranks` (the communicator receipt), `threads` (`configuration_report`), `record` and the `rms_*` fields (the recorded series), and `phase_rms`/`strength_rel_rms` indirectly (the series are sigma times the counter-RNG draws, checked bitwise in `U7/probe_records.jl`). The effect probes show `kbb_scale` and `chrom` do reach the line (27 of 28 moment columns and the luminosity differ) while `radiation` cannot be shown to (U7-1).
Repro: `julia --project=. -e 'using Octopus; println(read(TaskOutput(<artifact>), :execution))'` on any harness artifact: `(start_turn = [0], turns = [T], current_turn = [T-1], elapsed = [..])` and nothing else; `U7/probe_records.jl` prints it for every run.

### LEAD U7-4 [low, confidence high] test/examples/crab_cavity_noise.jl:716
Claim: `OCTOPUS_CUDA_DEVICE` is read and passed to `CUDAExecutionPolicy(device = ...)` but recorded in no output: not in the `CRAB-NOISE` line (`threads=NA`), not in the receipt (`backend = CUDABackend`), not in the artifact.
Mechanism: `configuration_report(CUDAExecutionPolicy(device = 0))` lists `device` as `:unresolved` ("validated against CUDA particle storage at execution"), and the harness reads the report only for `:threads` (line 1111); no `:cuda_device` receipt is consulted. On this one-GPU host a wrong index would presumably error, but a multi-GPU run cannot show which device it used.
Repro: `OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_DEVICE=0 julia --project=. test/examples/crab_cavity_noise.jl | grep -i device` prints nothing; `U7/probe_misc.out` shows the configuration entry.

### LEAD U7-5 [low (documentation), confidence high] validation/README.md:457
Claim: The README's list of part `noise` checks still says "the strength offset equal on both planes to 4 ulp", the pre-2026-10-15 additive check, while the same section states the relative semantics (`S (1 + d)`, `strengthY` staying 0) and the code's items are `recovered strength factor vs the rule's value <= 4 ulp(1)` and `exact: phase + d; X == S (1 + d), Y === 0.0` (`validation/crab_cavity_noise_response.jl:883-888`).
Mechanism: the sentence was carried over from the 2026-10-14 record (`docs/history/crab_cavity_noise_validation_2026_10_14.md:208`, frozen and correct for its date) when the README section was updated on 2026-10-15 and 2026-10-16.
Repro: `grep -n "both planes to 4 ulp" validation/README.md` (one hit) against `julia --project=. validation/crab_cavity_noise_response.jl noise | grep -c "both planes"` (0) and `grep -c "recovered strength factor"` (6).

### LEAD U7-6 [low, confidence medium] src/elements/turn_modulated.jl:889 (cross-file seam, outside the region; the validation uses the same formula)
Claim: The `PinkNoise` docstring's "13.8 % at 16384" does not follow from the formula it cites (`Var[rms^2] = (2/(K^2 N)) sum_k 2^k (2K - 1 - 2k)`), which gives 15.3 % at N = 16384; the construction's Monte Carlo gives 13.5 % there and 7.30 % at 65536 against the formula's 7.65 %.
Mechanism: the formula counts every generator as holding `N / 2^k` independent values; at N < 2^K generators k >= log2(N) hold one value for the whole run (the validation's own `pink_rms_mc_fn` models exactly that), so the formula overstates. The validation prints the formula only as INFO at N = 65536 (`validation/crab_cavity_noise_response.jl:757`, "one-sigma 7.654 %") and takes its verdict from the Monte Carlo band at 2^20, so no verdict rests on it; the headers quoting "7.65 %" (example line 785, harness line 260) quote the formula.
Repro: `U7/probe_misc.jl`: `pink_rms_one_sigma(16, 16384)` = 0.1531, `std(pink_rms_mc_fn(16384, 16; streams = 4096))` = 0.1351; at 65536: 0.0765 vs 0.0730.

### LEAD U7-7 [info, confidence high] src/tasks/RunArtifact.jl (provenance of a resolved spectral slot; cross-file seam)
Claim: A spectral slot reads back with kind `:table` and `rng_id = 0`; the stream id exists only inside the canonical name string.
Mechanism: `_resolve_turn_rule` replaces the `SpectralNoise` by a `TurnTable` before the provenance walk, and a `TurnTable` has no `rng_id`; the writer stores 0. The example and harness print `rng_id` for non-table kinds only, so nothing misprints, but a reader filtering slots by `s.rng_id` sees 0 for every spectral slot and must parse `rng_id=(\d+)` out of `s.name` (which `U7/probe_records.jl` had to do).
Repro: `turn_modulation_provenance(<spectral artifact>)[1].elements[1].slots[1]` -> `rng_id = 0x0000000000000000`, `name = "spectral(pink; ...; rng_id=11, slot=1, ...)"`.

## Hypothesis by hypothesis

### (i) A configuration set but not read: where the run RECORDS each toggle (Measured Lesson 11)

Probed with one non-default value each at small size on CPU; "recorded" means read back from the artifact, the receipts or the per-turn record, "echo" means the harness printing the variable it parsed. `U7/probe_records.jl` (170 assertions, ALL OK) holds every check.

| variable | probe value | where the RUN records it | result |
|---|---|---|---|
| `OCTOPUS_NOISE_RULE` | each of white, pink, table, spectral | receipt slot kinds; provenance `kind` (`:table` for spectral) | kinds `:white`, `:pink`, `:table`, `:table` |
| `OCTOPUS_NOISE_SCALE` | 2 | effective `phase_rms=`/`strength_rel_rms=`; the recorded series | `scale=2.0 phase_rms=4.0e-5 strength_rel_rms=0.0006`; every series == 4.0e-5 (6.0e-4) x `octopus_normal(seed, philox, turn, rng_id, 0, 1024 + slot)` bitwise, 8 slots |
| `OCTOPUS_PHASE_RMS` | 2e-5 | as above | as above |
| `OCTOPUS_STRENGTH_REL_RMS` | 3e-4; 0 (probeD2) | as above; 0 -> no strength slot | 6.0e-4 bitwise; probeD2 records 4 slots, `strength_rel_rms=0.0` |
| `OCTOPUS_PINK_OCTAVES` | 8 at 16 turns | nowhere but the series (not in the line, not in the provenance) | all 8 series == the K = 8 Voss-McCartney reconstruction bitwise; the K = 16 reconstruction differs |
| `OCTOPUS_TABLE_SEED` | 7 at 4 turns | provenance digest + series (the line prints `table_seed = 7` as echo) | all 8 series == `sigma .* randn(Xoshiro(rand(Xoshiro(7), UInt64)), 4)` in slot order bitwise, digests == FNV-1a; differ from seed 20261014 |
| `OCTOPUS_TABLE_FILE` | a 5-row TSV, phase columns + one unused strength column, 3 turns | `table_file=`; provenance `name` == column label, `length` 5, `digest` == FNV-1a of the whole column, series == the first 3 rows | all true; "table_file column "tccb_strength_noise_1" is unused" printed |
| `OCTOPUS_KBB_SCALE` | 0.5 (probeA); 0 (effect) | echo only (U7-3); effect: moments and luminosity | 27 of 28 columns and the luminosity (1.1e-2 rel) differ from `kbb 1` |
| `OCTOPUS_RADIATION` | 0 | echo + case name `_norad`; effect: none | bitwise identical to `radiation=1` (U7-1) |
| `OCTOPUS_CHROMATICITY` | 1.5,0.5; 0,0 (effect) | echo only (U7-3); effect | `chrom=1.5,0.5`; 27 columns differ from `2,2` |
| `OCTOPUS_SEED` | 42 | the artifact path `/42/`; the series keyed on 42 | bitwise (above) |
| `OCTOPUS_RESULT_DIR`, `OCTOPUS_CASE_NAME` | scratch dir, `probeA_case` | `artifact=` | `.../probeA/42/probeA_case.h5` |
| `OCTOPUS_MOMENT_STEP` | 2 at 5 turns | the moments' `turn` column (not in the line; the driver asserts the row count) | `[0, 2, 4]`, luminosity 5 rows |
| `OCTOPUS_USE_MPI`, `OCTOPUS_RANKS` | 1, 2 | `ranks=` from the `:multi_process_communicator` receipt, checked against `MPI.Comm_size` | `ranks=2 threads=4` |
| `OCTOPUS_CPU_THREADS` | 8 | `threads=` from `configuration_report(policy)` (checked against the communicator receipt under MPI) | `threads=8` |
| `OCTOPUS_USE_GPU` | 1 | `threads=NA`; receipt `backend = CUDABackend` | both |
| `OCTOPUS_CUDA_DEVICE` | 0 | nowhere (U7-4) | - |
| `OCTOPUS_RECORD_TURN_TIMES` | 1 at 5 turns; 1 at 25 turns (driver) | the `turn_timings_seconds` line; `steady_ms_per_turn=NA` below 21 turns | 5 turns: NA and said so; 25 turns: 2.3698530000000004 == the driver's median of the file's `max_over_ranks_seconds` column |
| `OCTOPUS_TURN_TIMING_PATH` | absolute path | `turn_timing_path = ` line; the TSV | header `turn seconds max_over_ranks_seconds` + 5 rows |
| `OCTOPUS_RECORD_TURN_MODULATION` | 0 | `record=false`, no `rms_*` fields, every slot `series === nothing`, the "none recorded" line | all true; with 1 (default): 8 `rms_*` fields each == the rms of the recorded series |
| `OCTOPUS_SPECTRUM`, `OCTOPUS_BAND`, `OCTOPUS_SPECTRAL_AMPLITUDES` | flat, 0.1,0.4, rayleigh at 64 turns | `spectrum=flat band=0.1,0.4 amplitudes=rayleigh`; the canonical names (`seed=123456789`, `rng_id=11..25`, `slot=1,2,4,5`, `amplitudes=rayleigh`); series == `spectral_turn_table(:flat, sigma, (0.1,0.4); turns=64, seed, rng_id, slot, amplitudes=:rayleigh)` bitwise and != the fixed table | all true, 8 slots; "K = 19 bins" printed |

### (ii) The `CRAB-NOISE` parsers

One line per run (12 lines: the four rules, CUDA, MPI, probes A-E, D2) through the driver's `crab_line` (regex `(\S+?)=(\S+)` on the first `^CRAB-NOISE ` match) and the validation's `parse_receipt_line` (last `CRAB-NOISE ` line, whitespace split, `split(tok, "="; limit = 2)`), both copied verbatim into `U7/probe_records.jl`: the two dictionaries are equal on every line and hold exactly one entry per token (34 with the record on, 26 with it off, 30 for the phase-only file table); every token's key and value round-trip. The trailing fields (`record=`, eight `rms_*`, `spectrum=`, `band=1.52587890625e-5,0.5`, `amplitudes=`) parse as single tokens because none contains whitespace. The validation's `startswith(l, "CRAB-NOISE ")` does not catch `CRAB-NOISE-RULES`/`-REPORT` lines (no space after NOISE). Clean.

### (iii) Stream ids

From the provenance of the four runs: white and pink, tccb `11, 12, 14, 15` and tcca `21, 22, 24, 25` (`10 + slot`, `20 + slot`, slot `i` for phase i and `3 + i` for strength i; the beam holds 1, the radiation element 2); table: eight distinct digests, no id; spectral: the canonical names carry `rng_id` 11, 12, 14, 15, 21, 22, 24, 25 with `slot` 1, 2, 4, 5, the provenance `rng_id` attribute 0 (U7-7). No two slots of different cavities share an id under white, pink or spectral; the shared-id warning (`_warn_duplicate_turn_modulation_streams`) fires at `TrackingTask` construction for two cavities sharing `rng_id = 77` under both `WhiteNoise` and `SpectralNoise` (captured with a `TestLogger`: "multiple turn-modulation rules on different elements share an rng_id ...") and not for 78/79; one `rng_id` on two spectral slots of ONE cavity resolves to two different tables (the slot is in the key). None of the four shipped runs' logs carries a shared-id or equal-digest warning. The one coincidence found is the degenerate 2-turn spectral table of U7-2, which no warning covers.

### (iv) The benchmark driver

`child_env` strips every `OCTOPUS_*` and sets the arm's switches; the child's `CRAB-NOISE` line in the dry run reads `record=true` with eight `rms_*` fields, so every arm records (8 B per slot per turn). The digest is SHA-256 over `/moments/<name>/data`, `/luminosity/strong_beam_1/turns` and `/values` read with HDF5.jl; the timing statistics come from the timing file; neither depends on the line. The line is used for the asserted keys (`rule, scale, radiation, turns, n_macro, seed, ranks, threads`), `steady_ms_per_turn` (cross-checked against the driver's own median of the same column: `reldiff <= 1e-9`; the harness's `(a + b)/2` median equals `Statistics.median` bitwise on 2000 random series, `U7/probe_arith.out`) and `eps_x_last`/`eps_y_last`/`lumi_mean` (bit-for-bit against the driver's reading of the artifact). The dry run (`arms=threads:4,mpi:2x4,cuda`, N = 1000, 25 turns, skip 20) ran every parsing path: three rows written, `harness_steady_ms_per_turn` 2.3698530000000004 / 1.305101 / 0.499048 against the driver's medians 2.3699 / 1.3051 / 0.4990, moment rows 25 == `length(0:1:24)`, MPI luminosity series bitwise with the moments' worst column `m000010` at 7.89e-13 scaled, CUDA emittances and luminosity at 8.2e-16; the second invocation resumed ("skip ... row exists" x3) and reprinted the table. The 2026-10-14 record states the fixed case as the driver still runs it (white, scale 1, radiation off, seed 123456789, 2000 turns, moments every turn, package load) and quotes timings and relative identity verdicts only, no digest or emittance values, so nothing in it is checkably stale; it predates both the relative strength semantics (2026-10-15) and the recording default, so a re-run today reproduces its timings approximately and not its outputs, which it does not quote. Its radiation sentence shares U7-1.

### (v) Header claims against code and runs

- Validation header 32-33 and `validation/README.md` 436-437: "about two and a half minutes after the Octopus load, the three spectral cases included": measured 2 min 17 s wall including the 27 s package load (16 threads, 354 % CPU), about 1 min 50 s after the load. Consistent.
- Check counts: the frozen records say 147 (2026-10-14) and 157 (2026-10-15); the run gives 273 = 157 + 9 (`recorded`: 1 + 2 x 2 per rule... 3 rules) + 107 (`spectral`: 33 + 33 + 41). No living document states a count. Consistent.
- Harness 232-238: "10 % is a 5-sigma band from T = 1250 on" (5/sqrt(2500) = 0.100), "at the suite's 2 turns a bare 10 % pin would fail 85 % of the time": analytic 1 - (e^-0.81 - e^-1.21) = 0.853, Monte Carlo 0.853. Correct.
- Harness 170-173: "3e-3,4e-3 holds its first bin from 250 turns and 32 bins from 32000": first bin from N = 250 exactly; 32 bins from N = 31000 (32000 gives 33). Approximately right.
- Validation 233-234: K = 66 at N = 65536 for (3e-3, 4e-3) and 32765 for (2^-14, 1/2) with the Nyquist bin: both reproduced (`noise_part.log`: "K = 66 bins (k = 197..262)", "K = 32765 bins (k = 4..32768), Nyquist bin in the band: true").
- Example 785, harness 260, validation 75: "7.65 % at K = 16, N = 65536": the formula gives 7.654 % (the construction's Monte Carlo 7.30 %; U7-6).
- Validation 70-71 and README 445: "3 sqrt(1/(2N)) = 0.83 % at 65536": 0.8286 %. Correct.
- Example 119, 313: "8 bytes per active slot per turn (64 MB per million turns for eight slots)": 8 x 8 x 1e6 = 64 MB. Correct.
- Harness 252: Rayleigh "1 +- 1/(2 sqrt(K))": Monte Carlo sd of rms/sigma for K = 19, 66, 1000 flat bins 0.1146, 0.0615, 0.0158 against 0.1147, 0.0615, 0.0158; the factory's own tables over 200 ids at K = 66: sd 0.0623. Correct.
- Example 130-131 "1 within +-1/sqrt(2 turns), one sigma": the band covers 67.3 % at T = 2 (exact), 68.3 % from T = 1250. Correct to the stated one sigma.
- Strength semantics in all four headers, the README and the catalogue: relative, `S (1 + d)`, `strengthY` stays 0; the validation's `exact` item passes under it (273/273) and the example's provenance prints `strengthY=0.0` nominal. Consistent, except README:457 (U7-5).
- The record default: the example's `record_turn_modulation = true` and the harness's `OCTOPUS_RECORD_TURN_MODULATION` default 1 both hold (`record=true` in every default line; the series present).
- `docs/public_api.md` 283-300 and the catalogue entry: every claim (one switch, independent streams, the receipt, the provenance, the recorded series and their rms, MPI and CUDA arms, the benchmark record, the harness toggle's refusals) matched by the runs.
- The MPI "ranks x threads" command lines of both headers run as written (package mode; MPICH_jll).

### (vi) The example's printed rms table

`example/default.log` (CUDA, white): header line "white and table rows: ratio = 1 within +-0.5 (one sigma, 1/sqrt(2 turns) at 2 turns)", eight rows, ratios 0.21 to 0.84, each tagged "1 +- 0.5 (1 sigma)". `pink.log`: eight rows "no pin (band-limited sum)", ratios 0.42 to 1.43. `table.log`: "1 +- 0.5 (1 sigma)", ratios 0.17 to 1.38 (the synthetic white record over 2 turns; two values of 2 fall outside the one-sigma band, as 1/3 should). `spectral.log` (table_turns 2^20, 2 turns): "no pin (partial period: 2 of 1048576 table turns)", ratios 0.16 to 2.08. `spectral64.log` (turns = table_turns = 64, band (1/16, 1/2), 28 bins): "1 exactly up to rounding (analytic normalisation over the whole period)", every ratio printed 1.0. The arithmetic: at T = 2 the band `1 +- 0.5` is the one-sigma of `sqrt(Exp(1))` (coverage 0.673); the whole-period rms of a fixed-amplitude table equals sigma to 0, 2.2e-16 and -1.3e-15 at N = 64, 4096, 2^20 while the first two entries of the 2^20 table have rms/sigma 0.16 (`probe_arith.out`). The example's `band_text` chooses the row text by `cn.rule`, `cn.amplitudes` and `length(series) == cn.table_turns`, which the five runs exercised on all branches but the Rayleigh one (covered by the harness's probeE text "no pin: sigma is the expected rms; one sigma 1/(2 sqrt(K)) = 0.1147 for a flat band of K = 19 bins"). Clean.

### (vii) The `tablefile` part and the `recorded`/`spectral` tolerances

`tablefile` realises `WhiteNoise` rules through the pure hook and writes `sigma * n` as `repr` (header 250-261 describes exactly that; it is not a spectral producer and does not claim to be). Fed back: `tablefile path=W1_8.tsv turns=8` then the harness `rule=white` (phase only, 8 turns, 4096 macroparticles) and `rule=table OCTOPUS_TABLE_FILE=W1_8.tsv`: 28 moment columns, the luminosity series and all four recorded series bitwise equal between the white and the table-fed runs; each table slot's digest equals the FNV-1a of its file column and the part printed the same digests (`4f1ad71fe6cff4bd` etc.). The `recorded` item is bitwise (no tolerance; measured true on all 6 element-rule pairs at 65536 turns). The `spectral` item's tolerances against their derivations and the measured margins: fixed amplitudes, periodogram ratio within 1e-10 (measured 4.4e-16 to 8.9e-16 flat, 1.3e-14 to 2.0e-14 pink over 32765 bins), rms within 1e-12 (measured 0 to 2.2e-16 flat, -1.2e-15 pink), out-of-band below 1e-12 of the peak (measured 1.6e-33 to 4.0e-32); Rayleigh, band mean within 5/sqrt(K) = 0.6155 (measured 0.80 to 1.14, i.e. 1.6 sigma at worst against a 5-sigma pin), variance >= 0.1 (measured 0.62 to 1.52 against the expected 1 +- 0.35), rms within 5/(2 sqrt(K)) = 0.3077 (measured 0.896 to 1.066). The derivations hold (a mean of K exponentials has sd 1/sqrt(K); the rms half of it); the pins are five-sigma, loose but not vacuous given the variance floor. Clean.

## Clean list (what was compared, what was measured)

- The four rules at the suite default, CUDA and two MPI ranks: every run exit 0; the eight recorded series bitwise identical across CPU, CUDA and MPI (host-side rules); the luminosity series CPU == MPI bitwise, CPU vs CUDA 3.9e-16; the eight `rms_*` fields equal the rms of the recorded series.
- Both parsers agree on 12 lines, field by field.
- Every toggle but `OCTOPUS_RADIATION` (U7-1) and `OCTOPUS_CUDA_DEVICE` (U7-4) shows a recorded or bitwise-reconstructable trace; `kbb_scale` and `chrom` are echoes that demonstrably act (U7-3).
- Stream ids disjoint between cavities under every rule; the shared-id warning fires for shared ids on white and spectral rules and stays silent for distinct ids and for the shipped configurations.
- The driver's dry run and resume; its asserted keys; the harness/driver steady agreement; `record=true` in every arm.
- Validation part `noise`: 273 of 273, 2 min 17 s wall; the spectral and recorded items' margins above.
- `tablefile` -> `OCTOPUS_TABLE_FILE`: bitwise identity with the white run at 8 turns.
- The example at its default and per rule: the printed bands as documented; the `spectral64` exact row.
- Every numeric header claim checked above reproduces (85 %, 1250, 0.83 %, 7.65 % as the formula, 66 and 32765 bins, 250 and ~31000 turns, 64 MB, 1/(2 sqrt K)).

## Not checked, and why

- The production benchmark (N = 1e5/1e6, 2000 turns, six arms) was not re-run; only the dry run at N = 1000, 25 turns.
- Parts `pilot`, `sweep`, `report` and `control` (GPU-hours) were not run; `tablefile` was run at 8 turns only.
- The driver's `load=include` mode and the harness in script mode (`julia test/examples/crab_cavity_noise.jl`, which compiles Octopus from source, ~170 s) were not run; every run used package mode. The suite's launcher testset covers script mode under MPI.
- The Rayleigh `K < 8` counted-FAIL path, `Float32` lines, the `f_rev` (hertz) band form and a custom `"label" => S` spectrum were not exercised (the harness offers presets only).
- The harness refusals (`OCTOPUS_MP`, `OCTOPUS_RANKS` without MPI, the spectral variables under another rule, GPU with MPI, timing path without the instrument) were read, not executed; the 2026-10-14 record says each was exercised then.
- The GPU was shared with a process holding 11.9 GB throughout (0 % utilisation before and after each CUDA run); no timing here is a measurement.
