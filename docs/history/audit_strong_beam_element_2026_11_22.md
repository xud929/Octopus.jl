# Targeted neighbour audit of the strong-beam consolidation (2026-11-22)

Status: the post-campaign neighbour audit the owner's standing direction
requires (`AGENTS.md`, "A fix's neighbours are where the next defect is";
protocol `../comprehensive_audit.md`, "The targeted neighbour audit"), scoped
to the strong-beam consolidation: stage 1
([`strong_beam_element_2026_11_22.md`](strong_beam_element_2026_11_22.md),
9d5c6ee) and stage 2
([`strong_beam_element_stage2_2026_11_22.md`](strong_beam_element_stage2_2026_11_22.md),
8e8139a). Conducted 2026-11-22 by the auditor with four read-only reading
units whose reports are archived beside this file
(`audit_strong_beam_element_2026_11_22_unit_reports/U1.md` to `U4.md`);
every lead below was reproduced by the auditor on the unfixed tree before it
was recorded, and the fixes landed in the commit carrying this report. The CI
run of the stage-1 push (9d5c6ee), owed by the stage-2 record: run 483 (id
44999125149) completed with success at 2026-11-22T08:37:04Z (59 minutes,
graniterapids runner).

## 1 Executive summary and repository

Octopus at 8e8139a plus this batch. The campaign made `GaussianStrongBeamSpec`
the one strong-beam element (its own parameters or a `LinearOptics` point, a
dispersive point consumed at the slice level, two offset functions) and kept
the old spellings alive as deprecated: no kernel changed, and the weak-strong
physics and performance were measured unchanged on CPU threads, MPI and CUDA.
The audit re-walked the constructors, the compile, the offset functions, the
twin runtime file and the task-layer readers, the validators and contracts
that build the deprecated kind, the suite's conversion, the scripts and the
documents. It confirmed one Moderate defect older than the campaign but
squarely in the surface the campaign made the recommended entry (a nonzero
`alpha` beside an explicit covariance was accepted and read by nothing, the
same class as the campaign's inert `mean`), one Minor consistency gap the
stage-2 centralisation exposed (a stored `sigz` and a stored 6×6 covariance
were two unchecked sources of one bunch length), five message, wording or
validation defects of the recommended form, one acceptance that moved with
the spelling (a one-slice element's cross-backend class), three coverage
losses from the test conversion, and eight documentation inconsistencies
including three wrong counts in the stage-2 record. Every finding is fixed in
this batch or recorded beside its claim; nothing is deferred. The physics
core (the Bassetti-Erskine kick, the virtual drifts, the slicing rules, the
conditional 6×6) was not in question and was not re-derived here: the
fingerprints and digests of both stages bound it.

## 2 Declared scope and coverage ledger

| Unit | Region | Hypotheses | Inspected by | Evidence |
|---|---|---|---|---|
| U1 | `src/elements/strong_beam.jl`, every line (constructors, deprecation table and helper, compile, `_thin_with_center`, `_stored_sigz`, `_gaussian_slices`, the offset functions, both metadata blocks) | route asymmetry between constructor, compile, `offset_slices!` and the flexible form; a deprecated spelling whose behaviour changed beyond the warning; metadata and help claims; warnings fired from inside Octopus; stale wording | reading unit, every line read, no execution; 7 leads | [`U1.md`](audit_strong_beam_element_2026_11_22_unit_reports/U1.md) |
| U2 | the twin and task seams: `src/track/strong_beam_track.jl` whole, the strong-beam readers of `src/track/Track.jl`, `src/tasks/Tasks.jl`, the strong-strong files, `src/examples/Examples.jl`; the silencing scope in `Knowledge.jl`; the effectiveness probes and wrappers in `Contracts.jl`; the include order | a reader treating the two kinds differently; the `mean` fix on the CUDA twin; every constructor site of the deprecated kind inside or outside the scope; the probe merge | reading unit, no execution; 3 leads, a 17-row reader table | [`U2.md`](audit_strong_beam_element_2026_11_22_unit_reports/U2.md) |
| U3 | the stage-2 diff of `test/runtests.jl` (48 hunks), `test/examples/`, `examples/`, `profiling/`, `validation/`; the stage-1 and compatibility testsets in full | assertions weakened or lost by conversion; thin-kind-only code paths no test reaches; the compatibility testset's completeness and vacuity; the `offset_slices!` placement in the scripts; the validation scripts' measured quantity | reading unit, 42 removed and 86 added `@test` lines traced; 3 leads | [`U3.md`](audit_strong_beam_element_2026_11_22_unit_reports/U3.md) |
| U4 | the design note, both records, the public API page, the index, the todo and experiences entries, the docstrings and help strings, the `LinearOptics` passages; the numbers of the stage-2 record against the logs | a documented claim the code does not make true; stale text; wrong numbers; link integrity; docstring placement for the sweeps | reading unit, every line read, logs compared with text tools; 8 leads | [`U4.md`](audit_strong_beam_element_2026_11_22_unit_reports/U4.md) |
| auditor | every lead above, reproduced on 8e8139a (`/tmp` probes whose outputs are quoted in section 4); the fixes; the new testset; the checks of section 5 | | executed | this report |

Not covered: the strong-strong solvers (no strong-beam spec), the MPI
extension (`ext/` names neither kind), the CUDA kernels' device compilation
beyond the backend-consistency script the gate's CUDA arm runs (the kernels
are unchanged by both stages; the physics digests are identical), and the
slicing rules' numerics (bound by the slicing-convergence script and the
kick fingerprints, both unchanged).

