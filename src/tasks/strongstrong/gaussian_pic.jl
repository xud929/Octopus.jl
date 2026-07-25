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

The solver composes a `PICPoissonSolver`: all PIC keywords (`grid`,
`deposit_method`, `green_type`, `green_cache`, `longitudinal_kick`, `slicing`,
`kbb1`/`kbb2`, `luminosity_scale`, the CUDA execution options, ...) are forwarded
to it unchanged, so `?PICPoissonSolver` documents them. The additional options
are:

- `margin_sigma`: minimum adaptive-box half-width, in beam sigmas, for containing
  the subtracted Gaussian (its tails extend beyond the particle cloud). `0`
  keeps the ordinary particle-wrapping box.
- `neutralize`: rescale the subtracted Gaussian grid so its total matches the
  deposited particles, removing the spurious open-boundary monopole.
- `coupling_tol`: correlation-coefficient threshold
  `|sigma_xy/(sigma_x*sigma_y)|` above which the coupled (rotated) subtraction
  would be used. The coupled branch is **not implemented**, so only the default
  `Inf` (always uncoupled) is accepted; a finite value throws rather than being
  silently ignored. The residual grid absorbs any transverse coupling.

CPU and CUDA are supported and CPU/CUDA bit-parity; the CUDA path defaults to the
indexed wavefront route (see `gaussian_pic_cuda.jl`).
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
    # The coupled (rotated) subtraction of docs Section 7 is not implemented, so a
    # finite threshold would silently do nothing. Reject it rather than accept a
    # non-default request that has no runtime consumer.
    isinf(ct) || throw(ArgumentError(
        "coupling_tol=$(coupling_tol) requests the coupled (rotated) Gaussian " *
        "subtraction, which is not implemented; only Inf (always-uncoupled) is " *
        "currently supported. See docs/theory/gaussian_subtracted_pic_solver.md Section 7."))
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
        "Correlation-coefficient threshold |sigma_xy/(sigma_x*sigma_y)| above which the coupled (rotated) subtraction is used; Inf always uses the separable uncoupled subtraction.";
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

function configuration_report(solver::GaussianPICPoissonSolver;
                              policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                              backend=nothing)
    pic_entries = configuration_report(solver.pic; policy=policy, backend=backend)
    extras = ConfigurationEntry[]
    push!(extras, ConfigurationEntry(:margin_sigma, solver.margin_sigma, solver.margin_sigma,
        :resolved, "adaptive-box Gaussian containment margin in sigmas", :gaussian_pic_subtraction))
    push!(extras, ConfigurationEntry(:neutralize, solver.neutralize, solver.neutralize,
        :resolved, "discrete charge neutralization of the subtracted Gaussian", :gaussian_pic_subtraction))
    # Only Inf is constructible today (the coupled branch is unimplemented), so the
    # option is reported as an inactive dependency rather than a resolved value.
    push!(extras, ConfigurationEntry(:coupling_tol, solver.coupling_tol, solver.coupling_tol,
        :inactive_dependency,
        "always-uncoupled separable subtraction; the coupled (rotated) branch is not implemented",
        :gaussian_pic_subtraction))
    return (pic_entries..., Tuple(extras)...)
