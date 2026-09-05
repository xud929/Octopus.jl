# Package extension binding Octopus's collective seam to MPI.jl — the one
# dependency-bound half of the multi-process execution policy (campaign step
# 2; docs/design/multi_process_policy.md). Core owns the policy type, the
# communicator handshake and a serial passthrough for every collective; this
# file owns nothing but the MPI calls.
#
# Every method here ADDS to a core function rather than replacing one: the
# communicator opener dispatches on `Octopus.MPIBackendTag` against a core
# fallback typed `::Any`, and each collective dispatches on `MPI.Comm`
# against a core method typed `::Nothing`. An extension that redefined a
# method its parent already defined for the same signature would fail to
# precompile.
module OctopusMPIExt

using Octopus
using MPI

"""
Octopus's own communicator, duplicated from `MPI.COMM_WORLD` once per
process.

Duplicated so that Octopus's collectives cannot interleave with a user's on
`COMM_WORLD` — the seam's determinism argument assumes its own messages are
the only ones in flight on its communicator. Cached because `Comm_dup` is
itself collective and activation happens once per `execute!`: duplicating per
activation would both leak a communicator per call and require every rank to
call it the same number of times.
"""
const _OCTOPUS_COMM = Ref{Any}(nothing)

function Octopus._mp_open_communicator(::Octopus.MPIBackendTag)
    if _OCTOPUS_COMM[] === nothing
        if MPI.Finalized()
            error("MPI has been finalized; a MultiProcessExecutionPolicy cannot \
                   open a communicator. Run Octopus before MPI.Finalize().")
        end
        # `:funneled`: Octopus issues every collective from the task driver on
        # the main thread, never from inside a worker task. Requesting a
        # weaker level than the code needs is the only safe direction, and a
        # user who initialised MPI themselves keeps their own level.
        MPI.Initialized() || MPI.Init(threadlevel = :funneled)
        _OCTOPUS_COMM[] = MPI.Comm_dup(MPI.COMM_WORLD)
    end
    return _OCTOPUS_COMM[]
end

Octopus._mp_communicator_size(comm::MPI.Comm) = Int(MPI.Comm_size(comm))
Octopus._mp_communicator_rank(comm::MPI.Comm) = Int(MPI.Comm_rank(comm))

# Wall time inside the MPI calls, per kind (`Octopus._mp_collective_times`):
# two clock reads per collective, main thread only.
const _MP_TIMES = Dict{Symbol,Tuple{Int,Int}}()
Octopus._mp_collective_times_impl(::Octopus.MPIBackendTag) = copy(_MP_TIMES)
Octopus._mp_reset_collective_times_impl!(::Octopus.MPIBackendTag) = (empty!(_MP_TIMES); nothing)
@inline function _mp_timed(f::F, kind::Symbol) where {F}
    t0 = time_ns()
    r = f()
    calls, ns = get(_MP_TIMES, kind, (0, 0))
    _MP_TIMES[kind] = (calls + 1, ns + Int(time_ns() - t0))
    return r
end

# Above `_MP_ALLSUM_SCATTER_MIN` elements the same sum is computed as a
# reduce-scatter (step 4c performance phase): an `Alltoall` of `P` equal blocks
# -- the array padded to a multiple of `P` -- each rank folding the `P` blocks it
# received IN RANK ORDER, then an `Allgather` of the folded blocks. Element by
# element that is exactly the gather-and-fold's sum (block `r` of rank `q` is
# the `r`-th term, so the bits are the same; measured identical at every size
# and rank count tried, 2, 4 and 8 ranks, `n` from 1 to 65536), moving `2n`
# elements per rank instead of `nP`: a 512 KB plane at 2 ranks went 6.3 ms ->
# 0.25 ms, at 8 ranks 10.0 -> 0.9 ms. Below the threshold two collectives cost
# more than one gather. The buffers are kept per (element type, padded length)
# -- collectives are funneled, so no two run at once.
const _MP_ALLSUM_SCATTER_MIN = 2048
const _MP_ALLSUM_BUFFERS = Dict{Tuple{DataType,Int,Int},Any}()

