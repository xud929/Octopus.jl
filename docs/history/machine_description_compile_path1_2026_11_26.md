# The machine description, batch A "compile-path, part 1": the owner's rulings of 2026-11-26 implemented (2026-11-26)

Batch A of [`../design/machine_description_followups.md`](../design/machine_description_followups.md),
section 3: rulings R2 to R6 and R8 to R11 of the owner's discussion of
2026-11-26 (R1, R7 and R12 land no code), implemented the same day as units
U1 to U8 with U9's ledgers, after the stage-5 record
[`machine_description_stage5_2026_11_25.md`](machine_description_stage5_2026_11_25.md).
The scoped neighbour audit the invariants require is
[`audit_machine_description_compile_path1_2026_11_26.md`](audit_machine_description_compile_path1_2026_11_26.md)
(its unit reports beside it). Guides: `../guides/development_workflow.md`,
`../guides/configuration.md`, `../guides/elements.md`,
`../guides/documentation.md`; the protocol `../comprehensive_audit.md` for the
audit. Branch `cp1`, based on c52d80e (the follow-ups note's commit, the tree
of the pushed stage 5 plus the note), one worktree, the units done in order
and verified red-first against `main` (c52d80e) as each landed, the whole
tree gated once. One commit on `cp1`, fast-forwarded onto `main` (the
commit that carries this record; its message carries the fast lane and
the gate), after the U1 work-in-progress commit 2ccd23a was folded into it.

## 0 The owner's choices (section 5 of the note, taken in discussion)

The note's section 5 listed five choices with defaults; the owner asked to be
consulted rather than defaulted, and answered before the batch started
(2026-11-26):

1. `npart` on a derived kick (R5): **refuse when a `reference` was given**; a
   flat-keyword beam without `npart` warns once per strong-strong task.
2. The snapshot's energy key (R4): **the key the user typed** (`E0`, `p0c`,
   `gamma0` or `brho`), so a `p0c` reference round-trips exactly.
3. A named strength at the flexible form (R11): **fold** as the friendly
   constructors do.
4. Batch order after A: **the `ParamMeta` type campaign (batch B) before the
   ramp (batch C)**.
5. `Moment(::AbstractString)`'s `tryparse` (R8d): **fix in U6**.
6. On a green full gate: **push** (fast-forward `main`, push, start the CI
   watcher, retire the worktree) without a further question; the owner then
   asked not to be asked again unless a new open item with physics content
   arose. One such item arose (U8, the RBEND template; section 2) and was
   decided by the MAD-X convention and recorded here rather than asked, since
   it is a convention of the authoring form, not a physics result.

## 1 What landed, by unit

Every change is additive; every existing call shape keeps working except the
two the note retires by decision (`Beam(...; r0 = ...)`, R3; a `BigFloat`
value on a typed element, R6), each refused by name with its remedy.

