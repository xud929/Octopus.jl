# The Multi-Process Execution Policy

Owner-directed campaign, single-node scope: P processes, each with T CPU
threads, for the tracking and strong-strong tasks. Phase 0
([`../history/multi_process_phase0_2026_08_19.md`](../history/multi_process_phase0_2026_08_19.md))
measured the transport and fixed the order:

1. **Weak-strong allocation extraction** — landed 2026-09-04
   ([`../history/weak_strong_allocation_2026_09_04.md`](../history/weak_strong_allocation_2026_09_04.md)).
2. **Policy type and collective seam** — this note.
3. **Weak-strong sharding** — the first consumers of the seam.
4. **Strong-strong, solver by solver** — soft-Gaussian, PIC, gpic, spectral.

Steps 3 and 4 add consumers; this note fixes the shapes they consume, so it
states what is decided and what is deliberately still open.

## What step 2 is, and what it is not

It is the policy, the communicator handshake, and six collectives with a
serial passthrough in core and an MPI implementation in an extension. It is
not sharding: no task divides work across ranks yet. A task asked to run on
more than one rank therefore **refuses**, naming step 3, rather than running
whole on every rank and letting every rank write the same output file. That
refusal is pinned, so the day step 3 removes it is a visible event rather
than a silent one.

At one rank the policy is `CPUThreadsExecutionPolicy` — the same partitions,
the same folds, the same numbers. That is measured both ways: in the serial
passthrough by the suite, and with MPI genuinely loaded under a launcher, in
the lane-gated section that compares a one-rank MPI run against a
single-process one coordinate by coordinate.

## The policy and where its state lives

