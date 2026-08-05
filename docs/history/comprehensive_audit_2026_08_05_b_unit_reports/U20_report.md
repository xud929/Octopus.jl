# U20 audit report — test/runtests.jl lines 6600–8759 (end of file)

Repo: `/cfs/ad/dxu/Library/Julia/Octopus`, HEAD `7de4d81`. Julia 1.12.4.
Machine: NVIDIA RTX 4500 Ada, driver 580.119.02, `CUDA.functional() == true`.

## Provenance

**Read (every line):** `test/runtests.jl:6600–8759`, plus context `6595–6599`
(the testset whose body spans the region start), the file header `1–53` (CUDA
gating policy + `CUDA coverage status`), and the diff
`git diff 6a3f39ab HEAD -- test/runtests.jl` in full (1,561 lines).
Also read for cross-checking: `AGENTS.md` "Hard-Won Rules";
`docs/comprehensive_audit.md` Phase 9 + Measured Lessons;
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U17_report.md`;
`src/knobs/Knobs.jl:58–113, 364–434`; `src/knobs/symbolic.jl:46–58`;
`src/tasks/strongstrong/pic_cpu.jl:995–1101, 1208–1211, 1545–1570`;
`src/tasks/strongstrong/pic_cuda.jl:4329–4360`;
`src/tasks/strongstrong/spectral_cuda.jl:27–53, 416–477`;
`src/beam/Beam.jl:1–21`; `docs/knob_control.md:25–35`; `Project.toml`.

**Executed:** every probe below ran in a scratch environment at
`scratchpad/audit/env` (Octopus dev'd from the repo + Test/ForwardDiff/Symbolics,
matching `Project.toml [targets] test`). **No repository file was modified.**
Defect injection was done by redefining the implementation function inside the
loaded `Octopus` module at runtime (`Octopus.eval(quote … end)`), with the
verbatim testset text extracted by `sed` and `include`d unchanged — so the test
source under measurement is byte-identical to the repository's.

Probe scripts (all under `scratchpad/audit/`): `prelude.jl`, `p1_gate.jl`,
`run_cuda_block.jl`, `run_gates.jl`, `pA_knob_roundtrip.jl`, `pA3_knob_fuzz2.jl`,
`pA4_minimal.jl`, `pA5_flatten.jl`, `pA6_valuechange.jl`, `pB_tsc_sensitivity.jl`,
`pB2.jl`, `inj_tsc.jl`, `inj_dropped.jl`, `inj_grids.jl`, `inj_grids2.jl`,
`inj_knob.jl`, `inj_spec.jl`, `pT_tolerance.jl`, `pT2.jl`, `pT3.jl`,
`pF_final.jl`, `pF2.jl`.

## Scope note: the briefed campaign testsets are NOT in this region

Of the nine testsets the recorded closure claims, **none** lands in 6600–8759.
Measured line numbers: replay-discard 3815; luminosity_append 3506; MomentObserver
append 3615; Philox KAT 3873; wrappers/streams/apertures 3899; exports-documented
3397; placement keys 3704; CUDA pz/`:node` 4939; all-kinds backend consistency
4247–4270; solenoid 5390/5471/5518/5648. They belong to an earlier reading unit.

What is actually **new at HEAD inside this region** (from the diff):

| line | what changed |
|---|---|
| 7572–7627 | NEW testset "CUDA spectral deposit tripwire (R9, U9-1)" (5 checks) |
| 7629–7645 | NEW testset "TSC weights are bit-identical across backends (U2-3)" (1 check) |
| 8064–8067 | NEW `knob_symbolics_available()` public-query asserts (2 checks) |
| 8080–8171 | NEW testset "Knob registry atomicity and round-trip totality" (~30 checks) |
| 8284, 8333, 8388 | `else @test true` → `else @test_skip "CUDA device not available"` (3 sites) |
| 8573–8588 | "Source and field grids keep equal extent" — negative control rewritten |
| 8707–8758 | "Dropped PIC charge reaches a reader" — 6 new asserts + source-side drop block |

---

## LEADS

### LEAD U20-1 [Major, confidence high] test/runtests.jl:7629 ("TSC weights are bit-identical across backends (U2-3)")
Claim: this new testset cannot fail on the defect its own comment names — its
entire sample grid is dyadic, and the `w3 = 1 - w1 - w2` complement is
bit-identical to the closed form on every dyadic input.
Mechanism: the sweep is `range(0.0, n-1.0; length=257)` for `n ∈ (16, 33)` plus
`[0.5, 1.5, 7.25, 7.5, 7.75, n-1.5, n-1.0]`. The step is `15/256` (n=16) and
`32/256` (n=33) — both dyadic rationals — so every fractional part `f` has few
significant bits. For dyadic `f`, `t = f*f`, `0.75 - t` and `0.125 + 0.5*(t ± f)`
are all exact, so `w1 + w2 + w3 == 1` exactly and the complement rounds to the
same Float64. Measured: **0 of 528** in-range samples expose the defect, while
**68.3% of random `f ∈ [0,1)` do** (1,366,189 of 2,000,000). The recorded U2-3
defect, re-injected verbatim into `Octopus._cuda_pic_tsc_weights`, is **not
caught** (testset passes). A clamp-bound defect *is* caught, so the testset is
not inert — only blind to the one thing it was written for.
Repro:
```
julia --project=<env> scratchpad/audit/pB_tsc_sensitivity.jl
  # "testset grid: 528 in-range samples, 0 expose the w3 = 1-w1-w2 defect"
  # "random f in [0,1): 1366189 of 2000000 (68.309%) differ"
