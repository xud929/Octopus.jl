# The machine description, stage 5: the derived lattice `with_overrides` and the campaign's neighbour audit (2026-11-25)

Stage 5 of [`../design/machine_description.md`](../design/machine_description.md),
section 3: decision D11 as `with_overrides`, the third variation route
beside knobs and in-place placement overrides, then the neighbour audit the
invariants require after every campaign, after the stage-4 record
[`machine_description_stage4_2026_11_25.md`](machine_description_stage4_2026_11_25.md).
The audit's report is
[`audit_machine_description_2026_11_25.md`](audit_machine_description_2026_11_25.md)
(its unit reports beside it); this record carries what the stage landed,
the decisions, the verification and the ledger. Guides:
`../guides/development_workflow.md`, `../guides/documentation.md`, the
protocol `../comprehensive_audit.md` for the audit. Branch `md5`, based on
aea4173 (the pre-gate sibling of the pushed stage-4 record commit 1c7ca22,
both children of b50f798 with byte-identical trees, so the stage-5 base is
the stage-4 tree and the replay onto `main` meets no conflict), worked in
three unit worktrees off the skeleton commit 5efe850 (the `with_overrides`
docstring as the specification unit A implements, its four stubs, the
`src/lattice/` source-map bullet of `AGENTS.md` naming the derived lattice
and the snapshot, the include of `lattice/overrides.jl` in `src/Octopus.jl`,
the `[MD5-A]`, `[MD5-B]` and `[MD5-C]` test anchors; `AGENTS.md` +4/-1,
`src/Octopus.jl` +4/-1, `src/lattice/overrides.jl` +95, `test/runtests.jl`
+12) and replayed onto `main` as a linear tail: the skeleton d0b1cb1, unit A 3504192 (the derived lattice; 3fcb4c8 on its
branch), unit B 0600139 (the audit's reading unit U1 and its fixes;
37441bf on its branch), unit C 3bb1800 (the audit's reading unit U2 and its
fixes; 71567d6 on its branch), then the record commit the record commit that follows them with the
regenerated snapshot and the docs. The commit messages carry the fast lane
and the gate.

## 1 What landed

- Unit A (3504192; `src/lattice/overrides.jl` +158/-13 over the skeleton,
  227 lines in all; `test/runtests.jl` +204): `with_overrides(lattice,
  (selector => (param = value, ...))...; name = lattice.name)` copies the
  source line's placements (`_copy_line_entry` through the keyword form
  `BeamLine(; name, entries, own...)`, the provenance paths kept, the spec
  objects shared), resolves every selector on the SOURCE line through
  `find_entries` (a `Selector`, a `String` parsed as one, a `Regex` against
  the rendered path, a tag `Symbol`, a stored spec type or a friendly
  constructor type, a predicate `LineEntry -> Bool`), writes the table's
  pairs (a `NamedTuple`, a `Dict{Symbol}`, or pairs) into the copies'
  `overrides` (later pairs win, an override the source placement carries is
  replaced) and returns a NEW `Lattice` with the source's reference, knob
  roots and numeric type, both construction tripwires run again. The
  machine form `with_overrides(machine, name, pairs...; name = machine.name)`
  replaces the named lattice by its variant (the lattice keeps its name,
  the machine's key) and returns a new `Machine` with the other lattices as
  they are and the shared roots kept, its own tripwire run again. No
  `_SPEC_EPOCH` bump: nothing shared is mutated. Every refusal starts
  `with_overrides("<name>"):` and names the remedy: a selector matching
  nothing (the selector's repr and the line's paths), no pair at all, an
  empty table, a non-`Symbol` key, a wrong right-hand type, a structural
  key (`LineEntry.spec`, `.path`, ...), the two in-place guards verbatim
  with the placement's path (a folded named strength, a line placement's
  `entries`/`name`/`L`), a key on a hook placement (not an element spec),
  a key the placement's kind does not declare (`_toml_declared_keys`, the
  codec's one table of a kind's keys: `L` on a marker, a misspelling), and
  the machine form's unknown name listing the keys. Placements inside a
  nested line kept whole are not addressed (derive that line's lattice
  first and rebuild). Testsets below `[MD5-A]`: "Machine description:
  with_overrides derives a lattice without touching the source" (28: the
  source line, its entries, their override tables and the spec epoch
  unchanged; the variant's placements copies with the overrides; the
  selectors by path, tag, type and predicate; later pairs winning; the
  machine form keeping the others and the roots), "... with_overrides
  refuses by name" (22, every refusal above red by its text) and "... the
  derived lattice's snapshot shows the overrides as placement data" (10:
  `machine_toml` of the variant printing `{ ref = ..., path = ...,
  overrides = { ... } }` on the addressed members only and the reload equal).
