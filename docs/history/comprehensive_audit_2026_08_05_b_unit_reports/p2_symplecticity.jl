# P2 -- exact ForwardDiff symplecticity sweep over the U9 region.
#
# Residual is  max |J' S J - S|  with S = blockdiag([0 1; -1 0], x3) in the
# canonical (x, px, y, py, z, pz) ordering.  The Jacobian is EXACT (forward-mode
# AD of the tracking kernel), not a finite difference, so the only floor is
# roundoff in the map itself -- there is no differencing noise floor.
using Octopus, ForwardDiff
const O = Octopus

const S6 = let M = zeros(6, 6)
    for b in (1, 3, 5)
        M[b, b + 1] = 1.0
        M[b + 1, b] = -1.0
    end
    M
end

"Exact Jacobian of a 6-in/6-out map at u0, and its symplectic residual."
function symp(f, u0)
    J = ForwardDiff.jacobian(u -> collect(f(u[1], u[2], u[3], u[4], u[5], u[6])), collect(u0))
    return maximum(abs, transpose(J) * S6 * J - S6)
end

# One off-design-orbit, off-momentum, fully 6-D probe point.  Deliberately not
# on any symmetry plane: y != 0 and py != 0 activate the skew and the curved
# potential; pz != 0 activates every chromatic factor.
const U0 = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)
# A larger-amplitude point, to make sure the residual is not small merely
# because the nonlinearity is small.
const U1 = (7.0e-3, 2.0e-3, -5.0e-3, 1.5e-3, 3.0e-3, 5.0e-3)

rows = Tuple{String,Float64,Float64}[]
function record(name, spec; ctor=nothing)
    elem = ctor === nothing ? compile_runtime(spec) : ctor(spec)
    r0 = symp((a...) -> elem(a...), U0)
    r1 = symp((a...) -> elem(a...), U1)
    push!(rows, (name, r0, r1))
    println(rpad(name, 76), "  ", rpad(r0, 12), "  ", r1)
end

println("="^110)
println("P2  exact-Jacobian symplecticity sweep.  columns: residual at small amplitude / at large amplitude")
println("="^110)

# ---------------------------------------------------------------------------
# A. every multipole order, normal and skew, straight frame
# ---------------------------------------------------------------------------
println("\n--- A. every multipole order 0..7, normal and skew, straight frame, o2/nst=1 ---")
for n in 0:7
    kn = ntuple(i -> i == n + 1 ? 1.7 / factorial(min(n, 6)) : 0.0, n + 1)
    ks = ntuple(i -> i == n + 1 ? 0.0 : 0.0, n + 1)
    record("multipole K$n normal (kn[$(n+1)])",
           MultipoleSpec(L=0.35, kn=kn, ks=ks, nst=3, integrator_order=2))
    kss = ntuple(i -> i == n + 1 ? 1.3 / factorial(min(n, 6)) : 0.0, n + 1)
    record("multipole K$(n)s skew  (ks[$(n+1)])",
           MultipoleSpec(L=0.35, kn=ntuple(_ -> 0.0, n + 1), ks=kss, nst=3, integrator_order=2))
end

# ---------------------------------------------------------------------------
# B. curvature: h = 0, h = b0, h != b0, b0 = 0, and h != 0 with every order
# ---------------------------------------------------------------------------
println("\n--- B. curvature axis (drift/bend), o2, nst=3 ---")
record("drift h=0", DriftSpec(L=0.9))
record("drift h=0.21 (curved drift)", DriftSpec(L=0.9, h=0.21))
record("drift h=0.21 curved=false (warns)", DriftSpec(L=0.9, h=0.21, curved=false))
record("drift h=0 curved=true (curved closed form at h=0)", DriftSpec(L=0.9, h=0.0, curved=true))
record("sbend h=b0=0.21 on design orbit", SBendSpec(L=0.9, angle=0.21 * 0.9, bend_fringe=false))
record("sbend h=0.21 b0=0.13 (h != b0)", SBendSpec(L=0.9, h=0.21, b0=0.13, bend_fringe=false))
record("sbend h=0.13 b0=0.21 (h != b0, other way)", SBendSpec(L=0.9, h=0.13, b0=0.21, bend_fringe=false))
record("sbend h=0 b0=0.21 (straight-frame bend)", SBendSpec(L=0.9, h=0.0, b0=0.21, bend_fringe=false))
record("sbend h=0.21 b0=0 (= curved drift)", SBendSpec(L=0.9, h=0.21, b0=0.0, bend_fringe=false))
record("sbend |hL| > pi/2 (h=b0=2.2, L=0.9) other branch",
       SBendSpec(L=0.9, h=2.2, b0=2.2, bend_fringe=false))
record("sbend b0 tiny 1e-8 (cancellation-free branch)",
       SBendSpec(L=0.9, h=0.21, b0=1e-8, bend_fringe=false))

