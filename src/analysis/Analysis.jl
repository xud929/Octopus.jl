export PlaceholderAnalysis, AbstractAnalysisResult,
       DETERMINATION_STATUSES, DETERMINATION_REASONS, AMBIGUITY_KINDS,
       Determined, AmbiguitySet, UndeterminedQuantityError,
       is_determined, is_ambiguous, determined_value, ambiguity_set,
       dispersion_interval

"""Placeholder analysis used when no concrete analysis is declared yet."""
struct PlaceholderAnalysis <: AbstractAnalysis end

description(::Type{PlaceholderAnalysis}) = "Placeholder for element analyses not yet implemented."

# The availability vocabulary below is stage 1 of the Twiss and dispersion
# analysis campaign (docs/design/twiss_dispersion_analysis.md, "Types and
# availability"; staging item 1). It defines HOW a quantity the physics may
# leave undetermined is represented and read. No analysis exists yet: there is
# no `analyze` function and no concrete analysis type besides the placeholder;
# stage 4 adds those. `Determined` and `AmbiguitySet` are plain types, not
# registry roots, so the registry snapshot is unchanged by this file.

"""
Root of analysis RESULT types. A result is runtime representation: it carries
what an analysis computed, including every diagnostic the theory asks for, and
may change shape between releases. The analysis object itself (a concrete
`AbstractAnalysis` carrying options) and its option schema are the stable
surface (design note `docs/design/twiss_dispersion_analysis.md`, "Types and
availability"). No concrete subtype exists yet; the first lands with the Twiss
and dispersion analysis.
"""
abstract type AbstractAnalysisResult end

"""
    DETERMINATION_STATUSES

Every status a [`Determined`](@ref) quantity may carry. Pinned against the
source in the suite the way `CONFIGURATION_STATUSES` is.

  * `:unique` -- the physics determines one value; [`determined_value`](@ref)
    returns it.
  * `:ambiguous_set` -- the physics determines a SET of values, not one
    (theory Section 13.6); [`ambiguity_set`](@ref) returns the
    [`AmbiguitySet`](@ref) and [`determined_value`](@ref) throws.
  * `:unavailable` -- the quantity is not defined for this input; the reason
    is one of [`DETERMINATION_REASONS`](@ref) and every accessor throws.
"""
const DETERMINATION_STATUSES = (:unique, :ambiguous_set, :unavailable)

"""
    DETERMINATION_REASONS

Every reason a [`Determined`](@ref) quantity may carry. `:none` is the reason
of a unique value; each other member names a distinct physical or numerical
situation the theory note distinguishes (`docs/theory/twiss_dispersion.md`,
Sections 8, 11.2 and 13; design note, "Types and availability"). Pinned
against the source in the suite; the suite also checks that this docstring
lists exactly the declared members.

  * `:none` -- a unique value.
  * `:cluster_unresolved` -- the mode lies in a degenerate or unresolved group,
    so an individual-mode quantity is a convention, not a result.
  * `:indefinite_cluster` -- the group's Krein (Gram) form is indefinite.
  * `:unresolved_defective` -- the group could not be classified as definite
    or indefinite within the map's accuracy; possibly defective, never
    asserted so.
  * `:singular_longitudinal_projection` -- `h = det U_ls` vanishes; the
    longitudinal graph does not exist.
  * `:unstable_spectrum` -- the cluster's Schur block leaves the unit circle.
  * `:unit_eigenvalue` -- an eigenvalue at plus or minus one outside the
    coasting structure.
  * `:coasting_structure` -- the coasting (D23) branch was taken; there is no
    synchrotron mode.
  * `:form_inadmissible` -- the requested Edwards-Teng form has a non-positive
    area weight.
  * `:zero_projection` -- a relative phase whose position projection vanishes.
  * `:singular_coefficient` -- a linear solve's coefficient matrix is singular
    or too ill conditioned to trust.
  * `:not_invariant` -- a candidate graph or eigenpair failed the normalized
    (I1) invariance residual.
  * `:not_derived_for_cluster` -- a per-mode derived quantity the analysis
    does not form for a group.
  * `:not_requested` -- an optional product the caller did not ask for.
  * `:route_not_selected` -- a dispersion route absent from the selected list.
  * `:graph_isotropic` -- a finite graph whose canonical area
    `1 + D1' S4 D2` vanishes, so no canonical normalization exists; distinct
    from a singular projection.
"""
const DETERMINATION_REASONS = (:none, :cluster_unresolved, :indefinite_cluster,
    :unresolved_defective, :singular_longitudinal_projection, :unstable_spectrum,
    :unit_eigenvalue, :coasting_structure, :form_inadmissible, :zero_projection,
    :singular_coefficient, :not_invariant, :not_derived_for_cluster, :not_requested,
    :route_not_selected, :graph_isotropic)

