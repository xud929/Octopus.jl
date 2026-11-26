# The machine description, stage 4: the TOML snapshot, its codec and the run artifact embedding it (2026-11-25)

Stage 4 of [`../design/machine_description.md`](../design/machine_description.md),
section 3: decision D13 as the TOML data form of a machine (the writer, the
reader and the registry-derived round-trip tripwires) and D14 as the run
artifact embedding the snapshot, after the stage-3 record
[`machine_description_stage3_2026_11_25.md`](machine_description_stage3_2026_11_25.md).
Guides: `../guides/development_workflow.md`,
`../guides/examples_and_validation.md`, `../guides/documentation.md`. Branch
`md4`, worked in three unit worktrees off the skeleton commit 58dfa00 (the
`write_machine` docstring as the format every unit implements, the public
signatures and the codec's stubs, the `[MD4-A]`, `[MD4-B]` and `[MD4-C]`
test anchors) and replayed onto `main` as a linear tail: the skeleton
1cefffa, unit A 052b161 (the core codec; 018ea38 on its branch), unit B
d7b439d (the objects beside the elements; its branch's two commits, the
last 0edb478, squashed), unit C bd6c16d (the artifact embedding, the
example's snapshot; its branch's three commits, the last 19b3912, squashed
to their code, the docs drafts going into the record commit filled), the
format docstring aligned with what the codec settled (b50f798), then the
record commit with the regenerated snapshot and the docs. The commit
messages carry the fast lane and the gate.

## 1 What landed

- The skeleton (1cefffa, 58dfa00 on the unit branches; `src/lattice/toml.jl` +342, `src/lattice/toml_hooks.jl`
  +18, `src/Octopus.jl` +10/-4, `Project.toml` +6 and `Manifest.toml` +4/-2
  (the `TOML` and `SHA` standard libraries as dependencies),
  `test/runtests.jl` +14, `AGENTS.md` +3/-1): the `write_machine` docstring
  written first as the format, the
  contract every unit implements (the tables in order, the element, value,
  hook, line and knob rules, the deterministic emitter, the refusals), the
  four public functions as documented stubs, the codec's extension points
  (`_TomlContext`, `_toml_at`, `_toml_refuse`, the bulk-table seam, the
  value rules, `_TOML_OBJECT_TYPES`, the object encoder and decoder), the
  include of `lattice/toml.jl` after `Machine.jl` and of
  `lattice/toml_hooks.jl` after the tasks whose types it names.
