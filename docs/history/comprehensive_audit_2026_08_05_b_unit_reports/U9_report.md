# U9 report — lattice magnets, solenoid, linear maps (HEAD = 7de4d81)

## Region and provenance

| File | Lines | Depth |
|---|---|---|
| `src/elements/lattice_magnets.jl` | 1,324 | every line read |
| `src/elements/solenoid.jl` | 470 | every line read |
| `src/elements/linear6d.jl` | 316 | every line read |
| `src/elements/linear_maps.jl` | 279 | every line read |

Also read (context, not audited): `AGENTS.md` "Hard-Won Rules"; `docs/comprehensive_audit.md`
"Measured Lessons"; `git diff 6a3f39ab..HEAD` over the four files; the prior
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U10_report.md`;
`docs/theory/solenoid.md` §15; `docs/theory/lattice_hamiltonian_and_conventions.md`
§4.4/4.5/5/5.2/5.3/6; `src/knowledge/Knowledge.jl` lines 72–200 (schema/warning seam);
`src/contracts/Contracts.jl` 1904–2135 (`ElementParameterEffectivenessContract`).

**Executed**, not merely read. Probe scripts (session scratch, never the repository):
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`
— `p1_small_arg.jl`, `p1b_vers_seam.jl`, `p2_symplecticity.jl`, `p3_genericity.jl`,
`p4_f17_bitwise.jl`, `p5_targeted.jl`, `p6_more.jl`, `p7_final.jl`, `p8_minor.jl`,
`p9_perf.jl`, `p10_seam.jl`.

Environment: Julia 1.12.4. ForwardDiff is a test-only dep, so probes ran under a
stacked load path:

```
env JULIA_LOAD_PATH="/cfs/ad/dxu/Library/Julia/Octopus:<scratch>/audit:@stdlib" \
    julia --startup-file=no <probe>.jl
```

All Jacobians are **exact forward-mode AD** of the tracking kernel, not finite
differences, so there is no differencing noise floor: the only floor is roundoff
in the map itself. Residual = `max |Jᵀ S J − S|`, `S = blockdiag([0 1; −1 0]×3)`
in `(x, px, y, py, z, pz)`.

---

## LEADS

### LEAD U9-1 [Major, confidence high] src/elements/solenoid.jl:166 (`_SOL_MIDPOINT_ITERS`), 411 (`nst` default)
Claim: the curved solenoid's implicit-midpoint stage is solved by a fixed 16
fixed-point sweeps with **no convergence check**, and at the element's own default
`nst = 16` it silently returns a map with symplectic residual up to 7.2 — or NaN —
over a production-plausible `(L, ks)` range.

Mechanism: implicit midpoint is symplectic only when the implicit stage is solved
to convergence (the code says so at solenoid.jl:150–152). The stage is solved by
`_SOL_MIDPOINT_ITERS = 16` fixed-point sweeps of
`m ← u + (d/2)·f(m)`, `d = L/nst`. That iteration is a contraction only when
`q ≈ L·ks/(2·nst) < 1`; nothing in the code forms `q`, tests it, or reports the
residual of the solve. When it diverges the solenoid still returns numbers, and
they are plausible-looking. The source comment at solenoid.jl:148–166 asserts the
opposite universally — *"At 16 it sits on the finite-difference noise floor for
every step count, so a coarse `nst` gives a less accurate but still symplectic map
— which is the property a ring needs"* — from a sweep-count table measured at the
**single** point `L=1.3, ks=1.7, h=0.18` (`q = 0.069`). This is exactly Measured
Lesson 5: a pin quoted outside the regime it was measured in.

Measured at the default `nst = 16`, exact AD Jacobian:

| h | ks | L | q = L·ks/(2·nst) | \|JᵀSJ−S\| | x(nst=16) | x(nst=512) |
|---|---|---|---|---|---|---|
| 0.18 | 1.7 | 1.3 | 0.069 | 1.1e-16 | — | — |
| 0.1 | 1.7 | 5.0 | 0.266 | 1.77e-9 | 0.05086 | 0.05638 |
| 0.1 | 5.0 | 1.3 | 0.203 | 2.63e-11 | 0.0012818 | 0.0012994 |
| 0.1 | 5.0 | 5.0 | 0.781 | **0.730** | 0.006641 | 0.001400 |
| 0.1 | 20.0 | 1.3 | 0.813 | **7.197** | 8.50e-6 | 8.66e-4 |
| 0.1 | 20.0 | 5.0 | 3.125 | **NaN** | NaN | 0.0014595 |
| 0.5 | 5.0 | 5.0 | 0.781 | **1.482** | 0.03936 | 0.002053 |
| 0.5 | 20.0 | 1.3 | 0.813 | **7.369** | 0.002371 | 0.001189 |

