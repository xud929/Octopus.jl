# U55: process documents: the audit protocol and the experiences file

Tree audited: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683 (read-only). Depth: claims-vs-code.
Hypotheses briefed: (1) every Measured Lesson and standing decision names receipts (files,
commits, numbers) that exist at HEAD, and the code still follows the rule; (2) the "deliberately
not being done" list against the code, both directions; (3) the protocol's own cross-references
(section numbers, record names, the newest-record pointer) resolve.

## Region

- `docs/comprehensive_audit.md`, lines 1-887 (887 lines), read in full.
- `docs/experiences.md`, lines 1-1766 (1766 lines), read in full.
- Total 2653 lines. Reference material consulted only where a claim pointed at it: `docs/history/*`
  (file list, named sections, grep for quoted numbers and finding IDs), `docs/README.md` (index
  lines named by the protocol), `docs/todo.md` and `docs/history/todo_ledger_archive.md` (rows the
  lessons cite), the `src/`, `ext/`, `test/`, `validation/` symbols the lessons name, `AGENTS.md`,
  `.github/workflows/ci.yml`, and git history read from a COPY of `.git` placed in the scratch
  directory (no git command was run against the audited checkout).

## Provenance

READ line by line (the auditor's own reading, not delegated):
- `docs/comprehensive_audit.md` 1-230, 231-460, 461-690, 691-887.
- `docs/experiences.md` 1-230, 231-460, 461-690, 691-920, 921-1150, 1151-1380, 1381-1610, 1611-1766.

EXECUTED (scratch: `result/comprehensive_audit_2026_10_18/probes/U55/`):
- `gitcopy/`: `cp -r .git` of the checkout; `git --git-dir=gitcopy log/show/ls-tree` resolved every
  commit hash the two files cite: baf0255 (2026-08-04), 3a395ae and 81430eb (2026-08-06), 3fd4826,
  a5d8609, 05c8ed5, 7de4d81 (2026-08-05), 8b84333 and 543e82f (2026-08-07/08), d0fb3f2 (2026-08-08,
  "neighbour-audit standard"), 5dd9e22 (2026-09-03, the AGENTS.md restructure), 6ac8d61 (2026-09-04,
  gate-per-push), 93e1720, 7711a8a, 21bce7d, ce43179, d5fc720, a351d74, cecb908, 39c6ae3, 075938c,
  7b566ad, 88a09da, e3818be (2026-07-25). All exist with the dates and subjects the text implies.
  `ls-tree HEAD` confirmed `docs/history/gpic_wobble_capture_2026_08_19.txt` is tracked and that no
  `.ipynb_checkpoints` path is tracked.
- `probe_counts.jl` (output in `probe_counts.out`): `analysis_option_schema(TwissDispersionAnalysis)`
  has 14 options (one of them `longitudinal_mode`); 31 registered element kinds; 22 kinds carry
  `Symplectic6DMap` by identity and not `NonSymplectic6DMap`, 5 carry `NonSymplectic6DMap`, and a
  substring match counts 27 — exactly the 27-vs-22 of the "substring match is not a set" lesson,
  still true at HEAD. `Base.get_extension(Octopus, :OctopusMPIExt)` is `nothing` under
  `using Octopus` alone.
- `probe_ext.jl` (output in `probe_ext.out`): `using Octopus` -> extension `nothing`; after
  `using MPI` -> `OctopusMPIExt`.
- Receipt sweeps (shell loops, results quoted below): 45 source symbols named by the two files
  grepped in `src ext test validation` — all 45 present; 102 numeric tokens from `experiences.md`
  grepped in `docs/history docs/design docs/theory` excluding the file itself — 93 located
  verbatim, 3 more under spelling variants, 6 not located anywhere outside the lesson (LEAD U55-7);
  every history file name checked against `docs/README.md` (one unindexed, LEAD U55-6).

## Leads

### LEAD U55-1 [Minor, confidence high] docs/comprehensive_audit.md:46
Claim: The protocol's "newest of all" neighbour-audit pointer (the stage 9 section of `history/twiss_dispersion_analysis_history.md`, 2026-09-16) is stale, and the `docs/README.md` list it tells the reader to consult repeats the same stale claim.
Mechanism: Two later targeted neighbour audits exist and are indexed elsewhere in the same README: the stage 4 audit inside `history/turn_modulation_stages3_4_2026_10_13.md` (README lines 468-472) and the scoped pass `history/audit_crab_cavity_noise_neighbours_2026_10_16.md` with its `_unit_reports/` (README lines 551-560). README lines 623-627 nevertheless still say the twiss stage 9 section "is the newest neighbour-audit precedent", so the hedge "check docs/README.md for anything later" lands on a list that confirms the wrong answer; a reader following the protocol's reading budget reads the wrong precedent. Cross-file seam (README outside this region), noted and stopped.
Repro: `grep -n "newest of all" docs/comprehensive_audit.md; grep -n "newest neighbour-audit precedent" docs/README.md; ls docs/history | grep -E "audit_crab_cavity_noise_neighbours_2026_10_16.md|turn_modulation_stages3_4_2026_10_13.md"` — one hit each in the two documents and two later files listed.

### LEAD U55-2 [Minor, confidence high] docs/experiences.md:24
Claim: The lesson "(U12-8, two remain open)" describes ledger state that ended 2026-09-07.
Mechanism: The archive (`todo_ledger_archive.md` lines 37 and 49) explains the "two" as the rows U4-18/U12-8 waiting on constructor-keyword introspection. `docs/todo.md` now carries "Three metadata-validator checks are tautologies | **CLOSED 2026-09-07**" (the U12-8 row: the three tautologies were proved and replaced by two non-circular checks, 31 friendly constructors measured) and "The observer schema-vs-report check is an identity for derived reports | CLOSED 2026-09-07" (U4-18), with only a narrowed successor row ("Observer declared defaults are unchecked, because two are sentinels", open 2026-09-07) left. The experiences entry still tells the reader two U12-8 items are open; the hypothesis-1 defect class (a lesson whose receipt state moved).
Repro: `grep -n "two remain open" docs/experiences.md; grep -n "Three metadata-validator checks are tautologies" docs/todo.md | grep -c CLOSED` — the first prints line 24, the second prints `1`.

### LEAD U55-3 [Minor, confidence high] docs/comprehensive_audit.md:176
Claim: The protocol states "`docs/todo.md` for open rows; closures move to `docs/history/todo_ledger_archive.md`", and the ledger does not follow it: 23 rows marked CLOSED (closed 2026-09-06 through 2026-10-16) still sit in `docs/todo.md`.
Mechanism: `docs/todo.md` lines 3-14 state the same rule ("Open work only ... When an item below closes: move its row ... to the archive"), so the protocol's description is of a rule, not of the practice; a compacted orchestrator reading "open rows" would re-triage 23 closed items, which is the rediscovery cost Phase 0's context-budget paragraph exists to prevent. Cross-file seam (`docs/todo.md` outside this region); whether the fix is to sweep the rows or to soften the two sentences is the auditor's call.
Repro: `grep -c "CLOSED" docs/todo.md` prints `23`; `grep -n "closures move to" docs/comprehensive_audit.md` prints line 176.

### LEAD U55-4 [Minor, confidence high] docs/experiences.md:511
Claim: The sentence "`Base.get_extension(Main.Octopus, :OctopusMPIExt)` is `nothing` under the include and `OctopusMPIExt` under `using Octopus`" is false as written: package mode alone does not attach the extension; `MPI` must be loaded too.
Mechanism: `OctopusMPIExt` is a `[weakdeps]` extension and Julia loads it only when both the package and the weak dependency are loaded. Measured on this tree: `using Octopus` -> `nothing`; then `using MPI` -> `OctopusMPIExt`. The harnesses do it right (`test/examples/crab_cavity_noise.jl` runs `using Octopus` then `using MPI` behind a `PkgId(...).uuid === nothing` refusal; `weak_strong_tracking.jl:172` asserts the extension by name), so this is a wording defect in the lesson: a reader who copies the sentence into a probe gets a `nothing`, concludes package mode is broken, and chases the wrong cause. One clause ("and `using MPI`") fixes it.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U55/probe_ext.jl` prints `ext under using Octopus only: nothing` then `ext after using MPI too: OctopusMPIExt`.

### LEAD U55-5 [Minor, confidence med] docs/experiences.md:1761
Claim: The standing decision "`AGENTS.md` carries stable invariants and routing only ... Dates, campaign identifiers ... live in generated registries, this file, the Measured Lessons, and `docs/history/`" is not met by `AGENTS.md` itself, which carries one date ("owner decision 2026-09-04", Definition of Done).
Mechanism: Hypothesis 2, direction "the list says it is not done, the tree does it". The date is a provenance citation for the gate-per-push rule (commit 6ac8d61, 2026-09-04) rather than a fact that will age, so the owner may judge it within the rule's intent; it is nevertheless the only dated string in the entry point and the standing decision admits no exception. Low cost either way: cite the decision by its `docs/experiences.md` section ("Process habits that earned their place") or amend the standing decision to allow decision dates.
Repro: `grep -n "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]" AGENTS.md` prints exactly one line (the Definition of Done bullet).

### LEAD U55-6 [Minor, confidence med] docs/comprehensive_audit.md:689
Claim: (Out of hypothesis, cross-file seam.) One tracked file under `docs/history/` is absent from the `docs/README.md` index: `gpic_wobble_capture_2026_08_19.txt`.
Mechanism: The protocol (line 689-690) and AGENTS.md ("`docs/README.md` indexes all of it") promise an index of the history directory; the suite's docs-index tripwire evidently requires only `.md` records, so a `.txt` capture can be tracked and unindexed without a signal. The capture is reachable only through `history/gpic_wobble_mechanism_2026_09_07.md` and a todo row, not through the index. Out of hypothesis (index completeness is class 14, "index and snapshot staleness"); cross-file (README, test tripwire), noted and stopped.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && for f in $(ls docs/history); do grep -q -F "history/$f" docs/README.md || echo "NOT INDEXED: $f"; done` prints exactly one line, `NOT INDEXED: gpic_wobble_capture_2026_08_19.txt`.

### LEAD U55-7 [Minor, confidence low] docs/experiences.md:962
Claim: Six measured numbers quoted by lessons have no receipt outside `experiences.md` — they were committed only inside the lesson, so the record that should carry them cannot be checked against them.
Mechanism: The repository rule is that the numbers behind a claim land with the claim; these did, but only in the lesson text: "54.8 best against 123.2 median" (line 962; commit 7b566ad changed `multi_process_step4g_spectral_2026_09_05.md` in the same batch yet that record carries only the 26%/25% comparison), "2.96e-5" (line 1084, the stage 3 chord measurement), "96 eps against 64 eps" (line 1109, the third broken assertion of the AVX2 episode), "80.9" (line 1345, one of four decade ratios; 41.6/46.5/11.3 are located), "1540 'ulp' ... 3.4e-21" and "128-4030 ulp" (lines 1596-1605; the record `turn_modulation_record_2026_10_15.md` line 74 says "27-35 ulp of the px kick and up to 4e3 of the pz kick", so these are finer than the record). None contradicts a record; the gap is that a reader cannot re-derive them from a harness or table. Confidence low on severity because the numbers are committed and consistent with their records' coarser statements.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/docs && for n in "54.8" "123.2" "2.96e-5" "96 eps" "80.9" "3.4e-21" "1540"; do printf "%s: " "$n"; grep -rl -F -- "$n" history design theory | grep -v experiences.md | grep -v twiss_dispersion_analysis_history | wc -l; done` prints `0` for each (the twiss history's "54.8"/"123.2" hits are unrelated quantities; checked).