- **U1 (R9; `src/tasks/RunArtifact.jl`, `src/tasks/Tasks.jl`,
  `src/tasks/strongstrong/interface.jl`; `docs/design/run_artifact.md`,
  `docs/public_api.md`, D14's status line).** The machine snapshot is stored
  once per distinct text under `/machine_snapshots/<sha256>` (a string
  dataset with a `bytes` attribute, written by `_ra_write_machine_snapshot!`
  only when the digest is new) and the ledger row keeps `machine_sha256`
  only (`_RA_LEDGER_COLUMNS` = `start_turn, turns, current_turn, elapsed,
  rng_seed, rng_method, machine_sha256`; the stage-4 `machine_toml` column
  is written as `""` on a file that has it, so a continued stage-4 file
  stays aligned). The digest is taken over the text's bytes
  (`_ra_text_digest`; the stage-4 digest over the `String` cost 3.27 s for a
  1.24 MB text, the byte digest 4.9 ms). The task renders the text once and
  caches it on the knob and spec epochs (`machine_snapshot_cache::RefValue`
  on both tasks, `_ra_machine_snapshot(machine, path, cache)` returning the
  cached `(kepoch, sepoch, text, digest, tables)`). `RunArtifact(path; ...;
  machine_snapshot = true)` and `RunArtifact(; ...; machine_snapshot = true)`
  switch the snapshot off (`machine_recorded = :disabled`, the row holding
  `"disabled"`), with its `ConfigurationOptionMeta` entry (category
  `:output`, consumer `:run_artifact_output`), a non-`Bool` refused by name;
  the `:run_artifact_output` receipt carries `machine_snapshot` and
  `machine_recorded`. The readers (`_ra_machine_text`, behind
  `read(out, :machine)` and `read_machine(out)`) resolve the digest under
  `/machine_snapshots`, fall back to the stage-4 column checked against the
  digest, and refuse by name an empty, disabled or missing snapshot. The
  table of contents lists `machine_snapshots => Dict(digest => bytes)`.
  Measured with the R9 cost probe (`result/gates/cp1/r9_cost_before.log`,
  `r9_cost_after.log`; the note's section 4 fixtures) on its A500 fixture, a
  machine of 500 distinct elements whose text is 57 kB, 200 single-turn
  `execute!` calls each:

  | | file growth over 200 calls | per call (after the first) |
  |---|---|---|
  | before (stage 4: the text in every row) | 12.3 MB | 18.9 ms |
  | after (U1) | 0.91 MB | 5.03 ms |

  The 24-element fixture A moves from 4.21 MB and 1.71 ms over 1000 calls to
  4.19 MB and 1.59 ms (its rows, not its text, are the file); the digest of
  fixture C's 1.24 MB text takes 3.27 s over the `String` and 4.9 ms over
  its bytes, before and after alike (the measurement, not the fix, since the
  byte digest is what U1 installs).

  Testsets: "Machine description: the run artifact embeds the machine
  snapshot and reads it back" (rewritten: the new layout, a stage-4 layout
  read back, a missing snapshot refused, the switch, the cache), the ledger
  columns block, the receipts testset's new option and `propertynames` pin.
  Red on c52d80e: `result/gates/cp1/red/u1_red.log`.

- **U2 (R3, R4, R5; `src/lattice/Lattice.jl`, `src/lattice/toml.jl`,
  `src/beam/Beam.jl`, `src/tasks/strongstrong/interface.jl`; the examples,
  harnesses, validation scripts, profiling drivers and contracts converted;
  `docs/public_api.md`, D12's status line).** `ReferenceParticle{E}` is the
  richer immutable record: `charge`, `mc2`, the energy under exactly one of
  `E0`, `p0c`, `gamma0`, `brho` (a number or a knob expression; two or none
  refused by name), the other three and `beta0` derived once through
  `_knob_arith` so an expression input stays an expression, `r0 = RE * ME0 /
  mc2` derived (`_reference_r0`), the typed key stored as an `isbits` index
  (`energy_key` through `getproperty`, `reference_energy(ref)`), the species
  presets `ReferenceParticle(:proton | :electron | :positron; <energy>)`
  (`_REFERENCE_SPECIES`, another species pointed at the explicit form),
  structural `==` and `hash` (a reference from `E0` and one from the
  equivalent `p0c` are physically equal, structurally distinct), `show`, and
  `Lattice(...)` checks an expression energy's knob roots. The snapshot
  writes `charge`, `mc2` and the typed key (choice 2) and reads exactly one
  of the four. `Beam` carries `reference` and `npart_given`, derives `r0`
  from `mc2` (zero when `mc2` is), refuses `r0 =` by name, and resolves a
  knob energy at construction (`_numeric_reference`); the positional
  `Beam{...}(params, rep)` form records no reference. The strong-strong
  preflight (`_preflight_solver_kbb` with `_check_derived_kick`) refuses a
  zero `mc2`, `r0` or `charge` of either beam by name, refuses a
  reference-built beam without `npart` (choice 1) and warns once per task
  for a flat-keyword beam without it; the derived `kbb1`/`kbb2` are in the
  solver report (status `:inherited`, one of the six declared statuses) and
  the `:strong_strong_collision` receipt. 180 `r0 =` keywords left the
  examples, `test/examples/`, `validation/`, `profiling/`,
  `src/contracts/` and the suite (`/tmp` sweep script recorded in section
  3; `examples/knob_control.jl` now declares its B-rho from the
  reference). Testsets: "Machine description: the reference particle derives
  its quantities once, takes presets and four energy spellings, and refuses
  by name" (90 assertions) and "Machine description: the beam derives its
  classical radius and carries its reference; the strong-strong preflight
  refuses a zero or defaulted kick factor by name" (27); the reference
  batch's pins adapted (`RE * ME0 / PMASS_EV`). Red on c52d80e:
  `result/gates/cp1/red/u2_red.log`.

- **U3 (R6; `src/knowledge/Knowledge.jl`, `src/lattice/Lattice.jl`).**
  `_as_numeric_type(T, v, key)` refuses by name a value `T` cannot hold
  (`_numeric_type_holds`: a wider float, a dual or complex into a real
  type), naming the parameter and the remedies (`numeric_type = BigFloat`,
  or the untyped form); `Float64` to `Float32` keeps narrowing.
  `Lattice(...)` refuses early through `_lattice_check_typed_values` over a
  typed element's or line's stored values and overrides, with
  `_lattice_eltype_remedy` naming `eltype = P`. The suite's pin of the old
  convention (a `BigFloat` offset narrowing on a typed line) is rewritten to
  the ruling. Testset: "Machine description: a typed element refuses a value
  wider than Float64 by name and keeps narrowing Float64 to Float32" (23).
  Red on c52d80e: `result/gates/cp1/red/u3_red.log`.

- **U4 (R2; `src/elements/beam_line.jl`, `src/tasks/Tasks.jl`,
  `src/tasks/strongstrong/interface.jl`).** `_inert_in_single_beam(x)` is
  `true` for a `StrongStrongCollision` and `false` otherwise; the whole-line
  compile and the generic `_append_runtime_line!` skip an inert child,
  `_collision_marker_count(elements)` counts them at task construction, the
  `:tracking_line_binding` receipt and `configuration_report(task).binding`
  carry `collision_markers` beside `apertures`, the `_binding_report` of the
  strong-strong task names them too, and the marker's and `TrackingTask`'s
  docstrings say so. The linear-map walk sees the identity, so
  `one_turn_matrix` and `analyze(TwissDispersionAnalysis(...))` are equal
  with and without the marker. Testset: "Machine description: a collision
  marker in a single-beam line is inert, counted, never an error" (22: the
  tracked coordinates bitwise equal with 0, 1 and 2 markers on the tuple,
  lattice and whole-line spellings, the analyses equal, the receipt and the
  report at 0, 1 and 2, nothing warns). Red on c52d80e
  (`result/gates/cp1/red/u4u6_red.log`): `MethodError: objects of type
  StrongStrongCollision are not callable` at the first turn, and the
  whole-line form refused as an in-line hook.

- **U5 (R8b; `src/knowledge/Knowledge.jl`, `src/math/counter_rng.jl`,
  `src/elements/beam_line.jl`, `src/lattice/overrides.jl`,
  `src/elements/radiation.jl`, `src/elements/linear6d.jl`).**
  `ElementMeta.rng_consumer` (`:lumped_radiation`, `:particle_tunes`;
  `nothing` elsewhere) names the class a kind's `rng_id` belongs to;
  `validate_element_metadata` holds "declares `rng_id` iff declares a
  class". The flexible form `ElementSpec{kind}(params)` claims an explicit
  positive integer id under the class (`_claim_spec_stream!`), the spec
  route (`spec.rng_id = ...`), the in-place placement override
  (`entry.rng_id = ...`) and `with_overrides` claim through
  `_claim_override_stream!`. Found before the testset ran (section 2): the
  friendly constructor stores the stream it resolved for `rng_id = 0`, so
  every rebuild through the flexible form -- the knob resolve at compile,
  `_with_numeric_type`, a derived lattice's copy -- hands the kind's own
  auto-assigned id back, and a plain `claim_rng_id!` would have warned
  "already held by an auto-assigned consumer" about the spec's own stream;
  `_rng_id_held_by(id, class)` (explicit or auto-assigned, a forgotten auto
  class read as the class's own) answers it and the form claims only what
  its class does not hold yet. Testset: "Machine description: an explicit
  stream id reaches the registry on every route into the flexible form, and
  the kind's own id passes silently" (24). Red on c52d80e:
  `result/gates/cp1/red/u5_red.log` (`ElementMeta` has no `rng_consumer`).

- **U6 (R8c, R8d; `src/tasks/Tasks.jl`, `src/lattice/toml_hooks.jl`,
  `src/tasks/BeamObservers.jl`).** `TrackingTask.has_accelerating_cavity` is
  fixed at construction (`_has_accelerating_cavity(element_tuple)` once; a
  knob changes values, never kinds) and read by `_execute_tracking_window!`
  (audit item C-3's 416 bytes per call). `EveryNSteps` prints `stop` only
  when one was given (`toml_hooks.jl`). `Moment(::AbstractString)` refuses a
  non-integer power by name through `tryparse` (choice 5). Testset: "Machine
  description: the accelerating-cavity flag is fixed at construction,
  EveryNSteps prints stop only when given, and a bad moment name is refused
  by name" (15; the executor's text pinned, since an allocation equality
  between the spellings does not hold, section 2). Red on c52d80e:
  `result/gates/cp1/red/u4u6_red.log`.

- **U7 (R10; `src/lattice/toml.jl`; `docs/public_api.md`, D13's status
  line).** `read_lattice(path; receipt = false)` reads a one-lattice snapshot
  (several lattices refused by name, listing them and
  `read_machine(path)[:name]`); `read_machine(path1, path2, paths...; name,
  knob_root = nothing, receipt = false)` assembles a machine from several
  files, `name` required, the receipts' union with `files`, `Machine`'s own
  tripwires inherited (a lattice name twice, a root two files declare that
  the machine does not declare shared). Testset: "Machine description:
  read_lattice reads a one-lattice snapshot and read_machine assembles a
  machine from several files" (13: the note's probe 4, the split machine
  reassembles `==` with a byte-identical `machine_toml`). Red on c52d80e:
  `result/gates/cp1/red/u7_red.log`.

- **U8 (R11; `src/knowledge/Knowledge.jl`, `src/elements/templates.jl` (new,
  included last in `Elements.jl`), `docs/public_api.md`, the
  `?@element_spec` checklist, D9's status line).** The class form
  `Ctor(template::ElementSpec{kind}; name, kwargs...)` is installed by the
  registration itself (`_install_class_form!`, where `ELEMENT_META_BY_KIND[kind]
  = meta` is written; a loop over the registry in `templates.jl` missed the
  aperture, which registers from `src/elements/aperture.jl` after
  `Elements.jl`); its body `_derive_spec` starts from the template's stored
  parameters, replaces a named strength's slot in the stored tuple through
  `_FOLDED_NAMED_STRENGTHS` and `_FOLDED_TUPLE_KEYS` (the thin kinds' `knl`/
  `ksl` and the solenoid's `kn`/`kskew` included), deletes `h` and `b0` for a
  sector bend's new `angle`, requires `name`, refuses a wrong kind (naming the
  right form), a stored `numeric_type` differing from the given one, and
  rebuilds through the kind's keyword constructor so every check runs; the
  RBEND alias has its own method (section 2). The flexible form's fold hook
  `_fold_flexible_params!` (installed in `templates.jl` as
  `_FLEXIBLE_FOLD_HOOK`, run by the inner constructor) folds a named strength
  as the constructors do, both spellings refused, a typed spec's folded values
  narrowed, a sector bend's `angle` folded, every already-folded dictionary
  left untouched; `element_help` prints the class form. Testset: "Machine
  description: the class form derives a spec from a template of its kind on
  every friendly constructor, and the flexible form folds a named strength"
  (135: the registry-derived no-change derivation of 31 kinds' examples equal
  up to the name, the slot replacement per family, the bends, the refusals,
  the types, a chain and an expression, the `@elements` passthrough and the
  flat snapshot, the fold on the flexible form and a hand-written `k1 = 1.0`
  through the reader written back as `kn`). The blast-radius grep
  (`ElementSpec{:<kind>}(` with a named strength in `test/`, `examples/`,
  `validation/`, `profiling/`) found one site, the suite's
  `compile_runtime(ElementSpec{:thin_quadrupole}(; k1l = 0.1, knl = (0.0,
  0.2)))` refusal, which still throws an `ArgumentError` (at construction
  now). Red on c52d80e: `result/gates/cp1/red/u8_red.log`.

- **U9 (this record; `docs/README.md`; `docs/todo.md` rows 22 and 23; the
  follow-ups note's header and per-ruling `Status` lines and its section 5
  resolutions; `docs/design/machine_description.md` D9, D12, D13, D14
  status lines; `docs/experiences.md`, three lessons; the registry snapshot;
  the neighbour audit and its unit reports).**

## 2 Decisions and departures from the note's text

- **The RBEND template (U8; physics-adjacent, decided by convention, for the
  owner to overrule).** R11 says a template's `angle` resets `h` and `b0`
  and `chord` the arc `L`. There is no `:rbend` kind: `RBendSpec` builds an
  `ElementSpec{:sbend}` with `angle/2` folded into each face and `chord`
  folded into `L`, nothing of the RBEND spelling stored, so a stored sector
  bend cannot say whether its faces carry a half angle. The convention
  landed follows MAD-X, where the class of the template is the class of the
  derived element: `RBendSpec(template; ...)` reads its template as an
  RBEND (faces unfolded by the stored half angle `h L / 2`, the angle
  restored, then refolded by `RBendSpec(; ...)` at the new angle, `chord`
  replacing `L`; a template with `h != b0` was not built as an RBEND and is
  refused by name with the `SBendSpec` remedy), and `SBendSpec(template;
  ...)` keeps the faces as stored (a new `angle` resets `h` and `b0` only).
  Exact where a zero face angle was given, to roundoff otherwise (the
  no-change derivation of an RBEND template is pinned with `isapprox`).
  `RBendSpec(rb; angle = 0.2)` on `rb = RBendSpec(; L = 1, angle = 0.1)`
  gives faces of 0.1 each, as MAD-X's `RB2: RB, ANGLE = 0.2` does.
- **The class form is installed by the registration, not by a loop over
  the registry (U8).** Include order: `aperture.jl` registers after
  `Elements.jl`. `_install_class_form!` runs for every registration; the
  method body is resolved at the call. The suite's tripwire derives every
  registered kind.
- **The flexible form's claim recognises its own class's holdings (U5).**
  R8b's "claim at the flexible form as the friendly constructor's" would
  have warned on every rebuild of a `LumpedRadSpec` built with `rng_id = 0`
  (its stored auto-assigned stream re-passed through the form). The claim
  now asks `_rng_id_held_by` first; the registry's policy for first claims
  (`claim_rng_id!`) is unchanged. A forgotten auto class (an id issued more
  than `_RNG_ID_CLASS_WINDOW` = 65536 assignments ago) is read as the
  class's own: the alternative warned "held by an auto-assigned consumer
  whose class is no longer retained" about a spec's own stream late in a
  long session, loud and wrong, while the missed case (an old cross-class
  collision reaching the form) went unwarned before R8b too.
- **The accelerating-cavity flag is fixed at construction, not per
  compilation (U6).** The element tuple's kinds are fixed when the task is
  built; a knob or an override changes values. The per-compilation cache the
  note described would re-survey on every knob epoch for no information.
- **The cost pin of U6 is structural.** The note's "cost pin on both
  spellings" was first written as an allocation equality between the tuple
  and the lattice spelling, which does not hold (17520 against 17488 bytes
  per single-turn `execute!`: the whole-line runtime and the element tuple
  are different shapes). The pin is the executor's text (the field read, no
  per-call survey) plus the tracked coordinates equal across spellings; the
  measured per-call bytes stay in this record.
- **`npart` (U2, choice 1).** A beam built from a `reference` without
  `npart` is refused by name at the strong-strong preflight; the flat
  spelling warns once per task (`maxlog = 1` keyed on the task and beam),
  since its callers predate the reference.
- **The energy key (U2, choice 2).** `energy_key` is stored as a `UInt8`
  index into `_REFERENCE_ENERGY_KEYS`, so the record stays `isbits`.
- **The validator's equivalence tripwire (U5).** "A kind declaring `rng_id`
  declares a class, and only such a kind" is checked in
  `validate_element_metadata`, so the next stream-holding kind cannot miss
  the claim.
- **Commits.** The units share files (`Knowledge.jl` carries U3, U5 and U8;
  `Tasks.jl` U1, U4 and U6; the suite all of them) and were done in one
  worktree in order, so the batch lands as ONE commit carrying the code, the tests, the
  ledgers, this record and the audit (the stage-5 precedent's per-unit
  commits came from per-unit worktrees); the per-unit
  evidence is the red logs under `result/gates/cp1/red/` and the testsets
  named above.

## 3 Verification

- **Red first.** Every unit's testset was run extracted against `main`
  (c52d80e) and failed on the missing behaviour, then green on the batch
  tree: `result/gates/cp1/red/u1_red.log`, `u2_red.log`, `u3_red.log`,
  `u4u6_red.log`, `u5_red.log`, `u7_red.log`, `u8_red.log` (each ends in
  `exit=1`; the first failures name the missing symbol or the old
  behaviour, never a test defect: `_REFERENCE_SPECIES` undefined, the R6
  wording absent, the marker's `MethodError`, `ElementMeta` without
  `rng_consumer`, `ReferenceParticle(::Symbol)` undefined, `hasmethod` false
  on the class form).
- **Validators on the batch tree** (`/tmp/claude-dxu/cp1/validators3.log`):
  `validate_configuration_metadata() = true`;
  `validate_element_metadata()` passed (614 default pairs checked, 34
  runtime-variant pairs); `element_help` renders both forms for all 32
  kinds; the registry snapshot regenerated (the new exports
  `reference_energy`, `read_lattice`, the `machine_snapshot` option);
  `validate(PublicConfigurationEffectivenessContract())` passed ("Public
  configuration reached CPU, fused CUDA, and CUDA PIC consumers").
- **The examples' fingerprints** (the stage records' recipe at the
  LinearOptics sizes, `/tmp/claude-dxu/cp1/compare/`; baseline the stage-5
  logs under `result/gates/md5/compare/`): CPU threads, all 20 rows
  IDENTICAL to the stage-5 baseline (the `r0` derivation, the reference
  rewrite, the inert marker and the fold hook preserve the bits; the one
  warning in the log is the shipped example's pre-existing `rng_id = 2`
  sharing, ledgered). CUDA, two runs on the batch tree: the 14 deterministic rows (weak-strong,
  crab noise, the DBA analysis) bitwise equal to the stage-5 CUDA logs and to
  each other; the 6 strong-strong PIC rows differ as they differ between two
  runs of one tree (the device atomics; the stage-5 logs' own two runs
  differ on the same 6 rows). The artifact tolerance comparison
  (`diff_artifacts_ref.jl`, max relative difference over every real column):

  | pair | luminosity/ip | moments/electron | moments/proton |
  |---|---|---|---|
  | batch run 1 vs batch run 2 (the same-tree floor) | 1.19e-11 | 2.26e-9 | 9.38e-10 |
  | batch run 1 vs stage-5 run 1 | 1.34e-11 | 2.78e-9 | 1.68e-9 |
  | batch run 2 vs stage-5 run 2 | 1.53e-11 | 3.69e-9 | 6.03e-10 |
  | batch CPU vs stage-5 CPU | 0 | 0 | 0 |

  The cross-tree differences are of the floor's size (the worst column is
  the same, `m001010` of the electron moments), and the weak-strong and
  crab-noise artifacts are bitwise equal on both pairs.
