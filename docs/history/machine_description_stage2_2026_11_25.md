# The machine description, stage 2: `Lattice`, `ReferenceParticle`, `@elements`, the friendly constructors accepting knob expressions (2026-11-25)

Stage 2 of the staging in [`../design/machine_description.md`](../design/machine_description.md)
(section 3; decisions D3, D7, D9, D10, D12, D15, D16), built on the line layer
of [`../theory/beam_line_composition.md`](../theory/beam_line_composition.md)
and the knob system of [`../knob_control.md`](../knob_control.md). Guides:
`../guides/development_workflow.md`, `../guides/elements.md`,
`../guides/examples_and_validation.md`, `../guides/documentation.md`. Branch
`md2`: skeleton 8317314, unit B 92c8d07, unit A bd99533 (merged 0adba7a),
unit C fe6d462 (merged db07e62); the example, the review fixes and this
record are the commits that follow them on `main`, written from the gate log.

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
  refuses a kind without a friendly constructor by name". Unit C (2 testsets, 156 assertions): "... the friendly constructors
  accept knob expressions (D10)" (126), "... the effectiveness contract's
  expression arm" (30, with the ratchet `expression_checked >= 347`; behind
  `_lane_gate`, since it runs the whole contract, about 100 s). The neighbour "BeamLine composes, addresses
  and tracks" is untouched (43 of 43).
