using Octopus, LinearAlgebra

beta = [k / sqrt(4k^2 - 1) for k in 1:95]
q = eigen(SymTridiagonal(zeros(96), beta))
nodes = (q.values .+ 1) ./ 2
weights = q.vectors[1, :] .^ 2

function transition_reference(sig1, sig2, x, y)
    v = (Float64(sig1)^2 + Float64(sig2)^2) / 2
    eta = (Float64(sig1)^2 - Float64(sig2)^2) / (2v)
    xb, yb = Float64(x), Float64(y)
    X, Y = xb / sqrt(v), yb / sqrt(v)
    ix = iy = jx = jy = 0.0
    for (z, w) in zip(nodes, weights)
        density = exp(-z / 2 * (X^2 / (1 + eta * z) + Y^2 / (1 - eta * z)))
        fx = density / ((1 + eta * z)^1.5 * (1 - eta * z)^0.5)
        fy = density / ((1 + eta * z)^0.5 * (1 - eta * z)^1.5)
        ix += w * fx; iy += w * fy
        jx += w * z / (1 + eta * z) * fx; jy += w * z / (1 - eta * z) * fy
    end
    return (xb / v * ix, yb / v * iy, -(ix / v - xb^2 / v^2 * jx), -(iy / v - yb^2 / v^2 * jy))
end

println("### moment recursion agreement (test line 515, bound 1e-12 / 5e-6)")
for T in (Float32, Float64)
    for qv in (prevfloat(T(2)), T(2), nextfloat(T(2)))
        a = Octopus._near_round_moments_0_6(qv)
        ref = setprecision(BigFloat, 256) do
            qb = BigFloat(qv); eq = exp(-qb); m = -expm1(-qb) / qb
            vals = BigFloat[m]
            for o in 1:6; m = (o * m - eq) / qb; push!(vals, m); end
            vals
        end
        rel = maximum(abs.(collect(Float64, a) .- Float64.(ref)) ./ abs.(Float64.(ref)))
        println("  ", T, " q=", qv, "  max rel err = ", rel,
                "  bound ", T === Float32 ? 5.0e-6 : 1.0e-12)
    end
end

println("\n### force/response error vs the Gauss-Legendre reference (test 542/543)")
for T in (Float32, Float64)
    inner, outer = Octopus._near_round_eta_bounds(zero(T))
    bound = T === Float32 ? 3.0e-5 : 5.0e-11
    wf = 0.0; wr = 0.0
    for eta in (zero(T), inner, T(0.75) * outer, outer, T(1.2) * outer)
        s1, s2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
        for (x, y) in ((T(1.0e-6), T(-5.0e-7)), (T(0.2), T(-0.1)), (T(1.3), T(0.7)),
                       (sqrt(T(0.0625)) * cos(T(pi / 16)), sqrt(T(0.0625)) * sin(T(pi / 16))),
                       (sqrt(T(5)) * cos(T(15pi / 32)), sqrt(T(5)) * sin(T(15pi / 32))))
            a = Octopus._gaussian_beambeam_kick_response(one(T), s1, s2, x, y)
            r = transition_reference(s1, s2, x, y)
            fe = hypot(Float64(a[1]) - r[1], Float64(a[2]) - r[2]) / hypot(r[1], r[2])
            re = hypot(Float64(a[3]) - r[3], Float64(a[4]) - r[4]) / hypot(r[3], r[4])
            wf = max(wf, fe); wr = max(wr, re)
        end
    end
    println("  ", T, " worst force err = ", wf, "  worst response err = ", wr, "  bound ", bound,
            "  headroom x", bound / max(wf, wr))
end

println("\n### core gradient Kx/x vs 2/(s1(s1+s2)) (test 556, rtol 32eps)")
for T in (Float32, Float64)
    _, outer = Octopus._near_round_eta_bounds(zero(T))
    cc = T === Float32 ? T(1.0e-4) : T(1.0e-8)
    w = 0.0
    for eta in (outer, T(0.001), T(0.1), T(0.9))
        s1, s2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
        Kx, _ = gaussian_beambeam_kick(s1, s2, cc, zero(T))
        gx = T(2) / (s1 * (s1 + s2))
        w = max(w, abs(Float64(Kx / cc) - Float64(gx)) / Float64(gx))
    end
    println("  ", T, " worst rel err = ", w, "  bound 32eps = ", 32 * eps(T),
            "  headroom x", 32 * eps(T) / w)
end

println("\n### round-Gaussian Hessian vs BigFloat (test 451, rtol/atol 32eps)")
for T in (Float32, Float64)
    sigma = one(T); na = T === Float32 ? 1.0f-4 : 1.0e-8
    for (x, y) in ((T(na), T(-na / 2)), (T(0.1), T(-0.05)), (T(0.2), T(-0.1)), (T(2), T(-1)))
        expterm = exp(-(x * x + y * y) / (2 * sigma * sigma))
        act = collect(Octopus._round_gaussian_hessian(one(T), sigma, x, y, expterm))
        ref = setprecision(BigFloat, 256) do
            kb, sb = BigFloat(1), BigFloat(sigma); xb, yb = BigFloat(x), BigFloat(y)
            r2 = xb * xb + yb * yb; u = r2 / (2 * sb * sb)
            if iszero(u)
                h = -kb / (sb * sb); return [Float64(h), 0.0, Float64(h)]
            end
            phi = -expm1(-u) / u
            dphi = ((one(u) + u) * exp(-u) - one(u)) / (u * u)
            inv2 = inv(sb * sb); f = phi * inv2; fp = dphi * inv2 * inv2 / 2
            [Float64(-kb * (f + 2 * xb * xb * fp)), Float64(-kb * (2 * xb * yb * fp)),
             Float64(-kb * (f + 2 * yb * yb * fp))]
        end
        println("  ", T, " (", x, ",", y, ") abs err = ", maximum(abs.(Float64.(act) .- ref)),
                "   |H| ~ ", maximum(abs, ref), "   atol 32eps = ", 32 * eps(T))
    end
end
