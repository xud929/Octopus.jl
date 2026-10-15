#=
Crab cavity RF noise on a colliding beam: the weak-strong EIC crab-crossing
case of examples/weak_strong_tracking.jl with turn-by-turn RF phase and
amplitude noise on the two PROTON crab cavities, `tccb` (upstream of the IP)
and `tcca` (downstream), each cavity on its own independent streams.

PURPOSE. A crab cavity's RF phase jitter displaces the bunch at the IP turn by
turn and its amplitude jitter modulates the crabbing tilt; against the strong
beam's beam-beam force both drive transverse emittance growth and cost
luminosity. This example is the production-shaped precedent for declaring that
noise with the turn-modulation rules (`WhiteNoise`, `PinkNoise`, `TurnTable`;
docs/design/turn_modulation.md) and for reading back what the run recorded.
It supports three verification questions, each answered by the companion
scripts named at the end of this header:

1. Does the rule generate the specified noise? The run's `/turn_modulation`
   provenance names every active slot with its kind and stream (or table
   digest); the realised offsets per turn have the stated rms and spectrum
   (validation/turn_modulation_spectra.jl measures the shipped rules).
2. What is the beam-beam response? The weak beam's rms emittances and the
   luminosity are in the artifact per turn; the response to the noise is
   their growth against the noise-free run, with and without the beam-beam
   kick (the harness toggles both).
3. How do the rules compare? White, pink and a tabulated record of the same
   rms are declared through one `crab_noise.rule` switch, so the comparison
   changes one line and the output names collide nowhere.

