# The slice-aligned spectral collide (multi-process step 4g). Design and the
# review it went through: docs/design/multi_process_policy.md, "Step 4g".
#
# The 6D spectral map is ORDER-DEPENDENT: a slice is kicked by the pairs before
# it and then serves as a source at its kicked positions, exactly as the PIC
# collide does. So it takes the same layout: for one collide the live particles
# of each beam are laid out by slice on a contiguous GROUP of ranks
# (`pic_cpu_sliced.jl` owns the layout, the migration and the buffers, which are
# solver-agnostic), every slice pair is a conversation between two small groups,
# and the particles migrate back at the exit.
#
# What spectral changes against the PIC protocol is who solves and how little is
# negotiated. The Dirichlet box is ONE box for the whole collide -- `_spectral_
# box_drifted`, already global (step 4g's first half) -- so there is no per-pair
# geometry to reduce, no extents record, no owner deal, and no Green table to
# publish: stages 0 and 1 of the PIC loop simply do not exist here. And because
# no geometry has to be agreed first, the natural solver of a directed
# interaction is the FIELD slice's group head rather than a dealt third party:
# the source group sends TWO drifted deposits (the L and R planes), the field
# head folds and solves them, and the potentials it produces never leave the
# group that needs them. Under `P <= nslices` that is two messages per direction
# per pair and no broadcast at all.
#
# Why the solve is dealt out at all: at the production grid one DST solve costs
# roughly four times the evaluation of the mesh it produces against a slice
# (measured 271 us against 64 us at 64x64 with 6000 particles), so a scheme that
# folded the deposit and let every rank solve it would leave the dominant term
# undivided. Pairs in one wavefront batch share no slice, so the field heads of
# a batch are distinct ranks and the batch's solves run at once.
#
# At one rank every message is to oneself (the seam's self-delivery), one group
# holds every slice in home order, and the deposit, the drift, the solve and the
# luminosity are the undivided collide's operations on the same numbers in the
# same order: that run is the CPU collide bit for bit, which is the pin the
# launcher child holds this code to.

const _SPECTRAL_TAG_CODES = 16
const _SPEC_TAG_PARTIAL = 0     # 0..3 : (direction, plane) source deposits
const _SPEC_TAG_PAYLOAD = 4     # 4..7 : (direction, plane) solved payloads
const _SPEC_TAG_LUMEXT1 = 8
const _SPEC_TAG_LUMEXT2 = 9
const _SPEC_TAG_LUMMESH = 10
const _SPEC_TAG_LUMDEP1 = 11
const _SPEC_TAG_LUMDEP2 = 12

"""Tag base for one pair, so no two pairs of a batch can collide."""
_spectral_sliced_tag(pair::Int, code::Int) = (pair - 1) * _SPECTRAL_TAG_CODES + code

# --- scratch -------------------------------------------------------------------

"""
Buffers the sliced spectral collide reuses across batches and across collides:
deposit planes, payloads, luminosity meshes, small records and the virtual
positions. Taken in order by a cursor and reset per batch, because every message
of a batch is waited before the next one starts. Kept in the run's cache for the
reason the PIC pools are: a fresh set is a whole collide's worth of garbage.
"""
mutable struct _SpectralSlicedScratch{T}
    planes::Vector{Matrix{T}}
    plane_cursor::Int
    payloads::Vector{Array{T,3}}
    payload_cursor::Int
    lum::Vector{Matrix{T}}
    lum_cursor::Int
    records::Vector{Vector{T}}
    record_cursor::Int
    virts::Vector{Vector{T}}
    virt_cursor::Int
end
_SpectralSlicedScratch{T}() where {T} =
    _SpectralSlicedScratch{T}(Matrix{T}[], 0, Array{T,3}[], 0, Matrix{T}[], 0,
                              Vector{T}[], 0, Vector{T}[], 0)

function _spectral_sliced_reset!(sc::_SpectralSlicedScratch)
    sc.plane_cursor = 0; sc.payload_cursor = 0; sc.lum_cursor = 0
    sc.record_cursor = 0; sc.virt_cursor = 0
    return nothing
end

