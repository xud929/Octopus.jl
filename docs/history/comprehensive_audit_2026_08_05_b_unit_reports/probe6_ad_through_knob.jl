# U13 probe 6 — the claim in Knobs.jl `_eval_knob_node` ("a knob may hold a dual
# number ... `bus` feeding a whole magnet family gives the family's response in
# a single pass"): seed a ForwardDiff.Dual into a ::Real knob and track.
using Octopus, ForwardDiff

reset_knobs!()
@knob bus::Real = 1.0
f1 = ElementSpec{:crab_dispersion}(; zeta1 = @knob_expr(2.0 * bus),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0, tracking_method = Symplectic6DMap())
f2 = ElementSpec{:crab_dispersion}(; zeta1 = @knob_expr(-(0.5 * bus)),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0, tracking_method = Symplectic6DMap())
z0 = 1.0e-3

function xout(k::T) where {T}
    set_knob!(:bus, k)
    task = TrackingTask((f1, f2); policy = CPUThreadsExecutionPolicy(threads = 1))
    r = Phase6DRep(T[1.0e-4], T[0.0], T[0.0], T[0.0], T[z0], T[0.0])
    execute!(task, r; turns = 1)
    return r.x[1]
end

println("knob_value type at Float64 seed: ", typeof(knob_value(:bus)))
try
    d = ForwardDiff.derivative(xout, 1.0)
    println("ForwardDiff d(x_out)/d(bus) = ", d, "   exact 1.5*z0 = ", 1.5 * z0,
            "   rel = ", abs(d - 1.5 * z0) / (1.5 * z0))
catch e
    println("ForwardDiff-through-knob FAILED: ", first(sprint(showerror, e), 400))
end
set_knob!(:bus, 1.0)
