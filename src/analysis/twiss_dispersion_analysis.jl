export TwissDispersionAnalysis, TwissDispersionResult, OpticsAnalysisError, NormalMode,
       ANALYSIS_STATUSES, analyze, analysis_option_schema, matched_covariance, normal_mode

# Stage 4b of the Twiss and dispersion analysis (design note
# docs/design/twiss_dispersion_analysis.md, "Types and availability",
# "Execution API and option certification", Staging item 4; campaign record
# docs/history/twiss_dispersion_analysis_history.md). This file is the PUBLIC
# SURFACE of the analysis: the analysis object with its options and schema,
# the verb `analyze`, the result tree, the strict-mode error, the accessors and
# the configuration report. Every kernel it calls lives in the stage 1-4a files
# (symplectic_linear_algebra.jl, mode_clusters.jl, degenerate_dispersion.jl,
# eigenmodes_4d.jl, coupled_parameterizations.jl, dispersion_routes.jl,
# canonical_separation.jl, one_turn_matrix.jl) and computes on the SCALED
# matrix; this file scales first and transforms every physical quantity back
# by the stage 1 `_unscale_*` table.

"""
    ANALYSIS_STATUSES

Every verdict a [`TwissDispersionResult`](@ref) may carry in its `status`
field. Pinned against the source in the suite the way `CONFIGURATION_STATUSES`
and `DETERMINATION_STATUSES` are.

  * `:passed` -- every numerical check held and no limitation was flagged.
  * `:degraded` -- every check held, but the result carries at least one
    honest limitation in `degradations` (a flagged non-symplectic input, a
    closed-orbit warning, a forced or unresolved or indefinite cluster, a
    label tie, an uncertified longitudinal selection that could not be
    cross-checked, iterative routes that converged to another invariant
    plane, an unavailable primary dispersion for a physical reason).
  * `:failed` -- a numerical check did not hold (`failures` names each one);
    under `strict = true` `analyze` throws [`OpticsAnalysisError`](@ref)
    carrying this result, under `strict = false` it returns it.
"""
const ANALYSIS_STATUSES = (:passed, :degraded, :failed)

"""
    _FRAME_ACCEPTANCE_MULTIPLIER

PROVISIONAL (stage 4b Part D1 measures it). The `c` in the acceptance test of
the 4D normal-mode frame: the normalized (I1) reconstruction residual of
`NormalModeFrame4D` must be at most `c * rho_M1` (the kappa of a backward
error of a backward-stable solve is 1: experiences.md, "the kappa is the
condition number of the quantity COMPARED") and its (E7) symplecticity
residual at most `c * rho_M1 * cond(U_4)` (FIRST order in the eigenvector
error, corrected 2026-09-14 from second order: the derivation pass below);
`rho_M1` is the clusters' perturbation scale; above either the result FAILS
(the stage 2 record: the acceptance threshold on the frame's residual
belongs to the analysis).
Extremes (stage 4b D1, measurement_table_4b.md c_frame: 54 unique frames of
25 dense 6D seeds, 8 dense 4x4 seeds, 4 coupled 4x4 maps, 3 coasting maps,
the DBA and FODO cells, 5 prescribed-h maps): `(I1) / rho_M1` at most 4.44
(dense 6D seed 20260932) and `(E7) / (rho_M1 cond(U_4))` at most 3.90 (seed
20260919), so the one-tenth rule needs c >= 44.4. No fixture the frame
acceptance must reject exists: a non-symplectic perturbation folds into
`rho_M1` (the dense map plus 1e-6 keeps `(I1) / rho_M1 = 0.31` and fails
through the (K5) separation), so the rejected edge is open. The boundary is
the near-degenerate coupled ladder `R(0.5) (+) R(0.5 + delta)` rotated by
0.3: its (E7) ratio grows as `eps / (delta rho_M1)` (8.3e2 at delta = 1e-3,
1.25e10 at 1e-11) while `cond(U_4) = 1`, so the analysis FAILS resolved
frames whose tunes differ by 1e-3; under the theory review's kappa
`cond(U_4) ||U_4||^2 / chord_min` the same rows are 0.13-0.83 and the
accepted extreme 1.56.

Owner decision 2026-09-14 (carried item 4): the landed kappa stays. The
ladder's failure at delta <= 1e-3 is an accepted, documented limitation: a
coupled pair whose phase advances differ by 1e-3 rad or less FAILS this test
with a unit-conditioned frame although `_recover_modes` resolved its two
clusters by the chord `min(2, 2 kappa rho_M1 / g)` (`_chord` in
mode_clusters.jl); the multiplier-1 ratio lies between 0.1 / delta and 0.9 /
delta down the ladder (8.3e2, 3.5e4, 1.25e6, 3.1e8, 1.25e10 at delta = 1e-3
... 1e-11). The resolution kappa was declined: on the 200 dense 6x6 maps of
the validation script's set the U_6 symplecticity ratio correlates NEGATIVELY
with it (Spearman -0.54 / -0.52, native / haswell) and with cond(U_6) (-0.50),
so it has the wrong shape on the population the identity contract freezes (the
M3 record in the history). The derivation pass of the same day (owner decision
(d); scratch
`result/twiss_impl_2026_09_11/carried/item4_derivation/DERIVATION.md`, cited
by path) finds the (E7) residual FIRST order in the eigenvector error, exactly
(E7)^2 = (n_1^2 + n_2^2) / 2 + |u_1^T S u_2|^2 + |u_1^dag S u_2|^2, bounded by
2 sqrt(2) c_1 rho_M1 cond(U_4) / _pair_gap(rho_1, rho_2): the derived kappa is
`cond(U_4) / _pair_gap` (`mode_clusters.jl`), one power of cond(U_4) and one
chord below the review's, and it explains the ladder ((E7) x delta = 0.5-3.4
eps, log-log slope -1.000). On the 200 + 20 set it puts this row's largest
multiplier-1 ratio at 0.893 / 0.831 (H15 c = 16) against the landed 6.494 /
5.508 (128) and removes the correlation with 1 / gap (Spearman +0.51 / +0.47
-> -0.10 / -0.19). The algebra, the numerics and the data were cross-checked
by three independent agents; the kappa is NOT adopted here (decision (a)). Any
kappa change is a separate, owner-decided job: the 4b ladder windows
re-measured in both CPU arms, the contract's twin rows re-frozen by the H15
rule, and the contract's c = 32 for `r_u6_symplecticity` harmonized with the
64 here in the same change (the history's section "2026-09-14: carried item 4
decided, the landed kappa rho_M1 cond(U) stays for the (E7) and U_6
symplecticity tests, the near-degenerate ladder's false FAIL is an accepted
limitation, the resolution kappa is declined; the read-only derivation pass
(docs(analysis) commit)").
"""
const _FRAME_ACCEPTANCE_MULTIPLIER = 64.0

"""
    _NORMALIZER_ACCEPTANCE_MULTIPLIER

PROVISIONAL (D1). The `c` in the acceptance test of the 6D normalizer `U_6`
of `ProjectedOptics6D`: its normalized (I1) reconstruction residual must be
at most `c * rho_M1` (kappa = 1, as for the 4D frame) and its symplecticity
residual at most `c * rho_M1 * cond(U_6)`; above either the result FAILS.
Extremes (stage 4b D1, measurement_table_4b.md c_normalizer: 37 bunched
fixtures with a unique `U_6`): `reconstruction / rho_M1` at most 4.45 (dense
6D seed 20260932), `symplecticity / (rho_M1 cond(U_6))` at most 6.39 (seed
20260919): window [63.9, open), 64 sits just inside. No fixture the `U_6`
acceptance must reject exists (the perturbed map loses its `U_6` through the
(K5) separation, `:not_invariant`).

The identity contract freezes `r_u6_symplecticity` at c = 32 (its own H15
measurement on the 20 + 5 set) beside this 64 with the same kappa; harmonizing
the two is part of the kappa change of carried item 4, if the owner orders it
(owner decision 2026-09-14, the history's section "2026-09-14: carried item 4
decided, the landed kappa rho_M1 cond(U) stays for the (E7) and U_6
symplecticity tests, the near-degenerate ladder's false FAIL is an accepted
limitation, the resolution kappa is declined; the read-only derivation pass
(docs(analysis) commit)"). That section's derivation pass (single-agent, not
cross-checked) finds the symplecticity residual of U_6 = M_cal blockdiag(U_4,
B) equal to the frame's (E7) residual plus an eps-sized separation term, by
the exact identity U_6^T S_6 U_6 - S_6 = Ub^T (M_cal^T S_6 M_cal - S_6) Ub +
blockdiag(U_4^T S_4 U_4 - S_4, B^T S_2 B - S_2) whose last block is exactly
sqrt(2) |det B - 1| <= eps; cond(U_6) does not enter its scale (the derived
kappa is the frame's `cond(U_4) / _pair_gap` plus ||M_cal||_F^2 max(cond(U_4),
||B||_2^2), H15 c = 8 on the 200 + 20 set against the landed 64). The
reconstruction residual's excess over the frame's (I1) is the longitudinal
block's symplecticity defect (det Mbar_s - 1, O(eps)) divided by |Mbar_s[1,2]|
= beta_s |sin mu_s|, exponent 0.3-0.4 against 1 / sin mu_3 on the 200 + 20 set
(not 1), and kappa = 1 with c = 64 stays the better description of that
population (worst two-arm ratio 13.17 on map 42 haswell, 0.21 of c). Neither
kappa changes here.
"""
const _NORMALIZER_ACCEPTANCE_MULTIPLIER = 64.0

"""
    _COVARIANCE_ACCEPTANCE_MULTIPLIER

PROVISIONAL (D1). The `c` in the acceptance test of a matched covariance:
the RAW closure residual `||M Sigma M' - Sigma||_F` (both dimensions:
`MatchedCovariance6D.closure_residual`, or the 4D closure of
`_matched_covariance_4d`) must be at most `c * rho_M1 * cond(U) * max(1,
||Sigma||)`; above it the result FAILS. The theory (K14) zz identity
`(G_j)_zz = eta' S_4 Gbar_j S_4' eta` is emittance-free and is REPORTED
under its own name with the tolerance `c * rho_M1 * cond(U) * max(1, max_j
|(G_j)_zz|)`, not judged (the stage 4b theory review: the dossier's F3 step
10 judged the identity and called it the closure, which made the check
vacuous as the emittances grew). Extremes (stage 4b D1, measurement_table_4b.md c_covariance: 49 fixtures
with emittances, the dense 6D map at emittances 1e-12 to 1e3, 25 dense 6D
seeds, 8 dense and 4 coupled 4x4 maps, 5 prescribed-h maps): `closure /
(rho_M1 cond(U) max(1, ||Sigma||))` at most 0.165 (dense 6D seed 20260911 at
emittances (1, 1, 1)); the reported (K14) identity ratio at most 0.036;
window [1.65, open), no fixture the closure must reject (a non-symplectic
map folds its defect into `rho_M1`).
"""
const _COVARIANCE_ACCEPTANCE_MULTIPLIER = 64.0

"""
    _TRACE_GAP_MULTIPLIER

PROVISIONAL (D1). Stage 2's closed-form and map-route guards
(`_closed_form_check_4d`, `_edwards_teng_from_map`) require a `min_trace_gap`
with no default; the analysis derives it from the data as
`min_trace_gap = c * rho_M1 * max(1, ||M_4||_F)` (the two block traces must
differ by more than the map's own uncertainty scale for the closed-form
division to mean anything). The suite's stage 2-4a fixtures used the literal
1e-8. Extremes (stage 4b D1, measurement_table_4b.md c_trace_gap, 54 unique
frames): `|tau_+ - tau_-| / (rho_M1 max(1, ||M_4||))` at least 2.49e11 (the
FODO cell), so c must stay below 2.49e10; equal mode traces mean coincident
eigenvalues, where no frame forms, so no frame the guard must refuse exists.
On the coupled ladder `R(0.5) (+) R(0.5 + delta)` the closed form is guarded
(`:singular_coefficient`) at delta = 1e-11 (ratio 5.4e3) and available at
1e-9 (5.4e5).
"""
const _TRACE_GAP_MULTIPLIER = 64.0

"""
    _STABILITY_ATOL_MULTIPLIER

PROVISIONAL (D1). Stage 2's closed-form route takes a `stability_atol` for its
raw-modulus stability test (a division guard only; the frame decides stability
on the Schur block, stage 3). The analysis derives it as
`stability_atol = c * rho_M1`. Extremes (stage 4b D1, measurement_table_4b.md
c_stability, 54 elliptic frames): `max |1 - |lambda|| / rho_M1` at most 5.04
(dense 6D seed 20260932); the spectra off the unit circle (the hyperbolic
synchrotron pair, the hyperbolic 4x4 map, the shear unit pair, whose
computed eigenvalues split by 7.5e5 rho_M1) depart by at least 7.47e5
rho_M1: window [50.4, 7.47e4].
"""
const _STABILITY_ATOL_MULTIPLIER = 64.0

