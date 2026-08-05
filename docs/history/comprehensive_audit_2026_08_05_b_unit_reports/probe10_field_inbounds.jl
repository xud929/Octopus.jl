using Octopus
using Printf
const O = Octopus

# Local copy of _pic_field! with the SAME arithmetic, differing only by @inbounds
# on the Ex pass (the shipped one marks the Ey pass @inbounds and the fourth-order
# Ex inner loop, but not the second-order Ex inner loop or the Ex boundary rows).
function field_all_inbounds!(Ex, Ey, phi, hx, hy, fourth::Bool)
    nx, ny = size(phi)
    T = eltype(phi)
    hxi = inv(hx); hyi = inv(hy)
    c4 = T(1) / T(12)
    @inbounds for i in 1:nx
        Ey[i, 1] = hyi * (T(1.5) * phi[i, 1] - 2 * phi[i, 2] + T(0.5) * phi[i, 3])
        Ey[i, ny] = hyi * (-T(1.5) * phi[i, ny] + 2 * phi[i, ny - 1] - T(0.5) * phi[i, ny - 2])
    end
    if fourth && ny >= 5
        @inbounds for i in 1:nx
            Ey[i, 2] = T(0.5) * hyi * (phi[i, 1] - phi[i, 3])
            Ey[i, ny - 1] = T(0.5) * hyi * (phi[i, ny - 2] - phi[i, ny])
        end
        @inbounds for j in 3:(ny - 2), i in 1:nx
            Ey[i, j] = c4 * hyi * ((phi[i, j + 2] - phi[i, j - 2]) + 8 * (phi[i, j - 1] - phi[i, j + 1]))
        end
    else
        @inbounds for j in 2:(ny - 1), i in 1:nx
            Ey[i, j] = T(0.5) * hyi * (phi[i, j - 1] - phi[i, j + 1])
        end
    end
    @inbounds for j in 1:ny
        Ex[1, j] = hxi * (T(1.5) * phi[1, j] - 2 * phi[2, j] + T(0.5) * phi[3, j])
        Ex[nx, j] = hxi * (-T(1.5) * phi[nx, j] + 2 * phi[nx - 1, j] - T(0.5) * phi[nx - 2, j])
        if fourth && nx >= 5
            Ex[2, j] = T(0.5) * hxi * (phi[1, j] - phi[3, j])
            Ex[nx - 1, j] = T(0.5) * hxi * (phi[nx - 2, j] - phi[nx, j])
            for i in 3:(nx - 2)
                Ex[i, j] = c4 * hxi * ((phi[i + 2, j] - phi[i - 2, j]) + 8 * (phi[i - 1, j] - phi[i + 1, j]))
            end
        else
            for i in 2:(nx - 1)
                Ex[i, j] = T(0.5) * hxi * (phi[i - 1, j] - phi[i + 1, j])
            end
        end
    end
    return nothing
end

for n in (64, 128, 256)
    phi = [sin(0.01i) * cos(0.013j) for i in 1:n, j in 1:n]
    Ex = similar(phi); Ey = similar(phi); Ex2 = similar(phi); Ey2 = similar(phi)
    for fourth in (false, true)
        O._pic_field!(Ex, Ey, phi, 1.0e-5, 1.0e-6, fourth)
        field_all_inbounds!(Ex2, Ey2, phi, 1.0e-5, 1.0e-6, fourth)
        ident = Ex == Ex2 && Ey == Ey2
        t1 = (O._pic_field!(Ex, Ey, phi, 1.0e-5, 1.0e-6, fourth);
              @elapsed for _ in 1:200; O._pic_field!(Ex, Ey, phi, 1.0e-5, 1.0e-6, fourth); end)
        t2 = (field_all_inbounds!(Ex2, Ey2, phi, 1.0e-5, 1.0e-6, fourth);
              @elapsed for _ in 1:200; field_all_inbounds!(Ex2, Ey2, phi, 1.0e-5, 1.0e-6, fourth); end)
        @printf("grid=%-4d fourth=%-5s bit-identical=%-5s shipped %7.2f us   all-@inbounds %7.2f us   %.2fx\n",
                n, fourth, ident, 1e6 * t1 / 200, 1e6 * t2 / 200, t1 / t2)
    end
end

println("\n--- deposit inner-loop type stability (Symbol(method) branch inside the loop) ---")
ct = code_typed(O._pic_deposit_range!,
                (Matrix{Float64}, Symbol, Vector{Float64}, Vector{Float64}, Float64,
                 Float64, Float64, Float64, Int, Int, Int, Int))[1]
rt = ct[2]
body = string(ct[1])
@printf("return type = %s;  'Union{' occurrences in typed IR = %d;  'Any' = %d\n",
        rt, count(i -> true, findall("Union{", body)), count(i -> true, findall("::Any", body)))
