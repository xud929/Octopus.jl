# Turn modulation stages 3-4: the RF cavity, the neighbour audit (2026-10-13)

Status: stage 3 of `docs/design/turn_modulation.md` (section 9, item 3)
implemented 2026-10-13 on top of the stage 1-2 batch pushed as `148d39a`
(CI run 447 green, section 5); stage 4, the targeted neighbour audit,
completed 2026-10-13 with its fixes folded into the same batch (section 6);
the gate is pending (section 7). The stage 1-2 record,
`turn_modulation_stage1_2026_10_12.md`, is frozen; this one builds on it and
carries the corrections to it (6.4).

Stage 3 puts the thin RF cavity's phase and strength under the same
`TurnModulated` wrap the crab cavity uses, the design's proof that the
wrapper is element-agnostic; the second kind also forced the walks written
once for the crab cavity into a protocol.

## 1 Stage 3: what landed

- `src/elements/rf_cavity.jl`: `phase_noise` (rad) and `strength_noise` (the
  unit of `strength`, the dimensionless qV/(P0 c)) on `ThinRFCavitySpec`,
  each `nothing` (the default) or ONE rule, coerced by `_rule_scalar`; the
  keyword `:turn_modulation`, two `ParamMeta` rows with default `nothing`,
  the construction-help sentence; `RFCavityNoise(phase, strength)` and its
  `realize` (phase slot 1, strength slot 2; `method`, `k`, `L`, `beta0`,
  `gamma0`, `ds_turn` carried verbatim); the kind's `_turn_modulation_wrap`
  method; the scalar `_check_rule_numeric_type`; the protocol methods
  `_slot_rules(::RFCavityNoise)` and `_turn_rule_values` on the spec kind; a
  comment at the accelerating cavity's `@element_spec`: no rule.
- `src/elements/turn_modulated.jl`: the slot protocol (its section comment
  "The slot protocol"): `_slot_rules` with no fallback,
  `_check_container_window` generic over it (called by
  `_check_turn_window(::TurnModulated)`), `_turn_modulation_slots` as one
  generic method, `_collect_turn_modulation_ids!(ids, ::ElementSpec)` generic
  over `_turn_rule_values`, whose one generic fallback `Any[]` is argued in
  its docstring.
- `src/elements/crab_cavity.jl`: `_slot_rules(::CrabCavityNoise)` and
  `_turn_rule_values(::ElementSpec{:thin_crab_cavity})` replace the crab
  cavity's three per-container methods (its `_check_rule_window`,
  `_turn_modulation_slots` and `_collect_turn_modulation_ids!`), deleted.
- `src/contracts/Contracts.jl`: the exemption rows `(:thin_rf_cavity,
  :phase_noise)` and `(:thin_rf_cavity, :strength_noise)`.
- `docs/registry_snapshot.md`: one line, the RF cavity's keywords gaining
  `:turn_modulation`, regenerated with the batch.
- `test/runtests.jl`: the testset "Turn modulation: the RF cavity by the same
  wrap" after the spectra testset; section (j) of "Turn modulation: rules,
  wrapper and the pure hook", the kind and container tripwires (section 4).
- Documentation: this record; `docs/README.md`; the design note's status
  line and its section 9 marker; `docs/todo.md`; `docs/experiences.md`;
  `docs/public_api.md`;
  `docs/current_runtime.md`.

## 2 Decisions

- **Scalars, with `nothing` as the inactive spelling.** The RF cavity has
  one phase and one strength, so each parameter is one rule or `nothing`,
  where the crab cavity's parameters are per-harmonic tuples whose inactive
  spelling is `()`. The asymmetry is the parameters' shapes, not a style
  choice: a scalar has no empty tuple to spell "inactive" with, and a tuple
  of harmonics has no scalar. A tuple or vector on the RF cavity is refused
  by name rather than unwrapped (`_rule_scalar`: "the RF cavity's phase and
  strength are scalars: give one rule or nothing for phase_noise, not a tuple
  (PinkNoise, TurnTable, WhiteNoise); got a Tuple{WhiteNoise{Float64}}"),
  the catalogue in the message derived by `_turn_rule_names()`.
- **Slots.** Phase is slot 1 and strength slot 2, so the draws sit on
  components `_RULE_COMPONENT_BASE + 1` and `+ 2`; the receipt and window
  labels are the bare parameter names, "phase_noise" and "strength_noise",
  without an index, because each parameter is its slot.
- **The strength unit.** A `strength_noise` offset is in the unit of
  `strength`, the dimensionless qV/(P0 c); a relative voltage jitter is the
  producer's sigma times the nominal strength (the producer/consumer
  boundary of design decision D7, unchanged).
- **The accelerating cavity carries no rule.** It is single-pass (a closed
  ring containing one is physically inconsistent), and a turn-by-turn
  modulation is a property of a ring element seen once per turn; with no
  parameters and no `_turn_modulation_wrap` method it is absent from the
  modulated-kind set by construction, the kind tripwire deriving that set
  from the wrap's methods.
- **The slot protocol replaces the crab cavity's per-container methods.** A
  rule container declares its scalar slots once, `_slot_rules(rules) ->
  ((label, rule), ...)` in slot order; a spec kind declares the rule objects
  it holds, `_turn_rule_values(spec) -> Vector{Any}`; the window check, the
  provenance slots and the stream-id collection are generic over those two
  declarations, and `realize` stays per container (the element's arithmetic,
  not a walk). Before stage 3 the crab cavity owned one method per walk, each
  a hand-copy of the walk it served; a second kind would have doubled them.
  `_slot_rules` and `realize` have no fallback (a `MethodError`, not an
  element silently unmodulated or missing from the provenance); the one
  fallback, `_turn_rule_values(spec) = Any[]`, is legitimate because the kind
  tripwire pins that every kind with a specific wrap method owns a specific
  `_turn_rule_values`, so a kind that would fall to it is named red there.
