# The 64-thread weak-strong "degradation" is the measurement — 2026-09-07

> **Later record (added 2026-09-07, no text below is altered):** the arms were
> re-run with the per-turn instrument. This document's central retraction
> stands, but its ABSOLUTE LEVELS and its "~2.9x over 16" are from
> `profiling/benchmark_track_cpu.jl`, a different line from the harness, and
> must not be read as production-case costs; its "gets faster as a run
> proceeds" does not hold for the harness either. Corrections in
> [`weak_strong_rerun_instrumented_2026_09_07.md`](weak_strong_rerun_instrumented_2026_09_07.md).


[`production_benchmark_2026_09_06.md`](production_benchmark_2026_09_06.md)
recorded one arm it would not quote plainly:

> **The 64-thread weak-strong arm degrades as the run proceeds, and that is a
> lead.** Its interval rate climbs from 0.313 s a turn over turns 50-100 to
> 0.816 over turns 150-200, and its fitted intercept is -0.5 s where every other
> mode sits at a physical 13 to 19 s of load and JIT. A straight line does not
> describe it.

It ruled that such a number "should not be quoted without its run length", and
named GC as the first suspect, with the probe to run being a GC-time series
against turn number at 16 and 64 threads.

Both halves were run. **The degradation is not a property of the workload. It is
an artifact of how the quantity was derived, and the record's own reported
intercept is the tell.** That record is frozen, so the correction lives here.

## The probe the row asked for: GC is not the suspect, because there is no GC

`profiling/benchmark_track_cpu.jl` times windows WITHIN one process. Four 50-turn
windows, 1.024M macroparticles, the production point:

| threads | window 1 | window 2 | window 3 | window 4 | GC share | allocation |
|---|---|---|---|---|---|---|
| 16 | 0.2052 | 0.1701 | 0.1767 | 0.1469 | 0.0% throughout | 0.000 GiB/turn |
| 64 | 0.0735 | 0.0628 | 0.0578 | 0.0551 | 0.0%, one window 5.5% | 0.000 GiB/turn |

The 64-thread series falls MONOTONICALLY — the opposite of the reported climb —
and the coordinate digest is `0xea779e21e96db67b` at both thread counts, so the
two arms did identical physics.

GC cannot be the mechanism here: the 2026-09-04 step-1 allocation extraction took
this path to 0.000 GiB/turn, and Phase 0's 3.2/30.8/52.2% GC shares at 1/16/64
threads describe the tree BEFORE that fix. The row named GC as first suspect on
the strength of those Phase 0 numbers without re-reading them against the fix
that had since landed.

## Why the two disagree: the reported rate was never measured within a run

The production record says so itself, in its methods:

> A `TrackingTask` records none, so the weak-strong case was run at 50, 100, 150
> and 200 turns per mode and the per-turn cost taken as the least-squares SLOPE
> of elapsed against turns.

So each "interval rate" is a difference between two SEPARATE PROCESSES' total
wall times — each paying its own Julia start, package load, JIT, beam
construction and artifact write, on a shared 128-core node whose load the same
record logs as ranging 0.4 to 6.9. Nothing in that subtraction is protected from
the node.

## The protocol, replicated twice

Same protocol, same harness, same 64 threads, same 1.024M macroparticles, each
turn count run TWICE and interleaved:

| | interval 50-100 | 100-150 | 150-200 | direction |
|---|---|---|---|---|
| the record, 2026-09-06 | 0.313 | 0.749 | 0.816 | climbs |
| replicate 1 | 0.731 | 0.431 | 0.436 | **falls** |
| replicate 2 | 0.408 | 0.552 | 0.678 | climbs |

**One replicate of the identical protocol falls and the other climbs.** The
direction is not reproducible, so it is not a property of the code.

The noise floor, measured directly as the spread between two runs of the SAME
configuration:

| turns | run A | run B | difference | as noise in a 50-turn interval |
|---|---|---|---|---|
| 50 | 67.70 | 75.68 | 7.98 s (11.8%) | 0.160 s/turn |
| 100 | 104.23 | 96.08 | 8.15 s (8.5%) | 0.163 s/turn |
| 150 | 125.78 | 123.71 | 2.07 s (1.7%) | 0.041 s/turn |
| 200 | 147.56 | 157.60 | 10.04 s (6.8%) | 0.201 s/turn |

Each interval difference carries TWO such errors, so the derived rate has roughly
±0.2 to 0.4 s/turn of pure measurement noise on it. The record's entire reported
spread, 0.313 to 0.816, is 0.50 — inside that. The load average was logged beside
every run here too, and moved from 2.50 to 21.69 across the eight.

## The intercept was the tell, and it does not reproduce

The record flagged its own fitted intercept of **-0.5 s** as anomalous against
the 13-19 s every other mode showed, and read it as evidence that "a straight
line does not describe it". A straight line describes it well:

| | slope (s/turn) | intercept | R^2 |
|---|---|---|---|
| the record | 0.6384 | **-0.5 s** | not reported |
| replicate 1 | 0.5222 | **+46.0 s** | 0.9810 |
| replicate 2 | 0.5468 | **+44.9 s** | 0.9880 |

Both replicates give a physical, positive intercept and R^2 above 0.98. A
negative intercept is not a finding about the code; it is what least squares
returns when the shortest run happened to land on a quiet node and the longer
ones did not. It was the strongest single piece of evidence the row had, and it
was evidence about the node.

(The intercept here is ~45 s rather than the 13-19 s that record quotes for other
modes because this harness also writes a per-turn moment artifact and builds a
1.024M-particle beam before the first turn; the point is the sign and the
stability, not the value.)

## What is true, and what replaces the row's rule

- Weak-strong tracking at 64 threads costs **~0.055-0.074 s/turn** at the
  production point measured within a process, and gets FASTER as a run proceeds,
  not slower.
- The 16-thread arm is ~0.15-0.21 s/turn, so 64 threads is a real ~2.9x over 16.
  The production record's table has 64 threads SLOWER than 16 for this case; that
  ordering comes from the same subtraction and should not be relied on either.
- GC is not implicated on this path at any thread count measured here.

The row's rule was "do not quote a 64-thread weak-strong per-turn number without
its run length". The measured rule is different and stronger: **do not derive a
per-turn cost by differencing whole-process wall times on a shared node.** Run
length is not the variable; the node is.

## The gap this actually exposes

The reason the benchmark had to difference whole processes is stated in its own
methods and is a real hole: `StrongStrongTask` records per-turn timings
(`StrongStrongDiagnostics(record_turn_times=true)`, read back with
`turn_timings`), and **`TrackingTask` records none**. Every weak-strong timing
claim in the repository therefore rests on external wall-clock arithmetic, while
every strong-strong one rests on an instrument.

That asymmetry is the follow-up worth having, and it is ledgered rather than
taken here: giving `TrackingTask` the same per-turn timing facility would have
made this whole investigation a single run.

## A note on what was checked before concluding

The first probe used `benchmark_track_cpu.jl`, whose line is not the harness's,
and its absolute numbers are 5-14x faster than the production arm's. That is a
different workload, and a within-run series from it could not by itself refute a
claim about the harness — a same-shape-different-subject comparison is exactly
the error this campaign keeps finding in its own records. So the harness protocol
was replicated directly, at the production particle count, before any conclusion
was drawn. Both instruments agree; only the second one is entitled to.
