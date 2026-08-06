# U24 Report — validation/ (PTC provenance, symplecticity sweep, print-only gates)

Commit audited: `b986c73`. Reading unit U24 of the 2026-08-05_b comprehensive audit,
closing a declared coverage gap (region not read before the Phase 16 halt).
Prior unit report for the same tree: `docs/history/comprehensive_audit_2026_08_05_unit_reports/U21_report.md`
(commit `dbefe42`).

## Region and provenance

Read **line by line, every line**:

| file | lines | read | executed |
|---|---|---|---|
| `validation/slice_longitudinal_zscan.jl` | 618 | yes | yes (36.6 s, `--threads=4`) |
| `validation/high_energy_weakstrong_limit.jl` | 423 | yes | yes (44.6 s CPU; 84.0 s with `OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1`) |
| `validation/generate_ptc_reference.jl` | 356 | yes | yes (~11 s, 55 MAD-X jobs, scratch copy) |
| `validation/gaussian_slicing_convergence.jl` | 291 | yes | yes (40.1 s) |
| `validation/strong_strong_spectral_comparison.jl` | 276 | yes | yes (134.4 s, `--threads=4`) |
| `validation/lattice_cells.jl` | 244 | yes | yes (158.6 s, CUDA leg ran) |
| `validation/slice_interpolation_emittance_growth.jl` | 239 | yes | partial (60 of 600 turns, 71.9 s — see "runtime cap") |
| `validation/symplecticity_validation.jl` | 156 | yes | yes (31.7 s) |
| `validation/slice_interpolation_emittance_growth_summary.jl` | 116 | yes | yes (read-only over the repo `result/`) |

Also read for cross-checking (not my region, cited as seams):
`src/contracts/Contracts.jl` §§ `SymplecticityContract` (1114–1192), `_symplecticity_contract_cases`
(1172–1243), `PTCConsistencyContract` / `_ptc_reference_specs` / `_ptc_reference_path` / `validate`
(1605–1900); `validation/reference/ptc_madx_5.03.06.tsv` (all 282 lines, mechanically);
`validation/README.md` §§ for all nine scripts; `test/runtests.jl:7103–7131`;
`docs/theory/slice_longitudinal_interpolation.md` §§10–11;
`docs/history/gaussian_slicing_convergence_2026_07_31.md`;
`git diff 6a3f39ab HEAD -- validation/` for all six changed files of my region.

