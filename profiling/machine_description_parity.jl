#=
Run-time parity of the machine description: one case tracked through the bare
tuple spelling and through `Lattice` / `Machine`, timed interleaved.

Purpose. The machine description (docs/design/machine_description.md; stage 3
adds `Machine` and `StrongStrongTask(machine, :A, :B)`) is a layer of records
over the line layer, and the owner's requirement is that it costs nothing at
run time: a task given a lattice or a machine compiles the runtime the tuple
spelling compiles (`_element_tuple`, design D15) and its per-turn work is the
same. The suite pins the compiled runtimes and the tracked coordinates of the
spellings; this driver measures the per-turn wall time and heap allocation of
the spellings side by side and digests the final coordinates, so a regression
that reaches the per-turn path (a wrapper, a copy, a re-resolve per turn)
shows as a time or allocation difference between routes whose digests say
they track the same physics.

Fixed point. Two cases, each the shipped example's physics as literals:

- `ss`: the crab-crossing e-p strong-strong case of
  examples/strong_strong_tracking.jl (PIC solver, grid 128 x 128, 15 slices,
  the slice-pair Green cache, longitudinal kick, radiation on the electron
  beam), built as the two bare tuples (route `tuples`) and as
  `Machine("EIC"; lattices = (esr, hsr))` with
  `StrongStrongTask(machine, :ESR, :HSR)` (route `machine`).
- `ws`: the weak-strong case of examples/weak_strong_tracking.jl (the
  soft-Gaussian strong beam as one element, crab crossing, radiation
  excitation), built as the tuple (route `tuple`), as `Lattice("HSR"; line =
  BeamLine("HSR", ...))` (route `lattice`) and as `Machine(lattice)` (route
  `machine`).

Each case also runs a CONTROL: the tuple spelling built a second time, which
differs from the tuple route in nothing. Its difference from the tuple route
is the floor every other route is read against: zero on CPU threads and for
`ws` on CUDA (deterministic kernels), the device atomics' run-to-run noise for
`ss` on CUDA (the PIC deposit). The examples' observers and run artifact are
left out: the question is the per-turn cost of the description layer, and the
probes would add file I/O of their own. Every route builds its own elements
(its own solver), so no state is shared between routes. The beams are rebuilt
for every run from one global seed (123456789, Philox), so every run of every
route starts from the same coordinates bit for bit, and the routes' tasks see
the same sequence of executions (warm-up, then run 1, 2, ...), so a per-task
counter such as the radiation's turn index agrees across routes at every step
(it does NOT agree between consecutive runs of one route, which is why the
floor is a control route and not a repeat).

