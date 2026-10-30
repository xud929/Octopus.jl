export ParticleLinear6D, TuneFunction, TuneDistribution, TuneHistogram

const _PARTICLE_TUNE_PLANES = (:nux, :nuy, :nuz)

function _tune_planes(planes)
    planes === nothing && return nothing
    planes isa Tuple && !isempty(planes) || throw(ArgumentError(
        "tune source planes must be a nonempty tuple of nux, nuy, nuz"))
    all(p -> p in _PARTICLE_TUNE_PLANES, planes) || throw(ArgumentError(
        "tune source planes contain an unknown name; use nux, nuy, nuz"))
    length(unique(planes)) == length(planes) || throw(ArgumentError(
        "tune source planes must not repeat a name"))
    return planes
end

"""
    TuneFunction(f; planes=nothing)

An entrance-coordinate tune source, evaluated as `f(x, px, y, py, z, pz)`
once per particle when its `Linear6DSpec` placement first initializes.
The coordinates are physical canonical entrance coordinates, before linear
normalization. The function must be deterministic and side-effect free.

Inside `particle_tunes=(nux=TuneFunction(f),)`, the plane is inferred. A
top-level joint source requires `planes`, for example `(:nux, :nuz)`, and
returns a tuple/vector in that order or a NamedTuple with exactly those keys.
One-plane sources return a scalar. All tunes must be finite real non-Bool
values. Ordinary six-argument functions need no wrapper in a per-plane input;
the wrapper also supports callable structs.
"""
struct TuneFunction{F,P}
    f::F
    planes::P
end
TuneFunction(f; planes=nothing) = TuneFunction(f, _tune_planes(planes))

"""
    TuneDistribution(distribution; planes=nothing)

A tune source drawn through `rand(rng, distribution)` once per particle.
Octopus supplies a private, counter-backed `Random.AbstractRNG` keyed by
seed, stream, initialization epoch, named planes and global particle ID.
The sampler must use only this RNG and must not reseed, retain or share it.
Scalar uniform/integer/normal and bulk draws are supported; arbitrary
third-party samplers may require additional Random methods.

Planes and scalar/joint return shapes follow [`TuneFunction`](@ref). Separate
per-plane distributions draw independently; one named joint distribution
preserves its sampled correlations. Sampling runs on the host once, including
for CUDA tracking. [`TuneHistogram`](@ref) is a built-in distribution.
"""
struct TuneDistribution{D,P}
    distribution::D
    planes::P
end
TuneDistribution(distribution; planes=nothing) =
    TuneDistribution(distribution, _tune_planes(planes))

"""
    TuneHistogram(edges, weights)

Piecewise-uniform one-, two- or three-dimensional tune distribution for
[`TuneDistribution`](@ref). For one dimension, pass edge and weight vectors;
for joint sampling, pass a tuple of edge vectors and an array of bin masses
whose shape is `map(e -> length(e)-1, edges)`. Edges must be finite and
strictly increasing. Weights are finite nonnegative **bin masses**, not
densities, with positive finite total mass; zero-mass bins are never drawn.
Sampling chooses a bin by mass and then a uniform point inside each interval.
Input edges and weights are copied. The histogram uses Float64 preparation;
assigned tunes convert to the element's declared Float32/Float64 precision.
"""
struct TuneHistogram{N}
    edges::NTuple{N,Vector{Float64}}
    shape::NTuple{N,Int}
    cdf::Vector{Float64}
end

