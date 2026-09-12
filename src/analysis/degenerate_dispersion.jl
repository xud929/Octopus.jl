# Canonical dispersion at a definite degenerate group (theory Section 13.6;
# design "What is returned in each case", rows 2 and 3; stage 3 Part B).
#
# Every function here computes on the (already scaled) cluster frame it is
# given and returns plain values or an `AmbiguitySet`; nothing here scales,
# nothing here decides which cluster is degenerate (that is the resolution
# chord of mode_clusters.jl), and nothing here claims an analysis. Inputs are
# PLAIN: a 6 x m complex frame `U_c` satisfying (N4), or the real group
# quantities `(P_c, G_c, multiplicity)` of (N5). Thin methods on the cluster
# structs are added by the integrator.
#
# Conventions (shared with the whole stage): coordinates (x, px, y, py, z,
# pz), S_6 = diag(S_2, S_2, S_2), oriented eigenvalue e^{-i mu}, frame
# normalization U_c' S U_c = -2i I_m and isotropy U_c^T S U_c = 0 (N4);
# P_c = -Im(U_c U_c') S, G_c = Re(U_c U_c') (N5); the (D12) readout
# eta_a = -Im(conj(u_z) u_a) with z = index 5 and pz = index 6 (theory 8.3).
#
# The midpoint of an ambiguity set is NEVER a dispersion (design "Alternatives
# rejected"): it is returned only inside the `AmbiguitySet`, whose accessor
# `dispersion_interval` gives the scalar range of a readout.

"""
    _EXACT_SET_MULTIPLIER

PROVISIONAL multiplier of [`_ambiguity_kind`](@ref): a cluster whose internal
complex-eigenvalue gap satisfies `internal_gap <= _EXACT_SET_MULTIPLIER *
rho_M1` is treated as exactly degenerate, so its ambiguity set is the sharp
solution set `:exact_set` of theory (N12); a larger gap is a genuine split the
map's own error resolves, and the set is only an `:orientation_envelope`
containing the members' dispersions. The design ("Default value") wants this
multiplier measured on the same fixtures as the chord, with the rule that the
largest gap-to-threshold ratio of an accepted (exact) fixture stays below one
tenth and the smallest of a rejected (split) fixture exceeds ten. Accepted:
the exact rolled FODO of theory 13.10 in its 6D embedding (gap of order
1e-16 at rho_M1 of order 1e-15) and `diag(R(0.73), R(1.41), R(0.73))`
conjugated by random symplectic maps (gap of order 1e-16 to 1e-15); rejected:
the FODO's 1e-12 detuned control, whose gap 2.1e-12 is real. Measured in Part
B (OUT/probes_B/measure_B.log, names printed from the rows): largest accepted
gap / rho_M1 = 0.587 (the exact rolled FODO, 4 x 4; its 6D embedding and the
30 conjugated pairs are below), smallest rejected = 681 (the 1e-12 control),
so the one-tenth / ten window is [5.87, 68.1] and the value 10 sits inside;
Part D re-measures and freezes it.
"""
const _EXACT_SET_MULTIPLIER = 10.0

"""
    _CLUSTER_FRAME_N4_MULTIPLIER

PROVISIONAL multiplier `c` of the roundoff tolerance `c eps m max(1,
||U_c||_2^2)` above which [`_check_cluster_frame`](@ref) refuses a frame: the
(N4) residuals of a frame built by (N20) from an orthonormal Schur basis are
of order `eps ||U_c||_2^2` (each entry of `U_c' S U_c` sums `6` products of
size `||U_c||^2`), so the tolerance is the shared `c eps kappa` form with
`kappa = ||U_c||_2^2`. Measured in Part B on the 30 conjugated copies of
`diag(R(0.73), R(1.41), R(0.73))`, the three-mode fixture, the exact FODO
embedding and the isospectral limit and split maps: the largest accepted
residual / tolerance is 0.043 (conjugated pair 11 of seed 20260911), so the
window's lower edge is 27; rejected: a column rescaled by 1 + 1e-6 gives
1.2e7 times the tolerance, the N15 indefinite frame 1.7e13, a conjugate
partner as second column 7.0e12 (window upper edge 7.5e8 for the smallest
rejected). Recorded in report_B.md.
"""
const _CLUSTER_FRAME_N4_MULTIPLIER = 64.0

