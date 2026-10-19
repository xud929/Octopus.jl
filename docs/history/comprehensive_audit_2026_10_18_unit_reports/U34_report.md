# U34: test/runtests.jl lines 19587-22525 — run-artifact record/lock/receipt testsets, the turn-modulation probe arms, the August-audit tripwires, the multi-process passthrough testsets

Comprehensive audit 2026-10-18, reading unit U34. Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at
commit 24e8683, read-only. Every claim below is a LEAD, not a finding.

## Region

`test/runtests.jl` lines 19587-22525 (2939 lines; the file has 32035). The region holds, in order:

| lines | `@testset` |
|---|---|
| 19587-19702 | The strong-strong physics line and observer tuples are cached per compilation and cost nothing per execute! |
| 19704-20258 | The run artifact records the realised turn modulation (parts a-j, CUDA arm gated) |
| 20260-20498 | Run artifact exclusion and seed provenance: the sidecar lock, lock-aware readers, the ledger's rng columns (child-process holder) |
| 20500-20994 | Run artifact receipts and slots: resolved output receipts for both task kinds, derived vocabularies, the non-HDF5 append refusal, a partial slot reported by the reader |
| 20996-21150 | Turn modulation: the one-particle probe verifies the loop per harmonic (CPU, CUDA, two-rank MPI arms) |
| 21152-21240 | Turn modulation: the strong-strong window and receipt |
| 21242-21335 | Solver equality is by configuration |
| 21337-21560 | Nested lines have length, reflection keeps state, folded sugar is rejected everywhere |
| 21562-21597 | Unknown spec keys warn, placement keys bind, set_param! bumps the epoch |
| 21600-21620 | Every register-heavy kick launch goes through the thread cap (source scan) |
| 21622-21660 | The Linear6D symplecticity validator accepts every numeric type it advertises |
| 21662-21682 | The standalone theory script's constants match the framework's |
| 21684-21741 | The near-round Gauss-Legendre reference has not drifted from its twin |
| 21743-21825 | No docstring is detached by comment lines (plus the foreign-binding half) |
| 21827-21872 | The documented configuration-status vocabulary is the real one |
| 21874-21884 | The Runtime Objects section is complete |
| 21886-21912 | Every registry type describes itself |
| 21914-21950 | The placeholder and deprecated policies actually run |
| 21952-22052 | The multi-process policy composes the CPU policy, and its seam is the identity at one rank |
| 22054-22080 | The rank shard is a whole number of reduction chunks |
| 22082-22124 | A sharded run keys its random streams on the global particle index |
| 22126-22142 | A beam built under the multi-process policy is the beam it composes |
| 22144-22380 | A strong-strong task under the multi-process policy is the task it composes (shard scope, :funneled tripwire, spawned-worker half) |
| 22382-22435 | A spawned worker on the driver's own thread is still refused (child at --threads=4,0) |
| 22437-22525 | A PIC task under the multi-process policy is the task it composes (14 variants, dataflow vs batched) |

## Provenance

READ line by line, in ten contiguous chunks covering every line: 19587-19880, 19881-20160,
20161-20440, 20441-20700, 20701-21000, 21001-21300, 21301-21600, 21601-21900, 21901-22200,
22201-22525. Read for mechanism only (outside the region, not audited): `test/runtests.jl` 1-80
(the lane preamble and its "prefer `else @test_skip`" rule) and 8556-8586 (the suite's
`transition_reference`); `src/tasks/strongstrong/pic_cuda.jl` 55-80 (`_cuda_launch_capped!`);
`src/tasks/strongstrong/spectral_cuda.jl` 646-715; `src/elements/floor_plan.jl` 100-246
(`survey`, `_survey_walk!`, `_girder_design_frames`); `src/registry/Registry.jl` 22-31 and the two
instrument functions `registry_types_without_description`,
`runtime_object_types_missing_from_snapshot`; grep hits in `src/elements/turn_modulated.jl` (the
`N + i` slot convention, 635 and 789). References consulted: `docs/design/testing_lanes.md`
sections 3-4; the previous audit's `LEAD_INDEX.md` rows U17-U20 and U12-9/U12-17 (both FIXED there;
the leads below about their tripwires' anti-vacuity are new).

EXECUTED (scratch: `result/comprehensive_audit_2026_10_18/probes/U34/`, logs beside the scripts):

