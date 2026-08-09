function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end

function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                  ctx::Nothing)
    return _pic_collide!(solver, beam1, beam2, ctx)
end

function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                  ctx::TrackingContext)
    return _pic_collide!(solver, beam1, beam2, ctx)
end

function _pic_collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ctx)
    T = _pic_cpu_scalar_type(solver, beam1, beam2)
    nx, ny = solver.grid
    workspaces = [_pic_cpu_workspace(T, nx, ny) for _ in 1:_pic_pool_size(solver)]
    green_cache = _pic_green_cache(solver, T)
    return _pic_collide!(solver, beam1, beam2, ctx, workspaces, green_cache)
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::PICPoissonSolver,
                                 beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                 ctx::TrackingContext)
    T = _pic_cpu_scalar_type(solver, beam1, beam2)
    workspaces = _pic_cpu_workspace_pool!(task.runtime_cache, label, solver, T,
                                          _pic_pool_size(solver))
    green_cache = _pic_green_cache!(task.runtime_cache, label, solver, T)
    return _pic_collide!(solver, beam1, beam2, ctx, workspaces, green_cache)
end

"""
Whether the CPU PIC pair loop may run its pairs in conflict-free batches.

`interaction_grid = :source_slice` may NOT, and this is the one place the
distinction is made. Its mesh comes from `_pic_union_bounds`, a union over the
**whole** partner beam evaluated at the source slice's first use, so its value
depends on how much of the turn has already been applied — and
`collision_pair_batches` preserves each slice's own collision order but not the
global one, so "how much has been applied" is exactly what batching changes.

The other two modes are schedule-independent by construction, which is why the
batched path reproduces the sequential result bit for bit rather than merely
approximating it:

- `:slice_pair` (the default) sizes its mesh from the two slices of its own
  pair, and the batcher preserves their relative order.
- `:node` builds every mesh at turn start in `_pic_prebuild_node_caches!` —
  written for precisely this hazard, after lazy building made CPU and the CUDA
  wavefront route disagree by 3.8e-5.
"""
_pic_batchable(solver::PICPoissonSolver) = !_pic_source_slice_grid(solver)

# Upper bound on the width of a conflict-free batch: no batch repeats a beam-1
# or a beam-2 slice, so it cannot be wider than the smaller slice count. Sizing
# the pool past that would allocate workspaces (~8 MB each at grid 128) that no
# schedule can ever hand work to. `:specified` slicing takes its count from the
# internal boundary list, so both sources are consulted rather than `nslices`
# alone.
_pic_slice_count_bound(slicing::LongitudinalSlicing) =
    max(slicing.nslices, length(slicing.positions) + 1)

function _pic_pool_size(solver::PICPoissonSolver)
    _pic_batchable(solver) || return 1
    width = min(_pic_slice_count_bound(solver.slicing1),
                _pic_slice_count_bound(solver.slicing2))
    return clamp(_cpu_worker_count(), 1, max(width, 1))
end

_strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                solver::PICPoissonSolver,
                                beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                ctx::TrackingContext) =
    _strong_strong_collide!(task, label, solver, beam1, beam2, CPUThreadsBackend, ctx)

_pic_collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ctx,
              workspace::_PICCPUWorkspace, green_cache) =
    _pic_collide!(solver, beam1, beam2, ctx, (workspace,), green_cache)

function _pic_collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ctx,
                       workspaces, green_cache)
    _validate_pic_solver(solver)
    isempty(workspaces) && throw(ArgumentError(
        "PIC CPU collide needs at least one scratch workspace; got an empty pool."))
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _pic_kbb1(solver, beam1, beam2)
    kbb2 = _pic_kbb2(solver, beam1, beam2)
    klum = _pic_luminosity_scale(solver, beam1, beam2)
    compute_luminosity = _pic_compute_luminosity(solver, ctx)
    T = promote_type(eltype(beam1.rep.x), eltype(beam2.rep.x), typeof(kbb1), typeof(kbb2))
    # The luminosity ESTIMATE is returned as Float64 on every backend and
    # every beam precision (2026-08-07 neighbour audit, N7). Nothing else is
    # stable to key it on: klum and kbb follow the beam's params type, so a
    # Float32 beam gave a Float32 klum, and which scalar happened to promote
    # differed by backend -- the CPU returned Float64, CUDA Float32, and every
    # no-compute arm a beam-typed NaN. Float64 is what the task layer already
    # writes to .lum files; the per-pair computation itself deliberately stays
    # at the pipeline's own precision (the recorded pipeline-precision
    # asymmetry remains on the N7 ledger row).
    LT = Float64
    share_grid = _pic_source_slice_grid(solver)
    node_grid = _pic_node_grid_mode(solver)
    # Node meshes are memoized per (source slice, direction); each is shared by
    # the two field slices adjacent to that node, which is what restores exact
    # continuity at their common boundary.
    for ws in workspaces
        ws.dropped[] = 0
    end
    node_cache = Dict{Tuple{Int,Int},Dict{Int,Any}}()
    if node_grid
        _pic_prebuild_node_caches!(node_cache, solver, T, beam1.rep, slices1,
                                   beam2.rep, slices2, 1)
        _pic_prebuild_node_caches!(node_cache, solver, T, beam2.rep, slices2,
                                   beam1.rep, slices1, 2)
    end
    # Under :source_slice the mesh is sized once per (source slice, direction)
    # from the union over every field slice, so adjacent field slices reuse one
    # mesh and the transverse kick no longer jumps at their shared boundary.
    union_bounds = Dict{Tuple{Int,Int},Any}()

    order = _slice_collision_order(slices1, slices2)
    npairs = length(order)
    # Every pair's position in the COLLISION order. The luminosity fold and the
    # per-pair trace are then written by position and read back in that order at
    # the end, whichever schedule ran -- so the batched path reproduces the
    # sequential fold exactly instead of reassociating it into a different
    # ~1-ulp answer. `spectral.jl` folds per batch and had to widen a pin for
    # it; there is no reason to repeat that here.
    pair_pos = Dict{Tuple{Int,Int},Int}()
    sizehint!(pair_pos, npairs)
    for (p, entry) in pairs(order)
        pair_pos[(entry[2], entry[3])] = p
    end
    lum_parts = zeros(LT, npairs)
    # `Vector{Bool}`, NOT a `BitVector`: workers write disjoint entries, and a
    # BitVector packs eight of them into one byte, so two workers updating
    # neighbouring pairs would read-modify-write the same word and lose one.
    ran = fill(false, npairs)

    # Gather each slice ONCE, and give it a scratch twin to be kicked into. The
    # pair loop then neither gathers nor scatters; it copies state -> scratch,
    # kicks the scratch, and swaps. See `_pic_slice_states`.
    state1 = _pic_slice_states(beam1.rep, slices1.indices)
    state2 = _pic_slice_states(beam2.rep, slices2.indices)
    # Only beam 2 needs a scratch twin: beam 1's slice is kicked in place. See
    # `_pic_collide_pair!` for why one copy per pair is the minimum.
    scratch2 = _pic_slice_states(beam2.rep, slices2.indices)

    # The pool is STORAGE, not a worker count. `_pic_cpu_workspace_pool!` only
    # ever grows, so `length(workspaces)` is the high-water mark of every policy
    # this label has run under; scheduling off it would keep spawning 15 pair
    # workers after a caller asked for 2, which is a configuration set and not
    # read. The width is recomputed from the policy here and the pool indexed
    # only up to it.
    pool_workers = min(length(workspaces), _pic_pool_size(solver))
    if _pic_batchable(solver) && pool_workers > 1 && npairs > 1
        # What is left of the pool once the pairs have taken their share, handed
        # to the per-particle maps inside each pair so the two levels compose
        # instead of multiplying. Integer division, floor at 1: a pair always
        # gets at least itself.
        # Divided ONCE, by the pool rather than by each batch's width. Dividing
        # per batch -- so the width-1 batch at each end gets every thread for
        # its per-particle and per-cell maps -- is the obvious remedy for the
        # wavefront triangle and was measured TWICE, before and after the Green
        # table build started threading: 16 threads went 4.20 -> 5.41 s the
        # first time and 3.20 -> 3.94 s the second. Both times CPU time rose
        # faster than wall time fell (19.3 -> 27.9 s at 16 threads), i.e. the
        # extra occupancy was overhead, not work. Re-measure after any change
        # that moves a substantial block inside a pair; it is the right idea
        # waiting on parallel efficiency it does not have yet.
        # NO nesting inside the batched pair loop. The pair level already
        # supplies the concurrency, and splitting each pair's per-particle and
        # per-cell maps on top of it measurably costs.
        #
        # Found by a natural experiment on `fld(nthreads, pool)`, which is 1 up
        # to 29 threads and 2 from 30 (the pool caps at 15 slices). Wall time
        # and CPU time at the production point:
        #
        #     threads   16     20     29  |   30     32
        #     wall    3.40   3.45   3.82  | 4.54   4.99
        #     cpu     20.1   19.8   25.9  | 43.9   49.5
        #
        # The step is exactly where the split turns on, not a smooth curve, so
        # it is this rule and not the thread count. With no nesting: 3.45 at 16,
        # 4.00 at 32, 4.36 at 64 -- the cliff is gone and wide pools merely stop
        # helping instead of hurting.
        #
        # `_pic_map_particles` is NOT dead: the sequential path (one workspace —
        # `:source_slice`, or too few slices to batch) leaves the budget at 0 and
        # uses the whole pool, which is where it earns its keep.
        inner_workers = 1
        batches = collision_pair_batches(slices1, slices2)
        # Consumer-boundary receipt, so a test can assert the schedule the run
        # ACTUALLY used rather than the one its policy asked for. Without it,
        # "batched and sequential agree bit for bit" passes just as happily when
        # nothing ever batched (Measured Lesson: a configuration you set is not
        # a configuration the code read).
        _record_execution!(:cpu_pic_pair_schedule, CPUThreadsBackend,
                           (schedule=:batched, pairs=npairs, batches=length(batches),
                            widest_batch=maximum(length, batches; init=0),
                            pair_workers=pool_workers,
                            inner_workers=inner_workers))
        Base.ScopedValues.with(_PIC_MAP_WORKER_BUDGET => inner_workers) do
        for batch in batches
            nworkers = clamp(pool_workers, 1, length(batch))
            # `chunk_ws`, NOT `ws`. The sequential branch below also assigns
            # `ws`, and `if`/`else` opens no scope in Julia, so one name here
            # would be a single function-scope variable captured by this
            # closure -- one `Core.Box` shared by every worker, and therefore
            # ONE workspace shared by every worker. Measured before the rename:
            # the charge grid of one pair reached the field solve of another and
            # the collide failed with an all-NaN slice. Same defect as
            # `chunk_lum` in gaussian.jl and `chunk_counts` in slicing.jl; the
            # permanent lowered-code sweep is what named it.
            _run_logical_workers(nworkers) do chunk, _
                chunk_ws = workspaces[chunk]
                lo, hi = _chunk_bounds(length(batch), nworkers, chunk)
                for pos in lo:hi
                    pr = batch[pos]
                    p = pair_pos[(pr.i, pr.j)]
                    ran[p] = _pic_collide_pair!(
                        lum_parts, p, solver, beam1, beam2, slices1, slices2,
                        state1, state2, scratch2,
                        pr.i, pr.j, chunk_ws, green_cache, node_cache, union_bounds,
                        share_grid, node_grid, kbb1, kbb2, klum,
                        compute_luminosity, T, true)
                end
            end
        end
        end
    else
        _record_execution!(:cpu_pic_pair_schedule, CPUThreadsBackend,
                           (schedule=:sequential, pairs=npairs, batches=0,
                            widest_batch=0, pair_workers=1,
                            inner_workers=_cpu_worker_count()))
        serial_ws = first(workspaces)
        for (p, entry) in pairs(order)
            ran[p] = _pic_collide_pair!(
                lum_parts, p, solver, beam1, beam2, slices1, slices2,
                state1, state2, scratch2,
                entry[2], entry[3], serial_ws, green_cache, node_cache, union_bounds,
                share_grid, node_grid, kbb1, kbb2, klum,
                compute_luminosity, T, false)
        end
    end

    # Scatter the resident slices back into the beams, once. Until this runs the
    # beams still hold the turn-start coordinates -- which is why anything
    # inside the loop that needs current values reads the states instead (see
    # the `_pic_union_bounds` states method).
    _pic_store_slice_states!(beam1.rep, slices1.indices, state1)
    _pic_store_slice_states!(beam2.rep, slices2.indices, state2)

    luminosity = LT(NaN)
    if compute_luminosity
        luminosity = zero(LT)
        sink = _ACTIVE_PIC_LUMINOSITY_PAIR_SINK[]
        turn = ctx === nothing ? -1 : ctx.turn
        for p in 1:npairs
            @inbounds ran[p] || continue
            @inbounds luminosity += lum_parts[p]
            sink === nothing || push!(sink, (
                turn=turn, i=Int(order[p][2]), j=Int(order[p][3]),
                luminosity=Float64(lum_parts[p]),
            ))
        end
    end
    _pic_report_green_cache(green_cache)
    _pic_report_dropped(workspaces)
    return luminosity
end

