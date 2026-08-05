"""
Frozen longitudinal z-scan of the sliced beam-beam kick.

Measures how much error the *longitudinal* reconstruction of the slice field
contributes to `Delta p_x`, `Delta p_y` and `Delta p_z`, and how discontinuous
that kick is across a field-slice boundary. For a flat beam `Delta p_y` is the
observable that matters: `E_y` varies on the scale `sigma_y << sigma_x`, so its
curvature with respect to the source drift is larger by roughly the aspect ratio,
and the vertical emittance is what a spurious modulation degrades first.

Reference model
---------------
One source slice is frozen (fixed macroparticles, fixed centroid `c`) and one
test particle is frozen in `(x, y, px, py)`. Its longitudinal coordinate `z` is
swept finely across several field slices. For each `z` the exact kick is obtained
by drifting the source to that particle's own collision point
`sigma(z) = (c - z)/2` and solving Poisson's equation there -- one solve per
sample, affordable only because there is a single test particle. That reference
is compared against

- `:linear`    -- two solves at the field-slice boundaries (production default),
- `:quadratic` -- three solves adding the slice midpoint (`slice_interpolation`).

All three use the **same** transverse grid, deposition and Green kernel, so the
transverse PIC discretization error cancels in the differences and only the
longitudinal interpolation error remains. This is what separates the
interpolation error from the slicing error: both are `O(dz^2)`, both shrink as
`nslices^-2`, and a convergence study in `nslices` alone cannot tell them apart.

The exact longitudinal reference is the central difference of the exact potential
along the scan, evaluated at the particle's own transverse position, which is the
same quantity the two-node secant `(phi_L - phi_R)/(rb - lb)` approximates.

A second pass repeats the `:linear` scheme with a **per-slice** grid, sized from
each field slice's own particle bounding box exactly as `_pic_interaction_grids`
does in production, to measure the transverse jump that per-slice grid resizing
introduces at a shared slice boundary. That jump is not an interpolation error
and is not removed by adding nodes.

Error metrics
-------------
All errors are normalized by the peak exact kick over the scan:

```text
relative_error   = max_z |Delta p_scheme(z) - Delta p_exact(z)| / max_z |Delta p_exact(z)|
boundary_jump    = |Delta p(z* + eps) - Delta p(z* - eps)| / max_z |Delta p_exact(z)|
```

Theory, error constants and the interpretation of each metric:
`docs/theory/slice_longitudinal_interpolation.md`.

Run
---
From the project root:

```bash
julia --threads=4 --project=. validation/slice_longitudinal_zscan.jl
```

Overrides: `OCTOPUS_ZSCAN_NPART`, `OCTOPUS_ZSCAN_GRID`, `OCTOPUS_ZSCAN_NSLICES`,
`OCTOPUS_ZSCAN_DEPOSIT` (`CIC` or `TSC`). Non-`CIC` deposition writes to its own
file stem so runs do not clobber each other:

```bash
OCTOPUS_ZSCAN_DEPOSIT=TSC julia --threads=4 --project=. validation/slice_longitudinal_zscan.jl
```

Outputs (under `result/`)
-------------------------
- `slice_longitudinal_zscan.tsv`         -- per-sample curves, plot ready
- `slice_longitudinal_zscan_summary.tsv` -- one row per (case, scheme, component)
- `slice_longitudinal_zscan_jumps.tsv`   -- per-boundary discontinuities
- `slice_longitudinal_zscan_cells.tsv`   -- per-source-slice mesh cell sizes,
  per-slice-pair vs shared, with the worst width/height ratios (this fourth
  file went undocumented here and in the README; 2026-08-05 audit, U21-8)
"""

include("../src/Octopus.jl")
using .Octopus
using DelimitedFiles
using Printf

const O = Octopus
const T = Float64

# ---------------------------------------------------------------- config -----
_envi(k, d) = parse(Int, get(ENV, k, string(d)))
_envs(k, d) = Symbol(get(ENV, k, string(d)))

