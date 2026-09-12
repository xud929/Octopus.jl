# Mode clusters, Krein classification, per-cluster stability and the
# resolution chord of the coupled Twiss analysis: theory
# docs/theory/twiss_dispersion.md Section 13 (13.2 Gram and Krein signature,
# 13.4 group quantities N4-N9, 13.8 numerical handling N19-N22, 13.10 the
# rolled FODO); design docs/design/twiss_dispersion_analysis.md "Pipeline"
# steps 4-7 and "Resolution criterion". Stage 3 of the campaign (design
# "Staging", item 3). Pure matrix arithmetic on a real 4x4 or 6x6 matrix the
# caller has ALREADY scaled (design "Input boundary" item 5): no scaling here;
# the stage 1 `_unscale_*` table transforms P_c, G_c back. This file defines
# no `analyze`, no analysis type and no export; the public verb is `analyze`
# of twiss_dispersion_analysis.jl (stage 4b).
#
# Conventions (theory Sections 2, 3 and 13): oriented eigenvalue
# rho_j = e^{-i mu_j}, u_j' S u_j = -2i (E3); the half-cluster basis Q_c is
# one member of each conjugate pair from an ordered complex Schur
# decomposition; H_c = (i/2) Q_c' S Q_c (N2); U_c = Q_c H_c^{-1/2} (N20);
# P_c = -Im(U_c U_c') S, G_c = Re(U_c U_c') (N5); T_c = (i/2) U_c' S M U_c
# (N21); r_mp = ||(M^2 - tau_c M + I) P_c||_F / ||M||_F^2 (N19); the chord
# q = min(2, 2 kappa rho_M1 / g) (N22, design "Resolution criterion").
#
# Every threshold constant below is PROVISIONAL until the stage 3 measurement
# (campaign record, stage 3 section) freezes it; each docstring names the
# fixtures that set it. The orchestrator's decisions D1-D11 (stage 3 dossier)
# fix the order of operations; the file follows them.

"""
    CLUSTER_CLASSIFICATIONS

Every classification a [`ModeCluster`](@ref) may carry. Pinned against the
source in the suite the way `DETERMINATION_REASONS` is; the suite also checks
that this docstring lists exactly the declared members.

  * `:definite` -- the half-cluster Gram form (N2) is definite (positive
    after the orientation choice); the cluster has a normalized frame (N20),
    group projector and covariance (N5); its individual modes are unique when
    `resolved` and a convention otherwise.
  * `:indefinite` -- the Gram form has both signs above the floor and the
    minimal-polynomial residual (N19) certifies a semisimple repeated
    eigenvalue; a signed basis is kept, no covariance (theory 13.2, 13.8).
  * `:unresolved` -- the accuracy of the map cannot classify the cluster
    (a Gram eigenvalue at the floor, or the minimal-polynomial residual above
    its tolerance, or a failed pairing); possibly defective, never asserted so.
  * `:unstable` -- the whole Schur block leaves the unit circle by more than
    its perturbation scale (design step 6); no modal output.
  * `:unit_eigenvalue` -- a real-class cluster at +1 or -1 (theory (D23)
    territory); flagged, never a mode.
"""
const CLUSTER_CLASSIFICATIONS = (:definite, :indefinite, :unresolved, :unstable, :unit_eigenvalue)

"""
    _DEFAULT_RESOLUTION_CHORD

The default of the resolution chord `q = min(2, 2 kappa rho_M1 / g)` (N22):
a pair of modes is resolved iff `q <= _DEFAULT_RESOLUTION_CHORD`. Policy,
not physics (design "Resolution criterion", "Default value"): PROVISIONAL in
the design's sense (a measured policy constant, re-measured whenever the
fixture table changes), FROZEN by the stage 3 measurement (2026-09-12, Part D1, OUT/measure/measure_stage3.jl in
package mode at roundoff `rho_M0`; the table travels in the campaign
record). Bracket = [largest chord of a control that must resolve, smallest
chord of a control that must not]. Largest must-resolve chord: the rolled
FODO of theory 13.10 detuned by 1e-9 (periodic tune error 4.45e-9 in the
working notes), `q = 2 * 11.93 * 2.647e-15 / 2.134e-9 = 2.960e-5`
(`kappa_frame = 11.93`: the design's unit-kappa estimate 2.5e-6 did not
count the FODO's Gram conditioning); the other must-resolve controls (FODO
1e-6 and 1e-3, the 24 dense oracle maps) sit at 2.96e-8 and below. Smallest
must-not-resolve chord: the same FODO detuned by 1e-12 (tune error 5.89e-6),
`q = 2 * 11.93 * 2.647e-15 / 2.135e-12 = 2.959e-2`. Geometric mean
`sqrt(2.960e-5 * 2.959e-2) = 9.36e-4`; the design's rounding (its own
example: 7.9e-5 "rounds to 1e-4", i.e. to a power of ten) gives `1e-3`
(the strict one-significant-digit reading would be 9e-4). The bracket
contains the provisional 1e-4 but the rounded mean differs, so the measured
value wins (design "Default value": "the same for a different rounded mean
inside the bracket: record it"). Margins at 1e-3: the 1e-9 control resolves
at ratio 0.030 of the default, the 1e-12 control stays merged at ratio 29.6.
No unlabelled fixture of the chord table (464 fixtures, 1177 clusters) has a
chord inside the bracket; the block-diagonal near collision
`diag(R(0.73), R(1.41), R(-0.73 - 1e-9))` resolves at q = 5.3e-6 (kappa_eig
= 2 exactly, separable modes) and the crab ladder `k = k_c (1 - 1e-9)`
resolves at q = 2.8e-5.
"""
const _DEFAULT_RESOLUTION_CHORD = 1.0e-3

"""
    _REAL_CLASS_MULTIPLIER

`c_real` of `tau_real = c_real * sqrt(rho_M1) * max(1, ||M||_2)`: an
eigenvalue with `|Im rho| <= tau_real` is real-class (self-conjugate, no
Krein orientation; dossier D2). The square root: a +-1 Jordan pair (a
drift's (z, pz) block) splits by the square root of the perturbation.
PROVISIONAL (a measured multiplier, re-measured whenever the fixture table
changes); measured 2026-09-12 (Part D1, OUT/measure/measure_stage3.jl, package mode;
ratio = |Im rho| / (sqrt(rho_M1) max(1, ||M||_2)) over every eigenvalue of
the chord table's 464 fixtures and the docstring fixtures, names printed
from the rows): largest accepted (real-class) ratio 0.0204 at the rotated
drift `W4 ([1 3; 0 1] (+) R(1.2)) W4^-1` (its +1 Jordan pair splits into a
complex pair of size sqrt(roundoff)); smallest rejected (complex-class)
ratio 33.6 at `R(1e-6) (+) R(1.2)` (the detuned FODO controls and the crab
ladder sit at 1e6 and above). Window by the one-tenth / ten rule
[0.204, 3.36]; A1's provisional `4` lay outside it (rejected margin 8.4 < 10)
and was moved to `1` (margins: accepted 49, rejected 33.6).
"""
const _REAL_CLASS_MULTIPLIER = 1.0

"""
    _STABILITY_MULTIPLIER

`c_stab` of the per-cluster scale `delta_c = c_stab * kappa_c * max(rho_M1,
(rho_M1 * dep_c^(m - 1))^(1/m))` on the half block of a cluster (dossier D5
as amended 2026-09-12 by the theory review: `kappa_c` is the cluster's Krein
conditioning, `kappa_frame` for a Gram-definite half, `kappa_eig` when every
member is orientable alone, `1` for a real-class or Krein-isotropic block;
theory 13.8 "normalizer conditioning", 13.9 "a degenerate but bounded map
should not be labeled unstable"). A cluster is unstable iff every member's
`||rho| - 1|` exceeds `delta_c`. PROVISIONAL; measured (OUT/fixer/
probe_measure.jl, ratio = departure / (delta_c / c_stab)) on the defective
spectator and its random symplectic conjugations (4D, 6D), the exact FODO
and its four detuned controls, the unit-eigenvalue fixtures and the rotated
drift, the crab ladder `k = k_c (1 - eps)`, eps = 1e-1 .. 1e-11 (the stable
side of the Krein collision, whose singleton eigenvalues leave the circle by
`eps_mach ||M|| kappa / 2` with kappa up to 1.4e5) and the 200 + 200
manufactured stable maps (accepted) against `diag(1 + 1e-6, 1/(1 + 1e-6),
R(1.2))`, `diag(2, 1/2, R(1.2))`, the complex quartet with `|lambda| - 1 =
1e-4` and the crab ladder's unstable side eps = -1e-2 .. -1e-7 (rejected).
Measured 2026-09-12 (fixer): largest accepted ratio 0.518 (the rotated
defective spectator, through the Jordan term; the manufactured maps reach
0.479), smallest rejected 1886 (crab eps = -1e-7; the 1e-6 hyperbolic pair
1.1e9), window [5.2, 189] by the one-tenth / ten rule; `64` keeps the
accepted ratio at 8.1e-3 and the rejected at 29. A1's earlier `256` was
chosen without `kappa_c` (accepted extreme 21.3 on manufactured 6D trial 1,
the same conditioning mechanism) and lies outside the amended window. Not
labelled: the crab ladder at eps = -1e-9 (unstable by 2.2e-6 against a
Jordan-term scale 7.7e-7 at 64), reported for Part D.
"""
const _STABILITY_MULTIPLIER = 64.0

