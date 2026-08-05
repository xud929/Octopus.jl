using Octopus, CUDA, Printf
const O = Octopus
T = Float64

# x[i] = i  =>  dx = i - 1, exact sum = N(N-1)/2 ; dx^2 sum = sum (i-1)^2
# Any thread dropped by the shared-memory tree reduction shows as a gross error.
function check(N, threads, blocks; COUPLED=false)
    x  = CuArray(T.(1:N)); px = CUDA.zeros(T, N)
    y  = CUDA.zeros(T, N); py = CUDA.zeros(T, N)
    idx = CuArray(collect(1:N))
    ns  = O._cuda_gaussian_moment_nstats(Val(COUPLED))
    cns = O._cuda_gaussian_centered_nstats(Val(COUPLED))
    partials = CUDA.zeros(T, ns, blocks, 1)
    shmem = cns * threads * sizeof(T)
    CUDA.@cuda threads=threads blocks=blocks shmem=shmem O._cuda_gaussian_moment_partials_kernel!(
        partials, x, px, y, py, idx, 1, Val(COUPLED))
    CUDA.synchronize()
    hp = Array(partials)
    sdx  = sum(hp[1, :, 1])
    sdx2 = sum(hp[5, :, 1])
    x0   = sum(hp[cns+1, :, 1])
    exact_sdx  = T(N) * T(N - 1) / 2
    exact_sdx2 = sum(k -> T(k)^2, 0:(N-1))
    return (sdx=sdx, exact_sdx=exact_sdx, sdx2=sdx2, exact_sdx2=exact_sdx2, x0=x0)
end

println("N      threads blocks |    Sum(dx) err     Sum(dx^2) err   anchor")
for N in (1237, 100_003), threads in (1, 2, 3, 5, 7, 31, 32, 33, 96, 127, 128, 255, 256),
    blocks in (1, 3, 7, 64)
    r = check(N, threads, blocks)
    e1 = abs(r.sdx - r.exact_sdx); e2 = abs(r.sdx2 - r.exact_sdx2)
    bad = (e1 > 1e-6 * abs(r.exact_sdx)) || (e2 > 1e-6 * abs(r.exact_sdx2)) || r.x0 != 1.0
    if bad || (threads in (1,3,33,127,255) && blocks in (1,7))
        @printf("%-6d %7d %6d | %14.6e  %14.6e   %6.1f  %s\n",
            N, threads, blocks, e1, e2, r.x0, bad ? "*** MISMATCH ***" : "ok")
    end
end
println()
println("full-sweep verdict:")
badcount = 0
for N in (1237, 100_003), threads in (1,2,3,5,7,31,32,33,96,127,128,255,256), blocks in (1,3,7,64)
    r = check(N, threads, blocks)
    if abs(r.sdx - r.exact_sdx) > 1e-9*abs(r.exact_sdx) ||
       abs(r.sdx2 - r.exact_sdx2) > 1e-9*abs(r.exact_sdx2) || r.x0 != 1.0
        global badcount += 1
        @printf("  BAD N=%d threads=%d blocks=%d\n", N, threads, blocks)
    end
end
println("  configurations with a lossy reduction: ", badcount, " / ",
        2*13*4)
