export ThinCrabCavitySpec, ThinCrabCavity

abstract type ThinCrabCavitySpec{N} end

"""
    ThinCrabCavitySpec{N}(frequency; strengthX=(), strengthY=(), phase=(),
                          tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:thin_crab_cavity}` for a thin two-dimensional crab
cavity with `N` harmonics. `frequency` is in Hz. Each harmonic stores horizontal
strength, vertical strength, and phase. Extra keyword arguments are stored as
descriptive spec metadata.
"""
function (::Type{ThinCrabCavitySpec{N}})(frequency::Real;
                                         strengthX=(),
                                         strengthY=(),
                                         phase=(),
                                         tracking_method=Symplectic6DMap(),
                                         kwargs...) where {N}
    T = typeof(float(frequency))
    return ElementSpec{:thin_crab_cavity}(
        _spec_params(;
            N=N,
            frequency=T(frequency),
            strengthX=_harmonic_tuple(Val(N), strengthX, T),
            strengthY=_harmonic_tuple(Val(N), strengthY, T),
            phase=_harmonic_tuple(Val(N), phase, T),
            tracking_method=tracking_method,
            kwargs...,
        ),
    )
end

"""
    ThinCrabCavity{N}(frequency; strengthX, strengthY, phase)

Runtime thin 2D crab cavity with `N` harmonics: `N` is a type parameter,
and the harmonic data are stored in fixed-size tuples for CPU/GPU tracking.

The map applies the kick

```text
px -= strengthX[i] * sin(i*kcc*z + phase[i]) / (i*kcc)
py -= strengthY[i] * sin(i*kcc*z + phase[i]) / (i*kcc)
pz -= (strengthX[i]*x + strengthY[i]*y) * cos(i*kcc*z + phase[i])
```

for `i = 1:N`, leaving `x`, `y`, and `z` unchanged.
"""
struct ThinCrabCavity{N,M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    kcc::T
    strengthX::NTuple{N,T}
    strengthY::NTuple{N,T}
    phase::NTuple{N,T}
end

function ThinCrabCavity{N}(frequency::Real;
                           strengthX=(),
                           strengthY=(),
                           phase=()) where {N}
    T = typeof(float(frequency))
    kcc = T(2) * T(pi) * T(frequency) / T(CLIGHT)
    return ThinCrabCavity{N,Symplectic6DMap,T}(
        Symplectic6DMap(),
        kcc,
        _harmonic_tuple(Val(N), strengthX, T),
        _harmonic_tuple(Val(N), strengthY, T),
        _harmonic_tuple(Val(N), phase, T),
    )
end

function ThinCrabCavity(spec::ElementSpec{:thin_crab_cavity}, method::AbstractTrackingMethod=tracking_method(spec))
    N = param(spec, :N)
    frequency = param(spec, :frequency)
    T = typeof(float(frequency))
    return ThinCrabCavity{N,typeof(method),T}(
        method,
        T(2) * T(pi) * T(frequency) / T(CLIGHT),
        _harmonic_tuple(Val(N), param(spec, :strengthX), T),
        _harmonic_tuple(Val(N), param(spec, :strengthY), T),
        _harmonic_tuple(Val(N), param(spec, :phase), T),
    )
end

Base.getindex(cavity::ThinCrabCavity, row::Integer, harmonic::Integer) =
    _cavity_get(cavity, row, harmonic)
Base.getindex(spec::ElementSpec{:thin_crab_cavity}, row::Integer, harmonic::Integer) =
    _spec_cavity_get(spec, row, harmonic)

@inline function track_particle(::Symplectic6DMap, cavity::ThinCrabCavity{N,M,T}, x0, px0, y0, py0, z0, pz0) where {N,M,T}
    dpx = zero(T)
    dpy = zero(T)
    dpz = zero(T)
    for i in 1:N
        ikcc = T(i) * cavity.kcc
        θ = ikcc * z0 + cavity.phase[i]
        s = sin(θ)
        c = cos(θ)
        sx = cavity.strengthX[i]
        sy = cavity.strengthY[i]
        dpx -= sx * s / ikcc
        dpy -= sy * s / ikcc
        dpz -= (sx * x0 + sy * y0) * c
    end
    return x0, px0 + dpx, y0, py0 + dpy, z0, pz0 + dpz
end

@inline (cavity::ThinCrabCavity)(x0, px0, y0, py0, z0, pz0) =
    track_particle(cavity.method, cavity, x0, px0, y0, py0, z0, pz0)

function _harmonic_tuple(::Val{N}, values, ::Type{T}) where {N,T}
    if values === () || length(values) == 0
        return ntuple(_ -> zero(T), N)
    end
    length(values) == N || throw(ArgumentError("expected $N harmonic values, got $(length(values))"))
    return ntuple(i -> T(values[i]), N)
end

@element_spec begin
    kind = :thin_crab_cavity
    spec_type = ElementSpec{:thin_crab_cavity}
    friendly_constructor = ThinCrabCavitySpec
    runtime_type = ThinCrabCavity
    description = "Flexible thin 2D crab cavity specification with fixed harmonic count."
    keywords = [:thin_element, :crab_cavity, :harmonic]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        N=ParamMeta(required=true, meaning="maximum harmonic count encoded by ThinCrabCavitySpec{N}"),
        frequency=ParamMeta(required=true, unit="Hz", meaning="RF frequency"),
        strengthX=ParamMeta(default=(), meaning="horizontal kick strength tuple of length N"),
        strengthY=ParamMeta(default=(), meaning="vertical kick strength tuple of length N"),
        phase=ParamMeta(unit="rad", default=(), meaning="phase tuple of length N"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = ThinCrabCavitySpec{2}(1.0e8; strengthX=(1.0, 0.5), strengthY=(0.25, 0.125), phase=(0.0, 0.1))
    construction_help = "Friendly constructor: ThinCrabCavitySpec{N}(frequency; strengthX, strengthY, phase, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:thin_crab_cavity}(; N=N, frequency=frequency, strengthX=strengthX, strengthY=strengthY, phase=phase, tracking_method=tracking_method, kwargs...). Harmonic tuples must have length N; omitted tuples are filled with zeros."
end

@inline function _cavity_get(cavity, row::Integer, harmonic::Integer)
    (1 <= harmonic <= length(cavity.phase)) ||
        throw(BoundsError(cavity, (row, harmonic)))
    if row == 1
        return cavity.strengthX[harmonic]
    elseif row == 2
        return cavity.strengthY[harmonic]
    elseif row == 3
        return cavity.phase[harmonic]
    else
        throw(BoundsError(cavity, (row, harmonic)))
    end
end

@inline function _spec_cavity_get(spec::ElementSpec{:thin_crab_cavity}, row::Integer, harmonic::Integer)
    N = param(spec, :N)
    (1 <= harmonic <= N) || throw(BoundsError(spec, (row, harmonic)))
    if row == 1
        return param(spec, :strengthX)[harmonic]
    elseif row == 2
        return param(spec, :strengthY)[harmonic]
    elseif row == 3
        return param(spec, :phase)[harmonic]
    else
        throw(BoundsError(spec, (row, harmonic)))
    end
end
