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

        function _cuda_spectral_interp_scatter_6d_kernel!(
                x, px, y, py, z, pz, idx,
                PhigL, ExgL, EygL, PhigR, ExgR, EygR,
                center_source, field_lb, field_rb, Lx, Ly, hx, hy, Nx, Ny, a)
            k = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            k <= length(idx) || return nothing
            p = idx[k]
            @inbounds begin
                xv = x[p]; pxv = px[p]
                yv = y[p]; pyv = py[p]
                zv = z[p]; pzv = pz[p]

                s = 0.5 * (zv - center_source)
                xd = xv + s * pxv
                yd = yv + s * pyv
                pzv -= 0.25 * (pxv * pxv + pyv * pyv)

                X = (xd + Lx) / hx
                Y = (yd + Ly) / hy
                i = unsafe_trunc(Int, floor(X))
                j = unsafe_trunc(Int, floor(Y))
                wx = X - i
                wy = Y - j
                phiL = zero(eltype(x)); exL = zero(eltype(x)); eyL = zero(eltype(x))
                phiR = zero(eltype(x)); exR = zero(eltype(x)); eyR = zero(eltype(x))
                if 1 <= i <= Nx && 1 <= j <= Ny
                    c = (1 - wx) * (1 - wy)
                    phiL += c * PhigL[i, j]; exL += c * ExgL[i, j]; eyL += c * EygL[i, j]
                    phiR += c * PhigR[i, j]; exR += c * ExgR[i, j]; eyR += c * EygR[i, j]
                end
                if 1 <= i + 1 <= Nx && 1 <= j <= Ny
                    c = wx * (1 - wy)
                    phiL += c * PhigL[i + 1, j]; exL += c * ExgL[i + 1, j]; eyL += c * EygL[i + 1, j]
                    phiR += c * PhigR[i + 1, j]; exR += c * ExgR[i + 1, j]; eyR += c * EygR[i + 1, j]
                end
                if 1 <= i <= Nx && 1 <= j + 1 <= Ny
                    c = (1 - wx) * wy
                    phiL += c * PhigL[i, j + 1]; exL += c * ExgL[i, j + 1]; eyL += c * EygL[i, j + 1]
                    phiR += c * PhigR[i, j + 1]; exR += c * ExgR[i, j + 1]; eyR += c * EygR[i, j + 1]
                end
                if 1 <= i + 1 <= Nx && 1 <= j + 1 <= Ny
                    c = wx * wy
                    phiL += c * PhigL[i + 1, j + 1]; exL += c * ExgL[i + 1, j + 1]; eyL += c * EygL[i + 1, j + 1]
                    phiR += c * PhigR[i + 1, j + 1]; exR += c * ExgR[i + 1, j + 1]; eyR += c * EygR[i + 1, j + 1]
                end

                denom = field_rb - field_lb
                hzi = (!isfinite(denom) || denom == zero(denom)) ? zero(denom) : inv(denom)
                zbias = hzi == zero(hzi) ? eltype(x)(0.5) : field_rb * hzi
                zL = min(max(-zv * hzi + zbias, zero(eltype(x))), one(eltype(x)))
                zR = one(eltype(x)) - zL
                pxn = pxv + a * (zL * exL + zR * exR)
                pyn = pyv + a * (zL * eyL + zR * eyR)
                pzn = pzv + a * (phiL - phiR) * hzi

                sback = 0.5 * (center_source - zv)
                x[p] = xd + sback * pxn
                y[p] = yd + sback * pyn
                px[p] = pxn
                py[p] = pyn
                pz[p] = pzn + 0.25 * (pxn * pxn + pyn * pyn)
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
            # Real symmetric extensions + their real-FFT (rfft) half-spectra. The DST/DCT
            # are computed from a real FFT of the real odd/even extension: half the FFT
            # cost and half the extension memory traffic of a complex FFT of a complex
            # extension (verified bit-identical to the complex path).
            er1::CUDA.CuMatrix{T}             # (2(Nx+1))×Ny  real ext, dim1
            c1::CUDA.CuMatrix{Complex{T}}     # (Nx+2)×Ny     rfft output, dim1
            er2::CUDA.CuMatrix{T}             # Nx×(2(Ny+1))  real ext, dim2
            c2::CUDA.CuMatrix{Complex{T}}     # Nx×(Ny+2)     rfft output, dim2
            s1::CUDA.CuMatrix{T}; s2::CUDA.CuMatrix{T}; s3::CUDA.CuMatrix{T}   # Nx×Ny scratch
            # Reused left/right potential+field output buffers for the 6D map, so the
            # per-slice-pair field solves allocate nothing.
            PhigL::CUDA.CuMatrix{T}; ExgL::CUDA.CuMatrix{T}; EygL::CUDA.CuMatrix{T}
            PhigR::CUDA.CuMatrix{T}; ExgR::CUDA.CuMatrix{T}; EygR::CUDA.CuMatrix{T}
            pr1::P1; pr2::P2
        end

        function _SpectralCudaWS(::Type{T}, Nx::Int, Ny::Int) where {T}
            er1 = CUDA.zeros(T, 2 * (Nx + 1), Ny)
            er2 = CUDA.zeros(T, Nx, 2 * (Ny + 1))
            c1 = CUDA.zeros(Complex{T}, Nx + 2, Ny)
            c2 = CUDA.zeros(Complex{T}, Nx, Ny + 2)
            pr1 = plan_rfft(er1, 1)
            pr2 = plan_rfft(er2, 2)
            zz() = CUDA.zeros(T, Nx, Ny)
            return _SpectralCudaWS{T,typeof(pr1),typeof(pr2)}(
                Nx, Ny, NaN, NaN,
                CUDA.zeros(T, Nx, 1), CUDA.zeros(T, 1, Ny), zz(),
                zz(), er1, c1, er2, c2,
                zz(), zz(), zz(),
                zz(), zz(), zz(), zz(), zz(), zz(), pr1, pr2)
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

        # Fused symmetric-extension build. The DST/DCT of A along a dimension is
        # computed from a real FFT of A's odd (sign=-1) or even (sign=+1) real extension
        # of length 2(N+1): [0, A[1..N], 0, sign*A[N..1]]. Building the whole extension
        # in one kernel (instead of fill! + two strided copies + a reversed-index copy)
        # removes the transform's dominant overhead. 2D grid indexing (column c =
        # blockIdx().y) avoids a per-thread integer division/modulo.
        function _cuda_ext1_kernel!(ext, A, Nx, Ny, sign)
            r = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            c = CUDA.blockIdx().y
            (r <= 2Nx + 2 && c <= Ny) || return nothing
            @inbounds begin
                v = zero(eltype(A))
                if 2 <= r <= Nx + 1
                    v = A[r - 1, c]
                elseif Nx + 3 <= r <= 2Nx + 2
                    v = sign * A[2Nx + 3 - r, c]
                end
                ext[r, c] = v
            end
            return nothing
        end
        function _cuda_ext2_kernel!(ext, A, Nx, Ny, sign)
            r = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            c = CUDA.blockIdx().y
            (r <= Nx && c <= 2Ny + 2) || return nothing
            @inbounds begin
                v = zero(eltype(A))
                if 2 <= c <= Ny + 1
                    v = A[r, c - 1]
                elseif Ny + 3 <= c <= 2Ny + 2
                    v = sign * A[r, 2Ny + 3 - c]
                end
                ext[r, c] = v
            end
            return nothing
        end

        _cuda_ext1_build!(ws, A, sign) = (CUDA.@cuda threads=256 blocks=(cld(2 * (ws.Nx + 1), 256), ws.Ny) _cuda_ext1_kernel!(ws.er1, A, ws.Nx, ws.Ny, sign))
        _cuda_ext2_build!(ws, A, sign) = (CUDA.@cuda threads=256 blocks=(cld(ws.Nx, 256), 2 * (ws.Ny + 1)) _cuda_ext2_kernel!(ws.er2, A, ws.Nx, ws.Ny, sign))

        # Fused, coalesced extract of the transform result from the interior rows/cols
        # of the rfft half-spectrum: out[r,c] = cim*imag(z) + cre*real(z), with the
        # final field scale folded in (saves a separate scaling kernel per solve and
        # replaces the strided `imag.(c[2:N+1,:])` broadcast with a contiguous write).
        function _cuda_extract1_kernel!(out, c1, Nx, Ny, cim, cre)
            r = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            c = CUDA.blockIdx().y
            (r <= Nx && c <= Ny) || return nothing
            @inbounds begin
                z = c1[r + 1, c]
                out[r, c] = cim * imag(z) + cre * real(z)
            end
            return nothing
        end
        function _cuda_extract2_kernel!(out, c2, Nx, Ny, cim, cre)
            r = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            c = CUDA.blockIdx().y
            (r <= Nx && c <= Ny) || return nothing
            @inbounds begin
                z = c2[r, c + 1]
                out[r, c] = cim * imag(z) + cre * real(z)
            end
            return nothing
        end
        _cuda_extract1!(out, ws, cim, cre) = (CUDA.@cuda threads=256 blocks=(cld(ws.Nx, 256), ws.Ny) _cuda_extract1_kernel!(out, ws.c1, ws.Nx, ws.Ny, cim, cre))
        _cuda_extract2!(out, ws, cim, cre) = (CUDA.@cuda threads=256 blocks=(cld(ws.Nx, 256), ws.Ny) _cuda_extract2_kernel!(out, ws.c2, ws.Nx, ws.Ny, cim, cre))

        # DST-I along dim1: out = scale * (-imag(rfft(odd_ext1(A))))[2:Nx+1]
        function _cuda_dst1!(out, ws::_SpectralCudaWS{T}, A, scale=one(T)) where {T}
            _cuda_ext1_build!(ws, A, -one(T))
            mul!(ws.c1, ws.pr1, ws.er1)
            _cuda_extract1!(out, ws, -scale, zero(T))
            return out
        end
        # DST-I along dim2
        function _cuda_dst2!(out, ws::_SpectralCudaWS{T}, A, scale=one(T)) where {T}
            _cuda_ext2_build!(ws, A, -one(T))
            mul!(ws.c2, ws.pr2, ws.er2)
            _cuda_extract2!(out, ws, -scale, zero(T))
            return out
        end
        # cosine derivative along dim1: out = scale * real(rfft(even_ext1(A)))[2:Nx+1] / 2
        function _cuda_cosderiv1!(out, ws::_SpectralCudaWS{T}, A, scale=one(T)) where {T}
            _cuda_ext1_build!(ws, A, one(T))
            mul!(ws.c1, ws.pr1, ws.er1)
            _cuda_extract1!(out, ws, zero(T), scale * T(0.5))
            return out
        end
        # cosine derivative along dim2
        function _cuda_cosderiv2!(out, ws::_SpectralCudaWS{T}, A, scale=one(T)) where {T}
            _cuda_ext2_build!(ws, A, one(T))
            mul!(ws.c2, ws.pr2, ws.er2)
            _cuda_extract2!(out, ws, zero(T), scale * T(0.5))
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

        # Deposit gathered source-slice particles (contiguous `sx`,`spx`,`sy`,`spy`
        # snapshots) after a virtual drift by `drift`, so the drift is folded into the
        # deposit and the 6D path never allocates a per-plane drifted source array.
        function _cuda_spectral_deposit_drift_kernel!(rho, sx, spx, sy, spy, drift,
                                                      Lx, Ly, hx, hy, Nx, Ny)
            t = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            t <= length(sx) || return nothing
            @inbounds begin
                X = (sx[t] + spx[t] * drift + Lx) / hx
                Y = (sy[t] + spy[t] * drift + Ly) / hy
                i = unsafe_trunc(Int, floor(X)); j = unsafe_trunc(Int, floor(Y))
                wx = X - i; wy = Y - j
                (1 <= i <= Nx   && 1 <= j <= Ny)   && CUDA.@atomic rho[i, j]         += (1 - wx) * (1 - wy)
                (1 <= i + 1 <= Nx && 1 <= j <= Ny) && CUDA.@atomic rho[i + 1, j]     += wx * (1 - wy)
                (1 <= i <= Nx   && 1 <= j + 1 <= Ny) && CUDA.@atomic rho[i, j + 1]   += (1 - wx) * wy
                (1 <= i + 1 <= Nx && 1 <= j + 1 <= Ny) && CUDA.@atomic rho[i + 1, j + 1] += wx * wy
            end
            return nothing
        end

        # Solve one directed field at a single drift plane, writing the potential and
        # transverse fields into the caller-supplied buffers (Phig, Exg, Eyg). Uses 7
        # transforms per solve (down from 8) by reusing DST_x(philm) for both the
        # potential and Ey.
        function _cuda_spectral_potential_solve!(ws::_SpectralCudaWS{T}, Phig, Exg, Eyg,
                                                 sx, spx, sy, spy, drift, Lx, Ly) where {T}
            Nx, Ny = ws.Nx, ws.Ny
            a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1); ns = length(sx)
            _spectral_cuda_setbox!(ws, Float64(a), Float64(b))
            CUDA.fill!(ws.rho, 0)
            threads = 256
            CUDA.@cuda threads=threads blocks=cld(ns, threads) _cuda_spectral_deposit_drift_kernel!(
                ws.rho, sx, spx, sy, spy, T(drift), T(Lx), T(Ly), T(hx), T(hy), Nx, Ny)
            _cuda_dst1!(ws.s2, ws, ws.rho)
            _cuda_dst2!(ws.s1, ws, ws.s2)
            invn = T(ns > 0 ? 1 / (a * b * ns) : 1 / (a * b))
            @. ws.s1 = -(ws.s1 * invn) * ws.G            # philm in s1
            scale = T(_SPECTRAL_FIELD_C0_GRID) * Nx * Ny / (2 * (Nx + 1) * 2 * (Ny + 1))

            # Ux = DST_x(philm) in s3, shared by the potential and Ey.
            _cuda_dst1!(ws.s3, ws, ws.s1)
            # Phig = DST_y(Ux). Factor 1/2: the 2D DST potential reconstruction carries
            # a factor 4 while each field component carries a factor 2 (see the CPU
            # _spectral_field_grid_potential! comment); keep phi = -grad^-1(E). The
            # final scale is folded into each transform's extract (no extra kernel).
            _cuda_dst2!(Phig, ws, ws.s3, T(0.5) * scale)
            # Ey = -scale * cosderiv_y(bm .* Ux)
            @. ws.s2 = ws.s3 * ws.bm
            _cuda_cosderiv2!(Eyg, ws, ws.s2, -scale)
            # Ex = -scale * cosderiv_x(al .* DST_y(philm))
            _cuda_dst2!(ws.s2, ws, ws.s1)
            @. ws.s2 = ws.al * ws.s2
            _cuda_cosderiv1!(Exg, ws, ws.s2, -scale)
            return T(hx), T(hy)
        end

        # --- collide! entry points --------------------------------------------
        collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend}) =
            _cuda_spectral_collide!(solver, beam1, beam2)
        collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend}, ::Nothing) =
            _cuda_spectral_collide!(solver, beam1, beam2)
        collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend}, ::TrackingContext) =
            _cuda_spectral_collide!(solver, beam1, beam2)

        function _cuda_spectral_collide!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
            return solver.longitudinal_kick ?
                _cuda_spectral_collide_longitudinal!(solver, beam1, beam2) :
                _cuda_spectral_collide_transverse!(solver, beam1, beam2)
        end

        function _cuda_spectral_collide_transverse!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
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

        function _cuda_spectral_midpoint_luminosity_pair(sx1, spx1, sy1, spy1, center1,
                                                         sx2, spx2, sy2, spy2, center2,
                                                         klum, nx, ny)
            T = eltype(sx1)
            s1 = T(0.5) * (T(center1) - T(center2))
            s2 = T(0.5) * (T(center2) - T(center1))
            mx1 = sx1 .+ spx1 .* s1
            my1 = sy1 .+ spy1 .* s1
            mx2 = sx2 .+ spx2 .* s2
            my2 = sy2 .+ spy2 .* s2
            return _cuda_spectral_luminosity_pair(mx1, my1, mx2, my2, klum, nx, ny)
        end

        function _cuda_spectral_collision_direction_6d!(
                solver::SpectralPoissonSolver, ws::_SpectralCudaWS{T},
                sx, spx, sy, spy, field_rep, field_idx,
                param_source, param_field, kbb_slice, Lx, Ly) where {T}
            sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
            sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
            hx, hy = _cuda_spectral_potential_solve!(
                ws, ws.PhigL, ws.ExgL, ws.EygL, sx, spx, sy, spy, sL, Lx, Ly)
            _cuda_spectral_potential_solve!(
                ws, ws.PhigR, ws.ExgR, ws.EygR, sx, spx, sy, spy, sR, Lx, Ly)
            Nx, Ny = solver.grid
            threads = 256
            CUDA.@cuda threads=threads blocks=cld(length(field_idx), threads) _cuda_spectral_interp_scatter_6d_kernel!(
                field_rep.x, field_rep.px, field_rep.y, field_rep.py, field_rep.z, field_rep.pz,
                field_idx, ws.PhigL, ws.ExgL, ws.EygL, ws.PhigR, ws.ExgR, ws.EygR,
                T(param_source.center), T(param_field.lb), T(param_field.rb),
                T(Lx), T(Ly), hx, hy, Nx, Ny, T(kbb_slice))
            return nothing
        end

        function _cuda_spectral_collide_longitudinal!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam)
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
            luminosity = zero(T)
            for (_, i, j) in _slice_collision_order(slices1, slices2)
                idx1 = slices1.indices[i]; idx2 = slices2.indices[j]
                (length(idx1) == 0 || length(idx2) == 0) && continue
                param1 = (weight=slices1.weight[i], lb=slices1.boundary[i],
                          center=slices1.center[i], rb=slices1.boundary[i + 1])
                param2 = (weight=slices2.weight[j], lb=slices2.boundary[j],
                          center=slices2.center[j], rb=slices2.boundary[j + 1])
                # Snapshot both source slices before either direction runs (direction 1
                # kicks beam2, direction 2 kicks beam1, so reading from the rep after a
                # kick would corrupt the other direction's source and the luminosity).
                # The drift to each collision plane is folded into the deposit kernel.
                sx1 = r1.x[idx1]; spx1 = r1.px[idx1]; sy1 = r1.y[idx1]; spy1 = r1.py[idx1]
                sx2 = r2.x[idx2]; spx2 = r2.px[idx2]; sy2 = r2.y[idx2]; spy2 = r2.py[idx2]
                _cuda_spectral_collision_direction_6d!(
                    solver, ws, sx1, spx1, sy1, spy1, r2, idx2, param1, param2,
                    slices1.weight[i] * kbb2, Lx, Ly)
                _cuda_spectral_collision_direction_6d!(
                    solver, ws, sx2, spx2, sy2, spy2, r1, idx1, param2, param1,
                    slices2.weight[j] * kbb1, Lx, Ly)
                luminosity += _cuda_spectral_midpoint_luminosity_pair(
                    sx1, spx1, sy1, spy1, param1.center,
                    sx2, spx2, sy2, spy2, param2.center, klum, lnx, lny)
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
