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

## Construct Beams

```julia
?Beam
?BeamParams
?Phase6DRep
?beam_initialization_option_schema
```

`Beam(N, policy; distribution=:gaussian, ...)` preserves the Gaussian default.
Use `distribution=:uniform, lower=lo, upper=hi` for random points in a physical
6D box. For a Cartesian grid, omit `N`:
`Beam(policy; lower=lo, upper=hi, grid_size=counts)` or `grid_step=spacing`.
The six-component order is `(x, px, y, py, z, pz)`; `grid_size` counts points,
and their product determines the macroparticle count. See the
[initialization design](design/beam_initialization.md) for the decisions behind
the API; `?Beam` owns the endpoint and inactive-option rules.

The beam's species and energy come from the lattice's reference particle as
one object, the recommended spelling since the reference batch (design D12,
record `docs/history/machine_description_reference_2026_11_25.md`; the flat
`charge`, `mc2`, `E0` keywords remain accepted on their own and build the same
beam bit for bit):

```julia
ref  = ReferenceParticle(; charge = 1, mc2 = PMASS_EV, E0 = 275e9)
beam = Beam(N, policy; reference = ref, r0 = r0, npart = npart, ...)   # r0, npart stay keywords
```

`reference` replaces `charge`, `mc2` and `E0` on every constructor form, the
bounded and grid forms included; any of the three given beside it, whatever
its value, is refused by name before anything is drawn or activated, as is a
`reference` that is not a `ReferenceParticle`. `r0` and `npart` stay keywords
(the classical radius is not derived from the reference in this batch).
`reference` is a beam-parameter keyword documented on `?Beam`, not an entry of
`beam_initialization_option_schema`, which enumerates the receipt-bearing
distribution options only.

A beam matched to a lattice point takes the point's optics as one object, the
recommended spelling (design D15; the flat `beta`, `alpha`, `zeta`, `eta`, `R`
keywords remain as the stored representation and for scripts written before
the point):

```julia
?LinearOptics
?EdwardsTengTwiss
?CanonicalDispersion
?advance_phase
?slope_dispersion
?dispersion_h
```

```julia
ip = LinearOptics(; beta=(0.8, 0.072, 90.9), alpha=(0, 0, 0), R=(0, 0, 0, 0),
                  zeta=(0, 0, 0, 0), eta=(0, 0, 0, 0), mu=(0.0, 0.0, 0.0), frame=:IR6)
beam = Beam(N, policy; optics=ip, sigma=(95e-6, 8.5e-6, 6e-2))
```

`LinearOptics` is the shared linear-optics value object
([design](design/linear_optics.md)): an `EdwardsTengTwiss` (three-plane
`beta`, `alpha`, the Edwards-Teng coupling matrix `R` and its `form`) and a
`CanonicalDispersion` (the canonical `zeta`, `eta`), optionally placed by its
mode phases `mu` in a named `frame`. `Beam(; optics=o)` flattens it into
`beta`, `alpha`, the coupling coefficients, `mode`, `eta` and `zeta`; giving any
of those beside `optics` is refused by name. The same object feeds
`Linear6DSpec(o1, o2)`, `ChromaticityKickSpec(; optics=)`,
`LumpedRadSpec(; optics=)` and `GaussianStrongBeamSpec(; optics=)` (see "Construct
Elements"), and `linear_optics(result)` builds one from a Twiss analysis (see
"Analyses").

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

The linear-optics consumers take a `LinearOptics` point in place of their
flat `beta, alpha, zeta, eta, R` keywords, the recommended spelling (design
D15); one form or the other, never both:

```julia
ip   = LinearOptics(; beta=(0.8, 0.072, 90.9), mu=(0.0, 0.0, 0.0), frame=:IR6)
sext = LinearOptics(; beta=(1.0, 1000.0, 90.9), mu=(-pi, -1.5pi, 0.0), frame=:IR6)
Linear6DSpec(ip, sext)                                   # transfer, dmu = sext.mu .- ip.mu
Linear6DSpec(ip, advance_phase(ip, 2pi .* (0.228, 0.210, -0.01)))   # one-turn map
ChromaticityKickSpec(; xi=(2.0, 2.0), optics=ip)
LumpedRadSpec(; damping_turns=(4e3, 4e3, 2e3), optics=ip, sigma=(95e-6, 8.5e-6, 6e-2))
GaussianStrongBeamSpec(; kbb=kbb, optics=LinearOptics(; beta=(0.45, 0.056, 1.0)), sigma=(95e-6, 8.5e-6),
                       ns=7, sigz=0.7e-2)          # the strong beam as one element; ns=1 is the 4D kick
offset_slices!(gsb, Dict(:dim => :x, :coef => 2e-4, :frequency => 394e6))   # the user's slice offsets, in place (:add)
gsb2 = offset_slices(gsb, z -> (0.0, 0.0, 1e-5 * z, 0.0); mode=:replace)   # on a copy; the bunch's own tilt (a point's zeta) stays
XYCouplingSpec(ip.twiss); MomentumDispersionSpec(ip.dispersion); CrabDispersionSpec(ip.dispersion)
```