**No repository file was modified.** `git status` clean at exit; no file under `result/` has an
mtime later than 14:12 (my session ran 19:50–20:15). Every script that writes under `result/` was
run from a sed-redirected copy in
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/runs/`,
or via its own output-prefix environment variable.

## Diff since `6a3f39ab` — what the audit already repaired, verified at HEAD

| prior lead | repair present? | evidence |
|---|---|---|
| U21-6 (`Case.octopus` dead + drifted) | **yes** | the `octopus::Dict` field is gone from `struct Case`; specs live only in `_ptc_reference_specs()` |
| U21-7 (lexicographic PTC pick) | **yes** | `natkey` sort at `Contracts.jl:1832-1833`; measured below |
| U21-2 (spectral MODEL verdict unasserted) | **yes** | `high_energy_weakstrong_limit.jl:422` now errors on `spectral_model_passed` |
| U21-3 (lattice_cells print-only) | **partial** | gate added at `lattice_cells.jl:239-243`; covers 2 of 4 declared metrics — **LEAD U24-2** |
| U21-8 (undocumented 4th zscan output) | **yes** | header lines 73-75; `lagrange3` dead helper removed |
| U21-11 (gaussian convergence print-only, dead config) | **yes (declared inert)** | header lines 7-12; `ns_crosscheck` removed |
| U21-4 (symplecticity case list 8 of 12) | **partly** | list now derived (12/12) — but the header tolerance and the coverage claim are unrepaired: **LEADS U24-3, U24-4, U24-5** |

---

# (a) THE PTC PROVENANCE CHAIN — verified end to end

### (i) Case count, independently measured

| stage | count | how measured |
|---|---|---|
| generator `CASES` | **55** | `grep -cE '^    Case\("' validation/generate_ptc_reference.jl` |
| committed table, distinct case names | **55** | `tail -n +8 …tsv \| cut -f1 \| sort -u \| wc -l` |
| contract `_ptc_reference_specs()` keys | **55** | `grep -oE '^        "[a-z0-9_]+"' Contracts.jl:1636-1817` |
| contract-consumed rows at runtime | **275** | `validate(PTCConsistencyContract()).metrics[:rows]` |
| contract-consumed cases at runtime | **55** | `.metrics[:cases]` |

The three **name sets are identical** — `diff gen_names.txt table_names.txt` and
`diff table_names.txt contract_names.txt` both empty. Every case has exactly 5 rows
(275 = 55 × 5); every row has exactly 14 tab fields; zero duplicate `(case, particle)` pairs;
zero NaN/Inf/non-numeric tokens in columns 3–14; the five distinct initial-coordinate tuples in
the table are exactly the five entries of `PARTICLES`, with `z0 = 0` on all of them as the writer
hardcodes.

Contract verdict, measured: **passed**, `madx_version = 5.03.06`, `max_deviation =
4.995292374188054e-13` against `default_atol = 1e-11`. This **independently confirms** the sibling
unit's 55/55/55 and worst deviation 5.0e-13. Worst five cases: `quad_mis_dpsi` 4.995e-13,
`cfbend_m2_n4` 4.993e-13, `rbend_k1` 4.969e-13, `quad_mis_all` 4.957e-13, `sextupole_m4_n2`
4.947e-13. `_PTC_DEFAULT_ATOL` is still an empty `Dict`, which the contract docstring now states
explicitly (U3-9 repair present).

### (ii) Version and flags recorded in the artifact, not only in a comment

The committed table's own first three lines:

```
# PTC reference for PTCConsistencyContract
# MAD-X version: 5.03.06
# flags: model=1 (drift-kick-drift), exact=true, time=false
```

plus three more comment lines pinning the `T`-negation convention. The version is additionally
encoded in the filename, and `validate` parses it back out of the file (`Contracts.jl:1844`) into
`metrics[:madx_version]`, so the version travels with the data rather than with the generator.
**Sound.**

### (iii) The "lexicographic PTC-table pick" — repaired; residual risk not live

`_ptc_reference_path` now sorts by `natkey(f) = [parse-each-digit-run]` rather than by string.
Measured:

- `["ptc_madx_5.9.0.tsv", "ptc_madx_5.10.0.tsv"]` → `natkey` picks `5.10.0`; **lexicographic picks
  `5.9.0`** (wrong). The fix is real.
- `["ptc_madx_5.03.06.tsv","ptc_madx_5.09.00.tsv","ptc_madx_5.10.00.tsv"]` → both orderings pick
  `5.10.00`, because MAD-X zero-pads its minor fields. So on MAD-X's *actual* naming the old bug
  was latent, not live; `natkey` is the correct defensive fix regardless.
- Today `readdir(validation/reference)` returns exactly one file, and
  `_ptc_reference_path(PTCConsistencyContract())` resolves to
  `validation/reference/ptc_madx_5.03.06.tsv`. **The risk is not live.**

Residual (unchanged, minor): a second committed table is still *silently* shadowed — no warning
names the file that lost. With one table, nothing to report.

### (iv) Does regeneration reproduce the committed file? — YES, byte-identical

MAD-X **is** installed on this machine (`/usr/local/bin/madx`, banner `MAD-X 5.03.06 (64 bit,
Linux)`), matching the committed table's recorded version. I copied
`generate_ptc_reference.jl` verbatim into scratch (its `OUTDIR = joinpath(@__DIR__, "reference")`
makes the copy write to scratch with **zero edits**) and ran it:

```
diff scratch/reference/ptc_madx_5.03.06.tsv validation/reference/ptc_madx_5.03.06.tsv
→ (no output)  BYTE-IDENTICAL, 55874 bytes, 55 cases, ~11 s for all 55 MAD-X jobs
```

This is the strongest form of the provenance claim available: the committed reference is
reproducible from the committed generator on the recorded MAD-X version, at bit level.

**PTC chain verdict: SOUND.** One minor lead against the generator (U24-10, non-atomic write).

---

# (b) THE SYMPLECTICITY SWEEP'S CASE LIST — DERIVED, 12 = 12

**Verdict: the script DERIVES; it does not carry a copy.**

`validation/symplecticity_validation.jl:87` is the whole of it:

```julia
symplecticity_cases() = Octopus._symplecticity_contract_cases()
```

**BOTH COUNTS:**

| side | count | how measured |
|---|---|---|
| `SymplecticityContract` (`_symplecticity_contract_cases()`) | **12** | `length(O._symplecticity_contract_cases())` |
| `symplecticity_validation.jl` | **12** | the script executed: 12 result lines printed |

Names, identical by construction and confirmed in the run output: `Linear6D, CrabDispersion,
MomentumDispersion, XYCoupling, ThinCrabCavity, ChromaticityKick, ThinStrongBeam,
ThinStrongBeamChromatic, ThinStrongBeamExact, GaussianStrongBeam, Solenoid,
SolenoidCurvedMultipole`. Measured residuals (script run, all passed):

```
Linear6D 1.502e-13 / CrabDispersion 1.319e-13 / MomentumDispersion 1.807e-13 / XYCoupling 1.319e-13
ThinCrabCavity 1.319e-13 / ChromaticityKick 4.163e-13 / ThinStrongBeam 7.9077e-8
ThinStrongBeamChromatic 7.9077e-8 / ThinStrongBeamExact 7.9077e-8 / GaussianStrongBeam 4.240e-8
Solenoid 6.657e-10 / SolenoidCurvedMultipole 2.119e-10
Lorentz: inverse residual 8.267e-19, determinant error 4.134e-13 — passed
```

The Measured-Lesson-4 half that is **still missing** is the tripwire (LEAD U24-5): the
declaration↔coverage tripwire lives in `validate(::SymplecticityContract)`
(`Contracts.jl:1276-1298`), which the script never calls. `run_symplecticity_validation` only maps
residuals over the cases.

**Tripwire measurement (positive + negative control), on the contract side:**

- As shipped: `validate(SymplecticityContract())` → `passed=true`,
  `metrics[:kinds_declaring_without_case] = 0`.
- Negative control (case list filtered to drop the two `Solenoid` cases, same tripwire loop):
  `uncovered = [:solenoid]` → tripwire **fires**. The mechanism works.

**And it inherits the near-tautology, confirmed independently:** exactly **ONE** registered kind
declares `SymplecticityContract` in its metadata — `[:solenoid]` — so the tripwire constrains one
kind, which the list already covers twice. Meanwhile **22** registered kinds support
`Symplectic6DMap`, and only **7** of them have a case:

```
WITH a case (7):    :chromaticity_kick :crab_dispersion :linear6d :momentum_dispersion
                    :solenoid :thin_crab_cavity :xy_coupling
WITHOUT a case (15): :drift :hkicker :kicker :marker :multipole :octupole :quadrupole :sbend
                     :sextupole :thin_dipole :thin_multipole :thin_quadrupole :thin_rf_cavity
                     :thin_sextupole :vkicker
