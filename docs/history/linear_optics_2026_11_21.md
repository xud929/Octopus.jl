# The shared linear-optics object: `LinearOptics` and its consumers (2026-11-21)

Status: designed 2026-11-16 to 2026-11-21 in an owner discussion (the
decisions D1-D10 of [`../design/linear_optics.md`](../design/linear_optics.md)),
authorised 2026-11-21 ("a tech note first, then implementation and
validation, audit following, finally commit and push"), implemented and
verified the same day as sections 3 and 4 record; the neighbour audit is
[`audit_linear_optics_2026_11_21.md`](audit_linear_optics_2026_11_21.md), the
gate is section 5, the ledger section 6. Bracketed `[...: pending]` markers
name a measurement the record commit after the gate fills; nothing under
`result/` is cited as evidence.

## 1 The decisions

The question the owner asked: should a struct carry the Twiss functions and
the canonical dispersion so that `Linear6DSpec`, the beam and the other
consumers of `beta`, `alpha`, `zeta`, `eta`, `R` accept one object, with the
phase as a position parameter? The design note holds the ten decisions with
their reasons; in one line each:

- D1 three plain value types, `EdwardsTengTwiss` (three-plane `beta`,
  `alpha`, the Edwards-Teng `R` and its `form`), `CanonicalDispersion`
  (`zeta`, `eta`, `h` derived, a `slope=` constructor), `LinearOptics`
  (both, plus `mu`, `s`, `frame`); the composite named for what it is, the
  parts for their parameterization (owner, 2026-11-20).
- D2 the theory note's conventions, (T2)-(T4) and (D1)-(D3), stated once in
  the type docstrings and repeated in every consumer's `ParamMeta`.
- D3 flattening, never storage: every consumer gains `optics = o`
  (`Linear6DSpec(o1, o2)` positional) and flattens it into its existing
  stored parameters; the stored spec, the metadata, the snapshot, the
  kernels and the flat path do not change.
- D4 exclusive forms, refused by name; no silent partial reads.
- D5 phases are positions: `mu` with a required `frame`,
  `Linear6DSpec(o1, o2)` from the phase difference, `advance_phase` for the
  one-turn map, disagreement and frame mismatch refused.
- D6 `linear_optics(result)` closes the loop from the analysis.
- D7 form 2 reaches `Linear6DSpec` (`form1`, `form2`), the block
  admissibility `det C < 1` refused by name.
- D8 `XY_UNDEF` refuses nonzero coefficients instead of ignoring them.
- D9 the three elementary maps from the parts.
- D10 the conventions documented where they were missing, including the
  `Beam` docstring's false claim about `R`.

## 2 What was measured before the design was fixed

Five read-only reading passes over the process rules, the audit protocol,
the analysis internals, the coupling conventions and the metadata machinery
(2026-11-21) established the facts the note's section 1 tabulates:

- `R` meant two matrices: `Linear6DSpec`'s `R1`/`R2` are the Edwards-Teng
  block `C = adj(R)/sqrt(1 + det R)` with normaliser `sqrt(1 - det C)` and
  no admissibility guard (`_mR66`, linear6d.jl); `XYCoupling` (modes A/B =
  (T2)'s V1/V2 entry for entry), `Beam`, `ChromaticityKickSpec` and
  `LumpedRadSpec` hold R itself, the last two with `XY_MODEA` hard-coded;
  `ThinStrongBeamSpec` takes an `XYCouplingSpec`, an `XYCoupling` or a 4x4
  matrix and never a tuple. No `ParamMeta` stated a convention; no test built
  a `Linear6DSpec` with a nonzero `R1`.
- The analysis stores the eigenmode Twiss only scaled
  (`EdwardsTengPair.formK.twiss`), the longitudinal mode's Twiss not at all
  (`_twiss_from_block` on the separation's `longitudinal_map` recovers it),
  and `physical.beta/alpha` are the Mais-Ripken projected arrays, which equal
  the barred Edwards-Teng Twiss only without crab dispersion.
- The metadata layer is indifferent to a flattened keyword: nothing
  enumerates a friendly constructor's keywords, the unknown-key warning fires
  only for STORED keys, `_check_declared_defaults!` passes `params(example)`
  through the constructor (so a literal default on `form1` was refused beside
  the matrix example and had to be declared like `alpha1`, "defaults to 1 in
  the optics form"), and the effectiveness contract has an optics-form probe
  for `linear6d` with nonzero `R1`/`R2` on which the form parameters are
  effective (deviations 2.7e-4 and 1.1e-3).
- Baseline first: `linear_optics_2026_11_21_baseline.jl` hashed the flat-path
  outputs of every consumer (two `Linear6DSpec` matrices and a tracked
  particle, the three elementary maps, `ChromaticityKickSpec`,
  `LumpedRadSpec` damping, `ThinStrongBeamSpec`, three CPU beams and one CUDA
  beam) on the pre-batch tree 9c48589; the 14 SHA-256 hashes are in
  `linear_optics_2026_11_21_baseline_fingerprints.txt` and came back
  identical on the batch tree.

## 3 What landed

- `src/knowledge/LinearOptics.jl` (new, included after `knowledge/Methods.jl`):
  the three types with their keyword constructors and refusals, the `slope`
  conversion (`h = 1/(1 + zeta' S4 d)`, `eta = h d`), `dispersion_h`,
  `slope_dispersion`, `advance_phase`, `_phase_advance` (D5), `isapprox` and
  `show`, and `_resolve_optics_keywords`, the one flattening rule the
  chromaticity kick and the radiation element call.
- `src/elements/linear6d.jl`: the two-point constructors (typed and untyped),
  `_edwards_teng_block` / `_edwards_teng_R_from_block`, the stored `form1`,
  `form2` (friendly constructor, raw form, `_LINEAR6D_OPTICS_KEYS`),
  `_mR66(C, form)` with the V2 block, `_check_linear6d_block` (det C < 1
  refused by name at construction and at the raw compile), the docstring, the
  `R1`/`R2`/`form1`/`form2` meanings and the construction help.
- `src/elements/linear_maps.jl`: `_coupling_mode`, `_check_undef_coefficients`
  at the spec and the runtime constructor (D8), the parts-to-spec
  constructors (D9), the `r1..r4` and `mode` meanings.
- `src/elements/chromaticity_kick.jl`, `src/elements/radiation.jl`: the
  `optics` keyword with `nothing` sentinels on the flat keywords, resolved
  before any stream is claimed; form 1 only; the `R` meanings; the help.
- `src/elements/strong_beam.jl`: `optics` on `ThinStrongBeamSpec` (transverse
  projection, `XYCouplingSpec` in the point's form when R is nonzero, nonzero
  dispersion refused); the help.
- `src/beam/Beam.jl`: `optics` on the Gaussian path (every optics keyword
  refused beside it, the bounded forms refuse it), the `XY_UNDEF` refusal
  before the draw, the docstring.
- `src/analysis/twiss_dispersion_analysis.jl`: `linear_optics` (exported).
- `test/runtests.jl`: the testset "LinearOptics: the shared optics object
  feeds every consumer by one flattening rule" (105 assertions, 115 with the
  audit's additions), the F-97
  pin retargeted to the refusal, an `optics` shape row in "A refused Beam has
  drawn nothing", the effectiveness ratchet 549 -> 551.
- Docs: `docs/design/linear_optics.md`, this record and the baseline files,
  `docs/public_api.md` (Construct Beams, Construct Elements, Analyses),
  `docs/registry_snapshot.md` regenerated, `docs/README.md` index,
  `docs/todo.md` row, two lessons in `docs/experiences.md`.

## 4 Verification

Numbers measured 2026-11-21 on the batch tree (CPU, Julia 1.12.4; scripts in
the audit's unit report where not in the suite):

- Baseline fingerprints: 14 of 14 identical before and after (section 2).
- Flattening identities (suite testset): `Linear6DSpec(o1, o2)` equals the
  flat optics form with `C = adj(R)/sqrt(1 + det R)`, `params` equal; `Beam(;
  optics)` equals the flat beam bit for bit under one seed in both forms;
  `ChromaticityKickSpec`, `LumpedRadSpec`, `ThinStrongBeamSpec` (coupled,
  uncoupled, form 2) equal their flat specs; the elementary maps equal
  theirs.
- Form 2 in `Linear6DSpec`: the map equals the `XYCouplingSpec(mode=XY_MODEB)`
  conjugation of the uncoupled map to 3.6e-15 (form 1: 3.6e-15) and is
  symplectic to 7e-16.
- Round trip `LinearOptics -> Linear6DSpec(o, advance_phase(o, 2pi nu)) ->
  analyze -> linear_optics`: uncoupled, weakly coupled (R = (0.05, 0.01,
  -0.02, 0.03)) and strongly coupled (R = (0.4, 0.1, -0.2, 0.3)) form-1
  points with crab and momentum dispersion return to 1e-8 relative in every
  field, the rebuilt map to 3e-14 .. 1.6e-13 absolute; a form-2 point
  returns as the relabelled form-1 point (the design note's D6 remark) with
  the map to 7.8e-14; `preferred_form = 2` presents form 2 and the point
  round-trips under the same request (map 5.7e-13).
- `Beam(; optics, emit)` with 4e5 particles against `matched_covariance`:
  variances within 0.31 %, covariances within 0.0031 of the geometric-mean
  scale (the suite pins 2e5 particles at 2 %).
- Refusals, each by name (suite): optics beside a flat keyword on every
  consumer; form 2 on the chromaticity kick and the radiation element;
  dispersion on the strong beam; `optics` on a bounded beam; `XY_UNDEF`
  with nonzero coefficients at the spec, the runtime and the beam (before
  the draw: the automatic stream counter unchanged across the refusals);
  `det C >= 1`; `form` outside 1:2; frame mismatch, phase disagreement,
  one-sided phases.
- Validators: `validate_element_metadata()` passed (612 default pairs, 34
  runtime variants); both `element_help` forms name `optics` on the four
  consumers and `EdwardsTengTwiss` on `xy_coupling`; the registry snapshot
  regenerated (the Exported API index gained seven names);
  `validate(ElementParameterEffectivenessContract())` passed with 553
  checked (ratchet raised to 551).
- Extracted sweeps, all green: Core.Box (5), detached docstrings (11), every
  export documented (1), every export in the snapshot (17), Architecture
  integrity (49, 1m40s); the neighbour testsets F-97/F-98/F-99 (36), "A
  refused Beam has drawn nothing" (36), "Thin elements, markers and RBEND"
  (114, carries the ratchet) green extracted; the "Edwards-Teng: the coupled
  construction" testset depends on file-level suite helpers and is covered by
  the lanes.
- Red where it should be: on the pre-batch tree `XYCouplingSpec(r1=0.01,
  mode=XY_UNDEF)` constructed and the F-97 pin asserted the identity; the
  retargeted pin fails there and passes here.

## 5 The gate

**Fast lane on the pre-fix tree** (the batch before the two audit fixes,
9c48589 plus the 22 uncommitted paths of the batch; 2026-11-21, 12:34:35 to
13:15:14 EST, 40.6 min, four threads): green, "Testing Octopus tests
passed", exit 0. 445 testset summaries, 157454 passing assertions summed
over them; the two testsets with a Broken column are "Misalignment maps"
(26 passed, 2 broken) and "Turn modulation: the RF cavity by the same wrap"
(144 passed, 1 broken), the pre-existing expected-broken checks every lane
records separately. The 17 heavyweight sections skipped loudly with the
lane's banner (the two effectiveness sections, the ForwardDiff pair, the
curved-frame routing, every example script, the two-rank turn-modulation
probe, the two MPI launcher sections, the contract coverage guards, the
lattice cells, the CUDA GaussianPIC subtraction, the physics contracts, the
two PIC sections, the PIC-family luminosity, the CUDA validation scripts).
A checkpoint, not the finish line. The audit fixes (U1-1, U1-2 of
`audit_linear_optics_2026_11_21.md`) were applied after it; their targeted
re-run is in the audit record's section 5, and the full gate below covers
the final tree.

[full gate, CUDA active, on the final tree: pending]

## 6 Ledger

`docs/todo.md`: the row "The shared linear-optics object `LinearOptics`"
(state and the open owner items). `docs/README.md`: the design note, this
record, the baseline script and its tables, the audit record and its unit
report. `docs/experiences.md`: "One name on six constructors is six
conventions until one object carries it" and "A form-2 point is a form-1
point with its modes exchanged". `docs/public_api.md`: the three sections
named above. `docs/registry_snapshot.md`: regenerated.
