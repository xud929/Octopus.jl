# CPU Threading Campaign — 2026-08-09

Owner-directed: test and optimize CPU threading for all four strong-strong
solvers on the 128-thread/64-core box. Constraints set by the owner: the GPU
paths stay UNTOUCHED, and CPU/GPU consistency gates every step — an
optimization that moves physics is a defect.

Continues the CPU columns of
[`solver_matrix_2026_08_08.md`](solver_matrix_2026_08_08.md), whose finding 3
opened this row.

## Hardware and instrument

- 2 x Intel Xeon Gold 6430: 64 physical cores, 128 hardware threads, 2 NUMA
  nodes (node0 CPUs 0-31,64-95; node1 32-63,96-127). Julia 1.12.4.
- Instrument: `profiling/benchmark_collide_cpu.jl`, which times `collide!`
  alone — no ring lines, no observers, no moment output — on the same EIC
  crab-crossing pair the production harness builds, and prints a **bitwise
  digest** (rotate-then-xor over every coordinate's Float64 bit pattern) of
  both beams after the collide. Every claim of "bit-identical" below is that
  digest agreeing, not a tolerance.
- Sizes: the production point is 2,560,000 e- / 1,024,000 p, 15 slices,
  grid (128,128), `:CIC`, `:slice_pair` Green cache. A quarter-size point
  (640,000 / 256,000) is used for iteration; both are reported where they
  disagree, because they weight per-particle work against grid work
  differently.

## Starting state, measured

CPU PIC `collide!`, quarter-size point, **before any change**:

| julia --threads | s/collide | digest |
|---|---|---|
| 1   | 13.67 | `0xc8af3cf19999b79c` |
| 16  | 12.73 | same |
| 64  | 13.23 | same |
| 128 | 15.05 | same |

**The CPU PIC solver did not scale at all** — 1 thread to 64 threads bought
3%, and 128 threads was 10% *slower* than one. The digest is identical at
every count, so the pre-existing worker-count invariance was real; there was
simply almost nothing running in parallel to be invariant about.

Reading the solver confirmed it. At the production point the CPU PIC path is
serial nearly end to end:

- the slice-pair loop in `_pic_collide!` is a plain `for`;
- the deposit takes its SERIAL branch, because `_pic_deposit_parallel`
  requires `160 * nx * ny` = 2,621,440 particles per slice and production
  supplies ~171k;
- every CPU FFT is single-threaded (`FFTW.set_num_threads` appears nowhere);
- the per-particle kick, drift, bounds and virtual-position loops were plain
  `for` loops in `_pic_interaction!`;
- the Green table build is a plain nested loop.

The only threaded structures on this path — `_pic_deposit_threaded!` and the
slicing/moment reductions — are either not entered at production sizes or are
a small share of the turn.

## Fix 1 — the per-particle maps in `_pic_interaction!` (2026-08-09)

**What.** The two kick loops (linear and `:quadratic`) and the
virtual-position loop moved out of `_pic_interaction!`'s body into
`_pic_apply_kick_range!`, `_pic_apply_kick_quadratic_range!` and
`_pic_virtual_positions_range!`, driven by a new `_pic_map_particles`
partitioner. This is the same `_xxx_range!` + threaded-wrapper shape the
deposit in this file already used.

**Why worker-count chunking is legal here, when U5-1/U5-2 forbade it for the
deposit.** That rule protects chunk-ordered float FOLDS, which reassociate
when the chunk count moves — the defect that shifted transverse moments by up
to 131,072 ulps between 1, 4 and 8 workers. These callbacks fold nothing:
every write is to index `i` of an array indexed by `i`, with the field planes
and the grid shared read-only. A partition cannot move a bit at any worker
count. That is pinned directly rather than argued, and the pin is
anti-vacuous: it asserts the partition tiles `1:n` exactly AND that it really
split into two or more chunks before comparing.

**The chunk-size floor, and why it is not a new tuned number.** Taking
`nchunks = worker count` outright measured 6.1 s at 16 workers, 8.6 s at 64
and **63.6 s at 128** on the quarter-size point: these maps run once per
interaction, 450 times per turn, so 128 workers on a 42k-particle slice gives
333-particle chunks whose spawn and join cost more than the arithmetic. The
floor is `_STRONG_STRONG_PARALLEL_KICK_MIN`, the same measured break-even
already used as the serial cutoff — a chunk smaller than the size at which
threading starts to pay is by definition not worth spawning. Same input with
the floor: 6.2 / 7.2 / 13.0 s.

Sweep of the floor at the quarter-size point (s/collide):

| floor | 16 thr | 64 thr | 128 thr |
|---|---|---|---|
| 1024 | 6.09 | 8.22 | 16.93 |
| 4096 (`_STRONG_STRONG_PARALLEL_KICK_MIN`) | 6.20 | 7.23 | 13.01 |
| 16384 | 6.83 | 7.46 | 11.57 |

**Result.** Quarter-size point, s/collide, digest `0xc8af3cf19999b79c`
throughout — bit-identical to the pre-change baseline at every thread count:

| julia --threads | before | after | speedup |
|---|---|---|---|
| 1   | 13.67 | 6.86 | **1.99x** |
| 16  | 12.73 | 6.13 | **2.08x** |
| 64  | 13.23 | 7.23 | 1.83x |
| 128 | 15.05 | 13.01 | 1.16x |

**The surprise worth recording: most of that is not threading.** The SERIAL
path (1 thread) went 13.67 -> 6.86 s, a 2x win from extracting the loop
bodies into their own functions and nothing else. `_pic_interaction!` is a
long function with many live values, and the kick loop compiled badly inside
it; the same arithmetic in a small function with its operands as arguments
compiles well. Threading the maps on top of that buys only a further 4.6% at
the production point (13.94 -> 13.29 s at 16 threads, measured by forcing the
maps serial with an oversized floor). The function extraction is the fix; the
threading is a small bonus at this shape.

Bit-parity is exact, which the extraction did not guarantee in advance —
moving arithmetic into a new compilation unit can change FMA contraction, the
mechanism that moved `mom.varx` by 1 ulp in the 2026-08-07 `Val` gating work.
Measured here, it did not: the digest is unchanged at 1/16/64/128 threads.

**Found by the tripwire, not by review.** The first version reused the name
`sM` for the `:quadratic` branch's midpoint drift and for the
virtual-position drift. `if` opens no scope in Julia, so that is one
function-scope variable assigned in two places and captured by a closure —
`Core.Box`, one shared box across every worker. The permanent lowered-code
sweep failed on it immediately (`_pic_interaction! @ pic_cpu.jl:533`). Same
defect class as `chunk_lum` in `gaussian.jl` and `chunk_counts` in
`slicing.jl`; a distinct name is the whole fix. This is the third time that
tripwire has caught this exact trap, which is the argument for keeping it.

## Machine-level findings that are not code changes

- **Idle-thread spin costs real bandwidth on this box.**
  `JULIA_THREAD_SLEEP_THRESHOLD=0` at 128 threads: 11.0 -> 8.4 s on the
  quarter-size point. The default spin keeps 128 threads polling `poptask`
  while ~10 do work, and on a 2-socket box that competes with the working
  threads for memory. Worth setting for any CPU strong-strong run on this
  hardware; it changes no results.
- **GC is not the ceiling.** 1.87 GiB allocated per collide at the
  quarter-size point, 8.4% of wall at 16 threads rising to 10.2% at 128. Real,
  but it explains ~0.6 s of the 4.7 s gap between 16 and 128 threads, not the
  gap.
- **A large pool is a cost even when the parallel structure is identical.**
  With the chunk floor the number of chunks is set by the data, so 16, 64 and
  128 threads run the *same* partition — and still measure 6.3 / 7.8 / 11.1 s.
  Whatever else is optimized, this workload should not be run with a pool much
  wider than the parallelism its data can feed.

## Where the time goes now (production point, 16 threads)

Sampling profile of `collide!` after fix 1, as a share of the collide:

| block | share | parallel today? |
|---|---|---|
| slice gather/scatter (`_pic_extract_slice` + `_pic_store_slice!` + `_pic_copy_coords`) | **41%** | no |
| Green table build + its FFT (`_pic_slice_pair_green!`) | **23%** | no |
| field solves (deposit + FFT + `_pic_field!`), both planes | **20%** | deposit only, and not at production sizes |
| luminosity | 5% | no |
| the kick maps | ~5% | yes |

The dominant cost is no longer physics: it is that each slice is gathered out
of the beam, copied, and scattered back **once per PAIR**, so slice `i` of
beam 1 makes that round trip 15 times per turn instead of once.

`spectral.jl` is the worked precedent for the structural fix — it already
groups the collision order into conflict-free batches with
`collision_pair_batches` and runs the pairs of a batch on
`_run_logical_workers` with a workspace pool and a pair-indexed luminosity
fold. That is why spectral measures 6.65 s/turn on CPU against PIC's 40.8.
PIC and GaussianPIC have no such structure. Both are next.

## Fix 2 — conflict-free pair batching for PIC (2026-08-09)

**What.** The PIC pair loop now takes its pairs from
`collision_pair_batches` and runs each batch on `_run_logical_workers`, one
scratch workspace per worker from a pooled, grown-in-place
`_pic_cpu_workspace_pool!`. The per-pair body moved into
`_pic_collide_pair!`. This is the structure `spectral.jl` has had all along.

**Bit-identical to the pre-campaign HEAD, not merely equivalent.** The
schedule is safe because `collision_pair_batches` preserves each slice's own
collision order, so a pair still sees exactly the partner state it saw when
the loop was sequential. What that does NOT give for free is the luminosity
fold: summing per batch would reassociate it. So every pair's luminosity is
written into `lum_parts[p]` at its position in the **collision** order and the
fold is done at the end in that order, and the per-pair trace with it. The
digest across the whole campaign is one number:

    baseline d0fb3f2, 1 and 16 threads      0x4625d8c583a1efa1
    after fix 1, 1/16/32/64/128 threads     0x4625d8c583a1efa1
    after fix 2, 1/8/16/32/64/128 threads   0x4625d8c583a1efa1

**Which modes may batch, and why the third may not.** `:slice_pair` (the
default) sizes its mesh from the two slices of its own pair, whose relative
order batching preserves. `:node` builds every mesh at turn start — the
prebuild written after lazy building made CPU and the CUDA wavefront route
disagree by 3.8e-5, i.e. this hazard was already known here. `:source_slice`
takes a union over the *whole* partner beam at the source slice's first use,
so its mesh depends on how much of the turn has been applied; it stays
sequential, enforced in `_pic_batchable` and asserted from the execution
receipt rather than from the predicate alone.

**Shared state, and what each needed.** The Green cache keeps one lock in the
cache object, held only across the `entries` lookup and insert — never across
the rebuild, which is the expensive part and runs in the worker's own
workspace. Because every `:slice_pair` key is `(i, j, direction)`, distinct
pairs touch distinct keys and each key's hit/miss/rebuild sequence is the one
the sequential loop produced. `dropped` is now summed over the pool so a
dropped particle stays exactly as loud as before. `ExecutionAudit` took a lock
too: `_record_execution!` is now reached from inside worker tasks, and two
tasks pushing to one Vector corrupt it rather than reorder it.

**Result at the production point** (2.56M/1.024M, 15 slices, grid 128,
s/collide, `JULIA_THREAD_SLEEP_THRESHOLD=0`):

| julia --threads | baseline `d0fb3f2` | after fix 1 | after fix 2 |
|---|---|---|---|
| 1   | 42.97 | 14.26 | 14.39 |
| 16  | 41.03 | 13.30 | **4.20–4.68** |
| 32  | —     | —     | 6.25 |
| 64  | —     | —     | 7.57 |
| 128 | —     | —     | 7.44 |

**8.8–9.8x at the production point**, bit-identical throughout.

**Allocation is where fix 1's production win actually came from.** The
baseline allocates **43.78 GiB per collide** and spends 23% of its wall in GC;
after fix 1 that is 6.13 GiB and 6%. The quarter-size point showed fix 1 as a
2x win, the production point as 3.1x, and this is the difference: the kick
loop inside the long `_pic_interaction!` body was allocating, and extracting
it into a small typed function stopped that.

**Two levels of parallelism have to be divided, not multiplied.** With the
pair loop batched, the per-particle maps inside each pair were still asking
for the whole pool: up to 15 concurrent pairs x 41 chunks each. Measured
5.76 s at 16 threads, 6.45 at 32, 7.08 at 64. A scoped `_PIC_MAP_WORKER_BUDGET`
now hands each pair `worker_count ÷ pool_size`, and 16 threads improved to
4.20 s — at 16 threads the budget is 1, so the inner maps go serial and that
is *faster* than splitting them 41 ways underneath an already-parallel loop.

**Why it stops scaling past ~16 threads, honestly.** A batch cannot repeat a
beam-1 or beam-2 slice, so with 15 slices no batch is wider than 15 and the
pool is capped there. Past that, extra threads add GC (now 20–27% of wall) and
scheduler cost with no more pair parallelism to claim. Getting beyond this
needs the allocation itself reduced, which is the next item: the slice
gather/scatter is both the 41% block and the source of the 6.3 GiB.

**Found by the tripwire again, and this one was not benign.** The per-worker
workspace was first named `ws`, the same name the sequential branch uses.
`if`/`else` opens no scope, so that is one function-scope variable captured by
the worker closure — one `Core.Box`, one workspace shared by every worker. One
pair's charge grid reached another pair's field solve and the collide died
with an all-NaN slice. Renamed to `chunk_ws`/`serial_ws`. Second time in this
campaign, and the reason the batched-vs-sequential pin asserts the schedule
from an execution receipt rather than trusting that it ran.

## Fix 3 — the same batching for GaussianPIC (2026-08-09)

`_gpic_collide!` had the identical sequential pair loop and now shares the
whole mechanism: `_pic_pool_size`, `_pic_cpu_workspace_pool!`,
`collision_pair_batches`, the collision-order luminosity fold, the
`:cpu_pic_pair_schedule` receipt and `_PIC_MAP_WORKER_BUDGET`. It is the
simpler case — gpic REJECTS `interaction_grid` as an inert option
(`_GPIC_INERT_PIC_OPTIONS`), so the `:source_slice` union mesh that keeps
plain PIC sequential cannot arise; `_pic_batchable` is still consulted rather
than assumed.

| point | baseline `d0fb3f2` | after fix 3 | |
|---|---|---|---|
| quarter size, 16 threads | 18.88 | 8.60 | 2.2x |
| production, 16 threads   | 65.45 | 26.16 | **2.5x** |
| production, 1 thread     | —     | 67.25 | |
| production, 32 threads   | —     | 26.16 | |

Digests: `0x967d4e7aecddbba5` (quarter size) and `0x58fc69d46333dfe0`
(production), each identical between the baseline and every thread count here.

**What this left, and it was the whole remaining cost.** gpic still allocated
**47.1 GiB per collide** — unchanged from the baseline — and spent **39%** of
its wall in GC, against PIC's 6.3 GiB and 20%. gpic had never received fix 1:
its kick loop was still inline in `_gpic_interaction!`, exactly the shape that
was allocating in `_pic_interaction!` before extraction. Fix 4 below.

## Fix 4 — the fix-1 treatment for GaussianPIC's kick loop (2026-08-09)

`_gpic_apply_kick_range!` and `_pic_virtual_positions_range!` (reused as is)
behind `_pic_map_particles`, exactly as for plain PIC. `use_coupled` stays a
runtime `Bool` rather than becoming a `Val`, for the recorded reason: a second
specialization lets LLVM contract the shared FMAs differently, which is how the
2026-08-07 `Val` gating moved `mom.varx` by 1 ulp.

Production point, s/collide, digest `0x58fc69d46333dfe0` throughout:

| julia --threads | baseline `d0fb3f2` | after fix 3 | after fix 4 |
|---|---|---|---|
| 1  | — | 67.25 | 33.76 |
| 16 | 65.45 | 26.16 | **8.23** |
| 32 | — | 26.16 | 10.27 |

| | after fix 3 | after fix 4 |
|---|---|---|
| allocated per collide | 47.14 GiB | **6.28 GiB** |
| GC share of wall (16 thr) | 39% | 12.3% |

**8.0x end to end for gpic** (65.45 → 8.23), and it confirms the fix-1 reading
on a second solver: the allocation was the loop compiling badly inside a long
function, not anything about the physics.

**Neighbour check on the two solvers this campaign did NOT touch.** Fixes 1–4
changed shared infrastructure — `_run_logical_workers` (it now unwraps a
worker's exception), `ExecutionAudit` (a lock) and `_PICSlicePairGreenCache` (a
lock field) — so spectral and the soft-Gaussian were re-measured against the
baseline rather than assumed unaffected. Production point, 16 threads:

| solver | baseline `d0fb3f2` | at HEAD | digest |
|---|---|---|---|
| Spectral      | 5.00 | 4.88 | `0x00c98cd00a439897`, identical |
| soft-Gaussian | 2.93 | 3.02 | `0x193c817f4b56ca7d`, identical |

Both within run-to-run noise, both bit-identical. Nothing leaked.

**All four CPU solvers, production point, 16 threads, s/collide:**

| solver | baseline | at HEAD | |
|---|---|---|---|
| PIC           | 41.03 | 4.20 | **9.8x** |
| GaussianPIC   | 65.45 | 8.23 | **8.0x** |
| Spectral      |  5.00 | 4.88 | untouched |
| soft-Gaussian |  2.93 | 3.02 | untouched |

The two grid solvers were 8–13x slower than the other two and are now level
with them. Every number here is bit-identical to the pre-campaign HEAD.

**Where the remaining headroom is, measured rather than guessed.** The
soft-Gaussian allocates 0.09 GiB per collide, spends ~0% in GC and still
improves from 16 to 32 threads (3.02 → 2.09 s) — it is healthy and needs
nothing. Spectral allocates **9.83 GiB** and spends **27–30%** of its wall in
GC, and regresses past 16 threads (4.88 → 6.28 at 32): it already batches its
pairs, so what it has is the allocation defect fixes 1 and 4 found twice, and
it is the obvious next target. PIC and gpic now sit at 6.3 GiB each, which is
the slice gather/scatter — each slice makes the beam round trip once per PAIR
rather than once per turn.

## Fix 5 — resident slice buffers, and fix 6 — the threaded Green table (2026-08-09)

**Thread utilisation is now measured, not inferred.**
`profiling/benchmark_collide_cpu.jl` reads process CPU seconds from
`/proc/self/stat` and reports `cpu / (wall x nthreads)`. It is only meaningful
with `JULIA_THREAD_SLEEP_THRESHOLD=0`, since spinning idle threads would
otherwise be counted as work; the harness says so when the variable is unset.

**Fix 5 — the slices are gathered once per collide, not once per pair.** A
slice used to be gathered out of the beam, copied, and scattered back for every
pair it took part in — 15 round trips per turn where one suffices — which the
profile put at **58.1% of a slice-pair's cost** and which accounted for
essentially the whole 6.28 GiB a collide allocated (26.8 MB per pair x 225
pairs = 6.0 GB, against 6.28 GiB measured). `_pic_slice_states` now holds each
slice resident with a scratch twin; a pair copies state into scratch, kicks the
scratch, and swaps. The `:source_slice` union mesh reads the STATES rather than
the beam, which is what keeps its bounds identical now that the beam is stale
until the collide ends.

**Fix 6 — the Green table build threads over columns.** After fix 5 it was the
largest block left, ~35% of a pair: four `_pic_kernel_integral` evaluations (an
`atan` and a `log` each) per cell of a 2nx x 2ny table. Every cell is a pure
function of its own `(i, j)`, so any partition is bit-exact. The loop nest also
became column-outer/row-inner, so a worker's cells are contiguous in this
column-major array instead of striding by `2nx`.

Production point, s/collide, digest `0x4625d8c583a1efa1` throughout:

| julia --threads | before fix 5 | after fixes 5+6 | allocated |
|---|---|---|---|
| 1  | 15.02 | **9.41** | 6.28 -> 1.64 GiB |
| 16 |  4.31 | **3.51** | 6.28 -> 1.79 GiB |
| 32 |  6.82 |   4.59 | |

**PIC is now 41.03 -> 3.51 s at the production point, 11.7x.**

## Utilisation is not the objective, and the measurement says why

The obvious reading of "threads are only 37% utilised" is that filling them
would cut the wall time proportionally. The instrument says otherwise, and this
is the campaign's most useful negative result:

| threads | wall | CPU | utilisation |
|---|---|---|---|
| 1  | 9.41 |  9.4 s | 99.8% |
| 16 | 3.51 | 21.1 s | 37.5% |
| 32 | 4.59 | 45.0 s | 28.7% |

**CPU time more than doubles** going from 1 to 16 threads for the same work.
Sixteen threads burn 21 CPU-seconds to do what one thread does in 9.4.

**Two different quantities, and this note conflated them once in each
direction.** CPU-time inflation and the wall-time ceiling have different
causes, and each was mis-attributed before being measured:

- **CPU-time inflation is dominated by GC threads.** Julia scales its GC thread
  count with `--threads`; running with `--gcthreads=4` cuts CPU from 40.7 to
  26.4 s at 64 threads. It does NOT improve wall time (4.12 -> 4.71 s — fewer
  markers make each collection slower), so CPU inflation is a red herring for
  the ceiling.
- **The wall-time ceiling is memory bandwidth**, and this one IS measured, by
  three tests that separate it from the alternatives:

  1. *Not the wavefront width.* Raising the slice count from 15 to 31 nearly
     doubles the available pair parallelism and lifts utilisation (38.6% ->
     48.8% at 16 threads), and 32 threads is still slower than 16 (6.20 against
     5.83 s). More independent work does not help.
  2. *Not NUMA latency.* `numactl --cpunodebind=0 --membind=0` gives ~10%
     (16 threads 6.39 -> 5.74, 32 threads 6.49 -> 6.12) and does not change the
     shape: 32 still loses to 16 with all memory local.
  3. *Positive control.* Shrink the working set until it is cache-resident
     (256k/102k over 31 slices, ~400 KB per slice) and the direction REVERSES:
     32 threads beats 16, 3.95 against 4.13 s. Same code, same schedule, same
     thread counts — only the footprint changed.

  Growing CPU time with flat wall time is the signature of a shared resource
  being saturated, and (3) identifies which one.

**What the wall-time cliff actually was: this campaign's own nesting rule.**
Going 16 -> 32 threads made the collide *slower*, 3.5 -> 4.6 s, which is not
something a thread count should do. A natural experiment isolates it. The pool
caps at 15 (one per slice), so `inner_workers = fld(nthreads, pool)` is 1 up to
29 threads and 2 from 30:

| threads | 16 | 20 | 29 | **30** | 32 |
|---|---|---|---|---|---|
| wall | 3.40 | 3.45 | 3.82 | **4.54** | 4.99 |
| cpu | 20.1 | 19.8 | 25.9 | **43.9** | 49.5 |

The step lands exactly where the split turns on, not on a smooth curve. So the
per-pair maps were being split on top of an already-parallel pair loop and
paying for it. With nesting removed inside the batched loop: **3.45 s at 16,
4.00 at 32, 4.36 at 64** — the cliff is gone and wide pools merely stop helping
rather than hurting.

That also explains why the per-batch allocation measured worse twice (4.20 ->
5.41, then 3.20 -> 3.94): it is a *finer* nesting rule, and nesting itself was
the problem.

## Fix 8 — one copy per pair instead of two

Both interactions of a pair must see their SOURCE slice as it stood before the
pair. Direction 1 reads slice `i` and writes slice `j`; direction 2 reads `j`
and writes `i`. In that order direction 1 has finished reading slice `i` before
direction 2 writes it — so **slice `i` can be kicked in place and needs no copy
at all**. Only slice `j` needs one, because direction 1 writes it before
direction 2 reads it. Copying both was the obvious form and cost twice the
traffic; aliasing the LARGER side (the 8.19 MB electron slice, against 3.28 MB
for a proton one) is where the saving is.

Production point, 16 threads: **3.45 -> 3.03 s**, allocation 1.79 -> 1.68 GiB,
digest unchanged. **PIC is now 41.03 -> 3.03 s, 13.5x.**

This is the shape the bandwidth finding implies: at a fixed schedule, the way
to go faster is to move fewer bytes per pair, not to spread the same bytes over
more threads.

## Fix 9 — the virtual-position buffers are reused, not reallocated

`_pic_interaction!`, `_pic_interaction_node!` and `_gpic_interaction!` each
allocated a fresh `vx`/`vy` pair for the source's virtual positions at the
luminosity plane: 3.82 MB per pair, 450 interactions per turn, **0.86 GiB per
collide** of the 1.68 that remained. They now come from two reusable slots on
the (per-worker) workspace — two, because both directions' results are alive at
once for `_pic_luminosity`, so one slot would alias.

`vslot = 0` still allocates, which is what the direct callers in `test/` and
`validation/` want; a working type that does not match the workspace's falls
back to allocation rather than asserting. The `mode === :pic` delegation inside
`_gpic_interaction!` forwards the slot — without that, gpic's most common route
would have kept allocating with nothing to show it.

| | before | after |
|---|---|---|
| allocated per collide (1 thread) | 1.68 GiB | **0.74 GiB** |
| 1 thread | 9.39 s | **8.81 s** |
| 16 threads | 3.03 s | **2.99 s** |
| 32 threads | 4.15 s | 3.82 s |
| GC pauses per collide | 13 | 7 |

Digest `0x4625d8c583a1efa1` unchanged. **PIC is 41.03 -> 2.99 s, 13.7x**, and
allocation is down 8.5x from the campaign's start.

The gain is largest at 1 and 32 threads and inside noise at 16, which is what
the bandwidth reading predicts: at 16 threads the memory system is already the
constraint, so removing allocation helps most where it is not.

## Fix 10 — the same treatment for GaussianPIC

gpic had received the batching and the kick extraction but not the structural
half: it still gathered and scattered per pair and copied both slices. Ported
`_pic_slice_states`, the single copy with slice `i` kicked in place, and the
end-of-collide scatter. gpic is the simpler case again — it rejects
`interaction_grid`, so there is no `:source_slice` union mesh to keep reading
live values.

| | before | after |
|---|---|---|
| production, 1 thread | 33.76 s | **27.50 s** |
| production, 16 threads | 8.23 s | **6.75 s** |
| allocated per collide | 6.28 GiB | **1.02 GiB** |
| GC share (16 threads) | 12.3% | **3.0%** |

Digest `0x58fc69d46333dfe0` unchanged. **gpic is 65.45 -> 6.75 s, 9.7x.**

Smaller than PIC's gain from the same change, and the reason is worth keeping:
gpic's per-pair physics (source moments, the coupled solve, the
Bassetti-Erskine add-back) is a larger share of its pair than PIC's is, so the
gather/scatter it removed was a smaller fraction to begin with. The fix is the
same; the leverage is not.

