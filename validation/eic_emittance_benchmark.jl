#=
EIC cross-code emittance benchmark (Sec. 5.4, Table 3, Fig. 8).

Head-on: crossing angle AND both crab-cavity families zeroed, chromaticity
zeroed, to match the BeamBeam3D `eicdamp` deck archived in
data/bb3d_decks/eicdamp/ of the paper repository
(https://github.com/xud929/2026_octopus_cpc).  10 GeV electrons against 275 GeV protons at the
production constants of Sec. 6.1, 15 normal-quantile slices, 128^2 mesh,
1e5 macroparticles per beam (matching BeamBeam3D), 8192 turns, electron
radiation damping shortened 4000 -> 400 turns (`radiation_damping_turns =
(400, 400, 200)` in the `input` block below -- the one place the damping
lives; the MESHSCAN receipt prints it from there).

Emittance vs turn is read from the run artifact's moment groups
(`MomentOutput(path; name = "electron"/"proton")`), NOT by
looping execute!(...; turns=1): a fresh execute! restarts the task turn
counter, which replays the counter-based Philox stream and turns the
radiation excitation into a fixed per-particle kick.  See
data/multiturn_deferred/README.md.

Run:
  OCTOPUS_USE_GPU=1 OCTOPUS_TURNS=8192 \
  OCTOPUS_N_MACRO_ELE=100000 OCTOPUS_N_MACRO_PRO=100000 \
  EIC_TAG=eic_matched EIC_MOMENT_STEP=16 SST_GRID=128 \
  julia --startup-file=no --project=. validation/eic_emittance_benchmark.jl

BeamBeam3D side: the eicdamp deck, `mpirun -n 2 ./xmain` (use the system
OpenMPI, not a conda one).  Emittance is column 7 of fort.24/25 (beam 1
x/y) and fort.34/35 (beam 2 x/y).

This file is an adapted copy of test/examples/strong_strong_tracking.jl (the
head-on EIC case with its own `input` block and the single multi-turn
`execute!`); it carried that harness's whole header verbatim under this one
until 2026-10-20 (the harness's run command, its `test/result/` outputs; the
header described another file -- comprehensive audit 2026-10-18, F-239), and it
did not receive the harness's later fixes: `env_bool`, one boolean grammar for
every switch (`OCTOPUS_USE_GPU=true` ran on the CPU here), is now its too.

Every environment variable this file reads, with its default (checked against
the body's reads at load, both directions; the OCTOPUS_* switches are the
strong-strong harness's and keep its meanings, see its header):

  run size and output
    OCTOPUS_TURNS (2), OCTOPUS_N_MACRO (200 per beam) or OCTOPUS_N_MACRO_ELE /
    OCTOPUS_N_MACRO_PRO, EIC_TAG (pic_hcc; the artifact is
    result/<EIC_TAG>.h5), EIC_MOMENT_STEP (1), EIC_EMIT_OUT
    (result/eic_emit_octopus_matched.tsv), SST_SEED (1), SST_GRID (128, the
    PIC mesh per side)
  device
    OCTOPUS_USE_GPU (0), OCTOPUS_CUDA_DEVICE, OCTOPUS_CUDA_THREADS (256),
    OCTOPUS_CUDA_BLOCKS (auto), OCTOPUS_CPU_THREADS (auto)
  physics switches
    OCTOPUS_WEAK_STRONG_LIMIT (0), OCTOPUS_ELECTRON_ENERGY_GEV,
    OCTOPUS_PROTON_ENERGY_GEV, OCTOPUS_DISABLE_COLLISION (0)
  solver
    OCTOPUS_SOLVER (pic), OCTOPUS_SPECTRAL_GRID (127,383),
    OCTOPUS_SPECTRAL_DOMAIN_FACTOR (8.0), OCTOPUS_SPECTRAL_FIELD_PRECISION
    (double), OCTOPUS_GPIC_GRID (64,64), OCTOPUS_PIC_GREEN_CACHE (slice_pair),
    OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO and
    OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO (0.50),
    OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH and
    OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_GROWTH (0.25),
    OCTOPUS_PIC_LONGITUDINAL_KICK (1), OCTOPUS_PIC_BATCH_MODE (wavefront),
    OCTOPUS_CUDA_PIC_ASYNC (1), OCTOPUS_CUDA_PIC_BATCH_FFT (1),
    OCTOPUS_CUDA_PIC_WAVEFRONT_FFT (1), OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT (1),
    OCTOPUS_PIC_LUMINOSITY_EVERY (1), OCTOPUS_PIC_LUMINOSITY_GRID,
    OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD (INHERIT),
    OCTOPUS_CUDA_PIC_GATHER_SCATTER_THREADS, OCTOPUS_CUDA_PIC_DEPOSITION_THREADS,
    OCTOPUS_CUDA_PIC_KICK_THREADS, OCTOPUS_CUDA_PIC_FIELD_THREADS,
    OCTOPUS_CUDA_PIC_SPECTRAL_THREADS, OCTOPUS_CUDA_PIC_GREEN_THREADS,
    OCTOPUS_CUDA_PIC_LUMINOSITY_THREADS
  diagnostics and output switches
    OCTOPUS_RECORD_TURN_TIMES (0), OCTOPUS_TURN_TIMING_PATH,
    OCTOPUS_CUDA_MEMORY_LOG_EVERY (0), OCTOPUS_CUDA_PIC_TIMING (0),
    OCTOPUS_CUDA_PIC_TIMING_DETAIL (0), OCTOPUS_PIC_CACHE_STATS (0),
    OCTOPUS_CUDA_NVTX (0), OCTOPUS_DISABLE_MOMENTS (0),
    OCTOPUS_DISABLE_LUMINOSITY_OUTPUT (0), OCTOPUS_MOMENT_CAPACITY (100)

The MESHSCAN receipt compares the emittances AFTER the run with the ones
BEFORE it (`_ele_i`, `_pro_i`, the turn-0 row of the TSV); until 2026-10-20
both sides were evaluated on the final state, so its four growth percentages
were 0.0 by construction (comprehensive audit 2026-10-18, F-237), and its
`damp=` field printed an environment variable nothing read. The moment schedule
runs for the whole run (no `stop`); it used to stop at a hard-coded 50000
turns under a configurable run length (F-239).

Outputs: result/<EIC_TAG>.h5 (the run artifact: /luminosity/ip,
/moments/electron, /moments/proton, /execution) and the two-row emittance TSV
at EIC_EMIT_OUT.

The gate's CUDA arm runs this benchmark at a reduced size (the testset
"CUDA-requiring validation scripts run in the gate's CUDA arm" in
test/runtests.jl reads the line below; validation/README.md):

GATE-CUDA-ARM: env OCTOPUS_USE_GPU=1 OCTOPUS_TURNS=2 OCTOPUS_N_MACRO=2000 EIC_TAG=cuda_arm_gate EIC_EMIT_OUT=@TMP@/eic_emit.tsv ; verdict "MESHSCAN " ; outputs result/cuda_arm_gate.h5
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

"""
Parse a boolean switch, rejecting anything it does not recognise: the
strong-strong harness's one grammar (its U21-15/U21-16 fix), which this copy
did not receive until 2026-10-20 -- `OCTOPUS_USE_GPU` was read as `== "1"`
beside the `in ("1", "true", ...)` grammar of every other switch, so
`OCTOPUS_USE_GPU=true` ran on the CPU (comprehensive audit 2026-10-18, F-239).
"""
function env_bool(key::AbstractString, default::Bool)
    raw = get(ENV, key, default ? "1" : "0")
    lowered = lowercase(strip(raw))
    lowered in ("1", "true", "yes", "on") && return true
    lowered in ("0", "false", "no", "off") && return false
    error("$(key)=$(repr(raw)) is not a boolean; use 1/0, true/false, yes/no or on/off")
end

# The header's variable list against what this file reads, so the two cannot
# drift (the pattern of profiling/benchmark_strong_strong_pic.jl; this file's
# header described another file until 2026-10-20, F-239). The header is the
# text above the first `=#`; a name is read when the body spells it as a string
# literal. A glob leaves a token ending in `_`, which is ignored.
let text = read(@__FILE__, String)
    header, body = split(text, "=#"; limit=2)
    names(s, pattern) = Set(String(m.captures[1]) for m in eachmatch(pattern, s)
                            if !endswith(m.captures[1], "_"))
    named = names(header, r"\b((?:OCTOPUS|EIC|SST)_[A-Z0-9_]+)")
    read_names = names(body, r"\"((?:OCTOPUS|EIC|SST)_[A-Z0-9_]+)\"")
    named == read_names || error("header drift: named but never read " *
        string(sort!(collect(setdiff(named, read_names)))) * "; read but not named " *
        string(sort!(collect(setdiff(read_names, named)))))
end

input = (
    case_name = "pic_hcc",
    result_dir = joinpath(@__DIR__, "..", "result"),
    seed = parse(Int, get(ENV, "SST_SEED", "1")),
    default_demo_macroparticles = 200,
    crossing_angle = 0.0,

    electron = (
        charge = -1.0,
        mass = EMASS_EV,
        energy = 10.0e9,
        n_particle = 1.7203e11,
        n_macro = 2560000,
        cutoff = 5.0,
        sigma = (106.0e-6, 9.5e-6, 0.7e-2),
        beta = (0.55, 0.056, 0.7e-2 / 5.5e-4),
        alpha = (0.0, 0.0, 0.0),
        crab_beta = (150.0, 30.0, 0.7e-2 / 5.5e-4),
        tune = (0.08, 0.14, -0.069),
        chromaticity = (0.0, 0.0),
        crab_frequency = 394.0e6,
        crab_strength_x = (0.0, 0.0, 0.0),
        crab_strength_y = (0.0, 0.0, 0.0),
        crab_phase = (0.0, 0.0, 0.0),
        radiation_damping_turns = (400.0, 400.0, 200.0),
    ),

    proton = (
        charge = 1.0,
        mass = PMASS_EV,
        energy = 275.0e9,
        n_particle = 0.6881e11,
        n_macro = 1024000,
        cutoff = 5.0,
        sigma = (95.0e-6, 8.5e-6, 6.0e-2),
        beta = (0.8, 0.072, 6.0e-2 / 6.6e-4),
        alpha = (0.0, 0.0, 0.0),
        crab_beta = (1300.0, 30.0, 6.0e-2 / 6.6e-4),
        tune = (0.228, 0.210, -0.01),
        chromaticity = (0.0, 0.0),
        crab_frequency = 197.0e6,
        crab_strength_x = (0.0, 0.0, 0.0),
        crab_strength_y = (0.0, 0.0, 0.0),
        crab_phase = (0.0, 0.0, 0.0),
    ),

    slicing = (
        zslice = 15,
        center = :centroid,
    ),

    solver = (
        pic_grid = (parse(Int, get(ENV, "SST_GRID", "128")), parse(Int, get(ENV, "SST_GRID", "128"))),
        pic_deposit_method = :CIC,
        pic_luminosity_deposit_method = nothing,
        pic_green_type = :integrated,
        pic_slice_pair_green_min_ratio = 0.50,
        pic_slice_pair_green_growth = 0.25,
        min_sigma = 1.0e-12,
        luminosity_scale = nothing,
    ),

    output = (
        artifact_file = get(ENV, "EIC_TAG", "pic_hcc") * ".h5",
        moment_start = 0,
        moment_step = parse(Int, get(ENV, "EIC_MOMENT_STEP", "1")),
        capacity = 100,   # the ARTIFACT'S: one batching knob for every producer
    ),
)

turns = parse(Int, get(ENV, "OCTOPUS_TURNS", "2"))
common_n_macro = get(ENV, "OCTOPUS_N_MACRO", "")
n_macro_ele = parse(Int, get(ENV, "OCTOPUS_N_MACRO_ELE",
                             isempty(common_n_macro) ? string(input.default_demo_macroparticles) : common_n_macro))
n_macro_pro = parse(Int, get(ENV, "OCTOPUS_N_MACRO_PRO",
                             isempty(common_n_macro) ? string(input.default_demo_macroparticles) : common_n_macro))

use_gpu = env_bool("OCTOPUS_USE_GPU", false)
if use_gpu
    import CUDA
    CUDA.functional(false) || error("OCTOPUS_USE_GPU=1 requested, but CUDA.functional(false) is false.")
end
policy = if use_gpu
    cuda_device_env = get(ENV, "OCTOPUS_CUDA_DEVICE", "")
    cuda_device = isempty(cuda_device_env) ? nothing : parse(Int, cuda_device_env)
    cuda_threads = parse(Int, get(ENV, "OCTOPUS_CUDA_THREADS", "256"))
    cuda_blocks_text = lowercase(get(ENV, "OCTOPUS_CUDA_BLOCKS", "auto"))
    cuda_blocks = cuda_blocks_text == "auto" ? :auto : parse(Int, cuda_blocks_text)
    CUDAExecutionPolicy(device = cuda_device,
        launch = CUDALaunchConfig(threads = cuda_threads, blocks = cuda_blocks))
else
    cpu_threads_text = lowercase(get(ENV, "OCTOPUS_CPU_THREADS", "auto"))
    cpu_threads = cpu_threads_text == "auto" ? :auto : parse(Int, cpu_threads_text)
    CPUThreadsExecutionPolicy(threads = cpu_threads)
end
set_global_rng!(seed = input.seed, method = :philox)

ele = input.electron
pro = input.proton
weak_strong_limit = env_bool("OCTOPUS_WEAK_STRONG_LIMIT", false)
electron_energy = if haskey(ENV, "OCTOPUS_ELECTRON_ENERGY_GEV")
    parse(Float64, ENV["OCTOPUS_ELECTRON_ENERGY_GEV"]) * 1.0e9
elseif weak_strong_limit
    1.0e100 * 1.0e9
else
    ele.energy
end
proton_energy = haskey(ENV, "OCTOPUS_PROTON_ENERGY_GEV") ?
    parse(Float64, ENV["OCTOPUS_PROTON_ENERGY_GEV"]) * 1.0e9 :
    pro.energy

beam_ele = Beam(n_macro_ele, policy, Float64;
    beta = ele.beta,
    alpha = ele.alpha,
    sigma = ele.sigma,
    cutoff = ele.cutoff,
    rng_id = 1,
    charge = ele.charge,
    mc2 = ele.mass,
    E0 = electron_energy,
    r0 = RE * ME0 / ele.mass,
    npart = ele.n_particle,
)

beam_pro = Beam(n_macro_pro, policy, Float64;
    beta = pro.beta,
    alpha = pro.alpha,
    sigma = pro.sigma,
    cutoff = pro.cutoff,
    rng_id = 2,
    charge = pro.charge,
    mc2 = pro.mass,
    E0 = proton_energy,
    r0 = RE * ME0 / pro.mass,
    npart = pro.n_particle,
)

eltype(beam_ele.rep.x) === Float64 || error("electron beam tracking arrays must be Float64")
eltype(beam_pro.rep.x) === Float64 || error("proton beam tracking arrays must be Float64")

slicing = LongitudinalSlicing(;
    method = :normal_quantile,
    nslices = input.slicing.zslice,
    center_position = input.slicing.center,
)

pic_green_cache = Symbol(lowercase(get(ENV, "OCTOPUS_PIC_GREEN_CACHE", "slice_pair")))
pic_slice_pair_green_min_ratio = parse(Float64, get(ENV, "OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO",
                                                    get(ENV, "OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO",
                                                        string(input.solver.pic_slice_pair_green_min_ratio))))
pic_slice_pair_green_growth = parse(Float64, get(ENV, "OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH",
                                                 get(ENV, "OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_GROWTH",
                                                     string(input.solver.pic_slice_pair_green_growth))))
pic_longitudinal_kick = env_bool("OCTOPUS_PIC_LONGITUDINAL_KICK", true)
pic_batch_mode = Symbol(lowercase(get(ENV, "OCTOPUS_PIC_BATCH_MODE", "wavefront")))
cuda_pic_async = env_bool("OCTOPUS_CUDA_PIC_ASYNC", true)
cuda_pic_batch_fft = env_bool("OCTOPUS_CUDA_PIC_BATCH_FFT", true)
cuda_pic_wavefront_fft = env_bool("OCTOPUS_CUDA_PIC_WAVEFRONT_FFT", true)
cuda_pic_indexed_wavefront = env_bool("OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT", true)
pic_luminosity_every = parse(Int, get(ENV, "OCTOPUS_PIC_LUMINOSITY_EVERY", "1"))
pic_luminosity_grid = if haskey(ENV, "OCTOPUS_PIC_LUMINOSITY_GRID")
    values = parse.(Int, split(ENV["OCTOPUS_PIC_LUMINOSITY_GRID"], ','))
    length(values) == 2 || error("OCTOPUS_PIC_LUMINOSITY_GRID must be nx,ny")
    (values[1], values[2])
else
    nothing
end
pic_luminosity_deposit_method = if haskey(ENV, "OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD")
    value = uppercase(ENV["OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD"])
    value == "INHERIT" ? nothing : Symbol(value)
else
    input.solver.pic_luminosity_deposit_method
end
pic_luminosity_schedule =
    pic_luminosity_every < 0 ? error("OCTOPUS_PIC_LUMINOSITY_EVERY must be >= 0") :
    pic_luminosity_every == 0 ? AtTurns(Int[]) :
    pic_luminosity_every == 1 ? nothing :
    EveryNSteps(step = pic_luminosity_every)
record_turn_times = env_bool("OCTOPUS_RECORD_TURN_TIMES", false)
diagnostics = StrongStrongDiagnostics(;
    record_turn_times,
    memory_log_every = parse(Int, get(ENV, "OCTOPUS_CUDA_MEMORY_LOG_EVERY", "0")),
    pic_timing = env_bool("OCTOPUS_CUDA_PIC_TIMING", false),
    pic_timing_detail = env_bool("OCTOPUS_CUDA_PIC_TIMING_DETAIL", false),
    cache_stats = env_bool("OCTOPUS_PIC_CACHE_STATS", false),
    nvtx = env_bool("OCTOPUS_CUDA_NVTX", false),
)
disable_moments = env_bool("OCTOPUS_DISABLE_MOMENTS", false)
disable_luminosity_output = env_bool("OCTOPUS_DISABLE_LUMINOSITY_OUTPUT", false)
disable_collision = env_bool("OCTOPUS_DISABLE_COLLISION", false)
# OCTOPUS_MOMENT_CAPACITY sets the ARTIFACT capacity; 0 keeps its harness
# meaning of "disable moment output" (the library capacity=0 spelling
# retired with the per-observer capacity, 2026-08-18).
moment_capacity = parse(Int, get(ENV, "OCTOPUS_MOMENT_CAPACITY",
                                 string(input.output.capacity)))
disable_moments = disable_moments || moment_capacity == 0
artifact_capacity = moment_capacity > 0 ? moment_capacity : input.output.capacity
optional_cuda_pic_threads(key) = haskey(ENV, key) ? parse(Int, ENV[key]) : nothing
cuda_pic_launch = CUDAPICLaunchConfig(
    gather_scatter_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_GATHER_SCATTER_THREADS"),
    deposition_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_DEPOSITION_THREADS"),
    kick_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_KICK_THREADS"),
    field_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_FIELD_THREADS"),
    spectral_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_SPECTRAL_THREADS"),
    green_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_GREEN_THREADS"),
    luminosity_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_LUMINOSITY_THREADS"),
)
cuda_pic_backend_configurations = use_gpu ? (cuda_pic_launch,) : ()
# PIC is the default solver. To use the soft-Gaussian solver instead, comment
# out the PICPoissonSolver construction below and uncomment this block. It
# replaces the grid PIC field solve with sliced Gaussian moments and a
# closed-form Bassetti-Erskine kick; see docs/theory/beam_beam_longitudinal_kick.md.
#
# solver = GaussianPoissonSolver(;
#     slicing = slicing,
#     min_sigma = input.solver.min_sigma,
#     luminosity_scale = input.solver.luminosity_scale,
#     longitudinal_kick = true,
#     virtual_drift = :hirata,      # :hirata, :chromatic, or :exact
#     include_sigma_xy = false,     # true for the full coupled transverse covariance
#     batch_mode = :wavefront,      # :wavefront or :sequential
# )
#
# Or the spectral sine-series solver (Dirichlet box + DST/DCT field solve). The
# grid follows N_thin ~ 5*domain_factor*sigma_x/sigma_y for flat beams (see
# docs/theory/spectral_sine_poisson_solver.md). With `longitudinal_kick=true` it applies
# the same synchro-beam drift and potential-difference pz structure as the PIC
# path. CUDA supports method=:grid only; method=:grid_free is CPU-only.
#
# Recommended CUDA production setting for the ~11:1 flat beams: grid=(127, 383),
# domain_factor=8. This matches the analytic/PIC kick to ~1% (both beams, all of
# x/y/z) and is ~6x faster than grid=(128,1024)/16 on GPU. Through the full example
# beamline at the production case it is ~1.5x the PIC solver (0.46 vs 0.31 s/turn on
# an RTX 4500 Ada), comparable but not at parity. The odd sizes are deliberate: a grid dimension
# N gives a DST/DCT extension of length 2(N+1), so N = 2^k-1 (127, 383, 511, ...)
# makes that a power of two and the CUDA real-FFT optimal. See the optimization
# history for the CPU/CUDA performance campaign.
#
# solver = SpectralPoissonSolver(;
#     slicing = slicing,
#     luminosity_scale = input.solver.luminosity_scale,
#     grid = (127, 383),            # ~11:1 flat production beams; (127,127) for round
#     domain_factor = 8.0,
#     method = :grid,               # :grid (fast, CUDA) or :grid_free (CPU only)
#     longitudinal_kick = true,
# )

# Solver selection via OCTOPUS_SOLVER (pic | spectral | gaussian | gaussian_pic);
# defaults to pic. An unrecognized name is an error rather than a silent fallback.
# The spectral grid/domain_factor can be overridden with OCTOPUS_SPECTRAL_GRID
# ("nx,ny") and OCTOPUS_SPECTRAL_DOMAIN_FACTOR for A/B benchmarking; the
# Gaussian-subtracted PIC grid with OCTOPUS_GPIC_GRID ("nx,ny").
solver_name = lowercase(get(ENV, "OCTOPUS_SOLVER", "pic"))
solver_name in ("pic", "spectral", "gaussian", "gaussian_pic") || error(
    "OCTOPUS_SOLVER must be one of pic, spectral, gaussian, gaussian_pic; got $(repr(solver_name))")
spectral_grid = let v = get(ENV, "OCTOPUS_SPECTRAL_GRID", "127,383")
    parts = parse.(Int, split(v, ',')); (parts[1], parts[2])
end
spectral_domain_factor = parse(Float64, get(ENV, "OCTOPUS_SPECTRAL_DOMAIN_FACTOR", "8.0"))
spectral_field_precision = Symbol(lowercase(get(ENV, "OCTOPUS_SPECTRAL_FIELD_PRECISION", "double")))
gpic_grid = let v = get(ENV, "OCTOPUS_GPIC_GRID", "64,64")
    parts = parse.(Int, split(v, ',')); (parts[1], parts[2])
end

solver = if solver_name == "spectral"
    SpectralPoissonSolver(;
        slicing = slicing,
        luminosity_scale = input.solver.luminosity_scale,
        grid = spectral_grid,
        domain_factor = spectral_domain_factor,
        method = :grid,
        field_precision = spectral_field_precision,
        longitudinal_kick = pic_longitudinal_kick,
        # The solvers' one schedule keyword (2026-09-04); the spectral 6D loop
        # reads it on CPU, the CUDA route records that it has one schedule.
        batch_mode = pic_batch_mode,
    )
elseif solver_name == "gaussian"
    GaussianPoissonSolver(;
        slicing = slicing,
        min_sigma = input.solver.min_sigma,
        luminosity_scale = input.solver.luminosity_scale,
        longitudinal_kick = pic_longitudinal_kick,
        batch_mode = pic_batch_mode,
    )
elseif solver_name == "gaussian_pic"
    GaussianPICPoissonSolver(;
        slicing = slicing,
        luminosity_scale = input.solver.luminosity_scale,
        grid = gpic_grid,
        deposit_method = input.solver.pic_deposit_method,
        green_type = input.solver.pic_green_type,
        green_cache = pic_green_cache,
        longitudinal_kick = pic_longitudinal_kick,
        batch_mode = pic_batch_mode,
        cuda_async = cuda_pic_async,
        cuda_batch_fft = cuda_pic_batch_fft,
        cuda_wavefront_fft = cuda_pic_wavefront_fft,
        cuda_indexed_wavefront = cuda_pic_indexed_wavefront,
        luminosity_schedule = pic_luminosity_schedule,
        backend_configurations = cuda_pic_backend_configurations,
    )
else
    PICPoissonSolver(;
        slicing = slicing,
        luminosity_scale = input.solver.luminosity_scale,
        grid = input.solver.pic_grid,
        deposit_method = input.solver.pic_deposit_method,
        green_type = input.solver.pic_green_type,
        green_cache = pic_green_cache,
        slice_pair_green_min_ratio = pic_slice_pair_green_min_ratio,
        slice_pair_green_growth = pic_slice_pair_green_growth,
        longitudinal_kick = pic_longitudinal_kick,
        batch_mode = pic_batch_mode,
        cuda_async = cuda_pic_async,
        cuda_batch_fft = cuda_pic_batch_fft,
        cuda_wavefront_fft = cuda_pic_wavefront_fft,
        cuda_indexed_wavefront = cuda_pic_indexed_wavefront,
        luminosity_schedule = pic_luminosity_schedule,
        luminosity_grid = pic_luminosity_grid,
        luminosity_deposit_method = pic_luminosity_deposit_method,
        backend_configurations = cuda_pic_backend_configurations,
    )
end

electron_tccb2ip = Linear6DSpec{Float64}(;
    beta1 = ele.crab_beta,
    beta2 = ele.beta,
    alpha1 = ele.alpha,
    alpha2 = ele.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
electron_tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(electron_tccb2ip))))

