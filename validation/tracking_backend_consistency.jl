if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

#=
Validate that a tracking line produces consistent coordinates on different
execution backends.

Run from the project root:

    julia --project=. validation/tracking_backend_consistency.jl

The script always runs CPU/CPU checks. It also runs CPU/GPU checks when CUDA is
visible to Julia, or when explicitly requested:

    OCTOPUS_RUN_GPU_CONTRACT=1 julia --project=. validation/tracking_backend_consistency.jl

Useful environment variables:

    OCTOPUS_CONTRACT_N=10000
    OCTOPUS_CONTRACT_TURNS=2
    OCTOPUS_CONTRACT_ATOL=1e-10
    OCTOPUS_CONTRACT_RTOL=1e-10
    OCTOPUS_CONTRACT_SEED=123456789
    OCTOPUS_REQUIRE_GPU_CONTRACT=1

If `OCTOPUS_REQUIRE_GPU_CONTRACT=1`, a skipped CPU/GPU check is treated as an
error. Otherwise, lack of a visible CUDA device is reported as skipped.

The gate's CUDA arm runs this script with the GPU legs required, at a reduced
particle count (the testset "CUDA-requiring validation scripts run in the gate's
CUDA arm" in test/runtests.jl reads the line below; validation/README.md):

GATE-CUDA-ARM: env OCTOPUS_REQUIRE_GPU_CONTRACT=1 OCTOPUS_CONTRACT_N=2000 ; verdict "instances within their declared classes on CPU/CPU and CPU/GPU"

The CPU/CPU check runs the same CPU backend twice in the same Julia process.
For elementwise fused tracking it is expected to be bitwise identical, even with
multiple Julia threads, because particles are independent and the Octopus
counter RNG is keyed by particle index rather than thread scheduling order.

The multi-turn line carries each cavity kind twice: bare, and with
turn-by-turn modulation rules (a white rule and a turn table), so the
`TurnModulated` wrap, its device conversion and the per-turn host update are on
the path of both arms; a wrap tripwire after the coverage tripwire fails the run
if a kind that admits a rule compiles to no wrapper (2026-10-16 neighbour audit,
S2-1).

PER KIND, AGAINST THE DECLARED CROSS-BACKEND ROUNDING CLASS (fix I of the
2026-10-16 crab-noise neighbour audit, 2026-10-17). After the composed-line
contracts, the script tracks every instance of the lines ALONE on the CPU twice
(bitwise, the determinism check) and on the CPU against CUDA, and checks the
result against the kind's declaration, `_cross_backend_rounding(op)` returning a
`CrossBackendRounding` (src/track/Track.jl, where the rule is stated; the
declarations sit beside the runtime structs in src/elements/). The rule: both
backends round the IEEE operations alike -- add, multiply, divide, square root,
fma -- but the device fuses `a * b + c` into one FMA where the host rounds twice
(and which multiply it fuses is the compiler's choice: the straight drift's
`x + px/ps0 L` is bitwise at L = 0.5 only because scaling by a power of two is
exact), and its libm differs from the host's by one to three ulp on a few
percent of transcendental arguments (`sin`, `cos`, `exp`, `log`, `atan`). So a
coordinate the class declares bitwise -- never written, or written through
single IEEE operations or arithmetic exact under any fusion -- must agree to the
bit, and a coordinate of the ulp class must agree within the class's bound in
ulps of the coordinate's scale over the beam (`_cross_backend_violations`). The
composed-line contracts above keep their one tolerance, because a line mixes
every kind; the per-kind table is where the declaration meets the measurement,
and a violation fails the run by name. Measured 2026-10-17 (N = 10000, 2
turns, RTX 4500 Ada): every instance within its class; the figures are printed.
=#

function _bool_env(name, default)
    value = lowercase(get(ENV, name, default ? "1" : "0"))
    return value in ("1", "true", "yes", "on")
end

function _cuda_visible()
    try
        isdefined(Octopus, :_HAS_CUDA) && getfield(Octopus, :_HAS_CUDA) || return false
        cuda = getfield(Octopus, :CUDA)
        return Base.invokelatest(getproperty(cuda, :functional), false)
    catch
        return false
    end
end

function _print_result(label, result)
    println(label)
    println("  status = ", result.status)
    println("  message = ", result.message)
    for key in sort!(collect(keys(result.metrics)); by=string)
        println("  ", key, " = ", result.metrics[key])
    end
    println()
end

N = parse(Int, get(ENV, "OCTOPUS_CONTRACT_N", "10000"))
turns = parse(Int, get(ENV, "OCTOPUS_CONTRACT_TURNS", "2"))
atol = parse(Float64, get(ENV, "OCTOPUS_CONTRACT_ATOL", "1e-10"))
rtol = parse(Float64, get(ENV, "OCTOPUS_CONTRACT_RTOL", "1e-10"))
seed = parse(UInt64, get(ENV, "OCTOPUS_CONTRACT_SEED", "123456789"))
run_gpu = get(ENV, "OCTOPUS_RUN_GPU_CONTRACT", "auto")
require_gpu = Octopus._require_gpu_contract()   # U25-10: one parser, in Octopus

line = (
    Linear6DSpec{Float64}(;
        beta1=(0.8, 0.072, 90.0),
        beta2=(0.82, 0.075, 91.0),
        alpha1=(0.0, 0.0, 0.0),
        alpha2=(0.01, -0.02, 0.0),
        dmu=(0.08, 0.12, 0.02),
    ),
    CrabDispersionSpec{Float64}(zeta1=0.02, zeta2=-0.01, zeta3=0.004, zeta4=0.002),
    MomentumDispersionSpec{Float64}(eta1=0.03, eta2=-0.006, eta3=0.002, eta4=0.01),
    XYCouplingSpec{Float64}(r1=0.01, r2=-0.003, r3=0.002, r4=0.004),
    LorentzBoostSpec(0.01),
    ThinCrabCavitySpec{2}(197.0e6;
        strengthX=(1.0e-5, -2.0e-6),
        strengthY=(3.0e-6, 0.0),
        phase=(0.0, 0.2),
    ),
    RevLorentzBoostSpec(0.01),
    ChromaticityKickSpec{Float64}(;
        xi=(1.2, -0.8),
        beta=(0.82, 0.075),
        alpha=(0.01, -0.02),
        zeta=(0.002, -0.001, 0.0, 0.0),
        eta=(0.001, 0.0, -0.001, 0.0),
        R=(0.001, -0.0005, 0.0003, 0.0007),
    ),
    ThinStrongBeamSpec{Float64}(;
        kbb=1.0e-8,
        klum=1.0,
        beta=(0.82, 0.075),
        alpha=(0.01, -0.02),
        sigma=(110.0e-6, 12.0e-6),
        center=(2.0e-6, -1.0e-6, 0.0),
        angle=(0.0, 0.0, 0.0),
    ),
    GaussianStrongBeamSpec{Float64}(;
        thin=ThinStrongBeamSpec{Float64}(;
            kbb=8.0e-9,
            klum=1.0,
            beta=(0.82, 0.075),
            alpha=(0.01, -0.02),
            sigma=(115.0e-6, 13.0e-6),
            center=(-1.0e-6, 1.5e-6, 0.0),
            angle=(0.0, 0.0, 0.0),
        ),
        ns=3,
        sigz=7.0e-3,
        slice_method=:equal_area,
    ),
    # The misaligned thin strong beam (fix M, 2026-10-18): a strong beam behind
    # a `MisalignedElement` reached the fused CUDA launch as a kernel argument
    # and failed it (`KernelError: passing non-bitstype argument`); it is now
    # lifted out through the wrapper and tracked by the wrapped-strong-beam
    # kernel (`_track_cuda_wrapped_strong_beam!`, src/track/strong_beam_track.jl),
    # which this instance exercises in the line and alone (the per-kind arm
    # below, tagged "(misaligned)"). The bare instance above, translated.
    ThinStrongBeamSpec{Float64}(;
        kbb=1.0e-8,
        klum=1.0,
        beta=(0.82, 0.075),
        alpha=(0.01, -0.02),
        sigma=(110.0e-6, 12.0e-6),
        center=(2.0e-6, -1.0e-6, 0.0),
        angle=(0.0, 0.0, 0.0),
        x_offset=1.0e-4,
    ),
    LumpedRadSpec{Float64}(;
        damping_turns=(4000.0, 4000.0, 2000.0),
        beta=(0.8, 0.072, 90.0),
        alpha=(0.0, 0.0, 0.0),
        sigma=(95.0e-6, 8.5e-6, 6.0e-2),
        rng_id=101,
    ),
    # Every kind that declares ElementTrackingBackendConsistencyContract in
    # its metadata tracks here. The line used to carry 11 hand-picked kinds
    # while 18 declaring kinds — the whole thick-magnet family and every thin
    # element — were covered by neither this script nor the suite's
    # composed-cell testset; the tripwire after the contract definitions
    # fails the run when a newly declaring kind is not added (2026-08-05
    # audit, U21-5). Strengths are mild and the aperture generous: this is a
    # parity check, and a lost or wildly nonlinear particle tests less of the
    # map, not more.
    DriftSpec(L=0.35, h=0.02),
    QuadrupoleSpec(L=0.4, k1=0.8, nst=2, fringe=:all, va=0.03, vs=1.0e-4,
                   x_offset=1.0e-4),
    SextupoleSpec(L=0.25, k2=6.0, nst=2, tilt=0.01),
    OctupoleSpec(L=0.15, k3=80.0, nst=2),
    MultipoleSpec(L=0.3, k1=0.5, k2=4.0, nst=2, y_offset=1.0e-4),
    SBendSpec(L=1.1, angle=0.05, k1=0.2, e1=0.02, e2=0.015, fringe=:all,
              nst=2, ref_tilt=0.05),
    SolenoidSpec(L=0.8, ks=0.3, kn=(0.0, 0.2), nst=2),
    # Derived pair, not hand-picked: the U14-4 reference-pair invariant rejects
    # (0.99, 100.0), and had rejected it since 2026-08-07 -- this script was
    # un-runnable for three days because the invariant's blast radius was not
    # re-walked over the validations that construct cavities.
    ThinRFCavitySpec(197.0e6; strength=1.0e-4,
                     beta0=reference_beta(51.1e6, 0.511e6),
                     gamma0=reference_gamma(51.1e6, 0.511e6)),
    # The two cavities WITH turn-modulation rules (2026-10-16 neighbour audit,
    # S2-1). The bare cavities above cover the kernels; these cover what a
    # rule adds -- the `TurnModulated` wrap, its device conversion
    # (`adapt_structure` drops to the realised element at the launch) and the
    # per-turn `update_line` on the host -- which the Verification Matrix names
    # this script for and which no case here exercised. A white rule on a
    # fixed stream id (realised on the host, identically for both backends,
    # from the seed in force, the id, the turn and the slot) beside a table of
    # exactly `turns` entries (the task refuses a shorter window), so a
    # stream rule and a table rule each ride both cavity kinds; mild
    # strengths, as for every element here. The wrap tripwire after the
    # coverage tripwire fails the run if a cavity kind compiles to no wrapper.
    ThinCrabCavitySpec{2}(197.0e6;
        strengthX=(1.0e-5, -2.0e-6),
        strengthY=(3.0e-6, 0.0),
        phase=(0.0, 0.2),
        phase_noise=(WhiteNoise(2.0e-3; rng_id=7001), nothing),
        strength_noise=(nothing, TurnTable([0.05 * sin(2pi * k / 7) for k in 1:turns];
                                           name="contract_crab_amp")),
    ),
    ThinRFCavitySpec(197.0e6; strength=1.0e-4,
                     beta0=reference_beta(51.1e6, 0.511e6),
                     gamma0=reference_gamma(51.1e6, 0.511e6),
                     phase_noise=TurnTable([0.02 * cos(2pi * k / 5) for k in 1:turns];
                                           name="contract_rf_phase"),
                     strength_noise=WhiteNoise(5.0e-3; rng_id=7002)),
    # The accelerating cavity is NOT here: it is single-pass by contract and
    # rides its own one-turn line below.
    PatchSpec(dx=1.0e-5, dz=2.0e-5, angle_x=1.0e-4, angle_s=0.01),
    MarkerSpec(),
    ThinMultipoleSpec(knl=(0.0, 0.05, 1.2)),
    ThinDipoleSpec(k0l=1.0e-3),
    ThinQuadrupoleSpec(k1l=0.05),
    ThinSextupoleSpec(k2l=1.2),
    HKickerSpec(hkick=1.0e-4),
    VKickerSpec(vkick=1.0e-4),
    KickerSpec(hkick=1.0e-4, vkick=-5.0e-5),
    ApertureSpec(shape=:ellipse, x_limit=1.0, y_limit=1.0),
)

# `execute!` refuses a window that re-traverses an accelerating cavity (the
# second pass would track against a stale reference energy; single-pass
# refusal, 2026-08-14), and this script's default window is two turns. The
# cavity joined the multi-turn line the same day, so the script's default run
# threw at the first `validate` from then until 2026-09-04, when the
# multi-process step-1 neighbour audit ran it as that change's targeted check
# (docs/history/weak_strong_allocation_2026_09_04.md). Same shape as the
# aperture arm below: the cavity tracks on its own one-turn line, and the
# coverage tripwire counts both lines.
single_pass_line = (
    ThinAcceleratingCavitySpec(1.3e9; strength=2.0e-2, phase=0.1,
                               beta0=reference_beta(51.1e6, 0.511e6),
                               gamma0=reference_gamma(51.1e6, 0.511e6)),
)

# Task-managed reset has to lead its own trial line. Leaving it in the
# composed lattice's interior is invalid; testing it alone without changing
# coordinates would only exercise an identity. The kick supplies a visible
# difference between an evolving trajectory and repeated fixed-input trials.
reset_line = (PhaseSpaceResetSpec(), HKickerSpec(hkick=2.0e-5))
reset_turns = max(turns, 2)
let task_only = Set(Octopus.kind(T) for T in Octopus.registered_element_specs()
                    if Octopus._requires_tracking_task(T)),
    witnessed = Set([Octopus.kind(first(reset_line))])
    task_only == witnessed || error(
        "task-managed element kinds and executable capture/restore witnesses differ: " *
        "declared=$(task_only), witnessed=$(witnessed)")
end

# Declaration↔coverage tripwire (2026-08-05 audit, U21-5), the same rule
# SymplecticityContract applies to its case list: a kind that declares the
# contract and is missing from these lines is a silent coverage gap.
let covered = Set(Octopus.kind(spec) for spec in (line..., single_pass_line..., reset_line...))
    declaring = Symbol[]
    for T in Octopus.registered_element_specs()
        meta = Octopus._element_meta_or_nothing(T)
        meta === nothing && continue
        any(C -> C === ElementTrackingBackendConsistencyContract, meta.contracts) &&
            push!(declaring, meta.kind)
    end
    uncovered = sort!(setdiff(declaring, covered))
    isempty(uncovered) || error(
        "kinds declare ElementTrackingBackendConsistencyContract but are " *
        "missing from these lines: " * join(uncovered, ", "))
end

# Rule↔wrap tripwire (2026-10-16 neighbour audit, S2-1): every kind whose
# parameters admit a turn-modulation rule (a `phase_noise` parameter, derived
# from the schemas, never listed) must reach the line through a `TurnModulated`
# wrap at least once, or the wrap, its device conversion and the per-turn
# update are covered by name only -- the gap this script had until the
# modulated cases above joined it.
let wrapped = Set(Octopus.kind(spec) for spec in line
                  if compile_runtime(spec) isa Octopus.TurnModulated),
    modulatable = Symbol[meta.kind for T in Octopus.registered_element_specs()
                         for meta in (Octopus._element_meta_or_nothing(T),)
                         if meta !== nothing && haskey(Octopus.parameter_schema(T), :phase_noise)]
    isempty(modulatable) && error("no element kind declares a phase_noise parameter; the wrap tripwire has nothing to check")
    unwrapped = sort!(setdiff(modulatable, wrapped))
    isempty(unwrapped) || error(
        "the backend-consistency line carries no modulated instance of " *
        join(unwrapped, ", ") * ": the TurnModulated wrap, its device conversion and the " *
        "per-turn update_line would be covered by name only")
end

cpu_cpu = ElementTrackingBackendConsistencyContract(;
    line=line,
    n_particles=N,
    turns=turns,
    backend_a=CPUThreadsBackend,
    backend_b=CPUThreadsBackend,
    seed=seed,
    rng_method=:philox,
    atol=atol,
    rtol=rtol,
)
cpu_cpu_result = validate(cpu_cpu)
_print_result("CPU/CPU tracking backend consistency", cpu_cpu_result)
cpu_cpu_result.passed || error("CPU/CPU tracking backend consistency failed")

should_run_gpu = run_gpu == "auto" ? _cuda_visible() : _bool_env("OCTOPUS_RUN_GPU_CONTRACT", false)
if should_run_gpu || require_gpu
    cpu_gpu = ElementTrackingBackendConsistencyContract(;
        line=line,
        n_particles=N,
        turns=turns,
        backend_a=CPUThreadsBackend,
        backend_b=CUDABackend,
        seed=seed,
        rng_method=:philox,
        atol=atol,
        rtol=rtol,
    )
    cpu_gpu_result = validate(cpu_gpu)
    _print_result("CPU/GPU tracking backend consistency", cpu_gpu_result)
    if cpu_gpu_result.status == :skipped && require_gpu
        error("CPU/GPU tracking backend consistency was required but skipped")
    end
    cpu_gpu_result.status == :failed && error("CPU/GPU tracking backend consistency failed")
else
    println("CPU/GPU tracking backend consistency")
    println("  status = skipped")
    println("  message = CUDA check not requested and CUDA is not visible to Julia.")
end

# --- the accelerating cavity, single-pass by contract -------------------------
single_pass_backends = Tuple{DataType,String}[(CPUThreadsBackend, "CPU/CPU")]
(should_run_gpu || require_gpu) && push!(single_pass_backends, (CUDABackend, "CPU/GPU"))
for (backend_b, label) in single_pass_backends
    result = validate(ElementTrackingBackendConsistencyContract(;
        line=single_pass_line, n_particles=N, turns=1,
        backend_a=CPUThreadsBackend, backend_b=backend_b,
        seed=seed, rng_method=:philox, atol=atol, rtol=rtol))
    _print_result("$(label) accelerating-cavity single-pass consistency", result)
    if result.status == :skipped
        require_gpu && error("$(label) accelerating-cavity single-pass consistency was required but skipped")
        continue
    end
    result.status == :failed && error("$(label) accelerating-cavity single-pass consistency failed")
    # Not allowed to go vacuous: the arm exists to compare a map.
    result.metrics[:compared_coordinates] > 0 ||
        error("accelerating-cavity single-pass consistency compared nothing")
end

# --- reset, with a reference that does not call the reset implementation ------
for (backend_b, label) in single_pass_backends
    result = validate(ElementTrackingBackendConsistencyContract(;
        line=reset_line, n_particles=N, turns=reset_turns,
        backend_a=CPUThreadsBackend, backend_b=backend_b,
        seed=seed, rng_method=:philox, atol=atol, rtol=rtol))
    _print_result("$(label) phase-space reset consistency", result)
    if result.status == :skipped
        require_gpu && error("$(label) phase-space reset consistency was required but skipped")
        continue
    end
    result.passed || error("$(label) phase-space reset consistency failed")
    base = Octopus._contract_default_initial_rep(N, Float64)
    trial_rep = Octopus._contract_rep_for_backend(base, backend_b)
    reference = Octopus._contract_rep_for_backend(base, backend_b)
    policy = Octopus._contract_policy(backend_b)
    execute!(TrackingTask(reset_line; policy=policy), trial_rep; turns=reset_turns)
    execute!(TrackingTask(Base.tail(reset_line); policy=policy), reference; turns=1)
    all(isequal(Array(a), Array(b)) for (a, b) in
        zip(coordinate_arrays(trial_rep), coordinate_arrays(reference))) || error(
        "phase-space reset did not reproduce the independently copied one-turn reference")
    !isequal(Array(reference.px), Array(base.px)) || error(
        "phase-space reset witness has no kick: a no-op reset could pass")
end

# --- the aperture, actually exercised -----------------------------------------
#
# `:aperture` is in the line above, and until now that was ALL it was: the
# committed limits are 1 m against a beam of ~1e-4 m, so no particle could ever
# reach the ellipse and the element was the identity map on both backends. The
# one behaviour an aperture has -- killing a particle -- was never executed
# (2026-08-05_b audit, U25-4).
#
# It could not be fixed in place, for two reasons, and both are now dealt with:
#
#   1. `_aperture_kill` writes NaN into all six coordinates, and the contract
#      comparator turned a single NaN into a NaN metric and a failed run even
#      when both backends killed exactly the same particles. The comparator now
#      counts identical losses as the agreement they are, and fails only when
#      the two backends DISAGREE about who died.
#   2. Tightening the in-line aperture is not stable. Every element upstream
#      shapes the beam by the time it reaches the aperture -- measured, a 1 mm
#      ellipse kills all 10000 particles there -- and the coverage tripwire
#      obliges future authors to ADD elements to that line, which moves the
#      distribution again. Any hand-tuned limit would drift to 0% or 100%.
#
# So the aperture gets its own arm, on the initial distribution, where the beam
# is known and fixed by `_contract_default_initial_rep`: |x| <= 1e-4,
# |y| <= 8e-5. The limits below cut well inside that, so the kill fraction is a
# property of two constants rather than of the whole line.
aperture_line = (ApertureSpec(shape=:ellipse, x_limit=7.0e-5, y_limit=5.6e-5),)
aperture_backends = Tuple{DataType,String}[(CPUThreadsBackend, "CPU/CPU")]
(should_run_gpu || require_gpu) && push!(aperture_backends, (CUDABackend, "CPU/GPU"))
for (backend_b, label) in aperture_backends
    result = validate(ElementTrackingBackendConsistencyContract(;
        line=aperture_line, n_particles=N, turns=1,
        backend_a=CPUThreadsBackend, backend_b=backend_b,
        seed=seed, rng_method=:philox, atol=atol, rtol=rtol))
    _print_result("$(label) aperture loss consistency", result)
    if result.status == :skipped
        require_gpu && error("$(label) aperture loss consistency was required but skipped")
        continue
    end
    result.status == :failed && error("$(label) aperture loss consistency failed")
    # The check must not be allowed to go quietly vacuous. If a future change to
    # the initial distribution or the limits stops the aperture killing anything,
    # this arm silently reverts to covering :aperture by name -- which is the
    # exact defect it was added to close. Survivors are equally required: with
    # every particle dead there is no map left to compare.
    lost = result.metrics[:lost_both_backends]
    compared = result.metrics[:compared_coordinates]
    lost > 0 || error("aperture loss consistency killed no particle: the aperture " *
                      "is being covered by name only again (limits vs distribution)")
    compared > 0 || error("aperture loss consistency killed every particle: nothing " *
                          "was compared, so the arm proves nothing")
    result.metrics[:lost_one_backend] == 0 ||
        error("backends disagree about which particles the aperture killed: " *
              "$(result.metrics[:lost_one_backend]) coordinate(s)")
    println("  killed ", lost, " of ", lost + compared,
            " coordinate slots, compared ", compared)
end

# --- per kind, against the declared cross-backend rounding class -------------
#
# Every instance of the lines above, tracked ALONE (so one kind's class meets
# its own measurement, not the line's mixture), on the CPU twice and on the
# CPU against CUDA. The CPU/CPU pair must be bitwise in every coordinate: the
# fused elementwise path has no shared reduction and the counter RNG is keyed
# by particle index. The CPU/CUDA pair must satisfy the kind's declared class
# (`_cross_backend_rounding`; the header states the rule): a bitwise coordinate
# to the bit, a ulp-class coordinate within the declared bound in ulps of its
# scale over the beam. The accelerating cavity is single-pass (one turn); the
# killing aperture of the arm above joins so a kill is checked against the
# class too (NaN on both backends is agreement, NaN on one is a violation the
# comparator counts by name). A violation fails the run by name.
println("\nPer-kind cross-backend rounding classes (CrossBackendRounding, src/track/Track.jl)")
println("  per coordinate: measured B (bitwise) or ulps of the coordinate's scale / declared u (ulp), b (bitwise), - (untouched)")
let violations = String[],
    cases = Tuple{String,Any,Int}[]
    for spec in line
        runtime = compile_runtime(spec)
        tag = runtime isa Octopus.TurnModulated ? " (modulated)" :
              runtime isa Octopus.MisalignedElement ? " (misaligned)" : ""
        push!(cases, (string(Octopus.kind(spec)) * tag, spec, turns))
    end
    for spec in single_pass_line
        push!(cases, (string(Octopus.kind(spec)) * " (single pass)", spec, 1))
    end
    push!(cases, ("phase_space_reset (mutate/restore)", first(reset_line), reset_turns))
    push!(cases, ("aperture (killing)", aperture_line[1], 1))
    gpu_arm = should_run_gpu || require_gpu
    gpu_arm && !_cuda_visible() && require_gpu &&
        error("per-kind cross-backend rounding classes were required on CUDA but no device is visible")
    old_seed = global_rng_seed()
    old_method = global_rng_method()
    try
        for (label, spec, nturns) in cases
            class = Octopus._cross_backend_rounding(compile_runtime(spec))
            base = Octopus._contract_default_initial_rep(N, Float64)
            run_on(backend) = begin
                rep = Octopus._contract_rep_for_backend(base, backend)
                set_global_rng!(seed=seed, method=:philox)
                task = TrackingTask((spec,); policy=Octopus._contract_policy(backend))
                if spec isa ElementSpec{:phase_space_reset}
                    execute!(task, rep; turns=1)
                    for (i, array) in enumerate(coordinate_arrays(rep))
                        array .+= eltype(array)(i + 1)
                    end
                    execute!(task, rep; turns=nturns - 1)
                    all(isequal(Array(a), Array(b)) for (a, b) in
                        zip(coordinate_arrays(rep), coordinate_arrays(base))) || error(
                        "$(label): mutation was not undone by an independent saved reference")
                else
                    execute!(task, rep; turns=nturns)
                end
                rep
            end
            cpu_a = run_on(CPUThreadsBackend)
            cpu_b = run_on(CPUThreadsBackend)
            cpu_cpu = Octopus._cross_backend_agreement(cpu_a, cpu_b)
            for k in Octopus._COORDINATE_NAMES
                getfield(cpu_cpu, k).bitwise || push!(violations,
                    "$(label): CPU/CPU $(k) not bitwise (max |a - b| = $(getfield(cpu_cpu, k).max_abs))")
            end
            if gpu_arm && _cuda_visible()
                gpu = run_on(CUDABackend)
                Octopus.CUDA.synchronize()
                agreement = Octopus._cross_backend_agreement(cpu_a, gpu)
                println("  ", rpad(label, 36), Octopus._cross_backend_summary(class, agreement))
                append!(violations, Octopus._cross_backend_violations(class, agreement; label=label))
            else
                println("  ", rpad(label, 36), "CPU/CPU bitwise; CPU/GPU not run (declared ", join((string(getfield(class, k))[1] for k in Octopus._COORDINATE_NAMES)), ")")
            end
        end
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end
    isempty(violations) || error("per-kind cross-backend rounding classes violated (the declaration or the kernel is wrong; the measurement wins):\n  " *
                                 join(violations, "\n  "))
    println("  per-kind cross-backend rounding classes: ", length(cases), " instances within their declared classes",
            gpu_arm && _cuda_visible() ? " on CPU/CPU and CPU/GPU" : " on CPU/CPU (CPU/GPU not run)")
end

println("tracking backend consistency validation complete")
