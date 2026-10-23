# Comprehensive-audit fix batch 3 (2026-10-21): the runtime rows

**Status:** complete 2026-10-22: eight units merged (unit H verified and gated with the
next push, unit J waiting on the owner), the two-arm full gate green with CUDA active on the
integrated tree 1128406 (section 4, the third attempt; the first two were red at one defect
each, both fixed on the merged tree and recorded there); the push was authorized by the
owner in advance (2026-10-20, "Push after gate green then move on next step"); the push and
its CI run are recorded by the next push's addendum (batch 3b, unit H).

Batch 3 of the 2026-10-18 comprehensive audit's fix campaign
([`comprehensive_audit_2026_10_18.md`](comprehensive_audit_2026_10_18.md); batch 1 is
[`comprehensive_audit_fixes_2026_10_19.md`](comprehensive_audit_fixes_2026_10_19.md), batch 2
[`comprehensive_audit_fixes_2026_10_20_batch2.md`](comprehensive_audit_fixes_2026_10_20_batch2.md)),
on the owner's word of 2026-10-20 ("Go ahead Batch 2, 3, 4 one by one"). The rows whose
subject is the RUNTIME -- the strong-strong solver stack, the task walkers and the output
tail, the observers, the element kinds, the weak-strong option values, the floor plan,
the beam and its statistics, the knobs, the analysis driver -- taken after the instrument
rows because the instruments batch 2 repaired are what verify these. Ten rows were briefed as units E to N; nine were launched (unit J waits on
the owner, section 1) and eight landed in this batch: unit H's agent ended three times in
API timeouts with nothing on disk, a fresh agent was started, and the batch went to its gate
without it (section 2, H).
Each unit a sub-agent proposing one commit on its own branch from `main` at da40d39
(batch 2's tip, CI run 467 green) under a common brief: a regression test written first
and shown red on the unfixed tree, the fix, the test green, the neighbours re-walked. The
integrator read every diff and report, ran every unit's regression testsets RED on the
unfixed base and GREEN on the integrated tree after its merge with the unit's neighbours,
made the two cross-unit changes the units had to leave for the merged tree (section 3),
and ran the pre-gate checks and the gate. Unit reports, probes and the integrator's logs:
`result/fix_batch3_2026_10_20/{plan,units,probes,verify}/` (git-ignored scratch; the
numbers are quoted here; `verify/INTEGRATION.md` is the red/green table).

## 1 Owner decisions (2026-10-20 and 2026-10-21)

1. **Order.** Batches 2 (instruments), 3 (runtime rows) and 4 (documentation and the Minor
   pointer) one by one; this record is batch 3.
2. **Method.** Sub-agents propose, the integrator verifies, as in batches 1 and 2; the push
   after a green gate was authorized in advance (2026-10-20, "Push after gate green then
   move on next step").
3. **Unit J waits.** The row "Cross-backend rounding classes: composition, regime,
   algorithm" (F-100, F-101, F-118, F-120, F-162, F-103, F-105) opens on two design
   questions put to the owner on 2026-10-20 -- a turn-growth regime option (qualified
   declarations, or a growth model) and the Faddeeva option (one algorithm on both
   backends, or an algorithm class); the integrator recommended the first choice of each.
   No answer had arrived when this batch closed; the row stays open with its brief
   (`result/fix_batch3_2026_10_20/plan/J.md`, decision slot `DECISION_J`) ready, and unit
   I's CUDA re-measurement of the `:exact` and `:chromatic` kernels (section 2, I) is the
   first input it will read.

## 2 Units and what landed

### Unit E: strong-strong solver stack (F-5, F-6, F-8, F-9, F-11, F-13 to F-26, F-41)

`fix3-strong-strong-stack`, fa262f2, 17 files (+933/-523). All twenty findings of the row:
the 6D CUDA spectral deposit tripwire's denominator (F-5); the luminosity-schedule memo keyed
by a run epoch beside the schedule and the turn, so a one-turn run cannot read the previous
run's evaluation (F-6); `LongitudinalSlices.live` with the soft-Gaussian and spectral default
luminosity scales dividing by the live count, PIC's full-count convention pinned beside them
(F-8); the five-event dropped-node tally on CPU and both CUDA node routes (F-9); one joint
`_pic_sliced_pair_bad` verdict for both owners of a sliced pair, PIC and Gaussian-PIC, so
every rank decides alike (F-11); luminosity buffers sized from the luminosity grid and the
workspace pool keyed by it (F-26); linear-range profile buffers so a tall grid runs on the
sliced route (F-41); four dead twins deleted with the launch census recounted (F-13, F-15,
F-17, F-18); the CUDA routes calling `_pic_luminosity_mesh` (F-14); a loud node lookup
(F-16); one longitudinal-slicing-method table with its aliases and one deposit-method tuple
feeding every validator and message (F-21, F-25); `oftype(S, 0.5)` at three sites so a
Float32 solver stays in Float32 (F-22); the design note, docstrings and one message (F-19,
F-20, F-23, F-24); and the integrator's item from unit F: the `:strong_strong_output`
receipt recorded after the observers' prepare and the commit, so a refused run leaves no
receipt claiming it ran. Twelve regression testsets, each red on the unfixed tree or by
injection where the defect's precondition required it, green after; the pre-gate checks
`validate_configuration_metadata()`, `PublicConfigurationEffectivenessContract` and
`SolverOptionEffectivenessContract` passed; the PIC-cache and Gaussian backend-consistency
scripts passed at the gate's reduced size with the GPU leg required. A `Contracts.jl`
caller of the changed scale signature was found by the census grep, not by a test, and
fixed. Red on the unfixed base in the integrator's run (`E_red.log`, twelve of thirteen
testsets red; the receipts testset's new block is red only on the unit's tree before the
receipt move, `probes/E/run4b_injection_red.log`), green after the merge with twelve
neighbours (`E_green.log`). Not verified by the unit: the MPI launcher testset (where the
divided consequences of F-6, F-8, F-9 and F-11 are proved; one-rank branches shown inert),
the F-22 change's one-rounding move of a Float32-solver result (no literal pin exists for
it). Priced, not fixed: the spectral family's three hand copies of the luminosity-mesh
arithmetic, the `_cuda_pic_async_luminosity_enabled` constant switch, the fifteen CUDA
launch sites encoding the deposit method by hand, a finite-but-overflowing `:extrema`
extent on the sliced route.

