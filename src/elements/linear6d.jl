export Linear6DSpec, Linear6D

abstract type Linear6DSpec{T} end

"""
    Linear6DSpec{T=Float64}(; matrix, tracking_method=Symplectic6DMap(), kwargs...)
    Linear6DSpec{T=Float64}(; beta1, dmu, beta2=beta1, alpha1=(0,0,0),
                             alpha2=alpha1, zeta1=(0,0,0,0),
                             eta1=(0,0,0,0), R1=(0,0,0,0),
                             zeta2=zeta1, eta2=eta1, R2=R1,
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
"""
Linear6DSpec(; matrix=nothing, beta1=nothing, dmu=nothing, beta2=beta1,
              alpha1=(0, 0, 0), alpha2=alpha1,
              zeta1=(0, 0, 0, 0), eta1=(0, 0, 0, 0), R1=(0, 0, 0, 0),
              zeta2=zeta1, eta2=eta1, R2=R1, kwargs...) =
    Linear6DSpec{_linear_map_eltype(matrix, beta1, dmu, beta2, alpha1, alpha2,
                                    zeta1, eta1, R1, zeta2, eta2, R2)}(;
        matrix=matrix, beta1=beta1, dmu=dmu, beta2=beta2,
        alpha1=alpha1, alpha2=alpha2, zeta1=zeta1, eta1=eta1, R1=R1,
        zeta2=zeta2, eta2=eta2, R2=R2, kwargs...)
function (::Type{Linear6DSpec{T}})(; matrix=nothing,
                                  beta1=nothing,
                                  dmu=nothing,
                                  beta2=beta1,
                                  alpha1=(zero(T), zero(T), zero(T)),
                                  alpha2=alpha1,
                                  zeta1=(zero(T), zero(T), zero(T), zero(T)),
                                  eta1=(zero(T), zero(T), zero(T), zero(T)),
                                  R1=(zero(T), zero(T), zero(T), zero(T)),
                                  zeta2=zeta1,
                                  eta2=eta1,
                                  R2=R1,
                                  tracking_method=Symplectic6DMap(),
                                  kwargs...) where {T}
    params = _spec_params(; tracking_method=tracking_method, kwargs...)
    if matrix !== nothing
        typed_matrix = _matrix66_tuple(matrix, T)
        _validate_linear6d_symplectic(typed_matrix; source="Linear6DSpec matrix")
        params[:matrix] = typed_matrix
    else
        beta1 === nothing && throw(ArgumentError("Linear6DSpec requires either matrix or beta1"))
        dmu === nothing && throw(ArgumentError("Linear6DSpec requires either matrix or dmu"))
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
    matrix = hasparam(spec, :matrix) ? param(spec, :matrix) : _linear6d_matrix_from_optics(spec)
    # `float(promote_type(...))` rather than a bare promote plus a rejection: an
    # integer matrix still becomes Float64, and a dual number or a truncated
    # power series passes through instead of being refused.
    T = float(promote_type(map(typeof, matrix)...))
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
    beta1 = param(spec, :beta1)
    beta2 = param(spec, :beta2)
    alpha1 = param(spec, :alpha1)
    alpha2 = param(spec, :alpha2)
    dmu = param(spec, :dmu)
    # The promotion has to span EVERY optics parameter that reaches the matrix,
    # not just the Twiss block: it used to cover beta/alpha/dmu only, so a Dual
    # or Complex zeta/eta/R died at the `_linear6d_tuple(..., T)` conversions
    # below with `Float64(::Dual)`. Unreachable through the friendly
    # constructor, which pre-converts, but reachable through a raw `ElementSpec`
    # -- which is the documented flexible form (2026-08-05_b audit, U9-6).
    T = promote_type(map(typeof, (beta1..., beta2..., alpha1..., alpha2..., dmu...,
                                  param(spec, :zeta1)..., param(spec, :eta1)...,
                                  param(spec, :R1)..., param(spec, :zeta2)...,
                                  param(spec, :eta2)..., param(spec, :R2)...))...)
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

    zeta1 = _linear6d_tuple(param(spec, :zeta1), 4, T)
    eta1 = _linear6d_tuple(param(spec, :eta1), 4, T)
    R1 = _linear6d_tuple(param(spec, :R1), 4, T)
    zeta2 = _linear6d_tuple(param(spec, :zeta2), 4, T)
    eta2 = _linear6d_tuple(param(spec, :eta2), 4, T)
    R2 = _linear6d_tuple(param(spec, :R2), 4, T)

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
    description = "Flexible canonical-symplectic six-dimensional linear map specification."
    keywords = [:coordinate_transform]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        matrix=ParamMeta(meaning="explicit canonical-symplectic 6x6 transfer matrix, or length-36 row-major collection"),
        beta1=ParamMeta(meaning="initial beta functions for optics construction"),
        beta2=ParamMeta(meaning="final beta functions for optics construction; defaults to beta1"),
        alpha1=ParamMeta(default=(0, 0, 0), meaning="initial alpha functions"),
        alpha2=ParamMeta(default=(0, 0, 0), meaning="final alpha functions; defaults to alpha1"),
        dmu=ParamMeta(meaning="phase advances in radians"),
        zeta1=ParamMeta(default=(0, 0, 0, 0), meaning="initial crab dispersion coefficients"),
        eta1=ParamMeta(default=(0, 0, 0, 0), meaning="initial momentum dispersion coefficients"),
        R1=ParamMeta(default=(0, 0, 0, 0), meaning="initial x-y coupling coefficients"),
        zeta2=ParamMeta(default=(0, 0, 0, 0), meaning="final crab dispersion coefficients"),
        eta2=ParamMeta(default=(0, 0, 0, 0), meaning="final momentum dispersion coefficients"),
        R2=ParamMeta(default=(0, 0, 0, 0), meaning="final x-y coupling coefficients"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = Linear6DSpec{Float64}(matrix=Matrix{Float64}(I, 6, 6))
    construction_help = "Friendly constructor: Linear6DSpec{T}(; matrix, tracking_method=Symplectic6DMap(), kwargs...), where matrix must be canonical symplectic, or Linear6DSpec{T}(; beta1, dmu, beta2=beta1, alpha1=(0,0,0), alpha2=alpha1, zeta1=(0,0,0,0), eta1=(0,0,0,0), R1=(0,0,0,0), zeta2=zeta1, eta2=eta1, R2=R1, tracking_method=Symplectic6DMap(), kwargs...). Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
end
