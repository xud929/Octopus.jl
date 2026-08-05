using Octopus, CUDA, Printf
const O = Octopus

for T in (Float64, Float32)
    n = 64; nx = Int32(16); ny = Int32(16)
    x  = CUDA.zeros(T, n); px = CUDA.zeros(T, n)
    y  = CUDA.zeros(T, n); py = CUDA.zeros(T, n)
    z  = CUDA.zeros(T, n); pz = CUDA.zeros(T, n)
    idx = CuArray(collect(1:n))
    P(k) = CUDA.zeros(T, Int(nx), Int(ny))
    phiL, ExL, EyL = P(1), P(2), P(3)
    phiR, ExR, EyR = P(4), P(5), P(6)
    for mc in (Int32(1), Int32(2))
        for (name, f, args) in (
            ("_cuda_pic_kick_indexed_kernel!  (DEAD)",
             O._cuda_pic_kick_indexed_kernel!,
             (x, px, y, py, z, idx, phiL, ExL, EyL, phiR, ExR, EyR,
              T(0), T(0), T(1), T(1), nx, ny, mc, T(0), T(1), T(0), T(1e-4))),
            ("_cuda_pic_kick_indexed_longitudinal_kernel! (DEAD)",
             O._cuda_pic_kick_indexed_longitudinal_kernel!,
             (x, px, y, py, pz, z, idx, phiL, ExL, EyL, phiR, ExR, EyR,
              T(0), T(0), T(1), T(1), nx, ny, mc, T(0), T(1), T(0), T(1e-4))),
        )
            st = try
                k = CUDA.@cuda launch=false f(args...)
                k(args...; threads=32, blocks=2)
                CUDA.synchronize()
                "compiles+runs"
            catch err
                "FAIL: " * first(first(split(sprint(showerror, err), '\n')), 120)
            end
            @printf("%-52s T=%-8s mc=%d  %s\n", name, T, mc, st)
        end
    end
end
