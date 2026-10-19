# U18: beam_line.jl + aperture.jl + misalignment.jl + ref_tilt.jl + patch.jl + floor_plan.jl

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every
claim below is a LEAD, not a finding. Line numbers are pointers into 24e8683; the Repro line
is the durable identity of each lead.

## Region

| file | lines read |
|---|---|
| `src/elements/beam_line.jl` | 1-930 (all) |
| `src/elements/aperture.jl` | 1-679 (all) |
| `src/elements/misalignment.jl` | 1-410 (all) |
| `src/elements/ref_tilt.jl` | 1-168 (all) |
| `src/elements/patch.jl` | 1-297 (all) |
| `src/elements/floor_plan.jl` | 1-227 (all) |

Total 2711 lines, all read line by line. Hypotheses briefed: (1) kept-whole vs dissolved lines
and every walker's view of them, including floor-plan survey vs misalignment survey; (2) frame
maps, roll and patch conventions against the note, inverse round trips, the placement-parameter
inactive table; (3) aperture: bare `track!` (kill, no record) vs the task path, shapes and
offsets, the loss-record write guard.

## Provenance

READ (line by line): the six region files in full, as tabled above. Reference notes read for
comparison: `docs/theory/floor_plan_survey.md` 1-155 (all); `docs/theory/beam_line_composition.md`
362-445 (§7b-§8 head) and 509-563 (§10); `docs/theory/misalignment_and_patch_maps.md` 185-465
(§5-§8); `docs/theory/aperture_and_particle_loss.md` 109-132, 329-363, 390-405. Cross-file reads
made only to confirm or bound a lead (seams, not audited): `src/tasks/Tasks.jl` 726-832
(`_aperture_specs`, `_aperture_s_positions`, `_collect_spec_s!`) and 1745-1800 (the loss-record
`fits` test and `_bind_apertures`); `src/knowledge/Knowledge.jl` 236-300 (`_PLACEMENT_PARAMS`);
`src/contracts/Contracts.jl` `DEFAULT_INACTIVE_ELEMENT_PARAMS` block; `src/knobs/Knobs.jl`
1038-1041 and `src/elements/turn_modulated.jl` 1452-1464 by grep; `ext/OctopusForwardDiffExt.jl`
(15 lines); `test/runtests.jl` 15150-15200, 15848-15900, 18722-18792, 26878-26900; `Project.toml`
by grep. Greps over `src/` for `_loss_record_matches_rep`, `:entries`, `_has_knob_parameters`,
`_patch_reference_length`, `_floor_children`, `_curv_vers`, `_ref_tilt_wrap(`, `_misalignment_wrap(`,
`struct .* <: AbstractTrackOp`, `DEFAULT_INACTIVE_ELEMENT_PARAMS`, "surveyed as STRAIGHT".

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U18/`,
each run as `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`, logs beside
the scripts as `<script>.log`; CPU only, no CUDA or MPI probe was run):

- `probe1.jl` (P1-P4; aborted at P4's `compile_runtime`, which is itself a measurement):
  `_loss_record_matches_rep` = `false` for a Float32 rep's own freshly allocated logging record,
  `true` for `log=false` and for Float64; `element_help(:line)` contains "assembly survey is
  STRAIGHT" and "compiling one warns"; `_has_knob_parameters(outer)` = `true` while
  `knob_report(outer)` prints "No knob-driven parameters" for a girder whose own `x_offset` is a
  knob and for a knob override on a line placement; `outer3[1].L = 5.0` ACCEPTED, then
  `s_positions(outer3)` throws.
- `probe1b.jl` (P4b, P5-P15): `compile_runtime(outer3)` throws at `total_length`; entries container
  `Vector` (both constructors) vs `Tuple` (`reverse`); keyword slice `head[1] === arc[1]` = `true`,
  `head[1].x_offset = 1e-3` sets `getparam(arc[1], :x_offset)` = 0.001, `entry_path(head[1])` =
  `ARC/QUADRUPOLE`, `find_entries(head, sel"HEAD//QUADRUPOLE")` = `Int64[]`; positional slice copies
  and re-roots; `PatchSpec(convention="madx")`: `Patch(spec).madx` = `true` but `_floor_step` uses
  the bmad order, max|R_madx - R_bmad| = 5.87e-2; sub-line `ref_tilt` placement override: tracking
  diff 0.0 vs on-spec, survey exit differs by 2.881e-1; patch `ref_tilt=pi/2`: tracked (px,py) =
  (0, 0.0998) vs (0.0998, 0), survey exit unchanged, `_floor_step(p1) == _floor_step(p0)`;
  `_floor_arc_step` vs `_curv_vers`: rel. err 1.0 (h=1e-4, l=1e-6), 7.99e-4, 8.27e-8, 9.3e-16;
  arc identity at h=0.3: max|A-R| = 0, max|o-d| = 1.4e-16; patch exact-inverse round trip:
  transverse/momenta residuals <= 4.4e-18, z residual -1.033905e-3 for both test particles,
  equal to the predicted constant -1.033905e-3; `survey(rolled)` exit (-0.739919, 0, 2.895740) vs
  `survey((rolled,))` (-0.681510, -0.288138, 2.895740); aperture `x_offset` and `dx` agree on three
  particles.
- `probe2.jl` (ForwardDiff v1.4.6 from the scratch env `fdenv`, stacked on `LOAD_PATH`):
  `Dual(0.0,1.0) == 0` is `false`; single-element wraps are retained at the design point and
  AD = central FD for x_offset (6.8e-1), y_offset, x_pitch, tilt, ref_tilt; the girder case
  `BeamLine("G", quad; x_offset=Dual)` throws `MethodError: no method matching Float64(::Dual)` at
  `misalignment.jl:378`.
- `probe3.jl`: `_misalign_frames` vs `_misalign_frames_from` on arcs: 1.1e-16, 0.0, 4.4e-16;
  `find_entries(outer, sel"OUTER//QUADRUPOLE")` = `Int64[]` (kept-whole interior opaque, by design);
  `_requires_tracking_context` and `_inner_method` each have one method for MisalignedElement,
  RefTilted, CompositeLine, TurnModulated; a recording aperture requires ctx, also inside a
  MisalignedElement; a bare aperture does not.
- `probe4.jl` (task level): Float32 beam + artifact: after the second `execute!` the record is NOT
  reused, counts `[1]` instead of `[2]`, `loss_summary` (dead, logged, unattributed) = (2, 1, 1) and
  the "particles were lost with no aperture responsible" warning fires; Float64 + artifact control:
  reused, `[2]`, (2, 2, 0); Float32 without artifact control: reused, `[2]`, (2, 2, 0).
- `probe5.jl`: misaligned girder containing a sub-line rolled by placement override vs by spec:
  members identical (0.0), girders differ by 2.333e-5; girder containing a rolled patch vs its
  plain vertical twin: patches identical (6.1e-18), girders differ by 9.983e-5, survey exits
  (-0.0998, 0, 0.995) vs (0, -0.0998, 0.995); `outer[1].entries = ...` ACCEPTED, walkers read the
  spec (total_length 1.4).
- `probe6.jl`: the compiled placement tracks the `entries` OVERRIDE (x = 0.002396 = the 7 m drift)
  while `total_length` = 1.4 and `s_positions` = [0.0, 0.4] read the 0.4 m spec.

## Leads

### LEAD U18-1 [Major, confidence high] src/elements/aperture.jl:139
Claim: A Float32 beam with a run artifact can never reuse its loss record, so every `execute!` reallocates it, zeroes the cumulative counters and reports the earlier losses as unattributed with a warning.
Mechanism: `_loss_record_matches_rep` requires `eltype(record.slots) == eltype(rep.x)`, but the allocator at aperture.jl:113 widens the slots to `promote_type(eltype(rep.x), Float64)` (the U15-11 turn-number fix), so for a Float32 rep a record allocated by `LossRecord(names, n, rep; log=true)` is `Float64` slots against a `Float32` rep and the predicate is false for the record's own rep. The Tasks.jl `fits` test (Tasks.jl:1771) includes this predicate, so with an artifact (slots wanted) the record is rebuilt on each window: counts restart, the previous window's kills become `dead - logged`, and the unattributed warning blames a numerical blowup. `log=false` (no artifact) is unaffected because the slots test short-circuits; Float64 beams are unaffected. Hypothesis 3 class (the record's reuse protocol); defect class 7 and 6.
Repro: `julia --project=. -e 'using Octopus; z=zeros(Float32,4); rep=Phase6DRep(z,z,z,z,z,z); r=Octopus.LossRecord(["A"],4,rep;log=true); println(eltype(r.slots), " ", Octopus._loss_record_matches_rep(r,rep))'` prints `Float64 false` (should be `true`); task level: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U18/probe4.jl` prints `record reused = false  counts = Int32[1]  summary ... = (2, 1, 1)` for the Float32+artifact case against `(2, 2, 0)` for both controls.

