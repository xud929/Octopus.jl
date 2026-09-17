#=
Twiss and dispersion analysis of a DBA ring with RF, given as a `BeamLine`.

One DBA-type cell (two sector bends around a focusing quadrupole, wrapped in
defocusing quadrupoles: the layout of a double-bend achromat, not tuned
achromatic here, so the cell ends are dispersive) closed by a thin RF cavity
is a ring for the one-turn map: the cell's transverse optics with its
momentum dispersion, plus a synchrotron mode. The ring must have a stable
synchrotron mode (`rf_strength = 0.02` here): without RF the map is coasting
and has none; with the opposite RF sign the longitudinal cluster is unstable.
Either way run 1 selects no mode and the script stops after it, printing the
analysis's reason. `analyze` with a `TwissDispersionAnalysis` runs twice:

1. With the default options the 6D result is `:degraded`: the longitudinal
   mode was selected by the `:max_signed_z_area` heuristic, which the
   analysis does not certify on its own, whatever h (theory (K12): kappa_sz = h
   and the signed z-areas sum to 1, so a betatron mode can carry more z-area,
   and must for h < 1/3; the theory labels the synchrotron mode by
   continuation, 10.4, 13.5, which no endpoint-map rule supplies). The result
   names the selected CANONICAL EIGENVALUE INDEX: the position in
   `result.clusters.eigenvalues` (ascending mod(angle, 2pi)) of either member
   of the mode's conjugate eigenvalue pair (the result echoes the member with
   positive imaginary part), not the normal-mode number 1, 2, 3 of
   `normal_mode`.
2. Passing that index back as `longitudinal_mode` certifies the selection and
   the result is `:passed`: tunes, canonical crab and momentum dispersion,
   the longitudinal factor h, the per-option configuration report, the three
   normal modes (each with its pair of canonical eigenvalue indices), the matched rms
   beam sizes for given mode emittances, and the residual checks.

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
    rf_strength = 0.02,                    # the thin cavity's strength (see ?ThinRFCavitySpec); keep it nonzero and of this sign: at 0.0 the ring is coasting (no synchrotron mode), at -0.02 the longitudinal cluster is unstable, and run 2 has nothing to certify either way
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
# `strict=false` (the default is `true`): under `strict=true` a :failed verdict
# throws an OpticsAnalysisError and a :degraded one is returned either way, so
# the option does not change these two runs; it is set so that a broken edit
# to the ring prints run 2's `failures` list instead of throwing.

println("Run 1: default options")
r1 = analyze(TwissDispersionAnalysis(strict=false, emittances=config.emittances), ring)
println("  status = ", r1.status)
for s in r1.degradations
    println("  degradation: ", s)
end
if r1.dispersion.longitudinal == 0
    # No synchrotron mode was selected, so run 2 has nothing to certify (an
    # explicit index must be positive). The analysis says why and the script
    # repeats it rather than guessing: at rf_strength = 0.0 the map has the
    # coasting structure (unit longitudinal block) and the selection is
    # unavailable with that reason; with the opposite RF sign the longitudinal
    # cluster is unstable and the degradations printed above say so.
    sel = r1.diagnostics.longitudinal_selection
    error("no synchrotron mode was selected (r1.dispersion.longitudinal == 0): ",
          is_determined(sel) ? determined_value(sel).detail : string(sel.reason, ", ", sel.detail),
          "; see run 1 above; the ring needs a nonzero rf_strength of the focusing sign (0.02 here)")
end
println("  heuristic longitudinal selection: canonical eigenvalue index ", r1.dispersion.longitudinal)
println()
# ---------------------------------------------------------------------------
# Run 2: the selection passed back as `longitudinal_mode` certifies it and the
# verdict is :passed. Everything below is read from this result. The number
# passed is a CANONICAL EIGENVALUE INDEX (the position in r1.clusters.eigenvalues,
# ascending mod(angle, 2pi), of either member of the mode's conjugate eigenvalue
# pair; the result echoes the member with positive imaginary part), not the
# normal-mode number: `normal_mode(r, 3)` is this ring's synchrotron mode while
# its canonical indices are r1.dispersion.longitudinal and that index's
# conjugate partner (the "Normal modes" block prints both numberings). Passing
# the normal-mode number would be accepted as a certified selection of a
# different eigenvalue.

println("Run 2: longitudinal_mode = ", r1.dispersion.longitudinal, " (certified; a canonical eigenvalue index)")
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
    # The oriented tune of theory (E5) is the angle mu in [0, 2pi) of the eigenvalue exp(-i mu) whose member has
    # Im(v' S v) < 0. The (E8) normal form M U = U diag(R(mu_j)) is unchanged by mu -> mu - 2pi (R is a rotation), so a
    # value above pi means the mode rotates in the opposite sense to the others (the synchrotron mode here) and its
    # fractional tune in the usual sense is 1 - Q. This gloss is the script's, not the theory's wording.
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

println("Normal modes (scaled coordinates: tune, signed areas per plane, canonical eigenvalue indices):")
# `normal_mode` orders the modes transverse 1, 2, synchrotron 3. `longitudinal_mode` takes a CANONICAL eigenvalue index
# instead: the position in r.clusters.eigenvalues (ascending mod(angle, 2pi)) of either member of the mode's conjugate
# eigenvalue pair. The analysis echoes the member with positive imaginary part (r.dispersion.longitudinal), which is the
# oriented eigenvalue exp(-i mu_j) of `normal_mode` only when mu_j > pi (true for this ring's synchrotron mode; on the
# reversed ring it is the partner). Printed beside each mode as (echoed member, partner) so the two numberings are never
# confused: the synchrotron mode's echoed member is the value run 2 passed.
for j in 1:3
    m = normal_mode(r, j)
    k = argmin(abs.(r.clusters.eigenvalues .- m.eigenvalue))       # the oriented member exp(-i mu_j)
    kp = r.clusters.conjugate_partner[k]
    pair = imag(r.clusters.eigenvalues[k]) > 0 ? (k, kp) : (kp, k)  # (echoed member, partner)
    println("  mode ", j, ": tune = ", m.tune, "  signed_area (x, y, z) = ", m.signed_area,
            "  canonical eigenvalue indices = ", pair, j == 3 ? "  (the synchrotron mode: run 2's longitudinal_mode is the first)" : "")
    j == 3 && pair[1] != r.dispersion.longitudinal && error("the synchrotron mode's canonical eigenvalue pair ", pair,
                                                           " does not start with the certified selection ", r.dispersion.longitudinal)
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