config = (
    n_source        = _envi("OCTOPUS_ZSCAN_NPART", 200_000),   # source macroparticles
    n_field         = _envi("OCTOPUS_ZSCAN_NPART", 200_000),   # field macroparticles
    grid            = (_envi("OCTOPUS_ZSCAN_GRID", 64), _envi("OCTOPUS_ZSCAN_GRID", 64)),
    deposit_method  = _envs("OCTOPUS_ZSCAN_DEPOSIT", :CIC),
    green_type      = :integrated,
    field_derivative = :second,
    nslices         = _envi("OCTOPUS_ZSCAN_NSLICES", 7),  # slices/beam, normal-quantile
    source_slices   = (4, 6),    # source slice indices to test: centre and off-centre
    scan_slices     = 3,         # number of adjacent field slices to sweep
    samples_per_slice = 61,      # z samples per field slice
    boundary_eps_frac = 1.0e-6,  # boundary probe offset, as a fraction of slice width
    seed            = 20260725,
)

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

nx, ny = config.grid

solver = PICPoissonSolver(; grid=config.grid,
                          deposit_method=config.deposit_method,
                          green_type=config.green_type,
                          field_derivative=config.field_derivative)

# ------------------------------------------------------------ beam setup -----
set_global_rng!(seed=config.seed, method=:philox)

# Flat EIC-like pair. Beam 1 (proton) is the source; beam 2 (electron) supplies
# the field slice boundaries and the test particle.
beam1 = Beam(config.n_source, CPUThreadsBackend, T; beta=(0.8, 0.072, 90.0),
             alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
             rng_id=1, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
             r0=RE * ME0 / PMASS_EV, npart=0.7e11)
beam2 = Beam(config.n_field, CPUThreadsBackend, T; beta=(0.55, 0.056, 12.0),
             alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
             rng_id=2, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
             r0=RE * ME0 / EMASS_EV, npart=1.7e11)

slicing = LongitudinalSlicing(nslices=config.nslices, method=:normal_quantile,
                              center_position=:centroid)
slices1 = O.longitudinal_slices(beam1.rep, slicing)   # source slices
slices2 = O.longitudinal_slices(beam2.rep, slicing)   # field slices

# Kick scale for beam-2 particles under a beam-1 source, exactly as the solver
# builds it: the population normalization lives in kbb, the deposit is unit
# weight per source macroparticle.
kbb = O._pic_kbb2(solver, beam1, beam2)

ws = O._pic_cpu_workspace(T, nx, ny)
newfield() = O._PICFieldWorkspace(zeros(T, nx, ny), zeros(T, nx, ny), zeros(T, nx, ny))

# ------------------------------------------------------------- utilities -----
"""Solve the drifted source field on a fixed grid and return a field workspace."""
function solve_at(src, drift, sg, green_fft)
    fw = newfield()
    O._pic_solve_drifted_field_with_green_fft!(fw, solver, src, drift, sg, green_fft, ws)
    return fw
end

"""Transverse kick from a single solved plane (no longitudinal blending)."""
function kick_single(fw, fg, x, y)
    Kx, Ky, _ = O._pic_interpolate_kick(solver, fg, x, y,
                                        fw.phi, fw.Ex, fw.Ey, fw.phi, fw.Ex, fw.Ey,
                                        one(T), zero(T))
    return 2kbb * Kx, 2kbb * Ky
end

"""
Difference of two solved potentials at one transverse position, using the same
CIC/TSC stencil the production kernel uses. `_pic_interpolate_kick` returns
`Kz = sum_w (phiA - phiB)`, which is exactly what is needed here.
"""
function phi_difference(fwA, fwB, fg, x, y)
    _, _, Kz = O._pic_interpolate_kick(solver, fg, x, y,
                                       fwA.phi, fwA.Ex, fwA.Ey, fwB.phi, fwB.Ex, fwB.Ey,
                                       one(T), zero(T))
    return Kz
end

function maxabs(v)
    m = 0.0
    for x in v
        a = abs(x)
        a > m && (m = a)
    end
    return m
end

# ------------------------------------------------------------- scan core -----
rows = Vector{Any}()
summary_rows = Vector{Any}()
jump_rows = Vector{Any}()
cell_rows = Vector{Any}()
node_cell_rows = Vector{Any}()