println("\n--- B2. curved frame x every multipole order (psi table path) ---")
for n in 0:6
    kn = ntuple(i -> i == n + 1 ? 1.1 / factorial(min(n, 6)) : 0.0, n + 1)
    record("sbend h=0.21 b0=0.21 + K$n normal, nst=3 o2",
           SBendSpec(L=0.9, h=0.21, b0=0.21, kn=kn, ks=ntuple(_ -> 0.0, n + 1),
                     nst=3, integrator_order=2, bend_fringe=false))
    ks = ntuple(i -> i == n + 1 ? 0.9 / factorial(min(n, 6)) : 0.0, n + 1)
    record("sbend h=0.21 b0=0.21 + K$(n)s skew,  nst=3 o2",
           SBendSpec(L=0.9, h=0.21, b0=0.21, kn=ntuple(_ -> 0.0, n + 1), ks=ks,
                     nst=3, integrator_order=2, bend_fringe=false))
end

# ---------------------------------------------------------------------------
# C. integrator order and nst
# ---------------------------------------------------------------------------
println("\n--- C. integrator order x nst, combined-function curved bend ---")
for ord in (2, 4), nst in (1, 2, 4, 8, 16)
    record("sbend h=b0=0.21 k1=1.4 k2=8 order=$ord nst=$nst",
           SBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, k2=8.0, nst=nst,
                     integrator_order=ord, bend_fringe=false))
end

println("\n--- C2. bend_model :exact vs :drift_kick ---")
for model in (:exact, :drift_kick), ord in (2, 4), nst in (1, 4)
    record("sbend h=b0=0.21 k1=1.4 model=$model order=$ord nst=$nst",
           SBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, nst=nst,
                     integrator_order=ord, bend_model=model, bend_fringe=false))
end

# ---------------------------------------------------------------------------
# D. fringes on and off, every mode, every kill combination
# ---------------------------------------------------------------------------
println("\n--- D. fringe stack ---")
for fr in (:none, :multipole, :soft_quad, :all), edge in (false, true)
    record("quad L=.4 k1=1.4 k1s=.7 fringe=$fr bend_fringe=$edge va=.03 vs=.02",
           QuadrupoleSpec(L=0.4, k1=1.4, k1s=0.7, fringe=fr, bend_fringe=edge,
                          va=0.03, vs=0.02, nst=3))
end
for fr in (:none, :multipole, :soft_quad, :all)
    record("sbend full faces fringe=$fr (e1,e2,fint,hgap,hface,wedge)",
           SBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, k2=6.0, e1=0.13, e2=-0.09,
                     fint1=0.5, fint2=0.4, hgap1=0.03, hgap2=0.025,
                     hface1=0.11, hface2=-0.07, fringe=fr, va=0.02, vs=0.01,
                     nst=3, integrator_order=4))
end
for k1 in (false, true), k2 in (false, true)
    record("sbend full faces kill_ent=$k1 kill_exi=$k2 fringe=:all",
           SBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, e1=0.13, e2=-0.09,
                     fint1=0.5, fint2=0.4, hgap1=0.03, hgap2=0.025,
                     hface1=0.11, hface2=-0.07, fringe=:all, va=0.02, vs=0.01,
                     kill_ent_fringe=k1, kill_exi_fringe=k2, nst=3))
end
for hf in (0, 1, 2, 3)
    record("multipole fringe cap highest_fringe=$hf",
           MultipoleSpec(L=0.4, k1=1.4, k2=8.0, k3=40.0, k1s=0.6, k2s=3.0,
                         fringe=:multipole, highest_fringe=hf, nst=3))
end
for wc in ((1, 2), (0, 0), (0.7, 1.3))
    record("sbend wedge_coeff=$wc",
           SBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, e1=0.13, e2=-0.09,
                     wedge_coeff=wc, nst=3))
end
record("rbend (e1,e2 += angle/2) fringe=:all",
       RBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, fringe=:all, va=0.02, vs=0.01,
                 fint1=0.5, hgap1=0.03, nst=3))

# ---------------------------------------------------------------------------
# E. curved_order convergence knob -- truncation must never cost symplecticity
# ---------------------------------------------------------------------------
println("\n--- E. curved_order (psi truncation) -- must be symplectic at EVERY order ---")
for m in (1, 2, 3, 4, 8, 12)
    record("sbend h=b0=0.21 k1=1.4 k2=8 k1s=.6 curved_order=$m",
           SBendSpec(L=0.9, angle=0.21 * 0.9, k1=1.4, k2=8.0, k1s=0.6,
                     curved_order=m, nst=3, bend_fringe=false))
end

