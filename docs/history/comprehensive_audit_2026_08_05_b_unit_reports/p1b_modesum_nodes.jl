# U11 probe 1b: independent mode-sum verification of the :grid solve, evaluated
# AT THE MESH NODES so CIC interpolation error is out of the comparison.
using Octopus, Printf
const O = Octopus
relerr(a, b) = maximum(abs.(a .- b)) / max(maximum(abs, b), eps())

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

# Independent: rho_lm = (4/(ab)) sum_ij rho_ij sin(al x_i) sin(bm y_j) / ns,
# phi_lm = -rho_lm/(al^2+bm^2); Ex = 4pi sum phi_lm al cos sin, Ey likewise,
# Phi = -4pi sum phi_lm sin sin.  Evaluated at the interior mesh nodes.
function modesum_nodes(rho, ns, Lx, Ly, Nx, Ny)
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    philm = zeros(Nx, Ny)
    for l in 1:Nx, m in 1:Ny
        s = 0.0
        for i in 1:Nx, j in 1:Ny
            s += rho[i, j] * sin(al[l] * i * hx) * sin(bm[m] * j * hy)
        end
        philm[l, m] = -((4 / (a * b)) * (s / ns)) / (al[l]^2 + bm[m]^2)
    end
    Ex = zeros(Nx, Ny); Ey = zeros(Nx, Ny); Phi = zeros(Nx, Ny)
    for i in 1:Nx, j in 1:Ny
        X = i * hx; Y = j * hy
        ex = 0.0; ey = 0.0; ph = 0.0
        for l in 1:Nx, m in 1:Ny
            sx = sin(al[l] * X); cx = cos(al[l] * X)
            sy = sin(bm[m] * Y); cy = cos(bm[m] * Y)
            ex += philm[l, m] * al[l] * cx * sy
            ey += philm[l, m] * bm[m] * sx * cy
            ph += philm[l, m] * sx * sy
        end
        Ex[i, j] = 4pi * ex; Ey[i, j] = 4pi * ey; Phi[i, j] = -4pi * ph
    end
    return Phi, Ex, Ey
end

for (Nx, Ny) in ((12, 10), (15, 15), (16, 24))
    L = 3.0e-3; ns = 40
    sx = [1.0e-3 * sin(0.7 * i) for i in 1:ns]
    sy = [0.8e-3 * cos(0.31 * i + 0.4) for i in 1:ns]
    rho = cic_deposit_ref(sx, sy, L, L, Nx, Ny)
    Phi_ref, Ex_ref, Ey_ref = modesum_nodes(rho, ns, L, L, Nx, Ny)
    ws = O._spectral_grid_ws(Nx, Ny)
    O._spectral_field_grid_potential!(ws, sx, sy, Float64[], Float64[], L, L)
    @printf("(%d,%d)  deposit match: %s   Ex %.3e  Ey %.3e  Phi %.3e\n",
            Nx, Ny, rho == ws.rho,
            relerr(ws.Exg, Ex_ref), relerr(ws.Eyg, Ey_ref), relerr(ws.Phig, Phi_ref))
end

# Node-level gradient consistency on the mesh: the spectral derivative must
# equal the analytic derivative of the same truncated series, so the check
# above already covers it; here compare the two independent code routes
# (:grid at the nodes vs :grid_free evaluated at the same nodes with the same
# mesh-sampled source) -- they must agree because both are the same series.
let Nx = 16, Ny = 16, L = 3.0e-3, ns = 40
    sx = [1.0e-3 * sin(0.7 * i) for i in 1:ns]
    sy = [0.8e-3 * cos(0.31 * i + 0.4) for i in 1:ns]
    ws = O._spectral_grid_ws(Nx, Ny)
    hx = 2L / (Nx + 1); hy = 2L / (Ny + 1)
    fx = [i * hx - L for i in 1:Nx for j in 1:Ny]
    fy = [j * hy - L for i in 1:Nx for j in 1:Ny]
    Pg, Exg, Eyg = O._spectral_field_grid_potential!(ws, sx, sy, fx, fy, L, L)
    # grid_free from the SAME deposited mesh: place a "particle" of weight
    # rho[i,j] at each node.  Emulated by repeating the CIC weights is not
    # possible with the equal-weight API, so instead compare grid vs free for a
    # source that lies exactly on nodes (then CIC deposit is exact).
    nsx = [((i % Nx) + 1) * hx - L for i in 1:ns]
    nsy = [((i % Ny) + 1) * hy - L for i in 1:ns]
    Pg2, Exg2, Eyg2 = O._spectral_field_grid_potential!(ws, nsx, nsy, fx, fy, L, L)
    Pf2, Exf2, Eyf2 = O._spectral_field_free_potential(nsx, nsy, fx, fy, L, L, Nx, Ny)
    @printf("on-node source, :grid vs :grid_free   Ex %.3e  Ey %.3e  Phi %.3e\n",
            relerr(Exg2, Exf2), relerr(Eyg2, Eyf2), relerr(Pg2, Pf2))
end
