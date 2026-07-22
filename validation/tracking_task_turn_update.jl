if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

#=
Validate that `TrackingTask` applies an explicit turn-dependent source action
consistently with and without a read-only observer.

Run from the project root:

    julia --project=. validation/tracking_task_turn_update.jl

The source modulation is workflow state owned by an `AbstractBeamAction`, not
state hidden inside `ThinStrongBeam`.
=#

struct _NoopObserver <: AbstractBeamObserver end
Octopus.observe!(::_NoopObserver, ctx::TrackingContext, rep) = nothing

struct _CentroidRamp{E,T} <: AbstractBeamAction
    element::E
    base::NTuple{2,T}
    slope::NTuple{2,T}
end

function Octopus.apply_action!(ramp::_CentroidRamp, ctx::TrackingContext, rep)
    ramp.element.xo = ramp.base[1] + ctx.turn * ramp.slope[1]
    ramp.element.yo = ramp.base[2] + ctx.turn * ramp.slope[2]
    return nothing
end

function _source_action_case(hooks)
    element = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb = 1.0e-4,
        beta = (1.0, 1.0),
        sigma = (1.0e-3, 1.0e-3),
    ))
    ramp = _CentroidRamp(element, (0.0, 0.0), (1.0e-3, 0.0))
    rep = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])
    execute!(TrackingTask((element,); hooks = (ramp, hooks...)), rep; turns = 2)
    return rep[1]
end

unobserved = _source_action_case(())
observed = _source_action_case((_NoopObserver(),))
max_abs_error = maximum(abs.(unobserved .- observed))

println("TrackingTask turn-update validation")
println("unobserved coordinate = ", unobserved)
println("observed coordinate = ", observed)
println("max_abs_error = ", max_abs_error)

max_abs_error == 0.0 || error("TrackingTask observer changed turn-dependent source updates")
println("tracking task turn-update validation passed")