julia --project=<env> scratchpad/audit/inj_tsc.jl
  # baseline => PASSED;  inj1-complement (the recorded defect) => PASSED (not caught)
  # inj3-clamp-lower => FAILED (caught)
```
Fix shape: add one non-dyadic `u` to the sweep. `f = 0.3, 0.1, 1/3, 0.7` each
differ at 1 ulp between the two forms (verified, `pB2.jl`).

### LEAD U20-2 [Major, confidence high] test/runtests.jl:8080 ("Knob registry atomicity and round-trip totality")
Claim: the "round-trip totality" half is not total — the documented invariant
`knob_expression(string(e)) == e` (docs/knob_control.md:30, `Knobs.jl:64–67`) is
FALSE for `*` and `+`, and the violation changes the evaluated value.
Mechanism: the printer drops parentheses around a nested `*`/`+`, so
`(a*b)*c` and `a*(b*c)` both print as `a * b * c`; reparsing yields a **flat
3-ary** `KnobCall`, structurally unequal to the binary original. Float `+`/`*`
are not associative, so the reparse can evaluate differently. The new testset
pins exactly this class for `^` (U14-2) and for `NaN`/`Inf`, but never for the
n-ary operators, so the class regenerated one operator to the left.
Measured value change: `t_m.x = 1e16`, `t_m.y = -1e16`, `t_m.z = 1.0`;
`e = knob_expression("t_m.x + (t_m.y + t_m.z)")` → `knob_value(e) == 0.0`;
`knob_value(knob_expression(string(e))) == 1.0`. A fuzz over 52,391 parsed and
differentiated trees found 1,716 round-trip failures and 143 value changes.
Repro:
```
julia --project=<env> scratchpad/audit/pA6_valuechange.jl
  # string(e) = "t_m.x + t_m.y + t_m.z"; 0.0 -> 1.0; contract == : false
julia --project=<env> scratchpad/audit/pA5_flatten.jl
  # * and + : ==  false ;  - / ^ min max : == true
```
Out-of-hypothesis note: this is a defect in `src/knobs/Knobs.jl`'s printer, not
only a test gap. Flagged here because the in-region testset claims to guard it.

### LEAD U20-3 [Major, confidence high] test/runtests.jl:7133 (and 6604, 8451)
Claim: on a CPU-only host **17 testsets and 402 of the 415 GPU-gated assertions
in this region vanish with no skip record**; only 3 of 6 gates are honest.
Mechanism: `if Octopus._HAS_CUDA && Octopus.CUDA.functional()` with no `else`.
Measured, by running the extracted testsets twice (with GPU, and with
`CUDA_VISIBLE_DEVICES=""`):

| gate | testsets | GPU asserts | CPU-only result |
|---|---|---|---|
| 7133 block | 16 | **358** | `Total 0` — block does not exist, silent |
| 6604 | 1 | 14 | `Total 0` — empty testset, silent |
| 8451 (tail of 8393) | partial | +5 (15 vs 10) | silent partial shrink |
| 8232 | 1 | 7 | `Broken 1` — honest skip ✓ |
| 8293 | 1 | 9 | `Broken 1` — honest skip ✓ |
| 8351 | 1 | 12 | `Broken 1` — honest skip ✓ |

The three `else @test_skip` conversions in the diff **work as advertised** — they
report SKIPPED, never PASSED. The remaining three gates are the F20 class the
file header itself forbids.
Repro:
```
julia --project=<env> --threads=4 scratchpad/audit/run_cuda_block.jl
  # REGION-CUDA-BLOCK | Pass 358 Total 358  3m45.5s
