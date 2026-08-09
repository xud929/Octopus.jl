export GaussianPICPoissonSolver

#=
Gaussian-subtracted PIC strong-strong collision solver (a control-variate / delta-f
hybrid). It reuses the entire PICPoissonSolver machinery -- slicing, drifted
deposition, the integrated-log Green FFT and its slice-pair cache, field
interpolation, and luminosity -- but before the Poisson solve it subtracts the
analytic deposition of a reference Gaussian (the slice's own drifted transverse
moments) from the charge grid, and after the field interpolation it adds the
exact Bassetti-Erskine field of that same Gaussian back at each field particle.
The grid therefore carries only the small residual delta_rho, so the field error
at a fixed grid falls sharply while the FFT cost is unchanged.

See docs/theory/gaussian_subtracted_pic_solver.md for the derivation (including the
node-centered erf moment integrals for CIC/TSC deposition, the domain-margin and
neutralization arguments, and the coupling switch). This is the CPU
implementation; the CUDA path lives in pic_cuda.jl.
=#

# ---------------------------------------------------------------------------
# Solver type: composition over PICPoissonSolver plus the Gaussian-subtraction
# controls. All PIC options are forwarded to the embedded solver, so the PIC
# leaf helpers are reused unchanged by passing `solver.pic`.
# ---------------------------------------------------------------------------
"""
    GaussianPICPoissonSolver(; margin_sigma=5.0, neutralize=true,
                             coupling_tol=Inf, kwargs...)

Gaussian-subtracted PIC strong-strong collision solver: a control-variate
("delta-f") hybrid of the analytic soft-Gaussian field and the grid PIC solver.
For each directed slice interaction it deposits the source slice, subtracts the
erf-integrated reference Gaussian (the slice's own drifted transverse moments)
from the charge grid, solves the *residual* with the same integrated-log Green
FFT as `PICPoissonSolver`, and adds the exact Bassetti-Erskine field back per
field particle. This raises systematic field accuracy at a fixed grid; the hybrid
error is nearly grid-independent. See `docs/theory/gaussian_subtracted_pic_solver.md`.

The solver composes a `PICPoissonSolver`: every PIC keyword is accepted by the
constructor and stored on the embedded solver, so `?PICPoissonSolver` documents
them. Six of them select machinery the hybrid does not implement and are
REJECTED at collide time rather than silently ignored: `interaction_grid`,
non-`:linear` `slice_interpolation`, and `grid_extent = :sigma` on either
backend, and `cuda_async = false`, `cuda_batch_fft = false`, or
`cuda_wavefront_fft = false` on CUDA, whose hybrid route is chosen by
`batch_mode` and `cuda_indexed_wavefront` alone. The additional options are:

- `margin_sigma`: minimum adaptive-box half-width, in beam sigmas, for containing
  the subtracted Gaussian (its tails extend beyond the particle cloud). `0`
  keeps the ordinary particle-wrapping box.
- `neutralize`: rescale the subtracted Gaussian grid so its total matches the
  deposited particles, removing the spurious open-boundary monopole.
- `coupling_tol`: correlation-coefficient threshold
  `|sigma_xy/(sigma_x*sigma_y)|` above which the coupled (rotated) subtraction is
  used. The default `Inf` always takes the separable uncoupled path; a finite
  value (`0` forces coupling wherever the covariance is numerically full rank)
  subtracts a *rotated* Gaussian built from the slice's full transverse covariance,
  per Section 7 of
  `docs/theory/gaussian_subtracted_pic_solver.md`. Available on the CPU path and
  on the default CUDA route (`batch_mode=:wavefront` with
  `cuda_indexed_wavefront=true`); the other two CUDA routes raise rather than
  silently running the uncoupled subtraction. When uncoupled, the residual grid
  absorbs any transverse coupling, so this is an accuracy refinement, not a
  correctness fix.

If a requested reference Gaussian is undefined (too few particles, a zero
marginal RMS, or a numerically rank-deficient coupled covariance), the entire
directed interaction falls back to the embedded ordinary PIC algorithm. The
rank test is dimensionless and precision-derived; no physical beam-size cutoff
is imposed.

**Use `deposit_method=:TSC` with this solver.** TSC is consistently the more
accurate deposition for the hybrid at nearly every grid and aspect ratio (e.g. at
the production 11:1 beams, grid 64: 1.7e-4 median field error with TSC against
2.4e-4 with CIC; at 25:1, 1.6e-4 against 3.2e-4), while for *plain* PIC it is
never better than CIC. The reason is that the subtraction removes the sharp
Gaussian core, leaving a smooth residual that TSC's wider stencil represents well
without the extra smoothing hurting. It costs ~25% more per interaction on CPU.

CPU and CUDA are supported and agree to rounding -- measured ~1e-13 relative on
the kicks at grid 16 -- not bit for bit: the two backends deposit and reduce in
different orders, and with the default `neutralize = true` they additionally
normalise the subtracted Gaussian to slightly different quantities (the CPU to
the deposited grid total, CUDA to the slice particle count, equal to ~1e-16
whenever no deposit clips). The CUDA path defaults to the indexed wavefront
route (see `gaussian_pic_cuda.jl`).
"""
struct GaussianPICPoissonSolver{T<:Real} <: AbstractPoissonSolver
    pic::PICPoissonSolver{T}
    margin_sigma::T
    neutralize::Bool
    coupling_tol::T
end

function GaussianPICPoissonSolver{T}(; margin_sigma=5.0, neutralize::Bool=true,
                                     coupling_tol=T(Inf), kwargs...) where {T<:Real}
    pic = PICPoissonSolver{T}(; kwargs...)
    ms = T(margin_sigma)
    ct = T(coupling_tol)
    ms >= zero(T) || throw(ArgumentError(
        "margin_sigma must be non-negative; got $(margin_sigma)."))
    ct >= zero(T) || throw(ArgumentError(
        "coupling_tol must be non-negative; got $(coupling_tol)."))
    # A finite coupling_tol selects the coupled (rotated) subtraction of docs
    # Section 7, implemented on the CPU path and on the default CUDA route
    # (indexed wavefront); the other two CUDA routes throw rather than
    # silently running the uncoupled subtraction. (An earlier version of this
    # comment said "CPU path only", which the CUDA route contradicted --
    # audit part 7, G3.)
    return GaussianPICPoissonSolver{T}(pic, ms, neutralize, ct)
end

GaussianPICPoissonSolver(; kwargs...) = GaussianPICPoissonSolver{Float64}(; kwargs...)

# ---------------------------------------------------------------------------
# Configuration metadata: the PIC schema plus the three Gaussian options.
# ---------------------------------------------------------------------------
const _GAUSSIAN_PIC_EXTRA_OPTION_SCHEMA = (
    margin_sigma = SolverOptionMeta(Real, 5.0,
        "Minimum adaptive-box half-width in beam sigmas for containing the subtracted Gaussian; 0 keeps the particle-wrapping box.";
        category=:accuracy_performance, consumer=:gaussian_pic_subtraction),
    neutralize = SolverOptionMeta(Bool, true,
        "Rescale the subtracted Gaussian grid so its total matches the deposited particles, removing the spurious open-boundary monopole.";
        category=:accuracy_performance, consumer=:gaussian_pic_subtraction),
    coupling_tol = SolverOptionMeta(Real, Inf,
        "Correlation-coefficient threshold |sigma_xy/(sigma_x*sigma_y)| above which the coupled (rotated) subtraction is used; Inf always uses the separable uncoupled subtraction, and numerically rank-deficient coupled references fall back to ordinary PIC.";
        category=:physics, consumer=:gaussian_pic_subtraction),
)

