# Canonical separation of betatron and longitudinal motion, the full 6D
# normalizer, the physical projected optics, the matched covariance and the
# Ohmi-Hirata-Oide factorization: theory docs/theory/twiss_dispersion.md
# Section 9.1-9.4 ((K1)-(K14), (O1)-(O5)) with the elementary factors (D2)
# and the ordered transformation (D3) of Section 8.1; design
# docs/design/twiss_dispersion_analysis.md "Pipeline" steps 10-11 and the
# return table. Stage 4a of the campaign (design "Staging", item 4, first
# half). Pure matrix arithmetic on a real 6x6 matrix the caller has ALREADY
# scaled; the stage 1 `_unscale_*` table transforms U_6, Sigma, P_j, G_j and
# the Twiss projections back. Nothing here claims an analysis exists.
#
# Conventions (theory 8.1, 9.1): coordinates (x, px, y, py, z, pz); the
# ordered transformation M_cal = M_zeta M_eta (D3) from barred (decoupled)
# to physical coordinates,
#     M_cal = [I_4 + zeta eta' S_4   zeta   eta ;
#              eta' S_4              1      0   ;
#              -zeta' S_4            0      h   ],   h = 1 - zeta' S_4 eta,
# with the closed-form inverse (K2) (no 1/h: it exists for every h);
# Mbar = M_cal^-1 M M_cal = diag(Mbar_beta, Mbar_s) (K4) when the
# (zbar, pzbar) columns span the longitudinal invariant plane; both blocks
# symplectic (K5); (K7) the explicit blocks for h != 0; (K8) the identity
# M_rr' S_4 M_rr + M_lr' S_2 M_lr = S_4 (why the raw M_rr is not symplectic);
# U_6 = M_cal diag(Ubar_beta, Ubar_s) (K9); Sigma_6 = U_6 diag(eps) U_6'
# (K10) = sum_j eps_j G_j (K12); kappa_ja = -Im(conj(u_ja) u_j,pa) with row
# and column sums one and kappa_sz = h (K12); the (K13) block identity; the
# Ohmi factor (O2) with sqrt(h), defined for h > 0 only. The ASCII forms
# above are the note's own equations, cited by label ((K2) in 9.1, (K4)-(K5)
# and (K7)-(K8) in 9.2, (K9)-(K10) and (K12)-(K13) in 9.3, (O2) in 9.4).
#
# Every threshold constant below is PROVISIONAL until the stage 4a
# measurement freezes it. The orchestrator's decisions E1-E12 (stage 4a
# dossier) fix the order of operations; the file follows them.

"""
    _SEPARATION_RESIDUAL_MULTIPLIER

`c_sep` of the separation acceptance: the off-diagonal blocks of
`M_cal^-1 M M_cal` (K4) are accepted as zero when their Frobenius norm is at
or below `c_sep * eps * kappa_sep`, `kappa_sep = max(1, ||M||_F) * ||M_cal||_F
* ||M_cal^-1||_F`; above it the separation is `:not_invariant` (the triple
does not span an invariant plane) but every block is still REPORTED.
PROVISIONAL; measured 2026-09-12 (stage 4a record, "Derived windows") on
the 260 fixtures: must-accept extreme `off / (eps kappa_sep) = 1.026` (the
(D8) triple of "trial-011 crab k=kc(1-1.0e-5)"); must-reject extreme
`5.138e4` (a dense map's exact `zeta` perturbed by `1e-10 (1, -1, 0.5,
0.25)`, an error far above roundoff). Window by the one-tenth / ten rule
`[10.3, 5.14e3]`; 256 lies inside it. The perturbations `1e-12` (ratio
514..700), `1e-13` (<= 118) and `1e-14` (<= 12) are UNLABELLED: neither
side of the rule classifies them, and the code's verdict on them is not a
claim of this docstring.
"""
const _SEPARATION_RESIDUAL_MULTIPLIER = 256.0

"""
    _TRIPLE_CONSISTENCY_MULTIPLIER

`c_triple` of the `(zeta, eta, h)` consistency check `|zeta' S_4 eta - (1 - h)|
<= c_triple * eps * max(1, ||zeta|| ||eta||)` (theory 9.4 uses the identity to
verify (K2) and (O3)); a triple failing it is an `ArgumentError` (it did not
come from (D8)). PROVISIONAL; measured 2026-09-12 (stage 4a record,
"Derived windows") on the 260 fixture triples: must-accept extreme `0.914`
(the ratio to `eps max(1, ||zeta|| ||eta||)`, the (D8) triple of "trial-011
crab k=kc(1-0.0001)"); must-reject extreme `4.503e3` (`h + 1e-12` on "dense
k=111"). Window by the one-tenth / ten rule `[9.14, 450]`; 64 lies inside
it. `h + 1e-13` (ratio 449), `h + 1e-14` (44.8) and the REPORT triples
carrying the (D11) `h` (up to 315 on the crab ladder) are UNLABELLED: the
rule classifies neither, and the code's verdict on them is not a claim of
this docstring.
"""
const _TRIPLE_CONSISTENCY_MULTIPLIER = 64.0