"""
    _CLOSED_ORBIT_ATOL_MULTIPLIER

PROVISIONAL (D1). The default of the `closed_orbit_atol` option when the
user passes `nothing`: `c * eps * max(1, maximum(abs, point))`, the roundoff
of evaluating the map once at the expansion `point` recorded in the
`LinearizationProvenance`; the fixed-point residual `map(point) - point` is
compared with it in the max norm. A lattice with the origin as its fixed
point gives a residual of exactly zero. Extremes (stage 4b D1, measurement_table_4b.md
c_closed_orbit, scaled coordinates): linearizations at the origin (the dense
Linear6DSpec by complex step and by finite differences, the FODO, DBA and
FODO + sextupole cells) have `residual / (eps max(1, max |C p|))` at most
0.068 (the DBA cell, residual 2.3e-17); displaced expansion points x or y >=
1e-9 on the FODO + sextupole cell and on the linear map have at least 3.48e6
(x = 1e-9): window [0.68, 3.48e5]. Boundary: x = 1e-12 (3.5e3) is refused,
x = 1e-14 (35) accepted under `:require`.
"""
const _CLOSED_ORBIT_ATOL_MULTIPLIER = 64.0

"""
    _TUNE_CHORD_FLOOR_MULTIPLIER

PROVISIONAL (D1). A synchrotron tune `mu_s` passed as `longitudinal_mode`
identifies a mode only when the chord `|lambda - exp(-i mu_s)|` of the
nearest eigenvalue is at most half the chord to the runner-up outside its
conjugate pair, OR at most `c * rho_M1` (this `c`): below the perturbation
scale two eigenvalues are not distinguishable by the tune (a degenerate
synchrotron/betatron pair, whose ambiguity the clusters carry), so the
guard does not reject at roundoff. Measured (stage 4b D1, measurement_table_4b.md
c_tune_floor, 74 tune rows on 6 dense seeds, 2 prescribed maps, the
repeated-betatron and the indefinite maps): exact tunes are accepted through
the half-gap rule (chords at most 4.6e-13 against runner-ups of at least
0.108); on a degenerate pair (repeated betatron 0.72, indefinite 0.73) the
runner-up is a few eps and a tune offset by 4 or 16 eps is accepted through
this floor with `chord / rho_M1` at most 2.60 (indefinite, + 16 eps), while
offsets of 1e-12 and 1e-10 (ratios 6.1e2 and 6.1e4) are refused (boundary);
midpoint tunes between two eigenvalues and the tunes 2.5 and 3.0 are refused
with `chord / rho_M1` at least 2.19e13: window [26.0, 2.19e12].
"""
const _TUNE_CHORD_FLOOR_MULTIPLIER = 64.0

"""
    _LONGITUDINAL_RULES

The symbolic values `longitudinal_mode` accepts: `:max_signed_z_area`, stage
4a's labelling heuristic (largest signed z-area of the (K12) table). By (K12)
`kappa_sz = h`, so for `h < 1/2` a betatron mode can carry more z-area and
the rule is UNCERTIFIED (campaign record, stage 4a "Carried forward" item
1); an explicit eigenvalue index (`Int`) or a synchrotron tune (`Float64`,
the mode whose eigenvalue is nearest `exp(-i mu_s)`) certifies the choice.
"""
const _LONGITUDINAL_RULES = (:max_signed_z_area,)

"""
    _ANALYSIS_CONSUMERS

The receipt consumers of the analysis, one per option group (design
"Certification"): every option's `ConfigurationOptionMeta.consumer` is a
member, every `_record_execution!` call in this file names a member, and
each receipt's NamedTuple carries the option's own name as a key (the
repo's matcher convention) beside what the branch did.
"""
const _ANALYSIS_CONSUMERS = (:analysis_scaling, :analysis_symplectic_check, :analysis_closed_orbit,
                             :analysis_cluster_resolution, :analysis_labels, :analysis_edwards_teng,
                             :analysis_dispersion_routes, :analysis_newton, :analysis_covariance,
                             :analysis_strictness)

# The `TwissDispersionAnalysis` struct and its docstring live in
# twiss_dispersion_type.jl (included before the element files, which declare the
# type in their `analyses` field since stage 5); the constructor below validates.

description(::Type{TwissDispersionAnalysis}) =
    "Twiss, coupling and dispersion analysis of a 4x4 or 6x6 one-turn matrix with certified options."

function _analysis_number(name::Symbol, x)
    x isa Real || throw(ArgumentError("TwissDispersionAnalysis: $(name) must be a real number, got $(x)"))
    (isfinite(x) && x >= 0) || throw(ArgumentError("TwissDispersionAnalysis: $(name) must be finite and non-negative, got $(x)"))
    return Float64(x)
end

function TwissDispersionAnalysis(; scaling=:auto, symplectic_rtol=nothing, nonsymplectic::Symbol=:error,
                                 closed_orbit::Symbol=:require, closed_orbit_atol=nothing, map_uncertainty=0.0,
                                 resolution_chord=_DEFAULT_RESOLUTION_CHORD, clusters=:auto,
                                 longitudinal_mode=:max_signed_z_area, preferred_form=:auto,
                                 dispersion_routes=DISPERSION_ROUTES, newton_max_iterations::Integer=50,
                                 emittances=nothing, strict::Bool=true)
    if scaling isa Symbol
        scaling in (:auto, :none) || throw(ArgumentError("TwissDispersionAnalysis: scaling must be :auto, :none or a tuple of positive factors, got :$(scaling)"))
        sc = scaling
    elseif scaling isa Tuple
        (length(scaling) in (2, 3) && all(x -> x isa Real && isfinite(x) && x > 0, scaling)) ||
            throw(ArgumentError("TwissDispersionAnalysis: explicit scaling factors must be 2 or 3 positive finite reals, got $(scaling)"))
        sc = Tuple(Float64.(scaling))
    else
        throw(ArgumentError("TwissDispersionAnalysis: scaling must be :auto, :none or a tuple of positive factors, got $(scaling)"))
    end
    rtol = symplectic_rtol === nothing ? nothing : _analysis_number(:symplectic_rtol, symplectic_rtol)
    nonsymplectic in (:error, :flag) || throw(ArgumentError("TwissDispersionAnalysis: nonsymplectic must be :error or :flag, got :$(nonsymplectic)"))
    closed_orbit in (:require, :warn) || throw(ArgumentError("TwissDispersionAnalysis: closed_orbit must be :require or :warn, got :$(closed_orbit)"))
    co_atol = closed_orbit_atol === nothing ? nothing : _analysis_number(:closed_orbit_atol, closed_orbit_atol)
    unc = _analysis_number(:map_uncertainty, map_uncertainty)
    resolution_chord isa Real || throw(ArgumentError("TwissDispersionAnalysis: resolution_chord must be a number in (0, 2] or Inf, got $(resolution_chord)"))
    chord = Float64(resolution_chord)
    ((0 < chord <= 2) || chord == Inf) || throw(ArgumentError("TwissDispersionAnalysis: resolution_chord must lie in (0, 2] or be Inf, got $(chord)"))
    if clusters isa Symbol
        clusters === :auto || throw(ArgumentError("TwissDispersionAnalysis: clusters must be :auto or a vector of index vectors, got :$(clusters)"))
        cl = clusters
    elseif clusters isa AbstractVector && all(g -> g isa AbstractVector && !isempty(g) && all(i -> i isa Integer && i >= 1, g), clusters) && !isempty(clusters)
        cl = [Int.(collect(g)) for g in clusters]
    else
        throw(ArgumentError("TwissDispersionAnalysis: clusters must be :auto or a non-empty vector of non-empty vectors of positive integers, got $(clusters)"))
    end
    if longitudinal_mode isa Symbol
        longitudinal_mode in _LONGITUDINAL_RULES || throw(ArgumentError("TwissDispersionAnalysis: longitudinal_mode must be one of $(_LONGITUDINAL_RULES), an eigenvalue index or a synchrotron tune, got :$(longitudinal_mode)"))
        lm = longitudinal_mode
    elseif longitudinal_mode isa Integer
        longitudinal_mode >= 1 || throw(ArgumentError("TwissDispersionAnalysis: an explicit longitudinal_mode index must be positive, got $(longitudinal_mode)"))
        lm = Int(longitudinal_mode)
    elseif longitudinal_mode isa Real
        (isfinite(longitudinal_mode) && 0 < longitudinal_mode < pi) || throw(ArgumentError("TwissDispersionAnalysis: a synchrotron tune must lie in (0, pi) radians per turn, got $(longitudinal_mode)"))
        lm = Float64(longitudinal_mode)
    else
        throw(ArgumentError("TwissDispersionAnalysis: longitudinal_mode must be a rule symbol, an eigenvalue index or a synchrotron tune, got $(longitudinal_mode)"))
    end
    if preferred_form isa Symbol
        preferred_form === :auto || throw(ArgumentError("TwissDispersionAnalysis: preferred_form must be :auto, 1 or 2, got :$(preferred_form)"))
        pf = preferred_form
    elseif preferred_form isa Integer && preferred_form in (1, 2)
        pf = Int(preferred_form)
    else
        throw(ArgumentError("TwissDispersionAnalysis: preferred_form must be :auto, 1 or 2, got $(preferred_form)"))
    end
    (dispersion_routes isa Tuple && !isempty(dispersion_routes) && all(r -> r isa Symbol, dispersion_routes)) ||
        throw(ArgumentError("TwissDispersionAnalysis: dispersion_routes must be a non-empty tuple of route symbols, got $(dispersion_routes)"))
    for r in dispersion_routes
        r in DISPERSION_ROUTES || throw(ArgumentError("TwissDispersionAnalysis: unknown dispersion route :$(r); the routes are $(DISPERSION_ROUTES)"))
    end
    length(unique(dispersion_routes)) == length(dispersion_routes) || throw(ArgumentError("TwissDispersionAnalysis: dispersion_routes repeats a route: $(dispersion_routes)"))
    newton_max_iterations >= 1 || throw(ArgumentError("TwissDispersionAnalysis: newton_max_iterations must be at least 1, got $(newton_max_iterations)"))
    if emittances === nothing
        em = nothing
    elseif emittances isa Tuple && length(emittances) in (2, 3) && all(e -> e isa Real && isfinite(e) && e >= 0, emittances)
        em = Tuple(Float64.(emittances))
    else
        throw(ArgumentError("TwissDispersionAnalysis: emittances must be nothing or a tuple of 2 or 3 finite non-negative rms emittances, got $(emittances)"))
    end
    return TwissDispersionAnalysis(sc, rtol, nonsymplectic, closed_orbit, co_atol, unc, chord, cl, lm, pf,
                                   Tuple(dispersion_routes), Int(newton_max_iterations), em, strict)
end

"""
    _with_longitudinal_mode(a::TwissDispersionAnalysis, index::Integer) -> TwissDispersionAnalysis

The same analysis with `longitudinal_mode` replaced by the Int `index` (the
certified re-run of the two-run recipe: `index >= 1`, else the keyword
constructor's `ArgumentError`). Every other option is carried by derivation
over `fieldnames(TwissDispersionAnalysis)`, never by a hand-typed keyword
list, so a future option is carried, not reset to its default. Used by the
identity contract's `_identity_contract_certified` and by the suite.
"""
function _with_longitudinal_mode(a::TwissDispersionAnalysis, index::Integer)
    kept = (f => getfield(a, f) for f in fieldnames(TwissDispersionAnalysis) if f !== :longitudinal_mode)
    return TwissDispersionAnalysis(; kept..., longitudinal_mode=Int(index))
end

