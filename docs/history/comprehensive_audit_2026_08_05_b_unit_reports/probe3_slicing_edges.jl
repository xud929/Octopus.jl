using Octopus
using Printf
const O = Octopus

rep_of(z) = O.Phase6DRep(zeros(length(z)), zeros(length(z)), zeros(length(z)),
                         zeros(length(z)), collect(float.(z)), zeros(length(z)))
workers(f, k, rep) = O._with_execution_policy(f,
    O._resolve_execution_policy(O.CPUThreadsExecutionPolicy(threads=k), rep))

METHODS = (:equal_area, :equal_count, :equal_width, :normal_quantile, :specified)

function show_slices(tag, sl)
    counts = [length(i) for i in sl.indices]
    @printf("  %-28s counts=%s  sum(w)-1=%.3g  bnd=%s  centers_finite=%s\n",
            tag, string(counts), sum(sl.weight) - 1,
            string(round.(sl.boundary; digits=6)), string(all(isfinite, sl.center)))
end

println("=== (c1) degenerate z: every particle at one z ===")
z = fill(0.5, 7)
for m in METHODS
    slc = m === :specified ? O.LongitudinalSlicing(nslices=3, method=m, positions=[-1.0, 1.0]) :
          O.LongitudinalSlicing(nslices=3, method=m)
    sl = O.longitudinal_slices(rep_of(z), slc)
    show_slices(string(m), sl)
end

println("\n=== (c2) n not divisible by nslices (n=10, ns=3) ===")
z = [0.1 * i for i in 1:10]
for m in METHODS
    slc = m === :specified ? O.LongitudinalSlicing(nslices=3, method=m, positions=[-0.5, 0.5]) :
          O.LongitudinalSlicing(nslices=3, method=m)
    sl = O.longitudinal_slices(rep_of(z), slc)
    show_slices(string(m), sl)
end

println("\n=== (c3) more slices than particles (n=3, ns=7) ===")
z = [0.0, 1.0, 2.0]
for m in METHODS
    slc = m === :specified ? O.LongitudinalSlicing(nslices=7, method=m, positions=collect(-3.0:1.0:2.0)) :
          O.LongitudinalSlicing(nslices=7, method=m)
    sl = O.longitudinal_slices(rep_of(z), slc)
    show_slices(string(m), sl)
end

println("\n=== (c4) single particle (n=1, ns=3) ===")
for m in METHODS
    slc = m === :specified ? O.LongitudinalSlicing(nslices=3, method=m, positions=[-1.0, 1.0]) :
          O.LongitudinalSlicing(nslices=3, method=m)
    sl = O.longitudinal_slices(rep_of([1.25]), slc)
    show_slices(string(m), sl)
end

println("\n=== (c5) equal_count with heavy ties (2000 particles, 64 z levels) ===")
z = [round(2.0e-2 * sin(0.7 * i + 2.0); digits=3) for i in 1:2000]
for ns in (4, 5, 9)
    sl = O.longitudinal_slices(rep_of(z), O.LongitudinalSlicing(nslices=ns, method=:equal_count))
    counts = [length(i) for i in sl.indices]
    # documented: a tied particle can sit exactly ON its reported boundary
    on_boundary = 0
    outside_halfopen = 0
    for s in 1:ns, i in sl.indices[s]
        zi = z[i]
        lb = sl.boundary[s]; rb = sl.boundary[s + 1]
        zi == lb || zi == rb ? (on_boundary += 1) : nothing
        (lb <= zi < rb) || (s == ns && zi == rb) || (outside_halfopen += 1)
    end
    @printf("  ns=%d counts=%s (exact equal? %s) sum(w)-1=%.3g on_boundary=%d outside[lb,rb)=%d\n",
            ns, string(counts),
            string(maximum(counts) - minimum(counts) <= 1), sum(sl.weight) - 1,
            on_boundary, outside_halfopen)
end

println("\n=== (c6) equal_count tie ordering: live-mask OFF vs ON (all particles live) ===")
z = [round(2.0e-2 * sin(0.7 * i + 2.0); digits=3) for i in 1:2000]
r = rep_of(z)
slc = O.LongitudinalSlicing(nslices=5, method=:equal_count)
sl_off = O.longitudinal_slices(r, slc)
sl_on = O.allow_lost_particles() do
    O.longitudinal_slices(r, slc)
