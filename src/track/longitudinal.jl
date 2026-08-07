export LongitudinalConvention, TimeEnergy, SigmaPsigma, PathLengthDelta, TimeDelta,
       TIME_ENERGY, SIGMA_PSIGMA, PATHLENGTH_DELTA, TIME_DELTA,
       convention_number, tracking_convention,
       reference_gamma, reference_beta, reference_beta_gamma,
       reference_pair_residual,
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

"""Convention #1 singleton, [`TimeEnergy`](@ref): `(-cΔt, ΔE/(P₀c))`."""
const TIME_ENERGY = TimeEnergy()

"""Convention #2 singleton, [`SigmaPsigma`](@ref): `(-β₀cΔt, ΔE/(β₀P₀c))`."""
const SIGMA_PSIGMA = SigmaPsigma()

"""Convention #3 singleton, [`PathLengthDelta`](@ref): `(s-ℓ, ΔP/P₀)` — what Octopus tracks."""
const PATHLENGTH_DELTA = PathLengthDelta()

"""Convention #4 singleton, [`TimeDelta`](@ref): `(-βcΔt, ΔP/P₀)`."""
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
`√(1-1/γ²)`: the two agree analytically, and the first keeps its digits as
`γ → 1`.

The direction matters and this docstring used to state it backwards (it said
the form "keeps its digits when `γ` is large, which is the only regime this is
ever used in" — 2026-08-05_b audit, U14-6). The cancellation is `γ² - 1`, and
it is catastrophic as `γ → 1`, not as `γ → ∞`: at large `γ` the naive form
subtracts a *tiny* number from 1 and loses nothing. Measured relative error
against `BigFloat`, evaluated from the same stored `γ`:

| γ | `√((γ-1)(γ+1))/γ` | `√(1-1/γ²)` |
|---|---|---|
| 19569.5 | 3.2e-17 | 7.9e-17 |
| 293.092 | 3.9e-17 | 7.2e-17 |
| 2.66447 | 4.2e-17 | 4.2e-17 |
| 1.000000001 | 5.3e-17 | **7.5e-10** |

Everything at γ ≳ 2 is sub-ulp either way, so the *choice* is free there; the
whole gain is the bottom row. "The only regime this is ever used in" was also
wrong — this repository's own 2.5 GeV proton validation case runs at γ = 2.66,
which is what the F16 note in §5.4 is about.
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

"""
    reference_pair_residual(beta0, gamma0)

`1/β₀² - 1/(β₀γ₀)² - 1`, which is **exactly zero** for any physically possible
reference particle: `β₀` and `γ₀` are two views of one energy, related by
`β₀² = (γ₀²-1)/γ₀²`, so the quantity is an algebraic identity and not an
approximation. Nonzero means the pair describes two *different* particles.

This is not decoration. [`_delta_from_pt`](@ref) and [`_pt_from_delta`](@ref)
use the identity to stay cancellation-free, and they are mutual inverses only
where it holds — so an inconsistent pair silently produces a map that is not
symplectic. Measured on the `SymplecticityContract`'s thin-RF-cavity case,
whose fixture carried `beta0 = 0.99, gamma0 = 100.0` (residual 2.0e-2, a pair
no particle can have): `‖JᵀSJ - S‖` was 5.0e-3 against a 1.0e-8 tolerance. On
the *consistent* pair for that γ₀ the same case measures 1.8e-13 — 800× better
than the pre-rewrite forms managed (2026-08-05_b audit, U14-4).

Evaluated in the well-conditioned `(a-ibg)(a+ibg) - 1` form, so a consistent
pair returns 0 or one ulp rather than a cancellation artefact.
"""
function reference_pair_residual(beta0, gamma0)
    a = inv(beta0)
    ibg = _inv_beta_gamma(beta0, gamma0)
    return (a - ibg) * (a + ibg) - 1
end

# The refusal, for constructors that take the pair directly. Construction time,
# never per particle: `_delta_from_pt` runs inside CUDA kernels, where a throw
# aborts the whole launch (U14-3).
#
# 1e-10 rather than a few ulp: a caller who writes beta0 out to ~11 digits is
# doing something reasonable, and the resulting defect stays below the
# symplecticity tolerances this repository holds its maps to. Beyond that the
# map is measurably non-canonical and saying so is worth more than accepting it.
const _REFERENCE_PAIR_TOLERANCE = 1.0e-10

function _check_reference_pair(beta0, gamma0; source::AbstractString)
    residual = reference_pair_residual(beta0, gamma0)
    abs(real(residual)) <= _REFERENCE_PAIR_TOLERANCE || throw(ArgumentError(
        "$(source): beta0 = $(beta0) and gamma0 = $(gamma0) are not the same " *
        "reference particle. They must satisfy beta0^2 = (gamma0^2-1)/gamma0^2 " *
        "exactly; this pair leaves 1/beta0^2 - 1/(beta0*gamma0)^2 - 1 = " *
        "$(residual), and gamma0 = $(gamma0) implies beta0 = " *
        "$(sqrt((gamma0 - 1) * (gamma0 + 1)) / gamma0). The longitudinal " *
        "conversions rely on that identity to stay cancellation-free and are " *
        "mutual inverses only where it holds, so an inconsistent pair gives a " *
        "map that is not symplectic. Derive both from the energy with " *
        "reference_beta_gamma(E0, mc2)."))
    return nothing
end

# `1/(β₀γ₀) = mc²/(P₀c)`. Formed once per conversion and passed down, because it
# is the only place the rest mass enters and because the product is better
# conditioned than either factor alone at high energy.
@inline _inv_beta_gamma(beta0, gamma0) = inv(beta0 * gamma0)

# ---------------------------------------------------------------------------
# The two momentum relations of Section 2.2. Everything routes through `p_t`.
# ---------------------------------------------------------------------------

"""
    _delta_from_pt(pt, beta0, gamma0)

`δ = -1 + √((1/β₀ + p_t)² - 1/(β₀γ₀)²)`, note Section 2.2, evaluated in the
cancellation-free form below.

Written as `δ = u/(1 + √(1+u))` with `u = 2p_t/β₀ + p_t²`. The two agree
because `1/β₀² - 1/(β₀γ₀)² = 1` *exactly* — it is `(γ₀²-1)/(β₀²γ₀²)` with
`β₀² = (γ₀²-1)/γ₀²` — so the radicand is `1 + u` and the literal form's
`-1 + √(1+u)` subtracts two quantities that are both ≈ 1. That costs ~1 ulp
of the *operands*, i.e. ~1e-16 **absolute** no matter how small δ is, so the
relative accuracy degrades as `1/δ`: measured against a BigFloat evaluation
from `E₀/mc²` at 10 GeV e⁻, the literal form is wrong by 5.6e-11 relative at
`p_t = 1e-6` and 8.9e-5 at `p_t = 1e-12`, and the δ→p_t→δ round trip returns
**zero** for δ = 1e-16. The form below is within 1 ulp at every amplitude
tested (1e-2 down to 1e-12, three energies spanning γ₀ = 2.66 to 19569) and
its round trip is bit-exact. Using the identity is not merely equivalent —
it is *better* than the literal form even in exact arithmetic on the stored
`beta0`, because the identity is the exact physical relation and so repairs
`beta0`'s own rounding instead of inheriting it (2026-08-05_b audit, U14-4).

`gamma0` is unused and kept for signature symmetry with [`_pt_from_delta`]
(@ref) and the `_pz_of` / `_pt_of` dispatch tables.
"""
@inline function _delta_from_pt(pt, beta0, gamma0)
    u = 2 * pt / beta0 + pt * pt
    rad = 1 + u
    # A particle decelerated below rest energy drives the radicand negative --
    # it happens at p_t = -1/beta0 + 1/(beta0*gamma0), reachable by anything
    # outside the RF bucket whose delta walks to -1, and `_rf_kick` runs this
    # per particle per turn. `sqrt` THREW a DomainError there, which is the one
    # outcome this repository's loss design cannot use: a dead particle is
    # defined by a NON-FINITE COORDINATE, and `allow_lost_particles` exists so a
    # run continues over the survivors. A throw is invisible to that machinery,
    # and inside a CUDA kernel it aborted the entire launch with a
    # KernelException rather than losing one particle (2026-08-05_b audit,
    # U14-3). NaN is also the better device IR: it removes a throw from a
    # kernel-reachable branch.
    #
    # `real(rad)`, not `rad`: this file's number type is not always real. The
    # parameter-derivative sweep differentiates by COMPLEX STEP, so a bare
    # `rad < 0` raises a MethodError on a complex argument and the element
    # silently leaves the differentiable set. That is the recurring bug this
    # repository has paid for before -- `_curv_sin`, `_curv_vers`,
    # `_atan_over`, `_sol_log_over_h` and `abs(hL) < pi/2` each needed the same
    # treatment. Caught here by the sweep's own floor dropping 25 -> 21.
    return real(rad) < 0 ? oftype(rad, NaN) : u / (1 + sqrt(rad))
end

"""
    _pt_from_delta(delta, beta0, gamma0)

`p_t = -1/β₀ + √((1+δ)² + 1/(β₀γ₀)²)`, note Section 2.2. The exact inverse of
[`_delta_from_pt`](@ref); `dδ/dp_t = 1/β`, which is what makes each conversion's
longitudinal Jacobian `β·β⁻¹ = 1`.

Written cancellation-free as `p_t = w/(1/β₀ + √((1+δ)² + 1/(β₀γ₀)²))` with
`w = 2δ + δ²`, by the same `1/β₀² - 1/(β₀γ₀)² = 1` identity that
[`_delta_from_pt`](@ref) uses — see its docstring for the measurements. This
form is what makes the round trip through `p_t` bit-exact; the literal form
lost all relative accuracy below δ ≈ 1e-14 (2026-08-05_b audit, U14-4).

The radicand is kept in the `(1+δ)² + 1/(β₀γ₀)²` form rather than the
algebraically equal `1/β₀² + w`: only the first is *provably* non-negative in
floating point. At δ ≈ -1 the second is a difference of two quantities that
are both ≈ 1 and can round below zero, which would put a `DomainError` back
into a kernel-reachable branch — the exact failure U14-3 removed from
[`_delta_from_pt`](@ref). The cancellation this lead is about lives in the
*numerator*, and that is where the rewrite is; the denominator is ≈ 2/β₀ and
well conditioned, so evaluating it the safe way costs nothing.
"""
@inline function _pt_from_delta(delta, beta0, gamma0)
    ibg = _inv_beta_gamma(beta0, gamma0)
    w = 2 * delta + delta * delta
    return w / (inv(beta0) + sqrt((1 + delta)^2 + ibg * ibg))
end

"""
    _beta_of(delta, pt, beta0)

`β = Pc/E = (1+δ)/(1/β₀ + p_t)`: the *particle's* velocity, not the reference's.
This is the factor that distinguishes the four coordinate definitions from one
another, and the one that silently disappears in the ultrarelativistic limit.

Evaluated as `β₀(1+δ)/(1 + β₀p_t)`, which is the same expression with the
reciprocal cleared. That makes the reference particle EXACT: at `δ = p_t = 0`
this returns `beta0` itself, where the literal form returns `1/(1/β₀)` — a
double reciprocal that is off by an ulp for most `β₀`. The old inexactness in
[`_pt_from_delta`](@ref) used to cancel that ulp by accident; making that
conversion bit-exact at zero (U14-4) exposed it, and "a particle at the design
momentum moves at the design velocity" is worth having exactly rather than
nearly. One division instead of two, as a side effect.
"""
@inline _beta_of(delta, pt, beta0) = beta0 * (1 + delta) / (1 + beta0 * pt)

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