const _TWISS_DISPERSION_OPTION_SCHEMA = (
    scaling=ConfigurationOptionMeta(Union{Symbol,Tuple{Vararg{Float64}}}, :auto,
        "Reciprocal canonical scaling of the matrix before every kernel: :auto derives per-plane factors from the matrix, :none leaves it, a tuple gives the factors. Physical results are transformed back; residuals are reported in scaled coordinates.";
        category=:execution, supported_backends=(CPUThreadsBackend,), consumer=:analysis_scaling),
    symplectic_rtol=ConfigurationOptionMeta(Union{Nothing,Float64}, nothing,
        "Symplectic-defect tolerance. nothing = stage 1's roundoff rule (row ratio at most one); a number is compared with the Frobenius defect of the scaled matrix. Required as a number for a finite-difference LinearizedMap.";
        category=:numerical, supported_backends=(CPUThreadsBackend,), consumer=:analysis_symplectic_check),
    nonsymplectic=ConfigurationOptionMeta(Symbol, :error,
        "What a defect above the tolerance does: :error throws an ArgumentError naming the defect and the rule; :flag continues and marks the result :degraded. The matrix is never symplectified.";
        category=:execution, supported_backends=(CPUThreadsBackend,), consumer=:analysis_symplectic_check),
    closed_orbit=ConfigurationOptionMeta(Symbol, :require,
        "On a LinearizedMap, what a fixed-point residual above closed_orbit_atol does: :require throws, :warn warns once and marks the result :degraded. Inactive on a bare matrix, which carries no closed-orbit information.";
        category=:execution, supported_backends=(CPUThreadsBackend,), dependencies=(:closed_orbit_atol,),
        consumer=:analysis_closed_orbit),
    closed_orbit_atol=ConfigurationOptionMeta(Union{Nothing,Float64}, nothing,
        "Max-norm tolerance on the recorded fixed-point residual map(point) - point; nothing = the roundoff default _CLOSED_ORBIT_ATOL_MULTIPLIER * eps * max(1, max|point|). Inactive on a bare matrix.";
        category=:numerical, supported_backends=(CPUThreadsBackend,), consumer=:analysis_closed_orbit),
    map_uncertainty=ConfigurationOptionMeta(Float64, 0.0,
        "A declared absolute error of the matrix entries, folded into the perturbation scale rho_M0 that every resolution and acceptance test reads.";
        category=:numerical, supported_backends=(CPUThreadsBackend,), consumer=:analysis_cluster_resolution),
    resolution_chord=ConfigurationOptionMeta(Float64, _DEFAULT_RESOLUTION_CHORD,
        "The chord q = min(2, 2 kappa rho_M1 / g) above which two candidate mode clusters merge (stage 3). The default is a MEASURED policy (campaign record, stage 3: bracket [2.96e-5, 2.96e-2], geometric mean rounded to a power of ten). Inf forces resolution and marks the clusters forced. Read by every clustering, including the re-clustering of the separated transverse block.";
        category=:numerical, supported_backends=(CPUThreadsBackend,), consumer=:analysis_cluster_resolution),
    clusters=ConfigurationOptionMeta(Union{Symbol,Vector{Vector{Int}}}, :auto,
        "The mode clusters: :auto clusters by the chord; an explicit partition (a vector of canonical eigenvalue index vectors) fixes the GROUPING only. The classification is still computed (an explicit union of far-apart pairs with a mixed Gram is :indefinite), and the 4D frame construction re-clusters automatically at the same chord.";
        category=:physics, supported_backends=(CPUThreadsBackend,), dependencies=(:resolution_chord,),
        consumer=:analysis_cluster_resolution),
    longitudinal_mode=ConfigurationOptionMeta(Union{Symbol,Int,Float64}, :max_signed_z_area,
        "Which mode is the synchrotron mode of a 6x6 map. :max_signed_z_area is stage 4a's heuristic (UNCERTIFIED: by (K12) kappa_sz = h and kappa_1z + kappa_2z = 1 - h, so a betatron mode CAN carry more z-area and the 3x3 array cannot distinguish a row permutation); an Int names a canonical eigenvalue index; a Float64 is the synchrotron tune mu_s in (0, pi), selecting the mode whose eigenvalue pair contains the one nearest exp(-i mu_s) (the chord must be below half the chord to the runner-up, else an ArgumentError). Inactive on 4x4 input and on a coasting map.";
        category=:physics, supported_backends=(CPUThreadsBackend,), consumer=:analysis_labels),
    preferred_form=ConfigurationOptionMeta(Union{Symbol,Int}, :auto,
        "Which Edwards-Teng form the result PRESENTS as preferred (both are always computed): :auto takes the admissible form with the larger area weight (ties to form 1); 1 or 2 name a form. Inactive when the transverse optics are unavailable.";
        category=:physics, supported_backends=(CPUThreadsBackend,), consumer=:analysis_edwards_teng),
    dispersion_routes=ConfigurationOptionMeta(Tuple{Vararg{Symbol}}, DISPERSION_ROUTES,
        "The dispersion routes to execute on a 6x6 map, a non-empty tuple of distinct members of DISPERSION_ROUTES; :eigenplane is always the primary. Inactive on 4x4 input and on a coasting map (no synchrotron mode); on a bunched map whose longitudinal cluster is blocked the requested tuple is still read (receipt :analysis_dispersion_routes), so the option stays resolved.";
        category=:physics, supported_backends=(CPUThreadsBackend,), consumer=:analysis_dispersion_routes),
    newton_max_iterations=ConfigurationOptionMeta(Int, 50,
        "Iteration cap of the Newton dispersion route. Inactive unless :newton is among the executed routes.";
        category=:numerical, supported_backends=(CPUThreadsBackend,), dependencies=(:dispersion_routes,),
        consumer=:analysis_newton),
    emittances=ConfigurationOptionMeta(Union{Nothing,NTuple{2,Float64},NTuple{3,Float64}}, nothing,
        "rms mode emittances (eps_1, eps_2) for a 4x4 map or (eps_1, eps_2, eps_s) for a 6x6 map; when given the matched covariance is computed and checked. Inactive when nothing.";
        category=:physics, supported_backends=(CPUThreadsBackend,), consumer=:analysis_covariance),
    strict=ConfigurationOptionMeta(Bool, true,
        "true throws OpticsAnalysisError carrying the full result on a :failed verdict; false returns the failed result.";
        category=:execution, supported_backends=(CPUThreadsBackend,), consumer=:analysis_strictness),
)

"""
    analysis_option_schema(analysis_or_type)

The public option schema of an analysis: a NamedTuple of
`ConfigurationOptionMeta`, one per option, keyed by the option's field name,
each naming its runtime consumer. [`TwissDispersionAnalysis`](@ref) has
fourteen options; `PlaceholderAnalysis` has none (an empty NamedTuple).
Certified by `validate_configuration_metadata()` (keys == fields, defaults ==
constructor defaults, every consumer named) and probed by the
`AnalysisOptionEffectivenessContract`.
"""
function analysis_option_schema end
analysis_option_schema(::Type{TwissDispersionAnalysis}) = _TWISS_DISPERSION_OPTION_SCHEMA
analysis_option_schema(::TwissDispersionAnalysis) = _TWISS_DISPERSION_OPTION_SCHEMA
analysis_option_schema(::Type{PlaceholderAnalysis}) = NamedTuple()
analysis_option_schema(::PlaceholderAnalysis) = NamedTuple()

# ---------------------------------------------------------------------------
# Result types. Runtime representation: they carry what the analysis computed
# and may change shape between releases; the analysis object and its option
# schema are the stable surface (design "Types and availability").

"""
    NormalMode

One labelled normal mode of the analysed map (design "Types and
availability", the normal-modes struct): `index` (its position in the
result's mode list: 1, 2 for a 4x4 map; 1, 2 transverse and 3 synchrotron
for a 6x6 map), `eigenvalue` (the oriented eigenvalue `exp(-i mu)`), `tune`
(`mu` in radians per turn), `vector` (the complex mode vector, `u' S u =
-2i`), `real_pair` (`Re u`, `-Im u`), `projector` (`P_j = -Im(u u') S`),
`covariance` (`G_j = Re(u u')`), `beta`, `alpha`, `gamma`, `signed_area`
(the per-plane projected Twiss row of the (M1)/(K12) arrays: one entry per
plane), `eigenvector_residual` (`||M u - rho u||`, normalized and raw), all
in SCALED coordinates. Built by [`normal_mode`](@ref) from the frame of a
[`TwissDispersionResult`](@ref).
"""
struct NormalMode
    index::Int
    eigenvalue::ComplexF64
    tune::Float64
    vector::Vector{ComplexF64}
    real_pair::NTuple{2,Vector{Float64}}
    projector::Matrix{Float64}
    covariance::Matrix{Float64}
    beta::Vector{Float64}
    alpha::Vector{Float64}
    gamma::Vector{Float64}
    signed_area::Vector{Float64}
    eigenvector_residual::NamedTuple{(:normalized, :raw), Tuple{Float64, Float64}}
end

"""
    TransverseOptics4D

The stage 2 products on ONE 4D normal-mode frame, exactly the bundle
`_transverse_optics_6d` forms on a separated block, here for the frame of
the matrix itself (4x4 input), of the separated betatron block `Mbar_beta`
(6x6 input with a unique separation) or of `M_rr` (coasting map; the
separation with `zeta = 0`, `h = 1` gives `Mbar_beta = M_rr` to the bit):
`eigenmodes` (the `Eigenmodes4D` with its clusters), `frame`, `closed_form`
(the closed-form check with the derived `min_trace_gap` and
`stability_atol`), `mais_ripken`, the three Edwards-Teng pairs
(`edwards_teng_normalizer`, `edwards_teng_map`, `edwards_teng_direct`),
`preferred_form` (the form the `preferred_form` option selected for
presentation, 1 or 2, unavailable with the pair's reason), `rho_M0` (the
perturbation scale this frame was built with). Every piece is a `Determined`
carrying the frame's reason when the frame is unavailable.
"""
struct TransverseOptics4D
    eigenmodes::Eigenmodes4D
    frame::Determined{NormalModeFrame4D}
    closed_form::Determined{ClosedFormCheck4D}
    mais_ripken::Determined{MaisRipkenSet}
    edwards_teng_normalizer::Determined{EdwardsTengPair}
    edwards_teng_map::Determined{EdwardsTengPair}
    edwards_teng_direct::Determined{EdwardsTengPair}
    preferred_form::Determined{Int}
    rho_M0::Float64
end

"""
    PhysicalOptics

The quantities of a [`TwissDispersionResult`](@ref) transformed BACK to the
caller's coordinates by the stage 1 table (`_unscale_normalizer`,
`_unscale_projector`, `_unscale_covariance`, `_unscale_graph`,
`_unscale_crab_dispersion`, `_unscale_momentum_dispersion`,
`_unscale_longitudinal_factor`, `_unscale_edwards_teng_R`,
`_unscale_twiss`), each a `Determined` with the reason of the scaled
quantity it came from: `normalizer` (`U_4` or `U_6`), `tunes` (scaling
invariant, repeated for convenience), `beta`, `alpha`, `gamma` (`[mode,
plane]` arrays), `edwards_teng_R` (of the presented form), `graph` (`D =
[zeta, eta / h]`), `zeta`, `eta`, `h`, `projectors`, `covariances` (`P_j`,
`G_j` per mode), `covariance` (the matched `Sigma` when emittances were
given). Shapes: on 4x4 input and on a 6x6 map whose `U_6` is unavailable
while the transverse frame is unique (a coasting map: the frame of `M_rr`,
design return table) the transverse rows are the 4D frame's, in the
caller's transverse coordinates (the barred ones, `r - eta delta`, on a
coasting map): `normalizer` 4x4, `beta`/`alpha`/`gamma` 2x2, two 4x4
`projectors` and `covariances`, two `tunes`; on a 6x6 map with a unique
`U_6` they are 6x6, 3x3, three 6x6 and three. Residuals and tolerances are
NOT here: they stay in scaled coordinates in the result and its
diagnostics.
"""
struct PhysicalOptics
    normalizer::Determined{Matrix{Float64}}
    tunes::Vector{Float64}
    beta::Determined{Matrix{Float64}}
    alpha::Determined{Matrix{Float64}}
    gamma::Determined{Matrix{Float64}}
    edwards_teng_R::Determined{Matrix{Float64}}
    graph::Determined{Matrix{Float64}}
    zeta::Determined{Vector{Float64}}
    eta::Determined{Vector{Float64}}
    h::Determined{Float64}
    projectors::Determined{Vector{Matrix{Float64}}}
    covariances::Determined{Vector{Matrix{Float64}}}
    covariance::Determined{Matrix{Float64}}
end

const _ANALYSIS_INPUT_T = NamedTuple{(:form, :dimension, :provenance),
                                     Tuple{Symbol, Int, Union{Nothing,LinearizationProvenance}}}
const _DEFECT_T = NamedTuple{(:frobenius, :row_ratio, :row_residual, :row_tolerance), NTuple{4, Float64}}
const _ROUTE_DIAGNOSTIC_T = NamedTuple{(:route, :status, :normalized_residual, :raw_residual,
                                        :coefficient_condition, :iterations, :converged, :detail),
                                       Tuple{Symbol, Symbol, Float64, Float64, Float64, Int, Bool, String}}
const _LONGITUDINAL_SELECTION_T = NamedTuple{(:rule, :certified, :selected, :cluster, :weights, :tie, :tune_chords, :detail),
                                             Tuple{Symbol, Bool, Int, Int, Vector{Float64}, Bool, Union{Nothing,NTuple{2,Float64}}, String}}
const _EDWARDS_TENG_DIAGNOSTIC_T = NamedTuple{(:requested, :reported, :admissible, :area_weights, :route),
                                              Tuple{Union{Symbol,Int}, Int, NTuple{2,Bool}, NTuple{2,Float64}, Symbol}}
const _PROJECTION_DIAGNOSTIC_T = NamedTuple{(:h_report, :h_separation, :h_difference, :graph_singular_value,
                                             :canonical_area, :triple_consistency),
                                            NTuple{6, Float64}}

