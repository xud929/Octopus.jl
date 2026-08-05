using Octopus
const O = Octopus

mkb(rng_id, charge, mc2, E0) = begin
    set_global_rng!(seed=5, method=:philox)
    Beam(300, CPUThreadsExecutionPolicy(), Float64;
        beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
        charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
end
beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                  alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
lum_rows(path) = readlines(path)[2:end]

ip = StrongStrongCollision(:ip)
A = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
B = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))

println("=== P4: does a failing prepare_observers! leave the .lum already destroyed? ===")
# Phase 1: a good run writing BOTH a .lum file (default replace mode) and an
# appendable MomentObserver table.
pl = tempname() * ".lum"
ph = tempname() * ".h5"
mko(orders) = ScheduledObserver(MomentObserver(ph; capacity=8, append=true, orders=orders))
t1 = StrongStrongTask((ip, A, mko(1)), (ip, B);
                      luminosity_path=pl,
                      policy=CPUThreadsExecutionPolicy(threads=1))
b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
println("  after good run: lum rows = ", length(lum_rows(pl)), "  ", lum_rows(pl))

# Phase 2: a NEW task whose MomentObserver has a DIFFERENT moment selection,
# which `_moment_append_continue!` refuses. The .lum path is the same and the
# task is in default replace mode.
t2 = StrongStrongTask((ip, A, mko(2)), (ip, B);
                      luminosity_path=pl,
                      policy=CPUThreadsExecutionPolicy(threads=1))
b1, b2 = beams()
err = try
    execute!(t2, b1, b2; turns=3)
    nothing
catch e
    e
end
println("  aborted execute! threw: ", err === nothing ? "NOTHING" : typeof(err))
println("  lum rows AFTER the aborted execute!: ", length(lum_rows(pl)), "  ", lum_rows(pl))
println("  -> the luminosity file was destroyed by a run that tracked nothing: ",
        isempty(lum_rows(pl)))

println()
println("=== P4b: same, in APPEND mode (rows at/after first_turn dropped first) ===")
pl2 = tempname() * ".lum"
ph2 = tempname() * ".h5"
mko2(orders) = ScheduledObserver(MomentObserver(ph2; capacity=8, append=true, orders=orders))
t3 = StrongStrongTask((ip, A, mko2(1)), (ip, B);
                      luminosity_path=pl2, luminosity_append=true,
                      policy=CPUThreadsExecutionPolicy(threads=1))
b1, b2 = beams(); execute!(t3, b1, b2; turns=5)
println("  after good run: lum rows = ", length(lum_rows(pl2)))
t4 = StrongStrongTask((ip, A, mko2(2)), (ip, B);
                      luminosity_path=pl2, luminosity_append=true,
                      policy=CPUThreadsExecutionPolicy(threads=1))
b1, b2 = beams()
err2 = try
    execute!(t4, b1, b2; turns=2, start_turn=2)
    nothing
catch e
    e
end
println("  aborted execute! threw: ", err2 === nothing ? "NOTHING" : typeof(err2))
println("  lum rows AFTER the aborted execute!: ", length(lum_rows(pl2)), "  ", lum_rows(pl2))

println()
println("=== P4c: leftover .prepare.tmp after a mid-prepare failure? ===")
println("  tmp exists: ", isfile(pl2 * ".prepare.tmp"))

foreach(p -> rm(p; force=true), (pl, ph, pl2, ph2))