electron_ip2tcca = Linear6DSpec{Float64}(;
    beta1 = ele.beta,
    beta2 = ele.crab_beta,
    alpha1 = ele.alpha,
    alpha2 = ele.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
electron_ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(electron_ip2tcca))))

electron_tccb = ThinCrabCavitySpec{3}(ele.crab_frequency;
    strengthX = ele.crab_strength_x,
    strengthY = ele.crab_strength_y,
    phase = ele.crab_phase,
)
electron_tcca = ThinCrabCavitySpec{3}(ele.crab_frequency;
    strengthX = ele.crab_strength_x,
    strengthY = ele.crab_strength_y,
    phase = ele.crab_phase,
)

electron_one_turn = Linear6DSpec{Float64}(;
    beta1 = ele.beta,
    beta2 = ele.beta,
    alpha1 = ele.alpha,
    alpha2 = ele.alpha,
    dmu = 2pi .* ele.tune,
)
electron_chrom = ChromaticityKickSpec{Float64}(;
    xi = ele.chromaticity,
    beta = ele.beta,
    alpha = ele.alpha,
)
electron_rad = LumpedRadSpec{Float64}(;
    damping_turns = ele.radiation_damping_turns,
    beta = ele.beta,
    alpha = ele.alpha,
    sigma = ele.sigma,
    is_damping = true,
    is_excitation = true,
    rng_id = 3,
)