### Unit F: Tasks.jl walkers and the output tail (F-75, F-76, F-77, F-80, F-81, F-82, F-83, F-106)

`fix3-tasks-walkers`, 6fe2031, 5 files (+611/-75). The arc walk forwards a `LineEntry`
whose spec is a hook to the hook itself, as the compile walk does, so the probe arm sees a
hook placed through `BeamLine` and its probe view carries `s` (F-75); a hook inside a line
that compiles whole -- an own-state line placed bare, a line nested in a tuple, a vector or
another line -- is refused by name at construction and at the compile walk's two whole-line
sites, both task kinds, where it died with a raw `MethodError` (F-81, with F-240); one hook
table `_HOOK_KINDS` and one enumeration `_run_scheduled_hooks` over both placements feed a
single per-run unfireable-schedule warning naming every hook in a `hooks` keyword beside
`turns` and `first_turn` (F-76, F-83: the old message's `\` sat outside the string literal
and made two keywords one); the stored turn advances only after the output tail completes,
and a failure there closes the artifact and releases its lock before the error propagates
(F-77); the `:tracking_output` receipt is recorded after the last refusal (F-80); the crash
path reconciles the loss accounting once for both consumers and closes the artifact when
the loss write fails (F-82); raw thin specs fold their declared named strengths from the one
fold registry, so `ElementSpec{:thin_quadrupole}(; k1l=0.1)` no longer compiles to the
identity (F-106). Four testsets red on the unfixed base (`F_red.log`: 59/55, 27/8/1, the
hook-kind derivation erroring on the absent table, 10/7), fourteen green after the merge
(`F_green.log`). Not verified by the unit: the MPI legs of the restructured tails (reasoned,
not run), CUDA (nothing device-reachable changed). Three twins named for other units: the
strong-strong receipt order and unfireable warning (unit E and the integrator, section 3),
the `_reject_folded_override` wording (unit K), the lattice-magnet raw-fold twin of F-106
(unit H).

### Unit G: observers, cost and provenance (F-78, F-79, F-66, F-85 to F-90)

