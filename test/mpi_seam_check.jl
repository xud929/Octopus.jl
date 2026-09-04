# Child process for the suite's multi-process section: the one place the MPI
# half of the collective seam actually executes.
#
# Run by `test/runtests.jl` under MPICH_jll's `mpiexec` at one and at two
# ranks; also runnable by hand:
#
#     mpiexec -n 2 julia --project=<env with Octopus and MPI> test/mpi_seam_check.jl
#
# Every line it prints that the suite asserts on begins with `MPI-CHECK`. It
# exits non-zero on the first failure, so a rank that dies takes the launcher
# down with it rather than hanging the others at the next collective.
using Octopus
using MPI
using Printf

fail(msg) = (println("MPI-CHECK FAIL ", msg); flush(stdout); exit(1))

include(joinpath(@__DIR__, "mpi_seam_check_fixture.jl"))

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

        # Rank-ordered all-sum: rank r contributes 10^r, so the total names
        # every contributing rank in its digits and a dropped or doubled rank
        # is visible rather than merely wrong in the last bits.
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
        length(receipts) == 1 ||
            fail("expected one communicator receipt, got $(length(receipts))")
        receipt = only(receipts)
        receipt.values.resolved_by === :mpi_communicator ||
            fail("receipt says $(receipt.values.resolved_by), not :mpi_communicator")
        receipt.values.nranks == nranks && receipt.values.rank == rank ||
            fail("receipt disagrees with the communicator")

        if nranks == 1
            # The campaign's literal requirement: one-rank MPI reproduces the
            # single-process result bit for bit. Printed rather than asserted
            # here -- the parent compares it against the same run under
            # CPUThreadsExecutionPolicy, so the two numbers come from two
            # different policies and one of them is today's.
            beam = _mpi_check_beam()
            execute!(TrackingTask(_mpi_check_line();
                                  policy=MultiProcessExecutionPolicy(threads=1)),
                     beam; turns=2)
            println("MPI-CHECK coords ", _mpi_check_signature(beam))
        else
            # Step 2 has no sharded consumer, so a task must refuse rather
            # than run whole on every rank. The day step 3 lands, this flips.
            threw = try
                execute!(TrackingTask(_mpi_check_line();
                                      policy=MultiProcessExecutionPolicy()),
                         _mpi_check_beam(); turns=1)
                false
            catch err
                err isa ArgumentError && occursin("MPI ranks", sprint(showerror, err))
            end
            threw || fail("execute! did not refuse an unsharded run at $(nranks) ranks")
        end

        @printf("MPI-CHECK rank=%d nranks=%d resolved_by=%s OK\n",
                rank, nranks, receipt.values.resolved_by)
    end
end
flush(stdout)
