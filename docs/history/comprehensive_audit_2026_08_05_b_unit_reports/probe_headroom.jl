# Headroom measurement for the tolerances asserted in test/runtests.jl lines
# 1-2200.  Prints measured value vs asserted bound for each threshold.
using Octopus, LinearAlgebra, ForwardDiff

S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
form6 = zeros(6, 6)
for c in (1, 3, 5); form6[c, c+1] = 1; form6[c+1, c] = -1; end
cs_jac(e, u0) = begin
    J = zeros(6, 6)
    for j in 1:6
        v = ComplexF64[u0...]; v[j] += 1e-30im
        J[:, j] = imag.(collect(e(v...))) ./ 1e-30
    end
    J
end
report(tag, val, bound, cmp=:lt) = println(rpad(tag, 62), " = ", val,
    "   bound ", cmp === :lt ? "< " : "> ", bound,
    "   headroom x", cmp === :lt ? bound / val : val / bound)

println("### A. _curv_vers closed branch, 1-ulp sensitivity of cos (test line 1599-1601)")
vers_ref(h) = (1 - cos(big(h))) / big(h)
relerr(v, ref) = Float64(abs((big(v) - ref) / ref))
for h in (prevfloat(0.125), nextfloat(0.125), 0.13, 0.15)
    e0 = relerr(Octopus._curv_vers(h, 1.0), vers_ref(h))
    c = cos(h)
    alts = [(1 - cc) / h for cc in (prevfloat(c), c, nextfloat(c))]
    es = [relerr(a, vers_ref(h)) for a in alts]
    println("  h=", h, "  relerr=", e0, "  bound 1e-14  headroom x", 1e-14 / max(e0, 1e-30),
            "   |  relerr if cos were off by -1/0/+1 ulp: ", es)
end

println("\n### B. near-round transition symplectic residual (test line 581, bound 2e-8)")
covxy(A, B, Q) = begin
    c = [A B; transpose(B) Q]; p = [1, 3, 2, 4]; c[p, p]
end
let (_, outer) = Octopus._near_round_eta_bounds(0.0)
    eta = 0.75 * outer
    A = Matrix(Diagonal([1 + eta, 1 - eta])); B = Matrix(Diagonal([0.03, -0.02]))
    Q = transpose(B) * (A \ B) + 0.3I
    el = ThinStrongBeam(ThinStrongBeamSpec(; kbb=0.7, covariance=covxy(A, B, Matrix(Q))))
    q0 = [0.4, 1.0e-4, -0.2, -1.5e-4, 0.0, 2.0e-4]; h = 1.0e-5
    mapq(q) = collect(el(q...))
    J = hcat([(mapq(q0 .+ (collect(1:6) .== c) .* h) - mapq(q0 .- (collect(1:6) .== c) .* h)) / (2h) for c in 1:6]...)
    report("  transition symplectic residual", norm(transpose(J) * form6 * J - form6, Inf), 2.0e-8)
    # what a broken (non-symplectic) map would score: drop the pz feedback term
    println("  (for scale) residual with the longitudinal kick zeroed:")
    el2 = ThinStrongBeam(ThinStrongBeamSpec(; kbb=0.7, covariance=covxy(A, B, Matrix(Q))))
    m2(q) = (o = collect(el2(q...)); o[6] = q[6]; o)
    J2 = hcat([(m2(q0 .+ (collect(1:6) .== c) .* h) - m2(q0 .- (collect(1:6) .== c) .* h)) / (2h) for c in 1:6]...)
    println("     ", norm(transpose(J2) * form6 * J2 - form6, Inf))
end

