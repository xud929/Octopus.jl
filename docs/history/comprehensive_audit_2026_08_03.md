# Comprehensive Audit — 2026-08-03

A repository-wide audit run against the protocol in
[`docs/comprehensive_audit.md`](../comprehensive_audit.md). **Five confirmed
defects, all fixed**, every one of them in code whose tests were passing.

Two of the five are the same Julia closure-capture bug in two different files,
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

The remaining 41 `validation/` scripts were not run.

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

## 12. Change log

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
