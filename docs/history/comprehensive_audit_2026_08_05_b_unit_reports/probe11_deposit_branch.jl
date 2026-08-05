using Octopus
using Printf
const O = Octopus

# Same arithmetic as _pic_deposit_drifted_serial!, with the CIC/TSC branch hoisted
# OUT of the per-particle loop (the only change).
function deposit_hoisted!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny)
    hxi = inv(hx); hyi = inv(hy)
    if Symbol(method) == :CIC
        for i in eachindex(x)
            xd = x[i] + px[i] * drift_s; yd = y[i] + py[i] * drift_s
            ix, wx = O._pic_cic_weights((xd - x0) * hxi, nx)
            iy, wy = O._pic_cic_weights((yd - y0) * hyi, ny)
            for m in eachindex(wx), n in eachindex(wy)
                @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
            end
        end
    else
        for i in eachindex(x)
            xd = x[i] + px[i] * drift_s; yd = y[i] + py[i] * drift_s
            ix, wx = O._pic_tsc_weights((xd - x0) * hxi, nx)
            iy, wy = O._pic_tsc_weights((yd - y0) * hyi, ny)
            for m in eachindex(wx), n in eachindex(wy)
                @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
            end
        end
    end
    return charge
end

for grid in (64, 128)
    for meth in (:CIC, :TSC)
        for n in (20000, 68000, 200000)
            x = [1.0e-4 * sin(0.7i) for i in 1:n]; y = [1.0e-5 * sin(0.31i) for i in 1:n]
            px = [1.0e-6 * sin(1.1i) for i in 1:n]; py = [1.0e-7 * sin(0.53i) for i in 1:n]
            c1 = zeros(2grid, 2grid); c2 = zeros(2grid, 2grid)
            x0 = -2.0e-4; y0 = -2.0e-5
            hx = 4.0e-4 / (grid - 1); hy = 4.0e-5 / (grid - 1)
            O._pic_deposit_drifted_serial!(c1, meth, x, px, y, py, 1e-3, x0, y0, hx, hy, grid, grid)
            deposit_hoisted!(c2, meth, x, px, y, py, 1e-3, x0, y0, hx, hy, grid, grid)
            ident = c1 == c2
            t1 = @elapsed for _ in 1:20
                fill!(c1, 0.0)
                O._pic_deposit_drifted_serial!(c1, meth, x, px, y, py, 1e-3, x0, y0, hx, hy, grid, grid)
            end
            t2 = @elapsed for _ in 1:20
                fill!(c2, 0.0)
                deposit_hoisted!(c2, meth, x, px, y, py, 1e-3, x0, y0, hx, hy, grid, grid)
            end
            @printf("grid=%-4d %s n=%-7d identical=%-5s shipped %7.3f ms  hoisted %7.3f ms  %.2fx\n",
                    grid, meth, n, ident, 1000t1 / 20, 1000t2 / 20, t1 / t2)
        end
    end
end
