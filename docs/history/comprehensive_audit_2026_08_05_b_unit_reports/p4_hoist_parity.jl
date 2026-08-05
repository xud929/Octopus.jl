# U11 probe 4: (d) R12 hoist equivalence on CUDA, (e) parity CPU/CUDA with
# >=8 slices + an empty slice + a dead particle, (f) accumulation ordering.
using Octopus, Printf, Test, Logging
const O = Octopus
const CU = Octopus.CUDA

reld(a, b) = maximum(abs.(vec(a) .- vec(b))) / max(maximum(abs, vec(b)), floatmin())
absd(a, b) = maximum(abs.(vec(a) .- vec(b)))

# ---- beams -----------------------------------------------------------------
# 10 equal-width slices over a BIMODAL z: the middle slices come out empty.
function mkrep(n; seed=0, dead=Int[])
    s(scale, phase) = [scale * sin(0.7 * i + phase + seed) for i in 1:n]
    z = [(i % 2 == 0 ? 1.0 : -1.0) * (1.0e-2 + 1.0e-3 * sin(0.9 * i + seed)) for i in 1:n]
    x = s(1.0e-4, 0.0); px = s(1.0e-5, 0.3); y = s(1.0e-4, 0.9); py = s(1.0e-5, 1.2)
    pz = s(1.0e-4, 2.5)
    for i in dead; pz[i] = NaN; end
    return (x, px, y, py, z, pz)
end
mkb(pol, arrs) = begin
    rep = pol === CPUThreadsBackend ? Phase6DRep(arrs...) :
          Phase6DRep((CU.CuArray(copy(a)) for a in arrs)...)
    p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=length(arrs[1]))
    B = pol === CPUThreadsBackend ? CPUThreadsBackend : O.CUDABackend
    Beam{B,typeof(p),typeof(rep)}(p, rep)
end

sl10 = LongitudinalSlicing(nslices=10, method=:equal_width)
a1 = mkrep(1200; seed=0.0); a2 = mkrep(1200; seed=1.7)
let sl = O.longitudinal_slices(Phase6DRep(a1...), sl10)
    @printf("slice populations beam1: %s (empty: %d of %d)\n",
            string(length.(sl.indices)), count(isempty, sl.indices), length(sl.indices))
end

println()
println("=== (d) R12 hoist: does the CUDA transverse map mutate x/y at all? ===")
let solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), longitudinal_kick=false, slicing=sl10)
    b1 = mkb(:gpu, a1); b2 = mkb(:gpu, a2)
    x0 = Array(b1.rep.x); y0 = Array(b1.rep.y); x0b = Array(b2.rep.x); y0b = Array(b2.rep.y)
    collide!(solver, b1, b2, O.CUDABackend); CU.synchronize()
    @printf("  beam1 x,y bit-unchanged: %s / %s ; beam2: %s / %s\n",
            Array(b1.rep.x) == x0, Array(b1.rep.y) == y0,
            Array(b2.rep.x) == x0b, Array(b2.rep.y) == y0b)
end