- Unit A (052b161; `src/lattice/toml.jl` and `test/runtests.jl` together
  +1612/-25, the test file +324 of them): the core codec: `machine_toml(machine, tables)`,
  `write_machine(path, machine)` with the `.tables.h5` sidecar,
  `parse_machine(text; tables, receipt)`, `read_machine(path; receipt)`; the
  element tables by stored parameters under `kind` with the ids made unique
  in first-placement order and one table per distinct spec object; the value
  rules in both directions (numbers by type, the knob expression as `{ expr
  }`, the symbol rule from the `ParamMeta` evidence, tuples by the default's
  class, `{ nothing = true }`, types through the numeric allowlist, tracking
  methods, enums, nested specs, unsigned integers); the lines as members with
  `ref`, `path`, `tags`, `overrides` rebuilt through the keyword
  `BeamLine(; name, entries)`; the knobs by dotted path, independent by
  value, dependent by expression, declared types explicit, unset marked,
  declared on reading in dependency order with the same-definition
  acceptance and the conflicting-definition refusal; the reference and
  lattice tables; the deterministic emitter, Octopus's own (`_toml_emit`:
  the standard library's printer renders an array of tables as `[[...]]`
  array-of-tables sections, not as the one-line inline members the format
  fixes); every refusal through `_toml_refuse`, `machine snapshot: at
  <where>: <message>`. Beyond the format's first text, the codec settled and
  the docstring now states: `{ vector = [...] }` and `{ matrix = [[...]] }`
  beside `{ tuple = [...] }` where the metadata gives no class hint,
  `{ type_name = "..." }` for a `Type` outside a typed key, the kind's
  example value as class evidence beside the `ParamMeta` default and
  alternatives (so `L = "0.6"` on a drift is refused as a bare string even
  though the default is `nothing`), a `BigFloat` value refused at write as
  lossy, a knob whose last segment is a marker word refused, a line's `name`
  written only when it differs from its id, and the hook and marker ids as
  the line's own labels (`SCHEDULEDOBSERVER`, `STRONGSTRONGCOLLISION`, made
  unique with `#2`). The tracking-method singletons and the `XYCouplingMode`
  enum are registered in `_TOML_OBJECT_TYPES` at include time from the
  registry. Testsets below `[MD4-A]`: "Machine description: the snapshot
  round-trips a lattice and its knobs and the emitter is deterministic" (47:
  the hand-built DBA ring with an independent and a dependent knob, an
  override, a tag and a kept-whole nested line, `==` and structural equality
  after the file, the shared cell object one object again, the paths
  verbatim, the text byte-identical from the original and the reload, the
  fresh-declaration path through a renamed root with its receipt and the
  second parse reporting `existing`), "... every registered element kind
  round-trips through the snapshot or is refused by name" (226 on the folded
  tree, 214 at unit A's commit: every kind's `meta.example` placed alone in
  a lattice of its numeric type, written and parsed back equal, a second
  write byte-identical; the two strong-beam kinds deferred at unit A's commit
  on their `HirataParaxialDrift` value round-trip once unit B registered the
  virtual drifts, and the function classes are covered by explicit
  `TuneFunction`, `NamedTuple` and aperture-callback arms), "... every knob
  operator round-trips through the snapshot" (162: all 24 whitelisted
  operators and the named constants, derived from `_KNOB_OPERATORS` with a
  coverage tripwire), "... the snapshot reader refuses by name" (91: the
  unknown format, the missing `[machine]`, the unknown kind, the unknown key,
  the bare string, the undefined and the three conflicting-knob cases, the
  dangling `ref`, the unregistered object type, the missing sidecar and the
  digest mismatch, the function-valued parameter at write).
- Unit B (d7b439d; `src/lattice/toml_hooks.jl` +743, `src/tasks/BeamObservers.jl`
  26 lines changed (the additive `MomentObserver(; name, moments)` route,
  the resolved selection given alone and canonicalised, refused beside
  `orders`, `extra` or `exclude`), `test/runtests.jl` +306): the
  `_toml_encode_object`/`_toml_decode_object` methods for the hooks
  (`ScheduledObserver`, `ScheduledAction`), the markers
  (`StrongStrongCollision`), the solvers and their nested option objects
  (`LongitudinalSlicing`, the virtual drifts, the launch configuration, the
  luminosity schedule), the schedules, the turn rules (`WhiteNoise`,
  `PinkNoise`, `TurnTable` by reference to the sidecar with the digest
  verified on reading, `SpectralNoise` refused by name) through the option
  schemas `validate_configuration_metadata()` sweeps; the registry-derived
  tripwire that every concrete observer, schedule, solver and rule type is
  registered in `_TOML_OBJECT_TYPES` or in the documented refusal list
  (`_toml_refused_object_types()`: `PredicateSchedule`, `BeamSwapAction`,
  `SpectralNoise`, each refusing by the field that holds the function). The
  option values are typed by the schemas (`_toml_option_encode`,
  `_toml_option_decode`: symbols bare, tuples, sets and vectors as arrays,
  unsigned ids decimal, nested objects recursively; an unknown key refused
  listing the schema's, a missing key taking the constructor's default);
  the solvers are rebuilt as `Solver{eltype}(; ...)` in the lattice's numeric
  type and a solver or rule of another numeric type is refused at write, as
  is a `TurnTable` carrying a resolved seed. Registered by unit B: the four
  solvers, `LongitudinalSlicing`, `CUDAPICLaunchConfig`, the six virtual
  drifts, `AlwaysSchedule`, `EveryNSteps`, `AtTurns`, `ScheduledObserver`,
  `ScheduledAction`, `StrongStrongCollision`, `MomentObserver`,
  `CoordinateSnapshotObserver`, `BPMObserver`, `WhiteNoise`, `PinkNoise`,
  `TurnTable` (24); by unit A the six tracking methods and the enum (7).
  Testsets below `[MD4-B]`: "Machine description: every hook, marker,
  solver, schedule and rule type round-trips through the snapshot or is
  refused by name" (87: the tripwire over the registry, every registered
  type with non-default options through the codec and back equal by its
  report or configuration, a seven-offset table through the sidecar with its
  digest verified, the three refusals red by name) and "... the strong-strong
  example's machine round-trips and the reloaded task compiles the tuple
  spelling's runtime" (18: the example's two lines at small size as lattices
  in a machine, written and read back, the reloaded task's compiled runtime
  blocks of identical type and equal field by field, both beams bitwise
  equal after two turns, a `TurnTable`-modulated crab cavity through the
  sidecar file beside the TOML).
