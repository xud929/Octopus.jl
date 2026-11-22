# BBSCL and Octopus: implementation and performance comparison (2026-11-22)

Owner request, 2026-11-22: compare the GPU beam-beam code BBSCL (checkout at
`/home/cfsd/dxu/Library/AcceleratorCodes/bbscl`, origin `github.com/BBSCL/bbscl`, HEAD `24b5eaf`
"Restore bfc5b26 with NaN aperture handling", 2026-09-28) with Octopus (tree `599d577`) on three
axes: implementation, performance on this machine's GPU, and what Octopus should borrow. BBSCL
is K. Ohmi's collider code: the `sctr` space-charge tracker of 2006, the Fortran `bbss`
strong-strong module of 2019, a CUDA port begun 2022-04, and a 2022-11 port of SAD's element
maps ("ZhiYuan's code"); its `HISTORY` file is the only documentation and the repository ships
no example input. Everything below about BBSCL was read from its source (file:line citations
are into that checkout) and, where it mattered, measured by running it; nothing in that
checkout was modified. The comparison scripts, the BBSCL inputs they generate and the raw run
output are under `validation/bbscl_comparison/` (see "Reproduction" at the end).

Companion reading in this repository: `docs/current_runtime.md` (the Octopus runtime this record
compares against), `docs/history/production_benchmark_2026_09_06.md` (the production timing
protocol reused here), `docs/theory/beam_beam_longitudinal_kick.md` (the synchro-beam map both
codes implement).

## 1. Scope and method

- **Implementation**: six read-only source surveys (four of BBSCL by subsystem, two of
  Octopus), cross-checked against each other and against runs; the survey notes are the source
  of every file:line below.
- **Performance**: three matched cases run on the same GPU within one hour, nothing else on
  the device, the load average logged before and after every arm, sequential arms, the BBSCL
  and Octopus arms of a case adjacent in time. BBSCL has no per-turn timer: its number is the
  `cudaEvent` pair around its whole turn loop (`gpu_time`, bbcol3d.cu:644-647, 785-802; TrackGPU
  element.cu:732-735, 826-831) divided by the turn count, so it includes everything a turn does
  (collision, lattice, moments, the per-`ITMon` host copies). Octopus's number is the mean of
  `turn_timings` over the turns after a warm-up window (the per-turn clock of `execute!`), which
  includes everything a turn does except the first turns' compilation and allocation. The two are
  the closest like-for-like clocks the codes offer; the difference between them is stated where
  it matters.
- **Physics agreement** is reported beside every timing: a speed comparison between two codes
  that compute different things is not a comparison. Luminosity per crossing and the rms beam
  sizes are the observables both codes print.
