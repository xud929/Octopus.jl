export ThinStrongBeamSpec, GaussianStrongBeamSpec,
       ThinStrongBeam, GaussianStrongBeam,
       NoTurnSignal, LinearTurnSignal, SinTurnSignal, CosTurnSignal,
       WhiteNoiseTurnSignal, InputTurnSignal, PinkNoiseTurnSignal,
       signal_value, update_strong_beam!, gaussian_beambeam_kick

const ROUND_BEAM_THRESHOLD = 1.0e-10

abstract type ThinStrongBeamSpec{T} end
abstract type GaussianStrongBeamSpec{T} end
abstract type AbstractTurnSignal{N,T} end

struct NoTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    value::NTuple{N,T}
end

struct LinearTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    base::NTuple{N,T}
    slope::NTuple{N,T}
end

struct SinTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    amplitude::NTuple{N,T}
    frequency::NTuple{N,T}
    offset::NTuple{N,T}
end

struct CosTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    amplitude::NTuple{N,T}
    frequency::NTuple{N,T}
    offset::NTuple{N,T}
end

struct WhiteNoiseTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    mean::NTuple{N,T}
    sigma::NTuple{N,T}
end

struct InputTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    values::Vector{NTuple{N,T}}
end

mutable struct PinkNoiseTurnSignal{N,T} <: AbstractTurnSignal{N,T}
    mean::NTuple{N,T}
    sigma::NTuple{N,T}
    state::NTuple{N,NTuple{3,T}}
end

NoTurnSignal{N,T}() where {N,T} = NoTurnSignal{N,T}(ntuple(_ -> zero(T), N))
NoTurnSignal(values::NTuple{N,T}) where {N,T} = NoTurnSignal{N,T}(values)
LinearTurnSignal(base, slope) = LinearTurnSignal(_strong_tuple(base), _strong_tuple(slope))
SinTurnSignal(amplitude, frequency; offset=nothing) =
    SinTurnSignal(_strong_tuple(amplitude), _strong_tuple(frequency),
                  offset === nothing ? _zero_signal_tuple(amplitude) : _strong_tuple(offset))
CosTurnSignal(amplitude, frequency; offset=nothing) =
    CosTurnSignal(_strong_tuple(amplitude), _strong_tuple(frequency),
                  offset === nothing ? _zero_signal_tuple(amplitude) : _strong_tuple(offset))
WhiteNoiseTurnSignal(mean, sigma) = WhiteNoiseTurnSignal(_strong_tuple(mean), _strong_tuple(sigma))
InputTurnSignal(values::AbstractVector) = InputTurnSignal([_strong_tuple(v) for v in values])
PinkNoiseTurnSignal(mean, sigma) = begin
    m = _strong_tuple(mean)
    s = _strong_tuple(sigma)
    T = promote_type(map(typeof, (m..., s...))...)
    PinkNoiseTurnSignal(ntuple(i -> T(m[i]), length(m)),
                        ntuple(i -> T(s[i]), length(s)),
                        ntuple(_ -> (zero(T), zero(T), zero(T)), length(m)))
end

@inline signal_value(s::NoTurnSignal, turn::Integer) = s.value
@inline signal_value(s::LinearTurnSignal, turn::Integer) =
    ntuple(i -> s.base[i] + s.slope[i] * turn, length(s.base))
@inline signal_value(s::SinTurnSignal, turn::Integer) =
    ntuple(i -> s.offset[i] + s.amplitude[i] * sin(TWOPI * turn * s.frequency[i]), length(s.amplitude))
@inline signal_value(s::CosTurnSignal, turn::Integer) =
    ntuple(i -> s.offset[i] + s.amplitude[i] * cos(TWOPI * turn * s.frequency[i]), length(s.amplitude))
@inline signal_value(s::WhiteNoiseTurnSignal, turn::Integer) =
    ntuple(i -> s.mean[i] + s.sigma[i] * Random.randn(), length(s.mean))
