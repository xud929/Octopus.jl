# `batch_mode` Becomes One Keyword Across the Solvers — 2026-09-04

The soft-Gaussian collide learned to read `batch_mode` on CPU the same day
([`soft_gaussian_wavefront_cpu_2026_09_04.md`](soft_gaussian_wavefront_cpu_2026_09_04.md)),
and the audit that followed found the keyword meant three different things
across the four strong-strong solvers. `PICPoissonSolver` and
`GaussianPICPoissonSolver` declared it CUDA-only and scheduled their CPU pair
loops by their own rule (`_pic_batchable`, the mesh constraint), so
`PICPoissonSolver(batch_mode=:sequential)` on CPU still batched -- warned about
at task level, silent through a bare `collide!`, which is the shape the public
option rule forbids. `SpectralPoissonSolver` had no such keyword at all: its CPU
6D loop always batched and its CUDA loop never did, and nothing let a caller
choose or even observe which they got. The owner put this row ahead of
multi-process step 4b, under the standing constraint: reuse the keywords,
invent none.

## What it means now

On every solver and both backends, `batch_mode = :sequential` runs the slice
pairs one at a time in collision-time order, and `batch_mode = :wavefront` (the
default) runs the conflict-free batches `collision_pair_batches` builds. A batch
repeats no beam-1 and no beam-2 slice, so each slice still meets its partners
in collision-time order, and every route folds luminosity by position in that
order rather than by arrival -- so the batched schedule reproduces the
sequential one BIT FOR BIT, luminosity included. Every route that reads the
keyword records a receipt of one shape at its consumer boundary:

| field | meaning |
|---|---|
| `batch_mode` | what RAN: `:wavefront`, `:sequential`, or `:order_free`, written as a literal in the branch that executed |
| `requested` | the solver field, so a downgrade shows beside what ran |
| `pairs`, `batches`, `widest_batch` | the counts the run actually used |

The field named after the option carries what the consumer DID with it, never
a copy of the field. A first draft of this change had it the other way round
(`batch_mode` = the request, `schedule` = what ran), and the adversarial design
review caught what that does to the effectiveness contract:
`_solver_contract_receipt_carries` certifies an option by finding the field
named after it in a receipt with the requested value, so a receipt that
echoes the field would certify a loop that never read it -- the U4-6 shape
the contract exists to forbid. The tree's convention (the soft-Gaussian and
the CUDA PIC routes already wrote literals per branch) was right; the draft
was wrong, and the derived tripwire below now pins the convention for every
solver.

The consumer names are `:gaussian_pair_schedule`, `:pic_pair_schedule` (PIC
and Gaussian-PIC, both backends) and `:spectral_pair_schedule`. The CPU PIC
receipt was `:cpu_pic_pair_schedule` and lost its backend tag, for the
mechanical reason the soft-Gaussian record gives: the effectiveness contract's
`_solver_contract_receipt_carries` filters receipts by backend BEFORE it
matches the consumer name, so an option both backends read needs one name both
backends emit. The CUDA PIC and Gaussian-PIC routes now emit it beside their
`:cuda_pic_algorithm` receipt, which keeps carrying the rest of the device
configuration.

Where the request and the schedule that ran differ, the receipt shows both,
and the configuration report calls the option inactive rather than resolved:

- **PIC under `interaction_grid = :source_slice`** cannot batch whatever is
  asked -- its mesh is a union over the partner beam taken at the source
  slice's first use, so its value depends on how much of the turn has already
  been applied. `_pic_batchable` stays the mesh constraint;
  `_pic_batching_requested` is that constraint AND the request; the schema
  declares `dependencies=(:interaction_grid,)` and `_pic_option_active` reports
  `:inactive_dependency`. A run records `requested=:wavefront,
  batch_mode=:sequential`.
