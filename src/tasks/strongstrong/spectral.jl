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
source particles and evaluates the field analytically. The default collision
uses the same synchro-beam virtual-drift and longitudinal potential-difference
structure as the PIC path; `longitudinal_kick=false` retains the original
transverse-only map for comparisons.
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
    longitudinal_kick::Bool
    slicing::LongitudinalSlicing
    slicing1::LongitudinalSlicing
    slicing2::LongitudinalSlicing
    requested_slicing1::Union{Nothing,LongitudinalSlicing}
    requested_slicing2::Union{Nothing,LongitudinalSlicing}
end

"""
    SpectralPoissonSolver(; kbb1=nothing, kbb2=nothing, luminosity_scale=nothing,
                           grid=(128, 128), domain_factor=16.0, method=:grid,
                           longitudinal_kick=true,
                           slicing=LongitudinalSlicing(), slicing1=nothing,
                           slicing2=nothing)

Spectral sine-series strong-strong collision solver on a rectangular domain with
homogeneous Dirichlet boundaries (a large-box approximation to open boundary
conditions). The meaning of `grid=(Nx, Ny)` depends on `method`: for
`method=:grid`, it is both the number of interior mesh points and the retained
sine-mode count in each transverse direction; for `method=:grid_free`, no mesh is
constructed, and the same tuple means direct sine-mode counts `Nx` and `Ny`.
Use an anisotropic `grid` for flat beams
(`Ny ~ 5 * domain_factor * sigma_x/sigma_y`). `domain_factor` sets the box
half-width as a multiple of the larger transverse rms (the box is square — sized
to the larger rms in both directions — because a flat beam's field extends on
that scale in both). `method` is `:grid` (DST/DCT, the fast path, and the only
CUDA-supported variant) or `:grid_free` (mode sums straight from particles; CPU
only). `kbb1`/`kbb2` are the physical kick scales, same convention as
`GaussianPoissonSolver` and `PICPoissonSolver`.

`longitudinal_kick=true` applies the Hirata-map synchro-beam drift and
potential-difference `pz` kick. Set it to `false` for the original
transverse-only spectral map.

For the production ~11:1 flat beams the recommended grid is `grid=(127, 383)` with
`domain_factor=8`, which reproduces the PIC/analytic kick to ~1% (the graininess
floor) on both beams in x/y/z. The odd sizes are intentional: a grid dimension `N`
gives a DST/DCT extension of length `2(N+1)`, so `N=2^k-1` makes that a power of
two and the CUDA real-FFT optimal. `(128, 1024)/16` also works but is heavily
over-resolved and ~6x slower on GPU. See
`validation/strong_strong_spectral_optimization_history.md`. Runs on both
`CPUThreadsBackend` (parallel over field slices) and `CUDABackend`; the optimized
CUDA 6D grid path is ~1.24x the PIC one-turn time at ~1e6 particles/beam (down from
6x, comparable to PIC).
"""
function SpectralPoissonSolver{T}(; kbb1=nothing, kbb2=nothing,
                                  luminosity_scale=nothing,
                                  grid=(128, 128), domain_factor=16.0,
                                  method::Symbol=:grid,
                                  longitudinal_kick::Bool=true,
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
        Bool(longitudinal_kick), slicing, s1, s2, slicing1, slicing2)
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
        "Transverse shape (Nx, Ny): grid nodes and modes for :grid, modes only for :grid_free."),
    domain_factor = SolverOptionMeta(Real, 16.0,
        "Box half-width as a multiple of the larger transverse rms."; category=:accuracy_performance),
    method = SolverOptionMeta(Symbol, :grid,
        "Field-solve variant; :grid (DST/DCT) or :grid_free (direct mode sums)."; category=:performance),
    longitudinal_kick = SolverOptionMeta(Bool, true,
        "Apply the synchro-beam virtual drift and potential-difference pz kick."; category=:physics),
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

# Density-overlap luminosity scale, identical to PICPoissonSolver: divides by both
# macroparticle counts (a grid overlap of the two deposited slices carries both
# 1/nmacro factors).
function _spectral_luminosity_scale(solver, beam1, beam2)
    solver.luminosity_scale !== nothing && return solver.luminosity_scale
    return beam1.params.npart * beam2.params.npart /
           (length(beam1.rep) * length(beam2.rep))
