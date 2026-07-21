"""
Validate CIC/TSC PIC luminosity quadrature against analytic Gaussian overlap.

The macroparticles are deterministic Halton points transformed through
Gaussian quantiles. The
reference for two normalized diagonal Gaussian densities is

    exp(-0.5 * (Δx²/(σx1²+σx2²) + Δy²/(σy1²+σy2²))) /
    (2π * sqrt((σx1²+σx2²) * (σy1²+σy2²)))

The deposited-grid sum is a convergent quadrature, not the exact continuous
overlap of finite-width CIC/TSC particle shapes. The sweep covers centered,
offset, unequal, round, and flat beams; both deposition methods; several grid
resolutions and padding values; and configurable macroparticle resolution.

Run from the project root:

    julia --project=. validation/pic_gaussian_luminosity_validation.jl

The summary is written to `result/pic_gaussian_luminosity_validation.tsv`.
"""

include("../src/Octopus.jl")
using .Octopus
using SpecialFunctions

const O = Octopus

function radical_inverse(index, base)
    value = 0.0
    factor = inv(Float64(base))
    while index > 0
        index, digit = divrem(index, base)
        value += digit * factor
        factor /= base
    end
    return value
end

function gaussian_halton_particles(μx, μy, σx, σy, n; start=1)
    x = Vector{Float64}(undef, n)
    y = similar(x)
    for k in 1:n
        index = start + k - 1
        ux = clamp(radical_inverse(index, 2), eps(Float64), 1 - eps(Float64))
        uy = clamp(radical_inverse(index, 3), eps(Float64), 1 - eps(Float64))
        x[k] = μx + σx * sqrt(2.0) * erfinv(2ux - 1)
        y[k] = μy + σy * sqrt(2.0) * erfinv(2uy - 1)
    end
    return x, y
end

function analytic_gaussian_overlap(case)
    sx2 = case.σx1^2 + case.σx2^2
    sy2 = case.σy1^2 + case.σy2^2
    dx = case.μx1 - case.μx2
    dy = case.μy1 - case.μy2
    return exp(-0.5 * (dx^2 / sx2 + dy^2 / sy2)) / (2π * sqrt(sx2 * sy2))
end

function deposited_overlap(method, grid, padding_cells, x1, y1, x2, y2)
    nx, ny = grid
    xmin = min(minimum(x1), minimum(x2))
    xmax = max(maximum(x1), maximum(x2))
    ymin = min(minimum(y1), minimum(y2))
    ymax = max(maximum(y1), maximum(y2))
    width0 = max(xmax - xmin, eps(Float64))
    height0 = max(ymax - ymin, eps(Float64))
    tx = width0 / (nx - 1 - padding_cells)
    ty = height0 / (ny - 1 - padding_cells)
    width = width0 + padding_cells * tx
    height = height0 + padding_cells * ty
    xmin -= 0.5 * padding_cells * tx
    ymin -= 0.5 * padding_cells * ty
    hx = width / (nx - 1)
    hy = height / (ny - 1)
    q1 = zeros(Float64, nx + 1, ny + 1)
    q2 = zeros(Float64, nx + 1, ny + 1)
    O._pic_deposit!(q1, method, x1, y1, xmin, ymin, hx, hy, nx + 1, ny + 1)
    O._pic_deposit!(q2, method, x2, y2, xmin, ymin, hx, hy, nx + 1, ny + 1)
    return sum(@view(q1[1:nx, 1:ny]) .* @view(q2[1:nx, 1:ny])) /
           (length(x1) * length(x2) * hx * hy)
end

