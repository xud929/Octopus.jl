export SpectralPoissonSolver

#=
Spectral sine-series 2D Poisson strong-strong collision solver. The transverse
potential of each source slice is expanded in the Dirichlet eigenfunctions
sin(l*pi*x/a) sin(m*pi*y/b) on a rectangular box, so the Poisson solve is one
division per mode, phi_lm = -kbb * rho_lm / (alpha_l^2 + beta_m^2). See
docs/spectral_sine_poisson_solver.md.

This is the CPU implementation. The grid variant deposits the source slice, takes
a 2D DST, solves per mode, differentiates on the mesh with the exact spectral
derivative (DST + zero-padded DCT), and interpolates the field to the field-slice
particles. The grid-free variant forms the mode coefficients directly from the
source particles and evaluates the field analytically. Both apply a thin
transverse kick per slice pair (no longitudinal synchro-beam kick yet).
=#

# Field scale that turns the raw DST/DCT field into the per-unit-charge
# Bassetti-Erskine field (the source deposit is normalized to unit total charge
# in the field solve, so the caller applies the physical kbb * slice_weight
# exactly as GaussianPoissonSolver does). The two variants have different scale
# structure: the grid path assembles the field from the deposit/DST and its scale
# grows with the mode count (folding in the DST inverse-normalization
# 1/(4(Nx+1)(Ny+1))), while the grid-free path evaluates the already-converged
# direct mode sum, whose scale is a mode-count-independent constant. Each carries
# its own pinned constant, fixed by a least-squares fit of the field onto the
# analytic normalized kick over a converged (large-count) round-beam sample; the
# domain-independence of the per-mode basis makes both box-size independent (see
# docs Section 17).
const _SPECTRAL_FIELD_C0_GRID = -25.72
const _SPECTRAL_FIELD_C0_FREE = 12.518

struct SpectralPoissonSolver{T<:Real} <: AbstractPoissonSolver
    kbb1::Union{Nothing,T}
    kbb2::Union{Nothing,T}
    luminosity_scale::Union{Nothing,T}
    grid::Tuple{Int,Int}
    domain_factor::T
    method::Symbol
    slicing::LongitudinalSlicing
    slicing1::LongitudinalSlicing
    slicing2::LongitudinalSlicing
    requested_slicing1::Union{Nothing,LongitudinalSlicing}
    requested_slicing2::Union{Nothing,LongitudinalSlicing}
end

"""
    SpectralPoissonSolver(; kbb1=nothing, kbb2=nothing, luminosity_scale=nothing,
                           grid=(128, 128), domain_factor=16.0, method=:grid,
                           slicing=LongitudinalSlicing(), slicing1=nothing,
                           slicing2=nothing)

Spectral sine-series strong-strong collision solver on a rectangular domain with
homogeneous Dirichlet boundaries (a large-box approximation to open boundary
conditions). `grid=(Nx, Ny)` sets the mesh and mode counts; use an anisotropic
grid for flat beams (`Ny ~ 5 * domain_factor * sigma_x/sigma_y`). `domain_factor`
sets the box half-width as a multiple of the larger transverse rms. `method` is
`:grid` (DST/DCT, the fast path) or `:grid_free` (mode sums straight from
particles). `kbb1`/`kbb2` are the physical kick scales, same convention as
`GaussianPoissonSolver` and `PICPoissonSolver`.
"""
function SpectralPoissonSolver{T}(; kbb1=nothing, kbb2=nothing,
                                  luminosity_scale=nothing,
                                  grid=(128, 128), domain_factor=16.0,
                                  method::Symbol=:grid,
                                  slicing::LongitudinalSlicing=LongitudinalSlicing(),
                                  slicing1=nothing, slicing2=nothing) where {T<:Real}
    s1 = slicing1 === nothing ? slicing : slicing1
    s2 = slicing2 === nothing ? slicing : slicing2
    gx, gy = Int(grid[1]), Int(grid[2])
    (gx >= 8 && gy >= 8) || throw(ArgumentError("SpectralPoissonSolver grid dimensions must be at least 8; got $(grid)"))
    domain_factor > 0 || throw(ArgumentError("domain_factor must be positive; got $(domain_factor)"))
    method in (:grid, :grid_free) || throw(ArgumentError("method must be :grid or :grid_free; got $(repr(method))"))
    return SpectralPoissonSolver{T}(
        _optional_solver_value(T, kbb1), _optional_solver_value(T, kbb2),
        _optional_solver_value(T, luminosity_scale), (gx, gy), T(domain_factor), method,
        slicing, s1, s2, slicing1, slicing2)
end

SpectralPoissonSolver(; kwargs...) = SpectralPoissonSolver{Float64}(; kwargs...)

