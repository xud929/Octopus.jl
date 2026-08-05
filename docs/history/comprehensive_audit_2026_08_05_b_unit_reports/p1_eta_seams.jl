using Octopus
using Printf

const O = Octopus

# eta -> (sig1, sig2) at fixed v
sigs(v, eta) = (sqrt(v * (1 + eta)), sqrt(v * (1 - eta)))

# Evaluate the full response at a given eta with sig1,sig2 derived from v.
function resp(kbb, v, eta, x, y)
    s1, s2 = sigs(v, eta)
    return O._gaussian_beambeam_kick_response_principal(kbb, s1, s2, x, y)
end

# Which branch does eta land in?
function branch(eta)
    eta == 0 && return :round
    inner, outer = O._near_round_eta_bounds(eta)
    eta <= inner && return :series
    eta >= outer && return :elliptic
    return :blend
end

const KBB = 1.0
const V = (1.0e-3)^2          # v = sigma^2 scale, sigma ~ 1 mm
const INNER, OUTER = O._near_round_eta_bounds(1.0)

println("Float64 eta bounds: inner = ", INNER, "  outer = ", OUTER)
println("Float32 eta bounds: ", O._near_round_eta_bounds(1.0f0))
println()

# Field points, in units of sqrt(v).
pts = [(0.3, 0.2), (1.0, 0.7), (2.0, 1.3), (3.5, 0.05), (0.05, 3.5),
       (5.0, 4.0), (0.5, 0.0), (0.0, 0.5), (8.0, 6.0)]

labels = ("Kx", "Ky", "H1", "H2", "L/D")

function seam_report(name, eta_star)
    println("=" ^ 78)
    println("SEAM: ", name, "   eta* = ", eta_star)
    println("=" ^ 78)
    # Richardson-style: sample at eta* +/- h for a geometric ladder of h,
    # one-sided linear extrapolation to eta* from each side, and compare.
    hs = [eta_star * 2.0^(-k) for k in 6:14]
    worst = zeros(5)
    worst_at = Vector{Any}(undef, 5)
    for (px, py) in pts
        x = px * sqrt(V)
        y = py * sqrt(V)
        for i in 1:5
            # one-sided values
            below = Float64[]
            above = Float64[]
            for h in hs
                em = eta_star - h
                ep = eta_star + h
                push!(below, resp(KBB, V, em, x, y)[i])
                push!(above, resp(KBB, V, ep, x, y)[i])
            end
            # Richardson extrapolate h->0 using the two smallest h (linear in h)
            # f(eta*-h) ~ f- - h f'-, use last two entries
            fm = below[end] + (below[end] - below[end-1])          # h/2 -> 0
            fp = above[end] + (above[end] - above[end-1])
            scale = max(abs(fm), abs(fp), eps())
            rel = abs(fp - fm) / scale
            if rel > worst[i]
                worst[i] = rel
                worst_at[i] = (px, py, fm, fp, abs(fp - fm))
            end
        end
    end
    for i in 1:5
        (px, py, fm, fp, ab) = worst_at[i]
        @printf("  %-4s worst rel jump %10.3e  (abs %10.3e) at (x,y)/sig=(%.2f,%.2f)  below=%.16e above=%.16e\n",
                labels[i], worst[i], ab, px, py, fm, fp)
    end
    println()

    # derivative continuity: one-sided slope estimates near the seam
    println("  d/deta one-sided slopes (relative mismatch):")
    for i in 1:5
        worstd = 0.0
        wat = (0.0, 0.0, 0.0, 0.0)
        for (px, py) in pts
            x = px * sqrt(V); y = py * sqrt(V)
            h = eta_star * 2.0^-9
            f0m = resp(KBB, V, eta_star - h, x, y)[i]
            f1m = resp(KBB, V, eta_star - 2h, x, y)[i]
            f0p = resp(KBB, V, eta_star + h, x, y)[i]
            f1p = resp(KBB, V, eta_star + 2h, x, y)[i]
            dm = (f0m - f1m) / h     # slope just below
            dp = (f0p - f1p) / (-h)  # slope just above  ( (f(e+h)-f(e+2h))/(-h) )
            sc = max(abs(dm), abs(dp), eps())
            rel = abs(dp - dm) / sc
            if rel > worstd
                worstd = rel; wat = (px, py, dm, dp)
            end
        end
        @printf("  %-4s worst rel slope mismatch %10.3e at (%.2f,%.2f) below'=%.6e above'=%.6e\n",
                labels[i], worstd, wat[1], wat[2], wat[3], wat[4])
    end
    println()
end

seam_report("inner (series <-> blend)", INNER)
seam_report("outer (blend <-> elliptic)", OUTER)

# eta -> 0 seam: eta == 0 exact round vs eta = tiny series
println("=" ^ 78)
println("SEAM: eta == 0 (exact-round) vs eta -> 0+ (series)")
println("=" ^ 78)
for (px, py) in pts
    x = px * sqrt(V); y = py * sqrt(V)
    r0 = resp(KBB, V, 0.0, x, y)
    worst = 0.0
    for e in (1e-16, 1e-14, 1e-12, 1e-10, 1e-8)
        re = resp(KBB, V, e, x, y)
        for i in 1:5
            sc = max(abs(r0[i]), abs(re[i]), eps())
            worst = max(worst, abs(r0[i] - re[i]) / sc)
        end
    end
    @printf("  (x,y)/sig=(%.2f,%.2f) worst rel diff over eta in [1e-16,1e-8] = %.3e   (L/D at eta=0 is %g)\n",
            px, py, worst, r0[5])
end
