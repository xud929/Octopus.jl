"""
Multi-turn consistency and cost of the PIC solver options.

Runs the crab-crossing EIC case of `examples/strong_strong_tracking.jl` -- same
beam parameters, crab cavities, Lorentz boost pair, one-turn optics, chromaticity
and electron radiation -- for a configurable number of turns under one PIC option
set, and records enough per turn to compare option sets against each other.

The options are *not* expected to agree bit-for-bit: each changes the
discretization deliberately. What is checked is that they agree to the accuracy the
discretization implies, and that none of them drifts away or destabilizes over many
turns. Three levels of evidence are recorded, in increasing strictness:

1. **Luminosity per turn** -- the coarsest integral observable.
2. **Beam moments per turn** -- `eps_x`, `eps_y`, `eps_z` and the centroid, which
   respond to per-particle errors that cancel in the luminosity.
3. **Per-particle coordinates at selected turns** -- the strictest check, and the
   one that catches a systematic per-particle bias whose beam-averaged effect is
   small. Run this with a small `OCTOPUS_OPT_NPART` so the dump stays manageable.

Timing is the mean wall time over turns `timing_from`..`turns`, excluding the
first turns so compilation and cache warm-up are not counted.

Run
---
```bash
OCTOPUS_OPT_TAG=base julia --threads=6 --project=. validation/pic_option_consistency.jl
```

Production reference point (from `examples/strong_strong_tracking.jl` and the
2026-07-24 Poisson-solver review): 2_560_000 electrons, 1_024_000 protons, 15
slices, grid (128,128), CUDA with the default indexed wavefront path -- about
0.3 s/turn including luminosity and moment output. Benchmark there, not at a
convenient small size: the cost ordering of the options is grid- and
particle-count dependent.

Overrides: `OCTOPUS_OPT_TAG`, `OCTOPUS_OPT_TURNS`, `OCTOPUS_OPT_NPART`
(or `OCTOPUS_OPT_NPART_E` / `OCTOPUS_OPT_NPART_P` separately),
`OCTOPUS_OPT_GRID`, `OCTOPUS_OPT_NSLICES`, `OCTOPUS_OPT_INTERACTION_GRID`,
`OCTOPUS_OPT_SLICE_INTERP`, `OCTOPUS_OPT_DEPOSIT`, `OCTOPUS_OPT_EXTENT`,
`OCTOPUS_OPT_QUANTIZE`, `OCTOPUS_OPT_DUMP_TURNS` (comma-separated),
`OCTOPUS_OPT_TIMING_FROM`, `OCTOPUS_OPT_BACKEND` (`cpu`/`gpu`),
`OCTOPUS_OPT_BATCH_MODE`, `OCTOPUS_OPT_CUDA_ASYNC`.

!!! warning "Hold batching fixed before comparing GPU costs"
    On the GPU, `interaction_grid=:node` and `slice_interpolation=:quadratic`
    each *also* switch `batch_mode` to `:sequential` and turn `cuda_async` off,
    unless you set `OCTOPUS_OPT_BATCH_MODE`/`OCTOPUS_OPT_CUDA_ASYNC`. A
    `mean_turn_s` from such an arm is the cost of the option **plus** the cost
    of losing batching, and the audit measured that as a 2.4x "cost of `:node`"
    (0.0252 s wavefront against 0.0617 s sequential+sync). The run now warns
    when this fires, and both effective values are recorded in `meta.tsv`
    (2026-08-05_b audit, U25-1).

Compare completed runs with
`validation/pic_option_consistency_summary.jl`.

Outputs (under `result/`)
-------------------------
- `pic_option_<tag>.tsv`        -- per-turn luminosity and moments
- `pic_option_<tag>.coords.tsv` -- coordinates at the dump turns
- `pic_option_<tag>.meta.tsv`   -- one row: options (including the *effective*
  `batch_mode` and `cuda_async`), timing, totals
- `pic_option_<tag>.h5`         -- the task's run artifact (append mode, one
  continuous /luminosity/ip series across the one-turn execute! calls), read
  back for the series above (2026-08-05_b audit, U25-8)
"""

using Octopus
using DelimitedFiles
using Printf

const O = Octopus

_envi(k, d) = parse(Int, get(ENV, k, string(d)))
_envf(k, d) = parse(Float64, get(ENV, k, string(d)))
_envs(k, d) = Symbol(get(ENV, k, string(d)))

