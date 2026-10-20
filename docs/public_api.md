# Octopus Docstring Entry Points

Source docstrings and generated metadata are the public API reference. Use this
file only as a map to the right help query.

## Load Octopus

```julia
include("src/Octopus.jl")
using .Octopus
```

## Discover Objects

```julia
summarize_registry()
build_registry()
example_catalog()                 # the curated scripts, as Example objects
example_script_path(entry)        # one entry's script, resolved
```

The generated inventory is `docs/registry_snapshot.md`; its Examples section
lists the catalogue entries with their categories and objects. Regenerate it
with:

```julia
write_registry_snapshot()
```

## Construct Elements

Start with:

```julia
element_help()
element_help(:thin_crab_cavity)
element_help(ThinCrabCavitySpec)
```

`element_help(:thin_crab_cavity)` also documents the crab cavity's
turn-by-turn modulation parameters `phase_noise` and `strength_noise` (see
"Turn Modulation" below).

Then use focused metadata queries when needed:

```julia
parameter_schema(ThinCrabCavitySpec)
example_spec(ThinCrabCavitySpec)
construction_help(ThinCrabCavitySpec)
supported_tracking_methods(ThinCrabCavitySpec)
```

For the element development pattern, use Julia help:

```julia
?ElementSpec
?@element_spec
?ParamMeta
?ElementMeta
```

## Build And Execute Tracking Workflows

Use Julia help:

```julia
?TrackingTask
?StrongStrongTask
?CPUThreadsExecutionPolicy
?MultiProcessExecutionPolicy
?CUDAExecutionPolicy
?CUDALaunchConfig
?CUDAPICLaunchConfig
?policy_option_schema
?cuda_pic_launch_option_schema
?configuration_report
?ExecutionAudit
?with_execution_audit
?execution_receipts
?validate_configuration_metadata
?StrongStrongDiagnostics
?DiagnosticsOptionMeta
?diagnostics_option_schema
?diagnostics_help
?turn_timings
?tracking_task_option_schema
?pic_phase_timings
?diagnostic_summary
?StrongStrongCollision
?GaussianPoissonSolver
?PICPoissonSolver
?SpectralPoissonSolver
?GaussianPICPoissonSolver
?SolverOptionMeta
?solver_option_schema
?solver_configuration
?solver_help
?LongitudinalSlicing
?longitudinal_slices
?AbstractPoissonSolver
?execute!
?TrackingContext
?ScheduledObserver
?ScheduledAction
?EveryNSteps
?AtTurns
?schedule_option_schema
?observer_option_schema
?Moment
?MomentObserver
?MomentOutput
?column_names
?name
?symbol
?RunArtifact
?run_artifact_option_schema
?TaskOutput
```

Runnable examples live in `examples/` and are self-documenting at the top of
each source file. They are clean precedents with a small top-of-file `config`
block; the matching configurable developer harnesses (driven by `OCTOPUS_*`
environment variables) live in `test/examples/`.

A task's outputs land in ONE run artifact — an HDF5 file the task carries
(`artifact = RunArtifact(path)` or `artifact = path` on `TrackingTask` and
`StrongStrongTask`; its options `append`, `capacity` and
`record_turn_modulation` are described by `run_artifact_option_schema()`;
design note `docs/design/run_artifact.md`). Probes are
named views into it: `MomentObserver(; name = ...)`,
`CoordinateSnapshotObserver(; name = ...)`, `BPMObserver(...; artifact =
true)`. Common access pattern:

Use `?MomentObserver`, `?Moment`, `?MomentOutput`, `?column_names`,
`?name`, `?symbol`, `?RunArtifact`, and `?TaskOutput` for the complete
output API docstrings. This section is the quick entry point.

```julia
observer = MomentObserver(; name = "proton",
    orders = 1:2,
    extra = (Moment(; pz=4),),
    exclude = (Moment(; z=2),),
)
# ... place it in the line, run the task with artifact = "result/pic_hcc.h5"

moments = MomentOutput("result/pic_hcc.h5"; name = "proton")
data = read(moments)               # column 1 is turn
turns = read(moments, :turn)        # same values as data[:, 1]
mx = read(moments, Moment(; x=1))
sxpx = read(moments, :m110000)
first_second = read(moments; orders = 1:2)
names = column_names(moments)

out = TaskOutput("result/pic_hcc.h5")
read(out)                                 # recursive contents: columns/rows/s per group
read(out, :luminosity; name = "ip")       # one collision's (turn, value)
read(out, :moments; name = "proton", column = Moment(; x = 1))
read(out, :moments; name = "proton", orders = 1:2)   # selection, MomentObserver rules
read(out, :bpm; name = "BPM_07", column = :x)
read(out, :snapshot; name = "inj", turn = 100)
read(out, :losses)                        # rows + apertures + summary
read(out, :execution)                     # per-execute! ledger
read(out, :all)                           # everything, nested by kind
```