- **Harmon and survey composition.** `_turn_modulation_wrap` sees the
  nominal cavity unbound (`k` NaN for a harmon spec, `ds_turn` NaN for every
  spec); a task binds the wrapper's `base` through
  `_survey_rebind(::TurnModulated)` and `realize` carries `k` and `ds_turn`
  verbatim, so a task-compiled wrapper realises survey-bound cavities, while
  a harmon cavity realised before binding keeps `k = NaN` and refuses to
  kick as its nominal does.

## 3 Measured

Every number is quoted at the precision its source printed (the stage 3
probe, git-ignored scratch; the suite's pins; the red and green runs).

**The fixture.** `set_global_rng!(seed=42, method=:philox)`, `rng_id` 21,
`sigma` 1e-2 on `ThinRFCavitySpec(400.8e6; voltage=12.0e6, e0=275.0e9,
mc2=PMASS_EV)`: the compiled bare cavity is `ThinRFCavity{Symplectic6DMap,
Float64}` with strength `4.363661762515765e-5`, `k` `8.40014684798234`,
`beta0` `0.9999941794573495`, `gamma0` `293.091953920384`, `ds_turn` NaN.
The wrapper is isbits with `inner === base`. Realised phase offsets on turns
0 to 3: `-0.014312039683119027, 0.01905802301093476, 0.014157071464927926,
-0.013726809899956728` rad (the testset pins `-1.431204e-2, 1.905802e-2,
1.415707e-2, -1.372681e-2` at `atol` 5e-7); a strength rule on slot 2 with
`sigma` 1e-7 realises `4.357148068034051e-5, 4.3672120680899266e-5,
4.373615779290772e-5, 4.348646381245439e-5` on those turns. `realize`
allocates nothing after a warm-up call (the pin; the probe's cold first call
printed 464 bytes, compilation).

**Effectiveness through `execute!`.** 300 particles at `z = pz = 0` through
`(DriftSpec(L=10.0), cavity)`, one `execute!` per turn on the fast loop
(asserted by name through the timing receipt's `fast_path`): `mean(pz)`
after turns 1 to 4 is `-6.2451131745815e-7, 2.0707084420038007e-7,
8.248205185062422e-7, 2.2584428800991784e-7` (pinned as `-6.245113175e-7,
2.070708176e-7, 8.248204741e-7, 2.258442609e-7` at `rtol` 1e-6), identical
across particles, nonzero from turn 1, and bitwise equal to a hand reference
built from the task's survey-BOUND wrapper (`base.ds_turn == 10.0`). A
reference from the bare wrapper (`ds_turn` NaN) is not bitwise equal: the
implementing run measured the difference at 2.7e-14 in `pz` and 4.7e-11 in
`z`, the slip term, which is why the fixture carries a drift; the suite pins
the inequality, not the magnitude.

**The harmon cavity.** `ThinRFCavitySpec(harmon=360; ...)` behind a 100 m
drift, through a task: bound `k = 22.619335448273493`, equal to
`2 * pi * 360 * beta0 / 100` with `beta0 = 0.9999941794573495` (pinned at
`rtol` 1e-14), `ds_turn = 100.0`; compiled bare: `k` NaN, `ds_turn` NaN, an
`update` realises a wrapper whose inner `k` is still NaN with a nonzero
phase, and the first kick throws "ThinRFCavitySpec(harmon=...) has no
frequency until a task line's circumference resolves it; compile through a
TrackingTask, or give frequency= for standalone use".

**The protocol walks.** Provenance slot of the white-phase wrapper:
`(slot = "phase_noise", kind = :white, rng_id = 0x0000000000000015, digest =
0x0000000000000000, name = "", length = 0)`; `_slot_rules`:
`(("phase_noise", WhiteNoise{Float64}(0.01, 0x0000000000000015)),
("strength_noise", nothing))`; collected ids `[0x0000000000000015]`. The
window check names the slot without an index ("the turn table "one" on
ThinRFCavity strength_noise holds 1 turns but the window runs turns 0 to 2
(absolute, zero-based): a table never wraps, extend it or shorten the run")
and the crab cavity's message through the same generic walk keeps its form
("... on ThinCrabCavity strength_noise[2] holds 2 turns ..."). A `Float32`
table: "strength_noise: a Float32 turn table on a Float64 cavity is refused
rather than promoted; convert the table to Float64". Method sets:
`_turn_modulation_wrap` on the two spec kinds and `Any`; `realize` and
`_slot_rules` on `CrabCavityNoise` and `RFCavityNoise`; `_turn_rule_values`
on the two kinds and `Any`.

**Metadata and sweeps.** `validate_element_metadata()` passed,
`validate_configuration_metadata()` returned true, both `element_help` forms
of both kinds name both parameters;
`validate(ElementParameterEffectivenessContract())` passed ("500 checked, 0
kinds without a probe; 41 with no formable perturbation, 23 whose
perturbation the constructor rejected"), 38 exemptions declared and applied,
0 stale. The extracted sweeps at the end of stage 3: the stage 6 pin
tripwire 2/2, the `Core.Box` sweep 2/2, the detached-docstring scan 1/1 (2/2
once the stage 4 foreign-binding check joined it).

## 4 Tests

- "Turn modulation: the RF cavity by the same wrap" (135 assertions at the
  end of stage 3, 140 after the stage 4 fixes; after
  the spectra testset): what compiles, the realise pins and zero allocation,
  the nominal path (a contextless `track!` tracks the nominal cavity bit for
  bit), effectiveness on the fast loop against the bound and the bare hand
  references, the harmon cavity bound and bare, the protocol walks and their
  labels, the guardrails, and (CUDA active) the noisy line tracked three
  turns on the device equal to the bit to a device `track!` of the
  task-bound realised cavities, CPU against CUDA within `atol = rtol = 1e-10`.
- Section (j) of "Turn modulation: rules, wrapper and the pure hook": the
  KIND tripwire, the set of spec types with a specific `_turn_modulation_wrap`
  method pinned in both directions against `{thin_crab_cavity,
  thin_rf_cavity}`, each member declaring the keyword, both `ParamMeta` rows
  (the `phase_noise` meaning naming every rule of the derived catalogue, unit
  rad), both `construction_help` mentions, both exemption rows, a specific
  `_turn_rule_values`, and compiling its registered example with a white rule
  in slot 1 to a `TurnModulated` whose container owns `_slot_rules` with that
  rule first; and the CONTAINER tripwire, the first-argument types of
  `realize` equal to those of `_slot_rules`, both `{CrabCavityNoise,
  RFCavityNoise}`.
- Red, each stub shown to fail for the feature's reason:

| stub | red result |
|---|---|
| `realize(::RFCavityNoise, ...)` returning the base | new testset 114 passed, 21 failed: the per-turn phase and strength pins (`0.0 == -0.014312039683119027`), the nonzero-`pz` pin, the harmon phase pin, the CUDA noise effect |
| `_turn_modulation_wrap(::ElementSpec{:thin_rf_cavity}, inner)` returning `inner` | 12 passed, 7 failed, 4 errored: a bare `ThinRFCavity` where a wrapper was expected (`FieldError: type ThinRFCavity has no field inner`) |
| a fake `_turn_modulation_wrap(::ElementSpec{:drift}, inner)` | rules testset 243 passed, 13 failed: the kind tripwire names `drift` (`Context: modulated_kind = drift`) |

- Green at the end of stage 3, before the stage 4 fixes, four threads, CUDA
  active: the new testset 135/135; the rules testset 243/243; "RF cavity
  closes the longitudinal plane" 33/33; "Cavity chain composition,
  single-pass refusal, harmon resolution" 9/9; the other turn-modulation
  testsets unchanged (effectiveness 51/51, spectra 44/44, artifact 51/51,
  CPU/CUDA 28/28). After the stage 4 fixes the fixers' extracted runs read
  RF 140/140, rules 321/321, effectiveness 57/57, artifact 127/127, CPU/CUDA
  39/39, spectra 44/44, slot bounds 25/25, strong-strong window 20/20; the
  gate in section 7 is the authority.

## 5 CI run 447 on 148d39a

The stage 1-2 batch was pushed as `148d39a`. CI run 447 (workflow run
38395232248), job "Julia 1.12 CPU full-lane tests" on a GitHub Actions
`ubuntu-latest` runner, started 2026-10-13T12:09:28Z and completed
2026-10-13T12:41:24Z, conclusion success, every step green. Eight
annotations: the six "stage 6 identity pins k/6 (znver3)" notices (the
identity-table chunks, host znver3), the Node.js 20 deprecation warning, the
`ubuntu-latest` migration notice; nothing else. CI has no GPU, so the CUDA
testsets skipped there; the CUDA-active evidence is the local gate.

## 6 Stage 4: the targeted neighbour audit

### 6.1 Hypothesis and blast radius

The audit's hypothesis: the invariants the design states hold at every seam
the campaign touched. Chunked and plan-split execution equal one continuous
call; nested placements of the wrapper behave as flat ones on every walk;
the device conversion reaches every container; the two-beam task checks and
records both lines; the artifact's append semantics and reader contract
hold; the spec layer's derived sets stay derived; the counter-RNG key layout
keeps every consumer class on its own cells. The blast radius was read as
seven units, each a seam the campaign's commits (`1fc2cbd`, `148d39a` on
`08f04e5`) and the uncommitted stage 3 changed or lean on: U1
`src/tasks/Tasks.jl` (the turn loops, the receipt, the collectors); U2 the
walker seam (every function in `src/` and `ext/` dispatching on or
descending `CompositeLine`, `MisalignedElement`, `RefTilted`,
`TurnModulated`); U3 the CUDA conversion seam; U4
`src/tasks/strongstrong/interface.jl`; U5 `src/tasks/RunArtifact.jl`; U6
the spec layer; U7 the counter-RNG key layout.

Verification ran in two passes. Each unit read its region line by line,
ran probes against its hypotheses and wrote leads; a second, independent
pass then reproduced every lead on the live tree (one pass took U1, U3, U4
and U5, the other U2, U6 and U7), re-ran the units' probes and gave each
lead a verdict. Of 39 leads, 35 are right as stated (U1-4 for its size and
allocation claims, its timing claim not reproduced), 1 is right with the
wrong reason (U5-1), 3 are narrower than reported (U1-2, U2-5, U5-2), none
is wrong outright. Two are moderate (U7-1, new in this campaign; U2-5,
pre-existing), the rest minor, style or informational. Dispositions
(6.5, 6.6): fixed in this batch with a regression test, ledgered as a
`docs/todo.md` row, handed to the owner, or documented.

### 6.2 Coverage ledger

- **U1, `src/tasks/Tasks.jl`.** Read in full (1861 lines), with
  `src/policies/Policies.jl` 90-200 and `src/track/Track.jl` 1-60; the
  campaign's diff to the file first. Seven hypotheses (state in two places,
  check once and gate per call, the receipt, nested placements, fast path
  against general loop, the walks, the docstrings), nine probe scripts, five
  leads. Clean, confirmed by the second pass: H1, five routes through the
  plan cache (a bare fast path, an observer every turn, `AtTurns([2,4])`,
  six one-turn calls, artifact only) agree bitwise on all six coordinates
  with `<px> = -3.2289830851212255e-06`, relative error 1.61e-08 against
  the hand counter-RNG reference; a strong beam with and without
  `AtTurns` agrees too.
- **U2, the walker seam.** Eleven type-dispatched walkers enumerated by
  machine over every binding of `Octopus` (`track_particle`, the two call
  operators, `track_luminous`, `_inner_method`, `_requires_tracking_context`,
  `update`, `_check_turn_window`, `_turn_modulation_provenance!`,
  `_survey_rebind`, `_descend_strong_beams!`, `_hidden_strong_beam_count`,
  `Adapt.adapt_structure`), each owning methods on all four containers;
  six hypotheses plus the strong-strong flattening, two probe scripts, six
  leads. Clean, confirmed: H2, the two-deep kept-whole line compiles to
  `MisalignedElement{CompositeLine{MisalignedElement{CompositeLine{TurnModulated}}}}`
  with no tuple in any `ops`; `update` reaches the cavity (phase
  `-0.006595654730844676`, type preserved); the window check names
  "ThinCrabCavity phase_noise[1]" holding 3 turns; the provenance lists one
  `:table` slot (digest `0x9a05327069b7658a`, length 3); the constructor
  warns with `rng_ids = [7]` on a shared id and not on distinct ids; through
  `execute!` the two-deep line equals the flat line bitwise over 3 turns.
- **U3, the CUDA conversion seam.** `src/track/phase6d_track.jl` (438
  lines) and `src/track/fused_track.jl` (133) in full, `src/beam/Beam.jl`
  1-70, `src/elements/aperture.jl` 60-100, 200-220 and 401-412, the four
  `adapt_structure` methods, and the installed CUDACore 6.3.1, Adapt 4.7.0
  and GPUCompiler 2.5.3 sources; six hypotheses, four probe scripts on the
  RTX 4500 Ada, five leads. Clean, confirmed: H1, the nested tuple is not
  isbits on the host and isbits after `cudaconvert`, innermost element
  `ThinCrabCavity{1, Symplectic6DMap, Float64}`, record
  `LossRecord{CuDeviceVector{Int32,1}, CuDeviceMatrix{Float64,1}, Nothing}`,
  launched, losses GPU `[500]` = CPU `[500]`, coordinate gap 5.42e-20; six
  deeper nestings isbits and launched.
- **U4, `src/tasks/strongstrong/interface.jl`.** Lines 2250-2800 and
  2950-3060 line by line plus the helpers at 3046-3168, every cross-file
  claim checked against `148d39a`; six hypotheses, four probe scripts,
  three leads. Clean, confirmed: H5, with a table inside beam 2's nested
  `BeamLine` (physics line `[:LatticeMagnet, :CompositeLine]`),
  `execute!(turns=4)` is refused by an `ArgumentError` naming the table
  before any turn, `next_turn` stays 0, both beams are untouched and no
  `:turn_modulation` receipt is recorded; `turns=3` succeeds with one
  receipt (`beam=1 phase_noise[1] :white`, then `beam=2 strength_noise[1]
  :table length 3`, `first_turn=0 turns=3`), `next_turn` 3.
- **U5, `src/tasks/RunArtifact.jl`.** Lines 1-940 line by line, the call
  sites in `Tasks.jl` and `interface.jl`, both design notes, the artifact
  testset; six hypotheses (crash path against provenance, append semantics,
  rank-0 gating, the reader contract, types and slot order, docs against
  code), three probe scripts with hand-made fixtures, seven leads. Clean:
  the crash path is consistent with the provenance, the rank-0 gating holds
  by reading, the reader contract, the types and the slot order hold.
- **U6, the spec layer.** `src/elements/crab_cavity.jl` in full (395
  lines), `src/elements/rf_cavity.jl` 200-560, `src/knowledge/Knowledge.jl`
  60-245, 540-580, 985-1065, 1076-1300, 1340-1400, `src/knobs/Knobs.jl`
  1015-1077, `src/contracts/Contracts.jl` 2850-2915, 2973-3055, 3085-3282,
  `src/registry/Registry.jl` 195-235, 295-335; seven hypotheses, six probe
  scripts, six leads. Clean, confirmed: H3, `resolve_knobs` keeps all four
  rule entries `===` (the `TurnTable` identity included) and resolves
  `phase = (0.3, 0.0)`; on one task the nominals 0.3, 0.4, 0.5 give
  `px = -7.2233e-5, -9.4952e-5, -1.1672e-4` while the inferred rule offset
  `2.846081366233e-3` is unchanged to 2.8e-16 and equals the turn-0 slot-1
  draw to 1.5e-17; the recompiled base carries `phase = (0.5, 0.0)`.
- **U7, the counter-RNG key layout.** `src/elements/turn_modulated.jl`
  1-380, `src/math/counter_rng.jl` 1-431,
  `validation/turn_modulation_spectra.jl` 1-203 and every consumer of
  `octopus_normal`, `octopus_uniform01` and
  `octopus_uint64` (`Beam.jl`, `radiation.jl`, `BPMObserver.jl`) with the
  particle-index origins; seven hypotheses, seven probes, seven leads.
  Clean: the rules' cells are disjoint from every other consumer (0 of 62
  cell equalities involve a rule); the component mixing is a bijection (0
  collisions over `2^22` inputs, no wrap at `2^16` or `2^32`); the shift
  `turn >> k` holds at `K = 62` up to `typemax`; the spectra instrument on
  200 known sequences fits white `+1.003 +- 0.024` and Timmer-Koenig `1/f`
  `-0.007 +- 0.022` at 65536 turns, 0 of 200 outside the tolerances;
  `sigma` is the ensemble per-turn rms exactly (Monte-Carlo mean `rms^2`
  1.003 and 1.007), the recorded `0.9054` being the 6.4th percentile of the
  construction's own scatter; the script reprints the recorded machine line
  exactly.

### 6.3 Findings by severity

Each line: mechanism, then disposition.

Moderate.

- U7-1 (new). A pink generator's component `_RULE_COMPONENT_BASE + slot +
  64 (k + 1)` coincides with another rule's `_RULE_COMPONENT_BASE + slot'`
  on the same `rng_id` once a container has more than 64 slots: measured
  through `compile_runtime` and `realize`, N = 32 gives 0 of 64 identical
  draws (corr +0.0043), N = 33 gives 64 of 64 (corr +0.2873), and the
  shared-id task built with no warning. Fixed: the generic
  `TurnModulated(base, rule)` constructor refuses a `PinkNoise` on a
  container with more than 64 slots and validates slot labels (non-empty, no
  '/', unique), so a crab cavity with more than 32 harmonics may carry white
  and table rules only; every recorded pink number is unchanged.
- U2-5 (pre-existing since `6f708bb`, narrower than reported).
  `_bind_aperture_entry` neither descends the wrappers nor records the
  losses of an unbound aperture: `execute!` on a misaligned aperture is
  refused ("loss record sized for 1 apertures but the compiled line
  contains 0"), and on the bare path a wrapped unbound aperture kills 1723
  of 2000 and the unwrapped one 1714 of 2000, both without a record, which
  is that path's design for every aperture. `TurnModulated` cannot wrap an
  aperture, so the campaign did not change it. Ledgered.

Minor.

- U1-1 (latent). The fast loop restarts a rule's successor on every
  `execute!` call and the general loop on every plan-key flip, so a stateful
  rule (design D6 admits one) would make split calls unequal to one call;
  the three shipped rules return themselves. Tripwire only (every shipped
  rule returns itself from `realize`), the `execute!` docstring qualified;
  the decision is the owner's.
- U1-2 (narrower). All five `LineEntry` collectors read the raw spec while
  compile merges the placement overrides, so override-only rules sharing an
  `rng_id` did not warn (`warned=false`, receipt `rng_ids: [7, 7]`). Fixed:
  one effective-spec helper in the five collectors.
- U1-4 (performance). A wrapper carries `base` and `inner`: the fused
  tuple is 4480 against 3520 bytes for 20 wrapped cavities in 40 elements
  (+27 %), the fast loop's per-turn allocation +3840 B exactly (4 workers
  times 960 B); the wall-time delta flipped sign between two runs on the
  shared host (wrapped 684.6 then 1158.9 us per turn against bare 1009.0
  then 984.5). Ledgered as a quiet-machine benchmark; no timing claim.
- U2-1. `_survey_rebind(::TurnModulated)`'s else branch rebound `inner`
  separately and advanced the cavity counter twice (`id[] = 2`), reachable
  only on a path the count check already refuses. Fixed: rebind `base` once,
  drop a stale `inner`.
- U2-2 (latent). `CompositeLine` accepted a nested `Tuple` member that four
  walkers do not descend (`_inner_method` throws, three count 0), inert
  under the builder invariant (every compile method returns one op). Fixed:
  the constructor refuses a `Tuple` member.
- U2-3 (test gap). `CompositeLine` sat outside the derived wrapper set, so a
  walk with methods on the three wrappers and none on `CompositeLine` passed
  the product loop. Fixed: every wrapper walk is checked against
  `CompositeLine`.
- U3-1. `CUDA.cudaconvert(::Phase6DRep)` was dead: `@cuda` converts through
  the two-argument `kernel_convert` into `adapt(KernelAdaptor(managed), x)`
  and `@adapt_structure Phase6DRep`; a counting twin saw 0 calls on six
  launch paths, 1 on a direct call. Fixed: deleted, with a tripwire that no
  Octopus method extends `CUDA.cudaconvert`.
- U3-5. The CUDA neighbour probe covered the kept-whole placement of a
  recording aperture only; `MisalignedElement` and `RefTilted` placements
  also convert, launch and match (losses 500 = 500, identical coordinates).
  Fixed: both joined the probe.
- U4-1. No test exercised the strong-strong window refusal (36 constructor
  sites, none with a `TurnTable`). Fixed: the probe body is a test.
- U5-2 (latent, narrower). The writer's `catch; close(file); rethrow()`
  makes any partial write durable (a label error, an I/O error mid-write,
  the ledger row already appended), and a label containing '/' nests a
  group silently and fails only at the reader; shipped labels are unique
  and '/'-free. Fixed in part through the label validation of U7-1 and the
  attribute reads of U5-1; the rollback is the owner's call (see U5-4): a
  rollback attempted after an I/O error is itself untrustworthy, and the
  reader's torn-group detection is the guard that exists today.
- U5-3. `prepare_run_artifact!` appended the ledger row before testing
  whether the slot group existed, leaving a phantom row (`start_turn = [0,
  1]`, provenance `[(1, 2), (2, 0)]`) on refusal. Fixed: `haskey` before
  the append.
- U5-7 (pre-existing). `read(out, :losses)` on an artifact without losses
  was a bare `KeyError` where `:moments` gives an `ArgumentError` naming
  what is present. Fixed: `:losses` and `:execution` reads go through
  `_ra_require_group`; no test had pinned the `KeyError`.
- U6-1. The crab constructor's docstring was bound to `Core.Type`, so
  `?ThinCrabCavitySpec` lacked `phase_noise` while the detached-docstring
  sweep saw nothing wrong (the docstring IS attached, to the wrong binding).
  Fixed: moved to the `abstract type` docstring; tripwire: no Octopus
  docstring binds outside the module.
- U6-5. The kind tripwire tested `construction_help` for the two parameter
  names only, and nothing checked the converse (every kind with the keyword
  is a modulated kind). Fixed: the per-rule catalogue loop and the converse
  check.
- U7-3. The spectra script's printed expectation of the pink sample
  variance charged generators with `2^k > N` wrongly; see 6.4. Fixed in the
  script.
- U7-4 (fragility). The twin's rms band `[0.8, 1.25]` misses 6.2 % (1024 streams; 120 of 2048, 5.9 %, in the fixer's run) of
  streams at 16384 turns (0.5 % at 65536); the pinned sequence is
  deterministic. Fixed: a stated quantile bound and the one-sigma figures
  (7.6 % at 65536, 13.8 % at 16384) in the prose.