function TuneHistogram(edges, weights)
    edge_tuple = edges isa AbstractVector ? (edges,) : edges
    edge_tuple isa Tuple && 1 <= length(edge_tuple) <= 3 || throw(ArgumentError(
        "TuneHistogram needs one edge vector or a tuple of one to three edge vectors"))
    copied = map(edge_tuple) do edge
        edge isa AbstractVector && length(edge) >= 2 || throw(ArgumentError(
            "TuneHistogram edge vectors need at least two entries"))
        values = [_checked_tune(v, Float64, "TuneHistogram edge") for v in Array(edge)]
        all(i -> values[i] < values[i+1], 1:length(values)-1) || throw(ArgumentError(
            "TuneHistogram edges must be strictly increasing"))
        values
    end
    shape = map(e -> length(e)-1, copied)
    weights isa AbstractArray && size(weights) == shape || throw(ArgumentError(
        "TuneHistogram weight shape must equal the number of intervals in each dimension"))
    masses = [_checked_tune(w, Float64, "TuneHistogram weight") for w in vec(Array(weights))]
    all(>=(0), masses) || throw(ArgumentError("TuneHistogram weights must be nonnegative"))
    total = sum(masses)
    isfinite(total) && total > 0 || throw(ArgumentError(
        "TuneHistogram needs a positive finite total bin mass"))
    cdf = cumsum(masses ./ total)
    cdf ./= cdf[end]
    previous = 0.0
    for i in eachindex(cdf)
        masses[i] == 0 || cdf[i] > previous || throw(ArgumentError(
            "TuneHistogram positive bin mass is too small to represent in its Float64 CDF"))
        previous = cdf[i]
    end
    cdf[end] = 1.0
    return TuneHistogram(copied, shape, cdf)
end

function Random.rand(rng::Random.AbstractRNG, histogram::TuneHistogram{N}) where {N}
    u = rand(rng)
    bin = min(searchsortedlast(histogram.cdf, u) + 1, length(histogram.cdf))
    indices = Tuple(CartesianIndices(histogram.shape)[bin])
    sample = ntuple(N) do d
        left = histogram.edges[d][indices[d]]
        right = histogram.edges[d][indices[d]+1]
        fraction = rand(rng)
        (1-fraction) * left + fraction * right
    end
    return N == 1 ? sample[1] : sample
end

struct _ParticleTuneGroup{P,S}
    planes::P
    source::S
    mode::Symbol
end

struct _ParticleTuneSources{G}
    groups::G
end

function _checked_tune(value, ::Type{T}, where_from) where {T}
    value isa Real && !(value isa Bool) && isfinite(value) || throw(ArgumentError(
        "$where_from must be a finite real tune, not a Bool or complex value"))
    converted = try
        T(value)
    catch err
        throw(ArgumentError("$where_from cannot convert to $T: $(sprint(showerror, err))"))
    end
    isfinite(converted) || throw(ArgumentError("$where_from overflows the tune precision $T"))
    return converted
end

_tune_plane_index(plane) = findfirst(==(plane), _PARTICLE_TUNE_PLANES)::Int
_tune_plane_mask(planes) = sum(p -> UInt8(1) << (_tune_plane_index(p)-1), planes)

function _particle_tune_group(source, enclosing)
    if source isa Union{TuneFunction,TuneDistribution}
        planes = source.planes === nothing ? enclosing : source.planes
        planes === nothing && throw(ArgumentError(
            "a top-level TuneFunction or TuneDistribution requires explicit planes"))
        enclosing === nothing || planes == enclosing || throw(ArgumentError(
            "a tune source's planes must agree with its enclosing named plane"))
        _tune_planes(planes)
        if source isa TuneFunction
            return _ParticleTuneGroup(planes, source.f, :function)
        end
        dist = source.distribution
        dist isa TuneHistogram && length(dist.edges) != length(planes) && throw(ArgumentError(
            "TuneHistogram dimensionality must match its declared tune planes"))
        return _ParticleTuneGroup(planes, dist, :distribution)
    end
    enclosing === nothing && throw(ArgumentError(
        "particle_tunes requires named planes or a TuneFunction/TuneDistribution with planes"))
    if source isa Real && !(source isa Bool)
        _checked_tune(source, Float64, "constant tune")
        return _ParticleTuneGroup(enclosing, source, :constant)
    elseif source isa AbstractVector
        return _ParticleTuneGroup(enclosing, source, :array)
    elseif source isa Function
        return _ParticleTuneGroup(enclosing, source, :function)
    end
    throw(ArgumentError(
        "unknown particle tune source; use a finite real scalar, vector, six-argument function, TuneFunction, or TuneDistribution"))
end

