# U10 report — lattice tracking core (commit 13c2733)

## Coverage
Read every line of:
- `src/elements/lattice_magnets.jl` lines 1-1223 (helpers, drift/bend/kick, curved potential, all six fringe/geometry maps, runtime, compile path, all six spec blocks, RBend alias)
- `src/elements/solenoid.jl` lines 1-437 (struct, helpers, curved integrator, exact map, Strang split, compile, spec)
- `src/elements/linear6d.jl` lines 1-306 (spec, runtime, validator, optics builder, zeta/eta/R factors)
- `src/elements/linear_maps.jl` lines 1-236 (crab/momentum dispersion, XY coupling)
Theory cross-checks: `docs/theory/lattice_hamiltonian_and_conventions.md` Sections 4-7 (esp. 5.3, 6.2-6.5), `docs/theory/solenoid.md` Sections 2-6, 14, 15.
Probes in `/tmp/claude-320114/-cfs-ad-dxu-Library-Julia-Octopus/94771dda-fd24-4438-922e-a4bd8afa2361/scratchpad/U10/` (p1...p11), all run from repo root with the ForwardDiff stacked env.

## Leads

### U10-1 — solenoid.jl:237 — `_curv_sin(kappa/2, L)` strict `(::T,::T)` signature; straight solenoid map cannot be coordinate-differentiated — HIGH
`kappa = ks/ps` is COORDINATE-dependent (solenoid.jl:228), so under a ForwardDiff
coordinate Jacobian `kappa/2::Dual` meets `L::Float64` and
`_curv_sin(h::T, L::T) where T` (lattice_magnets.jl:39) has no method. This is
exactly defect class 4 (the class that already bit `_sol_log_over_h`, whose fix
note at solenoid.jl:90-95 documents the trap). Reached from the pure solenoid
(`Solenoid{...,0,false}`), from the compiled element, and from every
Strang-split multipole solenoid (`_sol_body` -> `_solenoid_map`); P6's
symplecticity sweep crashed on it. Complex-step is independently impossible:
`complex(x, y)` at solenoid.jl:237 throws `complex(::ComplexF64, ::ComplexF64)`.
Every LatticeMagnet kernel supports Dual coordinates (P6 passes); the solenoid
alone does not.
Repro: `U10/p1_solmap_mixed_types.jl` (MethodError on raw map, compiled element,
and complex-step), `U10/p6_full_magnet_symplecticity.jl` (crash in `_sol_body`).

### U10-2 — solenoid.jl:390-392 — `Solenoid(spec)` promotes T over (L, ks, h) only; Dual multipole strengths throw — MEDIUM
`T = float(promote_type(typeof(L), typeof(ks), typeof(h), Float64))` omits
`kn`/`kskew`, then `T(kn_raw[i])` converts. A parameter derivative w.r.t. a
superimposed strength (`SolenoidSpec(L=1, ks=0.3, k1=Dual)`) survives spec
construction (`_fold_named_strengths` promotes correctly) and dies in the
runtime constructor with `MethodError: Float64(::Dual)`. Controls:
`d(px)/d(ks)` works; `LatticeMagnet` works because it uses `numeric_type(spec)`
(Knowledge.jl:428), which folds over all params — the exact machinery the
comment at lattice_magnets.jl:819-820 says was added to stop this failure mode.
Repro: `U10/p2_solenoid_param_dual.jl`.

