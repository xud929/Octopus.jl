# Behavioural fingerprint for the 2026-08-05_b comprehensive audit (Phase 13).
#
# Captured BEFORE the first source modification. Rerunning the tests afterwards
# shows the tests still pass; this shows that everything ELSE is unchanged.
# Full precision, one value per line, sorted and greppable so `diff` is exact.
#
#   julia --startup-file=no --project=. <this> > baseline.txt
#
using Octopus
using Printf

const OUT = stdout

f(x) = @sprintf("%.17e", x)

function emit(tag, rep)
    for (nm, v) in (("x", rep.x), ("px", rep.px), ("y", rep.y),
                    ("py", rep.py), ("z", rep.z), ("pz", rep.pz))
        for i in eachindex(v)
            println(OUT, tag, "|", nm, "[", i, "]=", f(v[i]))
        end
    end
end

# Deterministic, hand-written particles: no RNG in the initial state, so any
# difference is the map's, not the generator's. Amplitudes are realistic
# (100 um x, 10 um y, 1 cm z) with one on-axis particle and one at large
# amplitude to exercise branch boundaries.
function fresh()
    x  = [0.0,  1.0e-4, -2.0e-4,  5.0e-5,  3.0e-3, -1.0e-6,  8.0e-5, -4.0e-4]
    px = [0.0,  2.0e-6, -1.0e-6,  4.0e-7,  1.0e-5,  3.0e-8, -2.0e-6,  9.0e-7]
    y  = [0.0,  1.0e-5, -3.0e-5,  8.0e-6,  2.0e-4, -5.0e-7,  1.2e-5, -2.2e-5]
    py = [0.0,  3.0e-7, -2.0e-7,  1.0e-7,  4.0e-6,  7.0e-9, -8.0e-7,  5.0e-7]
    z  = [0.0,  1.0e-2, -2.0e-2,  5.0e-3,  4.0e-2, -1.0e-4,  7.0e-3, -1.5e-2]
    pz = [0.0,  1.0e-4, -2.0e-4,  3.0e-5,  1.0e-3, -1.0e-6,  6.0e-5, -8.0e-5]
    return Phase6DRep(copy(x), copy(px), copy(y), copy(py), copy(z), copy(pz))
end