STRUCTURE (the weak-strong example's pattern, one block added):

1. Define one `input` named tuple: weak beam, optics, crab cavity, CRAB NOISE,
   strong beam, radiation, output. Everything but `crab_noise` reproduces the
   weak-strong example's case, numbers unchanged.
2. Build the weak `Beam` directly from the input.
3. Build the element specs in tracking order; the two crab cavities carry
   `phase_noise` and `strength_noise` rules built from `crab_noise`.
4. Build `TrackingTask(line)`, `execute!` it inside an execution audit, and
   read back the receipt, the provenance and the physics columns.

INPUTS. `input.crab_noise`:

    rule             :white | :pink | :table | :none
    phase_rms        rms of the RF phase offset per active harmonic, rad
    strength_rel_rms relative rms of the kick strength per active harmonic
    scale            multiplies both rms values (amplitude sweeps)
    pink_octaves     the pink rule's octave count (read by :pink only)
    table_turns      length of the synthetic record (read by :table only)
    table_seed       seed of the synthetic record's generator (:table only)

For each harmonic i with a nonzero weight, `phase_noise[i]` is the rule with
sigma = phase_rms * scale (rad, added to the phase) and `strength_noise[i]`
the rule with sigma = strength_rel_rms * scale, the relative rms ITSELF: a
realised strength value d is ONE dimensionless factor per turn scaling both
planes' strengths of its harmonic, strengthX[i] (1 + d) and strengthY[i]
(1 + d) (`?ThinCrabCavitySpec`; one voltage driver per cavity, owner decision,
relative since 2026-10-15). With the vertical strength zero here the vertical
kick stays exactly zero, so amplitude noise excites no vertical emittance
growth without beam-beam. Harmonics with zero weight stay inactive
(`nothing`). `:table` hands a synthetic Gaussian white record of the stated
rms (rad on a phase slot, relative factors on a strength slot) to
`TurnTable(offsets; name = "<cavity>_<slot>_synthetic_white")`, one
`Random.Xoshiro` substream per slot derived from `table_seed`; a MEASURED LLRF
record (phase in rad, strength as relative factors, one entry per turn) would
be passed the same way, and the task refuses a table shorter than the run.
`:none` leaves every entry inactive, which is the weak-strong example's case.
`case_name` derives from the rule and the scale (`crab_noise_white_x1`), so
sweeps never collide on output paths.

OUTPUTS. ONE run artifact under `result/<seed>/<case_name>.h5`
(docs/design/run_artifact.md): `/luminosity/strong_beam_1`,
`/moments/weak_beam`, the `/execution` ledger and, for a modulated run,
`/turn_modulation/<ledger row>`. Read with one handle, `out =
TaskOutput(path)`: `read(out, :luminosity; name = "strong_beam_1")`,
`read(out, :moments; name = "weak_beam")`, `read(out, :execution)`,
`read(out, :turn_modulation)` (also `turn_modulation_provenance(path)`).
After the run this script prints the execution policy, the `:turn_modulation`
execution receipt (`execution_receipts` of the audit), the provenance per
element and slot, the luminosity mean and the weak beam's first and last
recorded rms emittances. Only the receipt and the provenance are
authoritative at the suite-sized default of 2 turns; the emittance growth is
a measurement only for long runs (the production comment on `config.turns`).
Under `:multiprocess` every rank prints the policy, the `crab_noise:`
configuration line (each rank asserting what it read) and its `mpi_rank = r
of P` line; rank 0 alone holds the artifact (the library gates the file) and
prints the readback, and every other rank ends with one line naming itself.

Run from the project root (edit the `config` block first; `:auto` picks CUDA
when a device is functional):

    julia --project=. examples/crab_cavity_noise.jl

With `config.execution = :multiprocess` -- MPI ranks x CPU threads -- the file
must run in PACKAGE mode under a launcher (the execution policy block says why):

    mpiexec -n 4 julia --project=. -e 'using Octopus, MPI; include("examples/crab_cavity_noise.jl")'

The configurable developer harness of the same case (run size, device, rule,
rms values, beam-beam and radiation toggles through OCTOPUS_* variables, one
machine-readable summary line) is test/examples/crab_cavity_noise.jl; the
numerical study of the noise response (the three questions above, with
tolerances) is validation/crab_cavity_noise_response.jl.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
import Random

# Physics input. Every block but `crab_noise` reproduces the weak-strong
# example's case (examples/weak_strong_tracking.jl), numbers unchanged, so the
# noise-free run of this file and that example describe the same machine.
input = (
    # `case_name` derives from the noise rule and scale below (one authority,
    # no copies); `seed` names the output directory. Every field in this
    # block is consumed -- a field nothing reads is the
    # config-that-was-never-read defect class (AGENTS.md Invariants).
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
        # what the crab strength tan(theta)/sqrt(beta_cc*beta*) below assumes
        # (the weak-strong example's note; the factor of two is the classic
        # beam-beam error, 2026-08-05_b audit, U16-10).
        crossing_angle = 12.5e-3,
        tune = (0.228, 0.210, -0.01),
        chromaticity = (2.0, 2.0),
    ),

    crab_cavity = (
        frequency = 197.0e6,
        # Relative harmonic weights of the horizontal crab kick; the absolute
        # scale tan(crossing_angle)/sqrt(beta_cc * beta*) is derived below.
        # (4/3, -1/3) is the two-harmonic scheme that cancels the leading
        # nonlinearity of a single 197 MHz cavity. The third harmonic has zero
        # weight and therefore carries no noise rule.
        harmonic_weights = (4.0 / 3.0, -1.0 / 3.0, 0.0),
        strength_y = (0.0, 0.0, 0.0),
        phase = (0.0, 0.0, 0.0),
    ),

    crab_noise = (
        # :white | :pink | :table | :none -- the one switch of the comparison.
        rule = :white,
        # Owner specification: RF phase noise rms 10 urad and relative
        # amplitude noise rms 1e-4, per active harmonic, each cavity with
        # independent streams.
        phase_rms = 10.0e-6,        # rad, rms of the RF phase offset per active harmonic
        strength_rel_rms = 1.0e-4,  # relative rms of the kick strength per active harmonic (the strength rule's sigma)
        scale = 1.0,                # multiplies both rms values (amplitude sweeps)
        # Read by :pink only: the Voss-McCartney octave count (`?PinkNoise`);
        # inert under the other rules.
        pink_octaves = 16,
        # Read by :table only, inert otherwise: the synthetic record's length
        # (must cover the run's turns -- the task refuses a shorter table and
        # never wraps one) and the seed of its generator, a `Random.Xoshiro`
        # independent of the tracker's counter RNG.
        table_turns = 1_048_576,
        table_seed = 20261014,
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
        # `capacity` is the ARTIFACT'S: the one knob for how many rows every
        # producer batches between appends. On a networked filesystem the
        # per-turn write is the dominant observer cost (docs/history/
        # weak_strong_cuda_luminosity_2026_08_11.md); do not lower it on
        # shared storage.
        capacity = 1024,
        moment_start = 0,
        moment_step = 1,
    ),
)

