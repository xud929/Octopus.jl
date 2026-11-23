#=
Multi-process memory check (2026-11-23): the strong-strong case of the owner's Perlmutter scan
(SS9GeV_scan.jl case 1134, MultiProcessExecutionPolicy, PIC, 15 x 15 slices, 128 x 128, every-turn
moment observers, file artifact) at a reduced macroparticle count, run under an MPI launcher so that
the resident memory of every rank can be watched over the turns. It found and then verified the fix of
the migration exchange-buffer leak (`docs/history/multi_process_exchange_leak_2026_11_23.md`): with
the leak, RSS grew 5.2 MiB per turn per rank at 8 ranks and the extension's `_MP_EXCHANGE_BUFFERS`
held one new matrix per distinct column count; fixed, the cache holds one send and one receive buffer
per (eltype, rows) and RSS plateaus.

Run (from the repository root, an environment holding Octopus and MPI):

    mpiexec -n 2 julia --project=. --threads=2,0 --gcthreads=1 validation/multi_process_memory/repro_exchange_leak.jl

with `rss_poll.sh "repro_exchange_leak.jl" rss.log` sampling every rank's VmRSS every 10 s beside it.
Environment: REPRO_NE, REPRO_NP (macroparticles per beam; 40,000 / 16,000 per rank is the Perlmutter
load), REPRO_TURNS (300), REPRO_TAG (artifact name), REPRO_GCLOG=1 (Julia GC log on rank 0,
summarised by gclog.py). At the end every rank reports maxrss, gc_live_bytes and the exchange-buffer
cache (entries and bytes), gathered on rank 0.
=#
using Octopus, MPI, Printf, Statistics

function get_beam_and_line(input, policy)
    beam = Beam(input.n_macro, policy, Float64; beta = input.beta, sigma = input.sigma, cutoff = input.cutoff, rng_id = input.rng_id, 
        charge = input.charge, mc2 = input.mass, E0 = input.energy, r0 = RE * ME0 / input.mass, npart = input.n_particle)

    tccb2ip = Linear6DSpec{Float64}(; beta1 = input.crab_beta, beta2 = input.beta, dmu = input.crab2ip_dmu)
    tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(tccb2ip))))
    ip2tcca = Linear6DSpec{Float64}(; beta1 = input.beta, beta2 = input.crab_beta, dmu = input.crab2ip_dmu)
    ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(ip2tcca))))
    tccb = ThinCrabCavitySpec{length(input.crab_strength_x)}( input.crab_frequency; strengthX = input.crab_strength_x)
    tcca = ThinCrabCavitySpec{length(input.crab_strength_x)}( input.crab_frequency; strengthX = input.crab_strength_x)
    ot = Linear6DSpec{Float64}(; beta1 = input.beta, beta2 = input.beta, dmu = 2pi .* input.tune)
    chrom = ChromaticityKickSpec{Float64}(; xi = input.chromaticity, beta = input.beta)
    rad = LumpedRadSpec{Float64}(; beta = input.beta, sigma = input.sigma, (input.radiation)...)
    obs = ScheduledObserver(MomentObserver(;name=input.name), EveryNSteps(;input.observer...))
    line_b = (tccb2ip_inv, tccb, tccb2ip)
    line_a = (ip2tcca, tcca, ip2tcca_inv, ot, chrom, rad, obs)
    return beam, line_b, line_a
end


