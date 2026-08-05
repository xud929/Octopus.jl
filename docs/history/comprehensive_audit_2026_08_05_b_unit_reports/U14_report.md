# U14 Audit Report — counter RNG, special functions, beam representation, tracking core

**Commit audited:** `7de4d81` (63 commits past the `6a3f39ab` the previous full audit
declared). **Unit:** U14, one reading unit of the comprehensive audit protocol.
**Date:** 2026-08-05. **Machine:** Julia 1.12.4, NVIDIA RTX 4500 Ada, 4 threads available.

---

## 1. Region and coverage

Read **line by line, every line**:

| file | lines | depth |
|---|---|---|
| `src/beam/Beam.jl` | 1–750 (all) | full |
| `src/math/counter_rng.jl` | 1–359 (all) | full |
| `src/math/SpecialMath.jl` | 1–168 (all) | full |
| `src/track/phase6d_track.jl` | 1–359 (all) | full |
| `src/track/longitudinal.jl` | 1–239 (all) | full |
| `src/track/fused_track.jl` | 1–77 (all) | full |
| `src/track/radiation_track.jl` | 1–67 (all) | full |
| `src/track/Track.jl` | 1–64 (all) | full |

Supporting reads (targeted, to resolve seams — **not** claimed as audited):
`git diff 6a3f39ab..HEAD -- src/beam src/math src/track` in full; `AGENTS.md`
"Hard-Won Rules"; `docs/comprehensive_audit.md` "Measured Lessons";
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U15_report.md`;
`docs/theory/rf_cavity_and_reference_energy.md` §5–§9; `docs/todo.md` F16 row;
`src/elements/radiation.jl` (construction + the two context tracking paths + the
non-context `track_particle` methods); `src/tasks/Tasks.jl`
`_warn_duplicate_radiation_streams`; `src/tasks/BPMObserver.jl` rng_id sites;
`src/elements/rf_cavity.jl:70–120`; `src/track/strong_beam_track.jl:380–415`;
`src/contracts/Contracts.jl` rng_id sites; `test/runtests.jl` rng_id and CUDA-gate
sites; `validation/` and `examples/` rng_id sites.

**Provenance.** Everything below labelled *measured* was executed in this session.
Probe scripts live in
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`
(session scratch, never the repository) and all run as
`julia --startup-file=no --project=/cfs/ad/dxu/Library/Julia/Octopus <script>`:

| script | what it measures |
|---|---|
| `philox_kat_independent.jl` | official Random123 KAT vectors; Octopus vs a KAT-anchored independent Philox |
| `stream_structure.jl` | counter/key injectivity, stream independence, consumer lattice, threaded `next_rng_id!` |
| `stream_namespace.jl` | the explicit-vs-auto `rng_id` collision |
| `faddeeva_bigfloat.jl` | Faddeeva accuracy vs `Complex{BigFloat}` across every branch region |
| `weideman_coeffs.jl` | regeneration of the 32 Weideman coefficients; the Bassetti-Erskine `Re(w)` seam |
| `beam_stats.jl` | moments vs BigFloat, covariance convention, n=0/1/identical edges |
| `longitudinal.jl`, `longitudinal2.jl` | conversions vs BigFloat, conditioning, round trips, sqrt domain |
| `device_ir.jl` | fused CUDA compile of every stochastic path; CPU/GPU sqrt-domain divergence |
| `contextless_turns.jl` | the contextless-CUDA turn repetition |
| `contextless_guard.jl` | the contextless refusal asymmetry |
| `misc_checks.jl`, `drift.jl` | guard coverage, static throw, splitmix, uniform bounds, I/O, cavity bias |

---

## 2. Hypothesis (a) — Philox / counter-based RNG

### 2.1 KAT verification, bit for bit

The three official `philox4x32 10` vectors were **fetched from the upstream file**
`https://raw.githubusercontent.com/DEShawResearch/random123/main/tests/kat_vectors`
in this session (not recalled, not taken from the prior report):

```
philox4x32 10 00000000 00000000 00000000 00000000 00000000 00000000   6627e8d5 e169c58d bc57ac4c 9b00dbd8
philox4x32 10 ffffffff ffffffff ffffffff ffffffff ffffffff ffffffff   408f276d 41c83b0e a20bc7c6 6d5451fd
philox4x32 10 243f6a88 85a308d3 13198a2e 03707344 a4093822 299f31d0   d16cfe09 94fdcceb 5001e420 24126ea1
```

An **independent** Philox4x32-10 was written from the published algorithm, with the key
schedule in the *upstream* order (bump **before** rounds 2..R) — textually different from
Octopus's (round, then bump) — so agreement tests the round count and schedule rather than
copying them. Result:

| counter | key | expected | independent impl |
|---|---|---|---|
| `00000000 00000000 00000000 00000000` | `00000000 00000000` | `6627e8d5 e169c58d bc57ac4c 9b00dbd8` | **identical** |
| `ffffffff ffffffff ffffffff ffffffff` | `ffffffff ffffffff` | `408f276d 41c83b0e a20bc7c6 6d5451fd` | **identical** |
| `243f6a88 85a308d3 13198a2e 03707344` | `a4093822 299f31d0` | `d16cfe09 94fdcceb 5001e420 24126ea1` | **identical** |

Round-count sensitivity (proves 10 means 10): R=8 → `618f177a 9920c1d7 1ec12dc0 c43b6eeb`;
R=9 → `7028b1c8 d6594c40 4f2051bb 76d6628e`; **R=10 → the KAT value**;
R=11 → `5805dfa6 7e9969d4 9ae116f5 5987480f`; R=12 → `ce9d78f7 f859be43 1ca381af 2f829cd2`.

The KAT-anchored implementation was then run against Octopus's **public**
`counter_philox4x32` end to end (documented wiring: counter =
`(lo32(particle), hi32(particle), lo32(turn), hi32(turn))`; key =
`SM(seed) ⊻ SM(rng_id+G) ⊻ SM(component+D)`, with SplitMix64 also written independently):

* **20 004 tuples compared, 0 mismatches** — 4 hand-picked corners
  (`(0,0,0,0,0)`, `(1,0,1,1,1)`, `(20260805,7,3,999983,6)`,
  `(typemax(UInt64), typemax(Int64), 2^40, 2^33, 12)`) plus 20 000 random tuples.
* `counter_uint64` packing `(w0<<32)|w1`: **0 mismatches over 2 000 tuples**.

**Verdict: Philox4x32-10 is bit-exact against the official Random123 stream at HEAD,
verified independently.** (Note the sample value at the all-zero *argument* tuple is
`9c4c4685 59e29484 2657ed38 096df4e1`, not the KAT zero vector, because the derived key
`SM(0) ⊻ SM(G) ⊻ SM(D)` is not zero — a check that could be mistaken for a failure.)

### 2.2 Stream structure — measured, not assumed

**Injectivity.** Keys over `rng_id ∈ 0:4000 × component ∈ 1:8`: **32 008 distinct of
32 008, 0 duplicates**. Full 64-bit outputs over 20 turns × 10 ids × 40 particles ×
6 components: **48 000 distinct of 48 000**. So two particles, two turns, two components
and two elements never share a counter over the whole reachable lattice.

**Independence,** Pearson *r* over N = 10⁶ draws (SE = 1.0e-3):