@inline signal_value(s::InputTurnSignal, turn::Integer) = s.values[mod(turn, length(s.values)) + 1]

function signal_value(s::PinkNoiseTurnSignal{N,T}, turn::Integer) where {N,T}
    hb = (T(0.049922035), T(-0.095993537), T(0.050612699), T(-0.004408786))
    ha = (one(T), T(-2.494956002), T(2.017265875), T(-0.522189400))
    norm = T(0.08680587859687908)
    return ntuple(N) do i
        x = s.mean[i] + s.sigma[i] * Random.randn()
        si = s.state[i]
        val = x * hb[1] + si[1]
        s1 = -val * ha[2] + x * hb[2] + si[2]
        s2 = -val * ha[3] + x * hb[3] + si[3]
        s3 = -val * ha[4] + x * hb[4]
        s.state = ntuple(j -> j == i ? (s1, s2, s3) : s.state[j], N)
        val / norm
    end
end

"""
    ThinStrongBeamSpec{T=Float64}(; kbb, klum=1, beta, alpha=(0,0),
                                  sigma, center=(0,0,0), angle=(0,0,0),
                                  curvature=(0,0,0), dynamic_drift_flag=0,
                                  size_signal=nothing,
                                  centroid_signal=nothing,
                                  angle_signal=nothing,
                                  tracking_method=WeakStrongBeamBeamMap(),
                                  kwargs...)

Create an `ElementSpec{:thin_strong_beam}` for a weak-strong beam-beam
interaction. Turn-dependent fluctuations are supplied as Julia turn-signal
objects.
"""
ThinStrongBeamSpec(; kwargs...) = ThinStrongBeamSpec{Float64}(; kwargs...)
function (::Type{ThinStrongBeamSpec{T}})(; kbb,
                                        klum=one(T),
                                        beta,
                                        alpha=(zero(T), zero(T)),
                                        sigma,
                                        center=(zero(T), zero(T), zero(T)),
                                        angle=(zero(T), zero(T), zero(T)),
                                        curvature=(zero(T), zero(T), zero(T)),
                                        dynamic_drift_flag=0,
                                        size_signal=nothing,
                                        centroid_signal=nothing,
                                        angle_signal=nothing,
                                        tracking_method=WeakStrongBeamBeamMap(),
                                        kwargs...) where {T}
    return ElementSpec{:thin_strong_beam}(
        _spec_params(;
            kbb=T(kbb),
            klum=T(klum),
            beta=_strong_tuple(beta, 2, T),
            alpha=_strong_tuple(alpha, 2, T),
            sigma=_strong_tuple(sigma, 2, T),
            center=_strong_tuple(center, 3, T),
            angle=_strong_tuple(angle, 3, T),
            curvature=_strong_tuple(curvature, 3, T),
            dynamic_drift_flag=Int(dynamic_drift_flag),
            size_signal=size_signal,
            centroid_signal=centroid_signal,
            angle_signal=angle_signal,
            tracking_method=tracking_method,
            kwargs...,
        ),
    )
end