function strong_strong(;artifact_path, artifact_option=(capacity=1000, append=false, storage=:file),
        seed=123456789, total_turns=50_000, zslice_e=15, zslice_p=15, mesh=(128, 128), nmacro_e = 2_560_000, nmacro_p = 1_024_000,
        npart_e = 1.7203e11, emit_e=(17e-9, 1.9e-9), bip_e=(0.4, 0.052), sigz_e=8e-3, sigd_e=4.9e-4, tune_e = (0.08, 0.14, -0.056),
        npart_p = 0.6881e11, emit_p=(8.5e-9, 1.0e-9), bip_p=(0.8, 0.096), sigz_p=6e-2, sigd_p=6.0e-4, tune_p = (0.228, 0.210, -0.010),
    )
    policy = MultiProcessExecutionPolicy()
    set_global_rng!(seed = seed, method = :philox)

    bcc_e=(150.0, 30.0, sigz_e/sigd_e)
    bcc_p=(1300.0, 30.0, sigz_p/sigd_p)

    half_crossing_angle = 12.5e-3
    cckick_e=tan(half_crossing_angle)/sqrt(bcc_e[1]*bip_e[1])
    cckick_p=tan(half_crossing_angle)/sqrt(bcc_p[1]*bip_p[1])
    crabbing_e=(1.0,)
    crabbing_p=(4/3,-1/3)

    # Lorentz boost and Poisson solver
    lb = LorentzBoostSpec(half_crossing_angle)
    rlb = RevLorentzBoostSpec(half_crossing_angle)
    pic_solver = PICPoissonSolver(;
        slicing1 = LongitudinalSlicing(; method = :normal_quantile, nslices = zslice_e, center_position = :centroid),
        slicing2 = LongitudinalSlicing(; method = :normal_quantile, nslices = zslice_p, center_position = :centroid),
        luminosity_scale = nothing, grid = mesh, deposit_method = :CIC, green_type = :integrated, interaction_grid = :slice_pair, 
        green_cache = :slice_pair, slice_pair_green_min_ratio = 0.95, slice_pair_green_growth = 0.05, longitudinal_kick = true, 
        batch_mode = :wavefront, cuda_async = true, cuda_batch_fft = true, cuda_wavefront_fft = true, cuda_indexed_wavefront = true, 
        luminosity_grid = nothing, luminosity_deposit_method = nothing, luminosity_schedule = nothing,
    )
    ip = StrongStrongCollision(:ip; poisson_solver = pic_solver)


    # beam1 input and line1 spec
    ele_input = (
        charge = -1.0, mass = EMASS_EV, energy = 9.0e9,
        n_particle = npart_e, n_macro = nmacro_e, cutoff = 5.0, rng_id = 1,
        sigma = (sqrt.(emit_e .* bip_e)..., sigz_e), beta = (bip_e..., bcc_e[3]),
        crab_beta = bcc_e, tune = tune_e,
        chromaticity = (1.0, 1.0), crab_frequency = 394.0e6,
        crab_strength_x = cckick_e .* crabbing_e,
        radiation = (damping_turns = (4000.0, 4000.0, 2000.0), rng_id = 3, is_damping = true, is_excitation = true),
        crab2ip_dmu = (pi/2, 0.0, 0.0),
        name = "ele",
        observer = (start = 0, step = 1, stop = total_turns),
    )
    beam_ele, lineb_e, linea_e = get_beam_and_line(ele_input, policy)
    line_ele = (lineb_e..., lb, ip, rlb, linea_e...)

    # beam2 input and line2 spec
    pro_input = (
        charge = 1.0, mass = PMASS_EV, energy = 275.0e9,
        n_particle = npart_p, n_macro = nmacro_p, cutoff = 5.0, rng_id = 2,
        sigma = (sqrt.(emit_p .* bip_p)..., sigz_p), beta = (bip_p..., bcc_p[3]),
        crab_beta = bcc_p, tune = tune_p,
        chromaticity = (2.0, 2.0), crab_frequency = 197.0e6,
        crab_strength_x = cckick_p .* crabbing_p,
        radiation = (damping_turns = (1e100, 1e100, 1e100), rng_id = 4, is_damping = false, is_excitation = false),
        crab2ip_dmu = (pi/2, 0.0, 0.0),
        name = "pro",
        observer = (start = 0, step = 1, stop = total_turns),
    )
    beam_pro, lineb_p, linea_p = get_beam_and_line(pro_input, policy)
    line_pro = (lineb_p..., lb, ip, rlb, linea_p...)

    if MPI.Comm_rank(MPI.COMM_WORLD) == 0
        println("Actual MPI ranks: ", MPI.Comm_size(MPI.COMM_WORLD))
        println("Julia compute threads per rank: ", Threads.nthreads(:default))
        println("Seed: ", seed)
        println("Turns: ", total_turns)
        println("Artifact: ", artifact_path)
        println("emit_e: ", emit_e)
        println("bip_e: ", bip_e)
        println("bip_p: ", bip_p)
        flush(stdout)
    end

    # artifact and task
    diagnostics = StrongStrongDiagnostics(; record_turn_times = false, memory_log_every = 0, cache_stats = false, pic_timing = false, pic_timing_detail = false, nvtx = false) 
    task = StrongStrongTask(line_ele, line_pro; policy = policy, artifact = RunArtifact(artifact_path; artifact_option...), diagnostics = diagnostics)
    execute!(task, beam_ele, beam_pro; turns = total_turns)
    return nothing
