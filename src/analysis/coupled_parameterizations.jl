# Coupled transverse parameterizations of the optics analysis: the complete
# Mais-Ripken set (theory docs/theory/twiss_dispersion.md Section 6, (M1)-(M16))
# and both Edwards-Teng forms (Section 4, (T1)-(T17); Section 7, (B1)-(B11)),
# with every conversion route of Section 7.5. Stage 2, Part B of the campaign
# (design docs/design/twiss_dispersion_analysis.md, "Staging" item 2, pipeline
# step 11). Pure matrix arithmetic in the conventions of the stage 1 kernel
# (symplectic_linear_algebra.jl): coordinates (x, px, y, py), S_4 = diag(S_2,
# S_2), the oriented eigenvector u_j with u_j' S_4 u_j = -2i (E3), the real
# normalizer U_4 = [Re u_1, -Im u_1, Re u_2, -Im u_2] (E6), tunes mu_j in
# [0, 2 pi) with M U_4 = U_4 diag(R(mu_1), R(mu_2)) (E8).
#
# Inputs are PLAIN arguments (a real normalizer with its tunes, or the two
# oriented complex vectors), so no kernel here depends on the eigenmode frame
# of eigenmodes_4d.jl; the thin methods on `NormalModeFrame4D` at the end of
# this file (stage 2 integration) only unpack that frame. Everything
# is computed on the (already scaled) matrix the caller passes: no scaling in
# this file, the back-transformations are the stage 1 `_unscale_*` table.
#
# Undetermined outputs are `Determined` values with a pinned reason, never NaN:
#   :zero_projection   a relative phase (M6) whose position projection vanishes
#   :form_inadmissible an Edwards-Teng form whose area weight is not positive or
#                      whose 1 + det R is not positive (design step 11: both,
#                      never the sign of det R alone)
#   :unstable_spectrum the map route (4.2) met Delta < 0 or |tau| >= 2 (T14)
#   :singular_coefficient the map route at coincident traces (Delta below the
#                      caller's guard; (T9) is stated for distinct traces)
#   :not_requested     a quantity that needs the tunes when none were passed
# No new reason is added in stage 2 (the vocabulary is pinned in Analysis.jl).

const _MR_PHASE_T = NamedTuple{(:cos, :sin), Tuple{Float64, Float64}}
const _ET_TWISS_T = NamedTuple{(:beta, :alpha, :gamma, :mu), NTuple{4, Float64}}
const _ET_RESIDUAL_T = NamedTuple{(:normalized, :raw), Tuple{Float64, Float64}}

"""
    MaisRipkenSet

The complete Mais-Ripken set of theory Section 6 for two oriented, (E3)-normalized
eigenvectors `u_1, u_2` (runtime representation, may change; not exported).
Indices are `[j, a]`: mode `j` in `1:2`, plane `a` in `1:2` for `(x, y)`.

  * `beta`, `alpha`, `gamma`, `kappa` -- the projected functions (M1):
    `beta_ja = |u_ja|^2`, `alpha_ja = -Re(u_ja* u_jpa)`, `gamma_ja = |u_jpa|^2`,
    the SIGNED area `kappa_ja = -Im(u_ja* u_jpa)`. `gamma` is (M1), never
    `(1 + alpha^2) / beta` (M5).
  * `kappa_row_sums` -- `kappa_jx + kappa_jy`, one per mode (M2, equals 1).
  * `kappa_column_sums` -- `kappa_1a + kappa_2a`, one per plane (M3, equals 1).
  * `m5_residuals` -- `beta_ja gamma_ja - alpha_ja^2 - kappa_ja^2` (M5).
  * `u_from_mode1`, `u_from_mode2`, `u_difference` -- the two evaluations of the
    area partition `u = kappa_1y = kappa_2x` (M4) and their difference. `u` is
    the mode-1 evaluation.
  * `phases` -- per mode the relative phase factors `(cos nu_j, sin nu_j)` of
    (M6) as `Determined`; unavailable with `:zero_projection` when either
    position projection of that mode is below `projection_rtol ||u_j||^2`
    (the design: "the phase fix applies only to nonzero position components").
  * `phase_valid` -- the two flags, `is_determined.(phases)`.
  * `vectors` -- the eigenvectors rephased to the (M7) convention (`u_1x > 0`,
    `u_2y > 0` real) where the primary position projection is nonzero, else the
    input vector unchanged. Rephasing changes nothing in (M1).
  * `projection_rtol` -- the relative floor the flags were decided with.
"""
struct MaisRipkenSet
    beta::Matrix{Float64}
    alpha::Matrix{Float64}
    gamma::Matrix{Float64}
    kappa::Matrix{Float64}
    kappa_row_sums::NTuple{2, Float64}
    kappa_column_sums::NTuple{2, Float64}
    m5_residuals::Matrix{Float64}
    u::Float64
    u_from_mode1::Float64
    u_from_mode2::Float64
    u_difference::Float64
    phases::NTuple{2, Determined{_MR_PHASE_T}}
    phase_valid::NTuple{2, Bool}
    vectors::NTuple{2, Vector{ComplexF64}}
    projection_rtol::Float64
end

"""
    EdwardsTengForm

One Edwards-Teng form (1 or 2, theory (T2)) of a transverse map under a FIXED
labelling of the two eigenmodes (runtime representation; not exported).

  * `form` -- 1 or 2. In form 1 mode 1 is carried by the `(x, px)` block of the
    normal coordinates (B2), in form 2 by the `(y, py)` block (B6); the labels
    never change with the form.
  * `route` -- `:normalizer` ((B10), (B5), (B9)), `:map` ((T9), (T10), (T11)),
    or `:direct` ((B11)).
  * `R` -- the 2x2 coupling matrix, `Determined`; unavailable with
    `:form_inadmissible` only when the block it divides by is singular (area
    weight zero), because then no finite `R` exists for this form.
  * `det_R` -- `det R`, `Determined` with `R`.
  * `area_weight` -- the signed area of the form's primary blocks: `1 - u` for
    form 1 (B3), `u` for form 2 (B7); `lambda^2` when the form is admissible.
    A plain `Float64`, never NaN: when a route's guard leaves the form with no
    `R` at all (the map route's spectrum and trace guards), it is `0.0` and the
    reason is the one carried by `R`, `det_R` and `lambda`.
  * `admissible` -- `1 + det R > 0` AND `area_weight > 0` (design step 11).
  * `lambda` -- `1 / sqrt(1 + det R)` (T3); `:form_inadmissible` otherwise.
  * `twiss` -- per mode `(beta_j, alpha_j, gamma_j, mu_j)` of the unit-area
    Edwards-Teng mode, `gamma_j = (1 + alpha_j^2) / beta_j`; by (B5)/(B9) on the
    normalizer route, (T15)/(T16) on the map route, the `Q_j` of (B11) on the
    direct route. `mu_j` in `[0, 2 pi)` (T16). `:form_inadmissible` when the form
    is not, `:not_requested` when the route was given no tunes.
  * `blocks` -- the normal blocks `(Mbar_1, Mbar_2)` (T11)/(T16), same
    availability as `twiss`.
  * `phases` -- the relative phase factors of (B4) (form 1) or (B8) (form 2),
    `:zero_projection` when a denominator vanishes, `:form_inadmissible` when
    the form is not.
  * `reconstruction_residual` -- the (T5) check in the (I1) form,
    `||M V - V diag(Mbar_1, Mbar_2)|| / max(1, ||M V||, ||V||)` with
    `V = V_form(R)`, plus the raw norm; same availability as `blocks`.
  * `consistency_residual` -- on the normalizer route the difference between
    the two (B10) expressions of the row, `||adj(R) - U_x2 U_y2^{-1}||` (form 1)
    or `||adj(R) - U_x1 U_y1^{-1}||` (form 2); `0.0` on the other routes.
"""
struct EdwardsTengForm
    form::Int
    route::Symbol
    R::Determined{Matrix{Float64}}
    det_R::Determined{Float64}
    area_weight::Float64
    admissible::Bool
    lambda::Determined{Float64}
    twiss::Determined{NTuple{2, _ET_TWISS_T}}
    blocks::Determined{NTuple{2, Matrix{Float64}}}
    phases::Determined{NTuple{2, _MR_PHASE_T}}
    reconstruction_residual::Determined{_ET_RESIDUAL_T}
    consistency_residual::Float64