"""
    _LONGITUDINAL_ELLIPTIC_MULTIPLIER

`c_ell` of the elliptic test on `Mbar_s`: `|tr Mbar_s| < 2 - c_ell * eps *
max(1, ||Mbar_s||_F)` is required for the 2x2 Courant-Snyder normalizer
`Ubar_s` of (K9); otherwise `U_6`, the projected optics of the third mode
and the covariance are unavailable with `:unit_eigenvalue` (a shear or a
hyperbolic longitudinal block; the coasting branch of Part A handles the
shear before this file is reached). PROVISIONAL; measured 2026-09-12 (stage
4a record, "Derived windows"): the smallest must-accept margin ratio `(2 -
|tr|) / (eps max(1, ||Mbar_s||))` over the fixture longitudinal blocks is
`1.998e9` (the weak-cavity map, `mu_s = 8.4e-4`); must-reject extremes: the
shears and `R(1e-8)` (ratio 0, `tr` rounds to 2) and `R(3e-8)` (ratio 2.83,
`2 - tr` within the roundoff `2 eps` of `tr` itself). Window by the
one-tenth / ten rule `[28.3, 2.0e8]`; 64 lies inside it, a factor 2.3 above
the lower edge. `R(1e-7)` (ratio 31.8) and `R(1e-6)` (3185) are UNLABELLED:
the rule classifies neither, and the code's verdict on them is not a claim
of this docstring; the (E5) branch of `_twiss_from_block` is well defined at
`R(1e-6)`.
"""
const _LONGITUDINAL_ELLIPTIC_MULTIPLIER = 64.0

"""
    _OHMI_POSITIVITY_MULTIPLIER

`c_ohmi` of the Ohmi domain: the factor (O2) needs `h > c_ohmi * eps *
max(1, ||zeta|| ||eta||)` (a positive `h` beyond roundoff); `h` at or below
that is `:singular_longitudinal_projection` (h = 0: the graph itself is
unavailable) and a negative `h` beyond it is `:form_inadmissible` with the
detail "outside the positive-root representation (O2) for this mode
selection" (theory 9.4). PROVISIONAL; measured 2026-09-12 (stage 4a record,
"Derived windows"): the smallest must-accept `h / (eps max(1, ||zeta||
||eta||))` over the positive-h fixtures is `2.252e14` ("prescribed h=0.05");
must-reject extremes `h = 0` (ratio 0) and the prescribed construction `h =
1e-15` (ratio 4.40, `h` within a few eps of 0); a negative `h` is refused by
sign, not by this constant. Window by the one-tenth / ten rule `[44.0,
2.25e13]`; 64 lies inside it, a factor 1.5 above the lower edge. The
synthetic `h = 1e-14` (ratio 44.0) and `2e-14` (87.9) are UNLABELLED: the
rule classifies neither, and the code's verdict on them is not a claim of
this docstring.
"""
const _OHMI_POSITIVITY_MULTIPLIER = 64.0

# ---------------------------------------------------------------------------
# Result structs.

"""
    CanonicalSeparation

The ordered separation (D3), (K1)-(K8) of a scaled 6x6 map for a dispersion
triple `(zeta, eta, h)` (dossier E11). Fields: `zeta`, `eta`, `h`,
`triple_consistency` (`|zeta' S_4 eta - (1 - h)|`); `transformation` `M_cal`
(D3) and `inverse` (K2) with `inverse_residual` (`||M_cal inverse - I||_F`) and
`symplecticity` (`||M_cal' S_6 M_cal - S_6||_F`, (K1), holds for every h);
`separated` (`Mbar = inverse M M_cal`), `transverse_map` (`Mbar_beta`, 4x4),
`longitudinal_map` (`Mbar_s`, 2x2), `off_diagonal_residual` (the (K4) 4x2
and 2x4 blocks, Frobenius, one number), `transverse_symplecticity` and
`longitudinal_symplecticity` (K5), `k7_difference` (a `Determined{Float64}`: the
(K7) blocks against the (K4) blocks, unique when `h != 0`),
`k8_residual` (`||M_rr' S_4 M_rr + M_lr' S_2 M_lr - S_4||_F`, an identity of
every symplectic map and the convention self-test), `raw_transverse_defect`
(`||M_lr' S_2 M_lr||_F`, the symplectic defect of the raw `M_rr`), `status`
(`:none`, or `:not_invariant` when the off-diagonal residual exceeds its
tolerance; everything is still reported).
"""
struct CanonicalSeparation
    zeta::Vector{Float64}
    eta::Vector{Float64}
    h::Float64
    triple_consistency::Float64
    transformation::Matrix{Float64}
    inverse::Matrix{Float64}
    inverse_residual::Float64
    symplecticity::Float64
    separated::Matrix{Float64}
    transverse_map::Matrix{Float64}
    longitudinal_map::Matrix{Float64}
    off_diagonal_residual::Float64
    transverse_symplecticity::Float64
    longitudinal_symplecticity::Float64
    k7_difference::Determined{Float64}
    k8_residual::Float64
    raw_transverse_defect::Float64
    status::Symbol
end

"""
    ProjectedOptics6D

The physical projected optics of theory 9.3 read from the full normalizer
`U_6` (K9), (K12)-(K13): `normalizer` `U_6`, its `symplecticity`
(`||U_6' S_6 U_6 - S_6||_F`) and `reconstruction` (the (I1) form of
`M U_6 - U_6 diag(R(mu_1), R(mu_2), R(mu_s))`); the three oriented complex
`vectors` `u_j` (columns `[Re, -Im]` pairs of `U_6`), `tunes`; the 3x3
arrays `beta`, `alpha`, `gamma`, `signed_areas` over modes `j` (rows: 1, 2,
s) and planes `a` (columns: x, y, z) by (M1)/(K12); `row_sums`,
`column_sums` (each one), `kappa_sz_minus_h` (`kappa_sz = h`, (K12));
`m5_residual` (the largest `|beta gamma - alpha^2 - kappa^2|`);
`k13_residual` (the largest (K13) block residual over the nine (j, a));
`projectors` `P_j` and `covariances` `G_j` (6x6, from `u_j u_j'`).
"""
struct ProjectedOptics6D
    normalizer::Matrix{Float64}
    symplecticity::Float64
    reconstruction::NamedTuple{(:normalized, :raw), Tuple{Float64, Float64}}
    vectors::NTuple{3,Vector{ComplexF64}}
    tunes::NTuple{3,Float64}
    beta::Matrix{Float64}
    alpha::Matrix{Float64}
    gamma::Matrix{Float64}
    signed_areas::Matrix{Float64}
    row_sums::Vector{Float64}
    column_sums::Vector{Float64}
    kappa_sz_minus_h::Float64
    m5_residual::Float64
    k13_residual::Float64
    projectors::NTuple{3,Matrix{Float64}}
    covariances::NTuple{3,Matrix{Float64}}
