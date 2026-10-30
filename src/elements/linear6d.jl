export Linear6DSpec, Linear6D

abstract type Linear6DSpec{T} end

"""
    Linear6DSpec{T=Float64}(; matrix, tracking_method=Symplectic6DMap(), kwargs...)
    Linear6DSpec{T=Float64}(; beta1, dmu, beta2=beta1, alpha1=(0,0,0),
                             alpha2=alpha1, zeta1=(0,0,0,0),
                             eta1=(0,0,0,0), R1=(0,0,0,0),
                             zeta2=zeta1, eta2=eta1, R2=R1,
                             particle_tunes=nothing, rng_id=0,
                             tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:linear6d}` for a six-dimensional linear transfer map.
The runtime stores the 6x6 matrix as a flat tuple for GPU-compatible callable
tracking. An explicit matrix must satisfy `transpose(M) * J * M = J` in the
canonical `(x, px, y, py, z, pz)` ordering. Validation uses a
precision-derived, magnitude-aware floating-point error bound.

Without the explicit `{T}`, the element type is inferred by promoting the
named parameters over a `Float64` floor, so a `Dual` or `Complex` parameter
differentiates without the caller having to spell the type — matching how
every lattice magnet promotes through `numeric_type(spec)` (2026-08-05_b
audit, U9-6). Integers, rationals and `Float32` still land on `Float64`;
narrowing stays behind the explicit `{T}` form. Extra keyword arguments are
descriptive metadata and take no part in the promotion.

The two forms are exclusive: `matrix` beside any optics keyword is refused by
name, at construction and again when a raw spec carrying both compiles. Until
the 2026-10-18 comprehensive audit the matrix won and the optics keywords
were dropped silently -- `Linear6DSpec(matrix=I6, beta1=..., dmu=...)` stored
`[:matrix, :tracking_method]` and nothing else (F-165). In the optics form
each exit parameter defaults to its entrance partner (`beta2 = beta1`,
`alpha2 = alpha1`, `zeta2 = zeta1`, `eta2 = eta1`, `R2 = R1`), through the
friendly constructor and the raw form alike, and the schema says so instead of
declaring a literal default the constructor never applied.

With `particle_tunes`, the optics form compiles to [`ParticleLinear6D`](@ref),
which uses one fixed tune triple per particle and shared entrance/exit
normalizations. Supply any nonempty subset of `nux`, `nuy`, `nuz` as a
NamedTuple of arrays, six-argument entrance-coordinate functions, finite real
constants, or [`TuneDistribution`](@ref) values. Joint named sources use
[`TuneFunction`](@ref) or `TuneDistribution` with `planes`; disjoint groups may
be composed in a tuple. Omitted planes retain `dmu/(2pi)`. Arrays contain one
entry per global particle (MPI ranks copy their own intervals). Tunes are
signed absolute advances in cycles per passage, initialized at actual first
passage and retained across continuation and coordinate reset.

This active form requires a `TrackingTask` with Float32 or Float64 precision
and an ordinary, unwrapped placement; explicit matrices, non-default
placement transforms, bare tracking and contextless optics analysis are
refused. CPU/CUDA/MPI keep owned local labels on their tracking backend.
`rng_id=0` allocates a named stream only for distribution sources; nonzero
`rng_id` without a distribution is refused. A raw stochastic `ElementSpec`
must provide a resolved nonzero stream. `clear_particle_tunes!` explicitly
rearms assignments with a fresh sampling epoch; `particle_tune_tables` returns
independent copies of assigned values and preparation provenance.
"""
Linear6DSpec(; matrix=nothing, beta1=nothing, dmu=nothing, beta2=nothing,
              alpha1=nothing, alpha2=nothing,
              zeta1=nothing, eta1=nothing, R1=nothing,
              zeta2=nothing, eta2=nothing, R2=nothing,
              particle_tunes=nothing, rng_id=0, numeric_type=nothing, kwargs...) =
    _floor_form(Linear6DSpec{something(numeric_type,
                                       _linear_map_eltype(matrix, beta1, dmu, beta2, alpha1, alpha2,
                                                          zeta1, eta1, R1, zeta2, eta2, R2))}(;
        matrix=matrix, beta1=beta1, dmu=dmu, beta2=beta2,
        alpha1=alpha1, alpha2=alpha2, zeta1=zeta1, eta1=eta1, R1=R1,
        zeta2=zeta2, eta2=eta2, R2=R2, particle_tunes=particle_tunes, rng_id=rng_id,
        kwargs...), numeric_type)
