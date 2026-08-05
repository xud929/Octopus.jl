using Octopus
const O = Octopus
u = (2.3e-3, 4.1e-4, -1.7e-3, -3.2e-4, 1.5e-3, 9.0e-4)
P = O.DEFAULT_ELEMENT_PARAM_PROBES

mapof(ctor, kw) = collect(O.compile_runtime(ctor(; kw...))(u...))

println("=== R. sbend.fringe at the contract's own probe vs a probe that can act ===")
sb = Dict{Symbol,Any}(pairs(P[:sbend]))
println("  contract probe for :sbend = ", P[:sbend])
b = mapof(O.SBendSpec, sb)
for f in (:none, :multipole, :soft_quad, :all)
    m = mapof(O.SBendSpec, merge(sb, Dict{Symbol,Any}(:fringe => f)))
    println("    fringe=:", rpad(string(f), 11), " max|delta| vs probe(:all) = ", maximum(abs, m .- b))
end
println("  -> with highest_fringe=2 (PTC's own default, used by the PTC cases):")
sb2 = merge(sb, Dict{Symbol,Any}(:highest_fringe => 2))
b2 = mapof(O.SBendSpec, sb2)
for f in (:none, :multipole)
    m = mapof(O.SBendSpec, merge(sb2, Dict{Symbol,Any}(:fringe => f)))
    println("    fringe=:", rpad(string(f), 11), " max|delta| = ", maximum(abs, m .- b2))
end
println("  -> with va/vs (soft edge) added, as the quadrupole probe has:")
sb3 = merge(sb, Dict{Symbol,Any}(:va => 0.03, :vs => 1.0e-4))
b3 = mapof(O.SBendSpec, sb3)
for f in (:none, :multipole)
    m = mapof(O.SBendSpec, merge(sb3, Dict{Symbol,Any}(:fringe => f)))
    println("    fringe=:", rpad(string(f), 11), " max|delta| = ", maximum(abs, m .- b3))
end
println("  (the contract docstring: \"probes ... chosen so conditional parameters are in a")
println("   configuration where they can act: `va` needs a soft-edge fringe enabled\")")

println()
println("=== S. misalign_convention: which values does each kind's constructor accept? ===")
junk = (:madx, :bmad, :MADX, :mad_x, :nonsense, :on)
for (kind, ctorname) in ((:drift, :DriftSpec), (:quadrupole, :QuadrupoleSpec),
                         (:sbend, :SBendSpec), (:marker, :MarkerSpec),
                         (:solenoid, :SolenoidSpec), (:aperture, :ApertureSpec),
                         (:linear6d, :Linear6DSpec), (:patch, :PatchSpec),
                         (:thin_multipole, :ThinMultipoleSpec))
    ctor = getfield(O, ctorname)
    probe = haskey(P, kind) ? Dict{Symbol,Any}(pairs(P[kind])) :
        Dict{Symbol,Any}(O.params(O.example_spec(O.ElementSpec{kind})))
    acc = Symbol[]
    for v in junk
        try; mapof(ctor, merge(probe, Dict{Symbol,Any}(:misalign_convention => v))); push!(acc, v)
        catch; end
    end
    println("  ", rpad(string(kind), 16), " accepts ", acc,
            length(acc) > 2 ? "   <-- accepts misspellings/garbage" : "")
end

println()
println("=== T. aperture.misalign_convention: garbage is accepted AND changes the map ===")
ap = Dict{Symbol,Any}(pairs(P[:aperture]))
base = mapof(O.ApertureSpec, merge(ap, Dict{Symbol,Any}(:misalign_convention => :bmad)))
for v in (:madx, :nonsense, :on)
    m = mapof(O.ApertureSpec, merge(ap, Dict{Symbol,Any}(:misalign_convention => v)))
    println("    :", rpad(string(v), 10), " max|delta| vs :bmad = ", maximum(abs, m .- base))
end
