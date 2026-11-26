#=
Per-element-type timing for the BBSCL comparison (follow-up to case L): one-turn
linear map (Linear6DSpec) plus OCT_COUNT copies of one element kind, 1,048,576
particles, time per turn after warm-up. OCT_KIND = map | drift | quad | sext | bend.
Element literals are those of case L (octopus_lattice_bbscl.jl): D 1.8/2.0 m,
Q 0.5 m k1 = +-0.36, S 0.2 m k2 = 1.0/-2.0, B 3.0 m angle 2 pi/16 with bend_fringe.
OCT_DUMP=dir dumps the fused kernel's code forms (CUDA.@device_code) for the static
instruction count; the occupancy cache is printed after the run.
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "..", "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics, Printf
import CUDA

envi(n, d) = parse(Int, get(ENV, n, string(d)))
const KIND   = lowercase(get(ENV, "OCT_KIND", "drift"))
const COUNT  = envi("OCT_COUNT", 16)
const N      = envi("OCT_N", 1_048_576)
const TURNS  = envi("OCT_TURNS", 40)
const WARMUP = envi("OCT_WARMUP", 10)
const NST    = envi("OCT_NST", 1)
const ORDER  = envi("OCT_ORDER", 2)
const BFR    = envi("OCT_BEND_FRINGE", 1) == 1
const SEED   = envi("OCT_SEED", 123456789)
const DUMP   = get(ENV, "OCT_DUMP", "")
const MAXREGS = envi("OCT_MAXREGS", 0)
tag = "$(KIND)_c$(COUNT)_nst$(NST)_o$(ORDER)" * (KIND == "bend" ? (BFR ? "_fr" : "_nofr") : "")
const OUT = get(ENV, "OCT_OUT", joinpath(@__DIR__, "octopus_T_" * tag * ".tsv"))

const E0 = 275.0e9
# One-turn-map optics per kind (alpha = 0), chosen so that the string plus the map is linearly
# stable (2 x 2 model: |Tr| < 1.2 in both planes); gen_bbscl_T.py uses the same table.
function map_optics(kind, count)
    kind == "drift" && return (count > 32 ? 400.0 : 100.0, count > 32 ? 400.0 : 100.0, 0.25, 0.26)
    kind in ("quad", "split", "thinq") && return (25.0, 25.0, 0.10, 0.10)
    kind == "sext"  && return (16.0, 16.0, 0.25, 0.26)
    kind == "bend"  && return (16.0, 100.0, 0.25, 0.26)
    return (16.0, 5.0, 0.31, 0.32)      # map only
end
bx, by, qx, qy = map_optics(KIND, COUNT)
ax, ay = 0.0, 0.0
bz = 88.69436505611495 * 8          # the case L one-cell beta_z scaled to 8 cells
const TUNES = (qx, qy, 0.0082)
println("one-turn map optics: beta = ($bx, $by, $bz)  alpha = 0  tunes = $TUNES")
point = LinearOptics(; beta = (bx, by, bz), alpha = (ax, ay, 0.0))
onemap = Linear6DSpec(point, point; dmu = 2pi .* TUNES)

function make_elements(kind, count)
    el = Any[]
    for k in 1:count
        if kind == "drift"
            push!(el, DriftSpec(; L = isodd(k) ? 1.8 : 2.0))
        elseif kind == "quad"
            push!(el, QuadrupoleSpec(; L = 0.5, k1 = isodd(k) ? 0.36 : -0.36, nst = NST, integrator_order = ORDER, fringe = :none))
        elseif kind == "sext"
            push!(el, SextupoleSpec(; L = 0.2, k2 = isodd(k) ? 1.0 : -2.0, nst = NST, integrator_order = ORDER, fringe = :none))
        elseif kind == "bend"
            push!(el, SBendSpec(; L = 3.0, angle = 2pi / 16, nst = NST, integrator_order = ORDER, bend_fringe = BFR, fringe = :none))
        elseif kind == "split"      # the Strang step written out: drift, thin quadrupole kick, drift
            push!(el, DriftSpec(; L = 0.25)); push!(el, ThinQuadrupoleSpec(; k1l = isodd(k) ? 0.18 : -0.18)); push!(el, DriftSpec(; L = 0.25))
        elseif kind == "thinq"      # the thin quadrupole kick alone
            push!(el, ThinQuadrupoleSpec(; k1l = isodd(k) ? 0.18 : -0.18))
        elseif kind == "map"
            break
        else
            error("unknown OCT_KIND $kind")
        end
    end
    return el
