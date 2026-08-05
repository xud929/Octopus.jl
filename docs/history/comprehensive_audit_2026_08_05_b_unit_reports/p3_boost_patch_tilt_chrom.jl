# U16 probe 3 — Lorentz boost invertibility/convention, and the
# patch / ref_tilt / chromaticity_kick maps against INDEPENDENT derivations,
# ForwardDiff symplecticity, and the BITWISE zero-parameter identity limit.

using ForwardDiff, LinearAlgebra
include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus

const S6 = [0.0 1 0 0 0 0; -1 0 0 0 0 0; 0 0 0 1 0 0; 0 0 -1 0 0 0;
            0 0 0 0 0 1; 0 0 0 0 -1 0]
sr(f, u) = (J = ForwardDiff.jacobian(f, u); maximum(abs, J'*S6*J - S6))
bit6(a, b) = all(a[i] === b[i] for i in 1:6)

u  = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)
uv = collect(u)
ubig = (5.0e-3, 3.0e-3, -4.0e-3, 2.5e-3, 2.0e-2, 8.0e-3)

println("#"^78); println("# (b) LORENTZ BOOST"); println("#"^78)

# Independent transcription of Hirata's published boost (PRL 74, 2228 (1995)):
#   H  = 1+d - sqrt((1+d)^2 - px^2 - py^2)
#   px*= (px - H tanf)/cosf ; py* = py/cosf ; d* = d - px tanf + H tan^2 f
#   H* = H/cos^2 f ; ps* = 1 + d* - H*
#   x* = tanf z + (1 + px* sinf/ps*) x ; y* = y + py* sinf/ps* x
#   z* = z/cosf - H* sinf/ps* x
function hirata(f, x, px, y, py, z, d)
    t = tan(f); c = cos(f); s = sin(f)
    H  = 1 + d - sqrt((1+d)^2 - px^2 - py^2)
    pxs = (px - H*t)/c
    pys = py/c
    ds  = d - px*t + H*t*t
    Hs  = H/(c*c)
    pss = 1 + ds - Hs
    xs = t*z + (1 + pxs*s/pss)*x
    ys = y + pys*s/pss*x
    zs = z/c - Hs*s/pss*x
    return (xs, pxs, ys, pys, zs, ds)
end

for ang in (12.5e-3, 25.0e-3, 0.3)
    fwd = O.LorentzBoost(ang); rev = O.RevLorentzBoost(ang)
    for (tag, p) in (("small", u), ("large", ubig))
        a = rev(fwd(p...)...)
        b = fwd(rev(p...)...)
        r1 = maximum(abs, collect(a) .- collect(p))
        r2 = maximum(abs, collect(b) .- collect(p))
        rrel = maximum(abs, (collect(a) .- collect(p)) ./ collect(p))
        println("angle=", ang, " ", tag, "  rev(fwd)-u = ", r1,
                "   fwd(rev)-u = ", r2, "   max rel = ", rrel)
    end
    # vs the independent Hirata transcription
    h = hirata(ang, u...)
    g = fwd(u...)
    println("   |code - Hirata(published form)| = ", maximum(abs, collect(g) .- collect(h)))
    # the internal ps1 must be the true sqrt, or the boost is not on the mass shell
    ps_used = 1 + g[6] - (1 + u[6] - sqrt((1+u[6])^2-u[2]^2-u[4]^2))/cos(ang)^2
    ps_true = sqrt((1+g[6])^2 - g[2]^2 - g[4]^2)
    println("   ps1 (as used) - sqrt((1+pz1)^2-px1^2-py1^2) = ", ps_used - ps_true)
    # Jacobian determinants
    Jf = ForwardDiff.jacobian(v -> collect(fwd(v...)), uv)
    Jr = ForwardDiff.jacobian(v -> collect(rev(v...)), uv)
    println("   det J(fwd) - sec^3 = ", det(Jf) - sec(ang)^3,
            "   det J(rev) - cos^3 = ", det(Jr) - cos(ang)^3)
    println("   det J(fwd)*det J(rev) - 1 = ", det(Jf)*det(Jr) - 1)
end

# identity limit and geometric signature
z0 = O.LorentzBoost(0.0); rz0 = O.RevLorentzBoost(0.0)
println("\nangle = 0 bitwise identity (fwd)? ", bit6(z0(u...), u))
println("angle = 0 bitwise identity (rev)? ", bit6(rz0(u...), u))
o = O.LorentzBoost(12.5e-3)(0.0,0.0,0.0,0.0,0.0,0.0)
println("origin -> ", o, "   fixed bitwise? ", all(v === 0.0 for v in o))
g = O.LorentzBoost(12.5e-3)(0.0,0.0,0.0,0.0,1.0e-3,0.0)
println("(0,0,0,0,z,0) -> x1 = ", g[1], "   z*tan(phi) = ", 1.0e-3*tan(12.5e-3),
        "   equal? ", g[1] == 1.0e-3*tan(12.5e-3))
println("inverse_boost(LorentzBoost) round trip: ",
        maximum(abs, collect(O.inverse_boost(O.LorentzBoost(12.5e-3))(
                     O.LorentzBoost(12.5e-3)(u...)...)) .- collect(u)))

println("\n", "#"^78); println("# (c1) PATCH"); println("#"^78)

pfull(conv) = O.compile_runtime(O.PatchSpec(dx=0.011, dy=-0.007, dz=0.23,
    angle_x=0.021, angle_y=-0.013, angle_s=0.031, t_offset=0.0017, convention=conv))
for conv in (:bmad, :madx)
    p = pfull(conv)
    println("symplectic |J'SJ-S| (", conv, ") = ", sr(v -> collect(p(v...)), uv))
end

# zero-parameter BITWISE identity
p0 = O.compile_runtime(O.PatchSpec())
println("PatchSpec() bitwise identity?          ", bit6(p0(u...), u))
println("  on a large-amplitude point?          ", bit6(p0(ubig...), ubig))
println("  with negative x,y,z?                 ",
        bit6(p0(-4.0e-4, -1.0e-4, -2.0e-4, 1.5e-4, -1.2e-3, 2.0e-4),
             (-4.0e-4, -1.0e-4, -2.0e-4, 1.5e-4, -1.2e-3, 2.0e-4)))
println("  at the exact origin?                 ",
        bit6(p0(0.0,0.0,0.0,0.0,0.0,0.0), (0.0,0.0,0.0,0.0,0.0,0.0)))

# independent derivation 1: a pure dz patch IS an exact drift of length dz
pd = O.compile_runtime(O.PatchSpec(dz=0.37))
dr = O.compile_runtime(O.DriftSpec(L=0.37))
a = pd(u...); b = dr(u...)
println("pure-dz patch vs exact drift: max|diff| = ", maximum(abs, collect(a).-collect(b)),
        "   bitwise? ", bit6(a, b))

# independent derivation 2: a pure angle_s patch IS a rigid (x,px,y,py) rotation
ps_ = O.compile_runtime(O.PatchSpec(angle_s=0.37))
c, s = cos(0.37), sin(0.37)
hand = (c*u[1] - s*u[3], c*u[2] - s*u[4], s*u[1] + c*u[3], s*u[2] + c*u[4], u[5], u[6])
hand2 = (c*u[1] + s*u[3], c*u[2] + s*u[4], -s*u[1] + c*u[3], -s*u[2] + c*u[4], u[5], u[6])
a = ps_(u...)
println("pure angle_s patch vs R_z(-psi): max|diff| = ", maximum(abs, collect(a).-collect(hand)))
println("pure angle_s patch vs R_z(+psi): max|diff| = ", maximum(abs, collect(a).-collect(hand2)))
println("  (z, pz) untouched bitwise? ", a[5] === u[5] && a[6] === u[6])

# independent derivation 3: pure angle_y, geometry from scratch.
# New frame axes = R about y by theta.  A particle on the old axis (px=py=0)
# must acquire px* = -sin(theta)*(1+delta) or +sin, and ps* = cos(theta)*(1+d).
for th in (0.05, -0.05)
    py_ = O.compile_runtime(O.PatchSpec(angle_y=th))
    a = py_(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    println("angle_y = ", th, " on-axis particle -> px = ", a[2],
            "   -sin(th) = ", -sin(th), "   +sin(th) = ", sin(th))
end
for th in (0.05, -0.05)
    px_ = O.compile_runtime(O.PatchSpec(angle_x=th))
    a = px_(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    println("angle_x = ", th, " on-axis particle -> py = ", a[4],
            "   -sin(th) = ", -sin(th), "   +sin(th) = ", sin(th))
end

# independent derivation 4: patch o (exact inverse patch) = identity
for conv in (:bmad, :madx)
    f = O.compile_runtime(O.PatchSpec(dz=0.23, angle_y=-0.013, convention=conv))
    # inverse of a single-axis rotation + dz: undo the rotation then the shift
    inv1 = O.compile_runtime(O.PatchSpec(angle_y=0.013, convention=conv))
    inv2 = O.compile_runtime(O.PatchSpec(dz=-0.23, convention=conv))
    a = inv2(inv1(f(u...)...)...)
    println("patch o inverse (", conv, ") residual = ", maximum(abs, collect(a).-collect(u)))
end

# t_offset is exactly additive on z
pt = O.compile_runtime(O.PatchSpec(t_offset=1.7e-3))
a = pt(u...)
println("t_offset alone: z_out - z_in - t_offset = ", a[5] - u[5] - 1.7e-3,
        "   others bitwise? ", a[1]===u[1] && a[2]===u[2] && a[3]===u[3] &&
                               a[4]===u[4] && a[6]===u[6])

println("\n", "#"^78); println("# (c2) REF_TILT"); println("#"^78)

# zero ref_tilt: the wrap must return the SAME OBJECT (identity by construction)
q = O.QuadrupoleSpec(L=0.4, k1=0.9)
inner = O.compile_runtime(q)
qz = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9, ref_tilt=0.0))
println("ref_tilt = 0 -> same runtime type?   ", typeof(qz), "  (RefTilted? ",
        qz isa O.RefTilted, ")")
println("ref_tilt = 0 bitwise identity to the unwrapped element? ",
        bit6(qz(u...), inner(u...)))
# a hand-built RefTilted at psi = 0
rt0 = O.RefTilted(inner, 1.0, 0.0)
println("RefTilted(inner, 1, 0) bitwise = inner? ", bit6(rt0(u...), inner(u...)))

# the docstring's own test: for a STRAIGHT element ref_tilt coincides with tilt
for psi in (0.37, -1.1, pi/2)
    a = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9, ref_tilt=psi))(u...)
    b = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9, tilt=psi))(u...)
    println("straight element: ref_tilt(", psi, ") vs tilt: max|diff| = ",
            maximum(abs, collect(a).-collect(b)))
