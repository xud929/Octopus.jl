### U7 probe 12: BPMObserver reading cost on a CUDA beam, each timer warmed.
using Octopus, Printf
if !(Octopus._HAS_CUDA && Octopus.CUDA.functional())
    println("CUDA not functional"); exit(0)
end
using .Octopus.CUDA

const CTX = Octopus.TrackingContext(turn = 0)
timeit(f, reps) = (f(); CUDA.synchronize();
                   t = @elapsed (for _ in 1:reps; f(); end; CUDA.synchronize()); 1e3 * t / reps)

for N in (250_000, 1_000_000, 2_560_000)
    z() = CUDA.zeros(Float64, N)
    d = Phase6DRep(CUDA.fill(1.0e-4, N), z(), CUDA.fill(2.0e-4, N), z(), z(), z())
    bpm = BPMObserver("g")
    mo = MomentObserver(tempname() * ".h5"; orders = 1)
    mom = (Moment(x = 1), Moment(y = 1))
    t_bpm = timeit(() -> Octopus.observe!(bpm, CTX, d), 10)
    t_cen = timeit(() -> Octopus._bpm_centroid(d), 10)
    t_cpy = timeit(() -> Octopus._host_coordinate_arrays(d), 10)
    t_dev = timeit(() -> (sum(d.x), sum(d.y)), 10)
    t_mom = timeit(() -> Octopus._moment_observer_row(CTX, d, mom, mo), 10)
    @printf("N=%-9d observe!=%7.2f ms  _bpm_centroid=%7.2f ms  host copy(6 arrays)=%7.2f ms  device sum(x)+sum(y)=%5.3f ms  MomentObserver 2 means=%5.3f ms   BPM/Moment=%6.0fx\n",
            N, t_bpm, t_cen, t_cpy, t_dev, t_mom, t_bpm / t_mom)
    empty!(bpm.turns); empty!(bpm.x); empty!(bpm.y)
    d = nothing; GC.gc(); CUDA.reclaim()
end