"""
    _AMBIGUITY_PSD_MULTIPLIER

PROVISIONAL multiplier `c` of the positive-semidefiniteness tolerance
`tol_psd = c eps max(1, scale)` of [`_ambiguity_factor`](@ref), where `scale`
is `||G_c||_2^2` when the shape is built from a covariance (its entries are
products of two `G_c` entries) and `||A||_2` when the factor is called on a
bare shape. Eigenvalues of the shape below `-tol_psd` are an error (theory
13.6: the shape is positive semidefinite), those within `[-tol_psd, tol_psd]`
are zero. The value must also keep the dropped part below the `AmbiguitySet`
constructor's own consistency tolerance, which is why the reported shape is
`F F'` by construction ([`_ambiguity_factor`](@ref)). Measured in Part B
(report_B.md): the largest |zero eigenvalue| / tol_psd over the accepted
fixtures is 0.034 (the trial-015 split map at eps = 1e-9 treated as one
cluster; the conjugated pairs are below), the largest |negative eigenvalue| /
tol_psd 0.034, so the window's lower edge is 2.7 for this multiplier; a
genuinely negative eigenvalue (-1e-3 on a unit shape) is 5.6e11 tol_psd.
The same multiplier scales the `G_c` symmetry and `P_c` idempotency refusals
of the (P_c, G_c) method (largest accepted idempotency ratio 0.070).
"""
const _AMBIGUITY_PSD_MULTIPLIER = 8.0

