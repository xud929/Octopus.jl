# Turn modulation stages 1 and 2: hook, wrapper, crab cavity rules (2026-10-12)

Status: stages 1 and 2 of `docs/design/turn_modulation.md` (section 9)
implemented 2026-10-12, stage 2 in section 8 of this record, both reviewed
the same day with the review's fixes folded in (sections 2, 3 and 5); stages
3 (the RF cavity) and 4 (the neighbour audit) open; the gate is recorded in
section 7.

Stage 1 gives a tracking run a parameter that takes a different value on
every turn: the crab cavity's RF phase and strength, modulated by a white
rule or a per-turn table, realised once per turn on the host by a pure,
type-preserving hook, never read by a kernel, reproducible across chunked,
repositioned, CPU and CUDA runs.

## 1 What landed

- `src/elements/turn_modulated.jl` (new): the root `AbstractTurnRule` and
  its concrete rules `WhiteNoise(sigma; rng_id=0)`, `PinkNoise(sigma;
  rng_id=0, octaves=16)` (section 8) and `TurnTable(offsets; name)`, with
  `_fnv1a64`; the key layout comment and the constants
  `_RULE_COMPONENT_BASE = 1024` and `_PINK_COMPONENT_STRIDE = 64`;
  `_rule_stream_id` (`next_rng_id!` for `0`, `claim_rng_id!` otherwise);
  `_turn_offset`, `_check_rule_window`, `_rule_numeric_type`, `_rule_kind`,
  `_turn_rule_names`, `realize`; `TurnModulated{E,R}` (`base`, `inner`,
  `rule`) with its four forwards, `_inner_method`,
  `_requires_tracking_context`; `update`, `update_line`; the walks
  `_check_turn_window`, `_collect_turn_modulation_ids!`,
  `_turn_modulation_provenance!`, `_turn_modulation_slots`, the generic
  `_push_rule_slot!`; the identity `_turn_modulation_wrap`.
- `src/elements/crab_cavity.jl`: `phase_noise` and `strength_noise` with
  `ParamMeta`, construction help and the keyword `:turn_modulation`;
  `_rule_tuple`, `_is_turn_rule` (`isa AbstractTurnRule`);
  `CrabCavityNoise(phase, strength)` with its `realize`,
  `_turn_modulation_wrap`, `_check_rule_numeric_types`, `_check_rule_window`,
  `_collect_turn_modulation_ids!` (every rule with an `rng_id` field),
  `_turn_modulation_slots`.
- `src/elements/Elements.jl`: the include, after `beam_line.jl`.
- `src/knowledge/Knowledge.jl`: `compile_runtime` applies
  `_turn_modulation_wrap` innermost; `:turn_modulation` in the vocabulary.
- `src/tasks/Tasks.jl`: `update!` removed; both turn loops call
  `update_line`; the three segment types hold their tuple or element in a
  `Base.RefValue`; `_check_turn_window` in `execute!` before any turn; the
  `:turn_modulation` receipt from `_turn_modulation_entries(elems, beam)`;
  `_warn_duplicate_turn_modulation_streams`; `_survey_rebind`,
  `_descend_strong_beams!`, `_hidden_strong_beam_count`.
- `src/tasks/strongstrong/interface.jl`: the window check on both beams'
  physics lines before the loop; the `:turn_modulation` receipt and the
  artifact group for both beams (`beam` 1 then 2); the constructor's
  duplicate-stream warning across the two lines.
- `src/tasks/RunArtifact.jl`: `/turn_modulation/<slot>` written per
  `/execution` ledger row by `_ra_write_turn_modulation!` (an existing slot
  group is refused, nothing is rewritten or deleted), read by
  `_ra_turn_modulation` (counts disagreeing with the subgroups present are
  "torn"); `turn_modulation_provenance(path)`, `read(out, :turn_modulation)`
  and the toc.
- `src/tasks/BPMObserver.jl`: a comment at the reading-noise draw pointing at
  the key layout.
- `src/track/phase6d_track.jl`: `Adapt.adapt_structure` for `TurnModulated`
  (dropped to `inner`), `CompositeLine`, `MisalignedElement`, `RefTilted`,
  under `_HAS_ADAPT` alone so a CPU-only machine has them; the `track!`
  docstring says a bare `track!` tracks the nominal element.
