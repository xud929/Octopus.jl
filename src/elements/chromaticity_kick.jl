export ChromaticityKickSpec, ChromaticityKick

abstract type ChromaticityKickSpec{T} end

ChromaticityKickSpec(; kwargs...) = ChromaticityKickSpec{Float64}(; kwargs...)
function (::Type{ChromaticityKickSpec{T}})(;
                                          xi,
                                          beta,
                                          alpha=(zero(T), zero(T)),
                                          zeta=(zero(T), zero(T), zero(T), zero(T)),
                                          eta=(zero(T), zero(T), zero(T), zero(T)),
                                          R=(zero(T), zero(T), zero(T), zero(T)),
                                          tracking_method=Symplectic6DMap(),
                                          kwargs...) where {T}
    return ElementSpec{:chromaticity_kick}(
        _spec_params(;
            xi=_pair_tuple(xi, T),
            beta=_pair_tuple(beta, T),
            alpha=_pair_tuple(alpha, T),
            zeta=_quad_tuple(zeta, T),
            eta=_quad_tuple(eta, T),
            R=_quad_tuple(R, T),
            tracking_method=tracking_method,
            kwargs...,
        ),
    )
end

struct ChromaticityKick{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    xix::T
    xiy::T
    betx::T
    bety::T
    alfx::T
    alfy::T
    gamx::T
    gamy::T
    zeta::CrabDispersion{Symplectic6DMap,T}
    eta::MomentumDispersion{Symplectic6DMap,T}
    coupling::XYCoupling{Symplectic6DMap,T}
end

function ChromaticityKick(spec::ElementSpec{:chromaticity_kick},
                          method::AbstractTrackingMethod=tracking_method(spec))
    xi = param(spec, :xi)
    beta = param(spec, :beta)
    alpha = param(spec, :alpha)
    T = promote_type(map(typeof, (xi..., beta..., alpha...))...)
    betx, bety = T(beta[1]), T(beta[2])
    alfx, alfy = T(alpha[1]), T(alpha[2])
    return ChromaticityKick(
        method,
        T(xi[1]), T(xi[2]),
        betx, bety,
        alfx, alfy,
        (one(T) + alfx * alfx) / betx,
        (one(T) + alfy * alfy) / bety,
        CrabDispersion(Symplectic6DMap(), _quad_tuple(param(spec, :zeta), T)...),
        MomentumDispersion(Symplectic6DMap(), _quad_tuple(param(spec, :eta), T)...),
        XYCoupling(_quad_tuple(param(spec, :R), T)..., XY_MODEA),
    )
end

@inline function track_particle(::Symplectic6DMap, elem::ChromaticityKick, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _inverse(elem.zeta, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _inverse(elem.eta, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _inverse(elem.coupling, x, px, y, py, z, pz)

    x0, px0, y0, py0 = x, px, y, py
    μx = TWOPI * elem.xix * pz
    cx = cos(μx)
    sx = sin(μx)
    x = x0 * (cx + elem.alfx * sx) + px0 * elem.betx * sx
    px = -x0 * sx * elem.gamx + px0 * (cx - elem.alfx * sx)

    μy = TWOPI * elem.xiy * pz
    cy = cos(μy)
    sy = sin(μy)
    y = y0 * (cy + elem.alfy * sy) + py0 * elem.bety * sy
    py = -y0 * sy * elem.gamy + py0 * (cy - elem.alfy * sy)

    Jx = 0.5 * (elem.gamx * x0 * x0 + 2 * elem.alfx * x0 * px0 + elem.betx * px0 * px0)
    Jy = 0.5 * (elem.gamy * y0 * y0 + 2 * elem.alfy * y0 * py0 + elem.bety * py0 * py0)
    z += TWOPI * (elem.xix * Jx + elem.xiy * Jy)

    x, px, y, py, z, pz = elem.coupling(x, px, y, py, z, pz)
    x, px, y, py, z, pz = elem.eta(x, px, y, py, z, pz)
    return elem.zeta(x, px, y, py, z, pz)
end

@inline (elem::ChromaticityKick)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

function _pair_tuple(values, ::Type{T}) where {T}
    length(values) == 2 || throw(ArgumentError("expected 2 values, got $(length(values))"))
    return (T(values[1]), T(values[2]))
end

function _quad_tuple(values, ::Type{T}) where {T}
    length(values) == 4 || throw(ArgumentError("expected 4 values, got $(length(values))"))
    return ntuple(i -> T(values[i]), 4)
end

@inline function _inverse(elem::CrabDispersion, x0, px0, y0, py0, z0, pz0)
    pz1 = pz0 - elem.zeta2 * x0 + elem.zeta1 * px0 - elem.zeta4 * y0 + elem.zeta3 * py0
    x1 = x0 - elem.zeta1 * z0
    px1 = px0 - elem.zeta2 * z0
    y1 = y0 - elem.zeta3 * z0
    py1 = py0 - elem.zeta4 * z0
    return x1, px1, y1, py1, z0, pz1
end

@inline function _inverse(elem::MomentumDispersion, x0, px0, y0, py0, z0, pz0)
    z1 = z0 + elem.eta2 * x0 - elem.eta1 * px0 + elem.eta4 * y0 - elem.eta3 * py0
    x1 = x0 - elem.eta1 * pz0
    px1 = px0 - elem.eta2 * pz0
    y1 = y0 - elem.eta3 * pz0
    py1 = py0 - elem.eta4 * pz0
    return x1, px1, y1, py1, z1, pz0
end

@inline function _inverse(elem::XYCoupling, x0, px0, y0, py0, z0, pz0)
    if elem.mode == XY_UNDEF
        return x0, px0, y0, py0, z0, pz0
    end
    if elem.mode == XY_MODEA
        return _inverse_xy_modea(elem, x0, px0, y0, py0, z0, pz0)
    end
    return _inverse_xy_modeb(elem, x0, px0, y0, py0, z0, pz0)
end

@inline function _inverse_xy_modea(elem::XYCoupling, x0, px0, y0, py0, z0, pz0)
    g = inv(sqrt(1 + elem.r1 * elem.r4 - elem.r2 * elem.r3))
    x1 = g * (x0 - elem.r4 * y0 + elem.r2 * py0)
    px1 = g * (px0 + elem.r3 * y0 - elem.r1 * py0)
    y1 = g * (elem.r1 * x0 + elem.r2 * px0 + y0)
    py1 = g * (elem.r3 * x0 + elem.r4 * px0 + py0)
    return x1, px1, y1, py1, z0, pz0
end

@inline function _inverse_xy_modeb(elem::XYCoupling, x0, px0, y0, py0, z0, pz0)
    g = inv(sqrt(1 + elem.r1 * elem.r4 - elem.r2 * elem.r3))
    x1 = g * (y0 + elem.r1 * x0 + elem.r2 * px0)
    px1 = g * (py0 + elem.r3 * x0 + elem.r4 * px0)
    y1 = g * (x0 - elem.r4 * y0 + elem.r2 * py0)
    py1 = g * (px0 + elem.r3 * y0 - elem.r1 * py0)
    return x1, px1, y1, py1, z0, pz0
end

@element_spec begin
    kind = :chromaticity_kick
    spec_type = ElementSpec{:chromaticity_kick}
    friendly_constructor = ChromaticityKickSpec
    runtime_type = ChromaticityKick
    description = "Flexible chromaticity kick specification."
    keywords = [:thin_element, :coordinate_transform]
    tracking_methods = [Symplectic6DMap]
    contracts = [TrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        xi=ParamMeta(required=true, meaning="horizontal and vertical chromaticities"),
        beta=ParamMeta(required=true, meaning="horizontal and vertical beta functions"),
        alpha=ParamMeta(default=(0, 0), meaning="horizontal and vertical alpha functions"),
        zeta=ParamMeta(default=(0, 0, 0, 0), meaning="crab dispersion coefficients"),
        eta=ParamMeta(default=(0, 0, 0, 0), meaning="momentum dispersion coefficients"),
        R=ParamMeta(default=(0, 0, 0, 0), meaning="x-y coupling coefficients"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = ChromaticityKickSpec{Float64}(xi=(1.0, 1.0), beta=(1.0, 1.0))
    construction_help = "Friendly constructor: ChromaticityKickSpec{T}(; xi, beta, alpha=(0,0), zeta=(0,0,0,0), eta=(0,0,0,0), R=(0,0,0,0), tracking_method=Symplectic6DMap(), kwargs...)."
end
