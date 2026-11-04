# The in-memory run artifact: `storage=:memory` and `save_run_artifact` (2026-11-03)

Status: decided 2026-11-03 in an owner discussion (section 1), probed the
same day before the design was written (section 2), implemented the same day
(section 3) and verified as section 4 records; the gate is section 5, the
ledger section 6. The design lives in
[`../design/run_artifact.md`](../design/run_artifact.md), "Artifact
options", the `storage` bullet; this record carries the decisions with
their reasons, the probe numbers, the red and green runs and the gate.
Bracketed `[...: pending]` markers name a measurement the record commit
after the gate fills; nothing under `result/` is cited as evidence.

## 1 The decisions

The question the owner asked: the task interface (`TrackingTask`,
`StrongStrongTask`) writes phase-space coordinates and moments to an HDF5
file; sometimes it would be convenient to keep the data in memory. Measured
first: no such facility existed -- `MomentObserver` and
`CoordinateSnapshotObserver` are artifact views that refuse at prepare
without `artifact=`, `RunArtifact` opened a path with `HDF5.h5open`
unconditionally, and only `BPMObserver` had a memory mode (centroids,
`readings`). The owner's decisions, each with the reason recorded in the
design note:

- D1 **A mode of the one artifact, never a second storage type.** 32 of the
  76 functions of `src/tasks/RunArtifact.jl` touch the HDF5 file directly
  and `TurnModulationRecorder` holds an `HDF5.File`; a pure-Julia store
  would have re-implemented the cursor, replay and ledger protocol and
  widened the nine `Union{Nothing,RunArtifact}` annotations outside the
  file. The HDF5 core driver (`HDF5.Drivers.Core(; backing_store=false)`)
  gives the same artifact in memory for one open call.
- D2 **The keyword is `storage`, with the values `:file` (default) and
  `:memory`** ("storage is fine" -- the owner; a common name, not
  "backing").
- D3 **`:memory` decides only where the rows live during the run.** A path
  given beside it keeps every other meaning: the label, the file
  `append=true` loads into memory and continues, the default save target.
  The reading "a path switches back to file mode" was rejected as a request
  the code would ignore.
- D4 **Nothing is saved automatically** at the end of `execute!`.
- D5 **The explicit `save_run_artifact(artifact[, path])`** writes the image
  to disk; the path may be omitted when one was given at construction; a
  path-less artifact must be given one.
- D6 **`append` keeps its file meaning** (section 2 made this possible): the
  image is continued across `execute!` calls within the process, a saved
  file at the path is loaded at the first window, `append=false` discards
  the previous image. The one difference left is durability: a crash keeps
  the rows through the last save, where a file run keeps them through its
  last flush.

Defaults applied beside them (stated to the owner, not objected to): a save
before the first `execute!` refuses by name; a save replaces its target
through a sibling temporary renamed into place and holds the target's
sidecar lock for the write; readers of a live or finished memory run are
`TaskOutput(artifact)` and `MomentOutput(artifact; name)`, the path readers
serve the saved file; rank 0 holds the image and saves under the
multi-process policy, every other rank's save returns `nothing`. The name
`save_run_artifact` rather than `save`: JLD2, which Octopus loads, exports
`save` (`:save in names(JLD2)` is `true`), so an Octopus export of that
name would make a bare `save` ambiguous in every session that also loads
JLD2 or FileIO.

## 2 The probes that decided the design

Scratch probes in `/tmp`, HDF5.jl 0.17 from the project environment,
2026-11-03, each run once; the numbers are recorded only here.

| probe | result |
|---|---|
| `h5open(path, "w"; driver=Core(backing_store=false))`: create a group, an extendable chunked dataset, attributes; flush; read back; close | reads back; no file on disk after the flush or the close; a re-open by path fails ("unable to determine if ... is accessible") -- the image lives only in the open handle |
| the same with `"w"` on a path holding an existing ordinary HDF5 file | the disk file is byte-identical afterwards: the driver touches no path under a create |
| `"w"` under a name in a directory that does not exist | works: the name is an identity only, so a fresh image is filed under a per-object dummy name |
| `h5open(path, "r+"; driver=Core(backing_store=false))` on an existing file, append two rows, close | the rows read in memory (`[1,2,3,4,5]`); the disk file unchanged (3 rows): an existing file is loaded into memory and never written back, which is what makes D6 possible |
| `HDF5.API.h5f_get_file_image` (size query, then the buffer) written to a path | the saved file reads the five rows; `HDF5.copy_object` works too and was not chosen (it rebuilds the file; the image is byte-identical) |
| 64 MB appended into an image in 1000 blocks of 1000 x 8 `Float64`, by the driver's growth step `increment` | 8 KiB (the library default) 41.9 ms; 1 MiB 38.8 ms; 64 MiB 19.8 ms |

