# Comprehensive-audit fix batch (2026-10-19): the Major rows

**Status:** complete 2026-10-20: ten units merged, the two-arm full gate green
with CUDA active on the integrated tree (section 4); push pending the owner's
word (an addendum records the push and its CI run).

The 2026-10-18 comprehensive audit
([`comprehensive_audit_2026_10_18.md`](comprehensive_audit_2026_10_18.md))
recorded 244 findings and closed without a fix, as authorized. On 2026-10-19
the owner lifted the push hold on the audit record ("lift the push hold. Do
Housekeeping. Then do the next fix batch"), and this batch is that Phase 13 on
the audit's thirteen Major rows of `todo.md` (F-244, the gate's own segfault,
stays in the record's step-2 addendum; the Moderate and Minor rows stay open).
Ten units, P to Y, each a sub-agent proposing one commit on its own branch cut
from `main` at cb3c344 under a common brief (regression test first and shown
failing, blast radius grepped, neighbour audit, docs stating the old behaviour
updated, no suite run in a unit worktree); the integrator read every diff,
re-ran every unit's regression testset RED on the integration tree before the
merge and GREEN after it with the unit's neighbours, resolved the merges, joined
two units that met in one function, and ran the pre-gate checks and the gate.
Unit reports, probes and the integrator's logs:
`result/fix_batch_2026_10_19/{plan,units,probes,verify}/` (git-ignored scratch;
the numbers are quoted here; `verify/INTEGRATION.md` is the red/green table).

## 1 Owner decisions (2026-10-19)

1. **Scope.** The audit's Major rows as one batch, the owner's "next fix
   batch"; nothing else from the audit's ledger.
2. **Method.** Sub-agents propose, the integrator verifies (the beam-beam fix
   batch's rule, 2026-10-18), on the audit record's own numbers as the
   reproduction target.
3. **Push** only on the owner's word, after the gate.

## 2 Units and what landed

Each unit: branch and commit; what the audit measured and the unit reproduced
on cb3c344; what landed; the regression test with the integrator's red run
(the branch's test tree on the integration tree's source BEFORE the merge)
and green run (after); what the unit left unverified.

### Unit P: CUDA PIC launch geometry (F-1, F-2; siblings F-12, F-45, F-215)

`fix-cuda-pic-launch`, 2d6d584, 3 files (+496/-32). Reproduced: offset beams
through a `StrongStrongTask` at `field_threads=100` against 128 differed by
3.8e-2 (`px`), 0.22 (`py`), 0.42 (luminosity); `field_threads=1024` and a plain
`CUDALaunchConfig(threads=1024)` failed the default indexed-wavefront route with
"Block register count exceeds device limit" (68 registers, 896 threads at most
on the RTX 4500 Ada). Landed: `_cuda_pic_bounds_block_reduce` masks the live
lanes of each warp in both shuffle stages (`_cuda_pic_warp_lane_mask`,
`_cuda_pic_bounds_warp_reduce`; the shuffle is a separate helper because the
inline `ntuple` closure boxed two loop variables and failed device compilation
with "unsupported dynamic function invocation"), chosen over validating
`field_threads % 32 == 0` because it removes the precondition, keeps the public
1:1024 surface and every contract, and leaves warp-multiple results bitwise
(min/max are exact); the four indexed bounds launches go through
`_cuda_launch_capped!`, which gained `max_blocks` so the block scale-up stays
inside the partials' 64 slots (the partials are initialised to the neutral
element and the finalize reads every slot, so the scale-up loses nothing);
the 59 other raw launch sites stay raw, pinned by a new source-derived
tripwire that also checks, on a GPU, every pinned kernel's ceiling against the
count its site can hand it (a measured census: 27 routes, 151 compiled
kernels; the luminosity bounds kernel is the ONLY raw kernel with a ceiling
below 1024). Docs: `?CUDAPICLaunchConfig`, the `field_threads` schema meaning,
the cap docstring. Tests (integrator's red on a5c23ea, green on 10902fc):
"The wavefront bounds reduction is exact at every block size, warp multiple or
not" 26 pass / 36 fail (minima 0.0 where the host gives 4.99) then green;
"Offset beams see the same CUDA PIC kick at field_threads=100 and 128" 7/3
then green (all three within the 1e-10 pin, window [2.7e-13, 3.8e-3]); "A
field thread count the device accepts but the bounds kernel cannot run is
capped, not fatal" errored then green (the `:cuda_strong_strong_thread_cap`
receipt: requested 1024, resolved 896); "Every raw CUDA PIC launch site is
pinned and its kernel fits the device thread ceiling" 66/2 then green.
Neighbours green: CUDA PIC parity across every route, the kick-cap pin and
scan, the luminosity power-of-two guard, slice-moment geometry invariance, the
Core.Box sweep; `validate_configuration_metadata()` true,
`validate(PublicConfigurationEffectivenessContract())` passed. Not verified by
the unit: timing (registers of the four bounds kernels rose by 2 to 8); the
census and ceilings are this machine's (the tripwire re-measures elsewhere);
F-215 (the spectral kick kernels, raw at a fixed 256, 62 registers) is outside
the tripwire's file list, a one-line widening priced in the ledger.

### Unit Q: the `:standard` Green kernel under the slice-pair cache (F-3)

`fix-green-standard-cache`, 113682d, 3 files (+215/-3). Reproduced:
`green_type=:standard` with the default `green_cache=:slice_pair` diverged
CPU/CUDA by 7.8e-3 of the coordinate scale (per-pair luminosity 1.4e-4) and
between two CUDA runs by 1.0e-2 / 1.8e-3; GaussianPIC with `:standard` 9.2e-3;
`:integrated` and `:lattice` agree to 1e-13. Mechanism: `_pic_align_grid_origins`
chose between the two half-cell separations by the SIGN of the fractional
separation, and the cache's 1.25x expansion maps a `(k + 1/2)`-cell separation
to an integer whenever `k = 2 (mod 5)`, exactly on that tie, where the device's
FMA-fused slice bounds and the host's twice-rounded ones (18373 of 100000
drifted coordinates differ) fall on opposite sides. Landed: a tie band
`_PIC_ALIGN_TIE_TOLERANCE = 1e-6` cells (the inputs' rounding noise is below
1e-10 cells, the smallest non-tie residual at the default growth 0.2 cells;
both bounds pinned) resolved by rule toward the larger separation; outside the
band the arithmetic is the old one bit for bit (199999 of 199999 random
non-tie inputs), so no `:integrated` or `:lattice` grid moved. Rejected:
`fma` on the host (keeps the knife edge for atomic-order and rank-count noise,
moves every CPU result) and reconstructing the exact lattice through the growth
factor (an arity change blind to the pre-expansion call's tie). After the fix:
5.8e-14 between the backends, 1.3e-14 between two CUDA runs, identical cache
histories; GaussianPIC 5.8e-14; controls unchanged. The brief asked for a
bitwise CUDA run-to-run pin; the controls themselves are not bitwise
(1.4e-13 to 2.1e-13, the deposit's float atomics), so the pin holds
`:standard` to the controls' measured class at 1e-11, 1e8 below the defect.
Theory note `pic_free_space_kernels.md` section 3.5 gained the dated
correction. Test "PIC :standard alignment tie is resolved by rule, not by
rounding noise": red on 10902fc 43 pass / 17 fail / 1 error (the tie residual
1.0 against 1e-9, the separation -0.5 against +0.5), green on 4617a4a with
CUDA; neighbours green (the expansion-alignment invariant, equal source and
field extent, CUDA PIC parity, GaussianPIC's cache honouring and coupled
subtraction, `:lattice`, grid extent and quantize);
`validation/strong_strong_pic_cache_backend_consistency.jl` passed (2.6e-15).
Not verified: MPI legs with `:standard`; other growth values; Float32 through
`:standard` + cache. Observation for the owner: neither PIC backend contract
can express `green_type` (a `green_type` field is the natural extension);
`:standard` with `grid_quantize > 0` now resolves its tie to `n + 1/2` by rule
where it resolved to `n ± 1/2` by the floor of snapped integers, a one-cell
placement change for some pairs of that non-default option, identical on both
backends (4.7e-14 before and after).

### Unit R: strong-strong line binding (F-4)

`fix-strong-strong-binding`, 58950c5, 10 files (+729/-69). Reproduced: a
`ThinRFCavity` in a strong-strong line tracked `ds_turn = NaN` where the same
line through a `TrackingTask` gives 100.0 (one turn differs in `z` and `pz`
only; the cavity-free control bitwise); the two-E0 lattice the TrackingTask
refuses was accepted; an aperture killed with no record, no count, no
`/losses`; `loss_summary(rep, task)` was a `MethodError`; the collision's
refusal blamed "the beam particles". Landed: ONE binder,
`_bind_line_entries(entries, elements, record)` in `Tasks.jl`, called by
`_runtime_entries` (TrackingTask) and by `_split_strong_strong_line`
(StrongStrongTask), which now compiles the line flat, binds it, then cuts at
the collision markers; each strong-strong line is surveyed against ITS OWN arc
length (a `StrongStrongCollision` is not an element spec, so the one arc
walker steps over it at zero length). `StrongStrongTask` holds one loss record
per beam through the shared `_ensure_loss_record!` core, `loss_record(task,
which)`, `loss_summary(beam, task[, which])` (the beam identified by its
storage; the unindexed `loss_record(task)` refuses by name), `/losses/beam_<i>`
artifact groups equal field for field to the TrackingTask's for the same beam
(the success path folded across ranks, the crash path unfolded with no
collective), a directed non-finite refusal naming the aperture, the beam, the
count and the remedy, a per-beam `:strong_strong_line_binding` receipt and a
`binding` entry of `configuration_report`; the harmon refusal names both task
kinds (one static string literal, device IR exercised by the testset's CUDA
arm). Five docs updated. The brief's premise that the TrackingTask records a
survey-binding receipt did not hold (no `_record_execution!` site carries the
survey); the TrackingTask's receipts are unchanged and the binder returns the
tuple a later unit could record. Test "Strong-strong lines bind the survey, the
apertures and the reference chain as a TrackingTask line does": red on 4617a4a
4 pass / 3 fail / 2 error (`NaN == 100.0`, the z twin, the harmon `k`), green
on 4b028e6 (82 s, CUDA arm included); 37 targeted testsets green in the unit,
re-run by the integrator for the loss, walker, collision and cavity families.
Not verified: more than one MPI rank for the strong-strong loss fold and crash
write; apertures inside kept-whole lines or wrappers within a strong-strong
line; knob-dependent strong-strong lines with apertures; Float32 strong-strong
beams with apertures. For the owner: aperture-free strong-strong runs stay
reduction-free and silent; a `loss_report`-style option for the strong-strong
task is a new public option and was not added.

### Unit S: the artifact's prepare order and `/losses` replay (F-56, F-58, F-57)

`fix-artifact-prepare-replay`, 4624468, 7 files (+877/-127). Reproduced: four
by-name refusals of `prepare_run_artifact!` under `append=true` fired after the
replay truncation (100 rows and cursor 99 became 50 and 49); probe groups were
truncated one bind at a time (a refused window 2 left `m1` at 5 rows and `m2`
at 10); a continued window written by a NEW task deleted `/losses` and rewrote
it from an empty record (window 3: 0 rows, `aperture_counts = [0]`). Landed:
`prepare_run_artifact!` runs every refusal from one derived table
(`_RA_PREPARE_CHECKS`: is-artifact, labels, ledger, ledger columns, partial
slots, a new `/losses` aperture-set check, turn-modulation provenance) before
writing anything; probe binds only validate (`PendingProbeBind`); a new
`commit_run_artifact!`, called by both task kinds after the last pre-turn
refusal, applies the replay rule to every channel and probe at once and gates
every row push (`push_luminosity!`, `_ra_push_probe_rows!` refuse before the
commit; a bind after it is refused); `_ra_write_losses!` merges under the
replay rule (`_ra_retained_loss_rows`: the earlier windows' rows below the
window's first turn and not already in this cumulative record are kept ahead
of this record's; `aperture_counts` follows the rows; the `summary_*`
attributes are the writing `execute!`'s beam) and skips an uncommitted window.
The design note gained "The window protocol: validation before mutation" and
"`/losses` under the replay rule"; `docs/public_api.md` one paragraph. Test
"Run artifact replay: the prepare validates before it mutates, probe binds
commit together, /losses follows the replay rule across a restart" (78
assertions; one byte-identity fixture per table entry, derived from the
table): red on 4b028e6 with the commit stubbed as a no-op 21 pass / 25 fail /
1 error, green on 82fa8cd; 24 neighbour testsets, the sweeps,
`validate_configuration_metadata()`, the effectiveness contract and a reduced
`pic_option_consistency.jl` green in the unit. Not verified: MPI (the gather
stays the first statement every rank reaches; the merge runs on rank 0); the
production-size validation arms; the per-`execute!` cost of the commit (the
same HDF5 calls, moved).

### Unit T: the observer row order and the cursor rule (F-73, F-84, F-74, F-59, F-63)

`fix-observer-row-cursor`, 3a57a6a, 5 files (+613/-47). Reproduced: after an
injected chunk-2 crash the moment table's turn column read `[0,1,2,3,4,5,
<garbage>]` with cursor 0 and the retry (owed 0:7) left `[0,4,5,6,7]`; a torn
tail of two HDF5 fill rows survived a continuation (`[0,1,2,3,4,5,0,0,6,7]`);
20 rows on disk with cursor 9 read back as 20; a group whose cursor attribute
was absent was truncated to 0 rows. Landed: the per-group cursor is a PAIR
stamped together (`_ra_stamp_cursor!`): `rows_valid`, the row index the writer
owns and the protocol keys on, and `rows_valid_through_turn`, its public
meaning; the append-open truncates to `rows_valid` first, then applies the
replay rule to the blessed prefix (`_ra_truncate_group!`, `_ra_truncate_probe!`);
every reader (`TaskOutput` of every kind and `:all`, the table of contents with
the new `rows_on_disk`, `MomentOutput`, `:record_count`) returns the blessed
rows only; a missing cursor, a cursor ahead of the extent, and a pre-2026-10-19
group with rows are refused by name under `append=true` (compatibility rule:
refusal with the remedy, the 2026-10-16 precedent; reading such a file stays
possible with a warning); `_ra_set_attr!` rewrites same-type scalars in place so
the cursor never passes through an absent state (an in-place write CONVERTS to
the stored type, measured: 2.5 over an Int64 attribute read back as 2, so a
type change still takes the delete-and-create route); `observe!(::MomentObserver)`
refuses, records, computes the row, then commits it. Test "The run artifact's
row cursor: a mid-row exception leaves no garbage row, a fill-row torn tail is
truncated, readers apply the cursor, a missing cursor is refused" (the failure
injected through a test-local coordinate array whose `collect` throws while
armed, through the public task loop, no method redefined): red on 82fa8cd
19 pass / 34 fail / 7 error, green on ee94158; 18 neighbour testsets green in
the unit; the audit's probes re-run give `0:7` and 6 valid rows;
`validate(PublicConfigurationEffectivenessContract())` passed. Not verified:
MPI at more than one rank; a real kill-induced torn tail (simulated by growing
the extent); archived pre-2026-10-19 files (the compatibility refusal was
exercised on a hand-edited file).

### Unit U: the zero-voltage survey-bound cavity (F-91)

`fix-rf-zero-voltage-slip`, ac81fff, 5 files (+219/-31). Reproduced on the
F16 two-cavity ring: strengths `(S, 0)` and `(0, S)` gave `nu_s / nu_s(eta_full)`
of 1.633 and 1.309 (the `(S/2, S/2)` control 0.9996), exactly the slip
fractions 0.3 and 0.7 the dead cavity owned; the one-turn `z` advance of a
`delta = 1e-3` particle read -0.02 (both dead), -0.01578, -0.01015 against the
full-eta -0.005932. Landed: in `_rf_kick` the survey z-shift `ds_turn g(delta)`
precedes the `iszero(strength)` return (which still precedes the harmon NaN
refusal), so a survey-bound cavity at zero voltage is its slip shift alone and
a bare one stays exactly the identity; `_cross_backend_rounding(::ThinRFCavity)`
at zero strength reads the survey (thin surveyed `----u-` bound 8, thick
surveyed bound 16; measured 2.0 and 3.0 ulps of z's scale at 2.5 GeV, 400
particles, 3 turns, RTX 4500 Ada; bitwise at 275 GeV); F-98 fixed while there
(the `L` ParamMeta no longer says "no velocity-slip term"); theory notes
`arc_survey_and_velocity_slip.md` section 8 and `rf_cavity_and_reference_energy.md`,
and the `twiss_benchmark_cells.jl` docstring, state the rule. The crab cavity
does not share the shape (no survey, no early return); `_acc_kick` unchanged by
design. Tests in four existing testsets (integrator's red on 5885ce2, green on
19165fb): "RF cavity closes the longitudinal plane" 36/2, "RF velocity slip
closes the full slip factor (F16)" 35/5 (`(S, 0)`, `(0, S)`, `(S/2, S/2)` all at
0.99958 of the full-eta tune after the fix, tolerance `rtol = 5e-3`; the
one-turn advance within `atol = 1e-13`), "CUDA surveyed cavity matches CPU
within its derived rounding class" 12/1, "Cross-backend rounding classes
declared per kind and checked by measurement ..." 187/3 (class `------` where
`----u-` is declared) then all green; neighbours green (the RF wrap, cavity
chain, accelerating cavity, two Dispersion-routes sets);
`validation/tracking_backend_consistency.jl` exit 0 (re-run by the integrator on
the final tree: 34 instances within their classes); `validate_element_metadata()`
passed; both `element_help` forms carry the new text; the snapshot regenerates
unchanged. Not verified: the dead-cavity path in a strong-strong line (unit R
binds the survey there; the shared kernel is the same) and a `TurnModulated`
strength realising exactly zero, reasoned about; Float32 through the reordered
branch. Observation: the LIVE surveyed cavity's declared bound 8 re-measured at
3.0 ulps (2.5 GeV, `ds_turn = 100 m`), a 2.7x rather than 4x margin, left
unchanged.

### Unit V: the Float32 loss record (F-117)

`fix-float32-loss-record`, b1dbe49, 2 files (+122/-17). Reproduced: a Float32
beam with an artifact, after the second `execute!`: record reused `false`,
counts `[1]`, summary (dead, logged, unattributed) `(2, 1, 1)` with the "no
aperture responsible" warning, `/losses` one row; both controls (Float64 with
artifact, Float32 without) `(2, 2, 0)`. Landed: the slot eltype rule lives in
one function `_loss_slot_eltype(rep) = promote_type(eltype(rep.x), Float64)`
read by the allocator and the matcher alike (the U15-11 rationale, the Float32
turn number past 2^24, moved into its docstring); the backend-change
reallocation is untouched. Test "A Float32 beam with an artifact reuses its
loss record across execute! calls": red on cb3c344 20 pass / 8 fail (every
failure the defect's; the CUDA Float32 arm included), green on 5885ce2 28/28
with the CUDA arm executed; neighbours green (the loss-record family, the
walker tripwire, the per-particle output, the turn-modulation CPU/CUDA identity).
No kernel line changed; no doc outside the docstrings stated the old rule.

### Unit W: the cluster mode index (F-192, F-176, F-177)

`fix-cluster-mode-index`, ed152a4, 4 files (+290/-70). Reproduced: the j-th
recovered mode of a resolved `m = 2` cluster was tagged `half[j]`, the other
member in 26 of 26 clusters under `resolution_chord = Inf` and 16 of 16 under
an explicit partition, so `analyze(clusters=..., longitudinal_mode=1)` returned
`tau_s = 1.490349` (expected 1.997501) and index 2 the reverse; the projector
route averaged a resolved cluster's two traces and reported a garbage graph as
`:not_invariant` with `degradations` silent; the selection text quoted the
wrong mode's z-area. Landed: `_recover_modes` tags each recovered mode with the
canonical index of its OWN eigenvalue (the half member nearest the oriented
eigenvalue under `_pair_gap`, one-to-one through the new `_nearest_assignment`,
which the indefinite branch's existing pairing now shares; certified when the
distance is below half the cluster's internal gap, guaranteed by construction
under any finite chord, a documented convention at exact degeneracy under
`Inf`); `_dispersion_routes` builds the projector route's traces per resolved
mode (`_eigenvalue_trace`), keeps the common-trace rule for unresolved clusters
only, hands the route the selected mode's (N5) projector inside a resolved
multi-member cluster (`reference_projector`), and the (D17) trace-cubic
diagnostic reads the per-mode traces too (a neighbour defect found in the
unit's own audit: residual 0.507 on resolved partitions); the heuristic text
quotes `weights[labels.longitudinal]`. Tests: `m = 2` index pins beside the
`m = 1` pin's testset ("Mode clusters: resolution_chord = Inf forces the exact
FODO, explicit partition": red on e8048ff 40/8, the match distance 0.388
against the half-gap 0.194) and a new stage-4b testset on the public path
("Resolved multi-member clusters (fix batch 2026-10-19 W): ...": red 11 pass /
26 fail / 3 error), both green on a5c23ea; the three analysis contracts
`:passed` on the merged tree (identity 57 identities / 160 runs, worst 0.132;
external 692 rows, worst 0.357; effectiveness 19 probes / 32 receipts; re-run
by the integrator); 91 Twiss-family testsets through the stage runner in the
unit (107,976 assertions, 0 failed); `validation/twiss_dispersion_identities.jl`
TSV bitwise identical before and after (it exits 1 at the recorded A-1 row as
before). Not verified: the acceptance-windows and external benchmark scripts
(singleton fixtures, argued unchanged); a resolved multiplicity-three cluster
under `Inf` through `analyze`. No CUDA-reachable code touched.

### Unit X: three dead scripts (A-4, F-200, F-236; F-201 in part)

`fix-dead-scripts`, 498d69b, 6 files (+341/-101, no `src/` change).
Reproduced: `validation/moment_observer_backend_consistency.jl` and
`validation/coherent_beam_beam_modes.jl` died on the retired
`MomentObserver(path)` constructor (2026-08-18), `profiling/benchmark_strong_strong_pic.jl`
on the retired `luminosity_path` keyword, and its eleven CUDA "configurations"
set environment switches no runtime code reads (four distinct runs under eleven
names); the blast-radius grep found a fourth user, `profiling/cuda_device_profile.jl`.
Landed: the three scripts on the artifact interface (`MomentObserver(; name,
orders)` views with `RunArtifact(path; ...)` on the task, the readers of
`docs/public_api.md`), run to completion: the moment-observer check on CUDA
(100k particles, 28 columns, max relative difference 1.67e-13 against
`rtol 5e-12`, exit 0; the integrator's own run reproduces the same numbers),
the coherent-modes study at 1024 turns and 20k per beam (soft-Gaussian Lambda
1.098 / 1.082, PIC 1.196 / 1.196, GaussianPIC 1.196 / 1.196, sigma drift at
most 5.2e-5, exit 0; the integrator ran it at 64 turns / 2000 / gaussian, exit
0), the PIC benchmark with its configurations made REAL through the solver's
own `cuda_*` keywords (an unknown field is a keyword error, never a silently
identical run), the two rows with no runtime counterpart dropped, a derived
`solver_default` row added, the phase profile through
`StrongStrongDiagnostics(pic_timing=true)`, a header with the fixed point and
provenance paragraph and a load-time check of its `OCTOPUS_BENCH_*` list (full
documented-default run exit 0, 14 rows, 4 min 24 s; the formerly identical
sequential rows now differ by 30 to 34 % in time); `cuda_device_profile.jl`
ported in its output construction only (the drifted-fork finding stays
priced). Tripwire "No committed script constructs a retired observer or task
spelling": 77 scripts of `validation/`, `profiling/`, `examples/`,
`test/examples/` scanned for every retired spelling, each row's probe run live
(it must still throw "retired"), every `"the ... was/were retired"` literal in
`src/` required to be covered; red on the unported tree 40/1 naming the four
scripts and seven spellings, green after. `validation/README.md` entries
updated. Not verified: the 8192-turn / 100k coherent-modes headline; the
benchmark's timings are a run receipt on a shared GPU, not a performance
record. Flagged for the owner: the benchmark's pre-existing verdict compares
slice-pair-cache rows against a `:none`-cache CPU reference, so `solver_default`
reads 1.76e-4 "inconsistent" on both backends identically (the cache's
discretisation, unchanged); the rest of F-201 and the class fix (CUDA
validation scripts in the gate's CUDA arm) stay priced.

### Unit Y: the MPI seam child's arms (F-222, F-223)

`fix-mpi-seam-arms`, 8c605a7, 4 files (+146/-49). Reproduced: the unfixed
child at one rank exits 0 printing `action=false` while its 3c fixture
`BeamSwapAction(identity)` throws `MethodError: no method matching
length(::TrackingContext)` and its 4b fixture throws the artifact-view
`ArgumentError` (the integrator's own one-rank runs from the integration
tree). Landed: `refusal_direction(f, token)` fails the child BY NAME on any
exception that is not the expected refusal, routed through by all five arms
(the two action arms and the three siblings carrying the same inline fold);
both action fixtures really run at one rank (a zero-argument counting swap
provider, the line-action task without observers) and each arm asserts and
prints the provider's call count (`MPI-TRACKREFUSE action=... action_calls=...`
new for 3c, `MPI-SSREFUSE ... action_calls=...` for 4b: 1 at one rank, 0
above), the parent asserting both directions; F-223: the five run artifacts
land in a per-launch directory every rank names alike (the parent's receipt
directory, else rank 0's `mktempdir()` broadcast) through one
`_mpi_check_artifact_path(dir, step)`; the one-suite paragraph of
`development_workflow.md` updated. Verification: the fixed child exit 0 at
`-n 1` (`action=false action_calls=1`, both arms) and `-n 2` (`action=true
action_calls=0`), by the unit and again by the integrator; the parent testset
"The multi-process seam runs under an MPI launcher" run by the unit through
the stage runner, alone on the machine (precondition logged), 1712/1712 in
10 min 55 s with the CUDA leg active; the gate runs it again. Not verified:
`-n 4` by hand; two whole suites at once (three concurrent children were
measured instead); the remaining F-223 sub-items (the nightly script's
stale-lock reclaim, the swallowing logger, the migration counts).

## 3 Integration

Merge order into `fix-batch-int` (from cb3c344): V (5885ce2), U (19165fb), X
(aefc114), Y (e8048ff), W (a5c23ea), P (10902fc), Q (4617a4a), R (4b028e6),
S (82fa8cd), T (ee94158), then the integrator's commit 705c37d. Every unit's
regression testset was run RED on the integration tree before its merge (the
branch's test tree over the then-current source) and GREEN after it together
with the unit's neighbours; the table with every count is
`result/fix_batch_2026_10_19/verify/INTEGRATION.md`.

Conflicts and joins:

- **R on U** (`src/elements/rf_cavity.jl`): U moved the zero-voltage return and
  the harmon refusal below the survey z-shift, R reworded the refusal to name
  both task kinds. Kept U's order with R's wording, one static string literal.
- **S on R** (`src/tasks/RunArtifact.jl`, three regions; the design note). S's
  replay merge and committed-window guard met R's per-beam `/losses/beam_<i>`
  groups in `_ra_write_losses!`. Joined: the write keeps S's guard and merge
  and reads the earlier rows from the group R's layout selects
  (`_ra_existing_losses_group`: `/losses` for a one-beam writer, `/losses/beam_<i>`
  for beam `i`), writing into `_ra_losses_group!`; the prepare's aperture
  check accepts a per-beam NamedTuple and refuses the other task kind's layout
  by name; the strong-strong prepare passes its two beams' aperture names. The
  join has its own test, block (3d) of unit R's testset: a continued file
  written by a NEW `StrongStrongTask` keeps window 1's `/losses/beam_1` rows and
  appends window 2's (turns `[0, 0, 1, 1]`, counts `[4]`, the writing beam's
  `logged = 2`), and a task whose beam-1 line names another aperture is refused
  at the prepare naming `/losses/beam_1` and the aperture, the file left as
  found.
- **T on S and R** (`test/runtests.jl`, the design note): both sides inserted at
  one anchor; both kept, HEAD first. The resolution left unit R's testset
  without its closing `end` (git had taken the shared trailing `end` as
  context); a `Meta.parseall` check that looked only for `:error` heads missed
  the `:incomplete` one, the stage runner's title cut did not (a `ParseError` at
  0.0 s), and the integrator's commit closes it. `RunArtifact.jl` auto-merged:
  S's `commit_run_artifact!` and `_ra_commit_probe!` call T's row-cursor
  truncations with the same signatures, as both units' integration notes
  predicted.

Runner artefacts, not defects: testsets that reference suite-level helpers
(`FailAtTurnAction`, `LedgerPeekObserver`, `_forwarding_track_ops`,
`FinalizeFlagObserver`, `ForwardDiff`) error under the stage runner until a
preamble supplies them; every such testset was re-run green with the units'
extended preambles, and the gate runs the suite as one process.

The batch's neighbour audit: each unit's own (sections 5 of the unit reports),
the integrator's green runs of the neighbouring families after every merge
(loss record, aperture, walker, RF and cavity, artifact and observer, Twiss
routes, CUDA PIC), the repo-wide `src/` grep of every symbol whose arity or
launch site changed (`_bind_survey` returns a pair, `_ensure_loss_record!`'s
shared core, `_append_strong_strong_line!`, `_recover_modes`, the masked
shuffle helper, `prepare_run_artifact!`'s keyword, the truncation functions:
no stale call form left), and the pre-gate checks of section 4.

## 4 Pre-gate checks and the gate

On 705c37d, before the gate: the suite's extracted source sweeps (the stage-6
pin tripwire, the Core.Box sweep, the detached-docstring sweep) green;
`validate_element_metadata()` passed, `validate_configuration_metadata()` true,
the registry snapshot regenerates byte-identical, both `element_help` forms
carry unit U's text; `validation/tracking_backend_consistency.jl` exit 0 (34
instances within their declared classes on CPU/CPU and CPU/GPU, CUDA active);
the three analysis contracts passed (section 2, unit W).

**The first native arm (705c37d, 23:13 to 23:51) was RED**, and the red was
the batch's own tripwire doing its job: "Every raw CUDA PIC launch site is
pinned and its kernel fits the device thread ceiling" failed 75/1 on
`_cuda_gaussian_build_moments_kernel!`, ceiling 896 against the 1024 its raw
`:device` site can hand it. Every targeted run had passed that testset, and the
probe explained why (`verify/probe_gaussian_build_moments_*.log`): in a plain
process the kernel compiles to 56 (uncoupled) and 64 (coupled) registers and
launches 1024 threads; under `--check-bounds=yes`, which is what `Pkg.test`
runs the test process with, `@inbounds` is void and it compiles to 66 and 76
registers (ceilings 896 and 768), and `CUDALaunchConfig(threads=1024)` fails
the raw launch with "Block register count exceeds device limit" on the unfixed
tree, uncoupled and coupled alike. The launch now goes through
`_cuda_launch_capped!` (the kernel is grid-strided with no per-block output),
the pinned row leaves the table, and the tripwire's comment states what its
device half measures: the kernels as the test process compiles them, the
stricter ceiling, which is the right side to be on. Integrator commit
8ba4384; the tripwire and the cap testset green under `--check-bounds=yes`
through the stage runner, the P family green without it, the sweeps green. The
AVX2 arm that had started automatically on 705c37d was stopped (it tested a tree
that changed).

**The second two-arm gate (8ba4384), both arms sequential in the integration
worktree, one suite at a time on the machine, under a pseudo-terminal with core
dumps enabled, four threads, CUDA active:**

- native arm (`result/gates/turnmod/full_gate_native_pty_fixbatch2.log`):
  2026-10-20 00:08:48 to 01:09:16, exit 0, "Testing Octopus tests passed", 362
  testset summaries, no failing or broken row, no `LANE SKIP` line (the full
  lane), the MPI seam testset included, no signal and no core. The thread cap
  announced itself four times, the F-2 route among them (`1024` to `896` for
  the luminosity bounds kernel).
- AVX2 arm (`OPENBLAS_CORETYPE=Haswell`, `julia -C haswell`,
  `full_gate_avx2_pty_fixbatch2.log`): 01:09:16 to 02:11:34, exit 0, "Testing Octopus tests passed", 362 testset
  summaries, no failing or broken row, no `LANE SKIP` line, no signal and no
  core.

The F-244 segfault did not occur in either arm of either attempt (three native
arms and one AVX2 arm ran on this batch's trees: attempt 1's native arm to its
red at testset 213, attempt 2's two arms to the end).

This record and the ledger changes of section 5 are a markdown-only commit on
top of the gated tree; the fast lane on the final tree is their gate:
GREEN (`result/gates/turnmod/fast_lane_wt_fixbatch_final.log`, 2026-10-20
02:12:56 to 02:40:44, exit 0, 347 testset summaries, 16 `LANE SKIP` lines, no
unindexed document), run on this commit's tree before this sentence was filled
in.

## 5 Ledger

Thirteen rows retired to `todo_ledger_archive.md` ("Rows retired by the
comprehensive-audit fix batch, closed 2026-10-20") with their closing
measurements: the CUDA bounds reduction, the legal `threads=1024`, the
`:standard` cache divergence, the strong-strong binding, the refused
continuation, the empty `/losses` on restart, the garbage observer row, the
value-keyed cursor, the zero-voltage cavity, the Float32 loss record, the
cluster index, the three dead scripts, the MPI seam arms. The pointer row
"Comprehensive audit 2026-10-18: the fix campaign (Phase 13)" records the batch.
Rows opened or widened: none new; the observations above (a `green_type` field
for the PIC backend contracts, a strong-strong `loss_report` option, F-215's
one-line tripwire widening, the benchmark's verdict reference) are noted in the
pointer row for the owner. Lessons in `experiences.md` (section 6 of this
record names them). This record is indexed in `docs/README.md`.

## 6 Lessons recorded

- Two fixes that are each green alone can leave a seam between them; when two
  units touch one function, the join needs its own test (R + S, block 3d).
- A same-anchor merge can take a shared closing `end` as context; a parse
  check must look for `:incomplete` as well as `:error`, and a cut by title is
  a structural tripwire of its own.
- A tie decided by the sign of a rounding residual is decided by the backend;
  resolve it by rule inside a measured band (unit Q, after fix I's fusion rule).
- Validate before you mutate: every refusal of a continuation runs before the
  first write, from one derived table (unit S).
- The suite compiles kernels under `--check-bounds=yes`, a stricter register
  ceiling than a plain process measures; a device property the suite asserts
  must be measured inside the suite (the gate's finding on the Gaussian
  build-moments launch).

## 7 Not verified

Collected from the units (their sections 7) and the integrator: multi-rank MPI
runs of the strong-strong loss fold, the artifact's replay merge and the row
cursor (the writer structure is unchanged; rank 0 holds the file; the seam
testset at 1, 2 and 4 ranks is the gate's); a real kill-induced torn tail;
archived pre-2026-10-19 artifacts; Float32 through the reordered cavity branch,
the `:standard` tie and strong-strong apertures; the CUDA launch census on
another device (the tripwire re-measures); the production-size validation
arms and the 8192-turn coherent-modes headline; the benchmark's timings as a
performance record.

## Addendum 2026-10-22 (push and CI)

The batch was pushed as b9c1253 on 2026-10-20 (23 commits over cb3c344); CI run 466 completed green. Recorded by the fix batch 3 commit, as the status line above promised.
