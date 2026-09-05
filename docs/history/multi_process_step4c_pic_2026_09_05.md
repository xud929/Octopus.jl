# The PIC Collide Across Ranks — Step 4c, PIC, 2026-09-05

Step 4a divided the soft-Gaussian collide and 4b the task around it; this
divides `PICPoissonSolver`'s CPU collide, the production solver, and the first
with a mesh. Gaussian-PIC and spectral follow the same shape and still refuse.

## What had to span the ranks

Each rank holds a chunk-aligned shard of each beam (the 4b scope). A PIC pair
deposits a slice's macroparticles onto a grid, solves the field by an FFT
convolution with the Green function, and interpolates the kick back to the
other slice's particles. The division is the obvious one -- each rank deposits
its own particles, the DEPOSITED CHARGE GRID is all-summed, every rank solves
the identical field redundantly and kicks its own particles -- and the work,
as in every step of this campaign, was the list of things that had quietly
been the shard's:

1. **The mesh extents**, from both slices' drifted extrema: all-reduced with
   min and max, which associate, so the grids, the quantized extents, the
   node and source-slice meshes and the slice-pair Green cache's reuse
   decisions all run identically on every rank from identical inputs. The
   Green cache works divided with no exchange because every rank holds the
   same one. Under `grid_extent = :sigma` the estimator's shift origin is the
   slice's globally-first member, obtained the 4a way (the owner contributes,
   the others zeros, one all-sum), re-read per direction because direction 1
   kicks its field slice in place before direction 2 reads it.
2. **Every plane's deposit**, all-summed before its solve: two per direction,
   three under quadratic interpolation or node mode.
3. **The luminosity**: the overlap mesh's extent from both slices' virtual
   positions across every rank, both deposits all-summed, the overlap then the
   beam's on every rank and returned as it is -- not summed again.
4. **The kick scale.** `_pic_kbb1` divides the physical scale by the source
   beam's macroparticle count and read `length(beam.rep)`, the shard's. The
   first divided run scaled every kick by the rank count: 1.9x at two ranks,
   3.5x at four, with the luminosity series falling to 0.82 and 0.65 of the
   undivided one. It reads the scoped global count now, as the luminosity
   scale does.
5. **Every skip**, from the slices' global counts in the shared plan: the pair
   itself, the node-mesh prebuild. A rank holding no member of a populated
   slice starts its extrema from infinity, deposits nothing, and still owes
   every collective of the pair.
6. **The non-finite chokepoints** in the interaction, the node-mesh build and
   the source-slice union bounds: each takes its verdict on the local data,
   agrees it across the ranks as a count, and throws on every rank or none.
7. **The dropped-charge count**: the beam's, warned once by rank 0.

