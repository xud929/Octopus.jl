# U48: theory notes C: lattice Hamiltonian and conventions, solenoid, beam-line composition

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Every claim below is a
LEAD for the auditor, not a finding. Severity guesses: Moderate x4, Minor x10.

## Region

- `docs/theory/lattice_hamiltonian_and_conventions.md` lines 1-1141 (whole file)
- `docs/theory/solenoid.md` lines 1-830 (whole file)
- `docs/theory/beam_line_composition.md` lines 1-563 (whole file)

Total 2534 lines, all read line by line. Depth: claims against code, with sampled independent
derivations and executed measurements.

## Provenance

READ line by line (the region):
- `lattice_hamiltonian_and_conventions.md` 1-1141, `solenoid.md` 1-830, `beam_line_composition.md` 1-563.

READ line by line (references the notes make claims about):
- `src/elements/lattice_magnets.jl` 1-1000 (helpers, `_lattice_drift`, `_lattice_bend`,
  `_lattice_kick`, `_curved_potential_coeffs`, `_curved_kick`, every fringe map, `_rot_xz`, `_wedge`,
  `_face`, `_wedge_quad`, `LatticeMagnet`, `_entrance`/`_exit`, `_body_step`, `track_particle`,
  `_cross_backend_rounding`); 1077-1079 and 1134-1138 (`wedge_coeff`, `curved_order` metadata).
- `src/elements/solenoid.jl` 1-608 (whole file).
- `src/elements/beam_line.jl` 1-840 (whole file except `knob_report` 838-930, skimmed for walker shape only).
- `src/tasks/Tasks.jl` 236-262, 400-480, 700-900, 1629-1631, 1660-1668, 1975-2000, 2020-2070.
- `src/elements/floor_plan.jl` 50-100, 115-160, 160-215.
- `src/knowledge/Knowledge.jl` 140-205.
- `test/runtests.jl` 9975-10140 (bend small-b0 pin; "Cancellation-free longitudinal updates" testset),
  10195-10235 (`_wedge` pin), and the check lines of the solenoid testsets 26984-27260 (grep).
- PTC source `/cfs/ad/dxu/Library/AcceleratorCodes/madx-5.03.06/libs/ptc/src/Sh_def_kind.f90`
  lines 120-128 (`wedge_coeff` declaration), 3771-3872 (`FRINGE_dipoleR`), 4000-4047
  (`FRINGE2QUADR`), 4800-4850 (`KICK_SOLR`), 11286-11307 (`MAD8_WEDGE` term); the bmad-ecosystem
  copy `forest/code/Sh_def_kind.f90` line 145 and 16269-16333 (`n_wedge`).
- `validation/generate_ptc_reference.jl` flag lines (grep), `validation/reference/ptc_madx_5.03.06.tsv`
  case names, `docs/todo.md` and `docs/history/todo_ledger_archive.md` rows the notes point at,
  `docs/README.md` index entries for the three notes.

EXECUTED (scripts and logs under `result/comprehensive_audit_2026_10_18/probes/U48/`):
- `ulp_probe.jl` -> `ulp_probe.log`: Float64 vs BigFloat(256-bit) for the four kernels on a uniform
  +-1e-3 sweep (my own distribution; its `max(|z|,|E|)` scale collapses on zero crossings, so the
  bend numbers there are superseded by the next probe), plus `_lattice_bend(b0) - _lattice_drift`
  at b0 = 1e-4, 1e-8, 1e-12, 1e-15: 3.150e-4, 3.151e-8, 3.150e-12, 3.00e-15 (linear, no floor).
- `pin_seed_probe.jl` -> `pin_seed_probe.log`: the suite's "Cancellation-free longitudinal updates"
  sweep (its exact distribution) re-run under 11 seeds; all z pins hold (curved drift <= 6.0 of pins
  4/16, bend <= 23.3/19.6/144.4/18.0/8.0/702.7 of pins 64/32/256/64/32/4096, solenoid <= 0.7 of 2,
  curved solenoid <= 3.2 of 8); the solenoid TRANSVERSE pin 64 is exceeded (215.3). The note's
  after-numbers reproduce at seed 2026: bend 15.6, solenoid 0.5, curved solenoid 2.1, weak bend 52.6,
  curved drift 4.7 (at h = 0.35, L = 0.5; the h = 1e-3 case gives 0.5). L = 0 solenoid bitwise
  identity: 4416/10000 particles at |u| ~ 1e-3, 9646/10000 at |px|,|py| ~ 0.1.
