#=
Probe: does validation/pic_gaussian_luminosity_validation.jl's local
`deposited_overlap` still match production `_pic_luminosity!` after the U5-8
"sum the FULL (nx+1)x(ny+1) extent" fix?

The script sums q1[1:nx,1:ny]; production sums 1:(nx+1),1:(ny+1).
Report the fractional contribution of the excluded last row/column.
=#
include(joinpath(@__DIR__, "repo", "src", "Octopus.jl"))
using .Octopus
using SpecialFunctions
const O = Octopus

function radical_inverse(index, base)
    value = 0.0; factor = inv(Float64(base))
    while index > 0
        index, digit = divrem(index, base)
        value += digit * factor; factor /= base
    end
    return value
end
function gaussian_halton_particles(mx, my, sx, sy, n; start=1)
    x = Vector{Float64}(undef, n); y = similar(x)
    for k in 1:n
        idx = start + k - 1
        ux = clamp(radical_inverse(idx, 2), eps(), 1 - eps())
        uy = clamp(radical_inverse(idx, 3), eps(), 1 - eps())
        x[k] = mx + sx * sqrt(2.0) * erfinv(2ux - 1)
        y[k] = my + sy * sqrt(2.0) * erfinv(2uy - 1)
    end
    return x, y
end

# Exactly the script's deposited_overlap, but returning both sum extents.
function both_overlaps(method, grid, padding_cells, x1, y1, x2, y2)
    nx, ny = grid
    xmin = min(minimum(x1), minimum(x2)); xmax = max(maximum(x1), maximum(x2))
    ymin = min(minimum(y1), minimum(y2)); ymax = max(maximum(y1), maximum(y2))
    width0 = max(xmax - xmin, eps()); height0 = max(ymax - ymin, eps())
    tx = width0 / (nx - 1 - padding_cells); ty = height0 / (ny - 1 - padding_cells)
    width = width0 + padding_cells * tx; height = height0 + padding_cells * ty
    xmin -= 0.5 * padding_cells * tx; ymin -= 0.5 * padding_cells * ty
    hx = width / (nx - 1); hy = height / (ny - 1)
    q1 = zeros(Float64, nx + 1, ny + 1); q2 = zeros(Float64, nx + 1, ny + 1)
    O._pic_deposit!(q1, method, x1, y1, xmin, ymin, hx, hy, nx + 1, ny + 1)
    O._pic_deposit!(q2, method, x2, y2, xmin, ymin, hx, hy, nx + 1, ny + 1)
    denom = length(x1) * length(x2) * hx * hy
    trunc_sum = sum(@view(q1[1:nx, 1:ny]) .* @view(q2[1:nx, 1:ny]))
    full_sum = sum(q1 .* q2)
    edge_q1 = sum(@view q1[nx+1, :]) + sum(@view q1[:, ny+1]) - q1[nx+1, ny+1]
    return trunc_sum / denom, full_sum / denom, edge_q1 / sum(q1)
end

cases = [
    (name=:centered_round, mx1=0.0, my1=0.0, sx1=95e-6, sy1=95e-6, mx2=0.0, my2=0.0, sx2=95e-6, sy2=95e-6),
    (name=:offset_round, mx1=-35e-6, my1=12e-6, sx1=95e-6, sy1=95e-6, mx2=42e-6, my2=-8e-6, sx2=95e-6, sy2=95e-6),
    (name=:unequal_round, mx1=0.0, my1=0.0, sx1=55e-6, sy1=55e-6, mx2=0.0, my2=0.0, sx2=130e-6, sy2=130e-6),
    (name=:centered_flat, mx1=0.0, my1=0.0, sx1=110e-6, sy1=9e-6, mx2=0.0, my2=0.0, sx2=85e-6, sy2=14e-6),
    (name=:offset_flat, mx1=-30e-6, my1=2e-6, sx1=110e-6, sy1=9e-6, mx2=25e-6, my2=-3e-6, sx2=85e-6, sy2=14e-6),
]

n = parse(Int, get(ENV, "NP", "20000"))
println("n_particles = ", n)
println("case                 method grid   trunc/full-1        edge_charge_frac")
worst = 0.0
for case in cases
    x1, y1 = gaussian_halton_particles(case.mx1, case.my1, case.sx1, case.sy1, n; start=1)
    x2, y2 = gaussian_halton_particles(case.mx2, case.my2, case.sx2, case.sy2, n; start=n + 101)
    for method in (:CIC, :TSC), g in (32, 128)
        t, f, ef = both_overlaps(method, (g, g), 0.1, x1, y1, x2, y2)
        d = abs(t - f) / max(abs(f), eps())
        global worst = max(worst, d)
        println(rpad(String(case.name), 20), " ", rpad(String(method), 6), " ",
                rpad(g, 6), " ", d, "   ", ef)
    end
end
println("worst truncated-vs-full relative difference = ", worst)
println("script gate tolerance = 1e-12")
