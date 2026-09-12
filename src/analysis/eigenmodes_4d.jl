# The 4D eigenmode route of the coupled Twiss analysis: theory
# docs/theory/twiss_dispersion.md Section 3 (E1)-(E14), Section 4.4
# (T13)-(T16), Section 6.1 (M1)-(M5); design docs/design/
# twiss_dispersion_analysis.md "Pipeline" steps 6, 8 and 10. Stage 2 of the
# campaign (design "Staging", item 2). Pure matrix arithmetic on a real 4x4
# matrix the caller has ALREADY scaled (design "Input boundary" item 5): no
# scaling happens here; the stage 1 `_unscale_*` table transforms the outputs
# back. Nothing in this file claims an analysis exists: no `analyze`, no
# analysis type, no export; the public verb is stage 4.
#
# Conventions (theory Section 2 and 3): coordinates (x, px, y, py),
# S_4 = diag(S_2, S_2), the oriented eigenvector u_j satisfies M u_j =
# e^{-i mu_j} u_j and u_j' S_4 u_j = -2i (E3), the real pair is
# U_j = [Re u_j, -Im u_j] (E6), and M U = U diag(R(mu_1), R(mu_2)) (E8).
#
# Two guards below are PROVISIONAL (dossier of the stage): the resolution
# guard on the complex eigenvalue gap and the raw-modulus stability guard.
# Stage 3 replaces them with the resolution chord (N22) and the per-cluster
# Schur-block test (design "Pipeline" steps 5-6); each is marked at its site.

"""
    SpectrumReport4D

The spectral diagnostics of a real 4x4 matrix that are available whether or
not a [`NormalModeFrame4D`](@ref) could be formed (theory 11.2: "unit-circle
departure", "conjugate-pair separation, including the distance to the
conjugate class"). Fields:

  * `eigenvalues`: the four eigenvalues in eigensolver order (unoriented).
  * `moduli`, `unit_circle_departure`: `abs.(eigenvalues)` and
    `max(abs(moduli - 1))`; `stability_atol` is the tolerance the provisional
    stability guard compared it against.
  * `unit_eigenvalue_distance`: `min over rho of min(|rho - 1|, |rho + 1|)`,
    the distance to a self-conjugate class.
  * `gap`: the complex gap between the two conjugate classes,
    `g = min(|rho_j - rho_k|, |rho_j - conj(rho_k)|)` over eigenvalues of
    different classes (design "Resolution criterion"); `min_gap` is the
    caller's threshold.
  * `trace`, `discriminant_t7`, `discriminant_e10`: `tr M`; the (T7)
    discriminant `(tr M_xx - tr M_yy)^2 + 4 det(adj(M_xy) + M_yx)` from the
    2x2 blocks; and the (E10) radicand `2 tr(M^2) - (tr M)^2 + 8`. Both equal
    `(tau_1 - tau_2)^2` in exact arithmetic; both are reported so a
    disagreement is visible.
  * `traces`: `tau_+, tau_-` of (E10)/(T13) from the (E10) radicand; complex
    when the discriminant is negative (no NaN stands in for it).
  * `t14_holds`: the (T14) test `Delta > 0, |tau_+| < 2, |tau_-| < 2`. A
    DIAGNOSTIC only: `diag(2, 1/2, R(1.2))` has a positive discriminant but
    fails `|tau_+| < 2` (`tau_+ = 2.5`, one hyperbolic mode; theory 4.4); the
    stability decision is the modulus guard either way.
"""
struct SpectrumReport4D
    eigenvalues::Vector{ComplexF64}
    moduli::Vector{Float64}
    unit_circle_departure::Float64
    stability_atol::Float64
    unit_eigenvalue_distance::Float64
    gap::Float64
    min_gap::Float64
    trace::Float64
    discriminant_t7::Float64
    discriminant_e10::Float64
    traces::NTuple{2,ComplexF64}
    t14_holds::Bool
end

