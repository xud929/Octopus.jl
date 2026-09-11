# Symplectic linear algebra kernel for the optics analyses. Pure matrix
# arithmetic in the conventions of docs/theory/twiss_dispersion.md Section 2:
# coordinates (x, px, y, py, z, pz), S_2 = [0 1; -1 0], S_d = diag(S_2, ...),
# {x, px} = +1. Nothing here knows about elements, tracking, or the analysis
# object; the file has no accelerator semantics. It lives under src/analysis/
# rather than src/math/ because the design note (docs/design/
# twiss_dispersion_analysis.md, "The decision") places the analysis's six
# pure-math files with the analysis; src/math/ was considered and the design
# was followed. Stage 1 of the campaign (design "Staging", item 1).
#
# The one call out of this file, `_linear6d_symplectic_error` inside
# `_symplectic_defect`, late-binds to src/elements/linear6d.jl, which is
# included after this file: Julia resolves the method at call time, the same
# arrangement src/tasks/RunArtifact.jl uses for the observer-registry helper.
# It is a deliberate reuse of the one magnitude-aware symplectic validator
# the repository has (AGENTS.md: derive, do not hand-copy) rather than an
# element dependency: the function is pure tuple arithmetic.

"""
    _symplectic_form(d) -> Matrix{Float64}

The canonical symplectic form `S_d = diag(S_2, ..., S_2)` with
`S_2 = [0 1; -1 0]` (theory (C1)-(C2)) for `d` in `(2, 4, 6)`; any other
dimension is an `ArgumentError`. `S_d' == -S_d` and `S_d^2 == -I`.
"""
function _symplectic_form(d::Integer)
    d in (2, 4, 6) || throw(ArgumentError(
        "the symplectic form is built for dimension 2, 4, or 6, got $(d)"))
    S = zeros(Float64, d, d)
    for c in 1:2:d
        S[c, c + 1] = 1.0
        S[c + 1, c] = -1.0
    end
    return S
end

"""
    _symplectic_inverse(M) -> Matrix

The inverse `-S M' S` of a symplectic matrix `M` (from `M' S M = S`), with no
linear solve; for a non-symplectic `M` it is not the inverse, and
[`_symplectic_defect`](@ref) says how far from symplectic `M` is. Square, of
dimension 2, 4, or 6.
"""
function _symplectic_inverse(M::AbstractMatrix)
    d = size(M, 1)
    size(M, 2) == d || throw(ArgumentError("symplectic inverse needs a square matrix, got $(size(M))"))
    S = _symplectic_form(d)
    return -S * transpose(M) * S
end

"""
    _adjugate2(K) -> Matrix

The 2x2 symplectic adjugate `adj(K) = -S_2 K' S_2 = [K22 -K12; -K21 K11]`
(theory (C4)), with `K adj(K) = adj(K) K = det(K) I`, `adj(KL) = adj(L) adj(K)`,
and `K + adj(K) = tr(K) I` (theory (C5)).
"""
function _adjugate2(K::AbstractMatrix)
    size(K) == (2, 2) || throw(ArgumentError("the symplectic adjugate is defined for 2x2 matrices, got $(size(K))"))
    return [K[2, 2] -K[1, 2]; -K[2, 1] K[1, 1]]
end

"""
    _rotation2(mu) -> Matrix{Float64}

The rotation block `R(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]` of theory
Section 3.3: with the oriented eigenvector `M u = e^{-i mu} u` and the real
pair `U = [Re u, -Im u]` of (E6), `M U = U R(mu)`.
"""
_rotation2(mu::Real) = [cos(mu) sin(mu); -sin(mu) cos(mu)]

"""
    _embed_4to6(M4) -> Matrix{Float64}

`diag(M4, I_2)`: a transverse 4x4 map embedded as a 6x6 map with an identity
longitudinal block. The embedding is symplectic with respect to `S_6` exactly
when `M4` is with respect to `S_4`, so a 4x4 input can be measured by the 6x6
row-scaled validator without a second copy of it.
"""
function _embed_4to6(M4::AbstractMatrix{<:Real})
    size(M4) == (4, 4) || throw(ArgumentError("_embed_4to6 takes a 4x4 matrix, got $(size(M4))"))
    M6 = zeros(Float64, 6, 6)
    M6[1:4, 1:4] .= M4
    M6[5, 5] = 1.0
    M6[6, 6] = 1.0
    return M6
