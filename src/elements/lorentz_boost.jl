export LorentzBoostSpec, RevLorentzBoostSpec, LorentzBoost, RevLorentzBoost

abstract type LorentzBoostSpec{T} end
abstract type RevLorentzBoostSpec{T} end

# Raw flexible specs inherit the same method default as the friendly
# constructors, so metadata-driven and direct ElementSpec construction agree.
default_method(::Type{ElementSpec{:lorentz_boost}}) = NonSymplectic6DMap()
default_method(::Type{ElementSpec{:rev_lorentz_boost}}) = NonSymplectic6DMap()

"""
    LorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...)
    LorentzBoostSpec{T}(angle; kwargs...)

Create an `ElementSpec{:lorentz_boost}` for a zero-length Lorentz boost
coordinate transformation. `angle` is in radians. Extra keyword arguments are
stored as descriptive spec metadata.

Numeric type: the untyped form compiles in `numeric_type(spec)`, the promotion
of the stored parameters over a `Float64` floor, so a `Float32` angle gives a
`Float64` boost and a dual or complex angle widens it (until 2026-10-16 the
boost's type followed `typeof(float(angle))` alone, the crab cavity's old rule,
so a `Float32` angle made a `Float32` boost silently); `LorentzBoostSpec{Float32}`
is the Float32 boost, the typed form every kind has (one precision rule, owner
decision 2026-10-16). A beam whose element type differs from the boost's is
refused by name when a task compiles the line.
"""
function LorentzBoostSpec(angle::Number; numeric_type=nothing, tracking_method=NonSymplectic6DMap(), kwargs...)
    numeric_type === nothing ||
        return LorentzBoostSpec{numeric_type}(angle; tracking_method=tracking_method, kwargs...)
    return ElementSpec{:lorentz_boost}(_spec_params(; angle=float(angle), tracking_method=tracking_method, kwargs...))
end
(::Type{LorentzBoostSpec{T}})(angle::Number; tracking_method=NonSymplectic6DMap(), kwargs...) where {T} =
    ElementSpec{:lorentz_boost}(_typed_spec_params(T; angle=float(angle), tracking_method=tracking_method, kwargs...))

# Keyword form: reflection builds every kind by keyword alone, and a spec
# rebuilt from `parameter_schema` must round trip — this kind's probe
# baseline threw as a silent skip until the parameter contract learned to
# report broken kinds (2026-08-05 audit, U3-7).
LorentzBoostSpec(; angle, kwargs...) = LorentzBoostSpec(angle; kwargs...)
(::Type{LorentzBoostSpec{T}})(; angle, kwargs...) where {T} = LorentzBoostSpec{T}(angle; kwargs...)

"""
    RevLorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...)
    RevLorentzBoostSpec{T}(angle; kwargs...)

Create an `ElementSpec{:rev_lorentz_boost}` for the reverse zero-length Lorentz
boost coordinate transformation. `angle` is in radians. Extra keyword arguments
are stored as descriptive spec metadata. Numeric type as for `LorentzBoostSpec`:
the untyped form compiles in `numeric_type(spec)` (a `Float64` floor),
`RevLorentzBoostSpec{Float32}` is the Float32 boost.
"""
function RevLorentzBoostSpec(angle::Number; numeric_type=nothing, tracking_method=NonSymplectic6DMap(), kwargs...)
    numeric_type === nothing ||
        return RevLorentzBoostSpec{numeric_type}(angle; tracking_method=tracking_method, kwargs...)
    return ElementSpec{:rev_lorentz_boost}(_spec_params(; angle=float(angle), tracking_method=tracking_method, kwargs...))
end
(::Type{RevLorentzBoostSpec{T}})(angle::Number; tracking_method=NonSymplectic6DMap(), kwargs...) where {T} =
    ElementSpec{:rev_lorentz_boost}(_typed_spec_params(T; angle=float(angle), tracking_method=tracking_method, kwargs...))