| axis (stream A vs stream B) | corr | corr of squares |
|---|---|---|
| adjacent particles, `p=i` vs `p=i+1` | 7.27e-04 | 1.45e-03 |
| adjacent turns, `t=0` vs `t=1` | 5.00e-04 | 1.35e-04 |
| far turns, `t=0` vs `t=10⁹` | 6.38e-04 | 3.37e-04 |
| adjacent elements/ids, `r=1` vs `r=2` | 5.17e-06 | 5.27e-05 |
| **radiation stream vs BPM stream**, `r=7` vs `r=8` at `t=3` | 2.05e-04 | 7.09e-04 |
| different components, different Box-Muller pair, `c=1` vs `c=3` | −5.22e-04 | −2.73e-04 |
| same Box-Muller pair, `c=1` vs `c=2` | 6.01e-04 | — |

All within 1σ of zero. Marginals healthy: mean −2.96e-04, var 1.000300 at N = 10⁶.
**A radiation stream and a stochastic-kick stream with distinct ids are independent —
measured.**

`next_rng_id!` under threads (the U15-5 atomic fix): 20 000 concurrent calls on 4 threads
→ **20 000 distinct ids, min 1, max 20 000, no duplicates**. The fix holds.

### 2.3 What is *not* protected — the shared id namespace (LEAD U14-2)

The three consumer classes draw from **one** `(seed, turn, rng_id, particle, component)`
lattice:

```
Beam init            (seed, turn=0,       rng_id_beam, particle=i,  component=1..6)   Beam.jl:130
LumpedRad excitation (ctx.seed, ctx.turn, elem.rng_id, particle_id, component=1..6)   radiation.jl:248-253, 270-275
BPMObserver noise    (ctx.seed, ctx.turn, bpm.rng_id,  occurrence,  component=1,2)    BPMObserver.jl:162-163
```

The first tracked turn is `ctx.turn = 0` (`track!` uses `ctx.turn + (turn-1)`), the same
turn beam initialisation draws at. Auto-assigned ids come from the single atomic
`next_rng_id!`, so an all-auto session is disjoint (measured: beam 1, rad 2, bpm 3).
**Explicit ids never advance that counter**, and there is no cross-class check —
`Tasks._warn_duplicate_radiation_streams` (the F14 remedy) covers radiation-vs-radiation
placements inside one line only. See LEAD U14-2 for the measured collision.

Shipped configurations were checked and are disjoint **by hand**, not by construction:
`examples/weak_strong_tracking.jl` (beam 1, rad 2), `examples/strong_strong_tracking.jl`
(beams 1,2, rad 3), `validation/pic_option_consistency.jl` (beams 1,2, rad 3),
`validation/tracking_backend_consistency.jl` (rad 101),
`validation/tracking_context_policy_consistency.jl` (rad 901),
`Contracts.jl` (beams 1,2,11,12,101–104; the `:lumped_radiation` option row uses
`rng_id=1` but that contract probes a deterministic map only).

---

## 3. Hypothesis (b) — SpecialMath Faddeeva

### 3.1 Accuracy table vs `Complex{BigFloat}`