"""
    _GRAM_FLOOR_MULTIPLIER

`c_gram` of the Gram floor `floor(c) = c_gram * rho_M1(c) / g_ext(c)` below
which a Gram eigenvalue has no sign (dossier D6): the Gram of an orthonormal
basis moves by the map error over the separation of the selected subspace
from its complement. PROVISIONAL; measured on every definite fixture
(accepted: smallest |lambda| over the floor) against the neutral vectors of
the defective spectator and the off-circle fixtures (rejected). Measured
2026-09-12 (A1): smallest accepted `min |lambda| / (rho_M1 / g_ext)` is
3.8e5 (the near collision, g_ext = 1e-9), 6.7e10 (FODO detuned 1e-3) and
1.4e13 (exact FODO). No fixture in the table produces a rejected value: the
defective spectator's Gram is +-1/2 (it is rejected by the minimal
polynomial, not by the floor) and the off-circle clusters are decided by
the stability test before the Gram is formed.
"""
const _GRAM_FLOOR_MULTIPLIER = 64.0

"""
    _MINIMAL_POLYNOMIAL_MULTIPLIER

`c_mp` of `mp_tol(c) = c_mp * max(rho_M1(c), g_int(c)) * ||P_c||_2 / ||M||_F`
(dossier D7b): a semisimple cluster split by `g_int` has `r_mp` (N19) of
order `g_int / ||M||`; a Jordan block has `r_mp` of order its nilpotent part.
PROVISIONAL; measured on the indefinite fixture and the near collision
(accepted) against the defective spectator (rejected). Measured 2026-09-12
(A1): largest accepted `r_mp / (max(rho_M1, g_int) ||P||_2 / ||M||_F)` is
0.23 (conjugated definite m = 2 fixture and the FODO 1e-12 control; the
indefinite fixture 0.068); the rejected defective spectator gives 1.9e14.
With 64: accepted ratio 3.6e-3, rejected 3e12.
"""
const _MINIMAL_POLYNOMIAL_MULTIPLIER = 64.0

"""
    _SUBSPACE_RESIDUAL_MULTIPLIER

`c_sub` of `sub_tol = c_sub * d * eps`: the invariant-subspace residual
`||M Q_c - Q_c T_c||_F / max(1, ||M||_F)` of an ordered Schur basis is
backward-stable roundoff; a cluster above it is `:unresolved` (dossier D7a).
PROVISIONAL; measured on every fixture (accepted side only; the rejected
side is an injected non-invariant basis). Measured 2026-09-12 (A1): the
largest `r_sub / (d eps)` over the fixture table and the 200 + 200
manufactured maps is 1.28 (ratio 0.02 to the multiplier).
"""
const _SUBSPACE_RESIDUAL_MULTIPLIER = 64.0

# ---------------------------------------------------------------------------
# Result structs (runtime representation; the analysis object of stage 4 is
# the stable surface).

const _CLUSTER_RESIDUALS_T = NamedTuple{(:subspace, :minimal_polynomial, :projector_idempotent,
                                         :projector_commutes, :projector_adjoint), NTuple{5,Float64}}
"""
    _CLUSTER_RESIDUALS_T

The NamedTuple type of `ModeCluster.residuals` (dossier D8, split from D8's
single tuple with `_FRAME_RESIDUALS_T` because the frame residuals exist only
for a definite or indefinite cluster): `subspace`, `minimal_polynomial`,
`projector_idempotent`, `projector_commutes`, `projector_adjoint`.
"""
_CLUSTER_RESIDUALS_T

"""
    _FRAME_RESIDUALS_T

The NamedTuple type of `ModeCluster.frame_residuals`: `normalization`
`||W' S W + 2i I||_F`, `isotropy` `||W^T S W||_F`, `unitarity`
`||T' T - I||_F` of the restricted map on the basis, and `eigenvector`, the
13.8 reconstruction check `_column_eigenvector_residual` (the largest
normalized (I1) residual of a column against the eigenvalue paired with it
by index). `W` is the frame `U_c` of a definite cluster (rotated when
resolved) or the signed basis of an indefinite one.
"""
const _FRAME_RESIDUALS_T = NamedTuple{(:normalization, :isotropy, :unitarity, :eigenvector), NTuple{4,Float64}}

"""
    _RESOLUTION_RECEIPT_T

The NamedTuple type of one `ModeClusters.resolution_receipt` entry (dossier
D6): the two components `first`, `second`, their `gap`, the `kappa` used and
its `kappa_source` (`:frame`, `:eigenvectors`, `:none`), `rho_M1`, the
`chord`, and `merged`.
"""
const _RESOLUTION_RECEIPT_T = NamedTuple{(:first, :second, :gap, :kappa, :kappa_source, :rho_M1, :chord, :merged),
                                         Tuple{Vector{Int},Vector{Int},Float64,Float64,Symbol,Float64,Float64,Bool}}

"""
    ClusterMode

One individual mode recovered from a definite cluster (dossier D7e; an
`m = 1` cluster has exactly one): `index` (position in the report's
eigenvalue list), `eigenvalue` (oriented, `e^{-i mu}`), `tune` (`mu` in
`[0, 2 pi)`), `vector` (the (E3)-normalized oriented eigenvector, a column of
the rotated frame), `eigenvector_residual` (the (I1) vector form of
`M u - rho u`, normalized and raw, `_invariance_residual`), and
`normalization_residual` (`|u' S u + 2i|`).
"""
struct ClusterMode
    index::Int
    eigenvalue::ComplexF64
    tune::Float64
    vector::Vector{ComplexF64}
    eigenvector_residual::NamedTuple{(:normalized, :raw),Tuple{Float64,Float64}}
    normalization_residual::Float64
end

"""
    ModeCluster

One cluster of the spectrum of a real symplectic matrix (theory Section 13,
design "Pipeline" steps 4-7; dossier D4-D8). Fields:

  * `members`, `half_members`: indices into the report's canonical eigenvalue
    list; the half holds one member of each conjugate pair (`Im rho > 0`
    before orientation) and is empty for a real-class cluster.
  * `eigenvalues`, `tunes`: the half's ORIENTED eigenvalues `e^{-i mu}` and
    tunes after the Gram decides the orientation (for a real-class cluster
    the members' eigenvalues and empty tunes).
  * `classification` in [`CLUSTER_CLASSIFICATIONS`](@ref); `reason` in
    `DETERMINATION_REASONS` (`:none` for a resolved definite cluster,
    `:cluster_unresolved` for a definite unresolved group,
    `:indefinite_cluster`, `:unresolved_defective`, `:unstable_spectrum`,
    `:unit_eigenvalue`); `detail` the human sub-reason; `conjugated` whether
    the half was conjugated because the Gram was negative definite.
  * `schur_basis` `Q_c` (d x m, orthonormal), `half_block` `T_c` (m x m),
    `full_block` (all members, a diagnostic that decides nothing),
    `departure_from_normality` (Henrici, of the half block),
    `stability_scale` `delta_c` (dossier D5), `unit_circle_departures`
    (`abs(abs(rho) - 1)` per member).
  * `gram_matrix` `H_c`, `gram_eigenvalues` (ascending), `krein_signs`
    (`+1`, `-1`, or `0` at or below `gram_floor`); empty for a real-class
    or unstable cluster.
  * `frame`: `U_c` (N20), unique for a definite cluster (the recovered
    per-mode vectors when `resolved`, else the N20 group basis whose columns
    are eigenvectors only at exact degeneracy); `signed_basis`: the columns
    of an indefinite cluster, each normalized to `-2i` after conjugating the
    negative-sign ones (13.8); unavailable with `:not_derived_for_cluster`
    for a definite cluster. The `eigenvalues` are paired with the columns of
    `frame` or `signed_basis` BY INDEX; that pairing is an eigen-pairing
    only when the cluster is resolved or `internal_gap` is at the map error
    (`frame_residuals.eigenvector` reports the (I1) residual of the pairing;
    for a split group the columns are a basis of the invariant subspace,
    not eigenvectors, 13.8). `projector`: the real Schur
    spectral projector `P_c = 2 Re Pi_c` (N9), unique for every stable
    complex-class cluster; `projector_n5_difference`: `||P_c(N5) - P_c(Schur)||_F`
    for a definite cluster; `covariance`: `G_c` (N5), definite only;
    `restricted_map`: `T_c` of (N21), definite only.
  * `residuals` (`_CLUSTER_RESIDUALS_T`: subspace, minimal_polynomial,
    projector_idempotent, projector_commutes, projector_adjoint), unique for
    every stable complex-class cluster; `frame_residuals`
    (`_FRAME_RESIDUALS_T`: normalization `||W' S W + 2i I||_F`, isotropy
    `||W^T S W||_F`, unitarity `||T' T - I||_F`, eigenvector (the 13.8
    reconstruction check, `_column_eigenvector_residual`) of the frame `W =
    U_c` (definite) or the signed basis (indefinite)); unavailable otherwise.
  * `rho_M1`, `kappa_frame` (`1 / lambda_min(H_c)`, definite only),
    `kappa_eig` (`||[u_j]||_2^2` of the individually normalized members,
    when each is orientable alone; else unavailable with
    `:cluster_unresolved`, an individual-member quantity the group does not
    support), `internal_gap`, `external_gap` (dossier D3), `chord_matrix`
    (m x m internal chords, zero diagonal), `resolved`, `forced` (the chord
    `Inf` decided `resolved` for a cluster the frozen default would have
    left unresolved, dossier D1 "every cluster it affected"), `modes`
    (unique when resolved, else unavailable with the cluster's reason).
    `stability_scale` is `c_stab * kappa_c * max(rho_M1, (rho_M1
    dep^(m-1))^(1/m))` with `kappa_c` = `kappa_frame` (Gram-definite half),
    `kappa_eig` (members orientable alone) or 1 (D5 as amended 2026-09-12).
"""
struct ModeCluster
    members::Vector{Int}
    half_members::Vector{Int}
    eigenvalues::Vector{ComplexF64}
    tunes::Vector{Float64}
    classification::Symbol
    reason::Symbol
    detail::String
    conjugated::Bool
    schur_basis::Matrix{ComplexF64}
    half_block::Matrix{ComplexF64}
    full_block::Matrix{ComplexF64}
    departure_from_normality::Float64
    stability_scale::Float64
    unit_circle_departures::Vector{Float64}
    gram_matrix::Matrix{ComplexF64}
    gram_eigenvalues::Vector{Float64}
    krein_signs::Vector{Int}
    gram_floor::Float64
    frame::Determined{Matrix{ComplexF64}}
    signed_basis::Determined{Matrix{ComplexF64}}
    projector::Determined{Matrix{Float64}}
    projector_n5_difference::Determined{Float64}
    covariance::Determined{Matrix{Float64}}
    restricted_map::Determined{Matrix{ComplexF64}}
    residuals::Determined{_CLUSTER_RESIDUALS_T}
    frame_residuals::Determined{_FRAME_RESIDUALS_T}
    rho_M1::Float64
    kappa_frame::Determined{Float64}
    kappa_eig::Determined{Float64}
    internal_gap::Float64
    external_gap::Float64
    chord_matrix::Matrix{Float64}
    resolved::Bool
    forced::Bool
    modes::Determined{Vector{ClusterMode}}
