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

# MAD-X refuses a zero-length sequence, so a thin element is tracked as itself
# followed by a drift. The contract composes the same two-element line, which is
# why a reference case may name a list of specs rather than one.
const THIN_SEQ_L = 0.2

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
The Octopus spec each case is compared against lives in ONE place,
`_ptc_reference_specs()` in `src/contracts/Contracts.jl`, keyed by `name`. A
`Case` once carried its own copy as an `octopus` Dict that nothing read; the
copy had already drifted (a `multipole` missing its strengths, an
unregistered `:rbend` kind), which is what an unread duplicate does
(2026-08-05 audit, U21-6).
"""
struct Case
    name::String
    madx::String          # element definition body, e.g. "quadrupole, l=0.4, k1=1.7"
    L::Float64
    method::Int
    nst::Int
    fringe::Bool          # per-element permfringe -- turns on MULTIPOLE_FRINGE
    ealign::String        # EALIGN body, applied through ptc_align; "" for none
end
Case(name, madx, L, method, nst, fringe::Bool) =
    Case(name, madx, L, method, nst, fringe, "")

# Fringe defaults off, so the cases that predate the fringe comparison keep
# generating byte-identical rows: the switch is only emitted when it is on.
Case(name, madx, L, method, nst) = Case(name, madx, L, method, nst, false, "")

const CASES = Case[
    Case("drift", "drift, l=0.7", 0.7, 2, 1),
    Case("quadrupole_m2_n1", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 1),
    Case("quadrupole_m2_n8", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 8),
    Case("quadrupole_m4_n3", "quadrupole, l=0.4, k1=1.7", 0.4, 4, 3),
    Case("quadrupole_skew", "quadrupole, l=0.4, k1s=0.9", 0.4, 2, 4),
    Case("sextupole_m2_n4", "sextupole, l=0.25, k2=14.0", 0.25, 2, 4),
    Case("sextupole_m4_n2", "sextupole, l=0.25, k2=14.0", 0.25, 4, 2),
    Case("octupole_m2_n4", "octupole, l=0.15, k3=220.0", 0.15, 2, 4),
    Case("sbend_m2_n1", "sbend, l=1.1, angle=0.198", 1.1, 2, 1),
    Case("sbend_m2_n4", "sbend, l=1.1, angle=0.198", 1.1, 2, 4),
    Case("sbend_m4_n2", "sbend, l=1.1, angle=0.198", 1.1, 4, 2),
    # angle=0 makes a MAD-X sbend a straight combined magnet, which is exactly
    # a thick general multipole -- MAD-X's own MULTIPOLE element is thin.
    Case("multipole_m2_n4", "sbend, l=0.3, angle=0, k1=1.2, k2=8.0", 0.3, 2, 4),
    Case("multipole_m4_n2", "sbend, l=0.3, angle=0, k1=1.2, k2=8.0, k3=90.0", 0.3, 4, 2),
    # Combined-function bends: the curved-frame multipole kick of Section 4.4.
    Case("cfbend_m2_n4", "sbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4),
    Case("cfbend_m4_n2", "sbend, l=1.1, angle=0.198, k1=0.6, k2=5.0", 1.1, 4, 2),
    # ---------------------------------------------------------------------
    # Hard-edge multipole fringe, via ptc_setswitch. Each case pins one branch
    # of PTC's MULTIPOLE_FRINGER that a source comparison turned up:
    #   quadrupole_fringe  the ordinary J=2 term
    #   multipole_fringe   HIGHEST_FRINGE=2 caps the loop, so K2 is excluded
    #   sbend_fringe       NMUL<=1 skips the multipole fringe outright
    #   cfbend_fringe      J==1 with BEND_FRINGE drops BN(1), which would
    #                      otherwise double-count the exact dipole fringe
    # ---------------------------------------------------------------------
    Case("quadrupole_fringe", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, true),
    Case("multipole_fringe", "sbend, l=0.3, angle=0, k1=1.2, k2=8.0", 0.3, 2, 4, true),
    Case("sbend_fringe", "sbend, l=1.1, angle=0.198", 1.1, 2, 4, true),
    Case("cfbend_fringe", "sbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4, true),
    # ---------------------------------------------------------------------
    # Pole-face angles. Fringes stay off here, which is what selects PTC's
    # MAD8_WEDGE branch: the quadrupole-in-wedge kick with its coefficients
    # hardcoded to (1,2). cfbend_edge is the only case that exercises it,
    # because the term needs both a nonzero edge angle and a quadrupole
    # component. sbend_fint adds the FINT/HGAP terms of FRINGE_dipole.
    # ---------------------------------------------------------------------
    Case("sbend_edge", "sbend, l=1.1, angle=0.198, e1=0.1, e2=0.1", 1.1, 2, 4),
    Case("cfbend_edge", "sbend, l=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1", 1.1, 2, 4),
    Case("sbend_fint",
         "sbend, l=1.1, angle=0.198, e1=0.1, e2=0.1, fint=0.5, fintx=0.5, hgap=0.03",
         1.1, 2, 4),
    # ---------------------------------------------------------------------
    # Misalignments, through EALIGN + ptc_align. One degree of freedom each:
    # MAD-X references a misalignment to the ENTRANCE frame (see
    # MAD_MISALIGN_FIBRE), so these pin misalign_convention = :madx, and they
    # pin the keyword mapping dx/dy/ds -> x/y/z_offset and
    # dtheta/dphi/dpsi -> x_pitch/y_pitch/tilt.
    #
    # One at a time first, because a single rotation cannot distinguish the two
    # composition orders -- MAD-X composes intrinsically as R_z R_x R_y, Bmad
    # about fixed axes as R_y R_x R_z, and they agree for any one of them. The
    # multi-rotation cases that DO separate them follow below.
    # ---------------------------------------------------------------------
    Case("quad_mis_dx", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "dx=1.0e-3"),
    Case("quad_mis_dy", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "dy=-8.0e-4"),
    Case("quad_mis_ds", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "ds=2.0e-3"),
    Case("quad_mis_dtheta", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "dtheta=3.0e-3"),
    Case("quad_mis_dphi", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "dphi=3.0e-3"),
    Case("quad_mis_dpsi", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "dpsi=0.03"),
    Case("sext_mis_dx", "sextupole, l=0.25, k2=14.0", 0.25, 2, 4, false,
         "dx=1.0e-3"),
    # All six at once. These are what distinguish the two rotation-composition
    # conventions: MAD-X composes intrinsically as R_z R_x R_y, Bmad about fixed
    # axes as R_y R_x R_z, and the two agree for any single rotation, so only a
    # multi-rotation case can tell them apart.
    Case("quad_mis_all", "quadrupole, l=0.4, k1=1.7", 0.4, 2, 4, false,
         "dx=1.0e-3, dy=-8.0e-4, ds=2.0e-3, dtheta=1.0e-3, dphi=-7.0e-4, dpsi=0.02"),
    # Misaligned bends, which exercise the survey: the exit transform is built
    # from the exit geometry, and the design frame has turned by hL in between.
    Case("cfbend_mis_dx", "sbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4, false,
         "dx=1.0e-3"),
    Case("cfbend_mis_all", "sbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4, false,
         "dx=1.0e-3, dy=-8.0e-4, ds=2.0e-3, dtheta=1.0e-3, dphi=-7.0e-4, dpsi=0.02"),
    # ---------------------------------------------------------------------
    # ref_tilt: the roll of the DESIGN ORBIT plane, which MAD-X spells `tilt`
    # on the element itself rather than through EALIGN. This is the keyword
    # trap the whole feature exists for -- MAD-X's bend `tilt` is Bmad's
    # `ref_tilt` and NOT Octopus's `tilt`, which is the body roll EALIGN sets
    # with dpsi -- so these cases pin the meaning, not just the arithmetic.
    #
    # `reftilt_vertical` is a literal pi/2: a vertical bend, which is the case
    # that was inexpressible before and the one a sign error cannot survive,
    # since it puts the entire dispersion in the other plane.
    #
    # The last two are the ORDERING cases and are the reason this is not a
    # one-parameter comparison. `ref_tilt` is design geometry and a
    # misalignment is an error measured against that design, so the roll must
    # compose OUTSIDE the misalignment frames: MAD_MISALIGN_FIBRE displaces a
    # fibre whose frames already carry the element tilt. Getting it inverted is
    # invisible unless both are nonzero, exactly as the rotation-composition
    # convention was, so a single-parameter case cannot see it.
    # ---------------------------------------------------------------------
    Case("sbend_reftilt", "sbend, l=1.1, angle=0.198, tilt=0.3", 1.1, 2, 4),
    Case("sbend_reftilt_vertical",
         "sbend, l=1.1, angle=0.198, tilt=1.5707963267948966", 1.1, 2, 4),
    Case("cfbend_reftilt", "sbend, l=1.1, angle=0.198, k1=0.6, tilt=0.3", 1.1, 2, 4),
    Case("cfbend_reftilt_mis_dx", "sbend, l=1.1, angle=0.198, k1=0.6, tilt=0.3",
         1.1, 2, 4, false, "dx=1.0e-3"),
    Case("cfbend_reftilt_mis_all", "sbend, l=1.1, angle=0.198, k1=0.6, tilt=0.3",
         1.1, 2, 4, false,
         "dx=1.0e-3, dy=-8.0e-4, ds=2.0e-3, dtheta=1.0e-3, dphi=-7.0e-4, dpsi=0.02"),
    # A spread of roll angles. Octopus cannot be quadrant-sensitive -- the map
    # is two sincos values and four multiply-adds, with no branch and no atan --
    # so these are really a check on MAD-X, which is free to normalise, wrap, or
    # special-case `tilt` in ways no amount of reading our own source reveals.
    #
    #   neg      negative roll, and a different magnitude from 0.3
    #   quarter  cos = sin, the one angle where swapping them is invisible;
    #            useless alone, worth having alongside the others
    #   obtuse   cos < 0, the second quadrant
    #   pi       the full flip -- a horizontal bend deflecting the other way
    #   small    1e-3, the near-identity regime real design rolls live in
    #
    # `neg_mis_all` repeats the ordering case at a negative roll, because the
    # `:madx` fix conjugates by R_z(-psi) and a sign slip there would survive
    # every positive-angle case.
    Case("sbend_reftilt_neg", "sbend, l=1.1, angle=0.198, tilt=-0.7", 1.1, 2, 4),
    Case("cfbend_reftilt_quarter",
         "sbend, l=1.1, angle=0.198, k1=0.6, tilt=0.7853981633974483", 1.1, 2, 4),
    Case("sbend_reftilt_obtuse", "sbend, l=1.1, angle=0.198, tilt=2.4", 1.1, 2, 4),
    Case("sbend_reftilt_pi", "sbend, l=1.1, angle=0.198, tilt=3.141592653589793",
         1.1, 2, 4),
    Case("sbend_reftilt_small", "sbend, l=1.1, angle=0.198, tilt=1.0e-3", 1.1, 2, 4),
    Case("cfbend_reftilt_neg_mis_all", "sbend, l=1.1, angle=0.198, k1=0.6, tilt=-0.7",
         1.1, 2, 4, false,
         "dx=1.0e-3, dy=-8.0e-4, ds=2.0e-3, dtheta=1.0e-3, dphi=-7.0e-4, dpsi=0.02"),
    # RBEND: a sector bend with angle/2 added to each face. `option, rbarc=false`
    # above matters -- by default MAD-X treats an RBEND's l as the CHORD and
    # converts to arc, while Octopus's L is the arc, so without it the two
    # magnets differ in length.
    Case("rbend", "rbend, l=1.1, angle=0.198", 1.1, 2, 4),
    Case("rbend_k1", "rbend, l=1.1, angle=0.198, k1=0.6", 1.1, 2, 4),
    # A rolled RBEND. Worth its own cases rather than inheriting the SBEND
    # ones: an RBEND reaches the sector-bend map through a conversion that adds
    # angle/2 to each pole face, and `ref_tilt` has to survive that conversion
    # and compose with the resulting face angles. The vertical case is the one
    # a real lattice wants -- a vertical RBEND -- and the last one carries the
    # roll and a misalignment together, so the RBEND path is held to the same
    # two-parameter ordering test as the sector bend.
    Case("rbend_reftilt", "rbend, l=1.1, angle=0.198, tilt=0.3", 1.1, 2, 4),
    Case("rbend_reftilt_vertical",
         "rbend, l=1.1, angle=0.198, tilt=1.5707963267948966", 1.1, 2, 4),
    Case("rbend_k1_reftilt_mis_all", "rbend, l=1.1, angle=0.198, k1=0.6, tilt=0.3",
         1.1, 2, 4, false,
         "dx=1.0e-3, dy=-8.0e-4, ds=2.0e-3, dtheta=1.0e-3, dphi=-7.0e-4, dpsi=0.02"),
    # Thin multipole: MAD-X's MULTIPOLE is zero length with integrated KNL/KSL,
    # which is exactly what ThinMultipoleSpec means.
    Case("thin_multipole", "multipole, knl={0.0, 0.05, 1.2}", 0.0, 2, 1),
    Case("thin_multipole_skew", "multipole, knl={0.0, 0.05}, ksl={0.0, 0.0, 0.8}", 0.0, 2, 1),
    # Solenoid. Both polarities, deliberately: the sign of ks follows the charge
    # convention and the field direction, so agreement at one polarity proves
    # nothing about the other, and a sign error is invisible in any quantity
    # that is even in ks. Two strengths so the ks-dependence is exercised, not
    # just one working point.
    Case("solenoid_pos", "solenoid, l=1.3, ks=0.35", 1.3, 2, 1),
    Case("solenoid_neg", "solenoid, l=1.3, ks=-0.35", 1.3, 2, 1),
    Case("solenoid_strong", "solenoid, l=2.0, ks=1.7", 2.0, 2, 1),
    # Solenoid with a superimposed multipole. PTC's SOL5 carries AN/BN natively
    # and interleaves KICK_SOL with KICKMUL, so this exercises our Strang
    # splitting against PTC's -- the two pieces do not commute, so agreement
    # here tests the splitting and not just the solenoid.
    # MAD-X's solenoid takes the INTEGRATED knl/ksl, not the thick k1 its
    # quadrupole takes -- `solenoid, k1=...` is rejected outright as an illegal
    # keyword. So the body is written with knl = k1*L = 0.6*1.3 = 0.78 while our
    # spec carries the thick k1 = 0.6, matching how every other thick magnet in
    # Octopus is spelled. Getting this conversion backwards is a factor of L.
    Case("solenoid_k1_n8", "solenoid, l=1.3, ks=0.35, knl={0.0, 0.78}", 1.3, 2, 8),
    Case("solenoid_k1_n32", "solenoid, l=1.3, ks=0.35, knl={0.0, 0.78}", 1.3, 2, 32),
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
        option, rbarc=false;   // RBEND l is the ARC length, as Octopus means it
        beam, particle=proton, energy=10.0, sequence=lat;
        el: $(case.madx)$(case.fringe ? ", permfringe=true" : "");
        lat: sequence, l=$(case.L == 0 ? THIN_SEQ_L : case.L);
          el, at=$(case.L == 0 ? 0.0 : case.L / 2);
        endsequence;
        use, sequence=lat;
        $(isempty(case.ealign) ? "" :
          "select, flag=error, clear;\n        select, flag=error, range=el;\n        ealign, " * case.ealign * ";")
        ptc_create_universe;
        ptc_create_layout, model=1, method=$(case.method), nst=$(case.nst),
                           exact=true, time=false;
        $(isempty(case.ealign) ? "" : "ptc_align;")
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
# Write to a temporary file and rename only on success. `open(path, "w")`
# TRUNCATES the committed reference before the first of 55 MAD-X jobs runs, so
# any failure part-way through -- a non-zero MAD-X exit, a short particle count,
# a missing output file -- left a partial table in the working tree: destroy the
# artifact first, detect later. The contract's declared-spec tripwire does catch
# a truncated table loudly, and `git checkout` recovers it, but neither is a
# reason to break it first (2026-08-05_b audit, U24-10). `mv` within the same
# directory is atomic on POSIX, so there is no window where `path` is partial.
tmp_path = path * ".partial-$(getpid())"
ok = false
try
open(tmp_path, "w") do io
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
global ok = true
finally
    if ok
        mv(tmp_path, path; force=true)
    else
        rm(tmp_path; force=true)
        @warn "PTC reference generation failed; the committed table is untouched" path
    end
end
println("\nMAD-X $version -> $path")
