#=
Weak-strong tracking example: a live weak proton beam colliding with a fixed
soft-Gaussian strong beam, through a crab crossing.

This is the clean, production-shaped example. Edit the small `config` block
below, then run from the project root:

    julia --project=. examples/weak_strong_tracking.jl

For a configurable development/testing harness of the same case with
environment-variable toggles (run size, CUDA device selection), see
test/examples/weak_strong_tracking.jl.

The pattern this example follows:

1. Define one `input` named tuple: weak beam, optics, crab cavity, strong beam,
   radiation, output.
2. Build the weak `Beam` directly from the input (including any initial offset).
3. Build element specs in tracking order and place observers where they matter.
4. Build `TrackingTask(line)` and `execute!` it.

Outputs are written under `result/<seed>/`, named by the case:

- `<case_name>.lum`  : turn and luminosity
- `<case_name>.h5`   : weak-beam moment history

so seed scans and multi-case studies (different chromaticities, crab
schemes) never collide on output paths — change `case_name` or `seed` and
everything downstream follows.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

# Physics input for this weak-proton crab-crossing case.
input = (
    # `case_name` and `seed` name the output directory and files below; every
    # field in this block is consumed — a field nothing reads is the
    # config-that-was-never-read defect class (AGENTS.md Hard-Won Rules).
    case_name = "weak_strong",
    result_dir = joinpath(@__DIR__, "..", "result"),
    seed = 123456789,

    weak_beam = (
        charge = 1.0,
        mass = PMASS_EV,
        energy = 275.0e9,
        n_particle = 0.6881e11,
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
        # HALF the full crossing angle, which is what LorentzBoostSpec takes and
        # what the crab strength tan(theta)/sqrt(beta_cc*beta*) below assumes.
        # Named `half_crossing_angle` in knob_control.jl, Knobs.jl and
        # validation/crossing_luminosity_anchor.jl -- same quantity, and the
        # factor of two is the classic beam-beam error (2026-08-05_b audit,
        # U16-10).
        crossing_angle = 12.5e-3,
        tune = (0.228, 0.210, -0.01),
        chromaticity = (2.0, 2.0),
    ),

    crab_cavity = (
        frequency = 197.0e6,
        # Relative harmonic weights of the horizontal crab kick; the absolute
        # scale tan(crossing_angle)/sqrt(beta_cc * beta*) is derived below.
        # (4/3, -1/3) is the two-harmonic scheme that cancels the leading
        # nonlinearity of a single 197 MHz cavity; (1.0, 0.0, 0.0) is a
        # single-harmonic crab.
        harmonic_weights = (4.0 / 3.0, -1.0 / 3.0, 0.0),
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
        virtual_drift = :hirata,
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
        # Filenames derive from `case_name` above — one authority, no copies.
        # The capacities buffer rows in memory between file appends/flushes:
        # on a networked filesystem the per-turn open/append/close is the
        # dominant observer cost (measured 2.3 ms/turn on a cluster
        # filesystem vs 0.02 local; docs/history/
        # weak_strong_cuda_luminosity_2026_08_11.md), and amortized cost
        # falls monotonically with capacity. 1024 is the MomentObserver
        # default; do not lower it on shared storage.
        luminosity_capacity = 100,
        moment_capacity = 1024,
        moment_start = 0,
        moment_step = 1,
    ),
)

# Run configuration. Edit these; the physics `input` above is separate.
config = (
    use_gpu = false,     # true routes beam storage and tracking to CUDA
    gpu_device = nothing, # CUDA device index, or nothing for the current one
    turns = 2,           # raise for a real run (production: 1_000_000)
    n_macro = 10_000,    # ~1_024_000 for a production weak beam
)
turns = config.turns
n_macro = config.n_macro
if config.use_gpu
    import CUDA
    CUDA.functional(false) || error("config.use_gpu is true, but CUDA is not functional")
end
policy = config.use_gpu ? CUDAExecutionPolicy(device = config.gpu_device) :
                          CPUThreadsExecutionPolicy()
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
cc_strength_x = cckick .* input.crab_cavity.harmonic_weights

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
    virtual_drift = strong.virtual_drift,
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

# Outputs land under result/<seed>/, named by the case, so seed scans and
# multi-case studies never collide.
outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
luminosity_path = joinpath(outdir, input.case_name * ".lum")
moment_path = joinpath(outdir, input.case_name * ".h5")
# Luminosity attaches at the TASK (the unified sink, 2026-08-17): sampled at
# turn end after the whole line, the same LuminosityObserver StrongStrongTask
# takes. The moment observer stays a line entry -- its position is physical.
moment_observer = ScheduledObserver(
    MomentObserver(moment_path; capacity = input.output.moment_capacity),
    EveryNSteps(
        start = input.output.moment_start,
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
    moment_observer,
)
task = TrackingTask(line_specs;
    luminosity = LuminosityObserver(luminosity_path;
                                    capacity = input.output.luminosity_capacity))
execute!(task, beam; turns = turns)

stats = beam_statistics(beam)
println("turns = ", turns)
println("n_macro = ", n_macro)
println("luminosity = ", luminosity_path)
println("moments = ", moment_path)
println("rms = ", stats.rms)