### LEAD U18-2 [Moderate, confidence high] src/elements/misalignment.jl:378
Claim: A dual-number (or any non-`Float64`-convertible) alignment parameter on a BEAM LINE throws `MethodError: Float64(::Dual)` in `_misalignment_wrap`, although the same function documents dual seeding as a supported use and the single-element path differentiates correctly.
Mechanism: `T = _wrap_numeric_type(spec, inner)` (misalignment.jl:281, fix H) returns `something(_required_beam_eltype(inner), numeric_type(spec))`; for a line `inner` is the `CompositeLine` of members compiled in their own `Float64`, so `T = Float64` wins over the line spec's own promotion, and `dx = T(getparam(spec, :x_offset, ...))` converts a `Dual` to `Float64`. For a single element `numeric_type(spec)` promotes over the dual and the inner is compiled in it, so `T` is the dual type. The same `T(...)` conversions in `_ref_tilt_wrap` (ref_tilt.jl:164) share the exposure. Hypothesis 2 (frame maps); neighbour of fix H (2026-10-16).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U18/probe2.jl` (needs ForwardDiff on `LOAD_PATH`, see the script): the quadrupole rows print `ForwardDiff = 6.800000e-01   central FD = 6.800000e-01`; the `girder x_offset` row aborts with `MethodError: no method matching Float64(::ForwardDiff.Dual...)` from `_misalignment_wrap`.

