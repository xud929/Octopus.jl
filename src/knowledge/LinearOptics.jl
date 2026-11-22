export EdwardsTengTwiss, CanonicalDispersion, LinearOptics, advance_phase, slope_dispersion, dispersion_h

# ---------------------------------------------------------------------------
# The shared linear-optics value object (design: docs/design/linear_optics.md).
#
# The quintuple (beta, alpha, zeta, eta, R) that fixes the linear optics at a
# lattice point is consumed by `Linear6DSpec`, `Beam`, `ChromaticityKickSpec`,
# `LumpedRadSpec`, `GaussianStrongBeamSpec` and the three elementary maps, and is
# read back by `TwissDispersionAnalysis`. These three plain value types carry
# it once, in the conventions the analysis reports (docs/theory/twiss_dispersion.md:
# Edwards-Teng forms (T2)-(T4), canonical dispersion (D1)-(D3)), and every
# consumer FLATTENS the object into its own stored parameters at construction
# (D3 of the design note). Nothing here is stored in an `ElementSpec`, reaches
# a kernel, or changes the runtime layer.
#
# Conventions, stated once (the consumers' ParamMeta repeat them, F-99):
#   * `beta`, `alpha` are the Twiss functions of the three canonically
#     decoupled modes, (x, y, z); the third is the longitudinal mode, which
#     the coupling matrix never touches.
#   * `R = (r1, r2, r3, r4)` is the Edwards-Teng matrix R = [r1 r2; r3 r4] of
#     (T2), lambda = 1/sqrt(1 + det R) (T3); `form` 1 is V1 = lambda [I adj(R); -R I]
#     (`XY_MODEA`), form 2 is V2 = lambda [adj(R) I; I -R] (`XY_MODEB`).
#   * `zeta`, `eta` are the CANONICAL crab and momentum dispersions (D1)-(D3),
#     with h = 1 - zeta' S4 eta and S4 = blockdiag([0 1; -1 0], [0 1; -1 0]);
#     the slope dispersion d = eta / h of Xsuite and MAD-X is a derived view.
#   * The normalizer of a point is N = M_zeta M_eta V_form(R) B(beta, alpha),
#     the order `Linear6DSpec` and `Beam` apply.
# ---------------------------------------------------------------------------

# Tuple coercion shared by the three constructors: a fixed length, one numeric
# type, every entry finite (`isfinite` on the real part for complex or dual
# inputs, which the element specs accept for differentiation).
function _optics_tuple(value, n::Int, ::Type{T}, name::Symbol) where {T<:Number}
    (value isa Tuple || value isa AbstractVector) || throw(ArgumentError(
        "$(name) must be a length-$(n) tuple or vector; got $(repr(value))"))
    length(value) == n || throw(ArgumentError(
        "$(name) must have length $(n); got length $(length(value))"))
    t = ntuple(i -> T(value[i]), n)
    all(x -> isfinite(real(x)), t) || throw(ArgumentError("$(name) must be finite; got $(t)"))
    return t
end

# The untyped forms promote their inputs over a Float64 floor and never narrow,
# the one numeric-type rule of the element specs (docs/guides/elements.md).
_optics_eltype(values...) = promote_type(Float64, map(v -> v === nothing ? Float64 : _optics_value_eltype(v), values)...)
_optics_value_eltype(v::Number) = typeof(v)
_optics_value_eltype(v) = isempty(v) ? Float64 : promote_type(map(typeof, collect(v))...)

