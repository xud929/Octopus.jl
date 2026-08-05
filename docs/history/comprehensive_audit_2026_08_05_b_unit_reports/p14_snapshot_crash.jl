### U7 probe 14: the U7-1 snapshot wipe on the HEADLINE case — a crashed
### execute! retried, with the file already holding somebody else's records.
using Octopus
const OUT = @__DIR__

struct Stamp <: Octopus.AbstractBeamAction end
Octopus.apply_action!(::Stamp, ctx, rep) = (rep.x[1] = Float64(ctx.turn); nothing)
mutable struct Boom <: Octopus.AbstractBeamAction; at::Int; armed::Bool; end
Octopus.apply_action!(a::Boom, ctx, rep) =
    (a.armed && ctx.turn == a.at && (a.armed = false; error("crash")); nothing)

function records(p)
    (isfile(p) && filesize(p) > 0) || return Int[]
    out = Int[]
    open(p, "r") do io
        while !eof(io)
            n = Int(read(io, UInt32)); xs = Vector{Float64}(undef, n)
            read!(io, xs); skip(io, 5 * n * 8); push!(out, Int(xs[1]))
        end
    end
    out
end

p = joinpath(OUT, "crashsnap.dat"); rm(p; force = true)
for v in (-1.0, -2.0)                                   # a previous run's records
    Octopus.write_beam_coordinates(p, Phase6DRep([v], [0.0], [0.0], [0.0], [0.0], [0.0]); append = true)
end
println("pre-existing records            : ", records(p), "  bytes=", filesize(p))

obs = CoordinateSnapshotObserver(p)                     # DEFAULT append=true
t = TrackingTask((DriftSpec(L = 1.0),);
                 hooks = (Stamp(), Boom(3, true), ScheduledObserver(obs)))
try; execute!(t, Phase6DRep([0.0],[0.0],[0.0],[0.0],[0.0],[0.0]); turns = 6); catch; end
println("after the crashed execute!      : ", records(p), "  bytes=", filesize(p))
execute!(t, Phase6DRep([0.0],[0.0],[0.0],[0.0],[0.0],[0.0]); turns = 6)   # retry from turn 0
println("after the retry                 : ", records(p), "  bytes=", filesize(p))
println("REQUIRED by _discard_replayed_snapshots!'s own docstring: [-1, -2, 0, 1, 2, 3, 4, 5]")
rm(p; force = true)
