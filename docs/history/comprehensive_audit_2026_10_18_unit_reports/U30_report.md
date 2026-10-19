# U30: test/runtests.jl lines 6448-9635 (stage 4b Part A/B analysis testsets, tracking-task and luminosity testsets, weak-strong kicks, slicing, lattice magnets, PTC fringe)

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Host for every
measurement: sapphirerapids, Julia 1.12.4, 4 threads, one RTX 4500 Ada (`CUDA.functional()` true).

## Region

`/cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` lines 6448-9635, 3188 lines, thirty-two top-level
`@testset`s from "Dense 4x4 map: no longitudinal notions ..." (6448) through "PTC fringe and wedge
conventions" (9551-9634); line 9635 is the blank before "Misalignment maps" (9636, U31's region).
Also read for context, outside the region: the stage-4b fixture helper block 5990-6095 (the
`_st4b_a_*` constructors every analysis testset calls), the suite header 1-160 (lane and CUDA gate
mechanism), and the source lines each lead names.

Lane structure of the region (grep, whole file): no `_lane_gate(...)` opens or closes inside
6448-9635 and none is open across it (the nearest gated section begins at 13948), so every testset
here runs in both lanes. One CUDA gate inside the region, `if CUDA_TESTS_ACTIVE` at 8364, with an
`else @test_skip "CUDA device not available"` arm (8424): the skip is visible.

## Provenance

READ line by line: 6448-9635 in eleven consecutive chunks (6448-6720, 6719-7000, 7001-7275,
7274-7600, 7601-7900, 7899-8200, 8201-8500, 8493-8800, 8801-9100, 9101-9400, 9401-9640); plus
5990-6095 (helpers), 1-160 (gates), and the source excerpts cited below
(`src/analysis/eigenmodes_4d.jl:303-335`, `src/analysis/twiss_dispersion_analysis.jl:968-990`,
`src/tasks/strongstrong/interface.jl:2249-2256`, `src/tasks/Tasks.jl:1-12`,
`src/math/SpecialMath.jl:4,173-174`, `src/analysis/dispersion_routes.jl:45`).

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U30/`,
each `.jl` run as `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`,
output in the sibling `.log`):

- `probe_branches.jl` -> `probe_branches.log`: the data-dependent branches of three analysis
  testsets, the snapshot-on-disk guard, two tolerance margins, the reason-table hand list, the
  `erf`/`inverse_erf` provenance, the five golden virtual-drift tuples. Numbers quoted in the leads.
- `probe_live_fixtures.jl` -> `probe_live_fixtures.log`: fixtures on which the two dead branches
  (leads U30-1, U30-2) become live.
- `probe_scaling_replay.jl` -> `probe_scaling_replay.log`: the suite's own "Scaling: :none, :auto
  and an explicit tuple ..." testset replayed with its helpers (the title-runner cut errors with
  `UndefVarError: _st4b_a_dense6`, the artefact the brief names; `scaling_testset.log` keeps that
  run): 116/116 pass, worst row ratio 109.16 (`:beta`) in c eps kappa units against c = 2048.
- `probe_cuda_lumpedrad.jl` -> `probe_cuda_lumpedrad.log` (CUDA active): all six coordinates of the
  deprecated CUDA LumpedRad route against the host context path (lead U30-8).
- `repro_check.sh` -> `repro_check.log`: the self-contained one-liners quoted as Repro below, run
  verbatim.

## Leads

### LEAD U30-1 [Moderate, confidence high] test/runtests.jl:7143
Claim: The "Explicit partitions ..." testset's only check of an explicit partition BLOCKING the 4x4 frame (lines 7146-7149, the `else` arm: reason, the "explicit partition" detail, `preferred_form` inactive) never executes, and it is the whole suite's only consumer of that production branch.
Mechanism: The test consults the artifact to choose its expectation: `block = Octopus._frame_availability(ru4.clusters)` and branches on `block === nothing`. On the fixture it is handed (the dense stable 4x4, explicit union `[[1, 2, 3, 4]]`) both modes have the same Krein orientation, the union classifies `:definite` and resolved, `_frame_availability` returns `nothing` (measured), so only the `if` arm (frame determined) runs. The comment two lines below ("the same rule on a genuinely blocked explicit report: the indefinite 4D union of stage 3") then analyzes `Mi4` under the AUTO partition, not an explicit one. `grep -n "explicit partition" test/runtests.jl` finds the detail string asserted only at 7148, so `src/analysis/twiss_dispersion_analysis.jl:984` (`block === nothing || (fr = Determined{NormalModeFrame4D}(block[1], "explicit partition blocks the frame: " * block[2]))`) is exercised by no test. A fixture whose two modes rotate oppositely makes the arm live: the explicit union is `:indefinite` (Gram signs [-1, 1]), the frame is blocked with that detail and `preferred_form` reports `:inactive_dependency` (measured, `probe_live_fixtures.log` [a']). Defect classes 1 and 13.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus, Random; M4 = Octopus._manufactured_symplectic_map(MersenneTwister(20260911), 4; stable=true)[1]; rot(m) = [cos(m) sin(m); -sin(m) cos(m)]; L = cat(rot(0.73), rot(-1.41); dims=(1, 2)); for M in (M4, L); r = analyze(TwissDispersionAnalysis(clusters=[[1, 2, 3, 4]], strict=false), M); println(repr(Octopus._frame_availability(r.clusters)), " | frame determined: ", Octopus.is_determined(Octopus.determined_value(r.transverse).frame)); end'` prints `nothing | frame determined: true` for the suite's fixture (the `else` arm is dead) and `(:indefinite_cluster, "cluster [1, 2, 3, 4] (indefinite): Gram signs [-1, 1]; ...") | frame determined: false` for the opposite-orientation map (the arm would run).

