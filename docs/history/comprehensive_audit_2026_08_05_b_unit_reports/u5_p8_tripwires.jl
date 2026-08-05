using Octopus
const O = Octopus

println("=== T1: does validate_configuration_metadata check OBSERVER defaults? ===")
observers = (O.BeamMomentObserver("m.bin"), O.JLD2BeamMomentObserver("m.jld2"),
             O.MomentObserver("m.h5"), O.CoordinateSnapshotObserver("m.coord"),
             O.LuminosityObserver("m.lum"), O.BPMObserver())
for obs in observers
    for (n, m) in pairs(O.observer_option_schema(obs))
        hasproperty(obs, n) || (println("  ", typeof(obs), ".", n, ": NOT A FIELD"); continue)
        v = getproperty(obs, n)
        isequal(v, m.default) || println("  DEFAULT DISAGREES: ", nameof(typeof(obs)), ".", n,
                                         " schema=", repr(m.default), " constructed=", repr(v))
    end
end
println("  (a default-built observer whose field differs from its schema default would print above)")

println()
println("=== T2: does validate_configuration_metadata check CUDAPICLaunchConfig defaults? ===")
src = read(joinpath(dirname(pathof(Octopus)), "tasks", "strongstrong", "interface.jl"), String)
blk = match(r"Set\(keys\(cuda_pic_launch_option_schema\(\)\)\).*?solver_fields = "s, src)
println("  block text between the CUDAPICLaunchConfig key check and the next block:")
println("  ", replace(strip(blk.match), "\n" => "\n  "))

println()
println("=== T3: schedule default coverage in validate_configuration_metadata ===")
for m in (r"default_every = EveryNSteps\(\)", r"AlwaysSchedule\(\)", r"AtTurns\(")
    println("  ", m, " appears in a DEFAULT check: ", occursin(m, src))
end

println()
println("=== T4: constructor keywords vs the docstring signature block ===")
for (nm, f, at) in (("PICPoissonSolver", PICPoissonSolver, Tuple{}),
                    ("GaussianPoissonSolver", GaussianPoissonSolver, Tuple{}),
                    ("LongitudinalSlicing", LongitudinalSlicing, Tuple{}),
                    ("CUDAPICLaunchConfig", CUDAPICLaunchConfig, Tuple{}),
                    ("StrongStrongDiagnostics", StrongStrongDiagnostics, Tuple{}),
                    ("StrongStrongTask", StrongStrongTask, Tuple{Any,Any}))
    ms = collect(methods(f, at))
    isempty(ms) && (println("  ", nm, ": no method"); continue)
    kws = Base.kwarg_decl(first(ms))
    doc = string(eval(:(@doc $(Symbol(nm)))))
    missing_kw = [k for k in kws if !occursin(string(k), doc)]
    println("  ", nm, ": ", length(kws), " keywords; NOT MENTIONED ANYWHERE in the docstring: ",
            isempty(missing_kw) ? "none" : missing_kw)
end