solver_option_schema(::Type{<:GaussianPICPoissonSolver}) =
    merge(_PIC_SOLVER_OPTION_SCHEMA, _GAUSSIAN_PIC_EXTRA_OPTION_SCHEMA)

function solver_configuration(solver::GaussianPICPoissonSolver)
    picconf = solver_configuration(solver.pic)
    return merge(picconf, (
        margin_sigma=solver.margin_sigma,
        neutralize=solver.neutralize,
        coupling_tol=solver.coupling_tol,
    ))
end

"""
PIC options the hybrid neither reads nor accepts a non-default value for.

Listed once here and consumed by `configuration_report` so the user-facing
"what will actually happen" surface cannot claim a setting is resolved when
`collide!` throws on it (2026-08-05_b audit, U10-1).
"""
const _GPIC_INERT_PIC_OPTIONS = (:slice_interpolation, :interaction_grid,
                                 :grid_extent, :grid_extent_sigma,
                                 :cuda_async, :cuda_batch_fft,
                                 :cuda_wavefront_fft)

function configuration_report(solver::GaussianPICPoissonSolver;
                              policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                              backend=nothing)
    pic_entries = configuration_report(solver.pic; policy=policy, backend=backend)
    # Seven of the embedded PIC solver's entries are NOT resolved for the
    # hybrid, and forwarding them unmodified told the user a setting was in
    # force for values that hard-error (2026-08-05_b audit, U10-1).
    # `_require_linear_slice_interpolation` throws on a non-default
    # `slice_interpolation`, `interaction_grid` or `grid_extent`, and the CUDA
    # route throws on `cuda_async`/`cuda_batch_fft`/`cuda_wavefront_fft = false`.
    # Even at their defaults the hybrid does not read them: it hardcodes the
    # slice-pair box, sizes its extent from `margin_sigma`, and picks its CUDA
    # route from `batch_mode` and `cuda_indexed_wavefront` alone. The
    # `coupling_tol` entry below is the pattern -- report the dependency, do not
    # claim resolution. "Ignored configuration must warn, throw, or be
    # documented as inert, never vanish", applied to the report rather than to
    # the run: the throw is loud and the report contradicted it.
    pic_entries = map(pic_entries) do e
        e.name in _GPIC_INERT_PIC_OPTIONS || return e
        ConfigurationEntry(e.name, e.requested, e.resolved, :inactive_dependency,
            "not read by GaussianPICPoissonSolver: " * e.reason, e.consumer)
    end
    extras = ConfigurationEntry[]
    push!(extras, ConfigurationEntry(:margin_sigma, solver.margin_sigma, solver.margin_sigma,
        :resolved, "adaptive-box Gaussian containment margin in sigmas", :gaussian_pic_subtraction))
    push!(extras, ConfigurationEntry(:neutralize, solver.neutralize, solver.neutralize,
        :resolved, "discrete charge neutralization of the subtracted Gaussian", :gaussian_pic_subtraction))
    coupled_active = isfinite(solver.coupling_tol)
    push!(extras, ConfigurationEntry(:coupling_tol, solver.coupling_tol, solver.coupling_tol,
        coupled_active ? :resolved : :inactive_dependency,
        coupled_active ?
            "coupled (rotated) subtraction above the correlation threshold; CPU and the default CUDA indexed-wavefront route" :
            "always-uncoupled separable subtraction",
        :gaussian_pic_subtraction))
    return (pic_entries..., Tuple(extras)...)
end

# The embedded PIC solver owns backend_configurations, and gaussian_pic_cuda.jl
# reaches the same _cuda_pic_threads consumers as pic_cuda.jl, so the launch
# configuration must resolve through it.
_pic_launch_solver(solver::GaussianPICPoissonSolver) = solver.pic

# Luminosity scheduling and kbb/luminosity scales all reuse the PIC logic.
_pic_compute_luminosity(solver::GaussianPICPoissonSolver, ctx) =
    _pic_compute_luminosity(solver.pic, ctx)
_strong_strong_luminosity_evaluated(solver::GaussianPICPoissonSolver, ctx::TrackingContext) =
    _pic_compute_luminosity(solver.pic, ctx)

# ---------------------------------------------------------------------------
# Node-centered erf Gaussian deposition profile (docs Section 5).
# Fills g[i] = integral of the unit Gaussian against the CIC/TSC assignment
# function centered on node x_i = x0 + (i-1)*h.
# ---------------------------------------------------------------------------
function _gpic_gaussian_profile!(g::AbstractVector{T}, x0::T, h::T, mu::T, sigma::T,
                                 method::Symbol) where {T}
    n = length(g)
    s = sigma
    invroot = inv(s * sqrt(T(2)))
    norm = inv(s * sqrt(2 * T(pi)))
    pdf(x) = norm * exp(-((x - mu) * (x - mu)) / (2 * s * s))
    m0(A, B) = T(0.5) * (erf((B - mu) * invroot) - erf((A - mu) * invroot))
    m1(A, B, xi) = (mu - xi) * m0(A, B) - s * s * (pdf(B) - pdf(A))
    m2(A, B, xi) = (s * s + (mu - xi)^2) * m0(A, B) -
                   s * s * ((B - mu) * pdf(B) - (A - mu) * pdf(A)) -
                   2 * (mu - xi) * s * s * (pdf(B) - pdf(A))
    half = h / 2
    if method === :CIC
        @inbounds for i in 1:n
            xi = x0 + (i - 1) * h
            g[i] = m0(xi - h, xi + h) + (m1(xi - h, xi, xi) - m1(xi, xi + h, xi)) / h
        end
    else # :TSC
        @inbounds for i in 1:n
            xi = x0 + (i - 1) * h
            cL = xi - half; cR = xi + half
            lL = xi - 3half; lR = xi - half   # left wing = [xi-3h/2, xi-h/2]
            rL = xi + half; rR = xi + 3half   # right wing = [xi+h/2, xi+3h/2]
            g[i] = T(0.75) * m0(cL, cR) - m2(cL, cR, xi) / (h * h) +
                   T(1.125) * (m0(lL, lR) + m0(rL, rR)) +
                   T(1.5) * (m1(lL, lR, xi) - m1(rL, rR, xi)) / h +
                   T(0.5) * (m2(lL, lR, xi) + m2(rL, rR, xi)) / (h * h)
        end
    end
    return g
end

