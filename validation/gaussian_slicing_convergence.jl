"""
Convergence of the Gaussian longitudinal slicing rules at EIC weak-strong parameters.

This is simultaneously the correctness check for the `slice_method` implementations
and the study that ranks them: a rule that is implemented wrongly does not converge
to the same limit as the others, so agreement at large `ns` is the verification.

Reference model
---------------
Furman, Zholents, Chen and Shatilov, "Comparisons of Beam-Beam Simulations",
PEP-II/AP Note 95.39 / LBL-37680 / CBP Note-152 (1995), Section 2. Derivations,
reference values and the erratum to their Table 1 are in
`../docs/theory/gaussian_longitudinal_slicing.md`.

The `ns -> infinity` reference is `:sqrt_density` at `ns_reference`. Ref. [1]
uses "algorithm #4 at 300 kicks" and scores every rule against it, which is
circular: each rule is measured against the asymptote of the best member of its
own family. Here the reference is instead qualified by its **own** residual,
estimated by Richardson extrapolation from three solves at `ns/2`, `ns` and
`2*ns`: with error ~ `C*ns^-p` the ratio of successive differences is `2^p`,
which gives `p` and hence `residual(ns) = d_fine / (1 - 2^-p)`. That residual is
the floor; `Q` at or below it is not resolved.

A cross-family comparison against `:equal_area_centroid` is printed for context
but is **not** the floor. At `ns_reference` it is dominated by that rule's own
residual — it converges at order ~1.3 against the reference's ~2 — so using it
would overstate the floor by more than an order of magnitude.

Error metric
------------
Furman Eq. (10): push a Gaussian test bunch once through the thick beam-beam
lens and compare the four transverse normalized coordinates against the
reference,

    Q = sum_{n=1..4} sqrt( < (X_n - X_n_ref)^2 > ),
    (X_1..X_4) = (x/sigma_x, px/sigma_px, y/sigma_y, py/sigma_py).

The metric involves no lattice parameter; it judges the beam-beam element alone.
The virtual-drift model cancels in the difference (rule and reference use the
same one), but `:exact` is used so a drift-model error cannot be mistaken for a
slicing error.

For a ring without radiation damping Furman's `Q ~ 4/sqrt(tau)` gives no bound at
all (the threshold goes to zero). The script therefore also reports the
**virtual-drift model error**, `|hirata - exact|` and `|chromatic - exact|` at
converged slicing. That is an error the run is already accepting, and it is the
practical stopping point: there is no value in refining the slicing far below it.

Alongside `Q` the script reports the tracking-free second-moment deficit
`1 - sum_k w_k z_k^2 / sigz^2` and, for the equal-charge family, its split into
the two semi-infinite tail bins versus the interior. **Comparing the two fitted
orders is the point of the script**: the deficit is tail-limited to ~first order,
while a tail slice collides at large |s_c| where the field is weakest, so `Q` may
down-weight exactly the bins the deficit says dominate. If the orders agree, the
remedy is node placement; if they do not, the tails are a red herring for `Q`.

Both collision directions are run. The governing hourglass ratio is
`sigma_z,strong / beta*_weak`, which differs by an order of magnitude between
them.

Inputs
------
Beam parameters are the EIC values already used by
`validation/slice_longitudinal_zscan.jl` (275 GeV proton, 10 GeV electron).
Edit the `config` block below.

Outputs (under `result/`)
-------------------------
- `gaussian_slicing_convergence.tsv`      Q and moment deficit per rule/ns/direction
- `gaussian_slicing_tail_split.tsv`       tail vs interior deficit, equal-charge family

Run
---
    julia --project=. validation/gaussian_slicing_convergence.jl
"""

include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
using .Octopus
using Random
using Printf

const O = Octopus

config = (
    n_particles    = 4000,
    ns_list        = [3, 5, 7, 9, 15, 21, 31, 45, 61],
    ns_reference   = 601,
    ns_crosscheck  = 61,          # gauss_hermite ceiling: weights underflow beyond ~100
    rules          = collect(O.SLICE_METHODS),
    # :equal_width has TWO convergence parameters. Its bin width is tied here to
    # Furman #1's growing half-span 1+(ns-3)/12 so that ns alone drives it; at a
    # fixed width it stops converging once the extra bins fall outside the bunch.
    equal_width_span = ns -> 2 * (1 + (ns - 3) / 12) / ns,
    virtual_drift  = :exact,
    seed           = 20260731,
    tau_electron   = 4000.0,      # transverse damping time in turns, electron ring
)

# EIC parameters, as in validation/slice_longitudinal_zscan.jl.
const PROTON = (name="proton", beta=(0.8, 0.072), betaz=90.0,
                sigma=(95.0e-6, 8.5e-6), sigz=6.0e-2,
                E0=275.0e9, mc2=O.PMASS_EV, charge=1.0, npart=0.7e11)