proton_tccb2ip = Linear6DSpec{Float64}(;
    beta1 = pro.crab_beta,
    beta2 = pro.beta,
    alpha1 = pro.alpha,
    alpha2 = pro.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
proton_tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(proton_tccb2ip))))

proton_ip2tcca = Linear6DSpec{Float64}(;
    beta1 = pro.beta,
    beta2 = pro.crab_beta,
    alpha1 = pro.alpha,
    alpha2 = pro.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
proton_ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(proton_ip2tcca))))

proton_tccb = ThinCrabCavitySpec{3}(pro.crab_frequency;
    strengthX = pro.crab_strength_x,
    strengthY = pro.crab_strength_y,
    phase = pro.crab_phase,
)
proton_tcca = ThinCrabCavitySpec{3}(pro.crab_frequency;
    strengthX = pro.crab_strength_x,
    strengthY = pro.crab_strength_y,
    phase = pro.crab_phase,
)

proton_one_turn = Linear6DSpec{Float64}(;
    beta1 = pro.beta,
    beta2 = pro.beta,
    alpha1 = pro.alpha,
    alpha2 = pro.alpha,
    dmu = 2pi .* pro.tune,
)
proton_chrom = ChromaticityKickSpec{Float64}(;
    xi = pro.chromaticity,
    beta = pro.beta,
    alpha = pro.alpha,
)

