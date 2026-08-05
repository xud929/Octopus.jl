### U7 probe 5: BPMObserver vs docs/theory/bpm_measurement_model.md.
using Octopus, Statistics, Printf
const OUT = @__DIR__

mkrep(n = 8; x0 = 3.0e-3, y0 = -2.0e-3) =
    Phase6DRep(fill(x0, n), zeros(n), fill(y0, n), zeros(n), zeros(n), zeros(n))

pass(b) = b ? "PASS" : "**FAIL**"

println("="^72); println("BPM §7 checkable claims"); println("="^72)

# ---- §7.1 zero-error BPM reproduces the centroid exactly --------------------
rep = mkrep()
bpm = BPMObserver("z")
rx, ry = bpm_reading(bpm, 3.0e-3, -2.0e-3, 0)
st = beam_statistics(rep)
println("1 zero-error == centroid: ", pass(rx == st.mean[1] && ry == st.mean[3]),
        "  read=(", rx, ",", ry, ")  mean=(", st.mean[1], ",", st.mean[3], ")")

# ---- §7.2 every error term reaches the reading -----------------------------
base = bpm_reading(BPMObserver("b"), 3.0e-3, -2.0e-3, 0)
terms = (:x_offset => 1e-4, :y_offset => 1e-4, :tilt => 0.1, :x_gain => 0.5,
         :y_gain => 0.5, :x_readout => 1e-4, :y_readout => 1e-4,
         :x_noise => 1e-5, :y_noise => 1e-5)
inert = Symbol[]
for (f, v) in terms
    b = BPMObserver("t"; NamedTuple{(f,)}((v,))...)
    r = bpm_reading(b, 3.0e-3, -2.0e-3, 0)
    r == base && push!(inert, f)
end
println("2 every term moves the reading: ", pass(isempty(inert)), "  inert=", inert)

# ---- §7.3 MAD-X limit ------------------------------------------------------
g, bx, xt = 0.5, 7.0e-5, 3.0e-3
b = BPMObserver("m"; x_gain = g, x_readout = bx)
rx, _ = bpm_reading(b, xt, 0.0, 0)
println("3 MAD-X (1+MSCALX)x+MREX: ", pass(rx ≈ (1 + g) * xt + bx),
        "  got=", rx, " want=", (1 + g) * xt + bx)

# ---- sign convention: beam on axis, BPM displaced +1mm reads -1mm ----------
b = BPMObserver("s"; x_offset = 1.0e-3)
rx, _ = bpm_reading(b, 0.0, 0.0, 0)
println("  sign (Bmad, offset subtracts): ", pass(rx == -1.0e-3), "  read=", rx)

# ---- tilt: AT's rel = [C S; -S C] ------------------------------------------
θ = 0.37; xb, yb = 3.0e-3, -2.0e-3
b = BPMObserver("r"; tilt = θ)
rx, ry = bpm_reading(b, xb, yb, 0)
want = (cos(θ) * xb + sin(θ) * yb, cos(θ) * yb - sin(θ) * xb)
println("4 tilt == [C S; -S C]: ", pass(rx ≈ want[1] && ry ≈ want[2]),
        "  got=", (rx, ry), " want=", want)

# ---- §2 the architecture trap: misaligned zero-length marker is identity ----
u0 = (0.003, 0.0003, -0.002, -0.00022, 0.002, 0.0011)
e_plain = compile_runtime(MarkerSpec())
e_off = compile_runtime(MarkerSpec(x_offset = 1.0e-3, y_offset = -8.0e-4))
a = collect(e_plain(u0...)); c = collect(e_off(u0...))
println("2' misaligned MarkerSpec is bit-identity: ", pass(a == c),
        "  maxdiff=", maximum(abs, a .- c))

# ---- §7.4 a BPM does not perturb tracking ----------------------------------
line = (DriftSpec(L = 1.0), QuadrupoleSpec(L = 0.3, k1 = 0.4))
r1 = mkrep(4); r2 = mkrep(4)
execute!(TrackingTask(line), r1; turns = 5)
t2 = TrackingTask((line[1], ScheduledObserver(BPMObserver("p"; x_noise = 1e-5)), line[2]))
execute!(t2, r2; turns = 5)
println("5 BPM is passive (bit-identical): ",
        pass(r1.x == r2.x && r1.px == r2.px && r1.y == r2.y && r1.py == r2.py))

# ---- §7.5 noise reproducible across chunked execution ----------------------
Octopus.set_global_rng!(seed = 12345)
function run_chunks(chunks; rng_id = 777)
    b = BPMObserver("n"; x_noise = 2.0e-6, y_noise = 3.0e-6, rng_id = rng_id)
    t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(b),))
    r = mkrep(4)
    for c in chunks
        execute!(t, r; turns = c)
    end
    return copy(b.turns), copy(b.x), copy(b.y)
end
t1, x1, y1 = run_chunks((10,))
t2_, x2, y2 = run_chunks((3, 3, 4))
println("6 chunk invariance: ", pass(t1 == t2_ && x1 == x2 && y1 == y2))

# ---- noise sample statistics match sigma -----------------------------------
b = BPMObserver("q"; x_noise = 1.0e-5, rng_id = 991)
t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(b),))
execute!(t, mkrep(4); turns = 20000)
resid = b.x .- 3.0e-3
println("7 noise sigma: measured=", @sprintf("%.4e", std(resid)), " requested=1.0000e-05  ",
        pass(abs(std(resid) / 1.0e-5 - 1) < 0.05), "  mean=", @sprintf("%.3e", mean(resid)))

# ---- occurrence: two readings in one turn must be independent draws --------
b = BPMObserver("o"; x_noise = 1.0e-5, rng_id = 4242)
sched = ScheduledObserver(b)
t = TrackingTask((DriftSpec(L = 0.5), sched, DriftSpec(L = 0.5), sched))
execute!(t, mkrep(4); turns = 3)
println("8 two readings/turn -> distinct noise: ",
        pass(length(b.x) == 6 && b.x[1] != b.x[2]), "  turns=", b.turns)

# ---- all-particles-dead reading --------------------------------------------
println("9 allow_lost_particles() = ", Octopus.allow_lost_particles())
Octopus.allow_lost_particles(; enabled = true) do
    dead = Phase6DRep([NaN], [NaN], [NaN], [NaN], [NaN], [NaN])
    b = BPMObserver("d")
    t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(b),))
    execute!(t, dead; turns = 1)
    println("   all-dead beam reading = ", (b.x[1], b.y[1]))
end

# ---- discard-window idempotence for the BPM --------------------------------
p = joinpath(OUT, "bpm.tsv"); rm(p; force = true)
b = BPMObserver("w"; path = p, x_noise = 1e-6, rng_id = 31)
t = TrackingTask((DriftSpec(L = 1.0),); hooks = (ScheduledObserver(b),))
execute!(t, mkrep(4); turns = 6)
execute!(t, mkrep(4); turns = 6, start_turn = 3)
tsv = [parse(Int, first(split(l, '\t'))) for l in readlines(p)[2:end]]
println("10 BPM rewind: memory=", b.turns, "  tsv=", tsv, "  ",
        pass(b.turns == collect(0:8) && tsv == collect(0:8)))
rm(p; force = true)
