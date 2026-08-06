# AUDITOR VERIFICATION of U11-1: the CUDA spectral R9 dropped-charge tripwire
# reported EXACTLY ZERO for the most severe charge loss it exists to catch.
#
# Kernel-level, against the CPU twin's conservation rule (ns - sum(rho)), which
# counts each fully-lost particle as one unit.
using Octopus
import CUDA
const O = Octopus

Nx = Ny = 16
Lx = Ly = 1.0e-3
hx = 2Lx / (Nx + 1); hy = 2Ly / (Ny + 1)

# 63 well-inside particles plus one pathological one.
function run_case(label, xbad)
    n = 64
    sx = fill(0.0, n); sy = fill(0.0, n)
    for k in 1:(n - 1)
        sx[k] = (k / n - 0.5) * Lx; sy[k] = ((k * 7 % n) / n - 0.5) * Ly
    end
    sx[n] = xbad; sy[n] = 0.0

    dsx = CUDA.CuArray(sx); dsy = CUDA.CuArray(sy)
    rho = CUDA.zeros(Float64, Nx, Ny)
    dropped = CUDA.zeros(Float64, 1)
    CUDA.@cuda threads=64 blocks=1 O._cuda_spectral_deposit_kernel!(
        rho, dsx, dsy, Lx, Ly, hx, hy, Nx, Ny, dropped)
    CUDA.synchronize()

    cuda_dropped = Array(dropped)[1]
    cpu_deficit = n - sum(Array(rho))          # the CPU twin's conservation rule
    println(rpad(label, 26),
            " CPU deficit = ", rpad(round(cpu_deficit, sigdigits = 6), 12),
            "  CUDA dropped = ", rpad(round(cuda_dropped, sigdigits = 6), 12),
            "  agree = ", isapprox(cuda_dropped, cpu_deficit; atol = 1e-9))
end

println("### CUDA spectral deposit tripwire vs the CPU conservation rule")
run_case("in-box control",           0.0)
run_case("x = 1e11 (floor ok)",      1.0e11)
run_case("x = 1e13 (floor ok)",      1.0e13)
run_case("x = 1e15 (GRID_REJECT)",   1.0e15)
run_case("x = 1e16 (GRID_REJECT)",   1.0e16)
run_case("x = NaN",                  NaN)
run_case("x = Inf",                  Inf)
