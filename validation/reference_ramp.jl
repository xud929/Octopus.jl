#=
Validate the reference ramp (docs/theory/reference_ramp.md, section 4,
targets 2 and 3b) on the F16 ring of the suite: C = 100 m as a pure drift, a
Linear6D R56 = -alpha_c C with alpha_c = 0.2, one ThinRFCavitySpec at
harmonic 1 built on the knob reference, a proton ramped from 2.5 to 3.5 GeV
linearly over 10,000 turns (100 keV per turn, V = 200 kV, sin(phi_s) = 0.5),
the ReferenceRamp last in the line.

  * Target 2 -- the synchrotron tune follows the program. A particle at
    delta = 1e-4, z = 0 with phi = phi_s programmed; its z series is cut into
    windows of 2,000 turns and the tune of each window (the F16 testset's
    Hann-windowed DTFT estimator) is compared with the linearised one-turn
    map's tune at the window's mid-turn energy,
        cos(2 pi nu_s) = 1 - pi h eta(E) qV cos(phi_s) / (beta0(E)^2 E),
        eta(E) = alpha_c - 1/gamma0(E)^2,
    within 1%. Along the ramp eta goes from 0.059 to 0.128 and E by 1.4, so
    the window tunes differ by a factor near 1.2.
  * Target 3b -- bucket motion. With phi = 0 held and the same program, the
    synchronous point moves to sin(2 pi h z1 / C) = dE_ref / qV, i.e.
    z1 = C asin(0.5) / (2 pi h) = 8.333 m in the z coordinate (beta0 drops
    out of the phase 2 pi h z / C); a particle launched 0.5 m from it
    oscillates about it, and the mean of z over each window is within 1% of
    z1.
  * The cost of the per-turn recompile: the ramped ring's wall time per turn
    against the same ring with a flat program (no step, no recompile), and
    against a 40-cell FODO line with the cavity, both on one thread.

Writes `reference_ramp_validation.txt` under OCTOPUS_RESULT_DIR (default
result/) with the per-window table; the verdict is the last line. Run from
the project root:

    julia --project=. --threads=1 validation/reference_ramp.jl

