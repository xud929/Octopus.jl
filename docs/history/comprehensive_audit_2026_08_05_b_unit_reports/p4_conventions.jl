# U16 probe 4 — patch rotation SENSE vs the misalignment/ref_tilt sense,
# numeric-type promotion, corrected patch-inverse test, and the unknown-key
# warning on the region's friendly constructors.

using ForwardDiff, LinearAlgebra
include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus
bit6(a,b) = all(a[i] === b[i] for i in 1:6)
u  = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)

println("#"^78); println("# 1. PATCH ROTATION SENSE vs ref_tilt / tilt"); println("#"^78)
psi = 0.37
# patch angle_s
pa = O.compile_runtime(O.PatchSpec(angle_s=psi))(u...)
# ref_tilt on a ZERO-STRENGTH thin element: the conjugation degenerates to
# entrance-rotation o exit-rotation = identity, so use the raw helper instead.
c, s = cos(psi), sin(psi)
rot_plus  = ( c*u[1] - s*u[3],  c*u[2] - s*u[4],  s*u[1] + c*u[3],  s*u[2] + c*u[4])
rot_minus = ( c*u[1] + s*u[3],  c*u[2] + s*u[4], -s*u[1] + c*u[3], -s*u[2] + c*u[4])
println("PatchSpec(angle_s=+psi) transverse out : ", pa[1:4])
println("  R(+psi) on (x,y)                     : ", rot_plus)
println("  R(-psi) on (x,y)                     : ", rot_minus)
println("  matches R(+psi)? ", all(pa[i] == rot_plus[i] for i in 1:4),
        "   matches R(-psi)? ", all(pa[i] == rot_minus[i] for i in 1:4))
# `_s_rotate` is what ref_tilt applies at the entrance, with c = W[1], s = W[4]
# of the SAME `_misalign_matrix(T,0,0,psi,false)`.
W = O._misalign_matrix(Float64, 0.0, 0.0, psi, false)
println("W (row-major, psi about s) = ", W)
sr_ = O._s_rotate(W[1], W[4], u[1], u[2], u[3], u[4])
println("ref_tilt entrance `_s_rotate` out      : ", sr_)
println("  matches R(+psi)? ", all(sr_[i] == rot_plus[i] for i in 1:4),
        "   matches R(-psi)? ", all(sr_[i] == rot_minus[i] for i in 1:4))
# and the misalignment tilt, on a real element, for the same psi:
qt = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9, tilt=psi))(u...)
qp = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9, tilt=-psi))(u...)
# a patch with angle_s = psi followed by the untilted quad followed by the
# inverse patch should equal ONE of the two.
q  = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9))
pf = O.compile_runtime(O.PatchSpec(angle_s=psi))
pb = O.compile_runtime(O.PatchSpec(angle_s=-psi))
conj = pb(q(pf(u...)...)...)
println("patch(+psi) o quad o patch(-psi) vs quad(tilt=+psi): ",
        maximum(abs, collect(conj) .- collect(qt)))
println("                                  vs quad(tilt=-psi): ",
        maximum(abs, collect(conj) .- collect(qp)))

println("\n#"^1, "="^70)
println("# 2. PATCH angle_x / angle_y PLANE (the docstring's `crossing angle` example)")
println("="^70)
for (nm, sp) in (("angle_x=12.5e-3 (the docstring's example)", O.PatchSpec(angle_x=12.5e-3)),
                 ("angle_y=12.5e-3", O.PatchSpec(angle_y=12.5e-3)))
    a = O.compile_runtime(sp)(0.0,0.0,0.0,0.0,0.0,0.0)
    println(nm, " -> (px, py) = (", a[2], ", ", a[4], ")")
end
println("(the repository's crossing angle is HORIZONTAL: Contracts.jl calls the")
println(" boost `the horizontal-crossing boost`, and every crab cavity in")
println(" examples/ kicks in x.)")

println("\n", "="^70); println("# 3. CORRECTED patch o exact-inverse"); println("="^70)
# single-parameter inverses (what the docstring claims)
for (nm, a, b) in (("dz",      O.PatchSpec(dz=0.23),        O.PatchSpec(dz=-0.23)),
                   ("dx",      O.PatchSpec(dx=0.011),       O.PatchSpec(dx=-0.011)),
                   ("angle_x", O.PatchSpec(angle_x=0.021),  O.PatchSpec(angle_x=-0.021)),
                   ("angle_y", O.PatchSpec(angle_y=-0.013), O.PatchSpec(angle_y=0.013)),
                   ("angle_s", O.PatchSpec(angle_s=0.031),  O.PatchSpec(angle_s=-0.031)),
                   ("t_offset",O.PatchSpec(t_offset=0.0017),O.PatchSpec(t_offset=-0.0017)))
    f = O.compile_runtime(a); g = O.compile_runtime(b)
    println("  ", rpad(nm,9), " patch o inverse residual = ",
            maximum(abs, collect(g(f(u...)...)) .- collect(u)))
