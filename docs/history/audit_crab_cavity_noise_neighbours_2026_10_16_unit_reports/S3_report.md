# S3 -- seam pass: the walkers over a compiled line

Audit crab_noise 2026-10-16, reading unit S3. Repository Octopus, main checkout
`/cfs/ad/dxu/Library/Julia/Octopus` at `3126908` (clean apart from the
untracked `docs/history/audit_crab_cavity_noise_neighbours_2026_10_16.md`).
Julia `--project=. --threads=4`, CUDA active (`Octopus._HAS_CUDA == true`,
one CUDA arm executed). No repository file was modified; probe scripts and
logs live in `result/audit_crab_noise_2026_10_16/S3/` (git-ignored scratch).

## Region and provenance

The seam: every walker that traverses a compiled line (or the spec line it
compiles from) looking for turn-modulated elements, which must agree element
for element and slot for slot. Every line of the following was read:

- `src/elements/turn_modulated.jl` 700-1000 (SpectralNoise, resolution,
  `_turn_offset`), 1090-1320 (slot protocol, container checks, the wrapper),
  1320-1760 (hook, walks, collectors, provenance and columns walks, slot
  builder);
- `src/tasks/Tasks.jl` 130-232 (constructor), 300-590 (spec-side walks,
  `_effective_spec`, warnings, `_collect_spec_s!`, `_element_tuple`),
  590-740 (`_collect_declared!`, `_turn_modulation_entries`, `execute!`),
  940-1260 (task executor, both turn loops), 1260-1500 (`_runtime_entries`,
  bind apertures/survey, `_survey_rebind`), 1560-1880 (runtime line
  construction, plan builder, segments, segment update);
- `src/tasks/RunArtifact.jl` 286-600 (prepare, provenance writer, series
  creation, recorder, per-turn protocol);
- `src/tasks/strongstrong/interface.jl` 2370-2410, 2570-2700, 2800-2900,
  3090-3290 (constructor warning, window checks, receipt, columns, turn loop,
  blocks, physics line);
- `src/elements/beam_line.jl` 54-200, 240-420, 620-760 (LineEntry, overrides,
  dissolution, own state, CompositeLine, line compile);
- `src/elements/crab_cavity.jl` 186-240, 340-470; `src/elements/rf_cavity.jl`
  376-600 (coercion, wraps, slot declarations, `_turn_rule_values`);
- `src/knowledge/Knowledge.jl` 1005-1035, 1370-1410 (`_compiled_matches_runtime`,
  the three-wrap compile entry); `src/knobs/Knobs.jl` 1025-1095;
  `src/tasks/BeamObservers.jl` 228-262;
- `test/runtests.jl` 8215-8245, 10220-10335, 10536-10625, 15016-15120,
  16755-16835, 17040-17100, 17519-17640 (the ownership tripwire, the
  container tripwires, the Core.Box sweep, the recorder and receipt pins).
- References: `docs/design/turn_modulation.md` section 4,
  `docs/design/turn_modulation_record.md` section 9,
  `docs/history/turn_modulation_record_2026_10_15.md` section 4,
  `docs/experiences.md` 1450-1485.

Executed: `S3/probe_walkers.jl` (log `S3/probe_walkers.log`, 371 lines) and
`S3/probe_followup.jl` (log `S3/probe_followup.log`). Both exit 0; the one
`FAIL` row in the first log is a wrong expectation of mine, corrected and
re-measured in the follow-up (section "Corrected expectations").

## Participants enumerated

Every method found by `grep -rn` over `src/` and `ext/` (no participant lives
in `ext/`). "Containers" lists what the walker descends.