# ---------------------------------------------------------------------------
# Coupled (rotated) shape-consistent deposition, docs Section 7.
#
# A tilted Gaussian is not separable in the axis-aligned grid coordinates, but it
# IS separable *conditionally*:
#
#   rho(x,y) = G(x; mux, sigx) * G(y; m(x), s),
#   m(x) = muy + lambda (x - mux),  lambda = sigxy / sigx^2,
#   s^2  = sigy^2 - sigxy^2 / sigx^2      (exact conditional variance)
#
# so the node integral Q_ij = Ns * int G_x W(x-x_i) g(y_j; m(x), s) dx becomes,
# after expanding g in the mean shift about muy,
#
#   Q_ij / Ns = M0_i g_j + lambda M1_i g'_j + (lambda^2/2) M2_i g''_j + O(lambda^3)
#
# with M_k the node-centred x-moments about mux and g', g'' the mean-derivatives
# of the 1D profile. Both derivatives are available in closed form from the same
# erf machinery: integrating by parts, g' = int G W' and g'' = int G W''; for the
# CIC tent W' is +-1/h on the two support cells and W'' is a difference of three
# delta functions, giving
#
#   g'_j  = [ m0(L_j) - m0(R_j) ] / h
#   g''_j = [ G(y_j-h) - 2 G(y_j) + G(y_j+h) ] / h
#
# The result is three separable outer products -- O(Nx+Ny) to build and
# O(Nx*Ny) to subtract, the same order as the uncoupled path -- and is exact
# through second order in the correlation. Any residue is simply left on the grid
# for the Poisson solve, exactly as the control-variate argument intends.
# ---------------------------------------------------------------------------
# Central moments (c_0..c_4) with c_k = int_A^B (x-mu)^k G(x) dx of the
# normalised 1D Gaussian. One integration by parts using (x-mu)G = -s^2 G' gives
#     c_k = -s^2 [ (x-mu)^{k-1} G ]_A^B + (k-1) s^2 c_{k-2},
# seeded by c_0 (erf difference) and c_1 = -s^2 (G(B) - G(A)).
@inline function _gpic_central_moments(A::T, B::T, mu::T, s::T) where {T}
    invroot = inv(s * sqrt(T(2)))
    norm = inv(s * sqrt(2 * T(pi)))
    a = A - mu; b = B - mu
    GA = norm * exp(-(a * a) / (2 * s * s))
    GB = norm * exp(-(b * b) / (2 * s * s))
    s2 = s * s
    c0 = T(0.5) * (erf(b * invroot) - erf(a * invroot))
    c1 = -s2 * (GB - GA)
    c2 = -s2 * (b * GB - a * GA) + s2 * c0
    c3 = -s2 * (b * b * GB - a * a * GA) + 2 * s2 * c1
    c4 = -s2 * (b^3 * GB - a^3 * GA) + 3 * s2 * c2
    return (c0, c1, c2, c3, c4)
end

# Node-centred moments m_k = int (x-xi)^k G over the same cell, from the central
# moments by the binomial shift with d = mu - xi (so x - xi = (x-mu) + d).
@inline function _gpic_shift_moments(c::NTuple{5,T}, d::T) where {T}
    d2 = d * d; d3 = d2 * d; d4 = d3 * d
    return (c[1],
            c[2] + d * c[1],
            c[3] + 2d * c[2] + d2 * c[1],
            c[4] + 3d * c[3] + 3d2 * c[2] + d3 * c[1],
            c[5] + 4d * c[4] + 6d2 * c[3] + 4d3 * c[2] + d4 * c[1])
end

# Assignment-weighted moments W_k = int (x-xi)^k G(x) W(x-xi) dx for k = 0,1,2.
# W_0 reproduces the uncoupled profile of Section 5; W_1 and W_2 are what the
# coupled expansion needs.
function _gpic_weighted_moments(xi::T, h::T, mu::T, s::T, method::Symbol) where {T}
    mom(A, B) = _gpic_shift_moments(_gpic_central_moments(A, B, mu, s), mu - xi)
    if method === :CIC
        L = mom(xi - h, xi); R = mom(xi, xi + h)
        return ((L[1] + L[2] / h) + (R[1] - R[2] / h),
                (L[2] + L[3] / h) + (R[2] - R[3] / h),
                (L[3] + L[4] / h) + (R[3] - R[4] / h))
    end
    half = h / 2
    C = mom(xi - half, xi + half)
    Lw = mom(xi - 3half, xi - half)
    Rw = mom(xi + half, xi + 3half)
    core(M, k) = T(0.75) * M[k + 1] - M[k + 3] / (h * h)
    wing(M, k, sgn) = T(1.125) * M[k + 1] + sgn * T(1.5) * M[k + 2] / h +
                      T(0.5) * M[k + 3] / (h * h)
    return (core(C, 0) + wing(Lw, 0, +1) + wing(Rw, 0, -1),
            core(C, 1) + wing(Lw, 1, +1) + wing(Rw, 1, -1),
            core(C, 2) + wing(Lw, 2, +1) + wing(Rw, 2, -1))
end

# Mean-derivatives of the 1D profile, g' = dg/dmu and g'' = d2g/dmu2. Since
# dG/dmu = -dG/dy, integrating by parts gives g' = int G W' and g'' = int G W''.
# CIC: W' = +-1/h on the two cells; W'' = [d(u+h) - 2d(u) + d(u-h)]/h.
# TSC: W' = -2u/h^2 on the core and -+(3/2 - |u|/h)/h on the wings;
#      W'' = -2/h^2 on the core and +1/h^2 on each wing.
function _gpic_profile_mean_derivs(yj::T, h::T, mu::T, s::T, method::Symbol) where {T}
    invroot = inv(s * sqrt(T(2)))
    norm = inv(s * sqrt(2 * T(pi)))
    pdf(y) = norm * exp(-((y - mu) * (y - mu)) / (2 * s * s))
    m0(A, B) = T(0.5) * (erf((B - mu) * invroot) - erf((A - mu) * invroot))
    if method === :CIC
        dg = (m0(yj - h, yj) - m0(yj, yj + h)) / h
        ddg = (pdf(yj - h) - 2 * pdf(yj) + pdf(yj + h)) / h
        return dg, ddg
    end
    half = h / 2
    mom(A, B) = _gpic_shift_moments(_gpic_central_moments(A, B, mu, s), mu - yj)
    C = mom(yj - half, yj + half)
    Lw = mom(yj - 3half, yj - half)
    Rw = mom(yj + half, yj + 3half)
    # dg/dmu = int G W'; W2' = -2u/h^2 on the core and -+(3/2 -+ u/h)/h on the wings
    dg = -2 * C[2] / (h * h) +
         (T(1.5) * Lw[1] + Lw[2] / h) / h +
         (-T(1.5) * Rw[1] + Rw[2] / h) / h
    ddg = (-2 * m0(yj - half, yj + half) +
           m0(yj - 3half, yj - half) + m0(yj + half, yj + 3half)) / (h * h)
    return dg, ddg
end

