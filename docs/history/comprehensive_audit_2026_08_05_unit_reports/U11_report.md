# U11 report — elements: beam_line / aperture / thin_elements / radiation / misalignment

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ e0f6bda (branch main, clean).
Probes: /tmp/claude-320114/-cfs-ad-dxu-Library-Julia-Octopus/94771dda-fd24-4438-922e-a4bd8afa2361/scratchpad/U11/
(p1_beamline.jl, p2_aperture.jl, p2b_threads.jl [--threads=8], p3_radiation_thin.jl,
p4_dual_misalign.jl [ForwardDiff env]). All CPU, < 60 s each.

## Coverage

Read every line of:
- src/elements/beam_line.jl 1–587
- src/elements/aperture.jl 1–583
- src/elements/thin_elements.jl 1–346
- src/elements/radiation.jl 1–313
- src/elements/misalignment.jl 1–293
- docs/theory/beam_line_composition.md 1–542, aperture_and_particle_loss.md 1–405,
  misalignment_and_patch_maps.md 1–444 (all in full)

Supporting reads (targeted, to trace every walker/caller of the audited code):
src/tasks/Tasks.jl 100–690 (all line walkers, loss-record wiring),
src/track/Track.jl 1–90, src/track/fused_track.jl 1–100, src/track/phase6d_track.jl 40–110,
src/knowledge/Knowledge.jl 40–130, 400–440, 860–960 (ElementSpec, setproperty!, compile_runtime),
src/knobs/Knobs.jl 860–917, src/elements/linear_maps.jl 1–120 (`_spec_params`),
src/elements/lattice_magnets.jl 30–200, 740–935 (`_lattice_kick`, `_fold_named_strengths`),
src/elements/ref_tilt.jl (whole), src/beam/Beam.jl 190–250, src/policies/Policies.jl 220–244,
test/runtests.jl (aperture/misalignment/beam-line testsets, excerpts).

## Leads

### U11-1 — nested composite line contributes L = 0 to every arc-length walker — MEDIUM
- beam_line.jl:361–370 (`s_positions`), 543–544 (`total_length`), and Tasks.jl:223–232
  (`_collect_aperture_s!`) all read `getparam(entry, :L, 0.0)`; a placement whose spec is an
  own-state (non-dissolved) sub-line (a cryostat) stores no `:L`, so its physical length vanishes.
- Measured (p1): `cryo = BeamLine("CRYO", QuadrupoleSpec(L=0.4), DriftSpec(L=1.0); x_offset=2e-4)`,
  `arc = BeamLine("ARC", cryo, DriftSpec(L=1.0))`:
  `s_positions(arc) = [0.0, 0.0]` (physical `[0.0, 1.4]`); `total_length(arc) = 1.0` (physical 2.4);
  `_aperture_s_positions((cryo, drift, aperture)) = [1.0]` (physical `[2.4]`).
- Violated invariant: `s` is "the summed L of everything ahead" (docstring), and loss-file
  `aperture_s` is meant to be readable without the producing script. Knock-on: a *misaligned parent*
  line's own survey geometry (beam_line.jl:558–561 builds `geom` with `:L => total_length`) uses the
  short length, so its exit-face frame is wrong by the nested assembly's length.
- Note: the walkers agree with *each other* (no T3-style crash); they are consistently wrong.

### U11-2 — `reverse(line)` silently drops the line's own state — MEDIUM
- beam_line.jl:294–295: `Base.reverse(spec) = BeamLine(line_name(spec), reverse(line_entries(spec))...)`
  rebuilds through the positional constructor with no kwargs, so every own parameter
  (x_offset, tilt, misalign_convention, tracking hints…) is discarded and the result dissolves.
- Measured (p1): `getparam(reverse(cryo), :x_offset)` = MISSING (source: 2.0e-4);
  `reverse(reverse(cryo))` ≠ `cryo` (misalignment gone both times).
- Violated invariant: reflection is "order only" (file header 21–24, note §2) — it must not change
  what the line *carries*, only the order of its contents. A reflected cryostat loses its rigidity.

### U11-3 — folded-strength override guard misses every thin kind — MEDIUM
- beam_line.jl:121–127: `_FOLDED_NAMED_STRENGTHS` lists only `:quadrupole, :sextupole, :octupole,
  :sbend, :multipole`. Thin kinds fold `k0l…k5sl` into `knl`/`ksl` at construction
  (thin_elements.jl:101–110), so a placement override named `k1l` is exactly the
  written-reported-never-read no-op `_reject_folded_override` (beam_line.jl:97–119) exists to catch.
