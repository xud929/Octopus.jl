# The machine description, stage 3: `Machine`, the task constructors accepting a machine, the strong-strong example as two lattices (2026-11-25)

Stage 3 of [`../design/machine_description.md`](../design/machine_description.md),
section 3: decision D5 as the namespace of lattices and shared knob roots,
the machine-level half of D7's tripwire, and D15 reaching `StrongStrongTask`
and `one_turn_matrix`, after the stage-2 record
[`machine_description_stage2_2026_11_25.md`](machine_description_stage2_2026_11_25.md)
and the reference batch
[`machine_description_reference_2026_11_25.md`](machine_description_reference_2026_11_25.md).
Guides: `../guides/development_workflow.md`,
`../guides/examples_and_validation.md`, `../guides/documentation.md`. Branch
`md3`, worked in unit worktrees off the reference batch's tree (7ea4f1f on
the `ref` branch, the tree `main` carries as ed7e283) and replayed onto
`main` as a linear tail: the skeleton 304ecc8 (the `Machine` docstring as
the specification, the stubs, the task-side forwards, the test anchors),
unit A 9789c21 and its follow-up f17b100, unit B 0cfbb18 and its
multi-process arm 420ddb4, then the record commit that follows them with the
regenerated snapshot and the docs (unit C's drafts, filled from the unit
reports and the logs). The commit messages carry the fast lane and the gate.

## 1 What landed

- The skeleton (304ecc8; `src/lattice/Machine.jl` +161, `src/Octopus.jl`
  +5/-4, `src/tasks/Tasks.jl` +8, `src/tasks/strongstrong/interface.jl` +21,
  `src/analysis/one_turn_matrix.jl` +5, `test/runtests.jl` +11, `AGENTS.md`
  +2/-1): the `Machine` docstring written first as the specification the
  units filled; `include("lattice/Machine.jl")` after `Lattice.jl` and before
  the beam, the one-turn-matrix helper and the tasks; the task-side forwards
  `_element_tuple(::Machine)`, `_describe_map`, `_source_kind` and
  `_linearizable` of a `Machine`, each through `_machine_only_lattice`; the
  two `StrongStrongTask` machine forms with their docstring; the `[MD3-A]`
  and `[MD3-B]` test anchors; the `src/lattice/` source-map bullet naming
  `Machine`.
