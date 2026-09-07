# Closing the multi-process audit's ledger — 2026-09-07

The 2026-09-06 neighbour audit
([`neighbour_audit_2026_09_06.md`](neighbour_audit_2026_09_06.md)) fixed three
majors and priced six items rather than fixing them. This closes all six. Two
turned out not to be defects, one was a defect the audit had misdescribed, one
was smaller than the audit said, and one — pulled on — led to a defect the audit
had not found at all.

Every claim below was re-verified by the auditor against the source or by
measurement before it was recorded, and the two places where the audit's own
evidence was wrong are stated as corrections rather than quietly fixed.

## The one that was not on the list: spectral's schedule was never memoized

Closing the "the luminosity broadcast is hand-copied per solver" row meant
hoisting the broadcast into the single shared consult,
`_luminosity_schedule_evaluated` (`src/tasks/strongstrong/interface.jl`). That
required checking every solver routes through it. **Spectral did not.**

`_spectral_compute_luminosity` was a private copy of that whole function — its
own `should_run` call, its own receipt, and **no memo**. The memo exists because
the schedule is consulted twice per collision per turn, once by the
file-writing gate and once by the solver, and for a stateful `PredicateSchedule`
the two calls return different answers: the gate writes "evaluated" while the
solver declined, and the artifact gets a row of NaN — the value reserved for
"evaluated and numerically failed". That is the 2026-08-05_b audit's U5-2,
fixed for the PIC family then and never ported to spectral.

Measured, one probe, a schedule alternating true/false over four turns:

| solver | gate == solver, every turn | consults for 4 turns |
|---|---|---|
| PIC | yes | 4 |
| Gaussian-PIC | yes | 4 |
| soft-Gaussian | yes | 4 |
| **spectral** | **no** | **8** |

Spectral now routes through the shared body and keeps its own
`:spectral_luminosity_schedule` receipt through a `consumer` argument, so the
receipt streams are unchanged while the logic has one home. The four
hand-written `_mp_bcast` copies in `pic_cpu.jl`, `spectral.jl` (twice) and
`gaussian_pic.jl` are gone; the broadcast lives in the shared consult, guarded
on `schedule !== nothing` and placed inside the memo miss so every rank issues
the same number of them.

The existing test of this property covered PIC alone. It now covers all four
solvers, which is what would have caught this.

## The `:funneled` tripwire — real, but narrower than the audit said

The audit's claim: `_record_collective!` guards on `Threads.threadid() != 1`,
which does not mean "in a worker task", because `Threads.@spawn` schedules onto
the `:default` pool and thread 1 is in that pool — so "a substantial fraction of
the 16- and 64-wide chunk grids execute ON thread 1" and are waved through.

**Measured, Julia 1.12.4, 256 spawned tasks per invocation:**

| invocation | interactive threads | driver id | spawned ids | on the driver's id |
|---|---|---|---|---|
| `--threads=4` | 1 | 1 | 2..5 | 0 of 256 |
| `--threads=auto` | 1 | 1 | 2.. | 0 of 256 |
| `JULIA_NUM_THREADS=4` | 1 | 1 | 2..5 | 0 of 256 |
| `--threads=4,0` | 0 | 1 | 1..4 | **104 of 256** |

So the audit's mechanism is right and its frequency is wrong. Every ordinary
invocation gives one interactive thread; the driver sits on id 1, which is then
**not** in the default pool, and the thread test does catch every spawned
worker. The exposure exists only with `--threads=N,0`, where the pool contains
the driver's thread and about forty per cent of workers read `threadid() == 1`.
That is also why the gate never saw it: the gate runs `--threads=4`.

`--threads=N,0` is a legal invocation, and a tripwire whose correctness depends
on how the process was launched is not one. So the check now asks two questions:

```julia
_mp_nranks() > 1 && (_ON_SPAWNED_WORKER[] || Threads.threadid() != 1)
```

