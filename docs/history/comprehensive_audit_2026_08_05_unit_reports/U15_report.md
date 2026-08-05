# U15 Audit Report — Beam representation, counter RNG, special functions, constants

Commit audited: 83e1d38 (post-7a8e9ca). Read line-by-line, every line:

- src/beam/Beam.jl — lines 1–729 (all)
- src/math/counter_rng.jl — lines 1–336 (all)
- src/math/SpecialMath.jl — lines 1–161 (all)
- src/constants/Constants.jl — lines 1–32 (all)
- Supporting reads: validation/counter_rng_validation.jl (1–118, all), test/runtests.jl RNG
  sections, src/track/strong_beam_track.jl:390–410, src/contracts/Contracts.jl constant/rng_id
  call sites, src/elements/{radiation.jl,rf_cavity.jl,crab_cavity.jl} constant call sites,
  src/tasks/BPMObserver.jl:117,162–163.

Probes (all in /tmp/claude-320114/-cfs-ad-dxu-Library-Julia-Octopus/94771dda-fd24-4438-922e-a4bd8afa2361/scratchpad/U15/):
philox_kat.jl, key_collision.jl, rng_stats.jl, validation_discrimination.jl,
beam_sampling.jl, beam_stats_ref.jl, mean_abs_check.jl, faddeeva_acc.jl,
constants_check.jl, method_fallback.jl. All run `julia --startup-file=no --project=. <script>`
from repo root; each < 60 s of compute after package precompilation.

---

## Leads

