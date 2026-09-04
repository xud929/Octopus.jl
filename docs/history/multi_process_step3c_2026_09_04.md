# Per-Particle Output Across Ranks — Step 3c, 2026-09-04

Step 3a divided the tracking, 3b the diagnostics that reduce the beam to
scalars. This divides the ones that emit a row per PARTICLE, which cannot be
reduced at all, only moved. It also fixes a defect in 3b that only became
visible once something was moved.

## A seventh collective

The seam's six operations all turn many numbers into few. Per-particle output
turns none into none: an aperture writes a row for each particle that died, a
snapshot observer a row for each particle each turn. So the seam gains
`_mp_gather_rows`, which collects every rank's rows onto rank 0 in rank order
— which is global particle order — and leaves the other ranks an empty matrix
with the same columns. Rank 0 only, because rank 0 owns the file; gathering
onto every rank would multiply the traffic by the rank count to no purpose.

Both consumers are sparse in practice. A loss row exists only for a particle
that died, and a snapshot's `npart` is a small window by convention, so the
message stays small even at the production size.

## The global particle id

The aperture's slot table has one column per particle THIS RANK holds, and its
recording path was indexed by the particle id — which step 3a made global. The
two disagree on a shard by exactly the shard offset, which the tracking context
already carries. So the slot is now `particle_id - ctx.index_offset` and the id
written to the file is the global one, restored by the same offset when the
rows are built. In a single-process run the offset is zero and neither
expression changes.

The snapshot observer's `npart` counts the whole beam, as it always did: each
rank contributes the part of `1:npart` its shard covers, and the rows carry the
global id.

## The defect this found

The gather returned only rank 0's rows. The cause was not the gather: the
post-run accounting in `execute!` — the loss summary, the report, the artifact
write — ran AFTER the `_with_execution_policy` block closed. Outside that
scope the collectives see a communicator of one, so each did nothing and every
rank kept its own shard's answer.

That applies equally to the loss summary step 3b globalized at exactly that
spot, which was therefore never reached by `execute!`. Step 3b's own test
called `_global_loss_summary` inside a policy scope and passed while the path
it was meant to protect did not have one — a test of the function rather than
of the route to it. The accounting now runs inside the scope, and the check is
the summary written INTO the file rather than one computed beside it.

Measured after the fix, a 256-particle beam through a tight elliptical
aperture with a 12-particle snapshot observer, two turns:

| ranks | loss rows in the file | loss ids | snapshot ids | summary in the file |
|---|---|---|---|---|
| 1 | 42 | reference | 12 ids x 2 turns | 256 particles, 42 dead, 214 live |
| 2 | 42 | identical | identical | identical |
| 4 | 42 | identical | identical | identical |

Before the fix the same run recorded 42, 17 and 9 rows at 1, 2 and 4 ranks —
each rank 0's shard alone, and each looking like a plausible answer.

## A second thing the tests caught

Moving the accounting inside the scope re-entered `_with_execution_policy`,
which ACTIVATES: it opens the communicator and records the receipt naming it.
Two entries meant two receipts for one run, and the passthrough testset --
which pins exactly one communicator receipt per `execute!` -- failed on the
gate. The receipt is the evidence that the rank count came from the
communicator, so "how many" is part of what it asserts. `execute!` now
activates once and enters the scope twice, around the tracking and around the
accounting.

The crash path stays outside every scope, and that is what makes it safe: an
exception is in flight, the ranks may not agree on having thrown, and a
collective issued by some of them would hang the rest. Outside the scope every
collective is its serial passthrough, so a crashed run flushes what its own
rank saw instead of deadlocking trying to agree.

## What is left

Actions, and only actions. An action is a callback the user wrote, handed the
rep this rank holds; Octopus cannot know whether it means to see a shard, and
one that computes a global quantity from a shard would be quietly wrong. Line
OBSERVERS are Octopus's own and divide, so the refusal now distinguishes a
line carrying an observer from one carrying an action, where step 3b refused
both.

Strong-strong tasks still refuse outright; that is step 4.
