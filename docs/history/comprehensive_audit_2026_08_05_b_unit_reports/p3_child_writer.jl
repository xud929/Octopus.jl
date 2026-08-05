### Child process for the kill-during-write probe. ARGS: <format> <path> <turns>
using Octopus
fmt, path, nturns = ARGS[1], ARGS[2], parse(Int, ARGS[3])
obs = fmt == "jld2" ? JLD2BeamMomentObserver(path; capacity = 1) :
      fmt == "bin"  ? BeamMomentObserver(path; capacity = 1) :
      fmt == "h5"   ? MomentObserver(path; capacity = 1, append = true) :
      error("format")
rep = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(obs),))
println("READY"); flush(stdout)
execute!(t, rep; turns = nturns)
println("DONE"); flush(stdout)