## Campaign result

All four CPU solvers, production point, 16 threads, s/collide:

| solver | baseline `d0fb3f2` | at HEAD | |
|---|---|---|---|
| PIC           | 41.03 | **2.99** | **13.7x** |
| GaussianPIC   | 65.45 | **6.75** | **9.7x** |
| Spectral      |  5.00 |   4.88 | untouched |
| soft-Gaussian |  2.93 |   3.02 | untouched |

End to end through the production harness, PIC at 16 threads: **40.8 -> 4.06
s/turn**, a 200-turn run going from 2 h 16 min to about 13.5 minutes. (The
baseline is the recorded mean over turns 100-200; the new figure is the mean
over turns 2-20 of the same harness at the same point.)

Every number in this campaign is bit-identical to the pre-campaign HEAD: one
digest per solver, held across ten fixes and every thread count from 1 to 128.

## The regression guard

The campaign left the suite able to lose all of this with the gate still green,
so it now carries a performance regression test — asserting **allocation**, not
wall time.

Wall time is what users care about, but a wall-clock bound in `runtests.jl`
would be the wrong instrument: the file aborts at its first failure, so one
flake on a loaded shared machine costs the whole gate including the CUDA half,
which is the recorded dominant failure class. Timing stays in
`profiling/benchmark_collide_cpu.jl`, on demand.

