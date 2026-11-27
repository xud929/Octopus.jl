# The suite's remaining testsets by area: the count behind the peels (2026-11-27)

The exact assignment of every testset still in `test/suite/legacy.jl` after the
split's first peel ([`suite_split_2026_11_27.md`](suite_split_2026_11_27.md)):
468 titles (451 `@testset` blocks and 17 lane-gated blocks), each read and
placed, none left over. Times are the testset's own wall time in the full
gate of `883a831` (CUDA active, four threads, `result/gates/split/full_gate_native.log`),
summed per area. Membership is a reading, not a derivation: a title names
its subject, and where two areas could claim one the subject the test
exercises decided (a CUDA parity test of a solver stays with the solver;
a cross-cutting parity test goes to `cuda`). Each peel revisits its list.

| Area (the file to peel) | Testsets | Summed time |
|---|---|---|
| `analysis_twiss` | 113 | 4.1 min |
| `lattice_machine` | 69 | 6.7 min |
| `elements_tracking` | 89 | 9.1 min |
| `beam_core` | 39 | 3.8 min |
| `strong_strong` | 92 | 5.2 min |
| `cuda` | 13 | 1.4 min |
| `turn_modulation` | 15 | 5.5 min |
| `contracts_metadata` | 14 | 7.1 min |
| `mpi` | 16 | 26.2 min |
| `examples_validation` | 5 | 21.6 min |
| `artifact_observers (owed)` | 3 | 0.2 min |
| total | 468 | 90.8 min |

Recommended order: `analysis_twiss` (largest, contiguous at the top of the
file, its helper families used by nothing else), then `lattice_machine` and
`elements_tracking`, then `strong_strong` and `cuda` (they share fixtures;
expect helpers to move into `common.jl`), then the small ones; `mpi` and
`examples_validation` are already lane-gated and gain only an explicit
`only=` exclusion from a file of their own; the three owed artifact testsets
ride with whichever peel comes first.

To peel an area, cut its section below into the mover's title file and run
the mover (dry run first, then with the helpers its report names):

```sh
sed -n '/^## analysis_twiss$/,/^## /p' docs/history/suite_split_2026_11_27_peels.md | grep '^- ' | sed 's/^- //' > /tmp/titles.txt
julia --startup-file=no test/move_testsets.jl --from test/suite/legacy.jl --to test/suite/analysis_twiss.jl --titles /tmp/titles.txt --dry-run
```

A title the mover cannot find exactly once (renamed, moved, deleted since
this reading) fails the run by name; fix the list, never the suite, to
match.

## analysis_twiss

the Twiss and dispersion analysis: the symplectic kernels, 4D eigenmodes, Mais-Ripken, Edwards-Teng, `LinearOptics`, mode clusters, ambiguity sets, the dispersion routes, canonical separation, `one_turn_matrix`, the analysis object, its receipts and its contracts' plumbing (113 testsets, 4.1 min).

