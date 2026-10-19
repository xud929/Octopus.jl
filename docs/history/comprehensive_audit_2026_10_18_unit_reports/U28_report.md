# U28: test/runtests.jl lines 1-3242 (lanes, CUDA visibility, architecture integrity, the Twiss analysis stages 1-3 and 5-6, 8)

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683 (read-only). Host: sapphirerapids, one RTX 4500 Ada,
`Octopus.CUDA.functional()` true, Julia with `--threads=4`. Reading unit of the comprehensive audit protocol;
every claim below is a LEAD, not a finding.

## Region

`test/runtests.jl` lines 1-3242 of 32035 (3242 lines, read line by line). Contents, in file order:

- 1-28 lane mechanism (`_TEST_LANE`, `_lane_gate`); 30-50 `using` block; 52-130 the header comment and the
  hoisted "TSC weights are bit-identical across backends (U2-3)" testset; 132-161 `CUDA_TESTS_ACTIVE` and
  "CUDA coverage status"; 163-268 "Architecture integrity".
- 270-1028 Twiss stage 1 Part A kernel testsets (symplectic form, defect, reciprocal scaling,
  back-transformation rows, invariance residual, perturbation scale, manufactured maps, vocabularies,
  `Determined`, `AmbiguitySet`) and the stage 5 declaration/analyzable-kind testsets (921-1077).
- 1079-1390 stage 6 (identity contract: registration, `_st6_*` helpers, `_ST6_PIN`, `_st6_pin_lines`, the
  pinned-metrics testset with negatives n1-n8) and stage 8 registration (1108-1138).
- 1392-2012 stage 2 Part A (4D eigenmodes, closed form, actions, FODO, clusters, scaling); 2014-2647 Part B
  (Mais-Ripken, Edwards-Teng, the 12.2-2 construction, guards, Sagan-Rubin, scaling).
- 2649-3030 stage 3 test-local fixture library (`_st3_*`, `_mc_*`); 3031-3241 the first three mode-cluster
  testsets (vocabulary, rolled FODO and detuned controls, `resolution_chord = Inf` and partitions). Line 3242
  is the blank line after the testset that closes at 3241; no testset is cut by the region boundary.

No `_lane_gate` call occurs in the region: every testset here runs in both lanes (the twiss blocks say so in
their headers, 276 and 1395).

## Provenance