- `probe_A.jl` -> `probe_A.log`: A1 (configuration-status regex) and A2 (docstring scanner fed
  seven planted shapes). Its third part, a sweep of `src/` with a backtracking regex, overflowed
  PCRE's stack and the process was killed by me; the sweep was redone regex-free in A2b.
- `probe_A2.jl` -> `probe_A2.log`: A2b (regex-free blind-shape sweep of `src/`: 0 sites), A3
  (near-round twin magnitudes: values 3.3e2 to 1.13e8, eps 5.7e-14 to 1.5e-8, worst difference
  0.0 = 0 ulp), A4 (both registry instruments detect a planted defect; the suite's anti-vacuity
  line evaluates `true == true` with `description(AbstractExecutionPolicy) == ""`).
- `probe_B.jl` -> `probe_B.log`: B1 (moments reader keys: 7 of 8 are vectors, `:s` is a scalar),
  B2 (TurnTable replay slot-insensitive: replay(1) == replay(2) == replay(4); with a WhiteNoise
  strength rule only slot 4 reproduces the realised offsets, 1.5e-16 vs >= 1.5e-2 at slots 1-3,
  and the recorded series matches slot 4 only), B3 (the PIC variants under a collecting logger:
  exactly one warning kind, the `:node` mesh drop, 1 per policy on `:node`, 0 on the other 26 runs).
- Read-only greps on `src/` for the kick-cap lead: `_cuda_launch_capped!` call sites per file
  (pic_cuda.jl 13, gaussian_pic_cuda.jl 4, spectral_cuda.jl 0); raw `CUDA.@cuda` launches of the
  spectral interp-scatter (kick) kernels: 4; `threads = 256` hardcoded at spectral_cuda.jl:665
  inside `_cuda_spectral_collide_transverse!` (header at 646).

Nothing in the repository was modified; no git command was run.

## Leads

### LEAD U34-1 [Moderate, confidence high] test/runtests.jl:21843
Claim: The configuration-status testset's comment promises two checks ("require that every DECLARED status is actually constructed somewhere, and that nothing constructs a status the constant does not declare") that do not exist, and the regex instrument it built for them cannot see one of the six statuses.
Mechanism: `found` (the regex-captured statuses, 21831-21839) is consumed only by two negative membership tests (`:library_managed ∉ found`, `:inactive ∉ found`); there is no `declared ⊆ found` and no `found ∩ statuses ⊆ declared`. Measured (probe A1): `declared ⊆ found` is false because `:inherited` is never captured by `ConfigurationEntry\([^)]*?,\s*(:[a-z_]+)\s*,` although its literal appears in `src/`, so the promised positive check would fail today for an instrument reason nobody noticed; the "every declared status is constructed" property is currently guarded by nothing (defect classes 1 and 13). The `live` half (21861-21871) covers only five policy/solver objects, not the task or element reports, so a status constructed only by `configuration_report(task, ...)` is outside it too.
Repro: `grep -c "issubset(declared, found)\|declared ⊆ found" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` prints 0; `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U34/probe_A.jl` prints `declared ⊆ found : false` and `declared \ found : [:inherited]`.

### LEAD U34-2 [Moderate, confidence med] test/runtests.jl:21638
Claim: "Every register-heavy kick launch goes through the thread cap" checks a narrower property than its title: no `CUDA.@cuda` line containing the substring "kick" in two hand-listed files; the spectral solver's kick kernels live in a third file, carry no "kick" in their names, and are launched raw with a hardcoded thread count.
Mechanism: the file list `("pic_cuda.jl", "gaussian_pic_cuda.jl")` is a hand copy (class 2) and the filter is `occursin("kick", lowercase(line))` on the same line as `CUDA.@cuda` (a launch whose kernel name wraps to the next line is invisible too). `src/tasks/strongstrong/spectral_cuda.jl` launches `_cuda_spectral_interp_scatter_kernel!` (705, 710) and `_cuda_spectral_interp_scatter_6d_kernel!` (742, 766) — the beam-beam kick of the spectral solver — with `threads = 256` fixed at line 665, through no `_cuda_launch_capped!` (0 call sites in that file against 13 and 4 in the scanned ones). The test passes while the property it names does not hold for one of the three CUDA solver files. Cross-file seam for the auditor (out of region, not measured): whether 256 is launchable for those kernels on every device the policy accepts (class 4, hardcoded launch shape; the cap helper exists precisely because register-heavy kick kernels cap below the request).
Repro: `grep -n "CUDA.@cuda" /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/spectral_cuda.jl | grep -c interp_scatter` prints 4; `grep -c "_cuda_launch_capped!" /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/spectral_cuda.jl` prints 0; `grep -n 'for file in ("pic_cuda.jl", "gaussian_pic_cuda.jl")' /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` shows the two-file list.

