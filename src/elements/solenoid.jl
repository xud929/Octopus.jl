export SolenoidSpec, Solenoid

# ---------------------------------------------------------------------------
# Solenoid.
#
# Derivation: `docs/theory/solenoid.md`. Conventions (Hamiltonian, the z = s - l
# longitudinal pair, the q/P0 normalization): `lattice_hamiltonian_and_conventions.md`.
#
# The one fact that shapes everything here: a solenoid's field is longitudinal,
# so its vector potential is *transverse*, so inside the magnet the stored
# canonical `px`/`py` are not the particle's transverse momenta. Every other
# element in Octopus has a_x = a_y = 0 and has never had to distinguish them.
# ---------------------------------------------------------------------------

"""
    Solenoid{M,T}

Exact solenoid map, hard edge, straight frame.

`ks` is the normalized strength `q B_s / P_0 = B_s / (B*rho)`, the same quantity
MAD-X calls `KS`.

**Exact, not the paraxial matrix.** The textbook solenoid matrix is the
`p_s -> 1` limit: it drops the chromatic and amplitude dependence of the
focusing, and -- the reason it is rejected here rather than reused -- it does not
reduce to Octopus's exact drift at `ks = 0`, so a switched-off solenoid would
disagree with the same lattice with the solenoid removed. This map reduces to
`_lattice_drift(h=0)` to roundoff.

No `nst` and no integrator order: the map is the exact flow, so subdividing it
would add error rather than remove it.
"""
# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
struct Solenoid{M<:AbstractTrackingMethod,T<:Number,N,CURVED} <: AbstractTrackOp
    method::M
    L::T
    ks::T
    # Reference-frame curvature. `h == 0` selects the exact closed-form map and
    # anything else the implicit-midpoint integrator.
    #
    # The comparison is exact rather than tolerant, deliberately. It is stable:
    # IEEE equality is deterministic and `-0.0 == 0.0`, so both signed zeros take
    # the straight path. A tolerance would be worse -- it would silently discard
    # curvature a caller explicitly asked for, and any epsilon would be arbitrary.
    #
    # What it does create, and what `_lattice_drift` does NOT, is a cliff in
    # *accuracy*: both of the drift's branches are exact, while these two differ
    # in kind. Measured at L=1.3, ks=1.7 against the exact straight map:
    #
    #     h = 0.0, -0.0        exact path     0.0
    #     h = 1e-300 .. 1e-8   curved path    2.03e-6   (integrator truncation)
    #
    # So h = 1/rho with a very large rho pays integration error it does not need.
    # The curved path is numerically safe there -- no 1/h exists anywhere, and
    # nothing blows up down to 1e-300 -- it is simply approximate where the exact
    # map would be exact. Pass exactly 0 when the frame is straight, which is the
    # default.
    h::T
    kn::NTuple{N,T}          # kn[i] = K_{i-1}, normal, THICK (not integrated)
    ksk::NTuple{N,T}         # skew partners
    nst::Int
end

"""
    _sol_log_over_h(h, x)

`ln(1+hx)/h`, smooth at `h = 0` where it is the removable limit `x`.

Same removable-singularity problem the curvature helpers solve, and handled the
same way: the closed form loses digits to cancellation near `h = 0`, so small
arguments take a series instead.
"""
@inline function _sol_log_over_h(h::T, x::T) where {T}
    u = h * x
    # `real(T)`: element parameters may be dual or complex now, and a complex
    # crossover threshold does not order. Same rule as the curvature helpers.
    abs(u) < real(T)(1e-4) && return x * (one(T) - u / 2 * (one(T) - 2u / 3))
    return log1p(u) / h
end

"""
    _sol_g(h, x), _sol_gp(h, x)

The curved-frame gauge function `g(x) = 2 ln(1+hx)/h - x` and its derivative
`g'(x) = 2/(1+hx) - 1`, from `docs/theory/solenoid.md` Section 15.1.

Chosen so that `g(x) -> x` as `h -> 0`, which makes the potential reduce to the
straight symmetric gauge and therefore makes the curved element's flat limit the
*same* map as the exact straight one -- not merely a numerically close one.
"""
@inline _sol_g(h::T, x) where {T} = 2 * _sol_log_over_h(h, x) - x
@inline _sol_gp(h::T, x) where {T} = 2 / (one(T) + h * x) - one(T)