Moment names are canonical strings such as `m100000`; if any exponent is
multi-digit, separator form is used, such as `m10_0_0_0_0_0`. The execution
ledger records start turn, planned window, current turn and elapsed wall
time per `execute!`, updated at every flush — live progress from one file —
and, since 2026-10-16, the global stochastic seed and counter-RNG method
name in force when each `execute!` began (`rng_seed`, `rng_method`; a
`set_global_rng!` between two windows is on record row by row). A continued
(`append = true`) file written before those columns existed is refused by
name rather than padded; reading it stays possible, the missing columns
read as `nothing`.

One `execute!` holds its artifact exclusively across processes (2026-10-16):
while it runs, the sidecar lock `<path>.lock` holds one line naming the
host, the process id, the time and the task kind, and a second Octopus
writer on the path — from any process or host, with either `append` — is
refused with that line and the remedy (if that process is gone, remove the
lock; nothing removes it automatically, since the holder may be alive on
another host). Reading does not take the lock: `TaskOutput`,
`turn_modulation_provenance` and `MomentOutput` read a file another process
is writing as of its last flush, say so once per writer with an `@info`
naming the lock's line (rows valid through each group's
`rows_valid_through_turn` cursor and the ledger's `current_turn`), and retry
a failed open once. The lock is advisory and for Octopus writers; HDF5
itself does not honour it.

