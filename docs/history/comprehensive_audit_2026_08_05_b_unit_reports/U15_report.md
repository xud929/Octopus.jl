# U15 report — elements: beam_line / aperture / thin_elements / radiation / misalignment

Repo: `/cfs/ad/dxu/Library/Julia/Octopus` @ **7de4d81** (detached HEAD, clean).
Predecessor pass: `docs/history/comprehensive_audit_2026_08_05_unit_reports/U11_report.md`
(audited `e0f6bda`; declared baseline `6a3f39ab`, 63 commits behind HEAD).

Probes: `/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`
(`p1_walkers.jl`, `p1b_binding.jl`, `p2_aperture.jl`, `p3_radiation.jl`,
`p3b_threads.jl`, `p4_misalign.jl`, `p5_seams.jl`, `p6_paths.jl`, `p7_edges.jl`,
`p8_solenoid.jl`, `p9_cuda.jl`, `p10_cuda2.jl`). Julia 1.12.4,
`julia --startup-file=no --project=<repo>`; CUDA present and functional on this
box (`CUDA.functional() == true`), so the GPU legs actually ran.

## Provenance

**Read every line of** (auditor, directly):

- `src/elements/beam_line.jl` 1–642
- `src/elements/aperture.jl` 1–593
- `src/elements/thin_elements.jl` 1–413
- `src/elements/radiation.jl` 1–329
- `src/elements/misalignment.jl` 1–305
- `git diff 6a3f39ab HEAD` over all five files (193 insertions, 33 deletions)
- `docs/theory/aperture_and_particle_loss.md` 1–405,
  `docs/theory/misalignment_and_patch_maps.md` 1–444,
  `docs/theory/beam_line_composition.md` 1–542 (all in full)
- `AGENTS.md` "Hard-Won Rules"; `docs/comprehensive_audit.md` "Measured Lessons"

**Read targeted** (to trace every walker and call path out of the region):
`src/tasks/Tasks.jl` 100–430, 430–800; `src/track/Track.jl` 40–90;
`src/track/fused_track.jl` 1–78; `src/track/phase6d_track.jl` 1–100, 200–215;
`src/policies/Policies.jl` 55–275; `src/elements/lattice_magnets.jl` 905–995,
1060–1075; `src/elements/solenoid.jl` 360–380; `src/elements/ref_tilt.jl`
(ctx method + `_inner_method`); `src/knowledge/Knowledge.jl` 79–200, 536;
`src/contracts/Contracts.jl` (fold/effectiveness call sites, tolerances);
`test/runtests.jl` 3671–3702 (the testset pinning the U11 fixes).

**Executed**: everything under "Repro" in each lead, plus the clean-list
measurements. All CPU probes < 60 s; the CUDA probes ~3 min each.

---

## Verdicts on the two inherited OPEN leads

### U11-1 (nested-line survey) — **REFUTED at HEAD. Fixed, and the fix is complete.**

`_placement_length` (`beam_line.jl:384–391`) was added and threaded into
`s_positions` (:409), `total_length` (:596–597) and — cross-file —
`_collect_aperture_s!` (`Tasks.jl:301–310`). Measured on a **three-deep** nested
line with own-state sub-lines, a zero-length marker and two apertures:

```
L3 = BeamLine("L3", MK, QF(L=0.4), COLL_IN, D(L=1.0); x_offset=2e-4)  # own state
L2 = BeamLine("L2", L3, D(L=1.0); y_offset=1e-4)                      # own state
L1 = BeamLine("L1", L2, QF, COLL_OUT, D)                              # dissolves
```

| walker | file:line | measured | physical | agree |
|---|---|---|---|---|
| line expansion `length`/`line_entries` | `beam_line.jl:365,368` | L1=4, L2=2, L3=4 | 4/2/4 | ✔ |
| `_element_tuple` (task normalisation) | `Tasks.jl:327–333` | 4 | 4 | ✔ |
| `_runtime_line_entries`/`_append_runtime_line!` | `Tasks.jl:670–714` | 4 ops: `MisalignedElement, LatticeMagnet, Aperture, LatticeMagnet` | 4 | ✔ |
| `s_positions(L1)` | `beam_line.jl:403–412` | `[0.0, 2.4, 2.8, 2.8]` | `[0.0, 2.4, 2.8, 2.8]` | ✔ |
| `s_positions(L2)` / `s_positions(L3)` | ″ | `[0.0, 1.4]` / `[0.0, 0.0, 0.4, 0.4]` | same | ✔ |
| `total_length` L1/L2/L3 | `beam_line.jl:596` | `3.8 / 2.4 / 1.4` | `3.8 / 2.4 / 1.4` | ✔ |
| misaligned-parent survey `L` (geom) | `beam_line.jl:613–614` | `2.4` for L2 | 2.4 | ✔ |
| `_aperture_specs` | `Tasks.jl:250` | 1 → `["COLL_OUT"]` | 1 attributable | ✔ |
| `_aperture_s_positions` | `Tasks.jl:287` | `[2.8]` | 2.8 | ✔ |
| `_bind_apertures` id count vs `counts` | `Tasks.jl:651–663` | `1 == 1` (T3 guard passes) | — | ✔ |
| `_collect_hidden_apertures!` | `Tasks.jl:190–205` | `[:COLL_IN]` + warning | — | ✔ |
| `_collect_declared!` (contracts/analyses) | `Tasks.jl:353–363` | 2 contracts / 1 analysis (sees through the kept-whole line) | — | ✔ |
| `entry_path` naming | `beam_line.jl:176–177` | `L1/L2`, `L1/QF`, `L1/COLL_OUT`, `L1/D` | — | ✔ |