- Unit A (9789c21, follow-up f17b100; `src/lattice/Machine.jl` +140/-18,
  `src/lattice/Lattice.jl` +31/-11, `src/tasks/strongstrong/interface.jl`
  +40/-3, `test/runtests.jl` +346): `Machine(name; lattices, knob_root = nothing)`,
  a record of the facility's lattices by name in declaration order and the
  knob roots they share. `lattices` is a `Lattice` or a tuple or vector of
  them, at least one, normalised by `_machine_lattices`: an empty tuple, an
  entry that is not a `Lattice` (a bare `BeamLine`, a tuple of elements) and
  two lattices of one name are refused by name, each message starting
  `Machine("<name>"):`. `knob_root` takes the spellings `Lattice` takes
  (`Symbol`, `String`, a tuple or vector of them) through the shared
  `_lattice_knob_roots`, which gained a `who` argument so the refusals name
  `Machine` where they named `Lattice`. The machine-level tripwire
  `_machine_check_knob_roots` runs at construction: a root two or more
  lattices declare must be among the machine's shared roots (refused by name
  with the root, the lattices declaring it and the remedy, `knob_root =
  :<root>` on the machine when the sharing is intended, a root of its own per
  lattice otherwise), and no two distinct roots of the machine, the lattices'
  and the shared ones together, may overlap as dotted prefixes
  (`_knob_root_overlaps`: `ring` and `ring.arc` overlap, `ring` and `ringx`
  do not, equal roots are one root). Nothing else is checked: each lattice
  checked its knob dependencies and numeric type when it was built, and a
  machine may hold lattices of different numeric types and references. The
  implicit one-lattice machine made explicit, `Machine(lattice) ==
  Machine(lattice.name; lattices = (lattice,))`. The readers: `machine[:ESR]`
  and `machine["ESR"]` (an unknown name refused listing the names held),
  `keys` (the names in declaration order, as strings), `haskey`, `length`,
  iteration over the lattices, `eltype(Machine) == Lattice`; structural `==`
  (names, shared roots, the lattices pairwise in order by `Lattice`'s
  equality) with a consistent `hash`; a one-line `show`. The consumers: a
  one-lattice machine enters `TrackingTask`, `analyze` and `one_turn_matrix`
  through `_machine_only_lattice`, and a machine of several lattices handed
  where one line is wanted is refused by name with the machine, its count
  and names, the consumer asking and the remedy (`machine[:NAME]`, or the
  pairing form). `StrongStrongTask(machine, :A, :B; kwargs...)` pairs two
  lattices by name (`Symbol` or `String`; beam 1 tracks the first; the same
  name twice is legal) and is `StrongStrongTask(machine[:A], machine[:B];
  kwargs...)`, the line form that has taken two `Lattice`s through
  `_element_tuple` since stage 2; `StrongStrongTask(machine; kwargs...)`
  takes a machine of exactly two lattices in declaration order and refuses
  any other count by name with the pairing form as the remedy. In every form
  the task stores the placements the lattice's bare line gives, so the
  compiled runtime, the kernels and the per-turn work are the tuple
  spelling's. Found and closed on the way, by the compiled-runtime pin: a collision
  marker placed in a line (a `LineEntry` whose spec is the
  `StrongStrongCollision`, which is every `BeamLine`, `Lattice` and `Machine`
  spelling of a strong-strong line) was recognised by `_append_strong_strong_line!`
  through `::StrongStrongCollision` dispatch only, fell to the element arm,
  compiled as a physics entry and was called as a map at the first turn (a
  `MethodError`; the stage-2 pin had compared the task's entries and never
  compiled them, so `StrongStrongTask(lattice1, lattice2)` constructed and
  died at `execute!`). A `LineEntry` arm now cuts the line at a wrapped marker
  and otherwise takes the element path (`_append_strong_strong_element!`);
  the regression test is the stage's StrongStrongTask testset, red before the
  fix (unit A's probe run 2: three failures and one error), green after; the
  walker audit of section 2 found no second site. Also found and closed: a
  lattice declaring nested roots, `knob_root = (:ring, "ring.arc")`, or one
  root twice, is refused by name by `_lattice_knob_roots` (a knob under
  `ring.arc` is under `ring` already), the machine-level overlap rule applied
  to one record; the repository's multi-root spellings (the stage-2 tests'
  `(:md2a_ring, :md2a_ip)` pairs, the docstring examples) nest nowhere, so no
  caller changed. Testsets, below the `[MD3-A]` anchor: "Machine description:
  a Machine holds lattices by name and the implicit one-lattice machine equals
  the explicit one" (35), "... the machine-level knob-root tripwire refuses an
  undeclared shared root and overlapping roots" (12), "... a one-lattice
  machine is accepted where a line is and a machine of several is refused by
  name" (11: `TrackingTask(Machine(lattice))` against the bare tuple bit for
  bit after three turns on CPU threads, the one-turn matrix and the Twiss
  analysis equal, the three refusals), "... StrongStrongTask takes a machine
  and compiles the runtime the tuple spelling compiles" (19: the placements'
  specs the tuples' objects, the compiled runtime blocks of both routes of
  identical type and equal field by field, `configuration_report` equal field
  by field, both beams' coordinates bit for bit after three turns for the
  tuple, the named and the bare machine form, the duplicate-stream warning
  raised by both spellings, the refusals), every refusal shown red by name and
  every identity with an anti-vacuity arm; the stage-2 testset "... a Lattice
  wraps a line and is accepted where the line is" gains the nested-root arm
  (42).