- D10, the friendly constructors accepting knob expressions (unit C):
  `_fold_named_strengths` keeps an expression in the `kn`/`ks` tuples, the
  bend's `angle / L` becomes an expression node when an operand is one, the
  typed-by-hand forms convert a number and keep an expression; a derivation
  the tree cannot express refuses by name with the remedy; an expression arm
  of `ElementParameterEffectivenessContract` under new metric keys. Sites
  changed: `lattice_magnets.jl` (the `kn`/`ks` fold with `k0`..`k5` and the
  skews; the sbend's `h = b0 = angle / L`; the RBend's half angle, `e1`, `e2`,
  and `chord` with a numeric angle), `linear_maps.jl` (`zeta1..4`, `eta1..4`,
  `r1..4`), `chromaticity_kick.jl` (`xi`, `beta`, `alpha`, `zeta`, `eta`, `R`),
  `radiation.jl` (`damping_turns`, `beta`, `alpha`, `sigma`, `zeta`, `eta`, `R`),
  `crab_cavity.jl` (the positional `frequency`, `strengthX`, `strengthY`,
  `phase`), `linear6d.jl` (the 36 matrix entries, `beta1`, `beta2`, `alpha1`,
  `alpha2`, `dmu`, `zeta`, `eta`, `R1`, `R2`; the symplectic and block checks
  run at compile, which re-checks the resolved matrix), `lorentz_boost.jl`
  (`angle`, both kinds), `strong_beam.jl` (`kbb`, `klum`, `center`, the
  transverse `angle` and `curvature`, `sigz`, the slice tables),
  `rf_cavity.jl` (`frequency`, `strength`, `phase`, `L`, `beta0`, `gamma0`;
  the `voltage`/`e0`/`mc2` derivation as trees of `sqrt`, `/`, `*`, `-`, `+`);
  the solenoid needed no change. Helpers: `_as_number_or_expression` and
  `_float_or_expression` (`Knowledge.jl`), `_knob_node` and `_knob_arith`
  (`Knobs.jl`, whitelisted nodes with constant folding). Also in `Knobs.jl`: a
  nested `ElementSpec` (the Gaussian strong beam's `thin` kernel) now resolves
  with its parent through `_resolve_knob_param` and `_param_has_knob`, with
  its own receipt; before, a knob inside the kernel was invisible to
  `resolve_knobs` and to the recompile gate. The refusals that remain, each by
  name with a remedy: the RBend `chord` with an expression `angle` (the
  zero-angle guard has no tree; a plain tree gave `L = NaN` at a knob angle of
  0 and compiled to NaN coordinates); the strong beams' `beta`, `alpha`,
  `sigma`, coupling and covariance (derived and validated at construction;
  remedy: the flexible `ElementSpec{:thin_strong_beam}` with the knob in a
  covariance entry, verified to compile, also as `thin=`); the inert
  `angle[3]`, `curvature[3]`, `mean[6]`; the Gaussian `sigz`/`sigma_delta`
  beside a dispersive `LinearOptics` point; the RF `harmon`; `LinearOptics`
  (`beta`, `alpha`, `R`, `zeta`, `eta`, `mu`, `dmu`), on the measurement
  section 3 reports. The fix round added: the arm's refusal classifier treats
  the generic eager-conversion error as unnamed and requires the parameter's
  name and a remedy (a site never widened cannot pass as refused by name);
  the compile-side re-checks of section 4; the lane gate on the arm's
  testset; `_knob_node` folding only a `Float64`-exact literal (a BigFloat or
  rational operand beside an expression is refused by name, where it was
  narrowed silently); a bare `kn = @knob_expr(...)` wrapped as a one-tuple
  like a bare number; and the committing of the measuring harness
  `machine_description_stage2_2026_11_25_optics_trees.jl` beside this record
  (its output is the source of the `LinearOptics` numbers below).
- `examples/twiss_dispersion_dba_ring.jl` (unit E): the hand-written element
  block became `module DBARing` (declarations only: `using ..Octopus`, the
  `config` of the parent module, `ReferenceParticle(; charge = 1, mc2 =
  PMASS_EV, E0 = config.energy_ev)` with `beta0, gamma0 =
  reference_beta_gamma(reference)` where the script derived them by hand,
  `@knob ring.qf_k1 = 1.5`, the optional crab cavity as a tuple child, and
  the `@elements` block `QD`, `QF` with `k1 = @knob_expr(ring.qf_k1)` (D10),
  `D`, `BEND`, `RF`, `DBA_RING = line(QD, D, BEND, D, QF, D, BEND, D, QD, RF,
  CRAB)`, then `const lattice = Lattice("DBA_RING"; line = DBA_RING,
  reference, knob_root = :ring)`), the top-level `lattice = DBARing.lattice`
  fed to both `analyze` calls, and exactly one printed line added before run
  1, `Lattice: Lattice("DBA_RING": 10 placements, 5.25 m, Float64, reference
  ReferenceParticle(charge = 1.0, mc2 = 9.3827208943e8 eV, E0 = 3.0e9 eV),
  knob roots (ring,))`; every element value, `nst`, `integrator_order` and
  cavity keyword unchanged, the header rewritten (the module is the precedent
  for a lattice module: declarations only, including it twice builds an equal
  lattice). Its catalogue entry in `src/examples/Examples.jl` describes the
  module and lists `Lattice` and `ReferenceParticle` beside
  `TwissDispersionAnalysis`, `BeamLine`, `ThinRFCavitySpec`, `SBendSpec` and
  `LinearOptics` (the catalogue tripwire reads each name in the script's text;
  the three kept names are in its comments). The suite pins the module's
  declarative equality: "Machine description: the shipped DBA lattice module
  builds an equal lattice when included twice" (13 assertions: two sandbox
  includes `==` with equal `hash`, not `===`, roots `(:ring,)`, the
  reference, the knob expression on `QF`'s `kn[2]` printing as `ring.qf_k1`;
  a hand-built lattice with `k1 = 1.6` is not `==`).
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
- The adversarial reviews of the three units (2026-11-24, read-only agents
  over the diffs; their findings are under the stage's scratch and summarised
  here) led to a fix round on the merged tree. Unit A: the numeric-type
  tripwire is the compile's own answer and not a re-derivation (it folded the
  promotion from the lattice's type where `numeric_type(spec)` folds from the
  Float64 floor, so a Float32 lattice accepted an untyped marker that
  compiled in Float64 and refused the Float32 beam at `execute!`); the rule
  is now: a stored `numeric_type` must be the lattice's, an untyped element
  passes when `numeric_type(spec)` is the lattice's, a kept-whole line when
  the misalignment wrap's `_wrap_numeric_type` is (its members' type when the
  line's own parameters promote to the Float64 floor), and the top-level
  line's own parameters count only when it has state of its own. Consequence
  for a Float32 lattice: every element is built typed, the marker included,
  which the `@elements Float32` header does. Enums compare by value in the
  structural equality (an `@enum` has no fields, so `XY_MODEA` and `XY_MODEB`
  compared equal); the wiring walker sees a knob inside a `NamedTuple` and
  inside a nested `ElementSpec` (the Gaussian strong beam's `thin` kernel),
  which `knob_report` and the knob-root tripwire had both missed; `eltype`
  must be concrete; the remedy spells the keyword route `numeric_type = T`
  (the `{T}` form is wrong for `ThinCrabCavitySpec{N,T}`); `StrongStrongTask`
  accepts lattices through the same `_element_tuple` site and the docstring
  says so, pinned; `show` prints "length pending" for a lattice whose length
  sits on an unassigned knob; knob roots are dotted Julia identifiers and
  never a reserved constant name. Unit B: a registered kind name called at a
  position the block does not rewrite (a keyword value, a function body, a
  `repeat` call, a tuple assignment) is refused at expansion by name with the
  remedy, where it used to fail at run time with `UndefVarError`; tuple and
  vector children of a kind call are rewritten; a nameless `line(...)` is
  labelled `line` (an empty name made an empty path segment, `N//QF`); the
  `:line` skip of the registry-derived testset is a visible `@test_skip`.
  Unit C: see section 4 for the compile-side re-checks the review widened.
- Owner, 2026-11-24, on the note's section 5: the DBA ring converts first;
  the derived-lattice verb is `with_overrides` (stage 5); the knob root of
  the shipped modules is `ring`; the `eltype` rule of section 1; D10 is in
  stage 2.

## 3 Verification

- Extracted per unit, in package mode (`test/run_extracted_testsets.jl`, one
  process per batch): unit A's five testsets, 91 of 91; unit B's four, 216 of
  216; "BeamLine composes, addresses and tracks", 43 of 43; unit C's two,
  95 of 95 and 27 of 27, with the neighbours "Element parameter
  effectiveness" 80 of 80, "Thin elements, markers and RBEND" 114 of 114
  and "Lattice magnets" 83 of 83; unit E's testset 13 of 13, with "the Example core object answers with real
  scripts" 54 of 54 and "Stage 5: every kind that declares the analysis
  analyzes its own example, or refuses it for the documented reason" 64 of
  64; the script itself exit 0 as the suite's example testset runs it (run 1
  degraded, run 2 passed, 57 printed lines against 56).