end

"""
    MatchedCovariance6D

(K10)/(K12) for given rms mode emittances `(eps_1, eps_2, eps_s)`: `sigma`
(`U_6 diag(eps) U_6'`), `by_modes` (`sum_j eps_j G_j`, and
`decomposition_residual` its difference from `sigma`), `closure_residual`
(`||M sigma M' - sigma||_F`), `symmetry_residual`, `min_eigenvalue` (PSD
margin), `bunch_length_squared` (`sum_j eps_j (G_j)_zz`), `k14_residual`
(the largest `|(G_j)_zz - eta' S_4 Gbar_j S_4' eta|` over the betatron
modes, from the barred 4D covariances), `emittances`.
"""
struct MatchedCovariance6D
    emittances::NTuple{3,Float64}
    sigma::Matrix{Float64}
    by_modes::Matrix{Float64}
    decomposition_residual::Float64
    closure_residual::Float64
    symmetry_residual::Float64
    min_eigenvalue::Float64
    bunch_length_squared::Float64
    k14_residual::Float64
end

"""
    OhmiFactorization

The Ohmi-Hirata-Oide transverse-longitudinal factor (O2)-(O5) for `h > 0`:
`transformation` `M_O`, `inverse` (O3), `inverse_residual`, `symplecticity`
(`||M_O' S_6 M_O - S_6||_F`), `separated_off_diagonal` (the (O1)
off-diagonal residual of `M_O^-1 M M_O`), `chart_change` (`M_O^-1 M_cal`,
(O5)) with `chart_change_off_diagonal` (its off-diagonal residual) and
`chart_change_block_symplecticity` (both blocks), `graph_difference`
(`||[zeta, eta / h] - D_graph||` from (O4) against the caller's graph).
"""
struct OhmiFactorization
    transformation::Matrix{Float64}
    inverse::Matrix{Float64}
    inverse_residual::Float64
    symplecticity::Float64
    separated_off_diagonal::Float64
    chart_change::Matrix{Float64}
    chart_change_off_diagonal::Float64
    chart_change_block_symplecticity::Float64
    graph_difference::Float64
end

# ---------------------------------------------------------------------------
# The elementary factors and the ordered transformation (theory 8.1, 9.1),
# implemented.

"""
    _dispersion_factors(zeta, eta) -> (M_eta, M_zeta)

(D2): `M_eta` carries `eta` in the pz column (6) of the transverse rows and
`eta' S_4` in the z row (5); `M_zeta` carries `zeta` in the z column (5) and
`-zeta' S_4` in the pz row (6). Built as elementary shears, not from the
expanded product (the note's `elementary_factors`).
"""
function _dispersion_factors(zeta::AbstractVector{<:Real}, eta::AbstractVector{<:Real})
    (length(zeta) == 4 && length(eta) == 4) || throw(ArgumentError("_dispersion_factors takes two 4-vectors"))
    S4 = _symplectic_form(4)
    Me = Matrix{Float64}(I, 6, 6); Mz = Matrix{Float64}(I, 6, 6)
    e = Vector{Float64}(eta); z = Vector{Float64}(zeta)
    Me[1:4, 6] .= e;  Me[5, 1:4] .= transpose(S4) * e      # the row eta' S_4 stored as the column S_4' eta
    Mz[1:4, 5] .= z;  Mz[6, 1:4] .= -(transpose(S4) * z)   # the row -zeta' S_4 stored as the column -S_4' zeta
    return (M_eta=Me, M_zeta=Mz)
end

"""
    _dispersion_transformation(zeta, eta) -> (M_cal, h)

(D3) `M_cal = M_zeta M_eta` with `h = 1 - zeta' S_4 eta`; the caller checks
the product against the displayed block form (the (1,1) block `I_4 + zeta
eta' S_4`, the (3,3) entry `h`).
"""
function _dispersion_transformation(zeta::AbstractVector{<:Real}, eta::AbstractVector{<:Real})
    f = _dispersion_factors(zeta, eta)
    h = 1 - dot(zeta, _symplectic_form(4) * Vector{Float64}(eta))
    return (M_cal=f.M_zeta * f.M_eta, h=h)
end

"""
    _dispersion_transformation_inverse(zeta, eta, h) -> Matrix{Float64}

(K2), closed form without `1 / h`:
`[I_4 - eta zeta' S_4, -zeta, -eta; -eta' S_4, h, 0; zeta' S_4, 0, 1]`.
"""
function _dispersion_transformation_inverse(zeta::AbstractVector{<:Real}, eta::AbstractVector{<:Real}, h::Real)
    S4 = _symplectic_form(4)
    z = Vector{Float64}(zeta); e = Vector{Float64}(eta)
    Minv = zeros(6, 6)
    Minv[1:4, 1:4] .= I(4) - e * transpose(transpose(S4) * z)     # eta zeta' S_4 = eta (S_4' zeta)'
    Minv[1:4, 5] .= -z
    Minv[1:4, 6] .= -e
    Minv[5, 1:4] .= -(transpose(S4) * e)                          # -eta' S_4
    Minv[5, 5] = h
    Minv[6, 1:4] .= transpose(S4) * z                             # zeta' S_4
    Minv[6, 6] = 1.0
    return Minv
