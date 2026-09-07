# Neighbour audit — the multi-process campaign (2026-09-06)

The campaign's targeted neighbour audit, deferred by owner decision (2026-09-04)
until the last solver divided rather than run once per step. Step 4h closed
2026-09-06, so it fell due. Scope: `git diff 5dd9e22..HEAD -- src ext` — 26
files, ~8,300 insertions, campaign steps 1, 2, 3a-3c and 4a-4h plus the
`batch_mode`-one-keyword row.

Method: the twelve neighbour classes the `docs/todo.md` row names, swept
read-only in parallel (no Julia, no `mpiexec` — a recompiling probe during a
gate corrupts it, `docs/experiences.md`), each sweep returning leads with
`file:line`; every lead then put to three independent skeptics with distinct
lenses — does it reproduce from a real entry point, is it already handled
somewhere the finder did not read, is the claim about the arithmetic right —
each instructed to default to refuted. 31 leads, 25 survived, and every one was
then re-verified against the source by the auditor before it was recorded or
fixed. The 25 are rows, not distinct defects: several classes found the same
site independently (the Gaussian-PIC broadcast was raised by both the
lost-particle and the rank-local-flow sweeps, the aperture counts by both
lost-particle and `n`-vs-`n_local`), so they cover 18 distinct sites. ONE of
them did not survive re-verification and is recorded as a not-defect at the
end, together with one suggested FIX that was wrong even though its finding was
right — because a wrong turn that is visible is worth more than a clean story.

## Executive summary

Three major defects, all in the class the precedent predicts — the sibling that
did not get the fix:

- **Gaussian-PIC does not broadcast its luminosity-schedule verdict**, and that
  verdict gates point-to-point messages in the shared sliced transport. A
  rank-divergent `PredicateSchedule` deadlocks the collide. The three sibling
  solvers all broadcast, each with a comment saying why; gpic was the fourth
  copy of a hand-copied rule and the one never written.
- **The run artifact's `/losses/aperture_counts` is one rank's shard**, beside
  loss rows and summary attributes that are the whole beam's. The globalized
  attribution was already computed and handed to the writer, which ignored it.
- **`profiling/benchmark_collide_cpu.jl` refuses two of the four solvers under
  MPI**, with a message asserting they "still refuse to run divided". A
  hand-copied solver roster that went stale the day steps 4f and 4g landed.

Beyond those: a CUDA activation that skips the launcher tripwire, a launcher
fixture whose shard offset was resolved outside the policy scope (so the test
did not test what it claimed), the gpic bare collide missing the shard scope
its three siblings open, and eight pieces of prose that misdescribe live
behavior. All fixed here.

Two things are priced and ledgered rather than fixed, both on concurrency
surfaces where the fix is larger than the finding: the `:funneled` tripwire
tests a thread id rather than the task, and `_run_logical_workers`' pool-of-one
inline branch is exercised nowhere in the suite.

## Coverage ledger

"Leads" is what the sweep raised, "survived" what three skeptics each left
standing, "confirmed" what the auditor's own re-verification against source
kept. "Survived" and "confirmed" differ in exactly one row — class 8, explained
under "Corrections" below. Where "leads" exceeds "survived", the skeptics
refuted the difference.

| # | class | leads | survived | confirmed | outcome |
|---|---|---|---|---|---|
| 1 | every `_slice_transverse_moments` caller | 1 | 1 | 1 | fixed (prose) |
| 2 | every `muladd` in the tree | 1 | 0 | 0 | **clean** |
| 3 | the CPU/CUDA twins | 1 | 1 | 1 | fixed |
| 4 | every `_run_logical_workers` caller | 0 | 0 | 0 | **clean** |
| 5 | `n` vs `n_local` | 1 | 1 | 1 | fixed |
| 6 | collectives outside `_with_execution_policy` | 3 | 3 | 3 | fixed |
| 7 | the representation-keyed shard scope | 3 | 3 | 3 | fixed |
| 8 | backend-tagged receipt names | 1 | 1 | 0 | not a defect (below) |
| 9 | prose that misdescribes live behavior | 10 | 9 | 9 | fixed |
| 10 | "a lost particle is excluded, exactly" | 3 | 3 | 3 | fixed |
| 11 | rank-local control flow that hangs peers | 3 | 2 | 2 | fixed |
| 12 | the campaign's own pins and tripwires | 4 | 1 | 1 | fixed + ledgered |
| | **total** | **31** | **25** | **24** | |

Two clean results worth stating, because an area inspected and found sound is a
result:

