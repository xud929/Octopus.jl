# The strong beam as one element, stage 2: deprecate and keep (2026-11-22)

Stage 2 of [`../design/strong_beam_element.md`](../design/strong_beam_element.md)
(S5 active, S6, S7), decided with the owner on 2026-11-22 after stage 1
([record](strong_beam_element_2026_11_22.md), pushed as 9d5c6ee): the old
spellings of the strong beam stay in the code for existing scripts and warn
once per process; the suite and the validation scripts spell the strong beam
in the recommended form; one compatibility testset pins the old spellings;
the weak-strong tracking's physics and performance are measured unchanged on
CPU threads, MPI and CUDA. The CI run of the stage-1 push (9d5c6ee):
run 483 (id 44999125149), in progress while this record was written (started
2026-11-22T07:38Z); its outcome is recorded in the next ledger touch.

## 1 What changed

- **Deprecated spellings, kept (S7).** The `ThinStrongBeamSpec` constructor
  (typed and untyped), the `GaussianStrongBeamSpec` constructor keywords
  `hvoffset`, `slice_hoffset`/`slice_voffset`/`slice_pxoffset`/`slice_pyoffset`
  and `mean` each warn once per process through `@warn ... maxlog = 1`
  (`_strong_beam_deprecated`, one table `_STRONG_BEAM_DEPRECATIONS` naming
  the replacement: `GaussianStrongBeamSpec(...; ns = 1)`, `offset_slices!` or
  `offset_slices`, `center`/`angle`). Nothing else about them changes; the
  thin kind, its runtime `ThinStrongBeam` (the Gaussian element's per-slice
  kernel), its CPU and wrapped CUDA routes, rounding class, metadata and
  contracts remain. `thin =` is not a warned spelling: it is the stored form's
  keyword, which the validators (`ctor(; params(example)...)`) and every
  `ElementSpec` round trip pass back.
- **The validators run silent.** `validate_element_metadata` and
  `validate(ElementParameterEffectivenessContract())` run their bodies under
  the `ScopedValue` `_SILENCE_DEPRECATIONS` (`_silence_deprecations(f)`,
  `src/knowledge/Knowledge.jl`): they build the deprecated kind through its
  friendly constructor like every other kind, and a warning addressed to
  nobody would be noise. Internal callers (the Gaussian constructor building
  its kernel, the symplecticity contract's probe, the effectiveness probe,
  the registry example) build the kernel through `_thin_strong_beam_spec`.
- **`mean` acts in every case (S5).** Until this batch a `mean` without a
  6×6 covariance was stored and read by nothing (probe on 9d5c6ee:
  `thin.xo == 0.0` with `mean[1] = 1e-6`,
  `result/gates/linopt/sb2_perf/probe_unfixed_9d5c6ee.txt`). The compile now
  reads it on every route through one helper, `_thin_with_center`, which the
  6×6 route also uses; its inert sixth component stays refused by name
  (F-124).
- **A 6×6 covariance alone describes the strong beam (S6).** With no
  `beta`/`sigma`, 4×4 or point beside it, the kernel's stored transverse
  covariance is the 6×6's transverse block, which the compile replaces by
  each slice's conditional covariance as for every 6×6. Before, the
  self-contained form refused it ("requires the strong beam's transverse
  optics"), so the thin= form's pair of a 4×4 kernel beside a 6×6 had no
  spelling.
- **`ns = 1` needs no `sigz`.** Every slicing rule puts one slice at `z = 0`
  with weight 1 (measured for all seven, `_gaussian_slices` on 9d5c6ee);
  `:equal_width` keeps requiring its width, and more slices the length.
- **`offset_slices!` reads `sigz` from a stored 6×6** as the compile does
  (`_stored_sigz`, one reader for both). Stage-1 defect found by the probe:
  the function refused "requires sigz" for a spec that compiled.
- **The suite.** Every physics test that used a strong beam as a building
  block spells it `GaussianStrongBeamSpec(...; ns = 1)` or the self-contained
  sliced form (33 testsets); tests of the kernel's own runtime (its virtual
  drifts, the coupled covariance and longitudinal limits, the symplecticity of
  the three drifts, the chromatic composite, the soft-Gaussian equivalence,
  the CUDA coupled parity, the wrapped CUDA route, the rounding classes, the
  thread-count pin of the thin carrier, the stored-form precision rule) build
  it through `Octopus._thin_strong_beam_spec`; the hvoffset validation test
  goes through `offset_slices!`. The stage-1 testset keeps the recommended
  form (S1-S3, S6); the new testset "Deprecated strong-beam spellings stay
  alive" pins each table entry (built twice, one warning naming the spelling
  and its replacement; silent in the scope; the validator silent), the thin
  kind's kernel and tracking identity with `ns = 1` (kick and luminosity,
  CPU and CUDA), the constructor offsets against the functions, and `mean`
  against `center`/`angle` with and without a 6×6 (the regression that fails
  on 9d5c6ee), S5 and F-124.
