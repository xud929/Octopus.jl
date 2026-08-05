# U18 probe 9: tolerance headroom + the unknown-parameter warning's payload.
using Octopus, ForwardDiff, LinearAlgebra, Logging

println("=== unknown-parameter warning: does the message name the key? ===")
logger = Test = nothing
buf = IOBuffer()
with_logger(ConsoleLogger(buf, Logging.Debug)) do
    QuadrupoleSpec(L=0.3, k1=1.2, this_keyword_does_not_exist=1.0)
    ElementSpec{:quadrupole}(; bogus=2.0)
end
txt = String(take!(buf))
println(txt)
println("message contains 'this_keyword_does_not_exist': ",
        occursin("this_keyword_does_not_exist", txt))
println("message contains 'bogus': ", occursin("bogus", txt))

println()
println("=== nu_s ~ sqrt(V) ratio headroom (rtol 1e-6 asserted) ===")
ring(V) = begin
    M = Matrix{Float64}(I, 6, 6)
    M[5, 6] = -1.0e-3
    [compile_runtime(ThinRFCavitySpec(400.8e6; voltage=V, e0=275e9, mc2=PMASS_EV)),
     compile_runtime(Linear6DSpec(; matrix=Tuple(vec(permutedims(M)))))]
end
nus = map((2e6, 8e6, 32e6)) do V
    ops = ring(V)
    J = zeros(2, 2)
    for j in 1:2
        v = ComplexF64[0, 0, 0, 0, 0, 0]
        v[4 + j] += 1e-30im
        o = foldl((c, op) -> op(c...), ops; init=Tuple(v))
        J[:, j] = [imag(o[5]), imag(o[6])] ./ 1e-30
    end
    acos((J[1, 1] + J[2, 2]) / 2) / 2pi
end
println("  nus = ", nus)
println("  nus[2]/nus[1] = ", nus[2] / nus[1], "  rel error vs 2 = ", abs(nus[2] / nus[1] - 2) / 2)
println("  nus[3]/nus[2] = ", nus[3] / nus[2], "  rel error vs 2 = ", abs(nus[3] / nus[2] - 2) / 2)

println()
println("=== symplecticity residual headrooms in the two solenoid testsets ===")
S6 = zeros(6, 6)
for (q, p) in ((1, 2), (3, 4), (5, 6))
    S6[q, p] = 1.0; S6[p, q] = -1.0
end
u0 = [1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 1.0e-3, 1.0e-4]
residual(mapf) = begin
    J = ForwardDiff.jacobian(u -> collect(mapf(u...)), u0)
    maximum(abs, J' * S6 * J - S6)
end
println("  curved solenoid nst=4  (asserted < 1e-8):  ",
        residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=4))))
println("  curved solenoid nst=16 (asserted < 1e-12): ",
        residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=16))))
sol_cf = compile_runtime(SolenoidSpec(L=1.3, ks=1.7, h=0.05, kskew=(0.05,),
                                      curved=false, nst=4))
println("  curved=false solenoid  (asserted < 1e-9):  ", residual(sol_cf))
println("  straight pure solenoid (asserted < 1e-10): ",
        residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7))))
println("  straight sol+kskew     (asserted < 1e-10): ",
        residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, kskew=(0.05,), nst=4))))
println("  h!=0 sweep instrument self-check (asserted isapprox 2.5e-3 rtol 1e-6): ",
        residual((x, px, y, py, z, pz) ->
            Octopus._lattice_kick((0.0,), (0.05,), 0.05, 1.0, x, px, y, py, z, pz)))
println("  worst SBend content case (all asserted < 1e-12):")
contents = [NamedTuple(), (kn=(0.02,),), (ks=(0.05,),), (kn=(0.0, 0.6),),
            (ks=(0.0, 0.6),), (kn=(0.0, 0.0, 2.0),), (ks=(0.0, 0.0, 2.0),),
            (kn=(0.0, 0.0, 0.0, 12.0),), (ks=(0.0, 0.0, 0.0, 12.0),),
            (kn=(0.0, 0.6, 1.0), ks=(0.03, 0.2))]
const WORST = Ref(0.0)
for kw in contents
    WORST[] = max(WORST[], residual(compile_runtime(SBendSpec(; L=1.1, h=0.05, b0=0.05, nst=2, kw...))))
end
println("      ", WORST[])

println()
println("=== elliptical strong-beam kick residual (asserted < 1e-10) ===")
el = compile_runtime(ThinStrongBeamSpec{Float64}(kbb=1.0e-4, beta=(1.0, 1.0),
                                                 sigma=(106.0e-6, 9.5e-6)))
u1 = [0.8e-4, 1.0e-5, 0.4e-4, -2.0e-5, 1.0e-3, 1.0e-4]
J = ForwardDiff.jacobian(u -> collect(el(u...)), u1)
println("  ", maximum(abs, J' * S6 * J - S6))

println()
println("=== lattice cell symplecticity (asserted < 1e-12) ===")
S6b = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
track(cell, u) = foldl((c, e) -> e(c...), cell; init=u)
function jac(cell, u0)
    J = zeros(6, 6)
    for j in 1:6
        u = ComplexF64[u0...]
        u[j] += 1e-30im
        J[:, j] = imag.(collect(track(cell, Tuple(u)))) ./ 1e-30
    end
    J
end
q(k, L=0.3) = compile_runtime(QuadrupoleSpec(L=L, kn=(0.0, k), nst=4, integrator_order=4))
d(L) = compile_runtime(DriftSpec(L=L))
b(L, ang) = compile_runtime(SBendSpec(L=L, h=ang / L, b0=ang / L, nst=4, integrator_order=4))
sx(k2) = compile_runtime(SextupoleSpec(L=0.2, kn=(0.0, 0.0, k2), nst=4, integrator_order=4))
fodo = (q(1.6), d(1.2), q(-1.6), d(1.2))
dba = (q(-1.1, 0.25), d(0.6), b(1.0, 0.20), d(0.6), q(1.5, 0.35),
       d(0.6), b(1.0, 0.20), d(0.6), q(-1.1, 0.25))
u00 = (1.0e-4, 2.0e-5, -0.8e-4, -1.5e-5, 0.0, 0.0)
for (name, cell) in (("FODO", fodo), ("DBA", dba), ("DBA+sext", (dba..., sx(8.0))))
    J = jac(cell, u00)
    println("  ", rpad(name, 10), maximum(abs, J' * S6b * J - S6b),
            "   |trace_x|=", abs(J[1, 1] + J[2, 2]), " |trace_y|=", abs(J[3, 3] + J[4, 4]))
end
