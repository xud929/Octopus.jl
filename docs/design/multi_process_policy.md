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
| `_mp_reduce_scatter_blocks!(A, nblocks)` | `1:nblocks` | Alltoall laid out so each rank receives whole blocks, then the rank-ordered fold of its own; returns the blocks this rank owns (step 4c performance phase) |
| `_mp_allgather_blocks!(A, nblocks)` | `A` | the inverse: each rank's owned blocks to every rank |
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
task refuses the same two), `:equal_count` slicing (4a), and every solver but
the soft-Gaussian -- PIC, Gaussian-PIC and spectral are step 4c onward, and
each refuses at its CPU collide entry as well as at the task's preflight, so
a bare `collide!` cannot collide one rank's shard and call it the beam.

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

## The CPU, MPI and CUDA consistency statement

Three execution modes, and the relation between them is asserted in two
places rather than three, because the third follows:

| pair | relation | measured by |
|---|---|---|
| CPU vs MPI, tracking | **bitwise**, at every rank count that divides the chunks | the suite's multi-process section, under a launcher, comparing gathered shards against a single-process run |
| CPU vs MPI, scalar diagnostics | agreement to the accumulation difference between one serial sum and P of them: 1.7e-14 at two ranks, 8.7e-14 at four | the same section, comparing a divided run's moment row against a single-process one |
| CPU vs MPI, strong-strong collides | **bitwise at one rank**; across rank counts the parity class -- the soft-Gaussian's aggregates to 5e-16, the PIC deposit's chunk fold is keyed by member-list position so its grids differ by accumulation order, measured 7e-15 worst over the option routes and 9e-14 on a 64-slice, 4096-pair arm | the same section: the child's luminosity series, fingerprints and per-route lines against a single-process run; for PIC also `StrongStrongPICMultiProcessConsistencyContract` |
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
