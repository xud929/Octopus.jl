# The CPU Soft-Gaussian Learns `batch_mode` — 2026-09-04

The multi-process budget for the divided soft-Gaussian collide
([`multi_process_strongstrong_scaling_2026_09_04.md`](multi_process_strongstrong_scaling_2026_09_04.md))
priced 64 ranks at 52% ideal compute, 18% per-rank inefficiency and 30%
collectives, and named one lever for the third term: the collide issues 1874
collectives, of which 1840 average 33 bytes, so the target is the CALL COUNT
and `collision_pair_batches` is the instrument. The CPU soft-Gaussian was the
only collide path in the tree still strictly sequential — the CUDA
soft-Gaussian, PIC on both backends, Gaussian-PIC and spectral all batch.

This is that change, plus the second lever the owner raised the same day: the
two beams within a pair are independent and were being done one after the
other.

## The keyword is the one that was already there

`GaussianPoissonSolver` has carried `batch_mode` (`:sequential` or
`:wavefront`, defaulting to `:wavefront`) since the CUDA route was written;
only its CPU method declined to read it, and the schema said so —
`supported_backends=(CUDABackend,)`, with `validate_configuration_metadata()`
warning that a non-default value was inactive on CPU storage. Owner
constraint, stated while this was being scoped: reuse the option keywords,
invent none. So the CPU method now reads that field. `supported_backends`
names both backends, and the CPU-inactive warning stops firing for it because
it stopped being true.

Its declared `consumer` had to move too, and the reason is mechanical rather
than aesthetic: `_solver_contract_receipt_carries` filters receipts BY BACKEND
before it matches the consumer name, so a `:cuda_gaussian_algorithm` consumer
could never certify a CPU consumer boundary — the CPU half of
`SolverOptionEffectivenessContract` would look for that name among
CPUThreadsBackend receipts and find nothing. Both routes now emit
`:gaussian_pair_schedule` carrying the mode; the CUDA algorithm receipt keeps
carrying the rest of the device configuration.

The docstring that called `batch_mode` CUDA-only was also wrong about the
solvers it named: it said "the CPU paths always use collision-time order", but
CPU PIC and CPU Gaussian-PIC batch by their own `_pic_batchable` rule
(`!_pic_source_slice_grid` — `:source_slice` shares mesh bounds across pairs,
so that mode cannot batch). Corrected with this change.

## What actually got cheaper

Three edits, and only the first is the schedule.

**The batch.** `collision_pair_batches` groups pairs that repeat no beam-1 and
no beam-2 slice. Within a batch the pairs commute — no pair reads or writes a
slice another pair in the same batch touches — so every slice in the batch can
have its moments taken before any of the batch's kicks. 225 pairs become 29
batches, widest 15.

**The hoist.** The paragraph in the design note that says the moments cannot
leave the pair loop is true of the COORDINATES: every pair kicks what it
touches, so a later pair reads what an earlier one wrote. Two things about a
slice are not coordinates. How many particles it holds is fixed once the beams
are sliced, and so is WHICH particle is its globally-first member — the shift
origin every rank must agree on. Both were being recomputed per pair, 450
times each. They now leave the collide's pair loop entirely: one all-sum over
all 30 slices' counts, one minimum per slice. Only the origin's four
coordinates are re-read per batch, because those move.

**The merge.** Each batch exchanges its slices' shift origins in one message
per beam and their shifted sums in one more — four messages per batch instead
of six per pair. Two buffers rather than one, because the two beams' working
precision is `promote_type(eltype(rep.x), typeof(min_sigma))` computed on
their own coordinate arrays, and merging buffers of different element types
would move the cross-rank sum to the wider one.

The kicks go out as one grid for the whole batch, both beams together. This is
the owner's second lever, and it is worth stating what it is and is not: the
two beams within a pair are genuinely independent — different moments,
disjoint kick targets, both moments taken before either kick — but at the
configuration that scales best under MPI (one thread per rank)
`_run_logical_workers` runs its grid inline, so widening it buys loop
structure rather than parallelism. It is the threaded and single-process cases
that get the width.

## Nothing moved

