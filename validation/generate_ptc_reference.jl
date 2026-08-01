"""
Generate the PTC reference table that `PTCConsistencyContract` checks against.

This script needs MAD-X on `PATH`; the *contract* does not, because the table it
produces is committed. Regenerate only when the case list changes, and record
the MAD-X version in the table header when you do.

Reference model
---------------
PTC as distributed with MAD-X, driven through `ptc_create_layout` with the flag
set pinned in `docs/theory/lattice_hamiltonian_and_conventions.md` Section 7:

    TIME  = false     convention #3, delta = dP/P0 (what Octopus tracks)
    EXACT = true      exact Hamiltonian, NOT MAD-X's expanded default
    MODEL = 1         drift-kick-drift, matching our splitting
    METHOD, NST       integrator order and step count, varied per case

`EXACT=false` is the PTC default and silently selects the expanded Hamiltonian,
so leaving it out would validate the wrong model.

The hard-edge multipole fringe is switched on **per element**, with
`permfringe=true`, and deliberately not with `ptc_setswitch, fringe=true`. The
global switch cannot be placed anywhere that works: `ptc_setfringe` ends with
`default = intstate; call update_states` (`madx_ptc_intstate.f90`), so calling it
*after* `ptc_create_layout` overwrites the state the layout established and
silently reverts `TIME` to true -- changing the longitudinal variable itself,
with the giveaway being a `z` error of `L * pt * (1/beta0^2 - 1)` on a particle
that has no transverse coordinates at all, which no fringe map could produce.
Calling it *before* `ptc_create_layout` keeps `TIME=false`, but the layout then
resets the state and the fringe never runs. The per-element attribute is set at
element construction and survives both.

Coordinate mapping
------------------
PTC's `T` column is conjugate to `delta` with the opposite orientation to the
transverse pairs (Section 5.3, confirmed four ways plus directly against MAD-X
output), so

    Octopus (x, px, y, py, z, pz)  <->  PTC (X, PX, Y, PY, -T, PT)

Outputs
-------
`validation/reference/ptc_madx_<version>.tsv` -- one row per (case, particle),
carrying both the initial and final coordinates so the contract needs nothing
but the table.

Run
---
    julia --project=. validation/generate_ptc_reference.jl
"""

using Printf

const HERE = @__DIR__
const OUTDIR = joinpath(HERE, "reference")
const WORK = mktempdir()

# Test particles: on-axis, off-momentum, and large-amplitude in each plane.
const PARTICLES = [
    (0.0,     0.0,     0.0,     0.0,     0.0),
    (1.3e-3,  3.0e-4, -0.9e-3, -2.2e-4,  1.1e-3),
    (-2.1e-3, -5.0e-4, 1.7e-3,  4.0e-4, -8.0e-4),
    (4.0e-3,  9.0e-4,  3.0e-3,  7.0e-4,  2.5e-3),
    (0.0,     0.0,     0.0,     0.0,     3.0e-3),
]

"""
One reference case: a MAD-X element definition plus the PTC integrator setting.
`octopus` names the spec keywords the contract will build from.
"""
struct Case
    name::String
    madx::String          # element definition body, e.g. "quadrupole, l=0.4, k1=1.7"
    L::Float64
    method::Int
    nst::Int
    fringe::Bool          # per-element permfringe -- turns on MULTIPOLE_FRINGE
    octopus::Dict{Symbol,Any}
end

# Fringe defaults off, so the cases that predate the fringe comparison keep
# generating byte-identical rows: the switch is only emitted when it is on.
Case(name, madx, L, method, nst, octopus) = Case(name, madx, L, method, nst, false, octopus)

