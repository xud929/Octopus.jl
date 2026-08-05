### U7 probe 6: (a) §7.1 done properly (observer path, not a hand-typed centroid)
###              (b) what _bpm_centroid costs on a CUDA beam.
using Octopus, Printf
pass(b) = b ? "PASS" : "**FAIL**"

# ---- §7.1 through the real observer path -----------------------------------
n = 8
rep = Phase6DRep(collect(range(1e-3, 5e-3; length = n)), zeros(n),
                 collect(range(-2e-3, 2e-3; length = n)), zeros(n), zeros(n), zeros(n))
b = BPMObserver("zero")
t = TrackingTask((DriftSpec(L = 0.0),); hooks = (ScheduledObserver(b),))
st = beam_statistics(rep)
execute!(t, rep; turns = 1)
println("1 zero-error BPM == beam_statistics centroid, bitwise: ",
        pass(b.x[1] === st.mean[1] && b.y[1] === st.mean[3]),
        "\n   bpm=(", b.x[1], ", ", b.y[1], ")\n   mom=(", st.mean[1], ", ", st.mean[3], ")")

# ---- (b) CUDA cost ---------------------------------------------------------
if Octopus._HAS_CUDA && Octopus.CUDA.functional()
    using .Octopus.CUDA
    for N in (100_000, 1_000_000)
        z() = CUDA.zeros(Float64, N)
        d = Phase6DRep(CUDA.fill(1.0e-4, N), z(), CUDA.fill(2.0e-4, N), z(), z(), z())
        bb = BPMObserver("g")
        ctx = Octopus.TrackingContext(turn = 0)
        Octopus.observe!(bb, ctx, d); CUDA.synchronize()      # warm
        e_bpm = @elapsed (for _ in 1:20; Octopus.observe!(bb, ctx, d); end; CUDA.synchronize())
        # what a device-side two-mean reduction costs instead
        CUDA.synchronize()
        e_dev = @elapsed (for _ in 1:20; sum(d.x); sum(d.y); end; CUDA.synchronize())
        # and what the MomentObserver's device path costs for the same 2 means
        mo = MomentObserver(tempname() * ".h5"; orders = 1)
        Octopus._moment_observer_row(ctx, d, (Moment(x = 1), Moment(y = 1)), mo)
        CUDA.synchronize()
        e_mom = @elapsed (for _ in 1:20
            Octopus._moment_observer_row(ctx, d, (Moment(x = 1), Moment(y = 1)), mo)
        end; CUDA.synchronize())
        @printf("2 N=%-9d  BPM observe!=%.3f ms/read   sum(x)+sum(y)=%.3f ms   MomentObserver 2 means=%.3f ms  ratio=%.1fx\n",
                N, 1e3 * e_bpm / 20, 1e3 * e_dev / 20, 1e3 * e_mom / 20, e_bpm / e_dev)
    end
else
    println("2 CUDA not functional -- device cost UNMEASURED")
end
