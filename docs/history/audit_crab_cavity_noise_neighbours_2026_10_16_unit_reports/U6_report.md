# U6 — Phase 9 test-quality reading unit, crab-cavity-noise campaign (2026-10-16)

Reading unit of the comprehensive audit protocol (`docs/comprehensive_audit.md`,
Phase 9; Measured Lessons 1, 5, 11; `docs/design/testing_lanes.md` section 3).
Every claim below is a LEAD, not a finding. The unit modified no repository
file; every probe script lives under
`result/audit_crab_noise_2026_10_16/U6/` (git-ignored scratch).

## Region and provenance

Repository: Octopus, main checkout `/cfs/ad/dxu/Library/Julia/Octopus` at
`3126908` (clean but for the auditor's untracked
`docs/history/audit_crab_cavity_noise_neighbours_2026_10_16.md`). Host
acnlinj4 (128 cores, RTX 4500 Ada, julia 1.12.4, CUDA active, MPI 0.20.26 in
the user's default environment, launcher
`~/.julia/artifacts/8bd6…/bin/mpiexec`).

READ, every line (diff `6995151..3126908 -- test/runtests.jl`, 2133 patch
lines, saved as `U6/runtests_diff.patch`, plus the current text of every
testset named in the brief, by line range):

| testset (current lines) | campaign change | lane |
|---|---|---|
| Turn modulation: effectiveness at the kernel boundary, chunking and repositioning (8052–8268) | unchanged, read in full | both |
| Turn modulation: rules, wrapper and the pure hook (9940–10622) | mixed-shape allocation pins with a recorder sink; relative strength pins; the fourth rule in the catalogue tripwires; `_realize_draws`/`_slot_nominals` container tripwires; the (k) draws/nominals checks | both |
| Spectral turn table: exact spectrum, rms, phases and refusals (10740–11271) | new | both |
| Spectral turn table: the producer through the consumer and the recorder (11272–11576) | new | both (CUDA arms gated, `@test_skip`) |
| Turn modulation: the RF cavity by the same wrap (11794–12210) | relative strength pins | both (its effectiveness-contract part skips loudly in the fast lane, 12208) |
| Every example script runs against the current interface (15690–15805) | derived script set, derived cleanup, harness `OCTOPUS_RESULT_DIR` | full only |
| The run artifact records turn-modulation provenance (16533–16743) | unchanged, read in full | both |
| The run artifact records the realised turn modulation (16745–17315) | new | both (CUDA arm gated) |
| Turn modulation: the one-particle probe verifies the loop per harmonic (17316–17517) + `test/turn_modulation_probe.jl` (543 lines) | new | CPU+CUDA arms both lanes; the two-rank arm full only (17445) |
| Turn modulation: the strong-strong window and receipt (17519–17601) | unchanged, read in full | both |
| The developer harnesses run divided under an MPI launcher (20129–20258) | derived harness set | full only |
| Turn modulation: CPU/CUDA identity and the device conversion (22923–23117) | unchanged, read in full | both |

EXECUTED (stage runner `result/gates/turnmod/stage3_run_testsets.jl`, package
mode on the main checkout, 4 threads, preamble
`result/crab_noise/S1B/stage3_preamble.jl` or a U6 preamble that includes it
and then monkey-patches ONE Octopus method through `Octopus.eval`; cwd
`test/`). Logs in `U6/*.log`.

