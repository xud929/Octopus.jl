# P3 -- type genericity of every element in the U9 region under
#   (i)   ForwardDiff.Dual coordinates (matched: all six are Duals)
#   (ii)  a Complex number type (complex-step)
#   (iii) UNMATCHED duals: a single-coordinate derivative, so x::Dual meets
#         px::Float64 -- the exact shape that made `_curv_sin(::T,::T)` a
#         MethodError while the matched sweep passed.
#   (iv)  Dual ELEMENT PARAMETERS (parameter derivative) through the spec path.
using Octopus, ForwardDiff
const O = Octopus

const U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)

cases = Pair{String,Any}[]
push!(cases, "drift h=0" => () -> compile_runtime(DriftSpec(L=0.9)))
push!(cases, "drift h=0.21 curved" => () -> compile_runtime(DriftSpec(L=0.9, h=0.21)))
push!(cases, "quad k1,k1s nst=3" => () -> compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, k1s=0.7, nst=3)))
push!(cases, "quad fringe=:all" => () -> compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, k1s=0.7, fringe=:all, va=0.03, vs=0.02, nst=3)))
push!(cases, "sext k2" => () -> compile_runtime(SextupoleSpec(L=0.3, k2=9.0, nst=2)))
push!(cases, "oct k3" => () -> compile_runtime(OctupoleSpec(L=0.2, k3=90.0, nst=2)))
push!(cases, "multipole k0..k5" => () -> compile_runtime(MultipoleSpec(L=0.3, k0=0.1, k1=1.0, k2=5.0, k3=20.0, k4=80.0, k5=300.0, k1s=0.3, nst=2)))
push!(cases, "sbend design orbit" => () -> compile_runtime(SBendSpec(L=0.9, angle=0.19, bend_fringe=false)))
push!(cases, "sbend h!=b0" => () -> compile_runtime(SBendSpec(L=0.9, h=0.21, b0=0.13, bend_fringe=false)))
push!(cases, "sbend |hL|>pi/2" => () -> compile_runtime(SBendSpec(L=0.9, h=2.2, b0=2.2, bend_fringe=false)))
push!(cases, "sbend b0=1e-8 (atan_over branch)" => () -> compile_runtime(SBendSpec(L=0.9, h=0.21, b0=1e-8, bend_fringe=false)))
push!(cases, "sbend full faces fringe=:all o4" => () -> compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, k2=6.0, e1=0.13, e2=-0.09, fint1=0.5, fint2=0.4, hgap1=0.03, hgap2=0.025, hface1=0.11, hface2=-0.07, fringe=:all, nst=3, integrator_order=4)))
push!(cases, "sbend drift_kick" => () -> compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, bend_model=:drift_kick, nst=3)))
push!(cases, "sbend curved psi table" => () -> compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, k1s=0.5, nst=3, bend_fringe=false)))
push!(cases, "rbend fringe=:all" => () -> compile_runtime(RBendSpec(L=0.9, angle=0.19, k1=1.4, fringe=:all, nst=3)))
push!(cases, "solenoid straight pure" => () -> Solenoid(SolenoidSpec(L=1.3, ks=1.7)))
push!(cases, "solenoid straight + k1 (Strang)" => () -> Solenoid(SolenoidSpec(L=1.3, ks=1.7, k1=0.9, nst=4)))
push!(cases, "solenoid CURVED pure nst=16" => () -> Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=16)))
push!(cases, "solenoid CURVED + k0s psi nst=8" => () -> Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, k0s=0.05, nst=8)))
push!(cases, "crab_dispersion" => () -> compile_runtime(CrabDispersionSpec{Float64}(zeta1=0.11, zeta2=-0.07, zeta3=0.05, zeta4=0.03)))
push!(cases, "momentum_dispersion" => () -> compile_runtime(MomentumDispersionSpec{Float64}(eta1=0.21, eta2=-0.13, eta3=0.09, eta4=-0.04)))
push!(cases, "xy_coupling MODEA" => () -> compile_runtime(XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041)))
push!(cases, "xy_coupling MODEB" => () -> compile_runtime(XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041, mode=XY_MODEB)))
push!(cases, "linear6d optics" => () -> compile_runtime(Linear6DSpec{Float64}(beta1=(3.1,2.2,40.0), dmu=(0.7,1.3,0.02), alpha1=(0.3,-0.7,0.1), eta1=(0.2,-0.1,0.05,-0.03), R1=(0.02,0.01,-0.03,0.015), zeta1=(0.01,-0.02,0.03,0.004))))