function _collect_particle_tune_groups!(out, input)
    if input isa NamedTuple
        isempty(input) && throw(ArgumentError("particle_tunes must not be an empty NamedTuple"))
        _tune_planes(keys(input))
        for (plane, source) in pairs(input)
            push!(out, _particle_tune_group(source, (plane,)))
        end
    elseif input isa Tuple
        isempty(input) && throw(ArgumentError("particle_tunes source groups must not be empty"))
        for group in input
            _collect_particle_tune_groups!(out, group)
        end
    else
        push!(out, _particle_tune_group(input, nothing))
    end
    return out
end

_normalize_particle_tunes(input::_ParticleTuneSources) = input
_normalize_particle_tunes(::Nothing) = nothing
function _normalize_particle_tunes(input)
    groups = _collect_particle_tune_groups!(Any[], input)
    occupied = UInt8(0)
    for group in groups
        mask = _tune_plane_mask(group.planes)
        iszero(occupied & mask) || throw(ArgumentError(
            "particle_tunes source groups must not overlap a named plane"))
        occupied |= mask
    end
    sort!(groups; by=g -> _tune_plane_mask(g.planes))
    return _ParticleTuneSources(Tuple(groups))
end

_particle_tunes_stochastic(::Nothing) = false
_particle_tunes_stochastic(sources::_ParticleTuneSources) =
    any(g -> g.mode === :distribution, sources.groups)
_particle_tunes_coordinate_source(sources::_ParticleTuneSources) =
    any(g -> g.mode === :function, sources.groups)

function _particle_tune_rng_id(sources, rng_id; claim=false)
    rng_id isa Integer && !(rng_id isa Bool) && 0 <= rng_id <= typemax(UInt64) ||
        throw(ArgumentError("particle-tune rng_id must be a nonnegative UInt64-representable integer"))
    if !_particle_tunes_stochastic(sources)
        iszero(rng_id) || throw(ArgumentError(
            "rng_id is inactive without a particle-tune distribution; omit it or use zero"))
        return UInt64(0)
    end
    if claim
        return iszero(rng_id) ? next_rng_id!(consumer=:particle_tunes) :
               claim_rng_id!(rng_id; consumer=:particle_tunes)
    end
    iszero(rng_id) && throw(ArgumentError(
        "raw stochastic ElementSpec{:linear6d} needs a resolved nonzero rng_id; use Linear6DSpec to allocate and claim a stream"))
    return UInt64(rng_id)
end

_particle_tune_stream_keys(::AbstractElementSpec) = ()
function _particle_tune_stream_keys(spec::ElementSpec{:linear6d})
    sources = _normalize_particle_tunes(getparam(spec, :particle_tunes, nothing))
    _particle_tunes_stochastic(sources) || return ()
    rng_id = _particle_tune_rng_id(sources, getparam(spec, :rng_id, 0))
    return Tuple((rng_id, _tune_plane_mask(g.planes)) for g in sources.groups if g.mode === :distribution)
end

"""Warn once at task construction when stochastic tune placements draw from
the same stream AND the same named source band. Reuse the declaration walker
so nested lines and placement overrides follow the existing spec traversal,
without an unnecessary survey or a second container enumeration."""
function _warn_duplicate_particle_tune_streams(elements::Tuple)
    keys = Tuple{UInt64,UInt8}[]
    _collect_declared!(keys, elements, _particle_tune_stream_keys)
    duplicates = [key for key in unique(keys) if count(==(key), keys) > 1]
    isempty(duplicates) && return nothing
    @warn "multiple particle-tune placements share an rng_id and named source band: their underlying draws are identical and their sampled tunes are correlated. Give each independent placement a distinct rng_id or construct a separate Linear6DSpec with rng_id=0." streams=duplicates
    return nothing
end

# Counter-RNG component namespace: high bit 1, bits 56:58 the nonzero plane
# mask, low 56 bits the draw ordinal. Current particle consumers use components
# 1:6; turn rules have particle slot 0. A source can never draw into another
# source's band; ordinal exhaustion is checked before its first invalid draw.
# The existing counter's turn dimension carries the explicit rearm epoch,
# never the actual tracking turn. Keep these bounds as the source of truth.
const _PARTICLE_TUNE_COMPONENT_BASE = UInt64(1) << 63
const _PARTICLE_TUNE_DRAW_MAX = (UInt64(1) << 56) - UInt64(1)

