# U11: Contracts.jl, second half + the MPI child

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683 (read-only; nothing in it
was modified, no git command was run there). Every claim below is a LEAD, not a finding.

## Region

- `src/contracts/Contracts.jl` lines 2101-4104 (2004 lines): the tail of
  `validate(::HighEnergyWeakStrongLimitContract)` (2101-2164), `CoherentModePhysicsContract`
  (2166-2320), `PTCConsistencyContract` (2322-2646), `MADXSurveyConsistencyContract`
  (2649-2814), `ElementParameterEffectivenessContract` with its probe/exemption tables and
  perturbation helpers (2817-3415), `SolverOptionEffectivenessContract` with its tables, receipt
  helpers and the CPU/CUDA sweep (3417-4104).
- `src/contracts/mpi_pic_consistency_child.jl` (55 lines), the launched child of
  `StrongStrongPICMultiProcessConsistencyContract`.

Total: 2059 lines, read line by line.

## Provenance

READ, line by line (absolute line numbers):
- `src/contracts/Contracts.jl` 2030-4104 (2030-2100 as lead-in context for the function split
  at 2101; 2101-4104 is the region).
- `src/contracts/mpi_pic_consistency_child.jl` 1-55.
- Reference context, read to judge the child protocol and the seams (not part of the region, no
  leads claimed inside them except where marked CROSS-FILE): `src/contracts/Contracts.jl` 20-64
  (`ContractResult`), 130-200 (the multi-process contract struct and docstring), 1470-1720 (the
  parent-side `_mpi_pic_contract_*` functions and `validate`); `ext/OctopusMPIExt.jl` 20-60
  (`MPI.Init(threadlevel=:funneled)` on first communicator open);
  `src/tasks/strongstrong/interface.jl` 286-320 (`_cuda_pic_threads`, the `:cuda_pic_launch`
  receipt site); `src/policies/Policies.jl` 17-40 and 150-200 (`ConfigurationOptionMeta`,
  receipts); `src/knowledge/Knowledge.jl` 80-90 and 225-240 (`_PLACEMENT_PARAM_KEYS`,
  `ParamMeta`); `docs/design/multi_process_policy.md` 160-175 and 310-325 (the rank-death
  posture); `test/runtests.jl` 13950-14130, 14255-14362, 14500-14554, 23785-23811, 24200-24285,
  30600-30640 (every testset that runs a contract of this region); the previous audit's
  `docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U4_report.md` lead headers and
  the bodies of U4-1..U4-8; `~/.julia/packages/MPI/pvbg6/src/environment.jl` 114-160 (MPI.jl's
  exit-code-aware `atexit` Finalize hook); the committed tables
  `validation/reference/ptc_madx_5.03.06.tsv` and `survey_madx_5.03.06.tsv` (headers, field
  counts, rows per case).

EXECUTED (scratch: `result/comprehensive_audit_2026_10_18/probes/U11/`, logs beside each script;
`julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`):
- `probe_a_element_sweep.jl` (log `probe_a.log`): replays the element sweep with every
  (kind, parameter) outcome recorded and the exempted pairs probed. Totals: 530 swept-moved,
  23 swept-rejected, 41 swept-unperturbable, 31 carried (matches the shipped metrics
  530/23/41/31); exempt pairs probed: 21 moved, 8 ignored, 6 rejected, 3 unperturbable.
- `probe_b_solver_alternatives.jl` (`probe_b.log`): all 90 (solver, option) rows with
  category, consumer, backends, exemption, baseline value, alternative; no swept alternative
  equals its baseline value (the only EQUAL row is the exempt `GaussianPICPoissonSolver.grid_extent`).
  `_solver_contract_spread` with a NaN returns `NaN`; `NaN > 1e-10` is `false`;
  `max(0.0, NaN) = NaN`. All four CPU baselines: 0 NaN of 3072 coordinates, 22 receipts each.
