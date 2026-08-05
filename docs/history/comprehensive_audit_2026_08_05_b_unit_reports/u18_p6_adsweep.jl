# U18 probe 6: headroom of the `@test length(verified) >= 25` floor in
# test/runtests.jl "Element parameters carry their own number type"
# (line ~2210 at HEAD 7de4d81), and the composition of the caught bucket.
using Octopus

u = (1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.0, 1.0e-3)
H = 1e-30
verified = String[]; disagreed = String[]; caught = Tuple{String,String}[]
seed(spec, key, v) = (p = copy(getfield(spec, :params)); p[key] = v;
                      ElementSpec{kind(spec)}(p))
for T in sort(collect(Octopus.registered_element_specs()); by=string)
    meta = Octopus._element_meta_or_nothing(T)
    meta === nothing && continue
    ex = example_spec(T)
    ex isa ElementSpec || continue
    for (key, val) in sort(collect(getfield(ex, :params)); by=x -> string(x[1]))
        val isa Real && !(val isa Bool) && !(val isa Integer) || continue
        val == 0 && continue
        try
            d = [imag(x) / H for x in
                 compile_runtime(seed(ex, key, complex(float(val), H)))(u...)]
            h = abs(float(val)) * 1e-6
            f(v) = collect(compile_runtime(seed(ex, key, v))(u...))
            fd = (f(float(val) + h) .- f(float(val) - h)) ./ (2h)
            err = maximum(abs, d .- fd) / max(maximum(abs, fd), 1e-8)
            push!(isfinite(err) && err < 1e-4 ? verified : disagreed,
                  "$(meta.kind).$(key)")
        catch sweep_err
            push!(caught, ("$(meta.kind).$(key)", string(typeof(sweep_err))))
            sweep_err isa Union{MethodError,InexactError} ||
                println("  RETHROW WOULD FIRE: $(meta.kind).$(key) -> ", typeof(sweep_err))
        end
    end
end
println("verified  = ", length(verified), "   (floor asserted: >= 25, headroom ",
        length(verified) - 25, ")")
println("disagreed = ", length(disagreed), "  ", disagreed)
println("caught    = ", length(caught))
foreach(c -> println("   ", c[1], "  ", c[2]), sort(caught))
println()
println("verified list:")
foreach(v -> println("   ", v), sort(verified))
named = ("quadrupole", "sextupole", "octupole", "multipole", "sbend",
         "drift", "patch", "kicker", "thin_crab_cavity")
outside = [v for v in verified if !any(startswith(v, k * ".") for k in named)]
println()
println("verified entries OUTSIDE the named-kind list: ", length(outside))
foreach(v -> println("   ", v), sort(outside))
