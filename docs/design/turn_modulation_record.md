# Recording the realised turn modulation in the run artifact

> **Status: designed 2026-10-15 in owner discussion, its four open questions
> decided by the owner the same day (section 8); stage 0 of section 7 (the
> relative strength semantics) landed as f7cfe6a, re-validated and gated,
> pushed as c070750 (CI run 454 green), record
> `../history/crab_cavity_noise_relative_strength_2026_10_15.md`; stage 1
> implementation landed 2026-10-15 (the recorder, the
> `record_turn_modulation` option with its metadata query
> `run_artifact_option_schema()`, the writer and the readers; section 9
> says where it departs from the sketches) and verified the same day by the
> one-particle probe on CPU threads, CUDA and two MPI ranks (the record's
> section 2.2), the examples update landed and the implementation reviewed
> and fixed the same day (the record's sections 3 and 4), committed as
> 77c0bcc, gated in both CPU arms with CUDA active and pushed as a710f5a 2026-10-15 (CI run 455 green: znver3, 36 min, identity pins 6 of 6, CPU testsets only),
> record
> `../history/turn_modulation_record_2026_10_15.md`; stage 2 of section 7,
> the examples update (the harness toggle, the example's `output` switch,
> the validation reading the public series), carried by the same batch,
> the record's section 3 -- this status read "stage 2 not implemented"
> until the 2026-10-16 neighbour audit.** This
> note records the decisions for recording, turn by turn, the offsets the
> turn-modulation rules produce during a run, so that a reader of the run
> artifact can verify that `execute!` realised a new value every turn and
> that the tracking consumed it. It extends `turn_modulation.md` (the
> wrapper, the pure hook, the rules, the provenance) and
> `run_artifact.md` (the one-output-file-per-task sink). The implementation
> is a full-gate batch with its own record; the owner questions of section
> 8 are decided before it starts.

## 1. The problem

A run with `phase_noise` or `strength_noise` rules leaves two traces today.
The `:turn_modulation` execution receipt, recorded inside
`with_execution_audit`, says which elements were modulated, which slots
carried which kind of rule with which stream id, and over which turns. The
artifact's `/turn_modulation/<execution slot>` group records the same
provenance per `execute!` window, with a table rule's name, length and
digest. Neither carries the numbers the rules produced: a reader cannot
tell white from pink, cannot check that the sequence the kick saw is the
one the rule was asked for, and cannot correlate the drive with the
per-turn luminosity or moments.

Until now that check has been made with internal helpers: the validation
study (`../history/crab_cavity_noise_validation_2026_10_14.md`, section 4)
realises every slot through the pure hook with a `TrackingContext` and
compares the sequences with their specification. That proves the rules,
not the loop: it never shows that the turn loop of `execute!` handed a new
realisation to the element on every turn, nor that the element's kick used
it. The owner asked for both to be verifiable from a run's artifact alone,
through the public surface, and for the cost to stay nil.

## 2. What exists

- The wrapper `TurnModulated{E,R}` holds `base` (compiled from the spec,
  the nominal) and `inner` (the realised element of the current turn). Each
  turn the pure hook `update_line` rebuilds the fused tuple: every wrapper's
  `realize(rules, base, ctx)` evaluates its active slots' rules at the
  absolute turn through `_turn_offset(rule, ctx, slot, T)`, adds the draws
  to the nominal parameters and returns the realised element and the
  successor rules. Every realisation starts from `base`; offsets never
  accumulate; the nominal changes only through a spec change (a knob bumps
  the spec epoch and the next `execute!` recompiles). Measured cost of the
  rebuild: about 2 us for twenty wrapped cavities.
- The slot protocol: `_slot_rules(container)` lists the active slots as
  `(label, rule)` pairs; inactive `nothing` entries produce no slot. The
  crab cavity has one slot per active harmonic for the phase and one for
  the strength; the RF cavity two scalar slots. The provenance walk and the
  artifact writer enumerate exactly these.
- The artifact (`run_artifact.md`): `RunArtifact(path; append=false,
  capacity=64)`, one HDF5 file per task, one group per producer, rows
  batched `capacity` at a time, `/turn_modulation/<slot>/<k>/<label>` groups
  with the attributes `element_count`; `element`, `beam`, `slot_count`;
  `index`, `kind`, `rng_id`, `digest`, `name`, `length`, and since 2026-10-21
  `sigma` and `octaves` (the live rules' free parameters, 0.0 and 0 for the
  kinds without them; comprehensive audit F-66), written per
  execution slot and never deleted. Readers:
  `turn_modulation_provenance(path)` and `read(out, :turn_modulation)`.
- The audit: `with_execution_audit(f)` binds a scoped value while `f` runs;
  consumer boundaries append receipts; outside a block nothing is recorded.
  Receipts are proof that a configuration was consumed, not a data channel;
  the effectiveness contracts wrap runs in audits as a matter of course.
- A one-particle probe is possible today: `Beam(1, policy, Float64; emit =
  (1e-40, 1e-40, 1e-40), initial_offset = (x0, px0, y0, py0, z0, pz0), ...)`
  places one particle at the offset; a line of one crab cavity and a
  `MomentObserver` records its coordinates every turn. Measured 2026-10-15
  on the CPU with the example's fundamental strength, `x0 = 1 mm`, `z0 = 1
  cm`: without noise the per-turn step of the mean `px` is -5.16653e-6, the
  kick formula `-S sin(k z)/k` to all printed digits; with `WhiteNoise(1e-5)`
  on the phase slot the six steps scatter around it and the small-angle
  inversion returns offsets of rms about 1.2e-5 rad.

## 3. Decisions

**D1. No empty beam.** The realised offsets are a pure function of the
rules, the seed, the RNG method and the absolute turn; no particle takes
part in producing them. A zero-particle `Beam` would touch every path that
divides by the count or reduces over it (statistics, luminosity, the shard
split across ranks, the CUDA launches) for a capability that needs none of
that. `Beam` keeps refusing a non-positive count; the one-particle probe of
section 6 is the verification instrument.

**D2. The switch lives on the run artifact, and nothing gains a new name.**
Recording is an output option of `RunArtifact`, the keyword
`record_turn_modulation = false` beside `append` and `capacity` (decided
2026-10-15; the verb-noun form parallels the task's `record_turn_times`),
off by default. It is not a keyword of
`with_execution_audit`: the audit is a proof instrument, and tying output to
it would make a run's artifact depend on whether a contract or a user
happened to wrap the run. No new function appears: the recorded data is
read through the existing `turn_modulation_provenance(path)` and
`read(out, :turn_modulation)`, whose per-slot entries gain the fields the
recording adds and hold `nothing` when the run did not record. A new
public option lands as every public option does (AGENTS.md Invariants):
runtime consumer, structured metadata, inactive and invalid behaviour, an
effectiveness test at the consumer boundary.

*Remark (2026-10-15, review of stage 1, F3).* One new name did land with
the option: the exported metadata query `run_artifact_option_schema()`,
which the suite's schema-export tripwire requires ("every public
configuration schema is exported", `test/runtests.jl`: every
`*_option_schema` binding of the module must be exported) and which D2 did
not foresee; no reader name was added. The option's declared consumer was
the `:strong_strong_output` receipt, which carried `record_turn_modulation`
beside `append` and the artifact path since the same review (the
`:turn_modulation` receipt stays unchanged, D9; naming it as the consumer
had declared a boundary that carried nothing), while the weak-strong
`TrackingTask` recorded no output receipt at all. *Superseded 2026-10-16
(the crab-noise neighbour audit's fix batch, S4-1/S4-2):* the declared
consumer of all three artifact options is the `:run_artifact_output`
receipt `prepare_run_artifact!` records once per `execute!` under both task
kinds, carrying `record_turn_modulation` beside what it RESOLVED
(`recording`: recorders built, the switch on AND a modulated element) and
`append` beside `continued`; the `TrackingTask` records `:tracking_output`
and the strong-strong receipt moved after the prepare
(`run_artifact.md`, "The output receipts"). The evidence of effect stays the
artifact file -- the `series` dataset present exactly when the option is on
-- as the suite's recorder testset reads it.

**D3. The offsets are recorded, not the realised values.** The offset is
the rule's output and the primary datum: it exists before any element is
built, and for a table it is the record entry at the turn's index. The
realised phase or strength, nominal plus offset, is a derived quantity and
is exactly what the verification reconstructs and checks against the
tracking; recording it would record the thing under test. The nominal
parameters of every active slot (the phase, and both planes' strengths) are
stored once per execution slot beside the labels, so a reader forms the
realised values, `phi0 + d` on a phase slot and `S (1 + d)` on a strength
slot under the relative semantics of section 5. Floating point agrees:
`(S + d) - S` is not bitwise `d`, so an offset derived from element fields
would miss a replay by a relative 1e-12, while the recorded `d` with the
stored `S` reproduces the element's value exactly.

**D4. Only the generated data.** The series has one column per ACTIVE
slot, in provenance order, labelled as the provenance labels the slot;
inactive `nothing` entries and unmodulated elements contribute nothing, as
they contribute no provenance entry today.

**D5. One evaluation, shared.** The hook computes the draws, builds the
realised element from them and, when the switch is on, hands the same
draws to the recorder. The recorder never reads the compiled element and
never re-evaluates a rule, so the recorded sequence and the one the element
used cannot disagree by construction, and the per-turn cost is a few
copies.

**D6. Synchronous, through the batched writer.** The values are already on
the host every turn (the rules never reach the device); recording appends
one row of `Float64` per active slot to the artifact's row buffer and
flushes with the configured `capacity`, the path the luminosity and
moments rows take. No asynchronous writer: it would open a concurrency
surface (the HDF5 writer is single-threaded by design) to hide the latency
of 64 bytes per turn.

**D7. Layout and semantics.** Under the execution slot's group, one
two-dimensional dataset `/turn_modulation/<slot>/<k>/series` of `turns`
rows by active-slot columns, with the attributes `columns` (the labels in
order), `first_turn` and `turns` (the window, as the receipt records them),
and the per-slot `nominal` attributes (`phase`, `strengthX`, `strengthY`
for a crab slot; the RF cavity's twins). Row `i` holds the offsets applied
on absolute turn `first_turn + i - 1`: radians on a phase slot; on a
strength slot the dimensionless relative factor `d` that scales both planes'
strengths of the harmonic, `S_X (1 + d)` and `S_Y (1 + d)` (section 5). Execution-slot groups are never
deleted, so chunked and repositioned runs stack as the provenance does
today, and a knob change between windows shows up as a different nominal
in the next slot.

**D8. Backends and tasks.** Every MPI rank realises the same values from
the same keys; rank 0 writes, as it writes the other producers. On CUDA
the realisation is host-side already; nothing crosses to the device. The
strong-strong task records both beams' lines through the same path,
labelled by beam as its provenance entries are.

**D10. Space reserved for rule state, nothing written today.** A stateful
rule, one whose successor differs from the rule (design D6 of the parent
note: an IIR filter, a counter), would have to resume across `execute!`
calls from where it stopped, and today both turn loops restart a successor
at a call or plan boundary (the stage 4 audit, lead U1-1). No shipped rule
is stateful and a tripwire pins it, so the recorder writes offsets only.
The artifact nevertheless reserves the place a future implementation uses:
one group `/turn_modulation/<slot>/state` per execution slot, written once
after the window's last turn by stateful rules only, holding one dataset
per stateful slot under the slot's label, a checkpoint and not a per-turn
series (any intermediate state is regenerable by replaying the recorded
offsets through the rule). Absent today; the readers return `nothing` for
it. Its contents and the restart semantics of the loops are designed
together with the first stateful rule; this paragraph and the todo row are
the hand-over.

**D9. What stays as it is.** `with_execution_audit`, the receipts and their
contents; the rules and the slot protocol; the realised element's
construction; the artifact's existing groups and readers' return shapes
except for the added fields.

## 4. Cost

| item | measured or derived | source |
|---|---|---|
| per-turn rebuild of twenty wrapped cavities | about 2 us, 0 B | `turn_modulation.md` section 7 |
| recording per turn | a few copies into the row buffer | D5, D6 |
| file growth | 8 bytes per active slot per turn: 8 MB per million turns per slot; 64 MB per million turns for the example's eight active slots | arithmetic |
| the example's moments table for comparison | 27 columns (the `MomentObserver` default moment set, `src/tasks/BeamObservers.jl`), 27 x 8 = 216 bytes per turn | arithmetic |
| per-turn tracking time the recording competes with | 3 ms (CUDA, 1e5 particles), 26 ms (CUDA, 1e6), 119 ms (16 threads, 1e5) | `../history/crab_cavity_noise_mpi_benchmark_2026_10_14.md` |

The file growth is the reason the default is off. Nothing above is
measurable in a per-turn timing; the effectiveness test of section 6
nevertheless pins the absence of any effect on the tracked coordinates.

## 5. Interactions

- **Knobs.** The nominal is the compiled spec parameter; a knob change
  recompiles at the next `execute!` and the new nominal is recorded with
  that window's execution slot, while the offsets are unchanged (verified
  for the knob case in the stage 4 audit).
- **The strength rule's action on the two planes** (decided 2026-10-15,
  owner): one voltage driver excites a cavity's horizontal and vertical
  kick, so one relative amplitude error scales both, `S_X (1 + d)` and
  `S_Y (1 + d)`; a second driver is a second cavity. The shipped additive
  semantics, one absolute offset added to both strengths, made a horizontal
  cavity kick vertically (the theory note predicted 0.87 of the horizontal
  rate, the sweep measured 1.16 with the beam-beam coupling) and is replaced
  by the relative scaling on the crab cavity and the RF cavity alike. The
  record stores the factor `d` and both nominals. Falsifier: horizontal
  amplitude noise grows no vertical emittance without beam-beam.
- **The amplitude-noise convention.** Under the relative semantics the
  rule's sigma IS the relative rms: the example hands `1e-4` over directly
  and drops its multiplication by the nominal strength; a strength table
  holds relative factors. The record stays in the rule's unit, the
  dimensionless factor, and the reader forms `S (1 + d)` from the stored
  nominal.
- **Tables.** The recorded series equals the table's entries over the
  window, which verifies the index mapping (`first_turn` to entry
  `first_turn + 1`) on a real run rather than by the compile-time length
  check alone.

## 6. Verification plan

**6.1 The one-particle probe, three comparisons.** A line of one crab
cavity carrying the rules and a `MomentObserver` every turn; one particle
placed by `initial_offset` with a 1e-40 m emittance; `z` constant since
nothing else acts, so the observer's row for turn `n` is the state right
after that turn's kick and the per-turn step of the mean `px` is the kick
alone. The probe is `test/turn_modulation_probe.jl`, functions only, included
by the suite's testset "Turn modulation: the one-particle probe verifies the
loop per harmonic" for the CPU and CUDA arms and run as that testset's
two-rank `mpiexec` child.

1. Recording on against recording off, same seed and rules: every moment
   column bitwise identical. The switch has no effect on the tracking.
2. The modulated run against the same line with every slot `nothing`: the
   steps differ from the first turn. The modulation is consumed.
3. The predicted step `-(S/k) sin(k z + phi0 + dphi_n)`, formed from the
   recorded offset and the stored nominal exactly as the element forms its
   phase, against the observed step: equal to a few ulps. The recorded
   values are the ones the element used.

The same probe runs under CPU threads, the MPI execution policy (two ranks)
and CUDA with the same three comparisons; across backends the series is
bitwise identical (it is host-side on every one), the luminosity series is
bitwise between threads and MPI, and the moments stay within the documented
fold bound (`multi_process_policy.md`).

**6.2 The option's effectiveness test.** Switch on: the dataset exists with
`turns` rows, the active-slot columns in provenance order, the window
attributes equal to the receipt's, the nominals equal to the spec's, and
the series equal to the hook's replay bitwise and, for a table slot, to the
record's entries. Switch off: no dataset, every other group unchanged. An
invalid value is refused by name. The receipt is identical with the switch
on and off.

**6.3 Chunking and repositioning.** Two windows of `n` turns record two
execution slots whose concatenated series equals one window of `2n`; a run
repositioned with `start_turn = N` records `first_turn = N` and the
entries from `N` on.

**6.4 Matrix classes.** Public configuration (an artifact option):
`validate_configuration_metadata()` and
`validate(PublicConfigurationEffectivenessContract())` in the full lane;
concurrency surfaces (both turn loops, the strong-strong loop, rank 0
writing under MPI): the full gate at four threads; the two-arm gate with
CUDA active before the push, recorded in the batch's history record.

## 7. Staging

0. The semantics change decided in section 5: the strength rule scales both
   planes relatively on the crab cavity and the RF cavity (`realize`, the
   `ParamMeta` unit, the tests pinning strength offsets, the kernel-boundary
   effectiveness test), the example and harness handing the relative rms
   over directly, the theory note's amplitude section and production-point
   table reworded, and the validation study's amplitude arms re-run (A05,
   A1, A2, A4, A4s, AP1, AT1, C2 and the covariance control; about an hour
   on the GPU) with a new dated record; a full-gate batch before stage 1.
1. The recorder in both tracking loops and the strong-strong loop, the
   `RunArtifact` option with its metadata, the writer and the extended
   readers, the one-particle probe testset with the three comparisons, the
   effectiveness test, and the documents (`run_artifact.md`,
   `public_api.md`, this note's status, the parent note's section 4.4).
2. The harness toggle `OCTOPUS_RECORD_TURN_MODULATION`, the example's
   `output` block gaining the switch (its two-turn default run records, as
   the precedent for reading the series back), and the validation study's
   noise part reading the recorded series through the public reader
   instead of the internal replay where it can.

## 8. Decisions taken by the owner (2026-10-15)

1. **Name.** `record_turn_modulation`, parallel to the task's
   `record_turn_times`.
2. **Default.** Off; the example's default run switches it on as the
   precedent for reading the series back.
3. **Strength rule.** Relative scaling per harmonic, `S (1 + d)` on both
   planes, on the crab cavity and the RF cavity alike: one voltage driver
   per cavity, two drivers are two cavities. Without beam-beam, horizontal
   amplitude noise excites no vertical emittance growth; that is a falsifier
   of the implementation. Replaces the additive both-planes default of
   2026-10-12 (parent note, section 10).
4. **Rule state.** Offsets only; the artifact reserves one checkpoint group
   per execution slot for a future stateful rule (D10), written by nothing
   today, so that the implementation of the first stateful rule picks up
   from this note and the todo row.

## 9. Stage 1 as built (2026-10-15)

Where the implementation departs from or sharpens the sketches above; the
record `../history/turn_modulation_record_2026_10_15.md` carries the code
locations, the tests and the measurements.

- **The shared evaluation (D5)** is a third method per rule container,
  `_realize_draws(rules, base, ctx) -> (element, rules′, draws)` (the crab
  cavity's `2N` draws in slot order, the RF cavity's two), and `realize` is
  its two-element projection. The recording form of the hook is
  `update(elem, ctx, sink)` / `update_line(line, ctx, sink)`; the
  two-argument forms forward with `sink = nothing`, whose
  `_record_turn_draws!` is a no-op, so the plain hook is unchanged in type
  and allocation. The nominals come from a sibling `_slot_nominals(rules,
  base)` per container (the harmonic's `(phase, strengthX, strengthY)` on
  both of its slots; the RF cavity's `(phase, strength)`), collected with
  the active-slot indices by `_turn_modulation_columns!` over the line in
  provenance order; tripwires pin that the three per-container methods are
  declared on the same set of containers and that `_realize_draws` projects
  to `realize` with one draw per declared slot.
- **The recorder (D6, D8)** is `TurnModulationRecorder`, one per beam with a
  modulated element, built by `prepare_run_artifact!` on rank 0 when the
  switch is on, resolved once per `execute!` and handed to the segments of
  the general tracking loop and of the strong-strong loop (per-beam sinks,
  since the two beams interleave block by block); a per-turn protocol
  (`_tm_begin_turn!`, `_tm_end_turn!`) checks that every listed element was
  met exactly once and drops a miscounted turn loudly rather than writing a
  misaligned column; the flushes every `capacity` turns and at finalize
  write complete rows only. The fast tracking loop is untouched: it is never
  taken with an artifact.
- **The option (D2)** refuses a non-`Bool` by an `ArgumentError` naming the
  keyword and the value, and the strong-strong `configuration_report`
  prints it in the `:artifact` output entry. One name D2 did not foresee was
  added: the exported metadata query `run_artifact_option_schema()`,
  describing `append`, `capacity` and `record_turn_modulation` as
  `ConfigurationOptionMeta` (the structured metadata the Invariants require
  of every public option; `append` and `capacity` had shipped without one),
  checked by a `RunArtifact` block of `validate_configuration_metadata()`.
  No reader name was added, as D2 requires; the `:turn_modulation` receipt
  is unchanged (D9), while the `:strong_strong_output` receipt carries the
  option beside `append` since the 2026-10-15 review (F3; the remark under
  D2).
- **The readers after the review (2026-10-15, F2)**: each element entry
  carries `first_turn` and `turns` from the `series` dataset's attributes
  (`nothing` when the run did not record), and a series shorter than its
  `turns` -- a run stopped before its window completed -- is read as it
  stands with one warning naming the dataset; the row count is
  authoritative (before, such a file read back silently).
- **The layout (D3, D7)**: the nominal attributes are written by the
  provenance writer at prepare whether or not the run records, so a
  switch-off run differs from a pre-stage-1 file only by them; the `series`
  dataset is extendable, chunked `(256, ncols)`, created with zero rows. The
  reserved `state` group (D10) is skipped by the readers' element count.
- **The readers (D2, D9)**: each slot entry gains `nominal` (`nothing` only
  for a pre-nominal file) and `series` (`nothing` when the run did not
  record); each execution entry gains `state = nothing`; the table of
  contents stays metadata-only, its `series` field the recorded row count.
  Torn by name: a `series` missing `columns`, `first_turn` or `turns`,
  `columns` not naming the slot groups in index order, a data width other
  than the column count, a recorded element without nominals.
- **Cost (section 4)**, measured at landing on the CPU (4 threads, 1024
  particles, 8 active slots, 2000 turns): +11.2 us per turn at
  `capacity = 64` (the HDF5 extend and flush every 64 turns), within noise
  at `capacity = 1024`; 68.6 bytes per turn for 8 columns, the 8 bytes per
  slot per turn plus the chunked dataset's overhead. The recorder's row
  buffers are sized at creation since 2026-10-16 (`sizehint!` to `capacity`
  turns of the element's active columns; U9-5 of the crab-noise neighbour
  audit measured their growth by doubling at about 580 bytes per turn
  averaged on a 20-element line, 1568 bytes over 62 turns on the suite's
  two-column fixture), so the recording hook is allocation-free below the
  flush, as "a few copies into the row buffer" reads; the suite pins it.
- **The partial slot (owner decision 2026-10-16; the stage 3-4 audit's
  U5-2).** A writer stopped by an HDF5 error mid-prepare leaves a
  `/turn_modulation/<slot>` group half-created; decided: the reader reports,
  nothing rolls back. The slot group carries the cursor
  `elements_valid_through` (0 at creation, advanced after each element group
  is complete, its `series` dataset included -- the dataset is created
  inside the provenance writer's per-element loop now, the recorders built
  over it afterwards); a cursor behind `element_count` marks a PARTIAL slot,
  which every reader reads as far as the cursor with one warning naming it
  and which `append=true` refuses by name. `run_artifact.md`, "The partial
  provenance slot", is the full statement.
- **The receipts (2026-10-16, S4-1/S4-2; the remark under D2).** The
  artifact's three options name the `:run_artifact_output` receipt the
  prepare records with the request and the resolution (`continued`,
  `recording`, `capacity`, `execution`), under both task kinds; the
  `TrackingTask` records `:tracking_output` (path, channels, `loss_report`),
  the strong-strong `:strong_strong_output` (path, channels) after the
  prepare. The `:turn_modulation` receipt is unchanged (D9).

## 10. References

- `turn_modulation.md`: the wrapper, the pure hook, the rules, the slot
  protocol, the provenance, the decisions D1-D8 this note builds on.
- `run_artifact.md`: the sink, its producers and readers, the batching.
- `multi_process_policy.md`: what a divided run reproduces bit for bit and
  what it reproduces to the fold bound.
- `../history/crab_cavity_noise_validation_2026_10_14.md`: the noise
  verification by internal replay this note makes public.
- `../history/crab_cavity_noise_mpi_benchmark_2026_10_14.md`: the per-turn
  costs the recording is compared with.
- `../theory/crab_cavity_noise_response.md`: the kick formula the probe's
  third comparison uses.
