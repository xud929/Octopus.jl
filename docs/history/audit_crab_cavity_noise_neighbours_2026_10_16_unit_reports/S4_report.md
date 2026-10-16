# S4 — SEAM pass: declared schemas and metadata versus the runtime that consumes them

Repository: Octopus, main checkout at 3126908 (`git rev-parse HEAD` =
31269082e8bdb33ff0e25c12398375656772299a). Julia 1.12.4,
`--project=. --threads=4`, CUDA functional (NVIDIA RTX 4500 Ada Generation).
Scratch: `result/audit_crab_noise_2026_10_16/S4/` (probe scripts `probe_*.jl`
and their logs `probe_*.log`; nothing in the repository was modified).

## Region and provenance

READ in full: `src/tasks/RunArtifact.jl` (1439 lines); the ParamMeta /
construction_help / docstring / rule-coercion / wrap / slot blocks of
`src/elements/crab_cavity.jl` and `src/elements/rf_cavity.jl`; the rule
types, `_rule_kind`, `_turn_rule_names`, `_push_rule_slot!`,
`_turn_modulation_provenance!`, `_turn_modulation_columns!` of
`src/elements/turn_modulated.jl`; `ConfigurationOptionMeta`
(`src/policies/Policies.jl:1-70`); `ParamMeta`, `validate_element_metadata`,
`_check_declared_defaults!`, both `element_help` forms
(`src/knowledge/Knowledge.jl`); the task schemas, the RunArtifact / observer
blocks of `validate_configuration_metadata`, the `:strong_strong_output`
receipt and the `configuration_report` output entry
(`src/tasks/strongstrong/interface.jl`); `tracking_task_option_schema`,
`configuration_report(::TrackingTask)`, the `:turn_modulation` receipt site,
`_turn_modulation_entries` (`src/tasks/Tasks.jl`); the observer schemas and
receipt sites (`src/tasks/BeamObservers.jl`, `src/tasks/BPMObserver.jl`);
`PublicConfigurationEffectivenessContract` (`src/contracts/Contracts.jl:195-720`)
and `DEFAULT_INACTIVE_ELEMENT_PARAMS` / `_perturb_candidates`;
`src/examples/Examples.jl` whole; `src/registry/Registry.jl:1-190`; the F4
tripwire and the record/receipt testsets (`test/runtests.jl:10355-10560,
16740-16960, 17020-17100`); `docs/design/run_artifact.md` (schema, series,
options), `docs/design/turn_modulation.md` 4.1, 4.4, 4.5, 5.6,
`docs/design/turn_modulation_record.md` 3, 8, 9, `docs/public_api.md`
100-135 and 195-340, `docs/comprehensive_audit.md` Measured Lessons 4 and 11,
the example header and `output` block (`examples/crab_cavity_noise.jl`),
the harness header (`test/examples/crab_cavity_noise.jl`), `docs/todo.md`
rows 28, 61, 63.

EXECUTED (all at 3126908; logs beside the scripts):

- `probe_receipts.jl` — which receipts carry `append`, `capacity`,
  `record_turn_modulation` under `TrackingTask` (bare, +MomentObserver,
  +BPMObserver, +CoordinateSnapshotObserver) and `StrongStrongTask`; the
  emitted `:turn_modulation` receipt and artifact reader shapes;
  `configuration_report` of both tasks.
- `probe_fifth_rule.jl` — `struct FifthRule <: AbstractTurnRule` injected
  INTO `Octopus` (the derived catalogue filters on `parentmodule`) with
  `_turn_offset` and `_rule_kind(::FifthRule) = :fifth`; the F4 tripwire's
  assertions replicated in-process; both validators; a run with the rule
  through the receipt, the file and the readers; a `SpectralNoise` run's
  file kind.
- `probe_schema.jl` — the schema table, every invalid value, task schemas
  versus constructor keywords, the ParamMeta table, `element_help` lines,
  `solver_help()`, the example catalogue entry versus exports and script,
  `registry_snapshot_markdown()` versus the committed snapshot.
- `probe_kinds.jl` — a run with all seven producers (luminosity via
  `ThinStrongBeamSpec`, moments, snapshot, bpm, losses via `ApertureSpec`,
  execution, turn_modulation): top-level groups versus `_RA_KINDS`;
  `read(out)`, `read(out, :all)`.