lb = LorentzBoostSpec(input.crossing_angle)
rlb = RevLorentzBoostSpec(input.crossing_angle)
ip = StrongStrongCollision(:ip; poisson_solver = solver)
collision_elements = disable_collision ? () : (ip,)

mkpath(input.result_dir)
artifact_path = joinpath(input.result_dir, input.output.artifact_file)
# No `stop`: the schedule covers the whole run, whatever OCTOPUS_TURNS says. It
# used to stop at a hard-coded `total_turns = 50000` while the run length came
# from the environment, so a longer run silently stopped recording moments
# (comprehensive audit 2026-10-18, F-239).
moment_schedule = EveryNSteps(;
    start = input.output.moment_start,
    step = input.output.moment_step,
)
electron_observers = disable_moments ? () : (
    ScheduledObserver(
        MomentObserver(; name = "electron"),
        moment_schedule,
    ),
)
proton_observers = disable_moments ? () : (
    ScheduledObserver(
        MomentObserver(; name = "proton"),
        moment_schedule,
    ),
)

line_ele = (
    electron_tccb2ip_inv,
    electron_tccb,
    electron_tccb2ip,
    lb,
    collision_elements...,
    rlb,
    electron_ip2tcca,
    electron_tcca,
    electron_ip2tcca_inv,
    electron_one_turn,
    electron_chrom,
    electron_rad,
    electron_observers...,
)