- Measured (p1): `entry.k1l = 999.0` on a `ThinQuadrupoleSpec(k1l=0.05)` placement: ACCEPTED;
  tracking identical with and without the override (`px_out = 5.0e-5` both). The thick counterpart
  (`entry.k1 = 999.0`) is correctly rejected with ArgumentError.

### U11-4 — folded names assignable (stored-never-read) at SPEC level — MEDIUM (cross-file)
- Same invariant as U11-3, other assignment path: Knowledge.jl setproperty! (Knowledge.jl:75–96)
  validates a *new* key against the metadata schema, and the schema lists the folded names
  (`k1` in the quadrupole ParamMeta), so `spec.k1 = 999.0` post-construction is accepted, stored,
  and never read (runtime reads `:kn` only).
- Measured (p1): `q.k1 = 999.0` accepted, params = `[:L, :k1, :kn, :nst]`, tracking identical to
  `k1 = 0.5`. The docstring at beam_line.jl:89–96 states the fold; only the LineEntry path is guarded.

### U11-5 — wrapped LumpedRad silently loses the counter-RNG context — MEDIUM-HIGH
- `MisalignedElement` (misalignment.jl:197–214), `RefTilted` (ref_tilt.jl), and `CompositeLine`
  (beam_line.jl:522–540) define only the 6-coordinate call; on the context-aware path every element
  is called `elem(ctx, particle_id, coords...)` (fused_track.jl:53–79) and the generic fallback
  (Track.jl:59–62) DROPS the context. A `LumpedRad` reached through any of these wrappers therefore
  runs its `Random.randn()` branch (radiation.jl:158–165) instead of `octopus_normal`.
- Measured (p3): `LumpedRadSpec(...; rng_id=11, x_offset=1e-12)` compiles to `MisalignedElement`;
  two identical `elem(ctx, 1, coords...)` calls differ by |Δx| = 4.27e-4. The aligned element is
  exactly repeatable. Consequences: silent loss of reproducibility and thread/CPU-CUDA invariance
  for any misaligned, ref-tilted, or in-cryostat radiation element (on CUDA it would instead fail to
  compile). No warning anywhere.

### U11-6 — two placements of one LumpedRadSpec draw IDENTICAL noise — MEDIUM
- radiation.jl:233–238 / 255–260: the noise key is (seed, rng_method, turn, rng_id, particle_id,
  component). `rng_id` is assigned per *spec* construction (radiation.jl:33–34), and BeamLine's
  family model deliberately shares one spec across placements — so two radiation elements built from
  one spec produce the same six draws for the same particle on the same turn.
- Measured (p3): with damping off, x after two successive kicks = exactly 2 × one kick
  (ratio 2.000000…, matches `amp*nx` with `nx = octopus_normal(..., rng_id=21, pid=5, comp=1)`).
  Variance grows 4× per pair instead of 2×: correlated excitation, physically wrong equilibrium.

### U11-7 — recording aperture with default element_id=0: silent OOB write + invisible loss — MEDIUM
- aperture.jl:334–342: `_aperture_bump!` does `@inbounds counts[id] += 1`; aperture.jl:428:
  `element_id` defaults to 0 while `loss_record` is an ordinary spec parameter a user can set
  (construction_help says "set neither by hand" — nothing enforces it).
- Measured (p2): `compile_runtime(ApertureSpec(x_limit=1e-9, loss_record=rec))` then
  `ap(ctx, 1, 5e-3, 0, …)`: returns all-NaN (kill happened), **no error**, `counts` unchanged
  `Int32[0]` — the increment landed outside the array (silent memory corruption at `counts[0]`) —
  and the slot row holds element_id 0 = the never-lost sentinel, so `loss_records` reports n = 0.
  A one-line `id >= 1` guard (or constructor check when a record is present) would make this loud.

### U11-8 — aperture inside an own-state (composite) line loses all attribution — LOW-MEDIUM
- `_collect_aperture_specs!` (Tasks.jl:181–193) has no method for `ElementSpec{:line}`, and the
  runtime walk compiles a kept-whole line to ONE op, so an aperture inside a cryostat gets no
  element_id, no record, no name, no count; it kills via the R=Nothing path.