end

"""
    _symplectic_defect(M) -> (frobenius, row_ratio, row_residual, row_tolerance)

Two measures of `M' S M - S` for a real 4x4 or 6x6 matrix (theory (C3);
design "Pipeline" step 1):

  * `frobenius`: `||M' S M - S||_F / max(1, ||M||_F^2)`, evaluated with the
    form of `M`'s own dimension; scale-free above unit norm.
  * `row_ratio`: the magnitude-aware worst-row ratio of the `Linear6D`
    validator (`_linear6d_symplectic_error`, src/elements/linear6d.jl), which
    accepts a matrix exactly when `row_ratio <= 1`; `row_residual` and
    `row_tolerance` are that row's residual and its `64 eps` scaled tolerance.
    A 4x4 input is embedded as `diag(M, I_2)` by [`_embed_4to6`](@ref) first,
    so both dimensions share the validator instead of a copy of it.

Non-finite entries and any other size are an `ArgumentError`. The function
measures; it never symplectifies (theory 11.1 step 3).
"""
function _symplectic_defect(M::AbstractMatrix{<:Real})
    d = size(M, 1)
    (size(M, 2) == d && d in (4, 6)) || throw(ArgumentError(
        "the symplectic defect is defined for 4x4 or 6x6 matrices, got $(size(M))"))
    all(isfinite, M) || throw(ArgumentError("the symplectic defect needs finite entries"))
    Mf = Matrix{Float64}(M)
    S = _symplectic_form(d)
    frob = norm(transpose(Mf) * S * Mf - S) / max(1.0, norm(Mf)^2)
    M6 = d == 6 ? Mf : _embed_4to6(Mf)
    err = _linear6d_symplectic_error(_matrix66_tuple(M6, Float64))
    return (frobenius=frob, row_ratio=err.ratio, row_residual=err.residual,
            row_tolerance=err.tolerance)
end

"""
    ReciprocalScaling

The record of a reciprocal canonical scaling `C = diag(a_1, 1/a_1, ..., a_n,
1/a_n)` of a `2n`-dimensional map (design "Input boundary" item 5; theory
11.1 step 2). `C' S C = S` holds exactly, so the scaled map `C M C^{-1}` is
symplectic with respect to the UNCHANGED form. Fields: `mode` (`:auto`,
`:none`, or `:explicit`, what the caller asked for), `factors` (the `a_i`,
length `n`), `dimension` (`2n`). Build it with [`_reciprocal_scaling`](@ref);
apply it with [`_scale_map`](@ref) and undo it with the `_unscale_*` helpers,
which implement the design's back-transformation table row by row.
"""
struct ReciprocalScaling
    mode::Symbol
    factors::Vector{Float64}
    dimension::Int
    function ReciprocalScaling(mode::Symbol, factors::AbstractVector{<:Real}, dimension::Integer)
        mode in (:auto, :none, :explicit) || throw(ArgumentError(
            "ReciprocalScaling mode must be :auto, :none, or :explicit, got :$(mode)"))
        dimension in (4, 6) || throw(ArgumentError(
            "ReciprocalScaling is defined for dimension 4 or 6, got $(dimension)"))
        length(factors) == dimension ÷ 2 || throw(ArgumentError(
            "ReciprocalScaling needs $(dimension ÷ 2) factors for dimension $(dimension), got $(length(factors))"))
        all(x -> isfinite(x) && x > 0, factors) || throw(ArgumentError(
            "ReciprocalScaling factors must be positive and finite, got $(collect(factors))"))
        return new(mode, Vector{Float64}(factors), Int(dimension))
    end
end

