# Recording the realised turn modulation in the run artifact: stage 1, the `record_turn_modulation` option (2026-10-15)

Status: stage 1 implementation landed 2026-10-15 and verified the same day by the
one-particle probe on CPU threads, CUDA and two MPI ranks (section 2.2, 376
of 376 assertions); the examples update landed the same day (section 3)
and a read-only review of the implementation found five items, all fixed in
the batch (section 4); committed as 77c0bcc and gated the same day in both
CPU arms with CUDA active (section 5), awaiting the push. Stage 1 of
[`../design/turn_modulation_record.md`](../design/turn_modulation_record.md)
(section 7), the design the owner decided on 2026-10-15 (its section 8),
whose section 9 summarises where the build departs from the sketches.
Stage 0, the relative strength semantics, landed as f7cfe6a, was
re-validated and gated in both CPU arms with CUDA active and pushed as
c070750 (CI run 454 green, znver4, 29.5 min); its record is
[`crab_cavity_noise_relative_strength_2026_10_15.md`](crab_cavity_noise_relative_strength_2026_10_15.md).
This record carries what stage 1 landed (section 1), the verification plan
as the owner stated it and its numbers (section 2), the examples update
(section 3), the review and its fixes (section 4), the gate (section 5) and
the ledger (section 6). The bracketed
`[...: pending]` markers that stood here for the implementer's, the
verification agent's and the gate's details have all been filled; every verdict carries its number here,
and a `result/` path is not evidence and none is cited as one.

## 1 What landed

The design in one paragraph (D1-D10 of the note): no empty beam; the switch
is the `RunArtifact` keyword `record_turn_modulation = false` beside
`append` and `capacity`, parallel to the task's `record_turn_times`, and
nothing gains a new name; the offsets are recorded (radians on a phase
slot, the dimensionless factor `d` on a strength slot that scales both
planes' strengths of the harmonic), not the realised values; only active
slots, in provenance order; one evaluation shared between the realised
element and the recorder; synchronous through the batched writer; the
layout `/turn_modulation/<slot>/<k>/series` (`turns` rows by active-slot
columns; attributes `columns`, `first_turn`, `turns`) with the nominals as
attributes of each active slot's group (`nominal_phase`,
`nominal_strengthX`, `nominal_strengthY`; on the RF cavity `nominal_phase`,
`nominal_strength`), written with the provenance; the group
`/turn_modulation/<slot>/state` reserved for a future stateful rule and
written by nothing; the readers `turn_modulation_provenance(path)` and
`read(out, :turn_modulation)` keep their shape and each slot entry gains
`series` (`Vector{Float64}`, or `nothing` when the run did not record) and
`nominal` (a NamedTuple of the nominal attributes); rank 0 writes under
MPI; host-side on CUDA.