## Clean

Hypothesis 3, the protocol's cross-references (every pointer in `docs/comprehensive_audit.md` was resolved against the tree):
- Record names: `history/neighbour_audit_2026_08_07.md`, `comprehensive_audit_2026_08_04.md`, `_08_05.md`, `_08_05_b.md`, `todo_ledger_archive.md`, `twiss_dispersion_analysis_history.md`, `neighbour_audit_2026_09_06.md`, `comprehensive_audit_2026_08_05_unit_reports/` (21 files, matching "the audit's 21 per-unit reports"), `comprehensive_audit_2026_08_05_b_unit_reports/U3_report.md` and `U1_report.md` — all exist. "At the time of writing the newest full record is `comprehensive_audit_2026_08_05_b.md`" is still true (no later `comprehensive_audit_*.md`); "newest standalone `neighbour_audit_2026_09_06.md`" is still true for that prefix (the stale part is LEAD U55-1).
- Section pointers: `comprehensive_audit_2026_08_05.md` §7 is "Open queue — dispositioned, priced, with reproductions" and contains the block "### Post-campaign closures (2026-08-05, audit-queue session)" at line 573, as the Measured Lessons preamble says; the "seam tally in the history record" is `_08_05_b.md` §3 "Seam map" (line 310-313, "every §4 finding sits on a seam"); "Phase 16 halt" names the halt paragraph that is in Phase 16; "(Measured Lesson 6)" and experiences' "Measured Lesson 12 in comprehensive_audit.md" point at the lessons with those contents; the stage 9 section exists as "## 2026-09-16: stage 9, the post-campaign targeted neighbour audit of 93e1720..7711a8a" (twiss history line 14931).
- Naming convention (Phase 18) against practice: full passes `comprehensive_audit_2026_08_04/05/05_b.md`; scoped passes `audit_twiss_dispersion_{theory,notation,literature}_2026_09_0{8,9}.md` and `audit_crab_cavity_noise_neighbours_2026_10_16.md`; unit reports `U<k>_report.md` beside them. Observed deviation, judged style and not raised as a lead: the crab-noise audit also archives seam-pass reports as `S1..S5_report.md` plus an `INDEX.md`, which the convention text does not mention.
- Gate invocation in Lesson 9 is byte-identical to the one in `AGENTS.md`'s Verification Matrix.