- U7-7 (pre-existing). The BPM's second reading of a turn (occurrence 1)
  draws the cells radiation particle 1 reads on a shared `rng_id`, and both
  duplicate-stream warnings compare within a class. Ledgered.

Style and informational.

- U1-3: the receipt records the window resolved for the call, not the turns
  completed (a crash at turn 2 of 5 records `turns=5`); comment reworded.
- U1-5: the `:turn_modulation` receipt preceded the unsharded-feature
  refusal; the refusal now runs first in the resolved-policy block
  (nothing in `test/`, `validation/`, `examples/` or `profiling/` pinned
  the order), and the `TrackingTask` docstring names both turn loops.
- U2-4: `_requires_cuda_elementwise` has no wrapper method; already a row.
- U2-6: section 4.3 named "the BPM observer's wrapper awareness"; no observer
  walks runtime wrappers; fixed in the design note (6.4).
- U3-2 (inert): the `adapt_structure` methods drop the wrapper under any
  adaptor, not only the kernel's; owner item.
- U3-3: two docstrings now say a bare `track!` tracks `inner`, unchanged
  across turns (the nominal element for a fresh wrapper).
- U3-4: the CUDA testset header's FMA attribution corrected (6.4).
- U4-2: the window message names the beam ("in beam 2's line"). Fixed.
- U4-3: the strong-strong preflight refusals run after two receipts record
  intent; owner item.
