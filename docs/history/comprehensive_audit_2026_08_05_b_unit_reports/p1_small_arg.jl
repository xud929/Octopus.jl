using Octopus
const O = Octopus

setprecision(BigFloat, 400)

relerr(got, exact) = exact == 0 ? (got == 0 ? 0.0 : Inf) : Float64(abs(BigFloat(got) - exact) / abs(exact))

println("="^100)
println("P1  small-argument accuracy of the removable-singularity helpers, vs BigFloat(400 bits)")
println("="^100)

# ---------------------------------------------------------------------------
# The briefed grid: h = 1e-1, 1e-4, 1e-8, 1e-12, 0  (L = 1 / x = 1)
# ---------------------------------------------------------------------------
hs = [1e-1, 1e-4, 1e-8, 1e-12, 0.0]

println("\n--- _curv_sin(h, L) = sin(hL)/h,  L = 1.0 ---")
println(rpad("h",12), rpad("branch",9), rpad("value",26), rpad("exact",26), "relerr")
for h in hs
    L = 1.0
    got = O._curv_sin(h, L)
    u = BigFloat(h) * BigFloat(L)
    exact = h == 0 ? BigFloat(L) : sin(u) / BigFloat(h)
    br = abs(h * L) < 1e-4 ? "series" : "closed"
    println(rpad(h,12), rpad(br,9), rpad(got,26), rpad(Float64(exact),26), relerr(got, exact))
end

println("\n--- _curv_vers(h, L) = (1-cos(hL))/h,  L = 1.0 ---")
println(rpad("h",12), rpad("branch",9), rpad("value",26), rpad("exact",26), "relerr")
for h in hs
    L = 1.0
    got = O._curv_vers(h, L)
    u = BigFloat(h) * BigFloat(L)
    exact = h == 0 ? BigFloat(0) : (1 - cos(u)) / BigFloat(h)
    br = abs(h * L) < 0.125 ? "series" : "closed"
    println(rpad(h,12), rpad(br,9), rpad(got,26), rpad(Float64(exact),26), relerr(got, exact))
end

println("\n--- _atan_over(u) = atan(u)/u ---")
println(rpad("u",12), rpad("branch",9), rpad("value",26), rpad("exact",26), "relerr")
for u in hs
    got = O._atan_over(u)
    exact = u == 0 ? BigFloat(1) : atan(BigFloat(u)) / BigFloat(u)
    br = abs(u) < 1e-4 ? "series" : "closed"
    println(rpad(u,12), rpad(br,9), rpad(got,26), rpad(Float64(exact),26), relerr(got, exact))
end

println("\n--- _sol_log_over_h(h, x) = log(1+hx)/h,  x = 1.0 ---")
println(rpad("h",12), rpad("branch",9), rpad("value",26), rpad("exact",26), "relerr")
for h in hs
    x = 1.0
    got = O._sol_log_over_h(h, x)
    exact = h == 0 ? BigFloat(x) : log(1 + BigFloat(h) * BigFloat(x)) / BigFloat(h)
    br = abs(h * x) < 1e-2 ? "series" : "closed"
    println(rpad(h,12), rpad(br,9), rpad(got,26), rpad(Float64(exact),26), relerr(got, exact))
end

println("\n--- _sol_g(h,x) = 2 log(1+hx)/h - x  and  _sol_gp(h,x) = 2/(1+hx) - 1, x = 1.0 ---")
println(rpad("h",12), rpad("g relerr",26), "gp relerr")
for h in hs
    x = 1.0
    g = O._sol_g(h, x); gp = O._sol_gp(h, x)
    ge = h == 0 ? BigFloat(x) : 2 * log(1 + BigFloat(h) * BigFloat(x)) / BigFloat(h) - BigFloat(x)
    gpe = 2 / (1 + BigFloat(h) * BigFloat(x)) - 1
    println(rpad(h,12), rpad(relerr(g, ge),26), relerr(gp, gpe))
end

# ---------------------------------------------------------------------------
# Seam scan: is the crossover a cliff?  Both sides across each guard.
# ---------------------------------------------------------------------------
println("\n" * "="^100)
println("Seam scan: worst relative error on each side of each crossover (L = x = 1)")
println("="^100)