"""
    AnalysisDiagnostics

The diagnostics record of a [`TwissDispersionResult`](@ref), one field group
per bullet of theory Section 11.2, everything in SCALED coordinates:

  * `convention`, `reference_point`: the coordinate convention and the
    expansion point (the provenance's `point`, or zeros for a bare matrix).
  * `symplectic_defect`, `symplectic_rule`, `unit_circle_departure`,
    `rho_M0`, `rho_M1`: the defect tuple of stage 1 and the rule that judged
    it (`:row_ratio` or `:frobenius`), the spectrum's departure from the unit
    circle, the two perturbation scales.
  * `residuals`: every reported residual by name (`"frame reconstruction
    (I1)"`, `"frame symplecticity (E7)"`, `"separation off-diagonal (K5)"`,
    `"U_6 reconstruction"`, `"U_6 symplecticity"`, `"covariance closure"`,
    `"(K14) zz identity"`, ...) as `(name, value, tolerance)` triples; the
    acceptance tests of the verdict read exactly the `_VERDICT_RESIDUALS`
    names (the (K14) identity, the separation, the triple consistency and
    the primary route are reported with a tolerance but judged elsewhere).
  * `resolution`: the clusters' resolution receipt (chord, `rho_M1`, the
    inter-cluster chords, `forced` flags) as `(name, value)` pairs.
  * `longitudinal_selection`: rule, certified flag, selected eigenvalue
    index and cluster, the signed z-areas (the weights), the tie flag,
    `tune_chords` (for a tune `mu_s`: the chord `|lambda - exp(-i mu_s)|`
    of the nearest eigenvalue and of the runner-up outside its conjugate
    pair, the margin the acceptance read; `nothing` for the other rules).
  * `edwards_teng`: the requested and reported form, both admissibility
    flags and area weights, the route the presented pair came from.
  * `projection`: the two `h` values (`h_report` = (D11) `det U_ls` of the
    primary route, `h_separation` = the (D8) value the separation used),
    their difference, the graph's smallest singular value, the canonical
    area and the triple consistency.
  * `phase_validity`: the Mais-Ripken phase-validity flags per mode.
  * `routes`: one row per executed dispersion route: status, normalized and
    raw invariance residual, coefficient condition, iterations, `converged`
    (`false` for an iterative route that stopped short of its stop floor,
    which is `:not_invariant` whatever the (I1) floor says; `true` for the
    direct routes), detail.
"""
struct AnalysisDiagnostics
    convention::String
    reference_point::NTuple{6,Float64}
    symplectic_defect::_DEFECT_T
    symplectic_rule::Symbol
    unit_circle_departure::Float64
    rho_M0::Float64
    rho_M1::Float64
    residuals::Vector{Tuple{String,Float64,Float64}}
    resolution::Vector{Tuple{String,Float64}}
    longitudinal_selection::Determined{_LONGITUDINAL_SELECTION_T}
    edwards_teng::Determined{_EDWARDS_TENG_DIAGNOSTIC_T}
    projection::Determined{_PROJECTION_DIAGNOSTIC_T}
    phase_validity::Determined{NTuple{2,Bool}}
    routes::Vector{_ROUTE_DIAGNOSTIC_T}
end

"""
    TwissDispersionResult

The result of [`analyze`](@ref) with a [`TwissDispersionAnalysis`](@ref):
runtime representation (it may change shape between releases; the analysis
object and its schema are the stable surface). Fields:

  * `analysis`: the object that produced it. `input`: `(form, dimension,
    provenance)` with `form` in `(:matrix, :linearized)`.
  * `scaling`: the `ReciprocalScaling` record; `matrix` as given;
    `matrix_scaled = C M C^-1`. Every kernel field below is in SCALED
    coordinates; [`PhysicalOptics`](@ref) holds the back-transformed ones.
  * `symplectic_defect`: stage 1's tuple on the scaled matrix; `rho_M0`: the
    first perturbation scale (defect, roundoff, declared uncertainty,
    provenance uncertainty).
  * `closed_orbit`: the max-norm fixed-point residual read from a
    `LinearizedMap`'s provenance, unavailable `:not_requested` on a bare
    matrix (the reason vocabulary's member for "the input carries no such
    datum").
  * `coasting`: the stage 4a `CoastingStructure` (6x6 only; `nothing` on a
    4x4 map, where the notion does not exist).
  * `clusters`: the `ModeClusters` report of the scaled matrix (under an
    explicit partition, that partition).
  * `transverse`: the [`TransverseOptics4D`](@ref) bundle on the frame of
    the matrix (4x4), of `Mbar_beta` (6x6, unique separation) or of `M_rr`
    (coasting map); unavailable with the dispersion's or separation's
    reason when no transverse block could be formed.
  * `dispersion`, `separation`, `projected_optics`, `ohmi`,
    `covariance_6d`: the stage 4a reports (6x6 only; `nothing` on 4x4
    input); the `Determined` ones carry the reason that blocked them.
  * `covariance`: the matched covariance `Sigma` (scaled) when emittances
    were given, else unavailable `:not_requested`.
  * `physical`: the back-transformed quantities. `diagnostics`: see
    [`AnalysisDiagnostics`](@ref).
  * `configuration`: one `ConfigurationEntry` per option, built from the
    branch the run took; [`configuration_report`](@ref) returns it.
  * `status` in [`ANALYSIS_STATUSES`](@ref); `degradations` and `failures`
    name each limitation and each failed check.

`Union{Nothing, X}` marks "does not exist for this input dimension" (a 4x4
map has no dispersion), never "unknown"; unknown is always a `Determined`
with its reason.
"""
struct TwissDispersionResult <: AbstractAnalysisResult
    analysis::TwissDispersionAnalysis
    input::_ANALYSIS_INPUT_T
    scaling::ReciprocalScaling
    matrix::Matrix{Float64}
    matrix_scaled::Matrix{Float64}
    symplectic_defect::_DEFECT_T
    rho_M0::Float64
    closed_orbit::Determined{Float64}
    coasting::Union{Nothing,CoastingStructure}
    clusters::ModeClusters
    transverse::Determined{TransverseOptics4D}
    dispersion::Union{Nothing,DispersionRoutes}
    separation::Union{Nothing,Determined{CanonicalSeparation}}
    projected_optics::Union{Nothing,Determined{ProjectedOptics6D}}
    ohmi::Union{Nothing,Determined{OhmiFactorization}}
    covariance_6d::Union{Nothing,Determined{MatchedCovariance6D}}
    covariance::Determined{Matrix{Float64}}
    physical::PhysicalOptics
    diagnostics::AnalysisDiagnostics
    configuration::Vector{ConfigurationEntry}
    status::Symbol
    degradations::Vector{String}
    failures::Vector{String}
end

"""
    OpticsAnalysisError <: Exception

Thrown by [`analyze`](@ref) when the verdict is `:failed` and the analysis
has `strict = true`: a numerical check did not hold (the primary dispersion
route or the separation `:not_invariant`, a frame or normalizer residual
above its acceptance, a covariance closure above its tolerance). Carries the
FULL `result` so the caller can read every diagnostic, and `failures`, the
same strings as `result.failures`. `strict = false` returns the failed result
instead. Physically undetermined quantities are never failures: they are
`Determined` statuses with reasons (and, where they limit the result,
degradations).
"""
struct OpticsAnalysisError <: Exception
    result::TwissDispersionResult
    failures::Vector{String}
end

function Base.showerror(io::IO, e::OpticsAnalysisError)
    n = length(e.failures)
    print(io, "OpticsAnalysisError: ", n, n == 1 ? " check failed" : " checks failed")
    isempty(e.failures) || print(io, ": ", first(e.failures))
    n > 1 && print(io, " (and ", n - 1, " more in .failures)")
    print(io, "; the full result is in .result")
end

# ---------------------------------------------------------------------------
# Accessors and the configuration report.

"""
    normal_mode(result::TwissDispersionResult, j::Integer) -> NormalMode

The `j`-th labelled normal mode of the result, in scaled coordinates: for a
4x4 map (or a 6x6 map whose transverse frame is unique) modes 1 and 2 come
from the `NormalModeFrame4D` of `result.transverse`; for a 6x6 map with a
unique `projected_optics` the three modes come from `ProjectedOptics6D`
(vectors, tunes, `beta`/`alpha`/`gamma`/`signed_areas` rows, projectors,
covariances), mode 3 being the synchrotron mode. Throws
`UndeterminedQuantityError` with the reason when the frame (or the 6D optics
for `j = 3`) is not unique, and `ArgumentError` for an index outside the
mode list.
"""
function normal_mode(result::TwissDispersionResult, j::Integer)
    d = result.input.dimension
    nmodes = d == 4 ? 2 : 3
    1 <= j <= nmodes || throw(ArgumentError("normal_mode: a $(d)x$(d) map has modes 1:$(nmodes), got $(j)"))
    if d == 6 && is_determined(result.projected_optics)
        o = determined_value(result.projected_optics)
        u = o.vectors[j]; mu = o.tunes[j]; rho = exp(-im * mu)
        res = _invariance_residual(result.matrix_scaled, u, rho)
        return NormalMode(Int(j), rho, mu, u, (real.(u), -imag.(u)), o.projectors[j], o.covariances[j],
                          Vector{Float64}(o.beta[j, :]), Vector{Float64}(o.alpha[j, :]), Vector{Float64}(o.gamma[j, :]),
                          Vector{Float64}(o.signed_areas[j, :]), (normalized=res[1], raw=res[2]))
    end
    if d == 6 && j == 3
        src = result.projected_optics
        throw(UndeterminedQuantityError(src.status, src.reason, "normal_mode(result, 3): the synchrotron mode needs a unique 6D normalizer: " * src.detail))
    end
    tr = result.transverse
    is_determined(tr) || throw(UndeterminedQuantityError(tr.status, tr.reason, "normal_mode(result, $(j)): no transverse frame: " * tr.detail))
    fr = determined_value(tr).frame
    is_determined(fr) || throw(UndeterminedQuantityError(fr.status, fr.reason, "normal_mode(result, $(j)): the 4D frame is not unique: " * fr.detail))
    f = determined_value(fr)
    u = f.vectors[j]
    return NormalMode(Int(j), f.eigenvalues[j], f.tunes[j], u, (real.(u), -imag.(u)), f.projectors[j], f.covariances[j],
                      Vector{Float64}(f.beta[j, :]), Vector{Float64}(f.alpha[j, :]), Vector{Float64}(f.gamma[j, :]),
                      Vector{Float64}(f.signed_areas[j, :]), f.eigenvector_residuals[j])
end

"""
    matched_covariance(result::TwissDispersionResult, emittances) -> Matrix{Float64}

The matched covariance of the analysed map in the CALLER'S coordinates for
rms mode emittances `(eps_1, eps_2)` (4x4) or `(eps_1, eps_2, eps_s)` (6x6):
stage 2's (M9) on the unique 4D normalizer, or stage 4a's (K10)
`_matched_covariance_6d` on the unique `ProjectedOptics6D` (with the barred
`G_j` of the transverse frame and the separation's `eta`), then
`_unscale_covariance`. Throws `UndeterminedQuantityError` with the reason
when the normalizer is not unique, `ArgumentError` for an emittance tuple of
the wrong length or with a negative entry.
"""
function matched_covariance(result::TwissDispersionResult, emittances)
    d = result.input.dimension
    n = d == 4 ? 2 : 3
    (emittances isa Tuple && length(emittances) == n && all(e -> e isa Real, emittances)) || throw(ArgumentError(
        "matched_covariance: a $(d)x$(d) map takes $(n) rms mode emittances, got $(emittances)"))
    all(e -> isfinite(e) && e >= 0, emittances) || throw(ArgumentError(
        "matched_covariance: rms mode emittances must be finite and non-negative, got $(emittances)"))
    em = Tuple(Float64.(emittances))
    tr = result.transverse
    is_determined(tr) || throw(UndeterminedQuantityError(tr.status, tr.reason, "matched_covariance: no transverse frame: " * tr.detail))
    fr = determined_value(tr).frame
    is_determined(fr) || throw(UndeterminedQuantityError(fr.status, fr.reason, "matched_covariance: the 4D normalizer is not unique: " * fr.detail))
    f = determined_value(fr)
    if d == 4
        Sigma = _matched_covariance_4d(f.normalizer, em)
    else
        po = result.projected_optics
        is_determined(po) || throw(UndeterminedQuantityError(po.status, po.reason, "matched_covariance: the 6D normalizer is not unique: " * po.detail))
        sep = determined_value(result.separation)
        Sigma = _matched_covariance_6d(result.matrix_scaled, determined_value(po), em, f.covariances, sep.eta).sigma
    end
    return _unscale_covariance(result.scaling, Sigma)
end

"""
    configuration_report(result::TwissDispersionResult) -> Vector{ConfigurationEntry}
    configuration_report(analysis::TwissDispersionAnalysis) -> Vector{ConfigurationEntry}

The per-option report of the run that produced `result`, one
`ConfigurationEntry` per option of [`analysis_option_schema`](@ref) with a
status from `CONFIGURATION_STATUSES`: `:resolved` for an option the run
read; `:inactive_dependency` with the reason for an option the branch taken
never read (design "Certification": `closed_orbit`, `closed_orbit_atol` on a
bare matrix; `longitudinal_mode`, `dispersion_routes` on 4x4 input and on a
coasting map; `newton_max_iterations` unless `:newton` executed;
`preferred_form` when the transverse optics are unavailable; `emittances`
when `nothing`). AMENDMENT to the design's table (stage 4b record):
`resolution_chord` stays `:resolved` under an explicit partition because the
stage 2/3 frame construction re-clusters at that chord. The report is built
by the pipeline and stored in `result.configuration`; this accessor returns
it. On an analysis OBJECT alone every entry is `:unresolved` with the reason
"depends on the input; analyze first", so the generic report machinery has a
method for the type.
"""
configuration_report(result::TwissDispersionResult) = result.configuration

function configuration_report(analysis::TwissDispersionAnalysis)
    return [ConfigurationEntry(name, getproperty(analysis, name), getproperty(analysis, name), :unresolved,
                               "depends on the input; analyze first", meta.consumer)
            for (name, meta) in pairs(analysis_option_schema(analysis))]
end

# ---------------------------------------------------------------------------
# The pipeline (design "Pipeline" steps 1-11; dossier F3). Every step is a
# small function so each receipt sits in the branch that READ its option.
# All of them work on the SCALED matrix `Ms`; `_analysis_back_transform`
# undoes the scaling row by row at the end.

