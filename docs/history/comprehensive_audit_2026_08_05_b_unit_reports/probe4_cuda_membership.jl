using Octopus
using Printf
const O = Octopus
using CUDA

rep_of(z) = O.Phase6DRep(zeros(length(z)), zeros(length(z)), zeros(length(z)),
                         zeros(length(z)), collect(float.(z)), zeros(length(z)))
rep_d(z) = O.Phase6DRep(CUDA.zeros(Float64, length(z)), CUDA.zeros(Float64, length(z)),
                        CUDA.zeros(Float64, length(z)), CUDA.zeros(Float64, length(z)),
                        CuArray(collect(float.(z))), CUDA.zeros(Float64, length(z)))

ulps(a, b) = (a == b) ? 0 : abs(reinterpret(Int64, Float64(a)) - reinterpret(Int64, Float64(b)))

function compare(tag, z, slc)
    hc = O.longitudinal_slices(rep_of(z), slc)
    dc = O._cuda_longitudinal_slices(rep_d(z), slc)
    ns = length(hc.indices)
    bnd_ulp = maximum(ulps(hc.boundary[i], dc.boundary[i]) for i in eachindex(hc.boundary))
    ctr_ulp = maximum(ulps(hc.center[i], dc.center[i]) for i in 1:ns)
    moved = 0
    for s in 1:ns
        a = Set(hc.indices[s]); b = Set(Array(dc.indices[s]))
        moved += length(symdiff(a, b))
    end
    hcounts = [length(i) for i in hc.indices]
    dcounts = [length(Array(i)) for i in dc.indices]
    lost_h = length(z) - sum(hcounts); lost_d = length(z) - sum(dcounts)
    @printf("  %-42s membership_diff=%d(/2) bnd=%d ulp ctr=%d ulp unassigned cpu=%d cuda=%d\n",
            tag, moved, bnd_ulp, ctr_ulp, lost_h, lost_d)
    if moved > 0
        @printf("      cpu counts=%s\n      gpu counts=%s\n", string(hcounts), string(dcounts))
    end
    return moved
end

for (n, quantize) in ((200000, false), (200000, true), (2000, true), (777, true))
    z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    quantize && (z = round.(z; digits=3))
    println("n=$n quantized=$quantize")
    for m in (:equal_area, :equal_count, :equal_width, :normal_quantile)
        for ns in (7, 15)
            compare("$m ns=$ns", z, O.LongitudinalSlicing(nslices=ns, method=m))
        end
    end
    compare("specified ns=3", z, O.LongitudinalSlicing(nslices=3, method=:specified, positions=[-0.5, 0.5]))
end

println("\ndegenerate z (all equal), n=7")
for m in (:equal_area, :equal_count, :equal_width, :normal_quantile)
    compare("$m ns=3", fill(0.5, 7), O.LongitudinalSlicing(nslices=3, method=m))
end

println("\nns > n (n=3, ns=7)")
for m in (:equal_area, :equal_count, :equal_width, :normal_quantile)
    compare("$m", [0.0, 1.0, 2.0], O.LongitudinalSlicing(nslices=7, method=m))
end