env CUDA_VISIBLE_DEVICES="" julia --project=<env> scratchpad/audit/run_cuda_block.jl
  # REGION-CUDA-BLOCK | Total 0   1.6s
julia --project=<env> --threads=4 scratchpad/audit/run_gates.jl        # with/without GPU
```

### LEAD U20-4 [Medium, confidence high] test/runtests.jl:7199 ("CUDA near-round Gaussian transition matches CPU")
Claim: at `T = Float32` the near-axis sample point cannot detect a zero,
sign-flipped, or 10×-wrong kick. `atol = 3.0e-5` exceeds `|Kx| ≈ 9.5e-7` by 45×.
Mechanism: `@test Array(output) ≈ collect(expected) rtol=tolerance atol=tolerance`
compares the 4-vector `(Kx, Ky, H1, H2)` as a whole; the Hessian components are
`O(1)` and set the vector norm, while the kick components at
`(x,y) = (1e-6, -5e-7)` are `O(1e-6)`. Julia's `isapprox` uses
`norm(x-y) <= max(atol, rtol*max(norm...))`, so the kick's effective tolerance is
`max(3e-5, 3e-5*1.41) = 4.27e-5` — 45× the quantity itself.
Measured: at `T=Float32`, **5 of 25 (eta, point) samples accept a zero kick** —
all five are the near-axis point, at every `eta`. Setting `Kx,Ky → 0`, `→ -Kx,-Ky`
and `→ 10Kx,10Ky` all pass; only `1000×` fails. At `T=Float64`, 0 of 25 are
vacuous (that leg is sound).
Repro:
```
julia --project=<env> scratchpad/audit/pT2.jl   # Float32 table: zero/flipped/x10 all "true"
julia --project=<env> scratchpad/audit/pT3.jl   # "T=Float32: 5 of 25 ... accept a zero kick"
```

### LEAD U20-5 [Medium, confidence high] test/runtests.jl:7173 ("CUDA round Gaussian near-axis stability")
Claim: the testset's named subject — near-axis kick stability — is compared under
a tolerance set by the Hessian, so a 1% (Float32) / 5e-7 (Float64) relative error
in the kick passes.
Mechanism: the same vector-norm `isapprox` on a 5-vector
`[kx, ky, hxx, hxy, hyy]`. Measured expected vectors:
`Float32 [1.0e-4, -5.0e-5, -1.0, -2.5e-9, -1.0]`, norm 1.414, tolerance
`16eps(Float32)*1.414 = 2.70e-6` → **2.7% relative headroom on kx**;
`Float64 [1.0e-8, -5.0e-9, -1.0, -2.5e-17, -1.0]`, tolerance `5.02e-15` →
**5.0e-7 relative headroom on kx**. Injected relative errors of 1e-2 (Float32)
and 1e-7 (Float64) in `kx,ky` both pass. The only kick-specific guards are
`actual[1] != zero(T)` / `actual[2] != zero(T)`, which catch total collapse only.
Repro:
```
julia --project=<env> scratchpad/audit/pT_tolerance.jl
  # "max RELATIVE error on kx that still PASSES: 0.026973983"  (Float32)
  # "max RELATIVE error on kx that still PASSES: 5.024e-7"     (Float64)
