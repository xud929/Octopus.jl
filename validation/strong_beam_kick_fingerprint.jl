#=
Bitwise fingerprints of the weak-strong strong-beam kick chain over the
branches the production line never exercises: every virtual-drift model,
coupled moments (`XYCouplingSpec`), nonzero centre/angle/curvature, a 6x6
covariance sliced beam (crab-slope slice angles, the coupled-moments
branch), and a per-slice `hvoffset`. Each configuration tracks a fixed
4,000-particle set two turns through BOTH loop copies -- the fused callable
(`track!(rep, (elem,), 2; policy=...)`) and the elementwise luminosity path
(`track!(rep, elem, 2, policy)`) -- and prints a digest of every coordinate
plus `last_luminosity` at full precision.

The instrument answers one question: did a refactor of the kick chain move
a bit anywhere? Run it on two checkouts and diff the `BR` lines:

    julia --startup-file=no --project=. validation/strong_beam_kick_fingerprint.jl > a.log
    OCT_ROOT=/path/to/other/checkout julia --startup-file=no --project=/path/to/other/checkout \
        validation/strong_beam_kick_fingerprint.jl > b.log
    diff <(grep '^BR' a.log) <(grep '^BR' b.log)

`OCT_ROOT` selects the tree whose `src/Octopus.jl` is included (script
mode); it defaults to this checkout. Digests are order-sensitive and
compare only between runs of the same Julia build on the same machine:
this is a refactor guard, not a cross-platform reference. Written for
multi-process step 1 (2026-09-04, docs/history/weak_strong_allocation_2026_09_04.md),
where nine configurations were bit-identical across the slice-carrier
change; the `hvoffset` configuration throws a `MethodError` on both trees
(a plain tuple is not accepted; recorded there as out of scope).
=#
const ROOT = get(ENV, "OCT_ROOT", normpath(joinpath(@__DIR__, "..")))
include(joinpath(ROOT, "src", "Octopus.jl"))
using .Octopus
using Printf
using LinearAlgebra
println("TREE ", ROOT)
function digest(rep)
    h = UInt64(0)
    for a in coordinate_arrays(rep), v in a
        h = (h << 1) | (h >> 63)
        h ⊻= reinterpret(UInt64, Float64(v))
    end
    return h
end
mkrep(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    Phase6DRep(s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9),
               s(1.0e-5, 1.2), s(1.0e-3, 2.1), s(1.0e-4, 2.5))
end
const N = 4000
thin(; kw...) = ThinStrongBeamSpec{Float64}(; kbb=1.0e-4, klum=1.0, beta=(0.82, 0.075),
    alpha=(0.01, -0.02), sigma=(115.0e-6, 13.0e-6), kw...)
cov6 = let sx = 115.0e-6, spx = 1.4e-4, sy = 13.0e-6, spy = 1.7e-4, sz = 7.0e-3, spz = 6.6e-4
    c = zeros(6, 6)
    for (i, s) in enumerate((sx, spx, sy, spy, sz, spz)); c[i, i] = s^2; end
    c[1, 5] = c[5, 1] = 0.3 * sx * sz          # crab slope x-z
    c[2, 5] = c[5, 2] = 0.1 * spx * sz
    c[1, 3] = c[3, 1] = 0.2 * sx * sy          # x-y coupling
    c[2, 4] = c[4, 2] = 0.15 * spx * spy
    c[1, 2] = c[2, 1] = -0.1 * sx * spx
    c
end
configs = [
    ("thin hirata angled",            () -> thin(center=(2.0e-6, -1.0e-6, 1.0e-3), angle=(1.0e-4, -2.0e-4, 5.0e-5), curvature=(1.0e-3, -2.0e-3, 4.0e-4))),
    ("thin coupled exact",            () -> thin(coupling=XYCouplingSpec{Float64}(r1=0.01, r2=-0.003, r3=0.002, r4=0.004), virtual_drift=:exact, angle=(1.0e-4, -2.0e-4, 0.0))),
    ("gsb hirata angled",             () -> GaussianStrongBeamSpec{Float64}(thin=thin(center=(2.0e-6, -1.0e-6, 1.0e-3), angle=(1.0e-4, -2.0e-4, 5.0e-5), curvature=(1.0e-3, -2.0e-3, 4.0e-4)), ns=3, sigz=7.0e-3, slice_method=:equal_area)),
    ("gsb chromatic",                 () -> GaussianStrongBeamSpec{Float64}(thin=thin(virtual_drift=:chromatic), ns=3, sigz=7.0e-3, slice_method=:equal_area)),
    ("gsb exact",                     () -> GaussianStrongBeamSpec{Float64}(thin=thin(virtual_drift=:exact), ns=3, sigz=7.0e-3, slice_method=:gauss_hermite)),
    ("gsb exact coupled",             () -> GaussianStrongBeamSpec{Float64}(thin=thin(coupling=XYCouplingSpec{Float64}(r1=0.01, r2=-0.003, r3=0.002, r4=0.004), virtual_drift=:exact), ns=3, sigz=7.0e-3, slice_method=:sqrt_density)),
    ("gsb 6x6 covariance hirata",     () -> GaussianStrongBeamSpec{Float64}(thin=thin(), ns=3, covariance=cov6, mean=(1.0e-6, 2.0e-6, -1.0e-6, 1.0e-6, 0.0, 0.0))),
    ("gsb unsafe paraxial-frozen",    () -> GaussianStrongBeamSpec{Float64}(thin=thin(virtual_drift=UnsafeVirtualDrift(:paraxial_frozen_longitudinal)), ns=3, sigz=7.0e-3, slice_method=:equal_area)),
    ("gsb unsafe chromatic-frozen",   () -> GaussianStrongBeamSpec{Float64}(thin=thin(virtual_drift=UnsafeVirtualDrift(:chromatic_frozen_energy)), ns=3, sigz=7.0e-3, slice_method=:equal_area)),
    ("gsb hirata hvoffset",           () -> GaussianStrongBeamSpec{Float64}(thin=thin(), ns=5, sigz=7.0e-3, slice_method=:equal_area, hvoffset=(1.0e-6, -2.0e-6))),
]
# `:auto` workers: the digests are thread-count invariant (the suite pins
# both loop copies across worker counts), so any `--threads` gives the same
# lines, and a bare `julia --project=.` launch works.
policy = CPUThreadsExecutionPolicy()
for (name, mk) in configs
    try
        elem = compile_runtime(mk())
        rep = mkrep(N)
        track!(rep, (elem,), 2; policy=policy)                    # fused callable
        d_f = digest(rep)
        elem2 = compile_runtime(mk())
        rep2 = mkrep(N)
        resolved = Octopus._resolve_execution_policy(policy, rep2)
        Octopus._with_execution_policy(resolved) do
            Octopus.track!(rep2, elem2, 2, resolved)               # elementwise + luminosity
        end
        @printf("BR %-28s fused 0x%016x  elementwise 0x%016x  lum %s  type %s\n", name, d_f, digest(rep2), repr(elem2.last_luminosity), nameof(typeof(elem2)))
    catch e
        println("BR ", name, " ERROR ", sprint(showerror, e)[1:min(300, end)])
    end
end
println("BR DONE")
