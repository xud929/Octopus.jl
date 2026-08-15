#=
Knob-control example: one knob drives many element parameters.

Two production-shaped scenarios:

1. The half crossing angle. `LorentzBoostSpec`, `RevLorentzBoostSpec`, and
   every crab-cavity strength all depend on the same physical angle. One knob
   `ip.half_crossing_angle` feeds the boost pair directly and both beams' crab
   strengths through dependent knobs, so changing the crossing angle is one
   plain assignment, not an edit in five places.
2. A real lattice: a FODO cell as a `BeamLine`, its quadrupoles driven
   `+K`/`-K` from ONE power-supply chain
   (`HSR.arc_k1 = HSR.power_supply.arc_quad * HSR.current_transfer /
   HSR.B_rho`), plus a trim supply on one PLACEMENT via an
   expression-valued override — main bus *plus* trim, the pattern the
   `LineEntry` docstring recommends over a detached numeric override. The
   wiring is inspected with the container `knob_report(cell)`, and a bus
   retune reaches an already-constructed `TrackingTask` at its next
   `execute!` (knob-epoch invalidation).

Knobs are declared with `@knob` (optionally typed, `::Float64` being the
default) and afterwards read and assigned with plain Julia syntax through
their namespace (`ip.half_crossing_angle = 15.0e-3`) — no strings. Element
parameters carry knob *expressions* (`@knob_expr`) through the flexible
`ElementSpec{kind}(; ...)` constructors; `compile_runtime` evaluates them when
the tracking line is built. Design note: `docs/knob_control.md` (§2a for the
registry-vs-wiring report split shown below).

Run from the project root:

    julia --project=. examples/knob_control.jl

Output is printed to the terminal; no files are written.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

config = (
    turns = 1,
    n_macro = 4,     # a few probe particles; this example is about the knobs
)

# ---------------------------------------------------------------------------
# Scenario 1: the half crossing angle (strong-strong example constants).
# ---------------------------------------------------------------------------
@knob ip.half_crossing_angle::Float64 = 12.5e-3    # rad

@knob ele.beta_x = 0.55                            # m, IP beta
@knob ele.crab_beta_x = 150.0                      # m, beta at the crab cavity
@knob ele.crab_strength =
    tan(ip.half_crossing_angle) / sqrt(ele.crab_beta_x * ele.beta_x)

@knob pro.beta_x = 0.8
@knob pro.crab_beta_x = 1300.0
@knob pro.crab_harmonics::Int = 2                  # typed knob: value count below
@knob pro.crab_strength_h1 =
    tan(ip.half_crossing_angle) / sqrt(pro.crab_beta_x * pro.beta_x) * (4.0 / 3.0)
@knob pro.crab_strength_h2 =
    -(tan(ip.half_crossing_angle) / sqrt(pro.crab_beta_x * pro.beta_x)) / 3.0

boost = ElementSpec{:lorentz_boost}(;
    angle = @knob_expr(ip.half_crossing_angle),
    tracking_method = NonSymplectic6DMap())
rev_boost = ElementSpec{:rev_lorentz_boost}(;
    angle = @knob_expr(ip.half_crossing_angle),
    tracking_method = NonSymplectic6DMap())
ele_crab = ElementSpec{:thin_crab_cavity}(;
    N = 3, frequency = 394.0e6,
    strengthX = (@knob_expr(ele.crab_strength), 0.0, 0.0),
    strengthY = (0.0, 0.0, 0.0), phase = (0.0, 0.0, 0.0),
    tracking_method = Symplectic6DMap())
pro_crab = ElementSpec{:thin_crab_cavity}(;
    N = 3, frequency = 197.0e6,
    strengthX = (@knob_expr(pro.crab_strength_h1), @knob_expr(pro.crab_strength_h2), 0.0),
    strengthY = (0.0, 0.0, 0.0), phase = (0.0, 0.0, 0.0),
    tracking_method = Symplectic6DMap())

# ---------------------------------------------------------------------------
# Scenario 2: a FODO cell, its quadrupole family on one power-supply chain.
#
# The knob chain is the control room's wiring: a supply current, a transfer
# function, a rigidity. `HSR.arc_k1` is the derived strength; the focusing
# quad takes +K and the defocusing quad -K THROUGH EXPRESSIONS, so the family
# stays on the bus. Knob-driven strengths go through the flexible
# `ElementSpec{kind}` constructor (the friendly constructors fold named
# strengths eagerly and refuse expressions, saying exactly this).
# ---------------------------------------------------------------------------
@knob HSR.B_rho = 81.1                             # T*m
@knob HSR.current_transfer = 0.05                  # (strength units) per A
@knob HSR.power_supply.arc_quad = 1000.0           # A, the main bus
@knob HSR.power_supply.qd_trim = 0.0               # A, one magnet's trim
@knob HSR.arc_k1 =
    HSR.power_supply.arc_quad * HSR.current_transfer / HSR.B_rho

qf = ElementSpec{:quadrupole}(;
    L = 0.5, kn = (0.0, @knob_expr(HSR.arc_k1)),
    tracking_method = Symplectic6DMap())
qd = ElementSpec{:quadrupole}(;
    L = 0.5, kn = (0.0, @knob_expr(-HSR.arc_k1)),
    tracking_method = Symplectic6DMap())