"""
    EdwardsTengTwiss{T=Float64}(; beta, alpha=(0, 0, 0), R=(0, 0, 0, 0), form=1)

The coupled Twiss functions of one lattice point in the Edwards-Teng
parameterization of `docs/theory/twiss_dispersion.md`, section 4: `beta` and
`alpha` are 3-tuples over the three canonically decoupled modes (x, y, z), the
third being the longitudinal mode (`beta[3] = sigma_z / sigma_delta`,
`alpha[3] = 0` for an upright longitudinal ellipse); `R = (r1, r2, r3, r4)` is
the Edwards-Teng matrix R = [r1 r2; r3 r4] of equation (T2) coupling the two
transverse modes, with the normaliser lambda = 1/sqrt(1 + det R) of (T3); `form`
selects V1 = lambda [I adj(R); -R I] (1, the default, `XYCoupling`'s
`XY_MODEA`) or V2 = lambda [adj(R) I; I -R] (2, `XY_MODEB`). The two forms
describe the same normalizer with the mode columns exchanged, (T4); form 2 is
the one that stays finite where the oscillation dominating x is the second
eigenmode. The longitudinal mode is not coupled by R.

Refused by name at construction: a non-positive or non-finite `beta`, a
non-finite `alpha` or `R`, `1 + det R <= 0` (no real normaliser, the
`:form_inadmissible` condition of the analysis), and a `form` other than 1
or 2. Without the explicit `{T}` the entries promote over a `Float64` floor.

The map `Linear6DSpec` builds from this object stores the Edwards-Teng BLOCK
`C = adj(R) / sqrt(1 + det R)` (its `R1`/`R2` parameters), `Beam`,
`ChromaticityKickSpec`, `LumpedRadSpec` and `XYCouplingSpec` store `R` itself;
the flattening is exact in both directions (`R = adj(C) / sqrt(1 - det C)`).
See [`LinearOptics`](@ref).
"""
struct EdwardsTengTwiss{T<:Number}
    beta::NTuple{3,T}
    alpha::NTuple{3,T}
    R::NTuple{4,T}
    form::Int
    function EdwardsTengTwiss{T}(beta::NTuple{3,T}, alpha::NTuple{3,T}, R::NTuple{4,T}, form::Int) where {T<:Number}
        all(b -> real(b) > 0, beta) || throw(ArgumentError(
            "EdwardsTengTwiss: beta must be positive in every plane; got $(beta)"))
        form in (1, 2) || throw(ArgumentError(
            "EdwardsTengTwiss: form must be 1 or 2 (the Edwards-Teng forms V1 and V2 of the theory note's (T2)); got $(repr(form))"))
        detR = R[1] * R[4] - R[2] * R[3]
        real(1 + detR) > 0 || throw(ArgumentError(
            "EdwardsTengTwiss: 1 + det R must be positive for a real normaliser lambda = 1/sqrt(1 + det R) (theory note (T3)); got det R = $(detR) from R = $(R)"))
        return new{T}(beta, alpha, R, form)
    end
end

function EdwardsTengTwiss{T}(; beta, alpha=(0, 0, 0), R=(0, 0, 0, 0), form::Integer=1) where {T<:Number}
    return EdwardsTengTwiss{T}(_optics_tuple(beta, 3, T, :beta), _optics_tuple(alpha, 3, T, :alpha),
                               _optics_tuple(R, 4, T, :R), Int(form))
end
EdwardsTengTwiss(; beta, alpha=(0, 0, 0), R=(0, 0, 0, 0), form::Integer=1) =
    EdwardsTengTwiss{_optics_eltype(beta, alpha, R)}(; beta, alpha, R, form)

"""
    CanonicalDispersion{T=Float64}(; zeta=(0, 0, 0, 0), eta=(0, 0, 0, 0))
    CanonicalDispersion{T=Float64}(; zeta=(0, 0, 0, 0), slope)

The canonical crab dispersion `zeta` and momentum dispersion `eta` of one
lattice point, each a 4-tuple over `(x, px, y, py)`, in the convention of
`docs/theory/twiss_dispersion.md` equations (D1)-(D3): zeta = dr/dz and
eta = dr/dpz at fixed canonically decoupled coordinates, realised by the
ordered product M = M_zeta M_eta, which also scales `pz` by
h = 1 - zeta' S4 eta ([`dispersion_h`](@ref)). This is the convention the
`TwissDispersionAnalysis` reports and every Octopus consumer stores
(`Linear6DSpec`, `Beam`, `ChromaticityKickSpec`, `LumpedRadSpec`,
`MomentumDispersionSpec`, `CrabDispersionSpec`). The SLOPE dispersion
d = eta / h that Xsuite (`dx`, `dpx`, ...) and MAD-X report on a coasting
cell equals `eta` only when no crab dispersion acts beside it (h = 1); give it
through `slope` and the constructor converts with h = 1/(1 + zeta' S4 d),
eta = h d (the inverse of (D8)). `eta` beside `slope` is refused by name, as
is a slope whose `1 + zeta' S4 d` vanishes. [`slope_dispersion`](@ref) is the
converse view. Without the explicit `{T}` the entries promote over a
`Float64` floor. See [`LinearOptics`](@ref).
"""
struct CanonicalDispersion{T<:Number}
    zeta::NTuple{4,T}
    eta::NTuple{4,T}
