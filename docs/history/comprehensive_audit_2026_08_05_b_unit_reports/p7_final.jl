using Octopus, ForwardDiff
const O = Octopus
const S6 = let M = zeros(6,6); for b in (1,3,5); M[b,b+1]=1.0; M[b+1,b]=-1.0; end; M end
symp(f, u0) = maximum(abs, let J = ForwardDiff.jacobian(u -> collect(f(u...)), collect(u0))
    transpose(J)*S6*J - S6 end)
const U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)

println("="^116)
println("A. curved solenoid: does raising nst recover the diverged default cases?  (structural vs discretization)")
println("="^116)
for (h, ks, L) in ((0.1, 5.0, 5.0), (0.1, 20.0, 1.3), (0.1, 20.0, 5.0))
    print(rpad("h=$h ks=$ks L=$L", 26))
    for nst in (16, 32, 64, 128, 256, 512, 1024)
        e = Solenoid(SolenoidSpec(L=L, ks=ks, h=h, nst=nst))
        s = try symp((a...) -> e(a...), U) catch; NaN end
        print(" nst=", nst, ":", round(s, sigdigits=3))
    end
    println()
end
println("\n  contraction factor of the fixed-point iteration is  q ~ (L/(2 nst)) * (ks/2) * 2 = L*ks/(2 nst):")
for (h, ks, L, nst) in ((0.18,1.7,1.3,16), (0.1,1.7,5.0,16), (0.1,5.0,5.0,16),
                        (0.1,20.0,1.3,16), (0.1,20.0,5.0,16), (0.1,20.0,5.0,128))
    e = Solenoid(SolenoidSpec(L=L, ks=ks, h=h, nst=nst))
    s = try symp((a...) -> e(a...), U) catch; NaN end
    println("   h=", rpad(h,6), " ks=", rpad(ks,6), " L=", rpad(L,6), " nst=", rpad(nst,5),
            " q=", rpad(round(L*ks/(2*nst), sigdigits=4), 10), " |J'SJ-S|=", s)
end

println("\n" * "="^116)
println("B. schema under-declaration, sharpened: a physics default that can only be turned off")
println("   through a key the schema calls unknown and the warning calls inert")
println("="^116)
a = compile_runtime(MultipoleSpec(L=0.2, k0=0.05, k1=1.2, nst=2))
b = compile_runtime(MultipoleSpec(L=0.2, k0=0.05, k1=1.2, nst=2, bend_fringe=false))
println("  MultipoleSpec(L=0.2, k0=0.05, k1=1.2): bend_fringe default TRUE vs explicit FALSE")
println("    max coordinate change = ", maximum(abs, collect(a(U...)) .- collect(b(U...))))
println("    :bend_fringe in parameter_schema(ElementSpec{:multipole})? ",
        :bend_fringe in keys(parameter_schema(ElementSpec{:multipole})))
println("\n  DriftSpec with undeclared kn: is it still a drift?")
d0 = compile_runtime(DriftSpec(L=0.9))
d1 = compile_runtime(DriftSpec(L=0.9, kn=(0.0, 1.4), nst=3))
println("    max coordinate change from kn=(0, 1.4) = ", maximum(abs, collect(d0(U...)) .- collect(d1(U...))))
println("    :kn in parameter_schema(ElementSpec{:drift})? ",
        :kn in keys(parameter_schema(ElementSpec{:drift})))

println("\n" * "="^116)
println("C. _needs_curved_potential coverage, at an amplitude where every order's non-gradient is visible")
println("="^116)
const UB = (2.0e-2, 5.0e-3, -1.5e-2, 4.0e-3, 3.0e-3, 5.0e-3)
for i in 1:7, skew in (false, true)
    kn = ntuple(j -> (!skew && j == i) ? 200.0 : 0.0, 7)
    ks = ntuple(j -> ( skew && j == i) ? 200.0 : 0.0, 7)
    need = O._needs_curved_potential(kn, ks, 0.21)
    r = symp((u...) -> O._lattice_kick(kn, ks, 0.21, 0.9, u...), UB)
    println("  K", i-1, skew ? "s" : " ", "  needs_table=", rpad(need, 6),
            " |J'SJ-S| of the closed kick = ", rpad(r, 24),
            "  ", need == (r > 1e-16) ? "consistent" : "*** MISMATCH ***")