"""
    _analysis_scaling(analysis, M) -> (rec::ReciprocalScaling, Ms::Matrix{Float64})

Step 1-2: the reciprocal scaling record from the `scaling` option
(`_reciprocal_scaling(M, mode)`, an explicit tuple becoming `:explicit`
with those factors; an explicit tuple of the wrong length for `size(M)` is
an ArgumentError) and the scaled matrix `_scale_map`. Receipt
`:analysis_scaling (scaling=<the option>, mode, factors)`.
"""
function _analysis_scaling(analysis::TwissDispersionAnalysis, M::AbstractMatrix{<:Real})
    d = size(M, 1)
    sc = analysis.scaling
    if sc isa Tuple
        length(sc) == div(d, 2) || throw(ArgumentError(
            "analyze: an explicit scaling tuple needs $(div(d, 2)) factors for a $(d)x$(d) matrix, got $(length(sc))"))
        rec = ReciprocalScaling(:explicit, collect(Float64, sc), d)
    else
        rec = _reciprocal_scaling(M, sc)
    end
    Ms = Matrix{Float64}(_scale_map(rec, M))
    _record_execution!(:analysis_scaling, CPUThreadsBackend,
                       (scaling=sc, mode=rec.mode, factors=Tuple(rec.factors)))
    return rec, Ms
end

"""
    _analysis_symplectic_check(analysis, Ms, input) -> (defect::_DEFECT_T, rule::Symbol, action::Symbol, degradation)

Step 3: `_symplectic_defect(Ms)`; the rule is `:row_ratio` (`row_ratio <=
1`) when `symplectic_rtol === nothing` and `:frobenius` (`frobenius <=
rtol`) otherwise; a finite-difference provenance with `symplectic_rtol ===
nothing` is an ArgumentError naming the option. Above the tolerance:
`nonsymplectic === :error` throws an ArgumentError naming the defect, the
rule and the tolerance; `:flag` returns `action = :flagged` and the
degradation string. Receipt `:analysis_symplectic_check (symplectic_rtol,
nonsymplectic, rule, defect, action)`.
"""
function _analysis_symplectic_check(analysis::TwissDispersionAnalysis, Ms::AbstractMatrix{<:Real}, input::_ANALYSIS_INPUT_T)
    defect = _DEFECT_T(_symplectic_defect(Ms))
    rtol = analysis.symplectic_rtol
    prov = input.provenance
    if rtol === nothing && prov !== nothing && prov.method isa FiniteDifferenceLinearization
        throw(ArgumentError("analyze: a finite-difference LinearizedMap carries a truncation error that is not roundoff; " *
                            "pass an explicit symplectic_rtol to TwissDispersionAnalysis (symplectic_rtol = nothing was given)"))
    end
    if rtol === nothing
        rule = :row_ratio
        accepted = defect.row_ratio <= 1
        tolerance = 1.0
        measured = defect.row_ratio
    else
        rule = :frobenius
        accepted = defect.frobenius <= rtol
        tolerance = rtol
        measured = defect.frobenius
    end
    degradation = nothing
    if accepted
        action = :accepted
    elseif analysis.nonsymplectic === :error
        throw(ArgumentError("analyze: the scaled matrix is not symplectic: rule :$(rule) measured $(measured) above the tolerance " *
                            "$(tolerance) (Frobenius defect $(defect.frobenius), row ratio $(defect.row_ratio)); " *
                            "pass nonsymplectic = :flag to continue with a :degraded result"))
    else
        action = :flagged
        degradation = "nonsymplectic = :flag: the symplectic defect (rule :$(rule), measured $(measured)) exceeds the tolerance $(tolerance); the matrix was analysed as given"
    end
    _record_execution!(:analysis_symplectic_check, CPUThreadsBackend,
                       (symplectic_rtol=rtol, nonsymplectic=analysis.nonsymplectic, rule=rule, defect=defect, action=action))
    return defect, rule, action, degradation
end

"""
    _analysis_closed_orbit(analysis, input, rec) -> (residual::Determined{Float64}, degradation)

Step 5: on a `:linearized` input the max norm of the provenance's
`fixed_point_residual` in SCALED coordinates (`C r`, design "Input boundary"
item 4; the receipt and `result.closed_orbit` carry that scaled norm)
against `closed_orbit_atol` (or the default `_CLOSED_ORBIT_ATOL_MULTIPLIER *
eps * max(1, maximum(abs, C point))`, the point scaled the same way);
`:require` throws an ArgumentError above it, `:warn` emits ONE warning
(`@warn ... maxlog=1 _id=:twiss_dispersion_closed_orbit`) and returns the
degradation string. Receipt `:analysis_closed_orbit (closed_orbit,
closed_orbit_atol, residual, action)` ONLY on a linearized input; on a bare
matrix NO receipt is issued and the residual is unavailable
`:not_requested` (the probe asserts the receipt's absence together with the
report's `:inactive_dependency`).
"""
function _analysis_closed_orbit(analysis::TwissDispersionAnalysis, input::_ANALYSIS_INPUT_T, rec::ReciprocalScaling)
    input.form === :linearized || return Determined{Float64}(:not_requested,
        "a bare matrix carries no closed-orbit information; the closed_orbit options are inactive"), nothing
    prov = input.provenance
    C = _scaling_matrix(rec)
    residual = maximum(abs, C * collect(Float64, prov.fixed_point_residual))
    atol = analysis.closed_orbit_atol
    if atol === nothing
        atol = _CLOSED_ORBIT_ATOL_MULTIPLIER * eps(Float64) * max(1.0, maximum(abs, C * collect(Float64, prov.point)))
    end
    degradation = nothing
    if residual <= atol
        action = :accepted
    elseif analysis.closed_orbit === :require
        throw(ArgumentError("analyze: the expansion point $(prov.point) is not a fixed point of the map: " *
                            "max-norm residual $(residual) (scaled coordinates) above closed_orbit_atol $(atol); pass closed_orbit = :warn " *
                            "to continue with a :degraded result or linearize at the closed orbit"))
    else
        action = :warned
        @warn "analyze: the expansion point is not a fixed point of the map (max-norm residual $(residual) above closed_orbit_atol $(atol)); the result is :degraded" maxlog=1 _id=:twiss_dispersion_closed_orbit
        degradation = "closed_orbit = :warn: the fixed-point residual $(residual) exceeds closed_orbit_atol $(atol); the linearization is not about a closed orbit"
    end
    _record_execution!(:analysis_closed_orbit, CPUThreadsBackend,
                       (closed_orbit=analysis.closed_orbit, closed_orbit_atol=analysis.closed_orbit_atol,
                        residual=residual, action=action))
    return Determined(residual), degradation
end

"""
    _analysis_clusters(analysis, Ms, rho_M0) -> ModeClusters

Step 7: `_mode_clusters(Ms; rho_M0, resolution_chord, partition)` with the
partition from `clusters` unless `:auto`. Receipt
`:analysis_cluster_resolution (resolution_chord, map_uncertainty, clusters,
rho_M0, rho_M1, forced)` where `clusters` is the value the consumer READ
(`:auto`, or the explicit partition itself; dossier F5. AMENDMENT of F3
step 7, which wrote a `:auto | :explicit` marker: a marker cannot show an
ignored partition to the effectiveness contract, stage 4b repo review).
"""
function _analysis_clusters(analysis::TwissDispersionAnalysis, Ms::AbstractMatrix{<:Real}, rho_M0::Real)
    partition = analysis.clusters === :auto ? nothing : analysis.clusters
    clusters = _mode_clusters(Ms; rho_M0=rho_M0, resolution_chord=analysis.resolution_chord, partition=partition)
    forced = any(c.forced for c in clusters.clusters)
    _record_execution!(:analysis_cluster_resolution, CPUThreadsBackend,
                       (resolution_chord=analysis.resolution_chord, map_uncertainty=analysis.map_uncertainty,
                        clusters=analysis.clusters, rho_M0=Float64(rho_M0),
                        rho_M1=clusters.rho_M1, forced=forced))
    return clusters
end

"""
    _analysis_transverse(analysis, M4, clusters, rho_M0; rho_M1) -> TransverseOptics4D

Step 8 (4x4 path) and the transverse half of step 8 (6x6 path, called on
`Mbar_beta` or `M_rr` through `_transverse_optics_6d`): the bundle of
[`TransverseOptics4D`](@ref) with `min_trace_gap = _TRACE_GAP_MULTIPLIER *
rho_M1 * max(1, ||M4||_F)` and `stability_atol = _STABILITY_ATOL_MULTIPLIER *
rho_M1`. On 4x4 input under an explicit partition the frame's availability
is FURTHER restricted by `_frame_availability(clusters)` of the explicit
report (the user's partition can block a frame, never form one). The
`preferred_form` selection is `_analysis_preferred_form`.
"""
function _analysis_transverse(analysis::TwissDispersionAnalysis, M4::AbstractMatrix{<:Real}, clusters::ModeClusters, rho_M0::Real; rho_M1::Real)
    min_trace_gap = _TRACE_GAP_MULTIPLIER * rho_M1 * max(1.0, norm(M4))
    stability_atol = _STABILITY_ATOL_MULTIPLIER * rho_M1
    e4 = _eigenmodes_4d(M4; rho_M0=rho_M0, resolution_chord=analysis.resolution_chord)
    fr = e4.frame
    if is_determined(fr) && clusters.partition_source !== :auto
        block = _frame_availability(clusters)
        block === nothing || (fr = Determined{NormalModeFrame4D}(block[1], "explicit partition blocks the frame: " * block[2]))
    end
    if is_determined(fr)
        f = determined_value(fr)
        cf = _closed_form_check_4d(f; min_trace_gap=min_trace_gap, stability_atol=stability_atol)
        mr = Determined(_mais_ripken(f))
        etn = Determined(_edwards_teng_from_normalizer(f))
        etm = Determined(_edwards_teng_from_map(f; min_trace_gap=min_trace_gap))
        etd = Determined(_edwards_teng_direct(f))
    else
        cf = Determined{ClosedFormCheck4D}(fr.reason, fr.detail)
        mr = Determined{MaisRipkenSet}(fr.reason, fr.detail)
        etn = Determined{EdwardsTengPair}(fr.reason, fr.detail)
        etm = Determined{EdwardsTengPair}(fr.reason, fr.detail)
        etd = Determined{EdwardsTengPair}(fr.reason, fr.detail)
    end
    form, _ = _analysis_preferred_form(analysis, etn)
    return TransverseOptics4D(e4, fr, cf, mr, etn, etm, etd, form, Float64(rho_M0))
end

# The same bundle from a `_transverse_optics_6d` NamedTuple (6x6 path): the
# stage 4a kernel already built every piece on `Mbar_beta` (or `M_rr`); only
# the presented form is selected here.
function _analysis_transverse_from_6d(analysis::TwissDispersionAnalysis, t)
    form, _ = _analysis_preferred_form(analysis, t.edwards_teng_normalizer)
    return TransverseOptics4D(t.eigenmodes, t.frame, t.closed_form, t.mais_ripken, t.edwards_teng_normalizer,
                              t.edwards_teng_map, t.edwards_teng_direct, form, t.rho_M0_bar)
end

"""
    _analysis_preferred_form(analysis, pair::Determined{EdwardsTengPair}) -> (form::Determined{Int}, diagnostic::Determined{_EDWARDS_TENG_DIAGNOSTIC_T})

Step 9: both forms are in the pair; `:auto` presents the admissible form
with the larger `area_weight` (ties to form 1), an Int presents that form
(unavailable `:form_inadmissible` with the form's detail when it is not
admissible). Receipt `:analysis_edwards_teng (preferred_form, reported,
admissible)` in the branch that read the option (none when the pair is
unavailable: the report then says `:inactive_dependency`).
"""
function _analysis_preferred_form(analysis::TwissDispersionAnalysis, pair::Determined{EdwardsTengPair})
    form, diagnostic = _preferred_form_selection(analysis, pair)
    if is_determined(pair)
        p = determined_value(pair)
        _record_execution!(:analysis_edwards_teng, CPUThreadsBackend,
                           (preferred_form=analysis.preferred_form,
                            reported=(is_determined(form) ? determined_value(form) : 0),
                            admissible=(p.form1.admissible, p.form2.admissible)))
    end
    return form, diagnostic
end

# The selection without the receipt (the driver re-reads the diagnostic from
# the pair the transverse bundle presented, without issuing a second receipt).
function _preferred_form_selection(analysis::TwissDispersionAnalysis, pair::Determined{EdwardsTengPair})
    if !is_determined(pair)
        return Determined{Int}(pair.reason, pair.detail), Determined{_EDWARDS_TENG_DIAGNOSTIC_T}(pair.reason, pair.detail)
    end
    p = determined_value(pair)
    forms = (p.form1, p.form2)
    admissible = (p.form1.admissible, p.form2.admissible)
    weights = (p.form1.area_weight, p.form2.area_weight)
    requested = analysis.preferred_form
    if requested === :auto
        if admissible[1] && admissible[2]
            selected = weights[2] > weights[1] ? 2 : 1
        elseif admissible[1] || admissible[2]
            selected = admissible[1] ? 1 : 2
        else
            selected = 0
        end
        form = selected == 0 ? Determined{Int}(:form_inadmissible,
                   "neither Edwards-Teng form is admissible (area weights $(weights)); route :$(p.route)") : Determined(selected)
    else
        selected = Int(requested)
        f = forms[selected]
        form = f.admissible ? Determined(selected) : Determined{Int}(:form_inadmissible,
                   "Edwards-Teng form $(selected) is not admissible (area weight $(f.area_weight)); " *
                   (is_determined(f.R) ? "" : f.R.detail))
    end
    reported = is_determined(form) ? determined_value(form) : 0
    diagnostic = Determined(_EDWARDS_TENG_DIAGNOSTIC_T((requested, reported, admissible, weights, p.route)))
    return form, diagnostic