- Unit C (bd6c16d; against the skeleton `src/tasks/RunArtifact.jl` 243 lines
  changed, `src/tasks/Tasks.jl` 34, `src/tasks/strongstrong/interface.jl` 64,
  `examples/strong_strong_tracking.jl` 23, `src/examples/Examples.jl` 4,
  `test/runtests.jl` +244, the docs 482 lines changed, this record included):
  the artifact embedding
  (D14). Both task structs gain a last field `machine::Union{Nothing,Machine}`
  set by their constructors from the spelling of the input: `Machine(lattice)`
  for `TrackingTask(lattice)`, the given machine for `TrackingTask(machine)`
  and for the two `StrongStrongTask` machine forms, the derived two-lattice
  machine `Machine("<name1>+<name2>"; lattices = (l1, l2))` for
  `StrongStrongTask(lattice1, lattice2)` with the roots both lattices declare
  as its shared ones, `Machine(l1)` when one lattice object is both lines,
  and `nothing` for tuples, vectors and bare lines and, with no warning, when
  no machine can hold the pair (two distinct lattices of one name, roots
  that overlap as dotted prefixes). `prepare_run_artifact!` takes the field
  as `machine = nothing`, renders `machine_toml(machine, tables)` on rank 0
  before the lock and the open, and writes the text into the new ledger
  column `machine_toml` and its SHA-256 hex digest into `machine_sha256`
  (both `""` without a machine), every bulk table under
  `/machine_tables/<sha256>` as a Float64 dataset (the group created at the
  first table, a digest already present skipped, so a continued file holds
  each table once; the group is not a product kind and `read(out, :all)` and
  the contents walker skip it, while the table of contents lists its digests
  and lengths); a machine the codec refuses (an `ArgumentError`: a
  function-valued parameter) warns once with the codec's message and records
  the empty columns rather than stopping the run. The readers: `read(out,
  :machine; slot = nothing)` returns the text of the last `execute!` row or
  of the ledger row `slot`, refusing by name an empty text (the task was
  built from tuples, or its machine could not be snapshotted; the remedy is
  the `Lattice` or `Machine` spelling), a `slot` outside the ledger, `slot`
  with any other kind, and a file written before the column existed;
  `read_machine(out::TaskOutput; slot, receipt)` parses it with the tables of
  the group through `parse_machine`. The continuation check
  `_ra_check_ledger_columns` keeps refusing a file lacking any column, its
  message now naming the generation the absent columns belong to (the seed
  columns, 2026-10-16; the machine columns, 2026-11-25); `read(out,
  :execution)` reads `nothing` for a column an old file lacks, as before. The
  shipped strong-strong example writes its machine once,
  `write_machine(joinpath(outdir, input.case_name * ".machine.toml"),
  machine)` (rank 0 under `:multiprocess`), prints the path beside the
  artifact's and names the file in its header; the catalogue entry mentions
  the snapshot. Testsets below `[MD4-C]`: "Machine description: the run
  artifact embeds the machine snapshot and reads it back" (38: the two
  columns in the table and the file, the text byte for byte
  `machine_toml(Machine(lattice))` and the file `write_machine` writes, the
  digest, `read_machine(out) == Machine(lattice)` with its receipt, a second
  `execute!` appending a row with the same text, the `slot` reads and
  refusals, the tuple-built row `""` with both readers refusing by name, a
  `StrongStrongTask(machine, :A, :B; artifact)` run of one turn embedding the
  two-lattice machine and reading it back equal, a `TurnTable`-modulated RF
  cavity putting its table under `/machine_tables` once over two rows with
  the reload's table equal to the original, a predicate-schedule hook making
  the prepare warn and record `""`, and an old-format ledger built through
  the writer's helpers reading `nothing` for the columns, refusing the
  machine readers by date and refusing continuation naming the machine
  generation alone) and "... the task records the machine it was given, by
  spelling" (20: the field for every input shape of both tasks, the
  derived machine's name, order and shared roots, the same-name and
  overlapping-root `nothing`s); the ledger testset "Run artifact exclusion
  and seed provenance ..." gains the machine generation (the 2026-10-16
  layout refused naming the machine columns alone, continuing once they are
  added, with `machine_toml == [""]`) and the two column pins.
