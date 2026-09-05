export PlaceholderPolicy, CPUThreadsExecutionPolicy,
       MultiProcessExecutionPolicy,
       AbstractGPUExecutionPolicy, CUDALaunchConfig, CUDAExecutionPolicy,
       GPUExecutionPolicy, backend_type, activate_policy!,
       ConfigurationOptionMeta, ConfigurationEntry, policy_option_schema,
       configuration_report, validate_configuration_metadata,
       ExecutionAudit, ExecutionAuditReceipt,
       with_execution_audit, execution_receipts

"""
    ConfigurationOptionMeta(option_type, default, meaning; ...)

Structured metadata for a public configuration option. `consumer` names the
runtime boundary that must apply the resolved value; `supported_backends` and
`dependencies` explain when the option can be active.
"""
struct ConfigurationOptionMeta
    option_type::Any
    default::Any
    meaning::String
    category::Symbol
    supported_backends::Tuple
    dependencies::Tuple{Vararg{Symbol}}
    consumer::Symbol
end

ConfigurationOptionMeta(option_type, default, meaning;
                        category=:execution,
                        supported_backends=(),
                        dependencies=(),
                        consumer=:unspecified) =
    ConfigurationOptionMeta(option_type, default, String(meaning), Symbol(category),
                            Tuple(supported_backends), Tuple(Symbol.(dependencies)),
                            Symbol(consumer))

"""
    CONFIGURATION_STATUSES

Every status a [`ConfigurationEntry`](@ref) may carry.

  * `:resolved` -- the requested value is in force.
  * `:unresolved` -- still awaiting runtime information.
  * `:inherited` -- taken from an enclosing object rather than set here.
  * `:deprecated` -- honoured, but the option is on its way out.
  * `:inactive_backend` -- meaningless on the backend in use.
  * `:inactive_dependency` -- meaningless given another option's value.

Pinned against the source in the suite (2026-08-05_b audit, U12-12).
"""
const CONFIGURATION_STATUSES = (:resolved, :unresolved, :inherited, :deprecated,
                                :inactive_backend, :inactive_dependency)

"""One requested/resolved configuration value and its effectiveness status."""
struct ConfigurationEntry
    name::Symbol
    requested::Any
    resolved::Any
    status::Symbol
    reason::String
    consumer::Symbol
end

"""A receipt emitted at an actual execution consumer boundary."""
struct ExecutionAuditReceipt
    consumer::Symbol
    backend::Any
    values::NamedTuple
end

"""
    ExecutionAudit()

Opt-in collection of configuration-effectiveness receipts. Normal execution
does not allocate receipts and does not synchronize merely for auditing.
"""
mutable struct ExecutionAudit
    receipts::Vector{ExecutionAuditReceipt}
    # `_record_execution!` is reached from inside worker tasks: the CPU PIC pair
    # loop runs batches of slice pairs concurrently and each pair's per-particle
    # maps call `_run_logical_workers` again, which records. Two tasks pushing
    # to one Vector is a corrupted vector, not a reordered one, so the push is
    # locked. Auditing is opt-in, so uninstrumented runs never take this lock --
    # `_record_execution!` returns on the `audit === nothing` check first.
    lock::ReentrantLock
end
ExecutionAudit(receipts::Vector{ExecutionAuditReceipt}) =
    ExecutionAudit(receipts, ReentrantLock())
ExecutionAudit() = ExecutionAudit(ExecutionAuditReceipt[])

const _ACTIVE_EXECUTION_AUDIT = Base.ScopedValues.ScopedValue{Any}(nothing)
const _ACTIVE_RESOLVED_POLICY = Base.ScopedValues.ScopedValue{Any}(nothing)

"""
    execution_receipts(audit) -> Vector

The receipts recorded inside a `with_execution_audit` block: one entry per
consumer-boundary `_record_execution!`, which is how the effectiveness
contracts prove a configuration value was READ rather than merely stored.
"""
function execution_receipts(audit::ExecutionAudit)
    lock(audit.lock)
    try
        return copy(audit.receipts)
    finally
        unlock(audit.lock)
    end
end

"""Run `f()` while recording actual configuration consumers into `audit`."""
function with_execution_audit(f::F, audit::ExecutionAudit=ExecutionAudit()) where {F}
    Base.ScopedValues.with(_ACTIVE_EXECUTION_AUDIT => audit) do
        f()
    end
    return audit
end

function _record_execution!(consumer::Symbol, backend, values::NamedTuple)
    audit = _ACTIVE_EXECUTION_AUDIT[]
    audit === nothing && return nothing
    receipt = ExecutionAuditReceipt(consumer, backend, values)
    lock(audit.lock)
    try
        push!(audit.receipts, receipt)
    finally
        unlock(audit.lock)
    end
    return nothing
end

function _with_resolved_policy(f::F, policy) where {F}
    return Base.ScopedValues.with(_ACTIVE_RESOLVED_POLICY => policy) do
        f()
    end
end

"""
    PlaceholderPolicy()

Placeholder execution policy used for examples and metadata until a real
execution choice is required. It intentionally does not imply slicing,
accuracy, MPI, or backend behavior.
"""
struct PlaceholderPolicy <: AbstractExecutionPolicy end

"""
    CPUThreadsExecutionPolicy(; threads=:auto)

Run with a fixed number of Octopus logical workers in Julia's default thread
pool. `:auto` resolves to `Threads.nthreads(:default)`. An integer must be in
`1:Threads.nthreads(:default)`; values are rejected rather than clamped.

Logical workers are work partitions/tasks. Julia's scheduler decides which OS
threads execute them, so this policy does not promise thread pinning.
"""
struct CPUThreadsExecutionPolicy <: AbstractExecutionPolicy
    threads::Union{Int,Symbol}
    function CPUThreadsExecutionPolicy(threads::Union{Integer,Symbol})
        if threads isa Symbol
            threads === :auto || throw(ArgumentError(
                "CPU threads must be :auto or an integer; got $(repr(threads))."))
            return new(:auto)
        end
        n = Int(threads)
        max_threads = Threads.nthreads(:default)
        1 <= n <= max_threads || throw(ArgumentError(
            "CPU threads must be in 1:$(max_threads); got $(n)."))
        return new(n)
    end
end
CPUThreadsExecutionPolicy(; threads=:auto) = CPUThreadsExecutionPolicy(threads)

"""
What a `MultiProcessExecutionPolicy` asked for, before any communicator has
been consulted. Resolution is PURE: it may not initialise MPI, because
`configuration_report` resolves a policy just to describe it, and the
strong-strong task resolves once per beam.
"""
struct MultiProcessRequest
    ranks::Union{Int,Symbol}
end

"""
What the run actually got: the communicator (`nothing` in the serial
passthrough), the rank count and this process's rank READ FROM IT at
activation, the request they are checked against, and which branch produced
them. Built by `_activate_resolved_policy!`, never by resolution -- the rank
count a receipt reports must be the communicator's, not the policy's field
(the "a configuration you set is not a configuration the code read"
invariant).
"""
struct MultiProcessContext
    comm::Any
    nranks::Int
    rank::Int
    ranks::Union{Int,Symbol}
    resolved_by::Symbol
end

