# U36: test/runtests.jl 25668-28979 -- lost-particle masking, apertures and loss records, solenoid and patch maps, PIC/spectral/GaussianPIC option effectiveness, batch_mode receipts

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683 (read-only). Julia 1.12.4, 4 threads, one RTX 4500 Ada
(`Octopus.CUDA.functional() == true`). Every claim below is a LEAD, not a finding.

## Region

`test/runtests.jl` lines 25668-28979 (3312 lines, 50 `@testset`s), from "Non-finite coordinates fail fast at
solver chokepoints" through "batch_mode is one keyword: PIC, Gaussian-PIC and spectral read it on CPU".
Groups: lost-particle masking (25668-26368, including four CUDA twins), apertures and loss records
(26370-26623), turn modulation CPU/CUDA (26625-26819), curvature/patch/solenoid maps (26821-27282),
TrackingTask loss record (27284-27355), PIC/GaussianPIC/spectral physics and options (27357-28321), the one
lane-gated CUDA GaussianPIC testset (28323-28371), coupled subtraction, Dirichlet box, luminosity schedules,
synchro-beam maps (28373-28776), batch_mode receipts (28778-28978).

## Provenance

READ line by line: `test/runtests.jl` 25668-28979 in twelve contiguous chunks (25668-25950, 25951-26230,
26231-26510, 26511-26800, 26801-27080, 27081-27360, 27361-27640, 27641-27920, 27921-28200, 28201-28480,
28481-28760, 28761-28979). Context read to judge leads (outside the region): `test/runtests.jl` 1-60
(`_lane_gate`, CUDA gating policy), 25398-25412 (`test_beam`), 25474-25496 (`nonfinite_test_rep`,
`expect_nonfinite_error`), 17980-17995 (the suite's solver-set tripwire); `src/tasks/strongstrong/interface.jl`
2925-2940 and 3005-3100 (the artifact gate and the luminosity-schedule memo); `src/tasks/strongstrong/spectral.jl`
548-585 (the clip tripwire); `src/beam/Beam.jl` 9-22 and 745-880 (`_HAS_CUDA`, the masked and unmasked
reductions); `src/elements/patch.jl` 100-200; `src/elements/ref_tilt.jl` 150-215; `src/tasks/BeamObservers.jl`
46-66 (schedule structs); `src/track/Track.jl` 20-32 (`TrackingContext` default turn 0); greps for
`should_run(`, `clipped`, `at least one live particle`, `positions`, `_concrete_octopus_subtypes`. Reference
documents: `docs/design/testing_lanes.md` section 3; `docs/comprehensive_audit.md` Phase 9; the lead headers of
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U19_report.md` and `U20_report.md` (none of the
leads below duplicates one of theirs; U19-2/3/5/6/8/9/10 and U20-3 are already closed in the region's comments).

EXECUTED (scripts and logs under `result/comprehensive_audit_2026_10_18/probes/U36/`):

- `probe1.jl` -> `probe1.log`: (B) the clip-warning instrument captured 8 "clipped charge" warnings at
  kbb = 1e-4, 0 at 1e-5 and 1e-6; (C) concrete `AbstractPoissonSolver` subtypes = registry solvers =
  {GaussianPIC, Gaussian, PIC, Spectral}, nothing missing from the hand lists; (D) `beam_statistics`
  masked vs survivors: mean differs by 1.02e-20 (scale 1.76e-5), covariance by 5.17e-26 (largest entry
  4.97e-5, ulp 6.78e-21), emittance and fourth moments by exactly 0.0 -- NOT bitwise identical;
  (D2) `longitudinal_slices` masked vs survivors: 0.0 difference in center, boundary and weight for all five
  methods, `:specified` populations [142, 57, 55, 143]; (E) field-derivative calibration errs[:second] =
  2.718e-3, errs[:fourth] = 1.680e-3, ratio 0.618; (F) receipt keys per family: PIC and GaussianPIC carry
  `pair_workers`/`inner_workers`, the spectral receipt does not; (G) 20,000 fresh `AtTurns` objects produced
  101 distinct `objectid`s (19,899 reused), no collision with one specific dropped id in 3e5 allocations.
- `probe2.jl` -> `probe2.log`: function-scoped stale-hit attempts, 2e6 allocations each (AtTurns and a
  PredicateSchedule over a Ref): no collision with the dropped id; a pairwise (correct) reassociation of the
  var(z) sum differs from the sequential one by 1.355e-20 (2 ulp) and the fourth moment by 8.27e-25 (1 ulp).
- `probe3.jl` -> `probe3.log`: the margins behind the inequality pins (numbers in Clean), the patch-roll vs
  tilt exact equality (0.0) and its control (2.04e-4), and the tilt wrapper type (`MisalignedElement`).

Not executed: the suite's own testsets (no stage-runner runs), and no CUDA testset was re-run; the GPU-only
assertions are reported as read.

## Leads

### LEAD U36-1 [Minor, confidence high] test/runtests.jl:25834
Claim: The covariance and fourth-moment pins in "Lost particles are excluded from every reduction" (`atol=1e-24`
at 25834 and `atol=1e-30` at 25836) are below the ulp of the quantities they bound, so they are bitwise pins
between two routes that are not structurally identical -- they pass today by rounding, not by structure.
Mechanism: `isapprox` with a positive `atol` sets `rtol = 0`, so `atol=1e-24` on a covariance whose largest entry
is 4.97e-5 (ulp 6.78e-21) and `atol=1e-30` on a fourth moment of 3.73e-9 (ulp 8.27e-25) can only be met by
exact agreement. The two routes are different arithmetic: the unmasked `_mean(v) = sum(v)/length(v)` and
`_covariance` = `sum(f, zip(a,b))` use Base's pairwise/SIMD-capable reductions (`src/beam/Beam.jl` 754-760),
while the masked route is a sequential conditional loop (766-790). The means already differ by 3 ulp (measured
1.02e-20); the covariance agrees to 5.17e-26 only because the mean perturbation cancels to second order and
both covariance loops happen to associate identically at n = 200. A correct reassociation of the same sum moves
var(z) by 1.355e-20, 13,500x the pin, and the fourth moment by 8.27e-25, 8e5x the pin: any future `@simd`,
threaded or pairwise change to either reduction fails this test on correct code, while the physics-level claim
the comment states ("must equal the same statistics computed on a beam that simply does not contain the dead
particles") would be carried by a tolerance at a few ulp (e.g. `rtol=1e-13`). Hypothesis 3.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U36/probe1.jl` section D prints
`mean diff 1.0164e-20 ... bitwise identical: false` (covariance diff 5.17e-26 against atol 1e-24, ulp 6.78e-21);
`probe2.jl` prints `|beam_statistics - pairwise| = 1.3553e-20 (pin atol 1e-24, ulp 6.78e-21)` for var(z) and
`|diff| = 8.27e-25 (pin atol 1e-30)` for the fourth moment.

### LEAD U36-2 [Moderate, confidence low] test/runtests.jl:25714 (seam: src/tasks/strongstrong/interface.jl:3023-3072)
Claim: Out of hypothesis and cross-file: the one-slot luminosity-schedule memo the testset at 25714-25767
exercises is keyed by `objectid(schedule)` of a collectable object with no invalidation, so a schedule object
collected and replaced by another whose storage reuses the address returns the PREVIOUS schedule's verdict at the
same turn -- a stale takeover (defect class 7); two testsets in this region run exactly that pattern at turn 0.
Mechanism: `_LUM_SCHEDULE_MEMO` holds `(objectid(schedule), turn, verdict)`; `AtTurns` and `PredicateSchedule`
are immutable wrappers whose `objectid` is derived from a mutable field (`Set`, closure capture), i.e. an address.
At 28505 `AtTurns([7])` is consulted at turn 0 (verdict false), the solver that owns it becomes garbage, then at
28517 a fresh `AtTurns([0])` is consulted at turn 0; the same shape at 28574/28584 and at 25699. If the new Set
lands at the old one's address the memo returns `false`, `collide!` returns NaN and `lum_run == lum_every` fails
-- a flake the suite cannot distinguish from a solver defect, and in a user script a silently missing luminosity
row. Measured: address reuse is the norm (19,899 of 20,000 fresh `AtTurns` reused an earlier id across GC
cycles), but the targeted collision with one specific dropped id was NOT reproduced in 2 x 2e6 attempts
(probe2), so the trigger probability in practice is unknown; the mechanism is from reading the code. This is a
seam for the auditor: the fix (key on the schedule object itself, or clear the memo per collide/turn) is in
`src/`, outside this unit's region.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U36/probe1.jl` section G prints
`20000 fresh objects -> distinct ids 101, ids seen before 19899`; `probe2.jl` prints `no collision in 2e6
allocations` for both demos. A deterministic reproduction would construct two schedules with equal `objectid`
and different `should_run` answers (e.g. by `unsafe_pointer_to_objref` reuse) and consult both at one turn
through `Octopus._luminosity_schedule_evaluated`.

### LEAD U36-3 [Minor, confidence high] test/runtests.jl:25738
Claim: The testsets that claim "EVERY solver" enumerate the strong-strong solvers by hand (25738-25747,
25870-25896, 26467-26475, 28874-28881) with no local tripwire deriving the list from the registry, so a fifth
solver would silently fall outside the per-solver properties (schedule memo, corpse immunity, aperture
transparency, batch_mode receipts) while the suite stays green.
Mechanism: AGENTS.md forbids hand-copied solver enumerations without a coverage tripwire. The only derivation
in the suite is at test/runtests.jl:17989, which compares `_concrete_octopus_subtypes(AbstractPoissonSolver)` to
another hand-written four-element `Set`; updating that one line when a solver is added satisfies it without
touching any of the four lists here. Measured today: 4 of 4 concrete solvers covered, so this is drift risk,
not present loss. Hypothesis 3 (derived-vs-copied case lists).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U36/probe1.jl` section C prints
the concrete subtypes and `missing from hand lists: Set{Any}()`; `grep -n 'EVERY solver\|every solver'
test/runtests.jl` finds the claims, and none of the four testsets references `_concrete_octopus_subtypes` or
`build_registry().solvers` (the only registry reference in the region, 27558, is a membership check).

### LEAD U36-4 [Minor, confidence high] test/runtests.jl:28909
Claim: In "batch_mode is one keyword...", the assertions that `:wavefront` at one worker reports
`pair_workers == 1` and `inner_workers == 1` sit behind `if haskey(wf1[4][1], :pair_workers)` and are silently
skipped for the spectral family, whose receipt carries neither key; nothing records the omission or declares
the exemption.
Mechanism: A body behind a condition that is false for one of the three families (hypothesis 1). The spectral
`:spectral_pair_schedule` receipt has keys `(:batch_mode, :requested, :pairs, :batches, :widest_batch, :ranks,
:exchange, :schedule)` -- measured -- so the two `@test`s never execute for it, and if the PIC receipt ever lost
the key the whole block would vanish for every family with the testset still green. The suite's own convention
for a deliberately unexercised check is a visible marker (`@test ... skip=` at 26531) or an assertion that the
exemption is intended (e.g. `@test haskey(...) == (label !== :spectral)`).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U36/probe1.jl` section F prints
`spectral k=1: ... has pair_workers=false` and `pic k=1: ... has pair_workers=true`.

### LEAD U36-5 [Minor, confidence high] test/runtests.jl:28933
Claim: The sequential-vs-batched worker-split assertions (`pair_workers > 1`, `inner_workers == 1`) are behind
`if nthr > 1` with no skip marker, so a single-threaded run passes the testset while its concurrency claim
("the sequential loop really threaded its inner maps while the batched loop pinned them to one") is never
checked and the omission is invisible in the summary.
Mechanism: Same class as U36-4 (hypothesis 1); the neighbouring loss-record testset handles the identical
situation visibly with `@test Threads.nthreads(:default) > 1 skip = (Threads.nthreads(:default) == 1)` at 26531.
CI runs four threads, so this is a by-hand-run hazard, not a CI gap.
Repro: `julia --project=. -t 1 -e 'using Pkg; Pkg.test(julia_args=["-t","1"])'` reports the testset
"batch_mode is one keyword: PIC, Gaussian-PIC and spectral read it on CPU" with two fewer assertions than at
`-t 4` and no skip row; `grep -n 'if nthr > 1' test/runtests.jl` locates the gate.

### LEAD U36-6 [Minor, confidence med] test/runtests.jl:25756
Claim: The four-solver "gate == own" assertion in "Non-finite coordinates fail fast at solver chokepoints"
compares one function with itself: for every solver the file-writing gate
`_strong_strong_luminosity_evaluated(solver, ctx)` forwards to exactly the consult the test names as the
solver's "own" (`_pic_compute_luminosity`, `_spectral_compute_luminosity`,
`_luminosity_schedule_evaluated`), so the disagreement property the comment describes is established by
construction and the assertion can fail only if the memo is removed -- which `calls[] == 4` already catches.
Mechanism: `interface.jl` 3084-3088 and `gaussian_pic.jl` 198-201, `spectral.jl` 330-331 define the gate as a
one-line forward to the solver's consult. The test therefore never observes the consumer boundary (a
`collide!`/`execute!` with a stateful schedule asserting that the artifact rows are exactly the turns the solver
evaluated); the only consumer-boundary schedule test in the region, 28524-28543, uses the stateless
`EveryNSteps`, so a regression that re-introduced a direct `should_run` call at the gate (2934) or in a solver
loop would pass 25756 and be caught nowhere in this region. Today `grep -n 'should_run(' src/tasks/strongstrong/`
shows one call site (3058), so there is no present defect -- this is a test that cannot fail on the defect it
documents (hypothesis 2; Phase 9 negative-control rule).
Repro: `grep -n '_strong_strong_luminosity_evaluated(solver::' src/tasks/strongstrong/*.jl` shows each method
body is the function the test calls as `own`; deleting the memo lines in `_luminosity_schedule_evaluated` is the
only change that turns 25756 red, and 25765 (`calls[] == 4`) turns red with it.