- `probe_c_rank_death.jl` + `probe_c_driver.jl` (`probe_c.log`): two ranks under `MPI.mpiexec()`
  (MPICH ABI, as the suite's `MPICH_jll.mpiexec()`), rank 1 dies while rank 0 waits in a
  collective. `exit(1)`: launcher returns in 1.3 s, exit code 1; uncaught exception: 3.4 s,
  exit code 1; watchdog never fired.
- `probe_ef_solver_cpu_only.jl` under `CUDA_VISIBLE_DEVICES=""` (`probe_ef.log`): E, a stale
  solver exemption `(:PICPoissonSolver, :no_such_option)` gives `status = skipped`, no
  `:stale_exemptions` metric; F, alternative `PICPoissonSolver.batch_mode => :wavefront`
  (the schema default, unset by the probe) gives `status = skipped`, no "equal to its own probe
  value", no failure naming `batch_mode`, "73 CPU-visible solver options reached a consumer"
  (same count as shipped).
- `probe_gh_element_exemptions.jl` (`probe_gh.log`): G, the shipped contract passes with
  `checked = 530`, `exemptions_declared = 38`; with the twelve exemptions of LEAD U11-1 removed it
  passes with `checked = 542`, `exemptions_declared = 26`, `ignored = 0`. H, the ParamMeta
  alternatives: `misalign_convention` is `(:bmad, :madx)` on 24 kinds and `()` on the 7
  zero-length kick kinds whose declared meaning says "At zero length the reference point cannot
  matter"; `gaussian_strong_beam.slice_method` and `thin_strong_beam.virtual_drift` declare `()`
  while their meanings list several legal values.
- `probe_i_cuda_floor.jl` (`probe_i.log`, RTX 4500 Ada): repeat spread of two identical CUDA
  baselines, the contract's self-calibrated floor `max(100*spread, 1e-10)`: GaussianPIC 7.1e-13
  (floor 1e-10), Gaussian 0.0 bitwise (1e-10), PIC 1.7e-11 (1.7e-9), Spectral 5.7e-16 (1e-10);
  0 NaN coordinates in every baseline; receipt consumers listed per solver.
- `probe_j_stdout_capture.jl` (`probe_j.log`): the parent's capture shape
  (`run(pipeline(cmd; stdout=buffer, stderr=buffer); wait=false)`, `wait(proc)`, `take!`) with a
  child printing 20000 lines then `exit(1)`: 20000/20000 captured, last line present, 3 of 3
  trials.
- `probe_k_wsl_pic_electron.jl` (`probe_k.log`): at the contract's own setup the PIC electron's
  max |change| is 5.4e-20 (same as the asserted soft-Gaussian electron's), the PIC proton moves
  by 1.8e-5; the contract passes with six metrics, none of them a PIC electron change.
- The one-liners quoted in the Repro fields of U11-1 and U11-4 were run and print the values
  quoted.

## Leads

### LEAD U11-1 [Moderate, confidence high] src/contracts/Contracts.jl:3057-3070
Claim: twelve `DEFAULT_INACTIVE_ELEMENT_PARAMS` exemptions state structural reasons ("a constant kick commutes with transverse displacements", "writes y without reading it, so a vertical displacement conjugates to exactly nothing") that the shipped probe falsifies by measured deviations of 1e-8 to 2.3e-6, and the sweep never notices because an exempted pair is `continue`d before it is probed (3334-3337) — the "bad direction" the file's own comments at 2999-3000 and 3324-3326 say matters.
Mechanism: every probe carries all six placement DOF (3306-3308: `x_pitch = 0.8e-3`, `y_pitch = -0.6e-3`, `tilt = 0.9e-3`), so a transverse offset no longer commutes with the kick: the pitch turns the offset into a longitudinal displacement of `offset * pitch`, the kick changes the momentum between the forward and backward displacement, and the net move is `kick * offset * pitch` — measured `thin_dipole.x_offset` 1.0390647e-7 = 1e-3 (k0l) x 0.13 (the +0.13 candidate) x 0.8e-3 (x_pitch) to three digits, `hkicker/vkicker/kicker.x_offset` ~1.04e-8 (hkick = 1e-4), `.y_offset` ~7.8e-9, `thin_rf_cavity.x_offset` 3.8e-8 / `.y_offset` 2.9e-8, and `lorentz_boost.y_offset` / `rev_lorentz_boost.y_offset` 2.34e-6 (through the tilt, the boost reads x). The exemption rows are evaluated only by `haskey(contract.inactive, (kind, key))`, and `exemptions_seen` (3335) detects a pair the sweep cannot REACH, not a pair whose reason is false; so these twelve rows document physics the probe contradicts and would keep excusing the parameters if a placement-wrap regression ever made them genuinely ignored. The other 26 rows hold: 8 probe as bitwise-ignored (the `lumped_radiation`, `thin_strong_beam.klum/alpha`, `aperture.element_id` rows), the 7 marker rows move by 4e-19..4e-17 as their "cancels to roundoff" text says, the rule-object and `harmon`/`line.L`/`aperture.alive`/`loss_record` rows are rejected or unperturbable as stated.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus; O=Octopus; u=(2.3e-3,4.1e-4,-1.7e-3,-3.2e-4,1.5e-3,9.0e-4); for (kind,key) in ((:thin_dipole,:x_offset),(:lorentz_boost,:y_offset)); T=only(t for t in O.registered_element_specs() if O._element_meta_or_nothing(t).kind===kind); ctor=O._element_meta_or_nothing(T).friendly_constructor; p=haskey(O.DEFAULT_ELEMENT_PARAM_PROBES,kind) ? Dict{Symbol,Any}(pairs(O.DEFAULT_ELEMENT_PARAM_PROBES[kind])) : Dict{Symbol,Any}(O.params(O.example_spec(T))); for (k,v) in pairs(O._PLACEMENT_PROBE_DOF); haskey(p,k) || (p[k]=v); end; b=collect(O.compile_runtime(ctor(;p...))(u...)); m=collect(O.compile_runtime(ctor(;merge(p,Dict{Symbol,Any}(key=>p[key]+0.13))...))(u...)); println(kind,".",key," ",O._probe_deviation(m,b)," | ",O.DEFAULT_INACTIVE_ELEMENT_PARAMS[(kind,key)]); end'` prints `thin_dipole.x_offset 1.0390647054705701e-7` and `lorentz_boost.y_offset 2.3420580761903537e-6` beside reasons claiming exactness. And the whole table: `probes/U11/probe_gh_element_exemptions.jl` section G — with the twelve rows removed the contract still passes, `checked` 530 -> 542, `ignored = 0`.

### LEAD U11-2 [Moderate, confidence high] src/contracts/Contracts.jl:3931-3940
Claim: on a process with no visible CUDA device — CI — `_validate_solver_options` returns before its stale-exemption tripwire (4087-4094), so a stale `(solver, option)` exemption in `DEFAULT_INACTIVE_SOLVER_OPTIONS` is reported as `:skipped` with no `:stale_exemptions` metric, and the suite's tolerant assertion (`test/runtests.jl:14511`, `status === :passed || (status === :skipped && !CUDA_TESTS_ACTIVE)`) accepts it.
Mechanism: the early return at 3936-3939 is placed after the CPU half and before both the CUDA half and the U4-17 staleness check; `solver_exemptions_seen` is complete at that point (it is filled in the CPU loop at 3863-3866 for every option regardless of backend), so the check could run there, but it does not. The element contract's twin check (3385-3406) has no such bypass. The comment at 4083-4086 states the tripwire's purpose as catching "an entry whose option later becomes genuinely ignored" — on the CPU-only gate the tripwire never executes, which is the brief's defect class 1.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && env CUDA_VISIBLE_DEVICES="" julia --project=. --threads=4 -e 'using Octopus; stale=merge(Octopus.DEFAULT_INACTIVE_SOLVER_OPTIONS, Dict((:PICPoissonSolver,:no_such_option)=>"stale")); r=validate(SolverOptionEffectivenessContract(inactive=stale)); println(r.status, " ", haskey(r.metrics,:stale_exemptions))'` prints `skipped false` (measured, `probe_ef.log` section E); the same command with the device visible should print `failed` naming `PICPoissonSolver.no_such_option`.

### LEAD U11-3 [Minor, confidence high] src/contracts/Contracts.jl:3879-3883
Claim: the vacuity guard compares a declared alternative with the PROBE's value only, so an alternative equal to the schema default of an option the probe does not set compares the solver against itself and is counted "checked"; for an execution option that comparison passes silently (not moved, and the receipt carries the default).
Mechanism: `haskey(option_probe, name) && isequal(getproperty(option_probe, name), alt_value)` is false whenever the probe lacks `name`, whatever the constructed baseline `T(; probe...)` actually carries; the baseline value is available as `getproperty(baseline_solver, name)` (or the schema default) and is not consulted. Today no swept alternative equals its baseline (probe B, all 90 rows), so the gap is latent; it opens the day a default moves onto a listed alternative (`cuda_async`, `cuda_batch_fft`, `cuda_wavefront_fft`, `cuda_indexed_wavefront`, `batch_mode`, `green_cache`, `grid_extent` and `longitudinal_kick` are all one default flip away from their listed alternative). The suite's control at `test/runtests.jl:14544-14552` exercises only the probe-value case.
Repro: `probes/U11/probe_ef_solver_cpu_only.jl` section F: with `alternatives[:PICPoissonSolver][:batch_mode] = :wavefront` (the default; the probe does not set `batch_mode`) the contract reports no guard message and no failure, and "73 CPU-visible solver options reached a consumer" — the same count as shipped, i.e. `batch_mode` was counted as checked against itself. The expected shape is a failure reading "declares an alternative equal to its baseline value".

### LEAD U11-4 [Minor, confidence high] src/contracts/Contracts.jl:3695-3705
Claim: `_solver_contract_spread` propagates NaN (`max(dev, NaN)` is NaN) and the device half compares `spread > cuda_floor` (4023), which is `false` for NaN — so a CUDA execution option that turns a coordinate into NaN passes "must not move", and a NaN in either calibration baseline makes `cuda_floor` NaN (3996) and every device-half movement check vacuous.
Mechanism: the coordinate loop at 3697-3699 has no NaN handling (the luminosity loop at 3700-3703 skips only the both-NaN case); Julia's `max` propagates NaN; `NaN > x` is false; `max(NaN * 100, 1.0e-10)` is NaN. The CPU half is not affected (`_solver_contract_moved` uses `!=`, and `NaN != NaN` reads as moved, which fails an execution option loudly). The element contract fixed the same shape in U4-1 (`_probe_deviation`, 3241-3251); the solver contract's device comparator did not receive the fix. Latent today: both CPU and CUDA baselines carry 0 NaN of 3072 coordinates (probes B and I).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus; O=Octopus; s=O._solver_contract_spread(([1.0,NaN],[1.0]),([1.0,2.0],[1.0])); println(s, " ", s > 1e-10, " ", max(NaN*100, 1e-10))'` prints `NaN false NaN`; the expected comparator answer for a finite-vs-NaN slot is "moved" (`Inf`, as `_probe_deviation` returns).

### LEAD U11-5 [Minor, confidence high] src/contracts/Contracts.jl:3347-3350
Claim: the two undecided buckets are reported as counts only (3390-3399, 3407-3412), so the pass message cannot tell a structurally unperturbable parameter (`tracking_method`, 30 of the 41) from an enum parameter whose legal alternatives were simply never declared — `gaussian_strong_beam.slice_method` (meaning lists `:sqrt_density`, `:equal_area`, `:equal_area_centroid`, ...; `alternatives = ()`) and `thin_strong_beam.virtual_drift` (meaning lists `:hirata` and others; `alternatives = ()`) sit in the bucket unverified with no `inactive` row and no name in any metric; and the `rejected` bucket's label ("whose perturbation the constructor rejected") misattributes map-time throws (`aperture.alive = 1e-3` compiles and fails in the map with `MethodError: objects of type Float64 are not callable`; `aperture.loss_record = 1e-3` fails with a missing `track_particle` method).
Mechanism: `_perturb_candidates` returns `()` for a Symbol without declared alternatives (3162) and the loop pushes the name only to a local vector; `catch` at 3369 swallows every exception type into the same `rejected` outcome. The suite ratchets `unperturbable <= 41` and `rejected <= 23` (`test/runtests.jl:14012-14013`), which pins the SIZE of the blind spot, not its membership. The `misalign_convention` entries of the 7 zero-length kinds are a different case: their schema declares `()` with a meaning that says why, so "unperturbable" is the honest outcome there.
Repro: `probes/U11/probe_a_element_sweep.jl` prints the 41 unperturbable and 23 rejected pairs by name with the exception text of each candidate (`probe_a.log`, sections "SWEPT pairs UNPERTURBABLE" / "REJECTED"); `probes/U11/probe_gh_element_exemptions.jl` section H prints `GaussianStrongBeamSpec.slice_method ... alternatives=()` and `ThinStrongBeamSpec.virtual_drift ... alternatives=()`. Declaring their alternatives should move both into `checked` (or into `inactive` with a reason) and lower the ratchet by two.

### LEAD U11-6 [Minor, confidence high] src/contracts/Contracts.jl:3188
Claim: with `atol = 0.0`, 22 of the 530 "checked" parameters are credited on a movement below 1e-12, twelve of them below 1e-15 — pure roundoff of a structurally inert conjugation (`chromaticity_kick.tilt` 6.5e-19, `thin_accelerating_cavity.tilt` 8.7e-19, `thin_strong_beam.tilt` and `gaussian_strong_beam.tilt` 1.4e-17, `marker.misalign_convention` 4.3e-19, `aperture.{z_offset, x_pitch, y_pitch, misalign_convention, ref_tilt}` 4e-19..1.5e-17, `multipole.curved_order` 2.6e-18, `multipole.k5s` 2.6e-18) — while the exemption policy at 3045-3049 states that such pairs belong in the structural table, not in the sweep's credit; and the additive-first candidate order credits large-magnitude parameters on a sub-physical perturbation because the loop breaks at the first nonzero movement (3375) before the scale-correct `x 1.37` candidate is tried: `thin_rf_cavity.frequency` (4.008e8 Hz) is "checked" by `+0.13 Hz`, a movement of 1.2e-16; `thin_accelerating_cavity.frequency` by 1.8e-15; `multipole.k5` (20000) by 2.8e-17.
Mechanism: `(Float64(current) + 0.13, Float64(current) * 1.37)` at 3188 puts the additive candidate first for every Real, the comment at 3181-3187 motivating the multiplicative one only for SMALL scales; `deviation > contract.atol && break` at 3375 ends the search at the first bit that moves. The defect class is 8 (a pin resting on rounding rather than structure): the evidence that `frequency` reaches the map is one ulp-scale bit from an unphysical perturbation, and would survive, for instance, a map that rounded the frequency to Float32 only by luck. Known to the authors for the aperture rows (comment 2948-2953: "weak but genuine consumption evidence"); the inconsistency is that the same reasoning exempted the marker's seven placement rows but not these.
Repro: `probes/U11/probe_a_element_sweep.jl`, section "SWEPT pairs that moved only at roundoff (0 < dev < 1e-12)" in `probe_a.log` lists the 22 pairs with deviations; running the contract with `atol = 1e-15` is the one-line test of how many "checked" parameters rest on roundoff (expected: the twelve named above become `declared but not consumed`).

### LEAD U11-7 [Minor, confidence med, CROSS-FILE SEAM, out of hypothesis] src/contracts/Contracts.jl:3367-3371 -> src/elements (gaussian_strong_beam, aperture)
Claim: the sweep's rejection log exposes constructor paths that accept an ill-typed value at construction and fail later with an internal `MethodError`: `GaussianStrongBeamSpec(hvoffset = true | 1e-3 | 1)` constructs without complaint and `compile_runtime` then throws `MethodError: no method matching get(::Bool, ::Symbol, ::Symbol)` (measured for `true` and `1e-3`); `ApertureSpec(alive = 1e-3)` compiles and the map throws `objects of type Float64 are not callable`; `ApertureSpec(loss_record = 1e-3)` compiles into `Aperture{Nothing, NonSymplectic6DMap, Float64, Float64}` for which no `track_particle` method exists.
Mechanism: these are the "ill-typed value not validated at the boundary" shape of defect class 5 at the element constructor, surfaced only because the contract's `catch` at 3369 keeps the messages (they are discarded in the shipped run and the pairs land in the anonymous `rejected` count, see U11-5). The contract is right to count them as undecided; the seam is that the owning constructors validate by failing downstream, at compile or track time, with messages that do not name the keyword.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus; O=Octopus; ex=O.example_spec(O.GaussianStrongBeamSpec); p=Dict{Symbol,Any}(O.params(ex)); p[:hvoffset]=true; s=O.GaussianStrongBeamSpec(;p...); println("constructed ", typeof(s)); try O.compile_runtime(s) catch e; println(first(sprint(showerror,e), 80)) end'` prints `constructed ElementSpec{:gaussian_strong_beam}` then `MethodError: no method matching get(::Bool, ::Symbol, ::Symbol)` (expected: an `ArgumentError` naming `hvoffset` at construction); the aperture messages are in `probe_a.log` under `aperture.alive` / `aperture.loss_record`.

### LEAD U11-8 [Minor, confidence high] src/contracts/Contracts.jl:3764-3767
Claim: the `:configuration` branch of `_solver_contract_receipt_carries` — reading the requested value back out of the `:solver_runtime` receipt, which is a dump of the solver object under test (previous audit U4-6's mechanism) — is still present and is a circular acceptance path; it is dormant only because no execution or performance option currently declares `consumer = :solver_runtime`, and nothing guards that.
Mechanism: the execution half (3912-3918, 4027-4031) is the only caller that consults receipts; probe B shows every execution/performance option's consumer is a specialised one (`pic_pair_schedule`, `gaussian_pair_schedule`, `spectral_pair_schedule`, `cuda_pic_algorithm`, `cuda_pic_launch`), and the one `:solver_runtime` execution-category option (`SpectralPoissonSolver.field_precision`) is exempt. A future execution option declared with `consumer = :solver_runtime` would be certified by the dump regardless of whether anything read it, with no tripwire firing. Probe I confirms the `:solver_runtime` receipt is emitted on both backends, so the branch is live code.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus; O=Octopus; struct R; consumer::Symbol; backend; values; end; r=[R(:solver_runtime, O.CUDABackend, (configuration=(cuda_async=false,),))]; println(O._solver_contract_receipt_carries(r, :solver_runtime, :cuda_async, false, O.CUDABackend))'` prints `true` from a receipt that proves only that the value was stored. A schema-level tripwire (no execution-category option may name `:solver_runtime` as consumer) would close it.

### LEAD U11-9 [Minor, confidence high, out of hypothesis] src/contracts/Contracts.jl:2128-2153
Claim: the PIC half of `HighEnergyWeakStrongLimitContract` asserts the proton's luminosity and size but nothing about the infinite-energy electron, so half of the stated claim ("the strong-strong collision reduces to the frozen-source weak-strong kick") is unasserted for PIC — the soft-Gaussian half asserts it (`gaussian_electron_change <= gaussian_atol`, 2133/2150).
Mechanism: `pic_electron` is collided (2128-2130) and never compared with `electron`; the metrics (2142-2147) carry no PIC electron entry. Measured at the contract's own setup the PIC electron's max |change| is 5.4e-20, so the missing assertion would pass; it is a coverage gap, not a failing check.
Repro: `probes/U11/probe_k_wsl_pic_electron.jl` prints `pic electron max|change| = 5.421010862427522e-20 (NOT asserted)` beside the asserted Gaussian value and the contract's six metric keys (no `pic_electron_*`).

### LEAD U11-10 [Minor, confidence med] src/contracts/Contracts.jl:2602
Claim: `length(f) == 14 || continue` drops a malformed PTC row silently; the coverage check at 2622-2626 catches a case with NO rows, not a case that lost some of its five, so a partially corrupted table narrows the comparison without a word (defect class 6).
Mechanism: `worst[name]` is a running maximum over whatever rows survive, and `rows` is reported only as a total; a case keeps its `haskey(worst, name)` after one surviving row. The committed table is uniform today (61 cases x 5 particles, 305 rows of 14 fields, matching the 61 declared specs), so nothing is dropped now. The survey contract's twin (2761) is protected by its per-case `length(entries) != length(rows)` comparison (2777); the PTC contract has no row-count expectation to compare against.
Repro: copy `validation/reference/ptc_madx_5.03.06.tsv` to a temp file, delete one tab from one `drift` row, run `validate(PTCConsistencyContract(path=tmp))`: expected a failure naming the row; actual `:passed` with `metrics[:rows] == 304` (the suite's truncation control at `test/runtests.jl:14274-14286` deletes all five rows of a case, which the coverage check does catch).

## Clean

Hypothesis 1 — the effectiveness contracts detect an ignored option by injection:
- Element contract: the suite's controls are real injections and were read as such — an emptied
  allowlist fails naming `thin_strong_beam.klum` (`test/runtests.jl:14093-14098`), a killing
  aperture probe fails naming `aperture.x_limit` (14113-14119), a broken baseline fails naming
  `quadrupole` (24208-24214); probe A confirms the shipped sweep has 0 ignored, 0 broken,
  0 skipped kinds, 0 stale exemptions, and the 530/41/23/31 counts the pins quote. The
  NaN-aware `_probe_deviation` behaves as its three documented corners say.
- Solver contract: the controls cover a missing probe entry, a missing alternative, and an
  alternative equal to the probe value; the enumeration is derived (`_solver_contract_types()`
  is the swept set, U4-7 closed). Probe B: all 90 (solver, option) rows have an alternative or
  an exemption; no swept alternative equals its baseline; the four CPU baselines are NaN-free.
  Probe I: the device half's self-calibrated floors are 1e-10 (three solvers) and 1.7e-9 (PIC),
  six to seven orders below the algorithmic differences the comment quotes (2e-3, 5e-3), so
  the "must not move" assertion on CUDA is strong on this device; the soft-Gaussian CUDA route is
  bitwise repeatable. `cuda_threads` is consumed (4042-4049, 4074); `_cuda_pic_launch_receipts_carry`
  requires every requested family and refuses an empty request; the `:cuda_pic_launch` receipt
  (`interface.jl:312`) is written where the launch helper READS the resolved family thread count
  — the consumer boundary, as the invariant asks — one step before the kernel launch that uses
  the returned value.
- Exemptions and why: the 38 element rows and 11 solver rows were each read against their
  reason; 26 element rows hold as stated (U11-1 names the 12 that do not); the solver rows'
  reasons (hybrid rejects `:source_slice`/`:quadratic`/non-default `grid_extent`; CUDA-only
  algorithm flags rejected by the hybrid; the two Green-cache ratios observable only in the
  cache history) are consistent with probe B's baseline values (the hybrid's `grid_extent`
  baseline is `:extrema`, the exempt alternative equal to it, as the reason implies).

Hypothesis 2 — the MPI child protocol:
- No claim is read off stdout: the child's results travel in the HDF5 file the parent names
  (`beam1`, `beam2`, `turns`, `values`, `nranks`), written by rank 0 only after a collective
  gather in rank order; stdout carries only the `MPI-PIC-CONTRACT FAIL` marker, which the parent
  uses for the failure tail. Probe J: the parent's capture shape loses nothing (20000/20000
  lines, 3 trials), so even that tail is complete.
- Rank-local vs gathered: `nranks` is the communicator size (not a rank's view) and the parent
  re-checks it against the launched count (1598); the beams are gathered (`_mp_gather_rows`)
  before writing; the luminosity series is read from the task artifact on root — a rank-local
  series would miss the suite's `mpi_2_luminosity_rel_error <= 1e-12` pin by a factor ~2, so
  the passing pin is evidence it is global. The child's own `_mp_nranks() == spec.ranks` refusal
  (36-37) is evaluated identically on every rank, so it cannot desynchronise them.
- A rank that dies: measured (probe C) the launcher returns in 1.3 s after `exit(1)` and 3.4 s
  after an uncaught exception, exit code 1 — because MPI.jl's `atexit` hook calls `MPI.Finalize`
  only when the exit code is 0 (`environment.jl:138-142`), the dying rank really exits and the
  launcher aborts its peer, exactly the posture `docs/design/multi_process_policy.md:316-320`
  describes. The extension-missing refusal (child 19-20) runs before MPI is initialised, so it
  cannot hang either. A rank that HANGS (rather than dies) is bounded only by the contract's
  `timeout` (1800 s default; the suite passes no shorter one), which the docstring states.
- Temp-directory hygiene: `out` and the task artifact live in a fresh `mktempdir()` per leg, so
  no stale file from an earlier run can be read as a result.
- `_mpi_pic_contract_spec` round-trips every word `_mpi_pic_contract_args` emits (checked
  field by field; the suite pins the same at 24266-24271).

Hypothesis 3 — skipped-as-passed:
- `ContractResult(:skipped, ...)` sets `passed = false` (37-41); every `:skipped` return in the
  region names what did not run (PTC/survey: the missing table and its generator; solver: the
  CUDA-only option count and the reason). The suite asserts `status === :passed` strictly for
  PTC (14261, 24672), survey (14295), the element contract (13955), the physics contracts
  (30605-30633), and the MPI contract under a launcher (23798); it accepts `:skipped` for the
  solver contract only when `!CUDA_TESTS_ACTIVE` (14511) and asserts the no-launcher MPI result
  IS `:skipped` and `!passed` (24259-24262). The pass messages name their counts
  ("$(checked) checked, ... neither group is verified"; "$(checked) on CPU, $(cuda_options_checked)
  on CUDA, $(cuda_checked) launch surfaces"). The one bypass found is U11-2.

Other checks in the region, sound with the evidence:
- `_wsl_weakstrong_reference!` passes ten positional arguments matching
  `_slice_slice_gaussian_kick!(rep, idx, moments2, center2, kbb_slice, klum_slice, min_sigma,
  virtual_drift, longitudinal_kick::Val, compute_luminosity::Bool)` (`gaussian.jl:110-114`);
  the source slice weight multiplies both the kick and the luminosity scale; the RNG is saved and
  restored around the fixed seed. The contract passes at 5.4e-20 electron change (probe K). Note
  the "reference" is assembled from the solver's own kernel, so this contract checks the
  orchestration (slicing, freezing, ordering), as its docstring says; the kick physics is
  evidenced elsewhere.
- `_coherent_fractional_tune`: Hann window, interior-bin argmax, parabolic refinement,
  `(k - 1 + delta)/n` is the rfft bin frequency; NaN or out-of-band lambda fails loudly
  (`<=` chains are false on NaN); RNG restored in `finally`.
- PTC: natural-number version sort (`[5,9,0] < [5,10]`); 61 declared specs = 61 table cases
  (hand-copied in both the contract and the generator, but the comparison itself is the
  tripwire: a drifted parameter shows as a deviation, a missing case as `untested`); the
  column mapping `f[3:8]` -> initial, `f[9:14]` -> final matches the table header
  `x0 px0 y0 py0 z0 pz0 x1 px1 y1 py1 z1 pz1`; the `:skipped` path names the generator.
- Survey: `f[5..12]` = `L s_end X Y Z theta phi psi` matches the table header; the per-case
  row-count comparison makes a dropped row loud; `s[i] + Li - send` on O(10) m at 1e-12 is two
  orders above Float64 eps at that scale; the measured max deviation pin is `<= 1e-12`.
- Element sweep mechanics: `Bool` is tested before `Integer`; placement parameters with integer
  defaults get the 1e-3 physical candidate first; `nothing` defaults offer `(true, false, 1e-3, 1)`;
  the coupled `beta0`/`gamma0` move stays on `beta0^2 = (gamma0^2-1)/gamma0^2`; the baseline
  `catch` reports a broken kind as a failure; `CARRIED` precedes `inactive` so a duplicated
  `:name` row would read stale, as documented.
- Solver sweep mechanics: the companion-setting baseline is rebuilt with the companion
  (`interaction_grid = :source_slice` with `grid_extent = :extrema`); options rejecting their
  alternative, throwing in collision, or lacking a CPU backend are each counted and named; the
  device-half set is "CUDA-only OR both-backend execution/performance", the derivation the
  suite re-computes at 14519-14533.
- Descriptions for `ElementParameterEffectivenessContract`, `PTCConsistencyContract` and
  `MADXSurveyConsistencyContract` exist (`src/registry/Registry.jl:291-295`); the other
  region contracts define theirs inline.

Style only (no lead): the `SolverOptionEffectivenessContract` docstring signature (3576-3577)
omits the `seed` field; `metrics[:cuda_status]` exists only on the skip path, so a GPU run has
no `:cuda_status` key; the PTC loop rebinds the loop variable `line` to the spec list inside the
body (2610), legal but confusing.

## Unchecked

- The `PublicConfigurationEffectivenessContract` and `KnobEffectivenessContract` named in
  hypothesis 1 live in the first half (lines 211-921) and belong to another unit; not read beyond
  their struct docstrings.
- The parent side of the MPI contract (1476-1668) was read as reference context only; no lead
  is claimed there. The suite's launcher-driven run of the MPI contract (`test/runtests.jl:23794`)
  was not executed in this session (several minutes of launched processes plus the CUDA leg);
  its protocol was judged from the code and from probe C's minimal reproduction of the rank-death
  mechanism under the same MPICH ABI, not under the contract's own child.
- The full `validate(SolverOptionEffectivenessContract())` with the device active was not run
  end to end (the suite does; this session ran its CPU half twice under a hidden device and its
  device-half calibration once); U11-3's device-side consequence is reasoned, its CPU-side
  consequence measured.
- The cross-file receipt emitters named by the execution options' consumers
  (`pic_pair_schedule`, `gaussian_pair_schedule`, `spectral_pair_schedule`, `cuda_pic_algorithm`)
  were not read; whether each is emitted at the consumer boundary rather than at the storing
  site is outside the region (the one emitter read, `_cuda_pic_threads`, is at the boundary).
- The physics of the PTC/survey fixtures (the 61 specs and 9 lines) was not re-derived; the
  contracts' comparison logic was audited, the committed numbers taken as the external reference
  they are.