end

"""
    ModeClusters

What [`_mode_clusters`](@ref) returns (dossier D8). Fields: `matrix` (the
scaled matrix analysed, a copy); `eigenvalues` in the CANONICAL order
(ascending `mod(angle, 2 pi)`, then modulus; every index in this file refers
to this order); `conjugate_partner` (index of each eigenvalue's conjugate
partner, `0` for a real-class eigenvalue); `real_class` (mask, dossier D2);
`tau_real`; `schur_backward_error` (`||M Z - Z T||_F` of the one complex
Schur decomposition); `rho_M0` (the caller's first perturbation scale);
`rho_M1` (the largest per-cluster second scale); `resolution_chord`;
`partition_source` (`:auto` or `:explicit`); `clusters`;
`resolution_receipt` (every candidate merge evaluated: the two components,
their gap, the kappa used and its source `:frame`, `:eigenvectors` or
`:none`, `rho_M1`, the chord, and whether they merged; empty under an
explicit partition); `inter_cluster_chords` (the last round's chord between
every pair of final clusters, zero diagonal); `degeneracy_status`, the worst
case present in order `:all_resolved < :degenerate < :indefinite <
:unresolved < :unit_eigenvalue < :unstable` (`:degenerate` = a definite
cluster that did not resolve).
"""
struct ModeClusters
    matrix::Matrix{Float64}
    eigenvalues::Vector{ComplexF64}
    conjugate_partner::Vector{Int}
    real_class::BitVector
    tau_real::Float64
    schur_backward_error::Float64
    rho_M0::Float64
    rho_M1::Float64
    resolution_chord::Float64
    partition_source::Symbol
    clusters::Vector{ModeCluster}
    resolution_receipt::Vector{_RESOLUTION_RECEIPT_T}
    inter_cluster_chords::Matrix{Float64}
    degeneracy_status::Symbol
end

# ---------------------------------------------------------------------------
# Spectrum, classes, pairing, gaps (dossier D2-D3).

"""
    _canonical_spectrum(M) -> (schur, eigenvalues, order, backward_error, matrix)

One complex Schur decomposition `schur(complex(M))` and its diagonal in the
canonical order (ascending `mod(angle(rho), 2 pi)`, then `abs(rho)`);
`order[k]` is the Schur-diagonal position of canonical eigenvalue `k`
(so `select = falses(d); select[order[idx]] .= true` builds an `ordschur`
selection for canonical indices `idx`); `backward_error = ||M Z - Z T||_F`;
`matrix` the `Float64` copy of `M` that every per-cluster residual is
measured against.
"""
function _canonical_spectrum(M::AbstractMatrix{<:Real})
    Mf = Matrix{Float64}(M)
    F = schur(complex(Mf))
    rho = Vector{ComplexF64}(diag(F.T))
    order = sortperm(collect(1:length(rho)); by=k -> (mod(angle(rho[k]), 2pi), abs(rho[k])))
    return (schur=F, eigenvalues=rho[order], order=order, backward_error=norm(Mf * F.Z - F.Z * F.T), matrix=Mf)
end

"""
    _pair_gap(a, b) -> Float64

The complex gap `min(|a - b|, |a - conj(b)|)` between two eigenvalues (design
step 4; the conjugate distance because equal traces can mean `mu_j = -mu_k`).
"""
_pair_gap(a::Number, b::Number) = min(abs(a - b), abs(a - conj(b)))

"""
    _real_class_mask(rho, tau_real) -> BitVector

`|Im rho_j| <= tau_real` per eigenvalue (dossier D2).
"""
_real_class_mask(rho::AbstractVector{<:Complex}, tau_real::Real) = BitVector(abs(imag(r)) <= tau_real for r in rho)

"""
    _conjugate_pairs(rho, real_class, tau_real) -> (partner, ok)

For every complex-class eigenvalue `j`, `partner[j]` is the complex-class
`k != j` nearest to `conj(rho[j])`; `partner[j] = 0` for a real-class
eigenvalue. `ok` is false when the pairing is not a perfect matching
(`partner[partner[j]] != j`) or a partner lies farther than `tau_real` from
the conjugate (dossier D2: then the whole complex class is one unresolved
cluster with detail "conjugate pairing failed").
"""
function _conjugate_pairs(rho::AbstractVector{<:Complex}, real_class::BitVector, tau_real::Real)
    n = length(rho)
    partner = zeros(Int, n)
    ok = true
    # Greedy matching in canonical order: a repeated pair (two copies of the
    # same conjugate pair) has two equally near conjugates, so the partner
    # search runs over the still UNMATCHED complex-class members only.
    for j in 1:n
        (real_class[j] || partner[j] != 0) && continue
        best = 0; bestdist = Inf
        for k in 1:n
            (k == j || real_class[k] || partner[k] != 0) && continue
            dist = abs(rho[k] - conj(rho[j]))
            if dist < bestdist
                best = k; bestdist = dist
            end
        end
        if best == 0 || bestdist > tau_real
            ok = false
            best == 0 && continue
        end
        partner[j] = best; partner[best] = j
    end
    for j in 1:n
        real_class[j] && continue
        (partner[j] != 0 && partner[partner[j]] == j) || (ok = false)
    end
    return (partner=partner, ok=ok)
end

"""
    _cluster_gap(rho, c1, c2) -> Float64

`min` of [`_pair_gap`](@ref) over `j in c1, k in c2` (dossier D3).
"""
_cluster_gap(rho::AbstractVector{<:Complex}, c1::AbstractVector{<:Integer}, c2::AbstractVector{<:Integer}) =
    minimum(_pair_gap(rho[j], rho[k]) for j in c1 for k in c2)

"""
    _external_gap(rho, half) -> Float64

The separation of the selected complex invariant subspace from its
complement: `min |rho_j - rho_k|` over `j in half` and every `k` NOT in
`half` (the cluster's own conjugates count; dossier D3). `Inf` when `half`
is the whole spectrum (cannot happen for a real symplectic matrix).
"""
function _external_gap(rho::AbstractVector{<:Complex}, half::AbstractVector{<:Integer})
    others = setdiff(eachindex(rho), half)
    isempty(others) && return Inf
    return minimum(abs(rho[j] - rho[k]) for j in half for k in others)
end

# ---------------------------------------------------------------------------
# Ordered Schur basis, Gram matrix, spectral projector, chord (theory 13.8,
# N2, N9, N22).

"""
    _ordered_schur_basis(F::Schur, select::AbstractVector{Bool}, M) -> (Q, T11, T12, T22, Z, values, backward_error)

`ordschur(F, select)` moves the selected eigenvalues to the leading block:
`Q = Z[:, 1:m]` is an orthonormal basis of their invariant subspace,
`T11` its `m x m` block, `T12` and `T22` the rest, `values` the selected
eigenvalues in the reordered diagonal, `backward_error = ||M Q - Q T11||_F`
against the INPUT matrix `M` that `F` factorizes (dossier D5, design step
5; the caller compares it with `||M||`). It is NOT measured against the
reconstruction `Z T Z'`, which satisfies `Z T Z' Q = Q T11` identically and
would only show product roundoff (review 2026-09-12, finding 1.7). Exactly
one member of each conjugate pair is selected for a half-cluster basis; all
members for a stability block.
"""
function _ordered_schur_basis(F::Schur, select::AbstractVector{Bool}, M::AbstractMatrix)
    m = count(select)
    m >= 1 || throw(ArgumentError("_ordered_schur_basis needs at least one selected eigenvalue"))
    size(M) == size(F.Z) || throw(ArgumentError("_ordered_schur_basis: M is $(size(M)) but the factorization is $(size(F.Z))"))
    Fo = ordschur(F, BitVector(select))
    Z = Matrix{ComplexF64}(Fo.Z); T = Matrix{ComplexF64}(Fo.T)
    Q = Z[:, 1:m]
    T11 = T[1:m, 1:m]; T12 = T[1:m, m+1:end]; T22 = T[m+1:end, m+1:end]
    return (Q=Q, T11=T11, T12=T12, T22=T22, Z=Z, values=Vector{ComplexF64}(diag(T11)),
            backward_error=norm(M * Q - Q * T11))