- Docs (unit C): `public_api.md` ("Describe A Lattice" gains the "Snapshot A
  Machine" paragraph with its example lines and the four help entries; the
  run-artifact reader section gains `read(out, :machine)` and
  `read_machine(out)` and the ledger paragraph the two columns), the design
  note's banner, the dated status sentences of D13 and D14 and the staging
  item, `run_artifact.md` (the `/machine_tables` schema line and the dated
  paragraph "The machine snapshot"), `README.md`, `todo.md`, this record; the
  snapshot regenerated at the fold (the four exports entering the wrapped
  export list and the strong-strong example's entry, 17 lines changed).

## 2 Decisions

- The format is the `write_machine` docstring, one source for the writer,
  the reader and every unit: tables in a fixed order, keys sorted where the
  format does not fix them, elements by their STORED parameters (the folded
  form the friendly constructors produce) read back through the flexible
  `ElementSpec{kind}(params)` form, so the per-kind round trip pins that
  friendly folding and flexible storage agree. Two details settled against
  the design note's D13 text: every element is a section table (no width
  rule, no inline form) and the elements print in first-placement order with
  one table per distinct spec object, so an object placed twice is one table
  referenced twice and `e.spec === qf` survives the round trip (unit A's
  report confirms both).
- The value rules read the metadata as a serializer must: `ParamMeta`
  carries no type, so the class of a stored value (a symbol to print bare, an
  array to read back as a tuple) is taken from the default, the alternatives
  and the kind's example value, and where none of the three speaks the value
  prints in a marker form (`{ tuple = [...] }`, `{ vector = [...] }`,
  `{ matrix = [[...]] }`, `{ symbol = "..." }`, `{ type_name = "..." }`)
  that needs no hint to read; `{ nothing = true }` because TOML has no null
  and a stored `nothing` is not an absent key; floats re-narrowed on reading
  by the stored `numeric_type` as the typed constructor converts; unsigned
  integers as decimal; a `BigFloat` value refused rather than rounded. The
  knobs are declared in dependency order from the expressions, a path
  already present with the same type and value or expression is kept and
  reported, a different one refused: a reload is idempotent and never
  rewires. Every refusal goes through `_toml_refuse` and names where it
  happened (`machine snapshot: at lattices.ESR.elements.QF.kn[2]: ...`).
- The emitter is Octopus's own rather than `TOML.print`: the standard
  library renders an array of tables as array-of-tables sections, which
  would have made the members of a line unreadable, and the format's
  one-line inline members, fixed key order and quoting rules are forty lines
  the printer could not be told.
- The objects beside the elements print by their option schemas, requested
  values only and never the `resolved_*` entries, and are rebuilt by the
  keyword constructors in the lattice's numeric type (a solver or rule typed
  otherwise is refused at write: the tables carry no type of their own, and
  a mixed-type lattice is not a shape the tasks accept either); a schema key
  the table omits takes the constructor's default while an unknown key
  refuses, the keyword constructor's own reading of a call. The `TurnTable`
  goes by reference with its SHA-256 verified on reading and a table carrying
  a resolved seed is refused (the seed is the run's, not the description's);
  `SpectralNoise`, `PredicateSchedule` and `BeamSwapAction` are refused by
  the field that holds a function, and the refusal list is the tripwire's
  second column. `MomentObserver` stores its resolved selection, so the one
  additive route a faithful rebuild needed is `MomentObserver(; name,
  moments)`, the canonical names written by the codec and refused beside the
  selecting keywords. A marker one object serves in two lattices reloads as
  two equal, distinct markers, which the task pairs by label and whose
  solvers it compares by configuration.
