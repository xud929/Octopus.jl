# U19 probe: measured values behind the quoted tolerances, and the
# solver-family coverage of the lost-particle charge-semantics pin.
using Octopus, Printf

u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
sol(; kw...) = compile_runtime(SolenoidSpec(; kw...))
ferr(a,b) = maximum(abs, collect(a) .- collect(b))

println("== Solenoid tolerances (runtests.jl 5390-5646)")
@printf("  5400 sol(0,1.3) vs _lattice_drift            = %.3g  (atol 1e-15)\n",
        ferr(sol(L=1.3,ks=0.0)(u0...), Octopus._lattice_drift(0.0,1.3,u0...)))
@printf("  5401 sol(1e-12,1.3) vs drift                 = %.3g  (atol 1e-14)\n",
        ferr(sol(L=1.3,ks=1.0e-12)(u0...), Octopus._lattice_drift(0.0,1.3,u0...)))
rot(u,t) = (c=cos(t); s=sin(t);
    (c*u[1]-s*u[3], c*u[2]-s*u[4], s*u[1]+c*u[3], s*u[2]+c*u[4], u[5], u[6]))
@printf("  5436 axisymmetry                             = %.3g  (atol 1e-15)\n",
        ferr(sol(L=1.3,ks=1.7)(rot(u0,0.7)...), rot(sol(L=1.3,ks=1.7)(u0...),0.7)))
@printf("  5457 invertibility                           = %.3g  (atol 1e-15)\n",
        ferr(sol(L=1.3,ks=1.7,)(0,0,0,0,0,0) === nothing ? u0 : sol(L=-1.3,ks=1.7)(sol(L=1.3,ks=1.7)(u0...)...), u0))
for h in (0.05, 0.18)
    @printf("  5531 ks=0 curved(nst=400) vs exact drift h=%.2f = %.3g  (atol 1e-7)\n", h,
            ferr(sol(L=1.3,ks=0.0,h=h,nst=400)(u0...), Octopus._lattice_drift(h,1.3,u0...)))
end
exact = collect(sol(L=1.3,ks=1.7)(u0...))
flat(n) = maximum(abs.(collect(sol(L=1.3,ks=1.7,h=1.0e-12,nst=n)(u0...)) .- exact))
@printf("  5540 flat(128)=%.3g (bound 1e-7)   flat(8)/flat(32)=%.4g (bound >8)\n",
        flat(128), flat(8)/flat(32))
dev(h) = maximum(abs.(collect(sol(L=1.3,ks=1.7,h=h,nst=200)(u0...)) .- exact))
@printf("  5547 dev(1e-3)/dev(1e-4)=%.5f (≈10 rtol 0.1)\n", dev(1.0e-3)/dev(1.0e-4))
ierr(n) = maximum(abs.(collect(sol(L=1.3,ks=1.7,curved=true,nst=n)(u0...)) .- exact))
@printf("  5580 ierr(512)=%.3g (bound 1e-8); ratios %.3f %.3f %.3f (bracket 12..20)\n",
        ierr(512), ierr(8)/ierr(32), ierr(32)/ierr(128), ierr(128)/ierr(512))
refc = collect(sol(L=1.3,ks=1.7,h=0.18,nst=8192)(u0...))
errc(n) = maximum(abs.(collect(sol(L=1.3,ks=1.7,h=0.18,nst=n)(u0...)) .- refc))
@printf("  5552 curved nst ratios %.3f %.3f %.3f (bracket 12..20)\n",
        errc(8)/errc(32), errc(32)/errc(128), errc(128)/errc(512))
for (nm, kw) in (("k1",(k1=0.6,)), ("k0s",(k0s=0.2,)))
    r = sol(; L=1.3, ks=1.7, nst=256, kw...)(u0...)
    e4 = ferr(sol(; L=1.3,ks=1.7,h=1.0e-4,nst=256, kw...)(u0...), r)
    e5 = ferr(sol(; L=1.3,ks=1.7,h=1.0e-5,nst=256, kw...)(u0...), r)
    @printf("  5626 %-4s e4/e5=%.4f (bracket 8..12)\n", nm, e4/e5)
end
qref = compile_runtime(SBendSpec(L=1.3,h=0.18,b0=0.0,k1=0.6,bend_fringe=false,nst=256))(u0...)
d = ferr(sol(L=1.3,ks=0.0,h=0.18,k1=0.6,nst=256)(u0...), qref)
@printf("  5630 cross-implementation SBend vs Solenoid  = %.3g  (bound 1e-6, headroom %.0fx)\n", d, 1e-6/d)

println("\n== Curvature-resolved / patch (5276-5388)")
for spec in (DriftSpec(L=0.7), QuadrupoleSpec(L=0.4,k1=1.7,nst=4), SextupoleSpec(L=0.25,k2=14.0,nst=4))
    s1 = compile_runtime(spec); s2 = compile_runtime(typeof(spec)(; spec.params..., curved=true))
    @printf("  5295 %-14s curved=true vs straight = %.3g (atol 1e-15)\n",
            string(nameof(typeof(spec))), ferr(s2(u0...), s1(u0...)))