# The optics form's keys, in one place for the two refusals of "both forms at
# once" (the typed constructor and `Linear6D(spec)` on a raw spec).
const _LINEAR6D_OPTICS_KEYS = (:beta1, :dmu, :beta2, :alpha1, :alpha2,
                               :zeta1, :eta1, :R1, :zeta2, :eta2, :R2)

_linear6d_both_forms(given) = ArgumentError(
    "Linear6DSpec takes either matrix or the optics form (beta1, dmu, ...), not both: " *
    "matrix was given beside $(join(string.(given), ", ")), which a stored matrix would " *
    "silently override because the optics keywords are never read when a matrix is " *
    "stored (2026-10-18 audit, F-165); give one form")

function (::Type{Linear6DSpec{T}})(; matrix=nothing,
                                  beta1=nothing,
                                  dmu=nothing,
                                  beta2=nothing,
                                  alpha1=nothing,
                                  alpha2=nothing,
                                  zeta1=nothing,
                                  eta1=nothing,
                                  R1=nothing,
                                  zeta2=nothing,
                                  eta2=nothing,
                                  R2=nothing,
                                  particle_tunes=nothing,
                                  rng_id=0,
                                  tracking_method=Symplectic6DMap(),
                                  kwargs...) where {T}
    params = _stamp_numeric_type!(_spec_params(; tracking_method=tracking_method, kwargs...), T)
    sources = _normalize_particle_tunes(particle_tunes)
    sources === nothing || T in (Float32, Float64) || throw(ArgumentError(
        "particle_tunes supports Float32 or Float64; ordinary Linear6DSpec supports other Number types"))
    optics = (; beta1, dmu, beta2, alpha1, alpha2, zeta1, eta1, R1, zeta2, eta2, R2)
    @assert keys(optics) == _LINEAR6D_OPTICS_KEYS
    if matrix !== nothing
        sources === nothing || throw(ArgumentError(
            "particle_tunes requires the Linear6DSpec optics form, not an explicit matrix"))
        given = [k for (k, v) in pairs(optics) if v !== nothing]
        isempty(given) || throw(_linear6d_both_forms(given))
        typed_matrix = _matrix66_tuple(matrix, T)
        _validate_linear6d_symplectic(typed_matrix; source="Linear6DSpec matrix")
        params[:matrix] = typed_matrix
    else
        beta1 === nothing && throw(ArgumentError("Linear6DSpec requires either matrix or beta1"))
        dmu === nothing && throw(ArgumentError("Linear6DSpec requires either matrix or dmu"))
        # Each exit parameter defaults to its entrance partner, the entrance
        # ones to zero; `nothing` is the "not given" sentinel so that the
        # matrix branch above can tell a given keyword from a default.
        z3 = (zero(T), zero(T), zero(T))
        z4 = (zero(T), zero(T), zero(T), zero(T))
        beta2 = something(beta2, beta1)
        alpha1 = something(alpha1, z3)
        alpha2 = something(alpha2, alpha1)
        zeta1 = something(zeta1, z4)
        eta1 = something(eta1, z4)
        R1 = something(R1, z4)
        zeta2 = something(zeta2, zeta1)
        eta2 = something(eta2, eta1)
        R2 = something(R2, R1)
        params[:beta1] = _linear6d_tuple(beta1, 3, T)
        params[:beta2] = _linear6d_tuple(beta2, 3, T)
        params[:alpha1] = _linear6d_tuple(alpha1, 3, T)
        params[:alpha2] = _linear6d_tuple(alpha2, 3, T)
        params[:dmu] = _linear6d_tuple(dmu, 3, T)
        params[:zeta1] = _linear6d_tuple(zeta1, 4, T)
        params[:eta1] = _linear6d_tuple(eta1, 4, T)
        params[:R1] = _linear6d_tuple(R1, 4, T)
        params[:zeta2] = _linear6d_tuple(zeta2, 4, T)
        params[:eta2] = _linear6d_tuple(eta2, 4, T)
        params[:R2] = _linear6d_tuple(R2, 4, T)
    end
    resolved_rng_id = _particle_tune_rng_id(sources, rng_id; claim=true)
    if sources !== nothing
        params[:particle_tunes] = sources
        params[:rng_id] = resolved_rng_id
    end
    return ElementSpec{:linear6d}(params)
