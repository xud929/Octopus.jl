# The machine description, stage 2: `Lattice`, `ReferenceParticle`, `@elements`, the friendly constructors accepting knob expressions (2026-11-25)

Stage 2 of the staging in [`../design/machine_description.md`](../design/machine_description.md)
(section 3; decisions D3, D7, D9, D10, D12, D15, D16), built on the line layer
of [`../theory/beam_line_composition.md`](../theory/beam_line_composition.md)
and the knob system of [`../knob_control.md`](../knob_control.md). Guides:
`../guides/development_workflow.md`, `../guides/elements.md`,
`../guides/examples_and_validation.md`, `../guides/documentation.md`. Branch
`md2`: skeleton 8317314, unit B 92c8d07, unit A bd99533 (merged 0adba7a),
[MEASURE: unit C, unit E and the fold commits].

## 1 What landed

- `src/lattice/Lattice.jl`: `ReferenceParticle(; charge, mc2, E0 | p0c)`, three
  `Float64` fields (`charge`, `mc2`, `E0`; `p0c` gives `E0 = sqrt(p0c^2 +
  mc2^2)`), refused by name for a non-finite or zero charge, a non-positive
  `mc2`, both or neither of `E0` and `p0c`, an `E0` not above `mc2`;
  `reference_beta_gamma`, `reference_beta`, `reference_gamma` methods on it.
  `Lattice(name; line, reference=nothing, knob_root=nothing, eltype=Float64)`,
  a record (not a Core Object, D16) around a top-level `BeamLine`, with two
  construction tripwires: the knob roots (every knob the line's expressions
  depend on, transitively and through placement overrides, under a declared
  root; no root declared and a dependency found is refused naming the remedy)
  and the numeric type (a stored `numeric_type` must equal `eltype`; an
  untyped element passes when the promotion of its stored numeric parameters
  over `eltype` is `eltype`, so a kind with no numeric value passes and a wider
  literal is refused with the typed-form remedy, the owner's ruling of
  2026-11-24). Structural `==` and `hash` on `Lattice` only; `show`;
  `line_entries`, `s_positions`, `find_entries`, `knob_report` forwarded to
  the line; `eltype(lattice)`.
- `src/lattice/elements_macro.jl`: `@elements T begin ... end`, `@elements
  begin ... end` (`T = Float64`) and `@element`. A call whose head is a
  registered kind maps onto that kind's friendly constructor with `name =
  "<binding>"` (an explicit `name =` wins) and `numeric_type = T` (every kind
  routes it to its typed form; an explicit `numeric_type =` wins); `line(...)`
  becomes `BeamLine(name, children...; kws...)` with no numeric type; a head
  that is not a kind passes through untouched; a kind without a friendly
  constructor is refused at expansion by name with the flexible-form remedy;
  positional arguments pass in place; `const`, docstring and bare-call
  statements handled. Measured by unit B: 32 registered kinds, all with
  friendly constructors, all expand; 31 build from their own example
  parameters through the keyword route (`:line` is covered by the DBA build
  test).
- Two forwarding methods, one each: `_element_tuple(::Lattice)` in
  `src/tasks/Tasks.jl` (so `TrackingTask(lattice; ...)`) and
  `_linearizable(::Lattice)` in `src/analysis/one_turn_matrix.jl` (so
  `analyze(analysis, lattice)` and `one_turn_matrix(lattice)`); both see
  exactly the placements the bare line gives (bitwise-identical tracking,
  pinned by unit A).
- `AGENTS.md`: the `src/lattice/` source-map bullet (the suite checks that
  every `src/` directory has one).
- The suite, under the anchors `# [MD2-A]`, `# [MD2-B]`, `# [MD2-C]` in
  `test/runtests.jl`. Unit A (5 testsets, 91 assertions): "Machine
  description: ReferenceParticle builds from E0 or p0c and refuses by name",
  "... a Lattice wraps a line and is accepted where the line is", "... the
  knob-root tripwire refuses a dependency outside the declared roots", "...
  the numeric-type tripwire follows the compile rule", "... lattice equality
  is structural and the record prints". Unit B (4 testsets, 216 assertions):
  "... @elements expands kind calls onto the friendly constructors", "... the
  @elements block builds the hand-written lattice", "... every registered
  kind expands through @elements, derived from the registry", "... @elements
  refuses a kind without a friendly constructor by name". Unit C: [MEASURE:
  unit C testsets and counts]. The neighbour "BeamLine composes, addresses
  and tracks" is untouched (43 of 43).
- D10, the friendly constructors accepting knob expressions (unit C):
  `_fold_named_strengths` keeps an expression in the `kn`/`ks` tuples, the
  bend's `angle / L` becomes an expression node when an operand is one, the
  typed-by-hand forms convert a number and keep an expression; a derivation
  the tree cannot express refuses by name with the remedy; an expression arm
  of `ElementParameterEffectivenessContract` under new metric keys. Sites
  changed and the refusals that remain: [MEASURE: unit C sites].