status(x) = x isa Exception ? "FAIL: " * sprint(showerror, x)[1:min(end, 90)] : x

# (i) matched Duals: the full 6x6 coordinate Jacobian
function try_matched(elem)
    try
        J = ForwardDiff.jacobian(u -> collect(elem(u[1],u[2],u[3],u[4],u[5],u[6])), collect(U))
        return "ok (J[1,1]=$(round(J[1,1], sigdigits=6)))"
    catch e
        return "FAIL " * string(typeof(e)) * ": " * first(sprint(showerror, e), 80)
    end
end

# (iii) UNMATCHED duals: derivative w.r.t. ONE coordinate at a time, so exactly
# one argument is a Dual and the other five stay Float64.
function try_unmatched(elem)
    msgs = String[]
    for i in 1:6
        try
            ForwardDiff.derivative(t -> begin
                u = Any[U...]; u[i] = t
                collect(elem(u[1],u[2],u[3],u[4],u[5],u[6]))
            end, U[i])
        catch e
            push!(msgs, "coord$i " * string(typeof(e)) * ": " * first(sprint(showerror, e), 70))
        end
    end
    return isempty(msgs) ? "ok (all 6 single-coordinate derivatives)" : "FAIL " * join(msgs, " | ")
end

# (ii) Complex coordinates (complex-step differentiation), one coordinate at a time
function try_complex(elem)
    msgs = String[]
    for i in 1:6
        try
            u = Any[U...]
            u[i] = complex(U[i], 1e-30)
            out = elem(u[1],u[2],u[3],u[4],u[5],u[6])
            all(isfinite, real.(out)) || push!(msgs, "coord$i non-finite")
        catch e
            push!(msgs, "coord$i " * string(typeof(e)) * ": " * first(sprint(showerror, e), 70))
        end
    end
    return isempty(msgs) ? "ok (all 6 complex-step)" : "FAIL " * join(msgs, " | ")
end

println("="^118)
println("P3  type genericity.  (i) matched Duals   (iii) UNMATCHED Duals   (ii) Complex")
println("="^118)
for (name, f) in cases
    elem = try
        f()
    catch e
        println(rpad(name, 34), "  BUILD FAIL: ", first(sprint(showerror, e), 90)); continue
    end
    println(rpad(name, 34), "  ", rpad(try_matched(elem), 30), "  ",
            rpad(try_unmatched(elem), 46), "  ", try_complex(elem))
end

# ---------------------------------------------------------------------------
# (iv) Dual ELEMENT PARAMETERS -- a parameter derivative, through the spec path.
# ---------------------------------------------------------------------------
println("\n" * "="^118)
println("(iv) parameter derivatives: every element parameter of every kind, one Dual at a time")
println("="^118)
function pderiv(name, build)
    try
        d = ForwardDiff.derivative(build, 0.0)
        println(rpad(name, 60), " ok  d(out)/d(param) = ", d)
    catch e
        println(rpad(name, 60), " FAIL ", string(typeof(e)), ": ", first(sprint(showerror, e), 100))
    end
