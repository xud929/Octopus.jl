# U20: track/ + math/

Comprehensive audit 2026-10-18, reading unit U20. Tree: `/cfs/ad/dxu/Library/Julia/Octopus`
at 24e8683, read-only. Scratch: `result/comprehensive_audit_2026_10_18/probes/U20/`.

## Region

| file | lines |
|---|---|
| `src/track/Track.jl` | 1-504 |
| `src/track/phase6d_track.jl` | 1-506 |
| `src/track/fused_track.jl` | 1-133 |
| `src/track/longitudinal.jl` | 1-374 |
| `src/track/radiation_track.jl` | 1-61 |
| `src/math/counter_rng.jl` | 1-712 |
| `src/math/SpecialMath.jl` | 1-174 |

Total 2464 lines, every line read. `src/track/strong_beam_track.jl` (954 lines) sits in the
same directory but is not in this unit's region; it was opened only at the seams named below.

## Provenance

READ line by line: all seven region files in full (the ranges above).

READ out of region, for seams only (not audited): `src/track/strong_beam_track.jl` 296-316,
564-606, 655-722 and the grep hits at 217-218, 304, 839-840; `src/elements/thin_elements.jl`
55-175; `src/elements/misalignment.jl` 240-300; `src/elements/ref_tilt.jl` 55-95;
`src/elements/turn_modulated.jl` 1436-1452; `src/elements/aperture.jl` 280-300, 388-420;
`src/elements/strong_beam.jl` 242-262, 1185-1202; `src/contracts/Contracts.jl`
`_contract_default_initial_rep`; `test/runtests.jl` 10735-10800, 13700-13830, 15255-15480,
13148, 24439-24452; `validation/tracking_backend_consistency.jl` header and 400-470;
`validation/counter_rng_validation.jl` 1-60; `docs/current_runtime.md` 121-215; `docs/todo.md`
row 36; `docs/theory/lattice_hamiltonian_and_conventions.md` 45-72, 101-123; the previous
audit's `docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U14_report.md` (leads
U14-1, -7, -8, -10, -11 and section 3).

EXECUTED (scripts and logs in the scratch directory; CUDA active, RTX 4500 Ada, 4 threads):

- `probe_cpu.jl` -> `probe_cpu.log`: Philox KAT (3 of 3 vectors bit-for-bit;
  `philox4x32_self_test() = true`); 1440 distinct `counter_uint64` values over a
  (seed, turn, rng_id, particle, component) grid; `_uniform_open01` endpoints
  `[2^-53, prevfloat(1)]` (Float64) and `[2^-24, prevfloat(1f0)]` (Float32);
  `_cross_backend_agreement` on Float32 data one Float32 ulp apart reports
  `ulps_of_scale = 5.36870912e8` (= 2^29); NaN-payload `===` behaviour; the per-kind class table
  and the wrapper rule against the line rule for all 30 example kinds.
- `probe_cuda.jl` -> `probe_cuda.log`: NaN payloads after one device operation (identical bits
  to the host for Float64 and Float32: literal, `NaN+1`, `0/0`); the fusion-exact declarations
  at 1e5 particles (thin quadrupole k1l=0.05 and 0.37, thin dipole, hkicker: 0 particles part;
  skew+normal quadrupole 11401; thin sextupole 130; drift L=0.35: 5881 part in x, L=0.5: 0);
  the growth of the CPU/CUDA parting with turns (1, 3, 10, 30, 100) for six fixtures on the
  suite's 400-particle state (table under LEAD U20-1).
- `probe_cuda2.jl`, `probe_cuda3.jl` -> logs: wrapped kinds behind `z_offset` (1e-3 to 0.5 m,
  angles x1 and x50) and `ref_tilt`: the face drift parted x in 0 of 1e5 particles in every
  configuration; the kept `:bitwise` classes held.
- `probe_cpu2.jl` -> `probe_cpu2.log`: the Bassetti-Erskine kick evaluated on ONE backend with
  the two Faddeeva routes the two backends call: Kx differs by 599.5 ulps of its scale, Ky by
  209.9, 14 of 400 Kx values bitwise equal.