# Run configuration. Edit these; the physics `input` above is separate.
config = (
    # WHICH DEVICE THIS RUN USES -- the one line to edit.
    #
    #   :auto          CUDA when a device is functional, CPU threads otherwise.
    #                  The default, so this file runs unmodified on a GPU box
    #                  and on one without (CI has no GPU).
    #   :cuda          one CUDA device, and an ERROR if none is functional.
    #   :threads       CPU logical workers, one process.
    #   :multiprocess  MPI ranks x CPU threads. Read the note in the execution
    #                  policy block below first: this file must then be run in
    #                  PACKAGE mode under a launcher.
    execution = :auto,
    gpu_device = nothing,  # CUDA device index, or nothing for the current one
    threads = :auto,       # CPU logical workers per process
    ranks = :auto,         # :multiprocess only; an integer asserts the count
    turns = 2,           # raise for a real run (production: 1_000_000)
    n_macro = 10_000,    # ~1_024_000 for a production weak beam
)
turns = config.turns
n_macro = config.n_macro
# ---------------------------------------------------------------------------
# Execution policy. `:auto` prefers CUDA and falls back to CPU threads, and the
# run PRINTS which it chose: a measurement whose device you have to guess at is
# one you cannot report. `:cuda` is the same choice made strict. `:multiprocess`
# divides the beam across MPI ranks (the weak-strong example's arm): the
# turn-modulation rules are stateless functions of the absolute turn, realised
# identically on every rank's host, so a divided run applies the same noise as
# the undivided one; each particle's streams key on its GLOBAL slot, so the
# tracked coordinates and the chunk-folded luminosity are the undivided run's
# bit for bit, while the moment observer's rank-ordered reduction agrees to
# the accumulation difference between one serial sum and P of them
# (`_masked_global_sum`, src/policies/Policies.jl, records that trade).
# ---------------------------------------------------------------------------
cuda_ok = false
if config.execution === :auto || config.execution === :cuda
    import CUDA
    cuda_ok = CUDA.functional(false)
    config.execution === :cuda && !cuda_ok && error(
        "config.execution = :cuda, but CUDA.functional(false) is false: no " *
        "usable device. Use :auto to fall back to CPU threads, or :threads.")
elseif !(config.execution in (:threads, :multiprocess))
    error("config.execution = $(repr(config.execution)) is not one of :auto, :cuda, :threads, :multiprocess")
end
# `ranks` is read by `:multiprocess` alone; set anywhere else it would be a
# configuration nothing read, which this repository counts as a defect.
config.execution === :multiprocess || config.ranks === :auto || error(
    "config.ranks = $(repr(config.ranks)) is read only under config.execution = :multiprocess; " *
    "under $(repr(config.execution)) it would go unread")

policy = if config.execution === :multiprocess
    # One Octopus process per MPI rank, each with its own CPU logical workers.
    #
    # This choice needs the file run in PACKAGE MODE under a launcher:
    #
    #   mpiexec -n 4 julia --project=. -e 'using Octopus, MPI; include("examples/crab_cavity_noise.jl")'
    #
    # because `MultiProcessExecutionPolicy` reaches a real communicator only
    # through the `OctopusMPIExt` package extension, and a package extension
    # attaches only to a PACKAGE -- which the `include` of src/Octopus.jl at the
    # top of this file is not. Without the extension every rank would be its own
    # communicator of one, `ranks = :auto` would accept that, and `mpiexec -n 4`
    # would run FOUR whole simulations racing on one artifact path: exit 0,
    # plausible timings, wrong answer. So it is refused instead.
    Base.get_extension(Main.Octopus, :OctopusMPIExt) === nothing && error(
        "config.execution = :multiprocess needs the OctopusMPIExt extension, " *
        "which attaches only when Octopus is loaded as a PACKAGE with MPI also " *
        "loaded. Run: mpiexec -n <P> julia --project=. -e 'using Octopus, MPI; " *
        "include(\"examples/crab_cavity_noise.jl\")'")
    MultiProcessExecutionPolicy(threads = config.threads, ranks = config.ranks)
elseif cuda_ok
    CUDAExecutionPolicy(device = config.gpu_device)
else
    CPUThreadsExecutionPolicy(threads = config.threads)
end
println("execution policy = ", nameof(typeof(policy)),
        config.execution === :auto ?
            (cuda_ok ? "  (auto: a CUDA device is available)" :
                       "  (auto: no CUDA device, running on CPU threads)") : "")
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