- `src/contracts/Contracts.jl`: `_perturb_candidates` forms no candidate for
  a tuple of rules; the exemption rows for `(:thin_crab_cavity,
  :phase_noise)` and `:strength_noise` state why they are inert there.
- `src/registry/Registry.jl`: `TurnModulated` among the snapshot's runtime
  objects; `docs/registry_snapshot.md` regenerated.
- `validation/turn_modulation_spectra.jl` and its section in
  `validation/README.md` (section 8).
- `test/runtests.jl`: the testsets of section 4. Documentation:
  `docs/public_api.md` ("Turn Modulation"), `docs/knob_control.md`,
  `docs/current_runtime.md`, the design note's status, section 2 markers,
  4.1, 4.3, 4.4, 5.1, 5.5, 8 and 10, `docs/README.md`, `docs/todo.md`,
  `docs/experiences.md` (two lessons), this record.

## 2 Decisions and deviations

**The three open questions** of the note's section 10 were decided from the
note's own defaults in the owner's absence, and are the owner's to confirm:

1. A rule is allowed beside a knob-driven nominal parameter: the knob
   resolves at compile into the nominal cavity, the rule adds its offset at
   run time. The knob-composition case (pinned in the effectiveness testset)
   shows `base.phase[1]` at the knob value 0.3, the realised phase at turn 1
   equal to it plus the rule's turn-1 offset, and `base.phase[1]` at 0.4
   after `set_knob!` and a recompile.
2. `strength_noise` carries one rule per harmonic whose realised offset is
   added to both planes, which is what one cavity voltage does.
3. A `Float32` table on a `Float64` cavity is refused at compile (an
   `ArgumentError` naming parameter, index and both types), no promotion.

**Deviations from the note's sketches**, each with its reason:

- The realised element is the field `inner`, not `current`: the structural
  unwrap in `_compiled_matches_runtime` (`hasfield(:inner)`, audit U12-10)
  and the suite's derived wrapper set recognise a wrapper by that field, so
  the new wrapper is a sibling of the existing two without a hand list.
- Rules are per-harmonic scalar offset generators, not the cavity-level
  `CrabPhaseNoise{N,T}` of section 5.1: each yields one additive offset for
  one slot, `CrabCavityNoise(phase_tuple, strength_tuple)` hands each entry
  its slot (phase harmonic `i` is slot `i`, strength harmonic `i` is slot
  `N + i`), and the spec parameters are per-harmonic tuples of `nothing` or
  a rule. One rule type thus serves both parameters and any later element;
  one `rng_id` over one cavity's entries draws independently per slot, two
  cavities sharing an id draw identical values and the task constructor
  warns ("share an rng_id", a plain `@warn` like the radiation one).
- The device conversion is `Adapt.adapt_structure(to, w) = adapt(to,
  w.inner)`, not the sketched `CUDA.cudaconvert(::TurnModulated)`: `@cuda`
  converts the tuple through `adapt`, which recurses via `adapt_structure`,
  so a `cudaconvert` method on the wrapper is not reached inside the tuple.
  The three containers got the same descent; section 3 records why.
- `update!` is gone; `update` and `update_line` are exported. One hook.
- The segments hold their tuple in a `Base.RefValue`; a plan built later
  under another plan key starts from the compiled nominal elements. Exact
  for the shipped rules, functions of the absolute turn alone; a stateful
  rule would have to keep its state in the element.
- `_survey_rebind(::TurnModulated)` rebinds `base` once and reuses it when
  `inner === base` (always true at binding), so a modulated RF cavity would
  never advance the survey counter twice.
- The window check runs in `execute!` before any turn and before the stored
  turn advances, and in the strong-strong task before its loop.
- The receipt is recorded only when the line holds a modulated element, and
  the artifact group is per execution slot, `/turn_modulation/<slot>` keyed
  by the `/execution` ledger row, attributes only, never rewritten: a
  continued file keeps every generation of rules it ran, and an unmodulated
  `execute!` writes nothing for its slot.
