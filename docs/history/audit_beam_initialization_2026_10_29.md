# Bounded beam initialization: implementation and neighbour audit

## Executive summary and scope

**Completed 2026-10-29:** the final four-thread full gate passed with CUDA
active: **444 testsets, 158,198 passed assertions, zero failures or errors**.
Two pre-existing expected-broken misalignment checks remain; two profiling-only
drivers are excluded by the suite. Real MPI initialization at 1/2/4 ranks and
the full MPI seam passed. The final receipt below names every exclusion and
links the durable testset and script measurements.

Starting tree: `8459b30872e48d49d71b0efc30c1d48fef6ae4cc`. The owner requested
an investigation, reviewed design, implementation, and verification of bounded
uniform random beams and deterministic Cartesian grids. The inventory found
only Gaussian public initialization; `octopus_uniform01` already supplied the
uniform primitive. The [design](../design/beam_initialization.md) was written
before code changes and reviewed independently by two agents.

The implementation adds `distribution=:uniform` to the existing count-taking
`Beam` interface and a no-count grid overload with point counts or coordinate
spacing. Both construct physical `(x,px,y,py,z,pz)` coordinates. Gaussian is
still the count-taking default. The beam representation and tracking kernels
are unchanged. Bounds, inactive options, endpoints, precision, global population,
RNG side effects, and MPI sharding are explicitly checked.

This is a targeted campaign audit, not a repository-wide review. The owning
source, constructor callers, RNG/storage helpers, configuration integration,
new tests, and their Gaussian/MPI neighbours were reviewed. The accelerator
maps and solver numerics were exercised by existing checks, not rederived.
Performance optimization, alternative coordinate distributions, distributed
generation without a whole-beam temporary, and new tracking physics were out
of scope. No throughput claim is made.

## Coverage and traceability

| Region | Depth and provenance | Verification |
|---|---|---|
| `src/beam/Beam.jl`: sampling helpers, constructor family, `_initialize_beam`, bounded helpers, sharding | Implementer read and independent neighbour review | Gaussian fingerprint, support/statistics, Cartesian oracle, rejection/side-effect tests, CPU/CUDA parity |
| `src/math/counter_rng.jl`: uniform draw/stream interfaces | Inventory agent and implementer focused read; unchanged | Both RNG methods, seed and stream changes, repeatability |
| `src/policies/Policies.jl`: activation and `_mp_shard_range` | Implementer focused read; unchanged | Pre-draw refusal, one-rank parity, MPI child cases |
| `src/contracts/Contracts.jl`: public configuration helper and integration | Configuration agent implementation, implementer full diff read | Positive checks, dropped-receipt and corrupted-coordinate negative controls |
| `src/tasks/strongstrong/interface.jl`: metadata validator block | Configuration agent implementation, implementer full diff read | Constructor-default receipts, contextual grid default, metadata drift controls |
| `test/runtests.jl`: new tests and existing Beam neighbours | Test agent implementation, implementer read and execution | Standalone extracted tests, source tripwires, gate |
| `test/mpi_seam_check.jl`: new initialization block | Test agent implementation, implementer full diff read | Real launcher checks through the existing seam runner |
| `docs/design/beam_initialization.md` | Implementer draft and two independent design reviews | Resolved review comments, source/docstring comparison |

All review agents were instructed not to run Julia. The implementer serialized
all runs; no gate or launcher overlapped another session-owned Julia process.
The independent neighbour unit's
[report](audit_beam_initialization_2026_10_29_unit_reports/U1_report.md)
distinguishes source inspection from the implementer's executions.

## Design review corrections

Both reviewers required explicit contextual defaults: Gaussian with `N`, grid
without `N`. The schema names both; the validator observes both constructors.
Other accepted corrections were comparison of inactive requests before
Float32 narrowing, strict checks of generated grid points, endpoint containment
after affine rounding, refusal of underflowed positive spacing, and separate
requested/resolved receipt fields. These were incorporated before implementation.

