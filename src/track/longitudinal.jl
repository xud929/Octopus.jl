export LongitudinalConvention, TimeEnergy, SigmaPsigma, PathLengthDelta, TimeDelta,
       TIME_ENERGY, SIGMA_PSIGMA, PATHLENGTH_DELTA, TIME_DELTA,
       convention_number, tracking_convention,
       reference_gamma, reference_beta, reference_beta_gamma,
       convert_longitudinal, particle_beta

# ---------------------------------------------------------------------------
# Longitudinal coordinate conventions and the exact conversions between them.
#
# Derivation, the generating functions, and which code uses which:
# `docs/theory/lattice_hamiltonian_and_conventions.md` Section 2. This file is
# that section, implemented.
#
# Four canonical pairs are in circulation. They are all related to the same
# (q_t, p_t) by generating functions, so every conversion here is EXACTLY
# symplectic -- not to first order, not for small delta, exactly. That is the
# property that lets a map be written in whichever pair makes it simplest and
# conjugated back, which is how an RF cavity should be built: the field is
# naturally a function of arrival time and delivers an energy gain, so the body
# belongs in `TimeEnergy` even though Octopus tracks `PathLengthDelta`.
#
# The theory note puts the cost plainly: one square root per conversion,
# "applied once per cavity rather than once per magnet, that is free".
# ---------------------------------------------------------------------------

"""
    LongitudinalConvention

Which canonical longitudinal pair a coordinate and momentum are expressed in.

| singleton | note § | coordinate | momentum | used by |
|---|---|---|---|---|
| [`TIME_ENERGY`](@ref) | #1 | `-c Δt` | `ΔE/(P₀c)` | MAD-X, PTC `TIME=TRUE`, Xsuite `τ`/`pτ` |
| [`SIGMA_PSIGMA`](@ref) | #2 | `-β₀c Δt` | `ΔE/(β₀P₀c)` | SixTrack, Xsuite `zeta`/`pζ` |
| [`PATHLENGTH_DELTA`](@ref) | #3 | `s - ℓ` | `ΔP/P₀` | PTC `TIME=FALSE`, **and Octopus** |
| [`TIME_DELTA`](@ref) | #4 | `-βc Δt` | `ΔP/P₀` | Bmad, Xsuite `ξ`/`delta` |

Note that #3 and #4 share a *momentum* and differ in coordinate, while #1 and #2
share neither. Two conventions agreeing on `δ` is exactly why mixing them is
easy and why Xsuite's `zeta`/`delta` are famously not a conjugate pair — `zeta`
is #2 and `delta` is #4's momentum.
"""
abstract type LongitudinalConvention end

"""#1: `(-cΔt, ΔE/(P₀c))`. MAD-X and PTC `TIME=TRUE`; Xsuite `τ`, `pτ`."""
struct TimeEnergy <: LongitudinalConvention end

"""#2: `(-β₀cΔt, ΔE/(β₀P₀c))`. SixTrack `σ`, `pσ`; Xsuite `zeta`, `pζ`."""
struct SigmaPsigma <: LongitudinalConvention end

"""#3: `(s-ℓ, ΔP/P₀)`. PTC `TIME=FALSE`, and what Octopus tracks."""
struct PathLengthDelta <: LongitudinalConvention end

"""#4: `(-βcΔt, ΔP/P₀)`. Bmad `z`, `pz`; Xsuite `ξ`, `delta`."""
struct TimeDelta <: LongitudinalConvention end

const TIME_ENERGY = TimeEnergy()
const SIGMA_PSIGMA = SigmaPsigma()
const PATHLENGTH_DELTA = PathLengthDelta()
const TIME_DELTA = TimeDelta()

"""Section number in the theory note's table, so code and note can be matched."""
convention_number(::TimeEnergy) = 1
convention_number(::SigmaPsigma) = 2
convention_number(::PathLengthDelta) = 3
convention_number(::TimeDelta) = 4

