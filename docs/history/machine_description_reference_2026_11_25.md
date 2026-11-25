# The reference particle reaches its consumers: `Beam` and the cavities take `reference = ReferenceParticle` (2026-11-25)

The batch after stage 2 of [`../design/machine_description.md`](../design/machine_description.md):
decision D12's acceptance half, carried on the lattice since the stage-2
record [`machine_description_stage2_2026_11_25.md`](machine_description_stage2_2026_11_25.md),
now reaches the two consumers the decision names first, `Beam` and the
cavities. Guides: `../guides/development_workflow.md`, `../guides/elements.md`,
`../guides/examples_and_validation.md`, `../guides/documentation.md`. Branch
`ref` off `main` 1f129b8: anchors 9e1dcb2, unit R1 bc8386d, unit R2 21e6bf1
(merged 6656d81), the R2 follow-ups f961ab5 and e976c66 (merged at the
fold), unit R3 and the docs in the fold's feature and record commits, which
follow them.

## 1 What landed

- Unit R1 (bc8386d; `src/beam/Beam.jl` +51/-9, `test/runtests.jl` +114):
  `Beam(...; reference = ReferenceParticle)` on every constructor form, the
  bounded and grid forms included, through the one funnel `_beam_params`:
  `charge`, `mc2` and `E0` come from the reference, converted exactly as the
  flat values are, so the beam built either way is the same bit for bit,
  `BeamParams` included; `r0` and `npart` stay keywords. Any of the three flat
  keywords beside `reference`, whatever its value, is refused by name before
  any draw or activation, as is a `reference` that is not a
  `ReferenceParticle`. Documented on the `Beam` docstring, not in
  `beam_initialization_option_schema`. One testset, "Reference particle: Beam
  takes the reference in place of charge, mc2 and E0" (30 assertions): flat
  and reference beams bit for bit (`params`, every coordinate array) under one
  seed, in Float32, on the grid and uniform forms; the refusals by name and
  before the stream is taken; the consumer boundary, the strong-strong kick
  scales `_strong_strong_kbb1/2` (the only `src/` site reading a beam's
  charge, `mc2`, `E0`) equal for both forms and moved by 2.75 by a 275 to
  100 GeV reference.
- Unit R2 (21e6bf1; `src/elements/rf_cavity.jl` +96/-8, `test/runtests.jl`
  +87): `ThinRFCavitySpec` and `ThinAcceleratingCavitySpec` take `reference`
  on both routes, in the typed and `harmon` forms, through one shared fold
  `_fold_reference`: the `strength` route gets `reference_beta_gamma(reference)`,
  the `voltage` route `E0`, `mc2`, `charge` (then the existing pair
  derivation), so the stored numbers are the flat call's bit for bit and
  `reference` itself is not stored. Any of `beta0`, `gamma0`, `e0`, `mc2`,
  `charge` beside it is refused by name; `charge` keeps its default of 1
  (signature `charge = nothing`, applied after the fold). `construction_help`,
  both docstrings and both `element_help` forms name it. One testset,
  "Reference particle: the cavities take the reference in place of beta0 and
  gamma0" (52 assertions): nine flat/reference twins equal by parameters and
  by compiled runtime, the refusals, the flat no-charge strength pinned,
  nothing construction-only stored. Found on the way: `e0`, `mc2`, `charge`
  given WITHOUT `voltage` were silently ignored by both constructors, a
  pre-existing defect, refused by name in the follow-up (f961ab5: a scan of
  76 cavity constructions over `src/`, `test/`, `validation/`, `examples/`,
  `ext/` and `profiling/` found 75 passing `voltage` beside them, one splat
  fixture whose eight callers all pass it, none affected; and e976c66 after
  the review: the five flat keywords read PRESENCE through a private sentinel
  `_UNGIVEN`, so an explicit `nothing` is refused by name instead of slipping
  past the fold, the refusal test device asserts the error type, seven
  compile assertions implied by the stored-parameter equality dropped, the
  Float32 precision clause added; the testset ends at 59 assertions).
