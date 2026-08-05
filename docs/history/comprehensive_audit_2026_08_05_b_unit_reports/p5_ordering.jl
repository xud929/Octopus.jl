# U11 probe 5: (e) luminosity/kick accumulation ordering.
#   CPU  _spectral_collide_longitudinal!  : folds per-worker partials, chunk grid
#                                           set by _cpu_worker_count()
#   CUDA _cuda_spectral_collide_longitudinal! : strictly sequential over
#                                           _slice_collision_order, but atomic deposits
using Octopus, Printf
const O = Octopus
const CU = Octopus.CUDA
reld(a, b) = maximum(abs.(vec(a) .- vec(b))) / max(maximum(abs, vec(b)), floatmin())

function mkrep(n; seed=0.0, bimodal=false)
    s(scale, phase) = [scale * sin(0.7 * i + phase + seed) for i in 1:n]
    z = bimodal ?
        [(i % 2 == 0 ? 1.0 : -1.0) * (1.0e-2 + 1.0e-3 * sin(0.9 * i + seed)) for i in 1:n] :
        [2.0e-2 * sin(0.7 * i + 2.0 + seed) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    (s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2), z, s(1.0e-4, 2.5))
end
mkb(gpu, arrs) = begin
    rep = gpu ? Phase6DRep((CU.CuArray(copy(a)) for a in arrs)...) :
                Phase6DRep((copy(a) for a in arrs)...)
    p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=length(arrs[1]))
    B = gpu ? O.CUDABackend : CPUThreadsBackend
    Beam{B,typeof(p),typeof(rep)}(p, rep)
end
workers(f, k, rep) = O._with_execution_policy(f,
    O._resolve_execution_policy(CPUThreadsExecutionPolicy(threads=k), rep))

println("threads available: ", Threads.nthreads(:default))
for (label, n, sl, bim) in (
        ("repo pin: n=15000 nsl=3 equal_count", 15000,
         LongitudinalSlicing(nslices=3, method=:equal_count), false),
        ("8 slices, equal_count, n=4000", 4000,
         LongitudinalSlicing(nslices=8, method=:equal_count), false),
        ("10 slices equal_width, 8 EMPTY, n=1200", 1200,
         LongitudinalSlicing(nslices=10, method=:equal_width), true))
    a1 = mkrep(n; seed=0.0, bimodal=bim); a2 = mkrep(n; seed=1.7, bimodal=bim)
    solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), slicing=sl)
    outs = map(unique((1, 2, Threads.nthreads(:default)))) do k
        c1 = mkb(false, a1); c2 = mkb(false, a2)
        l = workers(k, c1.rep) do; collide!(solver, c1, c2, CPUThreadsBackend) end
        (k, l, copy(c1.rep.px), copy(c1.rep.pz))
    end
    println("  ", label)
    for o in outs[2:end]
        ulp = abs(o[2] - outs[1][2]) / eps(abs(outs[1][2]))
        @printf("    CPU %d vs %d workers: lum bitwise %s (%.1f ulp, rel %.2e) ; px bitwise %s ; pz bitwise %s\n",
                o[1], outs[1][1], o[2] == outs[1][2], ulp,
                abs(o[2] - outs[1][2]) / abs(outs[1][2]),
                o[3] == outs[1][3], o[4] == outs[1][4])
    end
    ls = Float64[]; pxs = Vector{Float64}[]; pzs = Vector{Float64}[]
    for _ in 1:4
        g1 = mkb(true, a1); g2 = mkb(true, a2)
        push!(ls, collide!(solver, g1, g2, O.CUDABackend)); CU.synchronize()
        push!(pxs, Array(g1.rep.px)); push!(pzs, Array(g1.rep.pz))
    end
    @printf("    CUDA 4 runs: lum bitwise %s (spread %.1f ulp) ; px bitwise %s (rel %.2e) ; pz bitwise %s (rel %.2e)\n",
            all(==(ls[1]), ls), (maximum(ls) - minimum(ls)) / eps(abs(ls[1])),
            all(p -> p == pxs[1], pxs), maximum(reld(p, pxs[1]) for p in pxs),
            all(p -> p == pzs[1], pzs), maximum(reld(p, pzs[1]) for p in pzs))
end

println()
println("transverse map, same comparison")
for (label, n, sl, bim) in (
        ("8 slices, equal_count, n=4000", 4000,
         LongitudinalSlicing(nslices=8, method=:equal_count), false),)
    a1 = mkrep(n; seed=0.0, bimodal=bim); a2 = mkrep(n; seed=1.7, bimodal=bim)
    solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), longitudinal_kick=false, slicing=sl)
    outs = map(unique((1, 2, Threads.nthreads(:default)))) do k
        c1 = mkb(false, a1); c2 = mkb(false, a2)
        l = workers(k, c1.rep) do; collide!(solver, c1, c2, CPUThreadsBackend) end
        (k, l, copy(c1.rep.px))
    end
    for o in outs[2:end]
        @printf("    CPU %d vs %d workers: lum bitwise %s (%.1f ulp) ; px bitwise %s\n",
                o[1], outs[1][1], o[2] == outs[1][2],
                abs(o[2] - outs[1][2]) / eps(abs(outs[1][2])), o[3] == outs[1][3])
    end
    ls = Float64[]; pxs = Vector{Float64}[]
    for _ in 1:4
        g1 = mkb(true, a1); g2 = mkb(true, a2)
        push!(ls, collide!(solver, g1, g2, O.CUDABackend)); CU.synchronize()
        push!(pxs, Array(g1.rep.px))
    end
    @printf("    CUDA 4 runs: lum bitwise %s (spread %.1f ulp) ; px bitwise %s (rel %.2e)\n",
            all(==(ls[1]), ls), (maximum(ls) - minimum(ls)) / eps(abs(ls[1])),
            all(p -> p == pxs[1], pxs), maximum(reld(p, pxs[1]) for p in pxs))
end
