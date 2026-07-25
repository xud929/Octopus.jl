#=
Fairness test for GaussianPICPoissonSolver on a NON-Gaussian source.

A single-Gaussian source is a biased benchmark for the Gaussian-subtracted PIC
solver, because the hybrid subtracts exactly that Gaussian and the residual is
then only discretization noise. This script uses a bi-Gaussian source (a
dominant Gaussian G1 plus an offset perturbation Gaussian G2), which has an EXACT
analytic field by superposition,

    K_exact = f1 * BE(sig1, r - mu1) + f2 * BE(sig2, r - mu2),   f_i = N_i / N,

while the hybrid can only subtract a SINGLE Gaussian fitted to the combined
empirical moments -- so the perturbation genuinely lands in the grid residual,
exactly as a real non-Gaussian beam would.

Reference model: superposition of two `gaussian_beambeam_kick` (Bassetti-Erskine)
fields. Error metric: per-point transverse-kick error normalized by the maximum
exact kick norm over a +-4 sigma grid; medians and maxima reported. Deterministic
Gaussian quantile lattices (no shot noise) isolate the systematic field error.

Findings (see docs/theory/gaussian_subtracted_pic_solver.md): the hybrid is never worse
than plain PIC and beats it by ~2-3x for near-Gaussian sources (the beam-beam
regime), degrading gracefully toward parity as the perturbation grows. The
weakest gain is for a diagonally offset perturbation, which introduces x-y
coupling the uncoupled subtraction cannot remove -- motivating the coupled
(rotated) subtraction branch gated by `coupling_tol`.

Outputs (under result/):
- gaussian_pic_bigaussian_validation_summary.tsv

Run from the project root:

    julia --project=. validation/gaussian_pic_bigaussian_validation.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
const O = Octopus
using SpecialFunctions: erf, erfinv
using FFTW, Statistics, Printf, DelimitedFiles, Random

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

gval(x, mu, s) = exp(-(x - mu)^2 / (2s^2)) / (s * sqrt(2pi))
m0(A, B, mu, s) = 0.5 * (erf((B - mu) / (s * sqrt(2))) - erf((A - mu) / (s * sqrt(2))))
m1(A, B, mu, s, xi) = (mu - xi) * m0(A, B, mu, s) - s^2 * (gval(B, mu, s) - gval(A, mu, s))
cic_profile(nodes, h, mu, s) =
    [m0(xi - h, xi + h, mu, s) + (m1(xi - h, xi, mu, s, xi) - m1(xi, xi + h, mu, s, xi)) / h
     for xi in nodes]

function quantile_grid(sigx, sigy, n; mux=0.0, muy=0.0)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Float64[]; y = Float64[]
    for yy in q, xx in q
        push!(x, mux + sigx * xx); push!(y, muy + sigy * yy)
    end
    return x, y
end

function solve_from_charge(solver, charge, sg, fg, nx, ny)
    gfft = O._pic_green_fft(solver, Float64, sg, fg)
    sp = Complex{Float64}.(charge); fft!(sp); sp .*= gfft; ifft!(sp)
    phi = real.(sp[1:nx, 1:ny])
    Ex, Ey = O._pic_field(phi, sg.width / (nx - 1), sg.height / (ny - 1))
    return phi, Ex, Ey
end

