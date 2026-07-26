"""
Aggregate the per-arm/seed runs of `slice_interpolation_emittance_growth.jl`.

Reads every `result/emittance_growth_*.meta.tsv`, groups by arm (scheme, slices,
deposition, interaction grid), and reports the seed mean growth rate with its
spread.

The spread is the point of the script. Shot noise alone drives vertical emittance
growth in a strong-strong PIC run, and it differs from seed to seed. An arm is
only judged different from the baseline when the separation of the seed means
exceeds the seed-to-seed standard deviation -- otherwise the comparison is
measuring noise. `t_like` in the output is that separation expressed in pooled
standard errors; treat |t_like| < 2 as "not resolved".

The electron beam is the more sensitive probe: its synchrotron tune is -0.069
against the proton's -0.01, so in a fixed number of turns it executes ~7x more
synchrotron periods and samples the slice-boundary discontinuity that much more
often. Both beams are reported.

`boundary_cross_fraction` is a validity check, not a result: if particles do not
change slice index between turns, the slice-boundary discontinuity is never
sampled and a null result carries no information.

Run (after the arm processes have finished):

```bash
julia --project=. validation/slice_interpolation_emittance_growth_summary.jl
```

Outputs `result/emittance_growth_summary.tsv`.
"""

using DelimitedFiles
using Printf
using Statistics

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
files = sort(filter(f -> startswith(f, "emittance_growth_") && endswith(f, ".meta.tsv"),
                    readdir(result_dir)))
isempty(files) && error("no result/emittance_growth_*.meta.tsv files; run the arms first")

# Meta files written before `interaction_grid` existed lack a `gridmode` column,
# so each file is read with its own header and normalized into a Dict per run.
function load_runs(dir, files)
    runs = Vector{Dict{String,Any}}()
    for f in files
        data, head = readdlm(joinpath(dir, f), '\t', header=true)
        names = String.(vec(head))
        for r in 1:size(data, 1)
            d = Dict{String,Any}(names[c] => data[r, c] for c in eachindex(names))
            get!(d, "gridmode", "slice_pair")
            push!(runs, d)
        end
    end
    return runs
end

runs = load_runs(result_dir, files)

arm_of(d) = (String(d["scheme"]), Int(d["nslices"]),
             String(d["deposit"]), String(d["gridmode"]))

arms = Dict{Any,Vector{Dict{String,Any}}}()
for d in runs
    push!(get!(arms, arm_of(d), Vector{Dict{String,Any}}()), d)
end

function stats(v)
    n = length(v)
    m = mean(v)
    s = n > 1 ? std(v) : NaN
    return m, s, n
end

keys_sorted = sort(collect(keys(arms)), by=k -> (k[4], k[3], k[2], k[1]))
baseline = ("linear", minimum(k[2] for k in keys_sorted), "CIC", "slice_pair")

summary = Vector{Any}()
base_pro = haskey(arms, baseline) ? [Float64(d["growth_pro_ey"]) for d in arms[baseline]] : Float64[]
base_ele = haskey(arms, baseline) ? [Float64(d["growth_ele_ey"]) for d in arms[baseline]] : Float64[]

"""Separation of an arm mean from the baseline mean, in pooled standard errors."""
function tlike(v, base, is_baseline)
    (is_baseline || length(v) < 2 || length(base) < 2) && return NaN
    m, s, n = stats(v); bm, bs, bn = stats(base)
    se = sqrt(s^2 / n + bs^2 / bn)
    return se == 0 ? NaN : (m - bm) / se
end

@printf("%-10s %-4s %-5s %-12s %-3s %13s %8s %13s %8s %6s\n",
        "scheme", "nsl", "dep", "gridmode", "n",
        "ele_ey_growth", "t_ele", "pro_ey_growth", "t_pro", "cross")
for k in keys_sorted
    rs = arms[k]
    ey = [Float64(d["growth_pro_ey"]) for d in rs]
    ex = [Float64(d["growth_pro_ex"]) for d in rs]
    eey = [Float64(d["growth_ele_ey"]) for d in rs]
    cross = mean(Float64(d["boundary_cross_fraction"]) for d in rs)
    el = mean(Float64(d["elapsed_s"]) for d in rs)
    m, s, n = stats(ey)
    me, se_, _ = stats(eey)
    t_pro = tlike(ey, base_pro, k == baseline)
    t_ele = tlike(eey, base_ele, k == baseline)
    @printf("%-10s %-4d %-5s %-12s %-3d %13.4e %8.2f %13.4e %8.2f %6.3f\n",
            k[1], k[2], k[3], k[4], n, me, t_ele, m, t_pro, cross)
    push!(summary, [k[1] k[2] k[3] k[4] n me se_ t_ele m s t_pro mean(ex) cross el])
end

open(joinpath(result_dir, "emittance_growth_summary.tsv"), "w") do io
    writedlm(io, ["scheme" "nslices" "deposit" "gridmode" "seeds" "growth_ele_ey_mean" "growth_ele_ey_sd" "t_like_ele" "growth_pro_ey_mean" "growth_pro_ey_sd" "t_like_pro" "growth_pro_ex_mean" "boundary_cross_fraction" "elapsed_s_mean"])
    writedlm(io, vcat(summary...))
end
println()
println("baseline = ", baseline)
println("|t_like| < 2 means the arm is NOT resolved from the baseline at this seed count.")
println("Wrote result/emittance_growth_summary.tsv")