- Unit B (0cfbb18, the multi-process arm 420ddb4;
  `examples/strong_strong_tracking.jl` +31/-8, `src/examples/Examples.jl`
  +8/-3, `profiling/machine_description_parity.jl` 429 lines, 514 with the
  arm, `validation/README.md` +1, `test/runtests.jl` +66): the shipped strong-strong example
  declares its two rings as lattices, `Lattice("ESR"; ...)` around the
  electron line with the electron `ReferenceParticle` as its entrance
  reference and `Lattice("HSR"; ...)` around the proton line with the proton
  one (no knob roots: the script reads no knob), gathers them in
  `Machine("EIC"; lattices = (esr, hsr))` and builds the task as
  `StrongStrongTask(machine, :ESR, :HSR; ...)`; the input block, the beams,
  the solver and the observers are untouched and the same element objects
  enter the two lines in the same order, so the fingerprints of section 3 are
  the receipt. The catalogue entry lists `Lattice` and
  `Machine` among the example's objects. The parity driver
  `profiling/machine_description_parity.jl` (header: fixed point, digest)
  builds one case twice, from the tuple of elements and from the machine,
  and times the two routes interleaved (A, B, A, B, ...) so that whatever
  drifts during the run moves both alike: per route the median and minimum
  seconds per turn, the median allocated bytes per turn, and the digest of
  the tracked coordinates after the run, which must be equal between routes;
  a control route (the tuple spelling built a second time) as the noise
  floor every other route is read against, the beams rebuilt from one seed
  per run so every route starts bit for bit alike, two warm-up executions per
  route (a task's first and its first repeated execution compile different
  paths), the device synchronised around every CUDA run, and a verdict line
  (PASS when the digests agree; REPORT when they differ while the control
  differs too, the PIC deposit's atomics on CUDA; FAIL with exit 1 when they
  differ and the control does not); arms for CPU threads, CUDA
  (`OCTOPUS_USE_GPU=1`) and `MultiProcessExecutionPolicy`
  (`OCTOPUS_USE_MPI=1` under `mpiexec`, following the harness
  `test/examples/strong_strong_tracking.jl`: every rank builds its shard from
  the seed, a barrier before every timed run, the per-rank medians reduced to
  the maximum over ranks, the shard digests gathered in rank order, the
  verdict's quantities all-reduced so every rank exits alike). The gate's CUDA
  arm runs the deterministic weak-strong case at a reduced size (the
  `GATE-CUDA-ARM` line; the row in `validation/README.md`, 88 s). Testset,
  below the `[MD3-B]` anchor: "Machine description: the shipped strong-strong
  example declares two lattices in a machine whose placements the task holds"
  (15: the example included into a sandbox module with its execution keyword
  mapped to `:threads` once, asserted; the machine's keys in order, the two
  distinct references, the task's 13 and 12 placements carrying the lattices'
  own spec objects, the one marker in both lines, the artifact's two luminosity
  rows).
- Docs (unit C): `public_api.md` ("Describe A Lattice" gains the `Machine`
  paragraph, its example lines and `?Machine`; "Build And Execute Tracking
  Workflows" names the lattice and machine forms of the two task
  constructors), the design note's banner, D5's dated status and the staging
  item, `README.md`, `todo.md`, this record; `knob_control.md` untouched,
  since its section 2 does not name `Lattice`'s roots, so the machine-level
  roots are documented on the `Machine` docstring and in the design note;
  the snapshot regenerated at the fold (the `Machine` export entering the
  wrapped export list, 52 lines reflowing, and the strong-strong example's
  Objects line gaining `Machine`, `Lattice` and `BeamLine`).

## 2 Decisions

- The machine stores its lattices and its shared knob roots, nothing else.
  D5 lists reference particles and beam definitions among a machine's
  definitions; neither is stored in this stage because no runtime consumer
  reads a machine-level one: a `Lattice` carries its entrance reference (D3)
  and `Beam` and the cavities take that object directly since the reference
  batch, while a beam definition has no consumer until the TOML form (stage
  4) or a task reads it. A field no consumer reads is a configuration the
  code did not read, which the invariants count as a defect, so the two are
  deferred and the question whether the machine should hold them at all, or
  the snapshot carries them, goes to the owner (section 4, `todo.md`).
- The same lattice name twice, `StrongStrongTask(machine, :RING, :RING)`,
  is legal: two beams in one ring is the shape the strong-strong contracts
  build their cases in (one line, two beams), and the line form has always
  accepted one line twice; refusing it on the machine would refuse the
  contracts' own shape.
- `StrongStrongTask(machine)` without names reads declaration order, beam 1
  tracking the first-declared lattice, and accepts a machine of exactly two
  lattices; any other count is refused by name with the pairing form as the
  remedy, since the convenience is unambiguous only when there are two.
- A machine of several lattices handed where one line is wanted
  (`TrackingTask`, `analyze`, `one_turn_matrix`) is refused by name, never
  resolved to its first lattice: loud beats silent, and the remedy
  (`machine[:NAME]`, or the pairing form) is one spelling away.
- The machine-level tripwire is the machine's half of D7 and checks the
  roots only. The knob registry is process-global and its namespaces are
  names, not modules (`knob_control.md`, section 2), so two lattices
  declaring one root read one set of knobs whether or not anyone meant them
  to: a root declared by two lattices must be declared shared on the machine
  (the half crossing angle both rings' boosts and crab cavities read), and
  two distinct roots must not overlap as dotted prefixes, or every knob
  under the longer would sit under both. Equal roots are one root, and
  `ring` and `ringx` do not overlap, the `_knob_under_prefix` rule. The
  lattices' own dependency and numeric-type checks are not repeated, and a
  machine may hold lattices of different numeric types and references,
  since no consumer reads two of them as one.
- One root normaliser for both records: `_lattice_knob_roots` gained a `who`
  argument so `Machine`'s refusals name `Machine`, instead of a copy of the
  function with the word changed. The same normaliser now refuses nested or
  repeated roots on one lattice: the machine-level overlap rule would have
  refused a machine holding a lattice the lattice constructor accepted, and
  one rule for both records (a root is declared once, and never under another
  declared root) is the cheaper convention to carry. An acceptance narrowed on
  a stage-2 object, so the blast radius was measured first: every multi-root
  spelling in the tests, the examples, the validation scripts and the docs
  was listed, and none nests.
- The collision-marker fix lives in the strong-strong compile walker
  (`_append_strong_strong_line!`), not in the machine forms: a `LineEntry`
  arm that cuts at a wrapped marker and otherwise takes the element path is
  the one place every line spelling passes, and the alternative, unwrapping
  markers in `_element_tuple`, would have made the lattice's placements differ
  from the bare line's and broken the stage-2 identity pin. The neighbour
  audit (unit A, the same day) walked every reader of `task.line1`/`task.line2`
  in `interface.jl`: the constructor's duplicate-stream warnings
  (`_collect_radiation_ids!`, `_collect_turn_modulation_streams!`), the loss
  record's aperture collection, the survey's `_collect_spec_s!`, the
  knob-parameter check, the resolved-table check and the block readers
  (`_collision_solver`, `configuration_report`, `_validate_strong_strong_blocks`)
  all unwrap a `LineEntry` or read compiled blocks where markers are already
  cut; no second site needed a fix, and two of them are now pinned by the
  stage's StrongStrongTask testset (the report equality, the warning).
- The driver's multi-process arm follows the harness, not the suite's MPI
  contract child: the owner's requirement names MPI, so the parity is
  measured under `MultiProcessExecutionPolicy` with the same routes and the
  same verdict rule, every rank reaching one verdict; it needs Octopus loaded
  as a package beside MPI and MPICH_jll (a scratch environment made with
  `Pkg.develop`; the driver's header gives the recipe), which is why the
  first version refused the switch by name.
- A per-execution bookkeeping cost on lines spelled through placements is
  accepted and recorded, not hidden: the lattice and machine routes of the
  weak-strong case allocate about 410 bytes more per `execute!` call than the
  bare tuple (138 bytes per turn at 3 turns, 41 at 10, the product constant),
  a fixed cost per call and not per-turn work, with the per-turn time within
  the repeat spread; the strong-strong case shows no systematic difference.
  Its site is untraced (a candidate: a provenance string built once per
  execution for the placements) and is a lead for the stage-5 audit.
- Not a Core Object (D16): a record over the lattice layer like `Lattice`
  and `LinearOptics`, exported and in the snapshot, with no abstract root and
  no registry category.
- Performance parity is argued by construction and shown by measurement
  (the owner's ask: the description must not hurt CUDA, MPI or threads, nor
  any contract, and must give the results the tuple spelling gives). By
  construction, the task stores the placements the bare line gives, so the
  compiled runtime, the kernels and the per-turn work are the tuple
  spelling's, and the suite pins it by comparing the compiled runtime blocks
  and the tracked coordinates of the two spellings; the contracts build
  their cases from tuples and lines and are untouched. By measurement, the
  parity driver's interleaved A/B (section 3): a route that costs more per
  turn than the other, or allocates more, or ends at a different digest,
  would be a defect of the stage, not a property of the description.

## 3 Verification

- Extracted per unit, in package mode (`test/run_extracted_testsets.jl`),
  before each unit's commit (the unit reports, logs under the scratch
  directory of the day): unit A's four testsets 35, 12, 11 and 19 of as many,
  the stage-2 testset it touched 42 of 42; unit B's testset 15 of 15; the three
  source sweeps "Every export is documented" 1, "No docstring is detached by
  comment lines" 11, "No method grows a Core.Box outside the argued allowlist"
  5 in every run; "No committed script constructs a retired observer or task
  spelling" 41 (80 scripts, 0 offenders) and the catalogue tripwire "Elements
  and scripts follow-ups ... the catalogue in the snapshot" 89 of 89 (unit B).
  The arity change of `_lattice_knob_roots` (the `who` argument) covered by a
  `src/` grep of its call sites: three, the `Lattice` constructor (the default),
  the recursive call (passing `who`) and `Machine` (passing `"Machine"`). The
  StrongStrongTask testset was red before the marker fix (unit A's probe run
  2: three failures and one error, the compiled entry called as a map) and is
  the fix's regression test. Unit B's converted script exits 0 on CUDA (its
  `:auto` line found the device) and prints the machine.
- On the folded tree (2026-11-25 14:08 to 14:14 EST,
  `result/gates/md3/extracted_checks.log`): `validate_configuration_metadata()`
  `true`; `validate_element_metadata()` passed, 614 of 614 default pairs and
  34 of 34 runtime variants; `element_help` renders both forms for all 32
  kinds; the regenerated snapshot equal to the committed one. Extracted, every
  block green: "No method grows a Core.Box outside the argued allowlist" 5,
  "No docstring is detached by comment lines" 11, "Every export is documented"
  1, "Every exported API name appears in the registry snapshot" 17,
  "Architecture integrity" 50, "the Example core object answers with real
  scripts" 60, "Stage 5: every kind that declares the analysis analyzes its own
  example, or refuses it for the documented reason" 64, the stage-2 neighbours
  "Machine description: a Lattice wraps a line and is accepted where the line
  is" 42, "... the knob-root tripwire refuses a dependency outside the declared
  roots" 13, "... lattice equality is structural and the record prints" 24,
  "... the shipped DBA lattice module builds an equal lattice when included
  twice" 13, "No committed script constructs a retired observer or task
  spelling" 41, and the stage's five testsets 35, 12, 11, 19 and 15; the
  neighbour "StrongStrongTask chunking preserves stochastic physics" 12 of 12
  in a second process with its helper as the runner's prelude
  (`extracted_chunking.log`; the first process reported it errored on the
  helper it could not see, the runner's known limitation, not the tree's).
- The examples' fingerprints (SHA-256, the LinearOptics record's quantities
  and hashing rule; `ws` = `weak_strong_tracking.jl`, 10,000 particles x 50
  turns; `ss` = `strong_strong_tracking.jl`, 2,000 + 2,000 x 20 turns; `cn`
  = `crab_cavity_noise.jl`, 10,000 x 50 turns; `dba` = the DBA analysis),
  baseline the reference batch's tree (7ea4f1f, the tree of ed7e283; its CPU
  run and its two CUDA runs are the reference record's "post" logs, reused
  byte for byte as this stage's "pre") against the stage-3 tree (unit B's
  worktree after the units merged, 2026-11-25, logs copied to
  `result/gates/md3/compare/`). Only the `ss` script changed in this stage;
  the other fourteen rows pin that the new include, the new methods and the
  regenerated snapshot moved nothing else. The CUDA columns are two runs of
  the stage-3 tree, each read against the baseline run of the same index:

  | quantity | CPU threads | CUDA run 1 | CUDA run 2 |
  |---|---|---|---|
  | `ws_final_coords` | identical | identical | identical |
  | `ws_rms` | identical | identical | identical |
  | `ws_luminosity` | identical | identical | identical |
  | `ws_moments` | identical | identical | identical |
  | `ss_electron_final_coords` | identical | differs: device noise | differs: device noise |
  | `ss_proton_final_coords` | identical | differs: device noise | differs: device noise |
  | `ss_rms` | identical | differs: device noise | differs: device noise |
  | `ss_luminosity` | identical | differs: device noise | differs: device noise |
  | `ss_electron_moments` | identical | differs: device noise | differs: device noise |
  | `ss_proton_moments` | identical | differs: device noise | differs: device noise |
  | `cn_final_coords` | identical | identical | identical |
  | `cn_luminosity` | identical | identical | identical |
  | `cn_moments` | identical | identical | identical |
  | `dba_tunes` | identical | identical | identical |
  | `dba_zeta_eta_h` | identical | identical | identical |
  | `dba_point` | identical | identical | identical |
  | `dba_sizes` | identical | identical | identical |
  | `dba_residuals` | identical | identical | identical |
  | `dba_one_turn_matrix` | identical | identical | identical |
  | `dba_text` | identical | identical | identical |

  The CPU column is the proof: all twenty hashes equal the baseline's, the
  six strong-strong ones included, so the two lattices and the machine give
  the tuple spelling's numbers bit for bit. The six `ss` CUDA rows differ
  between ANY two device runs (the PIC deposit's atomics; the same six rows
  differ between the two baseline runs and between the two stage-3 runs), so
  they are read against the noise floor with the LinearOptics record's
  tolerance reader on the artifacts. Maximum relative difference per table,
  luminosity / electron moments / proton moments: the floor, baseline run 1
  against baseline run 2, 1.707e-11 / 2.357e-09 / 1.820e-09; stage-3 run 1
  against stage-3 run 2, 1.706e-11 / 1.334e-09 / 5.825e-10; across the trees,
  baseline 1 against stage-3 1, 2.146e-11 / 1.330e-09 / 1.908e-09, baseline 2
  against stage-3 2, 2.006e-11 / 2.361e-09 / 1.052e-09, baseline 1 against
  stage-3 2, 2.744e-11 / 5.551e-10 / 2.490e-09, baseline 2 against stage-3 1,
  1.625e-11 / 1.655e-09 / 9.804e-10. Maximum absolute moment difference: the
  floor 6.8e-17 (electron, `m000100`, scale 9.8e-6) and 6.8e-18 (proton,
  scale 7.2e-7); across the trees 2.4e-17 to 1.05e-16 and 2.4e-18 to 7.5e-18.
  Every cross-tree value interleaves with the same-tree ones, within 1.7x of
  the floor: nothing attributable to the spelling moved. The weak-strong,
  crab-noise and DBA artifact tables are bit-identical (every table 0.0).