Measurement. Per route two warm-up executions (the compile: a task's first
execution and its first REPEATED execution take different paths, the cache
hits and the turn continuation, and the second compiles on the first repeat;
measured 2026-11-25, one warm-up left the first route's first timed run with
the repeat's compile in its time and bytes), then OCTOPUS_PARITY_REPEATS timed
runs interleaved across routes (route 1, route 2, ..., route 1, route 2, ...),
each of OCTOPUS_PARITY_TURNS turns, recording
the wall time per turn and the heap bytes `@allocated` per turn, the device
synchronised before and after on CUDA. One markdown table per case: route,
median s/turn, min s/turn, median allocated bytes/turn, the SHA-256 of the
final coordinates of each beam after the last run. Then one verdict line:

    PARITY case=<ss|ws> backend=<cpu|cuda|mpi> ranks=<n> routes=<names> runs=<r> digests_equal=<bool> max_abs_coordinate_diff=<x> control_equal=<bool> control_floor=<y> verdict=<PASS|FAIL|REPORT>

`digests_equal` is over every run of every described route against the tuple
route, not only the last; `max_abs_coordinate_diff` is the largest
|difference| of any final coordinate between a described route and the tuple
route over the runs; `control_equal` and `control_floor` are the same two
quantities for the control route. Verdict: PASS when the digests are equal;
REPORT when they differ while the control differs too (the atomics' noise:
judge the difference against the floor, `ss` on CUDA); FAIL, exit 1, when
they differ and the control does not (a difference where the control shows
none is not noise).

Run from the project root (CPU threads; one thread per core is the quiet
setting, and the full-size timing belongs on a machine with nothing else
running):

    julia --project=. --threads=16 profiling/machine_description_parity.jl
    OCTOPUS_USE_GPU=1 julia --project=. profiling/machine_description_parity.jl
    OCTOPUS_USE_MPI=1 OCTOPUS_CPU_THREADS=4 OCTOPUS_RANKS=2 mpiexec -n 2 julia --project=<env> profiling/machine_description_parity.jl

Every OCTOPUS_* name this script reads, defaults shown (the list is checked
against the read sites at load; the `let` block after the switch grammar):

    OCTOPUS_PARITY_CASE=ss          ss or ws
    OCTOPUS_PARITY_N_MACRO=20000    macro-particles per beam
    OCTOPUS_PARITY_TURNS=10         turns per timed run
    OCTOPUS_PARITY_REPEATS=5        timed runs per route
    OCTOPUS_USE_GPU=0               1: one CUDA device, an error if none is functional
    OCTOPUS_CUDA_DEVICE=<unset>     CUDA device index; read with OCTOPUS_USE_GPU=1 only, refused otherwise
    OCTOPUS_CPU_THREADS=auto        the CPU policy's worker count (per rank under MPI); refused with OCTOPUS_USE_GPU=1
    OCTOPUS_USE_MPI=0               1: MPI ranks x CPU threads under a launcher, Octopus loaded as a PACKAGE (below)
    OCTOPUS_RANKS=auto              read with OCTOPUS_USE_MPI=1 only (refused otherwise): an integer asserts the
                                    launcher's rank count through the policy, `auto` accepts whatever it started

The multi-process arm (OCTOPUS_USE_MPI=1) follows test/examples/
strong_strong_tracking.jl: the switch is read BEFORE Octopus loads because it
decides HOW Octopus loads. `MultiProcessExecutionPolicy` reaches a real
communicator only through the `OctopusMPIExt` package extension, which
attaches only to a PACKAGE, so the arm does `using Octopus, MPI` and refuses
by name an `include`d Main.Octopus or an unloaded extension (without it every
rank would be its own communicator of one and `mpiexec -n P` would run P whole
measurements). `<env>` is an environment holding Octopus, MPI and MPICH_jll as
packages (the suite's test environment is one; `julia -e 'using Pkg;
Pkg.activate("env"); Pkg.develop(path="."); Pkg.add(["MPI", "MPICH_jll"])'`
makes another). Under the arm every rank builds its shard of the beams from
the same seed, every route is the same object on every rank, each rank times
its own `execute!` (a barrier precedes every timed run so the ranks start
together) and digests its local shard; the table, printed by rank 0, carries
the per-rank medians and minima reduced to the MAX over ranks and, per beam,
the SHA-256 of the ranks' shard digests in rank order; the verdict's four
quantities are reduced over all ranks (equality by MIN, differences by MAX),
so every rank reaches the same verdict and the same exit status. The rank
comes from MPI.Comm_rank, not from Octopus's `_mp_is_root()`, which reads a
serial passthrough outside an active policy scope. OCTOPUS_USE_GPU=1 with
OCTOPUS_USE_MPI=1 is refused: the policy composes the CPU policy and there is
no CUDA-plus-MPI mode to select.

The gate's CUDA arm runs the deterministic case at a reduced size (the testset
"CUDA-requiring validation scripts run in the gate's CUDA arm" in
test/runtests.jl reads the line below; validation/README.md); its timings at
that size are a run receipt, not a performance record:

GATE-CUDA-ARM: env OCTOPUS_USE_GPU=1 OCTOPUS_PARITY_CASE=ws OCTOPUS_PARITY_N_MACRO=2000 OCTOPUS_PARITY_TURNS=2 OCTOPUS_PARITY_REPEATS=1 ; verdict "PARITY case=ws backend=cuda ranks=1 routes=tuple,control,lattice,machine runs=1 digests_equal=true"
=#

# One grammar for every switch (the harnesses' rule since 2026-10-18): a value
# outside it is an error naming the variable, never a silent default. Defined
# above the Octopus load because OCTOPUS_USE_MPI decides how Octopus loads.
function env_bool(key::AbstractString, default::Bool)
    raw = get(ENV, key, default ? "1" : "0")
    lowered = lowercase(strip(raw))
    lowered in ("1", "true", "yes", "on") && return true
    lowered in ("0", "false", "no", "off") && return false
    error("$(key)=$(repr(raw)) is not a boolean; use 1/0, true/false, yes/no or on/off")