- Measured (p2): composite line containing `ApertureSpec(name="HIDDEN")`: particle killed,
  `loss_record(task) === nothing`, loss surfaces only as the `unattributed` warning
  (dead=1, logged=0). The two sizing walkers agree (T3 guard passes), so this is a semantics gap,
  not a crash — but neither theory note states that placing a collimator inside a girder silently
  removes it from loss accounting.

### U11-9 — unknown-keyword acceptance, and a BeamLine-specific aggravation — LOW (do not fix; characterized)
- Mechanism: every friendly constructor in these files funnels `kwargs...` through `_spec_params`
  (linear_maps.jl:8–10), a plain Dict build; `ElementSpec{Kind}(params)` never validates. Measured
  (p1): QuadrupoleSpec / ApertureSpec / ThinMultipoleSpec / LumpedRadSpec / MarkerSpec all ACCEPT
  `bogus_kw=…` and store it. Only post-construction `setproperty!` validates (and see U11-4 for the
  hole in that). No constructor in the five audited files validates keyword names.
- Aggravation specific to beam_line.jl:229–244 + 307–308: an unknown kwarg counts as "own state",
  so a typo silently stops the line dissolving. Measured: `BeamLine("CELL", qf, d; bogus_kw=1.0)`
  placed in a parent yields 1 entry instead of 2 — structure, s-positions, hook placement, and loss
  attribution (U11-8) all change from a typo.

### U11-10 — thin z_offset ParamMeta claims "no effect on the transverse map" — MINOR (doc)
- thin_elements.jl:125: "At zero length this is a pure drift of the kick location and has no effect
  on the transverse map". The drifted kick location *is* a transverse-map change (second order).
- Measured (p3): `ThinQuadrupoleSpec(k1l=0.5, z_offset=0.01)` vs without, at
  (x=1e-3, px=1e-4,…): Δdpx = −5.0e-7, Δx = +5.0e-6. The behavior is physically right; the text is wrong.

### U11-11 — theory note references a `misalign_reference` keyword that does not exist — MINOR (doc)
- docs/theory/misalignment_and_patch_maps.md:263–266 says Octopus "exposes `misalign_reference`,
  defaulting to :center … with :entrance"; grep finds no code occurrence. The note's own §6a later
  states the reference point rides on `misalign_convention` (which is what misalignment.jl:279
  implements: `sref = madx ? 0 : L/2`). Stale paragraph.

### U11-12 — LumpedRad's T<:Number widening contradicts its constructor — MINOR (doc/comment)
- radiation.jl:53–55 comment says the `T<:Number` bound exists so parameter duals are not refused;
  radiation.jl:77–81 then requires `T <: AbstractFloat` and throws for anything else (measured p3:
  complex damping_turns → ArgumentError). The widening is dead for its stated purpose; if the
  constructor's non-differentiability is deliberate (validation needs ordered reals), the comment
  should say so instead of claiming the opposite.

