#=
Linearized-Vlasov theory of coherent beam-beam dipole modes: the Yokoya
factor, its flatness dependence, and the asymmetric (EIC-like) two-beam
generalization. Companion derivation: docs/theory/coherent_beam_beam_modes.md.
Simulation counterpart: validation/coherent_beam_beam_modes.jl.

Model (per transverse plane, smooth-focusing, one IP):

- Each beam: action-angle (J, phi) with x = sqrt(2J) cos(phi) in units of its
  own rms size; equilibrium f0 = exp(-J)/2pi; bare tune Q0.
- Beam-beam force reduced to 1D with the exact 2D Coulomb kick averaged over
  the other plane's Gaussians: G(u) = < u/(u^2+v^2) >_{v ~ N(0, s^2)} with
  s^2 = sigma_other(witness)^2 + sigma_other(source)^2. Flatness enters ONLY
  here. The kick potential is normalized so the small-amplitude incoherent
  tune shift is exactly xi.
- Perturbation f1 = g(J) e^{i(phi - Omega*theta)} (m=1 harmonic; the m=-1
  sideband coupling and the angle-dependent part of the equilibrium-force
  term are dropped, the standard leading-order approximation).

This yields the coupled eigenproblem derived in the theory note:

  (Omega - omega_a(J)) g_a(J) = 2 xi_a e^{-J} Int K_ab(J,J') g_b(J') dJ'