function _gpic_coupled_profiles!(gx, m1x, m2x, gy, dgy, ddgy,
                                 x0::T, hx::T, mux::T, sigx::T,
                                 y0::T, hy::T, muy::T, sigc::T,
                                 method::Symbol) where {T}
    @inbounds for i in eachindex(gx)
        xi = x0 + (i - 1) * hx
        W0, W1, W2 = _gpic_weighted_moments(xi, hx, mux, sigx, method)
        d = mux - xi
        gx[i] = W0
        m1x[i] = W1 - d * W0
        m2x[i] = W2 - 2 * d * W1 + d * d * W0
    end
    _gpic_gaussian_profile!(gy, y0, hy, muy, sigc, method)
    @inbounds for j in eachindex(gy)
        yj = y0 + (j - 1) * hy
        dgy[j], ddgy[j] = _gpic_profile_mean_derivs(yj, hy, muy, sigc, method)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Raw transverse moments of the source slice, needed to build the drifted
# reference Gaussian at each field-slice boundary.
# ---------------------------------------------------------------------------
function _gpic_source_moments(source, coupled::Bool=true)
    T = eltype(source.x)
    n = length(source.x)
    x0 = source.x[1]; px0 = source.px[1]
    y0 = source.y[1]; py0 = source.py[1]
    sx = zero(T); spx = zero(T); sy = zero(T); spy = zero(T)
    sxx = zero(T); spxpx = zero(T); syy = zero(T); spypy = zero(T)
    sxpx = zero(T); sypy = zero(T)
    # Cross-plane sums, needed only for the coupled (rotated) subtraction —
    # gated exactly as the CUDA twin gates its 14-vs-10 device slots
    # (2026-08-05_b audit, U10-3): under the default coupling_tol = Inf the
    # coupled branch is unreachable, so accumulating these unconditionally
    # was a measured 33% overhead on this loop the GPU never paid.
    #
    # `coupled` is a RUNTIME Bool, not a Val, and that choice is load-bearing:
    # a Val parameter compiles a second specialization of this loop and of the
    # muladd tail below, and LLVM contracted the shared accumulations into FMA
    # differently in the two — mom.varx came out 1 ulp apart from identical
    # data, which surfaced as 1-ulp kick differences on ~27% of particles
    # between the gated and ungated paths. One instance means one instruction
    # sequence for the shared sums, so gating cannot move a single bit of
    # them; the per-particle branch predicts perfectly (it never changes
    # direction within a slice) and keeps ~all of the measured saving.
    sxy = zero(T); sxpy = zero(T); sypx = zero(T); spxpy = zero(T)
    @inbounds for i in 1:n
        dx = source.x[i] - x0; dpx = source.px[i] - px0
        dy = source.y[i] - y0; dpy = source.py[i] - py0
        sx += dx; spx += dpx; sy += dy; spy += dpy
        sxx += dx * dx; spxpx += dpx * dpx
        syy += dy * dy; spypy += dpy * dpy
        sxpx += dx * dpx; sypy += dy * dpy
        if coupled
            sxy += dx * dy; sxpy += dx * dpy
            sypx += dy * dpx; spxpy += dpx * dpy
        end
    end
    invn = inv(T(n))
    dmx = sx * invn; dmpx = spx * invn; dmy = sy * invn; dmpy = spy * invn
    mx = x0 + dmx; mpx = px0 + dmpx; my = y0 + dmy; mpy = py0 + dmpy
    varx = max(_shifted_second_moment(sxx, dmx, invn), zero(T))
    vary = max(_shifted_second_moment(syy, dmy, invn), zero(T))
    cxpx = _shifted_cross_moment(sxpx, dmx, dmpx, invn)
    varpx = max(_shifted_second_moment(spxpx, dmpx, invn), zero(T))
    cypy = _shifted_cross_moment(sypy, dmy, dmpy, invn)
    varpy = max(_shifted_second_moment(spypy, dmpy, invn), zero(T))
    z = zero(T)
    cxy = coupled ? _shifted_cross_moment(sxy, dmx, dmy, invn) : z
    cxpy = coupled ? _shifted_cross_moment(sxpy, dmx, dmpy, invn) : z
    cypx = coupled ? _shifted_cross_moment(sypx, dmy, dmpx, invn) : z
    cpxpy = coupled ? _shifted_cross_moment(spxpy, dmpx, dmpy, invn) : z
    return (n=n, mx=mx, mpx=mpx, varx=varx, cxpx=cxpx, varpx=varpx,
            my=my, mpy=mpy, vary=vary, cypy=cypy, varpy=varpy,
            cxy=cxy, cxpy=cxpy, cypx=cypx, cpxpy=cpxpy)
end

# Full 4x4 transverse covariance of the source slice as StrongTransverseMoments,
# so the coupled analytic add-back can reuse the validated soft-Gaussian
# `_cp_covariance_kick` (rotated Bassetti-Erskine kick plus the principal-axis
# and rotation-derivative pz terms of docs/theory Section 5).
# Tolerant of moment tuples built without the cross-plane terms (the CUDA
# non-indexed and sequential routes do not compute them, and do not support the
# coupled branch); those degrade to the uncoupled covariance rather than erroring.
@inline function _gpic_coupled_moments(mom)
    T = typeof(mom.mx)
    z = zero(T)
    cxy = hasproperty(mom, :cxy) ? T(mom.cxy) : z
    cxpy = hasproperty(mom, :cxpy) ? T(mom.cxpy) : z
    cypx = hasproperty(mom, :cypx) ? T(mom.cypx) : z
    cpxpy = hasproperty(mom, :cpxpy) ? T(mom.cpxpy) : z
    return StrongTransverseMoments{T,true}(
        mom.varx, cxy, mom.vary,
        mom.cxpx, cxpy, cypx, mom.cypy,
        mom.varpx, cpxpy, mom.varpy)
end

# Transported transverse covariance (a, b, d) = (sigma_x^2, sigma_xy, sigma_y^2)
# of the source slice drifted by +s. `_transport_transverse_moments` uses the
# field-particle convention S = -s, hence the sign.
@inline function _gpic_drifted_covariance(mom, s)
    return _transport_transverse_moments(_gpic_coupled_moments(mom), -s)
end

# Correlation coefficient of the drifted slice; the coupling switch of docs
# Section 7 branches on |r_xy|.
@inline function _gpic_correlation(a, b, d)
    (a <= 0 || d <= 0) && return zero(a)
    return (b / sqrt(a)) / sqrt(d)
end

@inline function _gpic_coupled_covariance_resolved(a, b, d)
    T = promote_type(typeof(a), typeof(b), typeof(d))
    isfinite(a) && isfinite(b) && isfinite(d) &&
        a > zero(T) && d > zero(T) || return false
    rho = T(_gpic_correlation(a, b, d))
    isfinite(rho) || return false
    relative_conditional_variance = muladd(-rho, rho, one(T))
    return relative_conditional_variance > sqrt(eps(T))
end

# Analytic Gaussian longitudinal (covariance-transport) contribution, matching
# the soft-Gaussian _cp_covariance_kick pz term. `rx`, `ry` are the drift
# derivatives d(sigma^2)/ds of the source variances at this boundary; `kbb` is
# the slice-population kick scale (kbb * n_slice).
@inline function _gpic_cov_pz(Hxx, Hyy, rx, ry)
    return (Hxx * rx + Hyy * ry) / 4
end

