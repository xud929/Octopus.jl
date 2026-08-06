# 2026-08-05_b audit — lead index

Mechanically extracted from the 26 archived unit reports, so it cannot drift
from them by hand-copying. **Every row is a LEAD, not a finding**: the series'
measured agent survival is ~60%, in four miss shapes (right; right for the wrong
reason, and the reason determines the fix; wrong; narrower than the truth). A row
is worth one reproduction, not a fix.

Status is filled in as rows are dispositioned. Blank = not yet reproduced.

**305 leads** — 20 Major/High, 88 Medium, 161 Low, 36 Info/style. **105 dispositioned.**

| id | sev | status | location | claim |
|---|---|---|---|---|
| U13-2 | major | F9 FIXED | `src/tasks/Tasks.jl:391-407` | An exception raised inside `execute!`'s failure-path loss report |
| U13-3 | major | F10 FIXED | `src/tasks/Tasks.jl:519-528` | An exception from `finalize_observers!` (or `_finalize_line_observers!`) |
| U13-4 | major | CONFIRMED, FIXED (2026-08-06) | `src/knobs/Knobs.jl:895-918` | The documented lossless round trip `knob_expression(string(e)) == e` |
| U14-1 | major | F5 FIXED | `src/track/phase6d_track.jl:304-314` | the **contextless** CUDA `track!` builds a fresh `TrackingContext()` *inside* its |
| U14-2 | major | F13 FIXED | `src/math/counter_rng.jl:50-61, src/beam/Beam.jl:166, src/elements/radi` | explicit `rng_id`s do not reserve themselves in the atomic auto-id counter, and the |
| U15-1 | major | F11 FIXED | `src/elements/beam_line.jl:568-593` | a kept-whole line (girder/cryostat) — the flagship feature of this file — |
| U20-1 | major | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:7629 ("TSC weights are bit-identical across backends ` | this new testset cannot fail on the defect its own comment names — its |
| U20-2 | major | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:8080 ("Knob registry atomicity and round-trip totalit` | the "round-trip totality" half is not total — the documented invariant |
| U20-3 | major | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:7133 (and 6604, 8451)` | on a CPU-only host **17 testsets and 402 of the 415 GPU-gated assertions |
| U21-1 | major | F8 FIXED | `test/nightly_suite.sh:49-57` | the suite's exit code is recovered by **scraping the log file**, a channel |
| U21-17 | major | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:235-247, 633-636` | `OCTOPUS_CUDA_THREADS`, `OCTOPUS_CUDA_BLOCKS` and `OCTOPUS_CPU_THREADS` |
| U22-1 | high | CONFIRMED, FIXED (2026-08-06) | `validation/coherent_mode_vlasov_theory.jl:108,111-112 (`GH_N/GH_W`, `g` | The flat-beam regime the note and the script disown as a limitation of the 1D |
| U24-1 | high | CONFIRMED, FIXED (2026-08-06) | `validation/slice_interpolation_emittance_growth_summary.jl:60-88` | the arm-grouping key omits `npart` and `turns`, so the baseline arm silently pools 22 runs |
| U26-1 | major | FIXED | `docs/theory/gaussian_longitudinal_slicing.md § "Measured ranking"` | the note states the shipped default slicing rule is `:equal_area` and |
| U26-2 | major | CONFIRMED, FIXED (2026-08-06) | `docs/theory/slice_longitudinal_interpolation.md §7.5, §10.6, §12` | the note says CUDA `:quadratic` exists only on the sequential |
| U26-3 | major | FIXED | `docs/README.md (theory index entries for aperture and RF cavity)` | the index describes two implemented subsystems as unimplemented — |
| U26-4 | major | CONFIRMED, FIXED (2026-08-06) | `docs/theory/coherent_beam_beam_modes.md §2` | §2 states the equilibrium potential is "normalized to $\hat V_0''(0)=1$ so |
| U6-1 | major | F7 CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/pic_cpu.jl:608 (also 870–938 and 824)` | under `interaction_grid = :node` and `:source_slice` the dropped-charge tripwire is |
| U6-2 | major (performance) | CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/pic_cpu.jl:1338–1365 (constants at src/tasks/st` | `_PIC_PARALLEL_DEPOSIT_MIN = 4096` now selects the fixed 16-chunk deposit far below |
| U9-1 | major | F4 FIXED | `src/elements/solenoid.jl:166 (`_SOL_MIDPOINT_ITERS`), 411 (`nst` defau` | the curved solenoid's implicit-midpoint stage is solved by a fixed 16 |
| U1-1 | medium | F1 CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/pic_cuda.jl:156-160, 360-366, 728-830, 832-926,` | the per-pair luminosity sink `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` is populated by the |
| U11-1 | medium | F6 FIXED | `src/tasks/strongstrong/spectral_cuda.jl:49-50 (identical copies at 440` | The CUDA R9 dropped-charge tripwire reports **exactly zero** for the most |
| U12-1 | medium | CONFIRMED, FIXED (2026-08-06) | `src/knowledge/Knowledge.jl:891-902 (declared-defaults check absent)` | `ParamMeta.default` is decoration — nothing in the repository compares a |
| U12-11 | medium | CONFIRMED, FIXED (2026-08-06) | `src/policies/Policies.jl:259-264` | `_active_cuda_launch` is an **undeclared second consumer** of |
| U12-2 | medium | PARTLY WRONG: parameter-is-read already covered (353 checks); recorded 2026-08-06 | `src/knowledge/Knowledge.jl:904-910, 948-965 (parameter-is-read and rea` | nothing verifies that a declared element parameter is consumed by the |
| U12-3 | medium | CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/interface.jl:1617 and :1743 — hardcoded POLICY ` | `validate_configuration_metadata`'s type enumeration was totalized for |
| U12-4 | medium | CONFIRMED, FIXED (2026-08-06) | `src/knowledge/Knowledge.jl:960-964` | for an element declaring more than one tracking method, only the |
| U13-1 | medium | CONFIRMED, FIXED (2026-08-06) | `src/knobs/Knobs.jl:394-418` | `@knob p::T` on an existing knob whose converted value is `isequal` to |
| U13-5 | medium | CONFIRMED, FIXED (2026-08-06) | `src/tasks/Tasks.jl:429 (and 242)` | A line whose `:L` is a knob expression makes every `execute!` that was |
| U14-3 | medium | CONFIRMED, FIXED (2026-08-06) | `src/track/longitudinal.jl:133-136 (`_delta_from_pt`), reached from `co` | a particle decelerated below rest energy makes the radicand negative and `sqrt` |
| U15-2 | medium | CONFIRMED, FIXED (2026-08-06) | `src/elements/beam_line.jl:599-616 (`compile_runtime(::ElementSpec{:lin` | a misaligned line that contains a bend is surveyed as **straight**, so its |
| U15-3 | medium | CONFIRMED, FIXED (2026-08-06) | `src/elements/beam_line.jl:310-320 (`Base.reverse`)` | reflection now **aliases** placements — the reversed line and its source |
| U15-4 | medium | F12 FIXED | `src/elements/beam_line.jl:568-577 (`track_particle(::AbstractTrackingM` | the context-free call path applies **one borrowed tracking method to every |
| U15-5 | medium | CONFIRMED, FIXED (2026-08-06) | `src/elements/aperture.jl:104-117 (`_loss_record_matches_rep`) + src/ta` | the task's loss record is reused for **any** representation of the same |
| U15-6 | medium | CONFIRMED, FIXED (2026-08-06) | `src/elements/beam_line.jl:384-391 + :637 (the new `L` ParamMeta on `:l` | declaring `L` as a `:line` parameter re-opens the walker split U11-1 |
| U15-7 | medium | CONFIRMED, FIXED (2026-08-06) | `src/elements/beam_line.jl:122-143 (`_FOLDED_NAMED_STRENGTHS`, `_FOLDED` | the folded-name guard is a hand-copied table that misses the sixth |
| U16-2 | medium |  | `docs/theory/rf_cavity_and_reference_energy.md:88-89 and 285-288` | ** The theory note — the design authority the element's |
| U16-4 | medium | CONFIRMED, FIXED (2026-08-06) | `src/elements/patch.jl:118-127 (`_patch_reference_length`)` | ** `_patch_reference_length` returns the new origin's displacement |
| U16-5 | medium | CONFIRMED; documented + pinned, not re-signed (2026-08-06) | `src/elements/patch.jl:74-82 vs src/elements/ref_tilt.jl:69-70` | ** The patch and the misalignment/`ref_tilt` family share |
| U17b-1 | medium |  | `test/runtests.jl:1599-1601` | the `_curv_vers` seam loop asserts `< 1.0e-14` on a quantity whose measured value |
| U17b-3 | low-medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:1889` | `@test r.metrics[:checked] > 200` leaves 153 checks (43% of the real count) of |
| U18-1 | medium |  | `test/runtests.jl:3134-3207 ("No method grows a Core.Box outside the ar` | the permanent `Core.Box` sweep catches **3 of 7** injected boxes — its |
| U18-2 | medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:3209-3288 ("CPU solver stack is thread-count invarian` | the second (above-threshold) block is a hand-copy of the first block's |
| U18-3 | low-medium |  | `test/runtests.jl:4252-4256, 4270-4274 ("Lattice cells track and stay s` | three CPU↔CUDA agreement checks are asserted as |
| U19-1 | medium | CLOSED by the U20-3 fix (2026-08-06) | `test/runtests.jl:6599 (gate at 6604)` | `"CUDA GaussianPIC coupled subtraction matches CPU"` is the only CUDA gate |
| U19-2 | medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:4733–4776 (Spectral arm)` | the Spectral arm of `"Lost particles cannot influence a strong-strong |
| U19-3 | medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:4778–4841` | `"Lost-particle charge semantics are pinned per solver family"` pins **2 |
| U20-4 | medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:7199 ("CUDA near-round Gaussian transition matches CP` | at `T = Float32` the near-axis sample point cannot detect a zero, |
| U20-5 | medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:7173 ("CUDA round Gaussian near-axis stability")` | the testset's named subject — near-axis kick stability — is compared under |
| U20-6 | medium | CONFIRMED, FIXED (2026-08-06) | `test/runtests.jl:7572 ("CUDA spectral deposit tripwire (R9, U9-1)")` | this new testset verifies "leaves exactly its unit charge" using only a |
| U21-10 | medium | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:29-39` | the U18-2 documentation fix landed by `b986c73` was inserted **into the |
| U21-11 | medium | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:35-36 vs 642-650` | the same commit's documentation and code contradict each other about |
| U21-12 | medium | REFUTED: test/result IS gitignored and the comment is accurate (2026-08-06) | `test/examples/strong_strong_tracking.jl:644-650` | the U18-5 fix's own comment misdescribes its own code, and the fix |
| U21-13 | medium | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:45-46` | U18-1 was only half-fixed. The code comment at 365-369 now correctly warns |
| U21-15 | medium | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:252-351 (all boolean toggles)` | every boolean `OCTOPUS_*` toggle silently treats an unrecognised value as |
| U21-16 | medium | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:230 and test/examples/weak_str` | `OCTOPUS_USE_GPU` is the one boolean with a stricter, different grammar |
| U21-18 | medium | CONFIRMED, FIXED (2026-08-06) | `test/examples/strong_strong_tracking.jl:352-364, 424-441` | all seven `OCTOPUS_CUDA_PIC_*_THREADS` overrides are validated and then |
| U21-19 | medium | PARTLY CONFIRMED: capacity=0 is a documented disable; the REPORT was wrong, fixed (2026-08-06) | `test/examples/strong_strong_tracking.jl:352-353, 589-600` | `OCTOPUS_MOMENT_CAPACITY=0` is silently accepted, writes **no moment files |
| U21-2 | medium | CONFIRMED CLOSED by U21-1 fix (2026-08-06) | `test/nightly_suite.sh:56-57` | the same scrape turns a **PASSING** suite into `FAIL` with a synthetic |
| U21-3 | medium | CONFIRMED, FIXED (2026-08-06) | `test/nightly_suite.sh:36-43` | lock contention writes **no row at all** and exits 0, so a wedged or |
| U21-4 | medium | CONFIRMED, FIXED (2026-08-06) | `test/nightly_suite.sh:33,46` | two further row-less exits. `mkdir -p "$OUTDIR"` (line 33) is unchecked, so |
| U22-2 | medium-high | CONFIRMED, FIXED (2026-08-06) | `docs/theory/coherent_beam_beam_modes.md:64-67 and validation/coherent_` | The theory note and the script's own header state `u(0)=1` and an incoherent |
| U22-3 | medium-high | CONFIRMED, FIXED (2026-08-06) | `validation/coherent_mode_vlasov_theory.jl:703-704 and docs/theory/cohe` | Every number in §4's x row is a quadrature artifact — the continuum edges (max |
| U22-4 | medium | CONFIRMED, FIXED (2026-08-06) | `validation/coherent_mode_vlasov_theory.jl:342-364 vs :235-254` | Self-check 5 — the check advertised as validating "every assembly constant ... |
| U22-5 | medium | CONFIRMED, FIXED (2026-08-06) | `docs/theory/coherent_beam_beam_modes.md:186-187` | The finite-ξ map correction is quoted with the **wrong sign** — "(for Q_0 = 0.31: |
| U22-6 | medium | CLOSED by the U22-1 rewrite (2026-08-06) | `docs/theory/coherent_beam_beam_modes.md:131-140 (the † footnote)` | The footnote that justifies flagging the r = 0.02-0.05 row quotes max-`u` numbers |
| U22-7 | medium | CONFIRMED, FIXED (2026-08-06) | `docs/theory/coherent_beam_beam_modes.md:243 (and :233-256)` | The §4 **comparison** table still states the retracted y-plane prediction ("top |
| U22-8 | low-medium | CONFIRMED, FIXED (2026-08-06) | `validation/coherent_mode_vlasov_theory.jl:399-403,410` | The referee's section comment states the **retracted** Fourier transform, and its |
| U22-9 | low-medium | CONFIRMED, FIXED (2026-08-06) | `validation/coherent_mode_vlasov_theory.jl:64-71` | The header's "residual inconsistency" block describes a diagnostic the code no |
| U23-1 | medium | CONFIRMED, FIXED (2026-08-06) | `validation/pic_gaussian_luminosity_validation.jl:81-82 (+148-149)` | The region's only enforced numeric gate compares production `_pic_luminosity` against |
| U23-2 | medium | CONFIRMED, FIXED (2026-08-06) | `validation/gaussian_pic_field_validation.jl:124-131` | The "HYB" column of the table that `docs/theory/gaussian_subtracted_pic_solver.md` §9 |
| U23-3 | medium-low |  | `validation/near_round_gaussian_transition.jl:173-188 and 407-411` | The script that is the theory note's declared validation of the near-round/elliptic |
| U24-2 | medium | CONFIRMED, FIXED (2026-08-06) | `validation/lattice_cells.jl:239-243` | the gate added for U21-3 covers 2 of the 4 error metrics the file's own header declares; |
| U24-3 | medium | FIXED earlier (642bc86); verified 2026-08-06 | `validation/symplecticity_validation.jl:13-14 (and validation/README.md` | both the script header and the README claim coverage of every registered `Symplectic6DMap` |
| U24-4 | medium | FIXED | `validation/symplecticity_validation.jl:11` | the header advertises `OCTOPUS_SYMPLECTICITY_TOL=5e-7`, ten times the code's actual default |
| U24-5 | medium | CONFIRMED, FIXED (2026-08-06) | `validation/symplecticity_validation.jl:116-124` | the script derives the case list from the contract but does **not** run the contract's |
| U24-6 | medium |  | `test/runtests.jl:7106 (SEAM — outside my region, reported and stopped)` | the one place that runs `symplecticity_validation.jl` automatically passes |
| U25-1 | medium |  | `validation/pic_option_consistency.jl:119-124 (+ :226-228)` | on the GPU, choosing `interaction_grid=:node` or `slice_interpolation=:quadratic` |
| U25-2 | medium |  | `validation/counter_rng_validation.jl:86-92` | the script's gate is a *statistics* test, not a *generator* test — it |
| U25-3 | medium | CONFIRMED, FIXED (2026-08-06) | `validation/counter_rng_validation.jl:86-92` | the same gate's tolerances are fixed absolute constants while the |
| U25-4 | medium |  | `validation/tracking_backend_consistency.jl:154 (seam: src/contracts/Co` | `:aperture` is covered by the tripwire **by name only** — with the |
| U3-1 | medium |  | `src/tasks/strongstrong/pic_cuda.jl:5564-5578, 5660-5668` | The CUDA slice transverse moments change with the launch grid rather than only with |
| U3-2 | medium |  | `src/tasks/strongstrong/pic_cuda.jl:5158, 5165, 2101, 1214` | `threads = 512` — a value the repository's own launch-geometry contract sweeps and |
| U3-3 | low-medium |  | `src/tasks/strongstrong/pic_cuda.jl:4885-4898, 5073-5090` | The CIC branch of `_cuda_pic_interpolate_field` and `_cuda_pic_interpolate_kick` is |
| U3-6 | low-medium |  | `src/tasks/strongstrong/pic_cuda.jl:4002-4010, 4034-4051, 4077-4094, 41` | The CUDA PIC route is **not** run-to-run bit-reproducible: the same process, the same |
| U4-1 | medium | CONFIRMED, not fixed — needs a probe redesign; on todo.md (2026-08-06) | `src/contracts/Contracts.jl:1963-1967 (probe) → :2125 (decision)` | the `:aperture` probe produces an all-NaN baseline, so all 11 aperture parameters counted in `checked` are decided by a NaN comparison that can only ever say "the parameter moved the map" — the apertu |
| U4-10 | low-medium |  | `src/contracts/Contracts.jl:321-322 with :344-348 and :351-354` | on a single-threaded Julia the `PublicConfigurationEffectivenessContract`'s worker-invariance comparison executes zero times, yet the metrics report it as measured and passed. |
| U4-11 | low-medium | CONFIRMED, FIXED (2026-08-06) | `src/contracts/Contracts.jl:1351-1371 with docstring :1310-1317` | the "analytic weak-strong reference" that `HighEnergyWeakStrongLimitContract` holds the soft-Gaussian solver to at 2e-14 is not analytic and not independent — it calls the same three functions the pro |
| U4-12 | medium-low |  | `src/contracts/Contracts.jl:1932-1986 (probes) with :2064` | `misalign_convention` — the MAD-X-vs-Bmad rotation composition order, which the PTC contract's `quad_mis_all` / `cfbend_mis_all` cases exist precisely to pin — is **inert at every shipped probe**, on  |
| U4-2 | medium |  | `src/contracts/Contracts.jl:2116-2117 and :2122, message at :2135-2137` | of the 501 declared element parameters (`ParamMeta` entries across all registered specs), 353 are checked, 36 are documented-inactive, and **112 are silently dropped** — neither counted in `checked` n |
| U4-3 | medium |  | `src/contracts/Contracts.jl:2061-2072 (`_perturb_param`)` | `_perturb_param`'s magnitude and type dispatch make ~15 declared parameters permanently unverifiable, and the "rejected ⇒ consumed" reasoning at :2122 is wrong for all of them. |
| U4-4 | medium-low | CONFIRMED, FIXED (2026-08-06) | `src/contracts/Contracts.jl:1942-1945 (`:sbend` probe)` | `sbend.fringe` is bitwise inert at the probe the contract ships, violating the probes' own stated design rule, and the Symbol blind spot (U4-2) guarantees nobody will ever be told. |
| U4-5 | medium |  | `src/contracts/Contracts.jl:2444-2454` | the U3-8 repair to the `:cuda_pic_launch` branch of `_solver_contract_receipt_carries` is vacuous for **both** options that actually take that branch, so the per-option receipt claim is still receipt- |
| U4-6 | medium |  | `src/contracts/Contracts.jl:2432-2443 with :2552-2555 / :2651-2655` | for options whose declared consumer is `:solver_runtime`, "the value reached a runtime consumer" is proven by reading back a receipt that is a verbatim dump of the object under test — the check's pass |
| U4-7 | medium |  | `src/contracts/Contracts.jl:2459-2471 vs :2338-2339` | the new solver-enumeration tripwire guards `contract.probes`, but the sweep iterates the hardcoded `_solver_contract_types()`. The two sets are different, so the natural response to a firing tripwire  |
| U4-8 | medium |  | `src/contracts/Contracts.jl:1276-1290 with :1172-1243` | the declaration↔case tripwire constrains exactly **one** registered kind, and fifteen kinds whose declared tracking method is `Symplectic6DMap` have no symplecticity case at all. The tripwire's author |
| U4-9 | low-medium |  | `src/contracts/Contracts.jl:867-879 with metrics at :905-915` | `StrongStrongPICBackendConsistencyContract` reports three named checks as passed with nothing compared, for public parameter choices its own docstring advertises. |
| U5-1 | medium | F2 FIXED | `src/tasks/strongstrong/interface.jl:2015-2025` | the U4-4 ordering fix reversed the truncation window instead of closing it — an |
| U5-2 | medium | CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/interface.jl:2217-2218` | the luminosity schedule is evaluated twice per collision per turn — once by the |
| U5-3 | low-medium | CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/interface.jl:2009-2010 (declaration at 1596-160` | `luminosity_append` declares `consumer=:strong_strong_output`, but the only |
| U5-4 | low-medium | CONFIRMED, FIXED (2026-08-06) | `src/tasks/strongstrong/interface.jl:1726-1733` | the task block of `validate_configuration_metadata` compares the schema default to |
| U6-3 | medium (performance) | CLOSED by the U6-2 fix; measured + pinned 2026-08-06 | `src/tasks/strongstrong/pic_cpu.jl:1990–1991` | the luminosity deposit calls the **workspace-less** `_pic_deposit!`, so above 4,096 |
| U7-1 | moderate | CONFIRMED, FIXED (2026-08-06) | `src/tasks/BeamObservers.jl:1094` | `_discard_replayed_snapshots!` truncates the file to preserve |
| U7-2 | moderate | CONFIRMED, FIXED (2026-08-06) | `src/tasks/BeamObservers.jl:1557 (`_jld2_replace!`), reached from 1549,` | a process death anywhere inside a `JLD2BeamMomentObserver` flush loses |
| U7-3 | moderate | CLOSED by the U7-2 fix; measured + pinned 2026-08-06 | `src/tasks/BeamObservers.jl:1531–1561` | `JLD2BeamMomentObserver` file size is **quadratic** in the number of |
| U7-4 | moderate | CONFIRMED, FIXED (2026-08-06) | `src/tasks/BeamObservers.jl:1745 (`_is_hdf5_output`), consumed at 1669–` | `MomentObserver` writes HDF5 to whatever path it is given, but |
| U7-5 | moderate | CONFIRMED, FIXED (2026-08-06) | `src/tasks/BPMObserver.jl:200–205 (`_bpm_centroid`)` | on a CUDA beam a BPM reading copies **all six** coordinate arrays to the |
| U9-2 | medium |  | `src/elements/lattice_magnets.jl spec blocks (drift 1092–1100, quadrupo` | the per-kind `parameters` declarations under-declare what `_lattice_magnet` |
| U1-2 | low |  | `src/tasks/strongstrong/pic_cuda.jl:585-605` | the U1-3 fix that landed in this diff copied three of the four fields the CUDA |
| U1-3 | low |  | `src/tasks/strongstrong/pic_cuda.jl:1587` | `_cuda_pic_prepare_interaction_wavefront_indexed!` hardcodes `threads = 256` — the |
| U1-4 | low |  | `src/tasks/strongstrong/pic_cuda.jl:16-21` | `collide!(solver, beam1, beam2, CUDABackend, ctx::TrackingContext)` accepts a real |
| U1-5 | low |  | `src/tasks/strongstrong/pic_cuda.jl:130-149, 1349-1452 — OUT OF HYPOTHE` | under `interaction_grid = :node` no particle that escapes its turn-start node mesh is |
| U1-6 | low |  | `src/tasks/strongstrong/pic_cuda.jl:670-696` | after the F10 fix, `_cuda_pic_extract_slice`'s `longitudinal_kick` parameter is dead |
| U10-1 | low |  | `src/tasks/strongstrong/gaussian_pic.jl:141-158` | `configuration_report(::GaussianPICPoissonSolver)` reports `status=:resolved` |
| U10-2 | low |  | `src/tasks/strongstrong/gaussian_pic.jl:775-820` | `_gpic_collide!` neither resets nor reports `workspace.dropped[]`, while |
| U10-3 | low |  | `src/tasks/strongstrong/gaussian_pic.jl:353,361-362,373-376` | the CPU moment pass always accumulates the four cross-plane sums |
| U10-4 | low |  | `src/tasks/strongstrong/gaussian_pic_cuda.jl:732-735` | `_cuda_gpic_gtuple` reads `m.cxy`, `m.cxpy`, `m.cypx`, `m.cpxpy` |
| U10-5 | low |  | `validation/gaussian_pic_field_validation.jl:44-72` | the validation script that produces the theory note's §9 accuracy table |
| U11-2 | low |  | `src/tasks/strongstrong/spectral_cuda.jl:279-287` | The CUDA warning's `dropped_fraction` is diluted by a denominator that |
| U11-3 | low |  | `src/tasks/strongstrong/spectral_cuda.jl:283-284 vs spectral.jl:411-412` | The two tripwires emit the same message string but different structured |
| U11-4 | low |  | `src/tasks/strongstrong/spectral_cuda.jl:686-719 and 639-681` | `field_precision=:single` reaches beyond the field solve: it downgrades |
| U11-5 | low |  | `src/tasks/strongstrong/spectral_cuda.jl:394 (also 529, 543)` | The three CUDA solve entry points cannot survive an empty source |
| U11-6 | low |  | `test/runtests.jl, "CUDA spectral deposit tripwire (R9, U9-1)" testset` | The comment "No transverse-path assert: that map never moves x/y inside |
| U11-7 | low |  | `docs/theory/spectral_sine_poisson_solver.md §13` | The recorded CPU/CUDA agreement figure ("kicks ~4e-16, luminosity |
| U12-10 | low |  | `src/knowledge/Knowledge.jl:839-845, 955-959` | the knowledge layer hard-codes the list of generic placement wrappers |
| U12-12 | low |  | `src/policies/Policies.jl:330-338` | the public `configuration_report` docstring states a six-item status |
| U12-13 | low |  | `src/policies/Policies.jl:45-50, 83-87` | `ExecutionAuditReceipt.backend` is written at every one of the ~30 |
| U12-14 | low |  | `src/policies/Policies.jl:96-102, 185-210` | `PlaceholderPolicy` and the deprecated `GPUExecutionPolicy` — both |
| U12-15 | low |  | `src/policies/Policies.jl:131-138` | `AbstractGPUExecutionPolicy` is a taxonomy node whose documented purpose is |
| U12-16 | low |  | `src/examples/Examples.jl:1-35` | `Example` is one of AGENTS.md's seven Core Objects, and its entire runtime |
| U12-17 | low |  | `src/knowledge/Knowledge.jl:538-554 — **out of hypothesis**` | `description()` silently returns `""` for 15 of the 35 types the registry |
| U12-18 | low |  | `src/knowledge/Knowledge.jl:84-104 — **out of hypothesis**` | the unknown-spec-key warning re-fires on **every** `compile_runtime` of a |
| U12-19 | low |  | `src/registry/Registry.jl:6-16 vs 211-226` | the `OctopusRegistry` docstring still enumerates exactly three |
| U12-20 | low |  | `src/Octopus.jl:107-121` | the script-mode ForwardDiff branch is dead under every committed |
| U12-5 | low |  | `src/knowledge/Knowledge.jl:899-900` | the "construction_help mentions every parameter" check is a bare substring |
| U12-6 | low |  | `src/knowledge/Knowledge.jl:173-180, 886-889` | three metadata channels the framework presents as authoritative — |
| U12-7 | low |  | `src/knowledge/Knowledge.jl:316-323` | a second `@element_spec` block for an already-registered kind silently |
| U12-8 | low |  | `src/knowledge/Knowledge.jl:967-982` | three of the validator's checks — friendly schema, friendly |
| U12-9 | low |  | `src/knowledge/Knowledge.jl:834-839` | the docstring on `_compiled_matches_runtime` is **detached** — the four |
| U13-6 | low |  | `src/tasks/Tasks.jl:503-518 (seam with BeamObservers.jl:74-80)` | A scheduled hook whose schedule cannot fire anywhere in the requested |
| U13-7 | low |  | `src/knobs/Knobs.jl:390-393` | Declaring a brand-new knob bumps the global epoch, so every |
| U13-8 | low |  | `src/knobs/Knobs.jl:196-202, 913-916` | `@knob_expr(-(5.0))` prints as `"-5.0"`, which reparses as the *literal* |
| U13-9 | low |  | `src/knobs/Knobs.jl:957-968 (out of hypothesis)` | A knob expression inside a **nested** tuple or a **vector**-valued spec |
| U14-4 | low |  | `src/track/longitudinal.jl:133-148, and the "4.4e-16" pin in docs/theor` | `_delta_from_pt` and `_pt_from_delta` are written in their cancelling forms, so |
| U14-5 | low |  | `src/beam/Beam.jl:445-455 vs 457-474` | the U15-7 directed refusal for non-`AbstractFloat` coordinate types was added to |
| U14-6 | low |  | `src/track/longitudinal.jl:100-103 (`reference_beta` docstring)` | the docstring's stated *reason* for choosing `√((γ-1)(γ+1))/γ` is measurably |
| U14-7 | low |  | `src/track/radiation_track.jl:33-65` | `cuda_track_lumped_rad_kernel!` is the only GPU radiation path that does **not** |
| U14-8 | low |  | `src/track/phase6d_track.jl:38-48 vs 304-314` | `_reject_contextless_tracking` — the directed refusal that exists so a |
| U14-9 | low |  | `src/beam/Beam.jl:650-691 vs 40-44` | `beam_statistics` on an empty `Phase6DRep` raises Base's generic |
| U16-1 | low | FIXED | `docs/theory/rf_cavity_and_reference_energy.md:160,163 (also docs/todo.` | ** The F16 correction block sends a future fixer to the wrong section — |
| U16-10 | low |  | `examples/weak_strong_tracking.jl:65, examples/strong_strong_tracking.j` | ** The same physical quantity, 12.5e-3 rad, is the **half** crossing |
| U16-3 | low |  | `src/elements/rf_cavity.jl:251 (`construction_help`)` | ** The velocity-slip model boundary is documented on the human docstring |
| U16-6 | low | FIXED | `src/elements/patch.jl:155 and :208` | ** The `PatchSpec` docstring's first worked example and the kind's |
| U16-7 | low | VERIFIED, not fixed — see note | `examples/weak_strong_tracking.jl:40 and :106` | ** `input.total_turns = 1_000_000` is **never read** — the file's |
| U16-8 | low |  | `src/elements/chromaticity_kick.jl:104,110,116,117` | ** `ChromaticityKick`'s tracking kernel is written with the Float64 |
| U16-9 | low |  | `src/elements/{rf_cavity,patch,chromaticity_kick,crab_cavity,lorentz_bo` | ** The declaration↔case tripwire added for `SymplecticityContract` |
| U17b-2 | low |  | `test/runtests.jl:1599-1601 and :1616` | the two seam checks in the new "Series helpers" testset have **zero** discriminating |
| U17b-4 | low |  | `test/runtests.jl:626-629` | on the Float32 leg, `soft_result ≈ weak_result rtol=32eps(T) atol=32eps(T)` admits |
| U17b-5 | low |  | `test/runtests.jl:1918 (also :1888, :1897, :44, :57)` | five assertions in the region cannot fail; they are guaranteed by the line above |
| U17b-6 | low |  | `test/runtests.jl:46-50` | the runtime banner that exists specifically to make CUDA skips visible understates |
| U17b-7 | low |  | `test/runtests.jl:2205-2210` | the AD sweep's floor is exact **today** (measured `verified = 25`, headroom 0) but |
| U17b-8 | low |  | `test/runtests.jl:904-909` | the `:equal_area` "closed form" check compares `_gaussian_slices` against an |
| U18-4 | low |  | `test/runtests.jl:3014-3085 ("Curved frame x transverse field: every ro` | the permanent h≠0 symplecticity sweep does **not** derive its case list; the |
| U18-5 | low |  | `test/runtests.jl:3718-3720 ("Unknown spec keys warn…")` | the comment promises a check ("match the message and check the kwarg |
| U18-6 | low |  | `test/runtests.jl:2876-2879 ("Observer finalizers, BPM noise keys, and ` | `@test @elapsed(Octopus._scheduled_turns(s, 5, 10^8)) < 0.005` is a |
| U19-10 | low |  | `test/runtests.jl:5805` | `@test isapprox(lum32, lum64; rtol=1.0e-5)` in |
| U19-4 | low |  | `test/runtests.jl:5747–5779` | `"PIC kbb override uses physical units"` is circular — the pass is |
| U19-5 | low |  | `test/runtests.jl:6341–6365` | the `:node` defining-property block — 18,036 of this testset's 30,053 |
| U19-6 | low | FIXED | `test/runtests.jl:4878` | `@test Octopus.longitudinal_slices(poisoned, sl) isa Any` asserts nothing |
| U19-7 | low | WONTFIX (idiom; recorded) | `test/runtests.jl:5182` | `@test Threads.nthreads(:default) > 1 skip = (Threads.nthreads(:default) == 1)` |
| U19-8 | low |  | `test/runtests.jl:5299–5300 and 5587–5588` | the two `curved = false` warning pins are content-free — `@test_logs |
| U19-9 | low |  | `test/runtests.jl:5628–5630` | the cross-implementation solenoid↔SBend reference — U17 rated it one of |
| U2-1 | low | F1 confirmed, open | `src/tasks/strongstrong/pic_cuda.jl:3672` | the per-pair luminosity diagnostic trace `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` |
| U2-2 | low |  | `src/tasks/strongstrong/pic_cuda.jl:2603` | the node-indexed wavefront field solve deposits, Green-multiplies, |
| U2-3 | low |  | `src/tasks/strongstrong/pic_cuda.jl:2140` | the CUDA workspace cache key — which is also the identity of the embedded |
| U20-10 | low |  | `test/runtests.jl:8723` | `@test Octopus._pic_count_outside_box([1.0, NaN, 2.0], …) == 1` cannot |
| U20-11 | low | CONFIRMED, FIXED (2026-08-06) | `out-of-region seam — test/runtests.jl:46–51` | the `@info` a CPU-only user actually sees still says "**Nine** |
| U20-13 | low |  | `test/runtests.jl:7679–7684 — carry-over of U17's "note while there"` | the comment states "~1e-13: … well within the 1e-10 contract" and the |
| U20-7 | low | FIXED | `test/runtests.jl:8067` | `@test knob_symbolics_available() === Octopus._symbolics_adapter_active()` |
| U20-8 | low |  | `test/runtests.jl:8123 and 7992` | two hand-copied case lists with no declaration-to-coverage tripwire, in the |
| U20-9 | low |  | `test/runtests.jl:7629 (gating, not content)` | "TSC weights are bit-identical across backends" is a **pure host-side** |
| U21-14 | low |  | `test/examples/strong_strong_tracking.jl:365-381 vs 434-441` | the new note claims the commented block "stays as the reference for what |
| U21-20 | low |  | `test/examples/strong_strong_tracking.jl:677-684` | the summary block prints PIC-family settings unconditionally, so a |
| U21-21 | low |  | `test/examples/strong_strong_tracking.jl:415-422` | inconsistent grid-value validation. `OCTOPUS_PIC_LUMINOSITY_GRID` checks |
| U21-22 | low |  | `test/examples/strong_strong_tracking.jl:254-263` | `OCTOPUS_ELECTRON_ENERGY_GEV=-5` (a negative beam energy) is accepted and |
| U21-23 | low |  | `test/examples/strong_strong_tracking.jl:1-139` | eight `OCTOPUS_*` variables are still absent from the header after the |
| U21-24 | low |  | `test/examples/strong_strong_tracking.jl:159,179 and test/examples/weak` | dead configuration fields that read as authoritative defaults. |
| U21-25 | low |  | `test/examples/strong_strong_tracking.jl:291-292` | confirms and refines the prior unit's finding. Both harnesses write into |
| U21-26 | low |  | `test/examples/weak_strong_tracking.jl:33` | confirms and refines the prior unit's finding. Both harnesses write into |
| U21-27 | low |  | `both harnesses (write paths)` | confirms and refines the prior unit's finding. Both harnesses write into |
| U21-28 | low |  | `seam — moment `.h5` outputs are not reproducible` |  |
| U21-5 | low |  | `test/nightly_suite.sh:58` | the `testsets` column is a real, uncalibrated coverage tripwire: it is not |
| U21-6 | low |  | `test/nightly_suite.sh:36-43` | stale-lock reclamation is racy — two runs that both observe `-mmin +1440` |
| U21-7 | low |  | `test/nightly_suite.sh:15,17,29` | header/output mismatch. It documents `$HOME/.octopus_nightly/<date>.log` |
| U21-8 | low |  | `test/nightly_suite.sh:20-22` | the header's own justification is factually wrong — "the trailing-pipe trap |
| U21-9 | low |  | `test/nightly_suite.sh:69` | `ls -1t "$OUTDIR"/*.log \| grep -v latest \| …` filters on the whole path, so a |
| U22-10 | low | FIXED | `docs/theory/coherent_beam_beam_modes.md:30-32` | "For flat beams the gradient scales as 1/σ_x (sheet-like field), so the same |
| U22-11 | low |  | `region-wide (see the table in §(f))` | 11 of the 13 thresholds in this region are print-only; no run in the region can |
| U22-12 | low |  | `validation/coherent_beam_beam_modes_beambeam3d.jl:8-30,67-68` | The cross-code comparison **data** is committed and reproduces exactly, but its |
| U22-17 | low |  | `validation/coherent_mode_scans.jl and validation/coherent_mode_eic_com` | The committed strong-strong archives **no longer reproduce** from current code |
| U23-10 | low |  | `validation/gaussian_pic_field_validation.jl:90 and validation/gaussian` | Both local-reimplementation scripts hardcode the second-order field derivative, so the |
| U23-11 | low |  | `validation/spectral_poisson_field_validation.jl:23, 244-245, 259` | Three header/comment statements disagree with the code beneath them (U20-4b/c/d, all |
| U23-12 | low |  | `docs/theory/gaussian_subtracted_pic_solver.md:693 + validation/gaussia` | "The hybrid is **never worse than PIC**" is contradicted by the max-error column of the |
| U23-13 | low |  | `validation/near_round_gaussian_transition.jl:29-60 (cross-file seam)` | The 96-point Gauss-Legendre reference — the independent standard the whole near-round |
| U23-4 | low | FIXED | `validation/gaussian_pic_field_validation.jl:17-20` | The header asserts the script exercises "real internals … PIC via `_pic_solve_field`"; |
| U23-5 | low |  | `docs/theory/gaussian_subtracted_pic_solver.md:695-701 + validation/gau` | The documented motivation for the coupled (rotated) subtraction branch — "the weakest |
| U23-6 | low |  | `validation/spectral_poisson_field_validation.jl:215-221` | `shape_relerr` returns **exactly 0.000e+00** for a "solver" whose field is the exact |
| U23-7 | low |  | `validation/pic_grid_extent_stability.jl:109-110` | The `dropped` column double-counts a corner escapee and measures a different box from |
| U23-8 | low |  | `validation/pic_gaussian_field_validation.jl:20-24` | The header's "Outputs are written under `result/`" list omits a file the script always |
| U24-10 | low |  | `validation/generate_ptc_reference.jl:336-355` | the committed reference table is truncated before the first MAD-X job runs, so a failure |
| U24-11 | low |  | `validation/high_energy_weakstrong_limit.jl:380-381` | the two Gaussian-arm thresholds are the only tolerances in the file that are neither |
| U24-12 | low |  | `validation/strong_strong_spectral_comparison.jl:1-27, 156-163` | the header has no `Outputs` section although the script writes five TSVs, and it carries a |
| U24-13 | low |  | `validation/slice_interpolation_emittance_growth.jl:26-35` | the arms table documents six arms A–F and omits the `:node` interaction-grid arm, which the |
| U24-7 | low |  | `validation/symplecticity_validation.jl:89-93` | the Lorentz leg is still hand-copied knowledge — reference point, crossing angle and both |
| U24-8 | low |  | `validation/slice_longitudinal_zscan.jl:98` | `source_slices = (4, 6)` is hardcoded while `OCTOPUS_ZSCAN_NSLICES` is a documented |
| U24-9 | low |  | `validation/slice_longitudinal_zscan.jl:34-38 vs 388-543` | the header describes one secondary pass (per-slice grid); the code runs and emits four |
| U26-10 | low |  | `docs/theory/slice_longitudinal_interpolation.md (file:line citations)` | nearly every `file:line` pointer in the note has rotted, and the note |
| U26-11 | low | FIXED | `docs/theory/solenoid.md §14.2` | "Contract now 41 cases"; the committed PTC reference table carries 55. |
| U26-12 | low |  | `AGENTS.md "Source Ownership" (out-of-hypothesis; task item f)` | the directory list names 7 of the 13 directories under `src/`. |
| U26-13 | low |  | `docs/theory/rf_cavity_and_reference_energy.md §6` | the note reads as a pending proposal for an element that is implemented, |
| U26-14 | low/style |  | `docs/theory/spectral_sine_poisson_solver.md §2` | "$\sin(\alpha_l\cdot 0)=\sin(l\pi)=0$" conflates the two edges — the |
| U26-15 | low/style | FIXED | `docs/theory/beam_line_composition.md §5, §7` | nomenclature drift — the note recommends `find(line, sel)` throughout |
| U3-4 | low |  | `src/tasks/strongstrong/pic_cuda.jl:5580-5584` | For a `Float32` beam the CPU builds the slice moments in `Float64` and the CUDA |
| U3-5 | low |  | `src/tasks/strongstrong/pic_cuda.jl:4661-4738` | `_cuda_pic_kick_indexed_kernel!` (4661-4696) and |
| U3-7 | low |  | `src/tasks/strongstrong/pic_cuda.jl:5136, 5173-5177` | For a `Float32` beam, `_cuda_gaussian_collide_sequential!` returns a `Float64` |
| U3-8 | low |  | `src/tasks/strongstrong/pic_cuda.jl:4774-4802` | `_cuda_pic_kick_pair_indexed_longitudinal_kernel!` is the only kick kernel in the |
| U4-13 | low |  | `src/contracts/Contracts.jl:180, :200, :310, :639, :683, :779, :1245, :` | every `validate` method takes `; kwargs...` and no method reads it, so any keyword a caller misspells or invents is silently accepted and dropped — the (e) unknown-keyword family, inside the file whos |
| U4-14 | low |  | `src/contracts/Contracts.jl:185-198, :1146, :1330, :1497, :2335` | the hand-written `description` method table covers 9 of the 11 concrete contracts; `PTCConsistencyContract` and `ElementParameterEffectivenessContract` fall through to a fallback that returns the empt |
| U4-15 | low |  | `src/contracts/Contracts.jl:1543-1545` | `CoherentModePhysicsContract(solver=:gaussian_pic)` — one of the three solver branches the contract's docstring declares, and one it declares *passing* — is executed by no test and no validation scrip |
| U4-16 | low |  | `src/contracts/Contracts.jl:1273` | the Lorentz quasi-symplecticity criterion uses two tolerances hardcoded in the function body (`1.0e-10`, `2.0e-7`) that no field of `SymplecticityContract` governs, so the contract's declared `default |
| U4-17 | low |  | `src/contracts/Contracts.jl:1987-2037 and :2257-2288` | neither exemption table has a staleness tripwire. Both are clean today (measured), but a `(kind, parameter)` or `(solver, option)` pair that no longer exists silently excuses nothing, and — the direct |
| U4-18 | low |  | `src/contracts/Contracts.jl:313 → src/tasks/strongstrong/interface.jl` | two of the checks `validate_configuration_metadata()` gained in the U3-4 repair, and which `PublicConfigurationEffectivenessContract` calls as its first act, cannot fail — the BPMObserver schema↔repor |
| U5-10 | low |  | `src/tasks/strongstrong/interface.jl:2160-2166` | the append-mode "replacing the entire existing luminosity history" warning fires |
| U5-11 | low |  | `src/tasks/strongstrong/interface.jl:1592 (export list at :1-10)` | `strong_strong_task_option_schema` is the only public configuration schema in the |
| U5-12 | low |  | `src/tasks/strongstrong/interface.jl:700-702 vs 647-677 — class (b)` | `LongitudinalSlicing` accepts three slicing methods that no docstring or schema |
| U5-13 | low | FIXED | `src/tasks/strongstrong/interface.jl:1545, 2064 — OUT OF HYPOTHESIS (tr` | two source comments point the reader at `pic_cuda.jl:5041` for the Gaussian |
| U5-14 | low |  | `src/tasks/strongstrong/interface.jl:1649-1654, 1743-1757, 1780-1792` | `validate_configuration_metadata`'s default-vs-constructor check is applied |
| U5-15 | low |  | `src/tasks/strongstrong/interface.jl:945-1179` | `backend_configurations` is a public `PICPoissonSolver` constructor keyword with a |
| U5-5 | low |  | `src/tasks/strongstrong/interface.jl:1484-1494 (declaration at 1413-141` | `grid_extent_sigma` declares `dependencies=(:grid_extent,)` but `_pic_option_active` |
| U5-6 | low |  | `src/tasks/strongstrong/interface.jl:2467-2482` | the identity→configuration change in `_collision_solver` silently accepts and |
| U5-7 | low |  | `src/tasks/strongstrong/interface.jl:2275-2281 (docstring claim at 2273` | `_record_solver_configuration!`'s docstring says "Costs nothing unless an |
| U5-8 | low |  | `src/tasks/strongstrong/interface.jl:2216 + 2467-2482 — OUT OF HYPOTHES` | `_collision_solver`'s new configuration comparison runs once per collision per |
| U5-9 | low |  | `src/tasks/strongstrong/interface.jl:2235-2245 — OUT OF HYPOTHESIS (obs` | the mixed-schedule dropped-row warning carries `maxlog = 4`, so a long run loses |
| U6-10 | low |  | `src/tasks/strongstrong/pic_cpu.jl:1418–1440` | the `length(local_charge) == nchunks` fallbacks are dead code, and the two of them |
| U6-4 | low (performance) |  | `src/tasks/strongstrong/pic_cpu.jl:1843–1858` | `_pic_field!` marks the whole `Ey` pass `@inbounds` but leaves the `Ex` boundary rows |
| U6-5 | low |  | `src/tasks/strongstrong/spectral.jl:1000 and 1043–1062` | the campaign's "including spectral luminosity (0 ulp)" is true of the **longitudinal** |
| U6-6 | low |  | `src/tasks/strongstrong/pic_cpu.jl:1551–1568` | `_pic_tsc_weights` still computes its weights from untyped `Float64` literals, so a |
| U6-7 | low |  | `src/tasks/strongstrong/slicing.jl:220–240 (`_live_z_stats`) and :464–4` | slice **membership** is identical CPU vs CUDA in every case I could construct (see |
| U6-8 | low |  | `src/tasks/strongstrong/slicing.jl:388` | the comment "One convention, slice 1, everywhere (audit part 6, R7)" is false for |
| U6-9 | low |  | `src/tasks/strongstrong/pic_cpu.jl:1243–1247` | two unreachable branches in `_pic_align_grid_origins`. |
| U7-10 | low |  | `src/tasks/BeamObservers.jl:1152–1176` | two `BeamMomentObserver`s writing one path silently interleave and lose |
| U7-11 | low |  | `src/tasks/BPMObserver.jl:170–171, 179–187` | `bpm_reading` mutates the observer. The exported convenience form |
| U7-12 | low |  | `src/tasks/BPMObserver.jl:200–205` | a BPM reading of a fully-lost beam is `NaN` by an undocumented `0/0`, |
| U7-13 | low |  | `src/tasks/BeamObservers.jl:934–937` | the compact coordinate record format has no framing or length check, so a |
| U7-6 | low |  | `src/tasks/BeamObservers.jl:1280–1286` | F3's "loud replacement" mitigation only fires when the whole table is |
| U7-7 | low |  | `src/tasks/BeamObservers.jl:1038–1042` | `_discard_replayed_binary_rows!` has no `filesize > 0` guard — the F7 fix |
| U7-8 | low |  | `src/tasks/BeamObservers.jl:1518–1605` | the JLD2 column layout is hand-copied into **three** independent places |
| U7-9 | low |  | `src/tasks/BeamObservers.jl:1223` | `MomentObserver(capacity=0)` silently skips the predictable-schedule |
| U8-1 | low |  | `src/elements/strong_beam.jl:1056-1061` | on the exact-round branch (`eta == 0`) the response evaluator returns |
| U8-2 | low |  | `src/track/strong_beam_track.jl:216-239, 252-285` | with `turns == 0`, CUDA `track!` **overwrites** `elem.last_luminosity` |
| U8-3 | low |  | `src/elements/strong_beam.jl:719` | `u < oftype(u, 1.0e-2)` in `_round_gaussian_hessian` is the exact |
| U8-4 | low |  | `src/elements/strong_beam.jl:1277-1280 — re-verification of prior lead ` | a `slice_center` supplied without a matching `slice_weight` is silently |
| U8-5 | low |  | `src/elements/strong_beam.jl:1285 — re-verification of prior lead U7-4,` | `slice_method = :equal_width` without `slice_width` throws |
| U9-3 | low |  | `src/elements/linear6d.jl:131–188 (`_linear6d_symplectic_error`, `_vali` | the symplecticity validator orders on `T` rather than `real(T)`, so a |
| U9-4 | low |  | `src/elements/lattice_magnets.jl:60–71 (`_curv_vers` crossover comment)` | the comment records "the closed branch holds <= 5.9e-15 for u in [0.125, 0.5]"; |
| U9-5 | low |  | `src/elements/solenoid.jl:464 (`nst` ParamMeta)` | the machine-readable `default=1` disagrees with the compile path's actual |
| U9-6 | low |  | `src/elements/linear_maps.jl:25, 103, 195; src/elements/linear6d.jl:19,` | the default friendly constructors of the four linear-map kinds pin `Float64` |
| U9-7 | low |  | `src/elements/linear_maps.jl:251–254 — OUT OF HYPOTHESIS (usability)` | `XYCoupling(r1::T, r2::T, r3::T, r4::T) where {T<:Number}` is strict same-type, |
| U9-8 | low |  | `src/elements/linear_maps.jl:263 — OUT OF HYPOTHESIS (error quality / d` | `g = inv(sqrt(1 + r1*r4 - r2*r3))` throws a bare `DomainError` with no element |
| U14-10 | info |  | `src/math/SpecialMath.jl:92-97` | `pi = zero(T)` inside `faddeeva_w_upper_reim` shadows `Base.pi` for the rest of the |
| U14-11 | info/seam |  | `src/math/SpecialMath.jl accuracy → src/track/strong_beam_track.jl:390-` | the Faddeeva real part carries no relative accuracy near the real axis, and its |
| U15-10 | minor |  | `src/elements/aperture.jl:416-441 (`Aperture(spec, method)`)` | supplying `alive` silently makes `shape`, `x_limit` and `y_limit` inert |
| U15-11 | minor |  | `src/elements/aperture.jl:295-304 (`_aperture_record!`)` | the turn number is stored in a slot whose element type is the *coordinate* |
| U15-12 | minor |  | `src/elements/beam_line.jl:335-346 (`_entry_label`)` | the beam-line design keys provenance paths on a `:name` parameter that |
| U15-13 | minor |  | `src/elements/aperture.jl:38-41 (LossRecord docstring claim)` | `LossRecord`'s docstring says the private-slot design means "CPU and CUDA |
| U15-8 | minor |  | `src/elements/beam_line.jl:385-389 (`_placement_length(::LineEntry)`)` | an `:L` placement override on a nested own-state line is stored, reported |
| U15-9 | minor | FIXED | `docs/theory/misalignment_and_patch_maps.md:262-266` | the theory note tells the reader Octopus exposes `misalign_convention` |
| U16-11 | style |  | `examples/weak_strong_tracking.jl:1` | ** Style only. `using LinearAlgebra` sits on line 1, **above** the |
| U20-12 | info |  | `test/runtests.jl:7103, 7113 — carry-over of U17-7` | the two `include`s of `validation/symplecticity_validation.jl` and |
| U22-13 | info |  | `docs/theory/coherent_beam_beam_modes.md:118-120,211-212,167` | The figures the regenerated sections point at predate the data they claim to |
| U22-14 | info |  | `docs/theory/coherent_beam_beam_modes.md:167,177,122-129` | Presentation defects in §3 that make the section hard to read correctly: the |
| U22-15 | info |  | `validation/coherent_mode_vlasov_theory.jl:678-680,415; validation/cohe` | Hand-copied constants and formulas across the region (Measured Lesson 4), all |
| U22-16 | info |  | `validation/coherent_mode_vlasov_theory.jl:508` | Self-check 4's 2e-2 tolerance passes at r=0.5 with only 11% of its budget to |
| U22-18 | info |  | `validation/coherent_mode_vlasov_theory.jl:718` | Latent crash — `maximum(v for v in vals if v <= e_band[2] + 5 * xi_e)` throws |
| U23-14 | trivial |  | `validation/pic_grid_extent_stability.jl:26 and src/tasks/strongstrong/` | Both the validation docstring and the production docstring record ":sigma … measured |
| U23-9 | trivial |  | `validation/gaussian_pic_zscan.jl:60, 88` | The documented override `OCTOPUS_GPIC_ZSCAN_NSLICES` throws `BoundsError` for any |
| U25-10 | minor |  | `validation/tracking_context_policy_consistency.jl, strong_strong_obser` | three scripts print their CUDA skip but offer no way to *require* the GPU |
| U25-11 | minor |  | `validation/pic_option_consistency_summary.jl:55-58, 90-102` | the summary pairs a run with its baseline by tag suffix alone and never |
| U25-12 | minor |  | `validation/README.md:881-890 and validation/{crossing_luminosity_ancho` | the two entries added for U21-1 are attached to the wrong section and |
| U25-13 | minor |  | `validation/README.md:213-256 §"Tracking Backend Consistency"` | the README entry for the region's most important script was not updated |
| U25-14 | info |  | `validation/crossing_luminosity_anchor.jl:6` | the only script in the region whose `include` of `src/Octopus.jl` is not |
| U25-15 | info |  | `validation/strong_strong_{diagnostics,pic_extreme}_benchmark.jl — unde` | both benchmark scripts read a dozen globals that leak out of |
| U25-16 | info — infrastructure |  | `seam: test/examples/strong_strong_tracking.jl fixed output directory` |  |
| U25-5 | minor | CONFIRMED, FIXED (2026-08-06) | `validation/strong_strong_diagnostics_benchmark.jl:26-64` | the script's turn count and the harness's turn count are two different |
| U25-6 | minor |  | `validation/strong_strong_diagnostics_benchmark.jl:108 and validation/s` | both benchmark scripts hand-copy the CUDA PIC launch-family list instead |
| U25-7 | minor |  | `validation/README.md §"Beam Optics Interface Consistency"` | the README credits the script with a check it does not perform — "and |
| U25-8 | minor |  | `validation/README.md and three script headers — undocumented outputs` | four output files that the region actually writes are named in neither |
| U25-9 | minor |  | `validation/README.md §soft_gaussian_pic_comparison and §moment_observe` | two scripts abort immediately without a GPU, and the README presents both |
| U26-5 | minor | CLOSED by the U22-3 fix (2026-08-06) | `docs/theory/coherent_beam_beam_modes.md §4 (EIC eigen-solve table)` | the x-plane continuum edges quoted in the theory table are set by the |
| U26-6 | minor | FIXED | `docs/theory/pic_free_space_kernels.md §3.5` | §3.4's correction block states plainly that at grid 128 `:lattice` "comes |
| U26-7 | minor | CONFIRMED, FIXED (2026-08-06) | `docs/theory/pic_free_space_kernels.md §3.4 correction table vs src/tas` | the note and the source carry the same re-measurement and disagree on the |
| U26-8 | minor | FIXED | `docs/theory/misalignment_and_patch_maps.md §6a` | §6a names two `misalign_convention` values that do not exist. |
| U26-9 | minor | CONFIRMED, FIXED (2026-08-06) | `docs/theory/slice_longitudinal_interpolation.md §10.5 + §12` | the note advertises `grid_extent = :sigma` as complementary to |
| U8-6 | informational |  | `— out-of-hypothesis, cross-file seam` | `validation/near_round_gaussian_transition.jl` computes exactly the two |
| U9-9 | info |  | `src/elements/solenoid.jl:188–196 — OUT OF HYPOTHESIS (style)` | `mz` in `_solenoid_curved_map` is assigned in every fixed-point sweep and |

## Notes on individual dispositions

**U16-7 — verified, deliberately not fixed.** The claim is correct:
`examples/weak_strong_tracking.jl`'s `input.total_turns` is read nowhere, and
the run length is a duplicated literal (`1_000_000` at two sites). The obvious
fix — pointing `moment_stop` at `input.total_turns` — **does not work and was
reverted after being caught by running the example**: `moment_stop` lives
*inside* the `input = (...)` literal, so the reference is to a variable that
does not exist yet (`UndefVarError: input not defined`). The sibling
`examples/strong_strong_tracking.jl` gets this right only because it uses
`input.total_turns` at the *point of use*, outside the config block. Fixing it
properly means restructuring the example's config literal, which changes a
curated precedent rather than repairing a defect — the auditor's call, not a
drive-by edit. Left for a session that can re-run and re-pin both examples.

**U19-7 — WONTFIX, recorded.** `@test nthreads(:default) > 1 skip = (nthreads(:default) == 1)`
is circular as filed, but it is the Julia idiom for "assert this premise where
it is testable, mark it skipped where it is not", and it does that job.
Rewriting it would be churn; manufacturing Minor findings to look thorough is
itself a defect in an audit.