- Performance parity, measured by `profiling/machine_description_parity.jl`
  (the case built from the tuple of elements, from the control, and from the
  lattice or machine; identical beams rebuilt per run from one seed; two
  warm-up executions per route, then the timed runs interleaved across routes;
  per route the median and minimum seconds per turn and the median heap bytes
  per turn; the digest of every beam's final coordinates compared across routes
  on every run). The small-size validation runs of unit B (2,000 particles per
  beam, 3 turns, 2 repeats; 2026-11-25, unit B's logs): threads `ss` PASS,
  threads `ws` PASS, CUDA `ws` PASS (digests equal), CUDA `ss` REPORT (the
  machine route's maximum coordinate difference from the tuple route
  3.316e-15, under the control route's own 4.798e-15, the atomics), and under
  `mpiexec -n 2` with `MultiProcessExecutionPolicy` (2 ranks x 2 threads, the
  scratch environment with Octopus, MPI and MPICH_jll) `ss` PASS with the
  shard digests equal on both ranks (maximum over ranks of the median s/turn
  2.383 / 2.276 / 2.270 for tuples / control / machine, bytes per turn
  85,882,261 / 85,882,256 / 85,881,525) and `ws` PASS (0.004748 / 0.004714 /
  0.004796 / 0.004665 s/turn for tuple / control / lattice / machine, bytes
  per turn 20,315 / 20,315 / 20,453 / 20,453). The full-size measurement on
  the quiet machine (2026-11-25, 128-thread Xeon Gold 6430 host, RTX 4500
  Ada; 20,000 particles per beam, 10 turns per timed run, 5 repeats; CPU
  threads with 32 workers; `result/gates/md3/parity_*.log`):

  | case | backend | route | median s/turn | min s/turn | median bytes/turn | digests |
  |---|---|---|---|---|---|---|
  | `ss` | CPU threads (32) | tuples | 1.1023 | 1.0532 | 58,765,458 | equal |
  | `ss` | CPU threads (32) | control | 1.1058 | 1.0420 | 58,765,301 | equal |
  | `ss` | CPU threads (32) | machine | 1.0710 | 1.0433 | 58,765,037 | equal |
  | `ss` | CUDA (RTX 4500 Ada) | tuples | 0.12738 | 0.11918 | 47,305,379 | (reference) |
  | `ss` | CUDA (RTX 4500 Ada) | control | 0.12910 | 0.12184 | 47,305,219 | differ, max 1.73e-15 |
  | `ss` | CUDA (RTX 4500 Ada) | machine | 0.12935 | 0.12192 | 47,304,779 | differ, max 1.45e-15 |
  | `ws` | CPU threads (32) | tuple | 0.006382 | 0.005838 | 87,154 | equal |
  | `ws` | CPU threads (32) | control | 0.006421 | 0.006284 | 87,154 | equal |
  | `ws` | CPU threads (32) | lattice | 0.006347 | 0.006204 | 87,195 | equal |
  | `ws` | CPU threads (32) | machine | 0.006407 | 0.006344 | 87,195 | equal |
  | `ws` | CUDA (RTX 4500 Ada) | tuple | 0.000890 | 0.000887 | 140,859 | equal |
  | `ws` | CUDA (RTX 4500 Ada) | control | 0.000889 | 0.000887 | 140,859 | equal |
  | `ws` | CUDA (RTX 4500 Ada) | lattice | 0.000906 | 0.000891 | 140,901 | equal |
  | `ws` | CUDA (RTX 4500 Ada) | machine | 0.000892 | 0.000891 | 140,930 | equal |
  | `ss` | MPI (2 ranks x 16 threads) | tuples | 0.8566 | 0.8280 | 31,236,796 | equal |
  | `ss` | MPI (2 ranks x 16 threads) | control | 0.8437 | 0.8382 | 31,236,812 | equal |
  | `ss` | MPI (2 ranks x 16 threads) | machine | 0.8460 | 0.8402 | 31,236,446 | equal |
  | `ws` | MPI (2 ranks x 16 threads) | tuple | 0.005971 | 0.005875 | 46,366 | equal |
  | `ws` | MPI (2 ranks x 16 threads) | control | 0.006046 | 0.005984 | 46,366 | equal |
  | `ws` | MPI (2 ranks x 16 threads) | lattice | 0.005968 | 0.005927 | 46,408 | equal |
  | `ws` | MPI (2 ranks x 16 threads) | machine | 0.005998 | 0.005954 | 46,408 | equal |

  The MPI rows are the driver's multi-process arm under `mpiexec -n 2` with
  `MultiProcessExecutionPolicy` (2026-11-25 14:39 to 14:44 EST,
  `result/gates/md3/parity_ss_mpi.log`, `parity_ws_mpi.log`; the scratch
  environment holds Octopus as a package from the unit-B worktree at c4e6a95,
  whose code is this tree's), each rank timing its own shard: the numbers are
  the maximum over the two ranks of the per-rank medians and minima, the
  digests the hash of the ranks' shard digests in rank order.

  Verdicts: `ss` CPU threads PASS (every run's digests equal across the three
  routes, both beams); `ss` CUDA REPORT (the digests differ between every
  pair of routes, the control's included: the PIC deposit's atomics; the
  machine route's largest coordinate difference from the tuple route,
  1.45e-15, is below the control route's own 1.73e-15); `ws` CPU threads
  PASS and `ws` CUDA PASS (the deterministic kernels: equal digests on every
  run). On CPU threads the machine route's `ss` median is 2.8 % below the
  tuple route's and within the repeat spread (the three minima agree to 1 %;
  the control itself is 0.3 % above the tuple); on CUDA the three `ss`
  medians agree to 1.6 % and the three minima to 2.3 %, the control above the
  tuple too, so the spread is the device's, not the spelling's. Bytes per
  turn agree to within 800 bytes out of 59 and 47 million (`ss`; the tuple
  route the highest) and to within 76 bytes out of 87 and 141 thousand (`ws`:
  +41 per turn for the lattice and machine routes at 10 turns per execution,
  the 410-byte-per-call bookkeeping of section 2).

  Reading rule: the machine route's median within the tuple route's repeat
  spread and no further from it than the control's, equal bytes per turn up to
  the per-execution bookkeeping of section 2 (410 bytes per call), and equal
  digests on every backend where the control's are equal. Under MPI both cases PASS: equal shard digests on both ranks on every run, the `ss` medians within 1.5 % of one another (the control the lowest), the `ws` medians within 1.3 %, bytes per turn within 370 of 31 million (`ss`) and +42 for the placement routes (`ws`). On every backend the description layer costs nothing measurable per turn and gives the tuple spelling's coordinates where the backend itself is deterministic.
- The suite's pins, by title (below the stage's two anchors in
  `test/runtests.jl`): "Machine description: a Machine holds lattices by name
  and the implicit one-lattice machine equals the explicit one" pins the
  implicit machine equal to the explicit one with an anti-vacuity arm (a
  changed parameter, name, root or order breaks it) and every reader and
  refusal; "... the machine-level knob-root tripwire refuses an undeclared
  shared root and overlapping roots" the D7 half; "... a one-lattice machine is
  accepted where a line is and a machine of several is refused by name" the
  tracked coordinates of `TrackingTask(machine)` and of the bare tuple bit for
  bit on CPU threads, the one-turn matrix and the Twiss analysis equal, the
  refusals; "... StrongStrongTask takes a machine and compiles the runtime the
  tuple spelling compiles" the two-lattice machine's lines reaching the task as
  the two tuples do (the placements' specs the tuples' objects, the compiled
  runtime blocks of identical type and equal field by field, the configuration
  report equal, the coordinates after three turns bit for bit for the named and
  the bare form, the same-name form, the duplicate-stream warning); "... the
  shipped strong-strong example declares two lattices in a machine whose
  placements the task holds" (unit B) the shipped example's machine. CUDA
  parity of the routes is the driver's, run in the gate's CUDA arm at the
  reduced size (the `GATE-CUDA-ARM` line) and at full size above.
- The fast lane and the full gate at CI settings with CUDA active ran on this
  tree after this record was written and before the final commits were made
  from it, so their numbers are in the commit messages (the feature and the
  record commit), not here: the record cannot carry the lane that covers its
  own last line. Logs: `result/gates/md3/fast_lane.log`,
  `result/gates/md3/full_gate_native.log`.

## 4 Carried and open

- Owner question (this stage): D5 lists reference particles and beam
  definitions among a machine's definitions, and the machine stores neither.
  When a consumer exists, the TOML form (stage 4) being the first candidate,
  should the machine hold beam definitions keyed like its lattices, or should
  the snapshot carry beams beside the machine and the machine stay lattices
  and roots? A machine-level reference particle has no reader as long as each
  lattice carries its own (D3), so the question is the beam's. Carried in
  `todo.md`, the machine-description row.
- From the unit reports, leads for the stage-5 neighbour audit (its lead
  list gains the stage's entry points: `_machine_only_lattice`, the two
  machine forms of `StrongStrongTask`, `_element_tuple(::Machine)` and the
  one-turn-matrix forwards): the marker fix's class, a `LineEntry` wrapping a
  non-element child reaching a walker that dispatches on the bare type (every
  `::StrongStrongCollision` and hook dispatch site outside `interface.jl` is
  unaudited; a placement override written on a marker or a hook has no
  parameters to land on and is not refused); the 410 bytes per `execute!` of
  placement-spelled lines, untraced; the `Lattice`'s nested-root acceptance
  narrowed in this stage without a deprecation (no caller used it); the
  explicit stream ids the stage-3 fixtures claim (4101, 4111, 4112) sit in
  the suite's one process and would warn, not fail, on a collision with an
  auto-assigned id; and the small-size CUDA `ss` REPORT verdict, which is the
  atomics' noise by the control's own floor and would need a deterministic
  deposit to become a PASS.
- Unchanged by this stage and still carried (the reference batch's record
  and `todo.md`, the "Knob-given values" row): no task compares the beam's
  reference with a cavity's stored pair at compile; a strong-strong `Beam`
  without `r0` gives a silent zero kick scale; and the shipped strong-strong
  example's proton beam still warns at construction about `rng_id = 2`,
  visible in every baseline and stage-3 log, since changing the ids moves
  the fingerprints the conversion exists to hold.
- Stages 4 (the TOML writer and reader, the artifact embedding; D13, D14) and
  5 (`with_overrides`, D11, then the neighbour audit over `_element_tuple`'s
  callers, the two task constructors, the placement-override guards and the
  knob epoch) remain; the design note's staging section marks item 3 landed.

## 5 Ledger and the previous push

`README.md`: this record indexed, the design entry naming the stage.
`todo.md`: the machine-description row (stage 3 implemented, what it
delivered, the owner question, the previous push's CI) and the carried row
(the stage-5 leads of section 4). `public_api.md`: "Describe A Lattice" (the `Machine` paragraph,
its example lines, `?Machine`) and "Build And Execute Tracking Workflows"
(the lattice and machine forms of the two task constructors). The design
note: the banner, D5's dated status, the staging item. The previous push:
the reference batch as c4492d5 and ed7e283 on `origin/main` (pushed
2026-11-25 13:25 EST, its tail rebuilt from the unit merge 6656d81 without
the two docs-draft commits, so no placeholder commit sits in that history),
CI run 490 (id 45674956893) ran 2026-11-25 18:25:12 to 19:39:12 UTC (74 min 0 s): success, the "Julia 1.12 CPU
full-lane tests" job green (`result/gates/ref/ci_watch.log`); no intermediate
docs-draft commit sits in that history (the skeleton-anchor commits of the unit
branches, 9e1dcb2 and e72cb10, do, each a working tree)..