function run_case(; sigx, sigy, grid, f2, offx, offy, sig2_scale,
                  draw::Symbol=:quantile, seed::Int=1,
                  n1axis=400, field_axis=81, extent=4.0, margin=5.0)
    solver = PICPoissonSolver(; grid=(grid, grid), deposit_method=:CIC, green_type=:integrated)
    nx = ny = grid
    n2axis = f2 <= 0 ? 0 : max(round(Int, n1axis * sqrt(f2 / (1 - f2))), 5)
    s2x = sig2_scale * sigx; s2y = sig2_scale * sigy
    if draw === :quantile
        # deterministic Gaussian quantile lattice -> no shot noise (systematic error)
        x1, y1 = quantile_grid(sigx, sigy, n1axis)
        x2, y2 = n2axis > 0 ? quantile_grid(s2x, s2y, n2axis; mux=offx * sigx, muy=offy * sigy) :
                              (Float64[], Float64[])
    else
        # random Monte-Carlo draw at the SAME counts (adds Poisson shot noise)
        rng = MersenneTwister(seed)
        N1 = n1axis^2; N2 = n2axis > 0 ? n2axis^2 : 0
        x1 = sigx .* randn(rng, N1); y1 = sigy .* randn(rng, N1)
        if N2 > 0
            x2 = offx * sigx .+ s2x .* randn(rng, N2)
            y2 = offy * sigy .+ s2y .* randn(rng, N2)
        else
            x2 = Float64[]; y2 = Float64[]
        end
    end
    sx = vcat(x1, x2); sy = vcat(y1, y2)
    ns = length(sx); fr1 = length(x1) / ns; fr2 = length(x2) / ns
    mux = mean(sx); muy = mean(sy)
    sigxe = sqrt(mean((sx .- mux) .^ 2)); sigye = sqrt(mean((sy .- muy) .^ 2))

    xg = collect(range(-extent * sigx, extent * sigx; length=field_axis))
    yg = collect(range(-extent * sigy, extent * sigy; length=field_axis))
    sxmin = min(minimum(sx), mux - margin * sigxe); sxmax = max(maximum(sx), mux + margin * sigxe)
    symin = min(minimum(sy), muy - margin * sigye); symax = max(maximum(sy), muy + margin * sigye)
    sg, fg = O._pic_interaction_grids(solver, sxmin, sxmax, symin, symax,
        min(minimum(xg), sxmin), max(maximum(xg), sxmax),
        min(minimum(yg), symin), max(maximum(yg), symax))
    hx = sg.width / (nx - 1); hy = sg.height / (ny - 1)

    Qpart = zeros(2nx, 2ny)
    O._pic_deposit!(Qpart, :CIC, sx, sy, sg.x0, sg.y0, hx, hy, nx, ny)
    phiP, ExP, EyP = solve_from_charge(solver, Qpart, sg, fg, nx, ny)

    xn = [sg.x0 + (i - 1) * hx for i in 1:nx]; yn = [sg.y0 + (j - 1) * hy for j in 1:ny]
    gx = cic_profile(xn, hx, mux, sigxe); gy = cic_profile(yn, hy, muy, sigye)
    dQ = copy(Qpart)
    for j in 1:ny, i in 1:nx
        dQ[i, j] -= ns * gx[i] * gy[j]
    end
    phiD, ExD, EyD = solve_from_charge(solver, dQ, sg, fg, nx, ny)

    pic = Float64[]; hyb = Float64[]; en = Float64[]
    for y in yg, x in xg
        e1x, e1y = gaussian_beambeam_kick(sigx, sigy, x, y)
        e2x, e2y = fr2 > 0 ? gaussian_beambeam_kick(s2x, s2y, x - offx * sigx, y - offy * sigy) : (0.0, 0.0)
        ekx = fr1 * e1x + fr2 * e2x; eky = fr1 * e1y + fr2 * e2y
        peX, peY, _ = O._pic_interpolate_kick(solver, fg, x, y, phiP, ExP, EyP, phiP, ExP, EyP, 1.0, 0.0)
        deX, deY, _ = O._pic_interpolate_kick(solver, fg, x, y, phiD, ExD, EyD, phiD, ExD, EyD, 1.0, 0.0)
        pkx = 2peX / ns; pky = 2peY / ns
        bx, by = gaussian_beambeam_kick(sigxe, sigye, x - mux, y - muy)
        hkx = 2 * (deX + (ns / 2) * bx) / ns; hky = 2 * (deY + (ns / 2) * by) / ns
        push!(pic, hypot(pkx - ekx, pky - eky)); push!(hyb, hypot(hkx - ekx, hky - eky))
        push!(en, hypot(ekx, eky))
    end
    gn = maximum(en)
    return (fr2=fr2, ns=ns, pic_med=median(pic) / gn, pic_max=maximum(pic) / gn,
            hyb_med=median(hyb) / gn, hyb_max=maximum(hyb) / gn)
