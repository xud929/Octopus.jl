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
function Octopus._mp_allsum_impl!(A::AbstractArray, comm::MPI.Comm)
    nranks = Int(MPI.Comm_size(comm))
    nranks == 1 && return A
    flat = vec(A)
    n = length(flat)
    gathered = Vector{eltype(A)}(undef, n * nranks)
    MPI.Allgather!(MPI.Buffer(flat), MPI.UBuffer(gathered, n), comm)
    fill!(flat, zero(eltype(A)))
    for r in 0:(nranks - 1)
        offset = r * n
        @inbounds for i in 1:n
            flat[i] += gathered[offset + i]
        end
    end
    return A
end

# min and max associate freely, so these need no ordered fold — which is what
# makes them usable for mesh and box sizing without a determinism argument.
Octopus._mp_allminmax_impl(lo, hi, comm::MPI.Comm) =
    (MPI.Allreduce(lo, min, comm), MPI.Allreduce(hi, max, comm))
Octopus._mp_allmin_impl!(A::AbstractArray, comm::MPI.Comm) = (MPI.Allreduce!(A, min, comm); A)
Octopus._mp_allmax_impl!(A::AbstractArray, comm::MPI.Comm) = (MPI.Allreduce!(A, max, comm); A)

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
