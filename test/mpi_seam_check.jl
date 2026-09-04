# Child process for the suite's multi-process section: the one place the MPI
# half of the seam and the sharded tracking path actually execute.
#
# Run by `test/runtests.jl` under MPICH_jll's `mpiexec` at one and at two
# ranks; also runnable by hand:
#
#     mpiexec -n 2 julia --project=<env with Octopus and MPI> test/mpi_seam_check.jl
#
# Every line it prints that the suite asserts on begins with `MPI-`. It exits
# non-zero on the first failure, so a rank that dies takes the launcher down
# with it rather than hanging the others at the next collective.
using Octopus
using MPI
using Printf

include(joinpath(@__DIR__, "mpi_seam_check_fixture.jl"))

fail(msg) = (println("MPI-CHECK FAIL ", msg); flush(stdout); exit(1))

# Labelling comes from the communicator, not from `Octopus._mp_rank()`: that
# accessor reads the policy in force and correctly reports a single process
# OUTSIDE an execution scope, which is where these lines are printed.
# Evaluated at CALL time, not at load time: Octopus initialises MPI when the
# policy is first activated, which is after this file is parsed.
child_rank() = MPI.Initialized() ? MPI.Comm_rank(MPI.COMM_WORLD) : 0

# The extension must be LOADED, not merely resolvable: a child that silently
# ran the serial passthrough would report `nranks = 1` and pass every
# rank-agnostic assertion below while proving nothing about MPI.
ext = Base.get_extension(Octopus, :OctopusMPIExt)
ext === nothing && fail("OctopusMPIExt is not loaded in the child process")

rep = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
resolved = Octopus._resolve_execution_policy(MultiProcessExecutionPolicy(), rep)
audit = ExecutionAudit()

with_execution_audit(audit) do
    Octopus._with_execution_policy(resolved) do
        nranks = Octopus._mp_nranks()
        rank = Octopus._mp_rank()

        # --- the seam ---------------------------------------------------
        #
        # Rank r contributes 10^r, so the total names every contributing rank
        # in its digits and a dropped or doubled rank is visible rather than
        # merely wrong in the last bits.
        contribution = [Float64(10.0^rank), Float64(rank + 1)]
        Octopus._mp_allsum!(contribution)
        expected = [sum(10.0^r for r in 0:(nranks - 1)), sum(1.0 * (r + 1) for r in 0:(nranks - 1))]
        contribution == expected ||
            fail("allsum on rank $(rank): got $(contribution), expected $(expected)")

        lanes = [Float64(rank + 1), Float64(-(rank + 1))]
        Octopus._mp_lane_fold!(lanes)
        lane_expected = [sum(1.0 * (r + 1) for r in 0:(nranks - 1)),
                         -sum(1.0 * (r + 1) for r in 0:(nranks - 1))]
        lanes == lane_expected ||
            fail("lane fold on rank $(rank): got $(lanes), expected $(lane_expected)")

        lo, hi = Octopus._mp_allminmax(Float64(rank), Float64(rank))
        (lo == 0.0 && hi == Float64(nranks - 1)) ||
            fail("allminmax on rank $(rank): got ($(lo), $(hi))")

        carried = [Float64(rank), Float64(rank)]
        Octopus._mp_bcast!(carried)
        carried == [0.0, 0.0] || fail("bcast on rank $(rank): got $(carried)")
        Octopus._mp_bcast(rank) == 0 || fail("scalar bcast on rank $(rank)")
        Octopus._mp_barrier()

        receipts = filter(r -> r.consumer === :multi_process_communicator,
                          execution_receipts(audit))
        isempty(receipts) && fail("no communicator receipt")
        receipt = last(receipts)
        receipt.values.resolved_by === :mpi_communicator ||
            fail("receipt says $(receipt.values.resolved_by), not :mpi_communicator")
        receipt.values.nranks == nranks && receipt.values.rank == rank ||
            fail("receipt disagrees with the communicator")

        @printf("MPI-CHECK rank=%d nranks=%d resolved_by=%s OK\n",
                rank, nranks, receipt.values.resolved_by)
    end
end

# --- sharded tracking (step 3a) -----------------------------------------
#
# Built and tracked exactly as a user would, through the public constructor
# and `execute!`, under the multi-process policy. Every coordinate is printed
# at full precision; the parent concatenates the shards in rank order and
# compares the result with a single-process run of the same line. String
# comparison, so the cross-rank concatenation involves no arithmetic and a
# bitwise claim stays bitwise.
let policy = MultiProcessExecutionPolicy(threads=1)
    beam = _mpi_check_build_beam(policy)
    resolved = Octopus._resolve_execution_policy(policy, beam.rep)
    Octopus._with_execution_policy(resolved) do
        rank, nranks = Octopus._mp_rank(), Octopus._mp_nranks()
        offset, global_n = Octopus._mp_resolve_shard(length(beam.rep))
        global_n == _mpi_check_global_n() ||
            fail("global count $(global_n) is not $(_mpi_check_global_n())")
        @printf("MPI-SHARD rank=%d nranks=%d n=%d offset=%d\n",
                rank, nranks, length(beam.rep), offset)
    end
    execute!(TrackingTask(_mpi_check_radiating_line(); policy=policy), beam; turns=3)
    println("MPI-TRACK ", child_rank(), " ", _mpi_check_shard_line(beam.rep))

    # The strong beam's luminosity fold spans ranks: each rank folds the
    # reduction chunks it owns and the partials go back in chunk order.
    lum_beam = _mpi_check_build_beam(policy)
    element = _mpi_check_strong_beam()
    lum_resolved = Octopus._resolve_execution_policy(policy, lum_beam.rep)
    Octopus._with_execution_policy(lum_resolved) do
        Octopus.track!(lum_beam.rep, element, 2, lum_resolved)
    end
    println("MPI-LUM ", child_rank(), " ", repr(element.last_luminosity))

    # Step 3a divides tracking, not the accounting that spans particles. A
    # task carrying a run artifact must refuse at more than one rank rather
    # than have every rank write the same file; at one rank it must not.
    diagnosed = TrackingTask(_mpi_check_radiating_line();
                             policy=policy,
                             artifact=joinpath(mktempdir(), "refused.h5"))
    threw = try
        execute!(diagnosed, _mpi_check_build_beam(policy); turns=1)
        false
    catch err
        err isa ArgumentError && occursin("step 3a does not divide", sprint(showerror, err))
    end
    Octopus._with_execution_policy(resolved) do
        expected_refusal = Octopus._mp_nranks() > 1
        threw == expected_refusal ||
            fail("artifact refusal was $(threw) at $(Octopus._mp_nranks()) rank(s)")
    end
end
flush(stdout)