- **`muladd`.** The complete set of `muladd`/`fma` sites in `src/` and `ext/`
  is five lines. The two that carry a bit-identity claim —
  `_shifted_second_moment` and `_shifted_cross_moment` (`slicing.jl:788-792`) —
  are pinned to `fma`, and every shifted-moment finalize in the tree
  (`slicing.jl`, `pic_cpu.jl`, `pic_cuda.jl`, `gaussian_pic.jl`,
  `gaussian_pic_cuda.jl` ×2) routes through them. The remaining three sit
  under no bit-identity comparison. The campaign's sharpest lesson has no
  outstanding exposure.
- **`_run_logical_workers`.** All 25 callers in `src/` were read and every one
  writes only its own indexed slot, so the one-thread inline path is the same
  writes in the same order. The property the inline path rests on holds per
  caller, not merely in the argument that introduced it. (What the inline path
  does NOT have is a test — see the ledger.)

## F1 — Gaussian-PIC's luminosity verdict is not broadcast (major, fixed)

`src/tasks/strongstrong/gaussian_pic.jl:985` read

```julia
compute_luminosity = _pic_compute_luminosity(pic, ctx)
```

Its three siblings do not:

| solver | site | form |
|---|---|---|
| PIC | `pic_cpu.jl:138` | `_mp_nranks() > 1 ? _mp_bcast(...) : ...` |
| spectral, 6D route | `spectral.jl:1591` | `divided ? _mp_bcast(...) : ...` |
| spectral, transverse route | `spectral.jl:1718` | `divided ? _mp_bcast(...) : ...` |
| **Gaussian-PIC** | **`gaussian_pic.jl:985`** | **no broadcast** |

The value is not advisory. Under a multi-process policy
`sliced = _mp_multi_process_active()` (`gaussian_pic.jl:1026`) is always true,
so the flag is handed straight into the shared slice-aligned transport, where
`pic_cpu_sliced.jl:1356` is

```julia
compute_luminosity || continue
```

immediately above the stage-3 `_mp_isend`/`_mp_irecv!` block and its
`_mp_wait_all(reqs, :wait_lum_extents)` at `:1378`; the dataflow loop's
equivalent is `pr.stage = compute_luminosity ? _PIC_DF_LUMEXT : _PIC_DF_DONE`
at `:1984`. A rank answering `false` while its pair coordinator answers `true`
skips sends the coordinator is already blocked on. The run stops, with no
error.

`luminosity_schedule` is live on this solver, not inert: `GaussianPICPoissonSolver`
forwards its kwargs to the embedded PIC solver (`gaussian_pic.jl:96`) and the
option is not in `_GPIC_INERT_PIC_OPTIONS` (`:150-153`). Nothing refuses a
`PredicateSchedule` luminosity schedule at more than one rank —
`_reject_unsharded_strong_strong_features` covers line actions and
predicate-scheduled line OBSERVERS, not solver schedules — and
`_solver_divides(::GaussianPICPoissonSolver)` is `true`, so
`_reject_undivided_solver` does not intercept it either.