- Unit R3 (in the fold's feature commit): the four examples take the reference:
  `weak_strong_tracking.jl` and `crab_cavity_noise.jl` one `ReferenceParticle`
  per weak-beam input block, passed to `Beam`; `strong_strong_tracking.jl` one
  per beam; `twiss_dispersion_dba_ring.jl` the `DBARing` cavity as
  `thin_rf_cavity(...; reference = reference)` in place of the hand-derived
  pair; the catalogue entries list `ReferenceParticle`. Fingerprints: section 3.
- Docs (R4): `public_api.md` (three sections), the design note's banner and
  D12, `README.md`, `todo.md`, this record; the snapshot regenerated at the
  fold (three Objects lines of the Examples section gain `ReferenceParticle`).

## 2 Decisions

- The light form, not the compile-path unification (orchestrator): each
  consumer flattens the object into the keywords it already stores, as the
  `LinearOptics` consumers do under D15, so nothing downstream changes and
  every call shape keeps working; the compile-path half of D12 (the reference
  derived at compile, an explicit value checked against the bound one) stays a
  campaign of its own, with the carried gap below as its first lead.
- `Beam`'s `reference` is documented on the `Beam` docstring and not in
  `beam_initialization_option_schema` (the receipt-bearing distribution
  options only, each with a contract probe). A non-`ReferenceParticle`
  `reference` is an `ArgumentError` by name, never a `TypeError`; a flat
  keyword beside `reference` is refused whatever its value: one place where
  the species and the energy are spelled, never two.
- `r0` and `npart` stay keywords (orchestrator): the classical radius is not
  derived from the reference in this batch, although `charge` and `mc2` fix it.
- Found by R2 and fixed, not carried: `e0`, `mc2`, `charge` on the strength
  route were silently ignored by both cavity constructors, a defect under the
  "silently ignored configuration" invariant; refused by name (f961ab5), and
  the keywords read presence, not value (e976c66).
- Carried (R1): no task compares the beam's `E0`, `mc2` with a cavity's
  `beta0`/`gamma0` at compile (`_validate_reference_chain` compares the
  cavities with one another only), so a beam at one energy through a cavity
  built for another compiles and tracks; `todo.md`, the "Knob-given values" row.

## 3 Verification

- Extracted per unit, in package mode (`test/run_extracted_testsets.jl`): unit
  R1's testset 30 of 30; unit R2's 52 of 52, with `validate_element_metadata()`
  passed and both `element_help` forms naming the keyword for both kinds,
  then 60 and 59 after the two follow-ups; beside them the neighbours "Beam
  refuses sigma with emit ..." 16, "A refused Beam has drawn nothing ..."
  36, "BeamParams keyword defaults are typed ..." 8, "Beam initialization
  metadata and effectiveness checks ..." 16, "RF cavity closes the
  longitudinal plane" 38, "Cavity chain composition ..." 9, "Turn
  modulation: the RF cavity by the same wrap" 147, and the three source
  sweeps 1 / 11 / 5 in every run. Unit R3: the four scripts exit 0 as the
  suite's example testset runs them (the tracking three on the CUDA device
  their `:auto` line found), and extracted "Machine description: the shipped
  DBA lattice module builds an equal lattice when included twice" 13 of 13,
  "the Example core object answers with real scripts" 57 of 57, "Stage 5:
  every kind that declares the analysis ..." 64 of 64.