- U5-1 (right, wrong reason): an attribute missing from a provenance group
  raised a bare `KeyError`; the docstrings promised "torn" for counts only,
  so no promise broke, but the two paths disagreed. Fixed: every attribute
  read reports a torn group.
- U5-4, U5-5: a crash between the ledger row and the group reads exactly as
  an unmodulated continuation, and a torn group makes `read(out)` throw for
  every product; owner items.
- U5-6: the `TaskOutput` docstring's example block gained
  `:turn_modulation`.
- U6-2: the crab refuses a bare `nothing` where the RF cavity requires it;
  owner item (exists), the crab help now says so.
- U6-3: the comment above the RF exemption rows named the wrong pin (the
  rows protect `rejected <= 23`; without them 25). Reworded.
- U6-4: the crab example line printed `phase_noise=(nothing, nothing)`;
  `_omit_example_key` now omits an all-`nothing` tuple with default `()`.
- U6-6: the Registry docstring's count ("six") dropped.
- U7-2: the key-layout comment now says the rules share no cell with any
  consumer, while the older consumers overlap among themselves (`Beam` turn
  0 with radiation turn 0, BPM occurrence 1 with radiation particle 1).
- U7-5: the spectra script's band labels (6.4).
- U7-6: `rng_id = -1` was an `InexactError`; the rule constructors now
  require a non-negative `Integer` (the shared `claim_rng_id!` path is a
  row).

