# U10 probe 6 (hypothesis c): does the implementation match the derivation?
#  1. _gpic_gaussian_profile! vs high-accuracy Gauss-Legendre quadrature of G*W
#  2. coupled profiles (M0,M1,M2,g,g',g'') vs 2D quadrature of the tilted Gaussian
#  3. transport identity: sqrt(b.a) == b.sigx, sigc^2 == d - b^2/a
#  4. neutralization: measured residual monopole, CPU amp (qsum/sg) vs CUDA amp (N/sg)
#  5. coupled-branch box containment: leaked mass vs the docs Section 6 table
#  6. drift check: validation/gaussian_pic_field_validation.jl's own erf profile
#     reimplementation vs the shipped _gpic_gaussian_profile!
#  7. uncoupled analytic add-back anchored to the validated soft-Gaussian kick
using Octopus
const O = Octopus
using SpecialFunctions: erf, erfinv
using Printf

# --- 64-node Gauss-Legendre on [a,b], composite over ncell subintervals -------
const GLN = 40
function gauss_legendre(n)
    # Newton on Legendre polynomials
    x = zeros(n); w = zeros(n)
    for i in 1:n
        z = cos(pi * (i - 0.25) / (n + 0.5))
        for _ in 1:100
            p0 = 1.0; p1 = 0.0
            for j in 1:n
                p2 = p1; p1 = p0
                p0 = ((2j - 1) * z * p1 - (j - 1) * p2) / j
            end
            dp = n * (z * p0 - p1) / (z * z - 1)
            dz = p0 / dp
            z -= dz
            abs(dz) < 1e-16 && break
        end
        p0 = 1.0; p1 = 0.0
        for j in 1:n
            p2 = p1; p1 = p0
            p0 = ((2j - 1) * z * p1 - (j - 1) * p2) / j
        end
        dp = n * (z * p0 - p1) / (z * z - 1)
        x[i] = z; w[i] = 2 / ((1 - z * z) * dp * dp)
    end
    return x, w
end
const GX, GW = gauss_legendre(GLN)
function quad(f, a, b; ncell=8)
    s = 0.0
    h = (b - a) / ncell
    for c in 1:ncell
        lo = a + (c - 1) * h; hi = lo + h
        m = 0.5 * (lo + hi); r = 0.5 * (hi - lo)
        for k in 1:GLN
            s += GW[k] * f(m + r * GX[k])
        end
        s *= 1.0
    end
    return s * 0.5 * ((b - a) / ncell)
end

G1(x, mu, s) = exp(-(x - mu)^2 / (2s^2)) / (s * sqrt(2pi))
Wcic(u, h) = abs(u) >= h ? 0.0 : 1 - abs(u) / h
function Wtsc(u, h)
    a = abs(u) / h
    a <= 0.5 && return 0.75 - a * a
    a <= 1.5 && return 0.5 * (1.5 - a)^2
    return 0.0
end
Wof(m) = m === :CIC ? Wcic : Wtsc
Wsupport(m, h) = m === :CIC ? h : 1.5h

println("############ 1. erf node profile vs Gauss-Legendre quadrature ############")
for method in (:CIC, :TSC), (sig, h) in ((1.0, 0.5), (1.0, 2.0), (1.0, 0.1), (0.3, 1.0))
    n = 41
    x0 = -10.0 * sig
    mu = 0.37 * sig
    g = Vector{Float64}(undef, n)
    O._gpic_gaussian_profile!(g, x0, h, mu, sig, method)
    W = Wof(method)
    # integrate each support CELL separately: W has kinks at the cell edges, so a
    # composite rule that straddles one converges only algebraically.
    edges = method === :CIC ? (-h, 0.0, h) : (-1.5h, -0.5h, 0.5h, 1.5h)
    worst = 0.0; scale = maximum(abs, g)
    for i in 1:n
        xi = x0 + (i - 1) * h
        q = 0.0
        for c in 1:(length(edges) - 1)
            q += quad(x -> G1(x, mu, sig) * W(x - xi, h), xi + edges[c], xi + edges[c + 1]; ncell=4)
        end
        worst = max(worst, abs(g[i] - q))
    end
    @printf("  %s sig=%.2f h=%.2f  max|analytic-quad| = %.3e   (profile peak %.3e)\n",
            method, sig, h, worst, scale)
