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
docs/design/turn_modulation.md; and `SpectralNoise`, a target spectrum over a
chosen band resolved into a `TurnTable` when the line compiles;
docs/design/spectral_turn_table.md) and for reading back what the run
recorded. It supports three verification questions, each answered by the
companion scripts named at the end of this header:

1. Does the rule generate the specified noise? The run's `/turn_modulation`
   provenance names every active slot with its kind and stream (or table
   digest), and with `output.record_turn_modulation = true` (this file's
   default) the artifact also holds the per-turn OFFSETS every active slot
   produced, read back through the same public reader; this script prints
   their realised rms against the requested rms per slot, read from the
   record rather than by replaying the rule. The spectrum is measured by
   validation/turn_modulation_spectra.jl (the shipped rules) and
   validation/crab_cavity_noise_response.jl part `noise` (the shipped rules
   and, item `spectral`, a spectral table's periodogram against its target).
2. What is the beam-beam response? The weak beam's rms emittances and the
   luminosity are in the artifact per turn; the response to the noise is
   their growth against the noise-free run, with and without the beam-beam
   kick (the harness toggles both).
3. How do the rules compare? White, pink, a tabulated record and a spectral
   table (a target spectrum over a chosen band) of the same rms are declared
   through one `crab_noise.rule` switch, so the comparison changes one line
   and the output names collide nowhere.

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

    rule             :white | :pink | :table | :spectral | :none
    phase_rms        rms of the RF phase offset per active harmonic, rad
    strength_rel_rms relative rms of the kick strength per active harmonic
    scale            multiplies both rms values (amplitude sweeps)
    pink_octaves     the pink rule's octave count (read by :pink only)
    table_turns      length of the synthetic or spectral table (:table, :spectral)
    table_seed       seed of the synthetic record's generator (:table only)
    spectrum         target spectrum of the spectral rule, :flat, :pink or
                     "label" => S (read by :spectral only)
    band             (lb, ub) of the spectral rule in cycles per turn
                     (read by :spectral only)
    amplitudes       :fixed | :rayleigh, the spectral rule's bin amplitudes
                     (read by :spectral only)

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
`:spectral` declares each slot's noise by its spectrum instead:
`SpectralNoise(sigma, band, spectrum; rng_id, turns = table_turns,
amplitudes)` (docs/design/spectral_turn_table.md), a spec-level rule exactly
parallel to `WhiteNoise` and `PinkNoise` -- the same explicit `rng_id` per
slot, the run's global seed (`set_global_rng!`) as its seed, no `table_seed`
-- that resolves when the line compiles into a `TurnTable` of `turns` entries
synthesised by the library's factory `spectral_turn_table` (the same function
serves offline tables, with an explicit `seed`): `spectrum` a preset
(`:flat`, `:pink`) or a `"label" => S` pair, `S(f) >= 0` the one-sided power
spectral density SHAPE whose square root is the bin amplitude (`f -> 1/f` as
an amplitude would be brown, 1/f^2, not pink); `band = (lb, ub)` in cycles
per turn with `0 < lb < ub <= 1/2` (the DC bin is never in it); the rms over
the band `sigma` by an analytic normalisation (no sample statistic); the bin
phases from the counter RNG keyed on `(seed, rng_id, slot, bin)`, the slot
index included so that one `rng_id` per cavity would still give independent
tables per slot, as for the white and pink rules; and `amplitudes`
either `:fixed` (this file's default: every bin at its target amplitude, so
the rms over one period of the table and the periodogram per bin are exact up
to rounding) or `:rayleigh` (a stationary Gaussian process: the bin
amplitudes are Rayleigh-distributed about the target, `sigma` is the EXPECTED
rms and the bin powers scatter exponentially about the target spectrum,
matching it statistically). The resolved table is named canonically,
`spectral(<label>; sigma=.., band=.., turns=.., seed=.., rng_id=.., slot=..,
amplitudes=..)`, so the provenance carries the physics that made it beside
its digest, and it is a
`TurnTable` like any other: the same window check, digest and recorder apply,
and the task refuses one shorter than the run.
`:none` leaves every entry inactive, which is the weak-strong example's case.
`case_name` derives from the rule and the scale (`crab_noise_white_x1`; a
spectral case adds its spectrum's label, `crab_noise_spectral_pink_x1`), so
sweeps never collide on output paths.

OUTPUTS. ONE run artifact under `result/<seed>/<case_name>.h5`
(docs/design/run_artifact.md): `/luminosity/strong_beam_1`,
`/moments/weak_beam`, the `/execution` ledger and, for a modulated run,
`/turn_modulation/<ledger row>` -- with, since `output.record_turn_modulation`
is `true` here, the `series` dataset per modulated element: one row per turn,
one Float64 column per active slot, the OFFSET the rule produced (radians on
a phase slot; the dimensionless relative factor d on a strength slot, the
realised strengths being S (1 + d)), the same evaluation the element used
(docs/design/turn_modulation_record.md; 8 bytes per active slot per turn,
which is why the library's default is off). Read with one handle, `out =
TaskOutput(path)`: `read(out, :luminosity; name = "strong_beam_1")`,
`read(out, :moments; name = "weak_beam")`, `read(out, :execution)`,
`read(out, :turn_modulation)` (also `turn_modulation_provenance(path)`; each
slot entry's `series` is the recorded column, `nothing` when a run did not
record, and `nominal` the slot's nominal parameters).
After the run this script prints the execution policy, the `:turn_modulation`
execution receipt (`execution_receipts` of the audit), the provenance per
element and slot, one table of the recorded series per element and active
slot (label, rule kind, nominal, series length, realised rms against the
requested rms and their ratio: for a white rule 1 within the sampling band
+-1/sqrt(2 turns), one sigma; for a pink rule printed without a pin, since
the band-limited sum's finite-run rms wanders with its slow generators; for
a spectral table with fixed amplitudes 1 exactly up to rounding when the run
covers the table's whole period, `turns = table_turns`, the normalisation
being analytic, and without a pin over a partial period or with Rayleigh
amplitudes, where `sigma` is the expected rms), the luminosity mean and the
weak beam's first and last recorded rms emittances.
Only the receipt, the provenance and the series are authoritative at the
suite-sized default of 2 turns (the series' rms then sits anywhere in a wide
band, and the printout says how wide); the emittance growth is a measurement
only for long runs (the production comment on `config.turns`).
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
        # :white | :pink | :table | :spectral | :none -- the one switch of the
        # comparison.
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
        # `table_turns`, read by :table and :spectral, inert otherwise: the
        # table's length (must cover the run's turns -- the task refuses a
        # shorter table and never wraps one). `table_seed`, read by :table
        # only: the seed of the synthetic record's generator, a
        # `Random.Xoshiro` independent of the tracker's counter RNG. The
        # spectral rule has no seed of its own: like the white and pink rules
        # it keys on the run's global seed (`set_global_rng!` below) and the
        # slot's explicit `rng_id`.
        table_turns = 1_048_576,
        table_seed = 20261014,
        # Read by :spectral only, inert otherwise: the target spectrum, the
        # band and the amplitudes of `SpectralNoise`
        # (docs/design/spectral_turn_table.md).
        # `spectrum` is a preset, :flat or :pink, or a `"label" => S` pair
        # with S(f) >= 0 the one-sided power spectral density SHAPE -- its
        # square root is the bin amplitude, so `f -> 1/f` handed as an
        # amplitude would be a 1/f^2 brown spectrum, not pink; only the shape
        # matters, so the unit of f inside S is irrelevant. `band = (lb, ub)`
        # is in cycles per turn, 0 < lb < ub <= 1/2, the DC bin never in it.
        # The default is the pink preset over the 16-octave band the :pink
        # rule covers (f_rev/2^16 to f_rev/2), so the two rules compare at
        # equal rms and equal band: this one with the exact 1/f spectrum, the
        # shipped one with the Voss-McCartney ripple
        # (docs/design/turn_modulation.md, section 5.5). `amplitudes` picks
        # the bin amplitudes: :fixed reproduces the target spectrum exactly
        # (every bin at its target amplitude; the rms over the table's period
        # and the periodogram per bin exact up to rounding) and is the owner's
        # construction; :rayleigh draws Rayleigh-distributed amplitudes, the
        # stationary Gaussian process whose EXPECTED rms is sigma and whose
        # bin powers scatter exponentially about the target (Q3 of the design
        # note, decided 2026-10-16).
        spectrum = :pink,
        band = (1.0 / 2^16, 0.5),
        amplitudes = :fixed,
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

    # The weak-strong example's block, unchanged. Inert in effect: with
    # `damping_turns = 1e100` the element's excitation scale,
    # sqrt(-expm1(-2/tau)) = 1.4e-50, is below half an ulp of every
    # coordinate, so the moments are bitwise identical with the element in
    # and out of the line (the harness's OCTOPUS_RADIATION toggle, 2 turns,
    # 2026-10-16 neighbour audit); a stochastic radiation drive needs the
    # damping turns set.
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
        # Record the per-turn offsets the noise rules produce as the `series`
        # dataset beside each cavity's provenance (`?RunArtifact`,
        # docs/design/turn_modulation_record.md). ON here, as the precedent
        # for reading the realised noise back from the record instead of
        # replaying the rule (owner decision 2026-10-15); the library's
        # default is off because the file grows by 8 bytes per active slot
        # per turn (64 MB per million turns for this case's eight slots).
        # Recording changes nothing in the tracking.
        record_turn_modulation = true,
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
cn.rule in (:white, :pink, :table, :spectral, :none) || error(
    "input.crab_noise.rule = $(repr(cn.rule)) is not one of :white, :pink, :table, :spectral, :none")
N_harmonics = length(input.crab_cavity.harmonic_weights)
# The rms values that RUN: the configured ones times `scale`, or 0 under
# :none, where no slot carries a rule (the harness reports the same quantity).
phase_sigma = cn.rule === :none ? 0.0 : cn.phase_rms * cn.scale
strength_sigma_rel = cn.rule === :none ? 0.0 : cn.strength_rel_rms * cn.scale
# One master generator seeded by `table_seed` hands each table its own
# substream seed, in slot order (tccb phases, tccb strengths, tcca phases,
# tcca strengths), so the record is reproducible and the slots independent.
# Built for :table only: no other rule reads the generator.
table_master = cn.rule === :table ? Random.Xoshiro(cn.table_seed) : nothing
function noise_rule(sigma, rng_id, label)
    cn.rule === :white && return WhiteNoise(sigma; rng_id = rng_id)
    cn.rule === :pink && return PinkNoise(sigma; rng_id = rng_id, octaves = cn.pink_octaves)
    # The spectral rule, parallel to the two above: the same explicit
    # `rng_id`, the run's global seed; it resolves when the line compiles into
    # a Float64 `TurnTable` of `table_turns` entries synthesised from the
    # target spectrum over the band, rms `sigma` by the analytic
    # normalisation (no sample statistic), the bin phases keyed on (seed,
    # rng_id, slot, bin). The resolved table's canonical name,
    # `spectral(<label>; sigma=.., band=.., turns=.., seed=.., rng_id=..,
    # slot=.., amplitudes=..)`,
    # goes into the provenance beside its digest, so the record carries the
    # physics that made it (D7 of the design note); `label` names the
    # synthetic white table and is not used here.
    cn.rule === :spectral && return SpectralNoise(sigma, cn.band, cn.spectrum;
                                                  rng_id = rng_id, turns = cn.table_turns,
                                                  amplitudes = cn.amplitudes)
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
# never collides on the artifact path; a spectral case adds its spectrum's
# label (`crab_noise_spectral_pink_x1`), so the presets never collide either
# (a band sweep is the validation's later campaign and names its own cases).
scale_tag(s) = isinteger(s) ? string(Int(s)) : string(s)
spectrum_label(sp) = sp isa Symbol ? string(sp) : String(first(sp))
case_name = "crab_noise_$(cn.rule)" *
            (cn.rule === :spectral ? "_" * replace(spectrum_label(cn.spectrum), r"[^A-Za-z0-9_]" => "_") : "") *
            "_x$(scale_tag(cn.scale))"
# The values that ran, not the configured ones: under :none both are 0.
println("crab_noise: rule = ", cn.rule, ", effective phase_rms = ", phase_sigma,
        " rad, effective strength_rel_rms = ", strength_sigma_rel,
        " (scale ", cn.scale, ")",
        cn.rule === :pink ? ", pink_octaves = $(cn.pink_octaves)" : "",
        cn.rule === :table ? ", table_turns = $(cn.table_turns), table_seed = $(cn.table_seed)" : "",
        cn.rule === :spectral ? ", spectrum = $(spectrum_label(cn.spectrum)), band = $(cn.band) cycles/turn, " *
                                "amplitudes = $(cn.amplitudes), table_turns = $(cn.table_turns) " *
                                "(the bin phases keyed on the run's seed $(input.seed) and the slots' rng_ids, as the white and pink rules are)" : "",
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
    artifact = RunArtifact(artifact_path; capacity = input.output.capacity,
                           record_turn_modulation = input.output.record_turn_modulation))
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
    cavity_name(k) = k <= length(modulated_cavities) ? modulated_cavities[k] : "element $(k)"
    cavity_label(k) = k <= length(modulated_cavities) ?
        "element $(k) = $(cavity_name(k))" : cavity_name(k)
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
    provenance = turn_modulation_provenance(artifact_path)
    for entry in provenance
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

    # The recorded series: what the rules GENERATED, turn by turn, read back
    # from the artifact (`output.record_turn_modulation = true`) through the
    # same reader -- entry i of a slot's `series` is the offset applied on
    # absolute turn first_turn + i - 1, the very value the element used (one
    # evaluation shared with the realised element; nothing is replayed here).
    # Per element and active slot: the realised rms of the series against the
    # requested rms of its rule -- a phase slot's offsets are radians, the
    # requested rms `phase_sigma`; a strength slot's are the dimensionless
    # relative factor d, the requested rms `strength_sigma_rel`. For the white
    # rule, and for the synthetic white table, the ratio is 1 up to the
    # sampling error of an rms over T iid normals, one sigma 1/sqrt(2T). For
    # the pink rule the ratio is printed WITHOUT a pin: the Voss-McCartney sum
    # is band-limited, its generator k holds one value for 2^k turns, so a
    # finite run's rms wanders with the slow generators far beyond 1/sqrt(2T)
    # (one sigma 7.65 % at 2^16 turns, `?PinkNoise`); the verdict belongs to
    # validation/crab_cavity_noise_response.jl part `noise`, taken over 2^20
    # turns against the construction's own Monte Carlo band. For a spectral
    # table the normalisation is analytic (D5 of
    # docs/design/spectral_turn_table.md): over the table's WHOLE period the
    # bins are orthogonal and the rms equals sigma exactly up to rounding, so
    # a run of `table_turns` turns expects a ratio of 1 to about 1e-12; over
    # a partial period (this file's default, 2 turns of a 2^20 table) the
    # window's rms is not the period's, and the ratio is printed without a
    # pin -- as it is for Rayleigh amplitudes, where sigma is the EXPECTED rms
    # and one realisation's rms scatters about it. The verdict on the
    # spectrum itself (the periodogram of the recorded series against the
    # target) is the validation's item `spectral`.
    if input.output.record_turn_modulation
        one_sigma = 1 / sqrt(2 * turns)
        fmt(x) = string(round(x; sigdigits = 6))
        nominal_text(nom) = nom === nothing ? "n/a" :
            join(("$(name)=$(fmt(getfield(nom, name)))" for name in propertynames(nom)), " ")
        # A spectral table reads back as kind :table (it IS one), so the rule
        # switch decides its row, and the series length says whether the run
        # covered the table's whole period.
        band_text(kind, n) = kind === :pink ? "no pin (band-limited sum)" :
            cn.rule === :spectral ?
                (cn.amplitudes !== :fixed ? "no pin (Rayleigh amplitudes: sigma is the expected rms)" :
                 n == cn.table_turns ? "1 exactly up to rounding (analytic normalisation over the whole period)" :
                                       "no pin (partial period: $(n) of $(cn.table_turns) table turns)") :
                "1 +- $(fmt(one_sigma)) (1 sigma)"
        println("turn_modulation series: recorded offsets read from the artifact, realised rms against the requested rms")
        if cn.rule === :spectral && cn.amplitudes !== :fixed
            println("  spectral table rows (", cn.amplitudes, " amplitudes): no pin; sigma is the EXPECTED rms of the ",
                    "stationary Gaussian process and one realisation's rms scatters about it")
        elseif cn.rule === :spectral
            println("  spectral table rows (fixed amplitudes): ratio = 1 exactly up to rounding when the run covers the table's whole period ",
                    "(turns == table_turns; here ", turns, " of ", cn.table_turns, " turns), ",
                    turns == cn.table_turns ? "which it does" : "else no pin: a window of a periodic sequence has not the period's rms")
        else
            println("  white and table rows: ratio = 1 within +-", fmt(one_sigma),
                    " (one sigma, 1/sqrt(2 turns) at ", turns, " turns); pink rows: no pin, ",
                    "the band-limited sum's finite-run rms wanders with its slow generators")
        end
        println("  ", rpad("element slot", 26), rpad("kind", 7), rpad("nominal", 50),
                lpad("length", 7), lpad("realised rms", 14), lpad("requested rms", 14),
                lpad("ratio", 9), "  expected")
        # One row per active slot of every recorded execution; counted first,
        # since a counter bumped inside a top-level `for` would be a new local.
        n_rows = sum(length(e.slots) for entry in provenance for e in entry.elements; init = 0)
        for entry in provenance, (k, e) in enumerate(entry.elements), s in e.slots
            s.series === nothing && error(
                "output.record_turn_modulation = true, but $(cavity_label(k)) $(s.slot) " *
                "recorded no series in /execution row $(entry.execution)")
            requested = startswith(s.slot, "phase_noise") ? phase_sigma : strength_sigma_rel
            realised = sqrt(sum(abs2, s.series) / length(s.series))
            println("  ", rpad("$(cavity_name(k)) $(s.slot)", 26), rpad(string(s.kind), 7),
                    rpad(nominal_text(s.nominal), 50), lpad(string(length(s.series)), 7),
                    lpad(fmt(realised), 14), lpad(fmt(requested), 14),
                    lpad(fmt(realised / requested), 9), "  ", band_text(s.kind, length(s.series)))
        end
        n_rows == 0 && println("  (no modulated element in the line: nothing recorded; crab_noise.rule = ", cn.rule, ")")
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