end
function env_int(key::AbstractString, default::Int)
    value = parse(Int, get(ENV, key, string(default)))
    value > 0 || error("$(key) must be positive; got $(value)")
    return value
end

const USE_MPI = env_bool("OCTOPUS_USE_MPI", false)
if USE_MPI
    # The harness's rule (header): the extension attaches only to a package,
    # and an `include`d Main.Octopus cannot become one.
    if isdefined(Main, :Octopus) && Base.PkgId(Main.Octopus).uuid === nothing
        error("OCTOPUS_USE_MPI=1 needs Octopus loaded as a PACKAGE, because the OctopusMPIExt " *
              "extension attaches only to a package -- but Main.Octopus is already an `include`d " *
              "module (its PkgId carries no UUID). Run this driver under the launcher with " *
              "--project=<env holding Octopus, MPI and MPICH_jll> and no earlier include of src/Octopus.jl.")
    end
    using Octopus
    using MPI
    MPI.Initialized() || MPI.Init(threadlevel = :funneled)
elseif !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using SHA, Printf
if USE_MPI && Base.get_extension(Main.Octopus, :OctopusMPIExt) === nothing
    error("OCTOPUS_USE_MPI=1, but OctopusMPIExt did not load: every rank would then be its own " *
          "communicator of one and run the WHOLE measurement. Run against an environment where " *
          "Octopus and MPI both resolve as packages.")
end

# The header's OCTOPUS_* list against what this file reads, so the two cannot
# drift (profiling/benchmark_strong_strong_pic.jl's rule, the harnesses'
# form): the header is the text above the first `=#`; a name is read when the
# body spells it as a string literal; a glob token ending in `_` is not a name.
let text = read(@__FILE__, String)
    header, body = split(text, "=#"; limit=2)
    names(s, pattern) = Set(String(m.captures[1]) for m in eachmatch(pattern, s)
                            if !endswith(m.captures[1], "_"))
    named = names(header, r"(OCTOPUS_[A-Z0-9_]+)")
    read_names = names(body, r"\"(OCTOPUS_[A-Z0-9_]+)\"")
    named == read_names || error("parity driver header drift: named but never read " *
        string(sort!(collect(setdiff(named, read_names)))) * "; read but not named " *
        string(sort!(collect(setdiff(read_names, named)))))
end

const CASE = Symbol(lowercase(strip(get(ENV, "OCTOPUS_PARITY_CASE", "ss"))))
CASE in (:ss, :ws) || error("OCTOPUS_PARITY_CASE=$(repr(String(CASE))) is not one of ss, ws")
const N_MACRO = env_int("OCTOPUS_PARITY_N_MACRO", 20_000)
const TURNS = env_int("OCTOPUS_PARITY_TURNS", 10)
const REPEATS = env_int("OCTOPUS_PARITY_REPEATS", 5)
const USE_GPU = env_bool("OCTOPUS_USE_GPU", false)
# A variable set where the chosen policy cannot read it is a configuration
# nothing read (the examples' rule, comprehensive audit 2026-10-18 F-204):
# refused by name instead of dropped.
USE_GPU && USE_MPI && error(
    "OCTOPUS_USE_GPU=1 and OCTOPUS_USE_MPI=1 together: MultiProcessExecutionPolicy composes " *
    "CPUThreadsExecutionPolicy and runs on CPU storage, so there is no CUDA-plus-MPI mode to select. Choose one.")
USE_MPI || !haskey(ENV, "OCTOPUS_RANKS") || error(
    "OCTOPUS_RANKS=$(repr(ENV["OCTOPUS_RANKS"])) without OCTOPUS_USE_MPI=1: the rank count is read only " *
    "by the multi-process arm, so it would go unread -- and under a launcher a single-process run on " *
    "every rank is P whole measurements. Set OCTOPUS_USE_MPI=1 for a divided run.")
