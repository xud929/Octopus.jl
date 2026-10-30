# Persistent particle tunes: implementation and neighbour audit

Campaign closed 2026-10-30. The final four-thread CUDA-active full gate passed
459 testsets with 159667 passing assertions, zero failures, zero errors and
the two pre-existing expected-broken checks. The authorized commit and push
carry the design, implementation, independent reviews and measured evidence.

## Executive summary and repository

The owner requested fixed per-particle tunes in the existing `Linear6DSpec`,
with function, distribution and direct-array preparation, all named plane
subsets, and persistent CPU/CUDA/MPI storage. Work began from clean `main` at
`529d8e9ddea111ad4c1b95d7d1b43132d3d452ad`. The
[design](../design/particle_tunes.md) was drafted by one agent and reviewed
independently by the core and validation agents and the lead before source
implementation. The agreed runtime is `ParticleLinear6D`; no new element kind,
method or policy is introduced. Final independent design review found no
outstanding mismatch with the owner's agreement.

## Declared scope and coverage ledger

This is a targeted feature/neighbour audit, not a repository-wide review.

| Unit | Responsibility | Evidence |
|---|---|---|
| Lead | Task ownership, first-passage segment, cache/plan/reset/loss integration, CPU/CUDA admission, MPI agreement, final gates | Source inspection, focused execution and final gate below |
| [U1](audit_particle_tunes_2026_10_30_unit_reports/U1.md), core agent | Independent task/track/loss/MPI neighbour review | Six resolved leads; isolated negative controls and permanent regressions |
| [U2](audit_particle_tunes_2026_10_30_unit_reports/U2.md), design agent | Independent source/sampler/map review; metadata/contract integration; final agreement review | Variant, method, RNG and publication checks, including deliberate omission controls |
| [U3](audit_particle_tunes_2026_10_30_unit_reports/U3.md), validation agent | Independent dense oracle, physics, source protocols, lifecycle, backends and MPI | 684 feature assertions, 50 numerical cases, 36 backend comparisons, real MPI at 1/2/4 ranks |

Unchanged strong-strong solver internals, generic checkpoint/restart, full
noisy crab-cavity studies and arbitrary third-party distribution packages are
outside this campaign. Metropolis-Hastings production is external to this
feature; users can provide its resulting arrays or a distribution implementing
`rand(rng, distribution)`. The included histogram sampler draws directly from
bin masses and preserves declared joint correlations.

## Traceability and reviewed decisions

| Requirement | Implementation surface | Executed verification |
|---|---|---|
| Existing spec; distinct runtime | `linear6d.jl`, `particle_tunes.jl`, runtime-variant metadata | Eight unchanged ordinary numerical fingerprints; variant registry/help/precision checks |
| Any named subset and joint sources | Source canonicalization and `TuneFunction`/`TuneDistribution`/`TuneHistogram` | All seven subsets, joint correlations, invalid sources and deterministic RNG tests |
| Actual entrance, then fixed labels | `ParticleTuneSegment`, task-owned bindings | Upstream-map witness, callback counts, split continuation, reset and cache rebuilds |
| Backend-local labels | Adaptation plus admitted CPU/CUDA kernels | Residency, recorded thread/launch settings, one-time initialization receipts, MPI global IDs |
| Fixed-label canonical map | Shared entrance/exit normalization and cached rotations | Independent BigFloat reference, frozen-label Jacobian, actions and analytic phase mixing |
| Explicit rearming | `clear_particle_tunes!`, preparation epoch | Fresh draws only on deliberate clear; unaffected reset/noise/turn state |

The map is `A_out R(2πν_i) inv_A_in`; shared matrices preserve ordinary Twiss,
crab/momentum dispersion and coupling conventions. All seven nonempty named
subsets of `nux`, `nuy`, `nuz` work; omitted planes use the nominal phase advance
divided by `2π`. Labels are absolute signed tunes and survive continuation,
coordinate resets, optics-only cache rebuilds and later global seed changes.
They initialize on the first actual entrance, not at compilation. Clear is
explicit and changes only this preparation epoch once a binding existed.