"""
    _auto_scaling_factors(M) -> Vector{Float64}

The default factors `a_i = sqrt(||M[2i, :]|| / ||M[2i-1, :]||)`: the factors
that WOULD balance the Euclidean norms of the position and momentum rows of
each canonical pair if only the rows were scaled. The similarity `C M C^-1`
also scales the columns, and that effect is not iterated (a one-pass
heuristic), so after the pass the two row norms of a pair are closer, not
equal (measured 2026-09-11 on the FODO one-turn matrix: pair 1 rows
(3.82, 1.72) -> (1.72, 1.83), pair 2 rows (2.47, 0.41) -> (1.35, 1.97)). A
factor is `1` when either row vanishes. Policy, not physics (design "Input
boundary" item 5): any positive factors give a valid reciprocal scaling, and
the back-transformation table makes the physical outputs independent of the
choice.
"""
function _auto_scaling_factors(M::AbstractMatrix{<:Real})
    d = size(M, 1)
    a = ones(Float64, d ÷ 2)
    for i in 1:(d ÷ 2)
        q = norm(view(M, 2i - 1, :))
        p = norm(view(M, 2i, :))
        if q > 0 && p > 0 && isfinite(q) && isfinite(p)
            a[i] = sqrt(p / q)
        end
    end
    return a
end

"""
    _reciprocal_scaling(M, mode) -> ReciprocalScaling

The scaling record for a real 4x4 or 6x6 map `M` under `mode`: `:auto`
(factors from [`_auto_scaling_factors`](@ref)), `:none` (all factors one), or
a `Tuple` or `AbstractVector` of explicit positive factors of length `d/2`.
An unknown symbol, a tuple of the wrong length, a non-positive or non-finite
factor, and any other matrix size are `ArgumentError`s (loud beats silent).
"""
function _reciprocal_scaling(M::AbstractMatrix{<:Real}, mode)
    d = size(M, 1)
    (size(M, 2) == d && d in (4, 6)) || throw(ArgumentError(
        "reciprocal scaling is defined for 4x4 or 6x6 matrices, got $(size(M))"))
    if mode === :auto
        return ReciprocalScaling(:auto, _auto_scaling_factors(M), d)
    elseif mode === :none
        return ReciprocalScaling(:none, ones(d ÷ 2), d)
    elseif mode isa Symbol
        throw(ArgumentError("scaling must be :auto, :none, or a tuple of $(d ÷ 2) positive factors, got :$(mode)"))
    elseif mode isa Tuple || mode isa AbstractVector
        length(mode) == d ÷ 2 || throw(ArgumentError(
            "explicit scaling needs $(d ÷ 2) factors for a $(d)x$(d) map, got $(length(mode))"))
        all(x -> x isa Real, mode) || throw(ArgumentError(
            "explicit scaling factors must be real numbers, got $(mode)"))
        return ReciprocalScaling(:explicit, collect(Float64, mode), d)
    end
    throw(ArgumentError("scaling must be :auto, :none, or a tuple of $(d ÷ 2) positive factors, got $(repr(mode))"))
end

"""
    _scaling_matrix(rec::ReciprocalScaling) -> Diagonal{Float64}

`C = diag(a_1, 1/a_1, a_2, 1/a_2, ...)` of the record.
"""
_scaling_matrix(rec::ReciprocalScaling) =
    Diagonal([isodd(k) ? rec.factors[(k + 1) ÷ 2] : 1 / rec.factors[k ÷ 2] for k in 1:rec.dimension])

"""
    _scaling_inverse(rec::ReciprocalScaling) -> Diagonal{Float64}

`C^{-1} = diag(1/a_1, a_1, 1/a_2, a_2, ...)`, formed from the factors directly
(not by inverting the reciprocals) so that `a_i` re-enters bit for bit.
"""
_scaling_inverse(rec::ReciprocalScaling) =
    Diagonal([isodd(k) ? 1 / rec.factors[(k + 1) ÷ 2] : rec.factors[k ÷ 2] for k in 1:rec.dimension])

"""
    _scale_map(rec::ReciprocalScaling, M) -> Matrix{Float64}

The scaled map `C M C^{-1}` in the coordinates `X~ = C X`. Every residual and
tolerance of the analysis is evaluated on this matrix (theory 11.2).
"""
function _scale_map(rec::ReciprocalScaling, M::AbstractMatrix{<:Real})
    size(M) == (rec.dimension, rec.dimension) || throw(ArgumentError(
        "_scale_map: the record is for $(rec.dimension)x$(rec.dimension), got $(size(M))"))
    return _scaling_matrix(rec) * Matrix{Float64}(M) * _scaling_inverse(rec)
