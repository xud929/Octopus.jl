# U7 Audit Report — Weak-Strong Beam-Beam Stack + Strong-Strong Soft-Gaussian

Repository: /cfs/ad/dxu/Library/Julia/Octopus @ 13c2733 (read-only audit)

## Coverage

Read line-by-line, 100%:

- `src/elements/strong_beam.jl` lines 1–1547
- `src/track/strong_beam_track.jl` lines 1–495
- `src/tasks/strongstrong/gaussian.jl` lines 1–195

Theory notes read and mapped to code:

- `docs/theory/weak_strong_6d_model.md` (full, 254)
- `docs/theory/beam_beam_longitudinal_kick.md` (full, 1524)
- `docs/theory/near_round_bassetti_erskine_switch.md` (full, 1150)
- `docs/theory/gaussian_longitudinal_slicing.md` (full, 890)

Targeted supporting context (not full audits): `src/tasks/strongstrong/slicing.jl`
(kbb/klum scales :77–102, collision order :500–522, `_slice_transverse_moments`
:599–621, `_threaded_histogram` :242–280), `src/tasks/strongstrong/interface.jl`
(:700–870 GaussianPoissonSolver), `src/contracts/Contracts.jl` (:45–120),
`src/beam/Beam.jl` (:29–470), `src/tasks/Tasks.jl` (:10–30),
`src/tasks/BeamObservers.jl` (:660–690), `src/math/SpecialMath.jl` (spot).

Probes (all runnable from repo root with
`julia --startup-file=no --project=. <script>`; p1 needs the stacked
ForwardDiff env): `scratchpad/U7/p0_smoke.jl`, `p1_dual.jl`, `p2_symplectic.jl`,
`p2b_symplectic_h.jl`, `p3_seams.jl`, `p3b_near_axis_seam.jl`, `p4_slices.jl`,
`p5_ws_lum.jl`, `p6_ss_lum.jl`, `p7_quadrature.jl`.

## Leads

### U7-1 — ForwardDiff Dual through any *elliptical* beam-beam kick throws; contradicts the struct's own AD design comment

