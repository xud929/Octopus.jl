# Production Solver Matrix — 2026-08-08

Every implemented strong-strong Poisson solver at the production point, both
backends, both precisions, one protocol. Owner-requested; run from a git
worktree pinned at `416cff0` so no in-flight edit could leak between arms.

## Protocol

- Case: the crab-crossing EIC electron–proton production point of
  `test/examples/strong_strong_tracking.jl` — 2,560,000 e⁻ / 1,024,000 p
  macroparticles, 15 z-slices (centroid centers), 200 turns, moment and
  luminosity output enabled.
- Metric: mean wall-time/turn over turns 100–200
  (`OCTOPUS_RECORD_TURN_TIMES=1`).
- Precision switch: a scratchpad copy of the harness with
  `OCTOPUS_SCALAR=float32|float64` selecting the beam element type (the
  committed harness stays Float64 by design).
- Solver model parameters where they must differ: PIC and GaussianPIC on
  grid (128, 128) with `:CIC` and the `:slice_pair` Green cache (harness
  defaults; note gpic's own docs recommend `:TSC` for accuracy — CIC was
  kept for cross-solver uniformity); Spectral on grid (127, 383) with
  `domain_factor = 8` (the documented production recommendation); the
  soft-Gaussian needs no grid. All other physics identical.
- Hardware: RTX 4500 Ada (GPU arms, `--threads=4` host); 16 CPU threads
  (CPU arms) on the 128-thread/64-core box — see "known limitation" below.
- Arms ran sequentially, GPU phase first. One overlap: a ~3-minute GPU
  side-run (arm 17) coincided with `pic_cpu_float32`'s FIRST turns; its
  measurement window (turns 100–200, starting ~1.7 h in) was not touched.

## Timing (mean s/turn, turns 100–200)

| solver | GPU f64 | GPU f32 | f32 gain | CPU f64 (16 thr) | CPU f32 (16 thr) |
|---|---|---|---|---|---|
| PIC (128², CIC)         | 0.331 | 0.224 | 1.48× | 40.8 | 61.0 (**0.67×**) |
| GaussianPIC (128², CIC) | 0.709 | 0.309 | 2.30× | 65.0 | 92.6 (**0.70×**) |
| Spectral (127×383, d=8) | 0.617 | 0.474 | 1.30× | 6.65 | 5.48 (1.21×) |
| soft-Gaussian (15 sl.)  | 0.250 | 0.244 | 1.03× | 2.95 | 2.62 (1.13×) |
| soft-Gaussian, `{Float32}` solver (arm 17) | — | 0.239 | — | — | — |

## Physics (electron beam; luminosity level over turns 100–200, beam-size
window means over 150–200, growth factors turn 0→199; reference =
PIC-GPU-f64)

- **Cross-backend, same solver and precision: bit-level.** PIC CPU-f64 vs
  GPU-f64 agree to 2.6e-16 in luminosity and ~1e-15 in beam sizes over 200
  turns — the 2026-08-07 parity campaign (U3-4/U6-7 and kin) visible at
  production scale. Every solver/precision pair shows the same character.
- **Cross-solver model spread**: vs PIC — GaussianPIC −0.27% luminosity,
  Spectral −0.03%, soft-Gaussian +1.2%. Emittance growth factors agree
  across all four models to ~0.5% (x: 1.215–1.221; y: 1.196–1.202). The
  soft-Gaussian's offsets are its moment-Gaussian field model, not error.
- **Float32 physics cost is negligible at this horizon**: within each
  solver, f32 sits within ~1.6e-5 of f64 beam sizes and ~1e-6 in
  luminosity, growth factors identical to 4 digits. (200 turns bounds
  noise-heating only at the ~1e-5/turn level; long-horizon behaviour is
  unmeasured.)

## Findings

1. **CPU grid solvers were 1.4–1.5× SLOWER at Float32 than Float64**
   (pic 40.8 → 61.0; gpic 65.0 → 92.6) while spectral/gaussian got modestly
   faster. Probe-confirmed mechanism: for Float32 beams the workspace and
   charge grids follow the beam (`kbb` comes from the beam's params) but
   `_pic_interaction_grids` / `_pic_resolve_transverse_extent` promoted
   their working type through the solver's Float64 `min_transverse_extent`,
   so grid origins/spacings were Float64 and every per-particle deposit and
   interpolation paid mixed-precision promotion in the hottest loops. The
   CUDA path never had this — its launch wrappers convert grid scalars to
   the working type at the kernel boundary. **Fixed in the commit carrying
   this report**: grid geometry now takes the bounds' type; measured at a
   400k probe point, CPU PIC f32 went 19.0 s → 11.9 s per collide — parity
   with f64 (11.97 s). Float64 runs bit-unchanged; suite pins the grid
   metadata types.
2. **Arm 17 (soft-Gaussian `{Float32}` solver, the genuinely-Float32
   Bassetti–Erskine path)**: 0.239 vs 0.250 s/turn — ~4% total. The GPU
   soft-Gaussian route is orchestration/sync-bound, not FLOP-bound, so
   there is no performance case for the `{Float32}` solver; the Float32
   near-round BE calibration itself is sound (luminosity agrees with the
   f64-solver arm on identical beams to 5.4e-7).
3. **Known limitation, feeding the CPU-threading campaign** (todo row
   "CPU thread optimization for all solvers"): CPU arms used 16 of 128
   hardware threads, and no CPU FFT is threaded
   (`FFTW.set_num_threads` appears nowhere) — PIC's ~450 serial per-pair
   solves per turn are the visible Amdahl ceiling. The CPU columns above
   are baselines for that campaign, not the machine's ceiling.

Raw artifacts (per-arm turn-time TSVs, run logs, `.lum`/`.h5` outputs)
lived in the session scratchpad and are reproducible from the protocol
above; the numbers in this report are the durable record.
