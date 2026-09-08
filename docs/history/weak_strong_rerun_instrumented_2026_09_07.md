# The weak-strong arms re-run with the instrument — 2026-09-07

The 2026-09-06 production benchmark
([`production_benchmark_2026_09_06.md`](production_benchmark_2026_09_06.md))
derived the weak-strong per-turn cost by differencing the total wall times of
four separate runs, and concluded the 64-thread arm "degrades as the run
proceeds". [`weak_strong_64thread_lead_2026_09_07.md`](weak_strong_64thread_lead_2026_09_07.md)
retracted that. `TrackingTask` then gained per-turn timing
([`tracking_task_turn_timing_2026_09_07.md`](tracking_task_turn_timing_2026_09_07.md)),
so the arms could be re-run with the instrument that did not exist when the claim
was made. This is that re-run.

**It refutes the original claim more strongly than the retraction did, it does
not establish the replacement numbers I expected, and it caught me about to
publish the identical error I had spent the day documenting.** All three are
below.

## What was run

`test/examples/weak_strong_tracking.jl`, 200 turns, 1,024,000 macroparticles,
`OCTOPUS_RECORD_TURN_TIMES=1`, one run per thread count. On CPU the instrument is
`time_ns()` plus a `push!` -- no synchronization -- so it does not perturb the arm
it measures.

| arm | whole process | sum of turns | outside the turn loop | turn 1 |
|---|---|---|---|---|
| 16 threads | 172.514 s | 125.652 s | 46.862 s | 2.531 s |
| 64 threads | 149.704 s | 101.196 s | 48.508 s | 2.193 s |

The two right-hand columns are the point of the exercise. Roughly 47 seconds sits
outside the turn loop in both arms, and a further ~2 seconds of first-call
compilation sits *inside* it, at turn 1, against per-turn costs near 0.4-0.65 s.
The 2026-09-06 protocol had only the first column and had to separate those terms
by subtracting one whole run from another.

## The finding: both series are STEP FUNCTIONS, not drifts

This is the result, and it was not what I was looking for.

**16 threads**

| turns | mean s/turn | CV |
|---|---|---|
| 12-47 | **0.4870** | 1.5% |
| 48-200 | **0.6529** | 1.7% |

One step up of 1.34x at turn 48, then 153 turns flat.

**64 threads**

| turns | mean s/turn | CV |
|---|---|---|
| 2-13 | 0.4009 | 10.9% |
| 14-33 | 0.5466 | 5.7% |
| 34-73 | **0.3722** | 3.4% |
| 74-84 | 0.5290 | 2.3% |
| 85-200 | **0.5392** | 4.9% |

Within a regime the machine reproduces to 1.5-4.9%. The transitions are 34-45%.
That is switching, not drift and not noise.

## What this refutes, and by better evidence than the retraction had

The original claim was a monotone climb, "degrades as the run proceeds". The
64-thread arm **steps DOWN mid-run**, 0.5466 to 0.3722 at turn 34 -- the single
largest turn-to-turn change in the series (-0.181 s).

No monotone-degradation mechanism produces a downward step. Not GC pressure, not
fragmentation, not growing data structures, not file growth. The I/O explanation
is dead too: the harness runs with the artifact's `capacity = 1024` against 200
turns, so the batch **never flushes mid-run** and there is no periodic write
cadence to blame.

The retraction argued from irreproducibility across replicates. This argues from
shape within a single run, and it is the stronger argument.

## What this does NOT establish, including an error I nearly published

**I was about to report the 64-thread arm as "rising 1.15x from the first window
to the second, then flat".** Three 50-turn windows give 0.4628 / 0.5402 / 0.5333,
which reads exactly like that. It is a window-placement artifact: the transition
to the sustained slow regime lands at turns 74-84, **inside window 1**, so
window 1 is a mixture of ~26 turns at 0.372 and ~24 at 0.53 while windows 2 and 3
are pure. There is no drift -- there is one step straddling a boundary.

That is the same class of error as the claim this whole thread exists to correct,
committed while documenting it, and caught only because the numbers were sent for
independent verification before being written down.

**"16 threads is flat" is also false, and its step is the bigger one.** The
16-thread arm steps by 1.34x against the 64-thread arm's apparent 1.15x. It looks
flat only because its step lands at turn 48, two turns before the first window
opens. Windowed at 11-70 / 71-130 / 131-190 the 16-thread arm would show the
*larger* climb. "16 is flat, 64 drifts" would have been a contrast manufactured
by where the boundaries were put.

