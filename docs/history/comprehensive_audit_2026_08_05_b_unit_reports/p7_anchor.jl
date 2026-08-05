# U10 probe 7:
#  7a. analytic add-back anchored to the validated soft-Gaussian _cp_covariance_kick
#      (with the kbb_eff scaling the region's own call sites apply)
#  7b. does the TRANSVERSE analytic kick depend on longitudinal_kick?  The region
#      calls gaussian_beambeam_kick when longitudinal_kick=false and
#      _gaussian_beambeam_kick_response when true (gaussian_pic.jl:728-736;
#      gaussian_pic_cuda.jl:823-826 vs 880-881). Same question on the device twins.
#  7c. coupled -> uncoupled continuity as b -> 0
#  7d. cost of the unconditional cross-plane moment sums on the CPU when
#      coupling_tol = Inf (they are computed and discarded)
using Octopus
const O = Octopus
using Printf

mom = (n=1000, mx=1.0e-4, mpx=2.0e-5, varx=(1.06e-4)^2, cxpx=3.0e-10, varpx=(2.0e-5)^2,
       my=-5.0e-5, mpy=-1.0e-5, vary=(9.5e-6)^2, cypy=-2.0e-12, varpy=(1.0e-5)^2,
       cxy=0.30 * 1.06e-4 * 9.5e-6, cxpy=1.0e-11, cypx=2.0e-11, cpxpy=1.0e-11)

println("############ 7a. uncoupled add-back vs _cp_covariance_kick ############")
let wpx = 0.0, wpy = 0.0, wpz = 0.0
    kbb_eff = 3.7e-9
    for s in (-2.0e-3, 0.0, 1.5e-3),
        (dx, dy) in ((1.3e-4, 2.0e-6), (-4.0e-5, -1.1e-5), (2.0e-4, 3.0e-5), (0.0, 0.0))
        b = O._gpic_boundary(mom, s)
        bex, bey, Hxx, Hyy = O._gaussian_beambeam_kick_response(kbb_eff, b.sigx, b.sigy, dx, dy)
        # the region applies kick_scale*half_ns*be = kbb_eff*be
        dpx = kbb_eff * bex; dpy = kbb_eff * bey
        covpz = O._gpic_cov_pz(Hxx, Hyy, b.rx, b.ry)
        umom = O.StrongTransverseMoments{Float64,true}(
            mom.varx, 0.0, mom.vary, mom.cxpx, 0.0, 0.0, mom.cypy, mom.varpx, 0.0, mom.varpy)
        _, px, _, py, _, pz, _ = O._cp_covariance_kick(
            umom, kbb_eff, -s, dx, dy, dx, 0.0, dy, 0.0, 0.0, 0.0)
        wpx = max(wpx, abs(dpx - px) / max(abs(px), 1e-300))
        wpy = max(wpy, abs(dpy - py) / max(abs(py), 1e-300))
        wpz = max(wpz, abs(covpz - pz) / max(abs(pz), 1e-300))
    end
    @printf("  max rel diff:  px %.3e   py %.3e   pz %.3e\n", wpx, wpy, wpz)
end

println()
println("############ 7b. transverse kick: response-form vs plain form ############")
let worst = 0.0, argworst = ()
    for sigx in (1.06e-4, 9.5e-6, 1.0e-5, 1.00001e-5), sigy in (9.5e-6, 1.0e-5, 1.06e-4)
        for dx in (0.0, 1.0e-7, 1.0e-6, 1.3e-5, 2.0e-4, -3.0e-4),
            dy in (0.0, 1.0e-8, 1.0e-6, 5.0e-6, 4.0e-5)
            a1, b1 = gaussian_beambeam_kick(sigx, sigy, dx, dy)
            a2, b2, _, _ = O._gaussian_beambeam_kick_response(1.0, sigx, sigy, dx, dy)
            sc = max(abs(a1), abs(b1), 1e-300)
            d = max(abs(a1 - a2), abs(b1 - b2)) / sc
            if d > worst
                worst = d; argworst = (sigx, sigy, dx, dy, a1, a2, b1, b2)
            end
        end
    end
    @printf("  max rel |plain - response| over 360 points = %.3e\n", worst)
    worst > 1e-12 && println("    worst at (sigx,sigy,x,y)=", argworst[1:4],
                             "  plain=(", argworst[5], ",", argworst[7],
                             ")  response=(", argworst[6], ",", argworst[8], ")")
end

println()
println("############ 7c. coupled -> uncoupled continuity as b -> 0 ############")
let
    kbb_eff = 3.7e-9
    for r in (1.0e-2, 1.0e-3, 1.0e-4, 1.0e-5)
        m = merge(mom, (cxy = r * sqrt(mom.varx * mom.vary),))
        b = O._gpic_boundary(m, 0.0)
        cm = O._gpic_coupled_moments(m)
        um = O.StrongTransverseMoments{Float64,true}(
            m.varx, 0.0, m.vary, m.cxpx, 0.0, 0.0, m.cypy, m.varpx, 0.0, m.varpy)
        dx, dy = 1.3e-4, 5.0e-6
        _, pxc, _, pyc, _, pzc, _ = O._cp_covariance_kick(cm, kbb_eff, 0.0, dx, dy, dx, 0.0, dy, 0.0, 0.0, 0.0)
        _, pxu, _, pyu, _, pzu, _ = O._cp_covariance_kick(um, kbb_eff, 0.0, dx, dy, dx, 0.0, dy, 0.0, 0.0, 0.0)
        @printf("  r=%.0e  |dpx|rel=%.3e  |dpy|rel=%.3e   lam=%.3e sigc/sigy=%.12f\n",
                r, abs(pxc - pxu) / abs(pxu), abs(pyc - pyu) / abs(pyu),
                b.lam, b.sigc / b.sigy)
    end
end

println()
println("############ 7d. cost of the always-on cross-plane moment sums ############")
let
    n = 2_000_000
    x = randn(n); px = randn(n) .* 1e-5; y = randn(n) .* 0.1; py = randn(n) .* 1e-5
    src = (x=x, px=px, y=y, py=py)
    O._gpic_source_moments(src)   # warm
    t = @elapsed for _ in 1:3; O._gpic_source_moments(src); end
    @printf("  _gpic_source_moments (14 accumulators, cross-plane always on): %.4f s / call at n=%d\n", t / 3, n)
    # the 10-accumulator subset the uncoupled path actually needs
    function moments10(s)
        T = eltype(s.x); nn = length(s.x)
        x0 = s.x[1]; px0 = s.px[1]; y0 = s.y[1]; py0 = s.py[1]
        a1 = zero(T); a2 = zero(T); a3 = zero(T); a4 = zero(T)
        a5 = zero(T); a6 = zero(T); a7 = zero(T); a8 = zero(T); a9 = zero(T); a10 = zero(T)
        @inbounds for i in 1:nn
            dx = s.x[i] - x0; dpx = s.px[i] - px0; dy = s.y[i] - y0; dpy = s.py[i] - py0
            a1 += dx; a2 += dpx; a3 += dy; a4 += dpy
            a5 += dx * dx; a6 += dpx * dpx; a7 += dy * dy; a8 += dpy * dpy
            a9 += dx * dpx; a10 += dy * dpy
        end
        return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    end
    moments10(src)
    t2 = @elapsed for _ in 1:3; moments10(src); end
    @printf("  10-accumulator equivalent (what coupling_tol=Inf needs):        %.4f s / call\n", t2 / 3)
    @printf("  overhead of the unused cross-plane sums: %.1f%%\n", 100 * (t / t2 - 1))
end