Also measured: `reverse(L2)` keeps own state (`y_offset = 1e-4`) and
`total_length = 2.4` (U11-2 fixed); `repeat(L3, 2)` gives 2 placements and
`total_length = 2.8`; `_placement_length` recursion terminates at any depth.
**Repro:** `p1_walkers.jl`.

One residual: the cryostat's *contents* are not addressable from the parent —
`find_entries(outer, sel"ARC//QUADRUPOLE")` returns only the top-level magnet
(`[2]`), never the two inside `ARC/CRYO`. That is the documented consequence of
§10 ("a girder is simply an element that happens to be long"), not a defect.

### U11-8 (composite-aperture attribution) — **REPRODUCED; the gap is unchanged but is no longer silent.**

The mechanism is exactly as U11 recorded it: `_collect_aperture_specs!` has no
`ElementSpec{:line}` method, a kept-whole line compiles to one op, so an
aperture inside it gets no `element_id`, no counts row and no name. Measured on
the L1/L2/L3 line above: `aperture_names = ["COLL_OUT"]`, `counts = Int32[0]`
for the particle killed by `COLL_IN`, `summary = (dead=1, logged=0,
unattributed=1)` plus the unattributed warning. What changed is that
`_warn_hidden_apertures` (`Tasks.jl:172–205`) now names the hidden aperture at
`TrackingTask` construction, and it works **three levels deep** (a dissolving
mid-line inside a kept-whole top line still reports `:DEEP`). The F15 guard
(`aperture.jl:334–349`) removes the out-of-bounds write that made this
dangerous. **Recommendation: close as "documented + warned limitation", not as
a defect.** **Repro:** `p1b_binding.jl`, `p7_edges.jl` §g5.

---

## LEADS