### LEAD U30-2 [Minor, confidence high] test/runtests.jl:7132
Claim: The assertion that an explicit union of two conjugate pairs degrades the result and names "cluster 1" (lines 7132-7134) is behind a data condition that is false on its fixture, so it never runs.
Mechanism: `if ru.clusters.clusters[1].classification in (:indefinite, :unresolved)` guards the `@test`; on the dense 6D fixture every pairwise union of the auto clusters classifies `:definite` (measured for (1,2), (1,3), (2,3)), so the body is skipped and the testset only pins that the classification is some member of `CLUSTER_CLASSIFICATIONS` and that the grouping was honoured. The docstring of the `clusters` option (`twiss_dispersion_analysis.jl:398`, "an explicit union of far-apart pairs with a mixed Gram is :indefinite") describes exactly the case the fixture cannot produce. A map built from opposite-orientation pairs, `W blockrot(0.73, -1.41, -0.94) W^-1`, gives `:indefinite` for the unions (1,2) and (1,3), status `:degraded`, "cluster 1" named (measured). Defect class 13.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus, Random; rot(m) = [cos(m) sin(m); -sin(m) cos(m)]; W = Octopus._manufactured_symplectic_map(MersenneTwister(20260911 + 77), 6; scale=0.1).M; for M in (Octopus._manufactured_symplectic_map(MersenneTwister(20260911), 6; stable=true)[1], W * cat(rot(0.73), rot(-1.41), rot(-0.94); dims=(1, 2)) * Octopus._symplectic_inverse(W)); part = [c.members for c in analyze(TwissDispersionAnalysis(strict=false), M).clusters.clusters]; ru = analyze(TwissDispersionAnalysis(clusters=[vcat(part[1], part[2]), part[3]], strict=false), M); println(ru.clusters.clusters[1].classification); end'` prints `definite` (the suite's fixture: the guarded `@test` never runs) then `indefinite` (a fixture on which it would).

### LEAD U30-3 [Minor, confidence high] test/runtests.jl:6643
Claim: `@test Octopus._CLOSED_ORBIT_ATOL_MULTIPLIER * eps() * 1.0 > 0` is a tautology standing in for the default closed-orbit tolerance rule, which the testset never asserts.
Mechanism: The constant is `64.0` (`twiss_dispersion_analysis.jl:211`); a positive constant times `eps()` is positive whatever the rule is. The comment above it ("the default atol: c eps max(1, max|point|), a fixed point at the origin has residual exactly zero") names the behaviour at `twiss_dispersion_analysis.jl:923` (`atol = 64 eps max(1, max|C point|)`, scaled coordinates), but no line exercises it: the receipts checked at 6608 and 6633 pin `closed_orbit_atol === nothing` / `1e-12` and the action, not the effective default; the `:require` throw at 6621 and the `atol=1.0` acceptance at 6639 bracket the default by six orders of magnitude on either side. A regression that multiplied the default by 1e6, or dropped the `max(1, |point|)` factor, passes every line of this testset. Defect classes 1 and 13.
Repro: `grep -n "_CLOSED_ORBIT_ATOL_MULTIPLIER" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` returns only the tautology line (no second use anywhere in the suite); `grep -n "_CLOSED_ORBIT_ATOL_MULTIPLIER" /cfs/ad/dxu/Library/Julia/Octopus/src/analysis/twiss_dispersion_analysis.jl` shows the rule at the line defining `atol`.