## Clean

- CUDA gating is visible (hypothesis 1): 9 `_HAS_CUDA && CUDA.functional()` gates in the region, 9 matching
  `else @test_skip "CUDA device not available"`; the one lane-gated testset (28323) uses `_lane_gate`, which
  prints `LANE SKIP` and records the name (runtests.jl 23-28). The region's only other conditional bodies are
  the two reported above (U36-4, U36-5) and the host-side `if Octopus._HAS_CUDA` at 26662, whose testset still
  reports a skip through its sibling gate.
- The clip-warning instrument at 25926 is validated by a positive control: under the same
  `with_logger(SimpleLogger(buf, Warn))` capture, the Spectral arm at kbb = 1e-4 produced 8 "clipped charge"
  warnings (the `maxlog = 8` budget, which is per logger instance and therefore fresh for the capture), 0 at
  1e-5 and 0 at 1e-6 (the arm the test runs). Message text matches `spectral.jl:570` and
  `spectral_cuda.jl:327`. The corpse-variant luminosities were equal even in the clipped regime, confirming
  the U19-2 history the comment records.
- `expect_nonfinite_error` (25486-25496) asserts `ArgumentError` and the substring "non-finite" and fails loudly
  on a non-throwing body; the all-dead slicing message at 26086 matches `slicing.jl:71` and `pic_cuda.jl:5653`.
