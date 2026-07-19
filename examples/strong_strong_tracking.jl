#=
Strong-strong tracking example with two live beams.

Run from the Octopus project root:

    julia --project=. examples/strong_strong_tracking.jl

This script is direct Julia construction of a realistic crab-crossing
electron-proton strong-strong case. The default run is intentionally small for
interactive testing. Use environment variables for larger runs:

    OCTOPUS_TURNS=100 OCTOPUS_N_MACRO_ELE=2560000 OCTOPUS_N_MACRO_PRO=1024000 julia --project=. examples/strong_strong_tracking.jl

Use CUDA for beam construction and tracking:

    OCTOPUS_USE_GPU=1 julia --project=. examples/strong_strong_tracking.jl

Select a CUDA device explicitly:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_DEVICE=1 julia --project=. examples/strong_strong_tracking.jl

Select the Poisson solver:

    OCTOPUS_POISSON_SOLVER=PIC julia --project=. examples/strong_strong_tracking.jl
    OCTOPUS_POISSON_SOLVER=gaussian julia --project=. examples/strong_strong_tracking.jl

Disable the beam-beam collision while retaining both complete ring lines:

    OCTOPUS_DISABLE_COLLISION=1 julia --project=. examples/strong_strong_tracking.jl

Control the PIC longitudinal potential-difference kick. It is enabled by default:

    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_LONGITUDINAL_KICK=1 julia --project=. examples/strong_strong_tracking.jl
    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_LONGITUDINAL_KICK=0 julia --project=. examples/strong_strong_tracking.jl

Select PIC slice-pair scheduling:

    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_BATCH_MODE=sequential julia --project=. examples/strong_strong_tracking.jl
    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_BATCH_MODE=wavefront julia --project=. examples/strong_strong_tracking.jl

Compute PIC luminosity every N turns. Use 0 to disable luminosity computation:

    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_LUMINOSITY_EVERY=10 julia --project=. examples/strong_strong_tracking.jl

The persistent slice-pair Green cache is the default for CPU and CUDA task
execution. Disable it to run an uncached reference comparison:

    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_GREEN_CACHE=slice_pair julia --project=. examples/strong_strong_tracking.jl
    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_GREEN_CACHE=none julia --project=. examples/strong_strong_tracking.jl

Tune the slice-pair Green cache. `GROWTH=0.20` builds cached
grids 1.20 times larger than the current request:

    OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_GREEN_CACHE=slice_pair OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO=0.50 OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH=0.20 julia --project=. examples/strong_strong_tracking.jl

Disable CUDA PIC asynchronous field solves for comparison:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_CUDA_PIC_ASYNC=0 julia --project=. examples/strong_strong_tracking.jl

Disable CUDA PIC batched FFT field solves for comparison:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_CUDA_PIC_BATCH_FFT=0 julia --project=. examples/strong_strong_tracking.jl

Disable CUDA PIC wavefront-level batched FFTs for comparison:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_BATCH_MODE=wavefront OCTOPUS_CUDA_PIC_WAVEFRONT_FFT=0 julia --project=. examples/strong_strong_tracking.jl

Print statistics for the default slice-pair Green cache:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_BATCH_MODE=wavefront OCTOPUS_PIC_GREEN_CACHE=slice_pair OCTOPUS_PIC_CACHE_STATS=1 julia --project=. examples/strong_strong_tracking.jl

Test the indexed CUDA wavefront path. It skips compact gather/scatter and
deposits/kicks through slice index vectors while leaving canonical particle
order unchanged:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_PIC_BATCH_MODE=wavefront OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=1 julia --project=. examples/strong_strong_tracking.jl

Log CUDA memory every N turns:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_MEMORY_LOG_EVERY=10 julia --project=. examples/strong_strong_tracking.jl

Print CUDA PIC phase timings:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_CUDA_PIC_TIMING=1 julia --project=. examples/strong_strong_tracking.jl

Record synchronized complete-turn timings and optionally write them as TSV:

    OCTOPUS_USE_GPU=1 OCTOPUS_RECORD_TURN_TIMES=1 OCTOPUS_TURN_TIMING_PATH=result/pic_turn_times.tsv julia --project=. examples/strong_strong_tracking.jl

Print additive field subphase timings. This disables async PIC field solves for
diagnosis:

    OCTOPUS_USE_GPU=1 OCTOPUS_POISSON_SOLVER=PIC OCTOPUS_CUDA_PIC_TIMING=1 OCTOPUS_CUDA_PIC_TIMING_DETAIL=1 julia --project=. examples/strong_strong_tracking.jl

Output is written to:

- `result/pic_hcc.lum`
- `result/pic_hcc.ele.h5`
- `result/pic_hcc.pro.h5`
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