end

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

# --- cached grid workspace (reusable buffers + FFTW plans) --------------------
# The allocating _spectral_field_grid below is the reference; production reuses
# this workspace across all slice-pair field solves to avoid ~18 MiB/solve of GC
# pressure. Plans are keyed by (Nx, Ny); the mode arrays al/bm and the diagonal
# mode-Green G = 1/(al^2+bm^2) are recomputed only when the box (a, b) changes.
mutable struct _SpectralGridWS
    Nx::Int; Ny::Int
    a::Float64; b::Float64
    al::Vector{Float64}; bm::Vector{Float64}; G::Matrix{Float64}
    rho::Matrix{Float64}; rholm::Matrix{Float64}; philm::Matrix{Float64}
    tmp::Matrix{Float64}                    # directional DST of philm
    padx::Matrix{Float64}; cosx::Matrix{Float64}   # (Nx+2) x Ny
    pady::Matrix{Float64}; cosy::Matrix{Float64}   # Nx x (Ny+2)
    Phig::Matrix{Float64}
    Exg::Matrix{Float64}; Eyg::Matrix{Float64}
    prho::FFTW.r2rFFTWPlan          # RODFT00 both dims
    prow::FFTW.r2rFFTWPlan          # RODFT00 dim 2
    pcol::FFTW.r2rFFTWPlan          # RODFT00 dim 1
    pcosx::FFTW.r2rFFTWPlan         # REDFT00 dim 1 on padx
    pcosy::FFTW.r2rFFTWPlan         # REDFT00 dim 2 on pady
end

function _SpectralGridWS(Nx::Int, Ny::Int)
    rho = zeros(Nx, Ny); rholm = zeros(Nx, Ny); philm = zeros(Nx, Ny)
    tmp = zeros(Nx, Ny); Phig = zeros(Nx, Ny); Exg = zeros(Nx, Ny); Eyg = zeros(Nx, Ny)
    padx = zeros(Nx + 2, Ny); cosx = zeros(Nx + 2, Ny)
    pady = zeros(Nx, Ny + 2); cosy = zeros(Nx, Ny + 2)
    prho = FFTW.plan_r2r(rho, FFTW.RODFT00)
    prow = FFTW.plan_r2r(philm, FFTW.RODFT00, 2)
    pcol = FFTW.plan_r2r(philm, FFTW.RODFT00, 1)
    pcosx = FFTW.plan_r2r(padx, FFTW.REDFT00, 1)
    pcosy = FFTW.plan_r2r(pady, FFTW.REDFT00, 2)
    return _SpectralGridWS(Nx, Ny, NaN, NaN, zeros(Nx), zeros(Ny), zeros(Nx, Ny),
        rho, rholm, philm, tmp, padx, cosx, pady, cosy, Phig, Exg, Eyg,
        prho, prow, pcol, pcosx, pcosy)
end

# Per-worker workspace pool: the collision parallelizes over field slices, so each
# logical worker needs its own buffers/plans. Cached by (Nx, Ny) and grown to the
# requested worker count on demand.
const _SPECTRAL_WS_CACHE = Dict{Tuple{Int,Int},Vector{_SpectralGridWS}}()
const _SPECTRAL_WS_LOCK = ReentrantLock()

function _spectral_grid_ws_pool(Nx::Int, Ny::Int, nworkers::Int)
    lock(_SPECTRAL_WS_LOCK) do
        pool = get!(() -> _SpectralGridWS[], _SPECTRAL_WS_CACHE, (Nx, Ny))
        while length(pool) < nworkers
            push!(pool, _SpectralGridWS(Nx, Ny))
        end
        return pool
    end
end

_spectral_grid_ws(Nx::Int, Ny::Int) = _spectral_grid_ws_pool(Nx, Ny, 1)[1]

