# U19 negative controls: for the strongest testsets in lines 4400-6600, inject
# the defect each claims to guard and confirm the assertion fails.
using Octopus, Printf, LinearAlgebra

println("== NC1  runtests.jl:6512 'PIC luminosity overlap sums the full deposit extent'")
n = 200
x1 = [1.0e-4*(i-1)/(n-1) for i in 1:n]; y1 = [1.0e-4*((i*7)%n)/n for i in 1:n]
x2 = copy(x1); y2 = reverse(y1)
res = Dict{Symbol,Any}()
for method in (:CIC, :TSC)
    solver = PICPoissonSolver(kbb1=1e-6, kbb2=1e-6, grid=(16,16), deposit_method=method)
    nx, ny = Octopus._pic_luminosity_grid(solver)
    q1 = zeros(nx+1, ny+1); q2 = zeros(nx+1, ny+1)
    lum = Octopus._pic_luminosity!(solver, x1, y1, x2, y2, 1.0, q1, q2)
    excluded = sum(q1[nx+1,:]) + sum(q1[:,ny+1]) - q1[nx+1,ny+1]
    full = sum(q1 .* q2)
    trunc_ = full - (sum(q1[nx+1,:].*q2[nx+1,:]) + sum(q1[:,ny+1].*q2[:,ny+1]) - q1[nx+1,ny+1]*q2[nx+1,ny+1])
    res[method] = (lum=lum, full=full, truncated=trunc_, excluded=excluded)
end
@printf("  CIC excluded=%.17g (asserted ==0)   TSC excluded=%.4g (asserted >0.4)\n",
        res[:CIC].excluded, res[:TSC].excluded)
r_ok = abs(res[:CIC].lum/res[:CIC].full - res[:TSC].lum/res[:TSC].full) /
       abs(res[:CIC].lum/res[:CIC].full)
lum_defect = res[:TSC].lum * res[:TSC].truncated / res[:TSC].full   # pre-fix behaviour
r_bad = abs(res[:CIC].lum/res[:CIC].full - lum_defect/res[:TSC].full) /
        abs(res[:CIC].lum/res[:CIC].full)
@printf("  ratio reldiff  as-shipped=%.3g (rtol 1e-12 -> PASS)   with truncated sum=%.3g -> %s\n",
        r_ok, r_bad, r_bad > 1e-12 ? "FAIL (control fires)" : "PASS (control DEAD)")
@printf("  recovered TSC deficit=%.3g (asserted >5e-5)\n\n",
        (res[:TSC].full - res[:TSC].truncated)/res[:TSC].full)

println("== NC2  runtests.jl:6414 '(a\\') top-edge CIC weights'")
for nn in (5, 16, 64)
    got = Octopus._pic_cic_weights(float(nn-1), nn)
    # pre-fix: base clamped inward but f from floor(u) -> (nn-2, (1.0, 0.0))
    @printf("  n=%-3d shipped=%s  pre-fix would be (%d, (1.0, 0.0)) -> assertion %s\n",
            nn, string(got), nn-2, got == (nn-1,(0.0,1.0)) ? "PASSES now / FAILS pre-fix" : "??")
end
println()

println("== NC3  runtests.jl:4778 lost-particle charge semantics (PIC live-fraction)")
function loss_test_coords(N)
    s(scale, phase) = [scale*sin(0.7*i+phase) for i in 1:N]
    Dict(:x=>s(1e-4,0.0), :px=>s(1e-5,0.3), :y=>s(1e-4,0.9), :py=>s(1e-5,1.2),
         :z=>s(1e-2,2.0), :pz=>s(1e-4,2.5))
end
const LF = (:x,:pz,:py,:z,:px,:y)
function loss_test_rep(N, dead; values=nothing)
    c = loss_test_coords(N)
    for (k,d) in enumerate(dead)
        f = LF[mod1(k,6)]; c[f][d] = values === nothing ? (isodd(k) ? NaN : Inf) : values
    end
    Phase6DRep(c[:x],c[:px],c[:y],c[:py],c[:z],c[:pz])
end
loss_survivor_rep(N, dead) = (c = loss_test_coords(N); keep = setdiff(1:N, dead);
    Phase6DRep((c[k][keep] for k in (:x,:px,:y,:py,:z,:pz))...))
N = 4000; dead = collect(1:10:N); live_frac = (N-length(dead))/N
slc = LongitudinalSlicing(nslices=3, method=:equal_count)
kbb = 1.0e-10
rmsf(v) = sqrt(sum(abs2,v)/length(v))
cleanrep() = Phase6DRep((loss_test_coords(N)[k] for k in (:x,:px,:y,:py,:z,:pz))...)
mkb(rep) = (p = BeamParams{Float64}(charge=1.0,mc2=1.0,E0=1.0,r0=1.0,npart=N);
            Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))
function arms(solver_masked, solver_surv)
    mt = mkb(cleanrep())
    lm = allow_lost_particles() do
        collide!(solver_masked, mkb(loss_test_rep(N,dead)), mt, CPUThreadsBackend)
    end
    st = mkb(cleanrep())
    ls = collide!(solver_surv, mkb(loss_survivor_rep(N,dead)), st, CPUThreadsBackend)
    (lm, ls, mt, st)
end
pic(k) = PICPoissonSolver(kbb1=k, kbb2=k, luminosity_scale=1.0, grid=(64,64),
                          green_cache=:none, slicing=slc)