const CASES = Case[
    Case("drift", "drift, l=0.7", 0.7, 2, 1,
         Dict(:kind => :drift, :L => 0.7)),
    Case("quadrupole_m2_n1", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 1,
         Dict(:kind => :quadrupole, :L => 0.4, :kn => (0.0, 1.7), :nst => 1, :integrator_order => 2)),
    Case("quadrupole_m2_n8", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 8,
         Dict(:kind => :quadrupole, :L => 0.4, :kn => (0.0, 1.7), :nst => 8, :integrator_order => 2)),
    Case("quadrupole_m4_n3", "quadrupole, l=0.4, k1=1.7", 0.4, 4, 3,
         Dict(:kind => :quadrupole, :L => 0.4, :kn => (0.0, 1.7), :nst => 3, :integrator_order => 4)),
    Case("quadrupole_skew", "quadrupole, l=0.4, k1s=0.9", 0.4, 2, 4,
         Dict(:kind => :quadrupole, :L => 0.4, :ks => (0.0, 0.9), :nst => 4, :integrator_order => 2)),
    Case("sextupole_m2_n4", "sextupole, l=0.25, k2=14.0", 0.25, 2, 4,
         Dict(:kind => :sextupole, :L => 0.25, :kn => (0.0, 0.0, 14.0), :nst => 4, :integrator_order => 2)),
    Case("sextupole_m4_n2", "sextupole, l=0.25, k2=14.0", 0.25, 4, 2,
         Dict(:kind => :sextupole, :L => 0.25, :kn => (0.0, 0.0, 14.0), :nst => 2, :integrator_order => 4)),
    Case("octupole_m2_n4", "octupole, l=0.15, k3=220.0", 0.15, 2, 4,
         Dict(:kind => :octupole, :L => 0.15, :kn => (0.0, 0.0, 0.0, 220.0), :nst => 4, :integrator_order => 2)),
    Case("sbend_m2_n1", "sbend, l=1.1, angle=0.198", 1.1, 2, 1,
         Dict(:kind => :sbend, :L => 1.1, :h => 0.198 / 1.1, :b0 => 0.198 / 1.1, :nst => 1)),
    Case("sbend_m2_n4", "sbend, l=1.1, angle=0.198", 1.1, 2, 4,
         Dict(:kind => :sbend, :L => 1.1, :h => 0.198 / 1.1, :b0 => 0.198 / 1.1, :nst => 4)),
    Case("sbend_m4_n2", "sbend, l=1.1, angle=0.198", 1.1, 4, 2,
         Dict(:kind => :sbend, :L => 1.1, :h => 0.198 / 1.1, :b0 => 0.198 / 1.1, :nst => 2)),
    # angle=0 makes a MAD-X sbend a straight combined magnet, which is exactly
    # a thick general multipole -- MAD-X's own MULTIPOLE element is thin.
    Case("multipole_m2_n4", "sbend, l=0.3, angle=0, k1=1.2, k2=8.0", 0.3, 2, 4,
         Dict(:kind => :multipole, :L => 0.3)),
    Case("multipole_m4_n2", "sbend, l=0.3, angle=0, k1=1.2, k2=8.0, k3=90.0", 0.3, 4, 2,
         Dict(:kind => :multipole, :L => 0.3)),
    # Combined-function bends: the curved-frame multipole kick of Section 4.4.
    Case("cfbend_m2_n4", "sbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4,
         Dict(:kind => :sbend, :L => 1.1, :h => 0.198 / 1.1, :b0 => 0.198 / 1.1, :nst => 4)),
    Case("cfbend_m4_n2", "sbend, l=1.1, angle=0.198, k1=0.6, k2=5.0", 1.1, 4, 2,
         Dict(:kind => :sbend, :L => 1.1, :h => 0.198 / 1.1, :b0 => 0.198 / 1.1, :nst => 2)),
    # ---------------------------------------------------------------------
    # Hard-edge multipole fringe, via ptc_setswitch. Each case pins one branch
    # of PTC's MULTIPOLE_FRINGER that a source comparison turned up:
    #   quadrupole_fringe  the ordinary J=2 term
    #   multipole_fringe   HIGHEST_FRINGE=2 caps the loop, so K2 is excluded
    #   sbend_fringe       NMUL<=1 skips the multipole fringe outright
    #   cfbend_fringe      J==1 with BEND_FRINGE drops BN(1), which would
    #                      otherwise double-count the exact dipole fringe
    # ---------------------------------------------------------------------
    Case("quadrupole_fringe", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, true,
         Dict(:kind => :quadrupole, :L => 0.4)),
    Case("multipole_fringe", "sbend, l=0.3, angle=0, k1=1.2, k2=8.0", 0.3, 2, 4, true,
         Dict(:kind => :multipole, :L => 0.3)),
    Case("sbend_fringe", "sbend, l=1.1, angle=0.198", 1.1, 2, 4, true,
         Dict(:kind => :sbend, :L => 1.1)),
    Case("cfbend_fringe", "sbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4, true,
         Dict(:kind => :sbend, :L => 1.1)),
    # ---------------------------------------------------------------------
    # Pole-face angles. Fringes stay off here, which is what selects PTC's
    # MAD8_WEDGE branch: the quadrupole-in-wedge kick with its coefficients
    # hardcoded to (1,2). cfbend_edge is the only case that exercises it,
    # because the term needs both a nonzero edge angle and a quadrupole
    # component. sbend_fint adds the FINT/HGAP terms of FRINGE_dipole.
    # ---------------------------------------------------------------------
    Case("sbend_edge", "sbend, l=1.1, angle=0.198, e1=0.1, e2=0.1", 1.1, 2, 4,
         Dict(:kind => :sbend, :L => 1.1)),
    Case("cfbend_edge", "sbend, l=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1", 1.1, 2, 4,
         Dict(:kind => :sbend, :L => 1.1)),
    Case("sbend_fint",
         "sbend, l=1.1, angle=0.198, e1=0.1, e2=0.1, fint=0.5, fintx=0.5, hgap=0.03",
         1.1, 2, 4, Dict(:kind => :sbend, :L => 1.1)),
]

