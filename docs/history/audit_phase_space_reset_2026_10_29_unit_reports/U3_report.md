# Phase-space reset validation unit U3

> Parent closure: the final CUDA-active gate passed on 2026-10-29; see the
> [campaign receipt](../audit_phase_space_reset_2026_10_29.md#final-gate-receipt-and-closure).
> Pending-gate statements below describe this unit's earlier handoff.

Status: final focused CPU/CUDA and MPI probes passed; parent owns the full gate and the last spectral rollback regression run.
Owner: `/root/reset_design`.

## Scope

Owned the reviewed design note, independent one-turn oracle, new standalone
validation driver, new CPU/CUDA lifecycle and artifact testsets, real-MPI reset
cases and adaptations to existing precision/rounding/artifact-product coverage.
No claim is made to have run the final full suite; the parent owns that gate.

The design was reviewed independently by the architecture and trial-loss
implementation agents before implementation. Review changes incorporated:
one reset at the first tracking position; task-owned capture; unchanged noise
turns; finite initial reference; explicit clear; device-resident copies and
CUDA loss counting; per-trial loss revival; bounded in-memory aggregates;
artifact epochs unique across fresh task append; explicit partial-trial state;
per-trial artifact flush with capacity inactive; unsupported strong-strong,
placement transforms, action hooks, bare tracking and optics refused.

## Independent oracle

`test/phase_space_reset_probe.jl` builds a reset task and an ordinary task from
the same physical element objects. Each ordinary one-turn run receives an
explicit copy of the original coordinates at the matching absolute turn.
Neither the initial copies nor the expected snapshots use reset internals.
Recorded per-particle six-coordinate snapshots, actual realized noise and
aperture events are compared, including the last trial and continuation chunks.
The matrix uses no noise, a prescribed asymmetric table, white noise, pink
noise and per-particle radiation excitation. Negative controls evolve the
beam without reset and repeat turn-zero noise; both disagree with the oracle.

Same-backend output and restoration comparisons are exact and NaN-aware.
Cross-backend identity columns and finite/lost masks are exact. Float64 physics
uses atol=rtol=1e-10; Float32 uses rtol=64eps(Float32), with each coordinate's
atol equal to that factor times the reference column's maximum finite absolute
value. A deliberately injected 1e-6 x error is rejected. The standalone driver
prints all six measured relative coordinate-scale gaps and checks event IDs.

## Executed checkpoint

Command: `julia --project=. --threads=4 /tmp/octopus_reset_targeted3.jl`.
This scratch script extracted the committed-source test blocks from
`test/runtests.jl`; it activated CUDA when functional. Log:
`/tmp/octopus_reset_targeted3.log`.

| Testset | Pass / total | Time |
|---|---:|---:|
| Independent one-turn oracle on CPU and CUDA | 270 / 270 | 74.4 s |
| Lifecycle, ownership, exact restoration and refusals | 233 / 233 | 9.5 s |
| Trial output, replay, recapture and failures | 39 / 39 | 3.8 s |

This checkpoint exercised both coordinate precisions, CPU worker counts one
and four, actual CUDA copies, repeated losses and revival, replay, fresh-task
append epochs, failed observers/finalizers and a CUDA host-coordinate-copy
spy. The spy was shown active by making ordinary `count_dead` throw, then the
artifact-free reset execution passed without reaching it; the mask remained
the same device allocation across execution calls. The all-six shape guard
refused a resized non-x array before restoring a deliberately modified x.

The first fixture used an aperture narrower than the nominal crab kick, so
its intended no-loss final turn was not physically no-loss. All reference
comparisons passed; widening the fixture aperture and choosing the prescribed
second noisy phase corrected those expectations. The second checkpoint's
errors were stale assertions of a zero summary after clear (API now returns
nothing) and direct invocation after deleting a temporary spy method (Julia
world age); the third checkpoint corrected those fixtures. These were not
implementation defects and were not counted as successful checks.

## Integration coverage and pending work

Existing per-kind precision and rounding tests now give task-only reset an
actual capture/mutate/restore witness. The reset class is pinned bbbbbb and
the set of task-only kinds is checked against the registry. The artifact
product vocabulary is covered by the union of genuine permanent-loss and
reset producers, since those loss semantics intentionally use separate files.
Effectiveness ratchets use the measured 549 checked, 35 unperturbable, 31
rejected and 32 carried entries; the eight new rejected names derive from the
placement table. Declared-default coverage is raised from 599 to 610.

The final focused revisions and MPI/driver runs are recorded below. A fifth
permanent regression added for the loss reviewer's spectral-cache rollback
finding is extracted at `/tmp/octopus_reset_spectral_permanent.jl`; the parent
owns its red/green run and source fix. It uses a unique RNG stream ID, restores
the previous global RNG configuration in `finally`, and cleans its artifact
with `mktempdir`. Its 16 assertions are not counted in the 620 below.

## Final scientific driver and real MPI receipts

`OCTOPUS_REQUIRE_GPU_CONTRACT=1 julia --project=. --threads=4 validation/phase_space_reset_consistency.jl`
exited 0 with CUDA active, 25 particles and 8 trials (the script defaults).
It executed 24 cases: both policies, both precisions, all five noise kinds,
and a table-noise aperture-loss case per precision/policy. All same-backend
coordinates, initial-state restoration and loss events matched exactly.
All CPU/CUDA identity columns, finite/lost masks and realized noise matched
exactly. Each loss-enabled case produced 24 repeated aperture events.
Full log: `/tmp/octopus_reset_consistency.log`.

Measured CPU/CUDA largest absolute difference was
9.313225746154785e-10. The following table gives the maximum coordinate gap
divided by that coordinate's maximum finite reference absolute value (six
columns are printed separately by the reproducing driver):