`fix3-observers`, 6f3fcdd, 9 files (+1104/-175). The CPU moment row is one fused serial
two-pass fold whose terms a `@generated` function emits as straight-line code, the arrays
read in place: bitwise the fold it replaces (sixteen `/moments` fixtures byte-identical
before and after) and 15.6x faster at the audit's fixture (40.6 to 2.6 ms, 4.80 MB to 7 KB
per 27-moment row at N = 1e5; F-78, F-87); the snapshot builds its block from views (9.6 MB
per fire to below the no-op turn's own allocation; F-79); `sigma` and `octaves` are in the
turn-modulation provenance entry, the artifact's slot attributes and the reader, with
defaults for older files (F-66); the path registry warns only for an earlier artifact still
holding its file open (F-85); the BPM centroid accumulates in Float64 on both paths, records
a `:bpm_reading` receipt per reading and stamps its device model on `/bpm/<name>` (F-88,
F-90); one observer object placed twice is refused by its cause before any bind (F-89);
`planned_records` and the PredicateSchedule refusal are gone; the BPM docstrings state the
append rule (F-86). Eight new testsets red on the unfixed base (`G_red.log`, with the
fix's symbols stubbed so each reaches its pin) and green after the merge with ten
neighbours, the fused CUDA row and the CPU/CUDA masking twin among them (`G_green.log`).
Unit T's row-cursor fixture (batch 1) now injects through a self-disarming element read,
valid on both trees. Not verified by the unit: an MPI run of the fused row (one-rank
identity by construction, the collective count read, not measured); the CUDA kernel is
untouched and its class unchanged by inference; all timings carry a load average of 43 to
48 and are ratios against same-process baselines.

### Unit H: element kinds, silent reads and conventions (F-92, F-93 to F-99, F-160, F-161 to F-167)

Not in this batch. The unit's agent was launched with the others and ended three times in
transient API timeouts after long reading phases, each time before writing anything to
disk (its worktree `fix3-H` clean at da40d39, no report, no probes); a fresh agent with a
focused brief and instructions to persist incrementally was started as the batch went to
its gate, so its result, if it lands, is verified and gated with the next push (batch 4's,
or a batch of its own). The row "Element kinds: silent reads and conventions" (F-92, F-93
to F-99, F-160, F-161 to F-167) stays open with that note; the integrator passed unit F's
note on the lattice-magnet raw-fold twin of F-106 and unit K's edits of `patch.jl`,
`misalignment.jl` and `ref_tilt.jl` to the new agent for a clean merge.

### Unit I: weak-strong element option values `:chromatic` and `:exact` (F-119 to F-125)

`fix3-weak-strong-options`, 32b2b57, 6 files (+562/-55). The forward chromatic drift hands
the kick the collision point's own `S = (z* - zo)/2` (F-119: the dual-Jacobian symplecticity
residual 4.54e-9 to 2.14e-13 thin and 1.43e-3 to 2.36e-13 for five slices, at the floor of
the `:hirata` and `:exact` models); the forward exact drift forms
`H_ex = (px^2 + py^2)/((1 + pz) + ps)`, cancellation-free (F-120: pz from 891.5 to 0.5 ulps
of scale against a 256-bit reference; the CUDA re-measurement for unit J: 0 violations in 18
class rows, `:exact` pz 0.0 to 3.5 ulps where it read 1024 to 4096, the class declarations
untouched); `_longitudinal_factor` and `_dispersion_graph` generic, so a ForwardDiff dual
passes through `gaussian_strong_beam_covariance` (F-121); `hvoffset` validated by name with
`coef` and `frequency` required and its waveform computed in the element's type (F-122,
F-123); `angle[3]`, `curvature[3]` and `mean[6]` refused by name when non-zero, with a
joint-move override so the effectiveness ratchet 549/34/23 is unchanged (F-124); position
variances below the covariance's rounding floor and singular coupled position blocks
refused at construction and compile (F-125). Documentation: the theory note's section 7
states the collision-point convention and 7.2 the cancellation-free form; the fingerprint
script's two "angled" configurations zeroed. Five new testsets red on the unfixed base
(`I_red.log`), the `:chromatic` and `:exact` bitwise pins re-pinned by 1 to 4 ulps with the
mechanism in the comment (the re-pinned testset red on the unfixed base, 15/2), the
effectiveness contract green as the control; green after the merge with its neighbours
(`I_green.log`). `validation/tracking_backend_consistency.jl` with the GPU required at
N = 2000: 34 instances within class. Not verified by the unit: Float32 `:exact` and
`:chromatic` kernels compiled and ran but have no measurable class (F-103, unit J);
`validation/gaussian_slicing_convergence.jl` and the recorded convergence tables of
`docs/theory/gaussian_longitudinal_slicing.md` were not re-run (the `:chromatic` column moves
by a first-order-in-phi amount; a follow-up candidate, not a claim).

### Unit K: floor plan and beam-line geometry (F-126 to F-138, F-232, F-240)

`fix3-floor-plan`, 10a4c23, 9 files (+731/-121). The floor plan rolls every step, patches
included, by the `ref_tilt` of the MERGED placement and of the top-level line (F-127,
F-128, F-129, F-232); one patch-convention normaliser serves tracking and the survey, and
the arc sagitta is cancellation-free (F-133, F-134); line placements refuse `L`, `entries`
and `name` at assignment, where the value is written, and the keyword `BeamLine(; entries)`
copies its placements (F-131, F-132, F-138); a dual alignment parameter on a line
differentiates like the element's (the wrap type widens, the wrappers'
`_required_beam_eltype` report the widened type; F-126); `knob_report` sees a line's own knob
parameters and a placement's knob override (F-130); `find_entries` matches friendly types
through the registry resolver, the line compile refuses an in-line hook by name, and the
design note states the rule with unit F's `_refuse_hooks_in_whole_line` (F-240); dead code
and three stale documents corrected (F-135, F-136, F-137), unit F's `_reject_folded_override`
wording among them. Eight new testsets red on the unfixed base (`K_red.log`, the nested-lines
control green), sixteen green after the merge with the MAD-X survey contract and the surveyed
cavity's CUDA class pin among them (`K_green.log`); `validate_element_metadata()` passed (607
defaults); the MAD-X survey contract 9 of 9 at 7.1e-15; the survey table's generator
reproduces the committed table byte for byte; the snapshot unchanged. Not verified by the
unit: a dual-typed wrap on CUDA (a CPU-only construction), the task-level refusal of a
Float64 beam against a dual-wrapped line (reasoned from the rule).

### Unit L: beam construction and statistics (F-185, F-186, F-187 to F-191, A-6)

