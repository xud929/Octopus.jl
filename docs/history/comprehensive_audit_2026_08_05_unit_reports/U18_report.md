# U18 — examples/ and test/examples/ audit

Repo: /cfs/ad/dxu/Library/Julia/Octopus, HEAD 83e1d38 at audit start.

## Coverage

Read line-by-line (100%): examples/knob_control.jl (159), examples/weak_strong_tracking.jl
(289), examples/strong_strong_tracking.jl (264), test/examples/weak_strong_tracking.jl
(318), test/examples/strong_strong_tracking.jl (677). Cross-read for verification:
test/runtests.jl 3156-3183 (examples testset) and 7090-7115; AGENTS.md examples
sections (56-58, 195-202, 309-324); src/tasks/strongstrong/interface.jl 20-70
(AbstractPoissonSolver doc), 794-822 (Gaussian), 902-1296 (PIC ctor), 1669-1733
(collision marker + StrongStrongTask .lum doc), 2315; spectral.jl 144-173;
gaussian_pic.jl 94-130; Policies.jl 98-209 (policy defaults); beam/Beam.jl 408-520
(kwargs incl. `R` alias); BeamObservers.jl 663-715 (LuminosityObserver/MomentObserver);
elements/{lorentz_boost,crab_cavity,linear_maps,strong_beam}.jl (field names,
:equal_area); constants/Constants.jl; math/counter_rng.jl; docs/knob_control.md;
docs/theory/{gaussian_subtracted_pic_solver,spectral_sine_poisson_solver}.md; .gitignore.

Executed (all exit 0, CPU only, outputs confined to scratch):
- examples/knob_control.jl directly from the repo root as documented (writes no files).
- Patched scratch copies of examples/weak_strong_tracking.jl,
  examples/strong_strong_tracking.jl, and test/examples/strong_strong_tracking.jl
  (only the Octopus include path made absolute and `result_dir` redirected to
  scratch — required because the originals write into the repo tree, see U18-3).
  test/examples/weak_strong_tracking.jl was not re-run: its body is
  diff-identical to the clean example outside the config/env section.
- exports probe: `Base.isexported(Octopus, s)` for all 52 public symbols the five
  scripts call.

Caveat: other audit agents modified src/ files concurrently mid-probe (tree was
clean at start; my commands were read-only against the repo). Both strong-strong
probes loaded the same tree state, so the pair comparison stands.

## Leads

### U18-1 test/examples/strong_strong_tracking.jl:357-360 (and header 36-37) — stale solver-swap instructions predate the OCTOPUS_SOLVER selection block — MEDIUM

Lines 357-360: "PIC is the default solver. To use the soft-Gaussian solver
instead, comment out the PICPoissonSolver construction below and uncomment this
block." Following this is broken: the commented `solver = GaussianPoissonSolver(...)`
at 361-369 (and the spectral block at 386-393) sits ABOVE the
`solver = if solver_name == ...` selection at 412-468, so an uncommented
assignment is immediately overwritten at 412; and commenting out the
PICPoissonSolver call inside the `else` branch (448-467) leaves `solver = nothing`
on the default path. The supported route is `OCTOPUS_SOLVER=gaussian|spectral|...`
(lines 395-402, header 29-31), added later. Header lines 36-37 compound it: "The
soft-Gaussian solver is also available as a commented alternative below the
solver construction" — the block is above the construction. This is exactly the
comment-rot failure mode the knob example once suffered (runtests.jl:3157-3160).
(The clean example's commented alternatives at examples/strong_strong_tracking.jl:168-179
are fine — they sit directly below a plain `solver = PICPoissonSolver(...)` and
all their keywords check against the constructors.)

### U18-2 test/examples/strong_strong_tracking.jl:1-130 — header omits 12+ env vars the harness reads — LOW/MEDIUM

The header's contract is to document the OCTOPUS_* interface; grep of lines 1-130
shows zero mentions of: OCTOPUS_CPU_THREADS (read :235), OCTOPUS_N_MACRO (:215,
common ELE/PRO override), OCTOPUS_PROTON_ENERGY_GEV (:252; header 40-43 shows only
the electron knob), OCTOPUS_CUDA_NVTX (:334), OCTOPUS_DISABLE_MOMENTS (:337),
OCTOPUS_DISABLE_LUMINOSITY_OUTPUT (:339), OCTOPUS_MOMENT_CAPACITY (:343),
OCTOPUS_SPECTRAL_FIELD_PRECISION (:407), OCTOPUS_GPIC_GRID (:408; only in the
inline comment at 399), legacy fallback aliases
OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO/_GROWTH (:293, :296), and 6 of the 7
OCTOPUS_CUDA_PIC_*_THREADS overrides (:345-353; only DEPOSITION_THREADS appears,
at :117). By contrast test/examples/weak_strong_tracking.jl documents all 4 vars
it reads (134-147 vs header 18-26).

### U18-3 examples/weak_strong_tracking.jl:38, examples/strong_strong_tracking.jl:54 — clean examples write into the repo working tree by default — LOW

`result_dir = joinpath(@__DIR__, "..", "result")` resolves to repo-root
`result/` (harnesses: `test/result/`, test/examples ws:61, ss:139). Writes:
weak_strong.lum, weak_strong_moments.h5, pic_hcc.{lum,ele.h5,pro.h5}. Mitigation:
`result/` is gitignored (.gitignore "Generated simulation and validation output")
and both headers state the location honestly (ws:24, ss:27; harness ws:43-44,
ss:124-129). But the suite's examples testset (runtests.jl:3156-3183) runs all
five scripts on every `Pkg.test` and never cleans the artifacts up, so suite runs
mutate the working tree. Audit ground rule: repo-tree-writing example = lead.

