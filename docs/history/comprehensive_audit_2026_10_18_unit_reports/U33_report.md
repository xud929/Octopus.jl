# U33: test/runtests.jl lines 16038-19586 (BeamLine, loss accounting, observers, thread invariance, metadata validators, run artifact, turn modulation, rng_id registry)

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Julia 1.12.4,
CUDA active (RTX 4500 Ada). Every claim below is a LEAD, not a finding.

## Region

`test/runtests.jl` lines 16038-19586, 3549 lines, 36 top-level `@testset`s (two of them behind
`_lane_gate`: "Curved frame x transverse field: every routing is a gradient" at 16738-16866 and
"Every example script runs against the current interface" at 17589-17704), plus the helper type
definitions at 16378-16414 (`FailAtTurnAction`, `LedgerPeekObserver`, `FinalizeFlagObserver`,
`ThrowingFinalizeObserver`, `ReseedGlobalRNGAction`).

Testsets in the region, by first line: 16038 BeamLine composes; 16164 Loss accounting; 16271 Every
walker over the line; 16416 Observer finalizers / BPM noise / planner; 16534 Crashed execute! loss
artifacts; 16584 ParamMeta alternatives; 16616 BPMObserver artifact capacity; 16657 Slicing
degenerate conventions + spectral charge tripwire; 16739 Curved frame sweep (lane-gated); 16868
Straight solenoids; 16915 Core.Box sweep; 17015 CPU thread-count invariance; 17443 collide
allocation; 17523 CUDA equal_area histogram; 17569 Spectral solve/eval split; 17590 Example scripts
(lane-gated); 17706 Every export documented; 17720 OCTOPUS_MP refusal; 17753 Observer schema keys;
17787 Precompile overwrite guard; 17808 Metadata validator declarations; 17951 Validator tree walks;
17994 perturbs_timing agreement; 18016 perturbs_timing child control; 18048 hidden-solver child
control; 18094 Run artifact luminosity channel; 18432 Turn-modulation provenance; 18644 Neighbour
audit 2026-10-16 pins; 18861 Seed-drift warning + equal-digest check; 19046 rng_id policy; 19187
Tasks/turn-modulation follow-ups (a)-(f).

## Provenance

