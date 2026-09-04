# Dividing a Tracking Task's Diagnostics — Step 3b, 2026-09-04

Step 3a divided the tracking; this divides the accounting that spans
particles, as far as it can be divided. The ledger left one question open
here, to be measured before choosing, and the measurement chose against the
option that looked more attractive.

## The decision the ledger left open

The moment observer's mean was a left-to-right accumulation over the whole
array. That cannot be divided: a shard's partial starts from zero where the
undivided sum would have started from everything before it. Two ways out
were available and both were measured.

**Option A, the fixed chunk grid.** Fold these reductions the way every other
count-invariant reduction in the CPU stack folds, on `_REDUCTION_CHUNKS`
chunks summed in chunk order. A rank owning whole chunks then reproduces the
undivided sum bit for bit — the same trick that makes the luminosity fold
exact across ranks.

It was implemented, and the suite rejected it. A chunk grid partitions the
SLOTS, and a masked beam has more slots than survivors, so the grid over a
beam containing dead particles is not the grid over the survivors alone. The
testset "Lost particles are excluded from every reduction" compares the
masked row against a survivors-only row with `==`, and the two stopped
agreeing in the last bits:

```
Expression: row_masked == row_reference
  Evaluated: [7.0, 1.962779070159072e-6, 2.0752527785736995e-6, …]
          == [7.0, 1.962779070159072e-6, 2.075252778573699e-6,  …]
```

Adopting it would also have moved recorded means by up to 206 ulps at the
production size (measured: 3.3e-14 relative on a near-zero mean over
1,024,000 particles; 1.8e-14 on an offset one).

**Option B, the local serial sum with a cross-rank fold, chosen.** Each rank
accumulates its own shard exactly as before and the ranks' partials fold in
rank order. At one rank this is byte for byte the number the undivided run
produced, so nothing recorded moves and the masking invariant is untouched.
Across ranks it agrees with an undivided run to the accumulation difference
between one serial sum and P of them.

Measured on a 256-particle beam, three turns, comparing a divided run's
moment row against a single-process one:

| ranks | agreement with one rank | worst ulps |
|---|---|---|
| 2 | 1.7e-14 relative | 112 |
| 4 | 8.7e-14 relative | 656 |

That is the campaign's own posture, which prices cross-rank agreement at the
parity tolerance class and reserves bitwise for the folds where alignment
makes it cheap. Here it is not cheap: it costs an invariant about masking
that is worth more.

## What divides now

- **Moment observers**: means and central moments reduce across the ranks,
  and the live count is a global integer sum, so the denominator is the
  beam's and not the shard's.
- **Beam position monitors**: the same, for the two centroid components, on
  both the masked and unmasked paths.
- **Loss accounting**: the counts — particles, live, dead, logged,
  unattributed, and the per-aperture tally — are summed across the ranks, and
  the summary is printed and warned about by rank 0 only, so one run produces
  one report. The crash path deliberately does NOT globalize: it runs while an
  exception is in flight, the ranks may not agree on having thrown, and a
  collective issued by some of them would hang the rest.
- **The run artifact**: one run, one file, opened and written by rank 0. Every
  rank still runs every observer, because the reductions are collectives and a
  rank that skipped one would hang its peers; the other ranks simply hold no
  file, so each write no-ops.

## What still refuses, and why

Everything that needs the whole beam's PARTICLES in one place, or that runs
code Octopus cannot reason about: task actions and line hooks (arbitrary
callbacks over the rep they are handed), apertures (their per-particle loss
rows key on the index the rank sees), and per-particle observers such as
`CoordinateSnapshotObserver` (one row per particle). Each needs a gather the
collective seam does not have. Which observers are per-particle is a declared
property beside each observer, not a guess at the refusal site.

## Measured under a launcher

A 256-particle beam through a radiating line, three turns, with a moment
observer and a run artifact, at 1, 2 and 4 ranks:

| ranks | moment rows in the file | loss counts |
|---|---|---|
| 1 | 3 | 256 particles, 4 dead, 252 live, 4 unattributed |
| 2 | 3 | identical |
| 4 | 3 | identical |

The row count is the proof that only rank 0 wrote: every rank runs the
observer, so a run where every rank also wrote would leave P rows per turn.
The loss counts are identical because they are integers, summed across the
ranks, and the four poisoned particles were placed at global indices that
fall in different ranks' shards at both 2 and 4.