mutable struct _ParticleTuneRNG <: Random.AbstractRNG
    seed::UInt64
    method::UInt8
    epoch::UInt64
    rng_id::UInt64
    particle_id::UInt64
    plane_mask::UInt8
    ordinal::UInt64
end

function _particle_tune_rng(ctx, rng_id, particle_id, planes, epoch)
    epoch isa Integer && 0 <= epoch <= typemax(UInt64) || throw(ArgumentError(
        "particle-tune initialization epoch must fit UInt64"))
    return _ParticleTuneRNG(ctx.seed, ctx.rng_method, UInt64(epoch), UInt64(rng_id),
                            UInt64(particle_id), _tune_plane_mask(planes), UInt64(0))
end

function Random.rand(rng::_ParticleTuneRNG, ::Random.SamplerType{UInt64})
    rng.ordinal <= _PARTICLE_TUNE_DRAW_MAX || throw(ArgumentError(
        "particle-tune sampler exhausted its counter draw namespace"))
    component = _PARTICLE_TUNE_COMPONENT_BASE | (UInt64(rng.plane_mask) << 56) | rng.ordinal
    value = octopus_uint64(rng.seed, rng.method, rng.epoch, rng.rng_id, rng.particle_id, component)
    rng.ordinal += UInt64(1)
    return value
end
Random.rng_native_52(::_ParticleTuneRNG) = UInt64
for T in (Bool, Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64)
    # `% T` converts the uniformly random bits modulo the target bit width;
    # Random.rand_generic has no Type{UInt32} method on Julia 1.12. Use the
    # public integer conversion directly rather than an internal helper's
    # version-dependent argument convention.
    @eval Random.rand(rng::_ParticleTuneRNG, ::Random.SamplerType{$T}) = rand(rng, UInt64) % $T
end
Random.rand(rng::_ParticleTuneRNG, ::Random.SamplerType{UInt128}) =
    (UInt128(rand(rng, UInt64)) << 64) | UInt128(rand(rng, UInt64))
Random.rand(rng::_ParticleTuneRNG, ::Random.SamplerType{Int128}) = rand(rng, UInt128) % Int128
Random.seed!(::_ParticleTuneRNG, args...) = throw(ArgumentError(
    "particle-tune samplers must not reseed the supplied counter RNG"))

const _PARTICLE_TUNES_TASK_REQUIRED =
    "ParticleLinear6D requires TrackingTask ownership and initialized per-particle tunes; bare track!, contextless scalar maps, Matrix and optics analysis are unsupported"

"""
    ParticleLinear6D

The `Linear6DSpec(particle_tunes=...)` runtime variant. It applies a shared
exit normalization, a fixed per-particle three-plane rotation, and the inverse
entrance normalization. A TrackingTask owns its persistent tune and cached
sine/cosine arrays; compilation alone is an unbound, source-only description.
The active variant supports Float32 and Float64. It is symplectic for each
fixed tune triple. Contextless scalar maps, bare tracking, Matrix and optics
analysis refuse because no unique particle map is selected. Use
`particle_tune_tables(task)` for independent copies of the assigned labels.
"""
struct ParticleLinear6D{M<:AbstractTrackingMethod,T<:Number,S,V} <: AbstractTrackOp
    method::M
    A::NTuple{36,T}
    inv_A::NTuple{36,T}
    nominal_tunes::NTuple{3,T}
    source::S
    rng_id::UInt64
    index_offset::Int64
    tunes::NTuple{3,V}
    rotations::NTuple{6,V}
end

_particle_tunes_bound(op::ParticleLinear6D) = op.tunes[1] !== nothing
_requires_tracking_task(::ParticleLinear6D) = true
_requires_tracking_task(spec::ElementSpec{:linear6d}) = getparam(spec, :particle_tunes, nothing) !== nothing

function runtime_type(spec::ElementSpec{:linear6d}, method)
    M = _tracking_method_type(method)
    M === Symplectic6DMap || return runtime_type(typeof(spec), M)
    return getparam(spec, :particle_tunes, nothing) === nothing ? Linear6D : ParticleLinear6D
