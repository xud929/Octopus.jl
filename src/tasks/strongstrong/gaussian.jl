"""
    collide!(solver, beam1, beam2, backend)

Advance two beams through one strong-strong collision and return the luminosity
estimate for that collision.
"""
function collide!(solver::GaussianPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    # Both beams' shards in scope for the whole collide (step 4b): a task has
    # already scoped them and this adds nothing; a bare collide resolves each
    # once here, at the entry, instead of a per-slice function paying a hidden
    # collective on a miss.
    return _with_beam_shards(beam1.rep, beam2.rep) do
        _cpu_gaussian_collide!(solver, beam1, beam2)
    end
end

function _cpu_gaussian_collide!(solver::GaussianPoissonSolver, beam1::Beam, beam2::Beam)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _strong_strong_kbb1(solver, beam1, beam2)
    kbb2 = _strong_strong_kbb2(solver, beam1, beam2)
    klum1, klum2 = _strong_strong_luminosity_scales(solver, beam1, beam2)
    T = eltype(beam1.rep.x)
    order = _slice_collision_order(slices1, slices2)
    npairs = length(order)
    # Luminosity by POSITION IN THE COLLISION ORDER, folded at the end in that
    # order, so the batched schedule reproduces the sequential fold exactly
    # rather than reassociating it into a different last bit. `pic_cpu.jl`
    # records the same decision for the same reason, and `spectral.jl` folds
    # per batch and had to widen a pin for it.
    LT = promote_type(T, eltype(beam2.rep.x),
                      eltype(slices1.weight), eltype(slices2.weight),
                      typeof(kbb1), typeof(kbb2), typeof(solver.min_sigma))
    lum_parts = zeros(LT, npairs)
    if solver.batch_mode === :wavefront && npairs > 1
        batches = collision_pair_batches(slices1, slices2)
        pair_pos = Dict{Tuple{Int,Int},Int}()
        sizehint!(pair_pos, npairs)
        for (p, entry) in pairs(order)
            pair_pos[(entry[2], entry[3])] = p
        end
        # `batch_mode` is what RAN -- a literal written in the branch that
        # executed, never a copy of the field, because a receipt that echoes
        # the request certifies nothing (U4-6) -- and `requested` is the field,
        # so a downgrade shows beside it. The one shape every solver's pair
        # schedule carries (2026-09-04).
        _record_execution!(:gaussian_pair_schedule, CPUThreadsBackend,
                           (batch_mode=:wavefront, requested=solver.batch_mode,
                            pairs=npairs, batches=length(batches),
                            widest_batch=maximum(length, batches; init=0)))
        _cpu_gaussian_wavefront!(lum_parts, pair_pos, solver, beam1, beam2,
                                 slices1, slices2, batches,
                                 kbb1, kbb2, klum1, klum2)
    else
        _record_execution!(:gaussian_pair_schedule, CPUThreadsBackend,
                           (batch_mode=:sequential, requested=solver.batch_mode,
                            pairs=npairs, batches=0, widest_batch=0))
        for (p, entry) in pairs(order)
            @inbounds lum_parts[p] = _cpu_gaussian_slice_pair!(
                solver, beam1.rep, beam2.rep, slices1, slices2,
                entry[2], entry[3], kbb1, kbb2, klum1, klum2)
        end
    end
    luminosity = zero(T)
    for p in 1:npairs
        @inbounds luminosity += lum_parts[p]
    end
    # Once per collide, not once per pair: each rank's per-pair contributions
    # accumulate locally in collision order and the ranks exchange one number
    # at the end. Per-pair exchange would cost a message per slice pair and
    # buy nothing -- no consumer reads a single pair's luminosity here.
    return _mp_global_sum(luminosity)
end

function _cpu_gaussian_slice_pair!(solver::GaussianPoissonSolver{T,D,COUPLED,LONGITUDINAL},
                                   rep1, rep2, slices1, slices2, i, j,
                                   kbb1, kbb2, klum1, klum2) where {T,D,COUPLED,LONGITUDINAL}
    moments1 = _slice_transverse_moments(
        rep1, slices1.indices[i], solver.ignore_centroid1, solver.min_sigma,
        Val(COUPLED))
    moments2 = _slice_transverse_moments(
        rep2, slices2.indices[j], solver.ignore_centroid2, solver.min_sigma,
        Val(COUPLED))
    # Non-finite chokepoint (N1, docs/history/todo_ledger_archive.md): the moment reduction already
    # scanned every transverse coordinate; a NaN/Inf lands in these O(1) values.
    _gaussian_moments_finite(moments1) ||
        _nonfinite_coordinate_error(:source,
            (x=rep1.x, px=rep1.px, y=rep1.y, py=rep1.py);
            context="beam 1, slice $(i)")
    _gaussian_moments_finite(moments2) ||
        _nonfinite_coordinate_error(:source,
            (x=rep2.x, px=rep2.px, y=rep2.y, py=rep2.py);
            context="beam 2, slice $(j)")
    sample_beam1 = solver.gaussian_when_luminosity == 1
    lum2 = _slice_slice_gaussian_kick!(
        rep1, slices1.indices[i], moments2, slices2.center[j],
        slices2.weight[j] * kbb1, slices2.weight[j] * klum1,
        solver.min_sigma, solver.virtual_drift, Val(LONGITUDINAL),
        !sample_beam1,
    )
    lum1 = _slice_slice_gaussian_kick!(
        rep2, slices2.indices[j], moments1, slices1.center[i],
        slices1.weight[i] * kbb2, slices1.weight[i] * klum2,
        solver.min_sigma, solver.virtual_drift, Val(LONGITUDINAL),
        sample_beam1,
    )
    return sample_beam1 ? lum1 : lum2
end

function _slice_slice_gaussian_kick!(rep::Phase6DRep, idx::Vector{Int}, moments2,
                                     center2, kbb_slice, klum_slice, min_sigma,
                                     virtual_drift::AbstractVirtualDrift,
                                     longitudinal_kick::Val,
                                     compute_luminosity::Bool)
    # Luminosity accumulates at the working precision the solver's scalars
    # promote to (U3-4's convention; found by U6-7's measurement): the chunked
    # branch stored Float64 per-chunk sums into an eltype(rep.x) array, so a
    # Float32 beam under the default Float64 solver lost ~1e-8 relative in the
    # fold while the serial branch (and the CUDA twin) accumulated in Float64.
    AT = promote_type(eltype(rep.x), typeof(kbb_slice), typeof(min_sigma))
    isempty(idx) && return zero(AT)
    n = length(idx)
    # Fixed chunk grid above the threshold, path choice by data size only —
    # same count-invariance rule as the deposit and moment reductions
    # (U5-1/2).
    nchunks = _REDUCTION_CHUNKS
    if n < _STRONG_STRONG_PARALLEL_KICK_MIN
        lum = zero(AT)
        for i in idx
            @inbounds lum += _apply_slice_kick_one!(
                rep, i, moments2, center2, kbb_slice, min_sigma,
                virtual_drift, longitudinal_kick, compute_luminosity)
        end
        return lum / TWOPI * klum_slice
    end
    local_lum = zeros(AT, nchunks)
    # `chunk_lum`, NOT `lum`. The do-block is a CLOSURE and `lum` is also
    # assigned in the serial branch above, which is function scope -- `if` does
    # not open a scope in Julia, only `for`/`let`/`function` do. Reusing the
    # name therefore does not give each worker its own accumulator: every
    # spawned worker resets and accumulates the SAME captured box, so
    # `local_lum[chunk]` receives whatever happened to be in it. The kicks
    # themselves were unaffected -- `_apply_slice_kick_one!` writes per particle
    # -- but the luminosity this returns was silently wrong and irreproducible
    # on more than one thread. Same defect, same cause, as `_threaded_histogram`
    # in `slicing.jl`; both were found by looking for `Core.Box` in the lowered
    # code of every `_run_logical_workers` caller.
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(n, nchunks, chunk)
        chunk_lum = zero(AT)
        for pos in first_i:last_i
            @inbounds chunk_lum += _apply_slice_kick_one!(
                rep, idx[pos], moments2, center2, kbb_slice, min_sigma,
                virtual_drift, longitudinal_kick, compute_luminosity)
        end
        local_lum[chunk] = chunk_lum
    end
    return sum(local_lum) / TWOPI * klum_slice
end

"""
Return whether a slice-moment NamedTuple carries only finite values.

This is a "no **unexpected** NaN" test, not a "no NaN" test, and the difference
is what makes it survive `allow_lost_particles`. A dead particle never reaches
these moments: slicing drops it, so it is absent from `slices.indices` and
contributes to no sum. Anything non-finite that arrives here therefore came from
*live* input -- a genuine overflow or invalid operation in the reduction -- which
is exactly the failure this guard was written to catch, and it still throws.

The restatement is in what the guard is allowed to conclude, not in its test:
before, a non-finite moment meant "some particle is non-finite"; now it means
"some **live** particle is non-finite". The mask upstream is what makes the
second statement true, which is why that mask and this guard have to land
together rather than in either order.
"""
@inline function _gaussian_moments_finite(m)
    return isfinite(m.mx) && isfinite(m.mpx) && isfinite(m.my) && isfinite(m.mpy) &&
           isfinite(m.sx) && isfinite(m.sy) && isfinite(m.spx) && isfinite(m.spy) &&
           isfinite(m.covxpx) && isfinite(m.covypy)
end

@inline _soft_gaussian_covariance(moments) = moments.moments

@inline _soft_gaussian_covariance(moments::NamedTuple{N}) where {N} =
    _soft_gaussian_covariance(moments, Val(:moments in N))

@inline _soft_gaussian_covariance(moments::NamedTuple, ::Val{true}) = moments.moments

@inline function _soft_gaussian_covariance(moments::NamedTuple, ::Val{false})
    T = typeof(moments.sx)
    return StrongTransverseMoments{T,false}(
        moments.sx * moments.sx, zero(T), moments.sy * moments.sy,
        moments.covxpx, zero(T), zero(T), moments.covypy,
        moments.spx * moments.spx, zero(T), moments.spy * moments.spy,
    )
end

@inline _soft_gaussian_drift(drift, ::Val{true}) = drift
@inline _soft_gaussian_drift(::AbstractVirtualDrift, ::Val{false}) =
    UnsafeVirtualDrift(_ParaxialFrozenLongitudinalDrift())

@inline function _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2,
                                        kbb_slice, min_sigma,
                                        virtual_drift::AbstractVirtualDrift,
                                        longitudinal_kick::Val{LONGITUDINAL},
                                        compute_luminosity::Bool) where {LONGITUDINAL}
    @inbounds begin
        x = rep.x[i]; px = rep.px[i]
        y = rep.y[i]; py = rep.py[i]
        z = rep.z[i]; pz = rep.pz[i]
    end
    drift = _soft_gaussian_drift(virtual_drift, longitudinal_kick)
    x, px, y, py, z, pz, S = _forward_virtual_drift(
        drift, x, px, y, py, z, pz, center2)
    xx = x - moments2.mx + moments2.mpx * S
    yy = y - moments2.my + moments2.mpy * S
    px0, py0, pz0 = px, py, pz
    x, px, y, py, z, pz, density = _cp_covariance_kick(
        _soft_gaussian_covariance(moments2), kbb_slice, S, xx, yy,
        x, px, y, py, z, pz)
    if LONGITUDINAL
        pz += 0.5 * ((px - px0) * moments2.mpx +
                    (py - py0) * moments2.mpy)
    else
        pz = pz0
    end
    x, px, y, py, z, pz = _reverse_virtual_drift(
        drift, x, px, y, py, z, pz, center2)
    @inbounds begin
        rep.x[i] = x; rep.px[i] = px
        rep.y[i] = y; rep.py[i] = py
        rep.z[i] = z; rep.pz[i] = pz
    end
    return compute_luminosity ? density * TWOPI : zero(density)
