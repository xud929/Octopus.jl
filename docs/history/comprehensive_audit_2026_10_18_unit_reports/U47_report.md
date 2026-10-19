# U47: theory notes B: subtracted PIC, spectral Poisson, free-space kernels, node grid, coherent modes, weak-strong 6D

Reading unit of the comprehensive audit 2026-10-18 (tree `/cfs/ad/dxu/Library/Julia/Octopus` at
commit 24e8683, read-only). Depth: claims-vs-code, with sampled independent derivations and
numeric probes. Every claim below is a LEAD, not a finding.

## Region

All six files read in full (2879 lines):

| file | lines |
|---|---|
| `docs/theory/gaussian_subtracted_pic_solver.md` | 1-834 |
| `docs/theory/spectral_sine_poisson_solver.md` | 1-693 |
| `docs/theory/pic_free_space_kernels.md` | 1-466 |
| `docs/theory/node_interaction_grid.md` | 1-182 |
| `docs/theory/coherent_beam_beam_modes.md` | 1-450 |
| `docs/theory/weak_strong_6d_model.md` | 1-254 |

References compared against (read in targeted ranges, not whole): `src/tasks/strongstrong/gaussian_pic.jl`
(L26-139, 376-386, 522-536, 589-600, 710-830, 836-962, 1250-1272), `gaussian_pic_cuda.jl` (L40-62),
`pic_cpu.jl` (L540-590, 646-704, 734, 888-900, 1143-1144, 1926-1966, 2062, 2101, 2159, 2556-2566,
2575-2600, 2655-2760, 2786-2800), `spectral.jl` (L45-64, 71-108, 158-205, 340-343, 456-460, 632,
706, 797-801, 915, 958-992, 1150-1212, 1329-1351), `spectral_cuda.jl` (L5-6, 24-97, 334-414),
`interface.jl` (L891-1054, 1130-1150, 1310-1313, 1391-1400, 1422-1476, 1576-1635), `pic_cuda.jl`
(L766-767, 2447-2474), `src/elements/strong_beam.jl` (L3-78, 124-145, 785-800, 1206-1228, 1285-1313,
1370-1440), `src/analysis/canonical_separation.jl` (L277-300), `src/contracts/Contracts.jl` (L95-135,
1195-1215, 1455-1475, 2201, 3646), `test/runtests.jl` (testset titles; L29637-29705),
`validation/pic_gaussian_field_validation.jl` (L73-135), `validation/gaussian_pic_field_validation.jl`
(L123-137), `validation/coherent_mode_vlasov_theory.jl` (L50-102, 350-358, 374-376, 453, 482,
574-592), `examples/strong_strong_tracking.jl` (L78-112), `docs/theory/lattice_hamiltonian_and_conventions.md`
(L45-142 and headings), `docs/theory/beam_beam_longitudinal_kick.md` (headings),
`docs/theory/slice_longitudinal_interpolation.md` (headings).

## Provenance

READ line by line: the six region files in full (ranges above). The reference ranges above were
read as named; everything else in `src/` was reached by `grep` only.