end

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
# Raw transverse moments of the source slice, needed to build the drifted
# reference Gaussian at each field-slice boundary.
# ---------------------------------------------------------------------------
function _gpic_source_moments(source)
    T = eltype(source.x)
    n = length(source.x)
    sx = zero(T); spx = zero(T); sy = zero(T); spy = zero(T)
    sxx = zero(T); spxpx = zero(T); syy = zero(T); spypy = zero(T)
    sxpx = zero(T); sypy = zero(T)
    @inbounds for i in 1:n
        xi = source.x[i]; pxi = source.px[i]; yi = source.y[i]; pyi = source.py[i]
        sx += xi; spx += pxi; sy += yi; spy += pyi
        sxx += xi * xi; spxpx += pxi * pxi; syy += yi * yi; spypy += pyi * pyi
        sxpx += xi * pxi; sypy += yi * pyi
    end
    invn = inv(T(n))
    mx = sx * invn; mpx = spx * invn; my = sy * invn; mpy = spy * invn
    varx = max(sxx * invn - mx * mx, zero(T))
    vary = max(syy * invn - my * my, zero(T))
    cxpx = sxpx * invn - mx * mpx
    varpx = max(spxpx * invn - mpx * mpx, zero(T))
    cypy = sypy * invn - my * mpy
    varpy = max(spypy * invn - mpy * mpy, zero(T))
    return (n=n, mx=mx, mpx=mpx, varx=varx, cxpx=cxpx, varpx=varpx,
            my=my, mpy=mpy, vary=vary, cypy=cypy, varpy=varpy)
end