end

function _particle_tune_normalizer(beta, alpha, zeta, eta, coupling, ::Type{T}) where {T}
    b = _linear6d_tuple(beta, 3, T)
    a = _linear6d_tuple(alpha, 3, T)
    all(v -> isfinite(v) && v > 0, b) || throw(ArgumentError(
        "particle-tune beta functions must be positive and finite"))
    all(isfinite, a) || throw(ArgumentError("particle-tune alpha functions must be finite"))
    N = _zero66(T)
    for i in 1:3
        row = 2i-1
        root_beta = sqrt(b[i])
        N = _mset(N, row, row, root_beta)
        N = _mset(N, row+1, row, -a[i]/root_beta)
        N = _mset(N, row+1, row+1, inv(root_beta))
    end
    A = _mmul66(_mmul66(_mmul66(_mzeta66(_linear6d_tuple(zeta, 4, T)),
                                _meta66(_linear6d_tuple(eta, 4, T))),
                        _mR66(_linear6d_tuple(coupling, 4, T))), N)
    _validate_linear6d_symplectic(A; source="particle-tune normalization")
    return A
end

function ParticleLinear6D(spec::ElementSpec{:linear6d}, method::Symplectic6DMap)
    hasparam(spec, :matrix) && throw(ArgumentError(
        "particle_tunes requires the Linear6DSpec optics form; an explicit matrix has no declared normalization"))
    T = numeric_type(spec)
    T in (Float32, Float64) || throw(ArgumentError(
        "particle_tunes supports Float32 or Float64; the ordinary Linear6D remains available for other Number types"))
    source = _normalize_particle_tunes(getparam(spec, :particle_tunes, nothing))
    source === nothing && throw(ArgumentError("ParticleLinear6D requires active particle_tunes"))
    rng_id = _particle_tune_rng_id(source, getparam(spec, :rng_id, 0))
    (hasparam(spec, :beta1) && hasparam(spec, :dmu)) || throw(ArgumentError(
        "particle_tunes requires beta1 and dmu in Linear6DSpec"))
    for key in _PLACEMENT_PARAM_KEYS
        value = _declared_param(spec, key)
        allowed = key === :misalign_convention ? value === :bmad : value isa Number && iszero(value)
        allowed || throw(ArgumentError(
            "particle_tunes does not support non-default placement parameter $key; use an ordinary unwrapped placement"))
    end
    b1 = param(spec, :beta1)
    a1 = getparam(spec, :alpha1, (0, 0, 0))
    z1 = getparam(spec, :zeta1, (0, 0, 0, 0))
    e1 = getparam(spec, :eta1, (0, 0, 0, 0))
    c1 = getparam(spec, :R1, (0, 0, 0, 0))
    Ain = _particle_tune_normalizer(b1, a1, z1, e1, c1, T)
    Aout = _particle_tune_normalizer(getparam(spec, :beta2, b1), getparam(spec, :alpha2, a1),
                                     getparam(spec, :zeta2, z1), getparam(spec, :eta2, e1),
                                     getparam(spec, :R2, c1), T)
    phases = _linear6d_tuple(param(spec, :dmu), 3, T)
    all(isfinite, phases) || throw(ArgumentError("particle-tune dmu must be finite"))
    nominal = map(v -> v / T(2pi), phases)
    return ParticleLinear6D(method, Aout, _minv66(Ain), nominal, source, rng_id, Int64(0),
                            (nothing, nothing, nothing), ntuple(_ -> nothing, 6))
end

function _particle_tune_binding_key(op::ParticleLinear6D)
    op.source === nothing && throw(ArgumentError("a tune binding key requires the unbound source runtime"))
    groups = op.source.groups
    mask = foldl((m, g) -> m | _tune_plane_mask(g.planes), groups; init=UInt8(0))
    nominal = ntuple(k -> iszero(mask & (UInt8(1) << (k-1))) ? op.nominal_tunes[k] : nothing, 3)
    sources = map(groups) do group
        identity = group.mode === :constant ? group.source : objectid(group.source)
        (group.planes, group.mode, identity)
    end
    return (nominal, sources, op.rng_id)