READ line by line: 16038-19586 complete (in chunks 16038-16416, 16416-16740, 16738-17015,
17015-17260, 17260-17530, 17523-17810, 17808-18095, 18094-18300, 18300-18432, 18432-18650,
18644-18860, 18861-19045, 19046-19186, 19187-19400, 19400-19586). Also read for context: the suite
header `test/runtests.jl` 1-30 (lane mechanism) and 60-135 (abort-at-first-failure caveat, the
`CUDA_TESTS_ACTIVE` definition at 132) and footer 32020-32035; `src/tasks/strongstrong/spectral.jl`
576-578 and 604-607, 664; `src/tasks/strongstrong/pic_cuda.jl` 5693-5718; `src/tasks/RunArtifact.jl`
150-175 and 434-449; `src/tasks/Tasks.jl` 1-12 and 1455-1500; `src/track/strong_beam_track.jl`
85-130 and 225-245; `src/knowledge/Knowledge.jl` 468-480 (`register_element_meta!`);
`test/examples/crab_cavity_noise.jl` 440-446; `docs/design/testing_lanes.md` sections 1 and 3;
`docs/comprehensive_audit.md` Phase 9 (489-516); the prior report
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U18_report.md` lines 35-70 (LEAD U18-1),
and the history grep dating `_initialize_moment_file!`'s removal
(`docs/history/todo_ledger_archive.md:88`, `docs/history/neighbour_audit_2026_08_11.md:90`).

EXECUTED (scratch `result/comprehensive_audit_2026_10_18/probes/U33/`):

1. `probe_corebox_allowlist.jl` (log `probe_corebox_allowlist.log`): re-runs the Core.Box sweep of
   16915-17013 with hit accounting. Positive control (a function assigning a captured local inside
   a closure) detected = true; negative control (Ref) = false; the box appears as
   `_5 = Core.Box()`. `nmethods swept = 4034`; boxed methods found = 8; offenders = none;
   allowlist hits: GaussianStrongBeam 1, _activate_symbolics_adapter! 1,
   _contract_default_initial_rep 1, read_beam_coordinates 1, validate 1,
   **_initialize_moment_file! 0**.
2. `probe_octopus_mp_crab.sh` (logs `crab_mp_1.log`, `crab_mp_0.log`, summary
   `probe_octopus_mp_crab.out`): `test/examples/crab_cavity_noise.jl` under `OCTOPUS_MP=1` and
   `OCTOPUS_MP=0` with `OCTOPUS_TURNS=1 OCTOPUS_N_MACRO=64`: exit 1 both times, the error names
   `OCTOPUS_USE_MPI` (refusal at `crab_cavity_noise.jl:442`).
3. `probe_ws_lum_turn0.jl` (log `probe_ws_lum_turn0.log`): the (4b) fixture of 18215-18225.
   Channel turns `[0]`, value `85189.5021952265`; particle after 3 turns at x = 0.2298 m,
   px = 0.0775 (the thin-beam kick at 1e-3 offset with kbb = 1e-4, sigma = 1e-3 is 74 mrad);
   one-turn-per-execute! with the particle reset each time records
   `[85189.5021952265, 85189.5021952265, 85189.5021952265]` at turns 0, 1, 2;
   `_thin_strong_beam_track` at the initial point returns lum = 85189.5021952265.
4. `probe_spectral_split_circular.jl` (log `probe_spectral_split_circular.log`): the body of
   "Spectral solve/eval split is exact" on the clean tree (pin holds, Ex0[1] = -212.729...,
   max|Ex0| = 2110.06), then with `Octopus._spectral_field_grid_eval` redefined to return an
   all-zero field: **pin holds = true, max|Ex0| = 0.0**. Same process: the undocumented-binding
   message on Julia 1.12.4 contains "No documentation found" (true); methods named `validate` in
   `Contracts.jl` blanketed by one allowlist key: 14.

The suite's own testsets were not re-run through the stage runner (see Unchecked).

## Leads

### LEAD U33-1 [Minor, confidence high] test/runtests.jl:17569
Claim: The testset "Spectral solve/eval split is exact" is circular — it compares `_spectral_field_grid!` against `_spectral_field_grid_solve!` + `_spectral_field_grid_eval`, and the former is defined as exactly that composition, so the equality cannot fail for any content of either half.
Mechanism: `src/tasks/strongstrong/spectral.jl:576-578` defines `_spectral_field_grid!(ws, sx, sy, fx, fy, Lx, Ly) = (_spectral_field_grid_solve!(ws, sx, sy, Lx, Ly); _spectral_field_grid_eval(ws.Exg, ws.Eyg, ws.Nx, ws.Ny, fx, fy, Lx, Ly))`. Both sides of `@test Ex1 == Ex0` therefore run the same two functions on the same data; the only property the pin can see is that `_spectral_field_grid_eval` is deterministic and indifferent to `copy(ws2.Exg)` versus `ws.Exg`. The comment says it "pins the seam: a stored mesh must evaluate bit-identically to the monolithic solve-and-eval", but no monolithic route exists any more (the pre-refactor capture the comment mentions was never committed as a reference). Hypothesis 2 (circular test) and Phase 9's rule: a check that consults what it validates proves nothing. Measured: with the eval replaced by an all-zero field the pin still passes.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U33/probe_spectral_split_circular.jl` → `injected eval defect (all-zero field): pin holds = true  max|Ex0| = 0.0` and `VERDICT: CIRCULAR`. A structural pin would compare the stored-mesh evaluation against an independent reference (the direct per-particle spectral field sum, or a committed capture of the pre-split route).