end
# compound: the true inverse of (o, W) is (-W*o expressed in the new frame, W')
# For a single-axis rotation W' = R(-angle), and the new origin is -W*o.
D = 0.23; th = -0.013
Wc = O._patch_rotation(Float64, 0.0, th, 0.0, false)
o2 = O._patch_apply(Wc, 0.0, 0.0, D)          # W*o
f = O.compile_runtime(O.PatchSpec(dz=D, angle_y=th))
g = O.compile_runtime(O.PatchSpec(dx=-o2[1], dy=-o2[2], dz=-o2[3], angle_y=-th))
println("  compound (dz,angle_y) o exact inverse residual = ",
        maximum(abs, collect(g(f(u...)...)) .- collect(u)))

println("\n", "="^70); println("# 4. pure-dz patch vs the exact drift, per component"); println("="^70)
pd = O.compile_runtime(O.PatchSpec(dz=0.37)); dr = O.compile_runtime(O.DriftSpec(L=0.37))
a = pd(u...); b = dr(u...)
for i in 1:6
    println("  comp ", i, ": patch = ", a[i], "   drift = ", b[i],
            "   diff = ", a[i]-b[i], "   bitwise ", a[i] === b[i])
end

println("\n", "="^70); println("# 5. NUMERIC TYPE PROMOTION"); println("="^70)
for (nm, sp) in (
   ("PatchSpec Float32",     O.PatchSpec(dx=Float32(0.01), dz=Float32(0.2), angle_y=Float32(0.01))),
   ("ChromKick Float32",     O.ChromaticityKickSpec{Float32}(; xi=(1.2f0,-0.8f0), beta=(0.82f0,0.075f0))),
   ("RFCavity  Float32",     O.ThinRFCavitySpec(Float32(4.008f8); strength=Float32(1f-4), beta0=Float32(0.99), gamma0=Float32(100))),
   ("CrabCav   Float32",     O.ThinCrabCavitySpec{2}(Float32(1.97f8); strengthX=(1f-5,-2f-6))),
   ("Boost     Float32",     O.LorentzBoostSpec(Float32(0.0125))))
    rt = O.compile_runtime(sp)
    println("  ", rpad(nm, 20), " -> ", typeof(rt))
end
println("  numeric_type(PatchSpec Float32 spec) = ",
        O.numeric_type(O.PatchSpec(dx=Float32(0.01), dz=Float32(0.2))))

println("\n", "="^70); println("# 6. UNKNOWN-KEY WARNING on this region's constructors"); println("="^70)
println("--- PatchSpec(angle_z=0.02)  (typo for angle_s; U12-10 said silent) ---")
sp = O.PatchSpec(angle_z=0.02)
println("    -> compiled: ", typeof(O.compile_runtime(sp)),
        "   identity? ", bit6(O.compile_runtime(sp)(u...), u))
println("--- ThinRFCavitySpec(...; phaze=0.3) ---")
sp2 = O.ThinRFCavitySpec(400.8e6; voltage=1e6, e0=275e9, mc2=O.PMASS_EV, phaze=0.3)
println("    -> stored keys: ", sort(collect(keys(O.params(sp2)))))
println("--- LorentzBoostSpec(0.0125; angel=1.0) ---")
sp3 = O.LorentzBoostSpec(0.0125; angel=1.0)
println("    -> ok")

println("\n", "="^70); println("# 7. voltage + explicit beta0/gamma0 now refused?"); println("="^70)
for kw in ((:beta0, 0.5), (:gamma0, 1.2))
    try
        O.ThinRFCavitySpec(400.8e6; voltage=1e6, e0=275e9, mc2=O.PMASS_EV, kw[1]=>kw[2])
        println("  ", kw[1], " ACCEPTED (silently overwritten)")
    catch e
        println("  ", kw[1], " refused: ", sprint(showerror, e)[1:min(90,end)], "...")
    end
end

println("\n", "="^70); println("# 8. Patch on a WRONG-KIND spec (U12-4)"); println("="^70)
try
    O.Patch(O.DriftSpec(L=1.0))
    println("  Patch(DriftSpec) ACCEPTED")
catch e
    println("  Patch(DriftSpec) refused: ", typeof(e))
end

println("\n", "="^70); println("# 9. SymplecticityContract coverage of this region"); println("="^70)
kinds = Symbol[]
for T in O.registered_element_specs()
    m = O.element_meta(T)
    any(C -> C === O.SymplecticityContract, m.contracts) && push!(kinds, m.kind)
end
println("  kinds DECLARING SymplecticityContract: ", kinds)
println("  region kinds: :thin_rf_cavity :patch :chromaticity_kick :thin_crab_cavity")
println("                :lorentz_boost :rev_lorentz_boost")
println("  -> the U3-3 declaration<->case tripwire can only ever see ", length(kinds), " kind(s).")
