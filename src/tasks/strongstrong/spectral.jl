"""
    _grid_floor(X)

Floor a normalized grid coordinate to an index, or return an index guaranteed to
fail every bounds check.

`floor(Int, X)` throws an `InexactError` for a non-finite `X`, and overflows for
a finite one large enough to leave `Int` range -- and the conversion happens
*before* the `1 <= i <= Nx` guards below it, so those guards cannot save it. The
range test is written so that `NaN` takes the reject branch, every comparison
against it being false, and `_GRID_REJECT` is far enough from `typemin` that
`i + 1` and `i + 2` cannot overflow.

This is the same contract `_pic_cic_weights` states for deposition: a particle
with no valid cell contributes nothing rather than crashing the solver. It is
what lets an aperture write NaN without taking the spectral path down with it.
"""
const _GRID_REJECT = typemin(Int) >> 2
@inline _grid_floor(X) = (-1e15 < X < 1e15) ? floor(Int, X) : _GRID_REJECT

export SpectralPoissonSolver

#=
Spectral sine-series 2D Poisson strong-strong collision solver. The transverse
potential of each source slice is expanded in the Dirichlet eigenfunctions
sin(l*pi*x/a) sin(m*pi*y/b) on a rectangular box, so the Poisson solve is one
division per mode, phi_lm = -kbb * rho_lm / (alpha_l^2 + beta_m^2). See
docs/theory/spectral_sine_poisson_solver.md.

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
# exactly as GaussianPoissonSolver does). Both constants are DERIVED, not fitted,
# and are therefore exactly grid- and box-independent:
#
#   philm = -rho_lm / (al^2 + bm^2) is the continuum coefficient of the potential
#   solving lap(phi) = rho for a unit-charge source, so phi = ln(r)/(2*pi) and
#   E = -grad(phi) = -r_hat/(2*pi*r) far from the source. The Bassetti-Erskine
#   kick this must reproduce is K = 2*r_hat/r per unit population, i.e. K = -4*pi*E.
#
#   :grid       FFTW RODFT00/REDFT00 each carry a factor 2, so the reconstructed
#               Exg = -scale * (cosx/2) equals 2*scale*E; matching -4*pi*E gives
#               scale = -2*pi.
#   :grid_free  the direct mode sum yields Ex = scale * dphi/dx = -scale*E;
#               matching -4*pi*E gives scale = +4*pi.
#
# Verified numerically: the least-squares scale needed to match the exact
# Bassetti-Erskine field converges to these values as the mesh is refined and the
# Dirichlet box is enlarged (-6.2869 at (1024,1024)/d=24 versus -2*pi = -6.28319).
# The previous fitted constants (-25.72 and 12.518 with a spurious
# Nx*Ny/((Nx+1)(Ny+1)) factor on the grid path) made the beam-beam coupling depend
# on the mesh, so refining the grid did not converge to the correct force.
const _SPECTRAL_FIELD_SCALE_GRID = -2 * pi
const _SPECTRAL_FIELD_SCALE_FREE = 4 * pi

struct SpectralPoissonSolver{T<:Real} <: AbstractPoissonSolver
    kbb1::Union{Nothing,T}
    kbb2::Union{Nothing,T}
    luminosity_scale::Union{Nothing,T}
    grid::Tuple{Int,Int}
    domain_factor::T
    min_domain_halfwidth::T
    method::Symbol
    longitudinal_kick::Bool
    field_precision::Symbol
    luminosity_schedule::Union{Nothing,AbstractSchedule}
    slicing::LongitudinalSlicing
    slicing1::LongitudinalSlicing
    slicing2::LongitudinalSlicing
    requested_slicing1::Union{Nothing,LongitudinalSlicing}
    requested_slicing2::Union{Nothing,LongitudinalSlicing}
end

