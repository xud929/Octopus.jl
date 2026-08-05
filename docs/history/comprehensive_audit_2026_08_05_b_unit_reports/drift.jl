using Octopus, Printf
b0, g0 = reference_beta_gamma(2.5e9, Octopus.PMASS_EV)
println("2.5 GeV proton: beta0=", b0, " gamma0=", g0)
# repeated identity sandwich delta -> pt -> delta, zero kick
d = 0.0
for k in (1, 10, 100, 1000, 10_000, 100_000, 1_000_000)
    global d
    while true
        pt = Octopus._pt_from_delta(d, b0, g0)
        d = Octopus._delta_from_pt(pt, b0, g0)
        break
    end
end
d = 0.0
hist = Float64[]
for k in 1:1_000_000
    global d
    pt = Octopus._pt_from_delta(d, b0, g0)
    d  = Octopus._delta_from_pt(pt, b0, g0)
    (k in (1, 10, 100, 1000, 10_000, 100_000, 1_000_000)) && push!(hist, d)
end
for (k, v) in zip((1,10,100,1000,10_000,100_000,1_000_000), hist)
    @printf("  after %8d identity sandwiches from delta=0: delta = %.6e\n", k, v)
end
println("  -> the bias is a FIXED POINT, not a random walk" )
# 10 GeV electron
b0, g0 = reference_beta_gamma(10.0e9, Octopus.EMASS_EV)
d = 0.0
for k in 1:1_000_000
    global d
    d = Octopus._delta_from_pt(Octopus._pt_from_delta(d, b0, g0), b0, g0)
end
@printf("  10 GeV electron after 1e6 sandwiches: delta = %.6e\n", d)