- Files: `src/elements/strong_beam.jl:746-757` (`_near_round_conditioning_factor`
  generic `T<:Real` method throws ArgumentError; `_near_round_eta_bounds`
  derives `T` from `eta`'s own type), plus `src/math/SpecialMath.jl` `_erfcx`
  (no `Complex{Dual}` method).
- Invariant violated: the struct bounds were widened to `T<:Number` explicitly
  so "a dual number is `<:Real` … the tighter bound refuses a parameter
  derivative outright" (strong_beam.jl:188-191, 331-333). But `eta` inherits the
  particle/parameter number type (S = (z−zo)/2 feeds the transported moments),
  so any Dual tracked or differentiated through a beam with η ≠ 0 anywhere
  reaches `_near_round_conditioning_factor(::Type{Dual})` → ArgumentError.
  The theory note (near_round_bassetti_erskine_switch.md:1016-1019) only claims
  this guard for "other `AbstractFloat` types" (unvalidated float precisions),
  not for AD wrappers of validated ones.
- Measured (p1_dual.jl): round beam σx=σy: `ForwardDiff.jacobian` succeeds
  (J[2,1] = 0.9826855872098359). Elliptical σ=(2e-3,1e-3): throws
  `ArgumentError: near-round Gaussian evaluation supports only Float32 and
  Float64; got ForwardDiff.Dual{…}`. Second blocker even if the factor were
  extended: `gaussian_beambeam_kick(2e-3,1e-3,Dual(1e-4,1.0),1e-4)` →
  `MethodError: no method matching _erfcx(::Complex{Dual{…}})`.
- Severity: medium (AD through the beam-beam element is an advertised design
  property; elliptical is the generic case). Repro: `scratchpad/U7/p1_dual.jl`.

### U7-2 — CPU and CUDA disagree on `last_luminosity` semantics for turns > 1

- Files: `src/track/strong_beam_track.jl:44-61` and `:75-93` (CPU: per-turn loop
  overwrites, so `elem.last_luminosity` = **final turn only**);
  `:144-154`, `:173-191` (CUDA kernels: `total_lum += l` inside
  `for turn in 1:turns`, so `lum[index]` = **sum over all turns**), consumed at
  `:228` and `:274` (`elem.last_luminosity = _cuda_luminosity_total(lum, rep)`).
- Invariant violated: backend consistency of the element's observable state.
  For `track!(rep, elem, N>1, CUDA…)` the stored value is ≈N× the CPU value
  (exactly N× for a static distribution). `ElementTrackingBackendConsistencyContract`
  compares only the six coordinates (src/contracts/Contracts.jl:45-74), so this
  is untested.
- Measured (p5_ws_lum.jl, CPU side): turns=1 → 79577.47154594767; turns=3 →
  79577.47154594767 (ratio 1.0). The CUDA kernel code path unambiguously
  accumulates across turns (cannot execute CUDA under audit rules; code-level).
- Severity: low-medium (per-turn observers use turns=1 and are unaffected;
  direct multi-turn `track!` calls diverge silently).
  Repro: `scratchpad/U7/p5_ws_lum.jl` + cited kernel lines.

### U7-3 — `slice_center` without `slice_weight` is silently discarded

- File: `src/elements/strong_beam.jl:1249-1252` (`_gaussian_slices` requires
  **both** to bypass; a lone `slice_center` with `sigz` present falls through to
  the `slice_method` generator with no warning or error).
- Measured (p4_slices.jl): requested `slice_center=(-0.02, 0.0, 0.02)`, ns=3,
  sigz=0.01 → compiled centers `(-0.011735298410123208, 0.0,
  0.011735298410123208)` (the :sqrt_density nodes). User-supplied physics
  silently ignored (defect class 6).
- Severity: low. Repro: `scratchpad/U7/p4_slices.jl` (Trap B).

### U7-4 — `:equal_width` without `slice_width` throws `MethodError`, not a diagnostic error

- File: `src/elements/strong_beam.jl:1257` (`T(width)` with `width===nothing`).
- Measured (p4_slices.jl): `MethodError: no method matching Float64(::Nothing)`
  — wrong exception class for a user configuration error (class 7); every other
  misconfiguration in this constructor throws ArgumentError with guidance.
- Severity: low. Repro: `scratchpad/U7/p4_slices.jl` (Trap A).

### U7-5 — Slicing theory note contradicts the shipped default slice method

- Files: `docs/theory/gaussian_longitudinal_slicing.md:814` (table row
  "`:equal_area` (default)") and `:856-860` ("**The default is still
  `:equal_area`**, because changing it is a behaviour change …") versus
  `src/elements/strong_beam.jl:304, 374, 1537` (default `:sqrt_density`) and the
  docstring `:270-273` ("**Changed from `:equal_area` on 2026-07-31**").
- Invariant violated: doc↔code agreement (class 7). The change the note says is
  an open call has in fact been made.
- Severity: low (documentation). No probe needed; line citations above.

## Minor observations (not leads)

- `ThinStrongBeam.pzo`/`ppzo` (i.e., `angle[3]`, `curvature[3]`) are stored and
  threaded through slicing/CUDA argument lists but never used by any kick — the
  2D transverse-field model has no use for a source mean-pz; harmless.
- `_apply_slice_kick_one!` (gaussian.jl:144-148) accepts `min_sigma` and never
  reads it; the floor is already applied in `_slice_transverse_moments`.
  Vestigial argument kept for the compat entry points.
- `track_particle(::WeakStrongBeamBeamMap, ::GaussianStrongBeam, …)`
  (strong_beam.jl:426-443) duplicates `_track_gaussian_strong_beam_with_luminosity`
  and accumulates a `lum` it never returns; dead accumulator, harmless, but a
  divergence hazard for future edits.

## Checked and found sound

1. **Longitudinal-kick term mapping (weak-strong and strong-strong).** Every
   term of beam_beam_longitudinal_kick.md maps sign-for-sign to
   strong_beam.jl:588-674: centroid term ½F·(p̄0 − C2·S) (:594-596), CP relative
   coordinate x − (xo − pxo·S + ½ppxo·S²) (:589-590), covariance term
   ¼(Uxx·au + 2Uxy·bu + Uyy·du) with au/bu/du = A_u at u=−S (:666-674, :611,
   :630), eigenvalue form 0.125((H1+H2)·tr_u + (H1−H2)·D_u) ≡
   ¼(Û11λ1,u + Û22λ2,u) (:658-660), rotation term −½θu(F̂xŷ−F̂yx̂) evaluated in
   the stable two-factor form rotation_projection·L_over_D (:661-662, doc §8
   of the switch note). Strong-strong specialization (gaussian.jl:157-165)
   matches doc §9 exactly (C2,u = p̄2, per-particle S, same drift conjugation).
2. **All virtual drifts match their boxed doc maps.** Hirata (pz ∓ q/4),
   chromatic (Φ = √(1−q/2P²)−1, x += Spx/P, z += 2SΦ, pz += PΦ; inverse with Ψ)
   and exact-Hamiltonian (self-consistent S = (z−z*)ps/(2ps+H); inverse via
   H_r = q/2P — verified algebraically to be the exact inverse) —
   strong_beam.jl:522-586 vs doc §6, §7.1, §7.2. The unsafe frozen variants
   match their documented deliberate incompleteness (:478-512, doc §7 table).
3. **6D symplecticity of the complete map.** Finite-difference Jacobian with
   nonzero angle, curvature, coupled covariance (b, bu, θu ≠ 0), all three
   drifts, and 5-slice Gaussian with crab+momentum dispersion: residual
   ‖JᵀΩJ−Ω‖∞ scales exactly as h² (2.9e-2 @ h=1e-4 → 2.9e-8 @ h=1e-7), i.e.
   FD-truncation-limited; no plateau → no symplecticity defect above ~1e-9.
   (p2_symplectic.jl, p2b_symplectic_h.jl)
4. **Branch seams of the Bassetti-Erskine switch.** η bounds computed as in
   the note (Float64: 2.2061e-4 / 4.4121e-4). Extrapolated seam jumps:
   inner ≤ 7.3e-15, outer ≤ 3.0e-12 (doc's measured bound 4.7e-11); near-axis
   radial seam (ρ⁷ = ε/√η) per-component extrapolated relative gaps ≤ 2.6e-11
   for forces/Hessians and ≤ 4.5e-8 for L/D (worst case at η=η1, a
   second-order-small term); coupled D=0 round branch (2Hxy·bu) vs D→0
   near-round series: Richardson-extrapolated Δpz difference 1.7e-21; the same
   covariance represented uncoupled vs coupled (qxy=1e-300): identical to 0.0.
   (p3_seams.jl, p3b_near_axis_seam.jl)
5. **Independent quadrature anchor.** Simpson (200k-point) evaluation of the
   theory note §2 fixed-interval integral vs
   `_gaussian_beambeam_kick_response_principal` at η ∈ {1e-5, 1e-4, 3e-4
   (blend), 1e-3, 0.05, 0.3, 0.7} × 3 field points: max |rel err| = 2.5e-14
   across series/blend/elliptic/near-axis branches. H1 = −∂Kx/∂x and
   H2 = −∂Ky/∂y verified by FD to ~2e-10 (FD-limited); L identity
   L_over_D·D = Kx·y − Ky·x to 6e-17. (p7_quadrature.jl)
6. **Series coefficients hand-verified against the note.** C1–C3 force
   coefficients, U1–U3 potential, V1–V3 covariance responses, U4–U6 blend
   residual, near-axis J-coefficients (j00…j02 rederived from the
   ∂λ-generating formula), the cancellation-free L/D series (expanded from
   (Kx y − Ky x)/D and confirmed identical), the round-Hessian small-u series
   (φ, φ′ through u⁷), moment recurrences and the 25/17-term cutoffs — all
   match strong_beam.jl:676-1096 exactly.
7. **Slicing rules.** All 7 rules × ns ∈ {1,2,3,5,8,15}: Σw = 1 (≤1e-13
   error), centers antisymmetric, weights symmetric, sorted. Furman Table 1 at
   ns=5 reproduced to ≤5e-7 per entry for #1,#2,#3,#4,#5 **including the
   erratum value w2 = 0.137503 for #4** (the published 0.17350 is not used).
   Gauss-Hermite: Σwζ² = Σwζ⁴/3 = 1 to 4.4e-15. Degenerate ns=1 returns
   ((0,),(1,)) in every rule. Even-ns generalizations match doc §8.
   (p4_slices.jl)
8. **Weak-strong luminosity.** Thin density exact at and off origin
   (rel err 0.0 vs exp(−½ξᵀA⁻¹ξ)/(2π√detA)); 200k-particle ensemble vs
   closed-form Gaussian overlap: rel err 7.5e-5 (MC σ ≈ 2.2e-3); 7-slice
   hourglass luminosity equals the manual w-weighted transported-σ sum to
   2.2e-16; slice weight applied exactly once (kick via kbb·w, luminosity via
   l·w). (p5_ws_lum.jl)
9. **Strong-strong soft-Gaussian collide!.** Luminosity matches the
   closed-form overlap np1·np2/(2π√((σx1²+σx2²)(σy1²+σy2²))) in *both*
   `gaussian_when_luminosity` directions (ratios 0.998–1.006, MC- and
   moment-fit-noise-consistent, N=1e5); klum scales np1·np2/N_sampled verified;
   both beams kicked per slice pair with the doc §9 directed kick;
   `_slice_collision_order` time −(c1+c2)/2 is the correct meeting time and the
   weak-strong ns:-1:1 loop is the same chronological order. **F6 closure fix
   verified: no `Core.Box` in the lowered code of any
   `_slice_slice_gaussian_kick!` method.** (p6_ss_lum.jl)
10. **CPU/CUDA kick-stack parity (by reading).** The `_cuda_*` functions in
    strong_beam_track.jl:289-495 are a statement-level mirror of the CPU stack
    (same seams, same series calls, Faddeeva via `faddeeva_w_upper_reim`); the
    only semantic divergence found is U7-2's turn accumulation.
11. **Validation guards bind.** `_validated_covariance` symmetry/PSD
    tolerances (100·eps·scale) and `_xy_coupling_matrix` symplecticity
    tolerance (500·eps·‖M‖²) are on live paths of both constructors;
    `UnsafeVirtualDrift`/`_virtual_drift` reject unknown names with
    ArgumentError; hvoffset `dim` rejects non-:x/:y; `gaussian_when_luminosity`
    ∈ {1,2} enforced.
12. **Conditional-Gaussian slicing of a 6×6 covariance.** Slope = Σwz/σz²
    applied to (hoff,pxoff,voff,pyoff) in the correct index order
    (strong_beam.jl:386-389), conditional covariance Σww − ΣwzΣzw/σzz replaces
    the thin moments, sigz falls back to √cov[5,5] — all per
    weak_strong_6d_model.md §2–3.