end

# `compute_luminosity` is a runtime Bool, not a Val, on the main method
# above (2026-08-07 neighbour audit, N6): the Val compiled a second
# specialization of the ENTIRE kick body to gate only the returned density,
# and both specializations are reachable for the same beam by flipping
# `gaussian_when_luminosity` -- the U10-3 second-specialization contraction
# mechanism, which moved shared results by 1 ulp there. One instruction
# sequence now, matching the CUDA fused route's runtime seg_complum gate;
# this Val method survives only as a compatibility entry for callers that
# still pass Val.
@inline _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2,
                               kbb_slice, min_sigma,
                               virtual_drift::AbstractVirtualDrift,
                               longitudinal_kick::Val,
                               compute_luminosity::Val{C}) where {C} =
    _apply_slice_kick_one!(rep, i, moments2, center2, kbb_slice, min_sigma,
                           virtual_drift, longitudinal_kick, C)

# Compatibility entry point for code that exercised the former internal helper.
@inline _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2,
                               kbb_slice, min_sigma,
                               longitudinal_kick::Bool=true,
                               compute_luminosity::Bool=true) =
    _apply_slice_kick_one!(rep, i, moments2, center2, kbb_slice, min_sigma,
                           HirataParaxialDrift(), Val(longitudinal_kick),
                           Val(compute_luminosity))