`_ON_SPAWNED_WORKER` is a `ScopedValue` bound around `_run_logical_workers`'
spawn branch and inherited by the tasks it spawns, so it answers the same under
every invocation and on every rank. The thread test is kept beside it because it
catches a collective issued from some other task entirely, which no worker flag
would see. Neither subsumes the other. `_mp_test_all`, which records no receipt
and so cannot inherit the check, carries the same pair by hand.

### The first draft was wrong, and a read-only sweep caught it before the gate

The audit proposed binding the flag around the worker bodies — all three
branches. That draft was written, and it would have refused the divided PIC
`:node` collide at every rank count.

`pic_cpu.jl` sets `pool_workers = divided ? 1 : ...` and says why: "ONE pair
worker when divided: on this path — the node and source-slice meshes — every
pair issues collectives, MPI is `:funneled`, and the seam's tripwire throws off
the main thread, so the batches keep their order and their pairs run one at a
time on the main thread." The divided collide deliberately routes its
collectives through `_run_logical_workers(1)`, whose body runs INLINE on the
caller's task, on the main thread, where `:funneled` allows them. A flag meaning
"lexically inside a worker body" refuses that legitimate path; the correct
predicate is "on a task that is not the driver's".

So the flag is bound on the spawn branch and nowhere else, and the two inline
branches are deliberately left false. The blast-radius sweep that found this
traced a five-hop chain — `_run_logical_workers` → `_pic_collide_pair!` →
`_pic_interaction_node!` → `_pic_solve_drifted_field_with_green_fft!` →
`_mp_allsum!` — and named the seam-check arms (`:node`, `:node2`) that would
have failed. Recorded because the audit's proposed remedy, followed literally,
would have shipped a regression.

### How it is shown to fail

Two pins, because the in-process one cannot demonstrate the exposure under the
suite's own invocation:

- In process: every spawned worker is flagged, the flag is clear outside and
  restored after, a collective from a spawned worker is refused naming the
  worker half, and — the other direction — a collective from the INLINE
  single-worker path is **not** refused, which is the divided PIC path.
- A `--threads=4,0` subprocess: asserts first that workers really do land on the
  driver's thread there (23 of 64 in the measured run, so the premise is
  asserted rather than assumed), then that a collective from one is still
  refused, and that it was the worker flag that refused it. That is the case the
  thread test cannot see.

### Cost

One `ScopedValue` binding per `_run_logical_workers` call, measured directly at
**45 ns**, against ~900 such calls per turn: 0.04 ms/turn, against a collide
that costs 2.6–8.4 s/turn at the production point. Below 0.002%.

## The pool-of-one inline path now has a test

The audit found this branch — the one every MPI rank takes at one thread per
rank, the configuration that scales best — exercised nowhere, and proposed
launching the MPI seam-check child at one thread. That is impossible: the
child's own thread-count sweeps build `MultiProcessExecutionPolicy(threads = 2)`,
which a one-thread process rejects with "CPU threads must be in 1:1".

A plain one-thread subprocess needs no MPI and no launcher. It asserts the
inline grid writes the same slots in the same order as the spawning branch the
parent just ran, and that the inline path leaves `_ON_SPAWNED_WORKER` false.

## Two rows closed as NOT defects

**The artifact's crash path.** The audit flagged that `_ra_write_losses!`'s
crash path passes a non-globalized summary while the success path passes a
globalized one, and calls a collective from a possibly rank-local failure. Both
are deliberate and documented at the site: the crash path runs outside the
execution-policy scope on purpose — "an exception is in flight, the ranks may
not agree on having thrown, and a collective issued by some of them would hang
the rest" — so the gather is a passthrough there and cannot hang, and the
rank-local summary is the information actually available.

What was missing is what that row itself proposed: "write this rank's rows,
LABELLED as such". A crashed four-rank run wrote `dead=1` where a successful one
writes `dead=4`, with nothing in the file to tell them apart. `/losses` now
carries `summary_folded` — true on the success path, false on the crash path —
pinned on both.

