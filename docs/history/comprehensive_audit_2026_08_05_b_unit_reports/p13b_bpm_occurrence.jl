### U7 probe 13b: a peek at `bpm_reading(bpm, x, y, turn)` from inside the turn
### loop consumes an occurrence index and changes what the BPM then records.
using Octopus
mkrep() = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])

struct Peek <: Octopus.AbstractBeamAction
    bpm::BPMObserver
    on::Bool
end
Octopus.apply_action!(a::Peek, ctx, rep) =
    (a.on && bpm_reading(a.bpm, 0.0, 0.0, ctx.turn); nothing)

function run(peek::Bool)
    Octopus.set_global_rng!(seed = 4242)
    b = BPMObserver("x"; x_noise = 1.0e-5, rng_id = 77)
    t = TrackingTask((DriftSpec(L = 1.0),); hooks = (Peek(b, peek), ScheduledObserver(b)))
    execute!(t, mkrep(); turns = 4)
    return copy(b.x)
end
a = run(false); c = run(true)
println("recorded readings, no peek : ", a)
println("recorded readings, w/ peek : ", c)
println("identical = ", a == c)
println("(false => a read-only convenience call changed the recorded noise stream)")