### LEAD U33-2 [Minor, confidence high] test/runtests.jl:16931
Claim: The Core.Box sweep's hand-maintained allowlist carries an entry for a method that no longer exists (`("_initialize_moment_file!", "BeamObservers.jl")`, removed with the legacy moment observers on 2026-08-11), and the testset has no tripwire for an unused or stale entry and no in-suite positive control for its detector, so the list can rot and the instrument can go blind without a failing test.
Mechanism: The sweep (16982-17005) only accumulates `offenders` (boxed methods NOT in `allowed`) and asserts `isempty(offenders)` plus `nmethods >= 2450`. An allowlist key is never checked to be hit; `_initialize_moment_file!` has no definition anywhere under `src/` (`grep -rn _initialize_moment_file! src` → nothing; `docs/history/todo_ledger_archive.md:88` records its removal "before 3a65c7e", 2026-08-11), so a future function of that name in `BeamObservers.jl` carrying a concurrent box would be exempt by a stale argument ("serial file I/O and initialisation"). Likewise `expr_has_box` is never fed a known box inside the suite: if Julia's lowering changed how a `Core.Box` appears, every method would read as clean, `offenders` would stay empty, and the test would pass with the five live boxes undetected. The `(clean_name(m), file)` key still blankets every method named `validate` in `Contracts.jl` (14 today, measured) under one argument, as the prior audit's LEAD U18-1 recorded (24 then); only the enumeration half of U18-1 was repaired (the `scan_modules` loop at 16963-16973 and the raised floor). Hypothesis 3: a sweep whose instrument is never validated against a known defect, and a hand-copied list without a coverage tripwire (AGENTS.md Invariants).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U33/probe_corebox_allowlist.jl` → `allowlist entries NEVER hit (stale or instrument blind): [("_initialize_moment_file!", "BeamObservers.jl")]`, `nmethods swept = 4034`, positive control `true`. Also `grep -rn '_initialize_moment_file!' /cfs/ad/dxu/Library/Julia/Octopus/src` → no output. The fix shape: assert every allowlist key was hit at least once (a removed box must leave the list), and add an in-suite boxed control function the detector must flag.

### LEAD U33-3 [Minor, confidence high] test/runtests.jl:17736
Claim: "The harnesses refuse the retired OCTOPUS_MP spelling" hand-lists two harnesses (`weak_strong_tracking.jl`, `strong_strong_tracking.jl`) while `test/examples/` holds three, so the third harness's refusal — which exists — is never verified by the suite, although the sibling testset at 17624 derives the very same set from the directory.
Mechanism: The testset's `for harness in ("weak_strong_tracking.jl", "strong_strong_tracking.jl")` is a copied case list; `crab_cavity_noise.jl` documents and reads `OCTOPUS_USE_MPI`/`OCTOPUS_RANKS` (header lines 19-61) and refuses `OCTOPUS_MP` at line 442, but nothing in the suite would notice if that refusal were dropped or mis-spelled, which is exactly the "non-default request silently ignored" class the testset's own comment names. The examples testset (17624) already derives `harnesses` from `readdir(joinpath(root, "test", "examples"))` with a `>= 3` floor; the refusal testset did not follow when the third harness landed (2026-10-14). Hypothesis 3 (derived-vs-copied case lists).
Repro: `ls /cfs/ad/dxu/Library/Julia/Octopus/test/examples/*.jl | wc -l` → 3, against the two names at 17736; `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U33/probe_octopus_mp_crab.sh` → `exit=1` and one `OCTOPUS_USE_MPI` line for both `OCTOPUS_MP=1` and `OCTOPUS_MP=0` (the third harness refuses today, unverified by the suite). Derive the list from the directory as 17624 does.

### LEAD U33-4 [Minor, confidence med] test/runtests.jl:18201
Claim: The crash-recovery pin captures the logs of the torn-tail reopen into `logs_t2b` and never asserts anything about them, so the test neither pins that the truncation is silent nor that it warns; the truncation in the source is silent, which the reader of the test cannot tell.
Mechanism: `logs_t2b, _ = Test.collect_test_logs() do ... end` (18201-18205) is followed only by `read(f["luminosity"]["ip"]["turns"]) == [0, 1, 2, 3]`; `logs_t2b` is dead. `_ra_truncate_group!` (`src/tasks/RunArtifact.jl:439-449`) shrinks `turns`/`values` with `HDF5.set_extent_dims` and emits no `@warn`/`@info`, so rows past the cursor are dropped with no signal beyond the docstring sentence at RunArtifact.jl:159-161. Whether a torn tail SHOULD be loud is a source-side decision outside this region (AGENTS.md: dropped rows "warn, throw, or are documented as inert" — here documented); the region's defect is a capture that executes but checks nothing (hypothesis 1, "a check that never executes", in the shape of an unread result), and the swallowed logs hide any future warning or error-log regression on this path. Cross-file seam noted for the auditor: RunArtifact.jl's torn-tail truncation has no receipt.
Repro: `grep -n 'logs_t2b' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` → exactly one line (the assignment); `sed -n '439,449p' /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/RunArtifact.jl` → no `@warn` in `_ra_truncate_group!`. Either assert `isempty(logs_t2b)` (pinning documented silence) or assert the warning once the source emits one.

### LEAD U33-5 [Minor, confidence low] test/runtests.jl:16433 (out-of-hypothesis; cross-file seam)
Claim: Nine testsets in the region mutate the process-wide RNG (`set_global_rng!` at 16433 to seed 424242 under the ambient method; seed 5/`:philox` at 18103, 18609, 18827; `0x5eed`/`:philox` at 18649, 19042, 19184, 19229, 19583) and none restores the state it found, so the seed and method any later testset inherits depend on which of these ran — an order coupling the suite header itself names as the way the U3-2 and U23-13 pins "failed the suite while passing alone".
Mechanism: `set_global_rng!` is global state; the region's testsets each set it before use (none reads an inherited seed — checked for every RNG-consuming testset in the region), so the region is self-consistent, but the state LEFT at 19586 is `0x5eed`/`:philox` only if the last testset ran, and 424242 with the pre-16416 method if the file aborted after 16416 (top-level testsets abort the file at their first failure, header lines 72-79). Any later testset that pins a noise value, a Beam sample, or a `SpectralNoise` table name under an assumed ambient seed would be order-dependent. Not verified beyond the region (a seam); confidence low because no dependent testset was identified.
Repro: `grep -n 'set_global_rng!' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | awk -F: '$1>=16038 && $1<=19586'` → 9 sites, none paired with a saved-and-restored prior state; `grep -c 'set_global_rng!' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` for the whole-file picture the auditor owns.

## Clean

Checked and found sound, with the evidence:

- **Hypothesis 1, CUDA gates skip visibly.** Every `if CUDA_TESTS_ACTIVE` in the region has an
  `else @test_skip` branch: 16522/16529, 16670/16680, 17531/17565, 19334/19343. `CUDA_TESTS_ACTIVE`
  is `Octopus._HAS_CUDA && Octopus.CUDA.functional()` (line 132). No CUDA body reports passed
  without a device.
- **Hypothesis 1, lane gates.** Both `_lane_gate` sections open at 16738 and 17589 and close with
  the matching `end # _lane_gate(...)` at 16866 and 17704; `_lane_gate` pushes the name to
  `_LANE_SKIPPED` and prints `LANE SKIP` (lines 23-28), and the footer banner lists them
  (32026-32034). `docs/design/testing_lanes.md` does not hand-list gate names, so there is no copied
  list to drift against. No `@testset` body in the region sits behind a false condition; the only
  conditional bodies are the CUDA gates above and `if maximum(counts) > 1` at 17284, which is true
  at every thread count >= 1 because `counts = unique((1, 2, nthreads))` always contains 2.
- **Hypothesis 1, aborting tolerances.** The region has no wall-clock gate tighter than 0.5 s
  (16489, 1000x the measured worst sample) and its allocation gates carry documented headroom
  (17513-17515 ~3x; 18825 fixed 448 B vs bound 40 kB; 19532-19533 bound 400 kB vs 97.8/103.6 kB
  measured; 19557 256 B vs 0-32 B). The planner cost pin is on allocation (16485), the
  machine-independent witness, as its comment argues.
- **Hypothesis 2, negative controls executed.** The curved-frame sweep (16765-16768) reproduces the
  recorded defect's analytic residual L*h*Ks0 = 2.5e-3 to rtol 1e-6 before sweeping; the validator
  controls at 17858-17870, 17888-17898, 17920-17934 inject liars and assert the named errors; the
  two child-process controls (18016-18046, 18048-18092) assert their premise (`HIDDEN-FROM-DIRECT
  true`) before the refusal; the observer-schema control (17768-17784) injects `not_a_field` and
  restores; the spectral charge tripwires (16725, 16734) are positive controls of their warnings
  (their negative controls live at 29789-29812, outside this region).
- **Hypothesis 2, the (4b) "turn 0 alone" pin is physics, not a recording defect** (18215-18225).
  Measured (probe 3): the fixture's 1e-3 offset against sigma = 1e-3 with kbb = 1e-4 gives a 74 mrad
  kick; after one 1 m drift the particle is at x = 0.075 m and the Gaussian overlap underflows to
  0, which the positive filter at `Tasks.jl:1483` drops. Resetting the particle each turn records
  the same 85189.5021952265 at turns 0, 1, 2, so `last_luminosity` is written every turn (CPU
  fold at `strong_beam_track.jl:124`).
- **Hypothesis 2, the CUDA histogram oracle is not circular** (17523-17567): the kernel hand-inlines
  `_slice_bin` (`pic_cuda.jl:5700-5707`, `unsafe_trunc(Int, floor(d))` + clamp) while the oracle
  calls the CPU `_slice_bin`; the comparison is a genuine cross-backend check on four sample sets
  including quantized ties and a dead-flag mask.
- **Hypothesis 3, bitwise pins that are structural.** 16060/16068 (a BeamLine tracks as its tuple:
  the line expands to the same runtime entries); 16907 and 16912 (`curved=false` stores h = 0.0 and
  is the h = 0 kernel); 17815-17829 (named-strength thin constructors build field-identical
  runtimes); 16361/16363 (`1e-4 + 0.25*1e-3` — the multipliers 0.25 and 0.5 are dyadic, so the
  product is exact and the single rounding is the same with or without fma); 18947-18948 (replayed
  WhiteNoise draws against the recorded series: same pure function, same inputs). Thread-count
  equality (17079-17081, 17105-17107, 17151, 17192, 17270-17272, 17436-17438) rests on fixed chunk
  grids and data-indexed folds, which the code comments trace to U5-1/2, U6-5, U18-2, and the
  block pins the routing predicate's worker-blindness (17176-17177, 17185) and the partition's
  exact tiling (17218-17224) rather than assuming them.
- **Hypothesis 3, derived case lists with tripwires.** 16846-16864 derives the curvature x field
  kind set from `registered_element_specs()` and checks both directions; 17616-17628 derives
  example scripts from `example_catalog()` and harnesses from `readdir`, with population floors;
  18752-18754 derives the `RunArtifact` keyword list from `Base.kwarg_decl` against the schema;
  19165-19183 derives rng_id claim sites from a `src/` walk with a `>= 4` floor and a fixed
  consumer-class set.
- **Anti-vacuity on recorded configuration (invariant 11).** 17281-17291 and 17316-17320 read
  `:pic_pair_schedule` receipts (`pair_workers`, `widest_batch`, `requested` vs `batch_mode`);
  17386-17390 pins "the policy, not the pool"; 19329-19331 and 19349-19355 pin receipt presence and
  absence around refusals; 17695-17700 requires the harness to have WRITTEN under
  `OCTOPUS_RESULT_DIR`.
- **Instruments verified by probe on this Julia.** `expr_has_box` detects a textbook box and not a
  `Ref` (probe 1); the export-documentation string "No documentation found" matches Julia 1.12.4's
  message (probe 4).
- **Registry cleanup in the metadata testset** (17871-17877, 17899-17904, 17935-17946) covers the
  three tables `register_element_meta!` writes (`Knowledge.jl:468-480`: BY_SPEC_TYPE, BY_FRIENDLY_TYPE
  when a constructor is given, BY_KIND) plus `REGISTERED_ELEMENT_SPECS`, and restores the overwritten
  `DriftSpec` friendly binding; `validate_element_metadata().passed` is re-asserted after each.
- **Style only.** `Test.collect_test_logs` swallows logs without assertion at 18171, 18426, 18486 and
  18564 (18486 is explained in a comment as the second-live-writer warning); `logs_t2b` is the one
  dead capture (LEAD U33-4). The comment at 17759 cites `BPMObserver.jl:412 and :416`, a line
  reference that rots. Several comments quote measurements with no harness in the region (16505-16506
  160.26 ms → 0.112 ms; 17025 3.06 s vs 3.10 s; 17120-17121; 17468-17473 the d0fb3f2 table): these are
  documentation claims (defect class 14), reported here as style since each pin's live bound is
  independent of the quoted number.

## Unchecked

- I did not re-run the region's testsets through the stage runner; the heavyweight ones
  (thread-count invariance at n = 15000/30000, the allocation pins, the example-script subprocesses,
  the ~1 min precompile guard, the two child-process validator controls) were read, not executed.
  Their current green status is taken from the repository's CI records, not measured here.
- The CUDA-only branches (16523-16527 `_bpm_centroid` on device, 16671-16676 degenerate CUDA slicing,
  17532-17563 the histogram kernel, 19335-19341 the :fused-on-CUDA refusal) were read but not
  executed; the machine has a GPU, but no probe of mine covered them.
- The quoted historical numbers in comments (listed under Style) were not reproduced.
- Whether any testset AFTER 19586 depends on the RNG state this region leaves behind (LEAD U33-5)
  was not checked; it is outside the region and is flagged as a seam.
- The torn-tail truncation's loudness policy (LEAD U33-4) is a RunArtifact.jl decision outside the
  region; only the test-side dead capture is claimed.
