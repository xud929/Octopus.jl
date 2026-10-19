# U32: test/runtests.jl lines 12911-16037 (precision rule, cross-backend classes, element/solver effectiveness, cavities, conversions, ForwardDiff)

## Region

`/cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` lines 12911-16037, 3127 lines, at commit 24e8683
(read-only tree). Twenty-six top-level `@testset`s, four of them behind `_lane_gate`
(13948-14136 "Element parameter effectiveness", 14502-14554 "Solver option effectiveness",
15662-15714 "script mode picks up the ForwardDiff rules", 15932-16036 "ForwardDiff differentiates
the lattice"). The region ends exactly before `@testset "BeamLine composes, addresses and tracks"`
(16038).

Testsets in order: Precision policy of the modulated cavities (12911); One precision rule (13178);
Cross-backend rounding classes (13520); Thin elements, markers and RBEND (13833); Element parameter
effectiveness (13949); Lattice-magnet body schemas U9-2 (14138); Curved magnets against straight
(14178); PTC coverage (14259); MAD-X survey consistency (14289); Integrated Green kernel on the axes
(14385); luminosity tree power-of-two guard (14402); launch config a bare collide! cannot apply
(14458); Solver option effectiveness (14503); Element parameters carry their own number type (14556);
RF cavity closes the longitudinal plane (14704); RF velocity slip F16 (14811); Accelerating cavity
Scope B (15007); Cavity chain / single-pass / harmon (15077); knob_report over a container (15154);
CUDA surveyed cavity (15198); CUDA wrapped strong beam (15266); Longitudinal conventions (15478);
script mode ForwardDiff (15663); torn coordinate record (15716); Example core object (15749); public
configuration schema exported (15779); PIC cache keys (15810); linear-map constructors promote
(15838); random Beam refuses non-AbstractFloat (15908); ForwardDiff differentiates the lattice (15933).

## Provenance

READ line by line: 12911-13177, 13178-13519, 13520-13832, 13833-14177, 14178-14502, 14503-14810,
14811-15153, 15154-15477, 15478-15750, 15751-16037 (the whole region, in ten contiguous reads).
Also read, to settle mechanisms the region depends on (outside the region, not audited):
`src/track/Track.jl` 160-460 (`CrossBackendRounding`, `_rounding_class`, `_cross_backend_agreement`,
`_cross_backend_violations`, `_cross_backend_summary`); `src/track/longitudinal.jl` 100-320
(`reference_beta`, `reference_pair_residual`, `_check_reference_pair`, `_delta_from_pt`,
`_pt_from_delta`, `_beta_of`, `particle_beta`); `src/elements/rf_cavity.jl` 800-842 and 861-871
(`_accelerating_exit_pair`, `rho`); `src/contracts/Contracts.jl` 3900-3950 (the solver-option
contract's `:failed`-before-`:skipped` order); `src/tasks/strongstrong/interface.jl` 1855-1871
(`_concrete_octopus_subtypes`) and 2050-2095 (the TrackingTask schema checks of
`validate_configuration_metadata`); `src/tasks/strongstrong/pic_cuda.jl` 746-790 and `pic_cpu.jl`
(the two cache keys); `src/elements/lattice_magnets.jl` 1080-1100 and 1405-1414 (`LatticeMagnet(spec)`,
`RBendSpec` folding to `SBendSpec`); the suite preamble 1-132 (`_TEST_LANE`, `_lane_gate`,
`CUDA_TESTS_ACTIVE`); `docs/design/testing_lanes.md` sections 1-4; `docs/comprehensive_audit.md`
Phase 9 (489-515); `docs/history/crab_cavity_noise_audit_fixes_batch3_2026_10_17.md` 170-200;
keyword greps of the previous audit's U17-U20 reports (only U20's three `@test true` -> `@test_skip`
conversions and U17's row 30 touch this region's subjects).

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U32/`):

- `probe1_registry_and_checker.jl` (log `probe1.log`): registry kinds = 31; kinds whose runtime is
  `LatticeMagnet` = `[:drift, :multipole, :octupole, :quadrupole, :sbend, :sextupole]`;
  `summarize_registry().elements` is a `Vector{Symbol}` of 31; negative control of
  `_cross_backend_violations` on synthetic reps: declared all-untouched with x parted by 4 ulps ->
  1 violation; declared x `:ulp` bound 4, measured 4 -> 0; measured 8 -> 1; one NaN on one side -> 2;
  occurrences of `_cross_backend_violations` in the suite = 5, occurrences of a non-empty
  expectation (`!isempty(violations`) = 0.
- `probe2_rounding_pins.jl` (log `probe2.log`): `cos(pi/2) = 6.123e-17`;
  `strength*beta0*cos(pi/2) = 1.53e-18`; `1 + that == 1.0` true; `op90.gamma1 == op90.gamma0` true;
  `strength*beta0` would need to reach 1.81 before `gamma1` moved by one ulp.
  `reference_pair_residual(reference_beta_gamma(E, PMASS_EV)...) == 0` for 591 of 2000 proton
  energies in [1, 300] GeV (29.6%), max |residual| 6.66e-16; residual at 275.1 GeV = -5.55e-16, at
  24 GeV = -2.22e-16, at 275 GeV and 2.5 GeV exactly 0. `particle_beta(PATHLENGTH_DELTA, 0.0) == beta0`
  for 2000 of 2000 energies. Registry examples carrying rule parameters: `thin_crab_cavity`
  (`(nothing, nothing)` tuples) and `thin_rf_cavity` (`nothing`), i.e. inactive. PIC cache-key
  extraction replicated: cuda key 10 fields / 1624-char blob, cpu key 6 fields / 264-char blob,
  `setdiff(cpu, cuda)` empty; dropping `interaction_grid` from the cuda key text -> `setdiff =
  {:interaction_grid}` (the tripwire fires); re-indenting the cuda key's closing paren -> blob 3047
  chars, still 10 fields, test still passes (over-capture is silent).
- Shell counts: fixtures in part (d) of the rounding-classes testset = 24 (`sed -n '13770,13800p' |
  grep -c '^\s*("'`); CUDA conditionals in the region = 12 (11 with a visible `else`); `_lane_gate`
  pairs = 4; `OCTOPUS_SKIP_SCRIPT_MODE_TEST` appears only in `test/runtests.jl` (not in
  `.github/workflows/ci.yml`); hand-pinned class-table kinds = 28 of 31 (missing `multipole`,
  `octupole`, `sextupole`); `docs/todo.md` has no row naming the Lorentz boost or the pole-face maps.

No testset of the region was run end to end (the measurement testsets need the GPU and minutes; the
brief asks for short probes). Every lead below rests on the read plus the probe named in its Repro.

## Leads

### LEAD U32-1 [Moderate, confidence med] test/runtests.jl:13765
Claim: The cross-backend checker `_cross_backend_violations`, the instrument behind three measurement testsets in this region (13765, 15377, 15451) and the per-kind arm of `validation/tracking_backend_consistency.jl`, is never fed a known defect anywhere in the suite, so an inverted or vacuous checker would turn every CPU/CUDA class measurement green.
Mechanism: All five suite call sites assert `isempty(violations)`; the anti-vacuity checks at 13808-13811 exercise `_cross_backend_agreement` (the measurement sees differences, the aperture killed) but never the classifier that turns agreement plus declaration into violations. Phase 9 of the protocol requires a negative control per regression test; probe 1 shows the checker does fire today (declared bitwise and parted by 4 ulps -> 1 violation; bound 4 measured 8 -> 1; a one-sided NaN -> 2), so the lead is the missing control, not a broken instrument.
Repro: `grep -c '_cross_backend_violations' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` (5) and `grep -c '!isempty(violations' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` (0); `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U32/probe1_registry_and_checker.jl` prints the three synthetic-defect violation counts 1, 1, 2 that a suite control should pin.

### LEAD U32-2 [Moderate, confidence med] test/runtests.jl:15806
Claim: The pin `keys(tracking_task_option_schema()) == (:record_turn_times, :luminosity_tracking, :artifact, :loss_report)` is a hand list, and the comment's claim that "a new public task option is invisible until it appears in the schema" names a tripwire nothing provides: a `TrackingTask` keyword added without a schema entry fails no test and no validator.
Mechanism: The pin fixes the schema's key set, not the constructor's keyword set; `validate_configuration_metadata` (src/tasks/strongstrong/interface.jl:2059-2066) checks only `keys(schema) ⊆ fieldnames(TrackingTask)` plus consumer and default per declared key, i.e. the direction that cannot see an undeclared keyword. This is the exact gap the 2026-10-16 neighbour audit's S4-10 found for `artifact` and `loss_report`, closed by adding the two names by hand; the derivation would be `Base.kwarg_decl` over `methods(TrackingTask)` against `keys(tracking_task_option_schema())`. Cross-file seam (interface.jl, Contracts.jl); reported and stopped.
Repro: `grep -n 'kwarg_decl' -r /cfs/ad/dxu/Library/Julia/Octopus/src` returns nothing; `grep -n 'tracking_task_option_schema())) ⊆' /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/interface.jl` shows the one-directional check. Confirming experiment (attended session, not run here): add a keyword `foo=false` to the `TrackingTask` constructor with no schema entry and observe the fast lane stay green.

### LEAD U32-3 [Moderate, confidence low] test/runtests.jl:13688
Claim: The declared cross-backend bounds the region pins, 8192 ulps of scale for a bend with pole-face angles (measured 829-1697) and 16384 for the Lorentz boost (px measured 3937), are the cancellation class (brief class 12) that fix batch 3 unit K removed from the bend body and the solenoid, and nothing tracks the remaining two: `docs/todo.md` has no row for the face maps or the boost.
Mechanism: `docs/history/crab_cavity_noise_audit_fixes_batch3_2026_10_17.md` 176-186 places the parting in `_rot_xz(e)` turning the momentum by an O(sin e) share of ps and `_wedge(-e, b1)` turning it back, "the last bits of two O(sin e) intermediates land on the O(px) result"; the declaration was widened to 8192 and `current_runtime.md` carries the figure, which is the "tolerance table that widens to hide a floor" shape of the hypothesis unless the deferral is recorded as a decision. Out of hypothesis for this unit (kernel numerics live in src/elements, outside the region); seam for the auditor.
Repro: `grep -n -i 'lorentz boost\|pole.face' /cfs/ad/dxu/Library/Julia/Octopus/docs/todo.md` (no row); `grep -n '8192\|16384' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | awk -F: '$1>=13660 && $1<=13710'` shows the pinned declarations; the run log of the "Cross-backend rounding classes" testset part (d) prints the measured ulps per kind beside the declared bound.

### LEAD U32-4 [Minor, confidence high] test/runtests.jl:15580
Claim: `@test reference_pair_residual(reference_beta_gamma(275e9, PMASS_EV)...) == 0` is a pin resting on rounding luck for one energy, not on structure.
Mechanism: `reference_pair_residual` evaluates `(a - ibg)*(a + ibg) - 1` on a `beta0` that is itself `sqrt((g-1)(g+1))/g`; its docstring (src/track/longitudinal.jl:155) promises "0 or one ulp", and the measurement agrees: the residual is exactly 0 for 29.6% of proton energies in [1, 300] GeV and -5.55e-16 at 275.1 GeV. The next line (15582) already pins the structural claim with `<= 1e-15` for three energies; the `== 0` line adds a fixture-specific bit pattern that any equally valid rewrite of `reference_beta` would break with no physics change.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U32/probe2_rounding_pins.jl` prints "residual == 0 exactly for 591 of 2000 proton energies ... (29.6%)" and the -5.55e-16 at 275.1 GeV.

### LEAD U32-5 [Minor, confidence high] test/runtests.jl:15031
Claim: `@test op90.rho == 1` with the comment "a phase-pi/2 cavity (zero design gain) leaves the reference alone: rho == 1 exactly" holds because `1 + 1.53e-18` rounds to 1.0, not because the design gain is zero.
Mechanism: `_accelerating_exit_pair` (src/elements/rf_cavity.jl:800) computes `gamma1 = gamma0 * (1 + strength * beta0 * cos(phase))` and `cos(pi/2) = 6.12e-17 != 0`; the design gain `strength*cos(phase)` the exit map subtracts is 1.53e-18, and `gamma1 == gamma0` only because the relative perturbation is below `eps(1.0)/2`. The pin cannot fail for any physical strength (`strength*beta0` would need to exceed 1.81), so it is harmless today, but it is a rounding statement presented as an exact identity; the structural spelling would be `cospi` or an explicit zero-gain fixture (`strength=0.0`, which 15018-15020 already pins bit for bit).
Repro: the probe 2 command above prints "cos(pi/2) = 6.123e-17", "1 + strength*beta0*cos(pi/2) == 1.0 : true", "design gain strength*cos(phase) = 1.53e-18".

### LEAD U32-6 [Minor, confidence high] test/runtests.jl:13323
Claim: In part (c) of "One precision rule" the guard `typed isa Exception && continue  # reported by part (b)` is unreachable for every kind but `:line`, so a kind that loses its typed form aborts the device half at the first such kind instead of being reported per kind as the comment says.
Mechanism: Line 13322 reads `typed = kind === :line ? line32 : typed_example(kind, Float32)`; only `line32` went through `attempt`, and `typed_example` throws directly, outside the `@testset let kind = kind` that would record it as one kind's error. Part (b) wraps the same construction in `attempt` for exactly this reason (13214-13218); the RED reproduction on ac3fbb2 the header describes (21 kinds without a typed form) would have ended part (c) at the first kind. Test-quality only; the verdict is still red.
Repro: `grep -n 'typed = kind === :line ? line32 : typed_example' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` shows no `attempt(` on the line; `grep -n 'typed isa Exception && continue' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` shows the guard it feeds.

### LEAD U32-7 [Minor, confidence med] test/runtests.jl:14519
Claim: The `if CUDA_TESTS_ACTIVE` block of "Solver option effectiveness" (the derived both-backend option count, `both >= 3`, and `cuda_options_checked == cuda_only_options + both`) has no `else`, so without a GPU the device-count check vanishes with no skip in the summary.
Mechanism: The suite's own header (lines 56-61) states the rule "gated sets without an else still vanish silently -- prefer `else @test_skip`"; eleven of the region's twelve CUDA conditionals follow it, this one does not. The tolerant status line at 14511 documents the skip in a comment only. Checked and found sound alongside: the contract itself returns `:failed` for CPU failures before its `:skipped` return (src/contracts/Contracts.jl:3929-3940), so no CPU regression is masked on CI.
Repro: `awk 'NR>=14503 && NR<=14554 && /CUDA_TESTS_ACTIVE|@test_skip|else/' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` lists the gate at 14519 with no `else`/`@test_skip` inside the testset.

### LEAD U32-8 [Minor, confidence med] test/runtests.jl:15678
Claim: Under `OCTOPUS_SKIP_SCRIPT_MODE_TEST=1` the script-mode testset records `@test true`, a Pass for a check that did not run, the green-lie shape the 2026-08-05 audit (U20) removed from three sites.
Mechanism: The branch at 15676-15678 logs an `@info` and then `@test true`; the sibling branch for an unbuildable environment at 15710 uses `@test_broken false` so the summary shows Broken. The two outcomes are the same (branch not exercised) and report differently. CI does not set the variable (not in `.github/workflows/ci.yml`), so today only a developer's local run can mint the pass.
Repro: `grep -rn 'OCTOPUS_SKIP_SCRIPT_MODE_TEST' /cfs/ad/dxu/Library/Julia/Octopus/test /cfs/ad/dxu/Library/Julia/Octopus/.github` shows the variable read at 15676 and nowhere else; `awk 'NR==15678' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` prints `@test true`.

### LEAD U32-9 [Minor, confidence high] test/runtests.jl:13814
Claim: The skip message "the measurement of the declared classes (31 registry examples and 25 mixed fixtures) is not exercised" hand-copies a fixture count that is 24.
Mechanism: The `fixtures` tuple at 13770-13796 has 24 entries; the two anti-vacuity calls (13808, 13810) re-measure an example and a fixture already in the list, so no count gives 25. Class 14 (a number in prose with no derivation); the "31" is right (probe 1: 31 registry kinds).
Repro: `sed -n '13770,13800p' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | grep -c '^\s*("'` prints 24.

### LEAD U32-10 [Minor, confidence low] test/runtests.jl:13809
Claim: The anti-vacuity pin `@test !bend.x.bitwise` asserts that the two backends DIFFER on the sbend example's x, which is a pin on the device compiler's FMA-contraction choice rather than on a property of the code.
Mechanism: `src/track/Track.jl` (the `CrossBackendRounding` docstring, 176-190) states that which multiply the device fuses "is the compiler's choice in the surrounding kernel, not the author's" and that a fixture may coincide bitwise (the octupole example on 1e5 particles); a CUDA/LLVM version that fuses the bend body differently makes this testset red with no defect anywhere. The intent (the measurement can see differences) is right; the chosen instance is the fragile part. Severity Minor because a false red is loud, not silent.
Repro: the "Cross-backend rounding classes" testset's part (d) log line for `sbend` shows `x=<ulps>/u`; a run on a different CUDA toolkit printing `x=B/u` would fail 13809 while every declaration still holds.

### LEAD U32-11 [Minor, confidence med] test/runtests.jl:13675
Claim: The hand-pinned class table of part (c) covers 28 of the 31 registry kinds (no pin for `sextupole`, `octupole`, `multipole`) and carries no tripwire that every registry kind has a pinned mark, so on CI (no GPU) those three declarations are checked only for existence and a non-empty `why`.
Mechanism: The loop at 13669-13674 derives `kinds` from the registry and asserts `class isa CrossBackendRounding && !isempty(class.why)`; the per-kind marks at 13675-13702 are a hand list. On a GPU, part (d) measures all 31, so the gap is CI-only; a future kind lands with no pinned class and nothing says so (the derived-vs-copied shape of the brief's class 2).
Repro: `awk 'NR>=13667 && NR<=13738' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | grep -o 'table\[:[a-z_0-9]*\]' | sort -u | wc -l` prints 28 against the 31 kinds `probe1.log` lists.

### LEAD U32-12 [Minor, confidence high] test/runtests.jl:14687
Claim: The comment "the `caught` bucket below says what" and "The caught bucket holds aperture.x/y_limit, gaussian_strong_beam.sigz and thin_strong_beam.kbb/klum -- five, by construction" refer to a bucket that does not exist; the swallowed `MethodError`/`InexactError` parameters are counted nowhere.
Mechanism: The sweep at 14641-14703 keeps only `verified` and `disagreed`; the `catch` at 14666-14676 rethrows anything but the two admitted types and records nothing for them. A sixth parameter silently entering the swallowed set is visible only through the exact `length(verified) == 29` pin, and only if it was previously verified; a new parameter that is swallowed from its first day is invisible. Class 14 (a claim about behaviour the code does not have) with a class 13 edge.
Repro: `awk 'NR>=14556 && NR<=14703 && /caught/' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` prints only the two comment lines, no variable.

### LEAD U32-13 [Minor, confidence low] test/runtests.jl:15833
Claim: The source-reading tripwire "CUDA and CPU PIC cache keys cannot drift apart" bounds its extraction from below only (`>= 6`, `>= 10`) and has no negative control, so an over-captured blob passes silently.
Mechanism: `key_fields` cuts the blob from the marker to the first `"\n            )"` / `"\n    )"` after it; a re-indented closing paren moves the cut to a later line. Probe 2 replicates the extraction: today 10 and 6 fields, subset holds, and dropping `interaction_grid` from the cuda text makes the check fire (the instrument works); re-indenting the cuda closer grows the blob from 1624 to 3047 characters while the test still passes. An over-capture that swallowed another function's `solver.<field>` reads would make the subset check weaker, the direction that goes blind; an exact-count pin or a mutation control would close it.
Repro: the probe 2 command above prints "after re-indenting the closer: cuda blob 3047 chars, 10 fields; setdiff(cpu, cuda) = Set{Symbol}()" after "after dropping interaction_grid ... setdiff(cpu, cuda) = Set([:interaction_grid])".

Style only, no LEAD block: 15262 uses `@test_broken false` where the rest of the region uses
`@test_skip` for the same CUDA-inactive outcome (both show as Broken); 15329 asserts that this
file's own text contains the wrapper-walk tripwire entry (self-referential, the real tripwire is
test 7 of the turn-modulation testset at 10763); 15842 pins the generic Float64 fallback of
`numeric_type` on a runtime element as documentation of a vacuity rather than as a property worth
keeping; `one(i, h)` at 16021 shadows `Base.one` inside its `let` (unused there).

## Clean

- Hypothesis 1 (checks that never execute): all twelve CUDA conditionals in the region located
  (13039, 13143, 13318, 13488, 13607, 13738, 14430, 14486, 14519, 15222, 15331, and the status line
  14511); eleven carry a visible `else` (`@test_skip` x9, `@test_broken false` x2), the twelfth is
  U32-7. The four `_lane_gate` sections are each wrapped `if _lane_gate(...) ... end` (13948/14136,
  14502/14554, 15662/15714, 15932/16036) and print the LANE SKIP line in the fast lane by the
  preamble's mechanism (lines 13-28 read). No tolerance aborts a run; every `@test` in the region is
  reachable on the full lane with a GPU. The solver-option contract returns `:failed` for CPU
  failures before its `:skipped` return (Contracts.jl 3929-3940), so the tolerant status assertion
  at 14511 masks nothing on CI.
- Hypothesis 2 (negative controls executed): PTC table truncation (14275-14287) and MAD-X truncation
  plus a corrupted length (14341-14362) both run and must fail by name; the element-effectiveness
  contract is driven to `:failed` by an emptied allowlist (14094-14099) and by the killing aperture
  probe (14110-14115), with `_probe_deviation` pinned at its three corners (14117-14122) and the
  survivable probe shown to survive (14125-14130); the solver-option contract by two mutation
  controls (14534-14550); the body-schema completion by a typo that still warns (14176); the Beam
  refusal on both documented entry points (15914-15921). Circularity: the "stated list is pointed
  to" checks (13820-13831) are pointer checks on a script and a doc, not consultations of the
  validated artifact; the PIC key tripwire reads source by design (U32-13 is about its bounds).
- Hypothesis 3 (pins and derivations): `RBendSpec` bitwise against the half-angle `SBendSpec`
  (13889-13897) is structural, `RBendSpec(; kwargs...) = SBendSpec(; _rbend_params(kwargs)...)`
  (lattice_magnets.jl:1413) with commutative addition of the face angles. The task-route versus
  bare-`track!` digests of part (e) (13107-13122) compare one kernel with itself and are printed,
  not pinned to a machine literal. `particle_beta(PATHLENGTH_DELTA, 0.0) == beta0` (15641) is
  structural: `_beta_of = beta0*(1+delta)/(1+beta0*pt)` (longitudinal.jl:287), 2000 of 2000
  energies agree (probe 2). Stated tolerances with their measurements: the Float32 cell pins are
  20x the measured gaps (13483-13496), the 1024 ulps32 pin is above ten times the larger of two
  measurements (13135-13156), the 64-turn surveyed-cavity bound 16 ulp is derived as a doubled
  random walk (15241-15260), the luminosity attribution rtol 1e-12 against measured 1.3e-16 and
  1.2e-14 (15432-15437). Derived sets: `_concrete_octopus_subtypes` keeps only
  `parentmodule(S) === Octopus` (interface.jl:1863-1871), so the suite's `Main._FixIBareOp` cannot
  leak into the typeless-ops pin (13254) or the declares-no-default pin (13636); the registry kinds
  number 31 as the two skip messages say (probe 1); the six `LatticeMagnet` kinds the U9-2 loop
  names equal the registry-derived set (probe 1); `summarize_registry().elements` is a
  `Vector{Symbol}`, so the `kd in ...` registration checks at 13943-13946 are live (probe 1); the
  `stored_floats` helper's not descending into rule objects is moot because both cavity examples
  carry `nothing` rules (probe 2); the PIC key extraction yields the expected 10 and 6 fields and
  fires on a dropped field (probe 2).
- Measurement instrument: `_cross_backend_agreement` and `_cross_backend_violations` (Track.jl
  369-432) read line by line; a `:ulp` coordinate that agrees bitwise is not a violation, a one-sided
  NaN and an empty comparison are, the scale-based ulp count is `max_abs / eps(scale)` with
  `scale == 0` handled; probe 1 confirms the three failure modes fire.
- Physics pins read for sense (not re-measured): the curved-drift conjugation identity and the
  polygon convergence (14178-14257), the RF beta-factor check at three energies (14767-14776), the
  nu_s ~ sqrt(V) scaling (14779-14797), the F16 slip A/B with its uncorrected baseline kept
  measurable (14891-14901) and the wrong-side-of-transition instability (14906-14912), the
  cancellation-free conversion round trips with RELATIVE tolerances only (15541-15569), the
  Hessian's symmetry bound and FD column pins (15991-16003).

## Unchecked

- No testset in the region was executed end to end; the measured numbers the region prints
  (part (d) tables, the Float32 gaps, the surveyed-cavity ulps) were not re-measured here. Reason:
  the measurement testsets need the GPU and minutes, and the brief asks for short probes.
- The tune estimator of "RF velocity slip" (14854-14880) was read, not fed a known-frequency
  series; its unbiasedness claim (~1e-7) is taken from the comment.
- The CUDA kernel paths behind "CUDA tracks a wrapped strong beam" and the device compile of every
  typed form are outside the region (src/track/strong_beam_track.jl, the fused launch); the
  receipts the testset reads (`:cuda_weak_strong_launch`) were not traced to their producer.
- The previous audit's U18 and U19 reports were consulted only by keyword grep; no lead of this
  unit touched their regions, so they were not read in full.
- Whether the `WhiteNoise` fixtures compiled three times with one explicit `rng_id` (13703, 13781,
  13784) emit the duplicate-stream warning on every run was not checked; it would be noise in the
  log, not a verdict change.
