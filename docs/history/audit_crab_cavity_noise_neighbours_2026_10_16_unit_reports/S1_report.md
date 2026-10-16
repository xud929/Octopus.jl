# S1 — seam pass: the counter-RNG key space

Unit S1 of the 2026-10-16 crab-noise neighbour audit. Repository: Octopus,
main checkout `/cfs/ad/dxu/Library/Julia/Octopus` at `3126908`. Julia
`--project=. --threads=4`, CUDA active (NVIDIA RTX 4500 Ada; `CUDA.functional()`
true). Scratch and probe logs: `result/audit_crab_noise_2026_10_16/S1/`.
Nothing in the repository was modified.

## 1. Region and provenance

The seam is the key `(seed, method_code, turn, rng_id, particle_index,
component)` of the keyed generator in `src/math/counter_rng.jl` and every
consumer of it in `src/` and `ext/`.

Read in full (every line): `src/math/counter_rng.jl` (431 lines); the
key-layout comment and every stochastic rule, the spectral factory, the
synthesis, the rule draws, `_check_slot_table`, and the id collector in
`src/elements/turn_modulated.jl` (lines 90-230, 365-435, 480-530, 560-660,
690-730, 795-1010, 1150-1190, 1465-1495); `src/beam/Beam.jl` 110-180 and
555-640; `src/tasks/BPMObserver.jl` 90-245 and 395-430;
`src/elements/radiation.jl` 1-60, 120-135, 160-290; `src/tasks/Tasks.jl`
216-234, 310-470, 965-990, 1085-1100, 1905-1925; `src/track/Track.jl` 1-60;
`src/track/phase6d_track.jl` 20-60, 255-300, 357-420;
`src/track/radiation_track.jl` 1-90; `src/track/strong_beam_track.jl` 70-90,
125-140; `src/policies/Policies.jl` 705-782, 925-985;
`src/tasks/strongstrong/interface.jl` 2388-2412, 2680-2692, 2825-2845;
`src/knowledge/Knowledge.jl` 55-85; `src/elements/aperture.jl` 40-56;
`src/contracts/Contracts.jl` 3540-3560. Reference documents:
`docs/design/turn_modulation.md` section 4.3, `docs/design/spectral_turn_table.md`
D4 and D11 with their dated remarks, `docs/experiences.md` lines 1483-1640,
`docs/todo.md` rows 34, 38, 40, `docs/current_runtime.md` 284-296,
`docs/theory/bpm_measurement_model.md` 178-196, `docs/public_api.md` 428-452.
Suite anchors read: `test/runtests.jl` 9948-9966, 10100-10150, 11225-11260,
18070-18160, 20780-20800; `test/mpi_seam_check_fixture.jl` 30-70;
`test/turn_modulation_probe.jl` header.

Enumerated by grep, whole tree: every call of `octopus_*`, `counter_*`,
`splitmix_*` draw names; every `rng_id`, `next_rng_id!`, `claim_rng_id!`,
`reset_rng_id_counter!`, `global_rng_*`, `TrackingContext(`, `index_offset`,
`_mp_current_shard`; every `rand`/`randn`/`Random.`/`MersenneTwister` in
`src/` and `ext/`; `ext/` for `rng|seed|random` (no hit).

Executed (logs beside the scripts): `probe_cells_registry.jl` (P1-P3 and the
start of P4), `probe_registry_tail.jl` (the rest of P4 and e3b),
`probe_backends.jl` (e1-e3), `probe_mixed_precision.jl`,
`probe_strongstrong_warning.jl`, `tripwire_prototype.jl`.

## 2. The consumer table

Every draw call site in `src/` and `ext/` outside the generator file, grouped
by enclosing function (the grep-derived list; `ext/` has none):

