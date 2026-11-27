# The suite split: a driver, `test/suite/`, `only=<file>`, and the first peel (2026-11-27)

The single 48,208-line `test/runtests.jl` became a driver over files under
`test/suite/`, with `only=<file>` selection, a layout tripwire, a parser
module every suite tool reads a file through, a block mover, and the first
area peeled off; the same batch added the `particle_id` keyword to the
snapshot reader. This record holds the measurements that priced the
decision, what landed, the red-first evidence, the checkpoints and the gate.
Design and rules: [`../design/testing_lanes.md`](../design/testing_lanes.md)
(sections 1, 4 and 5); the open row for the remaining peels is in
[`../todo.md`](../todo.md).

## 1. Why: the gate outgrew the decision that priced it

| Measurement | Value |
|---|---|
| Full gate when the per-push rule was priced (2026-09-04, `experiences.md`) | 24.5 min |
| Full gate on 2026-11-27 (`machine_description_reference_ramp_2026_11_27.md`), CUDA active, 519 rows | 100 min |
| Fast lane the same day, 498 rows | 41 min |
| Top-level testset times summed over that gate's log | 98.3 min |
| "The multi-process seam runs under an MPI launcher" | 22.3 min |
| "Every example script runs against the current interface" | 13.0 min |
| "CUDA-requiring validation scripts run in the gate's CUDA arm" | 8.8 min |
| Bare `using Octopus` (precompiled) | 5 s |

The gate is all testset time; the three subprocess-bound sections are 44
of its 100 minutes, and the fast lane already skips them. Positive
selection -- one file plus the structural sweeps -- was the lanes note's
"natural v2", blocked on splitting the file (section 5 of the note as it
stood since 2026-08-13).

What the file looked like before the cut (measured on `3cf452c`):

- 503 titles at column 0: 486 `@testset` blocks and 17 lane-gated
  `if _lane_gate(...)` blocks; no duplicate titles.
- Ordered by campaign date, not by area: machine-description testsets near
  lines 22,000 and 45,000, run-artifact testsets at 25,000, 28,000 and
  30,000, turn modulation at 12,000 and 32,000. A split by area is a
  regrouping, not a cut into ranges.
- 184 file-level names outside the testsets (about 2,700 lines): 130
  helper functions, 25 fixture structs, 32 constants. 108 used by more than
  one testset, 7 by testsets more than 5,000 lines apart
  (`CUDA_TESTS_ACTIVE` in 49 blocks, `test_beam` in 10, the stage 6 pin
  pair, two test observers, `transition_reference`). The rest are local to
  a neighbourhood and travel with it.
- A keyword pass over the gate log, grouping titles into prospective files
  (approximate; 85 titles matched no keyword): analysis and Twiss 87
  testsets / 6.3 min, strong-strong 76 / 8.6, lattice and machine
  description 63 / 4.7, elements and tracking 55 / 1.9, CUDA parity
  50 / 6.4, run artifact and observers 41 / 3.5, turn modulation 10 / 4.4,
  the MPI seam 13 / 26.2, examples and CUDA validation 2 / 21.7, the
  structural sweeps 24 / 4.1.

## 2. What landed

**The driver, `test/runtests.jl` (147 lines).** The lane preamble as before;
`only=<file>[,<file>]` parsed beside `lane=`, every other argument an
error; the test-only `using`s; `include` of `test/suite_structure.jl` and
`test/suite/common.jl`; the layout tripwire (below); the include loop over
`_SELECTED_FILES` (`core.jl` always, then the selection or every file in
`_SUITE_FILES` order); the lane banner as before and an `only=` banner
naming every file not run.

**`test/suite/common.jl` (63 lines).** `_SUITE_FILES` (the include order:
`core.jl`, `legacy.jl`, `artifact_observers.jl`), `_suite_dir()`,
`_suite_files_all()`, `_suite_lines()` and `_suite_text()` -- the suite's
text as one line vector, which the five pins that audit the suite's own
text now read (the stage 6 pin tripwire `_st6_pin_lines`, the GPU-only
block count, the seed-copy check, the declared-classes pin, the
wrapper-walk pin; each read `test/runtests.jl` by path before) -- and
`CUDA_TESTS_ACTIVE` with its rationale comment moved from the old head.

**`test/suite/core.jl` (817 lines, 12 testsets).** The structural sweeps
every run executes: "CUDA coverage status", "Architecture integrity",
"every public configuration schema is exported", "No method grows a
Core.Box outside the argued allowlist", "Every export is documented",
"Observer schema keys must name public fields", "The module precompiles
without overwriting its own methods", "Metadata queries and the validator
check declarations, not themselves", "No docstring is detached by comment
lines", "The documented configuration-status vocabulary is the real one",
"Every exported API name appears in the registry snapshot", "Every registry
type describes itself". Membership is a judgment (a sweep over the whole
module, cheap, no physics), renewed when a testset lands, as lane
membership is.

