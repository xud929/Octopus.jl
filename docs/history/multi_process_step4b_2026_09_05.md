# The Strong-Strong Task Across Ranks — Step 4b, 2026-09-05

Step 4a divided the soft-Gaussian collide and left the task around it
refusing: its turn loop, its line observers, its luminosity channel and its
run artifact were the wiring still to do. This is that wiring. Most of it was
already in place from steps 3b and 3c -- the observers reduce or gather, the
artifact is rank 0's, the luminosity the collide returns is already the
global sum -- and the work turned out to be about the one thing no earlier
step had met: a run that holds TWO beams.

## One shard per beam

Every earlier consumer of the shard scope held one beam. The scope stored one
`(offset, global_n)`, and `_mp_current_shard(local_n)` returned it whatever
count it was asked about, which was harmless with one beam and wrong with two:
a strong-strong task's beams may differ in size, and the second beam was
handed the first beam's offset. Under that offset its radiating elements
would key their draws on the wrong global indices, its apertures would file
losses under the wrong particle ids, and the collide's shift origin -- the
slice's globally-first member, found by a minimum over global index -- would
be looked for on the wrong rank.

Keying by local count is the obvious repair and is wrong in principle: beams
of 256 and 257 particles give rank 1 of 2 the same 128-particle shard at
different offsets, and a rank that guessed would guess silently. The scope now
holds one entry per beam keyed by the identity of its `Phase6DRep`, the object
every consumer already has in hand -- `Beam` is immutable and tracking mutates
its arrays in place, so a beam's representation is the same object for the
whole run. `_with_beam_shards(reps...)` resolves each beam's shard at the run's
entry, one integer collective each in a fixed order, and `_mp_current_shard(rep)`
reads the scope; a representation the run did not scope pays the collective
rather than inheriting another beam's answer, and every rank scopes the same
beams, so that miss is symmetric. The count-keyed form survives for callers
holding only an array, and throws on the ambiguous case rather than guess.
Every production reader moved to the representation form: the tracking
task's three sites, the strong-beam luminosity fold, the snapshot observer,
the slicing statistics (which now take the shard from their caller's
representation), the slice shift origin, and the soft-Gaussian's slice plan.

## One tracking context per beam

`TrackingContext.index_offset` is what makes a divided run draw the same noise
as an undivided one, and the strong-strong turn loop handed both lines one
context. Each line now tracks under its own beam's offset -- read from the
scope once per `execute!`, no collective -- so a radiating element or an
aperture in line 1 keys on beam 1's global indices and one in line 2 on beam
2's. The collide takes the turn-only context and reads its offsets from the
scope, as 4a built it to.

## What refuses, and what the run looks like

The blanket refusal is gone. In its place, at more than one rank: every solver
but the soft-Gaussian refuses -- PIC, Gaussian-PIC and spectral are step 4c
onward, and each refuses at its CPU collide entry as well as at the task's
preflight, so a bare `collide!` cannot collide one rank's shard and call it the
beam -- and a line ACTION in either line refuses, the same callback argument
the tracking task makes. `:equal_count` slicing refuses from 4a. Everything
else runs: line observers reduce (moment, BPM) or gather (snapshot), the
artifact is opened, written and closed by rank 0 only, and the luminosity
channel gets the collide's global sum through the root-only push.

The whole run -- preparation, the turn loop, the observers' flushes and the
artifact's close -- sits inside one policy scope entered once (one
communicator receipt per run), because any of those may issue a collective
and a collective outside the scope is a silent no-op (the 3c lesson). The
failure path issues none: probe-row pushes and the artifact finalize are
root-only, so a rank that throws cannot strand its peers from inside
`finally`.

## Two defects the design review found, both on the tree that closed 4a

The plan was reviewed adversarially before it landed (four lenses, each
finding refuted or confirmed against the committed tree), and two of the
confirmed findings were defects already present, not risks of the plan.