### LEAD U30-4 [Minor, confidence high] test/runtests.jl:7209
Claim: "the guard's message form" (7207-7214) tests a loop the test writes itself, not the tree guard inside `validate_configuration_metadata`; the real guard has no executed negative control.
Mechanism: Lines 7209-7213 build `msgs` by iterating `(derived..., Nothing)` against the local `hand` tuple and push the literal message; 7214 asserts `msgs` equals that literal. The production guard is the loop at `src/tasks/strongstrong/interface.jl:2249-2253` over `_concrete_octopus_subtypes(AbstractAnalysis)` against `_analysis_types`; nothing calls it with an unregistered concrete analysis, because defining one inside the suite would permanently break the derived-set pin at 7201 and the real `validate` later in the file. The only tie to the production code is `occursin` on the source text (7217-7219), which proves the string is present, not that the loop runs or reports. The identical pattern was priced once already (previous audit U16-1/U17: tautological `@test` inside the active CUDA branch). Defect class 13.
Repro: `sed -n 7207,7219p /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` (at 24e8683; search for `msgs = String[]` after drift) shows the test-local loop and the literal it is compared with; `sed -n 2249,2254p /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/interface.jl` shows the guard it never invokes.

### LEAD U30-5 [Minor, confidence high] test/runtests.jl:6763
Claim: In "Prescribed h = 0.05 ...", the loop asserting that "another branch" route failures of the heuristic run are named in its degradations iterates an empty set, so it asserts nothing for that run.
Mechanism: `other` (6762) filters `r.dispersion.routes` for `:newton`/`:fixed_point` with status `:not_invariant` and an "another branch" detail. On the heuristic run `r` the statuses are eigenplane/polynomial/projector/newton `:none` and fixed_point `:not_invariant` without "another branch" (measured), so `other == Symbol[]` and the `for route in other` body never executes; the sibling loop `nonconv` runs once (`[:fixed_point]`). The property is pinned non-vacuously only on the certified run (`other_c == [:newton]`, 6772-6774). The comment at 6761 ("the iterative routes on the heuristic's mode: 'another branch' degradations name the route (record item 2)") promises a check that the data does not provide. Defect class 13; low impact because the certified-run pin exists.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; rot(m) = [cos(m) sin(m); -sin(m) cos(m)]; zeta = [1.0, 0.2, 0.1, 0.0]; eta = [0.0, 0.95, 0.0, 0.0]; t = Octopus._dispersion_transformation(zeta, eta); M = t.M_cal * cat(rot(0.63), rot(1.74), rot(-0.94); dims=(1, 2)) * Octopus._dispersion_transformation_inverse(zeta, eta, 0.05); r = analyze(TwissDispersionAnalysis(strict=false), M); println([(x.route, x.status, x.status === :not_invariant && occursin("another branch", x.detail)) for x in r.dispersion.routes])'` prints five triples whose third entry is false in every one (displayed as `0` in the typed vector; so `other` is empty) and `:not_invariant` only on `:fixed_point` (verbatim output in `probes/U30/repro_check.log`).

