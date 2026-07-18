export LumpedRadSpec, LumpedRad

abstract type LumpedRadSpec{T} end

"""
    LumpedRadSpec{T=Float64}(; damping_turns, beta=(1,1,1), alpha=(0,0,0),
                              sigma=(-1,-1,-1), zeta=(0,0,0,0),
                              eta=(0,0,0,0), R=(0,0,0,0),
                              is_damping=true, is_excitation=true,
                              tracking_method=Radiation6DMap(), rng_id=0,
                              kwargs...)

Create an `ElementSpec{:lumped_radiation}` for a lumped damping and stochastic
excitation element.
"""
LumpedRadSpec(; kwargs...) = LumpedRadSpec{Float64}(; kwargs...)
function (::Type{LumpedRadSpec{T}})(;
                                    damping_turns,
                                    beta=(one(T), one(T), one(T)),
                                    alpha=(zero(T), zero(T), zero(T)),
                                    sigma=(-one(T), -one(T), -one(T)),
                                    zeta=(zero(T), zero(T), zero(T), zero(T)),
                                    eta=(zero(T), zero(T), zero(T), zero(T)),
                                    R=(zero(T), zero(T), zero(T), zero(T)),
                                    is_damping=true,
                                    is_excitation=true,
                                    tracking_method=Radiation6DMap(),
                                    rng_id=zero(UInt64),
                                    kwargs...) where {T}
    stream_id = UInt64(rng_id)
    stream_id == 0 && (stream_id = next_rng_id!())
    return ElementSpec{:lumped_radiation}(
        _spec_params(;
            damping_turns=_fixed_tuple(damping_turns, 3, T),
            beta=_fixed_tuple(beta, 3, T),
            alpha=_fixed_tuple(alpha, 3, T),
            sigma=_fixed_tuple(sigma, 3, T),
            zeta=_fixed_tuple(zeta, 4, T),
            eta=_fixed_tuple(eta, 4, T),
            R=_fixed_tuple(R, 4, T),
            is_damping=Bool(is_damping),
            is_excitation=Bool(is_excitation),
            tracking_method=tracking_method,
            rng_id=stream_id,
            kwargs...,
        ),
    )
end

struct LumpedRad{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    is_damping::Bool
    is_excitation::Bool
    damping::NTuple{3,T}
    excitation::NTuple{9,T}
    zeta::CrabDispersion{Symplectic6DMap,T}
    eta::MomentumDispersion{Symplectic6DMap,T}
    coupling::XYCoupling{Symplectic6DMap,T}
    rng_id::UInt64
end

function LumpedRad(spec::ElementSpec{:lumped_radiation},
                   method::AbstractTrackingMethod=tracking_method(spec))
    turns = param(spec, :damping_turns)
    beta = param(spec, :beta)
    alpha = param(spec, :alpha)
    sigma = param(spec, :sigma)
    zeta = param(spec, :zeta)
    eta = param(spec, :eta)
    R = param(spec, :R)
    T = promote_type(map(typeof, (turns..., beta..., alpha..., sigma..., zeta..., eta..., R...))...)
    turns_t = _fixed_tuple(turns, 3, T)
    beta_t = _fixed_tuple(beta, 3, T)
    alpha_t = _fixed_tuple(alpha, 3, T)
    sigma_t = _fixed_tuple(sigma, 3, T)
    valid_turns = all(t -> t > zero(T), turns_t)
    damping = ntuple(i -> valid_turns ? exp(-one(T) / turns_t[i]) : one(T), 3)
    excitation = _radiation_excitation(damping, beta_t, alpha_t, sigma_t)
    valid_excitation = all(i -> excitation[3 * i - 2] >= zero(T) &&
                                excitation[3 * i - 1] >= zero(T), 1:3)
    return LumpedRad(
        method,
        Bool(getparam(spec, :is_damping, true)) && valid_turns,
        Bool(getparam(spec, :is_excitation, true)) && valid_turns && valid_excitation,
        damping,
        excitation,
        CrabDispersion(Symplectic6DMap(), _fixed_tuple(zeta, 4, T)...),
        MomentumDispersion(Symplectic6DMap(), _fixed_tuple(eta, 4, T)...),
        XYCoupling(_fixed_tuple(R, 4, T)..., XY_MODEA),
        UInt64(getparam(spec, :rng_id, 0)),
    )
end

@inline function track_particle(::Radiation6DMap, elem::LumpedRad, x, px, y, py, z, pz)
    elem.is_excitation || return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                                            false, false, false,
                                                            false, false, false)
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                      Random.randn(), Random.randn(), Random.randn(),
                                      Random.randn(), Random.randn(), Random.randn())