"""
    SpectralPoissonSolver(; kbb1=nothing, kbb2=nothing, luminosity_scale=nothing,
                           grid=(128, 128), domain_factor=16.0,
                           min_domain_halfwidth=0.0, method=:grid,
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
that scale in both). `min_domain_halfwidth` is an optional physical lower bound
on that square half-width, in the same length units as the particle coordinates.
Its default `0` leaves every nonzero domain data-derived. A beam collapsed at the
origin has no inferable physical scale and is rejected unless this bound is
positive. `method` is `:grid` (DST/DCT, the fast path, and the only CUDA-supported
variant) or `:grid_free` (mode sums straight from particles; CPU only).
`kbb1`/`kbb2` are the physical kick scales, same convention as
`GaussianPoissonSolver` and `PICPoissonSolver`.

`longitudinal_kick=true` applies the Hirata-map synchro-beam drift and
potential-difference `pz` kick. Set it to `false` for the original
transverse-only spectral map.

`luminosity_schedule` may be `nothing` or a schedule such as
`EveryNSteps(step=10)` or `AtTurns([0, 100])`, with the same convention as
`PICPoissonSolver`: `nothing` evaluates luminosity every turn; when the schedule
does not run, the beam-beam kicks are still applied and the returned luminosity is
`NaN` to mark that it was intentionally not computed, and those turns leave no
row in the artifact's luminosity channel. Luminosity is a separate density-overlap
deposit for this solver (~11% of a turn at the recommended production grid), so
scheduling it is a real saving, unlike for `GaussianPoissonSolver` where the
luminosity is a by-product of the kick and costs nothing.

`field_precision` selects the CUDA field-solve precision: `:double` (default,
bit-parity with the CPU path) or `:single`, which runs the deposit/transform/field
reconstruction in `Float32` while keeping particle coordinates in `Float64`. The
field is smooth, so `:single` keeps the kick accurate to ~1e-6 (far under the ~1%
physics floor) and greatly speeds the FFTs on GPUs with weak `Float64` throughput;
it is not bit-parity with the CPU path and is not intended for production. The CPU
path always uses `Float64`.

For the production ~11:1 flat beams the recommended grid is `grid=(127, 383)` with
`domain_factor=8`, which reproduces the PIC/analytic kick to ~1% (the graininess
floor) on both beams in x/y/z. The odd sizes are intentional: a grid dimension `N`
gives a DST/DCT extension of length `2(N+1)`, so `N=2^k-1` makes that a power of
two and the CUDA real-FFT optimal. `(128, 1024)/16` also works but is heavily
over-resolved and ~6x slower on GPU. See
`docs/history/strong_strong_spectral_optimization_history.md`. Runs on both
`CPUThreadsBackend` (parallel over field slices) and `CUDABackend`; the optimized
CUDA 6D grid path is ~1.5x the PIC one-turn time at the production case (measured
through the full example beamline; down from 6x, comparable to PIC).
"""
function SpectralPoissonSolver{T}(; kbb1=nothing, kbb2=nothing,
                                  luminosity_scale=nothing,
                                  grid=(128, 128), domain_factor=16.0,
                                  min_domain_halfwidth=0.0,
                                  method::Symbol=:grid,
                                  longitudinal_kick::Bool=true,
                                  field_precision::Symbol=:double,
                                  luminosity_schedule::Union{Nothing,AbstractSchedule}=nothing,
                                  slicing::LongitudinalSlicing=LongitudinalSlicing(),
                                  slicing1=nothing, slicing2=nothing) where {T<:Real}
    s1 = slicing1 === nothing ? slicing : slicing1
    s2 = slicing2 === nothing ? slicing : slicing2
    gx, gy = Int(grid[1]), Int(grid[2])
    (gx >= 8 && gy >= 8) || throw(ArgumentError("SpectralPoissonSolver grid dimensions must be at least 8; got $(grid)"))
    domain_factor > 0 || throw(ArgumentError("domain_factor must be positive; got $(domain_factor)"))
    min_halfwidth = T(min_domain_halfwidth)
    isfinite(min_halfwidth) && min_halfwidth >= zero(T) || throw(ArgumentError(
        "min_domain_halfwidth must be finite and nonnegative; got $(min_domain_halfwidth)."))
    method in (:grid, :grid_free) || throw(ArgumentError("method must be :grid or :grid_free; got $(repr(method))"))
    field_precision in (:double, :single) ||
        throw(ArgumentError("field_precision must be :double or :single; got $(repr(field_precision))"))
    return SpectralPoissonSolver{T}(
        _optional_solver_value(T, kbb1), _optional_solver_value(T, kbb2),
        _optional_solver_value(T, luminosity_scale), (gx, gy), T(domain_factor),
        min_halfwidth, method,
        Bool(longitudinal_kick), field_precision, luminosity_schedule,
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
        "Transverse shape (Nx, Ny): grid nodes and modes for :grid, modes only for :grid_free."),
    domain_factor = SolverOptionMeta(Real, 16.0,
        "Box half-width as a multiple of the larger transverse rms."; category=:accuracy_performance),
    min_domain_halfwidth = SolverOptionMeta(Real, 0.0,
        "Optional physical lower bound on the square Dirichlet-domain half-width in particle-coordinate length units; 0 keeps nonzero domains data-derived.";
        category=:numerical),
    method = SolverOptionMeta(Symbol, :grid,
        "Field-solve variant; :grid (DST/DCT) or :grid_free (direct mode sums)."; category=:accuracy_performance),
    longitudinal_kick = SolverOptionMeta(Bool, true,
        "Apply the synchro-beam virtual drift and potential-difference pz kick."; category=:physics),
    # supported_backends marks this :inactive_backend on CPU, which provably
    # ignores it -- the CPU path is always Float64 (audit part 6, R11). The
    # same machinery PIC's cuda_* options use one file over.
    field_precision = SolverOptionMeta(Symbol, :double,
        "CUDA field-solve precision; :double (bit-parity) or :single (faster, ~1e-7 field error)."; category=:accuracy_performance,
        supported_backends=(CUDABackend,)),
    luminosity_schedule = SolverOptionMeta(Union{Nothing,AbstractSchedule}, nothing,
        "Schedule for luminosity evaluation; nothing evaluates every turn. Same convention as PICPoissonSolver: skipped turns return NaN and leave no row in the artifact's luminosity channel.";
        category=:diagnostic),
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

function configuration_report(solver::SpectralPoissonSolver;
                              policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                              backend=nothing)
    selected_backend = backend === nothing ?
        (policy === nothing ? nothing : backend_type(policy)) : backend
    configured = solver_configuration(solver)
    entries = ConfigurationEntry[]
    for (name, meta) in pairs(solver_option_schema(solver))
        requested = getproperty(configured, name)
        resolved = name === :slicing1 ? configured.resolved_slicing1 :
                   name === :slicing2 ? configured.resolved_slicing2 : requested
        if selected_backend !== nothing && !(selected_backend in meta.supported_backends)
            push!(entries, ConfigurationEntry(name, requested, resolved, :inactive_backend,
                "option does not apply to $(selected_backend)", meta.consumer))
        else
            status = requested === nothing && resolved !== nothing ? :inherited : :resolved
            push!(entries, ConfigurationEntry(name, requested, resolved, status,
                status === :inherited ? "inherited from shared slicing" :
                                        "validated spectral solver configuration",
                meta.consumer))
        end
    end
    return Tuple(entries)
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