USE_GPU || !haskey(ENV, "OCTOPUS_CUDA_DEVICE") || error(
    "OCTOPUS_CUDA_DEVICE=$(repr(ENV["OCTOPUS_CUDA_DEVICE"])) without OCTOPUS_USE_GPU=1: the CPU " *
    "policy reads no device index, so the value would be silently dropped. Set OCTOPUS_USE_GPU=1 or unset it.")
!USE_GPU || !haskey(ENV, "OCTOPUS_CPU_THREADS") || error(
    "OCTOPUS_CPU_THREADS=$(repr(ENV["OCTOPUS_CPU_THREADS"])) with OCTOPUS_USE_GPU=1: the CUDA policy " *
    "reads no worker count, so the value would be silently dropped. Unset one of the two.")

if USE_GPU
    import CUDA
    CUDA.functional(false) || error("OCTOPUS_USE_GPU=1 requested, but CUDA.functional(false) is false: no usable device.")
    device_text = strip(get(ENV, "OCTOPUS_CUDA_DEVICE", ""))
    policy = CUDAExecutionPolicy(device = isempty(device_text) ? nothing : parse(Int, device_text))
    sync_device() = CUDA.synchronize()
    reclaim_device() = CUDA.reclaim()
else
    threads_text = lowercase(strip(get(ENV, "OCTOPUS_CPU_THREADS", "auto")))
    cpu_threads = threads_text == "auto" ? :auto : parse(Int, threads_text)
    if USE_MPI
        # OCTOPUS_RANKS goes straight through as the policy's `ranks`: the policy
        # rejects a communicator whose size differs from an explicit request.
        ranks_text = lowercase(strip(get(ENV, "OCTOPUS_RANKS", "auto")))
        policy = MultiProcessExecutionPolicy(threads = cpu_threads,
                                             ranks = ranks_text == "auto" ? :auto : parse(Int, ranks_text))
    else
        policy = CPUThreadsExecutionPolicy(threads = cpu_threads)
    end
    sync_device() = nothing
    reclaim_device() = nothing
end
const BACKEND = USE_GPU ? "cuda" : USE_MPI ? "mpi" : "cpu"
const SEED = 123456789

# The collective seams of the arm, serial passthroughs without it. The rank is
# MPI's own (header), the reductions are over MPI.COMM_WORLD.
if USE_MPI
    const MPI_RANK = MPI.Comm_rank(MPI.COMM_WORLD)
    const MPI_NRANKS = MPI.Comm_size(MPI.COMM_WORLD)
    barrier() = MPI.Barrier(MPI.COMM_WORLD)
    reduce_max(x::Float64) = MPI.Allreduce(x, MPI.MAX, MPI.COMM_WORLD)
    reduce_all(flag::Bool) = MPI.Allreduce(flag ? 1 : 0, MPI.MIN, MPI.COMM_WORLD) == 1
    # Every rank's 64-byte hex digest to rank 0, in rank order.
    function gather_digests(d::String)
        buf = MPI.Gather(Vector{UInt8}(codeunits(d)), MPI.COMM_WORLD; root = 0)
        MPI_RANK == 0 || return String[]
        return [String(buf[(64 * k + 1):(64 * k + 64)]) for k in 0:(MPI_NRANKS - 1)]
    end
else
    const MPI_RANK = 0
    const MPI_NRANKS = 1
    barrier() = nothing
    reduce_max(x::Float64) = x
    reduce_all(flag::Bool) = flag
    gather_digests(d::String) = [d]
end
const ROOT = MPI_RANK == 0

# ---------------------------------------------------------------------------
# The strong-strong case: examples/strong_strong_tracking.jl's physics as
# literals (the fixed point; the example is the authority on their meaning).
# ---------------------------------------------------------------------------
const SS = (
    half_crossing_angle = 12.5e-3,          # HALF the full crossing angle (LorentzBoostSpec's argument)
    electron = (charge = -1.0, mass = EMASS_EV, energy = 10.0e9, n_particle = 1.7203e11, cutoff = 5.0,
                sigma = (106.0e-6, 9.5e-6, 0.7e-2), sigma_delta = 5.5e-4, beta_star = (0.55, 0.056),
                crab_beta_x = 150.0, tune = (0.08, 0.14, -0.069), chromaticity = (1.0, 1.0),
                crab_frequency = 394.0e6, radiation_damping_turns = (4000.0, 4000.0, 2000.0)),
    proton = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11, cutoff = 5.0,
              sigma = (95.0e-6, 8.5e-6, 6.0e-2), sigma_delta = 6.6e-4, beta_star = (0.8, 0.072),
              crab_beta_x = 1300.0, tune = (0.228, 0.210, -0.01), chromaticity = (2.0, 2.0),
              crab_frequency = 197.0e6),
    zslice = 15,
    pic_grid = (128, 128),
)
ss_crab_kick(beta_cc, beta_star) = tan(SS.half_crossing_angle) / sqrt(beta_cc * beta_star)

