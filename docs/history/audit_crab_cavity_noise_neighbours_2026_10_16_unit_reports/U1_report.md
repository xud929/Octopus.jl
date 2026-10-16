# U1 reading-unit report: `src/elements/turn_modulated.jl` (crab cavity noise campaign audit, 2026-10-16)

Repository: Octopus main checkout `/cfs/ad/dxu/Library/Julia/Octopus` at commit `3126908`
(worktrees untouched). Julia 1.12.4, `--project=. --threads=4` (one probe also at
`--threads=1`), host `sapphirerapids`, no GPU used. Nothing in the repository was modified;
every probe lives in `result/audit_crab_noise_2026_10_16/U1/`.

## Region and provenance

- READ, every line: `src/elements/turn_modulated.jl` lines 1-1671 (the header comment and
  key-layout comment, `AbstractTurnRule`, `_rule_stream_id`, `_check_rule_sigma`,
  `WhiteNoise`, `TurnTable`, `_fnv1a64`, the spectral family `_SPECTRAL_PRESETS` /
  `_spectral_shape` / `_spectral_band` / `_spectral_key` / `_spectral_slot` / `_spectral_name` /
  `_spectral_bin_frequency` / `_spectral_plan` / `_spectral_synthesis` / `spectral_turn_table` /
  `_spectral_table` / `SpectralNoise` / `_resolve_turn_rule(s)`, `_check_pink_octaves`,
  `PinkNoise`, `_rule_kind`, `_turn_rule_names`, the `_turn_offset` methods, `_slot_draws` /
  `_slot_values` / `_slot_successors`, `_check_rule_window`, the slot protocol (`_slot_rules`,
  `_slot_nominals`, `_check_container_window`, `_check_slot_rules`, `_check_slot_table`),
  `_rule_numeric_type`, `realize`, `_realize_draws`, `TurnModulated` and its forwards, `update` /
  `update_line` / `_update_entry` / `_record_turn_draws!`, `_check_turn_window`,
  `_each_turn_rule_spec`, `_collect_turn_modulation_ids!`, `_collect_turn_tables!`,
  `_turn_rule_values`, `_turn_modulation_wrap`, `_turn_modulation_provenance!`,
  `_turn_modulation_columns!`, `_turn_modulation_slots`, `_push_rule_slot!`).
- READ for the region's promises (not audited themselves): `src/math/counter_rng.jl` 1-300
  (signatures, key packing), `src/elements/crab_cavity.jl` 46-75 and 300-470,
  `src/elements/rf_cavity.jl` 269-333 and 470-600, `src/tasks/RunArtifact.jl` 40-62 and
  553-600, `src/tasks/Tasks.jl` 195-215, 331, 386-470, 577-584, 629-680, 1108-1123, 1239,
  1246-1274, 1478-1496, 1829-1857, `src/track/Track.jl` 1-33, `src/beam/Beam.jl` 128-167,
  `src/elements/beam_line.jl` 630-660, 741, test fixtures `test/runtests.jl` 9949-10175,
  10940-10990, 11180-11216, 11594-11760, 11840-11910, 16950-16980, and the design notes
  `docs/design/spectral_turn_table.md` 108-140, 183-196, 265-310.
- The campaign diff `git diff 6995151 3126908 -- src/elements/turn_modulated.jl` (987 lines,
  commits f7cfe6a, 77c0bcc, c3c6c2c) is saved as `U1/campaign_diff.patch`; the touched regions
  (relative-strength semantics in the docstrings, `_realize_draws` and the recording hook, the
  whole spectral family, `_collect_turn_tables!`) and the untouched ones (`update_line`, the
  window check, the slot check, the wrapper forwards, the collectors) were both re-walked.