| run | preamble | result |
|---|---|---|
| baseline | S1B | producer 382/382 (38.5 s), consumer 98/98 (28.5 s), realised 268/268 (30.0 s), probe 376/376 (50.4 s): the gate's counts, reproduced |
| gate closed | `preamble_gate_closed.jl` (`_lane_gate` returns false) | probe 333/333: the two-rank arm is 43 assertions |
| injection A | `_spectral_bin_frequency(k, N, scale) = (k+1)/N` | producer 373 pass / 9 FAIL |
| injection B | `_resolve_turn_rule(::SpectralNoise, slot, T)` drops the slot (the recorded F1 pre-fix defect) | consumer 73 / 25 FAIL |
| injection C | `_record_turn_draws!` writes the first active slot into every column | realised 243 / 25 FAIL; rules 535 / 1 FAIL (the two-active-slot mixed shape) |
| injection D | `_realize_draws(::CrabCavityNoise)` additive `S + d` (the superseded semantics) | probe 313 / 63 FAIL (CPU 4/4 FAIL, CUDA 4/4 FAIL); rules 516 / 20 FAIL |
| injection E | `_turn_offset(::WhiteNoise)` keyed on `slot + 1` | probe CPU arm 4/4 PASS, CUDA arm 4/4 PASS; realised 268/268 GREEN; rules 512 / 24 FAIL (`draw` pins); kernel-boundary 50 / 7 FAIL (`phase_at` pins). The probe's 14 failures are all in its two-rank arm and are an artefact of the method: the mpiexec child runs unpatched code and disagrees with the patched parent |
| standalone child, default load path | `mpiexec -n 2 julia --threads=2 test/turn_modulation_probe.jl`, `JULIA_PROJECT=<repo>`, `OCTOPUS_TM_PROBE_DIR` set, no CPU reference | `TM-PROBE-DONE … pass=4/4 coverage=true verdict=PASS`, 36 s, MPI from `~/.julia/environments/v1.12` |
| standalone child, Pkg.test-shaped load path `@:<repo>/test` with `JULIA_PROJECT=<repo>` | same | `Package Printf not found in current path`, exit 1 |
| `measure_check1.jl` | — | the residuals behind the producer's check-1 pins (LEAD U6-5) |

Reproduce any row with

    cd /cfs/ad/dxu/Library/Julia/Octopus/test && env STAGE3_PREAMBLE=<preamble> U6_BASE_PREAMBLE=/cfs/ad/dxu/Library/Julia/Octopus/result/crab_noise/S1B/stage3_preamble.jl \
      julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/gates/turnmod/stage3_run_testsets.jl "<testset title>" ...

## Leads

### LEAD U6-1 [low, confidence high] test/runtests.jl:16875
Claim: The two testsets the campaign names as the recording option's verification ("The run artifact records the realised turn modulation" and the one-particle probe) have no anchor for a LIVE rule's draw other than the hook's own function, so a wrong draw (wrong stream cell, wrong sigma) passes both; the anchors live in two other testsets.
Mechanism: `replay(rule, slot, turns)` (16784) and `tm_probe_replay` (probe 228–245) call `Octopus._turn_offset`, the same method `_slot_draws` → `_realize_draws` → the hook call; `realize` is the projection of `_realize_draws` (crab_cavity.jl 351). So `series == replay(...)` (16875–16877, 16984–16985, 17002, 17060, 17104), `realised.phase[i] === nominal + series[i]` (16883–16886) and the probe's `series_eq_replay` compare one function with itself; the probe's comparison 3 then proves the kernel consumed exactly the recorded values (an independent check of record → kernel, not of the draw). The only draw-independent anchor in the realised-record testset is the table slot (`series == table.offsets[1:5]`, 16878; `[5:8]`, 16985). The counter-RNG anchors are `draw(...)` in the rules testset (9960, 10212–10228) and `phase_at` in the kernel-boundary testset (8085–8094).
Repro: injection E (`U6/preamble_inject_E_slotkey.jl`) on the four testsets: realised 268/268 GREEN and probe CPU/CUDA verdicts 8× PASS (blind), rules 24 FAIL and kernel-boundary 7 FAIL (`isapprox(mean_px, expected_px)`: 1.83e-6 vs 2.72e-6). A one-line fix in the realised testset — one pin per live slot against `1e-2 * octopus_normal(0x5eed, method, t, 7, 0, _RULE_COMPONENT_BASE + 1)` — would make it see the defect; alternatively `tm_probe_replay` could form white/pink draws from `octopus_normal` directly rather than through `_turn_offset`.