- `symp_api_probe.jl` -> `symp_api_probe.log`: |J'SJ - S| by BigFloat central differences (step 1e-40)
  for every face map, both solenoid maps, the drift, the three bend branches and both kicks (table in
  Clean); `find_entries(line, QuadrupoleSpec)` = `Int64[]`; raw `qf.params[:kn] = ...` leaves
  `_SPEC_EPOCH` at 0 while `qf.kn = ...` bumps it; `line * line` MethodError, `vcat` -> Vector of lines;
  `compile_runtime` of an own-state line holding a `ScheduledObserver` -> MethodError.
- `override_hook_probe.jl` -> `override_hook_probe.log`: `ref_tilt` override on a kept-whole line
  placement: tracking A == B (max diff 0.0), A vs unrolled C 8.95e-5; `survey` and
  `_girder_design_frames` A == C (override ignored), A != B.
- `hook_site_probe.jl`, `entry_point_probe.jl` -> logs: the hook MethodError's Octopus frames
  (`compile_runtime @ beam_line.jl:191 <- compile_runtime @ beam_line.jl:739 <- _runtime_or_existing @
  Tasks.jl:1629 <- _append_runtime_line! @ Tasks.jl:2064`); `TrackingTask(cell)` (bare) dissolves
  to 3 entries and runs, `TrackingTask((cell,))`, `((cell, drift))`, `([cell])` keep the line whole
  (1-2 entries) and throw; per-seed solenoid transverse ulps (seed 3: 110.0, seed 6: 215.3).
- `cuda_probe.jl` -> `cuda_probe.log` (CUDA functional = true): CPU vs CUDA, 400 particles, 3 turns,
  with the suite's own helpers: sbend h=b0=0.3 L=2 z 2.0 ulps, sbend h=0.3 b0=0.1 L=2 (direct-E
  regime) z 5.0, sbend h=0.3 b0=1e-4 L=0.5 z 34.0, curved drift h=0.3 L=2 z 18.0; declared bound 64,
  no violations. Over-momentum particle (px = 2) through a drift: CPU `DomainError`, CUDA
  `KernelException` wrapping a `DomainError` thrown in the kernel.
- `floor_smallh_probe.jl` -> `floor_smallh_probe.log`: `_floor_arc_step` lateral coordinate vs
  BigFloat at L = 1: abs error 1.4e-16 m (h = 0.3), 7.8e-15 (1e-3), 4.4e-11 (1e-6), 5.0e-9 (1e-8,
  returns exactly 0), 5.0e-10 (1e-9, returns 0); `-_curv_vers(h, 1.0)` exact at every h.

## Leads

### LEAD U48-1 [Moderate, confidence high] src/elements/floor_plan.jl:137
Claim: A `ref_tilt` override written on the placement of a kept-whole sub-line is honoured by tracking but ignored by `survey` and by the girder design frames, so the floor plan and the tracked map disagree on the sub-line's roll.
Mechanism: `_survey_walk!` (floor_plan.jl:126-137) and `_girder_flat_entries!` (floor_plan.jl:169-171) take `spec = getfield(entry, :spec)` and read `getparam(spec, :ref_tilt, 0.0)` from the raw line spec, whereas `compile_runtime(entry::LineEntry)` (beam_line.jl:188-193) merges the placement's overrides first and `_ref_tilt_wrap` reads the merged value. Every other walker in Tasks.jl goes through `_effective_spec(entry)`, and `_floor_step` itself reads element parameters through `getparam(entry, ...)`; only the two line-spec reads bypass the merge. The design note's rule "placement wins" (beam_line_composition.md section 7b) therefore holds for tracking and not for geometry, which is the two-walker class (brief class 3). Cross-file seam between beam_line.jl and floor_plan.jl; reported and stopped here.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U48/override_hook_probe.jl` prints `tracking: override(A) vs spec(B) max diff = 0.0`, `survey: A == C (override ignored by survey) = true; A == B = false`, `girder design frames: A == C (override ignored) = true` (A: `outer[1].ref_tilt = 0.4` on a placement of `BeamLine("IN", SBendSpec(L=1.0, angle=0.3); x_offset=1e-4)`; B: the same `ref_tilt` on the sub-line spec; C: no roll). Exit frame A = C = (-0.2966, 0, 1.4627) against B = (-0.2732, -0.1155, 1.4627).

### LEAD U48-2 [Moderate, confidence high] src/tasks/Tasks.jl:861
Claim: An in-line hook placed inside a `BeamLine` makes `execute!` throw `MethodError: no method matching compile_runtime(::ScheduledObserver...)` unless the line is the task's bare `elements` argument, although the `BeamLine` docstring (beam_line.jl:217) lists in-line hooks among the allowed children and the design note (section 7, line 269; section 10, line 517) says the tracking plan accepts them and that the task dissolves every structural line.
Mechanism: `_element_tuple(line::ElementSpec{:line})` (Tasks.jl:859) dissolves a structural line only when the line IS the argument; `_element_tuple(elements::Tuple) = elements` (Tasks.jl:861) and the `AbstractVector` method pass a line inside a container through whole. The whole line then reaches `_append_runtime_line!(out, element)` (Tasks.jl:2064) -> `_runtime_or_existing(::AbstractElementSpec)` (1629) -> `compile_runtime(::ElementSpec{:line})` (beam_line.jl:739), which compiles every entry with `compile_runtime(entry)` (beam_line.jl:191); a `ScheduledObserver` has no `compile_runtime` method. The hook-aware path (`_append_runtime_line!(out, entry::LineEntry)`, Tasks.jl:2048-2055) is reached only for dissolved entries. The error is loud but names neither the rule nor the remedy, and fires at `execute!`, after `TrackingTask` accepted the line. Note the section 10 rule ("no in-line hooks inside a composite assembly") was written for own-state lines; here it bites structural ones too.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U48/entry_point_probe.jl` prints `bare line TrackingTask(cell) ... 3 entries; execute! returned normally` and `tuple TrackingTask((cell,)) ... 1 entries; execute! threw MethodError` (likewise for `(cell, drift)` and `[cell]`), with `cell = BeamLine("CELL", QuadrupoleSpec(L=0.4, k1=1.7), ScheduledObserver(BPMObserver("b")), DriftSpec(L=1.0))`; `hook_site_probe.log` holds the frames.