"""
    _pic_collide_pair!(lum_parts, p, solver, ..., workspace, ..., batched) -> Bool

One slice-pair collision, writing its luminosity into `lum_parts[p]` and
returning whether it ran at all (an empty slice on either side, or a node mesh
that could not be built, is a skip — and a skip must not contribute to the fold
or to the per-pair trace).

Everything it touches is either private to this pair (the extracted slice
coordinates, the returned virtual positions) or exclusive to `workspace` for the
duration of the call, which is what lets the batched caller hand different pairs
of one batch to different workers. The two shared structures are
`green_cache`, which takes its own lock, and — under `:source_slice` only —
`union_bounds`, which is why that mode does not batch (`_pic_batchable`).
"""
function _pic_collide_pair!(lum_parts, p::Int, solver::PICPoissonSolver,
                            beam1::Beam, beam2::Beam, slices1, slices2,
                            state1, state2, scratch2,
                            i::Int, j::Int, workspace::_PICCPUWorkspace,
                            green_cache, node_cache, union_bounds,
                            share_grid::Bool, node_grid::Bool,
                            kbb1, kbb2, klum, compute_luminosity::Bool,
                            ::Type{T}, batched::Bool) where {T}
    idx1 = slices1.indices[i]
    idx2 = slices2.indices[j]
    (isempty(idx1) || isempty(idx2)) && return false
    param1 = (weight=slices1.weight[i], lb=slices1.boundary[i],
              center=slices1.center[i], rb=slices1.boundary[i + 1])
    param2 = (weight=slices2.weight[j], lb=slices2.boundary[j],
              center=slices2.center[j], rb=slices2.boundary[j + 1])
    # ONE copy per pair, not two, and it is provably the minimum.
    #
    # Both interactions must see their SOURCE slice as it was before this pair.
    # Direction 1 reads slice i and writes slice j; direction 2 reads slice j
    # and writes slice i. Run in that order, direction 1 has finished reading
    # slice i before direction 2 writes it, so slice i can be kicked IN PLACE
    # and needs no copy at all. Slice j does: direction 1 writes it before
    # direction 2 reads it, so direction 2 would otherwise see kicked values.
    #
    # Copying both was the obvious form and cost twice the traffic. The copy is
    # pure memory movement -- 8.19 MB for an electron slice at the production
    # point against 3.28 MB for a proton one -- and traffic is what makes a pair
    # cost ~2x more when fifteen of them run at once, so aliasing the LARGER
    # side is where the saving is. Neither interaction writes its source (they
    # read it for bounds, for the deposit, and for the virtual positions), which
    # is what makes the in-place kick safe; `_pic_interaction!` and
    # `_pic_interaction_node!` both hold to that.
    coord1 = state1[i]
    coord2 = state2[j]
    field1 = coord1                                    # kicked in place
    field2 = _pic_copy_slice!(scratch2[j], coord2)
    if node_grid
        # Read-only lookups, never `get!`. `_pic_prebuild_node_caches!` ran for
        # both directions before any pair, and it fills every source slice that
        # has particles -- which this pair does, or the emptiness check above
        # would have returned. An insert here would both race two workers on one
        # Dict and build the mesh from a partially kicked beam, the 3.8e-5
        # CPU/CUDA divergence that the prebuild exists to prevent. Loud if the
        # invariant is ever broken, rather than silently raced.
        nc1 = get(node_cache, (i, 1), nothing)
        nc2 = get(node_cache, (j, 2), nothing)
        (nc1 === nothing || nc2 === nothing || isempty(nc1) || isempty(nc2)) && error(
            "PIC node mesh cache is missing or empty for source slice $(i) of beam 1 " *
            "or $(j) of beam 2 at collision time, though both slices have particles; " *
            "_pic_prebuild_node_caches! must fill every non-empty source slice " *
            "before the pair loop runs.")
        gL1 = _pic_node_grid!(nc1, solver, T, coord1, param1.center, beam2.rep,
                              slices2.indices, slices2.boundary, j)
        gR1 = _pic_node_grid!(nc1, solver, T, coord1, param1.center, beam2.rep,
                              slices2.indices, slices2.boundary, j + 1)
        gL2 = _pic_node_grid!(nc2, solver, T, coord2, param2.center, beam1.rep,
                              slices1.indices, slices1.boundary, i)
        gR2 = _pic_node_grid!(nc2, solver, T, coord2, param2.center, beam1.rep,
                              slices1.indices, slices1.boundary, i + 1)
        (gL1 === nothing || gR1 === nothing || gL2 === nothing || gR2 === nothing) && return false
        vx1, vy1 = _pic_interaction_node!(
            solver, coord1, param1, field2, param2, kbb2, workspace, gL1, gR1; vslot=1)
        vx2, vy2 = _pic_interaction_node!(
            solver, coord2, param2, field1, param1, kbb1, workspace, gL2, gR2; vslot=2)
    else
        # `union_bounds` is only ever written on the `:source_slice` path, which
        # `_pic_batchable` keeps sequential; `batched` asserts that rather than
        # trusting the two predicates to stay in step.
        batched && share_grid && error(
            "interaction_grid = :source_slice reached the batched PIC pair loop; " *
            "its union mesh depends on how much of the turn has been applied, so " *
            "_pic_batchable must keep it sequential.")
        # From the resident STATES, not `beam2.rep`: with the slices held
        # resident the beam is stale until the collide ends, so reading it would
        # size the mesh from the turn-start distribution instead of the current
        # one. See the states method of `_pic_union_bounds`.
        ov1 = share_grid ? get!(() -> _pic_union_bounds(coord1, param1.center, state2, slices2.indices),
                                union_bounds, (i, 1)) : nothing
        ov2 = share_grid ? get!(() -> _pic_union_bounds(coord2, param2.center, state1, slices1.indices),
                                union_bounds, (j, 2)) : nothing
        key1 = share_grid ? (i, 0, 1) : (i, j, 1)
        key2 = share_grid ? (j, 0, 2) : (i, j, 2)
        vx1, vy1 = _pic_interaction!(
            solver, coord1, param1, field2, param2, kbb2, workspace, green_cache, key1, ov1;
            vslot=1,
        )
        vx2, vy2 = _pic_interaction!(
            solver, coord2, param2, field1, param1, kbb1, workspace, green_cache, key2, ov2;
            vslot=2,
        )
    end
    # Slice i was kicked in place and is already current. Slice j swaps: the
    # kicked scratch BECOMES the resident slice, the old resident becomes the
    # next pair's scratch. Within a batch no two pairs share a slice index, so
    # this element write never races another.
    @inbounds state2[j], scratch2[j] = scratch2[j], state2[j]
    if compute_luminosity
        @inbounds lum_parts[p] = _pic_luminosity(solver, vx1, vy1, vx2, vy2, klum, workspace)
    end
    return true
end

"""
    _pic_report_dropped(workspace)

Surface the count of particles that fell outside an interaction mesh and were
dropped by the zero-weight branch in `_pic_cic_weights` / `_pic_tsc_weights` —
field particles against the mesh the kick interpolation reads, AND source
particles against the mesh their charge is deposited on. The source half used to
be uncounted: under `grid_extent = :sigma` an out-of-box source particle's
charge vanished from the field with `dropped == 0` and no warning, which is
exactly the "missing from the field" case the warning below claims to cover
(2026-08-05 audit, U5-5). The count is per particle, not per axis or per
deposit plane (U5-6).

`_PICCPUWorkspace.dropped` documents itself as "Never silent", `grid_extent`'s
option metadata (`interface.jl`) promises out-of-range particles are "dropped and
counted", and `validation/README.md` says the count "must stay at zero for a
production setting". None of that was true: the counter was incremented in
`_pic_interaction!` and **read by nothing in the repository** — the one validation
script that prints a `dropped` column recomputes its own from
`_pic_axis_extent` rather than reading this one.

Dropped charge is a correctness event, not a tuning statistic — dropping a
fraction `f` at radius `R` costs a field error `~ f*(sigma/R)` — so this warns
rather than printing only under the diagnostics flag. It is silent at zero.

That used to read "silent at zero, which is every run with the default
`grid_extent = :extrema`" -- which was the bug, not a property: the counting was
gated on `grid_extent !== :extrema`, and `:node`/`:source_slice` have
`:extrema` forced on them, so the two modes whose meshes are built pre-collision
could never report anything (2026-08-05_b audit, U6-1).
"""
function _pic_report_dropped(workspace::_PICCPUWorkspace)
    return _pic_report_dropped_count(Int(workspace.dropped[]))
end

# Pool form: the batched pair loop gives each worker its own workspace, so the
# count a run must report is the SUM over the pool, not one worker's share. One
# warning per collide either way -- summing here rather than warning per
# workspace keeps a dropped particle exactly as loud as it was when the loop was
# sequential, instead of N times louder or, worse, N-1 times quieter.
function _pic_report_dropped(workspaces)
    total = 0
    for ws in workspaces
        total += Int(ws.dropped[])
    end
    return _pic_report_dropped_count(total)
end

# Shared reader for both backends: the CUDA workspace's device counter is read
# back once per collide and routed here (`_cuda_pic_report_dropped`, U1-5), so
# a dropped particle warns identically wherever it happens.
function _pic_report_dropped_count(n::Integer)
    n == 0 && return nothing
    @warn "PIC interaction mesh dropped particles: the mesh under-covered a beam, \
so these particles received no kick, or their charge is missing from the field \
they source, or both. On interaction_grid = :slice_pair this is the transverse \
extent estimator -- use grid_extent = :extrema, or raise grid_extent_sigma. On \
:node and :source_slice, grid_extent is already forced to :extrema and the cause \
is different: those meshes are built before the collision (at turn start, and at \
the source slice's first use) and deposited into after the intra-collision kicks \
move the particles, so coverage is not guaranteed by construction. There raise \
the slice count or the grid, or use :slice_pair." dropped = n
    return nothing
end

function _pic_cpu_scalar_type(solver::PICPoissonSolver, beam1::Beam, beam2::Beam)
    return promote_type(
        eltype(beam1.rep.x), eltype(beam2.rep.x),
        typeof(_pic_kbb1(solver, beam1, beam2)),
        typeof(_pic_kbb2(solver, beam1, beam2)),
    )
end

"""
    _pic_cpu_workspace_pool!(runtime_cache, label, solver, T, n) -> Vector

`n` scratch workspaces for the batched pair loop, cached across turns and GROWN
in place when a later call wants more.

`n` is deliberately NOT part of the key. Keying on it would strand a whole pool
every time the worker count changed, and a workspace is ~8 MB at grid 128
(sixteen padded deposit grids); growing keeps exactly one pool per
(label, T, grid) for the process's lifetime.

Because it only grows, `length(pool)` is the HIGH-WATER MARK of every policy
this label has run under, not the policy in force now — so it is storage, never
a worker count. `_pic_collide!` recomputes the width from `_pic_pool_size`.

Which workspace a pair is handed cannot move a result. Every buffer is fully
overwritten before it is read -- `charge` and the luminosity grids are `fill!`ed,
`spectral` and `green_fft` are assigned whole, the field planes are written by
the solve that reads them -- and `dropped` is a counter that
`_pic_report_dropped` sums over the pool.
"""
function _pic_cpu_workspace_pool!(runtime_cache::Dict, label::Symbol,
                                  solver::PICPoissonSolver, ::Type{T},
                                  n::Integer) where {T}
    key = (:cpu_pic_workspace_pool, label, T, solver.grid)
    pool = get!(() -> _PICCPUWorkspace{T}[], runtime_cache, key)::Vector{_PICCPUWorkspace{T}}
    while length(pool) < n
        push!(pool, _pic_cpu_workspace(T, solver.grid...))
    end
    return pool
end

function _pic_green_cache!(runtime_cache::Dict, label::Symbol,
                           solver::PICPoissonSolver, ::Type{T}) where {T}
    key = (
        :cpu_pic_green_cache,
        label,
        T,
        solver.grid,
        Symbol(solver.green_type),
        Symbol(solver.green_cache),
        solver.slice_pair_green_min_ratio,
        solver.slice_pair_green_growth,
        Symbol(solver.interaction_grid),
    )
    return get!(runtime_cache, key) do
        _pic_green_cache(solver, T)
    end
end

function _validate_pic_solver(solver::PICPoissonSolver)
    nx, ny = solver.grid
    _validate_pic_grid(nx, ny)
    method = Symbol(solver.deposit_method)
    (method == :CIC || method == :TSC) ||
        throw(ArgumentError("PICPoissonSolver deposit_method must be :CIC or :TSC"))
    luminosity_method = _pic_luminosity_deposit_method(solver)
    (luminosity_method == :CIC || luminosity_method == :TSC) ||
        throw(ArgumentError("PICPoissonSolver luminosity_deposit_method must resolve to :CIC or :TSC"))
    green = Symbol(solver.green_type)
    (green == :integrated || green == :standard || green == :lattice) ||
        throw(ArgumentError("PICPoissonSolver green_type must be :integrated, :standard or :lattice"))
    cache = Symbol(solver.green_cache)
    (cache == :none || cache == :slice_pair) ||
        throw(ArgumentError("PICPoissonSolver green_cache must be :none or :slice_pair"))
    batch_mode = Symbol(solver.batch_mode)
    (batch_mode == :sequential || batch_mode == :wavefront) ||
        throw(ArgumentError("PICPoissonSolver batch_mode must be :sequential or :wavefront"))
    fd = Symbol(solver.field_derivative)
    (fd == :second || fd == :fourth) ||
        throw(ArgumentError("PICPoissonSolver field_derivative must be :second or :fourth"))
    si = Symbol(solver.slice_interpolation)
    (si == :linear || si == :quadratic) ||
        throw(ArgumentError("PICPoissonSolver slice_interpolation must be :linear or :quadratic"))
    ig = Symbol(solver.interaction_grid)
    (ig == :slice_pair || ig == :source_slice || ig == :node) ||
        throw(ArgumentError(
            "PICPoissonSolver interaction_grid must be :slice_pair, :source_slice or :node"))
    # `grid_extent` is consumed by `_pic_axis_extent`, which only the per-slice-pair
    # sizing path calls. `:source_slice` sizes from `_pic_union_bounds` and `:node`
    # from `_pic_build_node_grids!`; both take plain min/max over their own particle
    # sets and never consult the estimator, so a non-default `grid_extent` was
    # accepted and dropped — measured bit-identical results for :extrema, :sigma and
    # :sigma with grid_extent_sigma = 2.0. Reject rather than silently ignore, as
    # the CUDA PIC and Gaussian-PIC paths already do for this same option.
    if ig != :slice_pair && Symbol(solver.grid_extent) != :extrema
        throw(ArgumentError(
            "grid_extent = $(repr(solver.grid_extent)) is not implemented for " *
            "interaction_grid = $(repr(solver.interaction_grid)): that mode sizes its mesh " *
            "from the union/per-node extrema of its own particle sets and applies no extent " *
            "estimator, so a non-default value would be silently ignored. Use " *
            "interaction_grid = :slice_pair, or set grid_extent = :extrema."))
    end
    # `slice_interpolation = :quadratic` is consumed only by the slice-pair
    # interpolation path; the `:node` planes carry their own interpolation and
    # the quadratic request was accepted and bit-identically ignored on BOTH
    # backends, so the parity contract shared the blind spot (2026-08-05
    # audit, U1-2/U5-3, found independently by two readers). Reject rather
    # than silently ignore, the same policy as `grid_extent` above; making
    # :quadratic and :node compose is future work for the
    # node_interaction_grid program.
    if ig == :node && si != :linear
        throw(ArgumentError(
            "slice_interpolation = $(repr(solver.slice_interpolation)) is not implemented " *
            "for interaction_grid = :node: the node-plane path applies its own " *
            "interpolation, so the request was silently ignored on both backends. Use " *
            "interaction_grid = :slice_pair for :quadratic, or slice_interpolation = :linear."))
    end
    return nothing
end

"""
    _pic_mid_field!(workspace, nx, ny)

Return the midpoint field plane used by `slice_interpolation = :quadratic`,
allocating it on first use.

The two-node default never calls this, so the third plane costs no memory unless
the three-node scheme is actually selected. The size check also covers a
workspace built for a different grid.
"""
function _pic_mid_field!(workspace::_PICCPUWorkspace{T}, nx::Integer, ny::Integer) where {T}
    mid = workspace.mid[]
    if mid isa _PICFieldWorkspace{T} && size(mid.phi) == (nx, ny)
        return mid
    end
    fresh = _PICFieldWorkspace(zeros(T, nx, ny), zeros(T, nx, ny), zeros(T, nx, ny))
    workspace.mid[] = fresh
    return fresh
end

"""Return true when the solver requests the three-node longitudinal interpolation."""
_pic_quadratic_slice(solver::PICPoissonSolver) = solver.slice_interpolation === :quadratic

"""Return true when one interaction mesh is shared across a source slice's field slices."""
_pic_source_slice_grid(solver::PICPoissonSolver) = solver.interaction_grid === :source_slice

"""Return true when the interaction mesh is indexed by interpolation node."""
_pic_node_grid_mode(solver::PICPoissonSolver) = solver.interaction_grid === :node

"""
    _pic_union_bounds(source, center, field_rep, field_indices)

Transverse bounding boxes covering *every* field slice that will collide with one
source slice: the source drifted across the field beam's full longitudinal range,
and every field particle drifted to its own collision point.

Used by `interaction_grid = :source_slice` to size one mesh per (source slice,
direction). The drifted coordinate `x + px*s` is affine in `s`, so evaluating the
source at the two extreme drifts bounds every intermediate one.

These are grid-*sizing* bounds only. The per-slice actual bounds are still handed
to the Green cache's coverage test, so a slice whose particles have since moved
outside the shared mesh triggers a rebuild rather than being silently clipped.
"""
function _pic_union_bounds(source, center, rep, field_indices)
    T = eltype(source.x)
    c = T(center)
    zmin = T(Inf); zmax = T(-Inf)
    fxmin = T(Inf); fxmax = T(-Inf); fymin = T(Inf); fymax = T(-Inf)
    for idx in field_indices, i in idx
        @inbounds begin
            zi = T(rep.z[i])
            zmin = min(zmin, zi); zmax = max(zmax, zi)
            s = T(0.5) * (zi - c)
            xv = rep.x[i] + s * rep.px[i]
            yv = rep.y[i] + s * rep.py[i]
            fxmin = min(fxmin, xv); fxmax = max(fxmax, xv)
            fymin = min(fymin, yv); fymax = max(fymax, yv)
        end
    end
    isnan(zmin) && _nonfinite_coordinate_error(:field, (z=rep.z,);
                                               context="source-slice union bounds")
    isfinite(zmin) || return nothing
    all(isfinite, (fxmin, fxmax, fymin, fymax)) ||
        _nonfinite_coordinate_error(:field,
            (x=rep.x, px=rep.px, y=rep.y, py=rep.py, z=rep.z);
            context="source-slice union bounds")
    return _pic_union_bounds_tail(source, c, T, fxmin, fxmax, fymin, fymax, zmin, zmax)
end