"""
    AMBIGUITY_KINDS

The two kinds of [`AmbiguitySet`](@ref): `:exact_set`, the solution set of the
invariance equation for an exactly degenerate definite group, whose scalar
intervals are sharp; and `:orientation_envelope`, the set formed for a group
the map's own error cannot resolve, which CONTAINS the actual mode outputs
but is not their solution set, so its interval endpoints are containing, not
sharp.
"""
const AMBIGUITY_KINDS = (:exact_set, :orientation_envelope)

"""
    AmbiguitySet(center, shape, factor, multiplicity, kind)

The complete set of canonical momentum dispersions of a definite degenerate
group (theory Section 13.6): the set is `center .+ factor * n` over unit
vectors `n`, so the scalar readout `a' eta` ranges over
`a' center +- sqrt(a' shape a)` with `shape = factor * factor'` positive
semidefinite. `multiplicity` is the group size and must be at least 2: a
single mode has a unique dispersion, never a set. `kind` is one of
[`AMBIGUITY_KINDS`](@ref); for an `:orientation_envelope` the interval
endpoints of [`dispersion_interval`](@ref) are containing, not sharp. The
center is not itself a mode and must never be reported as the dispersion.

The constructor throws an `ArgumentError` on multiplicity below 2, an unknown
kind, a non-square or asymmetric shape, a factor with the wrong row count, a
factor whose `F F'` is not the shape to roundoff, or any non-finite entry.
"""
struct AmbiguitySet
    center::Vector{Float64}
    shape::Matrix{Float64}
    factor::Matrix{Float64}
    multiplicity::Int
    kind::Symbol
    function AmbiguitySet(center::AbstractVector{<:Real}, shape::AbstractMatrix{<:Real},
                          factor::AbstractMatrix{<:Real}, multiplicity::Integer, kind::Symbol)
        multiplicity >= 2 || throw(ArgumentError(
            "AmbiguitySet needs multiplicity >= 2 (got $(multiplicity)); a single mode has a " *
            "unique dispersion, not a set"))
        kind in AMBIGUITY_KINDS || throw(ArgumentError(
            "AmbiguitySet kind must be one of $(AMBIGUITY_KINDS), got :$(kind)"))
        n = length(center)
        size(shape) == (n, n) || throw(ArgumentError(
            "AmbiguitySet shape must be $(n)x$(n) to match the center, got $(size(shape))"))
        size(factor, 1) == n || throw(ArgumentError(
            "AmbiguitySet factor must have $(n) rows to match the center, got $(size(factor))"))
        all(isfinite, center) && all(isfinite, shape) && all(isfinite, factor) ||
            throw(ArgumentError("AmbiguitySet entries must be finite"))
        c = Vector{Float64}(center); s = Matrix{Float64}(shape); f = Matrix{Float64}(factor)
        # Roundoff-scale consistency: one matrix product of k terms per entry,
        # so 16 eps times the scale of the data is a loose first-order bound.
        tol = 16 * eps(Float64) * max(1.0, size(f, 2) * norm(f)^2, norm(s))
        norm(s - transpose(s)) <= tol || throw(ArgumentError(
            "AmbiguitySet shape must be symmetric (asymmetry $(norm(s - transpose(s))))"))
        norm(f * transpose(f) - s) <= tol || throw(ArgumentError(
            "AmbiguitySet factor must satisfy factor * factor' == shape " *
            "(residual $(norm(f * transpose(f) - s)), tolerance $(tol))"))
        return new(c, s, f, Int(multiplicity), kind)
    end