# Luminosity scheduling, same convention as PICPoissonSolver: when the schedule
# does not run, the beam-beam kicks are still applied and the returned luminosity
# is NaN to mark that it was intentionally not computed. `StrongStrongTask`
# leaves those turns out of the artifact's luminosity channel (see
# _strong_strong_luminosity_evaluated).
_spectral_compute_luminosity(::SpectralPoissonSolver, ::Nothing) = true
function _spectral_compute_luminosity(solver::SpectralPoissonSolver, ctx::TrackingContext)
    schedule = solver.luminosity_schedule
    evaluated = schedule === nothing || should_run(schedule, ctx)
    active_policy = _ACTIVE_RESOLVED_POLICY[]
    active_backend = active_policy isa AbstractResolvedExecutionPolicy ?
        backend_type(active_policy) : :unknown
    _record_execution!(:spectral_luminosity_schedule, active_backend,
                       (turn=ctx.turn, evaluated=evaluated,
                        schedule=schedule === nothing ? :every_turn : Symbol(nameof(typeof(schedule)))))
    return evaluated
end

_strong_strong_luminosity_evaluated(solver::SpectralPoissonSolver, ctx::TrackingContext) =
    _spectral_compute_luminosity(solver, ctx)

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
    # Per-pair scratch, TWO slots each because the L and R quantities are alive
    # together: the kick loop blends `phiL/ExL/EyL` with `phiR/ExR/EyR`, and the
    # two drifted source planes are both needed to size the box. One slot would
    # alias them.
    #
    # These were freshly allocated on every call -- three field arrays per solve
    # and two source arrays per drift, four solves and four drifts per slice
    # pair -- which is the 5.23 GiB/collide the slice hoist left behind. The
    # workspace is already leased per worker, so the slots inherit its
    # exclusivity.
    phi_buf::Vector{Vector{Float64}}
    ex_buf::Vector{Vector{Float64}}
    ey_buf::Vector{Vector{Float64}}
    src_x::Vector{Vector{Float64}}
    src_y::Vector{Vector{Float64}}
    # Virtual source positions at the luminosity plane. Slotted by DIRECTION,
    # not by L/R: both directions' results are alive together when
    # `_spectral_luminosity_pair` consumes all four, so the second interaction
    # of a pair must not reuse the first's buffers.
    mid_x::Vector{Vector{Float64}}
    mid_y::Vector{Vector{Float64}}
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
        prho, prow, pcol, pcosx, pcosy,
        [Float64[], Float64[]], [Float64[], Float64[]], [Float64[], Float64[]],
        [Float64[], Float64[]], [Float64[], Float64[]],
        [Float64[], Float64[]], [Float64[], Float64[]])
end

"""
    _spectral_slot(buffers, slot, n) -> Vector{Float64}

Slot `slot` of a workspace buffer set, resized to `n`.

`slot = 0` allocates, which is what the `:grid_free` method and every direct
caller outside the collide loop want -- `ws` is `nothing` there, and callers
that keep their arrays must not be handed one the next pair overwrites. Slots 1
and 2 are the L and R halves of one slice pair, valid until that slot is asked
for again.
"""
@inline function _spectral_slot(buffers::Vector{Vector{Float64}}, slot::Int, n::Int)
    buf = buffers[slot]
    length(buf) == n || resize!(buf, n)
    return buf
end

# A collision parallelizes over field slices, so each logical worker needs its
# own buffers/plans. Cache exclusive leases rather than raw workspaces: separate
# concurrent collisions must never mutate the same FFT buffers.
mutable struct _SpectralGridWSLease
    workspaces::Vector{_SpectralGridWS}
    in_use::Bool
end

const _SPECTRAL_WS_CACHE =
    Dict{Tuple{Int,Int},Vector{_SpectralGridWSLease}}()
const _SPECTRAL_WS_LOCK = ReentrantLock()

function _acquire_spectral_grid_ws_pool(Nx::Int, Ny::Int, nworkers::Int)
    nworkers >= 1 || throw(ArgumentError(
        "spectral workspace requires at least one worker; got $(nworkers)"))
    lock(_SPECTRAL_WS_LOCK) do
        leases = get!(() -> _SpectralGridWSLease[], _SPECTRAL_WS_CACHE, (Nx, Ny))
        for lease in leases
            lease.in_use && continue
            while length(lease.workspaces) < nworkers
                push!(lease.workspaces, _SpectralGridWS(Nx, Ny))
            end
            lease.in_use = true
            return lease
        end
        lease = _SpectralGridWSLease(
            [_SpectralGridWS(Nx, Ny) for _ in 1:nworkers], true)
        push!(leases, lease)
        return lease
    end
end

function _release_spectral_grid_ws_pool!(lease::_SpectralGridWSLease)
    lock(_SPECTRAL_WS_LOCK) do
        lease.in_use || error("spectral workspace lease was released twice")
        lease.in_use = false
    end
    return nothing
end

# Internal one-off validation callers own this workspace directly. Production
# collisions use the exclusive lease pool above. FFTW planning remains under
# the same lock because concurrent plan construction is not generally safe.
function _spectral_grid_ws(Nx::Int, Ny::Int)
    return lock(_SPECTRAL_WS_LOCK) do
        _SpectralGridWS(Nx, Ny)
    end
end

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

"""
Dropped-charge tripwire (audit part 6, R9). The box sizing covers every live
drifted coordinate by construction (1.05x the masked extremum plus the drift
bound), so nothing should ever deposit outside -- but the CIC loops clip
silently, and PIC learned that dropped charge is a correctness event, not a
tuning statistic. CIC weights sum to one per fully-in-box particle, so any
deficit in the grid total is exactly the clipped fraction. The known
reachable corner is small grids (Nx < ~41), where the 5% headroom is thinner
than one cell and an extreme particle's stencil brushes the wall.

The CUDA twin counts the clipped weight inside the deposit kernels (a grid
total per solve would synchronize the stream) and flushes one aggregate
warning per collision through `_cuda_spectral_deposit_tripwire_flush!`.
"""
function _spectral_deposit_tripwire(rho, ns, Lx, Ly)
    ns > 0 || return nothing
    deficit = ns - sum(rho)
    if deficit > 1.0e-9 * ns
        # `scope` distinguishes this per-solve number from the CUDA twin's
        # per-collision aggregate; the message text and the other keys are
        # deliberately identical so one grep finds both (2026-08-05_b audit,
        # U11-3).
        @warn "spectral deposit clipped charge at the Dirichlet wall; the box \
               no longer covers the whole beam" dropped_fraction = deficit / ns nsource = ns scope = :per_solve box = (Lx, Ly) maxlog = 8
    end
    return nothing