end

# a bend with ref_tilt = pi/2 is a VERTICAL bend (independent signature)
bh = O.compile_runtime(O.SBendSpec(L=2.0, angle=0.1))
bv = O.compile_runtime(O.SBendSpec(L=2.0, angle=0.1, ref_tilt=pi/2))
ah = bh(0.0,0.0,0.0,0.0,0.0,1.0e-3); av = bv(0.0,0.0,0.0,0.0,0.0,1.0e-3)
println("horizontal bend dispersion x = ", ah[1], "  vertical bend y = ", av[3],
        "   difference = ", av[3]-ah[1])
println("   vertical bend residual x = ", av[1], "   z equal? ", av[5] === ah[5])

# symplecticity of the conjugation
println("|J'SJ-S| for SBend(ref_tilt=0.37) = ",
        sr(v -> collect(O.compile_runtime(O.SBendSpec(L=2.0, angle=0.1, ref_tilt=0.37))(v...)), uv))

# the NEW ctx-forwarding method must agree with the plain call
ctx = O.TrackingContext(; turn=3, seed=UInt64(99), rng_method=:philox)
rt = O.compile_runtime(O.SBendSpec(L=2.0, angle=0.1, ref_tilt=0.37))
a = rt(u...); b = rt(ctx, 1, u...)
println("RefTilted ctx path vs plain: bitwise equal? ", bit6(a, b))

