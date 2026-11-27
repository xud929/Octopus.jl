# The machine description, batch B: a declared value class on every element parameter (2026-11-26)

Batch B of [`../design/machine_description_followups.md`](../design/machine_description_followups.md)
(section 3; ruling R8d), after batch A's record
[`machine_description_compile_path1_2026_11_26.md`](machine_description_compile_path1_2026_11_26.md):
the `ParamMeta` type campaign the stage-5 audit's C-6 asked for
([`audit_machine_description_2026_11_25.md`](audit_machine_description_2026_11_25.md))
and the prerequisite of the D17 translators. One batch, one worktree
(`pmb`, off cb4045e), one commit; the neighbour audit is section 4 of this
record. Guides: `../guides/elements.md`, `../guides/configuration.md`,
`../guides/development_workflow.md`; the protocol `../comprehensive_audit.md`
for the audit.

## 1 What landed

- **The declaration.** `ParamMeta` gains `type`, the class of value the
  parameter STORES (`src/knowledge/Knowledge.jl`): `Real` admits any
  non-`Bool` number and a knob expression (D10), `Integer` an integer only
  (the compile cannot resolve an expression to a count), `Bool`, `Symbol`,
  `AbstractString`, `Type`, `AbstractTrackingMethod`, `Tuple{Vararg{Real}}`
  (any length; `NTuple{N,Real}` a fixed one), `Union{Nothing,T}` where the
  stored value may be `nothing`, an object type for a rule, a record or a
  nested spec, and `Any` for a deliberately polymorphic parameter
  (`particle_tunes`, the strong beam's `coupling`); `nothing` is
  "undeclared". The five-field positional constructor is kept (undeclared).
  `_param_type_holds(T, v)` is the one class rule the validator, the writer
  and the reader ask.
- **The declarations.** All 681 parameters of the 32 registered kinds, at
  231 declaration sites (the shared tables `_LATTICE_BODY_PARAMS`,
  `_THIN_COMMON`, `_PLACEMENT_PARAMS`, `_STRAIGHT_BEND_FRINGE` included),
  typed by a per-file mapping (`/tmp` script recorded in section 3). Where
  one key name carries two classes the file decides: `ks` is the solenoid's
  strength (`Real`) and the magnets' skew tuple; `phase`, `phase_noise` and
  `strength_noise` are scalars or one rule on the RF cavity and per-harmonic
  tuples on the crab cavity; `angle` is a bend's or boost's `Real` and the
  strong beam's closed-orbit tuple; `zeta1`..`eta4` are the linear maps'
  scalars and `Linear6DSpec`'s tuples. `AbstractTurnRule`, the root of the
  turn rules, moved from `turn_modulated.jl` to `Knowledge.jl` beside
  `AbstractTrackingMethod`, since the cavities' schemas name it and include
  first.
- **The validator** (`validate_element_metadata`): an undeclared parameter,
  a declared type that is not a `Type`, a default outside the type, an
  alternative outside it and an example's stored value outside it are each
  refused by name; the placement-table comparison includes the type. A
  default of `nothing` is "no declared default" (the
  `_check_declared_defaults!` convention) and is not held to the type; a
  stored `nothing` in an example is, which is what makes the strong beam's
  `slice_*` parameters declare `Union{Nothing, Tuple{Vararg{Real}}}`.
- **The codec** (`src/lattice/toml.jl`): the hint of every element key
  carries the declared type; the writer prints the plain forms by it -- a
  tuple class as an array, a `Symbol` class as a bare string, a `Type` class
  as a name -- and refuses by name a stored value outside the class (a raw
  `ElementSpec` can store one; a friendly constructor does not); the reader
  coerces by it -- an array to a tuple, a bare string to a `Symbol` or a
  type name -- and refuses by name a float where an integer is declared, a
  bare string, a boolean or an array where a number is, `{ nothing = true }`
  where the class has no `nothing`, and, after decoding, any value outside
  the class; the marker forms are written only for `Any` keys and for a
  class admitting both tuples and vectors, and are read on every key, so a
  file written before the types reads unchanged. The format stays 1. The
  C-6 case: a `Linear6DSpec` built from two `LinearOptics` points now
  prints `beta1 = [1.1, 0.05, 80.0]` and `dmu = [...]`, no marker; its
  matrix form declares `Union{Nothing, AbstractMatrix, Tuple{Vararg{Real}}}`
  (the constructor stores a 36-tuple, now a plain array; a stored matrix
  keeps `{ matrix = ... }`).
- **`element_help`** prints `type=` first after `required`/`optional`
  (`- kn (optional; type=Tuple{Vararg{Real}}; ...)`), on both query forms.
- **Docs:** `?ParamMeta`, the `?@element_spec` checklist, the `write_machine`
  docstring's value rules, `docs/guides/elements.md`, `docs/public_api.md`,
  the design note's D13 status, the follow-ups note's batch B and R8d
  status lines, `docs/experiences.md` (the serializer lesson's closing),
  `docs/README.md`, `docs/todo.md` rows 22 and 23, the registry snapshot.

## 2 Measurements and decisions

- **The survey that decided the method** (`/tmp/claude-dxu/pmb/survey_params.log`
  on cb4045e): 681 parameters; 371 declare a real quantity through an
  integer default `0` with no example value (`x_offset`, `k1`, `h`, ...), 26
  more have an integer default and a float example, 28 have no default and
  no example. A type inferred from the default would therefore have been
  wrong for more than half the registry, so every site declares its class
  explicitly, and the validator refuses an undeclared one.
- **Int defaults stay.** `k1 = ParamMeta(type=Real, default=0, ...)` keeps
  its integer literal: the class rule admits an integer where a real is
  declared (`0 isa Real`), the constructors have always accepted both
  spellings, and rewriting 371 defaults to `0.0` would move nothing but
  text.
- **No knob expression in an integer class.** `Integer` refuses an
  `AbstractKnobExpression` because the compile resolves an expression to
  `Float64`, which a step count or a form index cannot take.
- **`Any` is explicit and rare**: `particle_tunes` (arrays, functions,
  constants, distributions, tuples of them) and the strong beam's
  `coupling` (an `XYCouplingSpec`, an `XYCoupling` or a matrix). Both keep
  the marker forms, which the format documents.

## 3 Verification

- **Red first** on cb4045e (`result/gates/pmb/red/b1_red.log`,
  `b2_red.log`): the metadata testset fails on `ParamMeta` having no `type`
  field, the codec testset on the marker forms the untyped codec prints and
  on the refusals it does not make.
- **The validators on the batch tree** (`/tmp/claude-dxu/pmb/validators.log`):
  `validate_configuration_metadata() = true`; `validate_element_metadata()`
  passed with 681 typed parameters (614 default pairs checked, 34
  runtime-variant pairs); `element_help` renders both forms for all 32
  kinds; the registry snapshot is unchanged (no new export);
  `validate(PublicConfigurationEffectivenessContract())` passed.
- **The extracted neighbours** (45 titles: the two new testsets, the codec
  blocks of stage 4 and 5, the metadata validator blocks, the element
  effectiveness contract, the `@elements`, reference and batch-A blocks,
  the export, docstring, `Core.Box` and architecture sweeps):
  three runs. The first (`/tmp/claude-dxu/pmb/extracted_final.log`, 45
  blocks, on the tree before the hint fix A-1) was green except the new
  codec testset (A-1), the architecture sweep (this record not yet written
  when the README already linked it) and the hidden-solver block, whose
  child process needs the test environment (the runner's stated limit, the
  gate's). The second (`extracted_final2.log`, 19 codec and metadata
  blocks after A-1) found A-4 and the moved reader pin. The third
  (`extracted_final3.log`, the same 19 plus the architecture sweep, after
  A-4): all 20 green, exit 0
- **The examples' fingerprints** (CPU threads, the stage records' recipe):
  all 20 rows IDENTICAL to the batch-A baseline
  (`/tmp/claude-dxu/pmb/compare/post.log` against `/tmp/claude-dxu/cp1/compare/post.log`,
  itself identical to the stage-5 logs under `result/gates/md5/compare/`). The batch touches no kernel and no compile path, so the
  CUDA arm was not re-run; the gate's CUDA arm covers the device.
- **The fast lane** on the batch tree: green at the first attempt, 19:47:28 to 20:29:03 EST (42 min), 497 testset rows, 160,078 passing assertions, 0 failed, 0 errored, exit 0 (`result/gates/pmb/fast_lane.log`).
- **The full gate** at CI settings, CUDA active, the depot idle: green, exit 0, 20:31:06 to 22:10:57 EST (1 h 40 min), 515 testset rows,
  163,563 passing assertions, 0 failed, 0 errored, 3 broken
  (`result/gates/pmb/full_gate_native.log`, `run_full_gate.sh`; the gated
  working tree's id `936706b687091403c7dd943277d7c455a427a7be` in `gated_tree.txt`, the
  committed tree differing from it in this record's text only, covered by
  a final fast lane whose numbers the next ledger touch records).

## 4 The neighbour audit (scoped to the batch's diff)

The post-campaign standard of `../comprehensive_audit.md`, scoped to the
batch's diff and conducted by the batch's own session; every lead reproduced
in a fresh process before recording.

- **A-1 (confirmed, fixed before the gate): the element hint dropped the
  type.** `_toml_element_hint` rebuilt the key's `ParamMeta` through the
  five-field positional form to append the example value to its
  alternatives, so every element key reached the codec untyped and the
  evidence rules ran as before (the first green run of the codec testset:
  17 of 23, `L = true`, `L = { nothing = true }`, `L = [0.3]` accepted, the
  old "where a number belongs" wording). Repro: the testset's refusals on
  the batch tree before the fix (`/tmp/claude-dxu/pmb/b2_green.log`). Fix:
  the hint carries `pm.type`; the five-field form is kept for callers
  outside `src/` (the suite's `withmeta` helper, now passing the type).
  The lesson is the one the positional `ElementMeta` rebuild taught in
  batch A: a positional reconstruction of a record is a reader of every
  field, and a new field finds it by failing.
- **A-2 (confirmed, fixed before the gate): include order.** The cavities'
  schemas name `AbstractTurnRule`, declared in `turn_modulated.jl`, included
  after them; the first load failed by name at `crab_cavity.jl:315`. Fix:
  the root type is declared in `Knowledge.jl` beside
  `AbstractTrackingMethod`, the rule file pointing at it. Every other type
  the declarations name (`LossRecord`, `ThinStrongBeam`,
  `AbstractVirtualDrift`, `XYCouplingMode`, `AbstractElementSpec`) precedes
  its use in its own file or in `Knowledge.jl`, checked by the load.
- **A-3 (confirmed, fixed before the gate): an ambiguous class prints the
  marker.** `matrix` of `Linear6DSpec` was first declared admitting tuples
  and vectors both, which the writer's rule reads as ambiguous and prints
  as `{ tuple = [...] }`; the constructors store a 36-tuple on both forms
  (probe `/tmp/claude-dxu/pmb/matrix_probe.log`), so the declaration is
  `Union{Nothing, AbstractMatrix, Tuple{Vararg{Real}}}` and the matrix form
  prints a plain array. A raw spec storing a `Vector` matrix is refused at
  write by name, the documented consequence of a stored class outside the
  declaration.
- **A-4 (confirmed, fixed before the gate): a matrix's cells inherited the
  matrix's class.** The `{ matrix = [[row], [row]] }` branches coded every
  cell with the parameter's own hint, so a `Union{Nothing, AbstractMatrix}`
  declaration refused its own cells on reading (`a float 1.0e-6 where the
  kind declares Union{Nothing, AbstractMatrix}` at
  `GAUSSIAN_STRONG_BEAM.thin.covariance.[1,1]`, the per-kind round trip
  extracted, `/tmp/claude-dxu/pmb/extracted_final2.log`). Fix: the cells
  take the element class as their hint, as the tuple and vector items do
  (`_toml_item_hint`, now for matrices too; `AbstractMatrix` without an
  element type gives none, so the cells follow the evidence rules).
- **The stage-4 reader pin moved with the wording.** `D.L = "0.5"` is
  refused as `a bare string "0.5" where the kind declares Real` (the pin
  read `where a number belongs`, the evidence wording an untyped key still
  gets).
- **Clean by reproduction.** The positional `ParamMeta` constructions in
  `src/` (two: `_placement_param`, `_toml_element_hint`) both carry the
  type; no `ParamMeta(` site in `src/` is untyped (grep) and the validator's
  registry sweep agrees (681 of 681); the objects' option metadata (hooks,
  markers, solvers, schedules, rules) is not a `ParamMeta` and keeps the
  evidence rules, their round trips green in the extracted codec blocks;
  the registry snapshot is byte-identical (the help text is not in it);
  the one suite pin of the help suffix (`y_offset`) moved with the text;
  the fingerprints are identical on CPU, as a batch touching no compile
  path must leave them; `Base.uniontypes` is `Base`-internal (present since
  1.0), a risk to know as `Base.kwarg_decl` is, failing loudly at load if
  renamed.
- **Not read, stated:** the CUDA kernels and the MPI extension (no change;
  the gate's CUDA arm covers them); the translators (none).

## 5 What stays open

- Batch C, the ramp (R7).
- The D17 translators may now read a foreign value into every parameter's
  declared class; the translation tables are theirs to write.
- The owner may overrule any declared class; the validator names the kind
  and the parameter when a declaration and a stored value disagree.

## 6 The previous push's ledger

Batch A was pushed 2026-11-26 as cb4045e; its CI run (495, head
cb4045e, id resolved by the watcher `result/gates/cp1/ci_watch.sh`) ran
2026-11-26 23:38:55 to 2026-11-27 01:17:41 UTC (1 h 38 min 46 s): success, the
"Julia 1.12 CPU full-lane tests" job green (`result/gates/cp1/ci_watch.log`).
The final fast lane of batch A on its committed tree, which its record could
not carry: green, 495 rows, 160,032 passing assertions (17:51 to 18:32 EST).