# One ring's optics points and reference particle: shared by its beam and its
# elements, as the example shares them.
function ss_ring(p)
    beta_z = p.sigma[3] / p.sigma_delta
    return (ip = LinearOptics(; beta = (p.beta_star..., beta_z), alpha = (0.0, 0.0, 0.0)),
            crab = LinearOptics(; beta = (p.crab_beta_x, 30.0, beta_z), alpha = (0.0, 0.0, 0.0)),
            ref = ReferenceParticle(; charge = p.charge, mc2 = p.mass, E0 = p.energy))
end
const SS_ELE = ss_ring(SS.electron)
const SS_PRO = ss_ring(SS.proton)

# The elements of one strong-strong build, in tracking order, as the two
# tuples the example gathers (observers left out, header). A fresh solver and
# marker per call: no state is shared between routes.
function ss_elements()
    ele, pro = SS.electron, SS.proton
    zero3 = (0.0, 0.0, 0.0)
    e_strength = (ss_crab_kick(ele.crab_beta_x, ele.beta_star[1]), 0.0, 0.0)
    p_kick = ss_crab_kick(pro.crab_beta_x, pro.beta_star[1])
    p_strength = (p_kick * 4.0 / 3.0, -p_kick / 3.0, 0.0)     # the two-harmonic scheme, weights (4/3, -1/3, 0)
    transport(a, b) = Linear6DSpec{Float64}(a, b; dmu = (pi / 2.0, 0.0, 0.0))
    inverse(spec) = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(spec))))
    cavity(p, strength) = ThinCrabCavitySpec{3}(p.crab_frequency; strengthX = strength, strengthY = zero3, phase = zero3)
    e_tccb2ip, e_ip2tcca = transport(SS_ELE.crab, SS_ELE.ip), transport(SS_ELE.ip, SS_ELE.crab)
    p_tccb2ip, p_ip2tcca = transport(SS_PRO.crab, SS_PRO.ip), transport(SS_PRO.ip, SS_PRO.crab)
    slicing = LongitudinalSlicing(; method = :normal_quantile, nslices = SS.zslice, center_position = :centroid)
    solver = PICPoissonSolver(; slicing = slicing, grid = SS.pic_grid, deposit_method = :CIC,
                              green_type = :integrated, green_cache = :slice_pair,
                              slice_pair_green_min_ratio = 0.50, slice_pair_green_growth = 0.25,
                              longitudinal_kick = true)
    lb = LorentzBoostSpec(SS.half_crossing_angle)
    rlb = RevLorentzBoostSpec(SS.half_crossing_angle)
    ip = StrongStrongCollision(:ip; poisson_solver = solver)
    electron = (inverse(e_tccb2ip), cavity(ele, e_strength), e_tccb2ip, lb, ip, rlb,
                e_ip2tcca, cavity(ele, e_strength), inverse(e_ip2tcca),
                Linear6DSpec{Float64}(SS_ELE.ip, SS_ELE.ip; dmu = 2pi .* ele.tune),
                ChromaticityKickSpec{Float64}(; xi = ele.chromaticity, optics = SS_ELE.ip),
                LumpedRadSpec{Float64}(; damping_turns = ele.radiation_damping_turns, optics = SS_ELE.ip,
                                         sigma = ele.sigma, is_damping = true, is_excitation = true, rng_id = 3))
    proton = (inverse(p_tccb2ip), cavity(pro, p_strength), p_tccb2ip, lb, ip, rlb,
              p_ip2tcca, cavity(pro, p_strength), inverse(p_ip2tcca),
              Linear6DSpec{Float64}(SS_PRO.ip, SS_PRO.ip; dmu = 2pi .* pro.tune),
              ChromaticityKickSpec{Float64}(; xi = pro.chromaticity, optics = SS_PRO.ip))
    return (electron = electron, proton = proton)