# ---------------------------------------------------------------------------
# The wavefront schedule: `batch_mode = :wavefront` on CPUThreadsBackend.
#
# Two levers, and they attack different terms of the measured multi-process
# budget (docs/history/multi_process_strongstrong_scaling_2026_09_04.md).
#
# CALL COUNT. Sequentially, every slice pair asks for its two slices' moments
# on its own, and each ask is three collectives -- the global count, the shared
# shift origin, and the ten or fourteen shifted sums. At 15 x 15 slices that is
# about 1350 messages, of which 1840 of the collide's 1874 averaged 33 bytes:
# the cost is latency, not payload. A batch's pairs repeat no beam-1 and no
# beam-2 slice, so its moments can be gathered ONCE for the whole batch and
# exchanged in one message per beam. The counts and the identity of each
# slice's shift-origin owner do not change during a collide at all -- slice
# membership is fixed once the beams are sliced -- so those are hoisted out of
# the pair loop entirely.
#
# WIDTH. Within a pair the two beams are independent: the two moment reductions
# read different beams and neither reads the other's result, and the two kicks
# write disjoint arrays from moments both computed BEFORE either kick. They ran
# one after the other, each over its own 64-chunk grid. A shard's slice is
# small -- at 15 slices and 64 ranks a rank holds roughly a 960th of the beam
# per slice -- so those grids are thin. The batch issues every kick it holds,
# both beams together, as ONE grid.
#
# What none of this may do is move a number. The luminosity fold is by position
# in the collision order (see `collide!`); each kick keeps its OWN accumulator
# and its own chunk-ordered fold, so widening the grid re-associates nothing;
# and the merged exchange is the same elementwise rank-ordered sum on a longer
# buffer. The result is bit-identical to `batch_mode = :sequential`, which is
# what the schedule pin asserts.
# ---------------------------------------------------------------------------

