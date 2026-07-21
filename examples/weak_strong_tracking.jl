using LinearAlgebra

#=
Weak-strong tracking example with crab crossing.

Run from the Octopus project root:

    julia --project=. examples/weak_strong_tracking.jl

The default run is intentionally small: 2 turns and 10000 macroparticles. Use
environment variables for larger runs without editing the physics input:

    OCTOPUS_TURNS=1000 OCTOPUS_N_MACRO=1024000 julia --project=. examples/weak_strong_tracking.jl

Run the same example with CUDA storage and CUDA tracking kernels:

    OCTOPUS_USE_GPU=1 julia --project=. examples/weak_strong_tracking.jl

Select a CUDA device explicitly:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_DEVICE=1 julia --project=. examples/weak_strong_tracking.jl

CUDA checks:

    julia --project=. -e 'using CUDA; println(CUDA.functional()); println(CUDA.has_cuda_gpu())'
    julia --project=. -e 'using CUDA; CUDA.versioninfo()'

This file is meant to be a concise precedent for realistic weak-strong tracking:

1. Define one `input` named tuple with beam, optics, element, and output
   settings.
2. Construct the weak beam directly from the input, including the initial
   offset.
3. Construct element specs in tracking order.
4. Place observers/actions in the line when their location matters.
5. Build `TrackingTask(line)` and execute it with `execute!`.

Outputs are written to `result/`:

- `weak_strong.lum`: turn and luminosity values.
- `weak_strong_moments.h5`: scheduled first- and second-order moments written
  by `MomentObserver`.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

# Input for this weak-proton crab-crossing case.
# Set OCTOPUS_TURNS and OCTOPUS_N_MACRO in the shell to run a smaller or larger
# job without editing the physics input below.
input = (
    case_name = "weak_strong",
    result_dir = joinpath(@__DIR__, "..", "result"),
    seed = 123456789,
    total_turns = 1_000_000,

    weak_beam = (
        charge = 1.0,
        mass = PMASS_EV,
        energy = 275.0e9,
        n_particle = 0.6881e11,
        n_macro = 1_024_000,
        cutoff = 5.0,
        sigx = 95.0e-6,
        sigy = 8.5e-6,
        sigz = 6.0e-2,
        sigd = 6.6e-4,
        beta_x = 0.8,
        beta_y = 0.072,
        alpha = (0.0, 0.0, 0.0),
        zeta = (0.0, 0.0, 0.0, 0.0),
        eta = (0.0, 0.0, 0.0, 0.0),
        coupling = (0.0, 0.0, 0.0, 0.0),
        initial_offset = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
    ),

    optics = (
        crab_beta_x = 1300.0,
        crab_beta_y = 100.0,
        crossing_angle = 12.5e-3,
        tune = (0.228, 0.210, -0.01),
        chromaticity = (2.0, 2.0),
    ),

    crab_cavity = (
        frequency = 197.0e6,
        strength_y = (0.0, 0.0, 0.0),
        phase = (0.0, 0.0, 0.0),
    ),

    strong_beam = (
        charge = -1.0,
        n_particle = 1.7203e11,
        sigma = (95.0e-6, 8.5e-6, 0.7e-2),
        beta = (0.55, 0.056),
        alpha = (0.0, 0.0),
        z_slices = 7,
        slice_method = :equal_area,
        center = (0.0, 0.0, 0.0),
        angle = (0.0, 0.0, 0.0),
        curvature = (0.0, 0.0, 0.0),
        dynamic_drift_flag = 0,
        size_signal = nothing,
        centroid_signal = nothing,
        angle_signal = nothing,
        hvoffset = nothing,
    ),

    radiation = (
        damping_turns = (1.0e100, 1.0e100, 1.0e100),
        is_damping = false,
        is_excitation = true,
        alpha = (0.0, 0.0, 0.0),
        zeta = (0.0, 0.0, 0.0, 0.0),
        eta = (0.0, 0.0, 0.0, 0.0),
        coupling = (0.0, 0.0, 0.0, 0.0),
    ),

    output = (
        luminosity_file = "weak_strong.lum",
        moment_file = "weak_strong_moments.h5",
        moment_start = 0,
        moment_step = 1,
        moment_stop = 1_000_000,
        moment_capacity = 100,
    ),
)