z0 = cleanrep()
lm, ls, mt, st = arms(pic(kbb), pic(kbb))
ratio_ok = rmsf(mt.rep.py .- z0.py) / rmsf(st.rep.py .- z0.py)
# defect: a PIC that RENORMALIZES (divides by live count) -> masked kbb scaled by 1/live_frac
lm2, ls2, mt2, st2 = arms(pic(kbb/live_frac), pic(kbb))
ratio_bad = rmsf(mt2.rep.py .- z0.py) / rmsf(st2.rep.py .- z0.py)
@printf("  shipped ratio=%.6f vs live_frac=%.4f (rtol 1e-3) -> %s\n", ratio_ok, live_frac,
        isapprox(ratio_ok, live_frac; rtol=1e-3) ? "PASS" : "FAIL")
@printf("  renormalising-PIC defect ratio=%.6f -> %s (%.0fx outside rtol)\n\n", ratio_bad,
        isapprox(ratio_bad, live_frac; rtol=1e-3) ? "PASS (control DEAD)" : "FAIL (control fires)",
        abs(ratio_bad-live_frac)/live_frac/1e-3)

println("== NC4  runtests.jl:6552 spectral absolute normalisation")
sig = 1.0e-4; n1d = 240
u = ((1:n1d) .- 0.5) ./ n1d
q = sqrt(2.0) .* Octopus.inverse_erf.(2 .* u .- 1)
sx = Float64[]; sy = Float64[]
for a in q, b in q; push!(sx, a*sig); push!(sy, b*sig); end
fx = Float64[]; fy = Float64[]
for k in 0:95, r in (0.25,0.5,0.75,1.0)
    th = 2pi*k/96; push!(fx, r*sig*cos(th)); push!(fy, r*sig*sin(th))
end
exact = [gaussian_beambeam_kick(sig, sig, fx[i], fy[i]) for i in eachindex(fx)]
Kx = getindex.(exact,1); Ky = getindex.(exact,2)
needed(Ex,Ey) = (sum(Ex.*Kx)+sum(Ey.*Ky)) / (sum(Ex.*Ex)+sum(Ey.*Ey))
L = 16.0*sig
exg, eyg = Octopus._spectral_field_grid(sx, sy, fx, fy, L, L, 511, 511)
exf, eyf = Octopus._spectral_field_free(sx, sy, fx, fy, L, L, 48, 48)
exg2, eyg2 = Octopus._spectral_field_grid(sx, sy, fx, fy, L, L, 127, 127)
@printf("  grid511 needed_scale=%.6f (|.-1|=%.3g vs atol 0.005)\n", needed(exg,eyg), abs(needed(exg,eyg)-1))
@printf("  free48  needed_scale=%.6f (|.-1|=%.3g vs atol 0.002)\n", needed(exf,eyf), abs(needed(exf,eyf)-1))
@printf("  grid127 needed_scale=%.6f ; refinement assertion %s\n", needed(exg2,eyg2),
        abs(needed(exg,eyg)-1) < abs(needed(exg2,eyg2)-1) ? "PASS" : "FAIL")
# recorded historical defect: a fitted scale 0.982 (i.e. field low by 1.8%)
sc = 0.982
@printf("  with the recorded Nx*Ny/((Nx+1)(Ny+1)) defect (field x %.3f): needed=%.4f -> %s\n\n",
        sc, needed(sc.*exg, sc.*eyg),
        abs(needed(sc.*exg, sc.*eyg)-1) > 0.005 ? "FAIL (control fires)" : "PASS (control DEAD)")

println("== NC5  runtests.jl:5390 'Exact solenoid map' RK4 headroom")
u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
sol(ks,L) = compile_runtime(SolenoidSpec(L=L, ks=ks))
function rk4_solenoid(ks, L, u0; nst=100_000)
    k = ks/2
    f(u) = begin
        x,px,y,py,z,pz = u
        Px = px + k*y; Py = py - k*x
        ps = sqrt((1+pz)^2 - Px^2 - Py^2)
        (Px/ps, k*Py/ps, Py/ps, -k*Px/ps, 1 - (1+pz)/ps, 0.0)
    end
    uu = u0; h = L/nst
    for _ in 1:nst
        a=f(uu); b=f(uu .+ h/2 .* a); c=f(uu .+ h/2 .* b); d=f(uu .+ h .* c)
        uu = uu .+ (h/6) .* (a .+ 2 .*b .+ 2 .*c .+ d)
    end
    uu
end
for ks in (0.35, 1.7, -0.9)
    d = maximum(abs.(collect(sol(ks,1.3)(u0...)) .- collect(rk4_solenoid(ks,1.3,u0))))
    @printf("  ks=%+.2f  |map - RK4|_inf = %.3g  (atol 1e-12, headroom %.0fx)\n", ks, d, 1e-12/d)
end
# defect control: drop the Larmor HALF (use ks instead of ks/2 in the drift piece)
d_half = maximum(abs.(collect(sol(1.7,1.3)(u0...)) .- collect(rk4_solenoid(0.85,1.3,u0))))
@printf("  if the map lost its Larmor half-angle: |diff| = %.3g -> FAIL (control fires)\n\n", d_half)

println("== NC6  runtests.jl:5810 shifted moments: naive two-pass vs shifted")
for T in (Float32, Float64)
    offset = T === Float32 ? T(1.0e4) : T(1.0e8)
    nn = 8192
    xdev = repeat(T[-1,1,-1,1], nn ÷ 4)
    x = offset .+ xdev
    naive = sum(abs2, x)/nn - (sum(x)/nn)^2          # the defect this pins
    @printf("  %-7s naive E[x^2]-E[x]^2 var = %.6g (true 1.0) -> assertion a0≈1 %s\n",
            string(T), Float64(naive), abs(Float64(naive)-1) > 1e-3 ? "FAILS (control fires)" : "PASSES")
end