"""
    MultiProcessExecutionPolicy(; threads=:auto, ranks=:auto)

Run one Octopus process per MPI rank, each with its own CPU logical workers.
The per-rank core is `CPUThreadsExecutionPolicy(threads)` unchanged, so at one
rank this policy is that policy: same partitions, same folds, same results,
bit for bit.

`ranks` is `:auto` (accept whatever the launcher started) or an integer the
run must match exactly; a communicator of another size is rejected rather
than silently accepted. Without `MPI` loaded the process is its own
communicator of one, so `ranks = 1` is accepted and any larger integer is
not: the collective seam runs its serial passthrough and `nranks` is 1.

A `TrackingTask` and a soft-Gaussian `StrongStrongTask` run divided across
the ranks (multi-process steps 3a-3c and 4a-4b; the design and the
per-step records are in `docs/design/multi_process_policy.md`). What still
refuses at more than one rank, naming what is missing: task and line
ACTIONS and observers on a `PredicateSchedule` (callbacks Octopus cannot
reason about), `:equal_count` slicing (a global sort), and the PIC,
Gaussian-PIC and spectral solvers (step 4c onward). CPU storage only.
"""
struct MultiProcessExecutionPolicy <: AbstractExecutionPolicy
    threads::Union{Int,Symbol}
    ranks::Union{Int,Symbol}
    function MultiProcessExecutionPolicy(threads::Union{Integer,Symbol},
                                         ranks::Union{Integer,Symbol})
        # The composed CPU policy validates `threads` with its own message, so
        # there is one rule for thread counts and one place that states it.
        cpu = CPUThreadsExecutionPolicy(threads)
        if ranks isa Symbol
            ranks === :auto || throw(ArgumentError(
                "ranks must be :auto or a positive integer; got $(repr(ranks))."))
            return new(cpu.threads, :auto)
        end
        n = Int(ranks)
        n >= 1 || throw(ArgumentError("ranks must be a positive integer; got $(n)."))
        return new(cpu.threads, n)
    end
end
MultiProcessExecutionPolicy(; threads=:auto, ranks=:auto) =
    MultiProcessExecutionPolicy(threads, ranks)

"""The CPU policy a `MultiProcessExecutionPolicy` runs inside each rank."""
_composed_cpu_policy(policy::MultiProcessExecutionPolicy) =
    CPUThreadsExecutionPolicy(policy.threads)

"""
Root of GPU execution policies (`CUDAExecutionPolicy` and the legacy
`GPUExecutionPolicy`), so GPU-generic code can dispatch on the family
without naming a vendor. (Docstring added by the 2026-08-05 audit; this and
`ElementParameterEffectivenessContract` were the two public registry
objects without one since part 1 of the prior audit.)
"""
abstract type AbstractGPUExecutionPolicy <: AbstractExecutionPolicy end

"""
    CUDALaunchConfig(; threads=256, blocks=:auto)

Launch geometry for fused CUDA tracking. `blocks=:auto` uses occupancy and
particle coverage; a positive integer preserves an explicit tuning choice.
"""
struct CUDALaunchConfig
    threads::Int
    blocks::Union{Int,Symbol}
    function CUDALaunchConfig(threads::Integer, blocks::Union{Integer,Symbol})
        nt = Int(threads)
        nt > 0 || throw(ArgumentError("CUDA threads must be positive; got $(nt)."))
        if blocks isa Symbol
            blocks === :auto || throw(ArgumentError(
                "CUDA blocks must be :auto or a positive integer; got $(repr(blocks))."))
            return new(nt, :auto)
        end
        nb = Int(blocks)
        nb > 0 || throw(ArgumentError("CUDA blocks must be positive; got $(nb)."))
        return new(nt, nb)
    end
end
CUDALaunchConfig(; threads::Integer=256, blocks=:auto) =
    CUDALaunchConfig(threads, blocks)

"""
    CUDAExecutionPolicy(; device=nothing, launch=CUDALaunchConfig())

Execution policy for CUDA storage. `device=nothing` resolves from particle
storage when tracking and keeps the current CUDA device only while allocating a
new `Beam`. CUDA-specific launch choices live in `CUDALaunchConfig`.
"""
struct CUDAExecutionPolicy <: AbstractGPUExecutionPolicy
    device::Union{Nothing,Int}
    launch::CUDALaunchConfig
    function CUDAExecutionPolicy(device, launch::CUDALaunchConfig)
        dev = device === nothing ? nothing : Int(device)
        dev === nothing || dev >= 0 || throw(ArgumentError(
            "CUDA device must be a nonnegative index or nothing; got $(repr(device))."))
        return new(dev, launch)
    end
end
CUDAExecutionPolicy(; device=nothing, launch::CUDALaunchConfig=CUDALaunchConfig()) =
    CUDAExecutionPolicy(device, launch)

"""
    GPUExecutionPolicy(; threads=256, blocks=256, device=nothing)

Deprecated compatibility policy for the historical CUDA-only `GPU` name. New
code should use `CUDAExecutionPolicy(launch=CUDALaunchConfig(...))`.
"""
struct GPUExecutionPolicy <: AbstractGPUExecutionPolicy
    threads::Int
    blocks::Int
    device::Union{Nothing,Int}
    function GPUExecutionPolicy(threads::Integer, blocks::Integer, device)
        Base.depwarn(
            "GPUExecutionPolicy is deprecated; use CUDAExecutionPolicy with CUDALaunchConfig.",
            :GPUExecutionPolicy,
        )
        launch = CUDALaunchConfig(threads, blocks)
        dev = device === nothing ? nothing : Int(device)
        dev === nothing || dev >= 0 || throw(ArgumentError(
            "CUDA device must be a nonnegative index or nothing; got $(repr(device))."))
        return new(launch.threads, launch.blocks, dev)
    end
end
GPUExecutionPolicy(threads::Integer, blocks::Integer) =
    GPUExecutionPolicy(threads, blocks, nothing)
GPUExecutionPolicy(; threads::Integer=256, blocks::Integer=256, device=nothing) =
    GPUExecutionPolicy(threads, blocks, device)

abstract type AbstractResolvedExecutionPolicy end

"""
A resolved CPU execution policy: the logical-worker count, plus the
multi-process state when the run was launched through a
`MultiProcessExecutionPolicy`.

The multi-process state is a SLOT on the CPU policy rather than a wrapper
type around it, deliberately. Eight methods and `_cpu_worker_count()`
dispatch on this concrete type, and the public `track!`, `Beam`, task and
`configuration_report` paths all pass a resolved policy positionally; a
wrapper would have to be unwrapped at each of them, and one missed site is a
`MethodError` for the public entry (or, worse, a silently different code
path). With a slot, a one-rank run IS today's run, by construction rather
than by argument. `nothing` is the ordinary single-process case; a
`MultiProcessRequest` is what resolution produces; a `MultiProcessContext` is
what activation puts back.
"""
struct ResolvedCPUExecutionPolicy <: AbstractResolvedExecutionPolicy
    threads::Int
    multi_process::Union{Nothing,MultiProcessRequest,MultiProcessContext}
end
ResolvedCPUExecutionPolicy(threads::Integer) =
    ResolvedCPUExecutionPolicy(Int(threads), nothing)
struct ResolvedCUDAExecutionPolicy <: AbstractResolvedExecutionPolicy
    device::Int
    threads::Int
    blocks::Union{Int,Symbol}
end

