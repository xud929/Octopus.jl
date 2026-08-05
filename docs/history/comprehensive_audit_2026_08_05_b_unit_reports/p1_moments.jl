using Octopus, CUDA, Random, Printf, Statistics
const O = Octopus

Random.seed!(20260805)
N = 200_003            # deliberately non-power-of-2, non-multiple of 256
T = Float64
x  = randn(T, N) .* 1e-3 .+ 2.0e-3
px = randn(T, N) .* 1e-4 .- 5.0e-5
y  = randn(T, N) .* 5e-4 .+ 1.0e-3
py = randn(T, N) .* 2e-4
z  = randn(T, N) .* 1e-2
pz = randn(T, N) .* 1e-4

rep_h = O.Phase6DRep(copy(x), copy(px), copy(y), copy(py), copy(z), copy(pz))
rep_d = O.Phase6DRep(CuArray(x), CuArray(px), CuArray(y), CuArray(py), CuArray(z), CuArray(pz))

idx_h = collect(1:N)
idx_d = CuArray(idx_h)

for COUPLED in (false, true)
    nstats = O._cuda_gaussian_moment_nstats(Val(COUPLED))
    mb = O._cuda_gaussian_moment_launch(N).blocks
    partials = CUDA.zeros(T, nstats, mb, 1)
    g = O._cuda_slice_transverse_moments(rep_d, idx_d, partials, false, 1e-9, Val(COUPLED))
    c = O._slice_transverse_moments(rep_h, idx_h, false, 1e-9, Val(COUPLED))
    println("== COUPLED=$COUPLED  blocks=$mb ==")
    for k in (:mx,:sx,:mpx,:spx,:covxpx,:my,:sy,:mpy,:spy,:covypy)
        gv = getfield(g,k); cv = getfield(c,k)
        @printf("  %-7s gpu=%.17e cpu=%.17e  relerr=%.3e ulps=%d\n", k, gv, cv,
                abs(gv-cv)/max(abs(cv),eps()), cv==gv ? 0 : Int(min(abs(reinterpret(Int64,gv)-reinterpret(Int64,cv)), 10^12)))
    end
    mg = g.moments; mc = c.moments
    for k in fieldnames(typeof(mc))
        gv = getfield(mg,k); cv = getfield(mc,k)
        @printf("  M.%-8s gpu=%.17e cpu=%.17e relerr=%.3e\n", k, gv, cv,
                abs(gv-cv)/max(abs(cv),eps()))
    end
end

# --- reference: independent population moments in extended precision -------
using Base.MathConstants
bigx = big.(x); bigpx = big.(px); bigy = big.(y); bigpy = big.(py)
mxr = sum(bigx)/N; mpxr = sum(bigpx)/N; myr = sum(bigy)/N; mpyr = sum(bigpy)/N
varxr = sum((bigx.-mxr).^2)/N
varyr = sum((bigy.-myr).^2)/N
covxpxr = sum((bigx.-mxr).*(bigpx.-mpxr))/N
covypyr = sum((bigy.-myr).*(bigpy.-mpyr))/N
println("== BigFloat population reference (denominator n) ==")
@printf("  mx=%.17e varx=%.17e sx=%.17e\n", Float64(mxr), Float64(varxr), Float64(sqrt(varxr)))
@printf("  my=%.17e vary=%.17e sy=%.17e\n", Float64(myr), Float64(varyr), Float64(sqrt(varyr)))
@printf("  covxpx=%.17e covypy=%.17e\n", Float64(covxpxr), Float64(covypyr))
@printf("  (n-1) varx would be %.17e\n", Float64(sum((bigx.-mxr).^2)/(N-1)))
