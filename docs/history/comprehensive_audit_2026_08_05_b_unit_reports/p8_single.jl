# U11 probe 8: does field_precision=:single reach beyond the field solve?
# `_cuda_spectral_luminosity_idx_snap!` is parameterised on the WORKSPACE type,
# so in :single its extents, grid spacing and overlap sum are Float32; the
# transverse `_cuda_spectral_luminosity_pair` uses eltype(x1) = Float64.
# The 6D kick scale T(kbb_slice) in `_cuda_spectral_collision_direction_6d*!`
# is likewise the workspace type.
using Octopus, Printf
const O = Octopus
const CU = Octopus.CUDA

function mkarrs(n, seed)
    s(sc, ph) = [sc * sin(0.7 * i + ph + seed) for i in 1:n]
    (s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2),
     [2.0e-2 * sin(0.7 * i + 2.0 + seed) for i in 1:n], s(1.0e-4, 2.5))
end
mkb(gpu, arrs) = begin
    rep = gpu ? Phase6DRep((CU.CuArray(copy(a)) for a in arrs)...) :
                Phase6DRep((copy(a) for a in arrs)...)
    p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=1.7e11)
    B = gpu ? O.CUDABackend : CPUThreadsBackend
    Beam{B,typeof(p),typeof(rep)}(p, rep)
end
a1 = mkarrs(4000, 0.0); a2 = mkarrs(4000, 1.7)
sl = LongitudinalSlicing(nslices=8, method=:equal_count)

for lk in (false, true)
    ref = nothing
    for fp in (:double, :single)
        sv = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, grid=(32, 32),
            longitudinal_kick=lk, field_precision=fp, slicing=sl)
        g1 = mkb(true, a1); g2 = mkb(true, a2)
        l = collide!(sv, g1, g2, O.CUDABackend); CU.synchronize()
        if fp === :double
            ref = l
            @printf("  lk=%-5s :double luminosity = %.17g\n", lk, l)
        else
            @printf("  lk=%-5s :single luminosity = %.17g   rel diff %.3e\n",
                    lk, l, abs(l - ref) / abs(ref))
        end
    end
end
println()
println("Float32 eps = ", eps(Float32), " ; a :single 6D luminosity carries ~1e-7 relative.")