## Confirmed findings and fixes

### BI-1: MPI refusal after sampling and success recording

The first implementation inherited the Gaussian constructor's late communicator
validation. A `MultiProcessExecutionPolicy(ranks=2)` in a no-MPI process threw
only after generating the beam; uniform initialization claimed its stream and
both uniform/grid modes left success receipts.

The implementer reproduced this on the intermediate implementation: **3 failed
and 3 passed assertions** over the uniform/grid cases. The failed properties
were an unheld explicit stream and absence of `:beam_initialization` receipts.
The fix resolves the communicator and chunk-aligned shard range after keyword
validation but before drawing, and takes the shard before the success receipt.
This order also protects the Gaussian neighbour. The committed refusal test
covers all three distribution branches; it passed in the final targeted run.

Reproduction shape (the suite now asserts the corrected result):

```julia
audit = ExecutionAudit()
rid = Octopus._unheld_rng_id(Octopus.next_rng_id!() + 2_000_000)
try
    with_execution_audit(audit) do
        Beam(16, MultiProcessExecutionPolicy(ranks=2);
             distribution=:uniform, lower=ntuple(_ -> 0.0, 6),
             upper=ntuple(_ -> 1.0, 6), rng_id=rid)
    end
catch err
    @assert err isa ArgumentError
end
@assert !Octopus._rng_id_held(rid)
@assert isempty(filter(r -> r.consumer === :beam_initialization,
                       execution_receipts(audit)))
```

### BI-2: invalid uniform RNG activated a policy before refusal

A test policy counted activations. `rng=:invalid` produced `MethodError` after
one activation: **2 failed assertions**, expecting `ArgumentError` and zero
activations. Uniform initialization now requires an `AbstractRNG` or `nothing`
before activation. The focused regression passed **2/2**; its permanent suite
version also verifies a valid RNG activates the policy, **4/4**.
Errors thrown inside a user-defined valid RNG remain runtime errors. Gaussian
explicit-RNG behavior is preserved; this change does not certify arbitrary
third-party RNG implementations.

### BI-3: boxed allocation-closure capture

The extracted existing `Core.Box` sweep reported `_bounded_beam` as its sole new
offender: **4 passed, 1 failed**. Both branches assigned `n`, and the grid
allocation closure captured it. A separate, once-assigned `grid_n` removed the
box. The unmodified sweep then passed **5/5**, with no allowlist expansion.

The independent reviewer reread the fixes and their Gaussian/RNG/upload
neighbours and reported no new concrete defect. No tolerance was loosened.

## Numerical rules checked

Uniform support is the specified physical box. For normalized uniform draws,
`E[u]=1/2`, `Var(u)=1/12`; the tests at `N=16384` allow eight sampling standard
errors: `8/sqrt(12N)` for the mean, `8/sqrt(180N)` for the variance, and
`8/(12sqrt(N))` for independent-axis covariance. They also check support
coverage, one-bound-at-a-time effectiveness, one-particle prefix behavior,
seed/stream changes, and fixed axes. No sample standardization is applied.

Grid tests enumerate literal axis values independently with `Iterators.product`,
including unequal axis counts. They verify both endpoints, order, singleton
axes, physical population, decimal spacing, adjacent representable bounds,
duplicate-point refusal, nondividing steps, precision collapse, and integer
storage overflow. CPU/CUDA construction is exact because the host arrays are
the uploaded arrays. The small three-slice, two-turn weak-strong tracking check
uses a per-coordinate scale tolerance of `1e-10`, since the analytic kick's
device special functions have a different rounding route.

## Targeted execution record

Environment: Julia 1.12.4, four Julia threads, NVIDIA RTX 4500 Ada Generation;
CUDA was asserted functional in the targeted runner. Tests were extracted from
the committed suite, starting at `random Beam refuses non-AbstractFloat on BOTH
entry points` and ending before `ForwardDiff differentiates the lattice`, into
a runner with `using Octopus, Test, Random` and `CUDA_TESTS_ACTIVE` asserted true.

