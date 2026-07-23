export LorentzBoostSpec, RevLorentzBoostSpec, LorentzBoost, RevLorentzBoost

abstract type LorentzBoostSpec end
abstract type RevLorentzBoostSpec end

# Raw flexible specs inherit the same method default as the friendly
# constructors, so metadata-driven and direct ElementSpec construction agree.
default_method(::Type{ElementSpec{:lorentz_boost}}) = NonSymplectic6DMap()
default_method(::Type{ElementSpec{:rev_lorentz_boost}}) = NonSymplectic6DMap()

"""
    LorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...)

Create an `ElementSpec{:lorentz_boost}` for a zero-length Lorentz boost
coordinate transformation. `angle` is in radians. Extra keyword arguments are
stored as descriptive spec metadata.
"""
LorentzBoostSpec(angle::Real; tracking_method=NonSymplectic6DMap(), kwargs...) =
    ElementSpec{:lorentz_boost}(_spec_params(; angle=float(angle), tracking_method=tracking_method, kwargs...))

"""
    RevLorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...)

Create an `ElementSpec{:rev_lorentz_boost}` for the reverse zero-length Lorentz
boost coordinate transformation. `angle` is in radians. Extra keyword arguments
are stored as descriptive spec metadata.
"""
RevLorentzBoostSpec(angle::Real; tracking_method=NonSymplectic6DMap(), kwargs...) =
    ElementSpec{:rev_lorentz_boost}(_spec_params(; angle=float(angle), tracking_method=tracking_method, kwargs...))

"""
    LorentzBoost(angle)

Runtime zero-length Lorentz boost coordinate transformation. This follows
Hirata's nonlinear six-dimensional crossing-angle transformation. In the
accelerator variables used here it is quasi-symplectic (Jacobian determinant
`sec(angle)^3`), not a canonical symplectic map by itself; the reverse map
restores the phase-space volume factor.
"""
struct LorentzBoost{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
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
        angle=ParamMeta(required=true, unit="rad", meaning="boost crossing angle"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
    )
    example = LorentzBoostSpec(0.03)
    construction_help = "Friendly constructor: LorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...), where angle is in radians. Equivalent flexible form: ElementSpec{:lorentz_boost}(; angle=angle, tracking_method=tracking_method, kwargs...). This quasi-symplectic coordinate transform supports NonSymplectic6DMap only. Extra keyword arguments are stored as metadata."
end

"""
    RevLorentzBoost(angle)

Runtime reverse zero-length Lorentz boost coordinate transformation. This
applies the exact inverse of Hirata's nonlinear crossing-angle map. Its
accelerator-coordinate Jacobian determinant is `cos(angle)^3`, so it is
likewise quasi-symplectic rather than canonical in isolation.
"""
struct RevLorentzBoost{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
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
        angle=ParamMeta(required=true, unit="rad", meaning="reverse boost crossing angle"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
    )
    example = RevLorentzBoostSpec(0.03)
    construction_help = "Friendly constructor: RevLorentzBoostSpec(angle; tracking_method=NonSymplectic6DMap(), kwargs...), where angle is in radians. Equivalent flexible form: ElementSpec{:rev_lorentz_boost}(; angle=angle, tracking_method=tracking_method, kwargs...). This quasi-symplectic coordinate transform supports NonSymplectic6DMap only. Extra keyword arguments are stored as metadata."
end

LorentzBoost(angle::Real) = _lorentz_boost(LorentzBoost, angle, NonSymplectic6DMap())
RevLorentzBoost(angle::Real) = _lorentz_boost(RevLorentzBoost, angle, NonSymplectic6DMap())

LorentzBoost(spec::ElementSpec{:lorentz_boost}, method::AbstractTrackingMethod=tracking_method(spec)) =
    _lorentz_boost(LorentzBoost, param(spec, :angle), method)
RevLorentzBoost(spec::ElementSpec{:rev_lorentz_boost}, method::AbstractTrackingMethod=tracking_method(spec)) =
    _lorentz_boost(RevLorentzBoost, param(spec, :angle), method)

inverse_boost(boost::LorentzBoost) = RevLorentzBoost(boost.angle)
inverse_boost(boost::RevLorentzBoost) = LorentzBoost(boost.angle)

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

function _lorentz_boost(::Type{B}, angle::Real, method::AbstractTrackingMethod) where {B}
    T = typeof(float(angle))
    θ = T(angle)
    c = cos(θ)
    s = sin(θ)
    return B{typeof(method),T}(method, θ, c, s, s / c)
end