- The DBA example's fingerprints (SHA-256 of the printed text, the tunes,
  zeta/eta/h, the `LinearOptics` point, the matched sizes, the residuals and
  the one-turn matrix), pre-change on main 2bfab81
  (`result/gates/md2/compare/fingerprints_pre.txt`: run 1 degraded, run 2
  passed, 56 printed lines) against the converted script:

  | quantity | pre (2bfab81) | post |
  |---|---|---|
  | printed text | `4650bb429bc87344` | `13aaab6156c61f4d` (the one added line; the text diff is exactly it) |
  | tunes | `e8ac2169212395e1` | `e8ac2169212395e1`, identical |
  | zeta, eta, h | `80a1e9e1190d98d6` | `80a1e9e1190d98d6`, identical |
  | `LinearOptics` point | `04d44e115496f7b6` | `04d44e115496f7b6`, identical |
  | matched sizes | `5703fdf7c53edea7` | `5703fdf7c53edea7`, identical |
  | residuals | `a1fa16d46cf61e76` | `a1fa16d46cf61e76`, identical |
  | one-turn matrix | `b2cebc5ce8cc7713` | `b2cebc5ce8cc7713`, identical after the provenance fix below |

  The first post-conversion run moved the one-turn-matrix hash alone
  (`22ac21ab00e027db`): the matrix was bitwise the line's, and the
  `LinearizedMap` provenance read `source_kind = :callable`, `source =
  "Lattice"`, because `_linearizable(::Lattice)` forwarded to the line while
  `_describe_map` and `_source_kind` did not. Both now forward (the
  provenance of a lattice is its line's, `:element_spec` and the line's
  name), unit A's wrap testset pins it, and the second run reproduced the
  baseline. The driver is `result/gates/md2/compare/fingerprint_dba.jl`'s
  twin kept under `/tmp` during the stage; its seven quantities and the
  hashing rule (every number as a Float64 payload in field order, strings as
  their bytes) are the LinearOptics record's.

  The CUDA clause of D15 (agreement within the device's run-to-run noise)
  does not apply to this stage's example: the DBA script runs an analysis on
  the CPU and has no CUDA path.
- The validators, in one package-mode process on the merged tree (the
  extracted-checks log, 2026-11-24 21:56 EST): `validate_element_metadata()`
  passed (613 default pairs checked, 34 runtime variants),
  `validate_configuration_metadata()` true, the regenerated snapshot equal
  to the committed one; re-run after the fix round (the metadata re-check of
  2026-11-24 23:25 EST): passed with 614 of 614 default pairs (the line's
  `numeric_type` added one), 34 of 34 runtime variants, both `element_help`
  forms rendered for all 32 kinds, the snapshot equal, the configuration
  metadata true; `validate(ElementParameterEffectivenessContract())` with the
  expression arm: passed on unit C's tree in 80 s (40 s before the arm; the
  suite calls it about six times), the numeric metrics unchanged (checked
  555, unperturbable 35, rejected 32, skipped 0; the suite's pins on
  `checked` untouched) and the new keys `expression_checked = 347` over 30
  kinds, `expression_refused = []`, `expression_failures = []`,
  `kinds_without_candidates = [marker, phase_space_reset]` (no numeric
  parameter to put a knob on), `expression_inapplicable`: 26 integer or flag,
  28 not a float or float tuple, 16 inactive, 1 carried. The `LinearOptics`
  measurement of D10: one knob in `beta[1]` gives 4 of the 36 matrix entries
  as trees of 6 nodes (24 nodes; the trees evaluate to the numeric build;
  `knob_value` over the 36 entries 4.75 us against 0.06 us for the numeric
  build on the committed harness's run, 78.5x; the implementer's probe had
  measured 66.6x on a loaded machine), one knob in `R` gives an Edwards-Teng
  block of (11, 12, 12, 11) = 46 nodes (the probe's 50 counted a spurious
  unary plus; the normalizer lambda alone is 9); both bounds of the stage's
  decision rule (a mean tree above 8 nodes, or an evaluation above 10 times
  the numeric build) are exceeded, so `LinearOptics` refuses an expression by
  name with these numbers in its docstring. The harness:
  `julia --project=. docs/history/machine_description_stage2_2026_11_25_optics_trees.jl`.
