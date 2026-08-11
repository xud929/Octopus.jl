# Weak-Strong CUDA Luminosity Path: Device Reduction and Buffer Reuse (2026-08-11)

Commits: `7eba18e` (buffer reuse), `6304601` (device reduction), `d7955df`
(validation-script repair found on the way).

## The observation that started it

Production weak-strong tracking on an A100 — 1M macroparticles, 15-slice
`GaussianStrongBeam`, every-turn `LuminosityObserver` — ran at **10.75 ms/turn**
with `nvidia-smi` GPU utilization fluctuating between 20% and 55%. The owner
read that as "the code is not well optimized." The number was real; the
inference was half right. Utilization is a duty-cycle metric, and the duty
cycle, not the kernels, was the problem.

## Per-turn anatomy (measured RTX 4500 Ada; host costs are GPU-independent)

| per-turn fixed cost on the observed-turn path            | ms    |
|----------------------------------------------------------|-------|
| `sum(Array(lum))` — 8 MB D2H + host sum at 1M particles  | 6.32  |
| same reduction on device (`sum(lum)`)                    | 0.63  |
| 4× slice-array `CUDA.CuArray` rebuild + upload           | 1.17  |
| `CUDA.zeros(Float64, 1M)`                                | 0.05  |
| file open/append/close on `/cfs`                         | 0.59  |

Kernel time on the A100 is ~4 ms/turn (FP64-rate scaling from the Ada
measurement, consistent with the observed duty cycle: 4/10.75 ≈ 37%, mid-band
of the 20–55% fluctuation). So the turn cycle was ~4 ms of GPU work against
~7–8 ms of host-side gap, nearly all of it the luminosity reduction: the
per-particle luminosity buffer crossed PCIe in full every observed turn and
was summed single-threaded on the host.

## What changed

1. **Buffer reuse** (`7eba18e`): `track!` for `ThinStrongBeam` and
   `GaussianStrongBeam` on CUDA allocated a fresh N-element `lum` buffer and
   rebuilt four to six ns-element slice CuArrays every call. Both now live in
   a `WeakKeyDict` workspace keyed by element identity, revalidated against
   device/eltype/lengths per call. Slice values are still uploaded every call
   (scheduled actions may mutate the host vectors between turns; the CPU path
   reads them fresh each turn) through a staging buffer that performs the same
   eltype conversion as before. The `lum` buffer is handed out uninitialized
   because both kernels write every index; the code comment carries that
   constraint.
2. **Device reduction** (`6304601`): `_cuda_luminosity_total` now reduces on
   the device; only the scalar crosses PCIe. The masked
   (`allow_lost_particles`) path fuses liveness selection into an n-ary
   `mapreduce` over the six coordinate arrays — no flags temporary, no 8 MB
   copy.

## Bitwise discipline

The owner's constraint: the modification must not change the physics —
byte-identical to the pre-change simulation. The A/B pin (100k particles, 10
turns, thin/gaussian × masked/unmasked, RTX 4500 Ada, references captured at
`4ed84e4`):

- **Particle coordinates: bit-identical in all four cases after both
  commits.** The kernels are untouched.
- **Buffer reuse alone is fully bit-identical**, luminosity series included —
  that is why it is its own commit.
- **The device reduction moves `last_luminosity` by ≤ 2.1e-16 relative**
  (1 ulp; the unmasked thin case happened to stay bit-equal). This is
  summation-order association, nothing else, and it is deterministic for a
  fixed device, length, and launch. Bitwise CPU↔CUDA luminosity equality
  never existed — the CPU backend folds fixed chunks, the old CUDA path
  summed pairwise on the host — and measured cross-backend agreement is
  unchanged: thin exact, gaussian ~1.8e-14 relative (per-particle codegen
  differences over 15 slices), against contract tolerances of 1e-10.

## Verification

- `validation/tracking_backend_consistency.jl` with
  `OCTOPUS_REQUIRE_GPU_CONTRACT=1`: all four checks pass (CPU/CPU, CPU/CUDA,
  standard and lost-particle), `max_abs_error = 0.0` on compared coordinates.
  Finding on the way: the script had been **un-runnable since 2026-08-07** —
  the U14-4 reference-pair invariant rejects the hand-picked
  `beta0=0.99, gamma0=100.0` its RF cavity carried, and the invariant's blast
  radius was never re-walked over the validations. Repaired in `d7955df` by
  deriving the pair, as the invariant's own error message prescribes. The
  neighbour rule finds its target again: the defect adjacent to a correct fix.
- New suite pins (in `6304601`), modeled on the U7-5 BPM twin of this defect:
  masked/unmasked CPU↔CUDA luminosity parity at `rtol=1e-12`, NaN-loudness of
  the unmasked path with dead particles, and a **host-allocation tripwire**
  (`@allocated < 200_000`; measured 9–13 KB/call, the old copy was 1.6 MB at
  the test size) so the D2H reduction cannot silently return.

## Measured effect