end

# ---------------------------------------------------------------------------
# Separation, transverse optics, normalizer, projections, covariance, Ohmi
# (dossier E11-E12).

"""
    _canonical_separation(M, zeta, eta, h) -> CanonicalSeparation

Dossier E11, theory 9.1-9.2: the triple check `|zeta' S_4 eta - (1 - h)|`
(ArgumentError above `_TRIPLE_CONSISTENCY_MULTIPLIER eps max(1, ||zeta||
||eta||)`), `M_cal` (D3) and (K2) with `inverse_residual` and (K1)
`symplecticity`; `Mbar = M_cal^-1 M M_cal`, its blocks, the (K4)
off-diagonal residual against `_SEPARATION_RESIDUAL_MULTIPLIER eps
kappa_sep` (`:not_invariant` above it, everything still reported), (K5)
block symplecticities, the (K7) blocks against (K4) when `h != 0`, (K8) and
the raw transverse defect.
"""
function _canonical_separation(M::AbstractMatrix{<:Real}, zeta::AbstractVector{<:Real}, eta::AbstractVector{<:Real}, h::Real)
    size(M) == (6, 6) || throw(ArgumentError("_canonical_separation takes a 6x6 map, got $(size(M))"))
    (length(zeta) == 4 && length(eta) == 4) || throw(ArgumentError("_canonical_separation takes 4-vectors zeta, eta"))
    all(isfinite, M) && all(isfinite, zeta) && all(isfinite, eta) && isfinite(h) ||
        throw(ArgumentError("_canonical_separation needs finite inputs"))
    S4 = _symplectic_form(4); S2 = _symplectic_form(2); S6 = _symplectic_form(6)
    z = Vector{Float64}(zeta); e = Vector{Float64}(eta); hh = Float64(h)
    consistency = abs(dot(z, S4 * e) - (1 - hh))
    consistency <= _TRIPLE_CONSISTENCY_MULTIPLIER * eps() * max(1.0, norm(z) * norm(e)) ||
        throw(ArgumentError("_canonical_separation: the triple (zeta, eta, h) is inconsistent: |zeta' S_4 eta - (1 - h)| = $(consistency) (it did not come from (D8))"))
    Mcal = _dispersion_transformation(z, e).M_cal
    Minv = _dispersion_transformation_inverse(z, e, hh)
    inverse_residual = norm(Mcal * Minv - I)
    symplecticity = norm(transpose(Mcal) * S6 * Mcal - S6)
    Mf = Matrix{Float64}(M)
    Mbar = Minv * Mf * Mcal
    Mb = Mbar[1:4, 1:4]; Ms = Mbar[5:6, 5:6]
    off = sqrt(norm(Mbar[1:4, 5:6])^2 + norm(Mbar[5:6, 1:4])^2)
    kappa_sep = max(1.0, norm(Mf)) * norm(Mcal) * norm(Minv)
    status = off <= _SEPARATION_RESIDUAL_MULTIPLIER * eps() * kappa_sep ? :none : :not_invariant
    tsym = norm(transpose(Mb) * S4 * Mb - S4)
    lsym = norm(transpose(Ms) * S2 * Ms - S2)
    Mrr = Mf[1:4, 1:4]; Mrl = Mf[1:4, 5:6]; Mlr = Mf[5:6, 1:4]; Mll = Mf[5:6, 5:6]
    k7 = if hh != 0
        D = hcat(z, e ./ hh)                                                # (D7)
        A = I(4) - e * transpose(transpose(S4) * z)                         # I_4 - eta zeta' S_4
        Ainv = I(4) + e * transpose(transpose(S4) * z) ./ hh                # I_4 + eta zeta' S_4 / h
        Mb7 = A * (Mrr - D * Mlr) * Ainv
        Ms7 = Diagonal([1.0, 1 / hh]) * (Mlr * D + Mll) * Diagonal([1.0, hh])
        Determined(sqrt(norm(Mb7 - Mb)^2 + norm(Ms7 - Ms)^2))
    else
        Determined{Float64}(:singular_longitudinal_projection, "(K7) needs h != 0; h = 0")
    end
    k8 = norm(transpose(Mrr) * S4 * Mrr + transpose(Mlr) * S2 * Mlr - S4)
    raw_defect = norm(transpose(Mlr) * S2 * Mlr)
    return CanonicalSeparation(z, e, hh, consistency, Mcal, Minv, inverse_residual, symplecticity,
                               Mbar, Mb, Ms, off, tsym, lsym, k7, k8, raw_defect, status)
end

"The `Determined` payload of `_longitudinal_normalizer`: `(normalizer, beta, alpha, gamma, tune, reconstruction)` (a file-local type alias, not a vocabulary)."
const _LONG_NORMALIZER_T = NamedTuple{(:normalizer, :beta, :alpha, :gamma, :tune, :reconstruction),
                                      Tuple{Matrix{Float64}, Float64, Float64, Float64, Float64, Float64}}

