# U7-1 verdict probe: ForwardDiff through the elliptical Bassetti-Erskine kick.
using Octopus, ForwardDiff, Printf
const O = Octopus

println("ForwardDiff rule loaded? ",
        hasmethod(O._near_round_conditioning_factor,
                  Tuple{Type{ForwardDiff.Dual{Nothing,Float64,1}}}))
println("faddeeva_w dual method? ",
        hasmethod(O.faddeeva_w, Tuple{Complex{ForwardDiff.Dual{Nothing,Float64,1}}}))
println()

# --- 1. bare kick, derivative wrt x, elliptical -------------------------------
println("=== gaussian_beambeam_kick, d/dx at eta far from every seam ===")
for (sx, sy) in ((2e-3, 1e-3), (1e-3, 2e-3), (1e-3, 1e-3), (5e-3, 1e-4))
    x0, y0 = 1.3e-4, 0.9e-4
    ok = true
    dfd = try
        ForwardDiff.derivative(t -> O.gaussian_beambeam_kick(sx, sy, t, y0)[1], x0)
    catch err
        ok = false
        sprint(showerror, err)
    end
    if ok
        h = 1e-9
        fd = (O.gaussian_beambeam_kick(sx, sy, x0 + h, y0)[1] -
              O.gaussian_beambeam_kick(sx, sy, x0 - h, y0)[1]) / (2h)
        @printf("  sig=(%.1e,%.1e)  AD=%.16e  FD=%.16e  rel=%.3e\n",
                sx, sy, dfd, fd, abs(dfd - fd) / abs(fd))
    else
        @printf("  sig=(%.1e,%.1e)  THROWS: %s\n", sx, sy, first(dfd, 120))
    end
end

# --- 2. derivative wrt an ELEMENT PARAMETER (sigma) ---------------------------
println()
println("=== d(kick)/d(sigma_x) — parameter derivative ===")
for (sx, sy) in ((2e-3, 1e-3), (1.000001e-3, 1e-3), (1e-3, 1e-3))
    x0, y0 = 1.3e-4, 0.9e-4
    r = try
        ForwardDiff.derivative(s -> O.gaussian_beambeam_kick(s, sy, x0, y0)[1], sx)
    catch err
        sprint(showerror, err)
    end
    if r isa Float64
        h = sx * 1e-7
        fd = (O.gaussian_beambeam_kick(sx + h, sy, x0, y0)[1] -
              O.gaussian_beambeam_kick(sx - h, sy, x0, y0)[1]) / (2h)
        @printf("  sig=(%.7e,%.1e)  AD=%.12e FD=%.12e rel=%.3e\n", sx, sy, r, fd,
                abs(r - fd) / abs(fd))
    else
        @printf("  sig=(%.7e,%.1e)  THROWS: %s\n", sx, sy, first(r, 140))
    end
end

# --- 3. full element map jacobian through a Dual ------------------------------
println()
println("=== ForwardDiff.jacobian of the full ThinStrongBeam map ===")
function build(T, sx, sy; drift=:hirata)
    spec = ThinStrongBeamSpec{T}(kbb=T(1e-4), beta=(T(1), T(1)),
                                 sigma=(T(sx), T(sy)), center=(T(0), T(0), T(0)),
                                 virtual_drift=drift)
    return compile_runtime(spec)
end
for (sx, sy, name) in ((1e-3, 1e-3, "round"), (2e-3, 1e-3, "elliptical"),
                       (1.0002e-3, 1e-3, "near-round blend"),
                       (1.0000001e-3, 1e-3, "near-round series"))
    elem = build(Float64, sx, sy)
    f = u -> begin
        out = elem(u[1], u[2], u[3], u[4], u[5], u[6])
        [out...]
    end
    u0 = [1.1e-4, 2e-5, 0.7e-4, -1e-5, 3e-3, 1e-4]
    r = try
        ForwardDiff.jacobian(f, u0)
    catch err
        sprint(showerror, err)
    end
    if r isa Matrix
        # FD reference
        J = zeros(6, 6)
        for j in 1:6
            h = max(abs(u0[j]), 1e-6) * 1e-6
            up = copy(u0); up[j] += h
            um = copy(u0); um[j] -= h
            J[:, j] = (f(up) - f(um)) / (2h)
        end
        @printf("  %-18s max|AD-FD| = %.3e  (scale %.3e)\n", name,
                maximum(abs, r - J), maximum(abs, J))
    else
        @printf("  %-18s THROWS: %s\n", name, first(r, 160))
    end