- EXECUTED (read-only probes, logs beside each script in `U1/`): `probe_alloc.jl`
  (single-shape allocation matrix), `probe_alloc2.jl` (nested tuples, `CompositeLine`, many
  harmonics, timing), `probe_hetero.jl` (heterogeneity threshold, inferred types, `execute!`
  slope), `probe_confirm.jl` (direct confirmation of the end-to-end compositions, typed IR at
  N = 32/33), `probe_composite.jl`, `probe_bigN.jl`, `probe_slope.jl` (1 and 4 threads),
  `probe_cost.jl`, `probe_window.jl`, `probe_slots.jl`, `probe_spectral.jl`,
  `probe_parity.jl`; shared helpers in `alloc_helpers.jl`.

## Leads

### LEAD U1-1 [high, confidence high] src/elements/turn_modulated.jl:1411-1415
Claim: `update_line` allocates 130-435 kB per turn on a 40-element line (and its docstring's
"zero allocation" is false) as soon as the line tuple holds about four distinct element types of
which two or more are `TurnModulated` -- three distinct types suffice with the recording sink --
which is the per-turn hot path of any ring carrying both a noisy crab cavity and a noisy RF
cavity; the suite's pins and the design note's numbers are taken on a two-type fixture that sits
below the threshold. Hypothesis (b).
Mechanism: `ntuple(i -> _update_entry(line[i], ctx, sink), Val(length(line)))` unrolls to
`f(1), f(2), ...` with literal indices, but each entry's type is known only through constant
propagation into the closure, which Julia declines when the closure's generic version is not
inlineable (the lesson review F1 of 2026-10-15 applied one level down to `_slot_draws`, line
1030-1050). With one modulated type beside any number of plain types the generic body is a
union-split of cheap `update(e, ctx, sink) = e` branches plus one heavy branch and stays
inlineable (measured 0 B up to 1 + 11 types); with two or more distinct `TurnModulated` types
among four, or among three with the sink, the generic body carries several non-inlineable
`update(::TurnModulated)` bodies, constant propagation is skipped, every entry infers as the
union of the line's element types (`Base.return_types` gives `NTuple{40, Union{CrabDispersion,
...}}`), and the result tuple is built from boxed values. The same mechanism reaches nested
tuples (`_update_entry(e::Tuple)`: `((e, disp), rf, (disp, (e, rf)), e)` costs 10.8 kB plain,
12.4 kB with sink) and the `ops` of a `CompositeLine` (`CompositeLine((cw, disp, rfe, e))`:
6.0 kB per `update`). End to end, `execute!` on the fast loop with no artifact reproduces the
direct number (246 kB/turn at one thread for the four-type line, 0 B for the suite's fixture).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U1/probe_confirm.jl`
-> row "crab white, disp, rf white, xy": plain 246464 B, recording 128704 B, return type
`NTuple{40, Union{...}}`; rows with three types: 0 B plain. One-liner: `julia --project=. -e 'using Octopus; set_global_rng!(seed=42); c=compile_runtime(ThinCrabCavitySpec{1}(394e6; strengthX=(2e-3,), phase=(0.1,), phase_noise=(WhiteNoise(1e-2),))); r=compile_runtime(ThinRFCavitySpec(400.8e6; voltage=12e6, e0=275e9, mc2=Octopus.PMASS_EV, phase_noise=WhiteNoise(1e-2))); d=compile_runtime(CrabDispersionSpec{Float64}(zeta1=0.1)); x=compile_runtime(XYCouplingSpec{Float64}(r1=0.1)); line=Tuple((c,d,r,x)[mod1(i,4)] for i in 1:40); ctx=TrackingContext(turn=3, seed=42); f(l,c)=@allocated update_line(l,c); f(line,ctx); println(f(line,ctx), " ", Base.return_types(update_line,(typeof(line),TrackingContext))[1])'`
-> `246464 NTuple{40, Union{...}}`; drop `x` from the pool -> `0` and a concrete tuple type.
Fix direction (not applied): a `@generated` body with literal indices for `update_line`, as
`_slot_draws` has, keeps the per-entry types without constant propagation.

