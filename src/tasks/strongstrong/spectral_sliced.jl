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

"""
Tag base for one pair of a batch.

Keyed by the pair's position in the BATCH's canonical order, not by its index
in the whole collide. A batch is a barrier -- every message it posts is waited
before the next batch posts anything -- so positions are all the separation
tags need, and the largest tag is then `(widest batch) * 16` rather than
`ns1 * ns2 * 16`. The MPI standard only guarantees tags up to 32767, which the
global keying would have exceeded past 45 slices a beam; and since the slice
count is exactly the knob that raises the rank ceiling (a batch holds at most
`min(n1, n2)` pairs and so `4 * min(n1, n2)` independent solves), that ceiling
must not be the thing that caps it.
"""
_spectral_sliced_tag(pair::Int, code::Int) = (pair - 1) * _SPECTRAL_TAG_CODES + code

"""
Which member of a field slice's group solves each of its two drifted planes.

Offset by the pair's collision position so consecutive pairs pick different
members, and by the plane so the two planes of one direction never land on the
same rank when the group can spare a second. A group of one gives that member
both planes, which is the rule this replaces -- so a run with whole slices on
whole ranks is unchanged, message for message.
"""
@inline function _spectral_sliced_solvers(group::UnitRange{Int}, k::Int)
    g = length(group)
    return (group[((k) % g) + 1], group[((k + 1) % g) + 1])
end

"""
Each pair's position among the pairs on each of ITS OWN slices, in collision
order.

The deal rotates over a group by this and not by the pair's position in the
whole collide, because a slice's pairs sit at scattered positions of that order
and `p % g` over a scattered set is not a rotation. It showed: at sixty-four
ranks the busiest rank carried 20 solved planes and the idlest 7, a 2.9x spread
where the group sizes alone (four and five) predict at most 1.25x. Numbering a
slice's pairs 1, 2, 3, ... makes the rotation exact, and an all-to-all is a
barrier that charges every rank for the slowest -- so this imbalance was being
paid twice, once in the solve and again in the migration's clock.
"""
function _spectral_slice_pair_positions(order, pair_pos, counts1, counts2)
    pos1 = Dict{Int,Int}(); pos2 = Dict{Int,Int}()
    seen1 = zeros(Int, length(counts1)); seen2 = zeros(Int, length(counts2))
    for entry in order
        i = Int(entry[2]); j = Int(entry[3])
        (counts1[i] == 0 || counts2[j] == 0) && continue
        p = pair_pos[(i, j)]
        seen1[i] += 1; seen2[j] += 1
        pos1[p] = seen1[i]; pos2[p] = seen2[j]
    end
    return pos1, pos2
end

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
    # Straight out of the payload: the mesh a field member evaluates is the one
    # that arrived, and copying it into the workspace first bought nothing.
    nf = length(fx)
    return _spectral_grid_potential_eval!(
        _spectral_slot(ws.phi_buf, vslot, nf), _spectral_slot(ws.ex_buf, vslot, nf),
        _spectral_slot(ws.ey_buf, vslot, nf),
        view(payload, :, :, 1), view(payload, :, :, 2), view(payload, :, :, 3),
        fx, fy, Lx, Ly)
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
    # By (direction, plane): the member of the FIELD slice's group that folds
    # that plane's deposits and solves it. Dealt across the group rather than
    # pinned to its head -- see `_spectral_sliced_solvers`.
    solvers::NTuple{2,NTuple{2,Int}}
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