## Baseline and targeted results

The [baseline reproducer](audit_particle_tunes_2026_10_30_baseline.jl) ran
before source edits and again after them on Julia 1.12.4, four threads, NVIDIA
RTX 4500 Ada. All eight SHA256 coordinate fingerprints match exactly: ordinary
crab/drift/aperture and asymmetric `Linear6D`, Float32/Float64, CPU/CUDA. The
ordinary loss count (85) and next-turn cursor (3) also match. The final existing
once-per-call walk tests passed 37 assertions, reset lifecycle passed 255 and
the `Core.Box` tripwire passed five. Detailed hashes, timings, allocations and
numerical cases are in the [measurement data](audit_particle_tunes_2026_10_30_measurements.json).

Final focused feature coverage totals **684 passing assertions in nine
feature testsets**: dense/reference/backend 113; source/entrance/error 173;
distributions 51; lifecycle 167; analytic physics 143; stream warnings 5;
removed-feature loss 5; atomic admission/clear 11; immutable-view ownership 16.
The existing reset refusal/reentrancy neighbour also passed 40 checks. These
counts combine the final successful focused runs; the full gate below reruns
the merged suite in one process.

Metadata validation passed 611 default comparisons and 34 runtime/method
representatives. Both `element_help` forms and configuration metadata ran.
The generated exported-API index passed 17 checks, including a deliberate
missing-name control. Targeted precision, rounding-class, RNG census and
method-probe negative controls passed; a declared extra runtime without a
symplecticity case is detected.

`PublicConfigurationEffectivenessContract` passed across CPU, fused CUDA and
CUDA PIC consumers. The tune-specific consumer probe exercised all seven
subsets and two stochastic stream IDs on CPU/CUDA (nine receipts each), with
maximum coordinate error `8.673617379884035e-19` against
`2.2737367544323206e-16`. Ignoring a non-default `nuy` or removing its receipt
fails the probe. `ElementParameterEffectivenessContract` passed with 551
checked parameters and zero kinds lacking a probe. Its existing limitations
remain explicit: 35 undecided (30 method declarations, two Symbol parameters,
three values not perturbable by the sweep), 31 with all candidates refused
(23 constructors, eight reset placement candidates), and ten weak movements
below `1e-12`. These are not verified effectiveness claims; U2 records the
exact counts and limitations.

## Findings and corrections

1. The RNG adapter initially lacked `rand(rng, UInt32)`. The first focused run
   passed 103 dense and 172 source checks, then stopped after seven distribution
   checks. Integer-width/Bool support and two-draw UInt128 handling were added;
   distribution coverage now passes 51 checks.
2. MPI admission could locally return before a peer entered collectives. It
   now agrees feature/state presence before branching, then observable source
   schema, placement, bound state, transforms, precision, stream and epoch.
   Initial stochastic binding also agrees captured seed and RNG method. Real
   1/2/4-rank runs passed six exact-source cases per rank, uneven/empty shards,
   single-rank source failure and eight mismatch refusals at multiple ranks.
   Opaque callback captures/distribution internals remain a caller obligation.
3. Clearing and disabling the feature left an empty manager whose ordinary
   fast path did not advance admission. A subsequent tracking failure restored
   an earlier beam's loss record. The regression failed with restored owner/
   record and count zero; the corrected path retains the current owner and
   records the actual aperture loss (count one).
4. Duplicate stochastic placements lacked the existing RNG stream warning.
   Warnings now identify shared `(rng_id, plane mask)` bands; disjoint masks do
   not warn. Five warning assertions pass.
5. A late Boolean guard admitted two concurrent calls. A forced mutable-vector
   barrier reproduced `accepted=2 refused=0`; a task-owned atomic guard before
   mutation gives `accepted=1 refused=1`. Both clear APIs share that guard,
   including the interval before manager preparation. Eleven permanent checks
   cover refusal, failed-clear isolation and valid subsequent execution.