| Precision | Noise | Losses | Maximum scaled coordinate gap |
|---|---|---|---:|
| Float64 | none | false | 2.143095510668101e-16 |
| Float64 | table | false | 1.503826906356311e-16 |
| Float64 | table | true | 1.385422105306519e-16 |
| Float64 | white | false | 1.646748057023119e-16 |
| Float64 | pink | false | 1.869476103429183e-16 |
| Float64 | radiation | false | 2.041671826585419e-16 |
| Float32 | none | false | 1.151259362616766e-07 |
| Float32 | table | false | 7.284604621892233e-08 |
| Float32 | table | true | 1.336697176334151e-07 |
| Float32 | white | false | 1.107797074618109e-07 |
| Float32 | pink | false | 1.697958052625493e-07 |
| Float32 | radiation | false | 9.444050470138998e-08 |

`julia --project=/tmp/jl_0ZPOdf --threads=4 /tmp/octopus_reset_mpi_driver.jl`
exited 0 with 27/27 assertions in 3m13.7s. The scratch child extracts the
permanent reset block from `test/mpi_seam_check.jl`; the project is the prior
Pkg.test environment carrying Octopus, MPI and MPICH_jll. One-, two- and
four-rank launches each ran table noise with losses in Float32 and Float64,
and per-particle radiation in Float64. N=17 gives uneven partitions at
multiple ranks; four trials were split into calls of one and three turns.
Every shard retained its own snapshot and the global particle interval;
completed counts were globally folded. Every rank rejected an initially
nonfinite coordinate present only on rank 0.

Besides the fresh-copy sharded oracle, root compiled the ordinary physical
line and evaluated each original particle independently with `fusedTrack`,
absolute-turn context, seed 0x50535220261029, Philox and the true global
particle ID, with index_offset=0. Every assembled MPI six-coordinate output
matched this undivided scalar oracle exactly in all nine launch/case pairs.
Thus MPI radiation validation does not rely only on two calls sharing the
same shard-offset implementation. Each launch printed its separate
`MPI-RESET-ORACLE nranks=P cases=3 scalar_exact=true OK` receipt and every
rank printed `MPI-RESET ... cases=3 finite_refused=true OK`.
Full log: `/tmp/octopus_reset_mpi.log`.

## Final focused testset receipts

`julia --project=. --threads=4 /tmp/octopus_reset_targeted4.jl` ran the
final CPU/CUDA oracle and lifecycle blocks successfully. Its artifact block
then exposed a fixture mistake: passing `BeamLine` inside a tuple intentionally
keeps it whole, which the reset correctly refuses; the test claimed to use a
flattened line. The fixture now uses the normal `TrackingTask(BeamLine(...))`
entry route, so its readonly observer and named reset become separate entries.
No production code changed for that correction. The affected artifact and
refused-reuse blocks were then extracted from the corrected source and run by
`julia --project=. --threads=4 /tmp/octopus_reset_targeted_tail.jl`, exit 0.

| Final testset | Pass / total | Time | Log |
|---|---:|---:|---|
| Independent one-turn oracle on CPU and CUDA | 278 / 278 | 74.5 s | `/tmp/octopus_reset_targeted4.log` |
| Lifecycle, ownership, exact restoration and refusals | 255 / 255 | 17.6 s | same |
| Trial output, replay, recapture and failures | 47 / 47 | 28.4 s | `/tmp/octopus_reset_targeted_tail.log` |
| Refused reuse preserves active and prior trials | 40 / 40 | 1.3 s | same |

Total: 620 passing assertions, with actual CUDA and no skipped arm. These
include the same-task renamed-aperture append refusal, unchanged prior loss
scratch and trial summaries after foreign-beam refusal, and caught recursive
execute/clear refusal without closing the outer artifact or marking a completed
trial partial. Direct and nested reset placement in either StrongStrongTask
beam is refused with both ensembles and the stored turn unchanged.

The existing effectiveness tests now partition constructor rejections from
the eight task-only placement compile rejections using the task-only trait and
placement table. The CUDA-inactive precision-test skip message derives the
kind count from the registry rather than retaining the former literal 31.
These existing-suite adaptations await the parent's full gate; they are not
included in the focused 620 assertion count.

No unsupported StrongStrong reset, arbitrary interior reset, transformed reset,
MPI+CUDA hybrid policy, multi-device CUDA transfer, or throughput benchmark is
claimed. All changed owned files passed `git diff --check`. The parent has the
final source-neighbour review, source checks, registry snapshot and full
four-thread CUDA-active suite obligation before pushing.
