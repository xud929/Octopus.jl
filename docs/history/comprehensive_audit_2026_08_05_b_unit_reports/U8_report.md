# U8 Audit Report — Weak-Strong Beam-Beam Physics Core (Bassetti-Erskine,
# near-round switch, synchro-beam map) + Strong-Strong Soft-Gaussian Kick

Repository: `/cfs/ad/dxu/Library/Julia/Octopus` @ `7de4d81` (read-only audit).
Prior unit report for this region:
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U7_report.md` (@ `13c2733`).
Machine: NVIDIA RTX 4500 Ada Generation, driver 580.119.02, Julia 1.12.4.

---

## 1. Region and provenance

**Read line-by-line, 100% (auditor, this unit):**

| File | Lines | Depth |
|---|---:|---|
| `src/elements/strong_beam.jl` | 1–1578 | every line |
| `src/track/strong_beam_track.jl` | 1–505 | every line |
| `src/tasks/strongstrong/gaussian.jl` | 1–199 | every line |

**Read as required context (not audited):** `AGENTS.md` §Hard-Won Rules;
`docs/comprehensive_audit.md` §Measured Lessons; `docs/theory/near_round_bassetti_erskine_switch.md`
§5–6 and the boxed switch results; `src/math/SpecialMath.jl` (full, 168);
`ext/OctopusForwardDiffRules.jl` + `ext/OctopusForwardDiffExt.jl` (full);
`validation/near_round_gaussian_transition.jl` (`_continuity_metrics`, the CUDA
parity leg, the `if abspath(PROGRAM_FILE)` block); `test/runtests.jl:3793-3813`
and `:5005-5032`; `src/tasks/strongstrong/interface.jl:555-585`;
`src/policies/Policies.jl:230-260`; `src/tasks/Tasks.jl:10-20`.

**Diff read in full:** `git diff 6a3f39ab HEAD -- <the three region files>`
(52 insertions, 10 deletions — three docstrings, `_PLACEMENT_PARAMS...` added to
both `@element_spec` blocks with matching `construction_help`, the U7-2 CUDA
per-turn reset in both kernels, and `nchunks = _cpu_worker_count()` →
`_REDUCTION_CHUNKS` in `_slice_slice_gaussian_kick!`).

**Executed (all read-only probes; scripts in session scratch
`.../scratchpad/audit/U8/`, plus `p1_eta_seams.jl`, `p3_dual.jl`, `p4_xy_seams.jl`,
`p5_seams2.jl` written before the directory was namespaced):**

| Probe | What it measures |
|---|---|
| `quadref.jl` | Independent Bassetti-Erskine reference derived from the Coulomb Green's function (see §2) |
| `p1_eta_seams.jl` | Extrapolated value/derivative gaps at the `inner`/`outer` eta seams |
| `p2_quadrature.jl` | Code vs independent quadrature across all branches |
| `p3_dual.jl` | ForwardDiff through every branch and the whole element (U7-1) |
| `p4_xy_seams.jl`, `p5_seams2.jl` | True 1-ulp branch jumps for the `q=2`, `u=1e-2` and `rho^7` switches; which side is accurate; limiting cases |
| `U8/p7_lum.jl` | CPU vs CUDA `last_luminosity` at turns 0..5, coordinate parity, kick-stack parity (U7-2) |
| `U8/p8_cuda_field.jl` | CPU/CUDA field accuracy vs truth; Weideman-32 accuracy; `y==0` symmetry |
| `U8/p9_ss.jl` | Strong-strong worker-count invariance, luminosity vs closed form, 64-chunk cost |
| `U8/p10_final.jl` | Coupled `D==0` seam; `turns==0` backend divergence; AD through all 7 slice rules |
| `U8/p11_placement.jl` | `_PLACEMENT_PARAMS` consumed?; U7-3/U7-4 status at HEAD |
| `U8/p12_coeffs.jl` | `j_mn` near-axis coefficients vs their definition; branch-resolved accuracy |
| `U8/p13_deriv.jl` | Kink-vs-curvature discrimination at the eta seams |
| `validation/near_round_gaussian_transition.jl` | The repository's own harness, run on this GPU box |

**Not executed:** the full test suite (out of scope for a reading unit).

---

## 2. The independent reference

The brief required verification against a high-precision quadrature of the
Gaussian-charge field integral, not against another copy of the Bassetti-Erskine
formula. `quadref.jl` derives one from scratch:

The 2D Coulomb kernel obeys `2u/|u|^2 = ∫_0^∞ dt (u/t^2) exp(-|u|^2/(2t))`.
Convolving with a Gaussian of covariance `Σ = diag(σx², σy²)`, using
`exp(-|u|²/2t) = 2πt·G_{tI}(u)`, `(x-x')G_{tI}(x-x') = -t ∇_x G_{tI}(x-x')`
and `G_Σ * G_{tI} = G_{Σ+tI}`, gives `K(x) = -2π ∫_0^∞ dt ∇G_{Σ+tI}(x)`, i.e.

```
Kx = x ∫_0^∞ dt E(t) / [(σx²+t)^{3/2}(σy²+t)^{1/2}],   E = exp(-x²/(2(σx²+t)) - y²/(2(σy²+t)))
Ky = y ∫_0^∞ dt E(t) / [(σx²+t)^{1/2}(σy²+t)^{3/2}]
```

mapped to `u = σ2²/(σ2²+t) ∈ (0,1]` and integrated with composite 32-node
Gauss–Legendre in 200–300-bit `BigFloat`. `H1 = -kbb ∂Kx/∂x` and
`H2 = -kbb ∂Ky/∂y` are obtained by differentiating under the integral sign, and
`L/D = (Kx·y - Ky·x)/(σ1²-σ2²)` is reduced analytically to the
cancellation-free `-(x y/σ2)∫_0^1 du E u/(σ2²+uΔ)^{3/2}`, which stays finite as
`Δ → 0` and therefore also supplies the exact `σ1 → σ2` limit.

**Reference self-checks (executed):**

- Round-beam closed form `2x(1-e^{-r²/2σ²})/r²` reproduced to **≤5.8e-16**
  relative at 0.4σ, 2σ and 6σ.
- Exact Poisson/divergence identity `∂ₓKx + ∂_yKy = 2·exp(...)/(σxσy)`
  satisfied to **2.7e-16** relative at (2e-3, 0.7e-3) sizes and three field
  points.
- Panel refinement 400 → 1600 → 6400: the code-vs-reference gap at the hardest
  point (η=0.999, (6,5)σ) falls 3.9e-12 → 1.8e-14 → 2.1e-15, i.e. the residual
  was the *reference's* resolution, not the code's.
- **Known limit:** uniform panels under-resolve the `u→0` boundary layer once
  `σ2/σ1 ≲ 1e-4`. Extreme flat-beam values are therefore **not** independently
  verified (§7).

---

## 3. Branch inventory (corrected) and boundary continuity

The brief anticipated four branches. The code actually carries **four η-branches
plus six further switches**, all of which were sampled:

| # | Switch | Location (CPU / CUDA twin) |
|---|---|---|
| S1 | `eta == 0` → exact round | `strong_beam.jl:1033,1056` / `strong_beam_track.jl:422,445` |
| S2 | `0 < eta <= inner` → near-round series | `:1039,1065` / `:428,454` |
| S3 | `inner < eta < outer` → quintic blend | `:1046,1084` / `:435,473` |
| S4 | `eta >= outer` → elliptic Faddeeva | `:1043,1080` / `:432,469` |
| S5 | `rho^7 <= eps(T)/sqrt(eta)` → near-axis 5th-degree polynomial (inside S3/S4) | `_use_elliptic_near_axis`, `:955-962` (shared) |
| S6 | `q <= T(2)` → Taylor vs upward recurrence | `_near_round_moments_0_6/_3_11`, `:793,817,829,854` (shared) |
| S7 | `u < 1e-2` → φ,φ′ series vs closed form | `_round_gaussian_hessian`, `:719` (shared) |
| S8 | `D = hypot(a-d, 2b) == 0` → lab-frame round Hessian vs principal frame + rotation term | `_cp_covariance_kick{true}`, `:641` / `:350` |
| S9 | `sigx >= sigy` wrapper ordering | `:1098,1119` / `:487,499` |
| S10 | `sigx == 0 \|\| sigy == 0`, and `a<=0 \|\| d<=0 \|\| detA<=0` | `:1118,622,638` / `:498,332,347` |

Float64 bounds: `inner = 2.2060595791255979e-4`, `outer = 4.4121191582511957e-4`.
Float32: `inner = 0.019966973`, `outer = 0.039933946`.

### S1 — `eta == 0` vs `eta → 0⁺`

`Kx, Ky, H1, H2` agree with the exact-round closed form to **≤4.6e-16** relative
(and with the independent quadrature to 4.3e-16 / 3.4e-16 / 4.6e-16 / 4.2e-16).
`L/D` jumps by **100%** — see **LEAD U8-1**.

### S2 — inner seam, `eta = 2.2060595791255979e-4`

One-sided linear extrapolation to the seam from each side, worst over 9 field
points from 0.05σ to (8,6)σ:

| | rel gap | abs gap | worst point |
|---|---:|---:|---|
| Kx | 6.544e-16 | 5.33e-15 | (0.05, 3.50)σ |
| Ky | 6.910e-16 | 3.41e-13 | (1.00, 0.70)σ |
| H1 | 1.102e-15 | 1.75e-10 | (3.50, 0.05)σ |
| H2 | 1.189e-15 | 1.27e-11 | (5.00, 4.00)σ |
| L/D | 6.115e-16 | 2.91e-11 | (5.00, 4.00)σ |

Repository harness on the same box (`validation/near_round_gaussian_transition.jl`,
independent grid): `force_value_gap = 1.77e-15`, `response_value_gap = 9.45e-13`,
`force_derivative_gap = 1.99e-13`, `response_derivative_gap = 1.30e-11`.

**Derivative.** By construction the blend weight is the quintic smoothstep
`w(t) = t³(10 - 15t + 6t²)`, with `w = w′ = w″ = 0` at `inner` and
`w = 1, w′ = w″ = 0` at `outer` (`_near_round_blend`, `:778-790`), so the map is
C² in η at both seams and the `dw` chain term in H1/H2 vanishes at both ends.
Measured discrimination (`U8/p13_deriv.jl`): the one-sided `d/dη` mismatch
**halves every time h halves** — at (0.3,0.2)σ, `h = η·2^-8…2^-11` gives
Kx 5.0e-6 → 2.5e-6 → 1.2e-6 → 6.4e-7 (same for Ky, H1, H2; L/D 2.9e-4 → 1.5e-4
→ 7.3e-5 → 3.7e-5). That is curvature, not a kink: **no derivative
discontinuity at the inner seam.**

### S3/S4 — outer seam, `eta = 4.4121191582511957e-4`

| | rel gap | abs gap | worst point |
|---|---:|---:|---|
| Kx | 7.379e-15 | 3.47e-12 | (0.50, 0.00)σ |
| Ky | 2.216e-14 | 4.29e-12 | (0.30, 0.20)σ |
| H1 | 9.062e-11 | 5.07e-07 | (8.00, 6.00)σ |
| H2 | 9.062e-11 | 5.07e-07 | (8.00, 6.00)σ |
| L/D | 4.088e-11 | 1.17e-06 | (0.30, 0.20)σ |

Repository harness: `force_value_gap = 9.47e-13`, `response_value_gap = 6.74e-9`
(relative) / `1.66e-13`, `4.68e-11` (natural scale).

**Mechanism of the H gap.** `_elliptic_gaussian_hessian_diagonal` (`:695-703`)
divides by `temp2 = σx² - σy² = 2·v·η`, and the numerator
`temp1 - 2·kbb·(1 - expterm·temp3)` is a difference of two O(kbb) quantities.
The absolute error floor is `≈ 2·eps·kbb/(v·η)`, i.e. a natural-scale relative
error `C_BE·eps/η`. This is exactly the quantity the outer bound was calibrated
to balance. The repository's own harness measures
`observed outer conditioning factor = 61.94` against the nominal `64.0` —
**the calibration is confirmed, not merely asserted.**

**Derivative.** Same halving test: at (0.3,0.2)σ, Kx/Ky/H mismatch
1.0e-5 → 5.0e-6 → 2.5e-6 → 1.2e-6 (curvature). At the far tail (8,6)σ the H1/H2
mismatch *grows* as h shrinks (2.2e-4 → 4.1e-4 → 1.2e-3 → 1.7e-3), the
`noise/h` signature of the cancellation above — floating-point noise, again not
a kink. **No derivative discontinuity at the outer seam.**

### S5 — near-axis switch `rho^7 = eps(T)/sqrt(eta)`

This is a *hard* switch with no blend, so it is the only place a genuine value
step survives. Both branches evaluated at the *same* seam point (so the number
below is the branch jump, not smooth variation), plus each branch's own error
against the independent quadrature:

| η | ρ_seam | jump Kx | jump Ky | err(near-axis) | err(Faddeeva) |
|---:|---:|---:|---:|---:|---:|
| 1e-3 | 9.507e-3 | 4.863e-13 | 5.338e-12 | 3.34e-15 | 4.83e-13 (Kx) / 5.34e-12 (Ky) |
| 1e-2 | 8.066e-3 | 1.191e-13 | 1.347e-12 | 9.85e-16 | 1.20e-13 / 1.35e-12 |
| 0.1 | 6.842e-3 | 3.174e-14 | 9.891e-13 | 1.45e-16 | 3.16e-14 / 9.89e-13 |
| 0.5 | 6.099e-3 | 1.400e-14 | 5.374e-13 | 0.00e+00 | 1.40e-14 / 5.37e-13 |
| 0.9 | 5.849e-3 | 8.920e-15 | 2.230e-13 | 1.44e-16 | 8.63e-15 / 2.23e-13 |

H1/H2 jumps ≤1.18e-13; `L/D` on the Faddeeva side is the worst component at
**6.03e-9** relative (η=1e-3).

**Verdict: the switch selects the accurate branch.** The near-axis polynomial is
right to ≤3.3e-15 everywhere at the seam; the entire jump is the Faddeeva
subtraction's conditioning error, which is precisely what the switch exists to
escape. The step is a real (if tiny) discontinuity in value and therefore in
derivative — reported here as a measured property, not a defect, because
smoothing it would require carrying both branches and blending, at a cost the
theory note's error balance does not justify.

### S6 — `q == 2` moment switch (TRUE jump, `2.0` vs `nextfloat(2.0)`)

| | m0 | m3 | m6 | m8 | m9 | m10 | m11 |
|---|---:|---:|---:|---:|---:|---:|---:|
| jump | 3.9e-16 | 1.4e-15 | 4.1e-14 | 7.6e-13 | 3.9e-12 | 2.2e-11 | 1.33e-10 |
| err(Taylor) | 1.3e-16 | 9.1e-16 | 1.5e-15 | 7.4e-16 | 1.1e-15 | 9.4e-16 | 1.4e-15 |
| err(recurrence) | 5.1e-16 | 5.2e-16 | 3.9e-14 | 7.6e-13 | 3.9e-12 | 2.2e-11 | 1.33e-10 |

This is the one switch in the region where the code moves onto the *less*
accurate branch. The upward recurrence `m_k = (k·m_{k-1} - e^{-q})/q` cancels
catastrophically just above `q = 2` (`k·m_{k-1} → e^{-q}` for large k), losing
about one digit every two steps. It recovers immediately: m11 relative error is
1.33e-10 at `q = 2⁺`, 1.80e-13 at `q = 3`, 3.16e-15 at `q = 5`, 1.9e-15 at
`q = 20, 50`.

**Consequence (bounded, harmless):** m7…m11 appear only in
`_near_round_potential_residual` (`:932-953`), the η⁴–η⁶ blend-chain residual,
whose own magnitude at the blend is ≲ η⁴ ≈ 3.8e-14 relative — so a 1.3e-10
relative error there lands around 5e-24 in the pz kick. m0…m6 (the live field
series) jump by ≤4.1e-14, and m6 enters at order η³ ≈ 1e-11. Recorded as a
measured property, below the threshold I would call a lead.

### S7 — `u == 1e-2` round-Hessian switch (TRUE jump, r² straddling by 1 ulp)

`u(below) = 0.0099999999999999985`, `u(above) = 0.010000000000000000`:

| | Hxx | Hxy | Hyy |
|---|---:|---:|---:|
| jump | 2.83e-15 | 1.15e-12 | 2.93e-15 |
| err(series) | 1.18e-16 | 2.11e-16 | 1.17e-16 |
| err(closed form) | 2.95e-15 | 1.15e-12 | 2.82e-15 |

Again the switch picks the accurate branch: the `2(e·u - (1-e))/r⁴` closed form
cancels at small u and the series does not. `Hxy` is used only by the coupled
`D == 0` branch (`2·Hxy·bu`).

### S8 — coupled `D == 0` seam (the branch the prior pass flagged as delicate)

`_cp_covariance_kick{Coupled=true}` splits at `D = hypot(a-d, 2b) == 0`. The
`D > 0` branch reconstructs the lab-frame contraction as
`0.125((H11+H22)·traceu + (H11-H22)·Du) - 0.5·kbb·rotation_projection·L/D`;
the `D == 0` branch instead evaluates the round lab-frame Hessian directly as
`0.25(Hxx·au + 2·Hxy·bu + Hyy·du)`. Both are complete — the `2·Hxy·bu` cross
term is the lab-frame image of the rotation term, whose limit is **not** zero.

Measured pz kick, approaching `D = 0` along four fixed directions
`(a-d, 2b) = D(cos φ, sin φ/2)`, with `au, bu, du = (3.1e-4, -1.7e-4, 2.3e-4)`,
`S = 3e-3`, field point (2e-4, -1.3e-4), `D==0` branch value
`pz = -1.30015773924573586e-02`:

| D/(a+d) | φ=0 | φ=π/4 | φ=π/3 | φ=1.1 |
|---:|---:|---:|---:|---:|
| 1e-3 | 6.05e-5 | 1.57e-4 | 2.15e-4 | 2.25e-4 |
| 1e-5 | 6.10e-7 | 1.57e-6 | 2.14e-6 | 2.24e-6 |
| 1e-7 | 6.10e-9 | 1.57e-8 | 2.14e-8 | 2.24e-8 |
| 1e-9 | 6.10e-11 | 1.57e-10 | 2.14e-10 | 2.24e-10 |
| 1e-11 | 6.10e-13 | 1.57e-12 | 2.14e-12 | 2.24e-12 |
| 1e-13 | 6.00e-15 | 1.59e-14 | 2.14e-14 | 2.26e-14 |

Exactly linear in D over ten decades, **no plateau**, for every direction. The
`D == 0` branch is the exact `D → 0` limit of the general branch. Clean.

### S9 — `sigx >= sigy` wrapper

At `sigx == sigy` exactly and at `sigx = sigy(1+1e-16)` both orderings return
**bit-identical** `(Kx, Ky)`; at 1e-15 and 1e-13 relative offsets they differ by
1.17e-15 and 1.01e-13 — pure rounding of the swapped arithmetic.

### S10 — vanishing size

`gaussian_beambeam_kick(σx, 0, x, y) → (0, 0)` (documented in the docstring
added by the audited diff). The true `σy → 0` limit is a line charge, not zero
field, so this is a deliberate physics discontinuity used as a guard; the code
tracks the true limit smoothly right up to it (σy = 1e-5 agrees with the
independent reference to 1.2e-15, and the values are stable from σy = 1e-7 down
to 1e-300 at 176.262 / 2307.84). Documented, guarded, and it is what keeps a
zero-emittance slice from producing `Inf`. Not a lead.

---

## 4. Leads

### LEAD U8-1 [Low, confidence high] src/elements/strong_beam.jl:1056-1061
Claim: on the exact-round branch (`eta == 0`) the response evaluator returns
`L_over_D = zero(T)`, but the true limit of `(Kx·y − Ky·x)/(σ1²−σ2²)` as
`σ1 → σ2` is finite and nonzero — a 100% error in the fifth return value while
the other four are correct to 4.6e-16.
Mechanism: `L/D` is cancellation-free in its integral form,
`L/D = −(x·y/σ)·∫₀¹ e^{−qu}·u·du/σ³ = −x·y·m₁(q)/v²`, which is exactly what
`_near_round_series_response` (`:923-925`) returns for `eta → 0⁺`. The
`eta == zero(eta)` short-circuit at `:1056` returns before reaching it and hands
back a hard zero instead of the limit. The CUDA twin
(`src/track/strong_beam_track.jl:445-450`) carries the same zero.
Currently **latent, not live**: the only consumer of `L/D` is the coupled
`_cp_covariance_kick` rotation term `pz -= 0.5·kbb·rotation_projection·L_over_D`
(`:681`), reached only when `eta = D/(a+d) > inner ≈ 2.206e-4`; the recomputed
inner `eta` differs from that by ≈2e-12 relative, so the `eta == 0` path is
unreachable from there, and the uncoupled wrapper
`_gaussian_beambeam_kick_response` (`:1097-1106`) discards the value. It is a
trap for any future caller or a lowered threshold.
Repro: `julia --startup-file=no --project=. -e 'using Octopus; v=(1e-3)^2; s=sqrt(v); println(Octopus._gaussian_beambeam_kick_response_principal(1.0,s,s,0.3*s,0.2*s)[5])'`
prints `0.0`; the true limit is `-2.87311456056616989e+04` (independent
quadrature, `scratchpad/audit/U8/quadref.jl`); the series branch at
`eta = 1e-12` already returns that value.

### LEAD U8-2 [Low, confidence high] src/track/strong_beam_track.jl:216-239, 252-285
Claim: with `turns == 0`, CUDA `track!` **overwrites** `elem.last_luminosity`
with `0.0` while CPU `track!` **retains** the previous value — the residual edge
left by the U7-2 fix.
Mechanism: the CPU loops `for _ in 1:turns … elem.last_luminosity = sum(local_lum)`
(`:45-59`, `:76-91`), so at `turns = 0` the field is never assigned. The CUDA
entry points allocate `lum = CUDA.zeros(T, N)`, launch the kernel (whose
`turn_lum` is initialised to zero *before* the turn loop, `:144`/`:180`, so it
stays zero when the loop body never runs), and then **unconditionally** assign
`elem.last_luminosity = _cuda_luminosity_total(lum, rep)` (`:237`, `:283`). The
U7-2 regression test (`test/runtests.jl:5005`) pins only `turns = 3`.
Repro: track one turn on both backends, then call `track!(rep, elem, 0, …)`.
Measured (`scratchpad/audit/U8/p10_final.jl`): CPU `1.5854148099e+05` →
`1.5854148099e+05`; CUDA `1.5854148099e+05` → `0.0000000000e+00`.

### LEAD U8-3 [Low, confidence high] src/elements/strong_beam.jl:719
Claim: `u < oftype(u, 1.0e-2)` in `_round_gaussian_hessian` is the exact
"numeric literal converted through the value type, then compared" pattern the
repository fixed elsewhere with `real(T)`, and it is the one such crossover in
this region that is not already type-guarded.
Mechanism: every neighbouring crossover in this file carries a `where {T<:Real}`
bound (`_near_round_eta_bounds:772`, `_near_round_blend:778`,
`_near_round_moments_0_6:792`, `_near_round_moments_3_11:828`), so a non-ordered
`T` fails at dispatch. `_round_gaussian_hessian` (and `_use_elliptic_near_axis`
at `:961`, whose `eps(T)` is the same class) carries no such bound, so with a
`Complex`-valued `T` the `oftype`/`eps` call succeeds and the `<` then throws a
`MethodError` from inside the kernel. The repository's stated convention is
`abs(u) < real(T)(1e-2)` with a comment explaining exactly this — see
`src/elements/solenoid.jl:97-108` and `src/elements/lattice_magnets.jl:48-51,
58-70, 85-89`. ForwardDiff `Dual`s are unaffected (measured working, §5).
This is convention consistency and failure-layer hygiene, not a wrong answer.
Repro: `grep -n "oftype(u, 1.0e-2)\|eps(T) / sqrt(eta)" src/elements/strong_beam.jl`
against `grep -n "real(T)(1e-" src/elements/solenoid.jl src/elements/lattice_magnets.jl`.

### LEAD U8-4 [Low, confidence high] src/elements/strong_beam.jl:1277-1280 — re-verification of prior lead U7-3, STILL OPEN
Claim: a `slice_center` supplied without a matching `slice_weight` is silently
discarded and replaced by the `slice_method` nodes — user-supplied physics
vanishing without a signal, the class Measured Lesson 8 exists for.
Mechanism: `_gaussian_slices` bypasses the generator only when **both**
`slice_center !== nothing && slice_weight !== nothing`; a lone `slice_center`
falls through to `method == :sqrt_density && return _sqrt_density_slices(...)`
with no warning or error. (The same silence covers user-supplied
`slice_weight`s that do not sum to 1 — no normalisation check exists on that
path either.)
Repro (measured at HEAD, `scratchpad/audit/U8/p11_placement.jl`): compile
`GaussianStrongBeamSpec{Float64}(thin=…, ns=3, sigz=1e-2, slice_center=(-0.02, 0.0, 0.02))`
→ `elem.slice_center == [-0.011735298410123208, 0.0, 0.011735298410123208]`
(the `:sqrt_density` nodes), no warning emitted.

### LEAD U8-5 [Low, confidence high] src/elements/strong_beam.jl:1285 — re-verification of prior lead U7-4, STILL OPEN
Claim: `slice_method = :equal_width` without `slice_width` throws
`MethodError: no method matching Float64(::Nothing)` — the wrong exception class
for a user configuration error, where every other misconfiguration in this
constructor throws `ArgumentError` with guidance.
Mechanism: `_gaussian_slices` calls `_equal_width_slices(T, ns, T(sigz), T(width))`
with `width === nothing`.
Repro (measured at HEAD): compile
`GaussianStrongBeamSpec{Float64}(thin=…, ns=3, sigz=1e-2, slice_method=:equal_width)`.

### LEAD U8-6 [Informational, confidence med] — out-of-hypothesis, cross-file seam
Claim: `validation/near_round_gaussian_transition.jl` computes exactly the two
numbers that would bind the near-round calibration and the CPU/CUDA split — and
asserts neither; its only failure condition is `all(isfinite, …)`.
Mechanism: the script reports `observed_outer_conditioning_factor` (measured
61.94 vs the nominal 64.0 hard-coded at `strong_beam.jl:765`) and
`CUDA parity Float64: max relative error = 1.37e-11 / natural 1.91e-11`, then the
`if abspath(PROGRAM_FILE) == @__FILE__` block errors only on non-finite metrics.
The theory note explicitly lists "CPU versus CUDA evaluation" as an axis on
which `C_BE` varies, yet one constant serves both. My own measurement puts the
CUDA field error at 1.11e-10 vs the CPU's 5.84e-11 against the independent
quadrature (worst over η ∈ [0, 0.99] × 9 field points) — a factor ~2, inside the
design budget, so **nothing is wrong today**; what is missing is the tripwire
that would notice if it stopped being inside. `validation/` is outside my
region: reported as a seam for the auditor, not acted on.
Repro: `julia --startup-file=no --project=. validation/near_round_gaussian_transition.jl`
on a CUDA box; read the last four printed lines.

---

## 5. Verdicts on the two inherited open leads

### U7-1 — "ForwardDiff Dual through any elliptical beam-beam kick throws" → **CLOSED**

The fix landed as `ext/OctopusForwardDiffRules.jl`, included by *both*
`ext/OctopusForwardDiffExt.jl` (package extension) and the script-mode
fallback at `src/Octopus.jl:121`, supplying the two rules generic code cannot
express:

1. `_near_round_conditioning_factor(::Type{Dual{T,V,N}}) = _near_round_conditioning_factor(V)`
   — the precision calibration passes through to the value type, which is right:
   taking a derivative does not change the floating-point grid.
2. `faddeeva_w(::Complex{Dual})` via the holomorphic rule
   `w′(z) = −2·z·w(z) + 2i/√π`, with the complex derivative distributed over the
   real and imaginary partials.

Measured at HEAD (`scratchpad/audit/p3_dual.jl`, `U8/p10_final.jl`), AD vs
central difference:

| what | AD vs FD, relative |
|---|---:|
| `d(Kx)/dx`, σ=(2e-3,1e-3) elliptical | 2.96e-10 |
| `d(Kx)/dx`, σ=(1e-3,2e-3) (swapped ordering) | 2.46e-10 |
| `d(Kx)/dx`, σ=(1e-3,1e-3) round | 3.78e-12 |
| `d(Kx)/dx`, σ=(5e-3,1e-4) flat | 5.83e-10 |
| `d(Kx)/dσx`, elliptical | 2.57e-09 |
| `d(Kx)/dσx`, near-round series (σx = σy(1+1e-6)) | 3.00e-11 |
| `d(px_out)/d(kbb)` through the compiled element | 8.19e-11 |
| `d(px_out)/d(σx)` through the compiled element | 5.70e-10 |
| `d(px_out)/d(σx)` through `GaussianStrongBeam`, ns=5 | 4.22e-11 |
| `d(px_out)/d(σz)`, all 7 `slice_method`s | 1.31e-09 … 2.52e-07 |

Full 6×6 element Jacobian vs central differences: `max|AD−FD| = 7.0e-6` on a
scale of 66 (≈1e-7 relative, the FD floor) for round, elliptical, blend and
series parameter choices — none throws. Regression-pinned at
`test/runtests.jl:3793` by the symplecticity of the dual-computed Jacobian
(`< 1e-10`), which is a stronger pin than any single entry.

`eps(::Type{Dual})` resolves to the value type's, so `_use_elliptic_near_axis`
and `_near_round_eta_bounds` produce Duals with zero partials — the thresholds
are correctly treated as parameter-independent constants.

### U7-2 — "CPU and CUDA disagree on `last_luminosity` for turns > 1" → **CLOSED for turns ≥ 1; one residual edge at turns = 0 (LEAD U8-2)**

The audited diff added a per-turn `turn_lum = zero(x)` reset inside the
in-kernel turn loop of both CUDA kernels, with the comment recording the
measured 3.0× at turns = 3. Executed on the RTX 4500 Ada
(`scratchpad/audit/U8/p7_lum.jl`), 4 particles, `klum = 1`:

| turns | thin CPU | thin CUDA | rel | gaussian(ns=5) CPU | gaussian CUDA | rel |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0.0 | 0.0 | 0 | 0.0 | 0.0 | 0 |
| 1 | 3.12318151290440699e5 | identical | **0.0** | 3.09889754841596237e5 | identical | **0.0** |
| 2 | 3.12318151290440699e5 | identical | **0.0** | 3.10207474430022528e5 | …645 | 3.75e-16 |
| 3 | 3.12318151290440699e5 | identical | **0.0** | 3.10673027633867285e5 | …401 | 3.75e-16 |
| 5 | 3.12318151290440699e5 | identical | **0.0** | 3.11337822831629950e5 | …008 | 1.87e-16 |

The semantics are now *final turn on both backends*, and the sliced element
shows genuine per-turn variation the old sum erased — the CPU per-turn sequence
is `[3.09890e5, 3.10207e5, 3.10673e5, 3.11087e5, 3.11338e5]`, and
`track!(…, 5)` equals the **5th** entry, not the sum. Coordinate parity over
5 turns: `max|CPU−CUDA| = 7.93e-15` (thin) and `5.99e-15` (gaussian), i.e.
8.8e-14 / 7.6e-14 relative. Regression-pinned at `test/runtests.jl:5005` for
both kinds at turns = 3.

**Not refuted, but not fully closed:** the `turns = 0` case still diverges
(LEAD U8-2).

---

## 6. Luminosity accumulation across the four paths (deliverable c)

| path | semantics | evidence |
|---|---|---|
| weak-strong CPU, `_track_thin_strong_beam!` / `_track_gaussian_strong_beam!` | `elem.last_luminosity` **overwritten** each turn ⇒ final turn's beam-sum | `strong_beam_track.jl:58, 90`; measured sequence above |
| weak-strong CUDA | same, since the audited fix | measured, rel ≤3.8e-16 |
| strong-strong `collide!` | **returns** a per-collision value; stores no per-turn state; sums over slice pairs, each pair scaled by `w_i·klum` | `gaussian.jl:14-21`; measured `[1.58639e27, 1.58639e27, 1.58639e27, 1.58640e27]` over 4 successive calls |
| slice weight application | applied **exactly once** — kick via `kbb·w`, luminosity via `l·w` — identically on CPU (`strong_beam_track.jl:104, 112`) and CUDA (`:191, 196`) | read + measured parity |

Strong-strong luminosity cross-checked against the closed-form Gaussian overlap
`np1·np2 / (2π√((σx1²+σx2²)(σy1²+σy2²)))` at N = 2e5/beam, σ1 = (1.0, 0.5) mm,
σ2 = (1.2, 0.4) mm: **ratio 0.999980**.

The two conventions differ in *shape* (stored-final-turn vs returned-per-collision)
but are not in contradiction; the place they meet is
`luminosity(elem, ctx, rep) = elem.last_luminosity` (`src/tasks/Tasks.jl:19`),
outside my region — noted as a seam, not a lead.

---

## 7. Clean list (what was compared, and what was measured)

1. **Independent quadrature anchor, branch-resolved.** Code vs the
   first-principles reference of §2, worst relative error over 9 field points
   (1e-4σ … (6,5)σ), normalised by the physical field scale
   `max(|Kx|,|Ky|)` / `max(|H1|,|H2|)`, stable under 800 → 3200 panel refinement:

   | branch | Kx | Ky | H1 | H2 | L/D |
   |---|---:|---:|---:|---:|---:|
   | exact round (η=0) | 4.3e-16 | 3.4e-16 | 4.6e-16 | 4.2e-16 | *see U8-1* |
   | series (0<η≤inner) | 1.3e-15 | 9.7e-16 | 4.0e-12 | 4.0e-12 | 4.4e-12 |
   | blend (inner<η<outer) | 4.6e-13 | 1.1e-13 | 6.6e-11 | 8.9e-11 | 6.2e-10 |
   | elliptic (η≥outer … 0.95) | 1.6e-13 | 1.4e-13 | 9.7e-11 | 7.4e-11 | 2.6e-10 |

   The H/L-D figures in the last two rows are the `C_BE·eps/η` conditioning
   floor, confirmed independently by the repository harness's
   `observed outer conditioning factor = 61.94` vs nominal `64.0`.

2. **Poisson identity as a Hessian-pair tripwire.** `H1 + H2 = −2·kbb·expterm/(σ1σ2)`
   holds analytically for `_elliptic_gaussian_hessian_diagonal` (verified by
   hand from `:695-703`) and numerically to **≤1.7e-15** of `max(|H1|,|H2|)` in
   the round and series branches, degrading to **2.33e-11** at η = outer,
   (6,5)σ — the same floor as above, not an independent defect.

3. **Near-axis `j_mn` coefficients verified against their definition.** All six
   closed forms in `_elliptic_gaussian_axis_component` (`:976-984`) checked
   against direct numerical integration of
   `J_mn = ∫₀^∞ dt (σx²+t)^{−(m+3/2)}(σy²+t)^{−(n+1/2)}` at four aspect ratios
   (2:1, 1:3, 1:1, 50:1): worst relative error **7.68e-16** (j20 at 1:1). The
   expansion structure `scale = j00 − (x²j10 + y²j01)/2 + x⁴j20/8 + x²y²j11/4 +
   y⁴j02/8` and its x-derivative `j00 − 1.5x²j10 − y²j01/2 + 0.625x⁴j20 +
   0.75x²y²j11 + y⁴j02/8` were re-derived from the exponential expansion of the
   t-integral and match the code term for term.

4. **Every branch boundary sampled densely on both sides** — see §3. No value
   discontinuity above 9.1e-11 relative anywhere, no derivative discontinuity at
   any η seam (kink-vs-curvature discriminated by h-halving), and the coupled
   `D → 0` limit exact to 6.0e-15 after ten decades of linear convergence.

5. **CPU/CUDA field-stack parity.** `_gaussian_beambeam_kick_response` vs
   `_cuda_gaussian_beambeam_kick_response` over η ∈ {0, 1e-8, 1e-5, 1e-4, inner,
   3e-4, outer, 5e-4, 1e-3, 1e-2, 0.1, 0.5, 0.9, 0.99} × 9 field points: both
   agree with the independent quadrature to 5.84e-11 (CPU) and 1.11e-10 (CUDA)
   of the field scale. Full-element parity over 5 turns: 8.8e-14 relative.
   *One asymmetry worth recording:* `x == 0` gives `Kx == 0.0` exactly on both
   backends, but `y == 0` gives `Ky` up to **6.2e-13** (CPU) and **2.8e-10**
   (CUDA) instead of the exact 0 — the Weideman-32 rational approximation
   (absolute error ≈1e-14 in `w`, measured worst relative 3.09e-13 at z=(5,0))
   does not preserve the `w1r − B·w2r` cancellation that is exact on the real
   axis, and the prefactor `A = 2√π/√(2(σ1²−σ2²))` amplifies it by ~5.6e3.
   Relative to `|Kx| ≈ 5e2`, that is 2e-13 — inside budget, but it means the
   mid-plane is not an exact invariant on the GPU.

6. **`_PLACEMENT_PARAMS` (added by the audited diff) is declared *and*
   consumed.** Schema `missing = Symbol[]` for both `:thin_strong_beam` and
   `:gaussian_strong_beam`; measured coordinate change for every one of the
   seven placement parameters: thin `x_offset` 3.33e-3, `y_offset` 6.65e-3,
   `z_offset` 2.33e-6, `x_pitch` 4.98e-6, `y_pitch` 9.96e-6, `tilt` 1.23e-3,
   `ref_tilt` 1.23e-3; gaussian `x_offset` 3.63e-3, `tilt`/`ref_tilt` 1.58e-3,
   `y_pitch` 6.32e-6. Not inert. Unknown parameters still warn loudly.

7. **`_REDUCTION_CHUNKS` change (added by the audited diff) is correct and
   complete.** `collide!` is **bitwise identical** — luminosity *and* all twelve
   coordinate arrays — at 1, 2, 4 and 8 workers, both below (n = 2000) and above
   (n = 20000) the `_STRONG_STRONG_PARALLEL_KICK_MIN = 4096` threshold. Cost of
   the now-unconditional 64-chunk grid at one worker:
   `_run_logical_workers(64)` is 172 µs/call at 1 worker vs 100 µs at 8; for
   ns = 9, n = 1e5/beam that is ≈3.4% of `collide!` wall time (3 collisions:
   0.5169 s at 1 worker, 0.4361 s at 8). No material regression.

8. **Limiting cases.** `kbb = 0` → exact identity map (`out == in`, `===`);
   `kbb < 0` → px kick exactly sign-flipped bitwise
   (`−3.66158812696902982e−03` vs `+3.66158812696902982e−03`); on-axis particle
   → exactly `(0.0, 0.0)` kick; zero covariance → identity map and `lum = 0.0`
   (the `a0 == 0 || d0 == 0` guard at `:470` / `:303`); 1000σ particle finite;
   50σ round asymptote **exactly** `2x/r² = 40.0`; 50σ elliptical 20.006 against
   `20 + ` the quadrupole correction `20·(σx²−σy²)/r² = 6e−3`; exact
   antisymmetry `K(−x,−y) + K(x,y) == (0.0, 0.0)`; `σx == σy` exactly reproduces
   the round closed form.

9. **AD through the slicing rules.** `d(px_out)/d(σz)` succeeds for **all seven**
   `SLICE_METHODS` (`:equal_area`, `:equal_width`, `:equal_area_centroid`,
   `:sqrt_density`, `:gauss_hermite`, `:equal_spacing_density`, `:min_cdf_area`),
   AD vs FD 1.31e-9 … 2.52e-7 (`:equal_width` worst, its `erf`-difference weights
   being the noisiest under central differences).

10. **`_equal_width_slices` weights re-derived.** Central bin
    `erf(nw/2)/erf(ns·nw/2)`, side bin `i` `(erf((i+½)nw) − erf((i−½)nw))/2/sumw`;
    the telescoping sum is `erf((w+½)nw)/erf(ns·nw/2) = 1` for odd `ns` and the
    even branch likewise — correct as written (`:1461-1491`).

11. **Float32 path exercised.** Bounds `inner = 0.019966973`,
    `outer = 0.039933946`. The inner seam shows **no** measurable jump at the
    tightest resolvable bracket; the outer seam gives ≤1.24e-6 (Kx/Ky/H) and
    3.93e-5 (L/D), consistent with the Float32 design bound
    `(3/8)·outer³ = 2.4e-5` and with the repository harness's own
    `outer response_value_gap = 2.29e-5` natural scale.

12. **Minor observations carried forward from U7, re-verified still present and
    still harmless.** `track_particle(::WeakStrongBeamBeamMap, ::GaussianStrongBeam, …)`
    (`:445-462`) still accumulates a `lum` it never returns — coordinates
    verified bit-identical to the live twin
    `_track_gaussian_strong_beam_with_luminosity`, so it is a divergence hazard
    for future edits, not a defect. `_apply_slice_kick_one!` still accepts an
    unread `min_sigma`. `ThinStrongBeam.pzo`/`ppzo` are still threaded and
    unused by any kick. `_crab_offsets` (`:1493-1503`) sums over
    `pairs(harmonics)` of a `Dict`, so the floating-point sum order is fixed only
    by Julia's `Dict` iteration order — deterministic within a version, a
    cross-version bitwise-reproducibility hazard with more than one harmonic.

---

## 8. Not checked, and why

- **Full test suite.** Not run — out of scope for a reading unit. The region's
  own testsets were read (`test/runtests.jl:492-600`, `:3793-3813`,
  `:5005-5032`, `:5128`, `:7181`) but only the two U7 regression testsets were
  reproduced independently.
- **Extreme flat beams (σ2/σ1 ≲ 1e-4).** My independent reference uses uniform
  panels and under-resolves the `u → 0` boundary layer there, so
  `gaussian_beambeam_kick(1e-3, ≤1e-7, …)` is **not** independently verified.
  What I can say is that the code's own values are stable and smooth across
  σy = 1e-7 … 1e-300 (176.26211982 / 2307.8415957) and agree with the reference
  to 1.2e-15 at σy = 1e-5, the smallest size the reference resolves.
- **`_near_round_potential_residual` u4/u5/u6 coefficients** were not re-derived
  term by term (the U7 pass did that). They were verified only through their
  effect on the blended H1/H2, bounded at 8.9e-11 against the independent
  quadrature.
- **Symbolics / truncated-power-series number types** through this region: not
  exercised. `OctopusSymbolicsExt` is the knob-tree adapter, not a tracking
  path, and I found no wired TPSA type; the `T<:Number` struct bounds
  (`:199`, `:353`) are therefore aspirational beyond `Dual` today — which is
  what LEAD U8-3 is about.
- **`validation/near_round_gaussian_transition.jl` itself** was run and read but
  not audited; it is outside my region. LEAD U8-6 flags what it measures without
  binding, for the auditor to route.
- **Multi-turn CUDA luminosity under `allow_lost_particles`.** The default is
  `false` on this box and I did not enable it; the two accumulators
  (`_add_luminosity` on CPU, `_cuda_luminosity_total` after the kernel) are
  documented to judge liveness on post-map coordinates and were verified by
  reading only.
