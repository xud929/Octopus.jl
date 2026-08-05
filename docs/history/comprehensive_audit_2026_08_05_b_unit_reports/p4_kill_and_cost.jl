### U7 probe 4: (a) SIGKILL a writer mid-run and see what the file is worth;
###              (b) cost of the JLD2 whole-dataset rewrite vs the binary append.
using Octopus
const OUT = @__DIR__
const CHILD = joinpath(OUT, "p3_child_writer.jl")
const PROJ = "/cfs/ad/dxu/Library/Julia/Octopus"

function readable_rows(fmt, path)
    isfile(path) || return (:missing_file, -1)
    try
        if fmt == "jld2"
            return Octopus.JLD2.jldopen(path, "r") do f
                haskey(f, "data") || return (:no_data_key, -1)
                (:ok, size(f["data"], 1))
            end
        elseif fmt == "bin"
            filesize(path) < 8 && return (:too_short, -1)
            return open(path, "r") do io
                n = Int(read(io, Int32)); fl = Int(read(io, Int32))
                fmtstr = String(read(io, fl)); ncols = count(==(','), fmtstr) + 1
                ondisk = div(filesize(path) - 8 - fl, ncols * 8)
                n > ondisk ? (:count_exceeds_rows, n) : (:ok, n)
            end
        else
            return Octopus.HDF5.h5open(path, "r") do f
                (:ok, Int(read(f["record_count"])[1]))
            end
        end
    catch e
        return (Symbol("throw_" * string(nameof(typeof(e)))), -1)
    end
end

println("="^72)
println("(a) SIGKILL during a 400-turn capacity=1 run; what survives")
println("="^72)
for fmt in ("jld2", "bin", "h5")
    tally = Dict{Symbol,Int}()
    rows = Int[]
    for trial in 1:12
        path = joinpath(OUT, "kill_$(fmt)_$(trial)" * (fmt == "h5" ? ".h5" : ".dat"))
        rm(path; force = true)
        cmd = `julia --startup-file=no --project=$PROJ $CHILD $fmt $path 400`
        p = open(cmd, "r")
        # wait until the package is loaded and tracking has begun
        line = ""
        while !eof(p) && line != "READY"
            line = readline(p)
        end
        sleep(0.30 + 0.06 * trial)     # land inside the write loop
        kill(p, 9)
        try; wait(p); catch; end
        st, n = readable_rows(fmt, path)
        tally[st] = get(tally, st, 0) + 1
        n >= 0 && push!(rows, n)
        rm(path; force = true)
    end
    println("  ", rpad(fmt, 5), " outcomes=", tally, "  rows_recovered=", rows)
end

println()
println("="^72)
println("(b) wall time vs number of buffered flushes (capacity=1)")
println("="^72)
function timed(fmt, nturns)
    path = joinpath(OUT, "cost_$fmt" * (fmt == "h5" ? ".h5" : fmt == "jld2" ? ".jld2" : ".dat"))
    rm(path; force = true)
    obs = fmt == "jld2" ? JLD2BeamMomentObserver(path; capacity = 1) :
          fmt == "bin"  ? BeamMomentObserver(path; capacity = 1) :
                          MomentObserver(path; capacity = 1)
    rep = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(obs),))
    execute!(t, rep; turns = 5)                       # warm up / compile
    obs2 = fmt == "jld2" ? JLD2BeamMomentObserver(path; capacity = 1) :
           fmt == "bin"  ? BeamMomentObserver(path; capacity = 1) :
                           MomentObserver(path; capacity = 1)
    rm(path; force = true)
    t2 = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(obs2),))
    rep2 = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    el = @elapsed execute!(t2, rep2; turns = nturns)
    sz = filesize(path); rm(path; force = true)
    return el, sz
end
for n in (250, 500, 1000, 2000)
    row = String[]
    for fmt in ("bin", "h5", "jld2")
        el, sz = timed(fmt, n)
        push!(row, "$(fmt)=$(round(el; digits=3))s/$(sz)B")
    end
    println("  turns=", lpad(n, 5), "  ", join(row, "  "))
end