input = (
    case_name = "pic_hcc",
    result_dir = joinpath(@__DIR__, "..", "result"),
    seed = 123456789,
    total_turns = 50000,
    default_demo_macroparticles = 200,
    crossing_angle = 12.5e-3,

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
        chromaticity = (1.0, 1.0),
        crab_frequency = 394.0e6,
        crab_strength_x = (tan(12.5e-3) / sqrt(150.0 * 0.55), 0.0, 0.0),
        crab_strength_y = (0.0, 0.0, 0.0),
        crab_phase = (0.0, 0.0, 0.0),
        radiation_damping_turns = (4000.0, 4000.0, 2000.0),
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
        chromaticity = (2.0, 2.0),
        crab_frequency = 197.0e6,
        crab_strength_x = (
            tan(12.5e-3) / sqrt(1300.0 * 0.8) * 4.0 / 3.0,
            -tan(12.5e-3) / sqrt(1300.0 * 0.8) / 3.0,
            0.0,
        ),
        crab_strength_y = (0.0, 0.0, 0.0),
        crab_phase = (0.0, 0.0, 0.0),
    ),

    slicing = (
        zslice = 15,
        center = :centroid,
    ),

    solver = (
        pic_grid = (128, 128),
        pic_deposit_method = :CIC,
        pic_green_type = :integrated,
        pic_slice_pair_green_min_ratio = 0.50,
        pic_slice_pair_green_growth = 0.25,
        min_sigma = 1.0e-12,
        luminosity_scale = nothing,
    ),

    output = (
        luminosity_file = "pic_hcc.lum",
        electron_moment_file = "pic_hcc.ele.h5",
        proton_moment_file = "pic_hcc.pro.h5",
        moment_start = 0,
        moment_step = 1,
        moment_capacity = 100,
    ),
)

turns = parse(Int, get(ENV, "OCTOPUS_TURNS", "2"))
common_n_macro = get(ENV, "OCTOPUS_N_MACRO", "")
n_macro_ele = parse(Int, get(ENV, "OCTOPUS_N_MACRO_ELE",
                             isempty(common_n_macro) ? string(input.default_demo_macroparticles) : common_n_macro))
n_macro_pro = parse(Int, get(ENV, "OCTOPUS_N_MACRO_PRO",
                             isempty(common_n_macro) ? string(input.default_demo_macroparticles) : common_n_macro))

use_gpu = get(ENV, "OCTOPUS_USE_GPU", "0") == "1"
if use_gpu
    import CUDA
    CUDA.functional(false) || error("OCTOPUS_USE_GPU=1 requested, but CUDA.functional(false) is false.")
end
policy = if use_gpu
    cuda_device_env = get(ENV, "OCTOPUS_CUDA_DEVICE", "")
    cuda_device = isempty(cuda_device_env) ? nothing : parse(Int, cuda_device_env)
    GPUExecutionPolicy(device = cuda_device)
else
    CPUThreadsExecutionPolicy()
end
set_global_rng!(seed = input.seed, method = :philox)

ele = input.electron
beam_ele = Beam(n_macro_ele, policy, Float64;
    beta = ele.beta,
    alpha = ele.alpha,
    sigma = ele.sigma,
    cutoff = ele.cutoff,
    rng_id = 1,
    charge = ele.charge,
    mc2 = ele.mass,
    E0 = ele.energy,
    r0 = RE * ME0 / ele.mass,
    npart = ele.n_particle,
)

