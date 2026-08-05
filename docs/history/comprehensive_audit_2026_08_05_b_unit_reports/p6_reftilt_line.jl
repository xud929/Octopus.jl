# U16 probe 6 — RefTilted's method dispatch on a wrapped LINE, and the
# discoverability of the F16 boundary through the reflection surfaces.

include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus
u = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)

println("="^78); println("A. RefTilted wrapping a CompositeLine (a rolled BeamLine)"); println("="^78)
ln = O.BeamLine("cell", O.QuadrupoleSpec(L=0.4, k1=0.9), O.DriftSpec(L=0.3); ref_tilt=0.37)
rt = O.compile_runtime(ln)
println("compiled type: ", typeof(rt))
println("inner type   : ", typeof(rt.inner))
println("inner has a `method` field? ", :method in fieldnames(typeof(rt.inner)))
print("plain 6-arg call rt(u...)     : ")
try
    println(rt(u...))
catch e
    println("THROWS ", typeof(e), " -- ", sprint(showerror, e)[1:min(160,end)])
end
ctx = O.TrackingContext(; turn=1, seed=UInt64(7), rng_method=:philox)
print("ctx call rt(ctx, 1, u...)     : ")
try
    println(rt(ctx, 1, u...))
catch e
    println("THROWS ", typeof(e), " -- ", sprint(showerror, e)[1:min(160,end)])
end
print("track_particle(method, rt, u) : ")
try
    println(O.track_particle(O.Symplectic6DMap(), rt, u...))
catch e
    println("THROWS ", typeof(e), " -- ", sprint(showerror, e)[1:min(160,end)])
end
# control: no ref_tilt
ln2 = O.BeamLine("cell2", O.QuadrupoleSpec(L=0.4, k1=0.9), O.DriftSpec(L=0.3))
rt2 = O.compile_runtime(ln2)
print("un-rolled line plain call     : ")
try
    println(rt2(u...))
catch e
    println("THROWS ", typeof(e), " -- ", sprint(showerror, e)[1:min(160,end)])
end
# and a ref_tilted MISALIGNED element (the documented nesting)
q = O.compile_runtime(O.QuadrupoleSpec(L=0.4, k1=0.9, ref_tilt=0.37, x_offset=1.0e-4))
println("ref_tilt + misalign type: ", typeof(q))
print("plain call: ")
try; println(q(u...)); catch e; println("THROWS ", typeof(e)); end

println("\n", "="^78); println("B. is the F16 boundary visible from the reflection surfaces?"); println("="^78)
h = sprint(io -> print(io, O.element_help(:thin_rf_cavity)))
for w in ("slip", "gamma0^2", "alpha_c", "velocity", "transit-time", "RF focusing", "z1")
    println("  element_help(:thin_rf_cavity) contains ", rpad(repr(w), 16), ": ", occursin(w, h))
end
ch = O.construction_help(O.ElementSpec{:thin_rf_cavity})
for w in ("slip", "velocity", "transit-time")
    println("  construction_help contains ", rpad(repr(w), 16), ": ", occursin(w, ch))
end
sch = O.parameter_schema(O.ElementSpec{:thin_rf_cavity})
println("  any ParamMeta `meaning` mentions slip? ",
        any(occursin("slip", string(getfield(v, :meaning))) for v in values(sch)))
d = string(@doc O.ThinRFCavitySpec)
println("  ?ThinRFCavitySpec docstring mentions `velocity-slip`: ", occursin("velocity-slip", d))
println("  ?ThinRFCavitySpec docstring mentions `1/gamma0`     : ", occursin("1/gamma0", d))
println("  ?ThinRFCavity (runtime) docstring mentions slip     : ",
        occursin("slip", string(@doc O.ThinRFCavity)))
