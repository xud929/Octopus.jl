# The machine description: `Lattice`, `Machine`, the element block and the TOML snapshot

> **Status: designed 2026-11-24 in owner discussion; the owner authorised this
> note and the staging of section 3 the same day ("Ok. Do it now."). Stage 2
> landed 2026-11-25, record
> [`../history/machine_description_stage2_2026_11_25.md`](../history/machine_description_stage2_2026_11_25.md):
> implemented are D3 (`Lattice`), D7 (the knob-root tripwire), D9
> (`@elements`, `@element`), D10 (the friendly constructors accepting knob
> expressions at every fold site and typed-by-hand form of section 4, the `LinearOptics` point measured and kept numeric by name), D12 as acceptance
> (`ReferenceParticle` exists and is carried on the lattice; since the
> reference batch of 2026-11-25, record
> [`../history/machine_description_reference_2026_11_25.md`](../history/machine_description_reference_2026_11_25.md),
> `Beam` and both cavities take it as `reference = ReferenceParticle` in
> place of their flat keywords, while the compile-path unification of D12
> remains proposed), D15 for `TrackingTask` and `analyze`, and D16
> (`src/lattice/`). Stage 3 landed 2026-11-25, record
> [`../history/machine_description_stage3_2026_11_25.md`](../history/machine_description_stage3_2026_11_25.md):
> D5 implemented as the namespace of lattices by name and the knob roots they
> share (beam definitions and machine-level reference particles, which D5
> lists, are deferred until a runtime consumer reads them, an owner question
> that record carries), the machine-level half of D7's tripwire, and D15 for
> `StrongStrongTask` and `one_turn_matrix`. Stage 4 landed 2026-11-25, record
> [`../history/machine_description_stage4_2026_11_25.md`](../history/machine_description_stage4_2026_11_25.md):
> D13 implemented as `write_machine`, `read_machine`, `machine_toml` and
> `parse_machine` over the format the `write_machine` docstring states (the
> registry-derived round trip per kind, the knobs by path, the hooks, markers
> and solvers by their option schemas, the bulk tables by digest), and D14 as
> the `machine_toml` and `machine_sha256` columns of the run artifact's
> ledger with the tables under `/machine_tables`, read back by
> `read(out, :machine)` and `read_machine(out)`. Stage 5 landed 2026-11-25,
> record
> [`../history/machine_description_stage5_2026_11_25.md`](../history/machine_description_stage5_2026_11_25.md):
> D11 implemented as `with_overrides` for a lattice and for a machine (the
> derived lattice; since the campaign's neighbour audit, recorded in
> [`../history/audit_machine_description_2026_11_25.md`](../history/audit_machine_description_2026_11_25.md),
> the in-place route and the snapshot's writer and reader refuse the same
> override classes the derived route refuses). Every item of the staging
> (section 3) has landed; what remains proposed is the compile-path half of
> D12 and the owner items the records carry, and the "(proposed)" markers
> below read as the state when the note was written. The owner's rulings of
> 2026-11-26 on the carried items and on the data form's questions, and the
> batches they add up to, are in
> [`machine_description_followups.md`](machine_description_followups.md);
> D5's beam-definition question is closed there (no).** Parent notes:
> [`../theory/beam_line_composition.md`](../theory/beam_line_composition.md)
> (the line layer this builds on: placements, provenance, selectors, its
> decisions 1 to 7), [`../knob_control.md`](../knob_control.md) (knobs as
> expression trees, the surface grammar and its total round trip),
> [`survey_and_reference_channel.md`](survey_and_reference_channel.md) (the
> reference is bookkeeping derived at compile; its sections 5 and 6 settle
> where a reference particle lives and how a ramp is modelled),
> [`linear_optics.md`](linear_optics.md) (a value object that consumers
> flatten; the precedent for a Knowledge-Layer record that is not a Core
> Object), [`run_artifact.md`](run_artifact.md) (where the snapshot is
> embedded).

## 1. The problem

Octopus describes a lattice in Julia, and the description layer is further
along than the question "should we have a lattice description" suggests.
Measured on the tree at `7b372b7` (2026-11-24):

- The line layer exists and was designed against MAD-X, Bmad, elegant,
  Accelerator Toolbox and JuAcc: `BeamLine` with nesting, `repeat`,
  `reverse`, placements carrying provenance paths, tags and per-occurrence
  overrides, the `sel"..."` selector, `s_positions`, `find_entries`. Element
  `name` is a declared parameter on every kind, carried into the provenance
  path (`ARC1/CQS[3]/QF[1]`; an unnamed quadrupole addresses as
  `QUADRUPOLE[7]`). Knobs are expression trees with a lossless surface
  syntax. `LinearOptics` is the recommended spelling of linear optics.
- No reader or writer of any lattice format exists in `src/`. Every external
  comparison carries a hand-spelled twin: the MAD-X twiss generator holds its
  element definitions as strings per fixture (`MadxFixture.elements`,
  `validation/generate_madx_twiss_reference.jl`), the Xsuite generator "reads
  the constants by eye" (`validation/twiss_benchmark_cells.jl`), and the
  BBSCL comparison needed three Python input generators
  (`validation/bbscl_comparison/gen_bbscl_*.py`).
