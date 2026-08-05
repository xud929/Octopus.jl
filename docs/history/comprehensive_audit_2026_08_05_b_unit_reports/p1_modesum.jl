# U11 probe 1: INDEPENDENT continuum mode-sum verification of the spectral
# sine-Poisson solve (both :grid and :grid_free), written from
# docs/theory/spectral_sine_poisson_solver.md alone, not from the source.
#
# Conventions derived independently:
#   rho_lm = (4/(ab)) * int rho sin(al x) sin(bm y),  al = l pi / a, bm = m pi / b
#   phi_lm = -rho_lm / (al^2 + bm^2)                  (lap phi = rho, Dirichlet)
#   unit-charge normalisation: rho integrates to 1, i.e. divide by ns
# The code's stated field convention is K = -4 pi E = +4 pi grad(phi), and the
# potential it stores is Phi_code = -4 pi phi.  So independently:
#   Ex_ref(x,y) = 4 pi sum_lm phi_lm al cos(al x) sin(bm y)
#   Ey_ref(x,y) = 4 pi sum_lm phi_lm bm sin(al x) cos(bm y)
#   Phi_ref(x,y) = -4 pi sum_lm phi_lm sin(al x) sin(bm y)
using Octopus, Printf
const O = Octopus

relerr(a, b) = maximum(abs.(a .- b)) / max(maximum(abs, b), eps())

# ---------- :grid path -------------------------------------------------------
function modesum_grid(rho, ns, Lx, Ly, Nx, Ny, fx, fy)
    a = 2Lx; b = 2Ly
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    hx = a / (Nx + 1); hy = b / (Ny + 1)
    # forward: rho_lm from the deposited mesh (mesh node i sits at x = i*hx)
    philm = zeros(Nx, Ny)
    for l in 1:Nx, m in 1:Ny
        s = 0.0
        for i in 1:Nx, j in 1:Ny
            s += rho[i, j] * sin(al[l] * i * hx) * sin(bm[m] * j * hy)
        end
        rholm = (4 / (a * b)) * (s / ns)
        philm[l, m] = -rholm / (al[l]^2 + bm[m]^2)
    end
    nf = length(fx)
    Ex = zeros(nf); Ey = zeros(nf); Phi = zeros(nf)
    for k in 1:nf
        X = fx[k] + Lx; Y = fy[k] + Ly       # box coordinates in [0,a]x[0,b]
        ex = 0.0; ey = 0.0; ph = 0.0
        for l in 1:Nx, m in 1:Ny
            sx = sin(al[l] * X); cx = cos(al[l] * X)
            sy = sin(bm[m] * Y); cy = cos(bm[m] * Y)
            ex += philm[l, m] * al[l] * cx * sy
            ey += philm[l, m] * bm[m] * sx * cy
            ph += philm[l, m] * sx * sy
        end
        Ex[k] = 4pi * ex; Ey[k] = 4pi * ey; Phi[k] = -4pi * ph
    end
    return Phi, Ex, Ey
end