Reference: `w(z) = exp(-z²)(1 - erf(-iz))` by Maclaurin series at **4096-bit** precision
(so the ~`exp(|z|²)` cancellation still leaves >500 digits) for |z| ≤ 35, and the
truncate-at-smallest-term asymptotic 1/z series beyond. The two references were
cross-validated on 20 ≤ |z| ≤ 35: **worst relative disagreement 1.09e-96**. No use was
made of `SpecialFunctions.erfcx` (the prior pass's reference).

| region (branch of `faddeeva_w_upper_reim`) | n | worst rel err on \|w\| | at z | worst rel Re | worst rel Im |
|---|---|---|---|---|---|
| Weideman interior 0≤x≤6, 0≤y≤7 | 625 | **3.092e-13** | (5, 0) | 1.08e+02 | 2.99e-13 |
| near-real-axis band, x≤6, y ∈ {0,1e-14,…,1e-3} | 186 | 3.092e-13 | (5, 1e-14) | 1.08e+02 | 3.06e-13 |
| boundary y = 7 | 30 | 4.522e-16 | (0.5, 6.99) | 5.24e-16 | 8.51e-16 |
| boundary x = 6, y = 0.1 | 25 | 1.840e-13 | (6.01, 0.09) | 1.06e-11 | 1.01e-13 |
| boundary x = 8, y = 1e-10 | 30 | 2.760e-13 | (7.99, 0) | 1.78e+21 | 2.31e-13 |
| boundary x = 28 (y < 1e-10) | 25 | 9.385e-14 | (27.9, 1e-14) | 3.84e+287 | 9.29e-14 |
| boundary x + y = 4000 (mid-field asymptote) | 18 | 2.143e-15 | (4000, 0.5) | 1.00e-14 | 2.11e-15 |
| boundary x + y = 1e7 (two far-field forms) | 9 | 5.047e-15 | (1e7, 1) | 1.51e-14 | 1.48e-14 |
| gap x ∈ (6,8], y ≤ 0.1 (Weideman branch) | 24 | 2.994e-13 | (6.5, 1e-9) | 2.01e-03 | 2.79e-13 |
| x ∈ (8,28), tiny y (CF branch) | 20 | 2.499e-16 | (10, 0.001) | 2.96e-16 | 2.45e-16 |
| all four quadrants through `faddeeva_w_approx_reim` | 48 | 9.064e-14 | (5.5, −0.2) | 2.31e-12 | 2.58e-14 |

Exact anchors: `w(0)` → `(1.0000000000000275, 0)`, rel 2.75e-14; `w(i)` → `0.42758357615580694`,
rel 1.42e-16; `w(5i)` rel 1.66e-17; `w(1)` rel 4.59e-14.

**Global worst on |w|: 3.09e-13**, everywhere, including every branch boundary and the
lower half plane via the reflection `w(z) = 2e^{-z²} − w(−z)` (which I re-derived from the
code: `_cexp_reim(-zr²+zi², -2 zr zi)` is exactly `exp(-z²)` — correct).

The blown-up `Re` columns are the **exponentially small real part near the real axis**
(`Re w(x+i0) = e^{-x²}`), which carries only the *absolute* error of the |w| computation.
See §3.3 — this was measured at its consumer and is harmless.

Every algebraic form in `_faddeeva_w_cf_reim` was independently re-derived and matches:
the two far-field forms (x>y and x≤y) both reduce to `Re w = y/(√π|z|²)`,
`Im w = x_s/(√π|z|²)` with the correct sign for negative `x_s`; the mid-field form is
`w = i z/(√π(z²−½))` term for term; the Laplace continued fraction
`W ← z − ν/W`, `w = i/(√π W)` matches line for line.

### 3.2 The coefficient table is derived, not drifted

"Do not hand-copy knowledge" — so the 32 coefficients were **regenerated** from Weideman's
own construction (SIAM J. Numer. Anal. 31 (1994) 1497: `t = L tan(θ/2)`,
`f = e^{-t²}(L²+t²)`, `a = Re fft(fftshift([0;f]))/2M`, `flipud(a(2:N+1))`) with a naive
128-point DFT in `BigFloat`:

* `L`: derived `4.7568284600108841` — **bit-identical** to the table, and equal to
  Weideman's `2^(-1/4)√N` for N=32.
* `FADDEEVA_WEIDEMAN_INVSQRTPI`: **0.00 ulp** from `1/√π`.
* Coefficients: largest absolute difference **7.79e-15** (index 10); sum of absolute
  differences **5.29e-14** (this bounds `|δp(Z)|` since `|Z| ≤ 1` on the mapped domain).
  The largest *relative* difference is 6.11e-04 at index 1 — that coefficient is itself
  −1.30e-12, i.e. the table is a **double-precision** generation of the same construction.
* Effect of substituting the exact coefficients: **worst relative change in w = 1.05e-14**,
  a factor 30 below the method's own 3.09e-13 approximation error.

**Verdict: the table is Weideman's, correct, and its double-precision provenance is
immaterial.**

### 3.3 The `Re(w)` noise floor at its consumer (seam, priced)

`_cuda_elliptic_gaussian_kick_principal` (strong_beam_track.jl, **outside U14's region**)
forms `Ky = A(w1r − B·w2r)` from exactly those exponentially small real parts, and `Ky`
must be **0** by symmetry at `y = 0`. Measured at σ₁ = 106 µm, σ₂ = 9.5 µm, x = 3e-4 m:

| y [m] | Kx | Ky |
|---|---|---|
| 0 | 7.936101251623e+03 | **6.411e-10** (exact answer 0) |
| 1e-18 | 7.936101251623e+03 | 7.121e-10 |
| 1e-15 | 7.936101251623e+03 | 7.130e-08 |
| 1e-12 | 7.936101251623e+03 | 7.066e-05 |
| 1e-09 | 7.936101251028e+03 | 7.066e-02 |

The floor is `Ky/Kx ≈ 8.1e-14`, equivalent to a spurious `|y| ≈ 9e-18 m ≈ 1e-12 σy`.
**Harmless** — and now that is a number rather than an assumption. Recorded as
LEAD U14-11 (Info, seam) so it is not rediscovered.

### 3.4 `real(T)` bug class and the reim design

Checked: `faddeeva_w_approx_reim`, `faddeeva_w_upper_reim`, `_faddeeva_w_cf_reim` are all
`where {T<:Real}` and every ordering comparison (`zi < zero(T)`, `y > T(7)`, `x > T(6)`,
`x + y > T(4000)`, `nu > T(0.4)`) is on a genuinely real-typed value. There is **no
`real(T)`-on-a-complex bug** in this file; `real(z)`/`imag(z)` appear once (line 150–151)
and act on a *value*, correctly. `faddeeva_w_approx(z::Complex{T})` is the only complex
entry point and it decomposes immediately. The scalar-only design is honored at the sole
kernel call site (`strong_beam_track.jl:398-399`, which takes `abs(x)`, `abs(y)` first, so
the upper-half-plane precondition holds).

Type genericity measured: Float32 at z = 1.5+0.7i → rel 9.97e-08 (eps(Float32) = 1.19e-07,
so at precision); `BigFloat` inputs run but cannot beat Float64 because the coefficients
are Float64 literals (rel 2.14e-16); mixed `(Float64, Float32)` is a `MethodError` (the
signature requires both `::T`) — noted, not a defect.

---

## 4. Hypothesis (c) — `beam_statistics`

N = 10⁶, β=(2,3,4), α=(1.5,−0.8,0.3), σ=(1e-3,2e-3,5e-3), six nonzero offsets,
`rng_id=17`; reference = naive `BigFloat` (256-bit) reduction over the **same** data:

| quantity | worst error |
|---|---|
| means | **0.000e+00 absolute** (largest \|mean\| = 7.0e-03) |
| covariance (21 upper-triangle entries) | **6.463e-14 relative**, at (1,4) |
| fourth central moments | **2.204e-16 relative** |
| emittances | **5.506e-14 relative** |
| `rms` vs `sqrt(diag(cov))` | **0.000e+00** |

Consistent with the prior pass's 4.8e-14.

**Covariance convention.** On `v = [1,2,4,8,16]`: `cov[1,1] = 29.760000000000009`,
which is exactly `Σ(v-μ)²/5` (**population, /n**); `Σ(v-μ)²/4 = 37.20000000000001` is
`Statistics.var`'s default and is **not** what is returned. Every other moment
computation in the repository divides by n or nlive as well —
`Beam.jl:147,149` (`_standardize!`), `Beam.jl:591,593,596` (and the masked variants at
604–629), `Contracts.jl:1338` (`_wsl_mean`), `BeamObservers.jl:1461,1494`,
`spectral.jl:796`, `spectral_cuda.jl:821,822,826,828`, `pic_cuda.jl:5208,5209`,
`slicing.jl:490`. **The convention is uniform; nothing in the repository uses n−1.**

**Edge cases.**

* `n = 0` — throws `ArgumentError: reducing over an empty collection is not allowed;
  consider supplying init to the reducer` (from `_covariance`'s `sum` over an empty
  `zip`). Loud, but undirected; `Phase6DRep`'s docstring advertises empty reps as legal
  for storage and I/O (LEAD U14-9).
* `n = 1` — `n=1`, `mean = [1.5,2.5,3.5,4.5,5.5,6.5]`, `cov[1,1] = 0`, `rms[1] = 0`,
  `emittance = [0,0,0]`. Correct under the population convention.
* all-identical (n = 1000) — means exact; covariance, rms, emittance and fourth central
  moments **all exactly zero**.
* `n = 1` through the *sampler* — `Beam(1, ...)` collapses to `(0,0,0,0,0,0)` via
  `_standardize!`'s `σ == 0` branch. Same observation the prior pass made; still true.
* the `max(·, 0)` guards hold: a perfectly correlated plane gives emittance exactly
  `0.000000e+00`, not a negative-radicand `NaN`.
* NaN handling: with the flag off a NaN **propagates** (`n=2`, `mean[1]=NaN`) rather than
  vanishing; under `allow_lost_particles` it is masked (`n=1`, `mean[1]=1`, `cov[1,1]=0`).
  This matches the documented contract exactly.

---

## 5. Hypothesis (d) — `src/track/longitudinal.jl`

### 5.1 The conventions, derived independently

I re-derived every entry rather than reading it off the table. With `ℓ` the particle path
length, `s` the reference arc, `Δt = ℓ/(βc) − s/(β₀c)`:

`z₁ ≡ −cΔt = s/β₀ − ℓ/β`, and with `z₃ = s − ℓ` this gives
**`z₁ = z₃/β + s(1/β₀ − 1/β)`**. The code's
`_z1_of(::PathLengthDelta, z, β, β₀, s) = (z + s(β/β₀ − 1))/β` is algebraically identical,
and its inverse `z₃ = βz₁ − s(β/β₀ − 1)` follows. `#2`: `σ = −β₀cΔt = β₀z₁` ✓.
`#4`: `ξ = −βcΔt = βz₁` ✓. Momenta: `E/(P₀c) = 1/β₀ + p_t`, `mc²/(P₀c) = 1/(β₀γ₀)`, so
`δ = √((1/β₀+p_t)² − 1/(β₀γ₀)²) − 1` ✓ and `p_t = −1/β₀ + √((1+δ)² + 1/(β₀γ₀)²)` ✓;
`β = Pc/E = (1+δ)/(1/β₀+p_t)` ✓. **All eight `_pt_of`/`_pz_of`/`_z1_of`/`_z_of` methods
are correct.**

Checked numerically at 2.5 GeV proton: the `s` term against the hand-derived
`z/β + s(1/β₀ − 1/β)` gives **0.0** difference at `s = 0` and **6.9e-14** at `s = 1000`
(the residual is my hand form's own `1/β₀ − 1/β` cancellation; the code's form is the
better-conditioned one).

Against physical definitions in BigFloat (`E = E₀ + p_t P₀c`, `δ = P/P₀ − 1`, `β = Pc/E`)
at 10 GeV e⁻ and 2.5 GeV p over `p_t ∈ {−0.4, −1e-3, 0, 1e-3, 0.4}`: **worst relative
`β` error 1.65e-16**; `δ` matches to the last bits at every non-zero amplitude.

### 5.2 Round trips — and the pin's envelope

12 ordered pairs × 3 energies (10 GeV e⁻, 275 GeV p, 2.5 GeV p) × 2 arc positions
(0 and 3141.59 m) × 4 sign combinations, per amplitude class:

| amplitude | max \|Δz\| | max \|Δpz\| | rel z | rel pz |
|---|---|---|---|---|
| z=5 cm, pz=3e-3 | 7.53e-13 | **3.30e-16** | 1.51e-11 | 1.10e-13 |
| z=1 mm, pz=1e-5 | 6.51e-19 | 2.68e-16 | 6.51e-16 | 2.68e-11 |
| z=1 µm, pz=1e-9 | 2.12e-22 | 4.16e-16 | 2.12e-16 | **4.16e-07** |
| z=1 nm, pz=1e-13 | 2.07e-25 | 4.75e-16 | 2.07e-16 | **4.75e-03** |

The momentum round trip is accurate to **~4e-16 absolute, independent of amplitude** —
so its *relative* accuracy degrades as 1/δ. The theory note's "**4.4e-16**" and the
brief's "**≤3.9e-17**" are absolute-scale statements measured at production amplitude;
they are correct there and **do not hold relatively below δ ≈ 1e-11**. Measured Lesson 5
("a pin that does not state the regime it was measured in will eventually be quoted
outside it") applies verbatim. See LEAD U14-4.

The `z` round trip at `s = 3141.59` loses 7.5e-13 m absolute at z = 5 cm: the intermediate
`s(β/β₀ − 1) ≈ 0.5 m` is a cancellation amplified by `s`, and 3141 × 1.5e-4 × eps
reproduces the number exactly. Sub-picometre; recorded, not a defect.

### 5.3 Conditioning of `δ ↔ p_t`

Reference: the **same expression** evaluated exactly in BigFloat with the code's own
Float64 `β₀`, `γ₀` promoted — so what is measured is the floating-point evaluation, not
input rounding. `stable` uses the exact identity `1/β₀² − 1/(β₀γ₀)² = 1`, hence
`δ = u/(√(1+u)+1)` with `u = 2p_t/β₀ + p_t²`:

| E₀ | p_t | δ | rel err (code) | rel err (stable) |
|---|---|---|---|---|
| 10 GeV e⁻ | 1e-1 | 1.000000e-01 | 5.23e-16 | 1.06e-16 |
| | 1e-2 | 1.000000e-02 | 6.08e-15 | 8.76e-16 |
| | 1e-4 | 1.000000e-04 | 1.48e-13 | 1.05e-13 |
| | 1e-6 | 1.000000e-06 | 4.51e-11 | 1.05e-11 |
| | 1e-8 | 1.000000e-08 | 6.34e-09 | 1.05e-09 |
| | 1e-10 | 1.000000e-10 | 1.86e-07 | 1.05e-07 |
| | 1e-12 | 1.000089e-12 | 9.94e-05 | 1.05e-05 |
| 2.5 GeV p | 1e-2 | 1.078054e-02 | 1.95e-14 | 6.12e-15 |
| | 1e-6 | 1.078865e-06 | 1.35e-11 | 6.16e-11 |
| | 1e-10 | 1.078866e-10 | 1.21e-06 | 6.16e-07 |
| | 1e-12 | 1.078915e-12 | 1.07e-04 | 6.16e-05 |

The inverse behaves the same (worst 8.07e-05 at δ=1e-12, 2.5 GeV p).
**Zero maps to zero** at 10 GeV e⁻ and 275 GeV p exactly; at 2.5 GeV p
`_delta_from_pt(0)` returns **−1.110e-16**. Iterating the identity sandwich
`δ → p_t → δ` from δ = 0 saturates at a **fixed point −5.551e-16 after ~10 iterations and
stays there through 10⁶** (10 GeV e⁻ stays at exactly 0), so it is a bounded bias, not a
drift. That retires the accumulation concern with a number.

### 5.4 The F16 boundary — honestly stated?

**Yes, at the reader's location.** `src/elements/rf_cavity.jl:70–84` states in the element's
own docstring that `s = 0` is used because a runtime element has no channel to its
accumulated reference path, spells out the missing `−1/γ₀²`, gives the measured
1.84× ν_s error at 2.5 GeV / α_c = 0.2, names the wrong-transition-side regime, and points
at `docs/todo.md`; the theory note carries the same correction block in §6 Step 0; and
`docs/todo.md:29` carries the open row. My own arithmetic reproduces the claim:
η_full = 0.0591433 vs η(s=0) = 0.2 at 2.5 GeV p, ratio ν_s = **1.8389**; at 10 GeV e⁻ the
ratio is 1.0000.

`longitudinal.jl` itself documents `s` correctly ("Leave `s` at its default and you are
working with `−ℓ`; pass the arc position and you get `s − ℓ`") and that statement is
algebraically right. The one gap: **the reader inside `longitudinal.jl` has no pointer to
the fact that its principal consumer leaves `s = 0`** — the trap is documented at the
element and in the note but not at the conversion whose default parameter is the trap.
That is a cross-reference, not a defect; noted here rather than as a lead.

### 5.5 The sqrt domain (LEAD U14-3)

At 2.5 GeV p the radicand of `_delta_from_pt` vanishes at `p_t = −0.6739575844`. Below it,
`sqrt` of a negative Float64 **throws `DomainError`** — on the CPU a hard stop that
`allow_lost_particles` cannot mask, and on CUDA a device-side `DomainError` that **aborts
the whole kernel launch** (`KernelException`, measured). This contradicts the region's own
documented design (`is_live`/`allow_lost_particles`: a lost particle is non-finite and
masked, and the chokepoints then decide). Reachable through `_rf_kick` for a particle
outside the RF bucket whose δ walks down to −1 (zero momentum) — the standard
longitudinal-loss scenario. Also measured: `convert_longitudinal(TIME_ENERGY =>
PATHLENGTH_DELTA, 0.01, −1.0)` throws.

---

## 6. Hypothesis (e) — device-IR compilability

**Everything in the region compiles as device IR and agrees with the CPU.** Measured on an
RTX 4500 Ada:

| check | result |
|---|---|
| fused CUDA kernel with a counter-RNG `LumpedRad` (`Radiation6DMap`), 3 turns, 4096 particles | **compiled and ran**; max\|x_gpu − x_cpu\| = **2.71e-20** (scale 3.61e-04), max\|pz_gpu − pz_cpu\| = **1.74e-18** |
| `Radiation6DMap` / `Damping6DMap` / `Diffusion6DMap` in the fused kernel | all three **compile OK** |
| `ThinRFCavity` (i.e. `convert_longitudinal`, i.e. `sqrt`) in the fused kernel, 5 turns | **compiled**; max\|pz_gpu − pz_cpu\| = **6.66e-16** |
| the U15-4 throw message | **`"unknown RNG method code; use RNG_PHILOX or RNG_SPLITMIX"` — contains no interpolated value** (verified `occursin("99", msg) == false` after `octopus_uint64(1, UInt8(99), …)`); the host-only `rng_method_symbol` still interpolates, correctly |

`src/track/Track.jl:56` throws `MethodError(track_particle, (method, op, x0, …))`, built
from runtime **values** — not device IR. It is the unregistered-(method, op) fallback, so
it is unreachable in any kernel that compiles at all, and if it ever became reachable the
failure mode is a compile error rather than a wrong answer. All of H1–H3 compiled, so it
is not in a compiled path today. Recorded as Info, not a lead.

`src/track/fused_track.jl` was read in full: both `@generated` expansions build a
straight-line call sequence over `Elems.parameters`, recursing into nested `Tuple`
parameters. No throw, no allocation, no dynamic dispatch; the `ctx`/`particle_id` variant
differs only by two extra call arguments. Sound.

---

## 7. LEADS

### LEAD U14-1 [Major, confidence high] src/track/phase6d_track.jl:304-314
Claim: the **contextless** CUDA `track!` builds a fresh `TrackingContext()` *inside* its
own turn loop, so every turn of a stochastic element draws at `turn = 0` — identical
kicks on every turn, excitation variance growing as turns² instead of turns.
Mechanism: `track!(rep, elems, turns, policy::ResolvedCUDAExecutionPolicy)` takes the
`_requires_cuda_elementwise(elems)` branch (true for `LumpedRad` with
`Radiation6DMap`/`Diffusion6DMap`), then loops `for _ in 1:turns` calling
`_track_cuda_policy_elementwise!(rep, elems, policy, TrackingContext(), stream)`. The
inner dispatch consults the *ctx* method `_requires_cuda_elementwise(::LumpedRad, ctx) =
false`, so the element is pushed into `fused` and flushed as
`track!(rep, Tuple(fused), 1, policy, ctx)` — a one-turn launch at `ctx.turn = 0`, every
time. Nothing increments the turn: the loop variable is discarded (`for _ in`). This is
the F14/U7-2 shape (correlated stochastic draws, quadratic variance) on the turn axis.
The CPU sibling (line 38) does not have the bug because it uses `Random.randn()`, which
advances; so CPU and GPU disagree structurally on this path, and no shipped test exercises
it — `test/runtests.jl:5026` is the only contextless multi-turn CUDA `track!` and its
element is deterministic.
Repro: `contextless_turns.jl`. `LumpedRadSpec(damping_turns=(1000,1000,1000),
sigma=(1,1,1), is_damping=false, is_excitation=true, rng_id=777)`, 20 000 particles
starting at the origin, 16 turns. With a context: `var(x) = 0.031669`, ratio to
`turns·exc² = 0.9906`. **Contextless (`track!(rep,(elem,),16,resolved_cuda_policy)`):
`var(x) = 0.502832`, ratio to `turns·exc² = 15.7292`, ratio to `turns²·exc² = 0.9831`;
`max|x_16 − 16·x_1| = 8.88e-16` on a scale of 2.745 and `corr(x_16, x_1) =
1.0000000000`.** The deprecated `track!(rep,(elem,),16,CUDABackend)` reproduces it
identically (`var = 0.502832`).

### LEAD U14-2 [Major, confidence high] src/math/counter_rng.jl:50-61, src/beam/Beam.jl:166, src/elements/radiation.jl:33-34, src/tasks/BPMObserver.jl:117
Claim: explicit `rng_id`s do not reserve themselves in the atomic auto-id counter, and the
three consumer classes share one stream namespace with no cross-check, so a beam with an
explicit id and an auto-assigned radiation element (or BPM) draw the **identical** stream.
Mechanism: `next_rng_id!` hands out 1, 2, 3, … and is the only allocator, but
`Beam(...; rng_id=k)`, `LumpedRadSpec(...; rng_id=k)` and `BPMObserver(...; rng_id=k)`
bypass it entirely without marking `k` as taken. Beam initialisation draws at `turn = 0`
with `component = 1..6` and `particle = i`; `LumpedRad` excitation draws at `ctx.turn`
(which starts at 0, since `track!` uses `ctx.turn + (turn-1)`) with the same components
and particle index. Same key, same counter, same numbers.
`Tasks._warn_duplicate_radiation_streams` — the F14 remedy — collects ids from
`ElementSpec{:lumped_radiation}` only, so it cannot see a beam or a BPM.
Repro: `stream_namespace.jl`. In a fresh session (`reset_rng_id_counter!(0)`):
`Beam(20000, CPUThreadsBackend, Float64; rng_id=1)` then
`LumpedRadSpec(damping_turns=(1000,1000,1000), sigma=(1,1,1))` → **auto-assigned
`rng_id = 1`**; the beam's raw component-1 draws and the element's first-turn `nx` are
**bitwise identical for all 20 000 particles**, `corr = 1.000000`, and `corr(beam.rep.x,
nx) = 1.000000` after standardisation and scaling. Same for
`BPMObserver("m1"; x_noise=1e-5)` → auto `rng_id = 1`. An all-auto session gives
beam 1 / rad 2 / bpm 3 (disjoint), which is the only thing protecting shipped
configurations today.

### LEAD U14-3 [Medium, confidence high] src/track/longitudinal.jl:133-136 (`_delta_from_pt`), reached from `convert_longitudinal`
Claim: a particle decelerated below rest energy makes the radicand negative and `sqrt`
throws `DomainError` — a hard stop that `allow_lost_particles` cannot mask and that aborts
the entire CUDA kernel launch, instead of producing the non-finite coordinate this
repository's loss design is built on.
Mechanism: `_delta_from_pt` evaluates `-1 + sqrt((1/β₀ + p_t)^2 - ibg^2)`. The radicand
vanishes at `p_t = -1/β₀ + 1/(β₀γ₀)` and goes negative below it. Julia's `sqrt(::Float64)`
throws `DomainError` rather than returning `NaN`, so the `is_live`/`allow_lost_particles`
machinery in `Beam.jl:199-310` — which defines a dead particle as one with a non-finite
coordinate and exists precisely so a run can continue over the survivors — can never see
this particle. `_rf_kick` (rf_cavity.jl:96-101) calls `convert_longitudinal` per particle
per turn, so the path is live for any particle outside the RF bucket whose δ walks to −1.
Repro: `longitudinal.jl` §F5 and `device_ir.jl` §H4. At 2.5 GeV proton
(`β₀ = 0.9268998208`, `γ₀ = 2.664472`) the threshold is `p_t = -0.6739575844`:
`Octopus._delta_from_pt(-0.674, β₀, γ₀)` → `DomainError with -8.0974e-13`;
`convert_longitudinal(TIME_ENERGY => PATHLENGTH_DELTA, 0.01, -1.0; beta0=β₀, gamma0=γ₀)`
→ `DomainError`. The same call inside a CUDA kernel → `CUDACore.KernelException`
("a DomainError was thrown during kernel execution on thread (1,1,1) in block (1,1,1)"),
i.e. the whole launch dies, not one particle.

### LEAD U14-4 [Low, confidence high] src/track/longitudinal.jl:133-148, and the "4.4e-16" pin in docs/theory/rf_cavity_and_reference_energy.md §6
Claim: `_delta_from_pt` and `_pt_from_delta` are written in their cancelling forms, so
their **relative** accuracy degrades as 1/amplitude; the committed round-trip pin is an
absolute-scale number quoted without its envelope.
Mechanism: `δ = -1 + sqrt(...)` subtracts two quantities that are both ≈ 1, so the result
carries ~1 ulp of the *operands*, i.e. ~1e-16 absolute regardless of how small δ is.
The identity `1/β₀² - 1/(β₀γ₀)² = 1` is exact, which makes
`δ = u/(√(1+u)+1)` with `u = 2p_t/β₀ + p_t²` (and the mirror form for the inverse)
cancellation-free. The file already applies exactly this reasoning to `reference_beta`
(choosing `√((γ-1)(γ+1))/γ` for conditioning), so the standard is the file's own.
Repro: `longitudinal2.jl` §G1/G2/G4 — reference is the same expression evaluated exactly
in BigFloat on the code's own Float64 β₀/γ₀. At 10 GeV e⁻: `p_t = 1e-6` → code
**4.51e-11** vs stable **1.05e-11**; `p_t = 1e-12` → code **9.94e-05** vs stable
**1.05e-05**. Round trips over 12 ordered pairs × 3 energies × 2 arc positions:
`|Δpz| = 3.30e-16 / 2.68e-16 / 4.16e-16 / 4.75e-16` at pz = 3e-3 / 1e-5 / 1e-9 / 1e-13
respectively — flat in absolute terms, hence **1.10e-13 / 2.68e-11 / 4.16e-07 /
4.75e-03** relative.

### LEAD U14-5 [Low, confidence high] src/beam/Beam.jl:445-455 vs 457-474
Claim: the U15-7 directed refusal for non-`AbstractFloat` coordinate types was added to
the policy overload only; the backend-tag overload — which the same docstring advertises —
still produces the deep `MethodError` the refusal exists to prevent.
Mechanism: `Beam(N, policy::AbstractExecutionPolicy, FloatT::Type{RT}) where {RT<:Real}`
carries the `RT <: AbstractFloat || throw(ArgumentError(...))` guard at line 449 and then
forwards to `Beam(N, backend_type(policy), RT; ...)`. But
`Beam(N, backend::Type{BTAG}, FloatT::Type{RT}=Float64; ...) where {RT<:Real}` at line 457
is a separate entry point with no guard, and the docstring at 437-439 explicitly lists
`CPUThreadsBackend` and `CUDABackend` as accepted second arguments.
Repro: `misc_checks.jl` §J1. `Beam(4, CPUThreadsExecutionPolicy(), Rational{Int})` →
`ArgumentError: Beam sampling requires an AbstractFloat coordinate type ...`.
`Beam(4, CPUThreadsBackend, Rational{Int})` → `MethodError: no method matching
octopus_normal(::UInt64, ::UInt8, ::Int64, ::UInt64, ::Int64, ::Int64,
::Type{Rational{Int64}})`.

### LEAD U14-6 [Low, confidence high] src/track/longitudinal.jl:100-103 (`reference_beta` docstring)
Claim: the docstring's stated *reason* for choosing `√((γ-1)(γ+1))/γ` is measurably
backwards — the form gains nothing at large γ (and is very slightly worse at the
repository's own moderate-γ validation points), and gains only as γ → 1, the regime the
docstring dismisses.
Mechanism: the docstring says the form "keeps its digits when `γ` is large, which is the
only regime this is ever used in". The cancellation `γ² - 1` is catastrophic as γ → 1, not
as γ → ∞; at large γ, `1 - 1/γ²` subtracts a tiny number from 1 and loses nothing. And
"the only regime" is contradicted by the repository's own 2.5 GeV proton (γ = 2.66)
validation case, which is exactly what the F16 note is about.
Repro: `longitudinal2.jl` §G5, errors vs BigFloat evaluation of the same expression:
γ = 19569.5 → code 1.047e-17, naive 1.047e-17 (**identical**);
γ = 293.092 → code 7.052e-17, naive 4.050e-17 (**code worse**);
γ = 2.66447 → code 7.414e-17, naive 4.564e-17 (**code worse**);
γ → 1 (`E0 = 1.0000001 mc²`) → code 1.046e-11, naive 7.040e-11 (**code better**);
γ → 1 hard → code 2.584e-08, naive 2.659e-08 (**code better**).
All the large-γ differences are sub-ulp, so the *choice* is harmless — it is the
justification that is wrong, and a future reader will trust it.

### LEAD U14-7 [Low, confidence med] src/track/radiation_track.jl:33-65
Claim: `cuda_track_lumped_rad_kernel!` is the only GPU radiation path that does **not**
use the counter RNG, it is unreachable from the policy API, and no test covers it — so a
divergent, non-reproducible implementation is being carried untested.
Mechanism: it draws with `Random.randn(CUDA.default_rng(), T, N)` (radiation_track.jl:37-42),
so its results depend on CUDA's own RNG state rather than `set_global_rng!`, cannot match
the CPU, and are not thread/layout invariant in the way the counter RNG guarantees.
Selection: `_requires_cuda_elementwise(elem::LumpedRad)` (no ctx) is `true`, but
`_track_cuda_policy_elementwise!` consults `_requires_cuda_elementwise(elem, ctx)` which is
`false`, so inside any policy `track!` the element is fused and this kernel is skipped.
It remains reachable through the deprecated single-element
`track!(rep, elem, turns, CUDABackend)`. It also allocates six N-length `CuArray`s **per
turn**.
Repro: `contextless_turns.jl` §I5. `Octopus._requires_cuda_elementwise(elem)` → `true`;
`Octopus._requires_cuda_elementwise(elem, TrackingContext())` → `false`.
`track!(rg, elem, 16, CUDABackend)` (bare element, not a tuple) reaches it and gives
`var(x) = 0.032156`, ratio to `turns·exc² = 1.0059` — statistically right, from a
different and unreproducible stream. `grep -rn "LumpedRad" test/runtests.jl validation
examples | grep -i "cuda|gpu"` returns nothing.

### LEAD U14-8 [Low, confidence high] src/track/phase6d_track.jl:38-48 vs 304-314
Claim: `_reject_contextless_tracking` — the directed refusal that exists so a
loss-recording line cannot run with an empty loss log — is wired into the CPU contextless
path only; the same line on CUDA fails with a ~100-line `GPUCompiler.InvalidIRError`
instead.
Mechanism: line 39 is the only call site in `src/` (verified by grep). The CUDA
contextless `track!` at line 304 has no equivalent check. It does **not** silently produce
an empty log — the aperture's non-context call is not device-compilable, so the launch
fails — but the failure is undirected, and the guard's docstring (lines 50-58) presents the
refusal as the design's protection without noting it covers one backend.
Repro: `contextless_guard.jl`. A line
`(DriftSpec(L=0.5), ApertureSpec(shape=:rectangle, x_limit=2e-3, y_limit=1.0, name="A",
element_id=1, loss_record=rec))` with `_requires_tracking_context = true`:
CPU contextless → `ArgumentError: this line contains an aperture with a loss record
attached, ...` (directed). CUDA contextless → `GPUCompiler.InvalidIRError: compiling
MethodInstance for Octopus.cuda_track_kernel!(...)`. The supported context path gives
`loss_counts = Int32[38]`, 38 recorded rows.

### LEAD U14-9 [Low, confidence high] src/beam/Beam.jl:650-691 vs 40-44
Claim: `beam_statistics` on an empty `Phase6DRep` raises Base's generic
"reducing over an empty collection" rather than a directed error, while the
`Phase6DRep` docstring advertises empty reps as legal for storage and I/O.
Mechanism: `_mean(v) = sum(v)/length(v)` survives an empty vector (`sum(Float64[]) = 0.0`),
but `_covariance` is `sum(f, zip(a,b))` with a function argument and no `init`, which Base
refuses on an empty collection. The failure therefore names neither `beam_statistics` nor
the empty beam. Contrast the file's own directed errors (`Phase6DRep` length mismatch,
`Beam` particle count, storage/policy mismatch), all of which name the problem.
Repro: `beam_stats.jl` §E3.
`beam_statistics(Phase6DRep(Float64[], Float64[], Float64[], Float64[], Float64[],
Float64[]))` → `ArgumentError: reducing over an empty collection is not allowed; consider
supplying init to the reducer`.

### LEAD U14-10 [Info, confidence high] src/math/SpecialMath.jl:92-97
Claim: `pi = zero(T)` inside `faddeeva_w_upper_reim` shadows `Base.pi` for the rest of the
function body — a latent trap for anyone who later writes `pi` in that scope meaning π.
Mechanism: Julia allows a local binding to shadow a `Base` constant with no warning; the
loop then reads `pr, pi = _cmul_reim(pr, pi, zrZ, ziZ)`. The code is correct today
(π is never needed there), but the function is the CUDA beam-beam hot path where an
accidental `T(pi)` would silently become `T(0)`.
Repro: read-only; `Octopus.faddeeva_w_upper_reim` gives correct values today (see the
§3.1 table), so this is a maintenance hazard, not a wrong answer. Renaming the local to
`pim`/`pi_` removes it at zero cost.

### LEAD U14-11 [Info/seam, confidence high] src/math/SpecialMath.jl accuracy → src/track/strong_beam_track.jl:390-415 (OUTSIDE U14's region)
Claim: the Faddeeva real part carries no relative accuracy near the real axis, and its
consumer forms the *vertical* beam-beam kick from exactly that quantity, giving a nonzero
`Ky` where symmetry demands zero. **Measured, and negligible** — recorded so the seam is
not rediscovered as an open question.
Mechanism: `Re w(x + i0) = e^{-x²}`, which for x ≳ 5 is far below the ~1e-14 absolute
error of the |w| evaluation, so `Re w` is noise at that level.
`_cuda_elliptic_gaussian_kick_principal` sets `Ky = A(w1r − B·w2r)`.
Repro: `weideman_coeffs.jl` §BE. At σ₁ = 106 µm, σ₂ = 9.5 µm, x = 3e-4 m: `Ky(y=0) =
6.411e-10` (exact answer 0) against `Kx = 7.936e+03`, i.e. `Ky/Kx = 8.1e-14`, an effective
spurious `|y| ≈ 9e-18 m ≈ 1e-12 σy`. `Ky(y=1e-9) = 7.066e-02`, so the floor is reached only
below `|y| ≈ 1e-17 m`. At x = 1e-3 m and 2e-3 m the floors are 5.97e-10 and 1.61e-10.
Seam noted; the auditor owns whether anything is due here.

---

## 8. Clean list — audited sound, with the evidence

1. **Philox4x32-10 is bit-exact against the OFFICIAL Random123 stream.** All three
   upstream `philox4x32 10` KAT vectors reproduced by an independently written
   implementation (upstream key-schedule ordering, so not a copy of Octopus's loop), and
   that implementation agrees with Octopus's public `counter_philox4x32` on **20 004
   tuples with 0 mismatches**, including `typemax` corners. Round count proven to be 10 by
   sensitivity (R=8..12 all differ). `counter_uint64` packing verified over 2 000 tuples.
   [`philox_kat_independent.jl`]
2. **The round function and constants match the published spec term for term.**
   `_philox4x32_round` returns `(hi1⊻c1⊻k0, lo1, hi0⊻c3⊻k1, lo0)` with
   `M0=0xD2511F53`, `M1=0xCD9E8D57`, `W0=0x9E3779B9`, `W1=0xBB67AE85` — read against the
   spec, then confirmed end to end by (1). The trailing key bump after round 10 is dead
   and harmless (`k0`, `k1` are locals).
3. **Stream separation is real, not assumed.** 48 000/48 000 distinct outputs over
   20 turns × 10 ids × 40 particles × 6 components; 32 008/32 008 distinct keys over
   `rng_id ∈ 0:4000 × component ∈ 1:8`; all seven independence correlations within 1σ of
   zero at N = 10⁶ (table in §2.2), including the radiation-vs-BPM pair at 2.05e-04.
   [`stream_structure.jl`]
4. **`next_rng_id!` is genuinely atomic.** 20 000 concurrent calls on 4 threads →
   20 000 distinct ids, contiguous 1..20 000. The U15-5 fix holds under load.
5. **The U15-4 throw carries a STATIC message and the fused CUDA kernel compiles.**
   `octopus_uint64(1, UInt8(99), 2, 3, 4, 5)` → `ArgumentError("unknown RNG method code;
   use RNG_PHILOX or RNG_SPLITMIX")`, verified to contain no interpolated value. A fused
   CUDA kernel containing a counter-RNG `LumpedRad` compiles and runs for **all three**
   tracking methods, and agrees with the CPU to 2.71e-20 in x and 1.74e-18 in pz over
   3 turns. An RF cavity (i.e. `sqrt` and the full conversion sandwich) also compiles, to
   6.66e-16. [`device_ir.jl`]
6. **`_uniform_open01` is exactly open in both precisions.** Extreme `UInt64` inputs give
   `1.1102230246251565e-16` and `0.99999999999999989`; 200 000 draws in Float32 and
   Float64 are strictly inside (0,1). The "one fewer source bit" comment is right
   (52 bits for Float64 at 2⁻⁵², 23 bits for Float32 at 2⁻²³).
7. **Both RNG methods are wired through and distinguishable.** `set_global_rng!(method=
   :splitmix)` changes `octopus_normal` (1.8827661679174839 vs 0.59083346378504009 at the
   same tuple) and changes a constructed `Beam`. `rng_method_code`/`rng_method_symbol`
   round-trip and throw on unknown codes.
8. **Faddeeva is accurate to 3.09e-13 relative on |w| everywhere probed** — 1 040 points
   spanning the Weideman interior, the near-real-axis band, every branch boundary
   (y=7, x=6/y=0.1, x=8/y=1e-10, x=28, x+y=4000, x+y=1e7 with both far-field forms), the
   gap regions between branches, and all four quadrants — against a `Complex{BigFloat}`
   reference at 4096-bit precision that was itself cross-validated two ways to 1.09e-96.
   All exact anchors reproduce. [`faddeeva_bigfloat.jl`]
9. **The 32 Weideman coefficients are derived, not drifted.** Regenerated from Weideman's
   own FFT construction in BigFloat: `L` bit-identical, `1/√π` at 0.00 ulp, worst absolute
   coefficient difference 7.79e-15, and substituting the exact coefficients changes `w` by
   at most **1.05e-14** relative — 30× below the method's own error.
   [`weideman_coeffs.jl`]
10. **Every algebraic form in `_faddeeva_w_cf_reim` re-derived and correct**: both
    `x+y > 1e7` forms reduce to `i/(√π z)` with the right sign for negative real part; the
    `x+y > 4000` form is `i z/(√π(z²−½))` term for term; the Laplace CF recursion and its
    `i/(√π W)` finish are exact. The lower-half-plane reflection
    `2 exp(-z²) − w(−z)` is correct, with `_cexp_reim(-zr²+zi², -2 zr zi) = exp(-z²)`.
11. **No `real(T)` ordering bug anywhere in SpecialMath.** Every branch comparison is on a
    `T<:Real`-typed value; `real`/`imag` are applied to values, once, correctly. The
    scalar (zr, zi) design is honored at the only kernel call site, which takes absolute
    coordinates first so the upper-half-plane precondition holds.
12. **`beam_statistics` is numerically true**: means exact to 0.0 absolute, covariance
    6.46e-14, emittance 5.51e-14, fourth central 2.20e-16 relative vs BigFloat on the same
    10⁶-particle data; `rms == sqrt(diag(cov))` bitwise. [`beam_stats.jl`]
13. **The covariance convention is population (/n) and uniform across the repository.**
    Verified numerically (`29.760000000000009` = Σ(v−μ)²/5, not /4), then checked against
    every other moment site: `Beam.jl` 147/149/591/593/596 and the masked variants,
    `Contracts.jl:1338`, `BeamObservers.jl:1461,1494`, `spectral.jl:796`,
    `spectral_cuda.jl:821-828`, `pic_cuda.jl:5208-5209`, `slicing.jl:490`. **No n−1
    anywhere.**
14. **The degenerate-beam edges behave.** n=1 → zero covariance/rms/emittance with correct
    means; all-identical → every second and fourth moment exactly zero; a perfectly
    correlated plane → emittance exactly 0 (the `max(·,0)` guard holds); NaN propagates by
    default and is masked with `allow_lost_particles` (n drops 2→1, moments correct).
15. **All four longitudinal conventions and all eight conversion methods are correct**,
    derived independently from `Δt = ℓ/(βc) − s/(β₀c)` rather than read off the table; the
    `s`-term algebra matches a hand derivation to 0.0 at s=0. The momentum relations match
    the physical definitions (`E = E₀ + p_t P₀c`, `δ = P/P₀ − 1`, `β = Pc/E`) in BigFloat
    to 1.65e-16 in β. [`longitudinal.jl`, `longitudinal2.jl`]
16. **Round trips are exact at production amplitude**: max |Δpz| = 3.30e-16 and
    |Δz| = 7.53e-13 m over 12 ordered pairs × 3 energies × 2 arc positions at z=5 cm,
    pz=3e-3. (The envelope is LEAD U14-4.) The zero-input bias saturates at a fixed point
    −5.55e-16 in δ and does not accumulate over 10⁶ sandwiches.
17. **The F16 model boundary is honestly and completely stated** — on the element
    (`rf_cavity.jl:70-84`, with the mechanism, the measured 1.84× ν_s error, the
    wrong-transition-side regime, and the reason the fix is blocked), in the theory note's
    §6 correction block, and as an open row in `docs/todo.md:29`. My own arithmetic
    reproduces the number: η_full = 0.0591433 vs η(s=0) = 0.2 at 2.5 GeV p / α_c = 0.2 →
    ν_s ratio **1.8389**; 1.0000 at 10 GeV e⁻.
18. **`reference_beta` refuses γ < 1 loudly and correctly**, with a message that names the
    total-vs-kinetic-energy trap.
19. **`fused_track.jl` is sound**: both `@generated` expansions produce a straight-line
    call sequence with compile-time tuple recursion, no throw, no allocation; the
    context variant differs only by the two extra leading arguments.
20. **`Track.jl` is sound**: `TrackingContext` is `isbits` (Int64/UInt64/UInt8) and passes
    to CUDA kernels; `with_turn` is the single mutation point; the default
    `(op::AbstractTrackOp)(ctx, particle_id, coords...)` correctly forwards to the
    context-free method so deterministic elements need no ctx overload.
21. **The turn advance is right on both supported paths**: CPU `track!` line 28 and the
    CUDA context kernel line 206 both compute `with_turn(ctx, ctx.turn + Int64(turn - 1))`,
    so turn `t` of a run started at `ctx.turn = 0` draws at counter `t-1`, consistently.
    Measured GPU/CPU agreement to 1.67e-16 over 16 turns of stochastic tracking.
22. **Compact I/O is coherent and now documented.** Two writes then `record=0` returns the
    **first** record `[1.0,1.0,1.0]` and `record=1` the second `[9.0,9.0,9.0]` — matching
    the U15-6 docstring added in the diff; reading past the end raises `EOFError` (loud).
23. **The U15-3 cutoff divergence, U15-2 key-collision limitation and U15-6 append default
    are all now documented in the code at the place they bite**, each with the measured
    numbers and the reason the behavior is kept. The comments match what I measured.
24. **The U7-2 strong-beam fix in the diff is right by inspection**: `turn_lum` is reset at
    the top of the in-kernel turn loop in both the thin and sliced kernels, so
    `last_luminosity` is the final turn's value as on the CPU.

---

## 9. Not checked, and why

* **`splitmix_uint64` as a production generator.** Exercised for wiring and
  distinguishability only (§8.7). Its statistical quality was not measured; the docstring
  says "exposed for comparison and validation. Prefer the Philox-backed `counter_uint64`
  for production", and no shipped configuration selects it. The U15-2 XOR-collision
  structure applies to it over all four fields and is documented in the code.
* **Multi-GPU.** `_cuda_storage_device` and the device-mismatch errors were read, not
  executed: one device is present.
* **`Adapt.@adapt_structure Phase6DRep` and `CUDA.cudaconvert(rep)`** were read; their
  correctness is exercised indirectly by every CUDA measurement above but was not probed
  in isolation.
* **Performance.** No timing was taken. The prior pass's 39.8% covariance-mirror figure
  was not re-measured; the mirror's *exactness* is structural (`_covariance` sums in
  particle order and IEEE multiplication commutes) and I did re-derive that argument, but
  I did not re-run the benchmark. `radiation_track.jl`'s six per-turn `CuArray`
  allocations are noted in LEAD U14-7 without a cost measurement.
* **The full test suite gate.** Not run — a reading unit does not modify or gate the
  repository. Every claim above is from a read-only probe in session scratch.
* **`allow_lost_particles` interaction with the LEAD U14-3 `DomainError`** was reasoned,
  not measured end to end through a `TrackingTask`: the flag is a `ScopedValue` consulted
  by reductions and chokepoints, and a `DomainError` bypasses all of them by construction,
  so there is nothing for the flag to mask. Confirming that through a full task run is the
  auditor's call.
* **Whether LEAD U14-2's collision is reachable from any *shipped* run.** I enumerated
  every `rng_id` in `src/contracts`, `examples/`, `validation/` and `test/` and found them
  disjoint (§2.3), but that is a snapshot of hand-maintained values, not a proof. The
  reachability of the *pattern* is measured; the reachability in a given committed script
  is a grep that will rot.