- Tasks consume bare tuples. `TrackingTask(elements; ...)` normalises its
  argument through `_element_tuple` (a tuple, a vector, or a `BeamLine` that
  dissolves into its placements), and `StrongStrongTask(line1, line2; ...)`
  does the same twice. Call sites of the two constructors, counted by a grep
  for `TrackingTask(` and `StrongStrongTask(` outside their definitions:

  | directory | `TrackingTask(` | `StrongStrongTask(` |
  |---|---|---|
  | `src/` | 25 | 17 |
  | `test/` | 429 | 101 |
  | `examples/` | 6 | 1 |
  | `validation/` | 14 | 17 |
  | `profiling/` | 2 | 4 |

  Every one of them is a compatibility site: the design is additive or it is
  wrong.
- The reference particle is spelled by hand. `beta0 =` appears 33 times in
  `src/`, 39 in `test/`, 54 in `validation/`; `gamma0 =` 34, 43, 57; `mc2 =`
  22, 192, 41; `E0 =` 15, 140, 44; `reference_beta_gamma(` 11, 21, 4. The DBA
  example derives `beta0, gamma0` once and hands them to its cavity; the
  strong-strong example hands `charge`, `mc2`, `E0` to each `Beam`. The
  reference-channel note (section 5) already decided that the authoritative
  objects are the survey and `BeamParams.E0` and that per-element values are
  derived at compile; nothing yet carries that reference as one object.
- A lattice has no textual identity. Two open ledger rows are symptoms: the
  turn-modulation receipt names an element by its type only, and
  `rng_id = 0` makes provenance depend on construction order. A run artifact
  records what ran, not the lattice it ran.
- The provenance of what a physicist would call "the machine" is spread over
  a script: the strong-strong example's own comments record the half crossing
  angle typed four times and drifting (F-206) before the input block derived
  it once.

What the owner asked for (2026-11-24): a convenient Julia description of
elements and beam lines, no new lattice language, a native data form that
can be saved and read back, and afterwards translators to and from the other
codes' inputs. What the discussion settled is below; what it deliberately
left out is in section 2's last decision.

## 2. Decisions

- **D1 Julia is the input language.** No lattice language of Octopus's own,
  and no operator algebra (`3 * cell`, `-cell`): the composition note's
  section 4 argued half of that zoo is over-design and that reflection is
  routinely confused with reversal; `repeat` and `reverse` say what they do.
  Rejected: a MAD-X-like text language (a compiler project whose semantics,
  not syntax, are the hard part; the AML/UAP universal-format effort of the
  2000s did not displace MAD syntax for the same reason), and the operator
  sugar the owner declined on 2026-11-24.

- **D2 Four forms of one truth.** The authoring form is a Julia module. The
  truth at run time is the in-memory object. The data form is a TOML
  snapshot. The execution form is the compiled runtime, derived and never
  stored. Module, object and file round-trip under tripwires (D13, section
  3); the runtime is derived from the object as today. The lesson borrowed
  from infrastructure-as-code: pure data cannot abstract and pure code leaves
  no inspectable artifact, so author in a language and persist a canonical
  data form.

- **D3 `Lattice` is a small record around a top-level `BeamLine`.**
  `Lattice(name; line, reference, knob_root, eltype)` (proposed): the line,
  the entrance `ReferenceParticle` (D12), the knob root the lattice's
  expressions must live under (D7), the numeric type every element must
  share, a name for provenance. It is not a parameter set on the line
  itself: the composition note's section 10 dissolves a line that carries
  nothing of its own and keeps whole one that carries state, so a line with
  a `reference` parameter would stop dissolving when nested; the record keeps
  `BeamLine` composable and gives the task and the serialiser one top-level
  object. `BeamLine` and `Lattice` are therefore not the same thing: the line
  is the sequence, the lattice is the sequence used as a beam's lattice plus
  the context the sequence does not carry. Not a Core Object (D16).

- **D4 No closure flag.** Whether a sequence is treated as a ring or as a
  transfer line is a boundary condition of the problem posed on it, as in
  MAD-X and Xsuite, where neither the sequence nor the `Line` carries a
  flag: a FODO cell has a periodic Twiss solution when the question is
  "repeated indefinitely" and a transported one from an initial condition,
  and a ring's arc is tracked as a line whenever the first turn from
  injection is followed. Every task Octopus has assumes a ring, so an `open`
  value would land without a consumer, which the invariants forbid. When a
  transfer-line task or an open-line Twiss arrives, the boundary condition
  arrives with it as an option on that task or analysis, and the machine
  (D5) states which lattices it uses as rings. A survey-closure consistency
  check belongs to the consumer that assumes a ring. Rejected: Bmad's
  `geometry = closed | open` on the branch, the one code that puts it on the
  lattice. An earlier draft of this design had `periodic` on the lattice; the
  owner's objection (2026-11-24) is recorded here so the reasoning stays
  visible.