end

println("\n== GaussianPIC Float32 vs Float64 luminosity (5781)")
mkbeam(T) = begin
    s(scale,phase) = T[T(scale*sin(0.7*i+phase)) for i in 1:64]
    rep = Phase6DRep(s(1e-4,0.0), s(1e-5,0.3), s(1e-4,0.9), s(1e-5,1.2), s(1e-2,2.0), s(1e-4,2.5))
    p = BeamParams{Float64}(charge=1.0,mc2=1.0,E0=1.0,r0=1.0,npart=64)
    Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep)
end
slg = LongitudinalSlicing(nslices=2, method=:equal_count)
mkg() = GaussianPICPoissonSolver(kbb1=1e-4,kbb2=1e-4,luminosity_scale=1.0,grid=(16,16),
                                 green_cache=:none, slicing=slg)
l32 = collide!(mkg(), mkbeam(Float32), mkbeam(Float32), CPUThreadsBackend)
l64 = collide!(mkg(), mkbeam(Float64), mkbeam(Float64), CPUThreadsBackend)
@printf("  lum32=%.8g lum64=%.8g reldiff=%.3g (rtol 1e-5, headroom %.0fx)\n",
        l32, l64, abs(l32-l64)/abs(l64), 1e-5/(abs(l32-l64)/abs(l64)))

println("\n== Lost-particle charge semantics: which solver families are pinned? (4778 vs 4733)")
function loss_test_coords(N)
    s(scale,phase) = [scale*sin(0.7*i+phase) for i in 1:N]
    Dict(:x=>s(1e-4,0.0), :px=>s(1e-5,0.3), :y=>s(1e-4,0.9), :py=>s(1e-5,1.2),
         :z=>s(1e-2,2.0), :pz=>s(1e-4,2.5))
end
const LF = (:x,:pz,:py,:z,:px,:y)
function loss_test_rep(N, dead)
    c = loss_test_coords(N)
    for (k,dd) in enumerate(dead); f = LF[mod1(k,6)]; c[f][dd] = isodd(k) ? NaN : Inf; end
    Phase6DRep(c[:x],c[:px],c[:y],c[:py],c[:z],c[:pz])
end
loss_survivor_rep(N, dead) = (c = loss_test_coords(N); keep = setdiff(1:N, dead);
    Phase6DRep((c[k][keep] for k in (:x,:px,:y,:py,:z,:pz))...))
N = 4000; dead = collect(1:10:N); live_frac = (N-length(dead))/N
slc = LongitudinalSlicing(nslices=3, method=:equal_count); kbb = 1.0e-10
rmsf(v) = sqrt(sum(abs2,v)/length(v))
cleanrep() = Phase6DRep((loss_test_coords(N)[k] for k in (:x,:px,:y,:py,:z,:pz))...)
mkb(rep) = (p = BeamParams{Float64}(charge=1.0,mc2=1.0,E0=1.0,r0=1.0,npart=N);
            Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))
z0 = cleanrep()
for (nm, s) in (
    ("Gaussian",    GaussianPoissonSolver(kbb1=kbb,kbb2=kbb,luminosity_scale=1.0,slicing=slc)),
    ("PIC",         PICPoissonSolver(kbb1=kbb,kbb2=kbb,luminosity_scale=1.0,grid=(64,64),green_cache=:none,slicing=slc)),
    ("PIC :sigma",  PICPoissonSolver(kbb1=kbb,kbb2=kbb,luminosity_scale=1.0,grid=(64,64),green_cache=:none,slicing=slc,grid_extent=:sigma)),
    ("GaussianPIC", GaussianPICPoissonSolver(kbb1=kbb,kbb2=kbb,luminosity_scale=1.0,grid=(64,64),green_cache=:none,slicing=slc)),
    ("Spectral",    SpectralPoissonSolver(kbb1=kbb,kbb2=kbb,luminosity_scale=1.0,grid=(64,64),slicing=slc)))
    mt = mkb(cleanrep())
    lm = allow_lost_particles() do
        collide!(s, mkb(loss_test_rep(N,dead)), mt, CPUThreadsBackend)
    end
    st = mkb(cleanrep())
    ls = collide!(s, mkb(loss_survivor_rep(N,dead)), st, CPUThreadsBackend)
    km = mt.rep.py .- z0.py; ks = st.rep.py .- z0.py
    bitid = all(a == b for (a,b) in zip(coordinate_arrays(mt), coordinate_arrays(st)))
    @printf("  %-12s kickrms(masked)/kickrms(surv)=%.6f (live_frac %.2f)  lum reldiff=%.3g  bit-identical=%s\n",
            nm, rmsf(km)/rmsf(ks), live_frac, abs(lm-ls)/abs(ls), bitid)
end
