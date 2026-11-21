# Targeted neighbour audit of the LinearOptics batch (2026-11-21)

Status: the post-campaign neighbour audit the owner's standing direction
requires (`AGENTS.md`, "A fix's neighbours are where the next defect is";
protocol `../comprehensive_audit.md`), scoped to the batch recorded in
[`linear_optics_2026_11_21.md`](linear_optics_2026_11_21.md). Conducted
2026-11-21 by the auditor alone (one reading unit, two confirmed findings,
both fixed in the batch), reproductions re-run before recording. Gate
numbers: the campaign record's section 5. Bracketed `[...: pending]` markers
are filled by the record commit after the gate.

## 1 Executive summary and repository

Octopus at the LinearOptics working tree (on 9c48589; the batch adds a value
object consumed by five constructors and an analysis accessor, no kernel
changes). The audit re-walked every reader of the parameters the batch
touched and the sibling surfaces of every consumer. Two findings, both in the
batch's own blast radius: the second runtime variant of the linear map
(`ParticleLinear6D`) did not read the new `form1`/`form2` (U1-1, Moderate),
and the `Beam` flattening could not see an explicit default-valued flat
keyword beside `optics` (U1-2, Minor). Both fixed with regression tests that
fail on the unfixed tree for the defect's reason. Nothing else moved: the 14
flat-path fingerprints are identical before and after the batch.

## 2 Declared scope and coverage ledger

| Unit | Responsibility | Inspected by | Evidence |
|---|---|---|---|
| U1 | the consumers of the optics parameters and the runtime variants of `linear6d`; `Beam`; the elementary maps; `XY_UNDEF` | auditor, line by line | [`audit_linear_optics_2026_11_21_unit_reports/U1.md`](audit_linear_optics_2026_11_21_unit_reports/U1.md); repro [`audit_linear_optics_2026_11_21_U1_1_repro.jl`](audit_linear_optics_2026_11_21_U1_1_repro.jl) |
| U2 | the metadata and effectiveness seam (ParamMeta without literal defaults, `element_help`, snapshot, the `linear6d` probe, the ratchet) | auditor, by running the validators and the contract | the record's section 4; `validate_element_metadata()` 612 pairs; contract 553 checked |
| U3 | the analysis accessor `linear_optics` (unscaling planes, the form presented, the longitudinal block, `Determined` paths) | auditor, by round trips | the record's section 4 (1e-8 fields, 1e-13 maps, forced form 2, refusals) |
| U4 | documents: public API page, design note, docstrings, snapshot, index | auditor | Architecture integrity 49 of 49; the suite's docstring sweeps |

Not covered: the CUDA kernels (unchanged by the batch; the CUDA beam
fingerprint identical), the strong-strong task (no optics keyword), the MPI
path of `Beam` (the flattening happens before the shard, on every rank alike,
not exercised here), the `GaussianStrongBeamSpec` (takes `thin`, unchanged).

## 3 Traceability and reviewed decisions

D1-D10 of `../design/linear_optics.md` against the tree: D1 `src/knowledge/LinearOptics.jl`;
D2 the type docstrings and the `R1`/`R2`/`R`/`r1..r4`/`mode` meanings; D3 the
`params` equality assertions per consumer and the fingerprints; D4 the
refusal assertions (one per consumer) and U1-2's fix; D5 `_phase_advance` and
its five refusals; D6 `linear_optics` and the round trips; D7 `form1`/`form2`,
`_mR66(C, form)`, `_check_linear6d_block`, and U1-1's fix for the second
variant; D8 `_check_undef_coefficients` at three sites and the retargeted F-97
pin; D9 the three parts-to-spec constructors; D10 the `Beam` docstring.

## 4 Findings

**U1-1 [Moderate] `ParticleLinear6D` ignored `form1`/`form2`.** The particle-tune
variant built its normalizer with the form-1 block for any form and reached a
bare `sqrt` DomainError for `det C >= 1` (repro: `|A - form1| = 0`,
`|A - form2| = 5.83` for a form-2 spec). Fix: `_particle_tune_normalizer`
takes the form and checks the block; `ParticleLinear6D(spec, method)` reads
`form1`/`form2` with the plain map's partner defaults
(`src/elements/particle_tunes.jl`). After: the normalizer equals
`_mR66(C, form) N` for both forms (suite, atol 1e-14) and the inadmissible
block is refused by name through `compile_runtime`. Pin: the "audit U1-1"
block of the LinearOptics testset. Lesson class: a parameter added to a spec
kind has as many consumers as the kind has runtime variants
(`runtime_variants` of the `@element_spec`), not one.