with omega_a(J) = Q_a + xi_a u_a(J) the amplitude-dependent incoherent tune and
the symmetric kernel

  K(J,J') = (1/2 pi^2) Int_0^{2pi} dphi Int_0^pi dphi'
            cos(phi) cos(phi') Vhat(x(J,phi) - x'(J',phi')).

Discretizing J on Gauss-Legendre nodes turns this into a 2N x 2N matrix
eigenproblem.

This is a CHARACTERIZATION script: it writes tables and prints diagnostics,
and only one condition stops it (the kernel-sign criterion below — a broken
kernel assembly poisons every table). The numbered self-checks print
PASS/FAIL and escalate to a warning naming which downstream rows are
unusable, but do not exit nonzero — a failing check in one regime still
leaves the other tables worth writing, and the reader of a quoted band is
expected to have read the warning (2026-08-05 audit, U19-4/9). Self-checks
built in:

1. max u <= 1, with u(0) = (1 + r)/(1 + sqrt2 r) for the symmetric case --
   NOT u(0) = 1. The reduction convolves BOTH beams' other-plane spreads into
   the kick (s_t = sqrt2 r) while xi is defined by the source's own sigma, so
   the reduction's small-amplitude detuning is smaller than xi by exactly that
   factor: 0.828 at r = 1, approaching 1 only in the flat limit. u(0) = 1 was
   the signature of the circular normalization that check 4 below removed, so
   asserting it here contradicted check 4 seventeen lines down (audit U22-2).
   The invariant with teeth is max u <= 1, asserted per row in the aspect scan;
2. the co-moving (sigma) mode must appear at exactly Q0 with the rigid
   translation eigenvector g ~ sqrt(2J) e^{-J} — this validates every
   constant in the kernel at once (translation invariance of the force);
3. the discrete pi mode must sit above the incoherent continuum
   [Q0, Q0 + xi], and Y = (Omega_pi - Q0)/xi must be xi-independent
   (leading-order theory), reproducing the literature anchors
   (~1.2 round, ~1.33 flat) and our measured strong-strong values;
4. the normalizing curvature must be the ANALYTIC on-axis gradient, not the
   reduction's own averaged curvature.  Normalizing by the latter is circular
   -- it forces u(0) = 1 whatever the kernel does -- and inflates Lambda by
   (sqrt(2) r + 1)/(r + 1).  The check below reports u(0), which after the fix
   is the ratio of the reduction's averaged curvature to the physical one and
   must therefore be BELOW 1 and aspect-dependent; a value of exactly 1 means
   the circular normalization has returned.

5. a HARMONIC interaction must give Lambda = 2 exactly.  For V(u) = u^2/2 the
   detuning vanishes (u(J) = 1) and the m=1 projection has the closed form
   K(J,J') = -sqrt(J J')/2, which puts the sigma mode at Q0 and the pi mode at
   Q0 + 2 xi.  This checks every assembly constant -- the phi/phi' quadrature
   weights, the 1/(2 pi^2) projection factor and the 2 xi e^{-J} w' weighting --
   against a closed form, independently of the Coulomb kernel and of check 4.

   The check-4 block also prints a rigid-bunch diagnostic,
   2*normalized_equilibrium(k,sqrt2)/n0phys, which is analytically exactly 1
   (2*[1/(sqrt2(sqrt2+s_t))]*(1+s_t/sqrt2) = 1) and measures 1.0000-1.0085
   across the scan.  It is a consistency check on the normalizer, not a
   physics result.

   This paragraph used to describe a DIFFERENT quantity --
   2*normalized_equilibrium(k,sqrt2)/normalized_equilibrium(k,1), divided by
   the reduction's own normalizer rather than the physical one -- and quoted it
   as running "1.21 (round) to 1.41 (extreme flat)", numbers no run has printed
   since that denominator changed.  It then drew a conclusion from them ("the
   reduction is therefore not a quantitative instrument at the few-percent
   level"), which rested on nothing this file computes, and contradicted the
   body's own printed preamble saying the rigid-bunch limit is analytically 1
   (2026-08-05_b audit, U22-9).  The reduction's accuracy claim now rests where
   it is actually measured: 1-2% against the independent particle referee at
   every aspect ratio (section 3 of docs/theory/coherent_beam_beam_modes.md).

Outputs (TSV under result/): yokoya_vs_aspect.tsv, yokoya_vs_aspect_narrow.tsv,
yokoya_box_convergence.tsv, yokoya_vs_xi_theory.tsv, eic_coherent_modes.tsv. Plots: validation/plot_coherent_mode_theory.py.

Run:  julia --project=. validation/coherent_mode_vlasov_theory.jl
(standalone: needs LinearAlgebra and FFTW (the exact referee); about 8-10 minutes warm (39 simulations) at default resolution)

Controls: OCTOPUS_VLASOV_NJ (default 72), OCTOPUS_VLASOV_NPHI (128).
=#

using LinearAlgebra

const NJ = parse(Int, get(ENV, "OCTOPUS_VLASOV_NJ", "72"))
const NPHI = parse(Int, get(ENV, "OCTOPUS_VLASOV_NPHI", "128"))
const JMAX = 14.0
const RESULT_DIR = joinpath(@__DIR__, "..", "result")

# ---------------------------------------------------------------------------
# Quadrature (Golub-Welsch from the Jacobi matrices; no dependencies).
# ---------------------------------------------------------------------------
function gauss_legendre(n)
    b = [k / sqrt(4k^2 - 1) for k in 1:(n - 1)]
    E = eigen(SymTridiagonal(zeros(n), b))
    nodes = E.values
    weights = 2 .* abs2.(E.vectors[1, :])
    return nodes, weights          # on [-1, 1], weight 1
end

# A Gauss-Hermite rule was used here to average over the source Gaussian. It is
# gone rather than merely unused: its node spacing is set by the measure, which
# is the one thing that must NOT set it here (see `gauss_avg`, audit U22-1).

# Nodes for one panel of the averaging rule below, on [-1, 1].
const GLP_N, GLP_W = gauss_legendre(10)
# Truncation of the averaging measure, in units of its own sigma. The Gaussian
# tail beyond 12 sigma is ~1e-32 and every integrand averaged here is bounded.
const GAUSS_AVG_HALFWIDTH = 12.0
# Panels per structure length, and the clamp on the resulting panel count.
const GAUSS_AVG_PER_STRUCTURE = 4.0
const GAUSS_AVG_MIN_PANELS = 64
const GAUSS_AVG_MAX_PANELS = 16384

"""
Gaussian average  < f(v) >  with v ~ N(0, s), by a panel Gauss-Legendre rule
whose panel width resolves `structure` -- the scale on which `f` varies.

A fixed-order Gauss-Hermite rule cannot be used here, and this is a measured
lesson rather than a preference (2026-08-05_b audit, U22-1). Its node spacing is
set by the *measure*: at 96 nodes the innermost sit at |v| = 0.160 s with 0.320 s
spacing. The integrands averaged below instead carry all their structure on the
scale `s_t` of the averaged plane, inside |u| <~ s_t. Once s_t <~ 0.3 s the rule
steps straight over that region, `averaged_potential`'s curvature at the origin
comes out too large, and u(J) -- the entire diagonal of the eigenproblem -- is
wrong. The damage was not subtle: Lambda at r = 0.02 came out 23.16 against a
converged 1.321, and the error tracked s_t/s exactly, so the flat-beam rows of
the aspect scan were quadrature artifacts that the note then read as a physical
limitation of the 1D reduction.

Raising the Hermite order is not the repair -- convergence is far too slow
(u(0) at r = 0.1 needs ~4000 nodes, and r = 0.05 is not converged even there).
What matters is node *spacing* relative to `s_t`, which is what this rule
controls directly. `structure` defaults to `s`, recovering an ordinary smooth
average when the integrand has no finer scale.
"""
gauss_avg(f, s) = gauss_avg(f, s, s)

function gauss_avg(f, s, structure)
    s == 0.0 && return f(0.0)
    half = GAUSS_AVG_HALFWIDTH * s
    width = 2 * half
    target = structure > 0 ? structure / GAUSS_AVG_PER_STRUCTURE : width
    npanel = clamp(ceil(Int, width / target), GAUSS_AVG_MIN_PANELS, GAUSS_AVG_MAX_PANELS)
    h = width / npanel
    acc = 0.0
    for p in 0:(npanel - 1)
        c = -half + (p + 0.5) * h
        for i in eachindex(GLP_N)
            v = c + 0.5h * GLP_N[i]
            acc += GLP_W[i] * f(v) * exp(-v * v / (2 * s * s))
        end
    end
    return acc * 0.5h / (sqrt(2pi) * s)
end

# ---------------------------------------------------------------------------
# The 1D-reduced kick kernel for one plane.
#
# `s_t`  : combined rms spread in the *other* (averaged) plane,
#          s_t^2 = sigma_t(witness)^2 + sigma_t(source)^2;
# `s_src`: source rms size in *this* plane (for the equilibrium force).
# All lengths in common (source-sigma or meter) units chosen by the caller.
# ---------------------------------------------------------------------------
# The v-average of the 2D Coulomb kick has a closed form,
#
#   G(u) = < u/(u^2+v^2) >_{v~N(0,s)} = sign(u) sqrt(pi/2)/s erfcx(|u|/(sqrt2 s)),
#
# with erfcx(z) = e^{z^2} erfc(z). G has a step at u = 0 (the sheet-beam
# limit), so naive Gaussian quadrature across it silently loses the origin
# region — every non-smooth piece below is therefore split off analytically
# and only smooth remainders are integrated numerically.

"""Scaled complementary error function erfcx(z) = e^{z^2} erfc(z), z >= 0."""
function erfcx_pos(z)
    if z < 1.0
        # e^{z^2} (1 - erf(z)) with erf from its Maclaurin series.
        s, term = z, z
        for k in 1:40
            term *= -z^2 / k
            s += term / (2k + 1)
            abs(term) < 1e-17 && break
        end
        return exp(z^2) * (1 - 2 / sqrt(pi) * s)
    end
    # Laplace continued fraction, accurate for z >= 1.
    cf = 0.0
    for k in 60:-1:1
        cf = (k / 2) / (z + cf)
    end
    return 1 / sqrt(pi) / (z + cf)
end

struct PlaneKernel
    s_t::Float64
    r_grid::Vector{Float64}   # R(a) = Int_0^a (erfcx(t/(sqrt2 s)) - 1) dt
    dr::Float64
    rmax::Float64
end

point_force(u, s_t) = u == 0.0 ? 0.0 :
    sign(u) * sqrt(pi / 2) / s_t * erfcx_pos(abs(u) / (sqrt(2.0) * s_t))

function PlaneKernel(s_t, umax)
    n = 20001
    dr = umax / (n - 1)
    R = Vector{Float64}(undef, n)
    R[1] = 0.0
    g(a) = erfcx_pos(a / (sqrt(2.0) * s_t)) - 1.0
    for i in 2:n
        a0 = (i - 2) * dr
        # Simpson step for the smooth integrand g.
        R[i] = R[i - 1] + dr / 6 * (g(a0) + 4g(a0 + dr / 2) + g(a0 + dr))
    end
    return PlaneKernel(s_t, R, dr, umax)
end

function _R(k::PlaneKernel, a)
    a >= k.rmax && return k.r_grid[end]
    i = floor(Int, a / k.dr) + 1
    t = (a - (i - 1) * k.dr) / k.dr
    return (1 - t) * k.r_grid[i] + t * k.r_grid[i + 1]
end

"""Kick potential W(u) = Int_0^u G, decomposed as sqrt(pi/2)/s (|u| + R(|u|))."""
raw_potential(k::PlaneKernel, u) =
    sqrt(pi / 2) / k.s_t * (abs(u) + _R(k, abs(u)))

# Gaussian mean of |x - x'| for x' ~ N(0, sigma): the analytic non-smooth part
# of the source-averaged potential.
mean_abs(x, sigma) = sqrt(2 / pi) * sigma * exp(-x^2 / (2sigma^2)) +
    x * erf_series(x / (sqrt(2.0) * sigma))

"""erf via erfcx (works for all real arguments)."""
erf_series(z) = z >= 0 ? 1 - exp(-z^2) * erfcx_pos(z) : -(1 - exp(-z^2) * erfcx_pos(-z))

"""Source-averaged raw potential  < W(x - x') >_{x'~N(0,s_src)}  (smooth in x)."""
function averaged_potential(k::PlaneKernel, x, s_src)
    # _R varies on the scale k.s_t, not on s_src: the rule must resolve it.
    smooth = gauss_avg(xp -> _R(k, abs(x - xp)), s_src, k.s_t)
    return sqrt(pi / 2) / k.s_t * (mean_abs(x, s_src) + smooth)
end

"""Slope of the equilibrium force at the origin (all pieces analytic/smooth):
F0'(0) = sqrt(pi/2)/s [ sqrt(2/pi)/s_src + < g'(x') >_{x'} ],
g'(u) = (1/sqrt2 s)(2 z erfcx(z) - 2/sqrt(pi)),  z = |u|/(sqrt2 s)."""
function normalized_equilibrium(k::PlaneKernel, s_src)
    s = k.s_t
    gp(u) = begin
        z = abs(u) / (sqrt(2.0) * s)
        (2z * erfcx_pos(z) - 2 / sqrt(pi)) / (sqrt(2.0) * s)
    end
    return sqrt(pi / 2) / s * (sqrt(2 / pi) / s_src + gauss_avg(gp, s_src, s))
end

# ---------------------------------------------------------------------------
# One beam-plane: detuning omega(J)/xi and the m=1 kernel matrix.
# `scale_w`, `scale_s`: physical size of one witness/source sigma in kernel
# units (1,1 for the symmetric case).
# ---------------------------------------------------------------------------
function detuning_u(k::PlaneKernel, N0, scale_w, scale_s, J)
    # u(J) = 2 d<Vhat0>/dJ, finite differences of the angle average of the
    # exact smooth potential (never the interpolated grid: differentiating
    # across interpolation kinks corrupts the small-J limit u(0) = 1).
    phis = ((0:(NPHI - 1)) .+ 0.5) .* (2pi / NPHI)
    avg(Jv) = begin
        acc = 0.0
        for phi in phis
            x = sqrt(2Jv) * cos(phi) * scale_w
            acc += averaged_potential(k, x, scale_s) / N0
        end
        acc / NPHI
    end
    dJ = 1e-3 * max(J, 0.05)
    Jm = max(J - dJ, 0.0)
    return 2 * (avg(J + dJ) - avg(Jm)) / (J + dJ - Jm)
end

"""
Assemble the m=1 kernel matrix for an arbitrary pairwise potential `V(u)`.

The potential is a parameter so that self-check 5 (harmonic limit) can drive
THIS function rather than a copy of it. It previously re-implemented the phi/phi'
grids, the accumulation and the `(2pi/nphi)(pi/nphi2)/(2pi^2)` factor inline,
under a comment asserting the constants were "identical to kernel_matrix" -- a
hand-copy inside the check whose whole purpose is to pin those constants against
a closed form, which is Measured Lesson 4 turned on itself. Measured: scaling
`kernel_matrix`'s result by 1.05 left self-check 5 reporting Lambda = 1.999975
and kernel_err = 1.2e-14, both unchanged to every printed digit, while every
Lambda in every table moved by +2.2% (2026-08-05_b audit, U22-4).
"""
function kernel_matrix_potential(V, N0, scale_w, scale_s, Jw, Js)
    nphi = NPHI
    nphi2 = NPHI ÷ 2
    phi = ((0:(nphi - 1)) .+ 0.5) .* (2pi / nphi)
    phi2 = ((0:(nphi2 - 1)) .+ 0.5) .* (pi / nphi2)
    cw = cos.(phi); cs = cos.(phi2)
    K = Matrix{Float64}(undef, length(Jw), length(Js))
    for (jj, Jp) in enumerate(Js)
        xs = sqrt(2Jp) .* cs .* scale_s
        for (ii, Jv) in enumerate(Jw)
            xw = sqrt(2Jv) .* cw .* scale_w
            acc = 0.0
            @inbounds for a in 1:nphi, b in 1:nphi2
                acc += cw[a] * cs[b] * V(xw[a] - xs[b])
            end
            K[ii, jj] = acc * (2pi / nphi) * (pi / nphi2) / (2 * pi^2) / N0
        end
    end
    return K
end

kernel_matrix(k::PlaneKernel, N0, scale_w, scale_s, Jw, Js) =
    kernel_matrix_potential(u -> raw_potential(k, u), N0, scale_w, scale_s, Jw, Js)

# ---------------------------------------------------------------------------
# Coupled two-beam eigenproblem for one plane.
# beams: named tuples (Q, xi, scale) — `scale` = this beam's in-plane sigma in
# kernel units. `s_t` in the same units. Returns eigenvalues, and diagnostics.
# ---------------------------------------------------------------------------
function coupled_modes(; Q1, xi1, scale1, Q2, xi2, scale2, s_t, sign_kernel)
    Jn, Jw = gauss_legendre(NJ)
    J = (Jn .+ 1.0) .* (JMAX / 2)
    w = Jw .* (JMAX / 2)
    umax = 1.05 * sqrt(2 * JMAX) * (scale1 + scale2) + 6 * s_t
    k = PlaneKernel(s_t, umax)

    # Normalization in each witness's own dimensionless coordinate: the
    # potential must satisfy Vhat0''(0) = 1 with respect to x-hat = x/scale_w,
    # so the raw curvature N0 (per meter^2 in kernel units) carries scale_w^2.
    #
    # The normalizing curvature must be the PHYSICAL on-axis gradient that
    # defines xi, 1/[sigma_i (sigma_i + sigma_o)] with the SOURCE's sizes, and
    # NOT the reduction's own averaged curvature `normalized_equilibrium`.
    # Using the latter self-normalizes: u(0) is then 1 by construction whatever
    # the kernel does, and the resulting Lambda is too large by
    # (sqrt(2) r + 1)/(r + 1).  The model diagnoses this itself -- with the
    # averaged curvature its rigid-bunch limit returns 1.213 (round) to 1.412
    # (extreme flat) where it must return exactly 1 (self-check 4 below).
    # `s_t` is the summed other-plane spread of both beams, so one beam's is
    # s_t/sqrt(2).
    sigma_o = s_t / sqrt(2.0)
    analytic_gradient(s_src) = 1.0 / (s_src * (s_src + sigma_o))
    N01 = analytic_gradient(scale2) * scale1^2   # beam 1 kicked by 2
    N02 = analytic_gradient(scale1) * scale2^2
    u1 = [detuning_u(k, N01, scale1, scale2, Jv) for Jv in J]
    u2 = [detuning_u(k, N02, scale2, scale1, Jv) for Jv in J]
    K12 = kernel_matrix(k, N01, scale1, scale2, J, J)
    K21 = kernel_matrix(k, N02, scale2, scale1, J, J)

    E = exp.(-J)
    A11 = Diagonal(Q1 .+ xi1 .* u1)
    A22 = Diagonal(Q2 .+ xi2 .* u2)
    A12 = sign_kernel .* 2 .* xi1 .* (E .* K12) .* w'
    A21 = sign_kernel .* 2 .* xi2 .* (E .* K21) .* w'
    M = [Matrix(A11) A12; A21 Matrix(A22)]
    ev = eigen(M)
    g_rigid = sqrt.(2 .* J) .* E
    return (J=J, w=w, u1=u1, u2=u2, values=ev.values, vectors=ev.vectors,
            g_rigid=g_rigid, M=M)
end

"""Locate the eigenvalue whose eigenvector best matches a target block vector."""
function best_match(res, target; block=:both)
    n = length(res.J)
    t = block === :both ? vcat(target, target) :
        block === :diff ? vcat(target, -target) : target
    t = t / norm(t)
    best, overlap = 1, 0.0
    for i in eachindex(res.values)
        v = real.(res.vectors[:, i]); v /= norm(v)
        o = abs(dot(v, t))
        o > overlap && (overlap = o; best = i)
    end
    return real(res.values[best]), overlap
end

# ---------------------------------------------------------------------------
# Exact check: a HARMONIC interaction must give Lambda = 2.
#
# For the pairwise potential V(u) = u^2/2 the source average is x^2/2 +
# s_src^2/2, whose on-axis curvature is 1, so N0 = 1 and
# u(J) = 2 d<V>_phi/dJ = 1 at every action: a linear force detunes nothing.
# The m=1 projection keeps only the cross term -x x', so analytically
#
#   K(J,J') = -(1/2pi^2) sqrt(2J) sqrt(2J') Int_0^2pi cos^2 phi dphi
#                                           Int_0^pi  cos^2 phi' dphi'
#           = -sqrt(J J')/2,
#
# and acting on the rigid translation g = sqrt(2J) e^{-J},
#
#   (C g)(J) = 2 xi e^{-J} Int K(J,J') g(J') dJ' = -xi g(J),
#
# so the sigma mode (g1 = g2) sits at Q0 + xi - xi = Q0 and the pi mode
# (g1 = -g2) at Q0 + xi + xi = Q0 + 2 xi.  Hence Lambda = 2 exactly.
#
# This exercises every assembly constant -- the phi and phi' quadrature
# weights, the 1/(2 pi^2) projection factor, and the 2 xi e^{-J} w' weighting
# -- against a closed form, independently of the Coulomb kernel and of the
# normalization fix that self-check 4 guards.
# ---------------------------------------------------------------------------
function harmonic_Y(; Q=Q0, xi=XI)
    Jn, Jw = gauss_legendre(NJ)
    J = (Jn .+ 1.0) .* (JMAX / 2)
    w = Jw .* (JMAX / 2)
    # THE assembly, not a copy of it: same function the Coulomb tables go
    # through, with the harmonic potential substituted and N0 = 1. That is what
    # makes this check able to fail on a drift in the projection factor or the
    # quadrature weights -- as a hand-copy could not (U22-4).
    K = kernel_matrix_potential(u -> u * u / 2, 1.0, 1.0, 1.0, J, J)
    # Largest relative departure of the assembled kernel from the closed form.
    kerr = maximum(abs(K[i, j] + sqrt(J[i] * J[j]) / 2) /
                   (sqrt(J[i] * J[j]) / 2) for i in eachindex(J), j in eachindex(J))
    E = exp.(-J)
    A = Diagonal(Q .+ xi .* ones(length(J)))      # u(J) = 1 exactly
    C = 2 .* xi .* (E .* K) .* w'
    M = [Matrix(A) C; C Matrix(A)]
    ev = eigen(M)
    res = (J=J, values=ev.values, vectors=ev.vectors)
    g = sqrt.(2 .* J) .* E
    q_sigma, o_s = best_match(res, g; block=:both)
    q_pi, o_p = best_match(res, g; block=:diff)
    return (Y=(q_pi - q_sigma) / xi, q_sigma=q_sigma, q_pi=q_pi,
            kernel_err=kerr, overlap_sigma=o_s, overlap_pi=o_p)
end

# ---------------------------------------------------------------------------
# 1. Symmetric case: self-checks and Y versus aspect ratio.
# ---------------------------------------------------------------------------
mkpath(RESULT_DIR)
const Q0 = 0.31
const XI = 0.01

function symmetric_Y(r; xi=XI, sign_kernel=1.0)
    res = coupled_modes(; Q1=Q0, xi1=xi, scale1=1.0, Q2=Q0, xi2=xi, scale2=1.0,
                        s_t=sqrt(2.0) * r, sign_kernel=sign_kernel)
    sigma_val, sigma_overlap = best_match(res, res.g_rigid; block=:both)
    pi_val = maximum(real.(res.values))
    return (Y=(pi_val - Q0) / xi, sigma_drift=(sigma_val - Q0) / xi,
            sigma_overlap=sigma_overlap, u0=res.u1[1], res=res)
end

# ---------------------------------------------------------------------------
# Independent referee: direct particle simulation of the SAME 1D-reduced
# model. The beam-beam force is a smoothed Hilbert transform of the opposing
# line density, computed spectrally each turn.
#
# This comment used to give the transform as FT[G](k) = -i pi sign(k)
# e^{-s^2 k^2/2}. That Gaussian suppression is WRONG -- it was retracted on
# 2026-07-28 after external review, the correct erfcx form is what the code 21
# lines below actually uses, and the inline comment there explains why. The
# file was carrying the error and its own correction at the same time
# (2026-05_b audit, U22-8). See the header's model section for the corrected
# transform.
#
# "Shares NO code with the matrix eigenproblem" was also too strong, and the
# strength of the cross-check does not need it: `erfcx_pos` is common to both,
# and the on-axis gradient is written out here rather than taken from
# `analytic_gradient`. What is genuinely independent is the SOLVE -- particles
# pushed turn by turn against a matrix eigenproblem -- which is what makes
# agreement meaningful, and it is why this referee was unaffected by the
# quadrature defect that broke the matrix's flat-beam rows (U22-1).
# ---------------------------------------------------------------------------
import FFTW

function simulate_1d_model(r; xi=XI, q0=Q0, n_macro=100_000, turns=4096,
                           ngrid=4096, L=24.0, offset=0.1, seed=1234567)
    s_t = sqrt(2.0) * r
    # (A `PlaneKernel` was built here and never read -- dead since this force
    # became spectral. Removed rather than left as a false hint that the
    # referee shares the matrix path's kernel; audit U22-8.)
    # Same normalization fix as coupled_modes: divide by the PHYSICAL on-axis
    # gradient 1/[sigma_i (sigma_i + sigma_o)], not by the reduction's own
    # averaged curvature. Both solvers must use the same xi or their agreement
    # is meaningless. sigma_o = s_t/sqrt(2) is one beam's other-plane spread.
    N0 = 1.0 / (1.0 * (1.0 + s_t / sqrt(2.0)))
    dx = L / ngrid
    kfreq = 2pi .* FFTW.fftfreq(ngrid, 1 / dx)
    # FT of G(u) = <u/(u^2+v^2)>_{v~N(0,s)}: averaging exp(-|k||v|) over the
    # half-normal gives the erfcx form (NOT a Gaussian suppression, which
    # would correspond to smoothing along u instead of averaging over v).
    Ghat = @. -im * pi * sign(kfreq) * erfcx_pos(s_t * abs(kfreq) / sqrt(2.0))

    # Deterministic Gaussian init (Box-Muller on a simple LCG).
    state = UInt64(seed)
    nextu() = begin
        state = state * 0x5deece66d + 0xb
        (state >> 11) / 2.0^53 + 1e-12
    end
    randn2() = sqrt(-2 * log(nextu())) * cospi(2 * nextu())
    # Float64[...]: the state-mutating closure is boxed, so an untyped
    # comprehension would produce Vector{Any} and box every hot-loop operation.
    beams = [(x=Float64[randn2() for _ in 1:n_macro],
              p=Float64[randn2() for _ in 1:n_macro]) for _ in 1:2]
    beams[1].x .+= offset

    rho = zeros(Float64, ngrid)
    force = [zeros(Float64, ngrid), zeros(Float64, ngrid)]
    c1 = Vector{Float64}(undef, turns); c2 = similar(c1)
    cphi = cos(2pi * q0); sphi = sin(2pi * q0)
    for t in 1:turns
        for b in 1:2
            fill!(rho, 0.0)
            for xv in beams[b].x            # CIC deposit
                g = (xv + L / 2) / dx + 1
                i = floor(Int, g); w = g - i
                if 1 <= i < ngrid
                    rho[i] += (1 - w); rho[i + 1] += w
                end
            end
            rho ./= (n_macro * dx)
            force[b] .= real.(FFTW.ifft(Ghat .* FFTW.fft(rho)))
        end
        for b in 1:2
            fb = force[3 - b]               # kicked by the OTHER beam
            for i in eachindex(beams[b].x)
                xv = beams[b].x[i]
                g = (xv + L / 2) / dx + 1
                j = clamp(floor(Int, g), 1, ngrid - 1); w = g - j
                F = (1 - w) * fb[j] + w * fb[j + 1]
                p = beams[b].p[i] - 4pi * xi * F / N0     # focusing kick
                x2 = cphi * xv + sphi * p                 # rotation
                p2 = -sphi * xv + cphi * p
                beams[b].x[i] = x2; beams[b].p[i] = p2
            end
        end
        c1[t] = sum(beams[1].x) / n_macro
        c2[t] = sum(beams[2].x) / n_macro
    end
    tune(sig) = begin
        n = length(sig)
        m = sum(sig) / n
        w = [0.5 - 0.5 * cospi(2 * (i - 1) / n) for i in 1:n]
        a = abs.(FFTW.rfft((sig .- m) .* w))
        kk = argmax(a[2:end-1]) + 1
        y1, y2, y3 = a[kk-1], a[kk], a[kk+1]
        d = y1 - 2y2 + y3
        (kk - 1 + (d == 0 ? 0.0 : 0.5 * (y1 - y3) / d)) / n
    end
    return (Y=(tune(c1 .- c2) - tune(c1 .+ c2)) / xi,
            q_sigma=tune(c1 .+ c2))
end

# Self-check outcomes, collected rather than only printed.
#
# 11 of the 13 thresholds in this file used to be print-only: the self-checks
# reported PASS/FAIL and escalated to `@warn`, and the only `error()` was the
# kernel-sign gate above -- so a run in which the quadrature was unconverged and
# the harmonic limit was wrong still exited 0, and a caller driving this from a
# script had no way to tell (2026-08-05_b audit, U22-11). The individual
# warnings stay, because they name which downstream rows are affected; what is
# new is that the run now FAILS at the end if any of them fired.
const SELF_CHECK_FAILURES = String[]

if get(ENV, "OCTOPUS_VLASOV_LIB_ONLY", "0") == "1"
    # Definitions only (for convergence experiments and external reuse).
else

println("Self-check 4 (normalization + origin-region quadrature):")
println("  The rigid-bunch limit is analytically 1: the coherent gradient")
println("  1/[2(sigma_o+1)] over the physical normalizer 1/(1+sigma_o).  It")
println("  therefore tests BOTH that the normalization is not circular AND that")
println("  the origin-region quadrature in `normalized_equilibrium` has")
println("  converged.  Tolerance 2e-2.")
let failed = String[]
    for r in (0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.85, 1.0, 5.0, 11.111)
        s_t = sqrt(2.0) * r
        kk = PlaneKernel(s_t, 1.05 * sqrt(2 * JMAX) * 2 + 6 * s_t)
        n0phys = 1.0 / (1.0 + s_t / sqrt(2.0))
        rigid = 2 * normalized_equilibrium(kk, sqrt(2.0)) / n0phys
        u0 = detuning_u(kk, n0phys, 1.0, 1.0, 1e-6)
        # PRIMARY test, and deliberately not substitutable: u(0) must equal
        # the exact ratio of the reduction's own gradient 1/(1+s_t) to the
        # physical normalizer 1/(1+sigma_o), i.e. (1+r)/(1+sqrt2 r).  This
        # exercises `averaged_potential`'s quadrature directly.  The rigid
        # diagnostic below tests `normalized_equilibrium` only, and would be
        # silently satisfied if a later maintainer substituted the analytic
        # gradient there while leaving the potential quadrature broken.
        u0_exact = (1.0 + r) / (1.0 + sqrt(2.0) * r)
        ok = abs(u0 - u0_exact) < 2e-2
        ok || push!(failed, string(r))
        println("  r=", rpad(r, 7), " u(0)=", rpad(round(u0; digits=4), 8),
                " exact=", rpad(round(u0_exact; digits=4), 8),
                " rigid=", rpad(round(rigid; digits=4), 9),
                ok ? "PASS" : "FAIL (quadrature unconverged at this s_t)")
    end
    isempty(failed) || push!(SELF_CHECK_FAILURES,
        "self-check 4 (normalization + origin quadrature) at r = " * join(failed, ", "))
    if !isempty(failed)
        @warn string("Self-check 4 FAILED at aspect ratios ", join(failed, ", "),
                     ": `normalized_equilibrium`'s origin-region quadrature is ",
                     "unconverged for s_t below ~1. Lambda from those rows is not ",
                     "quantitative and must not be plotted or quoted.")
    end
end

println()
println("Self-check 5 (harmonic interaction must give Lambda = 2 exactly):")
let h = harmonic_Y()
    println("  assembled kernel vs closed form -sqrt(J J')/2: max rel. err = ",
            round(h.kernel_err; sigdigits=3))
    println("  q_sigma - Q0 = ", round(h.q_sigma - Q0; sigdigits=3),
            " (must be 0; rigid-vector overlap ", round(h.overlap_sigma; digits=4), ")")
    println("  (q_pi - Q0)/xi = ", round((h.q_pi - Q0) / XI; digits=6),
            " (must be 2; overlap ", round(h.overlap_pi; digits=4), ")")
    println("  Lambda = ", round(h.Y; digits=6),
            abs(h.Y - 2.0) < 1e-3 && h.kernel_err < 1e-6 ? "  PASS" : "  FAIL")
    (abs(h.Y - 2.0) < 1e-3 && h.kernel_err < 1e-6) || push!(SELF_CHECK_FAILURES,
        "self-check 5 (harmonic limit) Lambda = $(h.Y), kernel err = $(h.kernel_err)")
    if !(abs(h.Y - 2.0) < 1e-3 && h.kernel_err < 1e-6)
        @warn string("Self-check 5 FAILED: harmonic interaction gives Lambda = ",
                     h.Y, " (exact 2) with kernel error ", h.kernel_err,
                     ". An assembly constant in `kernel_matrix` -- a quadrature ",
                     "weight, the 1/(2 pi^2) projection or the 2 xi e^{-J} w' ",
                     "weighting -- is wrong; every Lambda below is then wrong ",
                     "by the same factor.")
    end
end

println()
println("Self-checks (round beams, r=1, xi=$(XI), Q0=$(Q0)):")
for s in (1.0, -1.0)
    chk = symmetric_Y(1.0; sign_kernel=s)
    println("  sign_kernel=$(s):  sigma-mode drift/xi = ",
            round(chk.sigma_drift; sigdigits=3),
            "  (rigid-vector overlap ", round(chk.sigma_overlap; digits=3), ")",
            "   u(Jmin) = ", round(chk.u0; digits=4),
            "   max eigenvalue -> Y = ", round(chk.Y; digits=4))
end

# The physical sign is the one that puts the co-moving translation mode at
# Q0 — the theory note's structural check 1, used here as the selector
# because the note fixes the eigenproblem's sign convention while the
# assembled kernel's sign depends on quadrature bookkeeping this script owns.
# Turning the check into a selector costs it its power to fail on sign, so
# the selected sign must still SATISFY the criterion: the note's measured
# floor is |drift|/xi ~ 1e-5, and if neither sign lands within 10x of that
# the kernel assembly is broken and every Lambda below would be wrong —
# stopping is honest, silently adopting the less-bad sign was not
# (2026-08-05 audit, U19-10).
chk_p = symmetric_Y(1.0; sign_kernel=1.0)
chk_m = symmetric_Y(1.0; sign_kernel=-1.0)
const SIGN_KERNEL = abs(chk_p.sigma_drift) < abs(chk_m.sigma_drift) ? 1.0 : -1.0
let best = min(abs(chk_p.sigma_drift), abs(chk_m.sigma_drift))
    best <= 1.0e-4 || error(
        "neither kernel sign puts the co-moving translation mode at Q0 " *
        "(best |sigma drift|/xi = $(best), criterion 1e-4): the kernel " *
        "assembly is broken, not merely signed the other way")
end
println("selected sign_kernel = ", SIGN_KERNEL)

y1 = symmetric_Y(1.0; xi=XI, sign_kernel=SIGN_KERNEL)
y2 = symmetric_Y(1.0; xi=2XI, sign_kernel=SIGN_KERNEL)
println("xi-independence of Y (leading order): Y(xi)=",
        round(y1.Y; digits=4), "  Y(2xi)=", round(y2.Y; digits=4))

println()
println("Yokoya factor versus flatness r = sigma_other/sigma_plane")
println("(m=1 matrix and exact 1D-model simulation; the difference here is dominated")
println(" by the particle solver's PERIODIC BOX, not by m=1 truncation — see")
println(" yokoya_box_convergence.tsv and docs/theory/coherent_beam_beam_modes.md;")
println(" the physical 2D values come from validation/coherent_mode_scans.jl):")
aspects = [0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.85, 1.0]   # 0.02 ~ flat limit

# Per-row invariants. The 2026-08-05_b audit (U22-1) shipped a table whose three
# flattest rows were quadrature artifacts, and each of these would have caught it
# on its own -- while the criteria themselves already existed in the file, applied
# only at r = 1 as the kernel-sign selector. A row that fails any of them is not a
# Yokoya factor and is not written as one.
#
#   max u <= 1   exact in this model (self-check 4): u(J) is the reduction's
#                averaged curvature over the physical on-axis one. The broken
#                quadrature returned max u = 23.16 at r = 0.02.
#   Lambda - max u   a discrete pi mode must sit clear of the continuum whose top
#                is max u. When the gap collapses to the eigenvalue spacing the
#                largest eigenvalue IS the band edge, so reporting it as a mode
#                names a continuum top after a mode. At r <= 0.1 the broken run
#                had gap <= 0.007 against 0.17-0.33 everywhere it was right.
#   sigma drift  translation invariance, the check that validates every constant
#                in the kernel at once.
const U_MAX_TOL = 1.0e-3        # max u <= 1 + tol
const MODE_GAP_MIN = 0.02       # Lambda - max u, well above the ~1e-3 spacing
const DRIFT_TOL = 1.0e-4        # |sigma drift| / xi

not_modes = String[]
mesh_limited = String[]
open(joinpath(RESULT_DIR, "yokoya_vs_aspect.tsv"), "w") do io
    # Numeric columns only: the paper repository's make_figures.py
    # (https://github.com/xud929/2026_octopus_cpc) parses every field with
    # float(), so a status string here would break the figure pipeline. The
    # human-readable verdict goes to stdout; `is_mode` and `mesh_ok` carry it
    # here as 1/0.
    println(io, "aspect_ratio\tY_m1_matrix\tY_1d_sim\tsigma_drift_over_xi\tmax_u\tmode_gap\tis_mode\tmesh_ok")
    for r in aspects
        out = symmetric_Y(r; sign_kernel=SIGN_KERNEL)
        sim = simulate_1d_model(r)
        max_u = maximum(out.res.u1)
        gap = out.Y - max_u
        # Two independent verdicts, kept apart because they mean different
        # things. `not_a_mode` says the reported number is the top of the
        # continuum rather than a discrete mode -- it must not be quoted at all.
        # `mesh_limited` says the mode is real but the J-mesh has not resolved
        # the kernel's translation invariance to the usual floor, so the value
        # carries fewer digits than the rows around it. Conflating them would
        # have re-made the original mistake in the other direction.
        notmode = String[]
        max_u <= 1 + U_MAX_TOL || push!(notmode, "max_u=$(round(max_u; sigdigits=5))>1")
        gap >= MODE_GAP_MIN || push!(notmode, "gap=$(round(gap; sigdigits=3))<$(MODE_GAP_MIN)")
        mesh_ok = abs(out.sigma_drift) <= DRIFT_TOL
        status = !isempty(notmode) ? "not_a_mode:" * join(notmode, ";") :
                 mesh_ok ? "ok" : "mesh_limited:drift=$(round(out.sigma_drift; sigdigits=3))"
        isempty(notmode) || push!(not_modes, "r=$r (" * join(notmode, ";") * ")")
        isempty(notmode) && !mesh_ok && push!(mesh_limited, "r=$r")
        println(io, r, '\t', out.Y, '\t', sim.Y, '\t', out.sigma_drift, '\t',
                max_u, '\t', gap, '\t', isempty(notmode) ? 1 : 0, '\t', mesh_ok ? 1 : 0)
        println("  r = ", rpad(r, 5), "  Y(m=1 matrix) = ",
                rpad(round(out.Y; digits=3), 6),
                "  Y(exact 1D sim) = ", rpad(round(sim.Y; digits=3), 6),
                "  (sigma drift/xi = ", rpad(round(out.sigma_drift; sigdigits=2), 9),
                "  max u = ", rpad(round(max_u; digits=4), 7),
                "  gap = ", rpad(round(gap; digits=4), 7), ")",
                isempty(notmode) ? (mesh_ok ? "" : "  [mesh-limited]") :
                    "  <-- NOT A MODE: " * join(notmode, ";"))
    end
end
if isempty(not_modes) && isempty(mesh_limited)
    println("  [PASS] every row: max u <= 1, discrete pi mode clear of the continuum, ",
            "translation invariance within $(DRIFT_TOL).")
else
    # `max u <= 1` is the invariant with teeth -- a row that violates it is the
    # top of the incoherent continuum, not a Yokoya factor. It was checked and
    # warned about, never escalated, so a run producing them exited 0
    # (2026-08-05_b audit, U22-11).
    isempty(not_modes) || push!(SELF_CHECK_FAILURES,
        "aspect-scan rows that are NOT discrete modes: " * join(not_modes, ", "))
    isempty(not_modes) ||
        @warn """these rows are NOT Yokoya factors: `Y_m1_matrix` is the top of
                 the incoherent continuum, not a discrete mode. Do not quote
                 them. This is the failure the 96-node Gauss-Hermite average
                 produced for every r <= 0.1 before audit U22-1.""" rows = not_modes
    isempty(mesh_limited) ||
        @warn """these rows ARE discrete modes (max u <= 1, mode clear of the
                 continuum) but the J-mesh has not resolved translation
                 invariance to $(DRIFT_TOL); they carry fewer digits than the
                 rest of the scan. Measured: OCTOPUS_VLASOV_NJ=128/NPHI=160
                 brings r=0.02 to |drift| = 7.5e-5 and moves Lambda by 3e-4.""" rows = mesh_limited
end

# The scan above covers r <= 1, i.e. the WIDE plane of a flat source.  The
# NARROW plane of the same source is the reciprocal aspect ratio (r = 11.111
# for our sigma_x/sigma_y = 11.111 point), which self-check 4 above shows is on
# the CONVERGED side of the quadrature -- unlike its wide-plane partner
# r = 0.09.  Archive it so the narrow-plane numbers quoted in the paper are
# reproducible.  Lambda is taken from the m=1 matrix, which has no box.
println()
println("Narrow plane (reciprocal aspect ratio, r >= 1; converged side):")
open(joinpath(RESULT_DIR, "yokoya_vs_aspect_narrow.tsv"), "w") do io
    println(io, "# Narrow-plane branch of the 1D reduction: r = sigma_wide/sigma_narrow >= 1.")
    println(io, "# Self-check 4 passes throughout this range (it fails only for r <= 0.3).")
    println(io, "# Y_1d_sim here uses the DEFAULT periodic box L=24, which is NOT converged")
    println(io, "# at large r -- see yokoya_box_convergence.tsv.  Quote Y_m1_matrix.")
    println(io, "aspect_ratio\tY_m1_matrix\tY_1d_sim_L24\tspread_percent_L24")
    for r in [1.0, 1.5, 2.0, 3.0, 5.0, 11.111, 20.0, 50.0, 100.0, 500.0]
        out = symmetric_Y(r; sign_kernel=SIGN_KERNEL)
        sim = simulate_1d_model(r)
        spread = 100 * abs(sim.Y / out.Y - 1)
        println(io, r, '\t', out.Y, '\t', sim.Y, '\t', spread)
        println("  r = ", rpad(r, 7), "  Y(m=1) = ", rpad(round(out.Y; digits=4), 7),
                "  Y(sim,L=24) = ", rpad(round(sim.Y; digits=4), 7),
                "  spread = ", round(spread; digits=2), "%")
    end
end

# Box-convergence of the particle solver.  The apparent m=1/exact "truncation
# spread" -- 1.7% at round beams growing to 12.5% when flat -- is NOT truncation:
# it is the particle solver's periodic box.  The kernel's range is set by the
# OTHER plane's width sigma_o = s_t/sqrt(2) = r, so at r = 50 the default
# L = 24 box is narrower than the kernel itself.  Widening it at fixed dx drives
# the particle solution onto the matrix result at every aspect ratio, which
# establishes that the m=1/diagonal truncation error is negligible and that the
# two solvers are one consistent model.
println()
println("Periodic-box convergence of the particle solver (dx held fixed):")
open(joinpath(RESULT_DIR, "yokoya_box_convergence.tsv"), "w") do io
    println(io, "# Widening the particle solver's periodic box at fixed dx = L/ngrid.")
    println(io, "# Demonstrates the m=1-vs-exact difference is a box artifact, not truncation.")
    println(io, "aspect_ratio\tL\tngrid\tY_1d_sim\tY_m1_matrix\tspread_percent")
    for r in [0.2, 0.5, 1.0, 11.111, 50.0]
        mat = symmetric_Y(r; sign_kernel=SIGN_KERNEL).Y
        for L in [24.0, 48.0, 96.0, 192.0]
            ng = round(Int, 4096 * L / 24)
            sim = simulate_1d_model(r; L=L, ngrid=ng).Y
            spread = 100 * abs(mat / sim - 1)
            println(io, r, '\t', L, '\t', ng, '\t', sim, '\t', mat, '\t', spread)
            println("  r = ", rpad(r, 7), " L = ", rpad(L, 6),
                    " Y(sim) = ", rpad(round(sim; digits=4), 7),
                    " Y(m=1) = ", rpad(round(mat; digits=4), 7),
                    " spread = ", round(spread; digits=2), "%")
        end
    end
end

# ---------------------------------------------------------------------------
# 2. Finite-xi correction from the discrete one-turn map (rigid algebra with
#    Y0 inserted): cos 2pi Q_pi = cos 2pi Q0 - 2pi Y0 xi sin 2pi Q0.
#    Y0 is anchored to the MEASURED converged 2D round-beam value (1.20 from
#    the 8192-turn benchmark; the 1D-reduced model overestimates it, see the
#    theory note) so the curve is comparable with the measured xi scan.
# ---------------------------------------------------------------------------
Y0_anchor = 1.20
open(joinpath(RESULT_DIR, "yokoya_vs_xi_theory.tsv"), "w") do io
    println(io, "xi\tY_eff")
    for xi in 0.0005:0.0005:0.025
        c = cos(2pi * Q0) - 2pi * Y0_anchor * xi * sin(2pi * Q0)
        Qpi = acos(clamp(c, -1.0, 1.0)) / 2pi
        println(io, xi, '\t', (Qpi - Q0) / xi)
    end
end
println()
println("Finite-xi map correction written (Y0 anchored to measured 1.20).")

# ---------------------------------------------------------------------------
# 3. EIC-like asymmetric case (strong-strong example constants, head-on
#    equivalent). Lengths in meters inside the kernel.
# ---------------------------------------------------------------------------
# These MUST match src/constants/Constants.jl (2026-08-05_b audit, U22-15). They
# were older CODATA values -- 2.8179403262e-15, 0.51099906e6, 938.27231e6 --
# while the framework carries the current ones, so this script and
# coherent_mode_eic_comparison.jl described "the same EIC case" with different
# physical constants. The differences are ~1e-9 relative and changed no reported
# digit, which is why it went unnoticed; that is exactly the drift Measured
# Lesson 4 is about.
#
# The copy stays because this script is deliberately standalone (LinearAlgebra
# and FFTW only, no Octopus import), so the suite carries a tripwire that reads
# these three lines and compares them against the framework's values.
const RE_M = 2.8179403205e-15
const EMASS = 0.51099895069e6
const PMASS = 938.27208943e6
ele = (E=10.0e9, N=1.7203e11, sig=(106.0e-6, 9.5e-6), tune=(0.08, 0.14))
pro = (E=275.0e9, N=0.6881e11, sig=(95.0e-6, 8.5e-6), tune=(0.228, 0.210))
beta_e = (0.55, 0.056); beta_p = (0.8, 0.072)
gamma_e = ele.E / EMASS; gamma_p = pro.E / PMASS
r_p = RE_M * EMASS / PMASS

xi_bb(N_src, r0, beta_w, gamma_w, sig_src, i) =
    N_src * r0 * beta_w[i] / (2pi * gamma_w * sig_src[i] * (sig_src[1] + sig_src[2]))

println()
println("EIC-like asymmetric coupled modes (head-on equivalent):")
open(joinpath(RESULT_DIR, "eic_coherent_modes.tsv"), "w") do io
    println(io, "plane\tQ_e\txi_e\tQ_p\txi_p\teigenvalue\tin_e_continuum\tin_p_continuum")
    for (plane, i) in ((:x, 1), (:y, 2))
        j = 3 - i    # the averaged plane
        xi_e = xi_bb(pro.N, RE_M, beta_e, gamma_e, pro.sig, i)
        xi_p = xi_bb(ele.N, r_p, beta_p, gamma_p, ele.sig, i)
        s_t = sqrt(ele.sig[j]^2 + pro.sig[j]^2)
        res = coupled_modes(; Q1=ele.tune[i], xi1=xi_e, scale1=ele.sig[i],
                            Q2=pro.tune[i], xi2=xi_p, scale2=pro.sig[i],
                            s_t=s_t, sign_kernel=SIGN_KERNEL)
        vals = sort(real.(res.values))
        e_band = (ele.tune[i], ele.tune[i] + xi_e * maximum(res.u1))
        p_band = (pro.tune[i], pro.tune[i] + xi_p * maximum(res.u2))
        println("  plane ", plane, ":  xi_e = ", round(xi_e; digits=4),
                "  xi_p = ", round(xi_p; digits=4))
        println("    e continuum ", round.(e_band; digits=4),
                "   p continuum ", round.(p_band; digits=4))
        # Report discrete eigenvalues outside both continua (tolerance one
        # grid spacing of the discretized continuum).
        tol = 0.02 * max(xi_e, xi_p)
        discrete = [v for v in vals if
            !(e_band[1] - tol <= v <= e_band[2] + tol) &&
            !(p_band[1] - tol <= v <= p_band[2] + tol)]
        println("    discrete modes outside both continua: ",
                isempty(discrete) ? "none" :
                join(round.(discrete; digits=5), ", "))
        # Guarded: `maximum` over an empty generator throws
        # `ArgumentError: reducing over an empty collection`, and it would do so
        # AFTER the TSV had been partially written (2026-08-05_b audit, U22-18).
        # It cannot fire for the two shipped EIC planes, where the lowest
        # eigenvalue always sits near Q_e, but it is one parameter change away --
        # a much larger tune split, or an inverted band ordering in a future
        # asymmetric case.
        near_e = [v for v in vals if v <= e_band[2] + 5 * xi_e]
        if isempty(near_e)
            println("    highest mode near e-band: none (no eigenvalue at or below ",
                    round(e_band[2] + 5 * xi_e; digits=5),
                    "; the spectrum sits entirely above the electron band)")
        else
            top_e = maximum(near_e)
            println("    highest mode near e-band: ", round(top_e; digits=5),
                    "  ->  (Q - Q_e)/xi_e = ",
                    round((top_e - ele.tune[i]) / xi_e; digits=3))
        end
        top_all = maximum(vals)
        println("    highest mode overall:    ", round(top_all; digits=5),
                "  ->  (Q - Q_p)/xi_p = ",
                round((top_all - pro.tune[i]) / xi_p; digits=3))
        for v in vals
            println(io, plane, '\t', ele.tune[i], '\t', xi_e, '\t',
                    pro.tune[i], '\t', xi_p, '\t', v, '\t',
                    e_band[1] - tol <= v <= e_band[2] + tol, '\t',
                    p_band[1] - tol <= v <= p_band[2] + tol)
        end
    end
end
println()
# All five, not three (2026-08-05_b audit, U22-14 / U19-6): the header at the
# top of this file lists them correctly and this closing line named only three,
# so a reader who trusted the run's own summary missed two of its outputs.
println("TSV outputs in result/: yokoya_vs_aspect.tsv, yokoya_vs_aspect_narrow.tsv, ",
        "yokoya_box_convergence.tsv, yokoya_vs_xi_theory.tsv, eic_coherent_modes.tsv")

# The gate. `OCTOPUS_VLASOV_ALLOW_SELF_CHECK_FAILURE=1` reduces it to a warning,
# for the convergence experiments that deliberately drive the quadrature past
# where it converges -- but the default is to fail, so a run that produces
# non-quantitative rows cannot be mistaken for one that did not.
if !isempty(SELF_CHECK_FAILURES)
    message = "coherent-mode Vlasov self-checks failed: " *
              join(SELF_CHECK_FAILURES, "; ") *
              ". Lambda from the affected rows is not quantitative and must not " *
              "be plotted or quoted."
    if get(ENV, "OCTOPUS_VLASOV_ALLOW_SELF_CHECK_FAILURE", "0") == "1"
        @warn message
    else
        error(message)
    end
else
    println("all self-checks PASS")
end

end # OCTOPUS_VLASOV_LIB_ONLY guard
