using Octopus, Printf
include(joinpath(@__DIR__, "quadref.jl"))
const O = Octopus
setprecision(BigFloat, 200)

sigs(v, eta) = (sqrt(v * (1 + eta)), sqrt(v * (1 - eta)))

# Sanity: reference must reproduce the exact round-beam closed form.
println("--- reference self-check: round beam closed form ---")
let s = 1.3e-3
    for (px, py) in ((0.4, 0.9), (2.0, 1.0), (6.0, 0.001))
        x = px * s; y = py * s
        r2 = x * x + y * y
        Kx_exact = 2 * x * (1 - exp(-r2 / (2 * s * s))) / r2
        Ky_exact = 2 * y * (1 - exp(-r2 / (2 * s * s))) / r2
        R = be_reference(s, s, x, y)
        @printf("  (%.3f,%.3f)sig  relerr Kx=%.3e Ky=%.3e\n", px, py,
                abs(Float64(R[1]) - Kx_exact) / abs(Kx_exact),
                abs(Float64(R[2]) - Ky_exact) / abs(Ky_exact))
    end
end
# Sanity: the exact trace identity  dKx/dx + dKy/dy = -2*rho_normalized
# (from div K = -2 * 2pi * rho, rho = exp(...)/(2 pi sx sy))
println("--- reference self-check: divergence identity ---")
let sx = 2.0e-3, sy = 0.7e-3
    for (px, py) in ((0.4, 0.9), (2.0, 1.0), (5.0, 3.0))
        x = px * sx; y = py * sy
        R = be_reference(sx, sy, x, y)
        expt = exp(-0.5 * (x * x / sx^2 + y * y / sy^2))
        @printf("  div=%.16e  -2rho=%.16e  rel=%.3e\n", Float64(R[3] + R[4]),
                -2 * expt / (sx * sy), abs(Float64(R[3] + R[4]) + 2 * expt / (sx * sy)) /
                abs(2 * expt / (sx * sy)))
    end
end

println()
println("=== code vs independent quadrature, all branches ===")
const KBB = 1.0
const V = (1.0e-3)^2
INNER, OUTER = O._near_round_eta_bounds(1.0)

etas = [0.0, 1e-12, 1e-8, 1e-6, 1e-5, 1e-4, INNER * (1 - 1e-6), INNER,
        INNER * 1.0001, (INNER + OUTER) / 2, OUTER * (1 - 1e-6), OUTER,
        OUTER * 1.0001, 1e-3, 1e-2, 0.05, 0.2, 0.5, 0.8, 0.95, 0.999]
pts = [(1e-4, 1e-4), (1e-3, 1e-3), (0.005, 0.003), (0.02, 0.01),
       (0.3, 0.2), (1.0, 0.7), (2.0, 1.3), (4.0, 0.02), (0.02, 4.0),
       (6.0, 5.0)]
labels = ("Kx", "Ky", "H1", "H2", "L/D")

worst = zeros(5); worst_at = Vector{Any}(undef, 5)
for eta in etas, (px, py) in pts
    s1, s2 = sigs(V, eta)
    x = px * sqrt(V); y = py * sqrt(V)
    got = O._gaussian_beambeam_kick_response_principal(KBB, s1, s2, x, y)
    R = be_reference(s1, s2, x, y)
    ref = (Float64(R[1]), Float64(R[2]), -KBB * Float64(R[3]), -KBB * Float64(R[4]),
           Float64(R[5]))
    for i in 1:5
        sc = max(abs(ref[i]), eps())
        rel = abs(got[i] - ref[i]) / sc
        if rel > worst[i]
            worst[i] = rel; worst_at[i] = (eta, px, py, got[i], ref[i])
        end
    end
end
for i in 1:5
    (eta, px, py, g, r) = worst_at[i]
    @printf("%-4s worst rel err %.3e  at eta=%.6e (x,y)/sig=(%g,%g)\n     code=%.17e\n     ref =%.17e\n",
            labels[i], worst[i], eta, px, py, g, r)
end

println()
println("=== eta == 0 exactly: what does the code return for L/D? ===")
let eta = 0.0
    s1, s2 = sigs(V, eta)
    for (px, py) in ((0.3, 0.2), (1.0, 0.7), (2.0, 1.3))
        x = px * sqrt(V); y = py * sqrt(V)
        got = O._gaussian_beambeam_kick_response_principal(KBB, s1, s2, x, y)
        R = be_reference(s1, s2, x, y)
        @printf("  (x,y)/sig=(%.2f,%.2f)  code L/D = %.17e   true limit = %.17e\n",
                px, py, got[5], Float64(R[5]))
    end
end