- **Not compared**: BBSCL's space-charge and impedance modules (Octopus has neither), its
  beamstrahlung and crab-waist options (switched off; the comparison cases are e-p), the CPU
  paths (BBSCL's CPU tracker is a one-particle debug stub, element.cu:842-974), and MPI
  (BBSCL has none).

## 2. Provenance

| item | value |
|---|---|
| machine | acnlinj4 (2 x Xeon Gold 6430, 128 threads), one NVIDIA RTX 4500 Ada (24 GB, sm_89), driver 580.119.02 |
| BBSCL build | `nvcc` 12.6.85 from a conda-forge `cuda-nvcc` environment (`/home/cfsd/dxu/opt/cuda-conda`; the machine has no CUDA toolkit), host `g++` 11.5, `-O3 -arch=sm_89 -dc -w` (the Makefile's `-w -dc` plus optimisation and the native architecture; the Makefile itself passes no `-O` and no `-arch`), linked against the environment's cuFFT 11.3, cuRAND 10.3.7, cuSOLVER 11.7.1. Two programs: `collider` (two rings, strong-strong) and `prmb` (one ring, weak-strong), the latter linked by hand because `pr.mk` lacks the `section_map.o` the 2026-04 SectionMap commit added to the main Makefile only |
| Octopus | tree `599d577`, Julia 1.12.4, CUDA.jl runtime 13.0 artifacts, `--threads=4`, source-include mode |
| BBSCL source | 83 files, 1.7 MB, 18 commits since 2025-10-24; `HISTORY` dates the CUDA version to 2022-04 |

## 3. Implementation comparison

### 3.1 At a glance

| aspect | BBSCL | Octopus |
|---|---|---|
| language, size | CUDA C/C++, ~80 files, one `Makefile`; no tests, no documentation beyond `HISTORY` | Julia with CUDA.jl, one module; a 460-testset suite, contracts, theory and design notes |
| input | text files `<base>_e.in`, `<base>_p.in`; one statement per `;`, `Type Name=({k0,k1,...});`, positional parameter slots per element type (element.cu:1300-1408, 1756-1852); no sample input in the repository | Julia scripts constructing specs; keyword constructors with metadata, `element_help`, refusal of unread configuration |
| particle storage | AoS `d_beam[6*ip+k]`, `double` (element.cu:362; typereal.h:1) | SoA `Phase6DRep`, `Float64` (Float32 as a whole-line option) |
| coordinates | SAD: `x, px/P0, y, py/P0, z (head positive), delta`; SAD maps wrapped by a `px /= (1+delta)` conversion at every element (drift.cu:47-48, 66-67) | `x, px/P0, y, py/P0, z = s - l, delta` (PTC TIME=FALSE); no per-element conversion |
| turn execution | one persistent kernel per beam per turn, thread = particle, `switch` over a flat element-type array, element parameters in a flat `double` array addressed by an on-the-fly prefix sum (element.cu:347-481) | the line is a heterogeneous isbits tuple unrolled at compile time (`@generated fusedTrack`); one launch per turn per fused segment, the strong beam lifted into its own launch |
| element maps | SAD `tbend/tquad/tthin/tmulti/tsol/tcav` ports: exact drift, exact sector/rectangular bend, exact-in-delta thick quad with kinematic corrections, 3-drift/2-kick sextupole, leapfrog multipole, solenoid as a per-thread state machine, thin RF kick between half drifts | exact drift and sector bend; quad/sext/oct/multipole as symplectic split integrators (Strang `nst=1` default, Forest-Ruth order 4), optional PTC-style fringes; exact solenoid; thin RF cavity with the velocity slip at the cavity |
| radiation | lumped `Radiation` element: per-coordinate damping rates and normalised-coordinate excitation, cuRAND normals generated once per turn and reused by every radiation element (ph_rot.cu:247-340; element.cu:761) | lumped `LumpedRadSpec`: per-plane `exp(-1/tau)` damping, excitation in the normal-mode frame, Philox counter RNG keyed on (seed, turn, rng_id, particle, component) |
| weak-strong | Hirata synchro-beam map inside the turn kernel (`bb_map`, bb.cu:329-489), equal-charge Gaussian slices, Bassetti-Erskine through a 61 x 51 table of 8th-order local Taylor expansions of w(z) (errf.cu:132-217), Lorentz boost per particle inside the map | the same synchro-beam map (`:hirata`, plus `:chromatic` and `:exact` virtual drifts), seven slicing rules, Bassetti-Erskine through `erfcx` on CPU and a Weideman rational approximation on CUDA, Lorentz boosts as separate elements |
| strong-strong | Gaussian (`BBGAU`): per-slice float moments by shared-memory reduction and float atomics, Bassetti-Erskine kick; PIC (`BBPIC`): fixed input mesh in metres, float CIC atomics, one integrated Green table per mesh plane built once, single-precision R2C/C2R cuFFT, bicubic field interpolation, 8 FFTs and 6 device syncs per slice pair, all N^2 pairs sequential; slices by a one-block counting sort each turn | soft-Gaussian, PIC, spectral and Gaussian-subtracted PIC solvers; PIC: adaptive per-pair meshes, Float64 complex FFTs batched over a dependency wavefront, integrated Green with a per-pair cache, CIC/TSC, boundary-plane longitudinal interpolation; slices as index lists, no sort |
| luminosity | strong-strong: CIC overlap of the two slices on a common grid per pair (bbpic.cu:689-811); weak-strong: Gaussian density per particle, float `atomicAdd` into one address | PIC: a separate centroid-plane deposit per pair; Gaussian: density per sampled particle; weak-strong: per-particle density, device tree sum |
| RNG | cuRAND XORWOW, seed hard-coded `1234ULL` (bbcol3d.cu:641-642); host LAPACK `DLARAN` with a compiled-in seed, no input keyword (ran.cu:159) | stateless Philox4x32-10 counter RNG, reproducible across thread counts, launch geometry and MPI ranks |
| determinism | float atomics in deposition, moments, luminosity and bunch length: not run-to-run reproducible; both beams initialised from one fixed host stream | CPU bitwise at any thread count; CUDA PIC not bitwise (float atomics), declared, with a 1e-10 CPU/CUDA contract; soft-Gaussian route bitwise |
| loss | periodic sweep every 20 elements (`|x|>Ax`, `|y|>Ay`, NaN; element.cu:458-468), `Apert` element, `lost` codes, early exit of lost threads | NaN in all six coordinates, apertures as elements with loss records; dead particles keep flowing |
| output | `.f10` one row per turn (moments, luminosity), `.f15` particle dumps, stdout blocks; legacy banner that does not describe the lines that follow | one HDF5 run artifact per task with ledger, moments, luminosity, losses; receipts for every launch |
| parallelism beyond one GPU | none (OpenMP header included, never enabled) | CPU threads, MPI ranks x threads, CUDA |
| other physics | space charge (FFT solver with boundary conditions), single- and multi-bunch wakes, beamstrahlung, crab waist, injection | linear optics objects, crab cavities with turn-by-turn noise, Twiss/dispersion analysis, knobs |

### 3.2 Element-by-element tracking

**Kernel structure.** BBSCL's `TrackBeamGPU` (element.cu:347-481) is one kernel per beam per
turn: `ip = blockDim.x*blockIdx.x + threadIdx.x`, `x = d_beam + 6*ip`, a loop over all elements
with `switch(d_ElemType[i])` calling `__host__ __device__` map functions compiled in other
translation units (`-dc`, no device link-time optimisation, so the calls cross the device ABI
without inlining), `if(lost[ip]) break` to retire lost threads, and a NaN/aperture sweep every
20 elements. Every thread runs `updatephy(d_BeamParam)` at kernel start, writing the same values
to `__device__` globals (element.cu:366; DEF_func.cu:447-466), a benign race the two rings need
because they share those globals. There is no shared memory, no `__syncthreads`, no
`__launch_bounds__`. The one atomic is the float luminosity accumulation at a weak-strong IP
(element.cu:417). A second mode, `TrackSCBeamGPU`, launches one kernel per element and exists
for space charge and wakes, which need a grid-wide barrier (element.cu:496-681).

Octopus compiles the line into one specialised kernel per tuple type and launches once per
turn per fused segment under a `TrackingTask` (`src/tasks/Tasks.jl`), with the strong beam in its
own launch because its runtime struct is mutable (`src/track/strong_beam_track.jl:207-208`).
Element parameters travel as kernel arguments (registers and parameter space), not as a global
array; element types are resolved at compile time, so there is no `switch`. The AoS layout of
BBSCL costs a 48-byte stride per particle per coordinate access, read once and written once per
turn since the particle stays in registers; Octopus's SoA gather-scatter is coalesced but
happens once per launch.

**Maps.** Both codes use exact drifts and exact sector bends. The quadrupole differs: BBSCL's
`msolqu` (MAP_quad.cu:51-290) is SAD's exact-in-delta linear quadrupole matrix with kinematic
`exp(:dH:)` corrections, one slice for `|K1 L| < 0.2`; Octopus's default quadrupole is one Strang
drift-kick-drift step (`nst=1`, `integrator_order=2`), exact-in-delta through the drift but
second order in the body. BBSCL's sextupole is SAD's three-drift two-kick scheme with a
correction kick (MAP_sodd.cu:58-132), Octopus's a Strang step. BBSCL applies the Maxwellian
hard-edge dipole fringe in every bend unconditionally (MAP_bend.cu, steps 3 and 5 of
`mbcore_KO`), as Octopus's `bend_fringe=true` default does. BBSCL's GPU RF cavity is a thin
kick between two half drifts, `delta += V/(E beta^2) (sin(k z + phi) - sin phi)`
(cav.cu:436-444), with the frequency from `frev*HARM`; the full SAD cavity with transit-time
and RF focusing exists only on the CPU path. Two BBSCL map defects were found by reading:
the sextupole's entrance fringe is never applied because `if (DISFRIN == 0)` tests the enum
constant (sext.cu:218), and the bend precomputation drops `AE1/AE2` for finite-angle bends
without `K1` (bend.cu:82-83). The cavity writes two derived coefficients into the shared
parameter block from every thread (cav.cu:436, 439).

**Radiation.** Both codes lump damping and excitation into one element. BBSCL's `rad_map`
damps each raw coordinate by `(1-d_i)` and adds normal-coordinate noise with amplitudes
`sqrt(2 d eps)` (new scheme, ph_rot.cu:258-285); the six normals per particle come from one
`curandGenerateNormal` per turn per beam (bbcol3d.cu:692), so every `Radiation` element in a
lattice reuses the same six numbers. Octopus draws per element from the counter RNG keyed on
the element's `rng_id`.

**Loss handling.** BBSCL sets `lost = i+1000` on the periodic sweep and lets the thread leave
the element loop; the cadence is 20 in the code (element.cu:458) and 30 in `HISTORY`. Octopus
kills by writing NaN into all six coordinates and tracks the dead particle through every
element; reductions mask them. BBSCL's `Apert` setter allocates 10 reals and reports 12
(drift.cu:110-138), so the ring assembly reads two reals past each block (element.cu:1680).

### 3.3 Weak-strong beam-beam

Both codes implement Hirata's synchro-beam map slice by slice: drift to `S = (z - z_i)/2`,
`delta -= (px^2+py^2)/4`, Bassetti-Erskine kick with the slice's transverse covariance
transported to `S`, a longitudinal kick from the `S`-derivative of the covariance, drift back
with the new momenta (bb.cu:368-456; Octopus `src/elements/strong_beam.jl:905-1110`). BBSCL's
slices are equal-charge Gaussian slabs with centroid positions from the inverse normal
(bslices.cu:71-105); Octopus's `:equal_area` rule is the same construction, beside six others.
BBSCL carries the crossing angle by a per-particle Lorentz boost inside the map (`crsbst`,
bb.cu:241-284, Hirata's boost in the `h = E - p_s` form) and tilts the strong beam through the
boosted 6 x 6 envelope, from which a conditional 5 x 5 slice envelope and a centroid slope
`bcen_fac` are derived at setup (lin_map.cu:359-418); Octopus boosts with separate
`LorentzBoostSpec`/`RevLorentzBoostSpec` elements and conditions its slices on the 6 x 6
covariance in the same way. The kick coefficient is `Cp = 2 N r_e/gamma_weak` with no charge
sign and no mass (bb.cu:887): attractive e+e- is assumed. For a proton weak beam the comparison
hands BBSCL `N m_e/m_p` so that `2 (N m_e/m_p) r_e = 2 N r_p`.

The complex error function is where the two differ most. BBSCL evaluates w(z) from a table of
8th-order Taylor expansions on a 0.1 grid, 61 x 51 nodes, 9 complex coefficients per node,
Horner in the offset, 448 kB of doubles in global memory, with a rational asymptotic form
outside `x <= 6, y <= 5` (errf.cu:132-217). Octopus's CUDA kernel uses a 32-coefficient
Weideman rational approximation with a continued-fraction branch for large arguments
(`src/math/SpecialMath.jl:16-147`) and dedicated round and near-round series. BBSCL has no
round-beam branch in `bb_map`: `sqrt(sigma_x^2 - sigma_y^2)` is NaN for a vertical-dominated
slice and infinite for a round one (bb.cu:395-396; a round map `RBBMapping` exists but is never
called). One sign difference inside BBSCL was found by reading: the horizontal term of the
weak-strong energy kick (`Unx`, bb.cu:437-444) has the opposite sign from the strong-strong
implementation of the same term (`dux`, bbgauss3d.cu:157-174) and from the code's own
round-beam formula; at most one of the two is right.

### 3.4 Strong-strong beam-beam

**Orchestration.** BBSCL's collider runs the collision at the start of every turn for all
`nslice^2` slice pairs in a collision-time order sorted once at initialisation from the design
bunch lengths (bbcol3d.cu:510-567), strictly sequentially on the default stream. Octopus orders
pairs by collision time too but groups the non-conflicting ones into dependency wavefronts
(`collision_pair_batches`, `src/tasks/strongstrong/slicing.jl:771-820`; 29 batches for
15 x 15) and solves a batch's fields in one batched cuFFT, bit-identical to the sequential
order.

**Slicing.** BBSCL physically permutes both beams every turn with `sortsl2b<<<1,256>>>`: one
block, one thread per slice, each thread scanning all particles twice (bbcol3d.cu:1220-1394),
an O(nslice x N) serial pass that forces `NMacroP % 256 == 0` (collider.cu:36-44); the
boundaries are the inverse-normal quantiles of the measured `sigma_z` about the measured
centroid, as in Octopus's `:normal_quantile` rule. Octopus builds per-slice index lists (CPU:
two-pass count and fill; CUDA: a mask and scan per slice) and never moves a particle.

**Gaussian solver.** BBSCL measures ten float moments per slice by shared-memory reduction and
float atomics (`BeamSizeSlice`, bbcol3d.cu:1399-1444), subtracting the crossing-angle tilt
before squaring; the slice charge is the measured macro-particle count, and a slice with fewer
than 10 particles or a non-positive variance gives no kick, silently (bbgauss3d.cu:49-52, 68).
Its round-beam branch (`|1 - sigma_x^2/sigma_y^2| < 1e-3`) computes the round kick but the
kick, the beamstrahlung and the back-drift sit inside the flat-beam `else` (bbgauss3d.cu:88-189),
so a round slice leaves its particles half-drifted. Octopus's soft-Gaussian solver reduces
anchored-shifted Float64 sums on a fixed 64-chunk grid, applies the kick with the covariance
transported to each particle's own collision point, and has a round branch.

**PIC solver.** The table below is the heart of the implementation comparison.

| PIC aspect | BBSCL (`bbpic.cu`, `bbcol3d.cu`) | Octopus (`src/tasks/strongstrong/pic_*.jl`) |
|---|---|---|
| mesh | `ngx x ngy` with `dx, dy` fixed in metres from the input; the mesh centre follows each colliding slice (`xemc/xpmc`); with `nanobeam` a set of longitudinal planes with `dy` scaled by the hourglass and the inter-mesh offset folded into the Green table (bbcol3d.cu:467-507) | per directed slice pair, extents from the drifted particle extrema (or a sigma rule), two equal grids with different origins, optional quantisation; `:slice_pair`, `:source_slice`, `:node` programs |
| out-of-mesh particles | silently dropped from the density and given no kick (bbpic.cu:170, 450) | never, by construction (`:extrema`); counted and warned under `:sigma` |
| deposition | 4-point CIC, float `atomicAdd`, 8 atomics per particle per pair (two faces) | CIC or TSC, Float64 atomics on CUDA, per-thread grids on CPU |
| Green function | cell-averaged `ln r` from the closed-form double antiderivative, built ONCE per mesh plane on the host, float table, R2C-transformed (bbpic.cu:26-125) | cell-averaged `ln r`, rebuilt whenever the adaptive grid changes, cached per `(i, j, direction)` with 25% growth |
| FFT | two single-precision 2D plans (`cufftPlan2d(2ngx, 2ngy)` R2C and C2R), 8 executions per pair, not batched | Float64 complex-to-complex, one batched transform over the `(2nx, 2ny, 4 x batch)` stack per wavefront |
| field and kick | bicubic coefficients per cell from finite differences (Numerical Recipes `bcucof`), coefficients interpolated linearly in `s` between the target slice's two faces, analytic bicubic derivatives; `delta += cnp (phi_b - phi_f)/(2 dsbf)` (bbpic.cu:309-396, 402-530) | second- or fourth-order finite-difference field on the grid, CIC/TSC interpolation to particles, linear (or quadratic) interpolation between the two boundary planes; `pz += 2 kbb (phi_L - phi_R)/(rb - lb)` |
| synchro-beam map | Hirata drift and the potential-difference longitudinal kick, both present | the same, plus `:chromatic` and `:exact` virtual drifts in the Gaussian solver |
| launches and syncs | per pair: ~14 kernels, 8 FFTs, 5 memsets, 6 `cudaDeviceSynchronize`; for 15 slices 1800 FFTs and 1350 host syncs per turn | per wavefront: bounds kernels with one small D2H, deposits, one FFT, Green multiply, one inverse FFT, one field kernel, one kick kernel per pair, one sync per batch (29 per turn) |
| luminosity | both slices CIC-deposited on one common `ngx x ngy` grid per pair, shared-memory reduction, one float atomic per block; output in cm^-2 per particle pair | a separate deposit of both slices at the centroid plane on a `(nx+1) x (ny+1)` mesh per pair, device sum; output in m^-2 per crossing |
| precision | float grids, float FFT, float tables, float kick intermediates; double coordinates | Float64 throughout |
| kick scale | `2 N r_e/gamma` for both beams, electron radius and no charge sign (bbcol3d.cu:284-285) | `q1 q2 r0_1 N2 mc2_1/E0_1`, species-aware |

### 3.5 Infrastructure

BBSCL's parser (element.cu:1300-1408) reads one statement per `;`, requires a space after the
type keyword, treats `//` and `#` lines as comments only if they end with `;` (an unterminated
comment swallows the next statement), and fills positional slots; the grammar had to be
reconstructed from the parser because the repository holds no input file. The strong-strong
kick coefficient of the "positron" ring uses the electron radius (bbcol3d.cu:285), so an e-p
run is only correct after rescaling the electron bunch population by `m_e/m_p` in the electron
ring's `Bunches` line (the only consumer of that number in a strong-strong run). Its outputs
are text files per ring (`.f10` moments and luminosity once per turn, `.f15` particle dumps);
the stdout banner (`TURN ... Time(ms) ...`) describes a format no longer printed. Random seeds
are compiled in; `jobid` only renames files. The build uses `-w -dc` and no `-O`/`-arch`; the
code compiles unchanged with CUDA 12.6 and gcc 11 once a toolkit is present.

Octopus's corresponding machinery is the spec/metadata layer with `element_help`, the
configuration report, receipts, the run artifact, the counter RNG and the test suite; none of it
has a BBSCL counterpart, and the comparison relied on it (the Octopus drivers refuse unread
options and report their resolved policy).

### 3.6 Defects and hazards noticed in BBSCL while reading

Recorded so the owner can pass them on; none was fixed here.

1. `sodd_map` tests the enum constant `DISFRIN` instead of the parameter: the sextupole
   entrance fringe never runs while the exit fringe does (sext.cu:218, 226-229).
2. Bend precomputation ignores `AE1/AE2` for finite-angle bends without `K1` (bend.cu:82-83,
   98-102) although `mbcore_KO` assumes `psi = E*ANGLE + AE`.
3. Weak-strong `bb_map` has no round or vertical-dominated branch (bb.cu:395-396); the
   horizontal term of its energy kick has the opposite sign from the strong-strong twin
   (bb.cu:437-444 against bbgauss3d.cu:157-174).
4. The Gaussian solver's round-beam branch leaves particles half-drifted and unkicked
   (bbgauss3d.cu:88-189); slices below 10 particles or with a non-positive variance are
   silently skipped (bbgauss3d.cu:49-52, 68).
5. `BBGAF` (12) is accepted and performs no collision (element.cu:1535; bbcol3d.cu:1056-1058).
6. The kick coefficient uses `r_e` for both beams and no charge sign (bbcol3d.cu:284-285;
   bb.cu:887): correct for e+e- only.
7. PIC particles outside the fixed mesh are dropped from the density and receive no kick with
   no counter or warning (bbpic.cu:170, 196, 450); the collision order is frozen at
   initialisation while the slice positions move each turn (bbcol3d.cu:561 against 1327).
8. The one-block counting sort requires `NMacroP % 256 == 0` and never resets its tag array
   (bbcol3d.cu:1316-1324; the `cudaMemset` at 1028 is commented out).
9. Float atomics in deposition, moments, luminosity and bunch length; float `sqrt(<z^2> - <z>^2)`;
   float kick coefficients (bbss.h; bbcol3d.cu:1183-1200).
10. `TrackBeamGPU` accumulates an uninitialised `lumi` at IP elements in strong-strong mode
    (element.cu:355, 412-417); `TrackSCBeamGPU`'s IP test is inverted (element.cu:573-576).
11. The cavity map writes derived coefficients into the shared parameter block from every
    thread (cav.cu:436, 439); the cavity's half drifts take P0-normalised momenta without the
    `1/(1+delta)` wrapper every other map uses (cav.cu:381, 459).
12. `IPOrbitShift` is launched with the positron grid size for the electron beam
    (bbcol3d.cu:674, 680); `Apert` allocates 10 reals and reports 12 (drift.cu:110-138);
    `pr.mk` lacks `section_map.o`; `Gtab_ipm20.dat`, `tmp`, `tmp.dat`, `tmp2.dat` are written
    in the working directory on every run (bbpic.cu:66; element.cu:1706; bbgauss3d.cu:422-424).
13. The parameter printout labels `params[10]` "type" and `params[11]` "nanobeam" where the
    code reads `nanobeam = params[10]` (element.cu:1283-1284; bbcol3d.cu:173).

## 4. Performance comparison

### 4.1 The cases

All three cases use the EIC-like parameters of `examples/strong_strong_tracking.jl` and
`examples/weak_strong_tracking.jl` reduced to what both codes can express identically: no crab
cavities (BBSCL has none), no chromaticity kick (BBSCL's is a CPU-only no-op on the GPU), the
crossing angle as Hirata boosts (half angle 12.5 mrad), one-turn linear maps with the examples'
tunes, and in the strong-strong case radiation damping and excitation on the electron ring
(BBSCL `Radiation`, Octopus `LumpedRadSpec`, the same damping times and equilibrium sizes).
Beams are Gaussian; BBSCL's initial Gaussian is untruncated, Octopus's is cut at 5 sigma. The
BBSCL inputs are generated by `gen_bbscl_S.py`, `gen_bbscl_W.py` and `gen_bbscl_L.py`; the
Octopus side by `octopus_strong_strong_bbscl.jl`, `octopus_weak_strong_bbscl.jl` and
`octopus_lattice_bbscl.jl`; the tables by `summarize.py`.

- **S**: strong-strong, 2,560,000 electron and 1,024,000 proton macroparticles, 15 slices per
  beam at the normal-quantile boundaries of the measured bunch length, 200 turns. PIC in both
  codes at 128 x 128 (BBSCL: `dx = 1.0e-5 m`, `dy = 9.0e-7 m`, `nanobeam = 1` giving 29
  longitudinal mesh planes; Octopus: adaptive `:extrema` meshes, CIC, integrated Green,
  slice-pair cache), and soft-Gaussian in both (BBSCL `BBGAU`, Octopus `GaussianPoissonSolver`).
  BBSCL's electron bunch population is handed over as `N_e m_e/m_p` so that its `2 N r_e`
  coefficient gives the proton beam the right kick (section 3.5).
- **W**: weak-strong, 1,024,000 protons against a rigid 7-slice Gaussian electron beam
  (BBSCL's `IP` element in the single-ring program `prmb`; Octopus `GaussianStrongBeamSpec`
  with `:equal_area` slices and the `:hirata` virtual drift), 200 turns, no radiation. The
  strong-beam population is scaled by `m_e/m_p` for the same reason.
- **L**: element-by-element tracking of an 8-cell FODO ring (81 elements: thick quadrupoles
  of 0.5 m with `K1 L = 0.18`, sextupoles, sector bends of 22.5 degrees, drifts, one thin RF
  cavity at h = 320, 2 MV), 275 GeV protons, 1,048,576 macroparticles, 200 turns. Both codes
  start from the same Twiss numbers (`beta_x = 16.356 m, alpha_x = -1.490, beta_y = 5.130 m,
  alpha_y = 0.501` at the QF entrance, from Octopus's Twiss analysis of one cell closed on
  itself with the default integrator), so the beam is only approximately matched, identically
  in both codes; emittances 1e-8 m, `sigma_delta = 1e-7` so that the dispersion neither code
  puts into its initial distribution is irrelevant; centroid offsets `(1e-4, 0, 1e-4, 0, 1e-3,
  0)` so that the tunes can be read off the centroid motion in a 1024-turn run at 20,480
  particles. A 16-cell ring (161 elements) was the first choice and was abandoned when
  `ptxas` had spent seven minutes on the fused kernel (section 6). Fringe fields off on quadrupoles and sextupoles in both
  codes (BBSCL `DISFRIN = 1`, Octopus `fringe = :none`); the hard-edge dipole fringe on in both
  (BBSCL applies it unconditionally, Octopus `bend_fringe = true`). Octopus runs its default
  integrator (`nst = 1`, Strang order 2) and, as a second arm, `nst = 4`, order 4.

### 4.2 Results

#### Case S, PIC strong-strong, 2,560,000 e / 1,024,000 p, 15 slices, 200 turns

| quantity | BBSCL | Octopus |
|---|---|---|
| seconds per turn | 3.576 (gpu_time 715.2 s / 200; wall 725 s) | 0.2672 mean, 0.2674 median, sd 0.0017 (turns 21-200) |
| luminosity per crossing, turn 1 [m^-2] | 1.9192e+29 | 1.9175e+29 |
| luminosity, mean of turns 21-200 [m^-2] | 1.9783e+29 (sd 1.52e+27) | 1.9779e+29 (sd 1.51e+27) |
| luminosity, last turn [m^-2] | 2.0092e+29 | 2.0036e+29 |
| electron sigma_x, sigma_y, sigma_z at turn 1 [m] | 1.0518e-04, 9.0084e-06, 6.9944e-03 | see moments table |
| electron sigma_x, sigma_y, sigma_z at turn 200 [m] | 1.0679e-04, 9.3081e-06, 6.9997e-03 | see moments table |
| proton sigma_x, sigma_y, sigma_z at turn 200 [m] | 9.5169e-05, 8.5008e-06, 5.9967e-02 | see moments table |

Octopus PIC rms sizes from the moment observer (a separate run with the observer every turn), beside BBSCL's f10 moments:

| turn | Octopus e sigma_x | e sigma_y | e sigma_z | p sigma_x | p sigma_y | p sigma_z | BBSCL e sigma_x | e sigma_y | p sigma_y |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 1.0515e-04 | 9.0172e-06 | 7.0018e-03 | 9.5061e-05 | 8.4740e-06 | 6.0001e-02 | 1.0518e-04 | 9.0084e-06 | 8.4806e-06 |
| 50 | 1.0608e-04 | 9.3228e-06 | 7.0007e-03 | 9.5066e-05 | 8.5029e-06 | 6.0001e-02 | 1.0615e-04 | 9.3223e-06 | 8.5065e-06 |
| 100 | 1.0539e-04 | 9.3438e-06 | 6.9981e-03 | 9.5000e-05 | 8.5133e-06 | 6.0001e-02 | 1.0545e-04 | 9.3394e-06 | 8.5116e-06 |
| 150 | 1.0513e-04 | 9.3158e-06 | 6.9970e-03 | 9.5027e-05 | 8.5159e-06 | 6.0001e-02 | 1.0519e-04 | 9.3133e-06 | 8.5096e-06 |
| 199 | 1.0673e-04 | 9.3085e-06 | 7.0017e-03 | 9.5214e-05 | 8.4898e-06 | 6.0001e-02 | 1.0679e-04 | 9.3081e-06 | 8.5008e-06 |

#### Case S, Gaussian strong-strong, 2,560,000 e / 1,024,000 p, 15 slices, 200 turns

| quantity | BBSCL | Octopus |
|---|---|---|
| seconds per turn | 3.586 (gpu_time 717.2 s / 200; wall 727 s) | 0.1929 mean, 0.1929 median, sd 0.0008 (turns 21-200) |
| luminosity per crossing, turn 1 [m^-2] | 1.9192e+29 | 1.9183e+29 |
| luminosity, mean of turns 21-200 [m^-2] | 1.9784e+29 (sd 1.51e+27) | 1.9783e+29 (sd 1.48e+27) |
| luminosity, last turn [m^-2] | 2.0094e+29 | 2.0035e+29 |
| electron sigma_x, sigma_y, sigma_z at turn 1 [m] | 1.0519e-04, 9.0078e-06, 6.9944e-03 | see moments table |
| electron sigma_x, sigma_y, sigma_z at turn 200 [m] | 1.0681e-04, 9.3099e-06, 6.9998e-03 | see moments table |
| proton sigma_x, sigma_y, sigma_z at turn 200 [m] | 9.5169e-05, 8.5008e-06, 5.9967e-02 | see moments table |

#### Repeat (PIC, 60 turns, both arms adjacent): BBSCL 3.671 s/turn (gpu_time 220.3 s); Octopus 0.2998 s/turn (turns 11-60), sd 0.0037

#### Case W, weak-strong, 1,024,000 protons against a rigid 7-slice electron beam, half angle 12.5 mrad, 200 turns

| quantity | BBSCL (prmb, TrackGPU) | Octopus (TrackingTask) |
|---|---|---|
| seconds per turn | 0.0235 (gpu_time 4.70 s / 200; wall 5 s) | 0.03030 mean, 0.03030 median, sd 0.00005 (turns 21-200) |
| luminosity per crossing, turn 1 [m^-2] | 2.0360e+29 | 2.0394e+29 |
| luminosity, mean of turns 21-200 [m^-2] | 2.0685e+29 (sd 1.09e+27) | 2.0884e+29 (sd 1.49e+27) |
| proton sigma_x, sigma_y, sigma_z at turn 1 [m] | 9.4960e-05, 8.4681e-06, 5.9996e-02 | see moments table |
| proton sigma_x, sigma_y, sigma_z at turn 200 [m] | 9.5149e-05, 8.4945e-06, 5.9997e-02 | see moments table |

| turn | Octopus sigma_x | sigma_y | sigma_z | sigma_delta | BBSCL sigma_x | sigma_y | sigma_z |
|---|---|---|---|---|---|---|---|
| 0 | 9.5077e-05 | 8.4750e-06 | 5.9999e-02 | 6.6001e-04 | 9.4960e-05 | 8.4681e-06 | 5.9996e-02 |
| 50 | 9.5190e-05 | 8.5148e-06 | 5.9999e-02 | 6.6001e-04 | 9.5031e-05 | 8.5020e-06 | 5.9996e-02 |
| 100 | 9.5192e-05 | 8.5294e-06 | 6.0000e-02 | 6.6001e-04 | 9.5109e-05 | 8.5153e-06 | 5.9996e-02 |
| 150 | 9.5422e-05 | 8.5397e-06 | 6.0000e-02 | 6.6002e-04 | 9.5145e-05 | 8.5182e-06 | 5.9996e-02 |
| 199 | 9.5486e-05 | 8.5378e-06 | 6.0002e-02 | 6.6001e-04 | 9.5149e-05 | 8.4945e-06 | 5.9997e-02 |

#### L_200: BBSCL prmb (run.log) 0.1162 s/turn (gpu_time 23.23 s / 200 turns, wall 24 s)
#### L_200: BBSCL prmb (run_repeat.log) 0.1181 s/turn (gpu_time 23.61 s / 200 turns, wall 24 s)
#### L_200: Octopus octopus_L_200.tsv: 0.16942 s/turn mean (turns 21-200), median 0.16703, sd 0.02187; # octopus case L  N=1048576 turns=200 ncell=8 nst=1 order=2 backend=cuda seed=123456789 elements=81
#### L_200: Octopus octopus_L_200_nst4o4.tsv: 0.33308 s/turn mean (turns 21-200), median 0.33094, sd 0.01765; # octopus case L  N=1048576 turns=200 ncell=8 nst=4 order=4 backend=cuda seed=123456789 elements=81

#### L_gauge: BBSCL prmb (run.log) 0.0061 s/turn (gpu_time 0.12 s / 20 turns, wall 0 s)
#### L_gauge: Octopus octopus_L_gauge.tsv: 0.01574 s/turn mean (turns 6-20), median 0.00664, sd 0.03465; # octopus case L  N=20480 turns=20 ncell=8 nst=1 order=2 backend=cuda seed=123456789 elements=81

#### L_tunes: BBSCL prmb (run.log) 0.0032 s/turn (gpu_time 3.23 s / 1024 turns, wall 3 s)
#### L_tunes: Octopus octopus_L_tunes.tsv: 0.00690 s/turn mean (turns 21-1024), median 0.00606, sd 0.00421; # octopus case L  N=20480 turns=1024 ncell=8 nst=1 order=2 backend=cuda seed=123456789 elements=81
#### L_tunes: Octopus octopus_L_tunes_nst4o4.tsv: 0.01186 s/turn mean (turns 21-1024), median 0.01109, sd 0.00426; # octopus case L  N=20480 turns=1024 ncell=8 nst=4 order=4 backend=cuda seed=123456789 elements=81

```
bbscl: turns=1024  Qx=0.463593  Qy=0.165129  Qz=0.008169  <x> amplitude 2.134e-04  <y> 1.121e-04  <z> 1.041e-03
octopus: turns=1024  Qx=0.421166  Qy=0.113138  Qz=0.008046  <x> amplitude 2.144e-04  <y> 1.118e-04  <z> 1.046e-03
octopus: turns=1024  Qx=0.463600  Qy=0.165137  Qz=0.008169  <x> amplitude 2.102e-04  <y> 1.128e-04  <z> 1.040e-03
```

#### BBSCL strong-strong cost decomposition (20 turns each, production mesh)

| run | slices | macroparticles e / p | solver | s/turn | luminosity turn 1 [m^-2] |
|---|---|---|---|---|---|
| S_diag_gau_ns15_quarter | 15 | 640,000 / 256,000 | Gaussian | 0.800 | 1.9218e+29 |
| S_diag_gau_ns1_full | 1 | 2,560,000 / 1,024,000 | Gaussian | 3.826 | 1.9223e+29 |
| S_diag_pic_ns15_nonano | 15 | 2,560,000 / 1,024,000 | PIC, nanobeam=0, dy=1.8e-6 | 3.976 | nan |
| S_diag_pic_ns15_quarter | 15 | 640,000 / 256,000 | PIC | 0.818 | 1.9218e+29 |
| S_diag_pic_ns1_full | 1 | 2,560,000 / 1,024,000 | PIC | 3.867 | 1.9223e+29 |

### 4.3 Reading the numbers

**Strong-strong.** At the production point Octopus's PIC turn is 13.4 times faster than
BBSCL's and its soft-Gaussian turn 18.6 times faster, while the two codes agree on the
physics to the statistical noise of the case: the 200-turn mean luminosity differs by 0.02%
(PIC) and 0.005% (Gaussian), the vertical electron size grows from 9.0 to 9.3 um in both and
tracks turn by turn to better than 0.1%, and the proton sizes are unchanged in both. BBSCL's
PIC and Gaussian turns cost the same 3.58 s, which says the time is not in the Poisson solve;
the diagnostic runs of section 4.4 show that it is not in the per-pair machinery either (one
slice pair costs the same turn as 225) but in the one-block counting sort that runs once per
turn over every particle. The ratio therefore measures BBSCL as it ships rather than its
solvers, and section 4.4 says what the solvers would cost without the sort.

**Weak-strong.** BBSCL is 1.29 times faster per turn here. Its turn is one kernel: boost,
seven synchro-beam slices with the tabulated Faddeeva function, inverse boost and the 6 x 6
one-turn map, all inside `TrackBeamGPU`, followed by one moment kernel and a 4-byte copy.
Octopus's turn is several launches (the boost segment, the strong beam lifted into its own
kernel because its runtime struct is mutable, the reverse-boost and one-turn segment, a
luminosity reduction) plus the host-side plan and timing work of `execute!`. The physics
agrees to 0.2% in the luminosity of the first turn (2.036e29 against 2.039e29 m^-2) and the
two trends then separate slowly: 1.0% in the 200-turn mean luminosity, 0.5% in the proton
vertical size at turn 200. The difference was not isolated; the candidates are BBSCL's
weak-strong energy-kick sign (section 3.3), its untruncated initial Gaussian against Octopus's
5-sigma cut, and the slice-centroid treatment (BBSCL does not drift the strong slice centroid
to the collision point in the weak-strong map, bb.cu:381-384, while its strong-strong map
does).

**Lattice.** BBSCL tracks the 81-element ring at 0.116 s per turn for 1,048,576 particles (two runs,
0.1162 and 0.1181), Octopus at 0.169 s with its default integrator and 0.333 s with `nst = 4`,
order 4: 1.37, 2.0 and 3.9 ns per particle-element. The default Octopus run is the wrong one to
compare: its tunes are off by 0.04 in both planes (table below), so the like-for-like number is
the `nst = 4` arm, where BBSCL is 2.9 times faster with the same tunes to 1e-5. BBSCL's
quadrupole is SAD's exact matrix, one slice, with two `xsincos` evaluations and the kinematic
correction; Octopus's order-4 split is four exact drifts and three kicks per magnet, twice the
map evaluations of a Strang step. Both kernels are instruction-bound on this FP64-weak card
(1/64 rate), so the per-element instruction count is the whole story: an exact one-slice
quadrupole body (section 5, item 7) is what would close most of the gap. The longitudinal tune
agrees to six digits and the centroid amplitudes to a few per cent in all three planes; the
transverse beam was only approximately matched (identically in both codes), so the rms sizes
breathe and were not compared.

### 4.4 Where BBSCL's strong-strong time goes

Five 20-turn BBSCL runs at the production mesh, the table of which closes section 4.2
(`S_diag_*`): one slice pair instead of 225 at the full particle count costs 3.87 s/turn (PIC)
and 3.83 s (Gaussian), the same as the 15-slice production runs (3.58 to 3.95); a quarter of
the particles at 15 slices costs 0.82 s (PIC) and 0.80 s (Gaussian), 4.7 times less for 4
times fewer particles; and switching off the longitudinal mesh planes changes nothing (3.98 s).
So BBSCL's strong-strong turn costs about 1.0 us per macroparticle whatever the solver and
whatever the number of slice pairs, and the per-pair work (deposits, FFTs, kicks, syncs) is at
most a few tenths of a second of the 3.6 s. What scales with the particle count and not with
the pairs is the per-turn beam-wide work: `bunch_length`, the two lattice kernels, the moment
kernel, and `sortsl2b`. The first three are ordinary parallel kernels that this comparison
measured elsewhere at milliseconds for this particle count (the 81-element lattice arm tracks
1M particles through 81 elements in 0.116 s). `sortsl2b<<<1,256>>>` is one block in which
every thread loops over every particle twice (bbcol3d.cu:1273-1283, 1300-1312), one dependent
global load per iteration with no memory-level parallelism; at 400 to 600 ns per load, 3.58M
particles and two passes that is 3 to 4 s per turn, which is the measured cost to within the
uncertainty of the estimate. The profiler that would confirm the attribution (Nsight) was not
available on this machine; the three-way scaling evidence (slices, particles, solver) is what
the attribution rests on. Two consequences: the solver comparison of section 4.3 is a
comparison of BBSCL as it ships, not of its PIC algorithm, whose cost is hidden under the sort;
and a parallel counting sort (one histogram and scan, as thrust or cub provide) would make
BBSCL's strong-strong turn roughly ten times faster than measured here, after which the
per-pair design of section 3.4 (eight single-precision FFTs, six synchronisations and ~14
launches per pair, sequentially) would become the visible cost and the comparison with
Octopus's batched wavefront would be the interesting one. The `nanobeam = 0` run also shows the
fixed-mesh hazard of section 3.4: with `dy` widened to hold the hourglass, the first-turn
luminosity reads `nan` in `.f10` (an out-of-mesh or empty-cell path with no guard), where the
`nanobeam = 1` runs and Octopus agree to 0.1%.

## 5. What Octopus should borrow from BBSCL

Ranked by the evidence of this comparison; each item names what BBSCL does, what Octopus
does today, and what the measurement says.

1. **One kernel per turn for the weak-strong line.** BBSCL's whole turn is one launch and it
   beats Octopus by 29% on the production weak-strong case while agreeing on the first-turn
   luminosity to 0.2%. Octopus pays for the lift-out of the strong beam (a mutable runtime
   struct, `src/track/strong_beam_track.jl:207-208`) and for one launch per fused segment per
   turn. Making the strong beam's runtime isbits (its `last_luminosity` moved to a device
   buffer or a task slot) would let the boosts, the strong beam and the one-turn map fuse into
   one launch; keeping the luminosity as a per-particle buffer reduced once per turn is what
   BBSCL does with a float atomic and what Octopus already does with a device sum.
2. **A tabulated complex error function for the device.** BBSCL evaluates w(z) by Horner on 9
   stored complex Taylor coefficients of the nearest 0.1-grid node (448 kB in global memory,
   cached), with a rational asymptotic form outside `x <= 6, y <= 5` (errf.cu:132-217). Octopus's
   CUDA kernel runs a 32-coefficient rational approximation twice per slice plus series branches.
   The table is a candidate for the hot kick kernels of both the weak-strong element and the
   soft-Gaussian solver; its accuracy must be measured against `erfcx` before adoption, and the
   near-round and near-axis branches Octopus has (and BBSCL lacks) must stay.
3. **Species-aware kick coefficients and an explicit charge sign** are the Octopus side of
   this item: BBSCL's `2 N r_e/gamma` with no sign is the single largest obstacle to using it
   for e-p and a reminder that the kick coefficient belongs in the beam object, as Octopus's
   `kbb = q1 q2 r0 N mc2/E0` has it. Nothing to borrow; the comparison confirms the design.
4. **Bicubic field interpolation with C1 continuity.** BBSCL builds 16 bicubic coefficients
   per cell from finite differences and interpolates them linearly in `s` between the two
   faces (bbpic.cu:309-396, 489-504); the field is continuous with its first derivatives across
   cells. Octopus's CIC interpolation of a finite-difference field is piecewise linear. The
   PIC luminosity and emittance evolution of the two codes agreed within noise here, so the
   measurement does not show a benefit at 128 x 128 with 2.56M particles; the idea is worth a
   grid-convergence study as an interpolation option, not an immediate adoption.
5. **Hourglass-scaled vertical cell size per collision plane** (`dy_pm = max(dy, dy s/beta_y)`,
   bbcol3d.cu:493-495). Octopus's adaptive extents already resize per pair from the drifted
   particle extrema, so this is covered; the BBSCL form is the fixed-mesh equivalent.
6. **Beamstrahlung and crab waist** exist in BBSCL and not in Octopus: a single Bernoulli
   photon per particle per slice pair sampled from a tabulated cumulative K_5/3 integral
   (bbpic.cu:1181-1243) and the crab-waist Hamiltonian `H = x (c1 y^2 + 2 c2 y py + c3 py^2)/2`
   (bb.cu:292-311). Both are e+e- physics outside Octopus's current EIC focus; the beamstrahlung
   table-and-search scheme is the one to copy if an e+e- case arrives.
7. **An exact thick-quadrupole body.** BBSCL's quadrupole is SAD's exact-in-delta linear
   matrix with kinematic `exp(:dH:)` corrections, one slice for `|K1 L| < 0.2`
   (MAP_quad.cu:51-290). Octopus's default quadrupole is one Strang drift-kick-drift step, and
   on the lattice case that default misses the tunes by 0.04 (section 4.3) where `nst = 4`,
   order 4 agrees with BBSCL to 1e-5 at 1.8 times the cost. Two actions follow: the default
   `nst = 1, integrator_order = 2` is not a safe production default for thick quadrupoles and
   should at least be documented as a convergence parameter the user must check (the DBA ring
   example already uses `NST = 4, ORDER = 4`); and a `quad_model = :exact` body in the spirit of
   `bend_model = :exact` (the exact matrix in `(1 + delta)` with the kinematic correction) would
   give one-slice accuracy at one-slice cost, as BBSCL has.
8. **Reading the slice charge from the measured population** (bbgauss3d.cu:557-558) rather than
   from the slicing rule's weights makes the Gaussian solver robust to lost particles; Octopus's
   `weights = members/live` does the same already.

Not to borrow, by the measurements and the reading: the fixed input mesh with silent drops of
out-of-mesh particles; the one-block counting sort and the `NMacroP % 256` rule it forces; the
sequential pair loop with device synchronisations inside; single-precision grids, FFTs and
kick coefficients with float atomics; the compiled-in random seeds; the positional input
grammar; the per-turn reuse of one random block by every radiation element.

## 6. Observations on Octopus from the comparison

- The weak-strong turn is launch-bound at the production size: BBSCL's one-kernel design wins
  by 29% with the same physics. Item 1 above is the lead.
- The default thick-magnet integrator (`nst = 1`, Strang) misses the tunes of a 0.5 m, `K1 L =
  0.18` quadrupole lattice by 0.04 in both planes; `nst = 4`, order 4 reproduces BBSCL's exact
  quadrupole to 1e-5. Item 7 above is the lead; until then every lattice study must state its
  `nst` and show convergence.
- Compile time bounds the line length on CUDA: the 81-element line compiles in about 2.5
  minutes per process (most of it in `ptxas`), the 161-element line had not finished `ptxas`
  after seven minutes, and the Twiss analysis of the 641-element line died after fifteen.
  Every Octopus arm of case L paid the compile once per process; the timings exclude it.
- The exact dipole fringe takes an unguarded square root (`sqrt(1 - 2 B y)`,
  `src/elements/lattice_magnets.jl:853`): a four-cell test ring with 45-degree bends and a
  deliberately mismatched beam aborted the run with a `DomainError` instead of killing the
  particle, the class `_ps_or_dead` was introduced for (experiences.md, "An unphysical particle
  is a dead particle, not an exception"). Reproduction: the lattice driver with `OCT_NCELL=4` and
  a guessed optics file (`beta_x = 30, alpha = 0, beta_y = 10, beta_z = 20`).
- The compile-time unrolling that makes short beam-beam lines fast is a ceiling for long
  element-by-element lattices (previous bullet); the cell-as-sub-line route (`BeamLine` kept
  whole) was not tested here.
- `ThinRFCavitySpec(harmon=...)` cannot be analysed outside a task because its frequency
  resolves against the task line's arc length; the analysis needs the frequency form. By
  design, but it costs a user one round trip.

## 7. Caveats and what was not verified

- BBSCL was built with `-O3 -arch=sm_89`; its own Makefile passes neither. Device code is
  optimised by `nvcc` regardless, so the flags change the host loops only; the comparison was
  not repeated with the Makefile's bare flags.
- BBSCL has no per-turn clock, so its per-turn number is the whole turn loop divided by the
  turn count, first turns included; Octopus's number excludes a warm-up window. For the 200-turn
  arms the first turns are at most a few per cent of either total (BBSCL's 20-turn gauge gave
  3.95 s/turn against 3.58 over 200; Octopus's 0.319 against 0.267), and the direction of the
  bias favours BBSCL in no case.
- BBSCL's `collider` always runs the strong-strong collision at the start of the turn and its
  weak-strong IP exists only in the single-ring program; the weak-strong arm therefore ran a
  different executable (`prmb`) from the strong-strong arms (`collider`). Both come from the
  same source tree and share `TrackBeamGPU`.
- The e-p kick scaling in BBSCL relies on `eBeam->NParticle` having no other consumer in a
  strong-strong run without wakes or space charge, read from the source; the first-turn
  luminosity agreement (0.1%) is the measurement that the scaling did what it should.
- Octopus's weak-strong arm carried no radiation element and no chromaticity, unlike the
  production weak-strong case of `history/production_benchmark_2026_09_06.md` (0.038 s/turn
  with crabs, chromaticity, excitation and an every-turn moment observer), so the 0.0303 s/turn
  here is not that benchmark's number.
- Not compared: BBSCL's space charge, wakes, beamstrahlung, crab waist, multi-bunch, injection
  and f15 restart; Octopus's spectral and Gaussian-PIC solvers, MPI, Float32 lines; the CPU paths
  of either code. The energy-kick sign question inside BBSCL (section 3.3) was found by reading
  and not settled numerically here.
- The fast lane ran green on the final tree of this record (2026-11-22, `lane=fast`,
  `--threads=4`, CUDA active: 449 testsets passed, the 17 heavyweight sections the lane skips
  named in its banner, 40 minutes of wall time). It is the development checkpoint, not the
  finish line: the study adds files under `validation/` and one document, so the full gate is
  owed before the push that carries it (AGENTS.md, Verification Matrix, "validation, study, or
  benchmark").

## 8. Reproduction

Everything lives under `validation/bbscl_comparison/`:

- `octopus_strong_strong_bbscl.jl`, `octopus_weak_strong_bbscl.jl`, `octopus_lattice_bbscl.jl`:
  the Octopus arms, configured by `OCT_*` environment variables (defaults are the production
  points; `OCT_GPU=0` runs them on CPU threads, e.g. `OCT_N=20480 OCT_TURNS=10`).
- `gen_bbscl_S.py`, `gen_bbscl_W.py`, `gen_bbscl_L.py`: write the BBSCL input files from the same
  physics constants; the committed `inputs/` directory holds the generated production inputs.
- `lattice_optics.txt`: the one-cell Twiss analysis (`OCT_MODE=optics OCT_NCELL=1`) the lattice
  arms read; `tunes.py`: fractional tunes from either code's centroid series.
- `run_production.sh`, `run_lattice.sh`, `run_diag.sh`: the sequential chains that produced
  `results/`; `summarize.py` rebuilds the tables of section 4.2 from `results/`.
- Building BBSCL: copy its source tree (no file of it is modified), then
  `make -j16 LD=<nvcc> COMPFLAGS="-w -dc -O3 -arch=sm_89 -ccbin g++ -Xcompiler -O3"
  LDFLAGS="-arch=sm_89 -ccbin g++ -L<cuda lib> -Xlinker -rpath=<cuda lib> -lcurand -lcufft
  -lcusolver" collider`, and the same with `-f pr.mk ... prmb` followed by a manual link that
  adds `section_map.o` (missing from `pr.mk`). `collider_test bbscl_S` reads `bbscl_S_e.in` and
  `bbscl_S_p.in`; `prmb_test bbscl_W` reads `bbscl_W.in`; outputs land in the working directory.

## 9. Addendum (2026-11-22, later the same day): the element-by-element difference, measured per element type

Asked why BBSCL's element-by-element turn is faster, the attribution in section 4.3 ("Lattice":
the integrator order and the per-element instruction count of the exact quadrupole) was tested
rather than repeated. Two things in sections 4.2 and 4.3 are wrong and are corrected here; the
frozen sections above are left as written. Scripts under `validation/bbscl_comparison/eltype/`,
raw outputs under `validation/bbscl_comparison/results/eltype/` (section 9.7).

### 9.1 BBSCL's `gpu_time` contains an end-of-run constant

The `cudaEvent` pair of `TrackGPU` (element.cu) is closed after the turn loop, after the 48 MB
device-to-host copy of the beam and after `PrintPBeam`, which writes the whole beam as text to
`<base>.f15` (146.8 MB for 1,048,576 particles). Dividing `gpu_time` by the turn count, as
sections 4.2 and 4.3 do, therefore charges that dump to the turns. Measured by running the same
input at two turn counts (the slope is the per-turn cost, the intercept the constant):

| input | 200 turns [ms] | 400 turns [ms] | per turn [ms] | constant [ms] |
|---|---|---|---|---|
| one-turn map only (`Ph_rot`), 1,048,576 p | 2725.4 | 2334.2 | below the run-to-run noise of the dump | 2300 to 3100 |
| case L (`bbscl_L.in`), 1,048,576 p | 23549.5 | 44575.5 | 105.13 | 2523 |
| case W (`bbscl_W.in`), 1,024,000 p | 4705.1 | 6956.2 | 11.26 | 2454 |

Corrected BBSCL rows of section 4.2: case L 0.105 s/turn (recorded 0.1162 and 0.1181), case W
0.0113 s/turn (recorded 0.0235); case S is unchanged to three digits (2.5 s in 715 s). Corrected
ratios: weak-strong, BBSCL 2.7 times faster per turn (recorded 1.29); lattice at Octopus's default
`nst = 1`, BBSCL 1.61 times faster (recorded 1.46); lattice at `nst = 4`, order 4, BBSCL 3.17
times faster (recorded 2.9); strong-strong, Octopus 13.3 times (PIC) and 18.5 times (Gaussian)
faster (recorded 13.4 and 18.6). Per particle-element in case L: BBSCL 1.24 ns, not 1.37. The
section 7 caveat that the first-turn bias "favours BBSCL in no case" stands; this constant is a
different thing and favoured Octopus in every row.

### 9.2 Cost per element type

Each arm is the one-turn linear map (`Linear6DSpec` in Octopus, `Ph_rot` in BBSCL, the same
alpha, beta and tunes, chosen per kind so that the ring is linearly stable) plus 16 copies of one
element kind at the case L literals (32 for drifts), 1,048,576 particles, the map-only arm
subtracted, Octopus the median of turns 11-60 with `turn_timings`, BBSCL 200 turns of `gpu_time`
with the map-only arm's total subtracted (which removes the constant of 9.1; its 0.4 s spread
between runs is 0.06 ns per element here). Nanoseconds per particle-element, RTX 4500 Ada:

| element (count per arm) | BBSCL | Octopus, `nst = 1`, order 2 | Octopus, `nst = 4`, order 4 |
|---|---|---|---|
| drift (32) | 0.25 | 0.18 | n/a (no splitting) |
| quadrupole, 0.5 m, k1 = +-0.36 (16) | 2.04 (exact matrix, one slice) | 2.37 | 7.02 |
| sextupole, 0.2 m (16) | 1.20 (`sodd_thin`, 4 drifts and 3 kicks) | 2.42 | 7.54 |
| sector bend, 3 m, 22.5 deg (16) | 2.49 (hard-edge fringe built in) | 4.74 with `bend_fringe = true` (the default for a bend); 2.83 with it off | same (no splitting) |
| thin quadrupole kick (16) | n/a | 0.048 | |
| drift, thin quadrupole, drift (16) | n/a | 0.41 | |

The drift cost is flat in the line length (8, 32, 128 drifts: BBSCL 0.22, 0.25, 0.27; Octopus
0.16, 0.18, 0.18 ns), so neither code pays for code size at this scale. Summing the per-kind
costs with the case L multiplicities reproduces the full-turn measurements: Octopus 166 ms against
169.4 measured at `nst = 1` (2%), 330 against 333 at `nst = 4` order 4 (1%); BBSCL 104.7 against
105.1 (0.4%). The decomposition is therefore the full story of case L. Beam sizes stayed
bounded in every arm of both codes (the arms were read at different turns, 60 and 200, with a
mismatch oscillation on both, so the sizes were not compared beyond that; the map-only arm
agrees to 0.01%).

### 9.3 Where the 64 ms per turn of case L go

Octopus minus BBSCL per turn at `nst = 1`: bends +37.9 ms (of which the two hard-edge dipole
fringes 32 ms), sextupoles +20.3 ms, quadrupoles +5.6 ms, drifts -2.5 ms; the RF cavity and the
per-turn floor (Octopus 0.32 ms for the launch, the gather and scatter and the timing; BBSCL's
below noise) do not register. Three causes, in order of size:

1. **The hard-edge dipole fringe model.** Octopus's `_fringe_dipole_exact` is PTC's exact
   hard-edge map: per face an `atan`, a `cos^2`, a `tan`, a `sqrt` and about eight divisions,
   roughly 300 FP64 instructions, 1.9 ns per bend for the two faces, FP64-throughput-bound.
   BBSCL's `mbcore_KO` applies SAD's hard-edge terms (`fa`, `f`, `ff`: a polynomial in y with
   one `sqrt(1/(1 - px^2))` per face, some twenty FMAs). Octopus's exact body alone (2.83 ns)
   costs about what BBSCL's whole bend does (2.49). This is a physics-model difference (what
   Octopus promises is PTC's map), not an inefficiency; whether a cheaper hard-edge option is
   wanted is a physics decision for the lattice guide.
2. **A fixed overhead on every thick multipole magnet, about 2.0 ns, that is not arithmetic.**
   A Strang quadrupole at `nst = 1` costs 2.37 ns, the same step written out as `DriftSpec`,
   `ThinQuadrupoleSpec`, `DriftSpec` costs 0.41 ns, and `nst = 2` adds only 0.36 ns per extra
   step. Variants of `track_particle(::Symplectic6DMap, ::LatticeMagnet)` for the order-2 path,
   swapped in by `@eval` before the kernel compiled (`probe_strang.jl`), on the 16-quadrupole
   arm: as written 2.37 ns; without the kick 2.34; with the `nst` loop kept but `_lattice_drift`
   called directly in place of `_body_step` 0.40 (bit-identical rms to the original); with
   `_body_step` kept but the runtime loop removed (one step) 0.38; loop, direct drift, no kick
   0.22. The cost is the pairing of the runtime-trip-count `for _ in 1:elem.nst` loop with the
   untaken `_lattice_bend` arm of `_body_step` inside its body
   (`src/elements/lattice_magnets.jl`, `_body_step` and the Strang/Forest-Ruth loops of
   `track_particle`): each static loop body compiles to 3508 SASS instructions (1505 FP64-class,
   60 divisions, 14 trig slow-path calls, 122 convergence barriers) of which the drift arm is
   about 70, and the element pays once per pass, not per iteration. It is not occupancy: capping
   the kernel at 128 registers (16 resident warps per SM instead of 8) gave 40.20 against 40.12 ms
   per turn. Applied to the whole case L line through the same `@eval` (`run_probe_lattice.sh`),
   the direct-drift variant runs 0.100 s/turn at `nst = 1` (median of turns 11-100; 0.167 as
   written, BBSCL 0.105) and 0.193 s/turn at `nst = 4`, order 4 (0.331 as written), so at
   matched accuracy BBSCL's lead would be 1.84 times instead of 3.17; the variant's kernel also
   compiled in about 100 s where the original order-4 kernel took about 340 s. The physics
   equivalence of the variant is the bit-identical rms of the 16-quadrupole arm; the case L
   runs were 100 turns against the record's 200, so their final centroids were not compared.
   The cheapest fix is to decide `b0 == 0` at compile time, as `curved` already is (a type
   parameter, or a straight-multipole body method without the bend arm); a `docs/todo.md` row
   carries it.
3. **The integrator at matched accuracy.** With the overhead of item 2 removed, a `nst = 4`
   order-4 quadrupole is still 16 exact drifts and 12 kicks, about 3.4 ns of arithmetic
   (16 x 0.18 + 12 x 0.05), against BBSCL's one-slice exact matrix at 2.04 ns; the exact
   thick-quadrupole body of section 5 item 7 remains the borrow for the accurate setting, and
   at Octopus's default setting the same body would also remove the 0.04 tune error of section
   4.3 at no cost.

### 9.4 What was ruled out, with the measurement

- Occupancy and registers. After device linking BBSCL's `TrackBeamGPU` uses 241 registers and an
  18,096-byte stack per thread (`cuobjdump -res-usage`; the maps are separate-translation-unit
  calls with the particle in local memory), so it runs one 256-thread block per SM, 8 resident
  warps of 48. Octopus's 81-element kernel uses 170 registers and a 13,008-byte stack at `nst = 1` and 206
  registers at `nst = 4`, order 4 (ptxas on the dumped modules), also one block per SM. The per-file `ptxas -v` of element.cu alone reports
  40 registers because it does not see the callees; that number is not the kernel's.
- Launch structure, memory layout, lost-particle early exit, i-cache and code size: the
  Octopus per-turn floor is 0.32 ms (0.2% of the turn); 96 MB of particle traffic per turn is
  0.2 ms at the card's bandwidth; no particle was lost in any arm; the per-drift cost is flat
  from 8 to 128 drifts although the 81-element kernel is 362,276 SASS instructions (5.8 MB,
  151,073 FP64-class) at `nst = 1` and 495,332 at `nst = 4`, order 4, compiled by ptxas in 3 to
  11 minutes.
- BBSCL's own economies. Its drift and quadrupole avoid `sqrt` for small arguments by series
  (`pxy2dpz`, `sqrt1`: three terms below 8e-6), and its particle lives in local memory through
  ABI calls; the net is a drift 1.4 times slower than Octopus's exact drift with `sqrt`. Its
  turn also runs `BeamSizeMonitorGPU` and a synchronising 4-byte copy every turn.

### 9.5 Corrections to the text above

- Section 4.3, "Lattice": the integrator order is not "the whole story". At `nst = 1` the
  gap is the fringe model (half) and the thick-multipole overhead (a third); at `nst = 4` the
  integrator and the overhead together. The per-element numbers "1.37, 2.0 and 3.9 ns" become
  1.24, 2.0 and 3.9 ns.
- Section 4.3, "Weak-strong": BBSCL is 2.7 times faster, not 1.29; section 5 item 1 (fuse the
  weak-strong turn) gains weight accordingly.
- Section 7, second caveat: "BBSCL has no per-turn clock" is true and incomplete; its clock
  also contains the final beam dump (9.1).
- Section 3.5: the launch-site reading "one persistent kernel per beam per turn" stands, but
  the turn also launches `BeamSizeMonitorGPU` and copies the lost count back every turn.

### 9.6 Method notes

A foreign code's clock is read as a slope: the same input at two run lengths, never a total
divided by a turn count. A per-element decomposition (one kind per arm against a baseline,
summed and checked against the full turn to 2%) found the cost in a branch the physics never
takes, where reading the code had produced a plausible and wrong attribution (section 4.3). The
`@eval` variant probe of the memory note on kernel shapes (redefine the Octopus method before
the kernel compiles, compare the physics bit for bit) settled the cause in five runs of ninety
seconds.

### 9.7 Reproduction

`validation/bbscl_comparison/eltype/`: `octopus_eltype.jl` (`OCT_KIND`, `OCT_COUNT`, `OCT_NST`,
`OCT_ORDER`, `OCT_BEND_FRINGE`, `OCT_MAXREGS`, `OCT_DUMP`) and `gen_bbscl_T.py` (`--kind`,
`--count`) build the per-kind arms with the shared optics table; `run_eltype.sh` is the chain
that produced `results/eltype/runs/` (including the two-turn-count arms of 9.1);
`run_micro.sh`, `run_micro2.sh`, `run_micro3.sh` the register-cap, explicit-split and `nst`
probes; `probe_strang.jl` with `run_probe.sh` and `run_probe_lattice.sh` the variants of 9.3;
`dump_L81.jl` with `run_dump.sh`, `analyze_ptx.sh`, `split_ptx.py`, `sass_loops.py` and
`sass_blocks.py` the static counts (PTX dumped with `CUDA.@device_code_ptx io= dump_module=true`,
assembled with the CUDA.jl artifact `ptxas -v`, disassembled with `nvdisasm`);
`summarize_eltype.py` rebuilds the table of 9.2. BBSCL's static table is
`results/eltype/bbscl_opcode_table.txt` (`cuobjdump -sass` and `-res-usage` on `prmb_test`).
