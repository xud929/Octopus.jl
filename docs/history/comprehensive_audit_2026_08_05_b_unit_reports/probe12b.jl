using Octopus, Printf
const O = Octopus
for meth in (:CIC, :TSC)
    s = O.PICPoissonSolver(kbb1=1.0, kbb2=1.0, luminosity_scale=1.0, grid=(16,16), deposit_method=meth)
    np = 200
    x = [1.0e-4*(2*(i-1)/(np-1)-1) for i in 1:np]
    y = [1.0e-5*(2*(i-1)/(np-1)-1) for i in 1:np]
    nx, ny = O._pic_luminosity_grid(s)
    q1 = zeros(nx+1, ny+1); q2 = zeros(nx+1, ny+1)
    O._pic_luminosity!(s, x, y, x, y, 1.0, q1, q2)
    raw_full = sum(q1 .* q2)
    raw_old  = sum(q1[i,j]*q2[i,j] for i in 1:nx, j in 1:ny)
    excl = sum(q1) - sum(q1[i,j] for i in 1:nx, j in 1:ny)
    @printf("%s: excluded-row charge %.6g/%d (%.3f%%)   relative luminosity deficit of the OLD sum = %.3g\n",
            meth, excl, np, 100*excl/np, (raw_full-raw_old)/raw_full)
end