"""
    backend_type(policy) -> Type{<:AbstractExecutionBackend}

The backend TAG a policy executes on — the bridge from the HOW (policy) to
the WHERE (backend dispatch).
"""
backend_type(::CPUThreadsExecutionPolicy) = CPUThreadsBackend
backend_type(::MultiProcessExecutionPolicy) = CPUThreadsBackend
# ONE method on the family, not one per vendor policy. `AbstractGPUExecutionPolicy`
# was a taxonomy node whose docstring said it exists "so GPU-generic code can
# dispatch on the family without naming a vendor", and no method in the
# repository dispatched on it -- a published abstraction documenting a
# capability the code did not have (2026-08-05_b audit, U12-15). This is that
# capability, and it is not invented for the occasion: `CUDAExecutionPolicy` and
# the deprecated `GPUExecutionPolicy` had identical bodies here. A second vendor
# policy would inherit it.
backend_type(::AbstractGPUExecutionPolicy) = CUDABackend
backend_type(::ResolvedCPUExecutionPolicy) = CPUThreadsBackend
backend_type(::ResolvedCUDAExecutionPolicy) = CUDABackend
backend_type(::PlaceholderPolicy) = error(
    "PlaceholderPolicy has no execution backend. Use CPUThreadsExecutionPolicy or CUDAExecutionPolicy to execute a task.")

_resolved_cpu_threads(policy::CPUThreadsExecutionPolicy) =
    policy.threads === :auto ? Threads.nthreads(:default) : policy.threads

function _cpu_worker_count()
    policy = _ACTIVE_RESOLVED_POLICY[]
    return policy isa ResolvedCPUExecutionPolicy ? policy.threads : Threads.nthreads(:default)
end

"""
Tag the MPI extension dispatches on.

Core defines the fallback on `::Any`, the extension the method on this exact
type, so the extension ADDS a method instead of overwriting one -- an
extension that redefines a method its parent already defined for the same
signature fails to precompile.
"""
struct MPIBackendTag end

"""
The communicator the MPI extension offers, or `nothing` when it is not
loaded. `OctopusMPIExt` defines the `::MPIBackendTag` method; this fallback
is what a process without `MPI` sees.
"""
_mp_open_communicator(::Any) = nothing

"""Size of and this process's rank in a communicator; the extension owns both."""
_mp_communicator_size(comm) = error("no method to size $(typeof(comm)); OctopusMPIExt supplies it")
_mp_communicator_rank(comm) = error("no method to rank $(typeof(comm)); OctopusMPIExt supplies it")

"""
The rank count the LAUNCHER announces, or `nothing` when no launcher
variable is set.

`mpiexec -n 4 julia ...` with `MPI` never loaded would otherwise give four
processes that each believe they are a communicator of one, run the whole job,
and write the same output file over each other -- silently, four times. Every
launcher exports its size; a disagreement with the communicator Octopus
actually has is a defect, so it throws.
"""
function _launcher_rank_count()
    for name in ("PMI_SIZE", "OMPI_COMM_WORLD_SIZE", "MPI_LOCALNRANKS",
                 "PMIX_SIZE", "MV2_COMM_WORLD_SIZE", "SLURM_NTASKS")
        value = get(ENV, name, nothing)
        value === nothing && continue
        parsed = tryparse(Int, value)
        parsed === nothing && continue
        return (name, parsed)
    end
    return nothing
end

"""
The multi-process state of the policy in force, or `nothing` outside a
multi-process run. After activation this is a [`MultiProcessContext`](@ref).
"""
function _multi_process_state()
    policy = _ACTIVE_RESOLVED_POLICY[]
    policy isa ResolvedCPUExecutionPolicy || return nothing
    return policy.multi_process
end

function _multi_process_context()
    state = _multi_process_state()
    return state isa MultiProcessContext ? state : nothing
end

"""The communicator in force, or `nothing` in the serial passthrough."""
function _mp_comm()
    context = _multi_process_context()
    return context === nothing ? nothing : context.comm
end

"""Whether the active policy is a multi-process one, at ANY rank count --
one rank included, where the collectives are their passthroughs and the
messages are to oneself. The slice-aligned collide (step 4d) runs on it."""
function _mp_multi_process_active()
    policy = _ACTIVE_RESOLVED_POLICY[]
    return policy isa ResolvedCPUExecutionPolicy && policy.multi_process !== nothing
end

"""
    _mp_nranks() -> Int
    _mp_rank() -> Int

The size of the communicator in force and this process's rank in it: `1` and
`0` outside a multi-process run, and `1` and `0` in the serial passthrough.
"""
_mp_nranks() = (context = _multi_process_context(); context === nothing ? 1 : context.nranks)
_mp_rank() = (context = _multi_process_context(); context === nothing ? 0 : context.rank)

"""Whether this rank owns the run's single-writer output (rank 0, always)."""
_mp_is_root() = _mp_rank() == 0

"""
    _mp_collective_times() -> Dict{Symbol,Tuple{Int,Int}} or nothing

Per kind of collective, `(calls, nanoseconds)` spent inside the extension's
MPI calls since the last `_mp_reset_collective_times!()`: the number that
says what division costs, which the receipts (a count and a size per call)
cannot. `nothing` in the passthrough, where nothing is communicated. Rank
local; the benchmark prints rank 0's.
"""
_mp_collective_times() = _mp_collective_times_impl(MPIBackendTag())
_mp_reset_collective_times!() = _mp_reset_collective_times_impl!(MPIBackendTag())
# `::Any`, so the extension's `::MPIBackendTag` methods ADD rather than
# overwrite (an overwrite is refused at precompilation).
_mp_collective_times_impl(::Any) = nothing
_mp_reset_collective_times_impl!(::Any) = nothing

function _record_collective!(kind::Symbol, count::Integer, bytes::Integer)
    # MPI is initialised at `:funneled`: only the main thread may issue a
    # collective. Every seam function records BEFORE it communicates, so this
    # is the one tripwire the design promised (step 4b lands it): a collective
    # reached from a worker task throws a named error instead of corrupting
    # the communicator or hanging. Nothing to check at one rank, where every
    # collective is its passthrough.
    _mp_nranks() > 1 && Threads.threadid() != 1 && throw(ArgumentError(
        "a multi-process collective ($(kind)) was issued from thread " *
        "$(Threads.threadid()); MPI runs at :funneled and Octopus issues " *
        "collectives from the task driver on the main thread only, never from " *
        "inside _run_logical_workers."))
    # The `audit === nothing` check inside `_record_execution!` runs before
    # anything is built, and this NamedTuple is small and concrete, so an
    # unaudited collective pays a load and a branch.
    _record_execution!(:multi_process_collective, CPUThreadsBackend,
                       (kind=kind, count=Int(count), bytes=Int(bytes),
                        nranks=_mp_nranks()))
    return nothing
end

# --- the collective seam -----------------------------------------------------
#
# Six operations, each with a serial passthrough in core and an MPI method in
# the extension, dispatching on the communicator so the two never collide.
# Every floating-point reduction is an ALLGATHER FOLLOWED BY A FOLD IN RANK
# ORDER, never `MPI_SUM`: a library sum may associate as it likes and by rank
# count, which would make a result depend on how many processes computed it.
# Rank-ordered folding gives every rank the same bits, and the same bits a
# different rank count would give when the shard boundaries align with the
# fold's own partition (`docs/design/multi_process_policy.md`).