### 6.4 Corrections to earlier records

- The stage 1-2 record's section 8 and the spectra README's prose quoted
  the pink sample-std expectation at `K = 16`, `N = 16384` as `0.8660`
  (variance `0.7500`) from `1 - (2^K - 1) / (K N)`, which charges a
  generator whose hold exceeds the run (`2^k > N`) with `2^k / N` instead of
  the single value the mean removes. The correct form is
  `E[s^2] = (N / (N - 1)) (1 - (1 / K) sum_k min(2^k, N) / N) = 0.81255`,
  std `0.9014`; Monte Carlo over 1024 streams gives `0.8122 +- 0.0040` (the
  script's own 2048-stream run `0.8125 +- 0.0027`)
  (0.1 standard errors from 0.81255, 15 from 0.7500). At `N = 65536` both
  forms give `0.9375` (std `0.9682`), so that record's 65536-turn numbers
  stand. The frozen record keeps its line; this is the correction.
- The CUDA identity testset's header attributed the nominal crab line's
  CPU/GPU `px` gap to FMA. Measured: `fma(ikcc, z, 0.0) == ikcc * z` on
  1000 of 1000, libdevice `sin` differs from the host's by 1 ulp on 30 of
  1000 inputs (`cos` on 14), and the GPU `px` equals the host computed with
  the device `sin` on 1000 of 1000; the gap is the `sin` library plus the
  fused `theta`, not FMA. Header reworded.
- The design note said `Phase6DRep` set the precedent for a `cudaconvert`
  method at launch; the launch converts through `Adapt` and that method was
  dead (0 calls on six launch paths). The sentence now states the Adapt
  fact; the method is deleted.
- The stage 1-2 record credited the container methods with fixing the
  kept-whole placement of a recording aperture on CUDA only; the
  `MisalignedElement` and `RefTilted` placements convert, launch and match
  as well (losses 500 = 500, identical coordinates), and now sit in the
  same probe.
- The stage 1-2 record's section 8 band tables print each band's label as
  `2^i / N .. 2^(i+1) / N` while its bins are `(2^i - 1) / N .. (2^(i+1) -
  2) / N`: at 16384 turns the first band reads `1.22e-4 .. 2.44e-4` for
  bins at `6.10e-5 .. 1.22e-4`. The powers are unaffected; the labels stand
  in the frozen record with this note, and the script prints the bin edges.
- "Several percent" for the pink sample rms is `7.6 %` one sigma at 65536
  turns and `13.8 %` at 16384.
- The design note's section 4.3 named "the BPM observer's wrapper
  awareness" among the walks; no observer walks runtime wrappers (the BPM
  observer draws at particle slot = occurrence) and `_survey_rebind` rebinds
  `base` once; reworded (U2-6).

