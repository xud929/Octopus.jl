#=
Phase 0 prototype for the multi-process (MPI x CPUThreads) execution policy:
does P ranks x T threads beat 1 x 16 threads on one box for a strong-strong
collide? Measured answer (2026-08-19, this 128-thread box): yes -- PIC at
8x8 socket-bound is 1.86x over socket-bound 1x16 and 2.23x over unbound.
Full matrix: docs/history/multi_process_phase0_2026_08_19.md.

COST MODEL, NOT PHYSICS. In the real particle-decomposed design each rank
holds N/P particles of both beams, deposits its own particles, Allgathers and
folds the partial grids in rank order, redundantly solves the field, and kicks
its own particles. This prototype approximates the per-rank cost as:

    collide!(beams of size N/P)  +  NCOMM x (Allgather GRIDxGRID grid + ordered fold)

which is exact for the kick/deposit/FFT arithmetic and the memory traffic (the
quantities the 2026-08-09 campaign measured as the ceiling), and additive
rather than interleaved for the communication (slightly pessimistic). The
per-rank beams are IDENTICAL across ranks (same rng streams), not disjoint
shards: same per-rank arithmetic and traffic, no physics meaning. Luminosity
and digests are therefore per-rank internal consistency checks only.

Timing protocol copied from benchmark_collide_cpu.jl: task-path collide (warm
Green cache + workspace pool), snapshot/restore between repeats, median
reported. The cross-rank number that matters is MAX over ranks -- the slowest
rank sets the turn time.

SETUP -- two environment traps, both measured (see the history record):

  1. HDF5_jll variant flip: with MPIPreferences prefs visible in the load
     path, HDF5_jll selects an mpi+openmpi ARTIFACT VARIANT that is not
     installed and Octopus fails to load. So Octopus is loaded FIRST (serial
     HDF5), and the MPI environment joins the load path afterwards.
  2. Load-order lock: because HDF5 itself depends on MPIPreferences, step 1
     loads MPIPreferences with its MPICH_jll DEFAULT before MPI.jl ever
     reads a preference -- so the ranks run MPICH_jll regardless of any
     use_system_binary() configuration, and the launcher must be MPICH's
     hydra mpiexec (a PMIx launcher like Open MPI's prterun aborts with
     "unsupported PMI version"). For on-box timing the transport is
     immaterial; production MPI selection is a Phase 1 environment task.

One-time setup of the side environment (any path; MPI.jl is NOT an Octopus
dependency and must not become one through this script):

    julia -e 'using Pkg; Pkg.activate(ENV["OCTOPUS_MPI_ENV"]); Pkg.add(["MPI", "MPICH_jll"])'

Find the matching hydra mpiexec:

    julia --project=$OCTOPUS_MPI_ENV -e 'using MPICH_jll; println(MPICH_jll.mpiexec_path)'

Run from the Octopus project root (hydra forwards the environment; -bind-to
socket assigns ranks to sockets round-robin -- verified masks are printed by
rank 0):

    export OCTOPUS_MPI_ENV=/path/to/that/env
    export JULIA_THREAD_SLEEP_THRESHOLD=0
    <hydra mpiexec> -n 8 -bind-to socket \
      julia --startup-file=no --project=. --threads=8 profiling/mpi_collide_prototype.jl

Env: OCTOPUS_MPI_ENV (required; see above), OCTOPUS_BENCH_SOLVER
(pic | gaussian), OCTOPUS_BENCH_N_ELE / _N_PRO (TOTAL beam sizes, split /P
per rank; defaults are the production point 2_560_000 / 1_024_000),
OCTOPUS_BENCH_SLICES (15), OCTOPUS_BENCH_GRID (128), OCTOPUS_BENCH_REPEATS
(3), OCTOPUS_BENCH_COMM_CALLS (450 = one production turn's slice-pair
interactions; 0 disables the comm phase).
=#
using Octopus   # FIRST, and package-style: per-rank include-compiles are minutes each
haskey(ENV, "OCTOPUS_MPI_ENV") || error(
    "set OCTOPUS_MPI_ENV to a Julia environment containing MPI.jl " *
    "(created with Pkg.add([\"MPI\", \"MPICH_jll\"]); see the header).")
push!(LOAD_PATH, ENV["OCTOPUS_MPI_ENV"])
using MPI
using Printf

