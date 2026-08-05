### U7 probe 7: assorted leads in BeamObservers.jl.
using Octopus, Printf
const OUT = @__DIR__
mkrep() = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
const LINE = (DriftSpec(L = 1.0),)
say(tag, x) = println(rpad(tag, 46), x)

println("="^72)
println("A. MomentObserver writes HDF5 to ANY path; the reader dispatches on extension")
println("="^72)
p = joinpath(OUT, "moments.dat"); rm(p; force = true)
t = TrackingTask(LINE; hooks = (ScheduledObserver(MomentObserver(p; orders = 1)),))
execute!(t, mkrep(); turns = 3)
magic = open(io -> read(io, 8), p, "r")
say("  file magic bytes", magic)
say("  Octopus._is_hdf5_output(path)", Octopus._is_hdf5_output(p))
try
    read(MomentOutputFile(p))
    say("  read(MomentOutputFile(path))", "OK")
catch e
    say("  read(MomentOutputFile(path))", "THROWS " * string(nameof(typeof(e))))
end
rm(p; force = true)

println()
println("="^72)
println("B. MomentObserver(append=true): partial drop of an existing table is silent")
println("="^72)
p = joinpath(OUT, "part.h5"); rm(p; force = true)
o = MomentObserver(p; orders = 1, capacity = 1, append = true)
t = TrackingTask(LINE; hooks = (ScheduledObserver(o),))
execute!(t, mkrep(); turns = 10)
say("  rows after first run", size(read(MomentOutputFile(p)), 1))
o2 = MomentObserver(p; orders = 1, capacity = 1, append = true)   # FRESH task/object
t2 = TrackingTask(LINE; hooks = (ScheduledObserver(o2),))
execute!(t2, mkrep(); turns = 2, start_turn = 1)     # kept=1, 9 rows destroyed
say("  rows after fresh task, start_turn=1", size(read(MomentOutputFile(p)), 1))
say("  turn column", Int.(read(MomentOutputFile(p), :turn)))
say("  (a warning fires only when kept==0)", "")
rm(p; force = true)

println()
println("="^72)
println("C. capacity=0 leaves any previous file in place and creates none")
println("="^72)
p = joinpath(OUT, "cap0.h5"); rm(p; force = true)
t = TrackingTask(LINE; hooks = (ScheduledObserver(MomentObserver(p; orders = 1, capacity = 1)),))
execute!(t, mkrep(); turns = 4)
say("  rows written with capacity=1", size(read(MomentOutputFile(p)), 1))
t = TrackingTask(LINE; hooks = (ScheduledObserver(MomentObserver(p; orders = 1, capacity = 0)),))
execute!(t, mkrep(); turns = 4)
say("  rows after a capacity=0 re-run", size(read(MomentOutputFile(p)), 1))
say("  (stale table survives; PredicateSchedule not validated either)", "")
rm(p; force = true)

println()
println("="^72)
println("D. PredicateSchedule + MomentObserver: refused loudly?  capacity=0 variant?")
println("="^72)
for cap in (1, 0)
    p = joinpath(OUT, "pred$(cap).h5"); rm(p; force = true)
    sch = PredicateSchedule(ctx -> iseven(ctx.turn))
    t = TrackingTask(LINE; hooks = (ScheduledObserver(MomentObserver(p; capacity = cap), sch),))
    try
        execute!(t, mkrep(); turns = 4)
        say("  capacity=$cap", "NO ERROR; file exists=" * string(isfile(p)))
    catch e
        say("  capacity=$cap", "throws " * string(nameof(typeof(e))))
    end
    rm(p; force = true)
end

println()
println("="^72)
println("E. Hook output ordering is the declaration order (no Dict/Set in the path)")
println("="^72)
p1 = joinpath(OUT, "o1.dat"); p2 = joinpath(OUT, "o2.dat")
rm(p1; force = true); rm(p2; force = true)
seen = String[]
struct Tag <: Octopus.AbstractBeamObserver; s::String; sink::Vector{String}; end
Octopus.observe!(o::Tag, ctx, rep) = (push!(o.sink, o.s * "@" * string(ctx.turn)); nothing)
t = TrackingTask(LINE; hooks = [ScheduledObserver(Tag("a", seen)),
                                ScheduledObserver(Tag("b", seen), EveryNSteps(step = 2)),
                                ScheduledObserver(Tag("c", seen))])
execute!(t, mkrep(); turns = 3)
say("  observer call order", seen)

println()
println("="^72)
println("F. AtTurns schedule vs the MomentObserver plan, over a rewind")
println("="^72)
p = joinpath(OUT, "at.h5"); rm(p; force = true)
o = MomentObserver(p; orders = 1, capacity = 1, append = true)
sch = AtTurns([7, 2, 9, 4])
t = TrackingTask(LINE; hooks = (ScheduledObserver(o, sch),))
execute!(t, mkrep(); turns = 6)
say("  turns after execute!(turns=6)", Int.(read(MomentOutputFile(p), :turn)))
execute!(t, mkrep(); turns = 6, start_turn = 3)
say("  turns after rewind to 3", Int.(read(MomentOutputFile(p), :turn)))
rm(p; force = true)

println()
println("="^72)
println("G. BeamMomentObserver: does the discard survive a zero-byte file?")
println("="^72)
p = joinpath(OUT, "zb.dat"); rm(p; force = true)
o = BeamMomentObserver(p; capacity = 1)
t = TrackingTask(LINE; hooks = (ScheduledObserver(o),))
execute!(t, mkrep(); turns = 2)
open(io -> nothing, p, "w")     # emulate a crash at create time
try
    execute!(t, mkrep(); turns = 2, start_turn = 0)
    say("  zero-byte file, same object rewind", "no error; size=" * string(filesize(p)))
catch e
    say("  zero-byte file, same object rewind", "THROWS " * string(nameof(typeof(e))) *
        " : " * first(split(sprint(showerror, e), '\n')))
end
rm(p; force = true)