| Testset | Passed |
|---|---:|
| non-AbstractFloat refusal, both entry points | 6 |
| Gaussian size and coupling-alias refusals | 16 |
| refused Gaussian construction preserves stream state | 34 |
| BeamParams typed defaults | 8 |
| Gaussian CPU/CUDA initialization identity | 8 |
| bounded uniform sampling | 209 |
| grid population and Cartesian product | 78 |
| bounded invalid/inactive requests and MPI refusals | 273 |
| backend/policy semantics and Gaussian default | 34 |
| uniform/grid weak-strong tracking, CPU and CUDA | 20 |
| metadata/effectiveness drift controls | 16 |
| explicit uniform RNG validation order | 4 |
| **Total, no skips** | **706** |

This run followed BI-1 and BI-2; BI-3 subsequently changed only the local
variable captured by grid allocation. The source checks after BI-3 passed:
`Core.Box` **5/5**, detached docstrings **11/11**,
`validate_configuration_metadata()` true, regenerated snapshot byte-unchanged.
`validate(PublicConfigurationEffectivenessContract())` passed with CUDA active:
seven cases/seven receipts/all five options on each backend; CPU worker sweep
1/2/4, CPU worker coordinate error 0, CUDA coordinate error
`1.0842021724855044e-19`. The runner invoked the metadata validator before the
contract and observed the existing RNG-registry warning for explicit beam id 1
following an auto-assigned BPM id 1; it was not suppressed.

### Gaussian compatibility fingerprint

Twelve before/after SHA-256 digests matched exactly. Each case contains 257
particles, six coordinate arrays in canonical order, serialized as native
float bytes. Baseline was captured before constructor edits on the starting
tree named above. Reproduce in a fresh Julia process with `using Octopus,
Random, SHA`, then:

```julia
for T in (Float32, Float64), method in (:philox, :splitmix), variant in (:default, :optics, :explicit)
    set_global_rng!(seed=123456789, method=method)
    opts = variant === :optics ? (beta=(0.8, 0.072, 90.0), alpha=(0.3, -0.2, 0.1),
        emit=(1e-8, 1e-9, 4e-5), initial_offset=(1e-4, 2e-5, -1e-5, 3e-5, 1e-3, 2e-4)) :
        variant === :explicit ? (rng=MersenneTwister(410),) : (;)
    b = Beam(257, CPUThreadsExecutionPolicy(), T; rng_id=variant === :explicit ? 0 : 901, opts...)
    bytes = reduce(vcat, (collect(reinterpret(UInt8, a)) for a in coordinate_arrays(b)))
    println(T, " ", method, " ", variant, " ", bytes2hex(sha256(bytes)))
end
```

| Type | Method | Variant | SHA-256, before and after |
|---|---|---|---|
| Float32 | philox | default | fb84217d66fd0d551dbeb28ea264cd36ab7cf971d71ccb20496e2dbeffc1e636 |
| Float32 | philox | optics | df37713a38a482014f8a6be5efe461f5b96159bdaab6065afc3f3759f8e03e5a |
| Float32 | philox | explicit | 645d166756dad64fae3cb45cb585fa847414bbf811d0e13405091574fd4ede70 |
| Float32 | splitmix | default | 739411e76db11a5d75008eb77e15f7da73bed4c874a32970c12950c3fb16225b |
| Float32 | splitmix | optics | 1744a03769977a371ae909ef943849af18df45d43120a7bf9d21b88e96244f3b |
| Float32 | splitmix | explicit | 645d166756dad64fae3cb45cb585fa847414bbf811d0e13405091574fd4ede70 |
| Float64 | philox | default | 83cf2d4bc379775e4938906217f88419190f1c401e350d6bde277df791b28fdc |
| Float64 | philox | optics | 260e6e5bc556722d163b6c611ce0cd3b5049097cb88267b92c5bba6a64b369d2 |
| Float64 | philox | explicit | 5c1b4735f3e23d234b4ac9232dc04e47f1f703a253b326e974c0100b53394f89 |
| Float64 | splitmix | default | 432776af139e587689ab8f212d0d0cc094cab5b6486ea61a7930692eb4d7955f |
| Float64 | splitmix | optics | 6ff36050d39f13100b15b5abbc8fa23fb8f039464aaffad8e492b6915bfc2d85 |
| Float64 | splitmix | explicit | 5c1b4735f3e23d234b4ac9232dc04e47f1f703a253b326e974c0100b53394f89 |