"""
    _check_cluster_frame(U_c; multiplier=_CLUSTER_FRAME_N4_MULTIPLIER)
        -> (normalization, isotropy, tolerance, kappa)

The (N4) checker of a complex cluster frame `U_c` (`d x m`, `d` even, `m >=
1`): `normalization = ||U_c' S U_c + 2i I_m||_F` and `isotropy = ||U_c^T S
U_c||_F`, both against the roundoff tolerance `multiplier * eps * m * max(1,
kappa)` with `kappa = ||U_c||_2^2` (the frame's own conditioning; an
(E3)-normalized column has `||u||^2 >= 2`, so `kappa >= 2` for any valid
frame). Throws an `ArgumentError` naming the offending residual when either
exceeds the tolerance, on non-finite entries, on an odd row count, or on more
columns than `d / 2` (a half-spectrum has at most `d / 2` members). Returns
the residuals, the tolerance and `kappa` so a caller can report them. Every
positive-definite Gram normalization (N20) of an invariant half-cluster basis
satisfies both relations; an indefinite half-cluster (theory (N15)) cannot,
because no basis of it is Krein-orthonormal with one sign, and a single
oriented vector padded by an arbitrary partner fails isotropy.
"""
function _check_cluster_frame(U_c::AbstractMatrix{<:Complex};
                              multiplier::Real=_CLUSTER_FRAME_N4_MULTIPLIER)
    d, m = size(U_c)
    iseven(d) && d >= 2 || throw(ArgumentError(
        "_check_cluster_frame: the frame needs an even row count, got $(d)"))
    1 <= m <= div(d, 2) || throw(ArgumentError(
        "_check_cluster_frame: a half-cluster frame of a $(d)-dimensional map has 1 to $(div(d, 2)) " *
        "columns, got $(m)"))
    all(isfinite, U_c) || throw(ArgumentError("_check_cluster_frame: the frame must be finite"))
    isfinite(multiplier) && multiplier > 0 || throw(ArgumentError(
        "_check_cluster_frame: multiplier must be a positive finite number, got $(multiplier)"))
    U = Matrix{ComplexF64}(U_c)
    S = _symplectic_form(d)
    kappa = opnorm(U, 2)^2
    normalization = norm(U' * S * U + 2im * I)
    isotropy = norm(transpose(U) * S * U)
    tolerance = Float64(multiplier) * eps(Float64) * m * max(1.0, kappa)
    normalization <= tolerance || throw(ArgumentError(
        "_check_cluster_frame: the (N4) normalization residual ||U' S U + 2i I|| = $(normalization) " *
        "exceeds the roundoff tolerance $(tolerance) (kappa = $(kappa)); the frame is not the (N20) " *
        "normalization of a definite half-cluster"))
    isotropy <= tolerance || throw(ArgumentError(
        "_check_cluster_frame: the (N4) isotropy residual ||U^T S U|| = $(isotropy) exceeds the " *
        "roundoff tolerance $(tolerance) (kappa = $(kappa)); the columns are not one half of a " *
        "conjugation-closed cluster"))
    return (normalization=normalization, isotropy=isotropy, tolerance=tolerance, kappa=kappa)
end

"""
    _sampled_mode_dispersion(U_c, c) -> Vector{Float64}

The canonical momentum dispersion of the member `u = U_c c` of a 6 x m
cluster frame by theory (N10)/(D12): `eta_a = -Im(conj(u_z) u_a)` for `a` in
`(x, px, y, py)`, `z` the fifth coordinate. `c` is a unit complex coefficient
vector (`||c||_2 = 1` to roundoff, checked; any other norm rescales `eta` by
`||c||^2` and is refused loudly). Used by the tests and the measurement to
sample the ambiguity set (N12); a frame is not re-checked here, so the caller
verifies (N4) once with [`_check_cluster_frame`](@ref).
"""
function _sampled_mode_dispersion(U_c::AbstractMatrix{<:Complex}, c::AbstractVector{<:Number})
    size(U_c, 1) == 6 || throw(ArgumentError(
        "_sampled_mode_dispersion: the frame needs 6 rows (x, px, y, py, z, pz), got $(size(U_c, 1))"))
    length(c) == size(U_c, 2) || throw(ArgumentError(
        "_sampled_mode_dispersion: the coefficient vector must have $(size(U_c, 2)) entries, got $(length(c))"))
    all(isfinite, c) || throw(ArgumentError("_sampled_mode_dispersion: coefficients must be finite"))
    nc = norm(c)
    abs(nc - 1) <= 64 * eps(Float64) * length(c) || throw(ArgumentError(
        "_sampled_mode_dispersion: the coefficient vector must be a unit vector, got ||c|| = $(nc)"))
    u = Matrix{ComplexF64}(U_c) * Vector{ComplexF64}(c)
    uz = conj(u[5])
    return [-imag(uz * u[a]) for a in 1:4]
end

"""
    _ambiguity_factor(A, columns; tol_psd=_AMBIGUITY_PSD_MULTIPLIER * eps * max(1, ||A||_2))
        -> (factor, rank, eigenvalues, tol_psd, shape, dropped)

The rectangular factor `F` (`n x columns`, `F F^T = A`) of a positive
semidefinite shape matrix `A` (theory 13.6: `F_eta` has `2m - 1` columns).
`A` is symmetrized as `(A + A^T) / 2` and eigen-decomposed; an eigenvalue
below `-tol_psd` is an `ArgumentError` (the shape of a definite group is
positive semidefinite, so a genuinely negative eigenvalue means the input is
not such a shape), eigenvalues within `[-tol_psd, tol_psd]` are zero, and the
rank `r` is the count above `tol_psd`, asserted `r <= columns` (an
`ArgumentError` otherwise: the caller's multiplicity does not fit the shape).
`F = V_r sqrt(Lambda_r)` padded with zero columns to `columns`. Also returned:
`shape = F F^T` (symmetrized), the positive-semidefinite part of `A` with its
roundoff-null eigenvalues zeroed, and `dropped = ||A_sym - shape||_F <=
tol_psd`. The caller reports `shape`, not `A_sym`, as the set's shape so that
`shape == factor factor'` holds BY CONSTRUCTION and the `AmbiguitySet`
constructor's own consistency check (a roundoff bound on `F F' - shape`,
which is smaller than `tol_psd` on the measured fixtures) can never refuse a
shape this function accepted; the two spellings differ by `dropped`, a
roundoff-scale quantity, and `dropped` is returned so a caller can see it.
The Cholesky factorization is NOT used: it fails on every rank-deficient
shape, and the two-mode shape is rank-deficient by construction (rank at most
3 in 4 coordinates).
"""
function _ambiguity_factor(A::AbstractMatrix{<:Real}, columns::Integer;
                           tol_psd::Real=_AMBIGUITY_PSD_MULTIPLIER * eps(Float64) * max(1.0, opnorm(Matrix{Float64}(A), 2)))
    n = size(A, 1)
    size(A, 2) == n || throw(ArgumentError("_ambiguity_factor: the shape must be square, got $(size(A))"))
    all(isfinite, A) || throw(ArgumentError("_ambiguity_factor: the shape must be finite"))
    columns >= 1 || throw(ArgumentError("_ambiguity_factor: columns must be at least 1, got $(columns)"))
    isfinite(tol_psd) && tol_psd >= 0 || throw(ArgumentError(
        "_ambiguity_factor: tol_psd must be a non-negative finite number, got $(tol_psd)"))
    As = Matrix{Float64}(A)
    As = (As + transpose(As)) / 2
    lam, V = eigen(Symmetric(As))
    lam_min = minimum(lam)
    lam_min >= -tol_psd || throw(ArgumentError(
        "_ambiguity_factor: the shape has eigenvalue $(lam_min) below -tol_psd = $(-tol_psd); the " *
        "ambiguity shape of a definite group is positive semidefinite, so this is not such a shape"))
    keep = findall(l -> l > tol_psd, lam)
    r = length(keep)
    r <= columns || throw(ArgumentError(
        "_ambiguity_factor: the shape has rank $(r) above tol_psd = $(tol_psd) but only $(columns) " *
        "columns were requested (theory 13.6: 2m - 1 columns for multiplicity m)"))
    F = zeros(Float64, n, Int(columns))
    for (j, idx) in enumerate(keep)
        F[:, j] = V[:, idx] * sqrt(lam[idx])
    end
    shape = F * transpose(F)
    shape = (shape + transpose(shape)) / 2
    return (factor=F, rank=r, eigenvalues=lam, tol_psd=Float64(tol_psd), shape=shape,
            dropped=norm(As - shape))
end

"""
    _ambiguity_kind(internal_gap, rho_M1; exact_set_multiplier=_EXACT_SET_MULTIPLIER) -> Symbol

The kind of a cluster's ambiguity set (one of `AMBIGUITY_KINDS`): `:exact_set`
when `internal_gap <= exact_set_multiplier * rho_M1`, the cluster's split is
below the map's own perturbation scale, so the map cannot distinguish the
cluster from an exactly degenerate one and theory (N12) is its sharp solution
set; `:orientation_envelope` otherwise, the split is real but unresolved by
the chord, and the set built from the group quantities CONTAINS the members'
dispersions without being their solution set (its intervals are containing,
not sharp). Both arguments are non-negative finite scaled-coordinate
quantities (an `ArgumentError` otherwise); the multiplier is the PROVISIONAL
[`_EXACT_SET_MULTIPLIER`](@ref).
"""
function _ambiguity_kind(internal_gap::Real, rho_M1::Real; exact_set_multiplier::Real=_EXACT_SET_MULTIPLIER)
    for (name, v) in (("internal_gap", internal_gap), ("rho_M1", rho_M1),
                      ("exact_set_multiplier", exact_set_multiplier))
        isfinite(v) && v >= 0 || throw(ArgumentError(
            "_ambiguity_kind: $(name) must be a non-negative finite number, got $(v)"))
    end
    exact_set_multiplier > 0 || throw(ArgumentError(
        "_ambiguity_kind: exact_set_multiplier must be positive, got $(exact_set_multiplier)"))
    return internal_gap <= exact_set_multiplier * rho_M1 ? :exact_set : :orientation_envelope
end

"""
    _dispersion_ambiguity_set(U_c; kind) -> AmbiguitySet
    _dispersion_ambiguity_set(P_c, G_c, multiplicity; kind) -> AmbiguitySet

The complete set of canonical momentum dispersions of a definite degenerate
group (theory Section 13.6; design return-table row 2). The first method
takes the 6 x m complex frame `U_c` of a definite cluster, `m >= 2`,
satisfying (N4) to roundoff ([`_check_cluster_frame`](@ref); an
`ArgumentError` otherwise, so an indefinite group's Krein-mixed basis of
(N15) is refused rather than turned into a bounded set), forms `P_c = -Im(U_c
U_c') S_6` and `G_c = Re(U_c U_c')` (N5) and calls the second. The second
takes the real group quantities directly: `P_c`, `G_c` (6 x 6, finite,
`G_c` symmetric and `P_c` idempotent to roundoff) and the multiplicity `m`.

  * center (N11): `eta_mid = (P_c)[1:4, 6] / 2`, the transverse part of the
    `pz` column of the projector. It is the midpoint of the set and NOT a
    dispersion of any particular mode (design "Alternatives rejected"); it is
    returned only inside the `AmbiguitySet`.
  * shape (N11): `A = ((G_c)[5, 5] (G_c)[1:4, 1:4] - (G_c)[1:4, 5] (G_c)[5, 1:4]) / 4`,
    symmetrized; positive semidefinite. The REPORTED shape is its PSD part
    with the roundoff-null eigenvalues (|lambda| <= tol_psd) zeroed, equal to
    `factor factor'` by construction and to `A` within `tol_psd` (measured
    difference 0.034 tol_psd at most on the Part B fixtures).
  * factor (N12): `F` with `F F^T = A`, 4 x (2m - 1), from
    [`_ambiguity_factor`](@ref) with `tol_psd = _AMBIGUITY_PSD_MULTIPLIER eps
    max(1, ||G_c||_2^2)`; rank at most `2m - 1`, asserted there.
  * kind: one of `AMBIGUITY_KINDS`, REQUIRED (the caller decides it with
    [`_ambiguity_kind`](@ref) from the cluster's internal gap and `rho_M1`;
    this function has neither).

The set is `{eta_mid + F n : ||n||_2 = 1}`; the scalar readout `a' eta`
ranges over `a' eta_mid +- sqrt(a' A a)` (N14), available through
`dispersion_interval`. For `m = 2` it is an ellipsoid SURFACE (rank up to 3),
for three coincident modes the filled ellipsoid (N13). Graph qualification
(theory 13.6): for `m >= 2` the set always contains members with a singular
longitudinal projection (`h = 0`, a member with zero longitudinal-position
component), so the graph-based representation (D3) of some members does not
exist; the set is the closure of the graph-regular members' values.

Refusals, each an `ArgumentError` naming the reason BEFORE any set is built: a
4-row frame or 4 x 4 group quantities (no longitudinal plane: a 4D map has
no dispersion), multiplicity 1 (a single mode has a unique dispersion; the
`AmbiguitySet` constructor refuses it too, but this wrapper names the reason
first), an (N4) violation, a non-symmetric `G_c`, a non-idempotent `P_c`, a
shape with a genuinely negative eigenvalue, and an unknown `kind`.
"""
function _dispersion_ambiguity_set(U_c::AbstractMatrix{<:Complex}; kind::Symbol)
    d, m = size(U_c)
    d == 6 || throw(ArgumentError(
        "_dispersion_ambiguity_set: the frame needs 6 rows (x, px, y, py, z, pz), got $(d); a " *
        "$(d)-dimensional map has no longitudinal plane and no dispersion"))
    m >= 2 || throw(ArgumentError(
        "_dispersion_ambiguity_set: multiplicity $(m) has a unique dispersion, not a set; use the " *
        "(D12) readout of the single mode"))
    kind in AMBIGUITY_KINDS || throw(ArgumentError(
        "_dispersion_ambiguity_set: kind must be one of $(AMBIGUITY_KINDS), got :$(kind)"))
    _check_cluster_frame(U_c)
    U = Matrix{ComplexF64}(U_c)
    S = _symplectic_form(6)
    UU = U * U'
    P_c = -imag(UU) * S
    G_c = real(UU)
    G_c = (G_c + transpose(G_c)) / 2
    return _dispersion_ambiguity_set(P_c, G_c, m; kind=kind)
end

function _dispersion_ambiguity_set(P_c::AbstractMatrix{<:Real}, G_c::AbstractMatrix{<:Real},
                                   multiplicity::Integer; kind::Symbol)
    size(P_c) == (6, 6) || throw(ArgumentError(
        "_dispersion_ambiguity_set: P_c must be 6x6 (a 4x4 map has no longitudinal plane), got $(size(P_c))"))
    size(G_c) == (6, 6) || throw(ArgumentError(
        "_dispersion_ambiguity_set: G_c must be 6x6 (a 4x4 map has no longitudinal plane), got $(size(G_c))"))
    multiplicity >= 2 || throw(ArgumentError(
        "_dispersion_ambiguity_set: multiplicity $(multiplicity) has a unique dispersion, not a set"))
    multiplicity <= 3 || throw(ArgumentError(
        "_dispersion_ambiguity_set: a 6-dimensional map has at most 3 modes, got multiplicity $(multiplicity)"))
    kind in AMBIGUITY_KINDS || throw(ArgumentError(
        "_dispersion_ambiguity_set: kind must be one of $(AMBIGUITY_KINDS), got :$(kind)"))
    all(isfinite, P_c) && all(isfinite, G_c) || throw(ArgumentError(
        "_dispersion_ambiguity_set: P_c and G_c must be finite"))
    P = Matrix{Float64}(P_c); G = Matrix{Float64}(G_c)
    gscale = max(1.0, opnorm(G, 2)^2)
    asym = norm(G - transpose(G))
    asym <= _AMBIGUITY_PSD_MULTIPLIER * eps(Float64) * sqrt(gscale) || throw(ArgumentError(
        "_dispersion_ambiguity_set: G_c must be symmetric to roundoff (asymmetry $(asym))"))
    # P_c = -Im(U U') S carries roundoff of order eps ||U||^2 = eps kappa per
    # entry, and ||G_c||_2 = ||U||_2^2 up to the imaginary part, so the
    # idempotency tolerance is the shared c eps kappa form with kappa read
    # from G_c (the FODO cluster of theory 13.10 has kappa = 1 / 0.0838 = 11.9
    # and ||P^2 - P|| = 58 eps there; ||P||_2 = 1 would be the wrong scale).
    idem = norm(P * P - P)
    idem_tol = _AMBIGUITY_PSD_MULTIPLIER * eps(Float64) * 6 * max(gscale, opnorm(P, 2)^2)
    idem <= idem_tol || throw(ArgumentError(
        "_dispersion_ambiguity_set: P_c must be a projector to roundoff (||P^2 - P|| = $(idem), " *
        "tolerance $(idem_tol)); the group projector of (N5) is idempotent"))
    center = P[1:4, 6] / 2
    A = (G[5, 5] * G[1:4, 1:4] - G[1:4, 5] * transpose(G[5, 1:4])) / 4
    A = (A + transpose(A)) / 2
    tol_psd = _AMBIGUITY_PSD_MULTIPLIER * eps(Float64) * gscale
    fac = _ambiguity_factor(A, 2 * multiplicity - 1; tol_psd=tol_psd)
    # The reported shape is the PSD part of (N11) within tol_psd (see
    # _ambiguity_factor): factor * factor' == shape by construction.
    return AmbiguitySet(center, fac.shape, fac.factor, multiplicity, kind)
end

"""
    _dispersion_ambiguity_set(c::ModeCluster; kind=nothing) -> AmbiguitySet
    _dispersion_ambiguity_set(r::ModeClusters, index::Integer; kind=nothing) -> AmbiguitySet

Thin methods on the stage 3 cluster structs (integrator, Part C). The frame
`U_c` is the cluster's `frame` (the (N20) frame of a definite cluster, or its
unitary rotation onto the recovered modes when the cluster is resolved; the
set depends on `U_c U_c'` only, so the rotation is immaterial), and `kind`
defaults to `_ambiguity_kind(c.internal_gap, c.rho_M1)`. Refusals, each an
`ArgumentError` naming the cluster's members, classification, reason and
detail: a cluster that is not `:definite` (an indefinite or unresolved group
has no one-sign frame; an unstable or unit-eigenvalue cluster has no modes),
a cluster of multiplicity 1 (a single mode has a unique dispersion), and,
through the frame method, a 4-row frame (a 4D map has no longitudinal plane).
A resolved definite cluster with `m >= 2` is accepted (its envelope is the
caller's choice of `kind`; the design's split endpoint maps treated as one
cluster by an explicit partition). The second method indexes
`r.clusters`.
"""
function _dispersion_ambiguity_set(c::ModeCluster; kind::Union{Nothing,Symbol}=nothing)
    m = length(c.half_members)
    c.classification === :definite || throw(ArgumentError(
        "_dispersion_ambiguity_set: cluster $(c.members) is $(c.classification) (reason :$(c.reason)" *
        (isempty(c.detail) ? "" : "; " * c.detail) * "): only a definite cluster has a one-sign frame"))
    m >= 2 || throw(ArgumentError(
        "_dispersion_ambiguity_set: cluster $(c.members) has multiplicity 1 (reason :$(c.reason)): a single " *
        "mode has a unique dispersion, not a set; use the (D12) readout of its vector"))
    k = kind === nothing ? _ambiguity_kind(c.internal_gap, c.rho_M1) : kind
    return _dispersion_ambiguity_set(determined_value(c.frame); kind=k)
end

function _dispersion_ambiguity_set(r::ModeClusters, index::Integer; kind::Union{Nothing,Symbol}=nothing)
    1 <= index <= length(r.clusters) || throw(ArgumentError(
        "_dispersion_ambiguity_set: cluster index $(index) outside 1:$(length(r.clusters))"))
    return _dispersion_ambiguity_set(r.clusters[index]; kind=kind)
end
