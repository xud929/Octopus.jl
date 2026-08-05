using Octopus
const O = Octopus

println("=== (c) unknown-keyword acceptance ===")
function try_kw(name, f)
    try
        f()
        println("ACCEPTED SILENTLY: ", name)
    catch err
        println("rejected: ", name, " -> ", typeof(err))
    end
end

try_kw("PICPoissonSolver(grd=(64,64))", () -> PICPoissonSolver(grd=(64, 64)))
try_kw("PICPoissonSolver{Float64}(grd=(64,64))", () -> PICPoissonSolver{Float64}(grd=(64, 64)))
try_kw("GaussianPoissonSolver(min_sig=1.0)", () -> GaussianPoissonSolver(min_sig=1.0))
try_kw("SpectralPoissonSolver(grd=(64,64))", () -> O.SpectralPoissonSolver(grd=(64, 64)))
try_kw("GaussianPICPoissonSolver(margin_sig=3.0)", () -> O.GaussianPICPoissonSolver(margin_sig=3.0))
try_kw("LongitudinalSlicing(methd=:equal_width)", () -> LongitudinalSlicing(methd=:equal_width))
try_kw("LongitudinalSlicing(4; methd=:equal_width)", () -> LongitudinalSlicing(4; methd=:equal_width))
try_kw("CUDAPICLaunchConfig(kick_thread=64)", () -> CUDAPICLaunchConfig(kick_thread=64))
try_kw("StrongStrongDiagnostics(nvt=true)", () -> StrongStrongDiagnostics(nvt=true))
try_kw("StrongStrongCollision(:ip; poisson_solvr=nothing)",
       () -> StrongStrongCollision(:ip; poisson_solvr=nothing))
let ip = StrongStrongCollision(:ip)
    try_kw("StrongStrongTask(l1,l2; luminosity_apend=true)",
           () -> StrongStrongTask((ip,), (ip,); luminosity_apend=true))
    try_kw("StrongStrongTask(l1,l2; luminosity_path=..., append=true)",
           () -> StrongStrongTask((ip,), (ip,); luminosity_path="x", append=true))
end

println()
println("=== (e)/(a) StrongStrongTask option schema vs constructor vs report ===")
sch = O.strong_strong_task_option_schema()
println("schema keys: ", keys(sch))
ip = StrongStrongCollision(:ip)
t = StrongStrongTask((ip,), (ip,))
for (n, m) in pairs(sch)
    actual = getproperty(t, n)
    println("  ", n, ": schema default=", repr(m.default), " constructor default=", repr(actual),
            " agree=", isequal(actual, m.default), " consumer=", m.consumer)
end
# Which public constructor keywords exist but have NO schema entry?
kwnames = Base.kwarg_decl(first(methods(StrongStrongTask, (Any, Any))))
println("StrongStrongTask public keywords: ", kwnames)
println("keywords with NO schema entry: ", setdiff(kwnames, collect(keys(sch))))

println()
println("=== does validate_configuration_metadata() read the CONSTRUCTOR for task defaults? ===")
src = read(joinpath(dirname(pathof(Octopus)), "tasks", "strongstrong", "interface.jl"), String)
println("hand-copied literal present: ",
        occursin("task_defaults = (luminosity_path=nothing, luminosity_append=false)", src))

println()
println("=== schema vs configuration_report key agreement (task output block) ===")
b1 = Beam(8, CPUThreadsExecutionPolicy(threads=1), Float64; rng_id=1)
b2 = Beam(8, CPUThreadsExecutionPolicy(threads=1), Float64; rng_id=2)
rep = O.configuration_report(t, b1, b2)
println("output entry names: ", [e.name for e in rep.output])
println("schema keys      : ", collect(keys(sch)))

println()
println("=== (a) grid_extent_sigma reported status when grid_extent=:extrema ===")
s = PICPoissonSolver(grid=(16, 16))                      # grid_extent = :extrema (default)
for e in O.configuration_report(s; backend=CPUThreadsBackend)
    e.name in (:grid_extent, :grid_extent_sigma, :slice_pair_green_growth,
               :slice_pair_green_min_ratio) || continue
    println("  ", e.name, " status=", e.status, " requested=", repr(e.requested))
end
s2 = PICPoissonSolver(grid=(16, 16), green_cache=:none)
for e in O.configuration_report(s2; backend=CPUThreadsBackend)
    e.name in (:slice_pair_green_growth, :slice_pair_green_min_ratio) || continue
    println("  green_cache=:none -> ", e.name, " status=", e.status)
end

println()
println("=== (d) _collision_solver equality for a schema-less solver type ===")
println("empty schema fallback: ", O.solver_option_schema(O.AbstractPoissonSolver))
