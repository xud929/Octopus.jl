# Crab-cavity noise neighbour audit: fix batch 3 (2026-10-17)

**Status:** complete 2026-10-17: the three units merged, the integration fix
committed, both CPU arms of the full gate green with CUDA active on ef5d20f;
push pending the owner's word (an addendum records the push and its CI run).

**Scope.** The owner's follow-up on the four rows fix batch 2 left open
([batch 2](crab_cavity_noise_audit_fixes_batch2_2026_10_16.md), pushed as
c061088): fix rows 2 to 4 (the cross-backend rounding classes stated nowhere,
the strong-strong physics-line result boxing, the untyped marker in a Float32
line), at first keeping row 1 (the curved drift, the bend and the solenoid's
cancelling `z` form) open as "not urgent", then, once the two units were
running, "fix the item 1 too" (owner, 2026-10-17). Method as before: the
protocol's fix phase, three parallel units in their own worktrees, integrated
on `crab-noise-audit`, gated as one batch.

## 1 Owner decisions (2026-10-17)

1. **Cross-backend rounding classes (row 2):** one declared source per
   element kind (which coordinates its map leaves bitwise identical between
   CPU and CUDA, which are of the ulp class and through which function),
   checked by a CUDA-active measurement tripwire, consumed by the
   backend-consistency script's per-kind expectations and by the suite's
   formerly observational "bit for bit" pins; documented where
   `current_runtime.md` describes the backends.
2. **The untyped marker (row 4):** the marker completes the one precision
   rule like every other kind (a typed form with the Float64 floor, the
   runtime carrying its type, its wraps built in that type, a mismatched beam
   refused by name).
3. **The strong-strong physics line (row 3):** the per-line physics and
   observer tuples are computed once per compilation and cached with the
   blocks, so the once-per-`execute!` walks cost nothing after the fill; the
   turn loop is untouched.
4. **The curved drift, the bend and the solenoid (row 1):** first left open
   by the owner's call, then opened as the batch's third unit: a
   cancellation-free longitudinal update derived per kernel, pinned in ulp
   against BigFloat, the symplecticity and backend cases re-run, the pins
   that probe `z` through those kinds re-walked and re-derived, as unit G did
   for the straight drift; IEEE-only forms, so the rounding classes unit I
   declares stay valid.

## 2 Units and what landed

Each unit reproduced its defect on the unfixed tree c061088 first, wrote its
regression testset and showed it red there, fixed, re-ran its targeted
testsets and the source sweeps, re-walked the call sites, and committed on
its branch; the integrator merged the branches onto `crab-noise-audit`. Unit
reports and logs: `result/audit_crab_noise_2026_10_16/fixes/` (git-ignored
scratch; the numbers are quoted here).

### Unit J: the strong-strong physics line cached per compilation (row 3)

Branch `fix-ss-physics-line`, commit 465dfb5. Reproduced on c061088:
`_strong_strong_physics_line` 12,064 B per call on the nine-type pair (41
physics elements per line, a 4,928 B tuple), `_line_observers` 32 B.
Landed in `src/tasks/strongstrong/interface.jl`: `StrongStrongBlocks <:
AbstractVector{Any}` wraps the `Vector{Any}` of blocks together with the
line's physics and observer tuples, built once at the end of
`_split_strong_strong_line`; the two walks are field reads on it; the turn
loop, the plan caches, the cache entry's shape and the call sites are
unchanged in text. After: 0 B per call for both; `execute!(turns = 1)` on the
pair 507,088 to 386,880 B; the fingerprint (physics-line digests, beam
coordinates after three turns) identical. Testset "The strong-strong physics
line and observer tuples are cached per compilation and cost nothing per
execute!": red on c061088 (19 pass, 1 fail: `12064 <= 64`), green after (20
of 20); it pins the same object across an `execute!`, the refresh on a knob
assignment (a knob-free line stays cached) and on a spec mutation; batch 1's
`isa Vector` pin re-pinned on the wrapper. Targeted: the strong-strong
family, unit F's walk pins, the audit testset and the precision testset
green; sweeps green.