end

"""
    EdwardsTengPair

Both Edwards-Teng forms of one map under one mode labelling (design step 11:
"both forms are always reported with an admissibility flag each"; the
`preferred_form` option is stage 4). Fields `form1`, `form2` are
[`EdwardsTengForm`](@ref); `u` is the area partition `kappa_1y` the forms were
keyed on (`u = det R_1 / (1 + det R_1) = 1 / (1 + det R_2)`, (B3)/(B7)), a
`Determined` that is unavailable only when the map route's guards left both
forms without an `R`;
`route` names the extraction route shared by both forms. Not exported.
"""
struct EdwardsTengPair
    form1::EdwardsTengForm
    form2::EdwardsTengForm
    u::Determined{Float64}
    route::Symbol
end

# ---------------------------------------------------------------------------
# Shared helpers: argument checks, (E6) both ways, the 2x2 Edwards-Teng pieces.

function _check_mode_vector(u::AbstractVector, name::AbstractString)
    length(u) == 4 || throw(ArgumentError("$(name) must have length 4, got $(length(u))"))
    all(isfinite, u) || throw(ArgumentError("$(name) has a non-finite entry"))
    return Vector{ComplexF64}(u)
end

function _check_normalizer4(U::AbstractMatrix, name::AbstractString)
    size(U) == (4, 4) || throw(ArgumentError("$(name) must be 4x4, got $(size(U))"))
    all(isfinite, U) || throw(ArgumentError("$(name) has a non-finite entry"))
    return Matrix{Float64}(U)
end

function _check_tunes(mu)
    length(mu) == 2 || throw(ArgumentError("tunes must be a pair (mu1, mu2), got $(mu)"))
    all(x -> x isa Real && isfinite(x), mu) || throw(ArgumentError("tunes must be two finite reals, got $(mu)"))
    return (Float64(mu[1]), Float64(mu[2]))
end

"""
    _normalizer_to_vectors(U4) -> (u1, u2)

The inverse of (E6): `u_j = U[:, 2j-1] - i U[:, 2j]` for a real 4x4 normalizer
`U_4 = [Re u_1, -Im u_1, Re u_2, -Im u_2]`.
"""
function _normalizer_to_vectors(U::AbstractMatrix{<:Real})
    U4 = _check_normalizer4(U, "the normalizer U4")
    return (U4[:, 1] .- im .* U4[:, 2], U4[:, 3] .- im .* U4[:, 4])
end

"""
    _vectors_to_normalizer(u1, u2) -> Matrix{Float64}

(E6): `U_4 = [Re u_1, -Im u_1, Re u_2, -Im u_2]`.
"""
function _vectors_to_normalizer(u1::AbstractVector, u2::AbstractVector)
    v1 = _check_mode_vector(u1, "u1"); v2 = _check_mode_vector(u2, "u2")
    return hcat(real.(v1), -imag.(v1), real.(v2), -imag.(v2))
end

# Block of a 4x4 matrix: rows of plane `a` (1 = (x, px), 2 = (y, py)), columns
# of pair `b` (a plane of the physical coordinates, or a mode of the normal ones).
_block22(A::AbstractMatrix, a::Integer, b::Integer) = A[2a-1:2a, 2b-1:2b]

_blockdiag22(A::AbstractMatrix, B::AbstractMatrix) = [A zeros(2, 2); zeros(2, 2) B]

"""
    _edwards_teng_V(form, R) -> Matrix{Float64}

The Edwards-Teng matrix (T2): `V_1(R) = lambda [I adj(R); -R I]`,
`V_2(R) = lambda [adj(R) I; I -R]`, `lambda = 1 / sqrt(1 + det R)` (T3).
`1 + det R <= 0` is an `ArgumentError` (the theory: replacing it by its absolute
value is not a canonical normalization).
"""
function _edwards_teng_V(form::Integer, R::AbstractMatrix{<:Real})
    form in (1, 2) || throw(ArgumentError("the Edwards-Teng form is 1 or 2, got $(form)"))
    size(R) == (2, 2) || throw(ArgumentError("the coupling matrix R is 2x2, got $(size(R))"))
    d = det(R)
    1 + d > 0 || throw(ArgumentError("Edwards-Teng form $(form) needs 1 + det R > 0, got det R = $(d)"))
    lambda = 1 / sqrt(1 + d)
    I2 = Matrix{Float64}(I, 2, 2)
    A = _adjugate2(R)
    return form == 1 ? lambda * [I2 A; -R I2] : lambda * [A I2; I2 -R]
end

"""
    _courant_snyder_B(beta, alpha) -> Matrix{Float64}

The Courant-Snyder normalizer `B_j = [sqrt(beta) 0; -alpha/sqrt(beta) 1/sqrt(beta)]`
(T17); `beta <= 0` is an `ArgumentError`.
"""
function _courant_snyder_B(beta::Real, alpha::Real)
    beta > 0 || throw(ArgumentError("a Courant-Snyder beta must be positive, got $(beta)"))
    s = sqrt(beta)
    return [s 0.0; -alpha / s 1 / s]
end

"""
    _twiss_block(beta, alpha, mu) -> Matrix{Float64}

The 2x2 one-turn block (T16) of a unit-area mode,
`[cos mu + alpha sin mu, beta sin mu; -gamma sin mu, cos mu - alpha sin mu]`
with `gamma = (1 + alpha^2) / beta`; equals `B R(mu) B^{-1}` for (T17).
"""
function _twiss_block(beta::Real, alpha::Real, mu::Real)
    g = (1 + alpha^2) / beta
    s, c = sincos(mu)
    return [c + alpha * s beta * s; -g * s c - alpha * s]