What a run's artifact RESOLVED is on record (2026-10-16): under
`with_execution_audit`, `prepare_run_artifact!` records one
`:run_artifact_output` receipt per `execute!` with `task`, `artifact` (the
path), `append` beside `continued` (an existing file continued, or created
fresh), `capacity`, `record_turn_modulation` beside `recording` (recorders
built: the switch on and a modulated element in the line) and `execution`
(the ledger row); the task records its own output receipt beside it --
`:tracking_output` (`artifact`, `channels`, `loss_report`) or
`:strong_strong_output` (`artifact`, `channels`) -- after the artifact is
prepared, so a refused prepare leaves none. `tracking_task_option_schema()`
describes `artifact` and `loss_report`; `configuration_report(task, rep)`
carries an `output` entry pair whose artifact entry is `:unresolved` while
`append` or `record_turn_modulation` is requested (both are decided at
prepare) and names the receipt field that carries the answer. The probes'
`:observer_output` receipts carry the fields their `observer_option_schema`
names (`name`, `moments`, `npart` beside `captured`, `artifact`, the
artifact's `capacity`). A `/turn_modulation` slot a crashed prepare left
half-written is PARTIAL (its cursor `elements_valid_through` behind its
`element_count`): the readers read it as far as the cursor with a warning
naming it, never roll it back, and `append = true` onto such a file is
refused by name; `append = true` onto an existing file that is not HDF5 is
refused by name too.

Developer-facing numerical checks live in `validation/`. They may use internal
helpers and should not be treated as public API examples.
For the physics/method theory behind the beam-beam solvers (longitudinal-kick
formulas and virtual-drift conventions, the weak-strong source model, and the
spectral and Gaussian-subtracted PIC solvers), see the theory notes indexed in
`docs/README.md`, starting from `docs/theory/beam_beam_longitudinal_kick.md`.

## Knob Control

Deferred parameter expressions over named knobs; design note in
`docs/knob_control.md`. Use Julia help:

```julia
?@knob
?@knob_expr
?knobs
?KnobNamespace
?set_knob!
?knob_value
?resolve_knobs
?knob_report
?knob_dependencies
?knob_dependents
?knob_derivative
?knob_symbolic
?knob_from_symbolic
?knob_symbolics_available
?KnobEffectivenessContract
```

## Turn Modulation

Element parameters that change from turn to turn inside one tracking run
(crab cavity RF phase and amplitude noise first), realised once per turn on
the host by the `TurnModulated` compile-time wrap and never read by a kernel;
design note in `docs/design/turn_modulation.md`. The crab cavity's
`phase_noise` and `strength_noise` parameters are documented by
`element_help(:thin_crab_cavity)`; the thin RF cavity declares the same two
parameters as scalars, one rule or `nothing` each
(`element_help(:thin_rf_cavity)`). Use Julia help:

```julia
?TurnModulated
?WhiteNoise
?PinkNoise
?TurnTable
?SpectralNoise
?spectral_turn_table
?update
?update_line
?realize
?turn_modulation_provenance
```

Noise of a chosen spectrum (design `docs/design/spectral_turn_table.md`,
owner decisions 2026-10-15 and 2026-10-16): the fourth rule, `SpectralNoise(sigma,
band, spectrum; rng_id = 0, turns, amplitudes = :fixed, f_rev = nothing)`, is
the spec-level form -- `rng_id` claimed at construction as for `WhiteNoise`,
`turns` mandatory -- and resolves when the line COMPILES into the `TurnTable`
that `spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id,
slot = 0, amplitudes = :fixed, f_rev = nothing, T = Float64, name = nothing)`,
its offline form, returns for `seed = global_rng_seed()`, the rule's `rng_id`
and the entry's slot: at run time it IS a table (D7, the window check, the
recorder and the provenance unchanged, kind `table`, the canonical name
`spectral(<label>; sigma=.., band=.., turns=.., seed=.., rng_id=.., slot=.., amplitudes=..)`
beside the digest). `spectrum` is a preset (`:flat`, `:pink`) or `"<label>" =>
S` with `S(f) >= 0` the one-sided POWER SPECTRAL DENSITY shape; the bin
amplitude is `sqrt(S(f_k))`, so `f -> 1/f` is pink, while `1/f` handed as an
amplitude -- the custom PSD `f -> 1/f^2` -- is brown, one unit per octave
steeper (the classic trap; the suite pins it). `band = (lb, ub)` is in cycles
per turn with `0 < lb < ub <= 1/2` (hertz with `f_rev`; the DC bin is never
in the band); the phases are the counter RNG keyed on `(seed, rng_id, slot,
bin)`, `slot` the table's slot on its element -- `0` for an offline table;
for a rule the slot it realises on (crab cavity: phase harmonic `i` is slot
`i`, strength harmonic `i` slot `N + i`; RF cavity: phase 1, strength 2) --
so one `rng_id` on several slots of one cavity gives independent tables, as
it gives the live rules independent draws per entry, while two cavities
sharing an explicit id resolve to identical tables slot for slot and the task
constructor's shared-id warning fires (to regenerate a resolved table
offline, pass the slot its name records); with `amplitudes = :fixed` the rms over the table's period is `sigma` and the
periodogram the target EXACTLY (fixed bin amplitudes, Gaussian only in the
limit of many bins), with `:rayleigh` `sigma` is the EXPECTED rms of a
stationary Gaussian process whose periodogram scatters exponentially around
the target. The rule takes the global seed in force when the line compiles
(the first `execute!`, or a recompile after a knob assignment), unlike the
live rules, which read it every turn; the name records the seed used, and
every `execute!` of either task kind warns, naming the element, the slot and
both seeds, while the global seed differs from the one a resolved table
carries (the table stays as synthesised; rebuild the task to re-synthesise
it under the current seed; 2026-10-16). The offline table claims no stream,
so `rng_id = 0` is refused there; its sharing checks are the task
constructor's equal-digest warning (two tables of one `(seed, rng_id, slot)`
over one band are the same noise) and, once per compilation of the line, the
equal-digest check over the RESOLVED line, which names what the constructor
could not see -- a `SpectralNoise` beside its offline twin -- and skips what
it already named (one spec placed twice, two offline copies of one table, two
rules on one explicit id), one warning per cause, on both task kinds; a
custom spectrum labelled with a preset's name is refused (2026-10-16):

```julia
set_global_rng!(seed = 42); rule = SpectralNoise(1.0e-5, (1.0e-4, 1.0e-2), :pink; rng_id = 7, turns = 2^20)
cavity = ThinCrabCavitySpec{1}(394.0e6; strengthX = (2.0e-3,), phase = (0.0,), phase_noise = (rule,))   # phase_noise[1] is slot 1
table = spectral_turn_table(:pink, 1.0e-5, (1.0e-4, 1.0e-2); turns = 2^20, seed = 42, rng_id = 7, slot = 1)   # the same table, offline
```

A resolved spectral slot reads back from the receipt and the artifact as a
table (`kind = :table`, `rng_id = 0`, as for any `TurnTable`): the stream id
survives only inside the canonical name above, so a reader selecting slots
by `rng_id` must parse it from there (2026-10-16 neighbour audit, U7-7).