- No new effectiveness contract, although the note's section 8 asked for
  one: the existing `ElementParameterEffectivenessContract`'s exemption table
  carries the two rule parameters as a decision, not a crash guard
  (`_perturb_candidates` forms no candidate for a tuple of rules, so without
  the rows the pair would merely count as unperturbable), and the
  kernel-boundary testset pins the effect.
- The rules' draws sit in their own band of the counter-RNG key (review
  finding S1): particle slot 0, component `_RULE_COMPONENT_BASE + slot`, a
  pink generator `k` at `+ _PINK_COMPONENT_STRIDE * (k + 1)`. The first
  draft keyed component `slot` itself, which for slots 1 and 2 is the cell a
  noisy BPM's occurrence 0 reads (components 1-2), so a cavity and a BPM
  sharing an `rng_id` drew identical normals; the layout of every consumer
  (radiation: particle id, components 1-6; BPM: occurrence, components 1-2;
  rules: the band) is written once above the constant. The keyword
  constructors follow the radiation convention through `_rule_stream_id`:
  `rng_id = 0` assigns a fresh stream, an explicit id is claimed, and the
  guards run first so a refused rule claims nothing. Behaviour change: two
  `WhiteNoise(1e-2)` without ids used to share stream 0 and warn; they now
  draw independently, as `LumpedRadSpec` and `Beam` do.
- The rule catalogue is derived, never listed by hand: `AbstractTurnRule` is
  the root, `_rule_kind` has a method per type and no fallback,
  `_turn_rule_names` builds the error messages from the concrete subtypes,
  `_is_turn_rule` is `isa AbstractTurnRule`, the id collector keeps every
  rule with an `rng_id` field, and `_push_rule_slot!` is one generic method
  reading the fields a rule has; a new rule needs `_turn_offset` and
  `_rule_kind` and nothing else, and the suite's catalogue tripwire pins the
  derived set against its instance table in both directions.
- The rule types are documented public objects, not registry objects: no
  registry root, their metadata is the cavity's `ParamMeta` for
  `phase_noise` and `strength_noise`, and the snapshot lists only
  `TurnModulated`.
- The BPM observer holds no wrapper list (U12-10 made unwrapping
  structural), so nothing was owed there although the note's section 2
  named it among the walks.

## 3 Measured

Every number is quoted at the precision the probe printed.