### LEAD U48-3 [Moderate, confidence high] src/elements/beam_line.jl:616
Claim: `find_entries(line, QuadrupoleSpec)` -- the element-class selection the design note gives as an example (beam_line_composition.md:279, "the physicist's `find(line, QuadrupoleSpec)`") and the `find_entries` docstring describes as "a `Type` matched against the spec" -- returns an empty vector silently, because no spec is a subtype of the friendly-constructor type.
Mechanism: `_entry_matches(e::LineEntry, s::Type) = getfield(e, :spec) isa s`; `QuadrupoleSpec` is an abstract `UnionAll` used as the registry's constructor key, and `ElementSpec{:quadrupole} <: QuadrupoleSpec` is `false`, so the natural class name a user reaches for matches nothing and the empty result is indistinguishable from "no such magnet" (brief class 6). `ElementSpec{:quadrupole}` and `sel"ARC//quadrupole"` do work. A `Type` that no `ElementSpec` can satisfy could be refused with the two working spellings instead of returning `Int[]`.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; qf = QuadrupoleSpec(L=0.4, k1=1.7); d = DriftSpec(L=1.0); line = BeamLine("ARC", qf, d, qf, d); println(find_entries(line, QuadrupoleSpec), " ", find_entries(line, ElementSpec{:quadrupole}), " ", ElementSpec{:quadrupole} <: QuadrupoleSpec)'` prints `Int64[] [1, 3] false`.

### LEAD U48-4 [Moderate, confidence high] docs/theory/beam_line_composition.md:422
Claim: The design note's matching recipe -- "`qf.params[:k1] = ...` bumps `_SPEC_EPOCH`, and every task holding that line recompiles at the next `execute!`" (line 422; also the table at 399 and decision 3 at 479, "every mutation bumps `_SPEC_EPOCH`") -- is wrong on both counts, and following it leaves an already-built task tracking the stale compile while the written key is never read.
Mechanism: `Base.getproperty(spec, :params)` returns the raw `Dict` (Knowledge.jl:151-152) and a `Dict` write bumps nothing; the epoch is bumped only by `setproperty!` (Knowledge.jl:184), `set_param!` (:200) and `LineEntry` overrides (beam_line.jl:82). Knowledge.jl's own `set_param!` docstring and the `setproperty!` error text say exactly this ("the raw spec.params[...] = ... form skips the recompile epoch", 2026-08-05 audit U13-2). Separately, `k1` is folded into `kn` at construction, so `params[:k1]` is stored and never read; the property path refuses it (`_reject_folded_override`) but the raw path does not. The note recommends the one mutation path that bypasses both guards (brief classes 7 and 14).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; qf = QuadrupoleSpec(L=0.4, k1=1.7); e0 = Octopus._SPEC_EPOCH[]; qf.params[:kn] = (0.0, 1.9); println(Octopus._SPEC_EPOCH[] == e0); qf.kn = (0.0, 2.1); println(Octopus._SPEC_EPOCH[] == e0)'` prints `true` then `false`.