println("\n### C. coupled weak-strong (test lines 670, 709, 727, 739, 756)")
let
    uncoupled = transverse_covariance(; beta=(0.8, 1.2), alpha=(0.3, -0.2), sigma=(1.1, 0.7))
    coupling = XYCouplingSpec{Float64}(r1=0.08, r2=0.03, r3=-0.02, r4=0.05)
    coupled = ThinStrongBeam(ThinStrongBeamSpec(; kbb=1.0e-7, beta=(0.8, 1.2), alpha=(0.3, -0.2),
        sigma=(1.1, 0.7), coupling=coupling, center=(2.0e-5, -1.0e-5, 3.0e-4),
        angle=(3.0e-4, -2.0e-4, 0.0), curvature=(2.0e-3, -1.0e-3, 0.0), virtual_drift=:hirata))
    q0 = [0.4, 1.0e-4, -0.2, -1.5e-4, 1.2e-3, 2.0e-4]; h = 3.0e-7
    mapq(q) = collect(coupled(q...))
    J = hcat([(mapq(q0 .+ (collect(1:6) .== c) .* h) - mapq(q0 .- (collect(1:6) .== c) .* h)) / (2h) for c in 1:6]...)
    report("  coupled symplectic residual", norm(transpose(J) * form6 * J - form6, Inf), 2.0e-8)
    static_covariance = Matrix(Diagonal([1.4, 0.0, 0.8, 0.0]))
    static = ThinStrongBeam(ThinStrongBeamSpec(; kbb=0.2, covariance=static_covariance,
        center=(0.1, -0.05, 0.0), angle=(0.0, 0.0, 0.0)))
    sr = static(0.4, 0.0, -0.2, 0.0, 0.0, 0.0)
    println("  item 3 rel dev = ", abs(sr[6] - (sr[2]^2 + sr[4]^2) / 4) / abs(sr[6]), "  rtol 2e-13")
end

println("\n### D. virtual drift symplecticity scan (test lines 794-805)")
let
    cov = [1.21e-8 1.0e-9 2.4e-9 -3.0e-10; 1.0e-9 4.0e-8 2.0e-10 1.5e-9;
           2.4e-9 2.0e-10 6.4e-9 -6.0e-10; -3.0e-10 1.5e-9 -6.0e-10 2.25e-8]
    q0 = [4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4]
    res(d, step) = begin
        e = ThinStrongBeam(ThinStrongBeamSpec{Float64}(; kbb=1.0e-8, covariance=cov,
            center=(2.0e-5, -1.0e-5, 3.0e-4), angle=(3.0e-4, -2.0e-4, 0.0), virtual_drift=d))
        J = hcat([(collect(e((q0 .+ (collect(1:6) .== c) .* step)...)) -
                   collect(e((q0 .- (collect(1:6) .== c) .* step)...))) / (2step) for c in 1:6]...)
        norm(transpose(J) * form6 * J - form6, Inf)
    end
    for d in (:hirata, :chromatic, :exact)
        f, c = res(d, 3.0e-7), res(d, 3.0e-6)
        println("  ", d, ": fine=", f, " (<5e-7, headroom x", 5.0e-7 / f, ")  ratio=", c / f, " (50..200)")
    end
    for d in (UnsafeVirtualDrift(:chromatic_frozen_energy), UnsafeVirtualDrift(:paraxial_frozen_longitudinal))
        f, c = res(d, 3.0e-7), res(d, 3.0e-6)
        println("  ", d, ": fine=", f, " (>1e-5, headroom x", f / 1.0e-5, ")  ratio=", c / f, " (isapprox rtol .05)")
    end
end

println("\n### E. lattice magnets (test lines 1051, 1076, 1088, 1128, 1139)")
let u0 = (1.3e-3, 3.0e-4, -0.9e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    worst = 0.0
    for spec in (DriftSpec(L=0.7), DriftSpec(L=0.7, h=0.21), QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=2),
                 SextupoleSpec(L=0.25, kn=(0.0, 0.0, 14.0), nst=2, fringe=:all, va=0.03, vs=1.0e-4),
                 SBendSpec(L=1.1, h=0.18, b0=0.18, e1=0.09, e2=0.09, fint1=0.5, fint2=0.5,
                           hgap1=0.03, hgap2=0.03, bend_fringe=true, nst=2),
                 SBendSpec(L=1.1, h=0.18, b0=0.18, ks=(0.05,), nst=2))
        J = cs_jac(compile_runtime(spec), u0)
        worst = max(worst, maximum(abs, J' * S6 * J - S6))
    end
    report("  worst symplectic residual (subset)", worst, 1.0e-13)
    straight = collect(compile_runtime(DriftSpec(L=0.7))(u0...))
    d = maximum(abs, collect(compile_runtime(DriftSpec(L=0.7, h=1.0e-9))(u0...)) .- straight)
    report("  drift h=1e-9 departure", d, 1.0e-8)
    ref = collect(compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=4096, integrator_order=4))(u0...))
    err(o, n) = maximum(abs, collect(compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=n, integrator_order=o))(u0...)) .- ref)
    println("  err(2,4)/err(2,8) = ", err(2, 4) / err(2, 8), " (>3.5)   err(4,4)/err(4,8) = ",
            err(4, 4) / err(4, 8), " (>12)")
    refc = collect(compile_runtime(SBendSpec(L=1.0, h=0.18, b0=0.18, kn=(0.0, 0.6), nst=4, curved_order=16))(u0...))
    errc(M) = maximum(abs, collect(compile_runtime(SBendSpec(L=1.0, h=0.18, b0=0.18, kn=(0.0, 0.6), nst=4, curved_order=M))(u0...)) .- refc)
    println("  curved_order err(2)=", errc(2), "  err(6)=", errc(6), " (<1e-13)")
    st = collect(compile_runtime(QuadrupoleSpec(L=0.5, kn=(0.0, 1.7), nst=4))(u0...))
    dh = maximum(abs, collect(compile_runtime(SBendSpec(L=0.5, h=1.0e-6, b0=0.0, kn=(0.0, 1.7), nst=4))(u0...)) .- st)
    report("  curved->straight h=1e-6 departure", dh, 1.0e-5)