end

"""
    _twiss_from_block(Mbar) -> Determined{(beta, alpha, gamma, mu)}

(T15)/(T16) on a 2x2 normal block: `cos mu = tr/2`,
`sin mu = sign(Mbar_12) sqrt(1 - cos^2 mu)`, `beta = Mbar_12 / sin mu`,
`alpha = (Mbar_11 - Mbar_22) / (2 sin mu)`, `gamma = -Mbar_21 / sin mu`,
`mu = mod(atan2(sin, cos), 2 pi)`. Unavailable with `:unstable_spectrum` when
`|tr| >= 2` (the theory: a significantly unstable trace must not be clipped),
and with `:singular_coefficient` when `sin mu` vanishes (the extraction divides
by it; `mu = 0` or `pi` is the ill-conditioned point the theory names).
"""
function _twiss_from_block(Mbar::AbstractMatrix{<:Real})
    size(Mbar) == (2, 2) || throw(ArgumentError("a normal block is 2x2, got $(size(Mbar))"))
    c = (Mbar[1, 1] + Mbar[2, 2]) / 2
    abs(c) < 1 || return Determined{_ET_TWISS_T}(:unstable_spectrum,
        "normal block trace $(2c) is not inside (-2, 2)")
    s = sign(Mbar[1, 2]) * sqrt(1 - c^2)
    s == 0 && return Determined{_ET_TWISS_T}(:singular_coefficient,
        "sin mu = 0 (Mbar_12 = 0): (T15) divides by sin mu")
    beta = Mbar[1, 2] / s
    alpha = (Mbar[1, 1] - Mbar[2, 2]) / (2s)
    gamma = -Mbar[2, 1] / s
    mu = mod(atan(s, c), 2pi)
    return Determined((beta=beta, alpha=alpha, gamma=gamma, mu=mu))
end

# ---------------------------------------------------------------------------
# Mais-Ripken (Section 6): (M1)-(M8).

"""
    _mais_ripken(u1, u2; projection_rtol=64 eps()) -> MaisRipkenSet
    _mais_ripken(U4; projection_rtol=64 eps()) -> MaisRipkenSet

The complete Mais-Ripken set (Section 6) of the two oriented, (E3)-normalized
eigenvectors `u_1, u_2`, or of the real normalizer `U_4` in the (E6) convention
(converted by [`_normalizer_to_vectors`](@ref)). Every (M1) quantity is
phase-independent and always unique; the relative phase pair of mode `j` (M6)
is `Determined` unavailable with `:zero_projection` when
`sqrt(beta_jx beta_jy) <= projection_rtol ||u_j||^2`, the scale-aware floor
for a vanishing position component (the exactly uncoupled limit lands here for
BOTH modes). `projection_rtol` is a roundoff-scale relative floor, provisional
until the stage 2 measurement. Nothing is checked about the (E3) normalization
or the orientation here: the caller's frame is authoritative, and the (M2)/(M3)
sums in the result say how far from normalized it is.
"""
function _mais_ripken(u1::AbstractVector, u2::AbstractVector; projection_rtol::Real=64 * eps())
    v = (_check_mode_vector(u1, "u1"), _check_mode_vector(u2, "u2"))
    projection_rtol >= 0 || throw(ArgumentError("projection_rtol must be non-negative, got $(projection_rtol)"))
    beta = zeros(2, 2); alpha = zeros(2, 2); gamma = zeros(2, 2); kappa = zeros(2, 2)
    for j in 1:2, a in 1:2
        q = v[j][2a - 1]; p = v[j][2a]
        beta[j, a] = abs2(q)
        alpha[j, a] = -real(conj(q) * p)
        gamma[j, a] = abs2(p)
        kappa[j, a] = -imag(conj(q) * p)                                   # (M1), signed
    end
    m5 = beta .* gamma .- alpha .^ 2 .- kappa .^ 2                          # (M5)
    row_sums = (kappa[1, 1] + kappa[1, 2], kappa[2, 1] + kappa[2, 2])       # (M2)
    col_sums = (kappa[1, 1] + kappa[2, 1], kappa[1, 2] + kappa[2, 2])       # (M3)
    u1_eval = kappa[1, 2]                                                   # (M4) first evaluation
    u2_eval = kappa[2, 1]                                                   # (M4) second evaluation
    # (M6). The primary position component of mode j is x for j = 1, y for
    # j = 2; the phase is that of the secondary relative to the primary.
    phases = ntuple(2) do j
        prim = v[j][j == 1 ? 1 : 3]; sec = v[j][j == 1 ? 3 : 1]
        prod = sqrt(beta[j, 1] * beta[j, 2])
        if prod <= Float64(projection_rtol) * norm(v[j])^2
            Determined{_MR_PHASE_T}(:zero_projection,
                "mode $(j): sqrt(beta_$(j)x beta_$(j)y) = $(prod) is below the floor " *
                "$(Float64(projection_rtol)) ||u_$(j)||^2 = $(Float64(projection_rtol) * norm(v[j])^2)")
        else
            z = sec * conj(prim)
            Determined((cos=real(z) / prod, sin=imag(z) / prod))
        end
    end
    # (M7) convention: u_1x > 0 and u_2y > 0 real where the primary projection
    # is nonzero; the multiplier is conj(prim) / |prim|, no angle evaluated.
    vectors = ntuple(2) do j
        prim = v[j][j == 1 ? 1 : 3]
        abs(prim) > Float64(projection_rtol) * norm(v[j]) ? v[j] .* (conj(prim) / abs(prim)) : v[j]
    end
    return MaisRipkenSet(beta, alpha, gamma, kappa, row_sums, col_sums, m5,
        u1_eval, u1_eval, u2_eval, u1_eval - u2_eval,
        phases, map(is_determined, phases), vectors, Float64(projection_rtol))
end

_mais_ripken(U::AbstractMatrix{<:Real}; kwargs...) = _mais_ripken(_normalizer_to_vectors(U)...; kwargs...)

