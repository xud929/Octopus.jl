# P5 -- targeted probes on the leads the sweep surfaced.
using Octopus, ForwardDiff
const O = Octopus
setprecision(BigFloat, 300)

const S6 = let M = zeros(6, 6); for b in (1,3,5); M[b,b+1]=1.0; M[b+1,b]=-1.0; end; M end
symp(f, u0) = maximum(abs, let J = ForwardDiff.jacobian(u -> collect(f(u...)), collect(u0))
    transpose(J) * S6 * J - S6 end)
const U = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)

# ---------------------------------------------------------------------------
# A. The curved solenoid's implicit stage: is a non-converged solve SILENT?
# ---------------------------------------------------------------------------
println("="^112)
println("A. curved solenoid: fixed-point residual of the implicit stage after the fixed 16 sweeps")
println("   (the solve is never checked; _SOL_MIDPOINT_ITERS is a compile-time constant)")
println("="^112)
"Re-run one implicit-midpoint step, reporting the change in the midpoint state over the last sweep."
function midpoint_solve_residual(h, ks, L, nst, x, px, y, py, z, pz)
    d = L / nst
    worst = 0.0
    for _ in 1:nst
        mx, mpx, my, mpy = x, px, y, py
        prev = (mx, mpx, my, mpy)
        for it in 1:O._SOL_MIDPOINT_ITERS
            fx, fpx, fy, fpy, fz, _ = O._sol_curved_deriv(h, ks, mx, mpx, my, mpy, pz)
            prev = (mx, mpx, my, mpy)
            mx = x + d/2*fx; mpx = px + d/2*fpx; my = y + d/2*fy; mpy = py + d/2*fpy
        end
        worst = max(worst, maximum(abs, (mx, mpx, my, mpy) .- prev))
        fx, fpx, fy, fpy, fz, _ = O._sol_curved_deriv(h, ks, mx, mpx, my, mpy, pz)
        x += d*fx; px += d*fpx; y += d*fy; py += d*fpy; z += d*fz
    end
    return worst
end
println(rpad("nst",6), rpad("last-sweep change in midpoint state", 40),
        rpad("|J'SJ-S|", 26), "tracked x")
for nst in (1, 2, 3, 4, 6, 8, 12, 16, 32)
    e = Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=nst))
    r = midpoint_solve_residual(0.18, 1.7, 1.3, nst, U...)
    s = symp((a...) -> e(a...), U)
    println(rpad(nst,6), rpad(r, 40), rpad(s, 26), e(U...)[1])
end
println("\nreference (nst=256): x = ", Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=256))(U...)[1])

# ---------------------------------------------------------------------------
# B. Is `_sol_gp` the exact derivative of the COMPUTED `_sol_g`?
#    (implicit midpoint is symplectic only for a true gradient field)
# ---------------------------------------------------------------------------
println("\n" * "="^112)
println("B. consistency of _sol_gp with d(_sol_g)/dx  (AD through the series/closed branches)")
println("="^112)
for h in (1e-1, 1e-2, 5e-3, 1e-4, 1e-8, 0.0), x in (1e-3, 1e-2, 1.0)
    gp_direct = O._sol_gp(h, x)
    gp_ad = ForwardDiff.derivative(t -> O._sol_g(h, t), x)
    println(rpad("h=$h x=$x", 26), " _sol_gp=", rpad(gp_direct, 22),
            " d(_sol_g)/dx=", rpad(gp_ad, 22), " abs diff=", abs(gp_direct - gp_ad))
end

# ---------------------------------------------------------------------------
# C. curved-frame K0: why is the residual 7e-15 and not 2e-16?  conditioning?
# ---------------------------------------------------------------------------
println("\n" * "="^112)
println("C. curved sbend + strong normal dipole kick K0: residual vs kick strength (conditioning check)")
println("="^112)
for k0 in (0.01, 0.1, 0.5, 1.1)
    e = compile_runtime(SBendSpec(L=0.9, h=0.21, b0=0.21, kn=(k0,), nst=3, bend_fringe=false))
    J = ForwardDiff.jacobian(u -> collect(e(u...)), collect(U))
    println(rpad("K0=$k0", 14), " |J'SJ-S| = ", rpad(symp((a...) -> e(a...), U), 26),
            " max|J| = ", rpad(maximum(abs, J), 22), " ratio/eps|J|^2 = ",
            symp((a...) -> e(a...), U) / (eps() * maximum(abs, J)^2))
