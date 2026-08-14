export ThinRFCavitySpec, ThinRFCavity, rf_strength

# ---------------------------------------------------------------------------
# THIN RF cavity, without acceleration.
#
# "Thin" is a claim about the physics, not just a name. The model is ONE
# localised energy kick. `L` buys drift space so the cavity occupies its proper
# length in a lattice -- which matters now that a BeamLine computes arc
# positions from `L` -- but the kick still happens at a point, exactly as AT's
# CavityPass does. What that leaves out, stated so nobody has to discover it:
#
#   * no transit-time factor: the particle is not tracked through the field
#     while the field oscillates, so a cavity long compared with the RF
#     wavelength is not modelled;
#   * no RF focusing: a real cavity's transverse fields defocus, and here the
#     transverse coordinates are untouched by the kick;
#   * no distributed field, so no field map and no cell structure.
#
# It is the same standing as `ThinCrabCavity` next door, and the same standing
# as `ThinMultipole` against a thick magnet: correct for what it models, and
# named so the boundary is visible from the call site.
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
    ThinRFCavity{M,T}

Runtime RF cavity: a longitudinal kick between two half drifts.

Holds only **dimensionless** numbers. There is deliberately no energy here —
`BeamParams` owns `E0`, it is read once when the spec is built, and an element
that stored a second copy could disagree with it. Same discipline as the
strong-beam `kbb` and the crab cavity's `strength`.
"""
struct ThinRFCavity{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    strength::T      # qV/(P0 c), the kick in p_t per unit sin
    k::T             # 2*pi*frequency/c
    phase::T         # radians
    L::T
    beta0::T
    gamma0::T
    # Survey channel (docs/design/survey_and_reference_channel.md). NaN means
    # "no survey": the cavity was compiled bare, outside a task line, and
    # keeps the documented s = 0 model boundary. A finite value is bound by
    # `_bind_survey` when a task compiles the line, and switches the kick to
    # the slip-corrected form: a symplectic z-shift of
    # `ds_turn * (β/β₀ - 1)` before the kick (see _rf_kick). `ds_turn` is the
    # arc distance from the previous cavity kick, wrapping the turn (one
    # cavity: the full line length), so every number stays bounded at any
    # turn count and no turn counter is needed: the correction is a per-op
    # constant, identical on the fused, contextless, and direct
    # track_particle paths. The one convention this buys is that the
    # injection pass is treated as a full wrap too, misdating its slip by one
    # partial turn — a bounded, delta-dependent redefinition of the injection
    # reference time, recorded in the theory note.
    ds_turn::T
end

"""
    _velocity_slip_g(delta, pt, beta0, gamma0)

`(β - β₀)/β₀`, exactly and cancellation-free: the relative velocity excess of
an off-momentum particle. Derived by the conjugate trick from
`(1+δ)² - (1+β₀ p_t)² = p_t (2/β₀ + p_t)/γ₀²` (the same identity family as
the U14-4 `δ ↔ p_t` rewrite), so the `1/γ₀²` smallness is an explicit factor
rather than a subtraction of two numbers near 1 — full relative precision at
any energy, where the literal `β/β₀ - 1` loses everything at large `γ₀`.
Verified against BigFloat in the F16 validation testset.
"""
@inline _velocity_slip_g(delta, pt, beta0, gamma0) =
    pt * (2 / beta0 + pt) /
    (gamma0^2 * (2 + delta + beta0 * pt) * (1 + beta0 * pt))

"""
Longitudinal kick, in convention #1 where it is one line.

`p_t = dE/(P0 c)`, so an energy gain `qV sin(theta)` is `strength * sin(theta)`
with `strength = qV/(P0 c)` and nothing else, and the phase a particle sees is
`k*z1 + phase` — this is where the sandwich earns itself, since the same
expression written against the tracking coordinate would carry a stray `beta`.