`MultiProcessExecutionPolicy(; threads=:auto, ranks=:auto)` composes
`CPUThreadsExecutionPolicy(threads)` for the per-rank core. `ranks` is
`:auto` (accept the launcher's communicator) or an integer the run must match
exactly; a mismatch is rejected, never adjusted.

The resolved form is **not** a wrapper around `ResolvedCPUExecutionPolicy`.
It is that type, with a slot:

```julia
struct ResolvedCPUExecutionPolicy <: AbstractResolvedExecutionPolicy
    threads::Int
    multi_process::Union{Nothing,MultiProcessRequest,MultiProcessContext}
end
```

The reason is blast radius. Eight methods and `_cpu_worker_count()` dispatch
on this concrete type, and the public `track!`, `Beam`, task and
`configuration_report` paths all hand a resolved policy on positionally. A
wrapper has to be unwrapped at every one of them; one missed site is a
`MethodError` on a public entry, or worse, a silently different code path. A
slot makes "at one rank nothing changes" true by construction rather than by
argument — the object the inner code sees is the object it sees today, and
`nothing` in the slot is the ordinary single-process case.

**Resolution is pure.** `_resolve_execution_policy` records a
`MultiProcessRequest` and touches no communicator: `configuration_report`
resolves a policy just to describe it, and the strong-strong task resolves
once per beam. Initialising MPI as a side effect of asking a question would
be a trap.

**Activation reads the communicator.** `_activate_resolved_policy!` asks the
extension for one, reads the rank count and this rank's index *from it*,
checks them against the request and against the launcher, and returns a
policy whose slot holds a `MultiProcessContext`. `_with_execution_policy`
scopes the activated policy, so every consumer sees the context. The receipt
it records, `:multi_process_communicator`, carries the count it read, not the
count the policy asked for: a configuration you set is not a configuration
the code read.

## The seam

Six operations, each a core function with a serial passthrough and an
extension method dispatching on `MPI.Comm`:

| function | passthrough | MPI |
|---|---|---|
| `_mp_allsum!(A)` | `A` | Allgather, then fold the blocks into `A` in rank order |
| `_mp_lane_fold!(lanes)` | `lanes` | the same, named apart because the shard contract differs |
| `_mp_allminmax(lo, hi)` | `(lo, hi)` | `Allreduce` with `min` and `max` |
| `_mp_bcast!(A, root)` / `_mp_bcast(v, root)` | `A` / `v` | `Bcast!` / `bcast` |
| `_mp_barrier()` | `nothing` | `Barrier` |
| `_mp_nranks()`, `_mp_rank()`, `_mp_is_root()` | `1`, `0`, `true` | read from the communicator |

Every call records a `:multi_process_collective` receipt when an audit is
active, carrying kind, element count and bytes, so a later step can price its
own traffic instead of estimating it.

Two decisions inside those cells matter more than the rest.

**No `MPI_SUM`.** Every floating-point reduction is an Allgather followed by
a fold in rank order. A library sum may associate as it likes and may pick a
different tree for a different rank count, so the same run could give
different last bits on different ranks, and a 2-rank run could disagree with
a 4-rank one for reasons no physics explains. The ordered fold costs O(P) in
message volume, which Phase 0 already priced at 0.10–0.35 s/turn for 2–8
ranks and accepted. `_mp_allminmax` is the exception and is allowed to be a
true all-reduce, because min and max associate freely — which is exactly why
mesh and box sizing may use it without a determinism argument.

**A duplicated communicator.** The extension dups `COMM_WORLD` once per
process and caches it. Octopus's determinism argument assumes its own
messages are the only ones in flight on its communicator; dup buys that, and
caching it keeps `Comm_dup` — itself collective — from being called once per
`execute!`.

## Step 3a: dividing a tracking task

A tracking task is per-particle work. Every element whose map is a function of
one particle is divided by holding a shard of the beam, with no communication
at all. Only two things in a line reduce across particles, and each is handled
explicitly: a strong beam's luminosity, and an aperture's loss records.

**The shard rule is a contiguous run of whole reduction chunks.** The CPU
stack's count-invariant folds partition the beam into `_REDUCTION_CHUNKS`
fixed chunks and sum the partials in chunk order, and that order is what makes
a result independent of the worker count. Give each rank whole chunks and the
same property extends across processes for free: the ranks' partials,
gathered and folded in chunk order, are the single-process sum bit for bit.
The price is that the rank count must divide the chunk count, which is
enforced rather than worked around.

**The shard is derived and verified, never stored.** Nothing in the particle
representation records which slice of a larger beam it is, and a field that
said so could disagree with the array beside it. Summing the ranks' counts and
re-deriving the rule cannot disagree with itself, so a beam that was built or
split some other way fails loudly instead of tracking with the wrong random
streams and reducing into the wrong chunk slots.

**Random streams key on the global particle index.** The counter RNG keys each
particle's stream on its index, so a rank holding global particles `k+1 … k+m`
keys them on `k+i`. The offset rides on the tracking context, is zero in every
single-process run, and is what makes a radiating beam identical whether it is
divided or not.

**A beam is drawn whole and sliced, not drawn per rank.** This looks wasteful
and is, once, at startup. The alternative is not equivalent: the
standardization that turns raw normal draws into a unit beam takes the mean
and variance over the array, so a rank standardizing its own slice would
produce a measurably different beam, and no ordering of collectives recovers
Julia's pairwise sum over the full array. Drawing whole and slicing is
bit-identical by construction and needs no communication.

What 3a does not divide, and therefore refuses at more than one rank:
observers, actions, line hooks, the run artifact, and apertures. Each computes
over the beam it is handed, or keys on the index it sees, so at more than one
rank it would report a rank's own answer as the beam's. Step 3b divides them.

## Step 3b: dividing the diagnostics

The diagnostics that reduce the beam to SCALARS divide: moment observers,
beam position monitors, and the loss counts. Each reduces across the ranks and
each is reported by rank 0, so one run produces one report and one output
file. Every rank still runs every observer, because the reductions are
collectives and a rank that skipped one would hang its peers.

Those reductions are NOT bit-identical across rank counts, and that is a
decision rather than an oversight
([`../history/multi_process_step3b_2026_09_04.md`](../history/multi_process_step3b_2026_09_04.md)).
Folding them on the fixed chunk grid would have bought bitwise agreement, and
it was implemented and measured; it breaks a stronger property, that a lost
particle is excluded from every reduction EXACTLY, because a chunk grid
partitions slots and a masked beam has more slots than survivors. So the local
accumulation stays what it was -- one rank's numbers do not move at all -- and
the ranks' partials fold in rank order, agreeing with an undivided run to
1.7e-14 at two ranks and 8.7e-14 at four.

Still refused, because each needs the whole beam's PARTICLES in one place or
runs code Octopus cannot reason about: task actions, line hooks, apertures
(their per-particle loss rows key on the local index), and per-particle
observers. Which observers are per-particle is declared beside each observer.

## Step 3c: the output that cannot be reduced

An aperture writes a row per lost particle and a snapshot observer a row per
particle per turn. Those cannot be reduced, only moved, so the seam gains a
seventh operation: `_mp_gather_rows` collects every rank's rows onto rank 0 in
rank order, which is global particle order. Rank 0 only, because rank 0 owns
the file.

The rows carry the GLOBAL particle id. The aperture's slot table has one column
per particle the rank holds, and its recording path was indexed by the id,
which step 3a made global; the two differ by the shard offset the tracking
context already carries, so the slot is now `particle_id - ctx.index_offset`
while the file gets the global id back.

One rule this made explicit, at the cost of a defect that reached a commit:
**a collective outside the execution-policy scope is a silent no-op.** The
post-run accounting in `execute!` ran after the scope closed, so the gather saw
a communicator of one and returned only rank 0's rows -- and so had step 3b's
loss-summary reduction, at the same spot, which was therefore never reached by
`execute!` at all
([`../history/multi_process_step3c_2026_09_04.md`](../history/multi_process_step3c_2026_09_04.md)).

Only actions are refused now. An action is a callback the user wrote, handed
the rep this rank holds, and Octopus cannot know whether it means to see a
shard. Line observers are Octopus's own and divide, so the refusal
distinguishes a line carrying an observer from one carrying an action.

## Step 4a: the soft-Gaussian collide

Strong-strong is a different shape: both beams are sliced, every slice pair
interacts, and the loop's earlier iterations change the beams its later ones
read, so the moments cannot be hoisted out of it. Five reductions span the
ranks: the longitudinal statistics, the histogram the equal-area boundaries
are cut from, each slice's transverse moments, each slice's weight and
centroid, and the luminosity. The kick stays local.

The slice boundaries are the one place a tolerance is not acceptable. They
decide which particle is in which slice, so a disagreement between ranks is a
different collision rather than a small error. They come out bit-identical,
and the measured agreement of the collide's aggregates is about 5e-16
([`../history/multi_process_step4a_2026_09_04.md`](../history/multi_process_step4a_2026_09_04.md)).

The shifted moments need a shared origin, because two ranks shifting about
different ones produce sums that cannot be added. It is the slice's
globally-first member, found with a minimum over the global index and then
summed from the single rank that owns it.

`:equal_count` slicing refuses: it orders the whole beam, which is a sort and
not a fold. The other four methods size their boundaries from reductions that
are now global.

### The batch is what makes the divided collide cheap

The paragraph above says the moments cannot be hoisted out of the pair loop,
and for the COORDINATES that is true — every pair kicks the slices it touches,
so a later pair reads what an earlier one wrote. Two things about a slice are
not coordinates, and those hoist all the way out of the collide: how many
particles it holds, and WHICH particle is its globally-first member. Slice
membership is fixed once the beams are sliced. So the global counts leave the
pair loop as one all-sum over every slice, and the shift origin's OWNER leaves
it as one minimum per slice, paid once. Only the origin's four coordinates are
re-read, because those move.

What is left divides by batch rather than by pair. `collision_pair_batches`
groups pairs that repeat no beam-1 and no beam-2 slice, so within a batch the
pairs commute: no pair reads or writes a slice another pair in the same batch
touches. Every slice in a batch can therefore have its moments taken before
any of the batch's kicks, which turns 2w separate exchanges into one per beam
— and lets the batch issue all its kicks, both beams, as one grid. Measured at
15x15 slices: 1874 collectives per collide become 222, and the two schedules
agree to the bit at 1, 2 and 4 ranks (the multi-rank child asserts exactly
that, on the same four numbers, at every rank count it runs).

The switch is `batch_mode`, the keyword the solver already had for CUDA. It is
one keyword with one meaning on both backends rather than a CPU-shaped
sibling, which is also why its declared consumer is a receipt both routes emit:
`_solver_contract_receipt_carries` filters receipts BY BACKEND before it looks
at the name, so a `:cuda_`-tagged consumer could never have certified the CPU
half.

## The CPU, MPI and CUDA consistency statement

Three execution modes, and the relation between them is asserted in two
places rather than three, because the third follows:

| pair | relation | measured by |
|---|---|---|
| CPU vs MPI, tracking | **bitwise**, at every rank count that divides the chunks | the suite's multi-process section, under a launcher, comparing gathered shards against a single-process run |
| CPU vs MPI, scalar diagnostics | agreement to the accumulation difference between one serial sum and P of them: 1.7e-14 at two ranks, 8.7e-14 at four | the same section, comparing a divided run's moment row against a single-process one |
| CPU vs CUDA | agreement to the contract's tolerance | `ElementTrackingBackendConsistencyContract` and `validation/tracking_backend_consistency.jl` |
| MPI vs CUDA | the same tolerance, by composition | not measured directly, and cannot be: the multi-process policy is CPU storage only, so no rank holds a CUDA beam |

The bitwise half is the stronger claim and the one the shard rule exists to
buy. It is also the half that would decay silently: a tolerance would absorb a
fold quietly rearranged by a later change, where a bitwise comparison names it
on the next gate.

## Determinism, and what step 3 must choose

Fixed-P bit-repeatability holds for any shard, because the cross-rank fold is
rank-ordered.

Cross-P bit-invariance is available, but only where the shard aligns with the
partition a fold already uses. The CPU task path has three fixed, data-only
fold shapes: the 64-chunk `_REDUCTION_CHUNKS` grid, the 16-chunk
`_PIC_DEPOSIT_CHUNKS` grid, and the 4096-lane `_SLICE_FOLD_LANES` fold. A
rank shard that is a union of whole chunks (contiguous, `P | 64`) or whole
lanes (block-cyclic, `P | 4096`) keeps the fold's own order, and the gathered
partials fold to the same bits at any P. Folds keyed by *member-list
position* rather than global index — per-slice moments, slice centroids, the
PIC deposit — cannot be aligned that way, because slice membership is
per-turn data; those are the CPU/CUDA-parity tolerance class Phase 0 named.
The two aligned rules are mutually exclusive distributions, so step 3 picks
one and states which folds it buys.

Three more things step 3 owns, listed here because the seam is shaped for
them and they are easy to discover late: the counter RNG keys beam allocation
and radiation on the **global** particle index, so a shard carries an offset
or P > 1 draws different noise than P = 1; every length that enters physics
(slice weights, luminosity scales) becomes a global count through
`_mp_allsum!`; and any decision that gates a collective — a schedule
predicate, a slicing choice — must be broadcast, because a rank that decides
differently deadlocks its peers at the next collective.

## Threading, output, and the launcher

MPI is initialised at `:funneled`: Octopus issues collectives from the task
driver on the main thread, never from inside `_run_logical_workers`. Step 3
adds the tripwire when the first consumer lands; today no collective is
reachable from a worker.

Rank 0 owns the artifact and the console summaries — the run artifact is
serial HDF5 and two ranks opening one path is corruption. Step 3 implements
it; step 2's refusal is what keeps the question from arising early.

A launcher that starts several ranks while Octopus holds no communicator is
the trap this design most wants to avoid: every rank runs the whole job and
writes the same output, silently. With the multi-process policy that throws.
With an ordinary policy it warns once, because farming independent jobs with
`mpiexec` is legitimate — the warning names both readings and the keyword
that asks for the other one.

## Packaging

`MPI` is a `[weakdeps]` entry with the `OctopusMPIExt` extension; core never
imports it. Every method in the extension **adds** to a core function rather
than replacing one: the communicator opener dispatches on
`Octopus.MPIBackendTag` against a core fallback typed `::Any`, and each
collective dispatches on `MPI.Comm` against a core method typed `::Nothing`.
An extension that redefined a method its parent had already defined for the
same signature would fail to precompile.

The environment question — which MPI runtime an Octopus process carries, and
how that interacts with HDF5 — is measured and decided in
[`../history/mpi_environment_2026_09_04.md`](../history/mpi_environment_2026_09_04.md).