### Observation (informational, not filed as a defect)
- Zero-length misalignment identity: the pinned test (runtests.jl:3506–3515) asserts bit-identity
  for pure transverse offsets only. With pitches/tilt/z_offset the round trip returns to the input
  at max |out−in| = 4.9e-18 (:bmad) / 1.4e-18 (:madx) — round-off, not bit-for-bit (p3 #8).
  Physically fine; the general invariant is "identity to round-off", not bit-identity.

## Sound (invariants verified, with how)

1. **CPU loss-counter race fix (prior F1)**: `_aperture_bump!` is the only CPU writer of `counts`
   (grep: writes only at aperture.jl:337; CUDA branch uses `@atomic`); slots have per-particle
   ownership. Probe p2b, 8 threads, 200k particles, 5 turns: dead = 107026 = sum(counts) =
   records = unique(records); per-aperture counter == per-aperture records (63695/43331). Exact.
2. **T2 `_loss_record_matches_rep`**: Float64-slot record vs Float32 rep → false (reallocates);
   counter-only record vs Float32 rep → true (eltype irrelevant without slots). Probe p2.
3. **Loss attribution end-to-end**: nested BeamLine with two named apertures; names
   ["COLL_A","COLL_B"], counts [1,1], `aperture_s` [1.0, 3.5] exactly, per-loss rows
   (pid/elem/turn) correct, summary (dead=2, logged=2, unattributed=0), HDF5 round-trip via
   `read_loss_record` byte-consistent. Probe p2; suite additionally pins the write/read path.
4. **Loss-transition semantics**: `_aperture_newly_lost` uses `is_live` over all six coordinates
   (Beam.jl:210–211); dead particles never re-log (suite: one record per dead, unique pids);
   non-aperture deaths surface as `unattributed` with a warning (probe p2 case 2 fired it).
5. **Walker agreement on dissolved lines**: nested + `repeat` + `reverse` + zero-length marker:
   `line_entries` = `_element_tuple` = 7; `s_positions` cumulative ([0, .4, 1.4, 1.8, 2.8, 3.8, 4.2]);
   provenance paths well-formed; reflection is order-only (reversed cell = [:drift, :quadrupole],
   e1/e2 untouched by construction — `reverse` never touches params). `_collect_declared!`,
   `_aperture_specs`, `_append_runtime_line!`, `_has_knob_parameters` all handle
   Tuple/Vector/LineEntry/ElementSpec{:line}; the one pair that must agree exactly
   (_aperture_specs vs _bind_apertures) is guarded at Tasks.jl:580–583.
6. **Thin kicks vs conventions**: `ThinMultipole` calls the same `_lattice_kick` the PTC-validated
   thick runtime uses, at (h=0, L=1) — bit-identity by shared code path. Values: sextupole
   dpx = −k2l·x²/2 exactly (−6.0e-10 at x=1e-3 — measured −6.0e-7 at k2l=1.2, x=1e-3: matches
   formula exactly); dipole dpx = −k0l; hkicker dpx = +hkick (opposite sign, as documented);
   skew dipole dpy = +k0sl. n!-expansion indexing (knl[i] = K_{i-1}L) confirmed against
   `_fold_named_strengths` order+1 landing. Probe p3.
7. **Misalignment conventions vs the note**: `_misalign_matrix` composes exactly
   Ry·Rx(−φ)·Rz (:bmad) and Rz·Rx(−φ)·Ry (:madx) — max deviation 0.0 (probe p3 #9);
   `sref = 0` for :madx (entrance-referenced, d in entrance axes since Ac=I), `L/2` for :bmad;
   exit frames computed from exit geometry, never by inversion — probe p3 #10 shows
   o_out = (−9.95e-4, 0, +9.98e-5) vs inverted entry (−9.95e-4, 0, −9.98e-5) on an h=0.2 bend;
   the :madx branch (incl. ref_tilt conjugation W→Rz(−ψ)WRz(ψ)) is the one pinned at 2.8e-13–5.0e-13
   vs PTC; :bmad remains read-from-source with no reference case (not treated as verified).
8. **Dual-seeded misalignment derivatives at zero are NOT swallowed by the `dx == 0` early-out**:
   ForwardDiff seeded at x_offset = 0 gives 0.039711038827933 vs central FD 0.039711038827932;
   ref_tilt at 0: 3.9356665e-5 vs FD 3.9356656e-5. Probe p4.
9. **LumpedRad numerics**: damping factor exactly exp(−1/τ) per plane (bit-equal, probe p3 #4);
   excitation amplitude sqrt(−expm1(−2/τ))·σ with slope/−slope·α covariance structure matching the
   α/β/γ Twiss form (verified against `octopus_normal` draw, probe p3 #3c); mixed-sign σ rejected;
   Damping6DMap/Diffusion6DMap gate exactly one component each; unsupported methods throw.
   Aligned context path is counter-based and exactly repeatable (probe p3 #1).
10. **Context refusal**: a recording aperture on the context-free path throws (suite,
    runtests.jl:4426–4428); `_requires_tracking_context` folds over tuples; `LossRecord` Adapt
    drops names host-side only.

## Files/probes index

- p1_beamline.jl — U11-1..4, U11-9, walker agreement, selector parsing
- p2_aperture.jl — U11-7, U11-8, T2, end-to-end attribution
- p2b_threads.jl — race-fix verification (run with --threads=8)
- p3_radiation_thin.jl — U11-5, U11-6, U11-10, U11-12, thin kicks, convention orders, exit≠inverse
- p4_dual_misalign.jl — dual-at-zero derivatives (needs ForwardDiff env in JULIA_LOAD_PATH)