### Unit I: the cross-backend rounding classes and the typed marker (rows 2 and 4)

Branch `fix-backend-class`, commit 9a4e3d6, 26 files. Reproduced on c061088:
no stated classification anywhere, the suite's "bit for bit" pins written by
observation; the marker's trait `nothing`, an untyped marker accepted in a
Float32 beam. Landed: one declared source per runtime op type,
`_cross_backend_rounding(op) -> CrossBackendRounding` (`src/track/Track.jl`:
a class per coordinate, bitwise or ulp or untouched, an `ulp_bound` and a
`why`; a partial or double declaration, a bound under 4 or a missing reason
is refused), declared beside every runtime struct, wrappers passing their
subject through and a line's coordinate bitwise only if every member's is;
the TRIPWIRE measures every registry example on CPU and CUDA (Float64,
spread particles, a few turns) and holds each coordinate to its class; the
backend-consistency script takes per-kind expectations from the declaration
(33 instances within their classes, the composed line CPU/GPU 6.3e-16) and
its header states the rule; the formerly observational pin "CUDA surveyed
cavity matches CPU bit for bit" now holds the line's derived class, its
premise (`z` and `pz` ulp class) pinned. The measured rule, now written
down: the device compiler fuses `a*b + c` into one FMA (its choice which),
so a coordinate is bitwise only where no fusable product-sum touches it (a
drift of `L = 0.5` was bitwise because 0.5 is a power of two: at `L = 0.35`
7% of particles differ, at `L = 100` 26%), and the two libms differ by 1-3
ulp on transcendentals. The classification, bounds in ulps of the
coordinate's scale: thin dipoles, quadrupoles and kickers bitwise where they
write; thin sextupoles and multipoles 4; the straight drift, the thin RF and
crab cavities, the chromaticity kick, the patch, the dispersion maps, the
round thin strong beam and exciting radiation 8; the Linear6D dense rows 8;
the straight magnets 32; the accelerating cavity 128; the round Gaussian
strong beam 64, the elliptic 2048; the solenoid 4096; the sector bend and
the curved frame 8192; the Lorentz boosts 16384; the rotation wrap 1024 and
the roll 32. Three declarations lost to the measurement and were changed
(the crab map's `pz`, the elliptic strong beams 412 to 2048, the
accelerating cavity 31.5 to 128). The large bounds of the bend, the solenoid,
the boosts and the elliptic beam record the cancellation class unit K
addresses; the classification records the amplification, it does not remove
it. The marker: `Marker{M,T}` typed, `MarkerSpec{T}` and `numeric_type`
with the Float64 floor, its wraps built in its type, an untyped marker
refused in a Float32 beam like every kind; unit H's pins now say no kind
lacks a type (the two containers aside). Testset "Cross-backend rounding
classes declared per kind and checked by measurement, and the marker
completes the one precision rule": red on c061088 8 pass, 16 fail, 9 error
of 33; green after 180 of 180, CUDA active. Targeted: 30 of 32 CUDA-active
testsets green (two runner artefacts), both validators, snapshot unchanged,
sweeps green after a boxed closure was rewritten, a fast lane on the unit's
tree green (331 rows). Open: the bounds are stated for the contract fixture
over a few turns and accumulate as a random walk over many; the Linear6D and
radiation registry examples exercise trivial branches, their dense and
exciting kernels measured by the script's instances only.

### Unit K: cancellation-free longitudinal updates for the curved drift, the bend and the solenoid (row 1)