end

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    Linear6D{M,T}

Compiled runtime (`compile_runtime`) for `ElementSpec{:linear6d}`, built by
`Linear6DSpec`. Applies a constant linear map to `(x, px, y, py, z, pz)`: the
6x6 matrix, stored as a flat 36-tuple for GPU-compatible tracking, is validated
symplectic at construction. The runtime layer is an implementation detail
(AGENTS.md) and may change.
"""
struct Linear6D{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    matrix::NTuple{36,T}
    function Linear6D(method::M, matrix::NTuple{36,T}) where {
            M<:AbstractTrackingMethod,T<:Number}
        _validate_linear6d_symplectic(matrix; source="Linear6D runtime matrix")
        return new{M,T}(method, matrix)
    end
end

Base.Matrix(elem::Linear6D{M,T}) where {M,T} =
    [elem.matrix[(i - 1) * 6 + j] for i in 1:6, j in 1:6]

function Linear6D(spec::ElementSpec{:linear6d},
                  method::AbstractTrackingMethod=tracking_method(spec))
    getparam(spec, :particle_tunes, nothing) === nothing ||
        return ParticleLinear6D(spec, method)
    _particle_tune_rng_id(nothing, getparam(spec, :rng_id, 0))
    # A raw spec carrying both forms is refused here as the constructor refuses
    # them: the matrix would win and the optics keys would never be read.
    stored_optics = [k for k in _LINEAR6D_OPTICS_KEYS if hasparam(spec, k)]
    if hasparam(spec, :matrix)
        isempty(stored_optics) || throw(_linear6d_both_forms(stored_optics))
        matrix = param(spec, :matrix)
    else
        matrix = _linear6d_matrix_from_optics(spec)
    end
    # `numeric_type(spec)`, the one rule of every kind: the stored type of a
    # `Linear6DSpec{T}`, else the Float64-floor promotion of the stored
    # parameters, so an integer matrix still becomes Float64 and a dual number
    # or a truncated power series passes through instead of being refused.
    T = numeric_type(spec)
    T <: Number || throw(ArgumentError(
        "Linear6D matrix entries must promote to a Number type; got $(T)"))
    return Linear6D(method, _matrix66_tuple(matrix, T))
end

@inline function track_particle(::Symplectic6DMap, elem::Linear6D, x, px, y, py, z, pz)
    m = elem.matrix
    x1 = m[1]  * x + m[2]  * px + m[3]  * y + m[4]  * py + m[5]  * z + m[6]  * pz
    px1 = m[7]  * x + m[8]  * px + m[9]  * y + m[10] * py + m[11] * z + m[12] * pz
    y1 = m[13] * x + m[14] * px + m[15] * y + m[16] * py + m[17] * z + m[18] * pz
    py1 = m[19] * x + m[20] * px + m[21] * y + m[22] * py + m[23] * z + m[24] * pz
    z1 = m[25] * x + m[26] * px + m[27] * y + m[28] * py + m[29] * z + m[30] * pz
    pz1 = m[31] * x + m[32] * px + m[33] * y + m[34] * py + m[35] * z + m[36] * pz
    return x1, px1, y1, py1, z1, pz1
end

@inline (elem::Linear6D)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

# Cross-backend rounding class (`CrossBackendRounding`, src/track/Track.jl): a
# row that is its own coordinate's unit row, `1 x + 0 px + ...`, returns the
# coordinate as it came under any fusion (untouched); a dense row
# `m1 x + m2 px + ... + m6 pz` is fused term by term on the device (54% of 1e5
# random six-term rows part from the host's).
function _cross_backend_rounding(op::Linear6D)
    unit_row(i) = all(j -> op.matrix[(i - 1) * 6 + j] == (i == j ? 1 : 0), 1:6)
    passed = Tuple(c for (i, c) in enumerate(_COORDINATE_NAMES) if unit_row(i))
    fused = Tuple(c for (i, c) in enumerate(_COORDINATE_NAMES) if !unit_row(i))
    isempty(fused) && return _rounding_class(untouched=_COORDINATE_NAMES,
        why="the identity matrix: every row is its coordinate's unit row and returns it as it came")
    return _rounding_class(untouched=passed, ulp=fused, ulp_bound=8,
        why="a dense row `m1 x + m2 px + ... + m6 pz` is fused term by term on the device and rounded per term on the host (54% of 1e5 random rows part; 3 ulps of scale over 3 turns on the backend script's instance, 1.5 on a z-pz coupling); a unit row returns its coordinate as it came")
end

function _matrix66_tuple(matrix, ::Type{T}) where {T}
    if matrix isa AbstractMatrix
        size(matrix) == (6, 6) || throw(ArgumentError("matrix must be 6x6"))
        return ntuple(k -> begin
            i = (k - 1) ÷ 6 + 1
            j = (k - 1) % 6 + 1
            T(matrix[i, j])
        end, 36)
    end
    length(matrix) == 36 || throw(ArgumentError("matrix must be a 6x6 matrix or a length-36 row-major collection"))
    return ntuple(i -> T(matrix[i]), 36)
end

function _linear6d_tuple(values, n::Int, ::Type{T}) where {T}
    length(values) == n || throw(ArgumentError("expected $n values, got $(length(values))"))
    return ntuple(i -> T(values[i]), n)
end

_identity66(::Type{T}) where {T} =
    ntuple(k -> ((k - 1) ÷ 6 == (k - 1) % 6 ? one(T) : zero(T)), 36)

@inline _mget(m, i, j) = m[(i - 1) * 6 + j]

function _linear6d_symplectic_error(matrix::NTuple{36,T}) where {T<:Number}
    # Thresholds and accumulators live in `real(T)`, not `T` (2026-08-05_b
    # audit, U9-3). Everything that should be real already is -- `abs(value -
    # target)` and `abs(positive) + abs(negative)` return reals even for
    # Complex -- so only the ORDERED quantities were wrongly typed, and
    # `typemax`, `max`, `>` and `<=` are all undefined for Complex. A
    # `Linear6D` with complex entries therefore died with
    # `MethodError: isless(::ComplexF64, ::Float64)`, in the one function whose
    # widening to `T<:Number` exists to admit exactly that type -- which is
    # complex-step differentiation, the recurring class AGENTS.md names.
    R = real(T)
    all(isfinite, matrix) ||
        return (residual=typemax(R), tolerance=zero(R), ratio=typemax(R))
    max_residual = zero(R)
    max_tolerance = zero(R)
    max_ratio = zero(R)
    # Each entry of M'JM contains three signed 2x2 determinants. The row scale
    # is a componentwise forward-error bound, unlike ||M||^2, which becomes
    # unusably loose for large reciprocal canonical scalings.
    for i in 1:6
        row_residual = zero(R)
        row_scale = zero(R)
        for j in 1:6
            value = zero(T)              # a residual: stays in T
            product_scale = zero(R)      # a magnitude: real, or `max` has no order
            for coordinate in (1, 3, 5)
                positive = _mget(matrix, coordinate, i) *
                           _mget(matrix, coordinate + 1, j)
                negative = _mget(matrix, coordinate + 1, i) *
                           _mget(matrix, coordinate, j)
                isfinite(positive) && isfinite(negative) ||
                    return (residual=typemax(R), tolerance=zero(R),
                            ratio=typemax(R))
                value = (value + positive) - negative
                product_scale += abs(positive) + abs(negative)
            end
            target = isodd(i) && j == i + 1 ? one(T) :
                     iseven(i) && j == i - 1 ? -one(T) : zero(T)
            row_residual += R(abs(value - target))
            row_scale += R(max(abs(target), product_scale))
        end
        # Six products and additions form each entry. A factor of 64 leaves a
        # conservative margin over the first-order rounding bound while still
        # rejecting Float64 relative defects above roughly 1e-14.
        row_tolerance = R(64) * eps(R) * max(one(R), row_scale)
        isfinite(row_residual) && isfinite(row_tolerance) ||
            return (residual=typemax(R), tolerance=zero(R), ratio=typemax(R))
        ratio = row_tolerance > zero(R) ?
            row_residual / row_tolerance :
            (iszero(row_residual) ? zero(R) : typemax(R))
        if ratio > max_ratio
            max_ratio = ratio
            max_residual = row_residual
            max_tolerance = row_tolerance
        end
    end
    return (residual=max_residual, tolerance=max_tolerance, ratio=max_ratio)
end

function _validate_linear6d_symplectic(
        matrix::NTuple{36,T}; source="Linear6D matrix") where {T<:Number}
    error = _linear6d_symplectic_error(matrix)
    error.ratio <= one(real(T)) && return matrix
    throw(ArgumentError(
        "$(source) must be finite and canonical symplectic in " *
        "(x, px, y, py, z, pz) order: worst row residual=$(error.residual), " *
        "floating-point tolerance=$(error.tolerance), ratio=$(error.ratio)."))
end

function _mmul66(A::NTuple{36,T}, B::NTuple{36,T}) where {T}
    return ntuple(36) do k
        i = (k - 1) ÷ 6 + 1
        j = (k - 1) % 6 + 1
        sum(_mget(A, i, l) * _mget(B, l, j) for l in 1:6)
    end
end

function _minv66(A::NTuple{36,T}) where {T}
    M = Matrix{T}(undef, 6, 6)
    for i in 1:6, j in 1:6
        M[i, j] = _mget(A, i, j)
    end
    invM = inv(M)
    return _matrix66_tuple(invM, T)
end

function _linear6d_matrix_from_optics(spec::ElementSpec{:linear6d})
    # The raw form's reads mirror the friendly constructor: beta1 and dmu are
    # what the optics form needs (refused by name together when absent), the
    # entrance parameters take the schema's declared defaults
    # (`_declared_param`), and each exit parameter defaults to its entrance
    # partner, as the schema states. A raw spec died here with a KeyError on
    # `beta2` until the 2026-10-18 audit (F-165, the F-93 class).
    (hasparam(spec, :beta1) && hasparam(spec, :dmu)) || throw(ArgumentError(
        "ElementSpec{:linear6d} needs either matrix or both beta1 and dmu (the optics " *
        "form); it has $(join(string.(filter(k -> hasparam(spec, k), (:beta1, :dmu))), ", ")) " *
        "of the two (see construction_help(Linear6DSpec))"))
    partner(key, fallback) = hasparam(spec, key) ? param(spec, key) : fallback
    beta1 = param(spec, :beta1)
    dmu = param(spec, :dmu)
    # The entrance parameters default to zeros IN THE OPTICS FORM, the exit
    # ones to their partners; neither is a schema default, because the kind's
    # other form (a stored matrix) has no such parameter at all and the
    # validator passes every declared default beside the example, which the
    # two-forms refusal would reject. The schema states both rules in words.
    alpha1 = partner(:alpha1, (0, 0, 0))
    zeta1 = partner(:zeta1, (0, 0, 0, 0))
    eta1 = partner(:eta1, (0, 0, 0, 0))
    R1 = partner(:R1, (0, 0, 0, 0))
    beta2 = partner(:beta2, beta1)
    alpha2 = partner(:alpha2, alpha1)
    zeta2 = partner(:zeta2, zeta1)
    eta2 = partner(:eta2, eta1)
    R2 = partner(:R2, R1)
    # The promotion has to span EVERY optics parameter that reaches the matrix,
    # not just the Twiss block: it used to cover beta/alpha/dmu only, so a Dual
    # or Complex zeta/eta/R died at the `_linear6d_tuple(..., T)` conversions
    # below with `Float64(::Dual)`. Unreachable through the friendly
    # constructor, which pre-converts, but reachable through a raw `ElementSpec`
    # -- which is the documented flexible form (2026-08-05_b audit, U9-6).
    # `numeric_type(spec)` is the floor (Float64 for an all-integer raw spec).
    T = promote_type(numeric_type(spec),
                     map(typeof, (beta1..., beta2..., alpha1..., alpha2..., dmu...,
                                  zeta1..., eta1..., R1..., zeta2..., eta2..., R2...))...)
    B = _zero66(T)
    for i in 1:3
        s = sin(T(dmu[i]))
        c = cos(T(dmu[i]))
        row = 2 * i - 1
        B = _mset(B, row, row, sqrt(T(beta2[i]) / T(beta1[i])) * (c + T(alpha1[i]) * s))
        B = _mset(B, row, row + 1, sqrt(T(beta2[i]) * T(beta1[i])) * s)
        B = _mset(B, row + 1, row,
                  (-(one(T) + T(alpha1[i]) * T(alpha2[i])) * s +
                   (T(alpha1[i]) - T(alpha2[i])) * c) /
                  sqrt(T(beta1[i]) * T(beta2[i])))
        B = _mset(B, row + 1, row + 1,
                  sqrt(T(beta1[i]) / T(beta2[i])) * (c - T(alpha2[i]) * s))
    end

    zeta1 = _linear6d_tuple(zeta1, 4, T)
    eta1 = _linear6d_tuple(eta1, 4, T)
    R1 = _linear6d_tuple(R1, 4, T)
    zeta2 = _linear6d_tuple(zeta2, 4, T)
    eta2 = _linear6d_tuple(eta2, 4, T)
    R2 = _linear6d_tuple(R2, 4, T)

    return _mmul66(
        _mmul66(_mmul66(_mmul66(_mmul66(_mzeta66(zeta2), _meta66(eta2)), _mR66(R2)), B),
                _minv66(_mR66(R1))),
        _mmul66(_minv66(_meta66(eta1)), _minv66(_mzeta66(zeta1))),
    )
end

_zero66(::Type{T}) where {T} = ntuple(_ -> zero(T), 36)
_mset(m::NTuple{36,T}, i, j, value) where {T} =
    ntuple(k -> k == (i - 1) * 6 + j ? T(value) : m[k], 36)

function _mzeta66(zeta::NTuple{4,T}) where {T}
    M = _identity66(T)
    for i in 1:4
        M = _mset(M, i, 5, zeta[i])
    end
    M = _mset(M, 6, 1, zeta[2])
    M = _mset(M, 6, 2, -zeta[1])
    M = _mset(M, 6, 3, zeta[4])
    M = _mset(M, 6, 4, -zeta[3])
    return M
end

function _meta66(eta::NTuple{4,T}) where {T}
    M = _identity66(T)
    for i in 1:4
        M = _mset(M, i, 6, eta[i])
    end
    M = _mset(M, 5, 1, -eta[2])
    M = _mset(M, 5, 2, eta[1])
    M = _mset(M, 5, 3, -eta[4])
    M = _mset(M, 5, 4, eta[3])
    return M
end

function _mR66(C::NTuple{4,T}) where {T}
    M = _identity66(T)
    g = sqrt(one(T) - C[1] * C[4] + C[2] * C[3])
    for i in 1:4
        M = _mset(M, i, i, g)
    end
    M = _mset(M, 1, 3, C[1])
    M = _mset(M, 1, 4, C[2])
    M = _mset(M, 2, 3, C[3])
    M = _mset(M, 2, 4, C[4])
    M = _mset(M, 3, 1, -C[4])
    M = _mset(M, 3, 2, C[2])
    M = _mset(M, 4, 1, C[3])
    M = _mset(M, 4, 2, -C[1])
    return M
end

@element_spec begin
    kind = :linear6d
    spec_type = ElementSpec{:linear6d}
    friendly_constructor = Linear6DSpec
    runtime_type = Linear6D
    runtime_variants = Dict(Symplectic6DMap => (Linear6D, ParticleLinear6D))
    variant_examples = Dict(ParticleLinear6D => Linear6DSpec(
        beta1=(1.0, 1.0, 1.0), dmu=(0.2, 0.3, 0.4), particle_tunes=(nux=0.23,)))
    description = "Flexible canonical-symplectic six-dimensional linear map specification."
    keywords = [:coordinate_transform]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [TwissDispersionAnalysis]
    parameters = (
        matrix=ParamMeta(meaning="explicit canonical-symplectic 6x6 transfer matrix, or length-36 row-major collection"),
        beta1=ParamMeta(meaning="initial beta functions for optics construction"),
        beta2=ParamMeta(meaning="final beta functions for optics construction; defaults to beta1"),
        alpha1=ParamMeta(meaning="initial alpha functions for optics construction; defaults to (0, 0, 0) in the optics form (no schema default: the matrix form has no such parameter, and matrix beside any optics keyword is refused)"),
        alpha2=ParamMeta(meaning="final alpha functions for optics construction; defaults to alpha1 (the constructor and the raw form alike, so no literal default is declared)"),
        dmu=ParamMeta(meaning="phase advances in radians"),
        particle_tunes=ParamMeta(default=nothing,
            meaning="optional fixed per-particle absolute tunes in cycles per passage, consumed by ParticleLinear6D at first TrackingTask passage; named nux/nuy/nuz sources accept arrays, entrance-coordinate functions, constants or TuneDistribution, with omitted planes frozen at dmu/(2pi); nothing selects ordinary Linear6D, explicit matrices and wrapped placements are refused when active"),
        rng_id=ParamMeta(default=0,
            meaning="counter RNG stream consumed by particle-tune distributions at first passage and explicit rearm; zero allocates/claims a fresh stream at friendly construction, a raw stochastic spec requires a resolved nonzero ID, and nonzero without distributions is refused as inactive"),
        zeta1=ParamMeta(meaning="initial crab dispersion coefficients; defaults to zeros in the optics form (see alpha1). " * _CANONICAL_DISPERSION_NOTE),
        eta1=ParamMeta(meaning="initial momentum dispersion coefficients; defaults to zeros in the optics form (see alpha1). " * _CANONICAL_DISPERSION_NOTE),
        R1=ParamMeta(meaning="initial x-y coupling coefficients; defaults to zeros in the optics form (see alpha1)"),
        zeta2=ParamMeta(meaning="final crab dispersion coefficients; defaults to zeta1. " * _CANONICAL_DISPERSION_NOTE),
        eta2=ParamMeta(meaning="final momentum dispersion coefficients; defaults to eta1. " * _CANONICAL_DISPERSION_NOTE),
        R2=ParamMeta(meaning="final x-y coupling coefficients; defaults to R1"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = Linear6DSpec(matrix=Matrix{Float64}(I, 6, 6))
    construction_help = "Friendly constructor: Linear6DSpec{T}(; matrix, tracking_method=Symplectic6DMap(), kwargs...), where matrix must be canonical symplectic, or Linear6DSpec{T}(; beta1, dmu, beta2=beta1, alpha1=(0,0,0), alpha2=alpha1, zeta1=(0,0,0,0), eta1=(0,0,0,0), R1=(0,0,0,0), zeta2=zeta1, eta2=eta1, R2=R1, tracking_method=Symplectic6DMap(), kwargs...). The two forms are exclusive: matrix beside any optics keyword is refused by name, at construction and when a raw spec carrying both compiles. The optics form additionally accepts particle_tunes=nothing and rng_id=0: any named subset of nux/nuy/nuz can use global per-particle arrays, six-argument entrance-coordinate functions, finite real constants, or TuneDistribution; joint named sources use TuneFunction/TuneDistribution with planes, and disjoint groups compose in a tuple. Omitted tunes remain dmu/(2pi). The active ParticleLinear6D variant supports Float32/Float64 TrackingTask execution on CPU/CUDA/MPI, persists across continuation and coordinate reset, and refuses explicit matrices, non-default placement transforms, bare tracking and contextless Matrix/Twiss queries. rng_id is consumed only by distributions; zero assigns a fresh stream at friendly construction, raw stochastic specs require a resolved nonzero stream, and nonzero without distributions is refused. clear_particle_tunes! explicitly rearms with a fresh epoch; particle_tune_tables returns independent local copies and provenance. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel. numeric_type (every kind): the number type the element compiles in, Float64 unless built by the typed form Linear6DSpec{T}(; ...) or given numeric_type=T by keyword (Float32 for a Float32 line; the untyped form promotes its inputs over a Float64 floor and never narrows); a beam whose element type differs from the element's is refused by name when a task compiles the line."
end
