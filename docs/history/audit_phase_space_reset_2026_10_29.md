# Phase-space reset: implementation and neighbour audit

## Scope and status

Campaign opened 2026-10-29 from `2fc721f` on `main`, at the owner's request:
draft and independently review a design, implement, validate, commit and push.
The [design](../design/phase_space_reset.md) was reviewed before implementation.
The final four-thread full gate passed with CUDA active at **23:59:52 EDT on
2026-10-29**: **449 testsets, 158918 passed assertions, zero failures or errors**.
Two pre-existing expected-broken checks remain. The result was collected and
this closing record finalized on 2026-10-30 after the interrupted conversation
resumed. The receipt and exclusions are below.

`PhaseSpaceResetSpec` captures six independent coordinate arrays on first
passage and restores them on later passages. `TrackingTask` owns the snapshot,
on the beam's CPU/CUDA backend or MPI local shard. Absolute turns, stochastic
stream identities and global particle IDs continue normally. A reset is a
non-symplectic task operation; scalar maps, optics, transformed/buried resets,
interior/multiple resets, action hooks and strong-strong tracking are refused.
A leading observer may precede the first tracking element.

Each trial starts from the same finite ensemble. Aperture deaths and unexpected
non-finite outcomes are finalized before restoration, including the final turn.
The latest execution retains bounded aggregate counts and the last trial;
optional artifact groups retain complete per-trial summaries and loss events.
Explicit clear rearms capture without rewinding turn/RNG state. Reference
epochs distinguish recaptures, including a fresh task continuing an old file.

This is a targeted feature/neighbour campaign, not a repository-wide audit.
Review covered reset state ownership, generic tracking entry points, CPU/CUDA
copy and liveness consumers, loss scratch, artifact continuation/failure,
noise/RNG continuity, metadata/contract integration and MPI collective order.
Existing accelerator physics and strong-strong numerics were exercised by the
suite, not rederived. Throughput optimization, restoring two strong-strong
beams, interior reset sections, and thread-safe simultaneous task execution
are outside scope. No performance improvement is claimed.

## Independent review coverage

| Unit | Source and depth | Evidence |
|---|---|---|
| U1 architecture | Element, metadata probes, wrappers and low-level guards; focused source and call-site review | [Unit report](audit_phase_space_reset_2026_10_29_unit_reports/U1_report.md), metadata/help, configuration effectiveness, backend script |
| U2 lifecycle/output | Loss ledger, artifact producer, failure cleanup and rollback; independent focused review | [Unit report](audit_phase_space_reset_2026_10_29_unit_reports/U2_report.md), failing refusal reproductions and corrected regressions |
| U3 validation | Independent fresh-copy oracle, all noise modes, MPI/global IDs, precision tolerances and output fixtures | [Unit report](audit_phase_space_reset_2026_10_29_unit_reports/U3_report.md), focused blocks, standalone driver and real MPI |
| Parent integration | Full implementation diff, admission/caches, ordinary path and all-six storage binding | Baseline hashes, shape negative control, source tripwires, final gate |

Julia execution was serialized between agents and parent. The ordinary-path
baseline ran before implementation. The full gate runs alone. Reports
separate executed evidence from inspection and unverified boundaries.

## Design review decisions

The reviewed implementation keeps mutable reference data outside specs and
compiled plans, so knob recompilation and split calls preserve the reference.
It requires `loss_report=true`: restoration must not erase unexplained deaths.
The initial reference must be finite, with the MPI verdict collectively agreed.
Each loss record is scratch for one trial; ordinary tasks retain cumulative
loss semantics. Artifact rows identify absolute turn, capture turn and epoch.
Root-only output errors are broadcast inside the policy; exceptional partial
finalization outside the policy performs no MPI collective and records
`completed=false, folded=false` without replacing the original exception.

Review rejected a growing in-memory summary vector. The final ledger holds
aggregate counters and one last-trial summary, independent of turn count.
Optional reset products flush per trial before scratch reuse; this is an
explicit `RunArtifact.capacity` exception. Consumer receipts record actual
capture/restore, shard/backend and `flush_mode`, `capacity_applies=false`.

## Confirmed findings and fixes

- **All-six storage shape:** an identity/`length(x)` check missed in-place resize
  of another coordinate array. Signatures now include every length and axis;
  all lengths are checked before finite-state counting or mutation. The
  permanent regression mutates a non-x array while keeping its identity.