### LEAD U48-5 [Minor, confidence high] docs/theory/lattice_hamiltonian_and_conventions.md:881
Claim: The SAD cubic term the note tells the reader to "copy verbatim" is misstated: both lines lack one factor of 1/(1+delta) relative to PTC, while the code matches PTC.
Mechanism: PTC (`FRINGE_dipoleR`, Sh_def_kind.f90:3794-3796, 3816, 3863-3864) sets `fsad = 1/(72 FINT HGAP)`, `c3 = b^2 fsad / rel_p` with `rel_p = 1 + x(5)` under TIME=FALSE, then `x(4) -= 4 c3 x(3)^3` and `x(6) += c3 x(3)^4 / rel_p^2 * time_fac`, i.e. dp_y = -b^2 y^3 / (18 FG (1+delta)) and dz_PTC = +b^2 y^4 / (72 FG (1+delta)^2). `_fringe_dipole_exact` (lattice_magnets.jl, `c3 = b*b/(72*fg)/p; py -= 4*c3*y^3; z -= c3*y^4/p`) reproduces both, with the z sign flipped for the z = s - l orientation. The note writes dp_y = -h^2 y^3/(18 FG) (no 1/(1+delta)) and dz = +h^2 y^4/(72 FG) (1+delta)/(1+delta)^2 = 1/(1+delta) (one power short). The PTC benchmark cannot see the difference (the term is ~5e-14 at the reference amplitudes, its delta-dependence ~5e-17 against a 4.8e-13 agreement), so only the source decides; documentation defect (brief class 14), the note also writes `h` where it means the dipole strength `b`.
Repro: `sed -n '3794,3796p;3816p;3863,3864p' /cfs/ad/dxu/Library/AcceleratorCodes/madx-5.03.06/libs/ptc/src/Sh_def_kind.f90` and `grep -n 'c3 = b \* b\|4 \* c3\|c3 \* y^4' src/elements/lattice_magnets.jl`, against lines 881-882 of the note.

### LEAD U48-6 [Minor, confidence high] docs/theory/lattice_hamiltonian_and_conventions.md:1005
Claim: Section 6.4 writes the soft-edge quadrupole fringe as f_1 = -sigma F|F| b/(24 p_z), f_2 = G b/p_z with the symbol p_z that section 6.3.1 (line 832) defined as the kinetic root sqrt((1+delta)^2 - p_x^2 - p_y^2); PTC's and the code's divisor is 1+delta, so a port made from the note would be a different map.
Mechanism: `FRINGE2QUADR` (Sh_def_kind.f90:4017-4021) sets `PZ = 1 + X(5)` under TIME=FALSE (and `PZ = sqrt(1 + 2X(5)/beta0 + X(5)^2)`, again 1+delta, under TIME=TRUE), and `_soft_quad_fringe` uses `p = 1 + pz`. One symbol, two meanings in adjacent subsections (brief class 9 inside one document); the difference is O(p_x^2) in f_1 and f_2.
Repro: `sed -n '4017,4021p;4034,4035p' /cfs/ad/dxu/Library/AcceleratorCodes/madx-5.03.06/libs/ptc/src/Sh_def_kind.f90` shows `PZ=1.0_dp+X(5)` feeding `f1` and `f2`; compare the note's lines 832 and 1005-1006.

### LEAD U48-7 [Minor, confidence high] docs/theory/lattice_hamiltonian_and_conventions.md:641
Claim: "One more flag to pin: `n_wedge`" names a PTC switch that does not exist in the MAD-X 5.03.06 PTC the committed reference was generated with, and in the PTC version that has it the default is 5 (integrated wedge), not 0 (closed form) -- neither fact is in the note.
Mechanism: `grep -rli 'wyosh\|n_wedge' /cfs/ad/dxu/Library/AcceleratorCodes/madx-5.03.06/` finds nothing, so `generate_ptc_reference.jl` can neither set nor need it; the bmad-ecosystem copy (`forest/code/Sh_def_kind.f90:145`) declares `integer :: n_wedge = 5` and switches on `if(n_wedge==0)` at 16269, with `at = a/iabs(n_wedge)` at 16333. A reference regenerated with a newer MAD-X would integrate the wedge in 5 steps by default and the `sbend_edge`/`cfbend_edge`/`rbend*` cases would no longer agree with `_wedge`'s closed form at 5e-13. Pinning guidance without the default and the version boundary is the hand-copied-knowledge shape (brief classes 2 and 14).
Repro: `grep -n 'n_wedge' /cfs/ad/dxu/Library/AcceleratorCodes/bmad-ecosystem/forest/code/Sh_def_kind.f90 | head -3` prints `145:  integer :: n_wedge = 5`; the same grep over `madx-5.03.06/` prints nothing.

