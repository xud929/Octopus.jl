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

# Element type for a friendly linear-map constructor called WITHOUT its `{T}`.
#
# These four constructors used to hard-code `{Float64}` and then convert with
# `T(value)`, so a `Dual` or `Complex` parameter died with `Float64(::Dual)`
# unless the caller spelled `Spec{T}` -- while every lattice magnet promotes
# automatically through `numeric_type(spec)`. That inconsistency is what made
# the `T<:Number` widening only half delivered (2026-08-05_b audit, U9-6).
#
# `Float64` is a FLOOR, not just a fallback: integers, rationals and Float32
# still land on Float64 exactly as before, so this only ever widens. Narrowing
# (a genuinely Float32 spec) stays behind the explicit `Spec{Float32}` form,
# because the symplecticity tolerances downstream are calibrated per precision
# and silently narrowing on an argument's type would be a surprise.
#
# Only values of the named parameters are considered. Extra kwargs are stored
# as descriptive metadata and may be numbers with no bearing on the arithmetic
# -- promoting over `some_count=2` would be a real bug.
function _linear_map_eltype(values...)
    T = Float64
    for v in values
        if v isa Number
            T = promote_type(T, typeof(v))
        elseif v isa Union{Tuple,AbstractArray}
            for u in v
                u isa Number && (T = promote_type(T, typeof(u)))
            end
        end
    end
    return T
end

"""
    CrabDispersionSpec{T=Float64}(; zeta1=0, zeta2=0, zeta3=0, zeta4=0,
                                  tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:crab_dispersion}`. The `zeta` fields define a
six-dimensional symplectic crab-dispersion coordinate transform. Extra keyword
arguments are stored as descriptive spec metadata.

Without the explicit `{T}`, the element type is inferred by promoting the
named parameters over a `Float64` floor, so a `Dual` or `Complex` parameter
differentiates without the caller having to spell the type — matching how
every lattice magnet promotes through `numeric_type(spec)` (2026-08-05_b
audit, U9-6). Integers, rationals and `Float32` still land on `Float64`;
narrowing stays behind the explicit `{T}` form. Extra keyword arguments are
descriptive metadata and take no part in the promotion.
"""
CrabDispersionSpec(; zeta1=0, zeta2=0, zeta3=0, zeta4=0, kwargs...) =
    CrabDispersionSpec{_linear_map_eltype(zeta1, zeta2, zeta3, zeta4)}(;
        zeta1=zeta1, zeta2=zeta2, zeta3=zeta3, zeta4=zeta4, kwargs...)
function (::Type{CrabDispersionSpec{T}})(; zeta1=zero(T), zeta2=zero(T),
                                        zeta3=zero(T), zeta4=zero(T),
                                        tracking_method=Symplectic6DMap(),
                                        kwargs...) where {T}
    return ElementSpec{:crab_dispersion}(
        _spec_params(; zeta1=T(zeta1), zeta2=T(zeta2), zeta3=T(zeta3), zeta4=T(zeta4),
                     tracking_method=tracking_method, kwargs...),
    )
end

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    CrabDispersion{M,FloatT}

Compiled runtime (`compile_runtime`) for `ElementSpec{:crab_dispersion}`, built
by `CrabDispersionSpec`. Zero-length symplectic map coupling the transverse
plane to `z`: each transverse coordinate gains its `zeta` coefficient times
`z`, and `pz` absorbs the conjugate combination. The runtime layer is an
implementation detail (AGENTS.md) and may change.
"""
struct CrabDispersion{M<:AbstractTrackingMethod,FloatT <: Number} <: AbstractTrackOp
    method::M
    zeta1::FloatT
    zeta2::FloatT
    zeta3::FloatT
    zeta4::FloatT
end

CrabDispersion{T}(zeta1, zeta2, zeta3, zeta4) where {T<:Number} =
    CrabDispersion(Symplectic6DMap(), T(zeta1), T(zeta2), T(zeta3), T(zeta4))

@element_spec begin
    kind = :crab_dispersion
    spec_type = ElementSpec{:crab_dispersion}
    friendly_constructor = CrabDispersionSpec
    runtime_type = CrabDispersion
    description = "Flexible crab-dispersion element specification."
    keywords = [:crab_dispersion]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        zeta1=ParamMeta(default=0, meaning="x-z crab dispersion coefficient"),
        zeta2=ParamMeta(default=0, meaning="px-z crab dispersion coefficient"),
        zeta3=ParamMeta(default=0, meaning="y-z crab dispersion coefficient"),
        zeta4=ParamMeta(default=0, meaning="py-z crab dispersion coefficient"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = CrabDispersionSpec{Float64}(zeta1=0.1)
    construction_help = "Friendly constructor: CrabDispersionSpec{T}(; zeta1, zeta2, zeta3, zeta4, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:crab_dispersion}(; zeta1=zeta1, zeta2=zeta2, zeta3=zeta3, zeta4=zeta4, tracking_method=tracking_method, kwargs...). Extra keyword arguments are stored as metadata. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
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

Without the explicit `{T}`, the element type is inferred by promoting the
named parameters over a `Float64` floor, so a `Dual` or `Complex` parameter
differentiates without the caller having to spell the type — matching how
every lattice magnet promotes through `numeric_type(spec)` (2026-08-05_b
audit, U9-6). Integers, rationals and `Float32` still land on `Float64`;
narrowing stays behind the explicit `{T}` form. Extra keyword arguments are
descriptive metadata and take no part in the promotion.
"""
MomentumDispersionSpec(; eta1=0, eta2=0, eta3=0, eta4=0, kwargs...) =
    MomentumDispersionSpec{_linear_map_eltype(eta1, eta2, eta3, eta4)}(;
        eta1=eta1, eta2=eta2, eta3=eta3, eta4=eta4, kwargs...)