turns = parse(Int, get(ENV, "OCTOPUS_TURNS", "2"))
n_macro = parse(Int, get(ENV, "OCTOPUS_N_MACRO", "10000"))

# Execution policy used for beam construction. Tasks infer the backend from the
# beam storage at execution time.
# CPU threads are the portable default. Set OCTOPUS_USE_GPU=1 to use CUDA.
# Observers still write on the host and may synchronize GPU data when scheduled.
use_gpu = get(ENV, "OCTOPUS_USE_GPU", "0") == "1"
if use_gpu
    import CUDA
    CUDA.functional(false) || error("OCTOPUS_USE_GPU=1 requested, but CUDA.functional(false) is false.")
end
policy = if use_gpu
    cuda_device_env = get(ENV, "OCTOPUS_CUDA_DEVICE", "")
    cuda_device = isempty(cuda_device_env) ? nothing : parse(Int, cuda_device_env)
    CUDAExecutionPolicy(device = cuda_device)
else
    CPUThreadsExecutionPolicy()
end
set_global_rng!(seed = input.seed, method = :philox)

wb = input.weak_beam
beta_z = wb.sigz / wb.sigd
emit = (wb.sigx^2 / wb.beta_x, wb.sigy^2 / wb.beta_y, wb.sigz * wb.sigd)
weak_r0 = RE * ME0 / wb.mass

beam = Beam(n_macro, policy, Float64;
    beta = (wb.beta_x, wb.beta_y, beta_z),
    alpha = wb.alpha,
    emit = emit,
    cutoff = wb.cutoff,
    rng_id = 1,
    charge = wb.charge,
    mc2 = wb.mass,
    E0 = wb.energy,
    r0 = weak_r0,
    npart = wb.n_particle,
    zeta = wb.zeta,
    eta = wb.eta,
    R = wb.coupling,
    initial_offset = wb.initial_offset,
)

opt = input.optics
cckick = tan(opt.crossing_angle) / sqrt(wb.beta_x * opt.crab_beta_x)
cc_strength_x = (cckick * 4.0 / 3.0, -cckick / 3.0, 0.0)

tccb2ip = Linear6DSpec{Float64}(;
    beta1 = (opt.crab_beta_x, opt.crab_beta_y, beta_z),
    beta2 = (wb.beta_x, wb.beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0),
    alpha2 = (0.0, 0.0, 0.0),
    dmu = (pi / 2.0, 0.0, 0.0),
    zeta1 = (0.0, 0.0, 0.0, 0.0),
    eta1 = (0.0, 0.0, 0.0, 0.0),
    R1 = (0.0, 0.0, 0.0, 0.0),
    zeta2 = (0.0, 0.0, 0.0, 0.0),
    eta2 = (0.0, 0.0, 0.0, 0.0),
    R2 = (0.0, 0.0, 0.0, 0.0),
)
tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(tccb2ip))))

ip2tcca = Linear6DSpec{Float64}(;
    beta1 = (wb.beta_x, wb.beta_y, beta_z),
    beta2 = (opt.crab_beta_x, opt.crab_beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0),
    alpha2 = (0.0, 0.0, 0.0),
    dmu = (pi / 2.0, 0.0, 0.0),
    zeta1 = (0.0, 0.0, 0.0, 0.0),
    eta1 = (0.0, 0.0, 0.0, 0.0),
    R1 = (0.0, 0.0, 0.0, 0.0),
    zeta2 = (0.0, 0.0, 0.0, 0.0),
    eta2 = (0.0, 0.0, 0.0, 0.0),
    R2 = (0.0, 0.0, 0.0, 0.0),
)
ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(ip2tcca))))