"""
    _pic_union_bounds(source, center, states::AbstractVector, field_indices)

The resident-slice form, and the ONLY one the collide loop uses.

`interaction_grid = :source_slice` sizes its mesh from a union over the whole
partner beam **at the source slice's first use**, so its value depends on how
much of the turn has already been applied. Once the slices are held resident,
`rep` is stale until the collide ends, and reading it here would silently size
the mesh from the turn-START distribution instead of the current one — a
physics change disguised as a refactor. `states[sl][pos]` is exactly what
`rep[field_indices[sl][pos]]` held before hoisting, read in the same order, so
this reproduces the old bounds bit for bit.

The `rep` method above is kept for the direct callers in `test/` and
`validation/`, which pass a beam that no collide is mutating.
"""
function _pic_union_bounds(source, center, states::AbstractVector, field_indices)
    T = eltype(source.x)
    c = T(center)
    zmin = T(Inf); zmax = T(-Inf)
    fxmin = T(Inf); fxmax = T(-Inf); fymin = T(Inf); fymax = T(-Inf)
    for (sl, idx) in pairs(field_indices)
        fc = states[sl]
        @inbounds for pos in eachindex(idx)
            zi = T(fc.z[pos])
            zmin = min(zmin, zi); zmax = max(zmax, zi)
            s = T(0.5) * (zi - c)
            xv = fc.x[pos] + s * fc.px[pos]
            yv = fc.y[pos] + s * fc.py[pos]
            fxmin = min(fxmin, xv); fxmax = max(fxmax, xv)
            fymin = min(fymin, yv); fymax = max(fymax, yv)
        end
    end
    if isnan(zmin) || !all(isfinite, (fxmin, fxmax, fymin, fymax))
        bad = findfirst(c2 -> !all(isfinite, c2.z) || !all(isfinite, c2.x) ||
                              !all(isfinite, c2.px) || !all(isfinite, c2.y) ||
                              !all(isfinite, c2.py), states)
        bad === nothing || _nonfinite_coordinate_error(:field,
            (x=states[bad].x, px=states[bad].px, y=states[bad].y,
             py=states[bad].py, z=states[bad].z);
            context="source-slice union bounds")
    end
    isfinite(zmin) || return nothing
    return _pic_union_bounds_tail(source, c, T, fxmin, fxmax, fymin, fymax, zmin, zmax)
end

# The source half, shared by both forms: it reads only this slice's own
# coordinates, which hoisting does not change.
function _pic_union_bounds_tail(source, c, ::Type{T}, fxmin, fxmax, fymin, fymax,
                                zmin, zmax) where {T}
    sA = T(0.5) * (c - zmax)
    sB = T(0.5) * (c - zmin)
    sxmin = T(Inf); sxmax = T(-Inf); symin = T(Inf); symax = T(-Inf)
    for i in eachindex(source.x)
        @inbounds begin
            xa = source.x[i] + source.px[i] * sA; xb = source.x[i] + source.px[i] * sB
            ya = source.y[i] + source.py[i] * sA; yb = source.y[i] + source.py[i] * sB
            sxmin = min(sxmin, xa, xb); sxmax = max(sxmax, xa, xb)
            symin = min(symin, ya, yb); symax = max(symax, ya, yb)
        end
    end
    all(isfinite, (sxmin, sxmax, symin, symax)) ||
        _nonfinite_coordinate_error(:source,
            (x=source.x, px=source.px, y=source.y, py=source.py);
            context="source-slice union bounds")
    return ((xmin=sxmin, xmax=sxmax, ymin=symin, ymax=symax),
            (xmin=fxmin, xmax=fxmax, ymin=fymin, ymax=fymax))
end

"""
    _require_cuda_pic_options(solver)

Route check for the CUDA PIC backend. `slice_interpolation = :quadratic` runs on
the sequential non-async route and on the batched-FFT routes (including the
production indexed wavefront), which carry the midpoint plane through their own
6-planes-per-pair path (`nplanes = 6 * npairs`, L/M/R per direction). The one
unsupported combination is the non-batched *async* route (`cuda_async = true`
with `cuda_batch_fft = false`), whose four fixed field streams carry exactly two
planes per direction. `interaction_grid = :source_slice` is CPU-only. Neither
may be silently ignored.
"""
function _require_cuda_pic_options(solver::PICPoissonSolver)
    if solver.slice_interpolation !== :linear
        sequential_ok = Symbol(solver.batch_mode) === :sequential && !solver.cuda_async
        batched_ok = solver.cuda_async && solver.cuda_batch_fft
        (sequential_ok || batched_ok) || throw(ArgumentError(
            "slice_interpolation = $(repr(solver.slice_interpolation)) on the CUDA PIC backend " *
            "requires batch_mode = :sequential with cuda_async = false, or the batched-FFT " *
            "routes (cuda_async = true with cuda_batch_fft = true); the non-batched async " *
            "route carries only two field planes per slice-pair direction. Got " *
            "batch_mode = $(repr(solver.batch_mode)), cuda_async = $(solver.cuda_async), " *
            "cuda_batch_fft = $(solver.cuda_batch_fft)."))
    end
    if solver.interaction_grid === :node
        # :node runs on the FULLY-INDEXED wavefront route (its own 6-plane
        # path) and on the sequential non-async route. Every other route —
        # the sequential batched-FFT sub-route AND every non-indexed
        # wavefront sub-route — assumes one mesh per slice pair and never
        # reads the node caches: the 2026-08-05 audit (F11) measured :node
        # silently degrading to :slice_pair there (1.2e-2 coordinate shift
        # against the honored route), so the full indexed flag set is
        # required rather than assumed.
        wavefront_ok = Symbol(solver.batch_mode) === :wavefront &&
            solver.cuda_indexed_wavefront && solver.cuda_wavefront_fft &&
            solver.cuda_batch_fft && solver.cuda_async
        sequential_ok = Symbol(solver.batch_mode) === :sequential && !solver.cuda_async
        (wavefront_ok || sequential_ok) || throw(ArgumentError(
            "interaction_grid = :node on the CUDA PIC backend requires the fully-indexed " *
            "wavefront route (batch_mode = :wavefront with cuda_indexed_wavefront, " *
            "cuda_wavefront_fft, cuda_batch_fft and cuda_async all true), or " *
            "batch_mode = :sequential with cuda_async = false; every other route assumes " *
            "one mesh per slice pair and would silently drop :node. Got batch_mode = " *
            "$(repr(solver.batch_mode)), cuda_async = $(solver.cuda_async), cuda_batch_fft = " *
            "$(solver.cuda_batch_fft), cuda_wavefront_fft = $(solver.cuda_wavefront_fft), " *
            "cuda_indexed_wavefront = $(solver.cuda_indexed_wavefront)."))
    end
    solver.grid_extent === :extrema || throw(ArgumentError(
        "grid_extent = $(repr(solver.grid_extent)) is not implemented by the CUDA PIC " *
        "backend: _cuda_pic_prepare_interaction computes its bounds by mapreduce and applies " *
        "no estimator, so a non-default value would be silently ignored. Use the CPU backend, " *
        "or set grid_extent = :extrema."))
    if solver.interaction_grid !== :slice_pair && solver.interaction_grid !== :node
        throw(ArgumentError(
            "interaction_grid = $(repr(solver.interaction_grid)) is not implemented by the CUDA " *
            "PIC backend; only the CPU PICPoissonSolver path supports :source_slice. " *
            "Select the CPU backend, or set interaction_grid = :slice_pair."))
    end
    return nothing
end

"""
    _require_linear_slice_interpolation(solver, path)

Throw when a code path that implements only the two-node longitudinal
reconstruction and per-slice-pair mesh sizing is handed
`slice_interpolation = :quadratic` or `interaction_grid = :source_slice`. A
non-default public configuration value must never be silently ignored; see
`AGENTS.md`.
"""
function _require_linear_slice_interpolation(solver::PICPoissonSolver, path::AbstractString)
    solver.slice_interpolation === :linear || throw(ArgumentError(
        "slice_interpolation = $(repr(solver.slice_interpolation)) is not implemented by " *
        "$path; only the CPU PICPoissonSolver path supports :quadratic. Select the CPU " *
        "backend, or set slice_interpolation = :linear."))
    solver.interaction_grid === :slice_pair || throw(ArgumentError(
        "interaction_grid = $(repr(solver.interaction_grid)) is not implemented by " *
        "$path; only the CPU PICPoissonSolver path supports :source_slice and :node. Select " *
        "the CPU backend, or set interaction_grid = :slice_pair."))
    # The Gaussian-subtracted path sizes its own adaptive box from margin_sigma
    # and the reference Gaussian's moments; it never consults the mesh-extent
    # estimator, so a non-default value here was accepted and dropped. Measured
    # identical results for :extrema and :sigma at margin_sigma 5.0 and 0.0.
    # Rejecting matches how the CUDA PIC backend already handles this same
    # option rather than silently ignoring it.
    solver.grid_extent === :extrema || throw(ArgumentError(
        "grid_extent = $(repr(solver.grid_extent)) is not implemented by $path; it sizes " *
        "its interaction box from margin_sigma and the subtracted Gaussian's moments and " *
        "applies no extent estimator, so a non-default value would be silently ignored. " *
        "Use PICPoissonSolver, or set grid_extent = :extrema."))
    return nothing
end

function _validate_pic_grid(nx::Integer, ny::Integer)
    nx >= 5 && ny >= 5 || throw(ArgumentError("PICPoissonSolver grid must be at least (5, 5)"))
    return nothing
end

# kbb1/kbb2 are the physical kick scales (same convention as GaussianPoissonSolver
# and ThinStrongBeam). PIC deposits the source beam's macroparticles, so the
# physical scale is divided by the source macroparticle count to give the
# per-deposited-particle scale. The division applies to a user-supplied override
# too, so an explicit kbb1/kbb2 means the same physical quantity for both solvers.
_pic_kbb1(solver::PICPoissonSolver, beam1, beam2) =
    (solver.kbb1 !== nothing ? solver.kbb1 : _strong_strong_kbb1(solver, beam1, beam2)) / length(beam2.rep)
_pic_kbb2(solver::PICPoissonSolver, beam1, beam2) =
    (solver.kbb2 !== nothing ? solver.kbb2 : _strong_strong_kbb2(solver, beam1, beam2)) / length(beam1.rep)

function _pic_luminosity_scale(solver::PICPoissonSolver, beam1, beam2)
    solver.luminosity_scale !== nothing && return solver.luminosity_scale
    return beam1.params.npart * beam2.params.npart / (length(beam1.rep) * length(beam2.rep))
end

function _pic_extract_slice(rep::Phase6DRep, idx)
    T = eltype(rep.x)
    n = length(idx)
    x = Vector{T}(undef, n); px = similar(x); y = similar(x)
    py = similar(x); z = similar(x); pz = similar(x)
    for (j, i) in pairs(idx)
        @inbounds begin
            x[j] = rep.x[i]; px[j] = rep.px[i]
            y[j] = rep.y[i]; py[j] = rep.py[i]
            z[j] = rep.z[i]; pz[j] = rep.pz[i]
        end
    end
    return (x=x, px=px, y=y, py=py, z=z, pz=pz)
end

_pic_copy_coords(c) = (x=copy(c.x), px=copy(c.px), y=copy(c.y),
                       py=copy(c.py), z=copy(c.z), pz=copy(c.pz))

"""
    _pic_slice_states(rep, indices) -> Vector

Gather every slice's coordinates ONCE per collide, in slice order.

The pair loop used to gather a slice out of the beam, copy it, and scatter it
back for EVERY pair it took part in — 15 times per turn per slice at the
production point, when it needs gathering once and storing once. That was
measured at **58.1% of a slice-pair's cost** and accounted for essentially the
whole 6.28 GiB a collide allocated (extract + copy + store, 26.8 MB per pair x
225 pairs = 6.0 GB against 6.28 GiB measured), which in turn drove the ~20% of
wall spent in GC.

Holding the slices resident makes the per-pair cost one contiguous copy instead
of an indexed gather, an indexed scatter and a copy — and the values are
identical, so this removes work rather than changing any of it.
"""
_pic_slice_states(rep::Phase6DRep, indices) =
    [_pic_extract_slice(rep, idx) for idx in indices]

"""
    _pic_virtual_buffers(workspace, slot, n, T) -> (vx, vy)

`n`-element buffers for a direction's virtual source positions.

`slot = 0` allocates, which is what every caller outside the collide loop wants
(the direct entry points in `test/` and `validation/` keep their own arrays and
outlive the workspace). `slot = 1` or `2` hands back the workspace's reusable
pair for that direction — valid only until the same slot is asked for again,
which is within the pair, which is where `_pic_luminosity` consumes them.

The fallback method covers a working type that does not match the workspace's.
It cannot fire on the collide path — `_pic_cpu_scalar_type` builds the
workspace from the same promotion — but reusing a `Vector{Float64}` as
`Vector{Float32}` would be a type error rather than a slow path, so the
mismatch allocates instead of asserting.
"""
@inline _pic_virtual_buffers(::_PICCPUWorkspace, ::Int, n::Int, ::Type{T}) where {T} =
    (Vector{T}(undef, n), Vector{T}(undef, n))

@inline function _pic_virtual_buffers(workspace::_PICCPUWorkspace{T}, slot::Int,
                                      n::Int, ::Type{T}) where {T}
    slot == 0 && return (Vector{T}(undef, n), Vector{T}(undef, n))
    vx = workspace.virtual_x[slot]
    vy = workspace.virtual_y[slot]
    if length(vx) != n
        resize!(vx, n)
        resize!(vy, n)
    end
    return vx, vy
end

"""Copy one resident slice into its scratch twin, field by field."""
function _pic_copy_slice!(dst, src)
    copyto!(dst.x, src.x); copyto!(dst.px, src.px)
    copyto!(dst.y, src.y); copyto!(dst.py, src.py)
    copyto!(dst.z, src.z); copyto!(dst.pz, src.pz)
    return dst
end

"""
Scatter the resident slices back into the beam, once, at the end of the collide.

Empty slices are skipped rather than scattered: `_pic_extract_slice` gives them
zero-length arrays and `_pic_store_slice!` would loop zero times anyway, but
skipping says so.
"""
function _pic_store_slice_states!(rep::Phase6DRep, indices, states)
    for (sl, idx) in pairs(indices)
        isempty(idx) && continue
        _pic_store_slice!(rep, idx, states[sl])
    end
    return nothing
end