end

"""
    _analysis_6d(analysis, Ms, clusters; rho_M1) -> NamedTuple

Step 6 and 8 (6x6 path): `_coasting_structure` is inside
`_dispersion_routes`; the longitudinal selection from `longitudinal_mode`
(`:max_signed_z_area` -> `longitudinal=nothing`, an Int -> that index, a
tune `mu_s` -> the index of the eigenvalue nearest `exp(-i mu_s)` among the
canonical eigenvalues of `clusters`, accepted only when that chord is at
most half the chord to the runner-up outside the pair or at most
`_TUNE_CHORD_FLOOR_MULTIPLIER * rho_M1` (else an ArgumentError naming the
tunes of the map; the chords are kept in the selection diagnostic's
`tune_chords`); certified iff not the heuristic). The kernel
maps an index and its conjugate partner to the same ORIENTED mode, so the
receipt's `selected` and `dispersion.longitudinal` carry the oriented
canonical index of the pair, not necessarily the nearest index itself;
`_dispersion_routes(Ms, clusters; longitudinal, routes=dispersion_routes,
newton_max_iterations)`; receipts `:analysis_labels (longitudinal_mode,
rule, certified, selected, weights)`, `:analysis_dispersion_routes
(dispersion_routes, executed)` and, when `:newton` executed,
`:analysis_newton (newton_max_iterations, used)`. Then, when the primary
triple is unique (including the coasting triple), `_canonical_separation(Ms,
routes)` and `_transverse_optics_6d(sep; rho_M1, resolution_chord,
min_trace_gap, stability_atol)`, and the Ohmi factor
`_ohmi_factorization(Ms, sep.zeta, sep.eta, sep.h, sep.transformation,
graph)` when `h > 0`. Returns `(dispersion, separation, transverse_bundle,
projected_optics, ohmi, longitudinal_selection, degradations::Vector{String})`
where the degradations include: a label tie; an uncertified heuristic
selection; Newton or fixed-point routes `:not_invariant` with "another
branch" while the primary is unique; an unavailable primary dispersion for
a physical reason (`:singular_longitudinal_projection`, an ambiguity set
under `:cluster_unresolved`); NOT `:coasting_structure` and NOT the
longitudinal `:unit_eigenvalue` of a coasting map.
"""
function _analysis_6d(analysis::TwissDispersionAnalysis, Ms::AbstractMatrix{<:Real}, clusters::ModeClusters; rho_M1::Real)
    lm = analysis.longitudinal_mode
    tune_chords = nothing
    if lm isa Symbol
        longitudinal = nothing; certified = false
    elseif lm isa Int
        lm <= length(clusters.eigenvalues) || throw(ArgumentError(
            "analyze: longitudinal_mode = $(lm) is not a canonical eigenvalue index of a 6x6 map (1:$(length(clusters.eigenvalues)))"))
        longitudinal = lm; certified = true
    else
        # A tune identifies a mode only when it is unambiguously nearest to one
        # eigenvalue pair: the chord to the nearest eigenvalue must be at most
        # half the chord to the runner-up outside that pair (the conjugate
        # partner names the same oriented mode and does not compete).
        target = exp(-im * lm)
        chords = [abs(lambda - target) for lambda in clusters.eigenvalues]
        # `nearest` is assigned once: the generator below captures it (a closure over the branch-assigned
        # `longitudinal` would be a Core.Box, the suite's lowered-code sweep)
        nearest = argmin(chords)
        partner = clusters.conjugate_partner[nearest]
        runner_up = minimum(chords[k] for k in eachindex(chords) if k != nearest && k != partner)
        tune_chords = (chords[nearest], runner_up)
        if chords[nearest] > max(0.5 * runner_up, _TUNE_CHORD_FLOOR_MULTIPLIER * rho_M1)
            tunes = sort(unique(round.(abs.(angle.(clusters.eigenvalues)); digits=12)))
            throw(ArgumentError("analyze: longitudinal_mode = $(lm) (a synchrotron tune) identifies no mode: the nearest eigenvalue " *
                                "(tune $(abs(angle(clusters.eigenvalues[nearest])))) is at chord $(chords[nearest]) from exp(-i mu_s), " *
                                "above half the chord $(runner_up) to the runner-up; the tunes of the map are $(tunes) radians per turn; " *
                                "pass one of them or the canonical eigenvalue index"))
        end
        longitudinal = nearest
        certified = true
    end
    routes = _dispersion_routes(Ms, clusters; longitudinal=longitudinal, routes=analysis.dispersion_routes,
                                newton_max_iterations=analysis.newton_max_iterations)
    coasting = routes.coasting.holds
    degradations = String[]
    labels = routes.labels
    weights = is_determined(labels) ? Vector{Float64}(determined_value(labels).signed_areas[:, 3]) : Float64[]
    tie = is_determined(labels) && determined_value(labels).tie
    if coasting
        selection = Determined{_LONGITUDINAL_SELECTION_T}(:coasting_structure,
            "the map has the coasting structure (unit longitudinal block): no synchrotron mode to select")
    else
        rule = is_determined(labels) ? determined_value(labels).rule : (longitudinal === nothing ? :max_signed_z_area : :explicit)
        detail = if routes.longitudinal == 0
            "no longitudinal mode could be selected"
        elseif certified
            "longitudinal_mode = $(lm): certified selection of canonical eigenvalue $(routes.longitudinal)"
        else
            zarea_text = isempty(weights) ? "the signed z-areas are unavailable: $(labels.reason), $(labels.detail)" :
                "signed z-area $(weights[routes.longitudinal_cluster == 0 ? 1 : min(routes.longitudinal_cluster, length(weights))])"
            "the :max_signed_z_area heuristic selected canonical eigenvalue $(routes.longitudinal) (cluster $(routes.longitudinal_cluster); $(zarea_text)); by (K12) kappa_sz = h, so the rule is uncertified for h < 1/2: pass longitudinal_mode = <index> or the synchrotron tune mu_s to certify it"
        end
        selection = Determined(_LONGITUDINAL_SELECTION_T((rule, certified, routes.longitudinal, routes.longitudinal_cluster,
                                                          weights, tie, tune_chords, detail)))
        _record_execution!(:analysis_labels, CPUThreadsBackend,
                           (longitudinal_mode=lm, rule=rule, certified=certified, selected=routes.longitudinal, weights=weights))
        # a tie limits the HEURISTIC selection; a certified index or tune is not chosen by the z-areas (the flag stays in the diagnostics)
        (tie && !certified) && push!(degradations, "label tie: the signed z-areas of two modes agree within the tie tolerance; the heuristic longitudinal selection is not unique")
        # nothing to certify when no mode was selected: the unavailable dispersion carries that reason below
        (certified || routes.longitudinal == 0) || push!(degradations, "uncertified longitudinal selection: " * detail)
    end
    # On a coasting map the route options are inactive (dossier F6): every
    # route is `:coasting_structure` without reading the selection, no receipt.
    executed = coasting ? () : Tuple(r.route for r in routes.routes if r.status !== :route_not_selected)
    coasting || _record_execution!(:analysis_dispersion_routes, CPUThreadsBackend,
                                   (dispersion_routes=analysis.dispersion_routes, executed=executed))
    newton_executed = :newton in executed
    if newton_executed
        nr = routes.routes[findfirst(r -> r.route === :newton, routes.routes)]
        _record_execution!(:analysis_newton, CPUThreadsBackend, (newton_max_iterations=analysis.newton_max_iterations, used=nr.iterations))
    end
    triple = (routes.zeta, routes.eta, routes.h)
    if all(is_determined, triple)
        sep = _canonical_separation(Ms, routes)
        M4 = sep.transverse_map
        t6 = _transverse_optics_6d(sep; rho_M1=rho_M1, resolution_chord=analysis.resolution_chord,
                                   min_trace_gap=_TRACE_GAP_MULTIPLIER * rho_M1 * max(1.0, norm(M4)),
                                   stability_atol=_STABILITY_ATOL_MULTIPLIER * rho_M1)
        transverse = Determined(_analysis_transverse_from_6d(analysis, t6))
        separation = Determined(sep)
        projected = t6.optics
        graph = is_determined(routes.graph) ? determined_value(routes.graph) : hcat(sep.zeta, sep.eta ./ sep.h)
        ohmi = _ohmi_factorization(Ms, sep.zeta, sep.eta, sep.h, sep.transformation, graph)
        for r in routes.routes
            if r.route in (:newton, :fixed_point) && r.status === :not_invariant && occursin("another branch", r.detail)
                push!(degradations, "route :$(r.route) converged to another invariant plane (not the primary): $(r.detail)")
            end
        end
    else
        blocked = triple[findfirst(t -> !is_determined(t), triple)]
        reason = blocked.reason; detail = blocked.detail
        transverse = Determined{TransverseOptics4D}(reason, detail)
        separation = Determined{CanonicalSeparation}(reason, detail)
        projected = Determined{ProjectedOptics6D}(reason, detail)
        ohmi = Determined{OhmiFactorization}(reason, detail)
        if reason in (:singular_longitudinal_projection, :graph_isotropic, :cluster_unresolved, :indefinite_cluster,
                      :unresolved_defective, :unstable_spectrum, :unit_eigenvalue, :zero_projection)
            push!(degradations, "primary dispersion unavailable (:$(reason)): $(detail)")
        end
    end
    return (dispersion=routes, separation=separation, transverse=transverse, projected_optics=projected, ohmi=ohmi,
            longitudinal_selection=selection, degradations=degradations, coasting=coasting, newton_executed=newton_executed)
end

"""
    _analysis_covariance(analysis, Ms, transverse, projected_optics, separation) -> (covariance::Determined{Matrix{Float64}}, covariance_6d, closure_residual)

Step 10: when `emittances !== nothing`, stage 2's `_matched_covariance_4d`
on the unique 4D normalizer (4x4 input; a 3-tuple is an ArgumentError) or
stage 4a's `_matched_covariance_6d(Ms, optics, emittances, Gbar, eta)` on
the unique `ProjectedOptics6D` (6x6 input; a 2-tuple is an ArgumentError),
else unavailable `:not_requested`. Receipt `:analysis_covariance
(emittances,)` in the executing branch only. The third element (`nothing`
when no covariance was built) is the NamedTuple `(closure, k14, k14_scale)`:
`closure` is the RAW closure residual `||Ms Sigma Ms' - Sigma||_F` the
verdict judges against `c rho_M1 cond(U) max(1, ||Sigma||)` (both
dimensions, one normalization); `k14` is the theory (K14) identity
`max_j |(G_j)_zz - eta' S_4 Gbar_j S_4' eta|` of the betatron modes (6D;
`nothing` on 4x4 input), reported and NOT judged, with `k14_scale = max(1,
max_j |(G_j)_zz|)` the size of the quantities compared. `covariance_6d` is
the `Determined{MatchedCovariance6D}` of the 6D branch or `nothing`.
"""
function _analysis_covariance(analysis::TwissDispersionAnalysis, Ms::AbstractMatrix{<:Real}, transverse, projected_optics, separation)
    em = analysis.emittances
    d = size(Ms, 1)
    cov6 = d == 6 ? Determined{MatchedCovariance6D}(:not_requested, "no emittances were given") : nothing
    if em === nothing
        return Determined{Matrix{Float64}}(:not_requested, "no emittances were given; pass emittances = (eps_1, eps_2[, eps_s])"), cov6, nothing
    end
    if d == 4
        length(em) == 2 || throw(ArgumentError("analyze: a 4x4 map takes two rms emittances (eps_1, eps_2), got $(em)"))
        if !(is_determined(transverse) && is_determined(determined_value(transverse).frame))
            src = is_determined(transverse) ? determined_value(transverse).frame : transverse
            _record_execution!(:analysis_covariance, CPUThreadsBackend, (emittances=em,))
            return Determined{Matrix{Float64}}(src.reason, "no unique 4D normalizer: " * src.detail), nothing, nothing
        end
        U4 = determined_value(determined_value(transverse).frame).normalizer
        Sigma = _matched_covariance_4d(U4, em)
        residual = norm(Ms * Sigma * transpose(Ms) - Sigma)
        _record_execution!(:analysis_covariance, CPUThreadsBackend, (emittances=em,))
        return Determined(Sigma), nothing, (closure=residual, k14=nothing, k14_scale=1.0)
    end
    length(em) == 3 || throw(ArgumentError("analyze: a 6x6 map takes three rms emittances (eps_1, eps_2, eps_s), got $(em)"))
    _record_execution!(:analysis_covariance, CPUThreadsBackend, (emittances=em,))
    if !(is_determined(projected_optics) && is_determined(separation) && is_determined(transverse) &&
         is_determined(determined_value(transverse).frame))
        src = !is_determined(projected_optics) ? projected_optics : (!is_determined(separation) ? separation : transverse)
        return Determined{Matrix{Float64}}(src.reason, "no unique 6D normalizer: " * src.detail),
               Determined{MatchedCovariance6D}(src.reason, src.detail), nothing
    end
    optics = determined_value(projected_optics)
    frame = determined_value(determined_value(transverse).frame)
    sep = determined_value(separation)
    mc = _matched_covariance_6d(Ms, optics, em, frame.covariances, sep.eta)
    k14_scale = max(1.0, maximum(abs(optics.covariances[j][5, 5]) for j in 1:2))
    return Determined(mc.sigma), Determined(mc), (closure=mc.closure_residual, k14=mc.k14_residual, k14_scale=k14_scale)
