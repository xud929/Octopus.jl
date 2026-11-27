# The machine description after the staging: the owner's rulings of 2026-11-26 and the agreed batches

> **Status: agreed 2026-11-26 in owner discussion, the day after the staging
> of [`machine_description.md`](machine_description.md) completed (stage 5
> pushed as `f877ac1`; CI run 493 green). Nothing in this note is
> implemented. It records the rulings the discussion reached on the items
> the stage records carried and on the owner's questions about the data
> form, the batches those rulings add up to, and the measurements behind
> them, so that the next session starts at section 3 without re-deriving
> the discussion. The owning notes carry a dated line pointing here. The
> "(proposed)" wording below is the state on 2026-11-26; each ruling gains a
> dated `Status` line when it lands.** Parent notes:
> [`machine_description.md`](machine_description.md) (D5, D12, D13, D14,
> D17, D18 and section 3's staging, all landed),
> [`survey_and_reference_channel.md`](survey_and_reference_channel.md)
> (sections 5 and 6: the reference is bookkeeping derived at compile, a ramp
> is a control knob), [`run_artifact.md`](run_artifact.md) ("The machine
> snapshot"), [`../knob_control.md`](../knob_control.md) (expression trees,
> the whitelisted grammar). Records the rulings close:
> [`../history/machine_description_stage5_2026_11_25.md`](../history/machine_description_stage5_2026_11_25.md)
> section 4 and
> [`../history/audit_machine_description_2026_11_25.md`](../history/audit_machine_description_2026_11_25.md)
> section 6 (the carried items by id: B-1b, B-6a, B-11, C-3, C-5, C-6).

> **Status 2026-11-26, later the same day: batch A, "compile-path, part 1",
> is implemented and recorded in [`../history/machine_description_compile_path1_2026_11_26.md`](../history/machine_description_compile_path1_2026_11_26.md)
> with its scoped neighbour audit [`../history/audit_machine_description_compile_path1_2026_11_26.md`](../history/audit_machine_description_compile_path1_2026_11_26.md);
> the owner's choices of section 5 are resolved there (and under each item
> below); each ruling's dated `Status` line says what landed and where it
> departed from the text; batches B and C remain, B first.**

## 1. What was open, and what this note does with it

