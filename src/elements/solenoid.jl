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
struct Solenoid{M<:AbstractTrackingMethod,T<:AbstractFloat,N} <: AbstractTrackOp
    method::M
    L::T
    ks::T
    kn::NTuple{N,T}          # kn[i] = K_{i-1}, normal, THICK (not integrated)
    ksk::NTuple{N,T}         # skew partners
    nst::Int
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

# Pure solenoid: N == 0, one exact map, no splitting and no steps.
@inline track_particle(::Symplectic6DMap, elem::Solenoid{M,T,0},
                       x, px, y, py, z, pz) where {M,T} =
    _solenoid_map(elem.ks, elem.L, x, px, y, py, z, pz)

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
@inline function track_particle(::Symplectic6DMap, elem::Solenoid{M,T,N},
                                x, px, y, py, z, pz) where {M,T,N}
    nst = elem.nst
    d = elem.L / nst
    dh = d / 2
    @inbounds for _ in 1:nst
        x, px, y, py, z, pz = _solenoid_map(elem.ks, dh, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _lattice_kick(elem.kn, elem.ksk, zero(T), d,
                                            x, px, y, py, z, pz)
        x, px, y, py, z, pz = _solenoid_map(elem.ks, dh, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end

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
    nst = Int(getparam(spec, :nst, 1))
    nst >= 1 || throw(ArgumentError("solenoid nst must be at least 1; got $(nst)"))
    n = max(length(kn_raw), length(ksk_raw))
    T = float(promote_type(typeof(L), typeof(ks), Float64))
    kn = ntuple(i -> i <= length(kn_raw) ? T(kn_raw[i]) : zero(T), n)
    ksk = ntuple(i -> i <= length(ksk_raw) ? T(ksk_raw[i]) : zero(T), n)
    # A pure solenoid drops to N = 0, which selects the exact single-map method:
    # no splitting, no steps, and bit-identical to what it was before multipoles
    # existed.
    if all(iszero, kn) && all(iszero, ksk)
        return Solenoid{typeof(method),T,0}(method, T(L), T(ks), (), (), 1)
    end
    return Solenoid{typeof(method),T,n}(method, T(L), T(ks), kn, ksk, nst)
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
        nst=ParamMeta(default=1, meaning="Strang steps used only when multipoles are present. A pure solenoid is exact and ignores this"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = SolenoidSpec(L=2.0, ks=0.35)
    construction_help = "Friendly constructor: SolenoidSpec(; L, ks, kn=(), kskew=(), nst=1, tracking_method=Symplectic6DMap()), plus named k0/k1/k2... and skew k0s/k1s/k2s... exactly as QuadrupoleSpec takes them. ks = B_s/(B*rho) is MAD-X's KS and is the SOLENOID strength; because that name is taken, skew multipoles fold into `kskew` rather than the `ks` other magnets use. Multipole strengths are THICK K_n, not the thin family's integrated K_n L. A pure solenoid is the exact flow and ignores nst; ks=0 reproduces the exact drift and ks=0 with k1 reproduces QuadrupoleSpec, both to roundoff. With multipoles the map is a second-order Strang splitting over nst steps and is no longer exact, because the solenoid rotates the frame the multipole kicks in. Entrance and exit fringes are included and cannot be disabled: they are the canonical-to-kinetic momentum conversion a transverse vector potential forces, not an optional model. Do not split a solenoid -- a split point lies where the vector potential is non-zero. Derivation: docs/theory/solenoid.md."
end