6. Weak references to immutable coordinate wrappers could lose a temporary
   box while the beam still retained its storage. Standard `SubArray` views
   reproduced false ownership refusal for tune/reset state and loss-record
   replacement for ordinary/strong-strong tasks after GC. One shared helper
   keeps mutable arrays weak and retains immutable wrappers until clearing or
   replacement. All four owner consumers were audited; 16 regression checks
   and 40 existing reset checks passed. Parent retention is documented.
7. Metadata and contracts previously assumed one runtime per spec. Coverage
   now derives runtime variants, executes each representative's declared
   method, and checks the frozen-label symplectic map. The exported API index
   is derived from actual module exports and has an exact-name coverage test.

Three test assumptions were corrected without hiding their failed outcomes.
The first race fixture's immutable wrapper produced a false ownership refusal,
so it was replaced with a mutable wrapper before the race was counted as
reproduced. The view test expected reset trial counts to accumulate across
windows; the documented per-window count is one. The injected MPI defect did
not reliably hang: it also produced changed peers with impossible shard counts
or a fatal truncated `Allgather`. Its negative control now requires entry by
all four ranks and one of those specific collective-failure mechanisms; a
pre-entry compilation or generic launch failure does not qualify. U1 archives
both the original method and the isolated launcher.

## Numerical validation and tolerances

The [standalone driver](../../validation/particle_tunes_consistency.jl) passed
50 cases: Float32/Float64, CPU threads 1/2/4 and CUDA launches 64/256, combining
ten independent dense-map cases and forty phase/kick-response cases. The
maximum error/bound ratio is `0.011829078612328323`. Dense maximum absolute
errors are `3.46945e-18` (Float64) and `1.75038e-9` (Float32); the largest
Float32 response ratio is `0.00672204`, normalized action drift `1.76858e-6`
and phase error `2.38884e-6`. U3 records tolerance formulas and every case.
The mandatory tracking backend driver passed 36 comparisons, including all
six particle-tune coordinates bitwise equal across CPU/CUDA. This observation
is for the recorded hardware/configuration, not a universal bitwise promise.

The frozen-label symplecticity residual is `1.997467913017353e-12`, within its
`2e-11` case bound; the preparation callback ran once. Jacobian perturbations
hold tunes fixed. The standalone symplecticity script also passed all 28
declared cases and its zero-missing-kind coverage check. Its separate Hirata
quasi-symplectic checks passed (inverse residual `8.267041565201971e-19`,
determinant error `4.134470543704083e-13`).

The initial fixed-kick Float32 oracle used the nearly cancelling final output
coordinate to scale forward error. At turn 11, particle 1, `py`, CPU4 and CUDA
both gave absolute error `8.205081474857141e-10` against an old bound
`8.002899371996747e-11` (ratio 10.252636). The error carrier must include the
initial phase-plane amplitude and accumulated absolute kicks:
`0.0022659827540107563` in that case. Keeping the same `128*eps*turn` multiplier
gives bound `3.803376814898425e-7`. The old output-scaled diagnostic is retained;
independent action, phase, centroid and covariance checks are unchanged. This
was an oracle normalization correction, not a map correction.

## Performance report

Three tune arrays and six cached rotation arrays cost `9*N*sizeof(T)` per
placement, plus two shared normalization matrices. There is no per-particle
dense matrix, per-turn source sampling or per-turn trigonometry. The warmed
[allocation probe](audit_particle_tunes_2026_10_30_allocation_probe.jl) measured
Float64 initialization separately from 32 continuation turns:

| Policy | N | Initialization ms / host bytes | 32 turns ms / host bytes | Owned coefficient bytes |
|---|---:|---:|---:|---:|
| CPU, 4 threads | 128 | 0.883950 / 182816 | 1.136955 / 237216 | 9216 |
| CPU, 4 threads | 8192 | 1.976637 / 1537576 | 26.881573 / 237392 | 589824 |
| CUDA | 128 | 0.691638 / 183872 | 1.139286 / 170096 | 9216 |
| CUDA | 8192 | 1.274196 / 1538760 | 1.375703 / 171296 | 589824 |

