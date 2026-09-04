# Weak-Strong Allocation Extraction, Multi-Process Step 1 — 2026-09-04

Step 1 of the decided order in
[`multi_process_phase0_2026_08_19.md`](multi_process_phase0_2026_08_19.md):
the single-process fix that every later rank inherits. Phase 0 measured the
weak-strong `TrackingTask` path allocation/GC-bound — 1.282 GiB per turn at
every thread count, GC share 3.2% → 30.8% → 52.2% at 1/16/64 threads, the
16-thread optimum set by the collector rather than by the arithmetic — and
named the fix-1/fix-9 extraction pattern of the CPU-threading campaign as the
cure. This record is the localisation, the fix, the before/after measurements
at the production point, the pin shown to fail unfixed, and the neighbour
audit. Tree: HEAD `5dd9e22` before, this commit after. Box: the 128-thread
node, Julia 1.12.4, `JULIA_THREAD_SLEEP_THRESHOLD=0` throughout, the RTX 4500
Ada idle with 11,933 MiB of its 24,570 MiB in use by an unrelated IJulia
kernel (`nvidia-smi` memory.used). Load at launch is in the curve section.
Line numbers refer to this commit's tree, except the localisation section's, which are HEAD `5dd9e22`'s (the site no longer exists).

## Localisation (before any edit)

`profiling/benchmark_track_cpu.jl` gained an opt-in mode,
`OCTOPUS_BENCH_ALLOC_PROFILE=1`, that replaces the timed windows with the
allocation localisation: bytes per particle for one fused turn of the whole
line and of each element alone (the beam restored between measurements), then
`Profile.Allocs` top sites by innermost Octopus frame. At n = 16,384, four
threads, on the unfixed tree:

| element | B/particle/turn | allocs/particle |
|---|---|---|
| whole 12-element line | 1344.8 | 7.002 |
| `GaussianStrongBeam` (7 slices) | **1344.1** | **7.002** |
| each of the other 11 (`Linear6D` x5, `ThinCrabCavity` x2, `LorentzBoost`, `RevLorentzBoost`, `ChromaticityKick`, `LumpedRad`) | 0.1–0.2 | 0.002 |

Profile: 125,284 samples at rate 1.0; **97.5% of sampled bytes at one site**
(by element, 1344.1 of the line's 1344.8 B per particle per turn; the other
2.4% of samples is the profiler's own frame, and 1344 B x 1,024,000 is the
whole 1.282 GiB/turn),
`ThinStrongBeam` construction at `strong_beam.jl:201` ← `_slice_thin_strong_beam`
(:479) ← `track_particle(::WeakStrongBeamBeamMap, ::GaussianStrongBeam)` (:452),
1344.0 B/particle/turn; the residue is the profiler's own frames and the
per-call worker-task constants. Mechanism: the per-slice copy was a fresh
`mutable struct ThinStrongBeam` (176 B payload, 192 B pool class) handed to
the non-inlined `_thin_strong_beam_track`, so it escaped to the heap — 7
slices x 192 B = 1344 B and exactly 7.00 allocations per particle per turn.
1344 B x 1,024,000 = 1.2817 GiB: the Phase 0 number to four digits. (The
Phase 0 record's "1.25 KB per particle per turn" is the same figure read as
decimal gigabytes; the binary reading is 1344 B. Corrected here and in the
todo row; the frozen record is untouched, per the ledger rule.)

The elementwise luminosity copy of the loop
(`_track_gaussian_strong_beam_with_luminosity`, `strong_beam_track.jl`), the
route every observer or artifact run takes, carried the same site: 1344 B per
particle on a single call, measured before the edit.

## The fix