- **The parity driver** (`profiling/machine_description_parity.jl`, re-run
  for U4 and U6): both CPU cases pass with equal digests and a zero control floor
  (`result/gates/cp1/parity_ss_cpu.log`, `parity_ws_cpu.log`; 20,000
  macro-particles, 10 turns, 5 repeats, 16 threads): `ss` tuples 1.031 s per
  turn against the machine route's 1.040 (58.63 MB per turn on both); `ws`
  tuple 8.26 ms per turn, lattice 8.28, machine 8.28, the described routes
  at 46426 bytes per turn against the tuple's 46422 (the 416 bytes per call
  of audit item C-3 gone). The CUDA `ss` case (`parity_ss_cuda.log`) is the
  REPORT verdict the stage-3 record describes: the digests differ by
  1.66e-15 with the control floor at 1.46e-15 (the PIC deposit's atomics),
  tuples 105.6 ms per turn, machine 103.3.
- **The extracted neighbours** (`test/run_extracted_testsets.jl`, 49
  titles: the batch's testsets, the reference-particle, receipts,
  precision-rule, thin-element, snapshot, `@elements`, knob, rng-policy and
  artifact blocks, the export, docstring and `Core.Box` sweeps):
  all blocks green except the four that cannot run outside the suite by the
  runner's stated limit (a file-level helper `_st4b_a_dense6` in the
  receipts block, `with_logger` in the nested-lines block, `Symbolics` in
  the knob-control block), left to the gate; the first run
  (`/tmp/claude-dxu/cp1/extracted_final.log`) also found three stale pins
  and one new defect, fixed and re-run green
  (`extracted_final2.log`, exit 0): the reference batch's `grid.params`
  pin with `r0 = 0.0` (now `RE * ME0 / PMASS_EV`), the stage-2 "not both"
  wording pin (now "exactly one of"), the rng-policy call-site tripwire
  (now accepting the metadata's class at the flexible form's one site),
  and the RBEND alias's method docstring attached to `Core.Type` (now a
  comment; audit finding A-4).
