export CrabDispersionSpec, MomentumDispersionSpec, XYCouplingSpec,
       CrabDispersion, MomentumDispersion, XYCouplingMode, XY_UNDEF, XY_MODEA, XY_MODEB, XYCoupling

abstract type CrabDispersionSpec{T} end
abstract type MomentumDispersionSpec{T} end
abstract type XYCouplingSpec{T} end

function _spec_params(; kwargs...)
    return Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(kwargs))
end

function _float_params(spec::ElementSpec, keys::Symbol...)
    T = promote_type(map(k -> typeof(float(param(spec, k))), keys)...)
    return map(k -> T(param(spec, k)), keys)
end

"""
    CrabDispersionSpec{T=Float64}(; zeta1=0, zeta2=0, zeta3=0, zeta4=0,
                                  tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:crab_dispersion}`. The `zeta` fields define a
six-dimensional symplectic crab-dispersion coordinate transform. Extra keyword
arguments are stored as descriptive spec metadata.
"""
CrabDispersionSpec(; kwargs...) = CrabDispersionSpec{Float64}(; kwargs...)
function (::Type{CrabDispersionSpec{T}})(; zeta1=zero(T), zeta2=zero(T),
                                        zeta3=zero(T), zeta4=zero(T),
                                        tracking_method=Symplectic6DMap(),
                                        kwargs...) where {T}
    return ElementSpec{:crab_dispersion}(
        _spec_params(; zeta1=T(zeta1), zeta2=T(zeta2), zeta3=T(zeta3), zeta4=T(zeta4),
                     tracking_method=tracking_method, kwargs...),
    )
end

struct CrabDispersion{M<:AbstractTrackingMethod,FloatT <: AbstractFloat} <: AbstractTrackOp
    method::M
    zeta1::FloatT
    zeta2::FloatT
    zeta3::FloatT
    zeta4::FloatT
end

CrabDispersion{T}(zeta1, zeta2, zeta3, zeta4) where {T<:AbstractFloat} =
    CrabDispersion(Symplectic6DMap(), T(zeta1), T(zeta2), T(zeta3), T(zeta4))