| # | Consumer | Call site | seed | method | turn field | rng_id (source; 0 means) | particle field | components |
|---|---|---|---|---|---|---|---|---|
| C1 | Beam initial distribution | `src/beam/Beam.jl:133` `_alloc_counter_randn` | `global_rng_seed()` at construction | `global_rng_method_code()` | 0 | Beam keyword; 0 → `next_rng_id!`, else `claim_rng_id!` (Beam.jl:169) | i = 1..N over the WHOLE beam (MPI ranks draw whole, then slice: Beam.jl:596-606) | dim 1..6 |
| C2 | BPM reading noise | `src/tasks/BPMObserver.jl:208-209` `bpm_reading` | `ctx.seed` | `ctx.rng_method` | `ctx.turn` (absolute) | `bpm.rng_id::Int`; `nothing` → `next_rng_id!`; any integer incl. 0 → `claim_rng_id!` (BPMObserver.jl:149) | occurrence within the turn, o = 0, 1, ... | 1, 2 |
| C3 | LumpedRad excitation | `src/elements/radiation.jl:248-253, 270-275` `_track_lumped_rad_context` (Radiation6DMap, Diffusion6DMap) | `ctx.seed` | `ctx.rng_method` | `ctx.turn` | `elem.rng_id`; friendly `LumpedRadSpec`: 0 → `next_rng_id!` (radiation.jl:34); compile reads `getparam(spec, :rng_id, 0)` (radiation.jl:129) | `particle_id = ctx.index_offset + index` ≥ 1 | 1..6 |
| C4 | Spectral synthesis (`spectral_turn_table`, `SpectralNoise` resolution) | `src/elements/turn_modulated.jl:511, 514` `_spectral_synthesis` | factory `seed` argument / `global_rng_seed()` at compile (turn_modulated.jl:835) | `RNG_PHILOX` hard-coded | slot: 0 offline; `1:2N` crab, 1-2 RF when resolved | factory `rng_id` > 0, NOT claimed; `SpectralNoise.rng_id` claimed through `_rule_stream_id` | frequency bin k ≥ 1 | 1 (phase); 3-4 (Rayleigh pair 2) |
| C5 | WhiteNoise rule | `src/elements/turn_modulated.jl:982` `_turn_offset` | `ctx.seed` | `ctx.rng_method` | `ctx.turn` | `rule.rng_id` claimed (0 → fresh) | 0 | `1024 + slot` |
| C6 | PinkNoise rule | `src/elements/turn_modulated.jl:997` `_turn_offset` | `ctx.seed` | `ctx.rng_method` | `ctx.turn >> k`, k = 0..K-1, K ≤ 62 | `rule.rng_id` claimed | 0 | `1024 + slot + 64 (k + 1)` |

Context plumbing: `TrackingContext(turn, seed, rng_method, index_offset)` is
built from the globals at `execute!` (`Tasks.jl:979, 1094`,
`interface.jl:2686`), advanced with `with_turn` (absolute turn), and given the
shard offset with `with_index_offset`. The offset is `first(shard) - 1`
(`Policies.jl:771`), the 0-based `k` the `Track.jl` docstring promises, and
`(0, n)` at one rank. CPU workers (`phase6d_track.jl:53`), the CUDA fused
kernel (`phase6d_track.jl:278`), and the luminous CPU path (`Tasks.jl:1917`)
all key `ctx.index_offset + index`. No rank, thread, block, or worker index
enters any key.

Randomness outside the key space, for completeness: radiation's context-free
`track_particle` methods draw `Random.randn()` (`radiation.jl:178-179,
191-192`), reached only by the contextless CPU `fusedTrack` path (recorded at
`phase6d_track.jl:390-394`; the CUDA side rejects contextless tracking); a Beam
built with an explicit `rng` uses `randn(rng, ...)` and ignores `rng_id` with
a warning; contracts use `MersenneTwister` fixtures for analysis maps, not for
tracking. The strong-strong solvers, the knob system, and `ext/` contain no
random draw.

Registry: `next_rng_id!` (atomic add), `claim_rng_id!` (atomic max, skipped
for id ≤ 0), `reset_rng_id_counter!` (public; no caller anywhere in `src/`,
`test/`, `validation/`, `examples/`, `profiling/`; only the 2026-08-05_b
history scripts). The within-class warnings: `_warn_duplicate_radiation_streams`
(called only by `TrackingTask`, `Tasks.jl:208`) and
`_warn_duplicate_turn_modulation_streams` (both task constructors; it also runs
the equal-digest table warning).

## 3. Leads