"""
    _mais_ripken_normalizer(beta, alpha, u, phase1, phase2) -> Matrix{Float64}
    _mais_ripken_normalizer(mr::MaisRipkenSet) -> Determined{Matrix{Float64}}

The real normalizer (M8) of a COMPLETE Mais-Ripken set: the projected `beta[j, a]`
and `alpha[j, a]`, the area partition `u`, and the relative phase factors
`phase_j = (cos nu_j, sin nu_j)` of (M6). It is (E6) applied to the explicit
eigenvectors (M7); the projected gammas are implied through (M13) and are not
inputs. Every `beta[j, a]` must be positive (a zero position projection has no
(M8) chart, theory 6.2), else an `ArgumentError`. The `MaisRipkenSet` method
returns the matrix as `Determined`, unavailable with `:zero_projection` when
either phase pair of the set is.
"""
function _mais_ripken_normalizer(beta::AbstractMatrix{<:Real}, alpha::AbstractMatrix{<:Real},
                                 u::Real, phase1, phase2)
    size(beta) == (2, 2) && size(alpha) == (2, 2) || throw(ArgumentError(
        "beta and alpha are 2x2 [mode, plane] arrays, got $(size(beta)) and $(size(alpha))"))
    all(>(0), beta) || throw(ArgumentError(
        "(M8) needs every projected beta positive (nonzero position projections), got $(beta)"))
    c1, s1 = Float64(phase1.cos), Float64(phase1.sin)
    c2, s2 = Float64(phase2.cos), Float64(phase2.sin)
    b1x, b1y, b2x, b2y = sqrt(beta[1, 1]), sqrt(beta[1, 2]), sqrt(beta[2, 1]), sqrt(beta[2, 2])
    a1x, a1y, a2x, a2y = alpha[1, 1], alpha[1, 2], alpha[2, 1], alpha[2, 2]
    return [b1x                          0.0                        b2x * c2                       -b2x * s2;
            -a1x / b1x                   (1 - u) / b1x              (-a2x * c2 + u * s2) / b2x     (a2x * s2 + u * c2) / b2x;
            b1y * c1                     -b1y * s1                  b2y                            0.0;
            (-a1y * c1 + u * s1) / b1y   (a1y * s1 + u * c1) / b1y  -a2y / b2y                     (1 - u) / b2y]
end

function _mais_ripken_normalizer(mr::MaisRipkenSet)
    for j in 1:2
        is_determined(mr.phases[j]) || return Determined{Matrix{Float64}}(mr.phases[j].reason,
            "mode $(j) has no relative phase: " * mr.phases[j].detail)
    end
    return Determined(_mais_ripken_normalizer(mr.beta, mr.alpha, mr.u,
        determined_value(mr.phases[1]), determined_value(mr.phases[2])))
end

# ---------------------------------------------------------------------------
# Covariance (Section 6.3): (M9)-(M16), 4D only; the 6D (K10)/(K12) route is
# stage 4.

function _check_emittances(emittances)
    length(emittances) == 2 || throw(ArgumentError(
        "two rms mode emittances (eps_1, eps_2) are needed, got $(emittances)"))
    all(e -> isfinite(e) && e >= 0, emittances) || throw(ArgumentError(
        "rms mode emittances must be finite and non-negative, got $(emittances)"))
    return (Float64(emittances[1]), Float64(emittances[2]))
end

"""
    _matched_covariance_4d(U4, emittances) -> Matrix{Float64}
    _matched_covariance_4d(u1, u2, emittances) -> Matrix{Float64}

(M9): the matched covariance `Sigma = U_4 diag(eps_1, eps_1, eps_2, eps_2) U_4'`
of a matched ensemble with uncorrelated modes and rms mode emittances
`emittances = (eps_1, eps_2)`; the vector form evaluates the second expression
of (M9), `sum_j eps_j Re(u_j u_j')`. Both are finite at zero position
projections, unlike (M11)-(M16). Emittances are rms (the theory: a boundary
amplitude `sqrt(2J)` is not an rms emittance).
"""
function _matched_covariance_4d(U::AbstractMatrix{<:Real}, emittances)
    U4 = _check_normalizer4(U, "the normalizer U4")
    e1, e2 = _check_emittances(emittances)
    return U4 * Diagonal([e1, e1, e2, e2]) * transpose(U4)
end

function _matched_covariance_4d(u1::AbstractVector, u2::AbstractVector, emittances)
    v1 = _check_mode_vector(u1, "u1"); v2 = _check_mode_vector(u2, "u2")
    e1, e2 = _check_emittances(emittances)
    return e1 .* real.(v1 * v1') .+ e2 .* real.(v2 * v2')
end

"""
    _mais_ripken_covariance(mr::MaisRipkenSet, emittances) -> Determined{Matrix{Float64}}

The covariance matrix (M12) from the Mais-Ripken functions and the rms mode
emittances `(eps_1, eps_2)`: the diagonal blocks from (M10) and the projected
alphas and gammas of (M1), the cross-plane block from (M11), (M14), (M15),
(M16) with the relative phase factors (M6) and the area partition `u`. The
cross entries carry beta denominators, so the matrix is unavailable with
`:zero_projection` when either phase pair of the set is; (M9) through
[`_matched_covariance_4d`](@ref) remains finite there and defines the limit.
"""
function _mais_ripken_covariance(mr::MaisRipkenSet, emittances)
    e = _check_emittances(emittances)
    for j in 1:2
        is_determined(mr.phases[j]) || return Determined{Matrix{Float64}}(mr.phases[j].reason,
            "mode $(j) has no relative phase, so (M11)-(M16) have no chart: " * mr.phases[j].detail)
    end
    b, a, g, u = mr.beta, mr.alpha, mr.gamma, mr.u
    c1, s1 = determined_value(mr.phases[1]); c2, s2 = determined_value(mr.phases[2])
    Sigma = zeros(4, 4)
    for pl in 1:2                                                          # (M10), (M12) diagonal blocks
        r = 2pl - 1
        Sigma[r, r] = e[1] * b[1, pl] + e[2] * b[2, pl]
        Sigma[r, r + 1] = Sigma[r + 1, r] = -e[1] * a[1, pl] - e[2] * a[2, pl]
        Sigma[r + 1, r + 1] = e[1] * g[1, pl] + e[2] * g[2, pl]
    end
    sb1 = sqrt(b[1, 1] * b[1, 2]); sb2 = sqrt(b[2, 1] * b[2, 2])
    Sigma[1, 3] = e[1] * sb1 * c1 + e[2] * sb2 * c2                                          # (M11)
    Sigma[1, 4] = e[1] * sqrt(b[1, 1] / b[1, 2]) * (-a[1, 2] * c1 + u * s1) -
                  e[2] * sqrt(b[2, 1] / b[2, 2]) * (a[2, 2] * c2 + (1 - u) * s2)            # (M14)
    Sigma[2, 3] = -e[1] * sqrt(b[1, 2] / b[1, 1]) * (a[1, 1] * c1 + (1 - u) * s1) +
                  e[2] * sqrt(b[2, 2] / b[2, 1]) * (-a[2, 1] * c2 + u * s2)                 # (M15)
    Sigma[2, 4] = e[1] / sb1 * ((a[1, 1] * a[1, 2] + u * (1 - u)) * c1 + ((1 - u) * a[1, 2] - u * a[1, 1]) * s1) +
                  e[2] / sb2 * ((a[2, 1] * a[2, 2] + u * (1 - u)) * c2 + ((1 - u) * a[2, 1] - u * a[2, 2]) * s2)  # (M16)
    for (i, k) in ((1, 3), (1, 4), (2, 3), (2, 4))
        Sigma[k, i] = Sigma[i, k]
    end
    return Determined(Sigma)
end