- The task records the machine it was given, by spelling, never derived from
  the placements: a tuple-built task has no lattice context (no name,
  reference, roots or numeric type) and records `""`, and the readers refuse
  by name with the spelling as the remedy rather than inventing a lattice.
  `StrongStrongTask(lattice1, lattice2)` derives the two-lattice machine
  `Machine("<name1>+<name2>")`, with the roots both lattices declare as its
  shared ones so the machine-level half of D7 accepts what the two already
  read together, and `nothing`, with no warning, when no machine can hold the
  pair (two distinct lattices of one name, since the names are a machine's
  keys; roots that overlap as dotted prefixes): the line form accepted every
  such pair before the field existed and still does, so the derivation never
  refuses. The machine forms store the machine they were handed, its own name
  kept, which is why the line form's body became the inner builder
  `_strong_strong_task(line1, line2, machine; kwargs...)` and the public
  constructor a wrapper deriving the field, rather than a `machine` keyword
  on the public constructor (a public option without a runtime consumer of
  its own) or a struct rebuilt after construction.
- The snapshot is the run's by-product, not its condition: a machine the
  codec refuses to snapshot (an `ArgumentError` from `_toml_refuse`: a
  function-valued parameter such as a predicate schedule) warns once at
  prepare with the codec's message and records the empty columns, so the run
  proceeds and the reader refuses by name later; stopping a tracking run for
  a description it cannot serialise would refuse call shapes the lattice
  spelling accepted before this stage. Any other error propagates. An owner
  call to revisit if a hard refusal is preferred (`todo.md`, the carried row).
- The two columns join the one ledger table (`_RA_LEDGER_COLUMNS`), so
  creation, the appended row, the continuation check, the reader and the
  suite's pins derive them; a continued (`append=true`) file lacking them is
  refused by name as the seed columns' precedent (2026-10-16, S5-4) and never
  padded, since an empty machine column would claim "built from tuples" of
  rows that recorded nothing either way, while reading an old file stays
  possible (`nothing` for the absent columns). The message names the
  generation(s) the absent columns belong to, so a 2026-10-16 file is told
  about the machine columns alone.
- `/machine_tables` is content-addressed and shared, not a product group: one
  dataset per distinct digest however many rows reference it, created at the
  first table so a tuple-built or table-free file has no such group; it is
  outside `_RA_GROUPS` (`read(out, :all)` and the contents walker skip it, the
  product-group pin of the suite stays derived from the table), listed by the
  table of contents as digest => length, and read with the text by
  `read_machine(out)`. `read(out, :machine)` is likewise a view of the ledger
  (the `machine_toml` column of one row, selected by `slot`), not a kind of
  its own.
- The text is rendered on rank 0 before the lock and the open (validation
  before mutation, 2026-10-19): a codec error touches nothing on disk, and
  the non-root ranks render nothing (they write nothing).
- The example writes its snapshot once, beside the artifact, under the
  machine's own name derived from `case_name`; under `:multiprocess` rank 0
  writes it, as the library does for the artifact, through the `MPI` module
  the mode already requires in `Main`.

## 3 Verification