line_pro = (
    proton_tccb2ip_inv,
    proton_tccb,
    proton_tccb2ip,
    lb,
    collision_elements...,
    rlb,
    proton_ip2tcca,
    proton_tcca,
    proton_ip2tcca_inv,
    proton_one_turn,
    proton_chrom,
    proton_observers...,
)

# The moment views need the artifact, so it is dropped only when nothing
# needs it. With moments enabled, OCTOPUS_DISABLE_LUMINOSITY_OUTPUT cannot
# suppress the luminosity channel -- the collision writes it whenever it
# evaluates -- so that contradiction errors rather than writing silently.
disable_artifact = disable_luminosity_output && disable_moments
disable_luminosity_output && !disable_moments && !disable_collision && error(
    "OCTOPUS_DISABLE_LUMINOSITY_OUTPUT=1 cannot suppress the luminosity " *
    "channel while the artifact exists for the moment views; also set " *
    "OCTOPUS_DISABLE_MOMENTS=1 (or OCTOPUS_DISABLE_COLLISION=1).")
task = StrongStrongTask(line_ele, line_pro;
    artifact = disable_artifact ? nothing :
               RunArtifact(artifact_path; capacity = artifact_capacity),
    diagnostics,
)
function _emit(b)
    x = Array(b.rep.x); px = Array(b.rep.px)
    y = Array(b.rep.y); py = Array(b.rep.py)
    cx = x .- sum(x)/length(x); cpx = px .- sum(px)/length(px)
    cy = y .- sum(y)/length(y); cpy = py .- sum(py)/length(py)
    n = length(x)
    ex = sqrt(max(0.0, (sum(cx.^2)/n)*(sum(cpx.^2)/n) - (sum(cx.*cpx)/n)^2))
    ey = sqrt(max(0.0, (sum(cy.^2)/n)*(sum(cpy.^2)/n) - (sum(cy.*cpy)/n)^2))
    return (ex, ey)