const _SPECTRAL_SOLVER_OPTION_SCHEMA = (
    kbb1 = SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional physical beam-1 kick-scale override."; category=:physics_override),
    kbb2 = SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional physical beam-2 kick-scale override."; category=:physics_override),
    luminosity_scale = SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional luminosity normalization override."; category=:physics_override),
    grid = SolverOptionMeta(Tuple{Int,Int}, (128, 128),
        "Transverse sine-mode mesh (Nx, Ny); use anisotropic for flat beams."),
    domain_factor = SolverOptionMeta(Real, 16.0,
        "Box half-width as a multiple of the larger transverse rms."; category=:accuracy_performance),
    method = SolverOptionMeta(Symbol, :grid,
        "Field-solve variant; :grid (DST/DCT) or :grid_free (direct mode sums)."; category=:performance),
    slicing = SolverOptionMeta(LongitudinalSlicing, LongitudinalSlicing(),
        "Shared longitudinal slicing configuration."; category=:physics),
    slicing1 = SolverOptionMeta(Union{Nothing,LongitudinalSlicing}, nothing,
        "Optional beam-1 slicing override."; category=:physics, dependencies=(:slicing,)),
    slicing2 = SolverOptionMeta(Union{Nothing,LongitudinalSlicing}, nothing,
        "Optional beam-2 slicing override."; category=:physics, dependencies=(:slicing,)),
)
solver_option_schema(::Type{<:SpectralPoissonSolver}) = _SPECTRAL_SOLVER_OPTION_SCHEMA

function solver_configuration(solver::SpectralPoissonSolver)
    configured = _solver_configured_values(solver)
    return merge(configured, (
        slicing1=solver.requested_slicing1, slicing2=solver.requested_slicing2,
        resolved_slicing1=solver.slicing1, resolved_slicing2=solver.slicing2,
    ))
end

# Physical kbb / luminosity, identical convention to GaussianPoissonSolver. The
# source deposit is normalized to unit charge inside the field solve, so the field
# is the per-unit-charge (normalized) Bassetti-Erskine field and the physical
# kbb * slice_weight is applied by the caller exactly as in the Gaussian path.
_spectral_kbb1(solver, beam1, beam2) = _strong_strong_kbb1(solver, beam1, beam2)
_spectral_kbb2(solver, beam1, beam2) = _strong_strong_kbb2(solver, beam1, beam2)

# --- field solve for one directed interaction: source (sx,sy) -> field (fx,fy) ---
# Returns per-field-particle (Ex, Ey) already scaled to the physical BE per-unit-
# charge convention (kbb applied by the caller).
function _spectral_cosderiv(A, d)
    N = size(A, d)
    if d == 1
        P = vcat(zeros(1, size(A, 2)), A, zeros(1, size(A, 2)))
        return (FFTW.r2r(P, FFTW.REDFT00, 1) ./ 2)[2:N + 1, :]
    else
        P = hcat(zeros(size(A, 1), 1), A, zeros(size(A, 1), 1))
        return (FFTW.r2r(P, FFTW.REDFT00, 2) ./ 2)[:, 2:N + 1]
    end
end