```

That gap is what makes both the script header and `validation/README.md` false (LEAD U24-3).

---

# (c) PRINT-ONLY vs ENFORCED — every threshold in the region

`E` = the script exits non-zero when the threshold is exceeded. `P` = computed and printed/written,
never compared.

| file:where | threshold | value | E/P |
|---|---|---|---|
| `symplecticity_validation.jl:119,150` | per-case `residual <= max(case.tolerance, DEFAULT_TOL)` | floor 5e-8, cases 5e-8…5e-6 | **E** |
| `symplecticity_validation.jl:110,154` | Lorentz `inverse_residual <= inverse_tolerance` | 1.0e-10 | **E** |
| `symplecticity_validation.jl:111,154` | Lorentz `determinant_error <= determinant_tolerance` | 2.0e-7 | **E** |
| `symplecticity_validation.jl` (absent) | declaration↔coverage tripwire | — | **absent** (U24-5) |
| `high_energy_weakstrong_limit.jl:380,417` | `gaussian_proton_max_abs_error <= …` | 2.0e-14 hardcoded | **E** |
| `high_energy_weakstrong_limit.jl:381,417` | `gaussian_luminosity_rel <= …` | 2.0e-12 hardcoded | **E** |
| `high_energy_weakstrong_limit.jl:382,418` | `pic_luminosity_rel <= PIC_LUM_RTOL` | 0.08 (env) | **E** |
| `high_energy_weakstrong_limit.jl:382,418` | `pic_size_rel <= PIC_SIZE_RTOL` | 0.08 (env) | **E** |
| `high_energy_weakstrong_limit.jl:229,419` | spectral `proton_limit_max_abs <= limit_atol` | 5e-13 (env) | **E** |
| `high_energy_weakstrong_limit.jl:230,419` | spectral `electron_change <= limit_atol` | 5e-13 (env) | **E** |
| `high_energy_weakstrong_limit.jl:231,419` | spectral `limit_lum_rel <= limit_lum_rtol` | 1e-12 (env) | **E** |
| `high_energy_weakstrong_limit.jl:232,422` | spectral `model_lum_rel <= model_lum_rtol` | 0.08 (env) | **E** (new) |
| `high_energy_weakstrong_limit.jl:233,422` | spectral `model_size_rel <= model_size_rtol` | 0.08 (env) | **E** (new) |
| `high_energy_weakstrong_limit.jl:279-281,419` | CUDA spectral limit trio | same as CPU | **E when `SPECTRAL_CUDA=1`**; default off, opt-in documented |
| `lattice_cells.jl:178` | a stable working point exists per cell family | — | **E** |
| `lattice_cells.jl:240` | `symplectic_residual <= 5.0e-7` | 5e-7 hardcoded | **E** |
| `lattice_cells.jl:214,241` | CPU/CPU `ElementTrackingBackendConsistencyContract` | atol/rtol 1e-12 | **E** |
| `lattice_cells.jl:218,242` | CPU/CUDA contract | atol/rtol 1e-10, `:skipped` allowed | **E** (skip visible in stdout) |
| `lattice_cells.jl:203,205` | **invariant drift** over `LONG=2000` turns | — | **P** ← U24-2 |
| `lattice_cells.jl:204,205` | **final-cell linear stability `\|tr\|<2`** | 2 (search only) | **P** ← U24-2 |
| `generate_ptc_reference.jl:279` | MAD-X version parseable | — | **E** |
| `generate_ptc_reference.jl:328` | 5 tracked particles per case | — | **E** |
| `generate_ptc_reference.jl:312` | `madx` exits zero (`run` throws) | — | **E** |
| `strong_strong_spectral_comparison.jl:40,79,181` | input/CUDA/backend validation | — | **E** (not numerical) |
| `strong_strong_spectral_comparison.jl` | **any numerical agreement threshold** | — | **none exist**; pure characterization, README says "not an equality gate" |
| `slice_longitudinal_zscan.jl` | **any threshold** | — | **none exist**; whole script **P** |
| `gaussian_slicing_convergence.jl` | **any threshold** | — | **none exist**; whole script **P**, now declared inert in the header (lines 7-12) |
| `slice_interpolation_emittance_growth.jl` | **any threshold** | — | **none exist**; whole script **P** |
| `slice_interpolation_emittance_growth_summary.jl:40` | at least one meta file exists | — | **E** |
| `slice_interpolation_emittance_growth_summary.jl:115` | `\|t_like\| < 2` = "not resolved" | 2 | **P** (advisory text only; no comparison in code) |

Summary: 3 of 9 scripts have **no threshold of any kind** (`slice_longitudinal_zscan`,
`gaussian_slicing_convergence`, `slice_interpolation_emittance_growth`) — all three are
characterization studies and two of the three now say so in their header. One script
(`lattice_cells`) gates 2 of the 4 metrics its own header calls checks. The remaining five are
sound.

---

# (d) HEADER DRIFT — every disagreement, quoted

**`symplecticity_validation.jl:11` vs `:35`** (unrepaired since U21-4)

> header: `    OCTOPUS_SYMPLECTICITY_TOL=5e-7`
> code:   `const DEFAULT_TOL = parse(Float64, get(ENV, "OCTOPUS_SYMPLECTICITY_TOL", "5e-8"))`

**`symplecticity_validation.jl:13-14`** — false as measured

> "The script checks runtime maps that are registered as `Symplectic6DMap` plus the weak-strong
> beam-beam maps that are intended to be six-dimensional symplectic."

Measured: 7 of 22 `Symplectic6DMap`-supporting registered kinds have a case; 15 do not.

**`validation/README.md:385-387`** — the same claim, stronger

> "`symplecticity_validation.jl` computes finite-difference Jacobians for **all current
> six-dimensional symplectic runtime maps**"

**`lattice_cells.jl:2-3` and `:19-21`** — "checked"/"catches" for two ungated metrics

> "…checked for symplecticity, **closure** and CPU/CUDA consistency."
> "- **long-term Courant-Snyder invariant drift** over many turns, which catches a map that is
>   symplectic once but not stably so."

Neither is compared to anything. `validation/README.md:867-871` repeats it: "checks that they
compose into working lattices: one-turn symplecticity …, **linear stability in both planes,
Courant-Snyder invariant drift measured on momentum**, and CPU/CUDA tracking consistency."

**`lattice_cells.jl:24-30`** — "Cells: FODO / DBA / TBA" describes 3 cells; `CELLS` (line 183) runs
**6** (each with a `+sext` variant). The `+sext` variants are the only nonlinear elements exercised
and are undescribed in the Cells section.

**`slice_longitudinal_zscan.jl:34-38`** — describes 2 of the 4 grid-mode passes the code runs:

> "A second pass repeats the `:linear` scheme with a **per-slice** grid …"

The code additionally emits `source_slice_grid` (lines 388-419), `node_grid` (420-504) and
`node_source_evolution` (506-534) rows, and a whole extra printed table ("node grid vs
per-slice-pair", lines 613-616) that is written to no file. Four `grid_mode` values appear in
`_jumps.tsv`; the header names one.

**`strong_strong_spectral_comparison.jl`** — no `Outputs` section at all, though `main()` writes
five TSVs (`_timing`, `_luminosity`, `_moments`, `_coordinate_differences`,
`_field_microprofile`). `AGENTS.md` "Updating Validations" requires the header to state outputs.
Also the stale comment at lines 159-160:

> "This script was written before that and has not run since."

falsified today: I ran it at HEAD, exit 0, all five files written.

**`slice_interpolation_emittance_growth.jl:26-35`** — the arms table A–F documents
`interaction_grid=:source_slice` (arm F) but not `:node`, although the override list at line 73-74
documents `OCTOPUS_EMIT_GRIDMODE` (`slice_pair`/`source_slice`/**`node`**) and `result/` holds 14
`node` runs.

**`high_energy_weakstrong_limit.jl:8-23`** — all fourteen documented env defaults were checked
individually against the code and **all match**. The only gap is that the two Gaussian thresholds
(2.0e-14, 2.0e-12, lines 380-381) are the only tolerances in the file that are neither documented
in the header nor env-tunable.

**No drift found** in `generate_ptc_reference.jl` (flags, coordinate mapping, thin-sequence
rationale, outputs and run command all verified against the code and against the produced file) or
in `gaussian_slicing_convergence.jl` (reference model, error metric, both outputs, run command,
print-only declaration, Xoshiro caveat — all accurate).

---

# (e) DO THE RECORDED NUMBERS REPRODUCE?

## Reproduce — exactly

**`generate_ptc_reference.jl`** → committed table **byte-identical** (see (a)(iv)).

**`gaussian_slicing_convergence.jl`** vs `docs/history/gaussian_slicing_convergence_2026_07_31.md`
— every recorded figure reproduces, on Julia 1.12.4, despite the `Random.Xoshiro` caveat:

| quantity | recorded | measured |
|---|---|---|
| e-on-p Richardson order p / floor / cross-family | 2.05 / 5.3e-7 / 1.6e-5 | 2.05 / 5.292e-7 / 1.645e-5 |
| p-on-e Richardson order p / floor / cross-family | 1.95 / 3.4e-9 / 6.6e-8 | 1.95 / 3.352e-9 / 6.615e-8 |
| `:sqrt_density` Q at ns=5/15/31/61, order | 9.50e-3 / 1.01e-3 / 2.28e-4 / 5.67e-5, 2.06 | 9.498e-3 / 1.006e-3 / 2.280e-4 / 5.666e-5, 2.06 |
| `:equal_area_centroid` same | 1.15e-2 / 1.89e-3 / 6.84e-4 / 2.82e-4, 1.29 | 1.146e-2 / 1.892e-3 / 6.840e-4 / 2.821e-4, 1.29 |
| `:equal_area` / `:min_cdf_area` / `:gauss_hermite` / `#1` / `:equal_width` | all four columns each | all match to the recorded 3 s.f. |
| deficit orders (0.98 / 1.23 / 1.87 / 1.26) | recorded | 0.98 / 1.23 / 1.87 / 1.26 |
| Furman criterion, hirata and chromatic drift error | 6.3e-2, 3.9e-5, 1.4e-9 | 6.325e-2, 3.879e-5, 1.406e-9 |