READ line by line: `test/runtests.jl` 1-3242 (all of it). For mechanism, also read: `src/knowledge/Knowledge.jl`
345-348 and 436-485 (the four registry containers and `register_element_meta!`), `src/analysis/symplectic_linear_algebra.jl`
88-122 (`_symplectic_defect`), `src/elements/linear6d.jl` 170-230 (the row-ratio loop, grep), `src/beam/Beam.jl`
9-14 (`_HAS_CUDA`), `src/tasks/Tasks.jl` 356 and 363 (grep), `docs/README.md` (grep), `docs/design/testing_lanes.md`
sections 3-4, `docs/comprehensive_audit.md` Phase 9, the headers of the previous U17-U20 reports (different
numbering; none of their regions overlaps a lead below).

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U28/`):

- `probe1.jl` (log `probe1.log`): P1 the stage 6/8 on-disk snapshot path resolves (`isfile` true) and the same
  recipe on a three-deep method yields a nonexistent path; P2 `det([0.4 0.2; 0.6 0.3]) == 0.0` exactly, and the
  `else`-branch tolerances at a one-ulp determinant are 1.8e21 and Inf; P3 the four detuned rolled-FODO gaps:
  `|g - pin| / tol` = 0.11, 0.103, 0.103, 0.139 at eps = 1e-3, 1e-6, 1e-9, 1e-12, and the computed gap at 1e-12
  deviates 6.45e-4 relative (1.4e-15 absolute) from the exact split; P6 a temporary kind registered with a
  `friendly_constructor` survives the test's three deletes in `ELEMENT_META_BY_FRIENDLY_TYPE` (32 -> 33) while
  `validate_element_metadata().passed` and `validate(TwissDispersionIdentityContract()).passed` stay true;
  P7 `_EIG4D_MAPS == _PB_MAPS` (identical construction) true.
- `probe2.jl` (log `probe2.log`): `validate(TwissDispersionIdentityContract())` on this host: passed, 57 rows,
  worst 0.1317 (`k_longitudinal_block_symplecticity`, c = 16), next 0.125 (`c_d8_round_trip`, c = 8), 0 rows
  above 0.25.
- `probe3_docs_index.log` (python, read-only over `docs/`): 130 files indexed by name, 59 via the three
  `indexed-wholesale` markers, 0 unindexed, 0 files whose basename appears only as the tail of a longer name,
  21 basenames duplicated across directories, 3 files that pass the basename clause through a link to a
  different file of the same name (all three `U1_report.md`, all wholesale-covered).
- greps: `grep -rl CUDABackend src | wc -l` = 13 (the banner at 152-155 names twelve); `grep -n _ST6_PIN
  test/runtests.jl` shows the third pin reader at 30655 inside "Physics contracts" (30603).

## Leads

### LEAD U28-1 [Minor, confidence high] test/runtests.jl:152
Claim: The no-GPU banner's hand-maintained list "Twelve source files carry CUDABackend code" has drifted: thirteen files do, and `src/tasks/Tasks.jl` is missing from it.
Mechanism: The `@info` text at 148-158 enumerates the files by hand (three `*_cuda.jl` plus nine named files) directly under the comment (142-147) that records why the previous hand count "Nine" rotted (U20-11); nothing derives the list from the tree, so `src/tasks/Tasks.jl`, whose lines 356 and 363 guard `CUDA.synchronize()` on `backend === CUDABackend`, is live CUDA-reachable code the banner tells a CI reader does not exist. Out of hypothesis (defect classes 2 and 14, hand-copied knowledge drifting in a message that exists to be read when the GPU half did not run).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && grep -rl CUDABackend src | wc -l` prints 13; `grep -rl CUDABackend src | grep -c Tasks.jl` prints 1; `grep -n "Twelve source files" test/runtests.jl` finds the banner.

### LEAD U28-2 [Minor, confidence high] test/runtests.jl:1316
Claim: The n3 and n3b registry restores (1316-1319, 1331-1334) hand-list three of the four containers `register_element_meta!` writes, and the "registry restored" assertion at 1336 cannot see the fourth.
Mechanism: `register_element_meta!` (Knowledge.jl 454-482) writes `REGISTERED_ELEMENT_SPECS`, `ELEMENT_META_BY_SPEC_TYPE`, `ELEMENT_META_BY_KIND` and, when `friendly_constructor !== nothing`, `ELEMENT_META_BY_FRIENDLY_TYPE`; the `finally` blocks delete from the first three only. The test is correct today only because its liar metas omit `friendly_constructor` (default `nothing`); the restore check `validate(c).passed` and `validate_element_metadata()` both pass with a leaked friendly-type entry (measured), so a future negative that adds a friendly constructor would leave a stale `ElementMeta` in the friendly lookup for every later testset with no signal. Hypothesis 3, derived-vs-copied container list; defect class 3 (walkers disagreeing on what the registry is).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U28/probe1.jl` section P6 prints `BY_FRIENDLY_TYPE still has it: true (size 32 -> 33)` and `validate_element_metadata().passed after the leak: true`.

### LEAD U28-3 [Minor, confidence high] test/runtests.jl:1097
Claim: The stage 6 and stage 8 on-disk snapshot comparisons (1097-1103, 1125-1131) sit behind an `if isfile(ondisk)` whose path is derived by three `dirname` calls from `validate_configuration_metadata`'s source file, so a relocation of that one method silently removes both checks with no `@test_skip`.
Mechanism: `root = dirname^3(methods(validate_configuration_metadata).file)` equals `src/` only because the method lives four levels deep (`src/tasks/strongstrong/interface.jl`); `ondisk = joinpath(dirname(root), "docs", "registry_snapshot.md")` then resolves. Measured: the identical recipe applied to `validate_element_metadata` (Knowledge.jl, three deep) yields `/cfs/ad/dxu/Library/Julia/docs/registry_snapshot.md`, `isfile` false, and the guard would skip the block invisibly. Today the body executes (`isfile` true), and line 190 already asserts the stricter bitwise snapshot equality with `pkgdir(Octopus)`, so the loss would be of a redundant check; the pattern is still defect class 1 (a correct check behind a condition that can turn false without a visible skip). In hypothesis 1.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; f = String(first(methods(Octopus.validate_configuration_metadata)).file); println(isfile(joinpath(dirname(dirname(dirname(dirname(f)))), "docs", "registry_snapshot.md")))'` prints true today; `probe1.jl` P1 prints the three-deep counterexample with `isfile=false`.