end

# ---------------------------------------------------------------------------
# D. `_wedge` small-b1: U10-7's recorded 1/b1 cancellation, vs BigFloat
# ---------------------------------------------------------------------------
println("\n" * "="^112)
println("D. _wedge at small b1 vs a 300-bit reference of the SAME closed form (U10-7 regression)")
println("="^112)
function wedge_big(A, b1, x, px, y, py, z, pz)
    A = BigFloat(A); b1 = BigFloat(b1); x = BigFloat(x); px = BigFloat(px)
    y = BigFloat(y); py = BigFloat(py); z = BigFloat(z); pz = BigFloat(pz)
    ps = sqrt((1+pz)^2 - px^2 - py^2)
    pxn = px*cos(A) + (ps - b1*x)*sin(A)
    psn = sqrt((1+pz)^2 - pxn^2 - py^2)
    xn = x*cos(A) + (x*px*sin(2A) + sin(A)^2*(2*x*ps - b1*x*x)) / (psn + ps*cos(A) - px*sin(A))
    w = sqrt((1+pz)^2 - py^2)
    D = (A + asin(px/w) - asin(pxn/w)) / b1
    return xn, pxn, y + py*D, py, z - D*(1+pz), pz
end
p = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)
println(rpad("b1", 12), rpad("|dz|", 26), rpad("|dy|", 26), "|J'SJ-S|")
for b1 in (1.0, 1e-2, 1e-4, 1e-6, 1e-8, 1e-10, 1e-12, 1e-14)
    got = O._wedge(0.1, b1, p...)
    ex = wedge_big(0.1, b1, p...)
    e = O._wedge  # closure below
    s = symp((a...) -> O._wedge(0.1, b1, a...), p)
    println(rpad(b1, 12), rpad(Float64(abs(BigFloat(got[5]) - ex[5])), 26),
            rpad(Float64(abs(BigFloat(got[3]) - ex[3])), 26), s)
end
println("b1 -> 0 limit vs _rot_xz(A):")
for b1 in (1e-6, 1e-9, 1e-12, 0.0)
    a = O._wedge(0.1, b1, p...)
    b = O._rot_xz(0.1, p...)
    println("  b1=", rpad(b1, 10), " max|wedge - rot_xz| = ", maximum(abs, collect(a) .- collect(b)))
end

# ---------------------------------------------------------------------------
# E. `_lattice_bend` small-b0 and branch continuity (recorded fix regression)
# ---------------------------------------------------------------------------
println("\n" * "="^112)
println("E. _lattice_bend: b0 -> 0 agreement with the curved drift, and |hL| = pi/2 branch continuity")
println("="^112)
for b0 in (1e-3, 1e-6, 1e-9, 1e-12, 1e-16, 0.0)
    a = O._lattice_bend(0.21, b0, 0.9, p...)
    b = O._lattice_drift(Val(true), 0.21, 0.9, p...)
    println("  b0=", rpad(b0, 10), " max|bend - curved drift| = ", maximum(abs, collect(a) .- collect(b)),
            "   |J'SJ-S| = ", symp((u...) -> O._lattice_bend(0.21, b0, 0.9, u...), p))
end
println("  branch seam at |hL| = pi/2 (L = 1, h = pi/2 +- eps):")
for d in (1e-6, 1e-9, 1e-12)
    a = O._lattice_bend(pi/2 - d, 0.21, 1.0, p...)
    b = O._lattice_bend(pi/2 + d, 0.21, 1.0, p...)
    println("    eps=", rpad(d, 10), " max|below - above| = ", maximum(abs, collect(a) .- collect(b)))
end