**`slice_longitudinal_zscan.jl`** vs `docs/theory/slice_longitudinal_interpolation.md` §10.1 — all
six rows of the error table and all three rows of the jump table reproduce:

| src / comp | recorded peak / lin / quad / gain | measured |
|---|---|---|
| 4 Δp_x | 1.7e-5 / 7.5e-11 / 4.4e-11 / 1.7 | 1.7170e-5 / 7.549e-11 / 4.420e-11 / 1.708 |
| 4 Δp_y | 1.0e-5 / 2.3e-9 / 3.2e-10 / 7.3 | 1.0463e-5 / 2.3427e-9 / 3.2198e-10 / **7.276** |
| 4 Δp_z | 3.9e-11 / 1.29e-11 / 2.5e-12 / 5.2 | 3.8778e-11 / 1.2867e-11 / 2.4943e-12 / 5.158 |
| 6 Δp_x | 1.7e-5 / 2.2e-10 / 4.0e-11 / 5.5 | 1.6762e-5 / 2.2189e-10 / 4.0003e-11 / 5.547 |
| 6 Δp_y | 8.5e-6 / 1.2e-9 / 5.0e-10 / 2.4 | 8.4925e-6 / 1.1821e-9 / 4.9512e-10 / 2.387 |
| 6 Δp_z | 4.4e-10 / 1.24e-11 / 2.4e-12 / 5.2 | 4.3759e-10 / 1.2373e-11 / 2.3788e-12 / 5.201 |

Jumps: common/`:linear` Δp_z 0.45–0.52 recorded → 0.4547–0.5163 measured; common/`:quadratic`
0.039–0.11 → 0.0394–0.1092; common transverse ~2e-9 / ~2e-8 → 2.07–4.07e-9 / 1.61–2.98e-8;
per-slice Δp_x 1.0–1.6e-3 → 1.027–1.618e-3; per-slice Δp_y 0.3–4.8e-3 → 3.095e-4–4.836e-3;
per-slice Δp_z 0.04–0.69 → 0.0401–0.6925. The scratch `_cells.tsv` is **identical** to the
repository's prior artifact; `_summary.tsv` agrees to ~10 s.f. (differences at 1e-10 relative,
consistent with 4-thread reduction ordering).

**`lattice_cells.jl`** — the fresh `lattice_cells.tsv` is **byte-identical** to the repository's
prior `result/lattice_cells.tsv` (all 6 rows, all 9 columns). Working points reproduce
(FODO kq=1.60, DBA kf=1.50 kd=−1.10, TBA kf=0.90 kd=−1.00). CUDA leg ran and passed
(max|Δ| ≤ 1.332e-15).

**`high_energy_weakstrong_limit.jl`** — all four verdicts pass; the newly-asserted MODEL leg passes
with margin (`spectral_grid` model lum error 3.290e-3 and size 1.286e-4 against 0.08;
`spectral_grid_free` 6.380e-3 and 1.824e-3). I also ran the **opt-in CUDA leg**
(`OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1`) on the RTX 4500 Ada: `spectral_cuda_grid.limit_passed =
true`, `proton_limit_max_abs_error = 1.626e-19` against `limit_atol = 5e-13`. Measured Lesson 1's
"GPU leg never run on a GPU machine" does not apply here at HEAD.

**`slice_interpolation_emittance_growth.jl`** — `boundary_cross_fraction = 0.470201`, reproducing
the recorded 0.470 exactly.

**`symplecticity_validation.jl`** — the docstring's stated behaviour reproduces: linear maps at
~1.5e-13 ("~1e-13"), nonlinear beam-beam at 7.91e-8 ("~8e-8 at the default step").

**`strong_strong_spectral_comparison.jl`** — runs clean, five TSVs written; nothing recorded to
compare against (README documents no reference numbers).

## Does NOT reproduce — the region's largest finding

**`slice_interpolation_emittance_growth_summary.jl`** vs
`docs/theory/slice_longitudinal_interpolation.md` §11. Running the documented aggregate command
against the repository's own `result/` today:

| arm | recorded electron ε_y′ / t | measured today |
|---|---|---|
| `:linear` 15 CIC slice_pair (baseline) | 8.201e-5 / — | **5.6442e-5** / — (n=22, not 4) |
| `:quadratic` 15 CIC slice_pair | 8.185e-5 / **−0.09** | 8.1853e-5 / **+4.23** |
| `:linear` **30** CIC slice_pair | 8.464e-5 / **+1.56** | 8.5022e-5 / **+4.77** |
| `:linear` 15 **TSC** slice_pair | 7.160e-5 / **−6.93** | 7.1604e-5 / **+2.54** (sign flip) |
| `:quadratic` 15 **TSC** slice_pair | 7.057e-5 / **−5.22** | 7.0572e-5 / **+2.29** (sign flip) |
| `:linear` 15 CIC **source_slice** | 7.591e-5 / **−3.44**, proton −2.79 | 7.5913e-5 / **+3.23**, proton −0.60 (sign flip) |

