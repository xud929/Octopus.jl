# U12 report — RF/patch/boost/tilt/chromaticity elements + tracking kernel

Commit audited: e0f6bda072c4a4355f7698e8494d087550ab4a71 (matches assignment baseline e0f6bda).

## Coverage

Every line read:
- src/elements/rf_cavity.jl 1-223, patch.jl 1-209, chromaticity_kick.jl 1-192,
  crab_cavity.jl 1-181, lorentz_boost.jl 1-163, ref_tilt.jl 1-126, Elements.jl 1-15
- src/track/phase6d_track.jl 1-359, longitudinal.jl 1-232, fused_track.jl 1-77,
  radiation_track.jl 1-67, Track.jl 1-64
- Theory notes: rf_cavity_and_reference_energy.md (all sections, §4/§5/§8 in detail),
  lattice_hamiltonian_and_conventions.md §2 (full), misalignment_and_patch_maps.md (patch sections)
- Supporting reads (not in scope, for cross-checks): linear_maps.jl (CrabDispersion /
  MomentumDispersion / XYCoupling forward maps), lattice_magnets.jl:75-102 (_lattice_drift),
  misalignment.jl:48-88 (_misalign_matrix, _frame_change), radiation.jl (ctx RNG path).

Probes (all in scratchpad/U12/, run `julia --startup-file=no --project=. <script>` with the
ForwardDiff JULIA_LOAD_PATH env): probe_longitudinal.jl, probe_rf_cavity.jl,
probe_rf_slip.jl, probe_crab_patch.jl, probe_boost_chroma_tilt.jl, probe_fused_perf.jl,
probe_edges.jl. All CPU, each < 30 s.

## Leads

### U12-1 — rf_cavity.jl:81-85 — cavity phase computed from -l, not -c*dt: velocity slip (-1/gamma0^2) absent from synchrotron dynamics — MAJOR (moderate-energy hadron rings)

`_rf_kick` calls `convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, pz)` **without
the `s` keyword**. Per the conversion table (lattice_hamiltonian_and_conventions.md §2,
implemented at longitudinal.jl:179), `z1 = (z + s*(beta/beta0 - 1))/beta`; with `s = 0`
the cavity sees `z/beta`, which is the PTC `TIME=FALSE` "-l" variable — the exact trap the
note flags ("PTC's TIME=FALSE variable is -l, not s-l ... the offset has to be pinned").
The `s(beta/beta0-1)` term is not a relabeling: it is delta-dependent and is precisely the
velocity part of the slip factor. Dropping it makes the model's slip factor
`eta = alpha_c` instead of `eta = alpha_c - 1/gamma0^2`.

Numbers (probe_rf_slip.jl; proton E0 = 2.5 GeV total, beta0 = 0.92690, gamma0 = 2.66447,
1/gamma0^2 = 0.140857; ring C = 1000 m, alpha_c = 0.2, h = 5, V = 6 MV, phi_s = 0):
- tracked nu_s = 0.0211009
- analytic nu_s with eta = alpha_c: 0.0210855 — ratio tracked/analytic = **1.00073** (match)
- analytic nu_s with true eta = 0.0591433: 0.0114662 — ratio = **1.84027** (fails)
- d(phase)/d(delta) at the cavity: s=0 gives 0.0; s=C gives 4.42514, and
  (difference)/(k*C/(beta0*gamma0^2)) = 1.0000000000000022 — the missing term is exactly
  the conversion's s-term, so the seam already carries the fix.
Consequences: order-unity nu_s error whenever 1/gamma0^2 is comparable to alpha_c; for
alpha_c < 1/gamma0^2 (below transition) the model places the stable phase on the wrong
side of the bucket. Negligible for e- (1/gamma0^2 ~ 2.6e-9 at 10 GeV) and high-energy p
(1.2e-5 at 275 GeV). Note §8 validation item 4 (nu_s against the eta formula) is exactly
the check that fails; it is listed in the note as not yet performed. A fix needs the
cavity to receive arc position + accumulated turn path (TrackingContext.turn exists), or a
documented statement that Scope A is the PTC TIME=FALSE approximation.

Repro: scratchpad/U12/probe_rf_slip.jl

### U12-2 — rf_cavity.jl:141,215,222 vs :83 — docstring says phase argument is `k*z + phase` "exactly as ThinCrabCavity"; code uses `k*z1 = k*z/beta_particle` — MINOR (doc/convention drift)