# ---------------------------------------------------------------------------
# F. `_curved_potential_coeffs`: independent re-derivation of the recursion
# ---------------------------------------------------------------------------
println("\n" * "="^112)
println("F. curved-frame potential: does the tabulated Psi satisfy the Maxwell recursion and the seeds?")
println("   Psi_{k+2} = -Psi_k'' + h/(1+hx) Psi_k' ;  Psi_0' = -(1+hx)By(x,0) ;  Psi_1 = (1+hx)Bx(x,0)")
println("="^112)
function check_psi(kn, ks, h, M)
    psi = O._curved_potential_coeffs(Float64, kn, ks, h, M)
    np = M + 1
    # Psi(x, y) = sum_{k,j} psi[k*np+j+1] x^j y^k   (y^k/k! already folded in)
    Psi(x, y) = sum(psi[k*np + j + 1] * x^j * y^k for k in 0:M, j in 0:M)
    # 1. gradient of Psi vs the field it should reproduce on the midplane
    By0(x) = sum(kn[n+1] * x^n / factorial(n) for n in 0:length(kn)-1)
    Bx0(x) = sum(ks[n+1] * x^n / factorial(n) for n in 0:length(ks)-1)
    errs = Float64[]
    for x in (-0.02, -0.005, 0.0, 0.005, 0.02)
        dPdx = ForwardDiff.derivative(t -> Psi(t, 0.0), x)
        dPdy = ForwardDiff.derivative(t -> Psi(x, t), 0.0)
        push!(errs, abs(dPdx + (1 + h*x) * By0(x)))
        push!(errs, abs(dPdy - (1 + h*x) * Bx0(x)))
    end
    # 2. the Maxwell PDE the potential must satisfy:
    #    Psi_xx + Psi_yy - h/(1+hx) Psi_x = 0  (equivalent to the recursion)
    pde = Float64[]
    for x in (-0.01, 0.0, 0.01), y in (-0.01, 0.0, 0.01)
        Pxx = ForwardDiff.derivative(t -> ForwardDiff.derivative(s -> Psi(s, y), t), x)
        Pyy = ForwardDiff.derivative(t -> ForwardDiff.derivative(s -> Psi(x, s), t), y)
        Px = ForwardDiff.derivative(t -> Psi(t, y), x)
        push!(pde, abs(Pxx + Pyy - h/(1 + h*x) * Px))
    end
    return maximum(errs), maximum(pde)
end
for (name, kn, ks, h, M) in (
        ("pure normal dipole K0", (0.21,), (0.0,), 0.21, 8),
        ("skew dipole K0s", (0.0,), (0.05,), 0.21, 8),
        ("quad K1", (0.0, 1.4), (0.0, 0.0), 0.21, 8),
        ("combined K0,K1,K2 + skew", (0.21, 1.4, 6.0), (0.0, 0.5, 2.0), 0.21, 8),
        ("combined, M = 4 (coarse)", (0.21, 1.4, 6.0), (0.0, 0.5, 2.0), 0.21, 4),
        ("combined, M = 12", (0.21, 1.4, 6.0), (0.0, 0.5, 2.0), 0.21, 12),
        ("large h = 1.0", (0.21, 1.4), (0.0, 0.5), 1.0, 8))
    seed, pde = check_psi(kn, ks, h, M)
    println(rpad(name, 34), " max midplane-seed error = ", rpad(seed, 24),
            " max PDE residual = ", pde)
end

# ---------------------------------------------------------------------------
# G. `_lattice_kick`: normalization against the closed-form field sum
# ---------------------------------------------------------------------------
println("\n" * "="^112)
println("G. _lattice_kick vs  dpx - i dpy = -L (1+hx) sum_n (K_n + i Ks_n) (x+iy)^n / n!")
println("="^112)
for (kn, ks, h) in (((0.21, 1.4, 6.0, 20.0, 90.0, 300.0), (0.0, 0.5, 2.0, 7.0, 30.0, 100.0), 0.0),
                    ((0.21,), (0.0,), 0.21),
                    ((0.0, 1.4), (0.0, 0.0), 0.0))
    x, px, y, py, z, pz = U
    out = O._lattice_kick(kn, ks, h, 0.9, x, px, y, py, z, pz)
    w = complex(x, y)
    f = sum((kn[n+1] + im*ks[n+1]) * w^n / factorial(n) for n in 0:length(kn)-1)
    dpx = -0.9 * (1 + h*x) * real(f)
    dpy = +0.9 * (1 + h*x) * imag(f)
    println("  kn=", kn, " h=", h,
            "\n    dpx: code=", out[2] - px, " ref=", dpx, " diff=", abs((out[2]-px) - dpx),
            "\n    dpy: code=", out[4] - py, " ref=", dpy, " diff=", abs((out[4]-py) - dpy))
end
