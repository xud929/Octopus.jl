export RFCavitySpec, RFCavity, rf_strength

# ---------------------------------------------------------------------------
# RF cavity, without acceleration.
#
# Design, the four-code comparison, and why there is no reference particle:
# `docs/theory/rf_cavity_and_reference_energy.md`.
#
# THE REFERENCE ENERGY IS CONSTANT THROUGH THIS ELEMENT. That is Bmad's
# `rfcavity` rather than its `lcavity`, and the split is not redundancy: the two
# use different trig functions, so `phase = 0` means "no acceleration" in one
# and "on crest" in the other. An accelerating cavity is a separate kind, not a
# flag on this one, for exactly the reason `ref_tilt` is not a flag on `tilt`.
#
# The body is written in `TIME_ENERGY` (convention #1) and conjugated back into
# the pair Octopus tracks, because that is the pair the physics is stated in:
# #1's coordinate IS `-c dt` and its momentum IS `dE/(P0 c)`, so a cavity there
# is one line with no beta factor in it. Every beta lives in the two wrappers,
# where `lattice_hamiltonian_and_conventions.md` Section 2.2 put them. The note
# anticipated this use: one square root per conversion, "applied once per cavity
# rather than once per magnet, that is free".
# ---------------------------------------------------------------------------

"""
    RFCavity{M,T}

Runtime RF cavity: a longitudinal kick between two half drifts.

Holds only **dimensionless** numbers. There is deliberately no energy here —
`BeamParams` owns `E0`, it is read once when the spec is built, and an element
that stored a second copy could disagree with it. Same discipline as the
strong-beam `kbb` and the crab cavity's `strength`.
"""
struct RFCavity{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    strength::T      # qV/(P0 c), the kick in p_t per unit sin
    k::T             # 2*pi*frequency/c
    phase::T         # radians
    L::T
    beta0::T
    gamma0::T
end

"""
Longitudinal kick, in convention #1 where it is one line.

`p_t = dE/(P0 c)`, so an energy gain `qV sin(theta)` is `strength * sin(theta)`
with `strength = qV/(P0 c)` and nothing else. `z1 = -c dt` exactly, so the phase
a particle sees is `k*z1 + phase` with no approximation — this is where the
sandwich earns itself, since the same expression written against the tracking
coordinate would carry a stray `beta`.

Changing only the momentum by a function of the coordinate is a canonical
transformation, so the kick is symplectic, and the two wrappers are symplectic
by construction (Section 2). The composition therefore is.
"""
@inline function _rf_kick(elem::RFCavity, x, px, y, py, z, pz)
    # A cavity with no voltage is exactly nothing, not nothing to round-off.
    # The conversion round trip is only exact to ~4e-16, so without this a
    # switched-off cavity would perturb a lattice in the last bits -- and
    # `_misalignment_wrap` and `_ref_tilt_wrap` both set the precedent of
    # returning the input untouched when there is no effect to apply.
    iszero(elem.strength) && return (x, px, y, py, z, pz)
    z1, pt = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, pz;
                                  beta0=elem.beta0, gamma0=elem.gamma0)
    pt += elem.strength * sin(elem.k * z1 + elem.phase)
    zn, pzn = convert_longitudinal(TIME_ENERGY => PATHLENGTH_DELTA, z1, pt;
                                   beta0=elem.beta0, gamma0=elem.gamma0)
    return x, px, y, py, zn, pzn
end