The requirement is two-sided: `:sequential` must reproduce the tree it
replaced, and `:wavefront` must equal `:sequential`.

Undivided, against the pre-change tree at 1, 4 and 8 threads, coupled and
uncoupled, at 1, 5 and 15 slices: identical coordinate digests and identical
luminosity bits, both schedules, every cell.

Divided, under MPICH_jll's `mpiexec` at 1, 2 and 4 ranks, at the production
15-slice point: identical luminosity and identical whole-beam digests, both
schedules, and identical to the pre-change tree at the same rank count.

| ranks | luminosity | whole-beam digest |
|---|---|---|
| 1 | 1.0269151884272286e30 | 53f7ad6281f05e73 |
| 2 | 1.0269151884272289e30 | 5eb4df42df4cb758 |
| 4 | 1.0269151884272292e30 | 4ed13eaf8066e6e1 |

The drift down the column is the campaign's cross-rank parity tolerance and is
unchanged by this work — the pre-change tree produces the same three rows.

The suite pins both sides. `test/runtests.jl` compares the two schedules
bitwise on a single process, coupled and uncoupled, and asserts on what each
run RECORDED — the sequential arm reports zero batches, the wavefront arm
reports fewer batches than pairs and a widest batch above one — because
without that the equality is satisfied by a path that never batches, which is
exactly what the CPU did until today. `test/mpi_seam_check.jl` runs a second
collide with `batch_mode=:sequential` on an identical pair of beams and the
parent asserts the two `repr`-printed lines are equal to the character, at
every rank count the child runs.

## `fma`, not `muladd` — a 1-ulp trap found on the way

Splitting the moment finalize into its own function so a batched caller could
reuse it changed a coupled collide's coordinates by 1 ulp, with the raw
shifted sums bit-identical on both sides. The cause is `muladd`, which is
defined as "fuse if the compiler thinks it profitable": `_shifted_second_moment`
computes `muladd(-mean_offset, mean_offset, sum2 * invn)`, and the fused and
unfused results differ in the last bit. Which one a call site gets is a codegen
decision, so MOVING the code moved the answer.

Measured before deciding: 400 of 400 sampled shifted moments on this CPU came
back FUSED in the pre-change tree, i.e. `fma` is what the tree has been
computing all along. The two helpers now say `fma`, which pins the arithmetic
instead of leaving it to the inliner. Both backends have the instruction.

This is worth remembering beyond this change: every `muladd` in the tree is a
1-ulp coin that a refactor can flip, and the repository's recorded near-identity
wobbles are the same shape.

## Measured

Collectives per collide at the production point (15x15 slices), counted from
the run's own `:multi_process_collective` receipts:

| schedule | total | allsum | allminmax | bytes |
|---|---|---|---|---|
| sequential | 1874 | 1422 | 452 | 61,816 |
| wavefront | 222 | 190 | 32 | 51,736 |

8.4x fewer calls. The byte count barely moves, which is the point — the
latency table in the scaling record showed ten floats costing what one does.

Time, at the production point (640,000 x 256,000, 15 slices, one thread per
rank, `-bind-to core`), three interleaved A/B rounds of nine repeats each:

| ranks | schedule | best | median (round 1 / 2 / 3) |
|---|---|---|---|
| 16 | sequential | 0.2442 s | 0.2465 / 0.2501 / 0.2486 |
| 16 | wavefront | 0.2277 s | 0.2353 / 0.2351 / 0.2359 |
| 64 | sequential | 0.0970 s | 0.3942 / 0.3794 / 0.4119 |
| 64 | wavefront | 0.0749 s | 0.3404 / 0.2120 / 0.2083 |

**Read the best column, not the median, and here is why.** At 16 ranks the two
agree — best and median are within 3% of each other, and the schedule is worth
7%. At 64 ranks the best times are the most reproducible numbers in the table
(sequential 0.0970 / 0.0971 / 0.0982; wavefront 0.0760 / 0.0749 / 0.0755,
three independent rounds) while the medians scatter over 2x and the maxima
reach 1.99 s. Both schedules show it, so it is not the change: the box was
intermittently stalling 64-rank runs this evening in a way it was not when the
scaling record was measured, whose 64-rank sequential figure was 0.1028 s
against 0.0974 s best today. Serial reference the same evening: 3.3947 s.

