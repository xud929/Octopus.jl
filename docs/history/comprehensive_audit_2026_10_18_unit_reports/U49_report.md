# U49: theory notes D: misalignment and patch, aperture and loss, RF cavity and reference energy, arc survey, floor plan, BPM

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Depth: claims-vs-code.
Hypotheses briefed: (1) the 2026-10-18 survey change (cavities inside kept-whole lines) reflected
everywhere the old refusal was described; (2) two surveys over one geometry, one source or two;
(3) orphan numbers and stale behaviour statements.

## Region

| file | lines | read |
|---|---|---|
| `docs/theory/misalignment_and_patch_maps.md` | 1-465 | every line |
| `docs/theory/aperture_and_particle_loss.md` | 1-405 | every line |
| `docs/theory/rf_cavity_and_reference_energy.md` | 1-401 | every line |
| `docs/theory/arc_survey_and_velocity_slip.md` | 1-165 | every line |
| `docs/theory/floor_plan_survey.md` | 1-155 | every line |
| `docs/theory/bpm_measurement_model.md` | 1-233 | every line |

Total 1824 lines, all read. Reference files read in full to compare claims against:
`src/elements/misalignment.jl` (410), `src/elements/patch.jl` (297), `src/elements/floor_plan.jl` (227),
`src/elements/aperture.jl` (679), `src/elements/rf_cavity.jl` (940), `src/tasks/BPMObserver.jl` (447).
Read in part (the ranges a claim pointed at): `src/tasks/Tasks.jl` 395-432, 760-840, 1838-1895;
`src/elements/beam_line.jl` 40-160, 430-490, 700-770; `src/contracts/Contracts.jl` 2345-2360,
2581-2590, 2650-2815; `test/runtests.jl` 9685-9700, 14289-14335, 14765-14985, 15007-15075,
21430-21450, 24575-24700 (assertion lines), 25668-25700; `src/track/longitudinal.jl` 28-40 and the
function signatures; `docs/theory/beam_line_composition.md` 509-560; `docs/todo.md` 55-66;
`docs/experiences.md` 148-156, 1746-1752.

## Provenance

READ line by line: the six notes in full; the six reference files in full; the partial ranges above.

EXECUTED (scratch `result/comprehensive_audit_2026_10_18/probes/U49/`, logs beside each script):

- `probe1_anchors.jl` (`probe1_anchors.log`): floor-plan anchors — `sbend L=2 angle=0.5` exit
  `X = -0.489669752`, `Z = 1.917702154`, `theta = -0.5`; with `ref_tilt = pi/2`: `Y = -0.489669752`,
  `phi = -0.5`, `theta = -3.35e-17`, `psi = -8.54e-18`; with `ref_tilt = 0.3`:
  `(-0.4810158446769, -0.1421582627152, -0.0349203257493)`, equal to the closed form
  `R_S(0.3) R_Y(-0.5) R_S(-0.3)` extracted with `atan(W13,W33), asin(W23), atan(W21,W22)`;
  `PatchSpec(angle_s=+0.2)` + 3 m drift gives `psi = -0.2`; `PatchSpec(angle_y=+0.1)` gives
  `theta = -0.1` and `dX = -0.299500249940 = 3 cos(phi) sin(theta)`. Misalignment survey origin
  `_survey_frame(0.198/1.1, 1.1)` gives `X = -0.108545`, as does `survey` of the same bend.
  `MarkerSpec(x_offset=1e-3, y_offset=-8e-4)` compiles to `MisalignedElement` and returns its input
  with max difference `0.0`. `MarkerSpec(alive = closure)` is accepted WITH an unknown-parameter
  warning (Knowledge.jl:139) and the closure is callable through `getparam`. Aperture schema keys:
  `shape, x_limit, y_limit, dx, dy, alive, element_id, loss_record, ...`. `allow_lost_particles()`
  default `false`. Crab/RF argument difference at 2.5 GeV proton, `z = 7 mm`: `4.637e-3` rad at
  `f = 400.8 MHz` (2.279e-3 at 197 MHz). A bare `ThinRFCavitySpec(harmon=1; ...)` compiles with
  `k = NaN, ds_turn = NaN` and its kick throws the static message. `BeamLine(...)` returns
  `ElementSpec{:line}` and `survey` accepts it. Arc walker on `(Drift 1, kept-whole sub-line
  [bend 2 m, ref_tilt 0.4], Drift 3)`: bend found at `s = 1.0`, total `6.0`; floor plan rows at
  `s = [1, 3, 6]`.