for si in config.source_slices
    idx_src = slices1.indices[si]
    isempty(idx_src) && continue
    src = O._pic_extract_slice(beam1.rep, idx_src)
    c = slices1.center[si]

    # Field slices to sweep: `scan_slices` adjacent slices centred on the bunch.
    first_slice = max(1, (config.nslices - config.scan_slices) ÷ 2 + 1)
    slice_range = first_slice:(first_slice + config.scan_slices - 1)
    zlo = slices2.boundary[first(slice_range)]
    zhi = slices2.boundary[last(slice_range) + 1]

    # One frozen test particle, taken from the middle field slice so that its
    # transverse coordinates are representative rather than extreme.
    mid_slice = slice_range[(length(slice_range) + 1) ÷ 2]
    probe = slices2.indices[mid_slice][1]
    x0 = beam2.rep.x[probe]; px0 = beam2.rep.px[probe]
    y0 = beam2.rep.y[probe]; py0 = beam2.rep.py[probe]

    # Exact transverse position of the test particle at longitudinal coordinate z.
    xat(z) = x0 + T(0.5) * (z - c) * px0
    yat(z) = y0 + T(0.5) * (z - c) * py0
    sigma_at(z) = T(0.5) * (c - z)

    # --- one common grid for every scheme -------------------------------------
    # x + px*s is affine in s, so bounding the two extreme drifts bounds them all.
    sA = sigma_at(zlo); sB = sigma_at(zhi)
    sxmin = sxmax = src.x[1] + src.px[1] * sA
    symin = symax = src.y[1] + src.py[1] * sA
    for i in eachindex(src.x)
        @inbounds begin
            xa = src.x[i] + src.px[i] * sA; xb = src.x[i] + src.px[i] * sB
            ya = src.y[i] + src.py[i] * sA; yb = src.y[i] + src.py[i] * sB
            sxmin = min(sxmin, xa, xb); sxmax = max(sxmax, xa, xb)
            symin = min(symin, ya, yb); symax = max(symax, ya, yb)
        end
    end
    fxmin = min(xat(zlo), xat(zhi)); fxmax = max(xat(zlo), xat(zhi))
    fymin = min(yat(zlo), yat(zhi)); fymax = max(yat(zlo), yat(zhi))
    sg, fg = O._pic_interaction_grids(solver, sxmin, sxmax, symin, symax,
                                      fxmin, fxmax, fymin, fymax)
    green_fft = O._pic_green_fft(solver, T, sg, fg)

    # --- per-slice node solves ------------------------------------------------
    nodes = Dict{Int,NamedTuple}()
    for s in slice_range
        lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
        nodes[s] = (lb=lb, rb=rb, hzi=inv(rb - lb),
                    L=solve_at(src, sigma_at(lb), sg, green_fft),
                    M=solve_at(src, sigma_at(T(0.5) * (lb + rb)), sg, green_fft),
                    R=solve_at(src, sigma_at(rb), sg, green_fft))
    end

    # --- scan samples ---------------------------------------------------------
    zs = T[]
    for s in slice_range
        lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
        n = config.samples_per_slice
        for k in 1:n
            push!(zs, lb + (rb - lb) * (k - 0.5) / n)   # cell centres: never on a boundary
        end
    end
    nsample = length(zs)

    exact_fw = Vector{Any}(undef, nsample)
    for k in 1:nsample
        exact_fw[k] = solve_at(src, sigma_at(zs[k]), sg, green_fft)
    end

    dpx_e = zeros(T, nsample); dpy_e = zeros(T, nsample); dpz_e = fill(T(NaN), nsample)
    dpx_l = zeros(T, nsample); dpy_l = zeros(T, nsample); dpz_l = zeros(T, nsample)
    dpx_q = zeros(T, nsample); dpy_q = zeros(T, nsample); dpz_q = zeros(T, nsample)
    slice_of = zeros(Int, nsample); tval = zeros(T, nsample)

    for k in 1:nsample
        z = zs[k]; x = xat(z); y = yat(z)
        s = clamp(searchsortedlast(slices2.boundary, z), first(slice_range), last(slice_range))
        nd = nodes[s]
        t = clamp((z - nd.lb) / (nd.rb - nd.lb), zero(T), one(T))
        slice_of[k] = s; tval[k] = t

        dpx_e[k], dpy_e[k] = kick_single(exact_fw[k], fg, x, y)

        # Exact longitudinal kick: -dphi/dz at fixed transverse position, by
        # central difference of the exact potentials over the scan.
        if 1 < k < nsample
            dphi = phi_difference(exact_fw[k + 1], exact_fw[k - 1], fg, x, y)
            dpz_e[k] = -2kbb * dphi / (zs[k + 1] - zs[k - 1])
        end

        Kx, Ky, Kz = O._pic_interpolate_kick(solver, fg, x, y,
            nd.L.phi, nd.L.Ex, nd.L.Ey, nd.R.phi, nd.R.Ex, nd.R.Ey, one(T) - t, t)
        dpx_l[k] = 2kbb * Kx; dpy_l[k] = 2kbb * Ky; dpz_l[k] = 2kbb * Kz * nd.hzi

        Kx, Ky, Kz = O._pic_interpolate_kick_quadratic(solver, fg, x, y,
            nd.L.phi, nd.L.Ex, nd.L.Ey, nd.M.phi, nd.M.Ex, nd.M.Ey,
            nd.R.phi, nd.R.Ex, nd.R.Ey, t)
        dpx_q[k] = 2kbb * Kx; dpy_q[k] = 2kbb * Ky; dpz_q[k] = 2kbb * Kz * nd.hzi
    end

    interior = 2:(nsample - 1)
    peak = Dict(:px => maxabs(dpx_e), :py => maxabs(dpy_e),
                :pz => maxabs(view(dpz_e, interior)))

    for k in 1:nsample
        push!(rows, [si, zs[k], slice_of[k], tval[k],
                     dpx_e[k], dpx_l[k], dpx_q[k],
                     dpy_e[k], dpy_l[k], dpy_q[k],
                     dpz_e[k], dpz_l[k], dpz_q[k]])
    end

    for (comp, ex, lin, qd) in ((:px, dpx_e, dpx_l, dpx_q),
                                (:py, dpy_e, dpy_l, dpy_q),
                                (:pz, dpz_e, dpz_l, dpz_q))
        rng = comp === :pz ? interior : 1:nsample
        el = maxabs([lin[k] - ex[k] for k in rng])
        eq = maxabs([qd[k] - ex[k] for k in rng])
        p = peak[comp]
        push!(summary_rows, [si, comp, p, el, eq, el / p, eq / p, el / max(eq, eps(T))])
    end

    # --- boundary discontinuity probes ----------------------------------------
    # Common grid: measures the algorithmic jump only.
    for s in slice_range[1:(end - 1)]
        zb = slices2.boundary[s + 1]
        wL = slices2.boundary[s + 1] - slices2.boundary[s]
        eps_z = config.boundary_eps_frac * wL
        vals = Dict{Symbol,Vector{T}}()
        for (tag, zq) in ((:minus, zb - eps_z), (:plus, zb + eps_z))
            sq = clamp(searchsortedlast(slices2.boundary, zq), first(slice_range), last(slice_range))
            nd = nodes[sq]
            t = clamp((zq - nd.lb) / (nd.rb - nd.lb), zero(T), one(T))
            x = xat(zq); y = yat(zq)
            Kx, Ky, Kz = O._pic_interpolate_kick(solver, fg, x, y,
                nd.L.phi, nd.L.Ex, nd.L.Ey, nd.R.phi, nd.R.Ex, nd.R.Ey, one(T) - t, t)
            qx, qy, qz = O._pic_interpolate_kick_quadratic(solver, fg, x, y,
                nd.L.phi, nd.L.Ex, nd.L.Ey, nd.M.phi, nd.M.Ex, nd.M.Ey,
                nd.R.phi, nd.R.Ex, nd.R.Ey, t)
            vals[tag] = T[2kbb * Kx, 2kbb * Ky, 2kbb * Kz * nd.hzi,
                          2kbb * qx, 2kbb * qy, 2kbb * qz * nd.hzi]
        end
        d = vals[:plus] .- vals[:minus]
        push!(jump_rows, [si, s, zb, "common_grid",
                          abs(d[1]) / peak[:px], abs(d[2]) / peak[:py], abs(d[3]) / peak[:pz],
                          abs(d[4]) / peak[:px], abs(d[5]) / peak[:py], abs(d[6]) / peak[:pz]])
    end

    # Per-slice grid: adds the transverse jump from grid resizing, which is an
    # implementation artefact and is NOT removed by adding interpolation nodes.
    slice_grid = Dict{Int,NamedTuple}()
    for s in slice_range
        lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
        fidx = slices2.indices[s]
        isempty(fidx) && continue
        sA2 = sigma_at(lb); sB2 = sigma_at(rb)
        sxa = sxb = src.x[1] + src.px[1] * sA2
        sya = syb = src.y[1] + src.py[1] * sA2
        for i in eachindex(src.x)
            @inbounds begin
                xa = src.x[i] + src.px[i] * sA2; xb2 = src.x[i] + src.px[i] * sB2
                ya = src.y[i] + src.py[i] * sA2; yb2 = src.y[i] + src.py[i] * sB2
                sxa = min(sxa, xa, xb2); sxb = max(sxb, xa, xb2)
                sya = min(sya, ya, yb2); syb = max(syb, ya, yb2)
            end
        end
        # Field bounds from this slice's own particles, drifted to their own
        # collision points, exactly as `_pic_interaction!` does.
        fxa = fxb = beam2.rep.x[fidx[1]]; fya = fyb = beam2.rep.y[fidx[1]]
        for i in fidx
            @inbounds begin
                sh = T(0.5) * (beam2.rep.z[i] - c)
                xv = beam2.rep.x[i] + sh * beam2.rep.px[i]
                yv = beam2.rep.y[i] + sh * beam2.rep.py[i]
                fxa = min(fxa, xv); fxb = max(fxb, xv)
                fya = min(fya, yv); fyb = max(fyb, yv)
            end
        end
        sgs, fgs = O._pic_interaction_grids(solver, sxa, sxb, sya, syb, fxa, fxb, fya, fyb)
        gfs = O._pic_green_fft(solver, T, sgs, fgs)
        slice_grid[s] = (lb=lb, rb=rb, hzi=inv(rb - lb), fg=fgs, sg=sgs,
                         L=solve_at(src, sigma_at(lb), sgs, gfs),
                         R=solve_at(src, sigma_at(rb), sgs, gfs))
    end

    for s in slice_range[1:(end - 1)]
        (haskey(slice_grid, s) && haskey(slice_grid, s + 1)) || continue
        zb = slices2.boundary[s + 1]
        eps_z = config.boundary_eps_frac * (slices2.boundary[s + 1] - slices2.boundary[s])
        out = Dict{Symbol,Vector{T}}()
        for (tag, zq, sq) in ((:minus, zb - eps_z, s), (:plus, zb + eps_z, s + 1))
            nd = slice_grid[sq]
            t = clamp((zq - nd.lb) / (nd.rb - nd.lb), zero(T), one(T))
            Kx, Ky, Kz = O._pic_interpolate_kick(solver, nd.fg, xat(zq), yat(zq),
                nd.L.phi, nd.L.Ex, nd.L.Ey, nd.R.phi, nd.R.Ex, nd.R.Ey, one(T) - t, t)
            out[tag] = T[2kbb * Kx, 2kbb * Ky, 2kbb * Kz * nd.hzi]
        end
        d = out[:plus] .- out[:minus]
        push!(jump_rows, [si, s, zb, "per_slice_grid",
                          abs(d[1]) / peak[:px], abs(d[2]) / peak[:py], abs(d[3]) / peak[:pz],
                          NaN, NaN, NaN])
    end

    # Shared per-source-slice grid, using the production helper that backs
    # `interaction_grid = :source_slice`. Should collapse the transverse jump
    # back to the common-grid (roundoff) level.
    ub = O._pic_union_bounds(src, c, beam2.rep, slices2.indices)
    if ub !== nothing
        sb, fb = ub
        sgu, fgu = O._pic_interaction_grids(solver, sb.xmin, sb.xmax, sb.ymin, sb.ymax,
                                            fb.xmin, fb.xmax, fb.ymin, fb.ymax)
        gfu = O._pic_green_fft(solver, T, sgu, fgu)
        shared = Dict{Int,NamedTuple}()
        for s in slice_range
            lb = slices2.boundary[s]; rb = slices2.boundary[s + 1]
            shared[s] = (lb=lb, rb=rb, hzi=inv(rb - lb),
                         L=solve_at(src, sigma_at(lb), sgu, gfu),
                         R=solve_at(src, sigma_at(rb), sgu, gfu))
        end
        for s in slice_range[1:(end - 1)]
            zb = slices2.boundary[s + 1]
            eps_z = config.boundary_eps_frac * (slices2.boundary[s + 1] - slices2.boundary[s])
            out = Dict{Symbol,Vector{T}}()
            for (tag, zq, sq) in ((:minus, zb - eps_z, s), (:plus, zb + eps_z, s + 1))
                nd = shared[sq]
                t = clamp((zq - nd.lb) / (nd.rb - nd.lb), zero(T), one(T))
                Kx, Ky, Kz = O._pic_interpolate_kick(solver, fgu, xat(zq), yat(zq),
                    nd.L.phi, nd.L.Ex, nd.L.Ey, nd.R.phi, nd.R.Ex, nd.R.Ey, one(T) - t, t)
                out[tag] = T[2kbb * Kx, 2kbb * Ky, 2kbb * Kz * nd.hzi]
            end
            d = out[:plus] .- out[:minus]
            push!(jump_rows, [si, s, zb, "source_slice_grid",
                              abs(d[1]) / peak[:px], abs(d[2]) / peak[:py], abs(d[3]) / peak[:pz],
                              NaN, NaN, NaN])
        end
        # --- node-indexed grids (phase 4b prototype) --------------------------
        # One grid per interpolation NODE instead of per slice. Adjacent slices
        # share the node between them, so both sides of a boundary evaluate the
        # same plane on the same grid -> exact C0. Each node's grid covers only
        # its own single source drift and the two slices adjacent to it, so there
        # is no union over the field beam and no hourglass blow-up.
        zero_plane = zeros(T, nx, ny)
        interp_phi(F, grid, x, y) = O._pic_interpolate_kick(
            solver, grid, x, y, F.phi, F.Ex, F.Ey,
            zero_plane, zero_plane, zero_plane, one(T), zero(T))[3]
        interp_E(F, grid, x, y) = begin
            kx, ky, _ = O._pic_interpolate_kick(solver, grid, x, y, F.phi, F.Ex, F.Ey,
                                                F.phi, F.Ex, F.Ey, one(T), zero(T))
            (kx, ky)
        end

        node_ids = first(slice_range):(last(slice_range) + 1)
        node_grid = Dict{Int,NamedTuple}()
        for b in node_ids
            zb = slices2.boundary[b]
            sdr = sigma_at(zb)
            sdr_next = sigma_at(slices2.boundary[min(b + 1, length(slices2.boundary))])
            sxa = T(Inf); sxb2 = T(-Inf); sya = T(Inf); syb2 = T(-Inf)
            for k in eachindex(src.x), d in (sdr, sdr_next)
                @inbounds begin
                    xv = src.x[k] + src.px[k] * d; yv = src.y[k] + src.py[k] * d
                    sxa = min(sxa, xv); sxb2 = max(sxb2, xv)
                    sya = min(sya, yv); syb2 = max(syb2, yv)
                end
            end
            fxa = T(Inf); fxb2 = T(-Inf); fya = T(Inf); fyb2 = T(-Inf)
            for adj in (b - 1, b)
                (adj in slice_range) || continue
                for k in slices2.indices[adj]
                    @inbounds begin
                        sh = T(0.5) * (beam2.rep.z[k] - c)
                        xv = beam2.rep.x[k] + sh * beam2.rep.px[k]
                        yv = beam2.rep.y[k] + sh * beam2.rep.py[k]
                        fxa = min(fxa, xv); fxb2 = max(fxb2, xv)
                        fya = min(fya, yv); fyb2 = max(fyb2, yv)
                    end
                end
            end
            isfinite(fxa) || continue
            sgn, fgn = O._pic_interaction_grids(solver, sxa, sxb2, sya, syb2,
                                                fxa, fxb2, fya, fyb2)
            gfn = O._pic_green_fft(solver, T, sgn, fgn)
            # Fz: the NEXT node's plane solved on THIS node's mesh, for the
            # longitudinal difference (production's third solve).
            zb_next = slices2.boundary[min(b + 1, length(slices2.boundary))]
            node_grid[b] = (z=zb, fg=fgn, sg=sgn,
                            F=solve_at(src, sdr, sgn, gfn),
                            Fz=solve_at(src, sigma_at(zb_next), sgn, gfn))
        end

        """Kick at `zq` inside slice `sq`, each node plane read on its own grid."""
        function node_kick(sq, zq)
            lb = slices2.boundary[sq]; rb = slices2.boundary[sq + 1]
            t = clamp((zq - lb) / (rb - lb), zero(T), one(T))
            L = node_grid[sq]; R = node_grid[sq + 1]
            x = xat(zq); y = yat(zq)
            kxL, kyL = interp_E(L.F, L.fg, x, y)
            kxR, kyR = interp_E(R.F, R.fg, x, y)
            # Longitudinal pair must share a grid: phi_L - phi_R is a small
            # difference of large numbers whose discretization error only cancels
            # within one mesh. Production solves the right node a second time on
            # the LEFT node's mesh for exactly this reason.
            kz = interp_phi(L.F, L.fg, x, y) - interp_phi(L.Fz, L.fg, x, y)
            return (2kbb * ((one(T) - t) * kxL + t * kxR),
                    2kbb * ((one(T) - t) * kyL + t * kyR),
                    2kbb * kz / (rb - lb))
        end

        if all(b -> haskey(node_grid, b), node_ids)
            for s in slice_range[1:(end - 1)]
                zb = slices2.boundary[s + 1]
                eps_z = config.boundary_eps_frac * (slices2.boundary[s + 1] - slices2.boundary[s])
                m = node_kick(s, zb - eps_z)
                pl = node_kick(s + 1, zb + eps_z)
                push!(jump_rows, [si, s, zb, "node_grid",
                                  abs(pl[1] - m[1]) / peak[:px],
                                  abs(pl[2] - m[2]) / peak[:py],
                                  abs(pl[3] - m[3]) / peak[:pz],
                                  NaN, NaN, NaN])
            end

            # Residual from continuity breaker #3: the shared node is solved once
            # per adjacent slice, and in a real strong-strong run the source is
            # kicked in between. Reproduce that by applying one slice-pair's worth
            # of kick to the source and re-solving the same node on the same grid.
            kbb_src = O._pic_kbb1(solver, beam1, beam2)
            for s in slice_range[1:(end - 1)]
                b = s + 1
                haskey(node_grid, b) || continue
                fidx = slices2.indices[s]
                isempty(fidx) && continue
                kicked = O._pic_copy_coords(src)
                fld = O._pic_extract_slice(beam2.rep, fidx)
                pf = (weight=slices2.weight[s], lb=slices2.boundary[s],
                      center=slices2.center[s], rb=slices2.boundary[s + 1])
                psrc = (weight=slices1.weight[si], lb=slices1.boundary[si],
                        center=slices1.center[si], rb=slices1.boundary[si + 1])
                O._pic_interaction!(solver, fld, pf, kicked, psrc, kbb_src, ws, nothing, nothing)
                nd = node_grid[b]
                gfn = O._pic_green_fft(solver, T, nd.sg, nd.fg)
                Fk = solve_at(kicked, sigma_at(nd.z), nd.sg, gfn)
                zq = nd.z
                x = xat(zq); y = yat(zq)
                kx0, ky0 = interp_E(nd.F, nd.fg, x, y)
                kx1, ky1 = interp_E(Fk, nd.fg, x, y)
                push!(jump_rows, [si, s, zq, "node_source_evolution",
                                  abs(2kbb * (kx1 - kx0)) / peak[:px],
                                  abs(2kbb * (ky1 - ky0)) / peak[:py],
                                  NaN, NaN, NaN, NaN])
            end

            wxn = 1.0; wyn = 1.0
            for b in node_ids, s2 in slice_range
                haskey(slice_grid, s2) || continue
                wxn = max(wxn, node_grid[b].sg.width / slice_grid[s2].sg.width)
                wyn = max(wyn, node_grid[b].sg.height / slice_grid[s2].sg.height)
            end
            push!(node_cell_rows, [si, wxn, wyn])
        end

        # Resolution cost of sharing, against the grids production actually
        # builds: the per-slice-pair meshes. Reported as the worst case over the
        # scanned slices, which is what sets the accuracy penalty.
        wx = 1.0; wy = 1.0
        for s in slice_range
            haskey(slice_grid, s) || continue
            wx = max(wx, sgu.width / slice_grid[s].sg.width)
            wy = max(wy, sgu.height / slice_grid[s].sg.height)
        end
        hx_pair = minimum(slice_grid[s].sg.width for s in slice_range if haskey(slice_grid, s)) / (nx - 1)
        hy_pair = minimum(slice_grid[s].sg.height for s in slice_range if haskey(slice_grid, s)) / (ny - 1)
        push!(cell_rows, [si, hx_pair, hy_pair,
                          sgu.width / (nx - 1), sgu.height / (ny - 1), wx, wy])
    end