Hypothesis 1, receipts (what was compared):
- Commits: all 23 hashes cited by the two files resolve in the copied `.git` with matching dates (list under Provenance). The "2026-09-03 restructure" is 5dd9e22; the "owner decision 2026-09-04" is 6ac8d61; the "Owner direction (2026-08-08)" for the targeted neighbour audit is carried by d0fb3f2 (2026-08-08, "...neighbour-audit standard"), which is the commit that added that protocol section.
- Finding IDs: U3-6, U15-4 (`_08_05` unit reports U3/U21/U15 and record lines 530, 602); U11-1/2/3, U15-3/6/7, U5-1, U6-2, U3-2, U1-6, U4-6, U4-17, U4-12, U24-10 (`_08_05_b` unit reports and `LEAD_INDEX.md`); U21-6, U12-8, U4-2, U4-1, U16-2, U4-4, U14-4, U9-2, U14-2 (archive and records). "149/163/130 regs/thread" is `_08_05_b_unit_reports/U3_report.md:395`; "8 of 12" is `U24_report.md`; "1 of 13" is in the 2026-08-04 record, the archive and U4/U22 reports; "83%" in the 2026-08-04 record and archive; "~4,660" and `baf0255` at `_08_05.md:17, 210-213`; "~60%" at `_08_05.md:90, 456` and `_08_05_b.md:116, 783`; "nine sessions" at `_08_04.md:3`; "fifteen digits" is the ratio 1.0000000000000002 at `_08_04.md:4210`; "six defects" is the archive's row 65 ("Building it found six more defects"); "from 11 hand-picked kinds to all 30" is `_08_05.md:610` (U21-5) and the comment at `validation/tracking_backend_consistency.jl:173-178`; Lesson 2's "contract still probing the old rejection" is `_08_05.md:570, 663`; Lesson 5's "1/4/8" is `_08_05_b.md:903`; the 2026-08-07 precedent's "two real defects in the gpic sibling file" are N1 and N2 of that record (both `gaussian_pic_cuda.jl`), and its "closure commits had a missed sibling-file caller caught by the gate" is the body of 543e82f ("The first gate run caught a missed caller in validation/high_energy_weakstrong_limit.jl -- the U1-6 sibling-file class, again").
- Lesson 6's `:lattice` claim is still accurate: `docs/theory/pic_free_space_kernels.md:318-322` carries the 2026-08-03 correction "no harness for it was ever committed (`e3818be` changed only two markdown files), so its absolute numbers are not reproducible"; e3818be exists (2026-07-25); no `validation/*.jl` mentions `:lattice`.
- Numbers: 93 of 102 numeric tokens located verbatim in `docs/history`, `docs/design` or `docs/theory` (the multi-process campaign's 176%/1760%/1874/1.9x/3.5x/0.149 GiB/42 ms/0.09 ms/9.4 s/2.5 s/0.25 ms/"42, 17 and 9"/21 ms/27.1/15.11/14.80/1.33x/41.2/39.5/209 ms/40.8/26%/25%/1344 B/1.282 GiB/1.25 KB/104 of 256/2%/11%/4e-4 in their step records; "91 all-sums ... 35 calls cost 141 us each where 91 cost 65" in `design/multi_process_policy.md:1021-1028`; the batch 3 numbers 2.8 ulp/5.7e-64/"Lattice magnets" in `crab_cavity_noise_audit_fixes_batch3_2026_10_17.md:146-156`; 4.5 % and `_dispersion_graph` in `beam_beam_fixes_2026_10_18.md:47-49`; 14400 B and "592 B at exactly 32, 0 at 31" in `design/turn_modulation.md` §7; the PTC mass and 1.1102230246251565e-16 in `twiss_external_benchmarks_2026_09_15.md`; 0.205 in the theory note §4.5 and the archive row closed 2026-10-18). Three more located under spelling variants (1.66e-3, "15 of its 18", 55). The six not located are LEAD U55-7.
- Document sections named by lessons: `theory/arc_survey_and_velocity_slip.md` §4 "The two wrong forms, kept with their evidence"; `design/twiss_dispersion_analysis.md:244-248` records the 27-vs-22 substring episode; `design/turn_modulation.md` §7 "Measured cost of the pure update"; `guides/development_workflow.md:39` "Two load modes" with the quoted sentences; `theory/crab_cavity_noise_response.md:410` "4.5 The vertical response through the beam–beam force (measured, not derived here)"; `history/turn_modulation_stage1_2026_10_12.md` §3 "Measured"; `turn_modulation_record_2026_10_15.md` §2 with "section 2.2" cited at lines 4, 221, 568; `spectral_turn_table_2026_10_16.md` "review F1" at lines 79-129.

Hypothesis 1, the rule the code follows (each lesson's stated repair located in the tree):
- All 45 symbols named exist: `_LATTICE_BODY_KEYS = keys(_LATTICE_BODY_PARAMS)` (`src/elements/lattice_magnets.jl:1154`, U9-2's derivation); `_PLACEMENT_PROBE_DOF`, `_LATTICE_BODY_PROBE`, `_active_cuda_launch`, `_cuda_pic_extract_slice` (15 call sites, the two files of Lesson 12), `_mp_collective_times`, `_mp_nranks`, `_mp_is_root`, `_slice_transverse_moments`, `_shifted_second_moment` (`slicing.jl:815`), `_cuda_pic_threads`, `_dispersion_graph` (`canonical_separation.jl:277`, as the lesson says), `configuration_report`, `_spectral_option_active`, `_route_from_graph` with `_ROUTE_INVARIANCE_MULTIPLIER = 256.0` ("the constant stays 256"), `_INVARIANCE_RESIDUAL_CAP = 3.0` (`dispersion_routes.jl:213`, pinned 4 times in the suite), `_with_longitudinal_mode`, `coefficient_condition`, `_extref_read_wide`, `_RULE_COMPONENT_BASE = 1024` with its key-layout comment (`turn_modulated.jl:156`), `_slot_draws` as an `@generated` unroll (`turn_modulated.jl:1152`), `_update_line_unrolled`, `_unheld_rng_id`, `_rng_id_held`, `_subtypes_recursive`, `_concrete_octopus_subtypes`, `_FixG*`, `reset_rng_id_counter!`, `next_rng_id!`, `allow_lost_particles`, `TW-NORMALIZER` (9 suite lines), `PredicateSchedule`, `wedge_coeff`, `maxlog` (23 sites), `OCTOPUS_RANKS` (the launcher pin passes an explicit count).
- Effectiveness contract: the device filter is "CUDA reads it, and (CPU cannot see it OR it is an execution choice)" (`src/contracts/Contracts.jl:3970-3972`); the metric identity `cuda_options_checked == cuda_only_options + both` is asserted (`test/runtests.jl:14532`); `exemptions_seen` records consulted exemptions (U4-17, `Contracts.jl:3271, 3321`); no `drift.nst`/`drift.integrator_order` exemption entry remains (only fixture uses).
- `@element_spec` template declares `analyses = [TwissDispersionAnalysis]` (`Knowledge.jl:570`); `__init__` clears the RNG-id registry (`_forget_rng_id_holders!`, `Octopus.jl:184-187`); every `+ 1_000_000` site is wrapped in `_unheld_rng_id(...)` (11 suite sites, `counter_rng.jl:180-183` documents why); `reset_rng_id_counter!(next_rng_id!())` is used by the registry-warning testset (`runtests.jl:19246`).
- `_st6_pin_lines` asserts exactly three `ratio <=` lines, each naming `_ST6_PIN` (`runtests.jl:1206, 1387-1388`; `const _ST6_PIN = 0.5` at 1205, "above the stage 6 testset" as stated).
- `_with_longitudinal_mode`: the suite's loop runs over `fieldnames(TwissDispersionAnalysis)` (derived, not a hand list) and asserts each field differs from the default before asserting it is carried (`runtests.jl:6266-6290`); the measured 14 options minus `longitudinal_mode` are the lesson's "thirteen carried options".
- Docstring binding: the sweep refuses with `@test isempty(foreign)` (`runtests.jl:21814-21822`), not merely `@info`.
- MPI receipts: the suite counts receipt FILES per rank (`got1 == 1`, `got2 == 2`, `got4 == 4`, `runtests.jl:23105-23110`, "N ranks owe N receipt files") before the `MPI-LUM` bit-identity pin at 23167-23170 — the "assert that N arrived" rule is followed at the section level.
- The `:funneled` guard reads the `ScopedValue` `_ON_SPAWNED_WORKER[]` (`Policies.jl:574`), keeping `threadid() != 1` only as an additional catch with a comment saying so.
- Phase 16's permanent sweeps exist as testsets: "No method grows a Core.Box outside the argued allowlist" (16915), "CPU solver stack is thread-count invariant" (17015), "A second live writer on one path warns at initialization" (24385), "Curved frame x transverse field: every routing is a gradient" (16739).
- `validation/tracking_backend_consistency.jl:256-263` derives `declaring` kinds from metadata and fails on `uncovered`; `src/elements/strong_beam.jl:1369-1377` carries the `eta / h` conversion and the Xsuite/MAD-X mapping; declared fold sites at `lattice_magnets.jl:1191`; the heterogeneous-line allocation pin is a slope between 50 and 250 turns (`runtests.jl:18815-18826`); N = 33 pink refusal tested (`runtests.jl:11332`); testset "Turn modulation: CPU/CUDA identity and the device conversion" exists (26625); `hasfield(InexactError, ...)` pin exists (25217).
- The L1670 `+ 1_000_000` convention and its L1702 supersession both stand in the file by the "corrections beside originals" rule; `counter_rng.jl:180-183` carries the current form, so a reader of the code is not misled.
- The crab-noise harness guards package mode through `Base.PkgId(Main.Octopus).uuid === nothing` and then `using Octopus; using MPI` rather than asserting the extension by name as the lesson prescribes; equivalent in effect (measured in `probe_ext.jl`), noted, not raised.

Hypothesis 2, the standing decisions against the tree:
- Soft-fringe solenoid: no soft-fringe model in `src/elements/` (grep `soft.fringe` finds only an unrelated `why=` string); archive rows 113 and 2033 carry the decision.
- `pz` fail-fast gap: `allow_lost_particles` exists (`Beam.jl:3, 219`), `Beam.jl:210` documents the imaginary-`sqrt` case; archive rows 116 and 641-656 ("fail-fast is the policy, deliberately not configurable") carry the conditions.
- Node-solve caching: none in `src/tasks/strongstrong/`; `_pic_prebuild_node_caches!` (`pic_cpu.jl:65`) prebuilds MESHES for the `:node` grid mode and is unrelated to the closed-negative field-solve caching (archive rows 118, 486, 522 "plane sharing is REJECTED").
- Vertical response ratio 0.205: theory note §4.5 is titled "(measured, not derived here)"; `validation/crab_cavity_noise_response.jl` takes the ratio as the optional explicit input `ref_y_over_x_phase` and prints the y/x rows as INFO without a verdict (lines 23, 352-363); the archive row (lines 3000-3004) records the 2026-10-18 owner closure with "nothing was derived".
- Nightly jobs: `.github/workflows/ci.yml` has no `schedule:`/cron trigger; `profiling/nightly_benchmark.sh` states "It does NOT commit ... inert ... opt-in per machine" (lines 22-33) and `test/nightly_suite.sh` installs per machine into a user crontab writing `~/.octopus_nightly/` only; the archive row 107 records the 2026-08-07 uninstall.
- AGENTS.md invariants-only: holds except for one date (LEAD U55-5).
- Not on the list but done: nothing found — no soft-fringe solenoid, no node-solve cache, no scheduled CI job, no derived vertical ratio.

Other: the `docs/history/.ipynb_checkpoints/comprehensive_audit_2026_08_04-checkpoint.md` present on disk is untracked and covered by `.gitignore` lines 12-13 (a local stray, not a repository defect).

## Unchecked

- Numbers inside the Twiss campaign sections (lines 1078-1446) were checked for presence as tokens in `twiss_dispersion_analysis_history.md`, not re-derived or read in their record context; the three missing tokens there are in LEAD U55-7.
- The protocol's claim that the archived 2026-08-05 unit reports "used per-unit heading styles" (line 232-234) was spot-checked on U1, U7, U14 (all "## Coverage / ## Leads" at section level); the per-lead item formats were not compared.
- Lesson 5's `(v-d)+d` frame round-trip mechanism and the "placement-parameter inactive table argued from map structure" were not traced to code; the symbols around them (`_PLACEMENT_PROBE_DOF`, exemption bookkeeping) exist.
- Whether the 2026-10-18 beam-beam fix batch (`history/beam_beam_fixes_2026_10_18.md`, which has no neighbour-audit section; its only "neighbour" mention is a todo row at line 118) owes the targeted neighbour audit the protocol's first section and experiences line 1003 promise after every campaign, or whether this comprehensive pass is taken as that audit, cannot be read from the tree; left to the auditor.
- `docs/README.md`, `docs/todo.md`, `AGENTS.md`, the suite and the history records were consulted only at the lines the two files point to; they were not audited as regions (LEADs U55-1, U55-3, U55-6 are seams into them).
- The experiences file's process rules that describe agent behaviour (worktree hooks, watchdog sizing, workflow ground rules; lines 1448-1508) have no code or record counterpart to check beyond the history files they name, which exist.