end

println("\n### F/G/H. misalignment, ref_tilt, thin elements")
let u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    w = 0.0
    for s in (QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=1e-3, y_offset=-8e-4, z_offset=2e-3,
                             x_pitch=1e-3, y_pitch=-7e-4, tilt=0.02),
              SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1, nst=4, fringe=:multipole,
                        x_offset=1e-3, y_pitch=-7e-4, tilt=0.02))
        J = cs_jac(compile_runtime(s), u); w = max(w, maximum(abs, J' * S6 * J - S6))
    end
    report("  misaligned symplectic residual", w, 1.0e-13)
    φ = 0.037; k1 = 1.7
    a = compile_runtime(QuadrupoleSpec(L=0.4, k1=k1, nst=8, tilt=φ))
    b = compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, k1 * cos(2φ)), ks=(0.0, -k1 * sin(2φ)), nst=8))
    report("  roll==skew identity", maximum(abs, collect(a(u...)) .- collect(b(u...))), 1.0e-15)
    # negative control: wrong sign on the skew term
    b2 = compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, k1 * cos(2φ)), ks=(0.0, k1 * sin(2φ)), nst=8))
    println("     with the skew sign flipped: ", maximum(abs, collect(a(u...)) .- collect(b2(u...))))
    dx = 2.0e-4
    aligned = [QuadrupoleSpec(L=0.4, k1=1.7, nst=4), DriftSpec(L=0.6), QuadrupoleSpec(L=0.4, k1=-1.7, nst=4), DriftSpec(L=0.6)]
    moved = [QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=dx), DriftSpec(L=0.6),
             QuadrupoleSpec(L=0.4, k1=-1.7, nst=4, x_offset=dx), DriftSpec(L=0.6)]
    trk(line, v) = foldl((c, s) -> compile_runtime(s)(c...), line; init=v)
    o1 = collect(trk(aligned, u)); o2 = collect(trk(moved, (u[1] + dx, u[2], u[3], u[4], u[5], u[6]))); o2[1] -= dx
    report("  rigid-displacement frame invariance", maximum(abs, o1 .- o2), 1.0e-15)
    # negative control: half the displacement on the second quad only
    moved2 = [QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=dx), DriftSpec(L=0.6),
              QuadrupoleSpec(L=0.4, k1=-1.7, nst=4, x_offset=dx * (1 + 1e-9)), DriftSpec(L=0.6)]
    o3 = collect(trk(moved2, (u[1] + dx, u[2], u[3], u[4], u[5], u[6]))); o3[1] -= dx
    println("     with one quad displaced by dx*(1+1e-9): ", maximum(abs, o1 .- o3))
    h = compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4))
    v = compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=pi / 2))
    x, px, y, py, z, pz = u
    X, PX, Y, PY, Z, PZ = h(y, py, -x, -px, z, pz)
    report("  vertical bend == rotated horizontal", maximum(abs, collect(v(u...)) .- (-Y, -PY, X, PX, Z, PZ)), 1.0e-15)
    for s in (DriftSpec(L=0.7), SolenoidSpec(L=1.3, ks=0.35))
        rolled = compile_runtime(typeof(s)(; params(s)..., ref_tilt=0.41))
        report("  roll-invariance of $(kind(s))", maximum(abs, collect(rolled(u...)) .- collect(compile_runtime(s)(u...))), 1.0e-15)
    end