- `probe2_contracts_seam.jl` (`probe2_contracts_seam.log`): `validate(MADXSurveyConsistencyContract())`
  → `passed`, 9 cases, worst `7.105e-15`. `validate(PTCConsistencyContract())` → `passed`, 61 cases,
  305 rows, worst `4.995e-13`; per-case: `quad_mis_dx 4.10e-13, quad_mis_dy 4.08e-13,
  quad_mis_ds 4.45e-13, quad_mis_dtheta 4.92e-13, quad_mis_dphi 4.77e-13, quad_mis_dpsi 4.995e-13,
  quad_mis_all 4.957e-13, sext_mis_dx 4.11e-13, cfbend_mis_dx 4.48e-13, cfbend_mis_all 4.47e-13,
  cfbend_reftilt_mis_dx 2.79e-13, cfbend_reftilt_mis_all 4.46e-13, sbend_reftilt 3.50e-13,
  sbend_reftilt_vertical 4.11e-13, cfbend_reftilt 4.65e-13, sbend_edge 4.58e-13`.
  Override seam (LEAD U49-1): see the lead. Orphan nu_s numbers (LEAD U49-9): at `V = 1 MV`,
  `h = 1`, `C = 100 m`, 2.5 GeV proton, `alpha_c = 0.2`: task-bound ring `nu_s = 0.0020935`
  (analytic full-eta `0.0020934`), bare `0.0038498` (analytic alpha_c-only `0.0038497`), ratio
  `1.839`; `max|z|` over 4096 turns from `1e-3` is `1.000021594e-3`.
- `probe3_girder_override.jl` (`probe3_girder_override.log`): misaligned parent line around the
  kept-whole child with a placement-level `ref_tilt` override — tracked coordinates differ from the
  spec-level spelling by `1.505e-2` (girder exit frame built unrolled: `Ve = (-1.927946, 0, 5.550450)`
  against `(-1.775756, -0.750778, 5.550450)`), and by `0.0` when the parent is not misaligned.

## Leads

### LEAD U49-1 [Moderate, confidence high] src/elements/floor_plan.jl:137
Claim: The floor-plan walkers read a kept-whole sub-line's `ref_tilt` from the sub-line SPEC, so a `ref_tilt` set as a placement override on that sub-line's `LineEntry` rolls the tracked map (via `_effective_spec`) but not the survey nor the misaligned-girder faces — the two surveys the floor-plan note (§5, L152-155) says are "computed from the same `line_entries` walk" are three walkers that disagree on what a placement's parameters are (hypothesis 2; defect classes 3 and 11).
Mechanism: `_survey_walk!` (floor_plan.jl:137) and `_girder_flat_entries!` (floor_plan.jl:171) do `psi = getparam(spec, :ref_tilt, 0.0)` where `spec = getfield(entry, :spec)` — the raw sub-line spec, overrides dropped. For element entries the same file uses `getparam(entry, ...)` (merged params, L63-68, 82, 86), and the arc walker `_collect_spec_s!` (Tasks.jl:818-827) uses `_effective_spec(entry)`, which merges overrides (Tasks.jl:404-408). Tracking compiles the placement through the same `_effective_spec`, so the compiled entry is a `RefTilted` wrap: `survey(line)` reports an unrolled floor plan for a line that tracks rolled. `compile_runtime(::ElementSpec{:line})` (beam_line.jl:755-763) hands `_misalignment_wrap` a `design` built on `_girder_design_frames` → `_girder_flat_entries!`, so a MISALIGNED parent containing such a child gets entrance/exit faces computed for the unrolled geometry while its interior is rolled: measured `1.505e-2` difference in the tracked coordinates between the override spelling and the spec-level spelling of the same physical roll (parent `x_offset=1e-3, y_offset=-8e-4, x_pitch=1e-3, tilt=0.02`; child `x_offset=2e-4`, bend `L=2, angle=0.5`, `ref_tilt=0.4`), and exactly `0.0` with the parent unmisaligned (same `RefTilted` inside). This is the 2026-08-18 defect ("tracking rolled a nested cell's bends while the survey laid them flat", floor_plan.jl:128-136) re-opened through the override channel that beam_line.jl:46-48 documents as a supported way to set placement parameters.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus; b()=SBendSpec(L=2.0,angle=0.5,nst=4); o=BeamLine("o",DriftSpec(L=1.0),BeamLine("sub",b();x_offset=1e-3),DriftSpec(L=3.0)); line_entries(o)[2].ref_tilt=0.4; r=BeamLine("o",DriftSpec(L=1.0),BeamLine("sub",b();x_offset=1e-3,ref_tilt=0.4),DriftSpec(L=3.0)); f=survey(o)[end]; g=survey(r)[end]; println((f.theta,f.phi,f.psi)); println((g.theta,g.phi,g.psi)); u=(1e-3,2e-4,-5e-4,1e-4,0.0,1e-3); t(l)=collect(foldl((c,op)->op(c...),[e.element for e in Octopus._runtime_entries(TrackingTask(l)) if e isa Octopus.PhysicsEntry];init=u)); println(maximum(abs,t(o).-t(r)))'` — prints `(-0.5, 0.0, 0.0)` for the override line (roll ignored by the survey), `(-0.46619, -0.18780, -0.04471)` for the spec-level line, and `0.0` for the tracking difference (both roll). Then `result/comprehensive_audit_2026_10_18/probes/U49/probe3_girder_override.jl` prints `|override - spec-level roll| = 1.505e-02` for the misaligned parent and `0.000e+00` for the unmisaligned one.