# ---------------------------------------------------------------------------
# The noise rules. One builder serves both cavities; the slot a rule lands in
# is the crab cavity's (`phase_noise[i]` for harmonic i, `strength_noise[i]`),
# and the `TurnModulated` wrap that `compile_runtime` builds applies the
# realised offsets once per turn on the host (`?ThinCrabCavitySpec`).
#
# The stream ids are EXPLICIT: `rng_id = 0` (the default) takes the next id
# from a process-global counter, so the id a slot gets would depend on what
# else the session built first and would differ between this file, the
# harness and a REPL -- the provenance record (`rng_id` per slot) would then
# not be comparable across runs. Fixed ids keep the record identical from run
# to run and make an id readable as a slot: tccb uses 10 + slot, tcca 20 +
# slot, slot = i for `phase_noise[i]` and N + i for `strength_noise[i]`; the
# beam claims 1 and the radiation element 2. The two cavities' ranges are
# disjoint because two elements sharing one id draw IDENTICAL offsets (the
# task constructor warns about that); within one cavity the slot is part of
# the counter-RNG key, so one id per cavity would already be independent per
# slot -- the per-slot ids are for the record, not for independence.
# ---------------------------------------------------------------------------
cn = input.crab_noise
cn.rule in (:white, :pink, :table, :none) || error(
    "input.crab_noise.rule = $(repr(cn.rule)) is not one of :white, :pink, :table, :none")
N_harmonics = length(input.crab_cavity.harmonic_weights)
# The rms values that RUN: the configured ones times `scale`, or 0 under
# :none, where no slot carries a rule (the harness reports the same quantity).
phase_sigma = cn.rule === :none ? 0.0 : cn.phase_rms * cn.scale
strength_sigma_rel = cn.rule === :none ? 0.0 : cn.strength_rel_rms * cn.scale
# One master generator seeded by `table_seed` hands each table its own
# substream seed, in slot order (tccb phases, tccb strengths, tcca phases,
# tcca strengths), so the record is reproducible and the slots independent.
# Built for :table only: no other rule reads the seed.
table_master = cn.rule === :table ? Random.Xoshiro(cn.table_seed) : nothing
function noise_rule(sigma, rng_id, label)
    cn.rule === :white && return WhiteNoise(sigma; rng_id = rng_id)
    cn.rule === :pink && return PinkNoise(sigma; rng_id = rng_id, octaves = cn.pink_octaves)
    # Synthetic Gaussian white record of rms `sigma`, Float64 like the line
    # (a table of another element type is refused at compile, not promoted).
    offsets = sigma .* randn(Random.Xoshiro(rand(table_master, UInt64)), cn.table_turns)
    return TurnTable(offsets; name = label)
end
function crab_noise_rules(cavity::String, id_base::Int)
    cn.rule === :none && return (phase_noise = (), strength_noise = ())
    active = i -> !iszero(input.crab_cavity.harmonic_weights[i])
    phase = ntuple(N_harmonics) do i
        active(i) || return nothing
        noise_rule(phase_sigma, id_base + i,
                   "$(cavity)_phase_noise[$(i)]_synthetic_white")
    end
    # The strength rule's realised value d is ONE dimensionless relative
    # factor per turn scaling BOTH `strengthX[i]` and `strengthY[i]` to
    # S (1 + d) (`?ThinCrabCavitySpec`, docs/design/turn_modulation_record.md
    # section 5): one voltage driver excites a cavity's horizontal and vertical
    # kick, so one relative amplitude error scales both and a second driver is
    # a second cavity (owner decision, relative since 2026-10-15). The rule's
    # sigma is therefore the relative rms itself, no |strengthX[i]| factor;
    # with the vertical strength zero here the vertical kick stays exactly
    # zero, so amplitude noise excites no vertical emittance growth without
    # beam-beam.
    strength = ntuple(N_harmonics) do i
        active(i) || return nothing
        noise_rule(strength_sigma_rel,
                   id_base + N_harmonics + i,
                   "$(cavity)_strength_noise[$(i)]_synthetic_white")
    end
    return (phase_noise = phase, strength_noise = strength)
end
tccb_noise = crab_noise_rules("tccb", 10)
tcca_noise = crab_noise_rules("tcca", 20)

# The case name derives from the rule and the scale, so a sweep over either
# never collides on the artifact path.
scale_tag(s) = isinteger(s) ? string(Int(s)) : string(s)
case_name = "crab_noise_$(cn.rule)_x$(scale_tag(cn.scale))"
# The values that ran, not the configured ones: under :none both are 0.
println("crab_noise: rule = ", cn.rule, ", effective phase_rms = ", phase_sigma,
        " rad, effective strength_rel_rms = ", strength_sigma_rel,
        " (scale ", cn.scale, ")",
        cn.rule === :pink ? ", pink_octaves = $(cn.pink_octaves)" : "",
        cn.rule === :table ? ", table_turns = $(cn.table_turns), table_seed = $(cn.table_seed)" : "",
        cn.rule === :none ? " -- every slot inactive, the configured rms values unused; " *
                            "the weak-strong example's case" : "")

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

