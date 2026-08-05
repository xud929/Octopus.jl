using Octopus
using Octopus: CUDABackend
import CUDA
const O = Octopus
mkbeam(n, backend, rng_id, sig) = Beam(n, backend, Float64;
    beta=(0.55,0.056,12.7), alpha=(0.0,0.0,0.0), sigma=sig, cutoff=5.0,
    rng_id=rng_id, charge=-1.0, mc2=O.EMASS_EV, E0=10e9, r0=O.RE, npart=1.7e11)
slc = LongitudinalSlicing(nslices=4, method=:equal_count)
s = PICPoissonSolver(kbb1=1e-6, kbb2=1e-6, luminosity_scale=1.0, grid=(16,16),
                     slicing=slc, batch_mode=:wavefront, interaction_grid=:node)
O.set_global_rng!(seed=12345, method=:philox)
b1 = mkbeam(2000, CUDABackend, 1, (106e-6,9.5e-6,0.7e-2))
b2 = mkbeam(2000, CUDABackend, 2, (95e-6,8.5e-6,0.7e-2))
before = Array(b1.rep.x)
try
    Base.ScopedValues.with(O._ACTIVE_STRONG_STRONG_DIAGNOSTICS =>
                           StrongStrongDiagnostics(pic_timing_detail=true)) do
        collide!(s, b1, b2, CUDABackend)
    end
    println("RESULT: NO THROW -- :node ran under pic_timing_detail")
catch err
    println("RESULT: ", typeof(err))
    println(sprint(showerror, err)[1:min(end,400)])
end
CUDA.synchronize()
println("beam1.x unchanged by the aborted collide = ", before == Array(b1.rep.x))