**`test/suite/legacy.jl` (47,301 lines after stage 1, 43,397 after the
peel).** The single file's body in its original order, the `const
CUDA_TESTS_ACTIVE` line and the structural sweeps removed, with eight
`dirname(@__DIR__)` roots rewritten to `pkgdir(Octopus)` (an included file's
`@__DIR__` is `test/suite/`) and the five suite-reading pins rewritten to
`_suite_lines()` / `_suite_text()`.

**`test/suite/artifact_observers.jl` (3,898 lines).** The first peel: 23
testsets whose subject is the run artifact, a reader or an observer, with
the 12 fixture structs only they use and those structs' 17 `Octopus.`
methods; the file's header states the membership rule. Titles preserved:
503 across the files, as before.

**The layout tripwire** (the driver's first testset, every lane, every
selection): `readdir(test/suite)` equals `common.jl` plus `_SUITE_FILES`
(a file nobody includes is a check that never runs); block titles and
column-0 helper names are unique across the files; no file reaches for a
helper another file defines, `common.jl` excepted. The rule is a function,
`suite_cross_references`, shown failing inside the testset on a synthetic
pair for each of its three clauses before it is applied to the tree, where
it reports zero violations.

**`test/suite_structure.jl`.** The one parser of a suite file: top-level
expressions through `Meta.parseall` with their line spans, the comment run
directly above each, kind (`:testset`, `:gated`, `:block`, `:def`,
`:method`, `:using`, `:other`) and name; `unit_symbols` for references,
`unit_names` for destructuring consts, `suite_cross_references` for the
rule. The first version of the mover was a regex over column 0 and was
measured wrong in 24 places (the lesson in `experiences.md`, "A suite file
is addressed through the parser"): the lane-gated testsets sit at column 0
inside their `if`, and column-0 `end`s close indented openers. The parser
accounts for every line of the old file: 732 units, zero unowned code lines,
zero overlaps.

**`test/move_testsets.jl`.** Moves blocks by title and helpers by name from
one suite file to another, the comment run above each carried, source order
kept, blank runs folded; reports the helpers the moved units still reach for
in the source (and whether the source still uses them too, so the reader
knows which go to `common.jl`), re-parses both results, exit 1 on a title
not found exactly once.

**`test/run_extracted_testsets.jl`.** Finds a block by title across the
files, includes `common.jl`, and evaluates the block's own file's
definitions it reaches for, transitively (a helper's helpers, a test
observer's methods), in source order -- the resolution the single-file
runner lacked (it evaluated the test observers only).

**`validation/twiss_dispersion_acceptance_windows.jl`.** Read
`test/runtests.jl` by path to cut its `_st3_` / `_st4_` fixture helpers out
by name; nothing in the suite runs it, and only a grep for the file name
found it. It now reads the suite's files through the parser
(`definition_text`, and the stage 4 helpers as every definition from
`_ST4_SEED` to the first "Dispersion routes:" testset of their file).

**The `particle_id` keyword** on `read(::TaskOutput, :snapshot; ...)`:
symmetric with `turn`, the same one-Integer form, a row mask on the
snapshot's `particle_id` column; the two together select one row; an
absent id reads as empty columns; refused by name with any other kind,
without a `name`, and on the single-product kinds. Both masks go through
`_ra_keep_rows`, a function of its own so that no generator in `read`
captures a reassigned local (the `Core.Box` class). Docstrings of `read`
and `CoordinateSnapshotObserver`, the `RunArtifact` docstring example and
`docs/public_api.md` carry it; the registry snapshot is unchanged
(regenerated, zero diff).

**A finding of the reordering.** The first fast lane on the split tree went
red after 231 rows (11:54:30 EST, `result/gates/split/fast_lane_red_u12_8.log`)
at "Machine description: the class form derives a spec from a template of
its kind on every friendly constructor ...": walking the registry, it called
`DriftSpec(template)` and was refused with "the template is a drift spec,
not a u12_8_probe". The U12-8 control of "Metadata queries and the validator
check declarations, not themselves" (now in `core.jl`, so it runs first)
registers a scratch kind with `DriftSpec` as its friendly constructor and
restores the four registry containers afterwards; since 2026-11-26
`register_element_meta!` also installs the class form
(`_install_class_form!`, R11 of the machine-description follow-ups), a
method no container holds, so the control left `DriftSpec(template; ...)`
bound to the scratch kind. In the single file every consumer of the drift's
class form ran before that block, so every gate since the method landed was
green with the leak in it. The control now reinstalls the drift's class form
from the restored meta, and a testset after it ("The U12-8 probe leaves the
drift's class form as it found it") checks from outside the block (the
`@eval`ed method is a world-age matter inside it); red before the repair,
`red_u12_8_class_form.log`, green after with the machine-description
testset in the same process, `green_u12_8_class_form.log`. The
registration's silence about rebinding an existing friendly type is a
source-side question for its own batch (the todo row). No other test-side
registration borrows an existing friendly type (the stage 6 liars use their
own `_St6LiarFriendly`).

**Pointers.** `AGENTS.md` (the source-map bullet, the matrix's command
block and the test-infrastructure row), the lanes note (status, sections
1, 2, 4, 5), `guides/development_workflow.md` ("Iterating on one
testset"), `guides/configuration.md`, `guides/elements.md`,
`design/turn_modulation_record.md`, `validation/README.md` (four
passages), `docs/README.md` (the lanes entry and this record), the comment
pointers of twenty `validation/` and `profiling/` scripts and three
harnesses ("`test/runtests.jl` reads the line below" -> "the suite reads
the line below"), the docstrings of `src/contracts/twiss_dispersion_identity.jl`
and `src/math/counter_rng.jl` that named the file. Left as written: dated
narratives in `experiences.md`, `history/`, `design/linear_optics.md` and
`validation/high_energy_weakstrong_limit.jl` that describe the file as it
was.

## 3. Red first

- The reader testset "The run artifact carries the strong-strong luminosity
  channel" with the `particle_id` assertions added, extracted against the
  unchanged source (`result/gates/split/red_particle_id.log`): 56 passed,
  1 errored, the error `kwerr(::@NamedTuple{name::String,
  particle_id::Int64}, ...)` -- the keyword refused by the method, the
  defect's own reason. Green after the change
  (`green_particle_id.log`): 93 of 93, 1 min 03 s.
- The layout rule's three clauses each fail on a synthetic pair inside the
  tripwire testset (a helper used across files; a title in two files; a
  helper defined in two files) and pass on the tree.
- The U12-8 class-form control: "The U12-8 probe leaves the drift's class
  form as it found it" red after the unrepaired control in the same process
  (`red_u12_8_class_form.log`: `ArgumentError: DriftSpec(template; ...): the
  template is a drift spec, not a u12_8_probe`), green after the reinstall,
  2/2, with "Metadata queries ..." 23/23 and the machine-description
  class-form testset 135/135 behind it (`green_u12_8_class_form.log`).
- The mover's dry run before each cut named the helpers across the cut;
  stage 1 named `CUDA_TESTS_ACTIVE` (to `common.jl`), the peel named the
  twelve fixtures (moved along, none used by the remaining file).

## 4. Checkpoints and the gate

All on the GPU node (`sapphirerapids`, one RTX 4500 Ada), four threads.

- `Pkg.test(test_args=["only=core"])`: 13 rows (the tripwire and the twelve
  sweeps), exit 0, 3 min 29 s wall (11:08:44 to 11:12:13 EST), "Architecture
  integrity" 2 min 09 s; the banner `=== ONLY core: 1 suite files NOT RUN
  === / not run: legacy.jl` printed (`result/gates/split/only_core.log`;
  stage 1 tree, before the peel).
- The three source sweeps extracted on the final tree
  (`sweeps_extracted.log`): the `Core.Box` sweep 5/5, the detached-docstring
  sweep 11/11, the stage 6 testset with the pin tripwire reading the suite
  through `_suite_lines()` 179/179.
- `Pkg.test(test_args=["only=artifact_observers"])` on the split tree: 36
  rows (the tripwire, the twelve sweeps, the 23 artifact and observer
  testsets), exit 0, 8 min 08 s wall (11:22:29 to 11:30:37 EST,
  `only_artifact.log`); the banner named `legacy.jl` as not run; the four
  method-overwrite warnings of the schema testsets as in every gate.
- `validation/twiss_dispersion_acceptance_windows.jl` on the split tree
  (`acceptance_windows.log`): exit 0, the 352-line table written to
  `result/twiss_dispersion_acceptance_windows.md`, all ten PROVISIONAL
  windows (`c_coast` to `c_triple`) inside their sources, as before the
  split.
- The fast lane, first attempt (`fast_lane_red_u12_8.log`): red at 11:54:30
  EST after 231 rows, the U12-8 class-form leak above; exit 1.
- The fast lane on the final tree (the second attempt, after the U12-8
  repair): green: exit 0, 503 top-level rows, 160,221 of 160,225 pass, the three Broken rows the lane always carries ("Misalignment maps" 2, the `@elements` expansion 1, the one-particle probe's two-rank arm the lane skips 1), 18 sections skipped and named in the banner, 41 min 44 s (12:09:06 to 12:50:50 EST, `fast_lane.log`).
- The full gate at CI settings, CUDA active, on the final tree: [GATE].

Not verified: hidden order dependence beyond what the full gate's single
order exercises (the artifact file now runs after `legacy.jl`, so every
legacy testset keeps its relative order and the artifact testsets run later
than they did; `core.jl` running first is the reordering that surfaced the
U12-8 leak); CI (the push awaits the owner's word); the keyword pass's area
assignment, which the next peels measure one at a time.