# Refresh mode arrays / mode-Green only when the box changed.
function _spectral_ws_setbox!(ws::_SpectralGridWS, a::Float64, b::Float64)
    (ws.a == a && ws.b == b) && return ws
    Nx, Ny = ws.Nx, ws.Ny
    @inbounds for l in 1:Nx; ws.al[l] = l * pi / a; end
    @inbounds for m in 1:Ny; ws.bm[m] = m * pi / b; end
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.G[l, m] = 1.0 / (ws.al[l]^2 + ws.bm[m]^2)
    end
    ws.a = a; ws.b = b
    return ws
end

function _spectral_field_grid!(ws::_SpectralGridWS, sx, sy, fx, fy, Lx, Ly)
    Nx, Ny = ws.Nx, ws.Ny
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    ns = length(sx)
    _spectral_ws_setbox!(ws, a, b)
    rho = ws.rho; fill!(rho, 0.0)
    @inbounds for p in eachindex(sx)
        X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += cx * cy)
        end
    end
    # rholm = DST(rho) / (a*b*ns); philm = -rholm * G
    mul!(ws.rholm, ws.prho, rho)
    invn = ns > 0 ? 1.0 / (a * b * ns) : 1.0 / (a * b)
    @inbounds for k in eachindex(ws.philm)
        ws.philm[k] = -(ws.rholm[k] * invn) * ws.G[k]
    end
    scale = _SPECTRAL_FIELD_C0_GRID * Nx * Ny / (2 * (Nx + 1) * 2 * (Ny + 1))
    # Ex = -scale * ddx( DST_y(philm) ), spectral x-derivative via padded DCT-I
    mul!(ws.tmp, ws.prow, ws.philm)
    fill!(ws.padx, 0.0)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.padx[l + 1, m] = ws.al[l] * ws.tmp[l, m]
    end
    mul!(ws.cosx, ws.pcosx, ws.padx)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.Exg[l, m] = -scale * (ws.cosx[l + 1, m] / 2)
    end
    # Ey = -scale * ddy( DST_x(philm) )
    mul!(ws.tmp, ws.pcol, ws.philm)
    fill!(ws.pady, 0.0)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.pady[l, m + 1] = ws.tmp[l, m] * ws.bm[m]
    end
    mul!(ws.cosy, ws.pcosy, ws.pady)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.Eyg[l, m] = -scale * (ws.cosy[l, m + 1] / 2)
    end
    nf = length(fx); Ex = Vector{Float64}(undef, nf); Ey = Vector{Float64}(undef, nf)
    Exg = ws.Exg; Eyg = ws.Eyg
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