The failure is a solve failure, not a structural one — raising `nst` recovers
(`h=0.1, ks=20, L=5`: nst=64 → 26.1, 128 → 9.71e-5, 256 → 8.22e-10, 512 → 8.51e-15)
— but the *default configuration* is unsafe and the failure is silent. `ks = 20 m⁻¹`
and `L = 5 m` is an ordinary detector/low-energy solenoid, not an exotic input.
Note the ParamMeta text tells users to vary `nst` ("Measure convergence for
production work rather than trusting the default"), which walks them straight
into the unguarded regime — and `nst = 1` is accepted with residual 9409 and a
tracked `x = −1.19` against a true `0.100`.

Fix direction (not applied): form `q = L·ks/(2·nst)` (plus the `h` contribution) at
`Solenoid(spec)` and throw or warn when it is not comfortably below 1; or iterate to
a tolerance with a residual report. A compile-time test costs nothing per particle
and keeps the kernel branch-free.

Repro:
```julia
# stacked env as above
using Octopus, ForwardDiff
S6 = let M=zeros(6,6); for b in (1,3,5); M[b,b+1]=1.0; M[b+1,b]=-1.0; end; M end
U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)
e = Solenoid(SolenoidSpec(L=5.0, ks=5.0, h=0.1))       # default nst = 16
J = ForwardDiff.jacobian(u -> collect(e(u...)), collect(U))
maximum(abs, J'*S6*J - S6)                              # -> 0.7300201785352702
Solenoid(SolenoidSpec(L=5.0, ks=20.0, h=0.1))(U...)     # -> all NaN, no warning
```
Full script: `p6_more.jl` section A, `p7_final.jl` section A.

---

### LEAD U9-2 [Medium, confidence high] src/elements/lattice_magnets.jl spec blocks (drift 1092–1100, quadrupole 1115–1138, sextupole 1153–1176, octupole 1191–1214, multipole 1229–1262, sbend 1277–1316)
Claim: the per-kind `parameters` declarations under-declare what `_lattice_magnet`
actually reads, and the unknown-parameter warning added since 6a3f39ab therefore
tells the user **"it is NOT being tracked"** about keys that change tracking by up
to 5.8e-2.

Mechanism: `_lattice_magnet` (lattice_magnets.jl:796–864) reads 26 keys for *every*
kind — `h`, `b0`, `kn`, `ks`, `bend_model`, `curved`, `curved_order`, `bend_fringe`,
`fringe`, `highest_fringe`, `wedge_coeff`, `e1`, `e2`, `fint1/2`, `hgap1/2`,
`hface1/2`, `va`, `vs`, `kill_ent/exi_fringe` — but each kind's schema declares only
its own subset. `_warn_unknown_spec_keys` (Knowledge.jl:92–105) compares the
constructor kwargs against that schema and emits *"unknown parameter(s) stored as
descriptive metadata only — if one is a typo of a physics parameter, it is NOT being
tracked."* For the keys below that sentence is false, and the comment immediately
above the function (Knowledge.jl:85–91) cites the very measurement that proves it
false (`e1 = 0.2` on a quadrupole, 7.7e-7). Loud, but wrong, is worse than silent.

Measured (exact `parameter_schema` diff against the read set):

| kind | read by `_lattice_magnet`, not declared |
|---|---|
| drift | `b0 kn ks bend_model curved_order bend_fringe fringe highest_fringe wedge_coeff e1 e2 fint1 fint2 hgap1 hgap2 hface1 hface2 va vs kill_ent_fringe kill_exi_fringe` (21) |
| quadrupole / sextupole / octupole / multipole | `h b0 bend_model curved curved_order bend_fringe wedge_coeff e1 e2 fint1 fint2 hgap1 hgap2 hface1 hface2` (15) |
| sbend | `va vs` (2) |

Which of them actually move the map (`QuadrupoleSpec(L=0.4, k1=1.4, nst=3)` baseline,
max coordinate change):

| key on a quadrupole | coordinate change |
|---|---|
| `h=0.15` | **5.79e-2** |
| `b0=0.05` | **1.93e-2** |
| `e1=0.2` | **7.20e-7** |
| `bend_fringe=false`, `fint1`, `hface1`, `bend_model`, `wedge_coeff`, `curved_order` | 0.0 (inert without a `b1`/`e1`) |

Two sharper cases:
* `SBendSpec(..., fringe=:soft_quad, va=0.05, vs=0.02)` — the sbend schema *advertises*
  `:soft_quad` through `_COMMON_PARAMS.fringe` but declares neither `va` nor `vs`.
  Coordinate change **5.64e-5**, with a warning saying they are metadata only.
* `MultipoleSpec(L=0.2, k0=0.05, k1=1.2)` gets `bend_fringe = true` by default (a
  **4.79e-7** effect from the Maxwell-required dipole fringe on a corrector); the only
  way to switch it off is `bend_fringe=false`, a key the multipole schema calls
  unknown and the warning calls inert.
* `DriftSpec(L=0.9, kn=(0.0, 1.4), nst=3)` tracks as a quadrupole (**1.58e-3**) while
  the warning says `kn` is not tracked.

Why nothing caught it: `ElementParameterEffectivenessContract` walks
`parameter_schema(T)` and checks **declared ⇒ consumed**. The reverse direction,
**consumed ⇒ declared**, has no tripwire — precisely the shape Measured Lesson 4
prescribes and the shape `_PLACEMENT_PARAMS` was introduced to fix for the placement
keys only (Knowledge.jl:182–191, "before this, the schemas under-declared what
`compile_runtime` reads"). The lattice-magnet-specific keys were left behind.

Fix direction (in-region half): declare the keys each kind's compile path reads (a
`_BODY_PARAMS`/`_FACE_PARAMS` splat mirroring `_PLACEMENT_PARAMS`), or give
`_lattice_magnet` a per-kind read mask. The warning's wording is a Knowledge.jl seam
— noted, not pursued.

Repro:
```julia
using Octopus
U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)
a = compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, nst=3))
b = compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, nst=3, h=0.15))   # warns "NOT being tracked"
maximum(abs, collect(a(U...)) .- collect(b(U...)))                  # -> 0.0579031914961
[k for k in (:h,:b0,:e1,:bend_fringe) if !(k in keys(parameter_schema(ElementSpec{:quadrupole})))]
# -> [:h, :b0, :e1, :bend_fringe]
```
Full script: `p6_more.jl` section B, `p7_final.jl` section B.

---

### LEAD U9-3 [Low, confidence high] src/elements/linear6d.jl:131–188 (`_linear6d_symplectic_error`, `_validate_linear6d_symplectic`)
Claim: the symplecticity validator orders on `T` rather than `real(T)`, so a
`Linear6D` with complex entries dies with `MethodError: isless(::ComplexF64, ::Float64)`
— the exact recurring bug the brief names, in the one function whose widening to
`T<:Number` (linear6d.jl:57–59) exists to admit exactly that type.

Mechanism: four ordered/real-only operations on the parameter type. `typemax(T)`
(lines 133, 152–153, 167), `max_ratio = zero(T)` with `ratio > max_ratio` (168–175),
`row_tolerance = T(64) * eps(T) * max(one(T), row_scale)` (165), and
`error.ratio <= one(T)` (183). Everything that *should* be real already is —
`abs(value - target)` and `abs(positive)+abs(negative)` return reals for Complex —
so the residual and the row scale are real and only the *thresholds* are wrongly
typed. `real(T)` throughout is the whole fix. ForwardDiff `Dual` passes (verified:
the Dual identity returns `(residual=Dual(0.0,0.0), tolerance=Dual(0.0,0.0), ratio=Dual(0.0,0.0))`),
so complex-step is the only broken axis — and it is the axis the `T<:Number`
comment advertises. This is U10-11 at 13c2733, unchanged at HEAD.

Negative control (the validator is otherwise sound): perturbing `M[1,1]` of the
identity by δ gives ratio 0.0 / 0.0 / 0.078 / 0.703 / 7.03 / 7036.9 at
δ = 1e-17 / 1e-16 / 1e-15 / 1e-14 / 1e-13 / 1e-10 and rejects from 1e-13 on; a
plausible-looking `M[1,1] = 1 + 1e-12` is rejected at ratio 70.4.

Repro:
```julia
using Octopus
Id = ntuple(k -> ((k-1) ÷ 6 == (k-1) % 6 ? 1.0 : 0.0), 36)
Octopus._linear6d_symplectic_error(ntuple(k -> complex(Id[k], 0.0), 36))
# -> MethodError: no method matching isless(::ComplexF64, ::Float64)
# same failure through the public path:
compile_runtime(Linear6DSpec{ComplexF64}(beta1=(3.1,2.2,40.0), dmu=(0.7+0im,1.3,0.02)))
```
Full script: `p3_genericity.jl` section (v), `p6_more.jl` section D.

---

### LEAD U9-4 [Low, confidence high] src/elements/lattice_magnets.jl:60–71 (`_curv_vers` crossover comment)
Claim: the comment records "the closed branch holds <= 5.9e-15 for u in [0.125, 0.5]";
the measured maximum is **7.11e-15**, at `u = 0.1255`.

Mechanism: documentation drift, not a code defect — the helper's own overall claim
("both sides now <= 1e-14, seam jump 6.0e-15") holds (measured seam jump 6.23e-15).
A recorded bound that is 20% optimistic is the kind of number a later session will
re-derive a tolerance from. Out of hypothesis (b) as a *defect*; in hypothesis (b) as
a measurement.

Repro (400-bit BigFloat, 400k-point scan of `[0.125, 0.5]`):
```julia
setprecision(BigFloat, 400)
maximum(abs(BigFloat(Octopus._curv_vers(u,1.0)) - (1-cos(BigFloat(u)))/BigFloat(u)) /
        abs((1-cos(BigFloat(u)))/BigFloat(u)) for u in range(0.125, 0.5; length=400001))
# -> 7.105583785257429e-15
```
Full script: `p1b_vers_seam.jl`, `p8_minor.jl` section D.

---

### LEAD U9-5 [Low, confidence high] src/elements/solenoid.jl:464 (`nst` ParamMeta)
Claim: the machine-readable `default=1` disagrees with the compile path's actual
default of 16 for a curved solenoid (solenoid.jl:411).

Mechanism: `ParamMeta.default` is not decoration — `ElementParameterEffectivenessContract`
reads it (`current = get(probe, key, pmeta.default ...)`, Contracts.jl:~2120) and
`element_help` prints it. The `meaning` text explains the split correctly; only the
machine-readable field is stale. Carried over from the U10 minor list, unchanged.

Repro:
```julia
parameter_schema(ElementSpec{:solenoid})[:nst].default   # -> 1
Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18)).nst        # -> 16
```

---

### LEAD U9-6 [Low, confidence high] src/elements/linear_maps.jl:25, 103, 195; src/elements/linear6d.jl:19, 213 — OUT OF HYPOTHESIS (type genericity, spec layer)
Claim: the default friendly constructors of the four linear-map kinds pin `Float64`
and convert with `T(...)`, so a `Dual` or `Complex` parameter dies with
`Float64(::Dual)` unless the caller spells `Spec{T}` — while every lattice magnet
promotes automatically through `numeric_type(spec)`.

Mechanism: `CrabDispersionSpec(; kwargs...) = CrabDispersionSpec{Float64}(; kwargs...)`
(and the three siblings) then `T(zeta1)` inside. The `{T}` escape hatch works
(verified: `d(x)/d(dmu1)` through `Linear6DSpec{Dual}` = 1.346e-4), so this is a
documented signature rather than a functional gap — but it is inconsistent with the
lattice magnets and it is the reason the `T<:Number` widening's stated purpose is
only half delivered. Separately, `_linear6d_matrix_from_optics` (linear6d.jl:213)
promotes `T` over `beta/alpha/dmu` but **not** `zeta/eta/R`; unreachable through the
friendly constructor (which pre-converts) but reachable through a raw `ElementSpec`.

Repro:
```julia
using Octopus, ForwardDiff
ForwardDiff.derivative(t -> compile_runtime(CrabDispersionSpec(zeta1=0.11+t))(U...)[1], 0.0)
# -> MethodError: no method matching Float64(::ForwardDiff.Dual{...})
ForwardDiff.derivative(t -> compile_runtime(CrabDispersionSpec{typeof(t)}(zeta1=0.11+t))(U...)[1], 0.0)
# -> 0.00065   (works)
compile_runtime(ElementSpec{:linear6d}(Dict{Symbol,Any}(:beta1=>(3.1,2.2,40.0), ...,
    :zeta1=>(ForwardDiff.Dual(0.01,1.0),0.0,0.0,0.0), ...)))
# -> MethodError: Float64(::Dual)   (the missing zeta/eta/R promotion)
```
Full script: `p3_genericity.jl` section (iv), `p10_seam.jl`.

---

### LEAD U9-7 [Low, confidence high] src/elements/linear_maps.jl:251–254 — OUT OF HYPOTHESIS (usability)
Claim: `XYCoupling(r1::T, r2::T, r3::T, r4::T) where {T<:Number}` is strict same-type,
so the natural `XYCoupling(0.01, 0, 0, 0)` is a `MethodError`.

Mechanism: same strict-signature class as the `_curv_sin`/`_sol_log_over_h` fixes,
one layer up. The spec path promotes correctly, so only the direct convenience
constructor is affected. Carried over from the U10 minor list, unchanged.

Repro: `XYCoupling(0.01, 0, 0, 0)` → `MethodError: no method matching XYCoupling(::Float64, ::Int64, ::Int64, ::Int64)`;
`XYCoupling(1//100, 0.0, 0.0, 0.0)` likewise. `compile_runtime(XYCouplingSpec(r1=0.01, r2=0, r3=0, r4=0))`
succeeds and yields `XYCoupling{Symplectic6DMap, Float64}`.

---

### LEAD U9-8 [Low, confidence med] src/elements/linear_maps.jl:263 — OUT OF HYPOTHESIS (error quality / device IR)
Claim: `g = inv(sqrt(1 + r1*r4 - r2*r3))` throws a bare `DomainError` with no element
context, from inside a per-particle tracking kernel.

Mechanism: the discriminant is a property of the *element*, fixed at
`compile_runtime`, but it is formed per particle inside `track_particle`, so an
invalid parameter set is discovered once per particle at track time rather than once
at build time, and the message names neither the element nor the coefficients. Per
AGENTS.md's device-IR rule a throw reachable from a CUDA kernel must compile as
device IR with a static message; this one is Base's `sqrt` domain check. Validating
the discriminant in the `XYCoupling` constructor (as `Linear6D` validates its matrix)
would move it to build time entirely.

Repro:
```julia
compile_runtime(XYCouplingSpec{Float64}(r1=2.0, r2=0.0, r3=0.0, r4=-1.0))(U...)
# -> DomainError with -1.0: sqrt was called with a negative real argument...
```

---

### LEAD U9-9 [Info, confidence high] src/elements/solenoid.jl:188–196 — OUT OF HYPOTHESIS (style)
Claim: `mz` in `_solenoid_curved_map` is assigned in every fixed-point sweep and
never read (`_sol_curved_deriv` takes no `z`, and `z'` does not depend on `z`).
Harmless stored-never-read; flagged in the U10 minor list and unchanged.

---

## Hypothesis (a) — SYMPLECTICITY: the sweep

124 element configurations, exact AD Jacobian, two amplitudes:
`U0 = (1.3e-3, 4.1e-4, −8.7e-4, −2.3e-4, 6.5e-4, 1.7e-3)` and
`U1 = (7.0e-3, 2.0e-3, −5.0e-3, 1.5e-3, 3.0e-3, 5.0e-3)`. Both are off the design
orbit, off-momentum, and off every symmetry plane, so the skew content and the curved
potential are live. Values are `max(residual(U0), residual(U1))`.

### A. Every multipole order, normal and skew, straight frame (`nst=3`, order 2)

| order | normal | skew |
|---|---|---|
| K0 | 8.0e-17 | 1.4e-17 |
| K1 | 2.2e-16 | 3.3e-16 |
| K2 | 4.4e-16 | 2.2e-16 |
| K3 | 2.2e-16 | 2.2e-16 |
| K4 | 2.2e-16 | 2.2e-16 |
| K5 | 2.2e-16 | 3.3e-16 |
| K6 | 2.2e-16 | 3.3e-19 |
| K7 | 3.3e-19 | 3.3e-19 |

### B. Curvature axis (`nst=3`, order 2, fringes off)

| case | residual |
|---|---|
| drift h=0 | 4.3e-19 |
| drift h=0.21 (curved) | 1.1e-16 |
| drift h=0.21, `curved=false` | 4.3e-19 |
| drift h=0, `curved=true` | 4.3e-19 |
| sbend h=b0=0.21 (design orbit) | 1.1e-16 |
| sbend h=0.21, b0=0.13 (h≠b0) | 8.3e-17 |
| sbend h=0.13, b0=0.21 (h≠b0, reversed) | 1.1e-16 |
| sbend h=0, b0=0.21 (straight-frame bend) | 4.2e-17 |
| sbend h=0.21, b0=0 (= curved drift) | 1.1e-16 |
| sbend h=b0=2.2, L=0.9 (\|hL\|>π/2, other branch) | 2.2e-16 |
| sbend h=0.21, b0=1e-8 (cancellation-free branch) | 2.2e-16 |

### B2. Curved frame × every multipole order (psi-table path, h=b0=0.21, nst=3)

| order | normal | skew |
|---|---|---|
| K0 | 8.9e-15 † | 2.2e-16 |
| K1 | 2.2e-16 | 4.4e-16 |
| K2 | 3.3e-16 | 2.2e-16 |
| K3 | 2.2e-16 | 3.3e-16 |
| K4 | 4.4e-16 | 5.6e-16 |
| K5 | 3.3e-16 | 4.4e-16 |
| K6 | 2.2e-16 | 2.2e-16 |

† conditioning, not a defect: the probe used `K0 = 1.1` over `L = 0.9` (≈1 rad of
extra deflection), for which `max|J| = 29.0`, so `eps·|J|² = 1.9e-13` and the
residual sits at 0.038 of the roundoff bound. Scan: K0 = 0.01 → 3.8e-17 (`|J|`=1.0),
0.1 → 5.6e-17, 0.5 → 3.3e-16, 1.1 → 7.1e-15 (`|J|`=29.0).

### C. Integrator order × nst (curved combined-function bend, k1=1.4, k2=8)

| nst | order 2 | order 4 |
|---|---|---|
| 1 | 2.2e-16 | 8.9e-16 |
| 2 | 3.3e-16 | 7.8e-16 |
| 4 | 3.3e-16 | 6.7e-16 |
| 8 | 7.8e-16 | 6.7e-16 |
| 16 | 8.9e-16 | 1.7e-15 |

`bend_model` × order × nst: `:exact` 2.2e-16 … 4.4e-16; `:drift_kick` 2.2e-16 …
1.1e-15. Convergence-order control (F, `p7_final.jl`): observed rates 2.01 / 2.00 /
2.00 for order 2 and 4.02 / 4.01 / 4.00 for order 4, against an nst=4096 reference —
so the Forest-Ruth composition is genuinely fourth order, not merely symplectic.

### D. Fringes on and off

| case | residual |
|---|---|
| quad k1,k1s × `fringe ∈ {none, multipole, soft_quad, all}` × `bend_fringe ∈ {false,true}` (8 cases) | 1.1e-16 … 5.6e-16 |
| sbend full faces (e1,e2,fint,hgap,hface,wedge) × 4 fringe modes | 2.2e-16 … 1.7e-15 |
| sbend full faces × `kill_ent × kill_exi` (4 cases) | 2.2e-16 … 1.4e-15 |
| `highest_fringe ∈ {0,1,2,3}` | 2.2e-16 … 8.9e-16 |
| `wedge_coeff ∈ {(1,2), (0,0), (0.7,1.3)}` | 3.3e-16 … 6.7e-16 |
| rbend, `fringe=:all` | 2.2e-16 |

### E. `curved_order` (psi truncation) — truncation must never cost symplecticity

| M | 1 | 2 | 3 | 4 | 8 | 12 |
|---|---|---|---|---|---|---|
| residual | 4.4e-16 | 4.4e-16 | 5.6e-16 | 3.3e-16 | 4.4e-16 | 4.4e-16 |

### F. Solenoid — straight

| case | residual |
|---|---|
| pure straight L=1.3 ks=1.7 | 2.2e-16 |
| ks=0 (= exact drift) | 8.7e-19 |
| straight + k1, Strang nst=4 | 5.0e-16 |
| straight + k1,k2,k1s,k2s, nst=8 | 6.7e-16 |
| h=0.18 `curved=false` | 2.2e-16 |
| h=0.18 `curved=false` + k0s (was U10-3 at 2.5e-3) | 4.4e-16 |

### F2. Solenoid — CURVED, implicit midpoint (h=0.18, ks=1.7, L=1.3)

**This is the one convergence floor in the region, and it falls with nst as the
brief predicts.** The last-sweep change in the midpoint state (i.e. the *solve*
residual) tracks it within an order of magnitude, which identifies the floor as the
unconverged implicit solve rather than the method:

| nst | last-sweep change of the midpoint state | \|JᵀSJ−S\| | tracked x |
|---|---|---|---|
| 1 | 6.28e-1 | 9.41e+3 | −1.1892 |
| 2 | 5.55e-6 | 1.01e-4 | 0.08988 |
| 3 | 1.11e-8 | 1.30e-7 | 0.09533 |
| 4 | 1.19e-10 | **1.078e-9** | 0.09739 |
| 6 | 1.85e-13 | 1.19e-12 | 0.09891 |
| 8 | 1.83e-15 | 9.30e-15 | 0.09946 |
| 12 | 0.0 | 2.2e-16 | 0.09985 |
| 16 | 0.0 | **1.110e-16** | 0.09998 |
| 24 | — | 2.4e-16 | — |
| 32 | — | 4.4e-16 | — |
| 64 | — | 7.8e-16 | — |

The two briefed anchors reproduce exactly: **1.078e-9 at nst=4** (recorded 1.1e-9)
and **1.110e-16 at nst=16** (recorded 1.1e-16); reference x at nst=256 is 0.100161.

Curved integrator run on a straight frame (`h=0, curved=true`, the direct validation
of the integrator against the exact map): nst=4 → 7.4e-10, 8 → 6.1e-15, 16 → 4.4e-16,
32 → 2.8e-16.

Curved + multipoles: `+k1` nst=4 → 1.09e-14, 16 → 5.6e-16, 32 → 9.1e-16;
`+k0s` (skew dipole, psi path) nst=4 → 9.5e-15, 16 → 4.6e-16, 32 → 5.6e-16;
`+k0` (normal dipole, closed kick) nst=4 → 7.1e-15, 16 → 3.3e-16, 32 → 6.7e-16.

**Every curved-solenoid residual falls monotonically with nst until it hits machine
epsilon. No residual in the region is nst-independent. There is no structural
symplecticity defect.** What U9-1 reports is a different thing: the *default* nst is
not large enough over part of the parameter space, and nothing says so.

### G. Linear maps

| case | residual |
|---|---|
| crab_dispersion (all four zeta) | 4.3e-19 |
| momentum_dispersion (all four eta) | 1.3e-18 |
| xy_coupling MODEA / MODEB | 2.2e-16 / 2.2e-16 |
| xy_coupling UNDEF (identity) | 0.0 |
| linear6d identity | 0.0 |
| linear6d from optics (β/α/dμ + ζ/η/R, all nonzero) | 2.2e-16 |

### Individual kernels, each alone

| map | residual |
|---|---|
| `_rot_xz(0.13)` | 2.8e-17 |
| `_wedge(−0.13, b1=0.21)` | 2.2e-16 |
| `_wedge(−0.13, b1=0)` → `_rot_xz` | 1.3e-20 |
| `_wedge_quad(0.13, 6.0, 1, 2)` | 0.0 |
| `_face(0.21, 0.11, 0.13, ±1)` | 0.0 / 0.0 |
| `_fringe_dipole_exact(fint=hgap=0)` | 1.5e-20 |
| `_fringe_dipole_exact(fint=0.5, hgap=0.03)` | 2.2e-16 |
| `_fringe_dipole_exact(exit, σ=−1)` | 4.1e-20 |
| `_multipole_fringe(N=6, σ=+1)` | 1.2e-20 |
| `_multipole_fringe(σ=−1, drop1)` | 3.5e-23 |
| `_multipole_fringe(hf=2)` | 2.2e-16 |
| `_soft_quad_fringe(±1)` | 2.2e-16 / 2.2e-16 |
| `_curved_kick(M=8)` | 0.0 |
| `_lattice_kick(h=0, six orders)` | 0.0 |
| `_lattice_kick(h=0.21, pure normal dipole)` | 0.0 |

### Negative controls (a sweep that cannot fail proves nothing)

`_lattice_kick` with `h ≠ 0` and content the Cauchy-Riemann exemption excludes
**must** be non-symplectic, and is — this is what `_needs_curved_potential` exists
to route away. At `h=0.21, L=0.9`, amplitude `(2e-2, 5e-3, −1.5e-2, 4e-3, …)`,
unit-normalized `K_n = 200`:

| content | `_needs_curved_potential` | \|JᵀSJ−S\| of the closed kick |
|---|---|---|
| K0 (normal dipole) | **false** | **0.0** |
| K0s | true | 37.8 |
| K1 / K1s | true | 0.567 / 0.756 |
| K2 / K2s | true | 1.13e-2 / 3.31e-3 |
| K3 / K3s | true | 9.21e-5 / 3.47e-5 |
| K4 / K4s | true | 3.31e-7 / 5.19e-7 |
| K5 / K5s | true | 2.33e-10 / 3.07e-9 |
| K6 / K6s | true | 8.45e-12 / 9.64e-12 |

Control: at `h = 0` every one of the 14 is an exact gradient (residual 0.0 for all).
So `_needs_curved_potential` is **exactly** the Cauchy-Riemann condition — false only
for the pure normal dipole, true for every order ≥1 and for the skew dipole, with a
measurable non-gradient behind every `true`. Total coverage, no hand-copied case list.

Second negative control: the `Linear6D` validator rejects a defective matrix
(δ=1e-13 on `M[1,1]` → ratio 7.03, rejected; `M[1,1]=1+1e-12` → ratio 70.4, rejected)
while accepting δ ≤ 1e-14 (ratio 0.703).

Third: `_solenoid_edge` used alone as a map gives residual **1.7 = ks** — correct and
expected, because the edge is the canonical→kinetic gauge change, not a canonical
transformation. (My initial probe mislabelled it; the composite `edge ∘ flow ∘ edge⁻¹`
is the canonical object and measures 1.1e-16.)

---

## Hypothesis (b) — cancellation-free arithmetic

Relative error vs **BigFloat at 400 bits**, at the briefed grid `h = 1e-1, 1e-4,
1e-8, 1e-12, 0` with `L = x = 1`:

| h | `_curv_sin` sin(hL)/h | `_curv_vers` (1−cos hL)/h | `_atan_over` atan(u)/u | `_sol_log_over_h` ln(1+hx)/h |
|---|---|---|---|---|
| 1e-1 | 2.47e-17 (closed) | 1.47e-17 (series) | 7.97e-17 (closed) | 2.79e-17 (closed) |
| 1e-4 | 8.33e-17 (closed) | 9.34e-17 (series) | 7.38e-17 (closed) | 1.70e-17 (series) |
| 1e-8 | 1.67e-17 (series) | 8.33e-18 (series) | 3.33e-17 (series) | 2.95e-18 (series) |
| 1e-12 | 1.67e-25 (series) | 8.33e-26 (series) | 3.33e-25 (series) | 4.45e-17 (series) |
| 0 | 0.0 (exact) | 0.0 (exact) | 0.0 (exact) | 0.0 (exact) |

Siblings on the same grid: `_sol_g` 5.9e-17 / 3.4e-17 / 5.9e-18 / 8.9e-17 / 0.0;
`_sol_gp` 6.3e-17 / 3.3e-17 / 1.4e-16 / 1.8e-16 / 0.0.

**Seam scan** — worst relative error on each side of each crossover, and the one-ulp
jump across it:

| helper | crossover | series side | closed side | seam jump |
|---|---|---|---|---|
| `_curv_sin` | 1e-4 | 5.54e-17 | 1.37e-16 | 1.11e-16 |
| `_curv_vers` | 0.125 | 1.65e-16 | **7.11e-15** | 6.23e-15 |
| `_atan_over` | 1e-4 | 5.55e-17 | 1.26e-16 | 1.11e-16 |
| `_sol_log_over_h` | 1e-2 | 6.07e-17 | 1.47e-16 | 1.12e-16 |

**The two recorded defects U10-5 and U10-6 are closed.** `_curv_vers` at
`u = 1.001e-4` was 5.86e-9 and is now 1.54e-17 (the series covers it); at the new
seam `u = 0.125` it is 6.09e-15, down from an 8-digit cliff. `_sol_log_over_h` at its
old seam was 2.5e-13 and is now 4.08e-17; across the new 1e-2 seam it is
5.57e-17 / 5.67e-17. The only residual observation is U9-4 (the recorded closed-side
bound is 5.9e-15, measured 7.11e-15).

Series correctness, checked by hand against the Taylor expansions:
`_curv_vers`'s nested form is `1 − u²/12 + u⁴/360 − u⁶/20160 + u⁸/1814400`, exactly
the expansion of `2sin²(u/2)/(u²/2)`, first omitted term `u¹⁰/239500800 = 3.9e-18` at
`u = 0.125` ✓. `_sol_log_over_h`'s is `1 − u/2 + u²/3 − u³/4 + u⁴/5 − u⁵/6 + u⁶/7 −
u⁷/8`, first omitted `u⁸/9 = 1.1e-17` at `u = 1e-2` ✓.

**Composite check** — `_lattice_drift(Val(true), h, 1.0)` against a 400-bit
evaluation of the same closed form, max absolute error over all six coordinates:
h = 1e-1 → 2.22e-16, 1e-4 → 7.91e-17, 1e-8 → 3.18e-17, 1e-12 → 1.79e-16, 0 → 4.63e-17.

**The two recorded 1/x cancellations are gone, measured, not assumed:**

* `_wedge`'s `Δ` (U10-7 recorded 2.8e-10 on z at b1=1e-8). Now, vs a 300-bit
  reference of the direct form: |Δz| error 6.9e-20 / 6.6e-21 / 5.9e-20 / 1.3e-20 /
  1.5e-20 / 2.9e-20 / 5.4e-21 / 6.3e-21 at b1 = 1, 1e-2, 1e-4, 1e-6, 1e-8, 1e-10,
  1e-12, 1e-14 — **flat in b1**, with symplectic residual 2.2e-16 at every b1. The
  b1→0 limit matches `_rot_xz` linearly (1.30e-10 / 1.30e-13 / 1.4e-16 at
  b1 = 1e-6 / 1e-9 / 1e-12) and **exactly** (0.0) at b1 = 0.
* `_lattice_bend`'s `1/b0`: agreement with the curved drift is linear in b0 down to
  the floor — 8.95e-4 / 8.95e-7 / 8.95e-10 / 8.95e-13 / 1.11e-16 / 1.39e-16 at
  b0 = 1e-3 / 1e-6 / 1e-9 / 1e-12 / 1e-16 / 0 — with residual ≤ 1.1e-16 throughout.
  Branch seam at |hL| = π/2 is continuous, difference linear in ε: 7.93e-6 / 7.93e-9 /
  7.92e-12 at ε = 1e-6 / 1e-9 / 1e-12.

---

## Hypothesis (c) — type genericity

24 element configurations spanning every kernel in the region, under three regimes.
**(iii) is the regime the brief calls out**: `ForwardDiff.derivative` w.r.t. one
coordinate at a time, so exactly one argument is a `Dual` and the other five are
`Float64` — the shape that made `_curv_sin(::T,::T)` a MethodError while a matched
6×6 Jacobian passed. All six single-coordinate derivatives were taken for each
element.

| element | (i) matched Duals (6×6 J) | (iii) UNMATCHED Duals | (ii) Complex (complex-step) |
|---|---|---|---|
| drift h=0 | ok | ok (6/6) | ok (6/6) |
| drift h=0.21 curved | ok | ok | ok |
| quad k1,k1s nst=3 | ok | ok | ok |
| quad fringe=:all | ok | ok | ok |
| sextupole k2 | ok | ok | ok |
| octupole k3 | ok | ok | ok |
| multipole k0..k5 + k1s | ok | ok | ok |
| sbend design orbit | ok | ok | ok |
| sbend h≠b0 | ok | ok | ok |
| sbend \|hL\|>π/2 | ok | ok | ok |
| sbend b0=1e-8 (`_atan_over` branch) | ok | ok | ok |
| sbend full faces fringe=:all order 4 | ok | ok | ok |
| sbend `:drift_kick` | ok | ok | ok |
| sbend curved psi table | ok | ok | ok |
| rbend fringe=:all | ok | ok | ok |
| **solenoid straight pure** | ok | ok | ok |
| **solenoid straight + k1 (Strang)** | ok | ok | ok |
| **solenoid CURVED pure nst=16** | ok | ok | ok |
| **solenoid CURVED + k0s psi nst=8** | ok | ok | ok |
| crab_dispersion | ok | ok | ok |
| momentum_dispersion | ok | ok | ok |
| xy_coupling MODEA / MODEB | ok | ok | ok |
| linear6d from optics | ok | ok | ok |

**24 × 3 = 72 regimes, zero failures.** The four bolded rows are the ones U10-1
recorded as MethodErrors at 13c2733; the F17 untyping of `_curv_sin`/`_curv_vers`
and the real-arithmetic solenoid body closed them.

Every remaining strict `(::T, ::T)` signature in the region was traced to its
callers and is reachable only with matched types: `_lattice_drift(::Val, h::T, L::T)`,
`_lattice_bend(h::T,b0::T,L::T)`, `_lattice_kick(::NTuple{N,T},::NTuple{N,T},h::T,L::T)`,
`_curved_kick(::NTuple{NC,T},::Val,L::T)`, `_multipole_fringe`, `_soft_quad_fringe`,
`_fringe_dipole_exact`, `_wedge`, `_rot_xz`, `_face`, `_wedge_quad`,
`_solenoid_curved_map(h::T,ks::T,L::T,…)` — each takes only element fields (all `T`)
and a step `d` derived from `elem.L`, never a coordinate. The one value-dispatched
shim `_lattice_drift(h::T, L::T, …)` (lattice_magnets.jl:118) has no production
caller (grep: `test/runtests.jl` only), so its strict pair is inert.

**(iv) Dual element parameters** (parameter derivatives through the spec path) —
18 of 18 lattice-magnet and solenoid parameters differentiate, including the two
U10-2 cases:

`d(px)/d(k1)` quad −5.175e-4; `d(px)/d(k1s)` −3.488e-4; `d(x)/d(L)` −3.410e-4;
`d(px)/d(k2)` sext −1.553e-7; `d(px)/d(k3)` oct 2.656e-11; `d(x)/d(h)` curved drift
0.42387; `d(x)/d(b0)` sbend −0.40772; `d(x)/d(h)` sbend 0.40786; `d(x)/d(e1)`
2.494e-4; `d(x)/d(fint1)` −1.141e-9; `d(x)/d(va)` 1.239e-6; `d(px)/d(k1)` curved psi
−9.648e-4; `d(x)/d(ks)` solenoid −6.583e-4; **`d(x)/d(k1)` solenoid −8.630e-4**;
**`d(x)/d(k1s)` solenoid −5.276e-5**; `d(x)/d(h)` curved solenoid 0.56350;
`d(x)/d(ks)` curved solenoid −5.445e-2; `d(x)/d(k0s)` curved solenoid psi 0.50477.

The four linear-map kinds need the `Spec{T}` spelling (LEAD U9-6).

**(v) Complex element parameters** (complex-step): 9 of 10 pass and agree with the
Dual values to ~1e-15 (`k1` quad −5.175332935041651e-4 vs Dual
−5.175332935041651e-4, identical). The one failure is `Linear6D` — LEAD U9-3.

---

## Hypothesis (d) — F17 bitwise verification

**(1) `curved = false` equals `h = 0` exactly.** 16 solenoid configurations
(`L, ks, h` ∈ {(1.3,1.7,0.18), (1.3,1.7,1e-3), (0.5,−0.9,2.5), (2.0,0.35,1e-300)} ×
{pure, +k1, +k0s, +k1/k2/k1s}) × 5 probe points including the origin and 1e-9
coordinates: **bitwise identical in all 6 coordinates, all 80 comparisons**. The
stored field is `h = 0.0` in every `curved=false` element, and the `CURVED` type
parameter is `false` on both sides. The same for 12 `LatticeMagnet` configurations
(drift / quad / combined k1,k2,k1s / skew dipole × h ∈ {0.21, 1e-3, 2.5}): bitwise
identical, stored `h = 0.0`, psi table length 0 on both sides. U10-3 (2.5e-3) and
U10-4 (1.6e-7) are both closed, and closed *exactly* rather than to a tolerance.

**(2) The straight solenoid body is bit-identical to its complex predecessor.**
The pre-F17 `_solenoid_map` was transcribed verbatim from 6a3f39ab (`cis`,
`complex(x,y)`, `W0*rot`) and compared against the real-arithmetic HEAD version:

* structured grid `ks ∈ {1.7, −1.7, 0.35, 0, 1e-8, 1e-14, 50}` × `L ∈ {1.3, 0.05,
  3.7, 0, 1e-6}` × 5 probe points = **175 comparisons, 0 bitwise mismatches**;
* random sweep, `ks ∈ [−10,10]`, `L ∈ [−4,4]`, Gaussian coordinates:
  **200,000 draws, 0 bitwise mismatches**;
* the full compiled element (pure, +k1 nst=4, +k1/k2/k1s nst=8) rebuilt around the
  complex body: **bitwise equal in all three**.

Total **200,175 bitwise comparisons, zero mismatches.** The transcription is exact
because Julia defines `Complex*Complex` as `Complex(ar*br − ai*bi, ar*bi + ai*br)`
and `Complex/Real`, `Complex*Real` componentwise — the code's `rr = hr*hr − hi*hi`,
`ri = hr*hi + hi*hr`, `br = (Px/ps)*C1` reproduce those operation orders exactly, and
`sincos(θ)` agrees with `cis(θ)` bit for bit. The PTC validation is therefore intact.

---

## Clean list (with the evidence that makes it checkable)

* **Symplecticity, whole region.** 124 configurations × 2 amplitudes, exact AD
  Jacobians: every one at 2e-16–9e-15 except the curved solenoid, whose residual falls
  monotonically with nst to 1.11e-16 by nst=16. Reproduces both briefed anchors
  (1.078e-9 at nst=4, 1.110e-16 at nst=16). No nst-independent residual anywhere.
* **`_needs_curved_potential` is exactly the Cauchy-Riemann condition**, verified by
  total enumeration of orders 0–6 normal and skew with a measured non-gradient behind
  every `true` and 0.0 behind the one `false`, plus an `h = 0` control where all 14
  are exact gradients. Derived, not hand-copied — no case list to drift.
* **Curved-frame potential.** Independently re-derived: the tabulated `Ψ` reproduces
  the midplane seeds `∂Ψ/∂x = −(1+hx)B_y(x,0)` and `∂Ψ/∂y = (1+hx)B_x(x,0)` to
  0.0–2.8e-17, and satisfies the Maxwell PDE `Ψ_xx + Ψ_yy − h/(1+hx)·Ψ_x = 0` to
  4.0e-16 at M = 8 and M = 12 (and 4.2e-8 at M = 4, the truncation — which costs
  accuracy and, as the sweep confirms, never symplecticity).
* **`_lattice_kick` normalization.** Exact (0.0 difference) against
  `dpx − i·dpy = −L(1+hx)Σ(K_n + iKs_n)(x+iy)ⁿ/n!` at six orders normal+skew,
  at `h = 0` and `h = 0.21`.
* **`_sol_curved_deriv` is Hamilton's equations** for `H = δ − (1+hx)p_s` with
  `P_x = p_x + ky`, `P_y = p_y − k·g(x)`, `g(x) = (2/h)ln(1+hx) − x` — derived
  independently from the Hamiltonian, term for term, and matching
  `docs/theory/solenoid.md` §15.2. `g' = 2/(1+hx) − 1` is consistent with the
  computed `g` to 0.0–4.4e-16 through AD across both the series and closed branches
  (18 (h,x) points), so the integrated field really is a gradient field.
* **Every individual fringe/geometry kernel is symplectic alone** (18 kernels,
  0.0–2.2e-16), which is stronger than the composite being symplectic.
* **Forest-Ruth coefficients.** `_FR_A = 1 − 2^(1/3)` exactly; `2(d1+d2) − 1 = 0.0`;
  `2k1 + k2 − 1 = 0.0`; third-order condition `2k1³ + k2³ = −8.9e-16`. Measured
  convergence rates against an nst=4096 reference: 2.01/2.00/2.00 (order 2) and
  4.02/4.01/4.00 (order 4).
* **Documented solenoid limits hold.** `ks = 0` ≡ exact drift to 4.93e-17;
  `ks = 0, k1` ≡ `QuadrupoleSpec` to 1.44e-17; the curved integrator's `h → 0` and
  `ks → 0` plateaus (1.41e-7 and 6.82e-7 at nst=64) are the O((L/nst)²) truncation
  the struct comment already records at 2.03e-6 for nst=16 — the ratio is 16×, i.e.
  exactly second order, so the comment's number is right and reproducible.
* **Placement parameters newly declared in these spec blocks are real.** `ref_tilt`,
  `tilt`, `x/y/z_offset`, `x/y_pitch` each move the quadrupole map (4.2e-4, 4.2e-4,
  5.4e-4, 5.8e-4, 7.0e-7, 6.4e-6, 6.8e-6) and the wrapped element stays symplectic
  (2.5e-17–4.4e-16); the same for solenoid, crab, momentum, xy_coupling, linear6d,
  drift (0.0–5.6e-16). The `_PLACEMENT_PARAMS` splat is connected, not decorative.
* **`Linear6D` validator arithmetic is correct** (each `MᵀJM` entry is the right
  three signed 2×2 determinants, row-major indexing consistent between
  `_matrix66_tuple`, `_mget` and `Base.Matrix`) and its magnitude-aware tolerance
  both accepts roundoff and rejects a 1e-12 defect. Only its *type* is wrong (U9-3).
* **`_mzeta66`/`_meta66`/`_mR66` and the `CrabDispersion`/`MomentumDispersion`/
  `XYCoupling` kernels** are symplectic to 4.3e-19–2.2e-16, both XY modes, and the
  optics-built 6×6 with all of ζ/η/R nonzero is symplectic to 2.2e-16.

## A refuted hypothesis of my own (recorded per Guiding Principle 14)

I suspected a performance defect: `XYCoupling.track_particle` recomputes
`g = inv(sqrt(1 + r1r4 − r2r3))` from element fields for **every particle**, where
`Linear6D` folds its equivalent at compile time. Measured with a tight type-stable
loop (50M iterations, best of 5): `XYCoupling` 4.05 ns/particle vs `CrabDispersion`
2.36 and `MomentumDispersion` 2.40. But the **negative control** — the identical map
with `g` precomputed and stored in the struct — measures **4.08 ns/particle**, i.e.
no faster. The `sqrt` is loop-invariant and LLVM hoists it; the 1.7 ns gap is the
map's extra 8 multiplies, not the square root. **No performance lead.** (The
structural point about `sqrt` domain validation belonging at build time survives as
LEAD U9-8, on error-quality grounds only.)

## Not checked, and why

* **GPU/device-IR compilation** of any kernel in the region. No CUDA device was
  exercised in this session; the region contains throws reachable from device code
  (`sqrt` domain checks) that a device gate would compile. Priced as: one
  `ElementTrackingBackendConsistencyContract` run on a GPU box.
* **PTC numerical agreement.** The region's PTC pins live in
  `src/contracts/Contracts.jl` and `validation/`, outside my region. I verified only
  that F17's real-arithmetic transcription is bitwise identical to the complex body
  the PTC comparison was validated against (200,175 comparisons), which preserves any
  PTC result rather than re-establishing it.
* **The misalignment/design-roll wrap itself** (`src/elements/misalignment.jl`).
  In-region I checked only that the newly declared placement keys are consumed and
  that the wrapped elements stay symplectic. **Seam noted, not pursued.**
* **The unknown-parameter warning's wording** (`Knowledge.jl:92–105`). The
  under-declaration half of U9-2 is in my region; the message half is not.
  **Seam noted, not pursued.**
* **`bend_model = :drift_kick` PTC MODEL=1 equivalence** at finite nst — checked for
  symplecticity and genericity only, not against PTC.
* **The full test suite.** Not run: this is a reading unit, and the suite gate belongs
  to the orchestrator.