### LEAD U15-1 [Major, confidence high] src/elements/beam_line.jl:568-593
Claim: a kept-whole line (girder/cryostat) — the flagship feature of this file —
fails to compile for CUDA whenever its member runtimes are not all of one
concrete type, which is every realistic assembly.
Mechanism: both `CompositeLine` call methods walk `elem.ops` with a **runtime**
`for` loop (`track_particle`, :568–574; the F13 ctx method, :582–588). Indexing a
heterogeneous `Tuple` with a non-constant index lowers to
`ijl_get_nth_field_checked`, which has no device implementation, so
`cuda_track_kernel!` fails `InvalidIRError` at `beam_line.jl:586` →
`misalignment.jl:224` → `fusedTrack`. The rest of the tracker avoids this
precisely by unrolling at compile time (`fusedTrack` is `@generated` and expands
nested tuples, `fused_track.jl:28–77`). The defect predates F13 — the
context-free method has the same loop — but F13 moved it onto the path *every*
task takes, and the CPU path masks it because the loop is legal there.
Repro: `p10_cuda2.jl` §j1 —
`BeamLine("W", BeamLine("G3", QuadrupoleSpec(L=0.4,k1=1.0,nst=2), DriftSpec(L=1.0); x_offset=2e-4), DriftSpec(L=0.1))`
executed on a `CuArray` `Phase6DRep` throws
`InvalidIRError: ... unsupported call to an unknown function (call to ijl_get_nth_field_checked)`;
the same line with a *homogeneous* ops tuple ("girder, 1 magnet", "girder, 2
same-type quads", "girder, 3 quads") runs and is bit-identical to the CPU
(`max|cpu-gpu| = 0.0`). Control: the dissolving line runs.

### LEAD U15-2 [Medium, confidence high] src/elements/beam_line.jl:599-616 (`compile_runtime(::ElementSpec{:line})`) + src/elements/misalignment.jl:288-291
Claim: a misaligned line that contains a bend is surveyed as **straight**, so its
exit patch is wrong at first order in the bend angle — silently, and with no
caveat in the user-facing help.
Mechanism: `geom` is built by merging only `:L => total_length(resolved)` into
the line's params (`beam_line.jl:613–614`). `:h` is neither a declared `:line`
parameter nor derived, so `_misalignment_wrap` reads `h = 0`
(`misalignment.jl:290`) and `_misalign_frames` builds both faces from the
straight survey — the exact failure mode `misalignment_and_patch_maps.md` §5
calls "the worst possible failure mode, since a FODO test would pass". The
limitation *is* recorded in `beam_line_composition.md` §10 ("the assembly's own
survey stays 1D"), but nothing warns and `element_help(:line)`'s
`construction_help` advertises the girder use with no caveat.
Repro: `p5_seams.jl` §e1 — compare
`compile_runtime(BeamLine("G", SBendSpec(L=1.1, angle=θ, k1=0.0, nst=8); x_offset=1e-3))`
against `compile_runtime(SBendSpec(L=1.1, angle=θ, k1=0.0, nst=8, x_offset=1e-3))`
at `(1e-3, 2e-4, -5e-4, 1e-4, 0.0, 1e-3)`. Same rigid displacement of the same
body, so they must agree. Measured `max|girder − element|`:

| angle | 0.0 | 1e-3 | 1e-2 | 0.05 | 0.198 | 0.4 |
|---|---|---|---|---|---|---|
| diff | **0.0** | 1.000e-6 | 1.000e-5 | 5.001e-5 | **1.9864e-4** | 4.051e-4 |

exactly linear in the angle (= `dx·θ`), and exactly `0.0` for a straight element
of the same length with offset + pitch + tilt (`p5_seams.jl` §e2).

### LEAD U15-3 [Medium, confidence high] src/elements/beam_line.jl:310-320 (`Base.reverse`)
Claim: reflection now **aliases** placements — the reversed line and its source
share `LineEntry` objects, so a per-occurrence override written on one moves the
other. Regression introduced by the U11-2 fix.
Mechanism: the fix replaced the positional rebuild with
`p[:entries] = Tuple(reverse(collect(line_entries(spec))))`, which reuses the
same `LineEntry` objects (and therefore the same `overrides` `Dict` and `path`
`Vector`). The old path went through `_append_line_child!(::LineEntry)`
(`beam_line.jl:292–300`), which copies `overrides` and rebuilds `path` for
exactly this reason. `beam_line_composition.md` §7b is explicit: "Error
parameters must not share. Every physical magnet has its own misalignment. Two
occurrences with a common `x_offset` would be a fiction."
Repro: `p6_paths.jl` §f3 —
`inner = BeamLine("CRYO", QuadrupoleSpec(L=0.4,k1=1.7,nst=2), DriftSpec(L=1.0); x_offset=2e-4); rev = reverse(inner)`
gives `rev[1] === inner[2]` → `true`; then `rev[1].k1 = 9.9` yields
`getparam(inner[2], :k1) == 9.9`. `p1b_binding.jl` shows the same for a
dissolving line: `arc[1] === rev[2]` → `true`, and `rev[2].x_offset = 3.3e-3`
sets `getparam(arc[1], :x_offset) == 0.0033`.
Side note (cosmetic, same site): after `reverse`, `line_entries` returns a
`Tuple{LineEntry,...}` where every other construction path returns
`Vector{LineEntry}`.

### LEAD U15-4 [Medium, confidence high] src/elements/beam_line.jl:568-577 (`track_particle(::AbstractTrackingMethod, ::CompositeLine, …)`)
Claim: the context-free call path applies **one borrowed tracking method to every
member op**, so a kept-whole line whose members do not all share a method throws
a `MethodError` on that path while the context path tracks it fine — two call
paths over one runtime object disagreeing about what the object can do.
Mechanism: `(elem::CompositeLine)(x, …)` (:576) resolves `_inner_method(elem)` =
the **first** op's method (:592–593) and hands that single method to
`track_particle(method, op, …)` for every op (:568–574). The F13 ctx method
(:582–588) instead calls `op(ctx, pid, …)`, which lets each op pick its own
method — which is why the ctx path works. Mixed methods inside one assembly are
not exotic: an aperture is `NonSymplectic6DMap` and a magnet is
`Symplectic6DMap`, and `_warn_hidden_apertures` exists precisely because
apertures inside kept-whole lines happen.
Repro: `p7_edges.jl` §g4 / `p1b_binding.jl` — with
`ln = BeamLine("M1", QuadrupoleSpec(L=0.4,k1=1.0,nst=1), ApertureSpec(x_limit=1e-2,y_limit=1e-2); x_offset=1e-4)`,
`compile_runtime(ln)(1e-3, 0.0, 0.0, 0.0, 0.0, 0.0)` throws
`MethodError: no method matching track_particle(::Symplectic6DMap, ::Aperture{Nothing, NonSymplectic6DMap, Nothing, Float64}, …)`;
magnet+`LumpedRadSpec` throws the analogous `::LumpedRad{Radiation6DMap,…}`
error; reversing the order throws for the magnet instead; magnet+drift (one
method) is `OK`. The same object called as `rt(ctx, 1, coords…)` returns
`(0.00087968…, −0.00059119…, 0.0, 0.0, −2.6839e-8, 0.0)`. Reachable from
`Contracts.jl:1252` (`case.element(q…)`), `:1865`, `:2103`, `:2119`, and from
`track!(rep, elems, turns, ::ResolvedCPUExecutionPolicy)`
(`phase6d_track.jl:38–47`).

### LEAD U15-5 [Medium, confidence high] src/elements/aperture.jl:104-117 (`_loss_record_matches_rep`) + src/tasks/Tasks.jl:627-647 (`_ensure_loss_record!`)
Claim: the task's loss record is reused for **any** representation of the same
size and backend, so a second beam silently inherits the first beam's counters
and per-particle slots; `unattributed` then goes negative and the
`unattributed != 0` warning fires with a message that is false.
Mechanism: `LossRecord`'s docstring says "One per **beam**" (`aperture.jl:22–26`)
and `_runtime_entries` claims "a task re-run on a different beam needs a
different record" (`Tasks.jl:595–599`), but the `fits` test compares only
`length(counts)`, `_loss_record_matches_rep` (backend + slot eltype), the
slots-requested flag and `size(slots, 2)` — never identity or generation. Counts
are cumulative and are never zeroed.
Repro: `p7_edges.jl` §g3 — one `TrackingTask` over
`BeamLine("L", ApertureSpec(x_limit=1e-3, y_limit=1e-3, name="C"))`;
`execute!(task, rep1)` with `rep1.x = [5e-3, 0.0]` gives
`(dead=1, logged=1, unattributed=0)`; then `execute!(task, rep2)` on a
**pristine** two-particle rep gives `loss_record(task) === rec1 → true`,
`counts = Int32[1]`, `summary = (dead=0, logged=1, unattributed=-1)` and the
warning *"particles were lost with no aperture responsible"* for a beam in which
nothing was lost.

### LEAD U15-6 [Medium, confidence high] src/elements/beam_line.jl:384-391 + :637 (the new `L` ParamMeta on `:line`)
Claim: declaring `L` as a `:line` parameter re-opens the walker split U11-1
closed — a user-set `L` is honoured by the arc-position walkers and ignored by
`total_length` and the survey, and a bare `L=` silently stops a line dissolving.
Mechanism: `_placement_length(::ElementSpec{:line})` and
`_placement_length(::LineEntry)` consult `hasparam(spec, :L)` first, while
`total_length` (:596) always re-sums the entries and `compile_runtime`'s `geom`
merge (:613–614) *overwrites* any stored `:L` with the computed total. Nothing
stores `:L` on a line, so the ParamMeta text ("stored by the line machinery") is
also inaccurate; what the declaration actually does is make `L` a *settable*
parameter with no validation. Separately, `_line_has_own_state` (:332–333) counts
any key but `:name`/`:entries`, so `L=` alone turns a structural line into a
girder.
Repro: `p5_seams.jl` §e3 —
`cryoL = BeamLine("CRYOL", QuadrupoleSpec(L=0.4,k1=1.0,nst=1), DriftSpec(L=1.0); x_offset=1e-4, L=99.0)`;
`total_length(cryoL) = 1.4` but `_placement_length(cryoL) = 99.0`,
`s_positions(BeamLine("PARENT", cryoL, ApertureSpec(...))) = [0.0, 99.0]`, and
`_aperture_s_positions(task.elements) = [99.0]` while the compiled survey uses
`1.4`. `p4_misalign.jl` §d7: `_line_has_own_state` goes `false → true` when the
only kwarg is `L=99.0`.

### LEAD U15-7 [Medium, confidence med] src/elements/beam_line.jl:122-143 (`_FOLDED_NAMED_STRENGTHS`, `_FOLDED_TUPLE_KEYS`)
Claim: the folded-name guard is a hand-copied table that misses the sixth
`_fold_named_strengths` call site (`:solenoid`), and its `(:kn, :ks)` default
would actively misdirect for that kind. No coverage tripwire ties the table to
the fold sites — the exact regeneration Measured Lesson 4 warns about, one
commit after the same defect was fixed for the thin kinds (U11-3).
Mechanism: `SolenoidSpec` folds `_MULTIPOLE_NAMED` with
`nkey=:kn, skey=:kskew` (`solenoid.jl:376–377`) because `ks` is already the
*solenoid strength* there. `:solenoid` is absent from
`_FOLDED_NAMED_STRENGTHS`, so `_reject_folded_override` returns early; and if it
were added without a `_FOLDED_TUPLE_KEYS` entry, the message would tell the user
to write `ks`, i.e. to overwrite the solenoid strength.
Repro: `p8_solenoid.jl` — `s = SolenoidSpec(L=1.0, ks=0.3, k1=0.5)` stores
`[:L, :kn, :ks]` with `kn = (0.0, 0.5)` and no `:k1`; then
`BeamLine("S", s)[1].k1 = 999.0` is **ACCEPTED**, `getparam(entry, :k1) == 999.0`,
and `compile_runtime(entry).kn == (0.0, 0.5)` — written, reported, never read.
The §h2 table prints `solenoid guarded=false tuple-keys-correct=false`; all ten
other fold sites are `true/true`.

### LEAD U15-8 [Minor, confidence high] src/elements/beam_line.jl:385-389 (`_placement_length(::LineEntry)`)
Claim: an `:L` placement override on a nested own-state line is stored, reported
and never read.
Mechanism: `spec isa ElementSpec{:line} && !hasparam(spec, :L) && return total_length(spec)`
returns before the merged-parameter read, so the entry's own `:L` never reaches
`getparam(entry, :L, 0.0)` on line 388. The same override *is* honoured when the
sub-line happens to carry its own `:L` — the behaviour is inconsistent with
itself as well as with "placement wins" (`beam_line_composition.md` §7b).
Repro: `p4_misalign.jl` §d8 — `outer = BeamLine("OUT", cryo, DriftSpec(L=1.0)); e = outer[1]`;
`_placement_length(e) == 1.4`; `e.L = 50.0`; `getparam(e, :L) == 50.0` but
`_placement_length(e) == 1.4` still.

### LEAD U15-9 [Minor, confidence high] docs/theory/misalignment_and_patch_maps.md:262-266
Claim: the theory note tells the reader Octopus exposes `misalign_convention`
"defaulting to `:center` … with `:entrance` available to reproduce MAD-X", and
then quotes its PTC reference table "with `misalign_convention = :entrance`".
Both values are refused by the code, so the note's own reproduction instructions
cannot be executed. (U11-11 corrected the *keyword name* in this paragraph; the
*values* were left stale.)
Mechanism: `_misalignment_wrap` accepts only `(:bmad, :madx)`
(`misalignment.jl:285–287`). §6a's later subsection uses the right names, so the
note contradicts itself.
Repro: `p4_misalign.jl` §d4 — `compile_runtime(QuadrupoleSpec(L=1.0, k1=0.3, nst=1, x_offset=1e-3, misalign_convention=:center))`
throws `ArgumentError: misalign_convention must be :bmad or :madx; got :center`;
same for `:entrance`; `:bmad` and `:madx` are accepted.

### LEAD U15-10 [Minor, confidence high] src/elements/aperture.jl:416-441 (`Aperture(spec, method)`)
Claim: supplying `alive` silently makes `shape`, `x_limit` and `y_limit` inert
*and* skips their validation, so a spec that reads like a 1 mm ellipse passes
particles at 0.5 m and a negative half-aperture is accepted.
Mechanism: the shape/limit validation block is guarded by `alive === nothing`
(:425–434) and `shape` collapses to `UInt8(0)` (:435), but the parameters are
still stored, still reported by `element_help`, and still promoted into `T`
(:424). Nothing warns. `:aperture` declares only
`ElementTrackingBackendConsistencyContract`, so no effectiveness probe covers it.
Repro: `p7_edges.jl` §g1 —
`ap = compile_runtime(ApertureSpec(shape=:ellipse, x_limit=1e-3, y_limit=1e-3, alive=(x,px,y,py,z,pz)->abs(x)<1.0))`;
`ap.shape == 0`, `ap.x_limit == 0.001`, and `ap(0.5, 0,0,0,0,0)` survives.
`ApertureSpec(shape=:ellipse, x_limit=-1.0, y_limit=1e-3, alive=…)` compiles
without complaint.

### LEAD U15-11 [Minor, confidence high] src/elements/aperture.jl:295-304 (`_aperture_record!`)
Claim: the turn number is stored in a slot whose element type is the *coordinate*
type, so a `Float32` beam records wrong turn numbers past 16,777,216.
Mechanism: `slots` is allocated with `T = eltype(rep.x)` (`aperture.jl:89, 96–99`)
and `slots[_LOSS_ROW_TURN, particle_id] = ctx.turn` (:296) narrows an `Int64`.
`element_id` is small and safe; the turn is not, and lifetime studies are exactly
the runs that reach 10^7 turns.
Repro: `p7_edges.jl` §g2 — with a `Float32` rep, `eltype(rec.slots) == Float32`;
`Float32(16777216)` round-trips exactly, `Float32(16777217) == 1.6777216f7`
(off by 1), `Float32(16777219) == 1.677722f7` (off by 3).

### LEAD U15-12 [Minor, confidence high, OUT OF HYPOTHESIS — cross-file seam] src/elements/beam_line.jl:335-346 (`_entry_label`)
Claim: the beam-line design keys provenance paths on a `:name` parameter that
only two of the thirty element kinds declare, so naming any ordinary lattice
element emits a warning telling the user the value is "NOT being tracked".
Mechanism: `_entry_label` reads `getparam(child, :name, "")` and the docstring
promises `ARC1/QF[3]`; but only `:line` (`beam_line.jl:628`) and `:aperture`
(`aperture.jl:460`) declare `name=ParamMeta(...)`. Every other kind routes it
through the unknown-parameter path added by the U3-10/U13 work
(`Knowledge.jl:100`). The seam is between `_entry_label`'s contract and the
per-kind schemas; the repair belongs in `Knowledge.jl` (a `_PLACEMENT_PARAMS`-style
common declaration), which is outside this region.
Repro: `p1_walkers.jl` head, `p5_seams.jl` §e4 — `QuadrupoleSpec(L=0.4, k1=1.7, nst=2, name="QF")`
warns `ElementSpec{:quadrupole}: unknown parameter(s) … [:name]`; the §e4 table
shows `declares :name` = `false` for `QuadrupoleSpec`, `DriftSpec`,
`MarkerSpec`, `SBendSpec` and `true` only for `ApertureSpec`.

### LEAD U15-13 [Minor, confidence high, OUT OF HYPOTHESIS — cross-file seam] src/elements/aperture.jl:38-41 (LossRecord docstring claim)
Claim: `LossRecord`'s docstring says the private-slot design means "CPU and CUDA
produce byte-identical records"; for a stochastic line the recorded coordinates
are **not** byte-identical — `octopus_normal`'s `Float64` draws differ between
backends by up to 2 ulp on ~13 % of samples.
Mechanism: the *ordering* claim is sound (slot `i` is always particle `i`,
verified below); the *value* claim is not, and the difference is upstream in the
counter-RNG normal transform (`octopus_normal`, outside this region), not in the
aperture. Well inside every declared tolerance
(`ElementTrackingBackendConsistencyContract` uses `atol = rtol = 1e-10`), so this
is a documentation over-claim, not a numerical defect — but the docstring is what
a reader will quote.
Repro: `p10_cuda2.jl` §j2 and the isolation run — a line containing only
`LumpedRadSpec{Float64}(damping_turns=(1e4,1e4,1e4), sigma=(1e-3,1e-3,1e-3), is_damping=false, rng_id=901)`
(so `x_out = excitation[1]·nx` exactly), 1024 particles, one turn:
**135 / 1024 entries differ**, `max abs diff = 3.388e-21`, `max ulp diff = 2.0`.
Drift-only and quadrupole-only lines over the same beam are exactly bit-identical
(`max|cpu−gpu| = 0.0`), so the difference is entirely in the RNG path.

---

## Wrapper-vs-context table (hypothesis (e))

Every `AbstractTrackOp` in the repository that wraps another op — `grep "inner::"`
returns exactly two (`MisalignedElement`, `RefTilted`) and `CompositeLine` is the
third, holding `ops::Tuple`. All three are covered.

| type | file:line | has ctx method | forwards to inner | measured ctx-repeatable |
|---|---|---|---|---|
| `MisalignedElement` | `misalignment.jl:221–226` | yes (F13) | `elem.inner(ctx, pid, …)` | ✔ |
| `RefTilted` | `ref_tilt.jl:86` | yes (F13) | yes | ✔ |
| `CompositeLine` | `beam_line.jl:582–588` | yes (F13) | `op(ctx, pid, …)` for each op | ✔ (but see U15-1, U15-4) |
| `LumpedRad` (leaf, stochastic) | `radiation.jl:237–239` | yes, own | — | ✔ |
| `Aperture{F,M,<:LossRecord}` (leaf) | `aperture.jl:278–283` | yes, own | — | ✔ (refuses the ctx-free path, `phase6d_track.jl:53–67`) |
| `Aperture{F,M,Nothing}` (leaf) | `aperture.jl:267–274` | no — correct | — | generic fallback is right for a deterministic leaf |
| `Marker` (leaf) | `thin_elements.jl:35–38` | no — correct | — | identity |
| `ThinMultipole` (leaf) | `thin_elements.jl:72–80` | no — correct | — | deterministic |

Measured (`p5_seams.jl` §e5, `p3_radiation.jl` §c4–c6): a `LumpedRad` reached
through each of `MisalignedElement`, `RefTilted`, `RefTilted(MisalignedElement)`
and `MisalignedElement(CompositeLine)` returns identical results on two identical
`elem(ctx, pid, coords…)` calls. **F13 is closed for every wrapper that exists.**

---

## Sound (what was checked, and with what evidence)

1. **Aperture boundary is inclusive, uniformly.** `p2_aperture.jl` §1: for all
   three shapes, `x == x_limit` survives, `nextfloat(x_limit)` is killed,
   `prevfloat` survives, `y == y_limit` survives. The `(a, b)` corner survives
   the rectangle and is killed by the ellipse and rectellipse — correct, since
   `1² + 1² > 1`. Matches `abs(u) <= a` / `(u/a)² + (v/b)² <= 1`
   (`aperture.jl:216–222`) and the Xsuite/Elegant convention.
2. **Overlapping apertures resolve by lattice order.** Two zero-length apertures
   at the same `s` (wide `COLL_A` then tight `COLL_B`): a particle outside only
   the tight one is attributed to `COLL_B`, a particle outside both to `COLL_A`
   (`counts = Int32[1,1]`, rows `[(pid 1, elem 2), (pid 2, elem 1)]`,
   `aperture_s = [0.0, 0.0]`). With the order reversed, `COLL_B` claims both
   (`Int32[2, 0]`). Distinct ids at identical `s` — the zero-length attribution
   question is answered by order, as `aperture_and_particle_loss.md` §2 requires.
   (`p2_aperture.jl` §2–3.)
3. **F15 out-of-bounds counter write is closed.** A raw `compile_runtime`
   aperture handed a shared 1-row record with `element_id ∈ {0, 2, −5, 99}` kills
   the particle and leaves `counts` untouched; `element_id = 1` bumps normally.
   No crash, no corruption. (`p2_aperture.jl` §4.) The CUDA method carries the
   identical static guard (`aperture.jl:352–357`) and an aperture line with a
   loss record compiles and runs on device: 2048/4096 killed,
   `counts = Int32[2048]`, `unattributed = 0` (`p9_cuda.jl` §i3).
4. **`unattributed != 0` warns in every case asked about**, including a line with
   **no aperture at all**: `loss_record(task) === nothing`,
   `loss_counts(nothing) = Int[]`, `logged = 0`, `unattributed = dead = 1`, and
   the warning fires (`p2_aperture.jl` §5). A dead-on-arrival particle
   (`px = NaN`) reaching a wide aperture is *not* attributed to it
   (`counts = Int32[0]`, `unattributed = 1`) — `_aperture_newly_lost`'s six-
   coordinate `is_live` test working as the note specifies (`§8`).
5. **Radiation stream independence and determinism.** Two distinct
   `LumpedRadSpec` objects draw independently: over 4000 particles,
   `corr(a, b) = 0.0138` against a `1/√n = 0.0158` noise floor, with per-stream
   `sd = 1.423e-6 / 1.445e-6` against the analytic
   `σ·√(−expm1(−2/τ)) = 1.414e-6`. Two placements of **one** spec object draw the
   identical stream (`corr = 1.0`) — the F14 trap — and `TrackingTask`
   construction now warns naming the duplicated `rng_id`
   (`Tasks.jl:207–243`), while two distinct specs construct silently.
   (`p3_radiation.jl` §c1–c3.)
6. **Thread invariance, measured in the regime it is quoted in.** Same seed, a
   3-turn stochastic run over 20 000 particles: `hash = 8413091344994856442` and
   `sum|x| = 0.9310489798123385` at 1, 4 and 8 threads — **bit-identical**. The
   execution audit confirms the fan-out actually happened
   (`(workers = 1|4|8, pool_threads = 1|4|8)`, three receipts each), so this is
   not the "below the parallel threshold" pin Measured Lesson 5 warns about.
   (`p3b_threads.jl`.)
7. **Misalignment conventions match the note exactly, for both.**
   (`p4_misalign.jl` §d1–d3, §d5.)
   - Rotation order: `max|W_bmad − R_y(θ)R_x(−φ)R_z(ψ)| = 0.0` and
     `max|W_madx − R_z(ψ)R_x(−φ)R_y(θ)| = 0.0` against independently constructed
     matrices; the two differ by 7.83e-4 at (θ,φ,ψ) = (0.013, −0.021, 0.037) and
     agree to 0.0 for any single rotation — §4 / §6a, verbatim.
   - Reference point: `:madx` gives `o_in = (0,0,0)` (entrance-referenced),
     `:bmad` gives `o_in = (−5.491e-4, 0, −2.693e-5)` with the mirror-image
     `o_out` (centre-referenced) on an `h = 0.18, L = 1.1` bend — §4 / §6a.
   - `ref_tilt` frame: `:bmad` is unchanged by `ψ = 0.3`
     (`max|Δq_in| = max|Δo_in| = 0.0`), `:madx` is not (5.912e-4 / 2.955e-4), and
     the explicit conjugation `W → RᵀWR, d → Rᵀd` reproduces the `:madx` frames
     to **0.0 exactly** — §6a "which frame the error is quoted in", verbatim.
   - Zero length: `o_in = (0,0,0)` for both conventions, so the two differ only
     in rotation order — which is what `thin_elements.jl:188`'s ParamMeta says.
   - The `:bmad` reference-case gap is unchanged and remains openly recorded;
     nothing here could close it and nothing here contradicts it.
8. **Folded-name guard now covers every thin kind and the spec path (U11-3/U11-4
   closed).** `entry.k1l/k2l/k0l/k3l` and `entry.k1` are all rejected with a
   message naming the right tuple (`knl[2]`, `knl[3]`, `knl[1]`, `knl[4]`,
   `kn[2]`); `spec.k1 = 999` and `spec.k1l = 999` are rejected too.
   `entry.hkick = 999` is correctly **accepted** — `hkick` is not folded.
   (`p6_paths.jl` §f4–f5.) The one hole is `:solenoid` (U15-7).
9. **Aperture binding and the T3 guard hold on the nested line.** `_aperture_specs`
   sized `counts` to 1 and `_bind_apertures` assigned exactly 1 id
   (`id[] == length(record.counts)`), so the host-side loud check
   (`Tasks.jl:659–662`) passes; names, counts, `aperture_s` and the per-loss rows
   line up entry for entry. A `loss_record` hand-set on a task-level aperture spec
   is overridden by the binder (the user's shared record stays at its previous
   value) — documented in `construction_help` as "set neither by hand".
10. **Girder tracking is exact on CPU and, where it compiles, on GPU.** A
    misaligned line wrapping a single element reproduces element-level
    misalignment to `0.0` for a straight element with offset + pitch + tilt
    (`p5_seams.jl` §e2); homogeneous girders are bit-identical CPU vs CUDA
    (`max|cpu−gpu| = 0.0`, `p10_cuda2.jl` §j1).
11. **`_placement_length` recursion is well-founded** at three levels and under
    `reverse`/`repeat`; `total_length(reverse(L2)) == total_length(L2) == 2.4`,
    `total_length(repeat(L3, 2)) == 2.8`.
12. **Hidden-aperture detection is depth-correct**: an aperture inside a
    dissolving line inside a kept-whole line is still reported (`[:DEEP]`),
    and a top-level aperture produces no warning at all (`@test_logs` in the
    suite pins both directions).

---

## Not checked, and why

- **The `:bmad` misalignment convention against an external reference.** It has no
  reference case in this repository and closing the gap needs Bmad, which is not
  in the validation path. Checked code-vs-note internal consistency only (clean
  item 7); the gap remains openly recorded.
- **Whether the 2-ulp CPU/CUDA `octopus_normal` difference is in Philox, in the
  Box–Muller/inverse-CDF transform, or in libm-vs-CUDA `log`/`sqrt`.** The RNG is
  outside this region; U15-13 stops at the measurement, per the seam rule.
- **The `:line` `L` ParamMeta's interaction with
  `ElementParameterEffectivenessContract`.** `Contracts.jl:1991` declares it
  inactive with a reason; I read the declaration but did not run the contract, so
  I cannot say whether the inactive-list entry is exercised.
- **`write_loss_record` when `aperture_names` and `aperture_counts` have different
  lengths.** Reachable only through `LossRecord(String[], n, rep)`
  (`na = max(length(names), 1)` gives a 1-row `counts` with 0 names,
  `p2_aperture.jl` §6); the task never allocates a record with zero apertures
  (`Tasks.jl:630`), so I judged the path unreachable in practice and did not
  pursue it.
- **MPI / multi-rank loss accounting.** Out of region.
- **The full test suite gate.** This is a reading unit; no repository file was
  modified, and no fix was made whose blast radius would need it.