@element_spec begin
    kind = :crab_dispersion
    spec_type = ElementSpec{:crab_dispersion}
    friendly_constructor = CrabDispersionSpec
    runtime_type = CrabDispersion
    description = "Flexible crab-dispersion element specification."
    keywords = [:crab_dispersion]
    tracking_methods = [Symplectic6DMap]
    contracts = [TrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        zeta1=ParamMeta(default=0, meaning="x-z crab dispersion coefficient"),
        zeta2=ParamMeta(default=0, meaning="px-z crab dispersion coefficient"),
        zeta3=ParamMeta(default=0, meaning="y-z crab dispersion coefficient"),
        zeta4=ParamMeta(default=0, meaning="py-z crab dispersion coefficient"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = CrabDispersionSpec{Float64}(zeta1=0.1)
    construction_help = "Friendly constructor: CrabDispersionSpec{T}(; zeta1, zeta2, zeta3, zeta4, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:crab_dispersion}(; zeta1=zeta1, zeta2=zeta2, zeta3=zeta3, zeta4=zeta4, tracking_method=tracking_method, kwargs...). Extra keyword arguments are stored as metadata."
end

CrabDispersion(spec::ElementSpec{:crab_dispersion}, method::AbstractTrackingMethod=tracking_method(spec)) =
    CrabDispersion(method, _float_params(spec, :zeta1, :zeta2, :zeta3, :zeta4)...)

@inline function track_particle(::Symplectic6DMap, elem::CrabDispersion, x0, px0, y0, py0, z0, pz0)
    pz1 = pz0 + elem.zeta2*x0 - elem.zeta1*px0 + elem.zeta4*y0 - elem.zeta3*py0
    x1 = x0 + elem.zeta1*z0
    px1 = px0 + elem.zeta2*z0
    y1 = y0 + elem.zeta3*z0
    py1 = py0 + elem.zeta4*z0
    return x1, px1, y1, py1, z0, pz1
end

@inline (elem::CrabDispersion)(x0, px0, y0, py0, z0, pz0) =
    track_particle(elem.method, elem, x0, px0, y0, py0, z0, pz0)

"""
    MomentumDispersionSpec{T=Float64}(; eta1=0, eta2=0, eta3=0, eta4=0,
                                      tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:momentum_dispersion}`. Extra keyword arguments are
stored as descriptive spec metadata.
"""
MomentumDispersionSpec(; kwargs...) = MomentumDispersionSpec{Float64}(; kwargs...)
function (::Type{MomentumDispersionSpec{T}})(; eta1=zero(T), eta2=zero(T),
                                            eta3=zero(T), eta4=zero(T),
                                            tracking_method=Symplectic6DMap(),
                                            kwargs...) where {T}
    return ElementSpec{:momentum_dispersion}(
        _spec_params(; eta1=T(eta1), eta2=T(eta2), eta3=T(eta3), eta4=T(eta4),
                     tracking_method=tracking_method, kwargs...),
    )
end

struct MomentumDispersion{M<:AbstractTrackingMethod,FloatT <: AbstractFloat} <: AbstractTrackOp
    method::M
    eta1::FloatT
    eta2::FloatT
    eta3::FloatT
    eta4::FloatT
end

MomentumDispersion{T}(eta1, eta2, eta3, eta4) where {T<:AbstractFloat} =
    MomentumDispersion(Symplectic6DMap(), T(eta1), T(eta2), T(eta3), T(eta4))

@element_spec begin
    kind = :momentum_dispersion
    spec_type = ElementSpec{:momentum_dispersion}
    friendly_constructor = MomentumDispersionSpec
    runtime_type = MomentumDispersion
    description = "Flexible momentum-dispersion element specification."
    keywords = [:momentum_dispersion]
    tracking_methods = [Symplectic6DMap]
    contracts = [TrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        eta1=ParamMeta(default=0, meaning="x-pz momentum dispersion coefficient"),
        eta2=ParamMeta(default=0, meaning="px-pz momentum dispersion coefficient"),
        eta3=ParamMeta(default=0, meaning="y-pz momentum dispersion coefficient"),
        eta4=ParamMeta(default=0, meaning="py-pz momentum dispersion coefficient"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = MomentumDispersionSpec{Float64}(eta1=0.2)
    construction_help = "Friendly constructor: MomentumDispersionSpec{T}(; eta1, eta2, eta3, eta4, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:momentum_dispersion}(; eta1=eta1, eta2=eta2, eta3=eta3, eta4=eta4, tracking_method=tracking_method, kwargs...). Extra keyword arguments are stored as metadata."
end

MomentumDispersion(spec::ElementSpec{:momentum_dispersion}, method::AbstractTrackingMethod=tracking_method(spec)) =
    MomentumDispersion(method, _float_params(spec, :eta1, :eta2, :eta3, :eta4)...)

@inline function track_particle(::Symplectic6DMap, elem::MomentumDispersion, x0, px0, y0, py0, z0, pz0)
    z1 = z0 - elem.eta2*x0 + elem.eta1*px0 - elem.eta4*y0 + elem.eta3*py0
    x1 = x0 + elem.eta1*pz0
    px1 = px0 + elem.eta2*pz0
    y1 = y0 + elem.eta3*pz0
    py1 = py0 + elem.eta4*pz0
    return x1, px1, y1, py1, z1, pz0
end

@inline (elem::MomentumDispersion)(x0, px0, y0, py0, z0, pz0) =
    track_particle(elem.method, elem, x0, px0, y0, py0, z0, pz0)

@enum XYCouplingMode::UInt8 XY_UNDEF=0 XY_MODEA=1 XY_MODEB=2

"""
    XYCouplingSpec{T=Float64}(; r1=0, r2=0, r3=0, r4=0, mode=XY_MODEA,
                              tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:xy_coupling}` for a transverse x-y coupling coordinate
transform. Extra keyword arguments are stored as descriptive spec metadata.
"""
XYCouplingSpec(; kwargs...) = XYCouplingSpec{Float64}(; kwargs...)
function (::Type{XYCouplingSpec{T}})(; r1=zero(T), r2=zero(T), r3=zero(T),
                                    r4=zero(T), mode::XYCouplingMode=XY_MODEA,
                                    tracking_method=Symplectic6DMap(),
                                    kwargs...) where {T}
    return ElementSpec{:xy_coupling}(
        _spec_params(; r1=T(r1), r2=T(r2), r3=T(r3), r4=T(r4), mode=mode,
                     tracking_method=tracking_method, kwargs...),
    )
end

struct XYCoupling{M<:AbstractTrackingMethod,FloatT <: AbstractFloat} <: AbstractTrackOp
    method::M
    r1::FloatT
    r2::FloatT
    r3::FloatT
    r4::FloatT
    mode::XYCouplingMode
end

@element_spec begin
    kind = :xy_coupling
    spec_type = ElementSpec{:xy_coupling}
    friendly_constructor = XYCouplingSpec
    runtime_type = XYCoupling
    description = "Flexible transverse x-y coupling element specification."
    keywords = [:xy_coupling]
    tracking_methods = [Symplectic6DMap]
    contracts = [TrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        r1=ParamMeta(default=0, meaning="coupling coefficient r1"),
        r2=ParamMeta(default=0, meaning="coupling coefficient r2"),
        r3=ParamMeta(default=0, meaning="coupling coefficient r3"),
        r4=ParamMeta(default=0, meaning="coupling coefficient r4"),
        mode=ParamMeta(default=XY_MODEA, meaning="coupling convention"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = XYCouplingSpec{Float64}(r1=0.01)
    construction_help = "Friendly constructor: XYCouplingSpec{T}(; r1, r2, r3, r4, mode=XY_MODEA, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:xy_coupling}(; r1=r1, r2=r2, r3=r3, r4=r4, mode=mode, tracking_method=tracking_method, kwargs...). Extra keyword arguments are stored as metadata."
end

XYCoupling(r1::T, r2::T, r3::T, r4::T) where {T<:AbstractFloat} =
    XYCoupling{Symplectic6DMap,T}(Symplectic6DMap(), r1, r2, r3, r4, XY_MODEA)
XYCoupling(r1::T, r2::T, r3::T, r4::T, mode::XYCouplingMode) where {T<:AbstractFloat} =
    XYCoupling{Symplectic6DMap,T}(Symplectic6DMap(), r1, r2, r3, r4, mode)
XYCoupling(spec::ElementSpec{:xy_coupling}, method::AbstractTrackingMethod=tracking_method(spec)) =
    XYCoupling(method, _float_params(spec, :r1, :r2, :r3, :r4)..., getparam(spec, :mode, XY_MODEA))

@inline function track_particle(::Symplectic6DMap, elem::XYCoupling, x0, px0, y0, py0, z0, pz0)
    if elem.mode == XY_UNDEF
        return x0, px0, y0, py0, z0, pz0
    end

    g = inv(sqrt(1 + elem.r1*elem.r4 - elem.r2*elem.r3))
    if elem.mode == XY_MODEA
        x1 = g*(x0 + elem.r4*y0 - elem.r2*py0)
        px1 = g*(px0 - elem.r3*y0 + elem.r1*py0)
        y1 = g*(-elem.r1*x0 - elem.r2*px0 + y0)
        py1 = g*(-elem.r3*x0 - elem.r4*px0 + py0)
    else
        x1 = g*(elem.r4*x0 - elem.r2*px0 + y0)
        px1 = g*(-elem.r3*x0 + elem.r1*px0 + py0)
        y1 = g*(x0 - elem.r1*y0 - elem.r2*py0)
        py1 = g*(px0 - elem.r3*y0 - elem.r4*py0)
    end
    return x1, px1, y1, py1, z0, pz0
end

@inline (elem::XYCoupling)(x0, px0, y0, py0, z0, pz0) =
    track_particle(elem.method, elem, x0, px0, y0, py0, z0, pz0)