"""
    _longitudinal_normalizer(Mbar_s; multiplier=_LONGITUDINAL_ELLIPTIC_MULTIPLIER) -> Determined{NamedTuple}

The 2x2 Courant-Snyder normalizer of the separated longitudinal block: with
`(beta_s, alpha_s, mu_s)` from stage 2's `_twiss_from_block` (the (E5)
branch of the tune), `Ubar_s = _courant_snyder_B(beta_s, alpha_s)` so that
`Ubar_s^-1 Mbar_s Ubar_s = R(mu_s)`; unavailable with `:unit_eigenvalue`
when `|tr Mbar_s| >= 2 - multiplier eps max(1, ||Mbar_s||_F)` (a shear or a
hyperbolic block). Returns `(normalizer, beta, alpha, gamma, tune,
reconstruction)`.
"""
function _longitudinal_normalizer(Mbar_s::AbstractMatrix{<:Real}; multiplier::Real=_LONGITUDINAL_ELLIPTIC_MULTIPLIER)
    size(Mbar_s) == (2, 2) || throw(ArgumentError("_longitudinal_normalizer takes a 2x2 block, got $(size(Mbar_s))"))
    multiplier >= 0 || throw(ArgumentError("_longitudinal_normalizer: multiplier must be non-negative, got $(multiplier)"))
    Ms = Matrix{Float64}(Mbar_s)
    all(isfinite, Ms) || throw(ArgumentError("_longitudinal_normalizer needs a finite block"))
    tr_s = Ms[1, 1] + Ms[2, 2]
    margin = 2 - multiplier * eps() * max(1.0, norm(Ms))
    abs(tr_s) < margin || return Determined{_LONG_NORMALIZER_T}(:unit_eigenvalue,
        "|tr Mbar_s| = $(abs(tr_s)) is not below $(margin): a shear or a hyperbolic longitudinal block")
    tw = _twiss_from_block(Ms)
    is_determined(tw) || return Determined{_LONG_NORMALIZER_T}(tw.reason, tw.detail)
    t = tw.value
    B = _courant_snyder_B(t.beta, t.alpha)
    s, c = sincos(t.mu)
    R = [c s; -s c]
    reconstruction = norm(Ms * B - B * R) / max(1.0, norm(Ms * B), norm(B))
    return Determined((normalizer=B, beta=t.beta, alpha=t.alpha, gamma=t.gamma, tune=t.mu, reconstruction=reconstruction))
end

"""
    _full_normalizer_6d(sep::CanonicalSeparation, Ubar_beta, Ubar_s, tunes) -> ProjectedOptics6D

Dossier E12, theory 9.3: `U_6 = M_cal diag(Ubar_beta, Ubar_s)` (K9), its
symplecticity, the (I1) reconstruction against `diag(R(mu_1), R(mu_2),
R(mu_s))`; the three oriented vectors `u_j = U_6[:, 2j-1] - i U_6[:, 2j]`
((E6) inverted), the (M1)/(K12) per-plane projections, the row and column
sums, `kappa_sz - h`, the (M5) residual, the (K13) block residual, `P_j`,
`G_j`.
"""
function _full_normalizer_6d(sep::CanonicalSeparation, Ubar_beta::AbstractMatrix{<:Real}, Ubar_s::AbstractMatrix{<:Real},
                             tunes::NTuple{3,<:Real})
    size(Ubar_beta) == (4, 4) || throw(ArgumentError("_full_normalizer_6d: Ubar_beta is 4x4, got $(size(Ubar_beta))"))
    size(Ubar_s) == (2, 2) || throw(ArgumentError("_full_normalizer_6d: Ubar_s is 2x2, got $(size(Ubar_s))"))
    all(isfinite, Ubar_beta) && all(isfinite, Ubar_s) && all(isfinite, tunes) ||
        throw(ArgumentError("_full_normalizer_6d needs finite normalizers and tunes"))
    S6 = _symplectic_form(6)
    Ub = zeros(6, 6); Ub[1:4, 1:4] .= Ubar_beta; Ub[5:6, 5:6] .= Ubar_s
    U6 = sep.transformation * Ub                                              # (K9)
    symplecticity = norm(transpose(U6) * S6 * U6 - S6)
    mus = (Float64(tunes[1]), Float64(tunes[2]), Float64(tunes[3]))
    Rot = zeros(6, 6)
    for j in 1:3
        Rot[2j-1:2j, 2j-1:2j] .= _rotation2(mus[j])
    end
    M = sep.transformation * sep.separated * sep.inverse                      # the physical map, M_cal Mbar M_cal^-1
    rec = _invariance_residual(M, U6, Rot)
    vectors = ntuple(j -> ComplexF64.(U6[:, 2j-1]) .- im .* U6[:, 2j], 3)    # (E6) inverted
    beta = zeros(3, 3); alpha = zeros(3, 3); gamma = zeros(3, 3); kappa = zeros(3, 3)
    for j in 1:3, a in 1:3
        q = vectors[j][2a-1]; p = vectors[j][2a]
        beta[j, a] = abs2(q); alpha[j, a] = -real(conj(q) * p); gamma[j, a] = abs2(p)
        kappa[j, a] = -imag(conj(q) * p)                                       # (M1)/(K12), signed
    end
    row_sums = vec(sum(kappa; dims=2)); column_sums = vec(sum(kappa; dims=1))
    m5 = maximum(abs.(beta .* gamma .- alpha .^ 2 .- kappa .^ 2))
    projectors = ntuple(j -> -imag(vectors[j] * transpose(conj(vectors[j]))) * S6, 3)   # P_j = -Im(u u') S_6
    covariances = ntuple(j -> real(vectors[j] * transpose(conj(vectors[j]))), 3)         # G_j = Re(u u')
    k13 = 0.0
    for j in 1:3, a in 1:3
        s, c = sincos(mus[j]); idx = 2a-1:2a
        blk = (M * projectors[j])[idx, idx]
        rhs = kappa[j, a] * c * Matrix(1.0I, 2, 2) + s * [alpha[j, a] beta[j, a]; -gamma[j, a] -alpha[j, a]]
        k13 = max(k13, norm(blk - rhs))
    end
    return ProjectedOptics6D(U6, symplecticity, (normalized=rec.normalized, raw=rec.raw), vectors, mus,
                             beta, alpha, gamma, kappa, row_sums, column_sums, kappa[3, 3] - sep.h, m5, k13,
                             projectors, covariances)
