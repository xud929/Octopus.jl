# The Soft-Gaussian Collide Across Ranks — Step 4a, 2026-09-04

Step 3 divided a tracking task. Strong-strong is a different shape: both beams
are sliced and every slice pair interacts, so the reductions are per SLICE
rather than per beam, and they happen inside a loop whose earlier iterations
change the beams the later ones read. This divides the first of the four
solvers, in the order Phase 0 decided: soft-Gaussian, then PIC, then
Gaussian-PIC, then spectral.

## What had to span the ranks

Five reductions, and the fifth is the one that was easy to miss.

1. **The longitudinal statistics** — live count, extrema, mean, sigma. Count and
   extrema are order-independent and exact at any rank count. Mean and sigma go
   through the 4096-lane fold, which now carries the shard offset so a
   particle lands in the lane it would have occupied undivided, and the ranks
   exchange lane partials rather than scalars.
2. **The histogram the equal-area boundaries are cut from.** Integer counts, so
   the sum is exact.
3. **Each slice's transverse moments**, with a shared shift reference.
4. **Each slice's weight and centroid**, which are its share of the BEAM.
5. **The luminosity**, summed once per collide rather than once per pair.

The boundaries matter more than the tolerances elsewhere in this campaign.
They decide which particle is in which slice, so a disagreement between ranks
is not a small error but a different collision. They come out bit-identical.

## The shift reference

`_slice_transverse_moments` computes shifted moments about the slice's first
member, for conditioning. Two ranks shifting about different origins produce
sums that cannot be added, so every rank must use the same one, and it should
be the same particle an undivided run used: the slice's globally-first member.

Two collectives and no gather. The ranks agree on WHICH particle it is with a
minimum over the global index each holds, and then the one rank that owns it
contributes its four coordinates while the others contribute zeros, so the sum
is that rank's values exactly.

The empty-slice early return moved to the GLOBAL count for the same reason a
collective always does: a rank returning early because its own shard held no
member of a slice would leave its peers waiting at the next message.

## The defect the measurement found

The first divided collide returned luminosities of 2.56e11, 2.62e11 and
2.85e11 at one, two and four ranks — 2% and 11% out, far past any tolerance.
The longitudinal statistics were already exact and agreed to the bit, which
localised it immediately: the equal-area boundaries are not cut from those
statistics but from a HISTOGRAM of the beam, and each rank was binning its own
shard. At two and four ranks the boundaries bunched into the top of the
distribution and left whole slices empty, and the weights showed it plainly:

```
P=1  weight 0.198 0.200 0.198 0.201 0.202
P=2  weight 0.397 0.400 0.202 0.000 0.000244
P=4  weight 0.798 0.202 0.000 0.000 0.000244
```

One integer all-sum fixed it. The lesson is the one the statistics themselves
illustrate: a quantity being global is not the same as the quantity DERIVED
from it being global, and the derivation here went through a different
reduction that had to be found separately.

## Measured

4096 macroparticles per beam, five equal-area slices, one collide:

| ranks | slicing | luminosity | max kick | rms kick |
|---|---|---|---|---|
| 1 | reference | reference | reference | reference |
| 2 | **identical, bit for bit** | 4.8e-16 | 4.9e-16 | 1.1e-16 |
| 4 | **identical, bit for bit** | 4.8e-16 | 2.5e-16 | 1.1e-16 |

relative to the single-process run. The per-particle kicks agree to 9.6e-15 of
the beam's own scale at two ranks. That is better than the moments' own
agreement of about 1e-15 relative would suggest, because the aggregate
quantities average the per-slice differences out.

One measurement artifact, recorded because it looked exactly like a defect: an
earlier fingerprint took the root-mean-square over the LOCAL shard and reported
a 1.6% disagreement that was entirely its own. A quantity compared across rank
counts has to be a quantity of the beam.

## What refuses

`:equal_count` slicing orders the whole beam and cuts it into equal parts,
which is a sort and not a fold: a rank can order its own shard but cannot
learn where its particles sit in the beam's order without moving them. It
refuses, naming the four methods that do run divided. Every other method sizes
its boundaries from the longitudinal statistics or the histogram, both of
which are now global.

`StrongStrongTask` still refuses outright. Its turn loop, observers and
artifact are the wiring step 4b adds; the solver is reachable divided through
`collide!`, which is where it is measured here. PIC, Gaussian-PIC and spectral
are steps 4c onward, and they need what soft-Gaussian did not: grid all-sums
per slice pair, and global extrema for mesh sizing.