- The committed harness
  `docs/history/comprehensive_audit_2026_08_05_b_unit_reports/faddeeva_bigfloat.jl` re-run on
  this tree -> `faddeeva_bigfloat.log`: |w| relative error 3.092e-13 (Weideman interior, at
  z = 5), 4.5e-16 at the y = 7 boundary, 2.5e-16 on the continued-fraction branch, 9.1e-14 across
  the four quadrants, w(0) = 1 + 2.75e-14; identical to the 2026-08-05_b figures.

## Leads

### LEAD U20-1 [Moderate, confidence high] src/track/Track.jl:343
Claim: the `CrossBackendRounding` bounds are 2-3-turn figures and the line composition rule (the members' maximum) models neither accumulation over turns nor amplification through neighbours, so the declared classes are violated by ordinary lines and even by a single pitched element once a run is longer than the fixture that measured them; todo row 36 scopes this to a strong beam's gradient, and the measurement shows it is general.
Mechanism: `_cross_backend_rounding(ops::Tuple)` sets `bound = maximum(m.ulp_bound for m in members)`, and every per-kind bound is "the measurement on the registry example (400 particles with spread, 3 turns) times four" (docstring, Track.jl:211-213). A parting of one ulp in turn k is turn k+1's input: for a near-identity map with a systematic per-turn difference (a pitched frame: the device fuses the frame change, the host does not) the difference adds linearly in the turn count; for a stable focusing cell it random-walks as sqrt(turns); for a strong beam its gradient amplifies it. The suite measures 3 turns and the validation script defaults to `OCTOPUS_CONTRACT_TURNS=2`, so neither sees it, while `docs/current_runtime.md` ("A pin that compares the two backends consults the class instead of claiming bit for bit") invites consumers to use the bound as a property of the kind. Measured (`probe_cuda.jl` B3, CPU against CUDA, worst ulps of scale over the ulp-class coordinates; `V` = violates the declared bound):

    fixture                              bound   t=1     t=3     t=10     t=30      t=100
    marker x_pitch=1 mrad (one element)  1024    95.5    223.5   671.5    1951.5 V  6431.5 V   (px; linear in turns)
    FODO quad(1.7) drift quad(-1.7) drift  32     7.5    12.0    45.0 V   74.5 V    78.0 V     (~sqrt(turns))
    drift, elliptic thin strong beam, drift 2048  390.2  5986.2 V 8850.0 V 10269.5 V 8005.0 V  (px 3007 at t=3 = todo row 36)
    sbend example (pole faces)             64     1.0     2.0     4.0      5.0       16.0
    drift, round strong beam, drift         8     2.5     3.0     3.0      4.0       4.0
    rf cavity + drift                       8     0.1     0.5     0.5      1.0       2.0

The pitched marker's 223.5 at three turns is the declaration's own measured figure (misalignment.jl: "223 ulps of px's scale over 3 turns for a 1 mrad pitch"), so the regime, not the kernel, moved. Classes 8 and 10 of the brief.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U20/probe_cuda.jl`, section B3: `MarkerSpec(x_pitch=1.0e-3)` tracked 30 turns on the suite's `_contract_default_initial_rep(400, Float64)` state through `execute!(TrackingTask((spec,); policy))` on CPU and CUDA reports `px` at 1951.5 ulps of its scale against the declared 1024 (`_cross_backend_violations` non-empty); the FODO line reports `y` at 45.0 against 32 at 10 turns. Equivalently, run `validation/tracking_backend_consistency.jl` with `OCTOPUS_CONTRACT_TURNS=30`.

### LEAD U20-2 [Moderate, confidence high] src/math/SpecialMath.jl:14
Claim: the two backends evaluate the Faddeeva function of the elliptic beam-beam kick with two different algorithms -- `faddeeva_w` = `erfcx(-im z)` from SpecialFunctions on the CPU (`src/elements/strong_beam.jl:1200`), the N=32 Weideman form `faddeeva_w_upper_reim` on CUDA (`src/track/strong_beam_track.jl:839`) -- and this algorithm difference, not rounding, accounts for the elliptic beam's cross-backend class, which the rule statement in Track.jl and the kind's `why` attribute to FMA fusion, libm and cancellation; and no accuracy figure for the Weideman path is stated anywhere outside the frozen history.
Mechanism: `CrossBackendRounding`'s docstring (Track.jl:175-198) states THE RULE as "the two backends ... differ in two ways", fusion and libm; the elliptic `ThinStrongBeam` declaration (strong_beam.jl:248-262) explains its 2048 by "`exp` on each backend's libm" and "the difference of two Faddeeva functions cancels and amplifies the last bit". But the CPU kick calls a different special-function implementation than the device kick, with a relative disagreement of up to 3.1e-13 on |w| (the re-run harness) and 2.9e-14 on the suite's arguments (|z1| in [0.08, 0.82]). Evaluated on one backend with identical surrounding arithmetic, swapping only the Faddeeva route moves Kx by 599.5 ulps of its scale and Ky by 209.9 on the suite's 400-particle state (`probe_cpu2.jl`) -- the size of the whole measured CPU/CUDA class (the declaration's "412 and 331", the routing testset's 66-630). Consequences: the elliptic class is an algorithm floor that no rounding work (fix batch 3 unit K style) can lower; it scales with the Weideman error, not with eps; a `:ulp` label implies the two kernels compute the same function to rounding, which they do not; and the round beam (no Faddeeva call, class 8) differs from the elliptic one (2048) for this reason first. Separately, `faddeeva_w_upper_reim`'s and `faddeeva_w_approx`'s docstrings give no precision figure ("fixed-order Weideman rational approximation"), and the 3.1e-13 floor appears only in `docs/history/` (the 2026-08-05_b U14 report, where it was already noted as unstated) -- the beam-beam kick's accuracy on CUDA is a number with no home in the live documentation. Classes 9 and 14 of the brief; a seam between this region and the two kick kernels, noted and left to the auditor.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U20/probe_cpu2.jl` prints `Kx differs by 599.5 ulps of its scale, Ky by 209.9` and `bitwise equal kicks: Kx 14 of 400`; `grep -n "faddeeva_w" src/elements/strong_beam.jl src/track/strong_beam_track.jl` shows the two routes; `grep -rn -i "weideman\|3.09e-13" docs/*.md docs/theory docs/design validation/README.md` returns nothing.

### LEAD U20-3 [Minor, confidence high] src/track/phase6d_track.jl:136
Claim: `_track_line_elementwise!` and `_flush_cuda_fused_segment!` (phase6d_track.jl:136-210, eleven methods) are a second, uncalled walker over the line whose semantics disagree with the live one, `_track_cuda_policy_elementwise!`.
Mechanism: no caller exists in `src/`, `test/`, `validation/`, `examples/`, `ext/`, `profiling/` or `docs/` (only the definitions match). Where it differs from the live walker: (1) the context-taking forms drop the context for a lifted element (`track!(rep, elem, 1, backend)` at lines 177 and 205), so a lifted `LumpedRad` with excitation would re-enter the compatibility launch with a fresh `TrackingContext()` at turn 0 on every call -- the U14-1 replayed-draw shape, in dead code; (2) a nested tuple is flattened into the fused segment without a flush (lines 150-155), where the live walker flushes at a tuple boundary (line 382-384); (3) it reaches the deprecated backend-tag `track!` rather than the policy one, so no receipt is recorded. A dead twin of a routing walker is exactly where the next CUDA routing fix is applied to the wrong function (brief class 3; the 2026-10-18 fix M touched the live walker only, which is correct, and left this one). Dead, so no run is affected today.
Repro: `grep -rn "_track_line_elementwise!\|_flush_cuda_fused_segment!" src test validation examples ext profiling docs` lists definitions in `src/track/phase6d_track.jl` only (0 call sites); `grep -c "_track_line_elementwise!" src/track/phase6d_track.jl` = 11.

### LEAD U20-4 [Minor, confidence high] src/track/Track.jl:394
Claim: `_cross_backend_agreement` states `ulps_of_scale` in Float64 ulps whatever the representation's element type, so no `CrossBackendRounding` class can be checked on a Float32 beam and the suite already hand-rolls a second ulp measure to get around it.
Mechanism: every coordinate is widened with `Float64(a[i])` and the divisor is `eps(scale)` with `scale::Float64`, so one Float32 ulp reads as 2^29 = 5.4e8 "ulps of scale" against bounds of 4 to 16384; the docstring and `CrossBackendRounding` say "ulps OF THE COORDINATE'S SCALE" without naming the type. The "One precision rule" testset computes its own `ulps32` by hand (test/runtests.jl:13148, bound 1024) instead of consulting the class, which is the hand-copy the invariants forbid, and the Float32 kernels (31 of 31 kinds run in Float32 on both backends per current_runtime.md) have no declared cross-backend class at all. Brief classes 2 and 8.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U20/probe_cpu.jl`, section A3: two Float32 reps one Float32 ulp apart in x give `ulps_of_scale = 5.36870912e8` and a violation against a 4-ulp class; `grep -n "ulps32" test/runtests.jl` shows the parallel measure.

### LEAD U20-5 [Minor, confidence high] src/track/radiation_track.jl:52
Claim: the radiation compatibility launch is a third copy of the grid-stride tracking loop with its own launch shape and its own context semantics -- a hardcoded 256-block cap where the fused route resolves blocks from the occupancy API, and `index` passed to `_track_lumped_rad_context` without `ctx.index_offset` where the fused kernels key on `turn_ctx.index_offset + index`.
Mechanism: `track!(rep, ::LumpedRad, turns, policy::ResolvedCUDAExecutionPolicy)` (line 50-59) computes `blocks = min(cld(N, threads), 256)` and forwards to the backend-tag method, which builds its own `TrackingContext()` (offset 0) and launches `cuda_track_lumped_rad_kernel!` (line 12-22), whose body passes `index` as the particle id. Self-consistent as long as the context is the one it builds, but a divergence from the fused kernel (phase6d_track.jl:299-301) waiting for the day a sharded context reaches it; the same 256 cap sits on the four strong-beam sites (strong_beam_track.jl:598, 653, 694) while `_cuda_fused_occupancy_blocks` governs the fused launches. Reachable only through the deprecated single-element `track!(rep, elem, turns, CUDABackend)` and the four-argument policy form (the public keyword `track!` and every task take the context-taking method, which fuses the element), and the receipt names it (`:cuda_radiation_compatibility_launch`, `requested_blocks`), so this is loud, not silent. Brief classes 2 and 4.
Repro: `grep -n "256)" src/track/radiation_track.jl src/track/strong_beam_track.jl` (four hardcoded caps); `grep -n "index_offset" src/track/radiation_track.jl` returns nothing while `grep -n "index_offset + index" src/track/phase6d_track.jl` returns the two fused kernels.

### LEAD U20-6 [Minor, confidence low] src/track/Track.jl:315
Claim: `_rounding_written_over` keeps the inner element's `:bitwise` class for every coordinate outside the wrapper's `written` set, ignoring that the inner now READS coordinates the wrapper parted -- the spreading the line rule applies (Track.jl:336-341) and the wrapper rule does not; no registered kind triggers it today, so this is latent.
Mechanism: for a longitudinal offset the frame change writes (x, y, z) through a fused face drift and the rule keeps px, py from the inner; a thin quadrupole's `px - k x` then reads a ulp-class x into a coordinate declared `:bitwise` (`ThinQuadrupoleSpec(k1l=0.37, z_offset=ds)` compiles to class `ububu-`). Measured: the face drift parted x in 0 of 1e5 particles for ds = 1e-3, 1e-2, 0.1 and 0.5 m with the suite's angles and with angles x50, so px never parted and the declaration held everywhere tried (`probe_cuda3.jl`); the only kind whose wrapper class keeps a `:bitwise` coordinate under a ulp frame is the damping-only radiation element (z, pz under a roll, `probe_cpu.jl` A5), whose z and pz read only themselves, so that keep is correct. The rule is sound for the current kinds by inspection, not by construction. Class 10 of the brief; recorded so the next kind with a bitwise coordinate that reads a transverse one is checked.
Repro: `probe_cpu.jl` section A5 prints `kinds whose wrapper class keeps a :bitwise coordinate the line rule would make :ulp: ["lumped_radiation"]`; `probe_cuda3.jl` prints `parted x=0 px=0` for all sixteen (beam, ds) rows.

Style, not leads: the Box-Muller pair is written three times (`counter_normal_pair`,
`splitmix_normal_pair`, `octopus_normal_pair`, counter_rng.jl) and the fused emitter three
times (`fusedTrack` x2, `fusedTrackLuminous`, fused_track.jl); `faddeeva_w_upper_reim` is
exported with a documented `imag(z) >= 0` precondition and no guard (the guarded entry is
`faddeeva_w_approx_reim`); the `_track_cuda_elementwise!` ownership is not in the suite's
`wrapper_walks` single source (it is CUDA-only, and its fallback throws by name, so a missing
method is loud at first use rather than at the tripwire).

## Clean

- Philox4x32-10 (hypothesis 3): round function `(hi1 ^ c1 ^ k0, lo1, hi0 ^ c3 ^ k1, lo0)`
  with M0 = 0xD2511F53, M1 = 0xCD9E8D57, Weyl W0 = 0x9E3779B9, W1 = 0xBB67AE85, ten rounds,
  key bumped after each round -- compared against Random123 by reading; the three upstream
  `kat_vectors` reproduce bit-for-bit in `probe_cpu.jl` A1 (`6627e8d5 e169c58d bc57ac4c
  9b00dbd8`, `408f276d 41c83b0e a20bc7c6 6d5451fd`, `d16cfe09 94fdcceb 5001e420 24126ea1`), the
  suite asserts `philox4x32_self_test()` in "Philox4x32-10 matches the Random123 known-answer
  vectors" (test/runtests.jl:24452) and `validation/counter_rng_validation.jl` runs it first.
  Counter = (particle lo, hi, turn lo, hi), key = splitmix(seed) xor splitmix(rng_id + c) xor
  splitmix(component + c'); the XOR collision class is recorded as accepted (lines 477-482).
- Stream independence (hypothesis 3): the id registry (`next_rng_id!` skipping explicit claims,
  `claim_rng_id!` warning across classes and on an auto-assigned id, the 64 kB class ring, the
  floor after reset) read in full and consistent with its docstrings; every call site in `src/`
  passes components 1..6 (radiation), 1..2 (BPM), the beam's `dim` and the rules' `k` with
  their own class -- no component 0 (which would hit `UInt64(-1)` in the pair key). 1440 of
  1440 grid tuples distinct.
- Uniform draws strictly inside (0, 1) on both types: measured endpoints `2^-53 ..
  prevfloat(1.0)` and `2^-24 .. prevfloat(1f0)`; `Float64(bits) + 0.5` exact at 52+1 bits,
  `Float32(bits) + 0.5f0` exact at 23+1 bits.
- NaN payloads across backends (a concern raised while reading `a[i] === b[i]` at Track.jl:383):
  measured identical bits on this GPU for Float64 and Float32 -- the literal, `NaN + 1`
  (7ff8.../7fc00000) and `0/0` (fff8.../ffc00000) -- so a particle NaN on both sides is `===`
  and the docstring's "a lost particle NaN on both sides included" holds (`probe_cuda.jl` B1).
- The fusion-exact declarations (hypothesis 2): at 1e5 particles the thin quadrupole (k1l =
  0.05 and 0.37), thin dipole, hkicker and the thin-quad+hkicker line part in 0 particles;
  the normal-plus-skew quadrupole parts in 11401 (the declaration's own number), the thin
  sextupole in 130, the L = 0.35 drift in 5881 of 1e5 in x (the rule's "7%"), the L = 0.5
  drift in 0 -- the declarations in `thin_elements.jl:104-124` and the Track.jl rule's
  power-of-two remark are measured true.
- The line rule itself (not its regime): `_cross_backend_rounding(ops::Tuple)` composes
  `:untouched` only when no member writes, `:bitwise` only when all members are, the maximum
  bound, and the empty line as the identity; `_rounding_class` refuses a non-partition, a
  bound under 4 with a ulp coordinate, a nonzero bound without one, and an empty `why`.
- CUDA elementwise routing (hypothesis 1): `_requires_cuda_elementwise` forwards through
  `MisalignedElement`, `RefTilted`, `TurnModulated` and `CompositeLine` in both forms (lines
  128-134), `LumpedRad` answers true contextless and false with a context (radiation_track.jl:3-5)
  so a context is built once and advanced per turn (phase6d_track.jl:452-456, the U14-1 fix in
  place); every element answering true in the context-taking form owns
  `_track_cuda_elementwise!` -- the two strong beams (strong_beam_track.jl:304, forwarding the
  stream), the three wrappers (to `_track_cuda_wrapped_strong_beam!`, which throws by name when
  no beam is reachable) and `CompositeLine` (walked under the SAME context); the fallback
  throws by name (suite part (f)). Flush order: the fused segment is flushed before a lifted
  element and before descending a nested tuple, whose recursion owns a fresh segment, and the
  tail is flushed last -- line order preserved. Streams: segments and lifted launches take the
  same `stream`, and an explicit stream is synchronised before the host-side luminosity fold.
  The suite's wrapper-walk tripwire derives the wrapper set from the `inner` field and checks
  `_requires_cuda_elementwise`, `_cross_backend_rounding`, `_requires_tracking_context`,
  `adapt_structure` and twelve more against it and `CompositeLine` (test/runtests.jl:10755-10800).
- `_reject_contextless_tracking` is wired on both contextless policy paths (CPU line 62, CUDA
  line 434; U14-8 closed) and `_requires_tracking_context` descends all four containers
  (aperture.jl:407-418).
- The occupancy cache key `(device, typeof(rep), typeof(elems), ctx === nothing, threads)` is
  sufficient for a kernel whose code depends only on types; `blocks = min(cld(N, threads),
  active_per_sm * sm_count)`.
- `TrackingContext` is isbits with the shard offset threaded identically into the CPU loop
  (phase6d_track.jl:52-54) and the CUDA kernel (299-301); `_shard_context` leaves a
  caller-set offset alone outside a multi-process run.
- `_numeric_type_parameter` is `@generated` (a constant per concrete type), refuses two
  distinct numeric parameters, and `_typed_form_names` derives the remedy from
  `ELEMENT_META_BY_KIND`.
- Longitudinal conversions against `docs/theory/lattice_hamiltonian_and_conventions.md`
  Section 2: `_z1_of`/`_z_of` implement `z2 = beta0 z1`, `z3 = z1 beta - s(beta/beta0 - 1)`,
  `z4 = beta z1` and their inverses; `_delta_from_pt`/`_pt_from_delta` are the note's two
  relations in the cancellation-free forms (U14-4), `_beta_of` is `(1+delta)/(1/beta0 + pt)`
  with the reciprocal cleared; the kernel-reachable radicand returns NaN rather than throwing
  and is guarded with `real(rad)` for complex-step inputs; `_check_reference_pair` is called
  by both cavity constructors (rf_cavity.jl:349, 767). The suite's "Longitudinal conventions
  convert exactly" testset exists (test/runtests.jl:15478).
- Faddeeva (hypothesis 3): the Weideman branch is Weideman's formula with L = 2^(-1/4) sqrt(32),
  the continued-fraction and asymptotic branches are a faithful port of S. G. Johnson's
  Faddeeva.cc (region test, the `3.9 + 11.398/(0.08254 x + 0.1421 y + 0.2023)` term count, the
  two far-field forms re-derived here); the committed BigFloat harness re-run on this tree
  reproduces the 2026-08-05_b accuracy table exactly (3.092e-13 worst relative on |w|, the
  numbers under Provenance). The reflection `w(z) = 2 exp(-z^2) - w(-z)` for `imag(z) < 0`
  is correct and measured (9.1e-14 across quadrants).
- `radiation_track.jl`: the compatibility path draws through the counter RNG with 0-based
  turns (U14-7 closed), and `_requires_cuda_elementwise(::LumpedRad, ctx) = false` keeps every
  policy-routed radiation element in the fused launch.

## Unchecked

- `src/track/strong_beam_track.jl` (954 lines) is outside this unit; only the seams named under
  Provenance were read. Whether the device-view adaptor, the wrapped kernel and the
  luminosity fold are correct is not claimed here.
- Device-IR compilability of every branch (brief class 4) was exercised only to the extent the
  probes launched kernels (the fused kernel for the fixtures listed, the wrapped and bare
  strong-beam kernels through `execute!`); no per-branch IR audit of `longitudinal.jl` or
  `counter_rng.jl` was run beyond those launches.
- The multi-process shard path (`_shard_context`, `_mp_resolve_shard`, `index_offset != 0`)
  was read, not executed; no MPI run was made.
- The id registry's locking was read, not stress-tested under concurrent constructors.
- The deprecated backend-tag entry points (`track!(..., CUDABackend)`,
  `track!(..., CPUThreadsBackend)`) were read, not executed.
- `validation/counter_rng_validation.jl`'s moment checks were not re-run (the known-answer
  half was, through `philox4x32_self_test`).
- The Float32 Box-Muller tail truncation at `sqrt(-2 log(2^-24)) = 5.77 sigma` (Float64: 8.57
  sigma) was noted, not quantified against any consumer's tolerance.
- The counter-RNG receipts (what a run records about seed and method, brief class 11) belong
  to the task layer and were not followed there.