julia --project=<env> scratchpad/audit/pT2.jl   # 7173 rows
```
Fix shape: compare the kick sub-vector and the Hessian sub-vector separately, or
elementwise with a per-component relative bound.

### LEAD U20-6 [Medium, confidence high] test/runtests.jl:7572 ("CUDA spectral deposit tripwire (R9, U9-1)")
Claim: this new testset verifies "leaves exactly its unit charge" using only a
**fully** out-of-box particle, so it cannot distinguish charge from particle
count, and cannot see a tripwire that ignores partial clipping.
Mechanism: the probe particle sits at `5.0e-3` with `Lx = 1.0e-3` — entirely
outside, `written == 0`, `clipped == 1.0`. A per-particle counter and a
"count only if fully outside" counter both report exactly `1.0` here.
Injection results (defect injected into all three
`_cuda_spectral_deposit*_kernel!`): **2 caught of 4**.
- silent clipping (the recorded R9/U9-1 defect) → CAUGHT (4 of 5 asserts fail)
- double count → CAUGHT (3 of 5 fail)
- `dropped += 1.0` (count particles, not charge) → **NOT caught**
- `written == 0 && dropped += clipped` (miss partial clipping) → **NOT caught**

The gap is one line wide: a particle at `x = 0.94*Lx` leaves `dropped = 0.49`
(measured), which discriminates all four.
Repro:
```
julia --project=<env> --threads=4 scratchpad/audit/inj_spec.jl
julia --project=<env> scratchpad/audit/pF2.jl
  # x = 0.94*Lx  dropped = 0.48999999999999844