- `:specified` slicing positions are in units of sigma_z about the mean (`slicing.jl:509`), so
  `positions=[-0.6, 0.0, 0.6]` yields populations [142, 57, 55, 143]: the five-method sweep at 26043 is
  non-degenerate. Masked vs survivor slicings agree to exactly 0.0 in center, boundary and weight for all five
  methods, so the 1e-18 pin there (0.6 ulp of 9e-3) is structurally held (same sorted live z values).
- The patch-roll vs `tilt` exact equality (26917) measured 0.0 with its control at 2.04e-4; it rests on structure:
  both routes use `_misalign_matrix` (patch.jl:105-106, misalignment.jl:392), the pure-roll matrix has exact
  zeros in the s row and column, and `_patch_map` (patch.jl:150-166) then reduces to the same two-term products
  with exact-zero drift, excess and `sxy` terms. The tilt wrapper is `MisalignedElement`. The identity at 26946
  is the definition itself and acts as a mapping tripwire, not independent evidence; the independent patch pins
  are the inverse compositions, the z-invariance sweep and the `convention=:madx` product-of-angles check.
- Inequality pins are well inside their windows, and every number the comments quote was reproduced
  (probe3): err_h = 0.01606 (< 0.03) and err_h/err_p = 0.846 (< 0.95); spectral kick residuals 0.0216/0.0271
  (`:grid`) and 0.0218/0.0169 (`:grid_free`) against 0.05; Strang ratios 16.46/16.03/16.06 (multipole),
  15.91/16.00/16.06 (curved), 15.76/15.98/16.00 (curved=true at h=0) within (12, 20); flat(128) = 3.19e-8
  (< 1e-7), flat(8)/flat(32) = 15.76 (> 8); dev ratio 10.001 (10 +- 10%); ierr(512) = 2.00e-9 (< 1e-8); e4/e5 =
  10.004 (k1) and 10.019 (k0s) in (8, 12); ks -> 0 vs curved quadrupole 1.087e-8 (< 5e-8) and 6.794e-10 (< 3e-9),
  matching the comment's 1.09e-8 and 6.79e-10.
