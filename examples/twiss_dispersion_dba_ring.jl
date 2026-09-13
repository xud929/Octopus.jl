#=
Twiss and dispersion analysis of a DBA ring with RF, given as a `BeamLine`.

One double-bend-achromat cell (two sector bends around a focusing quadrupole,
wrapped in defocusing quadrupoles) closed by a thin RF cavity is a ring for
the one-turn map: the cell's transverse optics with its momentum dispersion,
plus a synchrotron mode. `analyze` with a `TwissDispersionAnalysis` runs
twice:

1. With the default options the 6D result is `:degraded`: the longitudinal
   mode was selected by the `:max_signed_z_area` heuristic, which the
   analysis does not certify on its own (theory (K12): kappa_sz = h, so the
   rule is ambiguous for h < 1/2). The result names the selected canonical
   eigenvalue.
2. Passing that index back as `longitudinal_mode` certifies the selection and
   the result is `:passed`: tunes, canonical crab and momentum dispersion,
   the longitudinal factor h, the per-option configuration report, the three
   normal modes, and the matched rms beam sizes for given mode emittances.

Every physically undetermined quantity is a `Determined` with a reason; this
script prints the reason instead of a value whenever one is not unique
(design note: no NaN stands in for "unknown"). The RF cavity sits in the
dispersive cell, so the crab dispersion zeta is already nonzero; set
`crab_strength` to a nonzero value to add a thin crab cavity and see it change.

Design note: `docs/design/twiss_dispersion_analysis.md`; theory:
`docs/theory/twiss_dispersion.md`.

Run from the project root:

    julia --project=. examples/twiss_dispersion_dba_ring.jl

Output is printed to the terminal; no files are written.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using LinearAlgebra

config = (
    energy_ev = 3.0e9,                     # proton reference energy for the cavity's beta0, gamma0
    rf_frequency = 400.0e6,                # Hz
    rf_strength = 0.02,                    # the thin cavity's strength (see ?ThinRFCavitySpec)
    crab_strength = 0.0,                   # 0.0: no crab cavity; 0.05 adds ThinCrabCavitySpec{1} with strengthX = (-k,)
    emittances = (1.0e-9, 1.0e-9, 1.0e-6), # rms mode emittances (eps_1, eps_2, eps_s) for the matched covariance
)

# ---------------------------------------------------------------------------
# The ring: one DBA cell (qd d bend d qf d bend d qd) closed by a thin RF
# cavity, as a BeamLine of specs. `analyze` compiles the line itself.

const NST = 4          # integrator slices per thick element
const ORDER = 4        # symplectic integrator order
beta0, gamma0 = reference_beta_gamma(config.energy_ev, PMASS_EV)

qd   = QuadrupoleSpec(L=0.25, kn=(0.0, -1.1), nst=NST, integrator_order=ORDER)
qf   = QuadrupoleSpec(L=0.35, kn=(0.0, 1.5), nst=NST, integrator_order=ORDER)
d    = DriftSpec(L=0.6)
bend = SBendSpec(L=1.0, h=0.2, b0=0.2, nst=NST, integrator_order=ORDER)
rf   = ThinRFCavitySpec(config.rf_frequency; strength=config.rf_strength, beta0=beta0, gamma0=gamma0)

elements = Any[qd, d, bend, d, qf, d, bend, d, qd, rf]
if config.crab_strength != 0
    # The kernel's sign convention: strengthX = (-k,) gives the theory's +k crab kick.
    push!(elements, ThinCrabCavitySpec{1}(config.rf_frequency; strengthX=(-config.crab_strength,)))
end
ring = BeamLine("DBA_RING", elements...)

"Print a `Determined` quantity, or the reason it is not unique (never a stand-in value)."
function show_determined(label, d)
    if is_determined(d)
        println("  ", label, " = ", determined_value(d))
    else
        println("  ", label, ": not unique (", d.status, ", ", d.reason, "): ", d.detail)
    end
end

# ---------------------------------------------------------------------------
# Run 1: the default options. The longitudinal mode is selected by the
# :max_signed_z_area heuristic, which the analysis reports but does not
# certify: the verdict is :degraded and names the selected eigenvalue index.

println("Run 1: default options")
r1 = analyze(TwissDispersionAnalysis(strict=false, emittances=config.emittances), ring)
println("  status = ", r1.status)
for s in r1.degradations
    println("  degradation: ", s)
end
println("  heuristic longitudinal selection: canonical eigenvalue index ", r1.dispersion.longitudinal)
println()
# ---------------------------------------------------------------------------
# Run 2: the selection passed back as `longitudinal_mode` certifies it and the
# verdict is :passed. Everything below is read from this result.

println("Run 2: longitudinal_mode = ", r1.dispersion.longitudinal, " (certified)")
analysis = TwissDispersionAnalysis(strict=false, emittances=config.emittances,
                                   longitudinal_mode=r1.dispersion.longitudinal)
r = analyze(analysis, ring)
println("  status = ", r.status)
for s in r.degradations
    println("  degradation: ", s)
end
for s in r.failures
    println("  failure: ", s)
end

println("Tunes (radians per turn, fractional mu / 2pi):")
for (j, mu) in enumerate(r.physical.tunes)
    println("  mode ", j, ": mu = ", mu, "  Q = ", mu / (2pi))
    # The oriented tune of theory (E5) is the angle of the eigenvalue exp(-i mu) whose member has Im(v' S v) < 0.
    # A value above pi means the mode rotates in the opposite sense to the others (the synchrotron mode here):
    # its fractional tune in the usual sense is 1 - Q.
    mu > pi && println("    (oriented tune above pi: the mode rotates in the opposite sense; fractional tune 1 - Q = ", 1 - mu / (2pi), ")")
end

println("Dispersion (physical coordinates):")
show_determined("zeta (crab dispersion, (x, px, y, py) per unit z)", r.physical.zeta)
show_determined("eta (momentum dispersion, (x, px, y, py) per unit delta)", r.physical.eta)
show_determined("h (longitudinal factor)", r.physical.h)

println("Configuration report (option, status):")
for e in configuration_report(r)
    println("  ", e.name, " => ", e.status, "  (requested ", e.requested, ", resolved ", e.resolved, ")")
end

println("Normal modes (scaled coordinates: tune and signed areas per plane):")
for j in 1:3
    m = normal_mode(r, j)
    println("  mode ", j, ": tune = ", m.tune, "  signed_area (x, y, z) = ", m.signed_area)
end

println("Matched rms beam sizes for mode emittances ", config.emittances, ":")
sizes = sqrt.(diag(matched_covariance(r, config.emittances)))
for (name, s) in zip(("x", "px", "y", "py", "z", "delta"), sizes)
    println("  rms ", name, " = ", s)
end

println("Residual checks (name, value, tolerance):")
for (name, value, tol) in r.diagnostics.residuals
    println("  ", name, ": ", value, " <= ", tol)
end