Conventions, stated in each kind's `element_help`: `Linear6DSpec`'s `R1`/`R2`
are the Edwards-Teng coupling BLOCK `C = adj(R)/sqrt(1 + det R)` (with
`form1`/`form2` selecting the Edwards-Teng form), while `XYCouplingSpec`,
`Beam`, `ChromaticityKickSpec` and `LumpedRadSpec` take the matrix `R =
(r1, r2, r3, r4)` itself; the object converts. `ChromaticityKickSpec` and
`LumpedRadSpec` store the point's form (`form`, 1 or 2) and couple in it, form 2
reaching them only through the point (D11);
`GaussianStrongBeamSpec(; optics)` consumes a dispersive point at the slice
level (with `sigz` and `sigma_delta`, design `design/strong_beam_element.md`
S2); the deprecated `ThinStrongBeamSpec`, kept for existing scripts and
warning once per process, is transverse and refuses one.


The two cavities take the lattice's reference particle in place of their flat
reference keywords, on either route and in the typed and `harmon` forms, the
recommended spelling since the reference batch (design D12; record
`docs/history/machine_description_reference_2026_11_25.md`); the flat keywords
remain accepted on their own and store the same numbers bit for bit:

```julia
ref = ReferenceParticle(; charge = 1, mc2 = PMASS_EV, E0 = 275e9)
ThinRFCavitySpec(400.8e6; voltage = 12e6, reference = ref)              # in place of e0, mc2, charge
ThinRFCavitySpec(400.8e6; strength = 12e6 / 275e9, reference = ref)     # in place of beta0, gamma0
ThinAcceleratingCavitySpec(1.3e9; voltage = 25e6, reference = ref)      # the ENTRY reference
```

`reference_beta_gamma(ref)` is the derivation the constructors use, so the
stored `beta0`, `gamma0` and `strength` are the flat call's and `reference`
itself is not stored (nothing downstream changes). Any of `beta0`, `gamma0`,
`e0`, `mc2`, `charge` given beside `reference`, whatever its value, is refused
by name, as is a `reference` that is not a `ReferenceParticle`; the flat
voltage route keeps `charge = 1` as its default, and `e0`, `mc2` or `charge`
given on the strength route (no `voltage`) is refused by name rather than
ignored, and the five flat keywords are read by presence, so an explicit
`nothing` is refused by name too. `construction_help` and
`element_help` of both kinds name the keyword.

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
?MultiProcessExecutionPolicy      # threads, ranks, and shard = :chunk_aligned | :balanced (the rank-count rule)
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
?save_run_artifact
?TaskOutput
```

`TrackingTask` takes a tuple or vector of elements, a `BeamLine`, a `Lattice`
or a one-lattice `Machine`; `StrongStrongTask` takes two of the same, one per
beam (the same line or lattice twice included), or a `Machine` with two
lattice names, `StrongStrongTask(machine, :ESR, :HSR; ...)`, beam 1 tracking
the first, or `StrongStrongTask(machine; ...)` for a machine of exactly two
lattices in declaration order; every form compiles the runtime the tuple
spelling compiles (see "Describe A Lattice").

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

The same artifact can live in process memory instead of on disk
(`storage = :memory`, 2026-11-03; `?RunArtifact`, "In memory", and
`?save_run_artifact`): nothing is written, not even the sidecar lock, until
the explicit save, the path given beside the keyword keeps its meanings as
label, append source and default save target, and the artifact object itself
is the reader's handle:

```julia
art = RunArtifact("result/pic_hcc.h5"; storage = :memory)   # or RunArtifact(; storage = :memory)
# ... run the task with artifact = art
read(TaskOutput(art), :moments; name = "proton")   # the live image, during or after the run
read(MomentOutput(art; name = "proton"))
save_run_artifact(art)                             # the image to result/pic_hcc.h5, byte for byte
save_run_artifact(art, "elsewhere.h5")             # or to another path
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
read as `nothing`. A continuation is validated before anything is written
(2026-10-19): every by-name refusal of the prepare leaves the file
byte-identical, a refused probe bind leaves every group's rows and cursor as
found, and the replay rule -- rows at or beyond the window's first turn
dropped per group, `/losses` included -- is applied once every bind is in.
`read(out, :losses)` on a continued file therefore spans every window the
file holds (rows and `aperture_counts` under the replay rule), while its
`summary` is the last `execute!`'s beam.

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
itself does not honour it. Every reader applies that cursor (2026-10-19):
the cursor is the row index the writer owns (`rows_valid`, with
`rows_valid_through_turn` its turn), rows beyond it are a torn tail from an
interrupted write and are not returned, `read(moments, :record_count)`
counts the rows a read returns, and the table of contents `read(out)`
reports `rows` beside `rows_on_disk` for every named group. A file written
before the row cursor existed reads whole, with a warning naming the group,
and is refused by name under `append = true` (use a new path or
`append = false`).

