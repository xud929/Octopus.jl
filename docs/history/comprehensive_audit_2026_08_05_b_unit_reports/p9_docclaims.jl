# U10 probe 9: check the two quantitative claims the region's own docstring makes,
# and the configuration_report honesty question.
using Octopus
using Octopus: CUDA
const O = Octopus
using SpecialFunctions: erfinv
using Statistics
using Printf

const CPU = CPUThreadsBackend
const GPU = Octopus.CUDABackend
to_gpu(b) = begin
    rep = Phase6DRep((CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
    Beam{GPU,typeof(b.params),typeof(rep)}(b.params, rep)
end
function mkbeam(n, sigx, sigy, sigz, seed, rngid, q, mc2, E0, npart)
    set_global_rng!(seed=seed, method=:philox)
    return Beam(n, CPU, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(sigx, sigy, sigz), cutoff=5.0, rng_id=rngid,
        charge=q, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=npart)
end
mkflat() = (mkbeam(6000, 106.0e-6, 9.5e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11),
            mkbeam(6000, 95.0e-6, 8.5e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11))

println("###### docstring claim: \"~1e-13 relative on the kicks at grid 16\" ######")
sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
for g in (16, 64)
    ec, pc = mkflat()
    base = (copy(ec.rep.px), copy(ec.rep.py), copy(ec.rep.pz))
    eg, pg = to_gpu(ec), to_gpu(pc)
    s = GaussianPICPoissonSolver(slicing=sl5, grid=(g, g), green_cache=:none,
        deposit_method=:TSC, longitudinal_kick=true)
    collide!(s, ec, pc, CPU); collide!(s, eg, pg, GPU); CUDA.synchronize()
    k = 0.0
    for (comp, b0) in zip((:px, :py), base)
        dc = getproperty(ec.rep, comp) .- b0
        dg = Array(getproperty(eg.rep, comp)) .- b0
        k = max(k, maximum(abs.(dc .- dg)) / maximum(abs, dc))
    end
    @printf("  grid %-4d  max relative kick difference = %.3e\n", g, k)
end

println()
println("###### docstring claim: TSC beats CIC for the hybrid, CIC beats TSC for PIC ######")
function quantile_lattice(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Float64[]; y = Float64[]
    for yy in q, xx in q; push!(x, sigx * xx); push!(y, sigy * yy); end
    return x, y
end
function mkb(x, y, z; charge, mc2, E0, npart)
    n = length(x)
    rep = Phase6DRep(copy(x), zeros(n), copy(y), zeros(n), collect(z), zeros(n))
    params = BeamParams{Float64}(charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=npart)
    return Beam{CPU,typeof(params),typeof(rep)}(params, rep)
end
function medvsBE(sigx, sigy; grid, dm)
    sx, sy = quantile_lattice(sigx, sigy, 300); ns = length(sx)
    xg = range(-4sigx, 4sigx; length=41); yg = range(-4sigy, 4sigy; length=41)
    fx = Float64[]; fy = Float64[]
    for yy in yg, xx in xg; push!(fx, xx); push!(fy, yy); end
    nf = length(fx)
    zs = 1e-9 .* (2 .* ((1:ns) ./ ns) .- 1); zf = 1e-9 .* (2 .* ((1:nf) ./ nf) .- 1)
    sl = LongitudinalSlicing(nslices=1, method=:equal_count)
    common = (slicing=sl, grid=(grid, grid), green_cache=:none,
              deposit_method=dm, longitudinal_kick=false)
    bex = zeros(nf); bey = zeros(nf)
    for i in 1:nf
        kx, ky = gaussian_beambeam_kick(sigx, sigy, fx[i], fy[i])
        bex[i] = 0.5ns * kx; bey[i] = 0.5ns * ky
    end
    scale = maximum(sqrt.(bex .^ 2 .+ bey .^ 2))
    out = Dict{Symbol,Float64}()
    for (tag, solver) in ((:hybrid, GaussianPICPoissonSolver(; common...)),
                          (:pic, PICPoissonSolver(; common...)))
        b1 = mkb(sx, sy, zs; charge=-1.0, mc2=EMASS_EV, E0=10.0e9, npart=1.7e11)
        b2 = mkb(fx, fy, zf; charge=1.0, mc2=PMASS_EV, E0=275.0e9, npart=0.7e11)
        pic = tag === :hybrid ? solver.pic : solver
        kbb2 = O._pic_kbb2(pic, b1, b2)
        collide!(solver, b1, b2, CPU)
        mx = b2.rep.px ./ (2kbb2); my = b2.rep.py ./ (2kbb2)
        out[tag] = median(sqrt.((mx .- bex) .^ 2 .+ (my .- bey) .^ 2) ./ scale)
    end
    return out
end
for (nm, sx, sy) in (("11:1", 106.0e-6, 9.5e-6), ("25:1", 240.0e-6, 9.5e-6))
    for dm in (:CIC, :TSC)
        o = medvsBE(sx, sy; grid=64, dm=dm)
        @printf("  %s grid 64 %s:  hybrid %.2e   PIC %.2e\n", nm, dm, o[:hybrid], o[:pic])
    end
end

println()
println("###### configuration_report status for options the hybrid REJECTS ######")
s = GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64), grid_extent=:sigma)
for e in O.configuration_report(s)
    e.name in (:grid_extent, :grid_extent_sigma, :interaction_grid, :slice_interpolation,
               :cuda_async, :cuda_batch_fft, :cuda_wavefront_fft, :coupling_tol) || continue
    @printf("  %-24s value=%-14s status=%s\n", e.name, string(e.resolved), e.status)
end
ec, pc = mkflat()
r = try; collide!(s, ec, pc, CPU); "no throw"; catch err; "THROW: " * first(split(sprint(showerror, err), '.')); end
println("  ... yet collide! with this solver: ", r)