- The field-derivative calibration (27822-27855) is a sane instrument: errs[:second] = 2.72e-3, errs[:fourth] =
  1.68e-3 (median pointwise relative field error 0.29% and 0.18%), ratio 0.618 against the 0.75 bound and the
  comment's "~1.6x". Note only: no absolute bound on errs[:second] is asserted, so the claim is relative.
- Lost-particle charge semantics (25935-26029) use the discriminating ratio with measured residuals
  (0.899934 and 0.899981 against 0.9, 1.000000 for spectral) and a separation control; the pins are an order
  inside their rtol.
- Receipt-based anti-vacuity is consistently present where the region claims an option reached its consumer:
  batch_mode receipts assert what RAN and the request (28819-28824, 28892-28900, 28952-28954, 28971-28973),
  the node-grid loop asserts its body ran (28042, 28062), the fused-moment chunk count (26353), the
  noise-moved-the-beam control (26715), the `isbits` before/after `cudaconvert` (26807-26808).
- Hand-copied solver lists are complete today: 4 of 4 concrete `AbstractPoissonSolver` subtypes appear in each
  (see U36-3 for the missing tripwire).
- No lead here duplicates a previous-audit lead: U19-2/3/5/6/8/9/10 and U20-3 are closed in the region's own
  comments with measured numbers, and the U20 lead list does not touch this region's content.

## Unchecked

- GPU-only assertions (the 1e-17 CPU/CUDA gaps at 26713/26759, the 1e-13 gathered-route parity at 26175,
  the device allocation tripwires at 26284/26289, the CUDA aperture and solenoid parities) were read, not
  re-measured; CUDA is active on this machine but the brief asks for short probes and these are the suite's
  own measurements.
- The Hirata synchro-beam formula at 28694-28697 (`expected_dpz`) was not checked against the theory note, so I
  cannot say whether it is independent of the implementation or copied from it.
- 27384-27385 pin `_pic_kbb1` relative to `_strong_strong_kbb1`; the absolute value of `_strong_strong_kbb1` is
  not pinned inside this region, and I did not look for its pin elsewhere.
- U36-2's stale takeover was not reproduced deterministically (2 x 2e6 allocations without the specific
  address being reused); the lead rests on the code's key choice plus the general reuse measurement.
- No testset was run through the stage runner; all execution was through the three probe scripts.