"""
    tracking_convention()

The convention Octopus tracks in: [`PATHLENGTH_DELTA`](@ref), #3.

Stated as a function rather than left implicit because every conversion in a
map, an importer or a benchmark is *to* or *from* this one, and a reader should
not have to infer it from a sign somewhere.
"""
tracking_convention() = PATHLENGTH_DELTA

# ---------------------------------------------------------------------------
# Reference kinematics
# ---------------------------------------------------------------------------

"""
    reference_gamma(E0, mc2)

Reference Lorentz factor `γ₀ = E₀/mc²`.
"""
reference_gamma(E0, mc2) = E0 / mc2

"""
    reference_beta(E0, mc2)

Reference velocity `β₀`, computed as `√((γ-1)(γ+1))/γ` rather than
`√(1-1/γ²)`: the two agree analytically, and the first keeps its digits when
`γ` is large, which is the only regime this is ever used in.
"""
function reference_beta(E0, mc2)
    g = reference_gamma(E0, mc2)
    g >= 1 || throw(ArgumentError(
        "reference gamma must be at least 1; got E0/mc2 = $(g). " *
        "E0 is the TOTAL energy, not the kinetic energy"))
    return sqrt((g - 1) * (g + 1)) / g
end

"""
    reference_beta_gamma(E0, mc2) -> (β₀, γ₀)

Both reference factors at once, which is what every conversion needs.
"""
reference_beta_gamma(E0, mc2) = (reference_beta(E0, mc2), reference_gamma(E0, mc2))

# `1/(β₀γ₀) = mc²/(P₀c)`. Formed once per conversion and passed down, because it
# is the only place the rest mass enters and because the product is better
# conditioned than either factor alone at high energy.
@inline _inv_beta_gamma(beta0, gamma0) = inv(beta0 * gamma0)

# ---------------------------------------------------------------------------
# The two momentum relations of Section 2.2. Everything routes through `p_t`.
# ---------------------------------------------------------------------------

"""
    _delta_from_pt(pt, beta0, gamma0)

`δ = -1 + √((1/β₀ + p_t)² - 1/(β₀γ₀)²)`, note Section 2.2.
"""
@inline function _delta_from_pt(pt, beta0, gamma0)
    ibg = _inv_beta_gamma(beta0, gamma0)
    return -1 + sqrt((inv(beta0) + pt)^2 - ibg * ibg)
end

"""
    _pt_from_delta(delta, beta0, gamma0)

`p_t = -1/β₀ + √((1+δ)² + 1/(β₀γ₀)²)`, note Section 2.2. The exact inverse of
[`_delta_from_pt`](@ref); `dδ/dp_t = 1/β`, which is what makes each conversion's
longitudinal Jacobian `β·β⁻¹ = 1`.
"""
@inline function _pt_from_delta(delta, beta0, gamma0)
    ibg = _inv_beta_gamma(beta0, gamma0)
    return -inv(beta0) + sqrt((1 + delta)^2 + ibg * ibg)
end

"""
    _beta_of(delta, pt, beta0)

`β = Pc/E = (1+δ)/(1/β₀ + p_t)`: the *particle's* velocity, not the reference's.
This is the factor that distinguishes the four coordinate definitions from one
another, and the one that silently disappears in the ultrarelativistic limit.
"""
@inline _beta_of(delta, pt, beta0) = (1 + delta) / (inv(beta0) + pt)

"""
    particle_beta(convention, pz; beta0, gamma0)

The velocity `β` of a particle whose longitudinal momentum is `pz` in the given
convention. Useful on its own — a cavity's energy-to-momentum conversion needs
it — and shared with the coordinate conversions rather than recomputed.
"""
function particle_beta(conv::LongitudinalConvention, pz; beta0, gamma0)
    pt = _pt_of(conv, pz, beta0, gamma0)
    return _beta_of(_delta_from_pt(pt, beta0, gamma0), pt, beta0)
end