### U18-4 test/runtests.jl:3160-3161 — examples-testset comment misstates the scripts' defaults — LOW

"Each script runs in a subprocess at its small config defaults (2 turns, 10k
macroparticles, CPU policy)" is true only of the weak-strong pair.
examples/knob_control.jl:36-39 defaults to turns=1, n_macro=4; both strong-strong
scripts default to 200 macroparticles/beam (examples/strong_strong_tracking.jl:44-46;
test/examples/strong_strong_tracking.jl:142 default_demo_macroparticles=200,
216-219). Comment↔code drift inside the very testset that guards the examples.

### U18-5 test/examples/strong_strong_tracking.jl:111 — documented OCTOPUS_TURN_TIMING_PATH example writes into repo-root result/ — LOW

`OCTOPUS_TURN_TIMING_PATH=result/pic_turn_times.tsv` is relative; the script
resolves it against the cwd (code 630-639 mkpath+open with the raw string), which
per the run instructions (line 11-13) is the repo root — contradicting the same
header's claim at 124-125 that "this harness keeps its outputs beside the tests"
in test/result/.

### U18-6 test/examples/weak_strong_tracking.jl:33 — harness still calls itself "a concise precedent" — LOW (cosmetic)

"This file is meant to be a concise precedent for realistic weak-strong
tracking" is leftover positioning from before the clean example existed;
AGENTS.md (195-198, 311-317) assigns the precedent role to examples/, and this
file's own lines 6-9 already defer to examples/weak_strong_tracking.jl.

Known/out-of-scope: examples/knob_control.jl:151 `Octopus._symbolics_adapter_active()`
was pre-flagged by the audit; grep confirms it is the ONLY internal (`Octopus._*`
or unexported) usage in all five files (exports probe: symbol defined, not exported).

## Sound (verified clean)

- All five scripts run to completion (exit 0) at their documented defaults on
  CPU; run commands in the headers are accurate (suite uses the same invocation,
  runtests.jl:3173).
- Weak-strong pair: bodies are diff-identical outside the config/env section;
  harness env defaults (TURNS=2, N_MACRO=10000, USE_GPU=0, CUDA_DEVICE unset →
  device=nothing) exactly equal the clean config block and policy defaults.
- Strong-strong pair: at defaults the example and harness produce bit-identical
  electron and proton rms vectors and byte-identical pic_hcc.lum; every harness
  env default equals a constructor/example default (batch_mode :wavefront,
  green_cache :slice_pair, min_ratio 0.50, growth 0.25, cuda_* true,
  luminosity_every 1 → schedule nothing, CUDALaunchConfig 256/:auto,
  CPUThreadsExecutionPolicy :auto, StrongStrongDiagnostics all-off,
  moment capacity 100, schedule stop = total_turns 50000).
- Cross-citations present and correct in both directions for both pairs
  (examples ws:12-14, ss:11-14; test/examples ws:6-9, ss:4-9).
- Config-block discipline holds: zero ENV reads in all three examples/ scripts
  (grep OCTOPUS_ = 0); ws harness reads exactly its four documented vars.
- Exports probe: all 52 public symbols used across the five scripts are
  exported; every keyword the scripts pass exists in the current constructors
  (Beam incl. `R` alias, ThinStrongBeamSpec/GaussianStrongBeamSpec, all four
  Poisson solvers incl. the commented alternatives, TrackingTask policy kwarg,
  ElementSpec kinds :lorentz_boost/:thin_crab_cavity/:crab_dispersion and their
  runtime fields .angle/.strengthX/.zeta1).
- knob_control printed physics verified by hand: ele crab kick
  tan(0.0125)/sqrt(150*0.55)=1.376276e-3 (matches docs/knob_control.md:152),
  proton harmonic ratio exactly -4 (4/3 vs -1/3), K=±1000*0.05/81.1=±0.616523,
  symbolic derivative equals finite difference to 1e-9, and reassigning
  ip.half_crossing_angle recompiles the SAME task (tracked x changes), as the
  header claims. Header "no files are written" confirmed; Symbolics adapter
  activates in script mode as the else-branch message describes.
- Output-format claims match the writers: ws .lum rows = turn + luminosity
  (LuminosityObserver doc, BeamObservers.jl:672); ss .lum = "turn\tip" header +
  per-collision luminosity (interface.jl:1714).
- Example comments' external claims verified: AbstractPoissonSolver docstring
  documents exactly the shared keywords cited (interface.jl:34-48); the
  GaussianPIC 64-vs-128 parity claim matches gaussian_subtracted_pic_solver.md:733-734;
  the spectral N_thin ~ 5*d*r rule matches the doc's recommended defaults;
  docs/knob_control.md exists and uses the same API names.
- knob_control's "strong-strong example's electron and proton constants" claim
  holds field-for-field (0.55/150/394 MHz; 0.8/1300/197 MHz; 12.5 mrad); the ws
  pair pins slice_method=:equal_area explicitly, correctly insulating it from
  the 2026-07-31 default change to :sqrt_density (strong_beam.jl:268-273).

Probe artifacts: scratchpad/U18/{knob,exports,ws_example,ss_example,ss_harness}.out,
result_{ws,ss,ssh}/, patched copies ws_example.jl, ss_example.jl, ss_harness.jl,
exports_probe.jl.
