if _HAS_CUDA
    @eval begin
        function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend})
            workspace = _cuda_pic_workspace(solver, eltype(beam1.rep.x))
            green_cache = _cuda_pic_green_cache(solver, eltype(beam1.rep.x))
            return _cuda_pic_collide!(solver, beam1, beam2, workspace, green_cache, nothing)
        end

        function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend},
                          ctx::Nothing)
            workspace = _cuda_pic_workspace(solver, eltype(beam1.rep.x))
            green_cache = _cuda_pic_green_cache(solver, eltype(beam1.rep.x))
            return _cuda_pic_collide!(solver, beam1, beam2, workspace, green_cache, ctx)
        end

        function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend},
                          ctx::TrackingContext)
            workspace = _cuda_pic_workspace(solver, eltype(beam1.rep.x))
            green_cache = _cuda_pic_green_cache(solver, eltype(beam1.rep.x))
            return _cuda_pic_collide!(solver, beam1, beam2, workspace, green_cache, ctx)
        end

        function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                         solver::PICPoissonSolver,
                                         beam1::Beam, beam2::Beam, ::Type{CUDABackend},
                                         ctx::TrackingContext)
            T = eltype(beam1.rep.x)
            workspace = _cuda_pic_workspace!(task.runtime_cache, label, solver, T)
            green_cache = _cuda_pic_green_cache!(task.runtime_cache, label, solver, T)
            return Base.ScopedValues.with(_ACTIVE_PIC_TIMING_CONTEXT => (label=label, turn=ctx.turn)) do
                _cuda_pic_collide!(solver, beam1, beam2, workspace, green_cache, ctx)
            end
        end

        _strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                        solver::PICPoissonSolver,
                                        beam1::Beam, beam2::Beam, ::Type{CUDABackend},
                                        ctx::TrackingContext) =
            _strong_strong_collide!(task, label, solver, beam1, beam2, CUDABackend, ctx)

        function _cuda_pic_collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam,
                                    workspace, green_cache, ctx=nothing)
            _validate_pic_solver(solver)
            if Symbol(solver.batch_mode) == :wavefront
                return _cuda_pic_collide_wavefront!(solver, beam1, beam2, workspace, green_cache, ctx)
            end
            timing = _cuda_pic_timing_stats()
            t0 = time_ns()
            slices1 = _cuda_longitudinal_slices(beam1.rep, solver.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, solver.slicing2)
            _cuda_pic_add_time!(timing, :slicing, t0)
            kbb1 = _pic_kbb1(solver, beam1, beam2)
            kbb2 = _pic_kbb2(solver, beam1, beam2)
            klum = _pic_luminosity_scale(solver, beam1, beam2)
            compute_luminosity = _pic_compute_luminosity(solver, ctx)
            luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : eltype(beam1.rep.x)(NaN)
            detailed_timing = _cuda_pic_detailed_timing_enabled()
            use_async = _cuda_pic_async_enabled(solver) && !detailed_timing
            use_batch_fft = use_async && _cuda_pic_batch_fft_enabled(solver)
            _record_execution!(:cuda_pic_algorithm, CUDABackend, (
                batch_mode=:sequential,
                cuda_async=use_async,
                cuda_batch_fft=use_batch_fft,
                cuda_wavefront_fft=false,
                cuda_indexed_wavefront=false,
                detailed_timing=detailed_timing,
            ))
            reclaim_policy = _cuda_pic_reclaim_policy()
            pair_count = 0
            for (_, i, j) in _slice_collision_order(slices1, slices2)
                pair_count += 1
                p1 = (lb=slices1.boundary[i], center=slices1.center[i], rb=slices1.boundary[i + 1],
                      include_hi=i == length(slices1.center))
                p2 = (lb=slices2.boundary[j], center=slices2.center[j], rb=slices2.boundary[j + 1],
                      include_hi=j == length(slices2.center))
                gather_range = _cuda_nvtx_push(CUDABackend, "pic gather slices")
                t_gather = time_ns()
                slice1 = _cuda_pic_extract_slice(beam1.rep, slices1.indices[i], solver.longitudinal_kick)
                slice2 = _cuda_pic_extract_slice(beam2.rep, slices2.indices[j], solver.longitudinal_kick)
                _cuda_pic_add_time!(timing, :gather, t_gather)
                _cuda_nvtx_pop(CUDABackend, gather_range)
                (slice1 === nothing || slice2 === nothing) && continue
                pair_range = _cuda_nvtx_push(CUDABackend, "pic slice-pair interaction")
                t_interaction = time_ns()
                if use_batch_fft
                    lum = _cuda_pic_interaction_pair_batched_fft!(
                        solver, slice1.coords, p1, slice2.coords, p2, kbb1, kbb2, green_cache, klum,
                        workspace, timing, compute_luminosity,
                    )
                    compute_luminosity && (luminosity += lum)
                elseif use_async
                    lum = _cuda_pic_interaction_pair_async!(
                        solver, slice1.coords, p1, slice2.coords, p2, kbb1, kbb2, green_cache, klum,
                        workspace, timing, compute_luminosity,
                    )
                    compute_luminosity && (luminosity += lum)
                else
                    _cuda_pic_interaction!(solver, slice1.coords, p1, slice2.coords, p2, kbb2, green_cache, workspace.charges[1], timing)
                    _cuda_pic_interaction!(solver, slice2.coords, p2, slice1.coords, p1, kbb1, green_cache, workspace.charges[2], timing)
                    if compute_luminosity
                        t_luminosity = time_ns()
                        luminosity += _cuda_pic_luminosity(solver, slice1.coords, p1, slice2.coords, p2, klum, workspace)
                        _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
                    end
                end
                _cuda_pic_add_time!(timing, :interaction, t_interaction)
                _cuda_nvtx_pop(CUDABackend, pair_range)
                scatter_range = _cuda_nvtx_push(CUDABackend, "pic scatter slices")
                t_scatter = time_ns()
                _cuda_pic_store_slice!(beam1.rep, slice1.idx, slice1.coords, solver.longitudinal_kick)
                _cuda_pic_store_slice!(beam2.rep, slice2.idx, slice2.coords, solver.longitudinal_kick)
                _cuda_pic_add_time!(timing, :scatter, t_scatter)
                _cuda_nvtx_pop(CUDABackend, scatter_range)
                t_reclaim = time_ns()
                _cuda_pic_maybe_reclaim(pair_count, reclaim_policy)
                _cuda_pic_add_time!(timing, :reclaim, t_reclaim)
            end
            _cuda_pic_reclaim_if_pressure(reclaim_policy)
            _cuda_pic_report_green_cache(green_cache)
            _cuda_pic_report_slice_pair_green_cache(workspace.slice_pair_green_cache)
            _cuda_pic_report_timing(timing, pair_count)
            # Scatter writes are launched on the current stream. Complete them
            # before post-collision tracking starts on independent beam streams.
            CUDA.synchronize(CUDA.stream())
            return luminosity
        end

        function _cuda_pic_collide_wavefront!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam,
                                              workspace, green_cache, ctx=nothing)
            timing = _cuda_pic_timing_stats()
            t0 = time_ns()
            slices1 = _cuda_longitudinal_slices(beam1.rep, solver.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, solver.slicing2)
            batches = collision_pair_batches(slices1, slices2)
            _cuda_pic_add_time!(timing, :slicing, t0)
            kbb1 = _pic_kbb1(solver, beam1, beam2)
            kbb2 = _pic_kbb2(solver, beam1, beam2)
            klum = _pic_luminosity_scale(solver, beam1, beam2)
            compute_luminosity = _pic_compute_luminosity(solver, ctx)
            luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : eltype(beam1.rep.x)(NaN)
            detailed_timing = _cuda_pic_detailed_timing_enabled()
            use_async = _cuda_pic_async_enabled(solver) && !detailed_timing
            use_batch_fft = use_async && _cuda_pic_batch_fft_enabled(solver)
            use_wavefront_fft = use_batch_fft && _cuda_pic_wavefront_fft_enabled(solver)
            reclaim_policy = _cuda_pic_reclaim_policy()
            pair_count = 0
            batch_count = 0
            max_batch_size = 0
            use_indexed_wavefront = _cuda_pic_indexed_wavefront_enabled(solver) &&
                use_wavefront_fft
            _record_execution!(:cuda_pic_algorithm, CUDABackend, (
                batch_mode=:wavefront,
                cuda_async=use_async,
                cuda_batch_fft=use_batch_fft,
                cuda_wavefront_fft=use_wavefront_fft,
                cuda_indexed_wavefront=use_indexed_wavefront,
                detailed_timing=detailed_timing,
            ))
            for batch in batches
                batch_count += 1
                max_batch_size = max(max_batch_size, length(batch))
                if use_indexed_wavefront
                    indexed = Vector{Any}(undef, length(batch))
                    for n in eachindex(batch)
                        pair = batch[n]
                        i, j = pair.i, pair.j
                        p1 = (lb=slices1.boundary[i], center=slices1.center[i], rb=slices1.boundary[i + 1],
                              include_hi=i == length(slices1.center))
                        p2 = (lb=slices2.boundary[j], center=slices2.center[j], rb=slices2.boundary[j + 1],
                              include_hi=j == length(slices2.center))
                        indexed[n] = (pair=pair, p1=p1, p2=p2, idx1=slices1.indices[i], idx2=slices2.indices[j])
                    end
                    pair_count += length(indexed)
                    pair_range = _cuda_nvtx_push(CUDABackend, "pic indexed wavefront interaction")
                    t_interaction = time_ns()
                    lum = _cuda_pic_interaction_wavefront_indexed_batched_fft!(
                        solver, indexed, beam1.rep, beam2.rep, kbb1, kbb2, green_cache, klum,
                        workspace, timing, compute_luminosity,
                    )
                    compute_luminosity && (luminosity += lum)
                    _cuda_pic_add_time!(timing, :interaction, t_interaction)
                    _cuda_nvtx_pop(CUDABackend, pair_range)
                    t_reclaim = time_ns()
                    _cuda_pic_maybe_reclaim(pair_count, reclaim_policy)
                    _cuda_pic_add_time!(timing, :reclaim, t_reclaim)
                    continue
                end
                gathered = Vector{Any}(undef, length(batch))
                gather_range = _cuda_nvtx_push(CUDABackend, "pic gather wavefront")
                t_gather = time_ns()
                for n in eachindex(batch)
                    pair = batch[n]
                    i, j = pair.i, pair.j
                    p1 = (lb=slices1.boundary[i], center=slices1.center[i], rb=slices1.boundary[i + 1],
                          include_hi=i == length(slices1.center))
                    p2 = (lb=slices2.boundary[j], center=slices2.center[j], rb=slices2.boundary[j + 1],
                          include_hi=j == length(slices2.center))
                    slice1 = _cuda_pic_extract_slice(beam1.rep, slices1.indices[i], solver.longitudinal_kick)
                    slice2 = _cuda_pic_extract_slice(beam2.rep, slices2.indices[j], solver.longitudinal_kick)
                    gathered[n] = (pair=pair, p1=p1, p2=p2, slice1=slice1, slice2=slice2)
                end
                _cuda_pic_add_time!(timing, :gather, t_gather)
                _cuda_nvtx_pop(CUDABackend, gather_range)

                if use_wavefront_fft
                    pair_count += length(gathered)
                    pair_range = _cuda_nvtx_push(CUDABackend, "pic wavefront batch interaction")
                    t_interaction = time_ns()
                    lum = _cuda_pic_interaction_wavefront_batched_fft!(
                        solver, gathered, kbb1, kbb2, green_cache, klum, workspace, timing, compute_luminosity,
                    )
                    compute_luminosity && (luminosity += lum)
                    _cuda_pic_add_time!(timing, :interaction, t_interaction)
                    _cuda_nvtx_pop(CUDABackend, pair_range)
                else
                    for item in gathered
                        pair_count += 1
                        (item.slice1 === nothing || item.slice2 === nothing) && continue
                        pair_range = _cuda_nvtx_push(CUDABackend, "pic wavefront pair interaction")
                        t_interaction = time_ns()
                        if use_batch_fft
                            lum = _cuda_pic_interaction_pair_batched_fft!(
                                solver, item.slice1.coords, item.p1, item.slice2.coords, item.p2,
                                kbb1, kbb2, green_cache, klum, workspace, timing, compute_luminosity,
                            )
                            compute_luminosity && (luminosity += lum)
                        elseif use_async
                            lum = _cuda_pic_interaction_pair_async!(
                                solver, item.slice1.coords, item.p1, item.slice2.coords, item.p2,
                                kbb1, kbb2, green_cache, klum, workspace, timing, compute_luminosity,
                            )
                            compute_luminosity && (luminosity += lum)
                        else
                            _cuda_pic_interaction!(
                                solver, item.slice1.coords, item.p1, item.slice2.coords, item.p2,
                                kbb2, green_cache, workspace.charges[1], timing,
                            )
                            _cuda_pic_interaction!(
                                solver, item.slice2.coords, item.p2, item.slice1.coords, item.p1,
                                kbb1, green_cache, workspace.charges[2], timing,
                            )
                            if compute_luminosity
                                t_luminosity = time_ns()
                                luminosity += _cuda_pic_luminosity(
                                    solver, item.slice1.coords, item.p1, item.slice2.coords, item.p2, klum, workspace,
                                )
                                _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
                            end
                        end
                        _cuda_pic_add_time!(timing, :interaction, t_interaction)
                        _cuda_nvtx_pop(CUDABackend, pair_range)
                    end
                end

                scatter_range = _cuda_nvtx_push(CUDABackend, "pic scatter wavefront")
                t_scatter = time_ns()
                for item in gathered
                    item.slice1 === nothing && continue
                    item.slice2 === nothing && continue
                    _cuda_pic_store_slice!(beam1.rep, item.slice1.idx, item.slice1.coords, solver.longitudinal_kick)
                    _cuda_pic_store_slice!(beam2.rep, item.slice2.idx, item.slice2.coords, solver.longitudinal_kick)
                end
                _cuda_pic_add_time!(timing, :scatter, t_scatter)
                _cuda_nvtx_pop(CUDABackend, scatter_range)
                t_reclaim = time_ns()
                _cuda_pic_maybe_reclaim(pair_count, reclaim_policy)
                _cuda_pic_add_time!(timing, :reclaim, t_reclaim)
            end
            _cuda_pic_reclaim_if_pressure(reclaim_policy)
            _cuda_pic_report_green_cache(green_cache)
            _cuda_pic_report_slice_pair_green_cache(workspace.slice_pair_green_cache)
            _cuda_pic_report_wavefront_timing(timing, pair_count, batch_count, max_batch_size)
            # Scatter writes are launched on the current stream. Complete them
            # before post-collision tracking starts on independent beam streams.
            CUDA.synchronize(CUDA.stream())
            return luminosity
        end

        mutable struct _CUDAPICSlicePairGreenEntry{T}
            source_grid::Any
            field_grid::Any
            green_fft::Any
            uses::Int
            rebuilds::Int
        end

        mutable struct _CUDAPICSlicePairGreenCache{T}
            entries::Dict{Tuple{Int,Int,Int},_CUDAPICSlicePairGreenEntry{T}}
            hits::Int
            misses::Int
            rebuilds::Int
        end

        struct _CUDAPICWorkspace{T}
            charges::NTuple{4,Any}
            batch_charges::Any
            batch_Ex::Any
            batch_Ey::Any
            wavefront_cache::Dict{Any,Any}
            slice_pair_green_cache::_CUDAPICSlicePairGreenCache{T}
            luminosity_q1::Any
            luminosity_q2::Any
            field_streams::NTuple{4,Any}
            luminosity_stream::Any
            prep_done::Any
        end

        mutable struct _CUDAPICTimingStats
            slicing::UInt64
            gather::UInt64
            interaction::UInt64
            prepare::UInt64
            prepare_source::UInt64
            prepare_field::UInt64
            prepare_grid::UInt64
            fields::UInt64
            field_deposit::UInt64
            field_green::UInt64
            green_lookup::UInt64
            green_build_kernel::UInt64
            green_build_fft::UInt64
            green_cache_sync::UInt64
            green_cache_insert::UInt64
            field_fft::UInt64
            field_derivative::UInt64
            kick::UInt64
            luminosity::UInt64
            scatter::UInt64
            reclaim::UInt64
        end

        _cuda_pic_timing_enabled() = begin
            diagnostics = _strong_strong_diagnostics()
            diagnostics.pic_timing || diagnostics.pic_timing_detail
        end

        _cuda_pic_detailed_timing_enabled() = _strong_strong_diagnostics().pic_timing_detail

        _cuda_pic_async_enabled(solver::PICPoissonSolver) = solver.cuda_async

        _cuda_pic_batch_fft_enabled(solver::PICPoissonSolver) = solver.cuda_batch_fft

        _cuda_pic_wavefront_fft_enabled(solver::PICPoissonSolver) = solver.cuda_wavefront_fft

        _cuda_pic_wavefront_green_fft_enabled() = true

        _cuda_pic_async_luminosity_enabled() = false

        _cuda_pic_batched_luminosity_enabled() = false

        _cuda_pic_slice_pair_green_cache_enabled(solver::PICPoissonSolver) =
            Symbol(solver.green_cache) == :slice_pair

        _cuda_pic_stack_cached_green_enabled() = true

        const _CUDA_PIC_BOUNDS_PARTIAL_BLOCKS = 64

        _cuda_pic_indexed_wavefront_enabled(solver::PICPoissonSolver) =
            solver.cuda_indexed_wavefront

        function _cuda_pic_timing_stats()
            _cuda_pic_timing_enabled() || return nothing
            return _CUDAPICTimingStats(
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            )
        end

        function _cuda_pic_add_time!(stats::_CUDAPICTimingStats, field::Symbol, t0::UInt64)
            CUDA.synchronize()
            setproperty!(stats, field, getproperty(stats, field) + (time_ns() - t0))
            return nothing
        end
        _cuda_pic_add_time!(::Nothing, field::Symbol, t0::UInt64) = nothing

        function _cuda_pic_add_elapsed!(stats::_CUDAPICTimingStats, field::Symbol, elapsed::UInt64)
            setproperty!(stats, field, getproperty(stats, field) + elapsed)
            return nothing
        end
        _cuda_pic_add_elapsed!(::Nothing, field::Symbol, elapsed::UInt64) = nothing

        function _cuda_pic_report_timing(stats::_CUDAPICTimingStats, pair_count::Integer)
            scale = 1.0e-9
            total = stats.slicing + stats.gather + stats.interaction + stats.scatter + stats.reclaim
            record = (; context=_ACTIVE_PIC_TIMING_CONTEXT[], slice_pairs=Int(pair_count),
                      (field => getproperty(stats, field) * scale for field in fieldnames(_CUDAPICTimingStats))...,
                      measured_total=total * scale)
            sink = _ACTIVE_PIC_PHASE_TIMING_SINK[]
            sink === nothing || push!(sink, record)
            println("CUDA PIC timing profile:")
            println("  slice_pairs = ", pair_count)
            println("  slicing     = ", stats.slicing * scale, " s")
            println("  gather      = ", stats.gather * scale, " s")
            println("  interaction = ", stats.interaction * scale, " s")
            println("    prepare   = ", stats.prepare * scale, " s")
            println("      source  = ", stats.prepare_source * scale, " s")
            println("      field   = ", stats.prepare_field * scale, " s")
            println("      grid    = ", stats.prepare_grid * scale, " s")
            println("    fields    = ", stats.fields * scale, " s")
            println("      deposit = ", stats.field_deposit * scale, " s")
            println("      green   = ", stats.field_green * scale, " s")
            println("        lookup= ", stats.green_lookup * scale, " s")
            println("        build = ", stats.green_build_kernel * scale, " s")
            println("        fft   = ", stats.green_build_fft * scale, " s")
            println("        sync  = ", stats.green_cache_sync * scale, " s")
            println("        insert= ", stats.green_cache_insert * scale, " s")
            println("      fft     = ", stats.field_fft * scale, " s")
            println("      deriv   = ", stats.field_derivative * scale, " s")
            println("    kick      = ", stats.kick * scale, " s")
            println("    luminosity= ", stats.luminosity * scale, " s")
            println("  scatter     = ", stats.scatter * scale, " s")
            println("  reclaim     = ", stats.reclaim * scale, " s")
            println("  measured_total = ", total * scale, " s")
            _cuda_pic_detailed_timing_enabled() || println(
                "  note: field sub-timers are diagnostic only in async mode; " *
                "use StrongStrongDiagnostics(pic_timing_detail=true) for additive field breakdown."
            )
            return nothing
        end
        _cuda_pic_report_timing(::Nothing, pair_count::Integer) = nothing

        function _cuda_pic_report_wavefront_timing(stats::_CUDAPICTimingStats,
                                                   pair_count::Integer,
                                                   batch_count::Integer,
                                                   max_batch_size::Integer)
            _cuda_pic_report_timing(stats, pair_count)
            println("  wavefront_batches = ", batch_count)
            println("  max_batch_size    = ", max_batch_size)
            println("  mean_batch_size   = ", pair_count / max(batch_count, 1))
            return nothing
        end
        _cuda_pic_report_wavefront_timing(::Nothing, pair_count::Integer,
                                          batch_count::Integer,
                                          max_batch_size::Integer) = nothing

        function _cuda_pic_workspace(solver::PICPoissonSolver, ::Type{T}) where {T}
            nx, ny = solver.grid
            lnx, lny = _pic_luminosity_grid(solver)
            charges = ntuple(_ -> CUDA.zeros(T, 2nx, 2ny), 4)
            return _CUDAPICWorkspace{T}(
                charges,
                CUDA.zeros(T, 2nx, 2ny, 4),
                CUDA.zeros(T, nx, ny, 4),
                CUDA.zeros(T, nx, ny, 4),
                Dict{Any,Any}(),
                _CUDAPICSlicePairGreenCache{T}(Dict{Tuple{Int,Int,Int},_CUDAPICSlicePairGreenEntry{T}}(), 0, 0, 0),
                CUDA.zeros(T, lnx + 1, lny + 1),
                CUDA.zeros(T, lnx + 1, lny + 1),
                (CUDA.CuStream(), CUDA.CuStream(), CUDA.CuStream(), CUDA.CuStream()),
                CUDA.CuStream(),
                CUDA.CuEvent(CUDA.EVENT_DISABLE_TIMING),
            )
        end

        function _cuda_pic_workspace!(cache::Dict, label::Symbol,
                                      solver::PICPoissonSolver, ::Type{T}) where {T}
            key = (
                :cuda_pic_workspace,
                label,
                T,
                solver.grid,
                _pic_luminosity_grid(solver),
                Symbol(solver.deposit_method),
                solver.luminosity_deposit_method,
                Symbol(solver.green_type),
                Bool(solver.longitudinal_kick),
                Symbol(solver.batch_mode),
            )
            return get!(cache, key) do
                _cuda_pic_workspace(solver, T)
            end
        end

        function _cuda_pic_green_cache(solver::PICPoissonSolver, ::Type{T}) where {T}
            return nothing
        end

        function _cuda_pic_green_cache!(runtime_cache::Dict, label::Symbol,
                                        solver::PICPoissonSolver, ::Type{T}) where {T}
            return nothing
        end

        function _cuda_pic_report_green_cache(cache)
            return nothing
        end

        function _cuda_pic_report_slice_pair_green_cache(cache::_CUDAPICSlicePairGreenCache)
            isempty(cache.entries) && return nothing
            _strong_strong_diagnostics().cache_stats || return nothing
            total_lookups = cache.hits + cache.misses + cache.rebuilds
            reuse_rate = total_lookups == 0 ? 0.0 : cache.hits / total_lookups
            initial_fill_rate = total_lookups == 0 ? 0.0 : cache.misses / total_lookups
            rebuild_rate = total_lookups == 0 ? 0.0 : cache.rebuilds / total_lookups
            println(
                "CUDA PIC slice-pair Green cache: entries=$(length(cache.entries)), " *
                "hits=$(cache.hits), misses=$(cache.misses), rebuilds=$(cache.rebuilds), " *
                "reuse_rate=$(reuse_rate), initial_fill_rate=$(initial_fill_rate), " *
                "rebuild_rate=$(rebuild_rate)"
            )
            return nothing
        end

        function _cuda_pic_reclaim_policy()
            return (mode=:adaptive, every=0, check_every=16, threshold=0.12)
        end

        function _cuda_pic_maybe_reclaim(pair_count::Integer, policy)
            if policy.mode == :fixed
                policy.every == 0 && return nothing
                pair_count % policy.every == 0 || return nothing
                _cuda_pic_reclaim()
            else
                pair_count % policy.check_every == 0 || return nothing
                _cuda_pic_reclaim_if_pressure(policy)
            end
            return nothing
        end

        function _cuda_pic_reclaim_if_pressure(policy)
            CUDA.free_memory() / CUDA.total_memory() < policy.threshold || return nothing
            _cuda_pic_reclaim()
            return nothing
        end

        function _cuda_pic_reclaim()
            CUDA.synchronize()
            GC.gc(false)
            CUDA.reclaim()
            return nothing
        end

        function _cuda_pic_slice_mask(z, p)
            return p.include_hi ? ((z .>= p.lb) .& (z .<= p.rb)) : ((z .>= p.lb) .& (z .< p.rb))
        end

        function _cuda_pic_extract_slice(rep::Phase6DRep, idx, longitudinal_kick::Bool=false)
            n = length(idx)
            n == 0 && return nothing
            T = eltype(rep.x)
            coords = longitudinal_kick ?
                (
                    x=CUDA.CuArray{T}(undef, n),
                    px=CUDA.CuArray{T}(undef, n),
                    y=CUDA.CuArray{T}(undef, n),
                    py=CUDA.CuArray{T}(undef, n),
                    z=CUDA.CuArray{T}(undef, n),
                    pz=CUDA.CuArray{T}(undef, n),
                ) :
                (
                    x=CUDA.CuArray{T}(undef, n),
                    px=CUDA.CuArray{T}(undef, n),
                    y=CUDA.CuArray{T}(undef, n),
                    py=CUDA.CuArray{T}(undef, n),
                    z=CUDA.CuArray{T}(undef, n),
                )
            threads = _cuda_pic_threads(:gather_scatter)
            if longitudinal_kick
                CUDA.@cuda threads=threads blocks=cld(n, threads) _cuda_pic_gather_slice_longitudinal_kernel!(
                    coords.x, coords.px, coords.y, coords.py, coords.z, coords.pz,
                    rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz, idx,
                )
            else
                CUDA.@cuda threads=threads blocks=cld(n, threads) _cuda_pic_gather_slice_kernel!(
                    coords.x, coords.px, coords.y, coords.py, coords.z,
                    rep.x, rep.px, rep.y, rep.py, rep.z, idx,
                )
            end
            return (idx=idx, coords=coords)
        end

        function _cuda_pic_store_slice!(rep::Phase6DRep, idx, coords, longitudinal_kick::Bool=false)
            n = length(idx)
            threads = _cuda_pic_threads(:gather_scatter)
            if longitudinal_kick
                CUDA.@cuda threads=threads blocks=cld(n, threads) _cuda_pic_scatter_slice_longitudinal_kernel!(
                    rep.x, rep.px, rep.y, rep.py, rep.pz,
                    coords.x, coords.px, coords.y, coords.py, coords.pz, idx,
                )
            else
                CUDA.@cuda threads=threads blocks=cld(n, threads) _cuda_pic_scatter_slice_kernel!(
                    rep.x, rep.px, rep.y, rep.py,
                    coords.x, coords.px, coords.y, coords.py, idx,
                )
            end
            return nothing
        end

        function _cuda_indices_from_mask(mask)
            flags = ifelse.(mask, 1, 0)
            positions = cumsum(flags)
            n = length(mask) == 0 ? 0 : Int(CUDA.@allowscalar positions[end])
            idx = CUDA.CuArray{Int}(undef, n)
            n == 0 && return idx
            threads = _cuda_pic_threads(:gather_scatter)
            CUDA.@cuda threads=threads blocks=cld(length(mask), threads) _cuda_indices_from_mask_kernel!(
                idx, mask, positions,
            )
            return idx
        end

        function _cuda_pic_interaction_pair_async!(solver::PICPoissonSolver,
                                                   old1, p1, old2, p2,
                                                   kbb1, kbb2, green_cache, klum,
                                                   workspace::_CUDAPICWorkspace,
                                                   timing=nothing,
                                                   compute_luminosity::Bool=true)
            prepare_range = _cuda_nvtx_push(CUDABackend, "pic prepare interaction")
            t_prepare = time_ns()
            prep12 = _cuda_pic_prepare_interaction(solver, old1, p1, old2, p2, green_cache, timing)
            prep21 = _cuda_pic_prepare_interaction(solver, old2, p2, old1, p1, green_cache, timing)
            _cuda_pic_add_time!(timing, :prepare, t_prepare)
            _cuda_nvtx_pop(CUDABackend, prepare_range)

            t_green = time_ns()
            green12 = prep12.green_fft === nothing ?
                _cuda_pic_green_fft(solver, eltype(old1.x), prep12.source_grid, prep12.field_grid, green_cache, timing) :
                prep12.green_fft
            green21 = prep21.green_fft === nothing ?
                _cuda_pic_green_fft(solver, eltype(old2.x), prep21.source_grid, prep21.field_grid, green_cache, timing) :
                prep21.green_fft
            _cuda_pic_add_time!(timing, :field_green, t_green)

            streams = workspace.field_streams
            luminosity_stream = workspace.luminosity_stream
            prep_done = workspace.prep_done
            CUDA.record(prep_done, CUDA.stream())
            luminosity_task = if compute_luminosity
                @async CUDA.stream!(luminosity_stream) do
                    CUDA.wait(prep_done, luminosity_stream)
                    lum_range = _cuda_nvtx_push(CUDABackend, "pic luminosity")
                    try
                        _cuda_pic_luminosity(solver, old1, p1, old2, p2, klum, workspace)
                    finally
                        _cuda_nvtx_pop(CUDABackend, lum_range)
                    end
                end
            else
                nothing
            end

            t_fields = time_ns()
            task12L = _cuda_pic_field_task(
                solver, old1, prep12.sL, prep12.source_grid,
                green12, workspace.charges[1], timing, streams[1], prep_done,
                "pic field solve 12 left",
            )
            task21L = _cuda_pic_field_task(
                solver, old2, prep21.sL, prep21.source_grid,
                green21, workspace.charges[3], timing, streams[3], prep_done,
                "pic field solve 21 left",
            )
            task12R = _cuda_pic_field_task(
                solver, old1, prep12.sR, prep12.source_grid,
                green12, workspace.charges[2], timing, streams[2], prep_done,
                "pic field solve 12 right",
            )
            task21R = _cuda_pic_field_task(
                solver, old2, prep21.sR, prep21.source_grid,
                green21, workspace.charges[4], timing, streams[4], prep_done,
                "pic field solve 21 right",
            )
            phi12L, Ex12L, Ey12L = fetch(task12L)
            phi12R, Ex12R, Ey12R = fetch(task12R)
            phi21L, Ex21L, Ey21L = fetch(task21L)
            phi21R, Ex21R, Ey21R = fetch(task21R)
            foreach(CUDA.synchronize, streams)
            _cuda_pic_add_time!(timing, :fields, t_fields)

            kick_range = _cuda_nvtx_push(CUDABackend, "pic kick")
            t_kick = time_ns()
            _cuda_pic_launch_kick!(
                solver, old2, p1.center, p2, old2, kbb2, prep12.field_grid,
                phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R, streams[1],
            )
            _cuda_pic_launch_kick!(
                solver, old1, p2.center, p1, old1, kbb1, prep21.field_grid,
                phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R, streams[3],
            )
            CUDA.synchronize(streams[1])
            CUDA.synchronize(streams[3])
            _cuda_pic_add_time!(timing, :kick, t_kick)
            _cuda_nvtx_pop(CUDABackend, kick_range)
            t_luminosity = time_ns()
            if compute_luminosity
                luminosity = fetch(luminosity_task)
                CUDA.synchronize(luminosity_stream)
                _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
                return luminosity
            end
            return zero(eltype(old1.x))
        end

        function _cuda_pic_interaction_pair_batched_fft!(solver::PICPoissonSolver,
                                                         old1, p1, old2, p2,
                                                         kbb1, kbb2, green_cache, klum,
                                                         workspace::_CUDAPICWorkspace,
                                                         timing=nothing,
                                                         compute_luminosity::Bool=true)
            prepare_range = _cuda_nvtx_push(CUDABackend, "pic prepare interaction")
            t_prepare = time_ns()
            prep12 = _cuda_pic_prepare_interaction(solver, old1, p1, old2, p2, green_cache, timing)
            prep21 = _cuda_pic_prepare_interaction(solver, old2, p2, old1, p1, green_cache, timing)
            _cuda_pic_add_time!(timing, :prepare, t_prepare)
            _cuda_nvtx_pop(CUDABackend, prepare_range)

            t_green = time_ns()
            green12 = prep12.green_fft === nothing ?
                _cuda_pic_green_fft(solver, eltype(old1.x), prep12.source_grid, prep12.field_grid, green_cache, timing) :
                prep12.green_fft
            green21 = prep21.green_fft === nothing ?
                _cuda_pic_green_fft(solver, eltype(old2.x), prep21.source_grid, prep21.field_grid, green_cache, timing) :
                prep21.green_fft
            _cuda_pic_add_time!(timing, :field_green, t_green)

            luminosity_stream = workspace.luminosity_stream
            prep_done = workspace.prep_done
            CUDA.record(prep_done, CUDA.stream())
            luminosity_task = if compute_luminosity
                @async CUDA.stream!(luminosity_stream) do
                    CUDA.wait(prep_done, luminosity_stream)
                    lum_range = _cuda_nvtx_push(CUDABackend, "pic luminosity")
                    try
                        _cuda_pic_luminosity(solver, old1, p1, old2, p2, klum, workspace)
                    finally
                        _cuda_nvtx_pop(CUDABackend, lum_range)
                    end
                end
            else
                nothing
            end

            field_range = _cuda_nvtx_push(CUDABackend, "pic batched field solve")
            t_fields = time_ns()
            phi_batch, Ex_batch, Ey_batch = _cuda_pic_solve_pair_fields_batched_fft!(
                solver, old1, prep12, old2, prep21, green12, green21, workspace, timing,
            )
            _cuda_pic_add_time!(timing, :fields, t_fields)
            _cuda_nvtx_pop(CUDABackend, field_range)

            kick_range = _cuda_nvtx_push(CUDABackend, "pic kick")
            t_kick = time_ns()
            stream = CUDA.stream()
            _cuda_pic_launch_kick!(
                solver, old2, p1.center, p2, old2, kbb2, prep12.field_grid,
                @view(phi_batch[1:size(Ex_batch, 1), 1:size(Ex_batch, 2), 1]),
                @view(Ex_batch[:, :, 1]),
                @view(Ey_batch[:, :, 1]),
                @view(phi_batch[1:size(Ex_batch, 1), 1:size(Ex_batch, 2), 2]),
                @view(Ex_batch[:, :, 2]),
                @view(Ey_batch[:, :, 2]),
                stream,
            )
            _cuda_pic_launch_kick!(
                solver, old1, p2.center, p1, old1, kbb1, prep21.field_grid,
                @view(phi_batch[1:size(Ex_batch, 1), 1:size(Ex_batch, 2), 3]),
                @view(Ex_batch[:, :, 3]),
                @view(Ey_batch[:, :, 3]),
                @view(phi_batch[1:size(Ex_batch, 1), 1:size(Ex_batch, 2), 4]),
                @view(Ex_batch[:, :, 4]),
                @view(Ey_batch[:, :, 4]),
                stream,
            )
            CUDA.synchronize(stream)
            _cuda_pic_add_time!(timing, :kick, t_kick)
            _cuda_nvtx_pop(CUDABackend, kick_range)

            t_luminosity = time_ns()
            if compute_luminosity
                luminosity = fetch(luminosity_task)
                CUDA.synchronize(luminosity_stream)
                _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
                return luminosity
            end
            return zero(eltype(old1.x))
        end

        function _cuda_pic_interaction_wavefront_batched_fft!(solver::PICPoissonSolver,
                                                              gathered,
                                                              kbb1, kbb2, green_cache, klum,
                                                              workspace::_CUDAPICWorkspace,
                                                              timing=nothing,
                                                              compute_luminosity::Bool=true)
            valid = Any[item for item in gathered if item.slice1 !== nothing && item.slice2 !== nothing]
            isempty(valid) && return zero(eltype(workspace.batch_charges))
            npairs = length(valid)
            nplanes = 4 * npairs
            T = eltype(valid[1].slice1.coords.x)

            prepare_range = _cuda_nvtx_push(CUDABackend, "pic wavefront prepare")
            t_prepare = time_ns()
            prep12 = Vector{Any}(undef, npairs)
            prep21 = Vector{Any}(undef, npairs)
            for n in 1:npairs
                item = valid[n]
                prep12[n] = _cuda_pic_prepare_interaction(
                    solver, item.slice1.coords, item.p1, item.slice2.coords, item.p2, green_cache, timing,
                )
                prep21[n] = _cuda_pic_prepare_interaction(
                    solver, item.slice2.coords, item.p2, item.slice1.coords, item.p1, green_cache, timing,
                )
                if green_cache === nothing && _cuda_pic_slice_pair_green_cache_enabled(solver)
                    prep12[n] = _cuda_pic_slice_pair_cached_prep!(
                        solver, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 1), prep12[n], timing,
                    )
                    prep21[n] = _cuda_pic_slice_pair_cached_prep!(
                        solver, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 2), prep21[n], timing,
                    )
                end
            end
            _cuda_pic_add_time!(timing, :prepare, t_prepare)
            _cuda_nvtx_pop(CUDABackend, prepare_range)

            luminosity = zero(T)
            luminosity_task = nothing
            if compute_luminosity && _cuda_pic_async_luminosity_enabled()
                luminosity_stream = workspace.luminosity_stream
                luminosity_task = @async CUDA.stream!(luminosity_stream) do
                    lum_range = _cuda_nvtx_push(CUDABackend, "pic wavefront luminosity")
                    try
                        _cuda_pic_wavefront_luminosity(solver, valid, klum, workspace, timing)
                    finally
                        _cuda_nvtx_pop(CUDABackend, lum_range)
                    end
                end
            elseif compute_luminosity
                luminosity = _cuda_pic_wavefront_luminosity(solver, valid, klum, workspace, timing)
            end

            use_slice_pair_green = green_cache === nothing && _cuda_pic_slice_pair_green_cache_enabled(solver)
            use_fused_green = green_cache === nothing && !use_slice_pair_green && _cuda_pic_wavefront_green_fft_enabled()
            green12 = nothing
            green21 = nothing
            if !use_fused_green
                t_green = time_ns()
                green12 = Vector{Any}(undef, npairs)
                green21 = Vector{Any}(undef, npairs)
                for n in 1:npairs
                    item = valid[n]
                    green12[n] = prep12[n].green_fft === nothing ?
                        _cuda_pic_green_fft(solver, T, prep12[n].source_grid, prep12[n].field_grid, green_cache, timing) :
                        prep12[n].green_fft
                    green21[n] = prep21[n].green_fft === nothing ?
                        _cuda_pic_green_fft(solver, T, prep21[n].source_grid, prep21[n].field_grid, green_cache, timing) :
                        prep21[n].green_fft
                end
                _cuda_pic_add_time!(timing, :field_green, t_green)
            end

            field_range = _cuda_nvtx_push(CUDABackend, "pic wavefront batched field solve")
            t_fields = time_ns()
            wf = _cuda_pic_wavefront_workspace!(workspace, solver, T, nplanes)
            phi_batch, Ex_batch, Ey_batch = _cuda_pic_solve_wavefront_fields_batched_fft!(
                solver, valid, prep12, prep21, green12, green21, wf, timing,
            )
            _cuda_pic_add_time!(timing, :fields, t_fields)
            _cuda_nvtx_pop(CUDABackend, field_range)

            kick_range = _cuda_nvtx_push(CUDABackend, "pic wavefront kicks")
            t_kick = time_ns()
            stream = CUDA.stream()
            nx, ny = solver.grid
            for n in 1:npairs
                item = valid[n]
                offset = 4 * (n - 1)
                _cuda_pic_launch_kick!(
                    solver, item.slice2.coords, item.p1.center, item.p2, item.slice2.coords,
                    kbb2, prep12[n].field_grid,
                    @view(phi_batch[1:nx, 1:ny, offset + 1]),
                    @view(Ex_batch[:, :, offset + 1]),
                    @view(Ey_batch[:, :, offset + 1]),
                    @view(phi_batch[1:nx, 1:ny, offset + 2]),
                    @view(Ex_batch[:, :, offset + 2]),
                    @view(Ey_batch[:, :, offset + 2]),
                    stream,
                )
                _cuda_pic_launch_kick!(
                    solver, item.slice1.coords, item.p2.center, item.p1, item.slice1.coords,
                    kbb1, prep21[n].field_grid,
                    @view(phi_batch[1:nx, 1:ny, offset + 3]),
                    @view(Ex_batch[:, :, offset + 3]),
                    @view(Ey_batch[:, :, offset + 3]),
                    @view(phi_batch[1:nx, 1:ny, offset + 4]),
                    @view(Ex_batch[:, :, offset + 4]),
                    @view(Ey_batch[:, :, offset + 4]),
                    stream,
                )
            end
            CUDA.synchronize(stream)
            _cuda_pic_add_time!(timing, :kick, t_kick)
            _cuda_nvtx_pop(CUDABackend, kick_range)
            if compute_luminosity && luminosity_task !== nothing
                luminosity = fetch(luminosity_task)
                CUDA.synchronize(workspace.luminosity_stream)
            end
            return luminosity
        end

        function _cuda_gaussian_collide_wavefront!(
                solver::GaussianPoissonSolver{ST,D,COUPLED,LONGITUDINAL}, beam1::Beam,
                beam2::Beam) where {ST,D,COUPLED,LONGITUDINAL}
            slices1 = _cuda_longitudinal_slices(beam1.rep, solver.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, solver.slicing2)
            batches = collision_pair_batches(slices1, slices2)
            kbb1 = _strong_strong_kbb1(solver, beam1, beam2)
            kbb2 = _strong_strong_kbb2(solver, beam1, beam2)
            klum1, klum2 = _strong_strong_luminosity_scales(solver, beam1, beam2)
            T = eltype(beam1.rep.x)
            sample_beam1 = solver.gaussian_when_luminosity == 1
            all_indices = Iterators.flatten((slices1.indices, slices2.indices))
            max_moment_blocks = maximum(
                idx -> _cuda_gaussian_moment_launch(length(idx)).blocks,
                all_indices; init=1)
            max_batch = maximum(length, batches; init=1)
            nstats = COUPLED ? 14 : 10
            partials = CUDA.zeros(T, nstats, max_moment_blocks, 2 * max_batch)
            device_sums = CUDA.CuArray{T}(undef, nstats, 2 * max_batch)
            block_counts = CUDA.CuArray{Int32}(undef, 2 * max_batch)
            host_block_counts = Vector{Int32}(undef, 2 * max_batch)
            max_lum = maximum(batches; init=0) do batch
                sum(pair -> sample_beam1 ? length(slices2.indices[pair.j]) :
                                           length(slices1.indices[pair.i]), batch)
            end
            lum = CUDA.CuArray{T}(undef, max(max_lum, 1))
            luminosity = zero(T)
            _record_execution!(:cuda_gaussian_algorithm, CUDABackend, (
                batch_mode=:wavefront, include_sigma_xy=COUPLED,
                virtual_drift=typeof(solver.virtual_drift),
            ))

            for batch in batches
                for (column, pair) in enumerate(batch)
                    idx1 = slices1.indices[pair.i]
                    idx2 = slices2.indices[pair.j]
                    host_block_counts[column] = Int32(_cuda_launch_gaussian_moment_partials!(
                        partials, column, beam1.rep, idx1, Val(COUPLED))
                    )
                    column2 = length(batch) + column
                    host_block_counts[column2] = Int32(_cuda_launch_gaussian_moment_partials!(
                        partials, column2, beam2.rep, idx2, Val(COUPLED))
                    )
                end
                ncolumns = 2 * length(batch)
                copyto!(block_counts, 1, host_block_counts, 1, ncolumns)
                launch_reduce = _active_cuda_launch(nstats * ncolumns)
                CUDA.@cuda threads=launch_reduce.threads blocks=launch_reduce.blocks _cuda_gaussian_reduce_partials_kernel!(
                        device_sums, partials, block_counts, nstats, ncolumns)
                host_sums = Array(@view device_sums[:, 1:ncolumns])

                moments1 = Vector{Any}(undef, length(batch))
                moments2 = Vector{Any}(undef, length(batch))
                for (column, pair) in enumerate(batch)
                    moments1[column] = _cuda_gaussian_moments_from_sums(
                        @view(host_sums[:, column]), length(slices1.indices[pair.i]),
                        solver.ignore_centroid1, solver.min_sigma, Val(COUPLED))
                    moments2[column] = _cuda_gaussian_moments_from_sums(
                        @view(host_sums[:, length(batch) + column]),
                        length(slices2.indices[pair.j]), solver.ignore_centroid2,
                        solver.min_sigma, Val(COUPLED))
                end

                lum_offset = 0
                for (column, pair) in enumerate(batch)
                    idx1 = slices1.indices[pair.i]
                    idx2 = slices2.indices[pair.j]
                    launch1 = _active_cuda_launch(length(idx1))
                    launch2 = _active_cuda_launch(length(idx2))
                    offset1 = sample_beam1 ? 0 : lum_offset
                    offset2 = sample_beam1 ? lum_offset : 0
                    scale1 = sample_beam1 ? one(T) :
                        slices2.weight[pair.j] * klum1 / TWOPI
                    scale2 = sample_beam1 ?
                        slices1.weight[pair.i] * klum2 / TWOPI : one(T)
                    CUDA.@cuda threads=launch1.threads blocks=launch1.blocks _cuda_slice_kick_kernel!(
                            beam1.rep, idx1, lum, moments2[column], slices2.center[pair.j],
                            slices2.weight[pair.j] * kbb1, solver.virtual_drift,
                            Val(LONGITUDINAL), Val(!sample_beam1),
                            offset1, scale1)
                    CUDA.@cuda threads=launch2.threads blocks=launch2.blocks _cuda_slice_kick_kernel!(
                            beam2.rep, idx2, lum, moments1[column], slices1.center[pair.i],
                            slices1.weight[pair.i] * kbb2, solver.virtual_drift,
                            Val(LONGITUDINAL), Val(sample_beam1),
                            offset2, scale2)
                    if sample_beam1
                        lum_offset += length(idx2)
                    else
                        lum_offset += length(idx1)
                    end
                end
                lum_offset > 0 && (luminosity += sum(@view lum[1:lum_offset]))
            end
            return luminosity
        end

        function _cuda_pic_interaction_wavefront_indexed_batched_fft!(solver::PICPoissonSolver,
                                                                      indexed,
                                                                      rep1, rep2,
                                                                      kbb1, kbb2, green_cache, klum,
                                                                      workspace::_CUDAPICWorkspace,
                                                                      timing=nothing,
                                                                      compute_luminosity::Bool=true)
            valid = Any[item for item in indexed if length(item.idx1) > 0 && length(item.idx2) > 0]
            isempty(valid) && return zero(eltype(rep1.x))
            npairs = length(valid)
            nplanes = 4 * npairs
            T = eltype(rep1.x)
            wf = _cuda_pic_wavefront_workspace!(workspace, solver, T, nplanes)

            prepare_range = _cuda_nvtx_push(CUDABackend, "pic indexed wavefront prepare")
            t_prepare = time_ns()
            prep12, prep21, luminosity_bounds = _cuda_pic_prepare_interaction_wavefront_indexed!(
                solver, valid, rep1, rep2, green_cache, wf, timing, compute_luminosity,
            )
            for n in 1:npairs
                item = valid[n]
                if green_cache === nothing && _cuda_pic_slice_pair_green_cache_enabled(solver)
                    prep12[n] = _cuda_pic_slice_pair_cached_prep!(
                        solver, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 1), prep12[n], timing,
                    )
                    prep21[n] = _cuda_pic_slice_pair_cached_prep!(
                        solver, T, workspace.slice_pair_green_cache,
                        (Int(item.pair.i), Int(item.pair.j), 2), prep21[n], timing,
                    )
                end
            end
            _cuda_pic_add_time!(timing, :prepare, t_prepare)
            _cuda_nvtx_pop(CUDABackend, prepare_range)

            luminosity = compute_luminosity ?
                _cuda_pic_wavefront_luminosity_indexed(
                    solver, valid, rep1, rep2, klum, workspace, timing, luminosity_bounds,
                ) :
                zero(T)

            use_slice_pair_green = green_cache === nothing && _cuda_pic_slice_pair_green_cache_enabled(solver)
            use_fused_green = green_cache === nothing && !use_slice_pair_green && _cuda_pic_wavefront_green_fft_enabled()
            green12 = nothing
            green21 = nothing
            if !use_fused_green
                t_green = time_ns()
                green12 = Vector{Any}(undef, npairs)
                green21 = Vector{Any}(undef, npairs)
                for n in 1:npairs
                    green12[n] = prep12[n].green_fft === nothing ?
                        _cuda_pic_green_fft(solver, T, prep12[n].source_grid, prep12[n].field_grid, green_cache, timing) :
                        prep12[n].green_fft
                    green21[n] = prep21[n].green_fft === nothing ?
                        _cuda_pic_green_fft(solver, T, prep21[n].source_grid, prep21[n].field_grid, green_cache, timing) :
                        prep21[n].green_fft
                end
                _cuda_pic_add_time!(timing, :field_green, t_green)
            end

            field_range = _cuda_nvtx_push(CUDABackend, "pic indexed wavefront field solve")
            t_fields = time_ns()
            phi_batch, Ex_batch, Ey_batch = _cuda_pic_solve_wavefront_fields_indexed_batched_fft!(
                solver, valid, rep1, rep2, prep12, prep21, green12, green21, wf, timing,
            )
            _cuda_pic_add_time!(timing, :fields, t_fields)
            _cuda_nvtx_pop(CUDABackend, field_range)

            kick_range = _cuda_nvtx_push(CUDABackend, "pic indexed wavefront kicks")
            t_kick = time_ns()
            stream = CUDA.stream()
            nx, ny = solver.grid
            for n in 1:npairs
                item = valid[n]
                offset = 4 * (n - 1)
                _cuda_pic_launch_kick_pair_indexed!(
                    solver,
                    rep1, item.idx1, item.p2.center, item.p1, kbb1, prep21[n].field_grid,
                    rep2, item.idx2, item.p1.center, item.p2, kbb2, prep12[n].field_grid,
                    @view(phi_batch[1:nx, 1:ny, offset + 1]),
                    @view(Ex_batch[:, :, offset + 1]),
                    @view(Ey_batch[:, :, offset + 1]),
                    @view(phi_batch[1:nx, 1:ny, offset + 2]),
                    @view(Ex_batch[:, :, offset + 2]),
                    @view(Ey_batch[:, :, offset + 2]),
                    @view(phi_batch[1:nx, 1:ny, offset + 3]),
                    @view(Ex_batch[:, :, offset + 3]),
                    @view(Ey_batch[:, :, offset + 3]),
                    @view(phi_batch[1:nx, 1:ny, offset + 4]),
                    @view(Ex_batch[:, :, offset + 4]),
                    @view(Ey_batch[:, :, offset + 4]),
                    stream,
                )
            end
            CUDA.synchronize(stream)
            _cuda_pic_add_time!(timing, :kick, t_kick)
            _cuda_nvtx_pop(CUDABackend, kick_range)
            return luminosity
        end

        function _cuda_pic_field_task(solver::PICPoissonSolver, source, drift_s, source_grid, green_fft,
                                      charge, timing, stream, prep_done, label)
            return @async CUDA.stream!(stream) do
                CUDA.wait(prep_done, stream)
                field_range = _cuda_nvtx_push(CUDABackend, label)
                try
                    _cuda_pic_solve_drifted_field_with_green_fft(
                        solver, source, drift_s, source_grid, green_fft, charge, timing,
                    )
                finally
                    _cuda_nvtx_pop(CUDABackend, field_range)
                end
            end
        end

        function _cuda_pic_interaction!(solver::PICPoissonSolver, source, param_source,
                                        field, param_field, kbb,
                                        green_cache=nothing, charge=nothing, timing=nothing)
            t_prepare = time_ns()
            prep = _cuda_pic_prepare_interaction(solver, source, param_source, field, param_field, green_cache, timing)
            _cuda_pic_add_time!(timing, :prepare, t_prepare)
            t_green = time_ns()
            green_fft = prep.green_fft === nothing ?
                _cuda_pic_green_fft(solver, eltype(source.x), prep.source_grid, prep.field_grid, green_cache, timing) :
                prep.green_fft
            _cuda_pic_add_time!(timing, :field_green, t_green)
            t_fields = time_ns()
            phiL, ExL, EyL = _cuda_pic_solve_drifted_field_with_green_fft(
                solver, source, prep.sL,
                prep.source_grid, green_fft, charge, timing,
            )
            phiR, ExR, EyR = _cuda_pic_solve_drifted_field_with_green_fft(
                solver, source, prep.sR,
                prep.source_grid, green_fft, charge, timing,
            )
            _cuda_pic_add_time!(timing, :fields, t_fields)
            t_kick = time_ns()
            _cuda_pic_launch_kick!(
                solver, field, param_source.center, param_field, field, kbb, prep.field_grid,
                phiL, ExL, EyL, phiR, ExR, EyR, CUDA.stream(),
            )
            _cuda_pic_add_time!(timing, :kick, t_kick)
            return nothing
        end

        function _cuda_pic_prepare_interaction(solver::PICPoissonSolver, source, param_source,
                                               field, param_field, green_cache=nothing, timing=nothing)
            T = eltype(source.x)
            sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
            sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
            t_source = time_ns()
            source_xmin = T(mapreduce((x, px) -> min(x + px * sL, x + px * sR), min, source.x, source.px))
            source_xmax = T(mapreduce((x, px) -> max(x + px * sL, x + px * sR), max, source.x, source.px))
            source_ymin = T(mapreduce((y, py) -> min(y + py * sL, y + py * sR), min, source.y, source.py))
            source_ymax = T(mapreduce((y, py) -> max(y + py * sL, y + py * sR), max, source.y, source.py))
            _cuda_pic_add_time!(timing, :prepare_source, t_source)

            t_field = time_ns()
            source_center = T(param_source.center)
            half = T(0.5)
            field_xmin = T(mapreduce((x, px, z) -> x + px * half * (z - source_center), min,
                                      field.x, field.px, field.z))
            field_xmax = T(mapreduce((x, px, z) -> x + px * half * (z - source_center), max,
                                      field.x, field.px, field.z))
            field_ymin = T(mapreduce((y, py, z) -> y + py * half * (z - source_center), min,
                                      field.y, field.py, field.z))
            field_ymax = T(mapreduce((y, py, z) -> y + py * half * (z - source_center), max,
                                      field.y, field.py, field.z))
            _cuda_pic_add_time!(timing, :prepare_field, t_field)

            t_grid = time_ns()
            source_grid0, field_grid0 = _pic_interaction_grids(
                solver, source_xmin, source_xmax, source_ymin, source_ymax,
                field_xmin, field_xmax, field_ymin, field_ymax,
            )
            source_grid, field_grid, green_fft = _cuda_pic_cached_interaction_grids(
                solver, T, green_cache, source_grid0, field_grid0,
                source_xmin, source_xmax, source_ymin, source_ymax,
                field_xmin, field_xmax, field_ymin, field_ymax,
            )
            _cuda_pic_add_time!(timing, :prepare_grid, t_grid)
            return (
                sL=sL,
                sR=sR,
                source_grid=source_grid,
                field_grid=field_grid,
                source_bounds=(xmin=source_xmin, xmax=source_xmax, ymin=source_ymin, ymax=source_ymax),
                field_bounds=(xmin=field_xmin, xmax=field_xmax, ymin=field_ymin, ymax=field_ymax),
                green_fft=green_fft,
            )
        end

        function _cuda_pic_prepare_interaction_indexed(solver::PICPoissonSolver,
                                                       source, source_idx, param_source,
                                                       field, field_idx, param_field,
                                                       green_cache=nothing, timing=nothing)
            T = eltype(source.x)
            sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
            sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
            neutral_bounds = _cuda_pic_bounds_neutral(T)
            t_source = time_ns()
            source_bounds = mapreduce(
                i -> _cuda_pic_source_bounds_value(source.x[i], source.px[i], source.y[i], source.py[i], sL, sR),
                _cuda_pic_bounds_combine,
                source_idx,
                init=neutral_bounds,
            )
            source_xmin, source_xmax, source_ymin, source_ymax = T.(source_bounds)
            _cuda_pic_add_time!(timing, :prepare_source, t_source)

            t_field = time_ns()
            source_center = T(param_source.center)
            half = T(0.5)
            field_bounds = mapreduce(
                i -> _cuda_pic_field_bounds_value(field.x[i], field.px[i], field.y[i], field.py[i], field.z[i], source_center, half),
                _cuda_pic_bounds_combine,
                field_idx,
                init=neutral_bounds,
            )
            field_xmin, field_xmax, field_ymin, field_ymax = T.(field_bounds)
            _cuda_pic_add_time!(timing, :prepare_field, t_field)

            return _cuda_pic_finish_interaction_indexed(
                solver, T, sL, sR,
                (source_xmin, source_xmax, source_ymin, source_ymax),
                (field_xmin, field_xmax, field_ymin, field_ymax),
                green_cache, timing,
            )
        end

        function _cuda_pic_prepare_interaction_pair_indexed(
            solver::PICPoissonSolver,
            rep1, idx1, param1,
            rep2, idx2, param2,
            green_cache=nothing, timing=nothing,
        )
            T = eltype(rep1.x)
            half = T(0.5)
            sL12 = half * (T(param1.center) - T(param2.lb))
            sR12 = half * (T(param1.center) - T(param2.rb))
            sL21 = half * (T(param2.center) - T(param1.lb))
            sR21 = half * (T(param2.center) - T(param1.rb))
            center1 = T(param1.center)
            center2 = T(param2.center)
            neutral = _cuda_pic_bounds_pair_neutral(T)

            t_bounds1 = time_ns()
            bounds1 = mapreduce(
                i -> _cuda_pic_source_field_bounds_value(
                    rep1.x[i], rep1.px[i], rep1.y[i], rep1.py[i], rep1.z[i],
                    sL12, sR12, center2, half,
                ),
                _cuda_pic_bounds_pair_combine,
                idx1,
                init=neutral,
            )
            elapsed1 = time_ns() - t_bounds1

            t_bounds2 = time_ns()
            bounds2 = mapreduce(
                i -> _cuda_pic_source_field_bounds_value(
                    rep2.x[i], rep2.px[i], rep2.y[i], rep2.py[i], rep2.z[i],
                    sL21, sR21, center1, half,
                ),
                _cuda_pic_bounds_pair_combine,
                idx2,
                init=neutral,
            )
            elapsed2 = time_ns() - t_bounds2
            # Source and field bounds are now measured together. Split only the
            # diagnostic attribution; complete-turn timing remains authoritative.
            total_bounds = elapsed1 + elapsed2
            _cuda_pic_add_elapsed!(timing, :prepare_source, total_bounds ÷ 2)
            _cuda_pic_add_elapsed!(timing, :prepare_field, total_bounds - total_bounds ÷ 2)

            source12 = T.(bounds1[1:4])
            field12 = T.(bounds2[5:8])
            source21 = T.(bounds2[1:4])
            field21 = T.(bounds1[5:8])
            prep12 = _cuda_pic_finish_interaction_indexed(
                solver, T, sL12, sR12, source12, field12, green_cache, timing,
            )
            prep21 = _cuda_pic_finish_interaction_indexed(
                solver, T, sL21, sR21, source21, field21, green_cache, timing,
            )
            return prep12, prep21
        end

        function _cuda_pic_prepare_interaction_wavefront_indexed!(
            solver::PICPoissonSolver, valid, rep1, rep2, green_cache, wf,
            timing=nothing, compute_luminosity::Bool=false,
        )
            T = eltype(rep1.x)
            npairs = length(valid)
            half = T(0.5)
            threads = 256
            block_cap = _CUDA_PIC_BOUNDS_PARTIAL_BLOCKS
            stream = CUDA.stream()
            t_bounds = time_ns()

            CUDA.@cuda threads=threads blocks=cld(length(wf.bounds_partials), threads) stream=stream _cuda_pic_init_wavefront_bounds_partials_kernel!(
                wf.bounds_partials,
            )
            for n in 1:npairs
                item = valid[n]
                center1 = T(item.p1.center)
                center2 = T(item.p2.center)
                sL12 = half * (center1 - T(item.p2.lb))
                sR12 = half * (center1 - T(item.p2.rb))
                sL21 = half * (center2 - T(item.p1.lb))
                sR21 = half * (center2 - T(item.p1.rb))
                blocks1 = min(cld(length(item.idx1), threads), block_cap)
                blocks2 = min(cld(length(item.idx2), threads), block_cap)
                if compute_luminosity
                    s1 = half * (center1 - center2)
                    CUDA.@cuda threads=threads blocks=blocks1 stream=stream _cuda_pic_force_luminosity_bounds_indexed_kernel!(
                        wf.bounds_partials, Int32(2n - 1),
                        rep1.x, rep1.px, rep1.y, rep1.py, rep1.z, item.idx1,
                        sL12, sR12, center2, half, s1,
                    )
                    CUDA.@cuda threads=threads blocks=blocks2 stream=stream _cuda_pic_force_luminosity_bounds_indexed_kernel!(
                        wf.bounds_partials, Int32(2n),
                        rep2.x, rep2.px, rep2.y, rep2.py, rep2.z, item.idx2,
                        sL21, sR21, center1, half, -s1,
                    )
                else
                    CUDA.@cuda threads=threads blocks=blocks1 stream=stream _cuda_pic_force_bounds_indexed_kernel!(
                        wf.bounds_partials, Int32(2n - 1),
                        rep1.x, rep1.px, rep1.y, rep1.py, rep1.z, item.idx1,
                        sL12, sR12, center2, half,
                    )
                    CUDA.@cuda threads=threads blocks=blocks2 stream=stream _cuda_pic_force_bounds_indexed_kernel!(
                        wf.bounds_partials, Int32(2n),
                        rep2.x, rep2.px, rep2.y, rep2.py, rep2.z, item.idx2,
                        sL21, sR21, center1, half,
                    )
                end
            end
            if compute_luminosity
                CUDA.@cuda threads=block_cap blocks=2npairs stream=stream _cuda_pic_finalize_force_luminosity_bounds_kernel!(
                    wf.bounds, wf.bounds_partials,
                )
            else
                CUDA.@cuda threads=block_cap blocks=2npairs stream=stream _cuda_pic_finalize_force_bounds_kernel!(
                    wf.bounds, wf.bounds_partials,
                )
            end
            copyto!(wf.bounds_host, wf.bounds)
            elapsed = time_ns() - t_bounds
            _cuda_pic_add_elapsed!(timing, :prepare_source, elapsed ÷ 2)
            _cuda_pic_add_elapsed!(timing, :prepare_field, elapsed - elapsed ÷ 2)

            prep12 = Vector{Any}(undef, npairs)
            prep21 = Vector{Any}(undef, npairs)
            luminosity_bounds = compute_luminosity ? Vector{Any}(undef, npairs) : nothing
            for n in 1:npairs
                item = valid[n]
                center1 = T(item.p1.center)
                center2 = T(item.p2.center)
                sL12 = half * (center1 - T(item.p2.lb))
                sR12 = half * (center1 - T(item.p2.rb))
                sL21 = half * (center2 - T(item.p1.lb))
                sR21 = half * (center2 - T(item.p1.rb))
                column1 = 2n - 1
                column2 = 2n
                bounds1 = ntuple(row -> wf.bounds_host[row, column1], 8)
                bounds2 = ntuple(row -> wf.bounds_host[row, column2], 8)
                prep12[n] = _cuda_pic_finish_interaction_indexed(
                    solver, T, sL12, sR12, bounds1[1:4], bounds2[5:8], green_cache, timing,
                )
                prep21[n] = _cuda_pic_finish_interaction_indexed(
                    solver, T, sL21, sR21, bounds2[1:4], bounds1[5:8], green_cache, timing,
                )
                if compute_luminosity
                    luminosity_bounds[n] = (
                        beam1=ntuple(row -> wf.bounds_host[row + 8, column1], 4),
                        beam2=ntuple(row -> wf.bounds_host[row + 8, column2], 4),
                    )
                end
            end
            return prep12, prep21, luminosity_bounds
        end

        function _cuda_pic_finish_interaction_indexed(
            solver::PICPoissonSolver, ::Type{T}, sL, sR,
            source_bounds, field_bounds, green_cache, timing,
        ) where {T}
            source_xmin, source_xmax, source_ymin, source_ymax = source_bounds
            field_xmin, field_xmax, field_ymin, field_ymax = field_bounds

            t_grid = time_ns()
            source_grid0, field_grid0 = _pic_interaction_grids(
                solver, source_xmin, source_xmax, source_ymin, source_ymax,
                field_xmin, field_xmax, field_ymin, field_ymax,
            )
            source_grid, field_grid, green_fft = _cuda_pic_cached_interaction_grids(
                solver, T, green_cache, source_grid0, field_grid0,
                source_xmin, source_xmax, source_ymin, source_ymax,
                field_xmin, field_xmax, field_ymin, field_ymax,
            )
            _cuda_pic_add_time!(timing, :prepare_grid, t_grid)
            return (
                sL=sL,
                sR=sR,
                source_grid=source_grid,
                field_grid=field_grid,
                source_bounds=(xmin=source_xmin, xmax=source_xmax, ymin=source_ymin, ymax=source_ymax),
                field_bounds=(xmin=field_xmin, xmax=field_xmax, ymin=field_ymin, ymax=field_ymax),
                green_fft=green_fft,
            )
        end

        function _cuda_pic_launch_kick!(solver::PICPoissonSolver, field, source_center, param_field,
                                        out, kbb, field_grid,
                                        phiL, ExL, EyL, phiR, ExR, EyR, stream)
            T = eltype(field.x)
            threads = _cuda_pic_threads(:kick)
            blocks = cld(length(field.x), threads)
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            nx, ny = solver.grid
            hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
            if solver.longitudinal_kick
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_kick_longitudinal_kernel!(
                    out.x, out.px, out.y, out.py, out.pz,
                    field.x, field.px, field.y, field.py, field.z, field.pz,
                    phiL, ExL, EyL, phiR, ExR, EyR,
                    T(field_grid.x0), T(field_grid.y0),
                    T(field_grid.width) / T(nx - 1), T(field_grid.height) / T(ny - 1),
                    Int32(nx), Int32(ny), method_code,
                    T(source_center), hzi, zbias, T(kbb),
                )
            else
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_kick_kernel!(
                    out.x, out.px, out.y, out.py,
                    field.x, field.px, field.y, field.py, field.z,
                    phiL, ExL, EyL, phiR, ExR, EyR,
                    T(field_grid.x0), T(field_grid.y0),
                    T(field_grid.width) / T(nx - 1), T(field_grid.height) / T(ny - 1),
                    Int32(nx), Int32(ny), method_code,
                    T(source_center), hzi, zbias, T(kbb),
                )
            end
            return nothing
        end

        function _cuda_pic_launch_kick_indexed!(solver::PICPoissonSolver, rep, idx,
                                                source_center, param_field,
                                                kbb, field_grid,
                                                phiL, ExL, EyL, phiR, ExR, EyR, stream)
            T = eltype(rep.x)
            threads = _cuda_pic_threads(:kick)
            blocks = cld(length(idx), threads)
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            nx, ny = solver.grid
            hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
            if solver.longitudinal_kick
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_kick_indexed_longitudinal_kernel!(
                    rep.x, rep.px, rep.y, rep.py, rep.pz, rep.z, idx,
                    phiL, ExL, EyL, phiR, ExR, EyR,
                    T(field_grid.x0), T(field_grid.y0),
                    T(field_grid.width) / T(nx - 1), T(field_grid.height) / T(ny - 1),
                    Int32(nx), Int32(ny), method_code,
                    T(source_center), hzi, zbias, T(kbb),
                )
            else
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_kick_indexed_kernel!(
                    rep.x, rep.px, rep.y, rep.py, rep.z, idx,
                    phiL, ExL, EyL, phiR, ExR, EyR,
                    T(field_grid.x0), T(field_grid.y0),
                    T(field_grid.width) / T(nx - 1), T(field_grid.height) / T(ny - 1),
                    Int32(nx), Int32(ny), method_code,
                    T(source_center), hzi, zbias, T(kbb),
                )
            end
            return nothing
        end

        function _cuda_pic_launch_kick_pair_indexed!(
            solver::PICPoissonSolver,
            rep1, idx1, source_center1, param_field1, kbb1, field_grid1,
            rep2, idx2, source_center2, param_field2, kbb2, field_grid2,
            phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
            phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
            stream,
        )
            T = eltype(rep1.x)
            threads = _cuda_pic_threads(:kick)
            n = max(length(idx1), length(idx2))
            blocks = cld(n, threads)
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            nx, ny = solver.grid
            hzi1, zbias1 = _slice_interpolation_parameters(T(param_field1.lb), T(param_field1.rb))
            hzi2, zbias2 = _slice_interpolation_parameters(T(param_field2.lb), T(param_field2.rb))
            if solver.longitudinal_kick
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_kick_pair_indexed_longitudinal_kernel!(
                    rep1.x, rep1.px, rep1.y, rep1.py, rep1.pz, rep1.z, idx1,
                    rep2.x, rep2.px, rep2.y, rep2.py, rep2.pz, rep2.z, idx2,
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                    T(field_grid1.x0), T(field_grid1.y0),
                    T(field_grid1.width) / T(nx - 1), T(field_grid1.height) / T(ny - 1),
                    T(field_grid2.x0), T(field_grid2.y0),
                    T(field_grid2.width) / T(nx - 1), T(field_grid2.height) / T(ny - 1),
                    Int32(nx), Int32(ny), method_code,
                    T(source_center1), hzi1, zbias1, T(kbb1),
                    T(source_center2), hzi2, zbias2, T(kbb2),
                )
            else
                CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_kick_pair_indexed_kernel!(
                    rep1.x, rep1.px, rep1.y, rep1.py, rep1.z, idx1,
                    rep2.x, rep2.px, rep2.y, rep2.py, rep2.z, idx2,
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                    T(field_grid1.x0), T(field_grid1.y0),
                    T(field_grid1.width) / T(nx - 1), T(field_grid1.height) / T(ny - 1),
                    T(field_grid2.x0), T(field_grid2.y0),
                    T(field_grid2.width) / T(nx - 1), T(field_grid2.height) / T(ny - 1),
                    Int32(nx), Int32(ny), method_code,
                    T(source_center1), hzi1, zbias1, T(kbb1),
                    T(source_center2), hzi2, zbias2, T(kbb2),
                )
            end
            return nothing
        end

        function _cuda_pic_solve_field(solver::PICPoissonSolver, x, y, source_grid, field_grid,
                                       green_cache=nothing, charge=nothing, timing=nothing)
            t_green = time_ns()
            green_fft = _cuda_pic_green_fft(solver, eltype(x), source_grid, field_grid, green_cache, timing)
            _cuda_pic_add_time!(timing, :field_green, t_green)
            return _cuda_pic_solve_field_with_green_fft(solver, x, y, source_grid, green_fft, charge, timing)
        end

        function _cuda_pic_cached_interaction_grids(solver::PICPoissonSolver, ::Type{T}, cache,
                                                    source_grid, field_grid,
                                                    sxmin, sxmax, symin, symax,
                                                    fxmin, fxmax, fymin, fymax) where {T}
            return source_grid, field_grid, nothing
        end

        function _cuda_pic_slice_pair_cached_prep!(solver::PICPoissonSolver, ::Type{T},
                                                 cache::_CUDAPICSlicePairGreenCache{T},
                                                 key::Tuple{Int,Int,Int}, prep,
                                                 timing=nothing) where {T}
            t_lookup = time_ns()
            entry = get(cache.entries, key, nothing)
            if entry !== nothing &&
               _cuda_pic_slice_pair_entry_usable(solver, entry, prep)
                cache.hits += 1
                entry.uses += 1
                _cuda_pic_add_time!(timing, :green_lookup, t_lookup)
                return merge(prep, (
                    source_grid=entry.source_grid,
                    field_grid=entry.field_grid,
                    green_fft=entry.green_fft,
                ))
            end
            _cuda_pic_add_time!(timing, :green_lookup, t_lookup)

            source_grid = _cuda_pic_expand_grid_by(prep.source_grid, T(1) + T(solver.slice_pair_green_growth))
            field_grid = _cuda_pic_expand_grid_by(prep.field_grid, T(1) + T(solver.slice_pair_green_growth))
            t_green = time_ns()
            green_fft = _cuda_pic_build_green_fft(solver, T, source_grid, field_grid, timing)
            _cuda_pic_add_time!(timing, :field_green, t_green)

            if entry === nothing
                cache.misses += 1
            else
                cache.rebuilds += 1
                entry.rebuilds += 1
            end
            cache.entries[key] = _CUDAPICSlicePairGreenEntry{T}(source_grid, field_grid, green_fft, 1, entry === nothing ? 0 : entry.rebuilds)
            return merge(prep, (
                source_grid=source_grid,
                field_grid=field_grid,
                green_fft=green_fft,
            ))
        end

        function _cuda_pic_slice_pair_entry_usable(solver::PICPoissonSolver, entry, prep)
            min_ratio = solver.slice_pair_green_min_ratio
            _cuda_pic_grid_size_usable(entry.source_grid, prep.source_grid, min_ratio) || return false
            _cuda_pic_grid_size_usable(entry.field_grid, prep.field_grid, min_ratio) || return false
            _cuda_pic_grid_covers_bounds(solver, entry.source_grid, prep.source_bounds) || return false
            _cuda_pic_grid_covers_bounds(solver, entry.field_grid, prep.field_bounds) || return false
            return true
        end

        function _cuda_pic_grid_size_usable(cached_grid, requested_grid, min_ratio)
            cached_grid.width >= requested_grid.width || return false
            cached_grid.height >= requested_grid.height || return false
            requested_grid.width >= min_ratio * cached_grid.width || return false
            requested_grid.height >= min_ratio * cached_grid.height || return false
            return true
        end

        function _cuda_pic_grid_covers_bounds(solver::PICPoissonSolver, grid, bounds)
            nx, ny = solver.grid
            T = promote_type(typeof(grid.x0), typeof(bounds.xmin))
            hx = T(grid.width) / T(nx - 1)
            hy = T(grid.height) / T(ny - 1)
            margin = T(_PIC_TEMPLATE_MARGIN_CELLS)
            xmin = T(grid.x0) + margin * hx
            xmax = T(grid.x0) + T(grid.width) - margin * hx
            ymin = T(grid.y0) + margin * hy
            ymax = T(grid.y0) + T(grid.height) - margin * hy
            return T(bounds.xmin) >= xmin && T(bounds.xmax) <= xmax &&
                   T(bounds.ymin) >= ymin && T(bounds.ymax) <= ymax
        end

        function _cuda_pic_expand_grid_by(grid, factor)
            T = promote_type(typeof(grid.x0), typeof(factor))
            new_width = T(grid.width) * T(factor)
            new_height = T(grid.height) * T(factor)
            return _cuda_pic_expand_grid(grid, new_width, new_height)
        end

        @inline function _cuda_pic_bounds_combine(a, b)
            return (min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3]), max(a[4], b[4]))
        end

        @inline function _cuda_pic_bounds_neutral(::Type{T}) where {T}
            return (T(Inf), -T(Inf), T(Inf), -T(Inf))
        end

        @inline function _cuda_pic_source_bounds_value(x, px, y, py, sL, sR)
            xL = x + px * sL
            xR = x + px * sR
            yL = y + py * sL
            yR = y + py * sR
            return (min(xL, xR), max(xL, xR), min(yL, yR), max(yL, yR))
        end

        @inline function _cuda_pic_field_bounds_value(x, px, y, py, z, source_center, half)
            s = half * (z - source_center)
            xd = x + px * s
            yd = y + py * s
            return (xd, xd, yd, yd)
        end

        @inline function _cuda_pic_bounds_pair_neutral(::Type{T}) where {T}
            bounds = _cuda_pic_bounds_neutral(T)
            return (bounds..., bounds...)
        end

        @inline function _cuda_pic_bounds_pair_combine(a, b)
            return (
                min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3]), max(a[4], b[4]),
                min(a[5], b[5]), max(a[6], b[6]), min(a[7], b[7]), max(a[8], b[8]),
            )
        end

        @inline function _cuda_pic_source_field_bounds_value(
            x, px, y, py, z, sL, sR, opposing_center, half,
        )
            source = _cuda_pic_source_bounds_value(x, px, y, py, sL, sR)
            field = _cuda_pic_field_bounds_value(x, px, y, py, z, opposing_center, half)
            return (source..., field...)
        end

        @inline function _cuda_pic_source_field_luminosity_bounds_value(
            x, px, y, py, z, sL, sR, opposing_center, half, luminosity_drift,
        )
            force = _cuda_pic_source_field_bounds_value(
                x, px, y, py, z, sL, sR, opposing_center, half,
            )
            luminosity = _cuda_pic_luminosity_bounds_value(x, px, y, py, luminosity_drift)
            return (force..., luminosity...)
        end

        function _cuda_pic_expand_grid(grid, new_width, new_height)
            T = promote_type(typeof(grid.x0), typeof(new_width))
            dw = T(new_width) - T(grid.width)
            dh = T(new_height) - T(grid.height)
            return (
                x0=T(grid.x0) - T(0.5) * dw,
                y0=T(grid.y0) - T(0.5) * dh,
                width=T(new_width),
                height=T(new_height),
            )
        end

        function _cuda_pic_solve_field_with_green_fft(solver::PICPoissonSolver, x, y,
                                                      source_grid, green_fft,
                                                      charge=nothing, timing=nothing)
            nx, ny = solver.grid
            T = eltype(rep.x)
            hx = T(source_grid.width) / T(nx - 1)
            hy = T(source_grid.height) / T(ny - 1)
            charge = charge === nothing ? CUDA.zeros(T, 2nx, 2ny) : charge
            fill!(charge, zero(T))
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            deposit_threads = _cuda_pic_threads(:deposition)
            blocks = cld(length(x), deposit_threads)
            stream = CUDA.stream()
            t_deposit = time_ns()
            CUDA.@cuda threads=deposit_threads blocks=blocks stream=stream _cuda_pic_deposit_nomask_kernel!(
                charge, x, y, T(source_grid.x0), T(source_grid.y0), hx, hy,
                Int32(nx), Int32(ny), method_code,
            )
            _cuda_pic_add_time!(timing, :field_deposit, t_deposit)
            t_fft = time_ns()
            phi_pad = real(ifft(fft(charge) .* green_fft))
            phi = phi_pad[1:nx, 1:ny]
            _cuda_pic_add_time!(timing, :field_fft, t_fft)
            Ex = similar(phi)
            Ey = similar(phi)
            field_threads = _cuda_pic_threads(:field)
            blocks_grid = cld(nx * ny, field_threads)
            t_derivative = time_ns()
            CUDA.@cuda threads=field_threads blocks=blocks_grid stream=stream _cuda_pic_field_kernel!(Ex, Ey, phi, hx, hy, Int32(nx), Int32(ny))
            _cuda_pic_add_time!(timing, :field_derivative, t_derivative)
            return phi, Ex, Ey
        end

        function _cuda_pic_solve_drifted_field_with_green_fft(solver::PICPoissonSolver, source, drift_s,
                                                              source_grid, green_fft,
                                                              charge=nothing, timing=nothing)
            nx, ny = solver.grid
            T = eltype(source.x)
            hx = T(source_grid.width) / T(nx - 1)
            hy = T(source_grid.height) / T(ny - 1)
            charge = charge === nothing ? CUDA.zeros(T, 2nx, 2ny) : charge
            fill!(charge, zero(T))
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            deposit_threads = _cuda_pic_threads(:deposition)
            blocks = cld(length(source.x), deposit_threads)
            stream = CUDA.stream()
            t_deposit = time_ns()
            CUDA.@cuda threads=deposit_threads blocks=blocks stream=stream _cuda_pic_deposit_drifted_nomask_kernel!(
                charge, source.x, source.px, source.y, source.py, T(drift_s),
                T(source_grid.x0), T(source_grid.y0), hx, hy,
                Int32(nx), Int32(ny), method_code,
            )
            _cuda_pic_add_time!(timing, :field_deposit, t_deposit)
            t_fft = time_ns()
            phi_pad = real(ifft(fft(charge) .* green_fft))
            phi = phi_pad[1:nx, 1:ny]
            _cuda_pic_add_time!(timing, :field_fft, t_fft)
            Ex = similar(phi)
            Ey = similar(phi)
            field_threads = _cuda_pic_threads(:field)
            blocks_grid = cld(nx * ny, field_threads)
            t_derivative = time_ns()
            CUDA.@cuda threads=field_threads blocks=blocks_grid stream=stream _cuda_pic_field_kernel!(Ex, Ey, phi, hx, hy, Int32(nx), Int32(ny))
            _cuda_pic_add_time!(timing, :field_derivative, t_derivative)
            return phi, Ex, Ey
        end

        function _cuda_pic_solve_pair_fields_batched_fft!(solver::PICPoissonSolver,
                                                          source12, prep12,
                                                          source21, prep21,
                                                          green12, green21,
                                                          workspace::_CUDAPICWorkspace,
                                                          timing=nothing)
            nx, ny = solver.grid
            T = eltype(source12.x)
            charge = workspace.batch_charges
            fill!(charge, zero(T))
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            deposit_threads = _cuda_pic_threads(:deposition)
            stream = CUDA.stream()
            t_deposit = time_ns()
            _cuda_pic_deposit_drifted_plane!(
                solver, charge, Int32(1), source12, prep12.sL, prep12.source_grid, method_code, deposit_threads, stream,
            )
            _cuda_pic_deposit_drifted_plane!(
                solver, charge, Int32(2), source12, prep12.sR, prep12.source_grid, method_code, deposit_threads, stream,
            )
            _cuda_pic_deposit_drifted_plane!(
                solver, charge, Int32(3), source21, prep21.sL, prep21.source_grid, method_code, deposit_threads, stream,
            )
            _cuda_pic_deposit_drifted_plane!(
                solver, charge, Int32(4), source21, prep21.sR, prep21.source_grid, method_code, deposit_threads, stream,
            )
            _cuda_pic_add_time!(timing, :field_deposit, t_deposit)

            t_fft = time_ns()
            spectral = fft(charge, (1, 2))
            spectral_threads = _cuda_pic_threads(:spectral)
            blocks_spectral = cld(length(spectral), spectral_threads)
            CUDA.@cuda threads=spectral_threads blocks=blocks_spectral stream=stream _cuda_pic_apply_green_batch_kernel!(
                spectral, green12, green21,
            )
            phi_batch = real(ifft(spectral, (1, 2)))
            _cuda_pic_add_time!(timing, :field_fft, t_fft)

            Ex = workspace.batch_Ex
            Ey = workspace.batch_Ey
            t_derivative = time_ns()
            field_threads = _cuda_pic_threads(:field)
            blocks_grid = cld(nx * ny * 4, field_threads)
            hx12 = T(prep12.source_grid.width) / T(nx - 1)
            hy12 = T(prep12.source_grid.height) / T(ny - 1)
            hx21 = T(prep21.source_grid.width) / T(nx - 1)
            hy21 = T(prep21.source_grid.height) / T(ny - 1)
            CUDA.@cuda threads=field_threads blocks=blocks_grid stream=stream _cuda_pic_field_batch_kernel!(
                Ex, Ey, phi_batch, hx12, hy12, hx21, hy21, Int32(nx), Int32(ny),
            )
            _cuda_pic_add_time!(timing, :field_derivative, t_derivative)
            return phi_batch, Ex, Ey
        end

        function _cuda_pic_wavefront_workspace!(workspace::_CUDAPICWorkspace,
                                                solver::PICPoissonSolver,
                                                ::Type{T}, nplanes::Integer) where {T}
            nx, ny = solver.grid
            lnx, lny = _pic_luminosity_grid(solver)
            ngreen = max(1, Int(nplanes) ÷ 2)
            luminosity_threads = _cuda_pic_threads(:luminosity)
            return get!(workspace.wavefront_cache, (Int(nplanes), luminosity_threads)) do
                (
                    charges=CUDA.zeros(T, 2nx, 2ny, nplanes),
                    greens=CUDA.zeros(T, 2nx, 2ny, ngreen),
                    Ex=CUDA.zeros(T, nx, ny, nplanes),
                    Ey=CUDA.zeros(T, nx, ny, nplanes),
                    luminosity_q1=CUDA.zeros(T, lnx + 1, lny + 1, max(1, nplanes ÷ 4)),
                    luminosity_q2=CUDA.zeros(T, lnx + 1, lny + 1, max(1, nplanes ÷ 4)),
                    luminosity_scale=CUDA.zeros(T, max(1, nplanes ÷ 4)),
                    luminosity_accum=CUDA.zeros(T, 1),
                    luminosity_overlap_partials=CUDA.zeros(
                        T,
                        cld(lnx * lny, luminosity_threads) * max(1, nplanes ÷ 4),
                    ),
                    hx=CUDA.zeros(T, nplanes),
                    hy=CUDA.zeros(T, nplanes),
                    green_field_x0=CUDA.zeros(T, ngreen),
                    green_field_y0=CUDA.zeros(T, ngreen),
                    green_source_x0=CUDA.zeros(T, ngreen),
                    green_source_y0=CUDA.zeros(T, ngreen),
                    green_hx=CUDA.zeros(T, ngreen),
                    green_hy=CUDA.zeros(T, ngreen),
                    green_spectral=CUDA.zeros(Complex{T}, 2nx, 2ny, ngreen),
                    bounds=CUDA.zeros(T, 12, 2 * max(1, nplanes ÷ 4)),
                    bounds_partials=CUDA.zeros(
                        T, 12, _CUDA_PIC_BOUNDS_PARTIAL_BLOCKS,
                        2 * max(1, nplanes ÷ 4),
                    ),
                    bounds_host=Array{T}(undef, 12, 2 * max(1, nplanes ÷ 4)),
                )
            end
        end

        function _cuda_pic_solve_wavefront_fields_batched_fft!(solver::PICPoissonSolver,
                                                               valid, prep12, prep21,
                                                               green12, green21, wf,
                                                               timing=nothing)
            nx, ny = solver.grid
            npairs = length(valid)
            nplanes = 4 * npairs
            T = eltype(valid[1].slice1.coords.x)
            charge = wf.charges
            fill!(charge, zero(T))
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            deposit_threads = _cuda_pic_threads(:deposition)
            stream = CUDA.stream()
            hx_host = Vector{T}(undef, nplanes)
            hy_host = Vector{T}(undef, nplanes)

            t_deposit = time_ns()
            for n in 1:npairs
                item = valid[n]
                offset = 4 * (n - 1)
                _cuda_pic_deposit_drifted_plane!(
                    solver, charge, Int32(offset + 1), item.slice1.coords, prep12[n].sL,
                    prep12[n].source_grid, method_code, deposit_threads, stream,
                )
                _cuda_pic_deposit_drifted_plane!(
                    solver, charge, Int32(offset + 2), item.slice1.coords, prep12[n].sR,
                    prep12[n].source_grid, method_code, deposit_threads, stream,
                )
                _cuda_pic_deposit_drifted_plane!(
                    solver, charge, Int32(offset + 3), item.slice2.coords, prep21[n].sL,
                    prep21[n].source_grid, method_code, deposit_threads, stream,
                )
                _cuda_pic_deposit_drifted_plane!(
                    solver, charge, Int32(offset + 4), item.slice2.coords, prep21[n].sR,
                    prep21[n].source_grid, method_code, deposit_threads, stream,
                )
                hx12 = T(prep12[n].source_grid.width) / T(nx - 1)
                hy12 = T(prep12[n].source_grid.height) / T(ny - 1)
                hx21 = T(prep21[n].source_grid.width) / T(nx - 1)
                hy21 = T(prep21[n].source_grid.height) / T(ny - 1)
                hx_host[offset + 1] = hx12
                hx_host[offset + 2] = hx12
                hx_host[offset + 3] = hx21
                hx_host[offset + 4] = hx21
                hy_host[offset + 1] = hy12
                hy_host[offset + 2] = hy12
                hy_host[offset + 3] = hy21
                hy_host[offset + 4] = hy21
            end
            _cuda_pic_add_time!(timing, :field_deposit, t_deposit)

            copyto!(wf.hx, hx_host)
            copyto!(wf.hy, hy_host)

            green_spectral = nothing
            if green12 === nothing && green21 === nothing
                green_spectral = _cuda_pic_build_wavefront_green_fft!(
                    solver, wf, prep12, prep21, T, timing, _cuda_pic_threads(:green), stream,
                )
            end

            t_fft = time_ns()
            spectral = fft(charge, (1, 2))
            if green12 === nothing && green21 === nothing
                spectral_threads = _cuda_pic_threads(:spectral)
                blocks_spectral = cld(length(spectral), spectral_threads)
                CUDA.@cuda threads=spectral_threads blocks=blocks_spectral stream=stream _cuda_pic_multiply_spectral_stack_kernel!(
                    spectral, green_spectral,
                )
            elseif _cuda_pic_stack_cached_green_enabled()
                t_green_stack = time_ns()
                _cuda_pic_copy_green_spectral_stack!(wf.green_spectral, green12, green21, stream)
                _cuda_pic_add_time!(timing, :green_lookup, t_green_stack)
                spectral_threads = _cuda_pic_threads(:spectral)
                blocks_spectral = cld(length(spectral), spectral_threads)
                CUDA.@cuda threads=spectral_threads blocks=blocks_spectral stream=stream _cuda_pic_multiply_spectral_stack_kernel!(
                    spectral, wf.green_spectral,
                )
            else
                for n in 1:npairs
                    offset = 4 * (n - 1)
                    spectral_threads = _cuda_pic_threads(:spectral)
                    _cuda_pic_apply_green_plane!(spectral, green12[n], Int32(offset + 1), spectral_threads, stream)
                    _cuda_pic_apply_green_plane!(spectral, green12[n], Int32(offset + 2), spectral_threads, stream)
                    _cuda_pic_apply_green_plane!(spectral, green21[n], Int32(offset + 3), spectral_threads, stream)
                    _cuda_pic_apply_green_plane!(spectral, green21[n], Int32(offset + 4), spectral_threads, stream)
                end
            end
            phi_batch = real(ifft(spectral, (1, 2)))
            _cuda_pic_add_time!(timing, :field_fft, t_fft)

            t_derivative = time_ns()
            field_threads = _cuda_pic_threads(:field)
            blocks_grid = cld(nx * ny * nplanes, field_threads)
            CUDA.@cuda threads=field_threads blocks=blocks_grid stream=stream _cuda_pic_field_wavefront_kernel!(
                wf.Ex, wf.Ey, phi_batch, wf.hx, wf.hy, Int32(nx), Int32(ny), Int32(nplanes),
            )
            _cuda_pic_add_time!(timing, :field_derivative, t_derivative)
            return phi_batch, wf.Ex, wf.Ey
        end

        function _cuda_pic_solve_wavefront_fields_indexed_batched_fft!(solver::PICPoissonSolver,
                                                                       valid, rep1, rep2,
                                                                       prep12, prep21,
                                                                       green12, green21, wf,
                                                                       timing=nothing)
            nx, ny = solver.grid
            npairs = length(valid)
            nplanes = 4 * npairs
            T = eltype(rep1.x)
            charge = wf.charges
            fill!(charge, zero(T))
            method_code = Symbol(solver.deposit_method) == :CIC ? Int32(1) : Int32(2)
            deposit_threads = _cuda_pic_threads(:deposition)
            stream = CUDA.stream()
            hx_host = Vector{T}(undef, nplanes)
            hy_host = Vector{T}(undef, nplanes)

            t_deposit = time_ns()
            for n in 1:npairs
                item = valid[n]
                offset = 4 * (n - 1)
                _cuda_pic_deposit_drifted_indexed_plane_pair!(
                    solver, charge, Int32(offset + 1), Int32(offset + 2),
                    rep1, item.idx1, prep12[n].sL, prep12[n].sR,
                    prep12[n].source_grid, method_code, deposit_threads, stream,
                )
                _cuda_pic_deposit_drifted_indexed_plane_pair!(
                    solver, charge, Int32(offset + 3), Int32(offset + 4),
                    rep2, item.idx2, prep21[n].sL, prep21[n].sR,
                    prep21[n].source_grid, method_code, deposit_threads, stream,
                )
                hx12 = T(prep12[n].source_grid.width) / T(nx - 1)
                hy12 = T(prep12[n].source_grid.height) / T(ny - 1)
                hx21 = T(prep21[n].source_grid.width) / T(nx - 1)
                hy21 = T(prep21[n].source_grid.height) / T(ny - 1)
                hx_host[offset + 1] = hx12
                hx_host[offset + 2] = hx12
                hx_host[offset + 3] = hx21
                hx_host[offset + 4] = hx21
                hy_host[offset + 1] = hy12
                hy_host[offset + 2] = hy12
                hy_host[offset + 3] = hy21
                hy_host[offset + 4] = hy21
            end
            _cuda_pic_add_time!(timing, :field_deposit, t_deposit)

            copyto!(wf.hx, hx_host)
            copyto!(wf.hy, hy_host)

            green_spectral = nothing
            if green12 === nothing && green21 === nothing
                green_spectral = _cuda_pic_build_wavefront_green_fft!(
                    solver, wf, prep12, prep21, T, timing, _cuda_pic_threads(:green), stream,
                )
            end

            t_fft = time_ns()
            spectral = fft(charge, (1, 2))
            spectral_threads = _cuda_pic_threads(:spectral)
            if green12 === nothing && green21 === nothing
                blocks_spectral = cld(length(spectral), spectral_threads)
                CUDA.@cuda threads=spectral_threads blocks=blocks_spectral stream=stream _cuda_pic_multiply_spectral_stack_kernel!(
                    spectral, green_spectral,
                )
            elseif _cuda_pic_stack_cached_green_enabled()
                t_green_stack = time_ns()
                _cuda_pic_copy_green_spectral_stack!(wf.green_spectral, green12, green21, stream)
                _cuda_pic_add_time!(timing, :green_lookup, t_green_stack)
                blocks_spectral = cld(length(spectral), spectral_threads)
                CUDA.@cuda threads=spectral_threads blocks=blocks_spectral stream=stream _cuda_pic_multiply_spectral_stack_kernel!(
                    spectral, wf.green_spectral,
                )
            else
                for n in 1:npairs
                    offset = 4 * (n - 1)
                    _cuda_pic_apply_green_plane!(spectral, green12[n], Int32(offset + 1), spectral_threads, stream)
                    _cuda_pic_apply_green_plane!(spectral, green12[n], Int32(offset + 2), spectral_threads, stream)
                    _cuda_pic_apply_green_plane!(spectral, green21[n], Int32(offset + 3), spectral_threads, stream)
                    _cuda_pic_apply_green_plane!(spectral, green21[n], Int32(offset + 4), spectral_threads, stream)
                end
            end
            phi_batch = real(ifft(spectral, (1, 2)))
            _cuda_pic_add_time!(timing, :field_fft, t_fft)

            t_derivative = time_ns()
            field_threads = _cuda_pic_threads(:field)
            blocks_grid = cld(nx * ny * nplanes, field_threads)
            CUDA.@cuda threads=field_threads blocks=blocks_grid stream=stream _cuda_pic_field_wavefront_kernel!(
                wf.Ex, wf.Ey, phi_batch, wf.hx, wf.hy, Int32(nx), Int32(ny), Int32(nplanes),
            )
            _cuda_pic_add_time!(timing, :field_derivative, t_derivative)
            return phi_batch, wf.Ex, wf.Ey
        end

        function _cuda_pic_copy_green_spectral_stack!(green_spectral, green12, green21, stream)
            CUDA.stream!(stream) do
                for n in eachindex(green12)
                    offset = 2 * (n - 1)
                    copyto!(@view(green_spectral[:, :, offset + 1]), green12[n])
                    copyto!(@view(green_spectral[:, :, offset + 2]), green21[n])
                end
            end
            return green_spectral
        end

        function _cuda_pic_build_wavefront_green_fft!(solver::PICPoissonSolver, wf,
                                                      prep12, prep21, ::Type{T},
                                                      timing, threads::Integer, stream) where {T}
            t_green_total = time_ns()
            nx, ny = solver.grid
            ngreen = length(prep12) * 2
            field_x0 = Vector{T}(undef, ngreen)
            field_y0 = Vector{T}(undef, ngreen)
            source_x0 = Vector{T}(undef, ngreen)
            source_y0 = Vector{T}(undef, ngreen)
            hx = Vector{T}(undef, ngreen)
            hy = Vector{T}(undef, ngreen)
            for n in eachindex(prep12)
                offset = 2 * (n - 1)
                _cuda_pic_green_plane_params!(field_x0, field_y0, source_x0, source_y0, hx, hy,
                                              offset + 1, prep12[n].source_grid, prep12[n].field_grid, nx, ny)
                _cuda_pic_green_plane_params!(field_x0, field_y0, source_x0, source_y0, hx, hy,
                                              offset + 2, prep21[n].source_grid, prep21[n].field_grid, nx, ny)
            end
            copyto!(wf.green_field_x0, field_x0)
            copyto!(wf.green_field_y0, field_y0)
            copyto!(wf.green_source_x0, source_x0)
            copyto!(wf.green_source_y0, source_y0)
            copyto!(wf.green_hx, hx)
            copyto!(wf.green_hy, hy)

            t_build = time_ns()
            green_code = Symbol(solver.green_type) == :integrated ? Int32(1) : Int32(2)
            CUDA.@cuda threads=threads blocks=cld(length(wf.greens), threads) stream=stream _cuda_pic_green_stack_kernel!(
                wf.greens, wf.green_field_x0, wf.green_field_y0,
                wf.green_source_x0, wf.green_source_y0, wf.green_hx, wf.green_hy,
                green_code, Int32(nx), Int32(ny), Int32(ngreen),
            )
            _cuda_pic_add_time!(timing, :green_build_kernel, t_build)

            t_green_fft = time_ns()
            green_spectral = fft(wf.greens, (1, 2))
            _cuda_pic_add_time!(timing, :green_build_fft, t_green_fft)
            _cuda_pic_add_time!(timing, :field_green, t_green_total)
            return green_spectral
        end

        function _cuda_pic_green_plane_params!(field_x0, field_y0, source_x0, source_y0, hx, hy,
                                               plane::Integer, source_grid, field_grid,
                                               nx::Integer, ny::Integer)
            T = eltype(hx)
            field_x0[plane] = T(field_grid.x0)
            field_y0[plane] = T(field_grid.y0)
            source_x0[plane] = T(source_grid.x0)
            source_y0[plane] = T(source_grid.y0)
            hx[plane] = T(source_grid.width) / T(nx - 1)
            hy[plane] = T(source_grid.height) / T(ny - 1)
            return nothing
        end

        function _cuda_pic_apply_green_plane!(spectral, green, plane::Int32, threads::Integer, stream)
            blocks = cld(size(spectral, 1) * size(spectral, 2), threads)
            CUDA.@cuda threads=threads blocks=blocks stream=stream _cuda_pic_apply_green_plane_kernel!(
                spectral, green, plane,
            )
            return nothing
        end

        function _cuda_pic_deposit_drifted_plane!(solver::PICPoissonSolver, charge, plane::Int32,
                                                  source, drift_s, source_grid, method_code::Int32,
                                                  threads::Integer, stream)
            nx, ny = solver.grid
            T = eltype(source.x)
            hx = T(source_grid.width) / T(nx - 1)
            hy = T(source_grid.height) / T(ny - 1)
            CUDA.@cuda threads=threads blocks=cld(length(source.x), threads) stream=stream _cuda_pic_deposit_drifted_plane_kernel!(
                charge, plane, source.x, source.px, source.y, source.py, T(drift_s),
                T(source_grid.x0), T(source_grid.y0), hx, hy, Int32(nx), Int32(ny), method_code,
            )
            return nothing
        end

        function _cuda_pic_deposit_drifted_indexed_plane!(solver::PICPoissonSolver, charge, plane::Int32,
                                                          source, idx, drift_s, source_grid,
                                                          method_code::Int32, threads::Integer, stream)
            nx, ny = solver.grid
            T = eltype(source.x)
            hx = T(source_grid.width) / T(nx - 1)
            hy = T(source_grid.height) / T(ny - 1)
            CUDA.@cuda threads=threads blocks=cld(length(idx), threads) stream=stream _cuda_pic_deposit_drifted_indexed_plane_kernel!(
                charge, plane, source.x, source.px, source.y, source.py, idx, T(drift_s),
                T(source_grid.x0), T(source_grid.y0), hx, hy, Int32(nx), Int32(ny), method_code,
            )
            return nothing
        end

        function _cuda_pic_deposit_drifted_indexed_plane_pair!(
            solver::PICPoissonSolver, charge, planeL::Int32, planeR::Int32,
            source, idx, driftL, driftR, source_grid,
            method_code::Int32, threads::Integer, stream,
        )
            nx, ny = solver.grid
            T = eltype(source.x)
            hx = T(source_grid.width) / T(nx - 1)
            hy = T(source_grid.height) / T(ny - 1)
            CUDA.@cuda threads=threads blocks=cld(length(idx), threads) stream=stream _cuda_pic_deposit_drifted_indexed_plane_pair_kernel!(
                charge, planeL, planeR, source.x, source.px, source.y, source.py, idx,
                T(driftL), T(driftR), T(source_grid.x0), T(source_grid.y0), hx, hy,
                Int32(nx), Int32(ny), method_code,
            )
            return nothing
        end

        function _cuda_pic_green_fft(solver::PICPoissonSolver, ::Type{T}, source_grid, field_grid,
                                     cache, timing=nothing) where {T}
            return _cuda_pic_build_green_fft(solver, T, source_grid, field_grid, timing)
        end

        function _cuda_pic_build_green_fft(solver::PICPoissonSolver, ::Type{T}, source_grid, field_grid,
                                           timing=nothing) where {T}
            nx, ny = solver.grid
            hx = T(source_grid.width) / T(nx - 1)
            hy = T(source_grid.height) / T(ny - 1)
            t_build = time_ns()
            green = CUDA.zeros(T, 2nx, 2ny)
            green_code = Symbol(solver.green_type) == :integrated ? Int32(1) : Int32(2)
            threads = _cuda_pic_threads(:green)
            blocks = cld(length(green), threads)
            CUDA.@cuda threads=threads blocks=blocks stream=CUDA.stream() _cuda_pic_green_kernel!(
                green, green_code,
                T(field_grid.x0), T(field_grid.y0),
                T(source_grid.x0), T(source_grid.y0),
                hx, hy, Int32(nx), Int32(ny),
            )
            _cuda_pic_add_time!(timing, :green_build_kernel, t_build)
            t_fft = time_ns()
            green_fft = fft(green)
            _cuda_pic_add_time!(timing, :green_build_fft, t_fft)
            return green_fft
        end

        function _cuda_pic_wavefront_luminosity(solver::PICPoissonSolver, valid, klum,
                                                workspace::_CUDAPICWorkspace, timing=nothing)
            if _cuda_pic_batched_luminosity_enabled()
                return _cuda_pic_wavefront_luminosity_batched(solver, valid, klum, workspace, timing)
            end
            T = eltype(valid[1].slice1.coords.x)
            t_luminosity = time_ns()
            luminosity = zero(T)
            for item in valid
                luminosity += _cuda_pic_luminosity(
                    solver, item.slice1.coords, item.p1, item.slice2.coords, item.p2, klum, workspace,
                )
            end
            _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
            return luminosity
        end

        function _cuda_pic_wavefront_luminosity_batched(solver::PICPoissonSolver, valid, klum,
                                                        workspace::_CUDAPICWorkspace, timing=nothing)
            npairs = length(valid)
            npairs == 0 && return zero(eltype(workspace.batch_charges))
            nx, ny = _pic_luminosity_grid(solver)
            T = eltype(valid[1].slice1.coords.x)
            wf = _cuda_pic_wavefront_workspace!(workspace, solver, T, 4 * npairs)
            q1 = wf.luminosity_q1
            q2 = wf.luminosity_q2
            scale = wf.luminosity_scale
            accum = wf.luminosity_accum
            fill!(q1, zero(T))
            fill!(q2, zero(T))
            fill!(accum, zero(T))
            scale_host = Vector{T}(undef, npairs)
            threads = _cuda_pic_threads(:luminosity)
            stream = CUDA.stream()
            t_luminosity = time_ns()
            method_code = _pic_luminosity_deposit_method(solver) == :CIC ? Int32(1) : Int32(2)
            for n in 1:npairs
                item = valid[n]
                rep1 = item.slice1.coords
                rep2 = item.slice2.coords
                p1 = item.p1
                p2 = item.p2
                s1 = T(0.5) * (T(p1.center) - T(p2.center))
                s2 = -s1
                x1 = rep1.x .+ rep1.px .* s1
                y1 = rep1.y .+ rep1.py .* s1
                x2 = rep2.x .+ rep2.px .* s2
                y2 = rep2.y .+ rep2.py .* s2
                xmin = min(T(minimum(x1)), T(minimum(x2)))
                xmax = max(T(maximum(x1)), T(maximum(x2)))
                ymin = min(T(minimum(y1)), T(minimum(y2)))
                ymax = max(T(maximum(y1)), T(maximum(y2)))
                width = max(T(xmax - xmin), eps(T))
                height = max(T(ymax - ymin), eps(T))
                tx = width / T(nx - 1.1)
                ty = height / T(ny - 1.1)
                width += T(0.1) * tx
                height += T(0.1) * ty
                xmin -= T(0.05) * tx
                ymin -= T(0.05) * ty
                hx = width / T(nx - 1)
                hy = height / T(ny - 1)
                scale_host[n] = T(klum) / (hx * hy)
                CUDA.@cuda threads=threads blocks=cld(length(rep1.x), threads) stream=stream _cuda_pic_deposit_drifted_plane_kernel!(
                    q1, Int32(n), rep1.x, rep1.px, rep1.y, rep1.py, s1,
                    xmin, ymin, hx, hy, Int32(nx + 1), Int32(ny + 1), method_code,
                )
                CUDA.@cuda threads=threads blocks=cld(length(rep2.x), threads) stream=stream _cuda_pic_deposit_drifted_plane_kernel!(
                    q2, Int32(n), rep2.x, rep2.px, rep2.y, rep2.py, s2,
                    xmin, ymin, hx, hy, Int32(nx + 1), Int32(ny + 1), method_code,
                )
            end
            copyto!(scale, scale_host)
            blocks_grid = cld(nx * ny * npairs, threads)
            CUDA.@cuda threads=threads blocks=blocks_grid stream=stream _cuda_pic_luminosity_wavefront_kernel!(
                accum, q1, q2, scale, Int32(nx), Int32(ny), Int32(npairs),
            )
            CUDA.synchronize(stream)
            _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
            return T(CUDA.@allowscalar accum[1])
        end

        function _cuda_pic_wavefront_luminosity_indexed(solver::PICPoissonSolver, valid,
                                                        rep1, rep2, klum,
                                                        workspace::_CUDAPICWorkspace, timing=nothing,
                                                        prepared_bounds=nothing)
            npairs = length(valid)
            npairs == 0 && return zero(eltype(rep1.x))
            nx, ny = _pic_luminosity_grid(solver)
            T = eltype(rep1.x)
            wf = _cuda_pic_wavefront_workspace!(workspace, solver, T, 4 * npairs)
            q1, q2 = wf.luminosity_q1, wf.luminosity_q2
            fill!(q1, zero(T))
            fill!(q2, zero(T))
            scale_host = Vector{T}(undef, npairs)
            threads = _cuda_pic_threads(:luminosity)
            stream = CUDA.stream()
            method_code = _pic_luminosity_deposit_method(solver) == :CIC ? Int32(1) : Int32(2)
            t_luminosity = time_ns()
            for n in 1:npairs
                item = valid[n]
                s1 = T(0.5) * (T(item.p1.center) - T(item.p2.center))
                s2 = -s1
                bounds1, bounds2 = if prepared_bounds === nothing
                    neutral = _cuda_pic_bounds_neutral(T)
                    (
                        mapreduce(
                            i -> _cuda_pic_luminosity_bounds_value(
                                rep1.x[i], rep1.px[i], rep1.y[i], rep1.py[i], s1,
                            ),
                            _cuda_pic_bounds_combine, item.idx1; init=neutral,
                        ),
                        mapreduce(
                            i -> _cuda_pic_luminosity_bounds_value(
                                rep2.x[i], rep2.px[i], rep2.y[i], rep2.py[i], s2,
                            ),
                            _cuda_pic_bounds_combine, item.idx2; init=neutral,
                        ),
                    )
                else
                    (prepared_bounds[n].beam1, prepared_bounds[n].beam2)
                end
                xmin = min(T(bounds1[1]), T(bounds2[1]))
                xmax = max(T(bounds1[2]), T(bounds2[2]))
                ymin = min(T(bounds1[3]), T(bounds2[3]))
                ymax = max(T(bounds1[4]), T(bounds2[4]))
                width = max(xmax - xmin, eps(T))
                height = max(ymax - ymin, eps(T))
                tx = width / T(nx - 1.1)
                ty = height / T(ny - 1.1)
                width += T(0.1) * tx
                height += T(0.1) * ty
                xmin -= T(0.05) * tx
                ymin -= T(0.05) * ty
                hx = width / T(nx - 1)
                hy = height / T(ny - 1)
                scale_host[n] = T(klum) / (hx * hy)
                CUDA.@cuda threads=threads blocks=cld(length(item.idx1), threads) stream=stream _cuda_pic_deposit_drifted_indexed_plane_kernel!(
                    q1, Int32(n), rep1.x, rep1.px, rep1.y, rep1.py, item.idx1, s1,
                    xmin, ymin, hx, hy, Int32(nx + 1), Int32(ny + 1), method_code,
                )
                CUDA.@cuda threads=threads blocks=cld(length(item.idx2), threads) stream=stream _cuda_pic_deposit_drifted_indexed_plane_kernel!(
                    q2, Int32(n), rep2.x, rep2.px, rep2.y, rep2.py, item.idx2, s2,
                    xmin, ymin, hx, hy, Int32(nx + 1), Int32(ny + 1), method_code,
                )
            end
            copyto!(wf.luminosity_scale, scale_host)
            blocks_per_pair = cld(nx * ny, threads)
            overlap_blocks = blocks_per_pair * npairs
            CUDA.@cuda threads=threads blocks=overlap_blocks shmem=threads*sizeof(T) stream=stream _cuda_pic_luminosity_overlap_partials_kernel!(
                wf.luminosity_overlap_partials, q1, q2, wf.luminosity_scale,
                Int32(nx), Int32(ny), Int32(blocks_per_pair), Int32(npairs),
            )
            luminosity = sum(wf.luminosity_overlap_partials)
            sink = _ACTIVE_PIC_LUMINOSITY_PAIR_SINK[]
            if sink !== nothing
                partials = Array(@view(wf.luminosity_overlap_partials[1:overlap_blocks]))
                context = _ACTIVE_PIC_TIMING_CONTEXT[]
                turn = context === nothing ? -1 : context.turn
                for n in 1:npairs
                    first_block = (n - 1) * blocks_per_pair + 1
                    pair_luminosity = sum(@view(partials[first_block:(first_block + blocks_per_pair - 1)]))
                    item = valid[n]
                    push!(sink, (
                        turn=turn, i=Int(item.pair.i), j=Int(item.pair.j),
                        luminosity=Float64(pair_luminosity),
                    ))
                end
            end
            _cuda_pic_add_time!(timing, :luminosity, t_luminosity)
            return T(luminosity)
        end

        @inline function _cuda_pic_luminosity_bounds_value(x, px, y, py, drift)
            xd = x + px * drift
            yd = y + py * drift
            return (xd, xd, yd, yd)
        end

        function _cuda_pic_luminosity(solver::PICPoissonSolver, rep1, p1, rep2, p2, klum,
                                      workspace=nothing)
            nx, ny = _pic_luminosity_grid(solver)
            T = eltype(rep1.x)
            s1 = T(0.5) * (T(p1.center) - T(p2.center))
            s2 = -s1
            x1 = rep1.x .+ rep1.px .* s1
            y1 = rep1.y .+ rep1.py .* s1
            x2 = rep2.x .+ rep2.px .* s2
            y2 = rep2.y .+ rep2.py .* s2
            xmin = min(T(minimum(x1)), T(minimum(x2)))
            xmax = max(T(maximum(x1)), T(maximum(x2)))
            ymin = min(T(minimum(y1)), T(minimum(y2)))
            ymax = max(T(maximum(y1)), T(maximum(y2)))
            width = max(T(xmax - xmin), eps(T))
            height = max(T(ymax - ymin), eps(T))
            tx = width / T(nx - 1.1)
            ty = height / T(ny - 1.1)
            width += T(0.1) * tx
            height += T(0.1) * ty
            xmin -= T(0.05) * tx
            ymin -= T(0.05) * ty
            hx = width / T(nx - 1)
            hy = height / T(ny - 1)
            q1 = workspace === nothing ? CUDA.zeros(T, nx + 1, ny + 1) : workspace.luminosity_q1
            q2 = workspace === nothing ? CUDA.zeros(T, nx + 1, ny + 1) : workspace.luminosity_q2
            fill!(q1, zero(T))
            fill!(q2, zero(T))
            threads = _cuda_pic_threads(:luminosity)
            stream = CUDA.stream()
            method_code = _pic_luminosity_deposit_method(solver) == :CIC ? Int32(1) : Int32(2)
            CUDA.@cuda threads=threads blocks=cld(length(x1), threads) stream=stream _cuda_pic_deposit_nomask_kernel!(
                q1, x1, y1, xmin, ymin, hx, hy, Int32(nx + 1), Int32(ny + 1), method_code,
            )
            CUDA.@cuda threads=threads blocks=cld(length(x2), threads) stream=stream _cuda_pic_deposit_nomask_kernel!(
                q2, x2, y2, xmin, ymin, hx, hy, Int32(nx + 1), Int32(ny + 1), method_code,
            )
            lum = sum(q1[1:nx, 1:ny] .* q2[1:nx, 1:ny])
            return T(lum) * T(klum) / (hx * hy)
        end

        function _cuda_pic_gather_slice_kernel!(sx, spx, sy, spy, sz,
                                                x, px, y, py, z, idx)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(idx)
                source_index = idx[index]
                @inbounds begin
                    sx[index] = x[source_index]
                    spx[index] = px[source_index]
                    sy[index] = y[source_index]
                    spy[index] = py[source_index]
                    sz[index] = z[source_index]
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_gather_slice_longitudinal_kernel!(sx, spx, sy, spy, sz, spz,
                                                             x, px, y, py, z, pz, idx)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(idx)
                source_index = idx[index]
                @inbounds begin
                    sx[index] = x[source_index]
                    spx[index] = px[source_index]
                    sy[index] = y[source_index]
                    spy[index] = py[source_index]
                    sz[index] = z[source_index]
                    spz[index] = pz[source_index]
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_scatter_slice_kernel!(x, px, y, py,
                                                 sx, spx, sy, spy, idx)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(idx)
                target_index = idx[index]
                @inbounds begin
                    x[target_index] = sx[index]
                    px[target_index] = spx[index]
                    y[target_index] = sy[index]
                    py[target_index] = spy[index]
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_scatter_slice_longitudinal_kernel!(x, px, y, py, pz,
                                                              sx, spx, sy, spy, spz, idx)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(idx)
                target_index = idx[index]
                @inbounds begin
                    x[target_index] = sx[index]
                    px[target_index] = spx[index]
                    y[target_index] = sy[index]
                    py[target_index] = spy[index]
                    pz[target_index] = spz[index]
                end
                index += stride
            end
            return nothing
        end

        function _cuda_indices_from_mask_kernel!(idx, mask, positions)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(mask)
                if mask[index]
                    @inbounds idx[positions[index]] = index
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_green_kernel!(green, green_code::Int32,
                                         field_x0, field_y0, source_x0, source_y0,
                                         hx, hy, nx::Int32, ny::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            nx2 = Int32(2) * nx
            ny2 = Int32(2) * ny
            total = Int(nx2) * Int(ny2)
            half_hx = hx / 2
            half_hy = hy / 2
            hxihyi = typeof(hx)(-0.5) / (hx * hy)
            while index <= total
                i0 = Int32((index - 1) % Int(nx2))
                j0 = Int32((index - 1) ÷ Int(nx2))
                ii = i0 < nx ? i0 : i0 - nx2
                jj = j0 < ny ? j0 : j0 - ny2
                x = field_x0 - source_x0 + ii * hx
                y = field_y0 - source_y0 + jj * hy
                @inbounds begin
                    if green_code == Int32(1)
                        val = _cuda_pic_kernel_integral(x + half_hx, y + half_hy)
                        val += _cuda_pic_kernel_integral(x - half_hx, y - half_hy)
                        val -= _cuda_pic_kernel_integral(x + half_hx, y - half_hy)
                        val -= _cuda_pic_kernel_integral(x - half_hx, y + half_hy)
                        green[i0 + Int32(1), j0 + Int32(1)] = hxihyi * val
                    else
                        r2 = max(x * x + y * y, eps(typeof(x)))
                        green[i0 + Int32(1), j0 + Int32(1)] = typeof(x)(-0.5) * log(r2)
                    end
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_green_stack_kernel!(green, field_x0, field_y0, source_x0, source_y0,
                                               hx, hy, green_code::Int32,
                                               nx::Int32, ny::Int32, nplanes::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            nx2 = Int32(2) * nx
            ny2 = Int32(2) * ny
            plane_size = Int(nx2) * Int(ny2)
            total = plane_size * Int(nplanes)
            while index <= total
                plane0 = (index - 1) ÷ plane_size
                local_index = index - plane0 * plane_size
                i0 = Int32((local_index - 1) % Int(nx2))
                j0 = Int32((local_index - 1) ÷ Int(nx2))
                plane = plane0 + 1
                hxp = hx[plane]
                hyp = hy[plane]
                half_hx = hxp / 2
                half_hy = hyp / 2
                hxihyi = typeof(hxp)(-0.5) / (hxp * hyp)
                ii = i0 < nx ? i0 : i0 - nx2
                jj = j0 < ny ? j0 : j0 - ny2
                x = field_x0[plane] - source_x0[plane] + ii * hxp
                y = field_y0[plane] - source_y0[plane] + jj * hyp
                @inbounds begin
                    if green_code == Int32(1)
                        val = _cuda_pic_kernel_integral(x + half_hx, y + half_hy)
                        val += _cuda_pic_kernel_integral(x - half_hx, y - half_hy)
                        val -= _cuda_pic_kernel_integral(x + half_hx, y - half_hy)
                        val -= _cuda_pic_kernel_integral(x - half_hx, y + half_hy)
                        green[i0 + Int32(1), j0 + Int32(1), plane] = hxihyi * val
                    else
                        r2 = max(x * x + y * y, eps(typeof(x)))
                        green[i0 + Int32(1), j0 + Int32(1), plane] = typeof(x)(-0.5) * log(r2)
                    end
                end
                index += stride
            end
            return nothing
        end

        @inline function _cuda_pic_atan_ratio(num, den)
            if den == 0
                num == 0 && return zero(num + den)
                return copysign(typeof(num / one(den))(pi / 2), num)
            end
            return atan(num / den)
        end

        @inline function _cuda_pic_kernel_integral(x, y)
            r2 = x * x + y * y
            r2 = max(r2, eps(typeof(r2)))
            return (log(r2) - 3) * x * y +
                   _cuda_pic_atan_ratio(y, x) * x * x +
                   _cuda_pic_atan_ratio(x, y) * y * y
        end

        function _cuda_pic_deposit_kernel!(charge, x, y, mask, x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(x)
                if mask[index]
                    ux = (x[index] - x0) * hxi
                    uy = (y[index] - y0) * hyi
                    if method_code == 1
                        ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                        iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                        @inbounds begin
                            CUDA.@atomic charge[ix, iy] += wx1 * wy1
                            CUDA.@atomic charge[ix + 1, iy] += wx2 * wy1
                            CUDA.@atomic charge[ix, iy + 1] += wx1 * wy2
                            CUDA.@atomic charge[ix + 1, iy + 1] += wx2 * wy2
                        end
                    else
                        ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                        iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                        @inbounds begin
                            CUDA.@atomic charge[ix, iy] += wx1 * wy1
                            CUDA.@atomic charge[ix, iy + 1] += wx1 * wy2
                            CUDA.@atomic charge[ix, iy + 2] += wx1 * wy3
                            CUDA.@atomic charge[ix + 1, iy] += wx2 * wy1
                            CUDA.@atomic charge[ix + 1, iy + 1] += wx2 * wy2
                            CUDA.@atomic charge[ix + 1, iy + 2] += wx2 * wy3
                            CUDA.@atomic charge[ix + 2, iy] += wx3 * wy1
                            CUDA.@atomic charge[ix + 2, iy + 1] += wx3 * wy2
                            CUDA.@atomic charge[ix + 2, iy + 2] += wx3 * wy3
                        end
                    end
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_deposit_nomask_kernel!(charge, x, y, x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(x)
                ux = (x[index] - x0) * hxi
                uy = (y[index] - y0) * hyi
                if method_code == 1
                    ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                    iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy] += wx1 * wy1
                        CUDA.@atomic charge[ix + 1, iy] += wx2 * wy1
                        CUDA.@atomic charge[ix, iy + 1] += wx1 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 1] += wx2 * wy2
                    end
                else
                    ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                    iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy] += wx1 * wy1
                        CUDA.@atomic charge[ix, iy + 1] += wx1 * wy2
                        CUDA.@atomic charge[ix, iy + 2] += wx1 * wy3
                        CUDA.@atomic charge[ix + 1, iy] += wx2 * wy1
                        CUDA.@atomic charge[ix + 1, iy + 1] += wx2 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 2] += wx2 * wy3
                        CUDA.@atomic charge[ix + 2, iy] += wx3 * wy1
                        CUDA.@atomic charge[ix + 2, iy + 1] += wx3 * wy2
                        CUDA.@atomic charge[ix + 2, iy + 2] += wx3 * wy3
                    end
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_deposit_drifted_nomask_kernel!(charge, x, px, y, py, drift_s,
                                                          x0, y0, hx, hy,
                                                          nx::Int32, ny::Int32, method_code::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(x)
                xd = x[index] + px[index] * drift_s
                yd = y[index] + py[index] * drift_s
                ux = (xd - x0) * hxi
                uy = (yd - y0) * hyi
                if method_code == 1
                    ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                    iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy] += wx1 * wy1
                        CUDA.@atomic charge[ix + 1, iy] += wx2 * wy1
                        CUDA.@atomic charge[ix, iy + 1] += wx1 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 1] += wx2 * wy2
                    end
                else
                    ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                    iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy] += wx1 * wy1
                        CUDA.@atomic charge[ix, iy + 1] += wx1 * wy2
                        CUDA.@atomic charge[ix, iy + 2] += wx1 * wy3
                        CUDA.@atomic charge[ix + 1, iy] += wx2 * wy1
                        CUDA.@atomic charge[ix + 1, iy + 1] += wx2 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 2] += wx2 * wy3
                        CUDA.@atomic charge[ix + 2, iy] += wx3 * wy1
                        CUDA.@atomic charge[ix + 2, iy + 1] += wx3 * wy2
                        CUDA.@atomic charge[ix + 2, iy + 2] += wx3 * wy3
                    end
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_deposit_drifted_plane_kernel!(charge, plane::Int32, x, px, y, py, drift_s,
                                                         x0, y0, hx, hy,
                                                         nx::Int32, ny::Int32, method_code::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(x)
                xd = x[index] + px[index] * drift_s
                yd = y[index] + py[index] * drift_s
                ux = (xd - x0) * hxi
                uy = (yd - y0) * hyi
                if method_code == 1
                    ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                    iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1
                        CUDA.@atomic charge[ix + 1, iy, plane] += wx2 * wy1
                        CUDA.@atomic charge[ix, iy + 1, plane] += wx1 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 1, plane] += wx2 * wy2
                    end
                else
                    ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                    iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1
                        CUDA.@atomic charge[ix, iy + 1, plane] += wx1 * wy2
                        CUDA.@atomic charge[ix, iy + 2, plane] += wx1 * wy3
                        CUDA.@atomic charge[ix + 1, iy, plane] += wx2 * wy1
                        CUDA.@atomic charge[ix + 1, iy + 1, plane] += wx2 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 2, plane] += wx2 * wy3
                        CUDA.@atomic charge[ix + 2, iy, plane] += wx3 * wy1
                        CUDA.@atomic charge[ix + 2, iy + 1, plane] += wx3 * wy2
                        CUDA.@atomic charge[ix + 2, iy + 2, plane] += wx3 * wy3
                    end
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_deposit_drifted_indexed_plane_kernel!(charge, plane::Int32,
                                                                 x, px, y, py, idx, drift_s,
                                                                 x0, y0, hx, hy,
                                                                 nx::Int32, ny::Int32, method_code::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(idx)
                particle = idx[index]
                xd = x[particle] + px[particle] * drift_s
                yd = y[particle] + py[particle] * drift_s
                ux = (xd - x0) * hxi
                uy = (yd - y0) * hyi
                if method_code == 1
                    ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                    iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1
                        CUDA.@atomic charge[ix + 1, iy, plane] += wx2 * wy1
                        CUDA.@atomic charge[ix, iy + 1, plane] += wx1 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 1, plane] += wx2 * wy2
                    end
                else
                    ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                    iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                    @inbounds begin
                        CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1
                        CUDA.@atomic charge[ix, iy + 1, plane] += wx1 * wy2
                        CUDA.@atomic charge[ix, iy + 2, plane] += wx1 * wy3
                        CUDA.@atomic charge[ix + 1, iy, plane] += wx2 * wy1
                        CUDA.@atomic charge[ix + 1, iy + 1, plane] += wx2 * wy2
                        CUDA.@atomic charge[ix + 1, iy + 2, plane] += wx2 * wy3
                        CUDA.@atomic charge[ix + 2, iy, plane] += wx3 * wy1
                        CUDA.@atomic charge[ix + 2, iy + 1, plane] += wx3 * wy2
                        CUDA.@atomic charge[ix + 2, iy + 2, plane] += wx3 * wy3
                    end
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_deposit_drifted_indexed_plane_pair_kernel!(
            charge, planeL::Int32, planeR::Int32,
            x, px, y, py, idx, driftL, driftR,
            x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
        )
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(idx)
                particle = idx[index]
                xp = x[particle]
                pxp = px[particle]
                yp = y[particle]
                pyp = py[particle]
                _cuda_pic_deposit_point!(
                    charge, planeL, xp + pxp * driftL, yp + pyp * driftL,
                    x0, y0, hxi, hyi, nx, ny, method_code,
                )
                _cuda_pic_deposit_point!(
                    charge, planeR, xp + pxp * driftR, yp + pyp * driftR,
                    x0, y0, hxi, hyi, nx, ny, method_code,
                )
                index += stride
            end
            return nothing
        end

        @inline function _cuda_pic_deposit_point!(charge, plane::Int32, xd, yd,
                                                  x0, y0, hxi, hyi,
                                                  nx::Int32, ny::Int32, method_code::Int32)
            ux = (xd - x0) * hxi
            uy = (yd - y0) * hyi
            if method_code == 1
                ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                @inbounds begin
                    CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1
                    CUDA.@atomic charge[ix + 1, iy, plane] += wx2 * wy1
                    CUDA.@atomic charge[ix, iy + 1, plane] += wx1 * wy2
                    CUDA.@atomic charge[ix + 1, iy + 1, plane] += wx2 * wy2
                end
            else
                ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                @inbounds begin
                    CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1
                    CUDA.@atomic charge[ix, iy + 1, plane] += wx1 * wy2
                    CUDA.@atomic charge[ix, iy + 2, plane] += wx1 * wy3
                    CUDA.@atomic charge[ix + 1, iy, plane] += wx2 * wy1
                    CUDA.@atomic charge[ix + 1, iy + 1, plane] += wx2 * wy2
                    CUDA.@atomic charge[ix + 1, iy + 2, plane] += wx2 * wy3
                    CUDA.@atomic charge[ix + 2, iy, plane] += wx3 * wy1
                    CUDA.@atomic charge[ix + 2, iy + 1, plane] += wx3 * wy2
                    CUDA.@atomic charge[ix + 2, iy + 2, plane] += wx3 * wy3
                end
            end
            return nothing
        end

        @inline function _cuda_pic_bounds_tuple_combine(a::NTuple{N,T}, b::NTuple{N,T}) where {N,T}
            return ntuple(
                row -> isodd(row) ? min(a[row], b[row]) : max(a[row], b[row]),
                Val(N),
            )
        end

        @inline function _cuda_pic_bounds_tuple_shuffle_down(values::NTuple{N,T}, offset) where {N,T}
            shuffled = ntuple(
                row -> CUDA.shfl_down_sync(UInt32(0xffffffff), values[row], offset),
                Val(N),
            )
            return _cuda_pic_bounds_tuple_combine(values, shuffled)
        end

        @inline function _cuda_pic_bounds_block_reduce(values::NTuple{N,T},
                                                       neutral::NTuple{N,T}) where {N,T}
            lane = Int(CUDA.threadIdx().x - 1) % 32 + 1
            warp = Int(CUDA.threadIdx().x - 1) ÷ 32 + 1
            offset = 16
            while offset >= 1
                values = _cuda_pic_bounds_tuple_shuffle_down(values, offset)
                offset ÷= 2
            end

            shared = CUDA.CuStaticSharedArray(T, (N, 32))
            if lane == 1
                for row in 1:N
                    @inbounds shared[row, warp] = values[row]
                end
            end
            CUDA.sync_threads()

            if warp == 1
                nwarps = cld(Int(CUDA.blockDim().x), 32)
                values = ntuple(
                    row -> lane <= nwarps ? (@inbounds shared[row, lane]) : neutral[row],
                    Val(N),
                )
                offset = 16
                while offset >= 1
                    values = _cuda_pic_bounds_tuple_shuffle_down(values, offset)
                    offset ÷= 2
                end
            end
            return values
        end

        function _cuda_pic_init_wavefront_bounds_partials_kernel!(bounds)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            if index <= length(bounds)
                row = (index - 1) % Int32(12) + 1
                T = eltype(bounds)
                @inbounds bounds[index] = isodd(row) ? T(Inf) : -T(Inf)
            end
            return nothing
        end

        function _cuda_pic_force_bounds_indexed_kernel!(
            partials, column::Int32, x, px, y, py, z, idx,
            sL, sR, opposing_center, half,
        )
            neutral = _cuda_pic_bounds_pair_neutral(eltype(x))
            values = neutral
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(idx)
                particle = @inbounds idx[index]
                point = @inbounds _cuda_pic_source_field_bounds_value(
                    x[particle], px[particle], y[particle], py[particle], z[particle],
                    sL, sR, opposing_center, half,
                )
                values = _cuda_pic_bounds_tuple_combine(values, point)
                index += stride
            end
            values = _cuda_pic_bounds_block_reduce(values, neutral)
            if CUDA.threadIdx().x == 1
                block = CUDA.blockIdx().x
                for row in 1:8
                    @inbounds partials[row, block, column] = values[row]
                end
            end
            return nothing
        end

        function _cuda_pic_force_luminosity_bounds_indexed_kernel!(
            partials, column::Int32, x, px, y, py, z, idx,
            sL, sR, opposing_center, half, luminosity_drift,
        )
            T = eltype(x)
            neutral8 = _cuda_pic_bounds_pair_neutral(T)
            neutral = (neutral8..., _cuda_pic_bounds_neutral(T)...)
            values = neutral
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= length(idx)
                particle = @inbounds idx[index]
                point = @inbounds _cuda_pic_source_field_luminosity_bounds_value(
                    x[particle], px[particle], y[particle], py[particle], z[particle],
                    sL, sR, opposing_center, half, luminosity_drift,
                )
                values = _cuda_pic_bounds_tuple_combine(values, point)
                index += stride
            end
            values = _cuda_pic_bounds_block_reduce(values, neutral)
            if CUDA.threadIdx().x == 1
                block = CUDA.blockIdx().x
                for row in 1:12
                    @inbounds partials[row, block, column] = values[row]
                end
            end
            return nothing
        end

        function _cuda_pic_finalize_force_bounds_kernel!(bounds, partials)
            column = CUDA.blockIdx().x
            thread = CUDA.threadIdx().x
            T = eltype(bounds)
            neutral = _cuda_pic_bounds_pair_neutral(T)
            values = ntuple(row -> (@inbounds partials[row, thread, column]), Val(8))
            values = _cuda_pic_bounds_block_reduce(values, neutral)
            if thread == 1
                for row in 1:8
                    @inbounds bounds[row, column] = values[row]
                end
            end
            return nothing
        end

        function _cuda_pic_finalize_force_luminosity_bounds_kernel!(bounds, partials)
            column = CUDA.blockIdx().x
            thread = CUDA.threadIdx().x
            T = eltype(bounds)
            neutral8 = _cuda_pic_bounds_pair_neutral(T)
            neutral = (neutral8..., _cuda_pic_bounds_neutral(T)...)
            values = ntuple(row -> (@inbounds partials[row, thread, column]), Val(12))
            values = _cuda_pic_bounds_block_reduce(values, neutral)
            if thread == 1
                for row in 1:12
                    @inbounds bounds[row, column] = values[row]
                end
            end
            return nothing
        end

        @inline function _cuda_pic_cic_weights(u, n::Int32)
            f0 = floor(u)
            base = Int32(f0) + Int32(1)
            base = max(Int32(1), min(base, n - Int32(1)))
            f = min(max(u - f0, zero(u)), one(u))
            return base, one(f) - f, f
        end

        @inline function _cuda_pic_tsc_weights(u, n::Int32)
            f0 = floor(u)
            ix = Int32(f0)
            f = u - f0
            if f < typeof(u)(0.5)
                t = f * f
                w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t - f)
                w2 = typeof(u)(0.75) - t
                w3 = one(u) - w1 - w2
                base = ix
            else
                fr = one(u) - f
                t = fr * fr
                w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t + fr)
                w2 = typeof(u)(0.75) - t
                w3 = one(u) - w1 - w2
                base = ix + Int32(1)
            end
            base = max(Int32(1), min(base, n - Int32(2)))
            return base, w1, w2, w3
        end

        function _cuda_pic_apply_green_batch_kernel!(spectral, green12, green21)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            n1 = size(spectral, 1)
            n2 = size(spectral, 2)
            plane_size = n1 * n2
            total = length(spectral)
            while index <= total
                plane0 = (index - 1) ÷ plane_size
                local_index = index - plane0 * plane_size
                i = (local_index - 1) % n1 + 1
                j = (local_index - 1) ÷ n1 + 1
                @inbounds begin
                    spectral[index] *= plane0 < 2 ? green12[i, j] : green21[i, j]
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_multiply_spectral_stack_kernel!(spectral, green_spectral)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            n1 = size(spectral, 1)
            n2 = size(spectral, 2)
            plane_size = n1 * n2
            total = length(spectral)
            while index <= total
                plane0 = (index - 1) ÷ plane_size
                local_index = index - plane0 * plane_size
                i = (local_index - 1) % n1 + 1
                j = (local_index - 1) ÷ n1 + 1
                green_plane = plane0 ÷ 2 + 1
                @inbounds spectral[index] *= green_spectral[i, j, green_plane]
                index += stride
            end
            return nothing
        end

        function _cuda_pic_apply_green_plane_kernel!(spectral, green, plane::Int32)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            n1 = size(spectral, 1)
            n2 = size(spectral, 2)
            total = n1 * n2
            while index <= total
                i = (index - 1) % n1 + 1
                j = (index - 1) ÷ n1 + 1
                @inbounds spectral[i, j, plane] *= green[i, j]
                index += stride
            end
            return nothing
        end

        function _cuda_pic_luminosity_overlap_partials_kernel!(
            partials, q1, q2, scale, nx::Int32, ny::Int32,
            blocks_per_pair::Int32, npairs::Int32,
        )
            block0 = CUDA.blockIdx().x - 1
            pair = Int32(block0 ÷ blocks_per_pair + 1)
            local_block = block0 % blocks_per_pair
            tid = CUDA.threadIdx().x
            plane_size = Int(nx) * Int(ny)
            local_index = Int(local_block) * CUDA.blockDim().x + tid
            value = zero(eltype(partials))
            if pair <= npairs && local_index <= plane_size
                i = Int32((local_index - 1) % Int(nx) + 1)
                j = Int32((local_index - 1) ÷ Int(nx) + 1)
                @inbounds value = q1[i, j, pair] * q2[i, j, pair] * scale[pair]
            end
            shared = CUDA.CuDynamicSharedArray(eltype(partials), CUDA.blockDim().x)
            @inbounds shared[tid] = value
            CUDA.sync_threads()
            step = CUDA.blockDim().x ÷ 2
            while step >= 1
                if tid <= step
                    @inbounds shared[tid] += shared[tid + step]
                end
                CUDA.sync_threads()
                step ÷= 2
            end
            if tid == 1
                @inbounds partials[CUDA.blockIdx().x] = shared[1]
            end
            return nothing
        end

        function _cuda_pic_luminosity_wavefront_kernel!(accum, q1, q2, scale,
                                                        nx::Int32, ny::Int32, npairs::Int32)
            linear = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            plane_size = Int(nx) * Int(ny)
            total = plane_size * Int(npairs)
            while linear <= total
                pair0 = (linear - 1) ÷ plane_size
                local_index = linear - pair0 * plane_size
                i = Int32((local_index - 1) % Int(nx) + 1)
                j = Int32((local_index - 1) ÷ Int(nx) + 1)
                plane = Int32(pair0 + 1)
                @inbounds CUDA.@atomic accum[1] += q1[i, j, plane] * q2[i, j, plane] * scale[plane]
                linear += stride
            end
            return nothing
        end

        function _cuda_pic_field_kernel!(Ex, Ey, phi, hx, hy, nx::Int32, ny::Int32)
            linear = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            total = Int(nx) * Int(ny)
            while linear <= total
                i = Int32((linear - 1) % Int(nx) + 1)
                j = Int32((linear - 1) ÷ Int(nx) + 1)
                @inbounds begin
                    if j == 1
                        Ey[i, j] = hyi * (typeof(hy)(1.5) * phi[i, j] - 2 * phi[i, j + 1] + typeof(hy)(0.5) * phi[i, j + 2])
                    elseif j == ny
                        Ey[i, j] = hyi * (-typeof(hy)(1.5) * phi[i, j] + 2 * phi[i, j - 1] - typeof(hy)(0.5) * phi[i, j - 2])
                    else
                        Ey[i, j] = typeof(hy)(0.5) * hyi * (phi[i, j - 1] - phi[i, j + 1])
                    end
                    if i == 1
                        Ex[i, j] = hxi * (typeof(hx)(1.5) * phi[i, j] - 2 * phi[i + 1, j] + typeof(hx)(0.5) * phi[i + 2, j])
                    elseif i == nx
                        Ex[i, j] = hxi * (-typeof(hx)(1.5) * phi[i, j] + 2 * phi[i - 1, j] - typeof(hx)(0.5) * phi[i - 2, j])
                    else
                        Ex[i, j] = typeof(hx)(0.5) * hxi * (phi[i - 1, j] - phi[i + 1, j])
                    end
                end
                linear += stride
            end
            return nothing
        end

        function _cuda_pic_field_wavefront_kernel!(Ex, Ey, phi, hx, hy, nx::Int32, ny::Int32,
                                                  nplanes::Int32)
            linear = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            total_plane = Int(nx) * Int(ny)
            total = total_plane * Int(nplanes)
            while linear <= total
                plane0 = (linear - 1) ÷ total_plane
                local_index = linear - plane0 * total_plane
                i = Int32((local_index - 1) % Int(nx) + 1)
                j = Int32((local_index - 1) ÷ Int(nx) + 1)
                plane = Int32(plane0 + 1)
                hx_plane = hx[plane]
                hy_plane = hy[plane]
                hxi = inv(hx_plane)
                hyi = inv(hy_plane)
                @inbounds begin
                    if j == 1
                        Ey[i, j, plane] = hyi * (typeof(hy_plane)(1.5) * phi[i, j, plane] - 2 * phi[i, j + 1, plane] + typeof(hy_plane)(0.5) * phi[i, j + 2, plane])
                    elseif j == ny
                        Ey[i, j, plane] = hyi * (-typeof(hy_plane)(1.5) * phi[i, j, plane] + 2 * phi[i, j - 1, plane] - typeof(hy_plane)(0.5) * phi[i, j - 2, plane])
                    else
                        Ey[i, j, plane] = typeof(hy_plane)(0.5) * hyi * (phi[i, j - 1, plane] - phi[i, j + 1, plane])
                    end
                    if i == 1
                        Ex[i, j, plane] = hxi * (typeof(hx_plane)(1.5) * phi[i, j, plane] - 2 * phi[i + 1, j, plane] + typeof(hx_plane)(0.5) * phi[i + 2, j, plane])
                    elseif i == nx
                        Ex[i, j, plane] = hxi * (-typeof(hx_plane)(1.5) * phi[i, j, plane] + 2 * phi[i - 1, j, plane] - typeof(hx_plane)(0.5) * phi[i - 2, j, plane])
                    else
                        Ex[i, j, plane] = typeof(hx_plane)(0.5) * hxi * (phi[i - 1, j, plane] - phi[i + 1, j, plane])
                    end
                end
                linear += stride
            end
            return nothing
        end

        function _cuda_pic_field_batch_kernel!(Ex, Ey, phi, hx12, hy12, hx21, hy21,
                                              nx::Int32, ny::Int32)
            linear = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            total_plane = Int(nx) * Int(ny)
            total = total_plane * 4
            while linear <= total
                plane0 = (linear - 1) ÷ total_plane
                local_index = linear - plane0 * total_plane
                i = Int32((local_index - 1) % Int(nx) + 1)
                j = Int32((local_index - 1) ÷ Int(nx) + 1)
                plane = Int32(plane0 + 1)
                hx = plane <= Int32(2) ? hx12 : hx21
                hy = plane <= Int32(2) ? hy12 : hy21
                hxi = inv(hx)
                hyi = inv(hy)
                @inbounds begin
                    if j == 1
                        Ey[i, j, plane] = hyi * (typeof(hy)(1.5) * phi[i, j, plane] - 2 * phi[i, j + 1, plane] + typeof(hy)(0.5) * phi[i, j + 2, plane])
                    elseif j == ny
                        Ey[i, j, plane] = hyi * (-typeof(hy)(1.5) * phi[i, j, plane] + 2 * phi[i, j - 1, plane] - typeof(hy)(0.5) * phi[i, j - 2, plane])
                    else
                        Ey[i, j, plane] = typeof(hy)(0.5) * hyi * (phi[i, j - 1, plane] - phi[i, j + 1, plane])
                    end
                    if i == 1
                        Ex[i, j, plane] = hxi * (typeof(hx)(1.5) * phi[i, j, plane] - 2 * phi[i + 1, j, plane] + typeof(hx)(0.5) * phi[i + 2, j, plane])
                    elseif i == nx
                        Ex[i, j, plane] = hxi * (-typeof(hx)(1.5) * phi[i, j, plane] + 2 * phi[i - 1, j, plane] - typeof(hx)(0.5) * phi[i - 2, j, plane])
                    else
                        Ex[i, j, plane] = typeof(hx)(0.5) * hxi * (phi[i - 1, j, plane] - phi[i + 1, j, plane])
                    end
                end
                linear += stride
            end
            return nothing
        end

        function _cuda_pic_kick_kernel!(outx, outpx, outy, outpy,
                                        fx, fpx, fy, fpy, fz,
                                        phiL, ExL, EyL, phiR, ExR, EyR,
                                        x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
                                        source_center, field_hzi, field_zbias, kbb)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
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
                newpx = fpx[index] + 2 * kbb * Kx
                newpy = fpy[index] + 2 * kbb * Ky
                s2 = typeof(source_center)(0.5) * (source_center - fz[index])
                outx[index] = x + s2 * newpx
                outy[index] = y + s2 * newpy
                outpx[index] = newpx
                outpy[index] = newpy
                index += stride
            end
            return nothing
        end

        function _cuda_pic_kick_longitudinal_kernel!(outx, outpx, outy, outpy, outpz,
                                                     fx, fpx, fy, fpy, fz, fpz,
                                                     phiL, ExL, EyL, phiR, ExR, EyR,
                                                     x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
                                                     source_center, field_hzi, field_zbias, kbb)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            kick_scale = 2 * kbb
            while index <= length(fx)
                oldpx = fpx[index]
                oldpy = fpy[index]
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
                newpx = oldpx + kick_scale * Kx
                newpy = oldpy + kick_scale * Ky
                pz += kick_scale * Kz * field_hzi
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

        function _cuda_pic_kick_indexed_kernel!(xarr, pxarr, yarr, pyarr, zarr, idx,
                                                phiL, ExL, EyL, phiR, ExR, EyR,
                                                x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
                                                source_center, field_hzi, field_zbias, kbb)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            while index <= length(idx)
                particle = idx[index]
                oldx = xarr[particle]
                oldpx = pxarr[particle]
                oldy = yarr[particle]
                oldpy = pyarr[particle]
                oldz = zarr[particle]
                s1 = typeof(source_center)(0.5) * (oldz - source_center)
                x = oldx + oldpx * s1
                y = oldy + oldpy * s1
                zL = -oldz * field_hzi + field_zbias
                zL = min(max(zL, zero(zL)), one(zL))
                zR = one(zL) - zL
                Kx, Ky = _cuda_pic_interpolate_field(
                    method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                    phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
                )
                newpx = oldpx + 2 * kbb * Kx
                newpy = oldpy + 2 * kbb * Ky
                s2 = typeof(source_center)(0.5) * (source_center - oldz)
                xarr[particle] = x + s2 * newpx
                yarr[particle] = y + s2 * newpy
                pxarr[particle] = newpx
                pyarr[particle] = newpy
                index += stride
            end
            return nothing
        end

        function _cuda_pic_kick_indexed_longitudinal_kernel!(xarr, pxarr, yarr, pyarr, pzarr, zarr, idx,
                                                             phiL, ExL, EyL, phiR, ExR, EyR,
                                                             x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
                                                             source_center, field_hzi, field_zbias, kbb)
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            hxi = inv(hx)
            hyi = inv(hy)
            kick_scale = 2 * kbb
            while index <= length(idx)
                particle = idx[index]
                oldx = xarr[particle]
                oldpx = pxarr[particle]
                oldy = yarr[particle]
                oldpy = pyarr[particle]
                oldz = zarr[particle]
                oldpz = pzarr[particle]
                s1 = typeof(source_center)(0.5) * (oldz - source_center)
                x = oldx + oldpx * s1
                y = oldy + oldpy * s1
                pz = oldpz - typeof(source_center)(0.25) * (oldpx * oldpx + oldpy * oldpy)
                zL = -oldz * field_hzi + field_zbias
                zL = min(max(zL, zero(zL)), one(zL))
                zR = one(zL) - zL
                Kx, Ky, Kz = _cuda_pic_interpolate_kick(
                    method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                    phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
                )
                newpx = oldpx + kick_scale * Kx
                newpy = oldpy + kick_scale * Ky
                pz += kick_scale * Kz * field_hzi
                s2 = typeof(source_center)(0.5) * (source_center - oldz)
                xarr[particle] = x + s2 * newpx
                yarr[particle] = y + s2 * newpy
                pxarr[particle] = newpx
                pyarr[particle] = newpy
                pzarr[particle] = pz + typeof(source_center)(0.25) * (newpx * newpx + newpy * newpy)
                index += stride
            end
            return nothing
        end

        function _cuda_pic_kick_pair_indexed_kernel!(
            x1, px1, y1, py1, z1, idx1,
            x2, px2, y2, py2, z2, idx2,
            phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
            phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
            x01, y01, hx1, hy1, x02, y02, hx2, hy2,
            nx::Int32, ny::Int32, method_code::Int32,
            source_center1, field_hzi1, field_zbias1, kbb1,
            source_center2, field_hzi2, field_zbias2, kbb2,
        )
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while index <= max(length(idx1), length(idx2))
                if index <= length(idx2)
                    _cuda_pic_apply_indexed_kick!(
                        x2, px2, y2, py2, z2, idx2[index],
                        phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                        x02, y02, hx2, hy2, nx, ny, method_code,
                        source_center2, field_hzi2, field_zbias2, kbb2,
                    )
                end
                if index <= length(idx1)
                    _cuda_pic_apply_indexed_kick!(
                        x1, px1, y1, py1, z1, idx1[index],
                        phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                        x01, y01, hx1, hy1, nx, ny, method_code,
                        source_center1, field_hzi1, field_zbias1, kbb1,
                    )
                end
                index += stride
            end
            return nothing
        end

        function _cuda_pic_kick_pair_indexed_longitudinal_kernel!(
            x1, px1, y1, py1, pz1, z1, idx1,
            x2, px2, y2, py2, pz2, z2, idx2,
            phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
            phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
            x01, y01, hx1, hy1, x02, y02, hx2, hy2,
            nx::Int32, ny::Int32, method_code::Int32,
            source_center1, field_hzi1, field_zbias1, kbb1,
            source_center2, field_hzi2, field_zbias2, kbb2,
        )
            index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            if index <= length(idx2)
                _cuda_pic_apply_indexed_longitudinal_kick!(
                    x2, px2, y2, py2, pz2, z2, idx2[index],
                    phi12L, Ex12L, Ey12L, phi12R, Ex12R, Ey12R,
                    x02, y02, hx2, hy2, nx, ny, method_code,
                    source_center2, field_hzi2, field_zbias2, kbb2,
                )
            end
            if index <= length(idx1)
                _cuda_pic_apply_indexed_longitudinal_kick!(
                    x1, px1, y1, py1, pz1, z1, idx1[index],
                    phi21L, Ex21L, Ey21L, phi21R, Ex21R, Ey21R,
                    x01, y01, hx1, hy1, nx, ny, method_code,
                    source_center1, field_hzi1, field_zbias1, kbb1,
                )
            end
            return nothing
        end

        @inline function _cuda_pic_apply_indexed_kick!(
            xarr, pxarr, yarr, pyarr, zarr, particle,
            phiL, ExL, EyL, phiR, ExR, EyR,
            x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
            source_center, field_hzi, field_zbias, kbb,
        )
            hxi = inv(hx)
            hyi = inv(hy)
            oldx = xarr[particle]
            oldpx = pxarr[particle]
            oldy = yarr[particle]
            oldpy = pyarr[particle]
            oldz = zarr[particle]
            s1 = typeof(source_center)(0.5) * (oldz - source_center)
            x = oldx + oldpx * s1
            y = oldy + oldpy * s1
            zL = -oldz * field_hzi + field_zbias
            zL = min(max(zL, zero(zL)), one(zL))
            zR = one(zL) - zL
            Kx, Ky = _cuda_pic_interpolate_field(
                method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
            )
            newpx = oldpx + 2 * kbb * Kx
            newpy = oldpy + 2 * kbb * Ky
            s2 = typeof(source_center)(0.5) * (source_center - oldz)
            xarr[particle] = x + s2 * newpx
            yarr[particle] = y + s2 * newpy
            pxarr[particle] = newpx
            pyarr[particle] = newpy
            return nothing
        end

        @inline function _cuda_pic_apply_indexed_longitudinal_kick!(
            xarr, pxarr, yarr, pyarr, pzarr, zarr, particle,
            phiL, ExL, EyL, phiR, ExR, EyR,
            x0, y0, hx, hy, nx::Int32, ny::Int32, method_code::Int32,
            source_center, field_hzi, field_zbias, kbb,
        )
            hxi = inv(hx)
            hyi = inv(hy)
            kick_scale = 2 * kbb
            oldx = xarr[particle]
            oldpx = pxarr[particle]
            oldy = yarr[particle]
            oldpy = pyarr[particle]
            oldz = zarr[particle]
            oldpz = pzarr[particle]
            s1 = typeof(source_center)(0.5) * (oldz - source_center)
            x = oldx + oldpx * s1
            y = oldy + oldpy * s1
            pz = oldpz - typeof(source_center)(0.25) * (oldpx * oldpx + oldpy * oldpy)
            zL = -oldz * field_hzi + field_zbias
            zL = min(max(zL, zero(zL)), one(zL))
            zR = one(zL) - zL
            Kx, Ky, Kz = _cuda_pic_interpolate_kick(
                method_code, x, y, x0, y0, hxi, hyi, nx, ny,
                phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
            )
            newpx = oldpx + kick_scale * Kx
            newpy = oldpy + kick_scale * Ky
            pz += kick_scale * Kz * field_hzi
            s2 = typeof(source_center)(0.5) * (source_center - oldz)
            xarr[particle] = x + s2 * newpx
            yarr[particle] = y + s2 * newpy
            pxarr[particle] = newpx
            pyarr[particle] = newpy
            pzarr[particle] = pz + typeof(source_center)(0.25) * (newpx * newpx + newpy * newpy)
            return nothing
        end

        @inline function _cuda_pic_interpolate_field(method_code::Int32, x, y, x0, y0, hxi, hyi,
                                                     nx::Int32, ny::Int32,
                                                     phiL, ExL, EyL, phiR, ExR, EyR, zL, zR)
            ux = (x - x0) * hxi
            uy = (y - y0) * hyi
            Kx = zero(x)
            Ky = zero(x)
            if method_code == 1
                ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                @inbounds begin
                    w = wx1 * wy1
                    Kx += w * (zL * ExL[ix, iy] + zR * ExR[ix, iy])
                    Ky += w * (zL * EyL[ix, iy] + zR * EyR[ix, iy])
                    w = wx2 * wy1
                    Kx += w * (zL * ExL[ix + 1, iy] + zR * ExR[ix + 1, iy])
                    Ky += w * (zL * EyL[ix + 1, iy] + zR * EyR[ix + 1, iy])
                    w = wx1 * wy2
                    Kx += w * (zL * ExL[ix, iy + 1] + zR * ExR[ix, iy + 1])
                    Ky += w * (zL * EyL[ix, iy + 1] + zR * EyR[ix, iy + 1])
                    w = wx2 * wy2
                    Kx += w * (zL * ExL[ix + 1, iy + 1] + zR * ExR[ix + 1, iy + 1])
                    Ky += w * (zL * EyL[ix + 1, iy + 1] + zR * EyR[ix + 1, iy + 1])
                end
            else
                ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                wx = (wx1, wx2, wx3)
                wy = (wy1, wy2, wy3)
                for m in 1:3, n in 1:3
                    @inbounds begin
                        w = wx[m] * wy[n]
                        ii = ix + Int32(m - 1)
                        jj = iy + Int32(n - 1)
                        Kx += w * (zL * ExL[ii, jj] + zR * ExR[ii, jj])
                        Ky += w * (zL * EyL[ii, jj] + zR * EyR[ii, jj])
                    end
                end
            end
            return Kx, Ky
        end

        @inline function _cuda_pic_interpolate_kick(method_code::Int32, x, y, x0, y0, hxi, hyi,
                                                    nx::Int32, ny::Int32,
                                                    phiL, ExL, EyL, phiR, ExR, EyR, zL, zR)
            ux = (x - x0) * hxi
            uy = (y - y0) * hyi
            Kx = zero(x)
            Ky = zero(x)
            Kz = zero(x)
            if method_code == 1
                ix, wx1, wx2 = _cuda_pic_cic_weights(ux, nx)
                iy, wy1, wy2 = _cuda_pic_cic_weights(uy, ny)
                @inbounds begin
                    w = wx1 * wy1
                    Kx += w * (zL * ExL[ix, iy] + zR * ExR[ix, iy])
                    Ky += w * (zL * EyL[ix, iy] + zR * EyR[ix, iy])
                    Kz += w * (phiL[ix, iy] - phiR[ix, iy])
                    w = wx2 * wy1
                    Kx += w * (zL * ExL[ix + 1, iy] + zR * ExR[ix + 1, iy])
                    Ky += w * (zL * EyL[ix + 1, iy] + zR * EyR[ix + 1, iy])
                    Kz += w * (phiL[ix + 1, iy] - phiR[ix + 1, iy])
                    w = wx1 * wy2
                    Kx += w * (zL * ExL[ix, iy + 1] + zR * ExR[ix, iy + 1])
                    Ky += w * (zL * EyL[ix, iy + 1] + zR * EyR[ix, iy + 1])
                    Kz += w * (phiL[ix, iy + 1] - phiR[ix, iy + 1])
                    w = wx2 * wy2
                    Kx += w * (zL * ExL[ix + 1, iy + 1] + zR * ExR[ix + 1, iy + 1])
                    Ky += w * (zL * EyL[ix + 1, iy + 1] + zR * EyR[ix + 1, iy + 1])
                    Kz += w * (phiL[ix + 1, iy + 1] - phiR[ix + 1, iy + 1])
                end
            else
                ix, wx1, wx2, wx3 = _cuda_pic_tsc_weights(ux, nx)
                iy, wy1, wy2, wy3 = _cuda_pic_tsc_weights(uy, ny)
                wx = (wx1, wx2, wx3)
                wy = (wy1, wy2, wy3)
                for m in 1:3, n in 1:3
                    @inbounds begin
                        w = wx[m] * wy[n]
                        ii = ix + Int32(m - 1)
                        jj = iy + Int32(n - 1)
                        Kx += w * (zL * ExL[ii, jj] + zR * ExR[ii, jj])
                        Ky += w * (zL * EyL[ii, jj] + zR * EyR[ii, jj])
                        Kz += w * (phiL[ii, jj] - phiR[ii, jj])
                    end
                end
            end
            return Kx, Ky, Kz
        end

        function collide!(solver::GaussianPoissonSolver, beam1::Beam, beam2::Beam,
                          ::Type{CUDABackend})
            if solver.batch_mode == :wavefront
                return _cuda_gaussian_collide_wavefront!(solver, beam1, beam2)
            end
            return _cuda_gaussian_collide_sequential!(solver, beam1, beam2)
        end

        function _cuda_gaussian_collide_sequential!(
                solver::GaussianPoissonSolver{ST,D,COUPLED,LONGITUDINAL}, beam1::Beam,
                beam2::Beam) where {ST,D,COUPLED,LONGITUDINAL}
            slices1 = _cuda_longitudinal_slices(beam1.rep, solver.slicing1)
            slices2 = _cuda_longitudinal_slices(beam2.rep, solver.slicing2)
            kbb1 = _strong_strong_kbb1(solver, beam1, beam2)
            kbb2 = _strong_strong_kbb2(solver, beam1, beam2)
            klum1, klum2 = _strong_strong_luminosity_scales(solver, beam1, beam2)
            T = eltype(beam1.rep.x)
            sample_beam1 = solver.gaussian_when_luminosity == 1
            sampled_indices = sample_beam1 ? slices2.indices : slices1.indices
            max_sampled_slice = maximum(length, sampled_indices; init=0)
            lum = CUDA.CuArray{T}(undef, max(max_sampled_slice, 1))
            all_indices = Iterators.flatten((slices1.indices, slices2.indices))
            max_moment_blocks = maximum(
                idx -> _cuda_gaussian_moment_launch(length(idx)).blocks, all_indices; init=1)
            nstats = COUPLED ? 14 : 10
            moment_partials = CUDA.CuArray{T}(undef, nstats, max_moment_blocks, 1)
            luminosity = zero(T)
            for (_, i, j) in _slice_collision_order(slices1, slices2)
                moments1 = _cuda_slice_transverse_moments(
                    beam1.rep, slices1.indices[i], moment_partials,
                    solver.ignore_centroid1, solver.min_sigma, Val(COUPLED),
                )
                moments2 = _cuda_slice_transverse_moments(
                    beam2.rep, slices2.indices[j], moment_partials,
                    solver.ignore_centroid2, solver.min_sigma, Val(COUPLED),
                )
                launch1 = _active_cuda_launch(length(slices1.indices[i]))
                launch2 = _active_cuda_launch(length(slices2.indices[j]))
                CUDA.@cuda threads=launch1.threads blocks=launch1.blocks _cuda_slice_kick_kernel!(
                    beam1.rep, slices1.indices[i], lum,
                    moments2, slices2.center[j],
                    slices2.weight[j] * kbb1,
                    solver.virtual_drift, Val(LONGITUDINAL),
                    Val(!sample_beam1), 0, one(T),
                )
                CUDA.@cuda threads=launch2.threads blocks=launch2.blocks _cuda_slice_kick_kernel!(
                    beam2.rep, slices2.indices[j], lum,
                    moments1, slices1.center[i],
                    slices1.weight[i] * kbb2,
                    solver.virtual_drift, Val(LONGITUDINAL),
                    Val(sample_beam1), 0, one(T),
                )
                if sample_beam1
                    luminosity += sum(@view lum[1:length(slices2.indices[j])]) /
                                  TWOPI * slices1.weight[i] * klum2
                else
                    luminosity += sum(@view lum[1:length(slices1.indices[i])]) /
                                  TWOPI * slices2.weight[j] * klum1
                end
            end
            return luminosity
        end

        function _cuda_longitudinal_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
            slicing.nslices > 0 || throw(ArgumentError("nslices must be positive"))
            isempty(rep.z) && throw(ArgumentError("longitudinal slicing requires at least one particle"))
            method = slicing.method
            if method == :equal_width || method == :equal_spaced
                return _cuda_equal_width_slices(rep, slicing)
            elseif method == :equal_area
                return _cuda_equal_area_slices(rep, slicing)
            elseif method == :normal_quantile || method == :gaussian || method == :Gaussian
                return _cuda_gaussian_slices(rep, slicing)
            elseif method == :specified
                return _cuda_specified_slices(rep, slicing)
            elseif method == :equal_count
                return _cuda_equal_count_slices(rep, slicing)
            else
                throw(ArgumentError("unknown longitudinal slicing method $method"))
            end
        end

        function _cuda_equal_width_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
            z = rep.z
            T = eltype(z)
            ns = slicing.nslices
            zmin = T(minimum(z))
            zmax = T(maximum(z))
            boundaries = collect(range(zmin, zmax; length=ns + 1))
            return _cuda_slices_from_boundaries(rep, slicing, boundaries)
        end

        function _cuda_equal_area_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
            slicing.resolution > 0 || throw(ArgumentError("resolution must be positive"))
            z = rep.z
            T = eltype(z)
            ns = slicing.nslices
            bins = ns * slicing.resolution
            zmin = T(minimum(z))
            zmax = T(maximum(z))
            if zmin == zmax
                return _cuda_slices_from_boundaries(rep, slicing, fill(T(zmin), ns + 1))
            end
            width = (zmax - zmin) / bins
            counts = Vector{Int}(undef, bins)
            for b in 1:bins
                lb = T(zmin + (b - 1) * width)
                rb = T(zmin + b * width)
                mask = b == bins ? ((z .>= lb) .& (z .<= rb)) : ((z .>= lb) .& (z .< rb))
                counts[b] = Int(sum(mask))
            end
            cumulative = cumsum(counts) ./ length(z)
            cumulative[end] = one(T)
            centers = [T(zmin + (i - 0.5) * width) for i in 1:bins]
            boundaries = Vector{T}(undef, ns + 1)
            boundaries[1] = T(zmin)
            boundaries[end] = T(zmax)
            current = 1
            for s in 1:(ns - 1)
                target = s / ns
                while current <= bins && cumulative[current] <= target
                    current += 1
                end
                if current <= 1
                    x1 = boundaries[1]
                    x2 = centers[1]
                    y1 = zero(T)
                    y2 = cumulative[1]
                elseif current > bins
                    x1 = centers[end]
                    x2 = boundaries[end]
                    y1 = cumulative[end - 1]
                    y2 = one(T)
                else
                    x1 = centers[current - 1]
                    x2 = centers[current]
                    y1 = cumulative[current - 1]
                    y2 = cumulative[current]
                end
                boundaries[s + 1] = y2 == y1 ? (x1 + x2) / 2 :
                                    x2 * (target - y1) / (y2 - y1) +
                                    x1 * (target - y2) / (y1 - y2)
            end
            return _cuda_slices_from_boundaries(rep, slicing, boundaries)
        end

        function _cuda_specified_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
            z = rep.z
            T = eltype(z)
            zmin = T(minimum(z))
            zmax = T(maximum(z))
            n = T(length(rep))
            μ = T(sum(z) / n)
            σ = sqrt(max(T(sum((z .- μ) .* (z .- μ)) / n), zero(T)))
            internal = sort([T(μ + p * σ) for p in slicing.positions])
            boundaries = Vector{T}(undef, length(internal) + 2)
            boundaries[1] = zmin
            boundaries[end] = zmax
            for (i, b) in enumerate(internal)
                boundaries[i + 1] = clamp(b, zmin, zmax)
            end
            return _cuda_slices_from_boundaries(rep, slicing, boundaries)
        end

        function _cuda_gaussian_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
            z = rep.z
            T = eltype(z)
            ns = slicing.nslices
            zmin = T(minimum(z))
            zmax = T(maximum(z))
            n = T(length(rep))
            μ = T(sum(z) / n)
            σ = sqrt(max(T(sum((z .- μ) .* (z .- μ)) / n), zero(T)))
            if σ == zero(T)
                return _cuda_slices_from_boundaries(rep, slicing, fill(T(μ), ns + 1))
            end
            boundaries = _gaussian_slice_boundaries(T, ns, μ, σ, zmin, zmax)
            return _cuda_slices_from_boundaries(rep, slicing, boundaries)
        end

        function _cuda_equal_count_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
            z_host = Array(rep.z)
            T = eltype(z_host)
            n = length(z_host)
            ns = slicing.nslices
            order = sortperm(z_host)
            sorted_z = z_host[order]
            boundaries = Vector{T}(undef, ns + 1)
            boundaries[1] = minimum(z_host)
            boundaries[end] = maximum(z_host)
            for s in 1:(ns - 1)
                pos = floor(Int, s * n / ns)
                boundaries[s + 1] = if pos == 0
                    sorted_z[1]
                elseif pos == n
                    sorted_z[end]
                else
                    (sorted_z[pos] + sorted_z[pos + 1]) / 2
                end
            end
            return _cuda_slices_from_boundaries(rep, slicing, boundaries)
        end

        function _cuda_slices_from_boundaries(rep::Phase6DRep, slicing::LongitudinalSlicing, boundaries)
            z = rep.z
            T = eltype(z)
            ns = length(boundaries) - 1
            centers = Vector{T}(undef, ns)
            weights = Vector{T}(undef, ns)
            indices = Vector{Any}(undef, ns)
            for s in 1:ns
                lb = boundaries[s]
                rb = boundaries[s + 1]
                include_hi = s == ns
                mask = include_hi ? ((z .>= lb) .& (z .<= rb)) : ((z .>= lb) .& (z .< rb))
                idx = _cuda_indices_from_mask(mask)
                count = length(idx)
                indices[s] = idx
                weights[s] = T(count) / T(length(rep))
                if slicing.center_position == :centroid
                    centers[s] = count == 0 ? (lb + rb) / 2 : T(sum(ifelse.(mask, z, zero(T))) / count)
                elseif slicing.center_position == :midpoint
                    centers[s] = (lb + rb) / 2
                else
                    throw(ArgumentError("unknown slice center_position $(slicing.center_position)"))
                end
            end
            return LongitudinalSlices(centers, weights, boundaries, indices)
        end

        function _cuda_slice_transverse_moments(rep::Phase6DRep, idx, partials,
                                                ignore_centroid::Bool, min_sigma,
                                                coupled::Val{COUPLED}) where {COUPLED}
            T = eltype(rep.x)
            n = length(idx)
            n == 0 && return _cuda_gaussian_moments_from_sums(
                zeros(T, COUPLED ? 14 : 10), n, ignore_centroid, min_sigma, coupled)
            blocks = _cuda_launch_gaussian_moment_partials!(
                partials, 1, rep, idx, coupled)
            host_partials = Array(@view partials[:, 1:blocks, 1])
            sums = vec(sum(host_partials; dims=2))
            return _cuda_gaussian_moments_from_sums(
                sums, n, ignore_centroid, min_sigma, coupled)
        end

        function _cuda_gaussian_moments_from_sums(sums, n::Integer,
                                                   ignore_centroid::Bool,
                                                   min_sigma,
                                                   ::Val{COUPLED}) where {COUPLED}
            T = eltype(sums)
            if n == 0
                zz = zero(T)
                floor2 = T(min_sigma) * T(min_sigma)
                moments = StrongTransverseMoments{T,COUPLED}(
                    floor2, zz, floor2, zz, zz, zz, zz, zz, zz, zz)
                return (mx=zz, sx=T(min_sigma), mpx=zz, spx=zz, covxpx=zz,
                        my=zz, sy=T(min_sigma), mpy=zz, spy=zz, covypy=zz,
                        moments=moments)
            end
            sx, spx, sy, spy = sums[1], sums[2], sums[3], sums[4]
            sx2sum, spx2sum = sums[5], sums[6]
            sy2sum, spy2sum = sums[7], sums[8]
            sxpxsum, sypysum = sums[9], sums[10]
            invn = inv(T(n))
            mx = T(sx * invn)
            mpx = T(spx * invn)
            my = T(sy * invn)
            mpy = T(spy * invn)
            sx2 = T(sx2sum * invn - mx * mx)
            spx2 = T(spx2sum * invn - mpx * mpx)
            sy2 = T(sy2sum * invn - my * my)
            spy2 = T(spy2sum * invn - mpy * mpy)
            covxpx = T(sxpxsum * invn - mx * mpx)
            covypy = T(sypysum * invn - my * mpy)
            covxy = COUPLED ? T(sums[11] * invn - mx * my) : zero(T)
            covxpy = COUPLED ? T(sums[12] * invn - mx * mpy) : zero(T)
            covpxy = COUPLED ? T(sums[13] * invn - mpx * my) : zero(T)
            covpxpy = COUPLED ? T(sums[14] * invn - mpx * mpy) : zero(T)
            floor2 = T(min_sigma) * T(min_sigma)
            varx = max(sx2, floor2)
            vary = max(sy2, floor2)
            moments = StrongTransverseMoments{T,COUPLED}(
                varx, covxy, vary, covxpx, covxpy, covpxy, covypy,
                max(spx2, zero(T)), covpxpy, max(spy2, zero(T)))
            if ignore_centroid
                mx = zero(T); mpx = zero(T); my = zero(T); mpy = zero(T)
            end
            return (
                mx=mx, sx=sqrt(varx),
                mpx=mpx, spx=sqrt(max(spx2, zero(T))), covxpx=covxpx,
                my=my, sy=sqrt(vary),
                mpy=mpy, spy=sqrt(max(spy2, zero(T))), covypy=covypy,
                moments=moments,
            )
        end

        function _cuda_launch_gaussian_moment_partials!(
                partials, column::Integer, rep::Phase6DRep, idx,
                ::Val{COUPLED}) where {COUPLED}
            launch = _cuda_gaussian_moment_launch(length(idx))
            nstats = COUPLED ? 14 : 10
            shmem = nstats * launch.threads * sizeof(eltype(partials))
            CUDA.@cuda threads=launch.threads blocks=launch.blocks shmem=shmem _cuda_gaussian_moment_partials_kernel!(
                    partials, rep.x, rep.px, rep.y, rep.py, idx, column,
                    Val(COUPLED))
            return launch.blocks
        end

        function _cuda_gaussian_moment_launch(n::Integer)
            requested = _active_cuda_launch(n)
            # Fourteen shared Float64 accumulators per thread make 256 the
            # portable ceiling even for the optional coupled path.
            threads = min(requested.threads, 256)
            coverage_blocks = max(cld(Int(n), threads), 1)
            blocks = max(requested.blocks, min(coverage_blocks, 256))
            return (threads=threads, blocks=blocks)
        end

        function _cuda_gaussian_moment_partials_kernel!(partials, x, px, y, py,
                                                        idx, column,
                                                        ::Val{COUPLED}) where {COUPLED}
            T = eltype(partials)
            nstats = COUPLED ? 14 : 10
            values = ntuple(_ -> zero(T), Val(nstats))
            position = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            while position <= length(idx)
                @inbounds begin
                    particle = idx[position]
                    xi = x[particle]; pxi = px[particle]
                    yi = y[particle]; pyi = py[particle]
                    if COUPLED
                        values = (
                            values[1] + xi, values[2] + pxi,
                            values[3] + yi, values[4] + pyi,
                            values[5] + xi * xi, values[6] + pxi * pxi,
                            values[7] + yi * yi, values[8] + pyi * pyi,
                            values[9] + xi * pxi, values[10] + yi * pyi,
                            values[11] + xi * yi, values[12] + xi * pyi,
                            values[13] + pxi * yi, values[14] + pxi * pyi,
                        )
                    else
                        values = (
                            values[1] + xi, values[2] + pxi,
                            values[3] + yi, values[4] + pyi,
                            values[5] + xi * xi, values[6] + pxi * pxi,
                            values[7] + yi * yi, values[8] + pyi * pyi,
                            values[9] + xi * pxi, values[10] + yi * pyi,
                        )
                    end
                end
                position += stride
            end
            shared = CUDA.CuDynamicSharedArray(T, nstats * CUDA.blockDim().x)
            base = nstats * (CUDA.threadIdx().x - 1)
            for stat in 1:nstats
                @inbounds shared[base + stat] = values[stat]
            end
            CUDA.sync_threads()
            active = CUDA.blockDim().x
            while active > 1
                offset = (active + 1) ÷ 2
                if CUDA.threadIdx().x <= active ÷ 2
                    other = nstats * (CUDA.threadIdx().x + offset - 1)
                    for stat in 1:nstats
                        @inbounds shared[base + stat] += shared[other + stat]
                    end
                end
                CUDA.sync_threads()
                active = offset
            end
            if CUDA.threadIdx().x == 1
                for stat in 1:nstats
                    @inbounds partials[stat, CUDA.blockIdx().x, column] = shared[stat]
                end
            end
            return nothing
        end

        function _cuda_gaussian_reduce_partials_kernel!(sums, partials,
                                                         block_counts, nstats,
                                                         ncolumns)
            linear = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            total = nstats * ncolumns
            while linear <= total
                stat = (linear - 1) % nstats + 1
                column = (linear - 1) ÷ nstats + 1
                value = zero(eltype(sums))
                nblocks = block_counts[column]
                for block in 1:nblocks
                    @inbounds value += partials[stat, block, column]
                end
                @inbounds sums[stat, column] = value
                linear += stride
            end
            return nothing
        end

        function _cuda_slice_kick_kernel!(rep, idx, lum, moments2, center2,
                                          kbb_slice, virtual_drift,
                                          longitudinal_kick::Val{LONGITUDINAL},
                                          ::Val{COMPUTE_LUMINOSITY}, lum_offset,
                                          lum_scale) where {LONGITUDINAL,COMPUTE_LUMINOSITY}
            start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
            stride = CUDA.gridDim().x * CUDA.blockDim().x
            position = start_index
            while position <= length(idx)
                @inbounds begin
                    index = idx[position]
                    x = rep.x[index]; px = rep.px[index]
                    y = rep.y[index]; py = rep.py[index]
                    z = rep.z[index]; pz = rep.pz[index]
                    drift = _soft_gaussian_drift(virtual_drift, longitudinal_kick)
                    x, px, y, py, z, pz, S = _forward_virtual_drift(
                        drift, x, px, y, py, z, pz, center2)
                    xx = x - moments2.mx + moments2.mpx * S
                    yy = y - moments2.my + moments2.mpy * S
                    px0, py0, pz0 = px, py, pz
                    x, px, y, py, z, pz, density = _cuda_cp_covariance_kick(
                        moments2.moments, kbb_slice, S, xx, yy,
                        x, px, y, py, z, pz)
                    if LONGITUDINAL
                        pz += 0.5 * ((px - px0) * moments2.mpx +
                                    (py - py0) * moments2.mpy)
                    else
                        pz = pz0
                    end
                    x, px, y, py, z, pz = _reverse_virtual_drift(
                        drift, x, px, y, py, z, pz, center2)
                    rep.x[index] = x; rep.px[index] = px
                    rep.y[index] = y; rep.py[index] = py
                    rep.z[index] = z; rep.pz[index] = pz
                    if COMPUTE_LUMINOSITY
                        lum[lum_offset + position] = density * TWOPI * lum_scale
                    end
                end
                position += stride
            end
            return nothing
        end
    end
else
    function collide!(solver::GaussianPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend})
        error("CUDABackend requires CUDA.jl to be available.")
    end
    function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CUDABackend})
        error("CUDABackend requires CUDA.jl to be available.")
    end
end