- **CUDA liveness transfers:** the first implementation called ordinary
  `count_dead`, which copies six device arrays to host. The reset consumer now
  uses a reusable device Boolean mask and scalar reduction. A host-copy spy
  with the old count path as positive control verifies the reset path does
  not enter that consumer. Zero-loss ranks skip copying event slots but still
  join every MPI gather.
- **Reentrant failure cleanup:** a nested rejected call could finalize its
  outer trial. The reproduction was **13 passed, 8 failed**, including an
  outer call returning normally with zero completed trials. The entry guard
  now runs outside failure cleanup; the same reproduction passed **21/21**.
- **Wrong-beam refusal:** candidate compilation could replace the previous
  trial's loss record before rejecting ownership. The reproduction was
  **6 passed, 4 failed** (logged 1 became 0; unattributed 0 became 1).
  Pre-admission rollback restores the accepted record and owner; **10/10**
  passed afterward.
- **Changed aperture names:** artifact continuation accepted changed labels
  while retaining old attribution. The append-mode reproduction was
  **1 passed, 4 failed**. Reset tasks now match the current aperture catalogue;
  incompatible output is refused without disturbing prior diagnostics or
  turns. The reproduction passed **5/5**. Ordinary record reuse is unchanged.

- **Rejected window regenerated spectral noise:** after changing the global
  seed, an out-of-range turn refusal cleared the accepted runtime cache.
  The next valid call silently synthesized a new table. The reproduction
  failed **8/16** assertions across artifact and no-artifact cases: seed 1001
  became 2002 and digest `9bfa3854007880a2` became `6ec260c55254f052`.
  Rollback now restores the accepted runtime cache, while clearing plans;
  ordinary cache keys still detect real spec/knob changes. The same reproduction passed **16/16** after the fix (18.6 s).
  The permanent regression checks table identity, seed, digest and the consumer receipt.

Source review also checks the fixes' neighbours: reentrant clear, zero turns,
failed first capture, failed output and retry, finalizers after completed
trials, explicit replay/recapture, wrapped/kept-whole lines, both strong-strong
beams, no-reset record reuse and resolved noise-table lifetime.

## Numerical validation and tolerances

The oracle copies the original six coordinates independently for every
absolute turn and tracks the physical lattice without a reset. It checks
realized noise before comparing every particle coordinate, alive/dead mask,
loss identity and pre-kill coordinate. It includes no noise, asymmetric table,
white and pink phase noise, and per-particle radiation excitation. Negative
controls omit reset, alias the reference or repeat turn zero.

Restoration and same-backend oracle comparisons are exact. Cross-backend
Float64 comparisons use absolute and relative tolerances `1e-10`. Float32
uses `rtol=64eps(Float32)` and a separate absolute tolerance for each
coordinate, `64eps(Float32) * maximum(abs, reference_column)`. Particle IDs
and loss masks are exact. The standalone default run executed **24 cases** at
**25 particles and 8 trials**, on CPU/CUDA and both precisions. All
same-backend coordinate/loss comparisons were exact. Largest CPU/CUDA absolute
coordinate difference was `9.313225746154785e-10` (Float32); largest
coordinate-scaled gap was `1.697958052625493e-7` (Float32) and
`2.1430955106681009e-16` (Float64).

Real MPI runs used **1, 2 and 4 ranks**, 17 global particles, four trials split
1+3, and three cases per rank count: Float64 table with losses, Float32 table
with losses and Float64 radiation. **27/27** launcher assertions passed in
**3m13.7s**. Every rank-local result matched repeated fresh sharded tracking;
root also matched an independent undivided scalar/global-ID oracle exactly.
All ranks refused an initial non-finite coordinate placed on rank 0. This
checks an uneven partition, empty-loss ranks and stochastic global offsets.
It does not add CUDA-backed MPI policy support.

## Targeted checks

Environment: Julia **1.12.4**, four Julia threads, NVIDIA **RTX 4500 Ada
Generation**. CUDA was explicitly required in GPU runs.