"""
Right-hand side of the curved-frame solenoid equations of motion, Section 15.2.

`p_s` is **not** conserved here -- the frame rotation feeds `P_x` into it -- which
is exactly why the straight map's closed form does not survive `h != 0`.
"""
@inline function _sol_curved_deriv(h::T, ks::T, x, px, y, py, pz) where {T}
    k = ks / 2
    Px = px + k * y
    Py = py - k * _sol_g(h, x)
    ps = sqrt((1 + pz)^2 - Px * Px - Py * Py)
    hx = one(T) + h * x
    gp = _sol_gp(h, x)
    return (hx * Px / ps,                       # x'
            h * ps + hx * k * gp * Py / ps,     # px'
            hx * Py / ps,                       # y'
            -hx * k * Px / ps,                  # py'
            one(T) - hx * (1 + pz) / ps,        # z'
            zero(T))                            # pz'
end

# Fixed-point sweeps for the implicit stage.
#
# This count is what makes the integrator symplectic, and it is not a tuning
# knob. Implicit midpoint is symplectic only when the implicit stage is solved
# to convergence; a truncated solve is merely a convergent explicit method
# wearing its name. Measured |M'JM - J| against the sweep count, L=1.3, ks=1.7,
# h=0.18:
#
#     sweeps    nst=4      nst=16     nst=64
#     4         4.2e-3     4.5e-6     4.3e-9
#     8         2.6e-5     5.1e-10    4.9e-10
#     16        1.4e-9     3.0e-10    5.2e-10
#
# At 4 and 8 sweeps the symplectic error tracks the *truncation* error, i.e. it
# is the unconverged solve rather than the method. At 16 it sits on the
# finite-difference noise floor for every step count, so a coarse `nst` gives a
# less accurate but still symplectic map -- which is the property a ring needs.
# A fixed count also keeps the kernel branch-free for the GPU.
const _SOL_MIDPOINT_ITERS = 16

"""
Curved-frame solenoid by the **implicit midpoint rule**.

A general symplectic integrator is required rather than a splitting one, because
`H` does not separate into two exactly-solvable pieces: a solenoid's potential is
transverse, so it lives inside the square root and no gauge moves it out. See
Section 15.3 -- composing the exact curved drift with the exact straight solenoid
converges to the *wrong* Hamiltonian, not merely slowly, so that tempting
shortcut is wrong rather than inaccurate.

Implicit midpoint is symplectic for any Hamiltonian, second order, and
time-reversible. The price is the fixed-point solve, several derivative
evaluations per step where a split integrator needs one. That cost is what
curvature costs here.
"""
@inline function _solenoid_curved_map(h::T, ks::T, L::T, nst::Int,
                                      x, px, y, py, z, pz) where {T}
    d = L / nst
    @inbounds for _ in 1:nst
        # Fixed-point iterate the midpoint state, starting from the current one.
        mx, mpx, my, mpy, mz = x, px, y, py, z
        for _ in 1:_SOL_MIDPOINT_ITERS
            fx, fpx, fy, fpy, fz, _ = _sol_curved_deriv(h, ks, mx, mpx, my, mpy, pz)
            mx = x + d / 2 * fx
            mpx = px + d / 2 * fpx
            my = y + d / 2 * fy
            mpy = py + d / 2 * fpy
            mz = z + d / 2 * fz
        end
        fx, fpx, fy, fpy, fz, _ = _sol_curved_deriv(h, ks, mx, mpx, my, mpy, pz)
        x += d * fx
        px += d * fpx
        y += d * fy
        py += d * fpy
        z += d * fz
    end
    return x, px, y, py, z, pz
end

"""
    _solenoid_edge(k, x, y, px, py) -> (Px, Py)

Canonical -> kinetic transverse momentum at a hard edge, with `k = ks/2`.

**This is the fringe field.** Not a model added on top of the body map: the
hard-edge vector potential `a_x = -k y`, `a_y = +k x` jumps at the face, and the
kinetic momentum `P = p - a` jumps with it while the canonical `p` stays
continuous (its derivative is bounded, so it cannot jump). Integrating the
radial fringe field `B_r = -(r/2) dB_s/ds` through an infinitely short edge
gives the same expression; the canonical route just cannot get the two faces
inconsistent with each other.

The exit uses the same function with `-k`, evaluated at the **exit** `x, y`.
"""
@inline _solenoid_edge(k, x, y, px, py) = (px + k * y, py - k * x)