"""Two `padded`-long vectors and one `block`-long one, keyed by all three so
that two callers wanting the same padded length with different blocks never
share a short block buffer. CONCRETELY typed on the way out: held as
`Vector` the fold below dispatched per element and a 512 KB plane cost 42 ms
against 0.09 ms for the MPI calls themselves (2026-09-05)."""
function _mp_allsum_buffers(::Type{E}, padded::Int, block::Int) where {E}
    bufs = get!(_MP_ALLSUM_BUFFERS, (E, padded, block)) do
        (Vector{E}(undef, padded), Vector{E}(undef, padded), Vector{E}(undef, block))
    end
    return bufs::Tuple{Vector{E},Vector{E},Vector{E}}
end

"""
Allgather, then fold the per-rank blocks into `A` IN RANK ORDER.

Not `MPI.Allreduce(+)`: a library sum may associate as it pleases and may
choose a different tree for a different rank count, so the same run at the
same rank count could give different last bits on different ranks, and a
2-rank run could disagree with a 4-rank one for reasons no physics explains.
A gather plus a fixed-order fold gives every rank the same bits, and the
project's determinism posture is stated against that (`docs/design/
multi_process_policy.md`). It costs O(P) in message volume, which the Phase 0
measurement already priced at 0.10–0.35 s/turn for 2–8 ranks.
"""
Octopus._mp_allsum_impl!(A::AbstractArray, comm::MPI.Comm) =
    _mp_timed(() -> _mp_allsum_timed!(A, comm), :allsum)

function _mp_allsum_timed!(A::AbstractArray, comm::MPI.Comm)
    nranks = Int(MPI.Comm_size(comm))
    nranks == 1 && return A
    n = length(A)
    E = eltype(A)
    # Through the cached vectors, never `MPI.Buffer(A)`: the batched exchange
    # hands the seam contiguous VIEWS of its staging arrays, which linear
    # `copyto!` reads and writes and a raw buffer would not.
    if n >= _MP_ALLSUM_SCATTER_MIN
        block = cld(n, nranks)
        padded = block * nranks
        send, recv, mine = _mp_allsum_buffers(E, padded, block)
        # Only the padding past the data needs zeroing.
        n < padded && fill!(view(send, (n + 1):padded), zero(E))
        copyto!(send, 1, A, 1, n)
        MPI.Alltoall!(MPI.UBuffer(send, block), MPI.UBuffer(recv, block), comm)
        fill!(mine, zero(E))
        for r in 0:(nranks - 1)
            offset = r * block
            @inbounds for i in 1:block
                mine[i] += recv[offset + i]
            end
        end
        MPI.Allgather!(MPI.Buffer(mine), MPI.UBuffer(send, block), comm)
        copyto!(A, 1, send, 1, n)
        return A
    end
    _, gathered, mine = _mp_allsum_buffers(E, n * nranks, n)
    copyto!(mine, 1, A, 1, n)
    MPI.Allgather!(MPI.Buffer(mine), MPI.UBuffer(gathered, n), comm)
    @inbounds for i in 1:n
        s = zero(E)
        for r in 0:(nranks - 1)
            s += gathered[r * n + i]
        end
        A[i] = s
    end
    return A
end

"""
The migration (`Octopus._mp_exchange_columns`): columns sorted by
destination, stably, so the order within a destination is the sender's; one
`Alltoallv` of whole columns.
"""
function Octopus._mp_exchange_columns_impl(cols::AbstractMatrix, dest, comm::MPI.Comm)
    return _mp_timed(:exchange_columns) do
        nranks = Int(MPI.Comm_size(comm))
        k, n = size(cols)
        E = eltype(cols)
        length(dest) == n || error("one destination per column: $(length(dest)) for $(n)")
        send_counts = zeros(Cint, nranks)
        for d in dest
            0 <= d < nranks || error("destination rank $(d) outside 0:$(nranks - 1)")
            send_counts[d + 1] += 1
        end
        offsets = cumsum(vcat(0, Int.(send_counts)))     # column offset per destination
        send = Matrix{E}(undef, k, n)
        fill_pos = copy(offsets)
        @inbounds for j in 1:n
            d = dest[j] + 1
            fill_pos[d] += 1
            copyto!(send, (fill_pos[d] - 1) * k + 1, cols, (j - 1) * k + 1, k)
        end
        recv_counts = similar(send_counts)
        MPI.Alltoall!(MPI.UBuffer(send_counts, 1), MPI.UBuffer(recv_counts, 1), comm)
        total = Int(sum(recv_counts))
        recv = Matrix{E}(undef, k, total)
        MPI.Alltoallv!(MPI.VBuffer(vec(send), send_counts .* Cint(k)),
                       MPI.VBuffer(vec(recv), recv_counts .* Cint(k)), comm)
        return recv, Int.(recv_counts)
    end
