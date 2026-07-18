if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

#=
Validate that `TrackingTask` applies turn-dependent runtime updates in the
no-hook fast path.

Run from the project root:

    julia --project=. validation/tracking_task_turn_update.jl

This compares a plain weak-strong line against the same line with a no-op
observer. The no-op observer forces the planned execution path; both paths must
produce identical coordinates when `ThinStrongBeam` turn signals are updated
correctly.
=#

struct _NoopObserver <: AbstractBeamObserver end
Octopus.observe!(::_NoopObserver, ctx::TrackingContext, rep) = nothing

function _turn_signal_case(hooks)
    spec = ThinStrongBeamSpec(;
        kbb = 1.0e-4,
        beta = (1.0, 1.0),
        sigma = (1.0e-3, 1.0e-3),
        centroid_signal = LinearTurnSignal((0.0, 0.0), (1.0e-3, 0.0)),
    )
    rep = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])
    execute!(TrackingTask((spec,); hooks = hooks), rep; turns = 2)
    return rep[1]
end

fast = _turn_signal_case(())
planned = _turn_signal_case((_NoopObserver(),))
max_abs_error = maximum(abs.(fast .- planned))

println("TrackingTask turn-update validation")
println("fast path coordinate = ", fast)
println("planned path coordinate = ", planned)
println("max_abs_error = ", max_abs_error)

max_abs_error == 0.0 || error("TrackingTask fast path skipped or mismatched turn-dependent updates")
println("tracking task turn-update validation passed")
