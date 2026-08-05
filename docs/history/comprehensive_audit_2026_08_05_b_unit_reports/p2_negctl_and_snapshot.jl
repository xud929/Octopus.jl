### U7 probe 2:
###  (a) NEGATIVE CONTROL for the four-format discard: the discard methods are
###      overwritten with pre-fix no-ops and scenario (C) is re-run.
###  (b) CoordinateSnapshotObserver at its DEFAULT append=true onto a file that
###      already holds records written by somebody else.
using Octopus
const OUT = @__DIR__

struct StampAction <: Octopus.AbstractBeamAction end
Octopus.apply_action!(::StampAction, ctx::Octopus.TrackingContext, rep) =
    (rep.x[1] = Float64(ctx.turn); nothing)

mkrep() = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
const LINE = (DriftSpec(L = 1.0),)

lum_turns(p) = [tryparse(Int, first(split(l, '\t'))) for l in readlines(p) if !isempty(strip(l))]
jld2_turns(p) = Octopus.JLD2.jldopen(f -> Int.(f["data"][:, 1]), p, "r")
function bin_turns(p)
    open(p, "r") do io
        n = Int(read(io, Int32)); fl = Int(read(io, Int32))
        fmt = String(read(io, fl)); ncols = count(==(','), fmt) + 1
        [(seek(io, 8 + fl + (i - 1) * ncols * 8); Int(read(io, Float64))) for i in 1:n]
    end
end
function snap_turns(p)
    (isfile(p) && filesize(p) > 0) || return Int[]
    out = Int[]
    open(p, "r") do io
        while !eof(io)
            n = Int(read(io, UInt32))
            xs = Vector{Float64}(undef, n); read!(io, xs); skip(io, 5 * n * 8)
            push!(out, Int(xs[1]))
        end
    end
    out
end

function scenario_C(obs, path, readback)
    t = TrackingTask(LINE; hooks = (StampAction(), ScheduledObserver(obs)))
    execute!(t, mkrep(); turns = 6)
    execute!(t, mkrep(); turns = 6, start_turn = 3)
    return readback(path)
end

println("="^72)
println("(b) CoordinateSnapshotObserver default append=true onto a NON-EMPTY file")
println("="^72)
ps = joinpath(OUT, "pre_existing.dat"); rm(ps; force=true)
# two records written by "somebody else" (turn stamps -1 and -2 in x[1])
for v in (-1.0, -2.0)
    Octopus.write_beam_coordinates(ps, Phase6DRep([v], [0.0], [0.0], [0.0], [0.0], [0.0]);
                                   append = true)
end
println("  pre-existing records: ", snap_turns(ps), "   bytes=", filesize(ps))
obs = CoordinateSnapshotObserver(ps)            # DEFAULT append=true
t = TrackingTask(LINE; hooks = (StampAction(), ScheduledObserver(obs)))
execute!(t, mkrep(); turns = 3)
println("  after execute!(turns=3):        ", snap_turns(ps), "   bytes=", filesize(ps))
println("  observer.written              = ", obs.written, "  append=", obs.append)
execute!(t, mkrep(); turns = 3, start_turn = 0) # full rewind -> discard everything it wrote
println("  after rewind prepare+run:       ", snap_turns(ps), "   bytes=", filesize(ps))
println("  observer.written              = ", obs.written, "  append=", obs.append)
println("  EXPECT [-1,-2,0,1,2]  (pre-existing records were not this object's to drop)")

println()
println("="^72)
println("(a) NEGATIVE CONTROL: discard methods replaced by pre-fix no-ops")
println("="^72)
# Overwrite the five-argument prepare hooks with the pre-fix behaviour.
Octopus.prepare_observer!(o::LuminosityObserver, re, s, t, ft) =
    (Octopus.prepare_observer!(o, re); nothing)
Octopus.prepare_observer!(o::JLD2BeamMomentObserver, re, s, t, ft) = nothing
Octopus.prepare_observer!(o::BeamMomentObserver, re, s, t, ft) = nothing
Octopus.prepare_observer!(o::CoordinateSnapshotObserver, re, s, t, ft) = nothing

p1 = joinpath(OUT, "N_lum.dat");  rm(p1; force=true)
p2 = joinpath(OUT, "N_jld2.jld2"); rm(p2; force=true)
p3 = joinpath(OUT, "N_bin.dat");  rm(p3; force=true)
p4 = joinpath(OUT, "N_snap.dat"); rm(p4; force=true)
println("  LUM  : ", scenario_C(LuminosityObserver(p1), p1, lum_turns))
println("  JLD2 : ", scenario_C(JLD2BeamMomentObserver(p2), p2, jld2_turns))
println("  BIN  : ", scenario_C(BeamMomentObserver(p3), p3, bin_turns))
println("  SNAP : ", scenario_C(CoordinateSnapshotObserver(p4), p4, snap_turns))
println("  (pre-fix expectation: duplicated labels 0..5 then 3..8)")
