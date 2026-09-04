#=
Benchmark weak-strong `TrackingTask` turns on the CPU, with a bitwise digest.

Purpose. The 2026-08-09 CPU campaign measured strong-strong `collide!` only;
this is the missing instrument for the OTHER production workload — the
crab-crossing weak-strong case of `test/examples/weak_strong_tracking.jl`
(physics literals copied here, per the fixed-measurement-point convention of
`benchmark_collide_cpu.jl`: this script must stay a fixed point even when the
harness's demo defaults change). No observer and no artifact, so the number is
tracking + beam-beam alone.

First measured curve (2026-08-19, production 1,024,000-particle point, this
128-thread box; docs/history/multi_process_phase0_2026_08_19.md): 2.22 s/turn
at 1 thread, 0.40 at 16 (the optimum), 0.66 at 32 — and 1.282 GiB allocated
per turn at EVERY thread count, with GC share rising 3.2% -> 30.8% -> 52.2%
at 1/16/64 threads. The weak-strong path was allocation/GC-bound past ~8
threads: it had never received the campaign's fix-1/fix-9 extraction treatment.
That fix was step 1 of the multi-process campaign this instrument was built
for, and it landed 2026-09-04
(docs/history/weak_strong_allocation_2026_09_04.md): the per-slice carrier of
the sliced strong beam became isbits, allocation 1.282 -> 0.000 GiB/turn and
GC 0% at every thread count, the curve monotone to 64 threads (2.09 s/turn at
1, 0.28 at 8, 0.17 at 16, 0.085 at 64), the digest below unmoved.

The digest is comparable ACROSS thread counts at fixed n_macro and turns:
same seed, same total turns => worker-count invariance says it must not move
(verified identical at 1/4/8/16/32/64 threads on 2026-08-19).

Run from the Octopus project root:

    julia --startup-file=no --project=. --threads=16 profiling/benchmark_track_cpu.jl

Set JULIA_THREAD_SLEEP_THRESHOLD=0 above ~32 threads (see the sibling script).

Env: OCTOPUS_BENCH_N_MACRO (default 1_024_000, the production proton count),
OCTOPUS_BENCH_TURNS (window length, default 20), OCTOPUS_BENCH_WINDOWS
(default 3). One warm window of 2 turns pays JIT; then WINDOWS timed windows
of TURNS turns each, continuing the same run (`execute!` advances the task's
absolute turn, so the radiation counter-RNG streams stay honest).

OCTOPUS_BENCH_ALLOC_PROFILE=1 replaces the timed windows with the allocation
localisation that found step 1's site: after the warm-up, bytes per particle
for one fused turn of the whole line and of each element alone (the beam is
restored between measurements, so every element sees the warmed state), then
Profile.Allocs' top sites by innermost Octopus frame, then exits. Run it at a
reduced point (OCTOPUS_BENCH_N_MACRO=16384); it prints no timing and no digest,
and it measures `track!` of the runtime line directly, so the task's per-turn
bookkeeping (schedules, observers, the artifact) is outside the number.
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Printf
using LinearAlgebra
using Profile          # the OCTOPUS_BENCH_ALLOC_PROFILE=1 mode below

env_int(name, default) = parse(Int, get(ENV, name, string(default)))
const N_MACRO = env_int("OCTOPUS_BENCH_N_MACRO", 1_024_000)
const TURNS   = env_int("OCTOPUS_BENCH_TURNS", 20)
const WINDOWS = env_int("OCTOPUS_BENCH_WINDOWS", 3)

set_global_rng!(seed = 123456789, method = :philox)
policy = CPUThreadsExecutionPolicy()

# Physics literals from test/examples/weak_strong_tracking.jl (weak proton
# beam, EIC crab crossing, 7-slice Gaussian strong beam, chromaticity,
# radiation excitation on).
wb = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11,
      cutoff = 5.0, sigx = 95.0e-6, sigy = 8.5e-6, sigz = 6.0e-2, sigd = 6.6e-4,
      beta_x = 0.8, beta_y = 0.072, alpha = (0.0, 0.0, 0.0),
      zeta = (0.0, 0.0, 0.0, 0.0), eta = (0.0, 0.0, 0.0, 0.0),
      coupling = (0.0, 0.0, 0.0, 0.0),
      initial_offset = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
opt = (crab_beta_x = 1300.0, crab_beta_y = 100.0, crossing_angle = 12.5e-3,
       tune = (0.228, 0.210, -0.01), chromaticity = (2.0, 2.0))
cc = (frequency = 197.0e6, harmonic_weights = (4.0 / 3.0, -1.0 / 3.0, 0.0),
      strength_y = (0.0, 0.0, 0.0), phase = (0.0, 0.0, 0.0))
strong = (charge = -1.0, n_particle = 1.7203e11,
          sigma = (95.0e-6, 8.5e-6, 0.7e-2), beta = (0.55, 0.056),
          alpha = (0.0, 0.0), z_slices = 7, slice_method = :equal_area,
          center = (0.0, 0.0, 0.0), angle = (0.0, 0.0, 0.0),
          curvature = (0.0, 0.0, 0.0), virtual_drift = :hirata,
          hvoffset = nothing)
rad = (damping_turns = (1.0e100, 1.0e100, 1.0e100), is_damping = false,
       is_excitation = true, alpha = (0.0, 0.0, 0.0),
       zeta = (0.0, 0.0, 0.0, 0.0), eta = (0.0, 0.0, 0.0, 0.0),
       coupling = (0.0, 0.0, 0.0, 0.0))

beta_z = wb.sigz / wb.sigd
emit = (wb.sigx^2 / wb.beta_x, wb.sigy^2 / wb.beta_y, wb.sigz * wb.sigd)
weak_r0 = RE * ME0 / wb.mass

beam = Beam(N_MACRO, policy, Float64;
    beta = (wb.beta_x, wb.beta_y, beta_z), alpha = wb.alpha, emit = emit,
    cutoff = wb.cutoff, rng_id = 1, charge = wb.charge, mc2 = wb.mass,
    E0 = wb.energy, r0 = weak_r0, npart = wb.n_particle, zeta = wb.zeta,
    eta = wb.eta, R = wb.coupling, initial_offset = wb.initial_offset)

cckick = tan(opt.crossing_angle) / sqrt(wb.beta_x * opt.crab_beta_x)
cc_strength_x = cckick .* cc.harmonic_weights
zero4 = (0.0, 0.0, 0.0, 0.0)
tccb2ip = Linear6DSpec{Float64}(;
    beta1 = (opt.crab_beta_x, opt.crab_beta_y, beta_z),
    beta2 = (wb.beta_x, wb.beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
    dmu = (pi / 2.0, 0.0, 0.0),
    zeta1 = zero4, eta1 = zero4, R1 = zero4, zeta2 = zero4, eta2 = zero4, R2 = zero4)
tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(tccb2ip))))
ip2tcca = Linear6DSpec{Float64}(;
    beta1 = (wb.beta_x, wb.beta_y, beta_z),
    beta2 = (opt.crab_beta_x, opt.crab_beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
    dmu = (pi / 2.0, 0.0, 0.0),
    zeta1 = zero4, eta1 = zero4, R1 = zero4, zeta2 = zero4, eta2 = zero4, R2 = zero4)
ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(ip2tcca))))
tccb = ThinCrabCavitySpec{3}(cc.frequency; strengthX = cc_strength_x,
    strengthY = cc.strength_y, phase = cc.phase)
