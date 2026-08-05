# U19 probe: measure the one-sided margins and loop coverage in region 4400-6600.
using Octopus, Test, Printf

# ---- (1) "PIC interaction_grid flag" :node memoization loop coverage (6341-6365)
mkpair53() = begin
    set_global_rng!(seed=53, method=:philox)
    e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
        alpha=(0.0,0.0,0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
        rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
        alpha=(0.0,0.0,0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
        rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=0.7e11)
    (e,p)
end
sl4 = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
e3, p3 = mkpair53()
s1 = Octopus.longitudinal_slices(e3.rep, sl4)
s2 = Octopus.longitudinal_slices(p3.rep, sl4)
src = Octopus._pic_extract_slice(e3.rep, s1.indices[2])
cache = Dict{Int,Any}()
get_node(b) = Octopus._pic_node_grid!(cache, PICPoissonSolver(; slicing=sl4, grid=(64,64)),
    Float64, src, s1.center[2], p3.rep, s2.indices, s2.boundary, b)
bs = collect(2:length(s2.boundary)-1)
nonnothing = Ref(0); inner = Ref(0)
for b in bs
    gb = get_node(b)
    gb === nothing && continue
    nonnothing[] += 1
    for adj in (b-1, b), i in s2.indices[adj]; inner[] += 1; end
end
@printf("NODE LOOP: boundary len=%d, b range=%s, nodes non-nothing=%d/%d, inner particle asserts=%d\n",
        length(s2.boundary), string(bs), nonnothing[], length(bs), inner[])

# union-bounds loop (6316-6320)
srcU = Octopus._pic_extract_slice(e3.rep, s1.indices[2])
ub = Octopus._pic_union_bounds(srcU, s1.center[2], p3.rep, s2.indices)
@printf("UNION BOUNDS: ub===nothing? %s ; inner asserts=%d\n", string(ub===nothing),
        sum(length(i) for i in s2.indices))

# ---- (2) grid_extent :sigma vs :extrema relvar margin (6448-6473)
mkpair64() = begin
    set_global_rng!(seed=64, method=:philox)
    e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
        alpha=(0.0,0.0,0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
        rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
        alpha=(0.0,0.0,0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
        rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=0.7e11)
    (e,p)
end
sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile)
e2, p2 = mkpair64()
sls = Octopus.longitudinal_slices(p2.rep, sl5)
widths(ge) = begin
    w = Float64[]
    for s in eachindex(sls.center)
        idx = sls.indices[s]; isempty(idx) && continue
        origin = p2.rep.x[idx[1]]
        lo, hi = Inf, -Inf; a, b = 0.0, 0.0
        for i in idx
            v = p2.rep.x[i]; d = v - origin
            lo = min(lo, v); hi = max(hi, v); a += d; b += d*d
        end
        ax = Octopus._pic_axis_extent(ge, lo, hi, origin, a, b, length(idx), 6.0)
        push!(w, ax[2]-ax[1])
    end
    w
end
relvar(v) = (m = sum(v)/length(v); sqrt(sum((v .- m).^2)/length(v))/m)
ws_, we_ = widths(:sigma), widths(:extrema)
@printf("GRID_EXTENT: nslices used sigma=%d extrema=%d ; relvar(sigma)=%.6g relvar(extrema)=%.6g ratio=%.4g\n",
        length(ws_), length(we_), relvar(ws_), relvar(we_), relvar(ws_)/relvar(we_))

# ---- (3) GaussianPIC beats PIC margin (5945-5983)
rms(v) = sqrt(sum(abs2, v)/length(v))
function round_pair11()
    set_global_rng!(seed=11, method=:philox)
    e = Beam(8000, CPUThreadsBackend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV,
        E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(8000, CPUThreadsBackend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV,
        E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=1.7e11)
    (e,p)
end
sl1 = LongitudinalSlicing(nslices=1, method=:normal_quantile, center_position=:centroid)
e0, _ = round_pair11(); px0 = copy(e0.rep.px)
eg, pg = round_pair11()
collide!(GaussianPoissonSolver(slicing=sl1, longitudinal_kick=false), eg, pg, CPUThreadsBackend)
kick_ref = eg.rep.px .- px0
coarse = (48,48)
eh, ph = round_pair11()
collide!(GaussianPICPoissonSolver(slicing=sl1, grid=coarse, green_cache=:none, longitudinal_kick=false), eh, ph, CPUThreadsBackend)
kick_h = eh.rep.px .- px0
ep, pp = round_pair11()
collide!(PICPoissonSolver(slicing=sl1, grid=coarse, green_cache=:none, longitudinal_kick=false), ep, pp, CPUThreadsBackend)
kick_p = ep.rep.px .- px0
err_h = rms(kick_h .- kick_ref)/rms(kick_ref); err_p = rms(kick_p .- kick_ref)/rms(kick_ref)
@printf("GPIC-BEATS-PIC: err_h=%.6g (bound 0.03) err_p=%.6g ratio err_h/err_p=%.6g (bound 0.95)\n",
        err_h, err_p, err_h/err_p)

# ---- (4) Spectral kick residuals (5985-6026)
function round_pair7()
    set_global_rng!(seed=7, method=:philox)
    e = Beam(8000, CPUThreadsBackend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV,
        E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(8000, CPUThreadsBackend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV,
        E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=1.7e11)
    (e,p)
end
e0s, p0s = round_pair7(); px0s = copy(e0s.rep.px); py0s = copy(p0s.rep.py)
egs, pgs = round_pair7()
collide!(GaussianPoissonSolver(slicing=sl1, longitudinal_kick=false), egs, pgs, CPUThreadsBackend)
ke_ref = egs.rep.px .- px0s; kp_ref = pgs.rep.py .- py0s
for (method, grid) in ((:grid,(128,128)), (:grid_free,(48,48)))
    es, ps = round_pair7()
    collide!(SpectralPoissonSolver(slicing=sl1, method=method, grid=grid,
             domain_factor=16.0, longitudinal_kick=false), es, ps, CPUThreadsBackend)
    ke = es.rep.px .- px0s; kp = ps.rep.py .- py0s
    @printf("SPECTRAL %-10s e_resid=%.6g p_resid=%.6g (bound 0.05)\n", string(method),
            rms(ke .- ke_ref)/rms(ke_ref), rms(kp .- kp_ref)/rms(kp_ref))
end