### LEAD S1-1 [low, confidence high] src/tasks/BPMObserver.jl:149
Claim: `BPMObserver(rng_id=0)` draws on stream 0, while `Beam`, `LumpedRadSpec`, `WhiteNoise`, `PinkNoise` and `SpectralNoise` all read `rng_id = 0` as "assign a fresh stream", and the BPM's own option metadata (BPMObserver.jl:408, default `0`, "Auto-assigned unique at construction") describes the other convention.
Mechanism: the BPM's auto sentinel is `nothing`, not `0`; an explicit `0` goes to `claim_rng_id!(0)`, whose `id > 0 &&` guard skips the atomic max and returns `0`, so the BPM lands on a stream no auto-assignment ever issues but any raw-spec or override-0 radiation element (LEAD S1-2) also occupies; measured, a task with such a radiation element and `BPMObserver(rng_id=0)` warns nothing and they share cells (BPM occurrence 1 component 1 on turn 2 === radiation particle 1 component 1 on turn 2).
Repro: `julia --project=. -e 'using Octopus; println(BPMObserver("z"; x_noise=1e-6, rng_id=0).rng_id)'` prints `0` (a fresh id would be ≥ 1); the task-level number is in `S1/probe_registry_tail.log` ("task: raw radiation on stream 0 + BPMObserver(rng_id=0): warnings 0").

### LEAD S1-2 [low, confidence high] src/elements/radiation.jl:129
Claim: a `:lumped_radiation` spec that reaches `compile_runtime` without a positive `rng_id` draws on stream 0 — a fully populated raw `ElementSpec{:lumped_radiation}` with `rng_id` omitted or `0`, and a friendly `LumpedRadSpec` whose placement carries the override `entry.rng_id = 0` — although the kind's `ParamMeta` (radiation.jl:322) says "0 auto-assigns a unique id".
Mechanism: auto-assignment happens only in the friendly constructor (radiation.jl:33-34); compile reads `UInt64(getparam(spec, :rng_id, 0))` with no `> 0` check, and `_merged_params` lets an override replace the claimed id with 0. Two such placements still trigger the within-class warning (0 counts as a shared id), so the silent case is stream 0 shared across classes (LEAD S1-1). A bare raw spec without the other parameters cannot compile at all (`KeyError: :beta`), so the route needs either every parameter or an override.
Repro: `S1/probe_registry_tail.jl` section (d2): "raw ElementSpec{:lumped_radiation}(all params, no rng_id) compiles to LumpedRad.rng_id = 0"; "the same spec placed with override rng_id = 0 compiles (compile_runtime(entry)) to LumpedRad.rng_id = 0".

### LEAD S1-3 [low, confidence high] src/tasks/strongstrong/interface.jl:2396-2400
Claim: `StrongStrongTask` runs only the turn-modulation duplicate-stream warning; two `LumpedRadSpec` placements sharing an `rng_id` in a strong-strong line (or one per beam) build with no warning, where `TrackingTask` warns, and the comment's "that gap is pre-existing and stays ledgered" resolves to no ledger row I could find.
Mechanism: `_warn_duplicate_radiation_streams` has one call site, `Tasks.jl:208`. Searched for the ledger row with `radiation sibling`, `_warn_duplicate_radiation_streams`, `F14`, `radiation placements`, `two radiation`, `StrongStrong`+`radiation` across `docs/todo.md`, `docs/history/todo_ledger_archive.md`, `docs/history/*.md`, `docs/experiences.md`, `docs/comprehensive_audit.md`: no hit. The F14 shape (two placements, kicks exactly correlated, variance scaling with the square of the placement count) applies unchanged to a strong-strong line.
Repro: `julia --project=. result/audit_crab_noise_2026_10_16/S1/probe_strongstrong_warning.jl` → `TrackingTask((rad, rad)) ... warnings 1`, `StrongStrongTask((ip, rad, rad), (ip, drift)) ... warnings 0`, `StrongStrongTask((ip, rad), (ip, rad)) ... warnings 0`.

### LEAD S1-4 [low (documentation), confidence high] src/elements/turn_modulated.jl:511
Claim: the method code is not a dimension of either key — it selects the generator (`octopus_uint64`, counter_rng.jl:105-125) — and the spectral synthesis is the one consumer that hard-codes `RNG_PHILOX`, so the key-layout comment's sentence "What separates one stochastic consumer from another is the CLAIMED rng_id ... and the method tag" (turn_modulated.jl:98-100) overstates: within one run the method is global and separates nothing; it separates the spectral class from the others only under `:splitmix`, by accident of the hard-coding.
Mechanism: C1-C3, C5, C6 take `global_rng_method_code()` or its `ctx.rng_method` snapshot; C4 passes the constant. Measured consequences: under `set_global_rng!(method=:splitmix)` a resolved `SpectralNoise` table is bitwise the `:philox` table while a `WhiteNoise` on the same slot changes (3.126e-5 against 5.836e-3 on turn 1); the documented Beam/spectral slot-0 coincidence holds under `:philox` (64/64) and vanishes under `:splitmix` (0/64); cross-method equality of a cell is chance (0 of 8000 cells equal). D4 and D9 of `docs/design/spectral_turn_table.md` and the factory docstring state Philox explicitly, so this is a design-stated asymmetry (the rule follows the global seed but not the global method), not a defect; the lead is the comment's wording and the absence of the method from the table's canonical name (which is correct only because it is always Philox).
Repro: `S1/probe_cells_registry.log`, section P2.