@inline function track_particle(::Symplectic6DMap, elem::RFCavity{M,T},
                                x, px, y, py, z, pz) where {M,T}
    if iszero(elem.L)
        return _rf_kick(elem, x, px, y, py, z, pz)
    end
    # Drift-kick-drift, as AT's CavityPass does. The thin case above is the
    # exact `L = 0` limit of this, not a separate model.
    half = elem.L / 2
    x, px, y, py, z, pz = _lattice_drift(Val(false), zero(T), half, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _rf_kick(elem, x, px, y, py, z, pz)
    return _lattice_drift(Val(false), zero(T), half, x, px, y, py, z, pz)
end

@inline (elem::RFCavity)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

"""
    rf_strength(; voltage, e0, charge = 1, beta0)

The dimensionless cavity strength `qV/(P0 c)`, with `P0 c = beta0 * E0`.

This is the one place a voltage meets an energy. Keeping it in a named function
rather than inline at each call site is the point: it is the single read of
`E0`, so it is the single place the coupling is visible. The result is a
**snapshot** — change the beam energy afterwards and the strength does not
follow, exactly as `kbb` behaves today.

`voltage` in volts, `e0` in eV, `charge` in units of the elementary charge.
"""
rf_strength(; voltage, e0, charge=1, beta0) = charge * voltage / (beta0 * e0)

# An abstract type rather than a bare function, matching PatchSpec, SBendSpec
# and BeamLine: the metadata registry keys friendly constructors by type.
abstract type RFCavitySpec end

"""
    RFCavitySpec(frequency; strength, beta0, gamma0, phase=0, L=0)
    RFCavitySpec(frequency; voltage, e0, mc2, charge=1, phase=0, L=0)

An RF cavity **without acceleration** — Bmad's `rfcavity`, not its `lcavity`.
The reference energy is constant through it, which is what a storage ring wants
and what closes the longitudinal plane so there is a synchrotron tune to speak
of.

Conventions follow `ThinCrabCavity`, deliberately, so that `phase` means one
thing across every RF element in a lattice:

- `frequency` in **Hz** (not MAD-X's MHz),
- `phase` in **radians** (not MAD-X's units of 2π, Bmad's rad/2π, or elegant's
  degrees),
- the argument is `k*z + phase`, **additive**.

The second form is the friendly one: give a voltage and the beam's `e0`/`mc2`
and the spec stores the dimensionless results. **The energy is an argument, not
a field** — nothing here can drift out of step with `BeamParams.E0`, because
nothing here remembers it.

```julia
RFCavitySpec(400.8e6; voltage = 12e6, e0 = 275e9, mc2 = PMASS_EV)
```

Importing from another code? The phase conversions are in
`docs/theory/rf_cavity_and_reference_energy.md` §4. MAD-X's `LAG` and Bmad's
`phi0` differ by half a turn from each other before any unit change.
"""
function RFCavitySpec(frequency;
                      strength=nothing, beta0=nothing, gamma0=nothing,
                      voltage=nothing, e0=nothing, mc2=nothing, charge=1,
                      phase=0, L=0, tracking_method=Symplectic6DMap(), kwargs...)
    if voltage !== nothing
        (e0 === nothing || mc2 === nothing) && throw(ArgumentError(
            "RFCavitySpec with `voltage` also needs `e0` and `mc2`, so the \
             dimensionless strength and beta0 can be derived; or give \
             `strength`, `beta0` and `gamma0` directly"))
        strength === nothing || throw(ArgumentError(
            "give either `voltage` (with e0, mc2) or `strength`, not both"))
        beta0, gamma0 = reference_beta_gamma(e0, mc2)
        strength = rf_strength(; voltage=voltage, e0=e0, charge=charge, beta0=beta0)
    end
    strength === nothing && throw(ArgumentError(
        "RFCavitySpec needs either `voltage` with `e0` and `mc2`, or `strength` \
         with `beta0` and `gamma0`"))
    (beta0 === nothing || gamma0 === nothing) && throw(ArgumentError(
        "RFCavitySpec needs `beta0` and `gamma0`; derive them with \
         reference_beta_gamma(e0, mc2)"))
    frequency > 0 || throw(ArgumentError("frequency must be positive, got $frequency"))
    T = float(promote_type(typeof(strength), typeof(frequency), typeof(phase),
                           typeof(L), typeof(beta0), typeof(gamma0)))
    return ElementSpec{:rf_cavity}(_spec_params(;
        frequency=T(frequency), strength=T(strength), phase=T(phase), L=T(L),
        beta0=T(beta0), gamma0=T(gamma0), tracking_method=tracking_method, kwargs...))
end

"""
    RFCavitySpec(; frequency, ...)

Keyword form. Same element; exists because reflection builds every kind by
keyword alone, and because a spec rebuilt from `parameter_schema` should round
trip.
"""
RFCavitySpec(; frequency, kwargs...) = RFCavitySpec(frequency; kwargs...)

function RFCavity(spec::ElementSpec{:rf_cavity},
                  method::AbstractTrackingMethod=tracking_method(spec))
    T = numeric_type(spec)
    k = T(2) * T(pi) * T(param(spec, :frequency)) / T(CLIGHT)
    return RFCavity{typeof(method),T}(
        method, T(param(spec, :strength)), k, T(getparam(spec, :phase, 0)),
        T(getparam(spec, :L, 0)), T(param(spec, :beta0)), T(param(spec, :gamma0)))
end

@element_spec begin
    kind = :rf_cavity
    spec_type = ElementSpec{:rf_cavity}
    friendly_constructor = RFCavitySpec
    runtime_type = RFCavity
    description = "RF cavity without acceleration: a longitudinal kick between two half drifts."
    keywords = [:harmonic, :thick_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        frequency=ParamMeta(required=true, unit="Hz", meaning="RF frequency, in Hz as ThinCrabCavity takes it and not MAD-X's MHz"),
        strength=ParamMeta(required=true, meaning="dimensionless kick qV/(P0 c): the change in p_t per unit sin. Derived from voltage and e0 by the friendly constructor, so no absolute energy is stored on the element and nothing can disagree with BeamParams.E0"),
        phase=ParamMeta(default=0, unit="rad", meaning="RF phase in radians, entering as the additive `k*z + phase` exactly as ThinCrabCavity does. phase = 0 gives no net acceleration, which is a ring's natural zero; an accelerating cavity is a different element with a different zero"),
        beta0=ParamMeta(required=true, meaning="reference velocity, dimensionless. Needed by the coordinate conversions and by the energy-to-momentum factor; it is what distinguishes a proton ring from an electron ring and what the ultrarelativistic approximation throws away"),
        gamma0=ParamMeta(required=true, meaning="reference Lorentz factor, dimensionless. With beta0, fixes the exact conversion between longitudinal conventions"),
        L=ParamMeta(default=0, unit="m", meaning="cavity length. Nonzero gives drift-kick-drift as AT's CavityPass does; L = 0 is the exact thin limit of it rather than a separate model"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = RFCavitySpec(400.8e6; voltage=12.0e6, e0=275.0e9, mc2=PMASS_EV)
    construction_help = "Friendly constructor: RFCavitySpec(frequency; voltage, e0, mc2, charge=1, phase=0, L=0) or RFCavitySpec(frequency; strength, beta0, gamma0, phase=0, L=0, tracking_method=Symplectic6DMap()). An RF cavity WITHOUT acceleration -- Bmad's rfcavity, not its lcavity -- so the reference energy is constant through it and phase = 0 is no net acceleration. Frequency in Hz and phase in radians, matching ThinCrabCavity so that `phase` means one thing across every RF element. The energy is an ARGUMENT and not a field: voltage and e0 are reduced to a dimensionless strength at construction, so nothing on the element can disagree with BeamParams.E0. The body is written in the TIME_ENERGY convention and conjugated back by convert_longitudinal, which is why there is no beta factor in it. Design: docs/theory/rf_cavity_and_reference_energy.md."
end