- **PIC on a one-worker pool** still batches under `:wavefront` -- the
  keyword is the schedule and the pool is the width, as on the other solvers.
  A first draft kept the old `pool_workers > 1` gate, and the review showed
  what that costs: the effectiveness contract's CPU half runs outside any
  policy scope at `Threads.nthreads()`, so at one thread its `:sequential`
  and `:wavefront` arms would both have run the sequential loop and agreed
  with themselves. Batching at width 1 costs nothing because the one
  exception to "no nesting inside the batched loop" is exactly the width-1
  pair level, which has nothing to nest under: there the inner maps are
  handed the whole pool, as the sequential loop hands it to them
  (`inner_workers = pool_workers > 1 ? 1 : _cpu_worker_count()`), so a 1 x N
  slicing on four threads stays threaded under the default.
- **Spectral with `longitudinal_kick = false`**: the transverse-only map reads
  original positions and only accumulates `px`/`py`, so there is no order to
  choose. The receipt says `batch_mode=:order_free`; the schema declares
  `dependencies=(:longitudinal_kick,)` and the report says inactive.
- **Spectral on CUDA** has one schedule. Its route solves each pair's
  left/right planes through ONE `_SpectralCudaWS` and has no batched field
  solve, so the option can select nothing there; the schema declares
  `supported_backends=(CPUThreadsBackend,)` with that reason, the report says
  `:inactive_backend`, and the route still records `batch_mode=:sequential`. A
  CUDA wavefront would need batched plane solves across pairs -- the shape
  `_cuda_pic_solve_wavefront_fields_batched_fft!` gives PIC -- and is priced
  as future performance work, not owed by this row.

## The spectral fold moved, deliberately

The spectral CPU 6D loop folded luminosity PER BATCH (`luminosity +=
sum(batch_parts)`), an association the code's own comment defended as
"deliberately left alone". A sequential route folding in collision order is a
different association by last bits, and `SolverOptionEffectivenessContract`
compares execution-category options EXACTLY (`!=` on coordinates, `isequal` on
luminosity) -- so either the sequential route had to reproduce the batched
grouping, or the batched route had to fold as the sequential one does. The
second is what PIC and the soft-Gaussian already do and is the honest
direction: the reference defines the fold. Both spectral routes now write each
pair's luminosity by its collision position and fold at the end in that order.

This supersedes the decision recorded in
[`cpu_threading_2026_08_09.md`](cpu_threading_2026_08_09.md) ("Fix 2") and
[`neighbour_audit_2026_08_10.md`](neighbour_audit_2026_08_10.md), and the
archive's U18-2 note that "no pinned serial value moved": the per-batch fold
was kept then precisely so the serial luminosity would not move, and it moves
now, by the amounts below. Consequences for the tracked records: the nightly
[`cpu_benchmark_history.tsv`](cpu_benchmark_history.tsv) spectral rows carry a
luminosity column (1.0247297487960337e+30 at the production point) that will
differ in its last bits from the next run against an unchanged coordinate
digest (0x00c98cd00a439897), and that is not a regression; and the
`cpu_sequential` configurations of `profiling/benchmark_strong_strong_pic.jl`
and every historical CPU "sequential" row in the `pic_option_consistency`
meta files were BATCHED runs, so their timings are not comparable with runs
after this change, which genuinely run one pair at a time.

Measured against a worktree of the pre-change commit (`db6364e`), same inputs,
same thread counts. Coordinates: bit-identical in every case (the digest column
did not move once). Luminosity:

| case | pre | post |
|---|---|---|
| synthetic 1500 x 3 slices | 3.371606888200381e14 | identical |
| synthetic 15000 x 3 | 3.3088420831010668e16 | 3.3088420831010664e16 |
| synthetic 15000 x 15 | 3.932695232428061e16 | 3.9326952324280616e16 |
| synthetic 90000 x 15 | 1.413382620846598e18 | 1.4133826208465987e18 |
| EIC-like 2000 x 3, grid (32,64) | 9.991774244030794e29 | 9.991774244030792e29 |
| EIC-like 2000 x 3, grid-free | 1.0091085108751251e30 | identical |
| EIC-like 4000 x 3, grid (64,512) | 1.017984353543896e30 | identical |
| EIC-like 20000 x 15, grid (32,64) | 1.0006237449649581e30 | 1.0006237449649577e30 |
| EIC-like 20000 x 15, grid-free | 1.0182940249165291e30 | 1.0182940249165285e30 |
| EIC-like 20000 x 15, grid (127,383) | 1.0338965527604383e30 | 1.0338965527604376e30 |