config = (
    tag         = get(ENV, "OCTOPUS_OPT_TAG", "base"),
    turns       = _envi("OCTOPUS_OPT_TURNS", 200),
    npart       = _envi("OCTOPUS_OPT_NPART", 50_000),
    npart_e     = _envi("OCTOPUS_OPT_NPART_E", _envi("OCTOPUS_OPT_NPART", 50_000)),
    npart_p     = _envi("OCTOPUS_OPT_NPART_P", _envi("OCTOPUS_OPT_NPART", 50_000)),
    grid        = _envi("OCTOPUS_OPT_GRID", 64),
    nslices     = _envi("OCTOPUS_OPT_NSLICES", 15),
    igrid       = _envs("OCTOPUS_OPT_INTERACTION_GRID", :slice_pair),
    sinterp     = _envs("OCTOPUS_OPT_SLICE_INTERP", :linear),
    deposit     = _envs("OCTOPUS_OPT_DEPOSIT", :CIC),
    extent      = _envs("OCTOPUS_OPT_EXTENT", :extrema),
    quantize    = _envf("OCTOPUS_OPT_QUANTIZE", 0.0),
    timing_from = _envi("OCTOPUS_OPT_TIMING_FROM", 100),
    backend     = _envs("OCTOPUS_OPT_BACKEND", :cpu),
    batch_mode  = get(ENV, "OCTOPUS_OPT_BATCH_MODE", ""),
    cuda_async  = get(ENV, "OCTOPUS_OPT_CUDA_ASYNC", ""),
    dump_turns  = [parse(Int, t) for t in split(get(ENV, "OCTOPUS_OPT_DUMP_TURNS", ""), ",") if !isempty(t)],
)

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

# --- physics: the strong-strong example's crab-crossing EIC case ---------------
crossing = 12.5e-3
ele = (charge=-1.0, mass=EMASS_EV, energy=10.0e9, n_particle=1.7203e11, cutoff=5.0,
       sigma=(106.0e-6, 9.5e-6, 0.7e-2), beta=(0.55, 0.056, 0.7e-2 / 5.5e-4),
       alpha=(0.0, 0.0, 0.0), crab_beta=(150.0, 30.0, 0.7e-2 / 5.5e-4),
       tune=(0.08, 0.14, -0.069), chrom=(1.0, 1.0), fcrab=394.0e6,
       kx=(tan(crossing) / sqrt(150.0 * 0.55), 0.0, 0.0), damp=(4000.0, 4000.0, 2000.0))
pro = (charge=1.0, mass=PMASS_EV, energy=275.0e9, n_particle=0.6881e11, cutoff=5.0,
       sigma=(95.0e-6, 8.5e-6, 6.0e-2), beta=(0.8, 0.072, 6.0e-2 / 6.6e-4),
       alpha=(0.0, 0.0, 0.0), crab_beta=(1300.0, 30.0, 6.0e-2 / 6.6e-4),
       tune=(0.228, 0.210, -0.01), chrom=(2.0, 2.0), fcrab=197.0e6,
       kx=(tan(crossing) / sqrt(1300.0 * 0.8) * 4.0 / 3.0,
           -tan(crossing) / sqrt(1300.0 * 0.8) / 3.0, 0.0))

policy = config.backend === :gpu ? CUDAExecutionPolicy() : CPUThreadsExecutionPolicy()
backend = config.backend === :gpu ? Octopus.CUDABackend : CPUThreadsBackend

set_global_rng!(seed=123456789, method=:philox)
beam_e = Beam(config.npart_e, policy, Float64; beta=ele.beta, alpha=ele.alpha,
    sigma=ele.sigma, cutoff=ele.cutoff, rng_id=1, charge=ele.charge, mc2=ele.mass,
    E0=ele.energy, r0=RE * ME0 / ele.mass, npart=ele.n_particle)
beam_p = Beam(config.npart_p, policy, Float64; beta=pro.beta, alpha=pro.alpha,
    sigma=pro.sigma, cutoff=pro.cutoff, rng_id=2, charge=pro.charge, mc2=pro.mass,
    E0=pro.energy, r0=RE * ME0 / pro.mass, npart=pro.n_particle)

slicing = LongitudinalSlicing(; method=:normal_quantile, nslices=config.nslices,
                              center_position=:centroid)
