### U7 probe 8: SIGKILL a writer that is definitely still inside the write loop.
### Per-format turn counts are sized so the run lasts several seconds.
using Octopus
const OUT = @__DIR__
const CHILD = joinpath(OUT, "p3_child_writer.jl")
const PROJ = "/cfs/ad/dxu/Library/Julia/Octopus"

function inspect(fmt, path)
    isfile(path) || return (:missing_file, -1, -1)
    try
        if fmt == "jld2"
            return Octopus.JLD2.jldopen(path, "r") do f
                haskey(f, "data") || return (:no_data_key, -1, filesize(path))
                (:ok, size(f["data"], 1), filesize(path))
            end
        elseif fmt == "bin"
            filesize(path) < 8 && return (:too_short, -1, filesize(path))
            return open(path, "r") do io
                n = Int(read(io, Int32)); fl = Int(read(io, Int32))
                s = String(read(io, fl)); ncols = count(==(','), s) + 1
                ondisk = div(filesize(path) - 8 - fl, ncols * 8)
                (n > ondisk ? :COUNT_EXCEEDS_ROWS : :ok, n, ondisk)
            end
        else
            return Octopus.HDF5.h5open(path, "r") do f
                (:ok, Int(read(f["record_count"])[1]), filesize(path))
            end
        end
    catch e
        return (Symbol("throw_" * string(nameof(typeof(e)))), -1, filesize(path))
    end
end

for (fmt, nturns, ext) in (("bin", 400_000, ".dat"), ("h5", 30_000, ".h5"),
                           ("jld2", 3_000, ".jld2"))
    println("--- ", fmt, "  (", nturns, " turns) ---")
    for trial in 1:6
        path = joinpath(OUT, "k2_$(fmt)_$(trial)$(ext)"); rm(path; force = true)
        p = open(`julia --startup-file=no --project=$PROJ $CHILD $fmt $path $nturns`, "r")
        line = ""
        while !eof(p) && line != "READY"; line = readline(p); end
        sleep(0.8 + 0.4 * trial)
        kill(p, 9)
        try; wait(p); catch; end
        st, n, extra = inspect(fmt, path)
        println("   trial $trial: ", rpad(string(st), 22), " reported_rows=", lpad(n, 7),
                "  rows_or_bytes_on_disk=", extra)
        rm(path; force = true)
    end
end