## Remaining verification

The tracking backend-consistency script and the four-thread full gate are
required after these targeted checks. Their completion receipts are appended
below when measured; the targeted results above do not claim either gate ran.
The MPI child has six initialization cases per rank, checked against the CPU
whole-beam reference; its execution is certified only by the launcher results.

## Tracking backend-consistency receipt

Executed after the final source change, with CUDA required:

```bash
OCTOPUS_REQUIRE_GPU_CONTRACT=1 julia --project=. --threads=4 validation/tracking_backend_consistency.jl
```

Exit status **0**; the script reached `tracking backend consistency validation
complete`. The recorded configuration was 10,000 macroparticles, two turns
for the composed line, Philox seed 123456789, `atol=rtol=1e-10`. No backend
check was skipped.

| Check | Recorded result |
|---|---|
| CPU repeatability | Bitwise, maximum absolute difference 0 |
| Composed line, CPU/CUDA | Maximum absolute difference `8.196568423990414e-17`; global relative difference `3.794018931393513e-15`; maximum tolerance ratio `8.176724527899806e-7`; no losses |
| Accelerating cavity, one pass | Maximum absolute difference `6.830473686658678e-18`; global relative difference `6.830463022928981e-16` |
| Aperture-loss case | Bitwise CPU/CUDA coordinates and loss flags; 6,725 of 10,000 lost on both; no one-sided losses |
| Per-kind registry cases | All 34 instances within their declared rounding classes on CPU/CPU and CPU/CUDA |

The temporary transcript is
`result/beam_initialization_tracking_validation_20261029.log`; the command,
configuration, tolerances, and measurements above are the durable evidence.

## Full-gate execution status

The first four-thread full-gate invocation was interrupted with its tool
session during the isolated script-mode dependency compilation. It reported
188 completed testsets: 115,940 passed assertions, no failures or errors, and
two expected-broken assertions in `Misalignment maps`. It had reached
`Longitudinal conventions convert exactly` (220/220) but did not finish the
script-mode check or the remaining suite. This is an incomplete run, not a
passing gate. Process inspection confirmed its Julia children had stopped
before the replacement was launched.