# ---------------------------------------------------------------------------
# F. solenoid
# ---------------------------------------------------------------------------
println("\n--- F. solenoid: straight (exact closed form) ---")
record("solenoid pure straight L=1.3 ks=1.7", SolenoidSpec(L=1.3, ks=1.7); ctor=Solenoid)
record("solenoid pure straight ks=0 (= drift)", SolenoidSpec(L=1.3, ks=0.0); ctor=Solenoid)
record("solenoid straight + k1 (Strang) nst=4",
       SolenoidSpec(L=1.3, ks=1.7, k1=0.9, nst=4); ctor=Solenoid)
record("solenoid straight + k1,k2,k1s,k2s nst=8",
       SolenoidSpec(L=1.3, ks=1.7, k1=0.9, k2=4.0, k1s=0.4, k2s=2.0, nst=8); ctor=Solenoid)
record("solenoid h=0.18 curved=false (warns; must equal straight)",
       SolenoidSpec(L=1.3, ks=1.7, h=0.18, curved=false); ctor=Solenoid)
record("solenoid h=0.18 curved=false + k1s (was U10-3, 2.5e-3)",
       SolenoidSpec(L=1.3, ks=1.7, h=0.18, k0s=0.05, curved=false); ctor=Solenoid)

println("\n--- F2. solenoid: CURVED, implicit midpoint, nst convergence ---")
println("     (the documented floor: 1.1e-9 at nst=4 falling to 1.1e-16 by nst=16)")
for nst in (1, 2, 4, 8, 12, 16, 24, 32, 64)
    record("solenoid pure CURVED h=0.18 ks=1.7 L=1.3 nst=$nst",
           SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=nst); ctor=Solenoid)
end
for nst in (4, 8, 16, 32)
    record("solenoid CURVED h=0 curved=true nst=$nst (integrator on straight frame)",
           SolenoidSpec(L=1.3, ks=1.7, h=0.0, curved=true, nst=nst); ctor=Solenoid)
end
for nst in (4, 16, 32)
    record("solenoid CURVED h=0.18 + k1=0.9 nst=$nst",
           SolenoidSpec(L=1.3, ks=1.7, h=0.18, k1=0.9, nst=nst); ctor=Solenoid)
    record("solenoid CURVED h=0.18 + k0s=0.05 (skew dipole, psi path) nst=$nst",
           SolenoidSpec(L=1.3, ks=1.7, h=0.18, k0s=0.05, nst=nst); ctor=Solenoid)
    record("solenoid CURVED h=0.18 + k0=0.05 (normal dipole, closed kick) nst=$nst",
           SolenoidSpec(L=1.3, ks=1.7, h=0.18, k0=0.05, nst=nst); ctor=Solenoid)
end

# ---------------------------------------------------------------------------
# G. linear maps
# ---------------------------------------------------------------------------
println("\n--- G. linear6d and linear_maps ---")
record("crab_dispersion all four zeta",
       CrabDispersionSpec{Float64}(zeta1=0.11, zeta2=-0.07, zeta3=0.05, zeta4=0.03))
record("momentum_dispersion all four eta",
       MomentumDispersionSpec{Float64}(eta1=0.21, eta2=-0.13, eta3=0.09, eta4=-0.04))
record("xy_coupling MODEA", XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041))
record("xy_coupling MODEB",
       XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041, mode=XY_MODEB))
record("xy_coupling UNDEF (identity)",
       XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041, mode=XY_UNDEF))
record("linear6d identity", Linear6DSpec{Float64}(matrix=[i == j ? 1.0 : 0.0 for i in 1:6, j in 1:6]))
record("linear6d from optics (beta/alpha/dmu + zeta/eta/R)",
       Linear6DSpec{Float64}(beta1=(3.1, 2.2, 40.0), beta2=(1.7, 4.5, 55.0),
                             alpha1=(0.3, -0.7, 0.1), alpha2=(-0.2, 0.5, -0.05),
                             dmu=(0.7, 1.3, 0.02),
                             zeta1=(0.01, -0.02, 0.03, 0.004),
                             eta1=(0.2, -0.1, 0.05, -0.03),
                             R1=(0.02, 0.01, -0.03, 0.015),
                             zeta2=(0.005, 0.007, -0.001, 0.002),
                             eta2=(0.15, 0.09, -0.02, 0.01),
                             R2=(-0.01, 0.02, 0.005, -0.02)))

println("\n" * "="^110)
worst = sort(rows, by=r -> -max(r[2], r[3]))
println("WORST 15 of $(length(rows)) cases:")
for r in worst[1:min(15, end)]
    println("  ", rpad(r[1], 76), "  ", rpad(r[2], 12), "  ", r[3])
end
println("\nGlobal worst residual = ", maximum(max(r[2], r[3]) for r in rows))
println("Cases with residual > 1e-14 (excluding curved-solenoid discretization):")
for r in rows
    m = max(r[2], r[3])
    m > 1e-14 && println("  ", rpad(r[1], 76), "  ", m)
end
