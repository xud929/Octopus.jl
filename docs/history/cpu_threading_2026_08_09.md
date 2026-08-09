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