**U1-2 [Minor] `Beam` could not see an explicit default beside `optics`.** Value
defaults made `beta = (1.0, 1.0, 1.0)` beside `optics` indistinguishable from
an absent keyword, so the point's values won silently. Fix: `nothing`
sentinels on `beta`, `alpha`, `zeta`, `eta`, `coupling`, `mode` in
`_initialize_beam`, clash by presence, defaults applied after the check and
before the bounded forward (`src/beam/Beam.jl`). After: three explicit
default-valued keywords beside `optics` refused (suite); the flat beam and the
object beam remain bit-identical; the bounded path's checks unchanged.

**Closed without change.** (a) `form1`/`form2` carry no literal `ParamMeta`
default: the validator passes `params(example)` (the matrix form) through the
constructor and the both-forms rule refuses a form beside a matrix, exactly as
for `alpha1`; the meanings state the optics-form default. (b) A form-2 point
whose first mode is y-dominant returns from the analysis as the relabelled
form-1 point: the analysis's canonical labelling (mode 1 x-dominant), the
(T4) identity; recorded in the design note and `docs/experiences.md`, tested
by map equality. (c) `_inverse(::XYCoupling)` keeps its `XY_UNDEF` identity
branch: reachable only with zero coefficients now, consistent. (d) The
`Edwards-Teng: the coupled construction` neighbour testset errors when run
extracted (file-level helpers `_pb_frame`, `_pb_blockdiag` undefined outside
the suite), not a defect; it runs in the lanes.

## 5 Verification of the fixes

Both fixes were applied after the fast lane of the pre-fix tree (green, the
campaign record's section 5) and before the full gate. Shown failing unfixed
on that tree (2026-11-21, 13:20 EST): U1-1 by the repro script beside this
report (`|A - form-1 normalizer| = 0`, `|A - form-2 normalizer| = 5.83` for a
form-2 spec); U1-2 by construction, `Beam(10, CPUThreadsBackend; optics=o,
sigma=(1e-4, 1e-5, 0.01), beta=(1.0, 1.0, 1.0))`, the same with
`mode=XY_MODEA` and with `coupling=(0.0, 0.0, 0.0, 0.0)`, each constructed
silently where the fixed tree refuses it by name (the three assertions added
to the LinearOptics testset). The targeted testsets re-run extracted after
the fixes (2026-11-21, 13:17 to 13:23 EST, the suite's blocks cut out by
title and evaluated after `using Octopus`, every block green, none failed):
"LinearOptics: the shared optics object feeds every consumer by one
flattening rule" (115, the ten audit assertions included); the F-97 metadata
testset "Dispersion parameters state the canonical convention, the coupling
mode declares every value the runtime accepts, ..." (48); "Thin elements,
markers and RBEND" (114, the effectiveness ratchet); the four Beam refusal
testsets ("A refused Beam has drawn nothing" 36, "Beam refuses sigma with
emit and a second spelling of the coupling coefficients" 16, "random Beam
refuses non-AbstractFloat on BOTH entry points" 6, "Bounded Beam refuses
invalid or inactive requests before policy and RNG effects" 273); the strong
beam's F-124/F-125 refusals (19); the nine "Particle tunes:" testsets (113,
173, 51, 167, 143, 5, 5, 11, 16); and the five sweeps (Core.Box 5, every
export documented 1, detached docstrings 11, every export in the snapshot
17, Architecture integrity 49). `validate_element_metadata()` and
`validate_configuration_metadata()` pass after the fixes, and the registry
snapshot regenerated after them is byte-identical to the batch's. Baseline fingerprints re-run after
the fixes (`linear_optics_2026_11_21_baseline.jl cuda`, 2026-11-21 13:30 EST): all 14
identical to the recorded tables, the particle-tune and Beam paths the fixes
touched included. The full gate on the final tree: the campaign record's
section 5.

## 6 Remaining risks and owner items

The owner items of the design note's section 4 stand (form 2 on the
chromaticity kick and the radiation element; retiring `XY_UNDEF`; dispersion
in the thin strong beam; `LumpedRadSpec`'s fixed Float64). Added by this
audit: the `runtime_variants` lesson above suggests a tripwire that every
reader of a kind's declared parameters is enumerated (today found by grep);
not built here, priced as a half-day.
