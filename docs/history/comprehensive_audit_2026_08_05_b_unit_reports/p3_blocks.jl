using Octopus, CUDA, Random, Printf
const O = Octopus
Random.seed!(7)
T = Float64
ulps(a,b) = a==b ? 0 : abs(reinterpret(Int64,a)-reinterpret(Int64,b))

for N in (1000, 20_000)
    x  = randn(T, N) .* 1e-3 .+ 2.0e-3
    px = randn(T, N) .* 1e-4 .- 5.0e-5
    y  = randn(T, N) .* 5e-4 .+ 1.0e-3
    py = randn(T, N) .* 2e-4
    z  = randn(T, N) .* 1e-2
    pz = randn(T, N) .* 1e-4
    rep_d = O.Phase6DRep(CuArray(x), CuArray(px), CuArray(y), CuArray(py), CuArray(z), CuArray(pz))
    idx_d = CuArray(collect(1:N))
    println("### N = $N  (threads pinned to 256, only requested BLOCKS varies)")
    ref = nothing
    for blocks in (:auto, 2, 4, 8, 16, 64, 256)
        pol = O.ResolvedCUDAExecutionPolicy(0, 256, blocks)
        r = O._with_resolved_policy(pol) do
            L = O._cuda_gaussian_moment_launch(N)
            ns = O._cuda_gaussian_moment_nstats(Val(false))
            p = CUDA.zeros(T, ns, L.blocks, 1)
            (L=L, g=O._cuda_slice_transverse_moments(rep_d, idx_d, p, false, 1e-9, Val(false)))
        end
        ref === nothing && (ref = r.g)
        @printf("  blocks=%-5s eff=%3d | varx ulps=%d  covxpx ulps=%d  mpy ulps=%d  sx ulps=%d\n",
            string(blocks), r.L.blocks,
            ulps(r.g.moments.a0, ref.moments.a0), ulps(r.g.covxpx, ref.covxpx),
            ulps(r.g.mpy, ref.mpy), ulps(r.g.sx, ref.sx))
    end
end