end

Octopus._mp_isend_impl(A, dest::Int, tag::Int, comm::MPI.Comm) =
    _mp_timed(() -> MPI.Isend(A, comm; dest=dest, tag=tag), :isend)
Octopus._mp_irecv_impl!(A, source::Int, tag::Int, comm::MPI.Comm) =
    _mp_timed(() -> MPI.Irecv!(A, comm; source=source, tag=tag), :irecv)
Octopus._mp_wait_all_impl(requests::Vector{MPI.Request}, stage::Symbol, ::MPI.Comm) =
    _mp_timed(() -> (MPI.Waitall(requests); nothing), stage)
Octopus._mp_requests_impl(::MPI.Comm) = MPI.Request[]

"""The cached vector `A`'s elements are copied through for a min/max
all-reduce, so a view can cross the seam (see `_mp_allsum_impl!`)."""
function _mp_minmax_through_buffer!(A::AbstractArray, op, comm::MPI.Comm)
    n = length(A)
    E = eltype(A)
    _, _, buf = _mp_allsum_buffers(E, n, n)
    copyto!(buf, 1, A, 1, n)
    MPI.Allreduce!(buf, op, comm)
    copyto!(A, 1, buf, 1, n)
    return A
end

# min and max associate freely, so these need no ordered fold — which is what
# makes them usable for mesh and box sizing without a determinism argument.
Octopus._mp_allminmax_impl(lo, hi, comm::MPI.Comm) = _mp_timed(:allminmax) do
    (MPI.Allreduce(lo, min, comm), MPI.Allreduce(hi, max, comm))
end
Octopus._mp_allmin_impl!(A::AbstractArray, comm::MPI.Comm) =
    _mp_timed(() -> _mp_minmax_through_buffer!(A, min, comm), :allmin)
Octopus._mp_allmax_impl!(A::AbstractArray, comm::MPI.Comm) =
    _mp_timed(() -> _mp_minmax_through_buffer!(A, max, comm), :allmax)

Octopus._mp_bcast_impl!(A::AbstractArray, root::Int, comm::MPI.Comm) =
    (MPI.Bcast!(A, root, comm); A)

Octopus._mp_bcast_scalar_impl(value, root::Int, comm::MPI.Comm) =
    MPI.bcast(value, root, comm)

Octopus._mp_barrier_impl(comm::MPI.Comm) = (MPI.Barrier(comm); nothing)

"""
Gather rows onto rank 0 in rank order.

Column by column, because the rows are stored column-major and a per-column
`Gatherv!` needs no transposition on either side. The counts are all-reduced
first so every rank knows the layout and only rank 0 allocates the result.
"""
function Octopus._mp_gather_rows_impl(rows::AbstractMatrix, comm::MPI.Comm)
    nranks = Int(MPI.Comm_size(comm))
    nranks == 1 && return rows
    rank = Int(MPI.Comm_rank(comm))
    root = 0
    ncols = size(rows, 2)
    counts = zeros(Cint, nranks)
    counts[rank + 1] = Cint(size(rows, 1))
    MPI.Allreduce!(counts, +, comm)
    total = Int(sum(counts))
    T = eltype(rows)
    out = rank == root ? Matrix{T}(undef, total, ncols) : Matrix{T}(undef, 0, ncols)
    for j in 1:ncols
        send = collect(@view rows[:, j])
        if rank == root
            recv = Vector{T}(undef, total)
            MPI.Gatherv!(send, MPI.VBuffer(recv, counts), root, comm)
            @inbounds out[:, j] = recv
        else
            MPI.Gatherv!(send, nothing, root, comm)
        end
    end
    return out
end

end