- **Validation scripts.** `strong_beam_kick_fingerprint.jl` (the two "thin"
  cases through the internal builder; "gsb 6x6 covariance hirata" spells its
  `mean` as `center`/`angle`, "gsb hirata hvoffset" its waveform through
  `offset_slices`), `gaussian_slicing_convergence.jl`,
  `tracking_task_turn_update.jl` and `tracking_context_policy_consistency.jl`
  (their centroid ramps write `element.thin.xo`),
  `near_round_gaussian_transition.jl`, and the two thin instances of
  `tracking_backend_consistency.jl` (the kind's own routes, internal builder).
- **Docs.** The design note (S5-S7, the stage list), the thin and Gaussian
  docstrings, the metadata meanings and construction help of both kinds (the
  thin kind's description says DEPRECATED), `docs/public_api.md`, the
  `LinearOptics` consumer list, the todo row, this record, and a lesson in
  `docs/experiences.md`. The registry snapshot is unchanged (regenerated and
  compared).

## 2 Verification

All on the stage-2 working tree (9d5c6ee plus the 22 paths of this batch),
2026-11-22 02:45-03:21 EST, Julia 1.12.4, acnlinj4 (CUDA active):

- The unfixed behaviours, shown on 9d5c6ee before the change
  (`result/gates/linopt/sb2_perf/probe_unfixed_9d5c6ee.txt`): `mean` without a
  6×6 compiled to `thin.xo = 0.0, thin.pxo = 0.0`; a 6×6 alone was refused
  ("requires the strong beam's transverse optics"); `ns = 1` without `sigz`
  was refused ("requires sigz"); `offset_slices` on a 6×6 spec without `sigz`
  was refused the same way while the spec compiled; `ThinStrongBeamSpec`
  constructed silently. On the stage-2 tree every one of these is the
  recorded opposite (`/tmp` probe, repeated by the compatibility and stage-1
  testsets).
- `validate_element_metadata()` passed with no error and no deprecation
  warning logged (one pre-existing `lumped_radiation compiles to the identity`
  warning from a probe); `validate_configuration_metadata()` returned `true`.
- Extracted testsets (`/tmp/linopt/run_extracted.jl`, 4 threads):
  42 blocks in two passes (03:00-03:12 EST, and the eight blocks that name
  file-level helpers re-run with those helpers defined, 03:17-03:20):
  2573 + 268 assertions passed, 0 failed. Among them the compatibility testset
  52/52 with the CUDA arm active, the stage-1 testset 61/61, the LinearOptics
  consumers 114, the slicing rules 470, the one precision rule 652, the
  rounding classes 204, the element effectiveness contract 80 (under the
  silencing scope, no deprecation warning), the Core.Box, documented-exports,
  detached-docstring and snapshot sweeps, the examples catalogue 52 and the
  architecture check 49. Left to the gate, each stopped by a fixture the
  extraction cannot define rather than by a strong-beam assertion: the two
  `ForwardDiff` blocks (the chromatic composite, the elliptical kick's
  derivative), the artifact row-cursor block (`_FixTFailingVec`), the
  strong-strong luminosity-channel block (`LedgerPeekObserver`), the last
  assertion of the coupled-covariance block (`numerical_potential_hessian`;
  14 of 15 passed) and two of the one_turn_matrix block
  (`_OTMUnimplementedMethod`; 17 of 19 passed).
- `validation/tracking_backend_consistency.jl` with
  `OCTOPUS_REQUIRE_GPU_CONTRACT=1`: exit 0, every instance "Tracking backends
  agree within tolerance", 36 per-kind rounding-class instances within their
  declared classes on CPU/CPU and CPU/GPU; the thin kind's own instances
  (bare and misaligned, through the internal builder) measured as before
  (px 411.75 and 366.0 ulps of scale against the declared 2048).
- `validation/strong_beam_kick_fingerprint.jl`: exit 0, no warning, all ten
  cases' fused and elementwise digests equal, and every digest identical to
  the stage-1 run's (`/tmp/linopt/b5/fingerprint.log`, 01:02 EST), among them
  "gsb 6x6 covariance hirata" = 0xb0954daa5a1f7bb1 with its `mean` respelled
  as `center`/`angle` (the recorded value of
  `weak_strong_allocation_2026_09_04.md`) and "gsb hirata hvoffset" =
  0x3ca913c3d4dc0d11 with its waveform through `offset_slices`.
- `validation/gaussian_slicing_convergence.jl` (defaults): exit 0, the
  `<-- GaussianStrongBeamSpec default` lines at |hirata - exact| = 2.928e-4
  and 3.879e-5 (the theory note's numbers), no warning.
- `validation/tracking_task_turn_update.jl`,
  `validation/tracking_context_policy_consistency.jl` (CPU and CUDA) and
  `validation/near_round_gaussian_transition.jl`: each "passed", exit 0, with
  the ramps writing `element.thin.xo`.
- Both shipped examples at their default configuration
  (`examples/weak_strong_tracking.jl`, `examples/crab_cavity_noise.jl`, on
  this CUDA machine): exit 0, no warning printed; their crab waveform now
  goes through `offset_slices!` when the input asks for one (as do the two
  harnesses' and the CPU benchmark driver's), which the defaults do not.
- `write_registry_snapshot` regenerated: identical to the tracked
  `docs/registry_snapshot.md` (no export changed; the examples' objects print
  the same).

## 3 Physics and performance before and after

The owner's condition for stage 2: the weak-strong tracking keeps the same
physics and performance for every execution policy. Instrument:
`profiling/crab_cavity_noise_backends.jl harness=weak_strong n_macro=1000000
turns=200 arms=threads:16,mpi:4x4,cuda` (the weak-strong harness
`test/examples/weak_strong_tracking.jl` at its shipped physics, one child
process per arm, SHA-256 digests of the moment table and the luminosity
series, per-turn wall over turns 21-200), run twice on this 128-core node
with nothing else heavy running: before, on 9d5c6ee clean (tag `sb2_before`,
02:38-02:42 EST), and after, on this batch's tree (9d5c6ee plus 22 modified
paths; tag `sb2_after`, 03:13-03:17 EST). Rows and child logs:
`result/gates/linopt/sb2_perf/benchmark_sb2_{before,after}.tsv` (git-ignored;
the numbers that matter are here).

| arm | moments digest | luminosity digest | ms/turn before (p10, p90) | ms/turn after (p10, p90) | after/before |
|---|---|---|---|---|---|
| threads:16 | identical | identical | 236.2 (211.0, 246.6) | 233.9 (210.9, 247.2) | 0.99 |
| mpi:4x4 | identical | identical | 193.5 (167.6, 199.3) | 168.1 (161.9, 174.7) | 0.87 |
| cuda | identical | identical | 27.88 (27.86, 27.93) | 27.87 (27.84, 27.89) | 1.00 |

Physics: every arm's moment table and luminosity series are bit-identical
before and after (`eps_y_last` 1.0090553236910245e-9 on threads,
...0127e-9 on MPI, ...009e-9 on CUDA; `lumi_mean` 1.0653827275077659e30 and
...657e30 on CUDA, in both runs). Performance: no arm slower; the MPI arm's
after-median sits at the before-run's p10, run-to-run spread of that arm
(the 4-rank exchange), not an effect of the batch, which changes nothing the
kernels execute: the deprecations live in the constructors, `_thin_with_center`
runs at compile, and the harness passes no deprecated spelling.

## 4 The gate

The batch changes a public constructor, element metadata, a contract's entry
point, validation scripts and the suite (the matrix: full, CUDA active; the
kernels are unchanged). The full gate ran on this batch's working tree after
this record was written and the tree was committed unchanged; its numbers are
in the commit message.

## 5 Ledger

- `docs/todo.md`: the strong-beam row names stages 1 and 2 as implemented;
  nothing scheduled.
- `docs/README.md`: this record and the design note's entry.
- `docs/experiences.md`: "A deprecation keeps the code, warns once, and keeps
  one test".
