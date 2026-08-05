using Octopus
using Octopus: CUDABackend, CPUThreadsBackend
import CUDA
const O = Octopus

mkbeam(n, backend, rng_id, sig) = Beam(n, backend, Float64;
    beta=(0.55,0.056,12.7), alpha=(0.0,0.0,0.0), sigma=sig, cutoff=5.0,
    rng_id=rng_id, charge=-1.0, mc2=O.EMASS_EV, E0=10e9, r0=O.RE, npart=1.7e11)
const SIG1 = (106e-6, 9.5e-6, 0.7e-2); const SIG2 = (95e-6, 8.5e-6, 0.7e-2)
slc = LongitudinalSlicing(nslices=4, method=:equal_count)
base = (kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(16,16), slicing=slc)

function coords(backend, solver; n=4000, diag=nothing)
    O.set_global_rng!(seed=12345, method=:philox)
    b1 = mkbeam(n, backend, 1, SIG1); b2 = mkbeam(n, backend, 2, SIG2)
    f() = collide!(solver, b1, b2, backend)
    lum = diag === nothing ? f() :
          Base.ScopedValues.with(O._ACTIVE_STRONG_STRONG_DIAGNOSTICS => diag) do; f(); end
    backend === CUDABackend && CUDA.synchronize()
    return lum, map(Array, (b1.rep.x, b1.rep.px, b1.rep.y, b1.rep.py, b1.rep.pz))
end

maxdiff(a, b) = maximum(maximum(abs.(x .- y)) for (x, y) in zip(a, b))
scale(a) = maximum(maximum(abs.(x)) for x in a)

println("=== 1. runtime :node gate under pic_timing_detail ===")
node_wf = PICPoissonSolver(; base..., batch_mode=:wavefront, interaction_grid=:node)
detail = StrongStrongDiagnostics(pic_timing_detail=true)
try
    coords(CUDABackend, node_wf; diag=detail)
    println("  NO THROW  <-- gate absent")
catch err
    println("  ", typeof(err), ": ", first(split(sprint(showerror, err), '\n')))
end

println("=== 2. static gate: :node with a non-indexed flag set ===")
for kw in ((:cuda_indexed_wavefront, false), (:cuda_wavefront_fft, false), (:cuda_async, false))
    try
        s = PICPoissonSolver(; base..., batch_mode=:wavefront, interaction_grid=:node,
                             kw[1] => kw[2])
        coords(CUDABackend, s)
        println("  ", kw[1], "=false -> NO THROW  <-- silently degraded?")
    catch err
        println("  ", kw[1], "=false -> ", typeof(err), " (rejected)")
    end
end

println("=== 3. :node + :quadratic rejection ===")
try
    s = PICPoissonSolver(; base..., batch_mode=:wavefront, interaction_grid=:node,
                         slice_interpolation=:quadratic)
    coords(CUDABackend, s); println("  NO THROW  <-- accepted")
catch err
    println("  ", typeof(err), " (rejected)")
end

println("=== 4. CUDA run-to-run bitwise reproducibility (default wavefront) ===")
dflt = PICPoissonSolver(; base..., batch_mode=:wavefront)
l1, c1 = coords(CUDABackend, dflt)
l2, c2 = coords(CUDABackend, dflt)
println("  identical coords = ", all(a == b for (a,b) in zip(c1,c2)),
        "   maxdiff = ", maxdiff(c1,c2), "  lum equal = ", l1 == l2)

println("=== 5. pic_timing_detail changes the route: does it change results? ===")
l3, c3 = coords(CUDABackend, dflt; diag=detail)
println("  detail vs default: maxdiff = ", maxdiff(c1,c3), "  scale = ", scale(c1),
        "  rel = ", maxdiff(c1,c3)/scale(c1), "  dlum/lum = ", abs(l3-l1)/abs(l1))

println("=== 6. node sequential route runs ===")
node_seq = PICPoissonSolver(; base..., batch_mode=:sequential, interaction_grid=:node,
                            cuda_async=false)
try
    ln, cn = coords(CUDABackend, node_seq)
    lc, cc = coords(CPUThreadsBackend, node_seq)
    println("  node seq CUDA lum=", ln, " CPU lum=", lc,
            " coord rel = ", maxdiff(cn,cc)/scale(cc))
catch err
    println("  ERROR ", typeof(err), ": ", first(split(sprint(showerror, err), '\n')))
end

println("=== 7. node indexed wavefront vs CPU node ===")
try
    lg, cg = coords(CUDABackend, node_wf)
    lc, cc = coords(CPUThreadsBackend, node_wf)
    println("  node wf CUDA lum=", lg, " CPU lum=", lc,
            " coord rel = ", maxdiff(cg,cc)/scale(cc))
catch err
    println("  ERROR ", typeof(err), ": ", first(split(sprint(showerror, err), '\n')))
end