### LEAD U6-2 [low, confidence high] test/runtests.jl:17448
Claim: Every MPI arm of the suite (probe 17454/17482, seam 19402/19413, harnesses 20182/20229) degrades to `@test_broken false`, which `Pkg.test` does not count as a failure, and all three reach the launcher only through `MPICH_jll.mpiexec(exe -> exe)`, a form MPICH_jll already deprecates; the day that method disappears the three arms turn Broken together and the gate stays green.
Mechanism: `try MPICH_jll.mpiexec(exe -> exe) catch err; @info ...; nothing end` → `launcher === nothing` → `@test_broken false`. The same branch is taken when a child dies or hangs (30-minute watchdog, 17470) before writing any `TM-PROBE` receipt (`!success(proc) && !ran`, 17480). Visible in the summary row's Broken column, but the campaign's gate records quote pass/total only, so a reader must know to look. Not a current defect: both c3c6c2c gate logs show no Broken row and the probe's 376 = 333 + 43 says the two-rank arm ran in both arms.
Repro: `grep -n "mpiexec() is deprecated" /cfs/ad/dxu/Library/Julia/Octopus/result/gates/turnmod/full_gate_native_c3c6c2c.log` → line 1093 (avx2 log line 1088); `grep -c Broken` on either log → 0. Suggested follow-up: move to `MPICH_jll.mpiexec()` (the non-do-block form) and have the gate record state the Broken count.

### LEAD U6-3 [low, confidence high] test/runtests.jl:17464
Claim: The probe child's `JULIA_LOAD_PATH` is the parent's expanded `Base.load_path()`, unlike the sibling MPI sections' `"@:@stdlib"`, so the stage runner exercises the two-rank arm against the user's default-environment MPI, a configuration the gate never runs, and the standalone form the probe's header describes works only through that default environment.
Mechanism: under `Pkg.test` the load path is `@:<repo>/test` (Pkg `Operations.jl` 2452), which `Base.load_path()` expands to `["<sandbox>/Project.toml", "<repo>/test"]` (emulated: `["…/Octopus/Project.toml", "…/Octopus/test"]`), no `@stdlib`; the child's `import Random, Printf` and `using Octopus, MPI` resolve through the sandbox project's deps (Octopus deps + the test target), so the gate is unaffected. In package mode `Base.load_path()` is `[<repo>/Project.toml, ~/.julia/environments/v1.12/Project.toml, <stdlib>]`, so `using MPI` in the child binds whatever MPI the default environment holds (0.20.26 here). A stdlib-only import added to the probe later would pass in the stage runner and fail under `Pkg.test` (the "passes alone, fails in the suite" class, Lesson 11).
Repro: `env JULIA_LOAD_PATH="@:/cfs/ad/dxu/Library/Julia/Octopus/test" julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'println(Base.load_path())'`; the standalone runs in `U6/standalone_default.log` (PASS 4/4, 36 s) and `U6/standalone_gateshaped.log` (`Package Printf not found`).

### LEAD U6-4 [low, confidence high] test/runtests.jl:16985
Claim: `series[5:6] ∪ replay(..., 6:7)` uses set union where concatenation was meant; a repeated value would shrink the right-hand side and fail the pin spuriously.
Mechanism: `∪` is `union`, which removes duplicates and returns a Vector; equality with the 4-entry series holds only while the four draws are distinct (astronomically likely for Float64 normals, so the pin passes, but the operator does not express the intent and the comparison is not the stated one).
Repro: `grep -n "∪" test/runtests.jl` → 16985 only; replace with `vcat`.

### LEAD U6-5 [information, confidence high] test/runtests.jl:10830
Claim: The producer's check-1 pins (rms 1e-12, periodogram 1e-10, out-of-band and DC 1e-12) are stated but the comment quotes a measured value only for the mean; the envelope is four or more orders and should be on the record.
Mechanism: measured on the testset's own tables (`U6/measure_check1.jl`): flat `rms_rel` 2.2e-16, `periodogram_rel` 8.9e-16, `outside_over_peak` 6.6e-32, `dc_over_peak` 1.5e-33; pink `rms_rel` −1.2e-15, `periodogram_rel` 1.5e-14, `outside_over_peak` 3.4e-33, `dc_over_peak` 5.0e-35. The `@testset let` context carries these numbers only on failure. Lesson 5 asks that a pin state the regime it was measured in.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus /cfs/ad/dxu/Library/Julia/Octopus/result/audit_crab_noise_2026_10_16/U6/measure_check1.jl`.