### LEAD U18-3 [Moderate, confidence high] src/elements/floor_plan.jl:117
Claim: `survey(line)` ignores the line's own `ref_tilt` while `survey((line,))` and the compiled `RefTilted` wrap apply it, so the exported survey disagrees with tracking for a rolled top-level line.
Mechanism: `survey(line::ElementSpec{:line}) = survey(line_entries(line))` hands the entries to the generic walk and bypasses the `ElementSpec{:line}` branch of `_survey_walk!` (floor_plan.jl:127-142), which is where the design-roll conjugation `W * R_z(psi)` lives; `compile_runtime(line)` (beam_line.jl:763) wraps the composite in `_ref_tilt_wrap(geom, ...)` regardless. Hypothesis 1 (two views of the same kept-whole line, by entry point).
Repro: `julia --project=. -e 'using Octopus; l=BeamLine("R", SBendSpec(L=1.0,h=0.3,b0=0.3), DriftSpec(L=2.0); ref_tilt=0.4); println(survey(l)[end].position, " ", survey((l,))[end].position)'` prints `(-0.739919, 0.0, 2.895740)` (the unrolled line) against `(-0.681510, -0.288138, 2.895740)`.

### LEAD U18-4 [Moderate, confidence high] src/elements/floor_plan.jl:137
Claim: The survey walkers read a kept-whole sub-line's `ref_tilt` from the spec, not the placement, so a `ref_tilt` placement override is honoured by tracking and ignored by `survey` and by a misaligned girder's design frames.
Mechanism: `_survey_walk!` (floor_plan.jl:137) and `_girder_flat_entries!` (floor_plan.jl:171) call `getparam(spec, :ref_tilt, 0.0)` with `spec = getfield(entry, :spec)`, discarding `getfield(entry, :overrides)`, while `compile_runtime(entry::LineEntry)` (beam_line.jl:188-194) merges overrides first ("placement wins", beam_line_composition.md §7b). Because `_girder_design_frames` feeds `_misalign_frames_from`, a misaligned parent girder containing such a placement is tracked with design frames that lack the roll: measured 2.3e-5 against the identical lattice with the roll on the spec, whose members track bit-identically.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U18/probe1b.jl` section P8 prints `max |difference| = 2.881e-01` between the two survey exits and `max|diff| = 0.000e+00` for the tracked members; `probe5.jl` section G1 prints `misaligned girder (override vs spec): max|diff| = 2.333e-05`.

### LEAD U18-5 [Moderate, confidence high] src/elements/floor_plan.jl:62
Claim: `_floor_step` ignores a patch's `ref_tilt`, which `_ref_tilt_wrap` applies in tracking, so a rolled patch is surveyed (and used in a girder's design frames) in the unrolled plane.
Mechanism: the patch branch of `_floor_step` (floor_plan.jl:62-72) returns `(dx, dy, dz)` and `_patch_rotation(...)'` without the `R_z(t) . R_z(-t)` conjugation the arc branch applies at floor_plan.jl:86-89; `compile_runtime` for every kind wraps the runtime in `_ref_tilt_wrap` (Knowledge.jl:1507), so `PatchSpec(angle_y=0.1, ref_tilt=pi/2)` tracks as a vertical kick (py = 0.0998) while its survey step equals that of `PatchSpec(angle_y=0.1)`. Through `_girder_design_frames` the omission reaches tracking: a misaligned girder holding the rolled patch differs by 1.0e-4 from the girder holding the equivalent `PatchSpec(angle_x=-0.1)`, whose patches alone agree to 6e-18. The `DEFAULT_INACTIVE_ELEMENT_PARAMS` table declares no `(:patch, :ref_tilt)` row, so the parameter is active by declaration; hypothesis 2.
Repro: `julia --project=. -e 'using Octopus; p0=PatchSpec(angle_y=0.1); p1=PatchSpec(angle_y=0.1, ref_tilt=pi/2); println(compile_runtime(p1)(0,0,0,0,0,0)[4], " ", Octopus._floor_step(p1) == Octopus._floor_step(p0))'` prints `0.0998... true`; `probe5.jl` section G2 prints `misaligned girders: max|diff| = 9.983e-05`.