## 3 Traceability of the decisions

S1 (self-contained constructor) `GaussianStrongBeamSpec{T}` and its
`own`/`thin` exclusivity; S2 (dispersion at the slice level) the dispersive
branch and `gaussian_strong_beam_covariance`; S3 (offsets) `offset_slices!`,
`offset_slices`, `_offset_shape`, the tilt in the compile; S4 (thin kind
unchanged, deprecated) `_thin_strong_beam_spec` and the two warning shims;
S5 (`mean` refused beside `center`/`angle`, active everywhere)
`_thin_with_center` on both compile routes; S6 (a 6×6 alone) the block rule
in the own-parameters branch; S7 (deprecate and keep) `_STRONG_BEAM_DEPRECATIONS`,
`_strong_beam_deprecated`, `_SILENCE_DEPRECATIONS`, the validator and
contract wrappers, the compatibility testset. Each is pinned by the stage-1
testset (now titled S1-S6), the compatibility testset, and the audit testset
this batch adds.

## 4 Findings

Severity per the protocol's Phase 17. "Unfixed" quotes the reproduction run
on the stage-2 tree before the fix (`/tmp/linopt/b5/stage2/audit/repro_U1.jl`,
`repro_U2_1.jl`, 03:4x EST); "after" is the audit testset's assertion.

### 4.1 Confirmed and fixed in this batch