### 6.5 Fixed in this batch

Each fix landed with its regression test in the same batch; the testset
named with each is where the red-then-green evidence lives.

- U7-1: the pink stride bound and the slot-label validation at
  `TurnModulated(base, rule)`; N = 33 with a `PinkNoise` refused, N = 32
  with one on slot 64 and N = 33 with white and table rules accepted
  (testset "Turn modulation: slot bounds and labels at the wrap", 25
  assertions, the refusal shown through `execute!` as well).
- U7-6: `rng_id` a non-negative `Integer` on `WhiteNoise` and `PinkNoise`
  ("Turn modulation: rules, wrapper and the pure hook", part (e); 1.5 and
  2.5 had been a `TypeError` from the typed keyword, -1 an `InexactError`).
- U7-3: the script's expectation formula (no suite test; the script's
  16384- and 65536-turn runs re-executed, the measured rms 0.8799 unchanged,
  `validation/README.md` carries the corrected 0.9014).
- U7-4: the quantile bound of the spectra twin ("Turn modulation: white
  and pink spectra", part (a): band [0.75, 1.6]; Monte-Carlo over 2048
  streams: q0.001 = 0.779, q0.995 = 1.538, 7 of 2048 outside, the old band
  120 of 2048).
- U7-5, U7-2: the band labels and the key-layout comment (script and
  comment; no test).