The spec docstring ("the argument is `k*z + phase`, additive"), the `phase` ParamMeta
("entering as the additive `k*z + phase` exactly as ThinCrabCavity does") and
construction_help ("matching ThinCrabCavity so that `phase` means one thing across every
RF element") all state the tracking coordinate `z`. The body computes `k*z1 + phase` with
`z1 = z/beta_particle` (s = 0). ThinCrabCavity (crab_cavity.jl:110) genuinely uses the
tracking `z`. At beta < 1 the two elements' `phase` therefore do NOT mean one thing:
measured `k*z1 - k*z = 4.617e-3 rad` at 2.5 GeV proton, z = 7 mm, delta = 2.3e-3
(probe_rf_cavity.jl). The cavity body is the physically defensible one (note §5); the
docstrings and the cross-element consistency claim are what drift.

Repro: scratchpad/U12/probe_rf_cavity.jl (phase-arg line)

### U12-3 — rf_cavity.jl:160-168 — `voltage` + explicit `beta0`/`gamma0` silently discards the user's values — MINOR (error path)

`ThinRFCavitySpec(f; voltage, e0, mc2, beta0=0.5, gamma0=1.2)` is accepted and stores
beta0 = 0.9268998207958971, gamma0 = 2.664472308367128 (derived from e0/mc2), discarding
the explicit 0.5/1.2 without error — inconsistent with the same constructor throwing for
`voltage` + `strength` ("not both", line 165).

Repro: scratchpad/U12/probe_edges.jl (1)

### U12-4 — patch.jl:168 — `Patch(spec::ElementSpec, ...)` unconstrained on spec kind; wrong-kind spec silently builds an identity patch — MINOR (strict signature)

Every sibling runtime constructor constrains the kind (`ThinRFCavity(::ElementSpec{:thin_rf_cavity})`,
`CrabDispersion(::ElementSpec{:crab_dispersion})`, ...). `Patch` takes any `ElementSpec`;
`Patch(ElementSpec{:drift}(L=1.0))` constructs and is the exact identity map (all
`getparam` defaults 0), verified bitwise.

Repro: scratchpad/U12/probe_crab_patch.jl (last block)

### U12-5 — chromaticity_kick.jl:69 — `promote_type` without `float`: integer params via the flexible spec form throw a raw MethodError — MINOR (error path)

`T = promote_type(map(typeof, (xi..., beta..., alpha...))...)` gives `T = Int64` for
`ElementSpec{:chromaticity_kick}` built with integer tuples; `gamx = (one(T)+alfx^2)/betx`
is then Float64 while the other T-slot args stay Int64, so the default struct constructor
fails: `MethodError: no method matching ChromaticityKick(::Symplectic6DMap, ::Int64, ...,
::Float64, ..., ::CrabDispersion{Symplectic6DMap, Int64}, ...)`. The friendly constructor
is unaffected (converts to Float64), but the flexible form advertised by
construction_help's pattern elsewhere hits this.

Repro: scratchpad/U12/probe_edges.jl (3)

### Measured, hypothesis REFUTED — patch.jl:101-103 per-particle rotation recompute (inherited perf hypothesis 4)

`_patch_map` calls `_patch_rotation` (3x sincos + two 3x3 multiplies) per particle per
turn. Measured against a variant with W hoisted out of the loop (probe_fused_perf.jl,
1e7 iterations, Float64, this host): as-is 11.059 ns/particle, hoisted 11.057 ns/particle,
ratio 1.0002. The computation is pure and loop-invariant, and LLVM hoists it out of the
particle loop; there is no measurable cost. Not a lead; do not "fix".

### Cross-file observations (outside assignment, discovered via probes; for the relevant auditor)

- linear_maps.jl:47 and :115 — `CrabDispersion{T}(z1..z4)` / `MomentumDispersion{T}(e1..e4)`
  convenience constructors are unreachable: `CrabDispersion{Float64}` throws
  `TypeError: in M, expected M<:AbstractTrackingMethod, got Type{Float64}` at type
  application, before dispatch. Dead API.
- lorentz_boost.jl:114-115 — `inverse_boost` is defined, unexported, and referenced
  nowhere else in src/test/examples (dead helper; it does round-trip correctly).
- radiation_track.jl:33-54 — the contextless CUDA `LumpedRad` path draws noise from
  `CUDA.default_rng()` (stateful), unlike the ctx path which uses the pure counter RNG
  `octopus_normal(seed, method, turn, rng_id, particle_id, component)` (radiation.jl:233-238).
  It is explicitly the compatibility launch (`:cuda_radiation_compatibility_launch`) and
  only reachable without a TrackingContext; not runnable here (no GPU) — inspection only.

## Sound (invariants verified, with how)

1. **longitudinal.jl conversion seam** (probe_longitudinal.jl): all 12 directed round
   trips A->B->A at s = 47.3 exact to <= 3.9e-17 at proton 2.5 GeV, proton 275 GeV,
   electron 10 GeV; every coordinate/momentum matched hand-built values from the note's
   definitions (z1=-c dt, z2=beta0 z1, z3=z1 beta - s(beta/beta0-1), z4=beta z1) to 0.0;
   `ddelta/dpt - 1/beta = 0.0` by ForwardDiff at all three energies; longitudinal 2x2
   Jacobian det - 1 = 0.0; A->A returns the identical objects; `particle_beta` agrees
   with (1+delta)/(1/beta0+pt) to < 1e-14 in all four conventions. The `1/beta` vs
   `beta` placement is correct everywhere; #2 uses beta0, #3/#4 use particle beta.
2. **RF cavity map** (probe_rf_cavity.jl): strength=0 is the bitwise identity (the
   documented guard); synchronous particle (phase=0, origin) residual <= 1.1e-16 (the
   documented ~4e-16 conversion round-trip, not a defect); kick equals the hand-built
   TIME_ENERGY sandwich bit-for-bit (dpz = dz = 0.0); finite-kick dpz*beta/dpt = 1 to
   2.5e-5 (proton, second order in strength) and 3e-12 (electron); transverse coordinates
   bitwise untouched; |J'SJ-S| <= 3.4e-16 for L=0 and L=2 at both energies (symplectic to
   1e-14 target met); L->0 vs L=0 agree to 2.1e-16; nu_s(4V)/nu_s(V) = 2.0044 (sqrt(V)
   law); `rf_strength` = qV/(beta0 E0) = qV/(P0 c) as documented; the body genuinely has
   no beta factor; the L!=0 case uses the exact drift (`_lattice_drift(Val(false),...)`),
   not a paraxial one.