### U10-3 — solenoid.jl:301-303 + 405/410 — `curved=false` with `h != 0` produces a NON-SYMPLECTIC kick — MEDIUM
The compile gates the psi table on `hc = curved ? T(h) : zero(T)` (line 405,
comment: "a caller who asked to ignore the curvature tracks a straight
solenoid") but stores `T(h)` in the element (line 410), and `_sol_kick` passes
`elem.h` to `_lattice_kick`. For content beyond a pure normal dipole that kick
is not a gradient (the Cauchy-Riemann violation documented at
lattice_magnets.jl:186-193). Measured (finite-difference Jacobian, floor 6e-11):
- `SolenoidSpec(L=1, ks=0.05, h=0.05, k0s=0.05, curved=false)`: |J'SJ-S| = 2.50e-3
  (the code's own predicted O(L h Ks0) = 2.5e-3)
- same with `k1=0.5, nst=4`: 2.54e-5
- h=0 controls: 6.3e-11, 3.4e-11.
Fix direction (not applied): store the gated `hc`, or pass it in `_sol_kick`.
Repro: `U10/p7b_sol_curved_false_symp.jl`.

### U10-4 — lattice_magnets.jl:783, 801-805 — LatticeMagnet `curved=false` with `h != 0`: warning claims curvature ignored, kick keeps it — LOW
`combined = _needs_curved_potential(kn, ks, h)` is not gated on `curved`
(contrast solenoid.jl:405), so with `curved=false, h=0.1, k1=0.5` the compile
builds an 81-entry psi table from h and `_step_kick` runs `_curved_kick`; the
`_lattice_kick` path likewise receives `elem.h`. The @warn text "the frame
curvature is ignored and the body tracks in a straight frame" is false for the
kick: tracking differs from the h=0 element by 1.55e-7 over one element. The
composite stays symplectic (gradient kick), but it is neither the curved nor
the straight element, and the two files resolve the same question oppositely.
Repro: `U10/p7_curved_false_routing.jl`.

### U10-5 — lattice_magnets.jl:48-55 — `_curv_vers` closed branch loses 8 digits just above its crossover — LOW
The guard protects |u| < 1e-4, but the `(1 - cos u)/h` cancellation persists to
u ~ 1e-2 (relative error ~ eps/u^2). Measured vs BigFloat at L=1:
u = 0.999e-4 (series): 5.2e-17; u = 1.001e-4 (closed): **5.86e-9**. The helper
exists (per its own comment and Section 5.2) to stop a 5-8 digit loss, and that
loss is fully present at the first representable point outside the window.
Absolute effect on C2 is ~eps/(2h) ≈ 1.1e-12 m at h = 1e-4, decaying as u grows.
A cancellation-free identity (2 sin^2(u/2)/h) or a ~1e-2 crossover would close it.
`_curv_sin` and `_atan_over` are clean on both sides (2.6e-17 / 4.1e-17).
Repro: `U10/p3_series_boundaries.jl`.

### U10-6 — solenoid.jl:99 — `_sol_log_over_h` series truncated at O(u^2) for a 1e-4 crossover: 2.5e-13 value gap, 1.5e-8 derivative error — LOW
Series `x(1 - u/2(1 - 2u/3))` omits the u^3/4 term; at the boundary the series
side is 2.49e-13 relative from BigFloat while the closed side is 9.5e-17, a
~1100-ulp jump across one ulp of h (measured 2.499e-13). d/dh at the boundary:
series side relerr 1.50e-8 (exact -0.49993334083, series -0.49993333333). The
sibling helpers carry one more term and sit at ~2.6e-17. One more series term
(u^3) or a ~3e-6 crossover restores the family's standard.
Repro: `U10/p3_series_boundaries.jl`.

### U10-7 — lattice_magnets.jl:446 — `_wedge` Delta cancellation grows as 1/b1 — LOW
`Δ = (A + asin(px/w) - asin(pxn/w))/b1` cancels to O(b1) computed from O(A)
terms — the identical pattern `_lattice_bend` was rewritten to remove (class 2).
Measured y/z absolute error vs BigFloat (A=0.1, mm-scale coordinates):
b1=1e-6: z err 1.06e-11; b1=1e-8: 2.81e-10; b1=1e-10: 5.72e-8 (clean 1/b1
scaling). The `b1 == 0` short-circuit to `_rot_xz` is exact and the b1->0 limit
is consistent (difference linear in b1: 9.98e-8 at b1=1e-3), but small nonzero
b1 (a weak corrector-like bend with pole-face angles) is unprotected. `_wedge`
is symplectic at moderate b1 (2.9e-16).
Repro: `U10/p4_wedge_small_b1.jl`.

### U10-8 — docs/theory/lattice_hamiltonian_and_conventions.md:824-825 vs lattice_magnets.jl:490-494 — SAD cubic equations in the note drop the 1/(1+delta) factors — DOC, LOW
Note: `Δp_y = -h²y³/(18FG)`, `Δz = +h²y⁴/(72FG)·(1+δ)/(1+δ)²`. Code:
`c3 = b²/(72·fg·(1+δ))`, `Δp_y = -4c3y³ = -b²y³/(18FG(1+δ))`,
`Δz = -c3y⁴/(1+δ) = -b²y⁴/(72FG(1+δ)²)`. The code's pair is exactly the
gradient of g = b²y⁴/(72FG(1+δ)) (verified analytically; P6 shows the full map
symplectic to 1.2e-15) and is pinned off-momentum by the `sbend_fint` PTC case
(fint·hgap = 0.015, pz up to 2.5e-3, Contracts.jl:1613). The note's displayed
pair is not symplectically consistent under either S56 orientation (Δp_y is
δ-independent while Δz carries 1/(1+δ)), so the note, not the code, drifted.

### U10-9 — note line 614 vs lattice_magnets.jl:603-605 — contradictory claims about PTC's KILL_*_FRINGE — DOC, LOW
Note 6.1: the kill flags "disable a face entirely". Code comment: kill
"deliberately does NOT suppress ROT_XZ, FACE or WEDGE, which are geometry
rather than fringe and which PTC leaves running" — and the implementation
follows the code comment (bits FRINGE_DIPOLE_EDGE blocks run un-killed at
lines 597-599, 618-624, 631-634, 648-651). One of the two mischaracterizes
PTC. Nothing pins it: no PTC reference case sets kill_ent/kill_exi (grep of
Contracts.jl), although note 6.5's own benchmark table lists the flags as
must-pin.

### U10-10 — unknown-keyword acceptance: mechanism and guard surface (class 9, characterization only) — INFO
Mechanism: every friendly constructor ends in
`ElementSpec{kind}(_spec_params(; kwargs...))` (lattice_magnets.jl:941-944,
linear_maps.jl:8-10) — `_spec_params` is a bare `Dict{Symbol,Any}` of all
kwargs; `ElementSpec` stores it; compile reads only known keys via `getparam`.
Three observed tiers (P10/P11):
1. Fully unknown key: `QuadrupoleSpec(L=0.3, k1=1.2, this_keyword_does_not_exist=1.0)`
   constructs, compiles, tracks; the key sits in `params(spec)` forever.
2. Typo'd strength: `QuadrupoleSpec(L=0.3, k1s_typo=1.2)` compiles to
   `kn = (), ks = ()` — a silently field-free magnet.
3. Out-of-schema but compile-known keys CHANGE PHYSICS silently:
   `QuadrupoleSpec(L=0.3, k1=1.2, e1=0.2)` shifts tracking by 7.7e-7 because
   `_lattice_magnet` reads e1/e2/h/b0/fint*/hgap*/hface*/bend_fringe/curved for
   every kind and `bend_fringe` defaults TRUE for every kind (line 788), so all
   six magnets carry FRINGE_DIPOLE_EDGE|FRINGE_BEND bits; `parameter_schema`
   for quadrupole lists neither e1 nor bend_fringe.
Guard surface: `parameter_schema(spec_type)` already answers correctly
(`haskey(...) == false` for unknown keys), so a strict guard needs one check in
the friendly constructors (or `ElementSpec{kind}` + registry lookup) comparing
kwargs against schema keys. It must stay opt-out per kind: linear_maps.jl's
docstrings *promise* "extra keyword arguments are stored as descriptive spec
metadata" (lines 22-23, 90-91, 160-161). Tier-3 keys would need either schema
entries for all kinds or per-kind read masks. NOT fixed, per mandate.

### U10-11 — linear6d.jl:122-168 — symplecticity validator orders on `T`; Complex entries throw MethodError — LOW
`ratio > max_ratio` / `error.ratio <= one(T)` / `eps(T)` require an ordered T.
A complex-step parameter derivative through `Linear6D` (the `T<:Number`
widening's stated purpose, lines 57-59) dies:
`MethodError: isless(::ComplexF64, ::Float64)`. ForwardDiff Duals DO pass
(verified: d(x)/d(dmu1) = -2.9552020666133953e-4 = exact) but only via the
explicit `Linear6DSpec{T}` spelling; the default `Linear6DSpec(...)` pins
Float64 at spec construction and throws `Float64(::Dual)` (documented signature,
but inconsistent with the lattice magnets' automatic promotion).
Repro: `U10/p8_linear6d.jl`.

## Sound (invariant verified, and how)
- `_lattice_bend`: both branches symplectic (|J'SJ-S| ≤ 1.1e-16 at hL = 0.05 and
  1.7, on/off design orbit); continuous across the |hL| = pi/2 switch
  (difference linear in ε: 9.4e-9/9.4e-12/9.5e-15 at ε = 1e-6/1e-9/1e-12);
  b0->0 agrees with the curved drift linearly down to the 1.4e-15 floor
  (b0 = 1e-16 and 0 coincide). All three branch comparisons use `real(T)` [p5].
- `_lattice_drift(Val(true))`: symplectic 1.2e-17; h=0 agrees with the straight
  branch to 4.3e-19; h->0 linear [p5].
- Full fringe stack symplectic to roundoff: sbend all-mechanisms (o2: 1.2e-15,
  o4: 5.1e-16), drift_kick 6.7e-16, quad fringe=:all 4.4e-16, multipole+k0
  9.2e-18, curved skew-dipole via psi table 4.4e-16 [p6].
- `_needs_curved_potential` is exactly the Cauchy-Riemann condition: h != 0 and
  (any order >= 2, or skew dipole); normal dipole alone exempt — matches the
  `h·Im f == 0` math precisely (read check; sweep pins it per assignment).
- `_curved_potential_coeffs`/`_curved_kick`: recursion, seeds, and n!/k!
  bookkeeping match Section 4.4; gradient-from-one-table structure; reduces to
  the straight kick linearly in h (1.8e-10/1.8e-13/1.8e-16 at h=1e-3/-6/-9) [p11].
- Face composition = note 6.3 steps 1-7 entrance, exact reverse at exit; kill
  flags gate mechanisms 3-5 only; `_wedge(-e)` sign; `_bend_strength` shows the
  same field to the faces under both bend models (read check vs note).
- `_multipole_fringe`: BN(j) = K_{j-1}/(j-1)! conversion, U/V/derivative algebra
  and J^{-T} update match note 6.2 exactly (hand check); z-update is the exact
  ∂S/∂Pz of the generating function with the ported sign; N<=1 return; hf cap
  changes tracking as PTC's MIN(NMUL, HIGHEST_FRINGE) [read + p11].
- `_soft_quad_fringe`: reproduces the note's implemented map including the
  generating-function z-update — verified analytically term-for-term
  (∂F̃/∂δ = -dz exactly); signed square va|va| present.
- `_fringe_dipole_exact`: Φ0, the nine slope-Jacobian entries, the f1/f2/f3
  contractions, and the cancellation-free y root all match note 6.3.1; the
  old-momenta/new-y evaluation pattern is exactly an F3-type generating
  function, hence exactly symplectic (hand derivation + p6).
- `_face`, `_wedge_quad`: match note equations; both exact gradients;
  wedge_coeff default (1,2) = PTC MAD8_WEDGE with (0,0) escape documented.
- Multipole normalization converts n! exactly once end-to-end: thin-limit
  sextupole and octupole kicks match -L·K_n·Re/Im[(x+iy)^n/n!] with ratio
  1.0000000000000002 [p10].
- Forest-Ruth coefficients: algebra checked, sums 2(d1+d2)=1, 2k1+k2=1; matches
  PTC METHOD=4 form.
- Solenoid: ks=0 ≡ exact drift (1.7e-16); ks=0 + k1 ≡ QuadrupoleSpec (6.1e-18);
  curved solenoid symplectic at the FD floor (2.4e-14, pure and with k1);
  `_sol_curved_deriv` ≡ note 15.2 term-for-term; `_solenoid_edge` signs are the
  symmetric-gauge canonical<->kinetic conversion; Larmor half-angle displacement
  phasor verified against the integral [p6, p11 + hand check].
- linear_maps: CrabDispersion ≡ `_mzeta66` and MomentumDispersion ≡ `_meta66`
  exactly (0.0 difference); all maps symplectic ≤ 2.2e-16 including XYCoupling
  both modes and `_mR66` (block-determinant hand proof + numeric) [p9].
- linear6d optics path: matrix symplectic 2.2e-16 with dispersion + coupling +
  crab factors; Twiss block matches the docstring convention
  (M11 = cos(dmu), M12 = beta·sin(dmu) verified numerically) [p8].
- RBend: e1/e2 += angle/2 on top of user angles = MAD-X conversion; L as arc
  length matches MAD-X rbarc default.
- Error paths in all four files interpolate defined values (read check; no
  `$(nothing)` siblings found).

## Minor observations (not leads)
- solenoid.jl:431 `nst` ParamMeta `default=1` while the compile default is 16
  for curved (meaning text explains it; the machine-readable default is stale)
  [p11].
- `_solenoid_curved_map` line 184: `mz` assigned every sweep, never read (z'
  does not depend on z; harmless dead store — class 10 stored-never-read).
- `XYCoupling(0.01, 0, 0, 0)` convenience ctor is strict same-type ->
  MethodError on mixed literals; spec path promotes correctly [p9].
- XYCoupling's (r1..r4, mode A/B) parametrization differs from
  Linear6DSpec R1/`_mR66` (both symplectic; no equivalence is claimed, but the
  adjacent naming invites confusion — max element difference 0.03 at r ~ 0.02).
- XYCoupling with 1 + r1r4 - r2r3 < 0 throws a bare sqrt DomainError with no
  element context.
- `_linear6d_matrix_from_optics` promotes T over beta/alpha/dmu but not
  zeta/eta/R (unreachable through the friendly ctor, which pre-converts).
