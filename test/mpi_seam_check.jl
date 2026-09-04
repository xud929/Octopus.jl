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

    # Step 3b divides the diagnostics that reduce the beam to scalars. What
    # is still refused needs the whole beam's PARTICLES in one place: an
    # aperture keys its loss rows on the index the rank sees.
    walled = TrackingTask((_mpi_check_radiating_line()...,
                           Octopus.ApertureSpec(shape=:ellipse, x_limit=1.0, y_limit=1.0));
                          policy=policy)
    threw = try
        execute!(walled, _mpi_check_build_beam(policy); turns=1)
        false
    catch err
        err isa ArgumentError && occursin("not divided", sprint(showerror, err))
    end
    Octopus._with_execution_policy(resolved) do
        expected_refusal = Octopus._mp_nranks() > 1
        threw == expected_refusal ||
            fail("aperture refusal was $(threw) at $(Octopus._mp_nranks()) rank(s)")
    end
end

# --- step 3b: the scalar diagnostics divide ------------------------------
#
# One run, one output file, written by rank 0; every rank runs the observer,
# because its reduction is a collective and a rank that skipped it would hang
# its peers. The proof that only rank 0 wrote is the ROW COUNT: if every rank
# wrote, a P-rank run would leave P rows per turn instead of one.
let policy = MultiProcessExecutionPolicy(threads=1)
    path = _mpi_check_artifact_path()
    beam = _mpi_check_build_beam(policy)
    resolved = Octopus._resolve_execution_policy(policy, beam.rep)
    Octopus._with_execution_policy(resolved) do
        Octopus._mp_is_root() && isfile(path) && rm(path)
        Octopus._mp_barrier()
    end
    task = TrackingTask(_mpi_check_radiating_line(); policy=policy, artifact=path,
                        observers=(MomentObserver(name="m", orders=1:2),))
    execute!(task, beam; turns=3)
    if child_rank() == 0
        rows = read(MomentOutput(path; name="m"))
        println("MPI-MOMROWS ", size(rows, 1))
        println("MPI-MOM ", join((repr(v) for v in rows[end, :]), " "))
    end

    # Loss accounting spans the ranks: the counts a divided run reports are
    # the whole beam's, not this rank's shard's.
    poisoned = allow_lost_particles() do
        b = _mpi_check_poisoned_beam(policy)
        execute!(TrackingTask(_mpi_check_line(); policy=policy), b; turns=1)
        b
    end
    Octopus._with_execution_policy(
        Octopus._resolve_execution_policy(policy, poisoned.rep)) do
        summary = Octopus._global_loss_summary(
            Octopus.loss_summary(poisoned.rep, nothing))
        Octopus._mp_is_root() && println("MPI-LOSS particles=", summary.particles,
                                         " dead=", summary.dead,
                                         " live=", summary.live,
                                         " unattributed=", summary.unattributed)
    end
end
flush(stdout)