"""
The per-slice facts a collide can hoist out of its pair loop.

`counts` is each slice's GLOBAL membership and `owns_reference` says whether
this rank holds the slice's globally-first member — the particle whose
coordinates every rank shifts its moments by. Both are functions of slice
MEMBERSHIP, which the collide fixes when it slices the beams and no kick
changes, so the two collectives behind them are paid once per collide instead
of once per slice per pair. The coordinates themselves are not here: those the
kicks do move, so they are re-read every batch.
"""
function _cpu_gaussian_slice_plan(rep::Phase6DRep, slices, divided::Bool)
    ns = length(slices.indices)
    counts = Vector{Int}(undef, ns)
    @inbounds for s in 1:ns
        counts[s] = length(slices.indices[s])
    end
    divided || return (counts=counts, owns_reference=trues(ns))
    _mp_allsum!(counts)
    offset, _ = _mp_current_shard(rep)
    owns = falses(ns)
    @inbounds for s in 1:ns
        idx = slices.indices[s]
        mine = isempty(idx) ? typemax(Int) : offset + idx[1]
        first_global, _ = _mp_allminmax(mine, mine)
        owns[s] = !isempty(idx) && mine == first_global
    end
    return (counts=counts, owns_reference=owns)
end

"""
Every slice in `sliceids` gets its shift origin, in one exchange for the lot.

The single-slice `_mp_slice_reference` in the same shape: the owning rank
writes its member's four coordinates and every other rank writes zeros, so the
sum is the owner's values exactly. WHICH rank owns each slice came from
`_cpu_gaussian_slice_plan` once for the collide; only the coordinates are
re-read, because the kicks move them.
"""
function _cpu_gaussian_batch_reference(rep::Phase6DRep, slices, plan,
                                       sliceids, ::Type{T},
                                       divided::Bool) where {T}
    refs = zeros(T, 4 * length(sliceids))
    @inbounds for k in eachindex(sliceids)
        s = sliceids[k]
        plan.owns_reference[s] || continue
        idx = slices.indices[s]
        isempty(idx) && continue
        i = idx[1]
        refs[4k-3] = T(rep.x[i]); refs[4k-2] = T(rep.px[i])
        refs[4k-1] = T(rep.y[i]); refs[4k]   = T(rep.py[i])
    end
    divided && _mp_allsum!(refs)
    return refs