println("=== (d) hoisted collide! vs an explicit PRE-HOIST pair loop ===")
# Verbatim reconstruction of the pre-6a3f39ab..HEAD loop: solve the source field
# inside the pair loop, once per direction per pair (2*n1*n2 solves).
function prehoist_transverse(solver, beam1, beam2)
    slices1 = O._cuda_longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = O._cuda_longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = O._spectral_kbb1(solver, beam1, beam2); kbb2 = O._spectral_kbb2(solver, beam1, beam2)
    klum = O._spectral_luminosity_scale(solver, beam1, beam2)
    lnx, lny = solver.grid
    T = eltype(beam1.rep.x); r1 = beam1.rep; r2 = beam2.rep
    Nx, Ny = solver.grid
    lease = O._acquire_spectral_cuda_ws(T, Nx, Ny); ws = lease.workspace
    try
        Lx, Ly = O._cuda_spectral_box(solver, r1, r2)
        threads = 256; luminosity = zero(T)
        CU.fill!(ws.dropped, 0.0)
        for (_, i, j) in O._slice_collision_order(slices1, slices2)
            idx1 = slices1.indices[i]; idx2 = slices2.indices[j]
            (length(idx1) == 0 || length(idx2) == 0) && continue
            sx1 = r1.x[idx1]; sy1 = r1.y[idx1]
            sx2 = r2.x[idx2]; sy2 = r2.y[idx2]
            Exg, Eyg, hx, hy = O._cuda_spectral_field!(ws, sx1, sy1, Lx, Ly)
            a1v = T(slices1.weight[i] * kbb2)
            CU.@cuda threads=threads blocks=cld(length(idx2), threads) O._cuda_spectral_interp_scatter_kernel!(
                r2.px, r2.py, idx2, Exg, Eyg, sx2, sy2, T(Lx), T(Ly), hx, hy, Nx, Ny, a1v)
            Exg2, Eyg2, hx2, hy2 = O._cuda_spectral_field!(ws, sx2, sy2, Lx, Ly)
            a2v = T(slices2.weight[j] * kbb1)
            CU.@cuda threads=threads blocks=cld(length(idx1), threads) O._cuda_spectral_interp_scatter_kernel!(
                r1.px, r1.py, idx1, Exg2, Eyg2, sx1, sy1, T(Lx), T(Ly), hx2, hy2, Nx, Ny, a2v)
            luminosity += O._cuda_spectral_luminosity_pair(
                solver, sx1, sy1, sx2, sy2, klum, lnx, lny, ws.dropped)
        end
        return luminosity
    finally
        O._release_spectral_cuda_ws!(lease)
    end
end

let solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), longitudinal_kick=false, slicing=sl10)
    # run the SAME code twice for the nondeterminism envelope
    bA1 = mkb(:gpu, a1); bA2 = mkb(:gpu, a2)
    lA = collide!(solver, bA1, bA2, O.CUDABackend); CU.synchronize()
    bB1 = mkb(:gpu, a1); bB2 = mkb(:gpu, a2)
    lB = collide!(solver, bB1, bB2, O.CUDABackend); CU.synchronize()
    bC1 = mkb(:gpu, a1); bC2 = mkb(:gpu, a2)
    lC = prehoist_transverse(solver, bC1, bC2); CU.synchronize()
    env_px = reld(Array(bB1.rep.px), Array(bA1.rep.px))
    env_py = reld(Array(bB1.rep.py), Array(bA1.rep.py))
    hoi_px = reld(Array(bC1.rep.px), Array(bA1.rep.px))
    hoi_py = reld(Array(bC1.rep.py), Array(bA1.rep.py))
    @printf("  run-to-run  (same code)  px %.3e  py %.3e  lum %.3e\n",
            env_px, env_py, abs(lB - lA) / abs(lA))
    @printf("  hoist vs pre-hoist       px %.3e  py %.3e  lum %.3e\n",
            hoi_px, hoi_py, abs(lC - lA) / abs(lA))
    @printf("  bitwise equal (hoist vs pre-hoist): px %s  lum %s\n",
            Array(bC1.rep.px) == Array(bA1.rep.px), lC == lA)
    @printf("  bitwise equal (run vs run)        : px %s  lum %s\n",
            Array(bB1.rep.px) == Array(bA1.rep.px), lB == lA)
end

println()
println("=== (c) CPU/CUDA parity: 10 slices, empty slices, no dead particle ===")
for lk in (false, true)
    solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), longitudinal_kick=lk, slicing=sl10)
    c1 = mkb(CPUThreadsBackend, a1); c2 = mkb(CPUThreadsBackend, a2)
    g1 = mkb(:gpu, a1); g2 = mkb(:gpu, a2)
    lc = collide!(solver, c1, c2, CPUThreadsBackend)
    lg = collide!(solver, g1, g2, O.CUDABackend); CU.synchronize()
    worst = 0.0; which = ""
    for (cb, gb) in ((c1, g1), (c2, g2)), (nm, e, a) in zip(
            (:x, :px, :y, :py, :z, :pz), coordinate_arrays(cb.rep), coordinate_arrays(gb.rep))
        d = reld(Array(a), e)
        d > worst && (worst = d; which = string(nm))
    end
    @printf("  longitudinal_kick=%-5s max rel coord diff %.3e (%s)   lum rel diff %.3e\n",
            lk, worst, which, abs(lg - lc) / abs(lc))