- U6-1: the crab constructor docstring moved to the type; no Octopus
  docstring binds outside the module ("Turn modulation: rules, wrapper and
  the pure hook", part (h), `@doc` of both specs; the sweep "No docstring is
  detached by comment lines" refuses a foreign non-`Function` binding, red
  naming `Core.Type`).
- U6-3, U6-4, U6-5, U6-6: the comment, `_omit_example_key`, the per-rule
  catalogue loop with the converse keyword check, the Registry count
  (U6-4: "Turn modulation: rules, wrapper and the pure hook", part (h), the
  example line of both help forms; U6-5: the same testset, part (j), red by a
  scratch copy with one rule name removed from the RF help and with the RF
  wrap pretended absent; U6-6: "The Runtime Objects section is complete";
  U6-3: comment only).
- U2-1: `_survey_rebind(::TurnModulated)` rebinds `base` once ("Turn
  modulation: the RF cavity by the same wrap", part (f): an updated wrapper
  advances the cavity counter once, `id[] == 1`, and leaves
  `inner === base`; red read 2).
- U2-2: `CompositeLine` refuses a nested `Tuple` member ("Turn modulation:
  rules, wrapper and the pure hook", part (f); every `CompositeLine(` site in
  `src/`, `test/`, `examples/`, `validation/` and `profiling/` is flat).
- U2-3: every wrapper walk checked against `CompositeLine` (the same part
  (f): the loop runs the derived wrappers and `CompositeLine` over every
  walk; red by a scratch copy with a `CompositeLine`-blind fake walk).
- U1-2: the effective-spec helper in the five `LineEntry` collectors;
  override-only rules sharing an `rng_id` warn ("Turn modulation:
  effectiveness at the kernel boundary, chunking and repositioning": the
  collector reads `[7, 7]` from an override-only pair and the constructor
  warns, a mixed spec-plus-override pair warns, an override that splits a
  shared id stays silent; "Wrapped stochastic elements keep their context,
  shared streams warn, unbound apertures cannot corrupt": the radiation
  collector sees an override-only shared stream and warns; red read empty id
  lists, no warning and one false-positive warning on the split pair).