Every arm *mean* reproduces to 4 s.f.; every *t*-value fails, and three flip sign. Mechanism and
repro in **LEAD U24-1**.

## Runtime cap — the honest partial

`slice_interpolation_emittance_growth.jl` at its defaults **exceeds a 420 s cap**, confirmed by
measurement rather than inherited: I ran one arm at `OCTOPUS_EMIT_TURNS=60` (scratch copy, scratch
tag `auditprobe_s1`, `--threads=8`) → **59.4 s of tracking for 60 turns (0.99 s/turn)**, 71.9 s
wall including package load. The default 600 turns therefore projects to **≈ 606 s wall for ONE
arm/seed**, and the study needs 6 arms × 4 seeds. The repository's own meta files corroborate:
`elapsed_s` ranges 507.2 s (600 turns, 30k) to 2004.8 s (800 turns, 30 slices). **Reported as an
honest partial run with the measured rate, not omitted.** The script itself is confirmed to execute
correctly at HEAD (exit 0, both output files written, `boundary_cross_fraction` reproducing).

All other eight scripts of the region completed under the cap and are reported above.

**Timing caveat:** the box was quiet of other audit agents, but I ran some scripts concurrently
with one another. Wall times measured under concurrency: `high_energy` 44.6 s and its CUDA variant
84.0 s, `lattice_cells` 158.6 s, `gaussian_slicing_convergence` 40.1 s (three-way overlap);
`strong_strong_spectral_comparison` 134.4 s and the emittance arm 71.9 s (two-way overlap). Treat
these as upper bounds. `symplecticity_validation` (31.7 s), `slice_longitudinal_zscan` (36.6 s) and
the PTC regeneration (~11 s) ran essentially alone.

---

# LEADS

### LEAD U24-1 [high, confidence high] validation/slice_interpolation_emittance_growth_summary.jl:60-88
Claim: the arm-grouping key omits `npart` and `turns`, so the baseline arm silently pools 22 runs
taken at three different particle counts, two different turn counts and at least two solver
families that are not this script's documented arms — and every `t_like` in the table, including
the ones the theory note's §11 conclusions rest on, is computed against that mixture; three of them
now report the opposite sign from the record.
Mechanism: `arm_of(d) = (String(d["scheme"]), Int(d["nslices"]), String(d["deposit"]),
String(d["gridmode"]))` (line 60) is the entire identity of an arm. The meta file records `npart`,
`grid` and `turns` as columns, and `slice_interpolation_emittance_growth.jl` exposes all three as
documented overrides (`OCTOPUS_EMIT_NPART`, `OCTOPUS_EMIT_GRID`, `OCTOPUS_EMIT_TURNS`), but none of
them enters the key. `baseline` (line 76) is then that pooled group, and `tlike` (83-88) divides
the mean separation by a pooled standard error whose baseline term is inflated by between-group
variation instead of seed variation. Vertical growth scales with shot noise, i.e. roughly as
1/`npart`: the pooled baseline contains 8.4e-5 (30k), 4.5e-5 (60k) and 2.2e-5 (120k) runs — a
factor of four — so its sd is 2.785e-5 against the clean 4-seed sd of 2.823e-6, a factor of ten,
and its mean is dragged from 8.201e-5 to 5.644e-5. Two of the pooled tags (`gaussctrl_*`,
`hybrid_*`) cannot have been produced by the committed script at all — it builds a
`PICPoissonSolver` unconditionally at line 136 — and the meta row carries no solver-family field,
so rows written by a modified script are indistinguishable from baseline rows. A third
(`repro_check_s1`) is a bit-identical duplicate of `linear_n15_cic_s1` and is counted twice.
Nothing warns; the printed table looks clean and its `n` column (22 against 4 everywhere else) is
the only visible symptom.
Repro:
```bash
# 1. what the documented command reports today
julia --project=. validation/slice_interpolation_emittance_growth_summary.jl
#    -> baseline row shows n=22, ele_ey_growth 5.6442e-05
#    -> quadratic/15/CIC/slice_pair shows t_ele = +4.23
#    -> linear/15/TSC t_ele = +2.54 ; quadratic/15/TSC +2.29 ; source_slice +3.23
# 2. what docs/theory/slice_longitudinal_interpolation.md section 11 records
#    -> baseline 8.201e-5 ; quadratic t = -0.09 ; TSC t = -6.93 ; source_slice t = -3.44
# 3. like-for-like (baseline restricted to the four linear_n15_cic_s* runs, npart=30000, turns=800)
#    -> clean baseline n=4 mean 8.2007e-5 sd 2.8231e-6 ; t_like(quadratic) = -0.09  (matches the record)
```
The decision rule the script prints ("|t_like| < 2 means NOT resolved") therefore flips from "not
resolved" to "resolved" for four of the five non-baseline arms purely from directory contents.

### LEAD U24-2 [medium, confidence high] validation/lattice_cells.jl:239-243
Claim: the gate added for U21-3 covers 2 of the 4 error metrics the file's own header declares;
the Courant-Snyder invariant drift — the metric explicitly introduced to catch what the one-turn
symplecticity residual cannot — and the final cells' linear stability remain print-only, and the
drift can be `NaN` without anyone noticing.
Mechanism: the loop checks `r[3]` (symplecticity residual) and `b[2]`/`b[3]` (the two backend
contract statuses). `r[4]`, `r[5]` (`|tr_x|`, `|tr_y|`) and `r[6]` (`invariant_drift`) are pushed
at line 205, printed at 204, written to the TSV at 231, and never compared. `|tr|<2` is enforced
only inside `find_stable` (line 138), which runs on the *bare* cells; the three `+sext` variants in
`CELLS` (185, 187, 189) are never re-tested for stability even though adding a thick sextupole
changes the one-turn map. `invariant_drift` returns `NaN` on three separate paths (unstable Twiss
155, tracking throw 167, non-finite coordinates 168); `NaN` propagates to the printed column, the
TSV and nothing else. A cell that is symplectic once per turn but unstable over 2000 turns — the
stated purpose of the metric — exits 0.
Repro: run `validation/lattice_cells.jl` and confirm the gate loop mentions only `r[3]`, `b[2]`,
`b[3]`. Measured drifts today: FODO 3.56e-9, FODO+sext 8.29e-4, DBA 9.39e-5, DBA+sext 7.24e-4, TBA
7.35e-5, TBA+sext 1.40e-3 — no threshold anywhere would reject any value, including 1.0.

