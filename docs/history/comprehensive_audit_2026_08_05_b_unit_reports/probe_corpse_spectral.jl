# U19 probe: does the Spectral arm of "Lost particles cannot influence a
# strong-strong collision" (runtests.jl:4733) run in a wall-clipped regime,
# and can the corpse-variant equality see a corpse leak there?
using Octopus, Logging, Printf

function loss_test_coords(n)
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    Dict(:x => s(1.0e-4,0.0), :px => s(1.0e-5,0.3), :y => s(1.0e-4,0.9),
         :py => s(1.0e-5,1.2), :z => s(1.0e-2,2.0), :pz => s(1.0e-4,2.5))
end
const LF = (:x, :pz, :py, :z, :px, :y)
function loss_test_rep(n, dead; values=nothing)
    c = loss_test_coords(n)
    for (k,d) in enumerate(dead)
        f = LF[mod1(k,6)]
        c[f][d] = values === nothing ? (isodd(k) ? NaN : Inf) : values
    end
    Phase6DRep(c[:x],c[:px],c[:y],c[:py],c[:z],c[:pz])
end
loss_survivor_rep(n, dead) = (c = loss_test_coords(n); keep = setdiff(1:n, dead);
    Phase6DRep((c[k][keep] for k in (:x,:px,:y,:py,:z,:pz))...))
test_beam(rep) = (p = BeamParams{Float64}(charge=1.0,mc2=1.0,E0=1.0,r0=1.0,npart=length(rep));
    Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))

n = 4000; dead = [5, 137, 2011]
sl = LongitudinalSlicing(nslices=3, method=:equal_count)
clean_rep() = Phase6DRep((loss_test_coords(n)[k] for k in (:x,:px,:y,:py,:z,:pz))...)
function corpse(v)
    v == 1 && return loss_test_rep(n, dead)
    v == 2 && return loss_test_rep(n, dead; values=NaN)
    c = loss_test_coords(n)
    for d in dead; c[:pz][d]=Inf; c[:x][d]=1.0e3; c[:y][d]=-1.0e3; end
    Phase6DRep(c[:x],c[:px],c[:y],c[:py],c[:z],c[:pz])
end

struct Counter <: AbstractLogger; n::Base.RefValue{Int}; fr::Vector{Float64}; end
Logging.min_enabled_level(::Counter) = Logging.Debug
Logging.shouldlog(::Counter, args...) = true
Logging.catch_exceptions(::Counter) = false
function Logging.handle_message(l::Counter, lvl, msg, mod, grp, id, file, line; kwargs...)
    if occursin("clipped charge", string(msg))
        l.n[] += 1
        haskey(kwargs, :dropped_fraction) && push!(l.fr, Float64(kwargs[:dropped_fraction]))
    end
end
function counted(f)
    c = Counter(Ref(0), Float64[])
    v = with_logger(f, c)
    (v, c.n[], isempty(c.fr) ? (NaN,NaN) : (minimum(c.fr), maximum(c.fr)))
end

solvers = (
 ("PIC",       PICPoissonSolver(kbb1=1e-4,kbb2=1e-4,luminosity_scale=1.0,grid=(64,64),green_cache=:none,slicing=sl)),
 ("Gaussian",  GaussianPoissonSolver(kbb1=1e-4,kbb2=1e-4,luminosity_scale=1.0,slicing=sl)),
 ("Spectral",  SpectralPoissonSolver(kbb1=1e-4,kbb2=1e-4,luminosity_scale=1.0,grid=(64,64),slicing=sl)),
)
for (name, solver) in solvers
    # exact test-as-written arm
    (values, nw, fr) = counted() do
        allow_lost_particles() do
            [collide!(solver, test_beam(corpse(v)), test_beam(clean_rep()), CPUThreadsBackend) for v in 1:3]
        end
    end
    # clean/clean control: does the CONFIGURATION itself clip, corpses aside?
    (_, nw0, fr0) = counted() do
        collide!(solver, test_beam(clean_rep()), test_beam(clean_rep()), CPUThreadsBackend)
    end
    # survivors-only reference (npart differs by construction, as in the test)
    (lsurv, _, _) = counted() do
        collide!(solver, test_beam(loss_survivor_rep(n, dead)), test_beam(clean_rep()), CPUThreadsBackend)
    end
    @printf("%-9s values=%s\n", name, string(values))
    @printf("%-9s equal123=%s  clip-warnings(corpse arms)=%d frac∈[%.3g,%.3g]  clip(clean/clean)=%d frac∈[%.3g,%.3g]\n",
            "", string(values[1]==values[2]==values[3]), nw, fr[1], fr[2], nw0, fr0[1], fr0[2])
    @printf("%-9s survivors-only lum=%.17g  reldiff vs masked=%.4g\n\n", "", lsurv,
            abs(lsurv - values[1]) / abs(lsurv))
end