- Extracted per unit, in package mode (`test/run_extracted_testsets.jl`),
  before each unit's commit (the unit reports, logs under the scratch
  directory of the day): unit A's four testsets 47, 214, 162 and 91 of as
  many (the per-kind one 226 once unit B's virtual drifts were registered;
  its first run was red on two literal float comparisons, fixed to compare
  the product), the neighbours "Machine description: a Lattice wraps a line
  and is accepted where the line is" 42, "... lattice equality is
  structural and the record prints" 24, "... the shipped DBA lattice module
  builds an equal lattice when included twice" 13, "Knob registry atomicity
  and round-trip totality" 50 and "Knob control" 156 of 158 (the two reds
  the Symbolics extension the extracted runner does not load, its documented
  limit); unit B's two testsets 87 and 18 of as many (a first merged run
  errored on its `{ nothing = true }` spelling meeting unit A's emitter rule
  and a Core.Box the sweep caught in `_toml_option_decode`, both fixed), the
  neighbours "Turn modulation: the RF cavity by the same wrap" 147,
  "MomentObserver task reuse" 4, "A Float32 beam's BPM centroid accumulates
  in Float64, as the moment observer does" 7, `validate_configuration_metadata()`
  `true`; unit C's two testsets, on its branch with units A and B merged
  (d7bbf21), "Machine description: the run artifact embeds the machine
  snapshot and reads it back" 38 of 38 and "... the task records the machine
  it was given, by spelling" 20 of 20, the ledger testset "Run artifact
  exclusion and seed provenance: the sidecar lock, lock-aware readers, the
  ledger's rng columns" 60 of 60 (it executes tuple-built tasks, so it ran
  green before the merges too, 60 of 60), the three source sweeps "Every
  export is documented" 1, "No docstring is detached by comment lines" 11,
  "No method grows a Core.Box outside the argued allowlist" 5 in every run.
  The embed testset's two earlier runs are on record as the dependency they
  measured: on unit C's tree with unit A alone merged, 22 of 24 and then 26
  of 28, the two errors in each the `StrongStrongCollision` marker
  unregistered until unit B's `toml_hooks.jl` (the prepare warned by name and
  recorded the empty columns, as designed, and the reader refused). The
  strong-strong example as a script once at its default configuration
  (`:auto`, which found the CUDA device; 2 turns, the PIC solver): exit 0,
  its `machine snapshot = .../result/123456789/pic_hcc.machine.toml` line
  printed beside the artifact's and the file present (13,984 bytes; the
  artifact 194,573 bytes); unit C's probe over that run (include mode): the
  artifact's `machine_toml` equal to the file byte for byte (13,984 bytes),
  the `machine_sha256` column the text's digest, `read_machine(out) ==
  read_machine(file)` with the keys `("ESR", "HSR")`, no `/machine_tables`
  group (the example holds no table), and the reloaded machine idempotent:
  `machine_toml(read_machine(file)) == file` and `write_machine` of it
  byte-identical to the file, so the example's every value class (the
  `linear6d` matrix as a flat tuple, the crab cavities' per-mode arrays with
  `{ nothing = true }` rules, the PIC solver with its slicing, the moment
  observers with their schedules, the references) survives the round trip.
- On the folded tree (2026-11-25 18:34 to 18:42 EST,
  `result/gates/md4/extracted_checks.log`): `validate_configuration_metadata()`
  `true`; `validate_element_metadata()` passed, 614 of 614 default pairs and
  34 of 34 runtime variants; `element_help` renders both forms for all 32
  kinds; the regenerated snapshot equal to the committed one. Extracted,
  every block green: "No method grows a Core.Box outside the argued
  allowlist" 5, "No docstring is detached by comment lines" 11, "Every
  export is documented" 1, "Every exported API name appears in the registry
  snapshot" 17, "Architecture integrity" 50, "the Example core object
  answers with real scripts" 60, "Stage 5: every kind that declares the
  analysis analyzes its own example, or refuses it for the documented
  reason" 64, the stage-2 neighbours 42, 13, 24 and 13, the stage-3
  neighbours 35, 12, 11, 19 and 15, "No committed script constructs a
  retired observer or task spelling" 41, the stage's eight testsets 47, 226,
  162, 91, 87, 18, 38 and 20, "Run artifact exclusion and seed provenance:
  the sidecar lock, lock-aware readers, the ledger's rng columns" 60, "Knob
  registry atomicity and round-trip totality" 50, "Turn modulation: the RF
  cavity by the same wrap" 147; the neighbour "StrongStrongTask chunking
  preserves stochastic physics" 12 of 12 in a second process with its
  helper as the runner's prelude (`extracted_chunking.log`).
- The tripwires: the registry-derived round trip per kind, all 32
  registered kinds through their metadata example, the object, the file and
  back, 32 of 32 equal and byte-identical on a second write (no kind refuses:
  the function-valued classes are tested on constructed values, since no
  kind's example holds one); the object types, 31 registered in
  `_TOML_OBJECT_TYPES` (24 by unit B, 7 by unit A) and 3 in the refusal
  list, every concrete observer, schedule, action, solver and rule type the
  registry knows in one of the two and none in both.
- The byte-identical pins: two snapshots of one machine byte-identical
  (`machine_toml` twice, `write_machine` twice); the artifact's embedded text
  equal to `machine_toml(Machine(lattice))` and to the file `write_machine`
  writes (the testset above, green); unit A's DBA pin (the text from the
  original and from the reload byte-identical, two writes byte-identical,
  every kind's second write byte-identical) and unit B's example pin
  (`write_machine` of the reloaded machine byte-identical to the file). The
  orchestrator's probe on the folded tree: the shipped DBA module's lattice
  (1,576 bytes of text) and the shipped strong-strong machine (13,984 bytes)
  written, read and written again byte for byte; the reloaded strong-strong
  machine is `==` its original only before the original has executed, since
  a `MomentObserver` carries its run state (buffer, record count, artifact
  handle) inside the object `Lattice`'s structural equality walks, which the
  snapshot rightly leaves out (section 4).
- The examples' fingerprints (SHA-256, the LinearOptics record's quantities
  and hashing rule; `ws`, `ss`, `cn`, `dba` as in the stage-3 record),
  baseline the stage-3 tree (the stage-3 record's "post" runs, code
  e1b011a, reused byte for byte) against the stage-4 tree (the merged `md4`
  tree 339b627, whose code is this tail's; 2026-11-25 18:34 to 18:41 EST,
  logs under `result/gates/md4/compare/`). Only the `ss` script changed in
  this stage, by one write (`write_machine` of its machine) and one print
  line, so its rows are expected identical on CPU threads and within the
  device noise floor on CUDA, as the stage-3 record measured them; every
  other row pins that the new includes, the new methods, the two ledger
  columns and the regenerated snapshot moved nothing else. The result, in
  the stage-3 table's form: all twenty CPU hashes identical (`ws` 4, `ss` 6,
  `cn` 3, `dba` 7); on CUDA the fourteen deterministic rows identical in
  both runs and the six `ss` rows different, as they are between any two
  device runs. Maximum relative difference per table, luminosity / electron
  moments / proton moments: the floor, baseline run 1 against baseline run
  2, 1.706e-11 / 1.334e-09 / 5.825e-10; stage-4 run 1 against stage-4 run 2,
  1.344e-11 / 3.903e-09 / 1.191e-09; across the trees, baseline 1 against
  stage-4 1, 1.492e-11 / 1.604e-09 / 6.251e-10, baseline 2 against stage-4
  2, 1.883e-11 / 3.634e-09 / 9.361e-10, baseline 1 against stage-4 2,
  1.284e-11 / 2.300e-09 / 8.641e-10, baseline 2 against stage-4 1,
  1.457e-11 / 9.631e-10 / 1.208e-09 (worst columns `m001010` and `m000100`
  throughout). Every cross-tree value sits inside the range the two
  same-tree pairs span: nothing attributable to the stage moved. The
  weak-strong, crab-noise and DBA tables are bit-identical (0.0 everywhere),
  the CPU strong-strong tables too.
- The fast lane and the full gate at CI settings with CUDA active ran on this
  tree after this record was written and before the final commits were made
  from it, so their numbers are in the commit messages (the feature commits
  and the record commit), not here: the record cannot carry the lane that
  covers its own last line. Logs: `result/gates/md4/fast_lane.log`,
  `result/gates/md4/full_gate_native.log`.

## 4 Carried and open

- Owner call (this stage): a machine the codec cannot snapshot warns at
  prepare and records an empty `machine_toml`; the alternative, refusing the
  `execute!`, would stop a run for its by-product and refuse call shapes the
  lattice spelling accepted before. Carried in `todo.md`.
- From the unit reports, leads for the stage-5 neighbour audit (its lead
  list gains the stage's entry points: `_ra_machine_snapshot`,
  `_ra_write_machine_tables!`, `_ra_machine_text`, `_strong_strong_machine`,
  `_task_machine`, `_toml_encode_value`/`_toml_decode_value`,
  `_toml_element_table`/`_toml_decode_element`, `_toml_line_table`/
  `_toml_decode_line`, `_toml_knobs_table`/`_toml_declare_knobs!`,
  `_toml_emit`, `_toml_option_encode`/`_toml_option_decode`, the
  `MomentObserver(; moments)` route): the `StrongStrongTask`
  line form is now a wrapper over `_strong_strong_task`, so an unknown
  keyword's `MethodError` names the inner builder; the derived two-lattice
  machine is `nothing` without a warning where no machine can hold the pair;
  a continued pre-stage-4 artifact is refused by name for lack of the machine
  columns (the seed columns' precedent, never padded); `AtTurns`'s `==`
  is identity (its `Set` field), so two independently built solvers
  scheduling luminosity with equal `AtTurns` compare unequal in
  `solver_configuration` and the strong-strong pairing would refuse them,
  pre-existing and found by unit B's round trip (its test compares
  structurally); a lattice whose observers have run is no longer `==` its
  pristine twin, since `MomentObserver` keeps its buffer, record count and
  artifact handle in the object the structural equality walks (compare hooks
  by their configuration report instead: a change of `==` semantics, with a
  blast radius to measure first); readability of the text: `EveryNSteps`
  prints its `stop` as `typemax(Int)` when none was given, and parameters
  whose `ParamMeta` carries neither a default nor an example of the right
  class print in the marker form (`Linear6DSpec`'s `beta1`, `matrix` as
  `{ tuple = [...] }`), both cured by metadata (a type or a typed default on
  `ParamMeta`, which has none today) rather than by the codec; `rng_id` reads
  back as `Int` where it was `UInt64` (equal by `isequal`, converted by the
  constructors); a reloaded knob root is a namespace and not a bound
  constant, so `root.path = v` needs one `@knob` under it in the session; a
  solver or rule of another numeric type than its lattice is refused at
  write (a `numeric_type` key on the object tables would lift it); decoding
  re-claims explicit stream ids silently and auto-assigned ones through the
  registry's one warning.
- Unchanged by this stage and still carried (the stage-3 record and
  `todo.md`): the owner question whether the machine should hold beam
  definitions (the snapshot carries lattices, knobs and references, no beam);
  the stage-3 leads (the `LineEntry`-wrapping walker class, the 410 bytes per
  `execute!` of placement-spelled lines, the nested-root narrowing, the
  fixtures' stream ids, the small-size CUDA `ss` REPORT verdict); the
  reference batch's gap (no task compares the beam's reference with a
  cavity's stored pair at compile) and the shipped example's `rng_id = 2`
  warning.
- Stage 5 (`with_overrides`, D11, then the neighbour audit over
  `_element_tuple`'s callers, the two task constructors, the placement-override
  guards and the knob epoch, with the stage-4 entry points above) remains; the
  design note's staging section marks item 4 landed.

## 5 Ledger and the previous push

`README.md`: this record indexed, the design entry naming the stage.
`todo.md`: the machine-description row (stage 4 implemented, what it
delivered, the previous push's CI) and the carried row (the stage-4 leads of
section 4). `public_api.md`: "Describe A Lattice" (the "Snapshot A Machine"
paragraph, its example lines, the four help entries) and the run-artifact
reader section (`read(out, :machine)`, `read_machine(out)`, the ledger's two
columns). The design notes: `machine_description.md` (the banner, the dated
status of D13 and D14, the staging item) and `run_artifact.md` (the
`/machine_tables` schema line, "The machine snapshot"). `experiences.md`: the
lesson "A serializer is the strictest reader of metadata". The previous push:
stage 3 as e1b011a on `origin/main` (pushed 2026-11-25 17:06 EST, its tail
the linear replay of the stage-3 record), CI run 491 (id 45710327150) ran 2026-11-25 22:06:21 to 23:44:28 UTC
(98 min 7 s): success, the "Julia 1.12 CPU full-lane tests" job green; no
intermediate docs-draft commit sits in that history
(`result/gates/md3/ci_watch.log`).
