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

# --- step 3c: the per-particle output gathers onto rank 0 -----------------
#
# An aperture writes one row per lost particle and a snapshot observer one row
# per particle per turn. Neither can be reduced, only moved, so both go
# through the seam's gather and land in rank 0's file -- carrying the GLOBAL
# particle id, not the slot index the rank happened to use.
let policy = MultiProcessExecutionPolicy(threads=1)
    path = joinpath(tempdir(), "octopus_mpi_seam_check_3c.h5")
    beam = _mpi_check_build_beam(policy)
    resolved = Octopus._resolve_execution_policy(policy, beam.rep)
    Octopus._with_execution_policy(resolved) do
        Octopus._mp_is_root() && isfile(path) && rm(path)
        Octopus._mp_barrier()
    end
    task = TrackingTask(_mpi_check_walled_line(); policy=policy, artifact=path,
                        observers=(CoordinateSnapshotObserver(name="snap", npart=12),))
    allow_lost_particles() do
        execute!(task, beam; turns=2)
    end
    if child_rank() == 0
        sig = _mpi_check_perparticle_signature(path)
        println("MPI-SNAPIDS ", join(sig.snapshot_ids, ","))
        println("MPI-SNAPTURNS ", join(sig.snapshot_turns, ","))
        println("MPI-LOSSIDS ", length(sig.loss_ids), " ", join(sig.loss_ids, ","))
        # The summary written INTO the file, which is the reduction that has
        # to have happened inside the policy scope.
        println("MPI-LOSSSUM particles=", sig.summary.particles,
                " dead=", sig.summary.dead, " live=", sig.summary.live)
    end

    # An action is the one thing left that Octopus cannot reason about, and it
    # must still refuse rather than hand a callback one rank's shard.
    threw = try
        execute!(TrackingTask(_mpi_check_line(); policy=policy,
                              actions=(Octopus.BeamSwapAction(identity),)),
                 _mpi_check_build_beam(policy); turns=1)
        false
    catch err
        err isa ArgumentError && occursin("task actions", sprint(showerror, err))
    end
    Octopus._with_execution_policy(resolved) do
        expected = Octopus._mp_nranks() > 1
        threw == expected ||
            fail("action refusal was $(threw) at $(Octopus._mp_nranks()) rank(s)")
    end
end

# --- step 4a: the soft-Gaussian collide divides ---------------------------
#
# Strong-strong is a different shape from tracking: both beams are sliced and
# every slice pair interacts, so the reductions are per slice rather than per
# beam. What has to span the ranks is the slicing (its statistics AND the
# histogram its boundaries are cut from), each slice's transverse moments and
# weight, and the luminosity. The kick itself is local.
let policy = MultiProcessExecutionPolicy(threads=1)
    b1, b2 = _mpi_check_collide_beams(policy)
    # A second, identical pair for the sequential schedule: the collide below
    # kicks the beams it is given, so the two schedules cannot share one.
    sb1, sb2 = _mpi_check_collide_beams(policy)
    resolved = Octopus._resolve_execution_policy(policy, b1.rep)
    Octopus._with_execution_policy(resolved) do
        Octopus._with_beam_shards(b1.rep, b2.rep, sb1.rep, sb2.rep) do
            slices = Octopus.longitudinal_slices(
                b1.rep, Octopus.LongitudinalSlicing(nslices=5, method=:equal_area))
            if Octopus._mp_is_root()
                println("MPI-SLICE bound ", join((repr(v) for v in slices.boundary), " "))
                println("MPI-SLICE weight ", join((repr(v) for v in slices.weight), " "))
            end
            lum = collide!(_mpi_check_gaussian_solver(), b1, b2, CPUThreadsBackend)
            sig = _mpi_check_collide_signature(b1.rep)
            Octopus._mp_is_root() && println("MPI-COLLIDE lum=", repr(lum),
                                             " maxpx=", repr(sig.maxpx),
                                             " rmspx=", repr(sig.rmspx),
                                             " rmspy=", repr(sig.rmspy))

            # `batch_mode` under division. The solver's default is
            # `:wavefront`, so the line above is the BATCHED schedule; this is
            # the sequential one, and the parent asserts the two agree to the
            # character. A batch repeats no beam-1 and no beam-2 slice, so each
            # slice still meets its partners in collision-time order, and the
            # luminosity folds by position in that order rather than by
            # arrival -- the schedule is free, at any rank count, and this is
            # where "at any rank count" is measured rather than argued.
            seq_lum = collide!(_mpi_check_gaussian_solver(batch_mode=:sequential),
                               sb1, sb2, CPUThreadsBackend)
            seq_sig = _mpi_check_collide_signature(sb1.rep)
            Octopus._mp_is_root() && println("MPI-COLLIDESEQ lum=", repr(seq_lum),
                                             " maxpx=", repr(seq_sig.maxpx),
                                             " rmspx=", repr(seq_sig.rmspx),
                                             " rmspy=", repr(seq_sig.rmspy))

            # `:equal_count` orders the whole beam, which is a sort and not a
            # fold, so it refuses rather than cutting a shard's boundaries.
            threw = try
                Octopus.longitudinal_slices(
                    b1.rep, Octopus.LongitudinalSlicing(nslices=5, method=:equal_count))
                false
            catch err
                err isa ArgumentError && occursin("global ordering", sprint(showerror, err))
            end
            threw == (Octopus._mp_nranks() > 1) ||
                fail("equal_count refusal was $(threw) at $(Octopus._mp_nranks()) rank(s)")
        end
    end