### LEAD U49-2 [Minor, confidence high] src/elements/floor_plan.jl:102
Claim: The `survey` docstring still says kept-whole sub-lines are descended as "the opposite choice from the arc walker, and deliberate on both sides", which the 2026-10-18 change (the arc walker now descends kept-whole lines) made false — the one surviving description of the old behaviour found outside `docs/history/` (hypothesis 1).
Mechanism: Tasks.jl:782-791 now says the arc walker "DESCENDS a line spec it meets -- a kept-whole (own-state) line in the task tuple ... entry by entry" (U2-5, 2026-10-18), and the probe shows the bend inside an own-state sub-line found at `s = 1.0` by `_collect_spec_s!`; rf_cavity.jl:503, Tasks.jl:1853-1858, aperture.jl's `loss_record` ParamMeta, arc_survey_and_velocity_slip.md:44-51 and runtests 14965-14975 were all updated, this docstring was not. A reader of `?survey` is told the two walkers differ on containers when they now agree.
Repro: `grep -n "opposite choice from the arc walker" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/floor_plan.jl` (one hit) against `grep -n "DESCENDS a line spec" /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/Tasks.jl` (one hit); `result/comprehensive_audit_2026_10_18/probes/U49/probe1_anchors.jl` last block prints `arc walker: bend at s = 1.0, total = 6.0`.

### LEAD U49-3 [Minor, confidence high] docs/theory/arc_survey_and_velocity_slip.md:53
Claim: "The floor plan proper — global `(X, Y, Z, θ, φ, ψ)` per element ... remains future work" is stale: the floor plan landed the same day the note's status banner is dated (2026-08-14, `src/elements/floor_plan.jl`, `survey`, `FloorFrame`, the extended `MADXSurveyConsistencyContract`).
Mechanism: The note's status block (L3-12) was updated to "implemented" for the slip channel but §1's last paragraph kept the pre-floor-plan statement; misalignment_and_patch_maps.md:446-457 records the floor plan as **Done (2026-08-14)** and floor_plan_survey.md is indexed, so the three notes disagree on whether the geometry layer exists.
Repro: `grep -n "remains future work" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/arc_survey_and_velocity_slip.md` (one hit) and `grep -n "^export FloorFrame, survey" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/floor_plan.jl` (one hit).

### LEAD U49-4 [Minor, confidence high] docs/theory/floor_plan_survey.md:3
Claim: The status banner says the note was "written BEFORE the implementation" and the probe numbers are "re-checked ... once implemented", while the note's own §4 item 2 (L125-135) records "Measured at implementation (2026-08-14)" and the code is installed; floor_plan.jl:1-2 likewise still opens with "Draft of src/elements/floor_plan.jl — reviewed against the theory note before installation; installed only after the audit commit lands."
Mechanism: Two pre-implementation markers were never retired when the implementation and its MAD-X contract landed; a reader is told the derivation is unverified when the suite pins it (runtests 14289-14335, contract worst deviation `7.105e-15` measured here).
Repro: `grep -n "written BEFORE the implementation" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/floor_plan_survey.md; grep -n "Measured at implementation" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/floor_plan_survey.md; head -2 /cfs/ad/dxu/Library/Julia/Octopus/src/elements/floor_plan.jl` — both markers present alongside the "Measured at implementation" record.

### LEAD U49-5 [Minor, confidence high] docs/theory/rf_cavity_and_reference_energy.md:8
Claim: The status banner says "§9's question 3 (`harmon`) remains open" while §9 item 3 (L392-401) is struck through as "Settled (2026-08-14): both, in sequence" and the code implements it (`ThinRFCavitySpec(harmon=h)` → `k = NaN` until `_bind_survey`, static refusal at the kick).
Mechanism: The banner was written at the 2026-08-05_b audit (U26-13) and §9 item 3 was settled nine days later without the banner being re-read; the note now contradicts itself in its first ten lines.
Repro: `grep -n "remains open" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/rf_cavity_and_reference_energy.md` (L8) against `grep -n "Settled (2026-08-14)" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/rf_cavity_and_reference_energy.md` (L394); probe1 prints `k = NaN ds_turn = NaN` and the kick's static message for a bare harmon cavity.

