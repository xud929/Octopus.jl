# Comprehensive Audit — 2026-08-03 .. 2026-08-04 (parts 1–9, merged)

> Nine session records merged into one file on 2026-08-04; each part is
> **verbatim** below, in order, with cross-part links rewritten to the
> `#part-N` anchors. The series' rule that corrections sit beside the
> claims they correct is unchanged by the merge.
>
> | part | session |
> |---|---|
> | [1](#part-1) | Comprehensive Audit — 2026-08-03 |
> | [2](#part-2) | Comprehensive Audit — 2026-08-03, part 2 |
> | [3](#part-3) | Comprehensive Audit — 2026-08-03, part 3 |
> | [4](#part-4) | Comprehensive Audit — 2026-08-03, part 4 |
> | [5](#part-5) | Comprehensive Audit — 2026-08-03, part 5 |
> | [6](#part-6) | Comprehensive Audit — 2026-08-03, part 6 |
> | [7](#part-7) | Comprehensive Audit — 2026-08-03, part 7 |
> | [8](#part-8) | Comprehensive Audit — 2026-08-04, part 8 |
> | [9](#part-9) | Comprehensive Audit — 2026-08-04, part 9 |

---

<a id="part-1"></a>

# Comprehensive Audit — 2026-08-03

A repository-wide audit run against the protocol in
[`docs/comprehensive_audit.md`](../comprehensive_audit.md). **Seven confirmed
defects, all fixed**, every one of them in code whose tests were passing.

Two of the seven are the same Julia closure-capture bug in two different files,
and it is the most consequential thing in this document: **the default
longitudinal slicing method and the strong-strong luminosity accumulator were
both silently wrong, and irreproducible, on more than one CPU thread.** Neither
had anything to do with the physics; both were a variable name reused between a
`do` block and its enclosing function.

The scope requested was the whole repository at full depth. It was not achieved,
and Section 2 says exactly how far it got.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| F1 | **Critical** | aperture loss counter races under CPU threads | fixed, verified |
| F5 | **Critical** | `_threaded_histogram` closure capture → default `:equal_area` slicing silently wrong under threads | fixed, verified |
| F6 | **Critical** | `_slice_slice_gaussian_kick!` closure capture → strong-strong luminosity accumulator corrupted under threads | fixed, verified |
| F2 | **Major** | skew dipole in a curved frame is not symplectic | fixed, verified |
| F3 | **Major** | curved solenoid + multipoles is not symplectic | fixed, verified |
| F7 | Moderate | `validation/strong_strong_spectral_comparison.jl` unrunnable since ~2026-07-30 | fixed, verified |
| F4 | Minor | two error messages print their own source text | fixed |

**The pattern worth taking away.** Every one of these had a test asserting the
right invariant, and every test passed:

- F1's invariant (`sum(loss_counts) == dead`) was asserted and *could not* fail,
  because CI ran single-threaded and the worker fan-out has a `nworkers == 1`
  fast path that never spawns.
- F5 was caught only because CI was changed to run threaded as part of fixing
  F1. It had been wrong on every multi-threaded run.
- F2 and F3 sat in configurations whose tests checked `isfinite` and `isbits`
  but never symplecticity.

This is a Phase 9 result, not a Phase 8 one. The suite was green throughout, and
the reason it was green is that it was not exercising the concurrent paths at
all.

## 2. Declared scope and coverage ledger

Requested: whole repository, deepest depth. Delivered: **~7,800 of 30,899
source lines read line by line (~25%)**, plus two whole-repository mechanical
sweeps (§8a) that do cover all 30,899 lines for one specific bug class, plus the
contracts and validation runs of §6.

The distinction matters and is not a way of inflating the number: a `Core.Box`
census over 1,792 methods genuinely inspects every file for *one* property. It
says nothing about whether the physics in those files is right.

The concern was raised before starting and the boundary was set by the session
ending, not by the work being complete. This ledger is what makes the claim
checkable.

### Read in full, line by line

`src/Octopus.jl` (76), `constants/Constants.jl` (32), `math/SpecialMath.jl`
(161), `knowledge/Methods.jl` (75), `track/longitudinal.jl` (232),
`elements/lattice_magnets.jl` (1192), `elements/solenoid.jl` (399),
`elements/misalignment.jl` (293), `elements/ref_tilt.jl` (126),
`elements/patch.jl` (209), `elements/rf_cavity.jl` (223),
`elements/thin_elements.jl` (347), `elements/beam_line.jl` (561),
`elements/aperture.jl` (540), `elements/crab_cavity.jl` (182),
`elements/lorentz_boost.jl` (163), `elements/Elements.jl` (15),
`tasks/BPMObserver.jl` (241), plus `Project.toml` and `.github/workflows/ci.yml`.

Added in the second pass: `math/counter_rng.jl` (336, in full),
`elements/linear_maps.jl` (237), `elements/radiation.jl` (314),
`track/fused_track.jl` (78).

**Verified in the second pass.** `counter_rng.jl`'s `_philox4x32_round` returns
`(hi1⊻c1⊻k0, lo1, hi0⊻c3⊻k1, lo0)` — bit-for-bit the Random123 reference round,
with M0/M1/W0/W1 correct and the key bumped after each round so round 1 uses the
unbumped key. `_uniform_open01` is provably strictly inside `(0,1)` with an exact
`+0.5` (52 and 23 source bits), which is what keeps `log(u1)` finite in
Box–Muller. `LumpedRad`'s damping/excitation pair gives stationary variance
`σ²s²/(1−d²) = σ²` exactly for `d = e^{−1/τ}`, `s = √(1−e^{−2/τ})`, and
`_radiation_excitation` reproduces the Twiss ellipse
(`⟨x·px⟩/⟨x²⟩ = −α/β`, `⟨px²⟩ = σ²s²(1+α²)/β²`).

**Two observations, neither promoted to a finding.** `next_rng_id!`
(`counter_rng.jl:47`) is a non-atomic `Ref` increment — the same class as F1, but
it runs at host-side construction, not on a tracking path, so two concurrently
constructed observers would need to race for it to matter. And `cutoff` means
*reject and redraw* in `_alloc_randn(CPUThreadsBackend, …)` but *clip* in the
CUDA method; the default counter-RNG path clips on both backends and so stays
CPU/GPU-identical, which is why the consistency contracts do not see it. The
divergence is reachable only by passing an explicit `rng`.

### Read in part, in pursuit of F5/F6

- `tasks/strongstrong/slicing.jl` — `_longitudinal_slices_equal_area`,
  `_threaded_histogram`, `_threaded_indices_by_function`, `_slice_bin`,
  `_live_z_stats`, `_live_flags`, `_chunk_bounds`, `_slices_from_boundaries`.
- `tasks/strongstrong/gaussian.jl` — `_slice_slice_gaussian_kick!`.
- `tasks/strongstrong/spectral.jl` — `_spectral_collide_longitudinal!`.
- `policies/Policies.jl` — the worker fan-out (l. 205–254).
- `track/phase6d_track.jl` — l. 55–124.
- `docs/theory/solenoid.md` §13–15; `docs/todo.md` header.

### Not inspected at all

`Knowledge.jl` (885), `Contracts.jl` (1963), `Beam.jl` (721), `Knobs.jl` (896),
`symbolic.jl` (285), `counter_rng.jl` (336), `Registry.jl` (209), `Tasks.jl`
(753), `BeamObservers.jl` (1446), `strong_beam.jl` (1547), `linear6d.jl`,
`linear_maps.jl`, `chromaticity_kick.jl`, `radiation.jl`, and the bulk of
`src/tasks/strongstrong/` — `pic_cuda.jl` (5807), `interface.jl` (2093),
`pic_cpu.jl` (1715), `gaussian_pic_cuda.jl` (1154), and the CUDA ports. Also
untouched: all 43 files of `validation/`, `examples/`, and nine of eleven
`docs/theory/` notes.

**Every CUDA path is unaudited.** F5 and F6 are CPU-threading defects; the
corresponding GPU kernels were not examined, and the same class of bug cannot
occur there in the same way, but nothing here establishes that they are correct.

### Equations independently derived

1. All four longitudinal conventions and the six conversions between them —
   `p_t = √((1+δ)² + 1/(β₀γ₀)²) − 1/β₀`, its exact inverse, `dδ/dp_t = 1/β`, and
   `z₃ = βz₁ − s(β/β₀ − 1)` from `z₃ = s − βct`. Symplecticity shown exactly.
2. The exact solenoid displacement `Δ(x+iy) = (W₀/p_s)(1−e^{−iκL})/(iκ)`,
   reducing to the Larmor half-angle form.
3. The curved-frame solenoid equations of motion from `H = −(1+hx)p_s`.
4. The gradient condition for a multipole kick in a curved frame — the
   derivation that produced F2 and F3.
5. The crab-cavity kick as `∇V`.
6. `_misalign_matrix` composition orders, `_survey_frame`, `_frame_change`,
   `_patch_reference_length`.
7. Faddeeva reflection, continued fraction, both asymptotic branches.
8. `rf_strength = qV/(β₀E₀) = qV/(P₀c)`, `k = 2πf/c`.

All physical constants checked against CODATA 2022.

## 3. The closure-capture defect (F5, F6)

### Mechanism

In Julia a `do` block is a closure, and **`if` does not open a scope while
`for`, `let` and `function` do**. So a name assigned at the top level of a `do`
block, which is *also* assigned anywhere in the enclosing function body outside a
`for`, is not a per-invocation local: it is one shared `Core.Box` captured by the
closure. When that closure is handed to `Threads.@spawn` once per worker, every
worker reads and writes the same box.

`_threaded_histogram` had exactly this shape:

```julia
if nchunks == 1
    counts = zeros(Int, bins)        # function scope: `if` does not scope
    ...
    return counts
end
local_counts = [zeros(Int, bins) for _ in 1:nchunks]
_run_logical_workers(nchunks) do chunk, _
    counts = local_counts[chunk]     # SAME variable, shared by all 8 workers
    ...
    counts[bin] += 1                 # increments whoever's array is in the box
end
counts = local_counts[1]             # function scope again
```

The per-chunk buffers were allocated correctly and the fan-out was correct. The
bug was purely that `counts` did not mean what it looks like it means.

### Evidence

Everything downstream was eliminated first, which is what made the diagnosis
certain rather than plausible:

- `_run_logical_workers` **joins correctly**: 0/200 trials returned before a
  worker finished, per-chunk buffers were 8 distinct objects, and the chunk
  indices seen were exactly `[1..8]`.
- `_chunk_bounds` covers `1:400` exactly once (`min = max = 1`).
- `_live_z_stats` and the liveness flags were **stable** across 12 repeats
  (`n_live = 397`, identical `zmin`/`zmax`).
- `_threaded_histogram` was **not**: 12 identical calls returned 12 distinct
  vectors, with totals of 392, 393, 394, 395, 396, 397 and **399** where the
  answer is 397. Individual bins both gained and lost counts (`+3`, `−2`, `+1`,
  `−1` at scattered indices). *Over*counting rules out a plain lost update and
  points at shared mutable state.
- A byte-for-byte replica of the function body in a separate file, reusing the
  same name, **reproduced the corruption**; two replicas differing only in
  using distinct names (`c`/`out`) were exact over 200 repeats. That is the
  controlled pair.
- After the rename, the library function was exact 10/10 while the unfixed
  replica still corrupted — the same pair, the other way round.

### Consequence

`LongitudinalSlicing` defaults to `method = :equal_area`
(`interface.jl:568`), and the histogram sets its slice boundaries. Measured
against the same beam sliced without lost particles, the boundaries and weights
disagreed by whole particles — weights differing by exact multiples of `1/397`,
e.g. `[99,99,99,100]/397` against the correct `[99,98,99,101]/397` — and
differently on every run. On the pristine tree the check failed **5 of 6 runs**
at 8 threads and passed at 1 and 2.

This affects any multi-threaded strong-strong run using the default slicing with
more than one slice. It does not affect `nslices = 1` (the boundary loop is
empty) and it did not affect the other four slicing methods.

F6 is the same defect in `_slice_slice_gaussian_kick!`, where the shared box was
the luminosity accumulator `lum`. The kicks themselves were unaffected —
`_apply_slice_kick_one!` writes per particle — but the returned luminosity was
corrupted. Luminosity is a headline observable of a beam-beam code.

### Sweep

Because the mechanism is a naming accident rather than a physics mistake, it was
swept for mechanically rather than by eye: every `_run_logical_workers` caller
(15 sites) had the lowered code of its enclosing function searched for
`Core.Box`. Two carried one — `_slice_slice_gaussian_kick!` and
`_spectral_collide_longitudinal!` — and a first, cruder text-based sweep produced
six false positives, all of them variables assigned inside a `for` body, which
*does* scope. The text sweep also **missed** `_spectral_collide_longitudinal!`.
Use the `Core.Box` test, not a grep.

`_spectral_collide_longitudinal!`'s box is **benign and was left alone**: the
closure only *reads* `luminosity` (through `typeof`), and the write at
`spectral.jl:1039` happens after `@sync` has joined. It is a type-instability
smell, not a race. Recording it rather than "fixing" it, because changing it
would be an unrelated refactor.

After both fixes, 0 of 15 fan-out sites carry a mutable shared box.

## 4. F1 — the aperture loss counter races under CPU threads

`aperture.jl` incremented a shared counter non-atomically while
`_run_logical_workers` fanned particles out over `Threads.@spawn`:

| workers | real losses | counter | error |
|---|---|---|---|
| 1 | 187 889 | 187 889 | 0 |
| 2 | 187 889 | 173 752 | −7.5% |
| 4 | 187 889 | 127 629 | −32% |
| 8 | 187 889 | **89 151** | **−53%** |

Nondeterministic across identical repeats at 8 workers (87 845 / 94 335 /
93 524 / 95 718 / 92 714 / 90 390). The per-particle `slots` were exact in every
run, which confirms the private-slot design and localises the bug to one cell.

Three compounding consequences:

1. `log=false` — counters only — is the default when no log path is requested,
   and is what a dynamic-aperture scan uses. There the counter is the *only*
   output.
2. `loss_summary` returns `unattributed = dead − logged`, documented to mean "a
   particle died where you put no collimator". Since `logged` is the racing
   quantity, **the diagnostic inverts**: an ordinary threaded run reports tens
   of thousands of phantom unattributed deaths and warns about them.
3. The per-collimator distribution — the primary collimation observable — was
   wrong aperture by aperture, not merely in total.

**Fixed** with a `Threads.SpinLock` around the increment: a lock rather than an
atomic because `counts` must stay a plain `Array` (`loss_counts`, `Adapt` and
the CUDA branch all depend on it) and Julia 1.12 needs an `AtomicMemory` for
atomic element access. It is entered once per *loss*, not per particle.
**Verified** exact and deterministic at 1/2/4/8 workers over six repeats.

## 5. F2, F3 — curved-frame kicks that are not gradients

Writing the kick sum as the analytic `f(w) = Σ(Kₙ + iKsₙ)wⁿ/n!`, `w = x + iy`,
`_lattice_kick` applies `dpx = −L(1+hx)·Re f`, `dpy = +L(1+hx)·Im f`, so by
Cauchy–Riemann

```
∂(dpx)/∂y − ∂(dpy)/∂x = −L·h·Im f .
```

The kick is a gradient — and the map symplectic — **iff `h·Im f ≡ 0`**, i.e. iff
the content is a pure *normal* dipole.

**A note on "skew dipole", and on how much F2 actually matters.** `ks[1]` is
the skew partner of the dipole order: index 1 is `n = 0`, so `kn[1] = K₀` is a
normal dipole (`B_y` on the midplane, `dpx = −L·K₀`, a horizontal bend) and
`ks[1] = Ks₀` is that magnet rolled 90° about `s` (`B_x` on the midplane,
`dpy = +L·Ks₀`, a *vertical* bend). It is a vertical bending field written as a
multipole coefficient instead of as rolled geometry.

It is reachable — `SBendSpec(…, ks=(0.05,))`, `MultipoleSpec(k0s=…)`,
`SolenoidSpec(k0s=…)` — and named in the metadata. But nobody would build a
vertical bend that way: `ref_tilt = pi/2` is the documented spelling, and
vertical steering is `VKickerSpec` or `k0sl`. **F2 is graded Major on the size
of the violation, not on the likelihood of the configuration**, and the two
should not be confused.

**F3 is the one with real exposure.** A solenoid with a superimposed
quadrupole is a detector-region final focus, which is exactly what §14 of the
solenoid note was written for, and *every* multipole order triggered it —
including a plain normal `k1`, the ordinary case. If only one of these two
findings is ever going to bite a production run, it is F3.

**F2**: `lattice_magnets.jl` tested `i >= 2`, exempting the whole dipole order.
True for the normal dipole (`Ψ₂ = K₀h − hK₀ = 0`), false for the skew one
(`Ψ₁ = Ks₀(1+hx)` seeds `Ψ₃ = h²Ks₀/(1+hx)`).

| `L=1, h=b0=0.05` | before | after |
|---|---|---|
| bend, no multipoles | 2.51e-10 | 2.51e-10 |
| **+ skew dipole** | **2.4990e-3** | **4.67e-11** |
| + skew quadrupole | 9.16e-11 | 9.16e-11 |
| + normal dipole error | 6.77e-11 | 6.77e-11 |
| straight frame + skew dipole | 2.66e-11 | 2.66e-11 |

Residual exactly linear in `ks[1]` and in `h`; predicted `L·h·Ks₀ = 2.5e-3`
against measured `2.4990e-3` — four significant figures.

**F3**: `solenoid.jl` passed `elem.h` into `_lattice_kick` with no routing at
all, so *every* order was affected.

| `L=1.3, ks=1.7, h=0.18` | before | after |
|---|---|---|
| pure solenoid | 4.38e-11 | 4.38e-11 |
| + normal dipole | 2.39e-11 | 2.39e-11 |
| **+ normal quadrupole** | **9.58e-4** | **5.13e-11** |
| **+ skew dipole** | **3.18e-2** | **5.38e-11** |

Refining `nst` did **not** remove it (16 → 64 → 256: 9.58e-4 → 9.62e-4 →
9.62e-4), which is what distinguishes a structural non-gradient from integrator
truncation.

### Could the fix be symplectic but WRONG?

Symplecticity plus unchanged controls does not exclude it: a different but
canonical map satisfies both. Since nothing external implements a curved
solenoid, the falsifying check is the **limit**.

**h → 0 must reproduce the straight map**, which PTC validates (solenoid + k1
at 4.7e-13). Convergence should be *first order* in h — a curved frame really
does differ from a straight one at O(h) — so what would indicate a wrong map is
convergence to a different limit, or none at all. Measured, `nst = 1024`:

| h | curved − straight (`k0s`) | ratio |
|---|---|---|
| 1e-3 | 8.7702e-4 | — |
| 1e-4 | 8.7703e-5 | 10.0 |
| 1e-5 | 8.7693e-6 | 10.0 |
| 1e-6 | 8.7599e-7 | 10.01 |

Clean O(h), and the same for `k1` and `k2` and for the F2 bend cases.

**ks → 0 with k1 must reproduce a curved-frame quadrupole**, which
`LatticeMagnet` builds through an entirely different path — exact curved drift
plus `_curved_kick`, no implicit midpoint anywhere. Two independent
implementations agree to **6.79e-10** at `nst = 1024`, converging at 16× per 4×
in `nst`. This is the strongest evidence available for a configuration with no
external reference.

**An anomaly that was chased rather than waved away.** At `nst = 64` the `k0s`
h-scan stalled at ratio 2.55 instead of 10, and the first explanation offered —
integrator truncation — was **wrong**: refining `nst` did not clear it as
`nst⁻²` (ratios 4.95, then 1.31). The correct explanation is that the residual
is the genuine O(h) physical difference, which no `nst` removes, and that the
*anomaly* was the Strang splitting error at coarse `nst` masking the h-scaling.
That predicts the scan recovers ratio 10 at fine `nst`, and it does — 10.0,
10.0, 10.01. The prediction was tested rather than assumed, which is the only
reason the first explanation's being wrong did not survive into this document.

Both limits are now permanent tests in `runtests.jl`.

**This was not a known limitation.** `docs/theory/solenoid.md` §14 covers
multipoles in a straight frame and claims "Symplectic at every step count"; §15
covers curvature for a pure solenoid. The cross-product is never discussed, yet
both keywords are accepted together and the element declares
`SymplecticityContract`.

Both fixed by routing through `_curved_potential_coeffs` via a shared predicate
`_needs_curved_potential`. `Solenoid` gained a `psi` table and `MC`/`NC` type
parameters mirroring `LatticeMagnet`; the kick is selected on `NC`, a type
parameter, so the straight path keeps its kernel unchanged.

## 6. F4 — two error messages interpolate nothing

`lattice_magnets.jl:746` and `:759` escaped the interpolation
(`"...got \$(repr(model))"`), printing the literal source text. Confirmed by
grep to be the only two occurrences in `src/`. Fixed.

## 7. Corrections to this audit's own analysis

Recorded beside the conclusions, as the Absolute Rules require.

1. **The first "finding" was mine, not the repository's.** The baseline run
   failed with `Package ForwardDiff not found`, which looked like a suite that
   could not run from a clean checkout. `Project.toml:34-40` declares it
   correctly under `[extras]`/`[targets]`; running `test/runtests.jl` directly
   under `--project=.` bypasses the test environment that `Pkg.test()` builds.
   No defect.
2. **I nearly misattributed F5 to my own fixes.** The threaded suite failed at
   `runtests.jl:2904` after my element-layer changes, and a single run on the
   stashed, pristine tree *passed* — which looked like a regression I had
   introduced. It was luck: six repeats on the pristine tree failed five times.
   A one-shot comparison against a nondeterministic bug is worthless, and I
   almost drew a conclusion from one.
3. **My first sweep for the closure bug was wrong in both directions.** A
   text-based scan reported six collisions that were not (variables assigned
   inside `for` bodies, which scope) and missed one that was. The `Core.Box`
   test replaced it.
4. **I asserted something about CUDA I had not checked.** The first pass said
   the closure-capture class "cannot occur there in the same way" while also
   listing every CUDA path as uninspected. Both cannot be true. Section 9a
   checks it; the claim happens to hold, but it was an assumption stated as a
   result, which is the thing the Absolute Rules forbid.
5. **The first pass shipped without running a single contract.** They were
   listed as "not run, therefore not claimed", which is honest but was the
   wrong trade: `PTCConsistencyContract` is the check that could have
   invalidated the F2/F3 magnet fix, it takes minutes, and a fix to magnet
   tracking should not be recorded before it has been run. It passes at
   4.995e-13.
6. **This document miscounted its own findings, and said so for months.** The
   headline read "Five confirmed defects" while the summary table below it
   listed seven — F7 and F4 were found and fixed after the opening paragraph
   was written, and the count was never brought forward. Corrected to seven on
   2026-08-03 by the part 2 session, which found it while curating the
   `docs/README.md` index. Recorded here rather than silently replaced,
   because a document whose headline disagrees with its own table is exactly
   the kind of internal inconsistency this protocol exists to catch, and it
   survived one full re-reading of this file.

## 8. Areas checked and found sound

- **`track/longitudinal.jl`** — all four conventions and every conversion
  independently derived; "exactly symplectic" verified as exact, not to order.
- **`_solenoid_map`** — closed form, edge conversion, Larmor half-angle; `ks=0`
  reduces to the exact drift.
- **`misalignment.jl`** — both composition orders match their docstrings;
  `_survey_frame` depends on `h` and never `b0`; the exit pair is built from
  exit geometry rather than by inverting the entrance.
- **`crab_cavity.jl`** — kick verified to be an exact gradient.
- **`rf_cavity.jl`** — `TIME_ENERGY` sandwich symplectic by construction;
  `strength = qV/(P₀c)` dimensionally correct; `phase = 0` gives no acceleration.
- **`Constants.jl`** — CODATA 2022 to the digit; four irrationals to 40 places.
- **`SpecialMath.jl`** — reflection, continued fraction, both asymptotics.
- **`beam_line.jl`** — dissolve/retain, provenance, selector grammar, girder path.
- **`BPMObserver.jl`** — rotation convention consistent with `_misalign_matrix`
  and AT; noise keyed by turn and `rng_id`.
- **`_run_logical_workers`, `_chunk_bounds`, `_threaded_indices_by_function`,
  `_pic_deposit_threaded!`, `_slice_transverse_moments`,
  `_spectral_collide_transverse!`** — checked for the F5 defect and clean.

## 9. Test, contract and validation report

RTX 4500 Ada (24 GB, driver 580.119.02), 128 CPUs, Julia 1.12.4.

- `Pkg.test()` **baseline, single-threaded, before any change: passed**, exit 0.
- `Pkg.test(julia_args=["--threads=8"])` **before the slicing fixes: FAILED** at
  `runtests.jl:2904-2912` — which is how F5 surfaced.
- `Pkg.test(julia_args=["--threads=8"])` **after all five fixes: passed**,
  exit 0, 101 testsets, no failures and no errors. Per-testset counts against
  the single-threaded baseline, showing the new assertions are live rather than
  merely added:

  | testset | baseline | final |
  |---|---|---|
  | Lattice magnets | 61 | 64 |
  | Solenoid in a curved frame | 25 | 35 |
  | Aperture loss record, counter and output | 20 | 21 |
  | Lost particles are dropped from every slicing method | 56 | 56 |

  The last row is the important one: the same 56 assertions, failing at 8
  threads before F5 and passing after.
- `validate_element_metadata()`, `validate_configuration_metadata()`: pass.
- `registry_snapshot_markdown() == docs/registry_snapshot.md`: true.
- Behavioural fingerprint, 40 element configurations × 3 phase-space points plus
  all 16 ordered convention pairs: after F2/F3 **only the two
  `sbend_skewdipole` rows moved**, bit-identical elsewhere; after F5/F6 the
  fingerprint was **byte-identical** again, confirming the slicing fixes do not
  touch the element layer.
- 0 of 15 `_run_logical_workers` sites carry a mutable shared box.

### Contracts — run in a second pass

The first pass of this audit did **not** run the contracts, which was the
largest hole in it. They were run afterwards; all pass.

| contract | result | residual |
|---|---|---|
| `PTCConsistencyContract` | **PASS** | 4.995e-13 over **55 cases**, worst 5.0e-13 |
| `ElementTrackingBackendConsistencyContract`, audit-touched line, CPU/CUDA | **PASS** | 1.998e-15 |
| `ElementTrackingBackendConsistencyContract`, reference line, CPU/CUDA | **PASS** | 1.665e-16 |
| `StrongStrongGaussianBackendConsistencyContract` | **PASS** | 1.794e-17 |
| `StrongStrongPICBackendConsistencyContract` CIC/wavefront | **PASS** | 5.220e-17 |
| `StrongStrongPICBackendConsistencyContract` TSC/sequential | **PASS** | 5.112e-17 |
| `SymplecticityContract` | **PASS** | — |
| `ElementParameterEffectivenessContract` | **PASS** | 238 parameters checked |
| `KnobEffectivenessContract` | **PASS** | 0.0 |
| `HighEnergyWeakStrongLimitContract` | **PASS** | — |
| `PublicConfigurationEffectivenessContract` | **PASS** | 0.0 |

**What the PTC pass does and does not establish.** It is a *regression* result,
not validation of the fixed paths. No PTC case exercises either configuration
F2 or F3 changed, and this was checked rather than assumed:

- `solenoid_k1_n8`/`_n32` are `SolenoidSpec(L=1.3, ks=0.35, k1=0.6, nst=…)` —
  **no `h`**, so a straight frame, which F3 does not touch.
- every `cfbend_*` case carries `k1` or `kn=(0.0, 0.6, …)` — normal orders only,
  never `ks[1]`.
- `quadrupole_skew` is `ks=(0.0, 0.9)`, a skew *quadrupole* in a straight frame.

Nor could such a case exist: PTC's `SOL5` carries no curvature, which
`solenoid.md` §15.5 already states. So the fixed configurations have **no
external reference**, and the evidence that they are now right is internal —
the derivation, the symplectic residual falling from 2.5e-3 / 9.6e-4 / 3.2e-2
to ~5e-11, and every control staying bit-identical. Per the protocol's
principle 13 the repository's own convention governs where the external codes
are silent, and here they are silent.

The `ElementTrackingBackendConsistencyContract` on a line built from exactly the
F2/F3 configurations is what establishes that the fix reaches the **device**:
`fusedTrack` is backend-agnostic and dispatches to the same `track_particle`, so
there is no second copy of the element physics to fix, and CPU and CUDA agree at
1.998e-15.

Still not run: every script in `validation/`, and any end-to-end luminosity
comparison for F6 — that fix rests on the `Core.Box` evidence, code inspection,
and the fact that the identical mechanism was empirically proven to corrupt in
F5.

### Validation scripts

- `validation/tracking_backend_consistency.jl` — **passed**. `AGENTS.md`
  requires this one after changing an element implementation, which F2/F3 did,
  and the first pass had not run it. CPU vs CUDA over 10 000 particles, 2 turns:
  `max_abs_error = 2.07e-17`, `global_rel_error = 9.42e-16`.
- `validation/symplecticity_validation.jl` — **passed** for every element:
  Linear6D 1.50e-13, CrabDispersion 1.32e-13, MomentumDispersion 1.81e-13,
  XYCoupling 1.32e-13, ThinCrabCavity 1.32e-13, ChromaticityKick 4.16e-13,
  ThinStrongBeam 7.91e-8, GaussianStrongBeam 4.24e-8, against tolerances of
  5e-7/5e-6. The Hirata boost pair reproduces `sec³`/`cos³` analytically
  (inverse residual 8.27e-19, determinant error 4.13e-13).

**The whole `validation/` tree was then run** — 42 scripts, one at a time, with
a 420 s cap each:

| result | count | note |
|---|---|---|
| PASS | 36 | including the one repaired below |
| TIMEOUT | 2 | `coherent_beam_beam_modes`, `slice_interpolation_emittance_growth` — long physics studies that exceeded **my** cap, not failures |
| skipped | 4 | benchmarks, skipped deliberately |
| **FAIL** | **1** | `strong_strong_spectral_comparison` — see F7 |

### F7 — a validation script that had not run since ~2026-07-30

`validation/strong_strong_spectral_comparison.jl:156` called
`Octopus._spectral_field`, which does not exist. The bare name is absent from
`src/` at the pre-audit commit `3fd3a52` too, so this predates the audit. The
script was last touched 2026-07-23; `ec86c34` *("isolate solver workspaces
across executions")*, part of the 2026-07-30 remediation, replaced the
allocating one-shot entry point with `_spectral_field_ws`, which takes a
caller-owned workspace. The script has been dead since.

**Fixed** by building the workspace outside the timed block — so `@allocated`
still measures the field solve and not the setup — and calling
`_spectral_field_ws`, which is what `_spectral_grid_ws`'s own comment
("internal one-off validation callers own this workspace directly") describes.
It now runs to completion and produces all five output files; the four solvers
agree on final luminosity to ~0.3% (Gaussian 1.046e30, PIC 1.045e30,
spectral-grid 1.043e30), with the coarse 48×48 grid-free variant 4.9% low.

**The meta-pattern, for the third time.** F1 was invisible because CI never ran
threaded; F5 because of the same; F7 because nothing runs `validation/` at all.
Every one of these is a check that existed and was not being executed. That is
a more productive thing to audit for in this repository than a missing check.

## 8a. Repo-wide census for the closure-capture class

The mechanical test that found F5 and F6 was applied to the **whole module**,
which covers every file including those never read by hand.

Scanned: **1 189 functions, 1 792 Octopus methods**. Methods containing a
`Core.Box`: **7**.

| method | file | verdict |
|---|---|---|
| `_spectral_collide_longitudinal!` | `spectral.jl:983` | benign — closure only *reads* `luminosity`; the write is after `@sync` |
| `_contract_default_initial_rep` | `Contracts.jl:919` | host-side contract setup, no fan-out |
| `read_beam_coordinates` | `Beam.jl:713` | file I/O, no fan-out |
| `validate(::KnobEffectivenessContract)` | `Contracts.jl:199` | host-side, no fan-out |
| `_initialize_moment_file!` | `BeamObservers.jl:827` | file I/O, no fan-out |
| two `#s107#` entries | `none:0` | `@generated` generator bodies, run at compile time |

None of the six non-spectral entries contains `_run_logical_workers`,
`Threads.@spawn`, `@async` or `@sync`. **The class is eliminated repository
wide**, and this is a whole-repository result rather than a sampled one.

It also confirms the earlier warning about method: the text sweep had flagged
`local_grid` in `_pic_deposit_threaded!` (`pic_cpu.jl:1217`) as a collision. It
is not — the reduction's `for local_grid in local_charge` is a loop variable,
and `for` scopes. The box census clears it correctly.

## 9a. The CUDA path

The first pass asserted that the F5/F6 bug class "cannot occur there in the same
way" without checking. That was unverified, and it is now checked.

**Found sound:**

- **Deposition is atomic.** Every charge-deposition write in `pic_cuda.jl`
  (CIC and TSC) and `spectral_cuda.jl` uses `CUDA.@atomic`, so the F1 class does
  not arise on device. The aperture's own device counter already used
  `CUDA.@atomic` and needed no change.
- **The closure-capture class is absent by construction.** The device path has
  no `_run_logical_workers` and no host closure carrying a mutable accumulator;
  per-thread state lives in registers and shared memory.
- **The two shared-memory reduction shapes are both correct, for different
  reasons, and the difference is deliberate.** `_cuda_pic_luminosity_overlap_partials_kernel!`
  (l. 4366) halves with `step = blockDim ÷ 2`, which **requires a power-of-two
  block** — at 100 threads element 25 would be orphaned. It is fed by
  `_cuda_pic_threads(:luminosity)`, and `interface.jl:112` and `:185` validate
  that family with `ispow2` at both construction and inheritance resolution,
  with an error message naming the tree reduction. The general moment reduction
  (l. 5514) instead uses the size-agnostic ceiling form `offset = (active+1)÷2`
  with thread `tid` absorbing element `tid+offset`; traced at 100 threads it
  steps 100 → 50 → 25 → 13 → 7 → 4 → 2 → 1 with nothing dropped.
- **Barriers.** All seven `sync_threads` sit outside their guarding `if`, as
  they must.
- **CPU/CUDA agreement** across the element layer and all three strong-strong
  solvers, at 1e-15 to 5e-17 (table above).

**Not inspected**, and so not claimed: the bulk of `pic_cuda.jl` (5807 lines) —
the wavefront scheduler, Green-function cache, workspace pooling and stream
management — `gaussian_pic_cuda.jl` (1154) and `spectral_cuda.jl` (760) beyond
their deposition kernels. The consistency contracts exercise these paths
end-to-end and pass, which is real evidence, but it is behavioural agreement on
one configuration each rather than a reading.

## 10. Performance

No hot path was slowed.

- F2/F3 move affected magnets onto the tabulated-potential kick, the route
  combined-function bends already took; unaffected magnets keep the closed form,
  selected by a type parameter that folds to one branch.
- F1 adds one uncontended spin-lock acquisition **per loss**, not per particle.
- F5/F6 are renames. They also *remove* a `Core.Box`, so if anything the
  affected loops get faster — untyped box loads become plain locals.

One observation, measured **not** at all and therefore a hypothesis:
`Patch._patch_map` (`patch.jl:103`) calls `_patch_rotation` inside the tracking
kernel, recomputing three `sincos` and two 3×3 products per particle per turn,
where `MisalignedElement` precomputes the equivalent at `compile_runtime`.

## 11. Remaining risks

1. **~80% of `src/` was not read**, including most of `pic_cuda.jl` and the
   beam-beam solver stack. Section 9a covers the CUDA concurrency primitives and
   the contracts cover CPU/GPU agreement end to end, but neither is a reading of
   the wavefront scheduler, the Green cache or the workspace pooling.
1a. **The F2/F3 configurations have no external reference** and cannot get one
   from PTC. If a curved solenoid with superimposed multipoles, or a bend with a
   skew dipole, ever matters in production, it needs a reference from somewhere
   else — a field-map integrator, or an independent implementation.
2. **Threading is under-tested, not just untested.** F1 and F5 were both
   invisible to a single-threaded suite, and F5 was found only as a side effect
   of fixing F1. CI now runs `--threads=4`, but the GPU paths and the remaining
   solver stack have never been run under a concurrency-aware test.
3. **The `h ≠ 0` × transverse-field cross-product should be swept generally**
   against the `Im f ≡ 0` condition. F2 and F3 were the same bug in two files.
4. **Contracts and `validation/` were not run** — the thinnest evidence here.
5. **`_SOL_CURVED_ORDER` is not a public knob.** A production curved solenoid
   with strong superimposed multipoles would need a convergence study and a
   declared parameter.
6. **BPM noise repeats within a turn** — `bpm_reading` keys the RNG on
   `(turn, rng_id)`, so one observer placed twice draws the same noise at both.
   Unverified; recorded rather than fixed.

## 12. Handoff — where the next session starts

This audit ran out of **context window**, not out of access or permission.
Every file is readable; what does not fit is ~68 000 lines of source plus the
reasoning about them in one session's working memory. Reading a 5 800-line file
spends capacity that is then unavailable for analysing it. Full line-by-line
coverage is therefore reachable, but across several sessions, each scoped to one
subsystem. This section is what makes that resumable.

### Done — do not redo

| area | state |
|---|---|
| Element layer (`src/elements/`) | **read in full**, except `strong_beam.jl` |
| `track/longitudinal.jl`, `fused_track.jl`, `Track.jl`, `radiation_track.jl` | read in full |
| `math/counter_rng.jl`, `math/SpecialMath.jl`, `constants/` | read in full, Philox checked against Random123 |
| `tasks/BPMObserver.jl` | read in full |
| `beam/Beam.jl` | read to l. 370 and `beam_statistics` |
| Closure-capture (`Core.Box`) class | **100% of the module swept**, 7 boxes, all cleared |
| Contracts | **all 11 run and passing** |
| `validation/` | **42 scripts run**; 36 pass, 1 fixed (F7), 2 over a 420 s cap, 4 benchmarks skipped |
| Public surface | all 30 kinds: `element_help` by symbol and type, `parameter_schema`, `construction_help`, example-compile — 0 failures |

### Next, in priority order

1. **`src/tasks/strongstrong/interface.jl` (2093)** — the public configuration
   surface for every solver, and the place `AGENTS.md`'s "no silently ignored
   non-default request" rule is most likely to be violated. Highest value per
   line read.
2. **`src/contracts/Contracts.jl` (1963)** — the contracts are the evidence
   everything else leans on, and nothing audits *them*. A contract that passes
   vacuously is worse than no contract.
3. **`src/elements/strong_beam.jl` (1547)** — the only element file unread, and
   the beam-beam kick is the physics this code exists for.
4. **`src/tasks/BeamObservers.jl` (1446)** — the moment reductions that produce
   every published number. Note the shifted-variance work of 2026-07-30 lives
   here.
5. **`src/knobs/Knobs.jl` (896) + `symbolic.jl` (285)** — a public subsystem
   with a lock and an epoch counter; check the epoch/recompile handshake.
6. **`src/tasks/strongstrong/pic_cuda.jl` (5807)** — largest, but the
   consistency contracts already exercise it end to end and the concurrency
   primitives are checked (§9a). Read the wavefront scheduler and Green cache;
   the kernels are lower risk.
7. Remaining: `Knowledge.jl` (read to l. 130), `Registry.jl`, `Policies.jl`
   (fan-out read), `Tasks.jl` (read to l. 140), `gaussian_pic*.jl`,
   `spectral*.jl`, `pic_cpu.jl`, and `test/runtests.jl` itself.

### Techniques that actually found things — use these first

Four of the seven findings came from **mechanical sweeps and execution**, not
from reading:

- **`Core.Box` census over lowered code** found F5 and F6. A text/grep sweep for
  the same thing gave six false positives and missed a real case. Always use the
  lowered-code test.
- **Running the suite with `--threads`** found F1 and exposed F5. Anything
  shared between workers is invisible at one thread, because
  `_run_logical_workers` has a `nworkers == 1` fast path that never spawns.
- **Running `validation/`** found F7. Nothing in CI runs that tree.
- **Limit tests** (`h → 0`, `k → 0`) are what distinguishes *symplectic* from
  *correct* where no external reference exists. Symplecticity alone cannot.

And the meta-pattern, four for four: **F1, F5, F7 were all checks that existed,
were correct, and were never executed.** Audit for unexecuted checks before
auditing for missing ones.

### Open, not started

- The two `validation/` scripts that exceeded the 420 s cap, re-run with a
  longer one.
- `AbstractGPUExecutionPolicy` and `ElementParameterEffectivenessContract` are
  the only two public registry objects without docstrings, against `AGENTS.md`'s
  "public architecture APIs need docstrings".
- The `beam_statistics` covariance loop computes all 36 entries of a symmetric
  matrix (15 redundant `O(N)` passes, per turn). Unmeasured, so a hypothesis.
- `Patch._patch_map` recomputes its rotation per particle per turn where
  `MisalignedElement` precomputes. Unmeasured.

## 13. Change log

| file | change | finding |
|---|---|---|
| `src/tasks/strongstrong/slicing.jl` | rename the closure's shared accumulator to `chunk_counts` | F5 |
| `src/tasks/strongstrong/gaussian.jl` | rename the closure's shared accumulator to `chunk_lum` | F6 |
| `src/elements/aperture.jl` | spin-lock around the CPU loss counter | F1 |
| `.github/workflows/ci.yml` | run tests with `--threads=4` | F1 |
| `test/runtests.jl` | note + single-thread skip marker on the counter invariant | F1 |
| `src/elements/lattice_magnets.jl` | `_needs_curved_potential`; `combined` uses it; corrected the `_lattice_kick` derivation comment | F2 |
| `test/runtests.jl` | three curved-frame bend cases in the symplecticity sweep | F2 |
| `src/elements/solenoid.jl` | `psi` table, `MC`/`NC` type parameters, `_sol_kick` | F3 |
| `test/runtests.jl` | symplecticity across five multipole kinds × two `nst`, replacing an `isfinite` check | F3 |
| `src/elements/lattice_magnets.jl` | two error messages un-escaped | F4 |

---

<a id="part-2"></a>

# Comprehensive Audit — 2026-08-03, part 2

> ## Start here
>
> **Do not read this front to back, and do not read part 1 front to back.**
> Between them they are ~1,600 lines, about what `pic_cpu.jl` costs to read —
> and that context is what the next session actually needs.
>
> | read | why |
> |---|---|
> | **§14** of this file | the handoff: what is done, what is next, and what the solver-option contract does *not* prove |
> | **§2** of this file | the coverage ledger, so you do not re-read what is already covered |
> | **§3 of [part 1](#part-1)** | the Julia closure-capture trap. Load-bearing for the next file: `pic_cpu.jl` has three `_run_logical_workers` sites. The census is clean today, so this is about reading those loops correctly and not reintroducing it — and about the fact that a text sweep gave six false positives and missed a real case, so the check must be on lowered code |
>
> Skip until the session that needs them: part 1 §4–6 (aperture loss counter,
> the curved-frame `Im f ≡ 0` gradient condition) are element-layer and closed;
> part 1 §9a (CUDA concurrency primitives) belongs to the eventual
> `pic_cuda.jl` session.
>
> §9 and §15.7 are the corrected wrong turns. They are worth more than the
> conclusions if you are deciding how much to trust a measurement here.

A second pass against the protocol in
[`docs/comprehensive_audit.md`](../comprehensive_audit.md), resuming from the
handoff in [part 1](#part-1) §12 and following its
priority order. **Thirteen confirmed defects, all fixed** — five in the first
pass over the declared scope, and eight more surfaced by building the
solver-option contract the first pass had identified as missing (§15).

The theme differs from part 1. That session found races — code that was wrong
whenever more than one thread ran. This one found **configuration that was
accepted, reported as active, and never used**: a solver whose CUDA launch
configuration was silently discarded while `configuration_report` claimed it
resolved, and a contract whose declared tolerances were overridden by its own
default. Nothing here changes a physics result. What it changes is whether the
repository's answer to "is this setting in effect?" can be trusted — which is
the question `AGENTS.md` cares most about, and the one part 1 did not ask.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S1 | **Moderate** | `GaussianPICPoissonSolver` silently discarded every CUDA PIC launch configuration *and* the policy thread count | fixed, verified |
| S2 | **Moderate** | a non-default CUDA-only Gaussian solver option was inactive on CPU with no signal on any surface | fixed, verified |
| S3 | Minor | `SymplecticityContract` and `validation/symplecticity_validation.jl` never enforced their four tightest declared tolerances | fixed, verified |
| S4 | Minor | the documented symplecticity of `:chromatic` and `:exact` virtual drifts was untested | fixed, verified |
| S5 | Minor (performance) | `beam_statistics` computed all 36 entries of a symmetric covariance | fixed, measured, bit-identical |
| S6 | **Major** | `UndefVarError: PI` in the **default** integrated Green kernel, on any node lying exactly on an axis | fixed, verified |
| S7 | Moderate | the `:solver_runtime` receipt was PIC-only, leaving 59 of 88 declared solver options with no observable consumer | fixed, verified |
| S8 | Moderate | `GaussianPICPoissonSolver` silently ignored `grid_extent` / `grid_extent_sigma` | fixed (now rejects), verified |
| S9 | Minor | `collide!` was ambiguous for `GaussianPICPoissonSolver` with a `TrackingContext` | fixed, verified |
| S10 | Minor | `loss_summary(rep, task)` was ambiguous — a public API `MethodError` | fixed, verified |
| S11 | Minor | `green_cache` and the spectral `method` were declared pure execution/performance but change results | fixed, measured |
| S12 | Moderate | the CUDA `GaussianPIC` route emitted no `:cuda_pic_algorithm` receipt, the consumer its five algorithm options declare | fixed, verified (§15.9) |
| S13 | Moderate | the CUDA `GaussianPIC` route reads `batch_mode` and `cuda_indexed_wavefront` only; `cuda_async`, `cuda_batch_fft` and `cuda_wavefront_fft` were accepted and dropped | fixed (now rejects), verified (§15.9) |

**The pattern worth taking away.** Part 1's lesson was "audit for checks that
exist and are never executed." This pass suggests the sibling rule: **audit for
values that are declared and never read.** S1, S2 and S3 are all the same
shape — a value stored, documented, and reported, with nothing downstream
consuming it. S1 is the sharpest case, because the introspection surface built
to answer exactly this question gave the wrong answer:
`configuration_report` reported `cuda_pic_kick_threads: requested=64,
resolved=64, status=resolved` while the runtime used 256.

`AGENTS.md` already states the rule — "Storing, documenting, or returning a
value from a configuration helper is not evidence that it is applied" — and
`ElementParameterEffectivenessContract` enforces it mechanically for *element*
parameters. No equivalent sweep exists for *solver* options, and S1 and S2 both
live in that gap.

## 2. Declared scope and coverage ledger

Scope was declared before reading anything in depth, following the part 1
handoff's priority order. `src/` is 31,005 lines.

### Read in full, line by line — 5,603 lines

| file | lines | handoff rank |
|---|---|---|
| `src/tasks/strongstrong/interface.jl` | 2,093 | 1 |
| `src/contracts/Contracts.jl` | 1,963 | 2 |
| `src/elements/strong_beam.jl` | 1,547 | 3 |

### Read in part — roughly 900 lines, in pursuit of specific questions

- `src/track/strong_beam_track.jl` l. 1–120 — the two `_run_logical_workers`
  luminosity accumulators, checked against the part 1 closure-capture class.
- `src/tasks/BeamObservers.jl` l. 700–1030 — observer output paths, the moment
  row builders, `_moment_live_flags`, `_scheduled_turns`.
- `src/knobs/Knobs.jl` — the epoch/lock handshake only (l. 112–166, 490–545).
- `src/beam/Beam.jl` — `beam_statistics`, `_live_stat_flags`,
  `_resolve_execution_policy`.
- `src/tasks/strongstrong/gaussian_pic.jl` l. 20–155; `pic_cpu.jl` l. 278–318;
  `pic_cuda.jl` l. 5030–5100; `policies/Policies.jl` l. 55–170.
- `docs/theory/beam_beam_longitudinal_kick.md` §7.1 in full.

### Whole-repository mechanical sweep

`Core.Box` census over lowered code: **3,112 functions/types, 2,110 Octopus
methods**. This covers every file including those never read by hand, for one
property only.

### Not inspected at all

`pic_cuda.jl` (5,807), `pic_cpu.jl` (1,715), `gaussian_pic_cuda.jl` (1,154),
`gaussian_pic.jl` bulk, `spectral.jl` (1,045), `spectral_cuda.jl` (760),
`Knowledge.jl` (885), `Tasks.jl` (753), `slicing.jl` (704), `Registry.jl` (209),
and `src/knobs/symbolic.jl` (285) — the one declared scope item **not reached**.
`test/runtests.jl` was run and edited, not read. `validation/` and `examples/`
were run, not read.

### Honest total

~6,500 of 31,005 lines (21%) read line by line this session. Part 1 reached
~7,800, on a disjoint file set — it explicitly listed `strong_beam.jl` as the
only unread element file, and never opened `interface.jl` or `Contracts.jl`.
Across the two sessions roughly **46% of `src/` has now been read line by
line**, with the beam-beam solver stack (`pic_cuda`, `pic_cpu`, `spectral`,
`gaussian_pic*`, ~11,300 lines) still the dominant gap.

### Equations independently derived

1. **Chromatic virtual drift**, against theory note §7.1, with `q = px²+py²`
   and `P = 1+pz`: `Φ = √(1 − q/2P²) − 1`, `Ψ = √(1 + q/2P²) − 1`, and all six
   components of both the forward and inverse maps. Exact match, including the
   factor of one half inside the radical, which comes from `dP²/dτ = −q/2` and
   is the one term that looks wrong until the derivation is read.
2. **Hirata paraxial drift**: `dP/dτ = −(∂S/∂z)H = −q/4` gives
   `pz −= 0.25(px²+py²)`, and `∂H/∂pz = 0` gives `z` unchanged — which is what
   the docstring's "no `pz` dependence, hence no path lengthening" means. It
   does *not* mean `pz` is unchanged, and the code is right.
3. **Exact-Hamiltonian drift**: the implicit solve `z₂ = (z + rr·z*)/(1 + rr)`
   with `rr = H/2p_s` verified to reproduce `S = (z_out − z*)/2`
   self-consistently — `z − 2rr·S = z₂` algebraically.
4. **Bassetti–Erskine kick**, verified against brute-force numerical
   integration (§6).
5. **`_equal_width_slices`** weights sum to exactly 1 for both odd and even
   `ns` — the telescoping `erf` sum reduces to `erf(nw·ns/2)/sumw`.
6. **`_equal_area_slices`** even-`ns` nodes are the equal-charge bin medians,
   `√2·erfinv((2i−1)/ns)`.
7. **`beam_statistics` covariance symmetry** is bit-exact, not approximate:
   `_covariance` sums `(a[k]−ma)(b[k]−mb)` in particle order and IEEE
   multiplication commutes (§8, verified by measurement).

## 3. S1 — a solver that composed instead of subtyping, and lost its configuration

`_with_solver_execution_configuration` (`interface.jl:199` before the fix)
installed the resolved CUDA PIC launch configuration only when
`solver isa PICPoissonSolver`. `GaussianPICPoissonSolver` **composes** a
`PICPoissonSolver` in its `pic` field (`gaussian_pic.jl:80`) rather than
subtyping it, so the scoped value was never installed and `_cuda_pic_threads`
(`interface.jl:216`) returned its hardcoded fallback:

```julia
config isa ResolvedCUDAPICLaunchConfig || return 256
```

`gaussian_pic_cuda.jl` calls that function at four sites (l. 690, 1002, 1013,
1026), and its routes reach further `pic_cuda.jl` kernels that call it too.

### What was claimed

- `gaussian_pic.jl:38-41`: "all PIC keywords (`grid`, ..., the CUDA execution
  options, ...) are forwarded to it unchanged".
- `CUDAPICLaunchConfig` docstring, `interface.jl:83`: "`nothing` inherits the
  thread count from `CUDAExecutionPolicy`".
- `configuration_report` reported the override as resolved.

All three were false for this solver.

### Evidence

Controlled pair, identical `CUDAPICLaunchConfig(kick_threads=64,
deposition_threads=64, field_threads=64)` under
`CUDAExecutionPolicy(threads=128)`:

| solver | before | after |
|---|---|---|
| `PICPoissonSolver` | (64, 64, 64) | (64, 64, 64) |
| `GaussianPICPoissonSolver` | **(256, 256, 256)** | (64, 64, 64) |
| `PICPoissonSolver`, no config | 128 — the policy | 128 |
| `GaussianPICPoissonSolver`, no config | **256** | 128 — the policy |

End to end, one turn, 512 particles per beam, counting `:cuda_pic_launch`
execution receipts:

| solver | before | after |
|---|---|---|
| PIC | 51 receipts, 7 families, threads {64, 128} | 51, unchanged |
| GaussianPIC | **0 receipts** | **56 receipts, 7 families, threads {64, 128}** |

The post-fix family list includes `:luminosity`, which is the part that matters
beyond tuning: `_resolve_cuda_pic_configuration` validates that the luminosity
thread count is a power of two (the overlap kernel uses a tree reduction that
orphans elements otherwise, per part 1 §9a) and that no family exceeds the
device maximum. Neither validation had ever run for this solver.

And `configuration_report(gpic; backend=CUDABackend)` reported
`cuda_pic_kick_threads: requested=64 resolved=64 status=resolved` — the
introspection surface asserting a value the runtime did not use.

**No physics impact.** Thread count is launch geometry; the CPU/CUDA
consistency contracts pass identically before and after. The impact is a public
performance-tuning surface that did nothing, an introspection surface that
misreported, and two safety validations that never executed.

**Fixed** by replacing the `isa` test with dispatch — `_pic_launch_solver`, with
a generic `nothing` fallback and a `PICPoissonSolver` method in `interface.jl`,
and the composing method beside the composing type at `gaussian_pic.jl:150`.
The same helper now drives the preflight, so composition is handled in one place
rather than at each `isa` site.

## 4. S2 — inactive on CPU, and silent on every surface

Two surfaces failed the same way for non-PIC solvers.

1. `configuration_report(::GaussianPoissonSolver)` (`interface.jl:1378` before
   the fix) accepted `policy` and `backend` keywords and used neither. So
   `batch_mode` — declared `supported_backends=(CUDABackend,)`, consumed at
   `pic_cuda.jl:5041` to choose the wavefront or sequential CUDA route, and
   genuinely inert on the CPU path — was reported `:resolved` on CPU. The PIC
   report already handled this correctly, so the two disagreed about the same
   option role.
2. `_preflight_solver_configurations!` (`interface.jl:1763` before the fix)
   opened with `solver isa PICPoissonSolver || continue`, so no non-PIC solver
   was ever checked for inactive CUDA-only options.

Net effect: `GaussianPoissonSolver(batch_mode=:sequential)` on CPU storage was
ignored, reported as active, and warned about nowhere.

### Evidence

`batch_mode=:sequential`, CPU backend:

| solver | report status before | after |
|---|---|---|
| PIC | `inactive_backend` | `inactive_backend` |
| Gaussian | **`resolved`** | `inactive_backend` |

Preflight warning, all three runs completing normally:

| case | before | after |
|---|---|---|
| PIC + `CUDAPICLaunchConfig` | WARNS | WARNS |
| GaussianPIC + `CUDAPICLaunchConfig` | **SILENT** | WARNS |
| Gaussian `batch_mode=:sequential` | **SILENT** | WARNS |

`SpectralPoissonSolver` declares no CUDA-only options, so generalizing the
preflight cannot produce a spurious warning there — checked before making the
change rather than after.

## 5. S3 — declared tolerances that never bound, in two files

`Contracts.jl:1193` and `validation/symplecticity_validation.jl:153` both
compute

```julia
tolerance = max(case.tolerance, default_tolerance)
```

which is a coherent design — `default_tolerance` is a floor, so raising it
relaxes every case at once. But both files shipped `default_tolerance = 5.0e-7`
while four cases declare `5.0e-8`, so `max` took the looser value and those four
declarations were decorative. Measured residuals for them are ~1.3–1.8e-13, so
nothing was failing; the point is that the number in the source was not the
number being enforced.

**Fixed** by lowering the floor in both files to `5.0e-8`, the tightest declared
value. Every per-case tolerance now binds exactly and `default_tolerance` keeps
its meaning. This is the same defect in two files, which is the shape part 1
found twice (F2/F3) and flagged as worth sweeping for.

| case | declared | enforced before | enforced after | residual |
|---|---|---|---|---|
| Linear6D | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.502e-13 |
| CrabDispersion | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.319e-13 |
| MomentumDispersion | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.807e-13 |
| XYCoupling | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.319e-13 |
| ThinCrabCavity | 5.0e-7 | 5.0e-7 | 5.0e-7 | 1.319e-13 |
| ChromaticityKick | 5.0e-6 | 5.0e-6 | 5.0e-6 | 4.163e-13 |
| ThinStrongBeam | 5.0e-7 | 5.0e-7 | 5.0e-7 | 7.908e-8 |
| GaussianStrongBeam | 5.0e-7 | 5.0e-7 | 5.0e-7 | 4.240e-8 |

## 6. S4 — two of three virtual drifts were symplectic by assertion only

`ThinStrongBeamSpec`'s docstring (`strong_beam.jl:135`) states: "All three are
exact flows of their own Hamiltonian, so all three are symplectic and telescope
exactly across slices." Both `SymplecticityContract` and
`validation/symplecticity_validation.jl` built their `ThinStrongBeam` case with
`virtual_drift=:hirata` and nothing else. `:chromatic` and `:exact` were covered
only by a CPU/CUDA parity test (`runtests.jl:5440`), which compares the map to
itself on another backend and cannot detect a non-symplectic map.

This is the configuration part 1 described for F2/F3 — "tests checked
`isfinite` and `isbits` but never symplecticity."

**Measured.** The step scan is what makes this a proof rather than a threshold:
a symplectic map's finite-difference residual is truncation error and falls as
`step²`, while a structurally non-symplectic map's residual is flat. The two
`UnsafeVirtualDrift` models are the negative control — documented as
non-symplectic, so a test that cannot separate them from the named three proves
nothing.

| drift | claimed | residual @ step 3e-7 | @ step 3e-6 | ratio | GaussianStrongBeam ns=5 |
|---|---|---|---|---|---|
| `:hirata` | symplectic | 7.908e-8 | 7.908e-6 | **100.0** | 4.240e-8 |
| `:chromatic` | symplectic | 7.908e-8 | 7.908e-6 | **100.0** | 4.240e-8 |
| `:exact` | symplectic | 7.908e-8 | 7.908e-6 | **100.0** | 4.240e-8 |
| `UnsafeVirtualDrift(:chromatic_frozen_energy)` | NOT | 2.047e-5 | 2.047e-5 | **1.0** | 1.476e-5 |
| `UnsafeVirtualDrift(:paraxial_frozen_longitudinal)` | NOT | 2.047e-5 | 2.047e-5 | **1.0** | 1.476e-5 |

Ratio 100 is exactly `(10)²`. The claim holds for all three, and the identical
residuals show the shared Gaussian kick sets the truncation floor — the drift
choice contributes nothing to it.

**Fixed** by adding `ThinStrongBeamChromatic` and `ThinStrongBeamExact` to
`_symplecticity_contract_cases()`, and a `runtests.jl` testset that asserts both
the `step²` scaling for the named three and the flat residual for the unsafe
two. The negative control is the part that gives the test discriminating power.

## 7. S5 — a symmetric matrix computed twice, measured rather than assumed

Part 1's handoff recorded, under "Open, not started": "The `beam_statistics`
covariance loop computes all 36 entries of a symmetric matrix (15 redundant
`O(N)` passes, per turn). Unmeasured, so a hypothesis." `Beam.jl:642` ran
`for i in 1:6, j in 1:6`.

**Measured**, minimum of seven runs, CPU:

| npart | `beam_statistics` before | after | `diagonal_fourth=true` before | after |
|---|---|---|---|---|
| 100 k | 2.288 ms | **1.385 ms** | 5.180 ms | **4.085 ms** |
| 1 M | 24.94 ms | **15.66 ms** | 55.36 ms | **42.87 ms** |

39.8% off the bare call and 22.6% off the `diagonal_fourth=true` form at 1 M
particles. The latter is the one that matters: `BeamMomentObserver.observe!` and
`JLD2BeamMomentObserver.observe!` call exactly that on every scheduled turn.

**The result is bit-identical, and that was verified rather than argued.**
`_covariance` sums `(a[k]−ma)(b[k]−mb)` over particles in index order; IEEE
multiplication commutes, so `cov[i,j]` and `cov[j,i]` were already equal to the
last bit. Checked directly: `cov[i,j] === cov[j,i]` bitwise `true` for all 36
entries at both particle counts, and the post-change library output compared
`===` against a locally computed 36-pass reference — identical at every entry.

## 8. Areas checked and found sound

- **The Bassetti–Erskine beam-beam kick, verified against an independent
  algorithm.** `gaussian_beambeam_kick` was compared to brute-force numerical
  integration of

      Kx = 2x ∫₀^∞ exp(−x²/(2σx²+t) − y²/(2σy²+t)) (2σx²+t)^{−3/2}(2σy²+t)^{−1/2} dt

  which shares no code with the Faddeeva closed form, the near-round `η` series,
  or the quintic blend between them. The reference self-checks against the exact
  round-beam form `2x(1−e^{−r²/2σ²})/r²` at 1.03e-14, which is its own accuracy
  floor. Sixteen field points per aspect ratio, `|x| ≤ 2.5σx`, `|y| ≤ 2.5σy`:

  | σx/σy | η | branch | max rel err Kx | max rel err Ky |
  |---|---|---|---|---|
  | 1.0 | 0 | round | 4.83e-14 | 4.83e-14 |
  | 1.0000001 | 1e-7 | series | 4.53e-14 | 4.04e-14 |
  | 1.0002 | 2.0e-4 | series | 4.32e-14 | 3.04e-14 |
  | 1.00024 | 2.4e-4 | **blend** | 2.32e-14 | 1.74e-14 |
  | 1.00025 | 2.5e-4 | **blend** | 2.69e-14 | 3.66e-14 |
  | 1.0003 | 3.0e-4 | **blend** | 4.63e-14 | 5.18e-14 |
  | 1.01 | 9.95e-3 | faddeeva | 6.58e-14 | 5.01e-14 |
  | 2.0 | 0.600 | faddeeva | 2.83e-14 | 3.57e-14 |
  | 11.0 | 0.984 | faddeeva | 4.62e-13 | 1.36e-13 |
  | 25.0 | 0.997 | faddeeva | 3.10e-10 | 4.77e-11 |

  All four branches agree at the reference's own floor. The blend window is
  narrow (`η ∈ [1.24e-4, 2.48e-4]` for `Float64`) and was targeted deliberately
  after the first sweep stepped over it — a sweep that misses the branch it was
  written to test is worth nothing. The growth at 25:1 is the reference
  integrand sharpening, not the evaluator.

- **The closure-capture class remains eliminated.** `Core.Box` census over
  lowered code, 2,110 Octopus methods, 8 boxes. Only one sits at a fan-out site:
  `_spectral_collide_longitudinal!` (`spectral.jl:983`), which part 1 already
  cleared as benign — the closure only reads `luminosity`, and the write happens
  after `@sync` has joined. The other seven have no `_run_logical_workers`,
  `Threads.@spawn`, `@async` or `@sync` anywhere in them.

  One entry is new relative to part 1's list of seven: `GaussianStrongBeam`'s
  constructor (`strong_beam.jl:349`), where `hoff_tuple`/`voff_tuple`/
  `pxoff_tuple`/`pyoff_tuple` are reassigned inside an `if` and captured by
  `ntuple` closures. It is host-side element construction with no fan-out, and
  the `ntuple` reads the old value before the assignment completes, so it is a
  type-instability smell rather than a race — the same standing as the spectral
  entry. It appears now because part 1's census scanned functions only; adding
  type constructors takes the method count from 1,792 to 2,110.

- **The knob epoch/recompile handshake.** Every mutation of `_KNOB_EPOCH`
  (`Knobs.jl:120`) happens under `_KNOB_LOCK`. `knob_epoch()` reads without the
  lock, which is a staleness window rather than a race — and the cache
  handshake in `_strong_strong_runtime_blocks` (`interface.jl:2003`) reads the
  epoch *before* building the runtime blocks and stores that value, so a knob
  changed during a build produces a mismatch and a rebuild at the next
  `execute!` rather than a lost update. The conservative ordering is the correct
  one and it is the one implemented.

- **`strong_beam_track.jl` worker accumulators.** Both
  `_track_thin_strong_beam!` and `_track_gaussian_strong_beam!` assign `value`
  only inside the `do` block, and `local_lum` inside a `for` body, which scopes.
  Neither is the part 1 F5/F6 shape. Confirmed by the census.

- **PTC contract coverage is complete today.** `_ptc_reference_specs()` declares
  55 cases; the committed `ptc_madx_5.03.06.tsv` contains exactly 55; the set
  difference is empty in both directions. No spec goes untested and no table row
  is silently dropped.

- **`_equal_width_slices` and `_equal_area_slices`** normalize and place nodes
  correctly for both odd and even `ns` (derivations in §2).

## 9. Corrections to this audit's own analysis

Recorded beside the conclusions, as the Absolute Rules require.

1. **The fingerprint diff first looked like my own fix had moved the CUDA PIC
   path.** Comparing before and after S1/S2/S3 showed 147 of 1,520 rows
   differing, all in `cuda/{pic,pic_cache,gpic,gpic_cache,spectral}`. That reads
   as a regression. Re-running the *unchanged* post-fix code produced 154
   differing rows in exactly the same five cases at the same magnitudes: the
   CUDA grid solvers are not bitwise reproducible run to run, and the
   before/after difference was entirely inside that noise. Everything
   deterministic — all seven CPU solver cases, both CUDA soft-Gaussian cases,
   all eight element configurations — was byte-identical throughout. A one-shot
   fingerprint comparison against a nondeterministic path proves nothing, which
   is the same lesson part 1 recorded as its correction #2. I repeated it.

2. **I nearly reported the "CPU/CUDA bit-parity" claims as a documentation
   defect.** Having measured that *no* solver is bitwise CPU/CUDA-identical
   (every one differs; max_abs 1.0e-16 to 2.7e-16), I was ready to call the four
   `src/` claims false. Checking the repository's own usage first showed
   "bit-parity" is a house term here, always quoted with its residual —
   `strong_strong_gaussian_pic_optimization_history.md:43` "bit-parity
   (~1e-15)", `:120` "1.2e-15 (lum) / 1.2e-12 (coords)", `todo.md:735` "lum
   ~2e-16, coords ~5e-13". My measured coordinate agreement, max_rel 2.4e-13 to
   2.7e-12, *reproduces* those recorded figures. Protocol principle 13: the
   repository's established convention wins. Not a finding, and the docstrings
   were left alone.

3. **The `0.5` in the chromatic drift looked like a factor-of-two error.**
   `phi = sqrt(1 - 0.5*(px*px + py*py)/((1+pz)*(1+pz))) - 1` does not match
   `p_s/(1+p_z)`, and my first reading was that it should have been the exact
   square root. Reading theory note §7.1 rather than guessing showed it is
   `Φ = √(1 − q/2P²) − 1` exactly, the one half coming from `dP²/dτ = −q/2`. The
   code is right and the derivation is where that is visible.

## 10. Test, contract and validation report

RTX 4500 Ada (24 GB, driver 580.119.02), 128 CPUs, Julia 1.12.4.

- `Pkg.test(julia_args=["--threads=8"])` **baseline, before any change:
  passed**, exit 0, 101 testsets.
- `Pkg.test(julia_args=["--threads=8"])` **after all fixes: passed**, exit 0,
  **102 testsets**, no failures and no errors. The new testset, "Virtual drifts:
  the named three are symplectic, the unsafe two are not", contributes 10
  assertions.
- Behavioural fingerprint, 7 solvers × 2 backends × 2 turns plus 8 element
  configurations, 1,520 full-precision rows: every deterministic case
  byte-identical to the pre-audit baseline. The five CUDA grid cases differ
  inside their measured run-to-run band (§9.1).

### Contracts — all 11 run, all passed

| contract | result | residual |
|---|---|---|
| `PTCConsistencyContract` | **PASS** | 4.995e-13 over 55 cases |
| `SymplecticityContract` (now 10 cases) | **PASS** | worst ratio 0.158 |
| `ElementParameterEffectivenessContract` | **PASS** | 238 parameters checked |
| `KnobEffectivenessContract` | **PASS** | 0.0 |
| `PublicConfigurationEffectivenessContract` | **PASS** | 0.0 |
| `HighEnergyWeakStrongLimitContract` | **PASS** | 3.010e-3 |
| `ElementTrackingBackendConsistencyContract`, audit line, CPU/CUDA | **PASS** | 8.327e-17 |
| `ElementTrackingBackendConsistencyContract`, reference line, CPU/CUDA | **PASS** | 0.0 |
| `StrongStrongGaussianBackendConsistencyContract` | **PASS** | 1.527e-17 |
| `StrongStrongPICBackendConsistencyContract` CIC/wavefront | **PASS** | 5.490e-17 |
| `StrongStrongPICBackendConsistencyContract` TSC/sequential | **PASS** | 5.952e-17 |

`PTCConsistencyContract` at 4.995e-13 is identical to part 1's figure, which is
the evidence that nothing in the magnet layer moved.

### Validation scripts

`AGENTS.md` requires `validate_configuration_metadata()` and
`validate(PublicConfigurationEffectivenessContract())` after changing solver
options or backend-specific launch configuration; both pass (the former runs
inside the latter).

- `validation/symplecticity_validation.jl` — **passed** for every element with
  the corrected tolerance floor; the four linear-map cases now judged at their
  declared 5.0e-8 rather than 5.0e-7 (§5).
- `validation/tracking_backend_consistency.jl` — **passed**,
  `max_abs_error = 2.0688e-17`, `global_rel_error` within tolerance, 10,000
  particles, 2 turns. Matches part 1's 2.07e-17.

**Not run this session**: the remaining 40 scripts in `validation/`. Part 1 ran
all 42 and repaired the one failure; nothing this session touches the element
layer or the solver kernels those scripts exercise, and the two scripts most
directly related to the changed surfaces were run.

## 11. Performance report

- **S5 is the only intentional performance change**: `beam_statistics` 24.94 →
  15.66 ms at 1 M particles, 55.36 → 42.87 ms with `diagonal_fourth=true`,
  bit-identical output (§7).
- **S1 restores a tuning surface rather than changing a default.** With the
  default `CUDAExecutionPolicy()`, `launch.threads` is 256 — exactly the
  hardcoded fallback that was being used — so default GaussianPIC runs are
  unchanged, which the fingerprint confirms. Only an explicitly non-default
  thread count now has an effect, which is the point.
- **S2, S3, S4 touch no hot path**: two are report/warning paths that run once
  per `execute!`, one is a tolerance constant, one adds test cases.

## 12. Change log

| file | change | finding |
|---|---|---|
| `src/tasks/strongstrong/interface.jl` | `_pic_launch_solver` dispatch helper replacing the `isa` test in `_with_solver_execution_configuration` | S1 |
| `src/tasks/strongstrong/gaussian_pic.jl` | `_pic_launch_solver(::GaussianPICPoissonSolver) = solver.pic` | S1 |
| `src/tasks/strongstrong/interface.jl` | `_preflight_solver_configurations!` covers every solver, not only PIC | S1, S2 |
| `src/tasks/strongstrong/interface.jl` | `configuration_report(::GaussianPoissonSolver)` honours `policy`/`backend` | S2 |
| `src/contracts/Contracts.jl` | `SymplecticityContract` tolerance floor 5.0e-7 → 5.0e-8 | S3 |
| `validation/symplecticity_validation.jl` | `DEFAULT_TOL` 5e-7 → 5e-8 | S3 |
| `src/contracts/Contracts.jl` | `thin_with(drift)` builder; `:chromatic` and `:exact` symplecticity cases | S4 |
| `test/runtests.jl` | virtual-drift symplecticity testset with step scan and unsafe-drift negative control | S4 |
| `src/beam/Beam.jl` | `beam_statistics` covariance upper triangle, mirrored | S5 |

## 13. Remaining risks

1. **~11,300 lines of the beam-beam solver stack remain unread** — `pic_cuda.jl`
   (5,807), `pic_cpu.jl` (1,715), `gaussian_pic_cuda.jl` (1,154),
   `spectral.jl` (1,045), `spectral_cuda.jl` (760), `gaussian_pic.jl` bulk. The
   consistency contracts exercise them end to end and pass at ~5e-17, which is
   real evidence, but it is behavioural agreement on one configuration each
   rather than a reading. This was part 1's largest risk and it still is.
2. **`src/knobs/symbolic.jl` (285) was declared in scope and not reached.**
3. **There is no `SolverOptionEffectivenessContract`.**
   `ElementParameterEffectivenessContract` sweeps all 238 element parameters
   mechanically and is what would have caught S1 and S2 had it covered solver
   options. `PublicConfigurationEffectivenessContract` checks the CUDA PIC
   launch families for `PICPoissonSolver` only — which is exactly why S1
   survived. **This is the highest-value next item**: the defect class is now
   demonstrated, and the enforcement pattern already exists one layer down.
4. **The CUDA grid solvers are not run-to-run bitwise reproducible** — measured
   at up to 1.3e-12 relative over two turns for `cuda/pic`, from float atomic
   deposition. The contracts' 1e-10 tolerance absorbs it and the soft-Gaussian
   CUDA path (no grid deposition) *is* bitwise reproducible, which is the
   control identifying deposition as the cause. This is inherent rather than a
   defect, but it is not stated anywhere in the docs, and a reproducibility-
   sensitive user would want to know.
5. ~~**`PTCConsistencyContract` can silently narrow.**~~ **Closed.** The row
   loop still skips a name the table does not carry, which is right for a stale
   row, but the contract now fails when a *declared* spec has no rows, naming
   the missing cases and pointing at `validation/generate_ptc_reference.jl`.
   Coverage asserted at 55 of 55, and the guard has a negative control: a copy
   of the table with one case's rows removed makes the contract fail naming that
   case rather than pass on the remaining fifty-four.
6. **`GaussianStrongBeamSpec`'s `:equal_area` docstring formula**,
   `z_k/sigz = sqrt(2)*erfinv(2k/ns)`, is the odd-`ns` form; the even-`ns` branch
   correctly uses `(2i−1)/ns`. The code is right, the formula as written covers
   half the cases.
7. **Part 1's risks 1a, 2, 5 and 6 are unchanged** — the F2/F3 configurations
   still have no external reference, GPU concurrency testing is still absent,
   `_SOL_CURVED_ORDER` is still not a public knob, and the BPM
   noise-repeats-within-a-turn question is still unverified.

## 14. Handoff — where the next session starts

### Done, do not redo

| area | state |
|---|---|
| `src/tasks/strongstrong/interface.jl` | **read in full** |
| `src/contracts/Contracts.jl` | **read in full** |
| `src/elements/strong_beam.jl` | **read in full**; beam-beam kick independently verified against numerical integration |
| Virtual drifts | all five measured for symplecticity, three now permanently tested |
| `Core.Box` class | swept again over 2,110 methods (up from 1,792); still eliminated |
| Contracts | all **12** run and passing, including the new solver-option contract |
| `beam_statistics` | measured and optimized, bit-identical |
| Solver options | `SolverOptionEffectivenessContract` built (§15): 68 on CPU, 10 CUDA-only on device, 2 launch surfaces, 10 exempted with reasons, **0 deferred** |
| `isa` against a concrete solver type | **class eliminated in `src/`** — it was the root cause of S1, S2 and S7; the only remaining textual hit is a docstring describing the fix |
| Method ambiguities | `Test.detect_ambiguities(Octopus)` swept and now **0** |

### Next, in priority order

*Item 1 of the original list — the solver-option effectiveness contract — was
built in this same session; see §15. What follows is the list with that removed.*

1. **`src/tasks/strongstrong/pic_cpu.jl` (1,715)** — the CPU reference every
   parity contract validates the CUDA paths against: if it is wrong, the
   contracts agree on the wrong answer. Its prior is now higher than when this
   list was first written. §15.2 found a reachable `UndefVarError` crash in it,
   in the **default** Green kernel, that the test suite, all twelve contracts
   and all forty-two validation scripts had never executed. That file has
   demonstrated it holds defects nothing exercises.
2. `src/tasks/BeamObservers.jl` (1,446) — only l. 700–1030 read.
3. `src/knobs/Knobs.jl` (896) + `symbolic.jl` (285) — only the epoch handshake
   was read, and `symbolic.jl` was declared in scope and never reached.
4. `src/tasks/strongstrong/pic_cuda.jl` (5,807) — the wavefront scheduler and
   Green cache; kernels are lower risk per part 1 §9a.

### What the new contract does *not* prove

It establishes that every declared solver option **reaches a consumer**. It says
nothing about whether that consumer is correct: `deposit_method = :TSC`
provably changes the result, and nothing in the contract claims TSC is
implemented right. That remains the job of the physics contracts and
`validation/`, and it is why item 1 above matters more than further contract
work.

### Techniques that found things this session

- **Read the derivation before calling a constant wrong.** The chromatic drift's
  `0.5` looked like a factor-of-two error and is exactly right; §7.1 of the
  theory note says so in one line.
- **An independent algorithm beats a tighter tolerance.** Numerical integration
  of the Bassetti–Erskine integral tested the Faddeeva form, the `η` series and
  the blend simultaneously, and cost about thirty lines.
- **Target the branch, not the range.** The first Bassetti–Erskine sweep stepped
  straight over the blend window, which is 1.2e-4 wide. A sweep that misses the
  branch it was written to test is worth nothing.
- **A negative control is what makes a passing test mean something.** The two
  `UnsafeVirtualDrift` models are documented non-symplectic maps; without them,
  "the residual is below tolerance" says nothing about whether the test could
  detect a defect.
- **Grep for the consumer, not the declaration.** Every finding here was found
  by asking "what reads this?" and following it to a runtime site — which is how
  `_cuda_pic_threads`'s hardcoded `return 256` surfaced.


---

# 15. Second phase — building the contract, and what it found

§13.3 recorded "no solver-option equivalent of
`ElementParameterEffectivenessContract`" as the highest-value next item. It was
built in the same session. Writing it surfaced six further defects, five of them
in code the contract had to touch before it could run at all.

## 15.1 `SolverOptionEffectivenessContract`

For each of the four solvers and each option in its `solver_option_schema`, the
option is set to a declared non-default value and one probe is run against a
baseline:

- **physics / numerical / accuracy categories** must change the observable —
  the twelve coordinate arrays *or* the returned luminosity. Luminosity is part
  of it because `gaussian_when_luminosity`, `luminosity_grid` and
  `luminosity_deposit_method` are meant to move that and nothing else.
- **execution categories** must *not* change the observable — that is what makes
  them execution choices — but must appear in a receipt named by the option's
  declared `consumer`.

An option with neither a declared alternative nor a stated reason **fails**, so
the tables cannot fall behind the schema. Result: 68 options checked on CPU, 2
launch surfaces on CUDA, 13 CUDA-only options deferred, 7 exempted with reasons.

**It has demonstrated discriminating power.** With S1 reintroduced by disabling
one method, the contract fails with
`GaussianPICPoissonSolver emitted no :cuda_pic_launch receipt`; with it restored,
it passes. That pair was run, not assumed.

## 15.2 S6 — `UndefVarError: PI` in the default Green kernel

`pic_cpu.jl:1369`, inside `_pic_atan_ratio`:

```julia
return copysign(oftype(num / one(den), PI / 2), num)
```

`PI` is not a name this module defines — `Constants.jl` exports `TWOPI`,
`SQRTPI`, `SQRT2PI` and `SQRT2`, never `PI`. The branch runs whenever
`den == 0` and `num != 0`, which for `_pic_kernel_integral(x, y)` means **any
Green-kernel node lying exactly on an axis**, under the default
`green_type = :integrated`.

Measured before the fix:

    _pic_kernel_integral(0.0, 1.0)  -> UndefVarError: `PI`
    _pic_kernel_integral(1.0, 0.0)  -> UndefVarError: `PI`
    _pic_kernel_integral(0.5, 0.25) -> -0.33528515411337795

**No working result can move.** `_pic_kernel_integral` multiplies the half-pi by
the coordinate that is zero on that branch, so the correct value there is `0.0`
and the fix only converts a crash into it — confirmed, both cases return exactly
`0.0` afterwards.

Graded Major on outcome, narrow on reachability, and the two should not be
confused: it is an unconditional crash in the default kernel, but only when a
mesh places a node at exactly zero, which ordinary extents do not. Nothing in
the suite, the contracts or `validation/` had ever hit it. It was found by
running the new contract against a caller that had moved the global RNG — a
different beam gave a different mesh, and the mesh put a node on the axis.

## 15.3 S7 — 59 of 88 options had no observable consumer

`interface.jl` emitted its `:solver_runtime` receipt behind
`if solver isa PICPoissonSolver`, and listed eleven of `PICPoissonSolver`'s
twenty-nine options by hand. Measured, one turn each:

| solver | declared options | `:solver_runtime` receipts |
|---|---|---|
| `GaussianPoissonSolver` | 14 | **0** |
| `PICPoissonSolver` | 29 | 1 |
| `GaussianPICPoissonSolver` | 32 | **0** |
| `SpectralPoissonSolver` | 13 | **0** |

Because `consumer` defaults to `:solver_runtime` in the `SolverOptionMeta`
constructor, most of those options *declared* a consumer that never fired for
them, and `validate_configuration_metadata()` passed throughout — it checks that
a consumer is named, not that it runs. Replaced with a receipt derived from
`solver_option_schema`/`solver_configuration`, complete by construction. Also
corrected `backend_configurations`, which declared `:solver_runtime` while its
real consumer is `:cuda_pic_launch`.

## 15.4 S8 — the hybrid dropped a mesh-extent estimator

`grid_extent` and `grid_extent_sigma` appear **nowhere** in `gaussian_pic.jl`:
the hybrid sizes its interaction box from `margin_sigma` and the subtracted
Gaussian's moments. Measured `:extrema` against `:sigma`, max relative
coordinate difference **0.0 at `margin_sigma = 5.0` and 0.0 at
`margin_sigma = 0.0`** — so the first hypothesis, that the adaptive box merely
masked the estimator, was wrong; the option is simply never read.

Fixed by **rejecting** rather than implementing, which is what the CUDA PIC
backend already does for this same option (`pic_cpu.jl:311`, "so a non-default
value would be silently ignored"). Following the established precedent rather
than inventing a third behaviour.

## 15.5 S9, S10 — two method ambiguities, one of them public

A module-wide `Test.detect_ambiguities` sweep — the same style of mechanical
whole-repository check as the `Core.Box` census — found two:

- `collide!(::GaussianPICPoissonSolver, …, ctx)` left `ctx` untyped, so it tied
  with the generic `collide!(::AbstractPoissonSolver, …, ::TrackingContext)`.
  `pic_cpu.jl` and `spectral.jl` both split `::Nothing` / `::TrackingContext`;
  the hybrid was the odd one out. The task path dispatches through
  `_strong_strong_collide_backend!` and never reached it.
- **`loss_summary(rep::Phase6DRep, task::TrackingTask)` was a `MethodError`** —
  a public API, for exactly the argument `execute!(task, rep; turns=…)` hands
  back. Passing a `Beam` worked, because its method is untyped in both
  positions, which is why nobody noticed. Verified before and after:

      loss_summary(rep, task)   FAILS: MethodError ... is ambiguous
      loss_summary(Beam, task)  OK  dead=0 logged=0

`detect_ambiguities` now reports **0** for the module.

## 15.6 S11 — two options declared as free that are not

The contract flagged both as "declared execution/performance but changed the
collision result", and both were confirmed by measurement rather than argued:

- `green_cache`: `:slice_pair` against `:none` differs by **1.96e-3** relative
  at the default `slice_pair_green_growth = 0.25`, and by **exactly 0.0** at
  `growth = 0`. That control proves the mechanism — a cached entry is built
  enlarged and reused, so the Green function is evaluated on a different domain.
  Recategorized `:execution` → `:accuracy_performance`.
- `SpectralPoissonSolver.method`: `:grid` against `:grid_free` differs by
  **5.3e-3** in coordinates and ~1% in luminosity, consistent with part 1's note
  that the coarse grid-free variant ran 4.9% low. Recategorized `:performance` →
  `:accuracy_performance`.

## 15.7 Corrections to this phase's own analysis

1. **The first version of the contract could not catch the defect it was written
   for.** It decided which solvers to test with
   `_pic_launch_solver(solver) === nothing && continue` — the very function S1
   broke. With S1 reintroduced it reported `1 launch surfaces` instead of 2 and
   **passed**, silently skipping `GaussianPICPoissonSolver` rather than failing
   it. The negative control is the only reason this was caught. Fixed by taking
   the obligation from the schema (`haskey(schema, :backend_configurations)`),
   never from the installer. A contract that asks the suspect whether to
   investigate is not a contract.
2. **The contract's result depended on its caller.** It passed standalone and
   failed inside the test suite, where earlier testsets had moved the global
   RNG. Every other strong-strong contract pins and restores the seed; this one
   did not. Fixed — and the dirty-caller run is what then exposed S6.
3. **The first probe could not see two whole classes of option.** A bare
   `collide!` passes `ctx = nothing`, which means "every turn", so
   `luminosity_schedule` looked ignored; and a single collision leaves the
   slice-pair Green cache with nothing to reuse, so the rebuild ratios looked
   ignored. Both were fixed in the probe, not blamed on the code.
4. **The `margin_sigma` hypothesis for S8 was wrong.** I expected the adaptive
   box to mask the estimator at the default margin and to reveal it at
   `margin_sigma = 0`. Measured 0.0 at both; the option is never read at all.

## 15.8 Verification for this phase

- `Pkg.test(julia_args=["--threads=8"])`: **passed**, exit 0, **104 testsets**
  (101 at the session baseline), with two new ones — the on-axis Green kernel
  and solver-option effectiveness, the latter carrying two negative controls of
  its own.
- **All 12 contracts pass**, `PTCConsistencyContract` still at 4.995e-13.
- Behavioural fingerprint: every deterministic case byte-identical.
- `Test.detect_ambiguities(Octopus)`: 0.


## 15.9 The CUDA-only options, checked rather than deferred

§15.1 deferred 13 CUDA-only options. They are now checked on the device, and
doing so found two more defects in `GaussianPICPoissonSolver` — both the same
class as S7 and S8, both invisible from the CPU.

`_cuda_gpic_collide!` (`gaussian_pic_cuda.jl:74`) selects its route from
`batch_mode` and `cuda_indexed_wavefront` **only**. It never reads
`cuda_async`, `cuda_batch_fft` or `cuda_wavefront_fft`, and it emitted no
`:cuda_pic_algorithm` receipt at all — the consumer all five of those options
declare, and which the plain PIC routes do emit at `pic_cuda.jl:71` and `:219`.
So on the hybrid, two options were consumed but unobservable and three were
accepted and dropped. The contract reported exactly that asymmetry: the same
five options passed for `PICPoissonSolver` and failed for the hybrid.

Fixed the same way as S8 — emit the receipt for the two the route reads, reject
the three it does not, matching how this backend already handles
`slice_interpolation` and `interaction_grid`.

Final coverage: **68 options on CPU, 10 CUDA-only on the device, 2 launch
surfaces**, 10 exempted with stated reasons, 0 deferred.

**A calibration problem worth recording.** The first CUDA comparison used exact
inequality and reported that *every* PIC option changed the result — because the
CUDA grid solvers are not run-to-run bitwise reproducible (§8), a fact this same
document had already established and which I nonetheless walked straight into.
The loop now runs each baseline twice and takes the spread as a noise floor,
subject to a minimum of `1e-10` — the tolerance the strong-strong
backend-consistency contracts already use for "the same result" across routes.
A route change reorders float atomic sums by ~6.5e-12 here; a genuine
algorithmic difference is seven orders above that (`green_cache` moved the CPU
result by 2e-3, the spectral `method` switch by 5e-3).

Both halves have negative controls, run rather than assumed: disabling
`_pic_launch_solver` for the hybrid makes the contract report
`emitted no :cuda_pic_launch receipt`, and suppressing the new
`:cuda_pic_algorithm` receipt makes it report
`batch_mode reached no receipt named by its consumer`.

**And a process error, since the rules apply to how the audit is run too.** One
suite run failed and I first read it as a regression; it was not. I had launched
the test suite in the background and then run the source-mutating negative
controls against the same working tree, so the suite compiled a half-disabled
library. Nothing was wrong with the code. Re-run on a quiet tree: exit 0, 104
testsets, 0 failures.

---

<a id="part-3"></a>

# Comprehensive Audit — 2026-08-03, part 3

> ## Start here
>
> **Do not read this front to back**, and do not read parts 1 or 2 front to back
> either. This pass covers exactly one file, `src/tasks/strongstrong/pic_cpu.jl`.
>
> | read | why |
> |---|---|
> | **§9** | the handoff: what is now covered and what is next |
> | **§1** and **§10** | the four defects. §10 is a same-day follow-up that closed the one open question §9 left, and found the largest accuracy defect of the pass doing it |
> | **§7** and **§10.2** | the wrong turns — three hypotheses this pass raised and its own measurements killed or corrected |
>
> §2 is the coverage ledger. §6 is the areas checked and found sound, which is
> most of the file and is the point of the exercise.
>
> If you read only one paragraph, read **§10.6**: the same blind spot — a check
> that cannot distinguish anything at `ρ = 1` — has now produced two separate
> defects in this one file.

A third pass against the protocol in
[`docs/comprehensive_audit.md`](../comprehensive_audit.md), resuming from
[part 2](#part-2) §14, whose priority list ranks
`pic_cpu.jl` first: it is the CPU reference every parity contract validates the
CUDA paths against, so if it is wrong the contracts agree on the wrong answer.

**That is not a hypothetical. It is what happened.** The largest finding here
(S14) is a Green function that both backends computed identically and both
computed for a source displaced by four tenths of a cell, with the CPU/CUDA
parity test passing at 1e-13 throughout.

**Four** confirmed defects, all fixed — three in the pass proper and a fourth
(§10) found by closing the one question the handoff left open. Three audit
hypotheses raised and then refuted or corrected by measurement, recorded in §7
and §10.2 rather than deleted.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S14 | **Moderate** | the Green cache's grid expansion destroys the integer-cell alignment `green_type = :lattice` is tabulated by; `_pic_green_lattice!` rounded silently, giving the field of a source displaced by 0.400 cells. Both backends, so parity agreed. | fixed, verified |
| S15 | Moderate | `_PICCPUWorkspace.dropped` was incremented and **read by nothing in the repository**, while its own comment said "Never silent", `grid_extent`'s metadata promised "dropped and counted", and `validation/README.md` said the count "must stay at zero" | fixed, verified |
| S16 | Minor | `grid_extent` is accepted and **bit-identically ignored** under `interaction_grid ∈ {:node, :source_slice}` | fixed (now rejects), verified |
| S17 | **Moderate** | the lattice Green function's periodic box is sized in *index* units, so at high aspect ratio it is physically far too flat; `:lattice` measured **10.3x worse** than the default kernel at the production aspect ratio, defeating the option's only stated purpose. Found by closing §9's open question — see **§10** | fixed, verified |
| P1 | performance | `_pic_field!`'s `Ey` pass walked a column-major array in row-major order — 42.8 µs → 3.0 µs at grid 128, bit-identical | fixed, measured |

**The pattern worth taking away.** Part 1's rule was "audit for checks that exist
and are never executed". Part 2's was "audit for values that are declared and
never read" — S15 and S16 are both squarely that, so the rule is still paying.

S14 is a third one, and it is the sharpest: **audit for invariants that one
function establishes and another quietly breaks.** `_pic_interaction_grids`
carefully aligns the two grids and says so; `_pic_expand_grid_by`, twenty lines
away, changes the cell size and undoes it. Neither function is wrong on its own.
Nothing that tests either of them in isolation can see it, and the thing built to
compare the two backends cannot see it either, because both backends break the
invariant the same way. What finds it is asking *what does this consumer assume,
and who guarantees it?* — `_pic_green_lattice!` assumed integer separation, the
comment above it named the function that guarantees it, and that function's
output no longer reaches it unmodified.

## 2. Declared scope and coverage ledger

Declared before reading anything in depth, per Phase 0. Scope was set by the
human and by the part 2 §14 handoff.

### Read in full, line by line — 1,732 lines

| file | lines | note |
|---|---|---|
| `src/tasks/strongstrong/pic_cpu.jl` | 1,732 (1,715 declared) | the whole declared scope |

### Read in part, in pursuit of specific questions

- `interface.jl` — the `PICPoissonSolver` struct and constructor validation
  (l. 1057–1180), the workspace and cache structs (l. 475–543),
  `_pic_luminosity_grid` / `_pic_luminosity_deposit_method` /
  `_pic_compute_luminosity` (l. 1207–1211, 1950–1975), the `grid_extent` option
  metadata (l. 1268–1291).
- `pic_cuda.jl` l. 2100–2245 — `_cuda_pic_slice_pair_cached_prep!` and the
  expansion helpers, because the CPU defect had to be checked for a mirror.
- `gaussian_pic.jl` l. 630–680 — it routes through `_pic_slice_pair_green!`, so
  S14 reached it too.
- `contracts/Contracts.jl` l. 2000–2090, 2294–2485 — the solver-option contract's
  probe/alternative tables and its main loop, which S16's fix made unrunnable.
- `validation/pic_gaussian_field_validation.jl`, `pic_grid_extent_stability.jl` —
  to establish what they actually score, which is how it became clear the Green
  cache is never in the loop when the kernel is measured.

### Deliberately not covered, and why

`pic_cuda.jl` bulk (5,807), `gaussian_pic_cuda.jl` (1,154), `spectral*.jl`
(1,805), `slicing.jl` (704), `gaussian_pic.jl` bulk — not this pass's declared
file. `interface.jl`, `Contracts.jl` and `strong_beam.jl` were read in full in
part 2 and were not re-read.

### Equations independently derived

1. **The integrated Green kernel.** `_pic_kernel_integral(x,y) =
   (ln r² − 3)xy + x² atan(y/x) + y² atan(x/y)` is the double antiderivative of
   `ln(x²+y²)`. Derived by hand: `∂F/∂x = y ln r² − 2y + 2x·atan(y/x)`, and
   `∂²F/∂x∂y = ln r² + 2y²/r² − 2 + 2x²/r² = ln r²`. The four-corner difference
   times `−1/(2 h_x h_y)` is therefore the cell average of `−ln r`. **Correct.**
   Also checked the one thing that derivation does not: `F` is *continuous*
   across `x = 0`, because the `x²` prefactor kills the `±π/2` jump in
   `atan(y/x)` — without which the four-corner difference of a cell straddling
   the axis would be wrong. It does.
2. **The lattice kernel normalization.** `∇²(−ln r) = −2πδ` and the five-point
   symbol is `−κ/h_x²` with `κ = (2−2cos t_x) + ρ²(2−2cos t_y)`, `ρ = h_x/h_y`,
   so `Ĝ = 2πρ/κ`. That is exactly `scale = 2pi*rho` over `ghat = 1/kap`,
   inverted with `ifft` (which carries the `1/N` the lattice sum needs).
   **Correct.**
3. **TSC weights.** For `δ = u − nearest`, `W(∓1) = ½(½∓δ)²`, `W(0) = ¾ − δ²`.
   Both branches of `_pic_tsc_weights` expand to exactly that, including the
   `f ≥ ½` branch where `δ = −(1−f)`. **Correct.**
4. **`_pic_align_grid_origins` does what it claims.** New separation is
   `d/h − (f₂−f₁)`, and `d/h = integer + (f₂−f₁)`, so the result is an exact
   integer (`:integrated`, `:lattice`) or exactly a half cell (`:standard`).
   **Correct** — which is what makes S14 a broken invariant rather than a wrong
   formula.
5. **The luminosity overlap**, verified against the closed-form Gaussian result
   `1/(2π√(σ₁ₓ²+σ₂ₓ²)√(σ₁ᵧ²+σ₂ᵧ²))` — see §5.
6. **Slice interpolation weights.** `zL = (rb − z)/(rb − lb)` from
   `_slice_interpolation_parameters`, which is 1 at `lb` and 0 at `rb`, matching
   `sL = ½(c_source − lb)`. The quadratic basis `2t²−3t+1`, `4t−4t²`, `2t²−t`
   sums to 1 and its `z`-derivative weights `3−4t`, `8t−4`, `1−4t` sum to zero,
   so the gauge constant in `φ` cancels. **Correct**, and both match the
   docstring's stated forms.

## 3. S14 — an invariant established by one function and destroyed by another

`_pic_interaction_grids` (`pic_cpu.jl:964-965`, and `955-956` under
`grid_quantize`) ends by calling `_pic_align_grid_origins`, which puts the source
and field grid origins an exact integer number of cells apart. The comment above
the lattice kernel says so explicitly (`pic_cpu.jl:1408-1412`):

> The table is indexed by INTEGER lattice separation, which is legitimate because
> `_pic_align_grid_origins` puts the source and field origins an exact integer
> number of cells apart for every `green_type` except `:standard`.

`_pic_slice_pair_green!` then expands both grids by `1 + slice_pair_green_growth`
(`pic_cpu.jl:988-989`) before building the Green function. `_pic_expand_grid_by`
scales `width` with the node count `nx` fixed, so the **cell size** grows by the
same factor while the origin separation does not. An exact `k`-cell separation
becomes `k/(1+growth)`.

### Evidence

Separation between the two origins, one representative slice pair, grid 64:

| `green_type` | growth | before expansion | after expansion |
|---|---|---|---|
| `:integrated` | 0.00 | 22.000000 (\|frac\| 3.6e-15) | 22.000000 |
| `:integrated` | 0.25 | 22.000000 | **17.600000 (\|frac\| 0.400)** |
| `:lattice` | 0.25 | 22.000000 | **17.600000 (\|frac\| 0.400)** |
| `:standard` | 0.25 | 21.500000 (a deliberate half cell) | **17.200000** |

`_pic_green_lattice!` (`pic_cpu.jl:1482-1483`) then did
`dx = round(Int, (field_x0 - source_x0) / hx)` — **rounding silently**. The
function already threw for a separation outside the tabulated range, with the
message "this indicates unaligned interaction grids", so it intended to catch
exactly this; it checked the wrong property.

The consequence is not a small error in the kernel value. It is the kernel of a
**displaced source**. Measured directly: one macroparticle at an exact source
node, apparent position located from the zero crossing of `Ex` on the field grid:

| grid pair | true source x | apparent x | offset |
|---|---|---|---|
| aligned (`green_cache = :none`) | −2.125000e−05 | −2.125000e−05 | **+0.0000 cells** |
| expanded (`green_cache = :slice_pair`, the default) | −2.010417e−05 | −2.468750e−05 | **−0.4000 cells** |

−0.4000 is exactly the rounding residual. Both backends do the same expansion
(`pic_cuda.jl:2123-2124`), so `test/runtests.jl`'s `:lattice` CPU/CUDA parity
check passed at `< 1e-13` on the displaced field.

### Why nothing caught it

- The `:lattice` testset (`test/runtests.jl:6166`) checks the *table* against
  `−ln r` (which is aligned by construction, separation 0), then checks
  end-to-end only that the result is finite, that it *differs* from
  `:integrated`, and that luminosity agrees to `rtol=1e-3`. A 0.4-cell field
  displacement passes all three.
- `validation/pic_gaussian_field_validation.jl` is the only place the kernel is
  scored against an analytic reference, and it calls `_pic_solve_field`
  (`pic_cpu.jl:1081`), which builds the Green function directly and **never
  touches the slice-pair cache**. The cache is out of the loop precisely where
  accuracy is measured.
- `SolverOptionEffectivenessContract` proves `green_type` reaches a consumer. It
  says nothing about whether the consumer is right — which part 2 §14 predicted
  in as many words.

### Fixed

`_pic_realign_expanded_grids` (`pic_cpu.jl`), called from `_pic_slice_pair_green!`
and from the CUDA mirror site, re-applies `_pic_align_grid_origins` with the
expanded cell size. `:integrated` is **deliberately excluded**: its kernel is
evaluated at real coordinates and does not depend on the alignment at all, so
re-aligning it would move the default mesh and change results that carry no
defect. `_pic_green_lattice!` now rejects a fractional separation instead of
rounding it.

Post-fix separations: `:lattice` 17.600000 → 17.000000 (residual 0.000e+00),
`:standard` restored to a half cell.

### What the fix does and does not buy

Honest accounting, because two attempts to show a physics improvement failed to
isolate one:

- The **displacement is gone**, which is measured directly and is not in doubt.
- Scored against the exact Bassetti–Erskine kick on a fixed grid at grid 128
  with the 11:1 production beams, the median relative field error moved
  3.097e−2 → 3.026e−2, a factor of **1.02**. The residual in that configuration
  was 0.2 cells, not 0.4, and the lattice kernel's own systematic error at that
  aspect ratio is an order of magnitude larger than the displacement it was
  masking.
- End to end at grid 64 against a grid-512 reference, the change is **not
  separable** from the grid-64 discretization error (§7.2).

So: a real defect, directly demonstrated, in a kernel that is documented
EXPERIMENTAL and explicitly not recommended for production. Fixing it is
justified by the invariant, not by a demonstrated change in a physics result, and
that is stated here rather than dressed up.

## 4. S15 — a counter written by one line and read by none, under a "Never silent" comment

`_PICCPUWorkspace.dropped` (`interface.jl:505-508`) counts particles that fell
outside the interaction mesh and were dropped by the zero-weight branch. Its
comment ends:

> non-zero means a robust estimator under-covered and the field lost charge.
> Never silent.

It was silent. A census over the lowered code of every method in the module found
`dropped` mentioned in **exactly one method** — `_pic_interaction!`
(`pic_cpu.jl:425`), the writer:

```
=== is _PICCPUWorkspace.dropped ever READ? ===
  methods mentioning `dropped`: 1
    _pic_interaction! @ src/tasks/strongstrong/pic_cpu.jl:425
```

Three separate documents promised it was observable:

- the field comment above, "Never silent";
- `interface.jl:1273`, `grid_extent`'s option metadata: "out-of-range particles
  are dropped **and counted**";
- `validation/README.md:531`: "`dropped` must stay at zero for a production
  setting".

`validation/pic_grid_extent_stability.jl` does print a `dropped` column, which is
what makes this look covered — but it recomputes its own from `_pic_axis_extent`
(l. 109–110) and never reads the runtime counter.

Measured consequence, `grid_extent = :sigma, grid_extent_sigma = 2.0`, 3000
particles per beam: **389 particles dropped**, luminosity 0.1% off, and no signal
anywhere. At `grid_extent_sigma = 1.5`: **1842 dropped**, silently.

### Fixed

`_pic_report_dropped` warns from `_pic_collide!` whenever the count is non-zero,
and the counter is reset per collision so the number means "this collision".
Dropped charge is a correctness event, not a tuning statistic, so it warns rather
than printing only under the diagnostics flag. It is silent at zero, which is
every run under the default `grid_extent = :extrema`.

The count was also **moved** to after the Green cache resolves the final grid,
and is now taken against `field_grid` rather than the estimator box. The old
placement over-reported: the mesh carries 1.5 cells of margin beyond the
estimator box, so a particle sitting in that margin was counted as dropped while
being interpolated perfectly well.

## 5. S16 — `grid_extent` accepted and bit-identically ignored under two of three mesh modes

`grid_extent` is consumed by `_pic_axis_extent`, which only the per-slice-pair
sizing path in `_pic_interaction!` calls. `:source_slice` sizes its mesh from
`_pic_union_bounds` and `:node` from `_pic_build_node_grids!` — both take plain
`min`/`max` over their own particle sets and never consult the estimator.

Controlled test, identical beams, comparing full coordinate arrays:

| `interaction_grid` | `:extrema` vs `:sigma` | vs `:sigma`, `grid_extent_sigma = 2.0` |
|---|---|---|
| `:slice_pair` | differs (option read) | differs (option read) |
| `:source_slice` | **BIT-IDENTICAL** | **BIT-IDENTICAL** |
| `:node` | **BIT-IDENTICAL** | **BIT-IDENTICAL** |

The control matters: `grid_quantize` and `min_transverse_extent` were checked the
same way under all three modes and are **read** under all three, so the test can
tell the difference between "ignored" and "my probe is blunt".

This is the same class as part 2's S8 (the Gaussian-PIC hybrid silently ignoring
`grid_extent`) and is fixed the same way — rejected, in the constructor and again
in `_validate_pic_solver`, matching how every other option in this file is
validated. Nothing in `test/`, `validation/` or `examples/` combined the two.

The fix made `SolverOptionEffectivenessContract` fail, because its PIC probe sets
`grid_extent = :sigma` (deliberately, so `grid_extent_sigma` can act) and its
`interaction_grid` alternative is `:source_slice`. That is the contract working.
An alternative may now be a `NamedTuple` carrying a companion setting, and the
companion is applied to the option's **baseline** as well, so the comparison
still isolates the option under test rather than measuring the companion.
Coverage is unchanged: 68 CPU options, 10 CUDA-only, 2 launch surfaces.

## 6. Areas checked and found sound

The point of the pass. Each of these was checked against something independent,
not merely read.

- **The three `_run_logical_workers` sites** (`_pic_deposit_threaded!` ×2,
  `_pic_deposit_drifted_threaded!`) — the part 1 §3 closure-capture class,
  checked on **lowered code** as that section requires, not by grep. All three
  clean: `Core.Box = false`. The `local_grid` name is assigned both inside the
  `do` block and in a following `for` header, which is the exact shape that gave
  six false positives to a text sweep — and `for` opens a scope, so it is a
  genuine false positive here too.
- **The integrated Green kernel**, derived by hand (§2.1) including the
  continuity at `x = 0` the four-corner difference depends on.
- **The lattice kernel normalization**, derived independently (§2.2).
- **TSC and CIC weights**, derived (§2.3) and checked to sum to 1 in range and 0
  out of range.
- **The luminosity path**, against the closed-form Gaussian overlap
  `1/(2π√(σ₁ₓ²+σ₂ₓ²)√(σ₁ᵧ²+σ₂ᵧ²))`, 200,000 particles per beam:

  | deposit | grid 64 | grid 128 | grid 256 |
  |---|---|---|---|
  | CIC | −3.644e−3 | −7.834e−4 | −1.978e−4 |
  | TSC | −5.535e−3 | −1.245e−3 | −2.781e−4 |

  Ratios 4.65 / 3.96 and 4.45 / 4.48 — clean second-order convergence to the
  analytic value. This validates the weights, the `h_x h_y` normalization and the
  `klum` scale together.
- **`_pic_align_grid_origins`** — derived (§2.4). Its `t > 0.5` / `t < −0.5`
  branches are unreachable (`t = (f₂−f₁)/2 ∈ (−0.5, 0.5)` since `f₁,f₂ ∈ [0,1)`),
  which is harmless dead code, not a defect.
- **The `:extrema` margin claim.** `_pic_cic_weights`' docstring says its
  out-of-range branch is unreachable under `grid_extent = :extrema`. Derived:
  `h_x = t_x` exactly, so `u ∈ [1.5, n−2.5]`; measured `[1.591, 61.591]` at
  `n = 64`. True, and it holds for the wider TSC stencil too.
- **`_pic_field!` boundary stencils** — the one-sided forms `(1.5φ₀ − 2φ₁ +
  0.5φ₂)/h` are the standard second-order one-sided first derivative, sign
  consistent with `E = −∇φ`; the fourth-order interior stencil
  `[(φ_{i+2}−φ_{i−2}) + 8(φ_{i−1}−φ_{i+1})]/(12h)` is the standard form.
- **The field/source drift bookkeeping.** The bounds initializer at
  `_pic_interaction!` l. 476–477 computes `field.x[1] + (0.5(z−c))·px[1]` with
  the same association as the loop's `s * field.px[i]`, so the initial min/max is
  bit-identical to the value the loop then writes. Checked because an off-by-one
  there would silently shrink the box by one particle.
- **The `:node` longitudinal path.** `phi_L − phi_Z` is evaluated with both
  planes on `gL`'s mesh, as its docstring requires — the transverse blend reads
  each node on its own mesh, the longitudinal difference does not. Confirmed by
  reading which grid each `_pic_interpolate_kick` call is handed.

## 7. Corrections to this audit's own analysis

Two hypotheses this pass raised and its own measurements killed. Both are kept
because a wrong turn that is visible is worth more than a clean story.

### 7.1 "`_pic_green!` iterates a column-major array in row-major order, so it is
slow." — **Refuted.**

The observation is true: `for i in 0:(2nx-1), j in 0:(2ny-1)` writing
`green[i+1, j+1]` walks with stride `2nx`, and the sibling
`_pic_green_lattice!` twenty lines below already loops the other way. The
inference was wrong. Measured at grid 128, bit-identical output:

```
shipped (i-outer)   4.950 ms
contiguous (j-outer) 4.990 ms   speedup 0.99x
```

No difference, because the loop body is four `_pic_kernel_integral` calls, each a
`log` and two `atan`. It is compute-bound; memory order is irrelevant. **Not
changed.** The lesson is the protocol's own: measure rather than speculate, and
"this loop is transposed" is a hypothesis, not a finding.

### 7.2 "The alignment fix should visibly improve the `:lattice` transverse kick."
— **Not demonstrated.**

The first attempt compared `:lattice` against `:integrated` on aligned, expanded
and re-aligned grid pairs, and the misaligned case came out *better*
(8.63e−2 against 1.00e−1). That comparison is worthless: the three grid pairs
have different cell sizes and different aspect ratios, so it was measuring the
lattice kernel's ρ-sensitivity, not the alignment. Recorded because it is the
kind of number that would have been easy to quote in the wrong direction.

The second attempt held the grid fixed and scored against the exact
Bassetti–Erskine kick, which is the right comparison, and gave 1.02x (§3). End to
end at grid 64 against a grid-512 reference, cache-on and cache-off differ by
less than the discretization error either carries. **The defect is confirmed
mechanically and the physics gain is not demonstrated**, and §3 says so.

## 8. Test, contract, validation and performance report

Julia 1.12.4, Linux 5.14.0, 128 logical cores, CUDA device visible and
functional.

### Tests

`Pkg.test(; julia_args=["--threads=4"])` — **passing**, including the CUDA
testsets. Three testsets added:

- `Green-cache expansion preserves the grid alignment its kernels require`
  (19 assertions) — checks the invariant before expansion, checks that the
  expansion **breaks** it (the negative control, so the test cannot pass
  vacuously), checks the realignment restores it, checks `:integrated` is left
  untouched, and checks `_pic_green_lattice!` accepts an aligned pair and rejects
  a 0.4-cell misaligned one.
- `grid_extent is rejected, not ignored, where no estimator runs` (7) — including
  that `:slice_pair` still accepts it, so the check cannot pass by forbidding the
  option outright.
- `Dropped PIC charge reaches a reader` (5) — `@test_logs` that the default is
  silent and that an under-covering estimator is not.

### Contracts — all pass

| contract | status |
|---|---|
| `StrongStrongPICBackendConsistencyContract` | passed |
| `StrongStrongGaussianBackendConsistencyContract` | passed |
| `ElementParameterEffectivenessContract` | passed (238 parameters) |
| `KnobEffectivenessContract` | passed |
| `PTCConsistencyContract` | passed (55 cases, worst 5.0e-13) |
| `PublicConfigurationEffectivenessContract` | passed |
| `SolverOptionEffectivenessContract` | passed (68 CPU, 10 CUDA-only, 2 launch surfaces — coverage unchanged) |
| `CoherentModePhysicsContract` | passed |
| `HighEnergyWeakStrongLimitContract` | passed |
| `SymplecticityContract` | passed |
| `ElementTrackingBackendConsistencyContract` | passed (via the suite) |

### Validation

| script | result |
|---|---|
| `pic_gaussian_field_validation.jl` | median relative error 3.46e-4 … 4.60e-4 across five aspect ratios — unchanged |
| `pic_grid_extent_stability.jl` | `:extrema` 5.31e-2 / `:sigma` 6.46e-3 slice-to-slice, `dropped = 0` — matches the recorded history |
| `tracking_backend_consistency.jl` | global relative error 9.42e-16, `passed_tolerance = true` |

### Behavioural fingerprint

Captured before the first modification (Phase 13) and re-captured after all
fixes: luminosity, `sum(abs, coords)` and `coords[1]` at 17 significant digits,
over 14 solver configurations. **Bit-identical in 12 of 14.** The two that moved
are `green_type = :lattice` and `green_type = :standard` with the default cache —
exactly the configurations S14 targets, and nothing beside them. In particular
the default, `green_cache = :none`, `:lattice`/`:standard` without the cache,
`:TSC`, `:fourth`, `:quadratic`, `:node`, `:source_slice`, `:sigma`,
`grid_quantize` and `longitudinal_kick = false` are all unchanged to the last
bit.

### Performance

`_pic_field!`'s `Ey` pass, grid 128, bit-identical output, decomposed:

| variant | time |
|---|---|
| i-outer, no `@inbounds` (shipped) | 42.8 µs |
| i-outer, `@inbounds` | 42.4 µs |
| j-outer, no `@inbounds` | 4.8 µs |
| j-outer, `@inbounds` (now) | **3.0 µs** |

Loop order is the cause (8.9x); `@inbounds` adds 1.6x; 14.3x together. The `Ex`
pass below it was already contiguous, which is what made the asymmetry visible.

**Honest share:** at ~256 calls per collision this is ~11 ms of a ~2 s collision
at grid 128, about **0.5%**, which is below the run-to-run wall-clock noise on
this machine. Taken because it is free and bit-identical, not because it moves a
total. No regression anywhere: the fingerprint above is unchanged.

## 9. Handoff — where the next session starts

### Done, do not redo

| area | state |
|---|---|
| `src/tasks/strongstrong/pic_cpu.jl` | **read in full**; four defects fixed |
| The integrated and lattice Green kernels | independently derived, normalization confirmed |
| The luminosity path | verified against the analytic Gaussian overlap, second-order convergence confirmed |
| `Core.Box` class in this file | all three fan-out sites checked on lowered code, clean |
| Contracts | all run and passing; solver-option coverage unchanged at 68/10/2 |

### Next, in priority order

1. **`src/tasks/BeamObservers.jl` (1,446)** — only l. 700–1030 read (part 2).
2. **`src/knobs/Knobs.jl` (896) + `symbolic.jl` (285)** — only the epoch handshake
   read; `symbolic.jl` was declared in scope in part 2 and never reached.
3. **`src/tasks/strongstrong/pic_cuda.jl` (5,807)** — the wavefront scheduler and
   Green cache. Now carries a *specific* question rather than a general one: §3
   shows the CUDA cached-prep path mirrors the CPU one closely enough to have
   inherited S14 verbatim. Look for the other invariants it mirrors.
4. `spectral.jl` (1,045) and `spectral_cuda.jl` (760) — untouched by any audit.

### Two things this pass could not settle

- ~~**`:lattice` accuracy against the theory note.**~~ **Closed in a follow-up the
  same day, and it was a real defect — see §10.**
- **The `:node` path has no dropped-particle accounting.** `_pic_interaction_node!`
  never counts, so `dropped` is structurally zero there. It does not matter today
  because S16 now forbids `grid_extent ≠ :extrema` under `:node`, and `:extrema`
  covers by construction — but the two facts are only accidentally consistent,
  and lifting S16's restriction without adding the count would reintroduce a
  silent charge loss.

### Techniques that found things this pass

- **Ask who guarantees a consumer's assumption, then check the guarantee still
  reaches it.** S14 is entirely this. The comment above `_pic_green_lattice!`
  named `_pic_align_grid_origins` as its guarantor; the question that found the
  defect was whether anything sits between them.
- **A census over lowered code answers "is this ever read?" definitively.** One
  loop over every method in the module settled S15 in seconds, where a grep would
  have found the validation script's unrelated `dropped` column and looked like
  coverage.
- **Test the option under every value of the option it interacts with.** S16 is a
  cross-product: `grid_extent` works, `interaction_grid` works, and one silently
  erases the other. The contract tests options one at a time against a fixed
  probe and cannot see this class.
- **Carry a control through every ignored-option test.** `grid_quantize` and
  `min_transverse_extent` being *read* under all three modes is what makes
  "`grid_extent` is bit-identical" mean something.
- **A negative control in the regression test.** The alignment test asserts the
  expansion *breaks* the invariant before asserting the fix restores it —
  otherwise it would pass just as happily against a no-op.

---

# 10. Follow-up — S17, the `:lattice` question closed, and it was a defect

§9 left the `:lattice` accuracy discrepancy open as "probably a harness
mismatch, not a claimed contradiction". It was neither. It was a fourth defect in
this file, and the caution in §9 was the right instinct applied to the wrong
conclusion.

| # | severity | area | state |
|---|---|---|---|
| S17 | **Moderate** | the lattice Green function's periodic box is sized in *index* units, so at high aspect ratio it is physically far too flat; `:lattice` measured **10.3x worse** than the default kernel at the production aspect ratio, defeating the option's only stated purpose | fixed, verified |

## 10.1 Ruling out the harness first

No harness for the theory note's table was ever committed — `e3818be`, the commit
that added Section 3.4, touched `pic_free_space_kernels.md` and `todo.md` and
nothing else. So the note's numbers cannot be reproduced by construction, and the
only way forward was to re-measure with the repository's own documented
methodology: `validation/pic_gaussian_field_validation.jl`'s harness defaults
(deterministic 320² quantile source, 161² field points over ±4σ, TSC deposition,
median relative error against Bassetti–Erskine).

That reproduction is what turned a suspicion into a finding, because of one row:

| case | grid | note's `:lattice` vs `:integrated` | re-measured |
|---|---|---|---|
| round | 128 | 2.80x worse | **2.74x worse** |
| 11:1 | 128 | 1.48x **better** | **30.0x worse** |
| 25:1 | 128 | 1.37x **better** | **120x worse** |

The round-beam case reproduces almost exactly. Only the anisotropic cases
diverge, and they diverge by two orders of magnitude. A harness mismatch does not
behave like that.

The decisive observation was in the grid refinement: `:lattice` at 11:1 went
**3.21e-2 at grid 64 → 3.47e-2 at grid 128**, and at 25:1 1.54e-1 → 1.64e-1. It
got *worse* with refinement. Discretization error does not do that; a kernel that
is simply wrong does.

## 10.2 The mechanism

`_PIC_LATTICE_GREEN_MULT = 8` sets `Mx = 8·2nx`, `My = 8·2ny` — a multiple of the
padded extent **in index units**. The free-space limit needs the periodic box to
be large in **physical** units in every direction. The box is `Mx·hx` by `My·hy`,
so at `ρ = hx/hy = 11` it is eleven times flatter than it is wide; the
separations the table must cover span `±2nx` cells in x and `±2ny` in y, which is
eleven times *wider* than tall physically. The y-images therefore sit an order of
magnitude closer than the x-images and contaminate every separation far along x.

Measured on the table itself, as the spread of `G + ln r` (identically zero for a
true `−ln r + const`), over 24 separations:

| ρ | mult 8 (shipped) | 16 | 32 | 64 |
|---:|---:|---:|---:|---:|
| 1 | 8.744e-3 | 8.762e-3 | 8.766e-3 | 8.768e-3 |
| 5 | 1.325e-1 | 1.141e-1 | 1.105e-1 | 1.105e-1 |
| 11 | **2.663e-1** | 1.524e-1 | 1.227e-1 | 1.152e-1 |
| 25 | **8.917e-1** | 4.368e-1 | 4.367e-1 | 4.367e-1 |

**That table also contains this pass's own wrong turn.** It does not converge to
zero, and the first reading of it — "the kernel is broken at high ρ" — was too
strong. Decomposing by axis separates two different things:

| separation | mult 8 | mult 64 |
|---|---:|---:|
| (m=16, n=0) | −2.921e-2 | **3.986e-6** |
| (m=32, n=0) | −1.430e-1 | **−1.758e-3** |
| (m=0, n=8) | 1.234e-1 | 1.134e-1 |
| (m=0, n=16) | 7.650e-2 | 6.625e-2 |

The **x-axis** residuals vanish when the box grows: that is box contamination and
it is the defect. The **y-axis** residuals do not move at all: at ρ=11 a
separation of n cells is n/11 x-cells, so those points are inside the near-origin
region, and this is the *intended* anisotropic lattice correction the note
already documents ("at ρ=11 the correction is still ~5.9e-2 at r=16 in coarse-axis
cells" — measured here as 7.65e-2). Only the first of the two was ever wrong.

## 10.3 Fixed, and what it costs

The multiplier is now applied per axis and scaled by the aspect ratio,
`_pic_lattice_box_mult(ρ)`, enlarging the box on the fine-spacing axis and capped
at 64 to bound the auxiliary FFT. Symmetric in `ρ ↔ 1/ρ`, since
`_pic_interaction_grids` produces both.

Median relative field error, grid 64, before and after:

| aspect | `:integrated` | `:lattice` before | `:lattice` after |
|---|---:|---:|---:|
| round | **9.60e-4** | 1.74e-3 (1.81x worse) | 1.74e-3 (1.81x worse) |
| 5:1 | 2.33e-3 | 6.76e-3 (2.90x worse) | **1.93e-3 (1.20x better)** |
| 11:1 | 3.10e-3 | 3.21e-2 (**10.3x worse**) | **2.63e-3 (1.18x better)** |
| 25:1 | 3.70e-3 | 1.54e-1 (**41.5x worse**) | **3.18e-3 (1.17x better)** |

The qualitative claim in the theory note — worse for round beams, better for flat
ones — is now what the code actually does. It was not before.

**The cost is real and is not hidden.** One table at grid 128, ρ=11 goes from
0.26 s to 3.63 s. The note already records that a production run needs ~306
distinct tables, so that is ~18 minutes of table building per run. This
strengthens rather than weakens the existing "do not use in production"
recommendation; `:lattice` exists for field-accuracy studies, and a kernel that is
fast and an order of magnitude wrong is worth nothing to that purpose.

Round beams (ρ=1) get `(8, 8)` exactly as before, so every previously recorded
isotropic result stands unchanged — including the `a(1,0) = 1/4` check.

## 10.4 What remains open

At grid 128 the cap binds: ρ=11 wants an 88× box and gets 64×, leaving the
physical y-extent at 5.8× the region rather than 8×. `:lattice` there lands at par
with `:integrated` (1.18e-3 against 1.16e-3) rather than the 1.48x better the note
claims. That gap is bounded by the auxiliary FFT cost, not by anything
conceptual, and the note's own "concrete route to making it cheap" — a small
lattice patch near the origin plus the analytic asymptotic beyond — would remove
the constraint entirely.

## 10.5 Verification

Full suite passing at `--threads=4` including every CUDA testset; the `:lattice`
CPU/CUDA parity check still holds at `< 1e-13` (the table is built on the host and
uploaded, so one fix covers both backends). One testset added, *The lattice Green
box is sized in physical units, not index units* (14 assertions): the multiplier
is aspect-scaled, symmetric under `ρ ↔ 1/ρ`, and capped; the coarse-axis residual
— the part box contamination destroys, as opposed to the fine-axis near-origin
correction, which is expected to remain — is bounded at 1e-2, against a pre-fix
value of 1.4e-1 at ρ=11.

## 10.6 The lesson worth keeping

**A dimensionless criterion needs its units named.** "The box must be a
comfortable multiple of the padded extent" is true and was implemented faithfully;
it is simply not the same statement in index units and in physical units, and the
two coincide exactly when ρ = 1 — which is the only aspect ratio the shipped test
ever checked. That is the same failure shape as the note's own recorded near-miss
on the normalization, where `2π/(h_x h_y)` and a bare `2π` coincide at
`h_x = h_y = 1` and an isotropic sanity check could not separate them. The same
blind spot, in the same file, caught twice by the same question: **what does this
check fail to distinguish at ρ = 1?**

---

<a id="part-4"></a>

# Comprehensive Audit — 2026-08-03, part 4

> ## Start here
>
> **This pass found nothing, and that is the result.** `pic_cuda.jl`'s host-side
> orchestration was audited against a specific hypothesis — that it had inherited
> more of the CPU's defects the way it inherited S14 — and the hypothesis failed.
>
> | read | why |
> |---|---|
> | **§1** | the hypothesis, and why an empty findings list here is evidence rather than absence |
> | **§3** | what was checked and found sound — this is the substance |
> | **§4** | three claims this pass made and then had to withdraw or correct, including one that nearly became a false finding |
> | **§5** | remaining risks, and §6 the handoff |
> | **§7.3** | how the field-solver region was settled — by *measurement*, with a 1e-15 noise floor against a 1e-5 signal — rather than by reading a plane layout |
> | **§8** | two non-defect findings, both fixed: an invariant nothing tested, and a green test run that says nothing about the GPU |
>
> §2 is the coverage ledger. Read it before trusting any coverage claim here.

Fourth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
resuming from [part 3](#part-3) §9, which ranked
`pic_cuda.jl` next and — unusually — handed it a *specific question* rather than a
general one.

## 1. Executive summary

**Zero confirmed defects** across `pic_cuda.jl` l. 1–3470. No `src/` behaviour
changed anywhere; one docstring added. **Two non-defect findings, both fixed**
(§8): an invariant the field derivative depends on that nothing tested, and a
test suite that reports green while silently skipping every GPU test.

Part 3's S14 showed `_cuda_pic_slice_pair_cached_prep!` inheriting a defect
*verbatim* from the CPU, with the parity test blind to it because both backends
broke the same invariant identically. The governing question here was therefore
not "is this code correct in isolation" but:

> **Which invariants does `pic_cuda.jl` re-derive rather than share, and does each
> re-derivation still hold?**

Anything computed independently on the two backends is where parity is strong (a
divergence shows up immediately). Anything *shared and wrong*, or *copied and
wrong the same way*, is where parity is blind. That is the map this pass followed.

Both classes came back clean, and the checks were built to fail loudly:

- The re-derived device functions were compared against their CPU twins
  **numerically**, over 200,000 randomised samples, not by eye.
- The `ρ = 1` blind spot that produced *two* defects in `pic_cpu.jl` (part 3
  §10.6) was tested at aspect ratios 1:1, 11:1 and 25:1 against an **analytic**
  reference, not against the CPU.
- The `Core.Box` class was swept over lowered code, closing a `docs/todo.md` item
  that recorded the CUDA paths as never having been checked.

An empty findings list from a genuine review is a successful audit, and
manufacturing Minor findings to appear thorough is itself a defect in the audit
(Phase 17). §4 records the two things this pass nearly filed and shouldn't have.

## 2. Declared scope and coverage ledger

Declared before reading in depth. The file is 5,807 lines and 168 definitions;
claiming a full line-by-line pass would be the failure mode Phase 0 exists to
prevent, so the scope was differentiated by depth and its boundary stated.

### Read in full, line by line — 2,260 lines

| region | contents |
|---|---|
| l. 1–1502 | entry points, both collide drivers, the workspace/cache/timing structs, reclaim, slice gather/scatter, and **all six interaction routes**: async pair, batched-FFT pair, wavefront batched-FFT, fused Gaussian wavefront, indexed wavefront, node-indexed wavefront |
| l. 1502–2260 | `prepare_interaction`, the indexed-wavefront bounds prepare, `finish_interaction_indexed`, node grid build/prebuild/lookup, node interaction, all five kick launchers, the indexed node and pair kick kernels, the slice-pair Green cache, every grid helper, expand/realign, both `solve_field` entry points |

### Read in part, in pursuit of specific questions

- l. 2285–2317 (`solve_drifted_field_with_green_fft`), l. 3472–3700 (the whole
  luminosity block), l. 3873–3890 (`atan_ratio`, `kernel_integral`),
  l. 4263–4300 (CIC/TSC weights), l. 4558–4594 and 4709–4737 (kick kernels).

### Three mechanical sweeps — the whole file, 5,807 lines

1. **Mirrored-invariant sweep** — which CPU helpers are shared vs re-derived.
2. **`ρ = 1` blind-spot sweep** — per part 3 §10.6.
3. **`Core.Box` census** over lowered code — 288 methods, extending part 1 §3.

### Not covered, and why

Device kernels beyond those listed (l. 3700–5040, ~1,340 lines) — part 1 §9a
assessed the kernel layer as lower risk and part 3's evidence pointed at host-side
orchestration. The Gaussian sequential path and CUDA slicing (l. 5040–5810, ~770)
— a distinct subsystem that belongs with the unread `slicing.jl`. (The field solvers, l. 2252–3470, were named in Phase 0 as the extension target
if the sweeps came back quiet. They did, so the region **was** covered — see §7,
including its provenance note on which parts were read by sub-agents.)

### Honest total

**~3,470 of 5,807 lines (60%)** covered line by line — ~2,600 by me directly and
~870 by three sub-agents against briefed hypotheses, with the region settled
independently by measurement (§7.3). Plus three whole-file sweeps. Across parts
1–4, roughly **55% of `src/`** has been read line by line.

## 3. Areas checked and found sound

The substance of the pass.

### 3.1 The re-derived function pairs

The device cannot call host helpers, so `cic_weights`, `tsc_weights`,
`kernel_integral`, `atan_ratio` and `interpolate_kick` are duplicated. Compared
numerically over 200,000 randomised samples:

| pair | worst difference |
|---|---|
| CIC weights + base index | **0.000e+00** (bit-identical) |
| `kernel_integral` | **0.000e+00** (bit-identical) |
| TSC weights + base index | 1.110e-16 |

The TSC difference is deliberate and undocumented: CUDA computes the third weight
as `w3 = 1 − w1 − w2`, an exact partition of unity, where the CPU uses the closed
form. Both were derived by hand in part 3 §2.3 and both are correct.

**The S6 copied-bug hypothesis failed.** Part 2's S6 was an `UndefVarError: PI`
in the CPU `_pic_atan_ratio`'s on-axis branch. Its CUDA twin never carried it:
`atan_ratio(±1, 0)` returns `±π/2` on both, `(0,0)` returns 0 on both.

### 3.2 The `ρ = 1` blind spot does not recur

Part 3 §10.6's lesson — a check that cannot distinguish anything at `hx = hy` has
now produced two defects in `pic_cpu.jl` — was applied here. Four candidate sites
(the three `klum/(hx·hy)` luminosity scales and the Green normalisation
`−0.5/(hx·hy)`) are all per-axis. Tested against the **closed-form Gaussian
overlap** rather than against the CPU:

| aspect | analytic | CPU | CUDA | CUDA rel. error |
|---|---|---|---|---|
| 1:1 | 8.793091e+06 | 8.778681e+06 | 8.778681e+06 | −1.639e-03 |
| 11:1 | 8.771281e+07 | 8.756631e+07 | 8.756631e+07 | −1.670e-03 |
| 25:1 | 5.495682e+07 | 5.486676e+07 | 5.486676e+07 | −1.639e-03 |

Flat to the analytic value independent of aspect ratio, and CPU/CUDA identical to
printed precision.

### 3.3 The wavefront invariant, checked rather than assumed

This is the load-bearing argument for the whole CUDA scheme and it holds:

- **Within a wavefront batch no two pairs share a slice index.** So the
  progressively-updated states the CPU uses and the pre-batch states CUDA uses
  are *equivalent*, not merely close; and the `idx1`/`idx2` writes of different
  pairs cannot collide. Parity is therefore meaningful rather than coincidental.
- **All field solves for a batch complete before any kick launches**, so both
  directions read the un-kicked opposing slice — matching the CPU, where the
  source is an unmutated extract and the field a copy.
- **Luminosity is consumed before the kicks on every route.** Not a theoretical
  concern: the comment at l. 868–871 records the batched-FFT path being
  "measurably wrong (1.8e-4 relative)" before its fetch was moved.

### 3.4 The kick kernels reproduce the CPU term for term

All three (plain, node-indexed, pair-indexed) implement:
drift in with **old** momenta → `pz −= ¼(px²+py²)` with **old** → interpolate at
the drifted position → kick → drift out with **new** momenta →
`pz += ¼(px²+py²)` with **new**. Checked against `_pic_interaction!` and
`_pic_interaction_node!` line by line. Aliased in/out arrays are safe: each
thread reads and writes only its own element, read before write.

The node path additionally selects `gL = nc[j]`, `gR = nc[j+1]` and solves `phiZ`
on **gL's** mesh, which is what the theory note requires — `φ_L − φ_R` is a small
difference of large numbers whose discretisation error cancels only within one
mesh.

### 3.5 Concurrency

- **`Core.Box` census: 288 methods defined in `pic_cuda.jl`, 0 boxed.** Closes the
  `docs/todo.md` item recording the CUDA paths as unchecked for the part 1 §3
  class. Done on lowered code — a text sweep gave six false positives and missed
  a real case in part 1.
- **Four concurrent field streams are safe**: each gets its own
  `workspace.charges[k]`, and `phi`/`Ex`/`Ey`/FFT scratch are freshly allocated
  per call. No shared mutable state.
- **`_cuda_pic_add_time!`'s non-atomic accumulate is safe**: no yield point
  between `getproperty` and `setproperty!`, and the tasks are `@async`
  (cooperative, single-threaded), not `@spawn`.

### 3.6 Buffer reuse without re-zeroing

The fused Gaussian route reuses `lum` and `partials` across batches without
clearing them. Both are safe because every read is bounded — `lum[1:lum_offset]`
where each segment writes a contiguous, fully-covered range, and `partials` read
only up to `block_counts[c]`. Checked rather than assumed, because a stale-buffer
sum is exactly the kind of bug that survives a parity test if both backends do it.

### 3.7 Grid invariants are shared, not re-derived

All three CUDA grid-building sites call the shared `_pic_interaction_grids`, so
alignment, `grid_quantize` and `min_transverse_extent` are inherited. Part 3's S16
class (an option silently dropped by an alternative sizing path) does not recur
here.

## 4. Corrections to this audit's own analysis

Three, and the first two are the ones worth reading.

### 4.1 The "latent trap" was overstated — **withdrawn**

I reported that `_cuda_pic_interaction_wavefront_node_indexed!` (l. 1352–1364)
rebuilds the node cache *lazily* on a miss, which is precisely what both prebuild
docstrings forbid and which is recorded as having made CPU/CUDA disagree by
3.8e-5; and I framed it as a CUDA-specific latent trap.

**That framing is wrong.** The CPU has the identical structure:
`_pic_node_grid!` (`pic_cpu.jl:794`) → `_pic_build_node_grids!` with the same
`isempty(cache) || return cache` guard (l. 691), and `_pic_collide!` prebuilds
unconditionally (l. 58–60). The lazy call is a deliberate no-op guard on **both**
backends. It is not CUDA-specific and warrants no change — "fixing" it would mean
altering two identical structures for zero behavioural effect. It survives only as
a remaining risk (§5).

### 4.2 A near-miss: the beam-swap that wasn't

`_cuda_pic_launch_kick_pair_indexed!` orders its two argument groups by **opposite
conventions** — the `rep`/`idx` groups name the *recipient* beam, the plane groups
name the *producing* beam. So the first beam group pairs with the *second* plane
group. Reading the call site alone, this looks like the two beams' fields are
swapped, which would be a major physics error.

It is correct. Establishing that required tracing to
`_cuda_pic_kick_pair_indexed_kernel!` 2,700 lines away, where the pairing is
actually made (`idx2 ← phi12*`, `idx1 ← phi21*`), and confirming both wavefront
solvers fill planes identically.

This came within one step of being filed as a Major finding on the *production*
route. It is recorded because the near-miss is the useful part: the code was
right and the reading was wrong, and the only thing that would have caught a
premature report is the discipline of confirming before writing. A docstring now
states the pairing at the launcher.

### 4.3 `slices.weight` is not a dead field

I reported `weight` as a dead field. It is dead only in `pic_cpu.jl`'s
`param1`/`param2` **tuples** (built at l. 71–73, read nowhere). The underlying
`slices.weight` is live — the fused Gaussian wavefront route reads
`slices2.weight[j]` and `slices1.weight[i]` at `pic_cuda.jl:1147` and `1158`. The
dead thing is the tuple copy, which is cosmetic and left alone.

## 5. Remaining risks

- **Node-cache prebuild and lazy fallback are consistent by caller discipline
  only** (§4.1). Both backends prebuild unconditionally under `:node`, which is
  what makes the lazy path a no-op. A future caller that skips the prebuild would
  silently reintroduce a measured, documented defect. Symmetric across backends,
  so it is a design property rather than a bug.
- **`green_cache` is vestigial on the CUDA path.** Both producers return `nothing`
  unconditionally, so it is `nothing` everywhere while being threaded through ~20
  functions, and `_cuda_pic_cached_interaction_grids` is a pure pass-through. Dead
  parameter, live caching elsewhere (the slice-pair cache in the workspace).
- **Dead but correct code**: `_cuda_pic_wavefront_luminosity_batched` (65 lines) is
  reachable only through `_cuda_pic_batched_luminosity_enabled()`, a hardcoded
  `false` — a complete alternative implementation of a headline observable that no
  test has ever run. Executed directly for this audit: it agrees with the live
  path to 1.6e-15 at both round and 11:1. Left in place.
- **A float-association mismatch inside CUDA.** `_cuda_pic_prepare_interaction`
  computes the field drift as `x + px*half*(z−c)` while the CPU *and the CUDA kick
  kernel* both use `x + (0.5*(z−c))*px`. Multiplication is not associative, so the
  bounds are computed ~1 ulp from the drift actually applied. Harmless against a
  1.5-cell margin, but the two CUDA sites disagree with each other while both
  mirror the same CPU line.
- **The unread half.** l. 2252–3470 (field solvers, wavefront workspaces, Green
  stack builders) and the device kernels are not covered by anything but the three
  sweeps.

## 6. Handoff

### Done, do not redo

| area | state |
|---|---|
| `pic_cuda.jl` l. 1–2260 | **read in full**; zero defects |
| The six interaction routes | all read; the wavefront invariant verified rather than assumed |
| Re-derived CPU/CUDA function pairs | verified numerically equivalent, 200k samples |
| `Core.Box` class on CUDA | **swept, 288 methods, clean** — closes the `todo.md` item |
| The `ρ = 1` blind spot | tested against an analytic reference at three aspect ratios |
| CUDA luminosity | verified against the closed-form Gaussian overlap |
| The field-solver extension, **partially** | see §7 — ~400 of 1,220 lines, with an exact resume point |

### Next, in priority order

1. **`src/tasks/strongstrong/pic_cuda.jl` l. 3038–3430 — the quadratic routes.**
   *(This item was started; see §7 for what is already covered and §7.3 for the
   exact resume point and the question to carry in.)* Originally scoped as
   l. 2252–3470 — the field solvers,
   wavefront workspaces and Green stack builders. Phase 0 named this as the
   extension target if the sweeps came back quiet, and they did. It is also where
   the batched FFT plane bookkeeping lives, which §4.2 shows is the most
   error-prone part of this file to read.
2. `src/tasks/BeamObservers.jl` (1,446) — only l. 700–1030 read (part 2).
3. `src/knobs/Knobs.jl` (896) + `symbolic.jl` (285) — `symbolic.jl` was declared in
   part 2's scope and never reached.
4. `spectral.jl` (1,045) + `spectral_cuda.jl` (760) — untouched by any audit.

### Techniques that mattered

- **Test the shared thing against an external reference, not against the other
  backend.** Parity cannot see a defect both backends share — that is what S14
  was. Every check here that could be anchored to an analytic result (the Gaussian
  overlap, the closed-form kernels) was.
- **Randomised comparison beats reading for duplicated functions.** 200,000
  samples through both the CPU and CUDA weight functions took minutes and is worth
  more than any amount of side-by-side reading.
- **Confirm before filing.** §4.2 came within one step of a false Major finding on
  the production route.
- **A clean sweep is a deliverable.** The `Core.Box` census closing a standing
  `todo.md` item is worth as much as a defect would have been, and it is only
  worth anything because it is recorded with its method count.

---

# 7. Extension — the field solvers (l. 2252–3470), now complete

§6 named this region as the next target. It is now **covered in full**.

**No defects.** Two non-defect findings, both fixed, in §8. No `src/` behaviour
changed anywhere in this region.

> **Provenance, because the ledger has to be checkable.** l. 2252–2625 and
> 2858–2952 were read by me directly. l. 2625–2858, 2947–3038, 3038–3470 and the
> deposit/Green device kernels were read by **three sub-agents** working disjoint
> regions against briefs that specified the hypothesis, the known-good pattern to
> compare against, and a requirement that every claim carry a `file:line`. Their
> reports are corroboration, not primary evidence — §7.4 is the measurement that
> actually settles the region, and it was run independently of all three. Where an
> agent raised something, I re-derived it before accepting or rejecting it; two of
> their three flagged items are dismissed in §7.5 with reasons.

## 7.1 The hypothesis being tested

§4.2 identified the batched-FFT **plane bookkeeping** as the most error-prone
thing in this file to read: which plane index holds which field, and whether the
deposit, the Green stack, the per-plane cell size and the kick all agree on it.

It is a good hypothesis because it is the one class a parity test is weak
against. A plane mix-up that is *symmetric* between the two backends would agree
at 1e-13 while being wrong — exactly S14's shape. And unlike S14 there is no
shared helper to anchor on: each backend lays out its planes independently.

## 7.2 Covered, and what makes it right

| lines | function | verdict |
|---|---|---|
| 2252–2337 | `solve_field_with_green_fft`, `solve_drifted_…` | sound (read in the part-4 pass) |
| 2337–2392 | `solve_pair_fields_batched_fft!` | sound |
| 2392–2427 | `allocate_wavefront_workspace` | sound |
| 2428–2483 | `wavefront_workspace!` | sound |
| 2484–2495 | `reserve_wavefront_workspaces!` | sound |
| 2496–2546 | `wavefront_node_workspace!` | sound |
| 2547–2625 | `solve_wavefront_fields_node_indexed!` | sound |
| 2858–2952 | `copy_green_spectral_stack!`, `build_wavefront_green_fft!`, `green_plane_params!` | sound |

**The node route is the model to compare the rest against.** It documents its
layout and then drives both the deposit and the Green copy from the *same* tuple,
so the two cannot drift apart:

    +1 dir1 L  sL1 gL1    +4 dir2 L  sL2 gL2
    +2 dir1 R  sR1 gR1    +5 dir2 R  sR2 gR2
    +3 dir1 Z  sR1 gL1    +6 dir2 Z  sR2 gL2

- Deposit `specs` (l. 2583–2590) and Green-stack copy (l. 2609–2611) carry
  identical `(plane, mesh)` pairings.
- `hx_host[plane]` comes from the mesh that plane was *actually* deposited on
  (l. 2596–2597), so the field derivative uses the matching cell size per plane.
- Plane +3 (Z) sits on **gL**, same as +1 (L) — the physics requirement, since
  `φ_L − φ_Z` is a small difference of large numbers whose discretisation error
  cancels only within one mesh.
- The kick call (l. 1416–1428) reads `+1,+1,+1,+2,+2,+3` as
  `phiL, ExL, EyL, ExR, EyR, phiZ` — matching the layout exactly.

**The design decision that removes the risk**, per the workspace docstring
(l. 2496–2509): node mode allocates **one Green per plane** and duplicates gL
into the L and Z slots, so the spectral multiply is a 1:1 elementwise product
with no mapping to get wrong. Where the mapping *is* non-uniform — the 4-plane
route, 4 charge planes over 2 Greens — the caller passes the correct Green
explicitly per plane (l. 2855–2859) rather than deriving it arithmetically.

**Guarded, not assumed**: `wavefront_workspace!` hard-validates
`nplanes % 4 == 0` and the node one `% 6 == 0`. A 6-plane request against the
4-plane allocator throws rather than silently mis-sizing `npairs = nplanes ÷ 4`.
That was the first suspicion of this stretch and it is explicitly defended.

**S14/S17 cross-check**: the `:lattice` branch of `build_wavefront_green_fft!`
(l. 2914–2931) calls `_pic_green_lattice!` per plane on host grids arriving
either straight from `_pic_interaction_grids` or through the realigned
`_cuda_pic_slice_pair_cached_prep!`. Both are aligned, which is why part 3's new
integrality guard does not fire here; the `:lattice` testset exercises both.

## 7.3 What settled it: measurement, not reading

Reading a plane layout is exactly the kind of check §4.2 already showed I can get
wrong. So the region was settled by measurement first.

**The argument.** A plane-bookkeeping error is normally the class parity is
weakest against — but only when *neither* side is independently verified. Here:

1. The CPU quadratic basis is independently verified — hand-derived in part 3
   §2.6, plus `test/runtests.jl` checks for partition of unity, boundary
   collapse, and the mid-slice reduction to the two-node form.
2. **The plane layout is CUDA-only.** The CPU has no planes; it uses separate
   workspace buffers. So there is no shared structural decision for both backends
   to get wrong together — which is precisely what made S14 invisible.
3. Therefore CPU/CUDA parity *is* decisive here, provided it discriminates.

**Measured noise floor** — every CUDA route against the CPU reference, same beams:

| route | 4-plane (linear) | 6-plane (quadratic) |
|---|---|---|
| indexed wavefront (production) | 1.113e-15 | 9.890e-16 |
| gathered wavefront | 1.246e-15 | 8.999e-16 |
| wavefront, no wavefront-FFT | 1.572e-15 | (rejected by design) |
| sequential batched FFT | 1.113e-15 | 1.389e-15 |
| sequential async, 4 streams | 1.113e-15 | (rejected by design) |
| sequential plain | 1.113e-15 | (rejected by design) |

**Measured signal** — what a disturbance at each level does to the same
observable:

| disturbance | magnitude |
|---|---|
| interpolation scheme changed (linear -> quadratic) | 1.481e-05 |
| mesh changed (`green_cache=:none`) | 3.350e-04 |
| which beam receives which field | 3.282e-02 |

So any plane-level error lands **10 to 13 orders of magnitude** above the floor.
The existing suite asserts only `rtol=1e-11` (l. 5301-5313); the actual agreement
is machine precision. The three sub-agent traces then independently confirmed the
mapping by reading, which is corroboration on top of this, not the basis for it.

## 7.4 The plane layouts, as traced

Recorded so a future change can be checked against them rather than re-derived.

**6-plane (node and quadratic), `o = 6(n-1)`** — one Green per plane, so the
spectral multiply is 1:1 and there is no mapping to get wrong:

    node:       +1 L sL1 gL1   +2 R sR1 gR1   +3 Z sR1 gL1   (+4..+6 dir 2)
    quadratic:  +1 L sL   +2 M sM=(sL+sR)/2   +3 R sR        (+4..+6 dir 2)

Quadratic duplicates each direction's Green into all three of its slots
(`k in 1:3` writing `o+k` and `o+3+k`), so its duplication factor is 3 where
node's is 2 — the question §7.3 of the previous revision posed, answered yes.
Both fill `hx`/`hy` for all six planes from the mesh each plane was deposited on.

**4-plane (linear), `o = 4(n-1)`, greens `g = 2(n-1)`**: `+1,+2` from beam 1 at
`prep12.sL/sR` -> green `g+1`, kicking beam 2; `+3,+4` from beam 2 at
`prep21.sL/sR` -> green `g+2`, kicking beam 1. Here the plane->Green map is
*arithmetic* (`plane0 ÷ 2 + 1`) and `@inbounds`, which the node route's docstring
explicitly says it avoided for that reason. Depths match exactly today.

## 7.5 Sub-agent claims I did not accept

Two of the three flagged items dissolve on checking, which is why agent output is
treated as a lead rather than a finding:

- **"The CUDA path has no dropped-particle accounting."** True as stated — the
  CPU's `dropped` counter (part 3 S15) has no CUDA equivalent. But it cannot
  matter: `_require_cuda_pic_options` (`pic_cpu.jl:311-315`) rejects every
  `grid_extent` but `:extrema` on CUDA, and `:extrema` covers every particle by
  construction. Nothing can be dropped, so there is nothing to count. Not a gap.
- **"`hx` is taken from `source_grid` while `phi` lives on `field_grid`."** Real
  observation, wrong conclusion that it is benign-by-luck. It is benign by an
  *invariant*, and the invariant deserved a test rather than a shrug — see §8.1.

The third (the `:lattice` per-plane host build) was already covered by part 3's
S17 work and needed no action.

## 7.6 Resume here — CLOSED

Unread, in the order a next session should take them:

| lines | function | why it matters |
|---|---|---|
| **3038–3430** | `copy_green_spectral_stack_quadratic!`, the two quadratic solvers, the two quadratic interaction routes, `apply_indexed_quadratic_kick!` + kernel + launcher | **Start here.** This is `slice_interpolation = :quadratic`, and it is the one layout that has *not* been checked against the discipline in §7.2 |
| 2743–2858 | `solve_wavefront_fields_indexed_batched_fft!` | the production route's solver body; only its plane-fill loop has been seen, via grep |
| 2625–2743 | tail of the node solve, `solve_wavefront_fields_batched_fft!` | same, plane-fill loop seen only via grep |
| 2952–3038 | `apply_green_plane!`, the three `deposit_drifted_*_plane*` helpers, `multiply_spectral_perplane_kernel!` | the primitives all of the above call |
| 3430–3470 | `green_fft`, `build_green_fft` | small |

### The specific question to carry into the quadratic routes

Quadratic uses **6 planes per pair** (L/M/R per direction) and borrows the
**node** workspace — which allocates one Green per plane. But unlike node mode,
all three planes of a quadratic direction share **one** `source_grid`: the
docstring in `pic_cpu.jl` justifies this by noting the drifted coordinate
`x + px·s` is affine in `s`, so the sL/sR bounding box already contains the
midpoint plane and no resizing is needed.

So the duplication factor is **3, not 2**, and the borrowed workspace was sized
for a different grouping. The questions are:

1. Does `copy_green_spectral_stack_quadratic!` (l. 3038) duplicate each
   direction's Green into all three of its slots?
2. Are `wf.hx[plane]`/`hy[plane]` filled for all six planes, given all three of a
   direction share one mesh?
3. Does the kick (`apply_indexed_quadratic_kick!`, l. 3355) read planes in the
   order the solver filled them?

Compare against §7.2's node layout, which is the known-good pattern.

### What would make this cheap to settle

The CPU has an independent quadratic implementation
(`_pic_interpolate_kick_quadratic`, verified by hand in part 3 §2.6: basis
`2t²−3t+1, 4t−4t², 2t²−t` summing to 1, derivative weights summing to zero). The
parity test covers `slice_interpolation = :quadratic`, so a plane mix-up that is
*asymmetric* between backends is already excluded. What remains to check by
reading is a mix-up that is symmetric — which, per §7.1, is the only kind that
survives parity, and is precisely what S14 was.

---

# 8. Two non-defect findings, both fixed

Neither is a wrong answer today. Both are cases where a correct result rests on
something unstated and untested, which is the shape every confirmed defect in
parts 3 and 4 turned out to have.

## 8.1 An invariant the field derivative depends on, and nothing tested

`E = −∇φ` is differenced with a cell size taken from the **source** grid — the
CPU's `_pic_solve_drifted_field_with_green_fft!` passes
`source_grid.width/(nx−1)` into `_pic_field!`, and the CUDA wavefront solvers
fill `hx[plane]` the same way. But `φ` is *interpolated* on the **field** grid:
`_pic_interpolate_kick` uses `grid.width/(nx−1)` with the field grid.

Those two spacings are only equal because `_pic_interaction_grids` returns the
same `width`/`height` for both grids, differing in origin alone
(`pic_cpu.jl:1010-1011, 1019-1020`).

This is S14's shape exactly — established by one function, silently depended on
by another twenty lines away — with one aggravating difference: **both backends
take the spacing from the source grid.** A divergence would make CPU and CUDA
wrong *identically*, so the parity argument that settles the rest of §7 could not
see it. That is the one hole in §7.3's reasoning, and it was worth closing.

Measured across the option cross-product — three green types × quantize on/off ×
min-extent on/off × four deliberately asymmetric box pairs, at three stages each
(as produced, after the Green cache's expansion, after part 3's realignment):
**0 violations**, with a negative control confirming the equality is a real
constraint rather than trivially true.

**Fixed** by a regression test asserting the invariant directly rather than any
output — 338 assertions. It would have caught S14's sibling had it existed.

## 8.2 A green test run that says nothing about the GPU

Nine testsets are gated behind `_HAS_CUDA && CUDA.functional()`. **Three carry an
`else @test_skip`; six are silent.** And CI (`.github/workflows/ci.yml`) runs on
`ubuntu-latest` with no GPU — the job is honestly named "Julia 1.12 CPU smoke
tests", but the consequence is that on CI *every* CUDA test is skipped while the
run still reports `Testing Octopus tests passed`.

That matters more than it looks, and §7.3 is why. The correctness argument for
`pic_cuda.jl` — 5,807 lines, and the production backend per the benchmark
histories — rests almost entirely on CPU/CUDA parity: the CPU side is
independently verified, the CUDA plane layout has no CPU counterpart, and the
measured residual is ~1e-15 against a ~1e-5 signal. Remove the parity tests and
that argument evaporates. Silently.

This session is a live example. S14 and S17 both changed `pic_cuda.jl`. On a
GPU-less machine the parity tests would not have run, and the suite would have
gone green anyway.

`AGENTS.md` already states the rule for contracts — "Use `status=:skipped` for
unavailable resources such as a missing CUDA device; do not report an unrun check
as passed." This is the same rule applied to the suite.

**Fixed** with a `CUDA coverage status` testset at the top of `test/runtests.jl`:
`@test_skip` plus an `@info` naming what did not run, so the skip is visible in
the summary instead of having to be inferred from assertion counts. Deliberately
one top-level notice rather than six `else` branches — the gate at l. 5077 spans
700+ lines, and matching `if`/`end` across that by hand is how you introduce a
defect while fixing a reporting gap.

---

<a id="part-5"></a>

# Comprehensive Audit — 2026-08-03, part 5

> ## Start here
>
> | read | why |
> |---|---|
> | **§3** | S18, the one confirmed defect: a public CUDA tuning surface that is completely inert on the bare `collide!` path — 0 launch receipts against 12 through a task |
> | **§4** | the tree-reduction orphaning analysis, and why the invariant that saves it is held by an unasserted literal in a different function from its two guards |
> | **§5** | areas checked and found sound — the bulk, including a byte-identical three-way kernel comparison |
> | **§6** | agent claims rejected, and one correction to part 1's record |
>
> §2 is the coverage ledger, and it is the section to read sceptically: most of
> this region was read by **sub-agents**, not by me, and it says which.

Fifth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
extending part 4 to the CUDA **device kernels**, `pic_cuda.jl` l. 3470–5040.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S18 | Moderate | `CUDAPICLaunchConfig` is **silently inert** on a bare `collide!` — every launch family falls back to a fixed 256 and the device max-threads validation never runs. Both the PIC and the composed GaussianPIC routes. | fixed (now warns), verified |
| V1 | verification gap | the luminosity tree reduction's power-of-two guard — two `ispow2` validations, **neither exercised by any test** | fixed, verified |

S18 is audit part 2's **S1 all over again**: a public performance-tuning surface
that does nothing, on a documented public API. S1's evidence was "0 receipts →
56"; this one measures **0 receipts on the bare path against 12 through a task**,
with the identical solver and configuration.

The difference is instructive. S1 was a dispatch bug — an `isa` test that missed a
composing type. S18 is not a bug in any function: `_with_solver_execution_configuration`
correctly installs the scoped configuration, and its only caller is the task
path. The configuration is inert because of **where the resolution lives**, and
nothing on the `collide!` path was obliged to notice.

## 2. Declared scope and coverage ledger

### Region: `pic_cuda.jl` l. 3470–5040 (~1,340 lines), the device kernels

Read by **four sub-agents** on disjoint regions, each given a *different*
hypothesis rather than a generic brief, plus the known-good reference to compare
against and a requirement that every claim carry a `file:line`:

| agent region | hypothesis it was given |
|---|---|
| field-derivative kernels (3 variants) | must reproduce the CPU `_pic_field!` in all four stencil cases, both axes, including signs and the fourth-order fallback rings |
| bounds reduction + gather/scatter | tree-reduction orphaning; neutral elements; whether the block **cap** drops particles |
| interpolation + kick appliers | the `Kz` unweighted-difference asymmetry, and old-vs-new momenta in the two `0.25(px²+py²)` brackets |
| luminosity + spectral multiplies | the power-of-two tree reduction, and whether its validation covers **every** path |

### Read by me directly

The power-of-two reachability question (§4), which is the crux of the fourth
brief, was settled by me independently — by experiment, before the agent
reported. The S18 confirmation (§3) is likewise my own measurement, not an
agent's claim.

### Provenance, stated plainly

Most of this region was **not** read by me line by line. The Absolute Rules
require the ledger to make coverage claims checkable, so: the four agent reports
are the evidence for §5, each carries `file:line` citations, and every item any
agent flagged was re-derived by me before being accepted or rejected (§6 records
two rejections). Where a conclusion rests on measurement rather than on reading,
§3 and §4 say so.

### Honest total

`pic_cuda.jl` is now covered to l. 5040 — **~87%**. Remaining: the Gaussian
sequential path and CUDA slicing, l. 5040–5810 (~770), which belong with the
still-unread `slicing.jl`.

## 3. S18 — a tuning surface that is inert on one of its two paths

`CUDAPICLaunchConfig` is documented as "Optional CUDA-only PIC launch overrides.
`nothing` inherits the thread count from `CUDAExecutionPolicy`." Nothing in that
docstring hints that the object is inert unless routed through a task.

`_cuda_pic_threads` (`interface.jl`) has three exits:

```julia
config = _ACTIVE_CUDA_PIC_LAUNCH_CONFIG[]
config isa ResolvedCUDAPICLaunchConfig || return 256      # <- the third exit
```

The scoped value is installed by `_with_solver_execution_configuration`, whose
**only caller is the `StrongStrongTask` path**. A bare
`collide!(solver, beam1, beam2, CUDABackend)` never enters it.

### Evidence

Identical solver carrying `CUDAPICLaunchConfig(kick_threads=64,
deposition_threads=64, field_threads=64)`, counting `:cuda_pic_launch` receipts:

| path | receipts | threads seen |
|---|---|---|
| bare `collide!` | **0** | — configuration never reached the device |
| via `StrongStrongTask` | **12** | {64, 128} |

Two consequences, not one: the user's overrides are discarded for **all seven
families**, and `_resolve_cuda_pic_configuration`'s device
`MAX_THREADS_PER_BLOCK` validation is skipped along with them.

### Fixed

The path cannot simply honour the configuration — resolution needs a
`ResolvedCUDAExecutionPolicy` to inherit from, and a bare `collide!` has no
policy at all. Inventing a default would be a design change, not an audit fix. So
it is made **loud** instead: `_warn_inactive_pic_launch_config` fires exactly when
a configuration exists and cannot be installed, and records an
`:inactive_path` execution receipt — mirroring the `:inactive_backend` receipt
`_with_solver_execution_configuration` already emits for the reverse case.

Wired into both CUDA routes. The GaussianPIC one matters: the predicate goes
through `_pic_launch_solver`, which is precisely the dispatch fix part 2's S1
introduced so the composing type is not missed. A test asserts the hybrid warns,
so S1's shape cannot return here.

## 4. The tree reduction, and an invariant held by an unasserted literal

`_cuda_pic_luminosity_overlap_partials_kernel!` reduces with the strict-halving
form:

```julia
step = CUDA.blockDim().x ÷ 2
while step >= 1
    if tid <= step; shared[tid] += shared[tid + step]; end
    CUDA.sync_threads(); step ÷= 2
end
```

Each stage covers indices `1 … 2·step`, which equals the live range only while
that range is even. Whenever `step` is odd, `step ÷= 2` truncates and index
`step` — already holding a partial sum — is never read again.

Worked at `blockDim = 100`, sequence `50, 25, 12, 6, 3, 1`: the `step=12` stage
orphans `g[25]`, and `step=1` orphans `s[3]` (eight groups). The final sum
carries **64 of 100 elements**; luminosity comes out low by a data-dependent
factor near 0.64, with no error, no NaN and no bounds violation.

### Is it reachable? Measured, exhaustively — no

| path | `:luminosity` threads |
|---|---|
| bare `collide!`, no configuration | 256 (pow2) |
| policy threads 32 / 64 / 128 / 256 / 512 / 1024 | inherited unchanged, all pow2 |
| policy threads 96 / 192 / 320 / 100 / 224 | **rejected at resolution** |
| policy 96 + explicit `luminosity_threads=64` | 64 — the override rescues it |

Two guards do the work: the `CUDAPICLaunchConfig` constructor (`ispow2(lum)`) and
`_resolve_cuda_pic_configuration` (`ispow2(resolved.luminosity)`). No
non-power-of-two value reaches the kernel on any path.

### V1 — but neither guard was tested

A repo-wide grep for `luminosity_threads`, `ispow2` or "power of two" in
`test/runtests.jl` returned **nothing**. Both validations could have been deleted
and the suite would have stayed green, while the consequence is a silently wrong
luminosity — the number a beam-beam code is judged on. That is part 1's "checks
that exist and are never executed", guarding a headline observable.

**Fixed** with a test asserting the constructor rejection (host-side, no GPU
needed), the inherited-policy rejection, the override rescue, and that the
fallback is a power of two.

**One residual risk, recorded not fixed.** On the bare path the invariant holds
only because the literal `256` happens to be a power of two — and that literal
lives in a different function from both guards, with nothing tying them together.
Changing it to 192 or 768 (both plausible occupancy tunings, both ≤ 1024, both
passing every other constraint in sight) would silently break the reduction. The
robust fix is to make the reduction size-agnostic, in the style of the moment
reduction elsewhere in the same file which uses `offset = (active+1)÷2` and drops
nothing at any block size. That is a change to working code with no confirmed
defect behind it, so it is left as a recommendation.

## 5. Areas checked and found sound

- **The three field-derivative kernels are textually one kernel.** After
  normalising the element-type alias and the plane subscript, the three stencil
  blocks are **byte-identical** (verified by `diff`, 22 lines each, zero
  differences). All four CPU cases — interior 2nd, interior 4th, first-ring
  fallback, boundary one-sided — match term for term in both axes, with the
  negative-gradient sign consistent in every branch.
  - The CPU's explicit `nx >= 5` / `ny >= 5` gate has no CUDA counterpart, but
    the range test `j >= 3 && j <= ny-2` is **self-guarding** and selects the same
    branch at every size including the unreachable `ny = 4`. Not a defect.
  - `c4` is bit-identical despite different construction (`T(1)/T(12)` vs
    `typeof(hy)(1/12)`): 1/12's repeating mantissa never produces a
    round-to-nearest tie, so the double rounding is harmless.
- **The bounds reduction's block cap drops nothing.** `blocks = min(cld(n,
  threads), block_cap)` looks like truncation but the kernel is a grid-stride
  loop bounded by `length(idx)` with `stride = gridDim·blockDim` computed from
  the *actual* launched grid, so every element is visited exactly once. The
  complementary half holds too: the partials array is fully re-initialised each
  launch, and slots for blocks that never launched hold ±Inf.
- **Neutral elements are ±Inf, never 0.0.** Checked on every path. A `0.0`
  neutral in a min/max reduction would silently clamp the bounding box to include
  the origin — a real defect, and it does not occur.
- **The block reduce does not require a power of two**, only `blockDim % 32 == 0`:
  it pads the cross-warp stage with `lane <= nwarps ? shared[row,lane] :
  neutral[row]`, so 3 or 5 warps reduce correctly. Its thread counts (256 and 64)
  are hardcoded and deliberately bypass the configurable path.
- **`Kz` is the unweighted `phiL − phiR` difference** in both stencils on both
  backends — the asymmetry most likely to be transcribed wrongly, transcribed
  correctly.
- **The drift/kick/drift sequence** matches the CPU term for term including the
  critical old-vs-new momentum split in the two `0.25(px²+py²)` brackets, in all
  five kick kernels.
- **Node mode uses the correct mesh per plane**: L on gL, R on gR, and the
  longitudinal pair `phiL`/`phiZ` both on gL.
- **Gather/scatter is an exact inverse permutation**, and the mask compaction's
  *inclusive* `cumsum` is the right choice — an exclusive scan is where the
  off-by-one would be.
- **All four spectral-multiply kernels** map planes to Greens correctly; the
  ragged tail is handled by zero-filling before the barrier rather than an early
  `return`, which would have deadlocked it.
- **The wavefront luminosity kernel excludes the guard row/column**, matching the
  CPU's `for j in 1:ny, i in 1:nx` over an `(nx+1, ny+1)` array.

## 6. Claims rejected, and a correction to part 1

Agent reports are leads, not findings. Three items were dismissed after
re-derivation:

- **"The CUDA path has no dropped-particle accounting."** True as stated, cannot
  matter: `_require_cuda_pic_options` rejects every `grid_extent` but `:extrema`
  on CUDA, and `:extrema` covers every particle by construction.
- **"`hx` comes from `source_grid` while `phi` lives on `field_grid`."** A real
  observation with the wrong conclusion — it is safe by an *invariant*, not by
  luck, and that invariant is now tested (part 4 §8.1).
- **Several "latent fragility" notes** — a kernel without a grid-stride loop, a
  missing `n == 0` guard, dead `phi` parameters. All correct observations, all
  unreachable today, none warranting a change to working code.

### Correction to part 1's record

Part 1 states that the luminosity kernel "is fed by `_cuda_pic_threads(:luminosity)`,
and `interface.jl:112` and `:185` validate that family with `ispow2` at both
construction and inheritance resolution."

That is **incomplete**: it names two of the three exits from `_cuda_pic_threads`
and omits the fallback `return 256`, which neither guard covers. The conclusion
part 1 drew is still correct — no bad value reaches the kernel — but for a reason
it did not state, and the omitted exit is exactly where S18 lives. Recorded here
rather than edited into part 1, per the rule that a correction sits beside the
original.

## 7. Handoff

### Next

1. **`pic_cuda.jl` l. 5040–5810** — the Gaussian sequential path and CUDA
   slicing, the last ~13% of the file. Take it together with **`slicing.jl`
   (704)**, which is unread and is the CPU counterpart.
2. `BeamObservers.jl` (1,446) — only l. 700–1030 read (part 2).
3. `Knobs.jl` (896) + `symbolic.jl` (285) — declared in part 2's scope, never
   reached.
4. `spectral.jl` (1,045) + `spectral_cuda.jl` (760) — untouched by any audit.

### Recommendation carried forward

Make the luminosity overlap reduction size-agnostic (§4). It removes a live
constraint rather than documenting one, and the pattern already exists in this
file.

### What worked here

- **Give each agent a different hypothesis, not a generic brief.** The four
  briefs named the specific failure mode, the known-good reference, and demanded
  `file:line`. The one that found S18 was the one told to ask "does the
  validation cover *every* path?" rather than "check this region".
- **Settle the crux yourself.** The power-of-two reachability and the S18
  receipt count were both measured independently before the relevant agent
  reported. Agent output then corroborated rather than being trusted.
- **Count receipts, not lines.** S1 and S18 were both found the same way: ask
  what the device actually *did*, not what the configuration said it should do.

---

<a id="part-6"></a>

# Comprehensive Audit — 2026-08-03, part 6

> ## Start here
>
> **This pass found more than the previous three combined, and most of it is not
> fixed.** Read §1 for the split between what was confirmed-and-fixed and what is
> confirmed-by-an-agent-but-not-yet-by-me.
>
> | read | why |
> |---|---|
> | **§1** | the ledger: two fixed, twelve recorded, and why the line falls there |
> | **§2** | S20 — a CUDA/CPU divergence of a **factor of 100** under a supported mode |
> | **§5** | the twelve recorded findings, each with its reproduction, for the next session to verify and fix |
> | **§8** | the follow-up: four of the twelve settled in-session — one fixed, one rejected, one whose stated reason was wrong |
> | **§6** | provenance and the agent hit rate — roughly 60%, which is why §5 is not presented as settled |

Sixth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
covering `slicing.jl`, the CUDA slicing and Gaussian sequential paths,
`BeamObservers.jl`, `Knobs.jl` + `symbolic.jl`, `spectral.jl` and
`spectral_cuda.jl` — roughly **6,000 lines**, read by six sub-agents on disjoint
regions.

> **A note on this ledger's own history, because it was wrong twice.** The
> `spectral.jl` agent was interrupted; I recorded the file as uncovered and said
> so. It then resumed and completed. So `spectral.jl` **is** covered, and the
> intermediate claim that it was not is itself corrected here rather than edited
> away — the same rule this series applies to its technical conclusions.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S20 | **Major** | the CUDA spectral Dirichlet box ignored `allow_lost_particles`; CPU 1.589e-3 vs CUDA 1.592e-1 half-width — **a factor of 100** | **fixed, verified by me** |
| S19 | Minor | `_nonfinite_coordinate_error` reported "0 of N macroparticles have a non-finite coordinate" — asserting what its own scan had just disproved | **fixed, verified by me** |
| R1–R12 | Major → Minor | twelve further findings (§5) | **confirmed by an agent, NOT independently verified, NOT fixed** |

### Why the line falls there

Two findings were reproduced by me directly and fixed. The other eight are
recorded with their reproductions and left for the next session.

That is a deliberate stopping point, not an omission. This session's measured
agent hit rate is roughly **60%** (§6): of the claims agents have raised across
parts 4–6, several dissolved entirely on checking — one because the CPU had the
identical structure, one because the option it worried about is rejected on that
backend anyway. Fixing eight unverified findings in sequence, at the end of a
long session, would be exactly the failure mode the protocol's "confirm before
you modify" gate exists to prevent. §5 gives the next session everything needed
to verify each in minutes.

## 2. S20 — a factor of 100, under a documented supported mode

The spectral Dirichlet box is sized from **whole coordinate arrays**, not from
slice membership. The CPU knows this and says so (`spectral.jl`, `_masked_rms` /
`_masked_ext` docstring):

> "unlike the PIC meshes it is built from whole coordinate arrays rather than
> from slice membership — so the mask that slicing applies for free does not
> reach here and has to be explicit."

The CUDA re-implementation was written with unconditional reductions:

```julia
rms(v) = begin n = length(v); m = sum(v) / n; sqrt(sum(abs2, v .- m) / n) end
ext(v) = maximum(abs, v)
```

### Evidence

Four particles marked dead (`pz = NaN`) carrying **finite but far-out**
coordinates at `|x| = 1e-1`, under `allow_lost_particles()`:

| | half-width |
|---|---|
| CPU `_spectral_box` | 1.5894818318553923e-3 |
| CUDA `_cuda_spectral_box` | **1.5920521973915616e-1** |
| relative difference | **9.9e+01** |

Every slice pair then sees a different mesh, so every kick differs. The path is
*half*-masked, which is what makes it insidious: `_cuda_longitudinal_slices` does
drop the dead from `slices.indices`, so they never deposit and never get kicked.
Only the box is wrong.

A second consequence: a dead particle carrying `NaN` in `x` or `y` makes the box
non-finite and raises `_nonfinite_coordinate_error` — which that function's own
docstring says cannot happen under the flag, because "the reductions upstream of
every caller skip it". CPU proceeds; CUDA throws.

### Fixed

`_cuda_masked_rms` / `_cuda_masked_ext`, using the same `ifelse.` masking idiom
as `_cuda_live_z_stats` in `pic_cuda.jl` — a dead entry contributes the
reduction's neutral element, so a NaN it carries can never reach the accumulator.
Applied to both the plain and the drifted box.

Post-fix, measured: clean beams **0.000e+00**, with dead particles **1.364e-16**,
for both boxes. Fail-fast preserved and verified in both directions — a NaN in
`x` with the flag **off** still throws; the same NaN on a particle marked dead
with the flag **on** is masked out and the box is finite.

### Why it hid

The CPU lost-particle test covers `SpectralPoissonSolver`. The CUDA
lost-particle test covers only moments and slicing. The CPU/CUDA spectral parity
test never enters `allow_lost_particles`. Two supported features, each tested
alone, never tested together — the cross-product shape `docs/todo.md` names as
"the shape to look for", and the fourth time this series has found it.

## 3. S19 — a diagnostic that asserted what its own scan disproved

Called with entirely finite input, `_nonfinite_coordinate_error` threw:

> `0 of 3 macroparticles have a non-finite coordinate; first at index 0 with .`

An error asserting a fact it had just disproved, with an empty detail and a
nonsense index, sending the reader to the particle array when the fault is
upstream of it.

**The agent found this on the CUDA fused wavefront path. It is broader.** The
callers fire on a non-finite *derived* quantity, and a drifted position
`x + px·s` can overflow to `±Inf` from perfectly finite `x` and `px` when the
drift is large — so it is reachable on **CPU** too, for a completely different
reason than the one reported. The new message names both causes.

It also absorbs the agent's second confirmed finding — that the wavefront guard
can blame beam 1 for beam 2's moments, because the kick crosses beams. The
message now says the beam it names need not be the beam at fault. Restructuring
the wavefront check to attribute correctly would be a design change on a hot
path with no wrong physics behind it.

## 4. Areas checked and found sound

- **The symbolic differentiator is correct.** All 24 rules independently derived;
  68 finite-difference cases in the live package to ≤2.9e-11; cross-checked
  against Symbolics.jl's `expand_derivatives` on 12 expressions to ≤5e-15. The
  single most likely place for a silent wrong gradient — constant-exponent vs
  variable-exponent `^` — is correctly separated, including the constant-base
  case where the spurious `log(a)` term folds away. The five non-smooth
  operations (`sign`, `min`, `max`, 2-arg `log`, 2-arg `atan`) all refuse with a
  directed error rather than returning something wrong.
- **The Gaussian moment reductions use the safe form**, `offset = (active+1)÷2`,
  not the strict-halving form that part 5 showed drops 36 of 100 elements. Since
  `CUDALaunchConfig(threads=100)` genuinely produces a 100-thread moment block,
  that choice is load-bearing — and correct.
- **`slicing.jl` is clear of the `Core.Box` class** that once corrupted its
  default `:equal_area` boundaries: 0 boxes across all 40 methods, checked on
  lowered IR. Boundaries, weights, centers and index sets are **bit-identical at
  1, 4, 8 and 16 threads** across 12 configurations.
- **Every spectral CUDA transform derived from scratch** and matched: the
  odd/even extensions, both `rfft` sizings, the spectrum-index extraction, and
  both scale foldings; the DST/DCT equivalences are algebraic identities, not
  approximations.
- **No observer field is entirely unread** — every constructor-facing field of
  every observer type reaches a runtime consumer, with a `file:line` for each.
- **The spectral solve is mathematically correct, verified independently.** The
  agent derived the Dirichlet eigenfunction solution, the RODFT00/REDFT00
  normalisation factors and both field scales from scratch, then checked the
  solver against an explicit `O(Nx*Ny)` continuum mode sum it wrote itself — on a
  deliberately **anisotropic 13x21 grid**, agreeing to **2e-15 relative** on Phi,
  Ex and Ey for both `:grid` and `:grid_free`. Cross-checked against the audited
  PIC solver: per-particle correlation 0.9996 (px), 0.9996 (py), 0.9992 (pz).
  Sign included. This closes the largest unaudited block of mathematics in the
  repository.
- **The one `Core.Box` in `spectral.jl` is confirmed benign**, upholding part 1's
  judgement rather than merely repeating it: the closure only *reads* `luminosity`
  (through `typeof`), the write is outside the `do` block, and
  `_run_logical_workers` is `@sync`-joined. Verified end to end — bit-identical
  luminosity and coordinates across 6 repeats at 8 threads, and between 1 and 8
  threads. The latent hazard is now named: the natural refactor
  `luminosity += local_lum` *inside* the closure would reproduce the
  `_threaded_histogram` defect exactly, and no current test would catch it.
- **Lost-particle masking in the moment observers** is correct on both backends,
  including the ordering subtlety that the CUDA path must zero the dead *after*
  forming the product because dead coordinates are non-finite.

## 5. Recorded, not fixed — the next session's work

Each is agent-confirmed with a reproduction. **None has been independently
verified by me.** Verify first, then fix.

| # | severity | finding |
|---|---|---|
| **R1** | **Major** | **`:equal_count` slicing on CUDA is not equal-count when z has ties.** CPU builds indices from the sort permutation; CUDA computes boundaries only and re-assigns by comparison, so tied values all fall one side. Measured n=2000, ns=9: CPU counts `[222,222,222,222,223,…]` vs CUDA `[211,196,236,238,163,…]` — a **27% relative error in a slice weight**, and slice weights multiply `kbb` directly. The docstring promises "exact empirical equal-count slices". |
| **R2** | Moderate | **CPU `:equal_count` returns a `boundary` and an `indices` that contradict each other** — 244 of 2000 particles lie outside the `[lb,rb)` their own slice reports. Bounded by the interpolation clamp, but `boundary` is consumed as the slice extent by every PIC and spectral path. |
| **R3** | Moderate | **The Symbolics adapter can never activate.** `Symbolics` is in no section of `Project.toml`, so `import Symbolics` inside the module fails unconditionally and `_HAS_SYMBOLICS` is permanently `false` — measured on a machine where Symbolics **is** installed. The error message tells the user to install a package they already have. ~20 lines unreachable, two exports permanently dead, the round-trip test always takes the `else` branch. The adapter body itself is correct: 31/31 expressions round-trip when run where the import resolves. |
| **R4** | Moderate | **`@knob p::T` changes a knob's value with no epoch bump and no cache invalidation.** `_resolve_knob_type_locked!` converts the stored value, then the `rhs === nothing` branch returns without touching the epoch. Measured: `knob_value(:a)` reports the new `Float32` value while dependent `:b` and every compiled runtime keep the old one, and nothing recompiles. `set_knob!` gets this right; this path does not. |
| **R5** | Moderate | **`MomentObserver` truncates its output on every `execute!`.** It reopens with mode `"w"` on each call, so a run split across two `execute!` calls keeps only the last chunk — measured `[0.0, 2.0]` then `[4.0]`. Contradicts `Tasks.jl`'s documented "splitting a run across multiple `execute!` calls preserves schedules". Every other observer appends. |
| **R6** | Moderate | **`_scheduled_turns` plans on a turn *count* while `should_run` tests an *absolute* turn.** Any `start_turn ≠ 0`, or any second `execute!`, plans 0 records while the observer fires — measured `BoundsError` crash. Also mis-plans silently where the counts happen to overlap. |
| **R7** | Minor | **Zero-width z distribution disagrees three ways.** CPU `:equal_area`/`:equal_width` put everything in slice 1; CUDA puts it in slice `ns`; CPU `:equal_count` splits evenly. Same input, three answers. Reachable for a single-particle beam. The existing degenerate tests assert only that the total count is right, never *which* slice. |
| **R8** | Minor (perf) | **CUDA `:equal_area` is 10–20× slower than it needs to be** — a per-bin loop of full-length device broadcasts. Measured 53.4 ms vs 2.6 ms at n=1e6, ns=15. At the **default** `nslices=1` the histogram's only consumer is an empty loop, so all 3.8 ms per beam per collision is discarded work. |

| **R9** | Moderate | **Spectral has no dropped-charge accounting, unlike PIC.** Out-of-box source charge is silently absent, with no counter, no warning, no receipt — where `_pic_report_dropped` exists precisely because "dropped charge is a correctness event, not a tuning statistic". Measured: 3 of 6 sources outside the box gives a field **exactly 0.5x** the in-box field at every probe. *Framing correction to the agent's report:* that ratio is the in-box fraction, and since `kbb` normalises per particle it is physically **right** when the escapees are far away (they contribute ~0). It is wrong only for a particle just outside the wall, which the `1.05*emax` sizing is designed to prevent. So the live gap is the missing counter, not the normalisation. |
| **R10** | **Major (if reachable)** | **`method = :grid_free` ALIASES rather than drops.** A source at `x = 1.7L` produces exactly **-1x** the field of a source at `x = 0.3L` — the odd periodic extension mirrors it back inside with a sign flip. A silently wrong field, not a missing one. Reachability depends on whether the box can ever under-cover; verify against the sizing before scoring severity. |
| **R11** | Minor | **`field_precision` is reported `status=resolved` on CPU, which provably ignores it** (its docstring says "The CPU path always uses Float64"). The `supported_backends` machinery that would mark it `inactive_backend` exists and is used correctly by PIC one file over. All 13 spectral options carry the default `consumer=:solver_runtime`, so the schema self-check passes vacuously for this solver. |
| **R12** | Minor (perf) | **`_spectral_collide_transverse!` does `n1*n2` field solves where `n1+n2` suffice** — the source mesh is identical for every field slice `j` but is recomputed inside the `j` loop. Measured 0.77 ms (1 pair) to 30.0 ms (64 pairs); ~8x redundant at 8 slices. The longitudinal path genuinely cannot be hoisted. |

Lower-priority items also recorded in the agent reports and not repeated here: a
`consumer=` label with no referent, a docstring detached from its binding by a
blank line, `EveryNSteps`'s validation bypassable through the positional
constructor, and a `1.05·emax` box headroom that is insufficient below `Nx = 41`
(unreachable at production grids).

## 6. Provenance, and the agent hit rate

Six sub-agents read ~6,000 lines on disjoint regions, each given a *different*
hypothesis drawn from the five defect classes established in parts 1–5, plus the
known-good reference to compare against and a requirement that every claim carry
a `file:line`.

**Their output is a lead, not a finding, and this session has the numbers to
justify saying so.** Across parts 4–6, of the claims agents raised:

- several were confirmed and became real fixes (S18, S19, S20);
- several dissolved on checking — the "latent trap" that turned out to be
  identical on both backends by design; the missing dropped-particle accounting
  that cannot matter because the only under-covering estimator is rejected on
  that backend; a "wrong grid" concern that was safe by an invariant rather than
  by luck;
- one was *broader* than reported — S19 reaches the CPU for a reason the agent
  did not identify.

That last category is the argument for re-deriving rather than trusting: the
agent's own framing was too narrow, and taking it at face value would have
produced a CUDA-only fix for a CPU-reachable defect.

Everything in §2 and §3 was reproduced by me before any code changed. Everything
in §5 was not, and is labelled accordingly.

## 7. Handoff

### Next, in priority order

1. **Verify and fix R1** (`:equal_count` ties). Highest severity in §5, and slice
   weights feed `kbb` directly. Reproduction is in the table.
2. **R6 then R5** — both make `MomentObserver` wrong in ordinary chunked runs,
   which is a documented workflow.
3. **R3, R4** — the knob subsystem. R3 is a one-line `Project.toml` change plus a
   test that would have caught it.
4. **R2, R7, R8** — bounded or performance-only.
5. **Wave 2, still unread**: `gaussian_pic.jl` (850), `gaussian_pic_cuda.jl`
   (1,182), `Knowledge.jl` (885), `Tasks.jl` (759), `Registry.jl` (209),
   `BPMObserver.jl` (240) — ~3,900 lines.

### The technique that produced this pass

**Give each agent a different hypothesis, and the known-good reference.** The six
briefs named a specific failure mode each — tree-reduction orphaning, declared-
and-never-read, invariants broken between functions, degenerate-parameter
blindness, the symbolic derivative as unreviewed mathematics. The two that found
the most were the two whose hypothesis matched a defect class this codebase has
already produced.

**Then verify the crux yourself.** S20's factor of 100 was measured, not read.

---

# 8. Follow-up — four of the twelve settled

Worked the §5 queue in the same session, in the order §7 recommended. Each was
verified before being touched, and the verification changed the outcome in two
of the four.

| # | outcome |
|---|---|
| **R1** | **CONFIRMED and FIXED** — physics |
| **R3** | **CONFIRMED, but the agent's reason was wrong**; partially fixed |
| **R5** | **REJECTED** — documented behaviour, the agent over-read a contradiction |
| **R6** | **CONFIRMED and FIXED** |
| **R4** | **CONFIRMED and FIXED** — see §8.6 |
| — | **§8.7 records a defect this audit itself introduced, and how it evaded the suite** |

## 8.1 R1 — CUDA `:equal_count` was not equal-count under ties

Reproduced: 2000 particles quantised to 64 distinct z values.

| ns | CPU counts | CUDA counts, before | max relative weight error |
|---|---|---|---|
| 5 | `[400,400,400,400,400]` | `[400,337,460,394,409]` | **15.8%** |
| 9 | `[222,222,222,222,223,…]` | `[211,189,255,219,161,…]` | **27.8%** |

The slice weight multiplies `kbb` directly, so this is a physics error, not a
bookkeeping one.

**Cause.** `_cuda_equal_count_slices` already computed the sort permutation —
and then discarded it, handing the boundaries to `_cuda_slices_from_boundaries`,
which re-derives membership from `z .>= lb .& z .< rb`. **A comparison cannot
split a tie**: when several particles share a z value the boundary lands on that
value and they all fall the same side. The CPU never had this because it slices
the permutation directly.

**Fixed** by assigning from the rank order, via a new
`_cuda_slices_from_indices` that mirrors the finishing logic of
`_cuda_slices_from_boundaries` but takes the index sets as given. Post-fix the
**index sets are identical** between backends, not merely the counts, with
weights and centers agreeing to exactly 0.0; the no-tie case is unchanged.

**Why it survived.** Ties are measure-zero for continuous `Float64` z. They are
routine for a **`Float32` beam**, for z loaded at limited precision, and for any
initial condition that puts z on a grid.

## 8.2 R3 — the agent's conclusion held, its reason did not

Reported as "`_HAS_SYMBOLICS` is permanently `false`". Measured:

| load mode | `_HAS_SYMBOLICS` |
|---|---|
| `include("src/Octopus.jl")` — what `AGENTS.md` prescribes for verification | **`true`** |
| `using Octopus` — package mode, `test/runtests.jl` and every user | **`false`** |

So it is not permanent: the optional `import` resolves against the *active
project* when Octopus is included as a script, and against Octopus's *declared
dependencies* when it is loaded as a package. That asymmetry is the actual
finding, and it explains the survival — developers exercise the working path and
users get the dead one.

**Partially fixed.** The correct repair is a package extension (`[weakdeps]` plus
an `ext/` module); a plain `[deps]` entry would contradict this project's
deliberate choice to take no runtime dependency on an AD package, and the
refactor was judged too large to attempt safely at the end of this session. What
was fixed is the part that actively misled: the error told users to
`Pkg.add("Symbolics")` — which they may already have done, to no effect. It now
states the real constraint, names the working load mode, and points at the
extension work. The stale comment claiming "the same pattern as CUDA in
`Beam.jl`" is corrected too: CUDA *is* a declared dependency, so the pattern
never transferred.

**Still open:** the extension itself.

## 8.3 R5 — rejected

Reported as `MomentObserver` truncating its output on every `execute!`,
contradicting `Tasks.jl`. It does truncate — and its own docstring says so:
*"Re-executing a task prepares a fresh table at `path`; output from the previous
[execution is replaced]"*. `Tasks.jl` claims that splitting a run preserves
"schedules, turn-dependent updates, and counter-based random streams" — it never
claims observer output is preserved. There is no contradiction. Documented
behaviour, left alone.

## 8.4 R6 — the planner and the predicate disagreed on what a turn is

`_scheduled_turns` filtered against `0:turns-1` while `should_run` is handed the
**absolute** `ctx.turn = first_turn + offset`. Reproduced:

| case | before | after |
|---|---|---|
| `AtTurns([100,101])`, turns=3, first=100 | `Int64[]` — plans nothing, observer fires twice, over-runs its preallocated table and throws | `[100, 101]` |
| `EveryNSteps(0,6,2)`, turns=3, first=3 | `[0,2]` — plans two records; the observer fires once, at turn 4. No error, silently wrong header | `[4]` |
| any schedule, `first_turn = 0` | — | unchanged |

`first_turn ≠ 0` is not exotic: it is **every second `execute!` on the same
task**, which `Tasks.jl` documents as a supported way to split a run.

**Fixed** by threading the absolute window through `prepare_observers!` /
`prepare_line_observers!` to the four `_scheduled_turns` methods, from both
`Tasks.jl` and the strong-strong executor. The `first_turn` argument defaults to
0 throughout, so every existing call keeps its behaviour.

## 8.6 R4 — a retype that silently staled everything downstream

`@knob p::T` on an existing knob looks like a pure annotation. It is not:
`_resolve_knob_type_locked!` **converts the stored value**, so it is a value
mutation. The bare-declaration branch of `_knob_define!` then returned without
invalidating dependents or bumping the epoch — the epoch that `Tasks.jl` and the
strong-strong executor gate recompilation on.

Reproduced:

    @knob a = 0.1 ; @knob b = a * 1.0        # knob_value(:b) == 0.1
    @knob a::Float32
      knob_value(:a) -> 0.1f0  (0.10000000149011612 as Float64)
      knob_value(:b) -> 0.1                   <- STALE
      epoch          -> unchanged             <- nothing recompiles

`knob_value` reports the new number while every dependent cache and every
compiled runtime keeps the old one. `set_knob!` has always invalidated *and*
bumped; this path did neither.

**Fixed** by capturing the stored value before the type resolution and, in the
bare-declaration branch, invalidating and bumping when the conversion actually
changed it. Post-fix `knob_value(:b)` tracks `:a` exactly and the epoch moves.
Deliberately conditional on the value changing: a `Float64 -> Float64`
re-declaration, and `0.5 -> Float32` where the value is exact, both correctly
leave the epoch alone. Verified in all three cases.

## 8.7 A defect this audit introduced, and why the suite did not see it

The R6 fix added

    prepare_line_observer!(observer::AbstractBeamObserver, turns, first_turn) = nothing

which lowers to `(::AbstractBeamObserver, ::Any, ::Any)` — the **same signature**
as the existing `(observer, schedule, turns)` method three lines above. It
silently overwrote it and made the module fail to precompile.

Two things about this matter more than the fix.

**It passed the full suite.** Both methods returned `nothing`, so behaviour was
identical, and nothing in `test/runtests.jl` detects a method overwrite. The
suite proved the code still worked; it could not prove the code still *existed*
as written. That is a verification gap of exactly the kind this series keeps
finding in the library — recorded here against the audit's own work.

**It was caught by accident.** The R4 verification happened to load the package
in a fresh process, which printed the precompilation warning. Nothing in the
process looked for it. A guard is recorded as open work rather than improvised
at the end of a long session.

A comment now sits at the site naming the collision, because the natural next
edit reintroduces it.

## 8.5 The running tally on agent claims

Across parts 4–6 and this follow-up: confirmed as reported, confirmed with a
wrong reason, rejected outright, and one *broader* than reported. The hit rate
sits near 60%, and every one of the four outcomes above required measurement to
tell apart. That is the case for the verify-then-fix gate, stated with numbers
rather than as a principle.

### Still open from §5

R2, R7–R12, plus the Symbolics package extension from R3, and a guard against
method overwrites (§8.7). R9/R10 — the spectral dropped-charge counter and the
`:grid_free` aliasing at −1× — are the highest-value remainders.

---

<a id="part-7"></a>

# Comprehensive Audit — 2026-08-03, part 7

> ## Start here
>
> **Nothing in this report is fixed, and almost nothing in it is verified by me.**
> It is a faithful record of what four sub-agents found in the last ~4,100
> unaudited lines, written at the point where the session ran out of room to keep
> verifying. Treat every entry as a **lead with a reproduction**, not a finding.
>
> | read | why |
> |---|---|
> | **§2** | the two items to take first — one is memory corruption, one is the consumer-side twin of a defect fixed in part 6 |
> | **§1** | the full list, by file |
> | **§4** | what "confirmed by an agent" has empirically meant in this series: ~60% survive verification |
>
> **Follow-up (2026-08-04):**
> [part 8](#part-8) verified and fixed
> **T1, T3, T4, T5, K1 and G1**. All six survived verification — but §2's
> "one root cause" framing below was wrong (it is two mechanisms: nested
> vectors for T3/T4, `LineEntry` for T1/T5), and G1 was narrower than the
> truth (*any* non-Float64 rep threw, not only mixed precision). The original
> text is kept unedited below, per this series' rule.

Seventh pass. Regions: `gaussian_pic.jl` (850), `gaussian_pic_cuda.jl` (1,182),
`Tasks.jl` (762) + `BPMObserver.jl` (240), `Knowledge.jl` (885) +
`Registry.jl` (209). Four agents, each with a hypothesis drawn from the defect
classes parts 1–6 established. **All four reported.** Between them: 26 claimed
findings, of which none has been independently verified by me.

**With this pass, every line of `src/` has been read by someone.** The ledger is
explicit that most of this one was read by agents rather than by me.

## 1. What was found, by file

### `Tasks.jl` — 11 confirmed by the agent, the largest single haul of the series

| # | severity claimed | finding |
|---|---|---|
| T1 | **Major** | **the knob epoch never fires for any task built from a `BeamLine`.** `_has_knob_parameters` has no `LineEntry` method and `LineEntry` is not an `ElementSpec`, so `knob_dependent = false` forever and the recompile gate short-circuits true. `set_knob!` then changes nothing while `knob_value` reports the new number. This is the **consumer-side twin of R4**, fixed in part 6 on the producer side. |
| T2 | Moderate | the loss record's `fits` test omits the backend, against its own docstring; reusing a task across CPU and CUDA reps gives a hard `KernelError` |
| T3 | **Major** | **a nested `AbstractVector` in a line makes the aperture walkers disagree**, so `counts` is undersized while ids are assigned for every aperture — an unchecked `@inbounds`/`CUDA.@atomic` write past the end. Reported symptom: heap word corruption *and* a collimator's kills reported as `unattributed`, i.e. the diagnostic meant to flag blow-ups fires on ordinary collimation |
| T4 | Moderate | the same nested vector silently zeroes aperture arc length, so every loss record after it reports the wrong `s` |
| T5 | Moderate | a task built from a `BeamLine` declares **no contracts and no analyses** — same root cause as T1/T3/T4 |
| T6 | Moderate | a failed `execute!` is not resumable: `next_turn` is correctly not advanced, but `rep` is mutated and observer state retained, so a resumed run produces duplicate turn labels. Also, the loss log is written outside the failure path, so a crashed run writes no loss file — the one artifact you want after a crash |
| T7 | Minor | one throwing finalizer strands the others; buffered observer measurements silently lost |
| T8 | Minor | BPM noise reads the live global RNG seed rather than the `TrackingContext` snapshot, falsifying its own docstring's purity claim |
| T9 | Minor | a BPM read twice in one turn draws **identical** noise — the counter key has no occurrence component, though `x_noise` is documented as "per-reading" |
| T10 | Minor (perf) | `_scheduled_turns(::EveryNSteps)` enumerates from `schedule.start`, so cost grows with absolute turn: 0.004 ms at `first_turn=0`, **29.5 ms at 1e8** — penalising exactly the chunked long run `first_turn` exists to serve |
| T11 | Minor | `rng_id` is read but absent from the BPM option schema, so `configuration_report` never shows the one field determining whether two BPMs share a noise stream |

### `gaussian_pic.jl`

| # | severity claimed | finding |
|---|---|---|
| G1 | **Major** | hard `MethodError` on a mixed-precision beam (`Float32` rep with `Float64` params or explicit `kbb`), because the profile buffers use the promoted type while the scalars are converted with `eltype(source.x)`. Plain `PICPoissonSolver` survives all four cases; only the hybrid breaks |
| G2 | Minor | CPU and CUDA neutralise to different quantities (deposited grid charge vs particle count), so the docstring's "CPU/CUDA bit-parity" cannot hold for the default `neutralize=true`. Measured `4.44e-16` relative — the claim is the defect, not the number |
| G3 | Minor | `configuration_report` says the coupled subtraction is "CPU path only", contradicted by this file's own docstring and by the CUDA route that implements it |
| G4 | Minor | the docstring promises six options are "forwarded unchanged" that are in fact rejected — including the three it names explicitly as "the CUDA execution options" |

### `gaussian_pic_cuda.jl`

| # | severity claimed | finding |
|---|---|---|
| C1 | Minor | the CUDA uncoupled neutralisation amplitude drops the CPU's `sgx*sgy > 0` guard, so a degenerate profile yields `Inf` and poisons the charge plane. The **coupled** branch has the guard — the omission is specific to one branch |
| C2 | Minor | a non-commutative `choose` passed to `mapreduce`, which CUDA.jl assumes is commutative: the moment anchor is whichever element the reduction tree reaches first. Roundoff-only, but it falsifies a claimed bit-parity on two non-default routes |
| C3 | Minor | PIC timing and cache stats are silently inert on two of the three CUDA routes — a non-default diagnostics request accepted and dropped |

Also **clean**, and worth recording: every reduction in `gaussian_pic_cuda.jl` is
confined to an already live-filtered slice index set, so the mask that was
missing in `spectral_cuda.jl` is correctly *redundant* here rather than absent.
And part 5's S18 fix was verified working — the bare-`collide!` warning sits in
the single funnel all three Gaussian routes pass through.

### `Knowledge.jl` + `Registry.jl` — the hypothesis was "metadata that lies", and it landed

This layer exists so agents and users can trust it *without reading the source*
(`AGENTS.md`), which makes a false entry uniquely damaging. The agent injected 13
deliberate metadata defects and diffed the validator's output.

| # | severity claimed | finding |
|---|---|---|
| K1 | **Major** | **`RBendSpec` is exported, user-facing, and carries five PTC reference cases — and has no `ElementMeta`.** Every query swallows the miss and returns empty, so `required_contracts(RBendSpec) == []` and `element_help(RBendSpec)` prints a confident, well-formed report claiming no contracts, no tracking methods, and an invented kind `:RBendSpec` that does not exist. The *instance* resolves correctly, so the lie is specific to the type-level query. An agent asking "which contracts apply?" is told "none" about a PTC-validated element |
| K2 | Moderate | `:thin_dipole`, `:thin_quadrupole`, `:thin_sextupole` declare `PTCConsistencyContract` but have **no reference case**, so the claim is never exercised — and what a PTC comparison would catch is exactly their per-constructor keyword folding (`k0l→knl[1]` etc.) and a documented sign convention. The neighbouring kickers correctly omit the claim, so the codebase knows how |
| K3 | Moderate | metadata can advertise a tracking method the implementation cannot execute. The validator's check is **circular**: `supported_tracking_methods(T)` returns `meta.tracking_methods` (verified `===`), so it asks whether a list's elements are in itself, and `runtime_types` is auto-populated from that same list. Demonstrated with a throwaway spec that validates clean and then throws `MethodError` on `compile_runtime` |
| K4 | Minor | `ElementMeta.runtime_type` (singular) is stored and **never read** — dead storage that can silently disagree with `runtime_types` |
| K5 | Moderate | query functions return **live internal state**, not copies. `push!(required_contracts(ElementSpec{:sbend}), Int64)` permanently corrupted the registry in-process and validation still passed — inconsistent with the deliberate `copy` discipline 200 lines earlier |
| K6 | Minor | `Registry.jl` crashes on metadata the Knowledge layer explicitly permits (`friendly_constructor = nothing`), so snapshot generation and the CI assertion die rather than report |
| K7 | Minor | three registry sections are hand-written prose in a file whose docstring claims derivation "from Julia's type graph rather than edited as external metadata" |
| K8 | Moderate | `:line` advertises **no** tracking methods yet silently accepts every one, because `compile_runtime(spec::ElementSpec{:line}, args...)` discards the request — against `AGENTS.md`'s "Do not accept silently ignored non-default requests" |

**The headline number: the element validator caught 1 of 13 injected defects.**
It does not check that a declared contract is a contract, that a declared
tracking method is one, that a declared default matches the constructor, or that
a declared parameter is read. `validate_configuration_metadata` is substantially
stronger — it *does* compare declared defaults against real values — but its gap
is enumeration: every type it inspects is a hardcoded literal, and a fabricated
`LyingSolver` with a wrong default and an invented consumer passed it.

Also found **sound**, and worth as much: every declared tracking method for all
30 registered kinds actually compiles (checked by running `compile_runtime` for
each); every declared contract is a real subtype with a runnable `validate`;
every declared analysis is `PlaceholderAnalysis`, exactly as `AGENTS.md`
requires; the physics-keyword vocabulary is genuinely enforced; and the snapshot
test is non-vacuous, deterministic, and does run in CI. The `:liar` scenario is
latent, not present.

## 2. Take these two first

**T3 — memory corruption.** An unchecked write past the end of a `Vector{Int32}`,
on both backends, reachable from an ordinary nested-vector line. Everything else
here is a wrong number or a wrong message; this one is undefined behaviour.

**T1 — the knob epoch never fires for `BeamLine` tasks.** Part 6 fixed the
producer side (a retype that did not bump the epoch). This is the consumer side,
and it is broader: for a whole class of task, *no* knob change ever recompiles.
`knob_value` reports the new number while tracking silently uses the old one.

T1, T3, T4 and T5 share one root cause — `LineEntry` is not an `ElementSpec`, and
five walkers over the runtime line handle that fact inconsistently. The agent
notes two of the five *do* carry `LineEntry` methods, so the case was known and
handled in some places and not others. Fixing the root cause plausibly closes
four findings at once, which is the first thing to check.

## 3. Verification status, stated plainly

I verified **none** of §1 independently. I attempted T1's reproduction and my
probe errored before producing a result; I did not get back to it.

That matters because of §4. Every entry carries the agent's own reproduction, and
most are the kind that can be re-run in minutes — that is what the next session
should do first, before changing any code.

The one thing I did check from this wave was C1's premise, and it held: the CPU
uncoupled path has `if neutralize && sgx * sgy > zero(T)` while the CUDA
uncoupled path divides unconditionally, and the CUDA *coupled* path has its own
`sg != 0` guard. That is an asymmetry in the source, whatever its reachability.

## 4. Why this is a queue and not a findings list

Across parts 4–7, agent claims have come out four different ways:

- **right as stated** — S18, S20, R1, R6;
- **right, with the stated reason wrong** — R3, where the failure is a load-mode
  asymmetry rather than a permanent one, and the reason is what determines the
  correct fix;
- **wrong** — R5, which one docstring dismissed; the "latent trap" that was
  identical on both backends by design; the missing dropped-particle accounting
  that cannot matter because the option is rejected on that backend;
- **narrower than the truth** — S19, reported as CUDA-only, actually reachable on
  CPU for a different reason.

Roughly 60% survive. A pass that fixed §1 on the agents' word would have written
several unnecessary changes into physics paths, and this series has the numbers
to say so rather than the intuition.

## 5. Handoff

1. **T3** — memory corruption; then check whether the `LineEntry` root cause also
   closes T1, T4, T5.
2. **T1** — verify with the reproduction, then fix.
3. **G1** — hard failure on a supported precision combination.
4. **K1** — `RBendSpec`'s missing `ElementMeta`. Small fix, and it stops the
   knowledge layer confidently misinforming an agent about a PTC-validated
   element. Then **K3/K5**, which are what let K1-shaped problems go unnoticed:
   a circular validator check and query functions handing out live state.
5. The remaining part 6 §5 items: R2, R7–R12, the Symbolics package extension,
   and a guard against method overwrites (part 6 §8.7).

### Coverage, finally

`src/` is 32,195 lines. With this pass every file has been read by someone.
Roughly 60% was read by me directly across parts 1–5; the rest, chiefly parts 6
and 7, by sub-agents against briefed hypotheses. The distinction is kept because
a coverage claim that hides its provenance is not checkable, and this series has
already had to correct its own ledger twice.

---

<a id="part-8"></a>

# Comprehensive Audit — 2026-08-04, part 8

> ## Start here
>
> **This pass verified and fixed the head of part 7's queue.** Six findings were
> reproduced before any code changed — and for the first time in this series,
> **every claim taken up survived verification**: four exactly as stated, one
> broader than stated, and one whose shared-root-cause framing was wrong in a
> way that mattered to the fix.
>
> | read | why |
> |---|---|
> | **§2** | verdicts against part 7's claims, including the framing correction |
> | **§3** | the fixes, each with its negative control |
> | **§5** | two defects in this session's own probes, recorded per protocol |
> | **§6** | what remains open in the queue |

Eighth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md).
No new reading: `src/` was fully covered by part 7, and this session is the
verify-and-fix phase that queue was written for.

## 1. Declared scope (Phase 0, recorded before work began)

Verify, then fix if confirmed: **T3** (the only undefined-behaviour item), the
`LineEntry` root-cause check against **T1/T4/T5**, then **K1**, then **G1**.
Depth: full reproduction of each claim before any edit; a behavioural
fingerprint before the first modification; a negative control for every
regression test. Deliberately not covered: T2, T6–T11, G2–G4, C1–C3, K2–K8,
and part 6's R2, R7–R12, the Symbolics package extension, and the
method-overwrite guard. Push access verified before starting (dry-run against
`github-dxu`).

## 2. Verification verdicts

| # | part 7 claimed | verdict |
|---|---|---|
| T3 | unchecked `@inbounds`/`CUDA.@atomic` write past the end of `counts`, reachable from a nested-vector line; kills reported `unattributed` | **CONFIRMED as stated.** `_aperture_specs` sized `counts` at 1 while the runtime walk bound ids 1 *and* 2; under `--check-bounds=yes` the bump is `BoundsError: attempt to access 1-element Vector{Int32} at index [2]`, under default flags it silently writes past the end; the summary reported the NESTED collimator's kill as `unattributed = 1` with a warning |
| T4 | the same nested vector zeroes aperture arc length | **CONFIRMED.** `_aperture_s_positions` gave `[1.0]` where `[3.5]` is correct, and dropped the nested aperture's entry entirely |
| T1 | the knob epoch never fires for a `BeamLine` task | **CONFIRMED as stated.** After `set_knob!`, the tuple twin moved `0.00035 → 0.0006` while the `BeamLine` task stayed `0.00035` and `knob_value` reported the new number. `set_knob!` bumps only the knob epoch (`Knobs.jl`), and with `knob_dependent = false` the cache gate short-circuits true forever |
| T5 | a `BeamLine` task declares no contracts and no analyses | **CONFIRMED.** `contracts=[] analyses=[]` against the tuple twin's `[ElementTrackingBackendConsistencyContract, PTCConsistencyContract]` / `[PlaceholderAnalysis]` |
| K1 | `RBendSpec` has no `ElementMeta`; `element_help` invents kind `:RBendSpec` and reports no contracts | **CONFIRMED.** All type-level queries missed the registry and returned confident emptiness; the instance resolved through `:sbend` exactly as the agent said |
| G1 | hard `MethodError` on a mixed-precision beam through the hybrid; plain PIC survives | **CONFIRMED, and broader than reported** — part 7 §4's fourth category. A **uniformly Float32** beam also threw, because the solver's own `kbb` is `Float64` by construction, so `promote_type(rep, rep, kbb)` ≠ `eltype(source.x)` for *every* non-Float64 rep. "Mixed precision" was never the condition |

**The framing correction that mattered.** Part 7 §2 presented T1/T3/T4/T5 as
one root cause — "`LineEntry` is not an `ElementSpec`, and five walkers handle
that inconsistently". Measured, it is **two mechanisms**: T3/T4 are
*nested-`AbstractVector`* blindness (`_append_runtime_line!` recurses into
vectors; the two aperture collectors did not — `LineEntry` never enters it),
and T1/T5 are *`LineEntry`* blindness (`_has_knob_parameters` and
`_collect_contracts`/`_collect_analyses` — vectors were already handled or
irrelevant there). One fix at the imagined single root would have closed two
findings and left two open. This is the "right, with the stated reason wrong"
category doing exactly what §4 said it does: the reason determines the fix.

## 3. Fixes, each verified before and after

All four T-items and both K1/G1 were fixed in this session. The behavioural
fingerprint (163 lines: aperture-line tracking, `BeamLine` tracking, a knob
task, a fused multi-element line, `element_help` for three kinds plus
`RBendSpec`, plain-PIC and hybrid collisions, the registry summary) is
**bit-identical** before and after, except the two intended K1 text changes.

**T3/T4 — `src/tasks/Tasks.jl`.** `_collect_aperture_specs!` and
`_collect_aperture_s!` gained the `AbstractVector` recursion that
`_append_runtime_line!` already had, with a comment naming the invariant.
`_bind_apertures` now asserts `id[] == length(record.counts)` at bind time —
if the walkers ever diverge again, the failure is a loud host-side error
naming the two walks, not an unchecked device write. Post-fix: `counts ==
[1, 1]`, both kills attributed, `unattributed = 0`, arc positions
`[1.0, 3.5]`; clean under `--check-bounds=yes`; **verified on CUDA too**
(RTX 4500 Ada), where the same task path previously fed the undersized vector
to `CUDA.@atomic`.

**T1 — `src/elements/beam_line.jl`.** `_has_knob_parameters(::LineEntry)`
checks the placement's spec *and* its overrides (either can hold a knob
expression); `_has_knob_parameters(::ElementSpec{:line})` covers a line kept
whole (a cryostat carrying its own state), whose composite compile resolves
its placements' knobs. A knob-free line still reports `false`, or every line
task would recompile every turn. Post-fix the `BeamLine` task tracks
`set_knob!` exactly as the tuple task does.

**T5 — `src/tasks/Tasks.jl`.** `_collect_contracts`/`_collect_analyses`
rewritten as one recursive walk (`_collect_declared!`) over tuples, vectors,
placements, and kept-whole lines. A `BeamLine` task now declares exactly what
its tuple twin declares, and a nested vector's contracts are seen too.

**K1 — `src/knowledge/Knowledge.jl` + `src/elements/lattice_magnets.jl`.**
`register_friendly_alias!(T, query)` maps an additional friendly constructor
type onto an existing `ElementMeta`; `RBendSpec` is registered onto `:sbend`,
which is what its constructor builds (parallel faces = `angle/2` added to each
of `e1`/`e2`, then `SBendSpec`). `element_help(RBendSpec)` now reports kind
`:sbend`, the PTC and backend-consistency contracts, and the full parameter
schema; the sbend `construction_help` gained one sentence stating the RBend
conversion. `validate_element_metadata()` passes; the registry snapshot is
unchanged (the alias registers no new spec).

**G1 — `src/tasks/strongstrong/gaussian_pic.jl`.** The two drifted-solve
helpers derived their scalar type from `eltype(source.x)` while the caller
allocates the profile buffers and `workspace.charge` in
`promote_type(rep1, rep2, kbb1, kbb2)` — and `_gpic_gaussian_profile!`'s
typed signature requires buffer and scalars to agree. They now derive it from
the buffer they were handed (`eltype(gxbuf)`), which is the workspace
convention the plain PIC already follows; the plain path survives Float32
beams only because its deposit helpers are generically typed. Post-fix all
four precision combinations pass on both the uncoupled and the coupled
(rotated-subtraction) branches; Float32 agrees with Float64 to ~6e-9 relative
(input precision), and the all-Float64 luminosity is bit-identical to the
fingerprint.

### Negative controls

Each new test was run against the pre-fix source (stashing only the fix under
test) and confirmed to fail there:

| test | on broken source | on fixed source |
|---|---|---|
| "Every walker over the line agrees…" (T1/T3/T4/T5) | **11 of 15 assertions fail** | 15/15 pass |
| K1 block in the PTC/metadata testset | **0 of 7 pass** | 7/7 pass |
| "GaussianPIC hybrid accepts non-Float64 beams" (G1) | **errors with the MethodError** | 4/4 pass |

## 4. Adjacent gaps observed, recorded, not fixed

- **An aperture inside a line kept whole is never bound to the loss record.**
  A stateful line compiles to a single composite runtime object; only
  `PhysicsEntry{<:Aperture}` entries are bound, so such an aperture takes the
  record-free kill path and its kills surface as `unattributed`. Both walkers
  miss it *consistently*, so there is no sizing mismatch and no UB — one
  severity class below T3. Same family as T5's kept-whole case, which IS now
  handled for contracts.
- **`_pic_solve_drifted_field_with_green_fft!` (plain PIC) still derives its
  scalar type from `eltype(source.x)`.** Harmless today — every helper it
  calls is generically typed, and all four precision cases pass — but it is
  the same pattern G1 grew from, one file over.

## 5. Two defects in this session's own probes

Recorded because part 6 §8.7 established the precedent, and both are the
class this series keeps finding in the library.

- **A closure swallowed the very BoundsError the probe existed to catch.** The
  first bounds-checked T3 run wrapped `execute!` in `try/catch` inside an
  `allow_lost_particles() do` block, with `err = e` in the catch. At script
  top level that assignment creates a *closure-local*, not the global — so the
  error was caught, discarded, and the run printed `dead = 1, unattributed =
  0`, which reads as "no OOB and no kill" — a wrong conclusion with plausible
  numbers. Caught only because the missing kill contradicted the unchecked
  run. The probe now threads the error through a `Ref`.
- **A keyword splat placed positionally** (`f(a=1, kw...)` instead of
  `f(; a=1, kw...)`) made the coupled-branch probe die in the constructor and
  nearly reported the coupled path as unreachable. The error message named the
  inner constructor, not the call-site mistake.

## 6. What remains open

> **Follow-up (2026-08-04, same day):**
> [part 9](#part-9) settled everything below
> except R8 and R12, which remain open as performance-only items. The list is
> kept as written.

- From part 7: **T2, T6–T11** (Tasks.jl), **G2–G4** (gaussian_pic), **C1–C3**
  (gaussian_pic_cuda), **K2–K8** (Knowledge/Registry — including the two
  validator gaps in the todo table, which K1's fix does not close).
- From part 6 §5: **R2, R7–R12**, the Symbolics package extension, and the
  method-overwrite guard (§8.7).
- Nothing regressed: the full suite passed at `--threads=4` **with the CUDA
  half active** (RTX 4500 Ada) on the final tree, after the fingerprint diff
  above.

## 7. The running tally on agent claims

Parts 4–7 measured ~60% survival. This session's six-for-six looks like a
counterexample; it is not. The queue was *ordered by verifiability* — these
six were taken first precisely because each carried a mechanical reproduction,
and even so, one arrived with the wrong root-cause framing and one narrower
than the truth. The two claims that needed correction were correctable only by
measurement, which is the same lesson at a better hit rate.

---

<a id="part-9"></a>

# Comprehensive Audit — 2026-08-04, part 9

> ## Start here
>
> **This pass worked everything left in the queue except two performance
> items.** Twenty-four findings from parts 6 and 7 were verified and settled:
> twenty-two fixed (several with corrections to the recorded claim), one
> resolved by documenting its actual contract, one rejected-then-upgraded when
> this session's own instrumentation found a reachable case the original
> analysis missed.
>
> | read | why |
> |---|---|
> | **§2** | the verdicts, including the four claims that needed correcting |
> | **§4** | R9/R10 — the pre-collision box assumption, and the 83% silent charge loss the new tripwire caught |
> | **§6** | this session's own errors, including one that destroyed uncommitted work |
> | **§7** | what remains open: R8 and R12, both performance-only |

Ninth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
continuing [part 8](#part-8). Declared scope:
T6 and T2 first, then T7–T11, G2–G4, C1–C3, K2–K8, R2, R7–R12, the Symbolics
package extension, and the method-overwrite guard. Every claim reproduced
before its fix; behavioural fingerprint bit-identical across all three fix
batches; negative controls run by stashing the fixes and asserting the new
tests fail.

## 1. The two headline items

**T6 — a crashed `execute!` (CONFIRMED as stated, both halves).** A failure at
turn 3 of 5 left the loss file unwritten — `MISSING` with kills already
recorded and a log path given — and the documented retry (the stored turn
deliberately does not advance) appended duplicate turn labels:
`[0,1,2,0,1,2]`. Fixed on both halves without touching the documented turn
semantics: `execute!` flushes the loss summary, file, and warnings on the
failure path before rethrowing; and BPM observers discard readings at or
beyond the upcoming window when preparing — a no-op for ordinary chunking,
idempotence for retries, and the correct behaviour for an explicit
`start_turn` rewind, which duplicated labels too. The TSV mirror is rewritten
from memory when anything is dropped, and the noise-occurrence counter forgets
the failed pass so a retry redraws identical noise.

**T2 — task reuse across backends (CONFIRMED as stated, both directions
measured).** CPU→CUDA reuse died compiling the kernel (host `counts` in device
arguments); CUDA→CPU died with `MethodError: _aperture_bump!(::CuArray, …)`.
The `fits` test compared shape only, against its own docstring's "shape or
backend". `_loss_record_matches_rep` now mirrors the constructor's placement
decision, plus the slots eltype. Both directions verified clean post-fix, with
the record visibly reallocated per backend.

## 2. Verdicts on the rest, with corrections kept visible

| # | verdict | disposition |
|---|---|---|
| T7 | **CONFIRMED** — one throwing finalizer stranded both the remaining task-level observer and every line observer | both finalizer loops now finish their list and rethrow the first error; the `finally` nests so line observers run even when task-level finalization throws |
| T8 | **CONFIRMED** — the BPM noise read the live global RNG, so a mid-run `set_global_rng!` retroactively changed a reading | the draw now uses the `TrackingContext` snapshot, exactly as stochastic tracking does; the `turn`-only method keeps its interactive globals-snapshot behaviour |
| T9 | **CONFIRMED** — a BPM read twice in one turn drew identical noise | occurrence index added to the counter key, riding in the free particle slot; occurrence 0 reproduces the pre-existing stream bit for bit |
| T10 | **CONFIRMED** — 9.3 µs at `first_turn=0` vs **29.52 ms at 1e8**, matching the recorded number | the planner enumerates from the first schedule point ≥ the window start; 0.05 ms at 1e8, zero mismatches against the enumerate-and-filter oracle over a 4,800-point parameter grid |
| T11 | **CONFIRMED** — `rng_id` absent from the BPM schema | added, always reported (its value is auto-assigned, so a default comparison would lie) |
| G2 | **CONFIRMED, broader** — bit-parity fails even with `neutralize=false` (~1.4e-13 relative), so the neutralize-quantity mismatch was never the whole story | the docstring now states measured rounding-level agreement and names both causes (reduction order; deposited-total vs particle-count normalisation) |
| G3 | **CONFIRMED as stated** — coupled subtraction WORKS on the default CUDA route and throws on the other two, so the main docstring was right and the constructor comment + configuration_report ("CPU path only") were the stale texts | both corrected, the old claim kept in the comment |
| G4 | **CONFIRMED — exactly six**: `interaction_grid`, non-linear `slice_interpolation`, `grid_extent=:sigma` (both backends); `cuda_async/cuda_batch_fft/cuda_wavefront_fft = false` (CUDA) | the "forwarded unchanged" docstring now says which six are rejected at collide time and why |
| C1 | **CONFIRMED asymmetry** (reachability not established) — three CUDA uncoupled neutralisation sites divided unguarded where the CPU and the CUDA coupled branch both guard | the same `> 0` guard on all three sites |
| C2 | **CONFIRMED** — `choose = (a,b) -> a[1] ? a : b` is non-commutative under a `mapreduce` CUDA.jl documents as commutative | anchor is now the lexicographic minimum of the coordinate tuples: commutative, associative, deterministic; any in-slice anchor is mathematically valid, so the change is roundoff-sized |
| C3 | **CONFIRMED** — timing records on the indexed route only; the sequential route used the green cache and never reported it | coarse phase timing and the cache report on all three routes; verified: records now appear on each |
| K2 | **resolved transitively** — the three thin named-strength constructors build **bit-identical** runtimes to the PTC-validated `ThinMultipoleSpec` spellings (all six equivalences verified), which is what justifies their `PTCConsistencyContract` | equivalence pinned in the suite; the claim stands on the shared runtime, not on per-constructor PTC cases |
| K3 | **CONFIRMED** — the tracking-method check asked whether a list's elements were in itself | validator now checks declarations against the architectural roots AND compiles every example to a declared runtime type; the injected liar that used to validate clean now fails on three independent counts |
| K4 | **CONFIRMED** — `runtime_type` (singular) stored, never read post-construction | consistency check: it must appear in the runtime map |
| K5 | **CONFIRMED** — `push!(required_contracts(…), Int64)` corrupted the registry while validation still passed | the four list-returning query pairs return copies |
| K6 | **CONFIRMED** — `nameof(nothing)` crashed snapshot generation for permitted metadata | reported as "(no friendly constructor)" instead |
| K7 | **CONFIRMED** — three hand-written sections under a "derived from the type graph" claim | the docstring now names them |
| K8 | **CONFIRMED** — `compile_runtime(::ElementSpec{:line}, args...)` discarded an explicit method request | rejected with direction to set `tracking_method` on placements |
| R2 | **CONFIRMED, mechanism pinned** — 238/2000 boundary violations with quantized z, **zero with continuous z**: rank-based membership cannot be an interval property under ties, and every violating particle sits exactly ON its reported boundary | the contract is now documented on the slicing docstring and pinned by tests; no code change, deliberately — R1 chose rank semantics and made both backends agree on it |
| R7 | **CONFIRMED** — degenerate z: slice 1 on the CPU equal-width/area paths, slice `ns` on CUDA and on every boundary-search path (a backend divergence AND a CPU-internal inconsistency) | one convention — slice 1 — on both backends and all methods |
| R11 | **CONFIRMED** — `field_precision` reported `resolved` on CPU | one `supported_backends=(CUDABackend,)` keyword; now `inactive_backend` on CPU, `resolved` on CUDA |
| R3 (completion) | the load-mode asymmetry part 6 diagnosed | **the package extension exists**: `[weakdeps]` + `ext/OctopusSymbolicsExt.jl`, registration in `__init__` (a top-level registration is silently discarded with the precompile process — measured, §6), script mode activates at include; both modes verified end to end, and the suite's round-trip is now unconditional |
| §8.7 guard | — | a testset forces `Base.compilecache` and asserts no overwrite message: measured on this Julia, a runtime include is SILENT about overwrites and the compile driver can exit 0 while the worker reports the collision, so the guard greps the message rather than trusting either signal. Verified: 2 hits on an injected collision, 0 clean |

## 3. R9 — the tripwire, and what it immediately caught

Part 6 recorded the missing spectral dropped-charge counter with the framing
correction "the live gap is the counter, not the normalisation". The counter
is now a mass-deficit tripwire after both grid deposits (CIC weights sum to
one per in-box particle, so the grid total's deficit IS the clipped fraction).

**Verifying it found a reachable case the queue did not record.** The
Dirichlet box is sized ONCE per collision from pre-collision coordinates —
which cover every drifted deposit by construction (1.05× the masked extremum
plus the worst-case drift bound; derived, not assumed). But deposits happen
after earlier slice pairs' kicks. On a strong-kick configuration
(`max|px|`: 1e-5 → 0.69 in one collide), later pairs' drifted sources land
far outside the box and **83% of a slice's charge was silently discarded** —
before the tripwire, with no signal of any kind. At production kick scales
the growth is orders of magnitude inside the headroom and the tripwire is
silent.

## 4. R10 — rejected as recorded, then upgraded by §3

The recorded worry was aliasing for a source outside the box. For
pre-collision coordinates that is unreachable — the box covers them by
construction, and this session derived rather than assumed it. That would
have closed R10 as "mechanism real, internal-API only". **The R9 measurement
above reopened it**: the same intra-collision kick growth reaches
`:grid_free`, where an out-of-box source does not clip — the odd periodic
extension mirrors it back inside at **exactly −1×**, silently. A guard now
warns on the mode-sum path, verified firing on the strong-kick configuration
and silent on a mild one. This is the fourth time in the series a claim's
verification changed its scope in the middle of the check.

## 5. Negative controls

| tests | on pre-fix source | on fixed source |
|---|---|---|
| T6/T2 probe | 6 pass / 2 fail / 1 error (missing file, duplicate labels, KernelError) | 14/14 |
| T7–T11 probe | finalizers stranded, live-reseed match, identical noise, 29.53 ms, `rng_id` absent | all five inverted |
| K probe | registry corrupted while the validator passed; snapshot `MethodError`; silent method acceptance; the liar validated clean | all four inverted |
| C3 probe | timing records on one route of three | records on all three |
| overwrite guard | 2 collision messages on an injected duplicate | 0 |

## 6. This session's own errors, recorded per protocol

- **A careless `git checkout src/tasks/Tasks.jl` destroyed the uncommitted
  T6/T2/T7 fixes** while cleaning up a negative-control injection. Recovered
  by re-applying the three edits from context and re-running the 14/14 probe.
  The lesson is the one the fingerprint discipline already encodes: revert by
  removing exactly what was added (the injection had a grep-able marker), not
  by resetting a file that carries unrelated state.
- **Two probes were mangled by shell quoting** (`'\n'` terminating a
  single-quoted `-e` string), one of which made the overwrite-guard probe
  silently test nothing. Probes now go through script files.
- **The R9 tripwire was first placed in only one of the two grid deposit
  functions** — the one the default path never calls. Caught because the
  verification expected a warning and got none.
- **The extension's adapter registration was first written at the module's
  top level and was silently discarded with the precompile process**
  (`active: false` after `using Symbolics`). Moved to `__init__`; the failure
  mode is now documented in the extension file.

## 7. What remains open

> **Follow-up (2026-08-04, same day): R8 and R12 are now closed too.** Both
> measured before and after, both bit-identical.
>
> **R8**: the per-bin device broadcasts were replaced with one atomic
> histogram kernel whose bin membership is corrected against the exact
> per-bin edge expressions the masks compared with — ties, the closed last
> bin, and the rounding-dropped extremes land identically. Measured at
> n=1e6: **57.8 → 3.2 ms at ns=15** (18×), and the default `nslices=1` now
> skips the histogram whose only consumer was an empty loop: **3.9 →
> 0.32 ms**. Slice counts, boundaries, weights and centers bit-identical
> across five configurations including quantized ties; a per-bin-mask oracle
> pins the kernel in the suite.
>
> **R12**: `_spectral_field_grid!` split into a source-only solve and a
> mesh eval; the transverse path pre-solves every source once (positions are
> never mutated there, so both directions' solves are valid up front) and the
> kick loops evaluate stored meshes in the exact order they used to solve in.
> Full transverse collides captured pre/post at 4 threads, ns=8:
> **kicks and luminosity bit-identical**. Solve count per collision:
> `2·n1·n2 → n1+n2`. Wall time with luminosity scheduled off, n=20k,
> grid 64: **75.5 → 39.0 ms at ns=16** — the removed ~36 ms matches the 480
> deleted solves; the remainder is the per-pair eval/kick work the pair
> structure requires. With the default per-pair luminosity on, the gain is
> smaller (86 → 56 ms) because those pair-dependent overlap deposits — which
> cannot be hoisted without changing numbers — now dominate; recorded, not
> chased. `:grid_free` keeps per-pair mode sums, noted in the code.

The list as it stood before that follow-up:

- **R8** — the CUDA `:equal_area` histogram costs 10–20× more than needed,
  and at the default `nslices=1` its only consumer is an empty loop. Pure
  performance; needs the benchmark discipline this session had no room for.
- **R12** — `_spectral_collide_transverse!` does `n1·n2` field solves where
  `n1+n2` suffice (the source mesh is identical for every field slice).
  Same category.

## 8. The concurrency sweep — the non-CUDA half, closed

The open `docs/todo.md` item asked for the sweep the 2026-08-03 audit
prescribed: lowered code, not grep. Done module-wide, and made permanent.

**The Box sweep.** All **2,175 methods** defined by the module were swept for
`Core.Box` allocations in their lowered code. **Nine** carry boxes. Cross-
referenced against the complete concurrency surface — **17
`_run_logical_workers` call sites, all funnelling through the single
`Threads.@spawn` in `Policies.jl`, and no raw `@async` outside the CUDA
files — exactly **one** boxed method contains concurrent closures:
`_spectral_collide_longitudinal!`, the luminosity box parts 1 and 6 already
confirmed benign (the workers only read it, through `typeof`; the write is
outside the `do`; the spawn is `@sync`-joined). The other eight are serial:
a constructor with branch-reassigned locals, two file-I/O helpers, two
contract helpers, the one-shot Symbolics adapter activation, and the two
`fusedTrack` `@generated` generator bodies (compile-time by construction).

**Made permanent.** The sweep is now a suite testset with an argued
allowlist — each entry carries its benign-ness argument, and generator
bodies are allowed by the `file == "none"` predicate rather than by name.
Discriminating power verified by injection: a deliberate
assigned-in-closure-and-function variable in a `_run_logical_workers` caller
is caught by name and line, and the clean tree reports zero offenders. This
is the guard part 6 §4 said did not exist: the natural refactor
`luminosity += local_lum` inside the closure now fails the suite instead of
silently reproducing the `_threaded_histogram` defect.

**Thread-count invariance.** Identical inputs at 1, 4 and 8 logical workers
across **14 configurations** — the five CPU solvers (PIC, Gaussian-PIC
hybrid, soft-Gaussian, spectral transverse and longitudinal), all four
slicing methods with and without z ties, and aperture loss accounting at
20k particles: **coordinates and counts bit-identical everywhere**. One
1-ulp exception, measured and then understood rather than papered over: the
spectral luminosity total is assembled from per-worker partials, and the
fold order moves it by exactly one ulp of a 4.75e14 total between
`nchunks = 1` and `nchunks > 1` — every `nchunks ≥ 2` is bit-identical to
every other. Coordinates cannot reassociate (kicks are chunk-local), and
the permanent invariance testset asserts exactly that split: coordinates
`==`, spectral luminosity to a few ulp.
- From part 7, unchanged: nothing — T1–T11, G1–G4, C1–C3, K1–K8 are all now
  settled.
- The CUDA spectral deposit has no tripwire (the CPU one is new); the
  strong-kick reachability applies there too.
- The `fits`/backend interplay for a line kept whole (aperture inside a
  composite runtime is never bound to a loss record) — recorded in part 8 §4,
  still open.

## 9. The h ≠ 0 × transverse-field cross-product sweep — clean, with one incidental find

The last open sweep from `docs/todo.md`: any element accepting a curvature
AND a transverse field must route non-normal-dipole content through the
curved potential, because the straight kick is a gradient iff `h·Im f ≡ 0` —
the condition the 2026-03-08 audit found violated twice (2.5e-3 .. 3.2e-2 of
symplecticity).

**The element list is derived, not assumed.** Enumerating every registered
kind's parameter schema for curvature keys (`h`, `angle`) crossed with field
keys: exactly two kinds carry both — `:sbend` and `:solenoid`. The straight
magnets do not offer `h` at all (combined-function content goes through
`SBendSpec` by design), and the only non-schema channel — the shared
`LatticeMagnet` compile reads `:h` with a default for every kind — was swept
explicitly by compiling a raw quadrupole spec with an undeclared `h` and
skew content: it routes through the same `_needs_curved_potential` gate,
residual 5.6e-16.

**The instrument, validated against the recorded defect.** Symplecticity
residual `max|JᵀSJ − S|` from an exact ForwardDiff Jacobian. Fed the
pre-fix configuration deliberately — the straight `_lattice_kick` with skew
dipole at `h = 0.05` — it reports **2.5000e-3 against the analytic
prediction `L·h·Ks₀ = 2.5e-3`, ratio 1.0000000000000002**. The suite keeps
that self-check as the sweep's permanent negative control.

**The grid: 29 configurations, all clean.** Ten content cases (every order,
normal and skew, alone and combined) on the sbend at machine epsilon
(2e-16 .. 3e-15), through eight structural variants (`nst` 1/2/8, integrator
order 4, `:drift_kick`, fringes on/off/multipole, `h ≠ b0`); the same ten
contents on the curved solenoid at ~9e-15; the undeclared-`h` quadrupole.
The one number above epsilon is the **pure** curved solenoid at `nst=4`:
1.11e-9 — which is the *documented* fixed-point convergence floor of the
16-sweep implicit midpoint (the committed table beside
`_SOL_MIDPOINT_ITERS` says 1.4e-9 there), and it collapses to 1.1e-16 at
`nst=16`. Convergent with `nst` is precisely the opposite of the structural
signature this sweep hunts, where refinement changes nothing.

**The incidental find.** The sweep's instrument would not run at first: the
curved solenoid was a `MethodError` under a coordinate Jacobian with
`Float64` elements, because `_sol_log_over_h(::T, ::T)` demanded matching
types and a Dual coordinate meets a Float64 curvature there — the same
strict-signature class as part 7's G1, invisible to the parameter-derivative
sweep (spec-level duals make both arguments dual). Fixed by promotion
through `u = h*x`; the permanent sweep testset now exercises exactly that
Jacobian, so the regression cannot return silently.

## 10. The reading program: provenance upgraded where it was weakest

Parts 6–7 completed line coverage of `src/`, but ~10,000 lines carried
agent-only provenance. This session upgraded the highest-risk regions to a
direct human read, and reconciled the stale ledger rows.

**`spectral_cuda.jl` — now human-read in full (806 lines), and clean.** The
comparative read against the now-well-verified CPU reference confirms: the
6D interp-scatter kernel is a line-for-line transcription of the CPU
sequence (same degenerate-slice guard, same drift-back with new momenta,
same pz restore); S20's masked boxes are in place on both variants with the
fail-fast preserved for the unmasked case; the snapshot dance gives
direction 2 and the luminosity both beams' PRE-kick states, matching the
CPU's copy semantics; and the DST/DCT-from-rfft pipeline matches the CPU
plan structure transform for transform, including the potential's ½ factor
and the shared-transform saving. Load-bearing check: CPU/CUDA parity through
the 6D path measured at **5.7e-15 on kicks and 2e-16 on luminosity**, with
and without an S20-shaped dead particle. Three ledger notes, none
defect-grade: the CUDA transverse path still solves per pair (R12's hoist is
CPU-only; the path is doubly non-default), it allocates `Exg`/`Eyg` per pair
against its own comment's claim of buffer reuse, and the R9 dropped-charge
tripwire remains CPU-only (recorded in §7).

**`pic_cuda.jl` tail — the agent-read remainder is now mostly human-read.**
The CUDA slicing block (dispatcher, live stats, all five methods, both
finishers) and the soft-Gaussian sequential collide were read directly:
R1's rank-membership fix reads exactly as recorded and mirrors the CPU;
the sequential collide freezes both beams' moments before either kick, so
the direction order cannot leak state; exactly one kick kernel samples the
luminosity buffer. Still agent-only: the ~450 lines of Gaussian moment and
kick kernels (l. ~5490–5960), which part 6 verified for the tree-reduction
safe-halving form and which the backend-consistency contracts exercise
continuously — kept on the ledger as agent-read, not claimed.

**Ledger corrections.** The `todo.md` strong-strong row predated parts 6–7
and still listed ~6,500 lines as unread; the `spectral.jl` row still said
"completely unaudited" although part 6's own history note records that its
agent resumed and finished. Both rows now state the actual provenance:
every line read by someone; auditor-direct coverage now spanning parts 1–5
plus this session's upgrades; the enumerated agent-only remainder above.