function _spectral_sliced_pair(::Type{T}, p, i, j, tagbase, in1, in2, coord, solvers,
                               param1, param2) where {T}
    return _SpectralSlicedPair{T}(p, i, j, tagbase, in1, in2, coord, solvers,
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
                                   batches, order, pair_pos, lum_parts, solver, slices1, slices2,
                                   counts1, counts2, pool, sc::_SpectralSlicedScratch{T},
                                   kbb1, kbb2, klum, Lx, Ly,
                                   compute_luminosity::Bool) where {T}
    P = _mp_nranks()
    rank = _mp_rank()
    Nx, Ny = solver.grid
    lnx, lny = solver.grid
    np = _spectral_payload_planes(solver)
    grid = solver.method !== :grid_free
    reqs = _mp_requests()
    _mp_check_tag_bound(_spectral_sliced_tag(maximum(length, batches; init=1),
                                             _SPECTRAL_TAG_CODES))
    partials_sent = 0; partials_received = 0
    payloads_sent = 0; payloads_received = 0
    lum_sent = 0; lum_received = 0; messages = 0
    pairs_coordinated = 0; planes_solved = 0; nbad = 0
    nworkers = length(pool)
    pos1, pos2 = _spectral_slice_pair_positions(order, pair_pos, counts1, counts2)
    for batch in batches
        _spectral_sliced_reset!(sc)
        plist = _SpectralSlicedPair{T}[]
        # `qb` is the pair's position in the batch's canonical order -- the same
        # number on every rank, and this batch's tag base. Skipped pairs keep
        # their position (the skip reads global counts, so every rank skips the
        # same ones).
        for (qb, (i, j)) in enumerate(sort([(pr.i, pr.j) for pr in batch]))
            counts1[i] == 0 && continue
            counts2[j] == 0 && continue
            g1 = sb1.layout.groups[i]; g2 = sb2.layout.groups[j]
            in1 = rank in g1; in2 = rank in g2
            (in1 || in2) || continue
            param1 = (weight=T(slices1.weight[i]), lb=T(slices1.boundary[i]),
                      center=T(slices1.center[i]), rb=T(slices1.boundary[i + 1]))
            param2 = (weight=T(slices2.weight[j]), lb=T(slices2.boundary[j]),
                      center=T(slices2.center[j]), rb=T(slices2.boundary[j + 1]))
            # A pair has FOUR independent solves -- two directions times the two
            # drifted planes -- and they are dealt across the FIELD slice's
            # group. Direction 1 kicks slice j, so g2 solves it and its
            # potentials never leave the group that needs them; direction 2 is
            # g1's. With a whole slice on one rank the group has one member and
            # this is the head rule it replaces, bit for bit. Once a slice
            # spans a group it is what lets more than `nslices` ranks solve at
            # all: the solve is ~70% of the collide and the only step that does
            # not split by particle, so pinning it to `first(group)` capped the
            # run at one solver per slice however many ranks were in force
            # (measured: 74 ms at sixteen ranks, 227 ms at thirty-two).
            p = pair_pos[(i, j)]
            push!(plist, _spectral_sliced_pair(T, p, i, j, qb, in1, in2, first(g1),
                                               (_spectral_sliced_solvers(g2, pos2[p]),
                                                _spectral_sliced_solvers(g1, pos1[p])),
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
                src_group = d == 1 ? sb1.layout.groups[pr.i] : sb2.layout.groups[pr.j]
                for m in 1:2
                    got = Matrix{T}[]
                    if rank == pr.solvers[d][m]
                        for r in src_group
                            plane = _spectral_plane!(sc, Nx, Ny)
                            push!(got, plane)
                            push!(reqs, _mp_irecv!(plane, r,
                                _spectral_sliced_tag(pr.pair, _SPEC_TAG_PARTIAL + 2 * (d - 1) + m - 1)))
                            partials_received += 1
                        end
                    end
                    push!(pr.partials_in[d], got)     # empty unless this rank solves it
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
                push!(reqs, _mp_isend(pr.planes_out[d][m], pr.solvers[d][m],
                    _spectral_sliced_tag(pr.pair, _SPEC_TAG_PARTIAL + 2 * (d - 1) + m - 1)))
                partials_sent += 1
            end
        end
        # The luminosity's extents ride THIS wait (they are read from the virtual
        # positions the pass above just wrote, and nothing else needs them
        # earlier), and its mesh rides the payload wait below. That is two of
        # the batch's five barriers removed: every barrier costs the slowest
        # rank of the batch, and the count multiplies by the batch count.
        if compute_luminosity
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
        end
        _mp_wait_all(reqs, :wait_deposits)

        # --- stage 2: the field heads fold and solve ----------------------------
        # The coordinators' luminosity meshes go out with the payloads: the
        # folded extents arrived at the wait above, and nothing reads the mesh
        # before the deposits below.
        if compute_luminosity
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
        end
        # One work item per (pair, direction, PLANE), not per (pair, direction):
        # four independent solves per pair instead of two chunks of two, which
        # is both what spreads them over the group and what gives a rank four
        # threads' worth of independent solves when it holds whole slices.
        headwork = NTuple{4,Int}[]
        for (q, pr) in enumerate(plist)
            for d in 1:2
                for m in 1:2
                    if rank == pr.solvers[d][m]
                        push!(pr.payload_out[d], _spectral_payload!(sc, Nx, Ny, np))
                        push!(headwork, (q, d, m, length(pr.payload_out[d])))
                    end
                end
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                for m in 1:2
                    payload = _spectral_payload!(sc, Nx, Ny, np)
                    push!(pr.payload_in[d], payload)
                    push!(reqs, _mp_irecv!(payload, pr.solvers[d][m],
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
                    q, d, m, slot = headwork[t]
                    pr = plist[q]
                    ns = d == 1 ? counts1[pr.i] : counts2[pr.j]
                    # Folded in SOURCE-GROUP rank order, never on arrival.
                    fold = _spectral_sliced_fold!(pr.partials_in[d][m])
                    _spectral_sliced_payload!(pr.payload_out[d][slot], solver, fold,
                                              ns, Lx, Ly, ws)
                end
            end
            end
            planes_solved += length(headwork)
        end
        for (q, d, m, slot) in headwork
            pr = plist[q]
            field_group = d == 1 ? sb2.layout.groups[pr.j] : sb1.layout.groups[pr.i]
            for r in field_group
                push!(reqs, _mp_isend(pr.payload_out[d][slot], r,
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
        # Last in the batch, so this skip skips only itself.
        compute_luminosity || continue
        # A degenerate mesh is COUNTED, not thrown here: only the ranks of that
        # pair received the verdict, and a throw they took alone would leave
        # every other rank in the next batch's first receive. The transport
        # agrees the count once the batches are through and every rank refuses
        # together -- the 4c rule.
        bad = falses(length(plist))
        for (q, pr) in enumerate(plist)
            pr.lummesh[5] == zero(T) || continue
            bad[q] = true
            # Counted by the COORDINATOR alone: every member of the pair
            # receives the same verdict, so counting them all would report a
            # pair count multiplied by the group size.
            rank == pr.coord && (nbad += 1)
        end
        for (q, pr) in enumerate(plist)
            bad[q] && continue
            g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
            mv = pr.lummesh
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _SPEC_TAG_LUMDEP1),
                                       (pr.in2, pr.vx2, pr.vy2, _SPEC_TAG_LUMDEP2))
                as || continue
                dep = _spectral_lumgrid!(sc, lnx, lny)
                fill!(dep, zero(T))
                _spectral_cic_deposit!(dep, vx, vy, mv[1], mv[2], mv[3], mv[4])
                push!(reqs, _mp_isend(dep, pr.coord, _spectral_sliced_tag(pr.pair, code)))
                lum_sent += 1
            end
            if rank == pr.coord
                for (g, code, slot) in ((g1, _SPEC_TAG_LUMDEP1, 1), (g2, _SPEC_TAG_LUMDEP2, 2)), r in g
                    dep = _spectral_lumgrid!(sc, lnx, lny)
                    push!(pr.lumdeps_in[slot], dep)
                    push!(reqs, _mp_irecv!(dep, r, _spectral_sliced_tag(pr.pair, code)))
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
                                     lum_parts, counts1, counts2, kbb1, kbb2, klum, Lx, Ly,
                                     compute_luminosity::Bool, requested::Symbol,
                                     sliced_scratch::Base.RefValue{Any},
                                     sliced_pool_ref::Base.RefValue{Any},
                                     sliced_migration_ref::Base.RefValue{Any},
                                     ::Type{T}) where {T}
    P = _mp_nranks()
    layout1 = _pic_sliced_layout(counts1, P)
    layout2 = _pic_sliced_layout(counts2, P)
    mig1, mig2 = _pic_migration_scratch(T, sliced_migration_ref)
    sb1, sb2 = _pic_sliced_migrate_pair_in(beam1.rep, slices1, layout1,
                                          beam2.rep, slices2, layout2, mig1, mig2, T)
    batching = requested === :wavefront && npairs > 1
    batches = batching ? collision_pair_batches(slices1, slices2) :
                         [[(i=Int(entry[2]), j=Int(entry[3]))] for entry in order]
    # WHICH loop, when the schedule leaves it open, is the layout's question
    # rather than a preference. A pair may not start until each of its slices
    # has been kicked by the pair before it, so a rank holding a WHOLE slice
    # has its pairs on that slice strictly in series and nothing to overlap:
    # the dataflow loop then only adds a wake per hop, and it gives up the
    # batched loop's threading (four independent solves a batch). Once a slice
    # spans a group each rank holds a fraction of the chain's work and there is
    # real independent work between the hops. `_SPECTRAL_SLICED_LOOP` overrides
    # it for a measurement or a pin, so the two can be timed on the same box at
    # the same moment and held to the same bits.
    widest_group = max(maximum(length, layout1.groups; init=0),
                       maximum(length, layout2.groups; init=0))
    loop = _SPECTRAL_SLICED_LOOP[] !== :auto ? _SPECTRAL_SLICED_LOOP[] :
           !batching ? :batched :
           widest_group >= 2 ? :dataflow : :batched
    _record_execution!(:spectral_pair_schedule, CPUThreadsBackend,
                       (batch_mode=batching ? :wavefront : :sequential,
                        requested=requested, pairs=npairs,
                        batches=batching ? length(batches) : 0,
                        widest_batch=batching ? maximum(length, batches; init=0) : 0,
                        ranks=P, exchange=:sliced, schedule=loop))
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
    nbad = try
        if loop === :dataflow
            _spectral_collide_dataflow!(sb1, sb2, order, pair_pos, lum_parts, solver,
                                        slices1, slices2, counts1, counts2,
                                        _spectral_df_pool(T, sliced_pool_ref, solver.grid[1],
                                                          solver.grid[2],
                                                          _spectral_payload_planes(solver),
                                                          solver.grid[1], solver.grid[2]),
                                        grid ? pool[1] : nothing,
                                        kbb1, kbb2, klum, Lx, Ly, compute_luminosity)
        else
            _spectral_collide_sliced!(sb1, sb2, batches, order, pair_pos, lum_parts, solver,
                                      slices1, slices2, counts1, counts2, pool,
                                      _spectral_sliced_scratch(T, sliced_scratch),
                                      kbb1, kbb2, klum, Lx, Ly, compute_luminosity)
        end
    finally
        lease === nothing || _release_spectral_grid_ws_pool!(lease)
    end
    _pic_sliced_migrate_pair_out!(beam1.rep, sb1, beam2.rep, sb2, mig1)
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
                              sliced_pool_ref=ref(:cpu_spectral_sliced_pool),
                              sliced_migration_ref=ref(:cpu_spectral_sliced_migration))
end

_strong_strong_collide_backend!(task::StrongStrongTask, label::Symbol,
                                solver::SpectralPoissonSolver,
                                beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                ctx::TrackingContext) =
    _strong_strong_collide!(task, label, solver, beam1, beam2, CPUThreadsBackend, ctx)

# --- the dataflow loop (multi-process step 4h) ---------------------------------
#
# The batched loop above walks every pair of a wavefront batch through the same
# stage at the same time, so a rank waits at each stage for the slowest member
# of the batch and idles whenever its own pairs are done. Nothing in the physics
# asks for that: a pair depends only on its two slices' PREVIOUS pairs, so each
# rank can instead run an event loop -- scan its pairs in the collision order,
# run every stage whose receives have arrived, and block on the union of what is
# outstanding only when a whole scan ran nothing.
#
# The stages, their messages, their tags' CODES and every number they compute
# are the batched loop's (the leaves are shared), so the two loops are
# bit-identical; `_SPECTRAL_SLICED_LOOP` pins them against each other and the
# launcher child holds them to the same bits at every rank count.
#
# Three rules make it safe, and they are PIC's (step 4e) because the hazards are
# the layout's rather than the solver's:
#
#  * **The gate** is the collision order, not index arithmetic. A pair may start
#    once the pair BEFORE it on each of its slices (among the non-empty pairs,
#    in `order`) has kicked. For ascending slice centres the collision time
#    `-(c1+c2)/2` puts the largest `j` first, so slice `i`'s predecessor of
#    `(i, j)` is `(i, j+1)`, not `(i, j-1)` -- which is why this is derived from
#    `order` and never computed from indices. `_pic_df_predecessors` already
#    does it.
#  * **A send buffer belongs to its send** until MPI says the send completed. A
#    pair returns its buffers to the free lists only after `_mp_test_all` on its
#    send list is true; under the batched loop the per-stage `_mp_wait_all`
#    covered that, and here nothing else does.
#  * **A pair whose luminosity mesh is degenerate still kicks**, and skips only
#    its luminosity -- which is what the batched loop does, because spectral's
#    `bad` verdict is about the luminosity mesh alone and arrives after the
#    kick. (PIC's is about the pair's field extents and comes before, so its
#    dataflow loop skips the kick; the wording is not transferable.) Either way
#    the pair reaches DONE, so its successors run and the collide reaches the
#    count that makes every rank throw; a bad pair that simply stopped would
#    hang both its slices.
#
# One thing differs from the batched loop and it is in the TAGS. A batch is a
# barrier, so the batched loop can key its tags by a pair's position in the
# batch; the dataflow loop has pairs from different batches in flight at once,
# so its tags must separate every pair of the collide. `_mp_check_tag_bound`
# is what says whether the communicator has room, and it throws rather than
# letting two pairs share a tag.

"""
Which loop the slice-aligned spectral collide runs, for measurement and for the
pin that holds the two to the same bits: `:auto` (the layout decides),
`:dataflow`, or `:batched`. NOT a solver keyword: one keyword means one thing
everywhere, and this selects an implementation of the same physics rather than
a configuration of it.
"""
const _SPECTRAL_SLICED_LOOP = Base.ScopedValues.ScopedValue{Symbol}(:auto)

const _SPEC_DF_DEPOSIT = 1
const _SPEC_DF_SOLVE = 2
const _SPEC_DF_KICK = 3
const _SPEC_DF_LUMFOLD = 4
const _SPEC_DF_DONE = 5
const _SPEC_DF_STAGE_NAMES = (:wait_deposits, :wait_payloads, :wait_lum_deposits,
                              :wait_lum_fold, :wait_done)
# The relay stages: a rank serves these before its own deposits and kicks, so
# the pairs waiting on it are not held behind a long stage of its own. The
# solve is a relay because a whole field group waits on it, and the luminosity
# fold because it is the last thing a coordinator owes.
const _SPEC_DF_RELAY = (_SPEC_DF_SOLVE, _SPEC_DF_LUMFOLD)

"""Free lists for the dataflow loop, by shape: a pair takes what it needs and
gives it all back once its receives are consumed and its sends complete."""
mutable struct _SpectralDataflowPool{T}
    planes::Vector{Matrix{T}}
    payloads::Vector{Array{T,3}}
    lums::Vector{Matrix{T}}
    recs::Dict{Int,Vector{Vector{T}}}
    virts::Vector{Vector{T}}
    nx::Int
    ny::Int
    np::Int
    lnx::Int
    lny::Int
    live_planes::Int
    high_planes::Int
end
_SpectralDataflowPool{T}(nx, ny, np, lnx, lny) where {T} =
    _SpectralDataflowPool{T}(Matrix{T}[], Array{T,3}[], Matrix{T}[],
                             Dict{Int,Vector{Vector{T}}}(), Vector{T}[],
                             nx, ny, np, lnx, lny, 0, 0)

function _spectral_df_pool(::Type{T}, holder::Base.RefValue{Any}, nx, ny, np, lnx, lny) where {T}
    pool = holder[]
    if pool isa _SpectralDataflowPool{T} && pool.nx == nx && pool.ny == ny &&
       pool.np == np && pool.lnx == lnx && pool.lny == lny
        return pool
    end
    fresh = _SpectralDataflowPool{T}(nx, ny, np, lnx, lny)
    holder[] = fresh
    return fresh
end

function _spectral_df_plane!(pool::_SpectralDataflowPool{T}) where {T}
    pool.live_planes += 1
    pool.high_planes = max(pool.high_planes, pool.live_planes)
    isempty(pool.planes) && return zeros(T, pool.nx, pool.ny)
    return pop!(pool.planes)
end
_spectral_df_payload!(pool::_SpectralDataflowPool{T}) where {T} =
    isempty(pool.payloads) ? zeros(T, pool.nx, pool.ny, pool.np) : pop!(pool.payloads)
_spectral_df_lum!(pool::_SpectralDataflowPool{T}) where {T} =
    isempty(pool.lums) ? zeros(T, pool.lnx, pool.lny) : pop!(pool.lums)
_spectral_df_virt!(pool::_SpectralDataflowPool{T}) where {T} =
    isempty(pool.virts) ? T[] : pop!(pool.virts)
function _spectral_df_rec!(pool::_SpectralDataflowPool{T}, n::Int) where {T}
    free = get!(() -> Vector{T}[], pool.recs, n)
    v = isempty(free) ? zeros(T, n) : pop!(free)
    fill!(v, zero(T))
    return v
end

"""What the dataflow loop counted, in a struct because its event loop reads
these outside the closure that writes them (a local would be one `Core.Box`
each, which the permanent lowered-code sweep names)."""
mutable struct _SpectralDataflowCounters
    nbad::Int
    partials_sent::Int
    partials_received::Int
    payloads_sent::Int
    payloads_received::Int
    lum_sent::Int
    lum_received::Int
    messages::Int
    pairs_coordinated::Int
    planes_solved::Int
    max_in_flight::Int
    inflight::Int
end
_SpectralDataflowCounters() = _SpectralDataflowCounters(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

"""One pair on this rank under the dataflow loop: its roles, its gate, the stage
it will run next, its per-stage receives, its outstanding sends, and every
buffer it holds."""
mutable struct _SpectralDataflowPair{T,R}
    p::Int
    i::Int
    j::Int
    in1::Bool
    in2::Bool
    coord::Int
    solvers::NTuple{2,NTuple{2,Int}}
    param1::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    param2::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    gate1::Int
    gate2::Int
    stage::Int
    bad::Bool
    retired::Bool
    recv::Vector{Vector{R}}
    sends::Vector{R}
    planes_out::NTuple{2,Vector{Matrix{T}}}
    partials_in::NTuple{2,Vector{Vector{Matrix{T}}}}
    payload_in::NTuple{2,Vector{Array{T,3}}}
    payload_out::NTuple{2,Vector{Array{T,3}}}
    solve_slots::Vector{NTuple{3,Int}}      # (direction, plane, slot) this rank solves
    vx1::Vector{T}; vy1::Vector{T}
    vx2::Vector{T}; vy2::Vector{T}
    lumexts_in::Vector{Vector{T}}
    lummesh::Union{Nothing,Vector{T}}
    lumdeps_in::NTuple{2,Vector{Matrix{T}}}
    took_planes::Vector{Matrix{T}}
    took_payloads::Vector{Array{T,3}}
    took_lums::Vector{Matrix{T}}
    took_recs::Vector{Vector{T}}
    took_virts::Vector{Vector{T}}
end

function _spectral_df_pair(::Type{T}, ::Type{R}, p, i, j, in1, in2, coord, solvers,
                           param1, param2) where {T,R}
    return _SpectralDataflowPair{T,R}(
        p, i, j, in1, in2, coord, solvers, param1, param2,
        0, 0, _SPEC_DF_DEPOSIT, false, false,
        [R[] for _ in 1:_SPEC_DF_DONE], R[],
        (Matrix{T}[], Matrix{T}[]), (Vector{Matrix{T}}[], Vector{Matrix{T}}[]),
        (Array{T,3}[], Array{T,3}[]), (Array{T,3}[], Array{T,3}[]),
        NTuple{3,Int}[], T[], T[], T[], T[], Vector{T}[], nothing,
        (Matrix{T}[], Matrix{T}[]),
        Matrix{T}[], Array{T,3}[], Matrix{T}[], Vector{T}[], Vector{T}[])
end

_spectral_df_take_plane!(pr::_SpectralDataflowPair, pool) =
    (A = _spectral_df_plane!(pool); push!(pr.took_planes, A); A)
_spectral_df_take_payload!(pr::_SpectralDataflowPair, pool) =
    (A = _spectral_df_payload!(pool); push!(pr.took_payloads, A); A)
_spectral_df_take_lum!(pr::_SpectralDataflowPair, pool) =
    (A = _spectral_df_lum!(pool); push!(pr.took_lums, A); A)
_spectral_df_take_rec!(pr::_SpectralDataflowPair, pool, n::Int) =
    (v = _spectral_df_rec!(pool, n); push!(pr.took_recs, v); v)
_spectral_df_take_virt!(pr::_SpectralDataflowPair, pool) =
    (v = _spectral_df_virt!(pool); push!(pr.took_virts, v); v)

"""Give a finished pair's buffers back. Called only once its sends have
completed, so no buffer is handed out while MPI may still be reading it."""
function _spectral_df_retire!(pr::_SpectralDataflowPair{T},
                              pool::_SpectralDataflowPool{T}) where {T}
    for A in pr.took_planes
        pool.live_planes -= 1
        push!(pool.planes, A)
    end
    append!(pool.payloads, pr.took_payloads)
    append!(pool.lums, pr.took_lums)
    for v in pr.took_recs
        push!(get!(() -> Vector{T}[], pool.recs, length(v)), v)
    end
    append!(pool.virts, pr.took_virts)
    empty!(pr.took_planes); empty!(pr.took_payloads); empty!(pr.took_lums)
    empty!(pr.took_recs); empty!(pr.took_virts)
    pr.retired = true
    return nothing
end

"""
The slice-aligned spectral collide under the dataflow loop. Same stages, same
arithmetic and the same messages as `_spectral_collide_sliced!`; only WHEN a
rank runs them differs.
"""
function _spectral_collide_dataflow!(sb1::_PICSlicedBeam{T}, sb2::_PICSlicedBeam{T},
                                     order, pair_pos, lum_parts, solver, slices1, slices2,
                                     counts1, counts2, pool::_SpectralDataflowPool{T},
                                     ws, kbb1, kbb2, klum, Lx, Ly,
                                     compute_luminosity::Bool) where {T}
    P = _mp_nranks()
    rank = _mp_rank()
    Nx, Ny = solver.grid
    lnx, lny = solver.grid
    grid = solver.method !== :grid_free
    R = eltype(_mp_requests())
    prev1, prev2 = _pic_df_predecessors(order, pair_pos, counts1, counts2)
    pos1, pos2 = _spectral_slice_pair_positions(order, pair_pos, counts1, counts2)
    # This rank's pairs, in the collision order, with the position of each in
    # this list so a gate is a local index.
    plist = _SpectralDataflowPair{T,R}[]
    index_of = Dict{Int,Int}()
    for entry in order
        i = Int(entry[2]); j = Int(entry[3])
        (counts1[i] == 0 || counts2[j] == 0) && continue
        p = pair_pos[(i, j)]
        g1 = sb1.layout.groups[i]; g2 = sb2.layout.groups[j]
        in1 = rank in g1; in2 = rank in g2
        (in1 || in2) || continue
        param1 = (weight=T(slices1.weight[i]), lb=T(slices1.boundary[i]),
                  center=T(slices1.center[i]), rb=T(slices1.boundary[i + 1]))
        param2 = (weight=T(slices2.weight[j]), lb=T(slices2.boundary[j]),
                  center=T(slices2.center[j]), rb=T(slices2.boundary[j + 1]))
        push!(plist, _spectral_df_pair(T, R, p, i, j, in1, in2, first(g1),
                                       (_spectral_sliced_solvers(g2, pos2[p]),
                                        _spectral_sliced_solvers(g1, pos1[p])),
                                       param1, param2))
        index_of[p] = length(plist)
    end
    for pr in plist
        pr.in1 && (pr.gate1 = get(index_of, get(prev1, pr.p, 0), 0))
        pr.in2 && (pr.gate2 = get(index_of, get(prev2, pr.p, 0), 0))
    end
    # Every pair of the collide needs its own tag band here: unlike the batched
    # loop, pairs from different wavefront batches are in flight at once.
    _mp_check_tag_bound(_spectral_sliced_tag(length(counts1) * length(counts2),
                                             _SPECTRAL_TAG_CODES))
    c = _SpectralDataflowCounters()
    wait_calls = 0; wait_ns = 0; scans = 0

    ready(pr) = _mp_test_all(pr.recv[pr.stage])
    gated(pr) = (pr.gate1 != 0 && plist[pr.gate1].stage <= _SPEC_DF_KICK) ||
                (pr.gate2 != 0 && plist[pr.gate2].stage <= _SPEC_DF_KICK)

    function run_stage!(pr)
        s = pr.stage
        g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
        if s == _SPEC_DF_DEPOSIT
            c.inflight += 1
            c.max_in_flight = max(c.max_in_flight, c.inflight)
            sx = T[]; sy = T[]
            for d in 1:2
                as_source = d == 1 ? pr.in1 : pr.in2
                src_group = d == 1 ? g1 : g2
                if as_source
                    part = d == 1 ? sb1.states[pr.i] : sb2.states[pr.j]
                    param_source = d == 1 ? pr.param1 : pr.param2
                    param_field = d == 1 ? pr.param2 : pr.param1
                    for m in 1:2
                        plane = _spectral_df_take_plane!(pr, pool)
                        push!(pr.planes_out[d], plane)
                        _spectral_sliced_source!(plane, solver, part, param_source,
                                                 param_field, m, sx, sy, Lx, Ly)
                    end
                    # The virtual positions, read BEFORE anything kicks this part.
                    vx = _spectral_df_take_virt!(pr, pool)
                    vy = _spectral_df_take_virt!(pr, pool)
                    d == 1 ? (pr.vx1 = vx; pr.vy1 = vy) : (pr.vx2 = vx; pr.vy2 = vy)
                    _spectral_sliced_virtual!(vx, vy, part, param_source, param_field)
                end
                for m in 1:2
                    got = Matrix{T}[]
                    if rank == pr.solvers[d][m]
                        for r in src_group
                            plane = _spectral_df_take_plane!(pr, pool)
                            push!(got, plane)
                            push!(pr.recv[_SPEC_DF_SOLVE], _mp_irecv!(plane, r,
                                _spectral_sliced_tag(pr.p, _SPEC_TAG_PARTIAL + 2 * (d - 1) + m - 1)))
                            c.partials_received += 1
                        end
                    end
                    push!(pr.partials_in[d], got)
                end
            end
            for d in 1:2
                (d == 1 ? pr.in1 : pr.in2) || continue
                for m in 1:2
                    push!(pr.sends, _mp_isend(pr.planes_out[d][m], pr.solvers[d][m],
                        _spectral_sliced_tag(pr.p, _SPEC_TAG_PARTIAL + 2 * (d - 1) + m - 1)))
                    c.partials_sent += 1
                end
            end
            if compute_luminosity
                for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _SPEC_TAG_LUMEXT1),
                                           (pr.in2, pr.vx2, pr.vy2, _SPEC_TAG_LUMEXT2))
                    as || continue
                    v = _spectral_df_take_rec!(pr, pool, 4)
                    v[1] = -_pic_extremum(minimum, vx, T(Inf)); v[2] = _pic_extremum(maximum, vx, T(-Inf))
                    v[3] = -_pic_extremum(minimum, vy, T(Inf)); v[4] = _pic_extremum(maximum, vy, T(-Inf))
                    push!(pr.sends, _mp_isend(v, pr.coord, _spectral_sliced_tag(pr.p, code)))
                    c.messages += 1
                end
                if rank == pr.coord
                    c.pairs_coordinated += 1
                    for (g, code) in ((g1, _SPEC_TAG_LUMEXT1), (g2, _SPEC_TAG_LUMEXT2)), r in g
                        v = _spectral_df_take_rec!(pr, pool, 4)
                        push!(pr.lumexts_in, v)
                        push!(pr.recv[_SPEC_DF_SOLVE],
                              _mp_irecv!(v, r, _spectral_sliced_tag(pr.p, code)))
                    end
                end
            end
            pr.stage = _SPEC_DF_SOLVE
        elseif s == _SPEC_DF_SOLVE
            if compute_luminosity
                members = _pic_sliced_members(g1, g2)
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
                    mv = _spectral_df_take_rec!(pr, pool, 5)
                    mv[1] = xmin; mv[2] = ymin
                    mv[3] = width / (lnx - 1); mv[4] = height / (lny - 1)
                    mv[5] = ok ? one(T) : zero(T)
                    for r in members
                        push!(pr.sends, _mp_isend(mv, r,
                            _spectral_sliced_tag(pr.p, _SPEC_TAG_LUMMESH)))
                        c.messages += 1
                    end
                end
                mv = _spectral_df_take_rec!(pr, pool, 5)
                pr.lummesh = mv
                push!(pr.recv[_SPEC_DF_KICK],
                      _mp_irecv!(mv, pr.coord, _spectral_sliced_tag(pr.p, _SPEC_TAG_LUMMESH)))
            end
            for d in 1:2
                for m in 1:2
                    if rank == pr.solvers[d][m]
                        payload = _spectral_df_take_payload!(pr, pool)
                        push!(pr.payload_out[d], payload)
                        ns = d == 1 ? counts1[pr.i] : counts2[pr.j]
                        # Folded in SOURCE-GROUP rank order, never on arrival.
                        fold = _spectral_sliced_fold!(pr.partials_in[d][m])
                        _spectral_sliced_payload!(payload, solver, fold, ns, Lx, Ly, ws)
                        c.planes_solved += 1
                        push!(pr.solve_slots, (d, m, length(pr.payload_out[d])))
                    end
                end
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                for m in 1:2
                    payload = _spectral_df_take_payload!(pr, pool)
                    push!(pr.payload_in[d], payload)
                    push!(pr.recv[_SPEC_DF_KICK], _mp_irecv!(payload, pr.solvers[d][m],
                        _spectral_sliced_tag(pr.p, _SPEC_TAG_PAYLOAD + 2 * (d - 1) + m - 1)))
                    c.payloads_received += 1
                end
            end
            for (d, m, slot) in pr.solve_slots
                field_group = d == 1 ? g2 : g1
                for r in field_group
                    push!(pr.sends, _mp_isend(pr.payload_out[d][slot], r,
                        _spectral_sliced_tag(pr.p, _SPEC_TAG_PAYLOAD + 2 * (d - 1) + m - 1)))
                    c.payloads_sent += 1
                end
            end
            pr.stage = _SPEC_DF_KICK
        elseif s == _SPEC_DF_KICK
            # A degenerate luminosity mesh is COUNTED, and the pair still
            # releases its slices: a bad pair that stopped here would hang every
            # successor on both of them.
            # The kick runs whatever the luminosity mesh turned out to be: the
            # batched loop kicks first and reads the verdict afterwards, and the
            # two loops have to be the same collide, not merely the same answer
            # when nothing goes wrong.
            if compute_luminosity && pr.lummesh[5] == zero(T)
                pr.bad = true
                rank == pr.coord && (c.nbad += 1)
            end
            for d in 1:2
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
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
            if compute_luminosity && !pr.bad
                mv = pr.lummesh
                for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _SPEC_TAG_LUMDEP1),
                                           (pr.in2, pr.vx2, pr.vy2, _SPEC_TAG_LUMDEP2))
                    as || continue
                    dep = _spectral_df_take_lum!(pr, pool)
                    fill!(dep, zero(T))
                    _spectral_cic_deposit!(dep, vx, vy, mv[1], mv[2], mv[3], mv[4])
                    push!(pr.sends, _mp_isend(dep, pr.coord,
                                              _spectral_sliced_tag(pr.p, code)))
                    c.lum_sent += 1
                end
                if rank == pr.coord
                    for (g, code, slot) in ((g1, _SPEC_TAG_LUMDEP1, 1),
                                            (g2, _SPEC_TAG_LUMDEP2, 2)), r in g
                        dep = _spectral_df_take_lum!(pr, pool)
                        push!(pr.lumdeps_in[slot], dep)
                        push!(pr.recv[_SPEC_DF_LUMFOLD],
                              _mp_irecv!(dep, r, _spectral_sliced_tag(pr.p, code)))
                        c.lum_received += 1
                    end
                end
            end
            pr.stage = _SPEC_DF_LUMFOLD
        elseif s == _SPEC_DF_LUMFOLD
            if compute_luminosity && !pr.bad && rank == pr.coord
                q1 = _spectral_sliced_fold!(pr.lumdeps_in[1])
                q2 = _spectral_sliced_fold!(pr.lumdeps_in[2])
                mv = pr.lummesh
                lum = zero(T)
                @inbounds for k in eachindex(q1); lum += q1[k] * q2[k]; end
                @inbounds lum_parts[pr.p] = lum * T(klum) / (mv[3] * mv[4])
            end
            pr.stage = _SPEC_DF_DONE
            c.inflight -= 1
        end
        return true
    end

    remaining = length(plist)
    while remaining > 0
        scans += 1
        ran_any = false
        # Relay duties first (a solver's fold and solve, a coordinator's mesh
        # and luminosity fold), then this rank's own particle work: a pair
        # waiting on this rank is not held behind a long deposit of its own.
        for relay in (true, false)
            for pr in plist
                pr.stage == _SPEC_DF_DONE && continue
                (pr.stage in _SPEC_DF_RELAY) == relay || continue
                pr.stage == _SPEC_DF_DEPOSIT && gated(pr) && continue
                ready(pr) || continue
                run_stage!(pr)
                ran_any = true
                pr.stage == _SPEC_DF_DONE && (remaining -= 1)
            end
        end
        # Buffers go back only once the sends that read them have completed.
        for pr in plist
            (pr.stage == _SPEC_DF_DONE && !pr.retired && _mp_test_all(pr.sends)) &&
                _spectral_df_retire!(pr, pool)
        end
        ran_any && continue
        remaining == 0 && break
        # Nothing ran: block on everything outstanding, whichever arrives.
        union = _mp_requests()
        stage = _SPEC_DF_DONE
        for pr in plist
            pr.stage == _SPEC_DF_DONE && continue
            isempty(pr.recv[pr.stage]) && continue   # gated, not waiting on a message
            append!(union, pr.recv[pr.stage])
            stage = min(stage, pr.stage)
        end
        isempty(union) && error(
            "the spectral dataflow loop has $(remaining) pair(s) to run and nothing " *
            "outstanding: the first is pair " *
            "$(first(pr.p for pr in plist if pr.stage != _SPEC_DF_DONE)) at stage " *
            "$(_SPEC_DF_STAGE_NAMES[first(pr.stage for pr in plist if pr.stage != _SPEC_DF_DONE)])")
        t0 = time_ns()
        _mp_wait_any(union, _SPEC_DF_STAGE_NAMES[stage])
        wait_ns += Int(time_ns() - t0)
        wait_calls += 1
    end
    # Every send drained before the buffers are handed back to the next collide.
    for pr in plist
        pr.retired || (_mp_wait_all(pr.sends, :wait_sends); _spectral_df_retire!(pr, pool))
    end
    _record_execution!(:spectral_slice_exchange, CPUThreadsBackend,
                       (partials_sent=c.partials_sent, partials_received=c.partials_received,
                        payloads_sent=c.payloads_sent, payloads_received=c.payloads_received,
                        lum_sent=c.lum_sent, lum_received=c.lum_received, messages=c.messages,
                        pairs_coordinated=c.pairs_coordinated, planes_solved=c.planes_solved,
                        schedule=:dataflow, ranks=P))
    return c.nbad
end
