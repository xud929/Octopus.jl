using Octopus, ForwardDiff
const O = Octopus
const S6 = let M = zeros(6,6); for b in (1,3,5); M[b,b+1]=1.0; M[b+1,b]=-1.0; end; M end
symp(f, u0) = maximum(abs, let J = ForwardDiff.jacobian(u -> collect(f(u...)), collect(u0))
    transpose(J)*S6*J - S6 end)
const U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)

# ---------------------------------------------------------------------------
# A. Does the DEFAULT curved-solenoid nst = 16 ever silently fail to converge?
# ---------------------------------------------------------------------------
println("="^116)
println("A. curved solenoid at the DEFAULT nst = 16: symplectic residual over a (h, ks, L) grid")
println("   (no convergence check exists; _SOL_MIDPOINT_ITERS = 16 fixed-point sweeps, nst default 16)")
println("="^116)
println(rpad("h",8), rpad("ks",8), rpad("L",8), rpad("d*ks/2 = L*ks/(2 nst)",24),
        rpad("|J'SJ-S| (nst=16)",26), "x(nst=16) vs x(nst=512)")
for h in (0.1, 0.5), ks in (1.7, 5.0, 20.0), L in (1.3, 5.0)
    e16 = Solenoid(SolenoidSpec(L=L, ks=ks, h=h, nst=16))
    eref = Solenoid(SolenoidSpec(L=L, ks=ks, h=h, nst=512))
    s = try symp((a...) -> e16(a...), U) catch err; NaN end
    x16 = try e16(U...)[1] catch err; NaN end
    xr = try eref(U...)[1] catch err; NaN end
    println(rpad(h,8), rpad(ks,8), rpad(L,8), rpad(L*ks/(2*16), 24), rpad(s, 26),
            "  ", x16, " vs ", xr)
end

# ---------------------------------------------------------------------------
# B. Schema under-declaration: keys `_lattice_magnet` READS but the per-kind
#    schema does not declare, so the new unknown-parameter warning calls them
#    "NOT being tracked" while they change the physics.
# ---------------------------------------------------------------------------
println("\n" * "="^116)
println("B. keys _lattice_magnet reads that the per-kind parameter schema does not declare")
println("="^116)
const READ_BY_COMPILE = [:L, :nst, :integrator_order, :h, :b0, :kn, :ks, :bend_model,
    :curved, :curved_order, :bend_fringe, :fringe, :highest_fringe, :wedge_coeff,
    :e1, :e2, :fint1, :fint2, :hgap1, :hgap2, :hface1, :hface2, :va, :vs,
    :kill_ent_fringe, :kill_exi_fringe]
for (kind, ctor) in ((:drift, DriftSpec), (:quadrupole, QuadrupoleSpec),
                     (:sextupole, SextupoleSpec), (:octupole, OctupoleSpec),
                     (:multipole, MultipoleSpec), (:sbend, SBendSpec))
    sch = keys(parameter_schema(ElementSpec{kind}))
    missing_keys = [k for k in READ_BY_COMPILE if !(k in sch)]
    println(rpad(String(kind), 12), " undeclared but read by _lattice_magnet: ", missing_keys)
end

println("\n  Does an undeclared-but-read key actually change tracking?  (warning says it does NOT)")
a = compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, nst=3))
for (kw, val) in ((:bend_fringe, false), (:e1, 0.2), (:h, 0.15), (:b0, 0.05),
                  (:fint1, 0.5), (:hface1, 0.1), (:bend_model, :drift_kick),
                  (:wedge_coeff, (0, 0)), (:curved_order, 2))
    b = compile_runtime(QuadrupoleSpec(; L=0.4, k1=1.4, nst=3, kw => val))
    d = maximum(abs, collect(a(U...)) .- collect(b(U...)))
    println("    quadrupole ", rpad(String(kw) * "=" * repr(val), 26),
            " max coordinate change = ", d)
end
println("\n  sbend + va/vs (undeclared) with fringe=:soft_quad, which the sbend schema advertises:")
a = compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, fringe=:soft_quad, nst=3))
b = compile_runtime(SBendSpec(L=0.9, angle=0.19, k1=1.4, fringe=:soft_quad, va=0.05, vs=0.02, nst=3))
println("    max coordinate change from va=0.05, vs=0.02 = ",
        maximum(abs, collect(a(U...)) .- collect(b(U...))))

