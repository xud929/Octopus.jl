#=
Frozen longitudinal z-scan of the Gaussian-subtracted PIC (hybrid) kick.

Completes docs/history/todo_ledger_archive.md item 4a: the earlier attempt called the raw PIC solve
path and never exercised `GaussianPICPoissonSolver`'s control-variate
subtraction, so it measured the PIC jump twice. This scan goes through the
hybrid's own field construction (`_gpic_solve_drifted_field!`: deposit, erf
Gaussian subtraction, residual Green-FFT solve) plus the analytic
Bassetti-Erskine add-back, exactly as `_gpic_interaction!` composes them.

Reference model: as in validation/slice_longitudinal_zscan.jl, one frozen source
slice, one frozen test particle swept in z across adjacent field slices, all
solves on ONE common transverse grid (sized to include the hybrid's
margin-sigma Gaussian box), so transverse discretization cancels and only the
longitudinal reconstruction remains. For each z the exact reference of a scheme
is that scheme's own solve at the exact drift sigma(z) = (c - z)/2; the
`:linear` scheme blends the residual field planes AND the analytic boundary
terms with the production zL/zR weights.

The prediction under test: at a shared field-slice boundary the analytic
add-back is continuous by construction (both slices evaluate the same boundary
drift), so the hybrid's transverse boundary jump comes only from the residual
grid part and should be smaller than pure PIC's jump by roughly the residual
fraction ||delta Q|| / ||Q||.