- **D5 `Machine` is the facility's namespace of definitions.** Lattices by
  name, knobs as the power supplies (D7), reference particles, beam
  definitions; nothing about how lattices connect, nothing about closure,
  and no interaction-point concept. A machine may hold a linac, a ramping
  ring, transfer lines and injection lines beside a collider's two rings;
  "not every machine is a collider" (owner, 2026-11-24). Xsuite's
  `Environment` is this object; MAD-X's global space of sequences, beams and
  variables is its older form. A task given a bare `Lattice` is a one-lattice
  machine implicitly, so the single-ring user never sees the extra level.
  Rejected: a machine that pairs lattices at shared points with per-beam
  frames and filling patterns (an earlier draft); its fields had no runtime
  consumer, and pairing is the task's business (D6). The revolution-period
  consistency of two rings that meet every turn is a check for the task that
  pairs them, the only place that knows they do.
  Status 2026-11-25: implemented in stage 3 as `Machine(name; lattices,
  knob_root)`, the lattices by name in declaration order and the knob roots
  they share, with the readers (`machine[:ESR]`, `keys`, `haskey`, `length`,
  iteration), structural equality and the machine-level root tripwire of D7,
  and `Machine(lattice)` as the explicit one-lattice machine (record
  [`../history/machine_description_stage3_2026_11_25.md`](../history/machine_description_stage3_2026_11_25.md));
  reference particles and beam definitions are not stored, since no runtime
  consumer reads a machine-level one while each `Lattice` carries its
  entrance reference (D3), an owner question that record carries.
  Decided 2026-11-26 (owner): no. The machine stores lattices and shared
  knob roots only; a beam describes a run, and the reproducibility motive
  moves to a beam receipt in the run artifact
  ([`machine_description_followups.md`](machine_description_followups.md), R1).

- **D6 Observers and solvers stay inside the lines; the solver stays on the
  collision marker.** Nothing changes in how a line is built or how
  `StrongStrongTask` pairs collision markers by order and label (owner,
  2026-11-24). Consequence for the data form: a line snapshot contains
  observers, their schedules and the solver on the marker, so the TOML schema
  derives from three metadata sources that already exist and are already
  swept by `validate_configuration_metadata()`: the element metadata, the
  observer and schedule option schemas, the solver option schemas. The
  snapshot is "the line as it ran", which is what provenance wants.

- **D7 Knob roots.** One root per lattice and one for the machine's shared
  quantities (the half crossing angle both beams' boosts and crab cavities
  read, `ip.half_crossing_angle` in `examples/knob_control.jl`). The knob
  registry is process-global and "namespaces are names, not modules"
  (`knob_control.md`, section 2), so two lattice modules declaring the same
  path would share one knob and redefinition would rewire it silently. The
  `Lattice` constructor therefore checks that every knob its expressions
  depend on sits under its declared roots, a tripwire rather than a
  convention. A root cannot be the module's own name, because a module is
  bound to its name inside itself and the knob macro binds the root as a
  constant in the calling module.

- **D8 Lattice modules are declarative.** Declarations and pure cell
  functions; no I/O, no unseeded randomness, no tracking. Including a module
  twice builds an equal lattice, and the suite pins that on the shipped
  lattice modules. This is Bazel's Starlark lesson: if code is the
  definition of record, restrict the code. The module is one of two
  producers of a `Lattice`; the TOML loader (D13) is the other, and both
  yield equal objects, so a lattice built in a Julia loop and one read from a
  file are the same kind of thing.

- **D9 The element block.** A macro `@elements T begin ... end` (proposed;
  `@element` for a single definition), with these rules and nothing more:
  (i) a call whose head is a registered kind name maps onto that kind's
  friendly constructor, read from `element_meta(kind).friendly_constructor`
  at expansion, so `QF = quadrupole(L = 0.35, k1 = 1.5)` becomes
  `QuadrupoleSpec{T}(name = "QF", L = 0.35, k1 = 1.5)`; a kind whose metadata
  declares no friendly constructor is refused by name with the remedy, the
  flexible form; (ii) the binding name is the default `name`, and an explicit
  `name =` wins, since imported MAD-X names such as `MQXA.1L5` are not Julia
  identifiers; (iii) the numeric type comes from the block header, `Float64`
  when omitted, and is applied as the `{T}` parameter of every constructor
  the block emits; (iv) `line(...)` is the `:line` kind and becomes
  `BeamLine(name, ...)`; (v) anything whose head is not a registered kind is
  left untouched, so helper calls, `LinearOptics` points and collision
  markers sit in the same block; (vi) the mapping is purely syntactic, so
  every error comes from the constructor with the kind's own message. Tests:
  `@macroexpand` fixtures, and a tripwire derived from the registry that
  every kind expands and builds. The name: not `@ele` (an abbreviation) and
  not `@ele_spec` (a near-twin of `@element_spec`, which declares a kind's
  schema and lives one layer down); `@elements` and `@element`, following
  `@testset` and `@kwdef`. Rejected: a macro that reads a module-level
  constant for the type (action at a distance; the header is visible beside
  the elements), with the constant acceptable later as the header's default
  only because D3's `eltype` check makes it safe. Implemented in stage 2
  with one change to rule (iii): the block applies the type through the
  `numeric_type = T` keyword every kind's friendly constructor routes to its
  typed form, not as a `{T}` parameter, because `ThinCrabCavitySpec{N}`
  carries the cavity count in its first parameter and a numeric `{T}` cannot
  be applied to it uniformly; an explicit `numeric_type =` on one call wins,
  as an explicit `name =` does.
  Status 2026-11-26 (R11 of
  [`machine_description_followups.md`](machine_description_followups.md),
  the compile-path batch): the MAD-X class form, `QuadrupoleSpec(Q; name =
  "QF", k1 = 1.0)` -- in the block `QF = quadrupole(RHIC.Q; k1 = 1.0)`, the
  positional template passing through rule 6 -- is one method on every
  kind's friendly constructor, installed by the registration itself; the
  flexible form folds a named strength as the constructors do, so the
  snapshot reader reads a hand-written `k1` as meant.