end

println("=== (c) CPU/CUDA parity: 10 slices + 6 dead particles (allow_lost_particles) ===")
let d1 = mkrep(1200; seed=0.0, dead=[3, 17, 400]), d2 = mkrep(1200; seed=1.7, dead=[9, 250, 1100])
    for lk in (false, true)
        solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
            grid=(32, 32), longitudinal_kick=lk, slicing=sl10)
        c1 = mkb(CPUThreadsBackend, d1); c2 = mkb(CPUThreadsBackend, d2)
        g1 = mkb(:gpu, d1); g2 = mkb(:gpu, d2)
        lc = allow_lost_particles() do; collide!(solver, c1, c2, CPUThreadsBackend) end
        lg = allow_lost_particles() do; collide!(solver, g1, g2, O.CUDABackend) end
        CU.synchronize()
        worst = 0.0; which = ""
        for (cb, gb) in ((c1, g1), (c2, g2)), (nm, e, a) in zip(
                (:x, :px, :y, :py, :z, :pz), coordinate_arrays(cb.rep), coordinate_arrays(gb.rep))
            ea = Array(a)
            m = isfinite.(e) .& isfinite.(ea)
            d = any(m) ? reld(ea[m], e[m]) : 0.0
            nanmatch = isnan.(e) == isnan.(ea)
            d > worst && (worst = d; which = string(nm))
            nanmatch || @printf("    NaN pattern MISMATCH in %s\n", nm)
        end
        @printf("  longitudinal_kick=%-5s max rel coord diff %.3e (%s)   lum rel diff %.3e\n",
                lk, worst, which, abs(lg - lc) / abs(lc))
    end
end

println()
println("=== (e) accumulation ordering ===")
let solver = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), slicing=sl10)
    workers(f, k, rep) = O._with_execution_policy(f,
        O._resolve_execution_policy(CPUThreadsExecutionPolicy(threads=k), rep))
    outs = map(unique((1, 2, Threads.nthreads(:default)))) do k
        c1 = mkb(CPUThreadsBackend, a1); c2 = mkb(CPUThreadsBackend, a2)
        l = workers(k, c1.rep) do; collide!(solver, c1, c2, CPUThreadsBackend) end
        (k, l, copy(c1.rep.px))
    end
    for o in outs[2:end]
        @printf("  CPU 6D lum, %d workers vs %d: bitwise %s, |ulp| %.1f ; px bitwise %s\n",
                o[1], outs[1][1], o[2] == outs[1][2],
                abs(o[2] - outs[1][2]) / eps(abs(outs[1][2])), o[3] == outs[1][3])
    end
    # CUDA: strictly sequential accumulation, but atomic deposits
    ls = Float64[]; pxs = []
    for _ in 1:4
        g1 = mkb(:gpu, a1); g2 = mkb(:gpu, a2)
        push!(ls, collide!(solver, g1, g2, O.CUDABackend)); CU.synchronize()
        push!(pxs, Array(g1.rep.px))
    end
    @printf("  CUDA 6D lum over 4 runs: all equal %s, spread %.3e rel (%.1f ulp)\n",
            all(==(ls[1]), ls), (maximum(ls) - minimum(ls)) / abs(ls[1]),
            (maximum(ls) - minimum(ls)) / eps(abs(ls[1])))
    @printf("  CUDA 6D px  over 4 runs: all equal %s, max rel spread %.3e\n",
            all(p -> p == pxs[1], pxs), maximum(reld(p, pxs[1]) for p in pxs))
end
