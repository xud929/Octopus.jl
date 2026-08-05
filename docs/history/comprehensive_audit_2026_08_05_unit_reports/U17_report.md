# U17 audit report — test/runtests.jl lines 3800–7766 (end of file)

Repo: /cfs/ad/dxu/Library/Julia/Octopus, branch main (HEAD 6a3f39a, post-83e1d38).
Read: every line 3800–7766, plus context 3740–3799 (the testset whose body spans the range
start), the file header 1–40 (CUDA gating policy comment), `.github/workflows/ci.yml`,
`validation/symplecticity_validation.jl` (structure), `validation/high_energy_weakstrong_limit.jl`
(structure), and `src/tasks/strongstrong/interface.jl:460–480` (lost-particle kbb contract).

## Coverage

- Lines 3800–7766: tail of `@testset "StrongStrongTask chunking preserves stochastic physics"`
  (opens 3765) + **75 complete top-level testsets** (3814 "Zero-width PIC slice remains finite"
  through 7734 "Dropped PIC charge reaches a reader"), of which 14 live inside the
  `if Octopus._HAS_CUDA && Octopus.CUDA.functional()` block at 6365–7077.
- Also in range: helper functions (test_beam, nonfinite_test_rep, expect_nonfinite_error,
  loss_test_*, aperture_beam, coords_identical), two top-level `include`s of validation
  scripts (6335, 6345), and 24 CUDA-gated sites.

## Leads

### U17-1 — CUDA gating reports green instead of skipped (lines 7281–7347, 7350–7396, 7399–7451, 5831–5873, 6365–7077, 7512–7538) — MEDIUM

The file header (lines 12–29) states the rule itself: "do not report an unrun check as
passed." Three testsets violate it directly:

- `"CUDA GaussianPIC honours green_cache=:slice_pair"` (7281): `else @test true` at 7344–7345.
- `"CUDA GaussianPIC emits PIC phase timing records"` (7350): `else @test true` at 7393–7394.
- `"CUDA PIC parity across every execution route"` (7399): `else @test true` at 7448–7449.

On a CPU-only machine each records a **passing test**, indistinguishable in the summary from
a run that verified anything. These three guard three separately-diagnosed regressions
(green-cache grid mismatch 4.7e-6, empty timing records, stale-coordinate luminosity 1.8e-4)
— the regressions could all return and CPU CI stays green with three extra "passes".

Additionally:
- `"CUDA GaussianPIC coupled subtraction matches CPU"` (5831): `if` with **no else** — the
  testset is empty on CPU and passes silently with zero assertions.
