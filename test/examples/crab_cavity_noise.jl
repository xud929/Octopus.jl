#=
Crab cavity RF noise on a colliding beam: the CONFIGURABLE development/testing
harness of examples/crab_cavity_noise.jl -- the weak-strong EIC crab-crossing
case with turn-by-turn RF phase and amplitude noise on the two proton crab
cavities `tccb` and `tcca`, each on independent streams. The clean,
production-shaped example meant as a user guideline (no environment variables)
is examples/crab_cavity_noise.jl; this file exposes the run size, the device,
the noise rule and its amplitudes, a spectral table's preset and band, the
chromaticity, a file-fed table and two A/B toggles (beam-beam kick,
radiation) through OCTOPUS_* variables, and ends
with ONE machine-readable line for validation/crab_cavity_noise_response.jl
to parse.

Run from the Octopus project root:

    julia --project=. test/examples/crab_cavity_noise.jl

Run divided across MPI ranks -- one Octopus process per rank, each with its own
CPU logical workers (OCTOPUS_CPU_THREADS per rank; OCTOPUS_RANKS optionally
states the process count the run must match, `auto` accepts whatever the
launcher started). This needs an environment where Octopus AND MPI both resolve
as PACKAGES (the OCTOPUS_USE_MPI paragraph below says why):

    OCTOPUS_USE_MPI=1 OCTOPUS_CPU_THREADS=4 OCTOPUS_RANKS=4 mpiexec -n 4 julia --project=. --threads=4 test/examples/crab_cavity_noise.jl

or, equivalently, with the packages loaded first:

    OCTOPUS_USE_MPI=1 OCTOPUS_RANKS=4 mpiexec -n 4 julia --project=. --threads=4 -e 'using Octopus, MPI; include("test/examples/crab_cavity_noise.jl")'

The default run is intentionally small: 2 turns and 10000 macroparticles,
white noise at the owner's specification (phase rms 10 urad, relative strength
rms 1e-4, per active harmonic). Every variable this harness reads, with its
default; each one is consumed, and a value outside a variable's grammar is an
error naming the variable and the value (booleans through `env_bool`, numbers
through `env_parse`; a set variable nothing reads is the
config-that-was-never-read defect class, AGENTS.md Invariants):

    OCTOPUS_TURNS             turns to track (2)
    OCTOPUS_N_MACRO           macroparticles of the weak beam (10000)
    OCTOPUS_USE_GPU           1|0: CUDA storage and kernels (0 = CPU threads);
                              one grammar, 1/0 true/false yes/no on/off
    OCTOPUS_CUDA_DEVICE       CUDA device index (the current device)
    OCTOPUS_CPU_THREADS       CPU logical workers (auto = the process default);
                              pair it with julia --threads=N; per RANK under
                              OCTOPUS_USE_MPI=1
    OCTOPUS_USE_MPI           1|0 (0): run divided across MPI ranks under a
                              launcher, one Octopus process per rank with
                              OCTOPUS_CPU_THREADS logical workers each
                              (MultiProcessExecutionPolicy); loads Octopus as
                              a PACKAGE (the paragraph below). Refused with
                              OCTOPUS_USE_GPU=1: the multi-process policy
                              composes the CPU policy and is CPU storage only
    OCTOPUS_RANKS             with OCTOPUS_USE_MPI=1: the rank count the run
                              must match (auto = whatever the launcher
                              started); the policy rejects a communicator of
                              another size and never adjusts. Refused without
                              OCTOPUS_USE_MPI=1, where it would go unread --
                              and `mpiexec -n P` with the switch off would
                              run P whole simulations on one artifact path
    OCTOPUS_RECORD_TURN_TIMES 1|0 (0): clock every complete turn (the task's
                              `record_turn_times`, read back with
                              `turn_timings`); every rank prints its own
                              series and the summary line gains
                              steady_ms_per_turn (below). Off by default: on
                              CUDA it synchronizes at every turn boundary and
                              perturbs the throughput it measures
    OCTOPUS_TURN_TIMING_PATH  with OCTOPUS_RECORD_TURN_TIMES=1: write the
                              series as a TSV with the header row
                              turn<TAB>seconds<TAB>max_over_ranks_seconds --
                              turn 1..T of this call; seconds = rank 0's own
                              clock of the turn; max_over_ranks_seconds = the
                              maximum over the ranks, which is the turn's
                              wall time (equal to seconds at one rank).
                              Written by rank 0 only; a relative path
                              resolves against the repository root, never
                              into OCTOPUS_RESULT_DIR (the suite asserts rank
                              0's result directory holds exactly one file).
                              Refused without OCTOPUS_RECORD_TURN_TIMES=1, and
                              refused when set but empty
    OCTOPUS_NOISE_RULE        white|pink|table|spectral|none (white)
    OCTOPUS_NOISE_SCALE       multiplies both rms values (1.0); amplitude sweeps
    OCTOPUS_PHASE_RMS         rms of the RF phase offset per active harmonic,
                              rad (10e-6). ZERO MEANS NO RULE on the phase:
                              every `phase_noise` slot is `nothing`, not a
                              zero-sigma rule (an amplitude-only run)
    OCTOPUS_STRENGTH_REL_RMS  relative rms of the kick strength per active
                              harmonic (1e-4): the strength rule's sigma
                              DIRECTLY (times OCTOPUS_NOISE_SCALE), no
                              |strengthX[i]| factor -- a realised value d is
                              a dimensionless relative factor scaling BOTH
                              planes' strengths of its harmonic,
                              strengthX[i] (1 + d) and strengthY[i] (1 + d),
                              one voltage driver per cavity (owner decision,
                              relative since 2026-10-15; the vertical
                              strength is zero here and stays exactly zero,
                              so amplitude noise alone excites no vertical
                              growth without beam-beam). ZERO MEANS NO RULE
                              on the strength (a phase-only run)
    OCTOPUS_CHROMATICITY      <xi_x>,<xi_y> of the ChromaticityKickSpec
                              (2.0,2.0; the kbb = 0 controls use 0,0)
    OCTOPUS_PINK_OCTAVES      the pink rule's octave count (16); read by the
                              pink rule only, inert otherwise
    OCTOPUS_TABLE_SEED        seed of the synthetic table's generator
                              (20261014), a Random.Xoshiro independent of the
                              tracker's counter RNG; read by the table rule
                              without OCTOPUS_TABLE_FILE only, inert otherwise
                              (refused together with the file; the spectral
                              rule keys on OCTOPUS_SEED and the slot's rng_id
                              like the white and pink rules). The synthetic
                              record is Gaussian white of the stated rms with
                              exactly OCTOPUS_TURNS entries (the task refuses
                              a table shorter than the run and never wraps
                              one), one substream per slot, drawn in slot
                              order tccb phase 1, 2, tccb strength 1, 2, tcca
                              phase 1, 2, tcca strength 1, 2 (active slots
                              only); the sample rms of every table slot over
                              the run's turns is printed
    OCTOPUS_TABLE_FILE        with OCTOPUS_NOISE_RULE=table: a TSV whose
                              header row holds slot labels of the form
                              <cavity>_phase_noise_<i> / <cavity>_strength_noise_<i>
                              (cavity tccb or tcca, i an active harmonic, 1 or
                              2 here) and whose rows, one per ABSOLUTE turn
                              from turn 0, hold the per-turn values in the
                              slot's unit (offsets in rad on a phase column;
                              dimensionless relative factors d on a strength
                              column, realised as S (1 + d)),
                              Float64 printed at full precision (`repr`, or
                              C's %.17g: `parse(Float64, s)` round-trips both
                              exactly). The table rules take their offsets
                              from the file, unscaled, instead of the
                              synthetic record; each table is named by its
                              column label. Refused: a file with fewer rows
                              than OCTOPUS_TURNS, a label outside the form
                              above or naming an inactive harmonic, a
                              duplicate label, a missing column for an active
                              slot, a non-numeric entry, the file without
                              OCTOPUS_NOISE_RULE=table, OCTOPUS_NOISE_SCALE
                              other than 1 with the file, OCTOPUS_TABLE_SEED
                              with the file. A valid column this run does not
                              need (its parameter has rms 0) is reported as
                              unused. Purpose: a white run's realised values
                              (exactly sigma times its draws, which the white
                              rule applies to the nominal as one Float64:
                              added to a phase, scaling a strength) fed back
                              through the table rule track bit for bit; a
                              measured LLRF record is passed the same way
    OCTOPUS_SPECTRUM          with OCTOPUS_NOISE_RULE=spectral: the target
                              spectrum's preset, flat|pink (pink), of the
                              `SpectralNoise` rule each slot carries
                              (docs/design/spectral_turn_table.md) -- a rule
                              parallel to WhiteNoise and PinkNoise (the same
                              explicit rng_id per slot, the run's seed
                              OCTOPUS_SEED) that resolves when the line
                              compiles into a TurnTable of OCTOPUS_TURNS
                              entries: bin amplitudes sqrt(S(f_k)) over the
                              band (fixed, or Rayleigh-scattered, below), bin
                              phases from the counter RNG keyed on (seed,
                              rng_id, slot, bin), rms sigma by the analytic
                              normalisation, and the library factory's
                              canonical name in the provenance. Presets only
                              here; a custom `"label" => S` spectrum is the
                              example's and the library's. Refused under any
                              other rule, where it would go unread
    OCTOPUS_BAND              with OCTOPUS_NOISE_RULE=spectral: <lb>,<ub>, the
                              band in cycles per turn (the example's default,
                              1/2^16,0.5: the pink rule's 16 octaves, so the
                              two rules compare at equal rms and band). Parsed
                              here, judged by the factory: it refuses a band
                              outside 0 < lb < ub <= 1/2 or one holding no bin
                              at OCTOPUS_TURNS (the first bin is 1/OCTOPUS_TURNS,
                              so a narrow band needs a long run: 3e-3,4e-3
                              holds its first bin from 250 turns and 32 bins
                              from 32000) and warns below 32 bins. Refused
                              under any other rule, where it would go unread
    OCTOPUS_SPECTRAL_AMPLITUDES
                              with OCTOPUS_NOISE_RULE=spectral: fixed|rayleigh
                              (fixed), the factory's `amplitudes`. fixed puts
                              every bin at its target amplitude, so the rms
                              over the table's period and the periodogram per
                              bin are exact up to rounding; rayleigh draws
                              Rayleigh-distributed amplitudes about the
                              target, the stationary Gaussian process whose
                              EXPECTED rms is sigma and whose bin powers
                              scatter exponentially about the target spectrum
                              (Q3 of the design note, decided 2026-10-16).
                              Refused under any other rule, where it would go
                              unread
    OCTOPUS_KBB_SCALE         multiplies the beam-beam strength kbb (1.0);
                              0.0 switches the kick off while the luminosity
                              bookkeeping (klum) stays, so the noise-only
                              emittance growth is measured with the same
                              observers
    OCTOPUS_RADIATION         1|0 (1): with 0 the lumped radiation element is
                              omitted from the line, so the only stochastic
                              drive is the crab noise
    OCTOPUS_SEED              the task seed (123456789, the example's); names
                              the output directory
    OCTOPUS_RESULT_DIR        output root (test/result beside the tests, as
                              the weak-strong harness; the clean example
                              writes the same layout under the repo-root
                              result/); the artifact is
                              <result_dir>/<seed>/<case_name>.h5. Prefer a
                              local disk for long runs: the per-turn observer
                              write on a networked filesystem costs
                              milliseconds per turn
    OCTOPUS_CASE_NAME         the artifact's basename; derived when unset as
                              crab_noise_<rule>_x<scale>, plus _kbb<k> when
                              OCTOPUS_KBB_SCALE is not 1 (_kbb0 for 0.0) and
                              _norad when OCTOPUS_RADIATION=0, so sweeps and
                              toggles never collide on the path. A phase-only
                              or amplitude-only run, a chromaticity or a file
                              table do NOT change the derived name: set
                              OCTOPUS_CASE_NAME for those sweeps
    OCTOPUS_MOMENT_STEP       turns between moment rows (1); row 1 is turn 0
    OCTOPUS_RECORD_TURN_MODULATION
                              1|0 (1): the artifact's `record_turn_modulation`
                              option (`?RunArtifact`, docs/design/
                              turn_modulation_record.md): record the per-turn
                              OFFSETS every active noise slot produced as the
                              `series` dataset beside the cavity's provenance,
                              one row per turn -- rad on a phase slot, the
                              dimensionless relative factor d on a strength
                              slot -- the very values the element used (one
                              evaluation, shared; nothing in the tracking
                              changes). ON by default here, as in the example
                              (the library's default is off: 8 bytes per
                              active slot per turn). When on, rank 0 reads the
                              series back through the public reader and
                              REFUSES the run, with the numbers, unless every
                              active slot of this run recorded a series of
                              exactly OCTOPUS_TURNS entries; every white
                              series has rms within max(10 %, 5/sqrt(2 T)) of
                              its sigma (the one-sigma of an rms over T iid
                              normals is 1/sqrt(2T), so 10 % is a 5-sigma
                              band from T = 1250 on and the band widens below
                              that to stay at 5 sigma -- at the suite's 2
                              turns a bare 10 % pin would fail 85 % of the
                              time on correct code); and every table series
                              equals its record's first T entries bitwise -- a
                              spectral slot's too, its record being the table
                              the library's factory builds under the run's
                              seed, the slot's rng_id and the slot index
                              (what the rule must have resolved to), with the
                              provenance carrying that table's canonical name
                              (seed and rng_id asserted by name), and
                              with fixed amplitudes its rms equals sigma
                              within 1e-9 relative, the normalisation being
                              analytic over the table's whole period, which
                              the run covers since the table is exactly T
                              long (a partial period would be printed without
                              a pin and say so); with rayleigh amplitudes the
                              ratio is printed with the band 1 +- 1/(2 sqrt(K)),
                              K the band's bin count -- the one-sigma of a
                              FLAT band's rms about the expected sigma (a
                              sloped band concentrates its weight in fewer
                              bins and wanders more) -- and no pin. A
                              pink series' rms is printed with its ratio and
                              no pin: the band-limited sum's finite-run rms
                              wanders with its slow generators (one sigma
                              7.65 % at 2^16 turns; the verdict is
                              validation/crab_cavity_noise_response.jl part
                              `noise`, over 2^20 turns). When off, every slot
                              must read back `series === nothing`, or the run
                              is refused: a series written unasked is a
                              configuration the code did not read