function _spectral_field_grid_potential!(ws::_SpectralGridWS, sx, sy, fx, fy, Lx, Ly)
    Nx, Ny = ws.Nx, ws.Ny
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    ns = length(sx)
    _spectral_ws_setbox!(ws, a, b)
    rho = ws.rho; fill!(rho, 0.0)
    @inbounds for p in eachindex(sx)
        X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += cx * cy)
        end
    end
    mul!(ws.rholm, ws.prho, rho)
    invn = ns > 0 ? 1.0 / (a * b * ns) : 1.0 / (a * b)
    @inbounds for k in eachindex(ws.philm)
        ws.philm[k] = -(ws.rholm[k] * invn) * ws.G[k]
    end
    scale = _SPECTRAL_FIELD_C0_GRID * Nx * Ny / (2 * (Nx + 1) * 2 * (Ny + 1))

    # Potential on the mesh (phi = 0 at the Dirichlet boundary). The 2D DST
    # reconstruction carries a factor 4 (FFTW RODFT00 is 2x per dimension), while
    # each field component carries only a factor 2 (one DST + one padded DCT whose
    # explicit /2 nets to 1x on the derivative dimension). To keep phi consistent
    # with E = -grad(phi) at the shared `scale`, the potential needs an extra 1/2.
    mul!(ws.tmp, ws.prho, ws.philm)
    @inbounds for k in eachindex(ws.Phig)
        ws.Phig[k] = 0.5 * scale * ws.tmp[k]
    end

    # Ex = -scale * ddx( DST_y(philm) ), spectral x-derivative via padded DCT-I
    mul!(ws.tmp, ws.prow, ws.philm)
    fill!(ws.padx, 0.0)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.padx[l + 1, m] = ws.al[l] * ws.tmp[l, m]
    end
    mul!(ws.cosx, ws.pcosx, ws.padx)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.Exg[l, m] = -scale * (ws.cosx[l + 1, m] / 2)
    end
    # Ey = -scale * ddy( DST_x(philm) )
    mul!(ws.tmp, ws.pcol, ws.philm)
    fill!(ws.pady, 0.0)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.pady[l, m + 1] = ws.tmp[l, m] * ws.bm[m]
    end
    mul!(ws.cosy, ws.pcosy, ws.pady)
    @inbounds for m in 1:Ny, l in 1:Nx
        ws.Eyg[l, m] = -scale * (ws.cosy[l, m + 1] / 2)
    end
    nf = length(fx)
    Phi = Vector{Float64}(undef, nf)
    Ex = Vector{Float64}(undef, nf)
    Ey = Vector{Float64}(undef, nf)
    Phig = ws.Phig; Exg = ws.Exg; Eyg = ws.Eyg
    @inbounds for k in 1:nf
        X = (fx[k] + Lx) / hx; Y = (fy[k] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        phi = 0.0; ex = 0.0; ey = 0.0
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            if 1 <= ii <= Nx && 1 <= jj <= Ny
                c = cx * cy
                phi += c * Phig[ii, jj]
                ex += c * Exg[ii, jj]
                ey += c * Eyg[ii, jj]
            end
        end
        Phi[k] = phi; Ex[k] = ex; Ey[k] = ey
    end
    return Phi, Ex, Ey
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

function _spectral_mode_sincos(coords, Lbox, Nmodes; need_cos::Bool)
    n = length(coords)
    S = Matrix{Float64}(undef, n, Nmodes)
    C = need_cos ? Matrix{Float64}(undef, n, Nmodes) : Matrix{Float64}(undef, 0, 0)
    inva = inv(2Lbox)
    @inbounds for p in 1:n
        theta = pi * (coords[p] + Lbox) * inva
        s1, c1 = sincos(theta)
        sm2 = 0.0
        sm1 = s1
        cm2 = 1.0
        cm1 = c1
        for l in 1:Nmodes
            if l == 1
                s = sm1
                c = cm1
            else
                s = 2c1 * sm1 - sm2
                c = 2c1 * cm1 - cm2
                sm2, sm1 = sm1, s
                cm2, cm1 = cm1, c
            end
            S[p, l] = s
            need_cos && (C[p, l] = c)
        end
    end
    return S, C
end

function _spectral_field_free_potential(sx, sy, fx, fy, Lx, Ly, Nx, Ny)
    a = 2Lx; b = 2Ly; ns = length(sx)
    al = [l * pi / a for l in 1:Nx]
    bm = [m * pi / b for m in 1:Ny]
    sX, _ = _spectral_mode_sincos(sx, Lx, Nx; need_cos=false)
    sY, _ = _spectral_mode_sincos(sy, Ly, Ny; need_cos=false)
    rho_modes = transpose(sX) * sY
    invns = ns > 0 ? 1.0 / ns : 1.0
    philm = Matrix{Float64}(undef, Nx, Ny)
    @inbounds for m in 1:Ny, l in 1:Nx
        # invns normalizes the source to unit total charge (see _spectral_field_grid).
        philm[l, m] = -(4 / (a * b)) * (rho_modes[l, m] * invns) /
            (al[l]^2 + bm[m]^2)
    end
    fSinX, fCosX = _spectral_mode_sincos(fx, Lx, Nx; need_cos=true)
    fSinY, fCosY = _spectral_mode_sincos(fy, Ly, Ny; need_cos=true)

    nf = length(fx)
    Phi = Vector{Float64}(undef, nf)
    Ex = Vector{Float64}(undef, nf)
    Ey = Vector{Float64}(undef, nf)
    tmp = fSinX * philm
    scale = _SPECTRAL_FIELD_C0_FREE  # mode-count independent (direct sum is converged)
    @inbounds for k in 1:nf
        phi = 0.0
        for m in 1:Ny
            phi += tmp[k, m] * fSinY[k, m]
        end
        Phi[k] = -scale * phi
    end

    ex_modes = similar(philm)
    ey_modes = similar(philm)
    @inbounds for m in 1:Ny, l in 1:Nx
        ex_modes[l, m] = al[l] * philm[l, m]
        ey_modes[l, m] = bm[m] * philm[l, m]
    end
    tmp = fCosX * ex_modes
    @inbounds for k in 1:nf
        ex = 0.0
        for m in 1:Ny
            ex += tmp[k, m] * fSinY[k, m]
        end
        Ex[k] = scale * ex
    end
    tmp = fSinX * ey_modes
    @inbounds for k in 1:nf
        ey = 0.0
        for m in 1:Ny
            ey += tmp[k, m] * fCosY[k, m]
        end
        Ey[k] = scale * ey
    end
    return Phi, Ex, Ey
end

function _spectral_field_free(sx, sy, fx, fy, Lx, Ly, Nx, Ny)
    _, Ex, Ey = _spectral_field_free_potential(sx, sy, fx, fy, Lx, Ly, Nx, Ny)
    return Ex, Ey
end

# Transverse density-overlap luminosity for one slice pair, mirroring the PIC
# convention (CIC deposit of both slices on a shared grid, summed product times
# klum / cell-area). The spectral and PIC luminosity therefore agree for the same
# beams up to deposition detail, giving a direct cross-check.
function _spectral_luminosity_pair(x1, y1, x2, y2, klum, nx, ny)
    T = promote_type(eltype(x1), eltype(x2), typeof(klum))
    xmin = min(minimum(x1), minimum(x2)); xmax = max(maximum(x1), maximum(x2))
    ymin = min(minimum(y1), minimum(y2)); ymax = max(maximum(y1), maximum(y2))
    width = max(T(xmax - xmin), eps(T)); height = max(T(ymax - ymin), eps(T))
    tx = width / T(nx - 1.1); ty = height / T(ny - 1.1)
    width += T(0.1) * tx; height += T(0.1) * ty
    xmin -= T(0.05) * tx; ymin -= T(0.05) * ty
    hx = width / (nx - 1); hy = height / (ny - 1)
    q1 = zeros(T, nx, ny); q2 = zeros(T, nx, ny)
    _spectral_cic_deposit!(q1, x1, y1, xmin, ymin, hx, hy)
    _spectral_cic_deposit!(q2, x2, y2, xmin, ymin, hx, hy)
    lum = zero(T)
    @inbounds for k in eachindex(q1); lum += q1[k] * q2[k]; end
    return lum * T(klum) / (hx * hy)
end

function _spectral_cic_deposit!(q, x, y, x0, y0, hx, hy)
    nx, ny = size(q)
    @inbounds for p in eachindex(x)
        X = (x[p] - x0) / hx + 1; Y = (y[p] - y0) / hy + 1
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= nx && 1 <= jj <= ny) && (q[ii, jj] += cx * cy)
        end
    end
    return q