end

# --- 4. parameter derivative through the whole element (kbb and sigma) --------
println()
println("=== d(px_out)/d(param) through the compiled element ===")
u0 = (1.1e-4, 2e-5, 0.7e-4, -1e-5, 3e-3, 1e-4)
for (pname, f) in (("kbb", k -> compile_runtime(ThinStrongBeamSpec{typeof(k)}(
                        kbb=k, beta=(one(k), one(k)),
                        sigma=(oftype(k, 2e-3), oftype(k, 1e-3))))(u0...)[2]),
                   ("sigma_x", s -> compile_runtime(ThinStrongBeamSpec{typeof(s)}(
                        kbb=oftype(s, 1e-4), beta=(one(s), one(s)),
                        sigma=(s, oftype(s, 1e-3))))(u0...)[2]))
    r = try
        ForwardDiff.derivative(f, pname == "kbb" ? 1e-4 : 2e-3)
    catch err
        sprint(showerror, err)
    end
    if r isa Float64
        p0 = pname == "kbb" ? 1e-4 : 2e-3
        h = p0 * 1e-6
        fd = (f(p0 + h) - f(p0 - h)) / (2h)
        @printf("  %-8s AD=%.12e FD=%.12e rel=%.3e\n", pname, r, fd, abs(r - fd) / abs(fd))
    else
        @printf("  %-8s THROWS: %s\n", pname, first(r, 200))
    end
end

# --- 5. GaussianStrongBeam (sliced) parameter derivative ---------------------
println()
println("=== d(px_out)/d(sigma_x) through GaussianStrongBeam, ns=5 ===")
gfun = s -> begin
    T = typeof(s)
    thin = ThinStrongBeamSpec{T}(kbb=T(1e-4), beta=(one(T), one(T)),
                                 sigma=(s, T(1e-3)))
    spec = GaussianStrongBeamSpec{T}(thin=thin, ns=5, sigz=T(0.01))
    compile_runtime(spec)(u0...)[2]
end
r = try
    ForwardDiff.derivative(gfun, 2e-3)
catch err
    sprint(showerror, err)
end
if r isa Float64
    h = 2e-3 * 1e-6
    fd = (gfun(2e-3 + h) - gfun(2e-3 - h)) / (2h)
    @printf("  AD=%.12e FD=%.12e rel=%.3e\n", r, fd, abs(r - fd) / abs(fd))
else
    @printf("  THROWS: %s\n", first(r, 300))
end

# --- 6. near-axis switch: is the *derivative* continuous across rho^7 seam? ---
println()
println("=== near-axis switch (rho^7 = eps/sqrt(eta)) — value and d/dx jump ===")
for eta in (1e-3, 1e-2, 0.1, 0.5, 0.9)
    v = (1e-3)^2
    s1 = sqrt(v * (1 + eta)); s2 = sqrt(v * (1 - eta))
    # solve rho^7 = eps/sqrt(eta) along y = 0.5*x*(s2/s1) so rho2 = x^2/s1^2*(1+0.25)
    target = (eps(Float64) / sqrt(eta))^(1 / 7)   # = rho at the seam
    fac = sqrt(1.25)
    xseam = target / fac * s1
    yseam = 0.5 * xseam * s2 / s1
    fs(t) = O._gaussian_beambeam_kick_response_principal(1.0, s1, s2, t, yseam)
    below = fs(xseam * (1 - 1e-10))
    above = fs(xseam * (1 + 1e-10))
    swb = O._use_elliptic_near_axis(s1, s2, xseam * (1 - 1e-10), yseam, eta)
    swa = O._use_elliptic_near_axis(s1, s2, xseam * (1 + 1e-10), yseam, eta)
    @printf("  eta=%.3g rho_seam=%.4e  branch(below/above)=(%s/%s)\n",
            eta, target, swb, swa)
    for (i, nm) in enumerate(("Kx", "Ky", "H1", "H2", "L/D"))
        sc = max(abs(below[i]), abs(above[i]), eps())
        @printf("      %-4s rel jump %.3e  (%.17e -> %.17e)\n", nm,
                abs(above[i] - below[i]) / sc, below[i], above[i])
    end
end