end

elements = make_elements(KIND, COUNT)
line_elems = Any[onemap]; append!(line_elems, elements)
line = Tuple(line_elems)
const NLOGICAL = KIND == "split" ? length(elements) ÷ 3 : length(elements)
println("kind=$KIND count=$(NLOGICAL) specs=$(length(elements)) line length=$(length(line)) nst=$NST order=$ORDER bend_fringe=$BFR N=$N turns=$TURNS")

CUDA.functional(false) || error("CUDA is not functional")
MAXREGS > 0 && include(joinpath(@__DIR__, "maxregs_override.jl"))
policy = CUDAExecutionPolicy()
set_global_rng!(seed = SEED, method = :philox)
emit_z = (bz * 1.0e-7) * 1.0e-7
beam = Beam(N, policy, Float64; optics = point, emit = (1.0e-8, 1.0e-8, emit_z), cutoff = 5.0, rng_id = 1,
            charge = 1.0, mc2 = PMASS_EV, E0 = E0, npart = 1.0e11,
            initial_offset = (1.0e-4, 0.0, 1.0e-4, 0.0, 1.0e-3, 0.0))
artifact = RunArtifact(; storage = :memory, capacity = 1024)
task = TrackingTask(line; policy = policy, artifact = artifact, record_turn_times = true)
s0 = beam_statistics(beam)
t0 = time()
if DUMP != ""
    mkpath(DUMP)
    dio = open(joinpath(DUMP, "all.ptx"), "w")
    CUDA.@device_code_ptx io=dio dump_module=true execute!(task, beam; turns = 1)
    close(dio)
    tcomp = time() - t0
    println("compile+1 turn with code dump: $(round(tcomp, digits=1)) s -> $DUMP")
    t0 = time()
end
execute!(task, beam; turns = TURNS)
CUDA.synchronize()
wall = time() - t0
times = turn_timings(task)
s1 = beam_statistics(beam)
sel = (WARMUP + 1):TURNS
tt = times[sel]
@printf("kind=%s count=%d nst=%d order=%d bend_fringe=%s N=%d turns=%d\n", KIND, NLOGICAL, NST, ORDER, BFR, N, TURNS)
@printf("wall(execute!)=%.3f s  mean/turn (turns %d-%d) = %.6f s  median = %.6f s  sd = %.6f s  min = %.6f max = %.6f\n",
        wall, first(sel), last(sel), mean(tt), median(tt), std(tt), minimum(tt), maximum(tt))
println("rms initial = ", s0.rms)
println("rms final   = ", s1.rms)
println("mean final  = ", s1.mean)
for (k, v) in Octopus._CUDA_FUSED_OCCUPANCY_CACHE
    println("occupancy: threads/block=", k[5], "  active blocks/SM=", v, "  resident warps/SM=", v * k[5] ÷ 32, "  (max 48)")
end
open(OUT, "w") do io
    println(io, "# octopus eltype  kind=$KIND count=$(length(elements)) nst=$NST order=$ORDER bend_fringe=$BFR N=$N turns=$TURNS seed=$SEED maxregs=$MAXREGS")
    println(io, "# rms_initial\t", join(s0.rms, "\t")); println(io, "# rms_final\t", join(s1.rms, "\t"))
    println(io, "turn\tseconds")
    for (k, t) in enumerate(times); println(io, k, "\t", t); end
end
println("ELTYPE done -> ", OUT)