end

"""
    UndeterminedQuantityError(status, reason, detail)

Thrown by [`determined_value`](@ref), [`ambiguity_set`](@ref), and
[`dispersion_interval`](@ref) when a [`Determined`](@ref) quantity is read in
a form its status does not support. Carries the `status`
([`DETERMINATION_STATUSES`](@ref)), the `reason`
([`DETERMINATION_REASONS`](@ref)), and the human `detail` of the quantity, so
the reason is available to code and not only to a reader of the message.
"""
struct UndeterminedQuantityError <: Exception
    status::Symbol
    reason::Symbol
    detail::String
end

function Base.showerror(io::IO, e::UndeterminedQuantityError)
    print(io, "UndeterminedQuantityError: quantity is ", e.status, " (reason :", e.reason, ")")
    isempty(e.detail) || print(io, ": ", e.detail)
end

"""
    Determined{T}

A quantity of type `T` that the physics may or may not determine. `status` is
one of [`DETERMINATION_STATUSES`](@ref); `reason` one of
[`DETERMINATION_REASONS`](@ref) (`:none` exactly when the status is
`:unique`); `detail` a sentence for humans. A quantity that is not unique is
never a number standing in for "unknown": read it with
[`determined_value`](@ref) or [`ambiguity_set`](@ref), which throw an
[`UndeterminedQuantityError`](@ref) carrying the reason, or test it with
[`is_determined`](@ref) and [`is_ambiguous`](@ref).

Constructors:

  * `Determined(value)` -- a unique value of type `typeof(value)`.
  * `Determined{T}(set::AmbiguitySet, reason=:cluster_unresolved, detail="")`
    -- an ambiguous quantity; the reason must not be `:none`.
  * `Determined{T}(reason::Symbol, detail="")` -- an unavailable quantity; the
    reason must not be `:none`.

Every other combination of status, value, set, and reason is an
`ArgumentError` at construction, so a `Determined` is consistent by
construction.
"""
struct Determined{T}
    status::Symbol
    value::Union{Nothing,T}
    set::Union{Nothing,AmbiguitySet}
    reason::Symbol
    detail::String
    function Determined{T}(status::Symbol, value, set, reason::Symbol,
                           detail::AbstractString) where {T}
        status in DETERMINATION_STATUSES || throw(ArgumentError(
            "Determined status must be one of $(DETERMINATION_STATUSES), got :$(status)"))
        reason in DETERMINATION_REASONS || throw(ArgumentError(
            "Determined reason must be one of $(DETERMINATION_REASONS), got :$(reason)"))
        if status === :unique
            value === nothing && throw(ArgumentError("a :unique Determined needs a value"))
            set === nothing || throw(ArgumentError("a :unique Determined carries no AmbiguitySet"))
            reason === :none || throw(ArgumentError(
                "a :unique Determined carries reason :none, got :$(reason)"))
        elseif status === :ambiguous_set
            set isa AmbiguitySet || throw(ArgumentError(
                "an :ambiguous_set Determined needs an AmbiguitySet"))
            value === nothing || throw(ArgumentError(
                "an :ambiguous_set Determined carries no unique value"))
            reason === :none && throw(ArgumentError(
                "an :ambiguous_set Determined needs a reason other than :none"))
        else
            value === nothing || throw(ArgumentError(
                "an :unavailable Determined carries no value"))
            set === nothing || throw(ArgumentError(
                "an :unavailable Determined carries no AmbiguitySet"))
            reason === :none && throw(ArgumentError(
                "an :unavailable Determined needs a reason other than :none"))
        end
        return new{T}(status, value, set, reason, String(detail))
    end
end

Determined(value::T) where {T} = Determined{T}(:unique, value, nothing, :none, "")
Determined{T}(set::AmbiguitySet, reason::Symbol=:cluster_unresolved,
              detail::AbstractString="") where {T} =
    Determined{T}(:ambiguous_set, nothing, set, reason, detail)