```

### LEAD U20-7 [Low, confidence high] test/runtests.jl:8067
Claim: `@test knob_symbolics_available() === Octopus._symbolics_adapter_active()`
is circular by construction — `src/knobs/symbolic.jl:58` reads
`knob_symbolics_available() = _symbolics_adapter_active()`. The assertion compares
a function to its own body and can never fail.
Mechanism: the public wrapper is a pure delegation; there is no second
implementation for the `===` to disagree with. The load-bearing check is the
preceding line 8066 (`@test knob_symbolics_available()`), which does pin that the
weak-dep extension activated under `using Symbolics`.
Repro: `grep -n 'knob_symbolics_available() =' src/knobs/symbolic.jl` →
`58:knob_symbolics_available() = _symbolics_adapter_active()`.

### LEAD U20-8 [Low, confidence med] test/runtests.jl:8123 and 7992
Claim: two hand-copied case lists with no declaration-to-coverage tripwire, in the
testset whose name claims totality.
Mechanism: (a) `for name in (:pi, :π, :ℯ, :NaN, :Inf)` at 8123 is a hand-copy of
`keys(Octopus._KNOB_NAMED_CONSTANTS)` (`Knobs.jl:110–113`). It happens to be 5 of
5 today; nothing fails if a sixth constant is added. The authoritative dict is
already reachable from the test (`Octopus._knob_define!` is used two lines above),
so `for name in keys(Octopus._KNOB_NAMED_CONSTANTS)` is a one-word derivation.
(b) The round-trip loop at 7992–7999 covers **8 of the 24** entries in
`Octopus._KNOB_OPERATORS`: `* / - ^ + sin atan max`. Uncovered: `abs acos asin
cbrt cos cosh exp inv log log10 min sign sinh sqrt tan tanh`.
Measured: deriving the sweep from `_KNOB_OPERATORS` (every operator, both
arities, plus one nested level) gives **0 failures**, so the hand-pick hides no
live bug on that axis today — but see U20-2 for the axis it does hide.
Repro: `julia --project=<env> scratchpad/audit/pA_knob_roundtrip.jl`.

### LEAD U20-9 [Low, confidence high] test/runtests.jl:7629 (gating, not content)
Claim: "TSC weights are bit-identical across backends" is a **pure host-side**
comparison and is needlessly locked inside the `CUDA.functional()` block, so CI
never runs it. Same class as U17-5.
Mechanism: `_cuda_pic_tsc_weights` lives in `src/tasks/strongstrong/pic_cuda.jl`
under `if _HAS_CUDA`, and `_HAS_CUDA` is true whenever CUDA.jl merely *imports*
(CUDA is a hard dependency in `Project.toml`) — no device required. Measured with
`CUDA_VISIBLE_DEVICES=""`: `_HAS_CUDA = true`, `CUDA.functional() = false`,
`isdefined(Octopus, :_cuda_pic_tsc_weights) = true`, and the host call returns
`(7, 0.03125, 0.6875, 0.28125)`.
Repro: `env CUDA_VISIBLE_DEVICES="" julia --project=<env> scratchpad/audit/p1_gate.jl`.

### LEAD U20-10 [Low, confidence high] test/runtests.jl:8723
Claim: `@test Octopus._pic_count_outside_box([1.0, NaN, 2.0], …) == 1` cannot
distinguish an implementation with the `isfinite` guard from one without it.
Mechanism: every comparison with `NaN` is already false, so `xlo <= NaN <= xhi`
alone rejects the particle; the `isfinite` call in `pic_cpu.jl:1000–1001` is
redundant for finite bounds. Injection "NaN-blind" (guard removed) **passes**.
Not a live defect — behaviour is genuinely identical — but the assertion's stated
purpose (pinning NaN handling as a guard) is not what it measures. The guard does
matter for infinite bounds, which nothing exercises.
Repro: `julia --project=<env> --threads=4 scratchpad/audit/inj_dropped.jl` →
`D2-nan-blind => PASSED (defect NOT caught)`.

### LEAD U20-11 [Low, confidence high] out-of-region seam — test/runtests.jl:46–51
Claim: the `@info` a CPU-only user actually sees still says "**Nine**
CUDA-gated testsets were skipped". Measured in **this region alone**: 17 testsets
vanish plus one partial shrink, and 3 announce a skip. The surrounding comment
(lines 15–18) was updated to "More than twenty" but the message body was not.
Mechanism: the message is a hand-maintained count of a set that grows with every
new CUDA testset, with no tripwire. Line 48 is outside my region; recorded as a
seam and stopped.
Repro: `sed -n '42,53p' test/runtests.jl`; contrast with the U20-3 table.

### LEAD U20-12 [Info, confidence high] test/runtests.jl:7103, 7113 — carry-over of U17-7
Claim: the two `include`s of `validation/symplecticity_validation.jl` and
`validation/high_energy_weakstrong_limit.jl` are top-level statements **outside
any testset**, so a load error in either aborts the file rather than failing one
testset; and the tightest physics backstops (8173 `Physics contracts`, with the
8% weak-strong bound and the Yokoya negative control) still run after the entire
CUDA block. Unchanged since U17. The header now documents the ordering caveat
(lines 32–39), which is the honest half of the fix.
Repro: `sed -n '7103,7115p' test/runtests.jl`.

### LEAD U20-13 [Low, confidence med] test/runtests.jl:7679–7684 — carry-over of U17's "note while there"
Claim: the comment states "~1e-13: … well within the 1e-10 contract" and the
assertion is `rtol=1.0e-9` — an order looser than the contract the comment cites.
Same shape at 7544/7547 (`rtol=1.0e-9` with the same "agree to round-off" claim).
Mechanism: no mechanism beyond the number; flagged because the testset is the
load-bearing CPU/CUDA parity argument for `gaussian_pic_cuda.jl`, and a 1e-9
relative bound on coordinates whose largest component is `z ~ 6e-2` admits an
absolute drift of 6e-11 — 100× the measured residual.
Repro: `sed -n '7676,7685p' test/runtests.jl`. Not re-measured this session
(would need instrumenting the parity loop); reported as a reading claim.

---

## Testset inventory (region 6600–8759)

25 top-level testsets + 16 nested inside the CUDA block = 41. "Runs?" is measured,
not inferred.

| line | testset | guards | runs on CPU-only? | GPU required | injections caught |
|---|---|---|---|---|---|
| 6599 | CUDA GaussianPIC coupled subtraction matches CPU | coupled branch CPU/CUDA parity, `coupling_tol` effectiveness, refusal on unsupported routes | **no — 0 asserts, silent** | yes | not injected |
| 6643 | GaussianPIC coupled (rotated) subtraction | brute-force 2D quadrature reference | yes | no | not injected (U17 rated strong) |
| 6715 | Spectral 6D Dirichlet box contains drifted source | `_spectral_box_drifted` never shrinks and bounds drifted extremes | yes | no | not injected |
| 6747 | Spectral luminosity_schedule reaches its consumer | NaN-on-skip, kicks unchanged, task file omits skipped turns | yes | no | not injected |
| 6826 | Spectral synchro-beam longitudinal map is finite | pz kick present/absent, spectral-vs-PIC pz rms at rtol 0.05 | yes | no | not injected |
| 6889 | Soft-Gaussian synchro-beam longitudinal map | analytic Δpz identity (rtol 2e-13) + FD symplecticity < 1e-8 | yes | no | not injected |
| 6943 | Soft-Gaussian weak-strong map equivalence | slice-kick vs `ThinStrongBeam` for 3 drifts, rtol 2e-14 | yes | no | not injected |
| 6994 | Zero-width soft-Gaussian slice remains finite | degenerate slice | yes | no | not injected |
| 7010 | Physical transverse scale controls | min_sigma / min_transverse_extent / min_domain_halfwidth, scale invariance | yes | no | not injected |
| 7105 | Finite-difference 6D symplecticity validation | validation script, static case tuple | yes | no | not injected (seam: script outside region) |
| 7115 | High-energy weak-strong strong-strong limit | loose smoke (rtol 0.60/0.80) | yes | no | not injected |
| 7158 | CUDA round Gaussian near-axis stability | device kick/Hessian vs host | **no** | yes | see U20-5 |
| 7179 | CUDA near-round Gaussian transition matches CPU | near-round series branch bounds | **no** | yes | see U20-4 |
| 7205 | CUDA strong-strong shifted moments preserve small spreads | shifted-moment accumulation on device | **no** | yes | not injected |
| 7283 | CUDA PIC field_derivative matches CPU | flag parity + reaches consumer | **no** | yes | not injected |
| 7317 | CUDA PIC slice_interpolation matches CPU | `:quadratic` / `:node` on every route + refusals | **no** | yes | not injected |
| 7439 | CUDA solver workspaces exclusive and device-aware | lease exclusivity, device in cache key | **no** | yes | not injected |
| 7468 | CUDA PIC wavefront workspace cache is capacity bounded | capacity arithmetic, aliasing, refusal | **no** | yes | not injected |
| 7509 | CUDA spectral solver matches CPU | 6D + transverse parity, `field_precision=:single`, grid-free refusal | **no** | yes | not injected |
| 7572 | **CUDA spectral deposit tripwire (R9, U9-1)** [NEW] | dropped-charge accounting in 3 deposit kernels + collide-level warning | **no** | yes | **2 of 4** (U20-6) |
| 7629 | **TSC weights bit-identical across backends (U2-3)** [NEW] | CPU/CUDA TSC weight agreement | **no** (but needs no GPU — U20-9) | no, gated anyway | **1 of 3; 0 of 1 for the named defect** (U20-1) |
| 7647 | CUDA GaussianPIC solver matches CPU | 4 route × map combinations | **no** | yes | not injected (U20-13 on tolerance) |
| 7688 | CUDA coupled weak-strong parity | 5 virtual drifts + GaussianStrongBeam on device | **no** | yes | not injected |
| 7731 | CUDA coupled soft-Gaussian wavefront parity | fused wavefront path | **no** | yes | not injected |
| 7766 | CUDA zero-width PIC routes remain finite | degenerate slice on 3 routes | **no** | yes | not injected |
| 7812 | CUDA GaussianPIC singular-reference fallback matches PIC | rank-one / zero-width fallback on 3 routes | **no** | yes | not injected |
| 7875 | CUDA non-finite coordinates fail fast | poisoned coordinate chokepoints, 8 configurations | **no** | yes | not injected |
| 7922 | Knob control | evaluation, typing, guards, compile_runtime, derivative, Symbolics adapter, contract | yes | no | not injected (U20-7 on 8067) |
| 8080 | **Knob registry atomicity and round-trip totality** [NEW] | U14-1/2/3/4/7 regressions | yes | no | **2 of 2** recorded defects; see U20-2, U20-8 |
| 8173 | Physics contracts | Symplecticity, HighEnergyWeakStrongLimit (8%), CoherentMode (Yokoya) with executed negative control | yes | no | not injected (runtime; negative control read) |
| 8197 | Strong-strong physical parameter validation | zero-energy beam rejection | yes | no | not injected |
| 8212 | CODATA 2022 constants | four constants, exact `==` | yes | no | not injected (exact literals) |
| 8220 | CUDA GaussianPIC honours green_cache=:slice_pair | grid expansion parity, growth effectiveness | **skipped, visibly** | yes | not injected |
| 8289 | CUDA GaussianPIC emits PIC phase timing records | non-empty timing records, gpic phases | **skipped, visibly** | yes | not injected |
| 8338 | CUDA PIC parity across every execution route | 6 routes, grid + luminosity-dependency bugs | **skipped, visibly** | yes | not injected |
| 8393 | PIC green_type=:lattice | −ln r reproduction, aspect-ratio invariance, consumer reach, EXPERIMENTAL label, (e) CUDA parity | partly (10 of 15) | (e) only | not injected |
| 8480 | The lattice Green box is sized in physical units | `_pic_lattice_box_mult` scaling/cap/symmetry + coarse-axis −ln r | yes | no | **1 of 1** |
| 8524 | Source and field grids keep equal extent [control REWRITTEN] | 48-case sweep of the equal-extent invariant + negative control | yes | no | **1 of 1** |
| 8591 | Green-cache expansion preserves grid alignment | expansion/realignment, in-test negative control, fractional-separation refusal | yes | no | **1 of 1** |
| 8666 | grid_extent is rejected, not ignored | option rejection where no estimator runs | yes | no | not injected |
| 8682 | Dropped PIC charge reaches a reader [EXTENDED] | warning + per-particle counting + source-side drop | yes | no | **4 of 5** (U20-10 is the miss) |

## Injection results, per testset (N caught of M injected)

| testset | N of M | uncaught injections |
|---|---|---|
| TSC weights bit-identical (7629) | **1 of 3** | `w3 = 1 - w1 - w2` (**the recorded U2-3 defect**); out-of-range base 1→0 |
| CUDA spectral deposit tripwire (7572) | **2 of 4** | count particles instead of charge; count only fully-outside |
| Knob registry atomicity (8080) | **2 of 2** | — |
| Dropped PIC charge reaches a reader (8682) | **4 of 5** | `isfinite` guard removed (behaviourally identical — U20-10) |
| Source and field grids keep equal extent (8524) | **1 of 1** | — |
| Green-cache expansion preserves alignment (8591) | **1 of 1** | — |
| Lattice Green box sized in physical units (8480) | **1 of 1** | — |
| **total** | **12 of 17** | |

Injection list, verbatim:
1. `_cuda_pic_tsc_weights`: `w3 = 1 - w1 - w2` → **not caught**
2. `_cuda_pic_tsc_weights`: out-of-range returns base `0` not `1` → **not caught**
3. `_cuda_pic_tsc_weights`: `clamp(base, 0, n-2)` → caught
4. spectral deposit kernels ×3: drop the `dropped[1] +=` line → caught
5. spectral deposit kernels ×3: `dropped[1] += 2*clipped` → caught
6. spectral deposit kernels ×3: `dropped[1] += 1.0` → **not caught**
7. spectral deposit kernels ×3: only count when `written == 0` → **not caught**
8. `_knob_define!`: named-constant guard removed (U14-3) → caught
9. `_knob_define!`: expression guard moved after the retype (U14-1) → caught
10. `_pic_count_outside_box`: count per axis (U5-6) → caught
11. `_pic_count_outside_box`: `isfinite` guards removed → **not caught**
12. `_pic_count_outside_box_drifted`: count per plane (U5-5) → caught
13. `_pic_count_outside_box*`: always return 0 → caught
14. `_pic_count_outside_box`: inflate count 10× → caught
15. `_pic_interaction_grids`: size each grid from its own beam's span → caught
16. `_pic_realign_expanded_grids`: identity (pre-fix behaviour) → caught
17. `_pic_lattice_box_mult`: `(8, 8)` regardless of ρ (index-unit defect) → caught

Probe caveat for reproducers: injection 16 must be defined with the **exact**
signature `(green_type, source_grid, field_grid, nx::Integer, ny::Integer)`; a
less specific method does not take precedence and the injection silently does
nothing (this bit me once — see `inj_grids.jl` vs `inj_grids2.jl`).

## CUDA gate skip-vs-pass verdicts

| gate | on GPU | with `CUDA_VISIBLE_DEVICES=""` | verdict |
|---|---|---|---|
| 8232 `else @test_skip` | Pass 7 | **Broken 1** | correct: reports SKIPPED |
| 8293 `else @test_skip` | Pass 9 | **Broken 1** | correct: reports SKIPPED |
| 8351 `else @test_skip` | Pass 12 | **Broken 1** | correct: reports SKIPPED |
| 6604 no `else` | Pass 14 | Total 0 | **silent** — no skip, no pass |
| 7133 block, no `else` | Pass 358 | Total 0 | **silent** — 16 testsets do not exist |
| 8451 no `else` | Pass 15 (whole set) | Pass 10 | **silent partial shrink** (5 asserts) |

The three `@test true` → `@test_skip` conversions in the diff are confirmed
effective. `@test_skip "CUDA device not available"` is legal (the string is never
evaluated) and lands in the summary's `Broken` column.

## Clean list (audited sound, with the evidence that makes it checkable)

- **The whole CUDA block executes green on real hardware.** `run_cuda_block.jl`
  on the RTX 4500 Ada: `REGION-CUDA-BLOCK | Pass 358 Total 358 3m45.5s`, no
  failures, no errors, no brokens. Log: `scratchpad/audit/cuda_block_gpu.log`.
- **No `@test true` remains in the region.** `awk 'NR>=6600 && NR<=8759 && /@test true/'` → 0.
- **No swallowing `catch`.** All five `try` blocks in the region (6796, 7447,
  7580, 7924, 8085) are `try … finally` cleanup: temp-file removal, workspace
  lease release, `reset_knobs!()`. Each was read; none has a bare `catch`.
- **No env-var gates.** `grep 'ENV\['` over 6600–8759 → 0.
- **No zero-iteration loops.** Every `for` in the region iterates a literal tuple,
  a literal range, or `zip` of 2-/6-element tuples; each was read. The largest is
  the 3×2×2×4 = 48-case sweep at 8549–8552.
- **Testset nesting is balanced.** Verified constructively: each top-level testset
  in the region was extracted by line range and executed standalone; all parsed
  and ran.
- **Knob operator round-trip holds for all 24 whitelist entries** when the case
  list is derived from `_KNOB_OPERATORS` (both arities plus one nested level):
  0 failures (`pA_knob_roundtrip.jl`). The hand-pick at 7992 hides no live bug on
  that axis — the live bug is on the association axis (U20-2).
- **The knob atomicity testset earns its name.** Both recorded U14 defects,
  re-injected verbatim into `_knob_define!`, are caught.
- **The three grid-geometry testsets (8480, 8524, 8591) have real discriminating
  power**, each demonstrated by injecting the recorded pre-fix implementation.
  The rewritten negative control at 8573–8588 replaces U17-8's vacuous
  `sg.width != fg.width * 1.01` with two asserts that the raw spans genuinely
  differ — a real control, confirmed by injection 15.
- **"Dropped PIC charge reaches a reader" now pins a real count**, not just a
  warning: the `l.kwargs[:dropped] isa Integer && > 0` check plus the exact
  `ws.dropped[] == 1` / `nsrc - sum(ws.charge) ≈ 1.0` source-side asserts catch
  4 of 5 injections including a 10× inflated count.
- **`CUDA_TESTS_ACTIVE` semantics verified**: `_HAS_CUDA` is true whenever CUDA.jl
  imports (hard dependency), so `CUDA.functional()` is the only device gate, and
  `CUDA_VISIBLE_DEVICES=""` is a faithful CPU-only simulation
  (`p1_gate.jl` prints `_HAS_CUDA = true, functional() = false`).

## Not checked, and why

- **`@testset "Physics contracts"` (8173)** — not injected. Two 1024-turn
  strong-strong runs (~1 min each) plus two more contracts; the cost did not fit
  the session, and the testset already carries an *executed* negative control
  (`@test !gau.passed` with the ordering `gau.metrics < coh.metrics`), which U17
  verified by reading and I re-read. Its tolerances are quoted but unmeasured
  here: `sym.metrics[:GaussianStrongBeam_residual] <= 5.0e-7`,
  `wsl.metrics[:gaussian_proton_max_abs_error] <= 2.0e-14`,
  `wsl.metrics[:pic_luminosity_relative_error] <= 0.08`,
  `abs(gau.metrics[:sigma_drift_x]) <= 2.0e-4`.
- **`validation/symplecticity_validation.jl` and
  `validation/high_energy_weakstrong_limit.jl`** (included at 7103, 7113) — the
  scripts are outside my region. Measured Lesson 4 records that the symplecticity
  script once carried a hand-copied 8-of-12 case list; I did not re-derive it.
  Seam noted, stopped.
- **The 14 GPU-only testsets I did not inject** (7158–7509, 7647–7875 excluding
  the two new ones) — each takes 10 s–1.5 min per run on device; a full injection
  battery would have been hours. They were read line by line and executed once
  for real (contributing to the 358 passing assertions). U20-4 and U20-5 are the
  tolerance findings that came out of that reading.
- **Full-suite run** — deliberately not performed; the auditor runs it.
- **Line 48's `@info` count** — the message is outside my region; recorded as
  U20-11 and stopped.