# momentum -> p_t, per convention
@inline _pt_of(::TimeEnergy, pz, beta0, gamma0) = pz
@inline _pt_of(::SigmaPsigma, pz, beta0, gamma0) = beta0 * pz
@inline _pt_of(::PathLengthDelta, pz, beta0, gamma0) = _pt_from_delta(pz, beta0, gamma0)
@inline _pt_of(::TimeDelta, pz, beta0, gamma0) = _pt_from_delta(pz, beta0, gamma0)

# p_t -> momentum, per convention
@inline _pz_of(::TimeEnergy, pt, beta0, gamma0) = pt
@inline _pz_of(::SigmaPsigma, pt, beta0, gamma0) = pt / beta0
@inline _pz_of(::PathLengthDelta, pt, beta0, gamma0) = _delta_from_pt(pt, beta0, gamma0)
@inline _pz_of(::TimeDelta, pt, beta0, gamma0) = _delta_from_pt(pt, beta0, gamma0)

# coordinate -> z1, per convention. `s` enters only for #3.
@inline _z1_of(::TimeEnergy, z, beta, beta0, s) = z
@inline _z1_of(::SigmaPsigma, z, beta, beta0, s) = z / beta0
@inline _z1_of(::PathLengthDelta, z, beta, beta0, s) = (z + s * (beta / beta0 - 1)) / beta
@inline _z1_of(::TimeDelta, z, beta, beta0, s) = z / beta

# z1 -> coordinate, per convention
@inline _z_of(::TimeEnergy, z1, beta, beta0, s) = z1
@inline _z_of(::SigmaPsigma, z1, beta, beta0, s) = beta0 * z1
@inline _z_of(::PathLengthDelta, z1, beta, beta0, s) = z1 * beta - s * (beta / beta0 - 1)
@inline _z_of(::TimeDelta, z1, beta, beta0, s) = beta * z1

# ---------------------------------------------------------------------------
# The public conversion
# ---------------------------------------------------------------------------

"""
    convert_longitudinal(from => to, z, pz; beta0, gamma0, s = 0)

Convert one longitudinal pair to another, exactly.

Written as a `Pair` so the direction is unmistakable at the call site:

```julia
z1, pt = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, δ;
                              beta0 = b0, gamma0 = g0)
z,  δ  = convert_longitudinal(TIME_ENERGY => PATHLENGTH_DELTA, z1, pt;
                              beta0 = b0, gamma0 = g0)
```

Every conversion routes through `p_t` and is **exactly symplectic**, because all
four pairs come from the same `(q_t, p_t)` by a generating function (note
Section 2). It is not a small-`δ` approximation and does not become one at large
amplitude.

`s` is the arc position, and it matters **only** for
[`PATHLENGTH_DELTA`](@ref): that convention's coordinate is `s - ℓ` rather than
a pure time, so it carries an explicit `s` offset. This is the trap the theory
note flags for PTC comparisons — PTC's `TIME=FALSE` variable is `-ℓ`, the same
dynamics with a different printed number. Leave `s` at its default and you are
working with `-ℓ`; pass the arc position and you get `s - ℓ`.

`beta0` and `gamma0` are the *reference* factors, from
[`reference_beta_gamma`](@ref); the particle's own `β` is recovered internally
and differs from `β₀` off-momentum, which is the entire content of the
distinction between conventions #1, #2 and #4.
"""
function convert_longitudinal(direction::Pair{<:LongitudinalConvention,<:LongitudinalConvention},
                              z, pz; beta0, gamma0, s=0)
    from, to = direction
    from === to && return (z, pz)
    pt = _pt_of(from, pz, beta0, gamma0)
    delta = _delta_from_pt(pt, beta0, gamma0)
    beta = _beta_of(delta, pt, beta0)
    z1 = _z1_of(from, z, beta, beta0, s)
    return (_z_of(to, z1, beta, beta0, s), _pz_of(to, pt, beta0, gamma0))
end