RTX 4500 Ada (FP64 1/64 rate, kernel-dominated, ±4 ms clock noise at ~100
ms/turn): every-turn-luminosity case 110.3 → 104.8 ms/turn. The
microbenchmarks above are the clean per-cost signal on this card.

A100 at the production point: predicted ~10.75 → 4.5–5.5 ms/turn (~2.2×) for
every-turn luminosity, GPU utilization from ~30% to ~70–80%. **To be
confirmed on the production machine**; the pre-change 10.75 ms/turn is the
owner's measurement, 2026-08-11.

## A100 confirmation and the filesystem finding (later the same day)

The owner's production batch (4 GPUs, 4 cases, `result/` on the cluster
filesystem) still measured 11.05 ms/turn on the new code — which looked like
the optimization failing. A steady-state anatomy harness run on the
production A100 attributed it instead:

| A100, 1.024M particles, ns=7, observer files on: | node-local tmp | cluster fs |
|--------------------------------------------------|---------------:|-----------:|
| bare line                                        | 3.407          | 3.391      |
| + luminosity every turn                          | 3.406          | 5.740      |
| + moments every turn (`capacity=100`)            | 5.150          | 6.711      |
| + both (the production configuration)            | 5.281          | 10.392     |

Readings: the device-reduction fix works — every-turn luminosity observation
costs 0.001 ms/turn on local storage, and the production-shaped line hits the
predicted 4–6 ms band (5.28). The remaining gap to 11.05 was **filesystem
cost**: ~2.3 ms/turn for the `.lum` per-turn open/append/close and ~1.6
ms/turn amortized HDF5 moment flushes (the owner's explicit
`moment_capacity=100` is 10x below the `MomentObserver` default of 1024).
False trails burned on the way, recorded so the next session does not repeat
them: GPU memory occupancy (750 MB resident of 40 GB — irrelevant), stale
code on the Distributed workers (`addprocs` does not inherit the notebook
project; ruled out by `isdefined` on every worker), and amortized first-call
compilation (ruled out at 186k turns).

Fix: `LuminosityObserver(path; capacity=N)` — rows buffer in memory and one
append writes them all, mirroring the moment observers' capacity pattern.
Default `capacity=1` preserves the old per-turn durability byte-for-byte;
`finalize_observer!` flushes on both execute! exit paths (T7), replay
discard empties pending rows first, and the file format is pinned
byte-identical across capacities. Measured on `/cfs`: 0.590 → 0.021 ms/turn
at `capacity=100` (28x). The strong-strong task never had this cost — its
`luminosity_path` streams through one handle held open across the whole
`execute!` (`interface.jl` run body), the third and fastest of the three
output designs now in the tree.

## Fused moment reductions (same day, third campaign)

With luminosity output at ~0.02 ms, the anatomy's next line was the
`MomentObserver`: 1.74 ms/turn at the A100 production point even with files
on local storage — not I/O but ~33 host sync round-trips and ~80 full-array
passes per observed turn (6 mean reductions, then fill/broadcast/sum per
order >= 2 moment, one scalar D2H each). Replaced by a fused two-pass
kernel: pass 1 computes the six coordinate sums plus the live count in one
sweep (a zero-power row's term is 1.0, so it counts what the mask admits);
pass 2 takes the means and accumulates every order >= 2 power row per
thread in registers, block-reduces each in a fixed-order shared-memory
tree, and the host finishes over block partials in block order — two
round-trips, two passes, no float atomics, bitwise run-to-run
deterministic. Power rows are staged in shared memory (global re-reads of
the powers matrix dominated the first version: 1.0 ms vs 0.94 after).
Selections whose order >= 2 count exceeds the 32-row register budget fall
back to the per-moment path, asserted in the suite at the workspace type.

Liveness semantics are unchanged and pinned: masked rows skip dead
particles inside the kernel; unmasked rows stay loud — a dead coordinate
poisons exactly the moments that touch it, and the suite pins the NaN
pattern equal to the CPU fold's, which remains the shared numerics oracle
(agreement ≤ 1.2e-13 measured, rtol 1e-12 pinned).

Measured, RTX 4500 Ada, 1.024M particles, default 27-moment set:
`observe!` 2.83 → 0.96 ms/turn. The Ada kernel is FP64-throttled (1/64
rate); on the A100 the fused passes are bandwidth-bound, projected
0.15–0.2 ms/turn against the measured 1.74. Benefits weak-strong and
strong-strong alike — the observer is task- and backend-agnostic, and
strong-strong lines carry it per beam at larger particle counts.

## Left open, deliberately

- The `:auto` blocks path for the isolated weak-strong elements caps at 256
  blocks (65,536 threads — an A100 holds ~221k resident). Worth an explicit
  `CUDALaunchConfig(threads=256, blocks=2048)` sweep on the A100; not changed
  here because the cap is also the fused-tracking convention and the kernel,
  not the launch, dominated the observed problem.
- Decimating the luminosity schedule
  (`ScheduledObserver(obs, EveryNSteps(step=10))`) remains the zero-code
  mitigation for workflows that do not need the turn-by-turn signal; on
  off-turns the fused plan already skips this entire path.