end

_spectral_field_grid!(ws::_SpectralGridWS, sx, sy, fx, fy, Lx, Ly) =
    (_spectral_field_grid_solve!(ws, sx, sy, Lx, Ly);
     _spectral_field_grid_eval(ws.Exg, ws.Eyg, ws.Nx, ws.Ny, fx, fy, Lx, Ly))

"""
Deposit `sx, sy` and solve, leaving `Exg`/`Eyg` on the workspace mesh. The
source-only half of `_spectral_field_grid!` (see `_spectral_field_grid_eval`
for why it is split -- audit part 6, R12).
"""
function _spectral_field_grid_solve!(ws::_SpectralGridWS, sx, sy, Lx, Ly)
    Nx, Ny = ws.Nx, ws.Ny
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    ns = length(sx)
    _spectral_ws_setbox!(ws, a, b)
    rho = ws.rho; fill!(rho, 0.0)
    @inbounds for p in eachindex(sx)
        X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += cx * cy)
        end
    end
    _spectral_deposit_tripwire(rho, ns, Lx, Ly)
    # rholm = DST(rho) / (a*b*ns); philm = -rholm * G
    mul!(ws.rholm, ws.prho, rho)
    invn = ns > 0 ? 1.0 / (a * b * ns) : 1.0 / (a * b)
    @inbounds for k in eachindex(ws.philm)
        ws.philm[k] = -(ws.rholm[k] * invn) * ws.G[k]
    end
    scale = _SPECTRAL_FIELD_SCALE_GRID
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
    return nothing
end

"""
Interpolate mesh fields at the field-particle positions. Split from the
deposit-and-solve half so the transverse path can solve each SOURCE slice once
and evaluate it against every field slice -- the mesh depends only on the
source, and recomputing it inside the field loop cost `n1*n2` solves where
`n1+n2` suffice (audit part 6, R12). Takes the mesh arrays rather than the
workspace so a stored copy evaluates identically to a live one.
"""
function _spectral_field_grid_eval(Exg, Eyg, Nx, Ny, fx, fy, Lx, Ly)
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    nf = length(fx); Ex = Vector{Float64}(undef, nf); Ey = Vector{Float64}(undef, nf)
    @inbounds for k in 1:nf
        X = (fx[k] + Lx) / hx; Y = (fy[k] + Ly) / hy
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
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

function _spectral_field_grid_potential!(ws::_SpectralGridWS, sx, sy, fx, fy, Lx, Ly;
                                         vslot::Int=0)
    Nx, Ny = ws.Nx, ws.Ny
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    ns = length(sx)
    _spectral_ws_setbox!(ws, a, b)
    rho = ws.rho; fill!(rho, 0.0)
    @inbounds for p in eachindex(sx)
        X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += cx * cy)
        end
    end
    _spectral_deposit_tripwire(rho, ns, Lx, Ly)
    mul!(ws.rholm, ws.prho, rho)
    invn = ns > 0 ? 1.0 / (a * b * ns) : 1.0 / (a * b)
    @inbounds for k in eachindex(ws.philm)
        ws.philm[k] = -(ws.rholm[k] * invn) * ws.G[k]
    end
    scale = _SPECTRAL_FIELD_SCALE_GRID

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
    Phi = vslot == 0 ? Vector{Float64}(undef, nf) : _spectral_slot(ws.phi_buf, vslot, nf)
    Ex  = vslot == 0 ? Vector{Float64}(undef, nf) : _spectral_slot(ws.ex_buf,  vslot, nf)
    Ey  = vslot == 0 ? Vector{Float64}(undef, nf) : _spectral_slot(ws.ey_buf,  vslot, nf)
    Phig = ws.Phig; Exg = ws.Exg; Eyg = ws.Eyg
    @inbounds for k in 1:nf
        X = (fx[k] + Lx) / hx; Y = (fy[k] + Ly) / hy
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
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
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
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
    scale = _SPECTRAL_FIELD_SCALE_GRID
    Exg = -scale .* _spectral_cosderiv(al .* FFTW.r2r(philm, FFTW.RODFT00, 2), 1)
    Eyg = -scale .* _spectral_cosderiv(FFTW.r2r(philm, FFTW.RODFT00, 1) .* transpose(bm), 2)
    nf = length(fx); Ex = Vector{Float64}(undef, nf); Ey = Vector{Float64}(undef, nf)
    @inbounds for k in 1:nf
        X = (fx[k] + Lx) / hx; Y = (fy[k] + Ly) / hy
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
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

"""
Out-of-box guard for the direct mode sums (audit part 6, R10). A `:grid`
source outside the Dirichlet box is CLIPPED (and the deposit tripwire warns);
a `:grid_free` source outside it is worse -- the odd periodic extension
mirrors it back inside with the SIGN FLIPPED, a measured exactly -1x field
with no signal at all. The box covers every pre-collision drifted coordinate
by construction, but the deposits happen after earlier slice pairs' kicks, so
a strong enough kick makes this reachable (the same mechanism the deposit
tripwire catches on the :grid path).
"""
function _spectral_mode_sum_guard(sx, sy, Lx, Ly)
    isempty(sx) && return nothing
    mx = maximum(abs, sx)
    my = maximum(abs, sy)
    if mx > Lx || my > Ly
        @warn "spectral :grid_free source outside the Dirichlet box; the odd \
               periodic extension mirrors it back with the sign flipped" max_abs_x = mx max_abs_y = my box = (Lx, Ly) maxlog = 8
    end
    return nothing