end
same = all(sl_off.indices[s] == sl_on.indices[s] for s in 1:5)
@printf("  membership identical with mask off vs on: %s\n", same)
if !same
    ndiff = sum(length(symdiff(Set(sl_off.indices[s]), Set(sl_on.indices[s]))) for s in 1:5)
    @printf("  particles whose slice changed: %d of %d; counts off=%s on=%s\n",
            ndiff ÷ 2, length(z),
            string([length(i) for i in sl_off.indices]), string([length(i) for i in sl_on.indices]))
    @printf("  centers off=%s\n  centers on =%s\n", string(sl_off.center), string(sl_on.center))
end

println("\n=== (c7) equal_width: CPU _slice_bin rule vs boundary-comparison rule (the CUDA twin's) ===")
for (n, ns, quantize) in ((200000, 15, false), (200000, 15, true), (2000, 7, true), (2000, 45, false))
    z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    quantize && (z = round.(z; digits=3))
    zmin, zmax = extrema(z)
    width = (zmax - zmin) / ns
    bnd = collect(range(zmin, zmax; length=ns + 1))
    dis = 0
    for zi in z
        a = O._slice_bin(zi, zmin, width, ns)
        b = 0
        for s in 1:ns
            lo = bnd[s]; hi = bnd[s + 1]
            if (s == ns ? (lo <= zi <= hi) : (lo <= zi < hi))
                b = s; break
            end
        end
        a == b || (dis += 1)
    end
    @printf("  n=%-7d ns=%-3d quantized=%-5s  disagreements: %d (%.4f%%)\n",
            n, ns, quantize, dis, 100 * dis / n)
end

println("\n=== (c8) slicing membership is worker-count invariant (1/4/8) ===")
for (m, n, ns) in ((:equal_area, 200000, 15), (:equal_width, 200000, 15),
                   (:equal_count, 200000, 15), (:normal_quantile, 200000, 15))
    z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    r = rep_of(z)
    slc = O.LongitudinalSlicing(nslices=ns, method=m)
    res = map((1, 4, 8)) do k
        workers(k, r) do
            O.longitudinal_slices(r, slc)
        end
    end
    ok_idx = all(all(res[1].indices[s] == res[t].indices[s] for s in 1:ns) for t in 2:3)
    ok_bnd = all(res[1].boundary == res[t].boundary for t in 2:3)
    ok_ctr = all(res[1].center == res[t].center for t in 2:3)
    @printf("  %-16s indices identical=%s boundaries bit-identical=%s centers bit-identical=%s\n",
            string(m), ok_idx, ok_bnd, ok_ctr)
end

println("\n=== (c9) _slice_transverse_moments degenerate inputs ===")
r = rep_of([0.0, 1.0, 2.0])
for idx in (Int[], [2], [1, 2, 3])
    mo = O._slice_transverse_moments(r, idx, false, 1.0e-9)
    @printf("  n=%d  mx=%.3g sx=%.3g spx=%.3g finite=%s\n", length(idx), mo.mx, mo.sx, mo.spx,
            all(isfinite, (mo.mx, mo.sx, mo.mpx, mo.spx, mo.covxpx, mo.my, mo.sy, mo.mpy, mo.spy, mo.covypy)))
end

println("\n=== (c10) all-dead beam and partly dead beam ===")
zz = [NaN, NaN, NaN]
try
    O.allow_lost_particles() do
        O.longitudinal_slices(rep_of(zz), O.LongitudinalSlicing(nslices=2, method=:equal_area))
    end
    println("  all-dead: NO THROW (unexpected)")
catch e
    println("  all-dead: throws ", typeof(e))
end
zz = [0.0, NaN, 1.0, 2.0]
sl = O.allow_lost_particles() do
    O.longitudinal_slices(rep_of(zz), O.LongitudinalSlicing(nslices=2, method=:equal_area))
end
show_slices("partly dead equal_area", sl)