Branch `fix-curved-z`, commit 36b8652, 5 files. Reproduced on c061088 against
the same kernels evaluated in BigFloat over a 100-particle sweep (x, p ~ 1e-3),
in ulps of max(|z|, |excess|) because the output z crosses zero: the curved
drift 2835 (h = 1e-3, L = 0.5), the bend 5190 (h = b0 = 0.3, L = 2), the
solenoid 4855 (ks = 1.7, L = 1.3), the curved solenoid 768; and on the same
bend kernel two transverse cancellations the row had not named, x 5863 and px
1225 ulp (the `C1 R - C2` bracket and the `pxr - b0 q C1` exit momentum).
Landed: each kernel forms the excess E = (1 + pz) Delta - L from the quantities
that make it small and applies z - E -- the curved drift through an identity in
S1 = (sin hL - hL)/h (a series for |hL| < 1), the bend as the design orbit's
own excess plus the particle's departure angle (a Kahan difference of products
through `_atan2`) plus pz Delta, with its exit momentum formed around the
design orbit (kappa = h - b0, exactly zero on a sector bend's axis) and its
transverse bracket expanded in pxn + px, the drift-like regime |b0| <= |h|/2
and b0 = 0 kept on the direct form; the solenoids in the kinetic momenta;
`_curv_vers`'s closed branch 2 sin^2(u/2)/h. After: 4.7, 15.6 (the weak bend
h = b0 = 0.05: 52.6, the deviation angle's rounding over b0), 0.5 and 2.1 ulp;
the bend's x 2.1 and px 1.6. CPU/CUDA on the backend-consistency line 2.9e-14
to 5.3e-15 (global relative error): the two backends' fused multiply-adds had
less cancellation to amplify. Two defects of the rewrite were found by the
targeted run and fixed before the commit: `atan(::Complex, ::Complex)` has no
method (the suite's complex-step symplecticity), and b0 = 0 with h = 0 reached
a 1/b0 term. Two pins moved and were re-derived, not loosened. The b0 -> 0
slope pin resolves a 1e-15 change of a momentum of order 0.2, and the
design-orbit form costs two more roundings at that scale (2.8 ulp of px against
the drift, 0.4 before), so the pin's widening rtol table became an explicit
floor of eight ulp of the exit momentum with rtol 1e-8 (24 of 24; the defect it
guards is still 1e14 away). The lattice-magnets pin held the bend's
complex-step Jacobian bitwise equal with and without the perpendicular-face
fringe: that fringe is second order, so its only trace is the step's own
square (1e-60) in an entry that is exactly zero otherwise, which the old
bend's rounding residual at the design orbit swamped and the exact bend keeps
(5.7e-64 measured); the pin is now a bound far below roundoff, 1e-40, where a
linear effect would be of order one. The first fast lane on the unit's tree
found that pin six minutes in -- "Lattice magnets", the owning file's testset,
was not in the targeted list (lesson in `experiences.md`). Testset "Cancellation-free longitudinal updates for the
curved drift, the bend and the solenoid": red on c061088 1425 pass, 18 fail, 1
error; green after 1463 of 1463. Targeted: 24 testsets green through the stage
runner, CUDA active (symplecticity, PTC, bend, solenoid, lattice cell,
curvature, patch, misalignment, survey, virtual drift, precision rule,
architecture); two runner artefacts (a suite-level helper; ForwardDiff not
loadable in package mode) covered by the fast lane; the backend-consistency
script with the GPU contract required, all six checks; sweeps green; the
second fast lane on the unit's tree green (331 rows, 24 min). Theory notes
`lattice_hamiltonian_and_conventions.md` 5.2 and `solenoid.md` 4.4 record both
forms with the numbers. Open: the drift-like regime keeps the direct form (611
ulp at b0 = 1e-4 over the sweep, bounded at 4096 by the pin); the weak bend's
1/b0 floor is intrinsic to Delta = (hL - phi)/b0.

### Integration: unit I's classes re-measured after unit K

Unit I declared the curved frame and the solenoid at 8192 and 4096 ulps for
the cancellation class unit K removed, and its `why` texts named the removed
forms. On the merged tree the backend-consistency script's per-kind table
read the curved drift's z 83 to 1, the sbend's z 334 to 3, its x and px
unchanged at about 1050 and 1420; a variant probe
(`fixes/K/sbend_variants_merged.log`, CPU against CUDA, 1e4 particles, 3
turns) placed those in the pole-face maps -- `_rot_xz(e)` turns the momentum
by an O(sin e) share of ps and `_wedge(-e, b1)` turns it back, so the last
bits of two O(sin e) intermediates land on the O(px) result: 829 to 1697 ulps
with e1 = 0.02, e2 = 0.015, with or without the hard-edge fringe -- while the
bare sector bend, the curved drifts and the bend with k1 are within 2 to 10
ulps and the solenoids within 7 to 25. The declarations now say so: a bend
with pole-face angles 8192 (the face maps), any other curved frame or bend
64, the solenoid 128 (the widest measured instance times four, rounded up,
the rule `src/track/Track.jl` states; its text and `current_runtime.md` carry
the new figures). The tripwire and the script's per-kind arm were re-run on
the rewritten declarations: the tripwire's pins on the declared table moved
with them (two more pin the body and the face branches), 182 of 182, CUDA
active; the script's per-kind arm, 33 instances within their classes.
Committed on `crab-noise-audit` as ef5d20f.

## 3 Verification

- Each unit: its regression testset red on c061088 and green on its tree;
  its targeted testsets through the stage runner, CUDA active; the source
  sweeps; a fast lane on the unit's tree (units I, J and K; K's second after
  the lattice-magnets pin).
- The merged tree (`crab-noise-audit` at 58fc8c6, then ef5d20f): the three
  units' testsets together with their neighbours (I's tripwire 180 of 180 and
  182 of 182 after the integration fix, J's 20 of 20, K's 1463 of 1463,
  "Lattice magnets" 83 of 83, the b0 -> 0 testset 24 of 24, the surveyed-cavity
  pin 6 of 6, the solenoid and lattice-cell testsets), "Architecture integrity"
  28 of 28, the source sweeps, the backend-consistency script with the GPU
  contract required (six checks, 33 per-kind instances within their classes),
  and the three ForwardDiff testsets the fast lane skips, run in a temporary
  environment that can load ForwardDiff (39 of 39, 9 of 9, 15 of 15; the
  curved-frame routing testset differentiates SBend maps through unit K's
  design-orbit branch).