"""
    NormalModeFrame4D

The normal-mode frame of a resolved, stable real 4x4 symplectic matrix with
two distinct conjugate eigenvalue pairs (theory Section 3), built by
[`_eigenmodes_4d`](@ref). Mode 1 is the mode with the larger signed area in
the `x` plane (`label_margin` is the difference of the two `kappa_jx`; a
zero margin leaves the eigensolver order, see the design's label step, which
calls labelling a heuristic that never feeds a Twiss value). Fields, `j` the
mode and `a` the plane (`1 = x`, `2 = y`):

  * `matrix`: the matrix analysed (a copy, already scaled by the caller).
  * `eigenvalues`, `tunes`: the oriented eigenvalue `rho_j = e^{-i mu_j}` and
    `mu_j = mod(-arg rho_j, 2 pi)` (E5) by `atan2`, in `[0, 2 pi)` (T16).
  * `vectors`: the oriented eigenvectors `u_j` with `u_j' S_4 u_j = -2i`
    (E3)-(E4); `normalization_residuals` is `|u_j' S_4 u_j + 2i|`.
  * `eigenvector_residuals`: the (I1) vector form of `M u_j - rho_j u_j`
    (normalized and raw).
  * `normalizer`: `U_4 = [Re u_1, -Im u_1, Re u_2, -Im u_2]` (E6);
    `symplecticity_residual` is `||U_4' S_4 U_4 - S_4||_F` (E7);
    `reconstruction_residual` is the (I1) matrix form of
    `M U_4 - U_4 diag(R(mu_1), R(mu_2))` (E8), normalized and raw.
  * `projectors`, `covariances`: `P_j = -Im(u_j u_j') S_4` and
    `G_j = Re(u_j u_j') = U_j U_j'` (theory 3.4, (E13)).
  * `signed_areas`: the 2x2 array `kappa[j, a] = -Im(conj(u_ja) u_j,pa)`
    (M1); `signed_area_row_sums[j] = kappa[j, 1] + kappa[j, 2]` (M2, one);
    `signed_area_column_sums[a] = kappa[1, a] + kappa[2, a]` (M3, one).
  * `beta`, `alpha`, `gamma`: the per-plane projected Twiss arrays `[j, a]`
    by (M1): `|u_ja|^2`, `-Re(conj(u_ja) u_j,pa)`, `|u_j,pa|^2`; NOT
    `(1 + alpha^2) / beta`, because `beta gamma - alpha^2 = kappa^2` (M5).
  * `u_evaluations`: `(kappa[1, 2], kappa[2, 1])`, the two evaluations of `u`
    in (M4); `u_difference` is their difference.
  * `label_margin`: `kappa[1, 1] - kappa[2, 1]`, non-negative by the rule.
"""
struct NormalModeFrame4D
    matrix::Matrix{Float64}
    eigenvalues::NTuple{2,ComplexF64}
    tunes::NTuple{2,Float64}
    vectors::NTuple{2,Vector{ComplexF64}}
    normalization_residuals::NTuple{2,Float64}
    eigenvector_residuals::NTuple{2,NamedTuple{(:normalized, :raw),Tuple{Float64,Float64}}}
    normalizer::Matrix{Float64}
    symplecticity_residual::Float64
    reconstruction_residual::NamedTuple{(:normalized, :raw),Tuple{Float64,Float64}}
    projectors::NTuple{2,Matrix{Float64}}
    covariances::NTuple{2,Matrix{Float64}}
    signed_areas::Matrix{Float64}
    signed_area_row_sums::NTuple{2,Float64}
    signed_area_column_sums::NTuple{2,Float64}
    beta::Matrix{Float64}
    alpha::Matrix{Float64}
    gamma::Matrix{Float64}
    u_evaluations::NTuple{2,Float64}
    u_difference::Float64
    label_margin::Float64
end

"""
    Eigenmodes4D

What [`_eigenmodes_4d`](@ref) returns: the [`SpectrumReport4D`](@ref)
diagnostics, always present, and the `frame`, a
`Determined{NormalModeFrame4D}` that is unique in the generic case and
unavailable with a pinned reason (`:unstable_spectrum`, `:unit_eigenvalue`,
`:cluster_unresolved`, `:unresolved_defective`) otherwise. Never a NaN.
"""
struct Eigenmodes4D
    spectrum::SpectrumReport4D
    frame::Determined{NormalModeFrame4D}
end

# ---------------------------------------------------------------------------
# Kernels shared by the eigenvector route and the closed-form check.

"""
    _orient_eigenvector(v, S) -> (u, s, flipped)

(E4) for one eigensolver output `v`: `s = Im(v' S v)`; the conjugate-pair
member with `s < 0` is kept (`flipped` says whether `conj(v)` was taken,
which also conjugates the eigenvalue), and `u = sqrt(-2 / s) v` so that
`u' S u = -2i` (E3). The sign of `Im(v' S v)` decides, never the sign of the
imaginary part of the eigenvalue (theory 3.2). An `s` of zero (a real
eigenvector) is an `ArgumentError`: the caller's guards must have excluded
it; the criterion "almost zero" is the caller's, scale-aware.
"""
function _orient_eigenvector(v::AbstractVector{<:Complex}, S::AbstractMatrix)
    s = imag(dot(v, S * v))
    s == 0 && throw(ArgumentError(
        "_orient_eigenvector: the symplectic norm Im(v' S v) vanishes; the eigenvector is neutral"))
    flipped = s > 0
    w = flipped ? conj(v) : v
    s = flipped ? -s : s
    return (u=sqrt(-2 / s) * w, s=s, flipped=flipped)
end

"""
    _conjugate_partner(rho, k) -> index

The index `l != k` whose eigenvalue is nearest to `conj(rho[k])`: the other
member of `k`'s conjugate pair (for a real `rho[k]` the nearest other real
or near-real eigenvalue).
"""
function _conjugate_partner(rho::AbstractVector{<:Complex}, k::Integer)
    best = 0; dist = Inf
    for l in eachindex(rho)
        l == k && continue
        dl = abs(rho[l] - conj(rho[k]))
        if dl < dist
            dist = dl; best = l
        end
    end
    return best
end