function _spectral_plane!(sc::_SpectralSlicedScratch{T}, nx::Int, ny::Int) where {T}
    sc.plane_cursor += 1
    sc.plane_cursor > length(sc.planes) && push!(sc.planes, zeros(T, nx, ny))
    A = sc.planes[sc.plane_cursor]
    size(A) == (nx, ny) || (A = zeros(T, nx, ny); sc.planes[sc.plane_cursor] = A)
    return A
end

function _spectral_payload!(sc::_SpectralSlicedScratch{T}, nx::Int, ny::Int, np::Int) where {T}
    sc.payload_cursor += 1
    sc.payload_cursor > length(sc.payloads) && push!(sc.payloads, zeros(T, nx, ny, np))
    A = sc.payloads[sc.payload_cursor]
    size(A) == (nx, ny, np) || (A = zeros(T, nx, ny, np); sc.payloads[sc.payload_cursor] = A)
    return A
end

function _spectral_lumgrid!(sc::_SpectralSlicedScratch{T}, nx::Int, ny::Int) where {T}
    sc.lum_cursor += 1
    sc.lum_cursor > length(sc.lum) && push!(sc.lum, zeros(T, nx, ny))
    A = sc.lum[sc.lum_cursor]
    size(A) == (nx, ny) || (A = zeros(T, nx, ny); sc.lum[sc.lum_cursor] = A)
    return A
end

function _spectral_record!(sc::_SpectralSlicedScratch{T}, n::Int) where {T}
    sc.record_cursor += 1
    sc.record_cursor > length(sc.records) && push!(sc.records, zeros(T, n))
    v = sc.records[sc.record_cursor]
    length(v) == n || (v = zeros(T, n); sc.records[sc.record_cursor] = v)
    fill!(v, zero(T))
    return v
end

function _spectral_virt!(sc::_SpectralSlicedScratch{T}) where {T}
    sc.virt_cursor += 1
    sc.virt_cursor > length(sc.virts) && push!(sc.virts, T[])
    return sc.virts[sc.virt_cursor]
end

"""The scratch for this collide label, kept across turns."""
function _spectral_sliced_scratch(::Type{T}, holder::Base.RefValue{Any}) where {T}
    held = holder[]
    held isa _SpectralSlicedScratch{T} && return held
    fresh = _SpectralSlicedScratch{T}()
    holder[] = fresh
    return fresh
end

# --- the leaves that touch particles -------------------------------------------

"""How many planes the payload a field member evaluates carries.

`:grid` sends the solved mesh -- `Phig`, `Exg`, `Eyg` -- because the DST solve is
the expensive step and belongs on ONE rank. `:grid_free` sends the folded mode
sums instead: there is no mesh, its evaluation is a sum per FIELD particle, and
that is already each member's own work, so the head only has to fold.
"""
_spectral_payload_planes(solver::SpectralPoissonSolver) =
    solver.method === :grid_free ? 1 : 3

"""One source part drifted to a plane, into caller-owned buffers.

The arithmetic of `_spectral_drifted_source` without its workspace slots, so
`:grid` and `:grid_free` take the same path and the buffers can live in the
collide's pool rather than in a per-worker workspace.
"""
function _spectral_sliced_drifted!(sx::Vector{T}, sy::Vector{T}, source, s::T) where {T}
    n = length(source.x)
    length(sx) == n || resize!(sx, n)
    length(sy) == n || resize!(sy, n)
    @inbounds for i in 1:n
        sx[i] = T(source.x[i]) + T(source.px[i]) * s
        sy[i] = T(source.y[i]) + T(source.py[i]) * s
    end
    return nothing
end

"""This part's virtual (luminosity-plane) positions; `_spectral_midpoint_source`
into caller-owned buffers, taken before anything kicks the part."""
function _spectral_sliced_virtual!(vx::Vector{T}, vy::Vector{T}, source,
                                   param_source, param_field) where {T}
    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    n = length(source.x)
    length(vx) == n || resize!(vx, n)
    length(vy) == n || resize!(vy, n)
    @inbounds for i in 1:n
        vx[i] = T(source.x[i]) + T(source.px[i]) * sM
        vy[i] = T(source.y[i]) + T(source.py[i]) * sM
    end
    return nothing
end

