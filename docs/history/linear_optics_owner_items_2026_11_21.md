# The LinearOptics owner items 1, 4 and 5 (2026-11-21)

The second batch of [`linear_optics_2026_11_21.md`](linear_optics_2026_11_21.md).
Walking through the design note's section 4 with the owner (2026-11-21), the
owner chose to close items 1, 4 and 5 together, item 1 through the unified
`LinearOptics` interface rather than a flat `form` keyword, then item 2
(retiring `XY_UNDEF`) as its own batch, and to be reminded of item 3 after
both. Design: [`../design/linear_optics.md`](../design/linear_optics.md),
D11-D13.

## 1 What changed

- `ChromaticityKickSpec` and `LumpedRadSpec` store `form` (1 or 2; `ParamMeta`
  default 1, alternatives (1, 2)) and compile their `XYCoupling` in that form
  (`_coupling_mode(_optics_form(...))`), so a `LinearOptics` point in form 2
  is accepted and couples in `XY_MODEB`. The shared resolver
  `_resolve_optics_keywords` returns the form (the point's, or 1 from the
  flat keywords) and lost its `form1_only` switch; the flat keyword `form=2`
  is refused by name with the pointer to the point, `form=1` is accepted as
  the explicit default, and the raw `ElementSpec{kind}(; form=2)` spells
  form 2 directly. The untyped `ChromaticityKickSpec` passes the point itself
  to the typed form so the form travels with it. Docstrings, the `R` meanings,
  the new `form` meanings and both construction helps say so.
- The effectiveness contract's probes for the two kinds carry a nonzero `R`
  and three-plane Twiss, and `_perturb_coupled_overrides` gives `form` its
  joint move: the probe re-spelled as the same point in form 2 with the flat
  keywords withdrawn, so the only difference between the two specs is the
  form.
- `LumpedRadSpec(; ...)` without `{T}` promotes its named parameters (and a
  point's parts) over the `Float64` floor through `_linear_map_eltype`, as
  the other untyped element forms do; `sigma` keeps the typed form's default
  when not given. A non-float type now constructs and is refused by name at
  compile.
- `preferred_form`: the type docstring, the option's description and the
  selection's docstring state that `:auto` is form 1 under the x-dominant
  labelling of mode 1 and never presents form 2; the rule itself is unchanged.
- Tests: the LinearOptics testset's two form-2 refusals became stored-form
  assertions; the new testset "Owner items 1, 4, 5 ..." checks the stored and
  compiled form, that a form's kick (and damping element) equals that form's
  coupling conjugating the uncoupled map and that the two forms differ, every
  refusal and the raw spelling, the help text, the untyped radiation
  promotion (Float32 and integers to Float64, BigFloat promoted, Float32 by
  `numeric_type`, a complex input refused at compile by name), and the
  `:auto` tripwire over four coupled fixtures including a form-2 point.

## 2 Verification

- `validate_element_metadata()` passes (613 default pairs checked, the two
  `form` defaults among them, through the friendly constructors);
  `validate_configuration_metadata()` passes with the new `preferred_form`
  description; both `element_help` forms of the two kinds name `form` and the
  point. `write_registry_snapshot()` reproduces the committed snapshot byte for
  byte (it lists no per-kind parameters and no option descriptions).
- `validate(ElementParameterEffectivenessContract())` passes with 555 checked
  (553 before this batch): `chromaticity_kick.form` and
  `lumped_radiation.form` are effective through the joint move. The suite's
  ratchet rises from 551 to 553.
- Extracted from the suite after the change (`using Octopus`, blocks cut out
  by title, 2026-11-21 18:07 to 18:20 EST, every block green): the new
  testset (49 of 49, after two fixes to its own accessors), "LinearOptics: the
  shared optics object feeds every consumer by one flattening rule" (115, the
  two flipped pins included), the F-97 metadata testset (48), "Thin elements,
  markers and RBEND" (114, carries the ratchet), "One precision rule: every
  element kind declares its beam type ..." (652), "Lumped radiation method and
  flag semantics" (18), "Precision policy of the modulated cavities and the
  radiation element" (68), "The untyped ChromaticityKickSpec promotes its named
  parameters over the Float64 floor (F-94)" (10), "The radiation element warns
  when nothing it was asked for can run ..." (40), "The deprecated CUDA
  LumpedRad route draws from the counter RNG" (13), and the five sweeps
  (Core.Box 5, every export documented 1, detached docstrings 11, every export
  in the snapshot 17, Architecture integrity 49). The kernels are unchanged
  (the form is a runtime field both branches of `XYCoupling` already compile
  for), so the backend-consistency scripts run where they always do, in the
  gate's CUDA arm.

## 3 The gate

The batch changes element metadata and public configuration descriptions
(the matrix: full). The full gate with CUDA active ran on this batch's
working tree after this record was written and the tree was committed
unchanged; its numbers are in the commit message of this batch.

## 4 Ledger and the previous batch's CI

`docs/README.md`: this record. `docs/todo.md`: the LinearOptics row (items
closed, the two still open). `docs/experiences.md`: "An option whose rule can
never pick one of its values must say so". `docs/registry_snapshot.md`:
regenerated (the two kinds' `form` parameter, the summaries). The examples batch pushed before this one (06b64f0..9f3c8c3, 2026-11-21 17:21 EST): CI run
480 (id 44956295179) completed with success at 2026-11-21T23:33:31Z (about 72 min), the
CPU full lane on the GitHub runner standing in for the AVX2 parity arm as on 2026-11-03;
its annotations report the stage 6 identity pins 6/6 and 5/6 (sapphirerapids), the
runner's own table.