"""
    _conjugate_class_gap(rho) -> Float64

The complex gap between the conjugate classes of four eigenvalues (design
"Resolution criterion", pipeline step 4): over every pair `(k, l)` that are
NOT conjugate partners of each other, the smallest
`min(|rho_k - rho_l|, |rho_k - conj(rho_l)|)`. The conjugate distance is
included because equal traces can mean `mu_j = -mu_k`. Zero for
`R(a) (+) R(a)`.
"""
function _conjugate_class_gap(rho::AbstractVector{<:Complex})
    length(rho) == 4 || throw(ArgumentError("_conjugate_class_gap takes four eigenvalues, got $(length(rho))"))
    g = Inf
    for k in 1:4
        pk = _conjugate_partner(rho, k)
        for l in (k + 1):4
            l == pk && continue
            g = min(g, abs(rho[k] - rho[l]), abs(rho[k] - conj(rho[l])))
        end
    end
    return g
end

"""
    _mode_label_order(kappa_x_a, kappa_x_b) -> (first, second, margin)

The design's maximum-weight assignment on the signed-area array for two
modes: because each row of the array sums to one (M2), the assignment weight
`kappa_ax + kappa_by` exceeds `kappa_bx + kappa_ay` exactly when
`kappa_ax > kappa_bx`, so the mode with the larger `x` area is mode 1.
Returns the order `(1, 2)` or `(2, 1)` and the margin `|kappa_ax - kappa_bx|`;
a zero margin keeps the given order (a declared tie; labelling is a
heuristic that never feeds a Twiss value).
"""
function _mode_label_order(kappa_x_a::Real, kappa_x_b::Real)
    margin = abs(kappa_x_a - kappa_x_b)
    return kappa_x_b > kappa_x_a ? (2, 1, margin) : (1, 2, margin)
end

"""
    _projected_twiss(u) -> (beta, alpha, gamma, kappa)

(M1) for one (E3)-normalized eigenvector `u = (u_x, u_px, u_y, u_py)`: per
plane `a` (`1 = x`, `2 = y`) `beta_a = |u_a|^2`,
`alpha_a = -Re(conj(u_a) u_pa)`, `gamma_a = |u_pa|^2`,
`kappa_a = -Im(conj(u_a) u_pa)`, each a 2-vector over the planes. Phase
independent. `gamma` is NOT `(1 + alpha^2) / beta`: (M5) gives
`beta gamma - alpha^2 = kappa^2`, which is one only for an uncoupled plane.
"""
function _projected_twiss(u::AbstractVector{<:Complex})
    length(u) == 4 || throw(ArgumentError("_projected_twiss takes a 4-vector, got length $(length(u))"))
    beta = zeros(2); alpha = zeros(2); gamma = zeros(2); kappa = zeros(2)
    for a in 1:2
        q = u[2a - 1]; p = u[2a]
        prod = conj(q) * p
        beta[a] = abs2(q)
        alpha[a] = -real(prod)
        gamma[a] = abs2(p)
        kappa[a] = -imag(prod)
    end
    return (beta=beta, alpha=alpha, gamma=gamma, kappa=kappa)
end

"""
    _spectrum_report_4d(M, rho; min_gap, stability_atol) -> SpectrumReport4D

The [`SpectrumReport4D`](@ref) of `M` with its eigenvalues `rho`: moduli
and their unit-circle departure, the distance to a unit eigenvalue, the
conjugate-class gap, both discriminants ((T7) from the blocks with
`_adjugate2`, (E10) from the traces), the (E10) traces and the (T14) verdict.
"""
function _spectrum_report_4d(M::AbstractMatrix{<:Real}, rho::AbstractVector{<:Complex};
                             min_gap::Real, stability_atol::Real)
    moduli = abs.(rho)
    departure = maximum(abs.(moduli .- 1))
    unit_distance = minimum(min(abs(r - 1), abs(r + 1)) for r in rho)
    gap = _conjugate_class_gap(rho)
    Mxx = M[1:2, 1:2]; Mxy = M[1:2, 3:4]; Myx = M[3:4, 1:2]; Myy = M[3:4, 3:4]
    trM = tr(M)
    d_t7 = (tr(Mxx) - tr(Myy))^2 + 4 * det(_adjugate2(Mxy) + Myx)
    d_e10 = 2 * tr(M * M) - trM^2 + 8
    root = sqrt(complex(d_e10))
    taus = ((trM + root) / 2, (trM - root) / 2)
    t14 = d_e10 > 0 && all(abs(real(t)) < 2 for t in taus)
    return SpectrumReport4D(collect(ComplexF64, rho), moduli, departure, Float64(stability_atol),
                            unit_distance, gap, Float64(min_gap), trM, d_t7, d_e10,
                            (ComplexF64(taus[1]), ComplexF64(taus[2])), t14)
end

# ---------------------------------------------------------------------------
# The eigenvector route (E1)-(E8), (M1)-(M5).

const _EIGENMODE_ARGUMENT_HELP = "a real 4x4 matrix with finite entries, min_gap > 0 and stability_atol > 0"