end

"""
    _matched_covariance_6d(M, optics::ProjectedOptics6D, emittances, Gbar, eta) -> MatchedCovariance6D

(K10)/(K12)/(K14) for the scaled map `M` (passed explicitly: `optics` stores
the normalizer, not the map) and the full normalizer of `optics`:
`sigma = U_6 diag(eps_1, eps_1, eps_2, eps_2, eps_s, eps_s) U_6'`, `sum_j eps_j
G_j`, closure `||M sigma M' - sigma||_F`, symmetry, the PSD margin (smallest
eigenvalue of the symmetrized `sigma`), `sigma_z^2 = sum_j eps_j (G_j)_zz`,
and the (K14) check `(G_j)_zz = eta' S_4 Gbar_j S_4' eta` for the betatron
modes with the barred 4D covariances `Gbar` (the 4D frame's `covariances`)
and the canonical `eta`. Emittances are a 3-tuple of non-negative finite
reals (ArgumentError otherwise).
"""
function _matched_covariance_6d(M::AbstractMatrix{<:Real}, optics::ProjectedOptics6D, emittances,
                                Gbar::NTuple{2,<:AbstractMatrix{<:Real}}, eta::AbstractVector{<:Real})
    (emittances isa Tuple && length(emittances) == 3 && all(x -> x isa Real, emittances)) ||
        throw(ArgumentError("_matched_covariance_6d: emittances must be a 3-tuple of reals (eps_1, eps_2, eps_s), got $(emittances)"))
    eps3 = (Float64(emittances[1]), Float64(emittances[2]), Float64(emittances[3]))
    all(x -> isfinite(x) && x >= 0, eps3) || throw(ArgumentError("_matched_covariance_6d: emittances must be non-negative and finite, got $(emittances)"))
    size(M) == (6, 6) || throw(ArgumentError("_matched_covariance_6d takes a 6x6 map, got $(size(M))"))
    all(g -> size(g) == (4, 4), Gbar) || throw(ArgumentError("_matched_covariance_6d: Gbar holds two 4x4 barred covariances, got sizes $(map(size, Gbar))"))
    length(eta) == 4 || throw(ArgumentError("_matched_covariance_6d: eta is a 4-vector, got length $(length(eta))"))
    U6 = optics.normalizer
    E = Diagonal([eps3[1], eps3[1], eps3[2], eps3[2], eps3[3], eps3[3]])
    sigma = U6 * E * transpose(U6)                                            # (K10)
    by_modes = sum(eps3[j] .* optics.covariances[j] for j in 1:3)             # (K12)
    decomposition = norm(sigma - by_modes)
    Mf = Matrix{Float64}(M)
    closure = norm(Mf * sigma * transpose(Mf) - sigma)
    symmetry = norm(sigma - transpose(sigma))
    min_eig = minimum(eigvals(Symmetric((sigma + transpose(sigma)) / 2)))
    bunch = sum(eps3[j] * optics.covariances[j][5, 5] for j in 1:3)
    S4 = _symplectic_form(4); e = Vector{Float64}(eta); w = transpose(S4) * e   # S_4' eta
    k14 = maximum(abs(optics.covariances[j][5, 5] - dot(w, Gbar[j] * w)) for j in 1:2)   # (K14)
    return MatchedCovariance6D(eps3, sigma, by_modes, decomposition, closure, symmetry, min_eig, bunch, k14)
end