"""This part's contribution to one drifted source plane of one direction.

`which` is 1 for the field slice's left boundary and 2 for its right, the `sL`
and `sR` of `_spectral_interaction!`.
"""
function _spectral_sliced_source!(plane, solver::SpectralPoissonSolver, part,
                                  param_source, param_field, which::Int,
                                  sx::Vector{T}, sy::Vector{T}, Lx, Ly) where {T}
    fill!(plane, zero(T))
    length(part.x) == 0 && return plane
    s = which == 1 ? T(0.5) * (T(param_source.center) - T(param_field.lb)) :
                     T(0.5) * (T(param_source.center) - T(param_field.rb))
    _spectral_sliced_drifted!(sx, sy, part, s)
    solver.method === :grid_free ? _spectral_free_modes!(plane, sx, sy, Lx, Ly) :
                                   _spectral_grid_deposit!(plane, sx, sy, Lx, Ly)
    return plane
end

"""The field head turns a folded source plane into what its group evaluates."""
function _spectral_sliced_payload!(payload, solver::SpectralPoissonSolver, plane,
                                   ns::Int, Lx, Ly, ws)
    if solver.method === :grid_free
        copyto!(view(payload, :, :, 1), plane)
        return payload
    end
    copyto!(ws.rho, plane)
    _spectral_grid_potential_from_rho!(ws, ns, Lx, Ly)
    copyto!(view(payload, :, :, 1), ws.Phig)
    copyto!(view(payload, :, :, 2), ws.Exg)
    copyto!(view(payload, :, :, 3), ws.Eyg)
    return payload
end

"""`Phi`, `Ex`, `Ey` at this part's field particles from one payload."""
function _spectral_sliced_eval(solver::SpectralPoissonSolver, payload, ns::Int,
                               fx, fy, Lx, Ly, ws, vslot::Int)
    if solver.method === :grid_free
        return _spectral_free_potential_from_modes(view(payload, :, :, 1), ns, fx, fy,
                                                   Lx, Ly, size(payload, 1), size(payload, 2))
    end
    copyto!(ws.Phig, view(payload, :, :, 1))
    copyto!(ws.Exg, view(payload, :, :, 2))
    copyto!(ws.Eyg, view(payload, :, :, 3))
    return _spectral_grid_potential_eval(ws, fx, fy, Lx, Ly; vslot=vslot)
end

"""The drift IN of `_spectral_interaction!`, on this part of the field slice."""
function _spectral_sliced_drift_in!(field, param_source, ::Type{T}) where {T}
    @inbounds for i in eachindex(field.x)
        s = T(0.5) * (T(field.z[i]) - T(param_source.center))
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
    end
    return nothing
end

"""The blended kick and the drift OUT of `_spectral_interaction!`, term for term."""
function _spectral_sliced_kick!(field, param_source, param_field, kbb_slice,
                                phiL, ExL, EyL, phiR, ExR, EyR, ::Type{T}) where {T}
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    kick_scale = T(kbb_slice)
    @inbounds for i in eachindex(field.x)
        zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T))
        zR = one(T) - zL
        Kx = zL * ExL[i] + zR * ExR[i]
        Ky = zL * EyL[i] + zR * EyR[i]
        Kz = phiL[i] - phiR[i]
        field.px[i] += kick_scale * Kx
        field.py[i] += kick_scale * Ky
        field.pz[i] += kick_scale * Kz * hzi
        s = T(0.5) * (T(param_source.center) - T(field.z[i]))
        field.x[i] += s * field.px[i]
        field.y[i] += s * field.py[i]
        field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
    end
    return nothing
end

# --- the pair ------------------------------------------------------------------

mutable struct _SpectralSlicedPair{T}
    p::Int                       # position in the collision order
    i::Int
    j::Int
    pair::Int                    # tag base
    in1::Bool
    in2::Bool
    coord::Int                   # first rank of slice i's group
    head::NTuple{2,Int}          # by direction: the FIELD slice's group head
    param1::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    param2::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    planes_out::NTuple{2,Vector{Matrix{T}}}           # source member: per plane
    partials_in::NTuple{2,Vector{Vector{Matrix{T}}}}  # head(d): per plane, the group's partials
    payload_in::NTuple{2,Vector{Array{T,3}}}          # field member: per plane
    payload_out::NTuple{2,Vector{Array{T,3}}}         # head(d): per plane
    vx1::Vector{T}; vy1::Vector{T}
    vx2::Vector{T}; vy2::Vector{T}
    lumext::Union{Nothing,Vector{T}}
    lumexts_in::Vector{Vector{T}}
    lummesh::Union{Nothing,Vector{T}}
    lumdeps_in::NTuple{2,Vector{Matrix{T}}}