The replacement uses the same command, under a detached supervisor with a
pseudo-terminal and core dumps enabled:

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
```

A first background restart lost its logging supervisor; its exact process
group was stopped and confirmed empty before another launch. That attempt has
no counted test results. The repaired supervisor runs in its own session
(`setsid`), uses flushed `script` output, and was observed alive independently
with an advancing transcript.

The repaired run's transcript is
`result/beam_initialization_full_gate_20261029_detached.log`; the supervisor
wrote exit status **1** to the adjacent `.exit` file. No source or test changes
were made between these invocations. The run reached 245 testsets, with
120,290 passed assertions, one failure, no errors, and the two expected-broken
misalignment assertions. All bounded-initialization testsets, the isolated
script-mode check, five clean examples and three developer harnesses passed.
The failure and correction follow. This run is not a passing gate and did not
reach the real MPI launcher checks.

### BI-4: the contract's stream reservation omitted its consumer label

The existing `One rng_id policy: zero assigns a fresh stream everywhere, ids
are UInt64, the registry warns on an explicit claim of an auto-assigned id
and on cross-class sharing` testset passed its 35 runtime assertions but
failed its source census: the newly added effectiveness helper called
`next_rng_id!()` without `consumer=:beam` while choosing an unheld probe id.
The source check requires every claim/reservation outside the registry to
name its existing consumer class.

An extracted, unchanged copy of that testset reproduced **35 passed / 1
failed** before the correction. Adding `consumer=:beam` to the contract's
reservation made the same testset pass **36/36**. No assertion, tolerance,
initialization algorithm, or stream-id arithmetic changed.

The configuration reviewer re-read the Gaussian/uniform claim paths, grid
RNG refusal, metadata's local RNG, sibling contract reservations, and all
radiation, turn-rule and BPM claim sites. A source census using the suite's
filter found **10 labelled claim/reservation lines**, no unlabelled calls,
and exactly the four existing consumer classes. No further concrete defect
was found. The original targeted source sweep missed this existing testset;
the full gate exposed the omission.

A second read-only integration review covered the testsets after that failure:
their receipt readers filter by consumer, MPI/strong-strong fixtures construct
beams outside tracking audits, and later public-configuration assertions do not
assume an exact metric-key set that excludes initialization. The MPI child
checks local coordinates alongside global population/count and one successful
initialization receipt. No further concrete defect or detached docstring was
found; these inspections do not substitute for the pending launcher runs.

A four-thread fast checkpoint now precedes the final full-gate retry, with
sequential execution under one detached supervisor. The full gate starts only
if the fast checkpoint exits zero. Transcripts use
`result/beam_initialization_fast_20261029_final.log` and
`result/beam_initialization_full_gate_20261029_final.log`; their adjacent
`.exit` files carry each exit status. The fast checkpoint stopped at the
fixture-description finding below, so that supervisor did not start its full
gate.

### BI-5: a test policy entered the registry without a description

The fast checkpoint reached 268 testsets: 121,646 passed assertions, two
failures, no errors, and three broken/skipped assertions. The failures were
the unchanged `Every registry type describes itself` assertions: the private
`_BoundedBeamProbePolicy` fixture is an `AbstractExecutionPolicy` subtype and
therefore participates in live reflection, including the description check.

The extracted fixture and unchanged registry test reproduced **10 passed / 2
failed**. Giving the test-only policy its `description` method made that check
pass **12/12**. Its activation-order test passed **4/4**, the adjacent runtime
objects check passed **4/4**, and configuration metadata validation passed in
the same process. Production code and registry acceptance rules were unchanged.

The neighbour walk located all registry/snapshot readers in the suite. The
on-disk snapshot comparisons precede the fixture definition; later membership
queries are compatible with a described test type. Configuration validation
filters concrete types to the Octopus module. No missing policy schema or
snapshot update is required for this Main-module test fixture.

That incomplete fast run explicitly skipped these sections:

- Element parameter effectiveness.
- Solver option effectiveness.
- Script mode picks up the ForwardDiff rules.
- ForwardDiff differentiates the lattice.
- Curved frame x transverse field: every routing is a gradient.
- Every example script runs against the current interface.
- Turn modulation: the one-particle probe, two-rank arm.

It also recorded the full-lane-only public-configuration effectiveness skip
inside `Turn modulation: the RF cavity by the same wrap`, alongside the two
existing expected-broken misalignment assertions. Tests after the registry
failure did not run. This is a failed checkpoint, not a gate claim.

After BI-5, the new MPI initialization block is extracted unchanged into a
standalone child and run at 1/2/4 ranks using the first full run's test
environment (`MPI 0.20.29`, `MPICH_jll 5.0.1+0`, current checkout). The driver
reads one receipt file per rank and requires every child to exit zero. A fresh
full gate follows only if these checks pass; its transcript is the final-log
path above. The known failing registry/RNG assertions remain unchanged.

## Real MPI initialization receipt

The extracted MPI initialization block completed successfully at 1, 2 and 4
ranks, two Julia threads per rank. All seven ranks delivered their receipt
files and each reported `cases=6 OK`: Float32/Float64 crossed with uniform,
grid point counts and grid spacing. This is **42 rank-local case executions**;
the parent process passed **24/24** launcher/receipt assertions. The three
launches took 33.2 seconds in the driver; this is a validation runtime, not a
performance benchmark. Exit status **0** is recorded in
`result/beam_initialization_mpi_20261029.exit`.

Uniform cases used 257 global macroparticles and physical `npart=7e10`;
both grid forms resolved to 90 global macroparticles. Local coordinates were
bitwise equal to each rank's expected contiguous slice of the whole CPU beam.
Physical population and initialization-receipt counts remained global. No
case was skipped. This closes the new feature's real-MPI check independently
of the broader MPI seam regressions still owed by the final full gate, which
started immediately afterward.

## Final full-gate receipt and closure

The final run used Julia 1.12.4 and the repository's full-lane command:

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
```