end

# zeta' S4 eta with S4 = blockdiag([0 1; -1 0], [0 1; -1 0]) on (x, px, y, py):
# the bilinear form behind h = 1 - zeta' S4 eta of (D3) and the inverse
# conversion of (D8).
_s4_form(a::NTuple{4}, b::NTuple{4}) = a[1] * b[2] - a[2] * b[1] + a[3] * b[4] - a[4] * b[3]

function CanonicalDispersion{T}(; zeta=(0, 0, 0, 0), eta=nothing, slope=nothing) where {T<:Number}
    z = _optics_tuple(zeta, 4, T, :zeta)
    if slope === nothing
        e = _optics_tuple(something(eta, (0, 0, 0, 0)), 4, T, :eta)
    else
        eta === nothing || throw(ArgumentError(
            "CanonicalDispersion takes either eta (canonical) or slope (eta / h, the Xsuite and MAD-X dispersion), not both"))
        d = _optics_tuple(slope, 4, T, :slope)
        denom = 1 + _s4_form(z, d)
        iszero(denom) && throw(ArgumentError(
            "CanonicalDispersion: the slope dispersion cannot be converted, 1 + zeta' S4 slope vanishes for zeta = $(z), slope = $(d)"))
        h = inv(denom)
        e = ntuple(i -> h * d[i], 4)
    end
    return CanonicalDispersion{T}(z, e)
end
CanonicalDispersion(; zeta=(0, 0, 0, 0), eta=nothing, slope=nothing) =
    CanonicalDispersion{_optics_eltype(zeta, eta, slope)}(; zeta, eta, slope)

"""
    dispersion_h(d::CanonicalDispersion) -> h

The longitudinal factor h = 1 - zeta' S4 eta of equation (D3) of
`docs/theory/twiss_dispersion.md`: the scale the dispersion transformation
M_zeta M_eta applies to `pz`, and the ratio between the canonical momentum
dispersion `eta` and the slope dispersion `eta / h` ([`slope_dispersion`](@ref)).
Equal to 1 whenever crab or momentum dispersion vanishes.
"""
dispersion_h(d::CanonicalDispersion) = 1 - _s4_form(d.zeta, d.eta)

"""
    slope_dispersion(d::CanonicalDispersion) -> NTuple{4}

The slope dispersion d = eta / h of a [`CanonicalDispersion`](@ref), the
quantity Xsuite's `dx, dpx, dy, dpy` and MAD-X's deltap dispersion report on
a coasting cell (equation (D8) of `docs/theory/twiss_dispersion.md`); equal to
the canonical `eta` when no crab dispersion acts beside it. Refused when h
vanishes.
"""
function slope_dispersion(d::CanonicalDispersion)
    h = dispersion_h(d)
    iszero(h) && throw(ArgumentError("slope_dispersion: h = 1 - zeta' S4 eta vanishes for $(d); the slope eta / h is undefined"))
    return ntuple(i -> d.eta[i] / h, 4)
end