Two more things worth recording. The bare-collide arms of the launcher check
first ran OUTSIDE the policy scope, where the collide sees a communicator of
one and collides the shard alone as if it were the beam; their luminosity fell
as 1/P^2 and looked like a defect in the division until it was recognised as
the instrument's -- the 3c lesson, met again. And at more than one rank the
wavefront batches keep their order but their pairs run one at a time on the
main thread (MPI is `:funneled`, and the seam's tripwire throws off it), with
the inner per-particle maps keeping the thread pool; the batched exchange of a
whole wavefront's planes in one message is the performance phase.

## Measured

The launcher child runs a PIC task on the 4b fixture -- two beams of 256 and
192 macroparticles, radiating lines, line-placed moment observers, the run
artifact -- for two turns at 1, 2 and 4 ranks, then one bare collide per
option route: the default, `:node` and `:source_slice` meshes, the `:sigma`
extent, quadratic interpolation, TSC deposition, no Green cache, a separate
luminosity mesh, the fourth-order field, quantized meshes, the lattice Green
function, and the transverse-only map. Every route is shown to differ from the
default on the same beams, so none is a vacuous arm.

| ranks | task luminosity series and fingerprints vs one rank | worst over the eleven option routes vs one rank | the 64-slice `:sparse` arm (4096 pairs) | grid all-sums recorded |
|---|---|---|---|---|
| 1 | reference (== this process's CPU run, bit for bit) | reference (bit for bit) | reference | 0 |
| 2 | 4.0e-15 | 7.1e-15 | 8.8e-14 | 72 |
| 4 | 1.7e-15 | 6.8e-15 | (not run at four in the suite) | 72 |

The `:big` arm (32768 macroparticles per beam on a 5 x 5 mesh, the threaded
deposit on every rank) agrees to 8.1e-16 at two ranks; the `:threads2` arm
equals the default bit for bit at one and two ranks; the `:node` arm's
dropped count is 29 at every rank count; the luminosity every rank reports is
the same bits on both ranks for every arm.

The 72 is the count a 9-pair, two-plane, two-turn run owes (9 x 2 directions
x 2 planes x 2 turns), asserted from the collective receipts so a run that
never divided anything cannot pass by agreeing with itself. The cross-rank
agreement is the parity class the design prices: the deposit's chunk fold is
keyed by member-list position, which no shard aligns with, so a divided grid
differs from the undivided one by accumulation order; the suite pins 1e-12
with an order of margin on the worst arm (the 4096-pair one) and three on the
rest, the CPU/CUDA contract's class. The one-rank run
reproduces `CPUThreadsExecutionPolicy` bit for bit on every route, pinned
in-process and through the launcher.

Not re-measured: performance. Phase 1 exchanges the whole padded 2nx x 2ny
grid per plane through the seam's ordered all-sum (Allgather plus fold), which
is O(P) in volume; at the production point that is 900 planes of 512 KB per
collide and is the target of the performance phase.

## The CPU/MPI/CUDA consistency contract

The design's consistency table is now one public object for PIC,
`StrongStrongPICMultiProcessConsistencyContract`. It takes the PIC backend
contract's beams and task (1024 macroparticles per beam, two turns, a 32 x 32
mesh, three quantile slices, the slice-pair Green cache), runs them under
`CPUThreadsExecutionPolicy` in the calling process, and launches
`src/contracts/mpi_pic_consistency_child.jl` at each rank count asked for.
Every rank of the child draws the same beams under the multi-process policy --
the constructor draws the whole beam and keeps the rank's shard, which is
bit-identical to the undivided beam by construction, so the parent and the
child compare the same particles without any coordinates crossing a process
boundary on the way in -- runs the same task divided, gathers both beams onto
rank 0 in shard order and writes them with the luminosity series to a file
the parent reads. One rank must reproduce the CPU run bit for bit; more
ranks must agree to `rtol = 1e-11` on the coordinates (pointwise, against
`atol + rtol * |x|`, `atol = 1e-18`) and `luminosity_rtol = 1e-12` on every
turn. With
`cuda = true` it then runs `StrongStrongPICBackendConsistencyContract` on the
same beams and reports the MPI-to-CUDA distance as the triangle bound, the sum
of the two legs' distances from the CPU, since no rank can hold a CUDA beam.

A rank count is a property of a launched process, so the contract needs the
launcher command (`mpiexec = MPICH_jll.mpiexec()` in the suite) and a project
that carries `MPI`, which it forwards as the current project and load path;
the child asserts the extension is loaded rather than run as one process
under the passthrough. Without a launcher the result is `:skipped` and names
the legs it did not run; a requested CUDA leg the device cannot run
downgrades the whole result to `:skipped` as well, because the three-way
claim is not made on two legs. A rank count the shard rule refuses fails
before anything is launched.

Measured on the contract's own fixture (this box, 2026-09-05):

| leg | coordinates vs CPU, max abs | vs CPU, against the beam scale | luminosity series vs CPU, max rel |
|---|---|---|---|
| MPI, 1 rank | 0 (bit for bit) | 0 | 0 (bit for bit) |
| MPI, 2 ranks | 5.5e-17 | 2.3e-15 | 1.6e-15 |
| MPI, 4 ranks | 5.8e-17 | (first run, before the ratio was recorded) | 1.1e-15 |
| CUDA | 5.1e-17 | (that contract's own metrics) | 9.6e-16 |

At two ranks the pointwise ratio to a 1e-12 allowance was 0.18, so the
default `rtol` is 1e-11 (a factor 50 of margin on the criterion; the
luminosity's 1e-12 has 600). The MPI-to-CUDA luminosity bound is 2.6e-15,
the sum of the two legs. The CPU/MPI/CUDA relation the design's table states
in words is therefore measured for PIC at 2.6e-15 relative on the observable
and at the parity class on every coordinate, with one rank exactly the CPU.
The whole contract, three legs, ran in 119 s on this box with the child's
extension already precompiled.

The suite's launcher lane runs the contract at 1 and 2 ranks with the CUDA
leg whenever the device is active and asserts `:passed`, the one-rank bitwise
flag and the CUDA leg's status (`:passed` with the device, `:not_run` without
-- never a pass by omission); the fast lane pins the no-launcher `:skipped`,
the refused rank count, and the round trip of the words the child rebuilds
the contract from. `StrongStrongTask` lists the contract among its required
ones, so the registry snapshot names it.

## What the adversarial review of the plan found, and what was done

Four lenses over the phase-1 plan against the 4b tree, every finding
verified by an independent refuter; the confirmed ones and their fate:

- **The kick and luminosity scales divided by the shard's count** (three
  lenses, independently). Found by measurement before the review returned;
  fixed as above. The review added that the fixture's explicit
  `luminosity_scale = 1.0` hid the default `npart / (n1 n2)` path, so the
  launcher check gained a `:lumscale` arm on the default scale (the contract
  runs the default scale too).
- **A NaN is not a signal across ranks.** `MPI_MIN`/`MPI_MAX` with a NaN
  input return rank-divergent results -- reproduced under MPICH: at two ranks
  the rank holding the NaN got it back and its peer got the finite value, at
  four the finite values themselves differed by rank -- so folding a NaN
  indicator into the bounds exchange, which the plan offered as an
  alternative, would have left one rank throwing and its peers blocked. The
  implementation takes every non-finite verdict on local data, agrees it as
  an integer count and throws on every rank before any exchanged bound is
  consumed; the seam's docstrings now say so.
- **`compute_luminosity` may come from user code** (a `PredicateSchedule`)
  and gates collectives: broadcast from rank 0, as above.
- **The locally-empty-slice branch was dead in every planned test**: no
  fixture gave a rank an empty share of a globally populated slice. The
  launcher check gained a `:sparse` arm -- 64 equal-area slices on the 256
  and 192-particle beams, which at two ranks leaves 10 (rank, slice) pairs on
  beam 1 and 9 on beam 2 with no local member (85 and 104 at four ranks),
  counted from the shard rule and asserted as the arm's premise -- and the
  in-process one-rank check runs the same slicing.
- **The one-worker forcing under division was invisible at one thread**
  (where one worker is the default anyway): a `:threads2` arm runs a
  two-thread policy and pins, from the schedule receipt, one pair worker with
  two inner workers at two ranks against two pair workers on the two-thread
  CPU reference.
- **The dropped-count sum across ranks was exercised by nothing**: every arm
  now reports the beam's dropped count (captured from rank 0's warning) and
  the parent holds it equal across rank counts and to the CPU run's; the
  `:node` arm is the one that drops, and is asserted to.