end

# Reduced reproduction of the Perlmutter scan case 1134 (bip_e = (0.51, 0.0512), bip_p = (0.8, 0.119),
# emit_e = (17e-9, 1.0e-9)): the same lines, solver options and observers, sizes and turns from the environment.
MPI.Initialized() || MPI.Init()
if get(ENV, "REPRO_GCLOG", "0") == "1" && MPI.Comm_rank(MPI.COMM_WORLD) == 0
    GC.enable_logging(true)   # every collection on rank 0: pause, collected, live heap
end
envi(n, d) = parse(Int, get(ENV, n, string(d)))
nmacro_e = envi("REPRO_NE", 320_000); nmacro_p = envi("REPRO_NP", 128_000)
total_turns = envi("REPRO_TURNS", 300)
tag = get(ENV, "REPRO_TAG", "run")
outdir = joinpath(@__DIR__, "..", "..", "result", "multi_process_memory")   # git-ignored run output
mkpath(outdir)
artifact_path = joinpath(outdir, "repro_" * tag * ".h5")
isfile(artifact_path) && rm(artifact_path); isfile(artifact_path * ".lock") && rm(artifact_path * ".lock")
if MPI.Comm_rank(MPI.COMM_WORLD) == 0
    println("heap_size_hint = ", Base.JLOptions().heap_size_hint, "  gcthreads = ", Base.JLOptions().nmarkthreads, "  Sys.total_memory GiB = ", round(Sys.total_memory() / 2^30, digits = 1))
    flush(stdout)
end
t0 = time()
strong_strong(; artifact_path = artifact_path, seed = 123456789, total_turns = total_turns,
              nmacro_e = nmacro_e, nmacro_p = nmacro_p, emit_e = (17e-9, 1.0e-9), bip_e = (0.51, 0.0512), bip_p = (0.8, 0.119))
MPI.Barrier(MPI.COMM_WORLD)
if MPI.Comm_rank(MPI.COMM_WORLD) == 0
    println("done: turns = ", total_turns, "  wall = ", round(time() - t0, digits = 1), " s  maxrss rank0 = ", round(Sys.maxrss() / 2^20, digits = 0), " MiB")
end
rss = Sys.maxrss(); allrss = MPI.Gather(rss, 0, MPI.COMM_WORLD)
live = Base.gc_live_bytes(); alllive = MPI.Gather(live, 0, MPI.COMM_WORLD)
ext = Base.get_extension(Octopus, :OctopusMPIExt)
xb = ext._MP_EXCHANGE_BUFFERS
nkeys = length(xb); nbytes = sum(sizeof, values(xb); init = 0)
allkeys = MPI.Gather(nkeys, 0, MPI.COMM_WORLD); allbytes = MPI.Gather(nbytes, 0, MPI.COMM_WORLD)
if MPI.Comm_rank(MPI.COMM_WORLD) == 0
    println("_MP_EXCHANGE_BUFFERS per rank: entries ", join(string.(allkeys), " "), "  MiB ", join(string.(round.(allbytes ./ 2^20, digits = 1)), " "), "  total MiB = ", round(sum(allbytes) / 2^20, digits = 1))
    ks = sort(collect(keys(xb)), by = string)
    println("rank 0 exchange-buffer keys, first 12: ", ks[1:min(12, end)])
end
if MPI.Comm_rank(MPI.COMM_WORLD) == 0
    println("gc_live_bytes per rank [MiB]: ", join(string.(round.(Int, alllive ./ 2^20)), " "), "  total = ", round(Int, sum(alllive) / 2^20))
end
if MPI.Comm_rank(MPI.COMM_WORLD) == 0
    println("maxrss per rank [MiB]: ", join(string.(round.(Int, allrss ./ 2^20)), " "), "  total = ", round(Int, sum(allrss) / 2^20))
end