### LEAD U48-8 [Minor, confidence high] test/runtests.jl:10105
Claim: The solenoid's transverse pin in "Cancellation-free longitudinal updates" (`transverse_ulps <= 64`) holds for the suite's seed and fails for other seeds of the suite's own particle distribution (110 and 215 ulps), because its scale `max(|out|, |in|)` of one coordinate omits the kinetic momentum magnitude the computation actually rounds at.
Mechanism: the solenoid rotates (P_x, P_y) = (p_x + k y, p_y - k x), so the rounding of the output p_x is ~eps(|P|) with |P| ~ 2e-3, while the pin divides by eps(max(|p_x out|, |p_x in|)); a particle with |p_x| ~ 2e-5 and |P| ~ 2.2e-3 (seed 6) reads 215 ulps of a correct result (brief class 8: a measured pin stated outside the regime it was measured in -- one seed). The z pins and every other kernel's transverse pin hold across all 11 seeds, so this is the one fragile row.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U48/entry_point_probe.jl` (second half) prints per seed: 2026: 15.4, 3: 110.0 (`<-- exceeds the pin`), 6: 215.3 (`<-- exceeds the pin`), the rest <= 60.2; the sweep generator is copied from the testset verbatim with only the `Xoshiro` seed changed.

### LEAD U48-9 [Minor, confidence high] test/runtests.jl:27001
Claim: The bitwise pin `collect(sol(1.7, 0.0)(u0...)) == collect(u0)` ("L = 0 is the identity", solenoid note section 9.1) rests on the rounding of one particle: the identity is exact in algebra and 1-2 ulp in floating point, and holds bitwise for 44% of random particles at the suite's amplitudes.
Mechanism: at L = 0 the exit edge computes `(px + k*y) - k*y`, which equals `px` bitwise only when the intermediate sum did not round; with px ~ k y ~ 1e-3 it rounds roughly half the time (brief classes 8 and 13: a pin on rounding, never fed the defect it guards). `_cross_backend_rounding(::Solenoid)` separately notes the device fuses `px + k y`, so the bitwise form is also backend-specific.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U48/pin_seed_probe.jl` (tail) prints `L = 0 solenoid bitwise identity on 4416 of 10000 random particles (|u| ~ 1e-3)` and `9646 of 10000 ... (|px|,|py| ~ 0.1)`.

### LEAD U48-10 [Minor, confidence high] docs/theory/solenoid.md:696
Claim: "Contract now 55 cases (the count is the committed PTC reference table's ...)" -- the committed table holds 61 cases.
Mechanism: the count is hand-copied from the table and has drifted twice (the note records 41 -> 55; the ref_tilt and misalignment cases since added make it 61); exactly the drift the sentence itself warns about (brief classes 2 and 14). The five solenoid cases (pos, neg, strong, k1_n8, k1_n32; 25 rows) the note describes are present.
Repro: `grep -v '^#' validation/reference/ptc_madx_5.03.06.tsv | tail -n +2 | cut -f1 | sort -u | wc -l` prints 61.

### LEAD U48-11 [Minor, confidence med] src/elements/floor_plan.jl:85
Claim: The floor plan's arc step is the one remaining `1/h` form not routed through the smooth helpers -- `rho = 1.0 / h; d0 = (rho * (cos(alpha) - 1.0), 0.0, rho * sin(alpha))` -- so the lateral floor coordinate of a weakly curved element loses digits exactly as section 5.2 of the conventions note forbids, while `_misalign_frames` (misalignment.jl:128) computes the same displacement with `_curv_vers`/`_curv_sin`.
Mechanism: `cos(alpha) - 1` rounds at eps/2 absolute and is multiplied by rho = 1/h, so the error is ~eps/(2h) metres regardless of how small the true value L^2 h/2 is (out of hypothesis 2's "every element with an h small limit" only in that this is the survey of such elements, not their map; two forms of one geometry is also brief class 3). Measured at L = 1 m: 7.8e-15 m at h = 1e-3, 4.4e-11 m at h = 1e-6 (four digits of a 0.5 micrometre quantity), and exactly 0 against -5e-9 m at h = 1e-8. The girder design frames (`_girder_design_frames`) feed these steps into `_misalignment_wrap`, so a misaligned assembly containing a very weak design bend inherits the error. Practical impact is small at realistic curvatures; the fix is the two helpers already used next door.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U48/floor_smallh_probe.jl` prints `h = 1.0e-8 floor x = 0.0 exact = -5.0e-9 abs err = 5.0e-9 m (misalignment.jl form -_curv_vers = -5.0e-9)`.