- **The fixture never reached the threaded deposit** (it is ~480x short of
  the floor at grid 16): a `:big` arm collides two beams of 32768
  macroparticles on a 5 x 5 mesh, where every rank's share of every slice
  clears the floor at two ranks -- asserted from the shard rule -- so the
  chunked deposit runs divided and is compared like the others.
- **Cross-rank identity of the redundantly solved field was assumed and
  asserted by nothing**: every rank now prints its luminosity for every arm
  and the parent holds the ranks to the same bits. The luminosity is computed
  per rank from the all-summed grids and identical extents, so a rank whose
  grids differed from its peers' would show there first. (The field solve's
  FFTW plans are built with the library's default `ESTIMATE` flag, which
  chooses the algorithm by a fixed heuristic rather than by timing it, so
  every rank builds the same plan for the same mesh; a `MEASURE` plan would
  break this silently and the per-rank luminosity line is what would catch
  it.)
- **Refuted, for the record**: that Gaussian-PIC and spectral refuse only at
  the task preflight (their CPU collide entries call the same refusal); that
  the shard scope must be opened at the 4-argument entry (it is); that the
  `:sigma` origin must be read from the resident slice state rather than the
  beam (it is).
- **Noted, not changed**: the fixture's Green cache reuse is zero at its
  1e-6 kick (the beams blow up per turn), so cache HITS under division are
  exercised by the contract at the physical kick rather than by the launcher
  fixture; under `:sigma` and `grid_quantize` a cross-rank-count comparison
  rests on thresholds that are discontinuous in a last bit, which the
  measured 7e-15 did not trip but a different seed could -- the parity claim
  is for the class, not a guarantee per configuration; the `cuda_*` options
  are CUDA-only by declaration and inert under the multi-process policy,
  whose storage is CPU (the configuration report warns as it always did).

## What is left

Gaussian-PIC (its subtraction reads the slice's moments, which 4a already
globalised, and reuses PIC's deposit and solve) and spectral (its Dirichlet
box from global extrema, its deposits all-summed the same way). The
performance phase: one message per wavefront batch carrying every plane and
both luminosity deposits, a deterministic tree all-sum for grids, and the
production-point measurement.