The last row is why the growth step is the internal constant
`_RA_MEMORY_INCREMENT = 4 MiB` and not a public option: a factor of two on
tens of milliseconds per 64 MB, against the 27.6 ms one default moment row
costs (`docs/todo.md`, "The every-turn `MomentObserver` and artifact row
...").

## 3 What landed

`src/tasks/RunArtifact.jl`:

- the field `storage::Symbol` beside the three options, and the field
  `image::Union{Nothing,HDF5.File}` beside `file`: the image kept between
  windows under memory storage. A slot of its own, because `file !==
  nothing` means "an `execute!` is in flight" at six sites (both task crash
  paths, `_path_writer_is_live`, `finalize_run_artifact!`, the reset-trials
  bind) and keeps meaning exactly that in both storages; none of those
  sites changed;
- the constructor keyword `storage=:file`, refused by name for any value
  other than `:file` or `:memory`; the path-less `RunArtifact(;
  storage=:memory, ...)`, refused by name with `storage=:file`; the label
  `_RA_MEMORY_LABEL = "<memory>"`, refused as a path; the shared
  `_run_artifact` behind both constructors;
- the schema entry `storage` of `run_artifact_option_schema()` (category
  `:output`, consumer `:run_artifact_output`); the `:run_artifact_output`
  receipt's field `storage`, and `artifact = nothing` for a path-less
  artifact in it and in the task output receipts; the configuration
  report's `:artifact` entry saying "in memory" and naming the path only
  where one was given, the file-mode text unchanged;
- `_ra_open_memory_image!`: the open of one `execute!` under memory
  storage (the retained image continued under `append=true`, else a saved
  file at the path loaded by the core driver, else a fresh image under
  `_ra_image_name`, the previous image discarded first under
  `append=false`, no lock), called from one `if _ra_in_memory(art)` branch
  at the top of `prepare_run_artifact!`; the file-storage open -- the lock,
  `fresh`, the non-HDF5 refusal (now the shared `_ra_not_hdf5_error`), the
  `HDF5.h5open` -- stays inline in `prepare_run_artifact!` textually as it
  was. It had been extracted into one helper for both storages first; the
  first fast lane on that tree failed the replay testset's structural pin
  (F-56 (c)), which reads `prepare_run_artifact!` from the source and
  requires the literal open to precede the refusal table and the first
  ledger write inside that function. The pin held exactly as designed; the
  open went back where it guards it rather than the pin being re-anchored.
  The prepare's refusal path puts a continued image back untouched; a
  memory artifact is not entered in the in-process path registry;
- `finalize_run_artifact!` retains the image (`art.image = art.file`) where
  it closes a file;
- the lock's create and remove as path functions (`_ra_create_lock`,
  `_ra_remove_lock`) behind the artifact's own take and release, their
  messages unchanged, so `save_run_artifact` can hold the lock of its
  target;
- `save_run_artifact(artifact)` and `save_run_artifact(artifact, path)`,
  exported: the flushed image through `H5Fget_file_image`, written to
  `<path>.saving-<pid>` and renamed into place under the target's lock;
  refused by name before any `execute!`, on a `storage=:file` artifact and
  on a path-less artifact without a path;
- `TaskOutput(artifact)` (a second field, `artifact`), `_ra_open(f,
  out::TaskOutput)` as the reader's source rule (the live image for a
  memory artifact, the path otherwise), `_ra_contents` over an open handle,
  and `turn_modulation_provenance(artifact)`.

`src/tasks/BeamObservers.jl`: `MomentOutput(artifact; name)` (a third
field, `artifact`), `_is_hdf5_output(::MomentOutput)` and the three moment
readers taking the handle. `src/contracts/Contracts.jl`: the memory fixture
of `PublicConfigurationEffectivenessContract` (every artifact option away
from its default, two windows continuing the image, the gap check over its
receipts, four new resolution fields). `test/runtests.jl`: the testset "The
run artifact in memory: ..." with its throwing observer, and the two pins
that enumerate the schema keys and the receipt's property names updated to
carry `storage`. `docs/registry_snapshot.md` regenerated (one export added,
`save_run_artifact`).