- Unit B (0600139; `src/elements/beam_line.jl` +57, `src/lattice/toml.jl`
  +16, `src/tasks/strongstrong/interface.jl` +36, `test/runtests.jl` +164,
  four files +268/-5 in all; the audit's
  reading unit U1, report
  [`audit_machine_description_2026_11_25_unit_reports/U1_report.md`](audit_machine_description_2026_11_25_unit_reports/U1_report.md)):
  three confirmed findings fixed with regression tests shown red first,
  one derived tripwire. B-2 (Moderate): a placement override written on an
  in-line hook or a collision-marker placement was stored, bumped the spec
  epoch, was read by no compile and round-tripped through the snapshot; now
  `_reject_hook_placement_override` runs first in `setproperty!(::LineEntry,
  ...)`, the TOML writer refuses a hand-built hook or marker member carrying
  overrides and the reader refuses `overrides` on a non-element member, the
  three routes agreeing with the derived route. B-10 (Moderate): an
  undeclared override key (`line[1].bogus = 1`) was stored by the placement
  route while the spec route refused it by name, and the writer printed a
  snapshot the reader refused; now `_reject_undeclared_override`, the
  placement twin of the spec route's schema check, runs last in the guard
  order and the writer refuses an undeclared override key by name (one
  suite probe that wrote `k1` on a reversed drift placement as a
  write-isolation check writes `x_offset` now). B-5 (Minor): the three
  public `StrongStrongTask` forms refuse an unknown keyword by their own
  name through `_strong_strong_refuse_unknown_keywords`, whose roster
  `_STRONG_STRONG_KEYWORDS` is read from the builder's method
  (`Base.kwarg_decl`), never hand-copied. B-6e: a derived suite test pins
  that every concrete tracking method and every module enum is a registered
  snapshot object type (injection-verified). Testsets below `[MD5-B]`:
  "Machine description audit: a placement override on a hook or marker
  placement is refused by name on every route", "... StrongStrongTask
  refuses an unknown keyword by its own name on the line and machine
  forms", "... every tracking method and enum of the module is a
  registered snapshot object type", "... an undeclared placement override
  key is refused by name where the spec route refuses it and is never
  written" (11, 12, 3 and 8: every refusal red by its text on the in-place
  route, the derived route's twin left to unit A, the writer and the
  reader; the four public forms' messages; the injection arm).
- Unit C (3bb1800; `src/lattice/Lattice.jl` +17/-1, `src/tasks/BeamObservers.jl`
  +10, `test/runtests.jl` +68; the audit's reading unit U2, report
  [`audit_machine_description_2026_11_25_unit_reports/U2_report.md`](audit_machine_description_2026_11_25_unit_reports/U2_report.md)):
  two confirmed findings carried by the stage-4 record, fixed with
  regression tests shown red first. C-1 (Major): `AtTurns` holds a
  `Set{Int}` and defined no `==`, so two solvers built independently and
  scheduling luminosity on equal turn sets compared unequal in
  `solver_configuration` and `_collision_solver` refused the pair; now
  `==`, `isequal` and `hash` by the set (the `LongitudinalSlicing`
  precedent). C-2 (Moderate): `_lattice_structurally_equal` walked every
  field of an in-line observer, and the artifact-view observers keep run
  state in the object, so a lattice that had run was no longer `==` its
  pristine twin; now an observer whose type has an `observer_option_schema`
  compares by the schema's values (the configuration view the snapshot
  writes, D6), an observer without one by its fields as before; `hash(::Lattice)`
  never read hook state. Testsets below `[MD5-C]`: "Machine description
  audit: AtTurns compares by its set, so independently built solvers
  scheduling the same turns pair" (9) and "... a lattice whose observers
  have run is still equal to its pristine twin" (6). Measured and ledgered,
  not changed: C-3, 416 bytes per `execute!` call of a placement-spelled
  line at `_has_accelerating_cavity(task.elements)` (the stage-3 lead's
  site, found); C-4 the artifact's machine readers clean; C-5 the zero kick
  scale and the D12 inventory of flat reference spellers (an owner item);
  C-6 the `moments` route's message gaps.