end

# The two beams, rebuilt from the one seed: identical coordinates every call.
function ss_beams()
    set_global_rng!(seed = SEED, method = :philox)
    ele, pro = SS.electron, SS.proton
    electron = Beam(N_MACRO, policy, Float64; optics = SS_ELE.ip, sigma = ele.sigma, cutoff = ele.cutoff,
                    rng_id = 1, reference = SS_ELE.ref, npart = ele.n_particle)
    proton = Beam(N_MACRO, policy, Float64; optics = SS_PRO.ip, sigma = pro.sigma, cutoff = pro.cutoff,
                  rng_id = 2, reference = SS_PRO.ref, npart = pro.n_particle)
    return (electron, proton)
end

# The routes: the bare tuples, the control (the tuples built again), and the
# machine description -- each ring a BeamLine of its elements, a Lattice with
# its reference, the two gathered in Machine("EIC") and paired by name.
function ss_routes()
    tuples = ss_elements()
    control = ss_elements()
    described = ss_elements()
    esr = Lattice("ESR"; line = BeamLine("ESR", described.electron...), reference = SS_ELE.ref)
    hsr = Lattice("HSR"; line = BeamLine("HSR", described.proton...), reference = SS_PRO.ref)
    machine = Machine("EIC"; lattices = (esr, hsr))
    return [(name = "tuples", task = StrongStrongTask(tuples.electron, tuples.proton; policy = policy)),
            (name = "control", task = StrongStrongTask(control.electron, control.proton; policy = policy)),
            (name = "machine", task = StrongStrongTask(machine, :ESR, :HSR; policy = policy))]
end

# ---------------------------------------------------------------------------
# The weak-strong case: examples/weak_strong_tracking.jl's physics as literals.
# ---------------------------------------------------------------------------
const WS = (
    weak = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11, cutoff = 5.0,
            sigx = 95.0e-6, sigy = 8.5e-6, sigz = 6.0e-2, sigd = 6.6e-4, beta_x = 0.8, beta_y = 0.072),
    crab_beta = (1300.0, 100.0),
    half_crossing_angle = 12.5e-3,
    tune = (0.228, 0.210, -0.01),
    chromaticity = (2.0, 2.0),
    crab_frequency = 197.0e6,
    harmonic_weights = (4.0 / 3.0, -1.0 / 3.0, 0.0),
    strong = (charge = -1.0, n_particle = 1.7203e11, sigma = (95.0e-6, 8.5e-6, 0.7e-2),
              beta = (0.55, 0.056), alpha = (0.0, 0.0), z_slices = 7),
    damping_turns = (1.0e100, 1.0e100, 1.0e100),   # damping off, excitation on, as the example runs it
)

function ws_points()
    wb = WS.weak
    beta_z = wb.sigz / wb.sigd
    zero4 = (0.0, 0.0, 0.0, 0.0)
    return (ip = LinearOptics(; beta = (wb.beta_x, wb.beta_y, beta_z), alpha = (0.0, 0.0, 0.0),
                              zeta = zero4, eta = zero4, R = zero4),
            crab = LinearOptics(; beta = (WS.crab_beta..., beta_z)),
            ref = ReferenceParticle(; charge = wb.charge, mc2 = wb.mass, E0 = wb.energy),
            emit = (wb.sigx^2 / wb.beta_x, wb.sigy^2 / wb.beta_y, wb.sigz * wb.sigd),
            r0 = RE * ME0 / wb.mass)
end
const WS_P = ws_points()