Fixed by mirroring the siblings at the same site. The design note's own
determinism section predicted this failure in general terms ("any decision that
gates a collective ... must be broadcast, because a rank that decides
differently deadlocks its peers"); what it did not have was a mechanism making
the fourth copy impossible to omit. That is ledgered.

## F2 — the artifact's aperture counts are one rank's (major, fixed)

`src/tasks/RunArtifact.jl:306` wrote

```julia
g["aperture_counts"] = loss_counts(record)
```

`loss_counts(record)` is the rank-local `LossRecord.counts`, allocated per rank
over `length(rep)` (the shard) and bumped only by this rank's own kills. Every
other value in the same `/losses` group is the whole beam's: `data` is
`_mp_gather_rows`ed over all ranks (`:281`), and `summary_particles`/`_live`/
`_dead`/`_unattributed` come from the all-summed counts (`:314-318`).

The globalized attribution existed and was discarded. `_global_loss_summary`
(`src/tasks/Tasks.jl:578-579`) computes

```julia
by_aperture = collect(Int, summary.by_aperture)
isempty(by_aperture) || _mp_allsum!(by_aperture)
```

and hands the result to this writer as `summary`, which then re-read the local
array instead. `by_aperture` and `aperture_names` both derive from the same
record (`aperture.jl:653-654`), so they are index-aligned, and at one rank the
two are the same array — the fix changes nothing undivided.

What the defect did: at P ranks a reader reconciling `sum(aperture_counts)`
against `summary_dead` — which is exactly what `loss_summary`'s docstring
instructs, "a run where these disagree is telling you a particle died somewhere
you did not put a collimator" — sees a phantom unattributed gap that grows with
the rank count, and the collimator's own load under-reported by a factor of P.
Silently: `_report_losses`' console-quiet rule suppresses the correct console
number precisely because an artifact was attached.

Fixed to write `summary.by_aperture` when a summary is present, falling back to
the local array only when it is not.

## F3 — a hand-copied solver roster in the collide benchmark (major, fixed)

`profiling/benchmark_collide_cpu.jl:111` refused two of the four solvers under
MPI:

```julia
error("OCTOPUS_BENCH_MPI=1 supports OCTOPUS_BENCH_SOLVER=gaussian (step 4a) " *
      "and pic (step 4c) only: gaussian_pic and spectral still refuse to " *
      "run divided.")
```

with a comment above the usage block reading "Only the soft-Gaussian solver
divides today (campaign step 4a); the others refuse, loudly, when asked to" —
already contradicted by the gate three lines below it, which admits `pic`.
`_solver_divides` is `true` for all four (`interface.jl:2387-2388`,
`gaussian_pic.jl:132`, `spectral.jl:242`), and step 4g's record measures
spectral at 16 ranks. The file was last touched at `7f85724` (step 4e) and was
never revisited when 4f and 4g landed.

This is the "do not hand-copy knowledge" invariant exactly: a second copy of the
solver roster, in a file with no tripwire over it, telling an operator the
runtime refuses a configuration the runtime supports. Fixed by deleting the
gate — `_reject_undivided_solver` at the collide entry is the one authority, so
a solver that genuinely does not divide is still refused, by the code that
knows.

## F4 — the CUDA activation skips the launcher tripwire (moderate, fixed)

`_warn_launcher_without_policy()` had exactly one caller,
`_activate_resolved_policy!(::ResolvedCPUExecutionPolicy)` (`Beam.jl:376`). The
CUDA activation (`Beam.jl:451`) did not call it, though its own docstring makes
the promise unconditionally — "warn once when a launcher started several ranks
and the policy in force is an ordinary single-process one ... Octopus is
tracking the whole beam four times and four processes are writing one output
path". A `CUDAExecutionPolicy` is an ordinary single-process policy, and the
detector it would use, `_launcher_rank_count()`, is entirely policy-independent.
So `mpiexec -n 4` with a CUDA policy was the silent case the warning exists for.
Fixed by calling it there too.

## F5 — the launcher fixture resolved its shard outside the policy scope (moderate, fixed)

`test/mpi_seam_check_fixture.jl:87` computed

```julia
offset = first(Octopus._mp_resolve_shard(length(beam.rep)))
```

under the comment "Global indices, chosen to fall in different ranks' shards at
P = 2 and 4". Its only call site (`test/mpi_seam_check.jl:201`) sits between two
`_with_execution_policy` blocks, not inside one, so `_mp_resolve_shard` took its
early return, issued no `_mp_allsum!` and handed back `offset = 0` on every
rank. Every rank poisoned its own LOCAL particles 7 and 70; the global indices
never happened.

The dead totals came out the same either way, which is why the pin passed — it
could not distinguish a correct `_mp_resolve_shard` from a broken one. This is
the class `docs/experiences.md` already names twice ("A collective outside its
scope is a silent no-op", and its subsection on tests), found for the third
time, in the fixture written to guard against it. Fixed by resolving inside the
scope, with an anti-vacuity assertion that at more than one rank some rank off
rank 0 must see a non-zero offset.

## F6 — the Gaussian-PIC bare collide does not scope its shards (minor, fixed)

`_gpic_collide_fresh!` called `_gpic_collide!` directly. The three other
divided solvers wrap the same entry in `_with_beam_shards`, each with a comment
saying why: "a bare collide resolves each once here, at the entry, instead of a
per-slice function paying a hidden collective on a miss" (`gaussian.jl:12`,
`pic_cpu.jl:23`, `spectral.jl:1378`). gpic was the one that did not. Fixed to
match; `_with_beam_shards` skips reps already in scope, so the task path pays
nothing.

## F7 — prose that misdescribes live behavior (fixed)

Eight sites, each verified against the code before rewriting. `docs/history/`
was excluded by design — those records describe the commit they audited.

- `src/policies/Policies.jl`, the `MultiProcessExecutionPolicy` docstring: still
  said the PIC, Gaussian-PIC and spectral solvers refuse at more than one rank
  "step 4c onward", and that only a *soft-Gaussian* `StrongStrongTask` divides.
  All four divide as of 4f/4g/4h. (Found independently by this audit and by the
  harness work of the same day.)
- `src/policies/Policies.jl:511`, the seam's section header: "Six operations".
  The seam has since gained `_mp_allmin!`/`_mp_allmax!` (4c), `_mp_gather_rows`
  (3c), `_mp_exchange_columns` and the four point-to-point calls (4d), the tag
  bound check (4e review) and `_mp_test_all`/`_mp_wait_any` (4e). The design
  note had been given the qualifier; the code copy had not.
- `src/policies/Policies.jl`, `_mp_test_all`/`_mp_wait_any`'s shared docstring:
  "Neither records a receipt" — true of `_mp_test_all`, false of
  `_mp_wait_any`, whose first line is `_record_collective!(stage, ...)`. Both
  the prose and the recording line were added in the same commit (`7f85724`).
- `src/tasks/Tasks.jl`, `_reject_unsharded_tracking_features`' docstring: "only
  line ACTIONS are refused", while the body four lines below also refuses
  observers and line observers on a `PredicateSchedule` (added at 4b).
- `src/tasks/strongstrong/interface.jl`, the strong-strong twin of that
  docstring: same omission, same cause.
- `src/tasks/Tasks.jl`, `_observer_is_per_particle`'s docstring: "these need a
  gather the seam does not have. Declared beside the refusal that reads it."
  The seam gained `_mp_gather_rows` at 3c and the one observer answering `true`
  uses it; and no refusal reads the predicate. Its reader,
  `_task_has_per_particle_observer`, had zero call sites anywhere in `src/`,
  `test/` or `docs/` — orphaned at 3c. Docstring restated to the post-3c
  behaviour and the orphan deleted (repo-wide grep confirms no references).
- `src/contracts/Contracts.jl`, the high-energy weak-strong contract: named
  `_gaussian_collide_pair!` as the production entry point. No such function is
  in the tree, and the contract builds its solver with `batch_mode = :wavefront`,
  so the production side goes through `_cpu_gaussian_batch_moments` and
  `_cpu_gaussian_kick_chunk!`, not `_slice_transverse_moments` and
  `_slice_slice_gaussian_kick!`. Rewritten to name the route the contract
  actually runs and the arithmetic the two sides genuinely share
  (`_slice_moment_local_sums!` and `_slice_moments_finalize`, which both
  entries call).
- `docs/current_runtime.md`: "a strong-strong task still refuses outright,
  though the soft-Gaussian `collide!` itself divides ... campaign step 3a of
  4" — three false claims, in a file whose own strong-strong section 200 lines
  later ends "No solver in the roster refuses at more than one rank".
- `docs/design/multi_process_policy.md`, the determinism section: headed "what
  step 3 must choose" and written in the future tense about choices settled a
  thousand lines earlier in the same file. Retitled and put in the past tense,
  with `docs/README.md`'s summary of it ("the six-function collective seam ...
  what step 3 must still choose") corrected to match.

## F8 — the inline-branch comparison names a child that is not inline (fixed as prose, gap ledgered)

`test/runtests.jl` introduced its collide comparison with "The child runs at ONE
thread, where `_run_logical_workers` runs its chunk grid inline instead of
spawning a task per chunk ... the suite runs at four threads, so this
comparison is the only place the two paths meet."

The child is launched with `--threads=2`, and the inline branch is guarded on
the POOL (`Threads.nthreads(:default) == 1`, `Policies.jl:1154`), not on the
policy's worker count. Both sides of the comparison take the spawning branch,
and the pool-of-one inline path is exercised nowhere in the suite. The
`_run_logical_workers` unit test nearby reaches the `nworkers == 1`
short-circuit at `:1150`, which returns before the pool test.

**The obvious fix is wrong for this tree.** Launching the child at
`--threads=1` would make the comment true, but the child's thread-count sweeps
build `MultiProcessExecutionPolicy(threads = 2)` (`mpi_seam_check.jl:486, 509,
555`), which a one-thread process rejects with "CPU threads must be in 1:1".
Recorded here because the audit's first answer was that fix. The comment now
states what the comparison actually is — cross-pool-width invariance of the
divided arithmetic — and says plainly that the inline branch is untested,
pointing at the todo row.

## Ledgered, not fixed

Both are on concurrency surfaces where the change is larger than the finding
and wants its own gate at four threads.

1. **The `:funneled` tripwire tests a thread, not a task.**
   `_record_collective!` guards every seam function with
   `_mp_nranks() > 1 && Threads.threadid() != 1 && throw(...)`, and both the
   code comment and the design note describe it as catching "a collective
   reached from a worker task". `Threads.@spawn` schedules onto the `:default`
   pool, and thread 1 is in that pool — while the driver blocks in `@sync`,
   thread 1 runs spawned tasks like any other, so a substantial fraction of the
   16- and 64-wide chunk grids execute on thread 1 and read
   `Threads.threadid() == 1`. The tripwire is therefore too permissive, and
   whether it fires depends on scheduling rather than on the program. The fix
   is to test the task: a `ScopedValue` bound inside `_run_logical_workers`,
   which propagates into spawned tasks and is independent of which OS thread
   runs them.
2. **The pool-of-one inline path has no test**, per F8.

Three smaller items are on the row as well: hoisting the luminosity-schedule
broadcast into the one shared evaluator so a fifth solver cannot omit it
(F1 is the fourth hand-copy of that rule); `_ra_write_losses!`'s crash path,
which passes a NON-globalized summary where the success path passes a globalized
one and calls the `_mp_gather_rows` collective from a failure that may be
rank-local; and writing `summary_logged` into the artifact so
`sum(aperture_counts) == summary_logged` is checkable in the file itself.

## Corrections to the audit's own analysis

One finding survived three skeptics and did **not** survive the auditor's
re-verification; one further finding was right while the fix it proposed was
not. Both are recorded rather than quietly dropped.

- **`:pic_pair_schedule`'s receipt shape — withdrawn as a finding.** A sweep
  reported that
  `pic_cpu.jl:297` and `:333` are "the only emitters that omit the `schedule`
  field its siblings pad in". They are the only CPU emitters that omit it, but
  five CUDA emitters omit it *and* `pair_workers`/`inner_workers` as well, so
  the consumer's key set already varies by emitter by design. The only
  src-side consumer probes with `haskey`. Nothing behaves incorrectly, so
  padding the field would be a cosmetic change recorded as a defect — which the
  protocol calls a defect in the audit. Not changed.
- **F8's proposed fix — rejected, though the finding stands.** The sweep was
  right that the comment is false and the inline branch untested, and wrong
  about the remedy: launching the seam-check child at one thread is impossible,
  because that child's own thread-count sweeps build
  `MultiProcessExecutionPolicy(threads = 2)`, which a one-thread process
  rejects. The finding was acted on; its fix was not.

**The F5 fix itself shipped a defect, caught by the gate.** Wrapping
`_mpi_check_poisoned_beam`'s shard resolution in the policy scope, the auditor
also renamed its second return value to `local_n` and used it as the array
bound. `_mp_resolve_shard(local_n)` returns `(offset, GLOBAL_n)` — its
docstring says so on its first line — so at two ranks the bound became 256
against a 128-element array and the child died with a `BoundsError` at global
index 150, taking nineteen downstream assertions with it. Found by the full
gate, fixed by bounding on `length(beam.rep)` as the original did, and recorded
here because it is this audit's own precedent repeating: the
`neighbour_audit_2026_08_07` closure commits also had a defect caught by the
gate that closed them. A fix has a blast radius you did not measure, and that
is as true of an audit's fixes as of the ones it audits.

One lead surfaced inside a refuting vote rather than as a finding, and is
recorded as a lead rather than a finding because it was not established:
`pic_cpu.jl:205` computes `sliced = _mp_multi_process_active() && !node_grid &&
!share_grid`, so the `:node` and `:source_slice` PIC grid modes take the
per-pair route at more than one rank, and `_solver_divides(::PICPoissonSolver)`
is grid-blind. Whether that route is correct when divided was not determined
here.

## What was fixed, in one list

| file | change |
|---|---|
| `src/tasks/strongstrong/gaussian_pic.jl` | broadcast the luminosity verdict (F1); wrap the bare collide in `_with_beam_shards` (F6) |
| `src/tasks/RunArtifact.jl` | write the globalized aperture counts (F2) |
| `profiling/benchmark_collide_cpu.jl` | delete the hand-copied solver roster (F3) |
| `src/beam/Beam.jl` | run the launcher tripwire on CUDA activation too (F4) |
| `test/mpi_seam_check_fixture.jl` | resolve the shard inside the policy scope, with an anti-vacuity assertion (F5) |
| `src/policies/Policies.jl` | the policy docstring, the seam header, the dataflow pair's receipt claim (F7) |
| `src/tasks/Tasks.jl` | two docstrings; delete the orphaned `_task_has_per_particle_observer` (F7) |
| `src/tasks/strongstrong/interface.jl` | the strong-strong refusal docstring (F7) |
| `src/contracts/Contracts.jl` | the weak-strong-limit contract's call chain (F7) |
| `docs/current_runtime.md`, `docs/design/multi_process_policy.md`, `docs/README.md` | the stale refusal list, the determinism section's tense, the seam summary (F7) |
| `test/runtests.jl` | the inline-branch comment (F8) |