end

println("\n### I. complex-step vs central difference on parameters (test 2110/2119/2127)")
let u = (1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.0, 1.0e-3), h = 1e-30
    dk1(v) = [imag(x) / h for x in compile_runtime(QuadrupoleSpec(L=0.4, k1=complex(v, h), nst=4))(u...)]
    ref(k) = collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=k, nst=4))(u...))
    report("  d/dk1", maximum(abs, dk1(1.7) .- (ref(1.7 + 1e-6) .- ref(1.7 - 1e-6)) ./ 2e-6), 1.0e-9)
    dx(v) = [imag(x) / h for x in compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=complex(v, h)))(u...)]
    refx(d) = collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=d))(u...))
    report("  d/dx_offset", maximum(abs, dx(1.0e-3) .- (refx(1.0e-3 + 1e-8) .- refx(1.0e-3 - 1e-8)) ./ 2e-8), 1.0e-8)
    dh(v) = [imag(x) / h for x in compile_runtime(SBendSpec(L=1.1, h=complex(v, h), b0=0.18, k1=0.6, e1=0.05, nst=4))(u...)]
    refh(g) = collect(compile_runtime(SBendSpec(L=1.1, h=g, b0=0.18, k1=0.6, e1=0.05, nst=4))(u...))
    report("  d/dh", maximum(abs, dh(0.18) .- (refh(0.18 + 1e-6) .- refh(0.18 - 1e-6)) ./ 2e-6), 1.0e-8)
end

println("\n### J. Furman Table 1 margins (test lines 899-900, bound 5e-6)")
let table1 = Dict(
        :equal_spacing_density => ([-1.166667, -0.5833333, 0.0, 0.5833333, 1.166667],
                                   [0.1368561, 0.2280002, 0.2702873, 0.2280002, 0.1368561]),
        :equal_area => ([-1.281552, -0.5244005, 0.0, 0.5244005, 1.281552], fill(0.2, 5)),
        :equal_area_centroid => ([-1.399809, -0.5319032, 0.0, 0.5319032, 1.399809], fill(0.2, 5)),
        :sqrt_density => ([-1.59898, -0.67872, 0.0, 0.67872, 1.59898],
                          [0.137503, 0.232216, 0.260561, 0.232216, 0.137503]),
        :min_cdf_area => ([-1.44156, -0.63623, 0.0, 0.63623, 1.44156],
                          [0.14943, 0.22577, 0.24960, 0.22577, 0.14943]))
    for (m, (c, w)) in table1
        z, ww = Octopus._gaussian_slices(Float64, 5, nothing, nothing, 1.0, m, nothing)
        println("  ", rpad(m, 24), " dz=", maximum(abs, collect(z) .- c),
                "  dw=", maximum(abs, collect(ww) .- w), "   bound 5e-6")
    end
    println("  SLICE_METHODS = ", Octopus.SLICE_METHODS, " (n=", length(Octopus.SLICE_METHODS), ")")
end

println("\n### K. round-Gaussian reference agreement (test lines 445/451)")
let
    rr(T, sigma, x, y) = setprecision(BigFloat, 256) do
        sb, xb, yb = BigFloat(sigma), BigFloat(x), BigFloat(y)
        r2 = xb * xb + yb * yb; u = r2 / (2 * sb * sb)
        phi = iszero(u) ? one(u) : -expm1(-u) / u
        s = phi / (sb * sb); (T(s * xb), T(s * yb))
    end
    for T in (Float32, Float64)
        sigma = one(T)
        for (x, y) in ((T(T === Float32 ? 1.0f-4 : 1.0e-8), T(-(T === Float32 ? 1.0f-4 : 1.0e-8) / 2)),
                       (T(0.1), T(-0.05)), (T(2), T(-1)))
            e = collect(rr(T, sigma, x, y)); a = collect(gaussian_beambeam_kick(sigma, sigma, x, y))
            println("  ", T, " (", x, ",", y, ") relerr=", maximum(abs.(a .- e) ./ abs.(e)),
                    "  bound 16eps = ", 16 * eps(T))
        end
    end
end