function _check_eigenmode_arguments(M::AbstractMatrix, min_gap::Real, stability_atol::Real)
    size(M) == (4, 4) || throw(ArgumentError(
        "the 4D eigenmode route takes $(_EIGENMODE_ARGUMENT_HELP); got size $(size(M))"))
    all(isfinite, M) || throw(ArgumentError(
        "the 4D eigenmode route takes $(_EIGENMODE_ARGUMENT_HELP); the matrix has a non-finite entry"))
    (isfinite(min_gap) && min_gap > 0) || throw(ArgumentError(
        "the 4D eigenmode route takes $(_EIGENMODE_ARGUMENT_HELP); got min_gap = $(min_gap)"))
    (isfinite(stability_atol) && stability_atol > 0) || throw(ArgumentError(
        "the 4D eigenmode route takes $(_EIGENMODE_ARGUMENT_HELP); got stability_atol = $(stability_atol)"))
    return nothing
end

"""
    _eigenmodes_4d(M; min_gap, stability_atol) -> Eigenmodes4D

The 4D eigenmode route (theory (E1)-(E8), design pipeline steps 6, 8, 10)
for a real 4x4 matrix `M` the caller has already scaled. Two keyword
thresholds, both REQUIRED (no default is exported before the measurement
stage freezes one): `min_gap`, the smallest conjugate-class gap of
[`_conjugate_class_gap`](@ref) at which the two pairs count as resolved, and
`stability_atol`, the largest unit-circle departure of any eigenvalue at
which the spectrum counts as stable.

Order of the guards, each an unavailable `frame` with its pinned reason:

 1. `unit_circle_departure > stability_atol` gives `:unstable_spectrum`
    (the design's `diag(2, 1/2, R(1.2))` lands here, never in a Twiss).
    PROVISIONAL: stage 3 replaces this guard with the per-cluster Schur-block
    test.
 2. an eigenvalue within `stability_atol` of `+1` or `-1` gives
    `:unit_eigenvalue` (its eigenvector is real and has no orientation).
 3. `gap <= min_gap` gives `:cluster_unresolved`. PROVISIONAL: stage 3
    replaces this guard with the resolution chord.
 4. anything else that leaves the orientation rule without exactly one
    oriented member per class (a symplectic norm `|Im(v' S v)|` below
    `64 eps ||v||^2`, or two oriented members in one class) gives
    `:unresolved_defective` with the detail; the word defective is never
    asserted.

In the generic case the oriented vectors are normalized by (E4), labelled by
[`_mode_label_order`](@ref), and every field of [`NormalModeFrame4D`](@ref)
is formed: the (E6) normalizer, its (E7) residual, the (I1) reconstruction
residual against `diag(R(mu_1), R(mu_2))` (`_rotation2`, `_invariance_residual`),
`P_j`, `G_j`, the (M1) array and Twiss projections, the (M2)/(M3) sums and
both (M4) evaluations of `u`. The residuals are REPORTED, not judged: the
acceptance threshold on the normalized (I1) value belongs to the analysis
(stage 4), which reads it from the frame. Argument errors: any other size, a
non-finite entry, a non-positive or non-finite threshold.
"""
function _eigenmodes_4d(M::AbstractMatrix{<:Real}; min_gap::Real, stability_atol::Real)
    _check_eigenmode_arguments(M, min_gap, stability_atol)
    Mf = Matrix{Float64}(M)
    S = _symplectic_form(4)
    F = eigen(Mf)
    rho = Vector{ComplexF64}(F.values)
    V = Matrix{ComplexF64}(F.vectors)
    spectrum = _spectrum_report_4d(Mf, rho; min_gap=min_gap, stability_atol=stability_atol)
    unavailable(reason, detail) = Eigenmodes4D(spectrum, Determined{NormalModeFrame4D}(reason, detail))

    # Guard 1 (provisional; stage 3 replaces this guard with the per-cluster
    # Schur-block test): raw eigenvalue moduli against the unit circle.
    if spectrum.unit_circle_departure > stability_atol
        return unavailable(:unstable_spectrum,
            "largest unit-circle departure $(spectrum.unit_circle_departure) exceeds stability_atol $(stability_atol)")
    end
    # Guard 2: an eigenvalue at +-1 has a real eigenvector; no orientation.
    if spectrum.unit_eigenvalue_distance <= stability_atol
        return unavailable(:unit_eigenvalue,
            "an eigenvalue lies within $(stability_atol) of +1 or -1 (distance $(spectrum.unit_eigenvalue_distance))")
    end
    # Guard 3 (provisional; stage 3 replaces this guard with the resolution
    # chord): the two conjugate classes must be separated by more than min_gap.
    if spectrum.gap <= min_gap
        return unavailable(:cluster_unresolved,
            "conjugate-class gap $(spectrum.gap) does not exceed min_gap $(min_gap); the two pairs are one cluster")
    end

    # Orientation (E4): every eigensolver output with Im(v' S v) < 0 is an
    # oriented member. Exactly one per class is expected here. The roundoff
    # floor 64 eps ||v||^2 below is PROVISIONAL and unmeasured (no fixture
    # reaches this branch at the test thresholds; stage 2 record): stage 3
    # replaces it with the per-cluster Schur-block test.
    norms = [imag(dot(view(V, :, k), S * view(V, :, k))) for k in 1:4]
    scale = [64 * eps(Float64) * norm(view(V, :, k))^2 for k in 1:4]
    if any(abs(norms[k]) <= scale[k] for k in 1:4)
        return unavailable(:unresolved_defective,
            "an eigenvector has a symplectic norm |Im(v' S v)| = $(minimum(abs, norms)) at or below its roundoff scale; the pair is neutral within the map's accuracy")
    end
    oriented = [k for k in 1:4 if norms[k] < 0]
    if length(oriented) != 2 || _conjugate_partner(rho, oriented[1]) == oriented[2]
        return unavailable(:unresolved_defective,
            "the orientation rule selected $(length(oriented)) members ($(oriented)) instead of one per conjugate class")
    end

    us = [_orient_eigenvector(view(V, :, k), S).u for k in oriented]
    rhos = [rho[k] for k in oriented]
    tw = [_projected_twiss(u) for u in us]
    first, second, margin = _mode_label_order(tw[1].kappa[1], tw[2].kappa[1])
    order = (first, second)
    u1, u2 = us[order[1]], us[order[2]]
    rho1, rho2 = rhos[order[1]], rhos[order[2]]
    tw1, tw2 = tw[order[1]], tw[order[2]]

    mu = (mod(atan(-imag(rho1), real(rho1)), 2pi), mod(atan(-imag(rho2), real(rho2)), 2pi))
    U = hcat(real(u1), -imag(u1), real(u2), -imag(u2))
    Rblock = zeros(4, 4)
    Rblock[1:2, 1:2] .= _rotation2(mu[1])
    Rblock[3:4, 3:4] .= _rotation2(mu[2])
    recon = _invariance_residual(Mf, U, Rblock)
    sympl = norm(transpose(U) * S * U - S)
    outer1 = u1 * u1'; outer2 = u2 * u2'
    P = (-imag(outer1) * S, -imag(outer2) * S)
    G = (real(outer1), real(outer2))
    kappa = [tw1.kappa[1] tw1.kappa[2]; tw2.kappa[1] tw2.kappa[2]]
    beta = [tw1.beta[1] tw1.beta[2]; tw2.beta[1] tw2.beta[2]]
    alpha = [tw1.alpha[1] tw1.alpha[2]; tw2.alpha[1] tw2.alpha[2]]
    gamma = [tw1.gamma[1] tw1.gamma[2]; tw2.gamma[1] tw2.gamma[2]]
    u_eval = (kappa[1, 2], kappa[2, 1])
    frame = NormalModeFrame4D(Mf, (rho1, rho2), mu, (u1, u2),
        (abs(dot(u1, S * u1) + 2im), abs(dot(u2, S * u2) + 2im)),
        (_invariance_residual(Mf, u1, rho1), _invariance_residual(Mf, u2, rho2)),
        U, sympl, recon, P, G, kappa,
        (kappa[1, 1] + kappa[1, 2], kappa[2, 1] + kappa[2, 2]),
        (kappa[1, 1] + kappa[2, 1], kappa[1, 2] + kappa[2, 2]),
        beta, alpha, gamma, u_eval, u_eval[1] - u_eval[2], margin)
    return Eigenmodes4D(spectrum, Determined(frame))