cases = [
    (name=:centered_round, μx1=0.0, μy1=0.0, σx1=95e-6, σy1=95e-6,
     μx2=0.0, μy2=0.0, σx2=95e-6, σy2=95e-6),
    (name=:offset_round, μx1=-35e-6, μy1=12e-6, σx1=95e-6, σy1=95e-6,
     μx2=42e-6, μy2=-8e-6, σx2=95e-6, σy2=95e-6),
    (name=:unequal_round, μx1=0.0, μy1=0.0, σx1=55e-6, σy1=55e-6,
     μx2=0.0, μy2=0.0, σx2=130e-6, σy2=130e-6),
    (name=:centered_flat, μx1=0.0, μy1=0.0, σx1=110e-6, σy1=9e-6,
     μx2=0.0, μy2=0.0, σx2=85e-6, σy2=14e-6),
    (name=:offset_flat, μx1=-30e-6, μy1=2e-6, σx1=110e-6, σy1=9e-6,
     μx2=25e-6, μy2=-3e-6, σx2=85e-6, σy2=14e-6),
]

n_particles_values = parse.(Int, split(
    get(ENV, "OCTOPUS_PIC_LUMINOSITY_VALIDATION_PARTICLES", "20000,100000,400000"), ','))
grids = parse.(Int, split(get(ENV, "OCTOPUS_PIC_LUMINOSITY_VALIDATION_GRIDS", "32,64,128,256"), ','))
paddings = parse.(Float64, split(get(ENV, "OCTOPUS_PIC_LUMINOSITY_VALIDATION_PADDING", "0.1,1.0,2.0"), ','))
rows = NamedTuple[]
interface_relative_errors = Float64[]
for n_particles in n_particles_values, case in cases
    x1, y1 = gaussian_halton_particles(
        case.μx1, case.μy1, case.σx1, case.σy1, n_particles; start=1,
    )
    x2, y2 = gaussian_halton_particles(
        case.μx2, case.μy2, case.σx2, case.σy2, n_particles;
        start=n_particles + 101,
    )
    exact = analytic_gaussian_overlap(case)
    for method in (:CIC, :TSC), ngrid in grids, padding in paddings
        value = deposited_overlap(method, (ngrid, ngrid), padding, x1, y1, x2, y2)
        if padding == 0.1
            solver = PICPoissonSolver(
                grid=(ngrid, ngrid), deposit_method=:CIC,
                luminosity_deposit_method=method,
            )
            public_value = O._pic_luminosity(
                solver, x1, y1, x2, y2, inv(Float64(length(x1) * length(x2))),
            )
            interface_relative_error = abs(public_value - value) / max(abs(value), eps(Float64))
            push!(interface_relative_errors, interface_relative_error)
        end
        push!(rows, (; case=case.name, method, grid=ngrid, padding_cells=padding,
                     n_particles, value, exact, relative_error=abs(value - exact) / exact))
    end
end

result_path = normpath(joinpath(@__DIR__, "..", "result", "pic_gaussian_luminosity_validation.tsv"))
mkpath(dirname(result_path))
open(result_path, "w") do io
    println(io, "case\tmethod\tgrid\tpadding_cells\tn_particles\tvalue\texact\trelative_error")
    for row in rows
        println(io, join(row, '\t'))
    end
end
println("PIC Gaussian luminosity validation")
println("  cases = ", length(cases))
println("  particles_per_beam = ", join(n_particles_values, ","))
println("  maximum_relative_error = ", maximum(row.relative_error for row in rows))
if isempty(interface_relative_errors)
    println("  maximum_production_interface_relative_error = not evaluated (padding 0.1 omitted)")
else
    maximum_interface_relative_error = maximum(interface_relative_errors)
    println("  maximum_production_interface_relative_error = ", maximum_interface_relative_error)
    maximum_interface_relative_error <= 1e-12 ||
        error("production luminosity path does not match the validation quadrature")
end
for method in (:CIC, :TSC)
    selected = filter(row -> row.method == method && row.grid == maximum(grids) &&
                             row.padding_cells == first(paddings) &&
                             row.n_particles == maximum(n_particles_values), rows)
    println("  ", method, " finest-grid maximum relative error = ",
            maximum(row.relative_error for row in selected))
end
println("  summary = ", result_path)