println("\n", "#"^78); println("# (c3) CHROMATICITY KICK"); println("#"^78)

ck = O.compile_runtime(O.ChromaticityKickSpec{Float64}(; xi=(1.2,-0.8),
        beta=(0.82,0.075), alpha=(0.01,-0.02),
        zeta=(0.002,-0.001,0.0,0.0), eta=(0.001,0.0,-0.001,0.0),
        R=(0.001,-0.0005,0.0003,0.0007)))
println("|J'SJ-S| full (all params) = ", sr(v -> collect(ck(v...)), uv))
ckp = O.compile_runtime(O.ChromaticityKickSpec{Float64}(; xi=(1.2,-0.8), beta=(0.82,0.075)))
println("|J'SJ-S| plain             = ", sr(v -> collect(ckp(v...)), uv))

# bitwise identity limits
ck0 = O.compile_runtime(O.ChromaticityKickSpec{Float64}(; xi=(0.0,0.0), beta=(0.82,0.075)))
println("xi = (0,0) bitwise identity?          ", bit6(ck0(u...), u))
println("  large amplitude?                    ", bit6(ck0(ubig...), ubig))
println("  origin?                             ",
        bit6(ck0(0.0,0.0,0.0,0.0,0.0,0.0), (0.0,0.0,0.0,0.0,0.0,0.0)))