Refused by name, because a non-default request this file would silently drop
is a defect rather than a typo: OCTOPUS_MP (the dead spelling the frozen
docs/history/production_benchmark_2026_09_06.md names; refused on presence,
as the weak-strong harness does; the switch is OCTOPUS_USE_MPI), OCTOPUS_RANKS
without OCTOPUS_USE_MPI=1, OCTOPUS_TURN_TIMING_PATH without
OCTOPUS_RECORD_TURN_TIMES=1 or set but empty, OCTOPUS_SPECTRUM, OCTOPUS_BAND
or OCTOPUS_SPECTRAL_AMPLITUDES without OCTOPUS_NOISE_RULE=spectral, and
OCTOPUS_USE_GPU=1 together with OCTOPUS_USE_MPI=1.

OCTOPUS_USE_MPI=1 needs an environment where BOTH Octopus and MPI resolve as
PACKAGES. MultiProcessExecutionPolicy reaches a communicator only through the
OctopusMPIExt package extension, and an extension does not load for the
`include` of src/Octopus.jl this harness uses by default -- so the switch loads
Octopus as a package instead and refuses to run if the extension is still
absent. Without it every rank would be its own communicator of one, which
OCTOPUS_RANKS=auto accepts, and every process would track the whole beam and
write the one artifact path (the weak-strong harness's header;
docs/experiences.md, "A weak dependency's extension does not exist for an
`include`d module"). What divides and what does not: the turn-modulation
rules are stateless functions of the absolute turn, realised identically on
every rank's host, so every rank applies the same noise; the beam is drawn
whole on every rank and sharded on chunk boundaries, and each particle's
counter-RNG streams key on its GLOBAL slot, so the tracked coordinates are the
undivided run's bit for bit; the luminosity folds on the fixed chunk grid in
chunk order and is bit for bit too; the moment observer reduces one serial sum
per rank and then across the ranks in rank order, so its columns are NOT
promised bit for bit against the undivided run (`_masked_global_sum` in
src/policies/Policies.jl records the trade: the masking invariant won over
cross-rank bitwise agreement, priced at the accumulation difference between
one serial sum and P of them). Under MPI every rank prints its `mpi_rank = r
of P` line and the configuration it read; rank 0 alone holds the artifact
(the library gates the file itself), so the receipt, the provenance, the
emittances and the CRAB-NOISE line are printed by rank 0 only, and the other
ranks end with one line each.

Examples:

    OCTOPUS_TURNS=200 OCTOPUS_N_MACRO=20000 OCTOPUS_USE_GPU=1 julia --project=. test/examples/crab_cavity_noise.jl
    OCTOPUS_NOISE_RULE=pink OCTOPUS_NOISE_SCALE=10 julia --project=. test/examples/crab_cavity_noise.jl
    OCTOPUS_NOISE_RULE=none OCTOPUS_RADIATION=0 julia --project=. --threads=4 test/examples/crab_cavity_noise.jl
    OCTOPUS_STRENGTH_REL_RMS=0 OCTOPUS_KBB_SCALE=0 OCTOPUS_CHROMATICITY=0,0 OCTOPUS_RADIATION=0 OCTOPUS_CASE_NAME=C1 OCTOPUS_TURNS=100000 OCTOPUS_USE_GPU=1 julia --project=. test/examples/crab_cavity_noise.jl
    OCTOPUS_NOISE_RULE=table OCTOPUS_TABLE_FILE=result/w1_offsets.tsv OCTOPUS_STRENGTH_REL_RMS=0 OCTOPUS_CASE_NAME=T1 julia --project=. test/examples/crab_cavity_noise.jl
    OCTOPUS_NOISE_RULE=spectral OCTOPUS_SPECTRUM=flat OCTOPUS_BAND=3e-3,4e-3 OCTOPUS_TURNS=65536 OCTOPUS_N_MACRO=1024 julia --project=. test/examples/crab_cavity_noise.jl
    OCTOPUS_NOISE_RULE=spectral OCTOPUS_SPECTRUM=pink OCTOPUS_SPECTRAL_AMPLITUDES=rayleigh OCTOPUS_TURNS=65536 julia --project=. test/examples/crab_cavity_noise.jl
    OCTOPUS_USE_MPI=1 OCTOPUS_RANKS=2 OCTOPUS_CPU_THREADS=4 OCTOPUS_TURNS=200 OCTOPUS_N_MACRO=20000 OCTOPUS_RECORD_TURN_TIMES=1 OCTOPUS_TURN_TIMING_PATH=result/timing_2ranks.tsv mpiexec -n 2 julia --project=. --threads=4 test/examples/crab_cavity_noise.jl

CUDA checks:

    julia --project=. -e 'using CUDA; println(CUDA.functional()); println(CUDA.has_cuda_gpu())'

Outputs: ONE run artifact, `<result_dir>/<seed>/<case_name>.h5`
(docs/design/run_artifact.md) -- `/luminosity/strong_beam_1`,
`/moments/weak_beam`, the `/execution` ledger and, for a modulated run,
`/turn_modulation/<ledger row>` (with OCTOPUS_RECORD_TURN_MODULATION=1 the
`series` dataset per cavity: one row per turn, one column per active slot);
read through one handle, `read(TaskOutput(path), kind; name = ...)` (the
series: `read(out, :turn_modulation)[1].elements[k].slots[j].series`, or
`turn_modulation_provenance(path)`); plus the TSV of
OCTOPUS_TURN_TIMING_PATH when asked for. The run prints the policy, the
`:turn_modulation` execution receipt, the artifact's provenance per element
and slot (the two cavities labelled by the line order this file owns, tccb
before tcca, because the record itself names only the element type), one
`series <label>: ...` line per recorded slot (its entry count, rms, sigma,
ratio and the band or bitwise verdict applied), and ends with the one line
the validation driver parses (rank 0's under MPI):

    CRAB-NOISE rule=<r> scale=<s> phase_rms=<rad> strength_rel_rms=<rel> chrom=<xi_x>,<xi_y> table_file=<path|none> turns=<T> n_macro=<N> kbb_scale=<k> radiation=<0|1> seed=<seed> artifact=<path> eps_x_first=<..> eps_x_last=<..> eps_y_first=<..> eps_y_last=<..> lumi_mean=<..> wall_s=<..> ms_per_turn=<..> ranks=<P> threads=<n|NA> steady_ms_per_turn=<ms|NA> record=<true|false> [rms_<cavity>_<parameter>_<i>=<rms> ...] spectrum=<flat|pink|none> band=<lb>,<ub>|none amplitudes=<fixed|rayleigh|none>

where the fields through steady_ms_per_turn are the line as it was before
the recording landed (2026-10-15), so a parser of `key=value` tokens
(validation/crab_cavity_noise_response.jl, profiling/
crab_cavity_noise_backends.jl) reads the same fields; record is
OCTOPUS_RECORD_TURN_MODULATION as read, and with it on one `rms_<label>`
field per recorded slot follows, in slot order, the label the
OCTOPUS_TABLE_FILE columns use (`tccb_phase_noise_1`, ...; absent with the
switch off or under rule none); spectrum, band and amplitudes close the line
(added after every earlier field, 2026-10-16): under rule spectral the
preset, the band in cycles per turn and the amplitudes as read, none under
every other rule. phase_rms and strength_rel_rms are the EFFECTIVE values that ran:
OCTOPUS_*_RMS times OCTOPUS_NOISE_SCALE when the parameter carries rules, 0
when it carries none (rms 0, or rule none); strength_rel_rms is the strength
rule's sigma itself, the relative rms of S (1 + d); with a file table they
are the selectors that activated the slots, and the values are the file's. The
emittances are the rms emittances from the artifact's central second moments,
eps_x = sqrt(<x^2><px^2> - <x px>^2) from the columns m200000, m020000,
m110000 of /moments/weak_beam and eps_y likewise from m002000, m000200,
m001100 (`?Moment`), at the first and the last recorded moment row; lumi_mean
is the mean of /luminosity/strong_beam_1 over the run; wall_s is the wall
time of the one `execute!` call (rank 0's under MPI), the JIT compilation of
its first turn included, and ms_per_turn = 1000 wall_s / turns -- an upper
bound, JIT-polluted by construction and kept as it is; ranks is the
communicator size the run RECORDED in its `:multi_process_communicator`
receipt (1 single-process), checked against MPI's own world; threads is the
per-process CPU logical-worker count the policy resolved (OCTOPUS_CPU_THREADS,
`auto` = the default pool), NA on CUDA, whose thread count is the launch
geometry's; steady_ms_per_turn is 1000 times the median over turns 21..T of
the per-turn wall time (max_over_ranks_seconds of the timing file, the slowest
rank's clock) when OCTOPUS_RECORD_TURN_TIMES=1 and T > 20, NA otherwise -- the
figure to compare across rank counts, free of the first turn's JIT and the
warm-up. The paths contain no spaces by construction of the derived names; an
OCTOPUS_CASE_NAME, OCTOPUS_RESULT_DIR or OCTOPUS_TABLE_FILE with a space would
break the line's parser.
=#

"""
Parse a boolean `OCTOPUS_*` switch, rejecting anything it does not recognise:
the one grammar the weak-strong and strong-strong harnesses use
(test/examples/weak_strong_tracking.jl), so `OCTOPUS_USE_GPU=true` enables
CUDA here as it does there rather than silently running on the CPU.
"""
function env_bool(key::AbstractString, default::Bool)
    raw = get(ENV, key, default ? "1" : "0")
    lowered = lowercase(strip(raw))
    lowered in ("1", "true", "yes", "on") && return true
    lowered in ("0", "false", "no", "off") && return false
    error("$(key)=$(repr(raw)) is not a boolean; use 1/0, true/false, yes/no or on/off")
end

"""
Parse a numeric `OCTOPUS_*` variable as `T`, naming the VARIABLE and the value
on failure. A bare `parse(Int, ENV[...])` names only the value it choked on,
and a sweep driver setting a dozen numeric variables then has to guess which
one it misspelt; every numeric variable of this harness goes through here.
"""
function env_parse(::Type{T}, key::AbstractString, default::AbstractString) where {T<:Real}
    raw = get(ENV, key, default)
    value = tryparse(T, strip(raw))
    value === nothing && error("$(key)=$(repr(raw)) is not a $(T)")
    return value
end

# The dead spelling, refused on presence as the weak-strong harness refuses it
# (its header says why: the frozen 2026-09-06 record names it). The switch
# this harness reads is OCTOPUS_USE_MPI, read next.
haskey(ENV, "OCTOPUS_MP") && error(
    "OCTOPUS_MP is not a switch this harness reads. The multi-process switch is " *
    "OCTOPUS_USE_MPI=1, matching OCTOPUS_USE_GPU; OCTOPUS_RANKS and " *
    "OCTOPUS_CPU_THREADS are spelled as you have them. OCTOPUS_MP is what the " *
    "scratch copies behind docs/history/production_benchmark_2026_09_06.md used, " *
    "and that record is frozen, so it still names the old spelling.")

# OCTOPUS_USE_MPI=1 runs this harness divided across MPI ranks -- the
# weak-strong harness's arm, with its semantics (brought here 2026-10-14; until
# then this file refused the switch by name). Read BEFORE Octopus is loaded
# because it decides HOW Octopus is loaded: `MultiProcessExecutionPolicy`
# reaches a communicator only through the `OctopusMPIExt` package extension,
# and an extension attaches only to a PACKAGE, which the default `include` of
# src/Octopus.jl into `Main` is not (docs/experiences.md, "A weak dependency's
# extension does not exist for an `include`d module"). With the switch off this
# is the same `include` the suite has always run. The suite's MPI testset
# classifies the harnesses under test/examples/ by the exact text of the next
# line, so it is spelled as the weak-strong harness spells it.
use_mpi = env_bool("OCTOPUS_USE_MPI", false)
if use_mpi
    # A Main.Octopus that came from an `include` cannot be turned into the
    # package: Julia 1.12 makes `using Octopus` a hard error here ("importing
    # Octopus into Main conflicts with an existing global"), which is loud but
    # says nothing about the cause. Say it here instead.
    if isdefined(Main, :Octopus) && Base.PkgId(Main.Octopus).uuid === nothing
        error("OCTOPUS_USE_MPI=1 needs Octopus loaded as a PACKAGE, because the " *
              "OctopusMPIExt extension attaches only to a package -- but " *
              "Main.Octopus is already an `include`d module (its PkgId carries no " *
              "UUID). Either drop the earlier `include` of src/Octopus.jl and let " *
              "this harness load the package, or `using Octopus` before including " *
              "this file.")
    end
    using Octopus
    using MPI
    # Idempotent through `Initialized()`, and the extension's own activation
    # makes exactly this call; doing it here makes this process's rank
    # available to this file before `execute!` rather than only after it.
    MPI.Initialized() || MPI.Init(threadlevel = :funneled)
elseif !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "..", "src", "Octopus.jl"))
end
using .Octopus
import Random
if use_mpi && Base.get_extension(Main.Octopus, :OctopusMPIExt) === nothing
    error("OCTOPUS_USE_MPI=1, but OctopusMPIExt did not load. Every rank would " *
          "then be its own communicator of one and each would run the WHOLE " *
          "simulation, racing on one artifact path and reporting plausible " *
          "timings. Run this harness against an environment where Octopus and " *
          "MPI both resolve as packages, and do not pre-`include` src/Octopus.jl " *
          "into Main before it.")
end
# This process's place in the launcher's world, read from the COMMUNICATOR and
# not from Octopus's `_mp_rank()`, which reads the policy in force and answers
# 0 on every rank outside an execution scope (docs/experiences.md, "A
# collective outside its scope is a silent no-op"). 1 and 0 single-process.
# Printed first, so every rank's lines below follow its own.
mpi_nranks = use_mpi ? MPI.Comm_size(MPI.COMM_WORLD) : 1
mpi_rank = use_mpi ? MPI.Comm_rank(MPI.COMM_WORLD) : 0
use_mpi && println("mpi_rank = ", mpi_rank, " of ", mpi_nranks)

# Run size.
turns = env_parse(Int, "OCTOPUS_TURNS", "2")
n_macro = env_parse(Int, "OCTOPUS_N_MACRO", "10000")
turns >= 1 || error("OCTOPUS_TURNS=$(turns) must be at least 1")
n_macro >= 1 || error("OCTOPUS_N_MACRO=$(n_macro) must be at least 1")

# The noise configuration.
rule_text = lowercase(strip(get(ENV, "OCTOPUS_NOISE_RULE", "white")))
rule_text in ("white", "pink", "table", "spectral", "none") || error(
    "OCTOPUS_NOISE_RULE=$(repr(rule_text)) is not one of white, pink, table, spectral, none")
noise_rule_kind = Symbol(rule_text)
noise_scale = env_parse(Float64, "OCTOPUS_NOISE_SCALE", "1.0")
phase_rms = env_parse(Float64, "OCTOPUS_PHASE_RMS", "10e-6")
strength_rel_rms = env_parse(Float64, "OCTOPUS_STRENGTH_REL_RMS", "1e-4")
pink_octaves = env_parse(Int, "OCTOPUS_PINK_OCTAVES", "16")
table_seed = env_parse(Int, "OCTOPUS_TABLE_SEED", "20261014")
table_file = get(ENV, "OCTOPUS_TABLE_FILE", "")
# The synthetic table is exactly as long as the run: the task refuses a
# shorter one and never wraps one, so this is the smallest record that serves
# the window.
table_turns = turns
(isfinite(noise_scale) && noise_scale >= 0) || error("OCTOPUS_NOISE_SCALE=$(noise_scale) must be finite and non-negative")
(isfinite(phase_rms) && phase_rms >= 0) || error("OCTOPUS_PHASE_RMS=$(phase_rms) must be finite and non-negative")
(isfinite(strength_rel_rms) && strength_rel_rms >= 0) || error("OCTOPUS_STRENGTH_REL_RMS=$(strength_rel_rms) must be finite and non-negative")
if !isempty(table_file)
    noise_rule_kind === :table || error(
        "OCTOPUS_TABLE_FILE is read only with OCTOPUS_NOISE_RULE=table; got " *
        "OCTOPUS_NOISE_RULE=$(rule_text), under which the file would go unread")
    noise_scale == 1 || error(
        "OCTOPUS_NOISE_SCALE=$(noise_scale) with OCTOPUS_TABLE_FILE: the file's offsets " *
        "are used as they are, so a scale other than 1 would go unapplied; scale " *
        "the record you write instead")
    haskey(ENV, "OCTOPUS_TABLE_SEED") && error(
        "OCTOPUS_TABLE_SEED with OCTOPUS_TABLE_FILE: the file replaces the synthetic " *
        "record, so the seed would go unread")
    isfile(table_file) || error("OCTOPUS_TABLE_FILE=$(repr(table_file)) is not a file")
end
# The spectral rule's target spectrum and band (OCTOPUS_SPECTRUM,
# OCTOPUS_BAND; the header): presets only here, and refused under any other
# rule, where a value nothing reads would be the config-that-was-never-read
# defect class rather than a typo.
if noise_rule_kind !== :spectral
    for key in ("OCTOPUS_SPECTRUM", "OCTOPUS_BAND", "OCTOPUS_SPECTRAL_AMPLITUDES")
        haskey(ENV, key) && error(
            "$(key)=$(repr(ENV[key])) is read only with OCTOPUS_NOISE_RULE=spectral; got " *
            "OCTOPUS_NOISE_RULE=$(rule_text), under which it would go unread")
    end
end
spectrum_text = lowercase(strip(get(ENV, "OCTOPUS_SPECTRUM", "pink")))
spectrum_text in ("flat", "pink") || error(
    "OCTOPUS_SPECTRUM=$(repr(spectrum_text)) is not one of flat, pink (the presets; a custom " *
    "\"label\" => S spectrum is the example's and the library's, not this harness's)")
spectrum = Symbol(spectrum_text)
amplitudes_text = lowercase(strip(get(ENV, "OCTOPUS_SPECTRAL_AMPLITUDES", "fixed")))
amplitudes_text in ("fixed", "rayleigh") || error(
    "OCTOPUS_SPECTRAL_AMPLITUDES=$(repr(amplitudes_text)) is not one of fixed, rayleigh")
spectral_amplitudes = Symbol(amplitudes_text)
# OCTOPUS_BAND, <lb>,<ub> in cycles per turn; the example's default band when
# unset (the :pink rule's 16 octaves, f_rev/2^16 to f_rev/2). Parsed here,
# judged by the factory, whose refusals name the band, the turns and the
# first bin: a band outside 0 < lb < ub <= 1/2, or one with no bin at
# OCTOPUS_TURNS; fewer than 32 bins is a warning, not a refusal.
band = if haskey(ENV, "OCTOPUS_BAND")
    band_env = ENV["OCTOPUS_BAND"]
    band_parts = split(band_env, ',')
    length(band_parts) == 2 || error(
        "OCTOPUS_BAND=$(repr(band_env)) must be two comma-separated numbers <lb>,<ub> in cycles per turn")
    band_values = map(band_parts) do part
        v = tryparse(Float64, strip(part))
        v === nothing && error("OCTOPUS_BAND=$(repr(band_env)): $(repr(String(part))) is not a Float64")
        v
    end
    all(isfinite, band_values) || error("OCTOPUS_BAND=$(repr(band_env)) must be finite")
    (band_values[1], band_values[2])
else
    (1.0 / 2^16, 0.5)
end
# Rms 0 means NO rule on that parameter (every slot `nothing`), not a
# zero-sigma rule; rule none means no rule on either. These are the EFFECTIVE
# values the summary line reports.
phase_sigma = noise_rule_kind === :none ? 0.0 : phase_rms * noise_scale
strength_sigma_rel = noise_rule_kind === :none ? 0.0 : strength_rel_rms * noise_scale
phase_on = phase_sigma > 0
strength_on = strength_sigma_rel > 0

# The chromaticity, <xi_x>,<xi_y>: one variable, two numbers, each named with
# the whole value on failure.
chrom_text = get(ENV, "OCTOPUS_CHROMATICITY", "2.0,2.0")
chrom_parts = split(chrom_text, ',')
length(chrom_parts) == 2 || error(
    "OCTOPUS_CHROMATICITY=$(repr(chrom_text)) must be two comma-separated numbers <xi_x>,<xi_y>")
chrom_values = map(chrom_parts) do part
    v = tryparse(Float64, strip(part))
    v === nothing && error(
        "OCTOPUS_CHROMATICITY=$(repr(chrom_text)): $(repr(String(part))) is not a Float64")
    v
end
chromaticity = (chrom_values[1], chrom_values[2])
all(isfinite, chromaticity) || error("OCTOPUS_CHROMATICITY=$(repr(chrom_text)) must be finite")

# The A/B toggles.
kbb_scale = env_parse(Float64, "OCTOPUS_KBB_SCALE", "1.0")
isfinite(kbb_scale) || error("OCTOPUS_KBB_SCALE=$(kbb_scale) must be finite")
use_radiation = env_bool("OCTOPUS_RADIATION", true)
moment_step = env_parse(Int, "OCTOPUS_MOMENT_STEP", "1")
moment_step >= 1 || error("OCTOPUS_MOMENT_STEP=$(moment_step) must be at least 1")
# The artifact's `record_turn_modulation` (header): on by default, as the
# example's `output` block has it; read back and checked on rank 0 below.
record_turn_modulation = env_bool("OCTOPUS_RECORD_TURN_MODULATION", true)

# The multi-process and timing switches (the weak-strong harness's, with its
# semantics), each read here so a bad value fails before any work -- and each
# refused where it would go unread, because a set variable nothing reads is
# the config-that-was-never-read defect class, not a typo.
use_mpi || !haskey(ENV, "OCTOPUS_RANKS") || error(
    "OCTOPUS_RANKS=$(repr(ENV["OCTOPUS_RANKS"])) without OCTOPUS_USE_MPI=1: the rank count is " *
    "read only by the multi-process arm, so it would go unread -- and under a " *
    "launcher a single-process run on every rank is P whole simulations racing " *
    "on one artifact path. Set OCTOPUS_USE_MPI=1 for a divided run.")
ranks_text = lowercase(strip(get(ENV, "OCTOPUS_RANKS", "auto")))
ranks = ranks_text == "auto" ? :auto : env_parse(Int, "OCTOPUS_RANKS", "auto")
record_turn_times = env_bool("OCTOPUS_RECORD_TURN_TIMES", false)
turn_timing_path = get(ENV, "OCTOPUS_TURN_TIMING_PATH", "")
# Set but empty would write nothing and say nothing: refused by name, like
# every other set variable this file cannot act on.
haskey(ENV, "OCTOPUS_TURN_TIMING_PATH") && isempty(strip(turn_timing_path)) && error(
    "OCTOPUS_TURN_TIMING_PATH is set but empty: name a file for the per-turn series " *
    "or unset the variable; an empty path would write nothing and say nothing.")
record_turn_times || !haskey(ENV, "OCTOPUS_TURN_TIMING_PATH") || error(
    "OCTOPUS_TURN_TIMING_PATH=$(repr(turn_timing_path)) without OCTOPUS_RECORD_TURN_TIMES=1: " *
    "no per-turn series is recorded, so nothing would be written there.")

scale_tag(s) = isinteger(s) ? string(Int(s)) : string(s)
default_case_name = "crab_noise_$(noise_rule_kind)_x$(scale_tag(noise_scale))" *
                    (kbb_scale == 1.0 ? "" : "_kbb" * scale_tag(kbb_scale)) *
                    (use_radiation ? "" : "_norad")

# Input for this weak-proton crab-crossing case: the example's numbers, which
# are the weak-strong example's. The run size comes from OCTOPUS_TURNS and
# OCTOPUS_N_MACRO above, never from a field here (an unread `total_turns` was
# the 2026-08-05_b audit's U21-24).
input = (
    case_name = get(ENV, "OCTOPUS_CASE_NAME", default_case_name),
    # OCTOPUS_RESULT_DIR: two concurrent runs used to clobber one another
    # silently (2026-08-05_b audit, U21-27).
    result_dir = get(ENV, "OCTOPUS_RESULT_DIR", joinpath(@__DIR__, "..", "result")),
    seed = env_parse(Int, "OCTOPUS_SEED", "123456789"),

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
        # HALF the full crossing angle (LorentzBoostSpec's convention).
        crossing_angle = 12.5e-3,
        tune = (0.228, 0.210, -0.01),
        # OCTOPUS_CHROMATICITY; the example's (2.0, 2.0) by default.
        chromaticity = chromaticity,
    ),

    crab_cavity = (
        frequency = 197.0e6,
        # (4/3, -1/3) is the two-harmonic compensation scheme; the third
        # harmonic has zero weight and carries no noise rule.
        harmonic_weights = (4.0 / 3.0, -1.0 / 3.0, 0.0),
        strength_y = (0.0, 0.0, 0.0),
        phase = (0.0, 0.0, 0.0),
    ),

    crab_noise = (
        rule = noise_rule_kind,
        phase_rms = phase_rms,
        strength_rel_rms = strength_rel_rms,
        scale = noise_scale,
        pink_octaves = pink_octaves,
        table_turns = table_turns,
        table_seed = table_seed,
        table_file = table_file,
        # OCTOPUS_SPECTRUM, OCTOPUS_BAND and OCTOPUS_SPECTRAL_AMPLITUDES; read
        # by the spectral rule only.
        spectrum = spectrum,
        band = band,
        amplitudes = spectral_amplitudes,
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
        # The artifact's batching knob (docs/history/
        # weak_strong_cuda_luminosity_2026_08_11.md); do not lower it on
        # shared storage.
        capacity = 1024,
        moment_start = 0,
        moment_step = moment_step,
    ),
)
isempty(input.case_name) && error("OCTOPUS_CASE_NAME is empty")

# Execution policy. CPU threads are the portable default; OCTOPUS_USE_GPU=1
# selects CUDA storage and kernels (the rules are realised on the host either
# way and uploaded with the element once per turn); OCTOPUS_USE_MPI=1 divides
# the beam across the launcher's ranks, each rank a CPU-threads process.
use_gpu = env_bool("OCTOPUS_USE_GPU", false)
# The multi-process policy composes the CPU policy and is CPU storage only, so
# there is no CUDA arm to divide; asking for both is a request one of the two
# switches would have to be silently dropped from.
use_gpu && use_mpi && error(
    "OCTOPUS_USE_GPU=1 and OCTOPUS_USE_MPI=1 together: MultiProcessExecutionPolicy " *
    "composes CPUThreadsExecutionPolicy and runs on CPU storage, so there is no " *
    "CUDA-plus-MPI mode to select. Choose one.")
if use_gpu
    import CUDA
    CUDA.functional(false) || error("OCTOPUS_USE_GPU=1 requested, but CUDA.functional(false) is false.")
end
policy = if use_gpu
    cuda_device = isempty(get(ENV, "OCTOPUS_CUDA_DEVICE", "")) ? nothing :
                  env_parse(Int, "OCTOPUS_CUDA_DEVICE", "")
    CUDAExecutionPolicy(device = cuda_device)
else
    cpu_threads_text = lowercase(strip(get(ENV, "OCTOPUS_CPU_THREADS", "auto")))
    cpu_threads = cpu_threads_text == "auto" ? :auto : env_parse(Int, "OCTOPUS_CPU_THREADS", "auto")
    if use_mpi
        # OCTOPUS_RANKS passes straight through as the policy's `ranks` with no
        # harness logic: the policy rejects a communicator whose size differs
        # from an explicit request and never adjusts; `auto` accepts whatever
        # `mpiexec -n` started.
        MultiProcessExecutionPolicy(threads = cpu_threads, ranks = ranks)
    else
        CPUThreadsExecutionPolicy(threads = cpu_threads)
    end
end
println("execution policy = ", nameof(typeof(policy)))
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

cn = input.crab_noise
N_harmonics = length(input.crab_cavity.harmonic_weights)
harmonic_active(i) = !iszero(input.crab_cavity.harmonic_weights[i])
# The slots this run needs, by file-column label `<cavity>_<parameter>_<i>`,
# in slot order: the file reader checks the file against this set.
needed_labels = String[]
for cavity in ("tccb", "tcca"), (parameter, on) in (("phase_noise", phase_on), ("strength_noise", strength_on))
    on || continue
    for i in 1:N_harmonics
        harmonic_active(i) && push!(needed_labels, "$(cavity)_$(parameter)_$(i)")
    end
end

# ---------------------------------------------------------------------------
# OCTOPUS_TABLE_FILE: the TSV of per-turn offsets, one column per slot label,
# read whole (a table longer than the run is fine; the task indexes absolute
# turns from entry 1) and checked against the slots this run activates.
# ---------------------------------------------------------------------------
file_tables = Dict{String,Vector{Float64}}()
if !isempty(table_file)
    lines = filter(l -> !isempty(strip(l)), readlines(table_file))
    length(lines) >= 2 || error("OCTOPUS_TABLE_FILE=$(table_file): a header row and at least one data row are needed")
    header = String.(strip.(split(lines[1], '\t')))
    nrows = length(lines) - 1
    nrows >= turns || error(
        "OCTOPUS_TABLE_FILE=$(table_file) holds $(nrows) data rows, fewer than the run's " *
        "OCTOPUS_TURNS=$(turns); the task refuses a table shorter than the run and never wraps one")
    label_re = r"^(tccb|tcca)_(phase_noise|strength_noise)_([0-9]+)$"
    for (c, label) in enumerate(header)
        m = match(label_re, label)
        m === nothing && error(
            "OCTOPUS_TABLE_FILE=$(table_file): column $(c) label $(repr(label)) is not of the form " *
            "<cavity>_phase_noise_<i> or <cavity>_strength_noise_<i> with cavity tccb or tcca")
        i = parse(Int, m.captures[3])
        (1 <= i <= N_harmonics && harmonic_active(i)) || error(
            "OCTOPUS_TABLE_FILE=$(table_file): column $(c) label $(repr(label)) names harmonic $(i), " *
            "which is not an active harmonic of this case (weights $(input.crab_cavity.harmonic_weights))")
        haskey(file_tables, label) && error(
            "OCTOPUS_TABLE_FILE=$(table_file): duplicate column label $(repr(label))")
        file_tables[label] = Vector{Float64}(undef, nrows)
    end
    for (r, line) in enumerate(@view lines[2:end])
        fields = split(line, '\t')
        length(fields) == length(header) || error(
            "OCTOPUS_TABLE_FILE=$(table_file): data row $(r) has $(length(fields)) fields, the header $(length(header))")
        for (c, label) in enumerate(header)
            v = tryparse(Float64, strip(fields[c]))
            v === nothing && error(
                "OCTOPUS_TABLE_FILE=$(table_file): data row $(r), column $(repr(label)): " *
                "$(repr(fields[c])) is not a Float64")
            file_tables[label][r] = v
        end
    end
    for label in needed_labels
        haskey(file_tables, label) || error(
            "OCTOPUS_TABLE_FILE=$(table_file) has no column $(repr(label)), which this run activates " *
            "(OCTOPUS_PHASE_RMS=$(phase_rms), OCTOPUS_STRENGTH_REL_RMS=$(strength_rel_rms)); columns present: " *
            join(repr.(header), ", "))
    end
    for label in header
        label in needed_labels || println("table_file column ", repr(label),
            " is unused in this run (its parameter carries no rule here)")
    end
    println("table_file = ", table_file, " (", nrows, " rows, ", length(header), " columns)")
end

# ---------------------------------------------------------------------------
# The noise rules, as the example builds them: per active harmonic i,
# `phase_noise[i]` with sigma = phase_rms * scale (rad, added to the phase)
# and `strength_noise[i]` with sigma = strength_rel_rms * scale, the relative
# rms itself (a realised value d scales both planes to S (1 + d); relative
# since 2026-10-15, no |strengthX[i]| factor); zero-weight harmonics
# stay inactive, and a parameter whose rms is 0 carries no rule at all.
# Explicit stream ids (tccb 10 + slot, tcca 20 + slot; slot = i for a phase,
# N + i for a strength; the beam claims 1, the radiation 2) keep the
# provenance record identical from run to run -- with the default `rng_id = 0`
# the id would come from a process-global counter and depend on construction
# order -- and disjoint between the cavities, because two elements sharing an
# id draw identical values. The strength factor scales BOTH planes' strengths
# of its harmonic, one voltage driver per cavity (the example's comment on
# the same lines); the vertical strength is zero here and stays exactly zero.
# ---------------------------------------------------------------------------
# The synthetic record's master generator exists only on the path that reads
# the seed: the table rule without a file (the header's "inert otherwise").
table_master = (cn.rule === :table && isempty(cn.table_file)) ? Random.Xoshiro(cn.table_seed) : nothing
table_slot_rms = Tuple{String,Float64}[]
# Every table rule's record, keyed by the file-column label
# `<cavity>_<parameter>_<i>` whatever its source (synthetic, file or
# spectral): the bitwise reference the recorded series is checked against on
# rank 0. For the spectral rule the record is the table the library's
# factory builds under the SAME keying the rule resolves with -- the run's
# global seed (`global_rng_seed()`, set from OCTOPUS_SEED above), the slot's
# rng_id and the slot index -- and `spectral_names` holds that table's
# canonical name, which the provenance must carry.
table_offsets = Dict{String,Vector{Float64}}()
spectral_names = Dict{String,String}()
spectral_ids = Dict{String,Int}()
function noise_rule(parameter::String, cavity::String, i::Int, sigma, rng_id)
    cn.rule === :white && return WhiteNoise(sigma; rng_id = rng_id)
    cn.rule === :pink && return PinkNoise(sigma; rng_id = rng_id, octaves = cn.pink_octaves)
    if cn.rule === :spectral
        # The spectral rule, parallel to the two above (the same explicit
        # rng_id, the run's global seed); it resolves when the line compiles
        # into a TurnTable of OCTOPUS_TURNS entries synthesised from the
        # preset over the band, rms sigma by the analytic normalisation, named
        # canonically (`spectral(<preset>; sigma=.., band=.., turns=..,
        # seed=.., rng_id=.., slot=..)`). The record below is the factory's own
        # output under that keying: what the compiled rule must have resolved
        # to, bit for bit, name included. The keying includes the SLOT the
        # rule sits in (phase harmonic i -> i, strength harmonic i -> N + i),
        # so one rng_id per cavity would still give independent tables per
        # slot, as it does for the white and pink rules.
        slot = parameter == "phase_noise" ? i : N_harmonics + i
        reference = spectral_turn_table(cn.spectrum, sigma, cn.band;
                                        turns = cn.table_turns, seed = global_rng_seed(),
                                        rng_id = rng_id, slot = slot, amplitudes = cn.amplitudes)
        offsets = reference.offsets
        label = "$(cavity)_$(parameter)_$(i) = $(reference.name)"
        spectral_names["$(cavity)_$(parameter)_$(i)"] = reference.name
        spectral_ids["$(cavity)_$(parameter)_$(i)"] = rng_id
        table = SpectralNoise(sigma, cn.band, cn.spectrum;
                              rng_id = rng_id, turns = cn.table_turns, amplitudes = cn.amplitudes)
    elseif isempty(cn.table_file)
        offsets = sigma .* randn(Random.Xoshiro(rand(table_master, UInt64)), cn.table_turns)
        label = "$(cavity)_$(parameter)[$(i)]_synthetic_white"
        table = TurnTable(offsets; name = label)
    else
        label = "$(cavity)_$(parameter)_$(i)"
        offsets = file_tables[label]
        table = TurnTable(offsets; name = label)
    end
    push!(table_slot_rms, (label, sqrt(sum(abs2, @view offsets[1:turns]) / turns)))
    table_offsets["$(cavity)_$(parameter)_$(i)"] = offsets
    return table
end
function crab_noise_rules(cavity::String, id_base::Int)
    phase = phase_on ? ntuple(N_harmonics) do i
        harmonic_active(i) || return nothing
        noise_rule("phase_noise", cavity, i, phase_sigma, id_base + i)
    end : ()
    strength = strength_on ? ntuple(N_harmonics) do i
        harmonic_active(i) || return nothing
        noise_rule("strength_noise", cavity, i, strength_sigma_rel,
                   id_base + N_harmonics + i)
    end : ()
    return (phase_noise = phase, strength_noise = strength)
end
tccb_noise = crab_noise_rules("tccb", 10)
tcca_noise = crab_noise_rules("tcca", 20)
println("crab_noise: rule = ", cn.rule,
        ", effective phase_rms = ", phase_sigma, " rad", phase_on ? "" : " (no phase rule)",
        ", effective strength_rel_rms = ", strength_sigma_rel, strength_on ? "" : " (no strength rule)",
        " (scale ", cn.scale, ")",
        cn.rule === :pink ? ", pink_octaves = $(cn.pink_octaves)" : "",
        cn.rule === :table && isempty(cn.table_file) ? ", synthetic table_turns = $(cn.table_turns), table_seed = $(cn.table_seed)" : "",
        cn.rule === :table && !isempty(cn.table_file) ? ", offsets from table_file" : "",
        cn.rule === :spectral ? ", spectrum = $(cn.spectrum), band = $(cn.band[1]),$(cn.band[2]) cycles/turn, " *
                                "amplitudes = $(cn.amplitudes), table_turns = $(cn.table_turns) " *
                                "(the bin phases keyed on the run's seed $(global_rng_seed()) and the slots' rng_ids, as the white and pink rules are)" : "",
        (phase_on || strength_on) ? "" : " -- every slot inactive")
for (label, rms) in table_slot_rms
    println("table slot ", label, ": sample rms over the run's ", turns, " turns = ", rms)
end
println("chromaticity = ", chromaticity)
println("kbb_scale = ", kbb_scale, kbb_scale == 0 ? "  (beam-beam kick OFF, luminosity bookkeeping kept)" : "")
println("radiation = ", use_radiation ? 1 : 0,
        use_radiation ? "" : "  (lumped radiation element omitted from the line)")

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
# OCTOPUS_KBB_SCALE scales the kick strength ONLY; `klum` keeps the luminosity
# channel alive at kbb_scale = 0, so the noise-only run and the colliding run
# are read through the same columns.
kbb = kbb_scale * wb.charge * strong.charge * strong.n_particle * weak_r0 * wb.mass / wb.energy
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
lumped_rad = LumpedRadSpec{Float64}(;
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

outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
artifact_path = normpath(joinpath(outdir, input.case_name * ".h5"))
moment_observer = ScheduledObserver(
    MomentObserver(; name = "weak_beam"),
    EveryNSteps(
        start = input.output.moment_start,
        step = input.output.moment_step,
    ),
)

# OCTOPUS_RADIATION=0 omits the lumped radiation element; everything else in
# the line is the example's, in the example's order.
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
    (use_radiation ? (lumped_rad,) : ())...,
    moment_observer,
)
# `policy = policy` is load-bearing (the weak-strong harness's note): without
# it `execute!` resolves a fresh default and OCTOPUS_USE_GPU, OCTOPUS_CUDA_DEVICE
# and OCTOPUS_CPU_THREADS would reach only `Beam(...)`. Under OCTOPUS_USE_MPI
# the inferred default is a single-process CPU policy, and what the library
# then does is this: the beam is already this rank's shard (built by the
# multi-process policy), and the run would track it AS IF IT WERE THE WHOLE
# BEAM -- global index offset 0, so the per-particle streams repeat across the
# ranks; every collective a serial passthrough, so the moments and the
# luminosity would be the shard's; every rank believing it is rank 0, so every
# rank would write the one artifact path. The only guard that fires is the
# launcher tripwire's WARNING (`_warn_launcher_without_policy`: "PMI_SIZE=P
# ... the execution policy in force is a single-process one"); the
# OCTOPUS_RANKS check runs only when the multi-process policy activates, which
# the inferred default never does. OCTOPUS_RECORD_TURN_TIMES is the task's own
# `record_turn_times` (`?TrackingTask`).
task = TrackingTask(line_specs;
    policy = policy,
    record_turn_times = record_turn_times,
    artifact = RunArtifact(artifact_path; capacity = input.output.capacity,
                           record_turn_modulation = record_turn_modulation))
# One `execute!`, timed whole (JIT of its first turn included), inside an
# execution audit so the `:turn_modulation` receipt can be read back.
t0 = time()
audit = with_execution_audit() do
    execute!(task, beam; turns = turns)
end
wall_s = time() - t0
ms_per_turn = 1000 * wall_s / turns

# What the run RECORDED about its division: the `:multi_process_communicator`
# receipt, written at activation from the communicator Octopus actually opened
# (nranks, rank, the per-rank worker count it resolved); a single-process run
# records none. The summary line's `ranks=` is that recorded count, checked
# against MPI's own world, so a policy that silently failed to divide cannot
# report the launcher's count as its own.
comm_receipts = filter(r -> r.consumer === :multi_process_communicator, execution_receipts(audit))
recorded_ranks = isempty(comm_receipts) ? 1 : Int(last(comm_receipts).values.nranks)
recorded_ranks == mpi_nranks || error(
    "the run recorded a communicator of $(recorded_ranks) rank(s) while MPI.COMM_WORLD holds " *
    "$(mpi_nranks): the policy in force did not divide over the launcher's world")
# The per-process CPU logical-worker count the policy RESOLVED (the
# configuration report's `:threads` entry: OCTOPUS_CPU_THREADS, or the default
# pool for `auto`), checked against the count the communicator receipt carries;
# NA on CUDA, whose `threads` is the launch geometry's, not a worker count.
threads_text = if use_gpu
    "NA"
else
    threads_entry = only(filter(e -> e.name === :threads, collect(configuration_report(policy))))
    if !isempty(comm_receipts) && Int(last(comm_receipts).values.threads) != threads_entry.resolved
        error("the communicator receipt records $(last(comm_receipts).values.threads) workers per " *
              "rank while the configuration report resolves $(threads_entry.resolved)")
    end
    string(threads_entry.resolved)
end

# OCTOPUS_RECORD_TURN_TIMES=1: the per-turn series the task clocked. PER RANK
# by the task's documented semantics: the INSTRUMENT adds no collective, each
# rank stamps its own clock at its own turn boundary, so every rank prints its
# own series. The turn itself is not independent per rank: the line's own
# per-turn collectives -- the luminosity's chunk fold every turn and the moment
# observer's reduction every recorded turn -- sit inside the clocked turn, so
# the slowest rank sets the turn, which is why the MAX over ranks is the turn's
# wall time. Reduced here with one max over MPI's own world after the run --
# outside Octopus's scope, where its collectives are passthroughs, but on
# MPI.COMM_WORLD, where this is a real collective that every rank issues (all
# ranks read the same switch). Exact: max associates freely.
series = turn_timings(task)
max_series = series
steady_text = "NA"
if record_turn_times
    length(series) == turns || error(
        "turn_timings(task) holds $(length(series)) entries for a $(turns)-turn run")
    println("turn_timings_seconds",
            mpi_nranks > 1 ? " (rank $(mpi_rank) shard of $(mpi_nranks); the turn's wall time is the max over ranks)" : "",
            " = ", series)
    use_mpi && (max_series = MPI.Allreduce(series, max, MPI.COMM_WORLD))
    # The steady figure: the median over turns 21..T of the turn's wall time,
    # after the first turn's JIT and the warm-up; NA when the run is too short
    # to have one, and said so.
    if turns > 20
        sorted_tail = sort(max_series[21:end])
        m = length(sorted_tail)
        steady_median = isodd(m) ? sorted_tail[(m + 1) ÷ 2] :
                                   (sorted_tail[m ÷ 2] + sorted_tail[m ÷ 2 + 1]) / 2
        steady_text = string(1000 * steady_median)
    else
        mpi_rank == 0 && println("steady_ms_per_turn = NA (needs more than 20 turns; this run has ", turns, ")")
    end
    if mpi_rank == 0 && !isempty(turn_timing_path)
        # Rank 0 alone writes: one path and P writers is a race. Relative
        # paths resolve against the repository, never into OCTOPUS_RESULT_DIR
        # (the suite asserts rank 0's result directory holds exactly one file).
        timing_file = isabspath(turn_timing_path) ? turn_timing_path :
                      normpath(joinpath(@__DIR__, "..", "..", turn_timing_path))
        mkpath(dirname(timing_file))
        open(timing_file, "w") do io
            println(io, "turn\tseconds\tmax_over_ranks_seconds")
            for i in 1:turns
                println(io, i, "\t", series[i], "\t", max_series[i])
            end
        end
        println("turn_timing_path = ", timing_file, " (", turns, " rows; seconds = rank 0's clock ",
                "of the turn, max_over_ranks_seconds = the slowest rank's, equal at one rank)")
    end
end

if mpi_rank != 0
    # Rank 0 alone holds the artifact (the library gates the file itself), so
    # the readback below is its; this rank tracked its shard and is done. Every
    # number printed below is whole-beam by construction -- the moment observer
    # reduces across the ranks, the luminosity folds across them -- so nothing
    # here needs the shard label the weak-strong harness puts on its
    # `beam_statistics` line, which this harness does not print.
    println("rank ", mpi_rank, " of ", mpi_nranks, ": shard tracked; rank 0 holds the artifact and prints the readback")
else
    println("turns = ", turns)
    println("n_macro = ", n_macro)
    println("artifact = ", artifact_path)
    println("  /luminosity/strong_beam_1, /moments/weak_beam, /execution",
            (phase_on || strength_on) ? ", /turn_modulation" : "")
    # The receipt and the provenance list the modulated elements in LINE ORDER
    # and name only the element type, so the two cavities read alike. This file
    # owns the line (tccb before tcca) and labels the entries by that order; the
    # labels are this file's, not something the record stores. The receipt is
    # per process and the same on every rank (the rules and the window are),
    # so it is printed once, here.
    modulated_cavities = ("tccb", "tcca")
    cavity_label(k) = k <= length(modulated_cavities) ?
        "element $(k) = $(modulated_cavities[k])" : "element $(k)"
    tm_receipts = filter(r -> r.consumer === :turn_modulation, execution_receipts(audit))
    isempty(tm_receipts) && println("turn_modulation receipt = none recorded (the line has no " *
                                    "modulated element: OCTOPUS_NOISE_RULE=", cn.rule,
                                    ", effective phase_rms ", phase_sigma,
                                    ", effective strength_rel_rms ", strength_sigma_rel, ")")
    for r in tm_receipts
        println("turn_modulation receipt: first_turn = ", r.values.first_turn,
                ", turns = ", r.values.turns, ", backend = ", r.backend)
        for (k, e) in enumerate(r.values.elements)
            println("  [", cavity_label(k), "] ", e.element, " (beam ", e.beam, "): ",
                    join(("$(s.slot) $(s.kind)" for s in e.slots), ", "))
        end
    end
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

    # The recorded series (OCTOPUS_RECORD_TURN_MODULATION, on by default): the
    # offsets every active slot produced, read back from the artifact through
    # the public reader -- entry i of a slot's `series` is the value applied on
    # absolute turn i - 1 of this one `execute!` (first_turn 0), the very value
    # the element used (one evaluation, shared with the realised element;
    # nothing is replayed here). Read on THIS rank because rank 0 alone holds
    # the file. Checked loudly, with the numbers (the header's paragraph on the
    # variable): every active slot of this run recorded a series of exactly
    # `turns` entries; a white series' rms is within `rms_tol` of its sigma,
    # rms_tol = max(0.10, 5/sqrt(2 turns)) -- the one-sigma of an rms over T
    # iid normals is 1/sqrt(2T), so 10 % is a 5-sigma band from T = 1250 on
    # and the band widens below that to stay at 5 sigma (at the suite's 2 turns
    # a bare 10 % pin would fail 85 % of the time on correct code); a table
    # series equals its record's first `turns` entries bitwise; a pink series'
    # rms is printed with its ratio and no pin (the band-limited sum's
    # finite-run rms wanders with its slow generators; the verdict is the
    # validation study's, over 2^20 turns). With the switch OFF every slot
    # must read back `nothing`: a series written unasked is a configuration
    # the code did not read. The `rms_<label>` fields join the summary line
    # after its pre-existing fields.
    series_fields = String[]
    if phase_on || strength_on
        rms_tol = max(0.10, 5 / sqrt(2 * turns))
        recorded_labels = String[]
        for entry in turn_modulation_provenance(artifact_path)
            for (k, e) in enumerate(entry.elements)
                k <= length(modulated_cavities) || error(
                    "the provenance lists $(length(entry.elements)) modulated elements; this line has $(length(modulated_cavities))")
                cavity = modulated_cavities[k]
                for s in e.slots
                    m = match(r"^(phase_noise|strength_noise)\[([0-9]+)\]$", s.slot)
                    m === nothing && error(
                        "slot label $(repr(s.slot)) of $(cavity_label(k)) is not of the form phase_noise[i] or strength_noise[i]")
                    parameter = String(m.captures[1])
                    label = "$(cavity)_$(parameter)_$(m.captures[2])"
                    if !record_turn_modulation
                        s.series === nothing || error(
                            "OCTOPUS_RECORD_TURN_MODULATION=0, but $(label) read back a series of " *
                            "$(length(s.series)) entries: the artifact recorded what was not asked for")
                        continue
                    end
                    s.series === nothing && error(
                        "OCTOPUS_RECORD_TURN_MODULATION=1, but $(label) read back no series (nothing)")
                    n = length(s.series)
                    n == turns || error(
                        "$(label): the recorded series has $(n) entries for a run of $(turns) turns")
                    push!(recorded_labels, label)
                    rms = sqrt(sum(abs2, s.series) / n)
                    sigma = parameter == "phase_noise" ? phase_sigma : strength_sigma_rel
                    if s.kind === :white
                        ratio = rms / sigma
                        abs(ratio - 1) <= rms_tol || error(
                            "$(label) (white): the recorded series has rms $(rms) against sigma $(sigma), " *
                            "ratio $(ratio), outside 1 +- $(rms_tol) (max(10 %, 5/sqrt(2 turns)) at $(turns) turns)")
                        println("series ", label, ": white, ", n, " entries, rms = ", rms, ", sigma = ", sigma,
                                ", ratio = ", ratio, " (within 1 +- ", rms_tol, ")")
                    elseif s.kind === :table
                        record = table_offsets[label]
                        if s.series != record[1:turns]
                            first_bad = findfirst(i -> s.series[i] !== record[i], 1:turns)
                            error("$(label) (table): the recorded series differs from the record's first $(turns) " *
                                  "entries; first difference at entry $(first_bad): recorded $(s.series[first_bad]), " *
                                  "record $(record[first_bad])")
                        end
                        if cn.rule === :spectral
                            # The provenance must carry the canonical name of the
                            # table the rule resolved to, which is the factory's
                            # under the run's seed and this slot's rng_id: the
                            # record's name, built above from the same keying. The
                            # two keys are asserted by name first, so a mismatch
                            # says WHICH key the rule resolved with differently.
                            expected_name = spectral_names[label]
                            occursin("seed=$(global_rng_seed())", s.name) || error(
                                "$(label) (spectral): the provenance name $(repr(s.name)) does not carry " *
                                "seed=$(global_rng_seed()), the run's global seed the rule must have resolved with")
                            occursin("rng_id=$(spectral_ids[label])", s.name) || error(
                                "$(label) (spectral): the provenance name $(repr(s.name)) does not carry " *
                                "rng_id=$(spectral_ids[label]), this slot's explicit stream id")
                            s.name == expected_name || error(
                                "$(label) (spectral): the provenance names the resolved table $(repr(s.name)); " *
                                "the factory under the run's seed $(global_rng_seed()) and this slot's rng_id names " *
                                "it $(repr(expected_name)) -- the rule did not resolve with the run's keying")
                        end
                        if cn.rule === :spectral && cn.amplitudes === :rayleigh
                            # Rayleigh amplitudes: sigma is the EXPECTED rms of the
                            # stationary Gaussian process, and one realisation's
                            # rms^2/sigma^2 is a weighted mean of K exponential
                            # variables (one per band bin, mean 1, variance 1), so
                            # for a FLAT band its one-sigma is 1/sqrt(K) and the rms's
                            # 1/(2 sqrt(K)); a sloped band (the pink preset) puts its
                            # weight in fewer bins and wanders more. Printed with
                            # that band and no pin; the statistics are the
                            # validation's item `spectral`.
                            ratio = rms / sigma
                            K = count(k -> cn.band[1] <= k / cn.table_turns <= cn.band[2], 1:(cn.table_turns ÷ 2))
                            println("series ", label, ": spectral table (rayleigh amplitudes), ", n,
                                    " entries == the table bitwise, rms = ", rms, ", sigma = ", sigma,
                                    ", ratio = ", ratio, " (no pin: sigma is the expected rms; one sigma 1/(2 sqrt(K)) = ",
                                    K == 0 ? "n/a" : string(1 / (2 * sqrt(K))), " for a flat band of K = ", K, " bins)")
                        elseif cn.rule === :spectral
                            # Fixed amplitudes: the spectral table's rms is ANALYTIC
                            # over its whole period (D5 of
                            # docs/design/spectral_turn_table.md): the band bins are
                            # orthogonal over the table's N entries, so the rms of
                            # all N equals sigma up to rounding -- pinned at 1e-9
                            # relative here (the validation's item `spectral` pins
                            # the same identity at 1e-12), and only when the recorded
                            # series IS the whole period, which it is whenever the
                            # table is exactly OCTOPUS_TURNS long; a partial period
                            # has no such identity and is printed without a pin.
                            ratio = rms / sigma
                            if n == cn.table_turns
                                abs(ratio - 1) <= 1e-9 || error(
                                    "$(label) (spectral table): the recorded series has rms $(rms) against sigma " *
                                    "$(sigma), ratio $(ratio), outside 1 +- 1e-9 although the run covers the " *
                                    "table's whole period ($(n) of $(cn.table_turns) entries): the analytic " *
                                    "normalisation did not hold")
                                println("series ", label, ": spectral table, ", n, " entries == the table bitwise, rms = ",
                                        rms, ", sigma = ", sigma, ", ratio = ", ratio,
                                        " (within 1 +- 1e-9: analytic normalisation over the whole period)")
                            else
                                println("series ", label, ": spectral table, ", n, " entries == the table's first ", turns,
                                        " entries bitwise, rms = ", rms, ", sigma = ", sigma, ", ratio = ", ratio,
                                        " (no pin: a partial period, ", n, " of ", cn.table_turns,
                                        " table entries, has not the period's rms)")
                            end
                        else
                            println("series ", label, ": table, ", n, " entries == the record's first ", turns,
                                    " entries bitwise, rms = ", rms)
                        end
                    else
                        cn.rule === :spectral && error(
                            "$(label): the spectral rule resolves into a table at compile, so its provenance " *
                            "entry should read kind :table; it reads kind $(repr(s.kind))")
                        println("series ", label, ": ", s.kind, ", ", n, " entries, rms = ", rms, ", sigma = ", sigma,
                                ", ratio = ", rms / sigma, " (no pin: band-limited sum, the finite-run rms wanders)")
                    end
                    push!(series_fields, "rms_$(label)=$(rms)")
                end
            end
        end
        if record_turn_modulation
            sort(recorded_labels) == sort(needed_labels) || error(
                "the recorded series name the slots $(sort(recorded_labels)) while this run activates $(sort(needed_labels))")
        else
            println("turn_modulation series = none recorded (OCTOPUS_RECORD_TURN_MODULATION=0; every slot read back nothing)")
        end
    end

    # Read back from the artifact, not from the live beam: the line below reports
    # what the file holds. The rms emittance from the central second moments,
    # eps_x = sqrt(<x^2><px^2> - <x px>^2) (columns m200000, m020000, m110000),
    # eps_y from m002000, m000200, m001100.
    out = TaskOutput(artifact_path)
    lum = read(out, :luminosity; name = "strong_beam_1")
    lumi_mean = sum(lum.value) / length(lum.value)
    mom = read(out, :moments; name = "weak_beam")
    eps_x = sqrt.(mom.m200000 .* mom.m020000 .- mom.m110000 .^ 2)
    eps_y = sqrt.(mom.m002000 .* mom.m000200 .- mom.m001100 .^ 2)
    println("emittance estimator = sqrt(<x^2><px^2> - <x px>^2) from the central second moments; ",
            length(eps_x), " moment rows, first at turn ", Int(mom.turn[1]),
            ", last at turn ", Int(mom.turn[end]), "; design eps_x = ", emit[1], ", eps_y = ", emit[2])
    # ONE string, written once: a line a parent parses is built whole
    # (docs/experiences.md, "Two ranks printing at the same moment merge
    # mid-line"). wall_s and ms_per_turn are this rank's `execute!`, JIT
    # included; steady_ms_per_turn is the max over ranks after the warm-up.
    summary = string("CRAB-NOISE rule=", cn.rule, " scale=", cn.scale,
        " phase_rms=", phase_sigma, " strength_rel_rms=", strength_sigma_rel,
        " chrom=", chromaticity[1], ",", chromaticity[2],
        " table_file=", isempty(cn.table_file) ? "none" : cn.table_file,
        " turns=", turns, " n_macro=", n_macro, " kbb_scale=", kbb_scale,
        " radiation=", use_radiation ? 1 : 0, " seed=", input.seed,
        " artifact=", artifact_path,
        " eps_x_first=", eps_x[1], " eps_x_last=", eps_x[end],
        " eps_y_first=", eps_y[1], " eps_y_last=", eps_y[end],
        " lumi_mean=", lumi_mean, " wall_s=", wall_s, " ms_per_turn=", ms_per_turn,
        " ranks=", recorded_ranks, " threads=", threads_text,
        " steady_ms_per_turn=", steady_text,
        # Appended AFTER the pre-2026-10-15 fields, so a parser of the fields
        # above reads them unchanged (the header's note on the line).
        " record=", record_turn_modulation,
        isempty(series_fields) ? "" : " " * join(series_fields, " "),
        # The spectral rule's preset, band and amplitudes (2026-10-16), after
        # every earlier field for the same reason; none under the other rules.
        " spectrum=", cn.rule === :spectral ? string(cn.spectrum) : "none",
        " band=", cn.rule === :spectral ? "$(cn.band[1]),$(cn.band[2])" : "none",
        " amplitudes=", cn.rule === :spectral ? string(cn.amplitudes) : "none")
    println(summary)
end