These are bounded local measurements, not a speedup claim. The nearly constant
continuation host allocation across N is distinct from owned O(N) coefficient
storage. Initialization includes task/source preparation; the driver records
its actual policy and synchronizes CUDA.

## Gates and remaining limits

The fast checkpoint passed on 2026-10-30 at 19:04:20 UTC (37m26s wall):
**443 testsets, 157243 passes, zero failures, zero errors**. Its three `Broken`
results comprise two pre-existing expected-broken misalignment-convention
checks and one explicit fast-lane skip of the RF-cavity effectiveness contract.
Seventeen heavyweight testsets were excluded with visible lane banners; the
[complete fast receipts](audit_particle_tunes_2026_10_30_fast.tsv) and
[skip list](audit_particle_tunes_2026_10_30_fast_skips.txt) preserve them. All
nine particle-tune testsets passed together in this run (684 assertions).

The full four-thread CUDA-active gate ran **19:04:23–20:27:22 UTC** on
2026-10-30: **82m59s wall, exit 0, 459 testsets, 159667 passes, zero failures,
zero errors, two pre-existing expected-broken checks**. Command:

```bash
OCTOPUS_REQUIRE_GPU_CONTRACT=1 julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
```

The [full testset receipt](audit_particle_tunes_2026_10_30_gate.tsv) preserves
all counts and timings; the [script receipt](audit_particle_tunes_2026_10_30_scripts.tsv)
preserves all 29 successful subprocess runs (eight examples/developer harnesses
and 21 CUDA-arm drivers). The CUDA arm ran four drivers at a time in 501.0 s;
its surrounding testset took 502.1 s (8m22.1s). The drivers' individual times
sum to 1824.7 s. The new particle-tune driver passed in 59.5 s; the backend-consistency
and reset drivers also passed. The actual MPI seam passed 1735 assertions in
12m28.0s, with 1/2/4-rank coverage; the divided developer harnesses passed their
13 assertions. There were **no fast-lane exclusions and no unavailable-device
or unavailable-MPI skips** in this full run.

The two existing `Misalignment maps` expected-broken assertions concern
`QuadrupoleSpec` with zero placement and invalid `misalign_convention=:middle`
or string `"madx"`: the identity-placement return bypasses their intended
rejection. This campaign did not change them. Two opt-in profiler wrappers are
explicitly excluded from the CUDA arm: `profiling/cuda_device_profile.jl`
(the paper-production-point `CUDA.@profile` fork) and
`profiling/profile_strong_strong_cuda.jl` (the profiling wrapper around the
strong-strong harness). Their profiler behavior was not verified.

The supervisor checked the [192 executable/registry hashes](audit_particle_tunes_2026_10_30_source_hashes.json)
before launch; all 192 still matched after completion. Subsequent changes
only record receipts, close the work ledger and index the evidence. Full-log
SHA256: `80107f428a2358e6e67ec08298eeb298aff7131b2c8bb81c7257719374725be6`.
The registry snapshot and executable inputs are unchanged from the gated tree.

The first fast checkpoint stopped at architecture integrity with 48 passes
and one failure: eight archived audit scripts lacked direct links in
`docs/README.md` (their unit reports already linked them). The direct index
entries were added; no source or numerical acceptance changed. This failed
checkpoint did not reach the new feature testsets.

First-version boundaries: Float32/Float64; optics-form `Linear6DSpec`;
unwrapped/flattened `TrackingTask` placements; global direct arrays under MPI;
no arbitrary action hooks, kept-whole transformed body boundaries,
StrongStrongTask bindings, or contextless common-matrix/Twiss interpretation.
Failures are transactional at the new element boundary, not across preceding
elements or user callback side effects. No arbitrary third-party distribution
implementation or production crab-noise scientific campaign is claimed tested.
