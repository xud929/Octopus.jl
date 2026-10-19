# U46: theory notes A: longitudinal kick, near-round switch, slice interpolation, longitudinal slicing

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Unit brief:
`result/comprehensive_audit_2026_10_18/plan/U46.md`. Depth: claims-vs-code with sampled
independent derivations (hypotheses 1-3 of the brief).

## Region

| file | lines | read |
|---|---:|---|
| `docs/theory/beam_beam_longitudinal_kick.md` | 1524 | 1-1524, every line |
| `docs/theory/near_round_bassetti_erskine_switch.md` | 1150 | 1-1150, every line |
| `docs/theory/slice_longitudinal_interpolation.md` | 1059 | 1-1059, every line |
| `docs/theory/gaussian_longitudinal_slicing.md` | 900 | 1-900, every line |

Total 4633 lines, all read. Reference code read for comparison (not the region, read only where a
note makes a claim about it): `src/elements/strong_beam.jl` 1-120, 120-300, 600-1320, 1478-1770;
`src/track/strong_beam_track.jl` 723-960; `src/tasks/strongstrong/gaussian.jl` 1-558;
`src/tasks/strongstrong/slicing.jl` 1-130, 136-250, 540-760; `src/tasks/strongstrong/pic_cpu.jl`
394-416, 1334-1362, 1448-1491, 1546-1600, 1757-1830, 1926-1990, 2470-2530, 2880-3010;
`src/tasks/strongstrong/pic_cuda.jl` 340-362; `src/tasks/strongstrong/interface.jl` 1240-1262 and
option lines by grep; `src/tasks/strongstrong/pic_cpu_sliced.jl` 1-60 (header only; the note
names `pic_cpu.jl`, not this file); `test/runtests.jl` 9050-9220; `validation/near_round_gaussian_transition.jl`
1-60 and its print block; `validation/gaussian_slicing_convergence.jl` 1-130, 206-265;
`docs/history/gaussian_slicing_convergence_2026_07_31.md` whole.

## Provenance

READ line by line: the four notes in full (ranges above) and the reference code ranges above.

EXECUTED (scratch `result/comprehensive_audit_2026_10_18/probes/U46/`, logs beside each script):

- `p1_near_round.jl` (`p1.log`): independent fixed-interval quadrature (400-point Gauss-Legendre)
  and a gauge-subtracted potential with cancellation-free integrand, against
  `_near_round_eta_bounds`, `_near_round_series_response`, `_elliptic_gaussian_near_axis_response`,
  `_gaussian_beambeam_kick_response_principal`. Numbers: eta bounds Float64 (2.2060596e-4,
  4.4121192e-4), Float32 (1.9966973e-2, 3.9933946e-2), delta_sigma 1.1030e-4/2.2061e-4 and
  9.9845e-3/1.9975e-2, (3/8)eta1^3 = 3.2209e-11 / 2.3881e-5 -- all equal to the Section 7 table.
  Series force vs reference 2.0e-15; series response vs spatial Hessian 4.0e-12; spatial Hessian vs
  2 dU/dlambda_i by finite differences (heat identity) 9.0e-12; L/D 3.4e-11. Core response remainder
  at the origin -3.713e-7 / +3.788e-7 at eta = 0.01 against (3/8)eta^3 = 3.750e-7. Near-axis J
  coefficients vs quadrature 3.3e-15 relative; near-axis evaluator vs reference 6.7e-16 (force) and
  4.4e-15 (response). Full Float64 route over eta in {0.5,1,1.2,1.5,1.8} x inner, outer, 1.5 outer,
  1e-2, 0.5, q in {1e-4,0.25,1,3,8}, 9 angles: max |dK| 5.2e-14, |dH| 7.5e-12, |dL/D| 7.5e-12.
  Float32 route: |dK| 5.1e-7, |dH| 5.9e-6.
