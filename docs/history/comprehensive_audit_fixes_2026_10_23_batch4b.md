# Comprehensive-audit fix batch 4b (2026-10-23): the Minor pointer's code, test and script findings

**Status:** complete 2026-10-23: six units merged and verified, the two-arm full gate green with CUDA active on the integrated tree 053364c (section 3, first attempt), the push authorized in advance by the owner (2026-10-22, "continue and push when appropriate"); the push and its CI run are recorded by the campaign's next record or addendum.

Batch 4b of the 2026-10-18 comprehensive audit's fix campaign
([`comprehensive_audit_2026_10_18.md`](comprehensive_audit_2026_10_18.md); the earlier batches:
[`comprehensive_audit_fixes_2026_10_19.md`](comprehensive_audit_fixes_2026_10_19.md),
[`comprehensive_audit_fixes_2026_10_20_batch2.md`](comprehensive_audit_fixes_2026_10_20_batch2.md),
[`comprehensive_audit_fixes_2026_10_21_batch3.md`](comprehensive_audit_fixes_2026_10_21_batch3.md) with its 3b addendum,
[`comprehensive_audit_fixes_2026_10_22_batch4a.md`](comprehensive_audit_fixes_2026_10_22_batch4a.md)).
It works the row "Minor findings of the 2026-10-18 comprehensive audit (pointer)": of the record's 165
Minor ids, 81 were closed by batches 1 to 3 and 34 belong to other open rows; the 50 that remained were
grouped by file into six units, together with the fifteen `.jl` leads batch 4a deferred (D1 to D14, D17,
D18). Five Float32 rounding-class ids (F-27, F-28, F-30, F-33, F-37) stay with the rounding-class row,
which waits on the owner's two decisions. The method is batch 3's: each unit proposes in its own
worktree with a regression test shown red on the unfixed base, the integrator re-runs the red on the
base with the unit's test tree and the green on the integrated tree with neighbours, merges `--no-ff`,
and gates the integrated tree with the two-arm full gate (CUDA active; AVX2).

## 1 Units and what landed

### Unit CT: `src/contracts/Contracts.jl`, second half (F-109 to F-115)