solver = PICPoissonSolver(; slicing=slicing, grid=(config.grid, config.grid),
    deposit_method=config.deposit, green_type=:integrated, green_cache=:slice_pair,
    longitudinal_kick=true, slice_interpolation=config.sinterp,
    interaction_grid=config.igrid, grid_extent=config.extent,
    grid_quantize=config.quantize,
    batch_mode=isempty(config.batch_mode) ?
        ((config.backend === :gpu && (config.igrid === :node || config.sinterp === :quadratic)) ?
            :sequential : :wavefront) : Symbol(config.batch_mode),
    cuda_async=isempty(config.cuda_async) ?
        !(config.backend === :gpu && (config.igrid === :node || config.sinterp === :quadratic)) :
        parse(Bool, config.cuda_async))

# A silent batching downgrade would confound every cost number this script
# reports (2026-08-05_b audit, U25-1).
#
# On the GPU, `interaction_grid=:node` and `slice_interpolation=:quadratic` each
# ALSO flip `batch_mode` to `:sequential` and `cuda_async` off, unless the caller
# overrides them. This script exists to report the per-turn cost of an option --
# its own docstring says the cost ordering is grid- and particle-count dependent
# -- so attributing a sequential, synchronous run's cost to `:node` alone
# overstates it by whatever the batching is worth. Measured for the audit:
# 0.0252 s (gpu, wavefront) against 0.0617 s (node, sequential+sync), reported
# as a 2.4x "cost of :node".
#
# The downgrade is not forced by the runtime -- `cuda_indexed_wavefront` defaults
# to true and the CUDA wavefront route supports `:node` through the fully-indexed
# sub-route -- so it is a default worth being able to see and to override. Both
# effective values are recorded in meta.tsv below, read off the constructed
# solver rather than recomputed here, and the downgrade announces itself.
if config.backend === :gpu && (config.igrid === :node || config.sinterp === :quadratic) &&
   (isempty(config.batch_mode) || isempty(config.cuda_async))
    @warn """
    Batching downgraded with the option under test: this arm's per-turn cost is \
    NOT comparable to a wavefront arm's without accounting for it.
      interaction_grid      = $(config.igrid)
      slice_interpolation   = $(config.sinterp)
      batch_mode            = $(solver.batch_mode)$(isempty(config.batch_mode) ? " (auto)" : " (OCTOPUS_OPT_BATCH_MODE)")
      cuda_async            = $(solver.cuda_async)$(isempty(config.cuda_async) ? " (auto)" : " (OCTOPUS_OPT_CUDA_ASYNC)")
    Set OCTOPUS_OPT_BATCH_MODE=wavefront and OCTOPUS_OPT_CUDA_ASYNC=true to hold \
    batching fixed and measure the option alone. Both effective values are in \
    the run's meta.tsv."""
end

function ring(b, other_beta, fcrab, kx, tune, chrom, rad)
    t2ip = Linear6DSpec{Float64}(; beta1=other_beta, beta2=b.beta, alpha1=b.alpha,
        alpha2=b.alpha, dmu=(pi / 2.0, 0.0, 0.0))
    t2ip_inv = Linear6DSpec{Float64}(matrix=inv(Matrix(Linear6D(t2ip))))
    ip2t = Linear6DSpec{Float64}(; beta1=b.beta, beta2=other_beta, alpha1=b.alpha,
        alpha2=b.alpha, dmu=(pi / 2.0, 0.0, 0.0))
    ip2t_inv = Linear6DSpec{Float64}(matrix=inv(Matrix(Linear6D(ip2t))))
    cav = ThinCrabCavitySpec{3}(fcrab; strengthX=kx, strengthY=(0.0, 0.0, 0.0),
                                phase=(0.0, 0.0, 0.0))
    turn = Linear6DSpec{Float64}(; beta1=b.beta, beta2=b.beta, alpha1=b.alpha,
        alpha2=b.alpha, dmu=2pi .* tune)
    ch = ChromaticityKickSpec{Float64}(; xi=chrom, beta=b.beta, alpha=b.alpha)
    return (t2ip_inv, cav, t2ip, ip2t, cav, ip2t_inv, turn, ch, rad)
end

ele_rad = LumpedRadSpec{Float64}(; damping_turns=ele.damp, beta=ele.beta,
    alpha=ele.alpha, sigma=ele.sigma, is_damping=true, is_excitation=true, rng_id=3)
lb = LorentzBoostSpec(crossing); rlb = RevLorentzBoostSpec(crossing)
ip = StrongStrongCollision(:ip; poisson_solver=solver)

re = ring(ele, ele.crab_beta, ele.fcrab, ele.kx, ele.tune, ele.chrom, ele_rad)
rp = ring(pro, pro.crab_beta, pro.fcrab, pro.kx, pro.tune, pro.chrom, nothing)
line_e = (re[1], re[2], re[3], lb, ip, rlb, re[4], re[5], re[6], re[7], re[8], ele_rad)
line_p = (rp[1], rp[2], rp[3], lb, ip, rlb, rp[4], rp[5], rp[6], rp[7], rp[8])