end

# ---------------------------------------------------------------------------
# Normal coordinates and actions (E9).

"""
    _normal_coordinates(U4, r) -> Vector{Float64}

`xi = U_4^{-1} r` with the symplectic inverse `U_4^{-1} = -S_4 U_4' S_4`
(E7), no linear solve; `U4` must be 4x4 and `r` a real 4-vector.
"""
function _normal_coordinates(U4::AbstractMatrix{<:Real}, r::AbstractVector{<:Real})
    size(U4) == (4, 4) || throw(ArgumentError("_normal_coordinates: U4 must be 4x4, got $(size(U4))"))
    length(r) == 4 || throw(ArgumentError("_normal_coordinates: r must have length 4, got $(length(r))"))
    return _symplectic_inverse(U4) * Vector{Float64}(r)
end

"""
    _mode_actions(frame::NormalModeFrame4D, r) -> (from_normal_coordinates, from_vectors)

The two evaluations of (E9) for a real phase-space point `r`:
`J_j = (xi_{2j-1}^2 + xi_{2j}^2) / 2` from [`_normal_coordinates`](@ref), and
`J_j = |u_j' S_4 r|^2 / 2` from the oriented vectors. Both 2-tuples are
returned so their agreement (which rests on (E3) fixing the action scale)
can be checked rather than assumed; each is invariant under `M`.
"""
function _mode_actions(frame::NormalModeFrame4D, r::AbstractVector{<:Real})
    xi = _normal_coordinates(frame.normalizer, r)
    S = _symplectic_form(4)
    rf = Vector{Float64}(r)
    from_xi = ((xi[1]^2 + xi[2]^2) / 2, (xi[3]^2 + xi[4]^2) / 2)
    from_u = (abs2(dot(frame.vectors[1], S * rf)) / 2, abs2(dot(frame.vectors[2], S * rf)) / 2)
    return (from_normal_coordinates=from_xi, from_vectors=from_u)