### LEAD U48-12 [Minor, confidence med] docs/theory/solenoid.md:334
Claim: Section 8's "misalignment should compose without special handling. This should be *verified* rather than assumed, because a rotation about s commutes with a solenoid while a pitch does not" was never verified: no test, validation script or PTC reference case misaligns a solenoid, and no ledger row carries the item.
Mechanism: `grep -n -i 'solenoid' test/runtests.jl | grep -i 'pitch\|misalign\|x_offset\|tilt'` is empty and the five `solenoid_*` reference cases carry no `ealign`; the only coverage is the parameter-effectiveness sweep over `_PLACEMENT_PARAMS`, which checks that `x_pitch` moves the map, not that the composed map is right (brief class 13: an announced check never run). The misalignment wrap is element-agnostic and PTC-pinned on quadrupoles, sextupoles and bends, which bounds the risk; the note's own stated concern (a pitch does not commute) is what a `solenoid_mis_dtheta` reference case would settle.
Repro: `cut -f1 validation/reference/ptc_madx_5.03.06.tsv | grep -i sol | sort -u` prints the five unmisaligned cases; the grep above prints nothing.

### LEAD U48-13 [Minor, confidence med] docs/theory/beam_line_composition.md:167
Claim: Several statements in the three notes describe behaviour or numbers the tree does not have: the section 4 table (line 167) and line 176 say concatenation is `vcat`/`*` and operators "must be closed over the type", but `line * line` is a `MethodError` and `vcat(line, line)` returns a `Vector{ElementSpec{:line}}`; section 7 (line 276) promises "`s` computed and cached" while decision 3 (line 479) and `s_positions` compute on demand; the conventions note's section 6.3 heading (line 803) says "six components" over seven numbered items; its section 5.2 (line 480) attributes the after-fix 4.7 ulp to the curved drift "(h = 1e-3, L = 0.5)" by "respectively", whereas that case measures 0.5 and 4.7 belongs to h = 0.35.
Mechanism: design-note proposals left standing as descriptions after implementation diverged (brief class 14). Style-level; bundled so the auditor can accept or drop them together.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U48/symp_api_probe.jl` prints `vcat(line, line) -> Vector{ElementSpec{:line}} length 2` and `line * line -> MethodError`; `pin_seed_probe.log` first four rows give the drift numbers per case.

### LEAD U48-14 [Minor, confidence low] docs/theory/lattice_hamiltonian_and_conventions.md:1107
Claim: Open items stated in the notes have no row in `docs/todo.md`: section 8's `VA`/`VS` moment-extraction utility and the measured default for the curved-multipole truncation order (the latter sits as item 8 of a closed record in `docs/history/todo_ledger_archive.md:2503`, still worded as open), and the solenoid note's section 9.1 (line 389-396) decision about `sqrt` guards versus crash-on-over-momentum across `src/elements/`.
Mechanism: `grep -n -i 'truncation\|curved_order\|over-momentum\|DomainError\|sqrt guard\|VA.*VS\|measurement recipe' docs/todo.md` returns nothing; AGENTS.md names `docs/todo.md` as the ledger of open work, so items living only in a theory note's "Open items" section are invisible to "choose the next task". Low confidence that the owner wants these as rows rather than as recorded non-work; the bookkeeping gap is the lead.
Repro: the grep above (empty) against `sed -n '1107,1125p' docs/theory/lattice_hamiltonian_and_conventions.md` and `sed -n '389,396p' docs/theory/solenoid.md`.

## Clean

Hypothesis 1 -- the notes as claims about the code; the 2026-10-17 longitudinal-half paragraph and the solenoid implementation note against the kernels:
- `_lattice_bend` (lattice_magnets.jl 271-368) implements the paragraph term for term: `kappa = h - b0`, `pxd = kappa*C1`, `pxn = pxd + dp` with `dp` from `ps0 - 1 = (pz(2+pz) - (px^2+py^2))/(1+ps0)` (derived by hand, holds); `E = -(kappa S1 + asin_excess(pxd))/b0 - dphi/b0 + pz Delta` with `dphi` the argument of (psn + i pxn)(psd - i pxd)(ps0 - i px) (expanded by hand: real part `Pr ps0 + Pi px`, imaginary `Pi ps0 - Pr px`, as coded); `Pi` built from `dp` through `psd - psn = (py^2 - pz(2+pz) + dp(pxn+pxd))/(psd+psn)` (verified algebraically); the `|b0| > |h|/2` switch to the direct form as the note states; the `x'` bracket `C1 (R - s/(1+c))` expanded via `pxr(1+c) - s psr = px(1+c) + ps0 s` and `ps0 - psn = (pxn-px)(pxn+px)/(ps0+psn)` (both verified). The curved drift's `E` identity, the solenoid's `z - L (Px^2+Py^2)/(ps((1+pz)+ps))` and the curved solenoid's `z'` all match the note's formulas; the `b0 == 0` fast path remains in `_body_step` as described; the `|hL| >= pi/2` fallback exists as described.
- Measured (pin_seed_probe.log): the note's after-fix numbers reproduce at the suite's seed (bend 15.6, solenoid 0.5, curved solenoid 2.1, weak bend 52.6) and every z pin holds under 11 seeds; `_lattice_bend` approaches `_lattice_drift` linearly in b0 with no floor (3.15e-4 b0 down to 3.0e-15 at b0 = 1e-15, ulp_probe.log). The suite's "Cancellation-free longitudinal updates" testset IS the committed BigFloat harness behind the paragraph (test/runtests.jl:10036-10135, fixed seed, pins as a table).
- Symplecticity under the standard S (S56 = +1), BigFloat Jacobians (symp_api_probe.log): `_rot_xz` 5e-39, `_wedge` 3e-30 / 5e-39, `_face` 8e-41, `_fringe_dipole_exact` 2e-40 / 1e-40 (with and without FINT HGAP), `_multipole_fringe` 9e-41 (entrance) / 1e-40 (exit), `_soft_quad_fringe` 2e-40, `_wedge_quad` 8e-41, `_solenoid_map` 2e-40, `_lattice_drift` curved 2e-31, `_lattice_bend` 5e-40 / 3e-37 (direct-E regime) / 6e-38 (h = 0) / 7e-38 (|hL| > pi/2), `_lattice_kick` 6e-41 / 4e-39 (curved pure normal dipole), `_curved_kick` (M = 8) 4e-39; `_solenoid_curved_map` 1.1e-17, the documented q^16 class. The sign flips of every longitudinal update relative to PTC (sections 2.1, 5.3, 6.4) are therefore the right ones.
- Solenoid implementation note: `_solenoid_edge(k, x, y, px, py) = (px + k y, py - k x)` with `k = ks/2`, exit at the new `x, y` with `-k`, `kappa = ks/ps` from the kinetic momenta, `C1 = _curv_sin(kappa/2, L)`, rotation by `-kappa L` with displacement along the half angle, the curved RHS of section 15.2 (`px' = h ps + (1+hx) k g' Py/ps`, `py' = -(1+hx) k Px/ps`, derived from H = delta - (1+hx) ps by hand), `_SOL_MIDPOINT_ITERS = 16`, `Solenoid{M,T,N,CURVED,MC,NC}` decided in the constructor from `!iszero(h)` with the `curved` override, `_SOL_CURVED_ORDER = 8`, `kskew` naming, `N = 0` runtime for an all-zero multipole set -- all as the note says.
- PTC source cross-checks (madx-5.03.06): `wedge_coeff(2)` declared without initializer at Sh_def_kind.f90:124 between initialised `phase0` and `MAD8_WEDGE`; the `MAD8_WEDGE`/`wedge_coeff` kick at 11286-11307 matches `_wedge_quad` and the note's item 6; `KICK_SOLR` 4811-4813 (`xp = x(2) + bsol x(3)/2`, `yp = x(4) - bsol x(1)/2`), 4821 (exact `h`), 4846 (half angle) match the solenoid note's section 12 quotation. Forest-Ruth coefficients `_FR_D1 = 0.5/(1+a)`, `_FR_D2 = a D1`, `_FR_K1 = 1/(1+a)`, `_FR_K2 = (a-1) K1` with `a = 1 - cbrt 2`, four drifts / three kicks, as section 7 states. `generate_ptc_reference.jl` pins `model=1, exact=true, time=false` and per-element `permfringe` as section 7 requires. Fringe order at entrance (ROT_XZ, FACE, FRINGE_dipole, MULTIPOLE_FRINGE, FRINGE2QUAD, wedge_quad, WEDGE(-e)) and its reversal with sigma = -1 at exit, the `drop1` of the normal dipole when the bend fringe runs, the `hf` cap, and the dipole fringe running regardless of the pole-face angle all match sections 6.1-6.3.
- CUDA (cuda_probe.log): the direct-form bend regime the paragraph keeps (|b0| <= |h|/2) stays inside the 64-ulp class `_cross_backend_rounding` declares for curved magnets (z 5.0 at h=0.3 b0=0.1 L=2; 34.0 at h=0.3 b0=1e-4 L=0.5); the solenoid note's "over-momentum particles throw, matching the drift" holds on both backends (CPU `DomainError`; the device kernel traps the same `DomainError`, surfacing as `KernelException`), so the suspected CPU/CUDA divergence is not there.