end
# NOTE: this MUST be a single multi-turn execute! call.  Calling
# execute!(...; turns=1) in a loop restarts the task's turn counter, so the
# counter-based (Philox) stochastic stream -- keyed by (seed, turn, stream,
# particle, component) -- replays the SAME normal variates every turn.  The
# radiation excitation then becomes a fixed per-particle kick instead of a
# random walk, and the beam equilibrates at amp/(1-lambda) rather than sigma
# (measured: <x^2> 795x the target over 2000 turns).  Per-turn sampling must go
# through the ScheduledObserver/MomentObserver hooks, which is what the moment
# observers attached to each beam line already do.
emit_path = get(ENV, "EIC_EMIT_OUT",
                joinpath(@__DIR__, "..", "result", "eic_emit_octopus_matched.tsv"))
_ele_i = _emit(beam_ele); _pro_i = _emit(beam_pro)
execute!(task, beam_ele, beam_pro; turns = turns)
open(emit_path, "w") do io
    println(io, "turn\tele_ex\tele_ey\tpro_ex\tpro_ey")
    println(io, 0, "\t", _ele_i[1], "\t", _ele_i[2], "\t", _pro_i[1], "\t", _pro_i[2])
    e = _emit(beam_ele); p = _emit(beam_pro)
    println(io, turns, "\t", e[1], "\t", e[2], "\t", p[1], "\t", p[2])