end

# Field for one directed interaction using a caller-supplied workspace (grid) or
# the allocating grid-free path. `ws` is ignored for :grid_free.
function _spectral_field_ws(solver::SpectralPoissonSolver, ws, sx, sy, fx, fy, Lx, Ly)
    solver.method === :grid_free &&
        return _spectral_field_free(sx, sy, fx, fy, Lx, Ly, solver.grid...)
    return _spectral_field_grid!(ws, sx, sy, fx, fy, Lx, Ly)
end

function _spectral_field_potential_ws(solver::SpectralPoissonSolver, ws, sx, sy, fx, fy, Lx, Ly)
    solver.method === :grid_free &&
        return _spectral_field_free_potential(sx, sy, fx, fy, Lx, Ly, solver.grid...)
    return _spectral_field_grid_potential!(ws, sx, sy, fx, fy, Lx, Ly)
end

function _spectral_field(solver::SpectralPoissonSolver, sx, sy, fx, fy, Lx, Ly)
    ws = solver.method === :grid_free ? nothing :
         _spectral_grid_ws(solver.grid[1], solver.grid[2])
    return _spectral_field_ws(solver, ws, sx, sy, fx, fy, Lx, Ly)
end

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

function _spectral_drifted_source(source, drift_s, ::Type{T}) where {T}
    n = length(source.x)
    x = Vector{T}(undef, n)
    y = Vector{T}(undef, n)
    @inbounds for i in 1:n
        x[i] = T(source.x[i]) + T(source.px[i]) * T(drift_s)
        y[i] = T(source.y[i]) + T(source.py[i]) * T(drift_s)
    end
    return x, y