Hypothesis 2 -- removable singularities honoured: `_curv_sin` (series below 1e-4 to u^4, truncation u^6/5040 ~ 2e-28), `_curv_vers` (series below 0.125 through u^8, next term u^10/239500800 ~ 4e-18; closed branch `2 sin^2(u/2)/h`), `_atan_over` (series below 1e-4, 1 - u^2/3 + u^4/5), `_sol_log_over_h` (series below 1e-2 through u^7, truncation u^8/9 ~ 1e-17), `_curv_sin_excess` (series below |u| = 1 to u^20/21!, nested divisors 20, 42, 72, 110, 156, 210, 272, 342, 420 checked against consecutive factorial ratios), `_asin_excess` (26-term series below 0.4, recurrence (2k-1)^2/(2k(2k+1)) checked), `_wedge`'s `b1 == 0` short-circuit and rationalised `atan(b1 G)/b1`, `_lattice_bend`'s `atan(b0 G)/(b0 G)`, `_fringe_dipole_exact`'s `2y/(1+sqrt(1-2By))`, and `_misalign_frames` on `_curv_vers`/`_curv_sin` (misalignment.jl:128). The one exception found is the floor plan (U48-11). The curved solenoid's `g(x)` goes through `_sol_log_over_h`.

Hypothesis 3 -- composition rules vs the walkers: dissolution of structural sub-lines at construction with provenance rewritten (`_append_line_child!`, ordinals per label, tags unioned, overrides copied); own-state kept whole by `_line_has_own_state` (any key but `name`/`entries`); `reverse` order-only, copying placements, docstring states it in one sentence (beam_line.jl:19-22, 219-220, 300-305); `repeat`; `compile_runtime(entry)` merges before `compile_runtime(spec)` whose `resolve_knobs` runs inside (beam_line.jl:188-193, 735); `_reject_line_length` and the placement-level `L` refusal; `CompositeLine` flat-tuple invariant; `_element_tuple` for the bare line. The spec-side walkers that know lines and placements -- `_collect_radiation_ids!`, `_collect_aperture_specs!`, `_collect_spec_s!`, `_collect_declared!`, `_each_turn_rule_spec`, `_survey_walk!`, `_girder_flat_entries!`, `_knob_binding_sites!`, `_has_knob_parameters` -- all descend `ElementSpec{:line}` and `LineEntry`; all but the two floor-plan line-spec reads (U48-1) see placements through `_effective_spec`/`getparam(entry)`. `_validate_reference_chain` (Tasks.jl:1987) reads kind from the raw spec and parameters from the entry, which is the right split. `docs/README.md` indexes all three notes (lines 226, 242, 319).