end

"""
Transverse moments for every slice in `sliceids`, in one exchange for the lot.

One buffer per beam rather than one for both: the two beams' working precision
is `promote_type(eltype(rep.x), typeof(min_sigma))` computed on their own
coordinate arrays, and merging buffers of different element types would move
the cross-rank sum to the wider one. Two messages per batch per beam (origins,
then sums) replace six per slice pair.
"""
function _cpu_gaussian_batch_moments(rep::Phase6DRep, slices, plan, sliceids,
                                     ignore_centroid::Bool, min_sigma,
                                     divided::Bool, ::Val{COUPLED}) where {COUPLED}
    T = promote_type(eltype(rep.x), typeof(min_sigma))
    nstats = _slice_moment_nstats(Val(COUPLED))
    refs = _cpu_gaussian_batch_reference(rep, slices, plan, sliceids, T, divided)
    sums = zeros(T, nstats * length(sliceids))
    @inbounds for k in eachindex(sliceids)
        s = sliceids[k]
        plan.counts[s] == 0 && continue
        _slice_moment_local_sums!(sums, (k - 1) * nstats, rep, slices.indices[s],
                                  refs[4k-3], refs[4k-2], refs[4k-1], refs[4k],
                                  Val(COUPLED))
    end
    divided && _mp_allsum!(sums)
    return [plan.counts[sliceids[k]] == 0 ?
            _slice_empty_moments(min_sigma, T, Val(COUPLED)) :
            _slice_moments_finalize(sums, (k - 1) * nstats,
                                    plan.counts[sliceids[k]],
                                    refs[4k-3], refs[4k-2], refs[4k-1], refs[4k],
                                    ignore_centroid, min_sigma, Val(COUPLED))
            for k in eachindex(sliceids)]
end