function _spectral_field_grid(sx, sy, fx, fy, Lx, Ly, Nx, Ny)
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    ns = length(sx)
    rho = zeros(Nx, Ny)
    @inbounds for p in eachindex(sx)
        X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += cx * cy)
        end
    end
    # Normalize the deposit to unit total charge so the field is the per-unit-
    # charge (normalized-Gaussian) field, matching the analytic Bassetti-Erskine
    # convention used by GaussianPoissonSolver (kbb * slice_weight applied later).
    ns > 0 && (rho ./= ns)
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    rholm = FFTW.r2r(rho, FFTW.RODFT00) ./ (a * b)
    philm = [-rholm[l, m] / (al[l]^2 + bm[m]^2) for l in 1:Nx, m in 1:Ny]
    scale = _SPECTRAL_FIELD_C0_GRID * Nx * Ny / (2 * (Nx + 1) * 2 * (Ny + 1))
    Exg = -scale .* _spectral_cosderiv(al .* FFTW.r2r(philm, FFTW.RODFT00, 2), 1)
    Eyg = -scale .* _spectral_cosderiv(FFTW.r2r(philm, FFTW.RODFT00, 1) .* transpose(bm), 2)
    nf = length(fx); Ex = Vector{Float64}(undef, nf); Ey = Vector{Float64}(undef, nf)
    @inbounds for k in 1:nf
        X = (fx[k] + Lx) / hx; Y = (fy[k] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        ex = 0.0; ey = 0.0
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            if 1 <= ii <= Nx && 1 <= jj <= Ny
                ex += cx * cy * Exg[ii, jj]; ey += cx * cy * Eyg[ii, jj]
            end
        end
        Ex[k] = ex; Ey[k] = ey
    end
    return Ex, Ey
end

function _spectral_field_free(sx, sy, fx, fy, Lx, Ly, Nx, Ny)
    a = 2Lx; b = 2Ly; ns = length(sx)
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    sS = Matrix{Float64}(undef, Nx, ns); sC = Matrix{Float64}(undef, Ny, ns)
    @inbounds for p in 1:ns
        xs = sx[p] + Lx; ys = sy[p] + Ly
        for l in 1:Nx; sS[l, p] = sin(al[l] * xs); end
        for m in 1:Ny; sC[m, p] = sin(bm[m] * ys); end
    end
    invns = ns > 0 ? 1.0 / ns : 1.0
    philm = Matrix{Float64}(undef, Nx, Ny)
    @inbounds for l in 1:Nx, m in 1:Ny
        s = 0.0
        for p in 1:ns; s += sS[l, p] * sC[m, p]; end
        # invns normalizes the source to unit total charge (see _spectral_field_grid).
        philm[l, m] = -(4 / (a * b)) * (s * invns) / (al[l]^2 + bm[m]^2)
    end
    scale = _SPECTRAL_FIELD_C0_FREE  # mode-count independent (direct sum is converged)
    nf = length(fx); Ex = Vector{Float64}(undef, nf); Ey = Vector{Float64}(undef, nf)
    @inbounds for k in 1:nf
        X = fx[k] + Lx; Y = fy[k] + Ly; ex = 0.0; ey = 0.0
        for l in 1:Nx
            cX = cos(al[l] * X); sX = sin(al[l] * X)
            for m in 1:Ny
                ex += philm[l, m] * al[l] * cX * sin(bm[m] * Y)
                ey += philm[l, m] * bm[m] * sX * cos(bm[m] * Y)
            end
        end
        Ex[k] = -scale * (-ex); Ey[k] = -scale * (-ey)
    end
    return Ex, Ey
end

_spectral_field(solver::SpectralPoissonSolver, sx, sy, fx, fy, Lx, Ly) =
    solver.method === :grid_free ?
        _spectral_field_free(sx, sy, fx, fy, Lx, Ly, solver.grid...) :
        _spectral_field_grid(sx, sy, fx, fy, Lx, Ly, solver.grid...)

function _spectral_box(solver::SpectralPoissonSolver, x1, y1, x2, y2)
    rms(v) = begin m = sum(v) / length(v); sqrt(sum(abs2, v .- m) / length(v)) end
    d = solver.domain_factor
    ext(v) = maximum(abs, v)
    # A flat beam's transverse field extends on the scale of the LARGER rms in
    # BOTH directions, so the Dirichlet box must be square and sized to sigma_max.
    # An anisotropic box (Ly ~ d*sigma_y) clips the wide field and biases the
    # kick by ~10% at 5:1; the thin direction is resolved by the grid (Ny), not a
    # smaller box. See docs/spectral_sine_poisson_solver.md.
    smax = max(rms(x1), rms(x2), rms(y1), rms(y2))
    emax = max(ext(x1), ext(x2), ext(y1), ext(y2))
    L = max(d * smax, 1.05 * emax)
    return L, L
end

function collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end
collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend}, ::Nothing) =
    _spectral_collide!(solver, beam1, beam2)
collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend}, ::TrackingContext) =
    _spectral_collide!(solver, beam1, beam2)

function _spectral_collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _spectral_kbb1(solver, beam1, beam2)
    kbb2 = _spectral_kbb2(solver, beam1, beam2)
    klum1, klum2 = _strong_strong_luminosity_scales(solver, beam1, beam2)
    r1 = beam1.rep; r2 = beam2.rep
    luminosity = zero(eltype(r1.x))
    Lx, Ly = _spectral_box(solver, r1.x, r1.y, r2.x, r2.y)
    for (_, i, j) in _slice_collision_order(slices1, slices2)
        idx1 = slices1.indices[i]; idx2 = slices2.indices[j]
        (isempty(idx1) || isempty(idx2)) && continue
        sx1 = @view r1.x[idx1]; sy1 = @view r1.y[idx1]
        sx2 = @view r2.x[idx2]; sy2 = @view r2.y[idx2]
        # beam1 sources -> kick beam2 field particles (weighted by beam1 slice weight)
        ex2, ey2 = _spectral_field(solver, sx1, sy1, sx2, sy2, Lx, Ly)
        w1 = slices1.weight[i] * kbb2
        @inbounds for (t, p) in enumerate(idx2)
            r2.px[p] += w1 * ex2[t]; r2.py[p] += w1 * ey2[t]
        end
        # beam2 sources -> kick beam1 field particles
        ex1, ey1 = _spectral_field(solver, sx2, sy2, sx1, sy1, Lx, Ly)
        w2 = slices2.weight[j] * kbb1
        @inbounds for (t, p) in enumerate(idx1)
            r1.px[p] += w2 * ex1[t]; r1.py[p] += w2 * ey1[t]
        end
        # WIP placeholder luminosity (density-overlap integral not yet implemented);
        # klum scale kept consistent with the Gaussian/PIC convention.
        luminosity += slices1.weight[i] * slices2.weight[j] * klum1
    end
    return luminosity
end