## Unchecked

- The notes' "before" measurements (2835, 5190, 4855, 768 ulp; 5863/1225; the 1.5e-4 field-truncation symplecticity; the polygon benchmark; the 2026-08-02 b0 floor; the misaligned-girder 1.0e-6..4.05e-4 series) describe code that no longer exists in this tree and cannot be reproduced from it.
- Section 4.4's closed forms for Psi_4, Psi_6, Psi_8 and the PDE residual scaling were not re-derived; `_curved_potential_coeffs` was read but only its kick's symplecticity was measured, not its accuracy against the PDE.
- The boxed closed form for the integrated multipole-fringe potential (section 6.2) was not numerically compared with the per-order loop; the loop was checked against the per-order formulas by reading only. The B, B1, B3 contractions of the dipole fringe were not re-derived; symplecticity was measured instead.
- Claims about Bmad, Elegant and Xsuite source (solenoid note section 12; conventions note section 2.1 table) were not re-read; only the PTC quotations were checked against the shipped source.
- Whether a `ScheduledObserver` inside a bare, dissolved `BeamLine` actually records at its placement (execute! returned normally) was not checked.
- `knob_report` and `_knob_binding_sites!` (beam_line.jl 838-930) were skimmed for walker shape only, not read line by line.
- The two-walker check for `ref_tilt` (U48-1) was run for a sub-line placement only; element placements read through the entry and were not probed further.