- Docs (this unit D, the orchestrator's fold): `public_api.md` ("Describe
  A Lattice" gains the "Derive A Lattice" paragraph with its example lines
  and `?with_overrides` in the help list), the design note's banner, the
  dated status sentence of D11 and the staging item 5, `README.md` (both
  records and the unit-report directory indexed, the design entry
  extended), `todo.md` (the machine-description row's status and delivery,
  the carried row dispositioned by the audit), the audit report, the two
  archived unit reports, this record; the snapshot regenerated at the fold
  (`with_overrides` entering the export list, two lines reflowing).

## 2 Decisions

- The derived route's guards are the in-place route's guards, prefixed with
  the placement they refuse: `_reject_folded_override` and
  `_reject_line_placement_override` verbatim, then two refusals the
  in-place route did not make when the skeleton was written (a key on a
  hook placement; a key the kind does not declare, read from the codec's
  one table of a kind's keys, `_toml_declared_keys`). The audit then made
  the in-place route, the TOML writer and the TOML reader refuse the same
  two classes (B-2, B-10), so the four routes agree and no override exists
  that a compile does not read or a snapshot cannot carry. The class
  without parameters is "an in-line hook or a collision marker"; the
  element kind `:marker` is an `ElementSpec{:marker}` with declared keys
  and keeps taking overrides (B-9 corrected the stage-3 wording).
- A call with no pair, an empty table and a selector matching nothing are
  refused (loud beats silent: a variant that changed nothing is a study
  that measured nothing), naming the selector and the line's paths.
- No spec-epoch bump on the derived route: nothing shared is mutated (the
  copies hold the overrides, the spec objects are the same), a task built
  from the variant compiles it fresh and a task built from the source has
  nothing to recompile; the in-place route keeps its bump.
- The machine form replaces the named lattice and keeps the others and the
  shared roots, returning a new `Machine` through the constructor so the
  machine-level tripwire runs again; an unknown name is refused listing the
  keys, as `machine[name]` does.
- The in-place route's guards as the audit decided them: a hook or
  collision-marker placement key refused first (nothing stored, the epoch
  untouched), an undeclared key refused last so the older guards keep their
  messages, mirroring the spec route's condition exactly (declared
  parameter, placement key, or a key the spec already stores; a kind
  without metadata keeps the acceptance). Blast radius measured first
  (every override writer in the suite, the examples and the harnesses
  listed in U1_report.md): one probe retargeted, no documented promise
  broken.
- Observers compare by their configuration view: in `Lattice`'s structural
  equality an observer whose type has an `observer_option_schema` compares
  by the schema's values, the view the snapshot writes (D6) and the
  validators sweep, so a run leaves equality alone; an observer without a
  schema keeps the field walk; `hash` was never over hook state. Two
  pristine lattices each with its own `BPMObserver("x")` stay unequal
  because their auto-assigned `rng_id`s differ, a configuration difference
  the snapshot writes (the test gives the BPM an explicit id).
- `AtTurns` by value: `==`, `isequal` and `hash` over its set, so the
  schedule family is value-equal throughout except `PredicateSchedule`,
  whose function compares by `===`, which is right.
- An unknown keyword on a public `StrongStrongTask` form is refused by the
  constructor's own name from a roster read off the inner builder's method
  (never hand-copied; the retired keywords stay in it and keep their own
  precise refusals).
- Left unchanged on purpose, recorded with the competing readings: a
  wider-than-`T` scalar override on a typed element converts at compile,
  the convention the suite pins (B-11, an owner question); the stage-4
  owner calls (a machine the codec cannot snapshot warns at prepare; the
  derived two-lattice machine is `nothing` without a warning where no
  machine can hold the pair) stand as recorded.

## 3 Verification