function _pic_store_slice!(rep::Phase6DRep, idx, c)
    for (j, i) in pairs(idx)
        @inbounds begin
            rep.x[i] = c.x[j]; rep.px[i] = c.px[j]
            rep.y[i] = c.y[j]; rep.py[i] = c.py[j]
            rep.z[i] = c.z[j]; rep.pz[i] = c.pz[j]
        end
    end
    return nothing
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb)
    nx, ny = solver.grid
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))
    workspace = _pic_cpu_workspace(T, nx, ny)
    green_cache = _pic_green_cache(solver, T)
    return _pic_interaction!(solver, source, param_source, field, param_field, kbb, workspace, green_cache)
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb,
                           workspace::_PICCPUWorkspace)
    green_cache = _pic_green_cache(solver, promote_type(eltype(source.x), eltype(field.x), typeof(kbb)))
    return _pic_interaction!(solver, source, param_source, field, param_field, kbb, workspace, green_cache)
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb,
                           workspace::_PICCPUWorkspace, green_cache)
    return _pic_interaction!(solver, source, param_source, field, param_field, kbb, workspace, green_cache, nothing)
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb,
                           workspace::_PICCPUWorkspace, green_cache, cache_key,
                           bounds_override=nothing; vslot::Int=0)
    nsource = length(source.x)
    nfield = length(field.x)
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))

    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    source_xl = source.x[1] + source.px[1] * sL
    source_yl = source.y[1] + source.py[1] * sL
    source_xr = source.x[1] + source.px[1] * sR
    source_yr = source.y[1] + source.py[1] * sR
    source_xmin = min(source_xl, source_xr)
    source_xmax = max(source_xl, source_xr)
    source_ymin = min(source_yl, source_yr)
    source_ymax = max(source_yl, source_yr)
    ge = Symbol(solver.grid_extent)
    source_x0 = source_xl
    source_y0 = source_yl
    sxs = zero(T); sxs2 = zero(T); sys = zero(T); sys2 = zero(T)
    for i in 1:nsource
        @inbounds begin
            xl = source.x[i] + source.px[i] * sL
            yl = source.y[i] + source.py[i] * sL
            xr = source.x[i] + source.px[i] * sR
            yr = source.y[i] + source.py[i] * sR
            source_xmin = min(source_xmin, xl, xr)
            source_xmax = max(source_xmax, xl, xr)
            source_ymin = min(source_ymin, yl, yr)
            source_ymax = max(source_ymax, yl, yr)
            if ge !== :extrema
                dxl = xl - source_x0; dxr = xr - source_x0
                dyl = yl - source_y0; dyr = yr - source_y0
                sxs += dxl + dxr; sxs2 += dxl * dxl + dxr * dxr
                sys += dyl + dyr; sys2 += dyl * dyl + dyr * dyr
            end
        end
    end
    kext = T(solver.grid_extent_sigma)
    source_xmin, source_xmax = _pic_axis_extent(ge, source_xmin, source_xmax,
                                                source_x0, sxs, sxs2, 2 * nsource, kext)
    source_ymin, source_ymax = _pic_axis_extent(ge, source_ymin, source_ymax,
                                                source_y0, sys, sys2, 2 * nsource, kext)
    # Non-finite chokepoint (N1, docs/todo.md): a NaN/Inf coordinate propagates
    # into these O(1) bound values, so this check costs nothing on the hot path.
    all(isfinite, (source_xmin, source_xmax, source_ymin, source_ymax)) ||
        _nonfinite_coordinate_error(:source,
            (x=source.x, px=source.px, y=source.y, py=source.py);
            context=_pic_slice_context(cache_key))

    field_xmin = field_xmax = field.x[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.px[1]
    field_ymin = field_ymax = field.y[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.py[1]
    field_x0 = field_xmin
    field_y0 = field_ymin
    fxs = zero(T); fxs2 = zero(T); fys = zero(T); fys2 = zero(T)
    for i in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[i] - T(param_source.center))
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
            field_xmin = min(field_xmin, field.x[i]); field_xmax = max(field_xmax, field.x[i])
            field_ymin = min(field_ymin, field.y[i]); field_ymax = max(field_ymax, field.y[i])
            if ge !== :extrema
                dx = field.x[i] - field_x0
                dy = field.y[i] - field_y0
                fxs += dx; fxs2 += dx * dx
                fys += dy; fys2 += dy * dy
            end
        end
    end
    field_xmin, field_xmax = _pic_axis_extent(ge, field_xmin, field_xmax,
                                              field_x0, fxs, fxs2, nfield, kext)
    field_ymin, field_ymax = _pic_axis_extent(ge, field_ymin, field_ymax,
                                              field_y0, fys, fys2, nfield, kext)
    all(isfinite, (field_xmin, field_xmax, field_ymin, field_ymax)) ||
        _nonfinite_coordinate_error(:field,
            (x=field.x, px=field.px, y=field.y, py=field.py, z=field.z);
            context=_pic_slice_context(cache_key))
    # Grid sizing may come from the shared per-source-slice union
    # (`interaction_grid = :source_slice`); the coverage bounds handed to the
    # cache are always this slice's own, so a stale shared mesh still rebuilds.
    if bounds_override === nothing
        gsx0, gsx1, gsy0, gsy1 = source_xmin, source_xmax, source_ymin, source_ymax
        gfx0, gfx1, gfy0, gfy1 = field_xmin, field_xmax, field_ymin, field_ymax
    else
        sb, fb = bounds_override
        gsx0, gsx1, gsy0, gsy1 = sb.xmin, sb.xmax, sb.ymin, sb.ymax
        gfx0, gfx1, gfy0, gfy1 = fb.xmin, fb.xmax, fb.ymin, fb.ymax
    end
    source_grid0, field_grid0 = _pic_interaction_grids(
        solver, gsx0, gsx1, gsy0, gsy1, gfx0, gfx1, gfy0, gfy1,
    )
    source_bounds = (xmin=source_xmin, xmax=source_xmax, ymin=source_ymin, ymax=source_ymax)
    field_bounds = (xmin=field_xmin, xmax=field_xmax, ymin=field_ymin, ymax=field_ymax)
    source_grid, field_grid, green_fft = _pic_slice_pair_green!(
        workspace, solver, T, green_cache, cache_key, source_grid0, field_grid0, source_bounds, field_bounds,
    )
    if ge !== :extrema || Symbol(solver.interaction_grid) !== :slice_pair
        # `:extrema` covers every particle by construction ONLY on `:slice_pair`,
        # where this mesh is sized here, from this slice's own post-drift
        # extrema. The robust estimators do not cover, so record what falls
        # outside instead of letting it be dropped silently by the zero-weight
        # branch in `_pic_cic_weights`.
        #
        # The `:slice_pair` qualifier is the correction. `_validate_pic_solver`
        # rejects any `grid_extent != :extrema` for `:node` and `:source_slice`,
        # so `ge !== :extrema` alone made this whole block unreachable in exactly
        # the two modes whose meshes are built PRE-COLLISION -- `:node` at turn
        # start, `:source_slice` at the source slice's first use -- and then
        # deposited into after the intra-collision kicks have moved the
        # particles. That is the same mechanism the R9 tripwire was built for.
        # Measured on an EIC-like flat pair, 30k/beam, 15 slices, grid 64: 2 of
        # 1,800,000 source deposits outside the mesh under `:node`, 1 of 900,000
        # under `:source_slice`, both with `dropped == 0` and no warning
        # (2026-08-05_b audit, U6-1).
        #
        # Counted against `field_grid`, which is the mesh the interpolation
        # actually reads, and only once it is final: the Green cache may return a
        # larger grid than `_pic_interaction_grids` asked for. Counting against
        # the *estimator* box instead — as this did — over-reported, because the
        # mesh carries 1.5 cells of margin beyond that box and a particle sitting
        # in the margin is interpolated correctly rather than dropped.
        workspace.dropped[] += _pic_count_outside_box(
            field.x, field.y,
            field_grid.x0, field_grid.x0 + field_grid.width,
            field_grid.y0, field_grid.y0 + field_grid.height)
        # SOURCE-side charge is subject to the same estimator: the deposits at
        # sL/sR below drop out-of-box source particles through the same
        # zero-weight branch, and that half went UNCOUNTED — measured 1.0
        # particle-charge missing from the field with dropped == 0 and no
        # warning (2026-08-05 audit, U5-5). Counted against `source_grid`, the
        # mesh those deposits write, at the drifted positions they use; the
        # quadratic path's extra sM plane needs no extra check because the
        # drifted coordinate is affine in s, so in-box at sL and sR implies
        # in-box at their midpoint.
        workspace.dropped[] += _pic_count_outside_box_drifted(
            source.x, source.px, source.y, source.py, sL, sR,
            source_grid.x0, source_grid.x0 + source_grid.width,
            source_grid.y0, source_grid.y0 + source_grid.height)
    end
    phiL, ExL, EyL = _pic_solve_drifted_field_with_green_fft!(
        workspace.left, solver, source, sL, source_grid, green_fft, workspace,
    )
    phiR, ExR, EyR = _pic_solve_drifted_field_with_green_fft!(
        workspace.right, solver, source, sR, source_grid, green_fft, workspace,
    )

    kick_scale = T(2) * T(kbb)
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    if _pic_quadratic_slice(solver)
        # Third node at the field-slice midpoint. The drifted source coordinate
        # x + px*s is affine in s, so the sL/sR bounding box already contains the
        # midpoint plane and no grid resizing is needed.
        # `s_mid`, NOT `sM`. The virtual-position closure below captures `sM`,
        # and `if` opens no scope in Julia, so reusing the name here makes one
        # function-scope variable assigned in two places -- which boxes it and
        # fails the `Core.Box` tripwire. Same defect class as `chunk_lum` in
        # gaussian.jl and `chunk_counts` in slicing.jl; the distinct name is the
        # whole fix.
        s_mid = T(0.5) * (sL + sR)
        phiM, ExM, EyM = _pic_solve_drifted_field_with_green_fft!(
            _pic_mid_field!(workspace, solver.grid...), solver, source, s_mid,
            source_grid, green_fft, workspace,
        )
        _pic_map_particles(nfield) do first_i, last_i
            _pic_apply_kick_quadratic_range!(
                solver, field, field_grid, phiL, ExL, EyL, phiM, ExM, EyM,
                phiR, ExR, EyR, kick_scale, hzi, zbias,
                T(param_source.center), T, first_i, last_i,
            )
        end
    else
        _pic_map_particles(nfield) do first_i, last_i
            _pic_apply_kick_range!(
                solver, field, field_grid, phiL, ExL, EyL, phiR, ExR, EyR,
                kick_scale, hzi, zbias, T(param_source.center), T, first_i, last_i,
            )
        end
    end

    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    vx, vy = _pic_virtual_buffers(workspace, vslot, nsource, T)
    _pic_map_particles(nsource) do first_i, last_i
        _pic_virtual_positions_range!(vx, vy, source, sM, first_i, last_i)
    end
    return vx, vy
end

"""
    _pic_map_particles(f, n)

Run `f(first_i, last_i)` over a partition of `1:n`, threaded above
`_STRONG_STRONG_PARALLEL_KICK_MIN` and serial below it.

**Why this one may chunk by worker count when the deposit may not.** U5-1/U5-2
fixed the rule that a chunk boundary must depend only on the data size, because
a chunk-ordered float FOLD reassociates when the chunk count changes — that is
what moved transverse moments by up to 131,072 ulps between 1, 4 and 8 workers.
The callers here fold nothing: every write is to index `i` of an array indexed
by `i`, read from index `i` of arrays indexed by `i`, with the field planes and
the grid shared read-only. A partition therefore cannot change a single bit, at
any worker count, in any order — which is asserted directly rather than argued,
by the 1-vs-N-worker bitwise pin in the suite.

That distinction is the whole reason this exists as a separate helper from
`_pic_deposit_threaded!`: the deposit accumulates into a shared grid and is
stuck at `_PIC_DEPOSIT_CHUNKS`, while these maps are free to use the whole
machine. Do not add a reduction to a `_pic_map_particles` callback — put it in a
fixed chunk grid instead, or the invariance pin above stops being true.
"""
_pic_map_particles(f::F, n::Integer) where {F} =
    _pic_map_range(f, n, _STRONG_STRONG_PARALLEL_KICK_MIN)

"""
    _pic_map_range(f, n, min_chunk)

The partitioner behind `_pic_map_particles`, with the break-even size as a
parameter so grid sweeps can use it too: a Green-table column carries `2nx`
cells of work, not one particle's worth, so it reaches the same per-chunk cost
at a very different count.
"""
function _pic_map_range(f::F, n::Integer, min_chunk::Integer) where {F}
    n > 0 || return nothing
    nn = Int(n)
    if nn < min_chunk
        f(1, nn)
        return nothing
    end
    # Inside the batched pair loop the pairs are already using the pool, so this
    # map may only have the slice of it that its own pair was given. Without
    # that budget every one of up to 15 concurrent pairs asked for the whole
    # machine -- measured 5.76 s at 16 threads but 6.45 at 32 and 7.08 at 64,
    # the cost of 600+ runnable tasks on 64 threads.
    budget = _PIC_MAP_WORKER_BUDGET[]
    workers = budget > 0 ? budget : _cpu_worker_count()
    # Chunk-size FLOOR, not just a total-size floor, and it is the SAME measured
    # break-even as the serial cutoff above rather than a second tuned number: a
    # chunk smaller than the size at which threading starts to pay is by
    # definition not worth spawning. These maps run once per interaction -- 450
    # of them per turn at the production point -- so the worker count alone is
    # the wrong chunk count. Measured on the 128-thread box at 640k/256k, taking
    # `nchunks = worker count` outright: 6.1 s at 16 workers but 8.6 s at 64 and
    # 63.6 s at 128, where the same input with this floor gives 6.2 / 7.2 / 13.0.
    # The width now follows the DATA and stops at what the data can feed.
    nchunks = clamp(fld(nn, Int(min_chunk)), 1, workers)
    if nchunks <= 1
        f(1, nn)
        return nothing
    end
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(nn, nchunks, chunk)
        first_i > last_i || f(first_i, last_i)
    end
    return nothing
end

"""
Apply the two-node interpolated beam-beam kick and the synchro-beam drift to
field particles `first_i:last_i`. Index-local: see `_pic_map_particles`.
"""
function _pic_apply_kick_range!(solver, field, field_grid, phiL, ExL, EyL,
                                phiR, ExR, EyR, kick_scale, hzi, zbias,
                                source_center, ::Type{T}, first_i, last_i) where {T}
    for i in first_i:last_i
        @inbounds begin
            zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
            zR = one(T) - zL
            Kx, Ky, Kz = _pic_interpolate_kick(
                solver, field_grid, field.x[i], field.y[i],
                phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
            )
            field.px[i] += kick_scale * Kx
            field.py[i] += kick_scale * Ky
            if solver.longitudinal_kick
                field.pz[i] += kick_scale * Kz * hzi
            end
            s = T(0.5) * (source_center - field.z[i])
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
        end
    end
    return nothing
end

"""
The `slice_interpolation = :quadratic` twin of `_pic_apply_kick_range!`.
"""
function _pic_apply_kick_quadratic_range!(solver, field, field_grid, phiL, ExL, EyL,
                                          phiM, ExM, EyM, phiR, ExR, EyR,
                                          kick_scale, hzi, zbias, source_center,
                                          ::Type{T}, first_i, last_i) where {T}
    for i in first_i:last_i
        @inbounds begin
            zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
            Kx, Ky, Kz = _pic_interpolate_kick_quadratic(
                solver, field_grid, field.x[i], field.y[i],
                phiL, ExL, EyL, phiM, ExM, EyM, phiR, ExR, EyR, one(T) - zL,
            )
            field.px[i] += kick_scale * Kx
            field.py[i] += kick_scale * Ky
            if solver.longitudinal_kick
                field.pz[i] += kick_scale * Kz * hzi
            end
            s = T(0.5) * (source_center - field.z[i])
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
        end
    end
    return nothing
end

"""
Drift source particles `first_i:last_i` to the luminosity overlap plane.
Index-local: see `_pic_map_particles`.
"""
function _pic_virtual_positions_range!(vx, vy, source, sM, first_i, last_i)
    for i in first_i:last_i
        @inbounds begin
            vx[i] = source.x[i] + source.px[i] * sM
            vy[i] = source.y[i] + source.py[i] * sM
        end
    end
    return nothing
end

"""
    _pic_build_node_grids!(cache, solver, T, source, center, rep, slice_indices, boundary)

Build **every** node mesh for one (source slice, direction) in two passes.

The obvious per-node implementation costs `nb` passes over the source slice (one
per node drift) and scans every field slice twice (once for each node adjacent to
it). Both loops are memory-bound, so that redundancy dominated: it measured
0.268 s/turn of `:node`'s cost at the production point, 31% of its gap to the
baseline.

Here the source is read **once**, updating all `nb` drift accumulators per
particle, and the field beam is read **once**, accumulating per-slice boxes that
are then unioned pairwise. Same arithmetic, `nb`x and 2x fewer memory passes.

Node `b` sits at `boundary[b]` and is shared by the two slices adjacent to it, so
both sides of that boundary read the same plane on the same mesh and the
transverse kick is continuous there by construction (see
`docs/theory/slice_longitudinal_interpolation.md` Section 10.4).

Sizing: node `b`'s **source** box spans its own drift *and* node `b+1`'s, because
slice `b` also evaluates its longitudinal `phi` difference on this mesh (both
planes of a slice must share a grid, or the discretization error stops cancelling
and `phi_L - phi_R` becomes meaningless); its **field** box covers only the two
slices adjacent to it. Neither involves a union over the whole field beam, so
there is no hourglass blow-up: measured cell coarsening is 1.05-1.12x against
per-slice-pair meshes.
"""
function _pic_build_node_grids!(cache::Dict, solver::PICPoissonSolver, ::Type{T},
                                source, center, rep, slice_indices, boundary) where {T}
    isempty(cache) || return cache
    nb = length(boundary)
    ns = nb - 1
    c = T(center)
    drifts = Vector{T}(undef, nb)
    for b in 1:nb
        drifts[b] = T(0.5) * (c - T(boundary[b]))
    end
    sxlo = fill(T(Inf), nb); sxhi = fill(T(-Inf), nb)
    sylo = fill(T(Inf), nb); syhi = fill(T(-Inf), nb)
    for i in eachindex(source.x)
        @inbounds begin
            x = source.x[i]; px = source.px[i]
            y = source.y[i]; py = source.py[i]
            for b in 1:nb
                d = drifts[b]
                xv = x + px * d; yv = y + py * d
                sxlo[b] = min(sxlo[b], xv); sxhi[b] = max(sxhi[b], xv)
                sylo[b] = min(sylo[b], yv); syhi[b] = max(syhi[b], yv)
            end
        end
    end
    fxlo = fill(T(Inf), ns); fxhi = fill(T(-Inf), ns)
    fylo = fill(T(Inf), ns); fyhi = fill(T(-Inf), ns)
    for sl in 1:ns
        for i in slice_indices[sl]
            @inbounds begin
                sh = T(0.5) * (T(rep.z[i]) - c)
                xv = rep.x[i] + sh * rep.px[i]
                yv = rep.y[i] + sh * rep.py[i]
                fxlo[sl] = min(fxlo[sl], xv); fxhi[sl] = max(fxhi[sl], xv)
                fylo[sl] = min(fylo[sl], yv); fyhi[sl] = max(fyhi[sl], yv)
            end
        end
    end
    # NaN in the node boxes means a non-finite coordinate; +-Inf means an empty
    # slice (legitimate skip). Distinguish the two: fail fast on NaN.
    any(v -> any(isnan, v), (sxlo, sxhi, sylo, syhi)) &&
        _nonfinite_coordinate_error(:source,
            (x=source.x, px=source.px, y=source.y, py=source.py);
            context="node-mesh build")
    any(v -> any(isnan, v), (fxlo, fxhi, fylo, fyhi)) &&
        _nonfinite_coordinate_error(:field,
            (x=rep.x, px=rep.px, y=rep.y, py=rep.py, z=rep.z);
            context="node-mesh build")
    for b in 1:nb
        bn = min(b + 1, nb)
        sxmin = min(sxlo[b], sxlo[bn]); sxmax = max(sxhi[b], sxhi[bn])
        symin = min(sylo[b], sylo[bn]); symax = max(syhi[b], syhi[bn])
        fxmin = T(Inf); fxmax = T(-Inf); fymin = T(Inf); fymax = T(-Inf)
        for adj in (b - 1, b)
            (1 <= adj <= ns) || continue
            isfinite(fxlo[adj]) || continue
            fxmin = min(fxmin, fxlo[adj]); fxmax = max(fxmax, fxhi[adj])
            fymin = min(fymin, fylo[adj]); fymax = max(fymax, fyhi[adj])
        end
        isfinite(fxmin) || continue
        sg, fg = _pic_interaction_grids(solver, sxmin, sxmax, symin, symax,
                                        fxmin, fxmax, fymin, fymax)
        cache[b] = (source_grid=sg, field_grid=fg,
                    green_fft=_pic_green_fft(solver, T, sg, fg))
    end
    return cache
end

"""
    _pic_prebuild_node_caches!(node_cache, solver, T, rep_src, slices_src, rep_fld, slices_fld, dir)

Build every node mesh for every source slice of one direction, **at turn start**.

Node meshes must not be built lazily at first use. A node mesh depends on *all*
field slices (its field box comes from per-slice boxes), so it is sensitive to how
much of the turn has already been applied when it is built -- and
`collision_pair_batches` preserves per-slice ordering but not global ordering, so
"first use" lands at a different beam state on the CUDA wavefront route than on
the CPU's collision-time order. That made CPU/CUDA disagree by 3.8e-5.

The baseline is immune because its grid depends only on the two slices of its own
pair, whose relative order the batching *does* preserve.

Building from the turn-start state makes the mesh a deterministic, schedule-
independent function of the distribution, which is what a discretization choice
should be. Particles move during the turn by far less than the 1.5-cell margin,
and the zero-weight deposition guard counts any escapee rather than smearing it.
"""
function _pic_prebuild_node_caches!(node_cache::Dict, solver::PICPoissonSolver, ::Type{T},
                                    rep_src, slices_src, rep_fld, slices_fld,
                                    dir::Int) where {T}
    for i in eachindex(slices_src.center)
        idx = slices_src.indices[i]
        isempty(idx) && continue
        nc = get!(() -> Dict{Int,Any}(), node_cache, (i, dir))
        isempty(nc) || continue
        # CPU reads `rep_fld` directly by index, so there is no gather to hoist
        # here; the per-source-slice field pass is a strided read, not a copy.
        src = _pic_extract_slice(rep_src, idx)
        _pic_build_node_grids!(nc, solver, T, src, slices_src.center[i], rep_fld,
                               slices_fld.indices, slices_fld.boundary)
    end
    return node_cache
end

"""Node mesh for node `b`, building the whole set on first use."""
function _pic_node_grid!(cache::Dict, solver::PICPoissonSolver, ::Type{T}, source, center,
                         rep, slice_indices, boundary, b::Int) where {T}
    _pic_build_node_grids!(cache, solver, T, source, center, rep, slice_indices, boundary)
    return get(cache, b, nothing)
end

"""
    _pic_interaction_node!(solver, source, param_source, field, param_field, kbb,
                           workspace, gL, gR)

Node-indexed variant of `_pic_interaction!`.

Three field solves instead of two:

1. `F_L` — node `s` at drift `sL`, on node `s`'s mesh `gL`;
2. `F_R` — node `s+1` at drift `sR`, on node `s+1`'s mesh `gR`;
3. `F_Z` — node `s+1` at drift `sR`, on **`gL`**.

The transverse kick blends `F_L`/`F_R`, each read on its own mesh, so at a shared
boundary both adjacent slices evaluate the same node plane on the same mesh and
the kick is continuous. The longitudinal kick uses `F_L` and `F_Z`, which live on
the *same* mesh — required, because `phi_L - phi_R` is a small difference of large
numbers whose discretization error only cancels within one grid (measured: across
grids the difference is wrong by 20-50%, and the discrepancy is not a constant, so
no gauge fix exists).
"""
function _pic_interaction_node!(solver::PICPoissonSolver, source, param_source, field,
                                param_field, kbb, workspace::_PICCPUWorkspace, gL, gR;
                                vslot::Int=0)
    nsource = length(source.x)
    nfield = length(field.x)
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))

    for i in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[i] - T(param_source.center))
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
        end
    end

    # This path had NO dropped-charge accounting of any kind, and it is the one
    # that needs it most: the node meshes are built once at turn start by
    # `_pic_prebuild_node_caches!` and deposited into after the intra-collision
    # kicks, so `grid_extent = :extrema` no longer implies coverage the way it
    # does when a mesh is sized from this slice's own post-drift extrema
    # (2026-08-05_b audit, U6-1; that docstring's claim that "the zero-weight
    # deposition guard counts any escapee" was not implemented anywhere).
    #
    # Each drift plane is counted against the mesh IT deposits into, so a
    # particle outside at both sL and sR counts twice -- two deposits, two lots
    # of lost charge. The field side is counted against the mesh the
    # interpolation reads, after the drift loop above has moved it.
    workspace.dropped[] += _pic_count_outside_box_drifted(
        source.x, source.px, source.y, source.py, sL, sL,
        gL.source_grid.x0, gL.source_grid.x0 + gL.source_grid.width,
        gL.source_grid.y0, gL.source_grid.y0 + gL.source_grid.height)
    workspace.dropped[] += _pic_count_outside_box_drifted(
        source.x, source.px, source.y, source.py, sR, sR,
        gR.source_grid.x0, gR.source_grid.x0 + gR.source_grid.width,
        gR.source_grid.y0, gR.source_grid.y0 + gR.source_grid.height)
    workspace.dropped[] += _pic_count_outside_box(
        field.x, field.y,
        gL.field_grid.x0, gL.field_grid.x0 + gL.field_grid.width,
        gL.field_grid.y0, gL.field_grid.y0 + gL.field_grid.height)

    phiL, ExL, EyL = _pic_solve_drifted_field_with_green_fft!(
        workspace.left, solver, source, sL, gL.source_grid, gL.green_fft, workspace)
    phiR, ExR, EyR = _pic_solve_drifted_field_with_green_fft!(
        workspace.right, solver, source, sR, gR.source_grid, gR.green_fft, workspace)
    phiZ = nothing
    if solver.longitudinal_kick
        nx, ny = solver.grid
        phiZ, _, _ = _pic_solve_drifted_field_with_green_fft!(
            _pic_mid_field!(workspace, nx, ny), solver, source, sR,
            gL.source_grid, gL.green_fft, workspace)
    end

    kick_scale = T(2) * T(kbb)
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    for i in 1:nfield
        @inbounds begin
            zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
            zR = one(T) - zL
            x = field.x[i]; y = field.y[i]
            KxL, KyL, phi_l = _pic_interpolate_kick(
                solver, gL.field_grid, x, y, phiL, ExL, EyL, phiL, ExL, EyL, one(T), zero(T))
            KxR, KyR, _ = _pic_interpolate_kick(
                solver, gR.field_grid, x, y, phiR, ExR, EyR, phiR, ExR, EyR, one(T), zero(T))
            field.px[i] += kick_scale * (zL * KxL + zR * KxR)
            field.py[i] += kick_scale * (zL * KyL + zR * KyR)
            if solver.longitudinal_kick
                _, _, Kz = _pic_interpolate_kick(
                    solver, gL.field_grid, x, y, phiL, ExL, EyL, phiZ, ExL, EyL, one(T), zero(T))
                field.pz[i] += kick_scale * Kz * hzi
            end
            s = T(0.5) * (T(param_source.center) - field.z[i])
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
        end
    end

    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    vx, vy = _pic_virtual_buffers(workspace, vslot, nsource, T)
    _pic_map_particles(nsource) do first_i, last_i
        _pic_virtual_positions_range!(vx, vy, source, sM, first_i, last_i)
    end
    return vx, vy
