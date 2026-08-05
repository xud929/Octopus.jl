using Octopus, LinearAlgebra

println("### 1. chunked-radiation bit-equality: is the physics non-vacuous?")
let
    radiation = LumpedRadSpec(damping_turns=(20.0, 25.0, 30.0), beta=(0.7, 0.9, 1.1),
        alpha=(0.2, -0.1, 0.05), sigma=(1.2e-3, 0.8e-3, 2.0e-3), rng_id=0x1234)
    n = 128
    initial = Phase6DRep(
        collect(range(-1.0e-3, 1.0e-3; length=n)), collect(range(2.0e-4, -2.0e-4; length=n)),
        collect(range(0.7e-3, -0.7e-3; length=n)), collect(range(-1.0e-4, 1.0e-4; length=n)),
        collect(range(-2.0e-3, 2.0e-3; length=n)), collect(range(3.0e-4, -3.0e-4; length=n)))
    continuous = deepcopy(initial); chunked = deepcopy(initial); wrongkey = deepcopy(initial)
    set_global_rng!(seed=0x5eed, method=:philox)
    execute!(TrackingTask((radiation,)), continuous; turns=7)
    set_global_rng!(seed=0x5eed, method=:philox)
    t = TrackingTask((radiation,)); execute!(t, chunked; turns=3); execute!(t, chunked; turns=4)
    # what a per-call (rather than absolute) turn key would produce: two fresh tasks
    set_global_rng!(seed=0x5eed, method=:philox)
    execute!(TrackingTask((radiation,)), wrongkey; turns=3)
    execute!(TrackingTask((radiation,)), wrongkey; turns=4)
    d_init = maximum(maximum(abs, a .- b) for (a, b) in
                     zip(coordinate_arrays(continuous), coordinate_arrays(initial)))
    d_chunk = maximum(maximum(abs, a .- b) for (a, b) in
                      zip(coordinate_arrays(continuous), coordinate_arrays(chunked)))
    d_wrong = maximum(maximum(abs, a .- b) for (a, b) in
                      zip(coordinate_arrays(continuous), coordinate_arrays(wrongkey)))
    println("  |continuous - initial|      = ", d_init, "   (physics is non-vacuous if > 0)")
    println("  |continuous - chunked|      = ", d_chunk, "   (the assertion: must be 0)")
    println("  |continuous - restarted|    = ", d_wrong, "   (defect signal the test guards)")
end

println("\n### 2. near-round precision support: soft-vs-weak deltas vs atol=32eps(T) (test 626-629)")
for T in (Float32, Float64)
    inner, outer = Octopus._near_round_eta_bounds(zero(T))
    for eta in (inner / T(2), T(0.75) * outer, T(1.2) * outer)
        sigx = sqrt(one(T) + eta); sigy = sqrt(one(T) - eta); kbb = T(-2.0e-3)
        covariance = Matrix(Diagonal(T[sigx * sigx, sigx * sigx, sigy * sigy, sigy * sigy]))
        ws = ThinStrongBeam(ThinStrongBeamSpec{T}(; kbb=kbb, covariance=covariance))
        initial = (T(0.4), T(1.0e-4), T(-0.2), T(-1.5e-4), zero(T), T(2.0e-4))
        wr = collect(ws(initial...))
        soft_rep = Phase6DRep(([v] for v in initial)...)
        src = (mx=zero(T), sx=sigx, mpx=zero(T), spx=sigx, covxpx=zero(T),
               my=zero(T), sy=sigy, mpy=zero(T), spy=sigy, covypy=zero(T))
        Octopus._apply_slice_kick_one!(soft_rep, 1, src, zero(T), kbb, zero(T), true, false)
        sr = collect(soft_rep[1])
        tol = T(32) * eps(T)
        println("  ", T, " eta=", eta, "  max|soft-weak| = ", maximum(abs.(sr .- wr)),
                "   tol = ", tol, "   kick size |dpx| = ", abs(wr[2] - initial[2]),
                "   tol/kick = ", tol / abs(wr[2] - initial[2]))
    end
end

println("\n### 3. equal_area closed form uses the same inverse_erf the implementation does")
let ns = 7
    z, w = Octopus._gaussian_slices(Float64, ns, nothing, nothing, 1.0, :equal_area, nothing)
    half = (ns - 1) ÷ 2
    ref = [Octopus.SQRT2 * Octopus.inverse_erf(2k / ns) for k in -half:half]
    println("  max|z - ref| = ", maximum(abs, collect(z) .- ref),
            "   (both sides call Octopus.inverse_erf)")
    # independent reference: bisection on erf from SpecialFunctions-free series
    println("  ns=5 Furman anchor already pins inverse_erf at 5 points to 5e-6 (see probe_headroom J)")
end

println("\n### 4. _wedge_quad: is it non-identity where the symplecticity check runs?")
let u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    o = collect(Octopus._wedge_quad(0.1, 0.6, 1.0, 2.0, u...))
    println("  max|_wedge_quad(0.1,0.6,1,2,u) - u| = ", maximum(abs, o .- collect(u)),
            "  (identity would still pass the symplecticity assertion at line 1371)")
end

println("\n### 5. checked-count headroom of the element-parameter contract (test line 1889)")
let r = validate(ElementParameterEffectivenessContract())
    println("  checked = ", r.metrics[:checked], "  asserted > 200  -> ",
            r.metrics[:checked] - 200, " checks could vanish silently and still pass")
end