- The extracted source sweeps on the merged tree after the fix round
  (integration run 3, 2026-11-24 23:17 to 23:22 EST, logs under
  `result/gates/md2/`): "Every export is documented" 1 of 1, "No docstring is
  detached by comment lines" 11 of 11, "No method grows a Core.Box outside
  the argued allowlist" 5 of 5, "Every exported API name appears in the
  registry snapshot" 17 of 17; "Architecture integrity" errored there on the
  line kind's construction help not yet naming `numeric_type`, fixed and
  re-checked by the metadata re-run above and green in the fast lane below.
  The stage's fourteen testsets extracted in the same run: ReferenceParticle
  20, the wrap 41, the knob-root tripwire 13, the numeric-type tripwire 29,
  equality 24, the DBA module 13, the macro's four 42 / 26 / 159 (plus the
  labelled `:line` skip) / 6, the tuple-and-vector children 5, D10 126, the
  arm 30; the neighbours "BeamLine composes, addresses and tracks" 43,
  "Element parameter effectiveness" 80, "Thin elements, markers and RBEND"
  114, "Lattice magnets" 83, the catalogue tripwire 54 and the Stage 5
  analysis tripwire 64.
- The fast lane, then the full gate at CI settings with CUDA active, on the
  merged tree: [MEASURE: gate: lane, testsets, assertions, skips, wall
  clock, the commit that carried it].