"""
How many logical workers one slice's kick asks for.

The same rule the sequential kick applies to itself — a fixed 64-chunk grid
above the threshold, one worker below it, decided by data size only so the fold
never depends on the pool — expressed as a count so a batch can lay several
kicks' workers end to end in one grid. An empty slice asks for none and is
skipped: its luminosity is zero and its `lum_parts` slot already holds it.
"""
@inline _cpu_gaussian_kick_workers(n::Int) =
    n == 0 ? 0 : (n < _STRONG_STRONG_PARALLEL_KICK_MIN ? 1 : _REDUCTION_CHUNKS)

"""
One kick's share of the grid: either its whole slice, or one chunk of it.

`nchunks == 1` is the sequential kick verbatim — iterate `idx` in order into
one accumulator — and above it the same `_chunk_bounds` partition the
sequential path uses. Either way the partial lands in this kick's OWN `store`,
so `sum(store)` afterwards is the identical fold whichever grid ran it.
"""
@inline function _cpu_gaussian_kick_chunk!(store, rep::Phase6DRep, task,
                                           chunk::Int, nchunks::Int, min_sigma,
                                           virtual_drift::AbstractVirtualDrift,
                                           longitudinal::Val)
    idx = task.idx
    chunk_lum = zero(eltype(store))
    if nchunks == 1
        for i in idx
            @inbounds chunk_lum += _apply_slice_kick_one!(
                rep, i, task.moments, task.center, task.kbb, min_sigma,
                virtual_drift, longitudinal, task.compute_lum)
        end
    else
        first_i, last_i = _chunk_bounds(length(idx), nchunks, chunk)
        for pos in first_i:last_i
            @inbounds chunk_lum += _apply_slice_kick_one!(
                rep, idx[pos], task.moments, task.center, task.kbb, min_sigma,
                virtual_drift, longitudinal, task.compute_lum)
        end
    end
    @inbounds store[chunk] = chunk_lum
    return nothing
end

"""
Run a batch's kicks — both beams, every pair — over one grid.

The two beams reach here as separate task vectors because they are separate
arrays with separate element types, and the worker index picks between them at
a boundary rather than through a union. Every task writes its own slice of its
own beam and reads only moments taken before any kick in this batch, which is
what makes the whole grid conflict-free; `collision_pair_batches` is what makes
that true of the pairs.
"""
function _cpu_gaussian_run_kicks!(lum_parts, rep_a::Phase6DRep, tasks_a,
                                  rep_b::Phase6DRep, tasks_b, min_sigma,
                                  virtual_drift::AbstractVirtualDrift,
                                  longitudinal::Val)
    ATa = promote_type(eltype(rep_a.x), typeof(first(tasks_a).kbb), typeof(min_sigma))
    ATb = promote_type(eltype(rep_b.x), typeof(first(tasks_b).kbb), typeof(min_sigma))
    grid_a = [_cpu_gaussian_kick_workers(length(t.idx)) for t in tasks_a]
    grid_b = [_cpu_gaussian_kick_workers(length(t.idx)) for t in tasks_b]
    store_a = [zeros(ATa, g) for g in grid_a]
    store_b = [zeros(ATb, g) for g in grid_b]
    total = sum(grid_a) + sum(grid_b)
    if total > 0
        map_task = Vector{Int}(undef, total)
        map_chunk = Vector{Int}(undef, total)
        w = 0
        for t in eachindex(grid_a), c in 1:grid_a[t]
            w += 1; map_task[w] = t; map_chunk[w] = c
        end
        nwa = w
        for t in eachindex(grid_b), c in 1:grid_b[t]
            w += 1; map_task[w] = t; map_chunk[w] = c
        end
        _run_logical_workers(total) do worker, _
            @inbounds t = map_task[worker]
            @inbounds c = map_chunk[worker]
            if worker <= nwa
                _cpu_gaussian_kick_chunk!(store_a[t], rep_a, tasks_a[t], c,
                                          grid_a[t], min_sigma, virtual_drift,
                                          longitudinal)
            else
                _cpu_gaussian_kick_chunk!(store_b[t], rep_b, tasks_b[t], c,
                                          grid_b[t], min_sigma, virtual_drift,
                                          longitudinal)
            end
        end
    end
    for t in eachindex(tasks_a)
        task = tasks_a[t]
        (grid_a[t] == 0 || task.slot == 0) && continue
        @inbounds lum_parts[task.slot] = sum(store_a[t]) / TWOPI * task.klum
    end
    for t in eachindex(tasks_b)
        task = tasks_b[t]
        (grid_b[t] == 0 || task.slot == 0) && continue
        @inbounds lum_parts[task.slot] = sum(store_b[t]) / TWOPI * task.klum
    end
    return nothing