### LEAD S1-5 [low, confidence high] src/elements/turn_modulated.jl:514
Claim: under one explicit `rng_id` and one seed the spectral class shares cells with the three older classes exactly as the key-layout comment predicts, and no cross-class warning exists; measured for the first time for the spectral class, including the exact-equality form under `amplitudes = :rayleigh`.
Mechanism: offline slot 0, bin k: the Rayleigh pair `octopus_normal_pair(S, PHILOX, 0, R, k, 2)` IS the Beam's raw `(y, py)` normals of particle k (64/64 bitwise, `Octopus._alloc_counter_randn(CPUThreadsBackend, Float64, N, 3; seed=S, rng_method=RNG_PHILOX, rng_id=R)`), and the bin's phase uniform is the first Box-Muller uniform of the Beam's x draw (64/64 reconstructed). Resolved slot s ≥ 1, bin k: the Rayleigh pair IS radiation particle k's `(ny, npy)` on turn s (64/64 for s = 1, 2, 7), and the phase uniform is the first uniform of BPM occurrence k's `n1` on turn s (64/64). One `TrackingTask` with `SpectralNoise(rng_id=5)`, `LumpedRadSpec(rng_id=5)` and `BPMObserver(rng_id=5)` builds with 0 warnings (control: two radiation placements on 5 → 1). The registry prevents none of this: auto ids are distinct, explicit ids are the user's. Rules against every other class: 0 shared cells over 8 turns, particles 0..64, components 1..6 (the band ≥ 1024 holds). Known and ledgered in shape: `docs/todo.md` row 38 ("one cross-class duplicate-id warning at task construction") covers it, but the row names radiation, a rule and a BPM, not the spectral class.
Repro: `S1/probe_cells_registry.log`, section P1 (a1)-(a5).

### LEAD S1-6 [low, confidence high] src/math/counter_rng.jl:77
Claim: the high-water-mark registry detects no collision of an explicit id chosen after a fresh one (todo row 34, open) and no sharing across tasks in one process.
Mechanism: `claim_rng_id!(k)` with k ≤ counter leaves the counter unchanged and returns k. Measured: a `Beam` took auto id 7, `LumpedRadSpec(rng_id=7)` was accepted with the counter still 7, and their turn-0 cells are equal (Beam raw x of particle 1 === radiation component 1 of particle 1 on turn 0). Two `TrackingTask`s each with `LumpedRadSpec(rng_id=5)` → 0 warnings; two each with a `WhiteNoise(rng_id=6)` crab cavity → 0 warnings: both warnings are per task constructor and no process-wide registry exists (the counter_rng.jl docstring says so).
Repro: `S1/probe_cells_registry.log` (d1) and `S1/probe_registry_tail.log` (d3).

### LEAD S1-7 [info, confidence high] src/tasks/BPMObserver.jl:98
Claim: the BPM narrows the `UInt64` stream id to `Int`, so an id that fits the registry can be refused or, worse, poison every later auto-assigned BPM.
Mechanism: `rng_id::Int` with `Int(claim_rng_id!(rng_id))` for an explicit id and a bare `next_rng_id!()` (a `UInt64`) stored into the `Int` field for the auto case. Measured: `BPMObserver(rng_id=typemax(UInt64))` → `InexactError`; `BPMObserver(rng_id=typemax(Int64))` is accepted and leaves the counter at 2^63, after which every `next_rng_id!()` exceeds `typemax(Int)` and a later `BPMObserver()` would throw on the implicit conversion. Negative ids: `claim_rng_id!(-1)`, `BPMObserver(rng_id=-1)`, `Beam(rng_id=-1)`, `LumpedRadSpec(rng_id=-1)` all die with `InexactError` (todo row 40, open); the rules and the spectral factory refuse with an `ArgumentError`. Purely theoretical at realistic ids; recorded for the shape of a fix (an `id >= 0` check inside `claim_rng_id!` plus a `UInt64` field on the BPM).
Repro: `S1/probe_registry_tail.log` (d4).