- **U1-1 [Moderate] `alpha` beside an explicit covariance was accepted and
  read by nothing.** `transverse_covariance`'s covariance branch refused
  `beta`, `sigma` and `coupling` by name but never looked at `alpha`, and the
  kernel builder always passed `something(alpha, (0, 0))`; the Gaussian
  constructor's 4×4 route and the new S6 6×6 route both forwarded it. Older
  than stage 1 (the thin constructor behaved so), but the recommended form
  made it the user's entry. Unfixed: the kernel params with `alpha = (0.3,
  -0.2)` beside a 4×4 equalled those without (`true`), the same beside a 6×6.
  Fix: a nonzero `alpha` beside a covariance is refused by name in the kernel
  builder (both routes); zero, the declared default, stays accepted so the
  metadata validator's default arm holds. The effectiveness contract's
  exemption `(:thin_strong_beam, :alpha)` ("used only when ... beta/alpha
  optics") was removed, since the sweep's candidate is now refused by the
  constructor rather than inert; the parameter moves to the `rejected`
  bucket and the suite's ratchet moves 23 → 24 with the reason beside it.
  (U4-6 is the same finding from the documents' side.)
- **U1-4 [Minor] a stored `sigz` beside a stored 6×6 covariance were two
  unchecked sources of one bunch length.** The slicing read `sigz`, the
  conditional covariance and the crab slope read `cov[5, 5]`. Unfixed: a beam
  given `sigz = 7e-3` beside a 6×6 built with `sigma_z = 3e-3` sliced at
  1.17 × 7e-3 (the outermost `sqrt_density` node) while its slices' conditional
  covariance was the 3e-3 bunch's (`true`), no warning. Fix:
  `_check_sigz_against_covariance` (relative 1e-9 on the variance) in the
  constructor and in `_stored_sigz`, so the flexible form's compile and the
  offset functions refuse too; the dispersive-point route, which builds the
  6×6 from `sigz`, passes exactly.
- **U1-2 [Minor] a `LinearOptics` point without `sigma` was refused by the
  kernel builder's message, naming the deprecated constructor and asking for
  `beta`, which the point supplied.** Fix: the Gaussian's optics branch refuses
  a missing `sigma` by its own name. (U4-5's first half.)
- **U1-3 [Minor] `ns = 1`, no `sigz`, an unknown `slice_method` blamed the
  missing `sigz`.** The stage-2 shortcut required `method in SLICE_METHODS`
  and fell through to the `sigz` refusal. Fix: the unknown rule is refused
  first, on every `ns`.
- **U1-7 [Minor] `thin =` accepted any object and died at compile with a
  `MethodError`.** Unfixed: `GaussianStrongBeamSpec(thin=42, ns=1)`
  constructed. Fix: refused by name unless an `ElementSpec{:thin_strong_beam}`
  or a compiled `ThinStrongBeam`.
- **U2-1 [Minor] the cross-backend rounding class moved with the spelling.**
  `_cross_backend_rounding(::GaussianStrongBeam)` declared the round-beam
  bound 64 (measured with three slices) for every `ns`, while the identical
  one-slice kernel spelled as the thin kind declared 8; a script migrating a
  round thin beam to `ns = 1` would have had its acceptance loosened 8×.
  Unfixed: `(8, 64)`. Fix: one slice declares the thin kernel's 8; the why
  text says so.
- **U4-5 (second half) [Minor] the compile's numeric-type mismatch message
  advised the nesting stage 2 deprecates** ("ThinStrongBeamSpec{T} inside
  GaussianStrongBeamSpec{T}"). Fix: it names the self-contained typed form or
  a kernel compiled in `T`.
- **U3-1, U3-2, U3-3 [Minor, coverage] three probes lost by the
  conversion.** The kernel builder's own optics refusals (a non-`LinearOptics`
  object, flat keywords beside the point) were reachable only through the
  deprecated constructor and had no test left; the constructor's refusal of a
  non-`Dict` `hvoffset` ("must be a Dict") lost its only probe when the
  hvoffset testset moved to `offset_slices!`; and no test tracked a Float32
  thin kind as a line element any more (only its compile was pinned). All
  three are pinned by the audit testset (the thin builder's three refusals
  through the internal builder; the constructor route and the flexible form's
  compile for the non-`Dict`; a Float32 one-turn `track!` of the thin kind
  against the one-slice Gaussian, bit for bit).
- **U3 seam [Minor] the `mean` deprecation warning fired before the S5
  refusal**, so a call refused for giving `mean` beside `center` also printed
  the warning. Fix: the warning follows the refusals; pinned.
- **U1-5, U1-6, U2-3, U4-2, U4-4, U4-8 and the nits [Minor, wording]**: the
  `offset_slices!` docstring said a stored `hvoffset` is folded unconditionally
  where `:replace` resets it with the rest of the user's offsets (code right,
  sentence fixed); "legacy" and "which `ThinStrongBeamSpec` documents" in the
  Gaussian docstring, "Recommended form" inside the thin kind's deprecated
  help, the `(with coupling)` claim beside the 4×4 route (coupling is refused
  beside a covariance); the `_elliptical_thin_strong_beam_probe` docstring's
  stale reason; the design note's section 4 still describing the replaced
  first-draft offset rule, S1 listing `hvoffset` without its deprecation, S6
  and the help saying `:equal_width` "keeps requiring its width" where the
  code requires `sigz` and the width; the stage-1 testset titled S1-S5 while
  pinning S6; the `:slice_offsets` warning's grammar; the thin docstring's
  "each public form warns once" where the two forms share one warning id.
- **U4-1 [Minor, ledger] the LinearOptics ledger row and design note still
  carried the strong beam's dispersion as an open owner item and named
  `ThinStrongBeamSpec(; optics)` among the recommended consumers.** Fixed by
  annotation (the design note's decisions are not rewritten): the open item
  gets its resolution pointer to S2, D15's consumer list names the Gaussian
  element, and the todo row closes the item.
- **U4-7 [Minor, provenance] the extraction harness behind two records'
  claims lived in session scratch, and the validators' clean result was not
  saved.** Fixed: the runner lands as
  `test/run_extracted_testsets.jl` with its limits in the header
  (a prelude hook for file-level helpers), and the validators' output of this
  batch is quoted in section 5.

### 4.2 Leads closed without a change

- **U2-2** the `:cuda_weak_strong_launch` receipt tags the kind
  (`element = :thin` or `:gaussian`), so a script re-spelled as `ns = 1`
  records a different value. This is the receipt naming the kernel that ran,
  a visible difference by design; the two in-tree asserters build the kind
  they assert. Recorded, not changed.
- U2's reader table (17 rows: luminosity, channel labels, the collectors,
  isolation, the plan builder, the CUDA elementwise requirement and routes,
  the device views, the workspaces, the beam element type) takes the same
  branch for both kinds everywhere else; the `mean` fix reaches the CUDA twin
  through the runtime kernel's fields, which every device path reads and no
  kernel reads a spec key. U2's H3 and H4: every construction of the
  deprecated kind through its friendly constructor sits inside the silencing
  scope; the effectiveness probe's merge keeps `thin` beside no own parameter.

### 4.3 Corrections to the records

Recorded beside the claims rather than by editing the frozen record
(`AGENTS.md`: history records are added to, never rewritten):

- `strong_beam_element_stage2_2026_11_22.md`, section 2: "42 blocks" should
  read 43; "2573 + 268 assertions passed, 0 failed" omits the two fixture
  failures of the re-run's `one_turn_matrix` block (`_OTMUnimplementedMethod`
  undefined in the extraction, 17 of 19 passed; listed correctly in the
  sentence that follows) and double-counts the partial passes of the
  re-run blocks; "each passed" for the three ramp and transition scripts:
  `near_round_gaussian_transition.jl` prints no verdict line, it exited 0.
  The per-block narrative and every other number were verified against the
  logs by U4 (its H3 list).
- The same record says `:equal_width` "keeps requiring its width": it
  requires `sigz` and the width at `ns = 1`, as the error text and now the
  design note say.

## 5 Verification of the fixes

All on this batch's tree (8e8139a plus the ten paths of this commit),
2026-11-22 03:52-04:25 EST, Julia 1.12.4, acnlinj4 (CUDA active). The
negative controls are the unfixed outputs quoted in section 4: every
assertion of the audit testset fails on 8e8139a for its lead's reason.

- Extracted testsets, through the committed runner
  (`test/run_extracted_testsets.jl`, 4 threads). First pass, the 43
  blocks of the stage-2 record plus the audit testset: 2676 passed, 1 failed,
  11 errored; the audit testset 24/24; ten of the errors are the fixture-less
  blocks the stage-2 record lists (file-level helpers the extraction does
  not evaluate), the failure and two errors were the compatibility testset
  reading the `:slice_offsets` warning, whose wording this batch made plural
  ("are deprecated spellings") while the testset's regex expected the
  singular: the regex now admits both, and the compatibility testset and the
  audit testset re-run extracted pass 52/52 and 24/24 (04:2x EST,
  `/tmp/linopt/b5/stage2/audit/extracted_two.log`). Second pass, the eight
  helper-dependent blocks with the prelude hook (`OCTOPUS_EXTRACT_PRELUDE`):
  265 passed, 3 failed, 3 errored, all of them the same regex (since fixed)
  and the two fixtures (`numerical_potential_hessian`, `_OTMUnimplementedMethod`)
  left to the gate as before.
- `validate_element_metadata()` passed (no error; the one log entry is the
  pre-existing `lumped_radiation compiles to the identity` probe warning) and
  `validate_configuration_metadata()` returned `true`:
  `result/gates/linopt/sb2_perf/validators_audit.txt` (U4-7's missing
  evidence, saved).
- The leads' reproductions re-run on the fixed tree
  (`result/gates/linopt/sb2_perf/repro_U1_fixed.txt`, `repro_U2_1_fixed.txt`):
  the U1-1 probe now throws `alpha = (0.3, -0.2) is not read beside an
  explicit covariance ...` at its first line (where the unfixed run printed
  `true`); U2-1 prints `(8, 8)` (unfixed `(8, 64)`); the U3-2 constructor
  route prints the `must be a Dict` refusal.
- `validation/strong_beam_kick_fingerprint.jl`: exit 0, no warning, all ten
  digests identical to the stage-1 and stage-2 runs ("gsb 6x6 covariance
  hirata" 0xb0954daa5a1f7bb1 among them).
- `validation/tracking_backend_consistency.jl` with
  `OCTOPUS_REQUIRE_GPU_CONTRACT=1`: exit 0, eight "Tracking backends agree
  within tolerance", 36 per-kind rounding-class instances within their
  declared classes on CPU/CPU and CPU/GPU (the one-slice bound of U2-1 is
  not among the script's instances, which slice three times; the audit
  testset pins it).
- Both shipped examples at their defaults: exit 0, no warning.
- `write_registry_snapshot`: identical to the tracked snapshot.
- The full gate at CI settings, CUDA active. A first attempt (04:19-05:01
  EST, exit 1) failed in "Every example script runs against the current
  interface": the extraction runner had been placed under `test/examples/`,
  whose every `.jl` that testset treats as a harness that must write under
  `OCTOPUS_RESULT_DIR`, and the runner, not a harness, wrote nothing (the
  blast-radius lesson of `AGENTS.md`, demonstrating itself on the audit's own
  provenance fix: the directory has a contract the suite probes). The runner
  moved to `test/run_extracted_testsets.jl`, beside the suite's probe files,
  and its header says why; nothing else changed. The gate then ran on this
  tree after this report was written and the tree was committed unchanged;
  its numbers are in the commit message. It covers the two commits 8e8139a (stage 2) and this one
  together (`AGENTS.md`: the gate is owed before the push and covers the
  accumulated tree).

## 6 Change log

- `src/elements/strong_beam.jl`: the `alpha`-beside-covariance refusal
  (kernel builder), the `sigma`-beside-point refusal and the `thin =` type
  refusal (Gaussian constructor), the `mean` warning after the refusals,
  `_check_sigz_against_covariance` (constructor and `_stored_sigz`), the
  unknown-rule refusal before the `ns = 1` shortcut, the one-slice rounding
  bound, the compile's mismatch message, the docstring and help wording.
- `src/contracts/Contracts.jl`: the `(:thin_strong_beam, :alpha)` exemption
  removed; the probe docstring's reason.
- `test/runtests.jl`: the audit testset; the stage-1 title S1-S6; the
  rejected ratchet 23 → 24 with its reason.
- `test/run_extracted_testsets.jl`: the extraction runner, landed.
- `docs/design/strong_beam_element.md`, `docs/design/linear_optics.md`,
  `docs/public_api.md` (unchanged), `docs/README.md`, `docs/todo.md`: the
  wording and ledger fixes of U4-1, U4-2, U4-4; this report and its unit
  reports indexed.

## 7 Remaining risks and the open queue

Nothing deferred from this audit. Risks that remain by design: the deprecated
spellings are kept indefinitely and pinned by one compatibility testset,
whose deletion would turn the compatibility into a claim; the kinds' shared
once-per-process warning id means a user of both thin forms sees one message;
the receipt tag of U2-2 names the kernel that ran, which is what a receipt is
for. Removing the deprecated spellings remains the owner's decision alone and
is not planned.