"""
Exact solenoid body: rotate the kinetic momentum, advance along the Larmor
half-angle, advance `z` as a drift of the same `p_s`.

`p_s` is a constant of the motion (a static magnetic field does no work), which
is what makes this closed-form rather than an expansion.
"""
@inline function _solenoid_map(ks::T, L::T, x, px, y, py, z, pz) where {T}
    k = ks / 2
    # Entrance edge. p_s MUST be formed from the kinetic momenta, after this
    # conversion -- forming it from the incoming canonical ones is the single
    # most likely error here, and it is invisible at small amplitude because the
    # two agree to first order in k.
    Px, Py = _solenoid_edge(k, x, y, px, py)
    ps = sqrt((1 + pz)^2 - Px * Px - Py * Py)
    kappa = ks / ps
    # Momentum rotates by -kappa*L; the displacement runs along the *half*
    # angle. That half is the Larmor angle and is the factor-of-two check.
    half = cis(-kappa * L / 2)
    rot = half * half
    W0 = complex(Px, Py)
    # 2 sin(kappa L / 2) / kappa is sin(uL)/u at u = kappa/2, so the existing
    # small-argument-safe helper is the same function and is reused rather than
    # a second series written.
    w = complex(x, y) + (W0 / ps) * _curv_sin(kappa / 2, L) * half
    W = W0 * rot
    xn, yn = real(w), imag(w)
    # Exit edge, at the new position.
    pxn, pyn = _solenoid_edge(-k, xn, yn, real(W), imag(W))
    # p_s is constant, so the longitudinal advance is the drift's, term for term.
    return xn, pxn, yn, pyn, z + L * (1 - (1 + pz) / ps), pz
end

# Pure solenoid, N == 0. Straight frame takes the exact closed form; a curved
# frame has none (Section 15.3) and uses the implicit-midpoint integrator.
#
# The choice is a TYPE parameter, not a field test. `h` is a runtime value, so
# `elem.h == 0` could not be constant-folded: every kernel compiled both paths,
# including the 16-sweep integrator loop, and paid a branch per particle for a
# question that is settled once when the lattice is built. Deciding it at
# `compile_runtime` means a straight solenoid's kernel does not contain the
# integrator at all. This also makes curvature consistent with the multipole
# axis, which was already dispatched on `N`.
@inline track_particle(::Symplectic6DMap, elem::Solenoid{M,T,0,false},
                       x, px, y, py, z, pz) where {M,T} =
    _solenoid_map(elem.ks, elem.L, x, px, y, py, z, pz)

@inline track_particle(::Symplectic6DMap, elem::Solenoid{M,T,0,true},
                       x, px, y, py, z, pz) where {M,T} =
    _solenoid_curved_map(elem.h, elem.ks, elem.L, elem.nst, x, px, y, py, z, pz)