end
# Two states, not one: the "before" is the pre-run emittance (`_pro_i`,
# `_ele_i`, the TSV's turn-0 row), the "after" the final state. Both sides
# used to be evaluated after `execute!`, so every percentage was 0.0 by
# construction whatever the run did (comprehensive audit 2026-10-18, F-237);
# `damp=` printed `SST_DAMP`, a variable nothing read, and now prints the
# damping turns the electron line was built with.
_e1 = _emit(beam_pro)
_ele1 = _emit(beam_ele)
println("MESHSCAN seed=", input.seed, " grid=", input.solver.pic_grid[1],
        " damp=", ele.radiation_damping_turns, " turns=", turns,
        " pro_ex_growth_pct=", 100*(_e1[1]/_pro_i[1] - 1),
        " pro_ey_growth_pct=", 100*(_e1[2]/_pro_i[2] - 1),
        " ele_ex_growth_pct=", 100*(_ele1[1]/_ele_i[1] - 1),
        " ele_ey_growth_pct=", 100*(_ele1[2]/_ele_i[2] - 1))

if record_turn_times
    timings = turn_timings(task)
    println("turn_timings_seconds = ", join(timings, ','))
    timing_path = get(ENV, "OCTOPUS_TURN_TIMING_PATH", "")
    if !isempty(timing_path)
        mkpath(dirname(timing_path))
        open(timing_path, "w") do io
            println(io, "turn\tseconds")
            for (turn, seconds) in enumerate(timings)
                println(io, turn - 1, '\t', seconds)
            end
        end
    end
