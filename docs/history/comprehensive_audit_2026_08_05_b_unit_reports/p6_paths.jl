using Octopus
const O = Octopus

q  = QuadrupoleSpec(L=0.4, k1=1.7, nst=2)
d  = DriftSpec(L=1.0)
ap = ApertureSpec(x_limit=2.0e-2, y_limit=2.0e-2, name="COLL_OUT")

println("== f1. public track! on a kept-whole line with mixed tracking methods ==")
mixed = BeamLine("MIX", q, ap; x_offset=1.0e-4)
rt = compile_runtime(mixed)
rep = Phase6DRep([1.0e-3], [0.0], [0.0], [0.0], [0.0], [0.0])
try
    track!(rep, (rt,), 1)
    println("  track!(rep, (girder,), 1) OK -> x = ", rep.x[1])
catch e
    println("  track!(rep, (girder,), 1) THREW: ", first(sprint(showerror, e), 220))
end
println("  -- homogeneous composite for comparison --")
homo = compile_runtime(BeamLine("HOM", q, d; x_offset=1.0e-4))
rep2 = Phase6DRep([1.0e-3], [0.0], [0.0], [0.0], [0.0], [0.0])
try
    track!(rep2, (homo,), 1); println("  OK -> x = ", rep2.x[1])
catch e
    println("  THREW: ", first(sprint(showerror, e), 160))
end

println()
println("== f2. selection cannot reach inside a kept-whole line ==")
inner = BeamLine("CRYO", q, d; x_offset=2.0e-4)
outer = BeamLine("ARC", inner, q, d)
println("  length(outer)            = ", length(outer))
println("  paths                    = ", [entry_path(e) for e in line_entries(outer)])
println("  find_entries(outer, sel\"ARC//QUADRUPOLE\") = ",
        find_entries(outer, sel"ARC//QUADRUPOLE"))
println("  find_entries(outer, sel\"ARC/CRYO\")        = ",
        find_entries(outer, sel"ARC/CRYO"))
println("  (the cryostat's two magnets are not addressable from the parent)")

println()
println("== f3. reverse of a kept-whole line shares placements with the source ==")
rev = reverse(inner)
println("  inner[1] === rev[2] : ", inner[1] === rev[2])
arc = BeamLine("A2", inner, rev)
println("  arc entries          = ", [entry_path(e) for e in line_entries(arc)])
arc[2].x_offset = 7.7e-3            # override on the REFLECTED cryostat placement
println("  after arc[2].x_offset=7.7e-3 -> arc[1].x_offset = ",
        getparam(arc[1], :x_offset, missing))
println("  inner[1].k1 (should be untouched) = ", getparam(inner[1], :k1, missing))
inner_of_rev = getfield(arc[2], :spec)
println("  arc[1].spec === arc[2].spec : ", getfield(arc[1], :spec) === inner_of_rev)
println("  reverse(inner)[1] entry object === inner[2] : ", rev[1] === inner[2])
rev[1].k1 = 9.9
println("  after rev[1].k1 = 9.9 -> inner[2].k1 = ", getparam(inner[2], :k1, missing))

println()
println("== f4. folded-name guard now covers thin kinds (U11-3) ==")
for (lbl, spec, name) in (("thin_quad k1l ", ThinQuadrupoleSpec(k1l=0.05), :k1l),
                          ("thin_sext k2l ", ThinSextupoleSpec(k2l=1.2),  :k2l),
                          ("thin_dip  k0l ", ThinDipoleSpec(k0l=1e-3),    :k0l),
                          ("thin_mult k3l ", ThinMultipoleSpec(k3l=1.0),  :k3l),
                          ("quad      k1  ", QuadrupoleSpec(L=1,k1=0.5,nst=1), :k1),
                          ("hkicker   hkick", HKickerSpec(hkick=1e-4),    :hkick))
    ln = BeamLine("T", spec)
    r = try
        setproperty!(ln[1], name, 999.0); "ACCEPTED"
    catch e
        "rejected: " * first(sprint(showerror, e), 60)
    end
    println("  ", lbl, " -> ", r)
end

println()
println("== f5. spec-level assignment of a folded name ==")
qs = QuadrupoleSpec(L=1.0, k1=0.5, nst=1)
r = try
    qs.k1 = 999.0; "ACCEPTED (params now $(sort(collect(keys(params(qs)))))"
catch e
    "rejected: " * first(sprint(showerror, e), 80)
end
println("  spec.k1 = 999 -> ", r)
ts = ThinQuadrupoleSpec(k1l=0.05)
r2 = try
    ts.k1l = 999.0; "ACCEPTED"
catch e
    "rejected: " * first(sprint(showerror, e), 80)
end
println("  thinspec.k1l = 999 -> ", r2)
println("done")