- `p2_slicing_rules.jl` (`p2.log`): the five Furman rules, Gauss-Hermite and the `:equal_width`
  weight formula re-implemented from the note's formulas with `SpecialFunctions` only, against
  `Octopus._gaussian_slices` and the note's tables. N_s = 5: |independent - note| <= 4.9e-7 (the
  note prints 6-7 digits), |independent - Octopus| <= 2.2e-15 for all five rules and 0.0 for
  Gauss-Hermite. Section 5 moment table reproduced entry for entry (all 19 rows). Section 5.1 tail
  table reproduced (84.9 / 82.5 / 84.5 / 86.6 %), local orders 1.32, 1.26, 1.20; #4 deficit order
  1.83-1.87. Even N_s = 4, 6: #2 and #3 match Octopus to 4.4e-16; #4, #5, GH, #1 normalised and
  symmetric. Gauss-Hermite N_s = 101: 24 zero weights of 101, max node 19.06 sigma. `:equal_width`
  weights equal the displayed formula to 5.6e-17 (N_s = 5, 6).
- `p3_longitudinal_kick.jl` (`p3.log`): the code's direct collision-point kick (`_cp_kick`, i.e.
  centroid term + (1/4) H:A_u including the coupled rotation term) against -(1/2) dU/dS of the
  Gaussian potential computed by 600-point quadrature with an INDEPENDENT covariance transport
  (P (I + uN) Sigma (I + uN)^T P^T, u = -S) and centroid C(S) = C0 - p0 S + C2 S^2 / 2, five-point
  finite differences in S. Relative agreement: 1.6e-11 (flat coupled, eta = 0.988, Bassetti-Erskine
  branch), 9.0e-10 (near-round coupled, eta = 2.5e-5, series branch), 2.0e-9 (near-round coupled,
  eta = 3.0e-4, blend region), 4.2e-10 (uncoupled kernel); each at or below the step-halving change
  of the reference (2.4e-10 to 3.1e-9). Transverse forces against -grad U: 1e-12 to 1.6e-10.
  6D symplectic residual |J'OmegaJ - Omega|max by five-point finite differences, full map with
  centroid angle, curvature and coupling: hirata 8.7e-11, chromatic 1.2e-8, exact 1.9e-9,
  UnsafeVirtualDrift(:paraxial_frozen_longitudinal) 3.3e-4, UnsafeVirtualDrift(:chromatic_frozen_energy)
  3.3e-4. Kick-free round trips: hirata 0.0, chromatic 1.1e-13, exact 8.2e-14, paraxial-frozen 0.0,
  chromatic-frozen 1.2e-12 (relative to coordinates of 1e-4).
- `p4_followups.jl` (`p4.log`): the symplectic residual at steps 2h, h, h/2: hirata (4.3e-11,
  8.7e-11, 1.7e-10, roundoff-dominated); chromatic (4.0e-9, 1.2e-8, 1.1e-8); exact (2.7e-9, 1.9e-9,
  1.4e-8); with px, py x10: chromatic (2.9e-9, 6.1e-9, 2.4e-8), exact (1.6e-9, 1.1e-9, 1.1e-9) --
  step-dependent, so no violation is resolved for any canonical drift. `:equal_width` vs #1 at
  N_s = 5 with matched spacing: max weight difference 1.994e-3 (note: 2.0e-3).
- `validation/near_round_gaussian_transition.jl`, the committed harness, run unmodified
  (`near_round_validation.log`, exit 0, CUDA active): see LEAD U46-1 for the numbers.

Not executed: `validation/gaussian_slicing_convergence.jl`, `validation/slice_longitudinal_zscan.jl`,
`validation/slice_interpolation_emittance_growth.jl`, `validation/pic_grid_extent_stability.jl`
(minutes-to-hours; the first two have committed records, the third is declared non-regenerable).

## Leads