end

@inline function _slice_interpolation_parameters(lb, rb)
    T = typeof(lb + rb)
    denom = T(rb - lb)
    if !isfinite(denom) || denom == zero(T)
        return zero(T), T(0.5)
    end
    hzi = inv(denom)
    return hzi, T(rb) * hzi
end

"""
    _pic_axis_extent(method, lo, hi, origin, ds, ds2, n, k)

Turn one axis' shifted single-pass accumulators into a `(lo, hi)` mesh extent.
`ds` and `ds2` are the sums of `x-origin` and `(x-origin)^2`.

- `:extrema` returns the sample min/max. Stable in the sense that it always
  covers every particle, but `O(1)`-noisy: for `n` particles the maximum is
  `sigma*sqrt(2 ln n)` with Gumbel fluctuation `sigma/sqrt(2 ln n)`, several
  percent of the box, and it drifts systematically with slice population.
- `:sigma` returns `mean +- k*sd`. Its noise is `O(1/sqrt(n))` instead: measured
  3.5-8.2x at the committed defaults (200,000 particles, 15 slices,
  8 turns): 8.2x and 5.1x in x slice-to-slice and turn-to-turn, 3.9x and
  3.5x in y. The quoted range used to be "4-8x" -- a single run's numbers
  with the envelope rounded off, and both vertical-plane ratios sit under
  its floor (2026-08-05_b audit, U23-14). The plane asymmetry is the point:
  y carries fewer sigma of aperture per slice, so its extremum is less
  noisy to begin with and there is less for `:sigma` to recover.
  Stabler than `:extrema` on every one of the four measures. It does
  **not** guarantee coverage, which is why `_pic_cic_weights` drops out-of-range
  particles and the caller counts them.

A `:quantile` estimator was implemented, measured and **removed**: at a coverage
target tight enough to avoid charge loss the target rounds to *all* particles for
realistic slice populations, so it degenerates to the extremum and adds histogram
quantization noise on top -- measured *worse* than `:extrema`
(`validation/pic_grid_extent_stability.jl`).

Degenerate input (zero spread, `n < 2`) falls back to the extrema so a slice with
identical coordinates still produces a usable mesh.
"""
@inline function _pic_axis_extent(method::Symbol, lo, hi, origin, ds, ds2, n::Int, k)
    method === :extrema && return lo, hi
    n < 2 && return lo, hi
    T = typeof(lo)
    invn = inv(T(n))
    mean_offset = T(ds) * invn
    m = T(origin) + mean_offset
    var = max(_shifted_second_moment(T(ds2), mean_offset, invn), zero(T))
    sd = sqrt(var)
    half = T(k) * sd
    half > zero(T) || return lo, hi
    return m - half, m + half
end

"""
Count PARTICLES outside the mesh box `[xlo, xhi] x [ylo, yhi]`, or non-finite.

Per particle, not per axis: the old per-axis pair of counts reported a corner
escapee — outside in both x and y — as 2, though the docstring and the warning
present the number as a count of particles (2026-08-05 audit, U5-6).
"""
function _pic_count_outside_box(xs, ys, xlo, xhi, ylo, yhi)
    c = 0
    for i in eachindex(xs, ys)
        @inbounds x = xs[i]
        @inbounds y = ys[i]
        (isfinite(x) && xlo <= x <= xhi &&
         isfinite(y) && ylo <= y <= yhi) || (c += 1)
    end
    return c
end

"""
Count source particles whose drifted deposit position — `x + px*s` at either
interaction plane `s = sL` or `s = sR`, the coordinates `_pic_deposit_drifted!`
actually bins — falls outside the source mesh box. One count per particle even
when both planes (or both axes) miss (2026-08-05 audit, U5-5/U5-6).
"""
function _pic_count_outside_box_drifted(xs, pxs, ys, pys, sL, sR, xlo, xhi, ylo, yhi)
    c = 0
    for i in eachindex(xs, pxs, ys, pys)
        @inbounds begin
            xl = xs[i] + pxs[i] * sL
            yl = ys[i] + pys[i] * sL
            xr = xs[i] + pxs[i] * sR
            yr = ys[i] + pys[i] * sR
        end
        (isfinite(xl) && xlo <= xl <= xhi && isfinite(yl) && ylo <= yl <= yhi &&
         isfinite(xr) && xlo <= xr <= xhi && isfinite(yr) && ylo <= yr <= yhi) || (c += 1)
    end
    return c
end

"""
    _pic_quantize_extent(w, q)

Round `w` up to the next power of `2^q`. With `q = 1/8` the ladder steps are ~9%,
so meshes whose requested extents differ by less than that collapse onto the same
value. Used by `grid_quantize`; `q = 0` disables it.
"""
@inline function _pic_quantize_extent(w, q)
    (q > zero(q) && isfinite(w) && w > zero(w)) || return w
    return exp2(ceil(log2(w) / q) * q)
end

@inline function _pic_resolve_transverse_extent(solver::PICPoissonSolver,
                                                xspan, yspan, context::AbstractString)
    # The working precision is the BOUNDS' type; solver configuration
    # scalars convert as values rather than promoting the type (2026-08-08,
    # from the solver-matrix finding): promoting through the solver's Float64
    # fields gave Float32 beams Float64 grid geometry, and every per-particle
    # deposit and interpolation then mixed Float32 coordinates with Float64
    # origins/spacings -- measured 1.5-1.6x SLOWER than the uniform Float64
    # path on the CPU at production size. The CUDA path never had this
    # because its launch wrappers convert grid scalars to the working type at
    # the kernel boundary. Float64 runs are bit-unchanged (T is Float64
    # there either way).
    T = promote_type(typeof(xspan), typeof(yspan))
    floor_x = T(solver.min_transverse_extent[1])
    floor_y = T(solver.min_transverse_extent[2])
    width = max(T(xspan), floor_x)
    height = max(T(yspan), floor_y)
    if !(isfinite(width) && isfinite(height) &&
         width > zero(T) && height > zero(T))
        throw(ArgumentError(
            "$(context) requires finite, positive transverse extents; observed " *
            "(x=$(xspan), y=$(yspan)) with min_transverse_extent=" *
            "$(solver.min_transverse_extent). Supply a positive physical bound " *
            "for every degenerate axis."))
    end
    return width, height
end

