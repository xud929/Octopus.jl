using Octopus
using Octopus: CUDABackend, CPUThreadsBackend
import CUDA

const O = Octopus

mkbeam(n, backend, rng_id, sig) = Beam(n, backend, Float64;
    beta=(0.55,0.056,12.7), alpha=(0.0,0.0,0.0),
    sigma=sig, cutoff=5.0, rng_id=rng_id,
    charge=-1.0, mc2=O.EMASS_EV, E0=10e9, r0=O.RE, npart=1.7e11)

const SIG1 = (106e-6, 9.5e-6, 0.7e-2)
const SIG2 = (95e-6, 8.5e-6, 0.7e-2)

slc = LongitudinalSlicing(nslices=4, method=:equal_count)

function run_case(label, backend, solver; n=4000)
    O.set_global_rng!(seed=12345, method=:philox)
    b1 = mkbeam(n, backend, 1, SIG1)
    b2 = mkbeam(n, backend, 2, SIG2)
    sink = Any[]
    lum = Base.ScopedValues.with(O._ACTIVE_PIC_LUMINOSITY_PAIR_SINK => sink) do
        collide!(solver, b1, b2, backend)
    end
    backend === CUDABackend && CUDA.synchronize()
    println(rpad(label, 46), " lum=", lum, "  sink_records=", length(sink))
    return sink
end

base = (kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(16,16), slicing=slc)

println("--- per-pair luminosity sink population ---")
run_case("CPU  sequential (default flags)", CPUThreadsBackend,
         PICPoissonSolver(; base..., batch_mode=:sequential))
run_case("CPU  wavefront", CPUThreadsBackend,
         PICPoissonSolver(; base..., batch_mode=:wavefront))
run_case("CUDA sequential cuda_async=false", CUDABackend,
         PICPoissonSolver(; base..., batch_mode=:sequential, cuda_async=false))
run_case("CUDA sequential cuda_async=true", CUDABackend,
         PICPoissonSolver(; base..., batch_mode=:sequential, cuda_async=true))
run_case("CUDA wavefront full indexed (default)", CUDABackend,
         PICPoissonSolver(; base..., batch_mode=:wavefront))
run_case("CUDA wavefront indexed=false", CUDABackend,
         PICPoissonSolver(; base..., batch_mode=:wavefront, cuda_indexed_wavefront=false))
run_case("CUDA wavefront wavefront_fft=false", CUDABackend,
         PICPoissonSolver(; base..., batch_mode=:wavefront, cuda_wavefront_fft=false))
run_case("CUDA wavefront async=false", CUDABackend,
         PICPoissonSolver(; base..., batch_mode=:wavefront, cuda_async=false))