"""
    LinearOptics(twiss::EdwardsTengTwiss, dispersion=CanonicalDispersion(); mu=nothing, s=nothing, frame=nothing)
    LinearOptics(; beta, alpha=(0,0,0), R=(0,0,0,0), form=1, zeta=(0,0,0,0), eta=(0,0,0,0),
                   slope=nothing, mu=nothing, s=nothing, frame=nothing)

The linear optics of one lattice point: an [`EdwardsTengTwiss`](@ref) and a
[`CanonicalDispersion`](@ref), optionally placed by its phases. Together the
two parts fix the point's normalizer N = M_zeta M_eta V_form(R) B(beta, alpha)
completely (the Twiss of the three decoupled modes, the coupling between the
two transverse modes, the coupling between them and the longitudinal mode),
so one object feeds every consumer of these quantities through its `optics`
keyword, the recommended spelling of linear optics in Octopus (design D15: new scripts,
examples and documentation give the optics as a point; the flat keywords
remain as the stored representation, what `params(spec)` holds and the raw
`ElementSpec{kind}(; ...)` form accepts, and as the spelling of scripts written
before the point), each consumer flattening it into its own parameters: `Linear6DSpec(o1, o2)`
(a transfer between two points), `Beam(N, policy; optics = o, sigma | emit)`
(a matched beam), `ChromaticityKickSpec(; xi, optics = o)`,
`LumpedRadSpec(; damping_turns, optics = o)`, `GaussianStrongBeamSpec(; kbb,
optics = o, sigma, ns, sigz)` (a dispersive point there needs `sigma_delta`;
the deprecated `ThinStrongBeamSpec(; kbb, optics = o, sigma)` still refuses
one), and [`linear_optics`](@ref) builds one from a
`TwissDispersionResult`. The object form and the flat keywords produce the
same spec or beam exactly; giving both is refused by name.

`mu` is the 3-tuple of phases of the decoupled modes at the point, in radians,
unwrapped, acting as the point's position: `Linear6DSpec(o1, o2)` advances by
`o2.mu .- o1.mu`, and [`advance_phase`](@ref) gives "the same point one turn
later" for a one-turn map, `Linear6DSpec(o, advance_phase(o, 2pi .* tune))`.
A phase is relative to a reference, so `mu` requires `frame`, a `Symbol`
naming that reference, and two points are subtracted only when their frames
agree; without `mu` a transfer needs an explicit `dmu`. `s` is an optional
position label in metres, bookkeeping that nothing reads. Without the
explicit `{T}` the parts promote to one numeric type over a `Float64` floor.
Design: `docs/design/linear_optics.md`.
"""
struct LinearOptics{T<:Number}
    twiss::EdwardsTengTwiss{T}
    dispersion::CanonicalDispersion{T}
    mu::Union{Nothing,NTuple{3,T}}
    s::Union{Nothing,T}
    frame::Union{Nothing,Symbol}
    function LinearOptics{T}(twiss::EdwardsTengTwiss{T}, dispersion::CanonicalDispersion{T},
                             mu::Union{Nothing,NTuple{3,T}}, s::Union{Nothing,T}, frame::Union{Nothing,Symbol}) where {T<:Number}
        mu === nothing || frame !== nothing || throw(ArgumentError(
            "LinearOptics: mu (the phases) requires frame, the Symbol naming the reference the phases are measured from; two points are subtracted only within one frame"))
        return new{T}(twiss, dispersion, mu, s, frame)
    end
end

_convert_twiss(::Type{T}, t::EdwardsTengTwiss) where {T} =
    EdwardsTengTwiss{T}(map(T, t.beta), map(T, t.alpha), map(T, t.R), t.form)
_convert_dispersion(::Type{T}, d::CanonicalDispersion) where {T} =
    CanonicalDispersion{T}(map(T, d.zeta), map(T, d.eta))

function LinearOptics{T}(twiss::EdwardsTengTwiss, dispersion::CanonicalDispersion=CanonicalDispersion{T}();
                         mu=nothing, s=nothing, frame=nothing) where {T<:Number}
    frame === nothing || frame isa Symbol || throw(ArgumentError("LinearOptics: frame must be a Symbol or nothing; got $(repr(frame))"))
    m = mu === nothing ? nothing : _optics_tuple(mu, 3, T, :mu)
    pos = s === nothing ? nothing : T(s)
    pos === nothing || isfinite(real(pos)) || throw(ArgumentError("LinearOptics: s must be finite; got $(s)"))
    return LinearOptics{T}(_convert_twiss(T, twiss), _convert_dispersion(T, dispersion), m, pos, frame)
end
function LinearOptics(twiss::EdwardsTengTwiss{T1}, dispersion::CanonicalDispersion{T2}=CanonicalDispersion{T1}();
                      mu=nothing, s=nothing, frame=nothing) where {T1,T2}
    T = promote_type(T1, T2, _optics_eltype(mu, s))
    return LinearOptics{T}(twiss, dispersion; mu, s, frame)