- **D10 The friendly constructors accept knob expressions** (owner,
  2026-11-24; consistency with D9, since the block maps kind calls onto the
  friendly constructors and the parameters people most want on a knob are
  the strengths and angles those constructors fold). The rule per path:
  conversion becomes "convert a number, keep an expression", which
  `_typed_spec_params` already does (`_as_numeric_type` converts floats and
  tuples and passes anything else through); folding builds whitelisted
  expression nodes when an operand is an expression (`angle / L` a division
  node, a sign flip a negation node), so the stored parameters remain the
  folded, flattened ones and the TOML stores `kn = [0.0, { expr = "..." }]`
  exactly as a flexible-form spec would; a construction the tree cannot
  express, the matrix inverse the strong-strong example takes for its
  inverse maps, keeps refusing the expression by name with the remedy. The
  flexible `ElementSpec{kind}(; ...)` form stays as the deferred path and as
  the loader's path. This is a pure widening: nothing that constructs today
  changes meaning, so no deprecation is needed. Measured sites (section 4):
  `_fold_named_strengths` and `_sbend_params` call `float` eagerly; the
  typed-by-hand forms named in `_stamp_numeric_type!`'s docstring (the linear
  maps, `Linear6DSpec`, the chromaticity kick, the strong beams, the
  radiation element, the crab cavity) convert by hand and are read one by one
  in stage 2. The test: an expression arm of the element effectiveness
  contract, per kind, derived from the registry: a spec built with an
  expression resolves at compile to the same runtime element, bitwise, as the
  spec built with the knob's current value, and a knob move between two
  compiles changes it. Whether the optics-point flattening should produce
  trees (thirty-six for a linear map) is measured in stage 2, not guessed.

- **D11 Three variation routes, and what in-place mutation is for.** Knobs,
  for numbers that move (declared dependencies, the epoch, receipts).
  Placement overrides, for per-occurrence differences: alignment errors, a
  trim on one magnet of a family, a noise rule and its stream on one cavity
  (`entry.phase_noise = (WhiteNoise(1e-5; rng_id = 11),)` wins over the spec
  and detaches that parameter from the family, as the `LineEntry` docstring
  documents; overrides merge into the spec before compile,
  `compile_runtime(::LineEntry)`). Derived lattices, for study variants:
  `override(lattice, selector => (param = value, ...), ...)` (proposed)
  copies the placements, as `BeamLine(; entries)` already does to avoid
  shared mutable state, applies the overrides and returns a new `Lattice`,
  leaving the module untouched so the pristine lattice and the variant
  coexist and the variant's snapshot shows the overrides as placement data.
  In-place mutation of a shared definition, `ESRLattice.TCCB.phase_noise = ...`,
  stays what it is today: legal, validated against the kind's metadata,
  and detected (`setproperty!` bumps the spec epoch, so every task recompiles
  at its next `execute!`). It changes every occurrence of the object in every
  lattice built afterwards in the process, so it is the interactive lever,
  not one a script of record uses. Access itself is Julia's: `ESRLattice.TCCB`
  reaches the binding, and a `const` binding cannot be rebound, nor can
  another module's globals be assigned. The verb: `with_overrides` (owner,
  2026-11-24; stage 5), not `override`. Status 2026-11-25: implemented in
  stage 5 (record
  [`../history/machine_description_stage5_2026_11_25.md`](../history/machine_description_stage5_2026_11_25.md))
  as `with_overrides(lattice, selector => (param = value, ...), ...; name)`
  and the machine form `with_overrides(machine, name, pairs...)`: the copy
  through `BeamLine(; entries)`, every selector `find_entries` takes, every
  key through the in-place route's guards plus the hook-placement and
  undeclared-key refusals (which the stage-5 neighbour audit then added to
  the in-place route, the snapshot's writer and its reader too, B-2 and B-10
  of [`../history/audit_machine_description_2026_11_25.md`](../history/audit_machine_description_2026_11_25.md)),
  a selector matching nothing and a call with no pair refused by name, no
  spec-epoch bump, the variant's snapshot showing the overrides as placement
  data; `override(...)` above reads as the proposal's spelling.

