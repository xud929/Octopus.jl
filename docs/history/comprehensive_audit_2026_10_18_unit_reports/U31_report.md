# U31: test/runtests.jl lines 9636-12910 — misalignment and ref_tilt maps, the bend and series numerics, turn modulation (rules, slots, spectral tables, the RF cavity)

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every
claim below is a LEAD, not a finding. Line numbers are pointers that rot; each Repro is written
to survive drift.

## Region

`test/runtests.jl` lines 9636-12910, 3275 lines, read line by line. Testsets in the region:

| lines | testset |
|---|---|
| 9636-9745 | "Misalignment maps" |
| 9747-9969 | "Aperture ids thread through the frame wrappers and kept-whole lines" |
| 9971-10034 | "The bend map is cancellation-free as b0 goes to zero" |
| 10036-10130 | "Cancellation-free longitudinal updates for the curved drift, the bend and the solenoid" |
| 10132-10247 | "Series helpers hold full precision across their crossovers" |
| 10249-10354 | "ref_tilt rolls the design orbit" |
| 10356-10389 | top-level helper `_forwarding_track_ops` |
| 10391-11146 | "Turn modulation: rules, wrapper and the pure hook" (parts a-k) |
| 11148-11161 | top-level probe types `_FixGBareOp`, `_FixGInnerNoForward`, `_FixGSubjectOp` |
| 11163-11309 | "Elements and scripts follow-ups: ... the ownership tripwire by forwarding" (parts 1-6) |
| 11311-11425 | "Turn modulation: slot bounds and labels at the wrap" |
| 11427-11960 | "Spectral turn table: exact spectrum, rms, phases and refusals" (parts a-j) |
| 11962-12270 | "Spectral turn table: the producer through the consumer and the recorder" (parts a-f) |
| 12272-12486 | "Turn modulation: white and pink spectra" (parts a-i) |
| 12488-12910 | "Turn modulation: the RF cavity by the same wrap" (parts a-j) |

Hypotheses briefed: (1) checks that never execute / CUDA gates that skip visibly; (2) circular
tests and tests without a negative control; (3) pins resting on rounding, hand-copied case lists,
sweeps whose instrument was never fed a defect.

## Provenance

READ line by line (the whole region, in nine contiguous chunks): 9636-9970, 9971-10250,
10249-10560, 10560-10960, 10960-11320, 11320-11700, 11700-12100, 12100-12500, 12500-12910.

READ for context (outside the region, to judge gating and structural claims):
`test/runtests.jl` 1-220 (lane gates `_lane_gate`/`_lane_full`, `CUDA_TESTS_ACTIVE`, the
abort-at-first-failing-testset caveat) and 23852-23872 (the sibling MPI harness scan);
`docs/design/testing_lanes.md` section 3; `docs/comprehensive_audit.md` Phase 9;
`src/elements/lattice_magnets.jl` 108-135 (`_atan_over`), 195-235 (`_asin_excess`,
`_curv_sin_excess`), 640-690 (`_wedge`); `src/elements/ref_tilt.jl` 50-168;
`src/elements/misalignment.jl` 40-110 (`_misalign_matrix`, `_frame_change`) and 365-430
(`_misalignment_wrap`); grep sites of `_track_cuda_elementwise!` in `src/track/phase6d_track.jl`
(421 throwing fallback, 426 CompositeLine, 428 the three-wrapper Union method);
`test/examples/*.jl` greps for the MPI gate line and `HARNESS_DEFAULT_SEED`.