MPI.Init(threadlevel = :funneled)
const comm = MPI.COMM_WORLD
const rank = MPI.Comm_rank(comm)
const nranks = MPI.Comm_size(comm)

env_int(name, default) = parse(Int, get(ENV, name, string(default)))
const SOLVER  = lowercase(get(ENV, "OCTOPUS_BENCH_SOLVER", "pic"))
const N_ELE_T = env_int("OCTOPUS_BENCH_N_ELE", 2_560_000)
const N_PRO_T = env_int("OCTOPUS_BENCH_N_PRO", 1_024_000)
const NSLICES = env_int("OCTOPUS_BENCH_SLICES", 15)
const GRID    = env_int("OCTOPUS_BENCH_GRID", 128)
const REPEATS = env_int("OCTOPUS_BENCH_REPEATS", 3)
const NCOMM   = env_int("OCTOPUS_BENCH_COMM_CALLS", 450)

N_ELE_T % nranks == 0 && N_PRO_T % nranks == 0 ||
    error("total beam sizes must divide the rank count; got $N_ELE_T/$N_PRO_T over $nranks")
const N_ELE = N_ELE_T ÷ nranks
const N_PRO = N_PRO_T ÷ nranks

set_global_rng!(seed = 123456789, method = :philox)
policy = CPUThreadsExecutionPolicy(threads = :auto)

# Production-point literals from benchmark_collide_cpu.jl.
const ELE = (charge = -1.0, mass = EMASS_EV, energy = 10.0e9, n_particle = 1.7203e11,
             cutoff = 5.0, sigma = (106.0e-6, 9.5e-6, 0.7e-2),
             beta = (0.55, 0.056, 0.7e-2 / 5.5e-4), alpha = (0.0, 0.0, 0.0))
const PRO = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11,
             cutoff = 5.0, sigma = (95.0e-6, 8.5e-6, 6.0e-2),
             beta = (0.8, 0.072, 6.0e-2 / 6.6e-4), alpha = (0.0, 0.0, 0.0))

beam_ele = Beam(N_ELE, policy, Float64; beta = ELE.beta, alpha = ELE.alpha,
                sigma = ELE.sigma, cutoff = ELE.cutoff, rng_id = 1,
                charge = ELE.charge, mc2 = ELE.mass, E0 = ELE.energy,
                r0 = RE * ME0 / ELE.mass, npart = ELE.n_particle)
beam_pro = Beam(N_PRO, policy, Float64; beta = PRO.beta, alpha = PRO.alpha,
                sigma = PRO.sigma, cutoff = PRO.cutoff, rng_id = 2,
                charge = PRO.charge, mc2 = PRO.mass, E0 = PRO.energy,
                r0 = RE * ME0 / PRO.mass, npart = PRO.n_particle)

slicing = LongitudinalSlicing(; method = :normal_quantile, nslices = NSLICES,
                              center_position = :centroid)
solver = if SOLVER == "gaussian"
    GaussianPoissonSolver(; slicing = slicing, min_sigma = 1.0e-12,
                          longitudinal_kick = true, batch_mode = :wavefront)
elseif SOLVER == "pic"
    PICPoissonSolver(; slicing = slicing, grid = (GRID, GRID),
                     deposit_method = :CIC, green_type = :integrated,
                     green_cache = :slice_pair,
                     slice_pair_green_min_ratio = 0.50,
                     slice_pair_green_growth = 0.25,
                     longitudinal_kick = true, batch_mode = :wavefront)
else
    error("OCTOPUS_BENCH_SOLVER must be pic | gaussian for this prototype; got $(repr(SOLVER))")
end

snapshot(beam) = map(copy, coordinate_arrays(beam))
restore!(beam, snap) = foreach((a, b) -> copyto!(a, b), coordinate_arrays(beam), snap)
snap_ele = snapshot(beam_ele)
snap_pro = snapshot(beam_pro)

bench_task = StrongStrongTask((), (); poisson_solver = solver)
const BENCH_LABEL = :bench
bench_ctx(turn) = TrackingContext(turn = Int64(turn))

function coordinate_digest(beams...)
    h = UInt64(0)
    for b in beams, a in coordinate_arrays(b), v in a
        h = (h << 1) | (h >> 63)
        h ⊻= reinterpret(UInt64, Float64(v))
    end
    return h