"""
    _ohmi_factorization(M, zeta, eta, h, M_cal, D_graph) -> Determined{OhmiFactorization}

Theory 9.4 (O2)-(O5), dossier E12: available iff `h > _OHMI_POSITIVITY_MULTIPLIER
eps max(1, ||zeta|| ||eta||)`; `h` at or below that in modulus is
`:singular_longitudinal_projection`, a negative `h` beyond it is
`:form_inadmissible` ("outside the positive-root representation (O2) for
this mode selection"). Otherwise `M_O`, (O3), the residuals, the (O1)
off-diagonal of `M_O^-1 M M_O`, the chart change (O5) against `M_cal`, and
the (O4) graph difference against `D_graph`.
"""
function _ohmi_factorization(M::AbstractMatrix{<:Real}, zeta::AbstractVector{<:Real}, eta::AbstractVector{<:Real}, h::Real,
                             M_cal::AbstractMatrix{<:Real}, D_graph::AbstractMatrix{<:Real})
    size(M) == (6, 6) || throw(ArgumentError("_ohmi_factorization takes a 6x6 map, got $(size(M))"))
    (length(zeta) == 4 && length(eta) == 4) || throw(ArgumentError("_ohmi_factorization takes 4-vectors zeta, eta"))
    size(M_cal) == (6, 6) || throw(ArgumentError("_ohmi_factorization: M_cal is 6x6, got $(size(M_cal))"))
    size(D_graph) == (4, 2) || throw(ArgumentError("_ohmi_factorization: D_graph is 4x2, got $(size(D_graph))"))
    z = Vector{Float64}(zeta); e = Vector{Float64}(eta); hh = Float64(h)
    all(isfinite, M) && all(isfinite, z) && all(isfinite, e) && isfinite(hh) && all(isfinite, M_cal) && all(isfinite, D_graph) ||
        throw(ArgumentError("_ohmi_factorization needs finite inputs"))
    floor_h = _OHMI_POSITIVITY_MULTIPLIER * eps() * max(1.0, norm(z) * norm(e))
    if abs(hh) <= floor_h
        return Determined{OhmiFactorization}(:singular_longitudinal_projection,
            "|h| = $(abs(hh)) is at or below $(floor_h): (O2)-(O5) and the graph are unavailable at h = 0")
    elseif hh < 0
        return Determined{OhmiFactorization}(:form_inadmissible,
            "h = $(hh) < 0: outside the positive-root representation (O2) for this mode selection")
    end
    S4 = _symplectic_form(4); S6 = _symplectic_form(6)
    r = sqrt(hh)
    zS = transpose(S4) * z; eS = transpose(S4) * e                            # the rows zeta' S_4, eta' S_4 as columns
    A = (z * transpose(eS) - e * transpose(zS)) ./ (1 + r)                    # (zeta eta' - eta zeta') S_4 / (1 + sqrt h)
    MO = zeros(6, 6); MOi = zeros(6, 6)
    MO[1:4, 1:4] .= I(4) + A;  MOi[1:4, 1:4] .= I(4) + A
    MO[1:4, 5] .= r .* z;      MOi[1:4, 5] .= -r .* z
    MO[1:4, 6] .= e ./ r;      MOi[1:4, 6] .= -e ./ r
    MO[5, 1:4] .= eS ./ r;     MOi[5, 1:4] .= -eS ./ r
    MO[6, 1:4] .= -r .* zS;    MOi[6, 1:4] .= r .* zS
    MO[5, 5] = r; MO[6, 6] = r; MOi[5, 5] = r; MOi[6, 6] = r                 # (O2), (O3)
    inverse_residual = norm(MO * MOi - I)
    symplecticity = norm(transpose(MO) * S6 * MO - S6)
    Mf = Matrix{Float64}(M)
    MbO = MOi * Mf * MO
    sep_off = sqrt(norm(MbO[1:4, 5:6])^2 + norm(MbO[5:6, 1:4])^2)            # (O1)
    C = MOi * Matrix{Float64}(M_cal)                                          # (O5)
    c_off = sqrt(norm(C[1:4, 5:6])^2 + norm(C[5:6, 1:4])^2)
    S2 = _symplectic_form(2)
    c_sym = sqrt(norm(transpose(C[1:4, 1:4]) * S4 * C[1:4, 1:4] - S4)^2 + norm(transpose(C[5:6, 5:6]) * S2 * C[5:6, 5:6] - S2)^2)
    graph_difference = norm(hcat(z, e ./ hh) - Matrix{Float64}(D_graph))    # (O4)
    return Determined(OhmiFactorization(MO, MOi, inverse_residual, symplecticity, sep_off, C, c_off, c_sym, graph_difference))
end

# ---------------------------------------------------------------------------
# Part C chaining (dossier E1, E12a): thin methods on Part A's report and on
# the separation. Nothing below computes a new quantity; each method reads the
# primary triple or chains the stage 2 / stage 3 kernels on the separated
# blocks and propagates every unavailable piece with its own reason.

"""
    _canonical_separation(M, routes::DispersionRoutes) -> CanonicalSeparation

The separation of the PRIMARY result of a [`DispersionRoutes`](@ref) report
(dossier E1): the triple is ONE (D8) evaluation of the primary `graph`
(`_graph_to_dispersion`), so `zeta` and `eta` are the report's to the bit and
`h` is `1 / (1 + D[:, 1]' S_4 D[:, 2])` of the same graph. The report's own
`h` is the eigenplane route's `det U_ls` (D11, dossier E4); it differs from
the (D8) value by roundoff amplified by `cond(U_ls)` (the trial-011 crab map
at `k = k_c (1 - 1e-6)`: `|h| = 354`, gap `2.5e-11 = 316 eps h`), which the
E11 consistency gate `|zeta' S_4 eta - (1 - h)| <= 64 eps max(1, ||zeta||
||eta||)` would reject although every route is `:none` (review 2026-09-12);
the (D8) triple of the graph satisfies the identity to roundoff by
construction, and the separation of that triple holds (`:none`) on the
fixture. When the coasting structure holds the graph is `[0, eta]` and the
triple `zeta = 0`, `h = 1`, the (D24) `eta`, so that `transverse_map` is `M_rr`
and `longitudinal_map` the shear (D25). ArgumentError naming the source (the
primary route, or "the coasting branch") and the reason when any member of
the triple or the graph is not unique (an ambiguity set `eta` with
`:cluster_unresolved`, a `:singular_longitudinal_projection` eigenplane, a
coasting (D24) `:singular_coefficient`, ...), and when `routes.matrix` is not
`M` to the bit.
"""
function _canonical_separation(M::AbstractMatrix{<:Real}, routes::DispersionRoutes)
    size(M) == (6, 6) || throw(ArgumentError("_canonical_separation takes a 6x6 map, got $(size(M))"))
    all(isfinite, M) || throw(ArgumentError("_canonical_separation needs finite inputs"))
    Matrix{Float64}(M) == routes.matrix ||
        throw(ArgumentError("_canonical_separation: the DispersionRoutes report describes a different matrix"))
    source = routes.coasting.holds ? "the coasting branch" : string("primary route :", routes.primary)
    for (name, d) in ((:zeta, routes.zeta), (:eta, routes.eta), (:h, routes.h), (:graph, routes.graph))
        is_determined(d) || throw(ArgumentError(string("_canonical_separation: the primary triple's ", name,
            " is not unique (", source, ", reason :", d.reason, "): ", d.detail)))
    end
    g = _graph_to_dispersion(determined_value(routes.graph))      # one (D8) evaluation: zeta, eta, h of the same graph
    return _canonical_separation(M, g.zeta, g.eta, g.h)