- `probe_request_vs_resolved.jl` — `append=true` on a path that does not
  exist and `record_turn_modulation=true` on an unmodulated strong-strong
  line: what the `:strong_strong_output` receipt and the configuration
  report say versus what the file shows.
- `probe_cuda.jl` — the bare-`TrackingTask` receipt question on the CUDA
  backend; CPU-versus-CUDA series.

## The schema table (hypothesis i, measured)

`run_artifact_option_schema()` at `src/tasks/RunArtifact.jl:218-245`;
constructor at `:177`.

| option | declared type | declared default | actual default (`RunArtifact(path)`) | declared consumer | receipt that carries it (measured) | tripwire catching its removal |
|---|---|---|---|---|---|---|
| `append` | `Bool` | `false` | `false` | `:strong_strong_output` | `:strong_strong_output` under `StrongStrongTask` ONLY (values `(artifact, append, record_turn_modulation)`); NOTHING under `TrackingTask`, CPU or CUDA | `test/runtests.jl:16922` (key set), `:17048` (receipt propertynames), `:17052` (consumer); the `RunArtifact` block of `validate_configuration_metadata()` (`interface.jl:2063-2075`) |
| `capacity` | `Int` (field `Int64`; constructor accepts `Integer`, so `Bool` too) | `64` | `64` | `:observer_output` | `:observer_output` of `MomentObserver` only (`capacity=7` measured); the `BPMObserver` receipt `(observer, name, turn)` does not carry it; `CoordinateSnapshotObserver` emits no receipt; the luminosity rows and the turn-modulation series batch by it with no receipt | `:16922`, `:16928` (`default == 64`); `PublicConfigurationEffectivenessContract` pins `capacity=2` through MomentObserver receipts (`Contracts.jl:538-551`) |
| `record_turn_modulation` | `Bool` | `false` | `false` | `:strong_strong_output` | `:strong_strong_output` under `StrongStrongTask` ONLY; nothing under `TrackingTask` (the file's `series` dataset is the evidence, as documented) | `:16922-16927`, `:17048-17051`; the testset "The run artifact records the realised turn modulation" |

Invalid values (measured): `capacity=0`, `-1`, `false` -> `ArgumentError` naming
`capacity`; `capacity=2.5`, `1.0`, `"64"` -> `TypeError: in keyword argument
capacity, expected Integer` (names the keyword); `capacity=true` -> ACCEPTED as
1; `capacity=UInt8(3)` -> 3; `record_turn_modulation=1`, `"true"` ->
`ArgumentError` naming the keyword and the value; `append=1`, `"true"`,
`nothing` -> `TypeError: non-boolean (Int64) used in boolean context` (Julia
1.12.4's wording for a `::Bool` keyword mismatch; the keyword is NOT named);
a misspelled keyword -> `MethodError`.

ParamMeta (measured): `thin_crab_cavity.phase_noise` unit `"rad"`, default
`()`, stored `(nothing,)` / `(nothing, nothing, nothing)` for N = 1 / 3;
`strength_noise` unit `""`, default `()`; `thin_rf_cavity.phase_noise` unit
`"rad"`, default `nothing`; `strength_noise` unit `""`, default `nothing`;
no `alternatives` anywhere; every meaning and both `construction_help`s name
all four rules; `ALLOWED_PARAM_UNITS = ["", "Hz", "m", "rad"]`;
`validate_element_metadata().passed == true` (its `_check_declared_defaults!`
compiles omitted-versus-declared-default maps, so `()` and `nothing` pass by
construction, non-circularly).

## Leads

### LEAD S4-1 [medium-low, confidence high] src/tasks/RunArtifact.jl:218-245
Claim: Under `TrackingTask` not one receipt carries any of the three artifact options; the declared consumers are reachable only from `StrongStrongTask` (`append`, `record_turn_modulation`) or only when a `MomentObserver` is present (`capacity`).
Mechanism: `:strong_strong_output` is recorded solely in `interface.jl:2619`; `TrackingTask` has no output receipt (`Tasks.jl` records `:tracking_turn_timing`, `:turn_modulation`, `:tracking_luminosity_route`, `:isolated_tracking`). `:observer_output` is recorded only by `MomentObserver` (`BeamObservers.jl:831`, with `capacity`) and `BPMObserver` (`BPMObserver.jl:296`, without it). The luminosity rows, the BPM artifact rows and the turn-modulation series all batch by `art.capacity` with no receipt. The docstring admits the `TrackingTask` gap for `record_turn_modulation`; measured, it holds for all three options on both backends. The F3 shape (a declared consumer that never carries the value) on the weak-strong task; `docs/todo.md` row 28 (open, 2026-10-15) ledgers the contract-side half of this (no schema-driven sweep) but not the receipt gap itself.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S4/probe_receipts.jl` — case `[A]` prints `consumers: [:cpu_logical_workers, :tracking_turn_timing, :turn_modulation]` and `receipts carrying each option key: Dict{Symbol, Vector{Symbol}}()` for `RunArtifact(append=true, capacity=7, record_turn_modulation=true)`; `[B2]`/`[B3]` print the same empty Dict with a BPM or snapshot probe; `[C]` shows the strong-strong receipt carrying `append`/`record_turn_modulation`/`artifact` and still nothing for `capacity`. `probe_cuda.jl` prints the same empty carrier list on CUDA.

### LEAD S4-2 [medium-low, confidence high] src/tasks/strongstrong/interface.jl:2619-2624
Claim: The `:strong_strong_output` receipt (the declared consumer of `append` and `record_turn_modulation`) carries the REQUESTED values, not what the artifact resolved, and `configuration_report` reports the request as `:resolved`.
Mechanism: The receipt is recorded at `:2619`, before `prepare_run_artifact!` at `:2673` decides `fresh = !append || !isfile || filesize == 0` and builds the recorders. With `append=true` on a path that does not exist the receipt says `append = true` while the file is created fresh; with `record_turn_modulation=true` on a line with no modulated element the receipt says `true`, `configuration_report` says "continuing the run artifact ..., recording the turn-modulation series" with status `:resolved`, and nothing is continued or recorded (`/turn_modulation` absent, zero recorders). The code comment calls this "the REQUEST, as `append` is"; Measured Lesson 11 is about exactly a receipt that echoes the request. The resolution (`fresh`, recorder count per beam) is available at prepare and is reported nowhere.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S4/probe_request_vs_resolved.jl` — prints `[pre] isfile(path) = false`, `[receipt] (artifact = ..., append = true, record_turn_modulation = true)`, `[resolved] file created fresh ...: true; /turn_modulation present: false; provenance entries: 0`, and the `:resolved` configuration-report line.

### LEAD S4-3 [low, confidence high] src/tasks/BeamObservers.jl:785-791 (out of hypothesis: pre-existing, 2026-08-18 artifact migration)
Claim: `CoordinateSnapshotObserver` declares `:observer_output` as the consumer of `name` and `npart` but never records an `:observer_output` receipt; `BPMObserver`'s `artifact` option (`BPMObserver.jl:410`) declares the same consumer and its receipt carries neither `artifact` nor `capacity`.
Mechanism: `observe!(::CoordinateSnapshotObserver, ...)` (`BeamObservers.jl:868-895`) calls `_ra_push_probe_rows!` and no `_record_execution!`; the only `:observer_output` sites in `src/` are `BeamObservers.jl:831` (MomentObserver) and `BPMObserver.jl:296` (`(observer, name, turn)`). `validate_configuration_metadata` checks only that a consumer is NAMED (`interface.jl:2176-2181`), so the F3 shape is invisible to it, as the 2026-10-15 review found for `record_turn_modulation`. The same seam the campaign's `capacity` consumer relies on.
Repro: `probe_receipts.jl` case `[B3]` prints `consumers: [:cpu_logical_workers, :hook_schedule, :multi_process_collective, :tracking_turn_timing, :turn_modulation]` (no `:observer_output`) for a `TrackingTask` whose only hook is `ScheduledObserver(CoordinateSnapshotObserver(; name="snap"))`; case `[B2]` prints `:observer_output receipt keys: [(:observer, :name, :turn)]` for `BPMObserver("b"; artifact=true)`. Static: `grep -n "_record_execution!(:observer_output" src/tasks/*.jl` -> two sites.

### LEAD S4-4 [low, confidence high] src/elements/crab_cavity.jl:17-18 and src/elements/rf_cavity.jl:244-246
Claim: The `?ThinCrabCavitySpec` and `?ThinRFCavitySpec` docstrings hand-list the rule catalogue as `WhiteNoise`, `PinkNoise` or `TurnTable` and omit `SpectralNoise`; the fourth rule has already slipped past these lists at HEAD.
Mechanism: The F4 tripwire derives the catalogue from the `AbstractTurnRule` tree and checks `parameter_schema(...).phase_noise.meaning`, `strength_noise.meaning` and `construction_help` (`test/runtests.jl:10427-10440, 10480-10500`), but the only docstring check is `occursin("phase_noise", string(@doc ThinCrabCavitySpec))` (`:10384-10387`). The two docstrings are the `?` surface `docs/public_api.md:202-205` points users to beside `element_help`. Hypothesis (c) confirmed by the fourth rule, not only by the injected fifth.
Repro: `julia --project=. -e 'using Octopus; println(occursin("SpectralNoise", string(@doc ThinCrabCavitySpec)), " ", occursin("SpectralNoise", string(@doc ThinRFCavitySpec)))'` -> `false false`; `probe_fifth_rule.jl` prints the same two lines plus `names FifthRule? false`.

### LEAD S4-5 [low, confidence high] src/tasks/RunArtifact.jl:86-87 and :1233, src/elements/turn_modulated.jl:919, docs/design/run_artifact.md:133
Claim: The artifact's slot `kind` vocabulary is hand-copied in four places as "white, pink or table" and no tripwire ties it to `_rule_kind` of the rules a compiled line can hold; a non-resolving new kind round-trips through the receipt, the file attribute and the readers unvalidated while every one of these lists stays silent.
Mechanism: `_rule_kind` has four methods (`turn_modulated.jl:925-928`, `:spectral` for the spec-level rule that `_resolve_turn_rule` turns into a `TurnTable`, so the three-kind file vocabulary is CORRECT at HEAD — measured: a `SpectralNoise` slot lands as kind `table` named `spectral(flat; sigma=..., ...)`). But `_push_rule_slot!` is generic over any `AbstractTurnRule`, `_ra_write_turn_modulation!` writes `String(s.kind)` and `_ra_turn_modulation` reads `Symbol(attr)` with no vocabulary check, so the injected `FifthRule` produced receipt kind `:fifth`, file attribute `fifth` and reader kind `:fifth` with no refusal; only the F4 pin at `test/runtests.jl:10417` (a hand-pinned set compared to the derived one, the right shape) and the meaning/help checks fire, and they say nothing about these four texts. Measured Lesson 4's shape (one authoritative source, consumers derive, a declaration-to-coverage tripwire) is satisfied for the catalogue and not for the kind vocabulary the docs promise.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S4/probe_fifth_rule.jl` -> `[F4 pin] ... false (the tripwire FIRES)` x4, `[validators] ... true (does NOT notice)` x2, `[run] receipt slot kind = fifth`, `[run] artifact slot kind = fifth`, `[run] file attr kind = fifth`, `[spectral] artifact slot kind = table`. Static: `grep -n "white\`, \`pink\` or \`table" src/tasks/RunArtifact.jl docs/design/run_artifact.md`.

### LEAD S4-6 [low, confidence high] src/tasks/RunArtifact.jl:177
Claim: `capacity::Integer` admits `Bool`, so `RunArtifact(path; capacity=true)` is accepted as capacity 1 (a configuration nobody wrote, read silently), and `append=1` is refused by a `TypeError` that does not name the keyword.
Mechanism: `Bool <: Integer` in Julia; `cap = Int(capacity)` turns `true` into 1 and `false` into the by-name refusal "capacity must be at least 1; got 0". The schema declares `Int`. `append::Bool` relies on the keyword sorter's check, whose Julia 1.12.4 message is "non-boolean (Int64) used in boolean context" — `record_turn_modulation` got its own by-name check for exactly this reason (the constructor comment) and `append` did not. `docs/design/run_artifact.md:243-248` claims by-name refusal only for `record_turn_modulation` and `capacity`, so this is a loud-beats-silent gap rather than a documentation contradiction.
Repro: `julia --project=. -e 'using Octopus; println(RunArtifact("x.h5"; capacity=true).capacity); try RunArtifact("x.h5"; append=1) catch e; showerror(stdout, e) end'` -> `1` then `TypeError: non-boolean (Int64) used in boolean context`.

### LEAD S4-7 [low, confidence high] src/registry/Registry.jl:132
Claim: The registry snapshot's "## Examples" section lists the three `AbstractExample` subtypes and never the `example_catalog()` entries, so the crab example (and every catalogue entry) is absent from `docs/registry_snapshot.md` and from `summarize_registry().examples`.
Mechanism: `registry_snapshot_markdown` calls `_write_type_section(io, "Examples", reg.examples)` over `_subtypes_recursive(AbstractExample)`; `example_catalog()` (the U12-16 fix `Examples.jl` describes as the answer to "which examples should an agent imitate?") is not consulted by `build_registry`, the snapshot or `summarize_registry`. The snapshot regenerates identically (so this is the design as landed, not drift) and the Definition of Done's "every new public object is in docs/registry_snapshot.md" is unmet for the catalogue entry, `RunArtifact`, `run_artifact_option_schema`, the four rule types (the design note 4.1 records the rules as "documented objects, not registry objects"; the snapshot lists `TurnModulated` under Runtime Objects only).
Repro: `grep -c "crab_cavity_noise\|RunArtifact\|SpectralNoise" docs/registry_snapshot.md` -> `0`; `julia --project=. -e 'using Octopus; println(summarize_registry().examples); println(length(example_catalog()))'` -> `[:BenchmarkExample, :ReferenceExample, :ResearchStudyExample]` and `5`.

### LEAD S4-8 [low, confidence medium] src/tasks/RunArtifact.jl:951-953
Claim: `_RA_KINDS` is a hand-copied list of the artifact's seven product groups with no suite tripwire against the writers' group names; it is correct at HEAD.
Mechanism: The writers create `luminosity`, `execution`, `turn_modulation` (prepare), `moments`/`snapshot`/`bpm` (`_ra_bind_probe!`), `losses` (`_ra_write_losses!`); `read(out, kind)` refuses a kind outside the list and `read(out, :all)` iterates the file's top-level keys and calls `read(out, Symbol(k))`, so a new producer group would make `:all` THROW ("unknown artifact product") — loud, which is why this is low. `grep -n _RA_KINDS test/runtests.jl` finds nothing.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/S4/probe_kinds.jl` -> `written ⊆ kinds: true; kinds ⊆ written: true; diff kinds∖written = Set{String}()` over a run with all seven producers, and `[read :state] ArgumentError: unknown artifact product :state`.

### LEAD S4-9 [low, confidence medium] src/tasks/Tasks.jl:624 and src/elements/turn_modulated.jl:1554-1575
Claim: The `:turn_modulation` receipt's element entries are `(element, beam, slots)` and its top level `(elements, first_turn, turns)`, but the only suite pin of the receipt's shape is the slot entry's six names (`test/runtests.jl:16905`), and the walk's docstring documents the pre-`beam` entry `(element, slots)` with `kind` as `:white, :pink or :table`.
Mechanism: `_turn_modulation_entries` adds `beam` (documented there); `_turn_modulation_provenance!`'s docstring is the one the artifact writer and `_push_rule_slot!` cite as "the shape both consumers rely on". Nothing pins `propertynames(receipt.values)` or `propertynames(elements[1])`, so a renamed or dropped `beam`/`first_turn` would pass the suite while `_ra_write_turn_modulation!` reads `entry.beam`. The artifact reader's shapes (`(execution, elements, state)`, element `(element, beam, first_turn, turns, slots)`, slot `+ nominal, series`) match `?turn_modulation_provenance`, `run_artifact.md` and `turn_modulation_record.md` 9 exactly (measured).
Repro: `probe_receipts.jl` case `[A]` prints `:turn_modulation receipt values keys: (:elements, :first_turn, :turns)`, `element entry keys: (:element, :beam, :slots)`, `slot entry keys: (:slot, :kind, :rng_id, :digest, :name, :length)` and the three artifact shapes; `grep -n "(:element, :beam, :slots)\|(:elements, :first_turn, :turns)" test/runtests.jl` -> nothing.

### LEAD S4-10 [low, confidence high] src/tasks/Tasks.jl:85-100 and :227-260 (out of hypothesis; the concrete instance of open todo row 63)
Claim: `TrackingTask` accepts `artifact` (and `loss_report`) as public constructor keywords stored in fields, yet `tracking_task_option_schema()` declares only `record_turn_times` and `luminosity_tracking`, and `configuration_report(::TrackingTask)` has no output entry at all, while `StrongStrongTask` declares `artifact` with consumer `:strong_strong_output` and reports path/append/record (not capacity).
Mechanism: The validator's task block checks `keys(schema) ⊆ fieldnames` and defaults, never the converse, so a keyword without a schema entry is invisible (row 63's family). For the campaign this is the carrier of every artifact option on the weak-strong task: no schema, no report, no receipt (S4-1).
Repro: `probe_schema.jl` prints `TrackingTask ctor kwargs: [..., :artifact, :record_turn_times, :luminosity_tracking]`, `tracking_task_option_schema keys: (:record_turn_times, :luminosity_tracking)`; `probe_receipts.jl` `[CR]` prints `configuration_report(TrackingTask) keys: (:policy, :actions, :observers, :record_turn_times, :luminosity_tracking)`, `mentions artifact? false`.

## Clean (with the evidence)

- Declared defaults equal constructed defaults for all three artifact options and every option names a consumer: the `RunArtifact` block of `validate_configuration_metadata()` (constructs the type, touches no file — non-circular) returns `true`; the table above.
- The `:strong_strong_output` receipt carries `artifact`, `append`, `record_turn_modulation` for `StrongStrongTask` (measured, values printed in `probe_receipts.log` `[C]`), and `MomentObserver`'s `:observer_output` carries the ARTIFACT's `capacity` (`buffer_capacity = art.capacity`, `BeamObservers.jl:945`; measured 7).
- ParamMeta of `phase_noise`/`strength_noise` on both cavities: units in the controlled vocabulary (`rad`; `""` for the dimensionless relative factor), declared defaults equal the keyword defaults, declared-default compile check passes, no alternatives (correct: a rule has no enumerable alternative), meanings and both `construction_help`s name all four rules, both `element_help` forms show both parameters with the unit on the phase line, `DEFAULT_INACTIVE_ELEMENT_PARAMS` rows present for both kinds with their reasons (`Contracts.jl:2895-2909`); `validate_element_metadata().passed == true`.
- The F4 tripwire is non-vacuous and fires on an injected fifth rule on all four fronts (derived-set pin, crab meaning, crab and RF `construction_help`); `_turn_rule_names()` derives the new member (`FifthRule, PinkNoise, SpectralNoise, TurnTable, WhiteNoise`).
- Relative strength semantics `S (1 + d)` are stated consistently in both ParamMeta meanings, both construction_helps, both container docstrings, `?turn_modulation_provenance`, `run_artifact.md`, `turn_modulation_record.md` D3/D7/8.3 and `public_api.md`; the artifact's nominal attributes carry what a reader needs (`nominal_phase`, `nominal_strengthX`, `nominal_strengthY`; RF `nominal_phase`, `nominal_strength`), measured in the record testset's shapes and in `[A]`.
- `_RA_KINDS` equals the set of groups a seven-producer run writes; `read(out)` (TOC with series as row count 3) and `read(out, :all)` succeed over all seven.
- Example catalogue entry: all eight object types exported, the script names each, the named harness and study exist, `example_script_path` resolves; `registry_snapshot_markdown() == docs/registry_snapshot.md`; all eleven `*_option_schema` bindings are exported, `run_artifact_option_schema` among them.
- CUDA arm: identical receipt set (no option carrier, S4-1), series bitwise equal between CPU and CUDA over 3 turns, file kinds `white`/`table`.
- Hypothesis (j), circularity: none found. The RunArtifact validator block measures a constructed instance; `_check_declared_defaults!` compiles omitted-versus-declared maps; the F4 tripwire compares a type-tree derivation against a literal pin and the meaning text.
- `solver_help()` does not mention the artifact options — by design: the artifact has no `*_help` printer (the help surface is `construction_help`, `diagnostics_help`, `element_help`, `solver_help`); its metadata is `run_artifact_option_schema()` and `?RunArtifact`, as `public_api.md:111-124` says. The example and harness declare no `ConfigurationOptionMeta` of their own; `input.output.capacity` and `.record_turn_modulation` are consumed at `examples/crab_cavity_noise.jl:684-685`.
- `strong_strong_task_option_schema().artifact` declares `Union{Nothing,RunArtifact}` while the constructor also takes a bare path (sugar) — intentional, documented in the meaning.

## Unchecked, and why

- The suite's F4 testset itself was not run with the injected rule (its assertions were replicated in-process; running `test/runtests.jl` sections standalone needs the suite's helpers). The `validate(PublicConfigurationEffectivenessContract())` run was not executed (a full-lane gate item; its RunArtifact use was read: `capacity=2` through MomentObserver receipts only, `Contracts.jl:538-551`, as open todo row 28 states).
- The MPI arm (rank-0-only recorder, non-root `_turn_modulation_sink === nothing`) was not executed; read only.
- Cross-file seams noted and left to the auditor: the two observers' missing/short `:observer_output` receipts (S4-3) and the `TrackingTask` schema/report gap (S4-10) sit outside the campaign's touched declarations.