function cic_deposit_ref(sx, sy, Lx, Ly, Nx, Ny)
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    rho = zeros(Nx, Ny)
    for p in eachindex(sx)
        X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); wx = X - i; wy = Y - j
        for (ii, cx) in ((i, 1 - wx), (i + 1, wx)), (jj, cy) in ((j, 1 - wy), (j + 1, wy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += cx * cy)
        end
    end
    return rho
end

Nx, Ny = 12, 10
L = 3.0e-3
ns = 40
sx = [1.0e-3 * sin(0.7 * i) for i in 1:ns]
sy = [0.8e-3 * cos(0.31 * i + 0.4) for i in 1:ns]
fx = [1.2e-3 * sin(1.1 * k + 0.2) for k in 1:17]
fy = [0.9e-3 * cos(0.53 * k) for k in 1:17]

rho = cic_deposit_ref(sx, sy, L, L, Nx, Ny)
Phi_ref, Ex_ref, Ey_ref = modesum_grid(rho, ns, L, L, Nx, Ny, fx, fy)

ws = O._spectral_grid_ws(Nx, Ny)
Phi_c, Ex_c, Ey_c = O._spectral_field_grid_potential!(ws, sx, sy, fx, fy, L, L)

@printf("grid  Ex  relerr vs independent mode sum : %.3e\n", relerr(Ex_c, Ex_ref))
@printf("grid  Ey  relerr vs independent mode sum : %.3e\n", relerr(Ey_c, Ey_ref))
@printf("grid  Phi relerr vs independent mode sum : %.3e\n", relerr(Phi_c, Phi_ref))

# The split solve/eval pair (R12) must equal the fused one bit for bit.
ws2 = O._spectral_grid_ws(Nx, Ny)
Ex_f, Ey_f = O._spectral_field_grid!(ws2, sx, sy, fx, fy, L, L)
ws3 = O._spectral_grid_ws(Nx, Ny)
O._spectral_field_grid_solve!(ws3, sx, sy, L, L)
Ex_s, Ey_s = O._spectral_field_grid_eval(copy(ws3.Exg), copy(ws3.Eyg), Nx, Ny, fx, fy, L, L)
@printf("grid  R12 split == fused, bitwise        : %s / %s\n",
        Ex_f == Ex_s, Ey_f == Ey_s)

# ---------- :grid_free path --------------------------------------------------
function modesum_free(sx, sy, Lx, Ly, Nx, Ny, fx, fy)
    a = 2Lx; b = 2Ly; ns = length(sx)
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    philm = zeros(Nx, Ny)
    for l in 1:Nx, m in 1:Ny
        s = 0.0
        for p in eachindex(sx)
            s += sin(al[l] * (sx[p] + Lx)) * sin(bm[m] * (sy[p] + Ly))
        end
        rholm = (4 / (a * b)) * (s / ns)
        philm[l, m] = -rholm / (al[l]^2 + bm[m]^2)
    end
    nf = length(fx); Ex = zeros(nf); Ey = zeros(nf); Phi = zeros(nf)
    for k in 1:nf
        X = fx[k] + Lx; Y = fy[k] + Ly
        ex = 0.0; ey = 0.0; ph = 0.0
        for l in 1:Nx, m in 1:Ny
            sxx = sin(al[l] * X); cxx = cos(al[l] * X)
            syy = sin(bm[m] * Y); cyy = cos(bm[m] * Y)
            ex += philm[l, m] * al[l] * cxx * syy
            ey += philm[l, m] * bm[m] * sxx * cyy
            ph += philm[l, m] * sxx * syy
        end
        Ex[k] = 4pi * ex; Ey[k] = 4pi * ey; Phi[k] = -4pi * ph
    end
    return Phi, Ex, Ey
end

Phi_fr, Ex_fr, Ey_fr = modesum_free(sx, sy, L, L, Nx, Ny, fx, fy)
Phi_g, Ex_g, Ey_g = O._spectral_field_free_potential(sx, sy, fx, fy, L, L, Nx, Ny)
@printf("free  Ex  relerr vs independent mode sum : %.3e\n", relerr(Ex_g, Ex_fr))
@printf("free  Ey  relerr vs independent mode sum : %.3e\n", relerr(Ey_g, Ey_fr))
@printf("free  Phi relerr vs independent mode sum : %.3e\n", relerr(Phi_g, Phi_fr))

# ---------- gradient consistency: is Phi the potential of (Ex,Ey)? -----------
# Phi_code = -4 pi phi and K = 4 pi grad(phi) = -grad(Phi_code).  Check by
# central differences of the code's own potential against its own field.
h = 1.0e-7
xq = [0.0, 5.0e-4, -8.0e-4]; yq = [1.0e-4, -3.0e-4, 6.0e-4]
Pp, _, _ = O._spectral_field_grid_potential!(ws, sx, sy, xq .+ h, yq, L, L)
Pm, _, _ = O._spectral_field_grid_potential!(ws, sx, sy, xq .- h, yq, L, L)
Pyp, _, _ = O._spectral_field_grid_potential!(ws, sx, sy, xq, yq .+ h, L, L)
Pym, _, _ = O._spectral_field_grid_potential!(ws, sx, sy, xq, yq .- h, L, L)
_, Exq, Eyq = O._spectral_field_grid_potential!(ws, sx, sy, xq, yq, L, L)
fdx = -(Pp .- Pm) ./ (2h); fdy = -(Pyp .- Pym) ./ (2h)
@printf("grid  -dPhi/dx vs Ex (rel, CIC-limited)  : %.3e\n", relerr(fdx, Exq))
@printf("grid  -dPhi/dy vs Ey (rel, CIC-limited)  : %.3e\n", relerr(fdy, Eyq))

_, Exf, Eyf = O._spectral_field_free_potential(sx, sy, xq, yq, L, L, Nx, Ny)
Pfp, _, _ = O._spectral_field_free_potential(sx, sy, xq .+ h, yq, L, L, Nx, Ny)
Pfm, _, _ = O._spectral_field_free_potential(sx, sy, xq .- h, yq, L, L, Nx, Ny)
Pfyp, _, _ = O._spectral_field_free_potential(sx, sy, xq, yq .+ h, L, L, Nx, Ny)
Pfym, _, _ = O._spectral_field_free_potential(sx, sy, xq, yq .- h, L, L, Nx, Ny)
@printf("free  -dPhi/dx vs Ex (rel)               : %.3e\n",
        relerr(-(Pfp .- Pfm) ./ (2h), Exf))
@printf("free  -dPhi/dy vs Ey (rel)               : %.3e\n",
        relerr(-(Pfyp .- Pfym) ./ (2h), Eyf))
