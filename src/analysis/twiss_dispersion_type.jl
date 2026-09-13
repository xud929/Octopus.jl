# The analysis object's TYPE, declared before the element files. Stage 5 of the
# Twiss and dispersion campaign (docs/design/twiss_dispersion_analysis.md,
# Staging item 5) puts `TwissDispersionAnalysis` in the `analyses = [...]`
# field of every element kind the design's rule selects (`Symplectic6DMap` by
# exact identity and not `NonSymplectic6DMap`, plus `:line`), and
# `@element_spec` registers its `ElementMeta` eagerly at include time, so the
# type must exist when src/elements/Elements.jl loads. Everything else about
# the analysis (the keyword constructor with its validation, the option
# schema, `analyze`, the result tree, the receipts) stays in
# twiss_dispersion_analysis.jl, which follows the elements because it
# dispatches on `LinearizedMap` and calls `one_turn_matrix`.

"""
    TwissDispersionAnalysis(; scaling=:auto, symplectic_rtol=nothing, nonsymplectic=:error,
                              closed_orbit=:require, closed_orbit_atol=nothing, map_uncertainty=0.0,
                              resolution_chord=_DEFAULT_RESOLUTION_CHORD, clusters=:auto,
                              longitudinal_mode=:max_signed_z_area, preferred_form=:auto,
                              dispersion_routes=DISPERSION_ROUTES, newton_max_iterations=50,
                              emittances=nothing, strict=true)

The Twiss and dispersion analysis of a one-turn matrix (theory
docs/theory/twiss_dispersion.md; design note docs/design/twiss_dispersion_analysis.md).
An analysis object carries OPTIONS ONLY; run it with [`analyze`](@ref) on a
`4x4` or `6x6` real matrix in canonical coordinates `(x, px, y, py[, z, pz])`,
on a [`LinearizedMap`](@ref), or on anything [`one_turn_matrix`](@ref)
accepts. The options, their meanings and their runtime consumers are the
[`analysis_option_schema`](@ref); every option is certified by a receipt and
listed in the result's configuration report ([`configuration_report`](@ref)).

  * `scaling`: `:auto` (reciprocal canonical scaling from the matrix, stage
    1 `_reciprocal_scaling`), `:none`, or a tuple of `d/2` positive factors.
  * `symplectic_rtol`: `nothing` uses stage 1's roundoff rule (the
    magnitude-aware row ratio of the `Linear6D` validator must be at most
    one); a number is compared with the Frobenius defect. A finite-difference
    `LinearizedMap` REQUIRES a number (its truncation error is not roundoff).
  * `nonsymplectic`: `:error` throws on a defect above the tolerance,
    `:flag` continues and marks the result `:degraded`. Never a repair.
  * `closed_orbit`, `closed_orbit_atol`: on a `LinearizedMap` the recorded
    fixed-point residual is compared with the tolerance (`nothing` = the
    roundoff default, `_CLOSED_ORBIT_ATOL_MULTIPLIER`); `:require` throws
    above it, `:warn` warns once and marks the result `:degraded`. Both are
    inactive on a bare matrix.
  * `map_uncertainty`: a declared error of the matrix, folded into `rho_M0`.
  * `resolution_chord`: the chord above which two candidate clusters merge
    (stage 3; the default is a MEASURED policy, `_DEFAULT_RESOLUTION_CHORD`);
    `Inf` forces resolution and marks the clusters `forced`.
  * `clusters`: `:auto`, or an explicit partition of the canonical
    eigenvalue indices (a vector of index vectors). An explicit partition
    PROMISES only the grouping: the classification is still computed (an
    explicit union of far-apart pairs with a mixed Gram is `:indefinite`),
    and the 4D frame construction re-clusters automatically at the same
    chord (stage 2/3 kernels take no partition).
  * `longitudinal_mode`: `:max_signed_z_area` (the uncertified heuristic,
    see `_LONGITUDINAL_RULES`), an `Int` canonical eigenvalue index, or a
    `Float64` synchrotron tune `mu_s` in `(0, pi)` (radians per turn).
  * `preferred_form`: `:auto` (the admissible Edwards-Teng form with the
    larger area weight, ties to form 1), `1` or `2`. Both forms are always
    computed; this selects the one PRESENTED.
  * `dispersion_routes`: a non-empty tuple of distinct members of
    `DISPERSION_ROUTES`; `:eigenplane` is always the primary route.
  * `newton_max_iterations`: the Newton route's iteration cap (inactive when
    `:newton` is not selected and on `4x4` input).
  * `emittances`: `nothing`, or rms mode emittances `(eps_1, eps_2[, eps_s])`
    for the matched covariance.
  * `strict`: `true` throws [`OpticsAnalysisError`](@ref) on a `:failed`
    verdict; `false` returns the failed result.

Argument errors at construction: an unknown symbol, a chord outside `(0, 2]`
and not `Inf`, an empty or repeated route tuple or an unknown route, a
partition that is not a vector of non-empty vectors of positive integers, a
cap below one, a negative or non-finite number, an emittance tuple of a
length other than two or three or with a negative entry, a tune outside
`(0, pi)`.
"""
struct TwissDispersionAnalysis <: AbstractAnalysis
    scaling::Union{Symbol,Tuple{Vararg{Float64}}}
    symplectic_rtol::Union{Nothing,Float64}
    nonsymplectic::Symbol
    closed_orbit::Symbol
    closed_orbit_atol::Union{Nothing,Float64}
    map_uncertainty::Float64
    resolution_chord::Float64
    clusters::Union{Symbol,Vector{Vector{Int}}}
    longitudinal_mode::Union{Symbol,Int,Float64}
    preferred_form::Union{Symbol,Int}
    dispersion_routes::Tuple{Vararg{Symbol}}
    newton_max_iterations::Int
    emittances::Union{Nothing,NTuple{2,Float64},NTuple{3,Float64}}
    strict::Bool
end