### LEAD U6-6 [low, confidence medium] test/runtests.jl:20244
Claim: The MPI harness testset's `seed_dir = joinpath(outdir, "123456789")` hand-copies every harness's default seed (AGENTS.md: derive, do not copy), while the harness set itself is now derived.
Mechanism: all three harnesses default to `OCTOPUS_SEED = 123456789` today (the crab harness header, test/examples/crab_cavity_noise.jl:196), so the pin passes; a harness that changes its default fails `isdir(seed_dir) && length(readdir(seed_dir)) == 1` without a message naming the seed. Deriving it (`readdir(outdir)` must be exactly one all-digit directory holding one file) removes the copy.
Repro: `grep -n '"123456789"' test/runtests.jl` → 20244; `grep -n "123456789" test/examples/*.jl`.

### LEAD U6-7 [low, confidence high] docs/history/turn_modulation_record_2026_10_15.md:177
Claim: Several of the campaign's pins have no recorded defect-targeted negative control; their only "red" is the feature-absent red of the pre-change source (FieldError/MethodError), which proves the test ran, not that it discriminates.
Mechanism: the record (lines 177–181) documents "11 passed, 1 failed, 6 errored, then aborted" on the pre-change source for the realised-record testset, and phase A/B both green for the probe (section 2.2); the spectral record (lines 353–358, 481–485) says explicitly that the new testsets were not run on the pre-change source, the mirrored in-test controls standing in. Defect-targeted reds ARE recorded for F1 (allocation, 6 failures), spectral F1 (equal digests, correlation 1.0) and F2 ("1 == 3"). The inventory below lists each pin family WITH or WITHOUT a control, and which U6 injection now supplies one.
Repro: the five injection logs in `U6/`; the inventory table in this report.

## Pin inventory: negative controls (Phase 9 rule)

| pin family | where | control recorded by the campaign | U6 measurement |
|---|---|---|---|
| relative strength semantics `S(1+d)`, `V(1+d)`, `S_Y=0` stays 0 | rules (e) 10212–10243, RF (b) 11874–11890, white/pink (h) 11777–11782, record (c) 16885–16886 | WITH: the superseded additive pin asserted false in-test | injection D: rules 20 FAIL, probe 8/8 FAIL (`py_const`, `within`) |
| mixed-shape zero-allocation on both hooks + sink met every element | rules (d) 10044–10099 | WITH: red on the unfixed tree (6 allocation pins, record F1) | injection C: the sink pin red on the two-active-slot shape |
| catalogue/kind/container tripwires with `SpectralNoise` | rules (i)–(k) 10400–10621 | structural tripwires; `SpectralNoise` added as the fourth rule | not injected (derived sets, both directions pinned) |
| spectral check 1 (rms, periodogram, out-of-band, DC, mean) | producer (b) 10810–10850 | WITH (in-test): pink vs flat and flat vs pink > 0.5 (d) | injection A: 4 periodogram pins red (0.18, 0.34, 9.8e-3), Rayleigh `mean_ratio` red, `fixed_var_ratio` 7.8e-4 red |
| check 2 slope and harmonic-sum expectation | producer (c) | WITH (in-test): flat slope +1, brown −1.017, each > 50× tolerance | injection A: `abs(slope − expected)` 0.016 red, brown control red |
| check 3 owner's generator, phase keying | producer (e) | WITH (in-test): shifted-phase control fails by > 0.1 | not injected |
| check 4 reproducibility, independence, names as text, `f_rev`, `Float32`, `sigma=0`, `slot` | producer (f) | WITH for `slot` (F1 red log); names pinned as text, no digest values | injection B (consumer side) |
| Rayleigh amplitudes | producer (g) | WITH (in-test): exact-periodogram pin missed by > 5e9× | injection A: `mean_ratio` red |
| refusals by message (31 factory + 13 rule), few-bins warning, F2 maxlog | producer (i), (j) | WITH for F2 ("1 == 3" red log); refusals: message pins | not injected |
| equal-digest and shared-stream warnings | producer (h), consumer (e) | `@test_logs` with specific patterns; silent cases asserted with pattern-less `@test_logs` | not injected |
| provenance of a spectral table; recorded series == table bitwise; window refusal | consumer (a), (b) | WITHOUT a recorded red (feature absent at landing) | injection C hits the recorder, not this path; the `series .=== tab7.offsets` pin is the one table-anchored record check |
| `SpectralNoise` resolves at compile, keyed on the slot | consumer (c), (d), (f) | WITH: F1 red log (equal digests, correlation 1.0) | injection B: 25 FAIL, the recorded disease reproduced |
| record off by default, file layout, nominals, TOC | realised (a), (b) | WITHOUT (feature-absent red only) | not injected |
| recorded columns == hook's draws; realised == nominal ∘ series | realised (c) | WITHOUT; and circular for live rules (LEAD U6-1) | injection C: 25 FAIL (seen); injection E: 268/268 GREEN (blind) |
| no side effect on moments/ledger; receipt identical | realised (d), (g) | WITHOUT | not injected |
| invalid refused by name; schema; inactive | realised (e) | WITHOUT (the `@test_throws` family) | not injected |
| chunking, repositioning, RF cavity, strong-strong both/one beam | realised (f), (h), (i) | WITHOUT (one-beam case: F4 "behaviour probed correct") | injection C: (f) and (h) pins red |
| short series warning, torn series, reserved `state`, pre-nominal files | realised, after (i) | WITHOUT a recorded red for F2 (the pre-fix reader was silent; `@test_logs (:warn, …)` would have failed on it, but no run is recorded) | not injected |
| recorder protocol on a hand-built recorder | realised, after (i) | WITHOUT | injection C: 3 pins red |
| `prepare_run_artifact!` column/provenance disagreement | realised, after (i) | F4 (test gap filled) | not injected |
| probe C1 (on vs off), C2 (consumed), C3 (prediction from the record) | probe + helper | WITHOUT (phase A 24/24 and phase B 376/376, both green; no red recorded) | injection D: C3 and `py_const` red on CPU and CUDA; injection E: C1–C3 all PASS (blind to a wrong draw, LEAD U6-1) |
| probe cross-backend: series bitwise, rows bitwise (MPI) / ≤ 1e-17 (CUDA) | probe (b), (c) | WITHOUT | injections D/E show the arm detects a parent/child disagreement (artefact here, but a working comparison) |
| example runner: derived catalogue, floors, derived cleanup, harness redirect read | example testset | tripwires with `@info` names; floors ≥ 5 / ≥ 3 | gate rows 21/21 = 2 + 2 + 5 + 1 + 3 + 1 + 1 + 3×2 (5 examples, 3 harnesses, 3 recorded artifacts on disk) |
| MPI harness testset: derived harness set, `xor(reads, refuses)` tripwire | 20161–20174 | tripwire | gate rows 10/10 = 3 + 1 + 3×2 |