# Keyword form — same round-trip rule as LorentzBoostSpec above.
RevLorentzBoostSpec(; angle, kwargs...) = RevLorentzBoostSpec(angle; kwargs...)
(::Type{RevLorentzBoostSpec{T}})(; angle, kwargs...) where {T} = RevLorentzBoostSpec{T}(angle; kwargs...)

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    LorentzBoost(angle)

Runtime zero-length Lorentz boost coordinate transformation. This follows
Hirata's nonlinear six-dimensional crossing-angle transformation. In the
accelerator variables used here it is quasi-symplectic (Jacobian determinant
`sec(angle)^3`), not a canonical symplectic map by itself; the reverse map
restores the phase-space volume factor.
"""
struct LorentzBoost{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    angle::T
    cos_ang::T
    sin_ang::T
    tan_ang::T
end

@element_spec begin
    kind = :lorentz_boost
    spec_type = ElementSpec{:lorentz_boost}
    friendly_constructor = LorentzBoostSpec
    runtime_type = LorentzBoost
    description = "Flexible zero-length Lorentz boost coordinate-transform specification."
    keywords = [:thin_element, :lorentz_boost, :coordinate_transform, :quasi_symplectic]
    tracking_methods = [NonSymplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        angle=ParamMeta(required=true, unit="rad", meaning="HALF the full crossing angle (the Hirata phi), in radians. Named half_crossing_angle in knob_control.jl, Knobs.jl and validation/crossing_luminosity_anchor.jl and crossing_angle in the two tracking examples -- the same quantity throughout, and its factor of two is the classic beam-beam error (2026-08-05_b audit, U16-10)"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = LorentzBoostSpec(0.03)
    construction_help = "Friendly constructor: LorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...), where angle is in radians. Equivalent flexible form: ElementSpec{:lorentz_boost}(; angle=angle, tracking_method=tracking_method, kwargs...). This quasi-symplectic coordinate transform supports NonSymplectic6DMap only. Extra keyword arguments are stored as metadata. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel. numeric_type (every kind): the number type the element compiles in, Float64 unless built by the typed form LorentzBoostSpec{T}(; ...) or given numeric_type=T by keyword (Float32 for a Float32 line; the untyped form promotes its inputs over a Float64 floor and never narrows); a beam whose element type differs from the element's is refused by name when a task compiles the line."
end

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    RevLorentzBoost(angle)

Runtime reverse zero-length Lorentz boost coordinate transformation. This
applies the exact inverse of Hirata's nonlinear crossing-angle map. Its
accelerator-coordinate Jacobian determinant is `cos(angle)^3`, so it is
likewise quasi-symplectic rather than canonical in isolation.
"""
struct RevLorentzBoost{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    angle::T
    cos_ang::T
    sin_ang::T
    tan_ang::T
end

@element_spec begin
    kind = :rev_lorentz_boost
    spec_type = ElementSpec{:rev_lorentz_boost}
    friendly_constructor = RevLorentzBoostSpec
    runtime_type = RevLorentzBoost
    description = "Flexible reverse zero-length Lorentz boost coordinate-transform specification."
    keywords = [:thin_element, :reverse_lorentz_boost, :coordinate_transform, :quasi_symplectic]
    tracking_methods = [NonSymplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        angle=ParamMeta(required=true, unit="rad", meaning="HALF the full crossing angle, matching LorentzBoostSpec; see its `angle` for the naming note (U16-10)"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = RevLorentzBoostSpec(0.03)
    construction_help = "Friendly constructor: RevLorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...), where angle is in radians. Equivalent flexible form: ElementSpec{:rev_lorentz_boost}(; angle=angle, tracking_method=tracking_method, kwargs...). This quasi-symplectic coordinate transform supports NonSymplectic6DMap only. Extra keyword arguments are stored as metadata. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel. numeric_type (every kind): the number type the element compiles in, Float64 unless built by the typed form RevLorentzBoostSpec{T}(; ...) or given numeric_type=T by keyword (Float32 for a Float32 line; the untyped form promotes its inputs over a Float64 floor and never narrows); a beam whose element type differs from the element's is refused by name when a task compiles the line."
end

# The direct runtime forms promote the angle over a Float64 floor, as the crab
# cavity's direct form does (`_linear_map_eltype`); a compiled spec builds in
# `numeric_type(spec)`; the inverse keeps its boost's type.
LorentzBoost(angle::Number) = _lorentz_boost(LorentzBoost, _linear_map_eltype(angle), angle, NonSymplectic6DMap())
RevLorentzBoost(angle::Number) = _lorentz_boost(RevLorentzBoost, _linear_map_eltype(angle), angle, NonSymplectic6DMap())

LorentzBoost(spec::ElementSpec{:lorentz_boost}, method::AbstractTrackingMethod=tracking_method(spec)) =
    _lorentz_boost(LorentzBoost, numeric_type(spec), param(spec, :angle), method)
RevLorentzBoost(spec::ElementSpec{:rev_lorentz_boost}, method::AbstractTrackingMethod=tracking_method(spec)) =
    _lorentz_boost(RevLorentzBoost, numeric_type(spec), param(spec, :angle), method)

inverse_boost(boost::LorentzBoost{M,T}) where {M,T} = _lorentz_boost(RevLorentzBoost, T, boost.angle, boost.method)
inverse_boost(boost::RevLorentzBoost{M,T}) where {M,T} = _lorentz_boost(LorentzBoost, T, boost.angle, boost.method)

@inline function track_particle(::NonSymplectic6DMap, boost::LorentzBoost, x0, px0, y0, py0, z0, pz0)
    ps0 = sqrt((one(pz0) + pz0)^2 - px0^2 - py0^2)
    h0 = one(pz0) + pz0 - ps0

    py1 = py0 / boost.cos_ang
    h1 = h0 / (boost.cos_ang * boost.cos_ang)
    px1 = px0 / boost.cos_ang - h1 * boost.sin_ang
    pz1 = pz0 - px1 * boost.sin_ang
    ps1 = one(pz1) + pz1 - h1

    ds = x0 * boost.sin_ang
    x1 = x0 + z0 * boost.tan_ang + px1 / ps1 * ds
    y1 = y0 + py1 / ps1 * ds
    z1 = z0 / boost.cos_ang - h1 / ps1 * ds
    return x1, px1, y1, py1, z1, pz1
end

@inline (boost::LorentzBoost)(x0, px0, y0, py0, z0, pz0) =
    track_particle(boost.method, boost, x0, px0, y0, py0, z0, pz0)

@inline function track_particle(::NonSymplectic6DMap, boost::RevLorentzBoost, x0, px0, y0, py0, z0, pz0)
    ps0 = sqrt((one(pz0) + pz0)^2 - px0^2 - py0^2)
    h0 = one(pz0) + pz0 - ps0

    x1 = x0 - z0 * boost.sin_ang
    x1 = x1 / (one(x1) + (px0 + h0 * boost.sin_ang) * boost.sin_ang / ps0)
    z1 = (z0 + h0 / ps0 * x1 * boost.sin_ang) * boost.cos_ang
    y1 = y0 - py0 / ps0 * x1 * boost.sin_ang

    pz1 = pz0 + px0 * boost.sin_ang
    px1 = (px0 + h0 * boost.sin_ang) * boost.cos_ang
    py1 = py0 * boost.cos_ang
    return x1, px1, y1, py1, z1, pz1
end

@inline (boost::RevLorentzBoost)(x0, px0, y0, py0, z0, pz0) =
    track_particle(boost.method, boost, x0, px0, y0, py0, z0, pz0)

# `Number`, not `Real`: a crossing angle is a legitimate thing to differentiate
# with respect to, and a dual number or a complex step is not a `Real`. `T` is
# the caller's: `numeric_type(spec)` from a spec, the floor promotion from the
# direct form (until 2026-10-16 it was `typeof(float(angle))` here, so a
# Float32 angle narrowed the boost to Float32 silently).
function _lorentz_boost(::Type{B}, ::Type{T}, angle::Number, method::AbstractTrackingMethod) where {B,T}
    θ = T(angle)
    c = cos(θ)
    s = sin(θ)
    return B{typeof(method),T}(method, θ, c, s, s / c)
end