# The proton crab cavities, upstream (tccb) and downstream (tcca) of the IP,
# each with its own noise rules. The nominal strengths and phases are the
# weak-strong example's; a rule's realised value per turn is added to the
# phase or scales the strengths (S (1 + d)) and never changes the nominal
# value stored here.
tccb = ThinCrabCavitySpec{N_harmonics}(input.crab_cavity.frequency;
    strengthX = cc_strength_x,
    strengthY = input.crab_cavity.strength_y,
    phase = input.crab_cavity.phase,
    phase_noise = tccb_noise.phase_noise,
    strength_noise = tccb_noise.strength_noise,
)
tcca = ThinCrabCavitySpec{N_harmonics}(input.crab_cavity.frequency;
    strengthX = cc_strength_x,
    strengthY = input.crab_cavity.strength_y,
    phase = input.crab_cavity.phase,
    phase_noise = tcca_noise.phase_noise,
    strength_noise = tcca_noise.strength_noise,
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

# Output lands under result/<seed>/, named by the case, so rule and amplitude
# sweeps never collide.
outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
artifact_path = normpath(joinpath(outdir, case_name * ".h5"))
# The run artifact attaches at the TASK: the strong beam's luminosity channel
# lands in it per turn, alongside the execution ledger and the modulation
# provenance. The moment observer stays a line entry -- its position is
# physical -- but is a named VIEW into the same file.
moment_observer = ScheduledObserver(
    MomentObserver(; name = "weak_beam"),
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
# `policy = policy` is load-bearing (the weak-strong example's note): without
# it `execute!` resolves a FRESH default policy and the one built above
# reaches only `Beam(...)`. Fatal rather than cosmetic for `:multiprocess`: the
# inferred default is a single-process CPU policy, under which each rank
# tracks the shard it holds AS IF IT WERE THE WHOLE BEAM -- local index
# offsets, so the per-particle streams repeat across the ranks; no cross-rank
# reduction, so the moments and the luminosity are the shard's; and every rank
# believing it is rank 0, so every rank writes the one artifact path. The
# library's launcher tripwire WARNS ("PMI_SIZE=P ... the execution policy in
# force is a single-process one"); the `ranks` check runs only when the
# multi-process policy activates, which the inferred default never does.
task = TrackingTask(line_specs;
    policy = policy,
    artifact = RunArtifact(artifact_path; capacity = input.output.capacity))
# The execution audit collects the receipts the run's consumers emit; the
# `:turn_modulation` receipt is how a run states which rules it actually
# realised (`?with_execution_audit`, `?execution_receipts`). A bare `track!`
# would realise none of them -- only a task's `execute!` does.
audit = with_execution_audit() do
    execute!(task, beam; turns = turns)
end

# Under `:multiprocess` every rank runs this file. Which rank this process is
# comes from the `:multi_process_communicator` receipt the run RECORDED at
# activation -- nranks and rank read from the communicator Octopus opened --
# not from Octopus's `_mp_rank()`, which reads the policy in force and answers
# 0 on every rank once `execute!` has closed its scope (docs/experiences.md,
# "A collective outside its scope is a silent no-op"). A single-process run
# records no such receipt: one rank, rank 0.
comm_receipts = filter(r -> r.consumer === :multi_process_communicator, execution_receipts(audit))
policy isa MultiProcessExecutionPolicy && isempty(comm_receipts) && error(
    "config.execution = :multiprocess, but the run recorded no :multi_process_communicator receipt")
mp_nranks = isempty(comm_receipts) ? 1 : Int(last(comm_receipts).values.nranks)
mp_rank = isempty(comm_receipts) ? 0 : Int(last(comm_receipts).values.rank)
policy isa MultiProcessExecutionPolicy && println(
    "mpi_rank = ", mp_rank, " of ", mp_nranks, " (recorded by the run; resolved_by = ",
    last(comm_receipts).values.resolved_by, ", threads per rank = ", last(comm_receipts).values.threads, ")")

if mp_rank != 0
    # Rank 0 alone holds the artifact (the library gates the file itself), so
    # the readback below is its. Nothing printed there is a per-rank quantity:
    # every number is read back from the artifact -- whole-beam by
    # construction, the moment observer reducing across the ranks and the
    # luminosity folding across them -- and the receipt is the same on every
    # rank (the rules and the window are). A `beam_statistics(beam)` here, as
    # the weak-strong example prints, would be THIS RANK'S SHARD and would
    # have to be labelled so.
    println("rank ", mp_rank, " of ", mp_nranks, ": shard tracked; rank 0 holds the artifact and prints the readback")
else
    println("turns = ", turns)
    println("n_macro = ", n_macro)
    println("artifact = ", artifact_path)
    println("  /luminosity/strong_beam_1, /moments/weak_beam, /execution",
            cn.rule === :none ? "" : ", /turn_modulation")

    # The receipt: one per `execute!` whose line held a modulated element, with
    # the elements and active slots it realised and the window it resolved (the
    # planned turns of this call, not the turns completed). Absent for a run
    # without a modulated element, and that absence is said out loud.
    tm_receipts = filter(r -> r.consumer === :turn_modulation, execution_receipts(audit))
    if isempty(tm_receipts)
        println("turn_modulation receipt = none recorded (the line has no modulated " *
                "element; crab_noise.rule = ", cn.rule, ")")
    end
    # The receipt and the provenance list the modulated elements in LINE ORDER
    # and name only the element type, so the two cavities read alike. This
    # script owns the line (tccb before tcca) and labels the entries by that
    # order; the labels are the script's, not something the record stores.
    modulated_cavities = ("tccb", "tcca")
    cavity_label(k) = k <= length(modulated_cavities) ?
        "element $(k) = $(modulated_cavities[k])" : "element $(k)"
    for r in tm_receipts
        println("turn_modulation receipt: first_turn = ", r.values.first_turn,
                ", turns = ", r.values.turns, ", backend = ", r.backend)
        for (k, e) in enumerate(r.values.elements)
            println("  [", cavity_label(k), "] ", e.element, " (beam ", e.beam, "): ",
                    join(("$(s.slot) $(s.kind)" for s in e.slots), ", "))
        end
    end

    # The provenance the artifact recorded, per execution and element: the stream
    # id of a white or pink slot, the digest, name and length of a table slot.
    for entry in turn_modulation_provenance(artifact_path)
        println("turn_modulation provenance, /execution row ", entry.execution, ":")
        for (k, e) in enumerate(entry.elements)
            println("  [", cavity_label(k), "] ", e.element, " (beam ", e.beam, ")")
            for s in e.slots
                if s.kind === :table
                    println("    ", s.slot, ": table digest = 0x", string(s.digest; base = 16, pad = 16),
                            ", name = ", repr(s.name), ", length = ", s.length)
                else
                    println("    ", s.slot, ": ", s.kind, ", rng_id = ", Int(s.rng_id))
                end
            end
        end
    end

    # Physics columns, read back from the artifact rather than from the live beam,
    # so what is printed is what the file holds.
    out = TaskOutput(artifact_path)
    lum = read(out, :luminosity; name = "strong_beam_1")
    println("luminosity mean over ", length(lum.value), " turns = ",
            sum(lum.value) / length(lum.value), " (per-turn values in /luminosity/strong_beam_1)")
    mom = read(out, :moments; name = "weak_beam")
    # The rms emittance from the central second moments, per recorded turn:
    # eps_x = sqrt(<x^2><px^2> - <x px>^2) with the columns m200000, m020000,
    # m110000, and eps_y likewise from m002000, m000200, m001100 (`?Moment`).
    eps_x = sqrt.(mom.m200000 .* mom.m020000 .- mom.m110000 .^ 2)
    eps_y = sqrt.(mom.m002000 .* mom.m000200 .- mom.m001100 .^ 2)
    println("weak beam rms emittance estimator = sqrt(<x^2><px^2> - <x px>^2) from the " *
            "central second moments of /moments/weak_beam")
    println("  design (input) emittances: eps_x = ", emit[1], ", eps_y = ", emit[2])
    println("  eps_x: first recorded (turn ", Int(mom.turn[1]), ") = ", eps_x[1],
            ", last recorded (turn ", Int(mom.turn[end]), ") = ", eps_x[end])
    println("  eps_y: first recorded (turn ", Int(mom.turn[1]), ") = ", eps_y[1],
            ", last recorded (turn ", Int(mom.turn[end]), ") = ", eps_y[end])
    println("  the first-to-last growth is a measurement only for long runs (raise " *
            "config.turns); at the suite-sized default it is noise of the estimator")
end
