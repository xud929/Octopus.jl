# Recording the realised turn modulation in the run artifact

> **Status: designed 2026-10-15 in owner discussion; not implemented.** This
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
  `index`, `kind`, `rng_id`, `digest`, `name`, `length`, written per
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
Recording is an output option of `RunArtifact`, a keyword beside `append`
and `capacity` (name to be fixed in section 8; `record_turn_modulation =
false` in this note), off by default. It is not a keyword of
`with_execution_audit`: the audit is a proof instrument, and tying output to
it would make a run's artifact depend on whether a contract or a user
happened to wrap the run. No new function appears: the recorded data is
read through the existing `turn_modulation_provenance(path)` and
`read(out, :turn_modulation)`, whose per-slot entries gain the fields the
recording adds and hold `nothing` when the run did not record. A new
public option lands as every public option does (AGENTS.md Invariants):
runtime consumer, structured metadata, inactive and invalid behaviour, an
effectiveness test at the consumer boundary.

**D3. The offsets are recorded, not the realised values.** The offset is
the rule's output and the primary datum: it exists before any element is
built, and for a table it is the record entry at the turn's index. The
realised phase or strength, nominal plus offset, is a derived quantity and
is exactly what the verification reconstructs and checks against the
tracking; recording it would record the thing under test. The nominal
parameters of every active slot (the phase, and both planes' strengths) are
stored once per execution slot beside the labels, so a reader forms the
realised values and any normalised view it wants. Floating point agrees:
`(S + d) - S` is not bitwise `d`, so an offset derived from element fields
would miss a replay by a relative 1e-12 on the strength slots, while the
recorded `d` with the stored `S` reproduces the element's value exactly.

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
on absolute turn `first_turn + i - 1`, in the parameter's own unit: radians
on a phase slot; the strength's unit on a strength slot, one value that the
shipped semantics adds to both planes. Execution-slot groups are never
deleted, so chunked and repositioned runs stack as the provenance does
today, and a knob change between windows shows up as a different nominal
in the next slot.

**D8. Backends and tasks.** Every MPI rank realises the same values from
the same keys; rank 0 writes, as it writes the other producers. On CUDA
the realisation is host-side already; nothing crosses to the device. The
strong-strong task records both beams' lines through the same path,
labelled by beam as its provenance entries are.

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
| the example's moments table for comparison | 27 columns, about 216 bytes per turn | `run_artifact.md` |
| per-turn tracking time the recording competes with | 3 ms (CUDA, 1e5 particles), 26 ms (CUDA, 1e6), 119 ms (16 threads, 1e5) | `../history/crab_cavity_noise_mpi_benchmark_2026_10_14.md` |

The file growth is the reason the default is off. Nothing above is
measurable in a per-turn timing; the effectiveness test of section 6
nevertheless pins the absence of any effect on the tracked coordinates.

## 5. Interactions

- **Knobs.** The nominal is the compiled spec parameter; a knob change
  recompiles at the next `execute!` and the new nominal is recorded with
  that window's execution slot, while the offsets are unchanged (verified
  for the knob case in the stage 4 audit).
- **The both-planes question** (`turn_modulation.md` section 10, open): one
  strength offset is added to `strengthX` and `strengthY`. The record
  stores the one offset and both nominals, so whichever semantics the owner
  decides, the dataset's meaning is "what the rule produced" and only the
  reader's reconstruction changes; the vertical column of a horizontal
  cavity makes the current semantics visible in the data.
- **The amplitude-noise convention.** The example specifies a relative rms
  and multiplies by the nominal strength before handing an additive rule
  over; that is the producer's convention, not the rule's, and the record
  stays in the rule's unit. A reader divides by the stored nominal where it
  is non-zero.
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
alone.

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

## 8. Open questions for the owner

- The option's name: `record_turn_modulation` (this note) or a name in the
  style of the other output options of `run_artifact.md`.
- Whether the default stays off (file growth, section 4) or on, with the
  example's default run recording either way.
- The both-planes semantics (`turn_modulation.md` section 10), which fixes
  what the `strengthY` nominal and the single strength offset mean
  together; the record is designed to survive either answer.
- Whether a successor rule's state should be recorded as well. No shipped
  rule is stateful (the stage 4 tripwire pins it), so this note records
  offsets only.

## 9. References

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