Four commits, tip 5519b6f. The solver-option sweep's vacuity guard compares each alternative with the
BASELINE solver's value before the CUDA-only deferral, on every process (F-109; "Solver option
effectiveness" re-pinned on the message); `_solver_contract_spread` is NaN-aware and a non-repeatable
NaN baseline fails the solver by name instead of certifying it (F-110); the element-parameter sweep names
its undecided pairs by reason and stage, carries its deviations with a reporting-only
`weak_evidence_floor = 1e-12` (ten pairs below it, each explained), probes anisotropically where the
isotropic probe cancelled, adds two exemption rows and retires one measured false (F-111, F-112; the
checked count 549 -> 548 with its reason; two undeclared enums pinned by name as the element owner's);
the `:configuration` branch that certified a `solver_runtime` dump is gone and a circular consumer is a
named failure (F-113); the high-energy weak-strong limit judges the PIC electron (metric
`pic_electron_max_abs_change` at `gaussian_atol`; injected 1e-12 m kick: the base certified it, the fix
fails it) (F-114); the PTC reference table is read whole or refused by row and by case (F-115). Red on
5907916: the three new testsets 2/6/3, 9/7/9, 3/1/2 and the two re-pinned sweeps 50/2/11, 8/1
(`CT_red.log`); green with nine titles, 294 passes (`CT_green.log`).

### Unit TR: track files, patch, RF cavity, strong beam, the conventions note's pin (F-102, F-104, F-116, D5, D7, D8, D14, D18)

Seven commits, tip 53da3dc. The dead second walker `_track_line_elementwise!` /
`_flush_cuda_fused_segment!` (12 occurrences, 0 call sites) is deleted and the suite pins the symbols
absent (F-102); `cuda_track_lumped_rad_kernel!` and the two LumpedRad-specific CUDA `track!` methods are
deleted, the deprecated entry taking the one fused route (measured bitwise equal to the removed kernel
before the change, 1 to 2 ulps of scale from the host after, as the live route is), and the per-element
`:auto` block rule is one function `_cuda_resolve_coverage_blocks` with `_CUDA_COVERAGE_BLOCK_CAP = 256`
used by the three strong-beam sites, whose receipts gain `resolved_by` (F-104); F-116 was found closed by
32b2b57 (batch 3, unit I) with the audit's shapes refused by name. The Hirata docstrings say `pz -= (px^2 +
py^2)/4`, which the kernel and the boost's `S' = 1/2` give (D5); the patch citations name section 7 by its
title (D7); a symplecticity-after-undoing-the-rescale pin joins the Scope B testset (64 eps, measured
5.2e-17; injections red at 1e-2) and the RF comment says what is pinned (D8); the MAD-X `deltap` clause
is qualified as the Twiss note does, in `strong_beam.jl` and `_CANONICAL_DISPERSION_NOTE` (D14); the
conventions note's SAD cubic reads `b^2` with the F-164 testset's two pins changed together and a negative
pin on `h^2y` (D18, batch 4a's deferral); the two example comments say `using MPI` follows. Red on
5907916: the F-102/F-104 testset 3/7/8 and the F-164 testset 6/3 (`TR_red.log`); green with nine titles
including the 582-assertion turn-modulation testset (`TR_green.log`). Lead for the integrator:
`src/policies/Policies.jl:1387` (`_active_cuda_launch`) still hand-copies the `:auto` block rule.

### Unit SS: the strong-strong solver files (F-29, F-31, F-32, F-34, F-35, F-36, F-38, F-39, F-40, F-42, F-43, F-44, F-72, D6)

Three commits, tip 47c9b32. The wavefront build kernel takes the solver's `min_sigma` in the beam's type
(routes differed 6e-8 relative on Float32 with a binding floor; now <= 1e-14) (F-29); the TSC docstring is
scoped (F-31); the pair migration pools its per-beam buckets and uses a pooled stable counting sort
(steady state 7.5 kB against 1.2 to 4.8 MB; `MergeSort`'s `scratch` keyword does not reach the legacy
algorithm in Julia 1.12, measured) (F-32); the CUDA spectral workspace gives the same mesh-width advisory
as the CPU one and records it (F-34); a `:grid_free` field point past the Dirichlet wall gets zero field
with a warning and a `:spectral_box_coverage` receipt, in-box values untouched to the bit (F-35); one
reporter writes a receipt per clipping event beside the budgeted warning on both backends (F-36);
`domain_factor` must be finite and positive at construction and an overflowed box names it on CPU and
CUDA (F-38); the spectral pair-schedule receipt has one shape on every route and backend (F-39); the CUDA
spectral luminosity pools its device temporaries, typed by the broadcast's element type so the `:single`
class does not move (luminosity bitwise before and after in six configurations; 647 kB -> 263 kB and 4.7
MB -> 1.2 MB per collide) (F-40); both Gaussian-PIC indexed kick kernels are grid-strided like their twins
(F-42); the reduced record is read through named accessors (F-43); the hybrid's inert PIC options are one
table its refusals and its report both read (F-44); `LongitudinalSlicing` refuses non-finite `:specified`
positions by name at construction (`interface.jl`, outside the unit's list, no other owner) (F-72); the
`_pic_cic_weights` docstring no longer lists the removed `:quantile` estimator (D6). Twelve new testsets,
all red on 5907916 (`SS_red.log`) and green with three neighbours on the integrated tree
(`SS_green.log`). Lead: the PIC family's own `:pic_pair_schedule` receipt differs in shape between
`pic_cpu.jl`, `gaussian_pic.jl`, `pic_cpu_sliced.jl` and the CUDA sites (F-39's class, outside its anchor).

### Unit TW: the Twiss contracts and analysis kernels (F-141 to F-145, F-178, F-193, D1 to D4)

Eight commits, tip 0dd7687. `_identity_contract_record!` fails a row by name on a non-finite kappa
(F-141); the Layer 3 rows judge the physical tunes, Twiss functions and the covariance accessor against
independent references (`eigvals(result.matrix)`, the physical normalizer's `U diag(eps) U'`, a new (M1)
row), multipliers 16/16/8/8 frozen two-arm, the slug count 58 derived by every consumer, and the V1
re-derivation is fed doctored verdicts in both directions (F-142); every full MAD-X fixture and PTC 5D
row asserts its coasting precondition through one predicate (F-143); tool versions are read from the
table headers and asserted against the file names, the fixture lists tripwired against the scripts'
constants and the tables (F-144); the `emittances` observable requires the alternative covariance's
symplectic invariants to match within `8 eps kappa` (ratios 0.06 and 0.05; a doubled control at 1.5e13)
(F-145); `_check_longitudinal_index` is one check, a bad index on a coasting map an `ArgumentError` and a
valid one an inactive option (F-178); `_mais_ripken` rephases through `_rephase_mode` and the real-class
floor's window is MEASURED by a committed testset every run (accepted 0.295, rejected 33.6 at multiplier
1; `_REAL_CLASS_MULTIPLIER` itself untouched: the owner item of the Twiss row) (F-193); the four
docstring derivations: 12.70 accepted / 2.39 rejected decades (D1), the window edge 7.7e7 = 1.2e7 x 64 /
10 (D2), the branch floor derived and measured (largest admitted 1.8e-3 of the floor; D3), `tau_s` as the
selected candidate's trace (D4). Red on 5907916: seven titles (`TW_red.log`), the window testset red by
injection in the unit's probes; green with eleven titles (`TW_green.log`).

### Unit TS: the suite's instrument repairs (F-146 to F-155, F-157 to F-159, D9, D11, D12)

Five commits, tip dfafaa2; `test/runtests.jl` +377/-109 and the dry-run hook seam of
`validation/twiss_dispersion_identities.jl`. The no-GPU banner's file list derives from the tree (F-146);
the stage 6 registry restore covers the four containers with a derived tripwire (F-147); the snapshot
guards locate the file by `pkgdir` and skip visibly when absent (F-148); the docs-index check covers every
file type under `docs/`, matches whole paths against the index's link targets, and checks dangling links
(135 by path, 377 by marker, 0 missing; F-149 = D10, the hole batch 4a's `.txt` showed); the hoisted TSC
gate has a skip arm (F-150); the stage 6 re-open ratio warns above 0.25 and the 12.2-2 branch is keyed on
the design determinant (F-151); the quartet is exactly one cluster with its departures pinned, the DBA
witness the unit-circle spectrum plus `R56 != 0` (the trace bound passed on an unstable map) (F-152); the
ladder's flip point pinned, the G tautology replaced by `(G S)^2 = -P` and `P G = G`, the (I1) floor
against the test's own `c_route eps kappa` (F-153); exports parsed from the export statement (F-154); the
identities script reads `IDENT_DRY_RUN_HOOK` from the including module and prints a loud skip, the
testset asserting no `Main` leak (F-155); the explicit union `:indefinite` fixture (F-157); the default
closed-orbit rule asserted at the consumer and the Reason table derived from `DETERMINATION_REASONS`
(F-158); the coasting multiplier 2048 by the one-tenth rule, the virtual drifts within 8 ulps with
pairwise separation >= 1000 ulps, CUDA LumpedRad parity on six coordinates (F-159); the lane banner and
header say "before any push" (D9); the solenoid transverse error is scaled at the kinetic momentum
(thirteen seeds: worst 3.4 under the new scale against 215 under the old; bound 16) (D11); the `L = 0`
identity is stated per coordinate with a discriminating-power tripwire (D12). Every repaired check was
shown red by an injected regression in the unit's probes; the integrator re-ran its twenty-four titles
green on the merged tree and three injections (`TS_green.log`): the determinant substitution on the Edwards-Teng 12.2-2 testset red, the snapshot-miss substitution on the Stage 6 registry testset a visible Broken row, and the seed substitution on the solenoid pins green under the new seed-robust pin (`ts_verify.sh`, PRE_UNTIL = 9800 on the live merged suite, 00:47 to 00:56).

### Unit VA: the validation scripts (F-209, F-243, D13, D17)

Five commits, tip 69b7518. The counter-RNG validation's uniform-variance bound is `6/sqrt(180 N)`, its
tail fractions are six-sigma binomial gates, its "13.8 %" re-derived (14.7 % by the formula, 13.3 % by
Monte Carlo over 8192 streams), its header consistent (F-209: U40-6 to U40-9; U40-5 and U40-15 closed by
batch 2's unit D); the crab-noise script's prediction defaults have one source (`REPORT_REFERENCE_DEFAULTS`)
held to its header at load, the default sweep order derives from `SWEEP_CASES` (17 cases; `report` prints
`not_evaluated=`), the `result/` pointer is gone, labels carry typed turn counts, the normaliser's
`trusted` column is `judged` (U40-10 to U40-14, D13); the effectiveness script honours the GPU-require
flag with exit 1, the extreme benchmark refuses the CPU override and derives its provenance, the
diagnostics check runs a real CPU PIC collision, four scripts forward to one tune estimator with the two
package-free copies held by a suite tripwire, the paper drivers gain verdicts on the crossing anchor and
the tune calibration (the lambda pair and `emit_xcode` stay characterisation: a verdict needs the
converged hours-long settings) (F-243: U54-3 to U54-9; U54-2 closed by 32b2b57; U54-10 = F-49 not
closed, a lead); the slicing convergence study reproduces the note's `N_s = 1, 4, 11` cells at +17 s
reduced (D17). Red on 5907916 with its test tree: "The standalone theory script's constants match the framework's" 7/1 and "Elements and scripts follow-ups ..." red, the spectra and retired-spelling testsets green on both trees (a comment and a derived check; `VA_red.log`); green: the four titles green and "CUDA-requiring validation scripts run in the gate's CUDA arm" 208/208 over nineteen scripts in 596 s (`VA_green.log`, `VAcuda_green.log`); scripts at
reduced size on the integrated tree: the counter-RNG validation (N = 2e5), the crab-noise `noise` (16384 turns, 273 checks) and `report` parts, the tune calibration (200 trials), the slicing convergence (500 particles, N_s reference 61) and the kick fingerprint exit 0; the effectiveness script with the device hidden and the GPU-require flag exits 1 and the extreme benchmark refuses the CPU override, both as designed (`VA_scripts.log`, 01:08 to 01:16).

## 2 Integration

Merged `--no-ff` into `fix4b-batch-int` in the order CT (d4f36b8), TR (df91080), SS (9b3f26d), TW
(e58bc2b), TS (216fa55), VA (e108f32); every merge clean (`git merge-tree` previews
of TS against TW and against the integrated tree found no conflict). The red worktree `fix4b-red` stayed
detached at 5907916 and received only each unit's test tree for its red run. Integrator changes on the
merged tree: one commit, 053364c, for two leads the units reported outside their files: three suite comments said "the 57-row table" where unit TW's Layer 3 row made it 58 and every consumer derives the count (now "the full slug table"), and the crab-noise theory note said the campaign's plan is kept with the record as `plan.md`, where the plan stayed in the untracked `result/` tree by the owner's 2026-09-15 rule (F-209/U40-10). The gate helper `result/gates/turnmod/run_sweeps.jl` was adapted to unit TS's layout of the stage 6 pin region (it extracted the pin constant to the first `end`, which is now a registry-restore helper's).

## 3 Pre-gate checks and the gate

On 053364c (`pregate_b4bpre1.log`, `sweeps_wt_b4bpre1b.log`): `validate_element_metadata()` true with no errors, `validate_configuration_metadata()` true, `docs/registry_snapshot.md` identical, the removed symbols of batches 3 and 4b (`planned_records`, `_compute_moment`, `_patch_reference_length`, `_floor_children`, `_track_line_elementwise!`, `_flush_cuda_fused_segment!`, `cuda_track_lumped_rad_kernel!`) absent from `src/` except in the comments that record their retirement; the extracted sweeps green: the stage 6 pin tripwire (3 pin lines) 2/2, the `Core.Box` allowlist 5/5, the detached-docstring sweep 11/11.

The two-arm full gate b4b1 on 053364c, green at the first attempt: native arm (CUDA active) `full_gate_native_pty_b4b1.log` 01:22:46 to 03:10:36 (1 h 48 min under a machine load of 33), exit 0, 437 summaries, 0 Test Failed, 0 Error During Test, Broken 2 ("Misalignment maps", expected), no skip, no signal; CUDA-arm testset 208/208, 19 scripts exit 0 (unit VA's extreme benchmark newly among them), CUDA arm wall 649 s. AVX2 arm (`julia -C haswell`, OPENBLAS_CORETYPE=Haswell) `full_gate_avx2_pty_b4b1.log` 03:10:36 to 04:57:54 (1 h 47 min), exit 0, 437 summaries, 0 Test Failed, 0 Error During Test, Broken 2, CUDA-arm testset 208/208, CUDA arm wall 632 s. The record and the ledger edits are a markdown-only commit on top of the gated tree; the fast lane on the final tree is their gate: exit 0, 421 summaries, 0 Test Failed, 0 Error During Test, 17 LANE SKIP lines, no unindexed document (`fast_lane_wt_b4b1_final.log`, 04:58:57 to 05:46:39, 48 min under a load of 34), run on this commit's tree before this sentence was filled in.

## 4 Owner items and leads carried

- Unit J's row (the rounding classes) still waits on the owner's two decisions; the five Float32 class
  ids are its.
- `_REAL_CLASS_MULTIPLIER` (the Twiss row's owner item) is now backed by a measured window testset; the
  row cites it.
- Leads found by the units, not fixed here: `Policies.jl:1387` `_active_cuda_launch` hand-copies the
  `:auto` block rule (TR); the PIC family's `:pic_pair_schedule` receipt shapes differ across its sites
  (SS); F-49's `rng_id 1 ... already held by a bpm_observer consumer` warning in every effectiveness run
  (VA); `docs/theory/crab_cavity_noise_response.md:602` still says the plan is kept with the record as
  `plan.md` (VA); five sibling registry-restore sites in the suite are hand-listed (correct today; TS);
  `validation/twiss_madx_benchmark.jl`'s A1 dispersion rows lack the coasting precondition the contract
  now asserts (TW); the two undeclared enums of the strong beams (`slice_method`, `virtual_drift`) are
  pinned by name until their owner declares `alternatives` (CT).

## 5 Ledger

The Minor pointer row stays open for five ids, its state naming the 45 closed here and the five that wait
with the rounding-class row; its notes point at this record's section 4 for what each closed id left
behind. The campaign pointer row records batch 4b. The Twiss row's `_REAL_CLASS_MULTIPLIER` clause cites
the measured window testset. This record's index entry sits beside batch 4a's. `docs/experiences.md`
gains one lesson (section 6). The fixes themselves are the units' commits and the six merges; this
record and the ledger edits are the one markdown-only commit on top of the gated tree, covered by the
fast lane on the final tree (section 3).

## 6 Lessons recorded

**The suite pins documentation text: grep before the sweep, change pin and text together.** Batch 4a's
fast lane went red once, at a testset of batch 3b's unit H that pins two formula strings of the
conventions note: a sweep unit had corrected the symbol in exactly those strings (the kernel's field `b`,
not the curvature `h`), and the pin, written days earlier from the note's own text, still said `h`.
Fourteen suite sites read a document and `occursin` its sentences. A documentation change is therefore a
coupled change whenever a pin exists: grep the suite for every read of the file and for the strings you
touch, and change the pin and the text in one commit, as unit TR did here (D18). The static check that
found no second collision -- every pin re-evaluated against the edited tree -- is the five-line script a
sweep runs before its gate, not after.

## 7 Not verified

- `Pkg.test` in either lane is the gate's (section 3); every unit's targeted runs and the integrator's
  red and green runs went through the title runner, which cuts a testset out of suite order and supplies
  the suite-level helpers by anchor (a runner artefact; the full suite is the authority).
- The MPI launcher testsets and `test/nightly_suite.sh` were not run outside the gate.
- Unit CT: the F-110 device failure path and the F-113 circular-consumer tripwire are unit-tested; no
  tree case trips them end to end. Unit TS: its measurements were taken on the native arm (and the
  Haswell arm only for the two-arm multipliers it froze); the AVX2 gate arm is the second measurement.
  Unit VA: the lambda pair and `emit_xcode` carry no verdict (characterisation; a verdict needs the
  converged hours-long settings); the production sizes of its scripts were not run. Unit TR: the MAD-X
  `deltap` clause is qualified, not verified against MAD-X. Unit TW: non-finite-kappa reachability on a
  `:unique` result and the production-size validation twin were not exercised.
- The leads of section 4 are recorded, not fixed.