So at 64 ranks the collide's floor moves **0.0974 -> 0.0755 s, 1.29x**, and
against the same serial reference that is 34.9x -> 45.0x. Ideal compute is
3.3947/64 = 0.0530 s, so the non-compute term falls from 0.0444 to 0.0225 —
**halved**, which is what an 8.4x cut in call count buys once the per-rank
inefficiency (which this does not address) is left standing. The projection in
the ledger was 0.0731 s from ~130 calls; 222 calls landed 0.0755, which is
where a 1874 -> 222 rather than 1874 -> 130 reduction should land.

## And on CUDA, where `batch_mode` came from

Asked afterwards, and worth answering with numbers rather than by assertion:
is `:sequential` a real option on the device?

It is honoured. `collide!(::GaussianPoissonSolver, …, ::Type{CUDABackend})`
branches on the field to `_cuda_gaussian_collide_sequential!`, which records the
mode. It is not, however, a choice anyone should make for speed — it is the
fallback, and the default is the other one. Isolated collision, 200,000
particles per beam, 15 slices, best of five:

| backend | coupling | `:sequential` | `:wavefront` |
|---|---|---|---|
| CUDA | uncoupled | 0.0430 s | **0.0282 s** (1.53x) |
| CUDA | coupled | 0.0479 s | **0.0327 s** (1.46x) |
| CPU (4 threads) | uncoupled | 1.0217 s | 1.0821 s |
| CPU (4 threads) | coupled | 0.8323 s | **0.6464 s** (1.29x) |

The CPU rows are a single process, where the batch buys no collectives and the
grid is the only lever; they are noisy at this size (the uncoupled medians run
the other way, 1.241 s sequential against 1.123 s wavefront) and the honest
reading is "no worse, sometimes better". The batch earns its keep on CPU where
the messages are, which is the divided run measured above.

One asymmetry worth stating: on CPU the two schedules are BIT-identical, and
the suite asserts that. On CUDA they are not — the coupled pair differs in the
last bits (1.027454028682913e30 against 1.0274540286829126e30) — which is the
device's own recorded float-atomic reordering, not the schedule. The CUDA
backend-consistency contracts compare at their stated tolerance for that reason.

### The device-side check that nearly disappeared

Making `batch_mode` CPU-visible silently removed the CUDA half of its
effectiveness check. `SolverOptionEffectivenessContract` decided what the
DEVICE must honour with `!(CPUThreadsBackend in meta.supported_backends)` — a
proxy for "only CUDA reads this" — so the moment the CPU learned to read the
option, it dropped out of that list. Nothing went red: a check that stops
running is not a failing check, which is this repository's dominant recorded
failure class.

The filter now asks the question it means: an option is checked on the device
when CUDA reads it AND either the CPU cannot see it or it is an execution or
performance choice. `_solver_option_is_execution` is what keeps physics options
out, since the device half's assertion is "the result must NOT move" — the
wrong claim for anything the CPU half checks by making it move. Enumerated
before changing it, the new filter admits exactly one option that the old one
did not: `GaussianPoissonSolver.batch_mode`. The contract passes with
`cuda_options_checked = 10` against `cuda_only_options = 9`.

## What this does not do, and what is left

The 18% per-rank inefficiency is untouched at one thread per rank, for the
reason given above. Remaining call-count headroom, in descending size:

- **The slicing's own messages.** 222 is not 130. About 70 of the survivors
  are the slicing's per-statistic scalar all-sums, one per quantity per beam;
  they vectorize into one message per beam the same way the moments just did.
- **The discarded maximum.** `_mp_slice_reference` calls `_mp_allminmax(mine,
  mine)` and throws the maximum away, and the extension implements that as two
  separate `MPI.Allreduce` calls. The hoist above cut these from 450 to 30, so
  what is left is 30 wasted messages per collide — hygiene, not speed.
- **The gather buffer.** `_mp_allsum_impl!` allocates its Allgather workspace
  on every call.

Then the two levers the scaling record already names: a deterministic reduction
tree, and non-blocking overlap.