end

"""
    _analysis_back_transform(rec, transverse, dispersion, separation, projected_optics, form, covariance) -> PhysicalOptics

Step 11: the stage 1 `_unscale_*` table row by row (design "Input
boundary"): `_unscale_normalizer` (U_4 or U_6), `_unscale_twiss` per mode
and plane, `_unscale_edwards_teng_R` of the presented form,
`_unscale_graph`, `_unscale_crab_dispersion`,
`_unscale_momentum_dispersion`, `_unscale_longitudinal_factor`,
`_unscale_projector`, `_unscale_covariance` (G_j and Sigma). Every output
`Determined` carries the reason of its scaled source.
"""
function _analysis_back_transform(rec::ReciprocalScaling, transverse, dispersion, separation, projected_optics, form, covariance)
    d = rec.dimension
    unavailable(T, src) = Determined{T}(src.reason, src.detail)
    unscale_twiss(beta, alpha, gamma) = begin
        nm, np = size(beta)
        b = similar(beta); a = similar(alpha); g = similar(gamma)
        for j in 1:nm, p in 1:np
            b[j, p], a[j, p], g[j, p] = _unscale_twiss(rec, p, beta[j, p], alpha[j, p], gamma[j, p])
        end
        (Determined(b), Determined(a), Determined(g))
    end
    frame = is_determined(transverse) ? determined_value(transverse).frame : Determined{NormalModeFrame4D}(transverse.reason, transverse.detail)
    if d == 4
        if is_determined(frame)
            f = determined_value(frame)
            normalizer = Determined(_unscale_normalizer(rec, f.normalizer))
            tunes = collect(Float64, f.tunes)
            beta, alpha, gamma = unscale_twiss(f.beta, f.alpha, f.gamma)
            projectors = Determined([_unscale_projector(rec, P) for P in f.projectors])
            covariances = Determined([_unscale_covariance(rec, G) for G in f.covariances])
        else
            normalizer = unavailable(Matrix{Float64}, frame); tunes = Float64[]
            beta = alpha = gamma = unavailable(Matrix{Float64}, frame)
            projectors = covariances = unavailable(Vector{Matrix{Float64}}, frame)
        end
        graph = Determined{Matrix{Float64}}(:not_requested, "a 4x4 map has no longitudinal graph")
        zeta = eta = Determined{Vector{Float64}}(:not_requested, "a 4x4 map has no dispersion")
        h = Determined{Float64}(:not_requested, "a 4x4 map has no longitudinal factor")
    else
        if is_determined(projected_optics)
            o = determined_value(projected_optics)
            normalizer = Determined(_unscale_normalizer(rec, o.normalizer))
            tunes = collect(Float64, o.tunes)
            beta, alpha, gamma = unscale_twiss(o.beta, o.alpha, o.gamma)
            projectors = Determined([_unscale_projector(rec, P) for P in o.projectors])
            covariances = Determined([_unscale_covariance(rec, G) for G in o.covariances])
        elseif is_determined(frame)
            # Design return table, "Coasting map: ... the transverse optics of M_rr": no U_6 exists (the
            # longitudinal block has a unit eigenvalue), but the 4D frame of the separated transverse
            # block is unique, so its rows are presented in the caller's transverse coordinates (the
            # barred ones, r - eta delta on a coasting map): U_4, two modes, 4x4 P_j and G_j.
            f = determined_value(frame)
            rec4 = ReciprocalScaling(rec.mode, rec.factors[1:2], 4)
            normalizer = Determined(_unscale_normalizer(rec4, f.normalizer))
            tunes = collect(Float64, f.tunes)
            beta, alpha, gamma = unscale_twiss(f.beta, f.alpha, f.gamma)
            projectors = Determined([_unscale_projector(rec4, P) for P in f.projectors])
            covariances = Determined([_unscale_covariance(rec4, G) for G in f.covariances])
        else
            normalizer = unavailable(Matrix{Float64}, projected_optics)
            tunes = Float64[]
            beta = alpha = gamma = unavailable(Matrix{Float64}, projected_optics)
            projectors = covariances = unavailable(Vector{Matrix{Float64}}, projected_optics)
        end
        if is_determined(separation)
            s = determined_value(separation)
            zeta = Determined(_unscale_crab_dispersion(rec, s.zeta))
            eta = Determined(_unscale_momentum_dispersion(rec, s.eta))
            h = Determined(_unscale_longitudinal_factor(rec, s.h))
            graph = Determined(_unscale_graph(rec, hcat(s.zeta, s.eta ./ s.h)))
        else
            zeta = unavailable(Vector{Float64}, separation)
            h = unavailable(Float64, separation)
            graph = unavailable(Matrix{Float64}, separation)
            reta = dispersion.eta
            if is_ambiguous(reta)
                set = ambiguity_set(reta)
                center = _unscale_momentum_dispersion(rec, set.center)
                factor = reduce(hcat, [_unscale_momentum_dispersion(rec, set.factor[:, k]) for k in 1:size(set.factor, 2)])
                eta = Determined{Vector{Float64}}(AmbiguitySet(center, factor * transpose(factor), factor, set.multiplicity, set.kind),
                                                  reta.reason, reta.detail)
            else
                eta = unavailable(Vector{Float64}, separation)
            end
        end
    end
    if is_determined(form) && is_determined(transverse) && is_determined(determined_value(transverse).edwards_teng_normalizer)
        pair = determined_value(determined_value(transverse).edwards_teng_normalizer)
        R = determined_value(form) == 1 ? pair.form1.R : pair.form2.R
        et_R = is_determined(R) ? Determined(_unscale_edwards_teng_R(rec, determined_value(R))) : unavailable(Matrix{Float64}, R)
    else
        et_R = unavailable(Matrix{Float64}, form)
    end
    Sigma = is_determined(covariance) ? Determined(_unscale_covariance(rec, determined_value(covariance))) : unavailable(Matrix{Float64}, covariance)
    return PhysicalOptics(normalizer, tunes, beta, alpha, gamma, et_R, graph, zeta, eta, h, projectors, covariances, Sigma)
end

"""
    _analysis_diagnostics(...) -> AnalysisDiagnostics

The diagnostics record from the pieces (see [`AnalysisDiagnostics`](@ref));
the `residuals` triples carry the tolerances the verdict uses, so a reader
can recompute every acceptance.
"""
function _analysis_diagnostics(input::_ANALYSIS_INPUT_T, defect::_DEFECT_T, rule::Symbol, rho_M0::Real,
                               clusters::ModeClusters, transverse, dispersion, separation, projected_optics,
                               longitudinal_selection, edwards_teng, covariance_residual)
    rho_M1 = clusters.rho_M1
    point = input.provenance === nothing ? ntuple(_ -> 0.0, 6) : input.provenance.point
    departure = isempty(clusters.eigenvalues) ? 0.0 : maximum(abs(abs(lambda) - 1) for lambda in clusters.eigenvalues)
    residuals = Tuple{String,Float64,Float64}[]
    frame = is_determined(transverse) ? determined_value(transverse).frame : transverse
    if is_determined(transverse) && is_determined(frame)
        f = determined_value(frame)
        # (I1) is the backward error of a backward-stable solve: its scale is rho alone (kappa = 1);
        # (E7) is FIRST order in the eigenvector error ((E3) pins the diagonal blocks); the landed kappa is cond(U_4),
        # the derived one cond(U_4) / _pair_gap (carried item 4, the docstring of _FRAME_ACCEPTANCE_MULTIPLIER).
        push!(residuals, ("frame reconstruction (I1)", f.reconstruction_residual.normalized, _FRAME_ACCEPTANCE_MULTIPLIER * rho_M1))
        push!(residuals, ("frame symplecticity (E7)", f.symplecticity_residual, _FRAME_ACCEPTANCE_MULTIPLIER * rho_M1 * cond(f.normalizer)))
    end
    if separation !== nothing && is_determined(separation)
        s = determined_value(separation)
        kappa_sep = max(1.0, norm(clusters.matrix)) * norm(s.transformation) * norm(s.inverse)
        push!(residuals, ("separation off-diagonal (K5)", s.off_diagonal_residual, _SEPARATION_RESIDUAL_MULTIPLIER * eps() * kappa_sep))
        push!(residuals, ("triple consistency (K7)", s.triple_consistency, _TRIPLE_CONSISTENCY_MULTIPLIER * eps() * kappa_sep))
    end
    if projected_optics !== nothing && is_determined(projected_optics)
        o = determined_value(projected_optics)
        push!(residuals, ("U_6 reconstruction", o.reconstruction.normalized, _NORMALIZER_ACCEPTANCE_MULTIPLIER * rho_M1))
        push!(residuals, ("U_6 symplecticity", o.symplecticity, _NORMALIZER_ACCEPTANCE_MULTIPLIER * rho_M1 * cond(o.normalizer)))
    end
    if covariance_residual !== nothing
        cr = covariance_residual
        push!(residuals, ("covariance closure", cr.closure,
                          _COVARIANCE_ACCEPTANCE_MULTIPLIER * rho_M1 * cr.kappa * max(1.0, cr.sigma_norm)))
        # theory (K14): an identity between unit-emittance covariances, reported (not judged: it is emittance-free)
        cr.k14 === nothing || push!(residuals, ("(K14) zz identity", cr.k14, _COVARIANCE_ACCEPTANCE_MULTIPLIER * rho_M1 * cr.kappa * cr.k14_scale))
    end
    resolution = Tuple{String,Float64}[("resolution_chord", clusters.resolution_chord), ("rho_M0", clusters.rho_M0), ("rho_M1", rho_M1)]
    for (i, c) in enumerate(clusters.clusters)
        push!(resolution, ("cluster $(i) forced", c.forced ? 1.0 : 0.0))
        push!(resolution, ("cluster $(i) resolved", c.resolved ? 1.0 : 0.0))
    end
    n = length(clusters.clusters)
    for i in 1:n, j in i+1:n
        push!(resolution, ("chord($(i),$(j))", clusters.inter_cluster_chords[i, j]))
    end
    for r in clusters.resolution_receipt
        push!(resolution, ("candidate chord $(r.first) | $(r.second)", r.chord))
    end
    routes = _ROUTE_DIAGNOSTIC_T[]
    projection = Determined{_PROJECTION_DIAGNOSTIC_T}(:not_requested, "a 4x4 map has no longitudinal projection")
    if dispersion !== nothing
        for r in dispersion.routes
            r.status === :route_not_selected && continue
            res = is_determined(r.invariance_residual) ? determined_value(r.invariance_residual) : (normalized=0.0, raw=0.0)
            cc = is_determined(r.coefficient_condition) ? determined_value(r.coefficient_condition) : 0.0
            push!(routes, _ROUTE_DIAGNOSTIC_T((r.route, r.status, res.normalized, res.raw, cc, r.iterations, r.converged, r.detail)))
            if r.route === dispersion.primary && is_determined(r.invariance_residual) && is_determined(r.graph)
                D = determined_value(r.graph)
                # the kernel's floor through the same helper with the same arguments: clusters.matrix is the scaled matrix
                # the routes ran on (result.matrix_scaled) and r.coefficient_condition the route's reported amplification
                push!(residuals, ("primary route invariance (I1)", res.normalized,
                                  _ROUTE_INVARIANCE_MULTIPLIER * eps() * _kappa_route(clusters.matrix, D, r.coefficient_condition)))
            end
        end
        if is_determined(separation)
            s = determined_value(separation)
            pr = dispersion.routes[findfirst(r -> r.route === dispersion.primary, dispersion.routes)]
            h_report = is_determined(pr.h) ? determined_value(pr.h) : (is_determined(dispersion.h) ? determined_value(dispersion.h) : s.h)
            D = hcat(s.zeta, s.eta ./ s.h)
            area = is_determined(pr.canonical_area) ? determined_value(pr.canonical_area) : dot(s.zeta, _symplectic_form(4) * (s.eta ./ s.h))
            projection = Determined(_PROJECTION_DIAGNOSTIC_T((h_report, s.h, abs(h_report - s.h), minimum(svdvals(D)), area, s.triple_consistency)))
        else
            projection = Determined{_PROJECTION_DIAGNOSTIC_T}(separation.reason, separation.detail)
        end
    end
    mr = is_determined(transverse) ? determined_value(transverse).mais_ripken : Determined{MaisRipkenSet}(transverse.reason, transverse.detail)
    phase_validity = is_determined(mr) ? Determined(determined_value(mr).phase_valid) : Determined{NTuple{2,Bool}}(mr.reason, mr.detail)
    return AnalysisDiagnostics("canonical (x, px, y, py[, z, pz]); eigenvalue exp(-i mu), tunes mu in radians per turn; scaled coordinates",
                               point, defect, rule, departure, Float64(rho_M0), rho_M1, residuals, resolution,
                               longitudinal_selection, edwards_teng, projection, phase_validity, routes)