**The mean-plus-sd summary is the wrong statistic.** "Steady state (turns 11+),
mean 0.6213, sd 0.0658" describes a mixture of two plateaus, not scatter about a
level; within-regime sd is 0.0074-0.0111. Lag-1 autocorrelation is 0.95 and 0.88,
so the effective sample size is about 5 and 12, not 190. Regime means with turn
ranges are the honest presentation, and are what this record gives.

## 64 threads against 16: an ordering, not a factor

| basis | ratio |
|---|---|
| turns 12-47 | 1.03x |
| turns 51-100 | 1.41x |
| turns 101-150 | 1.21x |
| turns 151-200 | 1.23x |
| regime-matched (16t 48-200 vs 64t 85-200) | **1.211x** |

The honest figure is **~1.21x regime-matched**, with a 1.03-1.41x spread across
window choices. And it is not a turn-for-turn win: the 16-thread arm's fast
regime (0.4870) is faster than the 64-thread arm's sustained late regime
(0.5392).

Hedges that belong with it: n = 1 per arm, the two arms ran sequentially with the
order not randomized, and node load rose throughout -- 1-minute load average 2.01
to 5.30 across the 16-thread arm and 5.30 to 10.02 across the 64-thread arm. The
64-thread arm's "before" figure IS the 16-thread arm's "after", i.e. the decaying
tail of the previous job, so load cannot be decomposed into own and foreign
contributions and this is not a controlled A/B.

**With one run per thread count, the environment's time-path and the code's turn
index are perfectly confounded.** The shape argument above buys "not monotone
code degradation". It does not buy "external load caused the steps". Separating
those needs a quiet node, randomized order, and replicates.

**A finding hiding in the load numbers:** a 64-thread arm on a 128-core node
drove the 1-minute load average only to 10.02. That is not consistent with
64-way concurrency, and it is the most plausible reason the arm buys 1.21x rather
than anything near 4x. Worth its own probe; not measured here.

## Corrections to what I wrote earlier the same day

Both are mine, from
[`weak_strong_64thread_lead_2026_09_07.md`](weak_strong_64thread_lead_2026_09_07.md),
and `docs/todo.md` carried them further.

**The absolute levels and the speedup were from the wrong instrument.** That
record quotes "~0.055-0.074 s/turn at 64 threads" and "~0.15-0.21 at 16" as costs
"at the production point", and derives "64 threads is a real ~2.9x over 16".
Those windows come from `profiling/benchmark_track_cpu.jl`, whose own header says
it has "no observer and no artifact, so the number is tracking + beam-beam
alone" -- a different line from the harness at the same particle count. Measured
on the harness the production benchmark actually used: **0.6529 and 0.5392 s/turn
in the late regimes**, 3-9x the quoted bands, and a speedup of **~1.21x, not
2.9x**. The 2.8x is real for the profiling line alone and does not transfer.

**The same record contradicts itself**, and I introduced the contradiction: it
flags the instrument mismatch plainly ("whose line is not the harness's... a
different workload") and then presents that instrument's numbers as "the
production point" and as "what is true". `docs/todo.md` propagated the figures
with both the attribution and the caveat stripped, making the row worse than the
record it points at.

**"Gets FASTER as a run proceeds" must go too.** That was a fact about the
profiling line. The harness shows no resolvable within-run trend in either
direction -- it shows steps.

**"Both instruments agree; only the second one is entitled to" is too strong.**
They agree on the negative -- no reproducible monotone degradation. They disagree
on level (3-9x), on speedup (2.8x against 1.21x), and on within-run direction
(monotone fall against steps).

What survives from that record unchanged is its central claim: the 0.313 / 0.749
/ 0.816 climb is an artifact of differencing whole-process wall times, not a
property of the workload. This run corroborates it; the replicates in that record
remain the primary evidence.

## What a production number would take

Not another single run. A quiet node, arms interleaved and order-randomized,
several replicates per thread count, regime-aware reporting rather than
mean-plus-sd, and the load average logged per turn rather than per run. The
instrument now makes each of those cheap -- one run yields the whole series --
which is the difference from 2026-09-06, when the same questions cost four runs
and still could not be answered.
