"""
Stability of the PIC interaction-mesh extent under the `grid_extent` estimators.

The transverse mesh is sized from the slice's particles. Under the default
`:extrema` that size is a **sample extremum**, which is `O(1)`-noisy: for `n`
particles per slice the maximum is `sigma*sqrt(2 ln n)` with Gumbel fluctuation
`sigma/sqrt(2 ln n)`, and it drifts systematically with slice population. That
jitter is what makes the mesh differ between adjacent slices and between turns,
which in turn produces the transverse kick discontinuity measured by
`slice_longitudinal_zscan.jl`.

This script quantifies the premise and compares the estimators.

Reference model
---------------
There is no analytic reference; the metric is *relative variation of the box*,
which is what the mesh discontinuity is proportional to:

```text
slice_to_slice = std_s(width_s) / mean_s(width_s)     within one turn
turn_to_turn   = std_t(width_t) / mean_t(width_t)     for one fixed slice
```

`:sigma` is expected to be stabler than `:extrema`, because a second moment has
`O(1/sqrt(n))` noise where an extremum has `O(1)`. Measured: 4-8x, against a
prediction of >=10x, so the prediction was optimistic.

A `:quantile` estimator was measured here and **removed**: at a coverage target
tight enough to avoid charge loss, the target rounds to *all* particles for
realistic slice populations, so it degenerates to the extremum and adds histogram
quantization noise -- it measured *worse* than `:extrema` (7.2e-2 against 5.3e-2).

`dropped` reports particles that fell outside the estimated box and were dropped
by the zero-weight branch in `_pic_cic_weights`. It must stay at zero for a
production setting: dropping a fraction `f` of charge at radius `R` costs a field
error `~ f*(sigma/R)`, so even `1e-3` is the same order as the discontinuity the
estimators are meant to remove.

Run
---
```bash
julia --threads=4 --project=. validation/pic_grid_extent_stability.jl
```

Overrides: `OCTOPUS_EXTENT_NPART`, `OCTOPUS_EXTENT_NSLICES`, `OCTOPUS_EXTENT_TURNS`.

Outputs `result/pic_grid_extent_stability.tsv`.
"""

include("../src/Octopus.jl")
using .Octopus
using DelimitedFiles
using Printf
using Statistics

const O = Octopus
const T = Float64

_envi(k, d) = parse(Int, get(ENV, k, string(d)))

config = (
    npart   = _envi("OCTOPUS_EXTENT_NPART", 200_000),
    nslices = _envi("OCTOPUS_EXTENT_NSLICES", 15),
    turns   = _envi("OCTOPUS_EXTENT_TURNS", 8),
    grid    = (64, 64),
)

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

set_global_rng!(seed=20260726, method=:philox)
beam_e = Beam(config.npart, CPUThreadsBackend, T; beta=(0.55, 0.056, 12.7),
    alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
    rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
beam_p = Beam(config.npart, CPUThreadsBackend, T; beta=(0.8, 0.072, 90.9),
    alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
    rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)

slicing = LongitudinalSlicing(nslices=config.nslices, method=:normal_quantile)
one_turn_e = Linear6DSpec{T}(; beta1=(0.55, 0.056, 12.7), beta2=(0.55, 0.056, 12.7),
    alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0), dmu=2pi .* (0.08, 0.14, -0.069))
one_turn_p = Linear6DSpec{T}(; beta1=(0.8, 0.072, 90.9), beta2=(0.8, 0.072, 90.9),
    alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0), dmu=2pi .* (0.228, 0.210, -0.01))

"""Per-slice mesh half-widths for one estimator, on the current distribution."""
function slice_boxes(solver, beam, sl)
    slices = O.longitudinal_slices(beam.rep, sl)
    ge = Symbol(solver.grid_extent)
    k = T(solver.grid_extent_sigma)
    wx = T[]; wy = T[]; drop = 0
    for s in eachindex(slices.center)
        idx = slices.indices[s]
        isempty(idx) && continue
        xlo = T(Inf); xhi = T(-Inf); ylo = T(Inf); yhi = T(-Inf)
        xs = zero(T); xs2 = zero(T); ys = zero(T); ys2 = zero(T)
        for i in idx
            @inbounds begin
                xv = beam.rep.x[i]; yv = beam.rep.y[i]
                xlo = min(xlo, xv); xhi = max(xhi, xv)
                ylo = min(ylo, yv); yhi = max(yhi, yv)
                xs += xv; xs2 += xv * xv; ys += yv; ys2 += yv * yv
            end
        end
        n = length(idx)
        ax = O._pic_axis_extent(ge, xlo, xhi, xs, xs2, n, k)
        ay = O._pic_axis_extent(ge, ylo, yhi, ys, ys2, n, k)
        drop += count(i -> !(ax[1] <= beam.rep.x[i] <= ax[2]), idx) +
                count(i -> !(ay[1] <= beam.rep.y[i] <= ay[2]), idx)
        push!(wx, ax[2] - ax[1]); push!(wy, ay[2] - ay[1])
    end
    return wx, wy, drop
end

relvar(v) = length(v) < 2 ? NaN : std(v) / mean(v)

modes = (:extrema, :sigma)
history = Dict(m => (Vector{Vector{T}}(), Vector{Vector{T}}()) for m in modes)
drops = Dict(m => 0 for m in modes)
s2s = Dict(m => (T[], T[]) for m in modes)

task = StrongStrongTask(
    (StrongStrongCollision(:ip; poisson_solver=PICPoissonSolver(; slicing=slicing, grid=config.grid)), one_turn_e),
    (StrongStrongCollision(:ip; poisson_solver=PICPoissonSolver(; slicing=slicing, grid=config.grid)), one_turn_p))

for turn in 1:config.turns
    for m in modes
        solver = PICPoissonSolver(; slicing=slicing, grid=config.grid, grid_extent=m)
        wx, wy, d = slice_boxes(solver, beam_p, slicing)
        push!(history[m][1], wx); push!(history[m][2], wy)
        drops[m] += d
        push!(s2s[m][1], relvar(wx)); push!(s2s[m][2], relvar(wy))
    end
    execute!(task, beam_e, beam_p; turns=1)
end

rows = Vector{Any}()
@printf("%-10s %14s %14s %14s %14s %9s\n",
        "estimator", "slice2slice_x", "slice2slice_y", "turn2turn_x", "turn2turn_y", "dropped")
for m in modes
    hx, hy = history[m]
    nsl = minimum(length.(hx))
    # turn-to-turn variation, per slice, averaged over slices
    t2t_x = mean(relvar([hx[t][s] for t in eachindex(hx)]) for s in 1:nsl)
    t2t_y = mean(relvar([hy[t][s] for t in eachindex(hy)]) for s in 1:nsl)
    sx = mean(s2s[m][1]); sy = mean(s2s[m][2])
    @printf("%-10s %14.4e %14.4e %14.4e %14.4e %9d\n", m, sx, sy, t2t_x, t2t_y, drops[m])
    push!(rows, [String(m) sx sy t2t_x t2t_y drops[m]])
end

open(joinpath(result_dir, "pic_grid_extent_stability.tsv"), "w") do io
    writedlm(io, ["estimator" "slice_to_slice_x" "slice_to_slice_y" "turn_to_turn_x" "turn_to_turn_y" "dropped"])
    writedlm(io, vcat(rows...))
end
println()
println("Wrote result/pic_grid_extent_stability.tsv")