### LEAD U34-3 [Minor, confidence high] test/runtests.jl:21904
Claim: The anti-vacuity assertion of "Every registry type describes itself" is a tautology (`isempty(x) == isempty(x)`), and the sibling anti-vacuity of "The Runtime Objects section is complete" (21883) only asserts the universe is non-empty; neither shows its instrument reporting a missing entry, although both instruments can.
Mechanism: line 21904-21905 compares `isempty(Octopus.description(Octopus.AbstractExecutionPolicy))` with the identical expression, so it is `true` for every possible `description` (measured: `true`, with the description being `""`); the comment above it claims "The tripwire must be able to fail, or it is decoration". Line 21883, `!isempty(_subtypes_recursive(AbstractTrackOp))`, cannot fail on a `runtime_object_types_missing_from_snapshot` that returns `[]` unconditionally. Probe A4 shows the cheap real control: both functions accept a `reg::OctopusRegistry`, and a doctored registry (an `Int` planted into `:solvers`; `elements[2:end]`) makes them report `(:solvers, Int64)` and `[CrabDispersion]` respectively (class 13: an instrument never fed a known defect).
Repro: `grep -n -A1 "isempty(Octopus.description(Octopus.AbstractExecutionPolicy)) ==" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` prints both sides identical; `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U34/probe_A2.jl` section A4 prints `instrument detects a planted defect: true` twice.

### LEAD U34-4 [Minor, confidence high] test/runtests.jl:21762
Claim: The detached-docstring scanner misses two definition shapes that Julia confirms leave a docstring unattached (`Base.`-qualified short-form definitions and `where`-clause short-forms), plus block docstrings closing on a text line and plain global assignments; the suite never fed it a known defect.
Mechanism: the target test at 21787-21788 is `^(function|const|macro|struct|abstract type|mutable struct|@\w+)\b` or `^[A-Za-z_][A-Za-z0-9_!]*\(.*\)\s*=`; a dot in the name (`Base.show(io, x) = ...`) and a `where {T}` between `)` and `=` both fail the second pattern, and `closes` at 21770-21771 does not recognise `text"""` as a closing line. Measured (probe A2): 2 of 7 planted shapes detected; for the qualified and `where` shapes `Base.Docs.meta` of a scratch module is empty, i.e. the docstring is genuinely lost. The foreign-binding half (21806-21825) names `Base.read`, `Base.repeat`, `Base.reverse`, `Base.setproperty!` as extended in this package, so the qualified shape is in live use. Today `src/` has 0 sites in the blind shapes (probe A2b), so this is instrument coverage, not a present defect.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U34/probe_A.jl` section A2 prints `missed_qualified_shortform detected: false` and `missed_where_shortform detected: false` with `Julia attached a docstring ...: false` for both.

### LEAD U34-5 [Minor, confidence med] test/runtests.jl:21740
Claim: The near-round twin pin `@test worst <= 1.0e-18`, described as "agree to round-off, not merely to a physics tolerance", is a bitwise pin in disguise: at the compared magnitudes 1e-18 is 4 to 10 orders below one ulp.
Mechanism: `transition_reference` returns kicks and derivatives of magnitude 3.3e2 to 1.13e8 on the testset's grid (probe A3), where `eps` is 5.7e-14 to 1.5e-8; the only value of `worst` that satisfies the pin is 0.0, which is what both verbatim copies produce today. The testset's stated purpose (a correction to one copy not reaching the other; the precedent was a 1e-9 relative CODATA drift) is served equally by a relative tolerance of order 1e-14, whereas the present pin also fails on a legitimate re-derivation of either copy with a different summation order — a pin resting on identical rounding rather than on the agreement it names (class 8).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U34/probe_A2.jl` section A3 prints `|values| range ... [330.89..., 1.132...e8]`, `eps at those magnitudes: [5.68e-14, 1.49e-8]`, `worst difference in ulps = 0.0`.