end
# sigma -> 0 discrete-weight limits (docs Section 5 check)
for method in (:CIC, :TSC)
    g = Vector{Float64}(undef, 5)
    O._gpic_gaussian_profile!(g, -2.0, 1.0, 0.0, 1.0e-9, method)
    @printf("  %s sigma->0 at a node: %s\n", method, string(round.(g; digits=12)))
end

println()
println("############ 2. coupled conditional expansion vs 2D quadrature ############")
function coupled_ref(xi, yj, hx, hy, mux, muy, sigx, sigy, rxy, method)
    # brute-force 2D integral of the tilted Gaussian against W(x)W(y)
    W = Wof(method)
    ex = method === :CIC ? (-hx, 0.0, hx) : (-1.5hx, -0.5hx, 0.5hx, 1.5hx)
    ey = method === :CIC ? (-hy, 0.0, hy) : (-1.5hy, -0.5hy, 0.5hy, 1.5hy)
    lam = rxy * sigy / sigx
    sc = sigy * sqrt(1 - rxy^2)
    f = x -> begin
        gx = G1(x, mux, sigx) * W(x - xi, hx)
        gx == 0 && return 0.0
        m = muy + lam * (x - mux)
        iy = 0.0
        for c in 1:(length(ey) - 1)
            iy += quad(y -> G1(y, m, sc) * W(y - yj, hy), yj + ey[c], yj + ey[c + 1]; ncell=4)
        end
        gx * iy
    end
    tot = 0.0
    for c in 1:(length(ex) - 1)
        tot += quad(f, xi + ex[c], xi + ex[c + 1]; ncell=4)
    end
    return tot
end
for method in (:CIC, :TSC), rxy in (0.05, 0.2, 0.5)
    nx = ny = 25
    sigx = 1.0; sigy = 1.0; hx = 0.5; hy = 0.5
    x0 = -6.0; y0 = -6.0; mux = 0.13; muy = -0.21
    lam = rxy * sigy / sigx
    sc = sigy * sqrt(1 - rxy^2)
    gx = Vector{Float64}(undef, nx); m1x = similar(gx); m2x = similar(gx)
    gy = Vector{Float64}(undef, ny); dgy = similar(gy); ddgy = similar(gy)
    O._gpic_coupled_profiles!(gx, m1x, m2x, gy, dgy, ddgy,
                              x0, hx, mux, sigx, y0, hy, muy, sc, method)
    worst = 0.0; peak = 0.0
    for i in 1:nx, j in 1:ny
        approx = gx[i] * gy[j] + lam * m1x[i] * dgy[j] + 0.5 * lam^2 * m2x[i] * ddgy[j]
        ref = coupled_ref(x0 + (i - 1) * hx, y0 + (j - 1) * hy, hx, hy,
                          mux, muy, sigx, sigy, rxy, method)
        peak = max(peak, abs(ref))
        worst = max(worst, abs(approx - ref))
    end
    @printf("  %s rxy=%.2f  max|coupled-quad| = %.3e   rel-to-peak = %.3e\n",
            method, rxy, worst, worst / peak)
end

println()
println("############ 3. transport identities ############")
mom = (n=1000, mx=1.0e-4, mpx=2.0e-5, varx=(1.06e-4)^2, cxpx=3.0e-10, varpx=(2.0e-5)^2,
       my=-5.0e-5, mpy=-1.0e-5, vary=(9.5e-6)^2, cypy=-2.0e-12, varpy=(1.0e-5)^2,
       cxy=0.30 * 1.06e-4 * 9.5e-6, cxpy=1.0e-11, cypx=2.0e-11, cpxpy=1.0e-11)
let worst_a = 0.0, worst_c = 0.0
for s in (-3.0e-3, -1.0e-4, 0.0, 2.7e-3, 5.0e-3)
    b = O._gpic_boundary(mom, s)
    worst_a = max(worst_a, abs(sqrt(b.a) - b.sigx) / b.sigx)
    ref = b.d - b.b^2 / b.a
    worst_c = max(worst_c, abs(b.sigc^2 - ref) / abs(ref))
end
@printf("  max rel |sqrt(a) - sigx| = %.3e ;  max rel |sigc^2 - (d - b^2/a)| = %.3e\n",
        worst_a, worst_c)