It started **2026-10-29 17:48:38 -04:00** and finished **19:01:30 -04:00**
(72 minutes 52 seconds). The process printed `Testing Octopus tests passed`
and exited **0**. CUDA coverage ran, with four default CPU threads; this was
the full lane, not the fast checkpoint. No implementation or test changes
followed this run; the final receipts and closure links were then added.

The [testset receipt table](audit_beam_initialization_2026_10_29_gate.tsv)
contains all **444** reported testsets and their counts/times: **158,198 pass,
0 fail, 0 error, 2 broken**. The
[script receipt table](audit_beam_initialization_2026_10_29_scripts.tsv)
records **27 successful subprocess exits**: five clean examples, three
developer harnesses and all 19 CUDA-arm validation/profiling scripts. The
CUDA script arm passed 208 assertions and recorded 412.1 seconds wall time;
its four concurrent subprocess slots are owned by that suite arm. No
independent Julia run overlapped the gate.

The final run covered both previously failing integration checks unchanged:
the RNG-policy test passed 36/36, and registry descriptions passed 12/12. The
new initialization testsets passed, as did configuration metadata, source
tripwires and the public-configuration effectiveness validation. The full MPI
launcher seam passed **1,712 assertions** at 1/2/4 ranks, including the new
initialization block. The generated registry snapshot remained unchanged.

### Explicit exclusions and limits

- `Misalignment maps`: two existing `@test_broken` assertions for invalid
  inactive `misalign_convention` values (`:middle` and `"madx"`) without a
  placement error. These are known failures, not passes, and were not changed.
- `profiling/cuda_device_profile.jl`: excluded by the suite because it is a
  `CUDA.@profile` fork frozen at the paper's production point (F-201).
- `profiling/profile_strong_strong_cuda.jl`: excluded by the suite because it
  wraps the strong-strong harness in `CUDA.@profile`; that harness is exercised
  through the benchmark scripts.

There were no full-lane skips or unavailable-resource skips. CPU tests ran in
this CUDA-active gate; a separate GPU-disabled gate was not run. The earlier
interrupted/failed runs and fast-lane exclusions above do not claim completion.
This work makes no throughput claim and retains the existing transient
whole-beam-per-rank MPI initialization strategy.

The temporary complete transcript is
`result/beam_initialization_full_gate_20261029_final.log`, with exit status in
the adjacent `.exit` file. The committed testset/script tables, configuration,
commands, tolerances and measurements in this record preserve the evidence
without depending on that ignored directory. The committed MPI child and
full-gate launcher reproduce the new MPI cases; the standalone probe only
narrowed execution to that unchanged block.

| Closed work | State | Evidence |
|---|---|---|
| Bounded beam initialization | Closed, 2026-10-29 | Reviewed design; uniform/grid implementation; unchanged Gaussian fingerprints; CPU/CUDA and real MPI checks; neighbour findings BI-1 through BI-5 corrected; full gate passed. |

No open finding remains from this feature campaign. The existing misalignment
findings and profiling exclusions remain outside its scope.