end

"""
    _analysis_verdict(analysis, diagnostics, degradations; primary_status=:none, separation_status=:none) -> (status::Symbol, failures::Vector{String})

Step 12 (dossier F4): FAILURES are the `_VERDICT_RESIDUALS` triples whose
value exceeds its tolerance (the frame's (I1) residual against
`_FRAME_ACCEPTANCE_MULTIPLIER * rho_M1` and its (E7) residual against the
same times `cond(U_4)`, the 6D normalizer's reconstruction against
`_NORMALIZER_ACCEPTANCE_MULTIPLIER * rho_M1` and its symplecticity against
the same times `cond(U_6)`, the raw covariance closure against
`_COVARIANCE_ACCEPTANCE_MULTIPLIER * rho_M1 * cond(U) * max(1, ||Sigma||)`;
the (K14) identity is reported, not judged), the primary dispersion route and the
separation when their statuses are `:not_invariant` (the keywords
`primary_status` / `separation_status` carry the `Determined` reason of the
route and of the separation, `:none` when the result is available or was
not attempted). `:failed` if any;
`:degraded` if none but `degradations` is non-empty; else `:passed`.
Receipt `:analysis_strictness (strict, outcome)`; the THROW itself is
`analyze`'s.
"""
function _analysis_verdict(analysis::TwissDispersionAnalysis, diagnostics::AnalysisDiagnostics, degradations::Vector{String};
                           primary_status::Symbol=:none, separation_status::Symbol=:none)
    failures = String[]
    for (name, value, tolerance) in diagnostics.residuals
        name in _VERDICT_RESIDUALS || continue
        (isfinite(value) && value <= tolerance) ||
            push!(failures, "$(name) residual $(value) exceeds its acceptance $(tolerance)")
    end
    primary_status === :not_invariant &&
        push!(failures, "the primary dispersion route (:eigenplane) is :not_invariant: its graph does not satisfy the invariance equation")
    separation_status === :not_invariant &&
        push!(failures, "the canonical separation is :not_invariant: the off-diagonal blocks of M_cal^-1 M M_cal exceed their tolerance")
    status = !isempty(failures) ? :failed : (!isempty(degradations) ? :degraded : :passed)
    _record_execution!(:analysis_strictness, CPUThreadsBackend, (strict=analysis.strict, outcome=status))
    return status, failures
end

# The `diagnostics.residuals` names the verdict judges (dossier F4); the other
# triples (separation, triple consistency, primary route) are reported with
# the tolerance their kernel used and are judged through the kernel's status.
const _VERDICT_RESIDUALS = ("frame reconstruction (I1)", "frame symplecticity (E7)", "U_6 reconstruction",
                            "U_6 symplecticity", "covariance closure")

"""
    _analysis_configuration(analysis, input, ...) -> Vector{ConfigurationEntry}

Dossier F6: one entry per schema option from the branch the run took;
statuses only from `CONFIGURATION_STATUSES` (`:resolved`,
`:inactive_dependency`), never `:inactive`. AMENDMENT to the design's
Certification paragraph ("the route list is inactive when the dispersion is
unavailable", recorded in the stage 4b history): on a bunched 6x6 map whose
primary dispersion is unavailable the requested `dispersion_routes` tuple IS
read and the routes execute (receipt `:analysis_dispersion_routes`), so the
option stays `:resolved`; it is inactive only where nothing reads it (4x4
input, a coasting map).
"""
function _analysis_configuration(analysis::TwissDispersionAnalysis, input::_ANALYSIS_INPUT_T, coasting_holds::Bool,
                                 transverse_available::Bool, newton_executed::Bool)
    entries = ConfigurationEntry[]
    matrix_input = input.form === :matrix
    four = input.dimension == 4
    for (name, meta) in pairs(analysis_option_schema(analysis))
        requested = getproperty(analysis, name)
        reason = if name in (:closed_orbit, :closed_orbit_atol) && matrix_input
            "a bare matrix carries no closed-orbit information"
        elseif name in (:longitudinal_mode, :dispersion_routes) && four
            "a 4x4 map has no longitudinal mode"
        elseif name in (:longitudinal_mode, :dispersion_routes) && coasting_holds
            "the map has the coasting structure: no synchrotron mode and a single (coasting) dispersion"
        elseif name === :newton_max_iterations && !newton_executed
            "the :newton route did not execute" * (four ? " (4x4 input)" : "")
        elseif name === :preferred_form && !transverse_available
            "the presented Edwards-Teng pair is unavailable"
        elseif name === :emittances && requested === nothing
            "no emittances were given"
        else
            ""
        end
        status = isempty(reason) ? :resolved : :inactive_dependency
        push!(entries, ConfigurationEntry(name, requested, requested, status, reason, meta.consumer))
    end
    return entries
end

"""
    _analyze_matrix(analysis, M, input) -> TwissDispersionResult

The pipeline driver behind every `analyze` method: size and finiteness
checks (a `4x4` or `6x6` real matrix; anything else an ArgumentError),
then steps 1-12 in the order of the design through the functions above,
the `:failed` verdict thrown as [`OpticsAnalysisError`](@ref) when
`analysis.strict`. ONE deviation from the design's "Pipeline" order,
recorded here and in the stage 4b history (theory review T7): the coasting
test (design step 3, "before any spectral classification") runs INSIDE
`_dispersion_routes`, i.e. after `_analysis_clusters` and after the
cluster-classification degradations of this driver. It is harmless on every
fixture because stage 3 flags the unit pair as a real-class cluster (never
`:indefinite` / `:unresolved`), so no degradation precedes the coasting
branch; the stage 3 record item 11 and the stage 4a record item 1 ("stage 4
runs it first") describe the design, not this driver.
"""
function _analyze_matrix(analysis::TwissDispersionAnalysis, M::AbstractMatrix{<:Real}, input::_ANALYSIS_INPUT_T)
    d = size(M, 1)
    (size(M, 2) == d && d in (4, 6)) || throw(ArgumentError(
        "analyze: a TwissDispersionAnalysis takes a 4x4 or 6x6 real matrix, got size $(size(M))"))
    all(isfinite, M) || throw(ArgumentError("analyze: the matrix has non-finite entries"))
    Mf = Matrix{Float64}(M)
    rec, Ms = _analysis_scaling(analysis, Mf)
    defect, rule, _, deg_symplectic = _analysis_symplectic_check(analysis, Ms, input)
    provenance_uncertainty = input.provenance === nothing ? 0.0 : input.provenance.map_uncertainty
    rho_M0 = _perturbation_scale(Ms, defect.frobenius; user_uncertainty=analysis.map_uncertainty,
                                 provenance_uncertainty=provenance_uncertainty).scale
    closed_orbit, deg_orbit = _analysis_closed_orbit(analysis, input, rec)
    clusters = _analysis_clusters(analysis, Ms, rho_M0)
    degradations = String[]
    deg_symplectic === nothing || push!(degradations, deg_symplectic)
    deg_orbit === nothing || push!(degradations, deg_orbit)
    for (i, c) in enumerate(clusters.clusters)
        c.forced && push!(degradations, "cluster $(i) $(c.members) was forced (resolution_chord = Inf resolved a group the default chord would not)")
        # :unstable and :unit_eigenvalue clusters are physics, not limitations (dossier F4).
        c.classification in (:indefinite, :unresolved) && push!(degradations,
            "cluster $(i) $(c.members) is $(c.classification) (:$(c.reason)): $(c.detail)")
    end
    if d == 4
        transverse = Determined(_analysis_transverse(analysis, Ms, clusters, rho_M0; rho_M1=clusters.rho_M1))
        dispersion = nothing; separation = nothing; projected = nothing; ohmi = nothing; coasting = nothing
        selection = Determined{_LONGITUDINAL_SELECTION_T}(:not_requested, "a 4x4 map has no longitudinal mode")
        coasting_holds = false; newton_executed = false
        primary_status = :none
    else
        r6 = _analysis_6d(analysis, Ms, clusters; rho_M1=clusters.rho_M1)
        dispersion = r6.dispersion; separation = r6.separation; transverse = r6.transverse
        projected = r6.projected_optics; ohmi = r6.ohmi; selection = r6.longitudinal_selection
        coasting = dispersion.coasting; coasting_holds = r6.coasting; newton_executed = r6.newton_executed
        append!(degradations, r6.degradations)
        # `primary` is assigned once: a closure over the branch-reassigned `dispersion` would be a Core.Box.
        primary = dispersion.primary
        primary_status = dispersion.routes[findfirst(r -> r.route === primary, dispersion.routes)].status
    end
    pair = is_determined(transverse) ? determined_value(transverse).edwards_teng_normalizer :
                                       Determined{EdwardsTengPair}(transverse.reason, transverse.detail)
    form, edwards_teng = _preferred_form_selection(analysis, pair)
    covariance, covariance_6d, closure = _analysis_covariance(analysis, Ms, transverse, projected, separation)
    covariance_info = nothing
    if closure !== nothing
        U = d == 4 ? determined_value(determined_value(transverse).frame).normalizer : determined_value(projected).normalizer
        covariance_info = (closure=closure.closure, k14=closure.k14, k14_scale=closure.k14_scale, kappa=cond(U),
                           sigma_norm=norm(determined_value(covariance)))
    end
    physical = _analysis_back_transform(rec, transverse, dispersion, separation, projected, form, covariance)
    diagnostics = _analysis_diagnostics(input, defect, rule, rho_M0, clusters, transverse, dispersion, separation,
                                        projected, selection, edwards_teng, covariance_info)
    separation_status = (separation !== nothing && is_determined(separation)) ? determined_value(separation).status : :none
    status, failures = _analysis_verdict(analysis, diagnostics, degradations;
                                         primary_status=primary_status, separation_status=separation_status)
    configuration = _analysis_configuration(analysis, input, coasting_holds, is_determined(pair), newton_executed)
    result = TwissDispersionResult(analysis, input, rec, Mf, Ms, defect, rho_M0, closed_orbit, coasting, clusters,
                                   transverse, dispersion, separation, projected, ohmi, covariance_6d, covariance,
                                   physical, diagnostics, configuration, status, degradations, failures)
    status === :failed && analysis.strict && throw(OpticsAnalysisError(result, failures))
    return result
end

"""
    analyze(analysis::TwissDispersionAnalysis, M::AbstractMatrix{<:Real}) -> TwissDispersionResult
    analyze(analysis::TwissDispersionAnalysis, lm::LinearizedMap) -> TwissDispersionResult
    analyze(analysis::TwissDispersionAnalysis, map; method=ComplexStepLinearization(), point=ntuple(_ -> 0.0, 6)) -> TwissDispersionResult

Run the Twiss and dispersion analysis. The three input forms:

  * a bare `4x4` or `6x6` real matrix in canonical coordinates: exact
    provenance is assumed, the closed-orbit options are inactive and
    `map_uncertainty` is the only declared uncertainty;
  * a [`LinearizedMap`](@ref) from [`one_turn_matrix`](@ref): the
    provenance's `map_uncertainty` folds into `rho_M0`, a finite-difference
    provenance REQUIRES an explicit `symplectic_rtol`, and the recorded
    fixed-point residual is judged by the `closed_orbit` options;
  * anything `one_turn_matrix` accepts (a callable, a tuple of compiled
    maps, a compiled line, an element spec): `one_turn_matrix(map; method,
    point)` is called and the result analysed as a `LinearizedMap`.

Argument errors at the boundary (wrong size, non-finite entries, a
non-symplectic matrix under `nonsymplectic = :error`, a closed-orbit defect
under `closed_orbit = :require`, a finite-difference map without
`symplectic_rtol`, a map the method cannot differentiate) are thrown before
any result exists; a `:failed` numerical verdict throws
[`OpticsAnalysisError`](@ref) carrying the result under `strict = true` and
returns it under `strict = false`. Physically undetermined quantities are
`Determined` statuses in the result, never numbers and never errors.
"""
function analyze(analysis::TwissDispersionAnalysis, M::AbstractMatrix{<:Real})
    d = size(M, 1)
    (size(M, 2) == d && d in (4, 6)) || throw(ArgumentError(
        "analyze: a TwissDispersionAnalysis takes a 4x4 or 6x6 real matrix, got size $(size(M))"))
    return _analyze_matrix(analysis, M, _ANALYSIS_INPUT_T((:matrix, d, nothing)))
end

function analyze(analysis::TwissDispersionAnalysis, lm::LinearizedMap)
    return _analyze_matrix(analysis, lm.matrix, _ANALYSIS_INPUT_T((:linearized, 6, lm.provenance)))
end

function analyze(analysis::TwissDispersionAnalysis, map; method::AbstractLinearizationMethod=ComplexStepLinearization(),
                 point=ntuple(_ -> 0.0, 6))
    return analyze(analysis, one_turn_matrix(map; method=method, point=point))
end
