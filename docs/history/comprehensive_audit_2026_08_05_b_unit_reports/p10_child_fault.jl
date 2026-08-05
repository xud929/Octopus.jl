### Deterministic fault injection child. ARGS: <format> <path> <turns> <fault>
### fault = "none" | "midwrite"  (hard _exit inside the flush's rewrite window)
using Octopus
fmt, path, nturns, fault = ARGS[1], ARGS[2], parse(Int, ARGS[3]), ARGS[4]

const HITS = Ref(0)
hard_exit() = ccall(:_exit, Cvoid, (Cint,), 137)

if fault == "midwrite"
    if fmt == "jld2"
        # A process death between `delete!` and the re-write is exactly the
        # window `_jld2_replace!` leaves open on every flush.
        function Octopus._jld2_replace!(file, key::AbstractString, value)
            haskey(file, key) && delete!(file, key)
            HITS[] += 1
            HITS[] >= 21 && key == "data" && hard_exit()
            file[key] = value
            return nothing
        end
    elseif fmt == "bin"
        # Death between the row write and the count update.
        function Octopus._flush_moment_buffer!(o::BeamMomentObserver)
            isempty(o.buffer) && return nothing
            open(o.path, "r+") do io
                seek(io, 4); fl = Int(read(io, Int32))
                rb = (1 + length(first(o.buffer))) * sizeof(Float64)
                seek(io, 8 + fl + o.record_count * rb)
                for (turn, row) in zip(o.buffer_turns, o.buffer)
                    write(io, Float64(turn)); write(io, Float64.(row))
                end
                HITS[] += 1
                HITS[] >= 11 && (flush(io); hard_exit())
                o.record_count += length(o.buffer)
                seekstart(io); write(io, Int32(o.record_count))
            end
            empty!(o.buffer_turns); empty!(o.buffer)
            return nothing
        end
    else
        # Death between the /data hyperslab write and /record_count.
        function Octopus._flush_moment_observer!(o::MomentObserver)
            o.buffer_length == 0 && return nothing
            r1 = o.record_count + 1; r2 = o.record_count + o.buffer_length
            Octopus.HDF5.h5open(o.path, "r+") do file
                file["data"][r1:r2, :] = o.buffer[1:o.buffer_length, :]
                HITS[] += 1
                HITS[] >= 11 && (Octopus.HDF5.flush(file); hard_exit())
                file["record_count"][1] = Int64(r2)
                Octopus.HDF5.flush(file)
            end
            o.record_count = r2; o.buffer_length = 0
            return nothing
        end
    end
end

obs = fmt == "jld2" ? JLD2BeamMomentObserver(path; capacity = 1) :
      fmt == "bin"  ? BeamMomentObserver(path; capacity = 1) :
                      MomentObserver(path; capacity = 1, append = true)
rep = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(obs),))
execute!(t, rep; turns = nturns)
println("DONE")
