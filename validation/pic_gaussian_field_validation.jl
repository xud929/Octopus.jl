"""
Validate the PIC slice-field calculation against the Bassetti-Erskine
soft-Gaussian kick for several transverse beam sizes.

The source beam is represented by deterministic equal-probability Gaussian
macroparticles. For each `(sigma_x, sigma_y)` case, the field is evaluated on a
uniform transverse grid and compared with `gaussian_beambeam_kick`. Relative
error is normalized by the maximum exact kick norm on that case's grid:

```text
relative_error = |K_pic - K_exact| / max_grid(|K_exact|)
```

From the project root:

```bash
/cfs/ad/dxu/packages/julias/julia-1.12.4/bin/julia --project=. validation/pic_gaussian_field_validation.jl
```

Outputs are written under `result/`:

- `pic_gaussian_field_validation_summary.tsv`
- `pic_gaussian_field_validation_caseNN.tsv`
- `pic_gaussian_field_validation_caseNN.png`
"""

include("../src/Octopus.jl")
using .Octopus
using DelimitedFiles
using Printf
using Random
using Statistics
using SpecialFunctions

const O = Octopus

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

default_validation_cases = [
    (sigx=2.0e-3, sigy=2.0e-3),
    (sigx=2.0e-3, sigy=1.2e-3),
    (sigx=2.0e-3, sigy=0.8e-3),
    (sigx=2.0e-3, sigy=0.4e-3),
    (sigx=0.8e-3, sigy=2.0e-3),
]

nsource_axis = parse(Int, get(ENV, "OCTOPUS_PIC_VALIDATION_SOURCE_AXIS", "320"))
field_axis = parse(Int, get(ENV, "OCTOPUS_PIC_VALIDATION_FIELD_AXIS", "161"))
pic_grid = parse(Int, get(ENV, "OCTOPUS_PIC_VALIDATION_PIC_GRID", "256"))
extent_sigma = parse(Float64, get(ENV, "OCTOPUS_PIC_VALIDATION_EXTENT_SIGMA", "4.0"))
random_cases = parse(Int, get(ENV, "OCTOPUS_PIC_VALIDATION_RANDOM_CASES", "0"))
random_seed = parse(Int, get(ENV, "OCTOPUS_PIC_VALIDATION_RANDOM_SEED", "20260712"))
random_sigma_min = parse(Float64, get(ENV, "OCTOPUS_PIC_VALIDATION_SIGMA_MIN", "2.0e-4"))
random_sigma_max = parse(Float64, get(ENV, "OCTOPUS_PIC_VALIDATION_SIGMA_MAX", "3.0e-3"))
write_case_data = parse(Bool, lowercase(get(ENV, "OCTOPUS_PIC_VALIDATION_WRITE_CASE_DATA", random_cases > 0 ? "false" : "true")))

function random_validation_cases(n, seed, sigma_min, sigma_max)
    sigma_min > 0 || throw(ArgumentError("sigma_min must be positive"))
    sigma_max > sigma_min || throw(ArgumentError("sigma_max must be larger than sigma_min"))
    rng = MersenneTwister(seed)
    logmin = log(sigma_min)
    logmax = log(sigma_max)
    return [
        (
            sigx=exp(logmin + rand(rng) * (logmax - logmin)),
            sigy=exp(logmin + rand(rng) * (logmax - logmin)),
        )
        for _ in 1:n
    ]
end

validation_cases = random_cases > 0 ?
    random_validation_cases(random_cases, random_seed, random_sigma_min, random_sigma_max) :
    default_validation_cases

solver = PICPoissonSolver(;
    grid=(pic_grid, pic_grid),
    deposit_method=:TSC,
    green_type=:integrated,
)