"""
    _mais_ripken_gamma_identities(mr::MaisRipkenSet) -> Matrix{Float64}

The residuals of (M13), `gamma_ja - (alpha_ja^2 + w_ja^2) / beta_ja` with
`w = 1 - u` on the primary plane of each mode and `u` on the secondary, as a
`[mode, plane]` array; `Inf` where the plane's beta vanishes (no chart).
"""
function _mais_ripken_gamma_identities(mr::MaisRipkenSet)
    u = mr.u
    w = [1 - u u; u 1 - u]
    return [mr.beta[j, a] > 0 ? mr.gamma[j, a] - (mr.alpha[j, a]^2 + w[j, a]^2) / mr.beta[j, a] : Inf
            for j in 1:2, a in 1:2]
end

# ---------------------------------------------------------------------------
# Edwards-Teng (Sections 4 and 7). Shared tail: (B4)/(B8) phases, the (T16)
# blocks, the (T5) reconstruction residual, and the assembly of one form.

"""
    _edwards_teng_phases(form, R, beta1, alpha1, beta2, alpha2) -> Determined

The relative phase factors (B4) (form 1) or (B8) (form 2) from the coupling
matrix and the unit-area Edwards-Teng Twiss functions; unavailable with
`:zero_projection` when a denominator vanishes (theory 7.3: "the associated
relative phase is undefined").
"""
function _edwards_teng_phases(form::Integer, R::AbstractMatrix{<:Real},
                              beta1::Real, alpha1::Real, beta2::Real, alpha2::Real)
    r11, r12, r22 = R[1, 1], R[1, 2], R[2, 2]
    if form == 1
        n1 = alpha1 * r12 - beta1 * r11; n2 = alpha2 * r12 + beta2 * r22; sgn = 1.0
    else
        n1 = alpha1 * r12 + beta1 * r22; n2 = alpha2 * r12 - beta2 * r11; sgn = -1.0
    end
    d1 = hypot(n1, r12); d2 = hypot(n2, r12)
    (d1 > 0 && d2 > 0) || return Determined{NTuple{2, _MR_PHASE_T}}(:zero_projection,
        "a (B$(form == 1 ? 4 : 8)) denominator vanishes: ($(d1), $(d2))")
    return Determined(((cos=n1 / d1, sin=sgn * r12 / d1), (cos=n2 / d2, sin=sgn * r12 / d2)))
end

# (T5) as a residual: M V = V diag(Mbar_1, Mbar_2) in the (I1) form on V = V_form(R).
function _edwards_teng_reconstruction(form::Integer, R::AbstractMatrix{<:Real},
                                      blocks, M::AbstractMatrix{<:Real})
    V = _edwards_teng_V(form, R)
    r = _invariance_residual(M, V, _blockdiag22(blocks[1], blocks[2]))
    return (normalized=r.normalized, raw=r.raw)
end

# An EdwardsTengForm whose tail (twiss, blocks, phases, reconstruction) is
# unavailable for one reason; `R`, `det_R`, `lambda` are passed as computed.
function _edwards_teng_form_tail_unavailable(form::Integer, route::Symbol, Rd::Determined{Matrix{Float64}},
                                             det_d::Determined{Float64}, weight::Real, admissible::Bool,
                                             lambda::Determined{Float64}, reason::Symbol,
                                             detail::AbstractString, consistency::Real)
    return EdwardsTengForm(form, route, Rd, det_d, Float64(weight), admissible, lambda,
        Determined{NTuple{2, _ET_TWISS_T}}(reason, detail),
        Determined{NTuple{2, Matrix{Float64}}}(reason, detail),
        Determined{NTuple{2, _MR_PHASE_T}}(reason, detail),
        Determined{_ET_RESIDUAL_T}(reason, detail), Float64(consistency))
end

# Assemble one form. `Rd` is the Determined coupling matrix; `twiss` is either
# `nothing` (no tunes were given, or the route could not extract them, in
# which case `twiss_reason` says why) or the pair ((beta, alpha, gamma, mu), ...);
# `blocks` likewise; `M` is the map for (T5) or `nothing`.
function _assemble_edwards_teng_form(form::Integer, route::Symbol, Rd::Determined{Matrix{Float64}},
                                     weight::Real, twiss, blocks, M, consistency::Real;
                                     twiss_reason::Symbol=:not_requested,
                                     twiss_detail::AbstractString="no tunes were passed to the $(route) route")
    if !is_determined(Rd)
        return _edwards_teng_form_tail_unavailable(form, route, Rd, Determined{Float64}(Rd.reason, Rd.detail),
            weight, false, Determined{Float64}(Rd.reason, Rd.detail), Rd.reason, Rd.detail, consistency)
    end
    R = determined_value(Rd); d = det(R)
    admissible = (1 + d > 0) && (weight > 0)
    if !admissible
        detail = "form $(form): 1 + det R = $(1 + d), area weight = $(weight); both must be positive"
        return _edwards_teng_form_tail_unavailable(form, route, Rd, Determined(d), weight, false,
            Determined{Float64}(:form_inadmissible, detail), :form_inadmissible, detail, consistency)
    end
    lambda = Determined(1 / sqrt(1 + d))
    twiss === nothing && return _edwards_teng_form_tail_unavailable(form, route, Rd, Determined(d),
        weight, true, lambda, twiss_reason, twiss_detail, consistency)
    t1, t2 = twiss
    phases = _edwards_teng_phases(form, R, t1.beta, t1.alpha, t2.beta, t2.alpha)
    rec = M === nothing ?
        Determined{_ET_RESIDUAL_T}(:not_requested, "no map was passed for the (T5) residual") :
        Determined(_edwards_teng_reconstruction(form, R, blocks, M))
    return EdwardsTengForm(form, route, Rd, Determined(d), Float64(weight), true, lambda,
        Determined((t1, t2)), Determined((Matrix{Float64}(blocks[1]), Matrix{Float64}(blocks[2]))),
        phases, rec, Float64(consistency))
end

# The Determined coupling matrix of one form from its block ratio (B10),
# or unavailable when the block the ratio inverts is singular at the floor.
function _block_ratio_R(Uy::AbstractMatrix, Ux::AbstractMatrix, weight::Real, weight_rtol::Real, form::Integer)
    if abs(weight) <= weight_rtol * norm(Ux)^2
        return Determined{Matrix{Float64}}(:form_inadmissible,
            "form $(form): the (B10) block has determinant $(weight), at or below the floor " *
            "$(weight_rtol) ||U_x||^2 = $(weight_rtol * norm(Ux)^2); no finite R exists for this form")
    end
    # R = -U_y U_x^{-1} by a linear solve (right division; design step 11: B10 by linear solves).
    return Determined(Matrix{Float64}(-(Uy / Ux)))
end