Hand derivations (pen-and-paper, no execution): note 1 moment integrals m_0..m_2, CIC and TSC node
values, the TSC sigma->0 limit (3/4, 1/8), the conditional expansion, g' and g'' forms, the r^2/(1-r^2)
expansion parameter; note 2 eigen/orthogonality/mode-division chain and the DST-I inverse factor;
note 3 stencil error terms by Taylor expansion, the cell-integral antiderivative
(d_x d_y I = ln r^2), the VGF transform and its k->0 limit, kappa^2, the Spitzer constants;
note 5 the averaged kernel G(u), its transform, u(0), the harmonic kernel -sqrt(JJ')/2, the
discrete-map drift; note 6 drift transport, conditional Gaussian, dispersion slope and
within-slice covariance, finite-bin term.

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U47/`):

- `be_component_order.jl` -> `.log` not kept separately; output in the lead block (U47-1):
  code `gaussian_beambeam_kick(2,1,30,20) = (0.046128, 0.030895)`, far field `(0.046154, 0.030769)`,
  the note's formula read as K_x + i K_y gives `(0.030895, 0.046128)`: components swapped.
- `numeric_checks.jl` -> `numeric_checks.log`: erfc table 2.6998e-3 / 6.334e-5 / 5.733e-7 / 1.973e-9;
  eps^(1/4) = 1.2207e-4 (Float64), 1.858e-2 (Float32); lattice table G(1,0) = -1.5707,
  G(4,0)-G(1,0) = -1.4248 (target -ln 4 = -1.3863); Y_eff = 1.209386 (xi=0.005), 1.243439 (xi=0.02);
  G(u) closed form vs quadrature rel. diff 1.8e-16; u(0) = 0.8284 (r=1), 0.9919 (r=0.02), 0.7246
  (r=106/9.5); EIC xi_e = (0.08821, 0.10038), xi_p = (0.009368, 0.009407); note-6 convention probe
  h = 0.99, code/raw-eta ratio = 1.020304.
- `node_option_composition.jl` -> `.log`: `PICPoissonSolver(interaction_grid=:node, grid_extent=:sigma)`
  throws ArgumentError at construction; `(interaction_grid=:node, slice_interpolation=:quadratic)` is
  accepted at construction.
- `validation/coherent_mode_vlasov_theory.jl` run to completion (`timeout 1500`, exit 0) -> `vlasov_selfcheck.log`
  (106 lines, "all self-checks PASS"): Self-check 4 rigid-bunch limit = 1.0 at nine of eleven r values,
  1.0003 (r=0.3) and 1.0001 (r=0.85); u(0) = 0.992/0.9805/0.9638/0.9354/0.9129/0.8786/0.8544/0.8401/
  0.8284/0.7439/0.7246 against exact 0.9919/0.9807/0.9637/0.9354/0.9128/0.8787/0.8543/0.8401/0.8284/
  0.7434/0.7246; Self-check 5 Lambda = 1.999975.

## Leads

### LEAD U47-1 [Moderate, confidence high] docs/theory/gaussian_subtracted_pic_solver.md:130
Claim: Section 3 writes the Bassetti-Erskine field as `K_x + i K_y = (2 sqrt(pi)/sqrt(2(sx^2-sy^2))) [w(z1) - e^{...} w(z2)]`, but that complex expression is `K_y + i K_x`; the two kick components are swapped in the note's central formula.
Mechanism: for large |z|, w(z) -> i/(sqrt(pi) z), so the right-hand side tends to 2i/(x+iy) = (2y + 2ix)/r^2: real part 2y/r^2 (the y-kick), imaginary part 2x/r^2 (the x-kick). The code agrees with the physics, not the note: `_elliptic_gaussian_kick_principal` (src/elements/strong_beam.jl, `Kx = imag(ret); Ky = real(ret)`), and the docstring's round-beam limit `Kx = 2x(1-exp)/r^2`. A reader implementing or validating from the note's Section 3 would exchange K_x and K_y (the standard BE form is E_y + i E_x).
Repro: `cd result/comprehensive_audit_2026_10_18/probes/U47 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus be_component_order.jl` -> prints `swap needed ... : true`; code `Kx=0.046128, Ky=0.030895` versus the note's reading `Kx=0.030895, Ky=0.046128` at (sigx,sigy,x,y)=(2,1,30,20).

### LEAD U47-2 [Moderate, confidence high] docs/theory/pic_free_space_kernels.md:325
Claim: the 2026-08-03 correction block says the `:lattice` kernel was "re-measured with that documented harness" (`validation/pic_gaussian_field_validation.jl`) and tabulates `:lattice` before/after columns, but the committed harness cannot select that kernel, and no committed script sweeps `green_type=:lattice`, `:standard`, or `field_derivative=:fourth`; the tables at L78-82 (`:fourth` gain), L126-131 (kernel sensitivity), L173-178 (VGF) and L331-337 (lattice after the box fix) therefore have no runnable harness in the tree.
Mechanism: `validation/pic_gaussian_field_validation.jl` constructs `PICPoissonSolver(; grid=..., deposit_method=:TSC, green_type=:integrated)` with the kernel hard-coded and exposes ENV switches only for source/field axes, grid, extent, random cases, seed, sigma range and case data; `validation/gaussian_pic_field_validation.jl` also hard-codes `green_type=:integrated` and builds its solver without `field_derivative`. The section itself already records that the older table (L302-309) "had no harness"; the re-measurement that was meant to cure that is in the same position. Some of the numbers are preserved as text in `docs/history/poisson_solver_review_2026_07_24.md`, which records but cannot reproduce them.
Repro: `grep -n "green_type\|field_derivative\|ENV" validation/pic_gaussian_field_validation.jl` -> only `green_type=:integrated` and eight unrelated ENV knobs; `grep -rn ":fourth\|green_type *= *:standard\|:lattice\b" validation/ profiling/ | grep -v "^\S*:\s*#"` -> one docstring mention in `slice_interpolation_emittance_growth.jl`, no sweep.

### LEAD U47-3 [Moderate, confidence high] docs/theory/coherent_beam_beam_modes.md:41
Claim: the note states "The committed `paper/data/*.tsv` are post-fix and match current code" and calls `yokoya_vs_aspect_measured.tsv` (L21) and `result/yokoya_vs_xi_theory.tsv` (L325) "committed", but no `paper/` directory exists anywhere in the tree and `result/` is git-ignored (as the note itself says at L34), so every table in Sections 3 and 4 rests on data files that are not in the repository.
Mechanism: the numbers quoted (1.321/1.308/1.290/.../1.162; 1.25/1.27/1.24/1.20/1.19; the EIC band edges and modes 0.23795, 0.22432; 1.2094/1.2434) are read from TSVs the generating scripts write to `result/`; the only in-tree carriers are prose copies in `validation/README.md` and the 2026-08-05 audit unit reports under `docs/history/`. This violates the "numbers behind a claim are committed, never only in git-ignored `result/`" invariant and leaves `paper/data/` as a dangling reference.
Repro: `ls /cfs/ad/dxu/Library/Julia/Octopus/paper` -> "No such file or directory"; `cd /cfs/ad/dxu/Library/Julia/Octopus && find . -path ./result -prune -o \( -name "yokoya*" -o -name "eic_coherent_modes*" \) -print` -> no output.

### LEAD U47-4 [Minor, confidence high] docs/theory/pic_free_space_kernels.md:202
Claim: the displayed infinite-lattice Green function `G(r) = -(1/M^2) sum_{k!=0} (cos(k.r)-1)/kappa^2` carries a leading minus that makes it increase like +ln r, contradicting the normalization two paragraphs later (`G = (2 pi/(h_x h_y)) F^{-1}[kappa^{-2}]`, L231), the stated asymptote `G_PIC -> -(ln r + C)` (L246), and the code.
Mechanism: since cos(k.r) - 1 <= 0, the sum without a sign is negative and decreasing, which is the -ln r behaviour; the code builds exactly that: `_pic_lattice_green_table` forms `ghat = 1/kap`, `g = real(ifft(ghat))`, `tab = 2 pi rho (g - g0)` with no leading minus. The text around the formula is right; the formula is off by a sign.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U47/numeric_checks.jl` section (c): code table G(4,0)-G(1,0) = -1.4248 (target -ln 4 = -1.3863; the difference is the near-origin lattice correction); the L202 sign would give +1.4248.

### LEAD U47-5 [Minor, confidence high] docs/theory/gaussian_subtracted_pic_solver.md:733
Claim: the "median qualifier" paragraph cites `max_gain` values 0.9988 / 0.9982 "at 25:1 on grids 96 and 256 in `paper/data/`", a directory that does not exist in the tree.
Mechanism: same missing `paper/` as U47-3; these two numbers are orphan measurements with no committed carrier (the fresh-run 0.9957 is reproducible through `validation/gaussian_pic_field_validation.jl`, the `paper/data/` pair is not).
Repro: `ls /cfs/ad/dxu/Library/Julia/Octopus/paper /cfs/ad/dxu/Library/Julia/Octopus/paper/data` -> both "No such file or directory"; `grep -rn "0\.9988\|0\.9982" /cfs/ad/dxu/Library/Julia/Octopus/validation /cfs/ad/dxu/Library/Julia/Octopus/docs/history` -> no data file.

### LEAD U47-6 [Minor, confidence high] docs/theory/coherent_beam_beam_modes.md:291
Claim: "the rigid-bunch diagnostic in Section 2 still runs 1.21-1.41 rather than 1" is a pre-fix statement that contradicts Section 1 (rigid Y = 1 exactly, verified at five aspect ratios) and the shipped script, whose Self-check 4 requires the rigid-bunch limit to equal 1 within 2e-2.
Mechanism: in `validation/coherent_mode_vlasov_theory.jl` the comment at L354-355 identifies 1.213 (round) to 1.412 (extreme flat) as what the rigid limit returned under the *circular* averaged-curvature normalization that check 4 was written to remove; the check now prints "The rigid-bunch limit is analytically 1" and computes `rigid = 2 * normalized_equilibrium(kk, sqrt(2)) / n0phys`. Section 2 of the note has no diagnostic reporting 1.21-1.41. Presenting the artifact range as "what survives" (L289-291) re-introduces the inverted framing that the U22-10 correction in Section 1 removed.
Repro: `grep -n "1.213\|1.412\|analytically 1" validation/coherent_mode_vlasov_theory.jl` -> L354-355 (pre-fix values, in a comment) and L576 (the live assertion); `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 validation/coherent_mode_vlasov_theory.jl 2>&1 | grep -A12 "Self-check 4"` -> MEASURED (probes/U47/vlasov_selfcheck.log, exit 0, all self-checks PASS): rigid = 1.0 at r = 0.02, 0.05, 0.1, 0.2, 0.5, 0.7, 1.0, 5.0, 11.111 and 1.0003 / 1.0001 at r = 0.3 / 0.85 -- nowhere near 1.21-1.41; u(0) matches (1+r)/(1+sqrt2 r) to four digits at every r.

### LEAD U47-7 [Minor, confidence high] docs/theory/node_interaction_grid.md:165
Claim: Section 6 names `grid_extent = :sigma` (re-slicing jitter) and `slice_interpolation = :quadratic` (longitudinal sawtooth) as the remedies for what node indexing leaves, without saying that neither composes with `interaction_grid = :node`: the code refuses both.
Mechanism: `_validate_pic_solver` (src/tasks/strongstrong/pic_cpu.jl) throws for `interaction_grid != :slice_pair` with `grid_extent != :extrema` ("that mode ... applies no extent estimator") and for `:node` with `slice_interpolation != :linear` ("the node-plane path applies its own interpolation"); the latter is explicitly "future work for the node_interaction_grid program". A reader following Section 6 would combine options the runtime rejects. Seam, out of region: the `:sigma` refusal fires in the constructor but the `:quadratic` one only when `_validate_pic_solver` runs (`pic_cpu.jl:121`, `gaussian_pic.jl:965`, the CUDA entries), so the construction succeeds and the refusal arrives at first use.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U47/node_option_composition.jl` -> `grid_extent=:sigma` with `:node` -> ArgumentError at construction; `slice_interpolation=:quadratic` with `:node` -> accepted at construction, refused by `_validate_pic_solver` (`grep -n "is not implemented" src/tasks/strongstrong/pic_cpu.jl`).

### LEAD U47-8 [Minor, confidence med] docs/theory/weak_strong_6d_model.md:131
Claim: Section 3 writes `w = w_beta + zeta z + eta p_z` and `Sigma_{w|z} = Sigma_beta + eta eta^T (...)` with eta called "momentum dispersion", but the API's `momentum_dispersion` is the *canonical* eta and the builder uses the physical slope `eta / h`, `h = 1 - zeta' S_4 eta`; the note names neither the convention nor the factor h, so its formula applied to the keyword value differs from the code whenever both dispersions are present.
Mechanism: `gaussian_strong_beam_covariance` (src/elements/strong_beam.jl) converts through `_dispersion_graph` (src/analysis/canonical_separation.jl: "graph = [zeta  eta / h] ... `eta / h` is the slope `d r / d pz`", owner decision 2026-10-18). The note's eta is therefore the slope, not the keyword; the two agree only when zeta' S_4 eta = 0. The discrepancy is (1/h)^2 on the eta eta^T term.
Repro: `numeric_checks.jl` section (h): with `crab_dispersion=(0.02,0,0,0)`, `momentum_dispersion=(0,0.5,0,0)`, `sigma_z=0.01`, `sigma_pz=1e-3`, correlation 0.2: h = 0.99; code conditional `Sigma[px,px] - Sigma_beta[px,px] = 2.4487e-7`; the note's formula with the keyword eta gives 2.4e-7, with eta/h gives 2.4487e-7; ratio code/raw = 1.020304.

### LEAD U47-9 [Minor, confidence med] docs/theory/spectral_sine_poisson_solver.md:432
Claim: Section 15 "Integration and validation plan" is written as future work ("Add the solver as an `AbstractPoissonSolver` variant ... Required checks before it becomes selectable"), although `SpectralPoissonSolver` is implemented, selectable, documented in Sections 13 and 16-18 of the same note, and CPU/CUDA-parity tested; it also names `validation/pic_gaussian_field_validation.jl` for the spectral-vs-Bassetti-Erskine comparison where the committed script is `validation/spectral_poisson_field_validation.jl` (Section 16).
Mechanism: stale planning text left in a theory note after implementation; the "required" contract-style CPU/CUDA check exists as the testset "CUDA spectral solver matches CPU" (test/runtests.jl) rather than as a contract, and no `StrongStrongSpectralBackendConsistencyContract` exists, so a reader cannot tell which of the three listed requirements were met.
Repro: `grep -n "struct SpectralPoissonSolver\|method in (:grid, :grid_free)" src/tasks/strongstrong/spectral.jl`; `grep -n "testset \"CUDA spectral solver matches CPU\"" test/runtests.jl`; `grep -n "Spectral.*Contract" src/contracts/Contracts.jl` -> none; `ls validation/spectral_poisson_field_validation.jl`.

### LEAD U47-10 [Minor, confidence med] docs/theory/spectral_sine_poisson_solver.md:417
Claim: the Section 14 "Numerical" verification (domain a=1.3, b=0.8, k_bb=-2.5, N=63: manufactured band-limited solution to 9.6e-16, Gaussian-source Laplacian residual 7.2e-3, boundary row 1.3%) has no committed harness or testset.
Mechanism: no file under `validation/`, `test/` or `profiling/` constructs that manufactured solution or those constants; the only "manufactured" matches in `test/runtests.jl` are the Twiss symplectic-map tests. The numbers are therefore documentation-only claims (class 14).
Repro: `grep -rn "1\.3.*0\.8.*-2\.5\|a = 1\.3\|band-limited\|manufactured" validation/ test/runtests.jl profiling/ | grep -iv "symplectic\|twiss"` -> no spectral match.

### LEAD U47-11 [Minor, confidence low] docs/theory/gaussian_subtracted_pic_solver.md:759
Claim: the "Measured CPU cost (corrected 2026-07-24)" per-term table (erf profile 2.8e-5 s, grid subtraction 1.1e-5 s, slice moments 3.2e-4 s, add-back 2.68e-2 s, PIC interpolation 2.4e-3 s) is recorded only as text in `docs/history/poisson_solver_review_2026_07_24.md`; no committed driver times those terms.
Mechanism: `profiling/benchmark_collide_cpu.jl` constructs a `GaussianPICPoissonSolver` and times whole interactions, with no erf/add-back/moments breakdown; the "roughly doubles the CPU cost" conclusion rests on a one-off measurement. Low confidence because the history record does carry the numbers and method; the gap is reproducibility, not provenance.
Repro: `grep -n "erf\|add-back\|moments\|faddeeva" profiling/benchmark_collide_cpu.jl` -> none; `grep -rn "2\.68e-2" docs/history/*.md` -> `poisson_solver_review_2026_07_24.md` L228, L455 only.

## Clean

What was compared and found sound (file: claim -> evidence).

gaussian_subtracted_pic_solver.md
- k_bb definition (L55-58) = `interface.jl:934` `kbb1 = beam1.charge*beam2.charge*beam1.r0*beam2.npart*beam1.mc2/beam1.E0`.
- Kick normalization (L46-75, L616-630): `kick_scale = 2*kbb`, `half_ns = 0.5*nsource`, `kbb_eff = kick_scale*half_ns` (gaussian_pic.jl L836-838); uncoupled add-back `kick_scale * half_ns * K_BE` (L926-929); coupled add-back via `_cp_covariance_kick(cmom, kbb_eff, ...)` (L901-903), defined in strong_beam.jl L785/L800.
- Options and defaults (L300-304, L354, L373, L392): `margin_sigma=5.0`, `neutralize=true`, `coupling_tol=Inf` in the constructor, struct, and `SolverOptionMeta` (gaussian_pic.jl L26-27, L94-95, L118-124); non-negativity checks L99-102.
- Box sizing (L352-361): union of drifted particle extrema and +-m sigma about both boundary centroids when `margin > 0`; margin 0 -> plain particle box (gaussian_pic.jl L743-766).
- Rank test (L482-490): `muladd(-rho, rho, one(T)) > sqrt(eps(T))` (L533-534); eps^(1/4) = 1.2207e-4 / 1.8581e-2 measured.
- erfc table (L343-345) reproduced: 2.70e-3, 6.33e-5, 5.73e-7, 1.97e-9.
- Moment formulas m_0, m_1, m_2 (L214-222), CIC node value (L237-238), TSC piecewise weights and node value (L267-281), the sigma->0 limit (3/4 centre, 1/8 neighbours), the conditional expansion (L420-461), g' and g'' for CIC/TSC (L536-548), expansion parameter r^2/(1-r^2) and its values 0.005/0.05/0.28 (L556-563): all re-derived by hand and correct.
- CUDA reference routes throw on finite `coupling_tol` (L595-599) = `_cuda_gpic_require_uncoupled` (gaussian_pic_cuda.jl L47-58).
- Referenced files exist: `validation/gaussian_pic_field_validation.jl`, `validation/gaussian_pic_bigaussian_validation.jl`, `validation/pic_gaussian_field_validation.jl`, `docs/history/todo_ledger_archive.md`; `_gpic_interaction!` derives both subtraction and add-back from `_gpic_source_moments` (gaussian_pic.jl L731).
- Green cache controls (L806, L819-820): `green_cache=:slice_pair` default and `slice_pair_green_min_ratio=0.50`, `slice_pair_green_growth=0.25` exist as solver options with range checks (interface.jl L1137-1138, L1399-1400, L1448-1454, L1632-1635) and are consumed (pic_cuda.jl L766-767, L2447-2474).
- Nits, not leads: L683 "9.2x gain" versus the table's 9.1x (L660); L689 "hybrid at 48x48 matches PIC at 128x128" versus L776 "64x64" (both supported by the table).

spectral_sine_poisson_solver.md
- Eigenfunctions, orthogonality (ab/4), mode division, no zero mode, DST-I self-inverse up to 2(N+1): verified.
- Section 18 constants: `_SPECTRAL_FIELD_SCALE_GRID = -2*pi`, `_SPECTRAL_FIELD_SCALE_FREE = 4*pi` (spectral.jl L63-64); the explicit `/2` in `_spectral_cosderiv` (L340, L343); `REDFT00([0;c;0])[2:N+1]/2` matches L340; p_z kick uses `kick_scale = kbb_slice` (L1338, L1347) where PIC uses `2*kbb`, as L661-662 says.
- Options (L261-267, L288-289): `method in (:grid, :grid_free)` (L175), `grid` meaning per method matches the docstring (L97-99, L198), `min_domain_halfwidth` default 0.0 (L72, L88, L201), `domain_factor` default 16.0 (L87, L199) consistent with "use d ~ 12-16".
- Domain (L283-289, L455-457): `_spectral_box` returns a square half-width `L = max(d*sigma_max, 1.05*extent_max)` floored by `min_domain_halfwidth` (L1157-1210); anisotropy goes into (Nx, Ny), as recommended.
- CUDA realization (L341-352): `DST-I = -imag(FFT(odd_ext))`, `DCT-I = real(FFT(even_ext))` (spectral_cuda.jl L5-6, L400, L414), `:grid` only (L108 "CPU only" for `:grid_free`), atomic deposits (L66-78) consistent with the run-to-run caveat (L362-368).
- Parity harness exists: testset "CUDA spectral solver matches CPU" (test/runtests.jl L29637) with `rtol=1e-12`; its comment records 8.5e-16 (coordinates) and 2.2e-16 (luminosity) on 2026-08-07 versus the note's "~4e-16 / ~9e-16" (L353): same order, different run, not a lead.
- Referenced records exist: `docs/history/strong_strong_spectral_optimization_history.md`, `validation/spectral_poisson_field_validation.jl`; L228's "flat-beam caveat in Section 13" resolves (L396); 225 = 15^2 slice pairs.

pic_free_space_kernels.md
- Stencil error terms (L46-47, L58-59): `-h^2/6 phi'''` and `+h^4/30 phi^(5)` verified by Taylor expansion.
- Cell-integral antiderivative (L117): d_x d_y I = ln r^2 verified; equals `_pic_kernel_integral` (pic_cpu.jl L2561-2565) with the r^2 = 0 guard; `:standard` replaces only the coincident cell by that integral (L2790-2796), as L97-102 says.
- VGF transform (L157-159) and its k->0 limit verified by parts; "kernel used by the code's convention is -2 pi G_L" consistent with Section 1.
- Lattice: kappa^2 (L205), eigenvalue (L216-219), normalization (L231) match `_pic_lattice_green_table` (`kap = (2-2cos tx) + rho^2 (2-2cos ty)`, `scale = 2 pi rho`); Spitzer constants C = 1.6169364 and C - pi/2 = 0.046140 recomputed; a(1,0) = 1/4 corresponds to the measured table value G(1,0) = -1.5707 = -pi/2.
- Caps and multipliers (L289-291, L419): `_PIC_LATTICE_GREEN_MULT = 8`, `_PIC_LATTICE_GREEN_MULT_MAX = 64`, per-axis rho-scaled via `_pic_lattice_box_mult`, `_PIC_LATTICE_GREEN_CACHE_MAX = 384`; 8*11 = 88 > 64 (L345) and M = 2048 = 8*256 (L435) arithmetic holds.
- Options and symbols (L33-35, L40-41, L91-93, L367-377): `min_transverse_extent=(0.0,0.0)`, `field_derivative in (:second,:fourth)` default `:second`, `green_type in (:integrated,:standard,:lattice)` default `:integrated` (interface.jl L1132-1150, L1422-1466); `_pic_field!`, `_pic_expand_grid_by`, `_pic_realign_expanded_grids`, `_pic_solve_field` exist; 1.5-cell padding (`sx0 = sxmin - 1.5*tx`, pic_cpu.jl `_pic_interaction_grids`).

node_interaction_grid.md
- Option values (L3, L15, L36, L81, L165, L169): `interaction_grid in (:slice_pair,:source_slice,:node)`, `grid_extent in (:extrema,:sigma)`, `slice_interpolation in (:linear,:quadratic)` (interface.jl L1467-1476) with defaults `:slice_pair`, `:extrema`, `:linear`.
- Drift convention (L44-47): sigma = (c - z)/2 equals `sL = 0.5*(center_source - lb_field)`, `sR = 0.5*(center_source - rb_field)` (pic_cpu.jl L1143-1144), consistent with note 1's field drift `0.5*(z_field - center_source)`.
- Three planes per slice (L118-129) = the "6-plane path" per slice pair on the fully-indexed wavefront route (pic_cpu.jl L892-900); 3N/2N = 1.5 and 0.3912/0.3110 = 1.258 (L151-153).
- References exist: the three validation scripts (L178-180), `docs/history/slice_longitudinal_interpolation_record.md`, and the companion note's Section 5 is "Continuity breakers below the algorithm".

coherent_beam_beam_modes.md
- Scripts and contract exist (L3-9, L384): `coherent_mode_vlasov_theory.jl`, `coherent_mode_scans.jl`, `coherent_beam_beam_modes.jl`, `plot_coherent_mode_theory.py`, `coherent_mode_eic_comparison.jl`, `CoherentModePhysicsContract` (Contracts.jl L2201); `simulate_1d_model`, `OCTOPUS_VLASOV_NJ` (72), `OCTOPUS_VLASOV_NPHI` (128) in the script.
- Rigid Y = 1 by degree -2 homogeneity (L59-66): correct.
- Averaged kernel G(u) (L96-98): closed form matches quadrature to 1.8e-16; transform (L187) re-derived (half-normal average of e^{-|k||v|}); u(0) = (1+r)/(1+sqrt2 r) gives 0.828 (r=1) and 0.992 (r=0.02), within the quoted 0.2% of the measured 0.990; harmonic kernel -sqrt(JJ')/2 (L176) re-derived.
- Section 4 constants (L340-341) match `examples/strong_strong_tracking.jl` (10 GeV / 275 GeV, sigma_e = (106, 9.5) um, sigma_p = (95, 8.5) um, beta_e = (0.55, 0.056), beta_p = (0.8, 0.072), tunes (0.08, 0.14) and (0.228, 0.210), N_e = 1.7203e11, N_p = 0.6881e11); the four xi values reproduce (0.0882, 0.1004, 0.00937, 0.00941); band edges 0.1650/0.2371 (max u 0.965/0.969) and 0.2126/0.2168 (y-plane u(0) = 0.7246) and the ratios 1.06, 0.84, 1.52 are arithmetically consistent.
- Discrete-map drift (L309-326): exact-map Y_eff = 1.209386 and 1.243439 at xi = 0.005 and 0.02 (the note's 1.2094 and 1.2434); cot(2 pi 0.31) = -0.396; the leading-order form -pi Y0^2 cot(2 pi Q0) xi is the correct first-order expansion.
- Gap Lambda - max u ~ 0.33 (L233): 1.162 - 0.827 = 0.335 (round), 1.321 - 0.990 = 0.331 (r = 0.02).

weak_strong_6d_model.md
- Drift transport A(u), A_u (L48-56), conditional mean/covariance (L104-120), slope and within-slice covariance (L153-172), finite-bin term (L196-198): all re-derived and correct (the zeta terms cancel in the conditional covariance, as the probe confirms numerically).
- `virtual_drift` (L73-78): default `:hirata`, `:chromatic`, `:exact` (strong_beam.jl L124-145); `UnsafeVirtualDrift(name)` with `:paraxial_frozen_longitudinal`, `:chromatic_frozen_energy` (L43-57); "Section 7" of `beam_beam_longitudinal_kick.md` is "Alternative named virtual-drift Hamiltonians".
- Coordinate ordering (x, p_x, y, p_y, z, p_z) matches `gaussian_strong_beam_covariance`'s documented order; `lattice_hamiltonian_and_conventions.md` Sections 2-3 define longitudinal pairs only and contain nothing that conflicts with the six notes (hypothesis 2: k_bb and phi_PIC conventions agree between notes 1, 2 (Section 18) and 3; note 2 Section 1's "general k_bb" is flagged as such by the note).

## Unchecked

- (Resolved before hand-back.) The U47-6 measurement completed: `probes/U47/vlasov_selfcheck.log` holds Self-check 4 with rigid = 1.0 (max 1.0003) at all eleven aspect ratios; nothing about U47-6 remains unchecked.
- Measured tables I did not reproduce (each would be a minutes-long run; harness status is stated instead): note 1 Section 9 field-validation and bi-Gaussian tables (scripts exist and are named); note 2 Section 16 tables (`validation/spectral_poisson_field_validation.jl` exists); note 3 Section 3.4-3.5 tables (no harness, U47-2) and the CUDA cost/count numbers (0.191/0.249/0.253/0.440 s, 306 tables, 645 MB); note 4's measured jump/coarsening/cost numbers (their tables live in the companion note, another unit's region); note 5's 2D PIC scans and the 4096-turn EIC comparison.
- Note 1 Section 7.1's statement that `_cp_covariance_kick` carries the lambda_{1,u}, lambda_{2,u}, theta_u terms was not re-derived (that derivation belongs to `beam_beam_longitudinal_kick.md`, outside this region); I checked only that the function exists and is the one called.
- Note 1 Section 10 lists five correctness checks; testsets exist for the pure-Gaussian limit ("GaussianPIC beats PIC toward the soft-Gaussian kick") and the rank-deficient fallback, but I found no testset titled for the zero-subtraction bit-identity or the far-field monopole decay. The note phrases these as prescribed checks rather than as existing tests, so this is noted, not claimed.
- Note 2 Section 12 (Bessel and Mathieu domains) was read and is standard; not independently verified numerically. The commit hash `e3818be` cited at note 3 L319 was not checked (no git in the audited tree).
- Cross-file seams noted and stopped at: U47-8 (the canonical-versus-physical dispersion convention, `twiss_dispersion.md` (D6)-(D8), owner decision 2026-10-18 in `docs/experiences.md`); U47-7 (constructor accepts `:node` + `:quadratic`, refusal deferred to `_validate_pic_solver`).
