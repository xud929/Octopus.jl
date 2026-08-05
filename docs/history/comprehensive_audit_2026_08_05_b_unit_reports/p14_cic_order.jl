using Random, Printf
Random.seed!(5)
# CPU `_pic_interpolate_kick` accumulates `for m in eachindex(wx), n in eachindex(wy)`
#   -> (1,1), (1,2), (2,1), (2,2)      [x-index OUTER]
# CUDA `_cuda_pic_interpolate_kick` / `_cuda_pic_interpolate_field` CIC branch is
# hand-unrolled as
#   -> (1,1), (2,1), (1,2), (2,2)      [y-index OUTER]
# The two middle terms are swapped.  The TSC branch of BOTH backends uses
# `for m in 1:3, n in 1:3`, so only CIC diverges.
cpu(t11,t12,t21,t22) = ((zero(t11) + t11) + t12 + t21) + t22
gpu(t11,t12,t21,t22) = ((zero(t11) + t11) + t21 + t12) + t22

ndiff = 0; maxulp = 0; maxrel = 0.0
N = 2_000_00
for _ in 1:N
    wx1 = rand(); wx2 = 1 - wx1
    wy1 = rand(); wy2 = 1 - wy1
    E = randn(4) .* 1e3
    t11 = wx1*wy1*E[1]; t21 = wx2*wy1*E[2]; t12 = wx1*wy2*E[3]; t22 = wx2*wy2*E[4]
    a = cpu(t11,t12,t21,t22); b = gpu(t11,t12,t21,t22)
    if a != b
        global ndiff += 1
        u = abs(reinterpret(Int64,a) - reinterpret(Int64,b))
        global maxulp = max(maxulp, u)
        global maxrel = max(maxrel, abs(a-b)/max(abs(a),abs(b)))
    end
end
@printf("CIC 4-term accumulation, CPU nesting vs CUDA unroll:\n")
@printf("  differing samples : %d / %d  (%.1f%%)\n", ndiff, N, 100*ndiff/N)
@printf("  max ulp gap       : %d\n", maxulp)
@printf("  max relative gap  : %.3e\n", maxrel)