### LEAD U1-2 [medium, confidence high] src/elements/crab_cavity.jl:349 (contract: turn_modulated.jl:1226-1243)
Claim: a crab cavity of 33 or more harmonics allocates 1.1-2.6 kB on every `realize`, `update`
and `update_line` call (0 B at 32 and below) although its return type infers concrete, so the
`_realize_draws` docstring's "the tuple is isbits and dead on the plain hook, so the off path
pays nothing" holds only up to 32 harmonics -- the shape white and table rules allow at any N
(only `PinkNoise` is bounded at 32 by `_check_slot_rules`). Hypothesis (b); cross-file seam (the
statement is the crab cavity's, the contract this region's).
Mechanism: the draws tuple `(dphi..., d...)` splats two `NTuple{N,T}`; Julia expands a splat
into a direct `tuple` call only while each splatted tuple is no longer than
`InferenceParams().max_tuple_splat == 32` (printed by the probe); at N = 33 the typed IR of
`_realize_draws` keeps `Core._apply_iterate(Base.iterate, Core.tuple, %1003, %1004)` (absent at
N = 32), a runtime apply that builds an argument array and boxes.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U1/probe_alloc2.jl`
-> rows N = 33 and 40: 2176 / 2624 B (all white), 1136 / 1360 B (one white or one table slot);
`probe_bigN.jl` -> the `_apply_iterate` statement at N = 33 only, return type concrete at both.
(The probe's standalone `_slot_draws` column is an artifact of passing `Float64` as a runtime
value and should be ignored.)

### LEAD U1-3 [medium, confidence med] src/tasks/Tasks.jl:1108-1123 and 1829-1857 (seam, outside the region)
Claim: with `record_turn_modulation = true` (an artifact attached), `execute!` allocates about
98 kB per turn on the suite's own two-type fixture and about 200 kB per turn on a 40-element
line of eight plain element types that carries NO modulated element, measured at one thread,
while `update_line(line, ctx, rec)` alone on the same lines allocates 0 B -- so the per-turn
cost lives in the general (segment) loop an artifact engages, not in this region's hook.
Hypothesis (b); mechanism not localized (Tasks.jl was not read for this); flagged for the Tasks
unit because the crab-noise example runs with recording on.
Mechanism: unknown; the slope scales with the number of distinct element types in the tuple
(3.2 kB/turn for one type, 98 kB for two, 200 kB for eight), which points at a per-element
dynamic dispatch over an abstractly typed tuple in the segment loop rather than at the hook.
Repro: `julia --project=. --threads=1 result/audit_crab_noise_2026_10_16/U1/probe_slope.jl`
-> "recording" column: 3200.0 (1 type), 199728.0 (8 plain types), 98415.2 (crab white + disp)
B/turn against -472.7 (i.e. 0) in the "plain" column for the same lines.

### LEAD U1-4 [low, confidence high] src/elements/turn_modulated.jl:636-637
Claim: the `spectral_turn_table` docstring's `:rayleigh` paragraph quotes the moduli's draw as
`octopus_normal_pair(seed, RNG_PHILOX, 0, rng_id, k, 2)` with a literal `0` in the turn field,
while the code (line 479) passes `slot` there since review F1; the same stale literal stands in
`docs/design/spectral_turn_table.md` (the "after landing" paragraph, about line 189-190).
Hypotheses (c) and (f).
Mechanism: the paragraph was written before F1 moved the slot into the key and was not
refreshed with the phase paragraph; a reader regenerating a resolved Rayleigh table from the
docstring gets another table.
Repro: `julia --project=. result/audit_crab_noise_2026_10_16/U1/probe_spectral.jl` -> "rayleigh
slot 2 with the pair at turn field = 0 (the docstring's :rayleigh paragraph): bitwise false",
"with the pair at turn field = slot: bitwise true".

### LEAD U1-5 [low, confidence high] src/elements/turn_modulated.jl:1475-1480
Claim: the `_collect_turn_modulation_ids!` docstring's "every rule carrying an `rng_id` field;
`WhiteNoise` and `PinkNoise` today" is a hand-copied list that omits `SpectralNoise`, which
carries `rng_id`, is collected, and is thereby what makes the shared-id warning fire for two
spectral rules on two elements (as the `SpectralNoise` docstring promises). Hypothesis (c).
Mechanism: the list predates c3c6c2c; the code is right, the prose names two of three.
Repro: `julia --project=. result/audit_crab_noise_2026_10_16/U1/probe_window.jl` -> "collectors"
section: `_collect_turn_modulation_ids!` on a spectral-only spec returns `[0x5b]` (= 91, the
rule's id).

### LEAD U1-6 [low, confidence high] src/elements/turn_modulated.jl:558-566 and 735-745
Claim: a `SpectralNoise` resolved on one element and its offline twin (`spectral_turn_table`
under the task's global seed, the same `rng_id` and the rule's slot) placed on another element
apply bitwise-identical per-turn offsets and the task constructor warns nothing: the shared-id
check finds no `rng_id` on the offline table and the equal-digest check finds no digest on the
spec-level rule, so the pair falls between the two sharing checks each docstring describes.
Hypothesis (a), low: the author must reproduce all three keys on purpose.
Mechanism: `_collect_turn_modulation_ids!` reads `rng_id` fields, `_collect_turn_tables!` reads
`digest` fields, both on the SPECS; the resolved table's digest exists only after compile.
Repro: `probe_spectral.jl` -> "crab spectral (slot 1, id 77) + crab carrying its offline twin:
0 warning(s)" and "offline twin == resolved slot-1 table bitwise: true"; two offline copies on
two elements do warn (1 warning, the digest message).

### LEAD U1-7 [low, confidence med] src/elements/turn_modulated.jl:303-309 and 373-376
Claim: a custom spectrum labelled with a preset's name (`"flat" => f -> 1/f`) yields a canonical
name byte-identical to the preset's (`spectral(flat; ...)`), so the receipt's name no longer
identifies the physics that made the table; only the digest differs. Out of hypothesis
(provenance), cheap to refuse.
Mechanism: `_spectral_shape(who, ::Pair)` accepts any non-empty label verbatim (D6/D7) and
`_spectral_name` records only the label, never `S`.
Repro: `probe_spectral.jl` -> "preset :flat vs \"flat\" => 1/f: same name true, same digest
false".

### LEAD U1-8 [low, confidence med] src/elements/turn_modulated.jl:255-269
Claim: `TurnTable.offsets` is a mutable `Vector` exposed as a field while `digest` and the
finiteness check are evaluated once at construction, so `tbl.offsets[1] = 5.0` (or `= NaN`)
after construction runs with a stale digest and name and nothing re-checks at compile or in the
receipt. Out of hypothesis (provenance), low.
Mechanism: immutable struct, mutable payload; the constructor copies the caller's vector but the
copy is reachable.
Repro: `probe_window.jl` -> "TurnTable.offsets mutated after construction: digest stale? true".

## Measured allocation (bytes per call, `@allocated` behind a function barrier after two warm-ups; Julia 1.12.4, 4 threads unless stated)

### Single shapes: every container shape, both hooks, 1 and 40 elements, Float64 and Float32 lines
All 34 rows measured 0 B in every column (`realize`, `_realize_draws`, `update`, `update+sink`,
`update_line` on a 1-element line, with sink, on a 40-element line interleaved with
`CrabDispersion`, with sink, on a 40-element homogeneous line, with sink), type-preserving, and
the sink met every element with the draws of the realisation (`probe_alloc.log`). Shapes, each
at Float64 and Float32: crab N=1 white phase; pink phase (16 octaves); table phase; spectral
phase (resolved table); white phase + pink strength; white under `x_offset` + `ref_tilt`
(`RefTilted(MisalignedElement(TurnModulated))`); crab N=2 (nothing, white) phase; (nothing,
pink4) phase; (nothing, table) strength; (nothing, spectral) phase; (white, pink4) phase with
(nothing, table) strength; (spectral, spectral) phase with (spectral, nothing) strength; RF
white phase; RF pink strength; RF table phase + white strength; RF spectral phase; RF spectral
phase + spectral strength. Note: `ThinRFCavitySpec` compiles to a Float64 cavity whatever the
input types through the voltage route and through the Float32 strength route on this tree, so
the "Float32" RF rows are Float64 cavities (a Float32 table on them is correctly refused).

### Heterogeneous 40-element lines (`probe_hetero.log`, `probe_confirm.log`)
| composition | distinct types (modulated) | plain hook | recording hook | inferred return |
|---|---|---|---|---|
| k plain types, k = 1..11, no modulated element | k (0) | 0 | n/a | concrete |
| one modulated type + k plain types, k = 1..11 | k+1 (1) | 0 | 0 | concrete |
| modulated types only, k = 1, 2 | k (k) | 0 | 0 | concrete |
| modulated types only, k = 3 | 3 (3) | 0 | 152000 | concrete |
| modulated types only, k = 4 | 4 (4) | 333312 | 174592 | `NTuple{40, TurnModulated}` |
| modulated types only, k = 5..8 | k (k) | 184320-203552 | same | `NTuple{40, TurnModulated}` |
| crab white, rf white | 2 (2) | 0 | 0 | concrete |
| crab white, disp, rf white | 3 (2) | 0 | 0 | concrete |
| crab white, rf white, xy | 3 (2) | 0 | 0 | concrete |
| crab white, disp, rf white, xy | 4 (2) | 246464 | 128704 | `NTuple{40, Union{...}}` |
| crab white, crab2 pink, disp | 3 (2) | 0 | 146752 | concrete |
| crab white, crab2 pink, rf table | 3 (3) | 0 | 204352 | concrete |
| crab white, crab2 pink, rf table, disp | 4 (3) | 170144 | 170144 | `NTuple{40, Union{...}}` |
| 17 modulated shapes + disp cycled, Float64 | 18 (17) | 435120 | 227760 | not concrete |
| 17 modulated shapes + disp cycled, Float32 | 18 (17) | 170384 | 170384 | not concrete |
| nested `((e, disp), rf, (disp, (e, rf)), e)` | 4 top-level (2) | 10800 | 12368 | concrete |
| `(CompositeLine((e, disp, rf)), disp, e)` | 3 (2) | 1856 | 5744 | concrete |
| `update(CompositeLine((e, disp, rfe)))` alone | ops 3 (2) | 0 | 2384 | concrete |
| `update(CompositeLine((cw, disp, rfe, e)))` alone | ops 4 (3) | 5968 | 3728 | concrete |
| `update(CompositeLine((e,)))`, `((e, e))`, `((e, disp))`, 40 x disp | <= 2 | 0 | 0 | concrete |

### Crab cavities of many harmonics, Float64 (`probe_alloc2.log`; all six measurements agree per row)
| N | slots | all white | one white (last phase) | one table (last strength) | pink4 on phase 1 |
|---|---|---|---|---|---|
| 1, 2, 4, 8, 15, 16, 17, 24, 32 | 2N | 0 | 0 | 0 | 0 |
| 33 | 66 | 2176 | 1136 | 1136 | refused (pink stride) |
| 40 | 80 | 2624 | 1360 | 1360 | refused |

### End to end, `execute!` slope (bytes per turn from 50 -> 250 turns, 4 particles, 40 elements; `probe_slope_t1.log`, `probe_slope_t4.log`)
| line | 1 thread, plain | 1 thread, recording | 4 threads, plain | 4 threads, recording |
|---|---|---|---|---|
| 40 x crab1 plain (1 type) | -473 (0) | 3200 | 7687 | 18477 |
| crab1..crab8 plain cycled (8 types) | -473 (0) | 199728 | 20935 | 221136 |
| crab1 white + disp (the suite's fixture) | -473 (0) | 98415 | 11463 | 110351 |
| crab1 white, disp, rf white, xy (4 types, 2 modulated) | 246183 | 248351 | 260423 | 262592 |
| crab1 white, crab2 pink4, rf table, disp (4 types, 3 modulated) | 173831 | 336039 | 192167 | 354375 |
The 4-thread "plain" baseline (7.7-21 kB/turn, growing with the tuple's size) is threading
overhead of the tracking loop, absent at one thread; the 1-thread "plain" column isolates
U1-1, the "recording" column U1-3.

### Timing and cost
`update_line` on the 40-element two-type line, plain hook: 1090 ns/turn with 20 white crab
cavities, 4226 ns with 20 (nothing, pink4) crab cavities (`probe_alloc2.log`).
`spectral_turn_table(:pink, 1e-5, (1e-4, 1e-2); turns=2^20, ...)`: 24.0 MiB allocated for an
8.0 MiB table (3.0x), 0.033 s fixed and Rayleigh alike (`probe_cost.log`; the docstring's
24.0 MiB / 3.0x holds, its 0.063 s is its machine's).

## Clean, with the evidence

- Hypothesis (a), remaining key collisions: none found. The Philox key takes all five fields at
  64 bits (particle and turn form the 128-bit counter, seed / rng_id / component the key), so a
  component above 1024 and a slot in the turn field alias nothing (`counter_rng.jl` 186-205,
  read). Measured on cells: resolved-table cells (turn = slot, particle k >= 1, components 1, 3,
  4) intersect white cells in 0 and pink cells in 0; the four slots of one crab cavity under one
  `rng_id` give 4 distinct digests, each regenerated bitwise by `spectral_turn_table` with the
  slot its name records, and distinct from the slot-0 offline table; the RF's two slots differ;
  the same explicit id on two elements gives equal tables slot for slot and the constructor warns
  (crab+crab, crab+rf, crab spectral + crab white all 1 warning; one rule on four slots of one
  element 0 warnings). The documented coincidences are real and as documented: offline slot 0
  shares 96 cells with a beam's turn-0 draws under the same seed and id, a resolved table shares
  turn `slot`'s cells with radiation (384 cells for 4 slots), a resolved table meets no turn-0
  cell. `next_rng_id!` starts at 1, so a default `SpectralNoise` never resolves with id 0.
  No code outside the file uses the rules' inner constructors (the only path to an unclaimed
  stream). Both spec walks (`_each_turn_rule_spec`, `_collect_radiation_ids!`) descend the same
  four containers.
- Hypothesis (b): see the tables; every single-shape row, every 1 + k plain composition, and
  every crab cavity up to 32 harmonics is 0 B on both hooks; the defects are U1-1 / U1-2 / U1-3.
- Hypothesis (c): the header's `octopus_normal(seed, method, turn, rng_id, particle_slot,
  component, T)` matches the signature; "pair 2 = components 3-4" matches `octopus_normal_pair`
  (`2 pair_id - 1, 2 pair_id`); the catalogue lists in `AbstractTurnRule`, the header and
  `_rule_kind` are complete; `_turn_rule_names` is derived. Stale literals: U1-4, U1-5.
- Hypothesis (d): the few-bins warning carries no `maxlog` (4 warnings for 4 constructions, two
  of them identical; 1 construction + 2 compiles = 1 warning); it is the only warning in the
  region.
- Hypothesis (e): `_check_slot_table` refuses 65 and 66 slots with a pink rule and accepts 63 and
  64, with or without a pink, and the bound is exactly the first collision (65 slots: 62
  component clashes, the first `white65 = pink1/g0`; 64 slots: 4032 distinct components); the
  compile path reaches it for N = 33 on a phase slot, on strength slot 66 and on a raw spec, while
  N = 33 all-white and N = 40 with a table pass; empty, `/`, duplicate and non-String labels are
  refused; `octaves` 0 and 63 refused, 1 and 62 accepted; the three-argument constructor skips
  the check and is used only by `_survey_rebind`. The window check through `execute!` on a
  10-turn table: turns 10 / (5, start 5) / (1, start 9) / (4, start 4) / (0, start 10) pass,
  11 / (6, start 5) / (1, start 10) throw naming the table, the element and the absolute window;
  a continuing task passes 5 + 5 and refuses the 11th; the walk reaches a table under
  `MisalignedElement` and on an RF strength slot; `_check_rule_window` boundaries exact (`first +
  n <= length`). A negative `first_turn` passes the scalar check but `_task_execution_window`
  refuses negative `start_turn`, so it is unreachable.
- Hypothesis (f): `TurnTable` never wraps (`BoundsError` at turn = length and at turn -1, on
  `_turn_offset` and on the by-hand `update_line`); a Float32 table on a Float64 crab and a
  Float64 table on a Float32 crab are refused at compile, a Float32 table on a Float32 crab
  realises Float32, a Float32 `sigma` on a Float64 crab is promoted; `SpectralNoise` on a Float32
  crab resolves to `TurnTable{Float32}` with `offsets == Float32.(Float64 table)` (same name,
  different digest); the keys quoted for the phases rebuild the fixed table bitwise and the
  Rayleigh table bitwise with `slot` in both turn fields; rms equals `sigma` to 4e-16 on odd N,
  a Nyquist-only band, a 1/f band and N = 2; the seed in the canonical name follows
  `set_global_rng!` at each compile and `TrackingContext().seed == global_rng_seed()`; the
  cost claim holds (above). "Identical on every backend" is reasoned, not measured (below).
  Wrapper parity: every function with a `MisalignedElement` or `RefTilted` method has a
  `TurnModulated` method and vice versa (11 functions; `probe_parity.log`).
- Refusals name their keyword and carry the numbers (`rng_id = -1`, `rng_id = 0` on the factory,
  `slot = -1`, `T = Int`, a non-callable `S`, a complex `S(f)`, a vector band, a hertz band
  without bins); a refused `SpectralNoise` claims no stream (counter unchanged across two
  refusals).

Notes, not leads: the factory prints the few-bins warning before refusing a malformed `seed`
(the `SpectralNoise` constructor avoids this for `rng_id` only); the spectral table's canonical
name does not record `T`, so regenerating a Float32 line's table offline needs `T = Float32`
from the element, not from the name; `ThinRFCavitySpec` cannot be made Float32 on this tree.

## Not checked, and why

- "identical on every backend" (WhiteNoise / PinkNoise docstrings): no GPU in this session; the
  rules realise on the host and the device sees the realised element (D8, `phase6d_track.jl`
  drop confirmed by reading), so backend independence follows from `ctx.seed`, `ctx.turn`,
  `ctx.rng_method` being equal, which was not measured on CUDA.
- "At `slot = 0` the table is bitwise the one this body produced before the slot entered the
  key" (`_spectral_synthesis` docstring): the pre-F1 code never landed in a commit (c3c6c2c is the
  only spectral commit), so only same-tree equality `t_slot0 == default` is checkable (true).
- The `SpectralNoise` docstring's recompile triggers (knob epoch, spec mutation, the loss
  record's identity via `_runtime_entries`) and the scope of the shared-id warning across the
  two beams of a strong-strong task: Tasks.jl, outside the region.
- U1-3's mechanism inside the general loop: outside the region.
- The recorder's own protocol (`_tm_end_turn!`, flushes, the artifact's readers): exercised only
  through hand-built sinks (line order met on nested lines), not through the artifact.

## Scratch artifacts
`/cfs/ad/dxu/Library/Julia/Octopus/result/audit_crab_noise_2026_10_16/U1/`: `campaign_diff.patch`,
`alloc_helpers.jl`, `probe_alloc.jl` + `.log`, `probe_alloc2.jl` + `.log`, `probe_hetero.jl` +
`.log`, `probe_confirm.jl` + `.log`, `probe_composite.jl` + `.log`, `probe_bigN.jl` + `.log`,
`probe_slope.jl` + `_t1.log` + `_t4.log`, `probe_cost.jl` + `.log`, `probe_window.jl` + `.log`,
`probe_slots.jl` + `.log`, `probe_spectral.jl` + `.log`, `probe_parity.jl` + `.log`, `smoke.log`.