end

function _spectral_midpoint_source(source, param_source, param_field, ::Type{T}) where {T}
    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    n = length(source.x)
    x = Vector{T}(undef, n)
    y = Vector{T}(undef, n)
    @inbounds for i in 1:n
        x[i] = T(source.x[i]) + T(source.px[i]) * sM
        y[i] = T(source.y[i]) + T(source.py[i]) * sM
    end
    return x, y
end

function _spectral_interaction!(solver::SpectralPoissonSolver, source, param_source,
                                field, param_field, kbb_slice, ws, Lx, Ly)
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb_slice))
    nfield = length(field.x)
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    sxL, syL = _spectral_drifted_source(source, sL, T)
    sxR, syR = _spectral_drifted_source(source, sR, T)

    @inbounds for i in 1:nfield
        s = T(0.5) * (T(field.z[i]) - T(param_source.center))
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
    end

    phiL, ExL, EyL = _spectral_field_potential_ws(solver, ws, sxL, syL, field.x, field.y, Lx, Ly)
    phiR, ExR, EyR = _spectral_field_potential_ws(solver, ws, sxR, syR, field.x, field.y, Lx, Ly)

    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    kick_scale = T(kbb_slice)
    @inbounds for i in 1:nfield
        zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
        zR = one(T) - zL
        Kx = zL * ExL[i] + zR * ExR[i]
        Ky = zL * EyL[i] + zR * EyR[i]
        Kz = phiL[i] - phiR[i]
        field.px[i] += kick_scale * Kx
        field.py[i] += kick_scale * Ky
        field.pz[i] += kick_scale * Kz * hzi
        s = T(0.5) * (T(param_source.center) - T(field.z[i]))
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
    end

    return _spectral_midpoint_source(source, param_source, param_field, T)
end

function collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end
collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend}, ::Nothing) =
    _spectral_collide!(solver, beam1, beam2)
collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend}, ::TrackingContext) =
    _spectral_collide!(solver, beam1, beam2)

# The transverse-only collision reads original positions and only accumulates
# px/py, so slice-pair order is irrelevant (addition is commutative). We therefore
# parallelize over FIELD slices: each worker owns a disjoint set of field slices
# and accumulates the kick from every source slice, so writes never collide.
# Direction 1 (kick beam2) also accumulates the density-overlap luminosity.
function _spectral_collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
    return solver.longitudinal_kick ?
        _spectral_collide_longitudinal!(solver, beam1, beam2) :
        _spectral_collide_transverse!(solver, beam1, beam2)
end