end
function LinearOptics{T}(; beta, alpha=(0, 0, 0), R=(0, 0, 0, 0), form::Integer=1,
                         zeta=(0, 0, 0, 0), eta=nothing, slope=nothing, mu=nothing, s=nothing, frame=nothing) where {T<:Number}
    return LinearOptics{T}(EdwardsTengTwiss{T}(; beta, alpha, R, form), CanonicalDispersion{T}(; zeta, eta, slope); mu, s, frame)
end
function LinearOptics(; beta, alpha=(0, 0, 0), R=(0, 0, 0, 0), form::Integer=1,
                      zeta=(0, 0, 0, 0), eta=nothing, slope=nothing, mu=nothing, s=nothing, frame=nothing)
    T = _optics_eltype(beta, alpha, R, zeta, eta, slope, mu, s)
    return LinearOptics{T}(; beta, alpha, R, form, zeta, eta, slope, mu, s, frame)
end

"""
    advance_phase(o::LinearOptics, dmu) -> LinearOptics

The same optics with the phases advanced by `dmu` (a 3-tuple, radians): the
point "one turn later" for a one-turn map, `Linear6DSpec(o, advance_phase(o, 2pi .* tune))`,
or a point further along a lattice with unchanged Twiss. Requires `o.mu`;
keeps `s` and `frame`.
"""
function advance_phase(o::LinearOptics{T}, dmu) where {T}
    o.mu === nothing && throw(ArgumentError("advance_phase: the optics carry no phases (mu = nothing); give mu and frame at construction"))
    d = _optics_tuple(dmu, 3, T, :dmu)
    return LinearOptics{T}(o.twiss, o.dispersion, ntuple(i -> o.mu[i] + d[i], 3), o.s, o.frame)
end

"""
    _phase_advance(o1, o2, dmu) -> NTuple{3}

The phase advance a transfer from `o1` to `o2` uses (design D5): `o2.mu .- o1.mu`
when both points carry phases in one frame and `dmu` is `nothing`; `dmu`
when the points carry no phases; a disagreement between a given `dmu` and the
points' own difference is refused, as is a pair in different frames or a pair
of which only one carries phases while `dmu` is absent.
"""
function _phase_advance(o1::LinearOptics, o2::LinearOptics, dmu)
    have = o1.mu !== nothing && o2.mu !== nothing
    if have
        o1.frame === o2.frame || throw(ArgumentError(
            "the two optics points carry phases in different frames ($(repr(o1.frame)) and $(repr(o2.frame))); phases are subtracted only within one frame"))
        diff = ntuple(i -> o2.mu[i] - o1.mu[i], 3)
        dmu === nothing && return diff
        given = _optics_tuple(dmu, 3, promote_type(eltype(diff), _optics_eltype(dmu)), :dmu)
        all(i -> isapprox(given[i], diff[i]; rtol=1e-12, atol=1e-12), 1:3) || throw(ArgumentError(
            "dmu = $(given) disagrees with the points' own phase difference $(diff); give one or the other"))
        return given
    end
    dmu === nothing && throw(ArgumentError(
        "the transfer needs a phase advance: give dmu, or give both optics points mu and a common frame"))
    (o1.mu === nothing) == (o2.mu === nothing) || throw(ArgumentError(
        "one optics point carries phases and the other does not; give both or neither (dmu was given, so neither is needed)"))
    return _optics_tuple(dmu, 3, _optics_eltype(dmu), :dmu)
end

Base.isapprox(a::EdwardsTengTwiss, b::EdwardsTengTwiss; kwargs...) =
    a.form == b.form && all(isapprox(x, y; kwargs...) for (x, y) in zip((a.beta..., a.alpha..., a.R...), (b.beta..., b.alpha..., b.R...)))
Base.isapprox(a::CanonicalDispersion, b::CanonicalDispersion; kwargs...) =
    all(isapprox(x, y; kwargs...) for (x, y) in zip((a.zeta..., a.eta...), (b.zeta..., b.eta...)))
