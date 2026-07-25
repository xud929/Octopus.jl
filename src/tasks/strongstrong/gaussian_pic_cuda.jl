#=
CUDA path for GaussianPICPoissonSolver.

Two execution modes reuse the PIC CUDA machinery:

- `batch_mode=:wavefront` (default): the production path. It reuses the PIC
  wavefront batched-FFT field solve unchanged except for one injected step -- the
  erf-integrated Gaussian is subtracted from every charge plane before the FFT
  (via the `gpic_subtract` argument threaded into
  `_cuda_pic_solve_wavefront_fields_batched_fft!`) -- and the kick kernel adds the
  analytic Bassetti-Erskine transverse field plus the covariance/centroid
  longitudinal term. Because it uses the same batched primitives, it inherits the
  wavefront path's CPU/CUDA bit-parity and throughput.
- `batch_mode=:sequential`: a simpler reference path (one slice pair at a time).

The erf node profiles are built on the host (they need only scalar drifted
moments and grid geometry) and uploaded, so no device erf is required;
neutralization needs no device reduction because deposition conserves the slice
count.
=#

if _HAS_CUDA
    @eval begin
        function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                          ::Type{CUDABackend})
            return _cuda_gpic_entry!(solver, beam1, beam2, nothing)
        end
        function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                          ::Type{CUDABackend}, ctx::Nothing)
            return _cuda_gpic_entry!(solver, beam1, beam2, ctx)
        end
        function collide!(solver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                          ::Type{CUDABackend}, ctx::TrackingContext)
            return _cuda_gpic_entry!(solver, beam1, beam2, ctx)
        end

        # The coupled (rotated) subtraction of docs Section 7 exists on the CPU
        # path only. Throw rather than silently running the uncoupled path, which
        # would be a silently ignored non-default request (AGENTS.md).
        function _cuda_gpic_require_uncoupled(solver)
            isfinite(solver.coupling_tol) && throw(ArgumentError(
                "GaussianPICPoissonSolver(coupling_tol=$(solver.coupling_tol)) selects the " *
                "coupled (rotated) Gaussian subtraction. On CUDA this is implemented for " *
                "the default indexed-wavefront route only; the non-indexed wavefront and " *
                "sequential reference paths do not support it. Use the defaults " *
                "(batch_mode=:wavefront, cuda_indexed_wavefront=true), set coupling_tol=Inf, " *
                "or run on CPUThreadsBackend."))
            return nothing
        end

        function _cuda_gpic_entry!(solver, beam1, beam2, ctx)
            workspace = _cuda_pic_workspace(solver.pic, eltype(beam1.rep.x))
            return _cuda_gpic_collide!(solver, beam1, beam2, workspace, ctx)
        end

        function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                         solver::GaussianPICPoissonSolver,
                                         beam1::Beam, beam2::Beam, ::Type{CUDABackend},
                                         ctx::TrackingContext)
            T = eltype(beam1.rep.x)
            workspace = _cuda_pic_workspace!(task.runtime_cache, label, solver.pic, T)
            return Base.ScopedValues.with(_ACTIVE_PIC_TIMING_CONTEXT => (label=label, turn=ctx.turn)) do
                _cuda_gpic_collide!(solver, beam1, beam2, workspace, ctx)
            end
        end

        _strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                        solver::GaussianPICPoissonSolver,
                                        beam1::Beam, beam2::Beam, ::Type{CUDABackend},
                                        ctx::TrackingContext) =
            _strong_strong_collide!(task, label, solver, beam1, beam2, CUDABackend, ctx)

        function _cuda_gpic_collide!(gsolver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                                     workspace, ctx=nothing)
            pic = gsolver.pic
            _validate_pic_solver(pic)
            if Symbol(pic.batch_mode) == :wavefront
                if _cuda_pic_indexed_wavefront_enabled(pic)
                    return _cuda_gpic_collide_wavefront_indexed!(gsolver, beam1, beam2, workspace, ctx)
                end
                return _cuda_gpic_collide_wavefront!(gsolver, beam1, beam2, workspace, ctx)
            end
            return _cuda_gpic_collide_sequential!(gsolver, beam1, beam2, workspace, ctx)
        end

        # -------- indexed wavefront (fastest: no gather/scatter) --------

        function _cuda_gpic_collide_wavefront_indexed!(gsolver::GaussianPICPoissonSolver,
                                                       beam1::Beam, beam2::Beam, workspace, ctx)
            pic = gsolver.pic
            t_slice = time_ns()
            slices1 = _cuda_longitudinal_slices(beam1.rep, pic.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, pic.slicing2)
            batches = collision_pair_batches(slices1, slices2)
            kbb1 = _pic_kbb1(pic, beam1, beam2)
            kbb2 = _pic_kbb2(pic, beam1, beam2)
            klum = _pic_luminosity_scale(pic, beam1, beam2)
            compute_luminosity = _pic_compute_luminosity(pic, ctx)
            luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : eltype(beam1.rep.x)(NaN)
            timing = _cuda_pic_timing_stats()
            _cuda_pic_add_time!(timing, :slicing, t_slice)
            pair_count = 0; batch_count = 0; max_batch = 0
            for batch in batches
                batch_count += 1
                pair_count += length(batch)
                max_batch = max(max_batch, length(batch))
                indexed = Vector{Any}(undef, length(batch))
                for n in eachindex(batch)
                    pair = batch[n]
                    i, j = pair.i, pair.j
                    p1 = (lb=slices1.boundary[i], center=slices1.center[i], rb=slices1.boundary[i + 1])
                    p2 = (lb=slices2.boundary[j], center=slices2.center[j], rb=slices2.boundary[j + 1])
                    indexed[n] = (pair=pair, p1=p1, p2=p2, idx1=slices1.indices[i], idx2=slices2.indices[j])
                end
                t_int = time_ns()
                lum = _cuda_gpic_interaction_wavefront_indexed_batched_fft!(
                    gsolver, indexed, beam1.rep, beam2.rep, kbb1, kbb2, klum, workspace,
                    compute_luminosity, timing,
                )
                _cuda_pic_add_time!(timing, :interaction, t_int)
                compute_luminosity && (luminosity += lum)
            end
            CUDA.synchronize(CUDA.stream())
            _cuda_pic_report_slice_pair_green_cache(workspace.slice_pair_green_cache)
            _cuda_pic_report_wavefront_timing(timing, pair_count, batch_count, max_batch)
            return luminosity
        end

        # Per-slice moments for a wavefront, batched on device (no gather), reusing
        # the soft-Gaussian moment kernels. Returns host sums (10 x 2npairs) and counts.
        function _cuda_gpic_batched_moments(valid, rep1, rep2, coupled::Bool=false)
            T = eltype(rep1.x)
            npairs = length(valid); ncols = 2 * npairs
            nstats = coupled ? 14 : 10
            max_blocks = 1
            for n in 1:npairs
                max_blocks = max(max_blocks,
                    _cuda_gaussian_moment_launch(length(valid[n].idx1)).blocks,
                    _cuda_gaussian_moment_launch(length(valid[n].idx2)).blocks)
            end
            partials = CUDA.zeros(T, nstats, max_blocks, ncols)
            block_counts_host = Vector{Int32}(undef, ncols)
            col_n_host = Vector{Int32}(undef, ncols)
            for n in 1:npairs
                item = valid[n]
                nb1 = coupled ?
                    _cuda_launch_gaussian_moment_partials!(partials, 2n - 1, rep1, item.idx1, Val(true)) :
                    _cuda_launch_gaussian_moment_partials!(partials, 2n - 1, rep1, item.idx1, Val(false))
                nb2 = coupled ?
                    _cuda_launch_gaussian_moment_partials!(partials, 2n, rep2, item.idx2, Val(true)) :
                    _cuda_launch_gaussian_moment_partials!(partials, 2n, rep2, item.idx2, Val(false))
                block_counts_host[2n - 1] = Int32(nb1); block_counts_host[2n] = Int32(nb2)
                col_n_host[2n - 1] = Int32(length(item.idx1)); col_n_host[2n] = Int32(length(item.idx2))
            end
            block_counts = CUDA.CuArray(block_counts_host)
            device_sums = CUDA.zeros(T, nstats, ncols)
            lr = _active_cuda_launch(nstats * ncols)
            CUDA.@cuda threads=lr.threads blocks=lr.blocks _cuda_gaussian_reduce_partials_kernel!(
                device_sums, partials, block_counts, nstats, ncols)
            return Array(device_sums), col_n_host
        end

        @inline function _gpic_mom_from_gaussian(g, n)
            z = zero(g.mx)
            return (n=n, mx=g.mx, mpx=g.mpx, varx=g.sx * g.sx, cxpx=g.covxpx, varpx=g.spx * g.spx,
                    my=g.my, mpy=g.mpy, vary=g.sy * g.sy, cypy=g.covypy, varpy=g.spy * g.spy,
                    cxy=z, cxpy=z, cypx=z, cpxpy=z)
        end

        # Raw moments including the cross-plane terms, from the 14 coupled sums.
        # Layout (see _cuda_gaussian_moment_partials_kernel!):
        #   1..4  sum x, px, y, py      5..8  sum x^2, px^2, y^2, py^2
        #   9,10  sum x*px, y*py        11..14 sum x*y, x*py, px*y, px*py
        function _gpic_mom_from_coupled_sums(sums, n::Integer)
            T = eltype(sums)
            n == 0 && return (n=0, mx=zero(T), mpx=zero(T), varx=zero(T), cxpx=zero(T),
                              varpx=zero(T), my=zero(T), mpy=zero(T), vary=zero(T),
                              cypy=zero(T), varpy=zero(T), cxy=zero(T), cxpy=zero(T),
                              cypx=zero(T), cpxpy=zero(T))
            invn = inv(T(n))
            mx = sums[1] * invn; mpx = sums[2] * invn
            my = sums[3] * invn; mpy = sums[4] * invn
            return (n=n, mx=mx, mpx=mpx,
                    varx=max(sums[5] * invn - mx * mx, zero(T)),
                    cxpx=sums[9] * invn - mx * mpx,
                    varpx=max(sums[6] * invn - mpx * mpx, zero(T)),
                    my=my, mpy=mpy,
                    vary=max(sums[7] * invn - my * my, zero(T)),
                    cypy=sums[10] * invn - my * mpy,
                    varpy=max(sums[8] * invn - mpy * mpy, zero(T)),
                    cxy=sums[11] * invn - mx * my,
                    cxpy=sums[12] * invn - mx * mpy,
                    cypx=sums[13] * invn - my * mpx,
                    cpxpy=sums[14] * invn - mpx * mpy)
        end

        # Enlarge a base prep's source box by the Gaussian margin and re-finish grids.
        function _cuda_gpic_augment_prep(gsolver, prep, mom)
            pic = gsolver.pic
            T = typeof(prep.sL)
            bL = _cuda_gpic_boundary(mom, prep.sL)
            bR = _cuda_gpic_boundary(mom, prep.sR)
            do_gauss = mom.n >= 2 && bL.sigx > 0 && bL.sigy > 0 && bR.sigx > 0 && bR.sigy > 0
            margin = T(gsolver.margin_sigma)
            sb = prep.source_bounds
            sxmin = sb.xmin; sxmax = sb.xmax; symin = sb.ymin; symax = sb.ymax
            if do_gauss && margin > 0
                sxmin = min(sxmin, bL.mux - margin * bL.sigx, bR.mux - margin * bR.sigx)
                sxmax = max(sxmax, bL.mux + margin * bL.sigx, bR.mux + margin * bR.sigx)
                symin = min(symin, bL.muy - margin * bL.sigy, bR.muy - margin * bR.sigy)
                symax = max(symax, bL.muy + margin * bL.sigy, bR.muy + margin * bR.sigy)
            end
            fb = prep.field_bounds
            newprep = _cuda_pic_finish_interaction_indexed(
                pic, T, prep.sL, prep.sR, (sxmin, sxmax, symin, symax),
                (fb.xmin, fb.xmax, fb.ymin, fb.ymax), nothing, nothing)
            return merge(newprep, (bL=bL, bR=bR, mom=mom, do_gauss=do_gauss))
        end

        function _cuda_gpic_interaction_wavefront_indexed_batched_fft!(gsolver, indexed, rep1, rep2,
                                                                       kbb1, kbb2, klum, workspace,
                                                                       compute_luminosity, timing=nothing)
            pic = gsolver.pic
            valid = Any[item for item in indexed if length(item.idx1) > 0 && length(item.idx2) > 0]
            isempty(valid) && return zero(eltype(rep1.x))
            npairs = length(valid); nplanes = 4 * npairs
            nx, ny = pic.grid
            T = eltype(rep1.x)
            wf = _cuda_pic_wavefront_workspace!(workspace, pic, T, nplanes)

            t_prep = time_ns()
            prep12, prep21, luminosity_bounds = _cuda_pic_prepare_interaction_wavefront_indexed!(
                pic, valid, rep1, rep2, nothing, wf, timing, compute_luminosity,
            )
            _cuda_pic_add_time!(timing, :prepare, t_prep)
            want_coupled = isfinite(gsolver.coupling_tol)
            t_mom = time_ns()
            sums_host, col_n = _cuda_gpic_batched_moments(valid, rep1, rep2, want_coupled)
            _cuda_pic_add_time!(timing, :gpic_moments, t_mom)
            for n in 1:npairs
                if want_coupled
                    m1 = _gpic_mom_from_coupled_sums(view(sums_host, :, 2n - 1), Int(col_n[2n - 1]))
                    m2 = _gpic_mom_from_coupled_sums(view(sums_host, :, 2n), Int(col_n[2n]))
                else
                    g1 = _cuda_gaussian_moments_from_sums(view(sums_host, :, 2n - 1), Int(col_n[2n - 1]), false, zero(T), Val(false))
                    g2 = _cuda_gaussian_moments_from_sums(view(sums_host, :, 2n), Int(col_n[2n]), false, zero(T), Val(false))
                    m1 = _gpic_mom_from_gaussian(g1, Int(col_n[2n - 1]))
                    m2 = _gpic_mom_from_gaussian(g2, Int(col_n[2n]))
                end
                prep12[n] = _cuda_gpic_augment_prep(gsolver, prep12[n], m1)
                prep21[n] = _cuda_gpic_augment_prep(gsolver, prep21[n], m2)
            end

            # The slice-pair Green cache must be applied AFTER the augment above:
            # augment recomputes the grid from the margin-enlarged source bounds,
            # so a grid cached before it would simply be discarded. The erf
            # profiles below are then built on the cached (expanded) grid, which
            # is what makes this agree with the CPU.
            use_slice_pair_green = _cuda_pic_slice_pair_green_cache_enabled(pic)
            green12 = nothing
            green21 = nothing
            if use_slice_pair_green
                for n in 1:npairs
                    item = valid[n]
                    prep12[n] = _cuda_pic_slice_pair_cached_prep!(
                        pic, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 1), prep12[n], timing,
                    )
                    prep21[n] = _cuda_pic_slice_pair_cached_prep!(
                        pic, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 2), prep21[n], timing,
                    )
                end
                green12 = Any[prep12[n].green_fft for n in 1:npairs]
                green21 = Any[prep21[n].green_fft for n in 1:npairs]
            end

            t_prof = time_ns()
            gxh = Matrix{T}(undef, nx, nplanes); gyh = Matrix{T}(undef, ny, nplanes)
            amph = Vector{T}(undef, nplanes)
            gtmp_x = Vector{T}(undef, nx); gtmp_y = Vector{T}(undef, ny)
            method = pic.deposit_method
            # Coupled buffers; lamh[p] == 0 marks an uncoupled plane, so a wavefront
            # may legitimately mix coupled and uncoupled slice pairs.
            m1xh = want_coupled ? Matrix{T}(undef, nx, nplanes) : Matrix{T}(undef, 0, 0)
            m2xh = want_coupled ? Matrix{T}(undef, nx, nplanes) : Matrix{T}(undef, 0, 0)
            dgyh = want_coupled ? Matrix{T}(undef, ny, nplanes) : Matrix{T}(undef, 0, 0)
            ddgyh = want_coupled ? Matrix{T}(undef, ny, nplanes) : Matrix{T}(undef, 0, 0)
            lamh = want_coupled ? zeros(T, nplanes) : T[]
            coupled_plane = falses(nplanes)
            tol = T(gsolver.coupling_tol)
            m1t = Vector{T}(undef, nx); m2t = Vector{T}(undef, nx)
            dgt = Vector{T}(undef, ny); ddgt = Vector{T}(undef, ny)
            for n in 1:npairs
                off = 4 * (n - 1)
                for (k, prep, b) in ((1, prep12[n], prep12[n].bL), (2, prep12[n], prep12[n].bR),
                                     (3, prep21[n], prep21[n].bL), (4, prep21[n], prep21[n].bR))
                    x0 = T(prep.source_grid.x0); y0 = T(prep.source_grid.y0)
                    hx = T(prep.source_grid.width) / T(nx - 1); hy = T(prep.source_grid.height) / T(ny - 1)
                    nsrc = k <= 2 ? prep12[n].mom.n : prep21[n].mom.n
                    pc = want_coupled && prep.do_gauss && abs(b.rxy) > tol &&
                         b.a > 0 && b.d > 0 && b.sigc > 0
                    coupled_plane[off + k] = pc
                    if pc
                        _gpic_coupled_profiles!(gtmp_x, m1t, m2t, gtmp_y, dgt, ddgt,
                                                x0, hx, T(b.mux), T(sqrt(b.a)),
                                                y0, hy, T(b.muy), T(b.sigc), method)
                        @views m1xh[:, off + k] .= m1t; @views m2xh[:, off + k] .= m2t
                        @views dgyh[:, off + k] .= dgt; @views ddgyh[:, off + k] .= ddgt
                        lamh[off + k] = T(b.lam)
                        sg = sum(gtmp_x) * sum(gtmp_y) + T(b.lam) * sum(m1t) * sum(dgt) +
                             T(0.5) * T(b.lam)^2 * sum(m2t) * sum(ddgt)
                        amph[off + k] = (gsolver.neutralize && sg != 0) ? T(nsrc) / sg : T(nsrc)
                    else
                        _cuda_gpic_fill_profile!(gtmp_x, gtmp_y, x0, y0, hx, hy, b, method, prep.do_gauss)
                        if want_coupled
                            @views m1xh[:, off + k] .= zero(T); @views m2xh[:, off + k] .= zero(T)
                            @views dgyh[:, off + k] .= zero(T); @views ddgyh[:, off + k] .= zero(T)
                            lamh[off + k] = zero(T)
                        end
                        amph[off + k] = (prep.do_gauss && gsolver.neutralize) ?
                            T(nsrc) / (sum(gtmp_x) * sum(gtmp_y)) : (prep.do_gauss ? T(nsrc) : zero(T))
                    end
                    @views gxh[:, off + k] .= gtmp_x
                    @views gyh[:, off + k] .= gtmp_y
                end
            end
            gx_d = CUDA.CuArray(gxh); gy_d = CUDA.CuArray(gyh); amp_d = CUDA.CuArray(amph)
            gsub = want_coupled ?
                (gx=gx_d, gy=gy_d, amp=amp_d, m1x=CUDA.CuArray(m1xh), m2x=CUDA.CuArray(m2xh),
                 dgy=CUDA.CuArray(dgyh), ddgy=CUDA.CuArray(ddgyh), lam=CUDA.CuArray(lamh)) :
                (gx=gx_d, gy=gy_d, amp=amp_d)

            _cuda_pic_add_time!(timing, :gpic_profiles, t_prof)

            luminosity = zero(T)
            luminosity_task = nothing
            t_lum = time_ns()
            if compute_luminosity && _cuda_pic_async_luminosity_enabled()
                lstream = workspace.luminosity_stream
                luminosity_task = @async CUDA.stream!(lstream) do
                    _cuda_pic_wavefront_luminosity_indexed(pic, valid, rep1, rep2, klum, workspace, nothing, luminosity_bounds)
                end
            elseif compute_luminosity
                luminosity = _cuda_pic_wavefront_luminosity_indexed(pic, valid, rep1, rep2, klum, workspace, nothing, luminosity_bounds)
            end

            _cuda_pic_add_time!(timing, :luminosity, t_lum)

            t_fields = time_ns()
            phi_batch, Ex_batch, Ey_batch = _cuda_pic_solve_wavefront_fields_indexed_batched_fft!(
                pic, valid, rep1, rep2, prep12, prep21, green12, green21, wf, timing;
                gpic_subtract=gsub,
            )
            _cuda_pic_add_time!(timing, :fields, t_fields)

            t_kick = time_ns()
            stream = CUDA.stream()
            for n in 1:npairs
                item = valid[n]; off = 4 * (n - 1)
                p12 = prep12[n]; p21 = prep21[n]
                _cuda_gpic_launch_kick_pair_indexed!(
                    pic, rep1, item.idx1, item.p2.center, item.p1, kbb1, p21.field_grid, p21,
                    rep2, item.idx2, item.p1.center, item.p2, kbb2, p12.field_grid, p12,
                    @view(phi_batch[1:nx, 1:ny, off + 1]), @view(Ex_batch[:, :, off + 1]), @view(Ey_batch[:, :, off + 1]),
                    @view(phi_batch[1:nx, 1:ny, off + 2]), @view(Ex_batch[:, :, off + 2]), @view(Ey_batch[:, :, off + 2]),
                    @view(phi_batch[1:nx, 1:ny, off + 3]), @view(Ex_batch[:, :, off + 3]), @view(Ey_batch[:, :, off + 3]),
                    @view(phi_batch[1:nx, 1:ny, off + 4]), @view(Ex_batch[:, :, off + 4]), @view(Ey_batch[:, :, off + 4]),
                    stream, gsolver.coupling_tol,
                )
            end
            CUDA.synchronize(stream)
            _cuda_pic_add_time!(timing, :kick, t_kick)
            if compute_luminosity && luminosity_task !== nothing
                t_lwait = time_ns()
                luminosity = fetch(luminosity_task)
                CUDA.synchronize(workspace.luminosity_stream)
                _cuda_pic_add_time!(timing, :luminosity, t_lwait)
            end
            return luminosity
        end

        # -------- shared helpers --------

        # Element-wise 10-tuple add (explicit, not broadcast: broadcast over tuples
        # compiles to a slow CUDA reduction; this stays a single fast device sync).
        @inline _gpic_addt(a::NTuple{10}, b::NTuple{10}) =
            (a[1] + b[1], a[2] + b[2], a[3] + b[3], a[4] + b[4], a[5] + b[5],
             a[6] + b[6], a[7] + b[7], a[8] + b[8], a[9] + b[9], a[10] + b[10])

        # Slice transverse moments in a single fused device reduction (one sync).
        function _cuda_gpic_source_moments(source)
            T = eltype(source.x)
            n = length(source.x)
            z = zero(T)
            f = (x, px, y, py) -> (x, px, y, py, x * x, px * px, y * y, py * py, x * px, y * py)
            s = mapreduce(f, _gpic_addt, source.x, source.px, source.y, source.py;
                          init=(z, z, z, z, z, z, z, z, z, z))
            invn = inv(T(n))
            mx = s[1] * invn; mpx = s[2] * invn; my = s[3] * invn; mpy = s[4] * invn
            varx = max(s[5] * invn - mx * mx, z); varpx = max(s[6] * invn - mpx * mpx, z)
            vary = max(s[7] * invn - my * my, z); varpy = max(s[8] * invn - mpy * mpy, z)
            cxpx = s[9] * invn - mx * mpx; cypy = s[10] * invn - my * mpy
            return (n=n, mx=mx, mpx=mpx, varx=varx, cxpx=cxpx, varpx=varpx,
                    my=my, mpy=mpy, vary=vary, cypy=cypy, varpy=varpy)
        end

        # Deep copy of a device slice-coordinate NamedTuple (x,px,y,py,z[,pz]).
        _cuda_gpic_copy_coords(c::NamedTuple) = map(copy, c)

        # Drifted-Gaussian boundary description (centroid, RMS, variance drift rates).
        @inline function _cuda_gpic_boundary(mom, s)
            mux, muy, sigx, sigy = _gpic_drifted_gaussian(mom, s)
            rx = 2 * (mom.cxpx + s * mom.varpx)
            ry = 2 * (mom.cypy + s * mom.varpy)
            # transported full covariance, for the coupling switch (docs Section 7)
            a, b, d, _, _, _ = _gpic_drifted_covariance(mom, s)
            rxy = _gpic_correlation(a, b, d)
            lam = a > 0 ? b / a : zero(b)
            sigc = sqrt(max(d - (a > 0 ? b * b / a : zero(b)), zero(d)))
            return (mux=mux, muy=muy, sigx=sigx, sigy=sigy, rx=rx, ry=ry,
                    a=a, b=b, d=d, rxy=rxy, lam=lam, sigc=sigc)
        end

        # Fill a host erf node profile for a boundary; zeros if the slice is degenerate.
        function _cuda_gpic_fill_profile!(gx, gy, x0, y0, hx, hy, b, method, ok)
            if ok
                _gpic_gaussian_profile!(gx, x0, hx, b.mux, b.sigx, method)
                _gpic_gaussian_profile!(gy, y0, hy, b.muy, b.sigy, method)
            else
                fill!(gx, zero(eltype(gx))); fill!(gy, zero(eltype(gy)))
            end
            return nothing
        end

        # -------- wavefront (production) path --------

        function _cuda_gpic_collide_wavefront!(gsolver::GaussianPICPoissonSolver,
                                               beam1::Beam, beam2::Beam, workspace, ctx)
            pic = gsolver.pic
            _cuda_gpic_require_uncoupled(gsolver)
            slices1 = _cuda_longitudinal_slices(beam1.rep, pic.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, pic.slicing2)
            batches = collision_pair_batches(slices1, slices2)
            kbb1 = _pic_kbb1(pic, beam1, beam2)
            kbb2 = _pic_kbb2(pic, beam1, beam2)
            klum = _pic_luminosity_scale(pic, beam1, beam2)
            compute_luminosity = _pic_compute_luminosity(pic, ctx)
            luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : eltype(beam1.rep.x)(NaN)
            for batch in batches
                gathered = Vector{Any}(undef, length(batch))
                for n in eachindex(batch)
                    pair = batch[n]
                    i, j = pair.i, pair.j
                    p1 = (lb=slices1.boundary[i], center=slices1.center[i], rb=slices1.boundary[i + 1])
                    p2 = (lb=slices2.boundary[j], center=slices2.center[j], rb=slices2.boundary[j + 1])
                    slice1 = _cuda_pic_extract_slice(beam1.rep, slices1.indices[i], pic.longitudinal_kick)
                    slice2 = _cuda_pic_extract_slice(beam2.rep, slices2.indices[j], pic.longitudinal_kick)
                    gathered[n] = (pair=pair, p1=p1, p2=p2, slice1=slice1, slice2=slice2)
                end
                lum = _cuda_gpic_interaction_wavefront_batched_fft!(
                    gsolver, gathered, kbb1, kbb2, klum, workspace, compute_luminosity,
                )
                compute_luminosity && (luminosity += lum)
                for item in gathered
                    (item.slice1 === nothing || item.slice2 === nothing) && continue
                    _cuda_pic_store_slice!(beam1.rep, item.slice1.idx, item.slice1.coords, pic.longitudinal_kick)
                    _cuda_pic_store_slice!(beam2.rep, item.slice2.idx, item.slice2.coords, pic.longitudinal_kick)
                end
            end
            CUDA.synchronize(CUDA.stream())
            return luminosity
        end

        # Margin-aware prepare: bounds (drifted particle extrema unioned with the
        # Gaussian margin), grids, and cached drifted moments for the two boundaries.
        function _cuda_gpic_prepare_interaction(gsolver, source, param_source, field, param_field, mom)
            pic = gsolver.pic
            T = eltype(source.x)
            sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
            sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
            bL = _cuda_gpic_boundary(mom, sL)
            bR = _cuda_gpic_boundary(mom, sR)
            do_gauss = mom.n >= 2 && bL.sigx > 0 && bL.sigy > 0 && bR.sigx > 0 && bR.sigy > 0
            sxmin = T(mapreduce((x, px) -> min(x + px * sL, x + px * sR), min, source.x, source.px))
            sxmax = T(mapreduce((x, px) -> max(x + px * sL, x + px * sR), max, source.x, source.px))
            symin = T(mapreduce((y, py) -> min(y + py * sL, y + py * sR), min, source.y, source.py))
            symax = T(mapreduce((y, py) -> max(y + py * sL, y + py * sR), max, source.y, source.py))
            margin = T(gsolver.margin_sigma)
            if do_gauss && margin > 0
                sxmin = min(sxmin, bL.mux - margin * bL.sigx, bR.mux - margin * bR.sigx)
                sxmax = max(sxmax, bL.mux + margin * bL.sigx, bR.mux + margin * bR.sigx)
                symin = min(symin, bL.muy - margin * bL.sigy, bR.muy - margin * bR.sigy)
                symax = max(symax, bL.muy + margin * bL.sigy, bR.muy + margin * bR.sigy)
            end
            center = T(param_source.center); half = T(0.5)
            fxmin = T(mapreduce((x, px, z) -> x + px * half * (z - center), min, field.x, field.px, field.z))
            fxmax = T(mapreduce((x, px, z) -> x + px * half * (z - center), max, field.x, field.px, field.z))
            fymin = T(mapreduce((y, py, z) -> y + py * half * (z - center), min, field.y, field.py, field.z))
            fymax = T(mapreduce((y, py, z) -> y + py * half * (z - center), max, field.y, field.py, field.z))
            source_grid, field_grid = _pic_interaction_grids(pic, sxmin, sxmax, symin, symax, fxmin, fxmax, fymin, fymax)
            return (sL=sL, sR=sR, source_grid=source_grid, field_grid=field_grid,
                    green_fft=nothing, bL=bL, bR=bR, mom=mom, do_gauss=do_gauss,
                    source_bounds=(xmin=sxmin, xmax=sxmax, ymin=symin, ymax=symax),
                    field_bounds=(xmin=fxmin, xmax=fxmax, ymin=fymin, ymax=fymax))
        end

        function _cuda_gpic_interaction_wavefront_batched_fft!(gsolver, gathered, kbb1, kbb2, klum,
                                                               workspace, compute_luminosity)
            pic = gsolver.pic
            valid = Any[item for item in gathered if item.slice1 !== nothing && item.slice2 !== nothing]
            isempty(valid) && return zero(eltype(workspace.batch_charges))
            npairs = length(valid); nplanes = 4 * npairs
            nx, ny = pic.grid
            T = eltype(valid[1].slice1.coords.x)

            prep12 = Vector{Any}(undef, npairs); prep21 = Vector{Any}(undef, npairs)
            mom1 = Vector{Any}(undef, npairs); mom2 = Vector{Any}(undef, npairs)
            for n in 1:npairs
                item = valid[n]
                mom1[n] = _cuda_gpic_source_moments(item.slice1.coords)
                mom2[n] = _cuda_gpic_source_moments(item.slice2.coords)
                prep12[n] = _cuda_gpic_prepare_interaction(gsolver, item.slice1.coords, item.p1, item.slice2.coords, item.p2, mom1[n])
                prep21[n] = _cuda_gpic_prepare_interaction(gsolver, item.slice2.coords, item.p2, item.slice1.coords, item.p1, mom2[n])
            end

            use_slice_pair_green = _cuda_pic_slice_pair_green_cache_enabled(pic)
            green12 = nothing
            green21 = nothing
            if use_slice_pair_green
                for n in 1:npairs
                    item = valid[n]
                    prep12[n] = _cuda_pic_slice_pair_cached_prep!(
                        pic, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 1), prep12[n], nothing,
                    )
                    prep21[n] = _cuda_pic_slice_pair_cached_prep!(
                        pic, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 2), prep21[n], nothing,
                    )
                end
                green12 = Any[prep12[n].green_fft for n in 1:npairs]
                green21 = Any[prep21[n].green_fft for n in 1:npairs]
            end

            # host-built erf profiles for the 4 planes of each pair, plus amplitudes
            gxh = Matrix{T}(undef, nx, nplanes); gyh = Matrix{T}(undef, ny, nplanes)
            amph = Vector{T}(undef, nplanes)
            gtmp_x = Vector{T}(undef, nx); gtmp_y = Vector{T}(undef, ny)
            method = pic.deposit_method
            for n in 1:npairs
                off = 4 * (n - 1)
                for (k, prep, b) in ((1, prep12[n], prep12[n].bL), (2, prep12[n], prep12[n].bR),
                                     (3, prep21[n], prep21[n].bL), (4, prep21[n], prep21[n].bR))
                    x0 = T(prep.source_grid.x0); y0 = T(prep.source_grid.y0)
                    hx = T(prep.source_grid.width) / T(nx - 1); hy = T(prep.source_grid.height) / T(ny - 1)
                    _cuda_gpic_fill_profile!(gtmp_x, gtmp_y, x0, y0, hx, hy, b, method, prep.do_gauss)
                    @views gxh[:, off + k] .= gtmp_x
                    @views gyh[:, off + k] .= gtmp_y
                    nsrc = (k <= 2 ? prep12[n].mom.n : prep21[n].mom.n)
                    amph[off + k] = (prep.do_gauss && gsolver.neutralize) ?
                        T(nsrc) / (sum(gtmp_x) * sum(gtmp_y)) :
                        (prep.do_gauss ? T(nsrc) : zero(T))
                end
            end
            gx_d = CUDA.CuArray(gxh); gy_d = CUDA.CuArray(gyh); amp_d = CUDA.CuArray(amph)

            # Luminosity overlaps the field solve/kick on a separate stream (as in PIC).
            luminosity = zero(T)
            luminosity_task = nothing
            if compute_luminosity && _cuda_pic_async_luminosity_enabled()
                lstream = workspace.luminosity_stream
                luminosity_task = @async CUDA.stream!(lstream) do
                    _cuda_pic_wavefront_luminosity(pic, valid, klum, workspace, nothing)
                end
            elseif compute_luminosity
                luminosity = _cuda_pic_wavefront_luminosity(pic, valid, klum, workspace, nothing)
            end

            wf = _cuda_pic_wavefront_workspace!(workspace, pic, T, nplanes)
            # green12/green21 = nothing triggers the fused on-device batched Green
            # build inside the solve (the fast PIC path); parity preserved. With
            # the slice-pair cache enabled they carry the cached per-pair Greens.
            phi_batch, Ex_batch, Ey_batch = _cuda_pic_solve_wavefront_fields_batched_fft!(
                pic, valid, prep12, prep21, green12, green21, wf, nothing;
                gpic_subtract=(gx=gx_d, gy=gy_d, amp=amp_d),
            )

            stream = CUDA.stream()
            for n in 1:npairs
                item = valid[n]; off = 4 * (n - 1)
                ns12 = prep12[n].do_gauss ? T(prep12[n].mom.n) : zero(T)
                ns21 = prep21[n].do_gauss ? T(prep21[n].mom.n) : zero(T)
                p12 = prep12[n]; p21 = prep21[n]
                _cuda_gpic_launch_kick!(
                    pic, item.slice2.coords, item.p1.center, item.p2, kbb2, p12.field_grid,
                    @view(phi_batch[1:nx, 1:ny, off + 1]), @view(Ex_batch[:, :, off + 1]), @view(Ey_batch[:, :, off + 1]),
                    @view(phi_batch[1:nx, 1:ny, off + 2]), @view(Ex_batch[:, :, off + 2]), @view(Ey_batch[:, :, off + 2]),
                    ns12, T(p12.mom.mpx), T(p12.mom.mpy),
                    T(p12.bL.sigx), T(p12.bL.sigy), T(p12.bL.mux), T(p12.bL.muy),
                    T(p12.bR.sigx), T(p12.bR.sigy), T(p12.bR.mux), T(p12.bR.muy),
                    T(p12.bL.rx), T(p12.bL.ry), T(p12.bR.rx), T(p12.bR.ry), stream,
                )
                _cuda_gpic_launch_kick!(
                    pic, item.slice1.coords, item.p2.center, item.p1, kbb1, p21.field_grid,
                    @view(phi_batch[1:nx, 1:ny, off + 3]), @view(Ex_batch[:, :, off + 3]), @view(Ey_batch[:, :, off + 3]),
                    @view(phi_batch[1:nx, 1:ny, off + 4]), @view(Ex_batch[:, :, off + 4]), @view(Ey_batch[:, :, off + 4]),
                    ns21, T(p21.mom.mpx), T(p21.mom.mpy),
                    T(p21.bL.sigx), T(p21.bL.sigy), T(p21.bL.mux), T(p21.bL.muy),
                    T(p21.bR.sigx), T(p21.bR.sigy), T(p21.bR.mux), T(p21.bR.muy),
                    T(p21.bL.rx), T(p21.bL.ry), T(p21.bR.rx), T(p21.bR.ry), stream,
                )
            end
            CUDA.synchronize(stream)
            if compute_luminosity && luminosity_task !== nothing
                luminosity = fetch(luminosity_task)
                CUDA.synchronize(workspace.luminosity_stream)
            end
            return luminosity
        end

        # Gaussian-parameter tuple for a prepared direction (isbits, kernel-passable).
        @inline function _cuda_gpic_gtuple(::Type{T}, prep, tol=T(Inf)) where {T}
            # `coupled` is decided per boundary exactly as on the CPU. cmom is the
            # full transverse covariance; the device kick transports it with
            # S = -s and applies the rotated Bassetti-Erskine kick plus the coupled
            # pz terms via _cuda_cp_covariance_kick.
            cpl = isfinite(tol) && prep.do_gauss &&
                  max(abs(prep.bL.rxy), abs(prep.bR.rxy)) > tol &&
                  prep.bL.a > 0 && prep.bL.d > 0 && prep.bR.a > 0 && prep.bR.d > 0
            m = prep.mom
            cmom = StrongTransverseMoments{T,true}(
                T(m.varx), T(m.cxy), T(m.vary),
                T(m.cxpx), T(m.cxpy), T(m.cypx), T(m.cypy),
                T(m.varpx), T(m.cpxpy), T(m.varpy))
            return (ns = prep.do_gauss ? T(prep.mom.n) : zero(T),
                    mpx=T(prep.mom.mpx), mpy=T(prep.mom.mpy),
                    sigxL=T(prep.bL.sigx), sigyL=T(prep.bL.sigy), muxL=T(prep.bL.mux), muyL=T(prep.bL.muy),
                    sigxR=T(prep.bR.sigx), sigyR=T(prep.bR.sigy), muxR=T(prep.bR.mux), muyR=T(prep.bR.muy),
                    rxL=T(prep.bL.rx), ryL=T(prep.bL.ry), rxR=T(prep.bR.rx), ryR=T(prep.bR.ry),
                    coupled=cpl, cmom=cmom, SL=T(-prep.sL), SR=T(-prep.sR))
        end

        function _cuda_gpic_launch_kick_pair_indexed!(
                pic, rep1, idx1, sc1, pf1, kbb1, fg1, prep1,
                rep2, idx2, sc2, pf2, kbb2, fg2, prep2,
                phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R, stream, gtol=Inf)
            T = eltype(rep1.x)
            gtol = T(gtol)
            threads = _cuda_pic_threads(:kick)
            blocks = cld(max(length(idx1), length(idx2)), threads)
            method_code = Symbol(pic.deposit_method) == :CIC ? Int32(1) : Int32(2)
            nx, ny = pic.grid
            hzi1, zbias1 = _slice_interpolation_parameters(T(pf1.lb), T(pf1.rb))
            hzi2, zbias2 = _slice_interpolation_parameters(T(pf2.lb), T(pf2.rb))
            x01 = T(fg1.x0); y01 = T(fg1.y0); hx1 = T(fg1.width) / T(nx - 1); hy1 = T(fg1.height) / T(ny - 1)
            x02 = T(fg2.x0); y02 = T(fg2.y0); hx2 = T(fg2.width) / T(nx - 1); hy2 = T(fg2.height) / T(ny - 1)
            g1 = _cuda_gpic_gtuple(T, prep1, gtol); g2 = _cuda_gpic_gtuple(T, prep2, gtol)
            if pic.longitudinal_kick
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_gpic_kick_pair_indexed_longitudinal_kernel!(
                    rep1.x, rep1.px, rep1.y, rep1.py, rep1.pz, rep1.z, idx1,
                    rep2.x, rep2.px, rep2.y, rep2.py, rep2.pz, rep2.z, idx2,
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                    x01, y01, hx1, hy1, x02, y02, hx2, hy2, Int32(nx), Int32(ny), method_code,
                    T(sc1), hzi1, zbias1, T(kbb1), g1, T(sc2), hzi2, zbias2, T(kbb2), g2,
                )
            else
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_gpic_kick_pair_indexed_kernel!(
                    rep1.x, rep1.px, rep1.y, rep1.py, rep1.z, idx1,
                    rep2.x, rep2.px, rep2.y, rep2.py, rep2.z, idx2,
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                    x01, y01, hx1, hy1, x02, y02, hx2, hy2, Int32(nx), Int32(ny), method_code,
                    T(sc1), hzi1, zbias1, T(kbb1), g1, T(sc2), hzi2, zbias2, T(kbb2), g2,
                )
            end
            return nothing
        end

        @inline function _cuda_gpic_apply_indexed_longitudinal_kick!(
                xarr, pxarr, yarr, pyarr, pzarr, zarr, particle,
                phiL, ExL, EyL, phiR, ExR, EyR, x0, y0, hx, hy, nx::Int32, ny::Int32,
                method_code::Int32, source_center, field_hzi, field_zbias, kbb, g)
            hxi = inv(hx); hyi = inv(hy)
            kick_scale = 2 * kbb
            half_ns = typeof(kbb)(0.5) * g.ns
            kbb_eff = kick_scale * half_ns
            oldx = xarr[particle]; oldpx = pxarr[particle]; oldy = yarr[particle]
            oldpy = pyarr[particle]; oldz = zarr[particle]; oldpz = pzarr[particle]
            s1 = typeof(source_center)(0.5) * (oldz - source_center)
            x = oldx + oldpx * s1; y = oldy + oldpy * s1
            pz = oldpz - typeof(source_center)(0.25) * (oldpx * oldpx + oldpy * oldpy)
            zL = -oldz * field_hzi + field_zbias
            zL = min(max(zL, zero(zL)), one(zL)); zR = one(zL) - zL
            Kx, Ky, Kz = _cuda_pic_interpolate_kick(method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                phiL, ExL, EyL, phiR, ExR, EyR, zL, zR)
            zt = zero(kbb)
            if g.coupled
                _, pxL, _, pyL, _, pzL, _ = _cuda_cp_covariance_kick(
                    g.cmom, kbb_eff, g.SL, x - g.muxL, y - g.muyL, x, zt, y, zt, zt, zt)
                _, pxR, _, pyR, _, pzR, _ = _cuda_cp_covariance_kick(
                    g.cmom, kbb_eff, g.SR, x - g.muxR, y - g.muyR, x, zt, y, zt, zt, zt)
                dpxa = zL * pxL + zR * pxR; dpya = zL * pyL + zR * pyR
                newpx = oldpx + kick_scale * Kx + dpxa
                newpy = oldpy + kick_scale * Ky + dpya
                pz += kick_scale * Kz * field_hzi
                pz += zL * pzL + zR * pzR
            else
            beLx, beLy = _cuda_gaussian_beambeam_kick(g.sigxL, g.sigyL, x - g.muxL, y - g.muyL)
            beRx, beRy = _cuda_gaussian_beambeam_kick(g.sigxR, g.sigyR, x - g.muxR, y - g.muyR)
            Kxa = half_ns * (zL * beLx + zR * beRx); Kya = half_ns * (zL * beLy + zR * beRy)
            dpxa = kick_scale * Kxa; dpya = kick_scale * Kya
            newpx = oldpx + kick_scale * Kx + dpxa
            newpy = oldpy + kick_scale * Ky + dpya
            pz += kick_scale * Kz * field_hzi
            covL = _gpic_cov_pz(kbb_eff, g.sigxL, g.sigyL, x - g.muxL, y - g.muyL, beLx, beLy, g.rxL, g.ryL)
            covR = _gpic_cov_pz(kbb_eff, g.sigxR, g.sigyR, x - g.muxR, y - g.muyR, beRx, beRy, g.rxR, g.ryR)
            pz += zL * covL + zR * covR
            end
            pz += typeof(kbb)(0.5) * (dpxa * g.mpx + dpya * g.mpy)
            s2 = typeof(source_center)(0.5) * (source_center - oldz)
            xarr[particle] = x + s2 * newpx; yarr[particle] = y + s2 * newpy
            pxarr[particle] = newpx; pyarr[particle] = newpy
            pzarr[particle] = pz + typeof(source_center)(0.25) * (newpx * newpx + newpy * newpy)
            return nothing
        end

        @inline function _cuda_gpic_apply_indexed_kick!(
                xarr, pxarr, yarr, pyarr, zarr, particle,
                phiL, ExL, EyL, phiR, ExR, EyR, x0, y0, hx, hy, nx::Int32, ny::Int32,
                method_code::Int32, source_center, field_hzi, field_zbias, kbb, g)
            hxi = inv(hx); hyi = inv(hy)
            half_ns = typeof(kbb)(0.5) * g.ns
            oldx = xarr[particle]; oldpx = pxarr[particle]; oldy = yarr[particle]
            oldpy = pyarr[particle]; oldz = zarr[particle]
            s1 = typeof(source_center)(0.5) * (oldz - source_center)
            x = oldx + oldpx * s1; y = oldy + oldpy * s1
            zL = -oldz * field_hzi + field_zbias
            zL = min(max(zL, zero(zL)), one(zL)); zR = one(zL) - zL
            Kx, Ky = _cuda_pic_interpolate_field(method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                phiL, ExL, EyL, phiR, ExR, EyR, zL, zR)
            if g.coupled
                zt = zero(kbb)
                kbb_eff = 2 * kbb * half_ns
                _, pxL, _, pyL, _, _, _ = _cuda_cp_covariance_kick(
                    g.cmom, kbb_eff, g.SL, x - g.muxL, y - g.muyL, x, zt, y, zt, zt, zt)
                _, pxR, _, pyR, _, _, _ = _cuda_cp_covariance_kick(
                    g.cmom, kbb_eff, g.SR, x - g.muxR, y - g.muyR, x, zt, y, zt, zt, zt)
                newpx = oldpx + 2 * kbb * Kx + (zL * pxL + zR * pxR)
                newpy = oldpy + 2 * kbb * Ky + (zL * pyL + zR * pyR)
            else
            beLx, beLy = _cuda_gaussian_beambeam_kick(g.sigxL, g.sigyL, x - g.muxL, y - g.muyL)
            beRx, beRy = _cuda_gaussian_beambeam_kick(g.sigxR, g.sigyR, x - g.muxR, y - g.muyR)
            Kxa = half_ns * (zL * beLx + zR * beRx); Kya = half_ns * (zL * beLy + zR * beRy)
            newpx = oldpx + 2 * kbb * (Kx + Kxa); newpy = oldpy + 2 * kbb * (Ky + Kya)
            end
            s2 = typeof(source_center)(0.5) * (source_center - oldz)
            xarr[particle] = x + s2 * newpx; yarr[particle] = y + s2 * newpy
            pxarr[particle] = newpx; pyarr[particle] = newpy
            return nothing
        end

        function _cuda_gpic_kick_pair_indexed_longitudinal_kernel!(
                x1, px1, y1, py1, pz1, z1, idx1, x2, px2, y2, py2, pz2, z2, idx2,
                phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                x01, y01, hx1, hy1, x02, y02, hx2, hy2, nx::Int32, ny::Int32, method_code::Int32,
                sc1, hzi1, zbias1, kbb1, g1, sc2, hzi2, zbias2, kbb2, g2)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            if index <= length(idx2)
                _cuda_gpic_apply_indexed_longitudinal_kick!(x2, px2, y2, py2, pz2, z2, idx2[index],
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R, x02, y02, hx2, hy2, nx, ny, method_code,
                    sc2, hzi2, zbias2, kbb2, g2)
            end
            if index <= length(idx1)
                _cuda_gpic_apply_indexed_longitudinal_kick!(x1, px1, y1, py1, pz1, z1, idx1[index],
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R, x01, y01, hx1, hy1, nx, ny, method_code,
                    sc1, hzi1, zbias1, kbb1, g1)
            end
            return nothing
        end

        function _cuda_gpic_kick_pair_indexed_kernel!(
                x1, px1, y1, py1, z1, idx1, x2, px2, y2, py2, z2, idx2,
                phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                x01, y01, hx1, hy1, x02, y02, hx2, hy2, nx::Int32, ny::Int32, method_code::Int32,
                sc1, hzi1, zbias1, kbb1, g1, sc2, hzi2, zbias2, kbb2, g2)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            if index <= length(idx2)
                _cuda_gpic_apply_indexed_kick!(x2, px2, y2, py2, z2, idx2[index],
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R, x02, y02, hx2, hy2, nx, ny, method_code,
                    sc2, hzi2, zbias2, kbb2, g2)
            end
            if index <= length(idx1)
                _cuda_gpic_apply_indexed_kick!(x1, px1, y1, py1, z1, idx1[index],
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R, x01, y01, hx1, hy1, nx, ny, method_code,
                    sc1, hzi1, zbias1, kbb1, g1)
            end
            return nothing
        end

        # Batched subtraction.
        #   uncoupled: charge[i,j,p] -= amp[p] * gx[i,p] * gy[j,p]
        #   coupled  : plus the two conditional-expansion corrections of docs
        #              Section 7.2, lam*M1x(x)dgy(y) and (lam^2/2)*M2x(x)ddgy(y).
        # `lam[p] == 0` marks an uncoupled plane, so a mixed wavefront is fine.
        function _cuda_gpic_subtract_kernel!(charge, gx, gy, amp, nx::Int32, ny::Int32, nplanes::Int32)
            idx = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            total = Int(nx) * Int(ny) * Int(nplanes)
            while idx <= total
                i = (idx - 1) % Int(nx) + 1
                j = ((idx - 1) ÷ Int(nx)) % Int(ny) + 1
                p = (idx - 1) ÷ (Int(nx) * Int(ny)) + 1
                @inbounds charge[i, j, p] -= amp[p] * gx[i, p] * gy[j, p]
                idx += stride
            end
            return nothing
        end

        function _cuda_gpic_subtract_coupled_kernel!(charge, gx, gy, m1x, m2x, dgy, ddgy,
                                                     amp, lam, nx::Int32, ny::Int32, nplanes::Int32)
            idx = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            total = Int(nx) * Int(ny) * Int(nplanes)
            while idx <= total
                i = (idx - 1) % Int(nx) + 1
                j = ((idx - 1) ÷ Int(nx)) % Int(ny) + 1
                p = (idx - 1) ÷ (Int(nx) * Int(ny)) + 1
                @inbounds begin
                    l = lam[p]
                    acc = gx[i, p] * gy[j, p]
                    if l != 0
                        acc += l * m1x[i, p] * dgy[j, p] +
                               typeof(l)(0.5) * l * l * m2x[i, p] * ddgy[j, p]
                    end
                    charge[i, j, p] -= amp[p] * acc
                end
                idx += stride
            end
            return nothing
        end

        # -------- sequential (reference) path --------

        function _cuda_gpic_collide_sequential!(gsolver::GaussianPICPoissonSolver, beam1::Beam, beam2::Beam,
                                                workspace, ctx)
            pic = gsolver.pic
            _cuda_gpic_require_uncoupled(gsolver)
            slices1 = _cuda_longitudinal_slices(beam1.rep, pic.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, pic.slicing2)
            kbb1 = _pic_kbb1(pic, beam1, beam2); kbb2 = _pic_kbb2(pic, beam1, beam2)
            klum = _pic_luminosity_scale(pic, beam1, beam2)
            compute_luminosity = _pic_compute_luminosity(pic, ctx)
            luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : eltype(beam1.rep.x)(NaN)
            for (_, i, j) in _slice_collision_order(slices1, slices2)
                p1 = (lb=slices1.boundary[i], center=slices1.center[i], rb=slices1.boundary[i + 1])
                p2 = (lb=slices2.boundary[j], center=slices2.center[j], rb=slices2.boundary[j + 1])
                slice1 = _cuda_pic_extract_slice(beam1.rep, slices1.indices[i], pic.longitudinal_kick)
                slice2 = _cuda_pic_extract_slice(beam2.rep, slices2.indices[j], pic.longitudinal_kick)
                (slice1 === nothing || slice2 === nothing) && continue
                # Separate source (pre-collision) and field (kicked) buffers so the
                # second direction deposits the UNKICKED opposing slice, matching the
                # CPU/wavefront two-direction semantics.
                field1 = _cuda_gpic_copy_coords(slice1.coords)
                field2 = _cuda_gpic_copy_coords(slice2.coords)
                spc = _cuda_pic_slice_pair_green_cache_enabled(pic) ?
                    workspace.slice_pair_green_cache : nothing
                _cuda_gpic_interaction!(gsolver, slice1.coords, p1, field2, p2, kbb2, workspace.charges[1],
                                        spc, (Int(i), Int(j), 1))
                _cuda_gpic_interaction!(gsolver, slice2.coords, p2, field1, p1, kbb1, workspace.charges[2],
                                        spc, (Int(i), Int(j), 2))
                if compute_luminosity
                    luminosity += _cuda_pic_luminosity(pic, slice1.coords, p1, slice2.coords, p2, klum, workspace)
                end
                _cuda_pic_store_slice!(beam1.rep, slice1.idx, field1, pic.longitudinal_kick)
                _cuda_pic_store_slice!(beam2.rep, slice2.idx, field2, pic.longitudinal_kick)
            end
            CUDA.synchronize(CUDA.stream())
            return luminosity
        end

        function _cuda_gpic_interaction!(gsolver::GaussianPICPoissonSolver, source, param_source,
                                         field, param_field, kbb, charge,
                                         slice_pair_cache=nothing, cache_key=nothing)
            pic = gsolver.pic
            T = eltype(source.x)
            nx, ny = pic.grid
            mom = _cuda_gpic_source_moments(source)
            prep = _cuda_gpic_prepare_interaction(gsolver, source, param_source, field, param_field, mom)
            if !prep.do_gauss
                return _cuda_pic_interaction!(pic, source, param_source, field, param_field, kbb, nothing, charge, nothing)
            end
            if slice_pair_cache !== nothing && cache_key !== nothing
                prep = _cuda_pic_slice_pair_cached_prep!(pic, T, slice_pair_cache, cache_key, prep, nothing)
            end
            sL = prep.sL; sR = prep.sR; bL = prep.bL; bR = prep.bR
            source_grid = prep.source_grid; field_grid = prep.field_grid
            green_fft = prep.green_fft === nothing ?
                _cuda_pic_green_fft(pic, T, source_grid, field_grid, nothing, nothing) : prep.green_fft
            hx = T(source_grid.width) / T(nx - 1); hy = T(source_grid.height) / T(ny - 1)
            gxL = Vector{T}(undef, nx); gyL = Vector{T}(undef, ny)
            gxR = Vector{T}(undef, nx); gyR = Vector{T}(undef, ny)
            _gpic_gaussian_profile!(gxL, T(source_grid.x0), hx, T(bL.mux), T(bL.sigx), pic.deposit_method)
            _gpic_gaussian_profile!(gyL, T(source_grid.y0), hy, T(bL.muy), T(bL.sigy), pic.deposit_method)
            _gpic_gaussian_profile!(gxR, T(source_grid.x0), hx, T(bR.mux), T(bR.sigx), pic.deposit_method)
            _gpic_gaussian_profile!(gyR, T(source_grid.y0), hy, T(bR.muy), T(bR.sigy), pic.deposit_method)
            ampL = gsolver.neutralize ? T(mom.n) / (sum(gxL) * sum(gyL)) : T(mom.n)
            ampR = gsolver.neutralize ? T(mom.n) / (sum(gxR) * sum(gyR)) : T(mom.n)
            gxLd = CUDA.CuArray(gxL); gyLd = CUDA.CuArray(gyL)
            gxRd = CUDA.CuArray(gxR); gyRd = CUDA.CuArray(gyR)
            phiL, ExL, EyL = _cuda_gpic_solve_drifted_field!(pic, source, sL, source_grid, green_fft, gxLd, gyLd, ampL, charge)
            phiR, ExR, EyR = _cuda_gpic_solve_drifted_field!(pic, source, sR, source_grid, green_fft, gxRd, gyRd, ampR, charge)
            _cuda_gpic_launch_kick!(
                pic, field, param_source.center, param_field, kbb, field_grid,
                phiL, ExL, EyL, phiR, ExR, EyR,
                T(mom.n), T(mom.mpx), T(mom.mpy),
                T(bL.sigx), T(bL.sigy), T(bL.mux), T(bL.muy), T(bR.sigx), T(bR.sigy), T(bR.mux), T(bR.muy),
                T(bL.rx), T(bL.ry), T(bR.rx), T(bR.ry), CUDA.stream(),
            )
            return nothing
        end

        function _cuda_gpic_solve_drifted_field!(pic::PICPoissonSolver, source, drift_s,
                                                 source_grid, green_fft, gxd, gyd, amp, charge)
            nx, ny = pic.grid
            T = eltype(source.x)
            hx = T(source_grid.width) / T(nx - 1); hy = T(source_grid.height) / T(ny - 1)
            fill!(charge, zero(T))
            method_code = Symbol(pic.deposit_method) == :CIC ? Int32(1) : Int32(2)
            deposit_threads = _cuda_pic_threads(:deposition)
            blocks = cld(length(source.x), deposit_threads)
            stream = CUDA.stream()
            CUDA.@cuda threads=deposit_threads blocks=blocks stream=stream _cuda_pic_deposit_drifted_nomask_kernel!(
                charge, source.x, source.px, source.y, source.py, T(drift_s),
                T(source_grid.x0), T(source_grid.y0), hx, hy, Int32(nx), Int32(ny), method_code,
            )
            @views charge[1:nx, 1:ny] .-= T(amp) .* gxd .* transpose(gyd)
            phi_pad = real(ifft(fft(charge) .* green_fft))
            phi = phi_pad[1:nx, 1:ny]
            Ex = similar(phi); Ey = similar(phi)
            field_threads = _cuda_pic_threads(:field)
            blocks_grid = cld(nx * ny, field_threads)
            CUDA.@cuda threads=field_threads blocks=blocks_grid stream=stream _cuda_pic_field_kernel!(Ex, Ey, phi, hx, hy, Int32(nx), Int32(ny), _pic_fourth_order(pic))
            return phi, Ex, Ey
        end

        # -------- shared kick launcher + kernels --------

        function _cuda_gpic_launch_kick!(pic::PICPoissonSolver, field, source_center, param_field,
                                         kbb, field_grid, phiL, ExL, EyL, phiR, ExR, EyR,
                                         ns, mpx, mpy, sigxL, sigyL, muxL, muyL,
                                         sigxR, sigyR, muxR, muyR, rxL, ryL, rxR, ryR, stream)
            T = eltype(field.x)
            threads = _cuda_pic_threads(:kick)
            blocks = cld(length(field.x), threads)
            method_code = Symbol(pic.deposit_method) == :CIC ? Int32(1) : Int32(2)
            nx, ny = pic.grid
            hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
            x0 = T(field_grid.x0); y0 = T(field_grid.y0)
            hx = T(field_grid.width) / T(nx - 1); hy = T(field_grid.height) / T(ny - 1)
            if pic.longitudinal_kick
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_gpic_kick_longitudinal_kernel!(
                    field.x, field.px, field.y, field.py, field.pz,
                    field.x, field.px, field.y, field.py, field.z, field.pz,
                    phiL, ExL, EyL, phiR, ExR, EyR, x0, y0, hx, hy, Int32(nx), Int32(ny), method_code,
                    T(source_center), hzi, zbias, T(kbb),
                    ns, mpx, mpy, sigxL, sigyL, muxL, muyL, sigxR, sigyR, muxR, muyR, rxL, ryL, rxR, ryR,
                )
            else
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_gpic_kick_kernel!(
                    field.x, field.px, field.y, field.py,
                    field.x, field.px, field.y, field.py, field.z,
                    phiL, ExL, EyL, phiR, ExR, EyR, x0, y0, hx, hy, Int32(nx), Int32(ny), method_code,
                    T(source_center), hzi, zbias, T(kbb),
                    ns, sigxL, sigyL, muxL, muyL, sigxR, sigyR, muxR, muyR,
                )
            end
            return nothing
        end

        function _cuda_gpic_kick_kernel!(outx, outpx, outy, outpy,
                                         fx, fpx, fy, fpy, fz,
                                         phiL, ExL, EyL, phiR, ExR, EyR,
                                         x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
                                         source_center, field_hzi, field_zbias, kbb,
                                         ns, sigxL, sigyL, muxL, muyL, sigxR, sigyR, muxR, muyR)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx); hyi = inv(hy)
            half_ns = typeof(kbb)(0.5) * ns
            while index <= length(fx)
                s1 = typeof(source_center)(0.5) * (fz[index] - source_center)
                x = fx[index] + fpx[index] * s1
                y = fy[index] + fpy[index] * s1
                zL = -fz[index] * field_hzi + field_zbias
                zL = min(max(zL, zero(zL)), one(zL))
                zR = one(zL) - zL
                Kx, Ky = _cuda_pic_interpolate_field(
                    method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                    phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
                )
                beLx, beLy = _cuda_gaussian_beambeam_kick(sigxL, sigyL, x - muxL, y - muyL)
                beRx, beRy = _cuda_gaussian_beambeam_kick(sigxR, sigyR, x - muxR, y - muyR)
                Kxa = half_ns * (zL * beLx + zR * beRx)
                Kya = half_ns * (zL * beLy + zR * beRy)
                newpx = fpx[index] + 2 * kbb * (Kx + Kxa)
                newpy = fpy[index] + 2 * kbb * (Ky + Kya)
                s2 = typeof(source_center)(0.5) * (source_center - fz[index])
                outx[index] = x + s2 * newpx
                outy[index] = y + s2 * newpy
                outpx[index] = newpx
                outpy[index] = newpy
                index += stride
            end
            return nothing
        end

        function _cuda_gpic_kick_longitudinal_kernel!(outx, outpx, outy, outpy, outpz,
                                                      fx, fpx, fy, fpy, fz, fpz,
                                                      phiL, ExL, EyL, phiR, ExR, EyR,
                                                      x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
                                                      source_center, field_hzi, field_zbias, kbb,
                                                      ns, mpx, mpy, sigxL, sigyL, muxL, muyL,
                                                      sigxR, sigyR, muxR, muyR, rxL, ryL, rxR, ryR)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx); hyi = inv(hy)
            kick_scale = 2 * kbb
            half_ns = typeof(kbb)(0.5) * ns
            kbb_eff = kick_scale * half_ns
            while index <= length(fx)
                oldpx = fpx[index]; oldpy = fpy[index]
                s1 = typeof(source_center)(0.5) * (fz[index] - source_center)
                x = fx[index] + oldpx * s1
                y = fy[index] + oldpy * s1
                pz = fpz[index] - typeof(source_center)(0.25) * (oldpx * oldpx + oldpy * oldpy)
                zL = -fz[index] * field_hzi + field_zbias
                zL = min(max(zL, zero(zL)), one(zL))
                zR = one(zL) - zL
                Kx, Ky, Kz = _cuda_pic_interpolate_kick(
                    method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                    phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
                )
                beLx, beLy = _cuda_gaussian_beambeam_kick(sigxL, sigyL, x - muxL, y - muyL)
                beRx, beRy = _cuda_gaussian_beambeam_kick(sigxR, sigyR, x - muxR, y - muyR)
                Kxa = half_ns * (zL * beLx + zR * beRx)
                Kya = half_ns * (zL * beLy + zR * beRy)
                dpxa = kick_scale * Kxa; dpya = kick_scale * Kya
                newpx = oldpx + kick_scale * Kx + dpxa
                newpy = oldpy + kick_scale * Ky + dpya
                pz += kick_scale * Kz * field_hzi
                covL = _gpic_cov_pz(kbb_eff, sigxL, sigyL, x - muxL, y - muyL, beLx, beLy, rxL, ryL)
                covR = _gpic_cov_pz(kbb_eff, sigxR, sigyR, x - muxR, y - muyR, beRx, beRy, rxR, ryR)
                pz += zL * covL + zR * covR
                pz += typeof(kbb)(0.5) * (dpxa * mpx + dpya * mpy)
                s2 = typeof(source_center)(0.5) * (source_center - fz[index])
                outx[index] = x + s2 * newpx
                outy[index] = y + s2 * newpy
                outpx[index] = newpx
                outpy[index] = newpy
                outpz[index] = pz + typeof(source_center)(0.25) * (newpx * newpx + newpy * newpy)
                index += stride
            end
            return nothing
        end
    end
end