end

"The NamedTuple `_transverse_optics_6d` returns (its fields are documented there; a file-local type alias, not a vocabulary)."
const _TRANSVERSE_OPTICS_6D_T = NamedTuple{(:rho_M0_bar, :eigenmodes, :frame, :closed_form, :mais_ripken,
                                            :edwards_teng_normalizer, :edwards_teng_map, :edwards_teng_direct,
                                            :longitudinal, :optics),
                                           Tuple{Float64, Eigenmodes4D, Determined{NormalModeFrame4D},
                                                 Determined{ClosedFormCheck4D}, Determined{MaisRipkenSet},
                                                 Determined{EdwardsTengPair}, Determined{EdwardsTengPair},
                                                 Determined{EdwardsTengPair}, Determined{_LONG_NORMALIZER_T},
                                                 Determined{ProjectedOptics6D}}}

"""
    _transverse_optics_6d(sep::CanonicalSeparation; rho_M1, resolution_chord=_DEFAULT_RESOLUTION_CHORD, min_trace_gap, stability_atol) -> NamedTuple

Dossier E12(a)-(c), the integrator's chaining on a separation: the 4D
pipeline on `Mbar_beta = sep.transverse_map` through stage 3's
`_eigenmodes_4d` with `rho_M0_bar = _perturbation_scale(Mbar_beta,
_symplectic_defect(Mbar_beta).frobenius; user_uncertainty=rho_M1).scale`
(the 6D map's error `rho_M1` propagates into the barred block) and the
caller's `resolution_chord`; on a unique frame the stage 2 thin methods
exactly as stage 2 defined them (`_closed_form_check_4d` with the caller's
`min_trace_gap` and `stability_atol`, `_mais_ripken`,
`_edwards_teng_from_normalizer`, `_edwards_teng_from_map` with
`min_trace_gap`, `_edwards_teng_direct`); the longitudinal normalizer of
`sep.longitudinal_map` (E12b); `U_6` and the [`ProjectedOptics6D`](@ref) by
[`_full_normalizer_6d`](@ref) (E12c). Returns the NamedTuple
`(rho_M0_bar, eigenmodes, frame, closed_form, mais_ripken,
edwards_teng_normalizer, edwards_teng_map, edwards_teng_direct,
longitudinal, optics)`: `eigenmodes` (the full `Eigenmodes4D`, clusters
included) is always present; every other piece is a `Determined` that
propagates the frame's reason (`:cluster_unresolved` for the repeated
betatron maps, ...) or the normalizer's (`:unit_eigenvalue` for the coasting
shear); `optics` is unavailable with `:not_invariant` when the separation
itself did not hold (`sep.status`), everything else still computed on the
reported blocks. `min_trace_gap` and `stability_atol` are the stage 2
guards and have no default there, hence none here.
"""
function _transverse_optics_6d(sep::CanonicalSeparation; rho_M1::Real, resolution_chord::Real=_DEFAULT_RESOLUTION_CHORD,
                               min_trace_gap::Real, stability_atol::Real)
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_transverse_optics_6d: rho_M1 must be a finite non-negative number, got $(rho_M1)"))
    Mb = sep.transverse_map
    rho_bar = _perturbation_scale(Mb, _symplectic_defect(Mb).frobenius; user_uncertainty=rho_M1).scale
    e4 = _eigenmodes_4d(Mb; rho_M0=rho_bar, resolution_chord=resolution_chord)
    fr = e4.frame
    lon = _longitudinal_normalizer(sep.longitudinal_map)
    if is_determined(fr)
        f = determined_value(fr)
        cf = _closed_form_check_4d(f; min_trace_gap=min_trace_gap, stability_atol=stability_atol)
        mr = Determined(_mais_ripken(f))
        etn = Determined(_edwards_teng_from_normalizer(f))
        etm = Determined(_edwards_teng_from_map(f; min_trace_gap=min_trace_gap))
        etd = Determined(_edwards_teng_direct(f))
        optics = if sep.status !== :none
            Determined{ProjectedOptics6D}(sep.status, "the separation did not hold (off-diagonal residual $(sep.off_diagonal_residual)): no U_6")
        elseif is_determined(lon)
            l = determined_value(lon)
            Determined(_full_normalizer_6d(sep, f.normalizer, l.normalizer, (f.tunes[1], f.tunes[2], l.tune)))
        else
            Determined{ProjectedOptics6D}(lon.reason, lon.detail)
        end
    else
        cf = Determined{ClosedFormCheck4D}(fr.reason, fr.detail)
        mr = Determined{MaisRipkenSet}(fr.reason, fr.detail)
        etn = Determined{EdwardsTengPair}(fr.reason, fr.detail)
        etm = Determined{EdwardsTengPair}(fr.reason, fr.detail)
        etd = Determined{EdwardsTengPair}(fr.reason, fr.detail)
        optics = Determined{ProjectedOptics6D}(fr.reason, fr.detail)
    end
    return _TRANSVERSE_OPTICS_6D_T((rho_bar, e4, fr, cf, mr, etn, etm, etd, lon, optics))
end