const ELECTRON = (name="electron", beta=(0.55, 0.056), betaz=12.0,
                  sigma=(106.0e-6, 9.5e-6), sigz=7.0e-3,
                  E0=10.0e9, mc2=O.EMASS_EV, charge=-1.0, npart=1.7e11)

classical_radius(beam) = O.RE * O.ME0 / beam.mc2

"Beam-beam kick coefficient felt by `weak` from `strong`, as in `_strong_strong_kbb1`."
kick_coefficient(weak, strong) =
    weak.charge * strong.charge * classical_radius(weak) * strong.npart *
    weak.mc2 / weak.E0

"Uncorrelated Gaussian test bunch matched to the bare lattice at the IP."
function test_bunch(weak, n, rng)
    sx, sy = weak.sigma
    spx, spy = sx / weak.beta[1], sy / weak.beta[2]
    sz = weak.sigz
    spz = sz / weak.betaz
    scale = (sx, spx, sy, spy, sz, spz)
    coords = ntuple(i -> scale[i] .* randn(rng, n), 6)
    return coords, (sx, spx, sy, spy)
end

push_once(weak, strong, rule, ns, coords) =
    push_once_drift(weak, strong, rule, ns, coords, config.virtual_drift)

function push_once_drift(weak, strong, rule, ns, coords, drift)
    thin = ThinStrongBeamSpec(; kbb=kick_coefficient(weak, strong),
                              beta=strong.beta, alpha=(0.0, 0.0),
                              sigma=strong.sigma, virtual_drift=drift)
    element = compile_runtime(GaussianStrongBeamSpec(;
        thin=thin, ns=ns, sigz=strong.sigz, slice_method=rule,
        slice_width=(rule === :equal_width ?
                     config.equal_width_span(ns) * strong.sigz : nothing)))
    n = length(coords[1])
    out = ntuple(_ -> Vector{Float64}(undef, n), 4)
    @inbounds for i in 1:n
        x, px, y, py, z, pz = track_particle(
            WeakStrongBeamBeamMap(), element,
            coords[1][i], coords[2][i], coords[3][i],
            coords[4][i], coords[5][i], coords[6][i])
        out[1][i] = x; out[2][i] = px; out[3][i] = y; out[4][i] = py
    end
    return out
end

"Furman Eq. (10)."
function furman_Q(sample, reference, norms)
    total = 0.0
    for n in 1:4
        acc = 0.0
        @inbounds for i in eachindex(sample[n])
            d = (sample[n][i] - reference[n][i]) / norms[n]
            acc += d * d
        end
        total += sqrt(acc / length(sample[n]))
    end
    return total
end

second_moment_deficit(rule, ns, sigz) = begin
    z, w = O._gaussian_slices(Float64, ns, nothing, nothing, sigz, rule,
                             rule === :equal_width ? config.equal_width_span(ns) * sigz : nothing)
    abs(1 - sum(collect(w) .* collect(z) .^ 2) / sigz^2)
end

"Split the equal-charge deficit into the two semi-infinite bins and the interior."
function deficit_split(ns)
    Phi(x) = O._snorm_cdf(x)
    phi(x) = isinf(x) ? 0.0 : O._snorm_pdf(x)
    edge(j) = j <= 0 ? -Inf : j >= ns ? Inf : O._snorm_quantile(j / ns)
    interior = 0.0; tails = 0.0
    for j in 1:ns
        a, b = edge(j - 1), edge(j)
        p = Phi(min(b, 40.0)) - Phi(max(a, -40.0))
        mu = (phi(a) - phi(b)) / p
        m2 = p + (isinf(a) ? 0.0 : a * phi(a)) - (isinf(b) ? 0.0 : b * phi(b))
        v = (m2 / p - mu^2) / ns
        (isinf(a) || isinf(b)) ? (tails += v) : (interior += v)
    end
    return interior + tails, interior, tails
end

fitted_order(x1, y1, x2, y2) = (y1 > 0 && y2 > 0) ? -log(y2 / y1) / log(x2 / x1) : NaN

# ---------------------------------------------------------------------------

rows = Tuple[]
println("Gaussian longitudinal slicing convergence — EIC weak-strong")
println("particles = ", config.n_particles, ", reference = :sqrt_density at ns = ",
        config.ns_reference, ", virtual_drift = ", config.virtual_drift, "\n")