end

# --- step 4b: the strong-strong TASK divides --------------------------------
#
# The collide divided in 4a; this runs it through `execute!` with everything
# a task adds: two lines that each draw per particle, a line-placed moment
# observer in each, the luminosity channel and the run artifact. Two beams of
# DIFFERENT sizes, because a run holding two beams is where one scoped shard
# handed the second beam the first beam's offset.
let policy = MultiProcessExecutionPolicy(threads=1)
    path = _mpi_check_ss_artifact_path()
    b1, b2 = _mpi_check_ss_beams(policy)
    resolved = Octopus._resolve_execution_policy(policy, b1.rep)
    Octopus._with_execution_policy(resolved) do
        Octopus._mp_is_root() && isfile(path) && rm(path)
        Octopus._mp_barrier()
        # Each beam's shard as this rank resolved it. The parent asserts the
        # offsets: a wrong shift origin or a wrong radiation key on beam 2
        # would look like ordinary last-bit noise everywhere else.
        Octopus._with_beam_shards(b1.rep, b2.rep) do
            s1 = Octopus._mp_current_shard(b1.rep)
            s2 = Octopus._mp_current_shard(b2.rep)
            @printf("MPI-SSSHARD rank=%d b1=%d/%d b2=%d/%d\n",
                    Octopus._mp_rank(), s1[1], s1[2], s2[1], s2[2])
        end
    end
    execute!(_mpi_check_ss_task(policy, path), b1, b2; turns=3)
    # Whole-beam fingerprints of both beams after three turns, through the
    # collectives, so a shard's own root-mean-square is never mistaken for the
    # beam's (the 4a lesson).
    Octopus._with_execution_policy(resolved) do
        Octopus._with_beam_shards(b1.rep, b2.rep) do
            s1 = _mpi_check_collide_signature(b1.rep)
            s2 = _mpi_check_collide_signature(b2.rep)
            if Octopus._mp_is_root()
                println("MPI-SSBEAM1 ", repr(s1.maxpx), " ", repr(s1.rmspx), " ", repr(s1.rmspy))
                println("MPI-SSBEAM2 ", repr(s2.maxpx), " ", repr(s2.rmspx), " ", repr(s2.rmspy))
            end
        end
    end
    if child_rank() == 0
        rec = _mpi_check_ss_record(path)
        println("MPI-SSLUMTURNS ", join(rec.turns, ","))
        println("MPI-SSLUM ", join((repr(v) for v in rec.values), " "))
        println("MPI-SSMOMROWS ", rec.m1rows, " ", rec.m2rows)
        println("MPI-SSMOM1 ", join((repr(v) for v in rec.m1), " "))
        println("MPI-SSMOM2 ", join((repr(v) for v in rec.m2), " "))
    end

    # What still refuses at more than one rank, and runs at one: a solver step
    # 4c has not divided, and a line action. Each must throw ONLY when the
    # ranks are more than one, naming what is missing.
    threw_pic = try
        pb1, pb2 = _mpi_check_ss_beams(policy)
        execute!(_mpi_check_ss_task(policy, nothing; solver=_mpi_check_pic_solver()),
                 pb1, pb2; turns=1)
        false
    catch err
        err isa ArgumentError && occursin("step 4c", sprint(showerror, err))
    end
    threw_action = try
        ab1, ab2 = _mpi_check_ss_beams(policy)
        execute!(_mpi_check_ss_task_with_action(policy), ab1, ab2; turns=1)
        false
    catch err
        err isa ArgumentError && occursin("line action", sprint(showerror, err))
    end
    Octopus._with_execution_policy(resolved) do
        expected = Octopus._mp_nranks() > 1
        threw_pic == expected ||
            fail("PIC refusal was $(threw_pic) at $(Octopus._mp_nranks()) rank(s)")
        threw_action == expected ||
            fail("line-action refusal was $(threw_action) at $(Octopus._mp_nranks()) rank(s)")
        # Every rank checked the direction above; rank 0 alone reports it.
        Octopus._mp_is_root() && println("MPI-SSREFUSE pic=", threw_pic, " action=", threw_action)
    end