end

# ---------------------------------------------------------------- output -----
# Non-default deposition writes to its own files so runs do not clobber each other.
stem = config.deposit_method === :CIC ? "slice_longitudinal_zscan" :
       "slice_longitudinal_zscan_" * lowercase(String(config.deposit_method))

scan_header = ["source_slice" "z" "field_slice" "t" "dpx_exact" "dpx_linear" "dpx_quadratic" "dpy_exact" "dpy_linear" "dpy_quadratic" "dpz_exact" "dpz_linear" "dpz_quadratic"]
open(joinpath(result_dir, stem * ".tsv"), "w") do io
    writedlm(io, scan_header)
    writedlm(io, permutedims(hcat(rows...)))
end

sum_header = ["source_slice" "component" "peak_exact" "max_err_linear" "max_err_quadratic" "rel_err_linear" "rel_err_quadratic" "improvement_factor"]
open(joinpath(result_dir, stem * "_summary.tsv"), "w") do io
    writedlm(io, sum_header)
    writedlm(io, permutedims(hcat(summary_rows...)))
end

jump_header = ["source_slice" "boundary_after_slice" "z_boundary" "grid_mode" "jump_px_linear" "jump_py_linear" "jump_pz_linear" "jump_px_quadratic" "jump_py_quadratic" "jump_pz_quadratic"]
open(joinpath(result_dir, stem * "_jumps.tsv"), "w") do io
    writedlm(io, jump_header)
    writedlm(io, permutedims(hcat(jump_rows...)))