end

function _particle_tune_descriptors(op::ParticleLinear6D)
    op.source === nothing && return ()
    return map(g -> (planes=g.planes, kind=g.mode), op.source.groups)
end

_particle_tunes_need_coordinates(op::ParticleLinear6D) =
    op.source !== nothing && _particle_tunes_coordinate_source(op.source)
function _particle_tune_planes(op::ParticleLinear6D)
    op.source === nothing && return ()
    return Tuple(p for p in _PARTICLE_TUNE_PLANES if any(g -> p in g.planes, op.source.groups))
end

function _validate_particle_tune_shape(op::ParticleLinear6D{M,T}; global_n, index_offset, local_n) where {M,T}
    global_n >= 0 && index_offset >= 0 && local_n >= 0 && index_offset+local_n <= global_n ||
        throw(ArgumentError("particle-tune global count and local shard interval are inconsistent"))
    op.source === nothing && throw(ArgumentError("source validation needs an unbound particle-tune runtime"))
    for group in op.source.groups
        if group.mode === :array
            length(group.source) == global_n || throw(ArgumentError(
                "particle-tune $(group.planes) array length $(length(group.source)) must equal global particle count $global_n"))
            for value in Array(group.source)
                _checked_tune(value, T, "particle-tune $(group.planes) array value")
            end
        elseif group.mode === :constant
            _checked_tune(group.source, T, "particle-tune $(group.planes) constant")
        end
    end
    return nothing
end

function _particle_tune_result(result, planes, ::Type{T}) where {T}
    if length(planes) == 1
        return (_checked_tune(result, T, "particle-tune $(planes[1]) source result"),)
    end
    values = if result isa NamedTuple
        length(result) == length(planes) && all(p -> haskey(result, p), planes) || throw(ArgumentError(
            "joint particle-tune result names must exactly match the declared planes"))
        map(p -> getproperty(result, p), planes)
    elseif result isa Union{Tuple,AbstractVector}
        length(result) == length(planes) || throw(ArgumentError(
            "joint particle-tune result length must match its declared planes"))
        Tuple(result)
    else
        throw(ArgumentError("joint particle-tune result must be a tuple, vector, or NamedTuple"))
    end
    return map(v -> _checked_tune(v, T, "joint particle-tune source result"), values)
end

function _initialize_particle_tunes(op::ParticleLinear6D{M,T}, hostcoords, ctx;
                                    index_offset=0,
                                    local_n=hostcoords === nothing ? nothing : length(hostcoords[1]),
                                    global_n=local_n, epoch=0) where {M,T}
    local_n isa Integer || throw(ArgumentError("particle-tune initialization needs local_n when no coordinates are supplied"))
    if hostcoords !== nothing
        length(hostcoords) == 6 || throw(ArgumentError("particle-tune initialization needs six coordinate arrays"))
        all(a -> length(a) == local_n, hostcoords) || throw(ArgumentError(
            "particle-tune initialization coordinate arrays must have equal lengths"))
    end
    _validate_particle_tune_shape(op; global_n, index_offset, local_n)
    if _particle_tunes_coordinate_source(op.source)
        hostcoords === nothing && throw(ArgumentError("coordinate-dependent particle tunes need entrance coordinates"))
        all(a -> all(isfinite, a), hostcoords) || throw(ArgumentError(
            "coordinate-dependent particle tunes require finite coordinates for every entrance particle"))
    end
    tunes = ntuple(k -> fill(op.nominal_tunes[k], local_n), 3)
    for group in op.source.groups
        array = group.mode === :array ? Array(group.source) : nothing
        for i in 1:local_n
            result = if group.mode === :constant
                group.source
            elseif group.mode === :array
                array[index_offset+i]
            elseif group.mode === :function
                group.source(ntuple(k -> hostcoords[k][i], 6)...)
            else
                rng = _particle_tune_rng(ctx, op.rng_id, index_offset+i, group.planes, epoch)
                try
                    rand(rng, group.source)
                catch err
                    throw(ArgumentError("particle-tune distribution sampling failed: $(sprint(showerror, err))"))
                end
            end
            values = _particle_tune_result(result, group.planes, T)
            for (plane, value) in zip(group.planes, values)
                tunes[_tune_plane_index(plane)][i] = value
            end
        end
    end
    rotations = ntuple(_ -> Vector{T}(undef, local_n), 6)
    for k in 1:3, i in 1:local_n
        # Preserve the original absolute tune label. Only phase evaluation is
        # reduced modulo one to keep every finite tune away from overflow.
        sine, cosine = sincos(T(2pi) * rem(tunes[k][i], one(T)))
        rotations[2k-1][i] = sine
        rotations[2k][i] = cosine
    end
    return (tunes=tunes, rotations=rotations)