- U1-1: the stateless-rule tripwire over the derived catalogue ("Turn modulation: rules, wrapper and the pure hook",
  part (k): every derived rule in every wrapping kind's example returns the
  identical container from `realize` at turns 0 and 1 and `update` keeps
  `rule ===`; the containers seen equal the `_slot_rules` method set; red by
  a scratch rule whose successor carries another `rng_id`, 6 failures).
- U3-1: the dead `CUDA.cudaconvert(::Phase6DRep)` deleted; no Octopus method
  on `CUDA.cudaconvert` ("Turn modulation: CPU/CUDA identity and the device conversion",
  host side before the device guard; red on the unfixed tree).
- U3-3, U3-4: the two docstrings and the testset header (wording; no test).
- U3-5: the `MisalignedElement` and `RefTilted` aperture placements in the
  CUDA neighbour probe (the same testset: a recording aperture inside each
  frame wrapper inside a `CompositeLine` is not isbits on the host, isbits
  after `cudaconvert`, launches, GPU losses equal CPU losses and the surviving
  coordinates are identical; red by a scratch session without the two frame
  adapt methods: `KernelError`, non-bitstype argument).
- U4-1: the strong-strong window refusal (new testset "Turn modulation: the
  strong-strong window and receipt", 20 assertions: a three-turn table in
  beam 2's kept-whole line is refused before any turn, `next_turn` stays 0,
  the beams are untouched, no `:turn_modulation` receipt; the beam-1
  variant; the success receipt names beams `[1, 2]`; a second refusal).
- U4-2: the beam label in the window message (the same testset: the message
  names "beam 2" and not "beam 1"; red had no beam label).
- U5-1: every attribute read of a provenance group reports a torn group
  ("The run artifact records turn-modulation provenance": five missing
  attributes, `index`, `digest`, `kind`, `element`, `beam`, through three
  reader routes each give an `ArgumentError` naming the torn group path and
  the attribute; red was a `KeyError`). The whole torn family is now
  `ArgumentError`, the count errors included, which were `ErrorException`;
  no test had pinned the old type.
- U5-3: `haskey` before the ledger append (the same testset: with
  `/turn_modulation/3` pre-created, `execute!` is refused, the ledger equals
  its prior state, `next_turn` is 0, the file is closed, the provenance
  reads `[(1, 1), (2, 1), (3, 0)]`, and an unmodulated continuation still
  appends; red grew the ledger to `[0, 2, 5]`).
- U5-6: the `TaskOutput` docstring line (no test).
- U5-7: `:losses` and `:execution` reads through `_ra_require_group` (the
  same testset: a drift-only artifact's `read(out, :losses)` and a
  luminosity-only file's `read(out, :execution)` give the "carries no ...;
  present: ..." `ArgumentError`; red was a `KeyError`).

### 6.6 Ledgered and owner items

Ledgered as `docs/todo.md` rows: U2-5 (the unbound aperture, with its
numbers); U7-7 (the BPM observer and radiation on one `rng_id`); U1-4 (the
quiet-machine benchmark of the per-turn rebuild); the shared `claim_rng_id!`
path, which still turns a negative id into an `InexactError`.

Owner items, appended to the turn-modulation row: U1-1 (design D6 admits
stateful rules, the loops do not persist a successor across `execute!`
calls or plan flips; persist successors or forbid state); the U7-1 deferred
layout (ii), pink generator `k` in particle slot `k` and component
`_RULE_COMPONENT_BASE + slot`, collision-free for any N but re-keying every
pink sequence, the stride constant and the keying pin; U3-2 (the
`adapt_structure` methods drop the wrapper under every adaptor, so a
non-kernel adaptor sees the realised element only); U4-3 (the strong-strong
preflight refusals run after the receipts record intent); U5-4 (a crash
between the ledger row and the group reads as an unmodulated continuation;
document the ambiguity or write an `element_count = 0` group); U5-5 (a torn
group makes `read(out)` and `read(out, :all)` throw while the per-kind reads
work; a per-kind error value in the table of contents would keep discovery);
U5-2 (whether the artifact writer rolls back a partial `/turn_modulation`
slot on a write error, deleting the group and shrinking the ledger, or
keeps the torn-detecting reader as the guard, as today); U6-2 (the bare
`nothing` on the crab cavity, already an owner item).

### 6.7 Not verified

The second pass ran nothing on CUDA for U2, U6 and U7 (their regions never
reach the device); the effectiveness contract variant V3 (all four
exemption rows removed) was not re-run, its 43/25 following from the two
single-kind variants; the pink-pink time-scaling correlation was measured
at N = 33 only; no stateful rule exists to run end to end; nothing ran under
MPI; `_execute_strong_strong_turns!` was not read line by line (its segment
path is the shared machinery U1 read); the SplitMix method's statistics
(the Philox known-answer test only); CI has not run on the stages 3-4 tree,
which is not pushed.

Observed by the fixers in the neighbours they touched, not verified and
not fixed: a `BeamLine` without own state handed INSIDE a tuple,
`TrackingTask((line,))`, is not dissolved (`_element_tuple(::Tuple)` is
the identity) and compiles to one `CompositeLine`, so an aperture inside
it is presumably unbound without the hidden-aperture warning, which fires
only under `_line_has_own_state` (no loss measurement was taken; the
unbound-aperture row carries it); and
`_warn_duplicate_turn_modulation_streams` says "on different elements"
also when one spec object is placed twice.

## 7 Gate

[gate: pending]