- The examples' fingerprints (SHA-256, the LinearOptics record's quantities
  and hashing rule; `ws` = `weak_strong_tracking.jl`, 10,000 particles x 50
  turns; `ss` = `strong_strong_tracking.jl`, 2,000 + 2,000 x 20 turns; `cn`
  = `crab_cavity_noise.jl`, 10,000 x 50 turns; `dba` = the DBA analysis),
  pre-change on `main` 1f129b8 (`/tmp/claude-dxu/ref/compare/pre.log`,
  `pre_cuda1.log`, `pre_cuda2.log`, 2026-11-25 09:57 to 10:02 EST; the logs,
  the copy maker and the driver are kept under `result/gates/ref/compare/`,
  git-ignored scratch, and the hashes are this table) against the
  converted scripts. The CUDA pre column is run 1 with run 2's verdict:

  | quantity | CPU pre (1f129b8) | CPU post | CUDA pre (run 1; run 2) | CUDA post (two runs) |
  |---|---|---|---|---|
  | `ws_final_coords` | `98dc07e8c396832f` | `98dc07e8c396832f`, identical | `8db22fd2b096a781`; equal | `8db22fd2b096a781`, equal |
  | `ws_rms` | `701353e212e715ac` | `701353e212e715ac`, identical | `f69762568ddc6c0c`; equal | `f69762568ddc6c0c`, equal |
  | `ws_luminosity` | `db81599532f3c8b8` | `db81599532f3c8b8`, identical | `85e298071df8865c`; equal | `85e298071df8865c`, equal |
  | `ws_moments` | `d8e66470f10bbace` | `d8e66470f10bbace`, identical | `3bfb0c2d9362b4cd`; equal | `3bfb0c2d9362b4cd`, equal |
  | `ss_electron_final_coords` | `a1cfea9e817a638f` | `a1cfea9e817a638f`, identical | `75a83e79fe0c16ea`; differs | `c7dfde451b9f997e`, differs (run 2 also differs; noise, below) |
  | `ss_proton_final_coords` | `2aa9524b1aed93b7` | `2aa9524b1aed93b7`, identical | `637a5fd9b14319e1`; differs | `e8fbd7f398410ca7`, differs (run 2 also differs; noise, below) |
  | `ss_rms` | `80e4841409255c35` | `80e4841409255c35`, identical | `7722cb64150561b0`; differs | `24726c81df629d13`, differs (run 2 also differs; noise, below) |
  | `ss_luminosity` | `c66eec4637087ba7` | `c66eec4637087ba7`, identical | `f8965f9bbd0a63e8`; differs | `b35fe8c02445afe5`, differs (run 2 also differs; noise, below) |
  | `ss_electron_moments` | `bb780250a3908aee` | `bb780250a3908aee`, identical | `27ba2fb921c297b6`; differs | `f227526293bfda69`, differs (run 2 also differs; noise, below) |
  | `ss_proton_moments` | `0f6f3731d67941b6` | `0f6f3731d67941b6`, identical | `824b1704e4d5ca4b`; differs | `e27981bc8d0fbba3`, differs (run 2 also differs; noise, below) |
  | `cn_final_coords` | `4c7fe49b5e2fdb30` | `4c7fe49b5e2fdb30`, identical | `3bdea6d4eecb15a2`; equal | `3bdea6d4eecb15a2`, equal |
  | `cn_luminosity` | `67058604548565e9` | `67058604548565e9`, identical | `7ae059102437e811`; equal | `7ae059102437e811`, equal |
  | `cn_moments` | `2a47b770f3ddab96` | `2a47b770f3ddab96`, identical | `df8822d1adda7769`; equal | `df8822d1adda7769`, equal |
  | `dba_tunes` | `e8ac2169212395e1` | `e8ac2169212395e1`, identical | `e8ac2169212395e1`; equal | `e8ac2169212395e1`, equal |
  | `dba_zeta_eta_h` | `80a1e9e1190d98d6` | `80a1e9e1190d98d6`, identical | `80a1e9e1190d98d6`; equal | `80a1e9e1190d98d6`, equal |
  | `dba_point` | `04d44e115496f7b6` | `04d44e115496f7b6`, identical | `04d44e115496f7b6`; equal | `04d44e115496f7b6`, equal |
  | `dba_sizes` | `5703fdf7c53edea7` | `5703fdf7c53edea7`, identical | `5703fdf7c53edea7`; equal | `5703fdf7c53edea7`, equal |
  | `dba_residuals` | `a1fa16d46cf61e76` | `a1fa16d46cf61e76`, identical | `a1fa16d46cf61e76`; equal | `a1fa16d46cf61e76`, equal |
  | `dba_one_turn_matrix` | `12d94da52ad3881a` | `12d94da52ad3881a`, identical | `12d94da52ad3881a`; equal | `12d94da52ad3881a`, equal |
  | `dba_text` | `13aaab6156c61f4d` | `13aaab6156c61f4d`, identical | `13aaab6156c61f4d`; equal | `13aaab6156c61f4d`, equal |

  The baseline's ten `ws` and `ss` CPU hashes are the LinearOptics record's
  `fingerprints_post.txt` byte for byte (this unit checked; the names differ
  by prefix only). The two CUDA baseline runs agree on the 14 hashes outside
  the strong-strong set and differ on its six, that record's device noise, so
  the CUDA post column is read against the noise, measured by R3 with the
  LinearOptics record's tolerance reader on the artifacts (max relative
  difference per table: floor = pre run 1 against pre run 2, then pre run 1
  against post run 1, then post run 1 against post run 2): weak-strong
  luminosity and moments 0 / 0 / 0, crab-noise luminosity and moments 0 / 0 /
  0, strong-strong luminosity 1.32e-11 / 1.70e-11 / 1.71e-11, electron
  moments 8.61e-9 / 5.05e-9 / 2.36e-9 (worst column `m001010`), proton
  moments 4.76e-10 / 2.06e-9 / 1.82e-9 (worst `m000100`): the cross-tree
  values interleave with the same-tree ones, the PIC reduction's noise, and
  the CPU identity is the proof that nothing attributable to the spelling
  moved. The
  baseline's `dba_one_turn_matrix` is not the stage-2 record's post hash
  `b2cebc5ce8cc7713` while its other six `dba` hashes are that record's
  because this batch's driver hashes the one-turn MATRIX alone where the
  stage-2 driver hashed the whole `LinearizedMap`, provenance included; the
  matrix is the same object in both (the stage-2 record's post run and this
  baseline were taken on the same tree).