end

function _spectral_field_free_potential(sx, sy, fx, fy, Lx, Ly, Nx, Ny)
    _spectral_mode_sum_guard(sx, sy, Lx, Ly)
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
    scale = _SPECTRAL_FIELD_SCALE_FREE  # derived, mode-count independent
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
@inline function _spectral_luminosity_extents(solver::SpectralPoissonSolver,
                                               xspan, yspan, ::Type{T}) where {T}
    minimum_width = T(2) * T(solver.min_domain_halfwidth)
    width = max(T(xspan), minimum_width)
    height = max(T(yspan), minimum_width)
    if !(isfinite(width) && isfinite(height) &&
         width > zero(T) && height > zero(T))
        throw(ArgumentError(
            "Spectral luminosity requires finite, positive transverse extents; " *
            "observed (x=$(xspan), y=$(yspan)) with min_domain_halfwidth=" *
            "$(solver.min_domain_halfwidth). Supply a positive physical bound " *
            "for a degenerate axis."))
    end
    return width, height
end

function _spectral_luminosity_pair(solver::SpectralPoissonSolver,
                                   x1, y1, x2, y2, klum, nx, ny)
    T = promote_type(eltype(x1), eltype(x2), typeof(klum))
    xmin = min(minimum(x1), minimum(x2)); xmax = max(maximum(x1), maximum(x2))
    ymin = min(minimum(y1), minimum(y2)); ymax = max(maximum(y1), maximum(y2))
    width, height = _spectral_luminosity_extents(
        solver, xmax - xmin, ymax - ymin, T)
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
        i = _grid_floor(X); j = _grid_floor(Y); wx = X - i; wy = Y - j
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

function _spectral_field_potential_ws(solver::SpectralPoissonSolver, ws, sx, sy, fx, fy,
                                      Lx, Ly; vslot::Int=0)
    solver.method === :grid_free &&
        return _spectral_field_free_potential(sx, sy, fx, fy, Lx, Ly, solver.grid...)
    return _spectral_field_grid_potential!(ws, sx, sy, fx, fy, Lx, Ly; vslot=vslot)
end


"""
    _masked_rms(v, flags), _masked_ext(v, flags)

Root-mean-square and maximum absolute value over live entries.

The Dirichlet box is sized from these, and unlike the PIC meshes it is built
from whole coordinate arrays rather than from slice membership -- so the mask
that slicing applies for free does not reach here and has to be explicit.
`flags === nothing` restores the plain reduction, `NaN` propagation included, so
the box still comes out non-finite and trips the chokepoint below when
`allow_lost_particles` is off.
"""
function _masked_rms(v, flags)
    T = eltype(v)
    # Mean and squared-deviation sums through the canonical lane fold
    # (`_SLICE_FOLD_LANES`, U6-7 machinery; 2026-08-07 neighbour audit, N5):
    # the CPU used a serial fold (and a DIFFERENT pairwise shape when
    # unmasked) while CUDA used tree reductions, so the Dirichlet box
    # half-width L = max(d*smax, 1.05*emax) — the mesh every spectral kick
    # is solved on — differed at ulps across backends whenever the rms half
    # dominates, which is the documented production regime. One shape now;
    # NaN from live input still propagates through the lane sums, so the
    # non-finite chokepoints downstream fire exactly as before.
    n = flags === nothing ? length(v) : count(flags)
    n == 0 && return T(NaN)
    m = _lane_z_moment(v, flags, zero(T), Val(1)) / n
    s2 = _lane_z_moment(v, flags, m, Val(2))
    return sqrt(s2 / n)
end

function _masked_ext(v, flags)
    T = eltype(v)
    flags === nothing && return maximum(abs, v)
    e = T(-Inf)
    @inbounds for i in eachindex(v)
        _flag_live(flags, i) || continue
        e = max(e, abs(v[i]))
    end
    return isfinite(e) ? e : T(NaN)
end

_spectral_box(solver::SpectralPoissonSolver, rep1::Phase6DRep, rep2::Phase6DRep) =
    _spectral_box(solver, rep1.x, rep1.y, rep2.x, rep2.y,
                  _live_flags(rep1, active_live_mask()),
                  _live_flags(rep2, active_live_mask()))

function _spectral_box(solver::SpectralPoissonSolver, x1, y1, x2, y2,
                       flags1=nothing, flags2=nothing)
    d = solver.domain_factor
    # A flat beam's transverse field extends on the scale of the LARGER rms in
    # BOTH directions, so the Dirichlet box must be square and sized to sigma_max.
    # An anisotropic box (Ly ~ d*sigma_y) clips the wide field and biases the
    # kick by ~10% at 5:1; the thin direction is resolved by the grid (Ny), not a
    # smaller box. See docs/theory/spectral_sine_poisson_solver.md.
    smax = max(_masked_rms(x1, flags1), _masked_rms(x2, flags2),
               _masked_rms(y1, flags1), _masked_rms(y2, flags2))
    ext_x1 = _masked_ext(x1, flags1); ext_y1 = _masked_ext(y1, flags1)
    ext_x2 = _masked_ext(x2, flags2); ext_y2 = _masked_ext(y2, flags2)
    emax = max(ext_x1, ext_x2, ext_y1, ext_y2)
    L = max(d * smax, 1.05 * emax)
    # Non-finite chokepoint (N1, docs/history/todo_ledger_archive.md): NaN/Inf coordinates propagate into
    # the box size; out-of-box particles are silently dropped by the Dirichlet
    # deposit, so fail fast here instead. Under `allow_lost_particles` the
    # extrema skipped the dead, so reaching this means live input produced a
    # non-finite box -- still the bug this was written for.
    if !isfinite(L)
        all(isfinite, (ext_x1, ext_y1)) ||
            _nonfinite_coordinate_error(:beam, (x=x1, y=y1);
                                        context="spectral Dirichlet box, beam 1")
        _nonfinite_coordinate_error(:beam, (x=x2, y=y2);
                                    context="spectral Dirichlet box, beam 2")
    end
    L = max(L, typeof(L)(solver.min_domain_halfwidth))
    L > zero(L) || throw(ArgumentError(
        "Spectral Dirichlet box has zero half-width. Supply a positive " *
        "min_domain_halfwidth in particle-coordinate length units for a beam " *
        "collapsed at the origin."))
    return L, L