### LEAD S1-8 [info, confidence high] src/track/radiation_track.jl:17
Claim: the deprecated single-element CUDA radiation kernel keys on `index` alone with a context it builds itself (offset 0, turns 0-based), so it agrees with the fused kernel only because no caller offset can reach it.
Mechanism: `track!(rep, elem::LumpedRad, turns, CUDABackend)` and its policy twin take no context; the MPI policy composes CPU execution only, so the offset is always 0 there. Measured: deprecated kernel against the fused CUDA kernel, 256 particles, turn 0: 0 ulp; both against the CPU: 3 ulp (the normal transform). Not a defect today; a note for the tripwire (section 5): the kernel forms a particle id but is not a draw site, so a draw-name grep does not see it.
Repro: `S1/probe_registry_tail.log` (e3b).

### LEAD S1-9 [out of hypothesis, low, confidence high] src/track/phase6d_track.jl:277
Claim: a `Float32` beam through a `Float64` `LumpedRadSpec` runs on CPU (coordinates silently narrowed on store) and fails on CUDA at kernel compile with `GPUCompiler.InvalidIRError` ("unsupported call to an unknown function (call to jl_f_tuple)" in `fusedTrack`, `ijl_get_nth_field_checked` in `setindex!` at `Beam.jl:187`); the matched `Float32`/`Float32` case runs on CUDA.
Mechanism: `_track_lumped_rad_context` computes in `T = typeof(x + ...)` = `Float32` but mixes `elem.excitation::Float64`, so the returned tuple is mixed-type and the device `setindex!` is dynamic; the CPU accepts the conversion. Outside this seam (the precision contract between a beam and its line); flagged for the auditor because the same mismatch is silent on one backend and opaque on the other.
Repro: `julia --project=. result/audit_crab_noise_2026_10_16/S1/probe_mixed_precision.jl` → "CPUThreadsExecutionPolicy: ... ran; eltype Float32", "CUDAExecutionPolicy: ... GPUCompiler.InvalidIRError", "CUDA: Float32 beam + LumpedRadSpec{Float32}: ran".

## 4. Clean list, with the evidence

Hypothesis (b), the method dimension: not a key dimension; a generator
selector; no consumer besides C4 departs from the global snapshot; cross-method
cell equality 0 of 8000 (see LEAD S1-4 for the documentation consequence).