end

function _cpu_gaussian_wavefront!(lum_parts, pair_pos,
                                  solver::GaussianPoissonSolver{ST,D,COUPLED,LONGITUDINAL},
                                  beam1::Beam, beam2::Beam, slices1, slices2,
                                  batches, kbb1, kbb2,
                                  klum1, klum2) where {ST,D,COUPLED,LONGITUDINAL}
    rep1 = beam1.rep
    rep2 = beam2.rep
    divided = _mp_nranks() > 1
    plan1 = _cpu_gaussian_slice_plan(rep1, slices1, divided)
    plan2 = _cpu_gaussian_slice_plan(rep2, slices2, divided)
    sample_beam1 = solver.gaussian_when_luminosity == 1
    min_sigma = solver.min_sigma
    for batch in batches
        ids1 = [pr.i for pr in batch]
        ids2 = [pr.j for pr in batch]
        moments1 = _cpu_gaussian_batch_moments(
            rep1, slices1, plan1, ids1, solver.ignore_centroid1, min_sigma,
            divided, Val(COUPLED))
        moments2 = _cpu_gaussian_batch_moments(
            rep2, slices2, plan2, ids2, solver.ignore_centroid2, min_sigma,
            divided, Val(COUPLED))
        # Non-finite chokepoint (N1, docs/history/todo_ledger_archive.md): the
        # moment reduction already scanned every transverse coordinate.
        for k in eachindex(batch)
            _gaussian_moments_finite(moments1[k]) ||
                _nonfinite_coordinate_error(:source,
                    (x=rep1.x, px=rep1.px, y=rep1.y, py=rep1.py);
                    context="beam 1, slice $(ids1[k])")
            _gaussian_moments_finite(moments2[k]) ||
                _nonfinite_coordinate_error(:source,
                    (x=rep2.x, px=rep2.px, y=rep2.y, py=rep2.py);
                    context="beam 2, slice $(ids2[k])")
        end
        # Beam 1 is kicked by beam 2's slice and vice versa, and only the beam
        # the solver samples reports luminosity -- `slot = 0` on the other side
        # says "kick, but write no luminosity", which is the runtime Bool the
        # kick already took.
        tasks1 = [(idx=slices1.indices[ids1[k]], moments=moments2[k],
                   center=slices2.center[ids2[k]],
                   kbb=slices2.weight[ids2[k]] * kbb1,
                   klum=slices2.weight[ids2[k]] * klum1,
                   compute_lum=!sample_beam1,
                   slot=sample_beam1 ? 0 : pair_pos[(ids1[k], ids2[k])])
                  for k in eachindex(batch)]
        tasks2 = [(idx=slices2.indices[ids2[k]], moments=moments1[k],
                   center=slices1.center[ids1[k]],
                   kbb=slices1.weight[ids1[k]] * kbb2,
                   klum=slices1.weight[ids1[k]] * klum2,
                   compute_lum=sample_beam1,
                   slot=sample_beam1 ? pair_pos[(ids1[k], ids2[k])] : 0)
                  for k in eachindex(batch)]
        _cpu_gaussian_run_kicks!(lum_parts, rep1, tasks1, rep2, tasks2,
                                 min_sigma, solver.virtual_drift,
                                 Val(LONGITUDINAL))
    end
    return nothing
end