Offset semantics (owner decision 2026-10-15, stage 0 of
`docs/design/turn_modulation_record.md`): a `phase_noise` rule's offsets are
radians added to the nominal phase; a `strength_noise` rule's offsets are
dimensionless relative factors `d`, one per harmonic, scaling both planes'
strengths of the harmonic, `strengthX (1 + d)` and `strengthY (1 + d)`, and
on the RF cavity the voltage, `V (1 + d)` (one voltage driver per cavity; a
second driver is a second cavity). A rule's `sigma` is therefore the phase
rms in radians or the relative amplitude rms itself: `WhiteNoise(1e-4)` on a
strength slot is a 1e-4 relative amplitude noise, with no multiplication by
the nominal strength, and a strength `TurnTable` holds relative factors.
Before 2026-10-15 the strength offset was added in the strengths' unit to
both planes; a strength table produced for that convention is wrong by the
nominal strength under this one.

A bare `track!` through a `TurnModulated` line tracks the NOMINAL element on
every turn; the rules are realised only by a task's `execute!`, which calls
`update_line` before each turn (design decision D5). CUDA.jl also exports an
`update`, so a session that does `using Octopus, CUDA` writes
`Octopus.update`.

The production-shaped precedent is `examples/crab_cavity_noise.jl`: the EIC
weak-strong crab crossing with RF phase and amplitude noise on both proton
crab cavities, white, pink, a tabulated record or a spectral rule
(`SpectralNoise`) through one switch, each
cavity on independent streams (harness `test/examples/crab_cavity_noise.jl`,
study `validation/crab_cavity_noise_response.jl`); the physics it measures
is derived in `docs/theory/crab_cavity_noise_response.md`. The example also
runs divided under the MPI execution policy (`config.execution =
:multiprocess`, package mode under a launcher; `OCTOPUS_USE_MPI=1` on the
harness), and `profiling/crab_cavity_noise_backends.jl` benchmarks it across
CPU threads, MPI ranks and CUDA with output digests; the numbers are in
`docs/history/crab_cavity_noise_mpi_benchmark_2026_10_14.md`. Since
2026-10-15 the example's default run records the realised offsets
(`record_turn_modulation = true` in its output block) and prints, per
cavity and active slot, the recorded series' rms against the rule's sigma;
the harness toggle `OCTOPUS_RECORD_TURN_MODULATION` (default on) refuses a
run whose series are short, whose white rms leaves
`max(10 %, 5/sqrt(2 turns))` of its sigma or whose table series differ
from the record, and appends `record=` and `rms_*` fields to its
`CRAB-NOISE` line (record
`docs/history/turn_modulation_record_2026_10_15.md`, section 3). Under
`OCTOPUS_NOISE_RULE=spectral` the harness reads three more toggles,
`OCTOPUS_SPECTRUM` (`flat` or `pink`), `OCTOPUS_BAND` (`<lb>,<ub>` in cycles
per turn) and `OCTOPUS_SPECTRAL_AMPLITUDES` (`fixed` or `rayleigh`), refused
under any other rule; it builds a `SpectralNoise` per slot, checks every
recorded series bitwise against the factory's table for the run's global
seed, the slot's `rng_id` and its slot, and appends the trailing fields
`spectrum= band= amplitudes=` to the `CRAB-NOISE` line (`none` under the
other rules; record `docs/history/spectral_turn_table_2026_10_16.md`,
section 3). To read the
`:turn_modulation` execution receipt, the run's own statement of which
elements and slots it realised and over which window, wrap the `execute!`
call in `with_execution_audit` and filter `execution_receipts` -- outside an
audit no receipt is recorded, while the artifact's provenance
(`turn_modulation_provenance(path)`, `read(TaskOutput(path),
:turn_modulation)`) is written by every `execute!` regardless:

```julia
audit = with_execution_audit() do; execute!(task, beam; turns = turns); end
receipts = filter(r -> r.consumer === :turn_modulation, execution_receipts(audit))
```

To record the offsets the rules realised, turn by turn, switch the run
artifact's `record_turn_modulation` option on and read the series back
through the existing provenance reader (design
`docs/design/turn_modulation_record.md`, stage 1 landed 2026-10-15;
`?RunArtifact`, `?run_artifact_option_schema`, `?turn_modulation_provenance`;
off by default):

```julia
task = TrackingTask(line; artifact = RunArtifact(path; record_turn_modulation = true))
slot = read(TaskOutput(path), :turn_modulation)[1].elements[1].slots[1]   # or turn_modulation_provenance(path)
```