end

println()
println("############ 4. neutralization / residual monopole ############")
# real deposit of a quantile lattice through the shipped deposit helper
function residual_sum(; nx=64, ny=64, nax=200, sigx=1.06e-4, sigy=9.5e-6,
                       method=:TSC, margin=5.0)
    u = ((1:nax) .- 0.5) ./ nax
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    xs = Float64[]; ys = Float64[]
    for yy in q, xx in q; push!(xs, sigx * xx); push!(ys, sigy * yy); end
    n = length(xs)
    solver = PICPoissonSolver(grid=(nx, ny), deposit_method=method)
    sxmin = min(minimum(xs), -margin * sigx); sxmax = max(maximum(xs), margin * sigx)
    symin = min(minimum(ys), -margin * sigy); symax = max(maximum(ys), margin * sigy)
    sg, fg = O._pic_interaction_grids(solver, sxmin, sxmax, symin, symax,
                                      sxmin, sxmax, symin, symax)
    hx = sg.width / (nx - 1); hy = sg.height / (ny - 1)
    charge = zeros(2nx, 2ny)
    O._pic_deposit!(charge, method, xs, ys, sg.x0, sg.y0, hx, hy, nx, ny)
    qsum = sum(@view charge[1:nx, 1:ny])
    gx = Vector{Float64}(undef, nx); gy = Vector{Float64}(undef, ny)
    O._gpic_gaussian_profile!(gx, sg.x0, hx, 0.0, sigx, method)
    O._gpic_gaussian_profile!(gy, sg.y0, hy, 0.0, sigy, method)
    sgp = sum(gx) * sum(gy)
    amp_cpu = qsum / sgp          # CPU convention
    amp_cuda = n / sgp            # CUDA convention
    res_cpu = qsum - amp_cpu * sgp
    res_cuda = qsum - amp_cuda * sgp
    res_none = qsum - n * sgp
    return (n=n, qsum=qsum, sgp=sgp, res_cpu=res_cpu / n, res_cuda=res_cuda / n,
            res_none=res_none / n, qdrop=(qsum - n) / n)
end
for method in (:CIC, :TSC), margin in (5.0, 0.0)
    r = residual_sum(; method=method, margin=margin)
    @printf("  %s margin=%.1f  (qsum-N)/N=%.3e  sum(gx)sum(gy)=%.12f\n", method, margin, r.qdrop, r.sgp)
    @printf("      residual/N: CPU-amp %.3e   CUDA-amp %.3e   no-neutralize %.3e\n",
            r.res_cpu, r.res_cuda, r.res_none)
end

println()
println("############ 5. coupled-branch box containment vs docs Sec.6 margin table ############")
# For the tilted Gaussian the axis-aligned +-m*sigma_marginal box does NOT contain
# the +-m contour: the tilted extent needs m*sigma_y*(|r| + sqrt(1-r^2)).
for rxy in (0.0, 0.1, 0.3, 0.6), margin in (5.0,)
    nx = ny = 128
    sigx = 1.0; sigy = 1.0
    lam = rxy * sigy / sigx; sc = sigy * sqrt(1 - rxy^2)
    hx = 2 * margin * sigx / (nx - 1); hy = 2 * margin * sigy / (ny - 1)
    x0 = -margin * sigx; y0 = -margin * sigy
    gx = Vector{Float64}(undef, nx); m1x = similar(gx); m2x = similar(gx)
    gy = Vector{Float64}(undef, ny); dgy = similar(gy); ddgy = similar(gy)
    O._gpic_coupled_profiles!(gx, m1x, m2x, gy, dgy, ddgy,
                              x0, hx, 0.0, sigx, y0, hy, 0.0, sc, :TSC)
    sg = sum(gx) * sum(gy) + lam * sum(m1x) * sum(dgy) + 0.5 * lam^2 * sum(m2x) * sum(ddgy)
    predicted = 1 - 2 * (1 - erf(margin / sqrt(2))) / 2 * 2   # 2 axes, one-sided each
    @printf("  r=%.2f margin=%.1f  subtracted mass sg = %.9f  leak = %.3e  (axis-aligned table: %.3e)\n",
            rxy, margin, sg, 1 - sg, 2 * (1 - erf(margin / sqrt(2))))