"""
    _mp_allsum!(A) -> A

Sum `A` elementwise across the communicator, in rank order, leaving the total
in `A` on every rank. The passthrough returns `A` untouched.
"""
function _mp_allsum!(A::AbstractArray)
    _record_collective!(:allsum, length(A), length(A) * sizeof(eltype(A)))
    return _mp_allsum_impl!(A, _mp_comm())
end
_mp_allsum_impl!(A, ::Nothing) = A

"""
    _mp_lane_fold!(lanes) -> lanes

The lane-partial form of [`_mp_allsum!`](@ref): each rank holds the partials of
the lanes it owns, and every rank leaves with the whole lane vector. Named
apart from `_mp_allsum!` because the shard contract differs -- lanes are
block-cyclic, grids are elementwise -- even though the passthrough and the
collective are the same operation today.
"""
function _mp_lane_fold!(lanes::AbstractVector)
    _record_collective!(:lane_fold, length(lanes), sizeof(lanes))
    return _mp_allsum_impl!(lanes, _mp_comm())
end

"""
    _mp_allminmax(lo, hi) -> (lo, hi)

The global minimum of `lo` and maximum of `hi`. Order-independent (min and max
associate freely), so this one needs no rank-ordered fold -- which is why mesh
and box sizing can use it without a determinism argument.

A NaN is NOT a signal here. The extension maps these to `MPI_MIN`/`MPI_MAX`,
whose result with a NaN input is rank-divergent (measured under MPICH at two
ranks: the rank holding the NaN received it back, its peer received the finite
value; at four ranks the finite values themselves differed by rank), so a rank
that read a bound to decide whether to throw would leave its peers waiting at
the next collective. A non-finite verdict is taken on LOCAL data, agreed as an
integer count (`_mp_global_count`), and thrown on every rank before any
exchanged bound is consumed -- `_pic_interaction!`, `_pic_build_node_grids!`
and `_pic_union_bounds` all follow that order. Same for `_mp_allmin!` and
`_mp_allmax!`.
"""
function _mp_allminmax(lo::Real, hi::Real)
    _record_collective!(:allminmax, 2, 2 * sizeof(lo))
    return _mp_allminmax_impl(lo, hi, _mp_comm())
end
_mp_allminmax_impl(lo, hi, ::Nothing) = (lo, hi)

"""
    _mp_allmin!(A) -> A
    _mp_allmax!(A) -> A

Element-wise global minimum (maximum) of `A` across the ranks, in place. The
vector form of `_mp_allminmax`, for the mesh sizing that reduces many
extrema at once (a node mesh holds one box per slice boundary); the same
free association makes both a plain all-reduce. Multi-process step 4c.
"""
function _mp_allmin!(A::AbstractArray)
    _record_collective!(:allmin, length(A), length(A) * sizeof(eltype(A)))
    return _mp_allmin_impl!(A, _mp_comm())
end
_mp_allmin_impl!(A, ::Nothing) = A
function _mp_allmax!(A::AbstractArray)
    _record_collective!(:allmax, length(A), length(A) * sizeof(eltype(A)))
    return _mp_allmax_impl!(A, _mp_comm())
end
_mp_allmax_impl!(A, ::Nothing) = A

"""
    _mp_bcast!(A, root=0) -> A

Replace `A` with rank `root`'s copy on every rank.
"""
function _mp_bcast!(A::AbstractArray, root::Integer=0)
    _record_collective!(:bcast, length(A), sizeof(A))
    return _mp_bcast_impl!(A, Int(root), _mp_comm())
end
_mp_bcast_impl!(A, root, ::Nothing) = A

"""
    _mp_bcast(value, root=0)

Scalar [`_mp_bcast!`](@ref): every rank leaves with rank `root`'s `value`. Used
for decisions that must not diverge (a schedule predicate, a slicing choice):
a rank that decides differently from the others deadlocks the next collective.
"""
function _mp_bcast(value, root::Integer=0)
    _record_collective!(:bcast_scalar, 1, sizeof(value))
    return _mp_bcast_scalar_impl(value, Int(root), _mp_comm())
end
_mp_bcast_scalar_impl(value, root, ::Nothing) = value

# --- the rank shard ----------------------------------------------------------
#
# A tracking task is per-particle work: every element whose map is a function
# of one particle needs no communication at all to be divided. Only two things
# in a line reduce across particles -- a strong beam's luminosity and an
# aperture's loss records -- so the shard rule is chosen by what those
# reductions need, not by the tracking.

"""
    _mp_shard_range(global_n, nranks, rank) -> UnitRange

The global particle indices rank `rank` owns.

The rule is: a contiguous run of WHOLE reduction chunks. Every count-invariant
float fold in the CPU stack partitions the beam into `_REDUCTION_CHUNKS` fixed
chunks and sums the partials in chunk order, and that order is what makes a
result independent of the worker count. Give each rank whole chunks and the
same property extends across processes for free: the ranks' partials, gathered
and folded in chunk order, are the single-process sum bit for bit. Give them
anything else and the fold has to be rearranged, which moves last bits for no
physical reason.

The price is that the rank count must divide `_REDUCTION_CHUNKS`. That is a
real restriction and it is enforced rather than worked around: a rank count
that would silently cost bitwise reproducibility is rejected.
"""
function _mp_shard_range(global_n::Integer, nranks::Integer, rank::Integer)
    chunks = _REDUCTION_CHUNKS
    per_rank, leftover = divrem(chunks, Int(nranks))
    leftover == 0 || throw(ArgumentError(
        "$(nranks) ranks cannot divide the $(chunks) fixed reduction chunks " *
        "evenly, so no shard of the beam is chunk-aligned and a cross-rank " *
        "fold could not reproduce the single-process sum bit for bit. Use a " *
        "rank count that divides $(chunks): " *
        join((p for p in 1:chunks if chunks % p == 0), ", ") * "."))
    lo = _chunk_bounds(Int(global_n), chunks, Int(rank) * per_rank + 1)[1]
    hi = _chunk_bounds(Int(global_n), chunks, (Int(rank) + 1) * per_rank)[2]
    return lo:hi
end

"""
    _mp_resolve_shard(local_n) -> (offset, global_n)

Derive this rank's place in the global beam from the counts the ranks actually
hold, and VERIFY that the local count is the one the shard rule prescribes.

Derived rather than stored: nothing in the particle representation records
which slice of a larger beam it is, and a field that said so could disagree
with the array beside it. Summing the counts and re-deriving the rule cannot
disagree with itself, and a beam that was built or split some other way fails
here, loudly, instead of tracking with the wrong RNG streams and reducing into
the wrong chunk slots.

Issues one integer collective, so every rank must reach it -- it belongs at a
run's entry, not inside a per-turn loop.
"""
function _mp_resolve_shard(local_n::Integer)
    context = _multi_process_context()
    (context === nothing || context.nranks == 1) && return (0, Int(local_n))
    counts = zeros(Int, context.nranks)
    counts[context.rank + 1] = Int(local_n)
    _mp_allsum!(counts)
    global_n = sum(counts)
    expected = _mp_shard_range(global_n, context.nranks, context.rank)
    length(expected) == Int(local_n) || throw(ArgumentError(
        "rank $(context.rank) of $(context.nranks) holds $(local_n) particles, " *
        "but the chunk-aligned shard of a $(global_n)-particle beam gives it " *
        "$(length(expected)) (global indices $(expected)). Build the beam with " *
        "`Beam(n_global, MultiProcessExecutionPolicy(...), ...)`, which shards " *
        "it by this rule, or split it yourself on the same boundaries."))
    return (first(expected) - 1, global_n)