end

println("Frozen longitudinal z-scan")
println("  grid=", config.grid, "  deposit=", config.deposit_method,
        "  nslices=", config.nslices, "  samples=", length(rows))
println()
@printf("%-7s %-5s %14s %14s %10s\n",
        "src", "comp", "rel_err_linear", "rel_err_quad", "gain")
for r in summary_rows
    @printf("%-7d %-5s %14.3e %14.3e %10.2f\n", r[1], String(r[2]), r[6], r[7], r[8])
end
println()
@printf("%-7s %-6s %-16s %12s %12s %12s\n",
        "src", "bnd", "grid_mode", "jump_px", "jump_py", "jump_pz")
for r in jump_rows
    @printf("%-7d %-6d %-16s %12.3e %12.3e %12.3e\n", r[1], r[2], r[4], r[5], r[6], r[7])
    if r[4] == "common_grid"
        @printf("%-7s %-6s %-16s %12.3e %12.3e %12.3e\n", "", "", "  (quadratic)", r[8], r[9], r[10])
    end
end
println()
@printf("%-7s %12s %12s %12s %12s %8s %8s\n",
        "src", "hx_pair", "hy_pair", "hx_shared", "hy_shared", "wx", "wy")
for r in cell_rows
    @printf("%-7d %12.4e %12.4e %12.4e %12.4e %8.3f %8.3f\n", r[1], r[2], r[3], r[4], r[5], r[6], r[7])
end
open(joinpath(result_dir, stem * "_cells.tsv"), "w") do io
    writedlm(io, ["source_slice" "hx_per_slice_pair" "hy_per_slice_pair" "hx_shared" "hy_shared" "width_ratio_worst" "height_ratio_worst"])
    writedlm(io, permutedims(hcat(cell_rows...)))
end
println()
@printf("%-7s %28s %8s %8s\n", "src", "node grid vs per-slice-pair", "wx", "wy")
for r in node_cell_rows
    @printf("%-7d %28s %8.3f %8.3f\n", r[1], "", r[2], r[3])
end
println()
println("Wrote result/", stem, ".tsv, _summary.tsv, _jumps.tsv, _cells.tsv")