tccb = ThinCrabCavitySpec{3}(input.crab_cavity.frequency;
    strengthX = cc_strength_x,
    strengthY = input.crab_cavity.strength_y,
    phase = input.crab_cavity.phase,
)
tcca = ThinCrabCavitySpec{3}(input.crab_cavity.frequency;
    strengthX = cc_strength_x,
    strengthY = input.crab_cavity.strength_y,
    phase = input.crab_cavity.phase,
)

one_turn = Linear6DSpec{Float64}(;
    beta1 = (wb.beta_x, wb.beta_y, beta_z),
    beta2 = (wb.beta_x, wb.beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0),
    alpha2 = (0.0, 0.0, 0.0),
    dmu = (2pi * opt.tune[1], 2pi * opt.tune[2], 2pi * opt.tune[3]),
    zeta1 = (0.0, 0.0, 0.0, 0.0),
    eta1 = (0.0, 0.0, 0.0, 0.0),
    R1 = (0.0, 0.0, 0.0, 0.0),
    zeta2 = (0.0, 0.0, 0.0, 0.0),
    eta2 = (0.0, 0.0, 0.0, 0.0),
    R2 = (0.0, 0.0, 0.0, 0.0),
)

chrom = ChromaticityKickSpec{Float64}(;
    xi = opt.chromaticity,
    beta = (wb.beta_x, wb.beta_y, beta_z),
    alpha = wb.alpha,
    zeta = (0.0, 0.0, 0.0, 0.0),
    eta = (0.0, 0.0, 0.0, 0.0),
    R = (0.0, 0.0, 0.0, 0.0),
)

strong = input.strong_beam
kbb = wb.charge * strong.charge * strong.n_particle * weak_r0 * wb.mass / wb.energy
klum = strong.n_particle * wb.n_particle / n_macro
thin_strong = ThinStrongBeamSpec{Float64}(;
    kbb = kbb,
    klum = klum,
    beta = strong.beta,
    alpha = strong.alpha,
    sigma = (strong.sigma[1], strong.sigma[2]),
    center = strong.center,
    angle = strong.angle,
    curvature = strong.curvature,
    dynamic_drift_flag = strong.dynamic_drift_flag,
    size_signal = strong.size_signal,
    centroid_signal = strong.centroid_signal,
    angle_signal = strong.angle_signal,
)
gsb = GaussianStrongBeamSpec{Float64}(;
    thin = thin_strong,
    ns = strong.z_slices,
    sigz = strong.sigma[3],
    slice_method = strong.slice_method,
    hvoffset = strong.hvoffset,
)

rad = input.radiation
radiation = LumpedRadSpec{Float64}(;
    damping_turns = rad.damping_turns,
    beta = (wb.beta_x, wb.beta_y, beta_z),
    alpha = rad.alpha,
    sigma = (wb.sigx, wb.sigy, wb.sigz),
    zeta = rad.zeta,
    eta = rad.eta,
    R = rad.coupling,
    is_damping = rad.is_damping,
    is_excitation = rad.is_excitation,
    rng_id = 2,
)

mkpath(input.result_dir)
luminosity_path = joinpath(input.result_dir, input.output.luminosity_file)
moment_path = joinpath(input.result_dir, input.output.moment_file)
luminosity_observer = ScheduledObserver(LuminosityObserver(luminosity_path))
moment_observer = ScheduledObserver(
    MomentObserver(moment_path; capacity = input.output.moment_capacity),
    EveryNSteps(
        start = input.output.moment_start,
        stop = input.output.moment_stop,
        step = input.output.moment_step,
    ),
)

line_specs = (
    tccb2ip_inv,
    tccb,
    tccb2ip,
    LorentzBoostSpec(opt.crossing_angle),
    gsb,
    RevLorentzBoostSpec(opt.crossing_angle),
    ip2tcca,
    tcca,
    ip2tcca_inv,
    one_turn,
    chrom,
    radiation,
    luminosity_observer,
    moment_observer,
)
task = TrackingTask(line_specs)
execute!(task, beam; turns = turns)

stats = beam_statistics(beam)
println("turns = ", turns)
println("n_macro = ", n_macro)
println("luminosity = ", luminosity_path)
println("moments = ", moment_path)
println("rms = ", stats.rms)