lum_path = joinpath(result_dir, "pic_option_$(config.tag).h5")
isfile(lum_path) && rm(lum_path)
task = StrongStrongTask(line_e, line_p;
                        artifact=RunArtifact(lum_path; append=true))

"""
Read the luminosity value the one-turn `execute!` just appended.

The artifact is in append mode, so the one-turn-per-call loop grows one
continuous /luminosity/ip series; the last value is the turn just tracked.
Every flush leaves the file readable, so reading immediately after each call
needs no buffering assumptions.
"""
function last_luminosity_value(path)
    isfile(path) || return NaN
    series = read(TaskOutput(path), :luminosity; name="ip")
    return isempty(series.value) ? NaN : Float64(series.value[end])
end

host(a) = Array(a)
function moments(beam)
    r = beam.rep
    x = host(r.x); px = host(r.px); y = host(r.y); py = host(r.py); z = host(r.z); pz = host(r.pz)
    n = length(x)
    emit(q, p) = begin
        mq = sum(q) / n; mp = sum(p) / n
        vqq = sum(abs2, q) / n - mq^2; vpp = sum(abs2, p) / n - mp^2
        vqp = sum(q .* p) / n - mq * mp
        sqrt(max(vqq * vpp - vqp^2, 0.0))
    end
    return (emit(x, px), emit(y, py), emit(z, pz), sum(x) / n, sum(y) / n, sum(z) / n)
end

rows = Vector{Any}()
coord_rows = Vector{Any}()
dump = Set(config.dump_turns)
times = Float64[]

for turn in 1:config.turns
    t0 = time()
    execute!(task, beam_e, beam_p; turns=1)
    dt = time() - t0
    turn >= config.timing_from && push!(times, dt)
    lum = last_luminosity_value(lum_path)
    me = moments(beam_e); mp = moments(beam_p)
    push!(rows, [turn, lum, me..., mp...])
    if turn in dump
        for (bn, b) in ((1, beam_e), (2, beam_p))
            r = b.rep
            xs = host(r.x); pxs = host(r.px); ys = host(r.y)
            pys = host(r.py); zs = host(r.z); pzs = host(r.pz)
            for i in eachindex(xs)
                push!(coord_rows, [turn, bn, i, xs[i], pxs[i], ys[i], pys[i], zs[i], pzs[i]])
            end
        end
    end
end

mean_t = isempty(times) ? NaN : sum(times) / length(times)
open(joinpath(result_dir, "pic_option_$(config.tag).tsv"), "w") do io
    writedlm(io, ["turn" "luminosity" "e_ex" "e_ey" "e_ez" "e_mx" "e_my" "e_mz" "p_ex" "p_ey" "p_ez" "p_mx" "p_my" "p_mz"])
    writedlm(io, permutedims(hcat(rows...)))
end
if !isempty(coord_rows)
    open(joinpath(result_dir, "pic_option_$(config.tag).coords.tsv"), "w") do io
        writedlm(io, ["turn" "beam" "particle" "x" "px" "y" "py" "z" "pz"])
        writedlm(io, permutedims(hcat(coord_rows...)))
    end
end
open(joinpath(result_dir, "pic_option_$(config.tag).meta.tsv"), "w") do io
    # batch_mode/cuda_async are read off the SOLVER, not recomputed from
    # `config`: they are what the run actually used, including the GPU
    # auto-downgrade that :node and :quadratic trigger (U25-1). Without them a
    # mean_turn_s attributed to one option silently contains a batching change.
    writedlm(io, ["tag" "backend" "turns" "npart" "npart_e" "npart_p" "grid" "nslices" "interaction_grid" "slice_interpolation" "deposit" "grid_extent" "grid_quantize" "batch_mode" "cuda_async" "mean_turn_s" "timing_from"])
    writedlm(io, [config.tag String(config.backend) config.turns config.npart config.npart_e config.npart_p config.grid config.nslices String(config.igrid) String(config.sinterp) String(config.deposit) String(config.extent) config.quantize String(solver.batch_mode) solver.cuda_async mean_t config.timing_from])
end

@printf("%-16s turns=%d npart=%d/%d grid=%d nsl=%d  mean turn (%d-%d) = %.4f s\n",
        config.tag, config.turns, config.npart_e, config.npart_p, config.grid,
        config.nslices, config.timing_from, config.turns, mean_t)