EXECUTED (scripts and logs under
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U31/`):

- `probe1_bend_and_ulps.jl` -> `probe1.log`.
  (a) The b0 -> 0 linear-law pin: the max-|.| component is px (index 2); its d/b0 is
  -1.093082397 at b0 = 1e-3, 1e-4 and 1e-5 alike (constant to <= 1e-10 relative);
  |d - slope*b0| = 6.1e-17..8.9e-17 for b0 <= 1e-7 against the floor `floor8` = 2.22e-16
  (8 ulp of ref[2] = 0.19722), i.e. 2.2-3.3 ulp used, at most 0.344 of the tolerance. The x and
  z components' d/b0 move by 2.0e-4 and 1.9e-3 relative between b0 = 1e-3 and 1e-5 (genuine
  quadratic terms).
  (b) The ulps table, measured worst over the 101-particle sweep against bound (margin):
  curved drift z 0.50/4 (x8.1), 1.02/4 (x3.9), 4.73/16 (x3.4), 4.44/16 (x3.6); transverse
  2.57-5.94/16 (x2.7-6.2). Bend z 5.04/32, 15.57/64, 52.59/256, 11.83/64, 4.20/32,
  610.97/4096 (x4.1-7.6); transverse 2.96-7.89/32 (x4.1-10.8). Solenoid z 0.50/2 (x4.0),
  transverse 15.45 and 17.04/64 (x3.8-4.1). Curved solenoid z 2.11/8 and 1.36/8 (x3.8-5.9),
  transverse 2.62 and 3.31/16 (x4.8-6.1). `fixed=true` (pass-through coordinates bitwise
  untouched) on every row. The values match the comment's recorded measurements
  (4.7, 15.6, 52.6, 0.5, 2.1).
  (c) A copy of `_atan_over` with the crossover moved to 1e-2 and a 1e-10 defect on the closed
  branch passes all four suite assertions: `(true, true, true, true)`; its series truncation
  error at its own crossover is 1.43e-13 relative and its seam jump 9.99e-11.
- `probe2_wrapper_walks.jl` -> `probe2.log`. Derived from the method tables: 19 (function,
  position) pairs own a method specialised on a wrapper or `CompositeLine`; all 19 cover
  `MisalignedElement`, `RefTilted`, `TurnModulated` and `CompositeLine`; 18 are in the suite's
  `wrapper_walks` list; `_track_cuda_elementwise!` (position 2) is not. No listed walk lacks
  a specialised method.
- `probe3_flat_slope.jl` -> `probe3.log`. `slope_flat` = 1.0000000000000067 = 1 + 30 ulp(1.0)
  (6.661e-15); the BigFloat value of the same octave sums is 1 + 1.98e-18; reverse-order
  summation gives the identical Float64; `slope_brown` = -1.016999 (margin 0.017 over 1.0).
- `probe4_misalign_convention_inactive.jl` -> `probe4.log`. With `x_offset=1e-3`,
  `misalign_convention=:middle` is REFUSED (ArgumentError). With no alignment error set, `:middle`
  is ACCEPTED at spec construction, at `compile_runtime` (a `LatticeMagnet`), through
  `ref_tilt=0.3` (a `RefTilted`), and at `TrackingTask` construction; the string `"madx"` is
  accepted the same way.
- Greps: `derived = _forwarding_track_ops(octopus_track_ops)` occurs at 10741 (the derivation)
  and 11307 (inside the `occursin` literal); `joinpath(outdir, "123456789")` occurs 0 times in
  the suite's raw text (the escaped literal does not self-match, so that pin is sound);
  `use_mpi = env_bool("OCTOPUS_USE_MPI", false)` matches 3 harnesses (strong_strong_tracking,
  crab_cavity_noise, weak_strong_tracking), each declaring `const HARNESS_DEFAULT_SEED = 123456789`;
  `_track_cuda_elementwise` appears in the suite only at 15466/15472 (a direct-call pin), never in
  `wrapper_walks`.

## Leads

### LEAD U31-1 [Minor, confidence high] test/runtests.jl:10032
Claim: The `_atan_over` seam check straddles a hand-written `1.0e-4` copied from a bare literal in the source, so moving the crossover silently turns the check into a same-branch comparison that cannot see a seam or series defect (the U17b-2 class the sibling `_curv_vers`/`_sol_log_over_h` checks in the same region were already converted away from by deriving their probe points from `CURV_VERS_CROSSOVER`/`SOL_LOG_CROSSOVER`).
Mechanism: `src/elements/lattice_magnets.jl` writes the crossover as `abs(u) < real(T)(1e-4)` with no named constant (the same bare literal sits in `_curv_sin`, whose seam is not tested in this region), while the test evaluates `_atan_over(1.0e-4 + eps())` against `_atan_over(1.0e-4 - eps())` with rtol 1e-14; the other three `_atan_over` assertions are an exact value at 0, a truncated-series comparison at 1e-5 with rtol 1e-12, and `≈` at 0.7 with the default rtol 1.5e-8, none of which resolves a sub-1e-8 closed-branch error or a series that has become inaccurate at a moved crossover. Hypothesis 3 (derived-vs-copied), test quality only: no current numerical defect.
Repro: `grep -n "real(T)(1e-4)" src/elements/lattice_magnets.jl` prints two bare literals (`_curv_sin`, `_atan_over`) and no constant; `grep -n "_atan_over(1.0e-4" test/runtests.jl` prints the hand-copied straddle; `julia --project=. -e 'moved(u)=abs(u)<1e-2 ? one(u)-u*u/3*(one(u)-3*u*u/5) : atan(u)/u*(1+1e-10); println((moved(0.0)==1.0, isapprox(moved(1e-5),1-1e-10/3;rtol=1e-12), isapprox(moved(1e-4+eps()),moved(1e-4-eps());rtol=1e-14), isapprox(moved(0.7),atan(0.7)/0.7)))'` prints `(true, true, true, true)` for a copy whose seam jumps by 1.0e-10 and whose series is 1.4e-13 off at its crossover (probe1 part c).

### LEAD U31-2 [Minor, confidence high] test/runtests.jl:11307
Claim: The text tripwire `suite_derives_by_forwarding = occursin("derived = _forwarding_track_ops(octopus_track_ops)", suite)` matches its own string literal and therefore cannot fail.
Mechanism: `suite` is the raw text of `test/runtests.jl`; the pattern contains no quote characters, so the `occursin` call's own literal at this line is a verbatim occurrence of the pattern. The pattern occurs twice in the file (10741, the real derivation, and 11307, the literal); deleting the derivation at 10741 leaves one occurrence and the assertion true. The sibling pin two lines above it (`suite_copies_seed`, the `joinpath(outdir, \"123456789\")` pattern) escapes its quotes and does not self-match, which is why it is sound and this one is not. Hypothesis 2 (circular test).
Repro: `grep -n 'derived = _forwarding_track_ops(octopus_track_ops)' test/runtests.jl` prints two lines, the second being the `occursin(...)` literal itself; copy the suite to scratch, delete the first (the derivation line), and `occursin` on the copy still returns `true`.

### LEAD U31-3 [Moderate, confidence high] test/runtests.jl:11585
Claim: The flat-table negative control `@test abs(slope_flat) > 0.02 * 50` passes only because Float64 rounding placed `slope_flat` 30 ulp above 1.0; the exact value is 1 to 2e-18, so the strict inequality against `0.02 * 50 == 1.0` is a coin flip on the rounding of a 12-point least-squares over FFT octave sums, and a sign change on another FFTW build, Julia version or vector width turns the suite red with nothing wrong.
Mechanism: the flat table has 2^j bins of equal power per octave, so log2(octave power) is exactly linear in j and the slope is exactly 1; the test asserts both `abs(slope_flat - 1.0) <= 1e-9` and `abs(slope_flat) > 1.0`, admitting only slope_flat in (1.0, 1.0 + 1e-9]. Measured: slope_flat = 1.0000000000000067 (+6.66e-15, 30 ulp), BigFloat 1 + 1.98e-18, reverse-order summation identical here; the matching brown control sits at |−1.016999| with a genuine 0.017 margin. The suite aborts at its first failing testset (preamble, U17-7), so a false red here would drop every testset after it, including the RF-cavity, CUDA and physics backstops. The "50 times its tolerance" the comment claims is exactly saturated, not exceeded. Hypothesis 3 (pin resting on rounding).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U31/probe3_flat_slope.jl` prints `slope_flat - 1 = 6.661e-15 = 30.0 ulp(1.0)` and the BigFloat slope `1 + 1.98e-18`; a fix is `>=`, or a factor below 50 (e.g. `> 0.02 * 25`), so that the margin is real rather than a rounding sign.

### LEAD U31-4 [Minor, confidence high] test/runtests.jl:10751
Claim: `wrapper_walks`, declared "the SINGLE SOURCE of the walks a wrapper joins", is a hand-maintained list that omits `_track_cuda_elementwise!` (position 2), one of the 19 walks that own wrapper-specialised methods, so a fourth wrapper lacking that method passes the ownership tripwire and fails only at a CUDA launch of a wrapped strong beam, a GPU-only runtime error CI never sees.
Mechanism: the tripwire derives the wrapper set (good) but not the walk set; two walks (`_requires_cuda_elementwise`, `_aperture_rebind`) were appended only after fixes M and N found them missing, which is the drift this class produces. `src/track/phase6d_track.jl` gives `_track_cuda_elementwise!` a method on `Union{MisalignedElement,RefTilted,TurnModulated}` and one on `CompositeLine`, with a generic fallback that throws an ArgumentError naming the missing method; `owns_wrapper_method` would accept the Union method if the walk were listed. A derivation of the walk set from the method tables (every Octopus function with a method whose argument type is narrower than `AbstractTrackOp` and admits a wrapper), pinned both ways against the list as the wrapper set and the rule catalogue already are, closes the class. Hypothesis 3 (hand-copied case list).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U31/probe2_wrapper_walks.jl` prints `_track_cuda_elementwise!  pos=2  CompositeLine,MisalignedElement,RefTilted,TurnModulated  all-3  NOT-IN-SUITE-LIST` and every other derived walk as `listed`; `grep -n "_track_cuda_elementwise" test/runtests.jl` shows no occurrence inside the `wrapper_walks` tuple (only the direct-call pin near 15466).

### LEAD U31-5 [Minor, confidence high] test/runtests.jl:11287
Claim: The harness-seed loop in "Elements and scripts follow-ups" part (5) skips every harness that does not contain the exact text `use_mpi = env_bool("OCTOPUS_USE_MPI", false)` with a bare `continue`, and asserts nothing about how many harnesses it visited, so a respelling of that gate line in the harnesses would leave the part with zero executed assertions and a green summary.
Mechanism: `occursin("use_mpi = env_bool(\"OCTOPUS_USE_MPI\", false)", text) || continue` precedes the `@testset let harness = h` block; the sibling scan of the same gate line in the MPI testset (around line 23860, outside this region) carries both tripwires the copy lacks (`@test xor(reads, refuses)` per harness and `@test length(mpi_harnesses) >= 2`), so the discipline exists in the suite and this loop is its weaker twin. Three harnesses match today, each with the `HARNESS_DEFAULT_SEED` constant, so the gap is latent. Hypothesis 1 (a body behind a condition with no coverage count).
Repro: `grep -l 'use_mpi = env_bool("OCTOPUS_USE_MPI", false)' test/examples/*.jl | wc -l` prints 3; `grep -n 'occursin("use_mpi = env_bool' test/runtests.jl` prints the two scan sites, and reading the first shows no assertion on the visited count while the second asserts `>= 2`.

### LEAD U31-6 [Minor, confidence high] test/runtests.jl:9711 (OUT OF HYPOTHESIS; cross-file seam into src/elements/misalignment.jl `_misalignment_wrap`)
Claim: An invalid `misalign_convention` is accepted silently whenever no alignment error is set (`:middle`, or even the string `"madx"`, passes spec construction, `compile_runtime` and `TrackingTask` construction), and the only test of the refusal probes the active path (`x_offset=1e-3`), so the inactive behaviour of this public option is unverified and wrong by the repository's own rule ("a silently ignored non-default request is a defect"; defect class 5).
Mechanism: `_misalignment_wrap` returns `inner` as soon as `dx == dy == dz == xp == yp == tl == 0`, and the `conv in (:bmad, :madx) || throw(ArgumentError(...))` check sits after that return; no schema-level allowed-values check exists for the keyword (grep of `src/knowledge/` and the element files finds only the construction-help text "(:bmad or :madx)"). A lattice carrying a typo'd convention with offsets not yet applied tracks without complaint and is refused only when the first offset is added. The auditor's call whether the fix belongs at the spec schema (allowed values) or by hoisting the check above the early return.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U31/probe4_misalign_convention_inactive.jl` prints `ACCEPTED -> LatticeMagnet...` for `compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, misalign_convention=:middle))` and for `misalign_convention="madx"`, `ACCEPTED -> TrackingTask` for the task, and `REFUSED -> ArgumentError` only with `x_offset=1e-3`.

## Clean

What was checked and found sound, with the evidence.

- Hypothesis 1, gating. Every CUDA-dependent body in the region is behind `CUDA_TESTS_ACTIVE`
  (or its literal expansion in the RF testset) with an `else @test_skip` that names what was not
  checked: aperture ids (j), spectral consumer (b) and the per-backend loop in (d) (`@test_skip
  ... continue`), RF cavity (i); the Adapt walk has `@test_skip` without `_HAS_ADAPT`; the
  effectiveness contract in RF (j) skips loudly off the full lane. Every `if <condition>` guarding
  further assertions is preceded by a `@test` of the same condition (`length(logs_dup) == 1`,
  `length(logs_few) == 1`, `meta_k !== nothing`, `wk isa TurnModulated`, `ran === true`), and the
  silent `continue` in part (k) of the rules testset is closed by the final
  `containers_seen == container_set(_slot_rules)`. The only unguarded skip is U31-5.
- Hypothesis 2, negative controls executed in the region: the drift's pre-fix z form
  (`old_form_ulp > 10`, measured 94.8 vs the 1-ulp pin); the pink table against the flat
  periodogram and the flat against the pink shape (> 0.5 vs a 1e-10 pin); the brown D2 trap
  slope (|-1.017| vs the pink 0.02 pin, a real 0.017 margin); the shifted-phase owner generator
  (> 0.1); the Rayleigh table against the exact-periodogram pin (`max_ratio_dev > 0.5` beside
  `fixed_var_ratio <= 1e-20`); the two-bin kurtosis -0.75; the additive-strength pins asserted
  false beside the relative ones; `_forwarding_track_ops` fed probe types with and without the
  forward (11305); the TSC-style "the comparison can fail" counter-assertions on slot phases
  (11685, 11713). The RF cavity z reference (11236-11247) re-implements the kernel's
  drift-kick-drift in BigFloat using the package's own `convert_longitudinal`: a rounding
  reference by construction, appropriate for the rounding defect it pins (U2-4), and loud rather
  than circular if the kernel's splitting changes.
- Hypothesis 3, bitwise pins reviewed for structure rather than rounding:
  (i) aligned vs zero-offset compile (9654-9660) and bare vs `ref_tilt=0.0` (10264): the wrap
  returns `inner` itself, so the runtime is identical by type;
  (ii) `ref_tilt=0.37` vs `tilt=0.37` on a straight element (10298-10303): both take `c, s` from
  `_misalign_matrix(T, 0, 0, psi, false)` (`_ref_tilt_wrap`, ref_tilt.jl:166-167) and
  `_frame_change` with Q = R_z, o = 0 performs `c*x + s*y + 0*az`, `qz = ps`, `ds = ±0`, i.e.
  `_s_rotate`'s operations plus exact ×0, ×1, +0 terms, so the equality is structural for h = 0;
  (iii) `_wedge(A, 0.0, ...) == _rot_xz(...)` (10233): `_wedge` dispatches `b1 == 0 && return
  _rot_xz(...)` (lattice_magnets.jl:646);
  (iv) the CPU/CUDA aperture cases marked `bitwise` (9907-9967): the fixture has zero momenta, so
  every op in the drift and the translation is exact and the roll is correctly excluded;
  (v) the Hz-band table equals the tune table (11664): f_rev = 65536 is an exact power-of-two
  scaling; (vi) one call vs six calls, flat vs sub-line, fast vs general loop, device run vs
  device hand-tracking: the same arithmetic in the same order on both routes; (vii) the keying
  pins (`seq_pink[1] == sp_formula(0, 1)`, `cav.phase[1] == 1e-2 * draw(turn)`) are the
  documented formula re-derived in the test, stated to depend on summation order.
- The b0 -> 0 linear-law pin (9994-10001): sound and exactly described by its comment. Measured
  2.2-3.3 ulp against the 8-ulp floor, 0.34 of tolerance at worst (probe1 a). The rtol = 1e-8
  "linear law" holds because the max component is px, whose exit value is exactly affine in b0 in
  the exact sector-bend map (lab-frame canonical momentum conservation across the radial exit
  plane: px_f = px_i cos θ + (ps_i - b0 (1/h + x_i)) sin θ); x and z carry genuine b0² terms
  (2e-4 and 2e-3 relative at b0 = 1e-3) and would fail rtol 1e-8 if a fixture made one of them
  the maximum. Recorded here so a future fixture change knows the dependence; not a defect.
- The ulps tables (10079-10114): every bound is 2.7x-10.8x above the measured worst case and the
  comment's recorded numbers reproduce (probe1 b); the weak-field bend's 4096 is an explicitly
  declared pre-fix regime (|b0| < |h|/2 keeps the direct form), measured 611, not a widened floor.
- The series-helper seams (10132-10247) derive their probe points from `CURV_VERS_CROSSOVER` and
  `SOL_LOG_CROSSOVER`; value and derivative continuity are both pinned; the `_curv_sin_excess`
  argument order `(h, L)` matches the BigFloat reference at 10118 (source checked).
- Derived-and-pinned case lists (sound tripwires): the `inner`-field wrapper set vs the forwarding
  derivation (10743-10747, 11301-11304), the rule catalogue vs `AbstractTurnRule` subtypes
  (10942-10948), the wrap kinds from `_turn_modulation_wrap` methods and their converse by keyword
  and by `_turn_rule_values` (11000-11038), the container sets of `realize`/`_slot_rules`/
  `_realize_draws`/`_slot_nominals` (11043-11051), the containers reached through examples
  (11144), the spectral preset table vs the two docstrings and the refusal text (11481-11493),
  and the hand aperture-wrapper set pinned by set equality (9888). The walks list is the one
  enumeration without a derivation (U31-4).
- Statistical pins use derived bounds on seeded, deterministic sequences (5/sqrt(K), 5 sqrt(8/K),
  5/(2 sqrt(K_eff)), 4/sqrt(2 K_eff), the pink-rms quantile band [0.75, 1.6] with its Monte Carlo
  derivation in the comment); none is a tuned number, and none can flake under a fixed seed.
- Refusal coverage: every public keyword touched in the region (`TurnTable`, `WhiteNoise`,
  `PinkNoise`, `SpectralNoise`, `spectral_turn_table`, slot tables, rng ids, the RF scalar forms)
  has its invalid inputs refused by `ArgumentError` with message needles asserted, and the
  refusal path is asserted not to claim an rng stream.

## Unchecked

- The two statements in "Elements and scripts follow-ups" part (4) that the harness and the
  validation script were "verified by running them" are text pins by design; I did not run the
  harness or the validation script (out of scope for a reading unit; minutes-long).
- The effectiveness contract `validate(ElementParameterEffectivenessContract())` (12900-12905)
  and the lane-gated contract testsets it refers to were not executed (minutes; full-lane only).
- No CUDA arm in the region was executed by me; their skip visibility was checked by reading, and
  the CPU/CUDA bitwise claims were assessed structurally (fixture momenta zero), not re-measured.
- The out-of-region sibling of `_atan_over`'s literal, `_curv_sin`'s `real(T)(1e-4)`, and whether
  any other region straddles it, were not examined (seam for the auditor; see U31-1).
- Style only, not leads: the `||`-weakened assertion at 12148 (`=== WhiteNoise(...) || rng_id ==
  31`) still fails on a wrong id; the RF testset gates on the literal `Octopus._HAS_CUDA &&
  Octopus.CUDA.functional()` instead of `CUDA_TESTS_ACTIVE` (identical value); the kurtosis
  `println` inside a testset is honest about being printed, not pinned.