### LEAD U46-1 [Minor, confidence high] docs/theory/near_round_bassetti_erskine_switch.md:1073
Claim: The Section 10.1 table and the Section 11 bound "transition-force errors of 4.8e-6 or less in Float32" no longer match the committed harness, which today prints Float32 max transition force relative error 5.4797e-6 (table 4.7557e-6), force natural-scale 1.1852e-6 (8.4271e-7), response natural-scale 1.7500e-5 (1.4771e-5), response relative maximum 3.0642e-3 (text: 1.7781e-3), and Float64 force natural-scale 9.8139e-14 (6.3707e-14), response natural-scale 3.9900e-11 (3.1170e-11).
Mechanism: the table is a dated (2026-07-30) snapshot of roundoff-floor maxima over a dense grid, quoted without the host or libm identity; every structural number reproduces to the printed digits (both eta intervals, Float64 force 6.1096e-12, core gradients 1.1921e-7 / 2.2204e-16, the 6D residual 1.6001e-10, all sixteen Section 10.2 endpoint figures, the observed conditioning factors 61.937 and 4.948, Float32 CUDA parity 1.0541e-5), so what moved is the arithmetic of the evaluator path or host since the snapshot (candidates: the 2026-08-05_b U8-1/U8-3 changes, the 2026-10-16 fix H literal typing, FMA contraction on this CPU), and the Section 11 sentence states the superseded maximum as a ceiling.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. --threads=4 validation/near_round_gaussian_transition.jl | grep -E "max force relative error|max response natural-scale error"` prints Float32 `5.479682906508171e-6` and `1.7499985130754224e-5`, Float64 `3.9900009556868623e-11`; compare the table at `grep -n "maximum transition force relative error" docs/theory/near_round_bassetti_erskine_switch.md` and the bound at `grep -n '4.8\\times10^{-6}' docs/theory/near_round_bassetti_erskine_switch.md`.

### LEAD U46-2 [Minor, confidence high] docs/theory/slice_longitudinal_interpolation.md:936
Claim: Section 10.6 states that `:node` is implemented only on the CUDA sequential non-async route and that "the wavefront and batched-FFT routes ... throw", while the code runs `:node` on the production indexed wavefront route and throws only for the non-indexed sub-route that `pic_timing_detail = true` forces; the note's own Section 7.5 callout (2026-08-06) says the latter, so the note asserts both.
Mechanism: the 2026-08-06 correction (audit lead U26-2) revised Sections 7.5 and 12 and left 10.6 as written; `node_mode = _pic_node_grid_mode(solver)` enters the wavefront branch at `src/tasks/strongstrong/pic_cuda.jl:328-357`, the throw there is conditional on `!use_indexed_wavefront`, and the node-indexed wavefront interaction is documented at `pic_cuda.jl:1540`.
Repro: `sed -n '934,940p' docs/theory/slice_longitudinal_interpolation.md` against `grep -n "node_mode" src/tasks/strongstrong/pic_cuda.jl` (wavefront branch lines 328, 330, 344) and `sed -n '344,357p' src/tasks/strongstrong/pic_cuda.jl` (throws only when the indexed sub-route is disabled).

### LEAD U46-3 [Minor, confidence high] docs/theory/slice_longitudinal_interpolation.md:883
Claim: The Section 10.5 callout names `_pic_validate` as the function that rejects `grid_extent != :extrema` with `interaction_grid != :slice_pair`; no function of that name exists anywhere in `src/` -- the refusal is in the `PICPoissonSolver` constructor (`src/tasks/strongstrong/interface.jl:1485-1490`) and is repeated by `_validate_pic_solver` (`src/tasks/strongstrong/pic_cpu.jl:646`).
Mechanism: the name was copied from the 2026-08-05_b U26 report, which used the same non-existent identifier; the note's preamble replaced line numbers by function names precisely so that a pointer stays `grep`-able, and this one greps to nothing.
Repro: `grep -rn "_pic_validate\b" src/ test/ validation/` returns no line; `grep -n "is not implemented for interaction_grid" src/tasks/strongstrong/interface.jl` returns line 1486 inside the constructor.

### LEAD U46-4 [Minor, confidence high] docs/theory/slice_longitudinal_interpolation.md:520
Claim: Section 9 item 1 cites "the `GaussianPoissonSolver` docstring in `interface.jl`" as the home of the `field_derivative = :fourth` precedent, but `field_derivative` is a `PICPoissonSolver` option only (`interface.jl:1150, 1213, 1424, 1465, 1585`) and `GaussianPoissonSolver` (`interface.jl:891-967`) has no such option or docstring text.
Mechanism: wrong-owner pointer; the soft-Gaussian solver has no mesh and therefore no field stencil, so a reader sent to that docstring finds nothing about the precedent the paragraph relies on.
Repro: `grep -n "field_derivative" src/tasks/strongstrong/interface.jl` (every hit is at line 1150 or later, inside the PIC block) and `sed -n '891,900p' src/tasks/strongstrong/interface.jl` (the GaussianPoissonSolver signature without it).

### LEAD U46-5 [Minor, confidence med] docs/theory/slice_longitudinal_interpolation.md:144
Claim: Section 3.2 locates the `param = (lb=boundary[i], center=center[i], rb=boundary[i+1])` tuples "at the top of `collide!`"; they are `param1`/`param2` built inside `_pic_collide_pair!` (`src/tasks/strongstrong/pic_cpu.jl:394, 413-416`), carry a `weight` field as well, and none of the three `collide!` methods (`pic_cpu.jl:1, 5, 10`) builds them.
Mechanism: the same pointer rot the note's preamble says it removed; harmless for the C^0 argument the sentence supports, but the function named is the wrong one.
Repro: `grep -n -E "^function collide!|^function _pic_collide_pair!|param1 = \(" src/tasks/strongstrong/pic_cpu.jl`.

### LEAD U46-6 [Minor, confidence med] docs/theory/gaussian_longitudinal_slicing.md:513
Claim: The Section 6.1 table of "measured residuals" for the three virtual-drift models (round trip 0.0 / 1.6e-16 / 9.1e-17; T depends on (z_a, z_b) only through Delta 5e-20 / 3.5e-18 / 3.5e-18; group law 9e-19 / 5.2e-15 / 3.5e-15; p_z across T 0.0 / 1.6e-16 / 1.0e-16) has no committed harness and no committed record of the numbers.
Mechanism: `test/runtests.jl`, `validation/` and `docs/history/gaussian_slicing_convergence_2026_07_31.md` contain no telescoping or one-parameter-group check; the record only says the result "stands as a recorded result (theory note Section 6.1)", i.e. the note cites itself. This unit's probe re-measures the round-trip row independently (chromatic 1.1e-13 and exact 8.2e-14 relative to coordinates of 1e-4, about 1e-17 absolute, consistent with the table) but the other three rows remain unreproduced.
Repro: `grep -rn -i -E "telescop|one-parameter group|T\(Δ" test/runtests.jl validation/ docs/history/gaussian_slicing_convergence_2026_07_31.md` returns nothing; `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U46/p3_longitudinal_kick.jl` prints the round-trip residuals.

### LEAD U46-7 [Minor, confidence med] docs/theory/gaussian_longitudinal_slicing.md:638
Claim: The Section 7.1 hadron-side Q(N_s) table carries columns N_s = 1, 4 and 11 -- and the conclusion "slicing falls below the drift-model error at N_s = 4; use N_s = 5" rests on the N_s = 4 cell -- but the committed harness computes Q only at `ns_list = [3, 5, 7, 9, 15, 21, 31, 45, 61]` and the history record does not carry this table.
Mechanism: three cells reproducible only by editing the harness configuration; the drift floors in the same section (2.93e-4 / 3.88e-5 / 2.76e-8 / 1.41e-9) are not in question, the harness prints them (`validation/gaussian_slicing_convergence.jl:235-240`), and they are repeated in `src/elements/strong_beam.jl:154-155, 1769`.
Repro: `grep -n "ns_list" validation/gaussian_slicing_convergence.jl` (line 99) and `grep -n -E "3\.8e-4|4\.1e-5|6\.8e-6" docs/history/gaussian_slicing_convergence_2026_07_31.md` (no hits).

### LEAD U46-8 [Minor, confidence low] docs/theory/beam_beam_longitudinal_kick.md:1496
Claim: Check 9 of Section 10 ("Six-dimensional symplecticity ... for a complete map") is stated without qualification, but with the `:chromatic` drift the implemented composite is a momentum-dependent thin kick in collision-point coordinates and is symplectic only to O(S Phi dF/dS), because the kick is evaluated at the input S = (z_in - z_*)/2 while the particle's collision-point coordinate is z_in + 2 S Phi (Section 7's "frozen-collision-field approximation", line 765); `:hirata` (z unchanged) and `:exact` (S solved self-consistently from the collision-point z) are exactly symplectic.
Mechanism: in collision-point variables S_in = S_CP / (1 + Phi(p_x, p_y, p_z)), so dF/dp_x acquires dS_in/dp_x * dF/dS; for a map (q, p) -> (q, p + f) symplecticity needs df/dp = 0. Analytic lead: the estimated size here (~1e-9 in Jacobian entries) is below the finite-difference resolution, and the measured residuals (chromatic 1.2e-8, exact 1.9e-9, hirata 8.7e-11) are step-dependent, so no violation was resolved; the point is that check 9 as written will show a non-zero, drift-dependent residual for `:chromatic` that is not a bug.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U46/p4_followups.jl` prints the (2h, h, h/2) residual triples; the analytic statement follows from `_forward_virtual_drift(::ChromaticDrift, ...)` returning `S = W(z - zo)/2` of the input z while advancing `z += 2 * S * phi` (`src/elements/strong_beam.jl`, `grep -n "z += 2 \* S \* phi" src/elements/strong_beam.jl`).