end

stats_ele = beam_statistics(beam_ele)
stats_pro = beam_statistics(beam_pro)
println("turns = ", turns)
println("n_macro_ele = ", n_macro_ele)
println("n_macro_pro = ", n_macro_pro)
println("poisson_solver = ", nameof(typeof(solver)))
println("beam_beam_collision = ", disable_collision ? "disabled" : "enabled")
println("weak_strong_limit = ", weak_strong_limit)
println("electron_energy_GeV = ", electron_energy / 1.0e9)
println("proton_energy_GeV = ", proton_energy / 1.0e9)
println("pic_longitudinal_kick = ", pic_longitudinal_kick)
println("pic_batch_mode = ", pic_batch_mode)
println("cuda_pic_async = ", cuda_pic_async)
println("cuda_pic_batch_fft = ", cuda_pic_batch_fft)
println("cuda_pic_wavefront_fft = ", cuda_pic_wavefront_fft)
println("cuda_pic_indexed_wavefront = ", cuda_pic_indexed_wavefront)
println("pic_green_cache = ", pic_green_cache)
println("pic_slice_pair_green_min_ratio = ", pic_slice_pair_green_min_ratio)
println("pic_slice_pair_green_growth = ", pic_slice_pair_green_growth)
println("pic_luminosity_every = ", pic_luminosity_every)
println("pic_luminosity_grid = ",
        pic_luminosity_grid === nothing ? input.solver.pic_grid : pic_luminosity_grid)
println("pic_luminosity_deposit_method = ",
        pic_luminosity_deposit_method === nothing ? "inherit" : pic_luminosity_deposit_method)
# Only the PIC-family solvers expose a resolved luminosity deposit method; the
# spectral and soft-Gaussian configurations have no such field.
let resolved = solver_configuration(solver)
    hasproperty(resolved, :resolved_luminosity_deposit_method) &&
        println("pic_luminosity_deposit_method_resolved = ",
                resolved.resolved_luminosity_deposit_method)
end
println("artifact = ", disable_artifact ? "disabled" : artifact_path)
println("electron moments = ", disable_moments ? "disabled" : "$(artifact_path):/moments/electron")
println("proton moments = ", disable_moments ? "disabled" : "$(artifact_path):/moments/proton")
println("electron rms = ", stats_ele.rms)
println("proton rms = ", stats_pro.rms)