- **D12 `ReferenceParticle`, one type wherever a reference is spelled.**
  Species and momentum (charge, mass, energy or `p0c`; proposed), accepted by
  `Beam` in place of `charge`, `mc2`, `E0`, by the cavities in place of
  `beta0`, `gamma0`, and by the strong-beam kick-scale derivation. The
  lattice carries the entrance reference (D3); per-element values are
  derived at compile by the reference channel, which the reference-channel
  note designed for exactly this ("the authoritative objects are the line
  survey and `BeamParams.E0`, the per-element values are derived at compile
  time", its section 5), with the accelerating cavity advancing it along a
  linac (its section 6, case 2). An explicit per-element value stays
  accepted, deprecate-and-keep, and is refused by name when it disagrees with
  the bound one. A ramp is a knob on the reference with the epoch recompile
  and boundary rescaling (section 6, case 4 of that note), out of scope here
  and not foreclosed. The unification of the roughly seventy source sites and
  six hundred test and validation sites of section 1 is a compile-path
  campaign of its own with backend consistency; the description work accepts
  the type and carries it, nothing more.
  Status 2026-11-25: `Beam` and both cavities accept `reference =
  ReferenceParticle` in place of their flat keywords, in the light form
  (the object is flattened into the stored keywords by one funnel per
  consumer, so nothing downstream changes; record
  [`../history/machine_description_reference_2026_11_25.md`](../history/machine_description_reference_2026_11_25.md));
  the compile-path unification remains proposed, and its first lead is the
  gap that batch carried: no task compares the beam's reference with a
  cavity's stored `beta0`/`gamma0` at compile (`_validate_reference_chain`
  compares the cavities with one another only).
  Status 2026-11-26 (R3 to R5 of
  [`machine_description_followups.md`](machine_description_followups.md),
  the compile-path batch): the record is the richer immutable one (species
  presets; exactly one of `E0`, `p0c`, `gamma0`, `brho`, a number or a knob
  expression, the typed key stored; `p0c`, `gamma0`, `beta0`, `brho` and
  `r0` derived once); `Beam` takes `r0` from it or derives it from `mc2` and
  refuses the keyword; the strong-strong preflight refuses a zero factor of
  a derived kick scale and a reference-built beam without `npart`, warns once
  per task for a flat one, and the derived scales are reported. The chain gap
  above stays open.

