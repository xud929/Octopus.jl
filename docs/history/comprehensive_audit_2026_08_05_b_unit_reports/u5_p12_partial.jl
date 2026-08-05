using Octopus
const O = Octopus
mkb(rng_id, charge, mc2, E0) = begin
    set_global_rng!(seed=5, method=:philox)
    Beam(300, CPUThreadsExecutionPolicy(), Float64;
        beta=(0.55,0.056,12.7), alpha=(0.0,0.0,0.0), sigma=(106.0e-6,9.5e-6,7.0e-3),
        cutoff=5.0, rng_id=rng_id, charge=charge, mc2=mc2, E0=E0, r0=RE*ME0/mc2, npart=1.0e10)
end
beams() = (mkb(1,-1.0,EMASS_EV,10.0e9), mkb(2,1.0,PMASS_EV,275.0e9))
L6s(b,t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0,0.0,0.0),
                                  alpha2=(0.0,0.0,0.0), dmu=2pi .* t)
A = L6s((0.55,0.056,12.7),(0.08,0.14,-0.069)); B = L6s((0.8,0.072,90.9),(0.228,0.210,-0.01))
ip = StrongStrongCollision(:ip)
turns_of(p) = [parse(Int, first(split(l,'\t'))) for l in readlines(p)[2:end]]
p = tempname()*".lum"
t1 = StrongStrongTask((ip,A),(ip,B); luminosity_path=p, luminosity_append=true)
b1,b2 = beams(); execute!(t1,b1,b2; turns=10)
println("=== P12: PARTIAL silent truncation by a fresh task with a wrong start_turn ===")
println("  before: ", turns_of(p))
t2 = StrongStrongTask((ip,A),(ip,B); luminosity_path=p, luminosity_append=true)
b1,b2 = beams(); execute!(t2,b1,b2; turns=1, start_turn=2)   # no warning expected
println("  after fresh task, start_turn=2, turns=1: ", turns_of(p))
println("  rows destroyed = ", 10 - length(turns_of(p)) + 0, "  (warning fires only when ALL rows go)")
rm(p; force=true)