# and with the conjugations switched on but xi = 0 -> the round trip
ck0c = O.compile_runtime(O.ChromaticityKickSpec{Float64}(; xi=(0.0,0.0),
        beta=(0.82,0.075), alpha=(0.01,-0.02),
        zeta=(0.002,-0.001,0.0,0.0), eta=(0.001,0.0,-0.001,0.0),
        R=(0.001,-0.0005,0.0003,0.0007)))
a = ck0c(u...)
println("xi = 0 with zeta/eta/R on: max|diff| = ", maximum(abs, collect(a).-collect(u)),
        "   bitwise? ", bit6(a, u))

# INDEPENDENT DERIVATION: the map is the time-1 flow of h = 2*pi*xi*pz*J(x,px).
#   (x,px) rotate by mu = 2 pi xi pz in Twiss coordinates
#   dz/ds = +dh/dpz = 2 pi xi J   -> z += 2 pi (xix Jx + xiy Jy)
bx, ax_ = 0.82, 0.01; by, ay_ = 0.075, -0.02
gx = (1+ax_^2)/bx; gy = (1+ay_^2)/by
xix, xiy = 1.2, -0.8
function hand_chrom(x, px, y, py, z, pz)
    mx = 2pi*xix*pz; my = 2pi*xiy*pz
    cx, sx = cos(mx), sin(mx); cy, sy = cos(my), sin(my)
    xn  =  x*(cx + ax_*sx) + px*bx*sx
    pxn = -x*gx*sx + px*(cx - ax_*sx)
    yn  =  y*(cy + ay_*sy) + py*by*sy
    pyn = -y*gy*sy + py*(cy - ay_*sy)
    Jx = (gx*x*x + 2ax_*x*px + bx*px*px)/2
    Jy = (gy*y*y + 2ay_*y*py + by*py*py)/2
    return (xn, pxn, yn, pyn, z + 2pi*(xix*Jx + xiy*Jy), pz)
end
ckh = O.compile_runtime(O.ChromaticityKickSpec{Float64}(; xi=(xix,xiy),
        beta=(bx,by), alpha=(ax_,ay_)))
a = ckh(u...); b = hand_chrom(u...)
println("vs independent Hamiltonian-flow derivation: max|diff| = ",
        maximum(abs, collect(a).-collect(b)), "   bitwise? ", bit6(a, b))
# the Twiss rotation preserves the CS action exactly
Jin  = (gx*u[1]^2 + 2ax_*u[1]*u[2] + bx*u[2]^2)/2
Jout = (gx*a[1]^2 + 2ax_*a[1]*a[2] + bx*a[2]^2)/2
println("CS action Jx preserved: Jout - Jin = ", Jout - Jin, "  (rel ", (Jout-Jin)/Jin, ")")

# integer-tuple flexible form (the U12-5 fix)
ik = O.compile_runtime(O.ElementSpec{:chromaticity_kick}(; xi=(1,1), beta=(1,1),
        alpha=(0,0,0), zeta=(0,0,0,0), eta=(0,0,0,0), R=(0,0,0,0)))
println("integer flexible form builds: ", typeof(ik))

println("\n", "#"^78); println("# CRAB CAVITY (adjacent, in region)"); println("#"^78)
cc = O.compile_runtime(O.ThinCrabCavitySpec{2}(197.0e6; strengthX=(1.0e-5,-2.0e-6),
        strengthY=(3.0e-6,0.0), phase=(0.0,0.2)))
println("|J'SJ-S| = ", sr(v -> collect(cc(v...)), uv))
cc0 = O.compile_runtime(O.ThinCrabCavitySpec{2}(197.0e6))
println("all-zero strengths bitwise identity? ", bit6(cc0(u...), u))
println("keyword round-trip form builds: ",
        typeof(O.compile_runtime(O.ThinCrabCavitySpec(; N=2, frequency=197.0e6,
                strengthX=(1.0e-5,-2.0e-6), strengthY=(3.0e-6,0.0), phase=(0.0,0.2)))))
println("LorentzBoostSpec(; angle=...) keyword form: ",
        typeof(O.compile_runtime(O.LorentzBoostSpec(; angle=0.0125))))