tcca = ThinCrabCavitySpec{3}(cc.frequency; strengthX = cc_strength_x,
    strengthY = cc.strength_y, phase = cc.phase)
one_turn = Linear6DSpec{Float64}(;
    beta1 = (wb.beta_x, wb.beta_y, beta_z), beta2 = (wb.beta_x, wb.beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
    dmu = (2pi * opt.tune[1], 2pi * opt.tune[2], 2pi * opt.tune[3]),
    zeta1 = zero4, eta1 = zero4, R1 = zero4, zeta2 = zero4, eta2 = zero4, R2 = zero4)
chrom = ChromaticityKickSpec{Float64}(; xi = opt.chromaticity,
    beta = (wb.beta_x, wb.beta_y, beta_z), alpha = wb.alpha,
    zeta = zero4, eta = zero4, R = zero4)
kbb = wb.charge * strong.charge * strong.n_particle * weak_r0 * wb.mass / wb.energy
klum = strong.n_particle * wb.n_particle / N_MACRO
thin_strong = ThinStrongBeamSpec{Float64}(; kbb = kbb, klum = klum,
    beta = strong.beta, alpha = strong.alpha,
    sigma = (strong.sigma[1], strong.sigma[2]), center = strong.center,
    angle = strong.angle, curvature = strong.curvature,
    virtual_drift = strong.virtual_drift)
gsb = GaussianStrongBeamSpec{Float64}(; thin = thin_strong, ns = strong.z_slices,
    sigz = strong.sigma[3], slice_method = strong.slice_method,
    hvoffset = strong.hvoffset)
radiation = LumpedRadSpec{Float64}(; damping_turns = rad.damping_turns,
    beta = (wb.beta_x, wb.beta_y, beta_z), alpha = rad.alpha,
    sigma = (wb.sigx, wb.sigy, wb.sigz), zeta = rad.zeta, eta = rad.eta,
    R = rad.coupling, is_damping = rad.is_damping,
    is_excitation = rad.is_excitation, rng_id = 2)

line_specs = (tccb2ip_inv, tccb, tccb2ip, LorentzBoostSpec(opt.crossing_angle),
              gsb, RevLorentzBoostSpec(opt.crossing_angle), ip2tcca, tcca,
              ip2tcca_inv, one_turn, chrom, radiation)
task = TrackingTask(line_specs)

"""Process CPU seconds (user+sys); see `benchmark_collide_cpu.jl` for how to
read the derived utilisation number (diagnostic, not target)."""
function cpu_seconds()
    stat = read("/proc/self/stat", String)
    fields = split(stat[findlast(==(')'), stat) + 1:end])
    return (parse(Int, fields[12]) + parse(Int, fields[13])) / 100
end

"""Order-sensitive bitwise digest of every coordinate (rotate-then-xor);
agreement means every coordinate is bitwise equal."""
function coordinate_digest(beams...)
    h = UInt64(0)
    for b in beams, a in coordinate_arrays(b), v in a
        h = (h << 1) | (h >> 63)
        h ⊻= reinterpret(UInt64, Float64(v))
    end
    return h
end

@printf("WS-BENCH n_macro=%d turns/window=%d windows=%d julia_threads=%d\n",
        N_MACRO, TURNS, WINDOWS, Threads.nthreads(:default))

execute!(task, beam; turns = 2)   # JIT + schedule warm-up

if get(ENV, "OCTOPUS_BENCH_ALLOC_PROFILE", "0") == "1"
    # Allocation localisation (multi-process step 1, 2026-09-04): the number
    # that matters is bytes per PARTICLE per turn -- a per-call constant (the
    # worker tasks, the chunk fold) is not a leak, a per-particle term is.
    rep = beam.rep
    elems = Octopus._physics_line(Octopus._runtime_entries(task, rep))
    resolved = Octopus._resolve_execution_policy(task.policy, rep)
    ctx = Octopus.with_turn(Octopus.TrackingContext(), Int64(2))
    saved = map(copy, coordinate_arrays(beam))
    restore!() = foreach((a, b) -> copyto!(a, b), coordinate_arrays(beam), saved)
    measure(line) = Octopus._with_execution_policy(resolved) do
        restore!()
        Octopus.track!(rep, line, 1, resolved, ctx)          # warm the method
        restore!()
        gc0 = Base.gc_num()
        Octopus.track!(rep, line, 1, resolved, ctx)
        d = Base.GC_Diff(Base.gc_num(), gc0)
        (bytes = d.allocd, count = Base.gc_alloc_count(d))
    end
    whole = measure(elems)
    @printf("WS-ALLOC whole line: %.1f B/particle/turn, %.3f allocs/particle\n",
            whole.bytes / N_MACRO, whole.count / N_MACRO)
    for (i, e) in enumerate(elems)
        one = measure((e,))
        @printf("WS-ALLOC element %2d %-24s %8.1f B/particle/turn %7.3f allocs/particle\n",
                i, string(nameof(typeof(e))), one.bytes / N_MACRO, one.count / N_MACRO)
    end
    restore!()
    rate = min(1.0, 150_000 / max(whole.count, 1))
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate = rate Octopus._with_execution_policy(resolved) do
        Octopus.track!(rep, elems, 1, resolved, ctx)
    end
    allocs = Profile.Allocs.fetch().allocs
    # Anchor on this checkout's own src/ directory, not on a name substring:
    # a clone named Octopus.jl/ or a scratch worktree must classify the same.
    repo_root = normpath(joinpath(@__DIR__, ".."))
    src_root = joinpath(repo_root, "src")
    is_oct(fr) = startswith(string(fr.file), src_root)
    frkey(fr) = string(fr.func, " @ ", relpath(string(fr.file), repo_root), ":", fr.line)
    sites = Dict{String,Tuple{Int,Int}}()
    for a in allocs
        fr = filter(is_oct, a.stacktrace)
        k = isempty(fr) ? "<no Octopus frame>" : join(frkey.(fr[1:min(3, length(fr))]), " <- ")
        b, c = get(sites, k, (0, 0))
        sites[k] = (b + a.size, c + 1)
    end
    total = sum(kv -> kv[2][1], sites; init = 0)
    @printf("WS-ALLOC profile: %d samples at rate %.4f\n", length(allocs), rate)
    for (k, (b, c)) in first(sort(collect(sites); by = kv -> -kv[2][1]), 12)
        @printf("WS-ALLOC site %7.1f B/particle/turn %5.1f%% %8d samples  %s\n",
                b / rate / N_MACRO, 100 * b / max(total, 1), c, k)
    end
    exit(0)
end

times = Float64[]
for w in 1:WINDOWS
    gc0 = Base.gc_num()
    cpu0 = cpu_seconds()
    t0 = time_ns()
    execute!(task, beam; turns = TURNS)
    dt = (time_ns() - t0) / 1e9
    cpu = cpu_seconds() - cpu0
    gc1 = Base.gc_num()
    gc_s = (gc1.total_time - gc0.total_time) / 1e9
    nthreads = Threads.nthreads(:default)
    alloc = (gc1.allocd - gc0.allocd + gc1.total_allocd - gc0.total_allocd) / 2^30
    @printf("  window %d: %.4f s/turn   gc %.1f%%   util %.1f%%   alloc %.3f GiB/turn%s\n",
            w, dt / TURNS, 100 * gc_s / dt, 100 * cpu / (dt * nthreads), alloc / TURNS,
            get(ENV, "JULIA_THREAD_SLEEP_THRESHOLD", "") == "0" ? "" :
                "   (idle threads spinning: util inflated)")
    push!(times, dt / TURNS)
end
sorted = sort(times)
median = sorted[cld(length(sorted), 2)]
@printf("WS-RESULT threads=%d n_macro=%d s_per_turn_median=%.4f min=%.4f max=%.4f\n",
        Threads.nthreads(:default), N_MACRO, median, first(sorted), last(sorted))
@printf("WS-DIGEST 0x%016x  (after %d total turns)\n",
        coordinate_digest(beam), 2 + WINDOWS * TURNS)