One to three last bits, relative 1e-16 to 6e-16; the CPU/CUDA spectral parity
test compares luminosity at `rtol = 1e-12` and is untouched. Thread-count
invariance holds on both sides of the change (1 and 4 workers equal in every
row), as it must: the fold order is a property of the data on both routes.
The rewrite also removed the one concurrent-closure `Core.Box` in the tree --
the per-batch accumulator reassigned under the pair closures -- so
`_spectral_collide_longitudinal!` left the sweep's allowlist.

A measurement trap worth recording: the first A/B run reported the fold change
as bit-identical at every size. It was pre against pre -- a `cd` into the
worktree earlier in the same shell command made the "post" arm's
`--project=.` resolve to the worktree too. What exposed it was a synthetic
check that the two associations differ on random data of the same batch shape
(1 and 3 ulps at 3 and 15 slices); the re-run from the repository root, with
`pathof(Octopus)` printed by both arms, gave the table above.

## What was verified

- **CPU bit-identity, every solver.** `:sequential` and `:wavefront` produce
  identical coordinates and identical luminosity for PIC, Gaussian-PIC, the
  spectral 6D and transverse maps, and the soft-Gaussian, at 1 and 4 workers,
  with the receipts asserting the wavefront arm really batched (5 x 5 slices:
  25 pairs, 9 batches, widest 5) -- at one worker too. A PIC arm at 9000
  particles per slice (3 x 27000) reaches the chunked inner map on the
  sequential side (`inner_workers = 4`) against the batched loop's pinned
  single inner worker, so the pin covers `_pic_map_particles`'s chunked-vs-
  serial claim on the collide path, which the earlier 3000-per-slice pins
  never did.
- **CUDA receipts, every route.** PIC sequential and wavefront, Gaussian-PIC
  indexed-wavefront, non-indexed wavefront and sequential, the soft-Gaussian's
  two routes, and both spectral routes record the schedule with the requested
  mode; the spectral 6D route records `:sequential` under either request.
- **The effectiveness contract, both halves, passed:** 73 options on CPU, 10
  on CUDA, 2 launch surfaces, 10 exemptions applied, 0 stale. The ledger row
  predicted `cuda_options_checked` "must rise" from 10; it stays at 10 while
  `cuda_only_options` falls from 9 to 7, because the two PIC options moved from
  the CUDA-only bucket to the both-backends-execution bucket rather than being
  added. The suite now asserts the derived identity
  `cuda_options_checked == cuda_only_options + (both-backend execution options
  from the schemas)` instead of a direction.
- `validate_configuration_metadata()` is clean with the new spectral field.
- Four new testsets: the CPU bit-identity pins with recorded-receipt
  anti-vacuity and the two inactive cases; a DERIVED tripwire over
  `_solver_contract_types()` that every solver's schema carries `batch_mode`
  with a CPU-visible execution consumer and that its receipt has the one shape
  with `requested` equal to the field and `batch_mode` equal to what ran; the
  CUDA-gated receipt checks per route; and a docs-index tripwire (every
  tracked document under `docs/` is reachable from `docs/README.md`), because
  the soft-Gaussian record of the day before had never been indexed and
  nothing noticed.
- Full gate: see the commit message for the run that covered this tree.

## What is left

- A CUDA wavefront for the spectral 6D route (batched plane solves across a
  batch's pairs), if the device's spectral throughput ever matters more than
  the ~1.5x-of-PIC it runs at today.
- Multi-process step 4c will divide PIC, Gaussian-PIC and spectral; the
  one-worker-pool condition on the CPU PIC batch should be revisited then,
  since under MPI a batch also cuts collectives and is worth issuing at one
  thread per rank, as the soft-Gaussian's is.