`fix3-beam-stats`, 8b94c45, 6 files (+619/-90). `Beam` refuses `sigma` with `emit` and any
two spellings of the coupling coefficients by name (F-185); `beam_statistics` under
`allow_lost_particles` compacts the survivors and runs the unmasked reductions, one
reduction order, so the masked statistics equal the survivors' bit for bit at any size and
the suite's pins return to `==` (F-186); every `Beam` keyword is validated before anything
is activated or drawn, so a refusal consumes no stream, and `cutoff`, `seed` and `rng_id`
are refused by name when they could not be honoured (F-187, F-190); the counter path draws,
standardizes and normalizes on the host and uploads once, so a CUDA beam is the CPU beam of
the same seed and stream bit for bit (F-189; every recorded CUDA seeded beam moves by
O(ulp), no CPU bit moves); `write_beam_coordinates` refuses `npart` outside the count and
`read_beam_coordinates` refuses a record past the end, a torn header and a negative record
by name (F-188, F-191); a mixed-type `Phase6DRep` is refused by name; `BeamParams(; ...)`
works with any keyword omitted (A-6); `summarize_registry()` lists concrete members only;
the source-map tripwire walks nested directories; the knob-control catalogue entry names
what its script names, with a tripwire over every entry (one snapshot line). Nine
regression testsets red on the unfixed base (`L_red.log`, every count the unit's own) and
green after the merge with seven lost-particle and masking neighbours (`L_green.log`; two
neighbours needed suite-level fixtures the unit's preamble lacked and are green in
`L_neighbours_green.log` and `K_green.log`); `validation/beam_optics_interface_consistency.jl`
passed on CPU and CUDA. Not verified by the unit: the MPI launcher testset, the deprecated
explicit-`rng` CUDA path, the masked `beam_statistics` cost at production size.

### Unit M: knobs, the derivative path and the edges (F-181, F-182, F-183, F-184)

`fix3-knobs`, 5de47e0, 5 files (+556/-51). `knob_derivative` validates its differentiation
variable against the registry: an unknown path is refused by name instead of yielding the
constant `0.0` (a silent column of zeros in a response matrix), a dependent variable is
refused with directions under `through_registry=true` and allowed as the free-symbol partial
under `false`, a forgotten reference is refused when the registry is consulted, with a
runnable docstring example the suite executes (F-181); five edges -- `signbit` for the
negative-zero literal, `chopprefix` in `propertynames`, a constant-only right-hand side
installing an independent knob, `list_knobs` and `knob_report` selecting a NAMESPACE through
one predicate `_knob_under_prefix`, `knob_value(::Real)` the identity (F-182); the MPI
extension's broadcast, scalar broadcast, barrier and row gather clocked under their receipt
kinds, with a suite tripwire pairing the core's receipt kinds with the extension's clocked
implementations (F-183); `_script_mode_weakdep_gate`, quiet on an `ArgumentError` and
warning by name on a load failure, with the "load path" wording and the world-age caveat
documented, and `resolve_knobs` reading the epoch before the values (F-184). Two new testsets
red on the unfixed base (`M_red.log`: 23/28/5 and the four unclocked kinds; "Knob control"
green as the control) and six green after the merge (`M_green.log`); a two-rank `mpiexec`
probe: four kinds unclocked before, none after, every collective's result unchanged. Not
verified by the unit: the MPI launcher testset, the world-age warning itself (printed from
C), the concurrent receipt race (pinned by a deterministic mutating container). Two notes
for other files: the wiring filter of `beam_line.jl` (section 3, the integrator) and the
ForwardDiff twin gate in `src/Octopus.jl` (left as a note; unit L's file, out of its scope).

### Unit N: analysis driver diagnostics and uncertainty fold (F-194, F-195, F-196 to F-199)

`fix3-analysis-driver`, 0c33a60, 10 files (+493/-127). `map_uncertainty` and the
finite-difference provenance uncertainty are multiplied by the scaling's gain
`max_ij C_ii / C_jj` (`_scaling_gain`, the operator norm of the similarity; 1 under `:none`,
63 on the DBA ring) before the `rho_M0` fold, with the four arms and the gain in
`diagnostics.resolution` (F-194); `_agglomerate` breaks a capped-chord tie by the smaller
gap, so a repeated betatron pair merges before it absorbs an isolated synchrotron pair and
`diag(R(.7), R(.7), R(.05))` gets a unique eta instead of one six-member cluster (F-195);
`DispersionRoutes.executed`, filled at each kernel call, is the one source for the receipt's
`executed`, the diagnostics rows (executed routes only, `Determined{Float64}` residuals and
conditions instead of `0.0` placeholders) and the Newton cap's activity (F-196, F-198); the
coasting canonical area uses the kernel's `1 + ...`; a synchrotron tune is accepted in
(0, 2pi) except pi (F-197); the closed-orbit receipt carries `effective_atol` and
`AnalysisDiagnostics` gains `closed_orbit`; `LinearizedMap` refuses a non-6x6 matrix at
construction; the constructor's typed keywords are validated with `ArgumentError`s and Bools
refused wherever a number is expected (F-199); the FD docstring's unreproducible 2.1e3 is
replaced by harness-backed numbers (65 on the suite's cell, 2.1 on the DBA ring) with a pin.
Two new testsets red on the unfixed base (`N_red.log`: 6/11/3 and 21/12/46) and green after
the merge with the six pin-holding testsets, the stage-6 identity contract and the
architecture check (`N_green.log`); the three analysis contracts pass through `validate`;
`validation/twiss_dispersion_identities.jl` at 200 + 20 maps gives a byte-identical TSV
before and after. The frozen design note still states the old receipt shape, agglomeration
rule and uncertainty fold: its amendments are recorded in section 5 of this record, not
edited into the frozen body. Not verified by the unit: the `-C haswell` arm, the stage-6
suite testsets through its runner (the integrator ran them).

## 3 Integration

Merge order into `fix3-batch-int` (from da40d39), each unit verified RED on the unfixed
base before its merge and GREEN on the integrated tree after it, with its neighbours
(`result/fix_batch3_2026_10_20/verify/INTEGRATION.md` holds every count): F (46d264a),
N (07131ea), M (198fefd), L (aefc75a), K (4b54ea7), the integrator's first change
(840ced9), G (4dc0450), E (7061518), the integrator's second change (ff09716), I
(e3b9757), and the integrator's third and fourth changes after the first two gate attempts
(5eb10ab and 1128406, section 4). Every merge was clean: no file conflicted, the units having been
cut to disjoint files and disjoint regions of the suite. Red runs were taken in dedicated
worktrees detached at the unfixed base (`fix3-red`, `fix3-red2`), the unit's `test/`
checked out onto the base's `src/` and restored afterwards; green runs on the integration
worktree after each merge. The suite's helpers the cut testsets reference were supplied
by the units' preambles and by three integrator preambles that evaluate the suite's own
definitions by anchor (`probes/int/`); each run names the preamble it used.

The two cross-unit changes the units named and could not make on their branches, made by
the integrator on the merged tree with the same red-then-green discipline (the third, a
regression the first gate attempt found, is in section 4):

- **840ced9, the wiring view's namespace prefix** (unit M's predicate, unit K's twin).
  `knob_report(elements; prefix)` in `beam_line.jl` selected its sites with a bare
  `startswith`, so `"krw_report.tri"` selected the knob `krw_report.trim` and `"HSR"` would
  select `HSRx.y`, where `list_knobs` and the registry's `knob_report(; prefix)` match a
  namespace through `_knob_under_prefix`. Two assertions in "knob_report over a container
  reports the wiring" (a string prefix that is not a namespace selects nothing; the
  namespace selects both sites): RED on the integrated tree before the change
  (`int_wiring_red_green.log`, 11 passed, 1 failed) and GREEN after it (`G_green.log`).
- **ff09716, the strong-strong line's unfireable scheduled hook** (unit F's API, unit E's
  call site). `_execute_strong_strong_task!` never asked whether a line observer's schedule
  selects a turn of the window; it now enumerates each line's in-line hook entries through
  the same `_run_scheduled_hooks` and warns through the same `_warn_unfireable_schedules`,
  once per line. The new testset "A strong-strong line's scheduled hook that cannot fire
  warns, as the tracking task's does" (a far schedule warns once naming the observer and
  the window, two lines warn twice, a reachable schedule stays silent): RED on the
  integrated tree before the change (`E_green.log`, 1 passed, 2 failed, 2 errored: zero
  warnings, the control passing) and GREEN after it with unit F's twin and the
  luminosity-channel neighbour (`int_ss_hooks_green.log`).