- **D13 TOML is the data form, and these rules make it one.** The file
  states its `format` version and the lattice `eltype` explicitly, never
  inferred from how a number is spelled. The schema is derived from the
  element metadata and the observer, schedule and solver option schemas (D6);
  unknown keys and unknown kinds are refused by name. A knob expression is
  an inline table `{ expr = "..." }` holding the knob system's own surface
  syntax, rendered by `string(e)` and parsed by `knob_expression`, whose round
  trip is documented as total; a bare string in a numeric parameter is a
  typo the loader refuses. Knobs mirror their dotted paths as nested tables,
  `[knobs.hsr.power_supply]`, with declared types other than `Float64`
  explicit (`{ type = "Int", value = 1160 }`) and dependent knobs written as
  expressions; TOML's rule that a key cannot be both a value and a table is
  the registry's rule against a knob that is also a namespace. Stored
  parameters only: no resolved value beside an expression, since a number
  next to a formula is a stale hand copy. Bulk tables (a `TurnTable`'s
  offsets) go by reference with a SHA-256 digest, not inline. The emitter is
  deterministic: an element prints as a one-line inline table when the
  rendered line stays under a fixed width and as a `[lattices.X.elements.NAME]`
  section otherwise, all one-liners before the first section header because a
  table cannot be reopened, elements in definition order, foreign names
  quoted. The loader is self-contained: it declares the file's independent
  knobs, then the dependent ones in dependency order derived from the
  expressions, refuses a reference to a knob the file does not define,
  refuses a knob path that already exists in the process with a different
  definition rather than rewiring it, and records what it declared in a
  receipt. Parsing an expression executes nothing: `Meta.parse` yields an
  AST and the knob builder accepts only whitelisted calls, references and
  literals. Names: `write_machine(path, m)` and `read_machine(path)`
  (proposed), following `save_run_artifact`, because JLD2 exports `save` and
  `load`. Measured (section 4): the Julia 1.12.4 standard library parses
  every form the snapshot needs and its printer takes `sorted`, `by` and
  `inline_tables` keywords, so the emitter is a thin wrapper choosing the
  inline set and the key order, not a printer of its own. Rejected: JSON as
  the human-facing file (a new dependency, no comments, integer and float
  indistinguishable in most stacks; acceptable later as a mechanical
  projection of the same schema if a collaborator's tooling needs it); YAML
  (implicit typing); HDF5 or JLD2 as the human file (binary; JLD2 is
  Julia-only); Julia source as the canonical artifact (`eval`, API drift, no
  other code reads it; fine as an export for humans); an expression tree as
  nested inline tables (exact and parser-free, but TOML 1.0 keeps an inline
  table on one line); evaluating expressions at save time (loses the
  dependency structure, so a retuned knob would not propagate after a load).
  Status 2026-11-25: implemented in `src/lattice/toml.jl` (the format as the
  `write_machine` docstring, which is the one source the writer and the
  reader derive from; the element, value, line, knob, reference and lattice
  rules; the deterministic emitter) and `src/lattice/toml_hooks.jl` (the
  hooks, markers, solvers, schedules and turn rules through their option
  schemas, the tables sidecar), record
  [`../history/machine_description_stage4_2026_11_25.md`](../history/machine_description_stage4_2026_11_25.md).
  Two details the implementation settled differ from the text above and
  the docstring is the authority: every element is a
  `[lattices.X.elements.NAME]` table (no width rule and no inline form, so
  the reader needs no second shape), and the elements print in
  first-placement order with one table per DISTINCT spec object (an object
  placed twice is one table referenced twice, so the identity the family
  queries rely on survives the round trip), both confirmed by unit A's report.
  Status 2026-11-26 (R10 of
  [`machine_description_followups.md`](machine_description_followups.md),
  the compile-path batch): no include and no template in the format, by
  decision; the multi-file description is a Julia module, and the format
  gained its two readers for it, `read_lattice(path)` for a one-lattice
  snapshot and `read_machine(path1, path2, ...; name, knob_root)` assembling
  a machine from several, equal to the original with a byte-identical
  `machine_toml`.
  Status 2026-11-26 (R8d, batch B of
  [`machine_description_followups.md`](machine_description_followups.md),
  record [`../history/machine_description_param_types_2026_11_26.md`](../history/machine_description_param_types_2026_11_26.md)): the
  schema the codec derives from the metadata now carries a declared value
  class per parameter (`ParamMeta.type`, every parameter of every kind),
  so the writer and the reader coerce by it -- a `Linear6DSpec`'s optics
  tuples print as plain arrays, a value outside the class is refused by
  name on both sides -- and the marker forms stay for the keys declared
  `Any` and for files written before the types; the format stays 1.

- **D14 The run artifact embeds the snapshot.** A run records the machine it
  ran as the TOML text, so it can be reproduced from the artifact alone and
  two runs can be diffed on their lattices. This gives the two provenance
  rows of section 1 the stable identity they lack; closing them is their own
  work.
  Status 2026-11-25: implemented (the record above; `run_artifact.md`, "The
  machine snapshot"). The task structs carry the machine they were given, by
  spelling (`machine`: `Machine(lattice)` for a lattice, the machine itself
  for a machine, the derived `Machine("<name1>+<name2>")` for
  `StrongStrongTask(lattice1, lattice2)`, `nothing` for tuples, vectors and
  bare lines, or when no machine can hold the pair); `prepare_run_artifact!`
  writes `machine_toml(machine, tables)` into the ledger columns
  `machine_toml` and `machine_sha256` and the tables under
  `/machine_tables/<sha256>`; `read(out, :machine; slot)` and
  `read_machine(out; slot, receipt)` read them back. A tuple-built task's row
  holds `""` and the readers refuse by name with the lattice spelling as the
  remedy; a machine the codec refuses warns at prepare and records `""`
  rather than stopping the run, since the snapshot is the run's by-product.
  Status 2026-11-26 (R9 of
  [`machine_description_followups.md`](machine_description_followups.md),
  the compile-path batch): the text is stored once per distinct digest under
  `/machine_snapshots/<sha256>` and the row keeps `machine_sha256` only, the
  digest is taken over the text's bytes, the task caches the rendered text
  on the knob and spec epochs, and `RunArtifact(...; machine_snapshot)`
  switches the embedding (the readers refuse by name when it was off); a
  2026-11-25 file still reads and is continued.

- **D15 Compatibility is additive.** Tasks keep accepting the tuples,
  vectors and `BeamLine`s they accept today; `Lattice` joins `_element_tuple`
  (one site) and `Machine` joins the task constructors beside them. Observers
  and solvers stay where they are (D6). Flat reference keywords stay accepted
  (D12). The examples run unchanged, and the full gate enforces it through the
  example-execution testset. Converting an example to the new description is
  its own commit, verified the way the LinearOptics examples batch was: the
  converted script reproduces the flat script's output fingerprints bit for
  bit on CPU threads and within the device's run-to-run noise on CUDA
  (`../history/linear_optics_examples_2026_11_21.md`, section 2).

- **D16 Where it lives.** `src/lattice/` with `Lattice.jl`, `Machine.jl`,
  `elements_macro.jl` and `toml.jl`, one source-map bullet in `AGENTS.md`
  (the suite checks every `src/` directory has one), exports in the registry
  snapshot and routes in `public_api.md`. Not Core Objects: the Core Objects
  are categories with registry-enumerated members, and these are records,
  like `LinearOptics`; the composition note's decision 1 made the same call
  for `BeamLine`. No abstract root, no registry category.

- **D17 Translators come after, one code first, table-driven.** Reading
  another code's input is three layers: syntax, a kind-and-attribute
  translation table, and the convention conversions (RBEND length as chord,
  `tilt` against `ref_tilt`, PTC ignoring `k0`, SAD and BBSCL integrated
  strengths, deferred expressions to knobs, `at=` positions to drifts). The
  parser is the cheap third. Read machine-readable exports rather than the
  MAD-X language: a saved flattened sequence or TFS table, Xsuite's JSON
  line, Bmad through Tao or SciBmad; elegant's lattice file is simple enough
  to parse directly. One table per code, derived from the element metadata
  where possible, with a tripwire that every Octopus kind has a row that
  translates or refuses by name, unknown foreign attributes refused by name,
  and a measured test per row against the foreign code by tracking or twiss
  agreement, the external-reference contract's pattern. Writers are the easy
  direction and unify the three hand-spelled generators of section 1. Order:
  MAD-X and Xsuite, whose conversion laws the twiss benchmarks measured;
  Bmad when it is in the validation path, which also unblocks the Bmad
  reference-case row.

- **D18 Deliberately not now.** Filling patterns and bunch trains (no
  consumer until a multi-bunch task; the lattice does not change, the task
  and beam layers do, and the encounter schedule is derived from machine data
  never stored). Interaction-point geometry and collision-owned Lorentz
  boosts: the boost pair is the collision model's frame change, and with a
  tilted ring (the EIC's former tilted ESR) each beam's transformation
  differs, a roll into the common crossing plane before the half-angle boost;
  owning that at the collision would remove a silent-asymmetry failure mode
  and aligns with the BBSCL fusion lead, but it is a kernel campaign that
  needs a theory note for the tilted geometry first, and `LorentzBoostSpec`
  takes a single planar angle today. A JSON projection. Overlay files (a base
  plus a patch keyed by selector; a derived lattice plus a full snapshot gives
  the same effect with the provenance intact). The per-turn knob ramp.

## 3. Staging, tests, verification

Each implementation stage is a full-gate class (new public objects, examples
converted, the registry snapshot regenerated), run at CI settings with CUDA
active on the stage's final tree before its push, with the ledgers travelling
in the same commits (`AGENTS.md`, Definition of Done).

1. **This note.** Indexed in `../README.md`; a `../todo.md` row; markdown
   only, so the fast lane on the final tree is its gate.
2. **`Lattice`, `ReferenceParticle`, `@elements`, the knob-root check;
   `TrackingTask` accepts a lattice beside the tuple.** Tests: the macro's
   expansion fixtures and the registry-derived kind tripwire; the
   including-twice equality pin on a shipped lattice module; the knob-root
   refusal shown red; the `eltype` refusal; `_element_tuple(::Lattice)`
   equal, element for element, to the tuple the same line gives today. One
   example converted (the DBA ring or the weak-strong script, owner's
   choice) with its fingerprints reproduced. The friendly constructors'
   expression acceptance (D10) lands here or in its own batch, with the
   effectiveness contract's expression arm; the reading pass over the fold
   sites decides which.
3. **`Machine`; `StrongStrongTask` accepts a machine; the strong-strong
   example converted.** Tests: a one-lattice machine built implicitly from a
   lattice equals the explicit one; the two-lattice machine's lines reach the
   task bitwise as the two tuples do today; the strong-strong example's
   fingerprints on CPU threads, and on CUDA within run-to-run noise.
   Landed 2026-11-25, record
   [`../history/machine_description_stage3_2026_11_25.md`](../history/machine_description_stage3_2026_11_25.md)
   (the fingerprints, the tuple-versus-machine parity measurement and the
   gate are in it).
4. **The TOML writer and reader; the artifact embedding.** Tests: the
   registry-derived round trip per kind (friendly constructor to object to
   file to object, equal in every parameter, knob and placement, which also
   pins that friendly folding and flexible storage agree); every operator of
   the knob whitelist through the file and back; the loader's refusals shown
   red (unknown key, unknown kind, undefined knob, conflicting knob, a bare
   string where a number belongs); the deterministic emitter (two snapshots of
   one lattice byte-identical); the artifact's embedded text equal to the
   file's. The three hand-spelled benchmark generators are not touched here;
   D17 reads them from the snapshot later.
   Landed 2026-11-25, record
   [`../history/machine_description_stage4_2026_11_25.md`](../history/machine_description_stage4_2026_11_25.md)
   (the per-kind and per-type round-trip counts, the fingerprints and the
   gate are in it).
5. **`override` and derived lattices, then the neighbour audit** the
   invariants require after every campaign: the fix's neighbours are where
   the next defect is, and here they are `_element_tuple`'s callers, the two
   task constructors, the placement-override guards and the knob epoch.
   Landed 2026-11-25 as `with_overrides`, record
   [`../history/machine_description_stage5_2026_11_25.md`](../history/machine_description_stage5_2026_11_25.md)
   (the three testsets, the per-unit verification and the gate are in it);
   the neighbour audit's report
   [`../history/audit_machine_description_2026_11_25.md`](../history/audit_machine_description_2026_11_25.md)
   (two reading units, 18 leads: 5 findings fixed with red-first regression
   tests, 4 ledgered with their price, 1 owner item carried, the clean
   regions with their evidence). The staging is complete.

Targeted checks before each stage's gate, from the matrix: `validate_element_metadata()`
and both `element_help` forms where a kind's constructor changed;
`validate_configuration_metadata()` and the effectiveness contract where an
option was added; the extracted source sweeps (Core.Box, detached docstrings,
the pin tripwires) on any tree whose `src/` or `test/` changed, then the fast
lane, then the full gate (`../experiences.md`, "Suite source sweeps before a
gate"). No stage changes a physics result: the converted examples' fingerprints
are the receipt, and a stage that moves one has a defect, not a feature.

## 4. Measurements behind the note (2026-11-24)

- Task call sites and reference spellings: the two tables of section 1,
  counted by grep on the tree at `7b372b7`.
- Conversion and fold sites: 77 grep hits for `_fold_named_strengths`,
  `_typed_spec_params`, `_spec_params`, `_optics_tuple` and the bend's
  `angle` and `chord` folds across `src/knowledge/Knowledge.jl` and
  `src/elements/*.jl`. Three mechanisms: `_typed_spec_params` converts
  through `_as_numeric_type`, which converts floats, tuples and float arrays
  and passes any other value through, so an expression already survives the
  typed form; `_fold_named_strengths` writes `T(float(v))` into the strength
  tuples and `_sbend_params` computes `float(d[:angle]) / L`, both eager and
  both refusing an expression today through `Base.float(::AbstractKnobExpression)`;
  the typed-by-hand forms listed in `_stamp_numeric_type!`'s docstring convert
  per kind and are the stage 2 reading list for D10.
- The kind-to-constructor map the block macro needs exists:
  `ElementMeta.friendly_constructor`, declared per kind in `@element_spec`
  (`friendly_constructor = DriftSpec`; `nothing` is explicitly permitted and
  printed as "(no friendly constructor)" by the registry).
- Placement overrides merge into the spec before compile
  (`_merged_params`, `compile_runtime(::LineEntry)` in
  `src/elements/beam_line.jl`), and a knob in an override makes the compiled
  runtime knob-dependent (`_has_knob_parameters(::LineEntry)`), so D11's
  per-occurrence noise rule needs no new mechanism. Overrides of folded named
  strengths are refused by the `_FOLDED_NAMED_STRENGTHS` guard (U15-7).
- The TOML standard library of Julia 1.12.4, probed with a snapshot-shaped
  document: mixed arrays (`[0.0, { expr = "x" }]` parses to `Float64` and
  `Dict`), nested inline tables, a quoted dotted key kept whole
  (`"MQXA.1L5"`), `inf`, `-inf`, `nan` and `1_000_000`, integers distinct from
  floats (`nst = 4` an `Int`, `L = 0.35` a `Float64`), arrays of inline tables
  in a line definition. `TOML.print` takes `sorted`, `by` and `inline_tables`
  keywords (`inline_tables = IdSet{Dict}([...])` printed
  `QF = {kind = "quadrupole", kn = [0.0, {expr = "x"}], L = 0.35}` on one
  line) and prints floats in shortest round-trip form (`0.30000000000000004`,
  `1.0e-5`, `0.0125`, `1.0e22`). The default print of nested dictionaries is
  one section per dictionary in insertion order; `sorted = true` orders keys
  alphabetically. The probe is ten lines and is not committed; its results are
  this paragraph.
- The knob surface syntax: 24 whitelisted operators with arities and five
  named constants (`_KNOB_OPERATORS`, `_KNOB_NAMED_CONSTANTS`,
  `src/knobs/Knobs.jl`); the printer parenthesises same-level nesting and
  negative literals under `^`; `knob_expression(string(e)) == e` is the
  documented total round trip. The registry is not persisted with specs
  today; `knob_control.md`, section 5, lists a save and load pair as future
  work, which D13's knobs section is.

## 5. Open for the owner

- Which example converts first in stage 2: the DBA ring (`BeamLine` already,
  one beam, the Twiss analysis as a check) or the weak-strong script (the
  production shape).
- The derived-lattice verb: `override` or `with_overrides`.
- The knob-root convention for the shipped lattice modules (`esr`, `hsr`,
  `ip` as `examples/knob_control.jl` uses it).
- Whether `Lattice`'s `eltype` check exempts kinds that store no numeric
  type (markers, apertures), or requires them untyped.
- Whether the expression acceptance of D10 is stage 2's batch or its own.

Decided 2026-11-24 (owner), the questions kept above as asked: the first
example converted is the DBA ring (`examples/twiss_dispersion_dba_ring.jl`);
the derived-lattice verb is `with_overrides`; the knob root of the shipped
lattice modules is `ring`; the `eltype` check accepts an element built by an
untyped friendly constructor when the promotion of its stored numeric
parameters over `eltype` is `eltype` itself, so a kind storing no numeric
value passes and a wider literal is refused with the typed-form remedy, while
a stored `numeric_type` must equal `eltype`; the expression acceptance of D10
is stage 2's batch.

Decided 2026-11-26 (owner), on the items the stage records carried and on
the data form's questions, recorded with their reasoning, acceptance and
prices in [`machine_description_followups.md`](machine_description_followups.md):
no beam definitions on the machine (R1); a collision marker outside a
strong-strong task inert and counted, never an error (R2); `r0` derived
from a richer, immutable `ReferenceParticle` with required inputs, species
presets and knob-expression inputs, and retired as a `Beam` input (R3,
R4); the zero factors of the derived kick scale refused at the preflight
and the scale reported, `npart` warn or refuse the owner's last choice
(R5); a wider-than-`Float64` override refused, the `Float64`-to-`Float32`
convention kept (R6); a ramp as a knob on the reference, its campaign
after a theory note (R7); the four priced leads dispositioned (R8); the
artifact's snapshot content-addressed, cached and switchable by
`machine_snapshot` (R9); no include and no templates in the TOML,
`read_lattice` and the multi-file `read_machine` added (R10); the MAD-X
class form on the friendly constructors (R11); a library as a Julia module
(R12). The compile-path half of D12 is that note's batch A.

## 6. Precedents read for this design

MAD-X (sequences, `:=` deferred expressions, `save, sequence`), Bmad (the
lattice language, branches, `geometry`, `p0c` bookkeeping, `call, file`),
Xsuite (`Environment`, `Line`, xdeps expressions, the JSON dictionary dump
with element definitions separate from the ordered name list), elegant, SAD,
Accelerator Toolbox, SciBmad's Julia port (`@ele` and `@eles` naming elements
from bindings, as far as the author knows), and the AML/UAP interchange
effort. Outside the field: infrastructure as code moving from raw JSON and
YAML to languages that synthesise canonical data; glTF as JSON done well
(schema, version, required extensions a reader must refuse, binary sidecar);
SBML and FMI, where the conformance suite defines the format; SPICE netlists
and MAD8's SIF outliving the universal formats; Bazel's Starlark restricting a
real language to deterministic declarations.
