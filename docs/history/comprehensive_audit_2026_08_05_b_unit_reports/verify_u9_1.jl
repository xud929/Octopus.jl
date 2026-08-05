# AUDITOR VERIFICATION of U9-1: curved solenoid implicit-midpoint solve has no
# convergence check; at the element's own DEFAULT nst it can return a wildly
# non-symplectic map, or NaN, with no warning.
using Octopus, ForwardDiff
S6 = let M = zeros(6,6); for b in (1,3,5); M[b,b+1] = 1.0; M[b+1,b] = -1.0; end; M end
U  = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)
resid(e) = (J = ForwardDiff.jacobian(u -> collect(e(u...)), collect(U)); maximum(abs, J'*S6*J - S6))

println(rpad("L",6), rpad("ks",7), rpad("h",6), rpad("q=L*ks/(2nst)",15), rpad("residual",14), "x_out")
for (L, ks, h) in ((1.3,1.7,0.18), (5.0,1.7,0.1), (1.3,5.0,0.1), (5.0,5.0,0.1),
                   (1.3,20.0,0.1), (5.0,20.0,0.1), (5.0,5.0,0.5), (1.3,20.0,0.5))
    e = Octopus.Solenoid(SolenoidSpec(L=L, ks=ks, h=h))       # DEFAULT nst
    q = L*ks/(2*e.nst)
    r = try resid(e) catch err; NaN end
    x = try e(U...)[1] catch err; NaN end
    println(rpad(L,6), rpad(ks,7), rpad(h,6), rpad(round(q,digits=4),15),
            rpad(string(round(r, sigdigits=4)),14), round(x, sigdigits=5))
end
println()
println("convergence: does raising nst recover? (L=5, ks=20, h=0.1)")
for nst in (16, 64, 128, 256, 512)
    e = Octopus.Solenoid(SolenoidSpec(L=5.0, ks=20.0, h=0.1, nst=nst))
    r = try resid(e) catch err; NaN end
    println("  nst=", rpad(nst,5), " residual = ", round(r, sigdigits=4))
end
println()
println("default nst for a curved solenoid = ", Octopus.Solenoid(SolenoidSpec(L=1.3,ks=1.7,h=0.18)).nst)
println("ParamMeta-declared nst default     = ", parameter_schema(ElementSpec{:solenoid})[:nst].default)
