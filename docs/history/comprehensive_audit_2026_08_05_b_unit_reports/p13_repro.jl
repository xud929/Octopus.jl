using Octopus, CUDA, Printf
const CUDABackend = Octopus.CUDABackend
const O = Octopus
function pair(backend)
    set_global_rng!(seed=11, method=:philox)
    e = Beam(60_000, backend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0,
        mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(60_000, backend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=2, charge=1.0,
        mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=1.7e11)
    return e, p
end
sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)

function once(; kw...)
    e, p = pair(CUDABackend)
    s = PICPoissonSolver(; grid=(32,32), green_cache=:none, slicing=sl, kw...)
    l = O._with_resolved_policy(O.ResolvedCUDAExecutionPolicy(0, 256, :auto)) do
        r = collide!(s, e, p, CUDABackend); CUDA.synchronize(); r
    end
    return l, Array(e.rep.px)
end

for (tag, kw) in (
    ("wavefront, non-indexed (atomic accum luminosity kernel)",
        (batch_mode=:wavefront, cuda_indexed_wavefront=false)),
    ("wavefront, indexed (shared-mem partials luminosity kernel)",
        (batch_mode=:wavefront, cuda_indexed_wavefront=true)),
    ("sequential", (batch_mode=:sequential,)),
)
    lums = Float64[]; pxs = Vector{Vector{Float64}}()
    for _ in 1:6
        l, px = once(; kw...)
        push!(lums, l); push!(pxs, px)
    end
    lum_ident = all(==(lums[1]), lums)
    px_ident  = all(v -> v == pxs[1], pxs)
    maxabs = maximum(v -> maximum(abs, v .- pxs[1]), pxs); relmax = maxabs / maximum(abs, pxs[1])
    @printf("%-58s lum bit-identical over 6 runs: %-5s   px bit-identical: %-5s\n",
            tag, lum_ident, string(px_ident)*@sprintf(" max abs dpx=%.3e rel=%.3e", maxabs, relmax))
    if !lum_ident
        @printf("      lums: %s\n", join(map(x -> @sprintf("%.17e", x), unique(lums)), "\n            "))
        @printf("      spread/mean = %.3e\n", (maximum(lums)-minimum(lums))/abs(sum(lums)/length(lums)))
    end
end