| Check | Executed result |
|---|---|
| Metadata and help | 610/610 defaults; both element help forms; combined metadata/help/config probe 9/9 |
| Parameter effectiveness | 549 checked; zero ignored/skipped/broken; 35 unperturbable, 31 rejected, 32 carried, 10 weak, 66 undecided |
| Public configuration effectiveness | CPU/CUDA passed; workers 1/2/4 and CUDA launches 64/128/256/512, existing fused/PIC and initialization consumers |
| Unsupported strong-strong/wrapped calls | 24/24 CPU/CUDA and both strong-strong beam positions |
| Backend consistency | 35 instances; N=2000, two turns; reset capture/mutate/restore bitwise over all 12000 coordinates |
| Ordinary composed backend physics | maximum absolute difference `8.196568423990414e-17`, tolerance `1e-10` |
| Reentrant/wrong-beam/append-label regressions | 21/21, 10/10, 5/5 |
| Standalone reset consistency | 24/24 CPU/CUDA cases, default size, tolerances above |
| MPI reset seam | 27/27 launcher assertions; 9 case/rank-count combinations |

Final focused blocks passed **620 assertions**: independent oracle 278/278
(74.5 s), lifecycle/ownership/restoration/refusals 255/255 (17.6 s), output/replay/
recapture/failure 47/47 (28.4 s), refused reuse 40/40 (1.3 s). The existing source
tripwires passed: **Core.Box 5/5**, detached docstrings **11/11**. An explicit
shape negative control reinstated the old signature/prepare functions in a
scratch process: the fixed implementation refused the resized `py` before any
coordinate changed and retained next turn 1; the old implementation accepted,
changed coordinates and advanced to turn 2. The two control assertions passed.
The extracted permanent spectral regression passed **16/16**; the complete
focused reset coverage is therefore **636 assertions**. The final gate receipt
is recorded below. Initial fixture failures are not
hidden: the scratch drift expectation used a linearized expression against an
exact drift; the first aperture threshold made an intended survivor die after
the nominal z-dependent crab kick. Correcting those expectations did not
change physics or relax any implementation tolerance. The first final-output
fixture kept the reset buried in a composite line; it was corrected to use
flattened line structure, consistent with the reviewed refusal.

## Ordinary tracking baseline

The [reproducer](audit_phase_space_reset_2026_10_29_baseline.jl) tracks 257
particles for three turns through a table-modulated crab cavity, exact drift
and aperture without a reset. Each case reports 85 losses and `next_turn=3`.
All four after-implementation results match these pre-implementation
fingerprints exactly, including loss counts and next turns. SHA-256 of all six
final coordinate arrays:

| Precision/backend | SHA-256 |
|---|---|
| Float32 CPU | `5b05776ff0cc70dca8d59eb4519a16d9d0b26183651b5e817ed2e525d77e17af` |
| Float32 CUDA | `d20fa9493aa7717a0bbe0bd79a0527543c982dfed2b8afcc344a5708ab9bfb0e` |
| Float64 CPU | `fe1095d9bd8767f83fd51c0d96b48513349bdd1b8d176c19b260b545d0853dab` |
| Float64 CUDA | `122c828e15e44cfc95cf867d5fc983fb9edcace4318cca766a9d03b3086fc3c2` |

## Boundaries and unverified cases

Task calls must be serialized; the reentrant guard is not atomic admission
for simultaneous host threads. External reordering of coordinate contents is
outside snapshot ownership tracking. Arbitrary process failure during a
collective is not recovered. Generic MPI precision validation occurs before
policy activation, so asymmetric malformed precision on only one rank is an
unverified existing boundary; collective-safe finite-reference and storage
checks here do not certify every distributed input error. No hardware besides
the named GPU or new CUDA/MPI combination was tested. No throughput benchmark
or long-term diffusion/resonance study was performed.

## First full-gate attempt

The first full four-thread CUDA-active gate ran from 21:51 to 22:32 EDT on
2026-10-29, then stopped at an existing ordinary-tracking allocation limit:
**251 completed testsets, 121080 passed assertions, 2 failed, 0 errors and
2 expected broken**. All five reset testsets passed 636/636 within this run.
The failure is a performance regression, not a passing full gate: one-turn
tracking through the existing 40-cavity/eight-type fixture allocated
**867120 bytes** on the fast route and **689744 bytes** on the general route,
against the unchanged **400000-byte** limit on each. Diagnosis and the final
re-run are recorded below. No push was made from this failed gate.

[Attempt-one testsets](audit_phase_space_reset_2026_10_29_gate_attempt1.tsv)
and [script receipts](audit_phase_space_reset_2026_10_29_scripts_attempt1.tsv)
preserve the failed run separately from the final receipt.