end

"""
    _masked_global_sum(term, islive, local_n) -> Float64

Sum `term(k)` over the live local particles, then across the ranks in rank
order.

The local half is the SAME left-to-right accumulation it has always been, so
at one rank this is byte for byte the number the undivided run produced and
no recorded moment moves.

That is a deliberate trade, and it is the answer to the question the ledger
left open. The alternative was to fold these reductions on the fixed chunk
grid, which would make a divided beam's moments the undivided beam's moments
bit for bit -- but a chunk grid partitions the SLOTS, and a masked beam has
more slots than survivors, so the grid over a beam with dead particles is not
the grid over the survivors alone. Measured: adopting it broke "a lost
particle is excluded from every reduction, exactly" -- the masked row stopped
equalling the survivors-only row in the last bits -- and moved recorded means
by up to 206 ulps at the production size. The masking invariant is worth more
than cross-rank bitwise agreement here, and the campaign's own posture already
prices cross-rank agreement at the parity tolerance class rather than at the
bit (`docs/design/multi_process_policy.md`).

So: bit-repeatable at a fixed rank count, and agreeing with an undivided run
to the accumulation difference between one serial sum and P of them -- of
order `eps` times the particle count, measured at 1e-14 relative for a
1,024,000-particle beam.
"""
function _masked_global_sum(term::F, islive::L, local_n::Integer) where {F,L}
    s = 0.0
    @inbounds for k in 1:Int(local_n)
        islive(k) && (s += term(k))
    end
    _mp_nranks() == 1 && return s
    partial = [s]
    _mp_allsum!(partial)
    return partial[1]
end

"""
    _mp_global_sum(value) -> value

One scalar summed across the ranks, in rank order. The passthrough returns it
unchanged, so a single-process run does no arithmetic it did not do before.
"""
function _mp_global_sum(value::T) where {T<:Real}
    _mp_nranks() == 1 && return value
    packed = T[value]
    _mp_allsum!(packed)
    return packed[1]
end

"""
    _mp_global_count(n) -> Int

The whole beam's count of something each rank counted for its own shard.
Integer, so the cross-rank sum is exact whatever order it takes.
"""
function _mp_global_count(n::Integer)
    _mp_nranks() == 1 && return Int(n)
    counts = [Int(n)]
    _mp_allsum!(counts)
    return counts[1]
end

"""
    _masked_global_count(islive, local_n) -> Int

How many live particles the WHOLE beam has. Integer, so the cross-rank sum is
exact whatever order it takes.
"""
function _masked_global_count(islive::L, local_n::Integer) where {L}
    n = 0
    @inbounds for k in 1:Int(local_n)
        islive(k) && (n += 1)
    end
    _mp_nranks() == 1 && return n
    counts = [n]
    _mp_allsum!(counts)
    return counts[1]
end

"""
One beam's place in a divided run: the identity of its representation, the
particle count this rank holds of it, and the `(offset, global_n)` the shard
rule gives that count.

Keyed by the REPRESENTATION, not by the count (multi-process step 4b). A
strong-strong task holds two beams of different sizes, and a scope that
stored one `(offset, global_n)` handed the second beam the first beam's
offset. Keying by local count instead is ambiguous in principle -- two beams
of 256 and 257 particles give rank 1 of 2 the same 128-particle shard with
different offsets -- so the key is the object every consumer already has in
hand. `Beam` is immutable and tracking mutates its arrays in place, so a
beam's `rep` is the same object for the whole run.
"""
struct _ShardEntry
    rep::Any            # matched by `===`: exact, no hash, and it keeps the rep alive
    local_n::Int
    offset::Int
    global_n::Int
end

"""
This run's shards, one entry per beam, set once at a run's entry so the
per-turn folds inside it need no collective of their own. `nothing` outside
a run.
"""
const _ACTIVE_SHARD = Base.ScopedValues.ScopedValue{Any}(nothing)

_shard_entry(rep, shard::Tuple) =
    _ShardEntry(rep, length(rep), Int(shard[1]), Int(shard[2]))

"""Whether `rep` already has a shard in scope."""
function _mp_shard_scoped(rep)
    entries = _ACTIVE_SHARD[]
    entries === nothing && return false
    return any(e -> e.rep === rep, entries)
end

"""
    _with_shards(f, entries)

Run `f` with these `_ShardEntry`s in scope; the ones the enclosing scope
already held stay visible, so a nested run of another beam does not hide the
outer beam's shard.
"""
function _with_shards(f::F, entries::Tuple{Vararg{_ShardEntry}}) where {F}
    outer = _ACTIVE_SHARD[]
    combined = outer === nothing ? entries : (entries..., outer...)
    return Base.ScopedValues.with(f, _ACTIVE_SHARD => combined)
end

"""
    _with_shard(f, rep, shard)

Run `f` with `rep`'s `(offset, global_n)` in scope.
"""
_with_shard(f::F, rep, shard::Tuple) where {F} = _with_shards(f, (_shard_entry(rep, shard),))

"""
    _with_beam_shards(f, reps...)

Resolve every beam's shard that is not already in scope -- one integer
collective each, in the order given, which every rank must therefore call in
the same order -- and run `f` with all of them in scope. The entry point of
any run that holds more than one beam; a bare `collide!` enters it too, so a
consumer inside never resolves a shard of its own, and a collide reached
through a task that already scoped its beams pays nothing here.
"""
function _with_beam_shards(f::F, reps...) where {F}
    fresh = Tuple(rep for rep in reps if !_mp_shard_scoped(rep))
    entries = Tuple(_shard_entry(rep, _mp_resolve_shard(length(rep))) for rep in fresh)
    return _with_shards(f, entries)
end

"""
    _mp_current_shard(rep) -> (offset, global_n)

The shard in force for this representation, matched by identity. Outside any
run (no scope) the shard is resolved -- one collective, symmetric because
every rank is equally outside. Inside a run, a representation the run did
not scope is an ERROR at more than one rank rather than a resolve: a resolve
here would be a collective hidden inside a per-slice or per-turn function,
and the design puts every shard resolution at a run's entry. At one rank it
is simply the whole beam. Every decision below is a function of the scope,
which every rank holds alike, so no branch can strand a peer.
"""
function _mp_current_shard(rep::AbstractPhaseRep)
    entries = _ACTIVE_SHARD[]
    entries === nothing && return _mp_resolve_shard(length(rep))
    for e in entries
        e.rep === rep || continue
        e.local_n == length(rep) || throw(ArgumentError(
            "the representation in scope held $(e.local_n) particles when its " *
            "shard was resolved and holds $(length(rep)) now; a beam does not " *
            "change size inside a run."))
        return (e.offset, e.global_n)
    end
    _mp_nranks() == 1 && return (0, Int(length(rep)))
    throw(ArgumentError(
        "this representation has no shard in scope on the $(_mp_nranks()) ranks " *
        "in force: enter the run through execute!, collide!, or " *
        "_with_beam_shards, which resolve every beam's shard at the entry."))