| Walker | Side | Where | Containers descended |
|---|---|---|---|
| `_turn_modulation_provenance!` | runtime | turn_modulated.jl 1577-1587 | Tuple, TurnModulated (leaf), MisalignedElement, RefTilted, CompositeLine; fallback = skip |
| `_turn_modulation_columns!` | runtime | turn_modulated.jl 1606-1628 | the same five |
| `_turn_modulation_entries` | runtime | Tasks.jl 624 | wraps the provenance walk with `beam` |
| `_check_turn_window` | runtime | turn_modulated.jl 1431-1442 | the same five |
| `update` / `update_line` / `_update_entry` | runtime | turn_modulated.jl 1346-1415 | Tuple (nested tuples via `_update_entry`), TurnModulated, MisalignedElement, RefTilted, CompositeLine |
| `_survey_rebind` | runtime | Tasks.jl 1453-1497 | CompositeLine, MisalignedElement, RefTilted, TurnModulated (rebinds `base` once, `inner := base`); applied per top-level `PhysicsEntry` by `_bind_survey_entry` |
| `_descend_strong_beams!`, `_hidden_strong_beam_count` | runtime | Tasks.jl 1773-1817 | Union of the three wrappers, CompositeLine |
| `_append_runtime_line!` | spec -> runtime | Tasks.jl 1575-1611 | Tuple, AbstractVector, LineEntry (`compile_runtime(entry)`), any spec via `_runtime_or_existing`; a bare `ElementSpec{:line}` compiles to ONE `CompositeLine` whatever its own state |
| `_build_tracking_plan` / `_append_tracking_segments!` | runtime | Tasks.jl 1678-1750 | entries in order; fused run flushed at observer/action entries and isolated strong beams |
| `_split_strong_strong_line` / `_strong_strong_physics_line` | spec -> runtime | interface.jl 3149-3185, 3245 | blocks split at `StrongStrongCollision`, each element through `_append_runtime_line!`; physics line = PhysicsEntry elements over blocks in order |
| `_each_turn_rule_spec` (-> `_collect_turn_modulation_ids!`, `_collect_turn_tables!`) | spec | turn_modulated.jl 1456-1520 | Tuple, AbstractVector, LineEntry (`_effective_spec`, overrides merged), ElementSpec{:line} (entries), ElementSpec (leaf) |
| the knob walk (`_has_knob_parameters`, `resolve_knobs`, `_knob_param_sites!`) | spec | Knobs.jl 1034-1085, beam_line.jl 160-165, 879 | Tuple, AbstractVector, ElementSpec, LineEntry, ElementSpec{:line}; never a runtime wrapper (a knob change recompiles the whole line); rule objects pass through `_resolve_knob_param(v) = v` untouched |
| the recorder protocol (`_record_turn_draws!`, `_tm_begin_turn!`, `_tm_end_turn!`) | runtime | RunArtifact.jl 561-595 | not a walk: a cursor over the provenance order, miscount raises |
| ownership tripwire | test | runtests.jl 10224-10310 | `wrapper_walks` (11 walks + `adapt_structure`) x (derived wrappers + CompositeLine) |

## Hypotheses and measurements

### H1 -- a walker that forgets a wrapper or a nesting

Method (`probe_walkers.jl`): a probe rule `Probe <: AbstractTurnRule` carrying
`id`, `rng_id = 1000+id`, `digest = 2000+id`, `name = "P<id>"`, whose
`_turn_offset` returns `id` and whose `_check_rule_window` records a hit;
every crab cavity `k` has nominal phase `k*0.01`. For each line: an
independent structural walk (tuples, `.inner`, `.ops`) is the ground truth;
the provenance walk, the columns walk (identity by nominal phase), the receipt
entries, the ids walk and the tables walk (spec side), the window-check hit
list, the `update_line` sink order (identity by draw) and a structural walk of
the rebuilt tuple are compared for count, order and identity; type
preservation and `realised phase == nominal + id` are checked.

Lines (all AGREE, all spec walks as expected, all realised):

1. flat `(crab1, drift, crab2)`;
2. element wraps: `RefTilted>MisalignedElement>TurnModulated`,
   `MisalignedElement>TurnModulated`, `RefTilted>TurnModulated`;
3. a kept-whole `BeamLine` with its own `x_offset` and `ref_tilt` holding a
   misaligned+tilted crab, in a task tuple -- depth six:
   `RefTilted>MisalignedElement>CompositeLine>RefTilted>MisalignedElement>TurnModulated`;
