# Emittance-evolution cross-check against BeamBeam3D (round and flat).
# Same beam parameters as the coherent-mode benchmark deck; records the
# per-turn geometric emittance of beam 1 so eps(turn) can be overlaid on
# BeamBeam3D's fort.24 columns 7-8 (the decks and outputs are archived in
# the paper repository, https://github.com/xud929/2026_octopus_cpc).
# Writes emit_xcode_<tag>.tsv under result/. Run from the project root:
#
#   julia --startup-file=no --project=. validation/emit_xcode.jl
include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
mkpath(joinpath(@__DIR__, "..", "result"))
using .Octopus
using Statistics

function emit_series(; aspect, turns, n_macro, xi, seed, offset)
    set_global_rng!(seed=seed, method=:philox)
    policy = CPUThreadsExecutionPolicy()
    energy = 10.0e9
    gamma_rel = energy / EMASS_EV
    r0 = RE * ME0 / EMASS_EV
    sig = 106.0e-6
    beta = (0.55, 0.55, 0.7e-2 / 5.5e-4)
    sigy = aspect * sig
    sigma = (sig, sigy, 0.7e-2)
    npart = xi * 2pi * gamma_rel * sig * (sig + sigy) / (r0 * beta[1])
    off = (offset * sig, 0.0, offset * sigy, 0.0, 0.0, 0.0)
    b1 = Beam(n_macro, policy, Float64; beta=beta, alpha=(0.0,0.0,0.0),
        sigma=sigma, cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV,
        E0=energy, r0=r0, npart=npart, initial_offset=off)
    b2 = Beam(n_macro, policy, Float64; beta=beta, alpha=(0.0,0.0,0.0),
        sigma=sigma, cutoff=5.0, rng_id=2, charge=+1.0, mc2=EMASS_EV,
        E0=energy, r0=r0, npart=npart)
    slicing = LongitudinalSlicing(; method=:normal_quantile, nslices=1,
                                  center_position=:centroid)
    solver = PICPoissonSolver(; slicing=slicing, grid=(128,128),
        deposit_method=:CIC, green_type=:integrated,
        green_cache=:slice_pair, longitudinal_kick=false)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    ot = Linear6DSpec{Float64}(; beta1=beta, beta2=beta,
        alpha1=(0.0,0.0,0.0), alpha2=(0.0,0.0,0.0),
        dmu=2pi .* (0.31, 0.32, -0.01))
    task = StrongStrongTask((ip, ot), (ip, ot); policy=policy)
    function emit(b)
        x=Array(b.rep.x); px=Array(b.rep.px); y=Array(b.rep.y); py=Array(b.rep.py)
        n=length(x)
        cx=x.-sum(x)/n; cpx=px.-sum(px)/n; cy=y.-sum(y)/n; cpy=py.-sum(py)/n
        ex=sqrt(max(0.0,(sum(cx.^2)/n)*(sum(cpx.^2)/n)-(sum(cx.*cpx)/n)^2))
        ey=sqrt(max(0.0,(sum(cy.^2)/n)*(sum(cpy.^2)/n)-(sum(cy.*cpy)/n)^2))
        (ex, ey)
    end
    tag = aspect == 1.0 ? "round" : "flat"
    open(joinpath(@__DIR__, "..", "result", "emit_xcode_$(tag).tsv"),"w") do io
        println(io, "# Octopus per-turn geometric emittance, aspect=$aspect xi=$xi")
        println(io, "turn\tex\tey")
        for t in 1:turns
            execute!(task, b1, b2; turns=1)
            if t % 8 == 0 || t == 1
                e = emit(b1)
                println(io, t, "\t", e[1], "\t", e[2]); flush(io)
            end
        end
    end
    println("done aspect=", aspect)
end

emit_series(aspect=1.0,  turns=4096, n_macro=100_000, xi=0.005, seed=1, offset=0.1)
emit_series(aspect=1/11, turns=4096, n_macro=100_000, xi=0.005, seed=1, offset=0.1)