function madx_version()
    out = read(pipeline(`sh -c "printf 'stop;\n' > $WORK/v.madx && madx $WORK/v.madx"`), String)
    m = match(r"MAD-X\s+([0-9.]+)", out)
    m === nothing && error("could not determine the MAD-X version")
    return m.captures[1]
end

function run_case(case::Case)
    job = "job.madx"
    out = "out"          # MAD-X writes relative to its working directory
    starts = join(("ptc_start, x=$(p[1]), px=$(p[2]), y=$(p[3]), py=$(p[4]), pt=$(p[5]);"
                   for p in PARTICLES), "\n")
    open(joinpath(WORK, job), "w") do io
        print(io, """
        option, -echo, -info, -warn;
        beam, particle=proton, energy=10.0, sequence=lat;
        el: $(case.madx)$(case.fringe ? ", permfringe=true" : "");
        lat: sequence, l=$(case.L);
          el, at=$(case.L / 2);
        endsequence;
        use, sequence=lat;
        ptc_create_universe;
        ptc_create_layout, model=1, method=$(case.method), nst=$(case.nst),
                           exact=true, time=false;
        $starts
        ptc_track, icase=6, closed_orbit=false, turns=1, element_by_element,
                   onetable, dump, file=$out;
        ptc_track_end;
        ptc_end;
        stop;
        """)
    end
    run(pipeline(Cmd(`madx $job`; dir=WORK), devnull))
    rows = Dict{Int,NTuple{6,Float64}}()
    seen_end = false
    for line in eachline(joinpath(WORK, out * "one"))
        if startswith(line, "#segment")
            seen_end = occursin("end", line)
            continue
        end
        (startswith(line, "@") || startswith(line, "*") || startswith(line, "\$")) && continue
        seen_end || continue
        f = split(strip(line))
        length(f) < 8 && continue
        id = parse(Int, f[1])
        rows[id] = (parse(Float64, f[3]), parse(Float64, f[4]), parse(Float64, f[5]),
                    parse(Float64, f[6]), parse(Float64, f[7]), parse(Float64, f[8]))
    end
    length(rows) == length(PARTICLES) ||
        error("case $(case.name): expected $(length(PARTICLES)) tracked particles, got $(length(rows))")
    return rows
end

version = madx_version()
mkpath(OUTDIR)
path = joinpath(OUTDIR, "ptc_madx_$(version).tsv")
open(path, "w") do io
    println(io, "# PTC reference for PTCConsistencyContract")
    println(io, "# MAD-X version: $version")
    println(io, "# flags: model=1 (drift-kick-drift), exact=true, time=false")
    println(io, "# columns hold OCTOPUS coordinates: PTC's T is negated on write,")
    println(io, "# because its longitudinal variable is conjugate to delta with the")
    println(io, "# opposite orientation (theory note Section 5.3).")
    println(io, join(["case", "particle", "x0", "px0", "y0", "py0", "z0", "pz0",
                      "x1", "px1", "y1", "py1", "z1", "pz1"], "\t"))
    for case in CASES
        rows = run_case(case)
        for (i, p) in enumerate(PARTICLES)
            f = rows[i]
            @printf(io, "%s\t%d\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\n",
                    case.name, i, p[1], p[2], p[3], p[4], 0.0, p[5],
                    f[1], f[2], f[3], f[4], -f[5], f[6])
        end
        println("  $(case.name): ok")
    end
end
println("\nMAD-X $version -> $path")