# The weak-strong line in tracking order (observer left out, header); the
# luminosity factor klum reads N_MACRO as the example reads its n_macro.
function ws_elements()
    wb, st = WS.weak, WS.strong
    zero3 = (0.0, 0.0, 0.0)
    strength = (tan(WS.half_crossing_angle) / sqrt(wb.beta_x * WS.crab_beta[1])) .* WS.harmonic_weights
    cavity() = ThinCrabCavitySpec{3}(WS.crab_frequency; strengthX = strength, strengthY = zero3, phase = zero3)
    inverse(spec) = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(spec))))
    tccb2ip = Linear6DSpec{Float64}(WS_P.crab, WS_P.ip; dmu = (pi / 2.0, 0.0, 0.0))
    ip2tcca = Linear6DSpec{Float64}(WS_P.ip, WS_P.crab; dmu = (pi / 2.0, 0.0, 0.0))
    kbb = wb.charge * st.charge * st.n_particle * WS_P.r0 * wb.mass / wb.energy
    klum = st.n_particle * wb.n_particle / N_MACRO
    strong_beam = GaussianStrongBeamSpec{Float64}(; kbb = kbb, klum = klum, beta = st.beta, alpha = st.alpha,
        sigma = (st.sigma[1], st.sigma[2]), center = zero3, angle = zero3, curvature = zero3,
        virtual_drift = :hirata, ns = st.z_slices, sigz = st.sigma[3], slice_method = :equal_area)
    return (inverse(tccb2ip), cavity(), tccb2ip,
            LorentzBoostSpec(WS.half_crossing_angle), strong_beam, RevLorentzBoostSpec(WS.half_crossing_angle),
            ip2tcca, cavity(), inverse(ip2tcca),
            Linear6DSpec{Float64}(WS_P.ip, WS_P.ip; dmu = 2pi .* WS.tune),
            ChromaticityKickSpec{Float64}(; xi = WS.chromaticity, optics = WS_P.ip),
            LumpedRadSpec{Float64}(; damping_turns = WS.damping_turns, optics = WS_P.ip,
                                     sigma = (wb.sigx, wb.sigy, wb.sigz), is_damping = false,
                                     is_excitation = true, rng_id = 2))
end

function ws_beams()
    set_global_rng!(seed = SEED, method = :philox)
    wb = WS.weak
    return (Beam(N_MACRO, policy, Float64; optics = WS_P.ip, emit = WS_P.emit, cutoff = wb.cutoff, rng_id = 1,
                 reference = WS_P.ref, npart = wb.n_particle,
                 initial_offset = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)),)
end

ws_lattice() = Lattice("HSR"; line = BeamLine("HSR", ws_elements()...), reference = WS_P.ref)

# The routes: the tuple, the control (the tuple built again), the Lattice, and
# the one-lattice Machine made explicit (the task takes it where a line is).
function ws_routes()
    return [(name = "tuple", task = TrackingTask(ws_elements(); policy = policy)),
            (name = "control", task = TrackingTask(ws_elements(); policy = policy)),
            (name = "lattice", task = TrackingTask(ws_lattice(); policy = policy)),
            (name = "machine", task = TrackingTask(Machine(ws_lattice()); policy = policy))]
end

# ---------------------------------------------------------------------------
# Measurement.
# ---------------------------------------------------------------------------
host_coordinates(beam) = map(x -> Vector{Float64}(Array(x)), coordinate_arrays(beam.rep))
digest(coords) = bytes2hex(sha256(collect(reinterpret(UInt8, reduce(vcat, coords)))))
max_abs_diff(a, b) = maximum(maximum(abs(x - y) for (x, y) in zip(va, vb)) for (va, vb) in zip(a, b))
median_value(values) = (s = sort(values); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)

function timed_execute!(task, beams)
    barrier()            # under MPI the ranks start a timed run together; a no-op otherwise
    sync_device()
    t0 = time_ns()
    bytes = @allocated execute!(task, beams...; turns = TURNS)
    sync_device()
    return ((time_ns() - t0) * 1.0e-9, bytes)
end

routes = CASE === :ss ? ss_routes() : ws_routes()
make_beams = CASE === :ss ? ss_beams : ws_beams
route_names = join((r.name for r in routes), ",")
ROOT && println("machine description parity: case=", CASE, " backend=", BACKEND, " policy=", nameof(typeof(policy)),
                " n_macro=", N_MACRO, " turns=", TURNS, " repeats=", REPEATS, " julia_threads=", Threads.nthreads(),
                " mpi_ranks=", MPI_NRANKS, " routes=", route_names)
# The initial beams are identical by construction (one seed): said once, checked
# (on every rank for its own shard under MPI).
initial_digests = [digest.(host_coordinates.(make_beams())) for _ in 1:2]
initial_digests[1] == initial_digests[2] || error("the beams rebuilt from the seed differ between two builds: ",
                                                 initial_digests)