### LEAD U18-6 [Minor, confidence high] src/elements/beam_line.jl:897
Claim: `knob_report` reports no knob-driven parameters for a girder whose own `x_offset` is a knob expression (or whose placement carries a knob override), while `_has_knob_parameters` counts both and the girder compiles knob-dependent.
Mechanism: `_knob_binding_sites!(out, entry::LineEntry, ordinal)` returns `_knob_binding_sites!(out, line_entries(spec), ordinal)` for a line spec before calling `_knob_param_sites!` on the entry's merged parameters, and the bare-line method (beam_line.jl:906-907) and top-level method (893-894) likewise descend without visiting the line's own params; `_has_knob_parameters(line::ElementSpec{:line})` (beam_line.jl:163-165) checks `values(params(line))` and the entry overrides. Two walkers over one container disagree (hypothesis 1, defect class 3); the wiring view is the documented answer to "what does this knob drive".
Repro: `julia --project=. -e 'using Octopus; @knob u.gx::Float64=1e-3; o=BeamLine("O", BeamLine("C", QuadrupoleSpec(L=0.4,k1=1.7); x_offset=@knob_expr(u.gx)), DriftSpec(L=1.0)); println(Octopus._has_knob_parameters(o)); knob_report(o)'` prints `true` then `No knob-driven parameters in the given elements.`

### LEAD U18-7 [Minor, confidence high] src/elements/beam_line.jl:81
Claim: An `L` override on a line placement is accepted at assignment and refused only by the next arc-length walk, contradicting the docstring's "the placement refuses it too rather than storing a value it will not use".
Mechanism: `Base.setproperty!(entry::LineEntry, ...)` guards `_ENTRY_FIELDS` and the folded strengths only, then stores the value and bumps the epoch; the refusal lives in `_placement_length(entry::LineEntry)` (beam_line.jl:451), reached from `s_positions`, `total_length`, `compile_runtime(::ElementSpec{:line})` and the Tasks.jl arc walker, so the user's lattice breaks at compile or report time instead of at the assignment the message is about (defect class 6: refusal after the write). The docstring at beam_line.jl:449-450 states the opposite of what the code does.
Repro: `julia --project=. -e 'using Octopus; o=BeamLine("O", BeamLine("C", QuadrupoleSpec(L=0.4,k1=1.7); y_offset=0.0), DriftSpec(L=1.0)); o[1].L=5.0; println(getparam(o[1], :L)); s_positions(o)'` prints `5.0` and then throws `ArgumentError: a beam line's arc length is computed from its entries and cannot be overridden on the placement either`.

### LEAD U18-8 [Minor, confidence med] src/elements/beam_line.jl:372
Claim: The keyword form `BeamLine(; name, entries=arc[1:k])`, documented as "how a slice becomes a line", aliases the given `LineEntry` objects, so an alignment override written on the slice silently appears on the source line, and its paths keep the source's root so the new line's own name matches nothing.
Mechanism: `params[:entries] = collect(LineEntry, entries)` stores the same objects (shared `overrides` Dict and `path` Vector), whereas the positional form `BeamLine("HEAD", arc[1:k]...)` copies overrides and re-roots paths (beam_line.jl:285-292) and `reverse` copies for the U15-3 reason ("error parameters must not share", §7b). The keyword form is also the reflection round-trip constructor, where preserving entries is required, so the two uses pull in opposite directions; what is measurable is that `head[1].x_offset = 1e-3` writes `arc[1]`, and `sel"HEAD//QUADRUPOLE"` returns nothing for a line named HEAD. Hypothesis 1.
Repro: `julia --project=. -e 'using Octopus; arc=BeamLine("ARC", QuadrupoleSpec(L=0.4,k1=1.7), DriftSpec(L=1.0)); h=BeamLine(; name="HEAD", entries=arc[1:2]); h[1].x_offset=1e-3; println(getparam(arc[1], :x_offset), " ", entry_path(h[1]), " ", find_entries(h, sel"HEAD//QUADRUPOLE"))'` prints `0.001 ARC/QUADRUPOLE Int64[]`.