- Extracted per unit, in package mode at four threads
  (`test/run_extracted_testsets.jl`), before each unit's commit (the unit
  reports and commit messages, logs under the scratch directory of the
  day): unit A's three testsets 28, 22 and 10 of as many (its first
  script-mode run had the refusal testset at 18 of 22 on the tests' own
  `startswith` checks not allowing for the `ArgumentError: ` prefix of
  `sprint(showerror)`; the tests were adjusted, not the code), the
  neighbours "Machine description: a Lattice wraps a line and is accepted
  where the line is" 42, "... lattice equality is structural and the
  record prints" 24, "... the snapshot round-trips a lattice and its knobs
  and the emitter is deterministic" 47, "Every exported API name appears in
  the registry snapshot" 17, the three sweeps "Every export is documented"
  1, "No docstring is detached by comment lines" 11, "No method grows a
  Core.Box outside the argued allowlist" 5, and "Architecture integrity"
  49 of 50 by the new export alone (the regenerated snapshot differs from
  the committed one in the two `with_overrides` lines of 481, measured by
  unit B); unit B's four testsets red on the unfixed tree for the defects'
  reasons (`red_run.log`: B-2's block with the refusal absent, B-5's 8
  failed and 1 errored; `red_run2.log`: B-10's 4 failed of 8) and 11, 12,
  3 and 8 of as many after (`green_run2.log`) with 27 neighbour blocks
  green (the codec blocks 47, 226, 91, 87, 18, 38 and 20, the task blocks
  11, 19 and 15, the guard blocks 43, 18, 12, 36, 13, 57 and 9, the
  lattice blocks 13, 29, 24 and 35, the macro blocks 42 and 26, and
  "Nested lines have length, reflection keeps state, folded sugar is
  rejected everywhere" 48 of 48 with the suite's `using Logging` as the
  runner's prelude, `green_nested.log`) and the three sweeps; unit C's two testsets red on the unfixed tree (`red_L1_L2.log`)
  and 9 of 9, 6 of 6 after, with 17 neighbour blocks green
  (`green_all.log`, `green_prelude.log`) and `validate_configuration_metadata()`
  `true` before and after. Blocks that cannot run extracted, left to the
  gate: "Particle tunes: fixed-label symplecticity ..." (unit B),
  "Non-finite coordinates fail fast at solver chokepoints" and "The run
  artifact's row cursor ..." (unit C).
- On the folded tree (2026-11-25 21:45 to 21:54 EST,
  `result/gates/md5/extracted_checks.log`): `validate_configuration_metadata()`
  `true`; `validate_element_metadata()` passed, 614 of 614 default pairs and
  34 of 34 runtime variants; `element_help` both forms for all 32 kinds; the
  regenerated snapshot equal to the committed one. Extracted, every block
  green: "No method grows a Core.Box outside the argued allowlist" 5, "No
  docstring is detached by comment lines" 11, "Every export is documented" 1,
  "Every exported API name appears in the registry snapshot" 17,
  "Architecture integrity" 50, "the Example core object answers with real
  scripts" 60, "Stage 5: every kind that declares the analysis ..." 64, the
  stage's nine testsets 28, 22, 10 (unit A), 11, 12, 3, 8 (unit B), 9, 6
  (unit C), the stage-2 neighbours 42, 13, 24, 13, the stage-3 neighbours 35,
  12, 11, 19, 15, the stage-4 neighbours 47, 226, 162, 91, 87, 18, 38, 20,
  "No committed script constructs a retired observer or task spelling" 41,
  "Run artifact exclusion and seed provenance ..." 60, "Knob registry
  atomicity and round-trip totality" 50, "Turn modulation: the RF cavity by
  the same wrap" 147; the neighbour "StrongStrongTask chunking preserves
  stochastic physics" 12 of 12 in a second process with its helper as the
  runner's prelude (`extracted_chunking.log`).
- The examples' fingerprints (SHA-256, the LinearOptics record's quantities
  and hashing rule; `ws`, `ss`, `cn`, `dba` as in the stage-3 record),
  baseline the stage-4 tree (the stage-4 record's runs, code 1c7ca22)
  against the stage-5 tree (the tail's code at 0600139, the merged `md5` tree
  e645e9b being the same; 2026-11-25 21:42 to 21:50 EST, logs under
  `result/gates/md5/compare/`): no script changed in this stage,
  so every row is expected identical on CPU threads and, for the six `ss`
  rows on CUDA, within the device noise floor the stage-3 and stage-4
  records measured. The result: `[all twenty CPU hashes identical (ws 4,
  ss 6, cn 3, dba 7); on CUDA the fourteen deterministic rows identical and
  the six ss rows within the floor: the maximum relative differences per
  table, luminosity / electron moments / proton moments, same-tree floor
  and cross-tree values]`.
- The fast lane and the full gate at CI settings with CUDA active ran on
  this tree after this record was written and before the final commits were
  made from it, so their numbers are in the commit messages (the unit
  commits name the gate that covered them; the record commit carries the
  lane's counts), not here: the record cannot carry the lane that covers its
  own last line. Logs: `result/gates/md5/fast_lane.log`,
  `result/gates/md5/full_gate_native.log`.

## 4 Carried and open

- Ledgered by the audit with a price (`todo.md`, the carried row; the
  report's section 6): B-1b [Minor], a `StrongStrongCollision` in a
  `TrackingTask` line dies at the first turn with a raw `MethodError`
  (a by-name refusal in `_runtime_or_existing` naming `StrongStrongTask`,
  about five lines plus a test); B-6a [Minor], a reloaded
  `:lumped_radiation` or `:linear6d` spec's explicit stream id is not
  re-claimed in the reading process and reads back as `Int` (a per-kind
  consumer class for `claim_rng_id!`, one call in `_toml_decode_element`,
  two tests; a metadata decision); C-3 [Minor], 416 bytes per `execute!`
  call of a placement-spelled line at `_has_accelerating_cavity(task.elements)`
  in `_execute_tracking_window!` (cache the flag per compilation beside the
  runtime cache tuple; the tuple route's 576 B for the same walk go with
  it); C-6 [Minor], `Moment(::AbstractString)`'s non-digit message (a
  `tryparse` naming the text, two lines) and `EveryNSteps`'s `stop =
  typemax(Int)` with `Linear6DSpec`'s marker forms (a type or typed default
  on the schema entry or `ParamMeta`).
- Owner items: C-5 [Moderate, carried since the reference batch], the
  derived strong-strong kick scale is zero for a zero `r0`, `charge` or
  `mc2` and only `E0` is refused (a preflight naming the zero factors after
  a count of the fixtures deriving a zero on purpose, or `r0` derived in the
  D12 compile-path campaign, whose inventory of flat spellers U2 lists);
  B-11 [Unconfirmed], convert (as pinned) or refuse a wider-than-`T` scalar
  override on a typed element (about six lines if refused); the stage-4
  calls unchanged (the snapshot refusal warning at prepare, the derived
  machine's silent `nothing`, beam definitions on the machine, the shipped
  example's `rng_id = 2` warning, the reloaded knob root as a namespace, a
  solver or rule of another numeric type refused at write); B-2's merge
  note (`_overrides_check_key` calling `_reject_hook_placement_override`
  rather than carrying its own test), a follow-up (priced at a few lines with unit A's message pins to move).
- Closed by the audit and struck from the carried row: the `AtTurns`
  identity `==` (C-1), the lattice equality after a run (C-2), the override
  on a hook or marker placement (B-2), the unknown keyword naming the inner
  builder (B-5), the undeclared override key (B-10), the "410 bytes" site
  (traced, C-3), the other `LineEntry`-wrapping walkers (B-1, enumerated
  clean), the nested-root narrowing (B-7, no caller), the fixtures' stream
  ids (B-8), the artifact readers (C-4). The compile-path half of D12 stays
  the next campaign (its lead list: the reference chain comparing the beam
  with the cavities, the flat spellers' inventory, C-5).
- The staging of the design note is complete; translators (D17) and the
  deliberately-not-now items (D18) remain as the note states them.

## 5 Ledger and the previous push

`README.md`: this record and the audit report indexed, the unit-report
directory indexed wholesale, the design entry naming the stage and the
audit. `todo.md`: the machine-description row (stage 5 implemented, the
staging complete, what it delivered, the audit's open queue pointer, the
previous push's CI) and the carried row (the audit's dispositions: fixed
items struck, ledgered ones kept with their price, the owner items).
`public_api.md`: "Describe A Lattice" (the "Derive A Lattice" paragraph,
its example lines, `?with_overrides`). The design note:
`machine_description.md` (the banner, the dated status of D11, the staging
item 5). `experiences.md`: the lesson "A new route to an old state inherits the old
route's missing guards". The previous push: stage 4 as 1c7ca22 on `origin/main` (pushed
2026-11-25 21:08 EST, its tail the linear replay of the stage-4 record),
CI run 492 (id 45740458059) ran 2026-11-26 02:08:51 to 03:23:27 UTC (74 min
36 s): success, the "Julia 1.12 CPU full-lane tests" job green
(`result/gates/md4/ci_watch.log`)
(`result/gates/md4/ci_watch.log`); no intermediate docs-draft commit sits
in that history (aea4173, the pre-gate draft of the same tree, stayed
local as the base of `md5` and is replaced by 1c7ca22 at the fold).