`src/elements/strong_beam.jl`: an immutable, isbits `ThinStrongBeamSlice{T,P,D}`
carrying the eleven fields the kick chain reads (moments, kbb, klum, xo, yo,
zo, pxo, pyo, ppxo, ppyo, the virtual drift) and neither `method`,
`last_luminosity`, nor the base element's `pzo`/`ppzo`, which no kick method
reads on either backend (the review's one confirmed finding: a first cut
carried them, and the docstring overstated); `_slice_thin_strong_beam`
returns it; the four kick-chain
annotations (`_thin_strong_beam_track`, the two virtual-drift wrappers,
`_cp_kick`) widen to `Union{ThinStrongBeam,ThinStrongBeamSlice}`. The bodies of
`_thin_strong_beam_track`, `_cp_kick` and `_cp_covariance_kick` are
byte-identical to before. The base `ThinStrongBeam` stays mutable (the
elementwise paths write its `last_luminosity` at `strong_beam_track.jl:83`,
`:125`, `:356`, `:411`); the slice is not an `AbstractTrackOp`, so the registry
snapshot is unchanged. The CUDA kick chain (`_cuda_thin_strong_beam_track`,
scalar arguments, its own `_cuda_cp_covariance_kick` rounding) was not
touched and was deliberately not unified with the CPU chain: their covariance
arithmetic rounds differently, and routing the CPU through it would move the
digest.

## Fingerprints across the edit (n = 65,536, three turns, four threads)