### LEAD U18-9 [Minor, confidence high] src/elements/floor_plan.jl:69
Claim: A patch `convention` given as a String is accepted silently and read by two consumers with two normalisations, so the tracked patch composes its rotations in the `:madx` order while the survey composes them in the `:bmad` order.
Mechanism: `Patch(spec)` (patch.jl:263) normalises with `Symbol(getparam(spec, :convention, :bmad))`, so `"madx"` becomes `:madx`; `_floor_step` tests `getparam(entry, :convention, :bmad) === :madx`, which is false for the String, and no construction-time check compares the value against the declared `alternatives=(:bmad, :madx)`. Two walkers over one parameter (class 3) under a silently accepted value type (class 5); the two orders differ at second order in the angles (5.9e-2 in the matrix for 0.2 and 0.3 rad).
Repro: `julia --project=. -e 'using Octopus; s=PatchSpec(angle_x=0.2, angle_y=0.3, convention="madx"); d,R=Octopus._floor_step(s); println(Octopus.Patch(s).madx, " ", R == Octopus._fp_transpose(Octopus._patch_rotation(Float64,0.2,0.3,0.0,true)))'` prints `true false`.

### LEAD U18-10 [Minor, confidence high] src/elements/floor_plan.jl:87
Claim: `_floor_arc_step` forms the arc sagitta as `rho * (cos(alpha) - 1.0)`, the cancellation-prone form that `_survey_frame` avoids with `_curv_vers`, so the two surveys' pinned identity holds only outside the small-angle regime.
Mechanism: for `alpha = h * ell` small, `cos(alpha) - 1` loses all relative precision (`cos(1e-10) - 1 == 0` in Float64) and the result is scaled by `rho = 1/h`; `_survey_frame` (misalignment.jl:128) and the lattice drift route the same quantity through the cancellation-safe `_curv_vers` (lattice_magnets.jl:68). Measured relative error of the floor-plan component against `-_curv_vers(h, ell)`: 1.0 at (h, ell) = (1e-4, 1e-6), 8.0e-4 at (1e-3, 1e-4), 8.3e-8 at (1e-2, 1e-3), 9.3e-16 at (0.3, 1.0); absolute error <= 4e-15 m, so physically negligible, but the "a single arc reproduces `_survey_frame` identically" statement (floor_plan.jl:191-193) carries no regime (defect classes 12 and 8). A partial girder step (`starget - s` tiny) is the realistic path into the regime.
Repro: `julia --project=. -e 'using Octopus; h=1e-4; l=1e-6; d,_=Octopus._floor_arc_step(SBendSpec(L=l,h=h,b0=h), l); println(d[1], " ", -Octopus._curv_vers(h, l))'` prints `-0.0 -4.9999999999999999e-17` (or `0.0`), i.e. relative error 1.

### LEAD U18-11 [Minor, confidence high] src/elements/patch.jl:234
Claim: The docstring's "Composing a patch with its exact inverse is the identity" (also `construction_help`, patch.jl:296) holds for the transverse coordinates and momenta but not for `z`, which shifts by a constant equal to the summed reference path lengths of the two patches whenever transverse offsets and rotations are both present.
Mechanism: each patch measures `z` against its own on-axis reference particle (patch.jl:158-167); the inverse patch's reference is a different particle, so the composite subtracts `R1 + R2 = (W7 dx + W8 dy + (W9 - 1) dz) / W9`, which is nonzero unless `dx = dy = 0` (then `W9 = 1` is not needed: `(W9-1)dz/W9` remains unless the rotation is pure roll). The exact inverse is constructible (rotation `W'`, which is the `:madx` order with negated angles, and translation `-W d`), and with it the measured residuals are <= 4.4e-18 in (x, px, y, py, pz) and -1.033905e-3 in z for every particle, equal to the predicted constant to the printed digits. The map is Bmad's convention and the test at test/runtests.jl:26884ff pins the single-patch `z = 0` invariant correctly; the lead is the unqualified identity claim (class 14), and that no API offers the exact inverse the claim invites a reader to test.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U18/probe1b.jl` section P11 prints `residual (x,px,y,py,z,pz) = (2.3e-18, -3.5e-18, 3.5e-18, 0.0e+00, -1.033905e-03, 0.0e+00)` and `predicted constant z shift ... = -1.033905e-03`.

### LEAD U18-12 [Minor, confidence high] src/elements/beam_line.jl:785
Claim: The `:line` `x_offset` metadata still tells `element_help` readers that the assembly survey is STRAIGHT, that a girder containing bends has an exit patch wrong at first order, and that compiling one warns, all of which were retired on 2026-08-16.
Mechanism: the ParamMeta `meaning` string was not updated when the floor-plan design frames landed; the file's own comments at beam_line.jl:744-771 and beam_line_composition.md §10 record the retirement and the 1e-14 exactness pin. Documentation as claims (class 14) on the public help surface.
Repro: `julia --project=. -e 'using Octopus; h=sprint(io->element_help(io,:line)); println(occursin("assembly survey is STRAIGHT", h), " ", occursin("compiling one warns", h))'` prints `true true` (should be `false false`).

