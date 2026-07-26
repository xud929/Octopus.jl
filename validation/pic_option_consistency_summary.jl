"""
Compare completed runs of `pic_option_consistency.jl` against a baseline.

Reads every `result/pic_option_*.meta.tsv` and its per-turn series, and reports
how far each option set drifts from the baseline over the run, at three levels of
strictness:

1. **Luminosity** -- mean relative difference over the last quarter of the run,
   plus the worst single turn.
2. **Moments** -- same, for `eps_y` (the flat-beam observable) and `eps_x`.
3. **Coordinates** -- if a `.coords.tsv` exists for both runs, the RMS and maximum
   per-particle coordinate difference at each dump turn, normalized by the beam
   size. This is the strict check: a systematic per-particle bias can hide inside
   an unchanged luminosity.

The options change the discretization deliberately, so they are **not** expected to
agree bit-for-bit. What the numbers establish is that the differences stay at the
size the discretization implies and do not grow without bound over the run --
a divergent option would show a rising trend rather than a bounded scatter.

Run
---
```bash
julia --project=. validation/pic_option_consistency_summary.jl
```

Outputs `result/pic_option_consistency_summary.tsv`.
"""

using DelimitedFiles
using Printf
using Statistics

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
metas = sort(filter(f -> startswith(f, "pic_option_") && endswith(f, ".meta.tsv"),
                    readdir(result_dir)))
isempty(metas) && error("no result/pic_option_*.meta.tsv; run pic_option_consistency.jl first")

runs = Dict{String,Any}()
for f in metas
    d, h = readdlm(joinpath(result_dir, f), '\t', header=true)
    names = String.(vec(h))
    m = Dict{String,Any}(names[c] => d[1, c] for c in eachindex(names))
    tag = String(m["tag"])
    series_path = joinpath(result_dir, "pic_option_$(tag).tsv")
    isfile(series_path) || continue
    sd, sh = readdlm(series_path, '\t', header=true)
    m["series"] = sd
    m["cols"] = Dict(String(c) => i for (i, c) in enumerate(vec(sh)))
    cp = joinpath(result_dir, "pic_option_$(tag).coords.tsv")
    m["coords"] = isfile(cp) ? readdlm(cp, '\t', header=true) : nothing
    runs[tag] = m
end

# Compare each run against the baseline with the SAME particle count: a 2k-particle
# run and a 50k-particle run differ by shot noise, which has nothing to do with the
# option under test.
baseline_for(tag) = endswith(tag, "_c") ? "base_c" : "base"


col(m, name) = m["series"][:, m["cols"][name]]

"""Mean and worst relative difference over the last quarter of the run."""
function reldiff(a, b)
    n = min(length(a), length(b))
    lo = max(1, n - n ÷ 4)
    d = [abs(a[i] - b[i]) / max(abs(b[i]), eps()) for i in lo:n if isfinite(a[i]) && isfinite(b[i])]
    isempty(d) && return (NaN, NaN)
    return (mean(d), maximum(d))
end

"""Trend of |a-b|/|b| over the run: >0 means the options are diverging."""
function drift(a, b)
    n = min(length(a), length(b))
    d = [abs(a[i] - b[i]) / max(abs(b[i]), eps()) for i in 1:n if isfinite(a[i]) && isfinite(b[i])]
    length(d) < 4 && return NaN
    h = length(d) ÷ 2
    return mean(d[(h + 1):end]) - mean(d[1:h])
end

rows = Vector{Any}()
@printf("%-10s %6s %9s %11s %11s %11s %11s %10s\n",
        "tag", "npart", "turn_s", "lum_mean", "lum_worst", "epsy_mean", "epsx_mean", "lum_drift")
for tag in sort(collect(keys(runs)))
    m = runs[tag]
    bt = baseline_for(tag)
    haskey(runs, bt) || continue
    base = runs[bt]
    lm, lw = reldiff(col(m, "luminosity"), col(base, "luminosity"))
    ym, _ = reldiff(col(m, "e_ey"), col(base, "e_ey"))
    xm, _ = reldiff(col(m, "e_ex"), col(base, "e_ex"))
    dr = drift(col(m, "luminosity"), col(base, "luminosity"))
    @printf("%-10s %6d %9.4f %11.3e %11.3e %11.3e %11.3e %10.2e\n",
            tag, Int(m["npart"]), Float64(m["mean_turn_s"]), lm, lw, ym, xm, dr)
    push!(rows, [tag Int(m["npart"]) Float64(m["mean_turn_s"]) lm lw ym xm dr])
end

# --- coordinate-level comparison ---------------------------------------------
println()
coord_tags = sort([t for t in keys(runs) if runs[t]["coords"] !== nothing])
if length(coord_tags) >= 2
    cbase = haskey(runs, "base_c") ? "base_c" : first(coord_tags)
    bd, bh = runs[cbase]["coords"]
    bcols = Dict(String(c) => i for (i, c) in enumerate(vec(bh)))
    key(d, i) = (Int(d[i, bcols["turn"]]), Int(d[i, bcols["beam"]]), Int(d[i, bcols["particle"]]))
    bidx = Dict(key(bd, i) => i for i in axes(bd, 1))
    @printf("coordinate baseline = %s\n\n", cbase)
    @printf("%-10s %6s %14s %14s %14s\n", "tag", "turn", "rms_dx/sigx", "rms_dy/sigy", "max_dy/sigy")
    sigx, sigy = 106.0e-6, 9.5e-6
    for tag in coord_tags
        tag == cbase && continue
        d, h = runs[tag]["coords"]
        cols = Dict(String(c) => i for (i, c) in enumerate(vec(h)))
        byturn = Dict{Int,Vector{Tuple{Float64,Float64}}}()
        for i in axes(d, 1)
            k = (Int(d[i, cols["turn"]]), Int(d[i, cols["beam"]]), Int(d[i, cols["particle"]]))
            j = get(bidx, k, nothing)
            j === nothing && continue
            push!(get!(() -> Tuple{Float64,Float64}[], byturn, k[1]),
                  (d[i, cols["x"]] - bd[j, bcols["x"]], d[i, cols["y"]] - bd[j, bcols["y"]]))
        end
        for t in sort(collect(keys(byturn)))
            v = byturn[t]
            rx = sqrt(mean(abs2(a[1]) for a in v)) / sigx
            ry = sqrt(mean(abs2(a[2]) for a in v)) / sigy
            my = maximum(abs(a[2]) for a in v) / sigy
            @printf("%-10s %6d %14.3e %14.3e %14.3e\n", tag, t, rx, ry, my)
        end
    end
end

open(joinpath(result_dir, "pic_option_consistency_summary.tsv"), "w") do io
    writedlm(io, ["tag" "npart" "mean_turn_s" "lum_reldiff_mean" "lum_reldiff_worst" "epsy_reldiff_mean" "epsx_reldiff_mean" "lum_drift"])
    writedlm(io, vcat(rows...))
end
println()
println("Wrote result/pic_option_consistency_summary.tsv")