function _pic_interaction_grids(solver::PICPoissonSolver, sxmin, sxmax, symin, symax,
                                fxmin, fxmax, fymin, fymax)
    nx, ny = solver.grid
    # Bounds' type, not the solver's -- see _pic_resolve_transverse_extent.
    T = promote_type(typeof(sxmin), typeof(fxmin))
    width, height = _pic_resolve_transverse_extent(
        solver,
        max(T(sxmax - sxmin), T(fxmax - fxmin)),
        max(T(symax - symin), T(fymax - fymin)),
        "PIC interaction grid",
    )
    tx = width / (nx - 4)
    ty = height / (ny - 4)
    width += 3 * tx
    height += 3 * ty
    q = T(solver.grid_quantize)
    if q > zero(T)
        # Snap the extent to a geometric ladder and the origins to whole cells, so
        # slices (and turns) whose distributions differ by less than one ladder
        # step land on *exactly* the same mesh instead of a nearly-identical one.
        # A nearly-identical mesh still produces a full-size discretization jump.
        width = _pic_quantize_extent(width, q)
        height = _pic_quantize_extent(height, q)
        hx = width / (nx - 1)
        hy = height / (ny - 1)
        # Centre on the data, then snap to the nearest whole cell: rounding rather
        # than flooring bounds the shift to half a cell, preserving margin.
        sx0 = round((T(sxmin + sxmax) / 2 - width / 2) / hx) * hx
        sy0 = round((T(symin + symax) / 2 - height / 2) / hy) * hy
        fx0 = round((T(fxmin + fxmax) / 2 - width / 2) / hx) * hx
        fy0 = round((T(fymin + fymax) / 2 - height / 2) / hy) * hy
        sx0, fx0 = _pic_align_grid_origins(solver.green_type, sx0, fx0, hx)
        sy0, fy0 = _pic_align_grid_origins(solver.green_type, sy0, fy0, hy)
        return (x0=sx0, y0=sy0, width=width, height=height),
               (x0=fx0, y0=fy0, width=width, height=height)
    end
    sx0 = T(sxmin) - T(1.5) * tx
    sy0 = T(symin) - T(1.5) * ty
    fx0 = T(fxmin) - T(1.5) * tx
    fy0 = T(fymin) - T(1.5) * ty
    sx0, fx0 = _pic_align_grid_origins(solver.green_type, sx0, fx0, tx)
    sy0, fy0 = _pic_align_grid_origins(solver.green_type, sy0, fy0, ty)
    return (x0=sx0, y0=sy0, width=width, height=height),
           (x0=fx0, y0=fy0, width=width, height=height)
end

function _pic_green_cache(solver::PICPoissonSolver, ::Type{T}) where {T}
    cache = Symbol(solver.green_cache)
    cache == :slice_pair && return _PICSlicePairGreenCache{T}(
        Dict{Tuple{Int,Int,Int},_PICSlicePairGreenEntry{T}}(), 0, 0, 0,
        ReentrantLock(),
    )
    return nothing
end

function _pic_slice_pair_green!(workspace::_PICCPUWorkspace, solver::PICPoissonSolver, ::Type{T},
                                cache, cache_key, source_grid, field_grid,
                                source_bounds, field_bounds) where {T}
    if cache isa _PICSlicePairGreenCache{T} && cache_key !== nothing
        # Explicit lock/unlock rather than `lock(cache.lock) do ... end`: the
        # do-block form is a closure over locals this function also assigns,
        # which is the `Core.Box` shape the permanent lowered-code sweep exists
        # to reject.
        local entry, usable
        lock(cache.lock)
        try
            entry = get(cache.entries, cache_key, nothing)
            usable = entry !== nothing && _pic_slice_pair_entry_usable(
                solver, entry, source_grid, field_grid, source_bounds, field_bounds)
            if usable
                cache.hits += 1
                entry.uses += 1
            end
        finally
            unlock(cache.lock)
        end
        if usable
            return entry.source_grid, entry.field_grid, entry.green_fft
        end
        # Rebuilt OUTSIDE the lock, into this worker's own workspace: the Green
        # table and its FFT are the expensive part of a miss, and holding the
        # cache lock across them would serialize the batch on the one thing
        # batching is meant to overlap.
        expanded_source = _pic_expand_grid_by(source_grid, T(1) + T(solver.slice_pair_green_growth))
        expanded_field = _pic_expand_grid_by(field_grid, T(1) + T(solver.slice_pair_green_growth))
        expanded_source, expanded_field = _pic_realign_expanded_grids(
            solver.green_type, expanded_source, expanded_field, solver.grid...)
        green_fft = copy(_pic_green_fft!(workspace, solver, T, expanded_source, expanded_field))
        lock(cache.lock)
        try
            if entry === nothing
                cache.misses += 1
                cache.entries[cache_key] = _PICSlicePairGreenEntry{T}(expanded_source, expanded_field, green_fft, 1, 0)
            else
                cache.rebuilds += 1
                entry.rebuilds += 1
                cache.entries[cache_key] = _PICSlicePairGreenEntry{T}(expanded_source, expanded_field, green_fft, 1, entry.rebuilds)
            end
        finally
            unlock(cache.lock)
        end
        return expanded_source, expanded_field, green_fft
    end
    return source_grid, field_grid, _pic_green_fft!(workspace, solver, T, source_grid, field_grid)
end

function _pic_slice_pair_entry_usable(solver::PICPoissonSolver, entry, source_grid, field_grid, source_bounds, field_bounds)
    min_ratio = solver.slice_pair_green_min_ratio
    _pic_grid_size_usable(entry.source_grid, source_grid, min_ratio) || return false
    _pic_grid_size_usable(entry.field_grid, field_grid, min_ratio) || return false
    _pic_grid_covers_bounds(solver, entry.source_grid, source_bounds) || return false
    _pic_grid_covers_bounds(solver, entry.field_grid, field_bounds) || return false
    return true
end

function _pic_grid_size_usable(cached_grid, requested_grid, min_ratio)
    cached_grid.width >= requested_grid.width || return false
    cached_grid.height >= requested_grid.height || return false
    requested_grid.width >= min_ratio * cached_grid.width || return false
    requested_grid.height >= min_ratio * cached_grid.height || return false
    return true
end

function _pic_grid_covers_bounds(solver::PICPoissonSolver, grid, bounds)
    nx, ny = solver.grid
    T = promote_type(typeof(grid.x0), typeof(bounds.xmin))
    hx = T(grid.width) / T(nx - 1)
    hy = T(grid.height) / T(ny - 1)
    margin = T(_PIC_TEMPLATE_MARGIN_CELLS)
    grid.x0 + margin * hx <= bounds.xmin || return false
    grid.x0 + grid.width - margin * hx >= bounds.xmax || return false
    grid.y0 + margin * hy <= bounds.ymin || return false
    grid.y0 + grid.height - margin * hy >= bounds.ymax || return false
    return true
end

function _pic_expand_grid_by(grid, factor)
    factor <= one(factor) && return grid
    T = promote_type(typeof(grid.x0), typeof(grid.width), typeof(factor))
    new_width = T(grid.width) * T(factor)
    new_height = T(grid.height) * T(factor)
    return (
        x0=T(grid.x0) - (new_width - T(grid.width)) / T(2),
        y0=T(grid.y0) - (new_height - T(grid.height)) / T(2),
        width=new_width,
        height=new_height,
    )
end

"""
    _pic_realign_expanded_grids(green_type, source_grid, field_grid, nx, ny)

Restore the source/field origin alignment that `_pic_interaction_grids` establishes
and `_pic_expand_grid_by` destroys.

The expansion scales `width` with the node count fixed, so the cell size grows by
the same factor while the origin separation does not: a separation of exactly `k`
cells becomes `k / (1 + slice_pair_green_growth)` cells, which is not an integer.
At the default growth of 0.25 a measured 22.000000-cell separation became
17.600000.

That matters for the two kernels whose value depends on where the two grids sit
relative to each other:

- `:lattice` is tabulated by **integer** cell separation, and `_pic_green_lattice!`
  rounded without checking. The cached Green function was therefore that of a
  source displaced by the rounding residual — measured 0.400 cells.
- `:standard` relies on the deliberate half-cell offset to stay off its own
  singularity; the expansion maps `k + 1/2` to `0.8k + 0.4`, which is an integer
  whenever `k ≡ 2 (mod 5)`, putting a node exactly on `r = 0`.

`:integrated` evaluates its kernel at real coordinates and does not depend on the
alignment, so it is deliberately left untouched: re-aligning it would move the
default mesh and change results that carry no defect.
"""
function _pic_realign_expanded_grids(green_type, source_grid, field_grid,
                                     nx::Integer, ny::Integer)
    Symbol(green_type) === :integrated && return source_grid, field_grid
    hx = source_grid.width / (nx - 1)
    hy = source_grid.height / (ny - 1)
    sx0, fx0 = _pic_align_grid_origins(green_type, source_grid.x0, field_grid.x0, hx)
    sy0, fy0 = _pic_align_grid_origins(green_type, source_grid.y0, field_grid.y0, hy)
    return ((x0=sx0, y0=sy0, width=source_grid.width, height=source_grid.height),
            (x0=fx0, y0=fy0, width=field_grid.width, height=field_grid.height))
end

function _pic_report_green_cache(cache)
    cache === nothing && return nothing
    _strong_strong_diagnostics().cache_stats || return nothing
    if cache isa _PICSlicePairGreenCache
        total = cache.hits + cache.misses + cache.rebuilds
        reuse_rate = total == 0 ? 0.0 : cache.hits / total
        initial_fill_rate = total == 0 ? 0.0 : cache.misses / total
        rebuild_rate = total == 0 ? 0.0 : cache.rebuilds / total
        println(
            "PIC slice-pair Green cache: entries=$(length(cache.entries)), " *
            "hits=$(cache.hits), misses=$(cache.misses), rebuilds=$(cache.rebuilds), " *
            "reuse_rate=$(reuse_rate), initial_fill_rate=$(initial_fill_rate), rebuild_rate=$(rebuild_rate)"
        )
    end
    return nothing
end

function _pic_align_grid_origins(green_type, source0, field0, h)
    f1 = source0 / h - floor(source0 / h)
    f2 = field0 / h - floor(field0 / h)
    t = (f2 - f1) / 2
    if Symbol(green_type) == :standard
        t += t > 0 ? -0.25 : 0.25
    else
        # Defensive, and unreachable as written (2026-08-05_b audit, U6-9).
        # `f1` and `f2` are `v/h - floor(v/h)`, so each lies in [0, 1] -- note
        # [0, 1], not [0, 1): for a tiny negative `v/h` the subtraction rounds
        # to exactly 1.0 in Float64, which the usual "fractional part is < 1"
        # argument misses. Even so `t = (f2 - f1)/2` is bounded by 0.5 in
        # magnitude, because reaching |t| > 0.5 would need |f2 - f1| > 1 and
        # both lie within [0, 1]. So neither branch fires.
        #
        # Kept rather than deleted: it is a two-line wrap whose premise depends
        # on that float subtlety, and it would be correct if a future change to
        # how `f1`/`f2` are formed made it reachable. The post-shift invariant
        # that actually matters -- fractional separation exactly 0 here, exactly
        # +/-0.5 for `:standard` -- holds either way.
        if t > 0.5
            t -= 0.5
        elseif t < -0.5
            t += 0.5
        end
    end
    shift = t * h
    return source0 + shift, field0 - shift
end

function _pic_solve_field(solver::PICPoissonSolver, x, y, source_grid, field_grid)
    nx, ny = solver.grid
    T = eltype(x)
    workspace = _pic_cpu_workspace(T, nx, ny)
    green_fft = _pic_green_fft(solver, T, source_grid, field_grid)
    return _pic_solve_field_with_green_fft!(
        workspace.left, solver, x, y, source_grid, green_fft, workspace,
    )
end

function _pic_green_fft(solver::PICPoissonSolver, ::Type{T}, source_grid, field_grid) where {T}
    nx, ny = solver.grid
    _validate_pic_grid(nx, ny)
    green = Matrix{T}(undef, 2nx, 2ny)
    _pic_green!(green, solver.green_type, T(field_grid.x0), T(field_grid.y0),
                T(source_grid.x0), T(source_grid.y0),
                T(source_grid.width) / (nx - 1), T(source_grid.height) / (ny - 1),
                nx, ny)
    return fft(green)
end

function _pic_green_fft!(workspace::_PICCPUWorkspace, solver::PICPoissonSolver,
                         ::Type{T}, source_grid, field_grid) where {T}
    nx, ny = solver.grid
    _validate_pic_grid(nx, ny)
    hx = T(source_grid.width) / (nx - 1)
    hy = T(source_grid.height) / (ny - 1)
    _pic_green!(workspace.green, solver.green_type, T(field_grid.x0), T(field_grid.y0),
                T(source_grid.x0), T(source_grid.y0), hx, hy, nx, ny)
    workspace.green_fft .= workspace.green
    workspace.fft_plan * workspace.green_fft
    return workspace.green_fft
end

function _pic_solve_field_with_green_fft!(field::_PICFieldWorkspace,
                                          solver::PICPoissonSolver, x, y,
                                          source_grid, green_fft,
                                          workspace::_PICCPUWorkspace)
    nx, ny = solver.grid
    T = eltype(x)
    hx = T(source_grid.width) / (nx - 1)
    hy = T(source_grid.height) / (ny - 1)
    charge = workspace.charge
    fill!(charge, zero(T))
    _pic_deposit!(charge, solver.deposit_method, x, y, T(source_grid.x0), T(source_grid.y0), hx, hy, nx, ny, workspace)
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = field.phi
    for j in 1:ny, i in 1:nx
        @inbounds phi[i, j] = real(spectral[i, j])
    end
    _pic_field!(field.Ex, field.Ey, phi, hx, hy, _pic_fourth_order(solver))
    return phi, field.Ex, field.Ey
end

function _pic_solve_drifted_field_with_green_fft!(field::_PICFieldWorkspace,
                                                  solver::PICPoissonSolver, source, drift_s,
                                                  source_grid, green_fft,
                                                  workspace::_PICCPUWorkspace)
    nx, ny = solver.grid
    T = eltype(source.x)
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    charge = workspace.charge
    fill!(charge, zero(T))
    _pic_deposit_drifted!(
        charge, solver.deposit_method, source.x, source.px, source.y, source.py, T(drift_s),
        T(source_grid.x0), T(source_grid.y0), hx, hy, nx, ny, workspace,
    )
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = field.phi
    for j in 1:ny, i in 1:nx
        @inbounds phi[i, j] = real(spectral[i, j])
    end
    _pic_field!(field.Ex, field.Ey, phi, hx, hy, _pic_fourth_order(solver))
    return phi, field.Ex, field.Ey
end

function _pic_deposit!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    # Path choice by data and mesh size ONLY: gating on the worker count made
    # the 1-worker result differ from every multi-worker one (U5-1), and gating
    # on n alone sent small slices on large grids into a deposit whose fixed
    # cost is grid-sized (U6-2).
    if _pic_deposit_parallel(length(x), nx, ny)
        return _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    end
    return _pic_deposit_serial!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
end

function _pic_deposit!(charge, method, x, y, x0, y0, hx, hy, nx, ny,
                       workspace::_PICCPUWorkspace)
    # Path choice by data and mesh size ONLY: gating on the worker count made
    # the 1-worker result differ from every multi-worker one (U5-1), and gating
    # on n alone sent small slices on large grids into a deposit whose fixed
    # cost is grid-sized (U6-2).
    if _pic_deposit_parallel(length(x), nx, ny)
        return _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny, workspace)
    end
    return _pic_deposit_serial!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
end

function _pic_deposit_drifted!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny,
                               workspace::_PICCPUWorkspace)
    # Path choice by data and mesh size ONLY: gating on the worker count made
    # the 1-worker result differ from every multi-worker one (U5-1), and gating
    # on n alone sent small slices on large grids into a deposit whose fixed
    # cost is grid-sized (U6-2).
    if _pic_deposit_parallel(length(x), nx, ny)
        return _pic_deposit_drifted_threaded!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny, workspace)
    end
    return _pic_deposit_drifted_serial!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny)
end