cell = BeamLine("FODO", qf, DriftSpec(L = 2.0), qd, DriftSpec(L = 2.0))

# The trim supply, on THIS PLACEMENT only: an override that IS an expression.
# A numeric override would detach the magnet from the family permanently;
# main bus plus trim keeps it on the bus AND individually adjustable.
line_entries(cell)[3].kn = (0.0,
    @knob_expr(-HSR.arc_k1 +
               HSR.power_supply.qd_trim * HSR.current_transfer / HSR.B_rho))

# ---------------------------------------------------------------------------
# Introspection, in both of its directions (docs/knob_control.md §2a):
# the registry view knows the knob NAMESPACE and its dependency graph; the
# container view walks a given line and reports the WIRING — which element
# parameters each knob actually drives, with expression text and value.
# ---------------------------------------------------------------------------
println("=== knob report (registry view) ===")
knob_report(prefix = "HSR")
println()
println("=== knob report (wiring view of the FODO cell) ===")
knob_report(cell)
println()
println("everything driven by ip.half_crossing_angle: ",
        join(knob_dependents(@knob_expr(ip.half_crossing_angle); transitive=true), ", "))
println("HSR.arc_k1 reads: ",
        join(knob_dependencies(@knob_expr(HSR.arc_k1)), ", "))
println("pro.crab_harmonics (typed ::Int) = ", pro.crab_harmonics)
println()

# ---------------------------------------------------------------------------
# Evaluation happens when a line is built; a knob assignment reaches an
# already-constructed task at its next execute!.
# ---------------------------------------------------------------------------
ip_line = (boost, ele_crab, rev_boost)
ip_task = TrackingTask(ip_line; policy = CPUThreadsExecutionPolicy(threads = 1))
fodo_task = TrackingTask(cell; policy = CPUThreadsExecutionPolicy(threads = 1))
rep() = Phase6DRep(
    [1.0e-4 * i for i in 1:config.n_macro], zeros(config.n_macro),
    [-5.0e-5 * i for i in 1:config.n_macro], zeros(config.n_macro),
    [1.0e-3 * i for i in 1:config.n_macro], zeros(config.n_macro))

println("=== compiled and tracked at the 1000 A working point ===")
println("boost angle       = ", compile_runtime(boost).angle)
println("ele crab kick     = ", compile_runtime(ele_crab).strengthX[1])
println("arc K (knob)      = ", HSR.arc_k1)
r1 = rep()
execute!(fodo_task, r1; turns = config.turns)
println("FODO tracked x[1] = ", r1.x[1])
r1ip = rep()
execute!(ip_task, r1ip; turns = config.turns)
println("IP tracked x[1]   = ", r1ip.x[1])
println()

# One plain assignment retunes the whole quad family through the bus...
HSR.power_supply.arc_quad = 1100.0
println("=== after HSR.power_supply.arc_quad = 1100.0 ===")
println("arc K (knob)      = ", HSR.arc_k1)
r2 = rep()
execute!(fodo_task, r2; turns = config.turns)
println("FODO tracked x[1] = ", r2.x[1], "   (was ", r1.x[1], ")")

# ...and the trim moves ONE placement while the family stays on the bus.
HSR.power_supply.qd_trim = 25.0
r3 = rep()
execute!(fodo_task, r3; turns = config.turns)
println("with 25 A QD trim = ", r3.x[1], "   (was ", r2.x[1], ")")
println()

# The crossing angle moves everything that depends on it, same mechanism.
ip.half_crossing_angle = 15.0e-3
println("=== after ip.half_crossing_angle = 15.0e-3 ===")
println("boost angle       = ", compile_runtime(boost).angle)
println("ele crab kick     = ", compile_runtime(ele_crab).strengthX[1])
println("pro crab kicks    = ", compile_runtime(pro_crab).strengthX[1:2])
r2ip = rep()
execute!(ip_task, r2ip; turns = config.turns)
println("IP tracked x[1]   = ", r2ip.x[1], "   (was ", r1ip.x[1], ")")
println()

# ---------------------------------------------------------------------------
# Symbolic layer: response of the crab strength to the crossing angle.
# ---------------------------------------------------------------------------
d = knob_derivative(@knob_expr(ele.crab_strength), @knob_expr(ip.half_crossing_angle))
println("=== symbolic layer ===")
println("d(ele.crab_strength)/d(half_crossing_angle) = ", d)
fd = (knob_value(@knob_expr(tan(ip.half_crossing_angle + 1.0e-9) /
                            sqrt(ele.crab_beta_x * ele.beta_x))) -
      ele.crab_strength) / 1.0e-9
println("  evaluated: ", knob_value(d), "   finite-difference check: ", fd)
if knob_symbolics_available()
    sym = knob_symbolic(@knob_expr(ele.crab_strength * HSR.B_rho + ele.crab_strength))
    println("Symbolics form:  ", sym)
    println("round-tripped:   ", knob_from_symbolic(sym))
else
    println("(Symbolics adapter inactive; `using Symbolics` activates it -- the ",
            "OctopusSymbolicsExt weak-dep extension in package mode, automatic ",
            "in script mode when Symbolics is importable)")
end