**The benchmark's single shard.** `profiling/benchmark_collide_cpu.jl` scoped
one shard -- the electron beam's -- and collided it with a proton beam of a
different size (640,000 against 256,000 at the production point). The
single-slot scope handed the proton beam the electron beam's `(offset,
global_n)`, so every divided measurement before this step ran the proton
beam's lane folds and shift origins at the wrong offset. The physics was not
wrong -- a shifted moment about a zero origin is the same moment -- and the
timings stand, but the 4a claim that a divided run's slice boundaries are bit-
identical to an undivided run's was only ever measured on the child's
equal-size pair. The benchmark scopes both beams now, and the 256/192 child
pair is the first unequal one under a launcher.

**The slicing's rank-local refusals.** `longitudinal_slices` refused an empty
representation, or one whose particles were all dead, on this rank's own
count, before its first collective. A shard can legitimately be either -- a
beam smaller than the chunk count leaves empty shards, and an aperture can
kill one rank's whole run of it -- and a rank that refused while its peers
went on into `_live_z_stats` left them blocked in the first all-sum. The
review's verifier reproduced the hang under a launcher at two ranks. Both
decisions now read the whole beam's counts (one integer all-sum each, free at
one rank), and the child kills all of rank 1's shard and then the whole beam:
every rank slices the first and every rank refuses the second.

Three more things the review changed. The count-keyed shard lookup's first
draft threw on a coincidence of THIS rank's counts -- two beams whose shards
happen to be the same size on one rank -- which would have thrown on that rank
and proceeded on the others: a deadlock at the next collective. It now decides
from the scope's global sizes, which every rank holds alike. The `:funneled`
tripwire the design note promised in step 2 exists: every seam function
records its collective before issuing it, and that record throws off the main
thread at more than one rank. And the launcher test has a watchdog, because
every one of these hazards presents as ranks blocked in a collective, and a
rank that blocks without exiting would have hung the suite rather than failed
it.

## Measured

The launcher child runs a strong-strong task on two beams of DIFFERENT sizes
(256 and 192 macroparticles, both whole-chunk shards at 1, 2 and 4 ranks),
each line a linear map, a radiating element that draws per particle keyed on
the beam's global index, a line-placed moment observer, the soft-Gaussian
collision (five equal-area slices) and a second linear map; three turns, with
the run artifact. Rank 0 prints what the artifact recorded and both beams'
whole-beam fingerprints (through the collectives, the 4a lesson).

| ranks | luminosity series (3 turns) | moment rows in the file | beam fingerprints vs one rank | moment rows vs one rank |
|---|---|---|---|---|
| 1 | 1.59783291871563e10, 474538.26065186807, 137662.60978584387 | 3 and 3 | reference | reference |
| 2 | **identical, bit for bit** | 3 and 3 | 1.9e-16 | 2.1e-14 |
| 4 | **identical, bit for bit** | 3 and 3 | 2.1e-16 | 1.8e-14 |

A second pair sized so every rank's slices enter the CHUNKED moment and kick
branches at 1, 2 and 4 ranks (98304 and 81920 particles, three slices -- the
4a segfault appeared only when a divided run first met a slice big enough to
chunk, so a fixture below that size is a different test), signatures and the
luminosity series only, two turns:

| ranks | luminosity series vs one rank | beam fingerprints vs one rank |
|---|---|---|
| 1 | 6.164704175434506e12, 1.8773535060009617e8 | reference |
| 2 | 3.2e-16 | 4.3e-16 |
| 4 | 4.8e-16 | 3.6e-16 |

The chunked branches move the luminosity by last bits where the small pair's
came out identical, which is the 4a price (5e-16) and not a surprise: the
per-slice moment sums are folded by member-list position, which no fixed
partition aligns with.

The one-rank MPI run reproduces this process's `CPUThreadsExecutionPolicy`
run bit for bit -- coordinates of both beams, the luminosity series, both
observers' rows -- which is the campaign's literal requirement, and the suite
pins it both in-process and through the launcher. The luminosity itself came
out bit-identical across rank counts here (the chunk-aligned folds and the
per-collide global sum), better than the 5e-16 the collide's aggregates were
priced at in 4a; the fingerprints move by last bits and the moment rows by
the accumulation difference between one serial sum and P of them (3b priced
1.7e-14 at two ranks on a beam of the same size), the parity tolerance class
the design prices. The refusals fire at two and four
ranks and not at one, checked by the child at every count.

## Performance

Not re-measured here, and deliberately: the task adds no collective of its
own to what 3a and 4a already priced. Per `execute!` it resolves the two
shards (two integer all-sums); per turn it runs the lines' tracking (3a: no
communication), the line observers' reductions (3b: one all-sum per observer
per turn), the collide (4a and the wavefront record: 222 collectives at the
production point), and one root-only luminosity push. The rank scaling of
the collide ([`multi_process_strongstrong_scaling_2026_09_04.md`](multi_process_strongstrong_scaling_2026_09_04.md),
[`soft_gaussian_wavefront_cpu_2026_09_04.md`](soft_gaussian_wavefront_cpu_2026_09_04.md))
and of the tracking ([`multi_process_tracking_scaling_2026_09_04.md`](multi_process_tracking_scaling_2026_09_04.md))
therefore bound the task's, and a task-level curve is owed when a solver that
adds per-pair traffic (step 4c) lands.

## What is left

Steps 4c onward: PIC, Gaussian-PIC and spectral, which need per-slice-pair
grid all-sums and global extrema for mesh sizing. When the last solver
divides, the campaign's targeted neighbour audit falls due (its accumulated
blast radius is in the ledger's audit row); this step adds to it the shard
scope's new shape and every reader that moved to the representation form.

Two hazards the review named and this step leaves as they are, recorded so
they are not rediscovered: a beam built WHOLE on every rank under an ordinary
policy (`Beam(n, CPUThreadsExecutionPolicy())`) passes the shard verification
whenever the chunk count divides P times n, because the ranks' counts sum to
P times n and the rule then gives each rank exactly n -- the run would treat
P copies as one beam of P times n particles; and a failure on rank 0 alone
during preparation leaves the other ranks in their first collective until the
launcher aborts the job. The first wants the sharded constructor to leave a
mark the verification can ask for; the second wants one broadcast after
preparation. Both are small; neither is owed by 4b.