### LEAD U49-6 [Minor, confidence med] docs/theory/rf_cavity_and_reference_energy.md:340
Claim: "item 5 (PTC, for THIS kind) remains open in `todo.md`" names a ledger row that does not exist — `docs/todo.md` mentions PTC only in the Twiss row (L20) and the Bmad-reference-case row (L58), and `docs/history/todo_ledger_archive.md` has no accelerating-cavity PTC row either — so the owed PTC pin of the accelerating cavity's phase convention (§8 item 5, "what pins the phase convention rather than merely documenting it") is tracked nowhere.
Mechanism: Either the row was never opened or it was dropped when the ledger was archived; the design authority points at a ledger entry as the place the obligation lives, and the pointer is dangling, so the item has silently left the definition of done (defect class 14).
Repro: `grep -n "PTC" /cfs/ad/dxu/Library/Julia/Octopus/docs/todo.md | cut -c1-80` (two rows, neither about the accelerating cavity); `grep -n -i "accelerating" /cfs/ad/dxu/Library/Julia/Octopus/docs/history/todo_ledger_archive.md | grep -i "PTC"` (no output).

### LEAD U49-7 [Minor, confidence med] docs/theory/rf_cavity_and_reference_energy.md:339
Claim: "§8's items 1–3 are suite testsets" over-claims item 3 (symplecticity "by complex step, as every other element") for the accelerating cavity, and rf_cavity.jl:923 ("det J = rho^3, symplectic after undoing the rescale ... are pinned in the suite") over-claims the second law: the Scope B testset pins the thin limit, the zero-voltage identity, `px, py` scaling and `det(J) ≈ rho^3` (ForwardDiff), and nothing checks symplecticity after undoing the rescale.
Mechanism: runtests 15007-15075 ("Accelerating cavity changes the reference exactly (Scope B)") read in full: the only Jacobian assertion is `isapprox(det(J), op.rho^3; rtol=1e-12)`; `grep -n -i "undoing\|undo the rescale" test/runtests.jl` returns nothing; Contracts.jl:3209 exempts `:thin_accelerating_cavity` from the symplecticity tripwire. A determinant equal to `rho^3` is necessary, not sufficient, for `J/rho`-rescaled symplecticity, so the stated pin is weaker than claimed.
Repro: `grep -n -i "undoing\|undo the rescale\|after the rescale" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` (no output) and `grep -n "rho^3\|rho\^3" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` (the one `det(J)` line).

### LEAD U49-8 [Minor, confidence high] docs/theory/bpm_measurement_model.md:142
Claim: "observers currently have no naming scheme" (L140-143) and "Naming and discovery ... observers have no naming scheme ... Recorded rather than solved here" (L210-214) are stale: `BPMObserver(name; ...)` takes `name` as its first positional argument, `name` is the first entry of `_BPM_OBSERVER_OPTION_SCHEMA`, and the artifact group is `/bpm/<name>`.
Mechanism: The naming question was answered on the observer when it was built (BPMObserver.jl:88-89, 130, 387-388, 404-405) and the note's §3 and §6 were not revisited; a reader is sent to a ledger row for a feature the constructor already has.
Repro: `grep -n "no naming scheme" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/bpm_measurement_model.md` (two hits) against `grep -n "name::String\|function BPMObserver(name" /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/BPMObserver.jl`.

### LEAD U49-9 [Minor, confidence high] docs/theory/arc_survey_and_velocity_slip.md:131
Claim: The probe numbers §4 calls "the record" — `ν_s = 0.004028`, the prediction `0.0021744`, the corrected `0.0021973`, `max|z| = 1.0000233×10⁻³` over 4096 turns — have no committed harness, no stated voltage and no stated tune-extraction method, and appear nowhere else in the repository (hypothesis 3; defect class 14).
Mechanism: `grep -rn "0.0021744\|0.004028\|0.0021973\|1.0000233" --include=*.jl --include=*.md .` (excluding `result/`) hits only this note. The suite's F16 testset uses a different point (200 kV, `rtol 5e-3`) so it cannot reproduce these digits, and the only committed slip probe (`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/p1_rf_slip.jl`) is a different ring (`C = 1000 m, h = 5, V = 6 MV`). Re-measured here at the contract fixture's voltage (`V = 1 MV`, `h = 1`, `C = 100 m`): bound `0.0020935`, bare `0.0038498`, ratio `1.839`, `max|z| = 1.000021594e-3`, matching the analytic values to 5 digits but not the note's digits (whose implied voltage is ~1.08 MV under the §8 item 4 formula). The physics claim stands; the numbers are unreproducible as quoted.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && grep -rn "0\.0021744\|0\.004028\|0\.0021973" --include=*.jl --include=*.md docs src test validation examples` (only the note); `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U49/probe2_contracts_seam.jl` section (c) prints the substitute measurement.