end

function _spectral_sliced_pair(::Type{T}, p, i, j, ns2, in1, in2, coord, head,
                               param1, param2) where {T}
    return _SpectralSlicedPair{T}(p, i, j, (i - 1) * ns2 + j, in1, in2, coord, head,
        param1, param2,
        (Matrix{T}[], Matrix{T}[]), (Vector{Matrix{T}}[], Vector{Matrix{T}}[]),
        (Array{T,3}[], Array{T,3}[]), (Array{T,3}[], Array{T,3}[]),
        T[], T[], T[], T[], nothing, Vector{T}[], nothing,
        (Matrix{T}[], Matrix{T}[]))
end

# --- the collide ---------------------------------------------------------------

"""
The slice-aligned 6D spectral collide of one batch list. Writes this rank's
coordinated pairs into `lum_parts` (the caller all-sums the vector) and leaves
the kicked coordinates in the sliced beams.
"""
function _spectral_collide_sliced!(sb1::_PICSlicedBeam{T}, sb2::_PICSlicedBeam{T},
                                   batches, pair_pos, lum_parts, solver, slices1, slices2,
                                   counts1, counts2, pool, sc::_SpectralSlicedScratch{T},
                                   kbb1, kbb2, klum, Lx, Ly,
                                   compute_luminosity::Bool) where {T}
    P = _mp_nranks()
    rank = _mp_rank()
    ns1 = length(sb1.layout.counts)
    ns2 = length(sb2.layout.counts)
    Nx, Ny = solver.grid
    lnx, lny = solver.grid
    np = _spectral_payload_planes(solver)
    grid = solver.method !== :grid_free
    reqs = _mp_requests()
    _mp_check_tag_bound(_spectral_sliced_tag(ns1 * ns2, _SPECTRAL_TAG_CODES))
    partials_sent = 0; partials_received = 0
    payloads_sent = 0; payloads_received = 0
    lum_sent = 0; lum_received = 0; messages = 0
    pairs_coordinated = 0; planes_solved = 0; nbad = 0
    nworkers = length(pool)
    for batch in batches
        _spectral_sliced_reset!(sc)
        plist = _SpectralSlicedPair{T}[]
        for (i, j) in sort([(pr.i, pr.j) for pr in batch])
            counts1[i] == 0 && continue
            counts2[j] == 0 && continue
            g1 = sb1.layout.groups[i]; g2 = sb2.layout.groups[j]
            in1 = rank in g1; in2 = rank in g2
            (in1 || in2) || continue
            param1 = (weight=T(slices1.weight[i]), lb=T(slices1.boundary[i]),
                      center=T(slices1.center[i]), rb=T(slices1.boundary[i + 1]))
            param2 = (weight=T(slices2.weight[j]), lb=T(slices2.boundary[j]),
                      center=T(slices2.center[j]), rb=T(slices2.boundary[j + 1]))
            # The FIELD slice's head solves: direction 1 kicks slice j, so slice
            # j's head folds and solves it, and its potentials never leave g2.
            push!(plist, _spectral_sliced_pair(T, pair_pos[(i, j)], i, j, ns2, in1, in2,
                                               first(g1), (first(g2), first(g1)),
                                               param1, param2))
        end
        isempty(plist) && continue

        # --- stage 1: the drifted source deposits -------------------------------
        # Every source plane and every virtual position below is read from the
        # part as it stands BEFORE this pair kicks anything, which is what makes
        # the two directions independent of each other and lets both slices be
        # kicked in place: the undivided loop copies slice j only because it
        # takes its deposits later.
        srcwork = Tuple{Int,Int}[]
        for (q, pr) in enumerate(plist)
            for d in 1:2
                as_source = d == 1 ? pr.in1 : pr.in2
                if as_source
                    for _ in 1:2
                        push!(pr.planes_out[d], _spectral_plane!(sc, Nx, Ny))
                    end
                    vx = _spectral_virt!(sc); vy = _spectral_virt!(sc)
                    d == 1 ? (pr.vx1 = vx; pr.vy1 = vy) : (pr.vx2 = vx; pr.vy2 = vy)
                    push!(srcwork, (q, d))
                end
                if rank == pr.head[d]
                    src_group = d == 1 ? sb1.layout.groups[pr.i] : sb2.layout.groups[pr.j]
                    for m in 1:2
                        got = Matrix{T}[]
                        for r in src_group
                            plane = _spectral_plane!(sc, Nx, Ny)
                            push!(got, plane)
                            push!(reqs, _mp_irecv!(plane, r,
                                _spectral_sliced_tag(pr.pair, _SPEC_TAG_PARTIAL + 2 * (d - 1) + m - 1)))
                            partials_received += 1
                        end
                        push!(pr.partials_in[d], got)
                    end
                end
            end
        end
        # `let`, and the same at the two stages below: `plist` and the work
        # lists are assigned once per BATCH, so a closure that captured them
        # from the loop body would grow one shared `Core.Box` per name -- the
        # trap the permanent lowered-code sweep exists to catch. Re-binding
        # them here gives the closure names assigned exactly once.
        if !isempty(srcwork)
            let plist = plist, srcwork = srcwork, nw = clamp(nworkers, 1, length(srcwork))
            _run_logical_workers(nw) do chunk, _
                sx = T[]; sy = T[]
                lo, hi = _chunk_bounds(length(srcwork), nw, chunk)
                for t in lo:hi
                    q, d = srcwork[t]
                    pr = plist[q]
                    part = d == 1 ? sb1.states[pr.i] : sb2.states[pr.j]
                    param_source = d == 1 ? pr.param1 : pr.param2
                    param_field = d == 1 ? pr.param2 : pr.param1
                    for m in 1:2
                        _spectral_sliced_source!(pr.planes_out[d][m], solver, part,
                                                 param_source, param_field, m, sx, sy, Lx, Ly)
                    end
                    vx = d == 1 ? pr.vx1 : pr.vx2
                    vy = d == 1 ? pr.vy1 : pr.vy2
                    _spectral_sliced_virtual!(vx, vy, part, param_source, param_field)
                end
            end
            end
        end
        for (q, d) in srcwork
            pr = plist[q]
            for m in 1:2
                push!(reqs, _mp_isend(pr.planes_out[d][m], pr.head[d],
                    _spectral_sliced_tag(pr.pair, _SPEC_TAG_PARTIAL + 2 * (d - 1) + m - 1)))
                partials_sent += 1
            end
        end
        _mp_wait_all(reqs, :wait_deposits)

        # --- stage 2: the field heads fold and solve ----------------------------
        headwork = Tuple{Int,Int}[]
        for (q, pr) in enumerate(plist)
            for d in 1:2
                if rank == pr.head[d]
                    for _ in 1:2
                        push!(pr.payload_out[d], _spectral_payload!(sc, Nx, Ny, np))
                    end
                    push!(headwork, (q, d))
                end
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                for m in 1:2
                    payload = _spectral_payload!(sc, Nx, Ny, np)
                    push!(pr.payload_in[d], payload)
                    push!(reqs, _mp_irecv!(payload, pr.head[d],
                        _spectral_sliced_tag(pr.pair, _SPEC_TAG_PAYLOAD + 2 * (d - 1) + m - 1)))
                    payloads_received += 1
                end
            end
        end
        if !isempty(headwork)
            let plist = plist, headwork = headwork, nw = clamp(nworkers, 1, length(headwork))
            _run_logical_workers(nw) do chunk, _
                ws = grid ? pool[chunk] : nothing
                lo, hi = _chunk_bounds(length(headwork), nw, chunk)
                for t in lo:hi
                    q, d = headwork[t]
                    pr = plist[q]
                    ns = d == 1 ? counts1[pr.i] : counts2[pr.j]
                    for m in 1:2
                        # Folded in SOURCE-GROUP rank order, never on arrival.
                        acc = pr.payload_out[d][m]
                        fold = _spectral_sliced_fold!(pr.partials_in[d][m])
                        _spectral_sliced_payload!(acc, solver, fold, ns, Lx, Ly, ws)
                    end
                end
            end
            end
            planes_solved += 2 * length(headwork)
        end
        for (q, d) in headwork
            pr = plist[q]
            field_group = d == 1 ? sb2.layout.groups[pr.j] : sb1.layout.groups[pr.i]
            for m in 1:2, r in field_group
                push!(reqs, _mp_isend(pr.payload_out[d][m], r,
                    _spectral_sliced_tag(pr.pair, _SPEC_TAG_PAYLOAD + 2 * (d - 1) + m - 1)))
                payloads_sent += 1
            end
        end
        _mp_wait_all(reqs, :wait_payloads)

        # --- stage 3: the field members drift, evaluate and kick ----------------
        kickwork = Tuple{Int,Int}[]
        for (q, pr) in enumerate(plist)
            for d in 1:2
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field && push!(kickwork, (q, d))
            end
        end
        if !isempty(kickwork)
            let plist = plist, kickwork = kickwork, nw = clamp(nworkers, 1, length(kickwork))
            _run_logical_workers(nw) do chunk, _
                ws = grid ? pool[chunk] : nothing
                lo, hi = _chunk_bounds(length(kickwork), nw, chunk)
                for t in lo:hi
                    q, d = kickwork[t]
                    pr = plist[q]
                    field = d == 1 ? sb2.states[pr.j] : sb1.states[pr.i]
                    param_source = d == 1 ? pr.param1 : pr.param2
                    param_field = d == 1 ? pr.param2 : pr.param1
                    ns = d == 1 ? counts1[pr.i] : counts2[pr.j]
                    kbb = d == 1 ? T(slices1.weight[pr.i]) * kbb2 :
                                   T(slices2.weight[pr.j]) * kbb1
                    _spectral_sliced_drift_in!(field, param_source, T)
                    phiL, ExL, EyL = _spectral_sliced_eval(solver, pr.payload_in[d][1], ns,
                                                           field.x, field.y, Lx, Ly, ws, 1)
                    phiR, ExR, EyR = _spectral_sliced_eval(solver, pr.payload_in[d][2], ns,
                                                           field.x, field.y, Lx, Ly, ws, 2)
                    _spectral_sliced_kick!(field, param_source, param_field, kbb,
                                           phiL, ExL, EyL, phiR, ExR, EyR, T)
                end
            end
            end
        end

        # --- stage 4: the luminosity --------------------------------------------
        compute_luminosity || continue
        for pr in plist
            g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _SPEC_TAG_LUMEXT1),
                                       (pr.in2, pr.vx2, pr.vy2, _SPEC_TAG_LUMEXT2))
                as || continue
                v = _spectral_record!(sc, 4)
                v[1] = -_pic_extremum(minimum, vx, T(Inf)); v[2] = _pic_extremum(maximum, vx, T(-Inf))
                v[3] = -_pic_extremum(minimum, vy, T(Inf)); v[4] = _pic_extremum(maximum, vy, T(-Inf))
                push!(reqs, _mp_isend(v, pr.coord, _spectral_sliced_tag(pr.pair, code)))
                messages += 1
            end
            if rank == pr.coord
                pairs_coordinated += 1
                for (g, code) in ((g1, _SPEC_TAG_LUMEXT1), (g2, _SPEC_TAG_LUMEXT2)), r in g
                    v = _spectral_record!(sc, 4)
                    push!(pr.lumexts_in, v)
                    push!(reqs, _mp_irecv!(v, r, _spectral_sliced_tag(pr.pair, code)))
                end
            end
        end
        _mp_wait_all(reqs, :wait_lum_extents)
        for pr in plist
            members = _pic_sliced_members(sb1.layout.groups[pr.i], sb2.layout.groups[pr.j])
            if rank == pr.coord
                xmin = T(Inf); xmax = T(-Inf); ymin = T(Inf); ymax = T(-Inf)
                for v in pr.lumexts_in
                    xmin = min(xmin, -v[1]); xmax = max(xmax, v[2])
                    ymin = min(ymin, -v[3]); ymax = max(ymax, v[4])
                end
                width, height, ok = _spectral_luminosity_extents_ok(
                    solver, xmax - xmin, ymax - ymin, T)
                tx = width / T(lnx - 1.1); ty = height / T(lny - 1.1)
                width += T(0.1) * tx; height += T(0.1) * ty
                xmin -= T(0.05) * tx; ymin -= T(0.05) * ty
                mv = _spectral_record!(sc, 5)
                mv[1] = xmin; mv[2] = ymin
                mv[3] = width / (lnx - 1); mv[4] = height / (lny - 1)
                # The verdict travels WITH the mesh: only the coordinator can
                # see the folded extents, so a throw it took alone would leave
                # its peers in the next receive (the 4c rule for a refusal).
                mv[5] = ok ? one(T) : zero(T)
                pr.lummesh = mv
                for r in members
                    push!(reqs, _mp_isend(mv, r, _spectral_sliced_tag(pr.pair, _SPEC_TAG_LUMMESH)))
                    messages += 1
                end
            end
            # Every member of the pair receives, the coordinator included: its
            # own send is the seam's self-delivery, so one code path serves both.
            mv = _spectral_record!(sc, 5)
            pr.lummesh = mv
            push!(reqs, _mp_irecv!(mv, pr.coord, _spectral_sliced_tag(pr.pair, _SPEC_TAG_LUMMESH)))
        end
        _mp_wait_all(reqs, :wait_lum_mesh)
        # A degenerate mesh is COUNTED, not thrown here: only the ranks of that
        # pair received the verdict, and a throw they took alone would leave
        # every other rank in the next batch's first receive. The transport
        # agrees the count once the batches are through and every rank refuses
        # together -- the 4c rule.
        bad = falses(length(plist))
        for (q, pr) in enumerate(plist)
            pr.lummesh[5] == zero(T) && (bad[q] = true; nbad += 1)
        end
        for (q, pr) in enumerate(plist)
            bad[q] && continue
            g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
            mv = pr.lummesh
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _SPEC_TAG_LUMDEP1),
                                       (pr.in2, pr.vx2, pr.vy2, _SPEC_TAG_LUMDEP2))
                as || continue
                q = _spectral_lumgrid!(sc, lnx, lny)
                fill!(q, zero(T))
                _spectral_cic_deposit!(q, vx, vy, mv[1], mv[2], mv[3], mv[4])
                push!(reqs, _mp_isend(q, pr.coord, _spectral_sliced_tag(pr.pair, code)))
                lum_sent += 1
            end
            if rank == pr.coord
                for (g, code, slot) in ((g1, _SPEC_TAG_LUMDEP1, 1), (g2, _SPEC_TAG_LUMDEP2, 2)), r in g
                    q = _spectral_lumgrid!(sc, lnx, lny)
                    push!(pr.lumdeps_in[slot], q)
                    push!(reqs, _mp_irecv!(q, r, _spectral_sliced_tag(pr.pair, code)))
                    lum_received += 1
                end
            end
        end
        _mp_wait_all(reqs, :wait_lum_deposits)
        for (q, pr) in enumerate(plist)
            (bad[q] || rank != pr.coord) && continue
            q1 = _spectral_sliced_fold!(pr.lumdeps_in[1])
            q2 = _spectral_sliced_fold!(pr.lumdeps_in[2])
            mv = pr.lummesh
            lum = zero(T)
            @inbounds for k in eachindex(q1); lum += q1[k] * q2[k]; end
            @inbounds lum_parts[pr.p] = lum * T(klum) / (mv[3] * mv[4])
        end
    end
    _record_execution!(:spectral_slice_exchange, CPUThreadsBackend,
                       (partials_sent=partials_sent, partials_received=partials_received,
                        payloads_sent=payloads_sent, payloads_received=payloads_received,
                        lum_sent=lum_sent, lum_received=lum_received, messages=messages,
                        pairs_coordinated=pairs_coordinated, planes_solved=planes_solved,
                        schedule=:batched, ranks=P))
    return nbad
