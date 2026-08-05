# Instrument validation of the ONLY enforced gate in
# validation/pic_gaussian_luminosity_validation.jl (lines 148-149, 1e-12):
# feed it the recorded U5-8 defect (truncated overlap sum) and see whether it reports it.
include(joinpath(@__DIR__, "repo", "src", "Octopus.jl"))
using .Octopus
using SpecialFunctions
const O = Octopus
function radical_inverse(index, base)
    v = 0.0; f = inv(Float64(base))
    while index > 0; index, d = divrem(index, base); v += d*f; f /= base; end
    v
end
function halton(mx,my,sx,sy,n;start=1)
    x=Vector{Float64}(undef,n); y=similar(x)
    for k in 1:n
        i=start+k-1
        ux=clamp(radical_inverse(i,2),eps(),1-eps()); uy=clamp(radical_inverse(i,3),eps(),1-eps())
        x[k]=mx+sx*sqrt(2.0)*erfinv(2ux-1); y[k]=my+sy*sqrt(2.0)*erfinv(2uy-1)
    end
    x,y
end
# the script's local reimplementation, verbatim
function deposited_overlap(method, grid, padding_cells, x1, y1, x2, y2)
    nx, ny = grid
    xmin=min(minimum(x1),minimum(x2)); xmax=max(maximum(x1),maximum(x2))
    ymin=min(minimum(y1),minimum(y2)); ymax=max(maximum(y1),maximum(y2))
    w0=max(xmax-xmin,eps()); h0=max(ymax-ymin,eps())
    tx=w0/(nx-1-padding_cells); ty=h0/(ny-1-padding_cells)
    w=w0+padding_cells*tx; h=h0+padding_cells*ty
    xmin-=0.5*padding_cells*tx; ymin-=0.5*padding_cells*ty
    hx=w/(nx-1); hy=h/(ny-1)
    q1=zeros(nx+1,ny+1); q2=zeros(nx+1,ny+1)
    O._pic_deposit!(q1,method,x1,y1,xmin,ymin,hx,hy,nx+1,ny+1)
    O._pic_deposit!(q2,method,x2,y2,xmin,ymin,hx,hy,nx+1,ny+1)
    sum(@view(q1[1:nx,1:ny]) .* @view(q2[1:nx,1:ny])) / (length(x1)*length(x2)*hx*hy)
end
n = 20000
println("configuration                     method grid  interface_rel_err   gate(1e-12)")
for (label, same) in (("committed cases (offset_flat)", false), ("BOTH BEAMS IDENTICAL", true))
    x1,y1 = halton(-30e-6,2e-6,110e-6,9e-6,n;start=1)
    x2,y2 = same ? (x1,y1) : halton(25e-6,-3e-6,85e-6,14e-6,n;start=n+101)
    for method in (:CIC,:TSC), g in (32,128)
        v = deposited_overlap(method,(g,g),0.1,x1,y1,x2,y2)
        s = PICPoissonSolver(grid=(g,g), deposit_method=:CIC, luminosity_deposit_method=method)
        p = O._pic_luminosity(s,x1,y1,x2,y2,inv(Float64(length(x1)*length(x2))))
        e = abs(p-v)/max(abs(v),eps())
        println(rpad(label,33)," ",rpad(String(method),6)," ",rpad(g,5)," ",rpad(e,20)," ", e<=1e-12 ? "PASS" : "FAIL")
    end
end