function (::Type{MomentumDispersionSpec{T}})(; eta1=zero(T), eta2=zero(T),
                                            eta3=zero(T), eta4=zero(T),
                                            tracking_method=Symplectic6DMap(),
                                            kwargs...) where {T}
    return ElementSpec{:momentum_dispersion}(
        _spec_params(; eta1=T(eta1), eta2=T(eta2), eta3=T(eta3), eta4=T(eta4),
                     tracking_method=tracking_method, kwargs...),
    )
end

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    MomentumDispersion{M,FloatT}

Compiled runtime (`compile_runtime`) for `ElementSpec{:momentum_dispersion}`,
built by `MomentumDispersionSpec`. Zero-length symplectic map coupling the
transverse plane to `pz`: each transverse coordinate gains its `eta`
coefficient times `pz`, and `z` absorbs the conjugate combination. The runtime
layer is an implementation detail (AGENTS.md) and may change.
"""
struct MomentumDispersion{M<:AbstractTrackingMethod,FloatT <: Number} <: AbstractTrackOp
    method::M
    eta1::FloatT
    eta2::FloatT
    eta3::FloatT
    eta4::FloatT
end

MomentumDispersion{T}(eta1, eta2, eta3, eta4) where {T<:Number} =
    MomentumDispersion(Symplectic6DMap(), T(eta1), T(eta2), T(eta3), T(eta4))

@element_spec begin
    kind = :momentum_dispersion
    spec_type = ElementSpec{:momentum_dispersion}
    friendly_constructor = MomentumDispersionSpec
    runtime_type = MomentumDispersion
    description = "Flexible momentum-dispersion element specification."
    keywords = [:momentum_dispersion]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        eta1=ParamMeta(default=0, meaning="x-pz momentum dispersion coefficient"),
        eta2=ParamMeta(default=0, meaning="px-pz momentum dispersion coefficient"),
        eta3=ParamMeta(default=0, meaning="y-pz momentum dispersion coefficient"),
        eta4=ParamMeta(default=0, meaning="py-pz momentum dispersion coefficient"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = MomentumDispersionSpec{Float64}(eta1=0.2)
    construction_help = "Friendly constructor: MomentumDispersionSpec{T}(; eta1, eta2, eta3, eta4, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:momentum_dispersion}(; eta1=eta1, eta2=eta2, eta3=eta3, eta4=eta4, tracking_method=tracking_method, kwargs...). Extra keyword arguments are stored as metadata. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
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

"""Convention selector for the `XYCoupling` map: which of its two coupling branches `track_particle` applies, or none."""
XYCouplingMode

"""`XYCoupling` mode under which the map is the identity."""
XY_UNDEF

"""`XYCoupling` mode selecting the first coupling branch of the map (the default)."""
XY_MODEA

"""`XYCoupling` mode selecting the second coupling branch, with the roles of the `(x, px)` and `(y, py)` blocks swapped relative to `XY_MODEA`."""
XY_MODEB

"""
    XYCouplingSpec{T=Float64}(; r1=0, r2=0, r3=0, r4=0, mode=XY_MODEA,
                              tracking_method=Symplectic6DMap(), kwargs...)

Create an `ElementSpec{:xy_coupling}` for a transverse x-y coupling coordinate
transform. Extra keyword arguments are stored as descriptive spec metadata.