end

# The comm phase: NCOMM x (Allgather one GRIDxGRID Float64 grid + fold the P
# partials in rank order). Rank-ordered serial fold => bit-identical result on
# every rank, the determinism posture the real design uses. Cost grows O(P);
# the real design must interleave it with compute and, past ~16 ranks, use a
# deterministic tree instead.
partial = fill(Float64(rank + 1), GRID, GRID)
gathered = zeros(Float64, GRID * GRID * nranks)
folded = zeros(Float64, GRID, GRID)
function comm_phase!(folded, gathered, partial, ncalls)
    for _ in 1:ncalls
        MPI.Allgather!(MPI.Buffer(vec(partial)), MPI.UBuffer(gathered, GRID * GRID), comm)
        fill!(folded, 0.0)
        for r in 0:(nranks - 1)
            block = reshape(view(gathered, (r * GRID * GRID + 1):((r + 1) * GRID * GRID)),
                            GRID, GRID)
            folded .+= block
        end
    end
    return folded
end

rank == 0 && @printf("MPI-PROTO solver=%s ranks=%d threads/rank=%d n_ele/rank=%d n_pro/rank=%d slices=%d grid=%d comm_calls=%d\n",
        SOLVER, nranks, Threads.nthreads(:default), N_ELE, N_PRO, NSLICES, GRID, NCOMM)

# Binding provenance (hydra has no --report-bindings): each rank's allowed
# CPUs, gathered and printed by rank 0. Cores 0-31,64-95 are socket 0 on this
# box, 32-63,96-127 socket 1 -- the mask says whether ranks really separated.
affinity = let s = read("/proc/self/status", String)
    m = match(r"Cpus_allowed_list:\s*(\S+)", s)
    m === nothing ? "?" : m.captures[1]
end
all_aff = MPI.gather(affinity, comm; root = 0)
if rank == 0
    for (r, a) in enumerate(all_aff)
        @printf("  rank %d cpus_allowed: %s\n", r - 1, a)
    end
end

for w in 1:2   # JIT + warm Green cache / workspace pool
    restore!(beam_ele, snap_ele)
    restore!(beam_pro, snap_pro)
    Octopus._strong_strong_collide_backend!(bench_task, BENCH_LABEL, solver, beam_ele,
                                            beam_pro, CPUThreadsBackend, bench_ctx(w))
    comm_phase!(folded, gathered, partial, min(NCOMM, 5))
end
MPI.Barrier(comm)

t_collide = Float64[]
t_comm = Float64[]
digests = UInt64[]
for r in 1:REPEATS
    restore!(beam_ele, snap_ele)
    restore!(beam_pro, snap_pro)
    MPI.Barrier(comm)
    t0 = time_ns()
    Octopus._strong_strong_collide_backend!(bench_task, BENCH_LABEL, solver, beam_ele,
                                            beam_pro, CPUThreadsBackend, bench_ctx(10 + r))
    t1 = time_ns()
    comm_phase!(folded, gathered, partial, NCOMM)
    t2 = time_ns()
    push!(t_collide, (t1 - t0) / 1e9)
    push!(t_comm, (t2 - t1) / 1e9)
    push!(digests, coordinate_digest(beam_ele, beam_pro))
end

med(v) = sort(v)[cld(length(v), 2)]
my_collide = med(t_collide)
my_comm = med(t_comm)
repeats_ok = all(==(first(digests)), digests)

all_collide = MPI.Gather(my_collide, comm; root = 0)
all_comm = MPI.Gather(my_comm, comm; root = 0)
all_ok = MPI.Gather(repeats_ok, comm; root = 0)
max_total = MPI.Allreduce(my_collide + my_comm, MPI.MAX, comm)

if rank == 0
    for r in 1:nranks
        @printf("  rank %d: collide %.4f s   comm %.4f s   repeats_agree=%s\n",
                r - 1, all_collide[r], all_comm[r], all_ok[r])
    end
    @printf("MPI-RESULT solver=%s P=%d T=%d turn_cost_max=%.4f collide_max=%.4f comm_max=%.4f\n",
            SOLVER, nranks, Threads.nthreads(:default),
            max_total, maximum(all_collide), maximum(all_comm))
    all(all_ok) || @warn "some rank's repeats disagreed; timings not comparable"
end
MPI.Finalize()