"""
    _edwards_teng_from_normalizer(U4, tunes; M4=nothing, weight_rtol=256 eps()) -> EdwardsTengPair

Both Edwards-Teng forms from a real symplectic normalizer `U_4` in the (E6)
convention with its tunes `(mu_1, mu_2)` (theory 7.4 and 7.2/7.3). Per form the
coupling matrix is the block ratio (B10) by a linear solve, `R = -U_y1 U_x1^{-1}`
(form 1) or `R = -U_y2 U_x2^{-1}` (form 2); its area weight is the determinant
of the inverted block, `kappa_1x = 1 - u` or `kappa_2x = u` (M3), and the form
is admissible when `1 + det R > 0` and that weight is positive. The unit-area
Twiss functions are (B5)/(B9) on the projected (M1) functions of `U_4`; the
normal blocks are (T16); the (T5) residual is evaluated against `M4` when given,
else against the reconstruction `U_4 diag(R(mu_1), R(mu_2)) U_4^{-1}` (E8). The
second expression of each (B10) row is evaluated too and its difference from
`adj(R)` reported as `consistency_residual`. A block whose determinant is within
`weight_rtol ||U_x||^2` of zero (the exactly uncoupled limit for form 2 under the
`u = 0` labelling) leaves that form with no finite `R` (`:form_inadmissible`).
The default floor `256 eps` is provisional: on the det R = 0 construction of
benchmark 12.2-2 the eigen frame's zero weight comes out at 15 eps, so 64 eps
would reject it by a factor 4 to 8 only, below the design's ten-fold rule
(stage 2 record).
"""
function _edwards_teng_from_normalizer(U::AbstractMatrix{<:Real}, tunes;
                                       M4=nothing, weight_rtol::Real=256 * eps())
    U4 = _check_normalizer4(U, "the normalizer U4")
    mu = _check_tunes(tunes)
    weight_rtol >= 0 || throw(ArgumentError("weight_rtol must be non-negative, got $(weight_rtol)"))
    M = M4 === nothing ?
        U4 * _blockdiag22(_rotation2(mu[1]), _rotation2(mu[2])) * _symplectic_inverse(U4) :
        _check_normalizer4(M4, "the map M4")
    mr = _mais_ripken(U4)
    Ux = (_block22(U4, 1, 1), _block22(U4, 1, 2)); Uy = (_block22(U4, 2, 1), _block22(U4, 2, 2))
    forms = ntuple(2) do form
        j = form                     # the mode carried by (x, px) in this form
        k = 3 - form                 # the other mode
        weight = mr.kappa[j, 1]      # det U_xj: 1 - u for form 1, u for form 2 (M3)
        Rd = _block_ratio_R(Uy[j], Ux[j], weight, weight_rtol, form)
        consistency = 0.0
        twiss = nothing; blocks = nothing
        if is_determined(Rd)
            R = determined_value(Rd)
            # The row's second expression, adj(R) = U_xk U_yk^{-1}; det U_yk = kappa_ky = weight (M3).
            consistency = abs(det(Uy[k])) > weight_rtol * norm(Uy[k])^2 ?
                norm(_adjugate2(R) - Ux[k] / Uy[k]) : Inf
            if 1 + det(R) > 0 && weight > 0
                # (B5) for form 1 (mode 1 from x, mode 2 from y), (B9) for form 2 (mode 1 from y, mode 2 from x).
                b1 = mr.beta[1, form] / weight;  a1 = mr.alpha[1, form] / weight
                b2 = mr.beta[2, k] / weight; a2 = mr.alpha[2, k] / weight
                twiss = ((beta=b1, alpha=a1, gamma=(1 + a1^2) / b1, mu=mu[1]),
                         (beta=b2, alpha=a2, gamma=(1 + a2^2) / b2, mu=mu[2]))
                blocks = (_twiss_block(b1, a1, mu[1]), _twiss_block(b2, a2, mu[2]))
            end
        end
        _assemble_edwards_teng_form(form, :normalizer, Rd, weight, twiss, blocks, M, consistency)
    end
    return EdwardsTengPair(forms[1], forms[2], Determined(mr.u), :normalizer)
end

"""
    _edwards_teng_normalizer(form, R, beta1, alpha1, beta2, alpha2) -> Matrix{Float64}

The real normalizer of an Edwards-Teng parameterization, `U_4 = V_form(R) B`
with `B = diag(B_1, B_2)` the Courant-Snyder normalizers (T17): (B2) for
form 1, (B6) for form 2. The (M7) position convention holds for form 1; form 2
generally needs the rephasing that [`_mais_ripken`](@ref) applies (theory 4.4,
7.3). Loud on bad input: `1 + det R <= 0` or a non-positive beta is an
`ArgumentError`. Mode `j` occupies columns `2j-1:2j`, as in (E6).
"""
function _edwards_teng_normalizer(form::Integer, R::AbstractMatrix{<:Real},
                                  beta1::Real, alpha1::Real, beta2::Real, alpha2::Real)
    V = _edwards_teng_V(form, R)
    return V * _blockdiag22(_courant_snyder_B(beta1, alpha1), _courant_snyder_B(beta2, alpha2))
end

"""
    _map_route_label_sign(D, mode_traces) -> Float64

The label sign `s` of the map route: `sign(D)` (mode 1 = the larger x-area,
the (T9) branch; `+1` at `D = 0`, a convention) when `mode_traces` is
`nothing`, else `sign(tr Mbar_1 - tr Mbar_2)` of the caller's pair, which must
be two distinct numbers (`ArgumentError` otherwise).
"""
function _map_route_label_sign(D::Real, mode_traces)
    mode_traces === nothing && return D == 0 ? 1.0 : sign(Float64(D))
    length(mode_traces) == 2 || throw(ArgumentError("mode_traces must be a pair, got $(mode_traces)"))
    s = sign(Float64(mode_traces[1]) - Float64(mode_traces[2]))
    s == 0 && throw(ArgumentError("mode_traces must be distinct to fix the labels, got $(mode_traces)"))
    return s
end