### LEAD U28-4 [Minor, confidence med] test/runtests.jl:228
Claim: The docs-index tripwire's name clause `occursin(f, index)` tests a basename substring, not the file's path, so a document is "indexed" whenever any link in `docs/README.md` names a different file with the same basename; its synthetic negative control (244-256) feeds only the directory clause.
Mechanism: 21 basenames are duplicated across `docs/` (`U1_report.md` ... `U21_report.md` in the audit bundles); `README.md` links `U1_report.md` twice (lines 635 and 640, two different directories), so the three other `U1_report.md` files pass the name clause through someone else's link (measured: 3; all three happen to be wholesale-covered, so there is no live false pass), and a newcomer named `U1_report.md` in a fresh, unindexed directory would pass today. The in-suite negative control at 244-256 shows the directory clause failing on a synthetic index; the basename clause was never shown to fail on an unindexed file whose name is shared, so the instrument's weaker half is unvalidated (hypothesis 3, instrument never fed a known defect; hypothesis 2, missing negative control).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && grep -n "U1_report.md" docs/README.md | wc -l` prints 2; `find docs -name U1_report.md | wc -l` prints 5; a one-line check `julia -e 'idx = read("docs/README.md", String); println(occursin("U1_report.md", idx), " ", occursin("history/comprehensive_audit_2026_08_05_unit_reports/U1_report.md", idx))'` prints `true false`.

### LEAD U28-5 [Minor, confidence med] test/runtests.jl:86
Claim: The hoisted "TSC weights are bit-identical across backends (U2-3)" testset is gated by `if Octopus._HAS_CUDA` with no `else @test_skip`, the shape the header's own rule at line 58 says to avoid.
Mechanism: `_HAS_CUDA` is `try @eval import CUDA; true catch false end` (Beam.jl 9-14), so a failed CUDA.jl import (a broken artifact or a load error on a new Julia) makes the whole `if` body vanish from the summary rather than reporting Broken, and with it the one host-side pin of the deposit's cross-backend agreement that the hoist (80-85) exists to keep running without a GPU. Today `_HAS_CUDA` is true on this host and on CI (CUDA.jl imports without a device), so the testset runs. In hypothesis 1 (a gate that skips invisibly).
Repro: `awk 'NR>=86 && NR<=130' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | grep -c "test_skip"` prints 0; `awk 'NR>=1 && NR<=3242 && /^if /' test/runtests.jl` shows this as the region's only column-0 runtime gate.

### LEAD U28-6 [Minor, confidence med] test/runtests.jl:1198
Claim: The documented re-open rule for the stage 6 identity pins (a row above 0.25 at its frozen multiplier "re-opens that row's measurement before the pin trips") has no instrument; nothing in the testset warns or records between 0.25 and the 0.5 pin.
Mechanism: The only assertions are `ratio <= _ST6_PIN` (1230, 1260) and the printed 57-row table (1242-1244; GitHub annotations under `GITHUB_ACTIONS`), so a row drifting from today's 0.13 into (0.25, 0.5] is silently green and the re-open depends on a human reading a log. Measured on this host: worst 0.1317 (`k_longitudinal_block_symplecticity`), 0.125 (`c_d8_round_trip`), 0 rows above 0.25; the comment records CI run 436 at 0.154. Out of hypothesis (defect class 6, "loud beats silent": a documented threshold that nothing fires on).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U28/probe2.jl` prints the rows above 0.1 and `above 0.25: 0`; `grep -n "0.25" test/runtests.jl | awk -F: '$1>=1198 && $1<=1262'` shows the threshold appears in comments only.

