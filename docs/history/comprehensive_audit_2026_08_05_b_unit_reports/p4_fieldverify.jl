# U10 probe 4: INDEPENDENT verification of the total hybrid field
# (analytic Bassetti-Erskine add-back + residual grid field) against
#   (i) a direct O(N^2) free-space summation over the SAME macroparticles
#       (the exact answer for the deposited source; measures the residual
#        grid error alone, and pins the analytic/grid normalization), and
#   (ii) the exact continuous-Gaussian Bassetti-Erskine field.
# The plain PICPoissonSolver is run in the identical configuration as the
# baseline.
#
# Setup that makes the comparison exact: px = py = 0 for every particle, so the
# drift to the two slice boundaries is a no-op and the L/R reference Gaussians
# coincide; longitudinal_kick = false; one slice per beam.
using Octopus
const O = Octopus
using SpecialFunctions: erfinv
using Statistics
using Printf

function quantile_lattice(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Float64[]; y = Float64[]
    for yy in q, xx in q
        push!(x, sigx * xx); push!(y, sigy * yy)
    end
    return x, y
end

function mkbeam(x, y, z; charge, mc2, E0, npart)
    n = length(x)
    rep = Phase6DRep(copy(x), zeros(n), copy(y), zeros(n), copy(z), zeros(n))
    params = BeamParams{Float64}(charge=charge, mc2=mc2, E0=E0,
                                 r0=RE * ME0 / mc2, npart=npart)
    return Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end

# Exact free-space PIC-normalized field of unit macroparticles: E = sum (r-r_p)/|r-r_p|^2
function direct_field(px_out, py_out, xq, yq, sx, sy)
    Threads.@threads for i in eachindex(xq)
        ax = 0.0; ay = 0.0
        @inbounds for p in eachindex(sx)
            dx = xq[i] - sx[p]; dy = yq[i] - sy[p]
            r2 = dx * dx + dy * dy
            r2 == 0 && continue
            ax += dx / r2; ay += dy / r2
        end
        px_out[i] = ax; py_out[i] = ay
    end
    return nothing
end

function run(sigx, sigy; grid, nsrc_axis=300, field_axis=41, extent=4.0,
             deposit_method=:TSC, margin_sigma=5.0, neutralize=true)
    sx, sy = quantile_lattice(sigx, sigy, nsrc_axis)
    ns = length(sx)
    xg = collect(range(-extent * sigx, extent * sigx; length=field_axis))
    yg = collect(range(-extent * sigy, extent * sigy; length=field_axis))
    fx = Float64[]; fy = Float64[]
    for yy in yg, xx in xg; push!(fx, xx); push!(fy, yy); end
    nf = length(fx)

    # tiny deterministic z spread: keeps slicing well posed, drifts nothing
    zs = collect(1.0e-9 .* (2 .* ((1:ns) ./ ns) .- 1))
    zf = collect(1.0e-9 .* (2 .* ((1:nf) ./ nf) .- 1))

    sl = LongitudinalSlicing(nslices=1, method=:equal_count)
    common = (slicing=sl, grid=(grid, grid), green_cache=:none,
              deposit_method=deposit_method, longitudinal_kick=false,
              )

    # exact direct sum, evaluated once
    ex = zeros(nf); ey = zeros(nf)
    direct_field(ex, ey, fx, fy, sx, sy)
    # exact continuous-Gaussian Bassetti-Erskine, unit population
    bex = zeros(nf); bey = zeros(nf)
    for i in 1:nf
        kx, ky = gaussian_beambeam_kick(sigx, sigy, fx[i], fy[i])
        bex[i] = 0.5 * ns * kx; bey[i] = 0.5 * ns * ky
    end

    out = Dict{Symbol,Any}()
    for (tag, solver) in ((:hybrid, GaussianPICPoissonSolver(; common...,
                                        margin_sigma=margin_sigma, neutralize=neutralize)),
                          (:pic, PICPoissonSolver(; common...)))
        b1 = mkbeam(sx, sy, zs; charge=-1.0, mc2=EMASS_EV, E0=10.0e9, npart=1.7e11)
        b2 = mkbeam(fx, fy, zf; charge=1.0, mc2=PMASS_EV, E0=275.0e9, npart=0.7e11)
        pic = tag === :hybrid ? solver.pic : solver
        kbb2 = O._pic_kbb2(pic, b1, b2)
        collide!(solver, b1, b2, CPUThreadsBackend)
        # measured field in PIC normalization
        mx = b2.rep.px ./ (2 * kbb2)
        my = b2.rep.py ./ (2 * kbb2)
        scale = maximum(sqrt.(ex .^ 2 .+ ey .^ 2))
        edir = sqrt.((mx .- ex) .^ 2 .+ (my .- ey) .^ 2) ./ scale
        ebe = sqrt.((mx .- bex) .^ 2 .+ (my .- bey) .^ 2) ./ scale
        out[tag] = (dir_med=median(edir), dir_max=maximum(edir),
                    be_med=median(ebe), be_max=maximum(ebe))
    end
    # how far the deterministic lattice itself is from a continuous Gaussian
    scale = maximum(sqrt.(ex .^ 2 .+ ey .^ 2))
    lat = sqrt.((bex .- ex) .^ 2 .+ (bey .- ey) .^ 2) ./ scale
    return out, (median(lat), maximum(lat))
end

println("Independent verification: hybrid total field (analytic + residual) vs")
println("  [direct]  exact O(N^2) free-space sum over the same macroparticles")
println("  [BE]      exact continuous-Gaussian Bassetti-Erskine")
println("normalized by max|E_direct| over the probe grid; median (max).")
println()
@printf("%-26s %-8s %-22s %-22s %-22s %-22s %s\n", "case", "grid",
        "hybrid vs direct", "PIC vs direct", "hybrid vs BE", "PIC vs BE", "lattice-vs-BE")
for (name, sigx, sigy) in (("round 100:100um", 100.0e-6, 100.0e-6),
                           ("flat  106:9.5um", 106.0e-6, 9.5e-6),
                           ("flat  250:9.5um", 250.0e-6, 9.5e-6))
    for grid in (48, 128)
        o, lat = run(sigx, sigy; grid=grid)
        @printf("%-26s %-8d %.3e (%.3e)   %.3e (%.3e)   %.3e (%.3e)   %.3e (%.3e)   %.3e\n",
                name, grid,
                o[:hybrid].dir_med, o[:hybrid].dir_max,
                o[:pic].dir_med, o[:pic].dir_max,
                o[:hybrid].be_med, o[:hybrid].be_max,
                o[:pic].be_med, o[:pic].be_max, lat[1])
    end
end

println()
println("margin / neutralize sensitivity (flat 106:9.5um, grid 128, vs direct):")
for (ms, nz) in ((5.0, true), (0.0, true), (5.0, false), (0.0, false), (3.0, false), (6.0, false))
    o, _ = run(106.0e-6, 9.5e-6; grid=128, margin_sigma=ms, neutralize=nz)
    @printf("  margin_sigma=%.1f neutralize=%-5s  hybrid %.3e (%.3e)   PIC %.3e\n",
            ms, nz, o[:hybrid].dir_med, o[:hybrid].dir_max, o[:pic].dir_med)
end

println()
println("deposit_method sensitivity (flat 106:9.5um, grid 64, vs direct):")
for dm in (:CIC, :TSC)
    o, _ = run(106.0e-6, 9.5e-6; grid=64, deposit_method=dm)
    @printf("  %s  hybrid %.3e (%.3e)   PIC %.3e (%.3e)\n", dm,
            o[:hybrid].dir_med, o[:hybrid].dir_max, o[:pic].dir_med, o[:pic].dir_max)
end
