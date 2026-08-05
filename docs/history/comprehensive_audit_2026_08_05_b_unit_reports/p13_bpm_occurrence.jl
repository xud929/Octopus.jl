### U7 probe 13: the convenience `bpm_reading(bpm, x, y, turn)` mutates the
### observer's occurrence counter, so it perturbs a live observer's noise.
using Octopus
mkrep() = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
line = (DriftSpec(L = 1.0),)

function run(peek::Bool)
    Octopus.set_global_rng!(seed = 4242)
    b = BPMObserver("x"; x_noise = 1.0e-5, rng_id = 77)
    struct_peek = peek
    t = TrackingTask(line; hooks = (ScheduledObserver(b),))
    for turn in 0:3
        # a user "peeking" at what the BPM would read, before the turn runs
        peek && bpm_reading(b, 0.0, 0.0, turn)
        execute!(t, mkrep(); turns = 1)
    end
    return copy(b.x)
end
a = run(false)
c = run(true)
println("readings without a peek : ", a)
println("readings with    a peek : ", c)
println("identical = ", a == c, "   (the peek shifted the occurrence index)")