end

# Box for the 6D path. The longitudinal map deposits each source slice DRIFTED to
# the field-slice boundaries, so the box must contain the drifted extremes, not
# the interaction-point ones -- `_spectral_field_grid!` silently drops any
# particle that lands outside, which would lose charge. Bound the drift by
# |s| <= (max|z1| + max|z2|)/2, the largest half-separation any slice pair can
# produce. This can only enlarge the box relative to `_spectral_box`; at the
# production settings the `d * sigma_max` term still dominates, so the box is
# unchanged there and this is a guard for tighter `domain_factor` or longer
# bunches rather than a change to the recommended configuration.
function _spectral_box_drifted(solver::SpectralPoissonSolver, rep1, rep2)
    mask = active_live_mask()
    f1 = _live_flags(rep1, mask); f2 = _live_flags(rep2, mask)
    d = solver.domain_factor
    sdrift = (_masked_ext(rep1.z, f1) + _masked_ext(rep2.z, f2)) / 2
    extd(w, pw, f) = _masked_ext(w, f) + sdrift * _masked_ext(pw, f)
    smax = max(_masked_rms(rep1.x, f1), _masked_rms(rep2.x, f2),
               _masked_rms(rep1.y, f1), _masked_rms(rep2.y, f2))
    ext1x = extd(rep1.x, rep1.px, f1); ext1y = extd(rep1.y, rep1.py, f1)
    emax = max(ext1x, extd(rep2.x, rep2.px, f2),
               ext1y, extd(rep2.y, rep2.py, f2))
    L = max(d * smax, 1.05 * emax)
    if !isfinite(L)
        all(isfinite, (ext1x, ext1y, _masked_ext(rep1.z, f1))) ||
            _nonfinite_coordinate_error(:beam,
                (x=rep1.x, px=rep1.px, y=rep1.y, py=rep1.py, z=rep1.z);
                context="spectral drifted Dirichlet box, beam 1")
        _nonfinite_coordinate_error(:beam,
            (x=rep2.x, px=rep2.px, y=rep2.y, py=rep2.py, z=rep2.z);
            context="spectral drifted Dirichlet box, beam 2")
    end
    L = max(L, typeof(L)(solver.min_domain_halfwidth))
    L > zero(L) || throw(ArgumentError(
        "Spectral drifted Dirichlet box has zero half-width. Supply a positive " *
        "min_domain_halfwidth in particle-coordinate length units for a beam " *
        "collapsed at the origin."))
    return L, L
end

"""
Drift a source slice to one boundary plane.

`ws`/`vslot` let the caller supply the workspace's reusable slot instead of a
fresh pair. The slot is only taken when `T === Float64` -- the buffers are
`Float64`, and handing them back as a `Vector{Float32}` would be a type error
rather than a slow path. On the collide path `T` promotes through the solver's
scalars and is `Float64`, so the allocating branch is the safety net.
"""
function _spectral_drifted_source(source, drift_s, ::Type{T};
                                  ws=nothing, vslot::Int=0) where {T}
    n = length(source.x)
    use_slot = ws !== nothing && vslot != 0 && T === Float64
    x = use_slot ? _spectral_slot(ws.src_x, vslot, n) : Vector{T}(undef, n)
    y = use_slot ? _spectral_slot(ws.src_y, vslot, n) : Vector{T}(undef, n)
    @inbounds for i in 1:n
        x[i] = T(source.x[i]) + T(source.px[i]) * T(drift_s)
        y[i] = T(source.y[i]) + T(source.py[i]) * T(drift_s)
    end
    return x, y
end

function _spectral_midpoint_source(source, param_source, param_field, ::Type{T};
                                   ws=nothing, dir::Int=0) where {T}
    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    n = length(source.x)
    use_slot = ws !== nothing && dir != 0 && T === Float64
    x = use_slot ? _spectral_slot(ws.mid_x, dir, n) : Vector{T}(undef, n)
    y = use_slot ? _spectral_slot(ws.mid_y, dir, n) : Vector{T}(undef, n)
    @inbounds for i in 1:n
        x[i] = T(source.x[i]) + T(source.px[i]) * sM
        y[i] = T(source.y[i]) + T(source.py[i]) * sM
    end
    return x, y
end

function _spectral_interaction!(solver::SpectralPoissonSolver, source, param_source,
                                field, param_field, kbb_slice, ws, Lx, Ly; dir::Int=0)
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb_slice))
    nfield = length(field.x)
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    sxL, syL = _spectral_drifted_source(source, sL, T; ws=ws, vslot=1)
    sxR, syR = _spectral_drifted_source(source, sR, T; ws=ws, vslot=2)

    @inbounds for i in 1:nfield
        s = T(0.5) * (T(field.z[i]) - T(param_source.center))
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
    end

    phiL, ExL, EyL = _spectral_field_potential_ws(solver, ws, sxL, syL, field.x, field.y,
                                                  Lx, Ly; vslot=1)
    phiR, ExR, EyR = _spectral_field_potential_ws(solver, ws, sxR, syR, field.x, field.y,
                                                  Lx, Ly; vslot=2)

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

    return _spectral_midpoint_source(source, param_source, param_field, T; ws=ws, dir=dir)