Nothing in the tracking changed: no element, kernel, policy or loop file was
touched, and a `storage=:file` artifact takes the code path it took before
(the one new branch tests `_ra_in_memory` and is false).

## 4 Verification

- **Red before the feature**, the new testset run as a scratch block
  against 2f311d3 (the tree before any edit): 0 passed, 3 errored --
  `FieldError: type RunArtifact has no field storage`, `MethodError: no
  method matching RunArtifact(::String; storage::Symbol)`, `MethodError: no
  method matching RunArtifact(; storage::Symbol)`.
- **Green after it**, the same block on the implemented tree: 90 of 90
  assertions in 41.7 s. What the block asserts: the constructor and the
  metadata (section 3); the same one-particle run with the three probes in
  both storages, every moment, snapshot and BPM column equal (`==`, no NaN
  in the fixture, so bitwise), the memory run leaving no file and no lock,
  every output option carried by its receipt under memory storage
  (`_output_receipt_gaps` empty); `TaskOutput(artifact)` and
  `MomentOutput(artifact; name)` reading the live image in every form; the
  configuration report's wording in both modes; `save_run_artifact`'s four
  refusals, the default and explicit targets, the saved file reading as the
  image and as the file run, two saves byte-identical, a held lock on the
  target refusing by name and leaving the lock, and a file-mode writer
  continuing the saved file; `append=false` discarding the image,
  `append=true` continuing it in process and loading a saved file in a new
  object with the disk copy untouched until saved, the non-HDF5 refusal; a
  run failing at turn 2 keeping its image and saving it; the strong-strong
  task's luminosity channel in memory and a refused continuation (another
  collision label) leaving the image as found.
- `validate_configuration_metadata()` is `true` on the implemented tree.
- `validate(PublicConfigurationEffectivenessContract())` passed on the
  implemented tree: `output_receipt_gaps` empty, `output_receipt_pairs_checked`
  49 (four tracking audits and one strong-strong), and every resolution
  field `true`, the four new ones included (`storage_resolved`,
  `memory_continued`, `memory_on_disk_only_when_saved`,
  `memory_rows_equal_saved`).
- The suite's source sweeps run extracted (the block cut from
  `test/runtests.jl` by its title, evaluated after `using Octopus, Test`):
  "No method grows a Core.Box outside the argued allowlist" green, "No
  docstring is detached by comment lines" green, "Architecture integrity"
  (the snapshot compare and the docs index walk) green.
- The artifact testsets the change touches, run extracted the same way:
  "The run artifact records the realised turn modulation" 271 of 271 (it
  holds the schema-key pin, now naming `storage`); "Run artifact exclusion
  and seed provenance ..." green (the lock's create and remove moved into
  path functions); "Run artifact receipts and slots ..." 219 of 219 after
  two edits its derived checks demanded -- the carries-every-option loop
  read over the file fixture AND a memory sibling, since `storage=:memory`
  would move the file fixture onto a path no reader below it opens, and the
  negative control's fake receipt given `storage=:file`, so its one missing
  field stays `record_turn_modulation` (the two red runs that asked for them
  are the file's own `Evaluated: file != file` and the two-gap list).
- The first fast lane (2026-11-03, 35 min to the failure, 260 testsets
  green before it, the six heavyweight sections skipped loudly) failed ONE
  block, "F-56: a refused continuation leaves the file byte-identical" (1
  failed, 2 errored, all three the structural pin above finding no
  `HDF5.h5open(art.path` in `prepare_run_artifact!`); every other artifact
  testset was green in it, the new one included (90 of 90). The open went
  back inline (section 3).
- The fast lane on the final tree of the feature commit (2026-11-03,
  19:24 to 20:02 EST, 38 min, four threads): green, 444 testset summaries,
  "Testing Octopus tests passed", the 17 heavyweight sections skipped
  loudly with the lane's banner (the two effectiveness sections, the
  ForwardDiff pair, the curved-frame routing, every example script, the
  two-rank turn-modulation probe, the two MPI launcher sections, the
  contract coverage guards, the lattice cells, the CUDA GaussianPIC
  subtraction, the physics contracts, the two PIC sections, the PIC-family
  luminosity, the CUDA validation scripts). A checkpoint, not the finish
  line: section 5.