end

function _bind_particle_tunes(op::ParticleLinear6D, tunes, rotations, index_offset)
    return ParticleLinear6D(op.method, op.A, op.inv_A, op.nominal_tunes, nothing, op.rng_id,
                            Int64(index_offset), tunes, rotations)
end

function _adapt_particle_linear6d(to, op::ParticleLinear6D)
    _particle_tunes_bound(op) || throw(ArgumentError(_PARTICLE_TUNES_TASK_REQUIRED))
    return _bind_particle_tunes(op, Adapt.adapt(to, op.tunes), Adapt.adapt(to, op.rotations), op.index_offset)
end

@inline function _particle_tune_matvec(m, x, px, y, py, z, pz)
    return ntuple(Val(6)) do row
        start = 6(row-1)
        fma(m[start+1], x, fma(m[start+2], px, fma(m[start+3], y,
            fma(m[start+4], py, fma(m[start+5], z, m[start+6]*pz)))))
    end
end

@inline function (op::ParticleLinear6D)(::TrackingContext, particle_id, x, px, y, py, z, pz)
    _particle_tunes_bound(op) || throw(ArgumentError(_PARTICLE_TUNES_TASK_REQUIRED))
    index = particle_id-op.index_offset
    1 <= index <= length(op.tunes[1]) || throw(ArgumentError(
        "particle-tune runtime received a global particle ID outside its bound shard"))
    qx, qpx, qy, qpy, qz, qpz = _particle_tune_matvec(op.inv_A, x, px, y, py, z, pz)
    @inbounds begin
        sx, cx = op.rotations[1][index], op.rotations[2][index]
        sy, cy = op.rotations[3][index], op.rotations[4][index]
        sz, cz = op.rotations[5][index], op.rotations[6][index]
    end
    return _particle_tune_matvec(op.A,
        fma(cx, qx, sx*qpx), fma(-sx, qx, cx*qpx),
        fma(cy, qy, sy*qpy), fma(-sy, qy, cy*qpy),
        fma(cz, qz, sz*qpz), fma(-sz, qz, cz*qpz))
end

@inline (::ParticleLinear6D)(x, px, y, py, z, pz) = throw(ArgumentError(_PARTICLE_TUNES_TASK_REQUIRED))
@inline track_particle(::Symplectic6DMap, ::ParticleLinear6D, x, px, y, py, z, pz) =
    throw(ArgumentError(_PARTICLE_TUNES_TASK_REQUIRED))
Base.Matrix(::ParticleLinear6D) = throw(ArgumentError(_PARTICLE_TUNES_TASK_REQUIRED))

_cross_backend_rounding(::ParticleLinear6D) = _rounding_class(bitwise=_COORDINATE_NAMES,
    why="shared normalization and frozen rotation coefficients are prepared on the host; every device/host matrix sum and rotation uses explicit IEEE fma with the same order")

function _element_metadata_probe(spec::ElementSpec{:linear6d}, coordinates)
    getparam(spec, :particle_tunes, nothing) === nothing &&
        return collect(compile_runtime(spec)(coordinates...))
    T = numeric_type(spec)
    rep = Phase6DRep(ntuple(i -> [T(coordinates[i])], 6)...)
    task = TrackingTask((spec,); policy=CPUThreadsExecutionPolicy(threads=1))
    execute!(task, rep; turns=1)
    return collect(rep[1])
end