end

"""
    _mp_current_shard(local_n) -> (offset, global_n)

The count-keyed form, for a caller that holds a coordinate array and not the
representation it belongs to. Every decision is made from facts every rank
shares -- the scope's entries and their GLOBAL sizes -- never from this
rank's own counts, because a rule keyed on local counts throws on the ranks
where two beams' shards happen to coincide and proceeds on the others, which
is a deadlock at the next collective. So: no scope, resolve; scoped beams of
one global size, that shard (they all have the same one on this rank);
scoped beams of several sizes, throw on every rank -- pass the
representation instead.
"""
function _mp_current_shard(local_n::Integer)
    entries = _ACTIVE_SHARD[]
    entries === nothing && return _mp_resolve_shard(local_n)
    sizes = unique(e.global_n for e in entries)
    length(sizes) == 1 || throw(ArgumentError(
        "$(length(sizes)) beams of different sizes ($(join(sort(sizes), ", ")) " *
        "particles) are in scope; a count cannot say which is meant -- call " *
        "_mp_current_shard with the beam's representation."))
    e = entries[1]
    e.local_n == Int(local_n) && return (e.offset, e.global_n)
    _mp_nranks() == 1 && return (0, Int(local_n))
    throw(ArgumentError(
        "a count of $(local_n) is not the scoped beam's $(e.local_n) particles " *
        "on this rank; call _mp_current_shard with the beam's representation."))
end

"""
    _mp_chunk_fold(partials, offset_chunk, nchunks_local) -> value

Fold this rank's chunk partials into the global chunk-ordered sum.

The single-process fold is `sum(partials)` over `_REDUCTION_CHUNKS` entries in
chunk order. Across ranks each rank holds a contiguous run of those entries, so
scattering them into their global slots, one all-sum, and the same ordered sum
reproduces it exactly. The all-sum is over `_REDUCTION_CHUNKS` numbers, once
per fold, whatever the beam size.
"""
function _mp_chunk_fold(partials::AbstractVector{T}, first_chunk::Integer) where {T}
    context = _multi_process_context()
    (context === nothing || context.nranks == 1) && return sum(partials)
    global_partials = zeros(T, _REDUCTION_CHUNKS)
    @inbounds for (j, value) in enumerate(partials)
        global_partials[Int(first_chunk) + j - 1] = value
    end
    _mp_allsum!(global_partials)
    return sum(global_partials)
end

"""The first global reduction chunk this rank owns (1 outside a sharded run)."""
function _mp_first_chunk()
    context = _multi_process_context()
    (context === nothing || context.nranks == 1) && return 1
    return context.rank * div(_REDUCTION_CHUNKS, context.nranks) + 1
end

"""The number of reduction chunks this rank owns."""
function _mp_local_chunks()
    context = _multi_process_context()
    (context === nothing || context.nranks == 1) && return _REDUCTION_CHUNKS
    return div(_REDUCTION_CHUNKS, context.nranks)
end

"""
    _mp_gather_rows(rows) -> Matrix

Collect every rank's rows onto rank 0, in rank order, and return them there;
the other ranks get an empty matrix with the same columns.

The seventh collective, and the one that is not a reduction. Everything above
turns the beam into scalars, which is why the first six sufficed; per-particle
output cannot be reduced, only moved. Losses and coordinate snapshots are the
two consumers, and both are sparse in practice -- a loss row exists only for a
particle that died -- so the message is small even at the production size.

Rank order, so the rows arrive in the order the shards do, which is global
particle order. Rank 0 only, because rank 0 owns the file: gathering onto
every rank would multiply the traffic by the rank count to no purpose.
"""
function _mp_gather_rows(rows::AbstractMatrix)
    _record_collective!(:gather_rows, length(rows), sizeof(rows))
    return _mp_gather_rows_impl(rows, _mp_comm())
end
_mp_gather_rows_impl(rows::AbstractMatrix, ::Nothing) = rows

"""
    _mp_exchange_columns(cols::AbstractMatrix, dest::AbstractVector{<:Integer})
        -> (received::Matrix, from_counts::Vector{Int})

Column `j` of `cols` (a particle: its coordinates and whatever travels with
them) goes to rank `dest[j]` (0-based). Every rank receives the columns sent
to it in sender rank order and, within a sender, in the sender's column
order -- a deterministic layout -- and learns how many came from each rank.
Step 4d's migration, in and out of the slice-aligned collide. The
passthrough returns `cols` itself and `[size(cols, 2)]`.
"""
function _mp_exchange_columns(cols::AbstractMatrix, dest::AbstractVector{<:Integer})
    _record_collective!(:exchange_columns, length(cols), length(cols) * sizeof(eltype(cols)))
    return _mp_exchange_columns_impl(cols, dest, _mp_comm())
end
_mp_exchange_columns_impl(cols::AbstractMatrix, dest, ::Nothing) = (cols, Int[size(cols, 2)])

"""
    _mp_isend(A, dest, tag) -> request
    _mp_irecv!(A, source, tag) -> request
    _mp_wait_all(requests, stage)
    _mp_requests() -> an empty request list

Point-to-point messages for the slice-aligned collide (step 4d): posted from
the main thread between the stages of a batch (MPI runs at `:funneled`; the
same tripwire as the collectives'), `A` an `Array` or a contiguous view that
must stay untouched until `_mp_wait_all` returns, which also empties the
list. `tag` is the message's identity -- pair, stage, direction and plane --
so two messages between the same ranks never cross; `stage` names the wait
in the receipts and the extension's clocks (`:wait_extents`,
`:wait_deposits`, ...), because wait time per stage is the imbalance signal.

At one rank every message is to oneself: the passthrough keeps the sent copy
in a mailbox and delivers it into the matching receive at the wait, so the
sliced collide runs at one rank on the same code -- which is what lets the
one-rank bitwise pin touch it.
"""
function _mp_isend(A::AbstractArray, dest::Integer, tag::Integer)
    _record_collective!(:isend, length(A), length(A) * sizeof(eltype(A)))
    return _mp_isend_impl(A, Int(dest), Int(tag), _mp_comm())
end
function _mp_irecv!(A::AbstractArray, source::Integer, tag::Integer)
    _record_collective!(:irecv, length(A), length(A) * sizeof(eltype(A)))
    return _mp_irecv_impl!(A, Int(source), Int(tag), _mp_comm())
end
function _mp_wait_all(requests, stage::Symbol)
    _record_collective!(stage, length(requests), 0)
    _mp_wait_all_impl(requests, stage, _mp_comm())
    empty!(requests)
    return nothing
end
_mp_requests() = _mp_requests_impl(_mp_comm())

# The passthrough's self-delivery: sends keep a copy by tag, receives queue
# their buffers, the wait matches them. Main thread only, like every seam
# call; a tag sent twice before a wait, or received without a send, is a
# protocol error and says so.
const _MP_SELF_MAILBOX = Dict{Int,Any}()
const _MP_SELF_PENDING = Vector{Tuple{Int,Any}}()
function _mp_isend_impl(A, dest::Int, tag::Int, ::Nothing)
    dest == 0 || error("a one-rank run sent to rank $(dest)")
    haskey(_MP_SELF_MAILBOX, tag) && error("tag $(tag) sent twice before a wait")
    _MP_SELF_MAILBOX[tag] = copy(A)
    return nothing