Metrics (transverse only; the longitudinal kick adds analytic covariance terms
outside this scan's scope): peak-normalized max interpolation error and
boundary jumps for pure PIC `:linear` and hybrid `:linear` on the same grid,
plus the deposited residual fraction.

Inputs (environment overrides): OCTOPUS_GPIC_ZSCAN_NPART (default 200_000),
OCTOPUS_GPIC_ZSCAN_GRID (64), OCTOPUS_GPIC_ZSCAN_NSLICES (7),
OCTOPUS_GPIC_ZSCAN_DEPOSIT (CIC | TSC).

Output: result/gaussian_pic_zscan_summary.tsv and a printed table.

Run from the project root:

    julia --threads=4 --project=. validation/gaussian_pic_zscan.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using DelimitedFiles
using Printf

const O = Octopus
const T = Float64

_envi(k, d) = parse(Int, get(ENV, k, string(d)))
_envs(k, d) = Symbol(get(ENV, k, string(d)))

config = (
    npart = _envi("OCTOPUS_GPIC_ZSCAN_NPART", 200_000),
    grid = (_envi("OCTOPUS_GPIC_ZSCAN_GRID", 64), _envi("OCTOPUS_GPIC_ZSCAN_GRID", 64)),
    deposit_method = _envs("OCTOPUS_GPIC_ZSCAN_DEPOSIT", :CIC),
    nslices = _envi("OCTOPUS_GPIC_ZSCAN_NSLICES", 7),
    # The MIDDLE slice, derived from nslices rather than hardcoded to 4
    # (2026-08-05_b audit, U23-9). `nslices` is env-driven while this was a
    # literal, so any documented override below 4 died with
    # `BoundsError: attempt to access 3-element Vector{Vector{Int64}} at
    # index [4]` -- a documented knob that could only be turned upward.
    source_slice = max(1, (_envi("OCTOPUS_GPIC_ZSCAN_NSLICES", 7) + 1) ÷ 2),
    scan_slices = 3,
    samples_per_slice = 61,
    boundary_eps_frac = 1.0e-6,
    seed = 20260726,
)

nx, ny = config.grid
gsolver = GaussianPICPoissonSolver(; grid=config.grid, deposit_method=config.deposit_method)
pic = gsolver.pic

set_global_rng!(seed=config.seed, method=:philox)
beam1 = Beam(config.npart, CPUThreadsBackend, T; beta=(0.8, 0.072, 90.0),
             alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
             rng_id=1, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
             r0=RE * ME0 / PMASS_EV, npart=0.7e11)
beam2 = Beam(config.npart, CPUThreadsBackend, T; beta=(0.55, 0.056, 12.0),
             alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
             rng_id=2, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
             r0=RE * ME0 / EMASS_EV, npart=1.7e11)

slicing = LongitudinalSlicing(nslices=config.nslices, method=:normal_quantile,
                              center_position=:centroid)
slices1 = O.longitudinal_slices(beam1.rep, slicing)
slices2 = O.longitudinal_slices(beam2.rep, slicing)
kbb = O._pic_kbb2(pic, beam1, beam2)

si = config.source_slice
src = O._pic_extract_slice(beam1.rep, slices1.indices[si])
c = slices1.center[si]
nsrc = length(src.x)
mom = O._gpic_source_moments(src)

first_slice = max(1, (config.nslices - config.scan_slices) ÷ 2 + 1)
slice_range = first_slice:(first_slice + config.scan_slices - 1)
zlo = slices2.boundary[first(slice_range)]
zhi = slices2.boundary[last(slice_range) + 1]

mid_slice = slice_range[(length(slice_range) + 1) ÷ 2]
probe = slices2.indices[mid_slice][1]
x0 = beam2.rep.x[probe]; px0 = beam2.rep.px[probe]
y0 = beam2.rep.y[probe]; py0 = beam2.rep.py[probe]
xat(z) = x0 + T(0.5) * (z - c) * px0
yat(z) = y0 + T(0.5) * (z - c) * py0
sigma_at(z) = T(0.5) * (c - z)

# One common grid: particle extent over the extreme drifts, unioned with the
# hybrid's margin-sigma Gaussian box at both extremes (as _gpic_interaction!).
sA = sigma_at(zlo); sB = sigma_at(zhi)
sxmin = T(Inf); sxmax = T(-Inf); symin = T(Inf); symax = T(-Inf)
for i in eachindex(src.x)
    xa = src.x[i] + src.px[i] * sA; xb = src.x[i] + src.px[i] * sB
    ya = src.y[i] + src.py[i] * sA; yb = src.y[i] + src.py[i] * sB
    global sxmin = min(sxmin, xa, xb); global sxmax = max(sxmax, xa, xb)
    global symin = min(symin, ya, yb); global symax = max(symax, ya, yb)
end
margin = T(gsolver.margin_sigma)
for s in (sA, sB)
    mux, muy, sigx, sigy = O._gpic_drifted_gaussian(mom, s)
    global sxmin = min(sxmin, mux - margin * sigx); global sxmax = max(sxmax, mux + margin * sigx)
    global symin = min(symin, muy - margin * sigy); global symax = max(symax, muy + margin * sigy)
end
fxmin = min(xat(zlo), xat(zhi)); fxmax = max(xat(zlo), xat(zhi))
fymin = min(yat(zlo), yat(zhi)); fymax = max(yat(zlo), yat(zhi))
sg, fg = O._pic_interaction_grids(pic, sxmin, sxmax, symin, symax,
                                  fxmin, fxmax, fymin, fymax)
green_fft = O._pic_green_fft(pic, T, sg, fg)

ws = O._pic_cpu_workspace(T, nx, ny)
gxbuf = Vector{T}(undef, nx)
gybuf = Vector{T}(undef, ny)
newfield() = O._PICFieldWorkspace(zeros(T, nx, ny), zeros(T, nx, ny), zeros(T, nx, ny))

"""Pure-PIC solve of the drifted source (no subtraction) on grid `sg_`."""
function solve_pic_on(drift, sg_, gf_)
    fw = newfield()
    O._pic_solve_drifted_field_with_green_fft!(fw, pic, src, drift, sg_, gf_, ws)
    return fw
end
solve_pic(drift) = solve_pic_on(drift, sg, green_fft)

"""Hybrid residual solve of the drifted source through the hybrid's own path."""
function solve_hybrid_on(drift, sg_, gf_)
    fw = newfield()
    mux, muy, sigx, sigy = O._gpic_drifted_gaussian(mom, drift)
    O._gpic_solve_drifted_field!(fw, pic, src, drift, sg_, gf_, ws,
                                 mux, muy, sigx, sigy, nsrc, gsolver.neutralize,
                                 gxbuf, gybuf)
    return fw
end
solve_hybrid(drift) = solve_hybrid_on(drift, sg, green_fft)

"""Analytic Bassetti-Erskine add-back at (x, y) for the source drifted by s."""
function analytic_kick(s, x, y)
    mux, muy, sigx, sigy = O._gpic_drifted_gaussian(mom, s)
    bex, bey = gaussian_beambeam_kick(sigx, sigy, x - mux, y - muy)
    half_ns = T(0.5) * T(nsrc)
    return 2kbb * half_ns * bex, 2kbb * half_ns * bey
end

function grid_kick(fw, x, y)
    Kx, Ky, _ = O._pic_interpolate_kick(pic, fg, x, y,
                                        fw.phi, fw.Ex, fw.Ey, fw.phi, fw.Ex, fw.Ey,
                                        one(T), zero(T))
    return 2kbb * Kx, 2kbb * Ky
end

# Residual fraction at the source-centre drift, using the actual deposited and
# subtracted grids: rebuild both and compare 1-norms.
residual_fraction = let
    drift = sigma_at(c)
    charge = ws.charge
    fill!(charge, zero(T))
    hx = T(sg.width) / T(nx - 1); hy = T(sg.height) / T(ny - 1)
    O._pic_deposit_drifted!(charge, pic.deposit_method, src.x, src.px, src.y, src.py,
                            drift, T(sg.x0), T(sg.y0), hx, hy, nx, ny, ws)
    full = sum(abs, @view charge[1:nx, 1:ny])
    mux, muy, sigx, sigy = O._gpic_drifted_gaussian(mom, drift)
    O._gpic_gaussian_profile!(gxbuf, T(sg.x0), hx, mux, sigx, pic.deposit_method)
    O._gpic_gaussian_profile!(gybuf, T(sg.y0), hy, muy, sigy, pic.deposit_method)
    amp = gsolver.neutralize ?
        sum(@view charge[1:nx, 1:ny]) / (sum(gxbuf) * sum(gybuf)) : T(nsrc)
    resid = 0.0
    for j in 1:ny, i in 1:nx
        resid += abs(charge[i, j] - amp * gxbuf[i] * gybuf[j])
    end
    resid / full
end

# Per-slice L/R planes for both solvers.
nodes_pic = Dict{Int,NamedTuple}()
nodes_hyb = Dict{Int,NamedTuple}()
for s in slice_range
    lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
    nodes_pic[s] = (lb=lb, rb=rb, L=solve_pic(sigma_at(lb)), R=solve_pic(sigma_at(rb)))
    nodes_hyb[s] = (lb=lb, rb=rb, L=solve_hybrid(sigma_at(lb)), R=solve_hybrid(sigma_at(rb)))
end

"""Linear-scheme transverse kick at z: grid planes and analytic boundary terms
blended with the production zL/zR weights (mirrors `_gpic_interaction!`)."""
function scheme_kick(nodes, s, z; hybrid::Bool)
    nd = nodes[s]
    t = clamp((z - nd.lb) / (nd.rb - nd.lb), zero(T), one(T))
    zL = one(T) - t
    x = xat(z); y = yat(z)
    Kx, Ky, _ = O._pic_interpolate_kick(pic, fg, x, y,
        nd.L.phi, nd.L.Ex, nd.L.Ey, nd.R.phi, nd.R.Ex, nd.R.Ey, zL, t)
    dpx = 2kbb * Kx; dpy = 2kbb * Ky
    if hybrid
        aLx, aLy = analytic_kick(sigma_at(nd.lb), x, y)
        aRx, aRy = analytic_kick(sigma_at(nd.rb), x, y)
        dpx += zL * aLx + t * aRx
        dpy += zL * aLy + t * aRy
    end
    return dpx, dpy
end

"""Exact kick at z: that scheme's own solve at the exact drift."""
function exact_kick(z; hybrid::Bool)
    fw = hybrid ? solve_hybrid(sigma_at(z)) : solve_pic(sigma_at(z))
    dpx, dpy = grid_kick(fw, xat(z), yat(z))
    if hybrid
        ax, ay = analytic_kick(sigma_at(z), xat(z), yat(z))
        dpx += ax; dpy += ay
    end
    return dpx, dpy
end

zs = T[]
for s in slice_range
    lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
    n = config.samples_per_slice
    for k in 1:n
        push!(zs, lb + (rb - lb) * (k - 0.5) / n)
    end
end

summary_rows = Vector{Any}()
for hybrid in (false, true)
    nodes = hybrid ? nodes_hyb : nodes_pic
    ex = [exact_kick(z; hybrid=hybrid) for z in zs]
    peak_x = maximum(abs(first(v)) for v in ex)
    peak_y = maximum(abs(last(v)) for v in ex)
    err_x = 0.0; err_y = 0.0
    for (k, z) in enumerate(zs)
        s = clamp(searchsortedlast(slices2.boundary, z), first(slice_range), last(slice_range))
        dpx, dpy = scheme_kick(nodes, s, z; hybrid=hybrid)
        err_x = max(err_x, abs(dpx - ex[k][1]))
        err_y = max(err_y, abs(dpy - ex[k][2]))
    end
    jump_x = 0.0; jump_y = 0.0
    for s in slice_range[1:(end - 1)]
        zb = slices2.boundary[s + 1]
        eps_z = config.boundary_eps_frac * (slices2.boundary[s + 1] - slices2.boundary[s])
        m = scheme_kick(nodes, s, zb - eps_z; hybrid=hybrid)
        p = scheme_kick(nodes, s + 1, zb + eps_z; hybrid=hybrid)
        jump_x = max(jump_x, abs(p[1] - m[1]))
        jump_y = max(jump_y, abs(p[2] - m[2]))
    end
    push!(summary_rows, [hybrid ? "hybrid" : "pic", peak_x, peak_y,
                         err_x / peak_x, err_y / peak_y,
                         jump_x / peak_x, jump_y / peak_y])
end

# --- per-slice-pair grids: the production mesh-resizing jump -----------------
# This is the jump the todo-item prediction is about. On per-slice-pair meshes
# the transverse kick jumps at every boundary because the discretization error
# changes with the mesh. For the hybrid only the RESIDUAL lives on the mesh (the
# analytic add-back is mesh-independent and continuous), so its mesh-resizing
# jump should scale down by roughly the residual fraction.
slice_nodes_pic = Dict{Int,NamedTuple}()
slice_nodes_hyb = Dict{Int,NamedTuple}()
for s in slice_range
    lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
    sA2 = sigma_at(lb); sB2 = sigma_at(rb)
    sxa = T(Inf); sxb = T(-Inf); sya = T(Inf); syb = T(-Inf)
    for i in eachindex(src.x)
        xa = src.x[i] + src.px[i] * sA2; xb2 = src.x[i] + src.px[i] * sB2
        ya = src.y[i] + src.py[i] * sA2; yb2 = src.y[i] + src.py[i] * sB2
        sxa = min(sxa, xa, xb2); sxb = max(sxb, xa, xb2)
        sya = min(sya, ya, yb2); syb = max(syb, ya, yb2)
    end
    # The hybrid enlarges the box by the margin-sigma Gaussian extent, exactly
    # as _gpic_interaction! does; use the same box for the PIC comparison so the
    # two solvers see identical meshes and only the deposited content differs.
    for s2 in (sA2, sB2)
        mux, muy, sigx, sigy = O._gpic_drifted_gaussian(mom, s2)
        sxa = min(sxa, mux - margin * sigx); sxb = max(sxb, mux + margin * sigx)
        sya = min(sya, muy - margin * sigy); syb = max(syb, muy + margin * sigy)
    end
    fidx = slices2.indices[s]
    isempty(fidx) && continue
    fxa = T(Inf); fxb = T(-Inf); fya = T(Inf); fyb = T(-Inf)
    for i in fidx
        sh = T(0.5) * (beam2.rep.z[i] - c)
        xv = beam2.rep.x[i] + sh * beam2.rep.px[i]
        yv = beam2.rep.y[i] + sh * beam2.rep.py[i]
        fxa = min(fxa, xv); fxb = max(fxb, xv)
        fya = min(fya, yv); fyb = max(fyb, yv)
    end
    sgs, fgs = O._pic_interaction_grids(pic, sxa, sxb, sya, syb, fxa, fxb, fya, fyb)
    gfs = O._pic_green_fft(pic, T, sgs, fgs)
    slice_nodes_pic[s] = (lb=lb, rb=rb, fg=fgs,
                          L=solve_pic_on(sA2, sgs, gfs), R=solve_pic_on(sB2, sgs, gfs))
    slice_nodes_hyb[s] = (lb=lb, rb=rb, fg=fgs,
                          L=solve_hybrid_on(sA2, sgs, gfs), R=solve_hybrid_on(sB2, sgs, gfs))
end

"""Linear-scheme kick with each slice's own grid (production mesh sizing)."""
function scheme_kick_grid(nodes, s, z; hybrid::Bool)
    nd = nodes[s]
    t = clamp((z - nd.lb) / (nd.rb - nd.lb), zero(T), one(T))
    zL = one(T) - t
    x = xat(z); y = yat(z)
    Kx, Ky, _ = O._pic_interpolate_kick(pic, nd.fg, x, y,
        nd.L.phi, nd.L.Ex, nd.L.Ey, nd.R.phi, nd.R.Ex, nd.R.Ey, zL, t)
    dpx = 2kbb * Kx; dpy = 2kbb * Ky
    if hybrid
        aLx, aLy = analytic_kick(sigma_at(nd.lb), x, y)
        aRx, aRy = analytic_kick(sigma_at(nd.rb), x, y)
        dpx += zL * aLx + t * aRx
        dpy += zL * aLy + t * aRy
    end
    return dpx, dpy
end

for hybrid in (false, true)
    nodes = hybrid ? slice_nodes_hyb : slice_nodes_pic
    peak_x = summary_rows[hybrid ? 2 : 1][2]
    peak_y = summary_rows[hybrid ? 2 : 1][3]
    jump_x = 0.0; jump_y = 0.0
    for s in slice_range[1:(end - 1)]
        (haskey(nodes, s) && haskey(nodes, s + 1)) || continue
        zb = slices2.boundary[s + 1]
        eps_z = config.boundary_eps_frac * (slices2.boundary[s + 1] - slices2.boundary[s])
        m = scheme_kick_grid(nodes, s, zb - eps_z; hybrid=hybrid)
        p = scheme_kick_grid(nodes, s + 1, zb + eps_z; hybrid=hybrid)
        jump_x = max(jump_x, abs(p[1] - m[1]))
        jump_y = max(jump_y, abs(p[2] - m[2]))
    end
    push!(summary_rows, [hybrid ? "hybrid_slice_grid" : "pic_slice_grid",
                         peak_x, peak_y, NaN, NaN, jump_x / peak_x, jump_y / peak_y])
end

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)
open(joinpath(result_dir, "gaussian_pic_zscan_summary.tsv"), "w") do io
    writedlm(io, ["solver" "peak_dpx" "peak_dpy" "rel_err_px" "rel_err_py" "jump_px" "jump_py"])
    writedlm(io, permutedims(hcat(summary_rows...)))
    println(io, "# residual_fraction\t", residual_fraction)
end

println("Gaussian-subtracted PIC z-scan (grid=", config.grid,
        ", deposit=", config.deposit_method, ", nslices=", config.nslices, ")")
println("deposited residual fraction ||dQ||_1 / ||Q||_1 = ",
        round(residual_fraction; sigdigits=3))
@printf("%-18s %12s %12s %12s %12s\n", "solver", "rel_err_px", "rel_err_py", "jump_px", "jump_py")
for r in summary_rows
    @printf("%-18s %12.3e %12.3e %12.3e %12.3e\n", r[1], r[4], r[5], r[6], r[7])
end
pic_sg = summary_rows[3]; hyb_sg = summary_rows[4]
@printf("per-slice-grid jump reduction: px %.2fx, py %.2fx (prediction: ~1/residual_fraction = %.1fx)\n",
        pic_sg[6] / hyb_sg[6], pic_sg[7] / hyb_sg[7], 1 / residual_fraction)
println("wrote result/gaussian_pic_zscan_summary.tsv")