- The block 6365–7077 wraps **14 testsets** that simply do not exist on CPU — no skip
  records at all (mitigated only by the single aggregate `@test_skip` in "CUDA coverage
  status" at line 31).
- `"PIC green_type=:lattice"` (7454): its part (e) CPU/CUDA parity sweep (7512–7538) is an
  `if` with no else inside an otherwise-CPU testset — silent partial shrink.
- The header inventory is stale: it claims "Nine testsets are gated... three carry an
  `else @test_skip` and six are silent"; in this range alone there are 24 gated sites
  (6 honest `@test_skip`: 3858, 3914, 4249, 4294, 4565, 4973; 1 empty-if; 14 silent;
  3 `@test true`; 1 partial). The aggregate @info message ("Nine CUDA-gated testsets were
  skipped") under-reports by ~2.5x.

Repro: none needed — grep `else` bodies; contrast with the honest skips at 3910, 3969, 4290.

### U17-2 — "Spectral solver reproduces soft-Gaussian kick" (5310–5338) cannot see a missing, doubled, or sign-flipped kick — MEDIUM-HIGH

Claim: "Both spectral variants reproduce the analytic Bassetti-Erskine kick ... well under
3%." Assertions (5335–5336) compare `rms(final momentum)` ratios, **not kicks** — unlike the
adjacent GaussianPIC testset (5270) which correctly computes `kick = px .- px0`.

Probe (`scratchpad/U17/probe_spectral_rms_power.jl`, exact test configuration) measured:

- proton beam: kick is only **4.8%** of the intrinsic py spread. Zero kick → ratio 0.9982
  (passes atol=0.03); doubled kick → 1.0041 (passes); flipped sign → 0.9987 (passes).
  **The beam2 assertion is vacuous** — a spectral solver applying no kick whatsoever to the
  proton beam passes.
- electron beam: kick/spread = 1.32, so zero (0.60) and double (1.70) fail — good — but a
  **sign-flipped** kick gives ratio 0.9887, which passes atol=0.03. rms is sign-blind up to
  the (small) x–px cross-correlation.

Mitigations elsewhere are partial: 5784 pins the *field routines'* scale and sign
(needed_scale ≈ +1), and the high-energy limit validation (6347, `spectral_limit_atol=5e-12`,
`validation/high_energy_weakstrong_limit.jl` `spectral_weakstrong_limit_reference!`) pins the
kick wiring **onto the proton/probe beam** in the frozen-source limit. But the kick the
spectral collide! applies to **beam1** in a two-live-beam configuration is pinned by nothing
on CPU except this sign-blind rms ratio and CPU/CUDA parity. Fix shape: subtract the stored
initial momenta (already available as the pattern at 5286–5299) and compare kick vectors.

### U17-3 — "Lost particles cannot influence a strong-strong collision" (4153–4196) has no corpse-free reference; lost-particle charge semantics are unpinned and provably solver-inconsistent — MEDIUM

The testset's only value assertions are `values[1] == values[2] == values[3]` across three
corpse *variants* plus `isfinite` plus the no-flag throw. Any defect that is
corpse-content-independent — e.g. normalizing a deposit, kbb, or luminosity by the wrong
*count* (total vs live) — produces identical values in all three variants and passes.

Probe (`scratchpad/U17/probe_corpse_reference.jl`, npart pinned equal, explicit kbb):

- Gaussian solver: masked-poisoned vs survivors-only collision — luminosity reldiff **0.0**,
  clean-beam coordinate diff **0.0**. The Gaussian solver renormalizes: a dead particle does
  NOT reduce the bunch charge (slice weights are live fractions summing to 1, per 4222).
- PIC solver: luminosity reldiff **2.6e-2**, clean-beam coordinate diff 0.44 against a kick
  magnitude ~1.4. PIC keeps `kbb/n_total` per macro (documented and defended at
  `src/tasks/strongstrong/interface.jl:471–476`: "the bunch carries proportionally less
  charge"), so 3 dead of 4000 reduce charge by 3/4000, amplified by this configuration's
  O(1) kicks.

So the two solver families implement **opposite** lost-particle charge semantics — the exact
choice interface.jl calls "the wrong physics" in its own PIC context — and no test in the
suite observes either: the corpse-variant equality is blind to it by construction, and the
slicing testset (4198) checks weights only. At minimum the suite should pin each solver's
intended semantics explicitly (masked vs survivors, expecting equality for Gaussian and the
documented 3/4000 charge deficit for PIC). Whether the inconsistency itself is a code bug is
for the auditor; the test gap is established.

### U17-4 — "PIC kbb override uses physical units" (5072–5104) is circular — LOW

`_pic_kbb1(over, e, p) == _pic_kbb1(base, e, p)` where `over`'s kbb1 *is*
`_strong_strong_kbb1(base, e, p)` — the override path is asserted against the derived path
of the same module, and the collision equality (5099–5101) is the same comparison end-to-end.
A common-mode defect (e.g. both paths dropping the /n_macro division the comment names) passes
both assertions. The absolute scale is backstopped only by the physics contracts
(`wsl.metrics[:pic_luminosity_relative_error] <= 0.08`, line 7242) at the far end of the file.
The testset does catch its historical defect (override-only skip); it just cannot catch the
common-mode version its comment implies it guards.

### U17-5 — CPU tie-robustness invariant needlessly GPU-gated (3858–3912) — LOW

`"CUDA :equal_count is equal-count even when z has ties"` gates *everything* behind
`CUDA_TESTS_ACTIVE`, including the CPU-side assertions: the premise
(`length(unique(z)) < n ÷ 10`) and the CPU slicer's exact equal-count under quantized z
(`maximum(cc) - minimum(cc) <= 1` for `Octopus.longitudinal_slices`). The comment itself
notes ties are "routine for a Float32 beam" — yet on every CPU-only run (i.e. all of CI,
per ci.yml ubuntu-latest) the CPU invariant is skipped along with the CUDA one.
Probe (`scratchpad/U17/probe_cpu_tie_slicing.jl`): the CPU half runs GPU-free in seconds and
passes (64 unique z of 2000; spreads 0 and 1 for ns=5, 9). The `@test_skip` is honest about
the CUDA half; the CPU half's exclusion is the silent shrink.

### U17-6 — "Spectral CPU workspaces are reentrant" (5340–5393): the end-to-end race check has no guaranteed concurrency — LOW

The two `Threads.@spawn collide!` tasks (5376–5379) only exercise reentrancy if the scheduler
actually interleaves them; at `nthreads()==1` (any hand run without `-t`) they serialize and
the comparison passes even with a shared-workspace defect present. CI runs `--threads=4`
(ci.yml:28) so there is *some* chance of overlap, but no assertion establishes that overlap
occurred. The load-bearing pins are the direct lease assertions (5343–5351: distinct leases,
distinct workspaces) — those are good; the spawned section is best-effort and should not be
read as a race test.

### U17-7 — Load-bearing ordering: the tight physics backstops sit at the end of the file — INFO

Under the suite's abort-on-first-failure property (this audit's F2), everything after an
aborting set goes unexecuted. In this range the *loose* smoke version of the weak-strong
limit runs at 6347 (rtol 0.60 / 0.80) while the *tight* pins — symplecticity validation
(include at 6335, testset 6337), `HighEnergyWeakStrongLimitContract` at 8% (7239–7242), and
the Yokoya coherent-mode contract with its executed negative control (7249–7255) — run last,
after the entire CUDA block and Knob control. Any abort anywhere in lines 1–7233 silently
drops the only tests with real discriminating power on absolute beam-beam physics, while the
partial output still shows the loose 6347 set green. The two top-level `include`s (6335,
6345) are themselves abort points outside any testset.

### U17-8 — Minor assertion-strength notes — LOW

- 7757–7760 (`"Dropped PIC charge reaches a reader"`): `@test_logs (:warn,) run(...)` pins
  that exactly one warning fires but never checks its content — a warning reporting a
  garbage count passes. (`_pic_count_outside` unit tests pin counting, not the wiring of the
  count into the message.)
- 7634–7640 (`"Source and field grids keep equal extent"`): the comment claims a "negative
  control: the equality is a real constraint, not trivially true", but
  `@test sg.width != fg.width * 1.01` only excludes the width==0 degenerate case; it does not
  demonstrate the test would fail under any grid-sizing defect. Comment overstates (class 3).
- 4519 (`"Aperture loss record"`): of the six recorded pre-kill coordinate columns only
  `losses.x` and `losses.pz` are checked finite.
- 4233: `@test Octopus.longitudinal_slices(poisoned, sl) isa Any` — the `isa Any` is
  vacuous as a value check; it pins only "does not throw" (which is the intent, but worth
  knowing it asserts nothing about the result).

## Claims checked and found sound (no lead)

- 4500–4507 concurrency comment: CI really does run `--threads=4` (ci.yml:28), and the
  `skip = (Threads.nthreads(:default) == 1)` conditional skip is honest.
- 6337: `run_symplecticity_validation` maps over a static literal tuple of cases
  (`symplecticity_cases()` returns a `(...)` literal), so `all(passed, results)` cannot pass
  vacuously on an empty collection.
- 4106–4151: the `atol=`-only tolerances are strict, not loose — Julia's `isapprox` sets
  rtol=0 when a positive atol is supplied, so `mean ≈ ... atol=1e-18` is a near-exactness pin.
- 4479–4539: loss-record identities (one record per dead, per-aperture counter agreement,
  pre-kill coordinates, file round-trip) are exact-equality pins with the premise
  (`dead > 0`) asserted.

## Strong tests (discriminating power verified)

1. **"Exact solenoid map"** (4715) — independent reference: RK4 integration of Hamilton's
   equations from the theory note at atol=1e-12 for three strengths; plus Larmor half-angle
   magnitude, p_s invariant (rtol 1e-14), invertibility, chromaticity presence, axisymmetry.
2. **"Patch: deliberate change of reference frame"** (4633) — pitch NON-invariance pinned
   quantitatively (≈ L·θ, rtol 0.2), convention discrepancy pinned at product-of-angles
   magnitude (≈ 0.012·0.3, rtol 0.05), FD symplecticity < 1e-8; single-axis degeneracy of the
   convention explicitly argued and asserted (`==` between conventions on one axis).
3. **"Solenoid in a curved frame"** (4843) — cross-implementation reference (SBend/
   `_curved_kick` path, no implicit midpoint) at 1e-6 where the guarded structural error was
   9.6e-4; convergence-order ratios *bracketed both sides* (12 < ratio < 20), which fails for
   wrong order in either direction; symplecticity at coarse nst (the check a truncated
   implicit solve would fail).
4. **"GaussianPIC coupled (rotated) subtraction"** (5875) — brute-force 2D quadrature of the
   tilted Gaussian as reference; both a relative bound (10x better than axis-aligned) and an
   absolute one (2%).
5. **"Spectral field absolute normalization is derived, not fitted"** (5784) — deliberately
   un-fitted least-squares scale must already be 1 ± 0.005 where the historical defect gave
   0.982; refinement direction pinned. Also catches field-level sign flips (scale → −1).
6. **"Lost particles are excluded from every reduction"** (4106) — independent survivor-beam
   reference, atol-only (rtol=0) near-exact pins, and the unmasked negative control actually
   executed (`!isfinite(...)`, `any(!isfinite, ...)`).
7. **"PIC field_derivative flag"** (5395) — default pinned bit-for-bit, consumer reach pinned
   by inequality, and accuracy against the *exact* Bassetti-Erskine kick with the measured
   1.6x gain bounded at 0.75.
8. **"Green-cache expansion preserves the grid alignment"** (7643) — genuine in-test negative
   control: the defect is demonstrated (`frac(dxE − want) > 0.1`) before the fix is asserted,
   so the assertion cannot pass vacuously; plus refusal path for fractional separations.
9. **"Physics contracts"** (7234) — the negative control is *run*: the soft-Gaussian closure
   is asserted to FAIL the Yokoya band (`@test !gau.passed`) with the ordering
   `gau.metrics < coh.metrics` pinned.
10. **"Strong-strong shifted moments preserve small spreads"** (5135) — offsets sized
    (1e4/Float32, 1e8/Float64) so naive E[x²]−E[x]² accumulation is catastrophically wrong
    (eps(offset²) ≫ spread²), making the default-rtol `≈` genuinely discriminating.
11. **"An aperture that kills nothing changes nothing"** (4431) — bit-identity via elementwise
    `===` (NaN-safe), premise `count_dead == 0` asserted, across plain tracking, weak-strong
    (including `last_luminosity ===`), and all four strong-strong solvers.
12. **"StrongStrongTask chunking preserves stochastic physics"** (3765/3800) — exact `==`
    across chunked executions with the RNG reseeded per arm; no tolerance to hide behind.

## GPU-dependent checks left as recipes for the auditor (not runnable here)

- 3858: CUDA equal-count with z ties — run on GPU host; verify `cg == cc` and identical
  membership for ns=5,9 with quantized z, and the no-ties sweep ns=1,4,15.
- 3914: `_cuda_spectral_box` masking parity at rtol 1e-12 plus fail-fast with flag off.
- 4249, 4294, 4565, 4973, 5831, 6365–7077 block, 7281, 7350, 7399, 7512: execute the suite on
  a CUDA host and confirm the assertion counts of these testsets are nonzero in the summary
  (per U17-1 three of them will report exactly one vacuous pass on CPU; on GPU they must
  report dozens).
- Note while there: "CUDA GaussianPIC solver matches CPU" (6804) comments a "1e-10 contract"
  and measured ~1e-13 but asserts rtol=1e-9 — tolerance an order looser than the stated
  contract.

## Probes

- `scratchpad/U17/probe_spectral_rms_power.jl` — U17-2 (output in report; ~20 s).
- `scratchpad/U17/probe_corpse_reference.jl` — U17-3 (~30 s).
- `scratchpad/U17/probe_cpu_tie_slicing.jl` — U17-5 (~10 s after precompile).