Without the explicit `{T}`, the element type is inferred by promoting the
named parameters over a `Float64` floor, so a `Dual` or `Complex` parameter
differentiates without the caller having to spell the type — matching how
every lattice magnet promotes through `numeric_type(spec)` (2026-08-05_b
audit, U9-6). Integers, rationals and `Float32` still land on `Float64`;
narrowing stays behind the explicit `{T}` form. Extra keyword arguments are
descriptive metadata and take no part in the promotion.
"""
XYCouplingSpec(; r1=0, r2=0, r3=0, r4=0, kwargs...) =
    XYCouplingSpec{_linear_map_eltype(r1, r2, r3, r4)}(;
        r1=r1, r2=r2, r3=r3, r4=r4, kwargs...)
function (::Type{XYCouplingSpec{T}})(; r1=zero(T), r2=zero(T), r3=zero(T),
                                    r4=zero(T), mode::XYCouplingMode=XY_MODEA,
                                    tracking_method=Symplectic6DMap(),
                                    kwargs...) where {T}
    return ElementSpec{:xy_coupling}(
        _spec_params(; r1=T(r1), r2=T(r2), r3=T(r3), r4=T(r4), mode=mode,
                     tracking_method=tracking_method, kwargs...),
    )
end

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    XYCoupling{M,FloatT}

Compiled runtime (`compile_runtime`) for `ElementSpec{:xy_coupling}`, built by
`XYCouplingSpec`. Zero-length linear map mixing `(x, px)` with `(y, py)`
through the coefficients `r1..r4`, normalized by
`1/sqrt(1 + r1*r4 - r2*r3)`; `mode` selects which of the two coupling branches
applies (`XY_UNDEF` makes it the identity), and `z`, `pz` are untouched. The
runtime layer is an implementation detail (AGENTS.md) and may change.
"""
struct XYCoupling{M<:AbstractTrackingMethod,FloatT <: Number} <: AbstractTrackOp
    method::M
    r1::FloatT
    r2::FloatT
    r3::FloatT
    r4::FloatT
    mode::XYCouplingMode

    function XYCoupling{M,FloatT}(method::M, r1::FloatT, r2::FloatT, r3::FloatT,
                                  r4::FloatT, mode::XYCouplingMode) where {M,FloatT}
        # Checked HERE, not in the kernel (2026-08-05_b audit, U9-8). The map
        # scales by `g = 1/sqrt(1 + r1*r4 - r2*r3)`, and a determinant at or
        # below zero made `sqrt` throw a bare DomainError from inside
        # `track_particle` -- naming neither the element nor which of the four
        # parameters was wrong, and from a kernel, where a throw is also a
        # device-IR problem. Construction is the only place that can say what
        # went wrong.
        #
        # `real` so the check works on the complex-step and Dual axes this type
        # is generic over; the determinant of a physical coupling block is real.
        det = 1 + r1 * r4 - r2 * r3
        if mode !== XY_UNDEF && isfinite(real(det)) && real(det) <= 0
            throw(ArgumentError(
                "XYCoupling is not invertible: 1 + r1*r4 - r2*r3 = $(real(det)) " *
                "must be positive, because the map scales by 1/sqrt of it. " *
                "Got r1=$(r1), r2=$(r2), r3=$(r3), r4=$(r4)."))
        end
        return new{M,FloatT}(method, r1, r2, r3, r4, mode)
    end
end

@element_spec begin
    kind = :xy_coupling
    spec_type = ElementSpec{:xy_coupling}
    friendly_constructor = XYCouplingSpec
    runtime_type = XYCoupling
    description = "Flexible transverse x-y coupling element specification."
    keywords = [:xy_coupling]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        r1=ParamMeta(default=0, meaning="coupling coefficient r1"),
        r2=ParamMeta(default=0, meaning="coupling coefficient r2"),
        r3=ParamMeta(default=0, meaning="coupling coefficient r3"),
        r4=ParamMeta(default=0, meaning="coupling coefficient r4"),
        mode=ParamMeta(default=XY_MODEA, alternatives=(XY_MODEA, XY_MODEB), meaning="coupling convention"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = XYCouplingSpec{Float64}(r1=0.01)
    construction_help = "Friendly constructor: XYCouplingSpec{T}(; r1, r2, r3, r4, mode=XY_MODEA, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:xy_coupling}(; r1=r1, r2=r2, r3=r3, r4=r4, mode=mode, tracking_method=tracking_method, kwargs...). Extra keyword arguments are stored as metadata. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
end

# Restored explicitly: defining an inner constructor above removes Julia's
# automatic outer one, and the spec path calls this six-argument form.
XYCoupling(method::M, r1::Number, r2::Number, r3::Number, r4::Number,
           mode::XYCouplingMode) where {M<:AbstractTrackingMethod} =
    XYCoupling{M,promote_type(typeof(r1), typeof(r2), typeof(r3), typeof(r4))}(
        method, promote(r1, r2, r3, r4)..., mode)

# `::Number`, not a strict same-type `::T`: the natural `XYCoupling(0.01, 0, 0, 0)`
# was a MethodError, because writing an exact zero as `0` rather than `0.0` is
# what anyone does. Same strict-signature class as the `_curv_sin` /
# `_sol_log_over_h` fixes, one layer up; the spec path already promoted
# correctly, so only these two convenience forms were affected (2026-08-05_b
# audit, U9-7). Promotion is delegated to the six-argument method above so
# there is one promotion rule, not three.
XYCoupling(r1::Number, r2::Number, r3::Number, r4::Number) =
    XYCoupling(Symplectic6DMap(), r1, r2, r3, r4, XY_MODEA)
XYCoupling(r1::Number, r2::Number, r3::Number, r4::Number, mode::XYCouplingMode) =
    XYCoupling(Symplectic6DMap(), r1, r2, r3, r4, mode)
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