mutable struct ThinStrongBeam{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    sigx0::T
    sigy0::T
    betx0::T
    bety0::T
    alfx0::T
    alfy0::T
    gamx0::T
    gamy0::T
    emitx::T
    emity::T
    kbb::T
    klum::T
    xo::T
    yo::T
    zo::T
    pxo::T
    pyo::T
    pzo::T
    ppxo::T
    ppyo::T
    ppzo::T
    dynamic_drift_flag::Int
    size_signal::Any
    centroid_signal::Any
    angle_signal::Any
    last_luminosity::T
end

function ThinStrongBeam(spec::ElementSpec{:thin_strong_beam},
                        method::AbstractTrackingMethod=tracking_method(spec))
    sigma = param(spec, :sigma)
    beta = param(spec, :beta)
    alpha = param(spec, :alpha)
    center = param(spec, :center)
    angle = param(spec, :angle)
    curvature = param(spec, :curvature)
    T = promote_type(map(typeof, (sigma..., beta..., alpha..., center..., angle..., curvature...,
                                  param(spec, :kbb), param(spec, :klum)))...)
    betx, bety = T(beta[1]), T(beta[2])
    alfx, alfy = T(alpha[1]), T(alpha[2])
    sigx, sigy = T(sigma[1]), T(sigma[2])
    gamx = (one(T) + alfx * alfx) / betx
    gamy = (one(T) + alfy * alfy) / bety
    return ThinStrongBeam(
        method,
        sigx, sigy, betx, bety, alfx, alfy, gamx, gamy,
        sigx * sigx / betx,
        sigy * sigy / bety,
        T(param(spec, :kbb)),
        T(param(spec, :klum)),
        T(center[1]), T(center[2]), T(center[3]),
        T(angle[1]), T(angle[2]), T(angle[3]),
        T(curvature[1]), T(curvature[2]), T(curvature[3]),
        Int(param(spec, :dynamic_drift_flag)),
        getparam(spec, :size_signal, nothing),
        getparam(spec, :centroid_signal, nothing),
        getparam(spec, :angle_signal, nothing),
        zero(T),
    )
end

"""
    GaussianStrongBeamSpec{T=Float64}(; thin, ns, slice_center=nothing,
                                      slice_weight=nothing,
                                      slice_hoffset=nothing,
                                      slice_voffset=nothing,
                                      sigz=nothing,
                                      slice_method=:equal_area,
                                      slice_width=nothing,
                                      hvoffset=nothing,
                                      tracking_method=WeakStrongBeamBeamMap(),
                                      kwargs...)

Create an `ElementSpec{:gaussian_strong_beam}`. `thin` may be a
`ThinStrongBeamSpec` or a compiled `ThinStrongBeam`.
"""
GaussianStrongBeamSpec(; kwargs...) = GaussianStrongBeamSpec{Float64}(; kwargs...)
function (::Type{GaussianStrongBeamSpec{T}})(; thin,
                                            ns,
                                            slice_center=nothing,
                                            slice_weight=nothing,
                                            slice_hoffset=nothing,
                                            slice_voffset=nothing,
                                            sigz=nothing,
                                            slice_method=:equal_area,
                                            slice_width=nothing,
                                            hvoffset=nothing,
                                            tracking_method=WeakStrongBeamBeamMap(),
                                            kwargs...) where {T}
    return ElementSpec{:gaussian_strong_beam}(
        _spec_params(;
            thin=thin,
            ns=Int(ns),
            sigz=sigz === nothing ? nothing : T(sigz),
            slice_method=slice_method,
            slice_width=slice_width,
            slice_center=slice_center === nothing ? nothing : _strong_tuple(slice_center, Int(ns), T),
            slice_weight=slice_weight === nothing ? nothing : _strong_tuple(slice_weight, Int(ns), T),
            slice_hoffset=slice_hoffset === nothing ? nothing : _strong_tuple(slice_hoffset, Int(ns), T),
            slice_voffset=slice_voffset === nothing ? nothing : _strong_tuple(slice_voffset, Int(ns), T),
            hvoffset=hvoffset,
            tracking_method=tracking_method,
            kwargs...,
        ),
    )
end

mutable struct GaussianStrongBeam{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    ns::Int
    slice_center::Vector{T}
    slice_weight::Vector{T}
    slice_hoffset::Vector{T}
    slice_voffset::Vector{T}
    thin::ThinStrongBeam{M,T}
    last_luminosity::T
end

function GaussianStrongBeam(spec::ElementSpec{:gaussian_strong_beam},
                            method::AbstractTrackingMethod=tracking_method(spec))
    thin_raw = param(spec, :thin)
    thin = thin_raw isa ThinStrongBeam ? thin_raw : ThinStrongBeam(thin_raw, method)
    T0 = typeof(thin.kbb)
    centers_tuple, weights_tuple = _gaussian_slices(
        T0,
        Int(param(spec, :ns)),
        getparam(spec, :slice_center, nothing),
        getparam(spec, :slice_weight, nothing),
        getparam(spec, :sigz, nothing),
        getparam(spec, :slice_method, :equal_area),
        getparam(spec, :slice_width, nothing),
    )
    hoff_tuple = getparam(spec, :slice_hoffset, nothing)
    voff_tuple = getparam(spec, :slice_voffset, nothing)
    hoff_tuple = hoff_tuple === nothing ? ntuple(_ -> zero(T0), Int(param(spec, :ns))) : _strong_tuple(hoff_tuple, Int(param(spec, :ns)), T0)
    voff_tuple = voff_tuple === nothing ? ntuple(_ -> zero(T0), Int(param(spec, :ns))) : _strong_tuple(voff_tuple, Int(param(spec, :ns)), T0)
    hvoffset = getparam(spec, :hvoffset, nothing)
    if hvoffset !== nothing
        dim = Symbol(get(hvoffset, :dim, :x))
        offsets = _crab_offsets(centers_tuple, T0(get(hvoffset, :coef, 0.0)),
                                T0(get(hvoffset, :frequency, -1.0)),
                                get(hvoffset, :harmonics, Dict(1 => 1.0)))
        if dim == :x
            hoff_tuple = offsets
        elseif dim == :y
            voff_tuple = offsets
        else
            throw(ArgumentError("hvoffset dim must be :x or :y"))
        end
    end
    centers = collect(centers_tuple)
    weights = collect(weights_tuple)
    hoff = collect(hoff_tuple)
    voff = collect(voff_tuple)
    T = promote_type(map(typeof, (centers..., weights..., hoff..., voff...))...)
    return GaussianStrongBeam(method, Int(param(spec, :ns)),
                              T.(centers), T.(weights), T.(hoff), T.(voff),
                              thin, zero(T))
end

@inline function track_particle(::WeakStrongBeamBeamMap, elem::ThinStrongBeam,
                                x, px, y, py, z, pz)
    x1, px1, y1, py1, z1, pz1, _ = _thin_strong_beam_track(elem, x, px, y, py, z, pz)
    return x1, px1, y1, py1, z1, pz1
end

@inline function track_particle(::WeakStrongBeamBeamMap, elem::GaussianStrongBeam,
                                x, px, y, py, z, pz)
    lum = zero(x + px + y + py + z + pz)
    kbb0 = elem.thin.kbb
    x0, y0, z0 = elem.thin.xo, elem.thin.yo, elem.thin.zo
    for i in elem.ns:-1:1
        thin = _slice_thin_strong_beam(elem.thin,
                                       kbb0 * elem.slice_weight[i],
                                       x0 + elem.slice_hoffset[i],
                                       y0 + elem.slice_voffset[i],
                                       elem.slice_center[i])
        x, px, y, py, z, pz, l = _thin_strong_beam_track(thin, x, px, y, py, z, pz)
        lum += l * elem.slice_weight[i]
    end
    return x, px, y, py, z, pz
end

@inline (elem::ThinStrongBeam)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)
@inline (elem::GaussianStrongBeam)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

function update_strong_beam!(elem::ThinStrongBeam, turn::Integer)
    if elem.size_signal !== nothing
        sx, sy = signal_value(elem.size_signal, turn)
        elem.sigx0 = sx
        elem.sigy0 = sy
        elem.emitx = sx * sx / elem.betx0
        elem.emity = sy * sy / elem.bety0
    end
    if elem.centroid_signal !== nothing
        elem.xo, elem.yo = signal_value(elem.centroid_signal, turn)
    end
    if elem.angle_signal !== nothing
        elem.pxo, elem.pyo = signal_value(elem.angle_signal, turn)
    end
    return elem
end

function update_strong_beam!(elem::GaussianStrongBeam, turn::Integer)
    update_strong_beam!(elem.thin, turn)
    return elem
end

function _thin_strong_beam_track(elem::ThinStrongBeam, x, px, y, py, z, pz)
    (elem.sigx0 == 0 || elem.sigy0 == 0) && return x, px, y, py, z, pz, zero(x)
    x, px, y, py, z, pz, S = _dynamic_drift(elem, x, px, y, py, z, pz)
    x, px, y, py, z, pz, lum = _cp_kick(elem, S, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _reverse_dynamic_drift(elem, x, px, y, py, z, pz)
    return x, px, y, py, z, pz, lum * elem.klum
end

function _slice_thin_strong_beam(base::ThinStrongBeam{M,T}, kbb, xo, yo, zo) where {M,T}
    return ThinStrongBeam(
        base.method,
        base.sigx0, base.sigy0,
        base.betx0, base.bety0,
        base.alfx0, base.alfy0,
        base.gamx0, base.gamy0,
        base.emitx, base.emity,
        T(kbb), base.klum,
        T(xo), T(yo), T(zo),
        base.pxo, base.pyo, base.pzo,
        base.ppxo, base.ppyo, base.ppzo,
        base.dynamic_drift_flag,
        base.size_signal,
        base.centroid_signal,
        base.angle_signal,
        zero(T),
    )
end

function _dynamic_drift(elem::ThinStrongBeam, x, px, y, py, z, pz)
    flag = elem.dynamic_drift_flag
    S = 0.5 * (z - elem.zo)
    if flag == -2
        PHI = sqrt(1 - 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
        x += S * px / (1 + pz)
        y += S * py / (1 + pz)
        z += 2 * S * PHI
    elseif flag == -1
        x += S * px
        y += S * py
    elseif flag == 0
        x += S * px
        y += S * py
        pz -= 0.25 * (px * px + py * py)
    elseif flag == 1
        PHI = sqrt(1 - 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
        x += S * px / (1 + pz)
        y += S * py / (1 + pz)
        z += 2 * S * PHI
        pz += (1 + pz) * PHI
    elseif flag == 2
        ps = sqrt((1 + pz) * (1 + pz) - px * px - py * py)
        H = 1 + pz - ps
        rr = 0.5 * H / ps
        z2 = (z + rr * elem.zo) / (1 + rr)
        S = 0.5 * (z2 - elem.zo)
        z -= H / ps * S
        pz -= 0.5 * H
        x += px / ps * S
        y += py / ps * S
    else
        throw(ArgumentError("invalid dynamic_drift_flag $(flag)"))
    end
    return x, px, y, py, z, pz, S
end

function _reverse_dynamic_drift(elem::ThinStrongBeam, x, px, y, py, z, pz)
    flag = elem.dynamic_drift_flag
    S = 0.5 * (z - elem.zo)
    if flag == -2
        PSI = sqrt(1 + 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
        x -= S * px / (1 + pz)
        y -= S * py / (1 + pz)
        z += 2 * S * PSI
    elseif flag == -1
        x -= S * px
        y -= S * py
    elseif flag == 0
        x -= S * px
        y -= S * py
        pz += 0.25 * (px * px + py * py)
    elseif flag == 1
        PSI = sqrt(1 + 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
        x -= S * px / (1 + pz)
        y -= S * py / (1 + pz)
        z += 2 * S * PSI
        pz += (1 + pz) * PSI
    elseif flag == 2
        H0 = 0.5 * (px * px + py * py) / (1 + pz)
        ps0 = 1 + pz - 0.5 * H0
        pz += 0.5 * H0
        x -= px / ps0 * S
        y -= py / ps0 * S
        z += H0 / ps0 * S
    else
        throw(ArgumentError("invalid dynamic_drift_flag $(flag)"))
    end
    return x, px, y, py, z, pz
end

function _cp_kick(elem::ThinStrongBeam, S, x, px, y, py, z, pz)
    betx = elem.betx0 + 2 * S * elem.alfx0 + S * S * elem.gamx0
    bety = elem.bety0 + 2 * S * elem.alfy0 + S * S * elem.gamy0
    sigx = sqrt(elem.emitx * betx)
    sigy = sqrt(elem.emity * bety)
    xx = x - elem.xo + elem.pxo * S - 0.5 * elem.ppxo * S * S
    yy = y - elem.yo + elem.pyo * S - 0.5 * elem.ppyo * S * S
    Kx, Ky = gaussian_beambeam_kick(sigx, sigy, xx, yy)
    expterm = exp(-0.5 * (xx * xx / (sigx * sigx) + yy * yy / (sigy * sigy)))
    px += Kx * elem.kbb
    py += Ky * elem.kbb

    dsize = abs((sigx - sigy) / 2)
    msize = sigx - (sigx - sigy) / 2
    if dsize / msize < ROUND_BEAM_THRESHOLD
        Uxx = -elem.kbb * expterm / msize / sigx
        Uyy = -elem.kbb * expterm / msize / sigy
    else
        temp1 = elem.kbb * (xx * Kx + yy * Ky)
        temp2 = sigx * sigx - sigy * sigy
        temp3 = sigy / sigx
        Uxx = (temp1 - 2 * elem.kbb * (1 - expterm * temp3)) / temp2
        Uyy = (-temp1 + 2 * elem.kbb * (1 - expterm / temp3)) / temp2
    end
    dsigx2 = 0.5 * elem.emitx * (elem.alfx0 + S * elem.gamx0)
    dsigy2 = 0.5 * elem.emity * (elem.alfy0 + S * elem.gamy0)
    pz -= Uxx * dsigx2 + Uyy * dsigy2
    return x, px, y, py, z, pz, expterm / TWOPI / sigx / sigy
end

function gaussian_beambeam_kick(sigx, sigy, x, y)
    (sigx == 0 || sigy == 0) && return zero(x), zero(y)
    dsize = abs((sigx - sigy) / 2)
    msize = sigx - (sigx - sigy) / 2
    negx = x < 0
    negy = y < 0
    x = abs(x)
    y = abs(y)
    if dsize / msize < ROUND_BEAM_THRESHOLD
        rr = x * x + y * y
        if rr == 0
            return zero(x), zero(y)
        end
        temp = 2 * (1 - exp(-rr / (2 * msize * msize))) / rr
        Kx = temp * x
        Ky = temp * y
    else
        if sigx > sigy
            sig1, sig2, x1, x2 = sigx, sigy, x, y
        else
            sig1, sig2, x1, x2 = sigy, sigx, y, x
        end
        denominator = SQRT2 * sqrt(sig1 * sig1 - sig2 * sig2)
        z1 = complex(x1 / denominator, x2 / denominator)
        z2 = complex(sig2 / sig1 * x1 / denominator, sig1 / sig2 * x2 / denominator)
        A = 2 * SQRTPI / denominator
        B = exp(-x1 * x1 / (2 * sig1 * sig1) - x2 * x2 / (2 * sig2 * sig2))
        ret = A * (faddeeva_w(z1) - B * faddeeva_w(z2))
        if sigx > sigy
            Ky = real(ret)
            Kx = imag(ret)
        else
            Ky = imag(ret)
            Kx = real(ret)
        end
    end
    return negx ? -Kx : Kx, negy ? -Ky : Ky
end

function _gaussian_slices(::Type{T}, ns::Int, slice_center, slice_weight, sigz, method, width) where {T}
    if slice_center !== nothing && slice_weight !== nothing
        return _strong_tuple(slice_center, ns, T), _strong_tuple(slice_weight, ns, T)
    end
    sigz === nothing && throw(ArgumentError("GaussianStrongBeamSpec requires sigz unless slice_center and slice_weight are supplied"))
    method == :equal_area && return _equal_area_slices(T, ns, T(sigz))
    method == :equal_width && return _equal_width_slices(T, ns, T(sigz), T(width))
    throw(ArgumentError("unknown slice_method $method"))
end

function _equal_area_slices(::Type{T}, ns::Int, sigz::T) where {T}
    centers = zeros(T, ns)
    weights = fill(inv(T(ns)), ns)
    rr = SQRT2 * sigz
    if isodd(ns)
        w = (ns - 1) ÷ 2
        centers[w + 1] = zero(T)
        for i in 1:w
            centers[i + w + 1] = inverse_erf(2 * i / ns) * rr
            centers[-i + w + 1] = -centers[i + w + 1]
        end
    else
        w = ns ÷ 2
        for i in 1:w
            centers[i + w] = inverse_erf((2 * i - 1) / ns) * rr
            centers[-i + w + 1] = -centers[i + w]
        end
    end
    return Tuple(centers), Tuple(weights)
end

function _equal_width_slices(::Type{T}, ns::Int, sigz::T, width::T) where {T}
    centers = zeros(T, ns)
    weights = zeros(T, ns)
    nw = width / SQRT2 / sigz
    sumw = erf(nw * ns / 2)
    if isodd(ns)
        w = (ns - 1) ÷ 2
        upper = erf(0.5 * nw)
        weights[w + 1] = upper / sumw
        for i in 1:w
            centers[i + w + 1] = width * i
            centers[-i + w + 1] = -centers[i + w + 1]
            lower = upper
            upper = erf((i + 0.5) * nw)
            weights[i + w + 1] = (upper - lower) / 2 / sumw
            weights[-i + w + 1] = weights[i + w + 1]
        end
    else
        w = ns ÷ 2
        upper = zero(T)
        for i in 1:w
            centers[i + w] = (i - 0.5) * width
            centers[-i + w + 1] = -centers[i + w]
            lower = upper
            upper = erf(i * nw)
            weights[i + w] = (upper - lower) / 2 / sumw
            weights[-i + w + 1] = weights[i + w]
        end
    end
    return Tuple(centers), Tuple(weights)
end

function _crab_offsets(centers, coef, freq, harmonics)
    freq <= 0 && return ntuple(_ -> zero(coef), length(centers))
    kcc = TWOPI * freq / CLIGHT
    return ntuple(length(centers)) do i
        t = -centers[i]
        for (h, rel) in pairs(harmonics)
            t += rel * sin(h * kcc * centers[i]) / (h * kcc)
        end
        -coef * t
    end
end

function _strong_tuple(values)
    T = promote_type(map(typeof, values)...)
    return ntuple(i -> T(values[i]), length(values))
end

function _zero_signal_tuple(values)
    T = promote_type(map(typeof, values)...)
    return ntuple(_ -> zero(T), length(values))
end

function _strong_tuple(values, n::Int, ::Type{T}) where {T}
    length(values) == n || throw(ArgumentError("expected $n values, got $(length(values))"))
    return ntuple(i -> T(values[i]), n)
end

@element_spec begin
    kind = :thin_strong_beam
    spec_type = ElementSpec{:thin_strong_beam}
    friendly_constructor = ThinStrongBeamSpec
    runtime_type = ThinStrongBeam
    description = "Flexible thin weak-strong beam-beam interaction specification."
    keywords = [:beam_beam, :nonlinear_interaction]
    tracking_methods = [WeakStrongBeamBeamMap]
    contracts = [TrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        kbb=ParamMeta(required=true, meaning="beam-beam kick coefficient"),
        klum=ParamMeta(default=1, meaning="luminosity scale"),
        beta=ParamMeta(required=true, meaning="strong-beam beta functions"),
        alpha=ParamMeta(default=(0, 0), meaning="strong-beam alpha functions"),
        sigma=ParamMeta(required=true, meaning="strong-beam transverse sizes"),
        center=ParamMeta(default=(0, 0, 0), meaning="strong-beam closed orbit center"),
        angle=ParamMeta(default=(0, 0, 0), meaning="strong-beam closed orbit angle"),
        curvature=ParamMeta(default=(0, 0, 0), meaning="strong-beam closed orbit curvature"),
        dynamic_drift_flag=ParamMeta(default=0, meaning="Hirata/dynamic drift convention flag"),
        size_signal=ParamMeta(meaning="optional turn signal returning (sigx, sigy)"),
        centroid_signal=ParamMeta(meaning="optional turn signal returning (x, y)"),
        angle_signal=ParamMeta(meaning="optional turn signal returning (px, py)"),
        tracking_method=ParamMeta(default=WeakStrongBeamBeamMap(), meaning="per-element tracking method"),
    )
    example = ThinStrongBeamSpec{Float64}(kbb=1e-4, beta=(1.0, 1.0), sigma=(1e-3, 1e-3))
    construction_help = "Friendly constructor: ThinStrongBeamSpec{T}(; kbb, klum=1, beta, alpha=(0,0), sigma, center=(0,0,0), angle=(0,0,0), curvature=(0,0,0), dynamic_drift_flag=0, size_signal=nothing, centroid_signal=nothing, angle_signal=nothing, tracking_method=WeakStrongBeamBeamMap(), kwargs...)."
end

@element_spec begin
    kind = :gaussian_strong_beam
    spec_type = ElementSpec{:gaussian_strong_beam}
    friendly_constructor = GaussianStrongBeamSpec
    runtime_type = GaussianStrongBeam
    description = "Flexible sliced Gaussian weak-strong beam-beam interaction specification."
    keywords = [:beam_beam, :nonlinear_interaction]
    tracking_methods = [WeakStrongBeamBeamMap]
    contracts = [TrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        thin=ParamMeta(required=true, meaning="base ThinStrongBeamSpec or ThinStrongBeam"),
        ns=ParamMeta(required=true, meaning="number of longitudinal slices"),
        slice_center=ParamMeta(meaning="explicit slice centers"),
        slice_weight=ParamMeta(meaning="explicit slice weights"),
        slice_hoffset=ParamMeta(meaning="explicit horizontal slice offsets"),
        slice_voffset=ParamMeta(meaning="explicit vertical slice offsets"),
        sigz=ParamMeta(meaning="strong-beam longitudinal rms size; required unless explicit slice_center and slice_weight are supplied"),
        slice_method=ParamMeta(default=:equal_area, meaning=":equal_area or :equal_width"),
        slice_width=ParamMeta(meaning="slice width for :equal_width"),
        hvoffset=ParamMeta(meaning="optional Dict with dim, coef, frequency, harmonics"),
        tracking_method=ParamMeta(default=WeakStrongBeamBeamMap(), meaning="per-element tracking method"),
    )
    example = GaussianStrongBeamSpec{Float64}(thin=ThinStrongBeamSpec{Float64}(kbb=1e-4, beta=(1.0, 1.0), sigma=(1e-3, 1e-3)), ns=3, sigz=0.01)
    construction_help = "Friendly constructor: GaussianStrongBeamSpec{T}(; thin, ns, sigz, slice_method=:equal_area, slice_width=nothing, slice_center=nothing, slice_weight=nothing, slice_hoffset=nothing, slice_voffset=nothing, hvoffset=nothing, tracking_method=WeakStrongBeamBeamMap(), kwargs...)."
end

default_method(::Type{ElementSpec{:thin_strong_beam}}) = WeakStrongBeamBeamMap()
default_method(::Type{ElementSpec{:gaussian_strong_beam}}) = WeakStrongBeamBeamMap()