end

"""
    _gram_matrix(Q, S) -> Hermitian{ComplexF64}

`H_c = (i/2) Q' S Q` (N2), symmetrized. Its eigenvalues lie in `[-1/2, 1/2]`
for an orthonormal `Q`; a single (E3)-normalized vector has `H = 1`.
"""
function _gram_matrix(Q::AbstractMatrix{<:Complex}, S::AbstractMatrix)
    H = (im / 2) * (Q' * S * Q)
    return Hermitian(Matrix{ComplexF64}((H + H') / 2))
end

"""
    _schur_spectral_projector(Z, T11, T12, T22) -> Matrix{ComplexF64}

The complex spectral projector `Pi_c` onto the leading invariant subspace of
the ordered Schur form `T = [T11 T12; 0 T22]`, along the complementary
invariant subspace: `Pi_c = Z [I X; 0 0] Z'` with `T11 X - X T22 = T12`
(Julia `sylvester(A, B, C)` solves `A X + X B + C = 0`, pitfall 1, so the
call is `sylvester(T11, -T22, -T12)`); the identity when `T22` is empty. The
real cluster projector is `P_c = 2 Re(Pi_c)` (N9, dossier D7d). An
`ArgumentError` when the block shares an eigenvalue with its complement (the
Sylvester operator is singular): a projector onto part of a repeated
eigenvalue does not exist, which is why clusters are selected whole.
"""
function _schur_spectral_projector(Z::AbstractMatrix{<:Complex}, T11::AbstractMatrix{<:Complex},
                                   T12::AbstractMatrix{<:Complex}, T22::AbstractMatrix{<:Complex})
    m = size(T11, 1); d = size(Z, 1)
    m == d && return Matrix{ComplexF64}(I, d, d)
    X = try
        sylvester(Matrix{ComplexF64}(T11), -Matrix{ComplexF64}(T22), -Matrix{ComplexF64}(T12))
    catch err
        err isa LinearAlgebra.LAPACKException || rethrow()
        # The Sylvester operator is singular exactly when T11 and T22 share an
        # eigenvalue: the selection split a repeated eigenvalue between the
        # block and its complement, so no spectral projector onto the block
        # exists. The cluster machinery must select whole clusters.
        throw(ArgumentError("_schur_spectral_projector: the selected block shares an eigenvalue with its " *
            "complement (LAPACK $(err.info)); a spectral projector onto part of a repeated eigenvalue does not " *
            "exist; select the whole cluster"))
    end
    B = zeros(ComplexF64, d, d)
    B[1:m, 1:m] .= I(m)
    B[1:m, m+1:end] .= X
    return Z * B * Z'
end

"""
    _chord(kappa, rho_M1, g) -> Float64

The finite-resolution chord `q = min(2, 2 kappa rho_M1 / g)` (N22, design
"Resolution criterion"): the largest rotation of the mode orientation the
map's own error can produce. `g <= 0` or `kappa = Inf` gives `2`
(undetermined orientation).
"""
function _chord(kappa::Real, rho_M1::Real, g::Real)
    (g > 0 && isfinite(kappa)) || return 2.0
    return min(2.0, 2 * kappa * rho_M1 / g)
end

# ---------------------------------------------------------------------------
# Per-cluster decisions (dossier D4-D7).

"""
    _cluster_stability(rho_c, T_half, rho_M1; multiplier=_STABILITY_MULTIPLIER, kappa=1.0) -> (unstable, scale, departure_from_normality, departures)

Dossier D5 on the half block `T_half` (`m x m`; for a real-class component
the block of all its members): Henrici departure from normality
`dep = sqrt(max(0, ||T||_F^2 - sum |rho|^2))`, the scale
`delta_c = multiplier * kappa * max(rho_M1, (rho_M1 * dep^(m - 1))^(1/m))`,
the departures `abs(abs(rho) - 1)` per member, and
`unstable = minimum(departures) > delta_c` ("only a cluster whose whole
block leaves the circle"). `kappa` is the cluster's Krein conditioning (D5
as amended 2026-09-12; theory 13.8 "normalizer conditioning"): a simple
eigenvalue with the (E3)-normalized eigenvector `u` has condition number
`||u||^2 / |u' S u| = kappa / 2`, so its computed modulus leaves the circle
by `eps ||M|| kappa / 2` on a STABLE map (the crab ladder near its Krein
collision: kappa 1e3 .. 1e5, which the earlier `multiplier * rho_M1` alone
declared :unstable). The caller passes `kappa_frame` for a Gram-definite
half, `kappa_eig` when every member is orientable alone, and `1` otherwise
(a real-class block, or Krein-isotropic members whose off-circle eigenvectors
carry no Krein bound: the Henrici term is then the only scale). `kappa` must
be finite and positive (an `ArgumentError` otherwise); a fixed-modulus
threshold is never the decision (design "Alternatives rejected").
"""
function _cluster_stability(rho_c::AbstractVector{<:Complex}, T_half::AbstractMatrix{<:Complex}, rho_M1::Real;
                            multiplier::Real=_STABILITY_MULTIPLIER, kappa::Real=1.0)
    m = length(rho_c)
    size(T_half) == (m, m) || throw(ArgumentError("_cluster_stability: block size $(size(T_half)) does not match $(m) eigenvalues"))
    (isfinite(kappa) && kappa > 0) || throw(ArgumentError("_cluster_stability: kappa must be finite and positive, got $(kappa)"))
    dep = sqrt(max(0.0, norm(T_half)^2 - sum(abs2, rho_c)))
    scale = multiplier * kappa * max(float(rho_M1), (rho_M1 * dep^(m - 1))^(1 / m))
    departures = Float64[abs(abs(r) - 1) for r in rho_c]
    unstable = minimum(departures) > scale
    return (unstable=unstable, scale=scale, departure_from_normality=dep, departures=departures)
end

"""
    _krein_classification(H, floor, r_mp, mp_tol) -> (classification, conjugate, signs, detail)

Dossier D7b on the Gram eigenvalues of `H` (ascending) with the floor of D6:
every eigenvalue above `+floor` gives `:definite` with `conjugate = false`;
every one below `-floor` gives `:definite` with `conjugate = true`; both
signs above the floor and `r_mp <= mp_tol` gives `:indefinite`; anything
else `:unresolved` with a `detail` naming the sub-reason. `signs` is `+1`,
`-1` or `0` per eigenvalue.
"""
function _krein_classification(H::Hermitian, floor::Real, r_mp::Real, mp_tol::Real)
    lam = eigvals(H)
    signs = Int[abs(l) > floor ? Int(sign(l)) : 0 for l in lam]
    if all(==(1), signs)
        return (classification=:definite, conjugate=false, signs=signs, detail="")
    elseif all(==(-1), signs)
        return (classification=:definite, conjugate=true, signs=signs, detail="")
    elseif any(==(0), signs)
        k = findfirst(==(0), signs)
        return (classification=:unresolved, conjugate=false, signs=signs,
                detail="Gram eigenvalue |lambda| = $(abs(lam[k])) at or below the floor $(floor)")
    elseif r_mp <= mp_tol
        return (classification=:indefinite, conjugate=false, signs=signs, detail="")
    else
        return (classification=:unresolved, conjugate=false, signs=signs,
                detail="minimal-polynomial residual $(r_mp) above its tolerance $(mp_tol)")
    end
end

"""
    _cluster_frame(Q, H, S) -> (U, normalization, isotropy)

`U_c = Q H^{-1/2}` (N20) for a positive definite `H` (conjugate the half
first when the Gram was negative definite), with the (N4) residuals
`||U' S U + 2i I||_F` and `||U^T S U||_F`.
"""
function _cluster_frame(Q::AbstractMatrix{<:Complex}, H::Hermitian, S::AbstractMatrix)
    lam, V = eigen(H)
    minimum(lam) > 0 || throw(ArgumentError("_cluster_frame needs a positive definite Gram matrix; got eigenvalues $(lam)"))
    U = Matrix{ComplexF64}(Q * (V * Diagonal(1 ./ sqrt.(lam)) * V'))
    m = size(U, 2)
    normalization = norm(U' * S * U + 2im * I(m))
    isotropy = norm(transpose(U) * S * U)
    return (U=U, normalization=normalization, isotropy=isotropy)
end

"""
    _group_quantities(M, U, S, tau_c) -> (P, G, T, unitarity, r_mp, kappa_frame)

(N5) `P_c = -Im(U U') S`, `G_c = Re(U U')`; (N21) `T_c = (i/2) U' S M U`
and `||T_c' T_c - I||_F`; (N19) `r_mp = ||(M^2 - tau_c M + I) P_c||_F / ||M||_F^2`
with `tau_c = 2 cos(mean tune)`; `kappa_frame = ||U||_2^2`
(`= 1 / lambda_min(H_c)`; assert the two agree to roundoff in a test).
"""
function _group_quantities(M::AbstractMatrix{<:Real}, U::AbstractMatrix{<:Complex}, S::AbstractMatrix, tau_c::Real)
    m = size(U, 2)
    UU = U * U'
    P = Matrix{Float64}(-imag(UU) * S)
    G = Matrix{Float64}(real(UU))
    G = (G + transpose(G)) / 2
    T = Matrix{ComplexF64}((im / 2) * (U' * S * M * U))
    unitarity = norm(T' * T - I(m))
    nM = norm(M)
    r_mp = norm((M * M - tau_c * M + I) * P) / nM^2
    kappa_frame = opnorm(U, 2)^2
    return (P=P, G=G, T=T, unitarity=unitarity, r_mp=r_mp, kappa_frame=kappa_frame)
end

"""
    _recover_modes(M, U, T, half, rho_M1, kappa_frame, resolution_chord; oriented_values=nothing) -> (resolved, forced, chord_matrix, U_rotated, modes, eigenvalues)

Dossier D7e: eigen-decompose the restricted map `T_c` (unitary), re-orthonormalize
its eigenvectors by `qr`, form the internal chords `q_jk = _chord(kappa_frame,
rho_M1, |theta_j - theta_k|)`; `resolved` iff every `q_jk <= resolution_chord`
(`Inf` resolves and sets `forced` when the frozen default chord would not
have resolved the cluster, D1). Resolved: `U_rotated = U V`, and `modes`
holds one [`ClusterMode`](@ref) per column (oriented eigenvalue `theta_j`,
tune `mod(-angle(theta_j), 2 pi)`, the (I1) residual by `_invariance_residual(M,
u_j, theta_j)`, `|u_j' S u_j + 2i|`). An `m = 1` frame is trivially resolved.

The eigenvalues of `T_c = (i/2) U' S M U` carry roundoff `eps ||M|| kappa_frame`
(the (E3) normalization puts `||u||^2` into the product, not into a
denominator), so a mode's `(u_j, theta_j)` pair from `T_c` alone has an (I1)
residual of that size (measured on the 200 manufactured 4x4 maps: up to 1766
`eps ||M||` at `kappa_frame = 5746`, a near-unit tune of 9e-5). The Schur
eigenvalues are backward stable pairs with the Schur columns. When
`oriented_values` (the half's oriented Schur eigenvalues, in any order) is
given, each recovered `theta_j` is replaced by the nearest oriented value
provided that assignment is one-to-one (it is whenever the cluster resolved:
the internal separation is then far above `eps kappa_frame ||M||`); the
chords are still formed from the `T_c` eigenvalues. Stage 3 Part A2 added
this after the stage 2 (I1) pin `residual <= 64 eps ||M||` failed on map 50.
"""
function _recover_modes(M::AbstractMatrix{<:Real}, U::AbstractMatrix{<:Complex}, T::AbstractMatrix{<:Complex},
                        half::AbstractVector{<:Integer}, rho_M1::Real, kappa_frame::Real, resolution_chord::Real;
                        oriented_values=nothing)
    m = size(U, 2)
    length(half) == m || throw(ArgumentError("_recover_modes: $(length(half)) half members for a frame of $(m) columns"))
    S = _symplectic_form(size(M, 1))
    if m == 1
        V = Matrix{ComplexF64}(I, 1, 1)
        theta = ComplexF64[T[1, 1]]
        chord_matrix = zeros(1, 1)
        resolved = true; forced = false
    else
        E = eigen(Matrix{ComplexF64}(T))
        theta = Vector{ComplexF64}(E.values)
        # Re-orthonormalize: T_c is unitary to roundoff, so its eigenvectors are
        # orthogonal up to the roundoff of `eigen`; qr restores a unitary V.
        Vq = Matrix(qr(E.vectors).Q)
        # Keep the eigenvector directions (qr may rotate within a phase); the
        # columns of Vq span the same one-dimensional eigenspaces in order.
        V = Vq
        chord_matrix = zeros(m, m)
        for j in 1:m, k in 1:m
            j == k && continue
            chord_matrix[j, k] = _chord(kappa_frame, rho_M1, abs(theta[j] - theta[k]))
        end
        qmax = maximum(chord_matrix)
        if resolution_chord == Inf
            # D1: `Inf` forces resolution and marks the clusters it AFFECTED, i.e.
            # those the frozen default chord (the merge chord under `Inf`) would
            # have left unresolved (review 2026-09-12).
            resolved = true; forced = qmax > _DEFAULT_RESOLUTION_CHORD
        else
            resolved = qmax <= resolution_chord; forced = false
        end
    end
    U_rotated = Matrix{ComplexF64}(U * V)
    # Snap each recovered theta_j to the nearest oriented Schur eigenvalue when
    # the assignment is one-to-one (A2 finding F7: T_c carries roundoff
    # eps kappa_frame ||M||). Explicit loops, not comprehensions: `theta` is
    # assigned on two branches above and a capturing closure would box it
    # (the suite's Core.Box tripwire).
    theta_out = theta
    if oriented_values !== nothing && length(oriented_values) == m
        nearest = zeros(Int, m)
        for j in 1:m
            nearest[j] = argmin(abs.(oriented_values .- theta[j]))
        end
        if length(unique(nearest)) == m
            theta_out = ComplexF64[oriented_values[k] for k in nearest]
        end
    end
    modes = ClusterMode[]
    if resolved
        for j in 1:m
            u = U_rotated[:, j]
            push!(modes, ClusterMode(half[j], theta_out[j], mod(-angle(theta_out[j]), 2pi), u,
                                     _invariance_residual(M, u, theta_out[j]), abs(dot(u, S * u) + 2im)))
        end
    end
    return (resolved=resolved, forced=forced, chord_matrix=chord_matrix, U_rotated=U_rotated, modes=modes,
            eigenvalues=theta_out)
end

"""
    _column_eigenvector_residual(M, W, evals) -> Float64

The 13.8 reconstruction check of a column basis: the largest normalized (I1)
residual `_invariance_residual(M, W[:, i], evals[i]).normalized` over the
columns, each against the eigenvalue paired with it by index. Roundoff for
the recovered modes of a resolved cluster and for the signed basis of an
EXACTLY degenerate indefinite cluster; of order the internal split for a
split group, whose columns are an N20 or Krein-signed basis of the invariant
subspace but not eigenvectors (13.8: the column mixing "may not be applied to
distinct resolved eigenvectors without re-establishing their eigenvector
property"). Reported, never judged (review 2026-09-12, finding 3).
"""
function _column_eigenvector_residual(M::AbstractMatrix{<:Real}, W::AbstractMatrix{<:Complex},
                                      evals::AbstractVector{<:Complex})
    size(W, 2) == length(evals) || throw(ArgumentError(
        "_column_eigenvector_residual: $(size(W, 2)) columns for $(length(evals)) eigenvalues"))
    return maximum(_invariance_residual(M, W[:, i], evals[i]).normalized for i in eachindex(evals))
end

"""
    _check_partition(partition, d, partner, real_class)

Dossier D1: `partition` must be a vector of index vectors forming a partition
of `1:d` that is closed under conjugation (each block holds the partner of
every complex-class member); anything else is an `ArgumentError` naming the
offending block.
"""
function _check_partition(partition, d::Integer, partner::AbstractVector{<:Integer}, real_class::BitVector)
    partition isa AbstractVector || throw(ArgumentError("partition must be a vector of index vectors, got $(typeof(partition))"))
    seen = falses(d)
    blocks = Vector{Vector{Int}}()
    for (b, block) in enumerate(partition)
        (block isa AbstractVector && all(x -> x isa Integer, block) && !isempty(block)) || throw(ArgumentError(
            "partition block $(b) must be a non-empty vector of integers, got $(block)"))
        idx = Int.(collect(block))
        for j in idx
            1 <= j <= d || throw(ArgumentError("partition block $(b) has index $(j) outside 1:$(d)"))
            seen[j] && throw(ArgumentError("partition block $(b) repeats index $(j): not a partition"))
            seen[j] = true
        end
        for j in idx
            real_class[j] && continue
            partner[j] in idx || throw(ArgumentError(
                "partition block $(b) = $(idx) is not closed under conjugation: member $(j) has partner $(partner[j])"))
        end
        push!(blocks, sort(idx))
    end
    all(seen) || throw(ArgumentError("partition misses indices $(findall(.!seen)) of 1:$(d)"))
    return blocks
end

"""
    _half_of(rho, members) -> Vector{Int}

The half of a component: its members with `Im rho > 0` (dossier D2), in order.
"""
_half_of(rho::AbstractVector{<:Complex}, members::AbstractVector{<:Integer}) = Int[j for j in members if imag(rho[j]) > 0]

"""
    _select(order, idx, d) -> BitVector

The `ordschur` selection of the canonical indices `idx` (see [`_canonical_spectrum`](@ref)).
"""
function _select(order::AbstractVector{<:Integer}, idx::AbstractVector{<:Integer}, d::Integer)
    sel = falses(d)
    sel[order[idx]] .= true
    return sel
end

"""
    _evaluate_component(spec, rho, S, half, rho_M0; gram_multiplier) -> NamedTuple

The shared evaluation of a complex-class component (dossier D5-D6): the
ordered-Schur basis of its half (`Q`, `T11`, `T12`, `T22`, `Z`), `rho_M1 =
max(rho_M0, ||M Q - Q T11||_F)`, the Gram `H` and its ascending eigenvalues,
the external gap and the Gram floor `gram_multiplier * rho_M1 / g_ext`, and
the two kappa estimates: `kappa_frame = 1 / min |lambda|` when the Gram is
definite above the floor (else `Inf`), `kappa_eig = ||[u_j]||_2^2` from the
individually (E3)-normalized Schur vectors of each half member when each is
orientable alone (`|h_j| > gram_multiplier * rho_M1 / g_ext({j})`), else
`Inf`. `kappa` and `kappa_source` (`:frame`, `:eigenvectors`, `:none`) pick
the estimate D6 uses for the chord. `eigenvector_estimate` is the `d x m`
matrix `[u_j]` behind `kappa_eig` (every column oriented by the sign of its
Gram value, `Im(u' S u) = -2` (E4), and (E3)-normalized), empty when a member
is not orientable alone.
"""
function _evaluate_component(spec, rho::AbstractVector{<:Complex}, S::AbstractMatrix, half::AbstractVector{<:Integer},
                             rho_M0::Real; gram_multiplier::Real=_GRAM_FLOOR_MULTIPLIER)
    d = length(rho)
    B = _ordered_schur_basis(spec.schur, _select(spec.order, half, d), spec.matrix)
    rho_M1 = max(float(rho_M0), B.backward_error)
    H = _gram_matrix(B.Q, S)
    lam = eigvals(H)
    g_ext = _external_gap(rho, half)
    floor = gram_multiplier * rho_M1 / g_ext
    definite = all(l -> abs(l) > floor, lam) && (all(l -> l > 0, lam) || all(l -> l < 0, lam))
    kappa_frame = definite ? 1 / minimum(abs, lam) : Inf
    # Eigenvector estimate: one ordered-Schur vector per half member, oriented
    # and (E3)-normalized alone (13.8; kappa_eig of the design's reporting list).
    m = length(half)
    Ueig = zeros(ComplexF64, d, m)
    orientable = true
    for (c, j) in enumerate(half)
        Bj = _ordered_schur_basis(spec.schur, _select(spec.order, [j], d), spec.matrix)
        q = Bj.Q[:, 1]
        h = -imag(dot(q, S * q)) / 2  # the Gram (i/2) q' S q = -Im(q' S q) / 2, real for one vector
        floor_j = gram_multiplier * rho_M1 / _external_gap(rho, [j])
        if abs(h) <= floor_j
            orientable = false
            break
        end
        # A positive Gram is the (E4) orientation (Im(u' S u) < 0); conjugate a negative one.
        Ueig[:, c] = (h < 0 ? conj(q) : q) / sqrt(abs(h))
    end
    kappa_eig = orientable ? opnorm(Ueig, 2)^2 : Inf
    kappa, source = definite ? (kappa_frame, :frame) : (orientable ? (kappa_eig, :eigenvectors) : (Inf, :none))
    return (Q=B.Q, T11=B.T11, T12=B.T12, T22=B.T22, Z=B.Z, values=B.values, backward_error=B.backward_error,
            rho_M1=rho_M1, H=H, gram_eigenvalues=lam, external_gap=g_ext, floor=floor, definite=definite,
            kappa_frame=kappa_frame, kappa_eig=kappa_eig, kappa=kappa, kappa_source=source,
            eigenvector_estimate=(orientable ? Ueig : zeros(ComplexF64, d, 0)))
end

"""
    _component_basis(spec, rho, S, members, rho_M0) -> Union{Nothing,Matrix{ComplexF64}}

The (E3)-normalized basis a component contributes to the eigenvector estimate
of a candidate union (dossier D6, "kappa_eig from the individually normalized
eigenvectors when each pair alone is orientable", generalized to components
that already merged): the frame `Q H^{-1/2}` of a definite component (after
the orientation), the signed basis `Q V |Lambda|^{-1/2}` (negative columns
conjugated) of a component whose Gram is indefinite above the floor, and
`nothing` when a Gram eigenvalue sits at or below the floor (the component is
not orientable alone). For a single pair this is the (E3)/(E4) eigenvector.
"""
function _component_basis(spec, rho::AbstractVector{<:Complex}, S::AbstractMatrix, members::AbstractVector{<:Integer},
                          rho_M0::Real)
    ev = _evaluate_component(spec, rho, S, _half_of(rho, members), rho_M0)
    lam, V = eigen(ev.H)
    all(l -> abs(l) > ev.floor, lam) || return nothing
    W = ev.Q * V * Diagonal(1 ./ sqrt.(abs.(lam)))
    for i in eachindex(lam)
        lam[i] < 0 && (W[:, i] = conj(W[:, i]))
    end
    return Matrix{ComplexF64}(W)
end

"""
    _agglomerate(M, spec, rho, partner, real_class, complex_pairs, rho_M0, resolution_chord, S) -> (components, receipt)

Dossier D6: start from the conjugate pairs as components; for every pair of
components form the union's half, its ordered-Schur basis and Gram, its
`rho_M1`, its kappa (`1 / lambda_min(|H|)` when definite above the floor,
else the eigenvector estimate when each pair alone is orientable, else
`Inf`), the gap and the chord; merge the pair with the LARGEST chord above
`resolution_chord` first, recompute, repeat until none exceeds it (a chord of
`Inf` merges at `_DEFAULT_RESOLUTION_CHORD`: it forces the RESOLUTION of the
clusters, D7e, not their absence). Every evaluated candidate goes into the
receipt; the returned `chords` are the last round's between the final
components.
"""
function _agglomerate(M::AbstractMatrix{<:Real}, spec, rho::AbstractVector{<:Complex}, partner::AbstractVector{<:Integer},
                      real_class::BitVector, complex_pairs::AbstractVector{<:AbstractVector{<:Integer}},
                      rho_M0::Real, resolution_chord::Real, S::AbstractMatrix)
    components = Vector{Vector{Int}}(sort(collect(map(c -> sort(Int.(c)), complex_pairs))))
    receipt = _RESOLUTION_RECEIPT_T[]
    # `Inf` forces RESOLUTION of every cluster (D7e), not the absence of
    # clusters: the merging itself runs at the frozen default chord so the
    # forced modes are recovered inside the physically identified cluster.
    merge_chord = isfinite(resolution_chord) ? resolution_chord : _DEFAULT_RESOLUTION_CHORD
    n = length(components)
    chords = zeros(n, n)
    bases = Dict{Vector{Int},Union{Nothing,Matrix{ComplexF64}}}()
    basis_of(c) = get!(() -> _component_basis(spec, rho, S, c, rho_M0), bases, c)
    evaluate(c1, c2) = begin
        union_members = sort(vcat(c1, c2))
        half = _half_of(rho, union_members)
        ev = _evaluate_component(spec, rho, S, half, rho_M0)
        g = _cluster_gap(rho, c1, c2)
        if ev.definite
            kappa, source = ev.kappa_frame, :frame
        else
            B1 = basis_of(c1); B2 = basis_of(c2)
            if B1 !== nothing && B2 !== nothing
                kappa, source = opnorm(hcat(B1, B2), 2)^2, :eigenvectors
            elseif isfinite(ev.kappa_eig)
                kappa, source = ev.kappa_eig, :eigenvectors
            else
                kappa, source = Inf, :none
            end
        end
        q = _chord(kappa, ev.rho_M1, g)
        (gap=g, kappa=kappa, kappa_source=source, rho_M1=ev.rho_M1, chord=q)
    end
    while true
        n = length(components)
        chords = zeros(n, n)
        best = (0, 0); bestq = -Inf
        for a in 1:n, b in a+1:n
            r = evaluate(components[a], components[b])
            chords[a, b] = chords[b, a] = r.chord
            do_merge = r.chord > merge_chord
            push!(receipt, (first=copy(components[a]), second=copy(components[b]), gap=r.gap, kappa=r.kappa,
                            kappa_source=r.kappa_source, rho_M1=r.rho_M1, chord=r.chord, merged=false))
            if do_merge && r.chord > bestq
                best = (a, b); bestq = r.chord
            end
        end
        best == (0, 0) && break
        # Mark the winning candidate merged in the receipt (the last round's entry).
        for k in length(receipt):-1:1
            e = receipt[k]
            if e.first == components[best[1]] && e.second == components[best[2]]
                receipt[k] = Base.merge(e, (merged=true,))
                break
            end
        end
        merged = sort(vcat(components[best[1]], components[best[2]]))
        # An explicit loop, not a comprehension: `components`, `n` and `best`
        # are reassigned in this loop and a capturing closure would box them
        # (the suite's Core.Box tripwire).
        kept = Vector{Vector{Int}}()
        for k in 1:n
            (k == best[1] || k == best[2]) && continue
            push!(kept, components[k])
        end
        push!(kept, merged)
        sort!(kept)
        components = kept
    end
    return (components=components, receipt=receipt, chords=chords)
end

"""
    _MODE_CLUSTERS_ARGUMENT_HELP

The one-line statement of what [`_mode_clusters`](@ref) accepts, quoted in
every `ArgumentError` of `_check_mode_clusters_arguments`.
"""
const _MODE_CLUSTERS_ARGUMENT_HELP = "a real 4x4 or 6x6 matrix with finite entries, rho_M0 >= 0 finite, resolution_chord in (0, 2] or Inf"

"""
    _check_mode_clusters_arguments(M, rho_M0, resolution_chord)

Dossier D1's argument contract: `M` square of size 4 or 6 with finite
entries, `rho_M0` finite and non-negative, `resolution_chord` in `(0, 2]` or
`Inf`; an `ArgumentError` naming the offending value otherwise. The
partition is checked separately by `_check_partition`.
"""
function _check_mode_clusters_arguments(M::AbstractMatrix, rho_M0::Real, resolution_chord::Real)
    d = size(M, 1)
    (size(M, 2) == d && d in (4, 6)) || throw(ArgumentError(
        "_mode_clusters takes $(_MODE_CLUSTERS_ARGUMENT_HELP); got size $(size(M))"))
    all(isfinite, M) || throw(ArgumentError(
        "_mode_clusters takes $(_MODE_CLUSTERS_ARGUMENT_HELP); the matrix has a non-finite entry"))
    (isfinite(rho_M0) && rho_M0 >= 0) || throw(ArgumentError(
        "_mode_clusters takes $(_MODE_CLUSTERS_ARGUMENT_HELP); got rho_M0 = $(rho_M0)"))
    (resolution_chord == Inf || (isfinite(resolution_chord) && 0 < resolution_chord <= 2)) || throw(ArgumentError(
        "_mode_clusters takes $(_MODE_CLUSTERS_ARGUMENT_HELP); got resolution_chord = $(resolution_chord)"))
    return nothing
end

"""
    _mode_clusters(M; rho_M0, resolution_chord=_DEFAULT_RESOLUTION_CHORD, partition=nothing) -> ModeClusters

The cluster-first pipeline of the design (steps 4-7) for a real 4x4 or 6x6
matrix `M` the caller has already scaled (dossier D1-D8). `rho_M0` is the
caller's first perturbation scale (`_perturbation_scale`), REQUIRED.
Order of operations: canonical spectrum and Schur backward error (D2);
real-class mask with `tau_real` (D2) and conjugate pairing; real-class
components (D4); complex-pair agglomeration by the chord, or the explicit
`partition` (D6, D1); per cluster: the half block and stability (D5),
the invariant-subspace residual, Gram and Krein classification (D7a-b), the
frame, group quantities and Schur projector (D7c-d), mode recovery (D7e);
the report with the receipt, the inter-cluster chords and the degeneracy
status (D8). Argument errors: any other size, a non-finite entry, a
negative or non-finite `rho_M0`, a chord outside `(0, 2]` that is not `Inf`,
an invalid partition. Residuals are REPORTED, not judged, except where a
decision above names them.
"""
function _mode_clusters(M::AbstractMatrix{<:Real}; rho_M0::Real, resolution_chord::Real=_DEFAULT_RESOLUTION_CHORD,
                        partition=nothing)
    _check_mode_clusters_arguments(M, rho_M0, resolution_chord)
    Mf = Matrix{Float64}(M); d = size(Mf, 1); S = _symplectic_form(d)
    spec = _canonical_spectrum(Mf)
    rho = spec.eigenvalues
    rho_M1_global = max(float(rho_M0), spec.backward_error)
    tau_real = _REAL_CLASS_MULTIPLIER * sqrt(rho_M1_global) * max(1.0, opnorm(Mf, 2))
    real_class = _real_class_mask(rho, tau_real)
    pairing = _conjugate_pairs(rho, real_class, tau_real)
    partner = pairing.partner
    complex_idx = findall(.!real_class)
    receipt = _RESOLUTION_RECEIPT_T[]
    complex_chords = zeros(0, 0)
    pairing_failed = !pairing.ok
    if partition !== nothing
        blocks = _check_partition(partition, d, partner, real_class)
        for b in blocks
            (all(real_class[b]) || !any(real_class[b])) || throw(ArgumentError(
                "partition block $(b) mixes real-class and complex-class eigenvalues"))
        end
        real_components = [b for b in blocks if all(real_class[b])]
        complex_components = [b for b in blocks if !any(real_class[b])]
        partition_source = :explicit
        pairing_failed = false
    else
        real_components = _real_components(rho, findall(real_class), tau_real)
        partition_source = :auto
        if pairing_failed
            complex_components = isempty(complex_idx) ? Vector{Vector{Int}}() : [complex_idx]
        else
            complex_pairs = unique(sort([j, partner[j]]) for j in complex_idx)
            if isempty(complex_pairs)
                complex_components = Vector{Vector{Int}}()
            else
                agg = _agglomerate(Mf, spec, rho, partner, real_class, complex_pairs, rho_M0, resolution_chord, S)
                complex_components = agg.components; receipt = agg.receipt; complex_chords = agg.chords
            end
        end
    end
    clusters = ModeCluster[]
    for members in real_components
        push!(clusters, _real_class_cluster(Mf, spec, rho, members, rho_M0, S))
    end
    complex_positions = Int[]
    for members in complex_components
        if pairing_failed
            B = _ordered_schur_basis(spec.schur, _select(spec.order, members, d), spec.matrix)
            rho_M1 = max(float(rho_M0), B.backward_error)
            st = _cluster_stability(B.values, B.T11, rho_M1)
            push!(clusters, _flag_cluster(members, Int[], rho, B.Q, B.T11, B.T11, st, rho_M1, :unresolved,
                                          :unresolved_defective, "conjugate pairing failed",
                                          _internal_gap(rho, members), _external_gap(rho, members)))
        else
            push!(clusters, _complex_cluster(Mf, spec, rho, members, rho_M0, resolution_chord, S))
        end
        push!(complex_positions, length(clusters))
    end
    perm = sortperm(clusters; by=c -> first(c.members))
    clusters = clusters[perm]
    n = length(clusters)
    inter = zeros(n, n)
    if size(complex_chords, 1) == length(complex_positions)
        inv = invperm(perm)
        for (a, pa) in enumerate(complex_positions), (b, pb) in enumerate(complex_positions)
            inter[inv[pa], inv[pb]] = complex_chords[a, b]
        end
    end
    rank = Dict(:all_resolved => 0, :degenerate => 1, :indefinite => 2, :unresolved => 3, :unit_eigenvalue => 4, :unstable => 5)
    status_of(c) = c.classification === :definite ? (c.resolved ? :all_resolved : :degenerate) : c.classification
    status = isempty(clusters) ? :all_resolved : clusters[argmax([rank[status_of(c)] for c in clusters])] |> status_of
    rho_M1 = isempty(clusters) ? float(rho_M0) : maximum(c.rho_M1 for c in clusters)
    return ModeClusters(Mf, Vector{ComplexF64}(rho), partner, real_class, tau_real, spec.backward_error, float(rho_M0),
                        rho_M1, float(resolution_chord), partition_source, clusters, receipt, inter, status)
end

# ---------------------------------------------------------------------------
# Cluster builders used by `_mode_clusters` (dossier D4, D5, D7).

"""
    _unavailable(T, reason, detail) -> Determined{T}

An unavailable `Determined{T}` with a pinned `reason` (a member of
`DETERMINATION_REASONS`; the constructor throws otherwise) and the human
`detail`: the form every non-formed cluster output takes (never `NaN`).
"""
_unavailable(::Type{T}, reason::Symbol, detail::AbstractString) where {T} =
    Determined{T}(:unavailable, nothing, nothing, reason, detail)

"""
    _real_components(rho, idx, tau_real) -> Vector{Vector{Int}}

Connected components of the indices `idx` under `_pair_gap <= tau_real`
(dossier D4), each sorted, the list sorted by first member.
"""
function _real_components(rho::AbstractVector{<:Complex}, idx::AbstractVector{<:Integer}, tau_real::Real)
    remaining = Set{Int}(idx)
    out = Vector{Vector{Int}}()
    while !isempty(remaining)
        seed = minimum(remaining)
        comp = Int[seed]; delete!(remaining, seed)
        frontier = Int[seed]
        while !isempty(frontier)
            j = pop!(frontier)
            for k in collect(remaining)
                if _pair_gap(rho[j], rho[k]) <= tau_real
                    push!(comp, k); push!(frontier, k); delete!(remaining, k)
                end
            end
        end
        push!(out, sort(comp))
    end
    return sort(out)
end

"""
    _internal_gap(rho, half) -> Float64

`min _pair_gap` over distinct half members (dossier D3); `Inf` for a singleton.
"""
function _internal_gap(rho::AbstractVector{<:Complex}, half::AbstractVector{<:Integer})
    length(half) <= 1 && return Inf
    return minimum(_pair_gap(rho[j], rho[k]) for j in half for k in half if j < k)
end

"""
    _flag_cluster(members, half, rho, Q, T_half, T_full, st, rho_M1, classification, reason, detail, g_int, g_ext) -> ModeCluster

A cluster with no modal output (real-class, unstable, or a failed pairing):
every `Determined` unavailable with the cluster's reason, empty Gram fields.
"""
function _flag_cluster(members::Vector{Int}, half::Vector{Int}, rho::AbstractVector{<:Complex},
                       Q::Matrix{ComplexF64}, T_half::Matrix{ComplexF64}, T_full::Matrix{ComplexF64}, st,
                       rho_M1::Real, classification::Symbol, reason::Symbol, detail::AbstractString,
                       g_int::Real, g_ext::Real)
    shown = isempty(half) ? members : half
    ev = Vector{ComplexF64}(rho[shown])
    tunes = isempty(half) ? Float64[] : Float64[mod(-angle(r), 2pi) for r in ev]
    m = length(shown)
    return ModeCluster(members, half, ev, tunes, classification, reason, String(detail), false,
        Q, T_half, T_full, st.departure_from_normality, st.scale, st.departures,
        zeros(ComplexF64, 0, 0), Float64[], Int[], 0.0,
        _unavailable(Matrix{ComplexF64}, reason, detail), _unavailable(Matrix{ComplexF64}, reason, detail),
        _unavailable(Matrix{Float64}, reason, detail), _unavailable(Float64, reason, detail),
        _unavailable(Matrix{Float64}, reason, detail), _unavailable(Matrix{ComplexF64}, reason, detail),
        _unavailable(_CLUSTER_RESIDUALS_T, reason, detail), _unavailable(_FRAME_RESIDUALS_T, reason, detail),
        float(rho_M1), _unavailable(Float64, reason, detail), _unavailable(Float64, reason, detail),
        float(g_int), float(g_ext), zeros(m, m), false, false,
        _unavailable(Vector{ClusterMode}, reason, detail))
end

"""
    _real_class_cluster(M, spec, rho, members, rho_M0, S) -> ModeCluster

Dossier D4: the ordered-Schur block of all members, the stability test D5 on
it, then `:unit_eigenvalue` (every member within `delta_c` of +-1),
`:unstable` (the whole block off the circle) or `:unresolved` (members
straddle the circle).
"""
function _real_class_cluster(M::AbstractMatrix{<:Real}, spec, rho::AbstractVector{<:Complex}, members::Vector{Int},
                             rho_M0::Real, S::AbstractMatrix)
    d = length(rho)
    B = _ordered_schur_basis(spec.schur, _select(spec.order, members, d), spec.matrix)
    rho_M1 = max(float(rho_M0), B.backward_error)
    st = _cluster_stability(B.values, B.T11, rho_M1)   # a real-class block has no Krein conditioning: kappa = 1
    if st.unstable
        cls, reason, detail = :unstable, :unstable_spectrum, "every real-class member leaves the unit circle by more than $(st.scale)"
    elseif all(r -> min(abs(r - 1), abs(r + 1)) <= st.scale, B.values)
        cls, reason, detail = :unit_eigenvalue, :unit_eigenvalue, "real-class cluster at +-1 within $(st.scale)"
    else
        cls, reason, detail = :unresolved, :unresolved_defective, "real-class members straddle the unit circle"
    end
    return _flag_cluster(members, Int[], rho, B.Q, B.T11, B.T11, st, rho_M1, cls, reason, detail,
                         _internal_gap(rho, members), _external_gap(rho, members))
end

"""
    _complex_cluster(M, spec, rho, members, rho_M0, resolution_chord, S) -> ModeCluster

Dossier D5 and D7 for one complex-class cluster: the half's ordered-Schur
block and stability (D5); the invariant-subspace residual (D7a); the Schur
spectral projector and its residuals (D7d); the minimal-polynomial residual
(N19) on that projector; the Gram, floor and Krein classification (D7b); for
a definite cluster the frame, group quantities and mode recovery (D7c, D7e);
for an indefinite cluster the signed basis (13.8).
"""
function _complex_cluster(M::AbstractMatrix{<:Real}, spec, rho::AbstractVector{<:Complex}, members::Vector{Int},
                          rho_M0::Real, resolution_chord::Real, S::AbstractMatrix)
    d = length(rho)
    half = _half_of(rho, members)
    m = length(half)
    ev = _evaluate_component(spec, rho, S, half, rho_M0)
    full = _ordered_schur_basis(spec.schur, _select(spec.order, members, d), spec.matrix)
    # D5 (amended 2026-09-12): the stability scale carries the cluster's Krein
    # conditioning; a Krein-isotropic half (off-circle eigenvectors, or members
    # not orientable alone) has none and falls back to 1.
    kappa_c = ev.definite ? ev.kappa_frame : (isfinite(ev.kappa_eig) ? ev.kappa_eig : 1.0)
    st = _cluster_stability(ev.values, ev.T11, ev.rho_M1; kappa=kappa_c)
    g_int = _internal_gap(rho, half)
    if st.unstable
        detail = "every member of the half block leaves the unit circle by more than $(st.scale)"
        return _flag_cluster(members, half, rho, ev.Q, ev.T11, full.T11, st, ev.rho_M1, :unstable, :unstable_spectrum,
                             detail, g_int, ev.external_gap)
    end
    nM = norm(M)
    r_sub = ev.backward_error / max(1.0, nM)
    sub_tol = _SUBSPACE_RESIDUAL_MULTIPLIER * d * eps(Float64)
    Pi = _schur_spectral_projector(ev.Z, ev.T11, ev.T12, ev.T22)
    P = Matrix{Float64}(2 * real(Pi))
    proj_res = (idempotent=norm(P * P - P), commutes=norm(M * P - P * M), adjoint=norm(transpose(P) * S - S * P))
    tau_c = 2 * cos(sum(abs.(angle.(ev.values))) / m)
    r_mp = norm((M * M - tau_c * M + I) * P) / nM^2
    mp_tol = _MINIMAL_POLYNOMIAL_MULTIPLIER * max(ev.rho_M1, m == 1 ? ev.rho_M1 : g_int) * opnorm(P, 2) / nM
    kc = _krein_classification(ev.H, ev.floor, r_mp, mp_tol)
    residuals = Determined((subspace=r_sub, minimal_polynomial=r_mp, projector_idempotent=proj_res.idempotent,
                            projector_commutes=proj_res.commutes, projector_adjoint=proj_res.adjoint))
    projector = Determined(P)
    if r_sub > sub_tol
        cls, reason, detail = :unresolved, :unresolved_defective, "invariant-subspace residual $(r_sub) above $(sub_tol)"
    elseif kc.classification === :unresolved
        cls, reason, detail = :unresolved, :unresolved_defective, kc.detail
    elseif kc.classification === :indefinite
        cls, reason, detail = :indefinite, :indefinite_cluster, "Gram signs $(kc.signs); minimal-polynomial residual $(r_mp) <= $(mp_tol)"
    else
        cls, reason, detail = :definite, :none, ""
    end
    lam = ev.gram_eigenvalues
    # An individual-member quantity the group does not support: the pinned
    # reason is :cluster_unresolved ("an individual-mode quantity is a
    # convention"), never :unresolved_defective, which would assert a
    # classification the cluster may not carry (review 2026-09-12).
    kappa_eig = isfinite(ev.kappa_eig) ? Determined(ev.kappa_eig) :
        _unavailable(Float64, :cluster_unresolved, "a half member is not orientable alone (Gram value at or below the floor)")
    if cls === :definite
        Qc = kc.conjugate ? conj(ev.Q) : ev.Q
        Hc = kc.conjugate ? Hermitian(Matrix{ComplexF64}(-conj(Matrix(ev.H)))) : ev.H
        oriented = kc.conjugate ? conj.(ev.values) : ev.values
        fr = _cluster_frame(Qc, Hc, S)
        gq = _group_quantities(M, fr.U, S, tau_c)
        rec = _recover_modes(M, fr.U, gq.T, half, ev.rho_M1, gq.kappa_frame, resolution_chord; oriented_values=oriented)
        U = rec.resolved ? rec.U_rotated : fr.U
        evals = rec.resolved ? rec.eigenvalues : Vector{ComplexF64}(oriented)
        reason = rec.resolved ? :none : :cluster_unresolved
        detail = rec.resolved ? "" : "internal chord $(maximum(rec.chord_matrix)) above the resolution chord $(resolution_chord)"
        modes = rec.resolved ? Determined(rec.modes) : _unavailable(Vector{ClusterMode}, reason, detail)
        eig_res = _column_eigenvector_residual(M, U, evals)
        return ModeCluster(members, half, evals, Float64[mod(-angle(r), 2pi) for r in evals], :definite, reason, detail,
            kc.conjugate, Matrix{ComplexF64}(Qc), ev.T11, full.T11, st.departure_from_normality, st.scale, st.departures,
            Matrix{ComplexF64}(Hc), eigvals(Hc), Int[1 for _ in 1:m], ev.floor,
            Determined(U), _unavailable(Matrix{ComplexF64}, :not_derived_for_cluster, "definite cluster: no signed basis"),
            projector, Determined(norm(gq.P - P)), Determined(gq.G), Determined(gq.T), residuals,
            Determined((normalization=fr.normalization, isotropy=fr.isotropy, unitarity=gq.unitarity, eigenvector=eig_res)),
            ev.rho_M1, Determined(gq.kappa_frame), kappa_eig, g_int, ev.external_gap, rec.chord_matrix,
            rec.resolved, rec.forced, modes)
    end
    # Indefinite or unresolved: no frame, no covariance; the projector stays.
    if cls === :indefinite
        V = eigen(ev.H).vectors
        W = zeros(ComplexF64, d, m); evals = zeros(ComplexF64, m)
        for i in 1:m
            w = ev.Q * V[:, i] / sqrt(abs(lam[i]))
            W[:, i] = lam[i] < 0 ? conj(w) : w
            evals[i] = lam[i] < 0 ? conj(ev.values[i]) : ev.values[i]
        end
        Tw = (im / 2) * (W' * S * M * W)
        # The 13.8 reconstruction check: the columns are eigenvectors of their
        # by-index eigenvalues only at exact degeneracy (internal_gap at the map
        # error); for a split group they are a Krein-signed basis of the
        # invariant subspace and this residual is of order the split.
        frame_res = Determined((normalization=norm(W' * S * W + 2im * I(m)), isotropy=norm(transpose(W) * S * W),
                                unitarity=norm(Tw' * Tw - I(m)), eigenvector=_column_eigenvector_residual(M, W, evals)))
        signed = Determined(W)
    else
        evals = Vector{ComplexF64}(ev.values)
        frame_res = _unavailable(_FRAME_RESIDUALS_T, reason, detail)
        signed = _unavailable(Matrix{ComplexF64}, reason, detail)
    end
    return ModeCluster(members, half, evals, Float64[mod(-angle(r), 2pi) for r in evals], cls, reason, detail, false,
        ev.Q, ev.T11, full.T11, st.departure_from_normality, st.scale, st.departures,
        Matrix{ComplexF64}(ev.H), lam, kc.signs, ev.floor,
        _unavailable(Matrix{ComplexF64}, reason, detail), signed, projector, _unavailable(Float64, reason, detail),
        _unavailable(Matrix{Float64}, reason, detail), _unavailable(Matrix{ComplexF64}, reason, detail), residuals, frame_res,
        ev.rho_M1, _unavailable(Float64, reason, detail), kappa_eig, g_int, ev.external_gap, zeros(m, m), false, false,
        _unavailable(Vector{ClusterMode}, reason, detail))
end
