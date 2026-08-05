### U7 probe 1: crash-and-retry idempotence for the four "continuing" observers.
### Every observer's turn labels are read back from disk after
###   (A) a clean split run  (turns 0..2 then 3..5),
###   (B) a real crash mid-window followed by a retry,
###   (C) an explicit start_turn rewind that replays an overlapping window,
### with the observers built at their DEFAULT constructor settings.
using Octopus
using Printf

const OUT = @__DIR__

# ---------------------------------------------------------------- helpers ----
struct StampAction <: Octopus.AbstractBeamAction end
function Octopus.apply_action!(::StampAction, ctx::Octopus.TrackingContext, rep)
    rep.x[1] = Float64(ctx.turn)
    return nothing
end

mutable struct CrashAt <: Octopus.AbstractBeamAction
    at::Int
    armed::Bool
end
CrashAt(at) = CrashAt(at, true)
function Octopus.apply_action!(a::CrashAt, ctx::Octopus.TrackingContext, rep)
    if a.armed && ctx.turn == a.at
        a.armed = false
        error("simulated crash at turn $(ctx.turn)")
    end
    return nothing
end

mkrep() = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])

lum_turns(p) = isfile(p) ?
    [tryparse(Int, first(split(l, '\t'))) for l in readlines(p) if !isempty(strip(l))] : Int[]

jld2_turns(p) = isfile(p) ? Octopus.JLD2.jldopen(p, "r") do f
    haskey(f, "data") ? Int.(f["data"][:, 1]) : Int[]
end : Int[]

function bin_turns(p)
    isfile(p) && filesize(p) > 0 || return Int[]
    open(p, "r") do io
        n = Int(read(io, Int32)); fl = Int(read(io, Int32))
        fmt = String(read(io, fl)); ncols = count(==(','), fmt) + 1
        [(seek(io, 8 + fl + (i - 1) * ncols * 8); Int(read(io, Float64))) for i in 1:n]
    end
end

# Snapshot records carry no turn label; StampAction put the turn in x[1].
function snap_turns(p)
    isfile(p) && filesize(p) > 0 || return Int[]
    out = Int[]
    open(p, "r") do io
        while !eof(io)
            n = Int(read(io, UInt32))
            xs = Vector{Float64}(undef, n); read!(io, xs)
            skip(io, 5 * n * 8)
            push!(out, Int(xs[1]))
        end
    end
    out
end

const LINE = (DriftSpec(L = 1.0),)

function build(kind, path)
    kind === :lum   && return LuminosityObserver(path)
    kind === :jld2  && return JLD2BeamMomentObserver(path)          # default capacity=1
    kind === :bin   && return BeamMomentObserver(path)              # default capacity=1
    kind === :snap  && return CoordinateSnapshotObserver(path)      # DEFAULT append=true
    error("kind")
end
readback(kind, p) = kind === :lum ? lum_turns(p) :
                    kind === :jld2 ? jld2_turns(p) :
                    kind === :bin ? bin_turns(p) : snap_turns(p)
ext(kind) = kind === :jld2 ? ".jld2" : ".dat"

results = Dict{Tuple{Symbol,Symbol},Any}()

for kind in (:lum, :jld2, :bin, :snap)
    # ---------------- (A) clean split run, no replay -------------------------
    pA = joinpath(OUT, "A_$(kind)$(ext(kind))"); rm(pA; force=true)
    obs = build(kind, pA)
    t = TrackingTask(LINE; hooks = (StampAction(), ScheduledObserver(obs)))
    execute!(t, mkrep(); turns = 3)
    execute!(t, mkrep(); turns = 3)
    results[(kind, :A_split)] = readback(kind, pA)

    # ---------------- (B) real crash mid-window, then retry ------------------
    pB = joinpath(OUT, "B_$(kind)$(ext(kind))"); rm(pB; force=true)
    obs = build(kind, pB)
    crash = CrashAt(4)
    t = TrackingTask(LINE; hooks = (StampAction(), crash, ScheduledObserver(obs)))
    err = nothing
    try
        execute!(t, mkrep(); turns = 8)
    catch e
        err = e
    end
    results[(kind, :B_after_crash)] = readback(kind, pB)
    results[(kind, :B_crashed)] = err !== nothing
    # retry: next_turn was NOT advanced, so this replays turns 0..7
    execute!(t, mkrep(); turns = 8)
    results[(kind, :B_after_retry)] = readback(kind, pB)

    # ---------------- (C) explicit start_turn rewind, overlapping window -----
    pC = joinpath(OUT, "C_$(kind)$(ext(kind))"); rm(pC; force=true)
    obs = build(kind, pC)
    t = TrackingTask(LINE; hooks = (StampAction(), ScheduledObserver(obs)))
    execute!(t, mkrep(); turns = 6)               # turns 0..5
    results[(kind, :C_before)] = readback(kind, pC)
    execute!(t, mkrep(); turns = 6, start_turn = 3)  # replays 3,4,5 then 6,7,8
    results[(kind, :C_after)] = readback(kind, pC)
end

println("="^72)
println("U7 PROBE 1 — four-format crash/retry turn labels (HEAD 7de4d81)")
println("="^72)
for kind in (:lum, :jld2, :bin, :snap)
    println("\n--- ", uppercase(String(kind)), " ---")
    for key in (:A_split, :B_crashed, :B_after_crash, :B_after_retry, :C_before, :C_after)
        println(@sprintf("  %-14s ", String(key)), results[(kind, key)])
    end
    ok_A = results[(kind, :A_split)] == collect(0:5)
    ok_B = results[(kind, :B_after_retry)] == collect(0:7)
    ok_C = results[(kind, :C_after)] == collect(0:8)
    println("  VERDICT  A(split 0:5)=", ok_A, "  B(retry 0:7)=", ok_B, "  C(rewind 0:8)=", ok_C)
end