Runner artefacts, not defects: four neighbour testsets errored under a unit's preamble on
a suite-level fixture or import the title cut excludes (`_FixTArmAtTurn`, `with_logger`,
`test_beam`, `LedgerPeekObserver`, `using ForwardDiff`) and are green with the suite's
definitions supplied (`L_neighbours_green.log`, `K_green.log`, `int_ss_hooks_green.log`,
`I_red.log` after `probes/int/preamble_I.jl`). Three logs carry a stray shell error and a
non-zero exit code AFTER the runner's `TESTSETS-DONE` marker (`F_red.log`, `G_red.log`,
`K_green.log`): the verify scripts were edited while those runs were inside their `julia`
line and bash reads a running script incrementally, so it resumed mid-line in the edited
file; every verdict line is intact and the worktrees were clean afterwards (lesson,
section 6).

The batch's neighbour audit: each unit's own (section 5 of its report), the integrator's
green runs of every unit's testsets with its neighbours after each merge
(`verify/*_green.log`), the two cross-unit changes above, and the pre-gate checks of
section 4.

## 4 Pre-gate checks and the gate

On e3b9757, before the gate (`verify/pregate_b3pre1.log`, `sweeps_wt_b3pre1.log`): the
extracted source sweeps green (the stage-6 pin tripwire 2 of 2, the `Core.Box` allowlist 5 of
5, the detached-docstring sweep 11 of 11), `validate_element_metadata()` passed with no
error, `validate_configuration_metadata()` true, the registry snapshot byte-identical to the
generated text, and the symbols the units removed (`planned_records`, `_compute_moment`,
`_patch_reference_length`, `_floor_children`) absent from `src/` except as the comment that
records the first one's retirement. The backend-consistency and validation scripts the
units ran at reduced size run again in the gate's CUDA arm (the 18-script testset of batch
2).

