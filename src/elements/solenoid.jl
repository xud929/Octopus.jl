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
struct Solenoid{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    L::T
    ks::T
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

@inline track_particle(::Symplectic6DMap, elem::Solenoid, x, px, y, py, z, pz) =
    _solenoid_map(elem.ks, elem.L, x, px, y, py, z, pz)

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

SolenoidSpec(; kwargs...) = ElementSpec{:solenoid}(_spec_params(; kwargs...))

function Solenoid(spec::ElementSpec,
                  method::AbstractTrackingMethod=Symplectic6DMap())
    L = getparam(spec, :L, 0)
    ks = getparam(spec, :ks, 0)
    T = float(promote_type(typeof(L), typeof(ks)))
    return Solenoid{typeof(method),T}(method, T(L), T(ks))
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
        ks=ParamMeta(default=0, meaning="normalized longitudinal field B_s/(B*rho), MAD-X's KS. Sign follows charge and field direction; both polarities are checked against PTC"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = SolenoidSpec(L=2.0, ks=0.35)
    construction_help = "Friendly constructor: SolenoidSpec(; L, ks, tracking_method=Symplectic6DMap()). ks = B_s/(B*rho) is MAD-X's KS. The map is the exact flow, so there is no nst and no integrator order, and ks=0 reproduces the exact drift to roundoff. Entrance and exit fringes are included and cannot be disabled: they are the canonical-to-kinetic momentum conversion a transverse vector potential forces, not an optional model. Do not split a solenoid -- a split point lies where the vector potential is non-zero. Derivation: docs/theory/solenoid.md."
end