## 5 The gate

Public configuration is a full-gate class (AGENTS.md matrix); CUDA is active
on the development machine.

**Native arm, CUDA active, on ff54b2a** (the feature commit's tree, 0 dirty
files; host acnlinj4, 2026-11-03 20:04:23 to 21:30:29 EST, 86 min, four
threads): green, "Testing Octopus tests passed", exit 0. 460 testset
summaries, 159754 passing assertions summed over them; the one testset with
a Broken column is "Misalignment maps" (26 passed, 2 broken, 28 total), the
two pre-existing expected-broken checks every gate records separately. No
lane skip (the full lane); the CUDA arm of the validation scripts ran inside
it, 21 scripts, every exit 0, 492.2 s wall four at a time
(`validation/tracking_backend_consistency.jl` 154.1 s among them). Nothing
was unrunnable: the machine has a functional device and the MPI launcher
sections ran.

**AVX2 arm** (`OPENBLAS_CORETYPE=Haswell julia -C haswell`, the CI-runner
parity arm of the two-arm pre-push gate): not run in this session. It is
owed before the push that carries this batch, not before the commit (the
owner's gate-before-push decision, `../experiences.md`, "Process habits that
earned their place"); the script `result/in_memory_artifact/run_full_gate_avx2.sh`
is prepared for it. Nothing in this batch is pushed.

**Addendum, 2026-11-04 (the paragraph above stands as written at commit
time; this is the correction beside it).** The batch was pushed on
2026-11-03 at 23:25 EST as 2f311d3..a232f91 on the owner's word ("Push
now"), with the native arm only: the AVX2 arm did not run, and the owner
chose to let CI stand in for it, since the runner IS the AVX2-class machine
the local `-C haswell` arm only emulates and the batch touches no
floating-point kernel, reduction or tolerance, the failure mode that arm
exists for (`../experiences.md`, "A tolerance measured on one CPU is a
hand-copy of that CPU's rounding"). CI run #476 (id 41772980957, job
"Julia 1.12 CPU full-lane tests" on `ubuntu-latest`, this time a znver5
host by the suite's own identity annotation, stage 6 identity pins 6 of 6)
ran the full CPU lane on a232f91 and completed green at 05:18:59 UTC on
2026-11-04, 54.8 min after it started; the CUDA testsets skip there as
always. So the AVX2-class check passed on the pushed tree itself, and the
only thing this batch did not have is the local emulation of a check the
real machine then ran. This addendum is the bookkeeping the owner asked
for on 2026-11-04; it is markdown-only and rides the fast lane named in
its commit message.

**Correction, 2026-11-04, beside the addendum:** the message of the commit
that carried it (1194818) states that fast lane's clock as "01:22 to 02:04
EST"; the lane's log says 2026-11-04 08:54 to 09:32 EST. The time was typed
from the writer's estimate instead of read from the log; every other clock
in this record was read from its log. The same lane had first run red once
on the tree before the todo row, at one assertion of the testset "Dropped
spectral charge is recorded in a receipt, not only in a warning (F-36)" --
a positional pairing of warnings with receipts across two channels that
worker threads fill -- recorded then as a todo row and closed 2026-11-04 by
the commit that carries this correction, which compares the payloads as
multisets (the row and its closing: `todo_ledger_archive.md`, "Row retired
by the in-memory run artifact bookkeeping"). CI run #477 on 1194818 was
green (85.8 min, within the runner's 52 to 81 min spread of the previous
five runs).

## 6 Ledger

`docs/todo.md`: a new row, "In-memory run artifact: the follow-ups the mode
left open" (the multi-process arm unexercised; a mid-run save holding the
rows flushed so far; unbounded growth by design; row 35's text mirror).
`docs/experiences.md`: "A new mode of a sink is a storage, not a second
sink". `docs/design/run_artifact.md`: the `storage` bullet under "Artifact
options", the receipts paragraph, a rejected alternative.
`docs/public_api.md`: `?save_run_artifact` and the memory paragraph.
`docs/README.md`: this record and the design entry.