`slot.series` is a `Vector{Float64}` with one entry per turn of that
`execute!` window (entry `i` is absolute turn `first_turn + i - 1`), or
`nothing` when the run did not record; `slot.nominal` holds the nominal
parameters of the harmonic (or cavity) the slot modulates, `(phase,
strengthX, strengthY)` on a crab cavity slot and `(phase, strength)` on an
RF cavity slot, written whether or not the run recorded (`nothing` only for
a file written before 2026-10-15). The numbers are the OFFSETS the rule
produced, not the realised values: on a phase slot radians, the realised
phase being `slot.nominal.phase + slot.series[i]`; on a strength slot the
dimensionless factor `d`, the realised strengths being
`slot.nominal.strengthX * (1 + d)` and `slot.nominal.strengthY * (1 + d)`
(on the RF cavity `slot.nominal.strength * (1 + d)`), exactly as the element
forms them. The recorded sequence is the one the element used (one
evaluation, shared between the realised element and the recorder), and
recording changes nothing in the tracking: the coordinates, the luminosity,
the moments and the receipt are bitwise identical with the switch on and
off; the cost is 8 bytes per active slot per turn, batched with the
artifact's `capacity`, written by rank 0 under MPI and host-side on CUDA.
Each execution entry also carries `state = nothing`, the group reserved for
a future stateful rule's checkpoint; the bare `read(TaskOutput(path))`
table of contents stays metadata-only and reports the recorded row count in
`series` instead of the column. Each element entry carries `first_turn` and
`turns`, the window the series covers (`nothing` when the run did not
record); the row count is authoritative, so a series shorter than `turns`
-- a run killed before its window completed -- reads as it stands with one
warning naming the dataset (2026-10-15). Series and nominals are stored as
`Float64` whatever the element's numeric type, so "exactly as the element
forms them" is bitwise for `Float64` lines.

Bounds the wrapper enforces at `TurnModulated(base, rule)`: a `PinkNoise` is
refused on a rule container with more than 64 slots (the pink component
stride), so a crab cavity with more than 32 harmonics may carry white and
table rules only; slot labels must be non-empty, free of '/' and unique. An
explicit `rng_id` must be a non-negative integer (`0`, the default, assigns
a fresh stream). The two kinds spell "inactive" differently because their
parameters have different shapes: the crab cavity takes `()` or a tuple of
`nothing` and refuses a bare `nothing`, the RF cavity takes `nothing` and
refuses a tuple; `element_help` of each kind says so.

## Beam And Runtime Helpers

Use Julia help:

```julia
?Beam
?Phase6DRep
?beam_statistics
?write_beam_coordinates
?read_beam_coordinates
?track_particle
?compile_runtime
?runtime_type
?tracking_method
?TrackingContext
?with_turn
```