When `f877ac1` was pushed, the machine description's staging was complete
and the records carried: four priced leads (B-1b, the collision marker in a
single-beam line; B-6a, the snapshot reader not re-claiming an explicit
stream id; C-3, 416 bytes per `execute!`; C-6, the snapshot's marker forms
and `EveryNSteps`'s `stop`), two owner items (C-5, the derived kick scale
silently zero; B-11, a wider-than-type override narrowed silently), D5's
question whether the machine holds beam definitions, and the compile-path
half of D12. The owner then asked four further questions: the cost and size
of the snapshot embedded in the run artifact, whether TOML can include other
files, how several files organise into a module, and whether an element can
serve as a template (MAD-X's `QF: Q, K1=1.0`) with a library reused across
machines (the EIC built on a RHIC library).

Section 2 records one ruling per item, R1 to R12. For each: **Decision** is
the ruling in the owner's words where they were short enough to quote;
**Why** is the reasoning the owner accepted, in two or three sentences;
**Lands in** names the code; **Acceptance** is the test the implementer
owes; **Price** is the estimate given in the discussion, to be re-measured
against the diff. Section 3 orders the rulings into batches. Section 4
holds the measurements. Section 5 lists the choices that are still the
owner's, each with a default the implementer takes if no answer arrives.

## 2. Rulings

### R1 The machine holds no beam definitions

- **Decision** (owner: "my answer is no"): `Machine` stores lattices and
  shared knob roots, nothing else. The "beam definitions" and
  "machine-level reference particles" D5 lists are struck; each `Lattice`
  carries its entrance `ReferenceParticle` (D3). The D5 question the stage-3
  and stage-4 records carried is closed.
- **Why.** A machine describes the facility; a beam describes a run.
  Emittances, bunch length, intensity and the macro-particle count are what
  a study scans, like `turns`, and belong to the script and the task. A
  machine-level beam with its own energy and charge would be a second copy
  of the reference, one more place to disagree with the lattice's, while the
  D12 chain gap (no task compares a beam's reference with a cavity's stored
  pair) is still open. A beam block in the snapshot would be configuration
  nothing reads until a task consumes it, which the invariants count as a
  defect. Precedents: Xsuite's `Environment` carries a reference particle per
  line and no beam sizes; Bmad's lattice holds the reference and a start
  particle; MAD-X's `BEAM` is the exception nobody has wanted to reproduce.
- **Consequence.** If the motive was reproducing a run from its artifact
  alone, the home is the run artifact beside the embedded machine: a beam
  receipt (charge, energy, sizes, intensity, macro-particle count) read next
  to `read(out, :machine)`. Unmeasured, a lead; deferred (section 3).
- **Lands in:** the design note's D5 status line (done with this note).
  Nothing in code.
- **Status 2026-11-26 (batch A):** nothing to land in code, as decided; `Machine` holds lattices and shared roots only, and D5's status line carries the ruling.

### R2 A collision marker outside a strong-strong task is inert, counted, never an error

- **Decision** (owner: "A collision does make no sense in tracking task.
  However, if we have defined a Lattice with a collision marker, sometimes
  we may want to track it without beam-beam. ... I prefer not to raise an
  error, but no impact on tracking or analysis"): a `StrongStrongCollision`
  in a line handed to `TrackingTask`, `one_turn_matrix` or `analyze` appends
  nothing and changes nothing. The lattice tracks bitwise as the same lattice
  without the marker and its one-turn matrix is the same matrix. The task's
  binding receipt gains `collision_markers = n`, shown by
  `configuration_report(task)`; no warning and no `@info` per construction
  (agreed: none). The docstrings of `TrackingTask` and
  `StrongStrongCollision` state that the marker is inert outside a
  strong-strong task. The audit's B-1b closes by this, not by the by-name
  refusal it priced.
- **Why.** One lattice of record then serves the strong-strong machine,
  weak-strong tracking (a `GaussianStrongBeamSpec` placed at the IP beside
  the inert marker) and the analyses. The mirror risk, a strong-strong
  lattice run single-beam with no beam-beam and nobody noticing, is answered
  by the receipt and the docstrings: "documented as inert" plus "assert what
  the run recorded".
- **Today.** `_runtime_or_existing(element) = element`
  (`src/tasks/Tasks.jl:2012`) pushes the marker as a physics entry, so the
  first turn calls it as a map (`MethodError: objects of type
  StrongStrongCollision{Nothing} are not callable`), on the placement and
  the tuple spelling alike; the analysis route refuses it "as an in-line
  hook". Both are accidents of dispatch, neither a design.
- **No removal verb.** The owner asked whether a marker can be removed.
  With the inert treatment none is needed; the keyword line form is the
  escape hatch and keeps every provenance path:

  ```julia
  entries = [e for e in line_entries(lattice) if !(e.spec isa StrongStrongCollision)]
  line    = BeamLine(; name = line_name(lattice.line), entries)
  noip    = Lattice(lattice.name * "_NOIP"; line, reference = lattice.reference, knob_root = lattice.knob_roots)
  ```

  A `without_entries(lattice, selector)` sibling of `with_overrides` (about
  twenty lines) is not added until a second use appears.
- **Lands in:** the single-beam compile walk in `src/tasks/Tasks.jl` (a
  `StrongStrongCollision` arm that appends nothing and counts), the
  linear-map walk the analyses use (the marker as the identity), the task's
  binding receipt and `configuration_report`, the two docstrings. The
  strong-strong route is untouched; its pins cover it.
- **Acceptance:** a lattice tracks bitwise with and without its marker
  (CPU; CUDA within the same-tree noise, as the stage records measured);
  `one_turn_matrix` equal; the receipt pinned at 0, 1 and 2 markers; the
  strong-strong pins unchanged. **Price:** about 40 lines plus tests; a full
  gate (the task compile).
- **Status 2026-11-26 (batch A, U4; record [`../history/machine_description_compile_path1_2026_11_26.md`](../history/machine_description_compile_path1_2026_11_26.md)):** landed. The whole-line compile and the generic walk skip a `StrongStrongCollision` child (`_inert_in_single_beam`, `src/elements/beam_line.jl` and `src/tasks/Tasks.jl`), the task counts it at construction (`_collision_marker_count`), the `:tracking_line_binding` receipt and `configuration_report(task).binding` carry `collision_markers`, and the linear-map walk sees the identity. Pinned: a lattice tracks bitwise with and without its marker on CPU, `one_turn_matrix` and `analyze` equal, the count at 0, 1 and 2 markers, nothing warns; red first on c52d80e (`MethodError: not callable` at the first turn, the whole-line form refused as an in-line hook).

### R3 `r0` is not an input

- **Decision** (owner: "Since r0 is not an independent input, I agree we
  should drop it from the input"): `r0 = RE * ME0 / mc2`, Octopus's
  unit-charge classical radius, is derived from the reference and stored on
  it (R4). `Beam`'s flat `r0` keyword is retired: refused by name with the
  remedy (`reference = ReferenceParticle(...)`), after the repo-wide grep.
  The three examples and the harnesses that hand-type `RE * ME0 / mass` are
  converted in the same batch; their fingerprints stay bit for bit, since the
  derived value is the same expression. An exotic particle is a
  `ReferenceParticle` with its own `mc2`, which is what `r0` derives from.
- **Today.** `_beam_params` (`src/beam/Beam.jl:1253-1260`) defaults `r0`,
  `charge` and `mc2` to 0 when not given; the examples never hit it because
  each computes `r0` by hand, which is why C-5 stayed invisible until the
  reference batch's review.
- **Lands in:** `src/beam/Beam.jl`, the examples, `test/examples/`,
  `validation/`, `docs/public_api.md`. **Acceptance:** `r0 =` refused by name;
  the fingerprint recipe of the stage records (weak-strong 10k x 50,
  strong-strong 2k+2k x 20, crab noise 10k x 50, the DBA ring) identical on
  CPU and within noise on CUDA; the grep count of `r0` spellers recorded in
  the batch record.
- **Status 2026-11-26 (batch A, U2; record [`../history/machine_description_compile_path1_2026_11_26.md`](../history/machine_description_compile_path1_2026_11_26.md)):** landed. `Beam` derives `r0 = RE * ME0 / mc2` (`_reference_r0`), refuses `r0 =` by name, and the 180 `r0 =` keywords of the examples, harnesses, validation scripts, profiling drivers, contracts and the suite are gone; the examples' CPU fingerprints are identical to the stage-5 baseline (the derivation preserves the bits).

### R4 The richer, immutable `ReferenceParticle`

- **Decision** (owner: "Should we let a reference particle carry more
  information when we construct it? ... Other information, like r0, p0c,
  B*rho rigidity, beta0, gamma0, etc. we can compute and save them once in
  the reference particle. ... This is like what MADX did, right?"; then "I
  think your recommendation about immutable reference is ok"): yes in
  substance, with two refinements the owner accepted: no silent physics
  defaults, and immutable rather than MAD-X's mutable `BEAM`.
- **Inputs.** `charge` and `mc2` required, numbers; exactly one of `E0`,
  `p0c`, `gamma0`, `brho`, two of them refused by name, none refused by name.
  `beta0` is not an input (ill-conditioned at high energy; nobody specifies a
  10 GeV electron by its beta). A numeric energy below `mc2` is refused by
  name at construction (the knob-given case, a bare `DomainError` in the
  derived tree's `sqrt`, stays the open row of `todo.md`). No defaulted
  energy or mass: a defaulted physics number is the class of silent wrong
  value R5 closes.
- **Species presets.** `ReferenceParticle(:proton; E0 = 275e9)`,
  `ReferenceParticle(:electron; p0c = 10e9)`, `:positron`; charge and mass
  from `src/constants/` by name, the energy still required; ions through the
  explicit form; a tripwire that every preset's numbers are named constants.
  This is MAD-X's `PARTICLE=PROTON` convenience without its defaults.
- **Derived, computed once** in the one constructor path and stored as
  fields of the immutable record: `p0c = sqrt(E0^2 - mc2^2)`,
  `gamma0 = E0 / mc2`, `beta0 = p0c / E0`, `brho = p0c / (c |charge|)` in
  T m with `p0c` in eV, `r0 = RE * ME0 / mc2`. Immutable plus one
  constructor means a stored derived field cannot go stale, which is the
  MAD-X failure mode this avoids (MAD-X recomputes `energy`, `pc`, `gamma`,
  `beta`, `brho` on every update of a global mutable `BEAM`, and the
  "which beam is current" confusions follow). The accessors
  `reference_beta`, `reference_gamma`, `reference_beta_gamma` keep working
  and read the fields.
- **Knob expressions, for the ramp (R7) at no cost now.** The energy input
  accepts a knob expression under D10, `E0 = @knob_expr(hsr.E0)`; the
  derived quantities are then stored as expression trees over it, built
  from the whitelisted operations, and resolve at compile like every other
  parameter. `charge` and `mc2` stay numbers (species facts do not ramp), so
  `|charge|` in `brho` is a number. Derived values are cached numbers only
  when the input is a number: there is no stored copy that can disagree with
  the knob.
- **Consumers.** `Beam` derives `r0` (R3); the cavities read `beta0` and
  `gamma0` from the reference; `examples/knob_control.jl`'s hand-typed
  `B_rho = 81.1` becomes the reference's rigidity; `npart` remains the one
  beam-level physical input.
- **Snapshot.** Discussed as "stays as it is": the file writes `charge`,
  `mc2`, `E0` (a number or `{ expr = ... }`) and the reader rebuilds through
  the constructor, the derived fields coming back identical. Refined after
  the discussion, for the owner to confirm (section 5, item 2): write the
  energy under the key the user typed (`E0`, `p0c`, `gamma0` or `brho`), so
  a reference given as `p0c` round-trips exactly; deriving `E0` and
  re-deriving `p0c` can move the last bit, and the typed input is the stored
  parameter D13 writes. Additive: the reader accepts the four keys, exactly
  one of them.
- **Lands in:** `src/lattice/Lattice.jl` (the three-field struct at line 43
  and the keyword constructor at line 49 today), `src/constants/`, the
  cavities' and `Beam`'s funnels, the snapshot's reference rule,
  `docs/public_api.md`, the registry snapshot. **Acceptance:** every refusal
  by name; the derived fields against hand formulas at 1e-15 relative for
  an electron at 10 GeV and a proton at 275 GeV; the numeric and the
  expression input agree after `resolve_knobs`; the fingerprints unchanged.
  **Price:** with R3 and R5, about three hours plus the gate.
- **Status 2026-11-26 (batch A, U2):** landed as decided: `ReferenceParticle(:proton | :electron | :positron; <one energy>)` and `ReferenceParticle(; charge, mc2, <one energy>)` with exactly one of `E0`, `p0c`, `gamma0`, `brho` (a number or a knob expression), the other quantities and `r0` derived once and stored (`beta0` included), the typed key kept (`energy_key`, `reference_energy`) and written by the snapshot under the key the user typed (the owner's choice, section 5 item 2); structural `==` and `hash`, so a reference built from `E0` and one from the equivalent `p0c` are physically equal and structurally distinct; the knob-root check at `Lattice`.

### R5 The derived kick scale: zero factors refused, the value reported, `npart` loud

- **The item.** A strong-strong run derives
  `kbb1 = charge1 * charge2 * r0_1 * npart_2 * mc2_1 / E0_1`
  (`src/tasks/strongstrong/slicing.jl:115`) unless `kbb1 =`/`kbb2 =` is set
  on the solver. Only `E0` is refused by the preflight; `charge`, `mc2` and
  `r0` default to 0, so any of them missing zeroes the force while the
  luminosity is still computed and written and nothing in the reports shows
  the derived value. `npart` defaults to `N`, the macro-particle count, so a
  beam built from a real reference without `npart` gets a plausible-looking
  kick typically five orders of magnitude too weak.
- **Decision.** (1) `r0` derived from the reference (R3) closes the common
  case at the source. (2) The preflight `_preflight_solver_kbb`
  (`src/tasks/strongstrong/interface.jl:3411`), where the `E0` refusal lives
  and the beams are still untouched, refuses a zero `charge`, `mc2` or `r0`
  of a derived kick by name: the beam, the factor, the two remedies
  (`reference = ReferenceParticle(...)`; `kbb1 =` on the solver to bypass the
  derivation). (3) `npart == N` on a derived kick: warn once per strong-strong
  task naming the remedy (the recommendation; many fixtures are small beams
  where the macro count is the population), or refuse whenever a `reference`
  was given (the stricter rule, acceptable): the owner's remaining choice
  (section 5, item 1). (4) The resolved `kbb1`/`kbb2` appear in the solver's
  entry of `configuration_report(task, beam1, beam2)` and in the artifact's
  receipt, so a zero or a suspiciously small scale is visible after the
  fact.
- **Blast radius measured first, not guessed.** The audit counted 96
  explicit `kbb1 =` overrides in the suite, which never derive and are
  unaffected, and 5 single-line beams built from `E0` alone whose
  expectations may encode the zero kick; multi-line constructions were not
  counted. One instrumented suite pass (count the fixtures deriving a zero
  on purpose) runs before the refusal lands. C-5 closes with this.
- **Class:** public configuration (`validate_configuration_metadata()`, the
  effectiveness contract) and acceptance (every probing test found first).
- **Status 2026-11-26 (batch A, U2):** landed. `_preflight_solver_kbb` refuses a zero `mc2`, `r0` or `charge` of either beam by name (`_check_derived_kick`), the derived `kbb1`/`kbb2` are in the solver report (status `:inherited`) and the `:strong_strong_collision` receipt; `npart` per the owner's choice (section 5 item 1): a beam built from a `reference` without `npart` is refused by name, a flat-keyword beam without it warns once per task.

### R6 Wider than `Float64` is refused; `Float64` to `Float32` stays

- **Decision** (owner: "I agree to refuse the loss, and keep the
  convention"): `_as_numeric_type(::Type{T}, v::AbstractFloat)`
  (`src/knowledge/Knowledge.jl:813`, today `T(v)`) converts when the value's
  type is at most `Float64` or `T` is at least as wide as the value's type,
  and refuses otherwise by name: the element, the parameter, the two types,
  the remedy (an untyped element, which promotes, or
  `numeric_type = BigFloat`). The lattice tripwire
  (`_lattice_check_entry_eltype`) calls the same predicate on a typed spec's
  merged values, so `Lattice(...)` refuses early with the same message. One
  rule for the in-place route, `with_overrides`, the spec route
  (`spec.L = big"..."`), the flexible constructor and the snapshot reader.
  A `ForwardDiff` dual already throws on `Float64(dual)`; unchanged. B-11
  closes with this.
- **Why.** Narrowing from `Float64` is what every `Float32` user wants (they
  type `0.7`, not `0.7f0`) and the suite pins it; a `BigFloat` reaching a
  `Float64` element is deliberate by construction, so the refusal never
  fires on an intended narrowing, and the untyped element already refuses
  the same value by name, so the two kinds of element agree afterwards.
- **Acceptance:** `lt[1].L = big"0.30000000000000000001"` on a
  `QuadrupoleSpec(; numeric_type = Float64, ...)` red first; the pin that a
  `Float64` literal on a `DriftSpec{Float32}` compiles to `0.7f0` (the suite
  lines 20655-20660 at the audit) still green; a grep of the suite for wide
  overrides on typed elements (expected none). **Price:** about twelve lines
  plus tests.
- **Status 2026-11-26 (batch A, U3):** landed. `_as_numeric_type` refuses by name a value the element's type cannot hold (`BigFloat` into `Float64` or `Float32`, a dual or complex into a real type), naming the parameter and the remedy (`numeric_type = BigFloat`, or the untyped form); `Float64` to `Float32` keeps narrowing; `Lattice(...)` refuses early through `_lattice_check_typed_values`; the suite's pin at the old convention rewritten with it (red first).

### R7 Ramping: a knob on the reference, never a rebuilt reference

- **Decision** (owner asked "what can we do to ramping machine? Should we
  rebuild the reference every acceleration?" and accepted the answer): no.
  The survey note owns this (sections 5 and 6): the reference is bookkeeping
  derived at compile, and time variation is a control knob, never a mutable
  field or a kernel that sees time. The immutable record fits each
  granularity: within one pass, the energy survey assigns every element its
  own reference downstream of each accelerating cavity with the coordinate
  rescaling at each step, the entrance reference staying the lattice's by
  definition (D3), which is why a line with an accelerating cavity refuses a
  second turn by name; multi-pass at different energies (an ERL) is
  statically unrolled with knobs as the sharing discipline; the ramping ring
  has a flat within-turn profile, so the dynamic part is one scalar per
  turn: the reference energy depends on a knob, a scheduled action assigns
  it at turn boundaries following the ramp program, the epoch bumps, the
  knob-dependent elements recompile with renormalised strengths, and the
  boundary applies the energy survey's coordinate rescaling, adiabatic
  damping at turn granularity. The reference is re-resolved by the machinery
  that re-resolves every knob-dependent parameter; nothing is rebuilt by
  hand; the kernels never see time.
- **Now, at no cost:** R4's expression inputs. **Later, its own campaign**
  (D18's deferred item), physics rather than plumbing: the boundary
  rescaling applied to a live beam at a turn boundary (the beam's own
  reference moving with it), the ramp program as a scheduled action over a
  turn table, the single-pass refusal relaxed for that route only, and a
  theory note with validation targets that make it a contract (adiabatic
  emittance damping as `1/(beta gamma)`, the synchrotron frequency following
  the voltage program, bucket motion). Not before batch A. For the artifact
  (R9): a per-turn ramp makes every turn a distinct machine state, so the
  ramp is recorded as a program (a table by digest) beside the declared
  machine, never as a snapshot per turn.
- **Status 2026-11-26:** not in batch A; the ramp campaign is batch C, after the `ParamMeta` type campaign (the owner's choice, section 5 item 4).
- **Status 2026-11-27:** batch C's theory note [`../theory/reference_ramp.md`](../theory/reference_ramp.md) written with the owner's choices; its implementation follows (the status line under "Batch C").

### R8 The four priced leads

- **(a) The marker in a single-beam line:** R2.
- **(b) B-6a, the stream id the reader does not re-claim.** Every consumer
  of the counter RNG holds an `rng_id`; explicit ids are claimed in a
  process-global registry at construction so auto-assigned ids never land on
  them and two consumer classes on one id warn. The friendly constructors,
  the rules and the observers claim; the snapshot reader rebuilds elements
  through the flexible form `ElementSpec{kind}(params)`, the raw storage
  door, which claims nothing, and the same gap exists for an in-place
  override `entry.rng_id = 11`. **Decision:** claim at the flexible form,
  which every route passes, when `params` carries `rng_id`, with the
  consumer class from a new `ElementMeta` field and a tripwire that every
  kind declaring `rng_id` declares a class; the override routes claim through
  the guard family; same-class re-claims are silent (the 2026-10-16 policy),
  so the friendly constructors do not double-warn.
  `claim_rng_id!(id; consumer)` is at `src/math/counter_rng.jl:269`.
  **Acceptance:** a reloaded explicit id is held (`_rng_id_held`); a reload
  onto another class's id warns. Metadata class (`validate_element_metadata()`).
- **(c) C-3, the 416 bytes per `execute!`.** Every window longer than one
  turn re-walks the line to ask whether it holds an accelerating cavity
  (`_has_accelerating_cavity(task.elements)` in `_execute_tracking_window!`,
  `src/tasks/Tasks.jl:1151`); for placements the walk goes through
  `Any`-typed specs and allocates. Per call, not per turn; no physics effect.
  **Decision:** compute the flag once per compilation beside the runtime
  cache, which the spec and knob epochs already invalidate, so both
  spellings stop paying the walk. **Acceptance:** a cost pin,
  `@allocated execute!(task, beam; turns = 1)` equal on the tuple and the
  lattice spelling (53248 B against 53664 B at the audit's probe point, the
  parity driver's weak-strong case at 2000 macroparticles). The ramp
  campaign rewrites this refusal later.
- **(d) C-6, readability where `ParamMeta` has no type.** The codec infers
  a value's class from the default, the alternatives and the kind's example,
  and prints the marker form `{ tuple = [...] }` where none speaks
  (`Linear6DSpec` built from optics points); `EveryNSteps` stores "no stop"
  as `typemax(Int)` and the writer prints what is stored
  (`src/lattice/toml_hooks.jl:513` documents it). **Decision:** the schedule
  special case now (print `stop` only when one was given, round-trip tested,
  the docstring pin moved with the text), and the `ParamMeta` type campaign
  as batch B: a declared type per parameter of every kind, a validator
  tripwire that every example value matches its declaration, the codec
  coercing by declared type with markers kept only for untyped parameters,
  `element_help` showing the types. Half a day plus a gate; a prerequisite
  for the D17 translators, which need every parameter's type to read a
  foreign lattice. The `Moment(::AbstractString)` `tryparse` (two lines;
  every caller's message changes) goes with the schedule case or stays with
  its price (section 5, item 5).
- **Status 2026-11-26 (batch A, U4, U5 and U6; record [`../history/machine_description_compile_path1_2026_11_26.md`](../history/machine_description_compile_path1_2026_11_26.md)):** (a) R2's status line. (b) landed: `ElementMeta.rng_consumer` (`:lumped_radiation`, `:particle_tunes`; `validate_element_metadata` holds "declares `rng_id` iff declares a class"), the flexible form claims an explicit id under the class (`_claim_spec_stream!`), the spec route, the in-place placement override and `with_overrides` claim through `_claim_override_stream!`; found in the batch and recorded in the record: the friendly constructor stores the stream it resolved for `rng_id = 0`, so every rebuild through the flexible form passes the kind's OWN auto-assigned id, which a plain `claim_rng_id!` would have warned about on every knob resolve -- `_rng_id_held_by(id, class)` answers it and the form claims only what its class does not hold yet. (c) landed: `TrackingTask.has_accelerating_cavity`, fixed at construction (the element kinds are fixed there; a knob changes values, never kinds), read by `_execute_tracking_window!`; the suite pins the executor's text, since an allocation equality between the tuple and the lattice spelling does not hold (different runtime shapes, 17520 against 17488 bytes per single-turn `execute!`). (d) landed: `EveryNSteps` prints `stop` only when one was given (the hook's own rule in `toml_hooks.jl`), and `Moment(::AbstractString)` refuses a non-integer power by name through `tryparse` (the owner's choice, section 5 item 5). The `ParamMeta` type campaign is batch B, landed 2026-11-26 (its status line under "Batch B").

### R9 The artifact's machine snapshot: content-addressed, cached, switchable

- **Owner:** "Agreed." to the five points below, asked as "Will it hurt
  performance? Will the output become too large for a large machine? Should
  we use a keyword to control whether we write the machine to the artifact?"
- **Measured** (section 4, table 1): rendering costs 1.1 ms for the shipped
  strong-strong example (14 kB) and 130 ms for 10,000 distinct elements
  (1.47 MB), once per `execute!` on rank 0; the digest takes SHA.jl's generic
  byte path on a `String` at about 3 microseconds per byte, 4.56 s for the
  1.47 MB text against 6.5 ms for the same bytes as a `Vector{UInt8}`,
  about 45 ms per `execute!` for the shipped example from that rate; and the stage-4
  layout writes the full text into the `/execution` row of every `execute!`
  call, so a per-turn loop of 100,000 calls carries 1.4 GB of repeated text
  for the small example and 150 GB for the large ring. The layout, not the
  snapshot, is the problem.
- **Decision.** (1) Content-address the text as the tables already are:
  `/machine_snapshots/<sha256>` written once per distinct digest, the ledger
  row keeping `machine_sha256` only (64 bytes per row);
  `read(out, :machine; slot)` resolves the row's digest; a stage-4 file that
  carries the text column still reads. (2) Cache the rendered text and its
  digest on the task beside the runtime cache, keyed on the same spec and
  knob epochs, so the machine is re-rendered only after a retune. (3) Digest
  the bytes, `sha256(Vector{UInt8}(codeunits(text)))`, as the table path
  (`_toml_digest`) already does; `_ra_machine_snapshot`
  (`src/tasks/RunArtifact.jl:892`) is the one site. (4) A keyword,
  `RunArtifact(path; machine_snapshot = true)`, on both constructors
  (`RunArtifact.jl:354` and `:367`): with `false` neither text nor digest is
  written and the readers refuse by name saying the artifact was written
  without a snapshot; it lands with its schema entry, inactive behaviour and
  an effectiveness test at the consumer boundary, like `append` and
  `capacity`; default `true`, since provenance is D14's point and with (1)
  to (3) the cost is one render per distinct machine state and one copy per
  artifact. (5) `run_artifact.md` gets a dated paragraph on the layout
  change; the stage-4 record stays frozen; the new record carries the
  addendum.
- **Order:** first in batch A; the digest fix should not wait. **Price:**
  about two hours plus the gate. **Acceptance:** before and after render
  plus digest time per `execute!` on the three machines of table 1; the
  file size of a 1,000-call loop before and after; the readers on a stage-4
  file and on a new file; the keyword's effectiveness test.
- **Status 2026-11-26 (batch A, U1; record [`../history/machine_description_compile_path1_2026_11_26.md`](../history/machine_description_compile_path1_2026_11_26.md)):** landed as decided: `/machine_snapshots/<sha256>` written once per distinct digest, the ledger row keeping `machine_sha256`, the digest over the text's bytes, the task-side cache keyed on the knob and spec epochs, `RunArtifact(...; machine_snapshot = true)` on both constructors with its schema entry and receipt (`machine_recorded`), the readers on the stage-4 layout and the new one. Measured (the record's table; the R9 cost probe's A500 fixture of 500 distinct elements, 200 single-turn `execute!` calls): the file's growth went from 12.3 MB to 0.91 MB and the call from 18.9 ms to 5.03 ms, the digest of a 1.24 MB text from 3.27 s over the `String` to 4.9 ms over its bytes.

### R10 TOML: no include, no templates; the multi-file description is a Julia module; two readers

- **Owner:** "Is there a mechanism to import or include other files in
  TOML?" then "Show me how you organize them into a module for a machine"
  then "read_lattice and read_machine help."
- **Decision.** TOML 1.0 has no include or import, by the format's design,
  and none is invented in the snapshot: the file is the data form (D2, D13),
  one self-contained flat file per machine, byte-identical for equal
  machines, the text the artifact embeds; an include directive would make
  the embedded copy either incomplete or different from the files on disk.
  Every compared code made the same split (MAD-X `CALL`, Bmad
  `call, file =`, elegant `#include`, Xsuite's Python imports in the
  authoring language; MAD-X `SAVE`, Bmad's writer, Xsuite's JSON line flat).
  Recorded as a standing decision in `docs/experiences.md`.
- **The module shape** (verified, section 4, probe 4): one one-lattice
  snapshot per file, written by `write_machine(path, lattice)`; a module
  reads them and assembles:

  ```julia
  module EIC
  using Octopus
  const DIR = @__DIR__
  const esr = read_machine(joinpath(DIR, "esr.toml"))[:ESR]
  const hsr = read_machine(joinpath(DIR, "hsr.toml"))[:HSR]
  const machine = Machine("EIC"; lattices = (esr, hsr), knob_root = :ip)   # the shared root declared once, here
  const esr_lowbeta = with_overrides(esr, sel"ESR/QF_IR[*]" => (kn = (0.0, 1.62),); name = "ESR_LOWBETA")
  end
  ```

  Rules: shared knobs live in the files of the lattices that read them,
  repeated by the writer and accepted the second time only with the same
  definition (a conflicting copy is refused by name), or declared once in
  Julia before the reads; a marker one object serves in two lattices reloads
  as two equal markers the strong-strong task pairs by label; reading fixed
  files is deterministic, so D8's include-twice equality holds, but the
  definition of record moves to the files, which are then what is versioned.
- **Agreed additions:** `read_lattice(path)`, a one-lattice file (several
  lattices refused by name, listing them); `read_machine(paths...; name,
  knob_root)`, each file read as today, the lattices collected in argument
  order, a duplicate name refused by name, the shared roots from `knob_root`,
  the same-definition knob rule across the files, the receipt the union.
  About twenty lines each plus tests (probe 4's split and reassembly is the
  test: equal to the original, byte-identical text). `docs/public_api.md`
  "Snapshot A Machine" and the registry snapshot gain them.
- **Deferred, not agreed:** `write_machine(path; split = :lattice)` (the
  machine and knobs in one file, each lattice in its own, referenced by
  relative path; about two hours) if a workflow needs a multi-file data
  form; a reader-side include of hand-written element libraries, which the
  D17 translators cover for an existing MAD-X or Xsuite library.
- **Status 2026-11-26 (batch A, U7):** landed: `read_lattice(path; receipt)` (a several-lattice snapshot refused by name, listing the lattices and the `read_machine(path)[:name]` remedy) and `read_machine(path1, path2, paths...; name, knob_root, receipt)` (the name required, the receipts' union with `files`, `Machine`'s own tripwires inherited: a lattice name twice, a shared root the assembled machine does not declare); probe 4 is a suite testset: the split machine reassembles `==` with a byte-identical `machine_toml`.

### R11 Element templates: the MAD-X class form on the friendly constructors

- **Owner's question:** "When I used madx, I can use the pre-defined
  element as a template. For example, Q: Quadrupole, L=1.0; QF:Q, K1=1.0;
  QD:Q, K1=-1.0; Does Octopus support such definition now? Can TOML
  description support it? What if Q is defined in a separate file?" The
  owner answered the recommendation below with "Ok."
- **Today** (section 4, probes 2 and 3). No class form. Three routes exist:
  one template placed several times with per-placement overrides
  (`entries[1].kn = (0.0, 1.0)`; the paths read `RING/Q` and `RING/Q[2]`,
  a placement keeps the spec's name; a `k1` override is refused by name
  because the constructor folds `k1` into `kn[2]`); a derived named spec by
  merging the template's stored parameters through the flexible form
  (`ElementSpec{:quadrupole}(merge(Q.params, Dict(:name => "QF", :kn => (0.0, 1.0))))`,
  which works and round-trips but has no fold guard: `k1` merged over a
  template is stored and compiles as `kn = ()`, identical to the template);
  and reuse across modules (a `RHIC` module's elements and cell used and
  derived by an `EIC` module, paths `HSR/CELL/Q`, the snapshot flat with one
  table per distinct spec, round trip equal). **TOML cannot express a
  template, by design:** D2 ("pure data cannot abstract") and D13 ("stored
  parameters only"); a `base = "Q"` key would read to the same object but the
  writer always flattens, so a templated hand-written file would never
  round-trip, a second shape forever; not added.
- **Decision.** Every friendly constructor gains one method taking a
  template of its own kind, `QuadrupoleSpec(Q; name = "QF", k1 = 1.0)`. The
  `@elements` macro is unchanged: positional arguments pass through (rule
  6), the binding name is the default `name` (rule 1), the block's numeric
  type applies (rule 3), so

  ```julia
  @elements begin
      QF = quadrupole(RHIC.Q; k1 =  1.0)      # QuadrupoleSpec(RHIC.Q; name = "QF", numeric_type = Float64, k1 = 1.0)
      QD = quadrupole(RHIC.Q; k1 = -1.0)
  end
  ```

  Semantics, matching MAD-X and the existing guards: start from the
  template's stored parameters; a keyword replaces its key; a named strength
  replaces its slot in the stored tuple (`k1` sets `kn[2]`, `k2` `kn[3]`,
  `angle` resets `h` and `b0`, `chord` the arc `L`), instead of the "both
  spellings set" refusal, because overriding the template's value is the
  point; the kind is fixed by the template (a drift template on
  `quadrupole(...)` is refused by name); chains are allowed
  (`QF2 = quadrupole(QF; k1 = 1.2)`); knob expressions are accepted as
  values (D10); a template whose stored `numeric_type` differs from the
  block's type is refused, not converted; `name` is required on the template
  method (the block supplies it; two specs of one name would share a path
  label); the result is a new spec and the template is never mutated; the
  snapshot stays flat and format 1 (a derivation's provenance is not
  recorded; a separate optional key if ever wanted).
- **Implementation.** One fold-aware helper over `_FOLDED_NAMED_STRENGTHS`
  and `_FOLDED_TUPLE_KEYS` (`src/elements/lattice_magnets.jl:1422-1431`) plus
  the bend's `angle`/`chord` rule, the result rebuilt through the kind's
  keyword constructor so every check runs; the template methods generated by
  an `@eval` loop over the registry's `friendly_constructor`s, no kind
  hand-listed. **Acceptance,** registry-derived: for every kind with a
  friendly constructor and a metadata `example`, deriving with no change
  equals the example up to its name; a named-strength derivation changes
  exactly its slot; a wrong kind and a mixed numeric type are refused by
  name; a chain; an expression value; the derived lattice's snapshot
  round-trips (the generic tripwire). Class: element metadata and help
  (`validate_element_metadata()`, both `element_help` forms, the registry
  snapshot); full gate. **Price:** about 200 lines with tests and docs.
- **Found while verifying, not yet ruled** (section 4, probe 3; section 5,
  item 3): the flexible form, and therefore the snapshot reader, accept a
  named strength and drop it. `k1` is a declared `ParamMeta` key of the
  quadrupole, so a table written `k1 = 1.0` in place of `kn = [0.0, 1.0]`
  (hand-written, or hand-edited from a snapshot) reads back with the stored
  keys `L, k1, name` and compiles `kn = ()`: a silently ignored
  configuration, the class the invariants forbid. The fix sits at the one
  choke point every route passes, `ElementSpec{Kind}(params)`
  (`src/knowledge/Knowledge.jl:61`), through a hook the element layer
  registers as the override guard's tables are: fold the named strengths as
  the friendly constructors do (recommended: a hand-written `k1` then means
  what it says, the both-spellings refusal still fires, the writer stays
  flat and the template-by-merge pattern becomes loud where it conflicts),
  or refuse them by name with the `kn` remedy as the placement guard does.
  Blast radius first: a grep of `ElementSpec{:quadrupole}(` and its siblings
  with a named strength in `test/`, `examples/` and `validation/`; the edited
  text red first. In batch A beside the class form.
- **Status 2026-11-26 (batch A, U8; record [`../history/machine_description_compile_path1_2026_11_26.md`](../history/machine_description_compile_path1_2026_11_26.md)):** landed. The class form is installed by the registration itself (`_install_class_form!` in `src/knowledge/Knowledge.jl`, since a loop over the registry in a later file missed the aperture, which registers after `Elements.jl`), its body `_derive_spec` in `src/elements/templates.jl`; the registry-derived tripwire derives every kind's example with no change and finds it equal up to the name (31 kinds); the named strength replaces its slot through `_FOLDED_NAMED_STRENGTHS` (the thin kinds and the solenoid included); the sector bend's `angle` resets `h` and `b0`; there is no `:rbend` kind, so the ruling's `chord` lands on the alias, `RBendSpec(template; ...)`, which reads its template as the RBEND it derives (faces unfolded by the stored half angle `h L / 2` and refolded at the new angle, `chord` replacing the arc, a template with `h != b0` refused by name) while `SBendSpec(template; ...)` keeps the faces as stored -- a convention beyond the ruling's text, recorded for the owner in the record; the flexible form folds a named strength as the constructors do (the owner's choice, section 5 item 3; `_fold_flexible_params!`, installed as the form's hook), so a hand-written `k1 = 1.0` reads as meant and is written back as `kn`; `element_help` prints the class form; the blast-radius grep found one suite test probing the old flexible-form behaviour (the thin quadrupole's both-spellings refusal, now at construction rather than compile, still an `ArgumentError`).

### R12 A library module, and a machine built on another

- **Owner:** "Sometimes, it is important to build a new machine by reusing
  existing modules. The EIC will build on RHIC. We already have a RHIC
  library which describes various magnet modules. For EIC, we want a new
  file, instead of maintain a very long file."
- **Decision.** The library is a Julia module (a file or a package) whose
  `@elements` blocks live in several included files; Julia's `include` is
  the include TOML lacks, and D8 holds, since source inclusion is
  deterministic. The library needs no `Lattice` of its own. The new machine's
  module does `using RHIC`, reuses elements and cells untouched, derives what
  differs with R11's class form, and assembles its lattices and `Machine`:

  ```
  RHIC/RHIC.jl       module RHIC; using Octopus; include("magnets.jl"); include("cells.jl"); end
  RHIC/magnets.jl    @elements begin  Q = quadrupole(L = 1.0);  D = drift(L = 0.5);  B = sbend(L = 2.0, h = 0.01, b0 = 0.01)  end
  RHIC/cells.jl      @elements begin  ARC_CELL = line(Q, D, B, D, Q, D, B, D)  end
  EIC/EIC.jl         module EIC; using Octopus, ..RHIC; include("hsr.jl"); include("esr.jl")
                     const machine = Machine("EIC"; lattices = (esr, hsr), knob_root = :ip); end
  EIC/hsr.jl         @elements begin
                         QF  = quadrupole(RHIC.Q; k1 =  1.0)
                         QD  = quadrupole(RHIC.Q; k1 = -1.0)
                         HSR = line(QF, RHIC.D, QD, RHIC.D, RHIC.ARC_CELL)
                     end
                     const hsr = Lattice("HSR"; line = HSR, reference = ReferenceParticle(:proton; E0 = 275e9))
  ```

  The EIC snapshot is flat, one table per distinct spec (`QF`, `D`, `QD`,
  `Q`, `B` in probe 2); the RHIC relation lives in the module, not in the
  file, which is D2's division. An existing RHIC library written in MAD-X
  enters through the D17 translator (one code first, table-driven; batch B's
  parameter types are its prerequisite), after which the derived relations
  are kept by authoring the EIC additions in Julia.
- **Status 2026-11-26 (batch A):** nothing to land in code; the U8 testset derives from a template bound in an enclosing module through `@elements`, the probe-2 shape.

## 3. The batches

### Batch A, "compile-path, part 1": the next session's work

One batch, nine units, in this order; each unit a full-gate class, the
gate once on the final tree before the push (the Definition of Done), CUDA
active. The order puts the digest fix first because it should not wait,
the reference work second because it is the largest and the examples'
fingerprints depend on it, and the class form last because it touches
every kind's constructor and its metadata tests.

| Unit | Content | Ruling | Change class (the matrix) | Targeted checks before the gate |
|---|---|---|---|---|
| U1 | the content-addressed `/machine_snapshots/<sha256>`, the ledger keeping the digest, the task-side cache keyed on the epochs, the byte digest, `RunArtifact(...; machine_snapshot)` on both constructors, the readers on old and new files, the `run_artifact.md` paragraph | R9 | public configuration; the artifact | `validate_configuration_metadata()`; `validate(PublicConfigurationEffectivenessContract())`; the before/after timings and sizes of R9 recorded |
| U2 | the richer immutable `ReferenceParticle` (required inputs, one-of energy, presets, derived fields, expression inputs), `r0` derived and retired as a `Beam` input, the zero-factor preflight, the derived `kbb` in the report and the receipt, `npart` per the owner's choice, the examples and harnesses converted | R3 R4 R5 | public configuration; acceptance; symbol removal (`r0 =`) | `validate_configuration_metadata()`; the effectiveness contract; every test probing the old acceptance found first; the instrumented suite pass counting fixtures that derive a zero; the repo-wide grep for `r0`; the fingerprint recipe on CPU and CUDA |
| U3 | the wider-than-`Float64` refusal at `_as_numeric_type` and the early lattice refusal | R6 | acceptance | the `20655-20660` pin found first; the `BigFloat` case red first; the suite grep for wide overrides on typed elements |
| U4 | the inert collision marker in the single-beam compile walk and the linear-map walk, the `collision_markers` receipt, the docstrings | R2 | the task compile (`compile_runtime` class) | the bitwise with/without test on CPU; CUDA within the same-tree noise; `one_turn_matrix` equal; `profiling/machine_description_parity.jl` re-run |
| U5 | the stream-id claim at the flexible form with the consumer class in `ElementMeta`, the override routes, the tripwire | R8b | element metadata | `validate_element_metadata()`; the reload tests |
| U6 | the accelerating-cavity flag cached per compilation; `EveryNSteps` printing `stop` only when given; optionally the `Moment` `tryparse` | R8c R8d | concurrency-adjacent compile cache; the codec | the cost pin on both spellings; the codec round trip; the moved docstring pin |
| U7 | `read_lattice(path)`; `read_machine(paths...; name, knob_root)` | R10 | public documentation and API | the split-and-reassemble test (probe 4); `docs/public_api.md`; the registry snapshot |
| U8 | the class form on every friendly constructor; the named-strength fold (or refusal) at the flexible form | R11 | element metadata and help; acceptance | `validate_element_metadata()`; both `element_help` forms; the registry snapshot; the blast-radius grep; the edited-text test red first; the registry-derived derivation tripwire |
| U9 | the ledgers and the scoped neighbour audit | all | docs | the index entry; the snapshot; the audit's report and unit reports |

Rules for the batch, from the standing instructions and the records:
everything additive, every existing call shape keeps working, the examples
run unchanged except where this note converts them; a regression test shown
red before each fix; the examples' fingerprints (the stage records' recipe)
identical on CPU threads and within the same-tree noise on CUDA for every
unit that touches the compile path (U2, U4, U6, U8), with the parity driver
re-run for U4 and U6; the extracted sweeps, then the fast lane, then the
full gate at CI settings with CUDA active on the final tree, nothing else
compiling on the machine while it runs; commit messages written from the
gate log after the gate and read back before the push; the batch record
`docs/history/machine_description_compile_path1_<date>.md`, the `todo.md`
rows, this note's `Status` lines per ruling, `machine_description.md`'s
D12, D13 and D14 status lines, `run_artifact.md`, `public_api.md`, the
registry snapshot and `experiences.md` (reusable lessons only) in the same
commits as the work; the neighbour audit per `docs/comprehensive_audit.md`
at the end, scoped to the batch's diff, its report indexed. The owner's
choices of section 5 are needed before U2 (item 1) and U8 (item 3); the
defaults stand if no answer arrives.

### Batch B: the `ParamMeta` type campaign

R8(d): a declared type per parameter of every kind, the validator tripwire,
the codec coercing by declared type, `element_help` showing the types.
Scheduled after batch A; a prerequisite for the D17 translators and for a
readable snapshot of every kind.

- **Status 2026-11-26 (batch B, record [`../history/machine_description_param_types_2026_11_26.md`](../history/machine_description_param_types_2026_11_26.md)):** landed. `ParamMeta.type` on all 681 parameters of the 32 registered kinds (231 declaration sites, the shared tables included), `_param_type_holds` as the one class rule (a real class admits numbers and knob expressions and never a flag, an integer class integers only, a tuple class its items, a union any member, `Any` everything), the validator refusing an undeclared parameter and holding the default, the alternatives and the example to the declaration, the codec coercing by it on both sides with the marker forms kept for `Any` and for old files, `element_help` printing `type=` before the unit. The one physics-free convention beyond the text: the matrix form of `Linear6DSpec` declares `Union{Nothing, AbstractMatrix, Tuple{Vararg{Real}}}` (the constructor stores a 36-tuple, which now prints as a plain array; a stored matrix keeps `{ matrix = ... }`).

### Batch C: the ramp campaign

R7: the theory note first (the boundary rescaling on a live beam, the ramp
program as a scheduled action over a turn table, the validation targets),
then the implementation with the single-pass refusal relaxed for that route
only and the ramp recorded as a program in the artifact. After batch B
unless the owner orders otherwise (section 5, item 4).

- **Status 2026-11-27:** the theory note is written,
  [`../theory/reference_ramp.md`](../theory/reference_ramp.md): the boundary
  map derived in convention #3 (momenta scale by `P0_old/P0_new`, positions
  stay), the consistency relation `E0(n+1) - E0(n) = qV sin(phi_s)`, the
  route (a turn table of `E0(n)` by digest, a scheduled action, the epoch
  check in the turn loop), four validation targets with tolerances, and the
  owner's four choices (single-beam `TrackingTask` first, the table as the
  program, the RF phase the user's through a knob program, plain-number
  strengths constant). One departure from R7's text: the single-pass refusal
  of `ThinAcceleratingCavitySpec` stays, since the ramp route never passes
  through an accelerating cavity. The implementation follows.

### Deferred by decision

The beam receipt in the run artifact (R1); `write_machine(path; split =
:lattice)` and any reader-side include (R10); a removal verb for markers
(R2); a derivation-provenance key in the snapshot (R11); the translators
(D17) and the deliberately-not-now items (D18) as the parent note states
them.

## 4. Measurements behind the note (2026-11-26)

All on the development host (four threads, warm) on the tree at `f877ac1`.
The probe scripts were scratch and stayed untracked; the numbers are here.

**Table 1, the artifact's snapshot cost (R9).** Rendering once per
`execute!` on rank 0; the digest as the stage-4 code computes it, on a
`String`, against the same bytes as a `Vector{UInt8}`.

| machine | text | render per `execute!` |
|---|---|---|
| shipped strong-strong example, 25 placements | 14 kB | 1.1 ms |
| 10,000 placements sharing 4 element objects | 0.39 MB | 24 ms |
| 10,000 distinct elements | 1.47 MB | 130 ms |

The digest, measured on the 1.47 MB text: 4.56 s through
`SHA.sha256(::String)` against 6.5 ms for the same bytes as a
`Vector{UInt8}`, about 3 microseconds per byte on the generic path. The
shipped example's digest cost, about 45 ms per `execute!`, follows from
that rate and was not timed separately.
The stage-4 layout repeats the text in every `/execution` row: 100,000
single-turn `execute!` calls carry 1.4 GB of text for the small example and
150 GB for the large ring. The 416 B per `execute!` of C-3 is the audit's
measurement (`probe_alloc.jl` in its report), not re-measured here.

**Probe 1, a template by merging stored parameters (R11, today).** A
`QuadrupoleSpec(; name = "Q", L = 1.0)` stores the keys `L, name` and no
`kn`. `ElementSpec{:quadrupole}(merge(Q.params, Dict(:name => "QF", :kn =>
(0.0, 1.0))))` gives `QF` with `kn = (0.0, 1.0)`, `L = 1.0`, and leaves `Q`
unchanged. The same merge with `:k1 => 1.0` stores the keys `L, k1, name`,
compiles to a `LatticeMagnet` with `kn = ()` and `ks = ()`, equal to the
compiled template and unequal to `QuadrupoleSpec(; L = 1.0, k1 = 1.0)`,
whose compiled strengths are `kn = (0.0, 1.0)`, `ks = (0.0, 0.0)`. No
warning is printed: `k1` is a declared key.

**Probe 2, one template placed twice, and two modules (R11, R12, today).**
`BeamLine("RING", Q, D, Q, D)` with `entries[1].kn = (0.0, 1.0)` and
`entries[3].kn = (0.0, -1.0)` has the paths `RING/Q, RING/D, RING/Q[2],
RING/D[2]`; `entries[1].k1 = 1.0` is refused by name ("`k1` is folded into
`kn[2]` ..."). A `RHIC` module declaring `Q`, `D`, `B` and
`CELL = line(Q, D, B, D, Q, D, B, D)` through `@elements`, and an `EIC`
module with `using ..RHIC` deriving `QF` and `QD` from `RHIC.Q` by the merge
inside its own `@elements` block (a helper call passes untouched), builds
`Lattice("HSR")` with 12 placements over 11.0 m and the paths `HSR/QF,
HSR/D, HSR/QD, HSR/D[2], HSR/CELL/Q, HSR/CELL/D, HSR/CELL/B, HSR/CELL/D[2],
HSR/CELL/Q[2], HSR/CELL/D[3], HSR/CELL/B[2], HSR/CELL/D[4]`; its snapshot is
1193 bytes with five element tables (`QF`, `D`, `QD`, `Q`, `B`), no
derivation recorded, and `read_machine(path)[:HSR] == EIC.lattice` is true.

**Probe 3, a hand-written `k1` through the snapshot reader (R11, the
finding).** `haskey(element_meta(:quadrupole).parameters, :k1)` is true. The
`machine_toml` of a lattice holding `QuadrupoleSpec(; name = "Q", L = 1.0,
k1 = 1.0)` writes `kn = [0.0, 1.0]`; the text with that line replaced by
`k1 = 1.0` is accepted by `parse_machine`, the reloaded spec stores the keys
`L, k1, name`, and `compile_runtime` gives `kn = ()` where the original
gives `(0.0, 1.0)`.

**Probe 4, the split snapshot reassembled by a module (R10).** The shipped
strong-strong machine written as `write_machine(path, machine[:ESR])` and
`write_machine(path, machine[:HSR])` gives files of 7257 and 6790 bytes,
each starting `format = 1`, `[machine] name = "ESR"`, `lattices = ["ESR"]`,
with `[lattices.ESR]` carrying `eltype`, the knob roots, the reference
`{ charge = -1.0, mc2 = 510998.95069, E0 = 1.0e10 }` and `line = "ESR"`.
A module reading both and building `Machine("EIC"; lattices = (esr, hsr))`
is `==` to the original and its `machine_toml` is byte-identical to the
original's.

## 5. Open for the owner

Each item carries the default the implementer takes if no answer arrives
before its unit.
All five were put to the owner on 2026-11-26 before the batch started
(the owner asked to be consulted rather than defaulted); the answers are
recorded under each item, and a sixth, the push: on a green full gate the
batch is pushed without a further question.

1. **`npart` on a derived kick (R5, before U2):** warn once per strong-strong
   task when `npart == N` (the default and the recommendation), or refuse
   whenever a `reference` was given.
   Resolved 2026-11-26 by the owner: refuse when a `reference` was given (a flat-keyword beam without `npart` warns once per task). Landed in U2.
2. **The snapshot's energy key (R4, U2):** write the energy under the key
   the user typed, `E0`, `p0c`, `gamma0` or `brho`, so a `p0c` reference
   round-trips exactly (the default and the recommendation), or always
   write `E0` as the discussion first said.
   Resolved 2026-11-26 by the owner: the key the user typed. Landed in U2 (`energy_key`).
3. **A named strength at the flexible form (R11, before U8):** fold it as the
   friendly constructors do (the default and the recommendation), or refuse
   it by name with the `kn` remedy as the placement guard does.
   Resolved 2026-11-26 by the owner: fold as the friendly constructors do. Landed in U8 (`_fold_flexible_params!`).
4. **Batch order after A:** the `ParamMeta` type campaign (batch B) before the
   ramp theory note (batch C), since D17 needs the types (the
   recommendation), or the ramp first.
   Resolved 2026-11-26 by the owner: the `ParamMeta` type campaign (batch B) first, then the ramp (batch C).
5. **`Moment(::AbstractString)`'s `tryparse` (R8d, U6):** with the
   `EveryNSteps` case (two lines, every caller's message changes; the
   default), or left with its price in the carried row.
   Resolved 2026-11-26 by the owner: fixed in U6.

## 6. Precedents read for these rulings

MAD-X: class definitions (`QF: Q, K1 = 1.0`, the shape R11 reproduces) and
the global mutable `BEAM` whose recomputed `energy`, `pc`, `gamma`, `beta`,
`brho` R4 deliberately does not copy; `CALL` as the include in the language.
Bmad: a lattice element defined from an existing one, the reference and a
start particle on the lattice, rampers for energy change (R7's knob route is
their translation), `call, file =`. Xsuite: `Environment` with a reference
particle per line and no beam sizes (R1), `env.new` taking an existing
element as parent (R11), Python imports as the include. elegant: ramp
elements and `#include`. All four dump a flat file; none puts a template or
an include in it (R10, R11).