## Clean (with the evidence that makes it checkable)

- Hypothesis 2, silent skips: every CUDA gate inside the region has a loud `else` — 11391→11400, 11477→11479 (`@test_skip` then `continue`), 12136→12176, 17282→17310, 17427→17435, 22963→23115; the Adapt gate 10252→10255; the RF effectiveness-contract part 12208. The sweep `awk` over the region's line ranges for `functional()|CUDA_TESTS_ACTIVE|_HAS_ADAPT|_HAS_CUDA` lists exactly these plus 22960 (`if _HAS_CUDA`, a host-side method-ownership check with no device dependence; CUDA is a hard dep). The probe's `@isdefined(_lane_gate) ? … : true` (17445) opens the arm in an extracted run; without the preamble `MPICH_jll` is undefined and the `try` turns the `UndefVarError` into `@test_broken` — visible. `@test_logs` patterns are specific (`r"only 2 bin"`, `r"only 31 bin"`, `r"same digest"`, `r"share an rng_id"`, the exact short-series regex at 17132); silence is asserted with pattern-less `@test_logs`, which fails on any log; the few-bins warning's kwargs and the digest warning's kwargs are pinned after capture (11109–11110, 11176–11178).
- Hypothesis 3, pins across machines: no digest VALUE is pinned anywhere in the suite (`grep "digest == 0x\|digest == [0-9]"` → only the `digest == 0` sentinels of live rules at 11769 and 12102); canonical names are pinned as text with `repr`-stable floats. Stated tolerances and their arguments: CUDA probe pin one state ulp plus 1e-14 of Σ|kick| (argued at 17333–17341, measured 2.0e-16; the `px_ulp = 512` on H1 in the gate log is a near-zero-crossing artefact of the ulp metric, which the excess metric is designed to ignore); CUDA rows ≤ 1e-17 absolute inherited from the identity testset's header (20× headroom at 1e-3 coordinates; the probe's moving coordinates px, pz are ≤ 5e-4, eps ≤ 1.1e-19); Rayleigh bounds 5/√K, 5√(8/K), 5/(2√K_eff), kurtosis 0.15, correlation 4/√(2K_eff) and 4/√K_eff, all derived in the testset header and deterministic under fixed seeds; the measured fixture pins (`-6.5957e-3` atol 5e-7, the RF `offsets` atol 5e-7, `pz_means` rtol 1e-6) survived both the native and the Haswell/OpenBLAS gate arms.
- Hypothesis 4, "correct check, never executed": both c3c6c2c gate logs carry a row for every region testset with equal counts (native lines 505–846, avx2 511–852): effectiveness 57, rules 536, slot bounds 26, producer 382, consumer 98, white/pink 45, RF 147, examples 21 (10m56 / 10m40), provenance 127, realised 268, probe 376, ss window 20, MPI seam 1710, MPI harnesses 10, identity 39. No `LANE SKIP`, `Broken`, `NOT exercised` or `@test_skip` line in either log. The probe's two-rank arm = 43 assertions (376 − 333 measured with the gate closed), so it ran in both arms; the eight `TM-PROBE` lines in each log carry the CPU and CUDA verdicts (the mpi2 lines go to the per-rank receipt files by design). Fast-lane membership: everything in the region runs in the fast lane except the example testset, the two MPI sections and the probe's two-rank arm, each announced by `_lane_gate` and listed in the final banner (runtests.jl 28326–28328).
- Hypothesis 5, test-side global state: every region testset that draws sets `set_global_rng!` before use (the suite's convention; the probe leaves the seed at the ALL verification's and the next testset sets 5 first); the rng-id counter is only ever raised (explicit claims at 10119–10124, 11233–11256, 11525–11526, 11553–11566) and `reset_rng_id_counter!` is called nowhere in test/ (grep), so claims cannot collide; all id assertions are relative (review F3). Temp files: `tempname()` artifacts removed at testset end, `mktempdir()` directories cleaned at exit; the example runner's cleanup is derived from each run's `artifact = ` line and tripwired on the seed-directory listing; the one known hazard is the concurrent-arms race recorded as an open row in `docs/todo.md:31` (not a defect of a suite run singly). The 1800 s watchdogs kill a hung child.
- Hypothesis 6, the probe helper: functions only, `tm_probe_`-prefixed, no top-level side effects, `main` guarded by `abspath(PROGRAM_FILE) == @__FILE__`; the per-rank receipt files are written, flushed and closed per rank, joined in rank order by the parent; the CPU reference path is read by both the child and the parent (the parent re-reads the child's artifacts itself, 17503–17512). The standalone form works where MPI and Printf are reachable (default environment: PASS 4/4 in 36 s); see LEAD U6-3 for the load-path caveat. The kick formula `tm_probe_kick` is the kernel's arithmetic in the kernel's order (crab_cavity.jl 156–172, compared line by line), which is what makes the 0-ulp CPU pin a justified pin rather than a lucky one.
- The `(k)` tripwire's `draws_k[1] === Octopus._turn_offset(slot1_k, …)` (10608) is a plumbing identity by design (the draws tuple IS the per-slot `_turn_offset`); it is labelled as such in the comment and is not presented as correctness evidence.

## Unchecked, and why

- The example testset and the two MPI sections were not re-executed here (10–12 minutes each; their gate rows and assertion arithmetic were verified instead).
- The `test/examples/crab_cavity_noise.jl` harness (1409 lines) was not read: outside the region (the brief names the testsets and the probe).
- Injections were applied in the parent process only; the mpiexec child always ran unpatched, so the two-rank arm's behaviour under an injected defect was not measured (its failures in D and E are parent/child disagreements, not detections).
- The fast lane was not run end to end; its membership was derived from the `_lane_gate` sites and confirmed for the probe by the gate-closed count.

## Artefacts

`U6/runtests_diff.patch`, `U6/baseline.log`, `U6/gate_closed.log`,
`U6/inject_{A,B,C,D,E}.log`, `U6/preamble_*.jl`, `U6/measure_check1.jl`,
`U6/standalone_default.log`, `U6/standalone_gateshaped.log`,
`U6/standalone_mpi_default/` (the child's receipts and twelve artifacts).