### LEAD U34-6 [Minor, confidence med] test/runtests.jl:19829
Claim: The record testset's only pin of the strength-slot number convention (`replay(wk.rule.strength[2], 4, 0:4)`, slot `N + i` = 4 for harmonic 2 of a 2-harmonic cavity) uses a `TurnTable`, whose replay ignores the slot number, so the pin passes for any slot number and cannot fail if the container's numbering changed.
Mechanism: `_turn_offset(::TurnTable, ctx, slot, T)` indexes the table by turn only; measured (probe B2) `replay(table, 1) == replay(table, 2) == replay(table, 4)`. The convention is documented at `src/elements/turn_modulated.jl:635` and `:789` and is observable with a slot-keyed rule: with `strength_noise=(nothing, WhiteNoise(...))` only slot 4 reproduces the realised offsets (1.5e-16; slots 1-3 differ by >= 1.5e-2) and only slot 4 matches the recorded series. The phase slots are pinned with WhiteNoise/PinkNoise (19826-19827) and are sensitive; the strength slot is not. Seam for the auditor: `test/turn_modulation_probe.jl` (outside this region) draws white/pink rules on strength slots and its `c3.series_eq_replay` may pin the convention; not verified here.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U34/probe_B.jl` section B2 prints `TurnTable: replay(slot=2) == replay(slot=4): true` and `recorded strength_noise[2] series matches replay with slot number: [4]`.

### LEAD U34-7 [Minor, confidence low] test/runtests.jl:22480
Claim: `with_logger(NullLogger())` around the whole 14-variant x 2-policy loop of the PIC multi-process testset silences every warning of 28 runs, while its justification (22477-22479) names one warning of one variant.
Mechanism: the comment explains the `:node` mesh drop; measured today (probe B3) that is indeed the only warning emitted — 1 per policy on `:node`, 0 on the other 26 runs — so nothing is hidden at 24e8683. The scope is nevertheless a silent-degradation surface (class 6): a new warning from any other variant (dropped charge, a clipped launch, a registry collision) would be swallowed by a testset whose assertions compare CPU and passthrough bitwise and would still pass. The second `NullLogger` at 22503 (the dataflow/batched pair) has the same shape with no justification at all. A collecting logger that asserts the expected `:node` warning and no other would keep the intent and lose the blind spot.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U34/probe_B.jl` section B3 prints `warnings=1` for the two `:node` rows and `warnings=0` for every other row.

### LEAD U34-8 [Minor, confidence med] test/runtests.jl:22300
Claim: In the spawned-worker half of the `:funneled` tripwire, `if Threads.nthreads(:default) > 1` has no `else @test_skip`, so at one default thread its five assertions (every worker flagged, flag restored, every worker ran, the refusal and its message) vanish silently — against the suite's own header rule and unlike the thread half at 22268-22283, which skips visibly.
Mechanism: the suite preamble (lines 60-63) records that "gated sets without an else still vanish silently — prefer `else @test_skip` in new ones"; this block, added 2026-09-07, follows the `if` with the inline-worker assertions and no `else`. CI and the gate run at four threads so the block executes there; the gap shows only under `--threads=1`, where the summary would not say the spawned-worker tripwire went untested (class 1, hypothesis 1).
Repro: `n=$(grep -n "flags = fill(false, 32)" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl | cut -d: -f1); sed -n "$((n-1))p" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` prints the `if Threads.nthreads(:default) > 1`; `awk -v s=$n 'NR>s && /^            end$/{print NR; exit}' ...` reaches the closing `end` with no `else` between (reading 22300-22323 shows none).

## Clean

Checked and found sound, with what was compared:

- Hypothesis 1, gates and skips (read every `if` in the region): the record testset's CUDA arm (j) and the one-particle probe's CUDA arm both end in `else @test_skip "CUDA device not available..."`; the probe's MPI arm is gated by `_lane_gate(...)` (a loud LANE SKIP in the fast lane) and reports `@test_broken false` both when `MPICH_jll.mpiexec()` is unavailable and when the child could not run (`!success(proc) && !ran`); the `:funneled` thread half has `else @test_skip`. No `@testset` body sits behind a constant-false condition; `assert_verification` nests its checks behind `r !== nothing && r.root` only after asserting that same condition (one visible failure, not a silent skip). The spawned-worker exception is U34-8.
- Hypothesis 1, aborting tolerances: no `@test` in the region compares against a quantity that could be `NaN`-silent; every refusal test captures the exception and asserts its type and message text (`err_e`, `err_k`, `err_m`, `err_cols0`, `errN`, `errP`, `err3`, `err4`, `err_box`, `err1`, `sol_msg`), so a wrong exception type fails rather than passing.
- Hypothesis 2, negative controls present and executed: `_output_receipt_gaps` is fed three fabricated receipt sets (a receipt lacking a field, no receipt, another observer's receipt) at 20746-20758; the fold-site registry is injected twice (`pop!` of `:solenoid` from both tables, restored in `finally`) at 21513-21530; the index-offset test's `wrong` arm (22120-22123); each PIC variant shown to differ from `:default` (22493-22495) and the dataflow/batched loops' schedule receipts asserted (22513-22514); the cache testset's "never invalidates" and "never holds" controls (19672-19698); the recorder protocol's two refusals and its dropped never-ended turn (20183-20213); the torn-attribute and partial-slot files built through HDF5 on every reader route (20094-20150, 20903-20960); the lock test's `held_line` falls back to `""` so a missing lock file fails `occursin("host=...")` instead of passing vacuously (20335-20339).
- Hypothesis 3, derived-vs-copied lists: observers pinned against `_concrete_octopus_subtypes(AbstractBeamObserver)` (20548); task schemas against the `AbstractTask` tree (20546); `_turn_rule_kinds()` against the rule catalogue (20765-20767); `_RA_KINDS`/`_RA_NAMED_KINDS` against `_RA_GROUPS` and a run of every producer (20800-20822); ledger columns from `_RA_LEDGER_COLUMNS` on creation, read and design note (20454-20464); `prepare_run_artifact!` call sites counted from `src/` (20394-20400); the ten folding kinds pinned against the registry keys (21532-21534); `declared` statuses count 6 (hand count paired with a derived set — a tripwire pairing, not a bare copy). Each hand list has its derived partner in the same assertion.
- Hypothesis 3, bitwise pins: CPU vs `MultiProcessExecutionPolicy` passthrough (21985-21988, 22132-22135, 22195-22200, 22486-22488) compare one code path with itself by construction (the receipts prove the passthrough resolved, 22010-22014) — structural. The girder-vs-survey `== 0.0` pins (21452-21453, 21489-21492) rest on shared code: read `floor_plan.jl` 109-246, both walkers call `_floor_step`, `_fp_apply`, `_fp_mul`, and the girder's extra conjugation by `Q = _FP_IDENTITY` is exact in IEEE arithmetic — structural, not rounding. Recorded series vs `replay` (19826-19829, 19925-19935, 20005-20006, 20215-20218) compare the host-side draw function with itself across turns, and the CUDA arm's series with the CPU's because draws are host-side on every backend (20228) — structural. The one exception is U34-5.
- The moments "no side effect" comparison (19843, 20249) filters `isa AbstractVector`: measured 7 of 8 keys are vectors and the skipped key is the scalar `:s`, so the filter drops nothing that varies per turn.
- Allocation pins: `<= 64` B for the cached tuple reads and `== 0` over 62 recorder turns are measured in-suite after warm-up, with the before/after numbers (12,064 B -> 0 B; 1568 B -> 0 B) recorded in the testset headers and their logs named.
- The record testset's part list (a)-(j) is complete: a, b, c, d, g, e, f, h, i, j all present (out of alphabetical order, none missing).
- `one` is shadowed by a local two-argument helper in the receipts testset (20518); every `one(` in that scope is the helper, no `Base.one` use remains in scope (read 20500-20994).
- Style only (no lead): `@test !saw(bendy)` (21427) checks a retired warning by message text and would pass trivially if the text were reworded, but it is paired with the exactness pin `< 5.0e-14` on the same geometry, which is the operative check.

## Unchecked

- `test/turn_modulation_probe.jl` is outside the region: the fields `r.c1`, `r.c2`, `r.c3`, `r.ref` and `tm_probe_pass(r)` asserted at 21028-21086 were not read, so whether `tm_probe_pass` is derived from the same fields the testset also asserts (a circular pass) is not known; noted as a seam under U34-6.
- Not executed by me: the record testset's CUDA arm (j), the probe's CUDA and two-rank MPI arms, the lock-holder child process, the `--threads=4,0` child, and the 1800 s MPI watchdog path. They were read; the suite's own full-lane logs are the evidence they run.
- The `:funneled` thread half's premise (an interactive thread exists under `--threads=N`, measured on Julia 1.12.4 per 22321-22327) was not re-measured on this machine's Julia.
- The `src/` side of U34-2 — whether `threads = 256` is launchable for `_cuda_spectral_interp_scatter_kernel!` on the device here — was not measured; it is out of region and belongs to the auditor's seam list.
- The behaviour of the lane-skip banner for the probe's MPI arm under `lane=fast` was not exercised here (read only).