# ---------------------------------------------------------------------------
# C. Newly declared `ref_tilt` on quad/sext/oct/multipole: is it consumed?
#    And do the placement wraps preserve symplecticity?
# ---------------------------------------------------------------------------
println("\n" * "="^116)
println("C. placement parameters newly declared in the U9 spec blocks: consumed? symplectic?")
println("="^116)
base = compile_runtime(QuadrupoleSpec(L=0.4, k1=1.4, nst=3))
for (kw, val) in ((:ref_tilt, 0.3), (:tilt, 0.3), (:x_offset, 1e-3), (:y_offset, 1e-3),
                  (:z_offset, 1e-3), (:x_pitch, 1e-3), (:y_pitch, 1e-3))
    e = compile_runtime(QuadrupoleSpec(; L=0.4, k1=1.4, nst=3, kw => val))
    d = maximum(abs, collect(base(U...)) .- collect(e(U...)))
    println(rpad("quadrupole $kw=$val", 34), " coordinate change = ", rpad(d, 24),
            " |J'SJ-S| = ", symp((a...) -> e(a...), U))
end
for (name, sp) in (("solenoid", SolenoidSpec(L=1.3, ks=1.7, ref_tilt=0.3, x_offset=1e-3)),
                   ("crab_dispersion", CrabDispersionSpec{Float64}(zeta1=0.11, ref_tilt=0.3, x_offset=1e-3)),
                   ("momentum_dispersion", MomentumDispersionSpec{Float64}(eta1=0.21, ref_tilt=0.3, x_offset=1e-3)),
                   ("xy_coupling", XYCouplingSpec{Float64}(r1=0.031, ref_tilt=0.3, x_offset=1e-3)),
                   ("linear6d", Linear6DSpec{Float64}(beta1=(3.1,2.2,40.0), dmu=(0.7,1.3,0.02), ref_tilt=0.3, x_offset=1e-3)),
                   ("drift", DriftSpec(L=0.9, ref_tilt=0.3, x_offset=1e-3)))
    e = compile_runtime(sp)
    println(rpad("$name + ref_tilt/x_offset", 34), " |J'SJ-S| = ", symp((a...) -> e(a...), U))
end

# ---------------------------------------------------------------------------
# D. Linear6D validator: Complex failure (U10-11) and a negative control.
# ---------------------------------------------------------------------------
println("\n" * "="^116)
println("D. Linear6D symplecticity validator: type genericity and negative control")
println("="^116)
Id = ntuple(k -> ((k-1) ÷ 6 == (k-1) % 6 ? 1.0 : 0.0), 36)
println("  Float64 identity:      ", O._linear6d_symplectic_error(Id))
try
    IdC = ntuple(k -> complex(Id[k], 0.0), 36)
    println("  ComplexF64 identity:   ", O._linear6d_symplectic_error(IdC))
catch e
    println("  ComplexF64 identity:   FAIL ", string(typeof(e)), ": ", first(sprint(showerror, e), 110))
end
try
    d = ForwardDiff.Dual(0.0, 1.0)
    IdD = ntuple(k -> ForwardDiff.Dual(Id[k], 0.0), 36)
    println("  Dual identity:         ", O._linear6d_symplectic_error(IdD))
catch e
    println("  Dual identity:         FAIL ", string(typeof(e)), ": ", first(sprint(showerror, e), 110))
end
println("\n  negative control -- perturb M[1,1] and see where the validator starts rejecting:")
for d in (1e-17, 1e-16, 1e-15, 1e-14, 1e-13, 1e-10)
    M = collect(Id); M[1] += d
    err = O._linear6d_symplectic_error(NTuple{36,Float64}(M))
    ok = try (O._validate_linear6d_symplectic(NTuple{36,Float64}(M)); true) catch; false end
    println("    delta=", rpad(d, 10), " ratio=", rpad(err.ratio, 24), " accepted=", ok)
end
println("\n  negative control -- non-symplectic but plausible matrix (scale x by 1+1e-12, px unchanged):")
M = collect(Id); M[1] = 1 + 1e-12
err = O._linear6d_symplectic_error(NTuple{36,Float64}(M))
println("    ratio=", err.ratio, "  accepted=",
        try (O._validate_linear6d_symplectic(NTuple{36,Float64}(M)); true) catch; false end)