- The two-arm full gate on ef5d20f, the arms one after the other in this
  worktree (native, then `OPENBLAS_CORETYPE=Haswell julia -C haswell`), four
  threads, CUDA active: native arm exit 0, 348 testset rows, 153,668 passes,
  63 min (19:16 to 20:19); AVX2 arm exit 0, the same 348 rows and 153,668
  passes, 61 min (20:19 to 21:20); no failed, errored, broken or skipped row in
  either (`result/gates/turnmod/full_gate_{native,avx2}_audit_gateD.log`). The
  record commit that follows is markdown only and carries a fast lane on the
  final tree.
- Not verified here: the AVX2 arm's identity table on the CI runner (read
  from the check-run annotations after the push); a GPU other than the RTX
  4500 Ada this machine has.

## 4 Ledger

- `docs/todo.md`: five rows retired to
  [`todo_ledger_archive.md`](todo_ledger_archive.md) under "Rows retired by
  the crab-cavity noise audit fix batch 3 — closed 2026-10-17", each with its
  closing measurements: the four follow-up rows of batch 2 (the cross-backend
  rounding classes; the untyped marker; the strong-strong physics-line
  boxing; the cancelling longitudinal form of the curved drift, the bend and the solenoid) and the phantom-ledger-row item of 2026-10-15,
  which the audit's U5-3 and U5-6 had fixed without retiring. The pointer row
  records the batch; after it, the audit's open queue is the pointer row
  alone.
- `docs/README.md`: this record indexed beside the audit's and the two
  batches'.
- The batch 2 record carries its addendum (pushed as c061088, CI run 461
  green, batch 3 opened); its body is unchanged.