# Analytic Gaussian longitudinal (covariance-transport) contribution, matching
# the soft-Gaussian _cp_covariance_kick pz term. `rx`, `ry` are the drift
# derivatives d(sigma^2)/ds of the source variances at this boundary; `kbb` is
# the slice-population kick scale (kbb * n_slice).
@inline function _gpic_cov_pz(kbb, sigx, sigy, xx, yy, Kx, Ky, rx, ry)
    expterm = exp(-(xx * xx / (sigx * sigx) + yy * yy / (sigy * sigy)) / 2)
    dsize = abs(sigx - sigy) / 2
    msize = (sigx + sigy) / 2
    if dsize / msize < ROUND_BEAM_THRESHOLD
        Hxx, _, Hyy = _round_gaussian_hessian(kbb, msize, xx, yy, expterm)
    else
        Hxx, Hyy = _elliptic_gaussian_hessian_diagonal(kbb, sigx, sigy, xx, yy, Kx, Ky, expterm)
    end
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
    T = eltype(source.x)
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
    _pic_field!(field.Ex, field.Ey, phi, hx, hy)
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

    mom = _gpic_source_moments(source)
    muxL, muyL, sigxL, sigyL = _gpic_drifted_gaussian(mom, sL)
    muxR, muyR, sigxR, sigyR = _gpic_drifted_gaussian(mom, sR)
    # Fall back to plain PIC for degenerate slices where the reference Gaussian
    # is undefined (single particle or zero transverse spread at a boundary).
    do_gauss = nsource >= 2 && sigxL > 0 && sigyL > 0 && sigxR > 0 && sigyR > 0
    do_gauss || return _pic_interaction!(pic, source, param_source, field, param_field,
                                         kbb, workspace, green_cache, cache_key)

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
    phiL, ExL, EyL = _gpic_solve_drifted_field!(
        workspace.left, pic, source, sL, source_grid, green_fft, workspace,
        muxL, muyL, sigxL, sigyL, nsource, gsolver.neutralize, gxbuf, gybuf,
    )
    phiR, ExR, EyR = _gpic_solve_drifted_field!(
        workspace.right, pic, source, sR, source_grid, green_fft, workspace,
        muxR, muyR, sigxR, sigyR, nsource, gsolver.neutralize, gxbuf, gybuf,
    )

    kick_scale = T(2) * T(kbb)
    half_ns = T(0.5) * T(nsource)
    kbb_eff = kick_scale * half_ns   # slice-population kick scale = kbb * n_slice
    mpx = mom.mpx; mpy = mom.mpy
    # Drift derivatives d(sigma^2)/ds of the source variances at each boundary,
    # matching the +s deposition convention used to build the reference Gaussian.
    rxL = 2 * (mom.cxpx + sL * mom.varpx); ryL = 2 * (mom.cypy + sL * mom.varpy)
    rxR = 2 * (mom.cxpx + sR * mom.varpx); ryR = 2 * (mom.cypy + sR * mom.varpy)
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    @inbounds for i in 1:nfield
        x = field.x[i]; y = field.y[i]
        zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
        zR = one(T) - zL
        Kx_d, Ky_d, Kz_d = _pic_interpolate_kick(
            pic, field_grid, x, y, phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
        )
        beLx, beLy = gaussian_beambeam_kick(sigxL, sigyL, x - muxL, y - muyL)
        beRx, beRy = gaussian_beambeam_kick(sigxR, sigyR, x - muxR, y - muyR)
        Kx_a = half_ns * (zL * beLx + zR * beRx)
        Ky_a = half_ns * (zL * beLy + zR * beRy)
        dpx_a = kick_scale * Kx_a
        dpy_a = kick_scale * Ky_a
        field.px[i] += kick_scale * Kx_d + dpx_a
        field.py[i] += kick_scale * Ky_d + dpy_a
        if pic.longitudinal_kick
            covL = _gpic_cov_pz(kbb_eff, sigxL, sigyL, x - muxL, y - muyL, beLx, beLy, rxL, ryL)
            covR = _gpic_cov_pz(kbb_eff, sigxR, sigyR, x - muxR, y - muyR, beRx, beRy, rxR, ryR)
            field.pz[i] += kick_scale * Kz_d * hzi
            field.pz[i] += zL * covL + zR * covR
            field.pz[i] += T(0.5) * (dpx_a * mpx + dpy_a * mpy)
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
function _gpic_collide!(gsolver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam, ctx,
                        workspace::_PICCPUWorkspace, green_cache)
    pic = gsolver.pic
    _validate_pic_solver(pic)
    slices1 = longitudinal_slices(beam1.rep, pic.slicing1)
    slices2 = longitudinal_slices(beam2.rep, pic.slicing2)
    kbb1 = _pic_kbb1(pic, beam1, beam2)
    kbb2 = _pic_kbb2(pic, beam1, beam2)
    klum = _pic_luminosity_scale(pic, beam1, beam2)
    compute_luminosity = _pic_compute_luminosity(pic, ctx)
    T = promote_type(eltype(beam1.rep.x), eltype(beam2.rep.x), typeof(kbb1), typeof(kbb2))
    luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : T(NaN)
    for (_, i, j) in _slice_collision_order(slices1, slices2)
        idx1 = slices1.indices[i]
        idx2 = slices2.indices[j]
        (isempty(idx1) || isempty(idx2)) && continue
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
            pair_luminosity = _pic_luminosity(pic, vx1, vy1, vx2, vy2, klum, workspace)
            luminosity += pair_luminosity
            sink = _ACTIVE_PIC_LUMINOSITY_PAIR_SINK[]
            sink === nothing || push!(sink, (
                turn=ctx === nothing ? -1 : ctx.turn, i=Int(i), j=Int(j),
                luminosity=Float64(pair_luminosity),
            ))
        end
    end
    _pic_report_green_cache(green_cache)
    return luminosity
end

function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                  ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end

function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                  ::Type{CPUThreadsBackend}, ctx)
    T = _pic_cpu_scalar_type(solver.pic, beam1, beam2)
    nx, ny = solver.pic.grid
    workspace = _pic_cpu_workspace(T, nx, ny)
    green_cache = _pic_green_cache(solver.pic, T)
    return _gpic_collide!(solver, beam1, beam2, ctx, workspace, green_cache)
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::GaussianPICPoissonSolver,
                                 beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                 ctx::TrackingContext)
    T = _pic_cpu_scalar_type(solver.pic, beam1, beam2)
    workspace = _pic_cpu_workspace!(task.runtime_cache, label, solver.pic, T)
    green_cache = _pic_green_cache!(task.runtime_cache, label, solver.pic, T)
    return _gpic_collide!(solver, beam1, beam2, ctx, workspace, green_cache)
end

_strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                solver::GaussianPICPoissonSolver,
                                beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                ctx::TrackingContext) =
    _strong_strong_collide!(task, label, solver, beam1, beam2, CPUThreadsBackend, ctx)

# The CUDA path is defined in gaussian_pic_cuda.jl (only when CUDA is available).