### LEAD U18-13 [Minor, confidence high] src/elements/floor_plan.jl:1
Claim: The file opens with "Draft of src/elements/floor_plan.jl -- reviewed against the theory note before installation; installed only after the audit commit lands", a stale status line on an installed, exported module file.
Mechanism: the header describes a pre-installation state; `export FloorFrame, survey` follows on line 3 and the file has been live since 2026-08-14 (floor_plan_survey.md §4 "Measured at implementation"). Class 14.
Repro: `sed -n '1,3p' src/elements/floor_plan.jl` prints the draft header followed by the export line.

### LEAD U18-14 [Minor, confidence med] src/elements/floor_plan.jl:103
Claim: The `survey` docstring says kept-whole sub-lines are descended as "the opposite choice from the arc walker, and deliberate on both sides", but since 2026-10-18 the task's arc walker descends them too; only `s_positions(line)` keeps the one-unit view.
Mechanism: `_collect_spec_s!` (Tasks.jl:797-798 and the `LineEntry` method following it, U2-5 2026-10-18) now descends a line spec or line placement entry by entry, while `s_positions` (beam_line.jl:474-483) still advances by `_placement_length` of the kept-whole placement; the docstring names a single "arc walker" whose behaviour it no longer describes. Class 14; hypothesis 1 (the two arc walkers now differ in granularity while agreeing on accumulated arc).
Repro: `julia --project=. -e 'using Octopus; o=BeamLine("O", BeamLine("C", QuadrupoleSpec(L=0.4,k1=1.7); x_offset=1e-4), DriftSpec(L=1.0)); println(s_positions(o), " ", length(survey(o)))'` prints `[0.0, 0.4] 2`; `grep -n "DESCENDS a line spec" src/tasks/Tasks.jl` shows the arc walker's own descent.

### LEAD U18-15 [Minor, confidence high] src/elements/patch.jl:190
Claim: `_patch_reference_length` has no caller, yet its docstring describes a live role ("Subtracting it is what keeps `z` measured against the reference") that `_patch_map` now performs inline.
Mechanism: the U16-4 fix moved the reference bookkeeping into `_patch_map` (`ref_excess`, patch.jl:162-167) and left the helper and its narrative behind; `grep -rn _patch_reference_length src/ test/` finds only the definition and a test comment. Dead code carrying a documentation claim (class 14).
Repro: `grep -rn "_patch_reference_length" src/ test/ | grep -v "patch.jl:1[89][0-9]\|patch.jl:19[0-9]"` prints only `test/runtests.jl:...# \`_patch_reference_length\` returned ...` (a comment).

### LEAD U18-16 [Minor, confidence high] src/elements/floor_plan.jl:94
Claim: `_floor_children` is defined and never called.
Mechanism: the walkers call `line_entries` directly (floor_plan.jl:138, 140, 173); the helper is a leftover of the draft. Dead code.
Repro: `grep -rn "_floor_children" src/ test/` prints only `src/elements/floor_plan.jl:94`.

### LEAD U18-17 [Minor, confidence high] docs/theory/aperture_and_particle_loss.md:403
Claim: The aperture note's §6 still states that "CPU and CUDA logs are byte-identical, which this codebase enforces by contract", the over-claim the `LossRecord` docstring retracted (aperture.jl:44-54, U15-13).
Mechanism: the docstring records 2 ulp differences on about 13% of samples for a stochastic line (counter-RNG normal transform) and calls byte-identity "a documentation over-claim"; the reference note was not updated with it. Out-of-region reference document; class 14.
Repro: `grep -n "byte-identical" docs/theory/aperture_and_particle_loss.md src/elements/aperture.jl` prints the note's claim at line 403 and the docstring's retraction ("this docstring used to overreach").