Allocation is the right proxy here because it is deterministic and
machine-independent — it cannot flake — and because it is what this campaign
actually bought: the wall-time ceiling was measured to be memory bandwidth, so
bytes moved is the quantity that governs.

The test asserts the PROPERTY rather than a magic number: a collide's
allocation is set by the BEAM size, not by the number of slice pairs, because
each slice is now held resident and copied once per pair instead of gathered,
copied and scattered. Quadrupling the pairs must barely move it.

Discriminating power, measured against the pre-campaign commit `d0fb3f2`:

| | at HEAD | `d0fb3f2` |
|---|---|---|
| 3 slices, 9 pairs | 6.1 x beam | **110.7 x beam** |
| 6 slices, 36 pairs | 6.9 x beam | **219.0 x beam** |
| growth, 9 -> 36 pairs | 1.14x | **1.98x** |

Bounds are 20x beam and 1.5x growth: roughly 3x headroom at HEAD, and the old
code fails both by a wide margin. Verified stable at 1, 4, 8, 16 and 32 threads
(5.3-7.5x beam, growth 1.14-1.25x) — it plateaus because the workspace pool
caps at the slice count. Anti-vacuous: a collide that did nothing would
allocate nothing and pass every bound, so the luminosity is asserted finite and
positive first.

## The honest ceiling statement

Wall time is the objective; the utilisation number can rise while it worsens,
so it is a diagnostic and not a target.

**Threads do pay, up to a point that is set by bandwidth**: 9.39 s at one
thread to 3.03 s at sixteen, a 3.1x speedup on a workload that measured no
speedup at all at the start of this campaign. Past ~16 threads at production
sizes the memory system is saturated (evidence above), so the route to using
more of the machine is **less traffic per unit of work**, not finer division of
the same traffic. That is what the last three fixes did — 6.28 GiB -> 1.68 GiB
per collide — and where the remaining headroom is: the per-interaction `vx`/`vy`
buffers are 0.86 GiB of the 1.68 that remain, and are reusable per worker.

**The trap fired a third time, in a new shape.** Here `phiL, ExL, EyL` and
`phiR, ExR, EyR` were assigned in BOTH branches of `if use_coupled`, which was
harmless while nothing captured them — adding the kick closure is what turned
two assignments at function scope into a `Core.Box`. Fixed by making the branch
an `if` EXPRESSION with a single assignment site. Worth generalising: any
`if`/`else` that assigns the same name in both branches becomes a boxing defect
the moment a closure is introduced below it, so extracting a loop into a
closure means re-checking every name it reads.