end
function _mp_irecv_impl!(A, source::Int, tag::Int, ::Nothing)
    source == 0 || error("a one-rank run received from rank $(source)")
    push!(_MP_SELF_PENDING, (tag, A))
    return nothing
end
function _mp_wait_all_impl(requests, stage::Symbol, ::Nothing)
    for (tag, buf) in _MP_SELF_PENDING
        haskey(_MP_SELF_MAILBOX, tag) || error("no message tagged $(tag) was sent before the $(stage) wait")
        sent = pop!(_MP_SELF_MAILBOX, tag)
        length(sent) == length(buf) || error("message tagged $(tag): $(length(sent)) elements sent into a $(length(buf))-element receive")
        copyto!(buf, 1, sent, 1, length(sent))
    end
    empty!(_MP_SELF_PENDING)
    return nothing
end
_mp_requests_impl(::Nothing) = Any[]

"""    _mp_barrier()

Wait until every rank arrives. A no-op in the passthrough."""
function _mp_barrier()
    _record_collective!(:barrier, 0, 0)
    return _mp_barrier_impl(_mp_comm())
end
_mp_barrier_impl(::Nothing) = nothing

function _run_logical_workers(f::F, workers::Integer=_cpu_worker_count()) where {F}
    nworkers = Int(workers)
    nworkers > 0 || throw(ArgumentError("logical worker count must be positive"))
    _record_execution!(:cpu_logical_workers, CPUThreadsBackend,
                       (workers=nworkers, pool_threads=Threads.nthreads(:default)))
    if nworkers == 1
        f(1, 1)
        return nothing
    end
    if Threads.nthreads(:default) == 1
        # A pool of one cannot run two things at once, so spawning `nworkers`
        # tasks buys nothing and costs a spawn and a join each. Running them
        # inline IN WORKER ORDER writes exactly the same slots -- the callers
        # give each worker its own -- so the fold that follows is unchanged
        # and this is a pure removal of overhead. It matters because the
        # fixed chunk grids are 16 and 64 wide whatever the pool is: a
        # strong-strong collide issues about 900 of these per turn, which at
        # one thread was ~57,600 spawns for no parallelism, and one thread per
        # rank is the configuration that scales best under MPI
        # (docs/history/multi_process_strongstrong_scaling_2026_09_04.md).
        for worker in 1:nworkers
            f(worker, nworkers)
        end
        return nothing
    end
    try
        @sync for worker in 1:nworkers
            Threads.@spawn f(worker, nworkers)
        end
    catch err
        _rethrow_worker_failure(err)
    end
    return nothing
end

"""
    _rethrow_worker_failure(err)

Rethrow what a worker actually threw, not the wrapper `@sync` builds around it.

A fail-fast throw from inside a worker arrives as
`CompositeException([TaskFailedException(task), ...])`, so a caller matching on
`ArgumentError` sees neither the type nor the message. That matters here beyond
tidiness: every non-finite chokepoint in this repository throws an
`ArgumentError` whose message names the slice pair, the count and the first
offending particle, and tells the caller about `allow_lost_particles` — a
diagnostic that is worthless buried two exception layers down.

The rule this restores is that the same input fails the same way whether the
work ran serially or across workers. Which is exactly what a worker count is
not allowed to change: `nworkers == 1` takes the branch above and never wraps.

Only the FIRST cause is unwrapped. Concurrent workers that fail together are
almost always seeing one poisoned input from their own share of it, so the first
is representative; if nothing can be unwrapped the original is rethrown intact
rather than being replaced by something less informative.
"""
function _rethrow_worker_failure(err)
    cause = err
    while true
        if cause isa CompositeException && !isempty(cause.exceptions)
            cause = first(cause.exceptions)
        elseif cause isa TaskFailedException
            result = cause.task.result
            result isa Exception || break
            cause = result
        else
            break
        end
    end
    throw(cause)
end

"""
Launch geometry for the strong-strong CUDA kernels.

This is the SECOND consumer of `CUDAExecutionPolicy`'s `threads`/`blocks`, and
it used to be an undeclared one: it applies them to real kernels
(`_cuda_gaussian_reduce_partials_kernel!`, `_cuda_gaussian_build_moments_kernel!`,
`_cuda_gaussian_fused_kick_kernel!`) while the schema named only
`:cuda_fused_launch` and only `_cuda_launch_track_policy!` emitted a receipt. So
`configuration_report` under-reported where the value goes, and the
effectiveness contracts could not observe it here at all (2026-08-05_b audit,
U12-11).

It also resolves `:auto` by a different rule than the fused tracker's — particle
coverage capped at 256 blocks, not occupancy — and substitutes a fixed
`(256, 256)` when no CUDA policy is in scope. Both are recorded in the receipt
rather than left for a reader to infer, `resolved_by` naming which rule ran.
"""
function _active_cuda_launch(nitems::Integer)
    policy = _ACTIVE_RESOLVED_POLICY[]
    if !(policy isa ResolvedCUDAExecutionPolicy)
        _record_execution!(:cuda_strong_strong_launch, CUDABackend,
            (threads=256, blocks=256, requested_blocks=:none,
             items=Int(nitems), resolved_by=:no_active_policy))
        return (threads=256, blocks=256)
    end
    blocks = policy.blocks isa Int ? policy.blocks : min(cld(Int(nitems), policy.threads), 256)
    blocks = max(blocks, 1)
    _record_execution!(:cuda_strong_strong_launch, CUDABackend,
        (threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
         items=Int(nitems),
         resolved_by=policy.blocks isa Int ? :explicit : :particle_coverage))
    return (threads=policy.threads, blocks=blocks)
end

_legacy_cuda_policy(policy::GPUExecutionPolicy) = CUDAExecutionPolicy(
    device=policy.device,
    launch=CUDALaunchConfig(threads=policy.threads, blocks=policy.blocks),
)

"""Activate allocation-time side effects associated with an execution policy."""
activate_policy!(policy::AbstractExecutionPolicy) = policy
function activate_policy!(policy::Union{CUDAExecutionPolicy,GPUExecutionPolicy})
    device = policy.device
    device === nothing && return policy
    @isdefined(_HAS_CUDA) && _HAS_CUDA || error("CUDA policy requires CUDA.jl to be available.")
    CUDA.device!(device)
    return policy
end

const _CPU_POLICY_OPTION_SCHEMA = (
    threads=ConfigurationOptionMeta(Union{Int,Symbol}, :auto,
        "Number of Octopus logical workers in Julia's default thread pool.";
        supported_backends=(CPUThreadsBackend,), consumer=:cpu_logical_workers),
)

const _MULTI_PROCESS_POLICY_OPTION_SCHEMA = (
    threads=ConfigurationOptionMeta(Union{Int,Symbol}, :auto,
        "Number of Octopus logical workers per rank, in Julia's default thread pool.";
        supported_backends=(CPUThreadsBackend,), consumer=:cpu_logical_workers),
    ranks=ConfigurationOptionMeta(Union{Int,Symbol}, :auto,
        "Required MPI rank count; :auto accepts the communicator the launcher \
         provided. Read back from the communicator at execution, never assumed.";
        supported_backends=(CPUThreadsBackend,),
        consumer=:multi_process_communicator),
)