### LEAD U30-6 [Minor, confidence high] test/runtests.jl:6716
Claim: The coasting-map dispersion pin `<= 256 eps kappa` sits 2.2x above its measured value, inside the window the neighbouring Scaling testset's own one-tenth rule forbids.
Mechanism: Measured today, `norm(eta - cst.eta) / (eps kappa) = 115.92` (the comment says "c measured 116"), against c = 256. The Scaling testset at 6526-6535 states and applies the rule "the one-tenth rule puts c at or above" ten times the measured ratio (it raised its own c from 256 to 2048 for a measured 110.7); the same author applies no margin rule here, so this is a pin resting on this host's rounding rather than on a stated structure (defect class 8). The Prescribed-h triple at 6749-6752 is comfortable by comparison (worst measured 4.08 against 64). A different BLAS or FMA contraction (the CI's Haswell arm, memory: two-arm gate) has at most a factor 2.2 before this line fails for a non-defect; I did not run that arm.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus, Random, LinearAlgebra; rng = MersenneTwister(20260911); eta = 0.2 * randn(rng, 4); A4 = Octopus._manufactured_symplectic_map(rng, 4; scale=0.3, stable=true).M; S4 = Octopus._symplectic_form(4); Mc = Matrix(1.0I, 6, 6); Mc[1:4, 6] = eta; Mc[5, 1:4] = transpose(eta) * S4; M = Mc * cat(A4, [1.0 0.3; 0.0 1.0]; dims=(1, 2)) * Octopus._symplectic_inverse(Mc); r = analyze(TwissDispersionAnalysis(), M); S = Octopus.determined_value(r.separation); kappa = max(1, norm(M)) * norm(S.transformation) * norm(S.inverse); println(norm(Octopus.determined_value(r.physical.eta) - eta) / (eps() * kappa))'` prints about 115.9 (bound 256; the Scaling testset's rule would ask for >= 1160).

### LEAD U30-7 [Minor, confidence med] test/runtests.jl:8468
Claim: The five virtual-drift selectors are pinned by `element(q...) == reference` against 17-digit literals with no tolerance: change detectors resting on rounding, against the invariant "prefer physics-level agreement, state every tolerance".
Mechanism: The kick the tuples encode is 3.67e-5 in px and 2.3e-8 to 2.7e-8 in pz on 1e-4-scale coordinates; bitwise equality on the full coordinate therefore resolves ~1e-21 absolute, far below any physical claim, and holds only while every operation's order and contraction are unchanged. Measured today: all five tuples agree to 0 ulps in every component on sapphirerapids; the previous audit (U17, row 9) already classed them "change-detector only (17-digit golden tuples, class-1 provenance)" and recorded that their provenance was never re-derived. Correctness is covered elsewhere (the symplecticity step scan at 8867 with its unsafe negative controls, the coupled-covariance checks at 8742), so the pins add fragility (a legitimate reordering, a compiler contraction change, another CPU) rather than evidence. Defect class 8.
Repro: `sed -n '/Physical and unsafe weak-strong virtual drifts/,/^end/p' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | grep -c "== reference"` returns 1 inside a loop over 5 selectors; `probe_branches.log` section [h] lists the per-component ulp distances (all 0 here) and the kick scales.

### LEAD U30-8 [Minor, confidence med] test/runtests.jl:8398
Claim: The CUDA LumpedRad parity asserts x and px against the host (and x, px, pz for run-to-run reproducibility) but never y, py or z, although each plane draws its own counter component.
Mechanism: Lines 8396-8399 compare `g1.x`, `g1.px` against the host context path; 8381-8382 compare x, px, pz between two device runs. A wrong component index or turn key in the y or z plane of the device wrapper (`track!(::LumpedRad, CUDABackend)`) would pass this testset. Measured today with the testset's own fixture: every coordinate agrees, max |gpu - host| = 4.3e-19 (x), 8.7e-19 (px), 3.3e-19 (y), 2.2e-19 (py), 6.5e-19 (z), 4.3e-19 (pz) on 1e-3-scale motion, and every coordinate is bitwise reproducible between two device runs. So a coverage gap with no present divergence (defect classes 4 and 13).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U30/probe_cuda_lumpedrad.jl` prints the six per-coordinate maxima above (all <= 1e-18); `sed -n '/deprecated CUDA LumpedRad route/,/^end/p' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | grep -c "ref.y\|ref.py\|ref.z"` returns 0.

### LEAD U30-9 [Minor, confidence high] test/runtests.jl:6838
Claim: The "Reason table" testset's title says the seen set "equals the set the docstrings claim", but `claimed` is a hand-written literal; no docstring is read in the testset.
Mechanism: Line 6905 compares `seen` with the 12-member literal at 6838-6840 and 6906 checks membership in `DETERMINATION_REASONS`; the docstring tie actually lives at runtests.jl:807 (`documented(:DETERMINATION_REASONS) == Set(DETERMINATION_REASONS)`, outside this region) and the length pin at 794. Measured: the literal plus the comment's three exclusions plus `:none` equals `Set(DETERMINATION_REASONS)` today, so nothing has drifted; the defect is the title's claim (class 14, documentation as claims) and the hand copy (class 2) whose tripwire is in another testset rather than beside it.
Repro: `sed -n '/Reason table: one fixture per reason/,/^end/p' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | grep -c "Docs\|docstring\|documented"` returns 0; `probe_branches.log` section [f] shows the set identity that holds today.