# The canonical 30-kind line, taken verbatim from
# validation/tracking_backend_consistency.jl (which carries the
# declaration<->coverage tripwire, so it is the authoritative full-kind list).
const LINE = (
    ("linear6d", Linear6DSpec{Float64}(; beta1=(0.8, 0.072, 90.0), beta2=(0.82, 0.075, 91.0),
        alpha1=(0.0, 0.0, 0.0), alpha2=(0.01, -0.02, 0.0), dmu=(0.08, 0.12, 0.02))),
    ("crab_dispersion", CrabDispersionSpec{Float64}(zeta1=0.02, zeta2=-0.01, zeta3=0.004, zeta4=0.002)),
    ("momentum_dispersion", MomentumDispersionSpec{Float64}(eta1=0.03, eta2=-0.006, eta3=0.002, eta4=0.01)),
    ("xy_coupling", XYCouplingSpec{Float64}(r1=0.01, r2=-0.003, r3=0.002, r4=0.004)),
    ("lorentz_boost", LorentzBoostSpec(0.01)),
    ("thin_crab_cavity", ThinCrabCavitySpec{2}(197.0e6; strengthX=(1.0e-5, -2.0e-6),
        strengthY=(3.0e-6, 0.0), phase=(0.0, 0.2))),
    ("rev_lorentz_boost", RevLorentzBoostSpec(0.01)),
    ("chromaticity_kick", ChromaticityKickSpec{Float64}(; xi=(1.2, -0.8), beta=(0.82, 0.075),
        alpha=(0.01, -0.02), zeta=(0.002, -0.001, 0.0, 0.0), eta=(0.001, 0.0, -0.001, 0.0),
        R=(0.001, -0.0005, 0.0003, 0.0007))),
    ("thin_strong_beam", ThinStrongBeamSpec{Float64}(; kbb=1.0e-8, klum=1.0, beta=(0.82, 0.075),
        alpha=(0.01, -0.02), sigma=(110.0e-6, 12.0e-6), center=(2.0e-6, -1.0e-6, 0.0),
        angle=(0.0, 0.0, 0.0))),
    ("gaussian_strong_beam", GaussianStrongBeamSpec{Float64}(;
        thin=ThinStrongBeamSpec{Float64}(; kbb=8.0e-9, klum=1.0, beta=(0.82, 0.075),
            alpha=(0.01, -0.02), sigma=(115.0e-6, 13.0e-6), center=(-1.0e-6, 1.5e-6, 0.0),
            angle=(0.0, 0.0, 0.0)), ns=3, sigz=7.0e-3, slice_method=:equal_area)),
    ("lumped_radiation", LumpedRadSpec{Float64}(; damping_turns=(4000.0, 4000.0, 2000.0),
        beta=(0.8, 0.072, 90.0), alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), rng_id=101)),
    ("drift", DriftSpec(L=0.35, h=0.02)),
    ("quadrupole", QuadrupoleSpec(L=0.4, k1=0.8, nst=2, fringe=:all, va=0.03, vs=1.0e-4, x_offset=1.0e-4)),
    ("sextupole", SextupoleSpec(L=0.25, k2=6.0, nst=2, tilt=0.01)),
    ("octupole", OctupoleSpec(L=0.15, k3=80.0, nst=2)),
    ("multipole", MultipoleSpec(L=0.3, k1=0.5, k2=4.0, nst=2, y_offset=1.0e-4)),
    ("sbend", SBendSpec(L=1.1, angle=0.05, k1=0.2, e1=0.02, e2=0.015, fringe=:all, nst=2, ref_tilt=0.05)),
    ("solenoid", SolenoidSpec(L=0.8, ks=0.3, kn=(0.0, 0.2), nst=2)),
    ("thin_rf_cavity", ThinRFCavitySpec(197.0e6; strength=1.0e-4, beta0=0.99, gamma0=100.0)),
    ("patch", PatchSpec(dx=1.0e-5, dz=2.0e-5, angle_x=1.0e-4, angle_s=0.01)),
    ("marker", MarkerSpec()),
    ("thin_multipole", ThinMultipoleSpec(knl=(0.0, 0.05, 1.2))),
    ("thin_dipole", ThinDipoleSpec(k0l=1.0e-3)),
    ("thin_quadrupole", ThinQuadrupoleSpec(k1l=0.05)),
    ("thin_sextupole", ThinSextupoleSpec(k2l=1.2)),
    ("hkicker", HKickerSpec(hkick=1.0e-4)),
    ("vkicker", VKickerSpec(vkick=1.0e-4)),
    ("kicker", KickerSpec(hkick=1.0e-4, vkick=-5.0e-5)),
    ("aperture", ApertureSpec(shape=:ellipse, x_limit=1.0, y_limit=1.0)),
)

# --- Part 1: every element kind in isolation, same input, one turn ----------
# Localises a diff to a single element rather than to the composed line.
for (nm, spec) in LINE
    set_global_rng!(seed=20260805, method=:philox)
    rep = fresh()
    task = TrackingTask((spec,))
    execute!(task, rep; turns = 1)
    emit("elem/" * nm, rep)
end

# --- Part 2: the composed 29-element line, three turns ---------------------
set_global_rng!(seed=20260805, method=:philox)
let rep = fresh(), task = TrackingTask(Tuple(s for (_, s) in LINE))
    execute!(task, rep; turns = 3)
    emit("line/3turns", rep)
end

# --- Part 3: beam statistics on a seeded random beam -----------------------
set_global_rng!(seed=20260805, method=:philox)
let beam = Beam(4096, CPUThreadsBackend; beta=(0.8, 0.072, 90.0), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), rng_id=7)
    st = beam_statistics(beam.rep)
    println(OUT, "stats|n=", st.n)
    for (i, m) in enumerate(st.mean);      println(OUT, "stats|mean[", i, "]=", f(m)); end
    for (i, r) in enumerate(st.rms);       println(OUT, "stats|rms[", i, "]=", f(r)); end
    for (i, e) in enumerate(st.emittance); println(OUT, "stats|emit[", i, "]=", f(e)); end
    C = st.covariance
    for i in 1:6, j in 1:6; println(OUT, "stats|cov[", i, ",", j, "]=", f(C[i, j])); end
    for (i, c) in enumerate(st.xz_covariance); println(OUT, "stats|xzcov[", i, "]=", f(c)); end
    for (i, c) in enumerate(st.yz_covariance); println(OUT, "stats|yzcov[", i, "]=", f(c)); end
end

println(OUT, "FINGERPRINT-COMPLETE")