CPU only; no GATE-CUDA-ARM header (the device twin of the boundary map is
pinned in the suite, "Reference ramp: the synchronous particle is the fixed
point of the ramped ring, and the device map is the host's bit for bit").
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Printf

const C = 100.0
const ALPHA_C = 0.2
const H = 1
const V = 2.0e5
const DE = 1.0e5
const TURNS = 10_000
const WINDOW = 2_000
const E_START = 2.5e9

@knob ramp_validation.E0 = 2.5e9
const REF = ReferenceParticle(:proton; E0=@knob_expr(ramp_validation.E0))
const PROGRAM = [E_START + DE * n for n in 0:TURNS]
const CPU = CPUThreadsExecutionPolicy(threads=1)

r56() = Linear6DSpec(matrix=[1.0 0 0 0 0 0; 0 1.0 0 0 0 0; 0 0 1.0 0 0 0; 0 0 0 1.0 0 0;
                             0 0 0 0 1.0 -ALPHA_C * C; 0 0 0 0 0 1.0])
ring(phase, program) = (DriftSpec(L=C), r56(),
                        ThinRFCavitySpec(; harmon=H, voltage=V, phase=phase, reference=REF),
                        ReferenceRamp(program; reference=REF, name="validation"))

# The F16 testset's tune estimator: FFT coarse bin, then golden-section
# refinement of the Hann-windowed DTFT magnitude (unbiased to ~1e-7).
function tune(zseries)
    N = length(zseries)
    zc = zseries .- sum(zseries) / N
    w = [0.5 - 0.5 * cospi(2 * (n - 1) / N) for n in 1:N]
    wz = w .* zc
    amp = nu -> abs(sum(wz[n] * cispi(-2 * nu * (n - 1)) for n in 1:N))
    a = abs.(Octopus.FFTW.rfft(wz))
    kbin = argmax(a[2:end]) + 1
    lo = (kbin - 2) / N
    hi = kbin / N
    gr = (sqrt(5) - 1) / 2
    c = hi - gr * (hi - lo)
    d = lo + gr * (hi - lo)
    for _ in 1:60
        if amp(c) > amp(d)
            hi = d
        else
            lo = c
        end
        c = hi - gr * (hi - lo)
        d = lo + gr * (hi - lo)
    end
    return (lo + hi) / 2
end

function nu_predicted(E, phis)
    b0, g0 = reference_beta_gamma(E, PMASS_EV)
    eta = ALPHA_C - 1 / g0^2
    return acos(1 - pi * H * eta * V * cos(phis) / (b0^2 * E)) / (2pi)
end

"Track one particle through the ramped ring, one window at a time, returning the z series."
function track_z(phase, z0, delta0)
    set_knob!("ramp_validation.E0", E_START)
    rep = Phase6DRep([0.0], [0.0], [0.0], [0.0], [z0], [delta0])
    task = TrackingTask(ring(phase, PROGRAM); policy=CPU)
    zs = Vector{Float64}(undef, TURNS)
    for n in 1:TURNS
        execute!(task, rep; turns=1)
        zs[n] = rep.z[1]
    end
    return zs, rep
end

function main()
    outdir = get(ENV, "OCTOPUS_RESULT_DIR", joinpath(@__DIR__, "..", "result"))
    mkpath(outdir)
    io = IOBuffer()
    println(io, "reference ramp validation (docs/theory/reference_ramp.md, section 4): F16 ring, C = $(C) m, alpha_c = $(ALPHA_C), h = $(H), V = $(V) V, dE = $(DE) eV per turn, $(TURNS) turns, windows of $(WINDOW)")
    phis = asin(DE / V)
    ok = true

    # Target 2.
    zs, rep_end = track_z(phis, 0.0, 1.0e-4)
    println(io, "\ntarget 2: nu_s per window against the linearised map at the window's mid-turn energy (phi = phi_s = $(phis) rad)")
    println(io, "| window (turns) | E0 mid [GeV] | eta mid | nu_s measured | nu_s predicted | ratio |")
    println(io, "|---|---|---|---|---|---|")
    worst2 = 0.0
    for w in 1:(TURNS ÷ WINDOW)
        lo = (w - 1) * WINDOW + 1
        hi = w * WINDOW
        Emid = PROGRAM[(lo + hi) ÷ 2 + 1]
        nu_m = tune(zs[lo:hi])
        nu_p = nu_predicted(Emid, phis)
        _, g0 = reference_beta_gamma(Emid, PMASS_EV)
        ratio = nu_m / nu_p
        worst2 = max(worst2, abs(ratio - 1))
        @printf(io, "| %d-%d | %.4f | %.4f | %.6e | %.6e | %.5f |\n", lo - 1, hi - 1, Emid / 1e9, ALPHA_C - 1 / g0^2, nu_m, nu_p, ratio)
    end
    @printf(io, "worst |ratio - 1| = %.2e (tolerance 1e-2); knob at the end %.6e eV (program's last entry %.6e)\n", worst2, knob_value("ramp_validation.E0"), PROGRAM[end])
    ok &= worst2 < 1.0e-2 && knob_value("ramp_validation.E0") == PROGRAM[end]

    # Target 3a, as the suite pins it, re-measured here on the full ramp.
    zs0, rep0 = track_z(phis, 0.0, 0.0)
    @printf(io, "\ntarget 3a: the synchronous particle over the full ramp: max |z| = %.3e m, final |delta| = %.3e (tolerance 1e-9 each)\n", maximum(abs, zs0), abs(rep0.pz[1]))
    ok &= maximum(abs, zs0) < 1.0e-9 && abs(rep0.pz[1]) < 1.0e-9

    # Target 3b.
    z1 = C * asin(DE / V) / (2pi * H)
    zb, _ = track_z(0.0, z1 + 0.5, 0.0)
    println(io, "\ntarget 3b: phi = 0 held; the bucket centre z1 = C asin(dE/qV)/(2 pi h) = $(z1) m; a particle launched at z1 + 0.5 m")
    println(io, "| window (turns) | mean z [m] | mean z / z1 | z range [m] |")
    println(io, "|---|---|---|---|")
    worst3 = 0.0
    for w in 1:(TURNS ÷ WINDOW)
        lo = (w - 1) * WINDOW + 1
        hi = w * WINDOW
        seg = zb[lo:hi]
        mz = sum(seg) / length(seg)
        worst3 = max(worst3, abs(mz / z1 - 1))
        @printf(io, "| %d-%d | %.5f | %.5f | %.4f .. %.4f |\n", lo - 1, hi - 1, mz, mz / z1, minimum(seg), maximum(seg))
    end
    @printf(io, "worst |mean z / z1 - 1| = %.2e (tolerance 1e-2)\n", worst3)
    ok &= worst3 < 1.0e-2

    # The recompile cost, per turn, on one thread.
    function seconds_per_turn(elements, program_end)
        set_knob!("ramp_validation.E0", E_START)
        rep = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [1.0e-4])
        task = TrackingTask(elements; policy=CPU)
        execute!(task, rep; turns=1)                       # compile and warm
        set_knob!("ramp_validation.E0", E_START)
        rep = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [1.0e-4])
        task = TrackingTask(elements; policy=CPU)
        t = @elapsed execute!(task, rep; turns=2000)
        knob_value("ramp_validation.E0") == program_end || error("the timing run did not end on the program's last entry")
        return t / 2000
    end
    flat = fill(E_START, TURNS + 1)
    t_ramp = seconds_per_turn(ring(phis, PROGRAM), PROGRAM[2001])
    t_flat = seconds_per_turn(ring(phis, flat), E_START)
    cells = [k % 4 == 1 ? QuadrupoleSpec(L=0.3, k1=0.8) : k % 4 == 3 ? QuadrupoleSpec(L=0.3, k1=-0.8) : DriftSpec(L=0.95) for k in 1:160]
    fodo(program) = (cells..., ThinRFCavitySpec(; harmon=H, voltage=V, phase=phis, reference=REF),
                     ReferenceRamp(program; reference=REF, name="fodo"))
    t_fodo_ramp = seconds_per_turn(fodo(PROGRAM), PROGRAM[2001])
    t_fodo_flat = seconds_per_turn(fodo(flat), E_START)
    println(io, "\nthe per-turn recompile (one particle, one thread, 2,000 turns, the program stepping every turn against a flat program):")
    @printf(io, "| line | s/turn, stepping | s/turn, flat | overhead per step [s] |\n|---|---|---|---|\n| F16 ring (4 entries) | %.3e | %.3e | %.3e |\n| 40-cell FODO + cavity (162 entries) | %.3e | %.3e | %.3e |\n",
            t_ramp, t_flat, t_ramp - t_flat, t_fodo_ramp, t_fodo_flat, t_fodo_ramp - t_fodo_flat)

    verdict = ok ? "reference ramp validation passed" : "reference ramp validation FAILED"
    println(io, "\n", verdict)
    text = String(take!(io))
    path = joinpath(outdir, "reference_ramp_validation.txt")
    write(path, text)
    print(text)
    println("written: ", path)
    ok || exit(1)
    return nothing
end

main()