# Gaussian centroid and RMS of the source slice drifted by longitudinal distance s.
@inline function _gpic_drifted_gaussian(mom, s)
    T = typeof(mom.mx)
    mux = mom.mx + mom.mpx * s
    muy = mom.my + mom.mpy * s
    varx = mom.varx + 2 * s * mom.cxpx + s * s * mom.varpx
    vary = mom.vary + 2 * s * mom.cypy + s * s * mom.varpy
    sigx = sqrt(max(varx, zero(T)))
    sigy = sqrt(max(vary, zero(T)))
    return mux, muy, sigx, sigy
end

@inline function _gpic_boundary(mom, s, coupled::Bool=true)
    mux, muy, sigx, sigy = _gpic_drifted_gaussian(mom, s)
    rx = 2 * (mom.cxpx + s * mom.varpx)
    ry = 2 * (mom.cypy + s * mom.varpy)
    if !coupled
        # Under the caller's gate (coupled ⇔ isfinite(coupling_tol), U10-3)
        # none of the coupled fields are ever read:
        # `_gpic_control_variate_mode` short-circuits on isfinite before
        # touching rxy or coupled_resolved, and a/lam/sigc are consumed only
        # inside the :coupled branch that gate makes unreachable. Zeros keep
        # the tuple shape stable without paying the covariance transport.
        # A runtime Bool, not a Val, for the same reason as
        # `_gpic_source_moments`: a second specialization of this function
        # contracted the drifted-variance polynomial differently and moved
        # sigx by 1 ulp between the gated and ungated paths.
        z = zero(rx)
        return (mux=mux, muy=muy, sigx=sigx, sigy=sigy, rx=rx, ry=ry,
                a=z, b=z, d=z, rxy=z, lam=z, sigc=z,
                coupled_resolved=false)
    end
    a, b, d, _, _, _ = _gpic_drifted_covariance(mom, s)
    rxy = _gpic_correlation(a, b, d)
    resolved = _gpic_coupled_covariance_resolved(a, b, d)
    lam = resolved ? b / a : zero(b)
    relative_conditional_variance =
        resolved ? max(muladd(-rxy, rxy, one(rxy)), zero(rxy)) : zero(rxy)
    sigc = resolved ? sqrt(d * relative_conditional_variance) : zero(d)
    return (mux=mux, muy=muy, sigx=sigx, sigy=sigy, rx=rx, ry=ry,
            a=a, b=b, d=d, rxy=rxy, lam=lam, sigc=sigc,
            coupled_resolved=resolved)
end

@inline function _gpic_control_variate_mode(n::Integer, coupling_tol, bL, bR)
    marginal_resolved =
        n >= 2 &&
        isfinite(bL.sigx) && isfinite(bL.sigy) &&
        isfinite(bR.sigx) && isfinite(bR.sigy) &&
        bL.sigx > 0 && bL.sigy > 0 && bR.sigx > 0 && bR.sigy > 0
    marginal_resolved || return :pic
    coupled_requested = isfinite(coupling_tol) &&
        max(abs(bL.rxy), abs(bR.rxy)) > coupling_tol
    coupled_requested || return :uncoupled
    return bL.coupled_resolved && bR.coupled_resolved ? :coupled : :pic
end

# ---------------------------------------------------------------------------
# Drifted source field solve with Gaussian subtraction: deposit the drifted
# source, subtract the erf-integrated drifted Gaussian, then run the shared
# Green-FFT Poisson solve and finite-difference field.
# ---------------------------------------------------------------------------
function _gpic_solve_drifted_field!(field::_PICFieldWorkspace, pic::PICPoissonSolver,
                                    source, drift_s, source_grid, green_fft, workspace,
                                    mux, muy, sigx, sigy, ns, neutralize,
                                    gxbuf, gybuf)
    nx, ny = pic.grid
    # The grid-side scalar type is the workspace's, not the coordinates': the
    # caller allocates the profile buffers and `workspace.charge` in
    # `promote_type(rep1, rep2, kbb1, kbb2)`, and `_gpic_gaussian_profile!`
    # requires its buffer and scalars to agree. Deriving this from
    # `eltype(source.x)` made every non-Float64 rep a MethodError -- the plain
    # PIC path survives the same beams only because its deposit helpers are
    # generically typed (audit part 7, G1).
    T = eltype(gxbuf)
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    charge = workspace.charge
    fill!(charge, zero(T))
    _pic_deposit_drifted!(charge, pic.deposit_method, source.x, source.px, source.y,
                          source.py, T(drift_s), T(source_grid.x0), T(source_grid.y0),
                          hx, hy, nx, ny, workspace)
    _gpic_gaussian_profile!(gxbuf, T(source_grid.x0), hx, T(mux), T(sigx), pic.deposit_method)
    _gpic_gaussian_profile!(gybuf, T(source_grid.y0), hy, T(muy), T(sigy), pic.deposit_method)
    sgx = sum(gxbuf); sgy = sum(gybuf)
    qsum = zero(T)
    @inbounds for j in 1:ny, i in 1:nx
        qsum += charge[i, j]
    end
    amp = T(ns)
    if neutralize && sgx * sgy > zero(T)
        amp = qsum / (sgx * sgy)
    end
    @inbounds for j in 1:ny
        gj = amp * gybuf[j]
        for i in 1:nx
            charge[i, j] -= gxbuf[i] * gj
        end
    end
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = field.phi
    @inbounds for j in 1:ny, i in 1:nx
        phi[i, j] = real(spectral[i, j])
    end
    _pic_field!(field.Ex, field.Ey, phi, hx, hy, _pic_fourth_order(pic))
    return phi, field.Ex, field.Ey
end

# Coupled variant of the drifted field solve: subtracts the tilted reference
# Gaussian using the three separable outer products of the conditional expansion
# (see _gpic_coupled_profiles!). lambda = sigma_xy/sigma_x^2 and sigc is the
# exact conditional sigma_y.
function _gpic_solve_drifted_field_coupled!(field::_PICFieldWorkspace, pic::PICPoissonSolver,
                                            source, drift_s, source_grid, green_fft, workspace,
                                            mux, muy, sigx, sigc, lambda, ns, neutralize,
                                            gxbuf, m1xbuf, m2xbuf, gybuf, dgybuf, ddgybuf)
    nx, ny = pic.grid
    # Workspace scalar type, for the same reason as _gpic_solve_drifted_field!.
    T = eltype(gxbuf)
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    charge = workspace.charge
    fill!(charge, zero(T))
    _pic_deposit_drifted!(charge, pic.deposit_method, source.x, source.px, source.y,
                          source.py, T(drift_s), T(source_grid.x0), T(source_grid.y0),
                          hx, hy, nx, ny, workspace)
    _gpic_coupled_profiles!(gxbuf, m1xbuf, m2xbuf, gybuf, dgybuf, ddgybuf,
                            T(source_grid.x0), hx, T(mux), T(sigx),
                            T(source_grid.y0), hy, T(muy), T(sigc), pic.deposit_method)
    qsum = zero(T)
    @inbounds for j in 1:ny, i in 1:nx
        qsum += charge[i, j]
    end
    lam = T(lambda); half_lam2 = T(0.5) * lam * lam
    # total mass of the subtracted grid, for the neutralization rescale
    sg = sum(gxbuf) * sum(gybuf) + lam * sum(m1xbuf) * sum(dgybuf) +
         half_lam2 * sum(m2xbuf) * sum(ddgybuf)
    amp = (neutralize && sg != 0) ? qsum / sg : T(ns)
    @inbounds for j in 1:ny
        gj = amp * gybuf[j]; dj = amp * lam * dgybuf[j]; ddj = amp * half_lam2 * ddgybuf[j]
        for i in 1:nx
            charge[i, j] -= gxbuf[i] * gj + m1xbuf[i] * dj + m2xbuf[i] * ddj
        end
    end
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = field.phi
    @inbounds for j in 1:ny, i in 1:nx
        phi[i, j] = real(spectral[i, j])
    end
    _pic_field!(field.Ex, field.Ey, phi, hx, hy, _pic_fourth_order(pic))
    return phi, field.Ex, field.Ey
