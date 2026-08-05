### U7 probe 11: deterministic mid-flush process death, then what a reader gets,
### and what a same-path retry recovers.
using Octopus
const OUT = @__DIR__
const CHILD = joinpath(OUT, "p10_child_fault.jl")
const PROJ = "/cfs/ad/dxu/Library/Julia/Octopus"

function inspect(fmt, path)
    isfile(path) || return "MISSING FILE"
    try
        if fmt == "jld2"
            return Octopus.JLD2.jldopen(path, "r") do f
                haskey(f, "data") || return "readable but NO /data key  (size=$(filesize(path)))"
                "readable, rows=$(size(f["data"],1))  size=$(filesize(path))"
            end
        elseif fmt == "bin"
            return open(path, "r") do io
                n = Int(read(io, Int32)); fl = Int(read(io, Int32))
                s = String(read(io, fl)); nc = count(==(','), s) + 1
                od = div(filesize(path) - 8 - fl, nc * 8)
                "count=$n  rows_on_disk=$od  " * (n > od ? "COUNT EXCEEDS ROWS" : "count<=rows OK")
            end
        else
            return Octopus.HDF5.h5open(path, "r") do f
                "record_count=$(Int(read(f["record_count"])[1]))  extent=$(size(f["data"],1))  size=$(filesize(path))"
            end
        end
    catch e
        return "UNREADABLE: " * string(nameof(typeof(e))) * " — " *
               first(split(sprint(showerror, e), '\n'))
    end
end

for (fmt, ext, n) in (("bin", ".dat", 40), ("h5", ".h5", 40), ("jld2", ".jld2", 40))
    path = joinpath(OUT, "f_$(fmt)$(ext)"); rm(path; force = true)
    cmd = `julia --startup-file=no --project=$PROJ $CHILD $fmt $path $n midwrite`
    ok = success(pipeline(ignorestatus(cmd); stdout = devnull, stderr = devnull))
    println(rpad(fmt, 6), " child_exited_normally=", ok)
    println("        after mid-flush death : ", inspect(fmt, path))
    rm(path; force = true)
end
