# Dividing a Tracking Task Across Ranks — Step 3a, 2026-09-04

Step 3a of the multi-process campaign: a `TrackingTask` runs across MPI ranks,
each holding a shard of the beam. The policy, the communicator handshake and
the collective seam landed in step 2
([`../design/multi_process_policy.md`](../design/multi_process_policy.md));
this is their first consumer. The accounting that spans particles is step 3b
and is refused until then.

Not a weak-strong-only feature, despite the campaign's phrasing: there is no
separate weak-strong task. `TrackingTask` is the general one, and a
strong-beam element is one element kind a line may contain, so 3a divides
every tracking run.

## What was built

- **The shard rule**: a contiguous run of whole reduction chunks, so the
  chunk-ordered folds the CPU stack already uses extend across processes
  unchanged. The rank count must divide `_REDUCTION_CHUNKS`; one that does not
  is rejected with the list of counts that do.
- **Derived, not stored**: the shard is recovered at a run's entry by summing
  the ranks' particle counts and re-deriving the rule, and the local count is
  checked against it. A beam split some other way fails there instead of
  tracking with the wrong random streams.
- **Global index keying**: `TrackingContext` carries an `index_offset`, zero in
  every single-process run, so a rank's particles draw the streams their global
  indices name.
- **Beam construction**: `Beam(n_global, MultiProcessExecutionPolicy(), …)`
  draws the whole beam and keeps this rank's slice. Drawing per rank is not
  equivalent — standardization is a whole-array mean and variance — and no
  arrangement of collectives recovers Julia's pairwise sum over the full array.
- **The strong-beam luminosity fold crosses ranks**: each rank folds the chunks
  it owns and the partials go back into chunk order through one all-sum of
  `_REDUCTION_CHUNKS` numbers, whatever the beam size.
- **A narrowed refusal**: step 2's blanket refusal becomes a list — observers,
  actions, line hooks, a run artifact, apertures — each named in the message.

## Measured

A 256-particle beam through a line carrying `LumpedRad` with excitation on,
three turns, built and tracked through the public constructor and `execute!`,
run under MPICH_jll's `mpiexec`. Every coordinate is printed at full precision
and the shards are concatenated in rank order, so the comparison is a string
comparison and no arithmetic touches it.

| ranks | shard offsets | tracking vs single process | luminosity vs single process |
|---|---|---|---|
| 1 | 0 | identical | identical |
| 2 | 0, 128 | **identical, bit for bit** | **identical, bit for bit** |
| 4 | 0, 64, 128, 192 | **identical, bit for bit** | **identical, bit for bit** |

The radiating line is the load-bearing part of that: `LumpedRad` draws six
normals per particle per turn keyed on the particle index, so a shard that kept
its local indices would track a different beam here while agreeing everywhere
else. The suite carries the same property without a launcher, by tracking a
64-particle beam whole and then tracking its second half with an offset of 32
and requiring the halves to match, with an anti-vacuity arm showing they do
not match without the offset.

## Two defects the tests caught, both in the safe direction

- The refusal's line-hook condition was inverted, so an ordinary task with no
  hooks at all was refused. Caught the first time a divided task ran.
- The multi-rank check labelled every line rank 0, because it read the rank
  accessor outside an execution scope, where that accessor correctly reports a
  single process, and then because it read the communicator before Octopus had
  initialised MPI. Both were in the instrument, not the code, and both would
  have made a two-rank comparison pass while comparing one rank with itself.

## What is not verified

Rank counts above 4 for the bitwise comparison, though the shard rule is
checked arithmetically for every divisor of the chunk count up to 64 and for
beams smaller than the chunk count. Cross-rank behaviour of observers, losses
and the artifact, which is step 3b and is refused rather than assumed.
Performance, which is measured separately.