### LEAD U49-10 [Minor, confidence high] docs/theory/misalignment_and_patch_maps.md:445
Claim: "the aperture deliberately carries its own `dx`/`dy` rather than routing through the misalignment frames — see that note's Section 4" points at the wrong section: aperture_and_particle_loss.md §4 never mentions `dx`/`dy`; the interaction is §5's bullet "Interaction with misalignment" (L375-379), which is still phrased as an OPEN question ("If the aperture is a separate element this is the user's problem"), while the decision lives only in aperture.jl:427-433.
Mechanism: The decision was recorded on the element docstring and cross-referenced from the misalignment note by section number; the aperture note was never updated to carry it, so the authority the pointer names does not contain the thing pointed at, and the aperture note's open-question list still includes an answered item (its own L387 defers the answers to the archive, not to the code).
Repro: `grep -n "dx\|Interaction with misalignment" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/aperture_and_particle_loss.md` (the only `dx`/`dy` discussion is §5's open bullet) and `grep -n "deliberately \*\*not\*\* routed" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/aperture.jl`.

### LEAD U49-11 [Minor, confidence high] docs/theory/misalignment_and_patch_maps.md:402
Claim: §7 item 3 ("Reuse `_rot_xz` ... `ROT_YZ` should be the x↔y relabelling of it") recommends a factorization the implementation did not take — misalignment.jl forms one `W` and one drift (`_frame_change`, L76-88; header L22-26) and never calls `_rot_xz` — and §8 does not mark the item superseded, while §7 item 1 already recommends the opposite; the §6a paragraph at L263-268 also refers to "§6a below" from inside §6a.
Mechanism: §7 is a pre-implementation design list; item 1 (Bmad's single-W factorization) and item 3 (PTC's one-parameter maps) are mutually exclusive, item 1 was built, and the "Open questions" section closes items 1, 2 and 4 of its list but never records that item 3 was dropped; the self-reference is a leftover from moving the correction paragraph into §6a.
Repro: `grep -n "_rot_xz" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/misalignment.jl` (no output) against `grep -n "_rot_xz" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/misalignment_and_patch_maps.md` (three hits, two in §7 item 3); `grep -n "§6a below" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/misalignment_and_patch_maps.md` (one hit, inside §6a).

### LEAD U49-12 [Minor, confidence med] docs/theory/floor_plan_survey.md:99
Claim: Three statements about the implementation are inaccurate: "the implementation asserts exactly this before anything else" (L99-100; floor_plan.jl contains no assertion — the suite pins the triple at runtests 14304-14306), §5's "composes the SAME rotation primitives `_frame_change` already implements" (L145-150; floor_plan.jl:27-39 defines its own `_fp_ry`, `_fp_rz`, `_fp_mul`, a second copy of the rotation convention, reusing `_patch_rotation` only for patches), and the §2 table (L40) lists the solenoid as a straight element while the code's generic `h` rule (floor_plan.jl:48-52, 82-84) bends a curved solenoid (`SolenoidSpec` has `h`, solenoid.jl:601), as arc_survey_and_velocity_slip.md:24-27 says.
Mechanism: The note predates the implementation (its banner says so) and was not reconciled afterwards; the duplicated rotation helpers are covered by the MAD-X contract and the girder/`_survey_frame` equivalence pins, so this is documentation drift rather than a numerical defect.
Repro: `grep -n "@assert\|assert" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/floor_plan.jl` (no output); `grep -n "_fp_ry\|_fp_rz\|_misalign_matrix\|_m3(" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/floor_plan.jl` (own helpers, no `_misalign_matrix`/`_m3` use); `grep -n "h=ParamMeta" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/solenoid.jl`.

### LEAD U49-13 [Minor, confidence med] docs/theory/aperture_and_particle_loss.md:307
Claim: "storing and calling a closure works today, verified directly" with the `MarkerSpec(alive = ...)` snippet is stale as a behaviour statement: the snippet now emits the `ElementSpec{:marker}: unknown parameter(s) stored as descriptive metadata only` warning (Knowledge.jl:139) because `alive` is not a marker parameter, and the supported home for the predicate is `ApertureSpec(alive=...)`.
Mechanism: The unknown-keyword guard landed after the note (defect class 5 remediation), turning the note's silent example into a warned one; the note still presents it as the verified way to store a predicate.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus; s = MarkerSpec(alive = (x,px,y,py,z,pz) -> x*x + y*y < 1e-4); println(getparam(s, :alive, nothing)(1e-3,0,0,0,0,0))'` — prints the warning naming `:alive`, then `true`.

### LEAD U49-14 [Minor, confidence high] src/elements/patch.jl:6
Claim: patch.jl:6 and its `construction_help` (L296) cite "docs/theory/misalignment_and_patch_maps.md Section 7.5", a section that does not exist — the patch recommendation is §7 item 5 (L413-417). Out of region (reference file), reported as a pointer defect into the region.
Mechanism: A numbered-list item was cited as a subsection; the note has no `###` under §7, so the pointer cannot be followed by heading.
Repro: `grep -n "Section 7.5" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/patch.jl` (two hits) against `grep -n "^### \|^## 7" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/misalignment_and_patch_maps.md` (no 7.x heading).

### LEAD U49-15 [Minor, confidence low] docs/public_api.md:1
Claim: The exported floor-plan API (`survey`, `FloorFrame`, floor_plan.jl:3) is not mentioned in `docs/public_api.md`, while `s_positions` and the loss readers are; out of hypothesis and out of region, noted as a seam for the auditor (the document's intended scope may exclude it).
Mechanism: `grep -n -i "survey\|FloorFrame" docs/public_api.md` returns nothing; the floor-plan note and the misalignment note both present `survey(line)` as the user-facing geometry export (misalignment_and_patch_maps.md:450-452).
Repro: `grep -c -i "survey\|FloorFrame" /cfs/ad/dxu/Library/Julia/Octopus/docs/public_api.md` (prints `0`) against `grep -n "^export" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/floor_plan.jl`.

## Clean

Hypothesis 1 (the 2026-10-18 change reflected everywhere): searched `src/`, `docs/` (excluding
`docs/history/`), `validation/`, `examples/`, `test/` for `kept-whole|kept whole|own-state|own_state`
near survey/cavity wording, and for `does not descend|not descend|refused.*inside|hidden cavity`.
Updated and consistent with the new behaviour: Tasks.jl:782-791 (the walker), Tasks.jl:1853-1858
(`_bind_survey`, old refusal phrased as history), rf_cavity.jl:503 (construction_help: "since
2026-10-18; before that it was refused loudly at compile"), aperture.jl `loss_record` ParamMeta
("wrapped or inside a kept-whole line included"), aperture.jl `_aperture_bump!` comment,
arc_survey_and_velocity_slip.md:44-51, runtests 14965-14985 (kept-whole cavity bound to `ds_turn = 3.0`
like the flat placement) and 9909. `docs/design/survey_and_reference_channel.md` never described the
kept-whole refusal (no sub-line/nested/CompositeLine wording at all). `docs/experiences.md:152` is a
historical lesson about the count tripwire and remains true as history. The one stale description is
LEAD U49-2.

Hypothesis 2 (two surveys, one source or two): the floor plan (`_survey_walk!`, `_girder_flat_entries!`
in floor_plan.jl), the arc walker (`_collect_spec_s!`, Tasks.jl), and `s_positions`/`total_length`
(beam_line.jl:461-483) are three traversals sharing only `line_entries` and `_placement_length`.
Measured agreeing: arc totals (`6.0` from both, probe1), the MAD-X contract checks arc columns from the
arc walker and floor columns from `survey` row by row (Contracts.jl:2775-2796; `passed`, worst
`7.105e-15`, 9 fixtures — the misalignment note's "7.1e-15 over nine fixtures" reproduced exactly),
the ring-closure test (runtests 14310-14316), the girder-walk/`survey` bitwise identity recorded in
beam_line_composition.md §10. Disagreeing: the placement-override channel on a kept-whole sub-line
(LEAD U49-1); a lesser asymmetry, noted not raised — the floor plan does not call
`_placement_length(entry)` for a line placement, so an `L` override on a kept-whole sub-line that the
arc walker and `s_positions` refuse by name (beam_line.jl:439-459) passes `survey(line)` silently
(the value is meaningless either way, so only refusal-vs-silence differs).

Misalignment note against misalignment.jl and PTC: the Bmad-factorization/PTC-bookkeeping design
(L22-26, `_frame_change` L76-88), exit frames built from the exit geometry never by inversion
(L158-162, 175-178), centre reference `sref = L/2` for `:bmad` and entrance `0` for `:madx` (L391),
both composition orders (L37-38, 54), the `:madx` conjugation `W → R_z(-ψ) W R_z(ψ)`, `d → R_z(-ψ) d`
(L395-401), only `:bmad`/`:madx` accepted (L386-387), the survey sign `-(1-cos hs)/h` (L115, 128;
`-0.108545` reproduced), the rigid-displacement-of-a-line test (runtests 9689-9700), the curved-girder
closure with `_misalign_frames_from` (runtests 21435+), `_rot_xz` at lattice_magnets.jl:631 and the
`sbend_edge` PTC case. Every number in §6a and §6b reproduced by running the PTC contract (probe2):
`DX/DY/DS 4.10/4.08/4.45e-13` (note 4.1/4.1/4.4), `DTHETA 4.92e-13` (4.9), `DPHI 4.77e-13` (4.8),
`DPSI 4.995e-13` (5.0), all-six `4.957e-13` (4.96), bends `cfbend_mis_dx 4.48e-13`/`cfbend_mis_all
4.47e-13` (4.5), `ref_tilt=0.3` cases `2.79e-13`/`4.46e-13` (2.8/4.5), `ref_tilt` pure dipole
`3.50e-13` (3.5), `π/2` `4.11e-13` (4.1), combined-function `4.65e-13` (4.6), `sbend_edge 4.58e-13`
(the note's "5e-13"). The six case names of §6a and the two of §8 exist in
`validation/generate_ptc_reference.jl` and `src/contracts/Contracts.jl`. `beam_line_composition.md`
§10 (L509-560) does carry the U15-2 closure record the note points to; all six notes are indexed in
`docs/README.md`.

Floor-plan note against floor_plan.jl and MAD-X: every anchor in §2 and §3 reproduced to the printed
digits (probe1, including the `-3.3e-17`/`-8.5e-18` roundoff signature of the vertical bend), the
extraction formulas (L155-157), the transpose-of-`_patch_rotation` rule and the `angle_s` sign
inversion (`ψ = -0.2` for `angle_s = +0.2`, `θ = -0.1` for `angle_y = +0.1`, drift displacement
`3 cos φ sin θ` to 12 digits), the bend row `R_S(t)·(ρ(cos α − 1), 0, ρ sin α)`, `R_S(t) R_Y(−α) R_S(−t)`
(L86-89), initial frame `V = 0, W = I` (L111-112), misalignments/`tilt` excluded (runtests 14318-14320),
the `asin` clamp at the gimbal edge (L156), the nine contract fixtures including `vertical_bend`,
`patch_srot` (twin `angle = -0.2`), `patch_yrot`, `rbend_chord`, `nested_reflected`, and the
`sub-line ref_tilt` conjugation (L128-141) for the spec-level case.

Arc-survey note against the code: `s` as summed placement lengths with `L` the arc for curved kinds
(Tasks.jl:807-833; beam_line.jl:438-461), `PatchSpec` `dz` omitted from the arc (`_placement_length`
reads `:L` only; s_positions docstring), `RBendSpec(chord=…)` with the fold `L = chord·(θ/2)/sin(θ/2)`
(lattice_magnets.jl:1393-1418; `rbend_chord` fixture, Contracts.jl:2697-2703), `_velocity_slip_g`
identical to the note's `g(δ)` (rf_cavity.jl:72-74), the z-shift before the unchanged conjugated body
and the per-op constant with no turn counter (rf_cavity.jl:123-127, 199-206), `Δs` as the arc from the
previous kick wrapping the turn (Tasks.jl:1860-1875; two-cavity partition pinned at runtests 9911-9917),
the suite pins of §5: ν_s against the full η (runtests 14812+), the transition-side A/B (14905-14920),
`_velocity_slip_g` against BigFloat (14922-14940), the walker against `s_positions` (14958-14963) and
MAD-X (14289+). The 1.84× separation reproduced: `0.0038498/0.0020935 = 1.839` (probe2).

RF note against rf_cavity.jl and longitudinal.jl: both constructor forms and the `harmon` keyword
form (L300-335, 503), body `pt += strength*sin(k*z1 + phase)` in `TIME_ENERGY` with the β's in the
wrappers (L158-163), drift-kick-drift with `L = 0` the exact thin limit (L170-180), no energy stored and
`rf_strength` the single `E0` read (L217-227), `reference_pair_residual`/`_check_reference_pair`
(longitudinal.jl:159, 175) and the corrected symplecticity fixture (Contracts.jl:1891-1894, residual
1.8e-13 as the note says), the four named conventions (longitudinal.jl:33-37), `convert_longitudinal(…;
s = 0)` (365-366), `execute!(task, beam::Beam)` dropping to `beam.rep` (Tasks.jl:934), the `kbb`
formula as the examples derive it (`examples/weak_strong_tracking.jl:297`), Scope B's
`_accelerating_exit_pair`, `ρ` on `px, py, p_t`, `det J = ρ³` by ForwardDiff (runtests 15039-15040),
cos body with `phase = 0` on crest, the chain validation; the 4.6e-3 rad crab/RF argument difference
reproduced at 400.8 MHz (`4.637e-3`; the frequency is unstated in the note). The `thin_crab_cavity`
snippet (L91-94) matches crab_cavity.jl:135-137, 168.

Aperture note against aperture.jl: the §4 recommendations are what was built (shapes `:rectangle`,
`:ellipse`, `:rectellipse`; `x_limit`/`y_limit`; `alive` as a type parameter; `dx`/`dy`;
`NonSymplectic6DMap`), the §2 mechanisms (transition detection over all six coordinates via `is_live`
L269-273, kill to NaN, record written before the kill, 8-wide `(turn, element_id, x, px, y, py, z, pz)`
slot per particle, running counter with a CPU spin lock and a CUDA atomic, `~64 N` bytes only on
request, no compaction, `loss_summary` exposing `dead - logged`), §6's "the file carries only the lost"
(`write_loss_record`), `allow_lost_particles()` default `false`, "five slicing methods" = five distinct
(`equal_area, equal_count, equal_width≡equal_spaced, normal_quantile≡gaussian≡Gaussian, specified`,
slicing.jl:92-96), `gaussian.jl:93` inside the finite-moments guard (L86-93), Contracts.jl:58-59
carrying the quoted RNG-key sentence, the `pz` fail-fast gap recorded as a standing decision
(experiences.md:1748-1750), the chokepoint testset (25668+) not poisoning `pz` as the note says,
`TrackingContext.turn` (Track.jl:20-25), `docs/history/todo_ledger_archive.md` present.

BPM note against BPMObserver.jl: the §4 formula term for term (L37-38, 202-210: offset inside `R` and
`G`, readout outside, noise last; `R = [c s; -s c]` from `_misalign_matrix`), nine error fields,
`octopus_normal(seed, method, turn, rng_id, occurrence, component)` (the 6-argument method exists,
counter_rng.jl:456), `next_rng_id!`/`claim_rng_id!`, the centroid over surviving particles (L256-303),
the §2 cancellation reproduced bit for bit (probe1), §7 items 1-5 all pinned in "BPM reads a device
number, not the truth" (runtests 24575+: centroid equality, passive bit-identity, MAD-X limit
`1.5·2e-3 + 1e-4`, every term moves the reading, chunk-invariant noise, sample std within 10% of
`2e-5`), the chunked-execution testset (8004), `_execute_tracking_task!`, `prepare_line_observers!`,
`_runtime_entries` (the note writes `runtime_entries`; naming nit, not raised), `PlaceholderPolicy`,
no observer in `docs/registry_snapshot.md` (consistent with L140-143).

## Unchecked

- The external-code citations in all six notes (PTC `Sm_tracking.f90`, `Sl_family.f90`, `Sd_frame.f90`,
  Bmad `track_a_patch.f90`, `offset_particle.f90`, `bmad_struct.f90`, AT `bpm_matrices.m`, MAD-X
  `mad_dict.c`, Xsuite/Elegant headers) and the quoted Fortran/MATLAB fragments: not opened; the
  comparison here is notes-vs-Octopus only, with PTC and MAD-X behaviour taken from the committed
  reference tables the contracts run against.
- The RF note's Step 0 precision numbers (`4.4e-16` round trip and symplecticity, `2.2e-16`/`3.2e-16`
  relative against BigFloat, `8.9e-5` at `p_t = 1e-12`, the `2.0e-2` and `-3.8e-8` fixture residuals):
  not re-measured; their provenance is the 2026-08-05_b U14 report under `docs/history/`, and the suite
  carries a conversion round-trip test (runtests 11242-11244) but no BigFloat pin of the conversion
  itself (only of `_velocity_slip_g`).
- The misalignment note's `:bmad` branch against Bmad (no reference case; `docs/todo.md` row 58,
  known and not re-raised).
- CUDA execution of the floor plan, aperture logging and the surveyed cavity: every probe here ran on
  the CPU; the CUDA testsets named in the files (runtests 15198, the aperture CUDA arms) were not run.
- The `docs/history/todo_ledger_archive.md` "step 3" answers the aperture note defers to (L387-388)
  and the archived BPM/observer-identity rows: file existence checked, contents not read.
- `docs/public_api.md`'s intended scope (whether `survey`/`FloorFrame` are deliberately undocumented),
  which decides LEAD U49-15.