**The section 5.1 fixture.** Seed 42, `rng_id` 7, `sigma` 1e-2 on slot 1
(`ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,))`, Philox,
through `realize`). Before the keying moved, the design-keyed implementation
reproduced the note's table to four digits (`+2.0085e-03, +2.2566e-03,
-2.0900e-03, -6.1631e-03, -6.8644e-03, -1.4883e-02, -3.4575e-03,
-1.0113e-02` rad on turns 1 to 8, `<px>` `+9.5198e-06` on turn 8). Under the
shipped band the realised phases on turns 1 to 8 are `-6.5957e-03,
+3.9700e-04, -4.8743e-03, -9.3795e-03, -9.8049e-03, -2.7768e-03, +5.6656e-03,
-2.7639e-03` rad and the `<px>` column of a `z = 0` beam (strength 2e-3,
394 MHz) is `+1.5975e-06, +1.5013e-06, +2.6819e-06, +4.9536e-06, +7.3283e-06,
+8.0008e-06, +6.6286e-06, +7.2980e-06`; a strength rule on slot 2 (seed 42,
`rng_id` 3, `sigma` 1e-4) moves both planes by `-6.1852e-05` on turn 5 (the
old keying gave `+2.5286e-05`) and leaves the phase alone; with `N = 2` the
phase slots 1, 2 and strength slots 3, 4 are distinct draws. `realize` is
type-preserving for cavity and container and allocates `0 bytes`.

**The keying regression.** On a shared `rng_id`, the realised draw differs on
every turn 1 to 8 from the cell a noisy BPM reads (particle slot 0,
components 1 and 2) and from the one a radiation element reads (particle 1,
component 1); before the band the first was bitwise the same normal on every
turn (pinned in the rules testset).

**The rebuild.** On a 40-element line with 20 wrapped cavities `update_line`
preserved the tuple type, realised every wrapped phase, left every `base`
untouched and allocated zero bytes (`got 0 B`); the allocation and the type
are the pinned quantities.

**The digest.** `_fnv1a64` reproduced the FNV-1a 64 test vectors for `''`,
`'a'` and `'foobar'`; a table's digest is stable across constructions.

**The guardrails**, each with its refusal path. `WhiteNoise` and `PinkNoise`
refuse `-1`, `NaN` and `Inf` in the constructor (`_check_rule_sigma`, run
before `_rule_stream_id` so a refused rule claims no stream), keep `Float32`,
and `0` is a quiet rule; `TurnTable` refuses an empty vector and names the
first non-finite entry in its constructor; a table past its end on the
by-hand `update_line` path is a `BoundsError` from the explicit `checkbounds`
in `_turn_offset` (index 4 of a 3-element table); the window check refuses
one turn too many through `_check_rule_window` before any turn, naming table
and slot (`the unnamed turn table on ThinCrabCavity phase_noise[1] holds 3
turns but the window runs turns 0 to 3 (absolute, zero-based): a table never
wraps, extend it or shorten the run`; an unnamed table read `the turn table
""` before the review). A bare rule, a length-2 tuple on `N = 1` and an
entry `1.0` are refused by `_rule_tuple`, in the friendly constructor and
again in `_turn_modulation_wrap` at compile for a raw spec, the message
naming the derived catalogue.

**The task layer.** `execute!(turns=3)` on the fast loop and on the general
loop (with an artifact) tracked the realised element each turn, bitwise
equal to a hand reference; the window check refused turns 3..4 before any
turn ran and the stored turn stayed at 3; the receipt was recorded once with
2 elements, `first_turn 0, turns 2`, and not on an unmodulated run; a
stateful probe rule's successor rode the segment `Ref` across turns and
calls (`counts = [5, 5]`); two elements sharing an `rng_id` warned once
(`rng_ids = [5]`), distinct ids did not.

**The GPU probe and the finding.** On an NVIDIA RTX 4500 Ada Generation
with CUDA.jl 6.3.1: a wrapper carrying a host table is not isbits, the bare
cavity is; `cudaconvert` of the tuple dropped the wrapper to the realised
element and left the bare cavity alone; the launch with the non-isbits
wrapper in the tuple succeeded (1000 particles, 1 turn), the kick changed
`px`, and the GPU through the wrapper equalled the GPU and the CPU through
the bare cavity bit for bit. That was the design's "one untested step", and
it passed for a wrapper placed directly in the tuple. One level down it had
not: before the container methods, a wrapper nested inside `CompositeLine`,
`MisalignedElement` or `RefTilted` reached the launch unconverted and failed
with a `KernelError`, "passing non-bitstype argument ... .rule is of type
TurnTable" (text kept in the comment above the methods in
`src/track/phase6d_track.jl`). With `adapt_structure` on the three
containers, `cudaconvert` descends `CompositeLine`, a nested tuple,
`RefTilted` and `MisalignedElement` to drop every wrapper; nested placements
launch and equal the bare nested line on the GPU and on the CPU bit for bit;
an updated wrapper tracks its realised element (phase 0.6) on the GPU.

**A pre-existing CUDA defect fixed in passing** (review finding S3). The same
identity default had been failing a user-reachable line before this batch:
on the base tree 08f04e5 a recording aperture inside a kept-whole `BeamLine`
never launched on CUDA, `KernelError: passing non-bitstype argument`, through
a bare `track!` and through `execute!` alike, while the flat placement
worked, measured by the reviewer on the base tree. On this tree the same
line launches and its losses and coordinates equal the CPU's to the bit; the
neighbour probe inside "Turn modulation: CPU/CUDA identity and the device
conversion" is its regression test, and the base-tree run is its
fails-unfixed evidence.

**Metadata and sweeps.** `validate_element_metadata()` passed; the rules
testset pins that both `element_help` forms, `construction_help` and the
`ParamMeta` meaning name every rule of the derived catalogue and that
`parameter_schema` carries `phase_noise [rad]` and `strength_noise` with
default `()`; `validate(ElementParameterEffectivenessContract())` passed with
the two exemption rows applied and none stale; the `Core.Box` sweep over the
three touched files (225 methods) and the detached-docstring scan found
none, and the suite's whole-tree sweep passed as well.

**The `update` export.** CUDA.jl also exports `update`: with `using CUDA` in
the same session the bare name is ambiguous and the GPU probe had to write
`Octopus.update`; the suite, which does not import CUDA's exports, is
unaffected.

**Counts**, re-run on the folded tree before the review moved the keying:
the rule and spec probe 51 PASS, 0 FAIL; the hook, wrapper and task probe 65
PASS, 0 FAIL; the CUDA probe 15 PASS, 0 FAIL. After the review the suite
testsets of section 4, not the probes, are the evidence.

## 4 Tests

The design's tests 1 to 9 (section 8 of the note), the knob composition and
the artifact provenance group, as these testsets:

- "Turn modulation: rules, wrapper and the pure hook" (tests 2, 4, 5, 7:
  the nominal path, type stability and zero allocation past 32 elements, the
  guardrails, the derived wrapper set with its tripwire, which now lists
  `(Adapt.adapt_structure, 2)` among the wrapper walks; the rule-catalogue
  tripwire, the derived `AbstractTurnRule` set against the test's instance
  table in both directions, every rule with `_turn_offset` and `_rule_kind`,
  accepted and named in `construction_help` and the `ParamMeta` meaning; the
  S1 regression pin of section 3).
- "Turn modulation: effectiveness at the kernel boundary, chunking and
  repositioning" (tests 1 and 3 on the shipped keying, the knob composition).
- "Turn modulation: white and pink spectra" (test 9; section 8).
- "Turn modulation: CPU/CUDA identity and the device conversion" (test 6,
  the nested placements of section 3 and the kept-whole recording-aperture
  neighbour probe; CUDA-active lanes only).
- "The run artifact records turn-modulation provenance" (two execution
  slots in one file, an unmodulated continuation writing nothing for its
  slot, torn files refused by name, a strong-strong fixture recording both
  beams, the strong-strong constructor's shared-stream warning,
  `turn_modulation_provenance(path)` and `read(out, :turn_modulation)`
  agreeing with the toc).
- "The fused route carries luminosity through every wrapper" (edited from
  "all three wrappers" to take the derived set) and the aperture testset's
  `_requires_tracking_context` wrapper cases, the new wrapper as a sibling.
  Test 8 is `validate_element_metadata()`,
  `validate_configuration_metadata()` and the snapshot, already in the suite.

## 5 Ledgered, not fixed

For the owner (`docs/todo.md`, the turn-modulation row):

- `update` is also exported by CUDA.jl; a session that does
  `using Octopus, CUDA` writes `Octopus.update`. Renaming is the owner's call.
- A `TurnTable` on a ForwardDiff dual-typed cavity is refused by the numeric
  type check; tables and parameter derivatives need a decision.
- A bare `phase_noise=nothing` (not a tuple) is refused with a message; only
  `()`, tuples and vectors are accepted.
- The three section-10 decisions of section 2 were taken in the owner's
  absence from the note's defaults; the owner confirms or reverses them.
- The strong-strong task warns on a shared turn-modulation stream across its
  two lines but has no radiation duplicate-stream warning: a pre-existing
  gap, the sibling of the new warning, deliberately not closed here.
- `_requires_cuda_elementwise` has no wrapper method and sits outside the
  wrapper-walk tripwire (adding it would fail every wrapper today). Its
  consequence, pre-existing on the base tree and on this one: a misaligned
  strong beam on CUDA (`MisalignedElement{ThinStrongBeam}`) is a
  `KernelError`, the mutable beam reaching the fused launch; its own
  `docs/todo.md` row ("Misaligned strong beam on CUDA is a `KernelError`")
  states the mechanism and the fix shape.
- Stage 3 (the RF cavity by the same wrap) and stage 4 (the neighbour audit
  of the fused path, the wrapper walks and the plan cache).

Fixed in passing: the container `adapt_structure` methods closed the
pre-existing kept-whole recording-aperture CUDA defect of section 3; it is
recorded here because no todo row ever named it.

## 6 How to re-run

The probe scripts behind section 3 are git-ignored scratch, not the
evidence; the suite is: the testsets of section 4 (the CUDA one on a GPU
machine), `validate_element_metadata()`,
`validate(ElementParameterEffectivenessContract())`,
`element_help(:thin_crab_cavity)`, and `validation/turn_modulation_spectra.jl`
for section 8. The section 5.1 fixture is seed 42, `rng_id` 7, `sigma` 1e-2
on `ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,))`.

Not verified: the RF cavity under the wrap; a stateful rule end to end (only
a probe rule exercised the successor path); a strong beam under the wrap
(none declares a rule; `LuminousFusedSegment` captures its beams at plan
build on that); the probes were not re-run after the keying moved.

## 7 Gate

The two-arm full gate ran on the committed batch 1fc2cbd (one commit on
08f04e5, the tree of every section above), from the worktree, with CUDA
active on the RTX 4500 Ada and four threads, after the fast lane on the
same tree (exit 0, 314 rows, the fifteen heavyweight sections skipped
loudly, every turn-modulation testset among the rows that ran) and the
extracted source sweeps (the stage 6 pin tripwire exactly three lines,
the `Core.Box` sweep, the detached-docstring sweep, all green):

| arm | start, end (EDT) | rows | assertions | skipped |
|---|---|---|---|---|
| native | 2026-10-12 20:48:51, 23:23:29 | 329 | 148926 / 148926 | none |
| `OPENBLAS_CORETYPE=Haswell`, `-C haswell` | 2026-10-12 23:23:29, 2026-10-13 01:48:16 | 329 | 148926 / 148926 | none |

Exit 0 in both arms, `Testing Octopus tests passed`; the two arms' rows
agree name for name and count for count; no row carries a failure, error
or broken column; no `LANE SKIP` line (the full lane) and no CUDA skip
(the CUDA testsets ran, "Turn modulation: CPU/CUDA identity and the device
conversion" 28 of 28 among them). Against the previous gate (the DBA-ring
example check at ce0bdf2: 324 rows, 148544 assertions) this batch adds
five rows and 382 assertions. The box carried a load average near 28
throughout, which is why each arm took about two and a half hours where
the campaign's earlier gates took forty-five minutes.

Not verified by this gate: the push and the CI run on the pushed tree (the
runner's own CPU class), which follow on the owner's word.


## 8 Stage 2: the pink rule and the spectra

Landed 2026-10-12, in the same batch, after section 7 was reserved: stage 2
of the note's section 9 (the Voss-McCartney pink rule, the spectra script,
the band statement) and test 9 of its section 8. Every number below is
quoted at the precision the script printed.

**What landed.** `PinkNoise{T}` (`PinkNoise(sigma; rng_id=0, octaves=16)`)
in `src/elements/turn_modulated.jl` after the `TurnTable` cluster, with its
`_turn_offset` method and the constant `_PINK_COMPONENT_STRIDE = 64`,
exported, listed wherever the file enumerates its rules, and documented with
its approximation band (the note's section 5.5 asked that a built-in pink
rule state the band in its metadata). `src/elements/crab_cavity.jl` accepts
the rule (`_is_turn_rule`), is named in every rule list (the `_rule_tuple`
messages, the `phase_noise` meaning, `construction_help`, the docstrings),
reports it as a provenance slot `kind = :pink` with its `rng_id` and zeros
elsewhere (`octaves`, like `sigma`, is a spec parameter rather than
provenance; the slot shape is unchanged, so the run artifact's
`/turn_modulation` writer, which stores `String(kind)`, needed no change),
and collects its `rng_id` for the duplicate-stream warning beside
`WhiteNoise`, because a pink rule is a stochastic rule and two cavities
sharing a pink stream draw identical values; silent would have been the
defect. Since the review every such list is derived from `AbstractTurnRule`
(section 2). `validation/turn_modulation_spectra.jl` with its section "Turn
Modulation Spectra" in `validation/README.md`; `?PinkNoise` in
`docs/public_api.md`; the testset "Turn modulation: white and pink spectra"
(below); this section; the note's status line and the todo row.

**The keying and the stride.** Generator `k` of `K = octaves` is
`octopus_normal(seed, method, turn >> k, rng_id, 0, _RULE_COMPONENT_BASE +
slot + 64 (k + 1), T)` and the offset is `sigma * (sum over k) / sqrt(K)`.
Keying on `turn >> k` (an arithmetic shift of the non-negative `Int64` turn)
IS the hold: generator `k` keeps its draw for `2^k` turns without carrying
state, so the rule is a pure function of the absolute turn like `WhiteNoise`,
chunk- and reposition-invariant by construction, and `_rule_numeric_type` has
no method for it (it adapts to the element's `T`). The component stride 64
keeps the pink bands `_RULE_COMPONENT_BASE + slot + 64`, `+ 128`, ... disjoint
from the components `_RULE_COMPONENT_BASE + 1:2N` a `WhiteNoise` sharing the
`rng_id` draws on another slot of the same cavity, as long as `2N <= 64`:
assumed and documented, not enforced (a crab cavity carries a few
harmonics). `octaves` is limited to `1:62` by the `Int64` turn counter.
`sigma` is the per-turn rms: the `K` generators are independent unit
normals, so their sum over `sqrt(K)` has unit variance. Every number below
was re-measured after the review moved the rules into their component band
(section 2); the values the first run printed before the move are gone with
that keying.

**Measured, 65536 turns.** `validation/turn_modulation_spectra.jl`, seed 42,
`rng_id` 7, Philox, `WhiteNoise(1.0; rng_id=7)` and `PinkNoise(1.0;
rng_id=7, octaves=16)` on slot 1 of `ThinCrabCavitySpec{1}(394.0e6;
strengthX=(2.0e-3,), phase=(0.0,))` through `compile_runtime` and `realize`
on the absolute turns `0:65535`; power per octave band of the periodogram,
top octave 1:

```
octave band (f_rev units)      bins      white       pink
  3.1e-05 .. 6.1e-05          2      0.000      0.642   (untrusted: too few bins)
  6.1e-05 .. 1.2e-04          4      0.000      1.670   (untrusted: too few bins)
  1.2e-04 .. 2.4e-04          8      0.000      0.738
  2.4e-04 .. 4.9e-04         16      0.001      1.053
  4.9e-04 .. 9.8e-04         32      0.003      1.234
  9.8e-04 .. 2.0e-03         64      0.004      1.061
  2.0e-03 .. 3.9e-03        128      0.009      1.177
  3.9e-03 .. 7.8e-03        256      0.017      1.208
  7.8e-03 .. 1.6e-02        512      0.031      1.241
  1.6e-02 .. 3.1e-02       1024      0.064      1.177
  3.1e-02 .. 6.2e-02       2048      0.129      1.115
  6.2e-02 .. 1.2e-01       4096      0.249      1.057
  1.2e-01 .. 2.5e-01       8192      0.501      0.996
  2.5e-01 .. 5.0e-01      16384      1.000      1.000