Probe: the benchmark's line at n = 65,536, `set_global_rng!(seed=123456789,
method=:philox)`, three turns, four threads; `coordinate_digest` as the
benchmark computes it; luminosity printed at full precision.

| route | before (`5dd9e22`) | after | equal |
|---|---|---|---|
| fused fast path (`execute!`, bare task) | `0x197922777bb209b6` | `0x197922777bb209b6` | yes |
| elementwise luminosity (`track!(rep, elem, 3, policy)`) | `0xcd5fd08e727d2391`, `last_luminosity` 1.0722357610918731e30 | same, same | yes |
| artifact route (isolated segment in a task) | `0x197922777bb209b6`; series 1.0720723597201638e30, 1.0829373703389317e30, 1.053992360844103e30 | same, same | yes |
| single-particle `@allocated`, callable / elementwise fn | 1344 B / 1344 B, 1 LLVM allocation site | **0 B / 0 B, 0 sites** | — |
| the slice type | `ThinStrongBeam{...}`, not isbits | `ThinStrongBeamSlice{Float64, StrongTransverseMoments{Float64,false}, HirataParaxialDrift}`, isbits | — |

The fused and artifact routes share a digest because the isolated segment
tracks the same fused callable; the elementwise route differs from them by
construction (its own loop copy and luminosity fold), and it is the copy the
benchmark never exercised — hence its own row.

Reduced-point benchmark (n = 65,536, 4 turns, one window, four threads):
before 0.0894 s/turn, GC 19.4%, 0.082 GiB/turn; after 0.0585 s/turn, GC 0.0%,
0.000 GiB/turn; `WS-DIGEST 0x8e9da2d1ab86966e` both.

The committed instrument's localisation mode on the fixed tree: whole line
0.8 B/particle/turn (the per-call constants over 16,384 particles),
`GaussianStrongBeam` 0.1 B, and no element or kick-chain frame among the
sampled sites; the only Octopus frames are the worker-task constants in
`Policies.jl` (1.9% of sampled bytes), the rest the profiler's own frame.

## Production-point curve, before and after

Protocol as Phase 0: 1,024,000 particles, a 2-turn warm-up, three timed
windows of 20 turns, median s/turn; `WS-DIGEST` after 62 turns.

| threads | before s/turn | after s/turn | speedup after/before | before GC | after GC | before alloc | after alloc | digest |
|---|---|---|---|---|---|---|---|---|
| 1  | 2.2270 | 2.0857 | 1.07x | 3.2%  | 0.0% | 1.282 GiB/turn | 0.000 | `0xbb09efa9e44e2017` both |
| 4  | 0.6926 | 0.5753 | 1.20x | 14.7% | 0.0% | 1.282 | 0.000 | same |
| 8  | 0.4493 | 0.2845 | 1.58x | 22.1% | 0.0% | 1.282 | 0.000 | same |
| 16 | 0.6464 | 0.1703 | 3.80x | 37.0% | 0.0% | 1.282 | 0.000 | same |
| 32 | 0.6306 | 0.1105 | 5.71x | 41.0% | 0.0% | 1.282 | 0.000 | same |
| 64 | 0.7283 | 0.0851 | **8.56x** | 52.9% | 0.0% | 1.282 | 0.000 | same |

Speedup over the 1-thread after-point: 3.6x at 4, 7.3x at 8, 12.2x at 16,
18.9x at 32, 24.5x at 64 threads. The curve is monotone to 64 threads; the
collector no longer sets an optimum. GC and allocation are the window
medians as printed; every after-window read 0.0% GC.

This after-curve is the second one measured: a first run on the 13-field
first cut of the slice (before `pzo`/`ppzo` were dropped, same protocol,
launched under a higher ambient load) gave 2.121 / 0.568 / 0.296 / 0.203 /
0.114 / 0.087 s/turn at 1/4/8/16/32/64 threads, the same digest, and the same
0.0% GC — within a few percent of the table, which is the final tree's.

Load at launch (1-minute / 5-minute averages, the previous run's spinning
threads still in the 1-minute figure): before 1.0–8.1 / 0.6–4.2; after
0.7–7.6 / 0.4–3.0.

Two notes on the before-curve. (1) Today's unfixed 16-thread point (0.646
s/turn, GC 37.0%) is slower than Phase 0's (0.400, 30.8%) on the same tree,
protocol and box, and today's unfixed optimum sits at 8 threads; the
allocation and the digest are identical, so the difference is machine state
(the RTX 4500 Ada held 11,933 MiB for an unrelated IJulia kernel throughout;
the load figures are above). A GC-bound loop is exactly the kind whose wall
time moves with ambient state; the after-curve does not have that
sensitivity to lose. (2) The Phase 0 weak-strong P x T inputs -- "optimum 16
threads", "2x32 loses to 2x16" for THIS path -- are superseded by the
after-curve: with the per-particle allocation gone, the per-process thread
optimum for weak-strong is no longer set by the collector, and step 3's
rank-count decision should re-measure against the fixed tree rather than
read Phase 0's Part A. Not re-measured here: thread counts above 64, and the
strong-strong P x T matrix (unaffected: its collide path was already
allocation-free after fix 1).

## The pin, shown to fail unfixed

`test/runtests.jl`, "CPU weak-strong strong-beam tracking allocation does not
scale with the particle count": both loop copies, n = 20,000 vs 40,000,
warm-first with fresh reps, `bytes(2n) <= 1.5 * bytes(n)`, with anti-vacuity
checks (the coordinates moved; the elementwise luminosity is finite and
positive). Standalone in package mode at four threads:

| tree | copy | n=20,000 | n=40,000 | growth | verdict |
|---|---|---|---|---|---|
| unfixed `5dd9e22` | fused | 26,882,368 B | 53,762,368 B | 2.000 | **fails** |
| unfixed `5dd9e22` | elementwise | 26,910,416 B | 53,790,416 B | 1.999 | **fails** |
| fixed (this commit) | fused | 2,368 B | 2,368 B | 1.000 | passes |
| fixed (this commit) | elementwise | 30,416 B | 30,416 B | 1.000 | passes |

The fixed-tree bytes are the per-call constants: the worker tasks of
`_run_logical_workers` on the fused path, plus the 64-chunk `zeros` fold and
its tasks on the elementwise path. Neither has a term in n.

The "Weak-strong luminosity is thread-count invariant" testset gained a
`GaussianStrongBeam` arm (five slices, 1/2/nthreads workers, `==` on
`last_luminosity` and `px`, anti-vacuity on the luminosity), because it tracked
a `ThinStrongBeam` only and neither changed loop copy was under it.

## Targeted checks and the gate

Targeted checks first, the gate last, per the matrix rows this diff falls
under (element kernels; concurrency surfaces; validation/benchmark; docs plus
code). All on the final tree unless stated.

- **Symplecticity.** `validate(SymplecticityContract())` passed: residuals
  `ThinStrongBeam` 7.9e-8 (all three drift variants), `GaussianStrongBeam`
  4.2e-8, no declaring kind without a case. `validation/symplecticity_validation.jl`
  passed every case and the Hirata Lorentz quasi-symplectic check.
- **Backend consistency.** `validation/tracking_backend_consistency.jl` had
  been unrunnable at its two-turn default since 2026-08-14 (confirmed on a
  pristine worktree of `5dd9e22`: the accelerating cavity sat in the
  multi-turn line, and the single-pass refusal that landed the same day
  throws at the first `validate`). Repaired in this commit: the cavity tracks
  on its own one-turn line, the coverage tripwire counts both lines, the
  validation README says so. Default run, 10,000 particles, two turns:
  CPU/CPU `max_abs_error` 0.0 over 60,000 coordinates; CPU/GPU 1.68e-16
  (global relative 7.8e-15); cavity arm CPU/CPU 0.0, CPU/GPU 3.5e-18; aperture
  arms 0.0 with 40,350 of 60,000 slots killed identically on both backends.
  (Before the repair, at `OCTOPUS_CONTRACT_TURNS=1`: CPU/GPU 1.1e-16.)
- **Snapshot, metadata, structure.** `registry_snapshot_markdown()` equals the
  committed snapshot; `validate_element_metadata()` passed; the slice is
  `isbitstype` and not `<: AbstractTrackOp` (both now pinned in the new
  testset), and not exported (probed).
- **Bit-identity beyond the production branch.** The production line is
  Hirata drift, uncoupled moments, zero angle and curvature, so its digest
  proves nothing about the other branches of the same widened methods. A
  probe tracked a fixed 4,000-particle set two turns through both loop copies
  on this tree and on the pristine `5dd9e22` worktree: nine configurations —
  thin element with nonzero centre/angle/curvature, thin coupled
  (`XYCouplingSpec`) with the exact drift, sliced Hirata with angles and
  curvature, sliced chromatic, sliced exact (Gauss–Hermite nodes), sliced
  exact coupled, sliced 6x6 covariance with crab slope and x–y coupling
  (the `StrongTransverseMoments{T,true}` branch), and both unsafe drifts —
  gave identical fused and elementwise digests and identical luminosity on the
  two trees, to the bit. The probe is committed as
  `validation/strong_beam_kick_fingerprint.jl` (run it on two checkouts and
  diff); the digests on this tree, equal on the pristine one:

| configuration | fused digest | elementwise digest | `last_luminosity` |
|---|---|---|---|
| thin hirata angled (ThinStrongBeam) | `0x3c2539886fc466cc` | `0x3c2539886fc466cc` | 3.550937949750742e10 |
| thin coupled exact (ThinStrongBeam) | `0x468ae12e3031c761` | `0x468ae12e3031c761` | 3.5301099624536674e10 |
| gsb hirata angled (GaussianStrongBeam) | `0x4b7f7c4427139cef` | `0x4b7f7c4427139cef` | 4.661739812804119e7 |
| gsb chromatic (GaussianStrongBeam) | `0x207f794bee948635` | `0x207f794bee948635` | 4.766435681213563e7 |
| gsb exact (GaussianStrongBeam) | `0x07924aad54ff3430` | `0x07924aad54ff3430` | 3.4131431030006074 |
| gsb exact coupled (GaussianStrongBeam) | `0x916e923e7500920c` | `0x916e923e7500920c` | 2.531967788053795e6 |
| gsb 6x6 covariance hirata (GaussianStrongBeam) | `0xb0954daa5a1f7bb1` | `0xb0954daa5a1f7bb1` | 6.055149097243364e7 |
| gsb unsafe paraxial-frozen (GaussianStrongBeam) | `0xd1be3017925fab6d` | `0xd1be3017925fab6d` | 3.411384211292839e7 |
| gsb unsafe chromatic-frozen (GaussianStrongBeam) | `0x1e7f20e493485293` | `0x1e7f20e493485293` | 5.396975075875967e7 |

  (A tenth configuration, `hvoffset` passed as a plain tuple, threw the same
  `MethodError` on both trees; see the audit's out-of-scope note.)
- **Repo-wide grep.** `_slice_thin_strong_beam` is called at two sites in
  `src/` (`strong_beam.jl:485`, `strong_beam_track.jl:137`) plus the pin's
  direct call in `test/runtests.jl`; `_thin_strong_beam_track` at four
  (`:474`, `:491`; `strong_beam_track.jl:76`, `:146`); the four widened
  annotations are the only `::ThinStrongBeam` sites in the kick chain; the
  CUDA chain (`_cuda_thin_strong_beam_track`, `strong_beam_track.jl:426`) is
  untouched, and `git diff` shows no change under `src/track/`.
- **Test infrastructure row.** The diff adds testsets and touches no lane or
  gate machinery; the full gate printed no `LANE SKIP` line, as the full lane
  must.
- **The gate.** Full lane on the final tree, 2026-09-04 09:54–10:18 UTC,
  CUDA active (RTX 4500 Ada; 11,933 MiB of it held by an unrelated process):
  `julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'`,
  193 testsets, 36,643 of 36,643 pass, 0 fail, 0 error, no `LANE SKIP` line;
  `git status` byte-identical before and after the run. Pkg re-resolved the
  test environment at start (the tracked Manifest predates Project.toml;
  ticketed in `docs/todo.md`). An earlier full gate on the same code before
  the last prose edits (03:34–03:58 UTC) gave the same counts.

