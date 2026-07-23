# CUDA implementation of the spectral sine-series strong-strong collision.
#
# cuFFT has no native DST/DCT, so the Dirichlet sine transform (RODFT00) and the
# cosine derivative (REDFT00) are built from complex FFTs of symmetric extensions:
#   DST-I(a)[k] = -imag(FFT(odd_ext(a))[k])          (matches FFTW RODFT00)
#   DCT-I(c)[k] =  real(FFT(even_ext(c))[k])          (matches FFTW REDFT00)
# both verified to machine precision against FFTW. The same FFT plan/size serves
# the DST and the DCT along a given dimension (only the extension sign differs),
# so one plan per dimension covers the whole field solve. The field solve itself
# reproduces the CPU _spectral_field_grid! path bit-for-bit up to FP rounding.

if _HAS_CUDA
    @eval begin

        # --- deposit / interpolate / scatter kernels ---------------------------
        function _cuda_spectral_deposit_kernel!(rho, sx, sy, Lx, Ly, hx, hy, Nx, Ny)
            p = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            p <= length(sx) || return nothing
            X = (sx[p] + Lx) / hx; Y = (sy[p] + Ly) / hy
            i = unsafe_trunc(Int, floor(X)); j = unsafe_trunc(Int, floor(Y))
            wx = X - i; wy = Y - j
            @inbounds begin
                (1 <= i <= Nx   && 1 <= j <= Ny)   && CUDA.@atomic rho[i, j]     += (1 - wx) * (1 - wy)
                (1 <= i + 1 <= Nx && 1 <= j <= Ny) && CUDA.@atomic rho[i + 1, j] += wx * (1 - wy)
                (1 <= i <= Nx   && 1 <= j + 1 <= Ny) && CUDA.@atomic rho[i, j + 1]   += (1 - wx) * wy
                (1 <= i + 1 <= Nx && 1 <= j + 1 <= Ny) && CUDA.@atomic rho[i + 1, j + 1] += wx * wy
            end
            return nothing
        end

        function _cuda_spectral_interp_scatter_kernel!(px, py, idx, Exg, Eyg, fx, fy,
                                                       Lx, Ly, hx, hy, Nx, Ny, a)
            k = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            k <= length(fx) || return nothing
            X = (fx[k] + Lx) / hx; Y = (fy[k] + Ly) / hy
            i = unsafe_trunc(Int, floor(X)); j = unsafe_trunc(Int, floor(Y))
            wx = X - i; wy = Y - j
            ex = zero(eltype(px)); ey = zero(eltype(py))
            @inbounds begin
                if 1 <= i <= Nx && 1 <= j <= Ny;         c = (1 - wx) * (1 - wy); ex += c * Exg[i, j]; ey += c * Eyg[i, j]; end
                if 1 <= i + 1 <= Nx && 1 <= j <= Ny;     c = wx * (1 - wy);       ex += c * Exg[i + 1, j]; ey += c * Eyg[i + 1, j]; end
                if 1 <= i <= Nx && 1 <= j + 1 <= Ny;     c = (1 - wx) * wy;       ex += c * Exg[i, j + 1]; ey += c * Eyg[i, j + 1]; end
                if 1 <= i + 1 <= Nx && 1 <= j + 1 <= Ny; c = wx * wy;             ex += c * Exg[i + 1, j + 1]; ey += c * Eyg[i + 1, j + 1]; end
                p = idx[k]
                px[p] += a * ex   # idx unique within a slice: no atomic needed
                py[p] += a * ey
            end
            return nothing
        end

        # --- cached workspace (plans + buffers) --------------------------------
        mutable struct _SpectralCudaWS{T,P1,P2}
            Nx::Int; Ny::Int; a::Float64; b::Float64
            al::CUDA.CuMatrix{T}         # (Nx,1)
            bm::CUDA.CuMatrix{T}         # (1,Ny)
            G::CUDA.CuMatrix{T}          # Nx×Ny
            rho::CUDA.CuMatrix{T}
            ext1::CUDA.CuMatrix{Complex{T}}   # (2(Nx+1))×Ny
            ext2::CUDA.CuMatrix{Complex{T}}   # Nx×(2(Ny+1))
            s1::CUDA.CuMatrix{T}; s2::CUDA.CuMatrix{T}   # Nx×Ny scratch
            plan1::P1; plan2::P2
        end

        function _SpectralCudaWS(::Type{T}, Nx::Int, Ny::Int) where {T}
            ext1 = CUDA.zeros(Complex{T}, 2 * (Nx + 1), Ny)
            ext2 = CUDA.zeros(Complex{T}, Nx, 2 * (Ny + 1))
            plan1 = plan_fft!(ext1, 1)
            plan2 = plan_fft!(ext2, 2)
            return _SpectralCudaWS{T,typeof(plan1),typeof(plan2)}(
                Nx, Ny, NaN, NaN,
                CUDA.zeros(T, Nx, 1), CUDA.zeros(T, 1, Ny), CUDA.zeros(T, Nx, Ny),
                CUDA.zeros(T, Nx, Ny), ext1, ext2,
                CUDA.zeros(T, Nx, Ny), CUDA.zeros(T, Nx, Ny), plan1, plan2)
        end

        const _SPECTRAL_CUDA_WS_CACHE = Dict{Tuple{DataType,Int,Int},Any}()

        function _spectral_cuda_ws(::Type{T}, Nx::Int, Ny::Int) where {T}
            get!(() -> _SpectralCudaWS(T, Nx, Ny), _SPECTRAL_CUDA_WS_CACHE, (T, Nx, Ny))::_SpectralCudaWS
        end

        function _spectral_cuda_setbox!(ws::_SpectralCudaWS{T}, a::Float64, b::Float64) where {T}
            (ws.a == a && ws.b == b) && return ws
            Nx, Ny = ws.Nx, ws.Ny
            ws.al .= CUDA.CuArray(reshape(T[l * pi / a for l in 1:Nx], Nx, 1))
            ws.bm .= CUDA.CuArray(reshape(T[m * pi / b for m in 1:Ny], 1, Ny))
            ws.G .= 1 ./ (ws.al .^ 2 .+ ws.bm .^ 2)
            ws.a = a; ws.b = b
            return ws
        end

        # DST-I along dim1: out (Nx×Ny) = -imag(FFT(odd_ext1(A)))
        function _cuda_dst1!(out, ws::_SpectralCudaWS, A)
            Nx, Ny = ws.Nx, ws.Ny
            CUDA.fill!(ws.ext1, 0)
            @views ws.ext1[2:Nx + 1, :] .= A
            @views ws.ext1[Nx + 3:2Nx + 2, :] .= .-A[Nx:-1:1, :]
            ws.plan1 * ws.ext1
            @views out .= .-imag.(ws.ext1[2:Nx + 1, :])
            return out
        end
        # DST-I along dim2
        function _cuda_dst2!(out, ws::_SpectralCudaWS, A)
            Nx, Ny = ws.Nx, ws.Ny
            CUDA.fill!(ws.ext2, 0)
            @views ws.ext2[:, 2:Ny + 1] .= A
            @views ws.ext2[:, Ny + 3:2Ny + 2] .= .-A[:, Ny:-1:1]
            ws.plan2 * ws.ext2
            @views out .= .-imag.(ws.ext2[:, 2:Ny + 1])
            return out
        end
        # cosine derivative along dim1: out = real(FFT(even_ext1(A)))[2:Nx+1] / 2
        function _cuda_cosderiv1!(out, ws::_SpectralCudaWS, A)
            Nx, Ny = ws.Nx, ws.Ny
            CUDA.fill!(ws.ext1, 0)
            @views ws.ext1[2:Nx + 1, :] .= A
            @views ws.ext1[Nx + 3:2Nx + 2, :] .= A[Nx:-1:1, :]
            ws.plan1 * ws.ext1
            @views out .= real.(ws.ext1[2:Nx + 1, :]) ./ 2
            return out
        end
        # cosine derivative along dim2
        function _cuda_cosderiv2!(out, ws::_SpectralCudaWS, A)
            Nx, Ny = ws.Nx, ws.Ny
            CUDA.fill!(ws.ext2, 0)
            @views ws.ext2[:, 2:Ny + 1] .= A
            @views ws.ext2[:, Ny + 3:2Ny + 2] .= A[:, Ny:-1:1]
            ws.plan2 * ws.ext2
            @views out .= real.(ws.ext2[:, 2:Ny + 1]) ./ 2
            return out
        end

        # Field of one directed interaction; writes Exg/Eyg into ws.s1/ws.s2 not
        # used, returns (Exg, Eyg) as fresh device matrices reused via ws buffers.
        function _cuda_spectral_field!(ws::_SpectralCudaWS{T}, sx, sy, Lx, Ly) where {T}
            Nx, Ny = ws.Nx, ws.Ny
            a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1); ns = length(sx)
            _spectral_cuda_setbox!(ws, Float64(a), Float64(b))
            CUDA.fill!(ws.rho, 0)
            threads = 256
            CUDA.@cuda threads=threads blocks=cld(ns, threads) _cuda_spectral_deposit_kernel!(
                ws.rho, sx, sy, T(Lx), T(Ly), T(hx), T(hy), Nx, Ny)
            # rholm = DST2(DST1(rho)) / (a*b*ns) ; philm = -rholm .* G  (store in s1)
            _cuda_dst1!(ws.s2, ws, ws.rho)
            _cuda_dst2!(ws.s1, ws, ws.s2)
            invn = T(ns > 0 ? 1 / (a * b * ns) : 1 / (a * b))
            @. ws.s1 = -(ws.s1 * invn) * ws.G            # philm in s1
            scale = T(_SPECTRAL_FIELD_C0_GRID) * Nx * Ny / (2 * (Nx + 1) * 2 * (Ny + 1))
            # Exg = -scale * cosderiv1( al .* DST2(philm) )
            _cuda_dst2!(ws.s2, ws, ws.s1)
            @. ws.s2 = ws.al * ws.s2
            Exg = CUDA.similar(ws.rho); _cuda_cosderiv1!(Exg, ws, ws.s2); @. Exg = -scale * Exg
            # Eyg = -scale * cosderiv2( DST1(philm) .* bm )
            _cuda_dst1!(ws.s2, ws, ws.s1)
            @. ws.s2 = ws.s2 * ws.bm
            Eyg = CUDA.similar(ws.rho); _cuda_cosderiv2!(Eyg, ws, ws.s2); @. Eyg = -scale * Eyg
            return Exg, Eyg, T(hx), T(hy)
        end

        # --- collide! entry points --------------------------------------------
        collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend}) =
            _cuda_spectral_collide!(solver, beam1, beam2)
        collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend}, ::Nothing) =
            _cuda_spectral_collide!(solver, beam1, beam2)
        collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend}, ::TrackingContext) =
            _cuda_spectral_collide!(solver, beam1, beam2)

        function _cuda_spectral_collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
            solver.method === :grid || throw(ArgumentError(
                "CUDA SpectralPoissonSolver supports method=:grid only; got $(repr(solver.method))"))
            slices1 = _cuda_longitudinal_slices(beam1.rep, solver.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, solver.slicing2)
            kbb1 = _spectral_kbb1(solver, beam1, beam2)
            kbb2 = _spectral_kbb2(solver, beam1, beam2)
            klum = _spectral_luminosity_scale(solver, beam1, beam2)
            lnx, lny = solver.grid
            T = eltype(beam1.rep.x)
            r1 = beam1.rep; r2 = beam2.rep
            Nx, Ny = solver.grid
            ws = _spectral_cuda_ws(T, Nx, Ny)
            Lx, Ly = _cuda_spectral_box(solver, r1, r2)
            n1 = length(slices1.indices); n2 = length(slices2.indices)
            threads = 256
            luminosity = zero(T)
            for (_, i, j) in _slice_collision_order(slices1, slices2)
                idx1 = slices1.indices[i]; idx2 = slices2.indices[j]
                (length(idx1) == 0 || length(idx2) == 0) && continue
                sx1 = r1.x[idx1]; sy1 = r1.y[idx1]
                sx2 = r2.x[idx2]; sy2 = r2.y[idx2]
                # beam1 -> beam2
                Exg, Eyg, hx, hy = _cuda_spectral_field!(ws, sx1, sy1, Lx, Ly)
                a1 = T(slices1.weight[i] * kbb2)
                CUDA.@cuda threads=threads blocks=cld(length(idx2), threads) _cuda_spectral_interp_scatter_kernel!(
                    r2.px, r2.py, idx2, Exg, Eyg, sx2, sy2, T(Lx), T(Ly), hx, hy, Nx, Ny, a1)
                # beam2 -> beam1
                Exg2, Eyg2, hx2, hy2 = _cuda_spectral_field!(ws, sx2, sy2, Lx, Ly)
                a2 = T(slices2.weight[j] * kbb1)
                CUDA.@cuda threads=threads blocks=cld(length(idx1), threads) _cuda_spectral_interp_scatter_kernel!(
                    r1.px, r1.py, idx1, Exg2, Eyg2, sx1, sy1, T(Lx), T(Ly), hx2, hy2, Nx, Ny, a2)
                luminosity += _cuda_spectral_luminosity_pair(sx1, sy1, sx2, sy2, klum, lnx, lny)
            end
            return luminosity
        end

        function _cuda_spectral_box(solver::SpectralPoissonSolver, r1, r2)
            rms(v) = begin n = length(v); m = sum(v) / n; sqrt(sum(abs2, v .- m) / n) end
            ext(v) = maximum(abs, v)
            d = solver.domain_factor
            smax = max(rms(r1.x), rms(r2.x), rms(r1.y), rms(r2.y))
            emax = max(ext(r1.x), ext(r2.x), ext(r1.y), ext(r2.y))
            L = max(d * smax, 1.05 * emax)
            return L, L
        end

        # Density-overlap luminosity on a shared grid (matches the CPU convention).
        function _cuda_spectral_luminosity_pair(x1, y1, x2, y2, klum, nx, ny)
            T = eltype(x1)
            xmin = min(minimum(x1), minimum(x2)); xmax = max(maximum(x1), maximum(x2))
            ymin = min(minimum(y1), minimum(y2)); ymax = max(maximum(y1), maximum(y2))
            width = max(T(xmax - xmin), eps(T)); height = max(T(ymax - ymin), eps(T))
            tx = width / T(nx - 1.1); ty = height / T(ny - 1.1)
            width += T(0.1) * tx; height += T(0.1) * ty
            xmin -= T(0.05) * tx; ymin -= T(0.05) * ty
            hx = width / (nx - 1); hy = height / (ny - 1)
            q1 = CUDA.zeros(T, nx, ny); q2 = CUDA.zeros(T, nx, ny)
            threads = 256
            CUDA.@cuda threads=threads blocks=cld(length(x1), threads) _cuda_spectral_deposit_kernel!(
                q1, x1, y1, T(-xmin + hx), T(-ymin + hy), hx, hy, nx, ny)
            CUDA.@cuda threads=threads blocks=cld(length(x2), threads) _cuda_spectral_deposit_kernel!(
                q2, x2, y2, T(-xmin + hx), T(-ymin + hy), hx, hy, nx, ny)
            lum = sum(q1 .* q2)
            return lum * T(klum) / (hx * hy)
        end

    end  # @eval
end  # if _HAS_CUDA