end

function collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end
collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend}, ctx::Nothing) =
    _spectral_collide!(solver, beam1, beam2, ctx)
collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend}, ctx::TrackingContext) =
    _spectral_collide!(solver, beam1, beam2, ctx)

# The transverse-only collision reads original positions and only accumulates
# px/py, so slice-pair order is irrelevant (addition is commutative). We therefore
# parallelize over FIELD slices: each worker owns a disjoint set of field slices
# and accumulates the kick from every source slice, so writes never collide.
# Direction 1 (kick beam2) also accumulates the density-overlap luminosity.
function _spectral_collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ctx=nothing)
    return solver.longitudinal_kick ?
        _spectral_collide_longitudinal!(solver, beam1, beam2, ctx) :
        _spectral_collide_transverse!(solver, beam1, beam2, ctx)
end

function _spectral_collide_transverse!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ctx=nothing)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _spectral_kbb1(solver, beam1, beam2)
    kbb2 = _spectral_kbb2(solver, beam1, beam2)
    # Density-overlap luminosity uses the PIC scale npart1*npart2/(nmacro1*nmacro2)
    # (the Gaussian's klum divides by only nmacro1 because its per-particle kick sum
    # supplies the other factor; a grid overlap needs both).
    klum = _spectral_luminosity_scale(solver, beam1, beam2)
    compute_luminosity = _spectral_compute_luminosity(solver, ctx)
    lnx, lny = solver.grid
    r1 = beam1.rep; r2 = beam2.rep
    T = eltype(r1.x)
    idx1 = slices1.indices; idx2 = slices2.indices
    w1 = slices1.weight; w2 = slices2.weight
    n1 = length(idx1); n2 = length(idx2)
    Lx, Ly = _spectral_box(solver, r1, r2)
    grid = solver.method !== :grid_free
    nchunks = clamp(_cpu_worker_count(), 1, max(n1, n2))
    lease = grid ?
        _acquire_spectral_grid_ws_pool(solver.grid[1], solver.grid[2], nchunks) :
        nothing
    pool = grid ? lease.workspaces : nothing

    try
        # R12 (audit part 6): the source mesh depends only on the source
        # slice, but it was recomputed inside the field loop -- n1*n2 solves
        # per direction where n1+n2 suffice for the whole collision. Solve
        # every source ONCE up front (positions are never mutated in this
        # path, so both beams' solves are valid for both directions) and
        # store the mesh fields; the kick loops below evaluate the stored
        # meshes in the exact order they used to solve in, so the kick
        # accumulation is unchanged term for term. :grid_free keeps its
        # per-pair mode sums.
        meshes1 = Vector{Union{Nothing,Tuple{Matrix{Float64},Matrix{Float64}}}}(nothing, n1)
        meshes2 = Vector{Union{Nothing,Tuple{Matrix{Float64},Matrix{Float64}}}}(nothing, n2)
        if grid
            _run_logical_workers(nchunks) do chunk, _
                ws = pool[chunk]
                lo1, hi1 = _chunk_bounds(n1, nchunks, chunk)
                for i in lo1:hi1
                    sdx = idx1[i]; isempty(sdx) && continue
                    _spectral_field_grid_solve!(ws, (@view r1.x[sdx]), (@view r1.y[sdx]), Lx, Ly)
                    meshes1[i] = (copy(ws.Exg), copy(ws.Eyg))
                end
                lo2, hi2 = _chunk_bounds(n2, nchunks, chunk)
                for j in lo2:hi2
                    sdx = idx2[j]; isempty(sdx) && continue
                    _spectral_field_grid_solve!(ws, (@view r2.x[sdx]), (@view r2.y[sdx]), Lx, Ly)
                    meshes2[j] = (copy(ws.Exg), copy(ws.Eyg))
                end
            end
        end
        gnx = grid ? pool[1].Nx : 0
        gny = grid ? pool[1].Ny : 0
        field_for(meshes, i, ws, sx, sy, fx, fy) = grid ?
            _spectral_field_grid_eval(meshes[i][1], meshes[i][2], gnx, gny, fx, fy, Lx, Ly) :
            _spectral_field_ws(solver, ws, sx, sy, fx, fy, Lx, Ly)

        # Direction 1: beam1 sources -> kick beam2 field slices (parallel over j).
        #
        # `lum_parts` is indexed by SLICE, not by chunk (2026-08-05_b audit,
        # U6-5). Its length was `nchunks`, i.e. the worker count, so
        # `sum(lum_parts)` reassociated whenever the worker count changed and
        # the transverse spectral luminosity was not thread-count invariant --
        # measured 1 ulp between 1 and 4 workers and 2 ulp between 1 and 8, at
        # 90,000 particles over 15 slices, while the coordinates were bitwise
        # identical (0 of 540,000 differing). The campaign that recorded
        # "including spectral luminosity (0 ulp)" had measured the LONGITUDINAL
        # solver.
        #
        # Indexing by slice makes the fold order a property of the data: n2
        # entries summed in j order at any worker count. The fixed-chunk-grid
        # precedent (`_REDUCTION_CHUNKS`, U5-2) is not usable here because
        # `nchunks` also sizes the grid-workspace pool, and 64 workspaces is a
        # memory cost this path should not pay; a per-slice vector of floats is
        # negligible. Each j is written by exactly one chunk, so there is no
        # race.
        lum_parts = zeros(T, n2)
        _run_logical_workers(nchunks) do chunk, _
            ws = grid ? pool[chunk] : nothing
            jlo, jhi = _chunk_bounds(n2, nchunks, chunk)
            for j in jlo:jhi
                jdx = idx2[j]; isempty(jdx) && continue
                fx = @view r2.x[jdx]; fy = @view r2.y[jdx]
                for i in 1:n1
                    sdx = idx1[i]; isempty(sdx) && continue
                    sx = @view r1.x[sdx]; sy = @view r1.y[sdx]
                    ex, ey = field_for(meshes1, i, ws, sx, sy, fx, fy)
                    a = w1[i] * kbb2
                    @inbounds for (t, p) in enumerate(jdx)
                        r2.px[p] += a * ex[t]; r2.py[p] += a * ey[t]
                    end
                    compute_luminosity &&
                        (@inbounds lum_parts[j] += _spectral_luminosity_pair(
                            solver, sx, sy, fx, fy, klum, lnx, lny))
                end
            end
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
                    ex, ey = field_for(meshes2, j, ws, sx, sy, fx, fy)
                    a = w2[j] * kbb1
                    @inbounds for (t, p) in enumerate(fdx)
                        r1.px[p] += a * ex[t]; r1.py[p] += a * ey[t]
                    end
                end
            end
        end
        return compute_luminosity ? sum(lum_parts) : T(NaN)
    finally
        lease === nothing || _release_spectral_grid_ws_pool!(lease)
    end
