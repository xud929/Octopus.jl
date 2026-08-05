# U16 probe 5 — `_patch_reference_length`: does the ON-AXIS REFERENCE PARTICLE
# come out with z unchanged?  The docstring says the projected length "is what
# the on-axis reference particle traverses"; measure it.

include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus
ref = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)          # on-axis, on-momentum

println("="^78)
println("A. on-axis reference particle through a patch: z_out (should be 0)")
println("="^78)
println(rpad("case",42), rpad("z_out",26), "predicted D(cos-1)")
for (nm, sp, pred) in (
  ("dz=0.23 only",                 O.PatchSpec(dz=0.23), 0.0),
  ("angle_y=0.013 only",           O.PatchSpec(angle_y=0.013), 0.0),
  ("dz=0.23, angle_y=0.013",       O.PatchSpec(dz=0.23, angle_y=0.013),
                                    0.23*(cos(0.013)-1)),
  ("dz=0.23, angle_x=0.013",       O.PatchSpec(dz=0.23, angle_x=0.013),
                                    0.23*(cos(0.013)-1)),
  ("dz=0.23, angle_y=0.10",        O.PatchSpec(dz=0.23, angle_y=0.10),
                                    0.23*(cos(0.10)-1)),
  ("dz=1.20, angle_y=0.0125",      O.PatchSpec(dz=1.20, angle_y=0.0125),
                                    1.20*(cos(0.0125)-1)),
  ("dz=0.23, angle_s=0.013",       O.PatchSpec(dz=0.23, angle_s=0.013), 0.0),
  ("dx=0.05, angle_y=0.013",       O.PatchSpec(dx=0.05, angle_y=0.013), NaN),
  ("dx=0.05, dz=1.2 (the docstring's junction)",
                                   O.PatchSpec(dx=0.05, dz=1.2), 0.0),
 )
    z = O.compile_runtime(sp)(ref...)[5]
    println(rpad(nm,42), rpad(string(z),26), pred)
end

println("\n", "="^78)
println("B. the two lengths the map uses, for the on-axis particle")
println("="^78)
for (D, th) in ((0.23, 0.013), (1.2, 0.0125), (0.5, 0.1))
    W = O._patch_rotation(Float64, 0.0, th, 0.0, false)
    elem = O.Patch{O.NonSymplectic6DMap,Float64}(O.NonSymplectic6DMap(),
              0.0,0.0,D, 0.0,th,0.0, 0.0, false)
    refl = O._patch_reference_length(elem, W)
    # the path the on-axis particle actually travels to reach the new face
    r = O._patch_apply(W, 0.0, 0.0, -D); q = O._patch_apply(W, 0.0, 0.0, 1.0)
    path = (-r[3]) * 1.0 / q[3]
    println("D = ", D, "  theta = ", th,
            "   ref (projected) = ", refl, "   path (actual) = ", path,
            "   ref - path = ", refl - path, "   D(cos-1) = ", D*(cos(th)-1))
end

println("\n", "="^78)
println("C. compound patch o EXACT GEOMETRIC INVERSE: residual per component")
println("="^78)
u = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)
for (D, th) in ((0.23, 0.013), (1.2, 0.0125), (0.5, 0.1))
    W = O._patch_rotation(Float64, 0.0, th, 0.0, false)
    o2 = O._patch_apply(W, 0.0, 0.0, D)                 # W*o
    f = O.compile_runtime(O.PatchSpec(dz=D, angle_y=th))
    g = O.compile_runtime(O.PatchSpec(dx=-o2[1], dy=-o2[2], dz=-o2[3], angle_y=-th))
    a = g(f(u...)...)
    d = collect(a) .- collect(u)
    println("D = ", D, " theta = ", th, "  residual = ", d)
    println("     z residual = ", d[5], "   D(cos-1)*2? ", 2*D*(cos(th)-1),
            "   D(cos-1) = ", D*(cos(th)-1))
end

println("\n", "="^78)
println("D. does anything in the repository build a COMPOUND patch?")
println("="^78)
println("(grep is run outside; see report)")