function Base.isapprox(a::LinearOptics, b::LinearOptics; kwargs...)
    isapprox(a.twiss, b.twiss; kwargs...) && isapprox(a.dispersion, b.dispersion; kwargs...) || return false
    a.frame === b.frame || return false
    (a.mu === nothing) == (b.mu === nothing) || return false
    a.mu === nothing || all(isapprox(x, y; kwargs...) for (x, y) in zip(a.mu, b.mu)) || return false
    (a.s === nothing) == (b.s === nothing) || return false
    return a.s === nothing || isapprox(a.s, b.s; kwargs...)
end

function Base.show(io::IO, t::EdwardsTengTwiss)
    print(io, "EdwardsTengTwiss(beta=", t.beta, ", alpha=", t.alpha, ", R=", t.R, ", form=", t.form, ")")
end
function Base.show(io::IO, d::CanonicalDispersion)
    print(io, "CanonicalDispersion(zeta=", d.zeta, ", eta=", d.eta, ")")
end
function Base.show(io::IO, o::LinearOptics)
    print(io, "LinearOptics(", o.twiss, ", ", o.dispersion)
    o.mu === nothing || print(io, ", mu=", o.mu)
    o.s === nothing || print(io, ", s=", o.s)
    o.frame === nothing || print(io, ", frame=", repr(o.frame))
    print(io, ")")
end

# An Edwards-Teng form value as the consumers store it: 1 or 2, an Integer that
# is not a Bool (`Linear6DSpec` has its own `_linear6d_form` with its own wording).
function _optics_form(value, who::AbstractString, name::Symbol=:form)
    (value isa Integer && !(value isa Bool) && value in (1, 2)) || throw(ArgumentError(
        "$(who) $(name) must be 1 or 2 (the Edwards-Teng forms V1 and V2 of the theory note's (T2)); got $(repr(value))"))
    return Int(value)
end

"""
    _resolve_optics_keywords(who, optics, given, defaults; require_beta=true)

The one flattening rule of the element constructors that take `beta, alpha,
zeta, eta, R` (design docs/design/linear_optics.md D3-D4): without `optics`
the flat keywords apply with their `defaults` (a `nothing` entry of `given`
means "not given") and the form is 1: `form=1` is accepted as the explicit
spelling of that default, `form=2` is refused by name, since form 2 reaches
these consumers through a `LinearOptics` point (the raw `ElementSpec{kind}(;
form=2)` spells it directly; design D11). With a `LinearOptics` every flat
keyword must be absent (refused by name otherwise) and the point's parts, its
form included, are returned. Returns the NamedTuple `(beta, alpha, zeta, eta,
R, form)`; `given` may omit `form`.
"""
function _resolve_optics_keywords(who::String, optics, given::NamedTuple, defaults::NamedTuple;
                                  require_beta::Bool=true)
    given_form = get(given, :form, nothing)
    if optics === nothing
        if given.beta === nothing && require_beta
            throw(ArgumentError("$(who) requires beta (or a LinearOptics through optics)"))
        end
        form = given_form === nothing ? 1 : _optics_form(given_form, who)
        form == 1 || throw(ArgumentError(
            "$(who) couples in Edwards-Teng form 1 from its flat keywords; form 2 reaches it through a LinearOptics " *
            "point in form 2 (optics=LinearOptics(; ..., form=2)) or through the raw ElementSpec form (form=2)"))
        return (beta=something(given.beta, defaults.beta), alpha=something(given.alpha, defaults.alpha),
                zeta=something(given.zeta, defaults.zeta), eta=something(given.eta, defaults.eta),
                R=something(given.R, defaults.R), form=1)
    end
    optics isa LinearOptics || throw(ArgumentError(
        "$(who) optics must be a LinearOptics; got $(typeof(optics))"))
    clash = [String(k) for (k, v) in pairs(given) if v !== nothing]
    isempty(clash) || throw(ArgumentError(
        "$(who) takes beta, alpha, zeta, eta, R and the form from the LinearOptics object given as optics; " *
        join(clash, ", ") * " cannot be given beside it (give one form)"))
    return (beta=optics.twiss.beta, alpha=optics.twiss.alpha, zeta=optics.dispersion.zeta,
            eta=optics.dispersion.eta, R=optics.twiss.R, form=optics.twiss.form)
end