end

# ---------------------------------------------------------------------------
# One directed slice-pair interaction with Gaussian subtraction. Mirrors
# _pic_interaction! and reuses its grid, Green-cache, and interpolation helpers.
# ---------------------------------------------------------------------------
function _gpic_interaction!(gsolver::GaussianPICPoissonSolver, source, param_source,
                            field, param_field, kbb, workspace::_PICCPUWorkspace,
                            green_cache, cache_key)
    pic = gsolver.pic
    nx, ny = pic.grid
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))
    nsource = length(source.x)
    nfield = length(field.x)

    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))

    # The coupled branch is reachable only when coupling_tol is finite
    # (`_gpic_control_variate_mode` short-circuits on isfinite before reading
    # any cross-plane quantity), so an infinite tolerance skips the four
    # cross-plane sums and the covariance transport entirely — the same gate
    # the CUDA twin applies to its 14-vs-10 device slots (U10-3). Results are
    # bit-identical either way: the gated work was provably unread, and the
    # gate is a runtime Bool so no second specialization exists to contract
    # the shared arithmetic differently.
    coupled_gate = isfinite(T(gsolver.coupling_tol))
    mom = _gpic_source_moments(source, coupled_gate)
    bL = _gpic_boundary(mom, sL, coupled_gate)
    bR = _gpic_boundary(mom, sR, coupled_gate)
    muxL, muyL, sigxL, sigyL = bL.mux, bL.muy, bL.sigx, bL.sigy
    muxR, muyR, sigxR, sigyR = bR.mux, bR.muy, bR.sigx, bR.sigy
    mode = _gpic_control_variate_mode(
        nsource, T(gsolver.coupling_tol), bL, bR)
    mode === :pic &&
        return _pic_interaction!(pic, source, param_source, field, param_field,
                                 kbb, workspace, green_cache, cache_key)
    use_coupled = mode === :coupled

    margin = T(gsolver.margin_sigma)
    # Source extent: union of drifted particle extrema and the Gaussian margin.
    source_xl = source.x[1] + source.px[1] * sL
    source_yl = source.y[1] + source.py[1] * sL
    source_xr = source.x[1] + source.px[1] * sR
    source_yr = source.y[1] + source.py[1] * sR
    source_xmin = min(source_xl, source_xr); source_xmax = max(source_xl, source_xr)
    source_ymin = min(source_yl, source_yr); source_ymax = max(source_yl, source_yr)
    @inbounds for i in 2:nsource
        xl = source.x[i] + source.px[i] * sL
        yl = source.y[i] + source.py[i] * sL
        xr = source.x[i] + source.px[i] * sR
        yr = source.y[i] + source.py[i] * sR
        source_xmin = min(source_xmin, xl, xr); source_xmax = max(source_xmax, xl, xr)
        source_ymin = min(source_ymin, yl, yr); source_ymax = max(source_ymax, yl, yr)
    end
    if margin > 0
        gxlo = min(muxL - margin * sigxL, muxR - margin * sigxR)
        gxhi = max(muxL + margin * sigxL, muxR + margin * sigxR)
        gylo = min(muyL - margin * sigyL, muyR - margin * sigyR)
        gyhi = max(muyL + margin * sigyL, muyR + margin * sigyR)
        source_xmin = min(source_xmin, gxlo); source_xmax = max(source_xmax, gxhi)
        source_ymin = min(source_ymin, gylo); source_ymax = max(source_ymax, gyhi)
    end
    # Non-finite chokepoint (N1, docs/todo.md); see _pic_interaction!.
    all(isfinite, (source_xmin, source_xmax, source_ymin, source_ymax)) ||
        _nonfinite_coordinate_error(:source,
            (x=source.x, px=source.px, y=source.y, py=source.py);
            context=_pic_slice_context(cache_key))

    # Field particles: drift to the collision point (identical to PIC).
    field_xmin = field_xmax = field.x[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.px[1]
    field_ymin = field_ymax = field.y[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.py[1]
    @inbounds for i in 1:nfield
        s = T(0.5) * (field.z[i] - T(param_source.center))
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        if pic.longitudinal_kick
            field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
        end
        field_xmin = min(field_xmin, field.x[i]); field_xmax = max(field_xmax, field.x[i])
        field_ymin = min(field_ymin, field.y[i]); field_ymax = max(field_ymax, field.y[i])
    end
    all(isfinite, (field_xmin, field_xmax, field_ymin, field_ymax)) ||
        _nonfinite_coordinate_error(:field,
            (x=field.x, px=field.px, y=field.y, py=field.py, z=field.z);
            context=_pic_slice_context(cache_key))

    source_grid0, field_grid0 = _pic_interaction_grids(
        pic, source_xmin, source_xmax, source_ymin, source_ymax,
        field_xmin, field_xmax, field_ymin, field_ymax,
    )
    source_bounds = (xmin=source_xmin, xmax=source_xmax, ymin=source_ymin, ymax=source_ymax)
    field_bounds = (xmin=field_xmin, xmax=field_xmax, ymin=field_ymin, ymax=field_ymax)
    source_grid, field_grid, green_fft = _pic_slice_pair_green!(
        workspace, pic, T, green_cache, cache_key, source_grid0, field_grid0,
        source_bounds, field_bounds,
    )

    gxbuf = Vector{T}(undef, nx)
    gybuf = Vector{T}(undef, ny)
    if use_coupled
        m1x = Vector{T}(undef, nx); m2x = Vector{T}(undef, nx)
        dgy = Vector{T}(undef, ny); ddgy = Vector{T}(undef, ny)
        phiL, ExL, EyL = _gpic_solve_drifted_field_coupled!(
            workspace.left, pic, source, sL, source_grid, green_fft, workspace,
            muxL, muyL, sqrt(bL.a), bL.sigc, bL.lam, nsource, gsolver.neutralize,
            gxbuf, m1x, m2x, gybuf, dgy, ddgy)
        phiR, ExR, EyR = _gpic_solve_drifted_field_coupled!(
            workspace.right, pic, source, sR, source_grid, green_fft, workspace,
            muxR, muyR, sqrt(bR.a), bR.sigc, bR.lam, nsource, gsolver.neutralize,
            gxbuf, m1x, m2x, gybuf, dgy, ddgy)
    else
        phiL, ExL, EyL = _gpic_solve_drifted_field!(
            workspace.left, pic, source, sL, source_grid, green_fft, workspace,
            muxL, muyL, sigxL, sigyL, nsource, gsolver.neutralize, gxbuf, gybuf,
        )
        phiR, ExR, EyR = _gpic_solve_drifted_field!(
            workspace.right, pic, source, sR, source_grid, green_fft, workspace,
            muxR, muyR, sigxR, sigyR, nsource, gsolver.neutralize, gxbuf, gybuf,
        )
    end

    kick_scale = T(2) * T(kbb)
    half_ns = T(0.5) * T(nsource)
    kbb_eff = kick_scale * half_ns   # slice-population kick scale = kbb * n_slice
    mpx = mom.mpx; mpy = mom.mpy
    # Drift derivatives d(sigma^2)/ds of the source variances at each boundary,
    # matching the +s deposition convention used to build the reference Gaussian.
    rxL = 2 * (mom.cxpx + sL * mom.varpx); ryL = 2 * (mom.cypy + sL * mom.varpy)
    rxR = 2 * (mom.cxpx + sR * mom.varpx); ryR = 2 * (mom.cypy + sR * mom.varpy)
    cmom = _gpic_coupled_moments(mom)
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    @inbounds for i in 1:nfield
        x = field.x[i]; y = field.y[i]
        zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
        zR = one(T) - zL
        Kx_d, Ky_d, Kz_d = _pic_interpolate_kick(
            pic, field_grid, x, y, phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
        )
        if use_coupled
            # Rotated analytic add-back. Delegating to _cp_covariance_kick reuses
            # the soft-Gaussian principal-axis kick together with its eigenvalue
            # and rotation-derivative pz terms (docs Section 5), which is exactly
            # the coupled longitudinal physics the uncoupled branch cannot form.
            zpx = zero(T); zpy = zero(T); zpz = zero(T)
            _, pxL, _, pyL, _, pzL, _ = _cp_covariance_kick(
                cmom, kbb_eff, -sL, x - muxL, y - muyL, x, zpx, y, zpy, T(0), zpz)
            _, pxR, _, pyR, _, pzR, _ = _cp_covariance_kick(
                cmom, kbb_eff, -sR, x - muxR, y - muyR, x, zpx, y, zpy, T(0), zpz)
            dpx_a = zL * pxL + zR * pxR
            dpy_a = zL * pyL + zR * pyR
            field.px[i] += kick_scale * Kx_d + dpx_a
            field.py[i] += kick_scale * Ky_d + dpy_a
            if pic.longitudinal_kick
                field.pz[i] += kick_scale * Kz_d * hzi
                field.pz[i] += zL * pzL + zR * pzR
                field.pz[i] += T(0.5) * (dpx_a * mpx + dpy_a * mpy)
            end
        else
            if pic.longitudinal_kick
                beLx, beLy, HxxL, HyyL = _gaussian_beambeam_kick_response(
                    kbb_eff, sigxL, sigyL, x - muxL, y - muyL)
                beRx, beRy, HxxR, HyyR = _gaussian_beambeam_kick_response(
                    kbb_eff, sigxR, sigyR, x - muxR, y - muyR)
            else
                beLx, beLy = gaussian_beambeam_kick(
                    sigxL, sigyL, x - muxL, y - muyL)
                beRx, beRy = gaussian_beambeam_kick(
                    sigxR, sigyR, x - muxR, y - muyR)
            end
            Kx_a = half_ns * (zL * beLx + zR * beRx)
            Ky_a = half_ns * (zL * beLy + zR * beRy)
            dpx_a = kick_scale * Kx_a
            dpy_a = kick_scale * Ky_a
            field.px[i] += kick_scale * Kx_d + dpx_a
            field.py[i] += kick_scale * Ky_d + dpy_a
            if pic.longitudinal_kick
                covL = _gpic_cov_pz(HxxL, HyyL, rxL, ryL)
                covR = _gpic_cov_pz(HxxR, HyyR, rxR, ryR)
                field.pz[i] += kick_scale * Kz_d * hzi
                field.pz[i] += zL * covL + zR * covR
                field.pz[i] += T(0.5) * (dpx_a * mpx + dpy_a * mpy)
            end
        end
        s = T(0.5) * (T(param_source.center) - field.z[i])
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        if pic.longitudinal_kick
            field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
        end
    end

    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    vx = Vector{T}(undef, nsource)
    vy = Vector{T}(undef, nsource)
    @inbounds for i in 1:nsource
        vx[i] = source.x[i] + source.px[i] * sM
        vy[i] = source.y[i] + source.py[i] * sM
    end
    return vx, vy
end

# ---------------------------------------------------------------------------
# Collide entry points. The slice loop mirrors _pic_collide! but calls the
# Gaussian-subtracted interaction; everything else (slicing, luminosity,
# green cache, workspace) is the shared PIC infrastructure.
# ---------------------------------------------------------------------------
_gpic_collide!(gsolver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam, ctx,
               workspace::_PICCPUWorkspace, green_cache) =
    _gpic_collide!(gsolver, beam1, beam2, ctx, (workspace,), green_cache)

function _gpic_collide!(gsolver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam, ctx,
                        workspaces, green_cache)
    pic = gsolver.pic
    _validate_pic_solver(pic)
    isempty(workspaces) && throw(ArgumentError(
        "GaussianPIC CPU collide needs at least one scratch workspace; got an empty pool."))
    _require_linear_slice_interpolation(pic, "GaussianPICPoissonSolver")
    # Reset and report the dropped-charge counter, as the plain-PIC twin does
    # (2026-08-05_b audit, U10-2). This solver shares `_PICCPUWorkspace` and
    # calls into `_pic_interaction!`, which increments `workspace.dropped[]`,
    # but never zeroed it and never reported it -- so a stale count from a
    # previous collide could persist and a real one would go unmentioned. The
    # channel is unreachable today only because the hybrid rejects every
    # non-:extrema `grid_extent`; this is the missing guardrail, not an active
    # loss, and it costs one store.
    for ws in workspaces
        ws.dropped[] = 0
    end
    slices1 = longitudinal_slices(beam1.rep, pic.slicing1)
    slices2 = longitudinal_slices(beam2.rep, pic.slicing2)
    kbb1 = _pic_kbb1(pic, beam1, beam2)
    kbb2 = _pic_kbb2(pic, beam1, beam2)
    klum = _pic_luminosity_scale(pic, beam1, beam2)
    compute_luminosity = _pic_compute_luminosity(pic, ctx)
    T = promote_type(eltype(beam1.rep.x), eltype(beam2.rep.x), typeof(kbb1), typeof(kbb2))
    # N7: the luminosity estimate returns Float64 everywhere (see pic_cpu.jl).
    LT = Float64

    # Same schedule, fold and receipts as `_pic_collide!`; see the reasoning
    # there. gpic is the simpler case: it REJECTS `interaction_grid` as inert
    # (`_GPIC_INERT_PIC_OPTIONS`), so the `:source_slice` union mesh that keeps
    # plain PIC sequential cannot arise here, and `_pic_batchable` is consulted
    # anyway rather than assumed.
    order = _slice_collision_order(slices1, slices2)
    npairs = length(order)
    pair_pos = Dict{Tuple{Int,Int},Int}()
    sizehint!(pair_pos, npairs)
    for (p, entry) in pairs(order)
        pair_pos[(entry[2], entry[3])] = p
    end
    lum_parts = zeros(LT, npairs)
    ran = fill(false, npairs)      # Vector{Bool}, not BitVector: see _pic_collide!

    if _pic_batchable(pic) && length(workspaces) > 1 && npairs > 1
        inner_workers = max(1, fld(_cpu_worker_count(), length(workspaces)))
        batches = collision_pair_batches(slices1, slices2)
        _record_execution!(:cpu_pic_pair_schedule, CPUThreadsBackend,
                           (schedule=:batched, pairs=npairs, batches=length(batches),
                            widest_batch=maximum(length, batches; init=0),
                            pair_workers=length(workspaces),
                            inner_workers=inner_workers))
        Base.ScopedValues.with(_PIC_MAP_WORKER_BUDGET => inner_workers) do
        for batch in batches
            nworkers = clamp(length(workspaces), 1, length(batch))
            # `chunk_ws`, NOT `ws` -- the sequential branch below assigns `ws`
            # at function scope, and sharing the name boxes it into one
            # workspace for every worker. See `_pic_collide!`.
            _run_logical_workers(nworkers) do chunk, _
                chunk_ws = workspaces[chunk]
                lo, hi = _chunk_bounds(length(batch), nworkers, chunk)
                for pos in lo:hi
                    pr = batch[pos]
                    p = pair_pos[(pr.i, pr.j)]
                    ran[p] = _gpic_collide_pair!(
                        lum_parts, p, gsolver, beam1, beam2, slices1, slices2,
                        pr.i, pr.j, chunk_ws, green_cache, kbb1, kbb2, klum,
                        compute_luminosity)
                end
            end
        end
        end
    else
        _record_execution!(:cpu_pic_pair_schedule, CPUThreadsBackend,
                           (schedule=:sequential, pairs=npairs, batches=0,
                            widest_batch=0, pair_workers=1,
                            inner_workers=_cpu_worker_count()))
        serial_ws = first(workspaces)
        for (p, entry) in pairs(order)
            ran[p] = _gpic_collide_pair!(
                lum_parts, p, gsolver, beam1, beam2, slices1, slices2,
                entry[2], entry[3], serial_ws, green_cache, kbb1, kbb2, klum,
                compute_luminosity)
        end
    end

    luminosity = LT(NaN)
    if compute_luminosity
        luminosity = zero(LT)
        sink = _ACTIVE_PIC_LUMINOSITY_PAIR_SINK[]
        turn = ctx === nothing ? -1 : ctx.turn
        for p in 1:npairs
            @inbounds ran[p] || continue
            @inbounds luminosity += lum_parts[p]
            sink === nothing || push!(sink, (
                turn=turn, i=Int(order[p][2]), j=Int(order[p][3]),
                luminosity=Float64(lum_parts[p]),
            ))
        end
    end
    _pic_report_green_cache(green_cache)
    _pic_report_dropped(workspaces)         # U10-2, summed over the pool
    return luminosity
end

"""
One Gaussian-subtracted slice-pair collision; the `_pic_collide_pair!` twin.

Returns whether the pair ran, and writes its luminosity into `lum_parts[p]` at
the pair's position in the COLLISION order so the fold stays independent of the
schedule.
"""
function _gpic_collide_pair!(lum_parts, p::Int, gsolver::GaussianPICPoissonSolver,
                             beam1::Beam, beam2::Beam, slices1, slices2,
                             i::Int, j::Int, workspace::_PICCPUWorkspace,
                             green_cache, kbb1, kbb2, klum,
                             compute_luminosity::Bool)
    idx1 = slices1.indices[i]
    idx2 = slices2.indices[j]
    (isempty(idx1) || isempty(idx2)) && return false
    param1 = (weight=slices1.weight[i], lb=slices1.boundary[i],
              center=slices1.center[i], rb=slices1.boundary[i + 1])
    param2 = (weight=slices2.weight[j], lb=slices2.boundary[j],
              center=slices2.center[j], rb=slices2.boundary[j + 1])
    coord1 = _pic_extract_slice(beam1.rep, idx1)
    coord2 = _pic_extract_slice(beam2.rep, idx2)
    field1 = _pic_copy_coords(coord1)
    field2 = _pic_copy_coords(coord2)
    vx1, vy1 = _gpic_interaction!(
        gsolver, coord1, param1, field2, param2, kbb2, workspace, green_cache, (i, j, 1),
    )
    vx2, vy2 = _gpic_interaction!(
        gsolver, coord2, param2, field1, param1, kbb1, workspace, green_cache, (i, j, 2),
    )
    _pic_store_slice!(beam1.rep, idx1, field1)
    _pic_store_slice!(beam2.rep, idx2, field2)
    if compute_luminosity
        @inbounds lum_parts[p] = _pic_luminosity(
            gsolver.pic, vx1, vy1, vx2, vy2, klum, workspace)
    end
    return true
end

function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                  ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end

# Split on the context type rather than leaving it untyped, as pic_cpu.jl and
# spectral.jl already do. An untyped `ctx` here was ambiguous against the
# generic `collide!(::AbstractPoissonSolver, ..., ::TrackingContext)` in
# interface.jl -- this method is more specific in the solver and backend, that
# one in the context, so neither dominates. The task path dispatches through
# `_strong_strong_collide_backend!` and never reached it, so the ambiguity sat
# unexercised until a caller used the documented five-argument form directly.
function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                  backend::Type{CPUThreadsBackend}, ctx::Nothing)
    return _gpic_collide_fresh!(solver, beam1, beam2, ctx)
end

function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                  backend::Type{CPUThreadsBackend}, ctx::TrackingContext)
    return _gpic_collide_fresh!(solver, beam1, beam2, ctx)