- Validators and sweeps on the folded tree (2026-11-25 10:42 to 10:49 EST,
  `result/gates/ref/extracted_checks.log`): `validate_element_metadata()`
  passed with 614 of 614 default pairs and 34 of 34 runtime variants, both
  `element_help` forms rendered for all 32 kinds, `validate_configuration_metadata()`
  true, the regenerated snapshot equal to the committed one; extracted,
  every block green: "No method grows a Core.Box outside the argued
  allowlist" 5, "No docstring is detached by comment lines" 11, "Every
  export is documented" 1, "Every exported API name appears in the registry
  snapshot" 17, "Architecture integrity" 50, the catalogue tripwire 57, the
  Stage 5 analysis tripwire 64, the DBA module's include-twice pin 13, the
  four Beam neighbours 16 / 36 / 8 / 16, the three cavity neighbours 38 / 9 /
  147, and the batch's two testsets 59 and 30. The fast lane and the full
  gate run on this tree after this record was written; their numbers are in
  the commit messages of the batch (the gate paragraph below).
- The full gate at CI settings with CUDA active runs on this tree after this
  record was written and the tree is committed unchanged; its numbers are in
  the commit message of this batch, as a record cannot carry the gate that
  covers it.

## 4 Ledger and the previous push

`README.md`: this record indexed, the design entry naming the batch.
`todo.md`: the machine-description row (reference batch implemented, what it
did, CI 489, the 5edd08a blemish) and the "Knob-given values" row (the carried
gap). `public_api.md`: "Construct Beams", "Construct Elements", "Describe A
Lattice" (its example in the recommended spelling). The design note: the
banner and D12's dated status. The previous push: CI run 489 (id 45634749404)
for 1f129b8 ran 2026-11-25 14:30:12 to 15:49:05 UTC (78 min 53 s): success, the
"Julia 1.12 CPU full-lane tests" job green;
the intermediate commit 5edd08a ("wip(docs): stage 2 docs drafts with
bracketed placeholders") sits in the pushed history before the unit-C merge,
superseded by the record commit 1f129b8 and not rewritten: a blemish, stated.