### LEAD U18-18 [Minor, confidence high] src/elements/beam_line.jl:77
Claim: `setproperty!` on a line placement accepts an `entries` (or `name`) override, after which the compiled placement tracks the overridden entries while `total_length`, `s_positions` and `survey` read the spec's.
Mechanism: the structural guard covers only `_ENTRY_FIELDS = (:spec, :path, :tags, :overrides)`, not the two keys `_line_has_own_state` treats as a line's structure; `compile_runtime(entry::LineEntry)` merges overrides into `ElementSpec{:line}(_merged_params(entry))` and compiles THAT, whereas `_placement_length(entry::LineEntry)` returns `total_length(getfield(entry, :spec))` and the survey walkers descend `line_entries(spec)`. Measured: with a 7 m drift as the override on a 0.4 m quadrupole line, the compiled placement reproduces the drift (x = 0.002396) and the walkers report 0.4 m. A user has to ask for it, hence Minor; the `_reject_folded_override` precedent shows the project rejects unreadable overrides at assignment.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U18/probe6.jl` prints `placement tracks the OVERRIDE: true   tracks the SPEC: false` and `total_length(outer) = 1.4  s_positions(outer) = [0.0, 0.4]`.

## Clean

Checked and found sound, with the evidence:

- Frame-map conventions against `misalignment_and_patch_maps.md` §5-§6a (read, not re-pinned
  against PTC): `_misalign_matrix` builds `R_y(theta) R_x(-phi) R_z(psi)` for `:bmad` and
  `R_z R_x R_y` for `:madx` exactly as the note states; `sref = 0` for `:madx`, `L/2` for `:bmad`;
  the `:madx` roll conjugation is `W -> R_z(-psi) W R_z(psi)`, `d -> R_z(-psi) d`
  (`_m3(_m3t(R, W), R)`, `_m3tv(R, d)`); the exit pair in `_misalign_frames` is built from the
  design exit frame (`Q_out = Q_ex' Ad`, `o_out = Q_ex' (Xd - o_ex)`), never by inverting the
  entrance pair, as §5 requires. The elementary matrices were checked by hand (`Ry`, `Rx` = `R_x(-phi)`,
  `Rz`).
- `_misalign_frames` (arc closed form) vs `_misalign_frames_from` (given frames) on arcs:
  max |difference| 1.1e-16 (h=0.3, L=1, sref=L/2), 0.0 (sref=0), 4.4e-16 (h=1e-3, L=2) -- probe3 C1.
- `_survey_frame` vs `_floor_arc_step` at h=0.3, L=1: rotation identical bitwise, origin to 1.4e-16
  (probe1b P10); the small-angle regime is LEAD U18-10.
- MAD-X angle extraction `_fp_theta`, `_fp_phi`, `_fp_psi`: derived by hand from
  `W = R_Y(theta) R_X(-phi) R_Z(psi)` -- `W13 = sin(theta) cos(phi)`, `W33 = cos(theta) cos(phi)`,
  `W23 = sin(phi)`, `W21 = cos(phi) sin(psi)`, `W22 = cos(phi) cos(psi)` -- matching
  floor_plan_survey.md §3; the row-major indices `w[3], w[9], w[6], w[4], w[5]` are the right entries.
- `_survey_walk!` conjugation of a rolled kept-whole sub-line (`W rt`, then `W rt'` on return) and
  `_girder_flat_entries!`'s per-member `Q R Q'` compose to the same `rt (R1...Rn) rt'`; `_girder_design_frames`
  boundary logic traced for a reference point on an exact member boundary (frame after the crossing),
  inside a member (partial `_floor_arc_step`), at `starget = 0`, past zero-length members and patches
  (patches never take the partial form because `Lp = 0`).
- Dual seeding at the design point for SINGLE elements: `ForwardDiff.Dual(0.0, 1.0) == 0` is `false`
  under ForwardDiff v1.4.6 (compat `"1"` in Project.toml), so the `== 0` early returns in
  `_misalignment_wrap` and `_ref_tilt_wrap` keep the wrap, and AD equals central FD for x_offset
  (6.8e-1 = k1 L), y_offset, x_pitch, tilt and ref_tilt at 0 (probe2). Envelope: under ForwardDiff
  0.10 value-only `==` semantics the same guards would have dropped the wrap and returned a zero
  derivative; the compat bound is what keeps this clean.