### LEAD U24-3 [medium, confidence high] validation/symplecticity_validation.jl:13-14 (and validation/README.md:385-387)
Claim: both the script header and the README claim coverage of every registered `Symplectic6DMap`
runtime map; the measured coverage is 7 of 22 registered kinds, with the entire lattice-magnet
family (quadrupole, sextupole, octupole, multipole, sbend, drift, all thin variants, all correctors)
absent. U21-4 reported this; it was not repaired when the case list was switched to derive.
Mechanism: switching `symplecticity_cases()` to `Octopus._symplecticity_contract_cases()` fixed the
*mirror* problem (the two sides can no longer disagree) but did not widen the underlying list,
which still enumerates 12 hand-built cases. The registry has grown past it. The one automatic
guard, the declaration↔case tripwire, only constrains kinds whose *metadata declares*
`SymplecticityContract`, and exactly one kind does (`:solenoid`), so growth of the
`Symplectic6DMap` family produces no signal at all.
Repro:
```julia
include("src/Octopus.jl"); using .Octopus; O = Octopus
cases = O._symplecticity_contract_cases()                    # 12
s6 = [O._element_meta_or_nothing(T).kind for T in O.registered_element_specs()
      if O._element_meta_or_nothing(T) !== nothing &&
         any(m -> m === O.Symplectic6DMap, O.supported_tracking_methods(T))]   # 22 kinds
# kinds with a case: 7 -> :chromaticity_kick :crab_dispersion :linear6d :momentum_dispersion
#                         :solenoid :thin_crab_cavity :xy_coupling
# kinds without:    15 -> :drift :hkicker :kicker :marker :multipole :octupole :quadrupole
#                         :sbend :sextupole :thin_dipole :thin_multipole :thin_quadrupole
#                         :thin_rf_cavity :thin_sextupole :vkicker
```

