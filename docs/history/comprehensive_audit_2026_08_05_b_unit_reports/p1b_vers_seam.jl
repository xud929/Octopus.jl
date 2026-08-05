using Octopus
const O = Octopus
setprecision(BigFloat, 400)
relerr(got, exact) = Float64(abs(BigFloat(got) - exact) / abs(exact))

function scan(lo, hi, n)
    best = 0.0; bestu = lo
    for k in 0:n
        u = lo + (hi - lo) * k / n
        u == 0 && continue
        e = relerr(O._curv_vers(u, 1.0), (1 - cos(BigFloat(u))) / BigFloat(u))
        if e > best; best = e; bestu = u; end
    end
    return best, bestu
end

b, u = scan(0.125, 0.5, 200000)
println("closed branch max relerr on u in [0.125, 0.5] = ", b, " at u = ", u)
b, u = scan(1e-7, prevfloat(0.125), 200000)
println("series branch max relerr on u in (0, 0.125) = ", b, " at u = ", u)
b, u = scan(1e-7, 3.0, 200000)
println("both branches max relerr on u in (0, 3]    = ", b, " at u = ", u)