- `_frame_change` longitudinal update without `+ds` (path-length difference only) matches the PTC
  `TRANS`/`ROT_XZ` convention the docstring cites; the two faces are paired so the reference term
  cancels for an on-axis particle (reasoned, pinned in the suite's PTC cases, not re-run here).
- `_patch_map` z bookkeeping derived by hand: `excess = ds (q1^2+q2^2)/(q3((1+pz)+q3))` equals
  `ds((1+pz)/q3 - 1)`; `ds = s - sxy` by linearity; the exact-inverse round trip is 4.4e-18 or better
  in (x, px, y, py, pz) (probe1b P11; the z constant is LEAD U18-11). `_patch_rotation` axis mapping
  (`angle_y -> theta`, `angle_x -> -phi`, `angle_s -> psi`) and the `:madx`-order-with-negated-angles =
  transpose identity measured to 3.5e-18.
- `_s_rotate(c, s, ...)` is `R_z(-psi)` on `(x, y)` and `(px, py)`, with `-s` for the exit; `W[1], W[4]`
  of `_misalign_matrix(0, 0, psi)` are `cos psi, sin psi` as the docstring says.
- Wrapper coverage: `_requires_tracking_context` and `_inner_method` have exactly one method for
  each of MisalignedElement, RefTilted, CompositeLine and TurnModulated (probe3 C3); all four
  `AbstractTrackOp` types in `src/` with an `inner` field are covered (grep). A recording aperture is
  refused on the bare path and seen through a MisalignedElement; a kill-only aperture is not refused
  (probe3 C4), matching the bare `track!` design of the aperture note §2 (hypothesis 3).
- Loss record: `_aperture_bump!` guards unbound ids on CPU and CUDA (F15); `_aperture_record!`'s
  unguarded slot write is protected upstream by the Tasks.jl `fits` test's `size(slots, 2) == length(rep)`
  (Tasks.jl:1776, read); an unbound-id row carries `element_id = 0` and is filtered by `loss_records`,
  with the kill surfacing as `unattributed` (documented at aperture.jl:369-376). `loss_records`'
  `offset` arithmetic (`i + offset` then `i - offset`) is consistent. `_aperture_newly_lost` tests all
  six coordinates via `is_live`. The `promote_type(eltype, Float64)` slot widening (U15-11) is correct
  for the turn column; its neighbour is LEAD U18-1.
- Aperture `x_offset` and `dx` agree for a pure transverse displacement (alive/dead identical on three
  particles, probe1b P14), consistent with the aperture note §4's "deliberately not routed through the
  misalignment frames" being a statement about `dx`, not a prohibition of the generic wrap.
- Shapes: `_aperture_inside` rectangle/ellipse/rectellipse with `Inf` defaults (`u/Inf = 0`) and
  Float32 `one(u)`; the `alive`-replaces-geometry warning (U15-10) in place.
- Beam-line construction: `_append_line_child!` copies overrides and re-roots paths for dissolved
  lines and `LineEntry` children; `Base.reverse` copies every placement (U15-3 fix present);
  `_reject_line_length` on both constructors; `CompositeLine` refuses nested tuples; `fusedTrack`
  delegation for CUDA (U15-1) and per-op methods (U15-4) as documented. `reverse` stores `entries` as
  a `Tuple` while both constructors store a `Vector` (probe1b P5) -- an observation, not a lead: no
  consumer outside beam_line.jl reads `:entries` (grep), and every in-file consumer iterates.
- Selector parsing and `_path_matches` traced by hand (leading `/` anchor, `//` descendant search at
  every depth, prefix semantics, 1-based ordinals); a trailing `/` sets a descendant flag that is
  silently dropped (style only). A kept-whole sub-line's interior is opaque to `find_entries`
  (probe3 C2), which is the §10 design ("a girder is simply an element that happens to be long").
- `DEFAULT_INACTIVE_ELEMENT_PARAMS` (lesson 5): no row names a kind owned by this unit's files except
  `(:line, :L)`, whose stated role (survey metadata merged by `compile_runtime`) matches
  beam_line.jl:742-743; `:patch` and `:aperture` have no placement rows, and both wraps are measurably
  active for them (probe1b P9, P14), so the table and the code agree for this region.

## Unchecked

- CUDA: no device probe was run; whether every branch of the aperture, misalignment, ref_tilt, patch
  and composite-line paths still compiles as device IR is left to the backend-consistency contracts.
- MPI: `ctx.index_offset` and the `offset` keyword of `loss_records` were read, not exercised.
- The ulp bounds and percentages quoted in the `_cross_backend_rounding` declarations of
  misalignment.jl, ref_tilt.jl, patch.jl and aperture.jl were not re-measured.
- `write_loss_record`/`read_loss_record` were read, not executed (zero-loss and empty-names cases
  untested here).
- No PTC or MAD-X comparison was re-run; the convention pins (`quad_mis_all`, `cfbend_reftilt_mis_*`,
  `MADXSurveyConsistencyContract`) are taken from the notes and docstrings.
- The artifact-side consequence of LEAD U18-1 (whether the previous window's `/losses` rows are lost
  when the record is reallocated) is a Tasks.jl seam, not measured.
- `knob_report`'s prefix filtering beyond the suite's own test, and `_knob_value_sites!` over nested
  tuples, were read only.
- The remaining sections of `beam_line_composition.md` (§1-§7a, §8-§9) and
  `misalignment_and_patch_maps.md` (§1-§4), and `aperture_and_particle_loss.md` §1, §3, §5, were not
  read; they are background to the sections compared.