Hypothesis (c), the pink stride bound: with 64 slots (N = 32), every slot
carrying a white AND a 62-octave pink rule, the rule components span
1025..5056 with 0 clashes; 65 slots give 62 clashes (pink slot 1 generator 40
= pink slot 65 generator 39) and 66 slots 124 (white slot 66 = pink slot 2
generator 0), the algebra `s - s' = 64 (k' - k)` needing `|s - s'| ≥ 64`. The
smallest rule component, 1025, exceeds the largest component any other
consumer draws, 6, so the band cannot overflow into another class at any N;
the spec places no bound on N (a type parameter) and none is needed for
cross-class disjointness. Enforcement measured on the compile path:
`ThinCrabCavitySpec{32}` with a `PinkNoise` compiles, `{33}` is refused ("66
slots, more than the pink stride 64") by `_check_slot_table` through the
two-argument `TurnModulated(base, rule)` (turn_modulated.jl:1303), `{33}`
white-only compiles. `octaves ≤ 62` bounds `turn >> k` on the `Int64` turn.
Two elements sharing an id are warned by the per-element collector.

Hypothesis (d), the registry: 1e6 `next_rng_id!` calls distinct and strictly
increasing, `UInt64`; `reset_rng_id_counter!(0)` re-issues id 1 (public,
caller-free in the tree; the 2026-08-05_b U14 report records it). The
defects found are LEADs S1-1, S1-2, S1-6, S1-7.

Hypothesis (e), rank and backend independence: static, no rank/thread index
in any key (section 2). Measured: a `WhiteNoise` crab cavity, one particle,
6 turns, CPU against CUDA: 0 ulp on all six coordinates on every turn (the
rule is realised on the host; the kernel sees the realised cavity);
diffusion-only `LumpedRad`, 1024 particles, 1 turn: CPU 4 threads against 1
thread bitwise on all coordinates; CPU against CUDA 121-155 of 1024 entries
per coordinate differ, max 4 ulp, max |diff| 1.1e-19 (the libdevice
`log`/`cos`/`sin` of the normal transform; the U15-13 reading in
aperture.jl:44-52, "up to 2 ulp" there, 3-4 ulp here, same order); particle
17's x reconstructed bitwise from `excitation[1] * octopus_normal(seed,
method, 0, 11, 17, 1)`; a 256-slice tracked with `index_offset = 512`
equals whole-beam rows 513:768 bitwise on CPU and within 3 ulp on CUDA. MPI
at more than one rank was NOT executed in this unit; the standing evidence is
the suite's `test/mpi_seam_check_fixture.jl` (a radiating line, `rng_id=101`,
compared by string across ranks) and the two-rank arm of
`test/turn_modulation_probe.jl`.

Hypothesis (a), the rules against every other class: 0 shared cells
(measured, probe a4); the three older classes among themselves and the
spectral class against them: LEAD S1-5.

## 5. Hypothesis (f): the tripwire, with a prototype

`S1/tripwire_prototype.jl` (run; log beside it) does three things and is the
proposed shape:

1. A table, one row per consumer, keyed on `(file, enclosing function)` rather
   than line numbers, carrying the key region: turn field (`:zero`,
   `:ctx_turn`, `:ctx_turn_shifted`, `:slot`), particle field (`:index`,
   `:occurrence`, `:zero`, `:bin`), component set, method source (`:global`,
   `:ctx`, `:philox`), and the id source with what `0` means. The five rows of
   section 2 (C5 and C6 share `_turn_offset`).
2. A sweep over `src/` and `ext/` (excluding `src/math/counter_rng.jl`) for
   the thirteen draw names, with triple-quote state tracking so docstring
   prose is skipped (without it three prose lines, turn_modulated.jl 489, 608,
   638, were false hits), grouping hits by enclosing function; the test
   requires set equality in both directions (an undeclared call site fails; a
   declared row with no live site fails). On this tree: five groups found,
   zero undeclared, zero stale.
3. A pairwise region check computed from the table: every pair whose declared
   regions can coincide on one `(seed, rng_id)` must be on an explicit
   allow-list with the reason (today: Beam/radiation, Beam/BPM, radiation/BPM,
   Beam/spectral slot 0, radiation/spectral slot ≥ 1, BPM/spectral slot ≥ 1 —
   the prototype derives exactly these six and finds the four rule pairs
   disjoint); a new consumer whose region meets an existing one without an
   entry fails. A fourth part, cheap and worth adding: one cell-level
   measurement per allowed pair (the coincidence is real, as probe P1 shows)
   and per disallowed pair (no equal cell over a small grid), the 62-equality
   ledger made permanent; and an assertion that every row's method source is
   `:global` or `:ctx` except the rows that declare `:philox`, so a new
   consumer hard-coding a method is a conscious table entry.

Two things the draw-name grep cannot see, to be declared beside the table:
the particle-id-forming sites (`index_offset + index` at phase6d_track.jl:53,
278, Tasks.jl:1917; the deprecated radiation kernel's bare `index`, LEAD
S1-8), and the id-claiming sites (`next_rng_id!`/`claim_rng_id!` callers:
Beam.jl:169, BPMObserver.jl:149, radiation.jl:34, turn_modulated.jl:177).
Where the table lives is the auditor's call; in `src/math/counter_rng.jl` it
could also feed the key-layout comment, which today is hand-maintained in
`turn_modulated.jl`.

## 6. Unchecked, and why

- MPI at two or more ranks: not launched (the suite's fixtures stand as the
  evidence; see hypothesis (e)).
- `ext/OctopusMPIExt.jl` and the other extensions: grepped for RNG usage (none);
  not read line by line.
- Files outside the seam were read at their call sites and plumbing only
  (`Tasks.jl`, `interface.jl`, `Policies.jl`, `phase6d_track.jl` are not
  read in full).
- Whether the suite already pins the method-independence of the spectral
  table or the stream-0 semantics of `BPMObserver(rng_id=0)`: grepped
  (`BPMObserver(` with `rng_id=0` has no test hit; no test sets `:splitmix`
  around a `SpectralNoise`), not exhaustively traced.
- The mixed-precision failure (LEAD S1-9) was measured on one element kind only.
