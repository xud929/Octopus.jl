# BLAST-RADIUS CHECK for the U9-1 fix: the curved solenoid is differentiated
# (U9 measured d(x)/d(h) = 0.56350 through it), so the new construction-time
# guard must survive Dual parameters. `ceil(Int, ::Dual)` would be a regression
# in a dimension the symplecticity sweep does not measure.
using Octopus, ForwardDiff
U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)

println("--- Dual through h (curved solenoid), q small so no warning path ---")
d1 = ForwardDiff.derivative(h -> Octopus.compile_runtime(
        SolenoidSpec(L=1.3, ks=1.7, h=h))(U...)[1], 0.18)
println("d(x)/d(h) = ", d1, "   (U9 recorded 0.56350)")

println("--- Dual through ks (enters q directly) ---")
d2 = ForwardDiff.derivative(ks -> Octopus.compile_runtime(
        SolenoidSpec(L=1.3, ks=ks, h=0.18))(U...)[1], 1.7)
println("d(x)/d(ks) = ", d2)

println("--- Dual through L (enters q directly) ---")
d3 = ForwardDiff.derivative(L -> Octopus.compile_runtime(
        SolenoidSpec(L=L, ks=1.7, h=0.18))(U...)[1], 1.3)
println("d(x)/d(L) = ", d3)

println("--- Dual on the WARNING path (q = 0.27 > 0.1) ---")
d4 = ForwardDiff.derivative(ks -> Octopus.compile_runtime(
        SolenoidSpec(L=5.0, ks=ks, h=0.1))(U...)[1], 1.7)
println("d(x)/d(ks) = ", d4)

println("--- straight solenoid unaffected (guard is curved-only) ---")
d5 = ForwardDiff.derivative(ks -> Octopus.compile_runtime(
        SolenoidSpec(L=1.3, ks=ks))(U...)[1], 1.7)
println("d(x)/d(ks) straight = ", d5)
println("ALL-DUAL-PATHS-OK")