What a run's artifact RESOLVED is on record (2026-10-16): under
`with_execution_audit`, `prepare_run_artifact!` records one
`:run_artifact_output` receipt per `execute!` with `task`, `artifact` (the
path), `append` beside `continued` (an existing file continued, or created
fresh), `capacity`, `record_turn_modulation` beside `recording` (recorders
built: the switch on and a modulated element in the line) and `execution`
(the ledger row); the task records its own output receipt beside it --
`:tracking_output` (`artifact`, `channels`, `loss_report`) or
`:strong_strong_output` (`artifact`, `channels`) -- after the artifact is
prepared, so a refused prepare leaves none; the `TrackingTask` records its
receipt after every refusal that can stop the run before its first turn (the
observers' prepare, the fused-route refusal), beside its two per-run
receipts. `tracking_task_option_schema()`
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
?runtime_variants
?runtime_examples
?tracking_method
?TrackingContext
?with_turn
?with_index_offset
?survey
?FloorFrame
```

`survey(elements)` returns the floor plan: one `FloorFrame` (global `X, Y, Z`,
`theta, phi, psi` and the exit arc position `s`) per element exit in MAD-X
`SURVEY` conventions, for a line spec, a `BeamLine` or a tuple of placements
(`docs/theory/floor_plan_survey.md`; checked element for element against a
committed MAD-X `SURVEY` reference by `MADXSurveyConsistencyContract`).

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

## Describe A Lattice

The machine description (design note `docs/design/machine_description.md`,
stage 2; record `docs/history/machine_description_stage2_2026_11_25.md`)
puts a top-level `BeamLine` into a `Lattice` record with the context the
line does not carry: the entrance `ReferenceParticle`, the knob root the
line's expressions must live under, and the numeric type every element
shares. The `@elements` block (`@element` for one declaration) declares
elements by registered kind name over the friendly constructors, the
binding name as each element's `name`, the header type as each element's
`numeric_type` (`Float64` when omitted), and `line(...)` as `BeamLine`; the
shipped DBA example declares its ring this way in a module. Use Julia help:

```julia
?Lattice
?Machine
?ReferenceParticle
?@elements
?@element
```

```julia
ref = ReferenceParticle(; charge = 1, mc2 = PMASS_EV, E0 = 3.0e9)   # spelled once
@knob ring.qf_k1 = 1.5                       # `ring`: the knob root of the shipped modules

@elements begin                              # `@elements Float32 begin ... end` types the block
    QF   = quadrupole(L = 0.35, k1 = @knob_expr(ring.qf_k1))
    QD   = quadrupole(L = 0.25, k1 = -1.1)
    D    = drift(L = 0.6)
    B    = sbend(L = 1.0, angle = 0.2)
    RF   = thin_rf_cavity(500e6; voltage = 2e6, reference = ref)
    RING = line(QF, D, B, D, QD, D, B, D, QF, RF)
end

lattice = Lattice("DBA_RING"; line = RING, reference = ref, knob_root = :ring)
beam    = Beam(N, policy; reference = ref, ...)       # the same object, spelled once
task   = TrackingTask(lattice)                        # the placements the bare line gives
result = analyze(TwissDispersionAnalysis(), lattice)  # one_turn_matrix(lattice) likewise
```

Two tripwires run when the lattice is built, so a convention becomes a
check. Every knob the line's expressions depend on, transitively and through
placement overrides, must sit under a declared root: a dependency outside
the roots, or any dependency when no root is declared, is refused by name
with the element's provenance path, the parameter, the knob path and the
remedy. Every element must carry the lattice's numeric type: a stored
`numeric_type` must equal `eltype`, and an untyped element passes when the
promotion of its stored numeric parameters over `eltype` is `eltype`, so a
kind with no numeric value passes and a wider literal is refused with the
typed-form remedy. The friendly constructors accept knob expressions since
this stage (design D10; `docs/knob_control.md`, section 2): a number is
converted, an expression is kept, and the folds build expression nodes, so
`k1 = @knob_expr(ring.qf_k1)` above stores the expression in `kn`; a
derivation the tree cannot express still refuses by name with the
flexible-form remedy (what still refuses: the RBend `chord` with an expression `angle`, the strong beams' optics and covariance keywords, the inert third components of the strong beam's `angle`, `curvature` and `mean`, the cavity's `harmon`, and every entry of a `LinearOptics` point, kept numeric on a measurement; the stage record lists each with its remedy). The lattice's
`ReferenceParticle` is the object the beam and the cavities take: `Beam(N,
policy; reference = ref)` in place of `charge`, `mc2`, `E0`, and
`thin_rf_cavity(f; voltage = V, reference = ref)` in place of `e0`, `mc2`,
`charge` (or `beta0`, `gamma0` beside `strength`), the one object spelled once
(see "Construct Beams" and "Construct Elements"; record
`docs/history/machine_description_reference_2026_11_25.md`); no task yet
compares the beam's reference with a cavity's stored pair at compile, the
compile-path half of D12 (`todo.md`). `Lattice` forwards `line_entries`, `s_positions`,
`find_entries` and `knob_report` to its line, and `eltype(lattice)` is its
numeric type. `StrongStrongTask` takes two lattices as it takes two lines,
one per beam, and a `Machine` since stage 3 (below).

`Machine` (stage 3; record
`docs/history/machine_description_stage3_2026_11_25.md`) is the facility's
namespace of lattices by name, in declaration order, with the knob roots the
lattices share: nothing about how lattices connect, no closure and no
interaction-point concept (design D5). A bare `Lattice` is a one-lattice
machine implicitly, so the single-ring user never sees this level;
`Machine(lattice)` spells it explicitly, and `TrackingTask`, `analyze` and
`one_turn_matrix` take a one-lattice machine as they take the lattice.
`StrongStrongTask(machine, :ESR, :HSR)` pairs two lattices by name (beam 1
tracks the first; the same name twice is legal, two beams in one ring), and
`StrongStrongTask(machine)` takes a machine of exactly two lattices in
declaration order. In every form the task stores the placements the bare
line gives, so the runtime it compiles, its kernels and its per-turn work are
the tuple spelling's (the suite pins the compiled runtimes and the tracked
coordinates of the two spellings equal). One tripwire runs at construction,
the machine-level half of the knob-root check: a root two lattices declare
must be declared shared on the machine (`knob_root = :ip` below), and no two
distinct roots may overlap as dotted prefixes (`ring` and `ring.arc`); both
are refused by name with the remedy, as are a duplicate lattice name, an
entry that is not a `Lattice`, an unknown name in `machine[:X]` (the message
lists the names held) and a machine of several lattices handed where one
line is wanted (`machine[:NAME]`, or the pairing form, is the remedy).
`keys`, `haskey`, `length` and iteration read it; `==` and `hash` are
structural; `show` is one line. The machine stores lattices and shared roots
only: beam definitions and machine-level reference particles are deferred
until a consumer reads them (the record), the TOML form is stage 4 and
`with_overrides` stage 5.

```julia
esr = Lattice("ESR"; line = ESR_LINE, reference = electron, knob_root = (:esr, :ip))
hsr = Lattice("HSR"; line = HSR_LINE, reference = proton,   knob_root = (:hsr, :ip))
eic = Machine("EIC"; lattices = (esr, hsr), knob_root = :ip)   # `ip`: the root both rings read
task = StrongStrongTask(eic, :ESR, :HSR; policy = policy, ...)  # beam 1 tracks ESR
keys(eic)                     # ("ESR", "HSR"), declaration order
eic[:HSR] === hsr             # true; eic["HSR"] likewise
Machine(esr) == Machine("ESR"; lattices = (esr,))   # the implicit one-lattice machine
```

## Fixed Particle Tunes

`Linear6DSpec` accepts `particle_tunes` in its optics form. For example,
`particle_tunes=(nux=measured_nux,)` assigns one horizontal tune per global
particle and retains the nominal `dmu/(2pi)` values in the other planes.
Any nonempty subset of `nux`, `nuy`, and `nuz` is supported. Each named value
may be a finite scalar, a global-length array, a six-argument coordinate
function, or `TuneDistribution(d)`. `TuneFunction(f; planes=...)` and
`TuneDistribution(d; planes=...)` supply joint sources over a named subset;
a tuple of disjoint declarations can combine a joint pair and the third plane.

```julia
?Linear6DSpec
?ParticleLinear6D
?TuneFunction
?TuneDistribution
?TuneHistogram
?clear_particle_tunes!
?particle_tune_tables
```

A function receives physical `(x, px, y, py, z, pz)` at the element entrance,
after upstream maps and before linear normalization. A distribution implements
`rand(rng, distribution)` using the supplied RNG; no additional distribution
package is required. `TuneHistogram(edges, weights)` treats weights as bin
masses and samples uniformly within the selected bin. Sources assign signed
absolute tunes, not offsets. First passage binds the table, and continuation,
cache rebuilding and coordinate reset retain it. `clear_particle_tunes!`
requests a fresh preparation epoch without moving coordinates or clearing a
saved reset reference. `particle_tune_tables` returns independent host copies
of local labels, placement identities, global shard ranges and preparation
provenance; MPI callers must retain global index correspondence when reusing
those arrays.

The compiled `ParticleLinear6D` keeps tunes and cached rotations on the beam's
CPU or CUDA backend. The active form supports Float32/Float64 `TrackingTask`
tracking, including the CPU multi-process policy. First-version restrictions
are explicit: no arbitrary-matrix form, scalar/contextless tracking,
StrongStrongTask, nontrivial placement wraps, kept-whole nested placement, or
arbitrary action hooks. Coordinate functions require a finite entrance
ensemble; arrays and distributions assign labels even to lost slots. An
active particle-tune map has no unique matrix or Twiss analysis; construct an
ordinary optics-form `Linear6DSpec` from a selected stored triple to analyze
that particle's fixed map. See the [reviewed design](design/particle_tunes.md)
for transaction boundaries, random-stream semantics and validation.

`runtime_type(spec, method)` selects the configured runtime, while a type-level
query returns the default. `runtime_variants(query, method)` and
`runtime_examples(query)` enumerate declared variants and representative specs
from the same metadata used by the registry and validator.

## Repeated Noise Trials

Put `PhaseSpaceResetSpec()` first in a `TrackingTask` line to capture each
particle's initial coordinates once and restore them before subsequent turns.
Noise still follows the absolute turn. CPU/CUDA snapshots stay on their own
backend, and MPI ranks retain their own shards. Record the response after the
physical lattice. One reset per task is supported, with `loss_report=true`.

```julia
?PhaseSpaceResetSpec
?clear_phase_space_reset!
?phase_space_reset_summary
```

The summary contains bounded totals for the latest execution window and its
last trial; `clear_phase_space_reset!` explicitly rearms capture without
rewinding turns or RNG streams. An artifact writes each trial under
`read(TaskOutput(path), :reset_trials; name="reset")` and repeated aperture
events under `:reset_losses`. Use `RunArtifact(path; append=true)` to retain
earlier execution windows; replay replaces rows at or beyond its starting
turn. These are trial outcomes, distinct from the
permanent-loss `/losses` product. Detailed lifecycle, restrictions and the
independent tracking oracle are in [the design note](design/phase_space_reset.md).

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
?linear_optics
?dispersion_interval
?Determined
?UndeterminedQuantityError
?OpticsAnalysisError
?ANALYSIS_STATUSES
?one_turn_matrix
```

`linear_optics(result; frame=:ring)` closes the loop between the analysis and
the constructors: the periodic optics of the analysed 6x6 map as a
`LinearOptics` point in the caller's coordinates (the Edwards-Teng `R` and
`form` the analysis presents, the eigenmode Twiss of that form, the canonical
dispersion, the longitudinal mode's Twiss), so that
`Linear6DSpec(o, advance_phase(o, result.physical.tunes))` rebuilds a map with
the analysed optics and `Beam(N, policy; optics=o, emit=...)` is matched to it.
The analysis labels mode 1 as the x-dominant mode, so a point written in the
other labelling (a form-2 point whose first mode is y-dominant) comes back as
the equivalent form-1 point with the two transverse modes exchanged; the map it
rebuilds is the same ((T4) of the theory note).

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