end

# ---------------------------------------------------------------------------
# Closed-form extraction (E10)-(E14): a cross-check, never the primary route.

"""
    ClosedFormEigenmodes4D

The eigenmode quantities of theory 3.4 formed WITHOUT an eigenvector solve,
by [`_closed_form_eigenmodes_4d`](@ref), labelled by the same rule as the
frame. Fields: `traces` (`tau_j = 2 cos mu_j`), `tunes` (`mu_j` in
`[0, 2 pi)` with the sign of `sin mu_j` chosen so that `G_j` is positive
semidefinite, (E12): tunes above one half are kept), `sines`,
`projectors` (E11), `covariances` (E12), `covariance_min_eigenvalues` (the
smallest eigenvalue of each symmetrized `G_j`, the PSD margin),
`pivots` and `vectors` (E14, the pivot `b` is the largest diagonal entry of
`G_j`, made real and positive), `normalization_residuals` (`|u_j' S u_j + 2i|`
of those vectors), `projector_residuals` (`max(||P_j^2 - P_j||)`,
`||P_1 + P_2 - I||`, `||P_1 P_2||`), `normalizer` (the (E6) matrix
`U_cf = [Re u_1, -Im u_1, Re u_2, -Im u_2]` of the (E14) vectors),
`reconstruction_residual` (the (I1) form `_invariance_residual(M, U_cf,
diag(R(mu_1), R(mu_2)))`, `(normalized, raw)`, the same measure the frame
reports for its own normalizer), `signed_areas` (`kappa_ja = (P_j S)_{a,pa}`),
and `label_margin`.

The (E14) sum `sum_j cos(mu_j) P_j + sin(mu_j) G_j S` is NOT reported as a
residual: with (E11) and (E12) it equals `M` identically for ANY matrix and
ANY two distinct traces (`sum_j tau_j P_j = M + M^-1`, `sum_j P_j = I`, and
the sign choice cancels in `sin(mu_j) G_j`), so it cannot fail. The (I1)
residual on `U_cf` depends on the (E3) normalization, the pivot and the
(E12) sign choice, and does fail when any of them is wrong.
"""
struct ClosedFormEigenmodes4D
    traces::NTuple{2,Float64}
    tunes::NTuple{2,Float64}
    sines::NTuple{2,Float64}
    projectors::NTuple{2,Matrix{Float64}}
    covariances::NTuple{2,Matrix{Float64}}
    covariance_min_eigenvalues::NTuple{2,Float64}
    pivots::NTuple{2,Int}
    vectors::NTuple{2,Vector{ComplexF64}}
    normalization_residuals::NTuple{2,Float64}
    projector_residuals::NamedTuple{(:idempotent, :complete, :disjoint),Tuple{Float64,Float64,Float64}}
    normalizer::Matrix{Float64}
    reconstruction_residual::NamedTuple{(:normalized, :raw),Tuple{Float64,Float64}}
    signed_areas::Matrix{Float64}
    label_margin::Float64
end