"""
Solenoid with superimposed multipoles, by Strang splitting.

The two pieces do not commute -- the solenoid rotates the frame the multipole
kicks in -- so a combined solenoid-multipole is **not** exactly integrable and
this is the one place the element stops being exact. Second-order Strang:

    S(d/2) K(d) S(d/2)   repeated `nst` times,

with `S` the exact solenoid map of `_solenoid_map` and `K` the same
`_lattice_kick` every thick magnet uses. This is structurally what PTC does in
`INTER_SOL5`, which interleaves `KICK_SOL` with `KICKMUL` at Yoshida orders 2, 4
and 6; the difference is that PTC's `S` is its rotating-frame decomposition and
ours is the closed form, which agree to 4.9e-13.

Strengths are **thick** `K_n`, not the thin family's integrated `K_n L`: a
solenoid has a length, so it follows `QuadrupoleSpec`'s convention and takes
`kn`/`k1`/`k2`, never `knl`/`k1l`. Confusing the two is a factor of `L`.
"""
@inline function track_particle(::Symplectic6DMap, elem::Solenoid{M,T,N,CURVED},
                                x, px, y, py, z, pz) where {M,T,N,CURVED}
    nst = elem.nst
    d = elem.L / nst
    dh = d / 2
    @inbounds for _ in 1:nst
        x, px, y, py, z, pz = _sol_body(elem, dh, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _lattice_kick(elem.kn, elem.ksk, elem.h, d,
                                            x, px, y, py, z, pz)
        x, px, y, py, z, pz = _sol_body(elem, dh, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end

# One solenoid sub-step of the Strang loop, selected by type as above.
@inline _sol_body(elem::Solenoid{M,T,N,false}, d, x, px, y, py, z, pz) where {M,T,N} =
    _solenoid_map(elem.ks, d, x, px, y, py, z, pz)

@inline _sol_body(elem::Solenoid{M,T,N,true}, d, x, px, y, py, z, pz) where {M,T,N} =
    _solenoid_curved_map(elem.h, elem.ks, d, 1, x, px, y, py, z, pz)

@inline (elem::Solenoid)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

"""
    SolenoidSpec(; L, ks, tracking_method=Symplectic6DMap())

Solenoid element spec. `ks = B_s / (B*rho)` is MAD-X's `KS`; `L` is the length.

The map is exact in `(1 + delta)` and in transverse amplitude, so the focusing
carries its natural chromaticity and amplitude dependence with no extra terms,
and `ks = 0` reproduces the exact drift to roundoff rather than to a tolerance.

The entrance and exit fringe fields are **included and cannot be switched off**,
because they are not a separate model: they are the canonical-to-kinetic
momentum conversion that a longitudinal field's transverse vector potential
forces at a hard edge. A solenoid without them would not be a solenoid without
fringe fields, it would be non-symplectic.

```julia
SolenoidSpec(L=2.0, ks=0.35)
```

Two consequences worth knowing, both from `docs/theory/solenoid.md`:

- **Do not split a solenoid.** A split point sits where the vector potential is
  non-zero, so the two halves would have to exchange kinetic rather than
  canonical momenta. The map is exact, so there is no accuracy reason to split.
- **Coordinates inside a solenoid are canonical.** Since elements are
  entrance-to-exit maps this is not reachable today, but it becomes reachable
  the moment one is split -- which is the second reason not to.
"""
abstract type SolenoidSpec end

# `ks` is the SOLENOID strength here, following MAD-X's `KS`. Every other thick
# magnet in Octopus uses `ks` for the *skew multipole tuple*, so the solenoid --
# and only the solenoid -- folds its skew strengths into `kskew` instead. The
# collision is real and one of the two spellings had to move; the solenoid's
# defining parameter keeps the name the rest of the world uses for it, and the
# skew tuple is the one users almost always reach through `k1s`/`k2s` anyway.
SolenoidSpec(; kwargs...) = ElementSpec{:solenoid}(
    _spec_params(; _fold_named_strengths(_MULTIPOLE_NAMED, kwargs;
                                         nkey=:kn, skey=:kskew)...))

function Solenoid(spec::ElementSpec,
                  method::AbstractTrackingMethod=Symplectic6DMap())
    L = getparam(spec, :L, 0)
    ks = getparam(spec, :ks, 0)
    kn_raw = getparam(spec, :kn, ())
    ksk_raw = getparam(spec, :kskew, ())
    h = getparam(spec, :h, 0)
    # The default step count depends on the frame, because the two paths need
    # utterly different things from it. A straight solenoid is the exact flow
    # and ignores `nst` entirely, so 1 is right. A curved one is integrated, and
    # `nst = 1` there is not merely inaccurate: at h = 0.18 over L = 1.3 the
    # implicit stage does not converge and the result is garbage (error 1.09
    # against coordinates of 1e-3). Defaulting to 1 in that case would let
    # `SolenoidSpec(L=..., ks=..., h=...)` silently return nonsense.
    # `curved` selects the tracking path and is settled here, once, then carried
    # in the type. It defaults to `!iszero(h)` -- the frame decides -- but is
    # deliberately overridable, because the two overrides are both useful:
    #
    #   curved = true,  h = 0    run the integrator on a straight frame, where
    #                            the exact closed form is also available. This
    #                            is a *direct* validation of the integrator
    #                            rather than an h -> 0 limit, and is why the
    #                            keyword exists rather than keying on `h` alone.
    #   curved = false, h != 0   ignore the curvature and track straight. A
    #                            legitimate approximation to ask for, but never
    #                            silently: it warns.
    requested = getparam(spec, :curved, nothing)
    curved = requested === nothing ? !iszero(h) : Bool(requested)
    if !curved && !iszero(h)
        @warn "solenoid has curved = false with h != 0; the frame curvature is \
               ignored and the element tracks as a straight solenoid" h
    end
    nst = Int(getparam(spec, :nst, curved ? 16 : 1))
    nst >= 1 || throw(ArgumentError("solenoid nst must be at least 1; got $(nst)"))
    n = max(length(kn_raw), length(ksk_raw))
    T = float(promote_type(typeof(L), typeof(ks), typeof(h), Float64))
    kn = ntuple(i -> i <= length(kn_raw) ? T(kn_raw[i]) : zero(T), n)
    ksk = ntuple(i -> i <= length(ksk_raw) ? T(ksk_raw[i]) : zero(T), n)
    # A pure solenoid drops to N = 0, which selects the exact single-map method:
    # no splitting, no steps, and bit-identical to what it was before multipoles
    # existed.
    if all(iszero, kn) && all(iszero, ksk)
        return Solenoid{typeof(method),T,0,curved}(
            method, T(L), T(ks), T(h), (), (), nst)
    end
    return Solenoid{typeof(method),T,n,curved}(
        method, T(L), T(ks), T(h), kn, ksk, nst)
end

@element_spec begin
    kind = :solenoid
    spec_type = ElementSpec{:solenoid}
    friendly_constructor = SolenoidSpec
    runtime_type = Solenoid
    description = "Exact solenoid: longitudinal field with hard-edge fringes, exact in delta and amplitude."
    keywords = [:lattice_magnet, :thick_element, :coordinate_transform]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, SymplecticityContract,
                 PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=ParamMeta(default=0, meaning="magnetic length in metres"),
        ks=ParamMeta(default=0, meaning="normalized longitudinal field B_s/(B*rho), MAD-X's KS. Sign follows charge and field direction; both polarities are checked against PTC. Note this is the SOLENOID strength, not the skew multipole tuple other magnets spell `ks`"),
        kn=ParamMeta(default=(), meaning="normal multipole strengths superimposed on the solenoid; kn[i] = K_{i-1}. THICK strengths as for QuadrupoleSpec, not the thin family's integrated K_n L"),
        kskew=ParamMeta(default=(), meaning="skew partners of kn. Spelled `kskew` rather than `ks` because the solenoid needs `ks` for its own strength; usually set through the named k0s/k1s/k2s keywords instead"),
        curved=ParamMeta(default=nothing, meaning="force the curved (implicit-midpoint) or straight (exact) tracking path. `nothing` lets the frame decide, i.e. curved when h != 0. `true` with h = 0 runs the integrator where the exact map is also available, which validates it directly rather than as a limit; `false` with h != 0 ignores the curvature and warns"),
        h=ParamMeta(default=0, meaning="reference-frame curvature. h=0 is the exact closed-form map; h!=0 has no closed form and no exact splitting either, so it integrates with implicit midpoint over nst steps"),
        nst=ParamMeta(default=1, meaning="integration steps. Used when multipoles are present, or when h != 0; a straight pure solenoid is exact and ignores it. The default is 1 straight but 16 curved, because nst=1 does not converge at production curvature. Measure convergence for production work rather than trusting the default"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = SolenoidSpec(L=2.0, ks=0.35)
    construction_help = "Friendly constructor: SolenoidSpec(; L, ks, h=0, curved=nothing, kn=(), kskew=(), nst=1, tracking_method=Symplectic6DMap()), plus named k0/k1/k2... and skew k0s/k1s/k2s... exactly as QuadrupoleSpec takes them. ks = B_s/(B*rho) is MAD-X's KS and is the SOLENOID strength; because that name is taken, skew multipoles fold into `kskew` rather than the `ks` other magnets use. Multipole strengths are THICK K_n, not the thin family's integrated K_n L. h is the reference-frame curvature and `curved` selects the tracking path, defaulting to curved when h != 0; curved=true at h=0 runs the integrator where the exact map also exists, which validates it directly, and curved=false at h!=0 ignores the curvature and warns. A straight pure solenoid is the exact flow and ignores nst; ks=0 reproduces the exact drift and ks=0 with k1 reproduces QuadrupoleSpec, both to roundoff. With multipoles the map is a second-order Strang splitting over nst steps and is no longer exact, because the solenoid rotates the frame the multipole kicks in. Entrance and exit fringes are included and cannot be disabled: they are the canonical-to-kinetic momentum conversion a transverse vector potential forces, not an optional model. Do not split a solenoid -- a split point lies where the vector potential is non-zero. Derivation: docs/theory/solenoid.md."
end