- The shared evaluation (D5). Per rule container a third method,
  `_realize_draws(rules, base, ctx) -> (element, rules′, draws::Tuple)`
  (the generic declaration and its docstring, `src/elements/turn_modulated.jl`
  lines 613-631; `src/elements/crab_cavity.jl` line 324, the `2N` draws in
  slot order, the `N` phase draws then the `N` strength draws;
  `src/elements/rf_cavity.jl` line 490, the two draws `(dphase, dstrength)`);
  `realize` is its two-element projection (`crab_cavity.jl` line 345,
  `rf_cavity.jl` line 500, each `realised, successor, _ = _realize_draws(...)`).
  The recording form of the hook, `update(elem, ctx, sink)`
  (`turn_modulated.jl` lines 731-749: the `TurnModulated` method calls
  `_realize_draws` once and hands `draws` to `_record_turn_draws!(sink,
  draws)`; the `MisalignedElement`, `RefTilted` and `CompositeLine` methods
  descend with the same sink) and `update_line(line, ctx, sink)` (lines
  776-780); the two-argument forms forward with `sink = nothing` (lines 712
  and 776) and `_record_turn_draws!(::Nothing, ::Tuple) = nothing` (line
  759) IS the plain hook, re-measured by the implementer at zero allocation
  (white and table rules, 2 and 36 elements, 0 B in both forms). The
  nominals: `_slot_nominals(rules, base)` (`turn_modulated.jl` lines
  477-493 generic; `crab_cavity.jl` line 414, harmonic `i`'s `(phase,
  strengthX, strengthY)` for its phase slot `i` and again for its strength
  slot `N + i`; `rf_cavity.jl` line 561, `(phase, strength)` twice). The
  per-turn row's shape comes from `_turn_modulation_columns!(out, elem)`
  (`turn_modulated.jl` lines 917-956), which walks the line in provenance
  order through the wrapper containers and returns, per modulated element,
  `(active, nominal)`: the active slots' indices into the draws tuple and
  their nominals; it joined the wrapper-walk ownership tripwire
  (`test/runtests.jl` line 10187). Tripwires in "Turn modulation: rules,
  wrapper and the pure hook": `container_set(_realize_draws) ==
  container_set(_slot_rules)` and `container_set(_slot_nominals) ==
  container_set(_slot_rules)` (lines 10488-10489), and per container and
  rule that `_realize_draws` projects to `realize` with one draw per
  declared slot equal to `_turn_offset` and one column per active slot
  (lines 10527-10539).
- The recorder and its call sites (D6, D8). `TurnModulationRecorder`
  (`src/tasks/RunArtifact.jl` lines 40-49: `file`, `capacity`, `beam`,
  `keys`, `active`, `buffers`, `cursor`, `rows`), one per beam that has a
  modulated element, built by `_ra_create_turn_modulation_series!` from
  `prepare_run_artifact!` (lines 294-395: the recorders emptied on every
  rank at line 303, `_mp_is_root() || return nothing` at line 308 so a
  non-root rank never holds one, the one switch branch
  `art.record_turn_modulation && ...` at line 383, after the provenance is
  written) and resolved once per `execute!` by `_turn_modulation_sink(art,
  beam)` (lines 536-543: `nothing` without an artifact, with the switch off,
  on a non-root rank or for a beam without a modulated element). The general
  tracking loop of `_execute_tracking_task!` (`src/tasks/Tasks.jl` lines
  1075-1090: `_tm_sink = _turn_modulation_sink(art, 1)` before the first
  turn, then per turn `_tm_begin_turn!(_tm_sink)`,
  `_execute_tracking_plan_turn!(rep, plan, policy, ctx; sink=_tm_sink)`,
  `_tm_end_turn!(_tm_sink, turn)`); the segment methods
  `_execute_tracking_plan_turn!` (line 1801) and
  `_execute_tracking_segment_turn!` (lines 1814-1830, keyword `sink`,
  `update_line(segment.elements[], ctx, sink)` on the host before any device
  conversion). The fast loop is untouched: its predicate requires
  `task.artifact === nothing` (lines 676 and 943). Strong-strong:
  `_execute_strong_strong_turns!` (`src/tasks/strongstrong/interface.jl`
  lines 2824-2874: `sink1` and `sink2` resolved once, `_tm_begin_turn!` on
  both before the blocks, `_tm_end_turn!` on both after) hands the per-beam
  sinks through `_execute_strong_strong_segment_pair!` (line 3073) to
  `_execute_strong_strong_segment!` (line 3101), per beam because the two
  beams interleave block by block; its prepare builds the columns over both
  physics lines, beam 1 then beam 2 (lines 2661-2664). The per-turn
  protocol: `_record_turn_draws!(rec, draws)` (`RunArtifact.jl` lines
  553-566) appends the active slots' values of the next listed element and
  errors on an unlisted one; `_tm_end_turn!` (lines 571-587) checks the
  count, drops a miscounted turn's partial values and raises naming the beam
  and the turn, counts the row and flushes at `capacity`. Off path: one
  `nothing` dispatch per element.
- The `RunArtifact` option (D2). `RunArtifact(path; append=false,
  capacity=64, record_turn_modulation=false)` (`RunArtifact.jl` lines
  177-190), the fields `record_turn_modulation::Bool` (line 155) and
  `turn_modulation_recorders` (line 162); a non-`Bool` refused by
  `ArgumentError("RunArtifact record_turn_modulation must be true or false;
  got ...")` (lines 184-186), not coerced. Metadata: the NEW EXPORT
  `run_artifact_option_schema()` (exported at line 1; lines 194-240:
  `append`, `capacity` and `record_turn_modulation` as
  `ConfigurationOptionMeta`, category `:output`, consumers
  `:strong_strong_output`, `:observer_output` and `:turn_modulation`; the
  receipt itself unchanged per D9) and a `RunArtifact` block of
  `validate_configuration_metadata()` (`interface.jl` lines 2062-2075:
  every key a field of the type, every default equal to a constructed
  artifact's, every option naming a consumer). The strong-strong
  `configuration_report` (lines 2358-2367) prints ", recording the
  turn-modulation series" in the `:artifact` output entry. The
  `?RunArtifact` docstring gained its paragraphs (lines 51-150).
- The writer (D3, D6, D7, D10). `_ra_write_turn_modulation!`
  (`RunArtifact.jl` lines 443-481, its docstring from line 429) writes each
  slot group's `nominal_*`
  attributes from the columns beside `index`, `kind`, `rng_id`, `digest`,
  `name` and `length`, WHETHER OR NOT the switch is on, refusing by name a
  column walk misaligned with the provenance (a different element count or
  a different active-slot count); `_ra_create_turn_modulation_series!`
  (lines 496-527) creates, only when the switch is on and the entries are
  non-empty, `/turn_modulation/<slot>/<k>/series` as an extendable `Float64`
  dataset of zero rows by `ncols` with chunk `(256, ncols)` and the
  attributes `columns`, `first_turn`, `turns`, and builds the recorders;
  `_ra_flush_turn_modulation!` (lines 600-620) appends the complete rows
  turn-major (`set_extent_dims` and one block write per element) and
  flushes the file, every `capacity` turns from `_tm_end_turn!` and at
  `finalize_run_artifact!` (lines 746-753), the values of an unfinished turn
  dropped. The constants `_RA_TM_NOMINAL_PREFIX = "nominal_"` and
  `_RA_TM_STATE = "state"` (lines 484-485); the reserved group is written by
  nothing.
- The readers (D2, D9). `_ra_tm_nominal` (`RunArtifact.jl` lines 1072-1078:
  the `nominal_*` attributes as a NamedTuple in name order, `nothing` for a
  pre-nominal file), `_ra_tm_series` (lines 1090-1106: the columns as
  `Vector{Float64}`s, `nothing` without the dataset; with `data=false` the
  recorded row count stands in for each column), `_ra_turn_modulation(f;
  data)` (lines 1121-1176: the element count skips a `state` subgroup, each
  slot entry is merged with `nominal` and `series`, each execution entry is
  `(execution, elements, state = nothing)`); the table of contents reads
  with `data=false` (line 1376), so `read(out)` stays metadata-only. Torn,
  refused by name: a `series` missing `columns`, `first_turn` or `turns`;
  `columns` not naming the slot groups in index order; a data width other
  than the column count; a recorded element whose slot groups lack
  nominals. The `turn_modulation_provenance` and `read(out, kind)`
  docstrings carry the new fields (lines 1182-1232 and 1236-1275).
- The tests. The new testset "The run artifact records the realised turn
  modulation" (`test/runtests.jl` line 15834; the implementer reports 226 of
  226 on the final tree): the effectiveness plan of the note's section 6.2
  (switch on: the dataset with `turns` rows, the active-slot columns in
  provenance order, the window attributes equal to the receipt's, the
  nominals equal to the spec's, the series equal to the hook's replay
  bitwise and, for a table slot, to the record's entries; switch off: no
  dataset, every other group unchanged; the non-`Bool` refused by name; the
  receipt identical with the switch on and off), the chunking and
  repositioning case of 6.3 (two windows of `n` turns whose concatenated
  series equals one window of `2n`; `start_turn = N` recording `first_turn
  = N`), torn-group and missing-attribute refusals per group and reader
  route, `run_artifact_option_schema()` (line 16010), a strong-strong arm on
  the CPU and a CUDA arm (`_HAS_CUDA && CUDA.functional()`: the series
  bitwise against the CPU's, the device moments equal on and off;
  `@test_skip` without a device). Red on the pre-change source (the
  implementer's run: 11 passed, 1 failed, 6 errored, then aborted --
  `FieldError` for `series`, `state` and `nominal`, slot groups without
  nominals, `MethodError` on the keyword). Extended testsets, the counts the
  implementer reports green on the final tree: rules 436, artifact
  provenance 127, kernel-boundary effectiveness 57, strong-strong window 20,
  RF 147, slot bounds 26, CPU/CUDA identity 39; the extracted sweeps green;
  `validate_configuration_metadata()` true;
  `validate(PublicConfigurationEffectivenessContract())` passed with 30
  metrics. The one-particle probe testset and its fixture
  `test/turn_modulation_probe.jl` are the verification agent's (section 2).
  Not verified by the implementer at landing: the full gate; an MPI two-rank
  run (rank-0-only recording rides `prepare_run_artifact!`'s existing
  `_mp_is_root()` return); CUDA strong-strong recording (the strong-strong
  arm ran on the CPU).
- Cost measured at landing (the implementer's numbers; CPU, 4 threads, 1024
  particles, two crab cavities = 8 active slots, a dispersion element and an
  every-turn `MomentObserver`, 2000 turns, minimum of 2 runs): `capacity =
  64`: off 0.276 s, on 0.298 s, +11.2 us per turn (the HDF5 extend and flush
  every 64 turns, amortised); `capacity = 1024`: off 0.161 s, on 0.159 s
  (noise). File 158607 to 295778 bytes, 68.6 bytes per turn for 8 columns
  (64 of data, the rest the chunked dataset's overhead).
- Documents, this batch: `design/run_artifact.md` (the option among the
  artifact's options, the `series` dataset and the nominal attributes beside
  the provenance text, the reserved `state` group, the readers' added
  fields), `public_api.md` ("Turn Modulation": switching the recording on
  and reading the series back, what the numbers mean, that recording changes
  nothing in the tracking), the record note's status,
  `design/turn_modulation.md` (status and section 4.4), `README.md`,
  `todo.md` (the record-note row; two follow-up rows opened at landing: the
  effectiveness contract's receipt-only pins of the `RunArtifact` options,
  and the two-harmonic pink-plus-table fixture's 1056 B per turn in the
  plain `update_line`, pre-existing), this record; the record note's section
  9 summarises the build. `docs/registry_snapshot.md`: unchanged (the
  implementer's regeneration produced 0 diff lines; the tracked file is
  unmodified in the worktree). Source files of the batch: `src/elements/
  crab_cavity.jl`, `src/elements/rf_cavity.jl`, `src/elements/turn_modulated.jl`,
  `src/tasks/RunArtifact.jl`, `src/tasks/Tasks.jl`,
  `src/tasks/strongstrong/interface.jl`, `test/runtests.jl`. After the
  examples update and the review (sections 3 and 4) the batch also changed
  `examples/crab_cavity_noise.jl`, `test/examples/crab_cavity_noise.jl`,
  `src/examples/Examples.jl`, `validation/crab_cavity_noise_response.jl`,
  the header of `profiling/crab_cavity_noise_backends.jl` (its arms now
  record by the harness default), `docs/experiences.md` (two entries: the
  re-anchored step comparison, section 2.2; the constant-propagation lesson,
  section 4) and added `test/turn_modulation_probe.jl`; the todo row on the
  pink-plus-table fixture closed with the review and a row on the phantom
  ledger row opened (section 4, F4).

## 2 Verification

**2.1 The plan, as the owner stated it.** The instrument is the
one-particle probe of the design note's section 6.1: a line of one thin crab
cavity with THREE harmonics carrying the rules and a `MomentObserver` every
turn; one particle placed by `initial_offset` with a 1e-40 m emittance;
nothing else acts, so `x`, `y` and `z` are constant, the observer's row for
turn `n` is the state right after that turn's kick, and the per-turn step of
the mean `px` is the kick alone, the sum over the harmonics `i` of
`-S_i (1 + d_{i,n}) / (i k) sin(i k z + phi_i + dphi_{i,n})` (the kick
formula of `../theory/crab_cavity_noise_response.md`, section 1, with the
realised parameters of `../design/turn_modulation.md`, section 10). The
initial coordinates are randomised per verification, and the seed is logged
with the result.

One harmonic at a time: a white or a pink rule on harmonic `i`'s strength
and on its phase, the other two harmonics unmodulated, and for each the
three comparisons:

1. Recording on against recording off, same seed and rules: every moment
   column bitwise identical. The switch has no effect on the tracking.
2. The modulated run against the same line with every slot inactive: the
   per-turn steps differ from the first turn. The modulation is consumed.
3. The predicted step, formed from the recorded offsets and the stored
   nominals exactly as the element forms its phase and strength
   (`nominal_phase + dphi_n`, `nominal_strengthX (1 + d_n)`), against the
   observed step: equal to a few ulps. The recorded values are the ones the
   element used.

Then all three harmonics modulated at once, the same three comparisons. The
same probe runs under CPU threads, CUDA and the MPI execution policy
(`MultiProcessExecutionPolicy`, two ranks); across backends the series is
bitwise identical (host-side on every one), the luminosity series is bitwise
between threads and MPI, and the moments stay within the documented fold
bound (`../design/multi_process_policy.md`).

Design-time measurement to compare against (the note's section 2; the CPU,
the example's fundamental strength, `x0 = 1 mm`, `z0 = 1 cm`): the
noise-free per-turn step of the mean `px` is -5.16653e-6, the kick formula
to all printed digits; with `WhiteNoise(1e-5)` on the phase slot the steps
scatter around it and the small-angle inversion returns offsets of rms about
1.2e-5 rad.

**2.2 Results.** Verified 2026-10-15: phase A by a standalone
development script (the hook's replay as the offsets' source, run-twice
determinism as comparison 1, two schedules, 24 of 24; a scratch run, not
retained as evidence, superseded by phase B);
phase B by the suite's testset "Turn modulation: the one-particle probe
verifies the loop per harmonic" with `test/turn_modulation_probe.jl` (the
recorded series as the source, record on against off as comparison 1),
376 of 376 assertions, 0 failures, on acnlinj4 (Xeon Gold 6430, sapphirerapids; RTX 4500 Ada; julia 1.12.4) through the stage runner
(CPU threads, CUDA and the two-rank mpiexec child; the suite's gate owed
before the push). One row per backend; the four verifications share the
seeds and the `initial_offset` listed under the table; comparison 3 is the
predicted row (the previous observed row plus the kick formed from the
recorded offsets and nominals) against the observed row, the largest gap
over the 64-turn window.

| backend | harmonics modulated | rule on strength and phase | seed; `initial_offset` | 1: max abs(moments on - off) | 2: first turn the steps differ | 3: max abs(predicted - observed) step, in ulps | verdict |
|---|---|---|---|---|---|---|---|
| CPU threads (4) | 1; 2; 3; all three | H1 pink/white; H2 white/pink; H3 pink/white; ALL [white, pink, pink]/[pink, white, pink] (phase/strength) | the four seeds and offsets below | 0 (every column bitwise) | turn 0 (px and pz, 64 of 64 turns; py bitwise equal) | 0 ulp (bitwise; the free-running chain bitwise too) | PASS |
| CUDA | same | same | same | 0 (bitwise) | turn 0 (64 of 64) | re-anchored rows within one state ulp plus 1e-14 of the kick: excess <= 2.0e-16 of the kick (px), 0 (pz); at most 3 ulp of px away from a px zero crossing; CPU/CUDA rows 4.3e-19 apart at most | PASS |
| MPI, two ranks | same | same | same (rank 1 holds the particle, rank 0 writes) | 0 (bitwise; the moments bitwise against the CPU arm) | turn 0 (64 of 64) | 0 ulp (bitwise) | PASS |

Seeds and `initial_offset` (x, px, y, py, z, pz), schedule base seed
0x5151202610150007, sigma 1e-5 rad and 1e-4 relative, stream ids 100+i and
200+i: H1 0x4b475bf0fe4a2bba (-8.300504e-04, -7.775496e-06, 6.262527e-04,
6.676420e-06, -3.101754e-03, -8.010894e-05); H2 0x60368548f3e98070
(5.372254e-04, -7.126429e-06, 2.659519e-04, 6.163995e-06, -6.491405e-02,
-1.259249e-04); H3 0x7dcc707df2025d2b (7.859034e-05, -9.609415e-06,
-4.462651e-04, -9.698959e-06, 1.948604e-02, -4.749203e-04); ALL
0x362ef5ddc19d9e87 (-9.831412e-04, -9.908409e-06, 9.802523e-04,
3.343521e-06, 5.135046e-02, 3.762744e-04). The naive step difference reads
27-35 ulp of the px kick and up to 4e3 of the pz kick: the state's one
rounding, which is why the pin re-anchors on the observed row.

Across backends: the recorded series bitwise identical on CPU, CUDA and the
two-rank MPI child (asserted by the testset, 4 of 4 verifications each); no
luminosity series in this probe (no strong beam), the moments compared in
its place, bitwise between threads and MPI (one particle on one rank folds
exactly), the CPU/CUDA moments 4.3e-19 apart at most on px after 64
turns, the identity testset's magnitude (its pin 1e-17). The option's
effectiveness test and the chunking and repositioning case: "The run
artifact records the realised turn modulation", 226 of 226
assertions on acnlinj4 (Xeon Gold 6430, sapphirerapids; RTX 4500 Ada; julia 1.12.4), CPU and CUDA arms both run.

## 3 The examples update

Done 2026-10-15, stage 2 of the note's staging carried by this batch
(owner decision, section 8 item 2: the precedent for reading the series
back). `examples/crab_cavity_noise.jl`: `output.record_turn_modulation =
true` with the reason beside it (the library default stays off; eight
active slots cost 64 MB per million turns), and after the provenance
printout one table per cavity and active slot: label, kind, nominal, series
length, realised rms, requested rms, ratio and the expected band, `1 +-
1/sqrt(2 turns)` (one sigma) for white and table rows and "no pin
(band-limited sum)" for pink rows; a `series === nothing` with the switch
on throws (the configuration-not-read class). `test/examples/crab_cavity_noise.jl`:
toggle `OCTOPUS_RECORD_TURN_MODULATION` (default on) passed into the
artifact; on the rank holding the file the run is refused with the numbers
unless every recorded series has exactly `turns` entries, the recorded slot
set equals the run's active slots, every white series' rms lies within
`max(0.10, 5/sqrt(2 turns))` of its sigma (10 % from 1250 turns on, where
10 % is a five-sigma band; at the suite's 2 turns a bare 10 % pin fails
about 85 % of the time on correct code, the rms of two normals being
`chi_2/sqrt(2)`), and every table series equals the record's first `turns`
entries bitwise; pink rows print their ratio without a pin (`?PinkNoise`:
one sigma 7.65 % at 2^16 turns); with the switch off every slot must read
back `nothing`. The `CRAB-NOISE` line gains, after every pre-existing
field, `record=<bool>` and one `rms_<cavity>_<parameter>_<i>=` per
recorded slot; the profiling driver's and the validation script's parsers
read the old fields unchanged (checked), and the suite parses no field of
that line. The profiling driver strips every `OCTOPUS_*` variable from its
children, so its arms now record by the harness default (8 B per slot per
turn, below the driver's resolution per section 1's cost figures). The
catalogue entry names the recorded offsets. `validation/crab_cavity_noise_response.jl`
part `noise` gains the `recorded` item: per rule a CPU `TrackingTask` of
the two cavities alone, 65536 turns with the switch on, every slot's
series bitwise equal to the hook replay (and, for the table rule, to the
record's first 65536 entries), 6 of 6, three artifacts
`noise_recorded_<rule>.h5`; the part now runs 166 checks, 0 failed, in
137 s wall including the compile.

Three red probes refused for the defect's reason (2000 turns, 1000
macroparticles, the reader monkey-patched): a halved series (`ratio
0.5085, outside 1 +- 0.1`), one dropped entry (`1999 entries for a run of
2000 turns`), a table entry nudged one ulp (`first difference at entry
2`); at 2 turns the halved series passes, as the five-sigma band there is
2.5, which is why the pin needs 1250 turns to see a factor two.

The printed per-slot rms of the default run (2 turns, 10000
macroparticles, white, CUDA chosen by `:auto`), bitwise identical on CPU
threads, CUDA and two MPI ranks (host-side realisation), sigma 1e-5 rad on
the phase slots and 1e-4 on the strength slots:

| slot | realised rms | ratio |
|---|---|---|
| tccb phase_noise[1] | 5.737460512005169e-6 | 0.574 |
| tccb phase_noise[2] | 8.424401877864224e-6 | 0.842 |
| tccb strength_noise[1] | 2.0696456834032818e-5 | 0.207 |
| tccb strength_noise[2] | 6.311293786505961e-5 | 0.631 |
| tcca phase_noise[1] | 7.76125265989294e-6 | 0.776 |
| tcca phase_noise[2] | 5.384103593524791e-6 | 0.538 |
| tcca strength_noise[1] | 6.861063466850236e-5 | 0.686 |
| tcca strength_noise[2] | 7.479028891612164e-5 | 0.748 |

(band `1 +- 0.5` one sigma at 2 turns); at 2000 turns on CPU the eight
ratios were 1.0171, 0.9809, 0.9883, 1.0218, 1.0085, 0.9951, 0.9965,
1.0158, all within `1 +- 0.1` (one sigma 0.0158). The suite's example
testset "Every example script runs against the current interface" ran
green through the stage runner, 21 of 21 in 9m29s (every script exit 0,
the example 82.5 s on CUDA, the harness 58.2 s); the MPI harness testset's
child was reproduced by hand at its exact configuration (1 turn, 4096
macroparticles, 2 threads per rank, exit 0, the artifact written once)
because the runner process lacks `MPICH_jll`; the full gate covers it.
`example_catalog()` lists the five entries, `validate_element_metadata()`
passes. One script defect met on the way: a counter bumped inside a
top-level `for` of the example was a new local (Julia's soft scope in a
file), fixed by counting the rows before the loop.

## 4 The review and its fixes

A read-only review of the recorder diff against the design note's
decisions, run after the verification (2026-10-15), found the logic sound:
one evaluation (`update(w, ctx, sink)` is the only per-turn caller of
`_realize_draws`), the turn alignment (row `i` is turn `first_turn + i - 1`
in both loops; non-zero windows and a second `execute!` on the same task
probed), the walk order (the five wrapper methods of
`_turn_modulation_columns!` sit in the ownership tripwire, segments follow
line order, recorders are per beam), the fast loop unreachable with an
artifact, loud drops (the miscount raises, the crash path finalizes complete
rows, non-root ranks hold empty recorders), MPI and CUDA (the rules key on
seed, method, turn, `rng_id` and slot only; realisation host-side; no sink
captured by a closure), the arity (every caller updated), the readers (a
pre-change file reads `nominal === nothing`; the torn cases are refused by
name on all three routes) and the HDF5 pattern. Five findings, all fixed in
the batch:

- F1 (medium, confirmed by measurement): the shared evaluation built the
  draws with `ntuple(i -> _turn_offset(rules.phase[i], ctx, i, T), Val(N))`,
  whose per-index type needs constant propagation into the closure; on a
  MIXED container (a `nothing` beside an active rule, or a pink slot) Julia
  skips it and the draws tuple boxes. Bytes per call, main checkout c070750
  / before the fix / after, for `realize`, `update` and a 40-element line's
  `update_line`: crab `(nothing, WhiteNoise)` phase 336 / 688 / 0, 640 /
  720 / 0, 12800 / 14400 / 0; `(nothing, PinkNoise)` phase 352 / 720 / 0,
  656 / 736 / 0, 13120 / 14720 / 0; the suite's white-pink-plus-table
  fixture 576 / 1024 / 0, 976 / 1056 / 0, 19520 / 21120 / 0; `(nothing,
  TurnTable)` strength, `(WhiteNoise, WhiteNoise)` and both RF shapes 0 in
  all three trees. The 640 B on the main checkout is the pre-existing
  neighbour defect the todo row of the same day had recorded (now closed):
  the design's "0 B" row held for homogeneous containers only, which is why
  the suite's 40-crab pin on `(WhiteNoise, WhiteNoise)` could not fail. Fix:
  three `@inline @generated` helpers in `src/elements/turn_modulated.jl`
  (`_slot_draws`, `_slot_values`, `_slot_successors`) unroll with literal
  indices, the `fusedTrack` precedent, and `_realize_draws(::CrabCavityNoise,
  ...)` is rebuilt on them. `Base.map` over tuples was rejected: it takes a
  `Vector{Any}` path from 32 entries on (592 B at exactly 32 entries, 0 at
  31, Julia 1.12.4), the pink stride bound's accepted edge. The RF container
  holds two concretely typed scalars, was 0 B in every tree, and is
  unchanged. Inferred return after the fix: `Tuple{ThinCrabCavity{2,...},
  CrabCavityNoise{Tuple{Nothing,PinkNoise{Float64}},Tuple{Nothing,Nothing}},
  NTuple{4,Float64}}`, no `Union`. The zero-allocation pin of "Turn
  modulation: rules, wrapper and the pure hook" now covers four named shapes
  (`(nothing, WhiteNoise)` phase, `(nothing, PinkNoise)` phase, `(nothing,
  TurnTable)` strength, the white-pink-plus-table fixture), each a
  40-element line, on the plain hook and on the hook with a recorder sink,
  with type preservation and the sink having met all 20 wrapped elements;
  red on the unfixed tree for the defect's reason (458 passed, 6 failed,
  every failure an allocation pin: 14400, 15360, 14720, 15680, 21120 and
  22080 B against 0), green after the fix, 464 of 464.
- F2 (low, confirmed): a series shorter than its `turns` attribute read
  back silently. The readers' element entry gained `first_turn` and
  `turns`, and the series reader warns per read, by name, when the row
  count is below `turns` ("the run was stopped before its window completed;
  the rows are read as they stand and the row count is authoritative"); a
  `TrackingTask` without strong beams stamps the ledger's `current_turn`
  only at finalize, the strong-strong loop before each turn, closing the
  series row after it (`design/run_artifact.md`). Test: a copy of a recorded
  file shrunk to one row warns exactly once on all three reader routes, and
  intact files log nothing.
- F3 (low): the schema named `:turn_modulation` as the consumer of
  `record_turn_modulation`, but that receipt never carries the value (D9).
  The `:strong_strong_output` receipt now carries `record_turn_modulation`
  beside `artifact` and `append`, the schema names it as the consumer, and
  its docstring states that the weak-strong `TrackingTask` has no output
  receipt and that its evidence is the artifact file (the testset); the
  `:turn_modulation` receipt is unchanged, so the probe's receipt-identity
  assertions hold. No test had pinned that receipt's shape; one does now
  (`propertynames == (:artifact, :append, :record_turn_modulation)`).
  `validate_configuration_metadata()` is true and the effectiveness
  contract passes (74.8 s). D2 of the design note carries a dated remark:
  the schema export `run_artifact_option_schema()` is the one new name,
  required by the schema-export tripwire.
- F4 (test gaps; behaviour probed correct): the recorder's testset gained
  strong-strong with only one beam modulated, either beam (one element
  group, the modulated beam, series equal to the replay), and the refusal
  by name of `prepare_run_artifact!` called with provenance but default
  empty columns. Observation left as a todo row: that refusal fires after
  the ledger row was appended, so the closed file keeps a ledger row with
  no provenance group, on an internal path `execute!` never takes.
- F5 (information): series and nominals are stored as Float64 of the
  element's `T`; the reader docstring and `design/run_artifact.md` say so.

After the fixes, on the final tree through the stage runner (package mode,
four threads, CUDA active, the launcher present): rules 464, recorder 268,
provenance 127, strong-strong window 20, RF 147, kernel boundary 57,
CPU/CUDA identity 39, the one-particle probe 376 (CPU, CUDA and the
two-rank arm), schema export 15, each passed in full; the extracted sweeps
(the stage 6 pin tripwire, the `Core.Box` sweep, the detached-docstring
sweep) exit 0. `docs/experiences.md` gained the lesson: a per-index type
that depends on constant propagation, the `map` cliff at 32 entries, and a
homogeneous fixture as a pin that cannot fail.

## 5 Verification and gate

Matrix classes, to be read from the diff once it exists: public
configuration (an artifact option: `validate_configuration_metadata()` and
`validate(PublicConfigurationEffectivenessContract())` in the full lane);
concurrency surfaces (both turn loops, the strong-strong loop, rank 0
writing under MPI: the full gate at four threads, thread-count invariance of
the series); CUDA-reachable code: no kernel changes, the realisation and the
recording are host-side and nothing new crosses to the device, but the turn
loops that launch the kernels change, so the CPU/CUDA identity testset and
the backend-consistency scripts run and the gate runs with CUDA active;
contracts and acceptance (every test probing the artifact's groups and
readers found first; the effectiveness contract's own `validate`); examples,
where stage 2's example change rides the batch (the script runs; the
catalogue entry); docs plus source: the full gate. The gate is the full gate
at four threads, CUDA active, in both CPU arms (native and the AVX2 parity
arm) on the batch's final tree before the push, as the stage 0 record's
section 5 ran it (its baseline: 332 rows and 149397 assertions per arm on
f7cfe6a).

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. --threads=4 \
  -e 'using Pkg; Pkg.test(julia_args=["--threads=4", "-C", "haswell"])'
```

Run 2026-10-15 on 77c0bcc, the batch's commit (`git status` clean at
the start of the native arm and of the first AVX2 attempt; the AVX2 rerun
started with one uncommitted file, `docs/todo.md` carrying the row on the
race described below, markdown that no test reads and that the record
commit carries), host acnlinj4 (Xeon Gold 6430, sapphirerapids; RTX 4500 Ada;
julia 1.12.4), four threads, CUDA active: every CUDA-gated testset reports
its assertions and neither green log carries a skipped, not-exercised or
lane-skip line. Before it, on the same tree: the extracted sweeps (the
stage 6 pin tripwire, the `Core.Box` sweep, the detached-docstring sweep,
2 of 2 each, exit 0) and the fast lane (318 rows, 147925 assertions passed and one
`@test_skip`, the RF testset's second-thread tripwire that both full arms
ran, 147 of 147; 16 loud lane skips, the sixteenth the probe's two-rank
arm; 19:12:58 to 19:32:49 EDT); the registry snapshot regenerates identical to the
tracked file.

| arm | start (EDT) | end (EDT) | rows | assertions | exit |
|---|---|---|---|---|---|
| native | 19:33:47 | 20:23:56 | 334 | 150148 of 150148 | 0 |
| AVX2 parity (`OPENBLAS_CORETYPE=Haswell`, `-C haswell`), started together with the native arm | 19:33:47 | 19:58:07 | 171 before the abort | 113903 of 113903 before the abort; "Every example script runs against the current interface" 20 of 21 | 1 |
| AVX2 parity, rerun alone | 20:24:30 | 21:14:15 | 334 | 150148 of 150148 | 0 |

Against the stage 0 baseline (332 rows, 149397 assertions per arm) the
batch adds two rows (the recorder's testset and the one-particle probe)
and 751 assertions. The concurrent AVX2 attempt failed on one
assertion, `leftover == String[]` of the example testset, evaluated to
`["123456789/.nfs0000000093de6d910000aa4d"]`: both arms ran in the same
worktree, the clean examples write under its `result/<seed>/`, and the
AVX2 arm's cleanup unlinked the crab-noise artifact while the native arm's
example still held it open, so NFS renamed the file in place and the
cleanup saw a leftover. Every script of that testset had exited 0 in both
arms, the native arm's run of the same testset passed 21 of 21 once the
AVX2 process had exited, and the rerun of the AVX2 arm alone passed it; a
`docs/todo.md` row records the race (two suites in one worktree) with the
candidate fix, and the gate procedure runs the arms one after the other
from now on. Nothing was skipped in either green arm. Not verified: CI on
this tree (it runs after the push; CI has no GPU, so it covers the CPU
testsets only), and the strong-strong recorder on CUDA (the recorder's
CUDA arm covers the weak-strong task; its strong-strong arm runs on CPU,
the design note's section 9 says so).

## 6 Ledger

- `docs/todo.md`: the record-note row's state reads "stage 1 implementation
  landed and probe-verified 2026-10-15, the examples update landed and the
  implementation reviewed and fixed the same day, gated 2026-10-15 in both
  CPU arms with CUDA active, awaiting the push" with stage 0 "landed as f7cfe6a, pushed as c070750"; the
  turn-modulation row's stage 0 clause likewise; two rows opened at landing
  (the effectiveness contract's receipt-only pins of the `RunArtifact`
  options; the two-harmonic pink-plus-table fixture's 1056 B per turn in the
  plain `update_line`). The row "Stateful
  turn-modulation rules: checkpoint reserved, restart semantics owed"
  (opened 2026-10-15 with the design) exists and, with D10, is the hand-over
  for the reserved `/turn_modulation/<slot>/state` group; nothing in this
  batch writes it.
- `docs/experiences.md`: one entry from the verification, "A per-turn
  step compared as a row difference carries the state's rounding": a step
  compared as a row difference carries the state's rounding (27-35 ulp of
  a px kick), so a kick-level pin re-anchors on the observed row; and an
  ulp metric on a free-running state means nothing where that state
  crosses zero. Both lessons also stand in section 2.2 and the testset's
  header.
- Documents changed in this batch: section 1's documents bullet.
- Markers: the implementation markers of section 1 were filled on
  2026-10-15 from the implementer's report, each structural fact checked
  against the source and the runtime numbers attributed to the implementer's
  runs; the verification results of section 2.2 are the probe agent's; the
  examples results of section 3 are the examples agent's; the
  gate section was filled from the two arms' logs after the run (the
  record commit); the status line changes to the push when it lands.
