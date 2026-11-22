# `LinearOptics`: one optics object for the linear-optics consumers

> **Status: designed 2026-11-16 to 2026-11-21 in owner discussion; the owner
> authorised implementation on 2026-11-21 ("a tech note first, then
> implementation and validation, audit following, finally commit and push").
> This note is the tech note; the campaign record that retires its pending
> markers is `../history/linear_optics_2026_11_21.md`. Implemented 2026-11-21
> (D1-D10, every stage); gate and push: see the record.** Parent notes:
> `twiss_dispersion_analysis.md` (the analysis that reads these quantities
> back), `../theory/twiss_dispersion.md` (the conventions: Edwards-Teng forms
> (T2)-(T4), canonical dispersion (D1)-(D3)), `beam_initialization.md` (the
> matched beam), 

## 1. The problem

The quintuple (beta, alpha, zeta, eta, R) that fixes the linear optics of a
lattice point is spelled on six constructors with no object between them,
and the symbol `R` does not mean one thing (measured 2026-11-21, reading
pass over `src/elements/linear6d.jl`, `linear_maps.jl`,
`chromaticity_kick.jl`, `radiation.jl`, `strong_beam.jl`, `src/beam/Beam.jl`):

| constructor | spelling | what `R` is | coupling form |
|---|---|---|---|
| `Linear6DSpec` optics form | `beta1, alpha1, zeta1, eta1, R1` and the exit twins, `dmu` | the Sagan-Rubin block `C` with normaliser `sqrt(1 - det C)` (`_mR66`, linear6d.jl:431-446) | form 1 only, no admissibility guard (`DomainError` from `sqrt`) |
| `XYCouplingSpec` | `r1..r4, mode` | the Edwards-Teng matrix R = [r1 r2; r3 r4], lambda = 1/sqrt(1 + det R) (linear_maps.jl:415-433) | `XY_MODEA` = form 1, `XY_MODEB` = form 2, pinned (runtests.jl:2795-2806) |
| `Beam` | `beta, alpha, sigma|emit, coupling|R|C, mode, eta, zeta` | `(r1..r4)` of `XYCoupling` | both, through `mode` |
| `ChromaticityKickSpec` | `xi, beta, alpha, zeta, eta, R` | `(r1..r4)`; `XYCoupling(R..., XY_MODEA)` hard-coded (chromaticity_kick.jl:116) | form 1 only |
| `LumpedRadSpec` | `damping_turns, beta, alpha, sigma, zeta, eta, R` | `(r1..r4)`; `XY_MODEA` hard-coded (radiation.jl:205) | form 1 only |
| `ThinStrongBeamSpec` | `beta, alpha, sigma, covariance, coupling` | an `XYCouplingSpec`, an `XYCoupling` or a 4x4 matrix, never a tuple (strong_beam.jl:1488-1510) | both, through the spec's mode; no dispersion |

The same four numbers given as `Linear6DSpec`'s `R1` and as `Beam`'s `R`
build different coupling maps unless they are zero: `C = lambda adj(R)`,
`R = adj(C)/sqrt(1 - det C)`. No schema meaning states either convention
(the `R1`/`R2` and `R` meanings read "x-y coupling coefficients"), and the
`Beam` docstring claims `R` is "the element specs' spelling", true for two
elements and false for `Linear6DSpec`. The analysis, meanwhile, reads the
quantities back (`TwissDispersionResult.physical`) with no constructible
counterpart; its eigenmode Twiss are stored only in scaled coordinates
(`EdwardsTengPair.formK.twiss`) and the longitudinal mode's Twiss are not
stored at all. The owner's lattice scripts show the user-side cost: every
`transfer(b1, b2, mux, muy)` repeats the point tuples, a backward transfer is
a hand-written negative phase, and adding dispersion would add four tuples
per call.

## 2. Decisions

- **D1 Types.** Three plain value types, `T<:Number`, in
  `src/knowledge/LinearOptics.jl`:
  `EdwardsTengTwiss(; beta, alpha=(0,0,0), R=(0,0,0,0), form=1)` -- 3-tuples
  over the three canonically decoupled modes (x, y, z; the third is the
  longitudinal mode, which R never touches) and the Edwards-Teng matrix
  `R = (r1, r2, r3, r4)` of (T2) in form 1 or 2;
  `CanonicalDispersion(; zeta=(0,0,0,0), eta=(0,0,0,0))` with `h` derived
  and a `slope=` constructor for the Xsuite/MAD-X dispersion;
  `LinearOptics(twiss, dispersion; mu=nothing, s=nothing, frame=nothing)` with
  the flat form `LinearOptics(; beta, alpha, R, form, zeta, eta, slope, mu, s, frame)`.
  The composite is named for what it is; the parts carry the parameterization,
  leaving room for a Mais-Ripken-parameterized point later. Refused by name
  at construction: non-positive beta, non-finite entries, `1 + det R <= 0`
  (the analysis's `:form_inadmissible`), a form other than 1 or 2, `eta`
  beside `slope`, `mu` without `frame`.
- **D2 Conventions, stated once in the type docstrings and repeated in every
  consumer's `ParamMeta` (F-99 rule).** R and lambda = 1/sqrt(1 + det R) as
  in (T2)-(T3); form 1 is V1 = lambda [I adj(R); -R I] = `XY_MODEA`, form 2 is
  V2 = lambda [adj(R) I; I -R] = `XY_MODEB`. zeta, eta are canonical,
  h = 1 - zeta' S4 eta; the slope d = eta/h converts back with
  h = 1/(1 + zeta' S4 d), eta = h d. The normalizer of a point is
  N = M_zeta M_eta V_form(R) B(beta, alpha), the order `Linear6DSpec`,
  `Beam`, `ChromaticityKickSpec` and `LumpedRadSpec` already apply.
- **D3 Flattening, never storage.** Every consumer gains ONE alternative,
  `optics = o` (the positional pair `Linear6DSpec(o1, o2)`), flattened into
  the existing stored parameters at construction. Nothing new is stored, so
  the spec layer, its metadata, provenance, the registry snapshot and every
  kernel are unchanged; the object form and the flat form must build a
  bitwise-identical spec or beam. `Linear6DSpec` receives
  `C = adj(R)/sqrt(1 + det R)`; `Beam`, `ChromaticityKickSpec`, `LumpedRadSpec`
  receive `R`; `ThinStrongBeamSpec` receives `XYCouplingSpec(R..., mode)`.
- **D4 Exclusive forms, refused by name; no silent partial reads.** `optics`
  beside any flat optics keyword is an `ArgumentError` naming both, the rule
  `Linear6DSpec` applies to `matrix` beside its optics keywords and `Beam` to
  its coupling spellings. A consumer that cannot honour a nonzero part of the
  object refuses it by name: `ChromaticityKickSpec` and `LumpedRadSpec`
  refuse form 2 (their coupling is form 1 by construction; the extension is a
  follow-up row), `ThinStrongBeamSpec` refuses nonzero dispersion (its
  covariance is transverse) and the bounded `Beam` distributions refuse
  `optics` as they refuse every other optics keyword.
- **D5 Phases are positions.** `mu` is the 3-tuple of decoupled mode phases
  in radians, unwrapped, acting as the point's position; it requires `frame`
  (a `Symbol`), because a phase is relative to a reference and two unrelated
  points must not be subtracted silently. `Linear6DSpec(o1, o2)` takes
  `dmu = o2.mu .- o1.mu` when both points carry phases in one frame, an
  explicit `dmu` when neither does, and refuses a disagreement, a frame
  mismatch, or a pair of which only one carries phases while `dmu` is absent.
  `advance_phase(o, dmu)` is the one-turn idiom,
  `Linear6DSpec(o, advance_phase(o, 2pi .* tune))`. `s` is bookkeeping.
- **D6 The analysis closes the loop.** `linear_optics(result; frame=nothing, s=nothing)`
  builds the point in the caller's coordinates: the Edwards-Teng R and form
  presented by the analysis (`physical.edwards_teng_R`, `transverse.preferred_form`),
  the eigenmode Twiss of that form unscaled from `EdwardsTengPair.formK.twiss`
  by `_unscale_twiss` with the plane carrying each mode (form 1: mode j in
  plane j; form 2: exchanged), the canonical `physical.zeta`, `physical.eta`,
  and the longitudinal mode's beta, alpha from `_twiss_from_block` on the
  separation's `longitudinal_map`, unscaled in plane 3 (cross-check:
  `physical.beta[3,3]` and `physical.alpha[3,3]/h`). `mu = (0,0,0)` when a
  frame is given, else `nothing`. An undetermined quantity throws
  `UndeterminedQuantityError` with the analysis's reason; a 4x4 input has no
  dispersion and no longitudinal mode and is refused as an `ArgumentError`.
  Measured while implementing (2026-11-21): the analysis labels mode 1 as
  the x-dominant mode, so under `preferred_form = :auto` it presents form 1
  whenever that form is admissible, and a point written in the other
  labelling -- a form-2 `EdwardsTengTwiss` whose first mode is y-dominant --
  comes back as the form-1 point with the two transverse modes exchanged and
  the same R ((T4)); the rebuilt map is the same to 1e-13. A form-2
  presentation is obtained on request (`preferred_form = 2`) and then
  round-trips under the same request. The suite therefore compares maps in
  every case and labels only where the labelling is canonical.
- **D7 Form 2 reaches `Linear6DSpec`.** The optics form gains the stored
  parameters `form1`, `form2` (1 or 2, default 1, exit defaults to entrance):
  `_mR66(C, 1) = [gI C; -adj(C) gI]`, `_mR66(C, 2) = [C gI; gI -adj(C)]`,
  g = sqrt(1 - det C), and the admissibility `det C < 1` becomes a named
  refusal instead of a `DomainError`. Without this a form-2 point could not
  feed the map; with R = 0 the form is inert, which the effectiveness probe
  must see through a probe carrying nonzero `R1`.
- **D8 `XY_UNDEF` stops ignoring coefficients.** `XYCouplingSpec(r1=0.01, mode=XY_UNDEF)`
  and the `Beam` Gaussian path with nonzero coupling under `XY_UNDEF` are
  refused by name (today both are silently the identity; the suite pins the
  identity at runtests.jl:15568 and changes with this batch). Full retirement
  of the mode is an owner item.
- **D9 Elementary maps from parts.** `XYCouplingSpec(t::EdwardsTengTwiss)`,
  `MomentumDispersionSpec(d::CanonicalDispersion)`, `CrabDispersionSpec(d)`.
- **D10 Conventions documented where they were missing.** The `R1`/`R2`
  meanings of `Linear6DSpec` state the block convention and the conversion;
  the `R` meanings of `ChromaticityKickSpec` and `LumpedRadSpec` state the
  Edwards-Teng form-1 convention; the `Beam` docstring stops claiming one
  spelling for all element specs.

### Decisions of the second batch (2026-11-21, the owner items 1, 4, 5 of section 4)

- **D11 Form 2 reaches `ChromaticityKickSpec` and `LumpedRadSpec` through the
  point only.** Both kinds store `form` (1 or 2, declared alternatives, default
  1) and compile their `XYCoupling` in that form; the value comes from the
  `LinearOptics` point given as `optics` (its `twiss.form`). The flat keywords
  couple in form 1: `form=1` is accepted as the explicit spelling of the
  default, `form=2` is refused by name with the pointer to the point, and the
  raw `ElementSpec{kind}(; form=2)` spells it directly, as every stored
  parameter can be. The owner asked for the unified interface rather than a
  second flat spelling (2026-11-21); the stored parameter exists because the
  runtime must read the form and the validators read declared defaults
  through the friendly constructor. The effectiveness contract probes `form`
  by a joint move that re-spells the probe as the same point in form 2
  (`_perturb_coupled_overrides`), the generic alternative `form=2` being the
  refused flat spelling; the probes carry a nonzero `R` so that the form is
  the only difference between the two specs.
- **D12 The untyped `LumpedRadSpec` promotes.** `LumpedRadSpec(; ...)` takes
  its type from the named parameters over the `Float64` floor through
  `_linear_map_eltype`, as every other untyped element form does (integers,
  rationals and `Float32` land on `Float64`; wider types promote); until this
  batch it fixed `Float64` whatever it was given. A non-float type constructs
  and is refused by name at compile ("lumped radiation parameters must be
  real floating-point values"), where before an `InexactError` fired inside
  the constructor.
- **D13 `preferred_form = :auto` is form 1, and says so.** The rule "the
  admissible form with the larger area weight, ties to form 1" is kept, but
  the analysis labels mode 1 as the x-dominant mode, so form 1's weight
  `1 - u` exceeds form 2's `u` and form 1 is admissible whenever the pair is
  (`lambda^2 = 1 - u > 0`): `:auto` never presents form 2. The option's
  description, the type docstring and the selection's docstring state this;
  a tripwire asserts it on coupled fixtures, a form-2 point among them, and
  that `2` still presents form 2.

### Decision of the third batch (2026-11-21, the owner item 2 of section 4)

- **D14 `XY_UNDEF` retired.** The enum `XYCouplingMode` is the two Edwards-Teng
  forms, `XY_MODEA = 1` and `XY_MODEB = 2`; the zero member that made
  `XYCoupling` the identity is gone, with its branch in the tracking kernel,
  in `_inverse` and in the cross-backend rounding class, the coefficient
  check D8 added for it, and its mention in the Beam docstring and the mode
  metadata. Zero coefficients in form 1 (`XY_MODEA`, the default) give the
  identity, the only meaning the member had; in form 2 they give the exchange
  of the transverse planes, as V2's definition says (the suite's first run of
  the retirement caught the claim "identity in either form"). A script naming `XY_UNDEF` fails loudly with an
  undefined-variable error; specs are in-memory objects, so nothing stored
  needs a migration. The symbol-removal class of the matrix: a repo-wide grep
  of `src/`, `test/`, `docs/`, `examples/`, `validation/` and `profiling/`
  found every mention listed in the record.

### Decision of the fourth batch (2026-11-21): the recommendation

- **D15 The point is the recommended spelling.** Every consumer's docstring
  and construction help, the `LinearOptics` docstring and
  `docs/public_api.md` say so: new scripts, examples and documentation give
  linear optics as `LinearOptics` points (`Beam(; optics)`,
  `Linear6DSpec(o1, o2)`, `ChromaticityKickSpec(; optics)`,
  `LumpedRadSpec(; optics)`, `GaussianStrongBeamSpec(; optics)` (since
  2026-11-22 the strong beam's recommended spelling; `ThinStrongBeamSpec(; optics)`
  is deprecated and kept, `strong_beam_element.md` S7),
  `XYCouplingSpec(o.twiss)`), and a point built by `linear_optics(result)`
  feeds them directly. The flat keywords remain as the stored representation
  (what `params(spec)` holds and the raw `ElementSpec{kind}(; ...)` form
  accepts) and as the spelling of scripts written before the point; nothing
  is deprecated or refused. Measured reason: the flat example scripts shipped
  with the maps' dispersion and coupling at zero whatever the beam input said
  (the examples batch), and one object makes the beam and the lattice one
  description. Owner request, 2026-11-21.

## 3. Staging, tests, verification

One batch, one record. Stage 1: D1, D2, `Linear6DSpec(o1, o2)`, `Beam(; optics)`,
`linear_optics`. Stage 2: `ChromaticityKickSpec`, `LumpedRadSpec`,
`ThinStrongBeamSpec`, D9. Stage 3: D7, D8, D10.

Baseline first (audit protocol): `../history/linear_optics_2026_11_21_baseline.jl`
hashes the flat-form outputs of every consumer (matrices, tracked
coordinates, Gaussian and grid beams on CPU and CUDA) before the first edit;
the same hashes must come back after the batch, since the flat path must not
move.

Suite testset "LinearOptics: the shared optics object": construction and
every refusal of D1, D4, D5, D8; bitwise identity of the object and flat
forms for every consumer (`params(spec)` equality; `Beam` coordinates under
one seed); the phase rules and the one-turn idiom; D7's matrix equal to the
V2 construction and symplectic; the round trip
`LinearOptics -> Linear6DSpec(o, advance_phase(o, tune)) -> analyze -> linear_optics`
with nonzero R in both forms, nonzero zeta and eta, to a stated tolerance; the
second moments of `Beam(; optics)` against `matched_covariance`; the
`XY_UNDEF` refusals; `element_help` of every touched kind naming `optics`.

Matrix classes touched: element spec and metadata, public configuration
(`Beam` keywords), contracts (acceptance semantics of D7, D8), public
documentation. Finish: `validate_element_metadata()`, both `element_help`
forms, `write_registry_snapshot()`, the extracted sweeps, the fast lane, the
full gate with CUDA active on the final tree, the record, the push.

## 4. Open after this batch (owner items)

Closed by the second batch (D11-D13, record
[`../history/linear_optics_owner_items_2026_11_21.md`](../history/linear_optics_owner_items_2026_11_21.md)):
form 2 on `ChromaticityKickSpec` and `LumpedRadSpec`; `LumpedRadSpec`'s
untyped form fixing `Float64`; whether `preferred_form = :auto` ever presents
form 2.

Closed by the third batch (D14, record
[`../history/linear_optics_xy_undef_2026_11_21.md`](../history/linear_optics_xy_undef_2026_11_21.md)):
retiring `XY_UNDEF`.

Still open:

- Dispersion in the strong beam through `gaussian_strong_beam_covariance`,
  which builds the 6x6 covariance `GaussianStrongBeamSpec` already consumes
  (the transverse Gaussian conditional on z, the crab slope per slice) and
  which nothing in the source calls; it needs the strong beam's momentum
  spread as a new input. Waits for the owner's word on whether a dispersive
  strong beam is needed.
  Resolved 2026-11-22 by [`strong_beam_element.md`](strong_beam_element.md) S2:
  `GaussianStrongBeamSpec(; optics)` consumes a dispersive point at the slice
  level through `gaussian_strong_beam_covariance` with `sigma_delta`.
