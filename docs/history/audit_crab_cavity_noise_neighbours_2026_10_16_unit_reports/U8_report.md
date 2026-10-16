# U8 report: the campaign's documents (Phases 3 and 6), crab cavity noise audit 2026-10-16

Reading unit U8 of the comprehensive audit protocol. Repository: Octopus, main
checkout `/cfs/ad/dxu/Library/Julia/Octopus` at `3126908` (= origin/main at the
time of reading; `git branch -r --contains 3126908` lists origin/main). Nothing
in the repository was modified. Every claim below is a LEAD for the auditor,
not a finding.

## Region and provenance

Read in full, line by line: `docs/theory/crab_cavity_noise_response.md` (770
lines); `docs/design/turn_modulation_record.md` (405); `docs/design/spectral_turn_table.md`
(529); the five history records `crab_cavity_noise_validation_2026_10_14.md`
(560), `crab_cavity_noise_mpi_benchmark_2026_10_14.md` (424),
`crab_cavity_noise_relative_strength_2026_10_15.md` (356),
`turn_modulation_record_2026_10_15.md` (578), `spectral_turn_table_2026_10_16.md`
(895); `docs/todo.md` rows 18-41 (every row naming crab, RF, turn modulation,
spectral, the recorder or the example); `docs/guides/documentation.md` (71).
Read as the brief scoped them: `docs/design/turn_modulation.md` lines 1-35 (the
status block), 549-647 (sections 5.6, 5.7, 6), 746-786 (section 10) and the
whole diff `git diff 6995151 3126908 -- docs/design/turn_modulation.md` (91+/16-);
`docs/design/run_artifact.md` 18-32 and 90-280 (the turn-modulation parts);
`docs/public_api.md` 28-48, 118-130, 195-380 ("Turn Modulation" and the example
paragraphs); `docs/README.md` 83-135, 369-392, 432-545 (the entries for these
notes and records); `docs/experiences.md` 1465-1607 (the campaign's entries);
`docs/history/turn_modulation_stages3_4_2026_10_13.md` 216-703 (section 6, the
39 leads with dispositions, and section 7). For hypothesis 6 only:
`src/elements/crab_cavity.jl` 1-40, 80-95, 150-190, 285-461 (the kick, `_realize_draws`,
`realize`, the wrap, the slot protocol).

Executed (read-only probes): `git log`/`git diff` for every commit sha the
documents cite; greps over `src/`, `test/runtests.jl`, `validation/`,
`examples/`, `profiling/` for the symbols, testset names, messages and code
facts behind each todo row and each matrix cell; arithmetic by hand on the
hand-copied numbers (stated per row in section B). Not executed: any Julia
process, any validation run, any CI query (`gh` is not installed on this host;
no network check was made), the gate logs under the git-ignored `result/gates/`.

## A. Leads

### LEAD U8-1 [low, confidence high] docs/theory/crab_cavity_noise_response.md:720
Claim: Section 8 item 2 still says the relative-strength implementation is "stage 0 of `../design/turn_modulation_record.md`, in progress 2026-10-15", after stage 0 landed (f7cfe6a), was gated and pushed (c070750, CI run 454 per the record note and the recorder record).
Mechanism: The theory note was reworded in the stage 0 batch before that batch finished (relative record section 2, "Documents, this batch: the theory note (sections 1, 3.1, 3.2, 4.5, 6, 7 and 8 item 2)") and the bookkeeping commits that closed stage 0 updated the todo row and the design notes but not this sentence; a status line that names a stage as in progress after its push is the class the brief calls "a status line not matching the pushed state".
Repro: `grep -n 'in progress 2026-10-15' docs/theory/crab_cavity_noise_response.md` prints one line (section 8 item 2); `git log -1 --format=%h c070750` exists.

### LEAD U8-2 [low, confidence high] docs/design/turn_modulation.md:364
Claim: Section 4.4's recorder paragraph ends "`turn_modulation_record.md`, stage 1 in progress 2026-10-15", while the same file's status block (lines 17-21) says stage 1 landed 2026-10-15 and section 10 says "stage 1 landed 2026-10-15 as 77c0bcc, pushed as a710f5a".
Mechanism: The 2026-10-16 coordinator's correction recorded in the spectral record (its section 6: "section 10's stale '(2026-10-15, not implemented)' ... now reads 'stage 1 landed'") fixed section 10 and left the sibling sentence in section 4.4, which the spectral batch's diff shows was added by the recorder batch with the "in progress" wording and never revisited.
Repro: `grep -n 'stage 1 in progress' docs/design/turn_modulation.md` prints the section 4.4 line; `grep -n 'landed 2026-10-15' docs/design/turn_modulation.md` prints the status block and section 10.

### LEAD U8-3 [low, confidence high] docs/design/turn_modulation_record.md:17
Claim: Three documents say stage 2 of the recorder design is not implemented (`turn_modulation_record.md` status "stage 2 not implemented"; `docs/README.md` line 107 "stage 2 not implemented"; `docs/todo.md` row 25 "gate pending; stage 2 (the harness toggle ..., the example's `output` switch ..., the validation study reading the public series) follows"), while the stage 1 record's section 3 opens "Done 2026-10-15, stage 2 of the note's staging carried by this batch" and the code carries all three stage 2 items.
Mechanism: Stage 2 as the design's section 7 defines it is (i) the harness toggle `OCTOPUS_RECORD_TURN_MODULATION`, (ii) the example's `output` block switching the record on by default, (iii) the validation's noise part reading the recorded series through the public reader. All three exist: the harness header documents the toggle (`test/examples/crab_cavity_noise.jl` line 215), the example sets `record_turn_modulation = true` (line 315), and the validation's `recorded` item reads `turn_modulation_provenance(recorded_path)` after a run with the switch on (`validation/crab_cavity_noise_response.jl` lines 959-998). The status lines were written when stage 1 landed and the examples update that followed the same day was filed under stage 1's record without the stage ledger being moved; row 25's notes cell also still reads "gate pending" beside a state cell that says gated and pushed.
Repro: `grep -n 'stage 2' docs/design/turn_modulation_record.md docs/README.md docs/todo.md | grep -i 'not implemented\|follows'` prints three hits; `grep -n 'stage 2 of the note' docs/history/turn_modulation_record_2026_10_15.md` prints the record's "carried by this batch" sentence; `grep -n 'record_turn_modulation = true' examples/crab_cavity_noise.jl validation/crab_cavity_noise_response.jl` prints both consumers.

### LEAD U8-4 [low, confidence high] docs/todo.md:21
Claim: The turn-modulation row's notes cell ends "pushed 2026-10-15 as c070750, CI run pending", while row 25, `docs/design/turn_modulation_record.md` line 6 and the recorder record line 14 record "CI run 454 green (znver4, 29.5 min)" for that push.
Mechanism: The same fact is hand-copied into two rows of one table and only one was updated by the bookkeeping commit that recorded CI 454; the Invariants' "do not hand-copy knowledge" rule names this failure mode.
Repro: `grep -o 'c070750, CI run [a-z0-9 ]*' docs/todo.md` prints "CI run pending" from row 21 and `grep -o 'c070750 (CI run 454 green)' docs/todo.md` prints row 25's.

### LEAD U8-5 [low, confidence high] docs/design/spectral_turn_table.md:229
Claim: Decision D7's canonical provenance-name template `spectral(<label>; sigma=..., band=..., turns=..., seed=..., rng_id=..., amplitudes=...)` lacks the `slot=<s>` field that the landed code emits between `rng_id=` and `amplitudes=`.
Mechanism: Review F1 (2026-10-16) added the slot to the key and to the name (the D4 dated remark at line 146 says "the canonical name gaining `slot=<s>`", the record's section 1 line 96-97 and `docs/public_api.md` line 231 show the eight-field name), but D7, the decision that owns the name's format, was given a dated remark for `amplitudes=` and `rng_id=` only (lines 235-239) and its template was not re-issued; `_spectral_name` in `src/elements/turn_modulated.jl` writes `slot=$(slot)` unconditionally, so every receipt differs from the design's stated format.
Repro: `grep -n 'slot=' docs/design/spectral_turn_table.md` shows the field only in the D4 remark, never in D7's template line (`grep -n 'amplitudes=<fixed|rayleigh>)' docs/design/spectral_turn_table.md`); `grep -n 'slot=\$(slot)' src/elements/turn_modulated.jl` prints the emitting line.

### LEAD U8-6 [low, confidence high] docs/README.md:122
Claim: The index entry for `spectral_turn_table.md` describes "Philox phases from a mandatory seed and stream", a keyword that D11 renamed to `rng_id` ("its second keyword is `rng_id`, not `stream`"); inside the design note the section 3 heading still reads "Decisions (proposed; owner to confirm, section 9)" and D4's heading "`seed` and `stream` mandatory" although section 9 records every question as decided 2026-10-16 (D4 has a dated correction beneath it; the section 3 heading and the README entry have none).
Mechanism: The brief's hypothesis names the pre-D11 "stream" keyword as superseded text; the README entry was last touched to add the D11 sentence and kept its earlier clause, and the design note's headings were left as written on 2026-10-15 while only dated remarks were appended below them, so a reader of headings and index alone meets the retired keyword and a "proposed" status.
Repro: `grep -n 'seed and stream\|stream. mandatory\|proposed; owner to confirm' docs/README.md docs/design/spectral_turn_table.md` prints the three sites; `grep -n 'stream' src/elements/turn_modulated.jl | grep -c 'kw\|keyword'` shows no `stream` keyword in the landed signature (`grep -n 'function spectral_turn_table' src/elements/turn_modulated.jl`).

### LEAD U8-7 [low, confidence high] docs/history/crab_cavity_noise_relative_strength_2026_10_15.md:3
Claim: The stage 0 record is frozen with "Status: in progress 2026-10-15", "Not verified: CI on this tree, which is not pushed at the time of writing" (line 339) and a ledger sentence promising "the status line changes to the gate's result when the push lands" (line 356); the push (c070750) and CI run 454 are recorded only in other documents, never in this record.
Mechanism: The sibling records of the same campaign closed themselves by an addendum ("Added after the push: pushed ... CI run ... completed green" in the 2026-10-14 validation and MPI records; the recorder and spectral records carry their CI runs), so the convention the campaign set was followed everywhere but here; a reader of this record alone cannot tell whether stage 0 was ever pushed.
Repro: `grep -c 'c070750\|CI run 454' docs/history/crab_cavity_noise_relative_strength_2026_10_15.md` prints 0; `grep -n 'Added after the push' docs/history/crab_cavity_noise_validation_2026_10_14.md docs/history/crab_cavity_noise_mpi_benchmark_2026_10_14.md` prints the sibling addenda.

### LEAD U8-8 [low, confidence high] docs/history/spectral_turn_table_2026_10_16.md:833
Claim: After the gate and CI text was added, the spectral record contradicts itself: line 52-53 says "the bracketed `[...: pending]` markers that remain stand where the gate's details go" (no marker remains); lines 828-832 record the push 0e3c8da and CI run 457 green and the next sentence (833-834) says "Not verified: CI on this tree at this writing"; lines 893-895 say the gate markers "are to be filled from the two arms' logs after the run, the push and the CI run"; and `docs/README.md` lines 541-543 still describe the record's markers as being filled "as the batch's agents report".
Mechanism: The record and bookkeeping commits (0e3c8da, 3126908) replaced the markers with the gate table and the CI result but did not revise the framing sentences written when the markers existed; the README entry was written at the same time as the framing and inherited it.
Repro: `grep -n 'pending\]' docs/history/spectral_turn_table_2026_10_16.md` prints only the framing sentence (line 52), no marker; `grep -n 'Not verified:' docs/history/spectral_turn_table_2026_10_16.md` and `grep -n 'CI run 457' docs/history/spectral_turn_table_2026_10_16.md` print adjacent lines; `grep -n 'are filled as the batch' docs/README.md`.

### LEAD U8-9 [low, confidence high] docs/history/turn_modulation_stages3_4_2026_10_13.md:630
Claim: Section 6.6 lists U5-2 (whether the artifact writer rolls back a partial `/turn_modulation` slot on a write error) among the owner items "appended to the turn-modulation row", but `docs/todo.md` carries no U5-2 and no rollback item in any row.
Mechanism: Row 21's owner list names U1-1, U7-1 layout (ii), U3-2, U4-3, U5-4, U5-5 and U6-2 (read in full); U5-2 was dropped between the record's text and the ledger edit, so the only trace of the owner question is the frozen record, which `docs/todo.md`'s header says is not where open work lives.
Repro: `grep -c 'U5-2\|roll back\|rollback' docs/todo.md` prints 1, and that hit (`grep -n 'U5-2' docs/todo.md`) is the 2026-08 multi-process U5-2 in row 48, not the turn-modulation one; `grep -n 'U5-2 (whether' docs/history/turn_modulation_stages3_4_2026_10_13.md` prints the owner item.

### LEAD U8-10 [low, confidence high] src/elements/crab_cavity.jl:17 (out of region: a docstring seam the document review exposed)
Claim: `?ThinCrabCavitySpec` (lines 17-18) and `?ThinRFCavitySpec` (`src/elements/rf_cavity.jl` 245-246) list the rules as `WhiteNoise`, `PinkNoise` or `TurnTable`, omitting `SpectralNoise`, while `construction_help`, both `ParamMeta` meanings, `docs/public_api.md`, the catalogue entry and the `CrabCavityNoise` docstring list four.
Mechanism: The spectral batch's review F4 extended the rules testset's tripwire to the `construction_help` and the two `ParamMeta` meanings of both kinds (record section 4) and the fixer reports "all six `element_help` forms name every rule"; `element_help` reads the metadata, not the type docstring, so the type docstrings were outside every check and kept the three-rule list. A user at the REPL asking `?ThinCrabCavitySpec` does not learn that the parameter accepts a `SpectralNoise`.
Repro: `grep -n 'TurnTable(offsets; name)' src/elements/crab_cavity.jl src/elements/rf_cavity.jl` prints the two docstring lines, neither followed by `SpectralNoise`; `grep -c 'SpectralNoise' src/elements/crab_cavity.jl` is non-zero only through the metadata and container docstrings (`grep -n 'SpectralNoise' src/elements/crab_cavity.jl`).

### LEAD U8-11 [low, confidence med] docs/theory/crab_cavity_noise_response.md:426
Claim: Section 4.5 says the relative-semantics amplitude runs' vertical rate "is this coupling alone, which the re-validation of 2026-10-15 measures", a forward reference never closed: the measured values (y/x = 0.296, 0.187, 0.085 at scales 0.5, 1, 2; AP1/A1 in y 0.247; C2 vertical identical to C0) live only in the relative record's section 3, while the same section of the note and its section 8 item 6 do carry the phase-noise ratios (0.205, 0.128, 0.072, 0.389) and the superseded amplitude measurement (1.180e-6), and todo row 24 lists the phase-noise ratios only.
Mechanism: The note was reworded in the stage 0 batch before the re-validation ran (relative record, section 2's documents bullet) and not revisited after; the note's own policy (lines 15-16, "the numbers they measure belong to the campaign's record, not to this note") is applied to the new measurement and not to the older ones, so the one place that explains the open theory item (section 4.5) shows the reader half of the measured dependence it says is unexplained.
Repro: `grep -n 'which the re-validation of 2026-10-15 measures' docs/theory/crab_cavity_noise_response.md`; `grep -n '0.296\|0.187' docs/theory/crab_cavity_noise_response.md docs/todo.md` prints nothing; `grep -n 'y/x = 0.296' docs/history/crab_cavity_noise_relative_strength_2026_10_15.md` prints the measurement.

### LEAD U8-12 [low, confidence med] validation/README.md:457 (out of region: the validation index the campaign's documents cite)
Claim: The crab-noise section's description of part `noise` still lists "the strength offset equal on both planes to 4 ulp", the additive-semantics check that the stage 0 batch replaced by "both planes carry the same factor, and `strengthY` stays 0 on a horizontal cavity" (relative record, section 2), two paragraphs after the same section states the relative sigma.
Mechanism: The relative record's section 4 lists the frozen 2026-10-14 record's sentences to read with the correction and the batch's documents bullet names the theory and design notes, `public_api.md`, `README.md`, `todo.md`, but not `validation/README.md`, whose part-`noise` paragraph predates the change and was later extended (the `recorded` and `spectral` items) without the old item being reworded.
Repro: `grep -n 'strength offset equal on both planes' validation/README.md` prints the line; `grep -n 'strengthY === 0.0\|stays 0 on a horizontal' docs/history/crab_cavity_noise_relative_strength_2026_10_15.md` prints the replacement check.

### LEAD U8-13 [low, confidence med] docs/design/spectral_turn_table.md:349
Claim: Section 4's cost sentence for the landed function, "Cost `O(N log N)`: 0.62 s and 8.4 MB at 2^20 turns on the section 6 machine", quotes the 2026-10-12 sketch's timing; the landed synthesis measures 0.058 s (implementer, the D11 remark at line 290 and the record), 0.063-0.070 s (fixer) and 71 ms (reviewer) at 2^20 turns, ten times less, and the design's section 2 and the README entry repeat the 0.62 s as well.
Mechanism: The sentence was written before the implementation and attributes the number to the sketch's machine, so it is not false, but it is the design's only cost statement in the section that describes the function, and the brief's hypothesis asks for "a claim about a number the code no longer produces"; the D11 remark carries the landed number without the section 4 sentence pointing at it.
Repro: `grep -n '0.62 s' docs/design/spectral_turn_table.md docs/design/turn_modulation.md docs/README.md` prints the sites; `grep -n '0.058 s\|0.063 s' docs/design/spectral_turn_table.md docs/history/spectral_turn_table_2026_10_16.md` prints the landed figures.

### LEAD U8-14 [info, confidence high] docs/todo.md:22
Claim: The two CLOSED rows of the campaign keep forward-looking text that is now wrong: row 22 ends "Next: the final acceptance (the C2 covariance test, the pink-specific scatter tolerance, the A4 re-run at 12500 turns, the theory note's derived coupling ratio), then the full gate..." and quotes "exponents 1.996 (phase) and 2.026 (amplitude)" where the record's final paragraph takes the amplitude exponent from A05/A1/A2 (2.017; 2.038 under the relative semantics); row 23 ends "Running: the crab benchmark ... Owed: the record's section 4 table, the full gate ..., the push and the CI run; a stale comment in the launcher testset still calls the crab harness the one without an arm", and that comment no longer exists in `test/runtests.jl`.
Mechanism: The state cells were closed by the bookkeeping commits and the notes cells were left as the in-progress snapshot; the file's own header says a closed row moves to the archive with its closing measurements, which would have forced the rewrite.
Repro: `grep -o 'Next: the final acceptance[^.]*' docs/todo.md`; `grep -o 'Owed: the record.s section 4 table[^|]*' docs/todo.md`; `grep -c 'multi-process arm\|without an arm' test/runtests.jl` prints 0.

### LEAD U8-15 [low, confidence med] docs/design/turn_modulation.md:775
Claim: Section 10's strength-semantics bullet ends "The validation sweep measures the vertical rate under the shipped semantics", a sentence written 2026-10-14 when "shipped" meant the additive default, now sitting after the paragraph that records the relative decision and its push, where "the shipped semantics" reads as the relative one and the sentence as a claim about a sweep that measured the other.
Mechanism: The 2026-10-15 edit inserted the decision text into the middle of the 2026-10-14 bullet (the diff shows the insertion after "to both planes.") and kept the bullet's closing sentence verbatim.
Repro: `grep -n 'measures the vertical rate under the shipped semantics' docs/design/turn_modulation.md`; `git diff 6995151 3126908 -- docs/design/turn_modulation.md | grep -n '^ .*shipped semantics'` shows the line as unchanged context.

### LEAD U8-16 [info, confidence high] src/tasks/Tasks.jl:431 (out of region; the stage 4 audit's "observed, not verified" item)
Claim: Section 6.7 of the stage 4 audit observed that `_warn_duplicate_turn_modulation_streams` says "on different elements" also when one spec object is placed twice; the message is unchanged, no todo row carries it, and the spectral batch's new equal-digest warning (`Tasks.jl` line 460) adopted the same wording.
Mechanism: The observation was recorded as "not verified and not fixed" with no disposition row, so nothing routed it to the ledger; the new warning was modelled on the old one.
Repro: `grep -n 'on different elements' src/tasks/Tasks.jl` prints two lines; `grep -c 'placed twice' docs/todo.md` prints 0.

### LEAD U8-17 [info, confidence high] docs/todo.md:26
Claim: The spectral producer row records the batch as landed, gated, pushed as 0e3c8da with CI run 457 green and names nothing owed, yet is not marked CLOSED; its notes cell gives the factory signature as `spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id)` without the `slot` keyword that review F1 added.
Mechanism: The design's staging is "one batch, one session", so stage 1 is the whole deliverable; the row's state cell was rewritten by the bookkeeping commit to record the push and left open, and the signature in the notes cell was written before F1.
Repro: `sed -n '26p' docs/todo.md | grep -c 'CLOSED'` prints 0; `sed -n '26p' docs/todo.md | grep -o 'spectral_turn_table([^)]*)'`; `grep -n 'slot=0' src/elements/turn_modulated.jl | head -1`.

### LEAD U8-18 [info, confidence med] docs/README.md:85
Claim: The index entry for `turn_modulation.md` dates the note as "stages 1 and 2 implemented 2026-10-12, stage 3 implemented 2026-10-13" and describes the catalogue as "white, Voss-McCartney pink, FIR, IIR, per-turn table"; it does not mention stage 4, the 2026-10-15 relative strength semantics or the fourth rule, all of which the note's status block now carries.
Mechanism: The entry was last edited for stage 3; later campaigns added their own entries (the record note, the spectral note) and did not revisit the parent's.
Repro: `sed -n '85,98p' docs/README.md | grep -c 'relative\|SpectralNoise\|stage 4'` prints 0; `sed -n '3,21p' docs/design/turn_modulation.md | grep -c 'relative factor\|stage 4\|stages 1-4'` is non-zero.

## B. Hypothesis 2: numbers that appear in two or more places

Checked by reading both sites and, where marked "arith", by recomputing by hand.

| number | sites | agree? | note |
|---|---|---|---|
| phase white x rate 1.72e-7 /turn | theory s6; validation record s3, s5; todo 22; validation script `ref_phase_white_x` default | yes | arith: 0.5 * 2 cavities * [(4.25e-4)^2 * 0.9422 + (5.31e-5)^2 * 0.806] = 1.725e-7 |
| amplitude white x 1.10e-6 /turn | theory s6; validation record; design s10; todo 21; relative record; `ref_amp_white_x` | yes | arith: 2 * 0.5 * [(1.021e-3)^2 + (2.34e-4)^2] = 1.097e-6 |
| additive-semantics y prediction 9.5e-7; ratio 0.865 / 0.87 | theory 281, 557, 706, 713; design s10; README 387; todo 21; validation record s2 item 5, s8; relative record s1; record note s5 | yes | 9.5/11.0 = 0.864; "0.865" and "0.87" are the same number at two and three digits |
| A1 additive measured y 1.180e-6, x 1.021e-6, 1.16 | theory 282, 424, 714; validation record s5; relative record s1; record note s5 | yes | arith 1.180/1.021 = 1.156 |
| vertical/horizontal under phase noise 0.205, 0.128, 0.072, 0.389 | theory 4.5 and s8; todo 24; validation record s5; relative record s3 | yes | arith from the record's table: 3.61e-8/1.764e-7 = 0.2046; 9.1e-8/7.119e-7 = 0.128; 2.04e-7/2.817e-6 = 0.0724; 9.6e-9/2.474e-8 = 0.388 |
| W1 1.764e-7, 1.026 of prediction; A1 x 0.928 | validation record; todo 22 | yes | arith 1.764/1.72 = 1.0256; 1.021/1.10 = 0.928 |
| exponents: 1.996 phase; 2.026 then 2.017 (A05/A1/A2) amplitude; 2.038 relative | validation record s5 (both), todo 22 (2.026 only), relative record (2.038) | partly | todo 22 quotes the superseded 2.026 (LEAD U8-14); arith on the relative rates 2.500e-7, 1.030e-6, 4.182e-6 gives 2.02-2.04 |
| relative re-validation ratios 0.97, 0.84, 0.63 of former excess; y/x 0.296, 0.187, 0.085; AP1/A1 x 0.150, y 0.247; AT1/A1 1.054 | relative record s3 only | n/a | arith all reproduce from the table (7.41e-8/7.6e-8 = 0.975; 1.930e-7/1.030e-6 = 0.187; 1.545/1.030 = 0.150; 4.76e-8/1.930e-7 = 0.247) |
| common-timing factor 0.59 / 0.588; 1.01e-7 /turn | theory 36, 211, 555, 702; validation record s2, s3 | yes | arith (3.02/3.94)^2 = 0.587 |
| f_rev 78196.75 Hz, 2.815e8 turns/h, beta 0.99999418 | theory table and s6; validation record s3 | yes | arith beta = 1 - 1/(2*293.09^2) = 0.99999418; beta c / 3833.8 = 78196.75; *3600 = 2.815e8 |
| per-hour and doubling-time columns | theory s6; validation record s3 | yes | arith: 1.72e-7*2.815e8 = 48.4; ln2/(1.72e-7*78196.75) = 51.5 s; 1.10e-6 -> 309.7, 8.06 s; 2.5e-8 -> 7.0, 354 s; 1.6e-7 -> 45, 55 s; 1.01e-7 -> 28.4, 87.7 s |
| strengthX 5.1684e-4, -1.2921e-4 m^-1; delta s 5.168e-8 | theory table and s3.1; relative record s1 | yes | arith (4/3) tan(0.0125)/sqrt(1040) = 5.1684e-4 |
| rms band 0.83 % (3 sqrt(1/(2N)), N = 65536); pink 2^20 band [0.9545, 1.0594], sd 0.0194 vs formula 0.0191; sigma_mean 0.25 sigma | theory 5.2; validation record s4; relative record s2, s3 | yes | arith 3*sqrt(1/131072) = 0.00829; (1/16)(2^16-1)/2^16 -> 0.25 |
| recorder cost +11.2 us/turn at capacity 64; 158607 -> 295778 bytes; 68.6 B/turn | record note s9; run_artifact.md; recorder record s1 | yes | arith (295778-158607)/2000 = 68.59; (0.298-0.276)/2000 = 11 us |
| 8 B per slot per turn; 64 MB per million turns for eight slots | record note s4; run_artifact.md; public_api.md; spectral note D10; recorder record s3 | yes | |
| per-turn costs the recorder competes with: 3 ms (CUDA 1e5), 26 ms (CUDA 1e6), 119 ms (16 threads 1e5) | record note s4 citing the benchmark record | yes, rounded | benchmark s4: 3.347, 26.02, 118.71 ms; "3" rounds 3.347 down by 10 % |
| per-turn rebuild about 2 us for twenty wrapped cavities (20 Philox draws); 20 ns / 40 elements bare | record note s2; design s7 table; README 91; todo 21 | yes | two different measurements (with and without draws), each copied consistently |
| `map` over a tuple: ">32" (todo 21, design s7 first table) vs "from 32 entries on, 592 B at exactly 32" (design s7 prose, experiences) | | superseded in todo 21 | the experiences entry records that "longer than 32" was off by one; row 21 keeps the older wording |
| allocation table main / before / after: 640/720/0 (nothing, White), 656/736/0 (nothing, Pink), 976/1056/0 fixture; 14400, 15360, 14720, 15680, 21120, 22080 B per turn | design s7; todo 29; recorder record s4; experiences | yes | |
| synthesis at 2^20: 0.62 s and 8.4 MB (sketch, 2026-10-12); 0.058 s fixed / 0.081 s rayleigh (implementer); 0.070 -> 0.063 s and 0.086 -> 0.082 s (fixer); 71 ms (reviewer) | design turn_modulation s6; spectral note s2, s4, D11 remark; spectral record s1, s4; README 117 | different runs, each attributed | the design's section 4 cost line quotes the sketch (LEAD U8-13); 8.4 MB = 8.0 MiB = 2^20 * 8 B |
| K_eff 294 of 32765 bins for :pink over (2^-14, 1/2) at N = 2^16 | spectral note D5, s6 item 9; spectral record 1r | yes | arith (H_32768 - H_3)^2 / (pi^2/6 - 1 - 1/4 - 1/9) = 294.4; bins k = 4..32768 = 32765 |
| correlation bound 4/sqrt(2 K_eff) = 0.147 at K_eff 372.6 | spectral note D11 remark; spectral record s1, s4 | yes | arith 4/sqrt(745.2) = 0.1465 |
| gate assertion chain: 149326 (b99f6b7) -> 149349 (90a15be, +23) -> 149351 (f858107, +2) -> 149397 (f7cfe6a, +46) -> 150148 (77c0bcc, +751, 334 rows) -> 150700 (c3c6c2c, +552, 336 rows) | the five records' gate sections and the stages 3-4 record | yes | arith: every stated delta matches the stated totals |
| CI runs: 447 (148d39a), 448 (6995151), 449 (20bbfaa), 451 (ef04cfc), 454 (c070750), 455 (a710f5a), 457 (0e3c8da) | todo 21, 22, 23, 25, 26; design status blocks; records | consistent across documents; unverifiable here | todo 21 says "CI run pending" for c070750 (LEAD U8-4); runs 456 and 458 (the markdown-only pushes ac021bc/12b4d75 and 3126908) are named nowhere, which is consistent with the gate rule |
| theory s7 sizing: 5 ms/turn "the default, N = 10^6" | theory 622-626 vs validation record (31 ms at N = 1e6 on a shared GPU; 5.7-6.4 ms at 2e5) and benchmark (26 ms at 1e6, 3.3 ms at 1e5) | plan vs measurement | the note is the plan "written in the present tense"; the fallback to N = 2e5 is documented in the record; not a defect, listed because the number is 5x off |
| harmonic 2 share 1.3 % phase / 5 % amplitude | theory s6; validation record s3 | yes | arith 2.274e-9/1.725e-7 = 1.3 %; 5.48e-8/1.097e-6 = 5.0 % |
| C1 vertical 4.7e-21 = 2.7e-14 of prediction | validation record s5, s6 | yes | arith 4.7e-21/1.72e-7 = 2.7e-14 |

## C. Hypothesis 3: the todo rows the campaign opened or touched

State cell quoted in brief; "code check" is what the grep on 3126908 shows.

| row | item | state cell (abridged) | code check at 3126908 | verdict |
|---|---|---|---|---|
| 21 | Turn-by-turn lattice modulation | stages 1-4 landed ... pushed 6995151, CI 448 green; notes end "pushed as c070750, CI run pending" | relative scaling in both `realize`s (`crab_cavity.jl` 343-345; `rf_cavity.jl` per the record) | state true; notes stale on CI 454 (U8-4); owner item U5-2 missing (U8-9) |
| 22 | Crab cavity noise example and validation | CLOSED 2026-10-14, CI 449 | example, harness, theory, validation present | closed; notes cell stale (U8-14) |
| 23 | MPI arm and benchmark | CLOSED 2026-10-14, CI 451 | `config.execution = :multiprocess` in the example; `profiling/crab_cavity_noise_backends.jl` exists; the "stale launcher comment" is gone from `test/runtests.jl` | closed; notes cell stale (U8-14) |
| 24 | Derive the beam-beam-mediated vertical response | open (2026-10-14) | theory 4.5 says "not derived here"; `ref_y_over_x_phase` is an overridable report argument (`validation/crab_cavity_noise_response.jl` 23, 1755, 1845) | still true; owner/theory item; lacks the relative-semantics amplitude ratios (U8-11) |
| 25 | Record the realised offsets | stage 1 landed, probe-verified, pushed a710f5a, CI 455; stage 0 pushed c070750 (CI 454); "stage 2 not implemented"; notes "gate pending; stage 2 ... follows" | all three stage 2 items exist in code (U8-3) | state partly stale (U8-3) |
| 26 | A spectral producer for TurnTable | stage 1 landed c3c6c2c, gated, pushed 0e3c8da, CI 457 | `SpectralNoise`, `spectral_turn_table`, `_resolve_turn_rule`, `_spectral_name` with `slot=` present | complete, not marked closed; signature omits `slot` (U8-17) |
| 27 | Stateful rules: checkpoint reserved | open (design decision) | no stateful rule; `_RA_TM_STATE = "state"` reserved; the stateless tripwire (stage 4 U1-1) | still true |
| 28 | Effectiveness contract pins RunArtifact options only through receipts | open (2026-10-15) | `grep -c 'record_turn_modulation\|run_artifact_option_schema' src/contracts/Contracts.jl` = 0; the only turn-modulation text in Contracts.jl is the metadata exemption rows (2887-2909, 3038) | still true |
| 29 | Pink-plus-table fixture allocates | CLOSED 2026-10-15 | `_slot_draws` used by `_realize_draws` (`crab_cavity.jl` 336-337) | closed, consistent |
| 30 | `prepare_run_artifact!` refusing empty recorder columns leaves a phantom ledger row | open (2026-10-15, F4) | `RunArtifact.jl` 364-394: the U5-3 slot check runs before the ledger extend, but `_ra_write_turn_modulation!` (the column-misalignment refusal) and `_ra_create_turn_modulation_series!` run after it ("Keyed by the ledger row just appended, so written after it") | still true; it is the U5-3 shape re-entered through the recorder's new refusal path (the stage 4 fix's neighbour) |
| 31 | Two concurrent suites race in the example cleanup | open (2026-10-15) | example `result_dir = joinpath(@__DIR__, "..", "result")`, no env switch (`examples/crab_cavity_noise.jl` 178) | still true; the gate procedure runs arms sequentially (spectral record s5) |
| 32 | Receipt and provenance name an element by its type only | open (2026-10-14) | the artifact writes `element` from `entry.element` only (`RunArtifact.jl` 470, 1192); no label attribute | still true |
| 33 | `rng_id = 0` makes provenance depend on construction order | open (2026-10-14) | `next_rng_id!` is a process-global counter (`counter_rng.jl` 50-54); `SpectralNoise` follows the same convention | still true; now also applies to the fourth rule |
| 34 | Explicit `rng_id` colliding with an earlier fresh id undetected | open (2026-10-14) | `claim_rng_id!` is `id > 0 && atomic_max!` with no registry (`counter_rng.jl` 77-79) | still true |
| 35 | Every-turn MomentObserver dominates CPU per-turn cost | open (2026-10-14) | `_moment_observer_row` still one `_masked_global_sum` per moment (`BeamObservers.jl` 1039-1056, 1280) | still true |
| 36 | Rank identity and per-rank timings have no public collective form | open (2026-10-14) | `_mp_rank()` internal (`Policies.jl` 532-541); no exported accessor | still true |
| 37 | Unbound aperture: `_bind_aperture_entry` neither descends wrappers nor records losses | open (pre-existing, U2-5) | `_bind_aperture_entry(entry::PhysicsEntry{<:Aperture}, ...)` and an identity fallback only (`Tasks.jl` 1382-1384) | still true |
| 38 | BPM observer and radiation can share an `rng_id` unwarned | open (U7-7) | the two warnings compare within a class (`Tasks.jl` 427-465 are turn-modulation only) | still true (not re-measured) |
| 39 | Quiet-machine benchmark of the rebuild | open (U1-4) | no `profiling/` driver for the rebuild (listing: `benchmark_track_cpu.jl`, `crab_cavity_noise_backends.jl`, ...) | still owed |
| 40 | `claim_rng_id!` turns a negative id into an `InexactError` | open (U7-6 shared path) | `return UInt64(id)` with no `id >= 0` check (`counter_rng.jl` 79) | still true |
| 41 | Misaligned strong beam on CUDA is a `KernelError` | open (2026-10-12) | `_requires_cuda_elementwise` has methods on `elem`, `Tuple`, `LumpedRad`, the two strong beams and none on the four wrappers (`phase6d_track.jl` 108-112, `radiation_track.jl` 3-5, `strong_beam_track.jl` 187-188) | still true |

Owner items on file (read from the rows and the records): row 21's list, U1-1 (persist successors or forbid state; now also row 27), U7-1 layout (ii), U3-2, U4-3, U5-4, U5-5, U6-2, plus the three section-10 decisions to confirm (knob plus rule; one rule per harmonic; Float32 table refused), the CUDA.jl `update` name clash, a table on a ForwardDiff dual cavity, the bare `nothing` spelling; row 24 (the vertical coupling derivation); the theory note's section 8 items 1 and 3-5 (common timing, the loud production point, the 1-2 % beam-beam correction, pink normalisation) and the validation record's item 5 (whether single-realisation fit-quality items should be verdicts); U5-2 (rollback) exists only in the stage 4 record (U8-9).

## D. Hypothesis 4: the 39 leads of the stage 4 neighbour audit

Dispositions read from sections 6.3, 6.5, 6.6 of `turn_modulation_stages3_4_2026_10_13.md`; "follow-up" is what the tree at 3126908 shows.

| lead | disposition | follow-up pointed at | happened? |
|---|---|---|---|
| U1-1 | tripwire + owner item | row 21 owner list; later row 27 | yes (both exist; D10 reserves the checkpoint) |
| U1-2 | fixed | regression in the effectiveness testset | yes per 6.5 (not re-run) |
| U1-3 | comment reworded | none | n/a |
| U1-4 | ledgered | row 39 | row exists; benchmark not done |
| U1-5 | fixed (refusal order) | none | n/a |
| U2-1, U2-2, U2-3 | fixed with tests | none | n/a |
| U2-4 | "already a row" | row 41 | row exists; wrapper methods still absent (section C) |
| U2-5 | ledgered | row 37 | row exists; `_bind_aperture_entry` unchanged |
| U2-6 | design note reworded | none | n/a |
| U3-1 | fixed (dead method deleted, tripwire) | none | n/a |
| U3-2 | owner item | row 21 | present in row 21 |
| U3-3, U3-4 | wording | none | n/a |
| U3-5 | fixed (probe extended) | none | n/a |
| U4-1, U4-2 | fixed with the new strong-strong window testset | none | testset exists (`runtests.jl` 17519) |
| U4-3 | owner item | row 21 | present |
| U5-1 | fixed | none | n/a |
| U5-2 | owner item | row 21 per 6.6 | NOT in docs/todo.md (LEAD U8-9) |
| U5-3 | fixed (`haskey` before the ledger append) | none | the fix stands (`RunArtifact.jl` 369-375); the recorder batch added a refusal after the append on another path, now row 30 |
| U5-4, U5-5 | owner items | row 21 | present |
| U5-6 | docstring | none | n/a |
| U5-7 | fixed | none | n/a |
| U6-1 | fixed (docstring moved; binding tripwire) | none | n/a; the type docstring is the one U8-10 finds lagging |
| U6-2 | owner item (exists) | row 21 | present |
| U6-3, U6-4, U6-5, U6-6 | fixed | none | n/a; U6-5's converse tripwire was extended again by spectral review F4 |
| U7-1 | fixed; deferred layout (ii) owner item | row 21 | present |
| U7-2, U7-5 | comment and script labels | none | n/a |
| U7-3, U7-4 | fixed (script expectation; quantile bound) | `validation/README.md` carries 0.9014 | per 6.5 |
| U7-6 | fixed on the rule constructors; shared path ledgered | row 40 | row exists; `claim_rng_id!` unchanged |
| U7-7 | ledgered | row 38 | row exists; unchanged |

Section 6.7's "not verified" items: CI on the stages 3-4 tree -> run 448 (todo 21); nothing ran under MPI -> the recorder batch's two-rank probe; `_execute_strong_strong_turns!` not read line by line -> the recorder batch changed and reviewed it (recorder record s1, s4); the `TrackingTask((line,))` kept-whole aperture -> carried by row 37's last sentence, no measurement since; the "on different elements" wording -> no follow-up (LEAD U8-16).

## E. Hypothesis 5: traceability matrix

"none" marks a missing link. Testset names are the `@testset` titles found in `test/runtests.jl` by grep.

| capability | scientific requirement | theory note section / equation | implementation (file:function) | documentation | docstring | example | test (testset) | validation (part/item) | benchmark | contract |
|---|---|---|---|---|---|---|---|---|---|---|
| phase noise rule (white) | per-turn RF phase error, rms 10 urad per active harmonic, independent streams | s2.1 (dipole + residual), s2.2 (dx_IP/dphi = w tan(theta)/(ik)), s4.1 (dJ/dn = eps a^2/2), s6 table | `turn_modulated.jl`: `WhiteNoise`, `_turn_offset`, `_slot_draws`; `crab_cavity.jl`: `_realize_draws` (`phase[c] + dphi[c]`) | design 5.1, 4.3; public_api "Turn Modulation" | `?WhiteNoise`, `?ThinCrabCavitySpec`, `?realize` | `examples/crab_cavity_noise.jl` rule `:white` | "Turn modulation: rules, wrapper and the pure hook"; "Turn modulation: effectiveness at the kernel boundary, chunking and repositioning"; "Turn modulation: white and pink spectra"; "Turn modulation: CPU/CUDA identity and the device conversion" | `noise` (rms, mean, spectrum, independence), `sweep` W1-W3, T2, `control` C1; `validation/turn_modulation_spectra.jl` | `profiling/crab_cavity_noise_backends.jl` (white at scale 1) | none (no contract validates a turn-modulation rule; `Contracts.jl` holds only the metadata exemption rows) |
| relative strength rule | relative amplitude error 1e-4, one voltage driver scales both planes | s3.1 (kick linear in s, rms over the bunch), s3.2 (dS_X = s_i d, dS_Y = s_y,i d), s6 | `crab_cavity.jl`: `_realize_draws` (`strengthX[a] * (1 + d[a])`, `strengthY[b] * (1 + d[b])`); `rf_cavity.jl`: `realize` (`strength * (1 + d)`) | design s10, 4.1, 5.6; record note s5, D3, D7; public_api offset paragraph | `?ThinCrabCavitySpec`, `CrabCavityNoise`, `ParamMeta` meaning | `strength_rel_rms` handed over directly | rules testset re-pinned (`2e-3 (1 + d)`), "Turn modulation: slot bounds and labels at the wrap", spectra part (h), "Turn modulation: the RF cavity by the same wrap" part (b), kernel-boundary effectiveness | `noise` `exact` verdict (`strengthX == S (1 + d)`, `strengthY === 0.0`); A05, A1, A2, A4, A4s, AP1, AT1; `control` covariance on C2 (falsifier: y at the C0 baseline) | none | none |
| pink rule | 1/f noise at equal rms | s5.1 (dJ/dn = eps S_a(Q)/2), s5.2 (rho(nu) Fejer sum; rho(0.228) = 0.1547; finite-window statistics) | `turn_modulated.jl`: `PinkNoise`, keyed `turn >> k` | design 5.2, 5.5 | `?PinkNoise` | rule `:pink` | "Turn modulation: white and pink spectra" | `noise` (2^20 band), P1, AP1; spectra script | none | none |
| table rule | a recorded sequence applied per absolute turn | s5.3 (reproduces the record's spectrum; bitwise with white when fed white's draws) | `turn_modulated.jl`: `TurnTable`, digest, window check `_check_container_window` | design 5.6, D7; run_artifact.md provenance | `?TurnTable` | rule `:table` (`randn` white tables) | rules testset; "Turn modulation: the strong-strong window and receipt"; "The run artifact records turn-modulation provenance" | T1 (bitwise = W1), T2, AT1, `tablefile` | none | none |
| spectral rule and factory | noise of a chosen spectrum over a band (sideband placement) | none in the theory note (motivation only, spectral note s1); the equations are design D5 (c = sigma N / sqrt(2 sum a_k^2)) | `turn_modulated.jl`: `SpectralNoise`, `spectral_turn_table`, `_spectral_plan`, `_spectral_synthesis`, `_spectral_name`, `_resolve_turn_rule`; call sites `crab_cavity.jl` `_turn_modulation_wrap`, `rf_cavity.jl` | design spectral_turn_table.md; public_api paragraph | `?SpectralNoise`, `?spectral_turn_table` (type docstrings of the specs omit it: U8-10) | rule `:spectral` | "Spectral turn table: exact spectrum, rms, phases and refusals"; "Spectral turn table: the producer through the consumer and the recorder" | `noise` `spectral` item (three cases) | none (synthesis cost measured in the record, no driver) | none |
| the recorder | the realised offsets verifiable from the artifact alone | s1 kick formula (used by the probe's third comparison); no theory of its own | `RunArtifact.jl`: `TurnModulationRecorder`, `_ra_write_turn_modulation!`, `_ra_create_turn_modulation_series!`, `_tm_begin_turn!`/`_tm_end_turn!`, `run_artifact_option_schema`; `turn_modulated.jl`: `update(elem, ctx, sink)`, `_turn_modulation_columns!`; `Tasks.jl`, `interface.jl` loops | design turn_modulation_record.md; run_artifact.md; public_api | `?RunArtifact`, `?run_artifact_option_schema`, `?turn_modulation_provenance` | `output.record_turn_modulation = true` | "The run artifact records the realised turn modulation"; "Turn modulation: the one-particle probe verifies the loop per harmonic" | `noise` `recorded` item | cost at landing (+11.2 us/turn, 68.6 B/turn; record s1) | `validate_configuration_metadata()` RunArtifact block only; `PublicConfigurationEffectivenessContract` does not pin it (row 28) |
| the one-particle probe | the loop realises a new value every turn and the kick consumes it | s1 kick formula | `test/turn_modulation_probe.jl` | design record note 6.1; recorder record 2.2 | none (a test fixture) | none | "Turn modulation: the one-particle probe verifies the loop per harmonic" (CPU, CUDA, two-rank child) | none | none | none |
| the example's MPI arm | the example runs divided, reproducing the undivided run | none (multi_process_policy.md owns the consistency statement) | `examples/crab_cavity_noise.jl` `:multiprocess`; harness `OCTOPUS_USE_MPI`, `OCTOPUS_RANKS`, `OCTOPUS_RECORD_TURN_TIMES` | public_api example paragraph; benchmark record | none | the example itself | "The developer harnesses run divided under an MPI launcher" | none (the benchmark record's section 2 is the reproduction evidence) | `profiling/crab_cavity_noise_backends.jl`; benchmark record s4 | none |

Missing links in summary: no capability has a contract; the spectral rule has no theory-note section; the probe and the MPI arm have no validation item; the pink, table and spectral rules have no benchmark; the spec type docstrings lag the metadata on the fourth rule (U8-10).

## F. Hypothesis 6: sections 3.2 and 4.5 against the code and the measurements

What the note claims the code does (s1 lines 67-83, s3.2): per harmonic `i`, `px -= s_i sin(ikz + phi_i)/(ik)`, `py -= s_y,i sin(...)/(ik)`, `pz -= (s_i x + s_y,i y) cos(...)`; `realize` adds the phase offset to `phase[i]` and scales both `strengthX[i]` and `strengthY[i]` by the same `1 + d_i`, host-side, once per turn; draws independent across cavities (distinct `rng_id`) and across harmonics (distinct slots of one id). What the code does (`crab_cavity.jl`): `track_particle` lines 156-172 apply exactly those three updates with `theta = i*kcc*z + phase[i]`; `_realize_draws` lines 334-349 builds `strengthX[a] * (one(T) + d[a])`, `strengthY[b] * (one(T) + d[b])`, `phase[c] + dphi[c]` from `_slot_draws(rules.phase, ctx, 1, T)` and `_slot_draws(rules.strength, ctx, N + 1, T)` (phase slot `i`, strength slot `N + i`); `realize` is its projection. The note's description matches the code. Consequence the note draws (s3.2): with `strengthY = 0` the vertical kick error is `s_y,i d = 0` exactly; falsifier: vertical growth under horizontal amplitude noise without the strong beam.

Measurements against it (relative record, section 3): C2 (`kbb = 0`) vertical `eps_c` rate +5.341e-17 per turn, identical to C0's +5.341e-17 (difference -1.07e-21, 3.2e-15 of the propagated horizontal slope), so the falsifier did not fire; the `noise` part's `exact` verdict pins `strengthY === 0.0` bitwise on every turn. With the strong beam the colliding amplitude runs grow vertically at y/x = 0.296, 0.187, 0.085 (scales 0.5, 1, 2), the same order and the same falling trend as the phase arms' 0.205, 0.128, 0.072 (scales 1, 2, 4), and 0.63-0.97 of the "excess" the 2026-10-14 record had attributed to the coupling on top of the additive kick. That is consistent with section 4.5's statement that the amplitude runs' vertical growth under the relative semantics is the beam-beam coupling alone and with section 3.2's zero direct vertical kick; the note's own caveat stands, that the ratio R and its dependence on amplitude and spectrum are measured, not derived (todo row 24). The one gap is documentary, not physical: the note announces the re-validation's measurement and never states it (LEAD U8-11).

## G. Clean list (what was compared and found consistent)

- Every commit sha the documents cite exists with the stated date and subject: 7711a8a, 148d39a, b99f6b7, 6995151, 90a15be, 20bbfaa, f858107, ef04cfc, bb22c2b, 7390b23, b3a06b1, f7cfe6a, c070750, 77c0bcc, a710f5a, ac021bc, 12b4d75, c3c6c2c, 0e3c8da, 3126908 (`git log -1` on each); `git log --oneline 6995151..3126908` is the campaign's 17 commits in the order the records narrate.
- The design note's section 5.6 and D7 text, section 4.1's `strength_noise` bullet, the record note's D3/D7, `run_artifact.md`'s series paragraph and option bullet, and `public_api.md`'s offset paragraph all state the relative semantics identically (`S_X (1 + d)`, `S_Y (1 + d)`, `V (1 + d)`; a strength table holds relative factors) and match `_realize_draws`.
- The canonical name as emitted (`_spectral_name`), as documented in `public_api.md` line 231 and as shown by the example run in the spectral record (`spectral(pink; sigma=1.0e-5, band=1.52587890625e-5..0.5, turns=1048576, seed=123456789, rng_id=11, slot=1, amplitudes=fixed)`) agree field for field; only the design's D7 template lags (U8-5).
- `run_artifact.md`'s `kind` list (`white`, `pink` or `table`) is right: a `SpectralNoise` resolves to a table before the provenance is written (`crab_cavity.jl` 382-391).
- The theory note's cited design sections (5.1, 5.2, 5.5, 5.6) exist and are the ones named; its section 7 acceptance tolerances (factor 1.25, exponent 2 +- 0.1, pink ratio +- 25 %, T1 1e-10, eps_c 0.8, J_c 10 %) equal the validation script's defaults printed in its usage line (`tol_rate=1.25 tol_exp=0.1 tol_ratio=0.25 tol_t1=1e-10 tol_epsc_frac=0.8 tol_jc_frac=0.10`).
- The theory note's section 7 falsifier list was rewritten for the relative semantics ("vertical growth under horizontal amplitude noise WITHOUT the strong beam"), and the validation's report part carries that falsifier line (relative record, section 2).
- Section 6's production-point table and its superseded-row footnote, the validation record's section 3 copy, and the relative record's section 4 correction list agree on which numbers are superseded (9.5e-7 and 1.6e-7 in y) and which stand (every x row).
- The experiences entries the records claim exist at the stated places: "A per-turn step compared as a row difference carries the state's rounding" (1519), "A per-index type that rests on constant propagation" (1538), "A new consumer of a keyed RNG must carry every dimension the existing promise spans" (1569).
- `docs/README.md` indexes every document of the region (the three design notes, the theory note, the six history records including `turn_modulation_stage1_2026_10_12.md`).
- The 39-lead count reconciles (U1 5 + U2 6 + U3 5 + U4 3 + U5 7 + U6 6 + U7 7); every ledgered lead has its row (37, 38, 39, 40, 41) and every owner item but U5-2 is in row 21.
- The gate assertion chain across the five batches is arithmetically consistent (section B).
- All seven public symbols of the matrix that I checked carry a docstring immediately above their definition (`WhiteNoise`, `PinkNoise`, `TurnTable`, `SpectralNoise`, `spectral_turn_table`, `TurnModulated`, `RunArtifact`, `run_artifact_option_schema`, `turn_modulation_provenance`, `realize`).

## H. Not checked, and why

- CI runs 449, 451, 454, 455, 457 (and the brief's 456, 458): `gh` is not installed on this host and I made no network request; I report what each document claims and that the claims agree with one another (section B).
- The validation and benchmark numbers were not re-run (hours of GPU time); the hand arithmetic in section B checks internal consistency of the quoted numbers only.
- The gate logs under `result/gates/` (git-ignored) were not opened; the records' gate tables are taken as written.
- `docs/history/turn_modulation_stage1_2026_10_12.md` is outside the region and was not read; `validation/README.md` was grepped for superseded wording only (U8-12), not read in full.
- `docs/design/turn_modulation.md` outside the diff and sections 5.6, 6 and 10 (sections 1-4, 5.1-5.5, 7-9) was not re-read for this unit.
- Docstring rendering (`?ThinCrabCavitySpec` in a Julia session) was not run; U8-10 rests on the source text of the docstring.
- The todo rows 37, 38 and 41 were checked by grep for the structural fact each asserts (method tables, warning scope), not by reproducing their measurements.