Determined{T}(reason::Symbol, detail::AbstractString="") where {T} =
    Determined{T}(:unavailable, nothing, nothing, reason, detail)

"""
    is_determined(d::Determined) -> Bool

Whether `d` holds a unique value (`status === :unique`).
"""
is_determined(d::Determined) = d.status === :unique

"""
    is_ambiguous(d::Determined) -> Bool

Whether `d` holds an [`AmbiguitySet`](@ref) (`status === :ambiguous_set`).
"""
is_ambiguous(d::Determined) = d.status === :ambiguous_set

"""
    determined_value(d::Determined{T}) -> T

The unique value of `d`. Throws an [`UndeterminedQuantityError`](@ref)
carrying the status, reason, and detail when the quantity is an ambiguity set
or unavailable. This is the loud accessor: code that wants a number goes
through it, so a set or an unavailable quantity can never be consumed as one.
"""
function determined_value(d::Determined)
    is_determined(d) && return d.value
    throw(UndeterminedQuantityError(d.status, d.reason, d.detail))
end

"""
    ambiguity_set(d::Determined) -> AmbiguitySet

The [`AmbiguitySet`](@ref) of an ambiguous quantity. Throws an
[`UndeterminedQuantityError`](@ref) when `d` is unique (a unique quantity has
no set; read it with [`determined_value`](@ref)) or unavailable.
"""
function ambiguity_set(d::Determined)
    is_ambiguous(d) && return d.set
    throw(UndeterminedQuantityError(d.status, d.reason,
        is_determined(d) ? "a unique quantity has no ambiguity set; use determined_value" :
                           d.detail))
end

"""
    dispersion_interval(set::AmbiguitySet, a::AbstractVector) -> (lo, hi)
    dispersion_interval(d::Determined, a::AbstractVector) -> (lo, hi)

The range `a' center +- sqrt(a' shape a)` of the scalar readout `a' eta` over
an [`AmbiguitySet`](@ref) (theory Section 13.6). For an `:exact_set` the
endpoints are attained; for an `:orientation_envelope` they are containing,
not sharp. `a` must have the set's dimension. On a [`Determined`](@ref) the
accessor refuses anything but an ambiguous quantity: a unique dispersion
(multiplicity one) has no interval and an unavailable one has no value, and
both throw an [`UndeterminedQuantityError`](@ref) carrying the reason. A set
of multiplicity one cannot be constructed, so the multiplicity guard lives in
the [`AmbiguitySet`](@ref) constructor and is re-checked here.
"""
function dispersion_interval(set::AmbiguitySet, a::AbstractVector{<:Real})
    set.multiplicity >= 2 || throw(ArgumentError(
        "dispersion_interval refuses multiplicity $(set.multiplicity); a single mode has a unique dispersion"))
    n = length(set.center)
    length(a) == n || throw(ArgumentError(
        "dispersion_interval direction must have length $(n), got $(length(a))"))
    all(isfinite, a) || throw(ArgumentError("dispersion_interval direction must be finite"))
    c = dot(a, set.center)
    q = dot(a, set.shape * a)
    # The shape is positive semidefinite; a roundoff-negative quadratic form
    # is a zero half-width, not a NaN.
    w = sqrt(max(q, 0.0))
    return (c - w, c + w)
end

function dispersion_interval(d::Determined, a::AbstractVector{<:Real})
    is_ambiguous(d) && return dispersion_interval(d.set, a)
    throw(UndeterminedQuantityError(d.status, d.reason,
        is_determined(d) ? "a unique dispersion has no interval; use determined_value" :
                           d.detail))
end

function Base.show(io::IO, d::Determined{T}) where {T}
    if is_determined(d)
        print(io, "Determined(", d.value, ")")
    elseif is_ambiguous(d)
        print(io, "Determined{", T, "}(:ambiguous_set, :", d.reason,
              ", multiplicity=", d.set.multiplicity, ", ", d.set.kind, ")")
    else
        print(io, "Determined{", T, "}(:unavailable, :", d.reason, ")")
    end
end