### LEAD U24-4 [medium, confidence high] validation/symplecticity_validation.jl:11
Claim: the header advertises `OCTOPUS_SYMPLECTICITY_TOL=5e-7`, ten times the code's actual default
of `5e-8`; a reader following the header would set the very value the code's own comment (lines
29-34) documents as the bug that made four cases unbindable. Reported as U21-4; still present.
Mechanism: line 11 is a literal in a comment block; line 35 is the code. The comment immediately
above the code even explains why 5e-7 is wrong ("at the former 5e-7 the four 5e-8 linear-map cases
were judged ten times looser than they declare"), so the header now contradicts the paragraph
three lines below it.
Repro: `grep -n "5e-7\|5e-8" validation/symplecticity_validation.jl` → line 11 `5e-7`, line 35
`"5e-8"`. Cross-check `SymplecticityContract`'s `default_tolerance::Float64 = 5.0e-8`.

### LEAD U24-5 [medium, confidence high] validation/symplecticity_validation.jl:116-124
Claim: the script derives the case list from the contract but does **not** run the contract's
declaration↔coverage tripwire, so the Measured-Lesson-4 repair is half applied: running the script
alone cannot detect a registered kind that declares `SymplecticityContract` and has no case.
Mechanism: `run_symplecticity_validation` (116-124) maps residuals over `symplecticity_cases()` and
returns; the tripwire lives in `validate(::SymplecticityContract)`
(`src/contracts/Contracts.jl:1276-1298`), which the script never calls. The file's own comment
(lines 82-83) says "the list now IS the contract's … whose validate carries the declaration↔case
tripwire" — true of the contract, not of the script. The script is the documented way a developer
checks symplecticity after a change (`validation/README.md:385`), and the check it runs is the one
without the tripwire.
Repro: positive control `validate(SymplecticityContract())` → `metrics[:kinds_declaring_without_case]
= 0`. Negative control: filter the two `Solenoid` cases out of the list and re-run the same loop →
`uncovered = [:solenoid]`, tripwire fires. Then run
`julia --project=. validation/symplecticity_validation.jl` and observe that its output contains no
coverage line at all. Note also that as shipped the tripwire constrains exactly one registered kind
(`:solenoid`), which the list covers twice — near-tautological, per U24-3.

### LEAD U24-6 [medium, confidence high] test/runtests.jl:7106 (SEAM — outside my region, reported and stopped)
Claim: the one place that runs `symplecticity_validation.jl` automatically passes
`default_tolerance=5.0e-6`, one hundred times the script's own floor and the contract's, so every
per-case declared tolerance is unbound in the suite — the exact defect the S3 fix was made to
remove, reintroduced at the call site.
Mechanism: the script applies `tolerance = max(case.tolerance, default_tolerance)` (line 119). With
`default_tolerance = 5.0e-6` every case, including the four 5.0e-8 linear-map cases measured at
~1.5e-13, is judged at 5.0e-6 — a 3.3e7× slack. `validate(SymplecticityContract())` is separately
tested at `test/runtests.jl:3739` and `:8174` with the tight 5e-8 default, so the tight check does
run; but the script leg is decorative, and a regression up to 5e-6 in any case would pass it.
Seam, not mine to fix: it is a `test/` caller of a `validation/` entry point.
Repro: `sed -n '7103,7112p' test/runtests.jl` → `run_symplecticity_validation(; step=3.0e-7,
default_tolerance=5.0e-6)`. Compare `validation/symplecticity_validation.jl:35` (`5e-8`) and
`Contracts.jl:1142` (`default_tolerance::Float64 = 5.0e-8`).

### LEAD U24-7 [low, confidence high] validation/symplecticity_validation.jl:89-93
Claim: the Lorentz leg is still hand-copied knowledge — reference point, crossing angle and both
tolerances are literals duplicated from `SymplecticityContract`, exactly the pattern the case-list
repair removed one function above.
Mechanism: `run_lorentz_quasisymplectic_validation(; angle=0.01, inverse_tolerance=1.0e-10,
determinant_tolerance=2.0e-7)` and `q0 = [4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4]`
duplicate `SymplecticityContract.lorentz_angle = 0.01`, the contract's
`inverse_residual <= 1.0e-10 && determinant_error <= 2.0e-7`, and the contract's own `q0`. They
agree today; nothing makes them agree tomorrow, and nothing would report the divergence.
Repro: diff `validation/symplecticity_validation.jl:89-93` against
`src/contracts/Contracts.jl` lines for `lorentz_angle`, `q0` and `lorentz_passed`.

### LEAD U24-8 [low, confidence high] validation/slice_longitudinal_zscan.jl:98
Claim: `source_slices = (4, 6)` is hardcoded while `OCTOPUS_ZSCAN_NSLICES` is a documented
override, so any documented use with fewer than 6 slices crashes with a `BoundsError` instead of
adapting or refusing.
Mechanism: line 97 reads `nslices` from the environment (default 7); line 98 fixes the source-slice
indices to 4 and 6 with a comment describing them as "centre and off-centre" of a 7-slice bunch.
`slices1.indices[si]` at line 187 indexes an `nslices`-long vector. With
`OCTOPUS_ZSCAN_NSLICES=3` or `5` the loop indexes past the end. The intent (centre / off-centre) is
expressible from `nslices`; the literal is not.
Repro: `OCTOPUS_ZSCAN_NSLICES=5 julia --threads=4 --project=. validation/slice_longitudinal_zscan.jl`
→ measured: `ERROR: LoadError: BoundsError: attempt to access 5-element Vector{Vector{Int64}} at
index [6]` from `slice_longitudinal_zscan.jl:187`, rather than a message naming the constraint.

### LEAD U24-9 [low, confidence high] validation/slice_longitudinal_zscan.jl:34-38 vs 388-543
Claim: the header describes one secondary pass (per-slice grid); the code runs and emits four
distinct `grid_mode` families, one of which (`node_source_evolution`) measures something the header
never mentions.
Mechanism: `_jumps.tsv` carries `common_grid`, `per_slice_grid`, `source_slice_grid`, `node_grid`
and `node_source_evolution` rows. The `node_grid` prototype (420-504), the source-evolution residual
(506-534) and the "node grid vs per-slice-pair" ratio table (536-542, printed at 613-616 and written
to no file) are all undocumented at the top of the file. A reader of `_jumps.tsv` cannot learn from
the header what three of its five `grid_mode` values mean.
Repro: `cut -f4 result/slice_longitudinal_zscan_jumps.tsv | sort -u` → five values; the header's
"Reference model" section names one non-default pass.

### LEAD U24-10 [low, confidence high] validation/generate_ptc_reference.jl:336-355
Claim: the committed reference table is truncated before the first MAD-X job runs, so a failure
part-way through regeneration leaves a partial reference in the working tree.
Mechanism: `open(path, "w") do io … for case in CASES; rows = run_case(case) …` opens with `"w"`
(truncate) and only then enters the loop that shells out to MAD-X 55 times. Any error inside
`run_case` — a MAD-X non-zero exit (312), a short particle count (328), a missing output file —
propagates out of the `do` block, which closes the file with however many cases were written.
Mitigation exists downstream and is real: the contract's declared-spec tripwire
(`Contracts.jl:1871-1881`) fails loudly when a spec has no rows, so a truncated table cannot pass
as green; and `git checkout` recovers. But the failure mode is "destroy the artifact first, detect
later"; a tempfile-plus-rename would make it "detect, artifact intact".
Repro: read lines 336-355; note there is no `tempname()`/`mv` and no `try`. Confirm the ordering by
observing that `println("  $(case.name): ok")` is inside the write loop.

### LEAD U24-11 [low, confidence high] validation/high_energy_weakstrong_limit.jl:380-381
Claim: the two Gaussian-arm thresholds are the only tolerances in the file that are neither
documented in the header's control list nor env-tunable, and they are hand copies of
`HighEnergyWeakStrongLimitContract`'s defaults.
Mechanism: every other tolerance in the file is a named `const` fed from an `OCTOPUS_HIGH_ENERGY_*`
variable listed at lines 8-23. `gaussian_passed = gaussian_proton_error <= 2.0e-14 &&
gaussian_lum_rel <= 2.0e-12` embeds two bare literals in the middle of a `NamedTuple`. The same two
numbers are the contract's `gaussian_atol=2.0e-14` and `gaussian_luminosity_rtol=2.0e-12`
kwarg defaults, and `test/runtests.jl:7116` calls this script's entry point overriding every
*other* tolerance but not these — so the two arms of the same comparison are tuned by different
mechanisms.
Repro: `grep -n "2.0e-14\|2.0e-12" validation/high_energy_weakstrong_limit.jl` → lines 380-381
only; compare `HighEnergyWeakStrongLimitContract`'s docstring signature in
`src/contracts/Contracts.jl`.

### LEAD U24-12 [low, confidence high] validation/strong_strong_spectral_comparison.jl:1-27, 156-163
Claim: the header has no `Outputs` section although the script writes five TSVs, and it carries a
stale in-code warning that this audit has now falsified.
Mechanism: `AGENTS.md` "Updating Validations" requires the top-of-file comment to state outputs;
this header states reference model, metrics, run command and seven controls, but names only the
`OCTOPUS_SPECTRAL_COMPARE_OUTPUT` *prefix*, leaving the five suffixes (`_timing`, `_luminosity`,
`_moments`, `_coordinate_differences`, `_field_microprofile`) discoverable only from the code. The
comment at 159-160, "This script was written before that and has not run since", is now false: I
ran it at HEAD to completion.
Repro: `OCTOPUS_SPECTRAL_COMPARE_OUTPUT=/tmp/x/ssc julia --threads=4 --project=. \
validation/strong_strong_spectral_comparison.jl` → exit 0 in 134 s, five files under `/tmp/x/`.

### LEAD U24-13 [low, confidence high] validation/slice_interpolation_emittance_growth.jl:26-35
Claim: the arms table documents six arms A–F and omits the `:node` interaction-grid arm, which the
same header's override list documents and which the repository's `result/` contains 14 runs of.
Mechanism: the table's arm F is `interaction_grid=:source_slice`; `:node` appears only in the
override list at line 73-74. `interaction_grid in (:slice_pair, :source_slice, :node)` is the
solver's own validation (`src/tasks/strongstrong/interface.jl:1272`), and
`docs/theory/slice_longitudinal_interpolation.md` §10.6 discusses `:node` at length, so the arm is
real and studied — just not in the table a reader uses to pick an arm.
Repro: `grep -c node result/emittance_growth_*node*.meta.tsv | wc -l` → 14 files; compare the arms
table at lines 26-35.

---

# Clean list — audited sound, with the evidence that makes it checkable

1. **The PTC provenance chain, end to end.** 55 generator cases = 55 table case names = 55 contract
   spec keys, with the three *name sets diffed to empty*, not merely counted. 275 rows = 55 × 5,
   every row 14 fields, zero duplicate `(case, particle)` pairs, zero NaN/Inf, initial-coordinate
   tuples equal to `PARTICLES`. Contract passes at worst deviation 4.9953e-13 against 1e-11.
   Version and flag set recorded inside the artifact and parsed back by `validate`. MAD-X 5.03.06
   present and matching; **regeneration byte-identical**.
2. **`natkey` table selection.** Verified to pick 5.10 over 5.9 where lexicographic picks 5.9;
   verified to resolve to the single committed table today. U21-7 is closed.
3. **U21-6 is closed.** The `Case.octopus` dict is gone from the struct and every constructor; the
   generator carries no spec knowledge at all, and `_ptc_reference_specs()` is the single source.
   Spot-checked the previously-drifted cases: `multipole_m2_n4` now maps to
   `MultipoleSpec(L=0.3, kn=(0.0,1.2,8.0), nst=4, integrator_order=2)` against the generator's
   `sbend, l=0.3, angle=0, k1=1.2, k2=8.0`; `quadrupole_fringe` to
   `QuadrupoleSpec(L=0.4, k1=1.7, nst=4, fringe=:multipole, highest_fringe=2)`; the `:rbend` cases
   to real `RBendSpec`. `h = 0.198/1.1 = 0.18` exactly, matching the contract's literal.
4. **U21-2 is closed and the new assertion has margin.** `spectral_model_passed` now errors;
   measured margins 3.29e-3 and 1.29e-4 (grid), 6.38e-3 and 1.82e-3 (grid-free), against 0.08.
5. **The symplecticity case list is derived, 12 = 12**, and the derivation is the right shape: the
   *evaluator* (finite-difference Jacobian, symplectic form) stays local to the script, so a defect
   in the contract's own differentiation cannot hide itself. Verified by running both and comparing
   the twelve names and their pass/fail.
6. **The symplecticity tripwire mechanism works** (positive control 0 uncovered; negative control
   with the Solenoid cases removed fires with `[:solenoid]`) — its *scope* is the problem (U24-3,
   U24-5), not its correctness.
7. **The CUDA legs of this region actually run on this machine and pass.** `lattice_cells` CPU/CUDA
   contract passed on all six cells (max|Δ| ≤ 1.332e-15); `high_energy_weakstrong_limit`'s opt-in
   spectral CUDA leg passed at 1.626e-19 against 5e-13. Measured Lesson 1's "GPU leg never run"
   failure mode is not present here.
8. **All 38 internal `Octopus._*` helper symbols** referenced across the nine scripts still exist
   (`isdefined` check, zero missing), and the z-scan's `_pic_interaction!(solver, fld, pf, kicked,
   psrc, kbb, ws, nothing, nothing)` call matches a real 9-argument method.
9. **Reproducibility of the recorded science, where it exists:** `gaussian_slicing_convergence`
   reproduces every number in its 2026-07-31 history record to the recorded precision, including
   both Richardson orders and both floors, despite drawing its bunch from `Random.Xoshiro` on a
   newer Julia; `slice_longitudinal_zscan` reproduces all six rows of the theory note's §10.1 table
   and all three jump rows, with `_cells.tsv` byte-identical to the prior artifact;
   `lattice_cells.tsv` byte-identical to the prior artifact.
10. **Output discipline.** Every writer in the region targets `result/` via `mkpath` or an
    environment-overridable prefix; the z-scan gives non-`CIC` deposition its own file stem so runs
    cannot clobber each other; nothing writes outside `result/` or a `mktempdir()`.
11. **`high_energy_weakstrong_limit`'s header is accurate**: all fourteen documented environment
    defaults were checked one by one against the code and all match.
12. **`generate_ptc_reference.jl`'s physics rationale checks out against the code it describes**:
    `permfringe=true` per element (line 293) and never `ptc_setswitch`; `option, rbarc=false` (291)
    so an RBEND's `l` is the arc; `model=1, exact=true, time=false` (301-302); PTC `T` negated on
    write (351); thin elements tracked as element + `THIN_SEQ_L=0.2` drift (294-295), matching the
    contract's `[ThinMultipoleSpec(...), DriftSpec(L=0.2)]` pair.
13. **RNG hygiene** across the region: every script that draws particles seeds deterministically
    (`set_global_rng!(seed=…, method=:philox)` in five of them; `Random.Xoshiro(config.seed)` in
    `gaussian_slicing_convergence`, whose Julia-version dependence is now declared in the header
    and was measured to be a non-issue at 1.12.4).

# Unchecked, with the reason

- **`slice_interpolation_emittance_growth.jl` at its documented defaults (600 turns).** Measured
  rate 0.99 s/turn → ≈606 s wall for one arm/seed, above the 420 s cap. Ran 60 turns instead;
  script confirmed working, `boundary_cross_fraction` confirmed reproducing. The full six-arm
  four-seed study (≈2.4 h of wall time at minimum, and the repository's own `elapsed_s` records
  suggest 4–8 h) was not attempted.
- **Whether the theory note's §11 conclusions are *scientifically* wrong or merely
  *irreproducible-as-documented*.** LEAD U24-1 shows the documented command no longer yields the
  recorded numbers, and shows that a like-for-like recomputation restores the `:quadratic` value
  exactly (−0.09). I did not recompute the other four arms like-for-like, because doing so requires
  deciding which of the 22 pooled baseline runs are legitimate — that is the auditor's judgement
  call, not a reading unit's.
- **The `gaussctrl_*` and `hybrid_*` result rows' provenance.** They cannot have come from the
  committed script (it hardcodes `PICPoissonSolver`), but tracing which script version wrote them
  would mean reading history outside my region.
- **CUDA path of `strong_strong_spectral_comparison`** (`OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda`).
  Not run; the CPU run already exercised every code path the script's own thresholds touch (there
  are none), and the GPU-vs-CPU question belongs to the dedicated backend-consistency scripts,
  which are another unit's region.
- **`_PTC_DEFAULT_ATOL` being empty.** Noted as already-documented (the docstring says so
  explicitly after U3-9); whether per-case defaults *should* exist is a design question for the
  auditor, and every case currently passes at the uniform 1e-11 with ≥20× margin.
- **Cross-file seams noted and stopped at:** `test/runtests.jl:7106` (U24-6);
  `SymplecticityContract`'s docstring at `Contracts.jl:1118-1127` enumerating 6 + 2 cases when the
  list holds 12 (it omits `Solenoid`, `SolenoidCurvedMultipole` and the two extra virtual-drift
  variants); the `curved solenoid: the implicit-midpoint stage is not converged at nst = 8` warning
  that `_symplecticity_contract_cases()` provokes on every construction of the
  `SolenoidCurvedMultipole` case, which means both the contract and this script emit a
  not-converged warning on every clean run.