"""
    _closed_form_eigenmodes_4d(M; min_trace_gap, stability_atol) -> Determined{ClosedFormEigenmodes4D}

(E10)-(E14) on a real 4x4 matrix `M` (already scaled). Both keywords are
REQUIRED: `min_trace_gap`, the smallest `|tau_+ - tau_-|` at which (E11)'s
denominator is trusted, and `stability_atol`, the same eigenvalue-distance
tolerance [`_eigenmodes_4d`](@ref) takes, applied here through the traces
so that both routes judge a spectrum on one scale: for `|tau| <= 2` the
distance of `e^{-i mu}` to `+-1` is `sqrt(2 - |tau|)` exactly, and for
`|tau| > 2` the unit-circle departure is `(|tau| + sqrt(tau^2 - 4)) / 2 - 1`.
Guards, each an unavailable value:

  * `|radicand| <= min_trace_gap^2`, i.e. `|tau_+ - tau_-| <= min_trace_gap`
    (for a negative radicand the traces are `(tr M +- i sqrt(-radicand)) / 2`
    and their distance is the same square root; coincident traces are what
    theory 3.4 excludes and stage 3's cluster machinery owns), gives
    `:singular_coefficient`, the design's status for the polynomial route
    near coincident traces (pipeline step 9); the vocabulary has no
    "coincident traces" member, and this choice is recorded in the stage 2
    record;
  * a negative radicand beyond that (complex traces: the eigenvalues have
    left the unit circle as a quartet) gives `:unstable_spectrum`;
  * a trace with `|tau_j| > 2` whose departure exceeds `stability_atol`
    gives `:unstable_spectrum`; a trace within `stability_atol` of `+-1` in
    the eigenvalue distance gives `:unit_eigenvalue` (`sin mu_j = 0`, which
    (E12) excludes).

The sign of `sin mu_j` is the one that makes `tr G_j > 0` (the trace of the
PSD rank-two `U_j U_j'`); its smallest eigenvalue is reported so a caller
can see that the choice produced a PSD matrix rather than trust it. Mode
labels follow [`_mode_label_order`](@ref) on `kappa_jx = (P_j S)_{x,px}`.
"""
function _closed_form_eigenmodes_4d(M::AbstractMatrix{<:Real}; min_trace_gap::Real, stability_atol::Real)
    size(M) == (4, 4) || throw(ArgumentError("_closed_form_eigenmodes_4d takes a 4x4 matrix, got $(size(M))"))
    all(isfinite, M) || throw(ArgumentError("_closed_form_eigenmodes_4d needs finite entries"))
    (isfinite(min_trace_gap) && min_trace_gap > 0) || throw(ArgumentError(
        "_closed_form_eigenmodes_4d needs min_trace_gap > 0, got $(min_trace_gap)"))
    (isfinite(stability_atol) && stability_atol > 0) || throw(ArgumentError(
        "_closed_form_eigenmodes_4d needs stability_atol > 0, got $(stability_atol)"))
    Mf = Matrix{Float64}(M)
    S = _symplectic_form(4)
    trM = tr(Mf)
    radicand = 2 * tr(Mf * Mf) - trM^2 + 8
    T = ClosedFormEigenmodes4D
    abs(radicand) <= min_trace_gap^2 && return Determined{T}(:singular_coefficient,
        "coincident eigenmode traces: |tau_+ - tau_-| = sqrt(|$(radicand)|) does not exceed min_trace_gap $(min_trace_gap); (E11) divides by it")
    radicand < 0 && return Determined{T}(:unstable_spectrum,
        "the (E10) radicand $(radicand) is negative: the eigenvalue traces are complex")
    root = sqrt(radicand)
    taus = [(trM + root) / 2, (trM - root) / 2]
    for t in taus
        if abs(t) > 2
            departure = (abs(t) + sqrt(t^2 - 4)) / 2 - 1
            departure > stability_atol && return Determined{T}(:unstable_spectrum,
                "an eigenmode trace $(t) exceeds 2 in magnitude: a hyperbolic mode with unit-circle departure $(departure)")
            return Determined{T}(:unit_eigenvalue,
                "an eigenmode trace $(t) is beyond +-2 by less than stability_atol $(stability_atol) in eigenvalue distance, so sin(mu) = 0 within tolerance")
        end
        sqrt(2 - abs(t)) <= stability_atol && return Determined{T}(:unit_eigenvalue,
            "an eigenmode trace $(t) puts the eigenvalue within stability_atol $(stability_atol) of +-1, so sin(mu) = 0 within tolerance")
    end
    Minv = _symplectic_inverse(Mf)
    Msum = Mf + Minv
    Mdiff = Mf - Minv
    Ps = Matrix{Float64}[]; Gs = Matrix{Float64}[]; sines = Float64[]; mins = Float64[]
    for j in 1:2
        k = 3 - j
        Pj = (Msum - taus[k] * I) / (taus[j] - taus[k])
        s0 = sqrt(1 - (taus[j] / 2)^2)
        G0 = -(Mdiff * Pj * S) / (2 * s0)
        sj = tr(G0) > 0 ? s0 : -s0
        Gj = tr(G0) > 0 ? G0 : -G0
        push!(Ps, Pj); push!(Gs, Gj); push!(sines, sj)
        push!(mins, eigmin(Symmetric((Gj + transpose(Gj)) / 2)))
    end
    kx = [(Ps[j] * S)[1, 2] for j in 1:2]
    first, second, margin = _mode_label_order(kx[1], kx[2])
    order = (first, second)
    P = (Ps[order[1]], Ps[order[2]]); G = (Gs[order[1]], Gs[order[2]])
    tau = (taus[order[1]], taus[order[2]]); sn = (sines[order[1]], sines[order[2]])
    mu = (mod(atan(sn[1], tau[1] / 2), 2pi), mod(atan(sn[2], tau[2] / 2), 2pi))
    pivots = (argmax(diag(G[1])), argmax(diag(G[2])))
    outer = (G[1] + im * P[1] * S, G[2] + im * P[2] * S)
    u = (outer[1][:, pivots[1]] / sqrt(G[1][pivots[1], pivots[1]]),
         outer[2][:, pivots[2]] / sqrt(G[2][pivots[2], pivots[2]]))
    nres = (abs(dot(u[1], S * u[1]) + 2im), abs(dot(u[2], S * u[2]) + 2im))
    pres = (idempotent=max(norm(P[1] * P[1] - P[1]), norm(P[2] * P[2] - P[2])),
            complete=norm(P[1] + P[2] - I), disjoint=norm(P[1] * P[2]))
    # (E6) on the (E14) vectors and the (I1) residual of M U_cf = U_cf diag(R(mu)).
    # Not the (E14) sum, which is an identity of (E11)/(E12) (see the docstring).
    Ucf = hcat(real(u[1]), -imag(u[1]), real(u[2]), -imag(u[2]))
    Rblock = zeros(4, 4)
    Rblock[1:2, 1:2] .= _rotation2(mu[1])
    Rblock[3:4, 3:4] .= _rotation2(mu[2])
    rres = _invariance_residual(Mf, Ucf, Rblock)
    kappa = [(P[1] * S)[1, 2] (P[1] * S)[3, 4]; (P[2] * S)[1, 2] (P[2] * S)[3, 4]]
    return Determined(ClosedFormEigenmodes4D(tau, mu, sn, P, G, (mins[order[1]], mins[order[2]]),
        pivots, u, nres, pres, Ucf, (normalized=rres.normalized, raw=rres.raw), kappa, margin))
