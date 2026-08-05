# U10 probe 1: CPU<->CUDA parity of GaussianPICPoissonSolver across four regimes.
#   (a) dead / lost particle present
#   (b) an empty slice
#   (c) near-round beam (sigma_x ~ sigma_y)
#   (d) very flat beam (aspect ratio >= 10)
# Reports max relative coordinate difference and max relative kick difference.
using Octopus
using Octopus: CUDA
using Printf

const CPU = CPUThreadsBackend
const GPU = Octopus.CUDABackend

to_gpu(b) = begin
    rep = Phase6DRep((CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
    Beam{GPU,typeof(b.params),typeof(rep)}(b.params, rep)
end

# max_i |a_i - b_i| / max(scale)   -- normalized by the array's own RMS scale so
# that near-zero entries do not manufacture a huge "relative" number.
function reldiff(a, b)
    A = Array(a); B = Array(b)
    sc = max(maximum(abs, A), maximum(abs, B))
    sc == 0 && return 0.0
    return maximum(abs.(A .- B)) / sc
end

function mkbeam(n, sigx, sigy, sigz, seed, rngid, q, mc2, E0, npart; cutoff=5.0)
    set_global_rng!(seed=seed, method=:philox)
    return Beam(n, CPU, Float64;
        beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(sigx, sigy, sigz), cutoff=cutoff, rng_id=rngid,
        charge=q, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=npart)
end

function run_case(name, e0, p0, sl; grid=(64, 64), longitudinal_kick=true,
                  indexed=true, deposit_method=:TSC, coupling_tol=Inf,
                  margin_sigma=5.0, neutralize=true, mutate=identity)
    solver = GaussianPICPoissonSolver(slicing=sl, grid=grid, green_cache=:none,
                                      deposit_method=deposit_method,
                                      longitudinal_kick=longitudinal_kick,
                                      cuda_indexed_wavefront=indexed,
                                      coupling_tol=coupling_tol,
                                      margin_sigma=margin_sigma,
                                      neutralize=neutralize)
    ecpu = deepcopy(e0); pcpu = deepcopy(p0)
    mutate(ecpu); mutate(pcpu)
    # pre-collision momenta, to form the kick difference
    px0e = copy(ecpu.rep.px); py0e = copy(ecpu.rep.py); pz0e = copy(ecpu.rep.pz)
    px0p = copy(pcpu.rep.px); py0p = copy(pcpu.rep.py); pz0p = copy(pcpu.rep.pz)
    egpu = to_gpu(ecpu); pgpu = to_gpu(pcpu)
    lum_cpu = collide!(solver, ecpu, pcpu, CPU)
    lum_gpu = collide!(solver, egpu, pgpu, GPU)
    CUDA.synchronize()

    coordmax = 0.0
    for (cb, gb) in ((ecpu, egpu), (pcpu, pgpu))
        for (a, b) in zip(coordinate_arrays(cb), coordinate_arrays(gb))
            coordmax = max(coordmax, reldiff(a, b))
        end
    end
    kickmax = 0.0
    for (cb, gb, p0x, p0y, p0z) in ((ecpu, egpu, px0e, py0e, pz0e),
                                    (pcpu, pgpu, px0p, py0p, pz0p))
        for (cc, gg, base) in ((cb.rep.px, gb.rep.px, p0x),
                               (cb.rep.py, gb.rep.py, p0y),
                               (cb.rep.pz, gb.rep.pz, p0z))
            dc = Array(cc) .- base
            dg = Array(gg) .- base
            sc = max(maximum(abs, dc), maximum(abs, dg))
            sc == 0 && continue
            kickmax = max(kickmax, maximum(abs.(dc .- dg)) / sc)
        end
    end
    lumrel = (isnan(lum_cpu) || lum_cpu == 0) ? 0.0 : abs(lum_gpu - lum_cpu) / abs(lum_cpu)
    @printf("%-52s coord %.3e   kick %.3e   lum %.3e\n", name, coordmax, kickmax, lumrel)
    return (coord=coordmax, kick=kickmax, lum=lumrel)
end

# ---------------------------------------------------------------------------
sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
# equal_width slicing over a fixed range makes empty slices reachable
sl_empty = LongitudinalSlicing(nslices=9, method=:equal_width, center_position=:centroid)

println("== (c) near-round beam, sigma_x ~ sigma_y ==")
er = mkbeam(6000, 100.0e-6, 95.0e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11)
pr = mkbeam(6000, 98.0e-6, 96.0e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11)
for dm in (:CIC, :TSC), lk in (false, true), ix in (true, false)
    run_case("round dm=$dm lk=$lk indexed=$ix", er, pr, sl5;
             deposit_method=dm, longitudinal_kick=lk, indexed=ix)
end

println()
println("== (d) very flat beam, aspect >= 10 ==")
ef = mkbeam(6000, 106.0e-6, 9.5e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11)
pf = mkbeam(6000, 95.0e-6, 8.5e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11)
for dm in (:CIC, :TSC), lk in (false, true), ix in (true, false)
    run_case("flat11 dm=$dm lk=$lk indexed=$ix", ef, pf, sl5;
             deposit_method=dm, longitudinal_kick=lk, indexed=ix)
end
ef25 = mkbeam(6000, 250.0e-6, 9.5e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11)
pf25 = mkbeam(6000, 240.0e-6, 8.5e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11)
run_case("flat25 dm=TSC lk=true indexed=true", ef25, pf25, sl5)

println()
println("== (a) dead / lost particle present ==")
# Octopus marks lost particles; emulate the two documented shapes:
#   (a1) a particle whose coordinates are far outside the cloud (survives, but
#        stretches the box),
#   (a2) a particle flagged dead by the representation, if that exists.
function far_outlier!(b)
    b.rep.x[3] = 50.0 * b.rep.x[3] + 1.0e-3
    b.rep.y[7] = -40.0 * b.rep.y[7] - 5.0e-4
    return b
end
for dm in (:CIC, :TSC), lk in (false, true), ix in (true, false)
    run_case("outlier dm=$dm lk=$lk indexed=$ix", ef, pf, sl5;
             deposit_method=dm, longitudinal_kick=lk, indexed=ix, mutate=far_outlier!)
end

println()
println("== (b) empty slice ==")
# equal_width over a beam with a strongly clustered z leaves outer slices empty
function cluster_z!(b)
    b.rep.z .*= 0.05
    b.rep.z[1] *= 400.0        # one far outlier fixes the slicing range
    b.rep.z[2] *= -400.0
    return b
end
for dm in (:CIC, :TSC), lk in (false, true), ix in (true, false)
    run_case("emptyslice dm=$dm lk=$lk indexed=$ix", ef, pf, sl_empty;
             deposit_method=dm, longitudinal_kick=lk, indexed=ix, mutate=cluster_z!)
end

println()
println("== margin / neutralize variants (flat) ==")
run_case("flat margin=0", ef, pf, sl5; margin_sigma=0.0)
run_case("flat neutralize=false", ef, pf, sl5; neutralize=false)
run_case("flat margin=0 neutralize=false", ef, pf, sl5; margin_sigma=0.0, neutralize=false)

println()
println("== coupled branch (indexed only) ==")
function tilt!(b)
    x = copy(b.rep.x); y = copy(b.rep.y)
    b.rep.y .= y .+ 0.30 .* (Octopus.std(y) / Octopus.std(x)) .* x
    return b
end
for dm in (:CIC, :TSC), lk in (false, true)
    run_case("coupled tol=0.05 dm=$dm lk=$lk", ef, pf, sl5;
             deposit_method=dm, longitudinal_kick=lk, coupling_tol=0.05, mutate=tilt!)
end