```

Least-squares slope of `log2(power)` per octave over the 12 trusted bands:
white `+0.984`, pink `+0.010` (machine line `white_slope=0.9839
pink_slope=0.0102`). The note's two-endpoint definition over all 14 bands
gives white `+0.991` and pink `+0.049` against the note's `+1.09` and
`-0.11`: the note's demo indexed turns `1..N` with raw `octopus_normal`
components `k + 1`, this run indexes the absolute turns `0..N-1` through the
cavity in the rules' component band with the stride, so the realisations
differ, and the two lowest, untrusted bands that carry the endpoint estimate
differ most (`0.642` and `1.670` here, `2.705` and `2.416` there); the
trusted bands agree in shape, and the pink ripple over them is `0.738` to
`1.241` of the top octave, a factor 1.7 band to band, the "factor of about
1.3" the note describes being the band-to-band scatter of its own
realisation. Sample rms about zero for `sigma = 1`: white `0.9966`, pink
`0.9054`; sample std about the run's mean `0.9966` and `0.9022` (the pink
expectation of that statistic is `0.9682`, variance `1 - (2^K - 1) / (K N)`,
the slow generators landing in the mean). The pink offset on turn 40000
computed alone from a fresh compile equalled the sequence's entry exactly
(`-1.324145e-02`). Verdict `PASS`; the band table went to
`result/turn_modulation_spectra.tsv` (git-ignored). The `PinkNoise`
docstring states the band as measured here: "within a factor 1.7 band to
band across the twelve trusted octaves ... every trusted octave band within
0.738 to 1.241 of the top octave's power at 65536 turns".

**Measured, 16384 turns** (the suite's size; same seed and rules): 12 bands,
10 trusted; white slope `+0.957`, pink `-0.039` (machine line
`white_slope=0.9573 pink_slope=-0.0389`; two-endpoint over all bands
`+1.011` and `-0.022`); white rms `0.9908`, pink rms `0.8799` (sample std
`0.9908` and `0.8527`, pink expectation `0.8660`); the trusted pink bands run
`0.998` to `1.440`; turn 16383 alone equalled the sequence (`-9.907808e-01`).
Verdict `PASS` with the same tolerances, so the suite twin uses 16384 turns.

**Tolerances and their reasons.** White slope `+1 ± 0.15` and pink `0 ± 0.2`
per octave are the note's test 9, judged on a least-squares fit over the
trusted bands rather than the note's two-endpoint change (the endpoints are
the noisiest bands; the fit weighs every trusted band). The pink rms bound
`[0.8, 1.25]` is the script's own, set from the first run and kept: the
expectation is exactly `sigma` at any length, but the slow generators (holds
of `2^13` to `2^15` turns, one to four values per run) move the sample value
by several percent either way (`0.9054` at 65536, `0.8799` at 16384 under the
shipped keying); both runs are deterministic at seed 42, so the suite's twin
is a fixed number, not a flaky statistic. Statelessness is exact equality.
The two lowest bands are excluded, as the note says, for having 2 and 4 bins.

**Tests.** The testset "Turn modulation: white and pink spectra": the
reduced-size twin of the script's four verdicts, the keying pinned by the
documented formula (bitwise, in the same summation order) on slots 1 and 2
and on `octaves = 5`, one octave equal to the white draw on component
`_RULE_COMPONENT_BASE + 1 + _PINK_COMPONENT_STRIDE` and the second generator
of two holding across each pair of turns, the guardrails (`octaves` 0 and 63
refused, 1 and 62 accepted, `-1`, `NaN` and `Inf` refused, `0` quiet,
`Float32` kept, the message naming the rule, the spec message naming
`PinkNoise`), a white and a pink rule sharing `rng_id` 7 on the two slots of
one cavity differing on turn 0 with the pink equal to the slot-2 formula, one
`execute!` of six turns equal bitwise to six of one on a 50-particle beam and
unequal to the quiet cavity, zero allocation and type preservation in
`realize`, the provenance slot (`:pink`, `rng_id` 7, zeros elsewhere, the
pinned property order), a pink `strength_noise` moving both planes by the
slot-2 formula with `rng_id` 9 and leaving the phase alone, two cavities
sharing a pink `rng_id` warning once and a white-plus-pink cavity with one id
not warning. Shown red, before the keying moved (the printed values are of
the demonstration keying; the mechanism is unchanged), by making
`_turn_offset(::PinkNoise)` forward to a `WhiteNoise` of the same `sigma`
and `rng_id`: `abs(sp_slope(pp)) <= 0.2` failed with `Evaluated:
1.0196859905200972 <= 0.2` (the degenerate pink has the white slope), the
keying pins failed (`-0.5730640580628288 == -0.263532233980376` on turn 0),
and the chunking section aborted on the type-preservation assertion of
`update` (`Cannot convert an object of type
CrabCavityNoise{Tuple{WhiteNoise{Float64}},Tuple{Nothing}} to an object of
type CrabCavityNoise{Tuple{PinkNoise{Float64}},Tuple{Nothing}}`): 20
passed, 7 failed, 1 errored. Green again on the intact tree.
`validate_element_metadata()` passed; both `element_help` forms name
`PinkNoise`; `registry_snapshot_markdown()` equals the committed snapshot
(rules are not registry objects, `WhiteNoise` was never in it); the
detached-docstring and `Core.Box` sweeps passed extracted.

**Ledgered, then closed in the review pass.** The two prose enumerations
that still read `(WhiteNoise, TurnTable)` after stage 2,
`docs/current_runtime.md` and the design note's section 4.3, now name
`PinkNoise`.

**Not verified.** The FIR (note 5.4) and IIR (note 5.3) rules stay
documented only; no stage 2 CUDA run (the rule never reaches the device, the
realised element does, and stage 1's test 6 covers that path for every rule);
the band statement is measured at `K = 16` only; the `2N <= 64` assumption
behind the stride is documented, not enforced; the red run was not repeated
after the keying moved.