ROOT && println("initial coordinates (per beam, every run of every route", USE_MPI ? "; rank 0's shard" : "",
                "): ", join(initial_digests[1], " "))

for route in routes, _ in 1:2    # warm-up (header): two executions of TURNS turns per route, through the
    beams = make_beams()           # measurement wrapper, so that neither a first nor a repeated execution's
    timed_execute!(route.task, beams)   # compile lands in the first route's first timed run
end

seconds = Dict(r.name => Float64[] for r in routes)
allocated = Dict(r.name => Float64[] for r in routes)
digests = Dict(r.name => Vector{Vector{String}}() for r in routes)
finals = Dict(r.name => Vector{Any}() for r in routes)
for run in 1:REPEATS, route in routes      # interleaved: route 1, route 2, ..., route 1, route 2, ...
    beams = make_beams()
    GC.gc()
    reclaim_device()
    t, bytes = timed_execute!(route.task, beams)
    push!(seconds[route.name], t / TURNS)
    push!(allocated[route.name], bytes / TURNS)
    coords = [host_coordinates(b) for b in beams]
    push!(digests[route.name], [digest(c) for c in coords])
    push!(finals[route.name], coords)
end

nbeams = length(first(values(digests))[1])
# The table: per rank the median over runs (and the minimum), reduced to the
# MAX over ranks under MPI; per beam the last run's digest, under MPI the
# SHA-256 of the ranks' shard digests in rank order. Every rank takes part in
# the reductions and the gathers; rank 0 prints.
over = USE_MPI ? "max over $(MPI_NRANKS) ranks of " : ""
shard = USE_MPI ? " (SHA-256 of the ranks' shard digests)" : ""
ROOT && println()
ROOT && println("| route | ", over, "median s/turn | ", over, "min s/turn | ", over, "median allocated bytes/turn |",
                join((" SHA-256 beam $(k) (last run)$(shard) |" for k in 1:nbeams)))
ROOT && println("|---|---|---|---|", join(("---|" for _ in 1:nbeams)))
for route in routes
    name = route.name
    med = reduce_max(median_value(seconds[name]))
    low = reduce_max(minimum(seconds[name]))
    bytes_med = reduce_max(median_value(allocated[name]))
    shown = String[]
    for d in last(digests[name])
        ranks_digests = gather_digests(d)
        push!(shown, USE_MPI ? (ROOT ? bytes2hex(sha256(join(ranks_digests))) : "") : d)
    end
    ROOT && @printf("| %s | %.6f | %.6f | %.0f |", name, med, low, bytes_med)
    ROOT && println(join((" $(d) |" for d in shown)))
end

# The verdict (header): every described route against the tuple route over
# every run; the control route likewise, as the floor.
reference = routes[1].name
described = [r.name for r in routes if r.name != reference && r.name != "control"]
equal_to_reference(name) = all(digests[name][j] == digests[reference][j] for j in 1:REPEATS)
diff_to_reference(name) = maximum(max_abs_diff(finals[name][j][k], finals[reference][j][k])
                                  for j in 1:REPEATS for k in 1:nbeams)
# Under MPI the four quantities are reduced over all ranks (equality by MIN,
# differences by MAX), so every rank reaches the same verdict and exit status.
digests_equal = reduce_all(all(equal_to_reference, described))
max_diff = reduce_max(maximum(diff_to_reference, described))
control_equal = reduce_all(equal_to_reference("control"))
control_floor = reduce_max(diff_to_reference("control"))
verdict = digests_equal ? "PASS" : (control_equal ? "FAIL" : "REPORT")
ROOT && println()
ROOT && println("PARITY case=", CASE, " backend=", BACKEND, " ranks=", MPI_NRANKS, " routes=", route_names,
                " runs=", REPEATS, " digests_equal=", digests_equal, " max_abs_coordinate_diff=", max_diff,
                " control_equal=", control_equal, " control_floor=", control_floor, " verdict=", verdict)
if verdict == "FAIL"
    ROOT && println("the described route(s) ", join(described, ","), " differ from the tuple route while ",
                    "the control does not: a difference where the control shows none is not noise")
    exit(1)
end