**The first two-arm gate (e3b9757, tag `b3a1`, 2026-10-21 23:55 to 2026-10-22 03:13) was RED
in both arms at one assertion, and the suite aborted there** (a failing top-level testset
ends the run): testset 219, "Tasks and turn modulation follow-ups: receipts after the
refusals, one warning per cause, apertures inside a bare line, frozen tables and preset
names, once-per-execute! walks, ...", block (e), the 2026-10-16 cost pin on the
once-per-execute! walks: `bytes <= 256` evaluated `352 <= 256` for
`walk = prepare_line_observers!`, identically in the native arm (218 summaries before it,
exit 1 at 01:56) and the AVX2 arm (218 summaries, exit 1 at 03:13; the integrator's request
to stop the doomed second arm by process id was declined by the session's permission
classifier, so it ran to its own failure). Cause: unit G's repeated-observer refusal
(F-89) counted a line's placements inside that walk -- an `Any[]` of the placed observers
and an `IdDict` -- and the unit's neighbour list did not include the pin's testset. Fix
(integrator commit 5eb10ab): the count moves to `_refuse_repeated_line_observers`, run
once per compilation by `_runtime_entries` over the resolved hook entries, before any
bind; the per-execute! walk is allocation-free again and the task-level count stays in
`prepare_observers!`, which the pin does not cover. The refusal's behaviour at `execute!`
is unchanged: the pin's testset GREEN, unit G's testset GREEN (29.9 s), the observer
planner, the strong-strong hook testset and the three source sweeps GREEN on 5eb10ab
(`int_walk_green.log`, `int_walk2_green.log`, `sweeps_wt_b3pre2.log`); the pre-gate
validators and the snapshot are unaffected (no spec, option or public object changed).

**The second two-arm gate (5eb10ab, tag `b3a2`, 2026-10-22 03:14 to 06:02) was RED in both
arms at one error, and the suite aborted there:** testset 283, unit G's "One observer placed
twice in a line is refused by name in artifact mode and still read twice in memory mode",
`UndefVarError: _FixGNoopObserver not defined` at its fifth assertion (282 summaries before
it in each arm, no failure; the walk fix of the first attempt held, the pin's testset
passing at position 219). Cause: the unit defined the fixture at the suite's top level
beside its fused-row testset, 2,000 lines AFTER the testset that first uses it, and the
suite runs top to bottom; every stage-runner run, the unit's and the integrator's, had
supplied the fixture through a preamble, and a cut block includes no top-level line outside
its testset, so only the suite's own order could show the gap. Fix (integrator commit
1128406, test-only): the two lines move to before the refusal testset, with the reason in a
comment; a scan of the merged suite for other top-level names used before their definition
found none (the other sixteen hits are docstring mentions and references inside function
bodies). The gate's own order is this fix's verification.

**The third two-arm gate (1128406, tag `b3a3`, 2026-10-22 06:05 to 09:40) was GREEN in both
arms.** Native arm (CUDA active) 06:05 to 07:53, 1 h 48 min, exit 0: 402 testsets, every one
green, Broken 2 (the expected markers in "Misalignment maps"), no skip, no signal, no core;
the CUDA-arm testset 205 of 205 with all 18 scripts exit 0 (685.0 s of wall for the scripts,
four at a time, their own times summing to 2332.0 s); the MPI seam 1712 of 1712 at 1, 2 and 4
ranks (916.9 s); the examples 21 of 21 (988.8 s); the once-per-execute! walks pin green
(block (e) of its testset, 109 of 109). AVX2 arm (`OPENBLAS_CORETYPE=Haswell`,
`julia -C haswell`, CUDA active) 07:53 to 09:40, 1 h 47 min, exit 0: 402 testsets green, the
same two Broken, the CUDA-arm testset 205 of 205 (683.5 s), no skip, no signal, no core. The
per-testset time column summed to 6345 s and 6303 s with the NFS client quiet again (batch 2's
record, section 4, has the saturated figures). The F-244 segfault did not occur in any of the
six arms run on this batch's trees. Logs:
`result/gates/turnmod/full_gate_{native,avx2}_pty_b3a{1,2,3}.log` (git-ignored scratch; the
numbers are here).

This record and the ledger changes of section 5 are a markdown-only commit on top of the
gated tree; the fast lane on the final tree is their gate: GREEN (`result/gates/turnmod/fast_lane_wt_b3a3_final.log`, 2026-10-22 09:41:47 to
10:29:41, exit 0, 386 testset summaries, 17 `LANE SKIP` lines, no unindexed
document), run
on this commit's tree before this sentence was filled in.

## 5 Ledger