### LEAD U30-10 [Minor, confidence med] test/runtests.jl:7432
Claim: The snapshot-on-disk comparison in "4b-B registry, description, snapshot lines, the real validate" is behind `if isfile(ondisk)` with no `else`, so a path miss would silence it without a visible skip.
Mechanism: `ondisk` is derived by three `dirname`s from `first(methods(Octopus.validate_configuration_metadata)).file` and one more to the repo root; it encodes that the defining file sits exactly three directories below the root (`src/tasks/strongstrong/interface.jl` today). Measured: `ondisk = /cfs/ad/dxu/Library/Julia/Octopus/docs/registry_snapshot.md`, `isfile = true`, so the body runs at 24e8683. Moving `validate_configuration_metadata` one directory up or down (it has moved between files before; the policy and contract blocks it hosts belong to other directories) turns the check off with no `@test_skip`, against the invariant "skips are visible". The byte-exact snapshot pin in "Architecture integrity" would still catch snapshot drift, so the risk is to this testset's own weaker claim, not to the gate. Defect class 1 (latent).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; root = dirname(dirname(dirname(String(first(methods(Octopus.validate_configuration_metadata)).file)))); p = joinpath(dirname(root), "docs", "registry_snapshot.md"); println(p, " ", isfile(p))'` prints the path and `true` today; the guard has no `else` (`sed -n 7432,7438p` at 24e8683).

## Clean

What was compared, and the measurement, for the parts of the region that audit sound:

- Gates (hypothesis 1): no lane gate touches the region (grep for `_lane_gate(` over the whole
  file: first site 13948), so every testset here is in the fast lane's accounting as well as the
  full gate's; the single CUDA gate (8364) has a visible `@test_skip` arm. No `@testset` body sits
  behind a constant-false condition; the data-conditional bodies that are false on their fixtures
  are leads U30-1, U30-2 and U30-5.
- Scaling invariance (6526-6586), replayed with the suite's helpers: 116/116 pass, worst row ratio
  109.16 (`:beta`) against c = 2048 (18.8x margin; the comment's recorded 110.7 over 332 rows is
  consistent). The receipt check reads the requested tuple back under the option's own name.
- Prescribed h triple (6749-6752): measured ratios h 0.052, zeta 4.08, eta 0.31, graph 1.23 against
  64 (15.7x margin on the worst).
- Reason table set identity: hand list + {`:graph_isotropic`, `:zero_projection`,
  `:not_derived_for_cluster`} + {`:none`} == `Set(DETERMINATION_REASONS)` (16 members) today.
- `erf` round trip (9094-9098) is NOT circular: `Octopus.erf` is `SpecialFunctions.erf` and
  `inverse_erf(x) = erfinv(x)` (`src/math/SpecialMath.jl:4,174`), an independent rational
  approximation, so `erf(inverse_erf(u)) ≈ u` tests one against the other as the comment claims; the
  circular `:equal_area` leg (9079-9092) is labelled circular and anchored by Furman's Table 1
  (5e-6, measured 4.34e-7 in U17).
- Luminosity route pins (7702-7801): `:isolated === :fused` is justified structurally (both routes
  use the fixed 64-chunk GLOBAL partition and the chunk-ordered `_mp_chunk_fold`, stated at
  7709-7713); the routes are shown to differ in plan shape (3 segments vs 1, `IsolatedSegment` vs
  `LuminousFusedSegment`), the receipt names the route that ran, and thread invariance is asserted
  at 1, 2, 4 workers (`policy.threads` is consumed by `_run_logical_workers`, phase6d_track.jl:50,64).
- `luminosity(strong, ctx, rep)` at 7840 reads `elem.last_luminosity` (`src/tasks/Tasks.jl:11`),
  so the "still records a luminosity" check tests the recorded value, not a recomputation.
- Negative controls present and executed: the verdict kernel (6957-6986: each `_VERDICT_RESIDUALS`
  triple bumped above its acceptance fails naming it, each reported-only triple bumped still
  passes); the validator block (7188-7199: three injected drifts, one message each); the contract
  plumbing (7355-7415: twelve injected defects through `_st4b_b_fake_run`, every one red); the
  receipt matcher (7315-7353); the virtual-drift symplecticity step scan (8867-8915: safe drifts
  fall as step^2 within [50, 200], unsafe ones flat within 5% and above 1e-5); the slicing table
  against published values; the near-round kernels against 256-bit BigFloat references.
- Hand-copied counts that are loud tripwires rather than silent drift: routes `== 5` and
  `route_not_selected == 4` (source `DISPERSION_ROUTES` has five members,
  `dispersion_routes.jl:45`), `length(rep) == 14` beside the derived `fieldnames` comparison,
  `length(ina) == 16` beside the 16 listed pairs, the contract metrics 19/16/4/15/32 with their
  derivations in comments. Each fails loudly when its source changes; none is derived.
- Receipts (6999-7073): the consumer set is derived from `_ANALYSIS_CONSUMERS`; the per-consumer
  key tuples are a hand-written spec table compared with `keys(r.values)` for every receipt.
- Turn-modulation effectiveness (8052-8272): both turn loops asserted by the receipt's `fast_path`
  flag; chunking, repositioning and window refusal are bitwise and state-checked (`next_turn`,
  untouched beam); the duplicate-stream warning has silent positives on distinct ids and on two
  slots of one cavity.
- Per-turn timing (7899-8002): the OFF arm is asserted empty; the allocation bound is ON against
  OFF at equal turn count after three warm-up rounds (the comment records why one round is not
  enough); timings are cleared per `execute!` and the accessor copies.
- Lattice magnets (9215-9438): the bit-identity between `one_turn_matrix` and the local complex-step
  closure is declared as "the helper IS this closure's arithmetic" (a witness, not a tolerance
  hiding a floor); symplecticity 1e-13, curved-drift closed form 1e-14, nst/integrator_order
  convergence ratios, removable singularity h -> 0, fringe defaults measured; the bend-fringe
  no-angle comparison was converted from bitwise to a 1e-40 bound with its reason recorded.
- Hand-checked arithmetic in the region: `h = 1 - zeta' S_4 eta = 0.957` for the quoted pair;
  `(order-1)!!` as `prod(max(order-1,1):-2:1)`; the near-round `eta` bounds and blend endpoints.
- The golden tuples (lead U30-7) and the snapshot guard (lead U30-10) hold today: 0 ulps, `isfile
  = true`.

Style only (not leads): three bare `@test true` after `execute!` calls (7884, 7890, 7896) where the
intent is "does not throw"; the high-order-multipole "acts" check `out[2] != ua[2]` (9530) is not
isolating for the combined-function `SBendSpec` member of its loop (the bend and k1 already move
px); `typeof(e).parameters[7] == 0` (9393) pins a positional type parameter.

## Unchecked

- The region's testsets other than "Scaling ..." were not executed as testsets by me; their
  green state is the suite's record (CI and the two-arm gate in the project memory), not my
  measurement. My probes re-ran the specific computations the leads rest on.
- Cross-architecture behaviour of the bitwise pins (U30-7) and of the 2.2x margin (U30-6) under the
  CI's Haswell/AVX2 arm was not run here; both are measured on sapphirerapids only.
- Lines 6077-6447 (the `_st4b_b_fake_run` scratch verb, the validator mirror
  `_st4b_b_block_errors`, and the Part A testsets before 6448) are outside the region and were not
  read, so the fidelity of the fake run to `analyze` (which the twelve negative controls at
  7355-7415 depend on) is taken on trust here; the real `validate(c)` at 7441-7446 does pass with
  the same metrics, which bounds the risk.
- The 1e-16 absolute bound at 8398-8399 was not re-derived against a model of FMA contraction; the
  measured 8.7e-19 leaves two orders of margin.
- Out-of-region seam, noted and stopped: the curved-drift reference at 9279 and the kernel it checks
  both form `z0 + L - (1 + pz) * Δ` (defect class 12, cancellation of two O(1) terms to O(1e-3));
  the test's `atol=1e-14` is met, so this is a kernel-side question for the drift's owner, not a
  test defect.
- The MPI arms and the examples lane do not pass through this region; nothing was checked there.