Allocation profiling reproduced the failure with bounds checking enabled:
fast route 867120 B, general route 689616 B (the gate measured 689744 B).
`_has_phase_space_reset(entries)` alone allocated 189824 B; the generic
`_requires_tracking_task(elems)` predicate allocated zero on this fixture.
The public execute wrapper and its internal execution function allocated
identically. A sampled allocation profile attributed 725088 B in 156
allocations directly to the reset-entry scan. The correction therefore targets
that scan only, using the existing unrolled tuple walker, and extends the
unchanged per-walk allocation limits to both new predicates. The corrected allocation probe measured **107824 B** on the fast route,
**119936 B** on the general route and **0 B** for the reset-entry predicate.
The generic tuple trait remained **0 B**, and complete coordinate fingerprints
were identical before and after the correction. The allocation profile no
longer attributes any allocation to the reset-entry scan. Existing execution
limits remain 400000 B, with 256 B per-walk limits; no bound was relaxed.
The exact affected allocation sub-block passed **29/29** (23.7 s), the reset
lifecycle/refusal block passed **255/255** (34.4 s), and the unchanged Core.Box
sweep passed **5/5** (1.6 s). Empty, absent, last-position and wrapped reset
cases verify detection and refusal before mutation; both predicates now join
the per-walk cost checks. The independent U2 reviewer reread this minimal
change and reported no altered refusal semantics. The final gate follows.

The [allocation/profile reproducer](audit_phase_space_reset_2026_10_29_allocation_probe.jl)
is the exact source run before and after this fix. Run it with
`julia --project=. --threads=4 --check-bounds=yes` followed by that path. It
prints complete coordinate fingerprints, public/internal execution allocation,
per-predicate allocation and attributed allocation stacks, and asserts the
unchanged acceptance limits. The final four-thread CUDA-active gate restarted
at **22:41:58 EDT on 2026-10-29** after all targeted checks finished.

## Final gate receipt and closure

Command, full lane at four threads:

```bash
OCTOPUS_REQUIRE_GPU_CONTRACT=1 julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
```

The gate ran **22:41:58–23:59:52 EDT, 2026-10-29 (77m54s)** and exited **0**
with `Testing Octopus tests passed`. Julia 1.12.4 ran with CUDA active on the
NVIDIA RTX 4500 Ada Generation. The final result is **449 testsets, 158918
passed assertions, 0 failed, 0 errors, 2 expected broken**. The
[per-testset receipt](audit_phase_space_reset_2026_10_29_gate.tsv) records every
executed summary. The two expected-broken entries belong to `Misalignment
maps` and predate this campaign; they are not new passing checks.

The five reset testsets passed **636/636** inside this gate. The previously
failing task/turn-modulation block passed **123/123**, including the unchanged
allocation bounds and the added predicate checks. The real MPI seam passed
**1725/1725** (11m22.9s); distributed developer harnesses passed **13/13**
(2m31.7s). The existing source closure/docstring, metadata, configuration,
ordinary tracking and allocation checks all executed successfully.

All **28 recorded scripts** exited zero: eight examples/developer harnesses
and twenty scripts in the CUDA arm. Their
[individual receipts](audit_phase_space_reset_2026_10_29_scripts.tsv) include
the new reset driver (**103.4s**, required GPU, 17 particles, four trials,
both precisions), backend consistency (**138.0s**) and public configuration
effectiveness (**122.9s**). The suite itself runs its CUDA arm four scripts at
a time: measured wall time **448.3s**, individual times sum **1661.0s**. No
agent-owned Julia run overlapped the gate.

The only excluded scripts were the suite's existing opt-in profiling wrappers:

- `profiling/cuda_device_profile.jl`, the frozen production-point CUDA profiler.
- `profiling/profile_strong_strong_cuda.jl`, the CUDA profiler wrapper around
  the strong-strong harness.

No CUDA or MPI arm was skipped. This local gate does not claim a GitHub CI
result, another GPU model, or a new CUDA-backed MPI combination. The narrower
unverified cases above remain explicit. No benchmark threshold was relaxed.

At closure, SHA-256 checks of all **20 changed executable source/test/validation and registry
files** exactly matched the copies frozen at the final gate's start. Only
measurement receipts and closing documentation were finalized afterward.
`git diff --check` passed. The completed ledger item is archived here rather
than rewriting an existing frozen history record:

| item | state | closing evidence |
|---|---|---|
| Phase-space reset for noise-response trials | completed | Reviewed design, backend-local capture/restore, per-trial losses/output, CPU/CUDA independent oracle, real MPI 1/2/4-rank equivalence, targeted neighbour audit and full CUDA-active gate above. |
