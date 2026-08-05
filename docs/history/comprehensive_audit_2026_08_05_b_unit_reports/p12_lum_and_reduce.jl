using Octopus, CUDA, Printf, Random
const O = Octopus
T = Float64

println("### A. luminosity overlap tree reduction vs blockDim (guard is ispow2)")
nx = Int32(9); ny = Int32(7); npairs = Int32(1)
q1 = CUDA.ones(T, Int(nx), Int(ny), 1)
q2 = CUDA.ones(T, Int(nx), Int(ny), 1)
scale = CUDA.ones(T, 1)
exact = T(Int(nx) * Int(ny))
for threads in (16, 24, 32, 48, 64, 96, 128)
    bpp = cld(Int(nx)*Int(ny), threads)
    partials = CUDA.zeros(T, bpp * Int(npairs))
    CUDA.@cuda threads=threads blocks=bpp*Int(npairs) shmem=threads*sizeof(T) O._cuda_pic_luminosity_overlap_partials_kernel!(
        partials, q1, q2, scale, nx, ny, Int32(bpp), npairs)
    CUDA.synchronize()
    got = sum(Array(partials))
    @printf("  threads=%-4d ispow2=%-5s  sum=%8.1f  exact=%8.1f  %s\n",
        threads, ispow2(threads), got, exact,
        got == exact ? "ok" : "*** LOSES $(exact-got) OF THE OVERLAP ***")
end

println()
println("### B. cross-block reduction: host `sum(dims=2)` vs device reduce kernel")
Random.seed!(3)
nstats = 14; nblocks = 37
hp = randn(T, nstats, nblocks) .* 1e-3
dp = CuArray(reshape(hp, nstats, nblocks, 1))
host = vec(sum(hp; dims=2))
sums_d = CUDA.zeros(T, nstats, 1)
bc = CuArray(Int32[nblocks])
CUDA.@cuda threads=64 blocks=1 O._cuda_gaussian_reduce_partials_kernel!(sums_d, dp, bc, nstats, 1)
CUDA.synchronize()
dev = vec(Array(sums_d))
serial = [foldl(+, hp[s, :]) for s in 1:nstats]
nd_hd = count(i -> host[i] != dev[i], 1:nstats)
nd_hs = count(i -> host[i] != serial[i], 1:nstats)
@printf("  stats where host sum(dims=2) != device reduce kernel : %d / %d\n", nd_hd, nstats)
@printf("  stats where host sum(dims=2) != left-to-right foldl   : %d / %d\n", nd_hs, nstats)
for s in 1:nstats
    host[s] == dev[s] && continue
    @printf("    stat %2d host=%.17e dev=%.17e ulps=%d\n", s, host[s], dev[s],
            abs(reinterpret(Int64, host[s]) - reinterpret(Int64, dev[s])))
end