end

function _spectral_collide_longitudinal!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ctx=nothing)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _spectral_kbb1(solver, beam1, beam2)
    kbb2 = _spectral_kbb2(solver, beam1, beam2)
    klum = _spectral_luminosity_scale(solver, beam1, beam2)
    compute_luminosity = _spectral_compute_luminosity(solver, ctx)
    lnx, lny = solver.grid
    Lx, Ly = _spectral_box_drifted(solver, beam1.rep, beam2.rep)
    LT = promote_type(eltype(beam1.rep.x), eltype(beam2.rep.x), typeof(klum))
    luminosity = zero(LT)
    grid = solver.method !== :grid_free
    batches = collision_pair_batches(slices1, slices2)
    max_workers = clamp(_cpu_worker_count(), 1, max(1, maximum(length, batches; init=1)))
    lease = grid ?
        _acquire_spectral_grid_ws_pool(
            solver.grid[1], solver.grid[2], max_workers) :
        nothing
    pool = grid ? lease.workspaces : nothing

    try
        # Gather each slice ONCE per collide instead of once per pair, and give
        # beam 2 a scratch twin. Direction 1 finishes reading slice i before
        # direction 2 writes it, so slice i is kicked IN PLACE and only slice j
        # needs a copy; `_spectral_interaction!` writes no source, which is what
        # makes that safe. Same treatment, and the same reasoning, as
        # `_pic_collide_pair!` -- see `_pic_slice_states`.
        #
        # This path allocated 9.83 GiB per collide and spent 27-30% of its wall
        # in GC, of which the per-pair gather, copy and scatter were about 6 GiB
        # (2026-08-10 neighbour audit ledger row).
        state1 = _pic_slice_states(beam1.rep, slices1.indices)
        state2 = _pic_slice_states(beam2.rep, slices2.indices)
        scratch2 = _pic_slice_states(beam2.rep, slices2.indices)
        for batch in batches
            nworkers = clamp(max_workers, 1, length(batch))
            # `lum_parts` indexed by PAIR position, not by chunk — the same
            # U6-5 treatment the transverse path got: `sum(lum_parts)` then
            # runs over the batch's pairs in schedule order at any worker
            # count, so the fold order is a property of the data. The
            # chunk-indexed version measured exact across 1/2/4 workers only
            # by luck of the summed values; this makes it structural (U18-2).
            lum_parts = zeros(typeof(luminosity), length(batch))
            _run_logical_workers(nworkers) do chunk, _
                ws = grid ? pool[chunk] : nothing
                lo, hi = _chunk_bounds(length(batch), nworkers, chunk)
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
                    coord1 = state1[i]
                    coord2 = state2[j]
                    field1 = coord1                     # kicked in place
                    field2 = _pic_copy_slice!(scratch2[j], coord2)
                    vx1, vy1 = _spectral_interaction!(
                        solver, coord1, param1, field2, param2,
                        slices1.weight[i] * kbb2, ws, Lx, Ly; dir=1)
                    vx2, vy2 = _spectral_interaction!(
                        solver, coord2, param2, field1, param1,
                        slices2.weight[j] * kbb1, ws, Lx, Ly; dir=2)
                    # Slice i is already current; slice j swaps its kicked
                    # scratch in. No two pairs of a batch share a slice index,
                    # so this element write never races another.
                    @inbounds state2[j], scratch2[j] = scratch2[j], state2[j]
                    compute_luminosity &&
                        (@inbounds lum_parts[pos] = _spectral_luminosity_pair(
                            solver, vx1, vy1, vx2, vy2, klum, lnx, lny))
                end
            end
            luminosity += sum(lum_parts)
        end
        # Scatter the resident slices back into the beams, once. The per-batch
        # luminosity fold above is deliberately left alone: it is pair-indexed
        # already (U6-5/U18-2) and moving it to a collision-order fold would
        # reassociate the sum and shift this solver's luminosity bits.
        _pic_store_slice_states!(beam1.rep, slices1.indices, state1)
        _pic_store_slice_states!(beam2.rep, slices2.indices, state2)
        return compute_luminosity ? luminosity : LT(NaN)
    finally
        lease === nothing || _release_spectral_grid_ws_pool!(lease)
    end
end