end

"""
    ClosedFormCheck4D

The closed-form cross-check of a [`NormalModeFrame4D`](@ref): the
[`ClosedFormEigenmodes4D`](@ref) `closed_form` and its disagreement with the
eigenvector route, each the largest over the two modes: `tune_difference`
(`|mu_p(j)^cf - mu_j|`), `projector_difference` (`||P_p(j)^cf - P_j||_F`),
`covariance_difference` (`||G_p(j)^cf - G_j||_F`), `outer_product_difference`
(`||u^cf u^cf' - u_j u_j'||_F`, phase free), and `signed_area_difference`
(`max |kappa^cf - kappa|` over the matched rows). `mode_permutation = p` is
the matching of closed-form modes to frame modes by the eigenvalue trace
(`p` minimizes `sum_j |tau_p(j)^cf - 2 cos mu_j|` over the two orders), NOT
by the label rule: both routes label mode 1 = larger `kappa_jx`, but at a
tie (`u = 1/2`, det R = 1, e.g. a 45-degree roll of an uncoupled cell) each
route keeps its own given order and a label-based comparison reports an
O(1) disagreement between identical modes. `label_margins` are
`(frame.label_margin, closed_form.label_margin)`, so a caller sees when the
labels themselves were undecided. A disagreement is reported, never
averaged (design "The decision").
"""
struct ClosedFormCheck4D
    closed_form::ClosedFormEigenmodes4D
    mode_permutation::NTuple{2,Int}
    label_margins::NTuple{2,Float64}
    tune_difference::Float64
    projector_difference::Float64
    covariance_difference::Float64
    outer_product_difference::Float64
    signed_area_difference::Float64
end

"""
    _closed_form_check_4d(frame::NormalModeFrame4D; min_trace_gap, stability_atol) -> Determined{ClosedFormCheck4D}

Runs [`_closed_form_eigenmodes_4d`](@ref) on `frame.matrix`, matches its
modes to the frame's by the eigenvalue trace ([`_closed_form_mode_permutation`](@ref);
the label rule is NOT used for the matching, see [`ClosedFormCheck4D`](@ref))
and compares matched mode to matched mode. When the closed form is
unavailable, the check is unavailable with that reason and detail.
"""
function _closed_form_check_4d(frame::NormalModeFrame4D; min_trace_gap::Real, stability_atol::Real)
    cf = _closed_form_eigenmodes_4d(frame.matrix; min_trace_gap=min_trace_gap, stability_atol=stability_atol)
    is_determined(cf) || return Determined{ClosedFormCheck4D}(cf.reason, cf.detail)
    c = determined_value(cf)
    p = _closed_form_mode_permutation(c.traces, frame.tunes)
    tune_d = maximum(abs(c.tunes[p[j]] - frame.tunes[j]) for j in 1:2)
    proj_d = maximum(norm(c.projectors[p[j]] - frame.projectors[j]) for j in 1:2)
    cov_d = maximum(norm(c.covariances[p[j]] - frame.covariances[j]) for j in 1:2)
    outer_d = maximum(norm(c.vectors[p[j]] * c.vectors[p[j]]' - frame.vectors[j] * frame.vectors[j]') for j in 1:2)
    kappa_d = maximum(abs.(c.signed_areas[[p[1], p[2]], :] - frame.signed_areas))
    return Determined(ClosedFormCheck4D(c, p, (frame.label_margin, c.label_margin),
                                        tune_d, proj_d, cov_d, outer_d, kappa_d))
end

"""
    _closed_form_mode_permutation(traces, tunes) -> (p1, p2)

The order `p` of the closed-form modes that matches them to the frame's modes
by the eigenvalue trace: `(1, 2)` when `|tau_1 - 2 cos mu_1| + |tau_2 - 2 cos mu_2|`
does not exceed the crossed sum, else `(2, 1)`. A trace is a class invariant
(it does not depend on the orientation or the label of a mode), so the match
is well defined whenever the traces are distinct, which the closed form's
coincident-trace guard already requires.
"""
function _closed_form_mode_permutation(traces, tunes)
    t = (2 * cos(tunes[1]), 2 * cos(tunes[2]))
    straight = abs(traces[1] - t[1]) + abs(traces[2] - t[2])
    crossed = abs(traces[2] - t[1]) + abs(traces[1] - t[2])
    return straight <= crossed ? (1, 2) : (2, 1)
end
