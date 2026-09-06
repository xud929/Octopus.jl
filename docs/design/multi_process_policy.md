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
refusal was pinned, so its removal was a visible event: step 3a narrowed it
to what was still undivided, and step 4b removed the last blanket one. What
refuses now is listed under each step, and every refusal names what is
missing.

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

The seam's operations, each a core function with a serial passthrough and an
extension method dispatching on `MPI.Comm` (the first six are step 2's; the
rest arrived with the steps that needed them):

| function | passthrough | MPI |
|---|---|---|
| `_mp_allsum!(A)` | `A` | below 2048 elements Allgather, then fold the blocks into `A` in rank order; above, an Alltoall of `P` blocks, the rank-ordered fold of each, then Allgather -- the same sum per element, `2n` per rank instead of `nP` (step 4c performance phase) |
| `_mp_lane_fold!(lanes)` | `lanes` | the gather-and-fold, named apart because the shard contract differs |
| `_mp_allminmax(lo, hi)` | `(lo, hi)` | `Allreduce` with `min` and `max` |
| `_mp_allmin!(A)` / `_mp_allmax!(A)` | `A` | vector `Allreduce!` with `min` / `max` (step 4c) |
| `_mp_exchange_columns(cols, dest)` | `cols`, `[n]` | counts by Alltoall, then one Alltoallv of whole columns; received in sender rank order (step 4d's migration) |
| `_mp_isend(A, dest, tag)` / `_mp_irecv!(A, source, tag)` / `_mp_wait_all(reqs, stage)` | a copy to oneself, matched by tag at the wait | `Isend` / `Irecv!` / `Waitall`, the wait clocked per stage (step 4d's pair messages) |
| `_mp_bcast!(A, root)` / `_mp_bcast(v, root)` | `A` / `v` | `Bcast!` / `bcast` |
| `_mp_gather_rows(rows)` | `rows` | rows onto rank 0 in rank order (step 3c) |
| `_mp_barrier()` | `nothing` | `Barrier` |
| `_mp_nranks()`, `_mp_rank()`, `_mp_is_root()` | `1`, `0`, `true` | read from the communicator |

Every call records a `:multi_process_collective` receipt when an audit is
active, carrying kind, element count and bytes, so a later step can price its
own traffic instead of estimating it; the extension also keeps per-kind
clocks of its MPI calls (`_mp_collective_times`), which the collide benchmark
prints, because a count and a size do not say what a call cost.

Two decisions inside those cells matter more than the rest.

**No `MPI_SUM`.** Every floating-point reduction is an Allgather followed by
a fold in rank order. A library sum may associate as it likes and may pick a
different tree for a different rank count, so the same run could give
different last bits on different ranks, and a 2-rank run could disagree with
a 4-rank one for reasons no physics explains. The ordered fold costs O(P) in
message volume, which Phase 0 already priced at 0.10–0.35 s/turn for 2–8
ranks and accepted. `_mp_allminmax` is the exception and is allowed to be a
true all-reduce (but a NaN in its input is rank-divergent under `MPI_MIN`
and `MPI_MAX`, measured, so a non-finite verdict is agreed as an integer
count and never read off an exchanged bound), because min and max associate freely — which is exactly why
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

## Step 4b: the strong-strong task

The collide divided in 4a; this wires the task around it. Three things had to
change, and two of them are about the run holding TWO beams where every
earlier step held one.

**One shard per beam, keyed by representation.** The scope that carries a
run's `(offset, global_n)` held one of them, and every fold read it whatever
beam it was folding. A strong-strong task's beams may differ in size, so the
second beam was handed the first beam's offset. Keying by local count instead
is ambiguous in principle -- beams of 256 and 257 particles give rank 1 of 2
the same 128-particle shard at different offsets -- so the scope holds one
entry per beam keyed by the identity of its `Phase6DRep`, which is the object
every consumer already has: `Beam` is immutable and tracking mutates its
arrays in place. The run resolves both shards at its entry, one integer
collective each in a fixed order, and a consumer that reaches a fold with a
representation the run did not scope pays the collective rather than getting
another beam's answer. The count-keyed form survives for callers holding only
an array; it throws on the ambiguous case rather than guess.

**One tracking context per beam.** Each line tracks under its own global
index offset, so a radiating element or an aperture in line 1 keys on beam
1's global indices and one in line 2 on beam 2's. The collide takes the
turn-only context and reads its offsets from the scope.

**The whole run inside the scope.** Preparation, the turn loop, the observers'
flushes and the artifact's close all sit inside the policy scope, because any
of them may issue a collective (the step-3c lesson). The failure path issues
none: probe-row pushes and the artifact's finalize are root-only, so a rank
that throws cannot strand its peers from inside `finally`.

Everything else was already divided: the luminosity is the collide's global
sum and lands in the artifact through the root-only push; line observers
reduce (3b) or gather (3c); the artifact is rank 0's. What refuses, named in
the message: line ACTIONS in either line and line observers on a
`PredicateSchedule` (both are user code handed one rank's shard, and a
schedule predicate gates a collective every rank must issue -- the tracking
task refuses the same two), `:equal_count` slicing (4a), and, when this was
written, every solver but the soft-Gaussian. Steps 4c through 4g divided the
rest; the solver refusal survives as a deny-by-default tripwire
(`_solver_divides`, false for `AbstractPoissonSolver`), fired at the task's
preflight and at the PIC collide entry, so a solver added after the campaign
cannot collide one rank's shard and call it the beam.

Two decisions that gated a collective were still rank-local on the collide
path and were found by the 4b review: the slicing refused an EMPTY shard, or
one whose particles were all dead, on this rank's own count, while its peers
went on into the first collective and waited there -- reproduced under a
launcher on the tree that closed 4a. Both refusals now read the whole beam's
counts. The remaining rank-0-only failures (an artifact that cannot be
opened, a duplicate probe name) leave the other ranks in their first
collective, and the job ends because the launcher aborts on the non-zero
exit -- the posture the tracking task has; a broadcast of the outcome after
preparation would close it and is priced as hygiene, not owed here.

Measured in
[`../history/multi_process_step4b_2026_09_05.md`](../history/multi_process_step4b_2026_09_05.md).

## Step 4c: the PIC collide

The second solver, and the first with a mesh. A PIC pair deposits each slice's
macroparticles onto a grid, solves the field by an FFT convolution with the
Green function, and interpolates the kick back to the other slice's
particles. Divided, each rank deposits its OWN particles of the source slice,
the deposited charge grid is all-summed across the ranks, and every rank then
solves the identical field redundantly -- a grid solve costs far less than
moving particles -- and kicks its own particles. The luminosity is the overlap
of two deposited grids, so its two deposits are all-summed the same way and
the overlap is then the beam's on every rank, returned as it is rather than
summed again (the soft-Gaussian's per-rank partials are summed once at the
end of its collide; PIC's per-pair values are already global).

What else had to become the beam's rather than the shard's, each found by
measurement or by review:

- **The mesh extents.** A pair's mesh is sized from the drifted extrema of
  both slices; those are all-reduced (min and max associate, so no ordering
  argument is needed), and everything downstream -- the grids, the quantized
  extents, the slice-pair Green cache's reuse decisions, the node and
  source-slice meshes -- then runs identically on every rank from identical
  inputs. The Green-function cache therefore works divided with no exchange:
  every rank holds the same cache. Under `grid_extent = :sigma` the estimator
  shifts its sums about the slice's first member, which must be the same
  particle on every rank: the globally-first member, obtained the 4a way.
- **The kick scale.** PIC's per-macroparticle kick divides by the source
  beam's macroparticle count, and it read the shard's. Every kick scaled by
  the rank count -- 1.9x at two ranks, 3.5x at four -- before it read the
  scoped global count. The luminosity scale had the same shape.
- **Every skip.** A pair whose slice is empty on THIS rank but not globally
  must still take part in the pair's collectives, so every skip -- the pair
  itself, the node-mesh prebuild -- reads the slices' global counts from the
  shared plan, and a rank holding no member of a slice starts its extrema
  from infinity and deposits nothing.
- **The non-finite chokepoints.** They tested local data and threw on one
  rank; each now takes its verdict on the local data, agrees it across the
  ranks as a count, and throws on every rank or none.
- **The schedule, and the batched exchange** (performance phase, record:
  [`../history/multi_process_pic_scaling_2026_09_05.md`](../history/multi_process_pic_scaling_2026_09_05.md)).
  The first division issued every collective from inside a pair -- about
  twenty-four per pair, six of them a whole padded plane -- and, MPI being
  `:funneled`, ran the pairs one at a time on the main thread. Under the
  wavefront schedule on the `:slice_pair` mesh a batch's pairs are
  conflict-free, so `pic_cpu_divided.jl` lets every pair of a batch reach
  each collective together and every plane be solved once: one all-max of
  every pair's stacked mesh extents and one all-sum of their `:sigma` sums,
  counts and non-finite flags; the nx x ny interiors of every deposited plane
  of both directions of every pair reduce-scattered by whole planes to OWNER
  ranks (`_mp_reduce_scatter_blocks!`: an Alltoall laid out so each rank
  receives whole planes, then the rank-ordered fold -- the all-sum's sum per
  element), the owners solve, and the potentials all-gather
  (`_mp_allgather_blocks!`) so every rank takes the gradient of the same
  numbers; one all-max of the luminosity meshes' extents, a reduce-scatter of
  every luminosity deposit to an owner that forms the overlap sum, and an
  all-gather of those scalars. Seven collectives per batch, eight under
  `:sigma`, none inside a pair -- so the pairs keep the worker pool -- the
  solves divided by the rank count, and the same arithmetic in the same order
  per particle and per grid element (the field's extents from `x + s*px`
  without writing it; the in-place drift moves to the kick stage; the
  padding sums zeros to zero), which the launcher child pins: the per-pair
  exchange, kept as `batch_mode = :sequential`, equals the batched one bit
  for bit at every rank count it runs. The node mesh keeps the per-pair
  exchange (its staging differs); `:source_slice` never batches. Underneath,
  the extension's all-sum above 2048 elements is a reduce-scatter (Alltoall
  of `P` blocks, rank-ordered fold, Allgather): `2n` per rank instead of
  `nP`, the same bits by construction and by measurement.

Gaussian-PIC and spectral still refuse. Measured in
[`../history/multi_process_step4c_pic_2026_09_05.md`](../history/multi_process_step4c_pic_2026_09_05.md).

## Step 4d: the slice-aligned collide

**Why.** Step 4c's collide, measured at the production point
([`../history/multi_process_pic_scaling_2026_09_05.md`](../history/multi_process_pic_scaling_2026_09_05.md)),
peaks at 5.9x on sixteen ranks and falls to 2.5x on sixty-four. The
collectives are 84% of the wall there, and the reason is the layout, not a
defect: every rank holds a chunk of every slice, so every plane's charge is
the sum of `P` partials and every plane's potential must reach all `P`
ranks. Per collide that is 900 planes x `P` x 128 KB through shared memory
(15 GB at 64 ranks, 60 reduce-scatter calls of 8 MB per rank each), and
MPICH's Alltoall delivers it at ~40 GB/s -- the aggregate grows with the rank
count while the compute shrinks, and they cross near sixteen. The owner
lifted the constraint that made the layout necessary (2026-09-05): the
chunk-aligned bit-identity is not required of the collide; a result in the
serial one's parity class is. (This section was reviewed adversarially
before it was built; the review's findings are folded in below.)

**The layout.** For the duration of one collide the LIVE particles of each
beam are laid out by slice, slice-aligned rather than equal-count, so that no
rank holds parts of two slices and no slice sends a sliver:

- with `P <= nslices`, whole slices go to ranks: slice `s` goes to rank
  `floor((C_{s-1} + n_s / 2) / (N / P))`, `C` the cumulative live counts, so
  a rank holds a contiguous run of whole slices (fifteen equal slices on
  sixteen ranks: one per rank and one rank idle; an `:equal_width` beam's
  central slice can be most of a rank alone);
- with `P > nslices`, slice `s` gets `g_s` ranks, `g_s` proportional to `n_s`
  by largest remainder with `sum g_s = P` and `g_s = 0` for an empty slice,
  and its members are split into `g_s` equal contiguous parts (fifteen equal
  slices on sixty-four ranks: four slices on five ranks, eleven on four).

A slice's GROUP `G_s` is the contiguous range of ranks holding it. Both beams
are laid out by the same rule, independently. Within a slice the members are
ordered by home rank then by home order -- the beam's global order -- so the
slice's first member on the first rank of its group is the undivided run's
first member, which is the `:sigma` origin, with no collective. Groups,
owners and every message layout below are derived on every rank from the
plan's global counts and the layout rule alone; changing that derivation is
a protocol change.

Tracking, the observers, the artifact and every other step of the campaign
keep the chunk-aligned home layout untouched: the collide migrates the live
particles in at its entry and back at its exit (`_mp_exchange_columns`, an
all-to-all of columns: six coordinates and the slice index out, six back --
no index travels; the home rank remembers the destination sort it applied
and the slice rank the re-bucketing by slice, and inverts them). Dead
particles join no slice and stay home. At the production point that is
~170 MB aggregate each way against the 15 GB of planes it replaces. Outside
the collide nothing changes.

**The pair.** Pair `(i, j)` joins `G1_i` (source of direction 1, field of
direction 2) and `G2_j`. Two fixed roles, both functions of the pair and the
layout only:

- the COORDINATOR is the first rank of `G1_i`; it forms the pair's mesh
  extents and its luminosity mesh;
- each PLANE of the pair (`(direction, plane)`: two planes per direction,
  three under `:quadratic`) has an OWNER, dealt round-robin over all `P`
  ranks from the pair's position in its batch (pairs of a batch in `(i, j)`
  order), so a batch's solves spread over every rank -- `ceil(planes / P)`
  each, one at 64 ranks -- rather than four on one rank; the owner keeps that
  plane's Green table in its own slice-pair cache, keyed by `(i, j,
  direction)`, and the deal is the same every turn while the batches are
  (a re-ordered batch costs one rebuild, counted in the cache receipts).

The stages of a batch, every message point-to-point (`Isend`/`Irecv` posted
from the main thread between stages, tagged by pair, stage, direction and
plane, waited with `_mp_wait_all`; the seam's `:funneled` tripwire covers
them), seven hops in all:

1. Every member of both groups sends the coordinator one record: its local
   extents and `:sigma` sums as source and as field, its local count, its
   first member's five coordinates, and a non-finite flag from its own data.
   The coordinator folds the records in group rank order and sends the
   reduced record (and the verdict) to every rank involved in the pair --
   members and plane owners -- each of which forms the same grids from the
   same numbers.
2. Members of the source group deposit the nx x ny interior of each plane
   at that plane's drift and send it to the plane's owner. The owner WAITS
   FOR EVERY PARTIAL, then folds them in group rank order (never on
   arrival), solves, and sends the potential to every member of the field
   group, which takes the gradient itself and kicks its particles. Both
   directions run in the same stages.
3. Members send the coordinator the extrema of their virtual positions; the
   coordinator returns the overlap mesh; members deposit and send; the
   coordinator folds in group order and forms the overlap sum for the pair.

Per pair that is `2 (|G1_i| + |G2_j|)` partial planes per direction and as
many potentials -- about ten at 64 ranks, two at sixteen -- against `P` of
each on the chunk-aligned layout; ~1.5 GB aggregate per collide at 64 ranks
with the luminosity deposits and the migration, against 15 GB. No rank
waits on any rank outside its pairs. The wavefront batches stay the
schedule: a rank's pairs of one batch touch disjoint slices, so their stages
interleave; at one thread per rank -- the measured-best configuration --
the stages are main-thread code and the pool serves the per-particle maps
only. Under `batch_mode = :sequential` the same path runs one pair per
batch, so the two schedules stay bit-identical at every rank count (the 4a
and 4c pin, kept). The 4c batched exchange (`pic_cpu_divided.jl`) is
retired with this step; `:node` and `:source_slice` keep their 4c per-pair
paths.

**What remains collective, and the non-finite verdict.** Per collide: the
slicing and the plan on the home layout (as before), the two migrations,
one all-sum of the pair luminosity vector so every rank holds every pair's
value folded in pair order, the dropped count, and one integer all-sum of
the non-finite flags. Inside the stages nothing is collective, so the 4c
rule -- every rank throws or none -- is kept this way: the flag rides in the
stage-1 record, the coordinator's reply carries the verdict, every rank
involved skips the rest of that pair, and the collide-end all-sum of flags
makes every rank throw, the rank holding the coordinates with the detailed
message. A failure outside that path ends the job through the launcher's
abort, the 4b posture.

**One rank.** The sliced path runs at one rank too, with self-delivery in
the passthrough (a send to oneself is a copy), and there it is the CPU
collide bit for bit: one group per slice, the members in home order, the
deposit and the solve the undivided ones. That is the pin that touches this
code -- the in-process one-rank check and the launcher's one-rank line --
and the reason the receipt says `exchange=sliced` at one rank rather than
`none`.

**What it costs, per observable.** At a fixed rank count the run is
bit-repeatable. Across rank counts the deposits of a slice are folded over
its group in a fixed order and the luminosity over pairs in pair order, so
the classes are 4c's ([`../history/multi_process_step4c_pic_2026_09_05.md`](../history/multi_process_step4c_pic_2026_09_05.md)):
the luminosity in the 1e-15 class, coordinates 1e-15 against the beam scale
and up to 1e-13 pointwise (the contract's own criterion), many-pair
fingerprints 1e-14 at fifteen slices and 1e-13 at sixty-four; with
`P <= nslices` a whole slice deposits in the serial member order, so the
class should shrink below 4c's, and with `P > nslices` it is 4c's at
`P / nslices` ranks. Under `grid_extent = :extrema` (the default) the grid is
the serial grid to the bit, because the per-pair extents are exact; under
`:sigma` the extents agree to the last bit of the exchanged sums, and
`grid_quantize` and the cache's reuse test are discontinuous in that bit --
the 4c caveat, unchanged. The class is a per-collide statement; nonlinear
tracking separates last bits over thousands of turns, as it does for 4c.
The tolerance protocol: land with the parent's 1e-12 pins, measure the
child at 2, 4 and 8 ranks and the contract at 1, 2, 4 and 8, record the
worst per arm and rank count, require ten times margin, pin no tighter than
1e-13 from one measurement.

**Expected.** The floor is the wavefront: 29 batches times the busiest
rank's stage work (its pairs' deposits and kicks, its owned solves at 1.3 ms
each, its copies) plus seven hops at ~0.5 ms a batch; at the production
point ~0.2-0.3 s per collide on 32-64 ranks against 1.07 s today and 6.27 s
serial, with the Green-cache hit rate at the physical kick deciding where in
that range, and a curve that flattens near `P ~ 4 nslices` rather than
turning over at sixteen. Measured ([`../history/multi_process_step4d_sliced_2026_09_05.md`](../history/multi_process_step4d_sliced_2026_09_05.md)):
0.88 s at 32 ranks and 0.90 at 64 at the production point, 7.6x, the curve
flat past 32; at sixteen ranks slower than 4c, because a batch's critical
path is one whole slice's work on one rank -- the wavefront's floor, which
dataflow across batches is the next step against. The `z` round trip (the
collide never writes `z`, so `z` returns to its home slot bit for bit) is
the migration's own check, printed per rank by the launcher child.

## Step 4e: dataflow across batches

**Why.** Step 4d's collide runs its pairs in wavefront batches, and within a
batch every rank walks the same eight stages, waiting at each for its own
messages. A rank's messages arrive when the ranks it shares a pair with have
finished their stage, so a batch runs at the pace of its slowest member and
a rank with a light pair, or none, idles until the batch is through. The
clocks priced it ([`../history/multi_process_step4d_sliced_2026_09_05.md`](../history/multi_process_step4d_sliced_2026_09_05.md)):
at sixteen ranks, one slice per rank, a batch's critical path is one whole
slice's deposits and kicks on one rank, and the wavefront's duty cycle
leaves half the ranks idle on the average batch (225 pairs over 29 batches,
fifteen at the widest); at sixty-four ranks 72% of the wall is waiting,
most of it owners on coordinators and the tail skew at the collide's end.

**The rule.** A pair depends on nothing but its two slices' previous pairs:
`(i, j)` may start once each of its slices has been kicked by THE PAIR BEFORE
IT in the collision order, among that slice's non-empty pairs. That
predecessor is read from `order`, never computed from indices: the collision
time is `-(c1 + c2)/2` ascending, so with ascending slice centres the pair
before `(i, j)` on slice `i` is `(i, j + 1)`, and index arithmetic would gate
on a pair that has not run yet (the 4e review's finding). A rank's part of a
slice is kicked by a stage of that rank alone, so the gate is local. The
batch is therefore not a synchronisation point at all -- it is only the deal
of the owners, which stays as it is (round-robin over all ranks from the
pair's position in its batch, so the solves and the Green cache still spread
and still land on the same rank every turn).

Each rank runs an event loop: scan every live pair in the collision order and
run every stage whose receives have completed (`_mp_test_all`, non-blocking)
and whose gate is open -- relay duties first (a coordinator's fold, an
owner's grids and solves, the luminosity folds), so a pair waiting on this
rank is not held behind a long deposit of its own -- and repeat; when a whole
scan runs nothing, block on the union of everything outstanding
(`_mp_wait_any`). The stages, their messages and their tags are 4d's; only
WHEN a rank runs them changes. The invariant that keeps every read identical:
for each (rank, slice part) at most one pair sits between its first read and
its kick, so every read is bracketed by the same kicks as in `order`.

**Buffers.** Under 4d every message of a batch was waited before the next, so
the scratch pools were reset per batch. Under dataflow a buffer belongs to
its send until MPI says the send completed: a pair returns its buffers to the
free lists only once `_mp_test_all` on its send list is true, and the loop
drains the rest at its end. Nothing else covers them, and a plane reused
early would corrupt a peer's charge silently. The pools are uncapped -- a cap
that both sends and receives draw from is a resource deadlock -- and what is
in flight is bounded by the gate instead: per slice part, one pair between
its record and its kick plus its luminosity tail, and the pairs this rank
owns or coordinates within the frontier. The `:sigma` origins move into the
per-pair buffers under two codes inside the pair's tag space, so the
free-list rule covers every buffer the loop sends and nothing rides a tag
band of its own (a separate band collided with the pair band a few hundred
pairs in, and a slice-keyed tag leaned on MPI's non-overtaking rule besides).
The collide checks its largest tag against the communicator's limit rather
than assuming it.

**A pair that meets a non-finite extent releases its slices.** It marks
itself done without kicking -- the batched loop's skip -- so its successors
run and the collide reaches the count that makes every rank throw. A bad pair
that simply stopped would hang its slices instead.

**What does not change.** The arithmetic and every fold order. Both loops
call the same leaves -- a direction's deposits, an owner's fold-and-solve of
one plane, a field part's gradient-drift-kick, the luminosity's fold and
overlap -- so the bits live in one place and the loops differ only in when
they run them. A slice's pairs are still kicked in its collision order, each
deposit still reads the slice after exactly the kicks the per-pair path
applied, an owner still folds after ALL its partials have arrived and in
group rank order (never on arrival), and the luminosity still folds in pair
order at the end.

`:sequential` keeps the 4d batched loop, one pair per batch, waited stage by
stage: two loops, owned here, pinned against each other on every gate by the
child's `:sequential` arm, which must equal the default bit for bit at every
rank count -- a comparison of two different loops AND two different owner
deals, not of one loop with itself. Every arm names the loop it ran in its
schedule receipt, so a run that quietly fell back to the batched loop cannot
pass as the dataflow one, and the child counts the overlap the loop achieved
(pairs started while a pair of an earlier batch was still in flight on the
same rank, and the widest set of batches in flight at once), so a dataflow
loop that never overlapped anything shows as a zero. At one rank the
self-delivery passthrough completes a receive when its tag has been sent, so
the same loop runs there and stays the CPU bit for bit.

**Which loop, and what it bought.** Measured as an A/B of the two loops on
one box, interleaved ([`../history/multi_process_step4e_dataflow_2026_09_05.md`](../history/multi_process_step4e_dataflow_2026_09_05.md)):
the dataflow loop runs the production collide faster where a slice spans a
group of ranks (medians 25% at thirty-two, 13% at sixty-four) and slower
where a rank holds whole slices (5% at sixteen), with best-of-six a tie
above sixteen. (First measured at 1.4x and 2x, before the collide stopped
rebuilding its buffers; a good part of that gap was GC.) The gate is
the reason, not the loop: a slice's pairs are a chain, so a rank holding a
WHOLE slice has nothing to overlap and the loop only adds a wake per hop,
while a rank holding a fraction of a slice has the rest of its group's pairs
and its owned planes to get on with. The stage waits the step set out to
remove did go (`wait_potentials` 0.84 s to 0.02 s at sixteen ranks); at that
layout the time reappears as idle in the chain. So the loop follows the
layout: **groups wider than one rank run the dataflow loop, whole slices per
rank the batched one**, and `batch_mode = :sequential` always runs the
batched one. The floor is then the chain and the warm-up, both priced in the
record.

## Step 4f: Gaussian-PIC on the same transport

Gaussian-PIC is PIC with a control variate: it deposits the same charge,
subtracts a reference Gaussian fitted to the SOURCE SLICE, solves the
residual on the same mesh with the same Green table, and adds the Gaussian's
kick back analytically. So it rides the slice-aligned transport unchanged --
the layout, the two migrations, the pair protocol, both loops, the leaves
that deposit and kick -- and what it contributes is a solver's three hooks:
its record, what its owner makes of the folded record, and the two leaves
that differ. That split is what the transport was factored for, and PIC's
bits are unmoved by it (the launcher child's PIC lines are byte-identical
across the change).

Three quantities are the SLICE's rather than one rank's part of it, and each
rides a stage the protocol already has:

- **The moments.** The reference Gaussian is fitted to the slice, so a rank
  cannot fit it to its own particles. Each member sends the fourteen SHIFTED
  sums of its part -- about the slice's globally-first member -- and the
  coordinator folds them in group rank order. Shifted sums are the only form
  in which such a fold is the serial sum, and a shared origin is what makes
  them comparable, which is why Gaussian-PIC needs the origin exchange at
  every pair where PIC needs it only under `grid_extent = :sigma`. The
  moments themselves come from one expression, shared with the undivided
  path, so a folded group and a whole slice compute the same thing.
- **The subtraction, on the plane's owner, after the fold.** With the default
  `neutralize = true` the amplitude is the DEPOSITED grid's total divided by
  the profile sums, and that total does not exist until the group's partials
  have been summed: a per-rank residual is not defined. So members deposit
  exactly what PIC deposits, and the owner subtracts -- the uncoupled
  profile or, when the mode says so, the coupled one with its three outer
  products.
- **The control-variate mode**, which decides both the mesh (the Gaussian's
  margin widens the source extent) and the kick (whether the analytic
  add-back runs at all). It is decided once, on the owner, from the folded
  moments, and travels in the grids message together with the moments, the
  slice's global count and the two boundary drifts -- because the field
  members need the SOURCE slice's moments for the add-back and are not in
  the source group.

The slice's global count comes free from the layout, which already carries
it; `nsource` read locally would have been the 4c kick-scale trap in three
more places. Gaussian-PIC rejects `interaction_grid`, so it has no node or
source-slice mesh and no per-pair path to keep.

Measured against the CPU policy: bit for bit at one rank on every option
route (the default subtraction, the coupled one, no margin, the
un-neutralised amplitude, and the sequential schedule), and 4e-16 to 1.4e-15
relative at two and four ranks -- the same parity class as PIC's. Spectral
is the only solver left, and step 4g divides it.

## Step 4g: spectral, and why it takes two routes

Spectral is the last solver, and it is the one with TWO collides. Which one
runs is `longitudinal_kick`, and they divide by different means because they
are different algorithms:

- The **6D map** (`longitudinal_kick = true`, the default and the production
  route) is order-DEPENDENT in exactly the way PIC's collide is: a slice is
  kicked by the pairs before it and then serves as a source at its kicked
  positions. It takes the slice-aligned transport, and `spectral_sliced.jl`
  is its batch loop.
- The **transverse-only map** (`longitudinal_kick = false`, a compatibility
  route) reads positions and only accumulates `px`/`py`, so slice-pair order
  is irrelevant. It stays on the home layout: no migration, no pair
  protocol, two collectives for the whole collide.

The earlier reading -- that spectral would divide on the home layout because
it "records `batch_mode = :order_free` and solves each source slice once" --
was taken from the transverse route alone and is wrong for the default one.

### The 6D map on the slice-aligned layout

Against the PIC protocol, what spectral changes is how little is negotiated
and therefore who solves. The Dirichlet box is ONE box for the whole collide
(`_spectral_box_drifted`, made global in this step), so there is no per-pair
geometry to reduce, no extents record, no owner deal and no Green table to
publish: stages 0 and 1 of the PIC loop do not exist here. And because no
geometry has to be agreed first, the solver of a directed interaction is the
FIELD slice's group head rather than a dealt third party. The source group
sends TWO drifted deposits -- the L and R planes of `_spectral_interaction!`
-- the field head folds and solves them, and the potentials it produces never
leave the group that needs them. Under `P <= nslices` that is two messages
per direction per pair and no broadcast at all, against the six a
source-solves scheme would send (three mesh arrays for each of the two drifted
planes).

Dealing the solve out is the whole point. At the production grid one DST
solve costs about four times the evaluation of the mesh it produces against a
slice (measured 271 us against 64 us at 64x64 with 6000 particles), so a
scheme that folded the deposit and let every rank solve it would leave the
dominant term undivided and cap the speed-up near 1.2x however many ranks
ran. Pairs in one wavefront batch share no slice, so the field heads of a
batch are distinct ranks and the batch's solves run at once.

Two more things the divided loop gets for free by taking every source deposit
and every virtual position BEFORE the pair kicks anything: the two directions
become independent of each other, and both slices can be kicked in place. The
undivided loop copies slice j only because it takes its deposits later.

`:grid_free` rides the same protocol with a different payload. Its planes are
sine-mode sums rather than a CIC deposit, and there is no mesh to send: the
head folds the modes and the field members evaluate them per particle, which
is already each member's own work. `_spectral_payload_planes` is the one
place that difference lives.

### The transverse map on the home layout

Two things have to cross the ranks and nothing else. Each source slice's
plane -- a deposit for `:grid`, mode sums for `:grid_free` -- is summed once
for the whole collide; then the `:grid` solves are dealt round-robin and
their meshes published by a second all-sum, each mesh written by exactly one
rank and zero everywhere else so the fold is that rank's value exactly. The
density-overlap luminosity needs both slices' global extents (one all-max for
the collide) and the product of two FOLDED deposits, which no rank can form
from its own share; those go in one all-sum per group of field slices, the
group sized so the buffer stays bounded however many slices a run carries.
The kick itself never leaves a rank: each evaluates the published meshes at
its own particles, in the same `i` order at any rank count.

### Lifting the ceiling: who is allowed to solve

The first cut of the 6D route gave every one of a pair's four solves to the
FIELD slice's group HEAD. That is optimal while a slice fits on one rank and
wrong the moment it does not: the head is one rank however wide the group
grows, the DST solve is the only step that does not split by particle, and it
is about 70% of the collide. So the number of ranks that could solve was the
number of SLICES, not the number of ranks -- and both beams' layouts are built
by the same rule from near-identical counts, so the direction-1 heads and the
direction-2 heads are the same set of ranks rather than two.

Measured, by reading each rank's own exchange receipt at 90,000 particles a
beam over fifteen slices:

| ranks | ranks that solved | busiest rank's planes |
|---|---|---|
| 8 | 8 of 8 | 120 |
| 16 | 16 of 16 | 60 |
| 32 | 20 of 32 | 60 |
| 64 | 23 of 64 | 60 |

At sixty-four ranks forty-one did no solving at all, and the busiest rank did
exactly as much absolute work as it had at sixteen. The distribution at
thirty-two was `60,0,60,0,...`: every odd rank idle, because `first(group)` is
always the even one.

The fix is to DEAL the four solves across the field group instead of pinning
them to its head -- one solver per (direction, plane), offset by the pair's
collision position so consecutive pairs pick different members. A group of one
gives that member both planes, which is the rule it replaces, so a run with
whole slices on whole ranks is unchanged message for message and bit for bit.
After it: 32 of 32 and 64 of 64 ranks solving, the busiest rank's share down
from 60 planes to 20.

**The timing comparison first published here has been WITHDRAWN.** It was taken
through the bare `collide!` entry, which defaults its scratch, migration and
pool refs to fresh ones per call while a `StrongStrongTask` holds them across
turns -- so every collide rebuilt every buffer it owns, a term invisible at one
rank and dominant at sixty-four -- and on a box carrying other work. It
reported 209 ms at sixty-four ranks where the identical collide measured 40.8
with the refs a task holds, and the "the curve turns up past thirty-two ranks"
conclusion drawn from it does not survive. The evidence for the ceiling that
DOES stand is the solve distribution above, which no clock enters.

Measured again through the refs a task holds, arms interleaved in one process,
90,000 particles a beam, fifteen slices, a 63x63 mesh (see the mesh-width note
below for why 63):

| ranks | widest group | ms |
|---|---|---|
| 1 | 1 | 379.4 |
| 2 | 1 | 286.1 |
| 4 | 1 | 179.0 |
| 8 | 1 | 100.0 |
| 16 | 2 | 55.6 |
| 32 | 2-3 | 37.4 |
| 64 | 4-5 | 39.0 |

Ten times the one-rank run at thirty-two ranks, and the curve FLATTENS there
rather than turning up -- which is what `4 * min(n1, n2)` = sixty concurrent
solves predicts for fifteen slices. Below sixteen ranks the deal changes
nothing, which is the point: a group of one is the rule it replaced.

Two constraints shape how a run should be laid out on a box with more CPUs
than slices. The shard rule (step 3a) rejects any rank count that does not
divide 64, so the choices are 1, 2, 4, 8, 16, 32 and 64; and the wavefront
gives at most `4 * min(n1, n2)` concurrent solves whatever the rank count is.
With fifteen slices that puts the useful point at 32 ranks rather than the 16
the head rule allowed, and THREADS take up the rest: a rank's per-batch solve
list is four items now instead of two, so four threads have independent solves
to run.

`4 * min(n1, n2)` is an upper bound on solve concurrency and nothing more: it
is NOT what binds this problem size. Measured through the refs a task holds,
fifteen slices reach 10.1x at thirty-two ranks and 9.7x at sixty-four, while
THIRTY slices -- which double the bound -- reach 8.5x at sixty-four rather than
more. The curve flattens near thirty-two ranks for a reason the bound does not
explain, and an earlier claim here that the slice count is the knob, drawn from
a contaminated benchmark, is WITHDRAWN. Attributing the flattening is the next
step, and the instrument exists: `_mp_collective_times` records per-kind wait
clocks that nothing has read for this route.

The tag keying stands on the bound being the slice count in principle: a pair's
tags are keyed by its position in the BATCH rather than in the whole collide,
because the global keying needed `ns1 * ns2 * 16` tags where the MPI standard
guarantees only 32767, which would have capped the slice count near 45 -- and
whatever binds the curve, a protocol should not be the thing that forbids more
slices.

Three constant factors went with it: the luminosity's extents now ride the
deposit wait and its mesh the payload wait, taking the batch from five
barriers to three; a field member evaluates straight out of the payload it
received instead of copying it into a workspace first; and the per-slice facts
come from a counts-only helper rather than `_divided_slice_plan`, whose
`owns_reference` cost two Allreduces per slice for a field spectral never
reads.

### The mesh width is a 4x lever, and it is invisible

A DST-I over `N` interior points has LOGICAL size `2(N + 1)`, and FFTW is fast
only when that number is smooth. Measured on one thread, `RODFT00` on an
`N x N` array:

| N | logical | largest prime | us |
|---|---|---|---|
| 63 | 128 | 2 | 39.2 |
| 64 | 130 | 13 | 67.5 |
| 95 | 192 | 3 | 143.8 |
| 96 | 194 | 97 | 735.3 |
| 127 | 256 | 2 | 166.7 |
| 128 | 258 | 43 | 663.2 |
| 255 | 512 | 2 | 634.0 |
| 256 | 514 | 257 | 5602.7 |

`grid=(256, 256)` costs 8.8x what `grid=(255, 255)` costs for a mesh one point
narrower, and `2(2^k + 1)` is twice a Fermat-ish number -- 17, 43, 97, 193, 257
-- so every power-of-two width is one of the slow ones, which is exactly what a
reader reaches for. The criterion is the largest prime factor and not the power
of two: `N = 48` (logical 98 = 2*7^2) beats `N = 47` (96). Since the solve is
most of the collide and nothing about the option says any of this,
`_spectral_note_grid_size` records it and warns, naming the nearby width whose
logical size is smooth. It starts at 48 points, below which the absolute cost
makes the note noise.

End to end on the same benchmark, moving the mesh ONE point from 64 to 63:
348 ms against 485 undivided (1.39x), 57.5 against 68.9 at sixteen ranks, and
39.7 against 47.4 at thirty-two. Against the pushed baseline's 227 ms at
thirty-two ranks, the two changes together are 5.7x.

### The global scalars both routes needed

The Dirichlet box is the beam's, not the shard's, and sizing it from a shard
would change every kick. `_lane_z_moment` already returned the folded scalar,
so what was left local was the rms COUNT and the extrema. The count is one
collective per beam per box; the extrema are one all-max. The non-finite
verdict runs BEFORE either -- taken on local data and agreed as an integer
count -- because a NaN handed to `_mp_allminmax`/`_mp_allmax!` comes back
different on different ranks, and a rank that decided from an exchanged bound
would throw while its peers walked into the next collective. Same rule the
PIC collide follows. `_spectral_luminosity_scale` divided by
`length(beam.rep)`, the 4c shard-count defect still live in spectral; it now
reads the scoped global count.

`_reject_undivided_solver` has nothing left to refuse, so it became a
deny-by-default tripwire: `_solver_divides` answers `false` for
`AbstractPoissonSolver` and `true` only where someone divided the collide and
said so. A solver added after the campaign refuses under a multi-process
policy until it is divided.

Measured against the CPU policy: bit for bit at one rank on both routes and
both methods, and last-bit agreement (~1e-15 relative) at two and four ranks.
Scaling of the 6D map at 90,000 particles per beam, fifteen slices and a
64x64 mesh, best of five on a shared box (which carried other work throughout, so these are best-observed rather than means): 451 ms undivided, 497 ms at one
rank, then 372, 230, 130 and 74 ms at two, four, eight and sixteen ranks --
6.7x over the one-rank divided run. At thirty-two ranks, more ranks than
slices, it turns back up to 227 ms; that regime is a todo row, not a claim.

### Step 4h: the dataflow loop for spectral

The batched loop walks every pair of a wavefront batch through the same stage
at the same time, so a rank waits at each stage for the slowest member of the
batch and idles whenever its own pairs are done. Nothing in the physics asks
for that -- a pair depends only on its two slices' PREVIOUS pairs -- so
`_spectral_collide_dataflow!` runs an event loop instead: scan this rank's
pairs in the collision order, run every stage whose receives have arrived, and
block on the union of what is outstanding only when a whole scan ran nothing.
It is PIC's step 4e applied to spectral's four stages, and it borrows PIC's
gate (`_pic_df_predecessors`) unchanged, because the hazard is the layout's and
not the solver's.

Two things are spectral's own. Its tags must separate every pair of the
COLLIDE, where the batched loop separates only the pairs of a batch: a batch is
a barrier, an event loop is not. And a pair whose luminosity mesh is degenerate
still kicks and skips only its luminosity, because spectral's verdict is about
the mesh and arrives after the kick -- PIC's is about the field extents and
arrives before, so PIC's dataflow loop skips the kick and the wording is not
transferable.

WHICH loop, measured rather than assumed, through the refs a task holds and
with the two arms interleaved in one process (90,000 particles a beam, fifteen
slices, a 63x63 mesh):

| ranks | widest group | batched | dataflow |
|---|---|---|---|
| 1 | 1 | **379.4 ms** | 387.7 |
| 2 | 1 | **286.1** | 304.1 |
| 4 | 1 | **179.0** | 191.9 |
| 8 | 1 | **100.0** | 113.7 |
| 16 | 2 | 69.6 | **55.6** |
| 32 | 2-3 | 38.2 | **37.4** |
| 64 | 4-5 | 40.8 | **39.0** |

The rule is the layout's, and it is the one 4e measured for PIC: a rank holding
a WHOLE slice has its pairs on that slice strictly in series and nothing to
overlap, so the event loop only adds a wake per hop and gives up the batched
loop's four independent solves a batch; once a slice spans a group each rank
holds a fraction of the chain's work and there is real independent work between
the hops. Groups wider than one rank get the dataflow loop -- 25% at sixteen
ranks, where a slice first spans two.

`_SPECTRAL_SLICED_LOOP` overrides the rule for a measurement or a pin. The two
loops are two independent implementations of one collide, so the suite holds
them to the same BITS rather than to the same answer: in process at one rank,
and under the launcher at one, two and four. That pin is the only thing that
would catch a dataflow gate letting a pair read a slice before its predecessor
kicked it, because the answer would still look plausible.

### Where the flattening near thirty-two ranks goes

`_mp_collective_times` keeps per-kind clocks and nothing had read them for this
route. Reading them settles it. One collide, 90,000 particles a beam, fifteen
slices, a 63x63 mesh, best of five with a barrier before each, wait kinds
averaged over the ranks and the local remainder taken as `wall - this rank's
MPI time`:

| ranks | wall | local | migration | collectives | idle at sync |
|---|---|---|---|---|---|
| 4 | 178.7 ms | 86.1 | 32.6 | 1.1 | 52.8 |
| 8 | 98.6 | 38.3 | 21.7 | 0.9 | ~28 |
| 16 | 54.1 | 20.7 | 14.8 | 1.0 | ~12 |
| 32 | 36.9 | 13.0 | 9.8 | 1.8 | ~9 |
| 64 | 39.5 | 9.9 | 8.6 | 4.9 | ~14 |

Three findings, none of them the one that was guessed.

**Local compute stops scaling, and the solve is why.** It falls by 1.59 from
sixteen to thirty-two ranks and by only 1.31 from thirty-two to sixty-four. A
pair offers four solves and they are dealt across the FIELD slice's group, so a
group can use at most two of its members per direction however wide it is: at
thirty-two ranks the groups are two to three wide and every member solves, at
sixty-four they are four to five and most do not. The per-rank solve load bears
that out -- the busiest rank carries 30 planes at thirty-two ranks and 20 at
sixty-four, a factor of 1.5 for a doubling. `4 * min(n1, n2)` bounds the solves
a BATCH offers; `2 * (number of groups)` bounds the ranks that can take them,
and that is the tighter of the two.

**The migration is flat.** Four all-to-alls a collide (`_mp_exchange_columns`,
two in and two out), 15 ms at sixteen ranks and 8.6 at sixty-four -- it barely
scales, and at sixty-four ranks it is the largest single MPI term, 22% of the
collide. It is latency-bound rather than bandwidth-bound: each rank holds 1,400
particles there and sends 1.2 KB to each of sixty-four peers, so an exchange is
4,096 tiny messages. Packing both beams into ONE exchange per direction halves
the message count; that is now done (below), and it did not move the clock,
which refutes the latency reading of this line.

**The rest is ranks waiting for each other**, and it grows as the local work
shrinks: local compute is 38% of the wall at sixteen ranks and 25% at
sixty-four.

A fourth thing turned up on the way. The collide issued 91 all-sums, and 72 of
them were not the collide's at all -- they were `longitudinal_slices` taking
two per slice, one for the member count and one for the centroid fold, which
every divided solver pays because they all slice. Folding them into one all-sum
over a length-`ns` vector is bit-identical (`_mp_allsum!` folds element by
element in rank order, which is what the scalar calls did) and takes the
collide to 35. It bought less than a millisecond, and THAT is the lesson: the
remaining 35 calls cost 141 us each where 91 cost 65, because a synchronising
collective's measured time is mostly the skew it absorbs. Removing calls
concentrates the same waiting into fewer of them. The count is still worth
cutting -- it is latency a bigger machine would pay for real -- but it was
never the flattening.

### Two structural fixes that did not move the clock, and what did explain it

Both were worth making and neither paid on this box. Recording that is the
point: the measurement is what says which of a plausible pair of levers is
real, and here it said neither.

**One migration exchange for both beams.** `_pic_sliced_migrate_pair_in` and
`_pic_sliced_migrate_pair_out!` replace the per-beam pair of calls. Eight rows
travel instead of seven -- six coordinates, the slice, and the beam -- the
counts fold in ONE `_mp_allsum!` over an `(ns1 + ns2, P)` matrix, and the
receiver buckets by the key `(beam - 1) * (maxns + 1) + slice` with a stable
sort, so a rank's particles land in the same order they landed in before.
Exchanges a collide: four to two. PIC, Gaussian-PIC and spectral all use it,
because all three share this transport. Bit-identical at one and four ranks.
Time at sixteen ranks: 15.11 ms before, 14.80 after. At thirty-two: 9.65
before, 9.76 after. That is noise, and it is the answer to "the migration is
latency-bound on 4,096 tiny messages" -- if it were, halving the messages would
have shown. The clock there is skew: the same collide reports a min wait of
1.09 ms and a max of 37.57 at sixteen ranks. The exchange is mostly ranks
arriving at different times.

**The owner deal rotates per slice now.** `_spectral_sliced_solvers(group, k)`
picks the two solvers as `group[k % g + 1]` and `group[(k+1) % g + 1]`, and `k`
used to be the pair's index in the global pair order. A slice's pairs are
scattered through that order, so `k % g` over them is not a rotation -- some
group members drew the deal repeatedly and others never. `_spectral_slice_pair_positions`
numbers each pair by its position among the pairs on its OWN slice, one per
direction, and hands those in. The solve spread at sixty-four ranks goes from
7-20 planes (2.9x) to 12-16 (1.33x). The wall: 41.2 ms against 39.5 before --
unchanged. So the solve imbalance was not binding either. It is still the
right shape; it just means the busiest rank was not the clock.

**What does explain it: the chain.** A collide runs `2 * nslices - 1` batches
in sequence because the longitudinal map is order-dependent, and the batch
count -- not the work in it -- is what the wall tracks. At sixty-four ranks,
same particle count and mesh, varying only the slice count:

| slices | batches | wall | per batch | compute in it |
|---|---|---|---|---|
| 8 | 15 | 27.1 ms | 1.81 ms | ~0.35 |
| 15 | 29 | 42.0 | 1.45 | ~0.37 |
| 30 | 59 | 225.6 | 3.82 | ~1.03 |

Halving the slices from fifteen to eight cuts the work per rank by about half
and the wall by 36%; a work-bound collide would have gone to ~21 ms and a
chain-bound one to ~27. It went to 27.1. The per-batch cost is roughly constant
and roughly ten times the compute inside it: three barriers and their skew,
paid `2 * nslices - 1` times. The luminosity is a measurable but minor part of
that -- 42.6 ms with it against 37.1 without at sixty-four ranks, 13% of the
wall, 0.19 ms of the 1.45 -- so its extra round trips are not the per-batch
cost either.

This is the ceiling for the sliced route as specified. The chain length is
physics: slice `i` of one beam must see slice `j` of the other after the
kicks that precede it. Shortening it means changing what the solver computes,
not how the ranks are arranged, and that is not a performance decision to make
here. The levers that remain inside the current contract are per-batch --
fewer barriers per batch, or overlapping a batch's sends with the next
batch's local work -- and the dataflow loop already takes the second of those
as far as the gate ordering allows.

## The CPU, MPI and CUDA consistency statement

Three execution modes, and the relation between them is asserted in two
places rather than three, because the third follows:

| pair | relation | measured by |
|---|---|---|
| CPU vs MPI, tracking | **bitwise**, at every rank count that divides the chunks | the suite's multi-process section, under a launcher, comparing gathered shards against a single-process run |
| CPU vs MPI, scalar diagnostics | agreement to the accumulation difference between one serial sum and P of them: 1.7e-14 at two ranks, 8.7e-14 at four | the same section, comparing a divided run's moment row against a single-process one |
| CPU vs MPI, strong-strong collides | **bitwise at one rank**; across rank counts the parity class -- the soft-Gaussian's aggregates to 5e-16; PIC's deposits fold over a slice's group of ranks in a fixed order (step 4d), measured 6e-15 worst over the option routes at 2 and 4 ranks and 9e-14 on a 64-slice, 4096-pair arm | the same section: the child's luminosity series, fingerprints and per-route lines against a single-process run at 1, 2 and 4 ranks; for PIC also `StrongStrongPICMultiProcessConsistencyContract` |
| CPU vs CUDA | agreement to the contract's tolerance | `ElementTrackingBackendConsistencyContract` and `validation/tracking_backend_consistency.jl`; for the collides the two `StrongStrong*BackendConsistencyContract`s |
| MPI vs CUDA | the same tolerance, by composition | not measured directly, and cannot be: the multi-process policy is CPU storage only, so no rank holds a CUDA beam. For PIC the composition is carried as a number: `StrongStrongPICMultiProcessConsistencyContract` runs both legs on the same beams and reports the triangle bound |

The bitwise half is the stronger claim and the one the shard rule exists to
buy. It is also the half that would decay silently: a tolerance would absorb a
fold quietly rearranged by a later change, where a bitwise comparison names it
on the next gate.

For the PIC collide the whole statement is one public object,
`StrongStrongPICMultiProcessConsistencyContract` (step 4c). It builds the PIC
backend contract's beams and task; runs them under
`CPUThreadsExecutionPolicy` in the calling process; launches
`src/contracts/mpi_pic_consistency_child.jl` at each requested rank count,
where every rank draws the same beams under the multi-process policy (whole
draw, own shard -- bit-identical to the undivided beam by construction), runs
the same task divided and gathers both beams onto rank 0; and compares. One
rank must match bit for bit, every other count to `rtol`/`luminosity_rtol`.
With `cuda = true` it then runs `StrongStrongPICBackendConsistencyContract` on
the same beams and reports the MPI-to-CUDA bound as the sum of the two legs'
distances from the CPU. A rank count is a property of a launched process, so
the contract needs the launcher command and a project that carries `MPI`;
without a launcher it returns `:skipped` naming the legs it did not run, and a
requested CUDA leg the device cannot run downgrades the result to `:skipped`
too -- the three-way claim is not made on two legs.

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
driver on the main thread, never from inside `_run_logical_workers`. The
tripwire landed in step 4b: `_record_collective!`, which every seam function
calls before it communicates, throws a named error at more than one rank
when called off the main thread, so a collective that ever reaches a worker
fails loudly instead of corrupting the communicator or hanging.

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