end
out1(elem) = elem(U...)[1]
out2(elem) = elem(U...)[2]
pderiv("d(px)/d(k1)  quadrupole", t -> out2(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4 + t, nst=3))))
pderiv("d(px)/d(k1s) quadrupole", t -> out2(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, k1s=0.7 + t, nst=3))))
pderiv("d(x)/d(L)    quadrupole", t -> out1(compile_runtime(QuadrupoleSpec(L=0.4 + t, k1=1.4, nst=3))))
pderiv("d(px)/d(k2)  sextupole", t -> out2(compile_runtime(SextupoleSpec(L=0.3, k2=9.0 + t, nst=2))))
pderiv("d(px)/d(k3)  octupole", t -> out2(compile_runtime(OctupoleSpec(L=0.2, k3=90.0 + t, nst=2))))
pderiv("d(x)/d(h)    curved drift", t -> out1(compile_runtime(DriftSpec(L=0.9, h=0.21 + t))))
pderiv("d(x)/d(b0)   sbend", t -> out1(compile_runtime(SBendSpec(L=0.9, h=0.21, b0=0.13 + t, bend_fringe=false))))
pderiv("d(x)/d(h)    sbend", t -> out1(compile_runtime(SBendSpec(L=0.9, h=0.21 + t, b0=0.13, bend_fringe=false))))
pderiv("d(x)/d(e1)   sbend faces", t -> out1(compile_runtime(SBendSpec(L=0.9, angle=0.19, e1=0.13 + t, fint1=0.5, hgap1=0.03, nst=3))))
pderiv("d(x)/d(fint1) sbend", t -> out1(compile_runtime(SBendSpec(L=0.9, angle=0.19, e1=0.13, fint1=0.5 + t, hgap1=0.03, nst=3))))
pderiv("d(x)/d(va)   quad soft fringe", t -> out1(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, fringe=:soft_quad, va=0.03 + t, vs=0.02, nst=3))))
pderiv("d(px)/d(k1)  curved sbend psi table", t -> out2(compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4 + t, k1s=0.5, nst=3, bend_fringe=false))))
pderiv("d(x)/d(ks)   solenoid straight", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7 + t))))
pderiv("d(x)/d(k1)   solenoid straight (U10-2)", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7, k1=0.9 + t, nst=4))))
pderiv("d(x)/d(k1s)  solenoid straight (U10-2)", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7, k1s=0.9 + t, nst=4))))
pderiv("d(x)/d(h)    solenoid curved", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18 + t, nst=16))))
pderiv("d(x)/d(ks)   solenoid curved", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7 + t, h=0.18, nst=16))))
pderiv("d(x)/d(k0s)  solenoid curved psi", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, k0s=0.05 + t, nst=8))))
pderiv("d(x)/d(zeta1) crab", t -> out1(compile_runtime(CrabDispersionSpec{Float64}(zeta1=0.11 + t))))
pderiv("d(x)/d(eta1) momentum", t -> out1(compile_runtime(MomentumDispersionSpec{Float64}(eta1=0.21 + t))))
pderiv("d(x)/d(r1)   xy_coupling", t -> out1(compile_runtime(XYCouplingSpec{Float64}(r1=0.031 + t))))
pderiv("d(x)/d(dmu1) linear6d {Float64} spec (documented Float64 pin)",
       t -> out1(compile_runtime(Linear6DSpec{Float64}(beta1=(3.1,2.2,40.0), dmu=(0.7 + t,1.3,0.02)))))
pderiv("d(x)/d(dmu1) linear6d {Dual} spec",
       t -> out1(compile_runtime(Linear6DSpec{typeof(t)}(beta1=(3.1,2.2,40.0), dmu=(0.7 + t,1.3,0.02)))))
pderiv("d(x)/d(zeta1) crab {Dual} spec",
       t -> out1(compile_runtime(CrabDispersionSpec{typeof(t)}(zeta1=0.11 + t))))
pderiv("d(x)/d(r1) xy_coupling {Dual} spec",
       t -> out1(compile_runtime(XYCouplingSpec{typeof(t)}(r1=0.031 + t))))

# ---------------------------------------------------------------------------
# (v) Complex ELEMENT PARAMETERS -- complex-step through the spec path.
# ---------------------------------------------------------------------------
println("\n" * "="^118)
println("(v) complex-valued element parameters (complex-step parameter derivative)")
println("="^118)
function cstep(name, build)
    try
        v = build(complex(0.0, 1e-30))
        println(rpad(name, 60), " ok  Im/h = ", imag(v) / 1e-30)
    catch e
        println(rpad(name, 60), " FAIL ", string(typeof(e)), ": ", first(sprint(showerror, e), 100))
    end
end
cstep("k1 quadrupole", t -> out2(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4 + t, nst=3))))
cstep("h curved drift", t -> out1(compile_runtime(DriftSpec(L=0.9, h=0.21 + t))))
cstep("b0 sbend", t -> out1(compile_runtime(SBendSpec(L=0.9, h=0.21, b0=0.13 + t, bend_fringe=false))))
cstep("e1 sbend faces", t -> out1(compile_runtime(SBendSpec(L=0.9, angle=0.19, e1=0.13 + t, fint1=0.5, hgap1=0.03, nst=3))))
cstep("ks solenoid straight", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7 + t))))
cstep("h solenoid curved", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18 + t, nst=16))))
cstep("k1 solenoid straight", t -> out1(Solenoid(SolenoidSpec(L=1.3, ks=1.7, k1=0.9 + t, nst=4))))
cstep("zeta1 crab {Complex} spec", t -> out1(compile_runtime(CrabDispersionSpec{typeof(t)}(zeta1=0.11 + t))))
cstep("r1 xy_coupling {Complex} spec", t -> out1(compile_runtime(XYCouplingSpec{typeof(t)}(r1=0.031 + t))))
cstep("dmu1 linear6d {Complex} spec (U10-11: validator orders on T)",
      t -> out1(compile_runtime(Linear6DSpec{typeof(t)}(beta1=(3.1,2.2,40.0), dmu=(0.7 + t,1.3,0.02)))))
