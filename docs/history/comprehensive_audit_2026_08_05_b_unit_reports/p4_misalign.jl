using Octopus
const O = Octopus
using LinearAlgebra

m(t) = [t[1] t[2] t[3]; t[4] t[5] t[6]; t[7] t[8] t[9]]   # row-major tuple -> Matrix
Rx(a) = [1 0 0; 0 cos(a) -sin(a); 0 sin(a) cos(a)]
Ry(a) = [cos(a) 0 sin(a); 0 1 0; -sin(a) 0 cos(a)]
Rz(a) = [cos(a) -sin(a) 0; sin(a) cos(a) 0; 0 0 1]

th, ph, ps = 0.013, -0.021, 0.037

println("== d1. rotation composition order vs the note (S4 / S6a) ==")
Wb = m(O._misalign_matrix(Float64, th, ph, ps, false))
Wm = m(O._misalign_matrix(Float64, th, ph, ps, true))
ref_b = Ry(th) * Rx(-ph) * Rz(ps)      # note S4:  W_Bmad = R_y(th) R_x(-phi) R_z(psi)
ref_m = Rz(ps) * Rx(-ph) * Ry(th)      # note S6a: W_MADX = R_z(psi) R_x(-phi) R_y(th)
println("  :bmad max|W - Ry(th)Rx(-ph)Rz(ps)| = ", maximum(abs, Wb .- ref_b))
println("  :madx max|W - Rz(ps)Rx(-ph)Ry(th)| = ", maximum(abs, Wm .- ref_m))
println("  max|Wb - Wm| (they must differ)    = ", maximum(abs, Wb .- Wm))
println("  single-rotation agreement (ps only)= ",
        maximum(abs, m(O._misalign_matrix(Float64,0.0,0.0,ps,false)) .-
                     m(O._misalign_matrix(Float64,0.0,0.0,ps,true))))

println()
println("== d2. reference point: sref = L/2 (:bmad) vs 0 (:madx) ==")
L, h, dx = 1.1, 0.18, 0.0
for conv in (:bmad, :madx)
    sref = conv === :madx ? 0.0 : L/2
    W = O._misalign_matrix(Float64, 1.0e-3, 0.0, 0.0, conv === :madx)
    qin, oin, qout, oout = O._misalign_frames(Float64, W, (0.0,0.0,0.0), h, L, sref)
    println("  ", rpad(String(conv),6), " oin = ", round.(oin, sigdigits=6),
            "   oout = ", round.(oout, sigdigits=6))
end

println()
println("== d3. ref_tilt: :madx conjugates, :bmad does not ==")
psi = 0.3
function frames(conv; ref_tilt=0.0)
    s = QuadrupoleSpec(L=1.0, k1=0.3, nst=1, x_offset=1.0e-3, x_pitch=2.0e-3,
                       tilt=1.5e-3, misalign_convention=conv, ref_tilt=ref_tilt)
    el = O._misalignment_wrap(s, O.Marker(Octopus.Symplectic6DMap()))
    return el
end
for conv in (:bmad, :madx)
    a = frames(conv; ref_tilt=0.0)
    b = frames(conv; ref_tilt=psi)
    println("  ", rpad(String(conv),6), " max|qin(psi=0) - qin(psi=0.3)| = ",
            maximum(abs, collect(a.qin) .- collect(b.qin)),
            "   max|oin diff| = ", maximum(abs, collect(a.oin) .- collect(b.oin)))
end
# explicit conjugation check
Wraw = m(O._misalign_matrix(Float64, 2.0e-3, 0.0, 1.5e-3, true))
R    = m(O._misalign_matrix(Float64, 0.0, 0.0, psi, false))
Wexp = R' * Wraw * R
d    = R' * [1.0e-3, 0.0, 0.0]
bm   = frames(:madx; ref_tilt=psi)
qexp, oexp, _, _ = O._misalign_frames(Float64, Tuple(vec(Wexp')), Tuple(d), 0.0, 1.0, 0.0)
println("  :madx conjugation W->R'WR, d->R'd reproduced: max|qin| = ",
        maximum(abs, collect(bm.qin) .- collect(qexp)),
        "  max|oin| = ", maximum(abs, collect(bm.oin) .- collect(oexp)))

println()
println("== d4. the convention values the theory note names ==")
for v in (:center, :entrance, :bmad, :madx)
    s = QuadrupoleSpec(L=1.0, k1=0.3, nst=1, x_offset=1.0e-3, misalign_convention=v)
    r = try
        compile_runtime(s); "accepted"
    catch e
        "REFUSED: " * sprint(showerror, e)[1:min(end,90)]
    end
    println("  misalign_convention=", rpad(repr(v), 11), r)
end

println()
println("== d5. zero length: the two conventions differ only in rotation order ==")
for conv in (:bmad, :madx)
    s = ThinQuadrupoleSpec(k1l=0.05, x_pitch=1.0e-3, y_pitch=2.0e-3, tilt=3.0e-3,
                           misalign_convention=conv)
    el = compile_runtime(s)
    println("  ", rpad(String(conv),6), " oin = ", round.(collect(el.oin), sigdigits=6))
end

println()
println("== d6. a MISALIGNED LINE containing a BEND: survey uses h = 0 ==")
bend = SBendSpec(L=1.1, angle=0.198, k1=0.0, nst=8)
girder = BeamLine("G", bend; x_offset=1.0e-3)
elem_mis = SBendSpec(L=1.1, angle=0.198, k1=0.0, nst=8, x_offset=1.0e-3)
a = compile_runtime(girder)          # MisalignedElement(CompositeLine([bend]))
b = compile_runtime(elem_mis)        # MisalignedElement(LatticeMagnet)
c0 = (1.0e-3, 2.0e-4, -5.0e-4, 1.0e-4, 0.0, 1.0e-3)
oa = a(c0...)
ob = b(c0...)
println("  girder-misaligned  = ", oa)
println("  element-misaligned = ", ob)
println("  max|difference|    = ", maximum(abs, collect(oa) .- collect(ob)))
println("  (same rigid displacement of the same body; they must agree)")
aligned = compile_runtime(BeamLine("G0", bend))
println("  aligned line runtime = ", nameof(typeof(aligned)))

println()
println("== d7. a user-set L on a line silently overrides the real arc length ==")
q = QuadrupoleSpec(L=0.4, k1=1.0, nst=1); d = DriftSpec(L=1.0)
cryo = BeamLine("CRYO", q, d; x_offset=1.0e-4)
println("  total_length(cryo)            = ", O.total_length(cryo))
cryoL = BeamLine("CRYOL", q, d; x_offset=1.0e-4, L=99.0)
println("  total_length(cryoL) with L=99 = ", O.total_length(cryoL))
plain = BeamLine("P", q, d)
plainL = BeamLine("PL", q, d; L=99.0)
println("  a bare L= makes a line own-state (stops dissolving): ",
        O._line_has_own_state(plain), " -> ", O._line_has_own_state(plainL))

println()
println("== d8. an :L override on a nested-line PLACEMENT is ignored ==")
outer = BeamLine("OUT", cryo, d)
e1 = outer[1]
println("  _placement_length before override = ", O._placement_length(e1))
e1.L = 50.0
println("  _placement_length after entry.L=50 = ", O._placement_length(e1),
        "   (getparam(entry,:L) = ", getparam(e1, :L, missing), ")")
println("done")