## Neighbour audit

The invariant: a fix's neighbours are where the next defect is. Sites
re-walked, and the property (no per-particle allocation, bit-identical
kicks) re-run on what the fix did not target.

- **Every `::ThinStrongBeam` annotation outside the kick chain** —
  `track_particle(::WeakStrongBeamBeamMap, ::ThinStrongBeam)` (`strong_beam.jl:472`),
  the thin callable (`:497`), the CPU `track!`/`_track_thin_strong_beam!`
  (`strong_beam_track.jl:1`, `:55`, `:59`), `_requires_cuda_elementwise`
  (`:165`), the CUDA workspace and `track!` methods (`:268`, `:328`, `:360`) —
  take the element, never a slice; correctly untouched.
- **Every positional `ThinStrongBeam(` constructor** — the spec constructor
  (`strong_beam.jl:227`), `GaussianStrongBeam`'s `thin` (`:404`),
  `_thin_with_distribution` (`:1308`), `Contracts.jl:1366`, `test/runtests.jl:811`,
  `:859`, `:996`, `validation/tracking_context_policy_consistency.jl:94` — build the base
  element (spec time, not per particle); untouched. `GaussianStrongBeam.thin`
  keeps its `ThinStrongBeam{M,T,P,D}` field type.
- **The sibling loop copy** (`_track_gaussian_strong_beam_with_luminosity`,
  `strong_beam_track.jl:130-150`) reaches the slice through the one shared
  constructor: measured 0 B single-particle and flat 30,416 B at n and 2n.