function seam(name, f, exactf, cutoff; n=400, lo_frac=1e-3, hi_mult=8.0)
    # below the cutoff (series branch)
    below = [cutoff * t for t in range(lo_frac, prevfloat(1.0); length=n)]
    above = [cutoff * t for t in range(1.0, hi_mult; length=n)]
    eb = maximum(relerr(f(u), exactf(BigFloat(u))) for u in below)
    ea = maximum(relerr(f(u), exactf(BigFloat(u))) for u in above)
    # one-ulp jump across the seam
    ulo = prevfloat(cutoff); uhi = cutoff
    jump = abs(f(uhi) - f(ulo)) / max(abs(f(uhi)), eps())
    println(rpad(name, 22), " cutoff=", rpad(cutoff, 10),
            " series-side max relerr=", rpad(eb, 12),
            " closed-side max relerr=", rpad(ea, 12),
            " seam jump(rel)=", jump)
end

seam("_curv_sin", u -> O._curv_sin(u, 1.0), u -> sin(u) / u, 1e-4)
seam("_curv_vers", u -> O._curv_vers(u, 1.0), u -> (1 - cos(u)) / u, 0.125; hi_mult=4.0)
seam("_atan_over", u -> O._atan_over(u), u -> atan(u) / u, 1e-4)
seam("_sol_log_over_h", u -> O._sol_log_over_h(u, 1.0), u -> log(1 + u) / u, 1e-2)

# ---------------------------------------------------------------------------
# The recorded U10-5 / U10-6 defects: are they actually closed?
# ---------------------------------------------------------------------------
println("\n" * "="^100)
println("Recorded-defect regression points (U10-5 _curv_vers, U10-6 _sol_log_over_h)")
println("="^100)
for u in (0.999e-4, 1.001e-4, prevfloat(0.125), 0.125, nextfloat(0.125), 0.5, 1.0)
    got = O._curv_vers(u, 1.0)
    ex = (1 - cos(BigFloat(u))) / BigFloat(u)
    println("_curv_vers  u=", rpad(u,24), " branch=", rpad(abs(u) < 0.125 ? "series" : "closed", 8),
            " relerr=", relerr(got, ex))
end
for u in (0.999e-4, 1.001e-4, prevfloat(1e-2), 1e-2, nextfloat(1e-2), 0.1)
    got = O._sol_log_over_h(u, 1.0)
    ex = log(1 + BigFloat(u)) / BigFloat(u)
    println("_sol_log    u=", rpad(u,24), " branch=", rpad(abs(u) < 1e-2 ? "series" : "closed", 8),
            " relerr=", relerr(got, ex))
end

# ---------------------------------------------------------------------------
# The full curved drift / bend as h -> 0: does the composite stay accurate?
# ---------------------------------------------------------------------------
println("\n" * "="^100)
println("Composite check: _lattice_drift(Val(true), h, L) vs BigFloat reference, and vs h=0")
println("="^100)
function drift_big(h, L, x, px, y, py, z, pz)
    h = BigFloat(h); L = BigFloat(L); x = BigFloat(x); px = BigFloat(px)
    y = BigFloat(y); py = BigFloat(py); z = BigFloat(z); pz = BigFloat(pz)
    ps0 = sqrt((1 + pz)^2 - px^2 - py^2)
    c, s = cos(h * L), sin(h * L)
    C1 = h == 0 ? L : sin(h * L) / h
    C2 = h == 0 ? BigFloat(0) : (1 - cos(h * L)) / h
    pxn = px * c + ps0 * s
    psn = -px * s + ps0 * c
    xn = (ps0 * C2 + px * C1 + x * ps0) / psn
    Delta = (-px * C2 + ps0 * C1 + xn * pxn - x * px) / ((1 + pz)^2 - py^2)
    return xn, pxn, y + py * Delta, py, z + L - (1 + pz) * Delta, pz
end
u0 = (1e-3, 2e-4, -5e-4, 3e-4, 1e-3, 1e-3)
for h in (1e-1, 1e-4, 1e-8, 1e-12, 0.0)
    got = O._lattice_drift(Val(true), h, 1.0, u0...)
    ex = drift_big(h, 1.0, u0...)
    err = maximum(i -> relerr(got[i], ex[i] == 0 ? BigFloat(1) : ex[i]) * (ex[i] == 0 ? abs(BigFloat(got[i])) : 1), 1:6)
    errs = [Float64(abs(BigFloat(got[i]) - ex[i])) for i in 1:6]
    println("h=", rpad(h,10), " max abs err over 6 coords = ", maximum(errs))
end