function _pic_deposit_serial!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    hxi = inv(hx); hyi = inv(hy)
    for i in eachindex(x)
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((y[i] - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((y[i] - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_deposit_drifted_serial!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny)
    hxi = inv(hx); hyi = inv(hy)
    for i in eachindex(x)
        xd = x[i] + px[i] * drift_s
        yd = y[i] + py[i] * drift_s
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((yd - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((yd - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    # Fixed chunk grid: results must not depend on the worker count (U5-1).
    nchunks = _PIC_DEPOSIT_CHUNKS
    local_charge = [zero(charge) for _ in 1:nchunks]
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(length(x), nchunks, chunk)
        local_grid = local_charge[chunk]
        _pic_deposit_range!(local_grid, method, x, y, x0, y0, hx, hy, nx, ny, first_i, last_i)
    end
    for local_grid in local_charge
        charge .+= local_grid
    end
    return charge
end

function _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny,
                                workspace::_PICCPUWorkspace)
    nchunks = _PIC_DEPOSIT_CHUNKS
    local_charge = workspace.local_charge
    # The invariant, not a silent fallback (2026-08-05_b audit, U6-10).
    # `_pic_cpu_workspace` always builds `local_charge` with exactly
    # `_PIC_DEPOSIT_CHUNKS` entries and both call sites compare against that
    # same constant, so this cannot fire -- and the two fallbacks DISAGREED
    # about what to do if it did: this one silently re-entered the threaded
    # path, its drifted twin the serial one. A workspace that does not match
    # its own constant is a construction bug, and a quietly different code
    # path is the worst way to learn about it.
    length(local_charge) == nchunks || error(
        "PIC deposit workspace has $(length(local_charge)) chunk grids but the " *
        "deposit wants $(nchunks); _pic_cpu_workspace builds _PIC_DEPOSIT_CHUNKS " *
        "of them, so this is a workspace construction bug.")
    _run_logical_workers(nchunks) do chunk, _
        local_grid = local_charge[chunk]
        fill!(local_grid, zero(eltype(local_grid)))
        first_i, last_i = _chunk_bounds(length(x), nchunks, chunk)
        _pic_deposit_range!(local_grid, method, x, y, x0, y0, hx, hy, nx, ny, first_i, last_i)
    end
    for local_grid in local_charge
        charge .+= local_grid
    end
    return charge
end

function _pic_deposit_drifted_threaded!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny,
                                        workspace::_PICCPUWorkspace)
    nchunks = _PIC_DEPOSIT_CHUNKS
    local_charge = workspace.local_charge
    # Same invariant as the undrifted twin above (U6-10).
    length(local_charge) == nchunks || error(
        "PIC drifted-deposit workspace has $(length(local_charge)) chunk grids " *
        "but the deposit wants $(nchunks); _pic_cpu_workspace builds " *
        "_PIC_DEPOSIT_CHUNKS of them, so this is a workspace construction bug.")
    _run_logical_workers(nchunks) do chunk, _
        local_grid = local_charge[chunk]
        fill!(local_grid, zero(eltype(local_grid)))
        first_i, last_i = _chunk_bounds(length(x), nchunks, chunk)
        _pic_deposit_drifted_range!(
            local_grid, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny, first_i, last_i,
        )
    end
    for local_grid in local_charge
        charge .+= local_grid
    end
    return charge
end

function _pic_deposit_drifted_range!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny, first_i, last_i)
    hxi = inv(hx); hyi = inv(hy)
    for i in first_i:last_i
        xd = x[i] + px[i] * drift_s
        yd = y[i] + py[i] * drift_s
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((yd - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((yd - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_deposit_range!(charge, method, x, y, x0, y0, hx, hy, nx, ny, first_i, last_i)
    hxi = inv(hx); hyi = inv(hy)
    for i in first_i:last_i
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((y[i] - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((y[i] - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

"""
    _pic_cic_weights(u, n)

CIC cell index and weights for normalized coordinate `u`.

A coordinate outside `[0, n-1]`, or non-finite, returns **zero weights** so that it
contributes nothing. Clamping the index while keeping the weight -- the previous
behaviour -- smeared the particle's full charge onto the boundary cell, a spurious
charge sheet strictly worse than dropping it; and `floor(Int, NaN)` threw an
`InexactError` from deep inside the kernel while the CUDA path silently poisoned
the whole charge grid. The `!(0 <= u <= n-1)` form is deliberate: every comparison
against `NaN` is false, so non-finite input takes the zero-weight branch.

With `grid_extent = :extrema` this branch is unreachable, because the mesh is sized
from the particle extrema plus a 1.5-cell margin. It exists so that the robust
estimators (`:sigma`, `:quantile`) cannot silently corrupt the field.
"""
@inline function _pic_cic_weights(u, n)
    if !(zero(u) <= u <= u_of(n))
        return 1, (zero(u), zero(u))
    end
    base = clamp(floor(Int, u) + 1, 1, n - 1)
    # The fraction is measured from the CLAMPED base, not from floor(u): at
    # u == n-1 — in range by the guard above — the clamp moves base one cell
    # inward while `u - floor(u) == 0` still produced weights (1, 0), putting
    # the full charge one cell INWARD of the particle (measured: charge centre
    # of mass 3.0 for a particle at u = 4, n = 5). `u - (base - 1)` gives
    # weights (0, 1) there, so the boundary node keeps the charge; everywhere
    # else base - 1 == floor(u) and the value is bit-identical
    # (2026-08-05 audit, U5-7).
    f = clamp(u - (base - 1), zero(u), one(u))
    return base, (one(f) - f, f)
end

"""Upper bound of the valid normalized coordinate range for an `n`-point axis."""
@inline u_of(n) = float(n - 1)

"""
    _pic_tsc_weights(u, n)

TSC cell index and weights. Same out-of-range contract as `_pic_cic_weights`:
outside `[0, n-1]` or non-finite contributes nothing.

**Inside** the range the two differ, and the difference is deliberate rather than
an oversight. The three-cell stencil does not fit within half a cell of either
end, so `base` is clamped into `[1, n-2]`; a particle at `u < 1/2` or
`u > n - 3/2` therefore has its whole stencil displaced by exactly one cell
(measured: charge centre of mass at `u + 1.000`), which is the index-clamping
behaviour `_pic_cic_weights` documents as worse than dropping. Widening the
stencil check to drop those particles instead would lose their charge entirely,
which is not better.

It does not arise on an interaction mesh: `:extrema` sizing puts every particle
in `u ∈ [1.5, n-2.5]` (measured `[1.591, 61.591]` at `n = 64`). It does arise on
the luminosity mesh, whose 0.05-cell margin is sized for CIC — measured 2 to 3
particles of 200,000. Widening that margin was measured and is **worse**: at a
fixed cell count a larger margin means coarser cells over the beam, and the
overlap integral moved from `-5.5e-3` to `-6.3e-3` against the analytic Gaussian
result. The margin stays as it is.
"""
@inline function _pic_tsc_weights(u, n)
    if !(zero(u) <= u <= u_of(n))
        return 1, (zero(u), zero(u), zero(u))
    end
    # Literals typed to the coordinate, as the CUDA twin already writes them
    # (2026-08-05_b audit, U6-6). Untyped `0.125` / `0.5` / `0.75` promote a
    # Float32 coordinate to Float64, so a Float32 beam got Float64 TSC weights
    # on the CPU while `_cuda_pic_tsc_weights` computed them in Float32 -- and
    # the CPU then accumulated `Float32_array += Float64_product`, i.e. in
    # Float64 with a final rounding, where the device accumulates in Float32.
    # The CIC pair beside this one is already type-clean on both sides, so TSC
    # was the only divergence left in a deposit the 2026-08-05 audit (U2-3)
    # aligned in closed form.
    ix = floor(Int, u)
    f = u - floor(u)
    c8 = oftype(f, 0.125); half = oftype(f, 0.5); c34 = oftype(f, 0.75)
    if f < half
        t = f * f
        w = (c8 + half * (t - f), c34 - t, c8 + half * (t + f))
        base = ix
    else
        fr = one(f) - f
        t = fr * fr
        w = (c8 + half * (t + fr), c34 - t, c8 + half * (t - fr))
        base = ix + 1
    end
    return clamp(base, 1, n - 2), w
end

@inline function _pic_atan_ratio(num, den)
    if den == 0
        num == 0 && return zero(promote_type(typeof(num), typeof(den)))
        # `PI` is not a name this module defines -- Constants.jl exports TWOPI,
        # SQRTPI, SQRT2PI and SQRT2, never PI -- so this branch raised
        # UndefVarError for every on-axis node of the default :integrated Green
        # kernel. The value itself never mattered: `_pic_kernel_integral`
        # multiplies it by the coordinate that is zero on that branch, so the
        # correct result is 0.0 either way and no working result can move.
        return copysign(oftype(num / one(den), pi / 2), num)
    end
    return atan(num / den)
end

@inline function _pic_kernel_integral(x, y)
    r2 = x * x + y * y
    iszero(r2) && return zero(r2)
    return (log(r2) - 3) * x * y + _pic_atan_ratio(y, x) * x * x + _pic_atan_ratio(x, y) * y * y
end

function _pic_green(green_type, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    T = promote_type(typeof(field_x0), typeof(hx))
    green = Matrix{T}(undef, 2nx, 2ny)
    _pic_green!(green, green_type, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    return green
end

# ---------------------------------------------------------------------------
# Lattice Green function (green_type=:lattice)
#
# Inverts the five-point discrete Laplacian exactly instead of discretizing the
# continuum -ln r. Derivation, normalization and measurements:
# docs/theory/pic_free_space_kernels.md Section 3.4.
#
# Two properties make this affordable, both derived in that section:
#   * G depends only on (nx, ny) and the ASPECT RATIO rho = hx/hy, never on the
#     absolute spacing -- absolute h enters as an additive -ln(h) gauge constant.
#   * That constant is invisible to the physics: transverse kicks use the mesh
#     gradient, and the longitudinal kick uses the DIFFERENCE phiL - phiR (see
#     _pic_interpolate_kick), so a uniform offset cancels exactly.
# So one table per (nx, ny, quantized rho) serves every slice pair and every turn.
#
# The table is indexed by INTEGER lattice separation, which is legitimate because
# _pic_align_grid_origins puts the source and field origins an exact integer
# number of cells apart for every green_type except :standard (which deliberately
# offsets by half a cell to dodge the singularity, and therefore cannot use this
# kernel).
const _PIC_LATTICE_GREEN_MULT = 8          # periodic box multiple of the padded extent
# ...but applied per axis, scaled by the aspect ratio. The free-space limit needs
# the periodic box to be large **in physical units** in both directions. A flat
# multiple of the padded extent is an INDEX-unit criterion: at `rho = hx/hy = 11`
# the box is `Mx*hx` by `My*hy`, i.e. eleven times flatter than it is wide, while
# the separations the table must cover span `+-2nx` cells in x and `+-2ny` in y --
# also eleven times wider than tall in physical units. So the y-images sit an
# order of magnitude closer than the x-images and contaminate every separation far
# along x. Measured directly on the table (spread of `G + ln r`, which is zero for
# a true `-ln r + const`): 8.7e-3 at rho=1, but 2.7e-1 at rho=11 and 8.9e-1 at
# rho=25, and the x-axis part of that vanishes when the box grows while the y-axis
# part -- the genuine near-origin lattice correction -- does not.
#
# End to end this defeated the option's entire purpose. Median relative field
# error against Bassetti-Erskine at grid 64, versus the `:integrated` default:
#
#     aspect    :integrated    :lattice (mult 8)    :lattice (aspect-aware)
#     round       9.60e-04           1.74e-03              1.74e-03
#     5:1         2.33e-03           6.76e-03              1.92e-03
#     11:1        3.10e-03           3.21e-02              2.64e-03
#     25:1        3.70e-03           1.54e-01              3.18e-03
#
# The round row's last two columns MUST be identical, and this table said
# 1.48e-03 there (2026-08-05_b audit, U26-7). At rho = 1,
# `_pic_lattice_box_mult(1.0)` returns (8, 8) -- literally the flat mult-8 box --
# so the two columns are the same computation and cannot differ. The theory
# note's §3.4 table is the self-consistent one (1.74e-3 in both) and this
# comment was the copy that drifted.
#
# `:lattice` exists for "flat-beam field-accuracy studies only", and at the 11:1
# production aspect ratio it was **10.3x worse** than the kernel it replaces. With
# the aspect-aware box it is 1.18x better, which is the direction
# docs/theory/pic_free_space_kernels.md Section 3.4 claims.
#
# The cap bounds the auxiliary FFT: `8*rho` would reach 200 at rho=25, and the FFT
# is `Mx*My`. Measured adequate through rho=25 at the cap (the 3.18e-3 above is at
# multy=64, where 8*rho would have asked for 200); beyond that it is unmeasured.
const _PIC_LATTICE_GREEN_MULT_MAX = 64
_pic_lattice_box_mult(rho) = (
    clamp(round(Int, _PIC_LATTICE_GREEN_MULT * max(one(rho), inv(rho))),
          _PIC_LATTICE_GREEN_MULT, _PIC_LATTICE_GREEN_MULT_MAX),
    clamp(round(Int, _PIC_LATTICE_GREEN_MULT * max(one(rho), rho)),
          _PIC_LATTICE_GREEN_MULT, _PIC_LATTICE_GREEN_MULT_MAX),
)
# rho quantization. Measured sensitivity at the 11:1 production beams, grid 128
# (:integrated reference 1.991e-2): exact rho 1.348e-2, 0.5% 1.529e-2, 2% 2.055e-2,
# 5% 3.055e-2. Beyond ~2% the kernel is WORSE than the one it replaces, so this
# cannot be coarsened to make the cache smaller.
const _PIC_LATTICE_GREEN_RHO_TOL = 0.005
# Hard cap. Production generates hundreds of distinct aspect ratios (306 in an
# 18-turn 15-slice run) and each table is (4nx+1)x(4ny+1) Float64 -- 2.1 MB at
# grid 128 -- so an uncapped cache reached ~645 MB. The cap bounds memory, but it
# must be generous: at 64 the cache thrashes and the cost goes from 1.8x to 6.8x
# a turn. This is the central reason :lattice is not recommended for production;
# see docs/theory/pic_free_space_kernels.md Section 3.4.
const _PIC_LATTICE_GREEN_CACHE_MAX = 384
# Alignment is exact up to floating-point rounding of the origins; the measured
# residual on an aligned pair is ~4e-15 cells, against 0.400 for a misaligned one,
# so this threshold separates the two by nine orders of magnitude.
const _PIC_LATTICE_ALIGNMENT_TOL = 1.0e-6
const _PIC_LATTICE_GREEN_CACHE = Dict{Tuple{Int,Int,Int},Matrix{Float64}}()
const _PIC_LATTICE_GREEN_LOCK = ReentrantLock()

_pic_lattice_rho_key(rho) = round(Int, log(rho) / log1p(_PIC_LATTICE_GREEN_RHO_TOL))
_pic_lattice_rho_of_key(key) = exp(key * log1p(_PIC_LATTICE_GREEN_RHO_TOL))

"""Free-space lattice Green function, tabulated by integer separation.

Returned array is indexed `[sx + 2nx + 1, sy + 2ny + 1]` for
`sx in -2nx:2nx`, `sy in -2ny:2ny`, in the `G_PIC = -ln r` convention with gauge
`G(0,0) = 0`.
"""
function _pic_lattice_green_table(nx::Int, ny::Int, rho::Float64)
    multx, multy = _pic_lattice_box_mult(rho)
    Mx = multx * 2nx
    My = multy * 2ny
    ghat = Matrix{Float64}(undef, Mx, My)
    r2 = rho * rho
    @inbounds for j in 1:My
        ty = 2pi * (j - 1) / My
        cy = r2 * (2 - 2cos(ty))
        for i in 1:Mx
            tx = 2pi * (i - 1) / Mx
            kap = (2 - 2cos(tx)) + cy
            ghat[i, j] = kap == 0 ? 0.0 : 1 / kap
        end
    end
    g = real(ifft(ghat))
    g0 = g[1, 1]
    scale = 2pi * rho
    tab = Matrix{Float64}(undef, 4nx + 1, 4ny + 1)
    @inbounds for sy in -2ny:2ny
        jj = mod(sy, My) + 1
        for sx in -2nx:2nx
            tab[sx + 2nx + 1, sy + 2ny + 1] = scale * (g[mod(sx, Mx) + 1, jj] - g0)
        end
    end
    return tab
end

function _pic_lattice_green_cached(nx::Int, ny::Int, rho::Real)
    key = (nx, ny, _pic_lattice_rho_key(Float64(rho)))
    lock(_PIC_LATTICE_GREEN_LOCK) do
        cached = get(_PIC_LATTICE_GREEN_CACHE, key, nothing)
        cached === nothing || return cached
        length(_PIC_LATTICE_GREEN_CACHE) >= _PIC_LATTICE_GREEN_CACHE_MAX &&
            empty!(_PIC_LATTICE_GREEN_CACHE)
        tab = _pic_lattice_green_table(nx, ny, _pic_lattice_rho_of_key(key[3]))
        _PIC_LATTICE_GREEN_CACHE[key] = tab
        return tab
    end
end

function _pic_green_lattice!(green, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    T = eltype(green)
    tab = _pic_lattice_green_cached(nx, ny, hx / hy)
    # Integer cell offset between the two grids (exact by construction; see above).
    # Check it rather than trusting it: a fractional separation is not a rounding
    # error in the kernel value, it is the kernel of a source *displaced* by the
    # residual, and rounding it silently is what let the Green cache's grid
    # expansion go unnoticed. The measured residual was 0.400 cells.
    fx = (field_x0 - source_x0) / hx
    fy = (field_y0 - source_y0) / hy
    dx = round(Int, fx)
    dy = round(Int, fy)
    tol = _PIC_LATTICE_ALIGNMENT_TOL
    (abs(fx - dx) <= tol && abs(fy - dy) <= tol) || throw(ArgumentError(
        "green_type=:lattice requires the field and source grids to be an integer " *
        "number of cells apart; got ($(fx), $(fy)) cells. The table is indexed by " *
        "integer separation, so a fractional offset silently returns the field of a " *
        "source displaced by the residual."))
    @inbounds for j in 0:(2ny - 1)
        jj = j < ny ? j : j - 2ny
        sy = dy + jj
        (-2ny <= sy <= 2ny) || throw(ArgumentError(
            "green_type=:lattice: field/source grids are offset by $(dy) cells in y, " *
            "outside the tabulated range; this indicates unaligned interaction grids."))
        row = sy + 2ny + 1
        for i in 0:(2nx - 1)
            ii = i < nx ? i : i - 2nx
            sx = dx + ii
            (-2nx <= sx <= 2nx) || throw(ArgumentError(
                "green_type=:lattice: field/source grids are offset by $(dx) cells in x, " *
                "outside the tabulated range; this indicates unaligned interaction grids."))
            green[i + 1, j + 1] = T(tab[sx + 2nx + 1, row])
        end
    end
    return green
end

function _pic_green!(green, green_type, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    Symbol(green_type) == :lattice && return _pic_green_lattice!(
        green, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    # Threaded over COLUMNS of the padded table. Every cell is a pure function
    # of its own (i, j) and writes only `green[i+1, j+1]`, so any partition in
    # any order gives the same table bit for bit -- the same argument as
    # `_pic_map_particles`, and the reason this needs no fold.
    #
    # Worth doing because it is the largest block left in a slice pair after the
    # slice-hoist: ~35% of the pair, four `_pic_kernel_integral` evaluations
    # (each an `atan` and a `log`) per cell over a 2nx x 2ny table.
    #
    # The loop nest is also column-outer/row-inner where it used to be
    # row-outer, so a worker's cells are contiguous in this column-major array
    # instead of striding by 2nx. That reorders the WRITES, not the values.
    _pic_map_range(2ny, max(1, cld(_PIC_GREEN_MIN_CHUNK_CELLS, 2nx))) do jfirst, jlast
        _pic_green_columns!(green, green_type, field_x0, field_y0,
                            source_x0, source_y0, hx, hy, nx, ny,
                            jfirst - 1, jlast - 1)
    end
    return green
end

"""
Fill Green-table columns `jfirst:jlast` (0-based). Index-local: see `_pic_green!`.
"""
function _pic_green_columns!(green, green_type, field_x0, field_y0,
                             source_x0, source_y0, hx, hy, nx, ny, jfirst, jlast)
    T = eltype(green)
    half_hx = hx / 2
    half_hy = hy / 2
    hxihyi = T(-0.5) / (hx * hy)
    integrated = Symbol(green_type) == :integrated
    for j in jfirst:jlast, i in 0:(2nx - 1)
        ii = i < nx ? i : i - 2nx
        jj = j < ny ? j : j - 2ny
        x = field_x0 - source_x0 + ii * hx
        y = field_y0 - source_y0 + jj * hy
        if integrated
            val = _pic_kernel_integral(x + half_hx, y + half_hy)
            val += _pic_kernel_integral(x - half_hx, y - half_hy)
            val -= _pic_kernel_integral(x + half_hx, y - half_hy)
            val -= _pic_kernel_integral(x - half_hx, y + half_hy)
            green[i + 1, j + 1] = hxihyi * val
        else
            r2 = x * x + y * y
            if iszero(r2)
                val = _pic_kernel_integral(x + half_hx, y + half_hy)
                val += _pic_kernel_integral(x - half_hx, y - half_hy)
                val -= _pic_kernel_integral(x + half_hx, y - half_hy)
                val -= _pic_kernel_integral(x - half_hx, y + half_hy)
                green[i + 1, j + 1] = hxihyi * val
            else
                green[i + 1, j + 1] = T(-0.5) * log(r2)
            end
        end
    end
    return green
end

function _pic_field(phi, hx, hy, fourth::Bool=false)
    nx, ny = size(phi)
    T = eltype(phi)
    Ex = Matrix{T}(undef, nx, ny)
    Ey = Matrix{T}(undef, nx, ny)
    _pic_field!(Ex, Ey, phi, hx, hy, fourth)
    return Ex, Ey
end

# E = -grad(phi) on the mesh. `fourth=false` is the second-order central stencil
# and is the default, bit-compatible with every result recorded before the option
# existed. `fourth=true` uses the fourth-order central stencil
#     -dphi/dx = [ (phi[i+2]-phi[i-2]) + 8*(phi[i-1]-phi[i+1]) ] / (12h)
# in the interior, falling back to the second-order central form on the first
# ring inside the boundary (where the wider stencil does not fit) and to the
# existing one-sided formulas on the boundary itself. The adaptive box already
# pads ~1.5 cells beyond the particles, so the fallback rings sit outside the
# region that carries the physics.
_pic_field!(Ex, Ey, phi, hx, hy) = _pic_field!(Ex, Ey, phi, hx, hy, false)

function _pic_field!(Ex, Ey, phi, hx, hy, fourth::Bool)
    nx, ny = size(phi)
    T = eltype(phi)
    hxi = inv(hx); hyi = inv(hy)
    c4 = T(1) / T(12)
    # `phi`, `Ex` and `Ey` are column-major, so the FIRST index must be the inner
    # loop. The Ex pass below already runs that way; this one ran `i` outer and
    # walked each row with stride `nx`. Same arithmetic, same order of operations
    # per element, bit-identical output — measured 42.8 -> 4.8 us at grid 128 from
    # the loop order alone, and 3.0 us with @inbounds (14.3x total). `_validate_pic_grid`
    # guarantees nx, ny >= 5, which is what makes the boundary indices safe.
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
            Ey[i, j] = c4 * hyi * ((phi[i, j + 2] - phi[i, j - 2]) +
                                   8 * (phi[i, j - 1] - phi[i, j + 1]))
        end
    else
        @inbounds for j in 2:(ny - 1), i in 1:nx
            Ey[i, j] = T(0.5) * hyi * (phi[i, j - 1] - phi[i, j + 1])
        end
    end
    # `@inbounds` over the whole Ex pass, not only its fourth-order inner loop
    # (2026-08-05_b audit, U6-4). The comment above records the @inbounds win as
    # taken, and the Ey pass has it throughout, but the boundary rows and the
    # DEFAULT second-order inner loop were still bounds-checked -- so the
    # default path paid for a check the Ey twin had already argued away.
    # `_validate_pic_grid` guarantees nx, ny >= 5, which is that same safety
    # argument. Verified bit-identical on all four (grid, order) combinations.
    #
    # Measured here on the default second-order path, best of 30 x 20 calls:
    # grid 64 2.56 -> 2.36 us (1.08x), grid 128 8.23 -> 7.45 us (1.10x). The
    # lead reported 1.23x / 1.22x / 1.09x at grids 64 / 128 / 256 against
    # different absolute timings (16.20 us at grid 128 where this box measures
    # 8.23), so the gain is real but smaller than recorded; these are this
    # machine's numbers.
    @inbounds for j in 1:ny
        Ex[1, j] = hxi * (T(1.5) * phi[1, j] - 2 * phi[2, j] + T(0.5) * phi[3, j])
        Ex[nx, j] = hxi * (-T(1.5) * phi[nx, j] + 2 * phi[nx - 1, j] - T(0.5) * phi[nx - 2, j])
        if fourth && nx >= 5
            Ex[2, j] = T(0.5) * hxi * (phi[1, j] - phi[3, j])
            Ex[nx - 1, j] = T(0.5) * hxi * (phi[nx - 2, j] - phi[nx, j])
            for i in 3:(nx - 2)
                Ex[i, j] = c4 * hxi * ((phi[i + 2, j] - phi[i - 2, j]) +
                                       8 * (phi[i - 1, j] - phi[i + 1, j]))
            end
        else
            for i in 2:(nx - 1)
                Ex[i, j] = T(0.5) * hxi * (phi[i - 1, j] - phi[i + 1, j])
            end
        end
    end
    return nothing
end

"""Return true when the solver requests the fourth-order field stencil."""
_pic_fourth_order(solver::PICPoissonSolver) = solver.field_derivative === :fourth

function _pic_interpolate_kick(solver, grid, x, y, phiL, ExL, EyL, phiR, ExR, EyR, zL, zR)
    nx, ny = solver.grid
    hx = grid.width / (nx - 1)
    hy = grid.height / (ny - 1)
    if Symbol(solver.deposit_method) == :CIC
        ix, wx = _pic_cic_weights((x - grid.x0) / hx, nx)
        iy, wy = _pic_cic_weights((y - grid.y0) / hy, ny)
    else
        ix, wx = _pic_tsc_weights((x - grid.x0) / hx, nx)
        iy, wy = _pic_tsc_weights((y - grid.y0) / hy, ny)
    end
    Kx = zero(x); Ky = zero(x); Kz = zero(x)
    for m in eachindex(wx), n in eachindex(wy)
        ii = ix + m - 1
        jj = iy + n - 1
        @inbounds begin
            w = wx[m] * wy[n]
            Kx += w * (zL * ExL[ii, jj] + zR * ExR[ii, jj])
            Ky += w * (zL * EyL[ii, jj] + zR * EyR[ii, jj])
            Kz += w * (phiL[ii, jj] - phiR[ii, jj])
        end
    end
    return Kx, Ky, Kz
end

"""
    _pic_interpolate_kick_quadratic(solver, grid, x, y, phiL, ExL, EyL, phiM, ExM, EyM,
                                    phiR, ExR, EyR, t)

Three-node longitudinal reconstruction of the slice kick at normalized slice
coordinate `t = (z - lb) / (rb - lb)`, with nodes at the field-slice left
boundary (`t=0`), midpoint (`t=1/2`) and right boundary (`t=1`).

The transverse field uses the quadratic Lagrange basis on those nodes,

    L_L = 2t^2 - 3t + 1,  L_M = 4t - 4t^2,  L_R = 2t^2 - t,

which sums to 1 and collapses to `(1,0,0)` / `(0,0,1)` at the boundaries, so
adjacent slices still agree exactly at a shared boundary.

The longitudinal kick is the `z`-derivative of the same quadratic, returned
without the `1/(rb - lb)` factor that the caller applies as `hzi`:

    Kz = (3 - 4t) phiL + (8t - 4) phiM + (1 - 4t) phiR.

Those weights sum to zero, so the arbitrary additive constant in the mesh
potential cancels exactly, as it does in the two-node form. At `t = 1/2` they
reduce to `phiL - phiR`, i.e. the two-node kick is this expression frozen at
mid-slice.

See `docs/theory/slice_longitudinal_interpolation.md` Section 7.
"""
function _pic_interpolate_kick_quadratic(solver, grid, x, y,
                                         phiL, ExL, EyL, phiM, ExM, EyM, phiR, ExR, EyR, t)
    nx, ny = solver.grid
    hx = grid.width / (nx - 1)
    hy = grid.height / (ny - 1)
    if Symbol(solver.deposit_method) == :CIC
        ix, wx = _pic_cic_weights((x - grid.x0) / hx, nx)
        iy, wy = _pic_cic_weights((y - grid.y0) / hy, ny)
    else
        ix, wx = _pic_tsc_weights((x - grid.x0) / hx, nx)
        iy, wy = _pic_tsc_weights((y - grid.y0) / hy, ny)
    end
    T = typeof(t)
    t2 = t * t
    aL = T(2) * t2 - T(3) * t + one(T)
    aM = T(4) * t - T(4) * t2
    aR = T(2) * t2 - t
    bL = T(3) - T(4) * t
    bM = T(8) * t - T(4)
    bR = one(T) - T(4) * t
    Kx = zero(x); Ky = zero(x); Kz = zero(x)
    for m in eachindex(wx), n in eachindex(wy)
        ii = ix + m - 1
        jj = iy + n - 1
        @inbounds begin
            w = wx[m] * wy[n]
            Kx += w * (aL * ExL[ii, jj] + aM * ExM[ii, jj] + aR * ExR[ii, jj])
            Ky += w * (aL * EyL[ii, jj] + aM * EyM[ii, jj] + aR * EyR[ii, jj])
            Kz += w * (bL * phiL[ii, jj] + bM * phiM[ii, jj] + bR * phiR[ii, jj])
        end
    end
    return Kx, Ky, Kz
end

function _pic_luminosity(solver::PICPoissonSolver, x1, y1, x2, y2, klum)
    nx, ny = _pic_luminosity_grid(solver)
    T = promote_type(eltype(x1), eltype(x2), typeof(klum))
    q1 = zeros(T, nx + 1, ny + 1)
    q2 = zeros(T, nx + 1, ny + 1)
    return _pic_luminosity!(solver, x1, y1, x2, y2, klum, q1, q2)
end

function _pic_luminosity(solver::PICPoissonSolver, x1, y1, x2, y2, klum,
                         workspace::_PICCPUWorkspace)
    nx, ny = _pic_luminosity_grid(solver)
    if size(workspace.luminosity_q1) != (nx + 1, ny + 1)
        return _pic_luminosity(solver, x1, y1, x2, y2, klum)
    end
    return _pic_luminosity!(solver, x1, y1, x2, y2, klum,
                            workspace.luminosity_q1, workspace.luminosity_q2)
end

function _pic_luminosity!(solver::PICPoissonSolver, x1, y1, x2, y2, klum, q1, q2)
    nx, ny = _pic_luminosity_grid(solver)
    T = promote_type(eltype(x1), eltype(x2), typeof(klum))
    xmin = min(minimum(x1), minimum(x2))
    xmax = max(maximum(x1), maximum(x2))
    ymin = min(minimum(y1), minimum(y2))
    ymax = max(maximum(y1), maximum(y2))
    width, height = _pic_resolve_transverse_extent(
        solver, T(xmax - xmin), T(ymax - ymin), "PIC luminosity grid")
    tx = width / T(nx - 1.1)
    ty = height / T(ny - 1.1)
    width += T(0.1) * tx
    height += T(0.1) * ty
    xmin -= T(0.05) * tx
    ymin -= T(0.05) * ty
    hx = width / (nx - 1)
    hy = height / (ny - 1)
    hxi = inv(hx); hyi = inv(hy)
    fill!(q1, zero(T))
    fill!(q2, zero(T))
    method = _pic_luminosity_deposit_method(solver)
    _pic_deposit!(q1, method, x1, y1, xmin, ymin, hx, hy, nx + 1, ny + 1)
    _pic_deposit!(q2, method, x2, y2, xmin, ymin, hx, hy, nx + 1, ny + 1)
    # The overlap sum covers the FULL (nx+1) x (ny+1) deposit extent. It used
    # to stop at nx x ny, and with a TSC luminosity deposit the topmost
    # particles' third stencil cell lands exactly in the excluded row/column
    # (u_max = nx - 1.05, stencil reach floor(u)+2 = nx+1): measured 0.26% of
    # the charge deposited there, an 8.0e-5 relative luminosity deficit. CIC
    # never reaches past node nx (stencil reach floor(nx-1.05)+1 = nx), so CIC
    # results are bit-identical (2026-08-05 audit, U5-8). The CUDA overlap sums
    # cover the same full extent — keep them in step.
    lum = zero(T)
    for j in 1:(ny + 1), i in 1:(nx + 1)
        @inbounds lum += q1[i, j] * q2[i, j]
    end
    return lum * T(klum) * hxi * hyi
end