3. **Crab cavity** (probe_crab_patch.jl): 2-harmonic, both planes: |J'SJ-S| = 0.0;
   conjugate-kick relation d(dpx)/dz = d(dpz)/dx and d(dpy)/dz = d(dpz)/dy hold to 0.0
   (the kick is the exact gradient of (sx x + sy y) sin(i kcc z + phi)/(i kcc)); x,y,z
   bitwise fixed; docstring map matches code term for term; harmonic tuple length
   validated; frequency validated finite+nonzero in all three constructors.
4. **Patch** (probe_crab_patch.jl): |J'SJ-S| <= 1.2e-16 with all seven parameters nonzero,
   both :bmad and :madx composition orders (the symplecticity claim of the docstring,
   despite the NonSymplectic6DMap tag, which the docstring explains as a kernel-family
   name); translation-patch o negated-translation = identity to 1.8e-17; each single-axis
   rotation o negated rotation = identity to 2.2e-19; t_offset inverse exact; a pure-dz
   patch reproduces the exact drift bitwise including the z accounting (ref - path), so
   `_patch_reference_length` is consistent with the drift-to-face step; rotation delegated
   to `_misalign_matrix` (PTC-pinned) with the documented axis mapping and sign flip.
5. **Lorentz boost** (probe_boost_chroma_tilt.jl): Rev(Fwd(u)) and Fwd(Rev(u)) = identity
   to 1.6e-18 at angle 12.5 mrad; det J(fwd) - sec^3 = 0.0 and det J(rev) - cos^3 = 0.0,
   exactly the quasi-symplectic claim in both docstrings; inverse_boost involution holds.
6. **Chromaticity kick** (probe_boost_chroma_tilt.jl): full map with xi, beta, alpha,
   zeta, eta, R all nonzero: |J'SJ-S| <= 5.6e-16; plain map 1.1e-16; x-plane rotation
   equals the Twiss rotation with mu = 2 pi xi pz to 0.0; z shift equals
   +2 pi (xi_x Jx + xi_y Jy) with J the Courant-Snyder actions to 4.2e-19 (the conjugate
   term that completes the 6D symplectic map, sign verified by the symplecticity check);
   each conjugation sub-map inverse is exact (zeta 0.0, eta 1.1e-19, R 2.2e-19), verified
   against the forward maps in linear_maps.jl including the XY mode-A normalization g.
   Every declared parameter is read (xi, beta, alpha, zeta, eta, R, tracking_method);
   beta/alpha accept 2- or 3-tuples and use exactly the transverse pair.
7. **ref_tilt** (probe_boost_chroma_tilt.jl): SBend(angle=0.1, L=2, ref_tilt=pi/2) maps
   dispersion into y exactly: y-displacement equals the untilted bend's x-displacement
   bit-for-bit (difference 0.0), x residual 6.1e-21, z bitwise equal — the vertical-bend
   claim of the header comment; ref_tilt = 0 returns the inner element untouched (no
   wrapper); the entrance/exit rotations use `_misalign_matrix`'s W[1], W[4] as documented
   (R_z row-major layout verified against misalignment.jl:53).
8. **fused/unfused and kernel interface** (probe_fused_perf.jl): fusedTrack over a flat
   tuple, a nested tuple, and the ctx form all return the bitwise-identical result of
   calling the elements sequentially (`===` on the tuple); `track!` CPU path (public
   keyword form, which always runs the context kernel) is bitwise identical too; the
   default `(op)(ctx, particle_id, coords...)` pass-through (Track.jl:59) forwards
   non-stochastic elements unchanged; `_reject_contextless_tracking` guards only the
   internal contextless CPU path, and its rationale comment matches the code;
   `with_turn` accumulates `ctx.turn + (turn-1)` consistently on CPU and CUDA kernels.
9. **Elements.jl**: pure include list; order satisfies every cross-file dependency used
   here (lattice_magnets before rf_cavity for `_lattice_drift`; misalignment before
   patch/ref_tilt for `_misalign_matrix`; linear_maps before chromaticity_kick).
10. **Unknown-keyword acceptance** (probe_edges.jl (2)): `PatchSpec(angle_z=0.02)` (typo
    for angle_s) is accepted and produces the identity patch — same repo-wide `_spec_params`
    metadata mechanism already reported as U3-10; these friendly constructors add no
    validation of their own. Recorded here as confirmation in this file set, not a new lead.