end

@inline function track_particle(::Damping6DMap, elem::LumpedRad, x, px, y, py, z, pz)
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                      false, false, false, false, false, false,
                                      true, false)
end

@inline function track_particle(::Diffusion6DMap, elem::LumpedRad, x, px, y, py, z, pz)
    elem.is_excitation || return x, px, y, py, z, pz
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                      Random.randn(), Random.randn(), Random.randn(),
                                      Random.randn(), Random.randn(), Random.randn(),
                                      false, true)
end

@inline function _track_lumped_rad_particle(elem::LumpedRad, x, px, y, py, z, pz,
                                            nx, npx, ny, npy, nz, npz)
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                      nx, npx, ny, npy, nz, npz,
                                      elem.is_damping, elem.is_excitation)
end

@inline function _track_lumped_rad_particle(elem::LumpedRad, x, px, y, py, z, pz,
                                            nx, npx, ny, npy, nz, npz,
                                            apply_damping::Bool, apply_excitation::Bool)
    (elem.is_damping || elem.is_excitation) || return x, px, y, py, z, pz
    x, px, y, py, z, pz = _inverse(elem.zeta, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _inverse(elem.eta, x, px, y, py, z, pz)
    x, px, y, py, z, pz = _inverse(elem.coupling, x, px, y, py, z, pz)

    if apply_damping
        x *= elem.damping[1]
        px *= elem.damping[1]
        y *= elem.damping[2]
        py *= elem.damping[2]
        z *= elem.damping[3]
        pz *= elem.damping[3]
    end

    if apply_excitation
        x += elem.excitation[1] * nx
        px += elem.excitation[2] * npx + elem.excitation[3] * nx
        y += elem.excitation[4] * ny
        py += elem.excitation[5] * npy + elem.excitation[6] * ny
        z += elem.excitation[7] * nz
        pz += elem.excitation[8] * npz + elem.excitation[9] * nz
    end

    x, px, y, py, z, pz = elem.coupling(x, px, y, py, z, pz)
    x, px, y, py, z, pz = elem.eta(x, px, y, py, z, pz)
    return elem.zeta(x, px, y, py, z, pz)
end

@inline (elem::LumpedRad)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

@inline function (elem::LumpedRad)(ctx::TrackingContext, particle_id, x, px, y, py, z, pz)
    return _track_lumped_rad_context(elem.method, elem, ctx, particle_id, x, px, y, py, z, pz)
end

@inline function _track_lumped_rad_context(::Radiation6DMap, elem::LumpedRad,
                                           ctx::TrackingContext, particle_id,
                                           x, px, y, py, z, pz)
    elem.is_excitation || return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                                            false, false, false,
                                                            false, false, false)
    T = typeof(x + px + y + py + z + pz)
    nx = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 1, T)
    npx = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 2, T)
    ny = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 3, T)
    npy = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 4, T)
    nz = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 5, T)
    npz = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 6, T)
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz, nx, npx, ny, npy, nz, npz)
end

@inline function _track_lumped_rad_context(::Damping6DMap, elem::LumpedRad,
                                           ctx::TrackingContext, particle_id,
                                           x, px, y, py, z, pz)
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                      false, false, false, false, false, false,
                                      true, false)