end

# --- step 4b, above the chunked thresholds ---------------------------------
#
# The pair above never enters the chunked moment and kick branches; this one
# does on every rank at 1, 2 and 4 ranks (see the fixture). Signatures and the
# luminosity series only: the moment observers' first-order columns sit near
# zero by construction at this size, and a relative comparison there measures
# chance rather than agreement.
let policy = MultiProcessExecutionPolicy(threads=1)
    path = _mpi_check_ss_big_artifact_path()
    b1, b2 = _mpi_check_ss_big_beams(policy)
    resolved = Octopus._resolve_execution_policy(policy, b1.rep)
    Octopus._with_execution_policy(resolved) do
        Octopus._mp_is_root() && isfile(path) && rm(path)
        Octopus._mp_barrier()
    end
    execute!(_mpi_check_ss_task(policy, path; solver=_mpi_check_ss_big_solver(),
                                observers=false), b1, b2; turns=2)
    Octopus._with_execution_policy(resolved) do
        Octopus._with_beam_shards(b1.rep, b2.rep) do
            s1 = _mpi_check_collide_signature(b1.rep)
            s2 = _mpi_check_collide_signature(b2.rep)
            if Octopus._mp_is_root()
                println("MPI-SSBIGBEAM1 ", repr(s1.maxpx), " ", repr(s1.rmspx), " ", repr(s1.rmspy))
                println("MPI-SSBIGBEAM2 ", repr(s2.maxpx), " ", repr(s2.rmspx), " ", repr(s2.rmspy))
            end
        end
    end
    if child_rank() == 0
        series = read(Octopus.TaskOutput(path), :luminosity; name="ip")
        println("MPI-SSBIGLUM ", join((repr(Float64(v)) for v in series.value), " "))
    end
end

# --- step 4b: a shard with no live particle must not hang its peers --------
#
# Found by the 4b design review and reproduced under a launcher on the tree
# that closed 4a: the slicing refused an all-dead SHARD on that rank's own
# count while its peers went on into the first collective and waited there.
# Both refusals now read the whole beam's counts. Global particles 129..256
# are killed -- all of rank 1's shard at two ranks, ranks 2 and 3 at four --
# so some ranks hold no live particle while the beam does; every rank must
# slice. Then every particle is killed, and every rank must refuse alike.
let policy = MultiProcessExecutionPolicy(threads=1)
    b1, _ = _mpi_check_ss_beams(policy)
    resolved = Octopus._resolve_execution_policy(policy, b1.rep)
    slc = Octopus.LongitudinalSlicing(nslices=5, method=:equal_area)
    Octopus._with_execution_policy(resolved) do
        offset, _ = Octopus._mp_resolve_shard(length(b1.rep))
        for g in 129:256
            local_i = g - offset
            1 <= local_i <= length(b1.rep) || continue
            for a in Octopus.coordinate_arrays(b1.rep)
                a[local_i] = NaN
            end
        end
        Octopus._with_beam_shards(b1.rep) do
            weights = allow_lost_particles() do
                Octopus.longitudinal_slices(b1.rep, slc).weight
            end
            isapprox(sum(weights), 1.0; rtol=1.0e-12) ||
                fail("half-dead beam sliced to weights $(weights) on rank $(Octopus._mp_rank())")
            for a in Octopus.coordinate_arrays(b1.rep)
                fill!(a, NaN)
            end
            threw = try
                allow_lost_particles() do
                    Octopus.longitudinal_slices(b1.rep, slc)
                end
                false
            catch err
                err isa ArgumentError && occursin("live particle", sprint(showerror, err))
            end
            threw || fail("all-dead beam did not refuse on rank $(Octopus._mp_rank())")
            Octopus._mp_is_root() &&
                println("MPI-SSPOISON half_dead_sliced=true all_dead_refused=true")
        end
    end
end
flush(stdout)