end

# Back-transformation table of the design note ("Input boundary" item 5),
# scaled quantity in, physical quantity out. `C_r` is the transverse 4x4
# block of C, `C_l = diag(a_3, 1/a_3)` the longitudinal 2x2 block. Residuals
# are reported in scaled coordinates and have no row here on purpose.

function _transverse_block(rec::ReciprocalScaling)
    rec.dimension == 6 || throw(ArgumentError(
        "the transverse/longitudinal split needs a 6x6 scaling, got dimension $(rec.dimension)"))
    C = _scaling_matrix(rec)
    Cinv = _scaling_inverse(rec)
    return (Cr=Diagonal(C.diag[1:4]), Cr_inv=Diagonal(Cinv.diag[1:4]),
            Cl=Diagonal(C.diag[5:6]), Cl_inv=Diagonal(Cinv.diag[5:6]), a3=rec.factors[3])
end

"""
    _unscale_normalizer(rec, U~) -> Matrix

Table row `U_6 = C^{-1} U~_6`: a normalizer (or any column set of vectors in
scaled coordinates) back to physical coordinates. Rows must match the
dimension; any column count.
"""
function _unscale_normalizer(rec::ReciprocalScaling, U::AbstractVecOrMat)
    size(U, 1) == rec.dimension || throw(ArgumentError(
        "_unscale_normalizer: expected $(rec.dimension) rows, got $(size(U, 1))"))
    return _scaling_inverse(rec) * U
end

"""
    _unscale_covariance(rec, Sigma~) -> Matrix

Table rows `Sigma = C^{-1} Sigma~ C^{-T}` and `G_j = C^{-1} G~_j C^{-T}`: a
covariance, a mode covariance, or a group covariance back to physical
coordinates (the same rule for all three; `C` is diagonal, so `C^{-T} =
C^{-1}`).
"""
function _unscale_covariance(rec::ReciprocalScaling, Sigma::AbstractMatrix)
    size(Sigma) == (rec.dimension, rec.dimension) || throw(ArgumentError(
        "_unscale_covariance: expected $(rec.dimension)x$(rec.dimension), got $(size(Sigma))"))
    Cinv = _scaling_inverse(rec)
    return Cinv * Sigma * Cinv
end

"""
    _unscale_projector(rec, P~) -> Matrix

Table row `P_j = C^{-1} P~_j C`: a mode or group projector (a linear map on
phase space) back to physical coordinates.
"""
function _unscale_projector(rec::ReciprocalScaling, P::AbstractMatrix)
    size(P) == (rec.dimension, rec.dimension) || throw(ArgumentError(
        "_unscale_projector: expected $(rec.dimension)x$(rec.dimension), got $(size(P))"))
    return _scaling_inverse(rec) * P * _scaling_matrix(rec)
end

"""
    _unscale_graph(rec, D~) -> Matrix

Table row `D = C_r^{-1} D~ C_l`: the 4x2 longitudinal graph `r = D l` back to
physical coordinates. Needs a 6x6 scaling.
"""
function _unscale_graph(rec::ReciprocalScaling, D::AbstractMatrix)
    size(D) == (4, 2) || throw(ArgumentError("_unscale_graph: the graph is 4x2, got $(size(D))"))
    b = _transverse_block(rec)
    return b.Cr_inv * D * b.Cl
end

"""
    _unscale_crab_dispersion(rec, zeta~) -> Vector

Table row `zeta = a_3 C_r^{-1} zeta~`: the canonical crab dispersion (the
`z` column of the graph, theory (D8)) back to physical coordinates.
"""
function _unscale_crab_dispersion(rec::ReciprocalScaling, zeta::AbstractVector)
    length(zeta) == 4 || throw(ArgumentError("_unscale_crab_dispersion: zeta has 4 components, got $(length(zeta))"))
    b = _transverse_block(rec)
    return b.a3 * (b.Cr_inv * zeta)
end