const _CUDA_POLICY_OPTION_SCHEMA = (
    device=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "CUDA device index; nothing resolves from particle storage.";
        supported_backends=(CUDABackend,), consumer=:cuda_device),
    threads=ConfigurationOptionMeta(Int, 256,
        "Threads per block for fused CUDA tracking AND for the strong-strong \
         CUDA kernels; both consume this value.";
        supported_backends=(CUDABackend,), consumer=:cuda_fused_launch),
    blocks=ConfigurationOptionMeta(Union{Int,Symbol}, :auto,
        "Blocks per launch. TWO consumers resolve :auto by different rules: \
         the fused tracker (:cuda_fused_launch) uses occupancy and particle \
         coverage, while the strong-strong kernels \
         (:cuda_strong_strong_launch) use particle coverage capped at 256 \
         blocks, and fall back to a fixed 256 when no CUDA policy is in scope. \
         The receipts carry `resolved_by` so which rule ran is observable. \
         `consumer` below names only the fused tracker because the field holds \
         ONE symbol; the second consumer is observable through its own \
         :cuda_strong_strong_launch receipt.";
        supported_backends=(CUDABackend,), dependencies=(:threads,),
        consumer=:cuda_fused_launch),
)

const _LEGACY_GPU_POLICY_OPTION_SCHEMA = (
    device=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Deprecated CUDA device selector.";
        supported_backends=(CUDABackend,), consumer=:cuda_device),
    threads=ConfigurationOptionMeta(Int, 256,
        "Deprecated fused CUDA thread-count compatibility option.";
        supported_backends=(CUDABackend,), consumer=:cuda_fused_launch),
    blocks=ConfigurationOptionMeta(Int, 256,
        "Deprecated fused CUDA block-count compatibility option.";
        supported_backends=(CUDABackend,), dependencies=(:threads,),
        consumer=:cuda_fused_launch),
)

"""
    policy_option_schema(policy_or_type) -> NamedTuple

Declared metadata (`ConfigurationOptionMeta`) for a policy's public options:
type, default, meaning, category, and the runtime consumer each option must
reach. `validate_configuration_metadata()` pins these against the
constructors.
"""
policy_option_schema(::Type{CPUThreadsExecutionPolicy}) = _CPU_POLICY_OPTION_SCHEMA
policy_option_schema(::CPUThreadsExecutionPolicy) = _CPU_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{MultiProcessExecutionPolicy}) = _MULTI_PROCESS_POLICY_OPTION_SCHEMA
policy_option_schema(::MultiProcessExecutionPolicy) = _MULTI_PROCESS_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{CUDAExecutionPolicy}) = _CUDA_POLICY_OPTION_SCHEMA
policy_option_schema(::CUDAExecutionPolicy) = _CUDA_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{GPUExecutionPolicy}) = _LEGACY_GPU_POLICY_OPTION_SCHEMA
policy_option_schema(::GPUExecutionPolicy) = _LEGACY_GPU_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{PlaceholderPolicy}) = NamedTuple()
policy_option_schema(::PlaceholderPolicy) = NamedTuple()

"""
    configuration_report(object[, storage...])

Return structured `ConfigurationEntry` values for a policy, solver, slicing
configuration, task, schedule, observer, or diagnostics object. Each entry
separates the requested value from its resolved value and reports its status,
one of [`CONFIGURATION_STATUSES`](@ref). Execution audits provide the separate
evidence that a resolved value reached its concrete consumer.

This list used to be prose -- "resolved, inherited, inactive, library-managed,
deprecated, or still awaiting runtime information" -- and two sixths of it were
wrong: there is no `:library_managed` status anywhere in the codebase, and
"inactive" is two distinct symbols, `:inactive_backend` and
`:inactive_dependency`, neither of them `:inactive` (2026-08-05_b audit, U12-12).
A hand-copied vocabulary with nothing checking it is the drift shape Measured
Lesson 4 names, so it is a constant now and the suite pins it against what the
source actually constructs.
"""
function configuration_report(policy::CPUThreadsExecutionPolicy)
    resolved = _resolved_cpu_threads(policy)
    return (
        ConfigurationEntry(:threads, policy.threads, resolved, :resolved,
            policy.threads === :auto ? "inherited from Julia's default thread pool" :
                                       "explicit logical-worker count",
            :cpu_logical_workers),
    )
end

function configuration_report(policy::MultiProcessExecutionPolicy)
    resolved_threads = _resolved_cpu_threads(_composed_cpu_policy(policy))
    return (
        ConfigurationEntry(:threads, policy.threads, resolved_threads, :resolved,
            policy.threads === :auto ? "inherited from Julia's default thread pool" :
                                       "explicit logical-worker count, per rank",
            :cpu_logical_workers),
        # `:unresolved`, and it stays `:unresolved` in this report however the
        # policy was constructed: the rank count in force is the
        # COMMUNICATOR's, read at activation, and a report that resolved it
        # from the field would be reporting the request as though it were the
        # answer.
        ConfigurationEntry(:ranks, policy.ranks, policy.ranks, :unresolved,
            policy.ranks === :auto ?
                "read from the MPI communicator at execution" :
                "checked against the MPI communicator at execution",
            :multi_process_communicator),
    )
end

function configuration_report(policy::CUDAExecutionPolicy)
    return (
        ConfigurationEntry(:device, policy.device, policy.device, :unresolved,
            policy.device === nothing ? "resolved from CUDA particle storage at execution" :
                                        "validated against CUDA particle storage at execution",
            :cuda_device),
        ConfigurationEntry(:threads, policy.launch.threads, policy.launch.threads, :resolved,
            "explicit fused CUDA thread count", :cuda_fused_launch),
        ConfigurationEntry(:blocks, policy.launch.blocks, policy.launch.blocks,
            policy.launch.blocks === :auto ? :unresolved : :resolved,
            policy.launch.blocks === :auto ? "resolved from kernel occupancy and particle coverage" :
                                             "explicit fused CUDA block count",
            :cuda_fused_launch),
    )
end
function configuration_report(policy::GPUExecutionPolicy)
    return (
        ConfigurationEntry(:device, policy.device, policy.device, :deprecated,
            "applied through the CUDAExecutionPolicy compatibility adapter", :cuda_device),
        ConfigurationEntry(:threads, policy.threads, policy.threads, :deprecated,
            "applied through the CUDAExecutionPolicy compatibility adapter", :cuda_fused_launch),
        ConfigurationEntry(:blocks, policy.blocks, policy.blocks, :deprecated,
            "applied through the CUDAExecutionPolicy compatibility adapter", :cuda_fused_launch),
    )
end
configuration_report(::PlaceholderPolicy) = ()

description(::Type{PlaceholderPolicy}) = "Placeholder policy with no executable backend."
description(::Type{CPUThreadsExecutionPolicy}) = "Runs with a bounded number of CPU logical workers."
description(::Type{MultiProcessExecutionPolicy}) = "Runs one process per MPI rank, each with a bounded number of CPU logical workers."
description(::Type{CUDAExecutionPolicy}) = "Runs CUDA kernels with backend-specific launch configuration."
description(::Type{GPUExecutionPolicy}) = "Deprecated CUDA execution-policy compatibility type."