end

@inline function _track_lumped_rad_context(::Diffusion6DMap, elem::LumpedRad,
                                           ctx::TrackingContext, particle_id,
                                           x, px, y, py, z, pz)
    elem.is_excitation || return x, px, y, py, z, pz
    T = typeof(x + px + y + py + z + pz)
    nx = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 1, T)
    npx = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 2, T)
    ny = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 3, T)
    npy = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 4, T)
    nz = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 5, T)
    npz = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, elem.rng_id, particle_id, 6, T)
    return _track_lumped_rad_particle(elem, x, px, y, py, z, pz,
                                      nx, npx, ny, npy, nz, npz,
                                      false, true)
end

function _fixed_tuple(values, n::Int, ::Type{T}) where {T}
    length(values) == n || throw(ArgumentError("expected $n values, got $(length(values))"))
    return ntuple(i -> T(values[i]), n)
end

function _radiation_excitation(damping::NTuple{3,T}, beta::NTuple{3,T},
                               alpha::NTuple{3,T}, sigma::NTuple{3,T}) where {T}
    values = ntuple(Val(9)) do j
        i = (j - 1) ÷ 3 + 1
        k = (j - 1) % 3 + 1
        if sigma[i] < zero(T) || beta[i] <= zero(T)
            return -one(T)
        end
        amp = sigma[i] * sqrt(max(zero(T), one(T) - damping[i] * damping[i]))
        slope = amp / beta[i]
        k == 1 && return amp
        k == 2 && return slope
        return -slope * alpha[i]
    end
    return values
end

@element_spec begin
    kind = :lumped_radiation
    spec_type = ElementSpec{:lumped_radiation}
    friendly_constructor = LumpedRadSpec
    runtime_type = LumpedRad
    description = "Flexible lumped radiation damping and excitation element specification."
    keywords = [:thin_element, :radiation]
    tracking_methods = [Radiation6DMap, Damping6DMap, Diffusion6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        damping_turns=ParamMeta(required=true, meaning="horizontal, vertical, and longitudinal damping turns"),
        beta=ParamMeta(default=(1, 1, 1), meaning="damped-mode beta values used by excitation"),
        alpha=ParamMeta(default=(0, 0, 0), meaning="damped-mode alpha values used by excitation"),
        sigma=ParamMeta(default=(-1, -1, -1), meaning="equilibrium beam sizes used by excitation; negative disables excitation"),
        zeta=ParamMeta(default=(0, 0, 0, 0), meaning="crab dispersion coefficients removed before damping"),
        eta=ParamMeta(default=(0, 0, 0, 0), meaning="momentum dispersion coefficients removed before damping"),
        R=ParamMeta(default=(0, 0, 0, 0), meaning="x-y coupling coefficients removed before damping"),
        is_damping=ParamMeta(default=true, meaning="enable radiation damping"),
        is_excitation=ParamMeta(default=true, meaning="enable stochastic excitation when sigma and beta are valid"),
        tracking_method=ParamMeta(default=Radiation6DMap(), meaning="per-element tracking method; use Damping6DMap() for damping only or Diffusion6DMap() for diffusion only"),
        rng_id=ParamMeta(default=0, meaning="counter-RNG stream id for stochastic excitation; 0 auto-assigns a unique id"),
    )
    example = LumpedRadSpec{Float64}(damping_turns=(1000.0, 1000.0, 500.0), rng_id=1)
    construction_help = "Friendly constructor: LumpedRadSpec{T}(; damping_turns, beta=(1,1,1), alpha=(0,0,0), sigma=(-1,-1,-1), zeta=(0,0,0,0), eta=(0,0,0,0), R=(0,0,0,0), is_damping=true, is_excitation=true, tracking_method=Radiation6DMap(), rng_id=0, kwargs...)."
end

default_method(::Type{ElementSpec{:lumped_radiation}}) = Radiation6DMap()