"""
    _unscale_momentum_dispersion(rec, eta~) -> Vector

Table row `eta = C_r^{-1} eta~ / a_3`: the canonical momentum dispersion
(`h` times the `pz` column of the graph, theory (D8)) back to physical
coordinates.
"""
function _unscale_momentum_dispersion(rec::ReciprocalScaling, eta::AbstractVector)
    length(eta) == 4 || throw(ArgumentError("_unscale_momentum_dispersion: eta has 4 components, got $(length(eta))"))
    b = _transverse_block(rec)
    return (b.Cr_inv * eta) / b.a3
end

"""
    _unscale_longitudinal_factor(rec, h) -> h

Table row `h` unchanged: `det C_l = 1`, so the longitudinal factor
`h = det U_ls` (theory (D8), (D12)) is the same in both coordinate systems.
Exists so the table is complete in code and the scaling-invariance test pins
every row, including this one.
"""
function _unscale_longitudinal_factor(rec::ReciprocalScaling, h::Real)
    rec.dimension == 6 || throw(ArgumentError(
        "_unscale_longitudinal_factor needs a 6x6 scaling, got dimension $(rec.dimension)"))
    return h
end

"""
    _unscale_edwards_teng_R(rec, R~) -> Matrix

Table row `R = diag(a_2, 1/a_2)^{-1} R~ diag(a_1, 1/a_1)`: the Edwards-Teng
coupling block, a linear map from plane-1 to plane-2 coordinates, back to
physical coordinates.
"""
function _unscale_edwards_teng_R(rec::ReciprocalScaling, R::AbstractMatrix)
    size(R) == (2, 2) || throw(ArgumentError("_unscale_edwards_teng_R: R is 2x2, got $(size(R))"))
    a1, a2 = rec.factors[1], rec.factors[2]
    return Diagonal([1 / a2, a2]) * R * Diagonal([a1, 1 / a1])
end

"""
    _unscale_twiss(rec, plane, beta~, alpha~, gamma~) -> (beta, alpha, gamma)

Table row `beta_ja = beta~_ja / a_a^2, alpha_ja = alpha~_ja,
gamma_ja = gamma~_ja a_a^2` for the projection onto `plane` (1, 2, or 3),
because a position scales as `a_a` and its momentum as `1/a_a`.
"""
function _unscale_twiss(rec::ReciprocalScaling, plane::Integer, beta::Real, alpha::Real, gamma::Real)
    1 <= plane <= rec.dimension ÷ 2 || throw(ArgumentError(
        "_unscale_twiss: plane must be in 1:$(rec.dimension ÷ 2), got $(plane)"))
    a = rec.factors[plane]
    return (beta / a^2, alpha, gamma * a^2)
end

"""
    _invariance_residual(M, U, R) -> (normalized, raw)

The eigenmode invariance residual of theory (I1) for a matrix `M`, a basis
`U` (a matrix of columns) and its representation `R` on that basis:
`raw = ||M U - U R||_F` and `normalized = raw / max(1, ||M U||_F, ||U||_F)`.
For a single vector `u` and a scalar `rho` (`M u = rho u`), the norms are the
infinity norm (design "Pipeline": Frobenius for matrices, infinity for
vectors). Both values are returned so the normalized one is never mislabelled
as the raw one; the design accepts a route on the NORMALIZED value only.
"""
function _invariance_residual(M::AbstractMatrix, U::AbstractMatrix, R::AbstractMatrix)
    size(M, 2) == size(U, 1) || throw(ArgumentError(
        "_invariance_residual: M is $(size(M)) but U has $(size(U, 1)) rows"))
    size(R) == (size(U, 2), size(U, 2)) || throw(ArgumentError(
        "_invariance_residual: R must be $(size(U, 2))x$(size(U, 2)), got $(size(R))"))
    MU = M * U
    raw = norm(MU - U * R)
    return (normalized=raw / max(1.0, norm(MU), norm(U)), raw=raw)
end

function _invariance_residual(M::AbstractMatrix, u::AbstractVector, rho::Number)
    size(M, 2) == length(u) || throw(ArgumentError(
        "_invariance_residual: M is $(size(M)) but u has length $(length(u))"))
    Mu = M * u
    raw = norm(Mu - rho * u, Inf)
    return (normalized=raw / max(1.0, norm(Mu, Inf), norm(u, Inf)), raw=raw)