# ---------------------------------------------------------------------------
# E. Fringe maps: are they exact gradients / canonical transformations?
# ---------------------------------------------------------------------------
println("\n" * "="^116)
println("E. individual fringe/geometry maps: symplectic residual of each kernel alone")
println("="^116)
maps = [
  ("_rot_xz(A=0.13)", (u...) -> O._rot_xz(0.13, u...)),
  ("_wedge(A=-0.13, b1=0.21)", (u...) -> O._wedge(-0.13, 0.21, u...)),
  ("_wedge(A=-0.13, b1=0)  -> _rot_xz", (u...) -> O._wedge(-0.13, 0.0, u...)),
  ("_wedge_quad(e=.13,b2=6,wc=(1,2))", (u...) -> O._wedge_quad(0.13, 6.0, 1.0, 2.0, u...)),
  ("_face(b1=.21,hface=.11,e=.13,+1)", (u...) -> O._face(0.21, 0.11, 0.13, 1.0, u...)),
  ("_face(...,-1)", (u...) -> O._face(0.21, 0.11, 0.13, -1.0, u...)),
  ("_fringe_dipole_exact(fint=hgap=0)", (u...) -> O._fringe_dipole_exact(0.21, 0.0, 0.0, 1.0, u...)),
  ("_fringe_dipole_exact(fint=.5,hgap=.03)", (u...) -> O._fringe_dipole_exact(0.21, 0.5, 0.03, 1.0, u...)),
  ("_fringe_dipole_exact(exit, sigma=-1)", (u...) -> O._fringe_dipole_exact(0.21, 0.5, 0.03, -1.0, u...)),
  ("_multipole_fringe(N=6, sigma=+1)", (u...) -> O._multipole_fringe((0.21,1.4,6.0,20.0,90.0,300.0), (0.0,0.5,2.0,7.0,30.0,100.0), 1.0, 0, false, u...)),
  ("_multipole_fringe(sigma=-1, drop1)", (u...) -> O._multipole_fringe((0.21,1.4,6.0,20.0,90.0,300.0), (0.0,0.5,2.0,7.0,30.0,100.0), -1.0, 0, true, u...)),
  ("_multipole_fringe(hf=2)", (u...) -> O._multipole_fringe((0.21,1.4,6.0,20.0,90.0,300.0), (0.0,0.5,2.0,7.0,30.0,100.0), 1.0, 2, false, u...)),
  ("_soft_quad_fringe(k1=1.4,ks1=.7,+1)", (u...) -> O._soft_quad_fringe(1.4, 0.7, 0.03, 0.02, 1.0, u...)),
  ("_soft_quad_fringe(sigma=-1)", (u...) -> O._soft_quad_fringe(1.4, 0.7, 0.03, 0.02, -1.0, u...)),
  ("_solenoid_edge as a map (k=.85)", (x,px,y,py,z,pz) -> (x, O._solenoid_edge(0.85,x,y,px,py)[1], y, O._solenoid_edge(0.85,x,y,px,py)[2], z, pz)),
  ("_curved_kick(M=8)", (u...) -> O._curved_kick(O._curved_potential_coeffs(Float64,(0.21,1.4,6.0),(0.0,0.5,2.0),0.21,8), Val(8), 0.9, u...)),
  ("_lattice_kick(h=0, six orders)", (u...) -> O._lattice_kick((0.21,1.4,6.0,20.0,90.0,300.0), (0.0,0.5,2.0,7.0,30.0,100.0), 0.0, 0.9, u...)),
  ("_lattice_kick(h=.21, pure normal dipole)", (u...) -> O._lattice_kick((0.21,), (0.0,), 0.21, 0.9, u...)),
]
for (n, f) in maps
    println(rpad(n, 46), " |J'SJ-S| = ", symp(f, U))
end
println("\n  NEGATIVE CONTROL -- _lattice_kick with h != 0 and content the exemption excludes")
println("  (must be NON-symplectic; this is what _needs_curved_potential exists to route away)")
for (nm, kn, ks) in (("skew dipole K0s", (0.0,), (0.05,)),
                     ("quad K1", (0.0, 1.4), (0.0, 0.0)),
                     ("sext K2", (0.0, 0.0, 6.0), (0.0, 0.0, 0.0)))
    r = symp((u...) -> O._lattice_kick(kn, ks, 0.21, 0.9, u...), U)
    println("    ", rpad(nm, 20), " |J'SJ-S| = ", r,
            "   _needs_curved_potential = ", O._needs_curved_potential(kn, ks, 0.21))
end

# ---------------------------------------------------------------------------
# F. _needs_curved_potential: total coverage of the Cauchy-Riemann condition
# ---------------------------------------------------------------------------
println("\n" * "="^116)
println("F. _needs_curved_potential vs the measured non-gradient of _lattice_kick, all orders 0..6")
println("="^116)
for i in 1:7, skew in (false, true)
    kn = ntuple(j -> (!skew && j == i) ? 1.0 : 0.0, 7)
    ks = ntuple(j -> ( skew && j == i) ? 1.0 : 0.0, 7)
    need = O._needs_curved_potential(kn, ks, 0.21)
    r = symp((u...) -> O._lattice_kick(kn, ks, 0.21, 0.9, u...), U)
    flag = need == (r > 1e-12) ? "consistent" : "*** MISMATCH ***"
    println("  K", i-1, skew ? "s" : " ", "  needs_table=", rpad(need, 6),
            " |J'SJ-S| of the closed kick = ", rpad(r, 24), "  ", flag)
end