function gaussian_quantile_grid(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Vector{Float64}(undef, n * n)
    y = similar(x)
    k = 1
    for yy in q, xx in q
        x[k] = sigx * xx
        y[k] = sigy * yy
        k += 1
    end
    return x, y
end

function validate_pic_gaussian_case(case_id, sigx, sigy, solver, result_dir;
                                   nsource_axis, field_axis, extent_sigma, pic_grid,
                                   write_case_data::Bool)
    source_x, source_y = gaussian_quantile_grid(sigx, sigy, nsource_axis)
    nsource = length(source_x)
    xgrid = collect(range(-extent_sigma * sigx, extent_sigma * sigx; length=field_axis))
    ygrid = collect(range(-extent_sigma * sigy, extent_sigma * sigy; length=field_axis))

    source_grid, field_grid = O._pic_interaction_grids(
        solver,
        minimum(source_x), maximum(source_x), minimum(source_y), maximum(source_y),
        minimum(xgrid), maximum(xgrid), minimum(ygrid), maximum(ygrid),
    )
    phi, Ex, Ey = O._pic_solve_field(solver, source_x, source_y, source_grid, field_grid)

    rows = Matrix{Float64}(undef, field_axis * field_axis, 12)
    row = 1
    for y in ygrid, x in xgrid
        pic_ex, pic_ey, _ = O._pic_interpolate_kick(
            solver, field_grid, x, y,
            phi, Ex, Ey, phi, Ex, Ey,
            1.0, 0.0,
        )
        pic_kx = 2.0 * pic_ex / nsource
        pic_ky = 2.0 * pic_ey / nsource
        exact_kx, exact_ky = gaussian_beambeam_kick(sigx, sigy, x, y)
        abs_x = abs(pic_kx - exact_kx)
        abs_y = abs(pic_ky - exact_ky)
        exact_norm = hypot(exact_kx, exact_ky)
        err_norm = hypot(pic_kx - exact_kx, pic_ky - exact_ky)
        rows[row, :] .= (
            x, y, pic_kx, pic_ky, exact_kx, exact_ky,
            abs_x, abs_y, err_norm, 0.0, exact_norm, hypot(pic_kx, pic_ky),
        )
        row += 1
    end

    global_exact_norm = maximum(rows[:, 11])
    global_exact_norm > 0 || error("exact Gaussian kick is zero at all validation points")
    rows[:, 10] .= rows[:, 9] ./ global_exact_norm
    rel = rows[:, 10]

    stem = @sprintf("pic_gaussian_field_validation_case%02d", case_id)
    data_path = write_case_data ? joinpath(result_dir, stem * ".tsv") : ""
    image_path = write_case_data ? joinpath(result_dir, stem * ".png") : ""
    if write_case_data
        open(data_path, "w") do io
            println(io, "# case_id\t$case_id")
            println(io, "# sigx\t$sigx")
            println(io, "# sigy\t$sigy")
            println(io, "# sigma_ratio_x_over_y\t$(sigx / sigy)")
            println(io, "# nsource_axis\t$nsource_axis")
            println(io, "# nsource\t$nsource")
            println(io, "# field_axis\t$field_axis")
            println(io, "# pic_grid\t$pic_grid")
            println(io, "# extent_sigma\t$extent_sigma")
            println(io, "# relative_normalization\tmax_grid_exact_norm\t$global_exact_norm")
            println(io, "# columns\tx y pic_kx pic_ky exact_kx exact_ky abs_kx abs_ky abs_norm rel_to_max_exact_norm exact_norm pic_norm")
            writedlm(io, rows, '\t')
        end
    end

    return (
        case_id=case_id,
        sigx=sigx,
        sigy=sigy,
        sigma_ratio=sigx / sigy,
        nsource=nsource,
        field_axis=field_axis,
        pic_grid=pic_grid,
        global_exact_norm=global_exact_norm,
        min_relative=minimum(rel),
        median_relative=median(rel),
        mean_relative=mean(rel),
        p95_relative=quantile(rel, 0.95),
        max_relative=maximum(rel),
        data_path=data_path,
        image_path=image_path,
    )
end

plot_path = joinpath(result_dir, "pic_gaussian_field_validation_plot.py")
open(plot_path, "w") do io
    print(io, raw"""
from pathlib import Path
import math
import struct
import zlib

base = Path(__file__).resolve().parent
data_paths = sorted(base.glob("pic_gaussian_field_validation_case*.tsv"))

def read_case(path):
    rows = []
    metadata = {}
    for line in path.read_text().splitlines():
        if not line:
            continue
        if line.startswith("#"):
            parts = line[1:].strip().split()
            if len(parts) >= 2:
                metadata[parts[0]] = parts[-1]
            continue
        rows.append([float(v) for v in line.split()])
    return metadata, rows

def positive_min(a):
    vals = [v for row in a for v in row if v > 0.0 and math.isfinite(v)]
    return max(min(vals), 1.0e-16)

def maxval(a):
    return max(v for row in a for v in row if math.isfinite(v))

def magma_like(t):
    t = min(max(t, 0.0), 1.0)
    stops = [
        (0.00, (0, 0, 4)),
        (0.25, (79, 18, 123)),
        (0.50, (182, 54, 121)),
        (0.75, (251, 136, 97)),
        (1.00, (252, 253, 191)),
    ]
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if t <= b:
            u = (t - a) / (b - a)
            return tuple(round(ca[i] * (1 - u) + cb[i] * u) for i in range(3))
    return stops[-1][1]

def render_panel(values, vmin, vmax, scale):
    ny = len(values)
    nx = len(values[0])
    lvmin = math.log10(vmin)
    lvmax = math.log10(max(vmax, vmin * 10.0))
    panel = []
    for j in range(ny - 1, -1, -1):
        line = []
        for i in range(nx):
            v = max(values[j][i], vmin)
            t = (math.log10(v) - lvmin) / (lvmax - lvmin)
            color = magma_like(t)
            line.extend([color] * scale)
        for _ in range(scale):
            panel.append(line[:])
    return panel

def render_colorbar(vmin, vmax, height, width):
    bar = []
    for j in range(height):
        u = 1.0 - j / max(height - 1, 1)
        color = magma_like(u)
        row = [color for _ in range(width)]
        bar.append(row)
    for y in (0, height // 2, height - 1):
        for x in range(width):
            bar[y][x] = (0, 0, 0)
    return bar

def write_png(path, pixels):
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b in row:
            raw.extend((r, g, b))
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)
    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(chunk(b"IEND", b""))
    Path(path).write_bytes(png)

FONT = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    ".": ("000", "000", "000", "000", "010"),
    "-": ("000", "000", "111", "000", "000"),
    "+": ("000", "010", "111", "010", "000"),
    "e": ("111", "100", "111", "100", "111"),
}

def draw_text(canvas, x, y, text, color=(0, 0, 0), scale=3):
    cursor = x
    for ch in text:
        glyph = FONT.get(ch)
        if glyph is None:
            cursor += 2 * scale
            continue
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    for sy in range(scale):
                        for sx in range(scale):
                            yy = y + gy * scale + sy
                            xx = cursor + gx * scale + sx
                            if 0 <= yy < len(canvas) and 0 <= xx < len(canvas[0]):
                                canvas[yy][xx] = color
        cursor += 4 * scale

def render_case(path):
    metadata, rows = read_case(path)
    xs = sorted({r[0] for r in rows})
    ys = sorted({r[1] for r in rows})
    nx = len(xs)
    ny = len(ys)
    rel_norm = [[0.0 for _ in range(nx)] for _ in range(ny)]
    for k, r in enumerate(rows):
        j = k // nx
        i = k % nx
        rel_norm[j][i] = r[9]

    scale = 4
    gap = 24
    border = 16
    colorbar_w = 32
    label_w = 110
    rel_min = positive_min(rel_norm)
    rel_max = maxval(rel_norm)
    panel = render_panel(rel_norm, rel_min, rel_max, scale)
    colorbar = render_colorbar(rel_min, rel_max, len(panel), colorbar_w)
    panel_h = len(panel)
    panel_w = len(panel[0])
    white = (255, 255, 255)
    canvas = [[white for _ in range(border * 2 + panel_w + gap + colorbar_w + label_w)] for _ in range(border * 2 + panel_h)]
    for y in range(panel_h):
        for x in range(panel_w):
            canvas[border + y][border + x] = panel[y][x]
        for x in range(colorbar_w):
            canvas[border + y][border + panel_w + gap + x] = colorbar[y][x]

    label_x = border + panel_w + gap + colorbar_w + 8
    draw_text(canvas, label_x, border, f"{rel_max:.1e}")
    draw_text(canvas, label_x, border + panel_h // 2 - 8, f"{math.sqrt(rel_min * rel_max):.1e}")
    draw_text(canvas, label_x, border + panel_h - 16, f"{rel_min:.1e}")

    out_path = path.with_suffix(".png")
    write_png(out_path, canvas)
    print(f"{out_path}: relative_colorbar_log_range = [{rel_min:.6e}, {rel_max:.6e}]")

for path in data_paths:
    render_case(path)
""")
end

summaries = [
    validate_pic_gaussian_case(
        i, case.sigx, case.sigy, solver, result_dir;
        nsource_axis=nsource_axis,
        field_axis=field_axis,
        extent_sigma=extent_sigma,
        pic_grid=pic_grid,
        write_case_data=write_case_data,
    )
    for (i, case) in enumerate(validation_cases)
]

summary_name = random_cases > 0 ?
    "pic_gaussian_field_validation_random_summary.tsv" :
    "pic_gaussian_field_validation_summary.tsv"
summary_path = joinpath(result_dir, summary_name)
open(summary_path, "w") do io
    println(io, "# random_cases\t$random_cases")
    println(io, "# random_seed\t$random_seed")
    println(io, "# random_sigma_min\t$random_sigma_min")
    println(io, "# random_sigma_max\t$random_sigma_max")
    println(io, "# write_case_data\t$write_case_data")
    println(io, "# nsource_axis\t$nsource_axis")
    println(io, "# field_axis\t$field_axis")
    println(io, "# pic_grid\t$pic_grid")
    println(io, "# extent_sigma\t$extent_sigma")
    println(io, "# columns\tcase_id sigx sigy sigma_ratio_x_over_y nsource field_axis pic_grid max_grid_exact_norm min_relative median_relative mean_relative p95_relative max_relative data_path image_path")
    for s in summaries
        println(io, join((
            s.case_id, s.sigx, s.sigy, s.sigma_ratio, s.nsource, s.field_axis, s.pic_grid,
            s.global_exact_norm, s.min_relative, s.median_relative, s.mean_relative,
            s.p95_relative, s.max_relative, s.data_path, s.image_path,
        ), '\t'))
    end
end

python = Sys.which("python3")
if write_case_data && python !== nothing
    run(`$python $plot_path`)
elseif write_case_data
    @warn "python3 not found; run the plot helper manually to create PNG images" plot_path
else
    @info "case grid files disabled; only the summary TSV was written"
end

println("summary = ", summary_path)
println("plot helper = ", plot_path)
if length(summaries) <= 20
    for s in summaries
        println(
            "case ", s.case_id,
            " sigx=", s.sigx,
            " sigy=", s.sigy,
            " median_rel=", s.median_relative,
            " p95_rel=", s.p95_relative,
            " max_rel=", s.max_relative,
        )
    end
else
    medians = [s.median_relative for s in summaries]
    p95s = [s.p95_relative for s in summaries]
    maxes = [s.max_relative for s in summaries]
    worst = summaries[argmax(maxes)]
    println("cases = ", length(summaries))
    println("median_of_median_rel = ", median(medians))
    println("max_median_rel = ", maximum(medians))
    println("median_p95_rel = ", median(p95s))
    println("max_p95_rel = ", maximum(p95s))
    println("median_max_rel = ", median(maxes))
    println("max_max_rel = ", maximum(maxes))
    println(
        "worst_case = ", worst.case_id,
        " sigx=", worst.sigx,
        " sigy=", worst.sigy,
        " ratio=", worst.sigma_ratio,
        " median_rel=", worst.median_relative,
        " p95_rel=", worst.p95_relative,
        " max_rel=", worst.max_relative,
    )
end