**Model boundary (2026-08-05 audit, F16): the conversion is called with its
arc position `s` at the default 0**, because a runtime element has no channel
to its accumulated reference path (`turn*C + s_elem` — the same missing
survey channel as Scope B's `P0(s)`). The `z1` used here is therefore
`z/beta`, not the full `-c dt = z/beta + s*(1/beta0 - 1/beta)`: the
velocity-slip term is absent, so the slip factor a ring built from
convention-#3 maps and this cavity sees is `alpha_c` alone, missing the
`-1/gamma0^2` term — convention-#3 lattice maps carry no velocity term by
construction, and this conversion was the one place it could have entered.
Negligible when `gamma0^2 * alpha_c >> 1` (the validated EIC-class cases:
electron 10 GeV has 1/gamma0^2 = 2.6e-9); WRONG physics for moderate-energy
hadron rings — measured 1.84x synchrotron-tune error at 2.5 GeV proton with
alpha_c = 0.2, and the wrong side of transition whenever
`alpha_c < 1/gamma0^2`.

**F16 closure (2026-08-13): this boundary now applies only to a cavity
compiled bare.** A cavity compiled through a task line gets `ds_turn` bound by
`_bind_survey` — the arc distance from the previous cavity's kick, wrapping
the turn — and this same kick then advances `z` by the exact velocity slip
`ds_turn * (β/β₀ - 1)` before the conjugated body, restoring the full
`eta = alpha_c - 1/gamma0^2`. Between kicks `delta` is untouched by the
convention-#3 lattice maps, so per-segment shifts compose to exactly the
per-turn `C*(β/β₀ - 1)`; every number stays bounded at any turn count. Why a
z-shift and not an `s` argument to the conversion: a constant per-turn `s`
inside the conjugation cancels out of the one-turn dynamics entirely
(measured), and an accumulating `turn*C` one grows without bound — the
derivation, that negative measurement, and the injection-pass convention are
in docs/theory/arc_survey_and_velocity_slip.md.

Changing only the momentum by a function of the coordinate is a canonical
transformation, so the kick is symplectic, and the two wrappers are symplectic
by construction (Section 2). The composition therefore is.
"""
@inline function _rf_kick(elem::ThinRFCavity{M,T}, x, px, y, py, z, pz) where {M,T}
    # A cavity with no voltage is exactly nothing, not nothing to round-off.
    # The conversion round trip is only exact to ~4e-16, so without this a
    # switched-off cavity would perturb a lattice in the last bits -- and
    # `_misalignment_wrap` and `_ref_tilt_wrap` both set the precedent of
    # returning the input untouched when there is no effect to apply.
    iszero(elem.strength) && return (x, px, y, py, z, pz)
    # Survey-bound (F16 closure): the velocity slip enters as a symplectic
    # z-SHIFT before the kick, never as an `s` argument to the conversion.
    # The convention-#3 coordinate is a path deficit and physically does not
    # slip with velocity -- the slip lives in arrival TIME, which accumulates
    # without bound -- so a bounded-state cavity must reconcile the two by
    # advancing the z its phase reads by the time slip accumulated since the
    # previous kick, `ds_turn * (β/β₀ - 1)`. (A constant `s` inside the
    # conversion cancels out of the one-turn dynamics entirely: measured
    # nu_s stayed at the alpha_c-only value to 0.7%. The derivation and that
    # negative result: docs/theory/arc_survey_and_velocity_slip.md.)
    if _has_survey(elem)
        pt0 = _pt_from_delta(pz, elem.beta0, elem.gamma0)
        z += elem.ds_turn * _velocity_slip_g(pz, pt0, elem.beta0, elem.gamma0)
    end
    z1, pt = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, pz;
                                  beta0=elem.beta0, gamma0=elem.gamma0)
    pt += elem.strength * sin(elem.k * z1 + elem.phase)
    zn, pzn = convert_longitudinal(TIME_ENERGY => PATHLENGTH_DELTA, z1, pt;
                                   beta0=elem.beta0, gamma0=elem.gamma0)
    return x, px, y, py, zn, pzn
end

@inline function track_particle(::Symplectic6DMap, elem::ThinRFCavity{M,T},
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

@inline (elem::ThinRFCavity)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

# No context-aware method is defined: with the arc argument in difference
# form the slip correction is a per-op CONSTANT, so the generic
# AbstractTrackOp ctx fallback (which drops ctx and calls the contextless op)
# is exactly right, and every path — fused, contextless track!, direct
# track_particle — computes the same corrected kick. This is deliberate: an
# earlier draft read ctx.turn to special-case the injection pass, which made
# the raw track! path (whose default TrackingContext pins turn = 0) silently
# wrong instead of merely conventionally offset. See the design note §3c.

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
abstract type ThinRFCavitySpec end

"""
    ThinRFCavitySpec(frequency; strength, beta0, gamma0, phase=0, L=0)
    ThinRFCavitySpec(frequency; voltage, e0, mc2, charge=1, phase=0, L=0)

A **thin** RF cavity **without acceleration** — Bmad's `rfcavity`, not its
`lcavity`, and a single localised kick rather than a field integrated along the
cavity.
The reference energy is constant through it, which is what a storage ring wants
and what closes the longitudinal plane so there is a synchrotron tune to speak
of.

Conventions follow `ThinCrabCavity`, deliberately, so that `phase` means one
thing across every RF element in a lattice:

- `frequency` in **Hz** (not MAD-X's MHz),
- `phase` in **radians** (not MAD-X's units of 2π, Bmad's rad/2π, or elegant's
  degrees),
- the argument is `k*z₁ + phase`, **additive**, with `z₁` the TIME_ENERGY
  coordinate (`z/β` in the tracked convention) — this coincides with
  `ThinCrabCavity`'s `k*z` only at `β = 1`; at 2.5 GeV proton and `z = 7 mm`
  the two differ by 4.6e-3 rad.

Model boundaries, stated so they are visible from the call site: no
transit-time factor and no RF focusing (see `L`). The velocity-slip boundary
is **conditional** since the F16 closure (2026-08-14): compiled *bare*, the
cavity has no velocity-slip term and closes a ring with `alpha_c` alone,
missing `-1/gamma0²`; compiled *through a task line*, it is bound to the
geometric survey and applies the exact slip as a symplectic z-shift before
its kick, closing the ring with the full `eta = alpha_c - 1/gamma0²`
(`docs/theory/arc_survey_and_velocity_slip.md`).

The second form is the friendly one: give a voltage and the beam's `e0`/`mc2`
and the spec stores the dimensionless results. **The energy is an argument, not
a field** — nothing here can drift out of step with `BeamParams.E0`, because
nothing here remembers it.

```julia
ThinRFCavitySpec(400.8e6; voltage = 12e6, e0 = 275e9, mc2 = PMASS_EV)
```

Importing from another code? The phase conversions are in
`docs/theory/rf_cavity_and_reference_energy.md` §4. MAD-X's `LAG` and Bmad's
`phi0` differ by half a turn from each other before any unit change.
"""
function ThinRFCavitySpec(frequency;
                      strength=nothing, beta0=nothing, gamma0=nothing,
                      voltage=nothing, e0=nothing, mc2=nothing, charge=1,
                      phase=0, L=0, tracking_method=Symplectic6DMap(), kwargs...)
    if voltage !== nothing
        (e0 === nothing || mc2 === nothing) && throw(ArgumentError(
            "ThinRFCavitySpec with `voltage` also needs `e0` and `mc2`, so the \
             dimensionless strength and beta0 can be derived; or give \
             `strength`, `beta0` and `gamma0` directly"))
        strength === nothing || throw(ArgumentError(
            "give either `voltage` (with e0, mc2) or `strength`, not both"))
        (beta0 === nothing && gamma0 === nothing) || throw(ArgumentError(
            "give either `voltage` (with e0, mc2 — beta0 and gamma0 are derived " *
            "from them) or `strength` with explicit `beta0`/`gamma0`, not a mix; " *
            "explicit values here were previously overwritten silently"))
        beta0, gamma0 = reference_beta_gamma(e0, mc2)
        strength = rf_strength(; voltage=voltage, e0=e0, charge=charge, beta0=beta0)
    end
    strength === nothing && throw(ArgumentError(
        "ThinRFCavitySpec needs either `voltage` with `e0` and `mc2`, or `strength` \
         with `beta0` and `gamma0`"))
    (beta0 === nothing || gamma0 === nothing) && throw(ArgumentError(
        "ThinRFCavitySpec needs `beta0` and `gamma0`; derive them with \
         reference_beta_gamma(e0, mc2)"))
    frequency > 0 || throw(ArgumentError("frequency must be positive, got $frequency"))
    # beta0 and gamma0 are two views of ONE reference energy. Supplied
    # separately they can disagree, and this element is the only place in the
    # repository where a caller hands over both by hand -- the `voltage` branch
    # above derives them together from `reference_beta_gamma`. An inconsistent
    # pair used to be accepted and produced a quietly non-symplectic map; this
    # spec's own contract fixture carried `beta0=0.99, gamma0=100.0`, which is
    # no particle at all (2026-08-05_b audit, U14-4).
    _check_reference_pair(beta0, gamma0; source="ThinRFCavitySpec")
    T = float(promote_type(typeof(strength), typeof(frequency), typeof(phase),
                           typeof(L), typeof(beta0), typeof(gamma0)))
    return ElementSpec{:thin_rf_cavity}(_spec_params(;
        frequency=T(frequency), strength=T(strength), phase=T(phase), L=T(L),
        beta0=T(beta0), gamma0=T(gamma0), tracking_method=tracking_method, kwargs...))
end

"""
    ThinRFCavitySpec(; frequency, ...)

Keyword form. Same element; exists because reflection builds every kind by
keyword alone, and because a spec rebuilt from `parameter_schema` should round
trip.
"""
ThinRFCavitySpec(; frequency, kwargs...) = ThinRFCavitySpec(frequency; kwargs...)

function ThinRFCavity(spec::ElementSpec{:thin_rf_cavity},
                  method::AbstractTrackingMethod=tracking_method(spec))
    T = numeric_type(spec)
    k = T(2) * T(pi) * T(param(spec, :frequency)) / T(CLIGHT)
    return ThinRFCavity{typeof(method),T}(
        method, T(param(spec, :strength)), k, T(getparam(spec, :phase, 0)),
        T(getparam(spec, :L, 0)), T(param(spec, :beta0)), T(param(spec, :gamma0)),
        T(NaN))
end

"""
    _attach_survey(elem::ThinRFCavity, ds_turn)

Rebuild the runtime cavity with its survey value bound. Called by
`_bind_survey` (Tasks.jl) when a task compiles a line containing this cavity;
never by users. Rebuilding rather than mutating keeps the compiled op
immutable and `isbits`, which the CUDA kernels require.
"""
_attach_survey(elem::ThinRFCavity{M,T}, ds_turn::Real) where {M,T} =
    ThinRFCavity{M,T}(elem.method, elem.strength, elem.k, elem.phase, elem.L,
                      elem.beta0, elem.gamma0, T(ds_turn))

_has_survey(elem::ThinRFCavity) = !isnan(elem.ds_turn)

@element_spec begin
    kind = :thin_rf_cavity
    spec_type = ElementSpec{:thin_rf_cavity}
    friendly_constructor = ThinRFCavitySpec
    runtime_type = ThinRFCavity
    description = "Thin RF cavity without acceleration: one localised longitudinal kick between two half drifts."
    keywords = [:harmonic, :thick_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        frequency=ParamMeta(required=true, unit="Hz", meaning="RF frequency, in Hz as ThinCrabCavity takes it and not MAD-X's MHz"),
        strength=ParamMeta(required=true, meaning="dimensionless kick qV/(P0 c): the change in p_t per unit sin. Derived from voltage and e0 by the friendly constructor, so no absolute energy is stored on the element and nothing can disagree with BeamParams.E0"),
        phase=ParamMeta(default=0, unit="rad", meaning="RF phase in radians, entering as the additive `k*z1 + phase` with z1 the TIME_ENERGY coordinate (z/beta in the tracked convention; coincides with ThinCrabCavity's k*z only at beta = 1). phase = 0 gives no net acceleration, which is a ring's natural zero; an accelerating cavity is a different element with a different zero"),
        beta0=ParamMeta(required=true, meaning="reference velocity, dimensionless. Needed by the coordinate conversions and by the energy-to-momentum factor; it is what distinguishes a proton ring from an electron ring and what the ultrarelativistic approximation throws away"),
        gamma0=ParamMeta(required=true, meaning="reference Lorentz factor, dimensionless. With beta0, fixes the exact conversion between longitudinal conventions"),
        L=ParamMeta(default=0, unit="m", meaning="cavity length, which buys DRIFT SPACE only: the kick stays a single localised impulse at the centre, as AT's CavityPass does, so a lattice gets the right arc positions without the element pretending to integrate the field. L = 0 is the exact limit of that rather than a separate model. No transit-time factor, no RF focusing and no velocity-slip term -- see the element docstring"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = ThinRFCavitySpec(400.8e6; voltage=12.0e6, e0=275.0e9, mc2=PMASS_EV)
    construction_help = "Friendly constructor: ThinRFCavitySpec(frequency; voltage, e0, mc2, charge=1, phase=0, L=0) or ThinRFCavitySpec(frequency; strength, beta0, gamma0, phase=0, L=0, tracking_method=Symplectic6DMap()). A THIN RF cavity WITHOUT acceleration -- Bmad's rfcavity, not its lcavity -- so the reference energy is constant through it and phase = 0 is no net acceleration. Thin means ONE localised kick: L buys drift space so the cavity occupies its proper arc length, but there is no transit-time factor and no RF focusing, the same standing as ThinCrabCavity and ThinMultipole. THIRD model boundary, CONDITIONAL since the F16 closure (2026-08-14): a cavity compiled BARE -- outside a task line -- has no velocity-slip term, so a ring it closes has slip factor alpha_c alone, missing -1/gamma0^2 (the recorded 1.84x synchrotron-tune error at a 2.5 GeV proton with alpha_c = 0.2, and the wrong side of transition whenever alpha_c < 1/gamma0^2). A cavity compiled THROUGH A TASK LINE is bound to the geometric survey and applies the exact velocity slip as a symplectic z-shift ds_turn*(beta/beta0 - 1) before its kick, closing the ring with the full eta = alpha_c - 1/gamma0^2 on every path and backend; a cavity hidden inside a kept-whole own-state sub-line is refused loudly at compile rather than silently left uncorrected. Physics: docs/theory/arc_survey_and_velocity_slip.md. Frequency in Hz and phase in radians, matching ThinCrabCavity so that `phase` means one thing across every RF element. The energy is an ARGUMENT and not a field: voltage and e0 are reduced to a dimensionless strength at construction, so nothing on the element can disagree with BeamParams.E0. The body is written in the TIME_ENERGY convention and conjugated back by convert_longitudinal, which is why there is no beta factor in it. Design: docs/theory/rf_cavity_and_reference_energy.md. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
end