end

"""Fold a group's partials into the FIRST of them, in group rank order.

The order is the group's, never the order the messages arrived in: that is what
makes a rank count reproducible run to run.
"""
function _spectral_sliced_fold!(parts::Vector{Matrix{T}}) where {T}
    acc = parts[1]
    for k in 2:length(parts)
        p = parts[k]
        @inbounds for t in eachindex(acc); acc[t] += p[t]; end
    end
    return acc
end

# --- transport -----------------------------------------------------------------

"""
    _spectral_sliced_transport!(solver, beam1, beam2, ...) -> nothing

The slice-aligned collide's transport for the 6D spectral map: the layout, the
two migrations, the batches, the receipts and the luminosity all-sum. The layout
and the migration are `pic_cpu_sliced.jl`'s -- they are a property of the
slicing, not of the field solver -- and what spectral supplies is the batch loop
above.
"""
function _spectral_sliced_transport!(solver::SpectralPoissonSolver, beam1::Beam, beam2::Beam,
                                     slices1, slices2, order, npairs::Int, pair_pos,
                                     lum_parts, plan1, plan2, kbb1, kbb2, klum, Lx, Ly,
                                     compute_luminosity::Bool, requested::Symbol,
                                     sliced_scratch::Base.RefValue{Any},
                                     sliced_migration_ref::Base.RefValue{Any},
                                     ::Type{T}) where {T}
    P = _mp_nranks()
    layout1 = _pic_sliced_layout(plan1.counts, P)
    layout2 = _pic_sliced_layout(plan2.counts, P)
    mig1, mig2 = _pic_migration_scratch(T, sliced_migration_ref)
    sb1 = _pic_sliced_migrate_in(beam1.rep, slices1, layout1, mig1, T)
    sb2 = _pic_sliced_migrate_in(beam2.rep, slices2, layout2, mig2, T)
    batching = requested === :wavefront && npairs > 1
    batches = batching ? collision_pair_batches(slices1, slices2) :
                         [[(i=Int(entry[2]), j=Int(entry[3]))] for entry in order]
    _record_execution!(:spectral_pair_schedule, CPUThreadsBackend,
                       (batch_mode=batching ? :wavefront : :sequential,
                        requested=requested, pairs=npairs,
                        batches=batching ? length(batches) : 0,
                        widest_batch=batching ? maximum(length, batches; init=0) : 0,
                        ranks=P, exchange=:sliced))
    for (which, sb) in ((1, sb1), (2, sb2))
        _record_execution!(:spectral_slice_layout, CPUThreadsBackend,
                           (beam=which, groups=[length(g) for g in sb.layout.groups],
                            migrated_out=sb.migrated_out, migrated_in=sb.migrated_in,
                            ranks=P))
    end
    grid = solver.method !== :grid_free
    nworkers = max(1, _cpu_worker_count())
    lease = grid ? _acquire_spectral_grid_ws_pool(solver.grid[1], solver.grid[2], nworkers) :
                   nothing
    pool = grid ? lease.workspaces : fill(nothing, nworkers)
    sc = _spectral_sliced_scratch(T, sliced_scratch)
    nbad = try
        _spectral_collide_sliced!(sb1, sb2, batches, pair_pos, lum_parts, solver,
                                  slices1, slices2, plan1.counts, plan2.counts,
                                  pool, sc, kbb1, kbb2, klum, Lx, Ly, compute_luminosity)
    finally
        lease === nothing || _release_spectral_grid_ws_pool!(lease)
    end
    _pic_sliced_migrate_out!(beam1.rep, sb1, mig1)
    _pic_sliced_migrate_out!(beam2.rep, sb2, mig2)
    # The coordinators hold their pairs' values and everyone else zeros, so the
    # all-sum is exact and every rank folds the same vector below.
    _mp_allsum!(lum_parts)
    # The degenerate-mesh verdict, agreed once per collide: every rank throws
    # or none, the pair's own ranks having already skipped it.
    nbad_all = _mp_global_count(nbad)
    nbad_all > 0 && throw(ArgumentError(
        "Spectral luminosity requires finite, positive transverse extents; " *
        "$(nbad_all) slice pair(s) produced none with min_domain_halfwidth=" *
        "$(solver.min_domain_halfwidth) (this rank coordinated $(nbad) of them). " *
        "Supply a positive physical bound for a degenerate axis."))
    return nothing
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::SpectralPoissonSolver,
                                 beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                 ctx::TrackingContext)
    # The slice-aligned collide's scratch and migration buffers, kept across
    # turns for the reason the PIC pools are: a fresh set is a whole collide's
    # worth of garbage. The FFT workspaces already have their own lease cache.
    ref(key) = get!(() -> Ref{Any}(nothing), task.runtime_cache, (key, label))::Base.RefValue{Any}
    return _spectral_collide!(solver, beam1, beam2, ctx;
                              sliced_scratch=ref(:cpu_spectral_sliced_scratch),
                              sliced_migration_ref=ref(:cpu_spectral_sliced_migration))
end

_strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                solver::SpectralPoissonSolver,
                                beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                ctx::TrackingContext) =
    _strong_strong_collide!(task, label, solver, beam1, beam2, CPUThreadsBackend, ctx)