Eight rows retired to `todo_ledger_archive.md` ("Rows retired by the
comprehensive-audit fix batch 3, closed 2026-10-22") with their closing measurements: the
strong-strong solver stack, the task walkers and the output tail, the observers, the
weak-strong option values, the floor plan, the beam and its statistics, the knobs, the
analysis driver. The element-kinds row (unit H) and the rounding-class row (unit J) stay
open, each with a note naming this batch and what it waits on. The pointer row carries what the batch left for the owner: unit J's two
design questions (section 1) and the items the units priced rather than fixed (E's
spectral mesh copies, async switch, hand-encoded deposit ids and the overflowing `:extrema`
extent; I's `gaussian_slicing_convergence.jl` re-run and the slicing note's `:chromatic`
column; G's `_moment_denominator` pair defined and read nowhere; M's ForwardDiff twin gate
in `src/Octopus.jl`; K's inert `name` override on an element placement and the knob-valued
`ref_tilt`'s eager conversion). Eight lessons in `experiences.md` (section 6). This
record is indexed in `docs/README.md`.

Amendments to frozen design notes, recorded here rather than edited into their bodies
(the records are frozen: add, never rewrite):

- `docs/design/twiss_dispersion_analysis.md` (unit N): the closed-orbit receipt is
  `(closed_orbit, closed_orbit_atol, effective_atol, residual, action)`, not
  `(mode, atol, residual)`; the agglomeration merges the largest chord first and breaks a
  capped-chord tie by the smaller gap, then loop order; `map_uncertainty` and the
  finite-difference provenance uncertainty fold into `rho_M0` multiplied by the scaling's
  gain `max_ij C_ii / C_jj`, the arms reported in `diagnostics.resolution`; the synchrotron
  tune domain is (0, 2pi) except pi; `diagnostics.routes` lists executed routes only, with
  `Determined` residuals and conditions; `AnalysisDiagnostics` gains `closed_orbit`.
- `docs/design/turn_modulation_record.md` and `docs/design/run_artifact.md` (unit G): the
  slot entry and the slot attributes carry `sigma` and `octaves`; `/bpm/<name>` carries the
  device model's attributes; the path registry warns for a writer still open, not for a
  finished writer's path continued.

Addenda to the earlier batch records, recorded by this batch's commit as those records
promised (batch 1's record, status line; batch 2's record, status line): batch 1 was pushed
as b9c1253 on 2026-10-20 (CI run 466 green); batch 2 was pushed as da40d39 on 2026-10-21
(CI run 467 green). Batch 3's own push and CI run are recorded by the next push's
addendum (batch 3b, unit H), as the status line above says.

## 6 Lessons recorded

- A convention is one function: where a quantity has two spellings or two code paths (a
  luminosity scale, a slicing-method alias list, a deposit-method pair, a hook-kind table,
  a namespace prefix), the fix is one table or one predicate that every consumer reads, and
  a tripwire that derives the consumers from it (units E, F, M and the integrator's first
  change).
- A dropped or refused run leaves no receipt claiming it ran: the output receipt is recorded
  after the LAST refusal that can stop the run, beside the per-run receipts, for both task
  kinds (units F and E).
- A check's precondition is part of the check: a memo keyed without the run epoch, a verdict
  taken by one owner of a pair, a positivity test with `> 0` admitting a rounding residue --
  each passed its own test and failed the case it existed for; the regression test states
  the precondition (one-turn runs, both directions, the rounding floor) and the fix keys on
  it (units E, I).
- Declared uncertainty lives in the caller's coordinates: an error bound passed into a
  scaled computation is multiplied by the scaling's gain before it is compared with
  anything in scaled coordinates, and the gain is reported (unit N).
- Nothing is read for its side effects alone: a Bool where a number is expected, a Dict key
  nobody reads, a longitudinal component the kick ignores, a differentiation variable that
  is not a knob -- each is refused by name at construction, not accepted and ignored
  (units I, L, M, N, H).
- A performance fix is proven bitwise before it is timed: the fused moment row and the
  host-side beam draw were pinned equal to the folds they replaced on committed fixtures
  first, and their timings are ratios against same-process baselines under the measured
  load (units G and L).
- Never edit a running shell script: bash reads it incrementally by byte offset and resumes
  mid-line in the edited file after a long child exits; the verdict lines of three runs
  survived, their exit codes did not (the integrator).
- A cost pin is a neighbour of every path it measures: the first gate failure in two
  batches came from a testset no unit listed, the once-per-execute! allocation pins; a
  change to a per-execute! walk re-runs the pins that cover the walk (the grep for the
  walk's name in `test/` finds them) before the gate does (the integrator, after unit G).

## 7 Not verified

Collected from the units (their sections 7) and the integrator: the MPI launcher testset
for every unit that touched a divided path (E's epoch bump, live count, node tally and
joint verdict; G's fused row at more than one rank; M's clocked collectives beyond the
two-rank hand probe; L's multi-process beam) -- the gate's seam testset runs them at 1, 2
and 4 ranks; the `-C haswell` arm beyond what the AVX2 gate arm itself measures; the
production sizes of the validation scripts (the CUDA arm runs the reduced sizes); the
Float32 one-rounding move of E's F-22 and I's Float32 kernels, which have no measurable
class yet (unit J); I's `gaussian_slicing_convergence.jl` and the slicing note's recorded
tables (a follow-up candidate, not a claim); G's timings, which carry the day's load; the
items the units priced rather than fixed (the pointer row names them); the element-kinds row (unit H, deferred to the next gated push) and
unit J's row, which this batch did not open.

## Addendum 2026-10-22 (batch 3b: unit H lands; batch 3's push and CI)

Batch 3 was pushed as ad36c83 on 2026-10-22; CI run 468 completed green.

Unit H (element kinds: silent reads and conventions; F-92, F-93 to F-99, F-160, F-161, F-163 to F-167; F-162 is unit J's) landed after the batch's push: its agent ended three times in transient API timeouts with nothing on disk, a fresh agent with a focused brief ended twice more and then delivered `fix3-element-kinds` at c7f5757, twelve commits each red-then-green on its own tree (section 2, H, above records the deferral). What landed: twelve commits (`fix3-element-kinds`, tip c7f5757) on every finding of the row but F-162 (unit J's): raw specs read their declared defaults through the schema (`_declared_param`; F-93), the untyped chromaticity kick promotes over the Float64 floor (F-94), one canonical-dispersion note on all 16 zeta/eta parameters and every coupling mode declared (F-97, F-99; F-98 found closed by batch 2 and pinned), the thin kinds refuse a key their shared runtime reads but they do not declare (F-92), the inert radiation element warns and the unkeyed excitation draw is refused (F-95, F-96), `Linear6DSpec` refuses the matrix beside the optics form with the partner defaults stated in the schema (F-165), the curved solenoid's gauge function and its derivative are one pair (map residual 1.9e-18 to 9.0e-49 in BigFloat; F-166), an unphysical particle dies as NaN instead of aborting the run and a curved drift refuses a quarter turn per step (F-163, F-167), the bend's design excess is cancellation-free at b0 = 2h (757 to 2136 ulp down to 2 to 43; F-161), `bend_fringe` is PTC's BEND_FRINGE declared per kind with the pole-face geometry following its parameters (F-160), the theory note's SAD cubic carries 1/(1+delta) (F-164); eleven testsets red on da40d39 and green on the integrated tree (`H_red.log`, `H_green.log`); `validate_element_metadata()`, the element-parameter effectiveness, PTC-consistency and symplecticity contracts passed; `validation/tracking_backend_consistency.jl` at N = 2000 with the GPU: 34 instances within class; the snapshot unchanged.

Verification of the landing: eleven new testsets red on da40d39 (`H_red.log`) and green on 12cd2d0 with eleven neighbours, the cross-backend class testset and the element-parameter effectiveness contract among them (`H_green.log`, 22 green); the pre-gate on 12cd2d0 clean (sweeps, both validators, the snapshot identical, the removed symbols absent). The gate took three attempts, each red for something the targeted runs could not see. Gate b3b1 (12cd2d0) was red in both arms at batch 2's validator testset: its ratchet `default_pairs >= 607` read 599 once unit H's `_declared_param` made five constructors read their defaults from the schema instead of restating them (fewer pairs to compare, the same coverage), and its lying-drift injection `h = 6` was refused at compile by H's quarter-turn rule before it could lie -- two test-only re-pins (dd76ad6: the ratchet at 599 with H's reason, the injection at `h = 1`). Gate b3b2 (dd76ad6) was red in both arms at "Aperture losses are identical on CPU and CUDA": one ulp between the CPU and CUDA x of 52 of 478 recorded losses after a straight drift at L = 0.5. The bisect lands on H's 092263b (`sqrt` -> `_ps_or_dead`), yet the radicand `(1 + pz)^2 - px^2 - py^2` is unchanged in the source: the device, which contracted none of its products in the one-drift kernel before the guard (0 of 20000 particles parted from the host), fuses `(1 + pz)^2` into the first subtraction once the guard changed the kernel around it (1165 of 20000), a standalone kernel of the plain shape fuses it on either tree, and the guard's own shape (a branch, or `ifelse` inside the `sqrt`) makes no difference -- the drift's bitwise agreement at a power-of-two L, which its class text explained by the exact scaling alone and the aperture-identity test rests on, had a second, unmeasured accident under it. The integrator's fix 6f309bd spells the radicand `_ps_radicand(px, py, pz) = fma(1 + pz, 1 + pz, -_pt2_fused(px, py))` on IEEE floats (the plain form on every other number type), the rule `_pt2_fused` in the same file already followed: measured in the real kernels, CPU and CUDA bitwise in x, y, z at L = 0.5 (and, with the class survey's 1e5-particle beam, at L = 0.35 and 100 m), the host's x and y moving by one ulp on 1608 of 20000 particles and z on 20, within the kind's class; device `mul.rn` products would have restored identity without moving the host but need a device override, a mechanism the code base does not have. The straight drift's class text, the class testset's comment and `docs/current_runtime.md` state the rule; the curved drift keeps the plain radicand, its class bounded by the device's fused rotation products and the two libms anyway. New testset "The straight drift's radicand is the source's fusion on both backends (fix batch 3b)", red on dd76ad6 (`Hb_red.log`: the hand formula in x and y and the six-coordinate device identity failed, the helper absent) and green with five neighbours (`Hb_green.log`, 334 passes: the aperture identity 6, the F-163/F-167 testset 26, "Lattice magnets" 83, the class testset 199, the surveyed cavity 13); `validation/tracking_backend_consistency.jl` at N = 2000 with the GPU (34 instances within class) and `validation/symplecticity_validation.jl` (28 cases) pass on 6f309bd; the pre-gate on 6f309bd clean. The two-arm full gate b3b3 on 6f309bd: native arm (CUDA active) `full_gate_native_pty_b3b3.log` 16:47:55 to 18:34:15 (1 h 46 min under a machine load of 33 from other users' jobs), exit 0, 414 summaries, 0 Test Failed, 0 Error During Test, Broken 2 ("Misalignment maps", expected), no skip, no signal; CUDA-arm testset 205/205, 18 scripts exit 0, CUDA arm wall 590 s; AVX2 arm (`julia -C haswell`, OPENBLAS_CORETYPE=Haswell) `full_gate_avx2_pty_b3b3.log` 18:34:15 to 20:23:38 (1 h 49 min), exit 0, 414 summaries, 0 Test Failed, 0 Error During Test, Broken 2, CUDA-arm testset 205/205, CUDA arm wall 580 s. This addendum and its ledger changes are a markdown-only commit on top of the gated tree; the fast lane on the final tree is their gate: exit 0, 398 summaries, 0 Test Failed, 0 Error During Test, 17 LANE SKIP lines, no unindexed document (`fast_lane_wt_b3b3_final.log`, 20:25:35 to 21:14:46, 49 min under a load of 34), run on this commit's tree before this sentence was filled in.