### LEAD U28-7 [Minor, confidence med] test/runtests.jl:2430
Claim: The admissibility branch for the det R = 0 fixture of the 12.2-2 construction is selected by `d == 0` on a computed `det(Rm)`, while the fixture is admitted only to `2 eps` at 2383; the `else` branch's tolerances scale as `1 / (w d)^2` and `1 / min(w, 1 - w)^2`, so at a one-ulp determinant they are vacuous.
Mechanism: `d = det([0.4 0.2; 0.6 0.3])` is exactly 0.0 today (measured; LU with pivoting and the literal products both give 0.12 bit for bit), so the `d == 0` arm runs and the test is correct. The correctness rests on how these particular literals round, not on structure: were `d` 2.8e-17, the `else` arm would run with a det tolerance of 1.8e21 and a lambda tolerance of Inf (measured), leaving `other.admissible == (d > 0)` at 2429 as the only discriminating assertion. Defect classes 8 and 12 (a branch on exact zero of a cancellation-prone quantity whose admission test is looser than the branch).
Repro: `julia -e 'using LinearAlgebra; d = det([0.4 0.2; 0.6 0.3]); println(repr(d), " ", d == 0); d = 2.8e-17; w = 1/(1+d); println(64*eps()*100/(w*d)^2, " ", 64*eps()*100/min(w, 1-w)^2)'` prints `0.0 true` then `1.8e21`-order and `Inf`.

## Clean

Checked and found sound, with the comparison made:

- Lane mechanism (13-28): an unknown or repeated `lane=` argument errors (15, 17-18); the skip list and the
  per-section yellow line are produced by `_lane_gate`; the banner lives in the tail of the file (outside the
  region). No testset in 1-3242 is lane-gated, matching the twiss headers (276, 1395).
- CUDA visibility (132-161): the no-GPU branch is an `@test_skip` (159), so it appears as Broken, and the
  GPU branch is non-empty (140). The hand count was removed on purpose (142-147); only the file list rotted
  (U28-1).
- "TSC weights are bit-identical across backends" (87-128): the bitwise `===` pin is between two pure
  host-side arithmetic routines meant to agree bit for bit, and the discriminating-power tripwire (127,
  `> 100` of 512 non-dyadic draws at ~68 percent) keeps the sweep honest against the all-dyadic regression
  the comment records (U20-1). Only the gate shape is weak (U28-5).
- "Architecture integrity" (163-268): the snapshot is compared bitwise with `pkgdir` (189-190); the policy
  walk is asserted at depth 2 (182-186); the AGENTS.md source-map check derives the directory list from
  `readdir(src)` (264-267; top-level directories only, which is what the map promises). The wholesale marker
  negative control (244-256) shows the old directory rule waving a file through and the new one catching it.
- Stage 1 kernel testsets (299-918): every tolerance is stated as `c eps kappa` with `c` justified beside
  it; exact equalities are structural: `_symplectic_form` entries are 0 and +-1 (309-311), `K + adj(K) ==
  tr(K) I` is exact by IEEE commutativity (332), the `:none` scaling and power-of-two factors are exact
  (454-457, 481-485), and the bitwise `row_ratio` equality between a 4x4 and its embedding (425) is one code
  path on an identical 6x6 tuple: `_symplectic_defect` embeds the 4x4 with `_embed_4to6` and calls the
  hand-written `_linear6d_symplectic_error` loop (read: symplectic_linear_algebra.jl 108-120, linear6d.jl
  170-220), no BLAS order involved. The 13 injected defects (285-297) are recorded with per-injection fail
  counts in the history file, out of suite, as the protocol allows.
- Vocabulary pins (782-818, 997-1010, 3031-3042): tuple, docstring bullets and (for `ANALYSIS_STATUSES`) the
  source literal are three copies reconciled by assertion; the 16-member reason list in the test is a
  deliberate second copy compared with the source.
- Stage 5 tripwires (952-988): the rule set is derived from the registry with `===` on the method types (the
  substring pitfall is named), `:line` is a declared union, both set differences are asserted, and the
  analyzable-kind sweep branches on the outcome, with a non-ArgumentError falling to `@test false` plus an
  `@info` (1067-1070). The closed-orbit refusal is checked for its documented message and its `:warn`
  continuation with `@test_logs match_mode=:any` (1063-1066).