Precision, one rule for every element kind (owner decision 2026-10-16):
`Beam(n, policy, Float32)` is a `Float32` beam, and it needs `Float32` elements
everywhere. Every kind's untyped constructor compiles in the type its
parameters promote to over a `Float64` floor (`numeric_type(spec)`), and every
kind has a typed form, `Spec{Float32}(; ...)` or `Spec(; numeric_type=Float32,
...)` by keyword (`QuadrupoleSpec{Float32}(L=0.5, k1=0.3)`,
`ThinRFCavitySpec{Float32}(frequency; ...)`, `ThinCrabCavitySpec{N,Float32}`,
`LumpedRadSpec{Float32}`; `element_help(kind)` lists `numeric_type` for each),
which stores `numeric_type = Float32` and compiles the `Float32` element. A
beam whose element type differs from an element's is refused when the task
compiles the line, by name, on both backends and in either direction, with the
remedy naming the kind's typed form; the marker included (`MarkerSpec{Float32}`
types its placement frames; fix I, 2026-10-17) (`current_runtime.md`, "Current
Backends", with the 31-kind measurement). The same section states which
coordinates of each kind agree bitwise between the CPU and CUDA kernels and
which agree to a stated number of ulps (`_cross_backend_rounding`, checked by
measurement in the suite and by `validation/tracking_backend_consistency.jl`).

## Particle Loss

A non-finite coordinate means a **bug** by default, and every solver chokepoint
fails fast on one. `allow_lost_particles` is the scoped opt-out that reinterprets
it as a *lost particle*: reductions skip the particle and divide by the live
count instead of stopping the run. A particle is live only when all six
coordinates are finite.

```julia
?allow_lost_particles
?is_live
?count_live
?count_dead
```

An `ApertureSpec` is the element that loses particles deliberately: it kills what
is outside its acceptance by marking all six coordinates non-finite, counts what
it killed, and — when given a record — logs the pre-kill coordinates so a loss is
still interpretable after the particle is gone. Loss position is resolved only to
where you place apertures, so guard both faces of a magnet with two of them.

`loss_summary` reports the beam-wide dead count and the aperture-attributed total
separately. The gap between them is particles that went non-finite with no
aperture responsible, which is the diagnostic that keeps a numerical blowup
distinguishable from collimation. A `TrackingTask` holds one loss record
(`loss_record(task)`, `loss_summary(beam, task)`); a `StrongStrongTask` holds
one per beam (`loss_record(task, 1)`, `loss_record(task, 2)`;
`loss_summary(beam, task)` reconciles the beam it is handed, identified by its
storage, or `loss_summary(beam, task, which)`), and writes each beam's
accounting into its artifact's `/losses/beam_<i>` group
(`read(TaskOutput(path), :losses).beam_1`).

```julia
?ApertureSpec
?LossRecord
?loss_records
?loss_counts
?loss_summary
?write_loss_record
?read_loss_record
```

## Numerical Math Helpers

Use Julia help:

```julia
?counter_philox4x32
?set_global_rng!
?global_rng_seed
?global_rng_method
?global_rng_method_code
?next_rng_id!
?claim_rng_id!
?reset_rng_id_counter!
?octopus_normal
?counter_uint64
?counter_uniform01
?counter_normal_pair
?counter_normal
?splitmix_uint64
?splitmix_uniform01
?splitmix_normal_pair
?splitmix_normal
?faddeeva_w
?faddeeva_w_approx_reim
```

Implementation details that are expected to evolve are summarized in
`docs/current_runtime.md`.

## Analyses

The first analysis: coupled Twiss and canonical dispersion from a one-turn
matrix (design note in `docs/design/twiss_dispersion_analysis.md`, theory in
`docs/theory/twiss_dispersion.md`). The analysis object carries the public
options; `analyze` consumes a real symplectic 4x4 or 6x6 matrix, a
`LinearizedMap`, or anything `one_turn_matrix` accepts, and returns a
`TwissDispersionResult` whose undetermined quantities are `Determined` values.

```julia
analysis = TwissDispersionAnalysis()                 # defaults; keywords validate
analysis = TwissDispersionAnalysis(strict=false, closed_orbit=:warn)
result = analyze(analysis, M)                        # bare 4x4 or 6x6 matrix
result = analyze(analysis, lm)                       # lm::LinearizedMap
result = analyze(analysis, line; method=ComplexStepLinearization(), point=ntuple(_ -> 0.0, 6))
lm = one_turn_matrix(line; method=ComplexStepLinearization())
configuration_report(result)                         # which option each branch read
```

Use Julia help:

```julia
?TwissDispersionAnalysis
?analyze
?analysis_option_schema
?TwissDispersionResult
?configuration_report
?matched_covariance
?normal_mode
?NormalMode
?dispersion_interval
?Determined
?UndeterminedQuantityError
?OpticsAnalysisError
?ANALYSIS_STATUSES
?one_turn_matrix
```

## Validation

The package regression suite runs at CI settings: plain `Pkg.test` at
`--threads=4` is the full gate and `lane=fast` is a development checkpoint.
The commands are in `AGENTS.md` (Verification Matrix).

The broader numerical studies and CPU/CUDA consistency checks remain separate
scripts under `validation/`.

Useful beam-beam checks:

```bash
julia --project=. validation/symplecticity_validation.jl
julia --project=. validation/high_energy_weakstrong_limit.jl
julia --project=. validation/soft_gaussian_pic_comparison.jl
```

Use Julia help:

```julia
?ContractResult
?ElementTrackingBackendConsistencyContract
?StrongStrongGaussianBackendConsistencyContract
?StrongStrongPICBackendConsistencyContract
?StrongStrongPICMultiProcessConsistencyContract
?PublicConfigurationEffectivenessContract
?AnalysisOptionEffectivenessContract
?TwissDispersionIdentityContract
?TwissExternalReferenceContract
?SymplecticityContract
?HighEnergyWeakStrongLimitContract
?CoherentModePhysicsContract
?validate
?turn_timings
```

After public element metadata changes:

```julia
validate_element_metadata()
write_registry_snapshot()
```

Run a relevant `TrackingTask` smoke test or executable example after changing
tracking behavior.