for (weak, strong) in ((ELECTRON, PROTON), (PROTON, ELECTRON))
    rng = Random.Xoshiro(config.seed)
    coords, norms = test_bunch(weak, config.n_particles, rng)
    hourglass = strong.sigz / weak.beta[2]
    @printf("=== %s (weak) on %s (strong):  sigma_z,strong / beta*_y,weak = %.3f ===\n",
            weak.name, strong.name, hourglass)

    # Richardson estimate of the reference's OWN residual. With error ~ C*ns^-p,
    # three solves at ns/2, ns, 2ns give d_coarse/d_fine = 2^p, hence p, hence
    # residual(ns) = d_fine / (1 - 2^-p). This is the floor.
    reference = push_once(weak, strong, :sqrt_density, config.ns_reference, coords)
    d_coarse = furman_Q(
        push_once(weak, strong, :sqrt_density, config.ns_reference ÷ 2, coords), reference, norms)
    d_fine = furman_Q(
        push_once(weak, strong, :sqrt_density, 2 * config.ns_reference, coords), reference, norms)
    order_ref = log2(d_coarse / d_fine)
    reference_floor = d_fine / (1 - 2.0^(-order_ref))
    @printf("reference residual (Richardson, measured order p = %.2f): %.3e  <- the floor\n",
            order_ref, reference_floor)
    # Reported for context only. At ns_reference this is dominated by #3's own
    # residual (it converges at order ~1.3, the reference at ~2), NOT by any
    # uncertainty in the reference, so it must not be used as the floor.
    cross_family = furman_Q(
        push_once(weak, strong, :equal_area_centroid, config.ns_reference, coords), reference, norms)
    @printf("cross-family |#3(%d) - #4(%d)| = %.3e (context only: this is #3's residual, not the floor)\n",
            config.ns_reference, config.ns_reference, cross_family)
    # A ring without radiation damping has no Q ~ 4/sqrt(tau) bound, so the
    # useful yardstick is an error the run is ALREADY accepting: the virtual-drift
    # model. Refining slicing far below it buys nothing.
    for drift in (:hirata, :chromatic)
        q = furman_Q(push_once_drift(weak, strong, :sqrt_density, config.ns_reference, coords, drift),
                     reference, norms)
        @printf("virtual-drift model error at ns=%d: |%s - exact| = %.3e%s\n",
                config.ns_reference, drift, q,
                drift === :hirata ? "   <-- ThinStrongBeamSpec default" : "")
    end
    @printf("Furman criterion for this ring: Q ~ 4/sqrt(tau) = %.3e %s\n\n",
            4 / sqrt(config.tau_electron),
            weak.name == "electron" ? "(applies)" :
            "(DOES NOT APPLY: no radiation damping; see the note, Section 7)")

    print(rpad("rule", 24)); for ns in config.ns_list; print(lpad("ns=$ns", 11)); end
    println(lpad("order", 8), lpad("m2-order", 10))
    println(" " ^ 24, "(orders are LOCAL fits over the last two ns; rules with a growing span converge non-uniformly)")
    for rule in config.rules
        qs = Float64[]
        print(rpad(String(rule), 24))
        for ns in config.ns_list
            q = furman_Q(push_once(weak, strong, rule, ns, coords), reference, norms)
            push!(qs, q)
            print(lpad(@sprintf("%.3e", q), 11))
            push!(rows, (weak.name, String(rule), ns, q,
                         second_moment_deficit(rule, ns, strong.sigz)))
        end
        lo, hi = length(config.ns_list) - 1, length(config.ns_list)
        qorder = fitted_order(config.ns_list[lo], qs[lo], config.ns_list[hi], qs[hi])
        morder = fitted_order(config.ns_list[lo],
                              second_moment_deficit(rule, config.ns_list[lo], strong.sigz),
                              config.ns_list[hi],
                              second_moment_deficit(rule, config.ns_list[hi], strong.sigz))
        if rule === :gauss_hermite
            @printf("%8.2f%10s\n", qorder, "exact")
        else
            @printf("%8.2f%10.2f\n", qorder, morder)
        end
    end
    println()
end

println("=== equal-charge second-moment deficit: tail vs interior (rule-independent) ===")
@printf("%6s %12s %12s %12s %8s\n", "ns", "total", "interior", "tails", "tail%")
tail_rows = Tuple[]
for ns in (5, 15, 31, 65, 101, 251)
    t, i, l = deficit_split(ns)
    @printf("%6d %12.4e %12.4e %12.4e %7.1f%%\n", ns, t, i, l, 100l / t)
    push!(tail_rows, (ns, t, i, l))
end

resultdir = joinpath(@__DIR__, "..", "result")
mkpath(resultdir)
open(joinpath(resultdir, "gaussian_slicing_convergence.tsv"), "w") do io
    println(io, "weak_beam\trule\tns\tQ\tsecond_moment_deficit")
    for r in rows
        @printf(io, "%s\t%s\t%d\t%.8e\t%.8e\n", r...)
    end
end
open(joinpath(resultdir, "gaussian_slicing_tail_split.tsv"), "w") do io
    println(io, "ns\tdeficit_total\tdeficit_interior\tdeficit_tails")
    for r in tail_rows
        @printf(io, "%d\t%.8e\t%.8e\t%.8e\n", r...)
    end
end
println("\nTSVs written to result/.")