### LEAD U46-9 [Minor, confidence high] src/elements/strong_beam.jl:67
Claim: (Out of region, cross-file seam with the first note.) Two docstrings state the paraxial Hirata energy term as `pz -= S/2 (px^2 + py^2)` (`strong_beam.jl:67` in `_virtual_drift_writes_z`, and the `why=` string of `_cross_backend_rounding` at `strong_beam.jl:254`), but the kernel and the note's Section 6 have the S-independent `pz -= (px^2 + py^2)/4`.
Mechanism: `_forward_virtual_drift(::HirataParaxialDrift, ...)` executes `pz -= oftype(S, 0.25) * (px * px + py * py)`; the docstrings describe a term proportional to the half slice distance that does not exist, and the rounding-class "why" string is surfaced to users through the cross-backend contract.
Repro: `grep -n "S/2 (px" src/elements/strong_beam.jl` (lines 67, 254) against `grep -n "0.25) \* (px \* px + py \* py)" src/elements/strong_beam.jl`.

### LEAD U46-10 [Minor, confidence med] src/tasks/strongstrong/pic_cpu.jl:2473
Claim: (Out of region, cross-file seam with the third note.) The `_pic_cic_weights` docstring still says the out-of-range zero-weight branch "exists so that the robust estimators (`:sigma`, `:quantile`) cannot silently corrupt the field", while `:quantile` was removed (the note's Section 10.5 and the `grid_extent` validator `grid_extent in (:extrema, :sigma)` at `interface.jl:1469`).
Mechanism: a removed public value survives in a code docstring as a live option; a reader of the deposit code is told an estimator exists that the constructor refuses.
Repro: `grep -n "quantile" src/tasks/strongstrong/pic_cpu.jl src/tasks/strongstrong/interface.jl` -- the pic_cpu.jl docstring hit lists it as an estimator; `interface.jl:1469-1470` accepts only `:extrema` and `:sigma`.

## Clean

Note 1, `beam_beam_longitudinal_kick.md`, against `src/elements/strong_beam.jl`, `src/track/strong_beam_track.jl`, `src/tasks/strongstrong/gaussian.jl`:
- Virtual drifts, all five, read against Sections 6-7 term by term: Hirata forward `pz -= q/4`, reverse `+= q/4`; chromatic forward `phi = sqrt(1 - q/(2P^2)) - 1`, `x += S px/P`, `z += 2 S phi`, `pz += P phi`, reverse with `psi = sqrt(1 + q/(2P^2)) - 1` and S recomputed from the collision-point z; exact forward `S = (z - z_*) p_s / (2 p_s + H)` (the code's `z2 = (z + rr zo)/(1 + rr)` form reduces to it), `z -= H/p_s S`, `pz -= H/2`, reverse `H_r = q/(2P)`, `p_s0 = P - H_r/2`, `z += H_r/p_s0 S`, `pz += H_r/2`; the two unsafe models freeze exactly what the Section 7 table says; the symbol lookup `_virtual_drift(::Symbol)` consults `_VIRTUAL_DRIFT_TYPES` (hirata, chromatic, exact) only, so the unsafe names are not selectable by a plain symbol, as claimed.
- Independent derivations recorded: S/P is invariant along the chromatic Lie flow (dS/dtau = -S q/(4P^2), dP/dtau = -q/(4P)), giving z^- = z + 2 S Phi, p_z^- = p_z + P Phi; the inverse with Psi follows from (P^-)^2 = P^2 - q/2 and S_inv = S P^-/P; the exact-drift forward map from the type-3 generating function (x_0 = x_CP - p_x S/p_s, z_0 = z_CP + H S/p_s, p_z^- = p_z - H/2) and its inverse (P = (P_0 + p_s0)/2, q = P_0^2 - p_s0^2, H_r = q/(2P)); the chromatic and exact slingshots vanish exactly at q^+ = q^- ; R^T A_u R = Lambda_u + theta_u (J Lambda - Lambda J); the uncoupled Twiss limit d sigma_x^2/du = -2 eps (alpha + gamma S).
- Direct collision-point kick: `_cp_kick` centroid term `0.5 ((px - px0)(pxo - ppxo S) + (py - py0)(pyo - ppyo S))` is (1/2) F . C_u with C_u = p0 - C2 S; the relative coordinate `x - xo + pxo S - 0.5 ppxo S^2` is r - C(u) with C = C0 + p0 u + C2 u^2/2, u = -S; the uncoupled kernel adds `0.25 (Hxx au + Hyy du)`; the coupled kernel adds `0.125 ((H11 + H22) tr_u + (H11 - H22) D_u) - 0.5 kbb rotation_projection L/D`, which is (1/4)(U11 lambda_1,u + U22 lambda_2,u) - (1/2) theta_u (F_x y - F_y x) with theta_u = ((a-d) b_u - b (a_u - d_u))/D^2 split into two finite factors; the D = 0 branch uses the invariant lab-frame contraction with the round Hessian; `_transport_transverse_moments` is A(u) = A0 + u(B0 + B0^T) + u^2 Q0 with u = -S, and A_u = B0 + B0^T + 2 u Q0. Measured (P3): code vs -(1/2) dU/dS from an independent transport, centroid and quadrature agrees to 1.6e-11 (BE), 9e-10 (series), 2e-9 (blend), 4e-10 (uncoupled), all at the finite-difference floor; forces to 1e-12..1.6e-10.
- Strong-strong consumer (`_apply_slice_kick_one!`): `xx = x - mx + mpx S`, `pz += 0.5 ((px - px0) mpx + (py - py0) mpy)` and the shared `_cp_covariance_kick` with `StrongTransverseMoments(sx^2, 0, sy^2, covxpx, 0, 0, covypy, spx^2, 0, spy^2)` is Section 9 (C_2,u = p_2, A_2,u = B + B^T + 2 u Q); with `longitudinal_kick = false` the solver substitutes `UnsafeVirtualDrift(_ParaxialFrozenLongitudinalDrift())` and restores `pz`, which is the note's diagnostic use.
- CUDA twin: `_cuda_thin_strong_beam_track`, `_cuda_cp_kick`, `_cuda_cp_covariance_kick` are the same sequence with the same literals, differing only in the Faddeeva evaluator (`faddeeva_w_upper_reim`).
- Section 10 checks 1-8 are consequences of the verified formulas; check 9 measured: hirata 8.7e-11 (floor), the two unsafe drifts 3.3e-4, i.e. non-symplectic as Section 7 states; the paraxial-frozen drift round-trips exactly and the chromatic-frozen one does not (1.2e-12, the predicted O(S Phi p_x) size).

Note 2, `near_round_bassetti_erskine_switch.md`, against `strong_beam.jl:930-1320` and the CUDA twin:
- Every named artefact exists: `src/track/strong_beam_track.jl` (the counterpart), `validation/near_round_gaussian_transition.jl`, the `"Near-round Gaussian transition"` testset (`test/runtests.jl:8587`), `ROUND_BEAM_THRESHOLD` absent from `src/`.
- Section 9 procedure, step by step: eta = D/(a+d) in both kernels; `expm1` round branch at eta == 0; `outer = ((8/3) C eps)^(1/4)`, `inner = outer/2`, C = 64 / 8, other `Real` types throw `ArgumentError`; series for eta <= inner; quintic `10t^3 - 15t^4 + 6t^5` with `dw = 30 t^2 (t-1)^2 / width` and the chain term `kbb dw deltaU / v` with the (1 -+ eta) factors; Bassetti-Erskine for eta >= outer; `rho^7 <= eps/sqrt(eta)` near-axis switch (computed as rho2^3 sqrt(rho2)); series moments for q <= 2 with 17 / 25 terms (`last_order` 16 / 24) and the upward recurrence above; the GaussianPIC add-back takes force and response from one `_gaussian_beambeam_kick_response` call (`gaussian_pic.jl:916-918`, CUDA twin 881-883).
- Coefficients C_{1..3,j}, U_{1..6}, V_{1..3}, the L/D series and the J^(x)_{mn} closed forms match the note symbol for symbol; by hand: C_{n,j}(q=0) = (-1/2, 1/2, -3/8) equal the expansion of 2/(sigma_1 (sigma_1 + sigma_2)) to O(eta^3); V_1 = v dU_1/dv and v dU_0/dv = -e^{-q}; the (3/8) eta^3 remainder follows from U_3(0) = 0. Measured (P1): all numbers in Provenance; Section 7 table reproduced to every digit; the harness reproduces every structural number (LEAD U46-1 lists the maxima that did not).
- Section 3's bound max R_1 = 1/2 via q M_2 = 2 M_1 - e^{-q} and M_1/M_0 <= 1/2 checked by hand; Section 5.2's J generating formula checked for J_10 by hand and all six by quadrature.

Note 3, `slice_longitudinal_interpolation.md`, against `pic_cpu.jl`, `slicing.jl`, `interface.jl`, `pic_cuda.jl`:
- Every function the note names exists except `_pic_validate` (LEAD U46-3): `_pic_build_node_grids!` (with the `xv = rep.x[i] + sh * rep.px[i]` pair and source drifts `0.5 (c - boundary[b])`), `_slice_interpolation_parameters` (returns `1/(rb - lb)` and `rb/(rb - lb)`; callers form `zL = clamp(-z hzi + zbias, 0, 1)` = 1 - t), `_pic_interpolate_kick` (`Kz += w (phiL - phiR)`, no t weight; callers apply `kick_scale = 2 kbb` and `hzi`), `_pic_interpolate_kick_quadratic` (L_L, L_M, L_R and `(3 - 4t) phiL + (8t - 4) phiM + (1 - 4t) phiR`, i.e. the note's -dq/dt), `_pic_interaction_grids`, `longitudinal_slices`, `_slice_collision_order` (keyed by -(c1 + c2)/2), `_pic_store_slice!`, `_pic_extract_slice`, `_pic_union_bounds`, `_pic_cic_weights` (zero weights outside [0, n-1] or non-finite), `_finish_longitudinal_slices` (`:centroid` mean z with midpoint fallback for an empty bin, `:midpoint` (b_s + b_s+1)/2), `_PICFieldWorkspace`, `_cuda_pic_interaction_wavefront_quadratic_indexed_batched_fft!`, `green_cache = :slice_pair`, `grid_quantize` (2^q ladder, origins to whole cells), `grid_extent in (:extrema, :sigma)` with `:quantile` removed, the `:node`/`grid_extent` refusal, `center_position` validated at `interface.jl:840`, `:equal_area` pinning `boundaries[1] = zmin`, `boundaries[end] = zmax` with a `nslices * resolution` histogram.
- Section 3.1, 7.3, 7.4 and 9 constants re-derived: Delta^2/32 (linear, Delta sigma = Delta/2), 2h^3/(3 sqrt 3) and h^3/(9 sqrt 3) = Delta^3/997.7 (quadratic, h = Delta/4), the nodal derivative errors +h^2 g'''/3 and -h^2 g'''/6 and the 2 k Delta^2/12 bound (h = Delta/2 in z), L_L(3/4) = -1/8, sum|L_i| = 1.25, ||L||_2 = 0.848 vs 0.791 at t = 1/4; the three-node formula at t = 1/2 is phiL - phiR, and the weights sum to zero.
- Records and harnesses named exist: `validation/slice_longitudinal_zscan.jl`, `slice_interpolation_emittance_growth.jl` and its `_summary.jl`, `pic_grid_extent_stability.jl`, `docs/history/slice_longitudinal_interpolation_record.md` (carries the 0.470 / 0.621 crossing fractions and the arm table), `docs/history/todo_ledger_archive.md`; companion notes `pic_free_space_kernels.md`, `weak_strong_6d_model.md` exist; `docs/README.md` indexes all four notes (lines 206, 212, 337, 349).

Note 4, `gaussian_longitudinal_slicing.md`, against `strong_beam.jl:1478-1760`, `slicing.jl`, `test/runtests.jl:9059-9212`:
- Section 10 table: all eight `slice_method` values exist, `ParamMeta(default=:sqrt_density)` and both constructors default to it, `slice_center`+`slice_weight` bypass the rule (and a lone one is refused), `:equal_width` weights are the displayed integrated-charge formula with the N_s Delta/2 truncation (measured 5.6e-17), `:equal_spacing_density` carries the 1 + (N_s - 3)/12 span, even N_s handled as Section 8 says (measured against the code to 4.4e-16).
- Test claims verified in the suite: Table 1 at N_s = 5 pinned per entry to 5e-6 with the 0.137503 erratum, Gauss-Hermite moment exactness through 2 N_s - 1, the default pinned, the Section 5.1 deficit ordering pinned at N_s = 15, 31.
- Independent re-derivation (P2): all five rules, Gauss-Hermite, Table 1, the moment table, the tail-share table and its drifting order, the #4 order ~1.8, 24 zero Gauss-Hermite weights of 101, and the 2.0e-3 `:equal_width`-vs-#1 figure; by hand: the erratum row sums to 1.072, (I2)/(I3), #1 and #2 node values at N_s = 5, the F_2 generating function supplying p_z -> p_z - q/4.
- Section 9.5: `:normal_quantile` boundaries are `mu + sigma q` from the measured live mean and rms (`slicing.jl:540`), clamped to the live extrema, with `:centroid` nodes -- the sampled analogue of #3 as stated.
- Section 7.1 drift floors have their harness (`gaussian_slicing_convergence.jl:235-240`), and the history record carries the Section 10 ranking table.

## Unchecked

- The reference papers (Furman et al. Table 1 and its erratum, Hirata-Moshammer-Ruggiero, Leunissen-Schmidt-Ripken, Bassetti-Erskine, Xsuite `TempSlicer` modes): not accessible from this session; the notes' statements about them are taken as given.
- Note 3 Sections 7.5, 10.1-10.4 and 11 measured tables (turn times, z-scan errors, cache statistics, coarsening ratios, emittance-growth arms): not re-run (minutes to hours each; Section 11 is declared non-regenerable by the note). Their harnesses and the 2026-07-26 record exist; the numbers were not re-measured here.
- Note 4 Section 10 ranking table and Section 7.1 Q rows at N_s in the harness list: harness not re-run (the record carries the ranking; LEAD U46-7 covers the rows the harness does not produce).
- The CUDA PIC kernels behind note 3's CUDA claims (`_cuda_pic_*` in `pic_cuda.jl` beyond lines 340-362 and the grep hits), and the CUDA Faddeeva evaluator `faddeeva_w_upper_reim`: outside the region; only their presence and call shape were checked. CPU/CUDA parity of the near-round evaluator was taken from the harness run (Float32 1.0541e-5, Float64 1.8544e-11).
- The chromatic composite's O(S Phi dF/dS) symplecticity defect (LEAD U46-8) was not resolved above finite-difference noise; a higher-precision (BigFloat or automatic-differentiation) Jacobian would decide it.