- `examples/twiss_dispersion_dba_ring.jl` (unit E): the ring declared in a
  module through `@elements`, a `ReferenceParticle`, a knob under the root
  `ring` and a `Lattice` fed to `analyze` [MEASURE: unit E: what the script
  declares and prints]; its catalogue entry in `src/examples/Examples.jl`
  lists the new objects [MEASURE: unit E catalogue words].
- Docs: `public_api.md` ("Describe A Lattice"), `knob_control.md` section 2
  (the flexible form is no longer required), the design note's banner, D9,
  D11 and section 5, `README.md`, `todo.md`, this record.

## 2 Decisions taken in the stage

- `analyze(analysis, lattice)` goes through `_linearizable(::Lattice)`, one
  method, so the example feeds the lattice to the analysis the way a task
  takes it through `_element_tuple(::Lattice)`.
- The macro uses the `numeric_type = T` keyword route, not the `{T}`
  parameter of D9 (iii): `ThinCrabCavitySpec{N}` carries the cavity count
  first and cannot take a numeric `{T}` uniformly.
- Structural equality lives on `Lattice` only; `ElementSpec` and `LineEntry`
  keep identity `==`, which `find_entries`, `unique` and `e.spec === qf`
  rely on.
- Unit A: a stored numeric type on a typed element wins over a `Float64`
  override (the tripwire reads the stored `numeric_type`); a kept-whole
  nested line's members report at their own provenance path.
- Unit B: an explicit `numeric_type =` on one call wins over the header, as
  an explicit `name =` does; a nested kind call (`line(quadrupole(...))`) is
  rewritten nameless; `@element` refuses a `begin ... end` block by name.
- Owner, 2026-11-24, on the note's section 5: the DBA ring converts first;
  the derived-lattice verb is `with_overrides` (stage 5); the knob root of
  the shipped modules is `ring`; the `eltype` rule of section 1; D10 is in
  stage 2.

## 3 Verification

- Extracted per unit, in package mode (`test/run_extracted_testsets.jl`, one
  process per batch): unit A's five testsets, 91 of 91; unit B's four, 216 of
  216; "BeamLine composes, addresses and tracks", 43 of 43; unit C [MEASURE:
  unit C extracted counts]; unit E [MEASURE: unit E extracted testsets].
- The DBA example's fingerprints (SHA-256 of the printed text, the tunes,
  zeta/eta/h, the `LinearOptics` point, the matched sizes, the residuals and
  the one-turn matrix), pre-change on main 2bfab81
  (`result/gates/md2/compare/fingerprints_pre.txt`: run 1 degraded, run 2
  passed, 56 printed lines) against the converted script:

  | quantity | pre (2bfab81) | post |
  |---|---|---|
  | printed text | `4650bb429bc87344` | [MEASURE: unit E post] |
  | tunes | `e8ac2169212395e1` | [MEASURE: unit E post] |
  | zeta, eta, h | `80a1e9e1190d98d6` | [MEASURE: unit E post] |
  | `LinearOptics` point | `04d44e115496f7b6` | [MEASURE: unit E post] |
  | matched sizes | `5703fdf7c53edea7` | [MEASURE: unit E post] |
  | residuals | `a1fa16d46cf61e76` | [MEASURE: unit E post] |
  | one-turn matrix | `b2cebc5ce8cc7713` | [MEASURE: unit E post] |

  The CUDA clause of D15 (agreement within the device's run-to-run noise)
  does not apply to this stage's example: the DBA script runs an analysis on
  the CPU and has no CUDA path.
- The validators: `validate_element_metadata()` [MEASURE: validators], both
  `element_help` forms for the kinds whose constructors changed [MEASURE:
  validators], `validate(ElementParameterEffectivenessContract())` with the
  expression arm [MEASURE: unit C contract].
- The extracted source sweeps on the merged tree ("Every export is
  documented", "No docstring is detached by comment lines", "No method grows
  a Core.Box outside the argued allowlist", "Architecture integrity"):
  [MEASURE: sweeps].
- The fast lane, then the full gate at CI settings with CUDA active, on the
  merged tree: [MEASURE: gate: lane, testsets, assertions, skips, wall
  clock, the commit that carried it].

## 4 Ledger

`README.md`: this record indexed; the design entry says stage 2 is
implemented. `todo.md`: the machine-description row (stage 2 implemented,
the owner's rulings, the deliverables; stages 3 to 5 not started).
`registry_snapshot.md`: regenerated at the fold for `Lattice`,
`ReferenceParticle`, `@elements`, `@element` [MEASURE: snapshot lines].
`design/machine_description.md`: the banner, D9, D11, section 5.
`knob_control.md`: section 2's first consequence. `experiences.md`:
[MEASURE: a lesson or none, the orchestrator's call].