- **The fast lane** on the final tree (`result/gates/cp1/fast_lane.log`,
  `run_fast_lane.sh`): five attempts. The first stopped at "Architecture
  integrity" (the audit's three unit reports not indexed in
  `docs/README.md`; linked, and the directory's wholesale marker added); the
  second at the validators' injection block (the suite's positional
  `ElementMeta(...)` rebuild helper lacked the new `rng_consumer` field;
  given it); the third at "Strong-strong lines bind the survey, the
  apertures and the reference chain as a TrackingTask line does" (four
  pins of the strong-strong binding tuple without `collision_markers`, the
  field the shared binding helper now carries for both task kinds -- the
  blast radius the extracted list had not named; the pins extended to the
  one marker each line holds, every other pin of the shape grepped: none);
  the fourth at "The run artifact records the realised turn modulation"
  (the option schema's key set pinned without `machine_snapshot`;
  extended, and a sweep of every pin of the shapes the batch widened --
  schema keys, field names, exports -- found no other). The fifth: green, 15:14:35 to 15:55:36 EST (41 min), 495 testset rows, 160,032 passing assertions, 0 failed, 0 errored, exit 0;
  the gate-only sections were also run extracted beforehand where the
  runner allows (contract coverage guards 145/145, element parameter
  effectiveness 80/80, solver option effectiveness 9/9, lattice cells
  41/41; the examples and physics-contract blocks need file-level state
  and are the gate's), and every example and harness ran by hand as the
  gate's examples section runs them, all exit 0 (`/tmp/claude-dxu/cp1/examples_run.log`).
- **The full gate** at CI settings, CUDA active, on the final tree, the
  depot idle: green, exit 0, 16:01:22 to 17:43:38 EST (1 h 42 min), 513 testset rows,
  163,503 passing assertions, 0 failed, 0 errored, 3 broken
  (`result/gates/cp1/full_gate_native.log`, `run_full_gate.sh`; the gated
  working tree's id `d302c4530815210ad253ab65dd4eb4ba5310ce65` in
  `gated_tree.txt`, the committed tree differing from it in this record's
  text only, which the final fast lane below covers).
- **The neighbour audit:** the report
  [`audit_machine_description_compile_path1_2026_11_26.md`](audit_machine_description_compile_path1_2026_11_26.md);
  three reading units over the batch's diff, 16 leads, 4 confirmed
  findings all fixed before the gate (A-1 the class form missing the
  aperture, A-2 the RBEND clause on a non-existent kind, A-3 the flexible
  form's claim of a spec's own auto-assigned stream, A-4 the docstring on
  `Core.Type`), 2 corrections to the batch's own analysis (the U6 cost pin,
  the U7 shared-root expectation), 10 clean by reproduction, nothing
  ledgered.

## 4 What stays open after this batch

- Batch B, the `ParamMeta` type campaign (C-6's metadata half), then batch
  C, the ramp (R7; the D12 chain gap, no task comparing a beam's reference
  with a cavity's stored pair, is its first lead).
- The owner may overrule the RBEND template convention of section 2.
- The shipped strong-strong example's explicit `rng_id = 2` warning (its
  own small batch: the ids move the fingerprints).
- From `docs/todo.md` row 23, unchanged: the knob `e0` below `mc2` dying in
  the derived tree's `sqrt`; the `thin_strong_beam` flexible form's
  spelled-out parameters.

## 5 The previous push's ledger

The follow-ups note c52d80e was pushed 2026-11-26 with the stage-5 record;
its CI run (494, id 45761258815) ran 2026-11-26 05:23:18 to 06:42:00 UTC
(78 min 42 s), the "Julia 1.12 CPU full-lane tests" job green (recorded in
`docs/todo.md` row 22 before this batch).