end

# (label, f2, offx[sig], offy[sig], sig2_scale)
cases = [
    ("pure_gaussian", 0.0, 0.0, 0.0, 1.0),
    ("pert_f0.2_off(1.5,0)", 0.2, 1.5, 0.0, 1.0),
    ("pert_f0.3_off(1.5,0)_narrow", 0.3, 1.5, 0.0, 0.5),
    ("pert_f0.1_off(3,0)", 0.1, 3.0, 0.0, 0.7),
    ("pert_f0.2_off(2,2)_coupled", 0.2, 2.0, 2.0, 1.0),
]
grid = parse(Int, get(ENV, "OCTOPUS_BIGAUSS_GRID", "128"))
nseeds = parse(Int, get(ENV, "OCTOPUS_BIGAUSS_SEEDS", "6"))

# Random-draw median/max error averaged over `nseeds` Monte-Carlo realizations.
function random_avg(; kwargs...)
    pm = Float64[]; px = Float64[]; hm = Float64[]; hx = Float64[]; nps = Int[]
    for s in 1:nseeds
        r = run_case(; draw=:random, seed=s, kwargs...)
        push!(pm, r.pic_med); push!(px, r.pic_max); push!(hm, r.hyb_med); push!(hx, r.hyb_max)
        push!(nps, r.ns)
    end
    return (pic_med=mean(pm), pic_max=mean(px), hyb_med=mean(hm), hyb_max=mean(hx), ns=nps[1])
end

rows = Any[]
for (label, f2, ox, oy, sc) in cases
    q = run_case(sigx=2e-3, sigy=2e-3, grid=grid, f2=f2, offx=ox, offy=oy, sig2_scale=sc,
                 draw=:quantile)
    r = random_avg(sigx=2e-3, sigy=2e-3, grid=grid, f2=f2, offx=ox, offy=oy, sig2_scale=sc)
    # Shot-noise contribution isolated in quadrature (random^2 - quantile^2).
    noise_pic = sqrt(max(r.pic_med^2 - q.pic_med^2, 0.0))
    noise_hyb = sqrt(max(r.hyb_med^2 - q.hyb_med^2, 0.0))
    push!(rows, (; label, ns=q.ns,
                 q_pic=q.pic_med, q_hyb=q.hyb_med, q_gain=q.pic_med / q.hyb_med,
                 r_pic=r.pic_med, r_hyb=r.hyb_med, r_gain=r.pic_med / r.hyb_med,
                 noise_pic, noise_hyb))
end

# ---- console + markdown summary ----
md = IOBuffer()
println(md, "# Gaussian-Subtracted PIC: quantile vs random-sampling accuracy\n")
println(md, "Bi-Gaussian source, grid $(grid)x$(grid), CIC, transverse-kick error vs the exact")
println(md, "2-Bassetti-Erskine field, normalized by max|K_exact| over a +-4 sigma grid; medians.\n")
println(md, "- **quantile** = deterministic Gaussian quantile lattice (no shot noise) -> **systematic** grid error.")
println(md, "- **random** = Monte-Carlo draw at the same particle count, averaged over $(nseeds) seeds -> systematic + **sampling** error.")
println(md, "- gain = PIC median / hybrid median. noise = sqrt(random^2 - quantile^2), the isolated shot-noise floor.\n")
println(md, "| case | N | quant PIC | quant HYB | quant gain | rand PIC | rand HYB | rand gain | noise PIC | noise HYB |")
println(md, "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for r in rows
    @printf(md, "| %s | %d | %.2e | %.2e | %.1f | %.2e | %.2e | %.1f | %.2e | %.2e |\n",
            r.label, r.ns, r.q_pic, r.q_hyb, r.q_gain, r.r_pic, r.r_hyb, r.r_gain,
            r.noise_pic, r.noise_hyb)
end
md_text = String(take!(md))
print(md_text)

md_path = joinpath(result_dir, "gaussian_pic_bigaussian_validation.md")
write(md_path, md_text)
println("\nmarkdown = ", md_path)
