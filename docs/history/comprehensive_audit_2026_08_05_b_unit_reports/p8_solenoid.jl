using Octopus
const O = Octopus

println("== h1. the folded-name guard misses :solenoid ==")
println("  _FOLDED_NAMED_STRENGTHS kinds = ", sort(collect(keys(O._FOLDED_NAMED_STRENGTHS))))
s = SolenoidSpec(L=1.0, ks=0.3, k1=0.5)
println("  SolenoidSpec(L=1, ks=0.3, k1=0.5) params = ", sort(collect(keys(params(s)))))
println("  -> k1 folded into kn = ", getparam(s, :kn, ()), "; no :k1 stored = ",
        !Octopus.hasparam(s, :k1))
ln = BeamLine("S", s)
e = ln[1]
r = try
    e.k1 = 999.0
    "ACCEPTED (written, reported, never read)"
catch err
    "rejected: " * first(sprint(showerror, err), 100)
end
println("  entry.k1 = 999 -> ", r)
println("  getparam(entry, :k1) = ", getparam(e, :k1, missing),
        "   compiled kn = ", compile_runtime(e).kn)
r2 = try
    s.k1s = 999.0; "ACCEPTED"
catch err
    "rejected: " * first(sprint(showerror, err), 100)
end
println("  spec.k1s = 999 -> ", r2)
println("  (a solenoid folds skew strengths into :kskew, not :ks -- :ks is the")
println("   SOLENOID STRENGTH, so even the fallback message would misdirect)")

println()
println("== h2. every _fold_named_strengths call site vs the guard table ==")
sites = [(:drift, :kn, :ks), (:quadrupole, :kn, :ks), (:sextupole, :kn, :ks),
         (:octupole, :kn, :ks), (:multipole, :kn, :ks), (:sbend, :kn, :ks),
         (:solenoid, :kn, :kskew),
         (:thin_multipole, :knl, :ksl), (:thin_dipole, :knl, :ksl),
         (:thin_quadrupole, :knl, :ksl), (:thin_sextupole, :knl, :ksl)]
for (k, nk, sk) in sites
    guarded = haskey(O._FOLDED_NAMED_STRENGTHS, k)
    keys_ok = get(O._FOLDED_TUPLE_KEYS, k, (:kn, :ks)) == (nk, sk)
    println("  ", rpad(String(k), 16), " guarded=", rpad(guarded, 6),
            " tuple-keys-correct=", keys_ok)
end
println("done")