function _spectral_collide_transverse!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _spectral_kbb1(solver, beam1, beam2)
    kbb2 = _spectral_kbb2(solver, beam1, beam2)
    # Density-overlap luminosity uses the PIC scale npart1*npart2/(nmacro1*nmacro2)
    # (the Gaussian's klum divides by only nmacro1 because its per-particle kick sum
    # supplies the other factor; a grid overlap needs both).
    klum = _spectral_luminosity_scale(solver, beam1, beam2)
    lnx, lny = solver.grid
    r1 = beam1.rep; r2 = beam2.rep
    T = eltype(r1.x)
    idx1 = slices1.indices; idx2 = slices2.indices
    w1 = slices1.weight; w2 = slices2.weight
    n1 = length(idx1); n2 = length(idx2)
    Lx, Ly = _spectral_box(solver, r1.x, r1.y, r2.x, r2.y)
    grid = solver.method !== :grid_free
    nchunks = clamp(_cpu_worker_count(), 1, max(n1, n2))
    pool = grid ? _spectral_grid_ws_pool(solver.grid[1], solver.grid[2], nchunks) : nothing

    # Direction 1: beam1 sources -> kick beam2 field slices (parallel over j).
    lum_parts = zeros(T, nchunks)
    _run_logical_workers(nchunks) do chunk, _
        ws = grid ? pool[chunk] : nothing
        jlo, jhi = _chunk_bounds(n2, nchunks, chunk)
        lp = zero(T)
        for j in jlo:jhi
            jdx = idx2[j]; isempty(jdx) && continue
            fx = @view r2.x[jdx]; fy = @view r2.y[jdx]
            for i in 1:n1
                sdx = idx1[i]; isempty(sdx) && continue
                sx = @view r1.x[sdx]; sy = @view r1.y[sdx]
                ex, ey = _spectral_field_ws(solver, ws, sx, sy, fx, fy, Lx, Ly)
                a = w1[i] * kbb2
                @inbounds for (t, p) in enumerate(jdx)
                    r2.px[p] += a * ex[t]; r2.py[p] += a * ey[t]
                end
                lp += _spectral_luminosity_pair(sx, sy, fx, fy, klum, lnx, lny)
            end
        end
        lum_parts[chunk] = lp
    end

    # Direction 2: beam2 sources -> kick beam1 field slices (parallel over i).
    _run_logical_workers(nchunks) do chunk, _
        ws = grid ? pool[chunk] : nothing
        ilo, ihi = _chunk_bounds(n1, nchunks, chunk)
        for i in ilo:ihi
            fdx = idx1[i]; isempty(fdx) && continue
            fx = @view r1.x[fdx]; fy = @view r1.y[fdx]
            for j in 1:n2
                sdx = idx2[j]; isempty(sdx) && continue
                sx = @view r2.x[sdx]; sy = @view r2.y[sdx]
                ex, ey = _spectral_field_ws(solver, ws, sx, sy, fx, fy, Lx, Ly)
                a = w2[j] * kbb1
                @inbounds for (t, p) in enumerate(fdx)
                    r1.px[p] += a * ex[t]; r1.py[p] += a * ey[t]
                end
            end
        end
    end
    return sum(lum_parts)
end

function _spectral_collide_longitudinal!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _spectral_kbb1(solver, beam1, beam2)
    kbb2 = _spectral_kbb2(solver, beam1, beam2)
    klum = _spectral_luminosity_scale(solver, beam1, beam2)
    lnx, lny = solver.grid
    Lx, Ly = _spectral_box(solver, beam1.rep.x, beam1.rep.y, beam2.rep.x, beam2.rep.y)
    luminosity = zero(promote_type(eltype(beam1.rep.x), eltype(beam2.rep.x), typeof(klum)))
    grid = solver.method !== :grid_free
    batches = collision_pair_batches(slices1, slices2)
    max_workers = clamp(_cpu_worker_count(), 1, max(1, maximum(length, batches; init=1)))
    pool = grid ? _spectral_grid_ws_pool(solver.grid[1], solver.grid[2], max_workers) : nothing

    for batch in batches
        nworkers = clamp(max_workers, 1, length(batch))
        lum_parts = zeros(typeof(luminosity), nworkers)
        _run_logical_workers(nworkers) do chunk, _
            ws = grid ? pool[chunk] : nothing
            lo, hi = _chunk_bounds(length(batch), nworkers, chunk)
            local_lum = zero(typeof(luminosity))
            for pos in lo:hi
                pair = batch[pos]
                i = pair.i; j = pair.j
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
                vx1, vy1 = _spectral_interaction!(
                    solver, coord1, param1, field2, param2, slices1.weight[i] * kbb2, ws, Lx, Ly)
                vx2, vy2 = _spectral_interaction!(
                    solver, coord2, param2, field1, param1, slices2.weight[j] * kbb1, ws, Lx, Ly)
                _pic_store_slice!(beam1.rep, idx1, field1)
                _pic_store_slice!(beam2.rep, idx2, field2)
                local_lum += _spectral_luminosity_pair(vx1, vy1, vx2, vy2, klum, lnx, lny)
            end
            lum_parts[chunk] = local_lum
        end
        luminosity += sum(lum_parts)
    end
    return luminosity
end
