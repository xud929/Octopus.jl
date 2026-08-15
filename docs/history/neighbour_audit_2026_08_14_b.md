# Targeted Neighbour Audit — floor plan, ledger closures, wiring report

Range audited: `1d6b760` … `ac40f62` (the floor-plan theory note and
implementation, the cavity ledger closures — chain-everywhere, single-pass
refusal, `harmon` — the CI pin re-float, the container `knob_report`, and
the FODO knob example). Second audit of 2026-08-14; the first
([`neighbour_audit_2026_08_14.md`](neighbour_audit_2026_08_14.md)) covered
the campaign this series built on. Method per
[`../comprehensive_audit.md`](../comprehensive_audit.md): per fix, re-walk
call sites and sibling surfaces, re-run the fix's property on the
neighbours it did not change.

## Findings

**FIXED — the accelerating kind lacked the hidden-cavity tripwire its ring
sibling had.** `_bind_survey` counted compiled `ThinRFCavity` ops against
the spec walk and refused a cavity hidden in a sub-line the walk does not
descend; the accelerating kind had no such check, and both of `f900e8d`'s
new guards — the reference-chain validation and the single-pass refusal —
walk SPECS. Probed: an accelerating cavity inside a kept-whole (own-state)
line **compiled silently and ran a multi-turn window** against a stale
reference — the exact silent wrongness the guards were built to prevent,
evading them through the one door they shared. The bind now counts
compiled accelerating ops against the walked specs and refuses with the
full story; the messages of both tripwires also now name the second shape
they catch (a bare line nested in a task tuple, which dissolves at compile
and is equally unseen by the spec walk). Suite-pinned beside the rf-kind
pin. The lesson is the protocol's own: the rf check existed because the
survey campaign needed it; the sibling kind, added days later, inherited
the walk but not the tripwire.

**VERIFIED and pinned — the patch's two readings are one transformation.**
The floor-plan note's §4 item 2 demanded that a patch's geometric step and
its coordinate map agree, and no test tied them together. Probed with all
six degrees of freedom nonzero in BOTH conventions (single rotations
cannot distinguish the composition orders): a particle launched on the new
reference — direction along the new `ŝ`, transverse position
back-projected through the longitudinal offset — tracks to transverse
zeros at **6.9e-18**. Now a permanent suite pin. Instructive detour kept
on the record: the probe's first draft launched at the new origin's
transverse coordinates without the back-projection and measured its own
`d₃·angle` parallax (1.5e-3) — a wrong probe indicting correct code, caught
by checking the residual's scale against the geometry before believing it.

**Clean walks, recorded:**
- `_floor_step`'s generic curved rule reads `h`, `ref_tilt`, and the
  placement length through the merged view, so an `L`/`h` override on a
  bend placement surveys consistently with what compiles; no per-kind
  enumeration exists to go stale.
- `survey` collides with no existing symbol (validation/examples sweep).
- The wiring `knob_report` deliberately DESCENDS kept-whole sub-lines
  (a report wants to see inside; the arc walker must not) — divergence
  documented at both sites. In-line hook objects holding expressions are
  outside its scope (they are not specs); boundary noted in the docstring.
- The knob example's rewrite is exercised by the in-suite examples testset
  (5/5 in the landing gate) and demonstrates the flexible-constructor
  requirement the friendly constructors enforce by refusal.
- CI since the re-float (`32915f9`): **4 runs on floating 1.12.6, 4 green**
  — tally carried to the todo ledger row.

## Dispositions

| finding | disposition |
|---|---|
| accelerating kind missing the hidden-cavity tripwire | **fixed here**, suite-pinned |
| patch floor/track consistency untested | **pinned here** (both conventions, all angles) |
| tripwire messages named only the kept-whole shape | widened to both shapes |
| curved-girder misalignment survey (U15-2's first-order bend limitation) could now ride `_floor_step` | ledgered as a todo row — an opportunity, not a defect |
| CI flake tally | 4/4 green on 1.12.6; ledger row updated |