end

println()
println("############ 6. validation-script profile reimplementation drift ############")
# validation/gaussian_pic_field_validation.jl carries its OWN copy of the erf
# profile rather than calling _gpic_gaussian_profile!. Check whether it drifted.
gval(x, mu, s) = exp(-(x - mu)^2 / (2s^2)) / (s * sqrt(2pi))
vm0(A, B, mu, s) = 0.5 * (erf((B - mu) / (s * sqrt(2))) - erf((A - mu) / (s * sqrt(2))))
function vm1(A, B, mu, s, xi)
    d = mu - xi
    return d * vm0(A, B, mu, s) - s^2 * (gval(B, mu, s) - gval(A, mu, s))
end
function vm2(A, B, mu, s, xi)
    d = mu - xi
    return (s^2 + d^2) * vm0(A, B, mu, s) -
           s^2 * ((B - mu) * gval(B, mu, s) - (A - mu) * gval(A, mu, s)) -
           2 * d * s^2 * (gval(B, mu, s) - gval(A, mu, s))
end
function vprofile(nodes, h, mu, s, method::Symbol)
    g = similar(nodes)
    for (k, xi) in pairs(nodes)
        if method === :CIC
            g[k] = vm0(xi - h, xi + h, mu, s) +
                   (vm1(xi - h, xi, mu, s, xi) - vm1(xi, xi + h, mu, s, xi)) / h
        else
            Lw = (xi - 1.5h, xi - 0.5h); C = (xi - 0.5h, xi + 0.5h); Rw = (xi + 0.5h, xi + 1.5h)
            g[k] = 0.75 * vm0(C..., mu, s) - vm2(C..., mu, s, xi) / h^2 +
                   1.125 * (vm0(Lw..., mu, s) + vm0(Rw..., mu, s)) +
                   1.5 * (vm1(Lw..., mu, s, xi) - vm1(Rw..., mu, s, xi)) / h +
                   0.5 * (vm2(Lw..., mu, s, xi) + vm2(Rw..., mu, s, xi)) / h^2
        end
    end
    return g
end
for method in (:CIC, :TSC)
    h = 0.31; n = 51; x0 = -7.0; mu = 0.19; s = 0.83
    nodes = [x0 + (i - 1) * h for i in 1:n]
    a = Vector{Float64}(undef, n)
    O._gpic_gaussian_profile!(a, x0, h, mu, s, method)
    b = vprofile(nodes, h, mu, s, method)
    @printf("  %s  max|shipped - validation-script copy| = %.3e\n", method, maximum(abs.(a .- b)))
end

println()
println("############ 7. analytic add-back anchored to _cp_covariance_kick ############")
# uncoupled hybrid terms vs the independently validated soft-Gaussian kick
kbb_eff = 3.7e-9
let worst_px = 0.0, worst_py = 0.0, worst_pz = 0.0
for s in (-2.0e-3, 0.0, 1.5e-3), (dx, dy) in ((1.3e-4, 2.0e-6), (-4.0e-5, -1.1e-5), (2.0e-4, 3.0e-5))
    b = O._gpic_boundary(mom, s)
    bex, bey, Hxx, Hyy = O._gaussian_beambeam_kick_response(kbb_eff, b.sigx, b.sigy, dx, dy)
    covpz = O._gpic_cov_pz(Hxx, Hyy, b.rx, b.ry)
    umom = O.StrongTransverseMoments{Float64,true}(
        mom.varx, 0.0, mom.vary, mom.cxpx, 0.0, 0.0, mom.cypy, mom.varpx, 0.0, mom.varpy)
    _, px, _, py, _, pz, _ = O._cp_covariance_kick(
        umom, kbb_eff, -s, dx, dy, dx, 0.0, dy, 0.0, 0.0, 0.0)
    worst_px = max(worst_px, abs(bex - px) / max(abs(px), eps()))
    worst_py = max(worst_py, abs(bey - py) / max(abs(py), eps()))
    worst_pz = max(worst_pz, abs(covpz - pz) / max(abs(pz), eps()))
end
@printf("  max rel diff vs _cp_covariance_kick:  px %.3e  py %.3e  pz %.3e\n",
        worst_px, worst_py, worst_pz)
end