pro = input.proton
beam_pro = Beam(n_macro_pro, policy, Float64;
    beta = pro.beta,
    alpha = pro.alpha,
    sigma = pro.sigma,
    cutoff = pro.cutoff,
    rng_id = 2,
    charge = pro.charge,
    mc2 = pro.mass,
    E0 = pro.energy,
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

solver_kind = lowercase(get(ENV, "OCTOPUS_POISSON_SOLVER", "PIC"))
pic_green_cache = Symbol(lowercase(get(ENV, "OCTOPUS_PIC_GREEN_CACHE", "slice_pair")))
pic_slice_pair_green_min_ratio = parse(Float64, get(ENV, "OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO",
                                                    get(ENV, "OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO",
                                                        string(input.solver.pic_slice_pair_green_min_ratio))))
pic_slice_pair_green_growth = parse(Float64, get(ENV, "OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH",
                                                 get(ENV, "OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_GROWTH",
                                                     string(input.solver.pic_slice_pair_green_growth))))
pic_longitudinal_kick = get(ENV, "OCTOPUS_PIC_LONGITUDINAL_KICK", "1") in ("1", "true", "TRUE", "yes", "YES")
pic_batch_mode = Symbol(lowercase(get(ENV, "OCTOPUS_PIC_BATCH_MODE", "wavefront")))
cuda_pic_async = get(ENV, "OCTOPUS_CUDA_PIC_ASYNC", "1") in ("1", "true", "TRUE", "yes", "YES")
cuda_pic_batch_fft = get(ENV, "OCTOPUS_CUDA_PIC_BATCH_FFT", "1") in ("1", "true", "TRUE", "yes", "YES")
cuda_pic_wavefront_fft = get(ENV, "OCTOPUS_CUDA_PIC_WAVEFRONT_FFT", "1") in ("1", "true", "TRUE", "yes", "YES")
cuda_pic_indexed_wavefront = get(ENV, "OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT", "1") in ("1", "true", "TRUE", "yes", "YES")
pic_luminosity_every = parse(Int, get(ENV, "OCTOPUS_PIC_LUMINOSITY_EVERY", "1"))
pic_luminosity_grid = if haskey(ENV, "OCTOPUS_PIC_LUMINOSITY_GRID")
    values = parse.(Int, split(ENV["OCTOPUS_PIC_LUMINOSITY_GRID"], ','))
    length(values) == 2 || error("OCTOPUS_PIC_LUMINOSITY_GRID must be nx,ny")
    (values[1], values[2])
else
    nothing
end
pic_luminosity_schedule =
    pic_luminosity_every < 0 ? error("OCTOPUS_PIC_LUMINOSITY_EVERY must be >= 0") :
    pic_luminosity_every == 0 ? AtTurns(Int[]) :
    pic_luminosity_every == 1 ? nothing :
    EveryNSteps(step = pic_luminosity_every)
record_turn_times = get(ENV, "OCTOPUS_RECORD_TURN_TIMES", "0") in
                    ("1", "true", "TRUE", "yes", "YES")
diagnostics = StrongStrongDiagnostics(;
    record_turn_times,
    memory_log_every = parse(Int, get(ENV, "OCTOPUS_CUDA_MEMORY_LOG_EVERY", "0")),
    pic_timing = get(ENV, "OCTOPUS_CUDA_PIC_TIMING", "0") in
                 ("1", "true", "TRUE", "yes", "YES"),
    pic_timing_detail = get(ENV, "OCTOPUS_CUDA_PIC_TIMING_DETAIL", "0") in
                        ("1", "true", "TRUE", "yes", "YES"),
    cache_stats = get(ENV, "OCTOPUS_PIC_CACHE_STATS", "0") in
                  ("1", "true", "TRUE", "yes", "YES"),
    nvtx = get(ENV, "OCTOPUS_CUDA_NVTX", "0") in
           ("1", "true", "TRUE", "yes", "YES"),
)
disable_moments = get(ENV, "OCTOPUS_DISABLE_MOMENTS", "0") in
                  ("1", "true", "TRUE", "yes", "YES")
disable_luminosity_output = get(ENV, "OCTOPUS_DISABLE_LUMINOSITY_OUTPUT", "0") in
                            ("1", "true", "TRUE", "yes", "YES")
disable_collision = get(ENV, "OCTOPUS_DISABLE_COLLISION", "0") in
                    ("1", "true", "TRUE", "yes", "YES")
moment_capacity = parse(Int, get(ENV, "OCTOPUS_MOMENT_CAPACITY",
                                 string(input.output.moment_capacity)))
solver = if solver_kind == "gaussian"
    GaussianPoissonSolver(;
        slicing = slicing,
        min_sigma = input.solver.min_sigma,
        luminosity_scale = input.solver.luminosity_scale,
    )
elseif solver_kind == "pic"
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
    )
else
    error("unknown OCTOPUS_POISSON_SOLVER=$(solver_kind); use gaussian or PIC")
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
luminosity_path = joinpath(input.result_dir, input.output.luminosity_file)
electron_moment_path = joinpath(input.result_dir, input.output.electron_moment_file)
proton_moment_path = joinpath(input.result_dir, input.output.proton_moment_file)
moment_schedule = EveryNSteps(;
    start = input.output.moment_start,
    stop = input.total_turns,
    step = input.output.moment_step,
)
electron_observers = disable_moments ? () : (
    ScheduledObserver(
        MomentObserver(electron_moment_path; capacity = moment_capacity),
        moment_schedule,
    ),
)
proton_observers = disable_moments ? () : (
    ScheduledObserver(
        MomentObserver(proton_moment_path; capacity = moment_capacity),
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

task = StrongStrongTask(line_ele, line_pro;
    luminosity_path = disable_luminosity_output ? nothing : luminosity_path,
    diagnostics,
)
execute!(task, beam_ele, beam_pro; turns = turns)

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
println("poisson_solver = ", solver_kind)
println("beam_beam_collision = ", disable_collision ? "disabled" : "enabled")
if solver_kind == "pic"
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
end
println("luminosity = ", disable_luminosity_output ? "disabled" : luminosity_path)
println("electron moments = ", disable_moments ? "disabled" : electron_moment_path)
println("proton moments = ", disable_moments ? "disabled" : proton_moment_path)
println("electron rms = ", stats_ele.rms)
println("proton rms = ", stats_pro.rms)