### U15-1 — validation/counter_rng_validation.jl:86-92 (and test/runtests.jl:135-144) — the determinism foundation has no known-answer anchor; the validation gate passes a Philox with the key schedule removed — MEDIUM
Invariant: "the validation script actually discriminates — a broken mixing round should fail it."
Probe `validation_discrimination.jl` rebuilds the script's exact pass gate and feeds it
weakened generators (N = 1e6, same seed/turn/rng_id as the script's defaults):

| variant | mean | var | corr_pair | corr_neighbor | gate |
|---|---|---|---|---|---|
| 10 rounds + Weyl bump (real) | 5.15e-4 | 0.9983 | -1.28e-3 | 2.38e-4 | PASSES |
| 10 rounds, NO key bump (broken) | 8.66e-4 | 1.003 | -5.62e-4 | 4.15e-4 | **PASSES** |
| 2 rounds + bump | -1.15 | 5.66e-7 | -0.967 | 1.0 | fails |
| 1 round + bump | -0.332 | 2.8e-32 | NaN | 1.0 | fails |

Removing the Weyl key bump (the per-round constants that make Philox Philox) sails through
every statistical check. Neither the validation script nor test/runtests.jl (which only checks
reproducibility, component separation, finiteness at lines 135-144) contains a single
known-answer vector, so any silent change to the mixing — constants, round order, bump — would
pass the whole suite while changing every "reproducible" stochastic result in the codebase.
Important context: probe `philox_kat.jl` shows the CURRENT implementation matches all three
official Random123 `philox4x32 10` kat_vectors bit-exactly (zeros, all-ff — expected 4th word
6d5451fd confirmed against the DEShawResearch/random123 repository — and the pi-digits vector),
and the public `counter_philox4x32` wiring reproduces the raw core. So this is a
missing-guardrail lead, not a wrong-output lead: three @test lines with those vectors would
close it.
Repro: U15/validation_discrimination.jl, U15/philox_kat.jl.

### U15-2 — src/math/counter_rng.jl:154-156 (also 192-195) — XOR key construction admits closed-form full-stream collisions — LOW/MEDIUM
Invariant: "two different (seed, rng_id, ..., component) tuples must never map to one
counter/key" (docstring line 142-143: "`rng_id` separates independent stochastic elements or
streams"). The Philox key is `SM(seed) ⊻ SM(rng_id+G) ⊻ SM(component+D)` with
`SM(x)=mix64(x+G)`, `G=0x9e3779b97f4a7c15`, `D=0xbf58476d1ce4e5b9`. XOR is symmetric, so
role-swaps with offset adjustment preserve the key exactly, and since (turn, particle) form the
counter unchanged, the ENTIRE streams coincide, not just one draw. Probe `key_collision.jl`:

- Collision A: `(seed=s, rng_id=r)` vs `(seed=r+G, rng_id=s-G)` — 16/16 tuples identical
  across turn ∈ {0,1,2^31,2^40}, particle ∈ {1,2,999983,2^33}
  (concrete: seed=20260805,rng_id=7 ≡ seed=11400714819323198492,rng_id=7046029254406613936).
- Collision B (same seed): `(rng_id=r, comp=c)` vs `(rng_id=c+D-G, comp=r+G-D)` — 6/6 identical.
- Collision C: `splitmix_uint64` has the same XOR structure over all four fields;
  turn↔particle swap `(turn=9,particle=123456)` ≡ `(turn=17769181034985322518,
  particle=677563038724352563)` confirmed.

Severity tempered by reachability: auto-assigned rng_ids are sequential small integers and the
colliding partners are ~1e19, so accidental collision is essentially impossible — UNLESS a user
derives 64-bit ids by hashing (nothing forbids it; rng_id is any Integer). A doc caveat or a
non-XOR combiner (e.g. sequential splitmix chaining as the key) would eliminate the structure.
Edge behavior also probed: negative turn/component throw InexactError (fail-loud, undocumented);
component=0 in `octopus_normal` throws via internal component -1; huge turn (typemax(Int64))
works and separates from turn=0.
Repro: U15/key_collision.jl.

### U15-3 — src/beam/Beam.jl:62-93 vs 116-126 — cutoff semantics differ per sampling path: clip vs resample — MEDIUM (at small cutoff), negligible at production cutoff=5
Invariant: one `Beam(...; cutoff=c)` call should draw from one distribution family regardless
of which RNG path serves it. Three paths exist:
- default counter path `_alloc_counter_randn` (line 123): **clamps** to ±c;
- explicit-rng GPU path `_alloc_randn(CUDABackend,...)` (line 73): **clamps** (comment admits it);
- explicit-rng CPU path `_alloc_randn(CPUThreadsBackend,...)` (lines 84-89): **resamples**.

Probe `beam_sampling.jl` at cutoff=3, N=1e6:
- counter path: 2705 samples EXACTLY at |x|=3 (theory 2·P(|N|>3)·N = 2700); var=0.99483,
  kurtosis=2.9192;
- resample path: 0 atoms; var=0.97413, kurtosis=2.8283 (exact truncated-normal: var 0.97334,
  kurtosis 2.8290 — the probe's printed "2.7013" label is a wrong constant in the probe text,
  the measured numbers are authoritative).

`_standardize!` then forces mean 0/var 1 on every path, so second moments (and all
Twiss-normalized covariances) agree; but 4th moments and tails differ between paths, and the
clip atoms land at c/σ_clip = 3.0078σ after standardization — i.e. slightly OUTSIDE the
requested cutoff. At the production cutoff=5 (Contracts.jl:996 ff.) the atom mass is 5.7e-7 so
the practical impact is nil; the inconsistency bites anyone comparing CPU-rng vs GPU-rng vs
counter runs at small cutoff, or computing beam kurtosis. Also: `cutoff` is not mentioned
anywhere in the `Beam` docstring (lines 408-435), so neither semantics is documented.
Repro: U15/beam_sampling.jl.

### U15-4 — src/math/counter_rng.jl:80-82 — unknown method code silently falls back to Philox — LOW
`octopus_uint64` returns the Philox value for any unrecognized `method_code` (`else` branch),
while `rng_method_symbol` throws ArgumentError for the same code. Probe `method_fallback.jl`:
`octopus_uint64(1, UInt8(99), 2, 3, 4, 5)` == `counter_uint64(1,2,3,4,5)` (true), and
`rng_method_symbol(0x63)` throws. A corrupted method code in a TrackingContext would produce
plausible numbers instead of an error. Deliberate for GPU-branchless code, perhaps, but it is a
check that never fires. Repro: U15/method_fallback.jl.

### U15-5 — src/math/counter_rng.jl:47-50 — next_rng_id! is a non-atomic global Ref — LOW (static)
`_GLOBAL_RNG_ID_COUNTER[] += 1` is not atomic; two threads constructing Beams (or radiation
elements, BPMObservers — all draw from this one counter: Beam.jl:158, radiation.jl:34,
BPMObserver.jl:117) can receive the same stream id, which by design means bitwise-identical
noise streams. Same for `set_global_rng!` racing readers. Construction is serial today; no
probe (timing-dependent race), flagged from the code.

### U15-6 — src/beam/Beam.jl:705 — write_beam_coordinates(path, ...) appends by default, undocumented — LOW
The path method defaults `append=true`; the docstring (689-694) documents neither the kwarg nor
the default. Two calls to the same path yield a 2-record file, and
`read_beam_coordinates(path)` (default `record=0`) then returns the FIRST (stale) record — a
write-then-read round trip silently reads old data. Doc drift + surprising default; consistent
with the append-across-restarts design of recent commits, but the contract is invisible.

### U15-7 — src/beam/Beam.jl:437,442 vs src/math/counter_rng.jl:126-131 — Beam accepts RT<:Real but sampling requires T<:AbstractFloat — INFO
`Beam(N, backend, FloatT::Type{RT}) where RT<:Real` promises any Real, but
`octopus_normal(..., ::Type{T}) where T<:AbstractFloat` (and `randn(rng, T)`) reject
non-AbstractFloat Reals, so randomized construction with e.g. ForwardDiff.Dual MethodErrors.
No test constructs a Dual beam; either tighten the signature to AbstractFloat or accept
statically. (This layer otherwise feeds Duals correctly: SpecialMath is fully generic in
T<:Real; counter RNG is integer-in/float-out.)

Minor observation (no number needed): Beam.jl:151/`_standardize!` — an N=1 beam collapses to
exactly (0,0,0,0,0,0) via the σ==0 branch (probe beam_sampling.jl last line); defensible, but a
"1-particle Gaussian beam" silently becomes an on-axis particle regardless of sigma.

---

## Sound (invariant verified, and how)

1. **Philox4x32-10 core is bit-exact against the published Random123 stream**: all three
   official kat_vectors reproduced (zeros → 6627e8d5 e169c58d bc57ac4c 9b00dbd8; all-ff →
   408f276d 41c83b0e a20bc7c6 6d5451fd, confirmed against the upstream kat_vectors file;
   pi-digits → d16cfe09 94fdcceb 5001e420 24126ea1). Round function, M0/M1/W0/W1 constants,
   counter packing (particle→c0,c1; turn→c2,c3) and key packing verified against spec; the
   extra key bump after round 10 is dead but harmless. [philox_kat.jl]
2. **Constants all correctly rounded**: CLIGHT exact; RE, EMASS_EV, PMASS_EV, ME0 within 0.47
   ulp of CODATA-2022; TWOPI/SQRT2PI/SQRTPI/SQRT2 within 0.44 ulp of exact. Downstream units
   spot-checked: γ = E/EMASS_EV (eV/eV), r0 = RE·ME0/PMASS_EV (m·eV/eV), k = 2πf/CLIGHT (1/m)
   — all consistent. Literal digit tails beyond Float64 precision are cosmetically off in two
   docstrings' 40th+ digits, irrelevant after parsing. [constants_check.jl]
3. **_uniform_open01 is exactly open**: outputs span [2^-53, 1-2^-53] (F64) and
   [2^-24, 1-2^-24] (F32) inclusive, strictly inside (0,1) for the extreme UInt64 inputs and
   over 1e6 draws in both precisions; the "one fewer source bit" comment is mathematically
   right (adding 0.5 is exact, upper endpoint cannot round to 1). [rng_stats.jl]
4. **octopus_normal statistics healthy at 1e6 draws**: mean=1.28e-4 (SE 1.0e-3), var=0.99778
   (SE 1.4e-3, -1.6σ), skew=6.3e-4, kurtosis=2.9949; uniforms mean 0.499828, var 0.083285
   (1/12=0.083333). Pair/component sharing (components 1,2 = one Box-Muller pair) confirmed
   bitwise. [rng_stats.jl]
5. **alpha≠0 Twiss covariance is correct**: for beta=(2,3,4), alpha=(1.5,-0.8,0.3),
   sigma=(1e-3,2e-3,5e-3) at N=1e6, sampled var(q)=σ² to 1e-14 (exact by standardization),
   var(p)→(σ/β)²(1+α²) and cov(q,p)→-ασ²/β within O(1/√N) (≤6.3e-4 rel), emittance = σ²/β to
   2e-7 (error is second-order in the residual cross-correlation, as algebra predicts). The
   longitudinal plane follows the documented cov(z,pz) = -αz·σz²/βz convention. [beam_sampling.jl]
6. **beam_statistics is numerically true**: vs BigFloat naive reference at N=1e6 with offsets,
   covariance max rel err 4.8e-14, emittance 5.9e-14, fourth central 1.3e-16, means abs err
   ≤ 1e-20 (the 0.31 "relative" figure in beam_stats_ref output is a 0/0 artifact on
   standardized means that are truly ~1e-22 — mean_abs_check.jl resolves it). Sequential
   summation in `_covariance` (vs pairwise in `_mean`) costs nothing detectable at 1e6.
   [beam_stats_ref.jl, mean_abs_check.jl]
7. **The 39.8% covariance-mirror claim reproduces**: cov 21-pass 13.48 ms vs 36-pass 23.38 ms
   at N=1e6; saving 9.90 ms = 39.9% of the reconstructed un-mirrored total (24.83 ms), matching
   the in-code "24.97→15.02 ms, 39.8%". Mirror exactness claim verified: cov21 == cov36
   bitwise, and `_covariance(a,μa,b,μb) === _covariance(b,μb,a,μa)` for all 36 pairs. Current
   beam_statistics = 14.93 ms; the remaining 21 O(N) passes (~90% of runtime) are the next
   perf frontier — measured, not fixed. [beam_stats_ref.jl]
8. **Faddeeva approximation is accurate everywhere probed**: worst |w(z)| relative error
   3.09e-13 over a ~2000-point grid spanning every branch boundary (y=7; x=6,8,28; x+y=4000,
   1e7) plus the near-real-axis band (y down to 1e-12) and all four sign quadrants, vs
   SpecialFunctions.erfcx(-im z); lower-half-plane reflection identity to 3.3e-14; w(0)=1,
   w(i)=erfcx(1) reproduced. Caveat (not a lead): the exponentially small real part at large x
   near the axis carries only ~1e-4 componentwise relative accuracy (2.3585e-10 vs 2.3588e-10
   at z=5.1+1e-8i) — absolute error ~3e-15, harmless for Bassetti-Erskine where Im dominates.
   The upper-half-plane precondition claimed in the docstring is honored at the only call site
   (strong_beam_track.jl:391-400 takes abs(x),abs(y) first). `faddeeva_w = erfcx(-im z)`
   identity exact. [faddeeva_acc.jl]
9. **is_live / LiveMask / allow_lost_particles machinery is coherent**: six-coordinate isfinite
   test as documented; LiveMask{false} default routes to the unmasked reductions
   (`flags === nothing` short-circuit at Beam.jl:590,599,608); beam_statistics divides every
   moment by `n = nlive` and returns that n, as its comment promises.
10. **rng_id stream separation behaves as documented**: same explicit rng_id → bitwise
    identical beams (documented convenience/hazard), auto-assigned ids → distinct beams;
    Contracts.jl passes distinct rng_id=1/2 (and 11/12) per beam, so the shipped setups cannot
    collide. Beam init draws at turn=0 while turn-loop consumers draw at ctx.turn with their
    own globally-unique ids, so no cross-consumer overlap. [beam_sampling.jl + call-site reads]
11. Phase6DRep invariants (equal-length check at construction, getindex/setindex round trip,
    backend homogeneity checks in _infer_backend/_cuda_storage_device with specific errors) and
    the compact I/O record format (UInt32 count + 6×Float64 blocks; read skips records by
    seeking) read correct; error paths (negative N, unknown Beam kwargs listed in the message,
    policy/storage mismatch) all raise specific ArgumentErrors.