- Stage 6 (1220-1390): the contract passes on this host with worst 0.1317 (probe2), the negatives n1-n8 run
  the probe on the same fixtures and each asserts the culprit by name; the registry restores are checked by
  a re-validate (1336; its blind spot is U28-2); the `_st6_pin_lines` tripwire counts exactly three pin
  lines naming `_ST6_PIN` across this testset and "Physics contracts" (the third at 30655, outside the
  region) and reads the suite by package path. Its `blk` scan ends at the first column-0 `end`; a block
  that failed to scan contributes no lines and fails the count, so the instrument cannot pass by silence.
- Stage 2 Parts A and B (1438-2647): the "field IS the formula" `==` pins (1545, 1548, 1564, 1568,
  1571-1573, 1582, 1585, 1635-1639, 1649-1650, 2098-2099, 2106-2109, 2185, 2245-2262, 2295, 2310, 2322) are
  recomputations of the source's expression on the same inputs, deliberate anti-copy tripwires; they hold
  only while the source keeps the same floating-point expression, which is the documented intent. Skips
  inside loops are counted (`n_frames == 200` 1588, `n_checked == 200` 1682, `n_labels_clear == 200` 1683,
  `n_tie_clear == 0` 1708, `n_rows == 60` 2011, `n_both > 0` 2361, `n_sr == 100` 2603), so a silent
  `continue` cannot hollow a testset. The scaled Twiss values are shown to move (2006-2008) so the invariance
  rows are not trivially satisfied. The two 200-map fixture sets are identical (probe1 P7: `_EIG4D_MAPS ==
  _PB_MAPS` true), as the comment at 2073-2074 claims without asserting.
- Stage 3 (3031-3241): the provisional-constant rule `^const _NAME(MULTIPLIER|CHORD) = ` finds exactly the
  nine constants of the two files (grep: 3 in degenerate_dispersion.jl, 6 in mode_clusters.jl; the remaining
  `const`s there are NamedTuple type aliases and a help string); the default chord is pinned to a range, not
  a literal (3068). The detuned-FODO gap pins have `|g - pin| / tol` of 0.10-0.14 at all four eps (probe1
  P3); at eps = 1e-12 the eigenvalue roundoff (1.4e-15 absolute, 6.5e-4 relative to a 2.1e-12 gap) is 0.32 of
  the tolerance, so the pin is inside its regime with a factor ~3 to the floor on this host. The chord
  bracket (3149-3153) and the kappa-decides control (3157-3161) are asserted on derived values.
- Hypothesis 1 sweep: no `@testset` body in the region sits behind a false condition today; the only
  runtime-conditional blocks are `if Octopus._HAS_CUDA` (86, U28-5), `if isfile(ondisk)` (1099 and 1127,
  true today, U28-3), `if haskey(ENV, "GITHUB_ACTIONS")` (1250, output only) and `if sc !== :auto` (2006, a
  deliberately narrower assertion). No `else @test true` remains in the region.

Style only, not leads: `rng = MersenneTwister(20260805)` is assigned twice (91 and 107); the comment at
711-712 calls the graph-invariance bound "the same 1e4 eps bound as the scaling-invariance block" while that
block uses `1000 eps` times a measured amplification (536); the 1391 and 1960 export lists are hand lists
by design, backed by the whole-module export check elsewhere.

## Unchecked

- The "Physics contracts" testset (30603 onward) that `_st6_pin_lines` also scans is outside the region;
  only the existence of its `_ST6_PIN` reader at 30655 was confirmed by grep, not its body.
- The recorded out-of-suite negative controls (13 + 11 + 15 injected defects, 281-297, 1406-1421, 2023-2040;
  the identity-contract and stage 3 history tables) were not re-run; the history file
  `docs/history/twiss_dispersion_analysis_history.md` was not read against the constants.
- The region's testsets were not executed through the stage runner by title; the probes targeted the seven
  leads and the pins named under Clean. The suite's own run on this tree is the owner's gate record, not
  this unit's measurement.
- The header's claim (80-85) that `_cuda_pic_tsc_weights` is callable with no device present was not
  measured: this host has a GPU, and the claim only matters on CI.
- `docs/comprehensive_audit.md` beyond Phase 9 and `docs/design/testing_lanes.md` beyond sections 3-4 were
  not read; no lead depends on them.