- **The bare thin element**, both paths: measured flat — fused 2,480 B,
  elementwise 30,576 B at n = 20,000 and 40,000 (growth 1.000), the probe's
  two lines verbatim: `THIN-ALLOC thin fused n=20000 2480 B, n=40000 2480 B,
  growth 1.0` and `THIN-ALLOC thin elementwise n=20000 30576 B, n=40000 30576
  B, growth 1.0`. It never had the site (no per-particle construction) and
  still does not.
- **Strong-strong kicks sharing `_cp_covariance_kick`** (`gaussian.jl:168`,
  `gaussian_pic.jl:837-839`) call it with moments directly, never through
  `_cp_kick(elem, …)`, so the widening cannot reach them; their allocation pin
  ("CPU strong-strong collide allocation does not scale with the pair count")
  runs in the gate.
- **CUDA.** No device-reachable method changed; the CUDA elementwise kernels
  and the CPU/GPU backend-consistency arms ran green above; the gate runs
  CUDA active.
- **Genericity.** `T<:Number` and the `P`, `D` parameters survive; the
  `@inferred` guard with `ExactHamiltonianDrift` (`test/runtests.jl` ~586)
  runs in the gate. Not pinned anywhere, before or after: a strong beam with
  a ForwardDiff `Dual` parameter type (the slice is isbits for any isbits
  `T`, reasoned, not measured).
- **Docs.** Live prose describing the pre-fix state: the benchmark header
  (updated beside its dated paragraph), the todo row, the README index; the
  Phase 0 record is frozen and corrected here. No other live document
  described the 1.282 GiB/turn as the current state (the README's Phase 0
  index blurb describes that frozen record).
- **Observed, out of scope, not fixed:** `GaussianStrongBeamSpec(hvoffset=(a, b))`
  with a plain tuple raises a `MethodError` from `get(::Tuple, ::Symbol, ::Symbol)`
  rather than an `ArgumentError`, identically on both trees.
