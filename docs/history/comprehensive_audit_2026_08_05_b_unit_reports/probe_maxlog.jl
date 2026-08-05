# U19 probe: does the Spectral arm of runtests.jl:4733 exhaust the process-wide
# maxlog=8 budget of the CPU spectral dropped-charge tripwire (spectral.jl:411)?
using Octopus, Logging, Printf
function loss_test_coords(N)
    s(scale,phase) = [scale*sin(0.7*i+phase) for i in 1:N]
    Dict(:x=>s(1e-4,0.0), :px=>s(1e-5,0.3), :y=>s(1e-4,0.9), :py=>s(1e-5,1.2),
         :z=>s(1e-2,2.0), :pz=>s(1e-4,2.5))
end
const LF = (:x,:pz,:py,:z,:px,:y)
function loss_test_rep(N, dead; values=nothing)
    c = loss_test_coords(N)
    for (k,d) in enumerate(dead); f = LF[mod1(k,6)];
        c[f][d] = values === nothing ? (isodd(k) ? NaN : Inf) : values; end
    Phase6DRep(c[:x],c[:px],c[:y],c[:py],c[:z],c[:pz])
end
tb(rep) = (p = BeamParams{Float64}(charge=1.0,mc2=1.0,E0=1.0,r0=1.0,npart=length(rep));
           Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))
N = 4000; dead = [5,137,2011]
sl = LongitudinalSlicing(nslices=3, method=:equal_count)
clean() = Phase6DRep((loss_test_coords(N)[k] for k in (:x,:px,:y,:py,:z,:pz))...)
spec = SpectralPoissonSolver(kbb1=1e-4,kbb2=1e-4,luminosity_scale=1.0,grid=(64,64),slicing=sl)

# capture what the DEFAULT (maxlog-aware) logger would print, via a SimpleLogger
buf = IOBuffer()
with_logger(SimpleLogger(buf, Logging.Info)) do
    allow_lost_particles() do
        for v in 1:3
            collide!(spec, tb(loss_test_rep(N, dead)), tb(clean()), CPUThreadsBackend)
        end
    end
    # a LATER, genuinely clipping spectral collide in the same process
    global marker_before = count(l -> occursin("clipped charge", l), split(String(take!(copy(buf))), "\n"))
    collide!(spec, tb(clean()), tb(clean()), CPUThreadsBackend)
end
s = String(take!(buf))
tot = count(i -> true, findall("clipped charge", s))
@printf("tripwire messages emitted under a maxlog-aware logger: %d (maxlog=8)\n", tot)
@printf("=> after the corpse testset the tripwire is %s for the rest of the process\n",
        tot <= 8 ? "SILENT" : "still live")