**PIC `:node` / `:source_slice` when divided.** Raised as a lead inside a
refuting vote. Established as deliberate: `pic_cpu.jl` computes
`sliced = _mp_multi_process_active() && !node_grid && !share_grid` and the
comment above it says "the node and source-slice meshes keep the per-pair paths
below". That route is divided-aware, and it is pinned under a launcher — the
seam check carries `:node`, `:source_slice` and `:node2` arms, and the suite
asserts for each, at 1, 2 **and** 4 ranks, that the pair-schedule receipt reads
`exchange=per_pair schedule=none`, so the route each rank took is asserted
rather than assumed. No change.

That reading also settles the receipt-shape item the audit withdrew: the
fixture normalises the absent `schedule` field with a `hasproperty` fallback,
which is why the varying key set harms nothing.

## `summary_logged`

`/losses` now records it, so `sum(aperture_counts) == summary_logged` — the
reconciliation `loss_summary`'s docstring instructs, and the equality the
2026-09-06 F2 fix makes true across ranks — is checkable inside the file rather
than only by recomputing it. Written as `Int64` like every other attribute in
the group; a file written earlier returns `nothing`, the shape this reader
already used for an absent `aperture_s`.

## The one MPI file the audit's scope never reached

The 2026-09-06 audit scoped itself to the campaign diff, `5dd9e22..HEAD`. That
is the right scope for a neighbour audit, but it leaves MPI code the campaign
did not touch unexamined. Enumerated by grep and differenced against the
campaign's file list, exactly one such file exists:
`profiling/mpi_collide_prototype.jl`. (Three other files match a naive `MPI`
grep and are substring false positives -- `COMPILE`, `PRECOMPILATION`,
`COMPILING`.)

It is the Phase 0 cost model from 2026-08-19, and three of its claims had gone
stale:

- **Its second "environment trap" states a mechanism that a later record
  disproves.** The header called it a LOAD-ORDER LOCK -- "HDF5 depends on
  MPIPreferences, so loading Octopus first pins the MPICH_jll default before
  MPI.jl reads a preference, so the ranks run MPICH_jll regardless of any
  `use_system_binary()` configuration".
  [`mpi_environment_2026_09_04.md`](mpi_environment_2026_09_04.md)'s probe 4
  contradicts the general form: with the preferences on the load path AT
  PROCESS START, Octopus loaded first and MPI.jl still ran the system Open MPI.
  What is true is narrower and is about WHEN the environment joined the load
  path -- which this script's `push!(LOAD_PATH, ...)` after start does trigger.
  The trap is real for this script; the reason it gave was wrong, and a reader
  would have carried the wrong rule away. Corrected in place, with the
  correction attributed.
- **"production MPI selection is a Phase 1 environment task"** -- settled the
  same day: MPICH_jll by default, no configuration.
- **"the real design must interleave it with compute and, past ~16 ranks, use a
  deterministic tree instead"** -- a prediction the campaign overtook. The
  all-sum became a reduce-scatter (4c), then per-pair point-to-point on a
  slice-aligned layout (4d), then a dataflow loop overlapping exchanges with the
  next batch (4e). No deterministic tree was needed; the rank-ordered fold
  survived all three.

And the framing gap that matters most: nothing in the file said the thing it was
prototyping now EXISTS. A reader could take a cost model for a measurement of
the implemented policy. The header now says so and points at
`OCTOPUS_BENCH_MPI=1 profiling/benchmark_collide_cpu.jl`, which runs the real
`MultiProcessExecutionPolicy` on real shards -- the same driver whose
hand-copied solver roster the 2026-09-06 audit deleted, so it now accepts all
four solvers.

With this file examined, every `.jl` in the tree that genuinely references MPI
has been through the audit.

## A mistake made and repaired while doing this

A scripted edit to `test/runtests.jl` used a `rfind` over too wide a span and
deleted about 550 lines of unrelated tests. It was caught immediately by the
diff stat (553 deletions where the edit should have been additive), the file was
restored from `HEAD`, and the four of the day's additions were re-applied
against narrow anchors; the diff is now 220 insertions and no deletions.
Recorded because "the diff stat is part of reading your own edit" is the cheap
habit that caught it, and because a repaired mistake that is visible is worth
more than one that is not.