end

"""
    _graph_invariance_residual(M, D) -> (normalized, raw)

The graph form of theory (I1)/(D14) for a 6x6 map `M` and a 4x2 graph `D`:
`F = M_rr D + M_rl - D (M_lr D + M_ll)`, `raw = ||F||_F`, and
`normalized = raw / max(1, ||M_rr D||_F, ||M_rl||_F, ||D (M_lr D + M_ll)||_F)`.
A graph is accepted as invariant only on the normalized value; the raw value
is reported beside it.
"""
function _graph_invariance_residual(M::AbstractMatrix, D::AbstractMatrix)
    size(M) == (6, 6) || throw(ArgumentError("_graph_invariance_residual: M must be 6x6, got $(size(M))"))
    size(D) == (4, 2) || throw(ArgumentError("_graph_invariance_residual: D must be 4x2, got $(size(D))"))
    Mrr = M[1:4, 1:4]; Mrl = M[1:4, 5:6]; Mlr = M[5:6, 1:4]; Mll = M[5:6, 5:6]
    A = Mrr * D
    B = D * (Mlr * D + Mll)
    raw = norm(A + Mrl - B)
    return (normalized=raw / max(1.0, norm(A), norm(Mrl), norm(B)), raw=raw)
end

"""
    _perturbation_scale(M, defect; user_uncertainty=0.0, provenance_uncertainty=0.0)

The first perturbation scale of the design ("Pipeline" step 2),
`rho_M0 = max(defect * ||M||_F, d * eps * ||M||_2, user_uncertainty,
provenance_uncertainty)`, where `defect` is the Frobenius member of
[`_symplectic_defect`](@ref) of the same (scaled) matrix and `d` its
dimension. Every arm is a non-negative finite number or an `ArgumentError`.
Returns the scale and the four arms, so a report can say which one won.
"""
function _perturbation_scale(M::AbstractMatrix{<:Real}, defect::Real;
                             user_uncertainty::Real=0.0, provenance_uncertainty::Real=0.0)
    d = size(M, 1)
    size(M, 2) == d || throw(ArgumentError("_perturbation_scale needs a square matrix, got $(size(M))"))
    for (name, v) in (("defect", defect), ("user_uncertainty", user_uncertainty),
                      ("provenance_uncertainty", provenance_uncertainty))
        isfinite(v) && v >= 0 || throw(ArgumentError(
            "_perturbation_scale: $(name) must be a non-negative finite number, got $(v)"))
    end
    all(isfinite, M) || throw(ArgumentError("_perturbation_scale needs finite entries"))
    Mf = Matrix{Float64}(M)
    arms = (defect=Float64(defect) * norm(Mf),
            roundoff=d * eps(Float64) * opnorm(Mf, 2),
            user=Float64(user_uncertainty),
            provenance=Float64(provenance_uncertainty))
    return (scale=max(arms...), arms=arms)
end

"""
    _manufactured_symplectic_map(rng, d; scale=0.5, stable=false) -> (M, H)

A test fixture: the symplectic map `M = exp(S_d H)` for a random real
symmetric `H` (design "Verification plan": manufactured maps are `exp(S H)`
with symmetric `H`, seed 20260911, which the caller passes as `rng`). `S H`
is Hamiltonian, so `M` is exactly symplectic up to the roundoff of `exp`.
With `stable=true`, `H` is positive definite (`scale * A A' / d` for a
Gaussian `A`), so every eigenvalue of `M` lies on the unit circle and the
map has three (or two) distinct stable modes almost surely. Returns the map
and the generator so a test can check `H` is what the docstring says.
"""
function _manufactured_symplectic_map(rng::AbstractRNG, d::Integer; scale::Real=0.5, stable::Bool=false)
    S = _symplectic_form(d)
    A = randn(rng, d, d)
    H = stable ? Float64(scale) * (A * transpose(A)) / d : Float64(scale) * (A + transpose(A)) / 2
    return (M=exp(S * H), H=H)
end