- Symplectic kernel: form, inverse, adjugate, rotation block
- Symplectic defect is at roundoff on 200 manufactured maps and catches a perturbation
- Reciprocal canonical scaling: modes, wrong length, C'SC = S
- Back-transformation rows are scaling-invariant on manufactured 6D maps
- Invariance residual (I1): eigenmode and graph forms, normalized and raw
- First perturbation scale rho_M0 takes the largest arm
- Manufactured symplectic maps: seed, symmetry, stability
- Availability vocabularies are pinned against the source
- Determined accessors throw with the reason
- AmbiguitySet refuses multiplicity one and a bad kind; the interval reads a'center +- sqrt(a'shape a)
- Stage 5 declares the analysis: the placeholder and TwissDispersionAnalysis are the analyses, analyze exists, and the declared kind set is the derived set plus :line
- Stage 5: every kind that declares the analysis analyzes its own example, or refuses it for the documented reason
- Stage 6 registers TwissDispersionIdentityContract: description, supertype, export, docstring, registry, snapshot, kwarg rejection
- Stage 6: _identity_contract_record! fails a row by name when its kappa is not finite (F-141)
- Stage 8 registers TwissExternalReferenceContract: description, supertype, export, docstring, registry, snapshot, kwarg rejection, skipped path
- Stage 8: the MAD-X dispersion rows assert their coasting precondition (F-143)
- Stage 8: the external-reference tables' versions are read from their headers, and the fixture lists are tripwired against the scripts and the tables (F-144)
- Stage 6: the identity contract passes on the tree with pinned metrics, and every negative is red
- Stage 6: the Layer 3 rows judge the physical tunes, Twiss functions and the covariance accessor against independent references, and the V1 re-derivation sees a doctored verdict (F-142)
- 4D eigenmodes: R(2pi 0.7) (+) R(2pi 0.31) gives tunes 0.7 and 0.31 with the orientation Im(v'Sv) < 0
- 4D eigenmodes: (E7), (E8), projectors, signed areas and (M5) on 200 manufactured maps
- 4D eigenmodes: closed-form (E10)-(E14) agrees with the eigenvector route and its guards fire
- 4D eigenmodes: normal coordinates and actions (E9) agree and are invariant under the map
- 4D eigenmodes: the FODO cell of validation/lattice_cells.jl against its Courant-Snyder rule (benchmark 12.2-1)
- 4D eigenmodes: clusters land diag(2, 1/2, R(1.2)) in :unstable_spectrum, equal pairs in :cluster_unresolved, R(a) (+) R(-a) in :indefinite_cluster
- 4D eigenmodes: scaling invariance through _reciprocal_scaling and _unscale_twiss on three scalings
- Mais-Ripken: (M1)-(M8) on 200 manufactured normalizers, zero projections, loud input
- Mais-Ripken: the (M7) rephasing is the frame's one phase convention, floor included (F-193)
- Mais-Ripken covariance: (M9)-(M16) agree, close under the map, and refuse a zero projection
- Edwards-Teng: normalizer (B10), map (T9) and direct (B11) routes agree on 200 maps; every reconstruction returns M; the 7.5 round trips
- LinearOptics: the shared optics object feeds every consumer by one flattening rule
- Owner items 1, 4, 5 (2026-11-21, design D11-D13): form 2 through the point, the untyped LumpedRadSpec promotes, :auto is form 1
- Edwards-Teng: the coupled construction of benchmark 12.2-2 (Linear6DSpec optics form conjugated by XYCouplingSpec)
- Edwards-Teng: the uncoupled FODO has R = 0 and lambda = 1, zero projections and inadmissible forms carry their reasons, the map-route guards fire
- Edwards-Teng: the Sagan-Rubin identities (T12) on the (T9) branch, and scaling invariance of R, lambda, det R, u, beta/alpha/gamma
- Mode clusters: pinned vocabulary and documented structs
- Mode clusters: rolled equal-tune FODO (13.10) and its detuned controls
- Mode clusters: resolution_chord = Inf forces the exact FODO, explicit partition
- Mode clusters: 200 + 200 manufactured stable maps are resolved singletons
- Mode clusters: definite m = 2 and m = 3 6D fixtures (N4, N5, N6/N7, N21, N19)
- Mode clusters: indefinite fixture, near collision, R(a) (+) R(-a)
- Mode clusters: defective spectator is unresolved with the minimal-polynomial sub-reason
- Mode clusters: unstable and unit-eigenvalue fixtures (D4, D5)
- Mode clusters: the chord and rho_M0 are READ (D11) on R(0.9) (+) R(0.9 + 1e-7)
- Mode clusters: the crab ladder k = k_c (1 - eps) is stable for eps > 0 (D5 with kappa_c)
- Mode clusters: scaling invariance of classification, tunes, P_c, G_c; q reported per scaling
- Mode clusters: argument errors and the receipt lists every candidate
- Mode clusters: the real-class floor's window is measured from the tree: rotated Jordan pairs stay real-class, the smallest complex pair stays complex (F-193)
- Mode clusters: a capped-chord tie merges the smallest gap first, so an isolated pair is not absorbed by a repeated one (fix batch 3 N, F-195)
- Ambiguity set: pins on diag(R(0.73), R(1.41), R(0.73))
- Ambiguity set: 30 conjugated copies (N12 surface, N14 endpoints, affine readout)
- Ambiguity set: three coincident modes (N13) and the (D12) convention on resolved maps
- Ambiguity set: refusals name their reason before any set is built
- Ambiguity set: exact-set versus envelope kind on the FODO gaps
- Ambiguity set: the trial-015 isospectral family
- Ambiguity set: N15 indefinite family and the N16/N17 negative controls of 13.7
- Dispersion routes: vocabulary pin and the dense elliptic maps (all five routes, agreement, cubic roots, labels)
- Dispersion routes: the prescribed-h maps (every direct route returns the triple; h negative included)
- Dispersion routes: repeated betatron and the defective spectator (design row 3: the dispersion is unique)
- Dispersion routes: a Krein quartet contributes no trace, the projector route is blocked with the cluster's reason (stage 9, U5-2-3)
- Stage 9 audit: conditions beyond Float64, non-finite graphs and scaling quotients
- Stage 9 audit U4a-2-2: the indefinite cluster's signed basis pairs each column with its own eigenvalue
- Stage 9 audit: the constructor rejects Bool stand-ins and repeated cluster indices with ArgumentErrors
- Stage 9 audit: a non-finite external-reference difference is an infinite worst ratio, not a NaN one
- Dispersion routes: coasting maps, the weak cavity, and the DBA cell at delta = +-1e-4
- Dispersion routes: singular projection, isotropic graph, degeneracy rejection (theory 13.7, E9)
- Dispersion routes: non-definite longitudinal clusters (E9): indefinite, unit-eigenvalue, hyperbolic
- Dispersion routes: the trial-011 crab map against its analytic eta_+
- Dispersion routes: linear-map line versus matrix, and the DBA cell with RF and a thin crab cavity
- Dispersion routes: route selection, newton_max_iterations READ, rho_M1 READ, scaling (E13)
- Dispersion routes: an unconverged iterate is :not_invariant whatever the (I1) floor says (M1, 2026-09-13)
- Dispersion routes: argument errors, label ties, and the kernels' loud inputs
- Dispersion routes: a coasting map refuses a bad longitudinal index before its early return (F-178)
- Canonical separation: (D3) block form, (K2) inverse and (K1) for every h
- Canonical separation: dense maps (K4), (K5), (K7), (K8), raw defect
- Canonical separation: prescribed-h maps, (K8) on every symplectic map, h = 0
- Canonical separation: 4D pipeline on Mbar_beta and the longitudinal normalizer
- Canonical separation: (K9) U_6 symplectic, reconstructs the rotations, equals W up to phase
- Canonical separation: the (K12) 3x3 array, (M5) and (K13)
- Canonical separation: matched covariance (K10), (K12), (K14), bunch length
- Canonical separation: Ohmi factorization (O2)-(O5), h < 0 and h = 0
- Canonical separation: scaling back-transformation (E13) for U_6, Sigma, P_j, G_j
- Canonical separation: a perturbed triple is :not_invariant, an inconsistent triple throws
- Stage 4a chain: _canonical_separation(M, routes) and _transverse_optics_6d on dense, repeated-betatron and coasting maps (E1, E12a)
- Dispersion routes and canonical separation: pinned vocabulary, documented structs, functions and consts, PROVISIONAL constants
- Analysis object: constructor rules, option schema, exports, the status vocabulary (F1, F2)
- TwissDispersionAnalysis: _with_longitudinal_mode carries every other option
- validation/twiss_dispersion_identities.jl: the reporting code on a fake result (dry run)
- Dense 6D map: the default path is :degraded by the uncertified heuristic, certified it :passed (F3, F4, dossier row 1)
- Dense 4x4 map: no longitudinal notions, two normal modes, the 4D matched covariance, the presented form (F3 step 8, F7)
- Scaling: :none, :auto and an explicit tuple give the same physical quantities row by row (F3 step 11, F13)
- Linearized inputs: the :linearized form, the closed-orbit options, the finite-difference rule, the tuple form (F2, F3 steps 3 and 5)
- Coasting maps: the stage 4a fixture and the DBA cell run the same separation path, not degraded, route options inactive (F3, F4, F6)
- Prescribed h = 0.05: the heuristic is uncertified and degraded, the tune certifies and recovers the analytic triple (F4 amendment, row 7)
- Stage 9 follow-up (the DBA-ring example check): the heuristic's degradation message is unconditional and names the index semantics
- Reason table: one fixture per reason the pipeline can emit, the set seen equals DETERMINATION_REASONS minus :none and the three kernel-level reasons (F13)
- Verdict and strictness: the near-non-symplectic map fails, strict throws the same result, :flag degrades, :error throws (F4, row 11)
- Receipts: one probe per option, the requested value under the option's own name, absent where inactive (F5)
- Configuration report: the statuses per option on the four input forms, never :inactive (F6)
- Explicit partitions promise the grouping only; a forced resolution is a degradation (F3 steps 6-8, row 14)
- Resolved multi-member clusters (fix batch 2026-10-19 W): each mode names its own eigenvalue, longitudinal_mode = k selects it, the projector route keeps per-mode traces, the selection text quotes the selected mode (F-192, F-176, F-177)
- Analysis driver (fix batch 3 N): map_uncertainty folds through the scaling gain, the diagnostics list executed routes with Determined residuals, the coasting canonical area, Newton's cap inactive when blocked, the closed-orbit tolerance recorded, the tune domain mod 2pi, the 4x4 LinearizedMap refused (F-194, F-196 to F-199)
- 4b-B validator block and AbstractAnalysis tree guard
- 4b-B probe tables: valid non-default alternatives, F6 inactive pairs, F8 tripwire
- 4b-B probe fixtures: forms, determinism, coasting structure, exact provenance
- 4b-B receipt matcher and probe helpers
- 4b-B contract plumbing through an injected run: metrics count, every negative is red
- 4b-B registry, description, snapshot lines, the real validate
- A ForwardDiff dual passes through gaussian_strong_beam_covariance and the dispersion graph (F-121)
- one_turn_matrix reproduces the inline complex step bit for bit
- one_turn_matrix: finite difference is order step^2 and declares it
- one_turn_matrix: the ForwardDiff route and the core fallback
- one_turn_matrix: the relabelling guard, the argument errors, the fixed point

## lattice_machine

the line layer and the machine description: `BeamLine`, `Lattice`, `Machine`, the knob system and the derivative path, the TOML snapshot, `@elements`, `with_overrides`, the floor plan, patches and surveys, the reference ramp (69 testsets, 6.7 min).

- MAD-X survey consistency
- knob_report over a container reports the wiring
- script mode picks up the ForwardDiff rules
- ForwardDiff differentiates the lattice
- BeamLine composes, addresses and tracks
- Machine description: ReferenceParticle builds from E0 or p0c and refuses by name
- Machine description: the reference particle derives its quantities once, takes presets and four energy spellings, and refuses by name
- Machine description: the beam derives its classical radius and carries its reference; the strong-strong preflight refuses a zero or defaulted kick factor by name
- Machine description: a typed element refuses a value wider than Float64 by name and keeps narrowing Float64 to Float32
- Machine description: a collision marker in a single-beam line is inert, counted, never an error
- Machine description: the accelerating-cavity flag is fixed at construction, EveryNSteps prints stop only when given, and a bad moment name is refused by name
- Machine description: an explicit stream id reaches the registry on every route into the flexible form, and the kind's own id passes silently
- Machine description: read_lattice reads a one-lattice snapshot and read_machine assembles a machine from several files
- Machine description: the class form derives a spec from a template of its kind on every friendly constructor, and the flexible form folds a named strength
- Machine description: every element parameter declares its value class, the validator holds the declaration, and element_help prints it
- Machine description: the snapshot coerces by the declared type, keeps the marker forms for untyped keys and old files, and refuses a value outside the class by name
- Machine description: a Lattice wraps a line and is accepted where the line is
- Machine description: the knob-root tripwire refuses a dependency outside the declared roots
- Machine description: the numeric-type tripwire follows the compile rule
- Machine description: lattice equality is structural and the record prints
- Machine description: the wiring walker sees the knobs the compile resolves inside a nested spec or a NamedTuple
- Machine description: the shipped DBA lattice module builds an equal lattice when included twice
- Machine description: a Machine holds lattices by name and the implicit one-lattice machine equals the explicit one
- Machine description: the machine-level knob-root tripwire refuses an undeclared shared root and overlapping roots
- Machine description: a one-lattice machine is accepted where a line is and a machine of several is refused by name
- Machine description: StrongStrongTask takes a machine and compiles the runtime the tuple spelling compiles
- Machine description: the shipped strong-strong example declares two lattices in a machine whose placements the task holds
- Machine description: the snapshot round-trips a lattice and its knobs and the emitter is deterministic
- Machine description: every registered element kind round-trips through the snapshot or is refused by name
- Machine description: every knob operator round-trips through the snapshot
- Machine description: the snapshot reader refuses by name
- Machine description: every hook, marker, solver, schedule and rule type round-trips through the snapshot or is refused by name
- Machine description: the strong-strong example's machine round-trips and the reloaded task compiles the tuple spelling's runtime
- Machine description: the run artifact embeds the machine snapshot and reads it back
- Machine description: the task records the machine it was given, by spelling
- Machine description: with_overrides derives a lattice without touching the source
- Machine description: with_overrides refuses by name
- Machine description: the derived lattice's snapshot shows the overrides as placement data
- Machine description audit: a placement override on a hook or marker placement is refused by name on every route
- Machine description audit: StrongStrongTask refuses an unknown keyword by its own name on the line and machine forms
- Machine description audit: every tracking method and enum of the module is a registered snapshot object type
- Machine description audit: an undeclared placement override key is refused by name where the spec route refuses it and is never written
- Machine description audit: AtTurns compares by its set, so independently built solvers scheduling the same turns pair
- Machine description audit: a lattice whose observers have run is still equal to its pristine twin
- Every walker over the line agrees on what a container is
- Machine description: @elements expands kind calls onto the friendly constructors
- Machine description: the @elements block builds the hand-written lattice
- Machine description: every registered kind expands through @elements, derived from the registry
- Machine description: @elements refuses a kind without a friendly constructor by name
- Machine description: the @elements block builds tuple and vector children and names a nameless line
- Nested lines have length, reflection keeps state, folded sugar is rejected everywhere
- Floor plan: ref_tilt from the merged placement, on a patch and on the top-level line (fix batch 3, F-127, F-128, F-129, F-232)
- Floor plan: the patch convention normalises once and the arc sagitta is cancellation-free (fix batch 3, F-133, F-134)
- Line placements refuse structural overrides at assignment, and the keyword form copies its placements (fix batch 3, F-131, F-132, F-138)
- knob_report sees a line's own knob parameters and a placement's knob override (fix batch 3, F-130)
- find_entries by friendly type, the design note's mutation recipe, and the in-line hook refusal (fix batch 3, F-240)
- Patch: the exact inverse restores the transverse state, and z shifts by the two reference paths (fix batch 3, F-135)
- Floor-plan documentation and dead code (fix batch 3, F-136, F-137)
- Unknown spec keys warn, placement keys bind, set_param! bumps the epoch
- Patch: deliberate change of reference frame
- Machine description: the friendly constructors accept knob expressions (D10)
- Machine description: the effectiveness contract's expression arm
- Reference ramp: the boundary map damps the emittance exactly, a flat program is the identity, and the receipts say so (targets 1, 4)
- Reference ramp: every misplacement and mismatch is refused by name
- Reference ramp: the snapshot carries the program by digest and the metadata validator covers the actions
- Reference ramp: the synchronous particle is the fixed point of the ramped ring, and the device map is the host's bit for bit (target 3a, backends)
- Knob control
- Knob registry atomicity and round-trip totality
- Knob edges: the derivative path, the namespace views, the constant right-hand side and the receipt epoch

## elements_tracking

element kernels and specs, the weak-strong strong beam and its luminosity routes, apertures and the loss record, the precision rule and the rounding classes, the PTC references, `TrackingTask` (89 testsets, 9.1 min).

- Non-symplectic Lorentz method classification
- Linear6D rejects non-symplectic matrices
- TrackingTask smoke test
- The fused route carries luminosity through every wrapper
- luminosity_tracking selects the route and both give the same number
- A wrapped strong beam cannot silently lose its luminosity
- TrackingTask records per-turn timings on BOTH of its turn loops
- TrackingTask absolute turns survive chunked execution
- Lumped radiation method and flag semantics
- The deprecated CUDA LumpedRad route draws from the counter RNG
- Physical and unsafe weak-strong virtual drifts
- Round Gaussian near-axis stability
- Near-round Gaussian transition
- Near-round precision support and tracking consumers
- Weak-strong coupled covariance and longitudinal limits
- Virtual drifts: the named three are symplectic, the unsafe two are not
- The chromatic composite kicks at the collision point's own S and is symplectic to the dual-Jacobian floor (F-119)
- The exact drift's forward form is cancellation-free: its BigFloat reference and its round trip within the round class (F-120)
- hvoffset keys are validated by name and the Float32 Gaussian with hvoffset compiles in Float32 (F-122, F-123)
- The strong beam's inert longitudinal components and a degenerate transverse covariance are refused by name (F-124, F-125)
- Conditional 6D Gaussian strong-beam slicing
- Strong beam element stage 1 (docs/design/strong_beam_element.md S1-S6): the self-contained GaussianStrongBeamSpec
- Deprecated strong-beam spellings stay alive (docs/design/strong_beam_element.md, stage 2): ThinStrongBeamSpec, constructor hvoffset and slice_*offset, mean
- Strong beam stage-2 neighbour audit (docs/history/audit_strong_beam_element_2026_11_22.md): U1-1..U1-4, U1-7, U2-1, U3-1..U3-3
- The strong beam's momentum dispersion is canonical: the builder forms the physical slope by (D7) and agrees with the Twiss analysis
- Gaussian longitudinal slicing rules
- Lattice magnets
- Named magnet strength keywords
- PTC fringe and wedge conventions
- Misalignment maps
- Aperture ids thread through the frame wrappers and kept-whole lines
- The bend map is cancellation-free as b0 goes to zero
- Cancellation-free longitudinal updates for the curved drift, the bend and the solenoid
- Series helpers hold full precision across their crossovers
- ref_tilt rolls the design orbit
- One precision rule: every element kind declares its beam type, a mismatched beam is refused by name on both backends, and every kind has a typed form
- Cross-backend rounding classes declared per kind and checked by measurement, and the marker completes the one precision rule
- A raw spec with only its required keys compiles with the schema's declared defaults (F-93)
- The untyped ChromaticityKickSpec promotes its named parameters over the Float64 floor (F-94)
- Dispersion parameters state the canonical convention, the coupling mode declares every value the runtime accepts, the cavity's L meta names the slip's owner (F-97, F-98, F-99)
- The thin kinds refuse a key their shared runtime reads but they do not declare (F-92)
- The radiation element warns when nothing it was asked for can run, and refuses an unkeyed excitation draw (F-95, F-96)
- Linear6DSpec refuses the matrix and the optics form together, and the raw optics form reads its declared and partner defaults (F-165)
- The curved solenoid's gauge function and its derivative are one consistent pair (F-166)
- An unphysical particle dies instead of aborting the run, and a curved drift refuses a quarter turn per step (F-163, F-167)
- The bend's design excess is cancellation-free at b0 = 2h as well (F-161)
- bend_fringe is PTC's BEND_FRINGE, on by default for the bend kind and off on the straight kinds; the pole-face geometry follows its parameters (F-160)
- The conventions note's SAD cubic carries the code's 1/(1+delta) (F-164)
- Thin elements, markers and RBEND
- Lattice-magnet body schemas are complete (U9-2)
- Curved magnets against straight magnets and coordinate changes
- PTC coverage cannot narrow silently
- PTC rows cannot be lost silently: one dropped row, one malformed row (F-115)
- The luminosity tree reduction's power-of-two guard is enforced
- Element parameters carry their own number type
- RF cavity closes the longitudinal plane
- RF velocity slip closes the full slip factor (F16)
- Accelerating cavity changes the reference exactly (Scope B)
- Reference particle: the cavities take the reference in place of beta0 and gamma0
- Cavity chain composition, single-pass refusal, harmon resolution
- Longitudinal conventions convert exactly
- linear-map friendly constructors promote their element type
- Loss accounting reports itself
- Curved frame x transverse field: every routing is a gradient
- Straight solenoids differentiate, and curved=false means straight
- A dual alignment parameter on a line differentiates like the element's (fix batch 3, F-126)
- The Linear6D symplecticity validator accepts every numeric type it advertises
- The near-round Gauss-Legendre reference has not drifted from its twin
- The elliptical strong-beam kick differentiates
- Wrapped stochastic elements keep their context, shared streams warn, unbound apertures cannot corrupt
- A task re-run on the other backend reallocates its loss record
- PTC consistency
- Lattice cells track and stay symplectic
- Phase-space and element boundary validation
- The non-finite reporter does not assert what its own scan disproved
- Aperture kills what is outside and nothing else
- An aperture that kills nothing changes nothing
- Aperture loss record, counter and output
- Aperture reconciliation exposes unattributed deaths
- The straight drift's radicand is the source's fusion on both backends (fix batch 3b)
- Curvature is resolved before tracking, not inside the kernel
- Exact solenoid map
- Solenoid with superimposed multipoles
- Solenoid in a curved frame
- TrackingTask owns the loss record
- A Float32 beam with an artifact reuses its loss record across execute! calls
- Finite-difference 6D symplecticity validation
- Weak-strong luminosity is thread-count invariant
- CPU weak-strong strong-beam tracking allocation does not scale with the particle count

## beam_core

`Beam` and `BeamParams`, bounded initialization, particle tunes, phase-space reset, execution policies and workers, the counter RNG and the stream registry, live masks and masked statistics, the constants (39 testsets, 3.8 min).

- Counter RNG smoke tests
- a torn coordinate record is reported, not mis-framed
- write_beam_coordinates refuses npart beyond the count; a record past the end and mixed coordinate arrays are refused by name
- random Beam refuses non-AbstractFloat on BOTH entry points
- Beam refuses sigma with emit and a second spelling of the coupling coefficients, by name
- A refused Beam has drawn nothing: every keyword is checked before the stream is taken
- BeamParams keyword defaults are typed: any keyword may be omitted, in the typed and the untyped form
- Reference particle: Beam takes the reference in place of charge, mc2 and E0
- A CUDA beam is the CPU beam of the same seed and stream, bit for bit
- Uniform Beam samples the requested box without Gaussian normalization
- Grid Beam derives its population and ordered Cartesian product from its axes
- Bounded Beam refuses invalid or inactive requests before policy and RNG effects
- Bounded Beam preserves backend and policy semantics and the Gaussian default
- Uniform and grid beams track through a sliced weak-strong collision on CPU and CUDA
- Beam initialization metadata and effectiveness checks detect injected drift
- Uniform Beam validates its explicit RNG before activating the policy
- Particle tunes: independent dense maps, runtime variants and backend precision
- Particle tunes: all plane subsets, entrance sources and preparation errors
- Particle tunes: distributions, histogram masses and keyed preparation
- Particle tunes: persistent ownership, coordinate resets and refusal recovery
- Particle tunes: fixed-label symplecticity and analytic phase-mixing response
- Particle tunes: shared stochastic source-band warnings
- Particle tunes: clearing and disabling preserves an admitted failed run
- Particle tunes: concurrent admission is atomic and releases its guard
- Particle tunes: immutable coordinate views retain identity across GC
- Phase-space reset: independent one-turn oracle on CPU and CUDA
- Phase-space reset: lifecycle, ownership, exact restoration and refusals
- Phase-space reset: trial output, replay, recapture and failures
- Phase-space reset: refused reuse preserves active and prior trials
- One rng_id policy: zero assigns a fresh stream everywhere, ids are UInt64, the registry warns on an explicit claim of an auto-assigned id and on cross-class sharing
- A spawned worker on the driver's own thread is still refused
- Scalar diagnostics reduce the whole beam, and a lost particle still counts for nothing
- The pool-of-one inline worker path agrees with the spawning one
- A lost particle is a comparison, not a poison pill
- Philox4x32-10 matches the Random123 known-answer vectors
- allow_lost_particles is off by default and scoped
- Lost particles are excluded from every reduction
- Masked statistics are the unmasked statistics of the survivors, bit for bit, at any size and for any values
- CODATA 2022 constants

## strong_strong

the strong-strong solvers (PIC, Gaussian-PIC, spectral, soft-Gaussian), slicing, the luminosity channels and schedules, the pair schedules, the coherent-mode physics, their CPU/CUDA parity (92 testsets, 5.2 min).

- Integrated Green kernel on the axes
- A launch config a bare collide! cannot apply is not discarded silently
- CUDA and CPU PIC cache keys cannot drift apart
- Phase-space reset: refused window preserves resolved spectral noise
- Slicing degenerate conventions and the spectral charge tripwire
- CPU solver stack is thread-count invariant
- CPU strong-strong collide allocation does not scale with the pair count
- CUDA equal_area histogram matches the CPU membership rule
- Spectral solve/eval split is exact
- Strong-strong lines bind the survey, the apertures and the reference chain as a TrackingTask line does
- The strong-strong physics line and observer tuples are cached per compilation and cost nothing per execute!
- Solver equality is by configuration
- The standalone theory script's constants match the framework's
- The reduced record is read through its accessors, not slot literals (F-43)
- The hybrid's inert PIC options are one table its refusals and its report both read (F-44)
- The sliced pair's non-finite verdict is joint across its two directions
- Gaussian-PIC profile buffers fit every legal grid
- The CUDA spectral workspace gives the same mesh-width advisory as the CPU one (F-34)
- The spectral mesh width says when it makes the DST slow
- Strong-strong slicing reduces the whole beam
- Slice moments are a function of the beam, not of the launch geometry
- Equal-count slicing permits empty slices
- StrongStrongTask chunking preserves stochastic physics
- Zero-width PIC slice remains finite
- CUDA :equal_count is equal-count even when z has ties
- The CUDA spectral Dirichlet box honours allow_lost_particles
- Non-finite coordinates fail fast at solver chokepoints
- Lost particles cannot influence a strong-strong collision
- Lost-particle charge semantics are pinned per solver family
- Lost particles are dropped from every slicing method
- Longitudinal slicing methods come from one table
- Specified slicing positions are finite at construction, and the clamp is documented (F-72)
- Gathered CUDA PIC routes carry pz; :node refuses silent degradation
- CUDA last_luminosity is the final turn's value, as on CPU
- CUDA luminosity reduces on the device and honors the live mask
- PIC kbb override uses physical units
- GaussianPIC hybrid accepts non-Float64 beams
- Strong-strong shifted moments preserve small spreads
- The gpic cross-plane gate skips work without moving a bit
- GaussianPIC solver construction and metadata
- Zero-width GaussianPIC slice remains finite
- Rank-deficient GaussianPIC reference falls back to PIC
- GaussianPIC beats PIC toward the soft-Gaussian kick
- Spectral solver reproduces soft-Gaussian kick
- Spectral CPU workspaces are reentrant
- PIC field_derivative flag
- PIC slice_interpolation flag
- PIC interaction_grid flag
- PIC grid_extent, grid_quantize and out-of-range deposition
- PIC luminosity overlap sums the full deposit extent
- The CPU PIC workspace sizes its luminosity buffers from the luminosity grid
- Strong-strong solver stack: one source per convention, no dead twin
- Spectral field absolute normalization is derived, not fitted
- CUDA GaussianPIC coupled subtraction matches CPU
- GaussianPIC coupled (rotated) subtraction
- domain_factor is finite at construction and an overflowed box names it (F-38)
- Dropped spectral charge is recorded in a receipt, not only in a warning (F-36)
- A grid_free field point past the Dirichlet wall gets no mirrored field (F-35)
- The CUDA spectral luminosity allocates no per-pair device temporaries (F-40)
- Spectral 6D Dirichlet box contains the drifted source
- Spectral luminosity_schedule reaches its runtime consumer
- The gaussian solver takes the luminosity schedule (reporting-only)
- Spectral synchro-beam longitudinal map is finite
- Soft-Gaussian synchro-beam longitudinal map
- Soft-Gaussian weak-strong map equivalence and coupling
- The CPU soft-Gaussian reads batch_mode and the two schedules agree
- batch_mode is one keyword: PIC, Gaussian-PIC and spectral read it on CPU
- Every solver's pair-schedule receipt has one shape
- CUDA routes record the pair schedule for every solver
- The spectral pair-schedule receipt has one shape on every route and backend (F-39)
- Zero-width soft-Gaussian slice remains finite
- Physical transverse scale controls
- High-energy weak-strong strong-strong limit
- High-energy weak-strong limit: the PIC electron is judged and a failure names its arm (F-114)
- Strong-strong physical parameter validation
- CUDA GaussianPIC honours green_cache=:slice_pair
- CUDA GaussianPIC emits PIC phase timing records
- CUDA PIC parity across every execution route
- PIC :standard alignment tie is resolved by rule, not by rounding noise
- PIC green_type=:lattice
- The lattice Green box is sized in physical units, not index units
- Source and field grids keep equal extent, which the field derivative assumes
- Green-cache expansion preserves the grid alignment its kernels require
- grid_extent is rejected, not ignored, where no estimator runs
- Dropped PIC charge reaches a reader
- Slice moments choose the solver's working precision on both backends
- The wavefront Gaussian route applies the solver's min_sigma, not the beam's rounding of it (F-29)
- PIC-family luminosity returns Float64 on every backend and precision
- Flipping gaussian_when_luminosity moves luminosity and nothing else
- The spectral rms and Dirichlet box are bit-identical across backends
- The gpic direct collide! stamps real turns on CUDA
- Slice geometry is bit-identical across backends

## cuda

CUDA infrastructure and cross-cutting parity: the elementwise walker, launch configuration and thread caps, lost-particle masking, aperture and solenoid parity (13 testsets, 1.4 min).

- The CUDA elementwise walker has one implementation and the deprecated LumpedRad route runs the fused kernel (F-102, F-104)
- CUDA surveyed cavity matches CPU within its derived rounding class
- CUDA tracks a wrapped strong beam elementwise and matches CPU within its declared rounding class
- Every register-heavy kick launch goes through the thread cap
- Every kernel launched through the thread cap is grid-strided (F-42)
- Every raw CUDA PIC launch site is pinned and its kernel fits the device thread ceiling
- A launch the device accepts but the kernel cannot run
- The wavefront bounds reduction is exact at every block size, warp multiple or not
- Offset beams see the same CUDA PIC kick at field_threads=100 and 128
- A field thread count the device accepts but the bounds kernel cannot run is capped, not fatal
- Lost-particle masking agrees between CPU and CUDA
- Aperture losses are identical on CPU and CUDA
- Solenoid agrees on CPU and CUDA

## turn_modulation

the turn-modulation rules and wrappers, the spectral turn tables, the modulated cavities, the one-particle probe (15 testsets, 5.5 min).

- Turn modulation: effectiveness at the kernel boundary, chunking and repositioning
- Turn modulation: rules, wrapper and the pure hook
- Elements and scripts follow-ups: the crab cavity's realize and update at forty harmonics, the drift's z update, the catalogue in the snapshot, the harness's readbacks and device, the derived default seed, the ownership tripwire by forwarding
- Turn modulation: slot bounds and labels at the wrap
- Spectral turn table: exact spectrum, rms, phases and refusals
- Spectral turn table: the producer through the consumer and the recorder
- A turn-modulation provenance entry carries the rule's sigma and octaves
- Turn modulation: white and pink spectra
- Turn modulation: the RF cavity by the same wrap
- Precision policy of the modulated cavities and the radiation element: the Float64 floor and the by-name refusal of a mismatched beam
- Turn modulation at execute!: the global-seed drift warning for resolved spectral tables and the equal-digest check over the resolved line
- Tasks and turn modulation follow-ups: receipts after the refusals, one warning per cause, apertures inside a bare line, frozen tables and preset names, once-per-execute! walks, the stream registry's bounds
- Turn modulation: the one-particle probe verifies the loop per harmonic
- Turn modulation: the strong-strong window and receipt
- Turn modulation: CPU/CUDA identity and the device conversion

## contracts_metadata

the effectiveness contracts, the configuration and element metadata validators, the physics contracts, the documentation pins outside `core.jl` (14 testsets, 7.1 min).

- Element parameter effectiveness
- Solver option effectiveness
- Solver option effectiveness: baseline-equal alternatives, NaN slots and the configuration dump (F-109, F-110, F-113)
- ParamMeta alternatives derive Symbol perturbations
- The validators check every key: declared defaults beyond the example, discrete defaults in their alternatives, runtime maps against method lists, free text non-empty, placement entries against the one table, a method-less kind's answers, policy defaults against constructed policies
- The configuration validator's tree walks reach concrete types at any depth
- perturbs_timing is declared consistently across schemas
- A perturbs_timing disagreement fails the validator
- A solver hidden under an abstract intermediate fails the validator
- The Runtime Objects section is complete
- The placeholder and deprecated policies actually run
- Contract coverage guards: declared kinds, solver tree, broken baselines, unrun contracts
- Configuration rejection
- Physics contracts

## mpi

the multi-process policy, shards and chunk grids, the seam and the launcher arms (16 testsets, 26.2 min).

- The multi-process policy composes the CPU policy, and its seam is the identity at one rank
- The rank shard is a whole number of reduction chunks
- A balanced shard accepts any rank count and is the aligned rule where that divides the chunks
- The reduction chunk grid follows the alignment in force
- A sharded run keys its random streams on the global particle index
- A beam built under the multi-process policy is the beam it composes
- A strong-strong task under the multi-process policy is the task it composes
- A PIC task under the multi-process policy is the task it composes
- The pair migration allocates nothing proportional to the particle count (F-32)
- A Gaussian-PIC task under the multi-process policy is the task it composes
- A spectral task under the multi-process policy is the task it composes
- Per-particle output carries the global particle id and gathers to one file
- The multi-process policy rejects what it cannot honour
- Every collective the MPI extension implements is clocked under its receipt kind
- The multi-process seam runs under an MPI launcher
- The developer harnesses run divided under an MPI launcher

## examples_validation

the example scripts, the harnesses, the CUDA validation arm, the script sweeps (5 testsets, 21.6 min).

- the Example core object answers with real scripts
- Every example script runs against the current interface
- The harnesses refuse the retired OCTOPUS_MP spelling
- No committed script constructs a retired observer or task spelling
- CUDA-requiring validation scripts run in the gate's CUDA arm

## artifact_observers (owed)

three testsets whose subject is the moment reader or the moment row, owed to the existing `artifact_observers.jl` (3 testsets, 0.2 min).

- The moment reader detects format by content, not filename
- Fused CUDA moment row matches the CPU fold on every liveness path
- The CPU moment row is one fused fold: no beam copy, bitwise the serial fold it replaces

## end
