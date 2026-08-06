"""
Aggregate the per-arm/seed runs of `slice_interpolation_emittance_growth.jl`.

Reads every `result/emittance_growth_*.meta.tsv` and reports the seed mean growth
rate with its spread, per arm.

The spread is the point of the script. Shot noise alone drives vertical emittance
growth in a strong-strong PIC run, and it differs from seed to seed. An arm is
only judged different from the baseline when the separation of the seed means
exceeds the seed-to-seed standard deviation -- otherwise the comparison is
measuring noise. `t_like` in the output is that separation expressed in pooled
standard errors; treat |t_like| < 2 as "not resolved".

**An arm is the full set of recorded run conditions, not just the four the study
varies.** Vertical growth scales roughly as 1/`npart`, so pooling runs taken at
different particle counts inflates the baseline spread by the between-group
variation and drags its mean. Every meta column that is not the run identity
(`tag`, `seed`) and not a measured output is therefore part of the grouping key:
`scheme`, `nslices`, `deposit` and `gridmode` define the *arm*, and the rest
(`npart`, `turns`, `grid`, `solver`, ...) define the *block* an arm is compared
within. A new condition column added to the meta row joins the key automatically
rather than being silently ignored.

Each arm is compared only against the baseline of its own block -- the
`:linear` / lowest-slice-count / `CIC` / `slice_pair` arm sharing that arm's
block conditions exactly. An arm whose block has no baseline reports `t_like`
as `NaN` and is listed as uncompared, rather than borrowing another block's.

Two seeds cannot collide. Two rows with the same `seed` and identical conditions
are either the same run counted twice or runs from a modified script that the
meta row cannot distinguish; either way the seed-variance estimate is not
defined, so the script errors and names the colliding tags instead of averaging
them. Runs that are not products of this script belong under a different file
prefix, not in `emittance_growth_*`.

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
            get!(d, "solver", "unrecorded")
            push!(runs, d)
        end
    end
    return runs
end

runs = load_runs(result_dir, files)

# The measured quantities. Everything else in a meta row is either the run
# identity or a condition, so a newly recorded condition joins the key without
# an edit here; a newly recorded *output* must be added, and until it is the
# blocks visibly fragment rather than silently pooling.
const OUTPUT_COLS = Set(["growth_ele_ey", "growth_ele_ex", "growth_pro_ey", "growth_pro_ex",
                         "final_ratio_ele_ey", "final_ratio_pro_ey",
                         "boundary_cross_fraction", "elapsed_s"])
const IDENTITY_COLS = Set(["tag", "seed"])
# The four the study varies; the remaining conditions define the comparison block.
const ARM_COLS = ["scheme", "nslices", "deposit", "gridmode"]

all_cols = sort(unique(reduce(vcat, [collect(keys(d)) for d in runs])))
block_cols = filter(c -> !(c in OUTPUT_COLS) && !(c in IDENTITY_COLS) && !(c in ARM_COLS),
                    all_cols)

cell(d, c) = haskey(d, c) ? (d[c] isa AbstractString ? String(d[c]) : d[c]) : missing
arm_of(d) = Tuple(cell(d, c) for c in ARM_COLS)
block_of(d) = Tuple(cell(d, c) for c in block_cols)
key_of(d) = (block_of(d), arm_of(d))

groups = Dict{Any,Vector{Dict{String,Any}}}()
for d in runs
    push!(get!(groups, key_of(d), Vector{Dict{String,Any}}()), d)
end

# A repeated seed under identical conditions makes the seed spread undefined.
collisions = String[]
for (k, rs) in groups
    byseed = Dict{Any,Vector{String}}()
    for d in rs
        push!(get!(byseed, d["seed"], String[]), String(d["tag"]))
    end
    for (s, tags) in sort(collect(byseed), by=first)
        length(tags) > 1 || continue
        push!(collisions,
              @sprintf("  seed %s in %s %s: %s", s, string(k[2]), string(k[1]), join(sort(tags), ", ")))
    end
end
if !isempty(collisions)
    error("duplicate seeds under identical recorded conditions -- the seed-to-seed\n" *
          "spread is undefined for these arms. Runs that are not products of this\n" *
          "script must not use the `emittance_growth_*` file prefix.\n" *
          join(sort(collisions), "\n"))
end

function stats(v)
    n = length(v)
    return mean(v), (n > 1 ? std(v) : NaN), n
end

"""Separation of an arm mean from its block baseline, in pooled standard errors."""
function tlike(v, base)
    (length(v) < 2 || length(base) < 2) && return NaN
    m, s, n = stats(v)
    bm, bs, bn = stats(base)
    se = sqrt(s^2 / n + bs^2 / bn)
    return se == 0 ? NaN : (m - bm) / se
end

# Baseline is per block: the :linear / lowest-nslices / CIC / slice_pair arm
# sharing that block's conditions. No cross-block comparison is formed.
blocks = unique(k[1] for k in keys(groups))
baseline_of = Dict{Any,Any}()
for b in blocks
    arms_here = [k[2] for k in keys(groups) if k[1] == b]
    cands = filter(a -> a[1] == "linear" && a[3] == "CIC" && a[4] == "slice_pair", arms_here)
    isempty(cands) && continue
    baseline_of[b] = (b, cands[argmin([a[2] for a in cands])])
end

vals(rs, col) = [Float64(d[col]) for d in rs]

keys_sorted = sort(collect(keys(groups)), by=k -> (string(k[1]), k[2][4], k[2][3], k[2][2], k[2][1]))

println("block conditions: ", join(block_cols, ", "))
println()
@printf("%-10s %-4s %-5s %-12s %-3s %13s %8s %13s %8s %6s  %s\n",
        "scheme", "nsl", "dep", "gridmode", "n",
        "ele_ey_growth", "t_ele", "pro_ey_growth", "t_pro", "cross", "block")

summary = Vector{Any}()
uncompared = String[]
for k in keys_sorted
    rs = groups[k]
    a = k[2]
    bkey = get(baseline_of, k[1], nothing)
    is_base = bkey !== nothing && bkey == k
    brs = bkey === nothing ? Dict{String,Any}[] : groups[bkey]
    if bkey === nothing
        push!(uncompared, string(a) * " " * string(k[1]))
    end

    ey = vals(rs, "growth_pro_ey")
    ex = vals(rs, "growth_pro_ex")
    eey = vals(rs, "growth_ele_ey")
    cross = mean(vals(rs, "boundary_cross_fraction"))
    el = mean(vals(rs, "elapsed_s"))
    m, s, n = stats(ey)
    me, se_, _ = stats(eey)
    t_pro = is_base || isempty(brs) ? NaN : tlike(ey, vals(brs, "growth_pro_ey"))
    t_ele = is_base || isempty(brs) ? NaN : tlike(eey, vals(brs, "growth_ele_ey"))

    blockstr = join(string.(k[1]), "/")
    @printf("%-10s %-4d %-5s %-12s %-3d %13.4e %8.2f %13.4e %8.2f %6.3f  %s\n",
            a[1], a[2], a[3], a[4], n, me, t_ele, m, t_pro, cross, blockstr)
    push!(summary, [a[1] a[2] a[3] a[4] blockstr n me se_ t_ele m s t_pro mean(ex) cross el])
end

open(joinpath(result_dir, "emittance_growth_summary.tsv"), "w") do io
    writedlm(io, ["scheme" "nslices" "deposit" "gridmode" "block" "seeds" "growth_ele_ey_mean" "growth_ele_ey_sd" "t_like_ele" "growth_pro_ey_mean" "growth_pro_ey_sd" "t_like_pro" "growth_pro_ex_mean" "boundary_cross_fraction" "elapsed_s_mean"])
    writedlm(io, vcat(summary...))
end
println()
if !isempty(uncompared)
    println("no baseline in block, t_like left NaN:")
    foreach(u -> println("  ", u), sort(uncompared))
    println()
end
println("baseline per block = (linear, lowest nslices, CIC, slice_pair)")
println("|t_like| < 2 means the arm is NOT resolved from the baseline at this seed count.")
println("Wrote result/emittance_growth_summary.tsv")
