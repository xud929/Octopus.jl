using Octopus, CUDA, Random, Printf
const O = Octopus

Random.seed!(20260805)
N = 200_003
T = Float64
x  = randn(T, N) .* 1e-3 .+ 2.0e-3
px = randn(T, N) .* 1e-4 .- 5.0e-5
y  = randn(T, N) .* 5e-4 .+ 1.0e-3
py = randn(T, N) .* 2e-4
z  = randn(T, N) .* 1e-2
pz = randn(T, N) .* 1e-4
rep_d = O.Phase6DRep(CuArray(x), CuArray(px), CuArray(y), CuArray(py), CuArray(z), CuArray(pz))
idx_d = CuArray(collect(1:N))

ulps(a,b) = a==b ? 0 : abs(reinterpret(Int64,a)-reinterpret(Int64,b))

function run_cfg(threads, blocks)
    pol = O.ResolvedCUDAExecutionPolicy(0, threads, blocks)
    O._with_resolved_policy(pol) do
        launch = O._cuda_gaussian_moment_launch(N)
        nstats = O._cuda_gaussian_moment_nstats(Val(false))
        partials = CUDA.zeros(T, nstats, launch.blocks, 1)
        g = O._cuda_slice_transverse_moments(rep_d, idx_d, partials, false, 1e-9, Val(false))
        return (launch=launch, g=g)
    end
end

ref = nothing
println("threads blocks | eff_threads eff_blocks |     sx ulps   covxpx ulps   mpy ulps    varx ulps")
for threads in (32, 64, 128, 256, 512), blocks in (:auto, 16, 64, 256)
    r = run_cfg(threads, blocks)
    if ref === nothing
        global ref = r.g
    end
    @printf("%7d %6s | %11d %10d | %10d %12d %10d %12d\n",
        threads, string(blocks), r.launch.threads, r.launch.blocks,
        ulps(r.g.sx, ref.sx), ulps(r.g.covxpx, ref.covxpx),
        ulps(r.g.mpy, ref.mpy), ulps(r.g.moments.a0, ref.moments.a0))
end