"""
    _edwards_teng_from_map(M4; min_trace_gap, mode_traces=nothing, weight_rtol=256 eps()) -> EdwardsTengPair

Both Edwards-Teng forms from the physical 4x4 map alone (theory 4.2 and 4.4).
With the blocks of (T1), `A = adj(M_xy) + M_yx`, `D = tr M_xx - tr M_yy`, the
discriminant `Delta = D^2 + 4 det A` (T7) is the squared separation of the mode
traces. Guards, in order, each leaving both forms with no `R`: `Delta < 0`
gives `:unstable_spectrum` (complex mode traces); `sqrt(Delta) <= min_trace_gap`
gives `:singular_coefficient` ((T8)/(T9) are stated for distinct traces and
divide by the separation; this is the conditioning guard the design asks for,
and `min_trace_gap` is a required caller choice); a mode trace (T13) with
`|tau| >= 2` gives `:unstable_spectrum` (T14). The labelling is by the sign
`s` of `tr Mbar_1 - tr Mbar_2`: from `mode_traces = (tr Mbar_1, tr Mbar_2)`
when the caller knows the labels (e.g. `2 cos mu_j` of an eigenmode frame),
else the (T9) initialization branch `s = sign(D)`, which puts the mode with the
larger x-area first (`det R_1` in `(-1, 1]`), with `s = +1` (mode 1 has the
larger trace) at `D = 0` where (T9) has no sign; the theory: this is an
initialization branch, never a continuation rule. Then form 1 has
`R_1 = -2A / (D + s sqrt(Delta))` ((T8), equal to (T9) on its branch) and form 2
`R_2 = -2A / (D - s sqrt(Delta))`, the other sign of (T8) under the SAME labels
(`R_2 = -R_1 / det R_1`, `det R_1 det R_2 = 1`); a vanishing denominator
(relative to `|D| + sqrt(Delta)` at `weight_rtol`) is a form with zero area
weight and no finite `R`. Per admissible form: `lambda` by (T3), the normal
blocks by (T11), their Twiss and tunes by (T15)/(T16), the (T5) residual, the
(B4)/(B8) phases. The area weight of a form is `1 / (1 + det R)` of its own `R`
((B3)/(B7): `1 - u` for form 1, `u` for form 2).
"""
function _edwards_teng_from_map(M::AbstractMatrix{<:Real}; min_trace_gap::Real,
                                mode_traces=nothing, weight_rtol::Real=256 * eps())
    M4 = _check_normalizer4(M, "the map M4")
    min_trace_gap > 0 || throw(ArgumentError("min_trace_gap must be positive, got $(min_trace_gap)"))
    weight_rtol >= 0 || throw(ArgumentError("weight_rtol must be non-negative, got $(weight_rtol)"))
    Mxx, Mxy, Myx, Myy = _block22(M4, 1, 1), _block22(M4, 1, 2), _block22(M4, 2, 1), _block22(M4, 2, 2)
    A = _adjugate2(Mxy) + Myx
    D = tr(Mxx) - tr(Myy)
    Delta = D^2 + 4 * det(A)
    unavailable(reason, detail) = begin
        Rd = Determined{Matrix{Float64}}(reason, detail)
        f = ntuple(form -> _assemble_edwards_teng_form(form, :map, Rd, 0.0, nothing, nothing, nothing, 0.0), 2)
        EdwardsTengPair(f[1], f[2], Determined{Float64}(reason, detail), :map)
    end
    Delta < 0 && return unavailable(:unstable_spectrum,
        "the trace discriminant (T7) is negative, Delta = $(Delta): the mode traces are complex")
    sq = sqrt(Delta)
    sq <= min_trace_gap && return unavailable(:singular_coefficient,
        "the mode traces coincide within the guard: sqrt(Delta) = $(sq) <= min_trace_gap = $(min_trace_gap)")
    tau = ((tr(Mxx) + tr(Myy) + sq) / 2, (tr(Mxx) + tr(Myy) - sq) / 2)       # (T13)
    maximum(abs, tau) < 2 || return unavailable(:unstable_spectrum,
        "a mode trace (T13) is outside (-2, 2): tau = $(tau) (T14)")
    # One assignment site for `s`: it is captured by the closure below, and a
    # name assigned in two branches and captured becomes a shared Core.Box
    # (the suite's "No method grows a Core.Box" tripwire caught the two-site form).
    s = _map_route_label_sign(D, mode_traces)
    forms = ntuple(2) do form
        den = form == 1 ? D + s * sq : D - s * sq
        if abs(den) <= weight_rtol * (abs(D) + sq)
            Rd = Determined{Matrix{Float64}}(:form_inadmissible,
                "form $(form): the (T8) denominator $(den) vanishes relative to |D| + sqrt(Delta) = $(abs(D) + sq); " *
                "this form has zero area weight and no finite R")
            return _assemble_edwards_teng_form(form, :map, Rd, 0.0, nothing, nothing, nothing, 0.0)
        end
        R = -2 .* A ./ den
        d = det(R)
        weight = 1 / (1 + d)                                                   # (B3)/(B7) with this form's R
        Rd = Determined(R)
        (1 + d > 0 && weight > 0) || return _assemble_edwards_teng_form(form, :map, Rd, weight, nothing, nothing, M4, 0.0)
        blocks = form == 1 ? (Mxx - Mxy * R, Myy + Myx * _adjugate2(R)) :
                             (Myy + Myx * _adjugate2(R), Mxx - Mxy * R)         # (T11)
        tw = map(_twiss_from_block, blocks)
        for t in tw
            is_determined(t) || return _assemble_edwards_teng_form(form, :map, Rd, weight, nothing, nothing, M4, 0.0;
                twiss_reason=t.reason, twiss_detail=t.detail)
        end
        _assemble_edwards_teng_form(form, :map, Rd, weight, map(determined_value, tw), blocks, M4, 0.0)
    end
    u = is_determined(forms[1].det_R) ? 1 - forms[1].area_weight : forms[2].area_weight
    return EdwardsTengPair(forms[1], forms[2], Determined(u), :map)
end

"""
    _mode_projector_covariance(u) -> (P, G)

The invariant-plane projector `P_j = -Im(u_j u_j') S_4` and the normalized modal
covariance `G_j = Re(u_j u_j')` of theory Section 3.4 ((E13): `u u' = G + i P S_4`)
for one oriented, (E3)-normalized eigenvector.
"""
function _mode_projector_covariance(u::AbstractVector)
    v = _check_mode_vector(u, "u")
    W = v * v'
    return (-imag.(W) * _symplectic_form(4), real.(W))
end