## 4 Findings of the fix round: closed, and carried

A knob-given value reached the compile without the refusals its numeric
twin meets at construction (unit C's probes, confirmed and widened by the
review): `thin_rf_cavity` did not re-check `frequency > 0` nor the
`beta0`/`gamma0` consistency (a knob of -1 Hz and a knob `beta0 = 1.5`
compiled and tracked); `thin_accelerating_cavity` with a decelerating knob
strength of -1 died at compile with a bare `DomainError` and one of -5
COMPILED AND TRACKED with an exit gamma below -1; an `sbend` whose knob `L`
resolved to 0 compiled `h = Inf` and tracked NaN. Closed in the stage by
compile-side re-checks, one site each, covering the knob route and the
flexible form alike: `_check_cavity_at_compile` in both cavity compile
constructors (frequency positive and finite, `gamma0 >= 1`, the pair
residual within `1e-10 + 4 eps (1 + 1/(beta0 gamma0)^2)` with `eps` the
coarser of the stored pair's rounding unit and `eps(T)`, so an untyped cavity
built from Float32 inputs keeps compiling; the accelerating cavity also
refuses a design gain to or below the rest energy by name), and the magnet
compile refusing a non-finite `h` or `b0` by name. Each shown red on resolved
knob values and through the flexible form with a literal; the pre-grep of
`test/`, `validation/` and `examples/` found no existing construction the new
refusals meet; the first fast lane then found the one no grep could: the
suite's derivative sweep "Element parameters carry their own number type"
stepped a cavity's `beta0` alone through the flexible form (a complex-step
seed inside a closure, no literal to grep), which the compile now refuses as
the friendly constructor does; the sweep moves the pair along its manifold
(gamma0 the variable, beta0 derived from it, the joint move of the
effectiveness contract), its verified count of 29 unchanged. Carried to
`todo.md` for the stage-5 neighbour audit: a knob
`e0` resolving below `mc2` dies in the derived tree's `sqrt` at resolve with
a bare `DomainError` (the by-name check sits after the resolution; a guarded
tree would change the pinned tree text); and, pre-existing, the flexible
`ElementSpec{:thin_strong_beam}` form requires every kernel parameter spelled
out (`KeyError: :center`) and `virtual_drift` as an object (the `:hirata`
symbol is a `MethodError`), the F-93 class. Also found and fixed on the way:
the `:line` kind never declared `numeric_type` although the misalignment
wrap reads it, so following the lattice's remedy `BeamLine(...; numeric_type
= T)` warned "unknown parameter ... stored as descriptive metadata only", a
warning that lied; the parameter is declared from the placement table, with
an inactive-table entry for the effectiveness contract (with Float64 members
the wrap promotes to Float64 whatever the line stores).

## 5 Ledger

`README.md`: this record indexed; the design entry says stage 2 is
implemented. `todo.md`: the machine-description row (stage 2 implemented,
the owner's rulings, the deliverables; stages 3 to 5 not started).
`registry_snapshot.md`: regenerated at the fold (71 lines replaced against
`main`: the Exported API index regrouped around `Lattice`,
`ReferenceParticle`, `@elements` and `@element`, and the DBA example's
Objects line gaining `Lattice` and `ReferenceParticle`).
`design/machine_description.md`: the banner, D9, D11, section 5.
`knob_control.md`: section 2's first consequence. `experiences.md`:
one lesson, "A new input type at an entry point is a method on every
helper that dispatches on the old ones" (the provenance describers the
`_linearizable` forward left behind, and the tripwire that re-derived the
compile rule).