4. kept-whole inside kept-whole with modulated crabs first, middle, last and
   at every depth (five elements, deepest
   `MisalignedElement>CompositeLine>RefTilted>CompositeLine>MisalignedElement>TurnModulated`);
5. a dissolving `BeamLine` handed directly, holding a kept-whole sub-line;
6. the same bare line INSIDE a task tuple (compiles to one `CompositeLine`);
7. `LineEntry` overrides carrying the rule, the frame and the phase, line
   handed directly, and the same line inside a tuple;
8. a `Vector` as the task line, and a `Vector` nested in the tuple beside a
   kept-whole line;
9. crab + RF cavities each wrapped plus a kept-whole crab; the RF cavity in a
   dissolving line handed directly, misaligned. The RF wrapper's `base`
   carries the survey (`ds_turn` 0.5 and 0.0, the latter correct: two
   cavities at one arc position) and so does every realised cavity.
   An RF cavity inside a kept-whole `BeamLine` is refused loudly by
   `_bind_survey` ("the survey walk found 0 thin_rf_cavity spec(s) but the
   compiled line contains 1"), the documented limit.

Slot alignment under nesting (`probe_followup.jl` (c)): three 2-harmonic
cavities with `(WhiteNoise, PinkNoise)` phase rules and `(nothing,
TurnTable)` strength rules, one bare, one inside a misaligned+tilted
kept-whole line, one tilted; columns `active == [1, 2, 4]` for each,
provenance slots `["phase_noise[1]", "phase_noise[2]", "strength_noise[2]"]`,
recorded series equal to the replays of slots 1 and 2 and the table, on CPU
and on CUDA, CPU == CUDA bitwise.

Verdict: no walker forgets a wrapper or a nesting on anything the specs
admit.

### H2 -- one spec placed twice

`(c1, drift, c1)` and `repeat(BeamLine("cell", c1, drift), 2)`: two runtime
elements, two provenance entries, two receipt entries, two recorder columns,
two window hits, two draws; the ids walk yields `[1, 1]` and the shared-stream
warning fires (`Tasks.jl:431`); the tables walk yields the digest twice and
the same-digest warning fires (`Tasks.jl:460`). Semantics per walker: a
placement is an element everywhere; the ids/tables walks are per PLACEMENT
(one entry per distinct id per placement), so two placements of one spec
object are reported as two correlated elements, which they are at run time.

### H3 -- the order contract

Weak-strong, recorded with `record_turn_modulation = true`: the line
`(crab T1 misaligned+tilted, observer m1, BeamLine("K", drift, crab T2;
x_offset), drift, observer m2, crab T3 tilted)`; the one cached plan is
`[Fused, Observer, Fused, Observer, Fused]` with one modulated element per
fused segment; tables `T<k>` hold the constant `k*1e-3`; the file's element
`k` carries series `fill(k*1e-3, 4)`, name `T<k>`, nominal phase `k*0.01`;
receipt order == file order. Strong-strong: `line1 = (T1, ip, BeamLine("K",
T2; ref_tilt), drift, T3)`, `line2 = (drift, ip, T4 misaligned)`, beam 1
blocks `[1 | 3]` entries; provenance beams `[1, 1, 1, 2]`, series `k*1e-3`
in group `k`, receipt == file. So provenance order == recorder column order
== receipt order == the order `update_line` realises, under segments and
under block interleaving.

### H4 -- the ownership tripwire

`test/runtests.jl:10231-10278`: the wrapper set is DERIVED as every concrete
`AbstractTrackOp` with a field `inner` and pinned both ways against
`{MisalignedElement, RefTilted, TurnModulated}`; the walks pinned are
`_inner_method`, `_hidden_strong_beam_count`, `_descend_strong_beams!`,
`_survey_rebind`, `_requires_tracking_context`, `update`,
`_check_turn_window`, `_turn_modulation_provenance!`,
`_turn_modulation_columns!`, `track_luminous`, `track_particle`, and
`Adapt.adapt_structure` when Adapt is loaded; each must own a method narrower
than `AbstractTrackOp` for every derived wrapper and for `CompositeLine`.
Recomputed in the probe: every cell true (12 walks x 4 types).

Walkers the tripwire does not cover:

- the spec-side walks: `_each_turn_rule_spec`, `_collect_radiation_ids!`,
  `_collect_aperture_specs!`, `_collect_hidden_apertures!`,
  `_collect_declared!`, `_collect_spec_s!`, `_has_knob_parameters`,
  `_append_runtime_line!`. Their containers (Tuple, AbstractVector,
  LineEntry, ElementSpec{:line}) are hand-listed per walker; no test derives
  the container set, and the only runtime guards are the aperture count check
  in `_bind_apertures` and the two survey count checks in `_bind_survey`.
  LEAD S3-1 below is a live disagreement in this family (apertures, out of
  hypothesis). For turn modulation the spec-side and runtime-side walks were
  found consistent on every container (H1).
- `_strong_beams_of`/`_collect_strong_beams!`, `_strong_beam_units`,
  `requires_isolated_tracking`, `_bind_aperture_entry`, `_bind_survey_entry`,
  `_compiled_matches_runtime`: not wrapper walks (generic dispatchers to a
  covered walk, top-level-only binders with a loud count check, or
  structural). `requires_isolated_tracking` is deliberately not wrapper-aware;
  the hidden-beam refusal covers the isolated route.
- A new wrapper added to `src/elements` is caught for every pinned walk IF it
  has an `inner` field (the derivation rule); a wrapper holding its subject
  under another field name joins no walk check (observation LEAD S3-3). A
  registered kind compiling to such a wrapper would still be rejected by
  `_compiled_matches_runtime` in `validate_element_metadata()`.

### H5 -- spec-side versus runtime-side rules

Three crabs with `SpectralNoise(...; rng_id = 7, 7, 8)`: the ids walk (spec
side, before compile) sees `[7, 7, 8]` and the shared-stream warning fires;
the tables walk sees nothing (a `SpectralNoise` has no digest); after
compile every rule is a `TurnTable`, the provenance kind is `:table` with the
canonical `spectral(...)` name, the two `rng_id = 7` digests are equal and the
`rng_id = 8` digest differs; a deep field search of the compiled runtime tuple
finds no `SpectralNoise`. The gap between the two constructor-time checks is
LEAD S3-2.

### Core.Box and the knob system

None of the 20 walker and loop methods (`_turn_modulation_provenance!`,
`_turn_modulation_columns!`, `_turn_modulation_entries`,
`_each_turn_rule_spec`, both collectors, `update_line`, `_update_entry`,
`update`, `_check_turn_window`, `_survey_rebind`, `_bind_survey`,
`_append_runtime_line!`, `_build_tracking_plan`,
`_append_tracking_segments!`, `_execute_tracking_segment_turn!`,
`_strong_strong_physics_line`, `_split_strong_strong_line`,
`_descend_strong_beams!`, `_hidden_strong_beam_count`) lowers to a
`Core.Box` (checked on `Base.uncompressed_ir` as the suite's sweep does). The
knob system walks specs only and never a runtime wrapper; `_resolve_knob_param`
returns a rule object unchanged, so a knobbed cavity keeps its rules.

## Leads

### LEAD S3-1 [low, confidence high] src/tasks/Tasks.jl:361
Claim: the hidden-aperture warning is silent for an aperture inside a bare (no-own-state) `BeamLine` placed inside a task tuple, although that line compiles whole into a `CompositeLine` and the aperture's kill is then reported as unattributed by a message saying nothing was collimating.
Mechanism: `_collect_hidden_apertures!(out, ::ElementSpec{:line}, inside)` decides "kept whole" by `_line_has_own_state` (Tasks.jl:363), the rule by which a line dissolves inside a parent `BeamLine` or at the top of `_element_tuple`; but a line spec met as an element of the task tuple goes through `_append_runtime_line!` (Tasks.jl:1599) -> `_runtime_or_existing` (1279) -> `compile_runtime(::ElementSpec{:line})` -> one `CompositeLine` whatever its own state, so the two walkers disagree on what dissolves (the T3 class). `_collect_aperture_specs!` has no `:line` method either, so no loss record is sized, the kill falls to the unattributed path and `Tasks.jl:857` asserts "a coordinate went non-finite where nothing was collimating". The kept-whole twin (`; x_offset = 0.0`) warns at construction as the `_warn_hidden_apertures` docstring promises; the bare twin does not. Out of hypothesis (apertures, not turn modulation); the turn-modulation walks handle this very container correctly (H1 case 6).
Repro: `julia --project=. -e 'using Octopus; line=(DriftSpec(L=1.0), BeamLine("A", ApertureSpec(x_limit=2.0e-3, name="COLL_A"), DriftSpec(L=1.0))); h=Symbol[]; Octopus._collect_hidden_apertures!(h, line, false); println(h); t=TrackingTask(line); r=Phase6DRep([5.0e-3,1.0e-4],zeros(2),zeros(2),zeros(2),zeros(2),zeros(2)); println([nameof(typeof(e)) for e in Octopus._physics_line(Octopus._runtime_entries(t, r))]); execute!(t, r; turns=1)'` prints `Symbol[]`, `[:LatticeMagnet, :CompositeLine]`, then the warning "particles were lost with no aperture responsible ... unattributed = 1" (measured: 1 of 2 particles lost, loss record none); with `; x_offset=0.0` on the `BeamLine` the first line prints `[:COLL_A]` and the construction warning fires.

### LEAD S3-2 [low, confidence high] src/tasks/Tasks.jl:426
Claim: an offline `spectral_turn_table` on one element and a `SpectralNoise` on another, built with the same `(seed, rng_id, slot, spectrum, sigma, band, turns)`, compile to bit-identical tables (equal digests) and neither constructor-time warning fires.
Mechanism: both duplicate checks run at construction on the spec side: `_collect_turn_modulation_ids!` (turn_modulated.jl:1480) keys on `rng_id`, which the offline `TurnTable` lacks, and `_collect_turn_tables!` (1505) keys on `digest`, which the `SpectralNoise` lacks until `_resolve_turn_rule` (833) synthesises it at compile; the pair falls between the two checks, and no runtime-side walk compares the compiled digests that the provenance already carries. The `SpectralNoise` docstring states the two warnings jointly cover equal ids and equal digests; this mixed case is the seam between them.
Repro: `julia --project=. -e 'using Octopus; set_global_rng!(seed=0x5eed, method=:philox); off=spectral_turn_table(:pink, 1.0e-3, (1.0e-3, 1.0e-1); turns=64, seed=0x5eed, rng_id=9, slot=1); sn=SpectralNoise(1.0e-3, (1.0e-3, 1.0e-1), :pink; rng_id=9, turns=64); c(r)=ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,), phase_noise=(r,)); t=TrackingTask((c(off), DriftSpec(L=0.5), c(sn))); es=Octopus._physics_line(Octopus._runtime_entries(t)); p=Octopus._turn_modulation_provenance!(Any[], es); println(p[1].slots[1].digest == p[2].slots[1].digest)'` prints `true` (measured digest `0xf41db1fe90fc0a0b` on both, offsets identical) and the log holds no "share an rng_id" or "same digest" warning, only the few-bins warnings of the synthesis.

### LEAD S3-3 [info, confidence med] test/runtests.jl:10231
Claim: the ownership tripwire's wrapper set is derived by the field name `inner`, so a future wrapper that holds its subject under another field joins no walk check.
Mechanism: `derived = Set(T for T in _subtypes_recursive(AbstractTrackOp) if :inner in fieldnames(T))` is pinned both ways against the three known wrappers, and the product check iterates `derived` only; the design note asked for derivation from the subtypes that forward `track_particle`. A registered kind compiling to such a wrapper would still fail `_compiled_matches_runtime` (Knowledge.jl:1013-1031, the same `inner` rule) in `validate_element_metadata()`, so the gap is for a hand-built or unregistered wrapper only. Style-grade; no code today falls through it.
Repro: in a session after `using Octopus`, define `struct Bare <: Octopus.AbstractTrackOp; elem; end` and evaluate the `derived` expression of runtests.jl:10231; `Bare` is absent and no assertion in the testset names it.

## Clean list (what was compared and measured)

- Runtime walkers (provenance, columns, receipt, window check, `update_line`
  sink order, rebuilt-tuple walk) agree in count, order and identity with an
  independent structural walk on 15 lines spanning every wrapper order the
  specs admit, nesting depth up to six, `LineEntry` overrides, bare lines in
  tuples, vectors, `repeat`, both cavity kinds (`probe_walkers.log`, every
  CASE prints `AGREE(runtime walkers) = true`); the rebuilt tuple keeps its
  type and every realised phase equals nominal + the rule's value.
- Spec-side collectors (`_each_turn_rule_spec` -> ids and tables) return one
  entry per placement in the same order on every line above, including a rule
  given only through a placement override, and warn on a spec placed twice.
- Slot alignment: `columns.active == [1, 2, 4]` matches provenance slots on a
  mixed container at three nestings; recorded series equal independent
  replays per slot on CPU and CUDA, bitwise equal across backends
  (`probe_followup.log` (c)).
- Order under segments and blocks: weak-strong `[Fused, Observer, Fused,
  Observer, Fused]`, strong-strong blocks `[1 | 3]` and `[1 | 1]`; each
  constant table lands in its own group; receipt order == file order; a
  second window with `append = true` adds execution 2 with `(first_turn,
  turns) = (8, 3)` and 3 rows per element.
- `SpectralNoise`: seen by the ids walk before compile (warning fires on a
  shared id), absent from the compiled line, provenance kind `:table`.
- RF survey through the wrappers: `base.ds_turn` bound through
  `MisalignedElement`/`RefTilted`, carried into the realised cavity; RF in a
  kept-whole line refused loudly.
- Ownership: all 12 pinned walks own methods for the three wrappers and
  `CompositeLine`; no `Core.Box` in 20 walker methods; the knob walk is
  spec-side only and leaves rules untouched.
- The record's "order" sound list (history 2026-10-15 section 4) re-verified:
  the five wrapper methods of `_turn_modulation_columns!` are in the tripwire,
  segments follow line order, recorders are per beam.

## Corrected expectations and unchecked items

- `probe_walkers.log` row `FAIL weak-strong second window`: my expectation
  was wrong, not the code. A `RunArtifact` with `append = false` reopens its
  file with `"w"` on every `execute!` (`prepare_run_artifact!`, `fresh =
  !art.append || ...`), so the second window replaces the first; measured in
  `probe_followup.log` (a): replace mode leaves one execution `(8, 3, 3)`,
  append mode keeps `(0, 4, 4)` and `(8, 3, 3)` with the correct series.
- Not executed: an `IsolatedSegment` (a strong beam under luminosity
  diagnostics) between modulated elements in a weak-strong task -- the same
  `_append_tracking_segments!` flush as the observer split that was executed;
  a CUDA strong-strong arm (CPU strong-strong and CUDA weak-strong were
  executed); MPI with more than one rank (recorders on non-root ranks); the
  suite's tripwire testsets themselves were read, not run (their product was
  recomputed in the probe).
- The probe rule `Probe` is a session type; the walkers dispatch on wrappers,
  not on rules, and the artifact runs used shipped `TurnTable`, `WhiteNoise`
  and `PinkNoise` rules only.

## Scratch files

- `result/audit_crab_noise_2026_10_16/S3/probe_walkers.jl`, `.log`
- `result/audit_crab_noise_2026_10_16/S3/probe_followup.jl`, `.log`
- `result/audit_crab_noise_2026_10_16/S3/repro_s3_1.jl`, `.log` and
  `repro_s3_2.jl`, `.log`: the two lead Repro lines run as written after the
  report was drafted (exit 0; `Symbol[]`, `[:LatticeMagnet, :CompositeLine]`,
  the unattributed warning; and `true` with no duplicate warning).