"""
    _edwards_teng_direct(P1, G1, P2, G2; tunes=nothing, M4=nothing, weight_rtol=256 eps()) -> EdwardsTengPair
    _edwards_teng_direct(u1, u2; kwargs...) -> EdwardsTengPair

The direct extraction (B11) from the per-mode projectors and covariances, with
no eigenvector phase chosen. With physical-pair block subscripts, form 1 has
`lambda^2 = 1 - u = kappa_1x`, `R = -(P_1)_{y,x} / (1 - u)`,
`Q_1 = (G_1)_{x,x} / (1 - u)`, `Q_2 = (G_2)_{y,y} / (1 - u)`; form 2 has
`lambda^2 = u = kappa_2x`, `R = -(P_2)_{y,x} / u`, `Q_1 = (G_1)_{y,y} / u`,
`Q_2 = (G_2)_{x,x} / u`, where `Q_j = [beta_j -alpha_j; -alpha_j gamma_j]` is
the unit-area Twiss matrix. The area weight of each form is read off its own
projector, `kappa_1x = (P_1 S_4)_{x,px}` and `kappa_2x = (P_2 S_4)_{x,px}` (3.4),
and a weight within `weight_rtol` of zero leaves the form with no finite `R`.
With `tunes = (mu_1, mu_2)` the (T16) blocks, the (B4)/(B8) phases and the
(T5) residual (against `M4`, or against the reconstruction
`sum_j cos(mu_j) P_j + sin(mu_j) G_j S_4` of (E14) when `M4` is not given) are
reported; without tunes they are `:not_requested`. The vector method forms
`P_j, G_j` by [`_mode_projector_covariance`](@ref).
"""
function _edwards_teng_direct(P1::AbstractMatrix{<:Real}, G1::AbstractMatrix{<:Real},
                              P2::AbstractMatrix{<:Real}, G2::AbstractMatrix{<:Real};
                              tunes=nothing, M4=nothing, weight_rtol::Real=256 * eps())
    P = (_check_normalizer4(P1, "P1"), _check_normalizer4(P2, "P2"))
    G = (_check_normalizer4(G1, "G1"), _check_normalizer4(G2, "G2"))
    weight_rtol >= 0 || throw(ArgumentError("weight_rtol must be non-negative, got $(weight_rtol)"))
    S4 = _symplectic_form(4)
    mu = tunes === nothing ? nothing : _check_tunes(tunes)
    M = M4 !== nothing ? _check_normalizer4(M4, "the map M4") :
        (mu === nothing ? nothing :
         cos(mu[1]) * P[1] + sin(mu[1]) * G[1] * S4 + cos(mu[2]) * P[2] + sin(mu[2]) * G[2] * S4)   # (E14)
    kappa_x = ((P[1] * S4)[1, 2], (P[2] * S4)[1, 2])          # kappa_1x = 1 - u, kappa_2x = u
    forms = ntuple(2) do form
        weight = kappa_x[form]
        if abs(weight) <= weight_rtol
            Rd = Determined{Matrix{Float64}}(:form_inadmissible,
                "form $(form): the area weight kappa_$(form)x = $(weight) is within $(weight_rtol) of zero; " *
                "no finite R exists for this form")
            return _assemble_edwards_teng_form(form, :direct, Rd, weight, nothing, nothing, M, 0.0)
        end
        Rd = Determined(Matrix{Float64}(-_block22(P[form], 2, 1) ./ weight))
        d = det(determined_value(Rd))
        (1 + d > 0 && weight > 0) || return _assemble_edwards_teng_form(form, :direct, Rd, weight, nothing, nothing, M, 0.0)
        # Q_1 from G_1 on the plane carrying mode 1 in this form (x for form 1, y for form 2), Q_2 on the other plane.
        Q1 = _block22(G[1], form, form) ./ weight
        Q2 = _block22(G[2], 3 - form, 3 - form) ./ weight
        mu === nothing && return _assemble_edwards_teng_form(form, :direct, Rd, weight, nothing, nothing, M, 0.0)
        twiss = ((beta=Q1[1, 1], alpha=-Q1[1, 2], gamma=Q1[2, 2], mu=mu[1]),
                 (beta=Q2[1, 1], alpha=-Q2[1, 2], gamma=Q2[2, 2], mu=mu[2]))
        blocks = (_twiss_block(twiss[1].beta, twiss[1].alpha, mu[1]), _twiss_block(twiss[2].beta, twiss[2].alpha, mu[2]))
        _assemble_edwards_teng_form(form, :direct, Rd, weight, twiss, blocks, M, 0.0)
    end
    return EdwardsTengPair(forms[1], forms[2], Determined((P[1] * S4)[3, 4]), :direct)
end

function _edwards_teng_direct(u1::AbstractVector, u2::AbstractVector; kwargs...)
    P1, G1 = _mode_projector_covariance(u1)
    P2, G2 = _mode_projector_covariance(u2)
    return _edwards_teng_direct(P1, G1, P2, G2; kwargs...)
end

# ---------------------------------------------------------------------------
# Thin methods on the Part A frame (stage 2 integration). Each unpacks a
# `NormalModeFrame4D` of eigenmodes_4d.jl into the plain arguments above and
# adds no arithmetic: the frame's oriented (E3) vectors, its (E6) normalizer,
# its tunes, its projectors and covariances, and its (already scaled) matrix.
# The frame's mode labels are kept as they are (mode 1 = larger kappa_jx);
# form 2 is the theory's form 2 under those labels, not form 1 relabelled.

"""
    _mais_ripken(frame::NormalModeFrame4D; projection_rtol=64 eps()) -> MaisRipkenSet

The complete Mais-Ripken set of the frame's two oriented vectors
(`frame.vectors`), by the vector method of [`_mais_ripken`](@ref).
"""
_mais_ripken(frame::NormalModeFrame4D; projection_rtol::Real=64 * eps()) =
    _mais_ripken(frame.vectors[1], frame.vectors[2]; projection_rtol=projection_rtol)

"""
    _matched_covariance_4d(frame::NormalModeFrame4D, emittances) -> Matrix{Float64}

(M9) for the frame's vectors, `sum_j eps_j Re(u_j u_j')`, by the vector method
of [`_matched_covariance_4d`](@ref).
"""
_matched_covariance_4d(frame::NormalModeFrame4D, emittances) =
    _matched_covariance_4d(frame.vectors[1], frame.vectors[2], emittances)

"""
    _edwards_teng_from_normalizer(frame::NormalModeFrame4D; M4=frame.matrix, weight_rtol=256 eps()) -> EdwardsTengPair

The (B10) route on the frame's normalizer and tunes; the (T5) residual is
taken against the frame's own matrix unless `M4` is given.
"""
_edwards_teng_from_normalizer(frame::NormalModeFrame4D; M4=frame.matrix, weight_rtol::Real=256 * eps()) =
    _edwards_teng_from_normalizer(frame.normalizer, frame.tunes; M4=M4, weight_rtol=weight_rtol)

"""
    _edwards_teng_from_map(frame::NormalModeFrame4D; min_trace_gap, weight_rtol=256 eps()) -> EdwardsTengPair

The map route (4.2) on the frame's matrix, labelled by the frame's modes
through `mode_traces = 2 cos.(frame.tunes)` so both forms carry the same
labels as the frame-based routes. `min_trace_gap` is the caller's guard, as
for the plain method. The frame methods take no `kwargs...`: a caller
`mode_traces` (here) or `tunes` (the direct method) would silently override
the frame's labels through a keyword splat, so such a keyword is a
`MethodError` (unsupported keyword) instead.
"""
_edwards_teng_from_map(frame::NormalModeFrame4D; min_trace_gap::Real, weight_rtol::Real=256 * eps()) =
    _edwards_teng_from_map(frame.matrix; min_trace_gap=min_trace_gap,
                           mode_traces=(2 * cos(frame.tunes[1]), 2 * cos(frame.tunes[2])), weight_rtol=weight_rtol)

"""
    _edwards_teng_direct(frame::NormalModeFrame4D; M4=frame.matrix, weight_rtol=256 eps()) -> EdwardsTengPair

The direct extraction (B11) from the frame's own projectors and covariances
(`frame.projectors`, `frame.covariances`, not recomputed from the vectors),
with the frame's tunes; the (T5) residual is against the frame's matrix
unless `M4` is given.
"""
_edwards_teng_direct(frame::NormalModeFrame4D; M4=frame.matrix, weight_rtol::Real=256 * eps()) =
    _edwards_teng_direct(frame.projectors[1], frame.covariances[1], frame.projectors[2], frame.covariances[2];
                         tunes=frame.tunes, M4=M4, weight_rtol=weight_rtol)