end

function _gpic_collide_fresh!(solver::GaussianPICPoissonSolver, beam1::Beam,
                              beam2::Beam, ctx)
    T = _pic_cpu_scalar_type(solver.pic, beam1, beam2)
    nx, ny = solver.pic.grid
    workspaces = [_pic_cpu_workspace(T, nx, ny) for _ in 1:_pic_pool_size(solver.pic)]
    green_cache = _pic_green_cache(solver.pic, T)
    return _gpic_collide!(solver, beam1, beam2, ctx, workspaces, green_cache)
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::GaussianPICPoissonSolver,
                                 beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                 ctx::TrackingContext)
    T = _pic_cpu_scalar_type(solver.pic, beam1, beam2)
    workspaces = _pic_cpu_workspace_pool!(task.runtime_cache, label, solver.pic, T,
                                          _pic_pool_size(solver.pic))
    green_cache = _pic_green_cache!(task.runtime_cache, label, solver.pic, T)
    return _gpic_collide!(solver, beam1, beam2, ctx, workspaces, green_cache)
end

_strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                solver::GaussianPICPoissonSolver,
                                beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                ctx::TrackingContext) =
    _strong_strong_collide!(task, label, solver, beam1, beam2, CPUThreadsBackend, ctx)

# The CUDA path is defined in gaussian_pic_cuda.jl (only when CUDA is available).