end
println("  control: h = 0 must make every one of them a gradient")
for i in 1:7, skew in (false, true)
    kn = ntuple(j -> (!skew && j == i) ? 200.0 : 0.0, 7)
    ks = ntuple(j -> ( skew && j == i) ? 200.0 : 0.0, 7)
    r = symp((u...) -> O._lattice_kick(kn, ks, 0.0, 0.9, u...), UB)
    r > 1e-16 && println("    *** K", i-1, skew ? "s" : "", " non-gradient at h=0: ", r)
end
println("    (nothing printed above means every straight-frame kick is an exact gradient)")

println("\n" * "="^116)
println("D. solenoid Strang split: is the curved sub-step really nst=1 per half, and does that")
println("   make the composite's convergence differ from the pure curved element?")
println("="^116)
for nst in (4, 8, 16, 32, 64)
    e = Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, k1=0.9, nst=nst))
    println("  curved solenoid + k1, nst=", rpad(nst,5), " |J'SJ-S| = ", symp((a...) -> e(a...), U),
            "  x = ", e(U...)[1])
end

println("\n" * "="^116)
println("E. documented limits: ks -> 0 == exact drift;  ks = 0 + k1 == QuadrupoleSpec;  h -> 0 curved -> straight")
println("="^116)
sd = Solenoid(SolenoidSpec(L=1.3, ks=0.0))
dd = compile_runtime(DriftSpec(L=1.3))
println("  solenoid(ks=0) vs drift:            max diff = ", maximum(abs, collect(sd(U...)) .- collect(dd(U...))))
sq = Solenoid(SolenoidSpec(L=1.3, ks=0.0, k1=1.2, nst=8))
qq = compile_runtime(QuadrupoleSpec(L=1.3, k1=1.2, nst=8, bend_fringe=false))
println("  solenoid(ks=0,k1) vs quadrupole:    max diff = ", maximum(abs, collect(sq(U...)) .- collect(qq(U...))))
for h in (1e-2, 1e-4, 1e-6, 1e-8)
    sc = Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=h, nst=64))
    ss = Solenoid(SolenoidSpec(L=1.3, ks=1.7))
    println("  curved solenoid h=", rpad(h,8), " vs exact straight: max diff = ",
            maximum(abs, collect(sc(U...)) .- collect(ss(U...))))
end
for ks in (1e-3, 1e-6, 1e-9)
    sc = Solenoid(SolenoidSpec(L=1.3, ks=ks, h=0.18, nst=64))
    cd = O._lattice_drift(Val(true), 0.18, 1.3, U...)
    println("  curved solenoid ks=", rpad(ks,8), " vs curved drift:   max diff = ",
            maximum(abs, collect(sc(U...)) .- collect(cd)))
end

println("\n" * "="^116)
println("F. Forest-Ruth coefficients: algebraic identities and PTC METHOD=4 form")
println("="^116)
println("  _FR_A  = ", O._FR_A, "   (1 - 2^(1/3) = ", 1 - 2^(1/3), ")")
println("  2(d1 + d2) - 1 = ", 2*(O._FR_D1 + O._FR_D2) - 1)
println("  2 k1 + k2 - 1  = ", 2*O._FR_K1 + O._FR_K2 - 1)
println("  k1^3*2 + k2^3 (third-order condition, must be 0) = ", 2*O._FR_K1^3 + O._FR_K2^3)
println("  4th-order check: composite of the sbend body at nst -> convergence order")
ref = compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, k2=8.0, nst=4096, integrator_order=4, bend_fringe=false))(U...)[1]
for ord in (2, 4)
    es = [abs(compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, k2=8.0, nst=n,
            integrator_order=ord, bend_fringe=false))(U...)[1] - ref) for n in (4, 8, 16, 32)]
    println("    order=", ord, " errors at nst=4,8,16,32: ", round.(es, sigdigits=3),
            "  observed rates: ", round.(log2.(es[1:end-1] ./ es[2:end]), digits=2))
end
