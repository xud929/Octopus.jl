# ---------------------------------------------------------------------------
# The run artifact, its readers and the beam observers: `src/tasks/RunArtifact.jl`
# (the HDF5 artifact, its cursor and replay rules, the ledger, the lock, the
# in-memory storage, `TaskOutput` and `MomentOutput`), `src/tasks/BeamObservers.jl`
# and `src/tasks/BPMObserver.jl` (the moment, snapshot and BPM probes, the
# schedules, the hooks that cannot fire). A testset belongs here when its
# subject is the artifact, a reader or an observer; the loss record and the
# task kinds that write to the artifact keep their testsets in their own
# areas. Peeled from `legacy.jl` on 2026-11-27 by `test/move_testsets.jl`
# (docs/design/testing_lanes.md, section 1), the test observers and
# fixtures the testsets alone use moved with them. Selectable alone through
# `only=artifact_observers`.
# ---------------------------------------------------------------------------

# Deliberate mid-run failure for the crashed-execute! tests below.
struct FailAtTurnAction <: Octopus.AbstractBeamAction
    at::Int64
end
Octopus.apply_action!(a::FailAtTurnAction, ctx, rep) =
    (ctx.turn == a.at && error("deliberate failure at turn $(ctx.turn)"); nothing)
# Output-tail failure injector (2026-10-18 comprehensive audit, F-77): spoils a
# spec's `L` at one turn, so the arc walk the success path's /losses write runs
# AFTER every turn tracked (`_aperture_s_positions`) fails there and nowhere
# earlier.
struct SpoilLengthAtTurn <: Octopus.AbstractBeamObserver
    spec::ElementSpec
    at::Int64
end
Octopus.observe!(o::SpoilLengthAtTurn, ctx, rep) =
    (ctx.turn == o.at && set_param!(o.spec, :L, "spoiled"); nothing)
# Mid-run ledger peek for the run-artifact testset: reads the OPEN
# artifact's /execution current_turn and the channel cursor at one turn,
# so the flush-time agreement between the two is observable from a test.
struct LedgerPeekObserver <: Octopus.AbstractBeamObserver
    art::RunArtifact
    at_turn::Int
    seen::Vector{Tuple{Int64,Int64}}
end
function Octopus.observe!(o::LedgerPeekObserver, ctx::Octopus.TrackingContext, rep)
    ctx.turn == o.at_turn || return nothing
    cur = read(o.art.file["execution"]["current_turn"])[end]
    g = o.art.file["luminosity"]["ip"]
    cursor = read(Octopus.HDF5.attributes(g)["rows_valid_through_turn"])
    push!(o.seen, (Int64(cur), Int64(cursor)))
    return nothing
end
# Observer pair for the stranded-finalizer test (part 7, T7).
mutable struct FinalizeFlagObserver <: Octopus.AbstractBeamObserver
    finalized::Bool
end
Octopus.observe!(o::FinalizeFlagObserver, ctx, rep) = nothing
Octopus.finalize_observer!(o::FinalizeFlagObserver) = (o.finalized = true; nothing)
struct ThrowingFinalizeObserver <: Octopus.AbstractBeamObserver end
Octopus.observe!(::ThrowingFinalizeObserver, ctx, rep) = nothing
Octopus.finalize_observer!(::ThrowingFinalizeObserver) = error("finalize failure")
# Mid-run reseed for the noise-snapshot test (part 7, T8).
struct ReseedGlobalRNGAction <: Octopus.AbstractBeamAction end
Octopus.apply_action!(::ReseedGlobalRNGAction, ctx, rep) =
    (set_global_rng!(seed=999); nothing)
@testset "Observer finalizers, BPM noise keys, and the schedule planner" begin
    # T7: one throwing finalizer must not strand the others -- a finalizer is
    # where buffered measurements reach disk. The first error still surfaces.
    flag_task = FinalizeFlagObserver(false)
    flag_line = FinalizeFlagObserver(false)
    t7 = TrackingTask((DriftSpec(L=1.0), ScheduledObserver(flag_line));
                      hooks=(ScheduledObserver(ThrowingFinalizeObserver()),
                             ScheduledObserver(flag_task)))
    @test_throws ErrorException execute!(
        t7, Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
    @test flag_task.finalized
    @test flag_line.finalized

    # T8: the noise draw is a function of the execute-time RNG snapshot, as
    # stochastic tracking is -- a mid-run set_global_rng! must not
    # retroactively change a reading.
    seed_a = UInt64(424242)
    set_global_rng!(seed=seed_a)
    method_a = global_rng_method()
    bpm8 = BPMObserver("t8"; x_noise=1.0)
    t8 = TrackingTask((DriftSpec(L=1.0),);
                      hooks=(ScheduledAction(ReseedGlobalRNGAction()),
                             ScheduledObserver(bpm8)))
    execute!(t8, Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
    @test readings(bpm8)[2][1] ==
          Octopus.octopus_normal(seed_a, method_a, 0, bpm8.rng_id, 0, 1, Float64)
    set_global_rng!(seed=seed_a)

    # T9: x_noise is per-reading, so a BPM read twice in one turn draws twice;
    # occurrence 0 keeps the exact pre-existing stream.
    bpm9 = BPMObserver("t9"; x_noise=1.0)
    t9 = TrackingTask((DriftSpec(L=1.0),);
                      hooks=(ScheduledObserver(bpm9), ScheduledObserver(bpm9)))
    execute!(t9, Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
    let (turns9, x9, _) = readings(bpm9)
        @test turns9 == [0, 0]
        @test x9[1] != x9[2]
        @test x9[1] ==
              Octopus.octopus_normal(seed_a, method_a, 0, bpm9.rng_id, 0, 1, Float64)
        @test x9[2] ==
              Octopus.octopus_normal(seed_a, method_a, 0, bpm9.rng_id, 1, 1, Float64)
    end

    # T10: the EveryNSteps planner must not enumerate from the schedule start
    # -- its cost was proportional to the ABSOLUTE turn (29.5 ms at 1e8,
    # penalising exactly the chunked long run first_turn serves). Equivalence
    # against the enumerate-and-filter oracle, then a generous cost ceiling.
    oracle(s, turns, first) = begin
        lo = Int(first); hi = lo + Int(turns)
        stop = min(s.stop, hi)
        s.start >= stop ? Int[] :
            [t for t in s.start:s.step:(stop - 1) if lo <= t < hi]
    end
    for start in 0:3, step in 1:4, stop in (0, 1, 5, 17, 100), turns in 0:4,
        first in (0, 1, 3, 7, 50)

        s = EveryNSteps(start, stop, step)
        @test Octopus._scheduled_turns(s, turns, first) == oracle(s, turns, first)
    end
    let s = EveryNSteps(start=0, stop=typemax(Int), step=1)
        Octopus._scheduled_turns(s, 5, 10^8)          # warm up
        # A COMPLEXITY guard, not a wall-clock one (2026-08-05_b audit, U18-6).
        # This was `@elapsed(...) < 0.005`, and this file aborts at its first
        # failing testset (its own header records that as U17-7), so one GC
        # pause or a preempted shared runner would silently drop every testset
        # after this line -- including the whole CUDA block and the end-of-file
        # physics backstops. Measured cost is 8.8e-8 to 4.2e-6 s, so the real
        # property is that the planner does not walk the 10^8 offset: allocation
        # is the machine-independent witness of that, where time is not.
        @test (@allocated Octopus._scheduled_turns(s, 5, 10^8)) < 4096
        # Belt and braces: still time it, but generously enough that only a
        # genuine O(first_turn) regression can trip it -- 1000x the worst
        # measured sample rather than the ~1200x-headroom 5 ms.
        @test @elapsed(Octopus._scheduled_turns(s, 5, 10^8)) < 0.5
        @test Octopus._scheduled_turns(s, 5, 10^8) == collect(10^8:(10^8 + 4))
    end

    # T11: rng_id is the one field deciding whether two BPMs share a noise
    # stream, and it must appear in the configuration report.
    let entries = configuration_report(BPMObserver("t11"; x_noise=1.0))
        @test any(e -> e.name === :rng_id, entries)
    end

    # 2026-08-05_b audit, U7-5: a BPM reading copied ALL SIX coordinate arrays
    # to the host for two numbers. `_live_stat_flags` returns nothing unless
    # `allow_lost_particles()` is on, so on the default path only x and y are
    # ever read -- but `_host_coordinate_arrays(rep)` ran first regardless. At
    # the production size that is 6 x 2.56e6 x 8 B = 123 MB per reading, in a
    # function whose docstring justifies itself with "hundreds of BPMs read
    # every turn". Measured on the RTX 4500 Ada at 2.56M particles: 160.26 ms
    # before, 0.112 ms after (1434x).
    #
    # Pinned by HOST ALLOCATION, which is what regressed: `_mean(v)` is
    # `sum(v)/length(v)` and reduces on the device, so the default path must
    # transfer essentially nothing. A returning `Array(v)` shows up here as
    # megabytes. The masked path is asserted to still agree numerically.
    let n = 50_000
        mk() = Phase6DRep([1.0e-4 * sin(0.7i) for i in 1:n], zeros(n),
                          [1.0e-5 * sin(0.3i) for i in 1:n], zeros(n),
                          [1.0e-3 * sin(0.1i) for i in 1:n], zeros(n))
        r = mk()
        plain = Octopus._bpm_centroid(r)
        masked = allow_lost_particles(; enabled=true) do
            Octopus._bpm_centroid(r)
        end
        @test plain[1] ≈ masked[1] && plain[2] ≈ masked[2]
        if CUDA_TESTS_ACTIVE
            g = Phase6DRep((Octopus.CUDA.CuArray(a) for a in coordinate_arrays(r))...)
            gx, gy = Octopus._bpm_centroid(g)
            @test gx ≈ plain[1] && gy ≈ plain[2]
            Octopus._bpm_centroid(g)                      # warm
            @test @allocated(Octopus._bpm_centroid(g)) < 100_000
        else
            @test_skip "CUDA device not available"
        end
    end
end
@testset "A scheduled hook that cannot fire warns, for every hook kind at every placement" begin
    # 2026-10-18 comprehensive audit, F-76 and F-83 (fix batch 3, unit F).
    # `AtTurns([500])` on a 10-turn window: the U13-6 warning read the
    # task-level observers alone, so a line-placed observer, a task action and
    # a line action whose schedule selects no turn of the window ran silently
    # (probe_u12.jl P3: warned 0, 1, 0, 0 of the four), and the `@warn` had a
    # `\` OUTSIDE its string literal, so `schedule = schedule \ turns = turns`
    # parsed as one keyword argument (a closure printed for the schedule, no
    # `turns`). The cases are DERIVED from the hook-kind table `_HOOK_KINDS`
    # (one rule for every kind) times the two placements, so a third kind
    # joins the table and is tested here with no new line.
    kinds = Octopus._HOOK_KINDS
    @test Set(k.kind for k in kinds) == Set([:observer, :action])
    # Every in-line hook entry type of the module (the structs carrying a
    # `hook_index`) is a row of the table: a new entry kind cannot stay out.
    entry_types = Set{Any}()
    for n in names(Octopus; all=true)
        isdefined(Octopus, n) || continue
        T = getfield(Octopus, n)
        U = T isa UnionAll ? Base.unwrap_unionall(T) : T      # the entries are parametric
        U isa DataType && isstructtype(U) && :hook_index in fieldnames(U) && push!(entry_types, T)
    end
    @test Set(Any[k.entry for k in kinds]) == entry_types
    never = AtTurns([500])
    hook_of(kind) = kind === :observer ?
        ScheduledObserver(BPMObserver("late_" * String(kind)), never) :
        ScheduledAction(BeamSwapAction(() -> error("an unfireable action fired")), never)
    mk() = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    unfireable(logs) = [r for r in logs if r.level == Logging.Warn && occursin("cannot fire", r.message)]
    for k in kinds, placement in (:task, :line)
        hook = hook_of(k.kind)
        task = placement === :task ?
            TrackingTask((DriftSpec(L=1.0), DriftSpec(L=2.0)); hooks=(hook,)) :
            TrackingTask((DriftSpec(L=1.0), hook, DriftSpec(L=2.0)))
        logs, _ = Test.collect_test_logs() do
            execute!(task, mk(); turns=10)
        end
        warns = unfireable(logs)
        @testset let kind = k.kind, placement = placement
            @test length(warns) == 1
            if length(warns) == 1
                w = only(warns)
                # F-83: the window and the hooks are keyword arguments of the record.
                @test haskey(w.kwargs, :turns) && w.kwargs[:turns] == 10
                @test haskey(w.kwargs, :first_turn) && w.kwargs[:first_turn] == 0
                @test haskey(w.kwargs, :hooks) && length(w.kwargs[:hooks]) == 1
                label = haskey(w.kwargs, :hooks) ? string(only(w.kwargs[:hooks])) : ""
                @test occursin(placement === :task ? "task-level" : "in-line", label)
                @test occursin(String(k.kind), label)
                @test occursin("AtTurns", label)
            end
        end
    end
    # A window that reaches the schedule is silent, at either placement, and
    # the window is the ABSOLUTE one (`start_turn`); a predicate schedule
    # ("unknown" is not "empty") says nothing.
    let task = TrackingTask((DriftSpec(L=1.0), hook_of(:observer), DriftSpec(L=2.0));
                            hooks=(hook_of(:observer),))
        logs, _ = Test.collect_test_logs() do
            execute!(task, mk(); turns=3, start_turn=499)
        end
        @test isempty(unfireable(logs))
    end
    let task = TrackingTask((DriftSpec(L=1.0),);
                            hooks=(ScheduledObserver(BPMObserver("pred"), PredicateSchedule(ctx -> false)),))
        logs, _ = Test.collect_test_logs() do
            execute!(task, mk(); turns=3)
        end
        @test isempty(unfireable(logs))
    end
    # Every unfireable hook of one run is named in ONE warning.
    let task = TrackingTask((DriftSpec(L=1.0), hook_of(:observer), DriftSpec(L=2.0));
                            hooks=(hook_of(:action),))
        logs, _ = Test.collect_test_logs() do
            execute!(task, mk(); turns=10)
        end
        warns = unfireable(logs)
        @test length(warns) == 1 && length(only(warns).kwargs[:hooks]) == 2
    end
end
@testset "A strong-strong line's scheduled hook that cannot fire warns, as the tracking task's does" begin
    # Fix batch 3 (2026-10-21): unit F derived the unfireable-schedule warning
    # from the one hook table `_HOOK_KINDS` for `TrackingTask` (every kind at
    # both placements); the strong-strong compile never asked the question
    # for its line observers (unit E's report, integrator item 2), so a
    # `ScheduledObserver(..., AtTurns([500]))` on a four-turn collision run
    # observed nothing and said nothing. The strong-strong execute! now
    # enumerates each line's in-line hooks through the same
    # `_run_scheduled_hooks` and warns through the same
    # `_warn_unfireable_schedules`, once per line; a reachable schedule and the
    # other line stay silent. Memory-mode BPMs, so no artifact is involved.
    rid = Octopus._unheld_rng_id(Octopus.next_rng_id!() + 1_000_000)
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(64, CPUThreadsExecutionPolicy(), Float64;
             beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
             sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
             charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
    end
    ip = StrongStrongCollision(:ip)
    plain = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,))
    unfireable(l) = l.level == Logging.Warn && occursin("cannot fire in this run", l.message)
    far = StrongStrongTask((ip, plain, ScheduledObserver(BPMObserver("ssfar"), AtTurns([500]))), (ip, plain))
    logs, _ = Test.collect_test_logs() do
        execute!(far, mkb(rid + 1, -1.0, EMASS_EV, 10.0e9), mkb(rid + 2, 1.0, PMASS_EV, 275.0e9); turns=4)
    end
    warns = filter(unfireable, logs)
    @test length(warns) == 1                                   # was 0: nothing asked
    @test haskey(warns[1].kwargs, :hooks) &&
          any(s -> occursin("in-line observer BPMObserver", s) && occursin("AtTurns", s), warns[1].kwargs[:hooks])
    @test warns[1].kwargs[:turns] == 4 && warns[1].kwargs[:first_turn] == 0
    # The second line's hook is enumerated too (one warning per line).
    both = StrongStrongTask((ip, plain, ScheduledObserver(BPMObserver("ssfar1"), AtTurns([500]))),
                            (ip, plain, ScheduledObserver(BPMObserver("ssfar2"), AtTurns([600]))))
    logs2, _ = Test.collect_test_logs() do
        execute!(both, mkb(rid + 3, -1.0, EMASS_EV, 10.0e9), mkb(rid + 4, 1.0, PMASS_EV, 275.0e9); turns=4)
    end
    @test length(filter(unfireable, logs2)) == 2
    # Control: a reachable schedule says nothing.
    near = StrongStrongTask((ip, plain, ScheduledObserver(BPMObserver("ssnear"), AtTurns([2]))), (ip, plain))
    logs3, _ = Test.collect_test_logs() do
        execute!(near, mkb(rid + 5, -1.0, EMASS_EV, 10.0e9), mkb(rid + 6, 1.0, PMASS_EV, 275.0e9); turns=4)
    end
    @test !any(unfireable, logs3)
end
@testset "A crashed execute! still delivers its loss artifacts" begin
    # Audit part 7, T6. The stored turn deliberately does not advance on
    # failure (documented retry semantics), so the retry replays the same
    # absolute window -- which means (a) the loss file must be flushed on the
    # failure path, since a crashed run is exactly when it is wanted, and
    # (b) an observer must not keep the failed window's partial readings, or
    # the retry appends duplicate turn labels and the table is corrupt for
    # every downstream reader.
    path = tempname() * ".h5"
    bpm = BPMObserver("b")
    line = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name="COLL"),
            DriftSpec(L=0.5))
    task = TrackingTask(line;
                        hooks=(ScheduledObserver(bpm),
                               ScheduledAction(FailAtTurnAction(3))),
                        artifact=path)
    rep = Phase6DRep([1.0e-3, 5.0e-3, 0.0, 0.0], zeros(4),
                     [0.0, 0.0, 1.0e-4, 0.0], zeros(4), zeros(4), zeros(4))
    allow_lost_particles(; enabled=true) do
        @test_throws ErrorException execute!(task, rep; turns=5)
    end
    @test task.next_turn[] == 0                # documented: no advance on failure
    @test isfile(path)                         # T6a: the artifact exists after a crash
    let l = read(TaskOutput(path), :losses)
        @test l.aperture_counts == [1]
        @test l.summary !== nothing && l.summary.dead == 1
        # Self-consistency on the CRASH path too, which rewrites the group whole
        # as well and so owes the same equality.
        @test l.summary.logged == sum(l.aperture_counts)
        # And it SAYS which it is: a crashed run flushes this rank's accounting
        # on purpose, outside the policy scope, so the group is not folded.
        @test l.summary.folded === false
    end
    @test readings(bpm)[1] == [0, 1, 2]
    allow_lost_particles(; enabled=true) do
        @test_throws ErrorException execute!(task, rep; turns=5)
    end
    @test readings(bpm)[1] == [0, 1, 2]        # T6b: retry does not duplicate labels
    rm(path; force=true)

    # The discard is a no-op for an ordinary chunked run: two successful
    # chunks still append distinct turns.
    bpm2 = BPMObserver("b2")
    chunked = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(bpm2),))
    r2 = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    execute!(chunked, r2; turns=3)
    execute!(chunked, r2; turns=3)
    @test readings(bpm2)[1] == [0, 1, 2, 3, 4, 5]
end
@testset "The output tail: a failure after the last turn keeps the stored turn and closes the artifact, a refusal leaves no output receipt, a crash reconciles once" begin
    # 2026-10-18 comprehensive audit, F-77, F-80 and F-82 (fix batch 3, unit F).
    mk() = Phase6DRep([1.0e-4, -1.0e-4], zeros(2), zeros(2), zeros(2), zeros(2), zeros(2))
    # (a) F-77: the success path's output step -- the loss accounting and the
    # artifact's close, after every turn tracked -- fails (the arc walk of the
    # /losses write, spoiled by an observer at the last turn). `execute!`
    # documents "a failed call does not advance the stored turn" and every
    # path that closes the artifact releases its lock; on 24e8683 the stored
    # turn read 3, the artifact stayed open and locked, and the retry was
    # refused "already open" (probe_u12_p5b.jl).
    let path = tempname() * ".h5"
        d = DriftSpec(L=1.0)
        task = TrackingTask((d, DriftSpec(L=2.0)); hooks=(SpoilLengthAtTurn(d, 2),), artifact=path)
        rep = mk()
        err = try
            execute!(task, rep; turns=3)
            nothing
        catch e
            e
        end
        @test err isa MethodError                    # the output step's own failure surfaces
        @test task.next_turn[] == 0                  # was 3
        @test task.artifact.file === nothing         # was open
        @test !isfile(path * ".lock")                # was held
        set_param!(d, :L, 1.0)
        retry = try                                  # was refused "already open"
            execute!(task, rep; turns=1)
            nothing
        catch e
            e
        end
        @test retry === nothing
        @test task.next_turn[] == 1
        @test task.artifact.file === nothing && !isfile(path * ".lock")
        rm(path; force=true)
    end
    # (b) F-80: the `:tracking_output` receipt follows EVERY refusal that can
    # stop the run with no turn tracked, as the two per-run receipts do: a
    # duplicate probe name (the observers' prepare) left
    # `[:run_artifact_output, :tracking_output]` and no turn tracked on
    # 24e8683 (probe_u12.jl P2).
    let path = tempname() * ".h5"
        task = TrackingTask((DriftSpec(L=1.0), ScheduledObserver(MomentObserver(; name="dup", orders=1)),
                             DriftSpec(L=2.0), ScheduledObserver(MomentObserver(; name="dup", orders=1)));
                            artifact=path)
        audit = ExecutionAudit()
        err_box = Ref{Any}(nothing)          # `with_execution_audit` returns the audit, not the block's value
        with_execution_audit(audit) do
            try
                execute!(task, mk(); turns=3)
            catch e
                err_box[] = e
            end
        end
        err = err_box[]
        @test err isa ArgumentError && occursin("duplicate probe name", sprint(showerror, err))
        consumers = [r.consumer for r in execution_receipts(audit)]
        @test :run_artifact_output in consumers       # the prepare ran and said so
        @test !(:tracking_output in consumers)        # was recorded
        @test !(:tracking_turn_timing in consumers)
        @test task.next_turn[] == 0
        @test task.artifact.file === nothing && !isfile(path * ".lock")
        rm(path; force=true)
    end
    # (c) F-82: the crash path reconciles the loss accounting ONCE, as the
    # success path does (two `loss_summary` reductions per crashed execute! on
    # 24e8683, probe_u12.jl P7). Counted through a more specific method that
    # defers to the real one with `invoke` -- no body is copied -- added for
    # this block and deleted after it; `invokelatest`, because the method is
    # newer than this block's world. The success path's count of one is the
    # instrument's own control.
    let path = tempname() * ".h5", calls = Ref(0)
        Octopus.eval(quote
            function loss_summary(rep::Phase6DRep, record::LossRecord)
                $calls[] += 1
                return invoke(loss_summary, Tuple{Phase6DRep,Any}, rep, record)
            end
        end)
        try
            lost() = Phase6DRep([5.0e-3, 0.0], zeros(2), zeros(2), zeros(2), zeros(2), zeros(2))
            ap = ApertureSpec(x_limit=1.0e-3, y_limit=1.0e-3, name="A")
            task = TrackingTask((DriftSpec(L=1.0), ap); hooks=(FailAtTurnAction(1),), artifact=path)
            allow_lost_particles(; enabled=true) do
                @test_throws ErrorException Base.invokelatest(execute!, task, lost(); turns=3)
            end
            @test calls[] == 1                                        # was 2
            @test read(TaskOutput(path), :losses).summary.dead == 1   # and the flush still lands
            calls[] = 0
            ok = TrackingTask((DriftSpec(L=1.0), ap); artifact=tempname() * ".h5")
            allow_lost_particles(; enabled=true) do
                Base.invokelatest(execute!, ok, lost(); turns=3)
            end
            @test calls[] == 1
            rm(ok.artifact.path; force=true)
        finally
            Base.delete_method(which(Octopus.loss_summary, (Phase6DRep, Octopus.LossRecord)))
        end
        rm(path; force=true)
    end
end
@testset "BPMObserver artifact mode buffers by the artifact capacity" begin
    # N2 closure (archived todo row, 2026-08-11), re-homed on the run artifact
    # when the TSV path mode retired (2026-08-18); the per-observer capacity
    # retired the same day, so the ARTIFACT'S capacity is the batching knob
    # composed with the BPM's replay discard. Buffered rows flush at every
    # execute! end through BOTH finalize chains; the artifact's push cursor
    # starts past the surviving memory prefix at every bind, so buffering and
    # replay cannot disagree about what is in the file.
    rep1() = Phase6DRep([1e-4], [0.0], [2e-4], [0.0], [0.0], [0.0])
    tdir = mktempdir()

    p3 = joinpath(tdir, "a3.h5")
    b3 = BPMObserver("b3"; artifact=true)
    t = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(b3),),
                     artifact=RunArtifact(p3; append=true, capacity=100))
    r = rep1()
    execute!(t, r; turns=7)
    @test length(read(TaskOutput(p3), :bpm; name="b3").turn) == 7   # execute! flushes the buffered tail
    execute!(t, r; turns=4, start_turn=3)           # rewind: replay 3..6
    @test read(TaskOutput(p3), :bpm; name="b3").turn == 0:6         # each turn exactly once

    p5 = joinpath(tdir, "a5.h5")
    b5 = BPMObserver("b5"; artifact=true)
    t5 = TrackingTask((DriftSpec(L=0.5), ScheduledObserver(b5),
                       DriftSpec(L=0.5)); artifact=RunArtifact(p5; capacity=50))
    execute!(t5, rep1(); turns=3)
    @test length(read(TaskOutput(p5), :bpm; name="b5").turn) == 3   # in-line finalize chain

    # The per-observer capacity and the TSV path mode are retired: both
    # keywords survive only to throw the migration pointer (buffering is the
    # artifact's one capacity).
    let err = try; BPMObserver("x"; capacity=2); "did not throw"
              catch e; sprint(showerror, e) end
        @test occursin("retired", err) && occursin("RunArtifact", err)
    end
    let err = try; BPMObserver("x"; path="x.tsv"); "did not throw"
              catch e; sprint(showerror, e) end
        @test occursin("retired", err) && occursin("TaskOutput", err)
    end
end
@testset "The run artifact carries the strong-strong luminosity channel" begin
    # docs/design/run_artifact.md, migration step 1 (2026-08-18): one HDF5
    # per task; /luminosity/<label> with INDEPENDENT per-collision turn axes;
    # /execution with one appended row per execute!; per-group
    # rows-valid-through-turn cursor for crash recovery; append/replay per
    # group; label mismatch refused. (The text observer originally ran
    # alongside as a mirror and was pinned to agree exactly where both wrote;
    # it retired in step 4, so the pins below carry the values directly.)
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    l6a = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
    l6b = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))
    ip = StrongStrongCollision(:ip)

    # (1) The channel carries every evaluated turn, the cursor trails the
    # rows, and the execution ledger carries this execute!.
    pa = tempname() * ".h5"
    t1 = StrongStrongTask((ip, l6a), (ip, l6b); artifact=pa)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    Octopus.HDF5.h5open(pa, "r") do f
        @test read(f["luminosity"]["ip"]["turns"]) == [0, 1, 2]
        @test all(isfinite, read(f["luminosity"]["ip"]["values"]))
        @test all(read(f["luminosity"]["ip"]["values"]) .> 0)
        @test read(Octopus.HDF5.attributes(f["luminosity"]["ip"])["rows_valid_through_turn"]) == 2
        @test read(f["execution"]["start_turn"]) == [0]
        @test read(f["execution"]["turns"]) == [3]
        @test read(f["execution"]["current_turn"]) == [2]   # reached the window's end
        @test all(read(f["execution"]["elapsed"]) .> 0)
    end
    # ... and the reader hands the same series back.
    let series = read(TaskOutput(pa), :luminosity; name="ip")
        @test series.turn == [0, 1, 2] && all(series.value .> 0)
    end

    # The retirement pins (step 4, 2026-08-18): every retired spelling throws
    # a precise migration error naming the artifact, never a silent accept or
    # a bare unknown-keyword MethodError -- and the retired observer type is
    # gone from the API surface.
    let dline = (DriftSpec(L=1.0),)
        for f in (() -> StrongStrongTask((ip, l6a), (ip, l6b); luminosity_path="x.lum"),
                  () -> StrongStrongTask((ip, l6a), (ip, l6b); luminosity_append=true),
                  () -> StrongStrongTask((ip, l6a), (ip, l6b); luminosity="x.lum"),
                  () -> TrackingTask(dline; luminosity="x.lum"),
                  () -> TrackingTask(dline; loss_log="x.h5"),
                  () -> MomentObserver("x.h5"),
                  () -> MomentObserver(; name="m", capacity=8),
                  () -> BPMObserver("b"; capacity=8),
                  () -> CoordinateSnapshotObserver("x.coord"))
            err = try; f(); "did not throw" catch e; sprint(showerror, e) end
            @test occursin("retired", err) && occursin("artifact", err)
        end
        @test !(:LuminosityObserver in names(Octopus))
        @test !(:read_moment in names(Octopus))   # retired with the rename; MomentOutput reads legacy files
    end

    # (2) THE DISSOLUTION PIN. Two IPs with disagreeing luminosity schedules:
    # the retired fixed-width text row had to drop disagreeing turns WHOLE,
    # while the artifact keeps each collision's OWN evaluated turns -- the
    # mixed-IP workaround does not exist here.
    sl = LongitudinalSlicing(nslices=2, method=:equal_count)
    sp = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
                               slicing=sl, method=:grid, grid=(32, 64),
                               domain_factor=16.0,
                               luminosity_schedule=EveryNSteps(step=3))
    ip1 = StrongStrongCollision(:ip1)
    ip2 = StrongStrongCollision(:ip2; poisson_solver=sp)
    pm = tempname() * ".h5"
    tmix = StrongStrongTask((ip1, l6a, ip2), (ip1, l6b, ip2); artifact=pm)
    b1, b2 = beams()
    Test.collect_test_logs() do
        execute!(tmix, b1, b2; turns=7)
    end
    Octopus.HDF5.h5open(pm, "r") do f
        @test read(f["luminosity"]["ip1"]["turns"]) == collect(0:6)
        @test read(f["luminosity"]["ip2"]["turns"]) == [0, 3, 6]
    end

    # (3) Append continues per group, a rewind drops per group, and every
    # execution keeps its ledger row.
    pa2 = tempname() * ".h5"
    t2 = StrongStrongTask((ip, l6a), (ip, l6b); artifact=RunArtifact(pa2; append=true))
    b1, b2 = beams(); execute!(t2, b1, b2; turns=3)
    b1, b2 = beams(); execute!(t2, b1, b2; turns=2, start_turn=3)
    b1, b2 = beams(); execute!(t2, b1, b2; turns=1, start_turn=2)
    Octopus.HDF5.h5open(pa2, "r") do f
        @test read(f["luminosity"]["ip"]["turns"]) == [0, 1, 2]
        @test read(f["execution"]["start_turn"]) == [0, 3, 2]
        @test read(f["execution"]["current_turn"]) == [2, 4, 2]   # per execution
    end
    # (4) Crash recovery: rows beyond the cursor are a torn tail and are
    # truncated on the next open.
    Octopus.HDF5.h5open(pa2, "r+") do f
        g = f["luminosity"]["ip"]
        n = length(g["turns"])
        Octopus.HDF5.set_extent_dims(g["turns"], (n + 2,))
        Octopus.HDF5.set_extent_dims(g["values"], (n + 2,))
        g["turns"][(n + 1):(n + 2)] = [98, 99]
        g["values"][(n + 1):(n + 2)] = [1.0, 2.0]
    end
    logs_t2b, _ = Test.collect_test_logs() do
        t2b = StrongStrongTask((ip, l6a), (ip, l6b);
                               artifact=RunArtifact(pa2; append=true))
        b1, b2 = beams(); execute!(t2b, b1, b2; turns=1, start_turn=3)
    end
    Octopus.HDF5.h5open(pa2, "r") do f
        @test read(f["luminosity"]["ip"]["turns"]) == [0, 1, 2, 3]
    end
    # The torn tail is truncated SILENTLY by design (RunArtifact.jl: rows past
    # the cursor are a torn tail, the docstring says so, and the truncation
    # emits nothing), and the reopen by a NEW task object of a path whose
    # previous writer (`t2`'s artifact) has finished and closed is the
    # sequential continuation the path registry stays silent for since fix
    # batch 3 (2026-10-21, unit G, F-85: it warned here as "a second live
    # observer ..." because `t2`'s artifact OBJECT was still alive, not still
    # writing; measured 2026-10-20: exactly one warning, that one). So this
    # reopen emits NOTHING at Warn or above, pinned on the capture so a new
    # warning or error log on this path is a change this test sees rather
    # than a capture nobody reads (2026-10-18 audit F-214/U33-4, `logs_t2b`
    # was dead).
    @testset let torn_tail_logs = [string(l.level, ": ", l.message) for l in logs_t2b if l.level >= Logging.Warn]
        @test isempty(torn_tail_logs)      # was 1: "a second live observer is initializing ..."
    end
    # (4b) The weak-strong side of the channel (step 2a): per-strong-beam
    # datasets carrying the positive rows only (this fixture's thin strong
    # beam reports positive luminosity at turn 0 alone -- verified against
    # the pre-existing text observer before it retired), /losses readable
    # through the losses read, and the ledger present even for a line with no
    # luminosity producer at all.
    let sb = GaussianStrongBeamSpec(; kbb=1.0e-4, beta=(1.0, 1.0),
                                    sigma=(1.0e-3, 1.0e-3), klum=1.0, ns=1)
        wa = tempname() * ".h5"
        tw = TrackingTask((sb, DriftSpec(L=1.0)); artifact=wa)
        execute!(tw, Phase6DRep([1.0e-3], [0.0], [0.5e-3], [0.0], [0.0], [0.0]);
                 turns=3)
        Octopus.HDF5.h5open(wa, "r") do f
            @test read(f["luminosity"]["strong_beam_1"]["turns"]) == [0]
            @test all(read(f["luminosity"]["strong_beam_1"]["values"]) .> 0)
            @test read(f["execution"]["current_turn"]) == [2]
        end
        ap = ApertureSpec(shape=:ellipse, x_limit=2.0e-3, y_limit=2.0e-3)
        wa2 = tempname() * ".h5"
        tl = TrackingTask((ap, DriftSpec(L=1.0)); artifact=wa2)
        execute!(tl, Phase6DRep([1.0e-3, 5.0e-3], [0.0, 0.0], [0.0, 0.0],
                                [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]); turns=3)
        let l = read(TaskOutput(wa2), :losses)
            @test l.aperture_counts == [1]
            @test length(l.particle_id) == 1        # per-loss rows present
            @test l.summary !== nothing && l.summary.dead == 1
            # The group is self-checking since 2026-09-07: `aperture_counts` is
            # what each aperture attributed and `summary_logged` is their total.
            # Under a divided run both are the whole beam's -- the 2026-09-06
            # neighbour audit found `aperture_counts` was one rank's while
            # everything beside it was global, which this equality would have
            # caught had the file carried both halves.
            @test l.summary.logged == sum(l.aperture_counts)
            # A completed run's group is the BEAM's, folded across the ranks.
            @test l.summary.folded === true
        end
        wa3 = tempname() * ".h5"
        execute!(TrackingTask((DriftSpec(L=1.0),); artifact=wa3),
                 Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=2)
        Octopus.HDF5.h5open(wa3, "r") do f
            @test read(f["execution"]["current_turn"]) == [1]
        end
        foreach(x -> rm(x; force=true), (wa, wa2, wa3))
    end

    # (4c) Probes as named views (step 2): moments, snapshots and BPM
    # readings bind to the artifact through the active-artifact scope at
    # prepare, write row-matrix groups keyed by NAME (the design's identity
    # rule), and follow the same continuation/rewind semantics per group.
    let pa = tempname() * ".h5",
        mk = () -> Phase6DRep([1.0e-3, -0.5e-3], [0.0, 0.0], [0.5e-3, 0.0],
                              [0.0, 0.0], [0.0, 0.0], [0.0, 0.0])
        tv = TrackingTask((DriftSpec(L=1.0),);
                          hooks=(ScheduledObserver(MomentObserver(; name="IP6", orders=1:1)),
                                 ScheduledObserver(CoordinateSnapshotObserver(; name="inj")),
                                 ScheduledObserver(BPMObserver("BPM_07"; artifact=true))),
                          artifact=RunArtifact(pa; append=true, capacity=2))
        execute!(tv, mk(); turns=3)
        execute!(tv, mk(); turns=2, start_turn=3)
        execute!(tv, mk(); turns=1, start_turn=2)      # rewind
        Octopus.HDF5.h5open(pa, "r") do f
            @test sort(collect(keys(f))) ==
                  ["bpm", "execution", "luminosity", "moments", "snapshot"]
            m = read(f["moments"]["IP6"]["data"])
            @test Int.(m[:, 1]) == [0, 1, 2]
            @test read(f["moments"]["IP6"]["column_names"])[1] == "turn"
            sdat = read(f["snapshot"]["inj"]["data"])
            @test size(sdat) == (6, 8)                  # 2 particles x 3 turns
            @test sort(unique(Int.(sdat[:, 1]))) == [0, 1, 2]
            b = read(f["bpm"]["BPM_07"]["data"])
            @test Int.(b[:, 1]) == [0, 1, 2]            # no duplicated rows
            @test read(f["execution"]["start_turn"]) == [0, 3, 2]
        end
        # The reader surface (step 4): ONE handle, `read(out, kind; ...)`
        # with keyword selection -- the MomentOutput ergonomics
        # generalized (owner direction, 2026-08-18) -- plus MomentOutput
        # itself against a group for Moment-aware selection.
        tout = TaskOutput(pa)
        # Bare read = the RECURSIVE metadata contents (owner direction,
        # 2026-08-19): per group its columns, row count, and s where
        # stamped -- one call sufficient to write every subsequent read.
        let toc = read(tout)
            @test sort(collect(keys(toc["moments"]))) == ["IP6"]
            @test toc["moments"]["IP6"].columns[1] == "turn"
            @test toc["moments"]["IP6"].rows == 3
            @test isempty(toc["luminosity"])   # drift line: no producer, kind present
            @test read(TaskOutput(pa2))["luminosity"]["ip"].columns == ["turn", "value"]
            @test toc["execution"].rows == 3
        end
        mout = MomentOutput(pa; name="IP6")
        @test Int.(read(mout, :turn)) == [0, 1, 2]
        @test column_names(mout)[1] == "turn"
        @test size(read(mout), 1) == 3
        @test Int.(read(tout, :bpm; name="BPM_07").turn) == [0, 1, 2]
        @test read(tout, :bpm; name="BPM_07", column=:x) ==
              read(tout, :bpm; name="BPM_07").x
        @test sort(unique(Int.(read(tout, :snapshot; name="inj").turn))) == [0, 1, 2]
        # turn= narrows a snapshot to one fired block; column=Moment selects
        # a moment column by its canonical identity.
        @test all(read(tout, :snapshot; name="inj", turn=1).turn .== 1.0)
        # particle_id= narrows a snapshot to one particle's rows, as turn=
        # narrows it to one fired block, and the two together select one
        # row; an id the group does not hold reads as empty columns, as an
        # absent turn does, and the keyword is refused by name wherever it
        # cannot mean anything (the keyword landed 2026-11-27, the one Integer
        # form `turn` takes).
        let every = read(tout, :snapshot; name="inj"),
            one = read(tout, :snapshot; name="inj", particle_id=2)
            @test all(one.particle_id .== 2.0) && sort(Int.(one.turn)) == [0, 1, 2]
            @test one.x == every.x[every.particle_id .== 2.0] && one.s === every.s
        end
        let cell = read(tout, :snapshot; name="inj", turn=1, particle_id=2)
            @test length(cell.turn) == 1 && cell.turn[1] == 1.0 && cell.particle_id[1] == 2.0
            @test read(tout, :snapshot; name="inj", turn=1, particle_id=2, column=:px) == cell.px
        end
        @test isempty(read(tout, :snapshot; name="inj", particle_id=7).turn)
        @test_throws ArgumentError read(tout, :moments; name="IP6", particle_id=1)
        @test_throws ArgumentError read(tout, :snapshot; particle_id=1)
        @test_throws ArgumentError read(tout, :execution; particle_id=1)
        @test occursin("particle_id", sprint(showerror, try read(tout, :bpm; name="BPM_07", particle_id=1) catch e; e end))
        @test read(tout, :moments; name="IP6", column=Moment(; x=1)) ==
              read(mout, Moment(; x=1))
        # orders/extra/exclude fold in with the MomentObserver selection
        # rules (owner direction, 2026-08-18), returning the usual columns
        # NamedTuple; MomentOutput keeps the matrix form of the same
        # selection, and MomentOutputFile survives as a rename alias.
        let sel = read(tout, :moments; name="IP6", orders=1)
            @test sel.m100000 == read(mout, Moment(; x=1))
            @test first(keys(sel)) == :turn && length(keys(sel)) == 7
        end
        @test keys(read(tout, :moments; name="IP6", orders=(),
                        extra=(Moment(; x=1),))) == (:turn, :m100000)
        @test MomentOutputFile === MomentOutput
        @test read(tout, :execution).start_turn == [0, 3, 2]
        # No name: every group of the kind, keyed by identity; read(out, :all)
        # nests every kind present. Selection keywords are refused where they
        # cannot mean anything.
        @test sort(collect(keys(read(tout, :moments)))) == ["IP6"]
        @test sort(collect(string.(keys(read(tout, :all))))) ==
              ["bpm", "execution", "luminosity", "moments", "snapshot"]
        @test Int.(read(tout, :all).bpm["BPM_07"].turn) == [0, 1, 2]
        @test_throws ArgumentError read(tout, :nonsense)
        @test_throws ArgumentError read(tout, :moments; name="absent")
        @test_throws ArgumentError read(tout, :moments; name="IP6", column=:zzz)
        @test_throws ArgumentError read(tout, :losses; name="x")
        @test_throws ArgumentError read(tout, :bpm; turn=1)
        @test_throws ArgumentError read(tout, :all; name="IP6")
        @test_throws ArgumentError read(tout, :bpm; name="BPM_07", orders=1)
        @test_throws ArgumentError read(tout, :moments; name="IP6",
                                        orders=1, column=:m100000)

        # Name uniqueness is the identity rule, enforced loudly; a named
        # probe without an artifact-carrying task is refused, not ignored.
        tdup = TrackingTask((DriftSpec(L=1.0),);
                            hooks=(ScheduledObserver(MomentObserver(; name="X")),
                                   ScheduledObserver(MomentObserver(; name="X"))),
                            artifact=tempname() * ".h5")
        @test_throws ArgumentError execute!(tdup, mk(); turns=1)
        tno = TrackingTask((DriftSpec(L=1.0),);
                           hooks=(ScheduledObserver(MomentObserver(; name="Y")),))
        @test_throws ArgumentError execute!(tno, mk(); turns=1)
        rm(pa; force=true)
    end

    # (4d) A STRONG-STRONG line-placed probe view: its buffered tail lives
    # in memory until finalize, so line observers must flush BEFORE the
    # artifact closes. The reverse order shipped briefly and only the
    # example scripts caught it (2026-08-18) -- the suite's strong-strong
    # artifact cases all used bare lines. Default capacity (64 > 3 turns)
    # makes the tail flush AT finalize, which is the pinned order.
    let pss = tempname() * ".h5"
        tss = StrongStrongTask(
            (ip, l6a, ScheduledObserver(MomentObserver(; name="e_mid"))),
            (ip, l6b); artifact=pss)
        b1, b2 = beams()
        execute!(tss, b1, b2; turns=3)
        @test Int.(read(TaskOutput(pss), :moments; name="e_mid").turn) == [0, 1, 2]
        @test read(TaskOutput(pss), :luminosity; name="ip").turn == [0, 1, 2]
        rm(pss; force=true)
    end

    # (4f) The design's `attrs: name, s` (the niceties row's first item,
    # closed 2026-08-19): a line-placed probe records its arc position,
    # stamped at bind from the ONE spec-line walk (the U11-1 walker) and
    # surfaced by the reader as the scalar `s` beside the columns. A
    # task-hook probe has no line position and reads nothing; probes in the
    # two strong-strong lines each get THEIR OWN line's arc length.
    let pf = tempname() * ".h5"
        hooked = MomentObserver(; name="hooked")
        tv2 = TrackingTask((DriftSpec(L=1.0),
                            ScheduledObserver(MomentObserver(; name="mid", orders=1)),
                            DriftSpec(L=0.5),
                            ScheduledObserver(BPMObserver("sb"; artifact=true)));
                           hooks=(ScheduledObserver(hooked),), artifact=pf)
        execute!(tv2, Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
        of = TaskOutput(pf)
        @test read(of, :moments; name="mid").s == 1.0
        @test read(of, :bpm; name="sb").s == 1.5
        @test read(of, :moments; name="hooked").s === nothing
        rm(pf; force=true)
    end
    let pss = tempname() * ".h5"
        tss2 = StrongStrongTask(
            (DriftSpec(L=2.0), ip, l6a, ScheduledObserver(MomentObserver(; name="se"))),
            (DriftSpec(L=3.0), ip, l6b, ScheduledObserver(MomentObserver(; name="sp")));
            artifact=pss)
        b1, b2 = beams()
        execute!(tss2, b1, b2; turns=1)
        @test read(TaskOutput(pss), :moments; name="se").s == 2.0
        @test read(TaskOutput(pss), :moments; name="sp").s == 3.0
        rm(pss; force=true)
    end

    # (4e) The ledger's live current_turn AGREES with the channel cursor
    # at a mid-run capacity flush. Owner-observed 2026-08-19 at
    # capacity=100: assigned at the loop tail, the strong-strong ledger
    # lagged the cursor by one turn (current_turn 798 against
    # rows_valid_through_turn 799) -- the flush fires DURING a turn's
    # collision push, so the assignment must precede the pushes (as the
    # weak-strong loop always did).
    let pled = tempname() * ".h5"
        artl = RunArtifact(pled; capacity=2)
        peek = LedgerPeekObserver(artl, 2, Tuple{Int64,Int64}[])
        tl = StrongStrongTask((ip, l6a, peek), (ip, l6b); artifact=artl)
        b1, b2 = beams()
        execute!(tl, b1, b2; turns=4)
        # capacity=2: the flush fires during turn 1's push and must persist
        # turn 1 -- the turn whose row triggered it -- matching the cursor.
        @test peek.seen == [(1, 1)]
        rm(pled; force=true)
    end

    # (5) A label mismatch is refused rather than silently mixed.
    tbad = StrongStrongTask((StrongStrongCollision(:other), l6a),
                            (StrongStrongCollision(:other), l6b);
                            artifact=RunArtifact(pa2; append=true))
    b1, b2 = beams()
    Test.collect_test_logs() do
        @test_throws ArgumentError execute!(tbad, b1, b2; turns=1)
    end
    foreach(x -> rm(x; force=true), (pa, pm, pa2))
end
# Fixtures for the row-cursor testset below (fix batch 2026-10-19, unit T:
# comprehensive audit F-73, F-84, F-74, F-59, F-63). A coordinate array whose
# element READ throws once while armed: the fused `_moment_observer_row`
# (fix batch 3, 2026-10-21, unit G, F-78) reads the six coordinate arrays in
# place -- no `collect`, which is where this fixture used to inject -- so
# arming it between a turn's tracking and the MomentObserver's fire puts an
# exception INSIDE the row computation through the public task loop, with no
# method of the package redefined. The read disarms itself as it throws, so
# the crash path (the loss summary, the best-effort finalize) indexes the
# arrays freely afterwards. The tracking kernels index the arrays with the
# arm down; the testset checks that the arm took its path (the particle was
# tracked through the arming turn before the observer threw).
struct _FixTFailingVec <: AbstractVector{Float64}
    data::Vector{Float64}
    armed::Base.RefValue{Bool}
end
Base.size(v::_FixTFailingVec) = size(v.data)
Base.IndexStyle(::Type{_FixTFailingVec}) = IndexLinear()
Base.@propagate_inbounds function Base.getindex(v::_FixTFailingVec, i::Int)
    if v.armed[]
        v.armed[] = false
        throw(_FixTInjectedRowFailure())
    end
    return v.data[i]
end
Base.@propagate_inbounds Base.setindex!(v::_FixTFailingVec, x, i::Int) = (v.data[i] = x; v)
struct _FixTInjectedRowFailure <: Exception end
Base.showerror(io::IO, ::_FixTInjectedRowFailure) =
    print(io, "injected failure inside the moment row computation")
# Arms the failure at one turn from the hook slot BEFORE the MomentObserver's
# (hooks run in order after the turn's tracking); `turn = -1` disarms a retry.
mutable struct _FixTArmAtTurn <: Octopus.AbstractBeamObserver
    turn::Int
    armed::Base.RefValue{Bool}
end
Octopus.observe!(a::_FixTArmAtTurn, ctx::Octopus.TrackingContext, rep) =
    (ctx.turn == a.turn && (a.armed[] = true); nothing)
@testset "The run artifact's row cursor: a mid-row exception leaves no garbage row, a fill-row torn tail is truncated, readers apply the cursor, a missing cursor is refused" begin
    # Fix batch 2026-10-19, unit T (comprehensive audit 2026-10-18: F-73,
    # F-84, F-74, F-59, F-63). Every pin marked "was" below was red on
    # cb3c344 with the value it names (the unit report quotes the run); the
    # `_ra_set_attr!` round trip at the end is a guard on the in-place
    # rewrite the fix introduced (an in-place write of 2.5 over an Int64
    # attribute reads back 2), green on both trees.
    HDF5 = Octopus.HDF5
    no_turn = Int64(typemin(Int32))
    mktempdir() do dir
        attrs(p, key) = HDF5.h5open(p, "r") do f
            a = HDF5.attributes(f[key])
            (; (Symbol(k) => read(a[k]) for k in keys(a))...)
        end
        disk_turns(p, key) = HDF5.h5open(p, "r") do f
            d = f[key]["data"]
            size(d, 1) == 0 ? Float64[] : vec(d[:, 1])
        end
        armed = Ref(false)
        coords() = ([1.0e-4, 2.0e-4], [1.0e-5, -2.0e-5], [3.0e-4, -1.0e-4], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0])
        failing() = Phase6DRep((_FixTFailingVec(copy(v), armed) for v in coords())...)
        plain() = Phase6DRep((copy(v) for v in coords())...)

        # (1) F-73: a chunked run whose second chunk throws inside the moment
        # row at turn 6 (capacity 3: the rows of turns 4 and 5 are buffered,
        # the row of turn 6 is never computed). The best-effort finalize of the
        # failed run flushes the two complete rows and nothing else; the retry
        # (the stored turn does not advance on failure) replays 4:7 onto 0:3
        # and the file holds exactly 0:7.
        p1 = joinpath(dir, "garbage_row.h5")
        m1 = MomentObserver(; name="m", orders=1)
        arm = _FixTArmAtTurn(6, armed)
        t1 = TrackingTask((DriftSpec(L=1.0),);
                          hooks=(ScheduledObserver(arm), ScheduledObserver(m1)),
                          artifact=RunArtifact(p1; append=true, capacity=3))
        r1 = failing()
        execute!(t1, r1; turns=4)
        @test disk_turns(p1, "moments/m") == [0, 1, 2, 3]
        err1 = try; execute!(t1, r1; turns=4); nothing; catch e; e; end
        # red for the defect's reason: the injected row failure, not a tracking error
        @test err1 isa _FixTInjectedRowFailure
        @test t1.next_turn[] == 4
        # the arm took its path: the beam was tracked through turn 6 (seven
        # drifts) before the observer threw -- bitwise what a plain seven-turn
        # run of the same beam gives
        let rp = plain()
            execute!(TrackingTask((DriftSpec(L=1.0),)), rp; turns=7)
            @test r1.x.data == rp.x && r1.px.data == rp.px
        end
        @test disk_turns(p1, "moments/m") == [0, 1, 2, 3, 4, 5]      # was [0,1,2,3,4,5,<garbage>] (7 rows)
        a1 = attrs(p1, "moments/m")
        @test a1.rows_valid == 6 && a1.rows_valid_through_turn == 5    # was rows_valid absent, cursor 0
        armed[] = false
        arm.turn = -1
        execute!(t1, r1; turns=4)
        @test disk_turns(p1, "moments/m") == collect(0:7)             # was [0,4,5,6,7]
        @test read(MomentOutput(p1; name="m"), :turn) == collect(0:7)
        a1b = attrs(p1, "moments/m")
        @test a1b.rows_valid == 8 && a1b.rows_valid_through_turn == 7

        # (1b) F-84: the receipt is recorded AFTER the `initialized` refusal,
        # as the snapshot twin orders them: a refused fire leaves no receipt.
        m84 = MomentObserver(; name="x", orders=1)
        audit84 = ExecutionAudit()
        @test_throws ArgumentError with_execution_audit(
            () -> observe!(m84, Octopus.TrackingContext(turn=0), plain()), audit84)
        @test isempty(execution_receipts(audit84))                   # was one :observer_output receipt

        # (2) F-74: a torn tail of HDF5 fill rows -- the extent advanced, the
        # cursor not, a kill between the data write and the cursor flush -- is
        # removed by the row cursor whatever the fill value, and the
        # continuation appends at the right place.
        p2 = joinpath(dir, "fill_tail.h5")
        m2 = MomentObserver(; name="m", orders=1)
        t2 = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(m2),),
                          artifact=RunArtifact(p2; append=true, capacity=64))
        r2 = plain()
        execute!(t2, r2; turns=6)
        a2 = attrs(p2, "moments/m")
        @test a2.rows_valid == 6 && a2.rows_valid_through_turn == 5
        HDF5.h5open(p2, "r+") do f
            d = f["moments/m/data"]
            n, c = size(d)
            HDF5.set_extent_dims(d, (n + 2, c))
        end
        @test disk_turns(p2, "moments/m") == [0, 1, 2, 3, 4, 5, 0, 0]   # the fill rows ARE on disk
        # (3) F-59: every reader applies the cursor; the raw count is the
        # table of contents' `rows_on_disk`.
        mo2 = MomentOutput(p2; name="m")
        @test read(mo2, :turn) == collect(0:5)                          # was 0:5 followed by [0, 0]
        @test size(read(mo2), 1) == 6
        @test size(read(mo2; orders=1), 1) == 6
        @test read(mo2, :record_count) == 6                             # was 8
        @test read(TaskOutput(p2), :moments; name="m").turn == collect(0:5)
        @test read(TaskOutput(p2), :moments; name="m", column=:turn) == collect(0:5)
        @test read(TaskOutput(p2), :moments)["m"].turn == collect(0:5)
        @test read(TaskOutput(p2), :all).moments["m"].turn == collect(0:5)
        let toc = read(TaskOutput(p2))["moments"]["m"]
            @test toc.rows == 6 && toc.rows_on_disk == 8                # was rows 8, no rows_on_disk
        end
        execute!(t2, r2; turns=2, start_turn=6)
        @test disk_turns(p2, "moments/m") == collect(0:7)             # was [0,1,2,3,4,5,0,0,6,7]
        a2b = attrs(p2, "moments/m")
        @test a2b.rows_valid == 8 && a2b.rows_valid_through_turn == 7

        # The luminosity channel takes the same rule (F-59's shape: rows on
        # disk beyond the cursor read as data). A weak-strong thin strong beam
        # with the particle on its axis writes a row every turn.
        sb = GaussianStrongBeamSpec(; kbb=1.0e-4, beta=(1.0, 1.0), sigma=(1.0e-3, 1.0e-3), klum=1.0, ns=1)
        p3 = joinpath(dir, "lum_tail.h5")
        t3 = TrackingTask((sb, DriftSpec(L=1.0)); artifact=RunArtifact(p3; append=true, capacity=2))
        axis() = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
        execute!(t3, axis(); turns=5)
        a3 = attrs(p3, "luminosity/strong_beam_1")
        @test a3.rows_valid == 5 && a3.rows_valid_through_turn == 4
        HDF5.h5open(p3, "r+") do f
            g = f["luminosity/strong_beam_1"]
            n = length(g["turns"])
            HDF5.set_extent_dims(g["turns"], (n + 3,))
            HDF5.set_extent_dims(g["values"], (n + 3,))
        end
        @test read(TaskOutput(p3), :luminosity; name="strong_beam_1").turn == collect(0:4)   # was 0:4 + [0,0,0]
        @test read(TaskOutput(p3), :luminosity)["strong_beam_1"].turn == collect(0:4)
        let ltoc = read(TaskOutput(p3))["luminosity"]["strong_beam_1"]
            @test ltoc.rows == 5 && ltoc.rows_on_disk == 8
        end
        execute!(t3, axis(); turns=2, start_turn=5)
        @test HDF5.h5open(f -> read(f["luminosity/strong_beam_1/turns"]), p3, "r") == collect(0:6)  # was [0,1,2,3,4,0,0,0,5,6]
        @test attrs(p3, "luminosity/strong_beam_1").rows_valid == 7

        # (4) F-63: a group whose cursor is absent is refused BY NAME on the
        # append-open, as found -- never truncated to zero rows -- and the
        # lock leaves with the refusal. Readers have no cursor to apply and
        # read the rows as they stand, saying so.
        p4 = joinpath(dir, "no_cursor.h5")
        m4 = MomentObserver(; name="m", orders=1)
        t4 = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(m4),),
                          artifact=RunArtifact(p4; append=true))
        execute!(t4, plain(); turns=10)
        HDF5.h5open(p4, "r+") do f
            # conditional, so the unfixed tree (no `rows_valid` yet) reaches the pins
            for attr in ("rows_valid", "rows_valid_through_turn")
                haskey(HDF5.attributes(f["moments/m"]), attr) && HDF5.delete_attribute(f["moments/m"], attr)
            end
        end
        err4 = try; execute!(t4, plain(); turns=1, start_turn=1000); nothing; catch e; e; end
        msg4 = err4 === nothing ? "did not throw" : sprint(showerror, err4)
        @test err4 isa ArgumentError && occursin("/moments/m", msg4) && occursin("rows_valid", msg4)   # was: no refusal
        @test disk_turns(p4, "moments/m") == collect(0:9)             # was truncated to 0 rows
        @test !isfile(p4 * ".lock")
        @test (@test_logs (:warn, r"carries no row cursor") match_mode=:any read(MomentOutput(p4; name="m"), :record_count)) == 10
        @test (@test_logs (:warn, r"carries no row cursor") match_mode=:any read(TaskOutput(p4), :moments; name="m").turn) == collect(0:9)

        # A file written under the turn-keyed convention (before 2026-10-19):
        # the turn cursor present, the row cursor absent. Refused by name under
        # append=true, with the remedy; read as it stands with a warning.
        p5 = joinpath(dir, "old_convention.h5")
        m5 = MomentObserver(; name="m", orders=1)
        t5 = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(m5),),
                          artifact=RunArtifact(p5; append=true))
        execute!(t5, plain(); turns=10)
        HDF5.h5open(p5, "r+") do f
            haskey(HDF5.attributes(f["moments/m"]), "rows_valid") &&
                HDF5.delete_attribute(f["moments/m"], "rows_valid")
        end
        @test attrs(p5, "moments/m").rows_valid_through_turn == 9
        err5 = try; execute!(t5, plain(); turns=1, start_turn=1000); nothing; catch e; e; end
        msg5 = err5 === nothing ? "did not throw" : sprint(showerror, err5)
        @test err5 isa ArgumentError && occursin("/moments/m", msg5) &&
              occursin("predates the row-indexed cursor (2026-10-19)", msg5) && occursin("append=false", msg5)
        @test disk_turns(p5, "moments/m") == collect(0:9)
        @test !isfile(p5 * ".lock")
        @test (@test_logs (:warn, r"predates the row-indexed cursor") match_mode=:any read(TaskOutput(p5), :moments; name="m").turn) == collect(0:9)
        @test (@test_logs (:warn, r"predates the row-indexed cursor") match_mode=:any read(MomentOutput(p5; name="m"), :record_count)) == 10

        # A group created and never flushed carries the no-rows sentinel alone
        # (the fresh group's shape at bind); it reads as zero valid rows with
        # no warning and continues without a refusal, after which it carries
        # the pair.
        p6 = joinpath(dir, "never_fired.h5")
        m6 = MomentObserver(; name="never", orders=1)
        t6 = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(m6, AtTurns([100])),),
                          artifact=RunArtifact(p6; append=true))
        Test.collect_test_logs() do        # the unfireable-schedule warning is not under test here
            execute!(t6, plain(); turns=3)
        end
        a6 = attrs(p6, "moments/never")
        @test a6.rows_valid_through_turn == no_turn && !haskey(a6, :rows_valid)
        @test (@test_logs size(read(MomentOutput(p6; name="never")))) == (0, 7)
        @test (@test_logs read(TaskOutput(p6))["moments"]["never"].rows) == 0
        Test.collect_test_logs() do
            execute!(t6, plain(); turns=3, start_turn=3)
        end
        a6b = attrs(p6, "moments/never")
        @test a6b.rows_valid == 0 && a6b.rows_valid_through_turn == no_turn

        # A cursor claiming rows the dataset does not hold is torn: refused by
        # name under append=true; the readers read as far as the rows on disk,
        # saying so.
        p7 = joinpath(dir, "cursor_ahead.h5")
        m7 = MomentObserver(; name="m", orders=1)
        t7 = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(m7),),
                          artifact=RunArtifact(p7; append=true))
        execute!(t7, plain(); turns=4)
        HDF5.h5open(p7, "r+") do f
            Octopus._ra_set_attr!(f["moments/m"], "rows_valid", Int64(9))
        end
        err7 = try; execute!(t7, plain(); turns=1, start_turn=4); nothing; catch e; e; end
        msg7 = err7 === nothing ? "did not throw" : sprint(showerror, err7)
        @test err7 isa ArgumentError && occursin("/moments/m", msg7) && occursin("rows_valid = 9", msg7)
        @test disk_turns(p7, "moments/m") == collect(0:3)
        @test (@test_logs (:warn, r"rows_valid = 9") match_mode=:any read(MomentOutput(p7; name="m"), :record_count)) == 4

        # (5) The guard on the cursor's in-place rewrite: an attribute of the
        # same type is rewritten in place and reads back in the same session
        # (the production route, every cursor advance); a type change takes
        # the delete-and-create route, read here after a reopen. Measured
        # 2026-10-19 (result/fix_batch_2026_10_19/probes/T/p1_attr_type_change.jl):
        # an in-place write of 2.5 over an Int64 attribute CONVERTS to 2, and
        # a by-name read in the session that deleted and recreated an
        # attribute returns the OLD value while an earlier read's handle is
        # still open (HDF5.jl closes attribute handles at GC) -- the right
        # value after a reopen. One attribute of the name remains either way.
        pattr = joinpath(dir, "attr.h5")
        HDF5.h5open(pattr, "w") do f
            g = HDF5.create_group(f, "g")
            Octopus._ra_set_attr!(g, "c", Int64(1))
            Octopus._ra_set_attr!(g, "c", Int64(2))
            @test read(HDF5.attributes(g)["c"]) === Int64(2)
            Octopus._ra_set_attr!(g, "c", 2.5)
        end
        HDF5.h5open(pattr, "r+") do f
            @test read(HDF5.attributes(f["g"])["c"]) === 2.5
            @test collect(keys(HDF5.attributes(f["g"]))) == ["c"]
            Octopus._ra_set_attr!(f["g"], "c", "s")
        end
        HDF5.h5open(pattr, "r") do f
            @test read(HDF5.attributes(f["g"])["c"]) == "s"
            @test collect(keys(HDF5.attributes(f["g"]))) == ["c"]
        end
    end
end
@testset "The run artifact records turn-modulation provenance" begin
    # docs/design/turn_modulation.md, D7 (owner, 2026-10-12): the table rule
    # owns its provenance in the run artifact. /turn_modulation/<slot> holds,
    # for every execute! (ledger row) whose line had a modulated element, one
    # group per modulated element in line order with its ACTIVE slots and the
    # rule's identity as attributes; nothing is ever deleted, an unmodulated
    # execute! writes nothing for its slot, a strong-strong run records both
    # beams, and a torn group is refused by name.
    mkp() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    table = TurnTable(collect(0.001:0.001:0.010); name="amp")
    crab = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,),
                                 phase_noise=(WhiteNoise(1.0e-2; rng_id=7),),
                                 strength_noise=(table,))
    disp = CrabDispersionSpec{Float64}(zeta1=0.1)
    p = tempname() * ".h5"
    t = TrackingTask((crab, disp); artifact=RunArtifact(p; append=true))
    execute!(t, mkp(); turns=2)
    execute!(t, mkp(); turns=3)          # continues at turn 2: ledger rows 1 and 2
    p_clean = tempname() * ".h5"          # the intact two-slot file, for the torn copies below
    cp(p, p_clean)
    prov = turn_modulation_provenance(p)
    @test length(prov) == 2
    @test [e.execution for e in prov] == [1, 2]
    Octopus.HDF5.h5open(p, "r") do f
        @test read(f["execution"]["start_turn"]) == [0, 2]   # the slots ARE the ledger rows
        @test sort(collect(keys(f["turn_modulation"]))) == ["1", "2"]
        @test read(Octopus.HDF5.attributes(f["turn_modulation"]["1"])["element_count"]) == 1
        @test sort(collect(keys(f["turn_modulation"]["1"]["1"]))) ==
              ["phase_noise[1]", "strength_noise[1]"]
    end
    for e in prov
        @test length(e.elements) == 1
        el = e.elements[1]
        @test el.element == "ThinCrabCavity"
        @test el.beam == 1
        @test length(el.slots) == 2
        @test el.slots[1].slot == "phase_noise[1]"
        @test el.slots[1].kind === :white
        @test el.slots[1].rng_id == 7
        @test el.slots[2].slot == "strength_noise[1]"
        @test el.slots[2].kind === :table
        @test el.slots[2].length == 10
        @test el.slots[2].digest == table.digest
        @test el.slots[2].name == "amp"
    end
    # The TaskOutput handle serves the same vector; the table of contents and
    # :all read with the group present.
    out = TaskOutput(p)
    @test read(out, :turn_modulation) == prov
    @test haskey(read(out), "turn_modulation")
    @test read(out, :all).turn_modulation == prov
    # An UNMODULATED task continuing the file adds a ledger row but no entry;
    # the two earlier entries stay (nothing is ever deleted).
    t0 = TrackingTask((DriftSpec(L=1.0),); artifact=RunArtifact(p; append=true))
    Test.collect_test_logs() do          # the second-live-writer warning (U7-10)
        execute!(t0, mkp(); turns=1, start_turn=5)
    end
    @test length(read(TaskOutput(p), :execution).start_turn) == 3
    @test turn_modulation_provenance(p) == prov
    # A torn group is refused by name, never read short: a missing count ...
    Octopus.HDF5.h5open(p, "r+") do f
        Octopus.HDF5.delete_attribute(f["turn_modulation"]["2"], "element_count")
    end
    err = try turn_modulation_provenance(p); nothing catch e; e end
    @test err !== nothing && occursin("torn", sprint(showerror, err))
    @test err isa ArgumentError
    # ... and a count that disagrees with the groups present.
    Octopus.HDF5.h5open(p, "r+") do f
        Octopus.HDF5.attributes(f["turn_modulation"]["2"])["element_count"] = Int64(1)
        g = f["turn_modulation"]["1"]["1"]
        Octopus.HDF5.delete_attribute(g, "slot_count")
        Octopus.HDF5.attributes(g)["slot_count"] = Int64(3)
    end
    err = try turn_modulation_provenance(p); nothing catch e; e end
    @test err !== nothing && occursin("torn", sprint(showerror, err))
    @test err isa ArgumentError
    # ... and a NON-count attribute missing from a slot or an element group
    # (the writer sets them one by one, so an interruption between two of them
    # leaves this shape): refused as torn by the same message shape, naming the
    # group and the attribute, on every reader path -- where a bare attribute
    # read surfaced `KeyError: key "index" not found` (2026-10-13 neighbour
    # audit, U5-1).
    for (grp, attr) in (("1/1/phase_noise[1]", "index"), ("1/1/strength_noise[1]", "digest"),
                        ("2/1/phase_noise[1]", "kind"), ("1/1", "element"), ("2/1", "beam"))
        p_attr = tempname() * ".h5"
        cp(p_clean, p_attr)
        Octopus.HDF5.h5open(p_attr, "r+") do f
            Octopus.HDF5.delete_attribute(f["turn_modulation"][grp], attr)
        end
        for (route, reader) in (("provenance", () -> turn_modulation_provenance(p_attr)),
                                ("read_kind", () -> read(TaskOutput(p_attr), :turn_modulation)),
                                ("toc", () -> read(TaskOutput(p_attr))))
            err_attr = try reader(); nothing catch e; e end
            msg_attr = err_attr === nothing ? "" : sprint(showerror, err_attr)
            @testset let torn_group = grp, missing_attribute = attr, reader_route = route
                @test err_attr isa ArgumentError
                @test occursin("torn", msg_attr)
                @test occursin("/turn_modulation/" * grp, msg_attr)
                @test occursin(attr, msg_attr)
            end
        end
        rm(p_attr; force=true)
    end
    # A `/turn_modulation/<n+1>` group already present when execute! prepares
    # row n+1 (a file whose ledger and provenance disagree) is refused BEFORE
    # the ledger row is appended, so the refused call leaves the ledger as it
    # found it, the stored turn at 0 and the file closed; before, the four
    # ledger datasets were extended first and the refusal left a phantom row
    # the reader paired with the stranger group (2026-10-13 neighbour audit,
    # U5-3: measured `start_turn = [0, 1]`, provenance `[(1, 2), (2, 0)]`).
    p_ph = tempname() * ".h5"
    cp(p_clean, p_ph)
    Octopus.HDF5.h5open(p_ph, "r+") do f
        g = Octopus.HDF5.create_group(f["turn_modulation"], "3")
        Octopus.HDF5.attributes(g)["element_count"] = Int64(0)
    end
    ledger_before = read(TaskOutput(p_ph), :execution)
    @test length(ledger_before.start_turn) == 2
    t_ph = TrackingTask((crab, disp); artifact=RunArtifact(p_ph; append=true))
    _, err_ph = Test.collect_test_logs() do
        try execute!(t_ph, mkp(); turns=2, start_turn=5); nothing catch e; e end
    end
    @test err_ph isa ArgumentError
    @test err_ph !== nothing && occursin("/turn_modulation/3", sprint(showerror, err_ph))
    @test read(TaskOutput(p_ph), :execution) == ledger_before
    @test t_ph.next_turn[] == 0
    @test t_ph.artifact.file === nothing
    @test [(e.execution, length(e.elements)) for e in turn_modulation_provenance(p_ph)] ==
          [(1, 1), (2, 1), (3, 0)]
    # An UNMODULATED execute! claims no slot group, so the stranger group does
    # not refuse it: its row is appended, the ledger grows by one.
    t_ph0 = TrackingTask((DriftSpec(L=1.0),); artifact=RunArtifact(p_ph; append=true))
    Test.collect_test_logs() do
        execute!(t_ph0, mkp(); turns=1, start_turn=5)
    end
    @test length(read(TaskOutput(p_ph), :execution).start_turn) == 3
    rm(p_ph; force=true)
    # An unmodulated run writes no group; the reader answers with an empty
    # vector (no execute! recorded in the file had a modulated element) ...
    p2 = tempname() * ".h5"
    execute!(TrackingTask((DriftSpec(L=1.0),); artifact=RunArtifact(p2)), mkp(); turns=1)
    @test isempty(turn_modulation_provenance(p2))
    @test isempty(read(TaskOutput(p2), :turn_modulation))
    Octopus.HDF5.h5open(p2, "r") do f
        @test !haskey(f, "turn_modulation")
    end
    # The single-product kinds on a file LACKING their group answer like the
    # named kinds, an `ArgumentError` naming what is present, where `:losses`
    # and `:execution` surfaced a raw HDF5 `KeyError` because their dispatch
    # returned before `_ra_require_group` (pre-existing; 2026-10-13 neighbour
    # audit, U5-7). The drift-only artifact has no /losses; a hand-made file
    # with only /luminosity has no /execution.
    err_l = try read(TaskOutput(p2), :losses); nothing catch e; e end
    @test err_l isa ArgumentError
    @test err_l !== nothing && occursin("carries no losses", sprint(showerror, err_l)) &&
          occursin("execution", sprint(showerror, err_l))
    err_m = try read(TaskOutput(p2), :moments); nothing catch e; e end   # the named-kind precedent
    @test err_m isa ArgumentError && occursin("carries no moments", sprint(showerror, err_m))
    p4 = tempname() * ".h5"
    Octopus.HDF5.h5open(p4, "w") do f
        Octopus.HDF5.create_group(f, "luminosity")
    end
    err_e = try read(TaskOutput(p4), :execution); nothing catch e; e end
    @test err_e isa ArgumentError
    @test err_e !== nothing && occursin("carries no execution", sprint(showerror, err_e)) &&
          occursin("luminosity", sprint(showerror, err_e))
    @test collect(keys(read(TaskOutput(p4)))) == ["luminosity"]   # discovery still answers
    # ... as does a file from before the group existed.
    p3 = tempname() * ".h5"
    Octopus.HDF5.h5open(p3, "w") do f
        Octopus.HDF5.create_group(f, "execution")
    end
    @test isempty(turn_modulation_provenance(p3))
    # A strong-strong run applies the modulation in both lines (shared
    # segment executor), so it records the receipt and the group with the
    # `beam` field: beam 1's entries first, then beam 2's.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(64, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
    end
    cav(rng_id) = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,),
                                        phase_noise=(WhiteNoise(1.0e-2; rng_id=rng_id),))
    ip = StrongStrongCollision(:ip)
    pss = tempname() * ".h5"
    tss = StrongStrongTask((ip, cav(11)), (ip, cav(12)); artifact=pss)
    audit = ExecutionAudit()
    b1, b2 = mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9)
    with_execution_audit(audit) do
        execute!(tss, b1, b2; turns=2)
    end
    receipts = filter(r -> r.consumer === :turn_modulation, execution_receipts(audit))
    @test length(receipts) == 1
    rcpt = only(receipts).values
    @test [e.beam for e in rcpt.elements] == [1, 2]
    @test all(e.element == "ThinCrabCavity" for e in rcpt.elements)
    @test [e.slots[1].rng_id for e in rcpt.elements] == [11, 12]
    @test rcpt.first_turn == 0 && rcpt.turns == 2
    pss_prov = turn_modulation_provenance(pss)
    @test length(pss_prov) == 1 && pss_prov[1].execution == 1
    @test [e.beam for e in pss_prov[1].elements] == [1, 2]
    @test [e.slots[1].rng_id for e in pss_prov[1].elements] == [11, 12]
    # Two beams' cavities sharing an rng_id draw identical offsets: the
    # constructor warns once; distinct ids are silent.
    @test_logs (:warn, r"share an rng_id") match_mode = :any StrongStrongTask(
        (ip, cav(11)), (ip, cav(11)))
    @test_logs StrongStrongTask((ip, cav(11)), (ip, cav(12)))
    foreach(x -> rm(x; force=true), (p, p_clean, p2, p3, p4, pss))
end
@testset "Neighbour audit 2026-10-16: the ledger stamps at every flush, a prepare refusal closes the artifact, the seed keyword refuses, radiation streams span both strong-strong lines" begin
    # docs/history/audit_crab_cavity_noise_neighbours_2026_10_16.md, findings
    # U5-1, U5-2, U3-1 and S1-3. Each pin failed on the pre-fix tree (the
    # auditor's probe: 8 of 10 red on 3126908, all green after the fixes).
    mktempdir() do dir
        set_global_rng!(seed=0x5eed, method=:philox)
        ip = StrongStrongCollision(:ip)
        mkp() = Phase6DRep([1.0e-4], [0.0], [3.0e-5], [0.0], [1.0e-2], [0.0])
        crab(rng, rules) = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,),
                                                 phase_noise=rules, tracking_method=Symplectic6DMap())
        # (a) U3-1: the retired seed keyword refuses by name, naming the
        # replacement, on both task kinds; the value used to be IGNORED after
        # a deprecation warning (coordinates bitwise identical for any seed).
        for f in (() -> TrackingTask((DriftSpec(L=1.0),); seed=1),
                  () -> StrongStrongTask((ip, DriftSpec(L=1.0)), (ip, DriftSpec(L=1.0)); seed=1))
            err = try; f(); "did not throw" catch e; sprint(showerror, e) end
            @test occursin("retired", err) && occursin("set_global_rng!", err)
        end
        # (b) S1-3: the radiation duplicate-stream warning spans both
        # strong-strong lines, as the turn-modulation one does; distinct ids
        # are silent. Before the fix the constructor never called it. The ids
        # sit above the registry's counter AND above every literal id of the
        # suite: the registry warns once when a class first claims an id an
        # auto-assigned consumer or another class holds (fix group C,
        # 2026-10-16), so a small literal id in a strict silence pin meets
        # the memory of whatever ran before, and an id merely above the
        # counter meets a later testset's literal in a short process.
        rad_base = Octopus._unheld_rng_id(Octopus.next_rng_id!() + 1_000_000)
        rad(id) = LumpedRadSpec(damping_turns=(20.0, 25.0, 30.0), beta=(0.7, 0.9, 1.1),
                                alpha=(0.2, -0.1, 0.05), sigma=(1.2e-3, 0.8e-3, 2.0e-3), rng_id=id)
        @test_logs (:warn, r"share an rng_id") match_mode = :any StrongStrongTask(
            (ip, rad(rad_base)), (ip, rad(rad_base)))
        @test_logs StrongStrongTask((ip, rad(rad_base)), (ip, rad(rad_base + 1)))
        # (c) U5-1: the `/execution` ledger is persisted by EVERY flush -- the
        # probe rows and the turn-modulation series as well as the luminosity
        # channel -- so a weak-strong run without a strong beam reports its
        # progress while running and after a kill. Before the fix the first
        # two flushes left the nothing-known sentinel (-1).
        tbl = TurnTable(collect(0.001:0.001:0.064); name="amp")
        w = compile_runtime(crab(7, (tbl,)))
        entries = Octopus._turn_modulation_entries((w,), 1)
        columns = Octopus._turn_modulation_columns!(Any[], (w,))
        art = RunArtifact(joinpath(dir, "ledger.h5"); capacity=4, record_turn_modulation=true)
        Octopus.prepare_run_artifact!(art, ["L"], 0, 10; turn_modulation=entries,
                                      turn_modulation_columns=columns)
        ledger() = read(art.file["execution/current_turn"])[1]
        @test ledger() == -1
        art.current_turn = 3
        key = Octopus._ra_bind_probe!(art, "moments", "m", ["turn", "x"], 0)
        Octopus.commit_run_artifact!(art)          # the window protocol since 2026-10-19 (F-56/F-58)
        Octopus._ra_push_probe_rows!(art, key, [3.0 1.0])
        @test ledger() == 3
        art.current_turn = 5
        rec = Octopus._turn_modulation_sink(art, 1)
        @test rec.owner === art
        for t in 0:3
            Octopus._tm_begin_turn!(rec)
            Octopus._record_turn_draws!(rec, (1.0t,))
            Octopus._tm_end_turn!(rec, t)
        end
        @test size(art.file["turn_modulation/1/1/series"], 1) == 4
        @test ledger() == 5
        art.current_turn = 7
        for t in 0:3
            Octopus.push_luminosity!(art, "L", t, 1.0)
        end
        @test ledger() == 7
        art.current_turn = 9
        Octopus.finalize_run_artifact!(art)
        @test read(TaskOutput(joinpath(dir, "ledger.h5")), :execution).current_turn == [9]
        # The hand-built recorder of the direct-API tests has no owner and
        # flushes without a stamp (the 8-argument constructor).
        rec0 = Octopus.TurnModulationRecorder(art.file === nothing ? Octopus.HDF5.h5open(joinpath(dir, "x.h5"), "w") : art.file,
                                              4, 1, String[], Vector{Int}[], Vector{Float64}[], 0, 0)
        @test rec0.owner === nothing
        close(rec0.file)
        # (d) U5-2: a refusal between `prepare_run_artifact!` and the turn
        # loop (a duplicate probe name) closes the artifact on the
        # strong-strong task as it always did on the weak-strong twin, so
        # the same task's next execute! and a fresh task on the same path
        # are not wedged by an open handle.
        mkb(rng_id, charge, mc2, E0) = Beam(64, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3),
            cutoff=5.0, rng_id=rng_id, charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
        b1, b2 = mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9)
        p_dss = joinpath(dir, "dup_ss.h5")
        white(rng) = (WhiteNoise(1.0e-3; rng_id=rng),)
        tss = StrongStrongTask((ip, crab(11, white(11)), ScheduledObserver(MomentObserver(; name="m", orders=1)),
                                ScheduledObserver(MomentObserver(; name="m", orders=1))),
                               (ip, crab(12, white(12))); artifact=RunArtifact(p_dss; record_turn_modulation=true))
        @test_throws ArgumentError execute!(tss, b1, b2; turns=2)
        @test tss.artifact.file === nothing
        @test isempty(tss.artifact.turn_modulation_recorders)
        fresh = StrongStrongTask((ip, crab(11, white(11))), (ip, crab(12, white(12)));
                                 artifact=RunArtifact(p_dss; record_turn_modulation=true))
        # The refused task's artifact stays registered in the path registry
        # (by object identity) but holds no open file, so the fresh task's
        # initialisation is SILENT since fix batch 3 (2026-10-21, unit G,
        # F-85; before, it warned "a second live observer ...", asserted here
        # so the suite log carried no unexplained line): the registry now
        # warns only for an earlier artifact still holding its file OPEN.
        lg_fresh, _ = Test.collect_test_logs() do
            execute!(fresh, b1, b2; turns=2)
        end
        @test count(l -> l.level >= Logging.Warn &&
                         (occursin("second live observer", string(l.message)) ||
                          occursin("still holds open", string(l.message))), lg_fresh) == 0   # was 1
        @test read(TaskOutput(p_dss), :execution).turns == [2]
        wt = TrackingTask((crab(13, white(13)), ScheduledObserver(MomentObserver(; name="m", orders=1)),
                           ScheduledObserver(MomentObserver(; name="m", orders=1)));
                          artifact=RunArtifact(joinpath(dir, "dup_ws.h5")))
        @test_throws ArgumentError execute!(wt, mkp(); turns=2)
        @test wt.artifact.file === nothing
        # (e) U5-5 and S4-6: the artifact's keyword list and its option schema
        # are one set (a fourth keyword without a schema entry passed every
        # check before this pin), and the refusals name the keyword.
        kw_method = only(m for m in methods(RunArtifact) if m.nargs == 2 && m.sig.parameters[2] <: AbstractString &&
                         !isempty(Base.kwarg_decl(m)))
        @test Set(Base.kwarg_decl(kw_method)) == Set(keys(run_artifact_option_schema()))
        for (kw, msg) in ((:(append = 1), "append"), (:(capacity = true), "capacity"),
                          (:(capacity = 2.0), "capacity"), (:(record_turn_modulation = 1), "record_turn_modulation"))
            err = try; eval(:(RunArtifact("x.h5"; $kw))); "did not throw" catch e; sprint(showerror, e) end
            @test occursin("RunArtifact $(msg)", err)
        end
        # (f) S5-1: the loss record's owner survives a garbage collection
        # between two windows. The owner was a `WeakRef` to the immutable
        # rep, cleared at the first GC: the second window then reallocated
        # the record (counts [1] again, the earlier loss "unattributed" with a
        # warning) and recompiled the line, so a spectral table changed seed
        # between windows. Now the key is the beam's storage.
        ap = ApertureSpec(shape=:rectangle, x_limit=1.5e-4, y_limit=1.0, name="tight")
        rep_l = Phase6DRep([1.0e-4, 2.0e-4], [0.0, 0.0], [3.0e-5, 0.0], [0.0, 0.0], [1.0e-2, -1.0e-2], [0.0, 0.0])
        tl = TrackingTask((ap, CrabDispersionSpec{Float64}(zeta1=0.1)))
        execute!(tl, rep_l; turns=1)
        rec1 = tl.loss_record[]
        @test Octopus.loss_counts(rec1) == [1]
        GC.gc(true)
        @test tl.loss_owner[].value !== nothing
        @test_logs execute!(tl, rep_l; turns=1)
        @test tl.loss_record[] === rec1
        @test Octopus.loss_counts(rec1) == [2]
        sl = Octopus.loss_summary(rep_l, rec1)
        @test (sl.dead, sl.logged, sl.unattributed) == (2, 2, 0)
        set_global_rng!(seed=21, method=:philox)
        p_gc = joinpath(dir, "gc.h5")
        rep_s = Phase6DRep([1.0e-4], [0.0], [3.0e-5], [0.0], [1.0e-2], [0.0])
        ts = TrackingTask((crab(5, (SpectralNoise(1.0e-4, (1 / 64, 0.5), :flat; rng_id=5, turns=64),)), ap);
                          artifact=RunArtifact(p_gc; append=true))
        execute!(ts, rep_s; turns=2)
        set_global_rng!(seed=22, method=:philox)
        GC.gc(true)
        # The table stays frozen under seed 21 (owner decision 2026-10-16,
        # fix B): the second window now SAYS so, the seed-drift warning naming
        # the slot and both seeds, rather than leaving the name as the only
        # evidence (U3-2).
        @test_logs (:warn, r"stay as synthesised") match_mode = :any execute!(ts, rep_s; turns=2)
        prov = turn_modulation_provenance(p_gc)
        @test length(prov) == 2
        @test prov[1].elements[1].slots[1].digest == prov[2].elements[1].slots[1].digest
        @test occursin("seed=21", prov[2].elements[1].slots[1].name)
        set_global_rng!(seed=0x5eed, method=:philox)
        # (g) U1-3 (localised by U9 as U9-1..3): neither turn loop walks the
        # heterogeneous entries tuple per turn any more. The per-turn plan
        # key boxed the WHOLE isbits entries tuple once per element (quadratic
        # in the line length) and the `get!` do-block copied it again, so
        # with an artifact attached an eight-type line of 40 crab cavities
        # cost about 200 kB per turn over the fast path at 1 and at 4 threads
        # (pre-fix 206,845 B at 4 threads; fixed 448); the strong-strong loop
        # paid the same per block per beam and re-copied each block at every
        # `blocks[j]` read of its heterogeneous tuple. Slopes between two
        # turn counts, so the once-per-execute! walks cancel; the strong-strong
        # pair is compared with a one-type pair of the SAME length so the
        # per-element thread overhead cancels too (what remains is the larger
        # per-element closures of the bigger elements, about 30 kB).
        crabN(N) = ThinCrabCavitySpec{N}(394.0e6; strengthX=ntuple(_ -> 2.0e-3, N),
                                        strengthY=ntuple(_ -> 5.0e-4, N), phase=ntuple(_ -> 0.1, N))
        hetero = Tuple(crabN(mod1(i, 8)) for i in 1:40)
        rep4() = Phase6DRep(collect(range(-1.0e-3, 1.0e-3; length=4)), zeros(4), zeros(4), zeros(4),
                            zeros(4), zeros(4))
        function ws_slope(task)
            r = rep4()
            execute!(task, r; turns=5); execute!(task, r; turns=5)
            a1 = @allocated execute!(task, r; turns=50)
            a2 = @allocated execute!(task, r; turns=250)
            return (a2 - a1) / 200
        end
        plain_slope = ws_slope(TrackingTask(hetero))
        rec_slope = ws_slope(TrackingTask(hetero; artifact=RunArtifact(joinpath(dir, "slope_ws.h5");
                                                                     capacity=10^6, record_turn_modulation=true)))
        @test rec_slope - plain_slope < 40_000
        mkb_s(rng_id, charge, mc2, E0) = begin
            set_global_rng!(seed=5, method=:philox)
            Beam(64, CPUThreadsExecutionPolicy(), Float64;
                beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
                charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
        end
        L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                          alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
        l6a = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
        l6b = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))
        function ss_slope(l1, l2, name)
            b1 = mkb_s(1, -1.0, EMASS_EV, 10.0e9); b2 = mkb_s(2, 1.0, PMASS_EV, 275.0e9)
            task = StrongStrongTask(l1, l2; artifact=RunArtifact(joinpath(dir, name); capacity=10^6,
                                                                 record_turn_modulation=true))
            execute!(task, b1, b2; turns=3); execute!(task, b1, b2; turns=3)
            a1 = @allocated execute!(task, b1, b2; turns=10)
            a2 = @allocated execute!(task, b1, b2; turns=30)
            return (a2 - a1) / 20
        end
        homo40 = Tuple(crabN(1) for _ in 1:40)
        homo = ss_slope((ip, homo40..., l6a), (ip, homo40..., l6b), "slope_ss_homo.h5")
        het = ss_slope((ip, hetero..., l6a), (ip, hetero..., l6b), "slope_ss_hetero.h5")
        @test het - homo < 100_000
        # The blocks are a vector, not a tuple (read once per turn, no copy);
        # since fix J (2026-10-17) the vector travels inside `StrongStrongBlocks`
        # beside the line's two tuples, indexing and iterating as it did.
        let blocks = Octopus._strong_strong_runtime_blocks(StrongStrongTask((ip, l6a), (ip, l6b)), 1)
            @test blocks isa AbstractVector{Any} && blocks.blocks isa Vector{Any}
            @test eltype(blocks) === Any && length(blocks) == 2 && blocks[2] === blocks.blocks[2]
        end
        set_global_rng!(seed=0x5eed, method=:philox)
    end
end
# A line observer whose prepare refuses the run. The observers' prepare is the
# last refusal that can stop a strong-strong run before its first turn, and
# the one the audit's probe reached (a duplicate probe name) moved into the
# artifact's own prepare in fix batch 1 (F-56/F-58), ahead of the task's
# output receipt; this observer refuses where the probe once did, so the
# receipt's position is still measured (2026-10-18 audit, U6-5).
struct ThrowingPrepareObserver <: Octopus.AbstractBeamObserver end
Octopus.prepare_observer!(::ThrowingPrepareObserver, runtime_elems) =
    throw(ArgumentError("ThrowingPrepareObserver refuses to prepare"))
@testset "The run artifact records the realised turn modulation" begin
    # docs/design/turn_modulation_record.md (2026-10-15, stage 1): the artifact
    # option `record_turn_modulation` records, turn by turn, the OFFSETS the
    # turn-modulation rules produced -- the draws of the ONE evaluation that
    # built the realised element (D5) -- as the `series` dataset beside each
    # modulated element's provenance (D7), the slots' nominals written with
    # the provenance whether or not the run records (D3), the window as the
    # receipt records it; off by default (D2) and nothing else in the file or
    # the tracking changes; the readers gain `series` and `nominal` and nothing
    # gains a new name. Parts (a)-(j) are the record note's sections 6.2 and
    # 6.3 plus the strong-strong and CUDA arms.
    table = TurnTable(collect(0.001:0.001:0.012); name="amp")
    crab = ThinCrabCavitySpec{2}(394.0e6; strengthX=(2.0e-3, 1.0e-3), strengthY=(0.0, 5.0e-4),
                                 phase=(0.1, 0.2),
                                 phase_noise=(WhiteNoise(1.0e-2; rng_id=7),
                                              PinkNoise(2.0e-3; rng_id=8, octaves=4)),
                                 strength_noise=(nothing, table))
    disp = CrabDispersionSpec{Float64}(zeta1=0.1)
    probe = ScheduledObserver(MomentObserver(; name="m", orders=1))
    line = (crab, disp, probe)
    mkp() = Phase6DRep([1.0e-4, -2.0e-4], [0.0, 0.0], [3.0e-5, 0.0], [0.0, 0.0],
                       [1.0e-2, -1.0e-2], [0.0, 0.0])
    mod_receipt(audit) = only(filter(r -> r.consumer === :turn_modulation,
                                     execution_receipts(audit))).values
    # One run: the global seed reset, the task executed under an audit, the
    # `:turn_modulation` receipt returned.
    function run(path, elements=line; turns=5, start_turn=nothing, policy=nothing,
                 rep=mkp(), kw...)
        set_global_rng!(seed=0x5eed, method=:philox)
        t = TrackingTask(elements; policy=policy, artifact=RunArtifact(path; kw...))
        audit = ExecutionAudit()
        with_execution_audit(audit) do
            execute!(t, rep; turns=turns, start_turn=start_turn)
        end
        return mod_receipt(audit)
    end
    # The hook's own replay of one slot over a window: the pure rule interface
    # with the task's context keys (the global seed and method, the absolute
    # turn) and the slot number the container hands it.
    replay(rule, slot, turns) =
        Float64[Octopus._turn_offset(rule, TrackingContext(turn=t), slot, Float64)[1] for t in turns]
    wk = compile_runtime(crab)
    labels = ["phase_noise[1]", "phase_noise[2]", "strength_noise[2]"]   # provenance order
    attr_names(obj) = sort!([String(k) for k in keys(Octopus.HDF5.attributes(obj))])
    group_names(g) = sort!([String(k) for k in keys(g)])
    bitwise(a, b) = size(a) == size(b) && all(a .=== b)
    # `sigma` and `octaves` joined the slot group 2026-10-21 (fix batch 3, unit G, F-66)
    provenance_attrs = ["digest", "index", "kind", "length", "name", "octaves", "rng_id", "sigma"]
    crab_nominals = ["nominal_phase", "nominal_strengthX", "nominal_strengthY"]

    # (a) OFF by default: no `series` dataset, the readers' `series` is
    # `nothing`, the nominals travel with the provenance (D3; the three
    # `nominal_*` attributes are the one addition to a slot group since the
    # provenance landed), the file's other groups are those of a run before
    # the option existed.
    p_off = tempname() * ".h5"
    rcpt_off = run(p_off)
    prov_off = turn_modulation_provenance(p_off)
    @test length(prov_off) == 1 && length(prov_off[1].elements) == 1
    el_off = prov_off[1].elements[1]
    @test [s.slot for s in el_off.slots] == labels
    @test all(s.series === nothing for s in el_off.slots)
    @test prov_off[1].state === nothing
    @test el_off.slots[1].nominal == (phase=0.1, strengthX=2.0e-3, strengthY=0.0)
    @test el_off.slots[2].nominal == (phase=0.2, strengthX=1.0e-3, strengthY=5.0e-4)
    @test el_off.slots[3].nominal == (phase=0.2, strengthX=1.0e-3, strengthY=5.0e-4)
    Octopus.HDF5.h5open(p_off, "r") do f
        @test group_names(f) == ["execution", "luminosity", "moments", "turn_modulation"]
        # The slot group's cursor `elements_valid_through` joined `element_count`
        # 2026-10-16 (the partial-slot decision; the receipts-and-slots testset).
        @test attr_names(f["turn_modulation"]["1"]) == ["element_count", "elements_valid_through"]
        eg = f["turn_modulation"]["1"]["1"]
        @test !haskey(eg, "series")
        @test group_names(eg) == labels
        @test attr_names(eg) == ["beam", "element", "slot_count"]
        @test attr_names(eg["phase_noise[1]"]) == sort(vcat(provenance_attrs, crab_nominals))
        @test !haskey(f["turn_modulation"]["1"], "state")
    end
    @test read(TaskOutput(p_off), :turn_modulation) == prov_off
    @test read(TaskOutput(p_off))["turn_modulation"] == prov_off   # nothing recorded: toc == read
    @test read(TaskOutput(p_off), :all).turn_modulation == prov_off

    # (b) ON: the dataset exists with `turns` rows by the active slots in
    # provenance order, its window attributes equal the receipt's, the
    # nominals equal the spec's; the provenance groups and attributes are
    # exactly those of (a).
    p_on = tempname() * ".h5"
    rcpt_on = run(p_on; record_turn_modulation=true)
    prov_on = turn_modulation_provenance(p_on)
    @test length(prov_on) == 1 && length(prov_on[1].elements) == 1
    el = prov_on[1].elements[1]
    @test [s.slot for s in el.slots] == labels
    @test all(s.series isa Vector{Float64} && length(s.series) == 5 for s in el.slots)
    @test prov_on[1].state === nothing
    Octopus.HDF5.h5open(p_on, "r") do f
        @test group_names(f) == ["execution", "luminosity", "moments", "turn_modulation"]
        eg = f["turn_modulation"]["1"]["1"]
        @test haskey(eg, "series")
        d = eg["series"]
        @test size(d) == (5, 3)
        @test eltype(d) == Float64
        a = Octopus.HDF5.attributes(d)
        @test read(a["columns"]) == labels
        @test read(a["first_turn"]) == rcpt_on.first_turn == 0
        @test read(a["turns"]) == rcpt_on.turns == 5
        @test attr_names(d) == ["columns", "first_turn", "turns"]
        # the dataset is the one addition beside the slot groups
        @test group_names(eg) == sort(vcat(labels, ["series"]))
        @test sort!([String(k) for k in keys(eg) if eg[k] isa Octopus.HDF5.Group]) == labels
        @test attr_names(eg) == ["beam", "element", "slot_count"]
        @test attr_names(f["turn_modulation"]["1"]) == ["element_count", "elements_valid_through"]
        for label in labels
            @test attr_names(eg[label]) == sort(vcat(provenance_attrs, crab_nominals))
        end
    end
    @test el.slots[1].nominal == (phase=0.1, strengthX=2.0e-3, strengthY=0.0)
    @test el.slots[2].nominal == (phase=0.2, strengthX=1.0e-3, strengthY=5.0e-4)
    @test el.slots[3].nominal == (phase=0.2, strengthX=1.0e-3, strengthY=5.0e-4)
    @test read(TaskOutput(p_on), :turn_modulation) == prov_on
    @test read(TaskOutput(p_on), :all).turn_modulation == prov_on
    # The table of contents stays metadata-only: the recorded row count stands
    # in for each column; the nominals (attributes) are there.
    toc_on = read(TaskOutput(p_on))["turn_modulation"]
    @test [s.series for s in toc_on[1].elements[1].slots] == [5, 5, 5]
    @test [s.nominal for s in toc_on[1].elements[1].slots] == [s.nominal for s in el.slots]
    @test [(s.slot, s.kind, s.rng_id) for s in toc_on[1].elements[1].slots] ==
          [(s.slot, s.kind, s.rng_id) for s in el.slots]

    # (c) BITWISE: every recorded column equals the draws the hook produces for
    # the same rule, slot and turns; the table slot's column equals the
    # record's entries over the window; and the realised values formed from
    # the recorded offsets and the stored nominals are the element's own, to
    # the bit (D3: the offset is recorded, not the realised value).
    @test el.slots[1].series == replay(wk.rule.phase[1], 1, 0:4)
    @test el.slots[2].series == replay(wk.rule.phase[2], 2, 0:4)
    @test el.slots[3].series == replay(wk.rule.strength[2], 4, 0:4)
    @test el.slots[3].series == table.offsets[1:5]
    @test el.slots[1].series != el.slots[2].series
    @test all(x -> abs(x) > 0, el.slots[1].series)
    for (i, t) in enumerate(0:4)
        realised = realize(wk.rule, wk.base, TrackingContext(turn=t))[1]
        @test realised.phase[1] === el.slots[1].nominal.phase + el.slots[1].series[i]
        @test realised.phase[2] === el.slots[2].nominal.phase + el.slots[2].series[i]
        @test realised.strengthX[2] === el.slots[3].nominal.strengthX * (1 + el.slots[3].series[i])
        @test realised.strengthY[2] === el.slots[3].nominal.strengthY * (1 + el.slots[3].series[i])
        @test realised.strengthX[1] === el.slots[1].nominal.strengthX   # the inactive strength slot
    end

    # The strength slot NUMBER (`N + i`: 4 for harmonic 2 of a two-harmonic
    # cavity, src/elements/turn_modulated.jl) is observable only through a
    # slot-keyed rule -- a `TurnTable` replays by turn alone, so the pin above
    # held for any slot number (2026-10-18 audit F-216/U34-6). A white rule on
    # that slot reproduces the recorded series at slot 4 and at no other.
    let crab_w = ThinCrabCavitySpec{2}(394.0e6; strengthX=(2.0e-3, 1.0e-3), strengthY=(0.0, 5.0e-4),
                                       phase=(0.1, 0.2), strength_noise=(nothing, WhiteNoise(1.0e-2; rng_id=9))),
        p_w = tempname() * ".h5"
        run(p_w, (crab_w, disp, probe); record_turn_modulation=true)
        el_w = turn_modulation_provenance(p_w)[1].elements[1]
        rule_w = compile_runtime(crab_w).rule.strength[2]
        @test [s.slot for s in el_w.slots] == ["strength_noise[2]"]
        @test el_w.slots[1].series == replay(rule_w, 4, 0:4)
        @test all(el_w.slots[1].series != replay(rule_w, s, 0:4) for s in (1, 2, 3))
        rm(p_w; force=true)
    end

    # (d) NO SIDE EFFECT: the moments of the run with the switch on are bitwise
    # those of the run with it off, and the ledger agrees but for `elapsed`.
    m_off = read(TaskOutput(p_off), :moments; name="m")
    m_on = read(TaskOutput(p_on), :moments; name="m")
    @test keys(m_off) == keys(m_on)
    @test length(m_on.turn) == 5
    @test all(bitwise(m_off[k], m_on[k]) for k in keys(m_off) if m_off[k] isa AbstractVector)
    ex_off, ex_on = read(TaskOutput(p_off), :execution), read(TaskOutput(p_on), :execution)
    @test ex_off.start_turn == ex_on.start_turn == [0]
    @test ex_off.turns == ex_on.turns == [5]
    @test ex_off.current_turn == ex_on.current_turn == [4]

    # (g) The receipt is identical with the switch on and off, in the shape
    # the kernel-boundary testset pins (D9: the receipts do not change).
    @test rcpt_on == rcpt_off
    @test propertynames(rcpt_on.elements[1].slots[1]) == (:slot, :kind, :rng_id, :digest, :name, :length, :sigma, :octaves)

    # (e) INVALID refused by name (an ArgumentError naming the keyword and the
    # value, as `capacity` is refused); an unknown keyword stays a
    # MethodError; the default is `false`; the structured metadata validates
    # with every other public option; the option is INACTIVE on a line with
    # no modulated element (nothing to record, nothing written, no error).
    err_e = try RunArtifact(tempname() * ".h5"; record_turn_modulation=1); nothing catch e; e end
    @test err_e isa ArgumentError
    @test err_e !== nothing && occursin("record_turn_modulation", sprint(showerror, err_e)) &&
          occursin("got 1", sprint(showerror, err_e))
    @test_throws ArgumentError RunArtifact(tempname() * ".h5"; record_turn_modulation="true")
    @test_throws ArgumentError RunArtifact(tempname() * ".h5"; record_turn_modulation=nothing)
    @test_throws MethodError RunArtifact(tempname() * ".h5"; record_turn_modulations=true)
    @test RunArtifact(tempname() * ".h5").record_turn_modulation === false
    @test RunArtifact(tempname() * ".h5"; record_turn_modulation=true).record_turn_modulation === true
    schema = run_artifact_option_schema()
    @test Set(keys(schema)) == Set((:append, :capacity, :record_turn_modulation, :storage, :machine_snapshot))   # :storage since 2026-11-03, :machine_snapshot since 2026-11-26 (R9)
    @test Set(keys(schema)) ⊆ Set(fieldnames(RunArtifact))
    @test schema.record_turn_modulation.option_type === Bool
    @test schema.record_turn_modulation.default === false
    @test schema.record_turn_modulation.category === :output
    @test schema.record_turn_modulation.consumer !== :unspecified
    @test schema.capacity.default == 64 && schema.append.default === false
    @test validate_configuration_metadata()
    p_in = tempname() * ".h5"
    set_global_rng!(seed=0x5eed, method=:philox)
    execute!(TrackingTask((disp, probe); artifact=RunArtifact(p_in; record_turn_modulation=true)),
             mkp(); turns=2)
    @test isempty(turn_modulation_provenance(p_in))
    Octopus.HDF5.h5open(p_in, "r") do f
        @test !haskey(f, "turn_modulation")
        @test group_names(f) == ["execution", "luminosity", "moments"]
    end

    # (f) CHUNKING and REPOSITIONING (6.3): two windows of 3 turns on a
    # continued artifact record two execution slots whose concatenated series
    # equals one window of 6, each slot's window attributes its own; a run
    # repositioned with `start_turn = 4` records `first_turn = 4` and the
    # entries from turn 4 on (the table's entries 5 to 8). `capacity = 2` so
    # the three turns of a window cross a flush boundary and leave a tail.
    p_c = tempname() * ".h5"
    set_global_rng!(seed=0x5eed, method=:philox)
    t_c = TrackingTask(line; artifact=RunArtifact(p_c; append=true, capacity=2,
                                                  record_turn_modulation=true))
    rep_c = mkp()
    execute!(t_c, rep_c; turns=3)
    execute!(t_c, rep_c; turns=3)
    prov_c = turn_modulation_provenance(p_c)
    @test [e.execution for e in prov_c] == [1, 2]
    p_6 = tempname() * ".h5"
    run(p_6; turns=6, record_turn_modulation=true)
    prov_6 = turn_modulation_provenance(p_6)
    for j in 1:3
        @test length(prov_c[1].elements[1].slots[j].series) == 3
        @test vcat(prov_c[1].elements[1].slots[j].series, prov_c[2].elements[1].slots[j].series) ==
              prov_6[1].elements[1].slots[j].series
    end
    Octopus.HDF5.h5open(p_c, "r") do f
        for (slot, first) in (("1", 0), ("2", 3))
            d = f["turn_modulation"][slot]["1"]["series"]
            @test size(d) == (3, 3)
            @test read(Octopus.HDF5.attributes(d)["first_turn"]) == first
            @test read(Octopus.HDF5.attributes(d)["turns"]) == 3
        end
        @test read(f["execution"]["start_turn"]) == [0, 3]
    end
    p_r = tempname() * ".h5"
    rcpt_r = run(p_r; turns=4, start_turn=4, record_turn_modulation=true)
    prov_r = turn_modulation_provenance(p_r)
    @test rcpt_r.first_turn == 4 && rcpt_r.turns == 4
    Octopus.HDF5.h5open(p_r, "r") do f
        d = f["turn_modulation"]["1"]["1"]["series"]
        @test read(Octopus.HDF5.attributes(d)["first_turn"]) == 4
        @test read(Octopus.HDF5.attributes(d)["turns"]) == 4
        @test size(d) == (4, 3)
    end
    @test prov_r[1].elements[1].slots[3].series == table.offsets[5:8]
    @test prov_r[1].elements[1].slots[1].series == replay(wk.rule.phase[1], 1, 4:7)
    @test prov_r[1].elements[1].slots[2].series == replay(wk.rule.phase[2], 2, 4:7)
    @test prov_r[1].elements[1].slots[1].series == vcat(prov_6[1].elements[1].slots[1].series[5:6],
          replay(wk.rule.phase[1], 1, 6:7))   # the overlap with the 6-turn run agrees
    # (`vcat`, not `∪`: the union would drop a repeated draw and shrink the
    # right-hand side -- 2026-10-16 neighbour audit U6-4.)

    # (h) The RF cavity by the same wrap: one phase and one strength column,
    # the nominals `(phase, strength)` of the compiled cavity.
    rf = ThinRFCavitySpec(400.8e6; voltage=12.0e6, e0=275.0e9, mc2=PMASS_EV,
                          phase_noise=WhiteNoise(1.0e-2; rng_id=21),
                          strength_noise=TurnTable([1.0e-4, 2.0e-4, 3.0e-4]; name="rf_amp"))
    p_rf = tempname() * ".h5"
    rcpt_rf = run(p_rf, (rf, DriftSpec(L=0.5)); turns=3, record_turn_modulation=true)
    prov_rf = turn_modulation_provenance(p_rf)
    el_rf = prov_rf[1].elements[1]
    w_rf = compile_runtime(rf)
    @test el_rf.element == "ThinRFCavity"
    @test [s.slot for s in el_rf.slots] == ["phase_noise", "strength_noise"]
    @test el_rf.slots[1].nominal == (phase=w_rf.base.phase, strength=w_rf.base.strength)
    @test el_rf.slots[2].nominal == el_rf.slots[1].nominal
    @test el_rf.slots[1].series == replay(w_rf.rule.phase, 1, 0:2)
    @test el_rf.slots[2].series == [1.0e-4, 2.0e-4, 3.0e-4]
    @test rcpt_rf.first_turn == 0 && rcpt_rf.turns == 3
    Octopus.HDF5.h5open(p_rf, "r") do f
        d = f["turn_modulation"]["1"]["1"]["series"]
        @test size(d) == (3, 2)
        @test read(Octopus.HDF5.attributes(d)["columns"]) == ["phase_noise", "strength_noise"]
        @test attr_names(f["turn_modulation"]["1"]["1"]["phase_noise"]) ==
              sort(vcat(provenance_attrs, ["nominal_phase", "nominal_strength"]))
    end

    # (i) STRONG-STRONG: a modulated cavity on each beam records two labelled
    # element groups per execution slot (the provenance testset's fixture),
    # each series the replay of its own stream; the luminosity is bitwise with
    # the switch off and the receipt identical.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(64, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
    end
    cav(rng_id) = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,),
                                        phase_noise=(WhiteNoise(1.0e-2; rng_id=rng_id),))
    ip = StrongStrongCollision(:ip)
    out_receipt(audit) = only(filter(r -> r.consumer === :strong_strong_output,
                                     execution_receipts(audit))).values
    function ss_run(path; kw...)
        tss = StrongStrongTask((ip, cav(11)), (ip, cav(12)); artifact=RunArtifact(path; kw...))
        b1, b2 = mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9)
        audit = ExecutionAudit()
        with_execution_audit(audit) do
            execute!(tss, b1, b2; turns=2)
        end
        return mod_receipt(audit), out_receipt(audit)
    end
    pss_on, pss_off = tempname() * ".h5", tempname() * ".h5"
    rc_on, orc_on = ss_run(pss_on; record_turn_modulation=true)
    rc_off, orc_off = ss_run(pss_off)
    @test rc_on == rc_off
    # The task's output receipt carries the path and the collision labels the
    # artifact's luminosity channels opened with; the option's declared
    # consumer is the `:run_artifact_output` receipt the prepare records with
    # the request AND what it resolved (2026-10-16 fix batch, S4-2: until
    # then this receipt carried `append` and `record_turn_modulation` as
    # requested, before the prepare decided anything; the receipts-and-slots
    # testset derives the option-to-receipt pairs from the schemas).
    @test propertynames(orc_on) == (:artifact, :channels)
    @test orc_on.artifact == pss_on && orc_off.artifact == pss_off
    @test orc_on.channels == orc_off.channels == ["ip"]
    @test run_artifact_option_schema().record_turn_modulation.consumer === :run_artifact_output
    @test run_artifact_option_schema().append.consumer === :run_artifact_output
    prov_ss = turn_modulation_provenance(pss_on)
    @test length(prov_ss) == 1 && length(prov_ss[1].elements) == 2
    @test [e.beam for e in prov_ss[1].elements] == [1, 2]
    for (k, rng_id) in ((1, 11), (2, 12))
        s = prov_ss[1].elements[k].slots[1]
        @testset let beam = k
            @test s.slot == "phase_noise[1]" && s.rng_id == rng_id
            @test s.series == replay(compile_runtime(cav(rng_id)).rule.phase[1], 1, 0:1)
            @test s.nominal == (phase=0.0, strengthX=2.0e-3, strengthY=0.0)
        end
    end
    @test prov_ss[1].elements[1].slots[1].series != prov_ss[1].elements[2].slots[1].series
    @test all(s.series === nothing for e in turn_modulation_provenance(pss_off)[1].elements for s in e.slots)
    lum_on = read(TaskOutput(pss_on), :luminosity; name="ip")
    lum_off = read(TaskOutput(pss_off), :luminosity; name="ip")
    @test lum_on.turn == lum_off.turn == [0, 1]
    @test bitwise(lum_on.value, lum_off.value)
    Octopus.HDF5.h5open(pss_on, "r") do f
        @test size(f["turn_modulation"]["1"]["1"]["series"]) == (2, 1)
        @test size(f["turn_modulation"]["1"]["2"]["series"]) == (2, 1)
        @test read(Octopus.HDF5.attributes(f["turn_modulation"]["1"]["2"])["beam"]) == 2
    end
    # ...and the strong-strong configuration report names the recording where
    # it names the artifact's other options.
    tss_report = StrongStrongTask((ip, cav(11)), (ip, cav(12));
                                  artifact=RunArtifact(pss_on; record_turn_modulation=true))
    report = configuration_report(tss_report, mkb(1, -1.0, EMASS_EV, 10.0e9),
                                  mkb(2, 1.0, PMASS_EV, 275.0e9))
    @test occursin("recording the turn-modulation series", only(report.output).reason)
    @test !occursin("recording", only(configuration_report(
        StrongStrongTask((ip, cav(11)), (ip, cav(12)); artifact=pss_off),
        mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9)).output).reason)
    # Only ONE beam modulated, either beam (review F4, 2026-10-15; the
    # reviewer's probe P1): one element group tagged with the modulated beam,
    # one recorder, its series the replay of that beam's stream over the
    # window; `capacity = 2` over 3 turns, so the tail flush is exercised.
    cav_plain() = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,))
    for (beam, rng_id, line1, line2) in ((1, 11, (ip, cav(11)), (ip, cav_plain())),
                                         (2, 12, (ip, cav_plain()), (ip, cav(12))))
        p_one = tempname() * ".h5"
        tss_one = StrongStrongTask(line1, line2;
                                   artifact=RunArtifact(p_one; capacity=2, record_turn_modulation=true))
        execute!(tss_one, mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9); turns=3)
        prov_one = turn_modulation_provenance(p_one)
        @testset let modulated_beam = beam
            @test length(prov_one) == 1 && length(prov_one[1].elements) == 1
            el_one = prov_one[1].elements[1]
            @test el_one.beam == beam && el_one.element == "ThinCrabCavity"
            @test el_one.first_turn == 0 && el_one.turns == 3
            @test [s.slot for s in el_one.slots] == ["phase_noise[1]"]
            @test el_one.slots[1].rng_id == rng_id
            @test el_one.slots[1].series == replay(compile_runtime(cav(rng_id)).rule.phase[1], 1, 0:2)
            Octopus.HDF5.h5open(p_one, "r") do f
                @test sort(collect(String.(keys(f["turn_modulation"]["1"])))) == ["1"]
                @test read(Octopus.HDF5.attributes(f["turn_modulation"]["1"]["1"])["beam"]) == beam
                @test size(f["turn_modulation"]["1"]["1"]["series"]) == (3, 1)
            end
        end
        rm(p_one; force=true)
    end

    # A series SHORTER than its `turns` attribute is a run stopped before its
    # window completed (killed, or interrupted between two flushes; the
    # reviewer's probe P6, which such a file answered silently): the row count
    # is authoritative, the rows are read as they stand, ONE warning names the
    # dataset on every reader path, and the element entry carries the window
    # the attributes declare (`first_turn`, `turns`; `nothing` when the run did
    # not record). The intact file reads silently with the same window
    # (review F2, 2026-10-15).
    @test propertynames(el) == (:element, :beam, :first_turn, :turns, :slots)
    @test el.first_turn == 0 && el.turns == 5
    @test el_off.first_turn === nothing && el_off.turns === nothing
    @test toc_on[1].elements[1].first_turn == 0 && toc_on[1].elements[1].turns == 5
    @test_logs turn_modulation_provenance(p_on)
    p_short = tempname() * ".h5"
    cp(p_on, p_short)
    Octopus.HDF5.h5open(p_short, "r+") do f
        Octopus.HDF5.set_extent_dims(f["turn_modulation"]["1"]["1"]["series"], (1, 3))
    end
    short_warning = r"/turn_modulation/1/1/series holds 1 recorded turn\(s\) of the 5 its turns attribute declares \(first_turn 0\)"
    prov_short = @test_logs (:warn, short_warning) turn_modulation_provenance(p_short)
    el_short = prov_short[1].elements[1]
    @test el_short.first_turn == 0 && el_short.turns == 5
    @test [s.slot for s in el_short.slots] == labels
    @test all(length(s.series) == 1 for s in el_short.slots)
    @test [s.series[1] for s in el_short.slots] == [s.series[1] for s in el.slots]
    @test [s.nominal for s in el_short.slots] == [s.nominal for s in el.slots]
    toc_short = @test_logs (:warn, short_warning) read(TaskOutput(p_short))["turn_modulation"]
    @test [s.series for s in toc_short[1].elements[1].slots] == [1, 1, 1]
    @test toc_short[1].elements[1].first_turn == 0 && toc_short[1].elements[1].turns == 5
    @test (@test_logs (:warn, short_warning) read(TaskOutput(p_short), :turn_modulation)) == prov_short
    rm(p_short; force=true)

    # The reserved `state` group (D10) is skipped by the element count and
    # read as `nothing`; a torn series -- a missing `columns`, `first_turn` or
    # `turns` attribute, a slot group without its nominals although the
    # element recorded, a `columns` attribute that does not name the slot
    # groups -- is refused by name on every reader path, as the existing
    # attributes are.
    p_st = tempname() * ".h5"
    cp(p_on, p_st)
    Octopus.HDF5.h5open(p_st, "r+") do f
        Octopus.HDF5.create_group(f["turn_modulation"]["1"], "state")
    end
    @test turn_modulation_provenance(p_st) == prov_on
    @test read(TaskOutput(p_st))["turn_modulation"] == toc_on
    # (the nominal case removes the whole `nominal_*` family of one slot group,
    # and the message names the family)
    torn_cases = Any[(("1/1/series", "columns"), p_on), (("1/1/series", "first_turn"), p_on),
                     (("1/1/series", "turns"), p_on), (("1/1/phase_noise[2]", "nominal_"), p_on)]
    for ((grp, attr), src) in torn_cases
        p_a = tempname() * ".h5"
        cp(src, p_a)
        Octopus.HDF5.h5open(p_a, "r+") do f
            obj = f["turn_modulation"][grp]
            if startswith(attr, "nominal_")
                for n in attr_names(obj)
                    startswith(n, "nominal_") && Octopus.HDF5.delete_attribute(obj, n)
                end
            else
                Octopus.HDF5.delete_attribute(obj, attr)
            end
        end
        for (route, reader) in (("provenance", () -> turn_modulation_provenance(p_a)),
                                ("read_kind", () -> read(TaskOutput(p_a), :turn_modulation)),
                                ("toc", () -> read(TaskOutput(p_a))))
            err_a = try reader(); nothing catch e; e end
            msg_a = err_a === nothing ? "" : sprint(showerror, err_a)
            @testset let torn_group = grp, missing_attribute = attr, reader_route = route
                @test err_a isa ArgumentError
                @test occursin("torn", msg_a)
                @test occursin("/turn_modulation/" * grp, msg_a)
                @test occursin(attr, msg_a)
            end
        end
        rm(p_a; force=true)
    end
    p_cols = tempname() * ".h5"
    cp(p_on, p_cols)
    Octopus.HDF5.h5open(p_cols, "r+") do f
        d = f["turn_modulation"]["1"]["1"]["series"]
        Octopus.HDF5.delete_attribute(d, "columns")
        Octopus.HDF5.attributes(d)["columns"] = ["phase_noise[2]", "phase_noise[1]", "strength_noise[2]"]
    end
    err_c = try turn_modulation_provenance(p_cols); nothing catch e; e end
    @test err_c isa ArgumentError
    @test err_c !== nothing && occursin("torn", sprint(showerror, err_c)) &&
          occursin("/turn_modulation/1/1/series", sprint(showerror, err_c))
    # A nominal-less slot group of an UNRECORDED element is a file from before
    # the nominals existed, not a torn one: `nominal` reads `nothing`.
    p_old = tempname() * ".h5"
    cp(p_off, p_old)
    Octopus.HDF5.h5open(p_old, "r+") do f
        obj = f["turn_modulation"]["1"]["1"]["phase_noise[1]"]
        for n in attr_names(obj)
            startswith(n, "nominal_") && Octopus.HDF5.delete_attribute(obj, n)
        end
    end
    @test turn_modulation_provenance(p_old)[1].elements[1].slots[1].nominal === nothing
    @test turn_modulation_provenance(p_old)[1].elements[1].slots[2].nominal == el_off.slots[2].nominal

    # The recorder's protocol, on a hand-built recorder over one dataset: the
    # active slots' values of each element are kept in slot order, `capacity`
    # complete turns flush, a turn that never ends (the crash path's finalize)
    # is dropped rather than written as a misaligned row, an element the
    # provenance did not list is refused by name, and a turn closed with an
    # element missing is refused with its partial values dropped.
    p_rec = tempname() * ".h5"
    Octopus.HDF5.h5open(p_rec, "w") do f
        g = Octopus.HDF5.create_group(Octopus.HDF5.create_group(
                Octopus.HDF5.create_group(f, "turn_modulation"), "1"), "1")
        d = Octopus.HDF5.create_dataset(g, "series", Octopus.HDF5.datatype(Float64),
                                        Octopus.HDF5.dataspace((0, 2); max_dims=(-1, 2)); chunk=(4, 2))
        rec = Octopus.TurnModulationRecorder(f, 2, 1, ["turn_modulation/1/1"], [[1, 3]],
                                             [Float64[]], 0, 0)
        @test Octopus._turn_modulation_sink(nothing, 1) === nothing
        Octopus._tm_begin_turn!(rec)
        Octopus._record_turn_draws!(rec, (1.0, 9.0, 2.0))
        Octopus._tm_end_turn!(rec, 0)
        @test size(d) == (0, 2) && rec.rows == 1                 # buffered, below capacity
        Octopus._tm_begin_turn!(rec)
        Octopus._record_turn_draws!(rec, (3.0, 9.0, 4.0))
        Octopus._tm_end_turn!(rec, 1)
        @test read(d) == [1.0 2.0; 3.0 4.0] && rec.rows == 0     # capacity 2: flushed
        Octopus._tm_begin_turn!(rec)
        Octopus._record_turn_draws!(rec, (5.0, 9.0, 6.0))         # a turn that never ends
        Octopus._ra_flush_turn_modulation!(rec)                   # the crash path's finalize
        @test read(d) == [1.0 2.0; 3.0 4.0] && isempty(rec.buffers[1])
        Octopus._tm_begin_turn!(rec)
        Octopus._record_turn_draws!(rec, (7.0, 9.0, 8.0))
        err_k = try Octopus._record_turn_draws!(rec, (0.0, 0.0, 0.0)); nothing catch e; e end
        @test err_k isa ErrorException
        @test err_k !== nothing && occursin("beam 1", sprint(showerror, err_k)) &&
              occursin("element 2", sprint(showerror, err_k)) &&
              occursin("lists 1", sprint(showerror, err_k))
        Octopus._tm_end_turn!(rec, 3)
        Octopus._tm_begin_turn!(rec)                              # a turn with the element missing
        err_m = try Octopus._tm_end_turn!(rec, 4); nothing catch e; e end
        @test err_m isa ErrorException
        @test err_m !== nothing && occursin("turn 4", sprint(showerror, err_m)) &&
              occursin("met 0", sprint(showerror, err_m)) && occursin("lists 1", sprint(showerror, err_m))
        Octopus._ra_flush_turn_modulation!(rec)
        @test read(d) == [1.0 2.0; 3.0 4.0; 7.0 8.0]
    end
    rm(p_rec; force=true)
    # `prepare_run_artifact!` handed a non-empty provenance with its DEFAULT
    # empty `turn_modulation_columns` -- the two walks over the line
    # disagreeing -- is refused by name, an ArgumentError naming the path and
    # both counts, and leaves the artifact closed (review F4, 2026-10-15; the
    # reviewer's probe P3).
    p_cols0 = tempname() * ".h5"
    art_cols0 = RunArtifact(p_cols0)
    err_cols0 = try
        Octopus.prepare_run_artifact!(art_cols0, String[], 0, 2;
                                      turn_modulation=Octopus._turn_modulation_entries((wk,), 1))
        nothing
    catch e
        e
    end
    msg_cols0 = err_cols0 === nothing ? "" : sprint(showerror, err_cols0)
    @test err_cols0 isa ArgumentError
    @test occursin(p_cols0, msg_cols0) && occursin("lists 1 modulated element(s)", msg_cols0) &&
          occursin("column walk lists 0", msg_cols0)
    @test art_cols0.file === nothing
    rm(p_cols0; force=true)

    # (j) CUDA: (b)-(d) on the device. The series is host-side on every
    # backend, so it is bitwise the CPU run's; the device moments of the run
    # with the switch on are bitwise those with it off.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        device(h) = Phase6DRep((Octopus.CUDA.CuArray(a) for a in coordinate_arrays(h))...)
        p_g_on, p_g_off = tempname() * ".h5", tempname() * ".h5"
        rc_g_on = run(p_g_on; policy=CUDAExecutionPolicy(), rep=device(mkp()),
                      record_turn_modulation=true)
        Octopus.CUDA.synchronize()
        rc_g_off = run(p_g_off; policy=CUDAExecutionPolicy(), rep=device(mkp()))
        Octopus.CUDA.synchronize()
        @test rc_g_on == rc_g_off == rcpt_on
        prov_g = turn_modulation_provenance(p_g_on)
        @test length(prov_g) == 1 && length(prov_g[1].elements) == 1
        @test [s.slot for s in prov_g[1].elements[1].slots] == labels
        @test [s.series for s in prov_g[1].elements[1].slots] == [s.series for s in el.slots]
        @test [s.nominal for s in prov_g[1].elements[1].slots] == [s.nominal for s in el.slots]
        @test all(s.series === nothing for s in turn_modulation_provenance(p_g_off)[1].elements[1].slots)
        Octopus.HDF5.h5open(p_g_on, "r") do f
            d = f["turn_modulation"]["1"]["1"]["series"]
            @test size(d) == (5, 3)
            @test read(Octopus.HDF5.attributes(d)["columns"]) == labels
            @test read(Octopus.HDF5.attributes(d)["first_turn"]) == 0
            @test read(Octopus.HDF5.attributes(d)["turns"]) == 5
        end
        mg_off = read(TaskOutput(p_g_off), :moments; name="m")
        mg_on = read(TaskOutput(p_g_on), :moments; name="m")
        @test keys(mg_off) == keys(mg_on)
        @test all(bitwise(mg_off[k], mg_on[k]) for k in keys(mg_off) if mg_off[k] isa AbstractVector)
        foreach(x -> rm(x; force=true), (p_g_on, p_g_off))
    else
        @test_skip "CUDA device not available"
    end
    foreach(x -> rm(x; force=true), (p_off, p_on, p_in, p_c, p_6, p_r, p_rf, pss_on, pss_off,
                                      p_st, p_cols, p_old))
end
# The in-memory run artifact (2026-11-03): the observer the testset below
# fails a run with, at top level like the suite's other test observers.
struct _MemArtifactThrowAtTurn <: Octopus.AbstractBeamObserver
    turn::Int
end
Octopus.observe!(o::_MemArtifactThrowAtTurn, ctx::Octopus.TrackingContext, rep) =
    (ctx.turn == o.turn && error("the observer failed at turn $(o.turn)"); nothing)
@testset "The run artifact in memory: storage=:memory keeps the HDF5 image in the process, save_run_artifact writes it, file mode is untouched" begin
    # 2026-11-03 (docs/design/run_artifact.md, "Artifact options", `storage`;
    # record history/in_memory_run_artifact_2026_11_03.md). Owner decisions: the
    # keyword `storage=:memory` only decides where the rows live during the
    # run; a path given beside it keeps every other meaning (the label, the
    # file `append=true` loads, the default save target); nothing is saved
    # automatically; the explicit `save_run_artifact(artifact[, path])`
    # writes the image. Shown RED on the tree before the option existed
    # (MethodError on the keyword, recorded in the history file), green here.
    mktempdir() do dir
        rep() = Phase6DRep([1.0e-4], [2.0e-5], [3.0e-5], [0.0], [1.0e-3], [0.0])
        drift = DriftSpec(L=1.0)
        probes() = (ScheduledObserver(MomentObserver(; name="m", orders=1)),
                    ScheduledObserver(CoordinateSnapshotObserver(; name="s", npart=1)),
                    ScheduledObserver(BPMObserver("b"; artifact=true)))
        pfile, pmem = joinpath(dir, "file.h5"), joinpath(dir, "mem.h5")
        audited(f) = (a = ExecutionAudit(); with_execution_audit(f, a); execution_receipts(a))
        one(rs, c) = only(filter(r -> r.consumer === c, rs)).values
        columns(t) = (; (k => v for (k, v) in pairs(t) if v isa AbstractVector)...)   # the BPM's attrs carry its own rng_id
        schemas = Pair{Symbol,Any}[:RunArtifact => run_artifact_option_schema(),
                                   :TrackingTask => tracking_task_option_schema(),
                                   :MomentObserver => observer_option_schema(MomentObserver),
                                   :CoordinateSnapshotObserver => observer_option_schema(CoordinateSnapshotObserver),
                                   :BPMObserver => observer_option_schema(BPMObserver)]

        # (a) The constructor and the metadata: `storage` is a field and a schema
        # key naming the artifact's receipt, `:file` by default, refused by name
        # otherwise; a path-less artifact needs `:memory` and carries the
        # reserved label, which a path may not spell.
        @test RunArtifact(pfile).storage === :file
        @test RunArtifact(pmem; storage=:memory).storage === :memory && RunArtifact(pmem; storage=:memory).path == pmem
        mem0 = RunArtifact(; storage=:memory)
        @test mem0.storage === :memory && mem0.path == Octopus._RA_MEMORY_LABEL && !Octopus._ra_has_path(mem0)
        for kw in (:(storage = :disk), :(storage = "memory"), :(storage = true))
            err = try; eval(:(RunArtifact($pfile; $kw))); "did not throw" catch e; sprint(showerror, e) end
            @test occursin("RunArtifact storage must be :file or :memory", err)
        end
        err0 = try; RunArtifact(); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("RunArtifact storage=:file needs a path", err0)
        @test_throws ArgumentError RunArtifact(; storage=:file)
        @test_throws ArgumentError RunArtifact(Octopus._RA_MEMORY_LABEL)
        @test_throws ArgumentError RunArtifact(; storage=:memory, capacity=0)
        schema = run_artifact_option_schema()
        @test schema.storage.default === :file && schema.storage.option_type === Symbol
        @test schema.storage.category === :output && schema.storage.consumer === :run_artifact_output
        @test :storage in fieldnames(RunArtifact) && :image in fieldnames(RunArtifact)

        # (b) The same run in both modes: every row equal, the memory run leaves
        # nothing on disk (no file, no sidecar lock), its receipts say :memory
        # and carry the path, the file run's say :file; every output option is
        # carried by its receipt under memory storage too.
        set_global_rng!(seed=0x5eed, method=:philox)
        tf = TrackingTask((drift, probes()...); artifact=RunArtifact(pfile; capacity=2))
        rs_f = audited(() -> execute!(tf, rep(); turns=5))
        set_global_rng!(seed=0x5eed, method=:philox)
        am = RunArtifact(pmem; storage=:memory, capacity=2)
        tm = TrackingTask((drift, probes()...); artifact=am)
        rs_m = audited(() -> execute!(tm, rep(); turns=5))
        @test !isfile(pmem) && !isfile(pmem * ".lock") && isfile(pfile)
        @test one(rs_f, :run_artifact_output).storage === :file
        ra_m = one(rs_m, :run_artifact_output)
        @test ra_m.storage === :memory && ra_m.artifact == pmem && ra_m.continued === false && ra_m.execution == 1
        @test ra_m.capacity == 2 && ra_m.append === false
        @test one(rs_m, :tracking_output).artifact == pmem
        @test isempty(Octopus._output_receipt_gaps(rs_m, schemas))
        of, om = TaskOutput(pfile), TaskOutput(am)
        @test om.artifact === am && om.path == pmem && of.artifact === nothing
        for (kind, name) in ((:moments, "m"), (:snapshot, "s"), (:bpm, "b"))
            rf, rm_ = read(of, kind; name=name), read(om, kind; name=name)
            @test keys(rf) == keys(rm_)
            @test columns(rf) == columns(rm_)
            @test rf.s == rm_.s                                     # line-placed: the arc position stamped in both
        end
        @test read(om, :moments; name="m").turn == collect(0.0:4.0)
        @test read(om, :execution).turns == [5] && read(om, :execution).current_turn == [4]
        toc_f, toc_m = read(of), read(om)
        @test Set(keys(toc_f)) == Set(keys(toc_m))
        @test all(toc_f[k] == toc_m[k] for k in ("moments", "snapshot", "bpm"))
        @test read(om, :all).moments["m"].turn == read(of, :all).moments["m"].turn
        @test read(MomentOutput(am; name="m")) == read(MomentOutput(pfile; name="m"))
        @test read(MomentOutput(am; name="m"), :turn) == collect(0.0:4.0)
        @test read(MomentOutput(am; name="m"), Moment(; x=1)) == read(MomentOutput(pfile; name="m"), Moment(; x=1))
        @test read(MomentOutput(am; name="m"); orders=1) == read(MomentOutput(pfile; name="m"); orders=1)
        @test column_names(MomentOutput(am; name="m")) == column_names(MomentOutput(pfile; name="m"))
        @test read(MomentOutput(am; name="m"), :record_count) == 5
        # After the run the artifact is closed for writing, is not a live
        # writer, and holds its image.
        @test am.file === nothing && am.image !== nothing && !Octopus._path_writer_is_live(am)
        # A reader of an image that was never written says so by name.
        err_r = try; read(TaskOutput(RunArtifact(; storage=:memory))); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("holds no image yet", err_r)

        # (c) The configuration report names the mode; the file-mode text is untouched.
        rep_m = configuration_report(tm, rep())
        @test rep_m.output[1].status === :resolved && occursin("rewriting the run artifact in memory", rep_m.output[1].reason) &&
              occursin(pmem, rep_m.output[1].reason)
        @test startswith(configuration_report(tf, rep()).output[1].reason, "rewriting the run artifact at " * pfile)
        rep_0 = configuration_report(TrackingTask((drift,); artifact=mem0), rep())
        @test occursin("in memory", rep_0.output[1].reason) && !occursin("save_run_artifact", rep_0.output[1].reason)

        # (d) save_run_artifact: refused before anything ran, refused on a file
        # artifact, refused path-less without a path; writes the constructor
        # path by default and an explicit path otherwise; the saved file reads
        # exactly as the live image; a lock another writer holds on the target
        # refuses by name, writes nothing and leaves that lock in place; the
        # saved file is a complete artifact a file-mode writer continues.
        err_n = try; save_run_artifact(RunArtifact(joinpath(dir, "never.h5"); storage=:memory)); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("holds no image yet", err_n) && !isfile(joinpath(dir, "never.h5"))
        err_f = try; save_run_artifact(tf.artifact); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("storage=:file", err_f) && occursin("already on disk", err_f)
        err_0 = try; save_run_artifact(mem0); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("constructed without a path", err_0)
        @test save_run_artifact(am) == pmem && isfile(pmem) && !isfile(pmem * ".lock")
        @test Octopus.HDF5.ishdf5(pmem)
        for (kind, name) in ((:moments, "m"), (:snapshot, "s"), (:bpm, "b"))
            @test read(TaskOutput(pmem), kind; name=name) == read(om, kind; name=name)
        end
        @test read(TaskOutput(pmem), :execution).turns == [5]
        @test read(TaskOutput(pmem)) == toc_m
        pother = joinpath(dir, "other.h5")
        @test save_run_artifact(am, pother) == pother && isfile(pother)
        @test read(TaskOutput(pother), :moments; name="m") == read(om, :moments; name="m")
        @test read(pother) == read(pmem)                           # one image, byte-identical copies
        plocked = joinpath(dir, "locked.h5")
        held = "host=elsewhere pid=1 since=2026-11-03T00:00:00+0000 task=TrackingTask"
        write(plocked * ".lock", held * "\n")
        err_l = try; save_run_artifact(am, plocked); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("another Octopus writer holds its lock", err_l) && occursin(held, err_l)
        @test !isfile(plocked) && isfile(plocked * ".lock") && isempty(filter(f -> occursin(".saving", f), readdir(dir)))
        rm(plocked * ".lock")
        set_global_rng!(seed=0x5eed, method=:philox)
        tcont = TrackingTask((drift, probes()...); artifact=RunArtifact(pother; append=true, capacity=2))
        execute!(tcont, rep(); turns=2, start_turn=5)
        @test read(TaskOutput(pother), :execution).start_turn == [0, 5]
        @test read(TaskOutput(pother), :moments; name="m").turn == collect(0.0:6.0)

        # (e) append in memory: append=false discards the previous image when the
        # next execute! begins; append=true continues the image in the process
        # (`continued` false then true, ledger rows 1 then 2, rows spanning
        # both windows); with a saved file at the path a NEW artifact object
        # loads it into memory and continues it, and the disk copy stays as
        # found until saved; a non-HDF5 file at the path is refused by name
        # and left alone, as in file mode.
        set_global_rng!(seed=0x5eed, method=:philox)
        rs_m2 = audited(() -> execute!(tm, rep(); turns=3, start_turn=5))
        @test one(rs_m2, :run_artifact_output).continued === false && one(rs_m2, :run_artifact_output).execution == 1
        @test read(om, :execution).start_turn == [5] && read(om, :moments; name="m").turn == collect(5.0:7.0)
        @test read(TaskOutput(pmem), :execution).turns == [5]            # the saved file is not the image
        pa = joinpath(dir, "append.h5")
        aa = RunArtifact(pa; storage=:memory, append=true, capacity=2)
        ta = TrackingTask((drift, probes()...); artifact=aa)
        rs_a1 = audited(() -> execute!(ta, rep(); turns=3))
        rs_a2 = audited(() -> execute!(ta, rep(); turns=3))
        @test one(rs_a1, :run_artifact_output).continued === false && one(rs_a2, :run_artifact_output).continued === true
        @test (one(rs_a1, :run_artifact_output).execution, one(rs_a2, :run_artifact_output).execution) == (1, 2)
        @test read(TaskOutput(aa), :execution).start_turn == [0, 3]
        @test read(TaskOutput(aa), :moments; name="m").turn == collect(0.0:5.0)
        @test !isfile(pa)
        save_run_artifact(aa)
        bytes = read(pa)
        ab = RunArtifact(pa; storage=:memory, append=true, capacity=2)
        tb = TrackingTask((drift, probes()...); artifact=ab)
        rs_b = audited(() -> execute!(tb, rep(); turns=2, start_turn=6))
        @test one(rs_b, :run_artifact_output).continued === true && one(rs_b, :run_artifact_output).execution == 3
        @test read(TaskOutput(ab), :moments; name="m").turn == collect(0.0:7.0)
        @test read(pa) == bytes
        @test read(TaskOutput(pa), :execution).turns == [3, 3]
        save_run_artifact(ab)
        @test read(TaskOutput(pa), :execution).turns == [3, 3, 2]
        @test !isfile(pa * ".lock")
        pbad = joinpath(dir, "bad.h5")
        write(pbad, "not hdf5")
        err_b = try; execute!(TrackingTask((drift,); artifact=RunArtifact(pbad; storage=:memory, append=true)), rep(); turns=1); "did not throw" catch e; sprint(showerror, e) end
        @test occursin("not an HDF5 file", err_b) && read(pbad, String) == "not hdf5"

        # (f) A failing run keeps its image (the task's best-effort finalize
        # retains it in memory as it closes a file), nothing reaches disk, and
        # the image can still be saved.
        pc = joinpath(dir, "crash.h5")
        ac = RunArtifact(pc; storage=:memory, capacity=1)
        tc = TrackingTask((drift, ScheduledObserver(_MemArtifactThrowAtTurn(2)),
                           ScheduledObserver(MomentObserver(; name="m", orders=1))); artifact=ac)
        @test_throws ErrorException execute!(tc, rep(); turns=5)
        @test ac.file === nothing && ac.image !== nothing && !isfile(pc) && !isfile(pc * ".lock")
        @test read(TaskOutput(ac), :moments; name="m").turn == [0.0, 1.0]
        @test read(TaskOutput(ac), :execution).turns == [5] && 1 <= only(read(TaskOutput(ac), :execution).current_turn) <= 2
        @test save_run_artifact(ac) == pc && read(TaskOutput(pc), :moments; name="m").turn == [0.0, 1.0]

        # (g) The strong-strong task: the luminosity channel lives in the image,
        # nothing on disk; a refused continuation (another collision label on
        # the same object) leaves the live image as found.
        mkb(rng_id, charge, mc2, E0) = begin
            set_global_rng!(seed=5, method=:philox)
            Beam(64, CPUThreadsExecutionPolicy(), Float64;
                 beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                 sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
                 charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
        end
        rid = Octopus.next_rng_id!() + 3_000_000
        b1, b2 = mkb(rid + 1, -1.0, EMASS_EV, 10.0e9), mkb(rid + 2, 1.0, PMASS_EV, 275.0e9)
        pss = joinpath(dir, "ss.h5")
        ass = RunArtifact(pss; storage=:memory, append=true, capacity=2)
        ip = StrongStrongCollision(:ip)
        rs_ss = audited(() -> execute!(StrongStrongTask((ip, drift), (ip, drift); artifact=ass), b1, b2; turns=2))
        @test one(rs_ss, :run_artifact_output).storage === :memory
        @test one(rs_ss, :strong_strong_output) == (artifact=pss, channels=["ip"])
        @test !isfile(pss) && !isfile(pss * ".lock")
        lum = read(TaskOutput(ass), :luminosity; name="ip")
        @test lum.turn == [0, 1] && length(lum.value) == 2 && all(isfinite, lum.value)
        ip2 = StrongStrongCollision(:elsewhere)
        @test_throws ArgumentError execute!(StrongStrongTask((ip2, drift), (ip2, drift); artifact=ass), b1, b2; turns=1)
        @test ass.file === nothing && !isfile(pss)
        @test read(TaskOutput(ass), :luminosity; name="ip").turn == [0, 1] && read(TaskOutput(ass), :execution).turns == [2]
        @test save_run_artifact(ass) == pss && read(TaskOutput(pss), :luminosity; name="ip").turn == [0, 1]
    end
end
@testset "Run artifact exclusion and seed provenance: the sidecar lock, lock-aware readers, the ledger's rng columns" begin
    # 2026-10-16 crab-cavity noise neighbour audit, S5-2 and S5-4
    # (docs/design/run_artifact.md, the two dated paragraphs). Measured on
    # 8ace18b: HDF5's own file lock is not effective on the NFSv3 mount, so a
    # second PROCESS opening a path another process held succeeded with
    # either `append` -- `append=false` truncated the holder's open file,
    # which then read back torn ("len not positive after adjustment for
    # EOA"), and two concurrent writers of one path both finished with one
    # run's 400 rows silently gone -- and nothing in the file recorded the
    # global RNG seed or method (a spectral table's canonical name was its
    # only mention of a seed). Every pin below was red on that tree.
    mktempdir() do dir
        set_global_rng!(seed=0x5eed, method=:philox)
        root = pkgdir(Octopus)
        rep = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
        drift = (DriftSpec(L=1.0),)
        lockof(p) = p * ".lock"
        quiet(f) = Test.collect_test_logs(f)[2]      # the U7-10 registry warning is not under test here
        # (a) A real TrackingTask in a CHILD process holds the path: its first
        # turn blocks on a marker, so this process -- "another process" to the
        # child -- attempts, reads and releases at known moments. The child
        # is the writer whose lock line names its task kind; its own seed and
        # method are deliberately not this process's.
        p_held = joinpath(dir, "held.h5")
        marker = joinpath(dir, "go")
        holder_script = """
            using Octopus
            struct HoldObserver <: Octopus.AbstractBeamObserver
                marker::String
            end
            function Octopus.observe!(o::HoldObserver, ctx, rep)
                ctx.turn == 0 || return nothing
                touch(o.marker * ".ready")
                t0 = time()
                while !isfile(o.marker) && time() - t0 < 240
                    sleep(0.1)
                end
                return nothing
            end
            set_global_rng!(seed=77, method=:splitmix)
            rep = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
            t = TrackingTask((DriftSpec(L=1.0), ScheduledObserver(MomentObserver(; name="m", orders=1)),
                              HoldObserver(ARGS[2])); artifact=RunArtifact(ARGS[1]; capacity=1))
            execute!(t, rep; turns=3)
            println("HOLDER-DONE lock_after=", isfile(ARGS[1] * ".lock"))
            """
        buf = IOBuffer()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(root) -e $(holder_script) $(p_held) $(marker)`
        holder = run(pipeline(cmd; stdout=buf, stderr=buf); wait=false)
        t0 = time()
        while !isfile(marker * ".ready") && process_running(holder) && time() - t0 < 300
            sleep(0.2)
        end
        @test isfile(marker * ".ready")
        held_line = isfile(lockof(p_held)) ? strip(read(lockof(p_held), String)) : ""
        @test occursin("host=$(gethostname())", held_line)
        @test occursin(r"pid=\d+", held_line) && !occursin("pid=$(getpid())", held_line)
        @test occursin(r"since=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", held_line)
        @test occursin("task=TrackingTask", held_line)
        @test count('\n', read(lockof(p_held), String)) == 1          # one line
        # A second writer from this process, with either `append`, is refused
        # by name -- the lock path, the holder's line, the remedy -- and the
        # holder's lock and file are untouched; the refused artifact holds
        # neither a file nor a lock.
        for append in (false, true)
            art2 = RunArtifact(p_held; append=append)
            err = try
                execute!(TrackingTask(drift; artifact=art2), rep; turns=2)
                "did not throw"
            catch e
                sprint(showerror, e)
            end
            @testset let append = append
                @test occursin("holds its lock", err) && occursin(lockof(p_held), err)
                @test occursin(held_line, err)
                @test occursin("remove $(lockof(p_held))", err)
                @test art2.file === nothing && art2.lock_line === nothing
            end
        end
        @test isfile(lockof(p_held)) && strip(read(lockof(p_held), String)) == held_line
        # A reader in this process while the child writes: the rows as of the
        # last flush, the seed and method the CHILD's execute! began with, one
        # @info naming the writer's line -- on the TaskOutput route and on the
        # MomentOutput route, which reads the same file.
        @testset "a reader while the writer holds the file" begin
            logs, (ex_held, m_held) = Test.collect_test_logs() do
                (read(TaskOutput(p_held), :execution), read(MomentOutput(p_held; name="m")))
            end
            @test ex_held.start_turn == [0] && ex_held.turns == [3]
            @test ex_held.rng_seed == UInt64[77] && ex_held.rng_method == ["splitmix"]
            @test m_held isa AbstractMatrix && size(m_held, 1) >= 1 && m_held[1, 1] == 0.0
            infos = [l for l in logs if l.level == Base.CoreLogging.Info &&
                     occursin("holds the run artifact's lock", string(l.message))]
            @test !isempty(infos) && all(l -> l.kwargs[:writer] == held_line, infos)
            @test all(l -> occursin("rows_valid_through_turn", string(l.message)), infos)
        end
        # Release: the child finishes, its lock leaves with its file, and the
        # refused writer now continues the file -- the lock was the only
        # reason -- recording this process's seed beside the child's.
        touch(marker)
        wait(holder)
        text = String(take!(buf))
        @test occursin("HOLDER-DONE lock_after=false", text)
        @test !isfile(lockof(p_held))
        set_global_rng!(seed=78, method=:philox)
        quiet(() -> execute!(TrackingTask(drift; artifact=RunArtifact(p_held; append=true)), rep;
                             turns=2, start_turn=3))
        ex_after = read(TaskOutput(p_held), :execution)
        @test ex_after.start_turn == [0, 3]
        @test ex_after.rng_seed == UInt64[77, 78] && ex_after.rng_method == ["splitmix", "philox"]
        @test !isfile(lockof(p_held))
        # Every call site of `prepare_run_artifact!` in src/ names its task
        # kind for the lock line, derived from the task's type.
        srcfiles = String[]
        for (d, _, fs) in walkdir(joinpath(root, "src")), f in fs
            endswith(f, ".jl") && push!(srcfiles, joinpath(d, f))
        end
        callsites = [f for f in srcfiles if occursin(r"^\s+prepare_run_artifact!\("m, read(f, String))]
        @test length(callsites) == 2
        @test all(f -> occursin("task_kind=string(nameof(typeof(task)))", read(f, String)), callsites)
        # (b) The lock leaves with the file on every closing path: the
        # prepare's own refusal (a continued file whose luminosity groups do
        # not match), an open that fails (a read handle this process holds),
        # and the observer-prepare refusal after prepare (duplicate probe
        # names) on both task kinds, which is their crash path's finalize.
        p_mis = joinpath(dir, "mismatch.h5")
        execute!(TrackingTask(drift; artifact=RunArtifact(p_mis)), rep; turns=1)
        @test !isfile(lockof(p_mis))
        Octopus.HDF5.h5open(p_mis, "r+") do f
            Octopus.HDF5.create_group(f["luminosity"], "stranger")
        end
        quiet() do          # the U7-10 registry warning of sequential sharing, not under test
            @test_throws ArgumentError execute!(TrackingTask(drift; artifact=RunArtifact(p_mis; append=true)),
                                                rep; turns=1)
        end
        @test !isfile(lockof(p_mis))
        h = Octopus.HDF5.h5open(p_mis, "r")
        quiet() do
            @test_throws Octopus.HDF5.API.H5Error execute!(TrackingTask(drift; artifact=RunArtifact(p_mis)),
                                                           rep; turns=1)
        end
        close(h)
        @test !isfile(lockof(p_mis))
        p_dup = joinpath(dir, "dup_ws.h5")
        wt = TrackingTask((drift..., ScheduledObserver(MomentObserver(; name="m", orders=1)),
                           ScheduledObserver(MomentObserver(; name="m", orders=1)));
                          artifact=RunArtifact(p_dup))
        @test_throws ArgumentError execute!(wt, rep; turns=2)
        @test wt.artifact.file === nothing && wt.artifact.lock_line === nothing
        @test !isfile(lockof(p_dup))
        mkb(rng_id, charge, mc2, E0) = Beam(64, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3),
            cutoff=5.0, rng_id=rng_id, charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
        b1, b2 = mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9)
        ip = StrongStrongCollision(:ip)
        p_dss = joinpath(dir, "dup_ss.h5")
        tss = StrongStrongTask((ip, drift..., ScheduledObserver(MomentObserver(; name="m", orders=1)),
                                ScheduledObserver(MomentObserver(; name="m", orders=1))),
                               (ip, drift...); artifact=RunArtifact(p_dss))
        @test_throws ArgumentError execute!(tss, b1, b2; turns=2)
        @test tss.artifact.file === nothing && tss.artifact.lock_line === nothing
        @test !isfile(lockof(p_dss))
        # (c) The ledger records the global seed and method of EACH execute!:
        # two windows on one continued file with a seed and method change in
        # between, the values those in force as each window began, the method
        # named from the RNG code (not copied).
        p_seed = joinpath(dir, "seed.h5")
        ts = TrackingTask(drift; artifact=RunArtifact(p_seed; append=true))
        set_global_rng!(seed=21, method=:philox)
        execute!(ts, rep; turns=2)
        want = [(global_rng_seed(), string(global_rng_method()))]
        set_global_rng!(seed=22, method=:splitmix)
        execute!(ts, rep; turns=2)
        push!(want, (global_rng_seed(), string(global_rng_method())))
        ex_seed = read(TaskOutput(p_seed), :execution)
        @test ex_seed.rng_seed == UInt64[21, 22]
        @test ex_seed.rng_method == ["philox", "splitmix"]
        @test collect(zip(ex_seed.rng_seed, ex_seed.rng_method)) == want
        @test ex_seed.rng_method[2] == string(Octopus.rng_method_symbol(Octopus.RNG_SPLITMIX))
        @test ex_seed.rng_seed isa Vector{UInt64} && ex_seed.rng_method isa Vector{String}
        # The file's columns are the writer's table (one source: creation, the
        # appended row, the continue-check and the reader), the table of
        # contents lists them, and the design note names each one.
        cols = [n for (n, _) in Octopus._RA_LEDGER_COLUMNS]
        @test ("rng_seed", UInt64) in Octopus._RA_LEDGER_COLUMNS
        @test ("rng_method", String) in Octopus._RA_LEDGER_COLUMNS
        @test ("machine_sha256", String) in Octopus._RA_LEDGER_COLUMNS      # D14, 2026-11-25; the text under /machine_snapshots since R9 (2026-11-26)
        @test !any(c -> c[1] == "machine_toml", Octopus._RA_LEDGER_COLUMNS)
        Octopus.HDF5.h5open(p_seed, "r") do f
            @test sort(String.(collect(keys(f["execution"])))) == sort(cols)
        end
        @test Set(read(TaskOutput(p_seed))["execution"].columns) == Set(cols)
        @test collect(propertynames(ex_seed)) == Symbol.(cols)
        design = read(joinpath(root, "docs", "design", "run_artifact.md"), String)
        @test all(occursin("`$(n)`", design) for n in cols)
        # (d) A continued file whose ledger lacks the columns -- the layout
        # every artifact had before 2026-10-16, rebuilt here through HDF5 --
        # is refused by name, left as found and still readable (its missing
        # columns read as `nothing`); with the two columns added it continues.
        p_old = joinpath(dir, "old.h5")
        Octopus.HDF5.h5open(p_old, "w") do f
            Octopus.HDF5.attributes(f)["octopus_run_artifact"] = Int64(1)
            Octopus.HDF5.create_group(f, "luminosity")
            ex = Octopus.HDF5.create_group(f, "execution")
            for (name, T) in (("start_turn", Int64), ("turns", Int64), ("current_turn", Int64),
                              ("elapsed", Float64))               # the pre-column layout, by design
                Octopus._ra_extendable!(ex, name, T)
            end
        end
        ledger_keys(p) = Octopus.HDF5.h5open(f -> sort(String.(collect(keys(f["execution"])))), p, "r")
        keys_before = ledger_keys(p_old)
        err_old = try
            execute!(TrackingTask(drift; artifact=RunArtifact(p_old; append=true)), rep; turns=1)
            "did not throw"
        catch e
            sprint(showerror, e)
        end
        @test occursin("rng_seed", err_old) && occursin("rng_method", err_old)
        @test occursin("predates", err_old) && occursin("2026-10-16", err_old)
        @test occursin("append=false", err_old) && occursin(p_old, err_old)
        @test ledger_keys(p_old) == keys_before
        @test !isfile(lockof(p_old))
        ex_old = read(TaskOutput(p_old), :execution)
        @test ex_old.rng_seed === nothing && ex_old.rng_method === nothing && ex_old.start_turn == Int64[]
        Octopus.HDF5.h5open(p_old, "r+") do f
            Octopus._ra_extendable!(f["execution"], "rng_seed", UInt64)
            Octopus._ra_extendable!(f["execution"], "rng_method", String)
        end
        # With the seed columns added the file is the 2026-10-16 layout, which
        # lacks the machine digest column of 2026-11-25 (D14): refused by name
        # naming that generation alone; with it added as well it continues.
        err_mid = try
            execute!(TrackingTask(drift; artifact=RunArtifact(p_old; append=true)), rep; turns=1)
            "did not throw"
        catch e
            sprint(showerror, e)
        end
        @test occursin("machine_sha256", err_mid) && !occursin("machine_toml", err_mid) &&
              occursin("2026-11-25", err_mid) && !occursin("2026-10-16", err_mid)
        Octopus.HDF5.h5open(p_old, "r+") do f
            Octopus._ra_extendable!(f["execution"], "machine_sha256", String)
        end
        set_global_rng!(seed=23, method=:philox)
        quiet(() -> execute!(TrackingTask(drift; artifact=RunArtifact(p_old; append=true)), rep; turns=1))
        @test read(TaskOutput(p_old), :execution).rng_seed == UInt64[23]
        @test read(TaskOutput(p_old), :execution).machine_sha256 == [""]
        set_global_rng!(seed=0x5eed, method=:philox)
    end
end
@testset "Run artifact receipts and slots: resolved output receipts for both task kinds, derived vocabularies, the non-HDF5 append refusal, a partial slot reported by the reader" begin
    # 2026-10-16 crab-cavity noise neighbour audit, fix unit E: S4-1, S4-2,
    # S4-3, S4-10 (the output receipts), S4-5, S4-8, S4-9 (the artifact's
    # vocabularies), S5-7 (append onto a non-HDF5 file), unit A's open point
    # (a refused writer registered as live), the owner's partial-slot
    # decision (the stage 3-4 audit's U5-2: the reader reports, no rollback)
    # and U9-5 (the recorder's unsized buffers). Every pin below was red on
    # ac3fbb2 (fixes/E/red_unfixed.log).
    HDF5 = Octopus.HDF5
    mktempdir() do dir
        set_global_rng!(seed=0x5eed, method=:philox)
        root = pkgdir(Octopus)
        # Stream ids above the registry's counter, so the fixture's explicit
        # ids (rules, beams) never collide with the ids the probes auto-assign
        # (the registry would warn, and the suite log carries no unexplained line).
        rid = Octopus.next_rng_id!() + 3_000_000
        mkp(n=4) = Phase6DRep(collect(range(-1.0e-4, 1.0e-4; length=n)), zeros(n), fill(3.0e-5, n),
                              zeros(n), fill(1.0e-2, n), zeros(n))
        table = TurnTable(collect(0.001:0.001:0.012); name="amp")
        crab() = ThinCrabCavitySpec{2}(394.0e6; strengthX=(2.0e-3, 1.0e-3), strengthY=(0.0, 5.0e-4),
                                       phase=(0.1, 0.2), phase_noise=(WhiteNoise(1.0e-2; rng_id=rid + 7), nothing),
                                       strength_noise=(nothing, table))
        disp() = CrabDispersionSpec{Float64}(zeta1=0.1)
        rf() = ThinRFCavitySpec(400.0e6; voltage=1.0e6, e0=275.0e9, mc2=PMASS_EV,
                                phase_noise=WhiteNoise(1.0e-3; rng_id=rid + 9))
        hooks() = (ScheduledObserver(MomentObserver(; name="m", orders=1)),
                   ScheduledObserver(CoordinateSnapshotObserver(; name="snap", npart=2)),
                   ScheduledObserver(BPMObserver("b"; artifact=true)))
        function audited(f)
            audit = ExecutionAudit()
            with_execution_audit(audit) do; f(); end
            return execution_receipts(audit)
        end
        one(rs, c) = only(filter(r -> r.consumer === c, rs)).values
        quiet(f) = Test.collect_test_logs(f)[2]      # the U7-10 registry warning is not under test here
        refusal(f) = try f(); nothing catch e; e end
        ex_rows(p) = length(read(TaskOutput(p), :execution).start_turn)
        srcfiles = String[]
        for (d, _, fs) in walkdir(joinpath(root, "src")), f in fs
            endswith(f, ".jl") && push!(srcfiles, joinpath(d, f))
        end
        src = join([read(f, String) for f in srcfiles], "\n")

        # (a) The output boundary's metadata, DERIVED. The schema family: the
        # artifact, every concrete task (the pair list is pinned against the
        # AbstractTask tree, the validator's own shape) and every concrete
        # observer (from the tree). Every artifact option names the ONE receipt
        # the prepare records; each task's `artifact` entry names its own output
        # receipt, `loss_report` rides with the tracking task's; every observer
        # option of category :output names the observers' receipt; and every
        # consumer an :output option names has a `_record_execution!` site in
        # src/ (the F3 shape -- a declared consumer no receipt records -- fails
        # here by name; `moment_reduction` was one until 2026-10-16).
        art_schema = :RunArtifact => run_artifact_option_schema()
        task_schemas = [TrackingTask => tracking_task_option_schema(),
                        StrongStrongTask => strong_strong_task_option_schema()]
        @test Set(first.(task_schemas)) == Set(Octopus._concrete_octopus_subtypes(Octopus.AbstractTask))
        observers = Octopus._concrete_octopus_subtypes(Octopus.AbstractBeamObserver)
        @test Set(observers) == Set(Any[MomentObserver, CoordinateSnapshotObserver, BPMObserver])
        obs_schemas = [Symbol(nameof(T)) => observer_option_schema(T) for T in observers]
        tracking_schemas = [art_schema, :TrackingTask => tracking_task_option_schema(), obs_schemas...]
        strong_strong_schemas = [art_schema, :StrongStrongTask => strong_strong_task_option_schema()]
        @test all(m.consumer === :run_artifact_output && m.category === :output
                  for m in run_artifact_option_schema())
        @test (:artifact, :loss_report) ⊆ keys(tracking_task_option_schema())
        @test tracking_task_option_schema().artifact.consumer === :tracking_output
        @test tracking_task_option_schema().artifact.category === :output
        @test tracking_task_option_schema().loss_report.consumer === :tracking_output
        @test tracking_task_option_schema().loss_report.default === true
        @test strong_strong_task_option_schema().artifact.consumer === :strong_strong_output
        @test all(m.consumer === :observer_output for (_, s) in obs_schemas for m in s if m.category === :output)
        @test observer_option_schema(MomentObserver).moments.consumer === :observer_output
        output_consumers = Set(m.consumer for (_, s) in (art_schema, (Symbol(nameof(T)) => s for (T, s) in task_schemas)...,
                                                          obs_schemas...) for m in s if m.category === :output)
        @test output_consumers == Set([:run_artifact_output, :tracking_output, :strong_strong_output, :observer_output])
        for c in output_consumers
            @test occursin("_record_execution!(:$(c)", src)
        end
        @test !occursin("_record_execution!(:moment_reduction", src)
        @test validate_configuration_metadata()

        # (b) The TrackingTask fixture: every artifact option away from its
        # default and `loss_report` off (the carries-every-option rule), a
        # modulated line, all three probes. `append=true` on a path that does
        # not exist RESOLVES to `continued=false`; the same task's next window
        # continues the file, `continued=true`. Not one of these keys reached
        # a receipt under a TrackingTask before.
        pA = joinpath(dir, "A.h5")
        tA = TrackingTask((disp(), crab(), hooks()...); loss_report=false,
                          artifact=RunArtifact(pA; append=true, capacity=3, record_turn_modulation=true))
        # The memory sibling (2026-11-03): `storage=:memory` is the one option
        # the file fixture must leave at its default (every reader and lock
        # check below opens pA on disk), so the carries-every-option rule is
        # read over BOTH fixtures, each gap-checked below: every option is
        # away from its default in at least one artifact whose receipts this
        # testset checks.
        pM = joinpath(dir, "M.h5")
        tM = TrackingTask((disp(), hooks()...); loss_report=false,
                          artifact=RunArtifact(pM; storage=:memory, append=true, capacity=3,
                                               record_turn_modulation=true, machine_snapshot=false))   # R9 (2026-11-26): off here, on in tA
        for (k, m) in pairs(run_artifact_option_schema())
            @test any(a -> getproperty(a, k) != m.default, (tA.artifact, tM.artifact))
        end
        @test tA.loss_report != tracking_task_option_schema().loss_report.default
        rsA = audited(() -> execute!(tA, mkp(); turns=4))
        @test isempty(Octopus._output_receipt_gaps(rsA, tracking_schemas))
        ra = one(rsA, :run_artifact_output)
        @test propertynames(ra) == (:task, :artifact, :append, :continued, :capacity,
                                    :record_turn_modulation, :recording, :storage,
                                    :machine_snapshot, :machine_recorded, :execution)   # :storage since 2026-11-03; the machine pair since 2026-11-26 (R9)
        @test ra.machine_snapshot === true && ra.machine_recorded === :none           # a tuple-built task has no machine to embed
        @test ra.storage === :file
        @test ra.task === :TrackingTask && ra.artifact == pA && ra.execution == 1
        @test ra.append === true && ra.continued === false
        @test ra.capacity == 3
        @test ra.record_turn_modulation === true && ra.recording === true
        to = one(rsA, :tracking_output)
        @test propertynames(to) == (:artifact, :channels, :loss_report)
        @test to.artifact == pA && to.channels == String[] && to.loss_report === false
        rsA2 = audited(() -> execute!(tA, mkp(); turns=2))
        @test isempty(Octopus._output_receipt_gaps(rsA2, tracking_schemas))
        ra2 = one(rsA2, :run_artifact_output)
        @test ra2.append === true && ra2.continued === true && ra2.execution == 2 && ra2.recording === true
        @test ex_rows(pA) == 2
        # The memory sibling's receipts: every output option carried, `storage`
        # as applied, the path kept as the label, nothing on disk, no registry
        # entry (nothing for two writers to interleave into), the ledger read
        # from the live image (2026-11-03).
        rsM = audited(() -> execute!(tM, mkp(); turns=2))
        @test isempty(Octopus._output_receipt_gaps(rsM, tracking_schemas))
        raM = one(rsM, :run_artifact_output)
        @test raM.storage === :memory && raM.artifact == pM && raM.continued === false && raM.execution == 1
        @test raM.append === true && raM.capacity == 3 && raM.record_turn_modulation === true && raM.recording === false
        @test !isfile(pM) && !isfile(pM * ".lock") && !haskey(Octopus._OBSERVER_PATH_REGISTRY, abspath(pM))
        @test one(rsM, :tracking_output).artifact == pM
        @test read(TaskOutput(tM.artifact), :execution).turns == [2]
        # The observers' receipts carry the fields their metadata names, the
        # request under the option's name and what was applied beside it: the
        # moment probe's `name`, `moments` and the ARTIFACT's capacity; the
        # snapshot's `name` and `npart` beside `captured` (it recorded no
        # receipt at all before); the BPM's `artifact` switch and the
        # capacity it batches by (it carried neither).
        obs = [r.values for r in rsA if r.consumer === :observer_output]
        mom = [v for v in obs if v.observer === :MomentObserver]
        snap = [v for v in obs if v.observer === :CoordinateSnapshotObserver]
        bpm = [v for v in obs if v.observer === :BPMObserver]
        @test length(mom) == length(snap) == length(bpm) == 4
        @test all(v -> propertynames(v) == (:observer, :name, :turn, :capacity, :moments), mom)
        @test all(v -> v.name === :m && v.capacity == 3 &&
                       v.moments == length(MomentObserver(; name="m", orders=1).moments), mom)
        @test all(v -> propertynames(v) == (:observer, :name, :turn, :npart, :captured), snap)
        @test all(v -> v.name === :snap && v.npart == 2 && v.captured == 2, snap)
        @test all(v -> propertynames(v) == (:observer, :name, :turn, :artifact, :capacity), bpm)
        @test all(v -> v.name === :b && v.artifact === true && v.capacity == 3, bpm)
        @test [v.turn for v in snap] == [0, 1, 2, 3]
        # `npart = nothing` requests every particle: the request stays
        # `nothing`, the count captured is the beam's.
        pN = joinpath(dir, "N.h5")
        rsN = audited(() -> execute!(TrackingTask((disp(), ScheduledObserver(CoordinateSnapshotObserver(; name="all")));
                                                  artifact=RunArtifact(pN)), mkp(3); turns=1))
        vN = one(rsN, :observer_output)
        @test vN.npart === nothing && vN.captured == 3
        # A memory-only BPM batches nothing: `artifact = false`, no capacity.
        rsB = audited(() -> execute!(TrackingTask((disp(), ScheduledObserver(BPMObserver("mem")))), mkp(); turns=1))
        vB = one(rsB, :observer_output)
        @test vB.artifact === false && vB.capacity === nothing
        # No artifact: the task's output receipt says so on both loops -- the
        # fast loop (no hooks) and the general one -- with the loss-report
        # switch, and no artifact receipt is recorded.
        rs0 = audited(() -> execute!(TrackingTask((disp(),); loss_report=false), mkp(); turns=1))
        @test one(rs0, :tracking_output) == (artifact=nothing, channels=nothing, loss_report=false)
        @test one(rs0, :tracking_turn_timing).fast_path === true
        @test !any(r -> r.consumer === :run_artifact_output, rs0)
        rs0h = audited(() -> execute!(TrackingTask((disp(), ScheduledObserver(BPMObserver("mem2")))), mkp(); turns=1))
        @test one(rs0h, :tracking_output) == (artifact=nothing, channels=nothing, loss_report=true)
        @test one(rs0h, :tracking_turn_timing).fast_path === false
        # A weak-strong line with strong beams names its channels.
        pW = joinpath(dir, "W.h5")
        strong() = GaussianStrongBeamSpec(; kbb=1.0e-4, beta=(1.0, 1.0), sigma=(1.0e-3, 1.0e-3), ns=1)
        rsW = audited(() -> execute!(TrackingTask((disp(), strong(), strong()); artifact=RunArtifact(pW)), mkp(); turns=1))
        @test one(rsW, :tracking_output).channels == ["strong_beam_1", "strong_beam_2"]
        @test sort(collect(keys(read(TaskOutput(pW), :luminosity)))) == ["strong_beam_1", "strong_beam_2"]
        # The receipts sit AFTER the prepare: a prepare refusal (a continued
        # file whose luminosity groups do not match) leaves neither of them,
        # and (unit A's open point) the refused writer is not registered as a
        # live writer of the path -- the first writer's entry stands -- while
        # its lock is gone with the file.
        pM = joinpath(dir, "M.h5")
        first_writer = RunArtifact(pM)
        execute!(TrackingTask((disp(),); artifact=first_writer), mkp(); turns=1)
        HDF5.h5open(pM, "r+") do f
            HDF5.create_group(f["luminosity"], "stranger")
        end
        refused = RunArtifact(pM; append=true)
        rsM = quiet(() -> audited(() -> @test_throws ArgumentError execute!(
            TrackingTask((disp(),); artifact=refused), mkp(); turns=1)))
        @test !any(r -> r.consumer in (:tracking_output, :run_artifact_output), rsM)
        @test refused.registered === false && refused.file === nothing
        reg = get(Octopus._OBSERVER_PATH_REGISTRY, abspath(pM), nothing)
        @test reg !== nothing && reg.value === first_writer
        @test !isfile(pM * ".lock")
        # ... and a writer that succeeds IS registered, once.
        @test tA.artifact.registered === true
        @test Octopus._OBSERVER_PATH_REGISTRY[abspath(pA)].value === tA.artifact
        # The configuration report has the output entries the schema names:
        # the artifact entry `:unresolved` while `append` or
        # `record_turn_modulation` is requested (both are decided at prepare
        # and reported by the receipt), `:resolved` when neither is,
        # `:inactive_dependency` without an artifact; `loss_report` resolved.
        rep = configuration_report(tA, mkp())
        @test haskey(rep, :output) && [e.name for e in rep.output] == [:artifact, :loss_report]
        @test rep.output[1].status === :unresolved && rep.output[1].consumer === :tracking_output
        @test occursin("continuing the run artifact at " * pA, rep.output[1].reason)
        @test occursin("recording the turn-modulation series", rep.output[1].reason)
        @test occursin("decided at prepare", rep.output[1].reason) &&
              occursin("`continued`", rep.output[1].reason) && occursin("`recording`", rep.output[1].reason)
        @test rep.output[2].status === :resolved && rep.output[2].requested === false &&
              rep.output[2].consumer === :tracking_output && occursin("skipped", rep.output[2].reason)
        rep_plain = configuration_report(TrackingTask((disp(),); artifact=RunArtifact(joinpath(dir, "X.h5"))), mkp())
        @test rep_plain.output[1].status === :resolved && startswith(rep_plain.output[1].reason, "rewriting")
        @test !occursin("recording", rep_plain.output[1].reason) && !occursin("decided", rep_plain.output[1].reason)
        @test rep_plain.output[2].requested === true && occursin("reconciled", rep_plain.output[2].reason)
        @test configuration_report(TrackingTask((disp(),)), mkp()).output[1].status === :inactive_dependency
        rep_app = configuration_report(TrackingTask((disp(),); artifact=RunArtifact(joinpath(dir, "Y.h5"); append=true)), mkp())
        @test rep_app.output[1].status === :unresolved && !occursin("recording", rep_app.output[1].reason) &&
              occursin("`continued`", rep_app.output[1].reason)

        # (c) The StrongStrongTask fixture: `append=true` on a fresh path and
        # `record_turn_modulation=true` on lines with NO modulated element --
        # both requested, both resolved inactive -- `capacity=5`; the task's
        # own receipt carries the path and the collision labels; the second
        # window continues; a prepare refusal leaves no output receipt (the
        # diagnostics receipt before the preflight is the U4-3 owner item).
        mkb(rng_id, charge, mc2, E0) = begin
            set_global_rng!(seed=5, method=:philox)
            Beam(64, CPUThreadsExecutionPolicy(), Float64;
                beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
                charge=charge, mc2=mc2, E0=E0, npart=1.0e10)
        end
        ip = StrongStrongCollision(:ip)
        plain = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,))
        pS = joinpath(dir, "S.h5")
        tS = StrongStrongTask((ip, plain), (ip, plain);
                              artifact=RunArtifact(pS; append=true, capacity=5, record_turn_modulation=true))
        b1, b2 = mkb(rid + 1, -1.0, EMASS_EV, 10.0e9), mkb(rid + 2, 1.0, PMASS_EV, 275.0e9)
        repS = configuration_report(tS, b1, b2)
        @test only(repS.output).status === :unresolved && only(repS.output).consumer === :strong_strong_output
        @test occursin("recording the turn-modulation series", only(repS.output).reason)
        rsS = audited(() -> execute!(tS, b1, b2; turns=2))
        @test isempty(Octopus._output_receipt_gaps(rsS, strong_strong_schemas))
        raS = one(rsS, :run_artifact_output)
        @test raS.task === :StrongStrongTask && raS.artifact == pS && raS.execution == 1
        @test raS.append === true && raS.continued === false && raS.capacity == 5
        @test raS.record_turn_modulation === true && raS.recording === false
        @test one(rsS, :strong_strong_output) == (artifact=pS, channels=["ip"])
        @test !HDF5.h5open(f -> haskey(f, "turn_modulation"), pS)
        rsS2 = audited(() -> execute!(tS, b1, b2; turns=1))
        @test one(rsS2, :run_artifact_output).continued === true && one(rsS2, :run_artifact_output).execution == 2
        HDF5.h5open(pS, "r+") do f
            HDF5.create_group(f["luminosity"], "stranger")
        end
        rsS3 = quiet(() -> audited(() -> @test_throws ArgumentError execute!(
            StrongStrongTask((ip, plain), (ip, plain); artifact=RunArtifact(pS; append=true)), b1, b2; turns=1)))
        @test !any(r -> r.consumer in (:strong_strong_output, :run_artifact_output), rsS3)
        @test any(r -> r.consumer === :strong_strong_diagnostics, rsS3)
        # The OBSERVERS' prepare is the last refusal that can stop the run, and
        # it refused AFTER the task's output receipt was recorded (2026-10-18
        # audit, U6-5, measured with a duplicate probe name, a refusal that has
        # since moved into the artifact's prepare; `ThrowingPrepareObserver`
        # above refuses where it did). The TrackingTask twin's
        # `:tracking_output` moved the same way in fix batch 3, unit F. The
        # receipt sits after the commit now, beside the per-run receipts, so a
        # run the observers refuse leaves no `:strong_strong_output` claiming
        # it ran. (The artifact's own `:run_artifact_output`, recorded by its
        # prepare in RunArtifact.jl, is the artifact's seam and not asserted.)
        pS5 = joinpath(dir, "S5.h5")
        refusing = (ip, plain, ScheduledObserver(ThrowingPrepareObserver()))
        rsS5 = quiet(() -> audited(() -> @test_throws ArgumentError execute!(
            StrongStrongTask(refusing, (ip, plain); artifact=RunArtifact(pS5)), b1, b2; turns=1)))
        @test !any(r -> r.consumer === :strong_strong_output, rsS5)       # was recorded: (artifact=pS5, channels=["ip"])
        @test any(r -> r.consumer === :strong_strong_diagnostics, rsS5)
        # The strong-strong receipt under a modulated line resolves `recording`.
        pS2 = joinpath(dir, "S2.h5")
        cav(rng_id) = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,),
                                            phase_noise=(WhiteNoise(1.0e-2; rng_id=rng_id),))
        rsS4 = audited(() -> execute!(StrongStrongTask((ip, cav(rid + 11)), (ip, cav(rid + 12));
                                                       artifact=RunArtifact(pS2; record_turn_modulation=true)),
                                      mkb(rid + 1, -1.0, EMASS_EV, 10.0e9), mkb(rid + 2, 1.0, PMASS_EV, 275.0e9); turns=1))
        @test one(rsS4, :run_artifact_output).recording === true
        @test one(rsS4, :run_artifact_output).continued === false && one(rsS4, :run_artifact_output).append === false

        # (d) The derivation's negative controls: a receipt lacking an option's
        # field, no receipt at all, and another observer's receipt standing in
        # for the owner's are each a named gap.
        fake(c, v) = ExecutionAuditReceipt(c, CPUThreadsBackend, v)
        g1 = Octopus._output_receipt_gaps([fake(:run_artifact_output, (task=:TrackingTask, artifact="x", append=true,
                                                                       continued=false, capacity=1, recording=false,
                                                                       storage=:file, machine_snapshot=true,
                                                                       machine_recorded=:none, execution=1))], [art_schema])   # one field missing: storage carried since 2026-11-03, machine_snapshot since 2026-11-26
        @test length(g1) == 1 && occursin("RunArtifact.record_turn_modulation", g1[1]) &&
              occursin("no field named record_turn_modulation", g1[1])
        @test Octopus._output_receipt_gaps(ExecutionAuditReceipt[], [art_schema]) ==
              ["RunArtifact.$(k): no run_artifact_output receipt was recorded" for k in keys(run_artifact_option_schema())]
        g2 = Octopus._output_receipt_gaps([fake(:observer_output, (observer=:MomentObserver, name=:m, turn=0, capacity=3, moments=6))],
                                          [:CoordinateSnapshotObserver => observer_option_schema(CoordinateSnapshotObserver)])
        @test length(g2) == 2 && all(g -> occursin("no observer_output receipt", g), g2)
        @test isempty(Octopus._output_receipt_gaps([fake(:observer_output, (observer=:MomentObserver, name=:m, turn=0, capacity=3, moments=6))],
                                                   [:MomentObserver => observer_option_schema(MomentObserver)]))
        # The BPM's reading terms name `:bpm_reading`, not an output receipt:
        # outside this derivation by construction (todo row 28's sweep).
        @test all(m.consumer === :bpm_reading for (k, m) in pairs(observer_option_schema(BPMObserver)) if k !== :artifact)

        # (e) The vocabularies. The slot `kind` vocabulary is DERIVED from the
        # rule catalogue's type-level `_rule_kind` (no instance needed); every
        # text that names it names every kind and carries no hand list; the
        # reader warns by name on a kind outside it and reads it as it stands.
        kinds = Octopus._turn_rule_kinds()
        @test kinds == Tuple(sort!(unique!(Symbol[Octopus._rule_kind(R) for R in
                                                   Octopus._concrete_octopus_subtypes(Octopus.AbstractTurnRule)])))
        @test kinds == (:pink, :spectral, :table, :white)
        @test Octopus._rule_kind(WhiteNoise) === :white === Octopus._rule_kind(WhiteNoise(1.0))
        @test Octopus._rule_kind(TurnTable) === :table === Octopus._rule_kind(table)
        @test Octopus._rule_kind(SpectralNoise) === :spectral
        @test Octopus._rule_kind(PinkNoise{Float64}) === :pink
        texts = ["?RunArtifact" => string(@doc RunArtifact),
                 "?turn_modulation_provenance" => string(@doc turn_modulation_provenance),
                 "the walk's docstring" => string(@doc Octopus._turn_modulation_provenance!),
                 "the _rule_kind docstring" => string(@doc Octopus._rule_kind),
                 "docs/design/run_artifact.md" => read(joinpath(root, "docs", "design", "run_artifact.md"), String)]
        for (label, text) in texts
            @testset let names_kinds_in = label
                for k in kinds
                    @test occursin("`$(k)`", text) || occursin(":$(k)", text)
                end
                @test !occursin("white`, `pink` or `table", text)
                @test !occursin(":white, :pink or :table", text)
            end
        end
        pK = joinpath(dir, "K.h5")
        set_global_rng!(seed=0x5eed, method=:philox)
        execute!(TrackingTask((disp(), crab()); artifact=RunArtifact(pK)), mkp(); turns=1)
        HDF5.h5open(pK, "r+") do f
            sg = f["turn_modulation"]["1"]["1"]["phase_noise[1]"]
            HDF5.delete_attribute(sg, "kind")
            HDF5.attributes(sg)["kind"] = "fifth"
        end
        provK = @test_logs (:warn, r"phase_noise\[1\] carries the kind \"fifth\", which is not a rule kind this reader knows \(pink, spectral, table, white\)") turn_modulation_provenance(pK)
        @test provK[1].elements[1].slots[1].kind === :fifth
        # The product groups: `_RA_KINDS` and `_RA_NAMED_KINDS` derive from the
        # one table, a run of every producer writes exactly the table's groups,
        # the readers serve all of them, and a probe binds under no other name.
        @test Octopus._RA_KINDS == keys(Octopus._RA_GROUPS)
        @test Set(Octopus._RA_NAMED_KINDS) == Set(k for (k, s) in pairs(Octopus._RA_GROUPS) if s === :named)
        @test Set(values(Octopus._RA_GROUPS)) == Set([:named, :single, :slotted])
        pG = joinpath(dir, "G.h5")
        set_global_rng!(seed=0x5eed, method=:philox)
        n = 64
        rep64 = Phase6DRep([1.0e-4 * sin(0.017i) for i in 1:n], [2.0e-5 * cos(0.013i) for i in 1:n],
                           [8.0e-5 * sin(0.017i + 0.2) for i in 1:n], [1.5e-5 * cos(0.013i + 0.3) for i in 1:n],
                           [1.0e-2 * sin(0.017i + 0.4) for i in 1:n], [5.0e-4 * cos(0.013i + 0.5) for i in 1:n])
        execute!(TrackingTask((disp(), crab(), strong(), ApertureSpec(x_limit=6.0e-5, name="COLL"), hooks()...);
                              artifact=RunArtifact(pG; capacity=2, record_turn_modulation=true)), rep64; turns=3)
        # Permanent-loss and reset-trial producers intentionally use distinct
        # semantics, so cover their product union with two genuine runs.
        pReset = joinpath(dir, "G_reset.h5")
        reset_rep = Phase6DRep([0.0, 1.0e-3], zeros(2), zeros(2), zeros(2), zeros(2), zeros(2))
        execute!(TrackingTask((PhaseSpaceResetSpec(), ApertureSpec(x_limit=5e-4, name="COLL"));
            artifact=RunArtifact(pReset)), reset_rep; turns=2)
        producer_paths = (pG, pReset)
        written = union((HDF5.h5open(f -> Set(Symbol(String(k)) for k in keys(f)), path)
                         for path in producer_paths)...)
        @test written == Set(Octopus._RA_KINDS)
        @test union((Set(propertynames(read(TaskOutput(path), :all))) for path in producer_paths)...) == Set(Octopus._RA_KINDS)
        @test union((Set(Symbol.(keys(read(TaskOutput(path))))) for path in producer_paths)...) == Set(Octopus._RA_KINDS)
        for path in producer_paths
            HDF5.h5open(path, "r") do f
                for (k, shape) in pairs(Octopus._RA_GROUPS)
                    haskey(f, String(k)) || continue
                    children = [f[String(k)][c] for c in keys(f[String(k)])]
                    @testset let group = k
                        # a named or slotted kind holds groups, a single kind datasets
                        @test all(c -> c isa HDF5.Group, children) == (shape !== :single)
                    end
                end
            end
        end
        errK = refusal(() -> read(TaskOutput(pG), :state))
        @test errK isa ArgumentError && occursin("unknown artifact product :state", sprint(showerror, errK))
        artG = RunArtifact(joinpath(dir, "bind.h5"))
        Octopus.prepare_run_artifact!(artG, String[], 0, 1)
        errB = refusal(() -> Octopus._ra_bind_probe!(artG, "state", "x", ["turn"], 0))
        @test errB isa ArgumentError && occursin("cannot bind under /state", sprint(showerror, errB)) &&
              occursin(join(string.(Octopus._RA_NAMED_KINDS), ", "), sprint(showerror, errB))
        Octopus.finalize_run_artifact!(artG)
        # The `:turn_modulation` receipt's shape at all three levels, and the
        # artifact reader's (the slot entry alone was pinned before, S4-9).
        rc = one(rsA, :turn_modulation)
        @test propertynames(rc) == (:elements, :first_turn, :turns)
        @test propertynames(rc.elements[1]) == (:element, :beam, :slots)
        @test propertynames(rc.elements[1].slots[1]) == (:slot, :kind, :rng_id, :digest, :name, :length, :sigma, :octaves)
        @test rc.first_turn == 0 && rc.turns == 4 && rc.elements[1].beam == 1
        provA = turn_modulation_provenance(pA)
        @test propertynames(provA[1]) == (:execution, :elements, :state)
        @test propertynames(provA[1].elements[1]) == (:element, :beam, :first_turn, :turns, :slots)
        @test propertynames(provA[1].elements[1].slots[1]) == (:slot, :kind, :rng_id, :digest, :name, :length, :sigma, :octaves, :nominal, :series)
        @test [e.execution for e in provA] == [1, 2]
        # the walk's docstring documents the receipt entry WITH `beam`
        @test occursin("beam    = 1", string(@doc Octopus._turn_modulation_provenance!))
        @test occursin("(elements, first_turn, turns)", string(@doc Octopus._turn_modulation_provenance!))

        # (f) `append=true` onto an existing file that is not HDF5: refused by
        # name before the open (HDF5's own "unable to determine if ... is
        # accessible" surfaced first, S5-7), the file untouched, no lock left;
        # a zero-byte file is still treated as fresh.
        pN2 = joinpath(dir, "notart.h5")
        write(pN2, "not an hdf5 file")
        errN = quiet(() -> refusal(() -> execute!(TrackingTask((disp(),); artifact=RunArtifact(pN2; append=true)), mkp(); turns=1)))
        msgN = sprint(showerror, errN)
        @test errN isa ArgumentError
        @test occursin("RunArtifact(append=true): " * pN2 * " exists (16 bytes) and is not an HDF5 file", msgN)
        @test occursin("use a new path or append=false", msgN)
        @test read(pN2, String) == "not an hdf5 file" && !isfile(pN2 * ".lock")
        pZ = joinpath(dir, "zero.h5")
        touch(pZ)
        execute!(TrackingTask((disp(),); artifact=RunArtifact(pZ; append=true)), mkp(); turns=1)
        @test ex_rows(pZ) == 1

        # (g) The partial slot (owner decision 2026-10-16). The writer creates
        # the slot group's cursor `elements_valid_through` at 0 BEFORE the
        # first element group and advances it after each element is complete
        # (its series dataset included), so a writer that stopped mid-way is
        # recognisable: the readers read such a slot as far as the cursor with
        # one warning naming it, never error, never roll back; `append=true`
        # onto the file is refused by name. Built through HDF5 directly, in
        # the two shapes a stopped writer leaves: element 2 half-written, and
        # element 2 never created.
        pP = joinpath(dir, "P.h5")
        set_global_rng!(seed=0x5eed, method=:philox)
        execute!(TrackingTask((disp(), crab(), rf()); artifact=RunArtifact(pP; record_turn_modulation=true)), mkp(); turns=2)
        full = turn_modulation_provenance(pP)
        @test length(full) == 1 && length(full[1].elements) == 2
        @test Octopus._RA_TM_CURSOR == "elements_valid_through"
        HDF5.h5open(pP, "r") do f
            g = f["turn_modulation"]["1"]
            @test read(HDF5.attributes(g)["element_count"]) == 2
            @test read(HDF5.attributes(g)["elements_valid_through"]) == 2
            @test haskey(g["1"], "series") && haskey(g["2"], "series")
        end
        set_cursor!(p, v) = HDF5.h5open(p, "r+") do f
            Octopus._ra_set_attr!(f["turn_modulation"]["1"], "elements_valid_through", Int64(v))
        end
        p1 = joinpath(dir, "P1.h5"); cp(pP, p1)
        set_cursor!(p1, 1)
        HDF5.h5open(p1, "r+") do f
            eg = f["turn_modulation"]["1"]["2"]
            HDF5.delete_attribute(eg, "element")
            HDF5.delete_object(eg, "series")
        end
        p2 = joinpath(dir, "P2.h5"); cp(pP, p2)
        set_cursor!(p2, 1)
        HDF5.h5open(p2, "r+") do f
            HDF5.delete_object(f["turn_modulation"]["1"], "2")
        end
        partial = r"/turn_modulation/1 is partial: 1 of 2 modulated element group\(s\) were written before the writer stopped"
        for p in (p1, p2)
            @testset let partial_file = basename(p)
                prov = @test_logs (:warn, partial) turn_modulation_provenance(p)
                @test length(prov) == 1 && length(prov[1].elements) == 1
                @test prov[1].elements[1] == full[1].elements[1]
                @test (@test_logs (:warn, partial) read(TaskOutput(p), :turn_modulation)) == prov
                toc = @test_logs (:warn, partial) read(TaskOutput(p))
                @test length(toc["turn_modulation"][1].elements) == 1
                @test length((@test_logs (:warn, partial) read(TaskOutput(p), :all)).turn_modulation[1].elements) == 1
                errP = quiet(() -> refusal(() -> execute!(
                    TrackingTask((disp(), crab(), rf()); artifact=RunArtifact(p; append=true, record_turn_modulation=true)),
                    mkp(); turns=1, start_turn=2)))
                msgP = sprint(showerror, errP)
                @test errP isa ArgumentError
                @test occursin("RunArtifact(append=true): /turn_modulation/1 at " * p * " is partial (1 of 2", msgP)
                @test occursin("neither continues past nor rolls back", msgP) && occursin("use a new path", msgP)
                @test ex_rows(p) == 1 && !isfile(p * ".lock")
                @test (@test_logs (:warn, partial) length(turn_modulation_provenance(p)[1].elements)) == 1   # left as found
            end
        end
        # Negative controls: a COMPLETE slot (cursor == count) missing a group
        # is torn as before; a cursor beyond the count is torn; a slot written
        # before the cursor existed reads as complete, and torn on a mismatch.
        p3 = joinpath(dir, "P3.h5"); cp(pP, p3)
        HDF5.h5open(p3, "r+") do f
            HDF5.delete_object(f["turn_modulation"]["1"], "2")
        end
        err3 = refusal(() -> turn_modulation_provenance(p3))
        @test err3 isa ArgumentError && occursin("is torn: element_count = 2 but 1 element group(s) present", sprint(showerror, err3))
        p4 = joinpath(dir, "P4.h5"); cp(pP, p4)
        set_cursor!(p4, 3)
        err4 = refusal(() -> turn_modulation_provenance(p4))
        @test err4 isa ArgumentError && occursin("elements_valid_through = 3 exceeds element_count = 2", sprint(showerror, err4))
        p5 = joinpath(dir, "P5.h5"); cp(pP, p5)
        HDF5.h5open(p5, "r+") do f
            HDF5.delete_attribute(f["turn_modulation"]["1"], "elements_valid_through")
        end
        @test turn_modulation_provenance(p5) == full
        HDF5.h5open(p5, "r+") do f
            HDF5.delete_object(f["turn_modulation"]["1"], "2")
        end
        @test refusal(() -> turn_modulation_provenance(p5)) isa ArgumentError
        # ... and a slot WITHOUT the cursor (a file written before it existed)
        # is not the append check's concern: the append proceeds and the
        # readers judge the slot (the partial slot of p1/p2 above sat in an
        # earlier execution than the refused window: the check walks every slot).
        quiet(() -> execute!(TrackingTask((disp(), crab(), rf()); artifact=RunArtifact(p5; append=true)), mkp(); turns=1, start_turn=2))
        @test ex_rows(p5) == 2
        # the design notes name the cursor and the decision
        for doc in ("docs/design/run_artifact.md", "docs/design/turn_modulation_record.md")
            text = read(joinpath(root, doc), String)
            @test occursin("elements_valid_through", text) && occursin("partial", text)
            @test occursin(":run_artifact_output", text)
        end

        # (h) The recorder's buffers are sized at creation (`sizehint!`,
        # capacity turns of the element's active columns), so the recording
        # hook -- begin, the draws, end -- is allocation-free below the flush
        # (U9-5: 1568 bytes over 62 turns on this fixture before, growth by
        # doubling; 580 bytes per turn averaged on U9's 20-element line).
        w = compile_runtime(crab())
        entries = Octopus._turn_modulation_entries((w,), 1)
        columns = Octopus._turn_modulation_columns!(Any[], (w,))
        pR = joinpath(dir, "R.h5")
        artR = RunArtifact(pR; capacity=64, record_turn_modulation=true)
        Octopus.prepare_run_artifact!(artR, String[], 0, 200; turn_modulation=entries, turn_modulation_columns=columns)
        rec = Octopus._turn_modulation_sink(artR, 1)
        @test length(rec.active[1]) == 2
        @test length(rec.buffers[1].ref.mem) >= 64 * 2         # the hint landed
        hook!(rec, t) = (Octopus._tm_begin_turn!(rec); Octopus._record_turn_draws!(rec, (1.0t, 2.0t, 3.0t, 4.0t));
                         Octopus._tm_end_turn!(rec, t); nothing)
        hook!(rec, 0)                                           # warm-up: turn 0 of the first 64
        @test sum(t -> @allocated(hook!(rec, t)), 1:62) == 0    # turns 1..62, below the flush at 64
        @test rec.rows == 63 && length(rec.buffers[1]) == 126
        Octopus.finalize_run_artifact!(artR)
        @test size(HDF5.h5open(f -> read(f["turn_modulation/1/1/series"]), pR)) == (63, 2)
        set_global_rng!(seed=0x5eed, method=:philox)
    end
end
@testset "Run artifact replay: the prepare validates before it mutates, probe binds commit together, /losses follows the replay rule across a restart" begin
    # 2026-10-19 comprehensive audit, fix unit S: F-56 (four by-name refusals of
    # `prepare_run_artifact!` fired AFTER the replay truncation had dropped every
    # luminosity row at or beyond `first_turn`), F-58 (probe groups were truncated
    # one bind at a time, so a later bind's refusal left the earlier probes cut
    # back) and F-57 (`/losses` was rewritten whole from the current record, so a
    # new task continuing a file emptied it). The window protocol since the fix:
    # `prepare_run_artifact!` validates every refusal of the table
    # `_RA_PREPARE_CHECKS` before it mutates a continued file, every probe bind
    # validates without touching its group, and `commit_run_artifact!` -- called
    # by both task kinds after the last refusal that can stop a run before its
    # first turn -- applies the replay rule to every group at once. Red on
    # cb3c344 with the commit step stubbed as a no-op (the unit's report quotes
    # the run: result/fix_batch_2026_10_19/units/S_report.md).
    HDF5 = Octopus.HDF5
    mktempdir() do dir
        refusal(f) = begin
            err = try; f(); nothing catch e; e end
            (err, err === nothing ? "" : sprint(showerror, err))
        end
        quiet(f) = Test.collect_test_logs(f)[2]      # the registry's sequential-sharing warning is not under test
        lum_rows(p) = HDF5.h5open(f -> length(f["luminosity"]["ip"]["turns"]), p, "r")
        lum_cursor(p) = HDF5.h5open(f -> read(HDF5.attributes(f["luminosity"]["ip"])["rows_valid_through_turn"]), p, "r")
        probe_rows(p, kind, name) = HDF5.h5open(f -> size(f[kind][name]["data"], 1), p, "r")
        ex_rows(p) = HDF5.h5open(f -> length(f["execution"]["start_turn"]), p, "r")
        # A real artifact through the writer's own API, as the audit's probe A
        # built it: the channel "ip" with rows 0..n-1 (cursor n-1), the probe
        # /moments/m with the same turns, one ledger row.
        function build(p; n=100)
            rm(p; force=true); rm(p * ".lock"; force=true)
            art = RunArtifact(p; capacity=1000)
            Octopus.prepare_run_artifact!(art, ["ip"], 0, n; task_kind="suite")
            key = Octopus._ra_bind_probe!(art, "moments", "m", ["turn", "x"], 0)
            Octopus.commit_run_artifact!(art)
            for t in 0:(n - 1)
                Octopus.push_luminosity!(art, "ip", t, 1.0 + t)
            end
            Octopus._ra_push_probe_rows!(art, key, hcat(Float64.(0:(n - 1)), fill(0.5, n)))
            Octopus.finalize_run_artifact!(art)
            return nothing
        end
        # A partial /turn_modulation slot (probe A1b's shape) and a /losses group
        # naming one aperture, both built through HDF5 directly.
        partial!(p) = HDF5.h5open(p, "r+") do f
            g = HDF5.create_group(HDF5.create_group(f, "turn_modulation"), "1")
            HDF5.attributes(g)["element_count"] = Int64(2)
            HDF5.attributes(g)["elements_valid_through"] = Int64(1)
            eg = HDF5.create_group(g, "1")
            HDF5.attributes(eg)["element"] = "ThinCrabCavity"
            HDF5.attributes(eg)["beam"] = Int64(1)
            HDF5.attributes(eg)["slot_count"] = Int64(0)
        end
        losses!(p) = HDF5.h5open(p, "r+") do f
            g = HDF5.create_group(f, "losses")
            g["aperture_names"] = ["COLL"]
            g["aperture_counts"] = Int64[1]
        end

        @testset "F-56: a refused continuation leaves the file byte-identical" begin
            # (a) The two refusals the audit measured (probe A1/A1b): a ledger
            # without the rng_seed column, and a partial provenance slot. Before
            # the fix both fired after the replay truncation: 100 rows and
            # cursor 99 became 50 and 49. An HDF5 "r+" open and close without a
            # write leaves the bytes identical (measured, the unit's probe), so
            # the pin is on the bytes.
            p_col = joinpath(dir, "a1_oldledger.h5"); build(p_col)
            HDF5.h5open(f -> HDF5.delete_object(f["execution"], "rng_seed"), p_col, "r+")
            p_part = joinpath(dir, "a1b_partial.h5"); build(p_part); partial!(p_part)
            for (p, fragment) in ((p_col, "has no rng_seed column(s)"),
                                  (p_part, "/turn_modulation/1 at " * p_part * " is partial (1 of 2"))
                @testset let fixture = basename(p)
                    before = read(p)
                    @test lum_rows(p) == 100 && lum_cursor(p) == 99
                    art = RunArtifact(p; append=true)
                    err, msg = refusal(() -> Octopus.prepare_run_artifact!(art, ["ip"], 50, 10; task_kind="suite"))
                    @test err isa ArgumentError && occursin(fragment, msg)
                    @test read(p) == before
                    @test lum_rows(p) == 100 && lum_cursor(p) == 99 && probe_rows(p, "moments", "m") == 100
                    @test art.file === nothing && !isfile(p * ".lock")
                end
            end
            # (b) The refusal table itself, `_RA_PREPARE_CHECKS`, derived from the
            # code: one fixture per check it lists, each a continuation at turn
            # 50 of a 100-row file that the check refuses and that must come
            # back byte-identical. A check without a fixture here fails by name,
            # so the table cannot grow without its measurement.
            rid = Octopus._unheld_rng_id(Octopus.next_rng_id!() + 4_000_000)
            w = compile_runtime(ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,),
                                                     phase_noise=(WhiteNoise(1.0e-3; rng_id=rid),),
                                                     tracking_method=Symplectic6DMap()))
            entries = Octopus._turn_modulation_entries((w,), 1)
            columns = Octopus._turn_modulation_columns!(Any[], (w,))
            # check => (corrupt the built file, the continuation's labels, its keywords, a fragment of the refusal)
            fixtures = Dict{Function,Tuple}(
                Octopus._ra_check_is_artifact =>
                    (p -> HDF5.h5open(f -> HDF5.delete_object(f, "luminosity"), p, "r+"),
                     ["ip"], (;), "is not a run artifact (no /luminosity group)"),
                Octopus._ra_check_labels =>
                    (p -> nothing, ["other"], (;), "do not match this task's collision labels"),
                Octopus._ra_check_ledger =>
                    (p -> HDF5.h5open(f -> HDF5.delete_object(f, "execution"), p, "r+"),
                     ["ip"], (;), "carries no /execution ledger"),
                Octopus._ra_check_ledger_columns =>
                    (p -> HDF5.h5open(f -> HDF5.delete_object(f["execution"], "rng_method"), p, "r+"),
                     ["ip"], (;), "has no rng_method column(s)"),
                Octopus._ra_check_partial_slots =>
                    (partial!, ["ip"], (;), "is partial (1 of 2"),
                Octopus._ra_check_loss_apertures =>
                    (losses!, ["ip"], (; aperture_names=["OTHER"]), "the /losses group at"),
                Octopus._ra_check_turn_modulation =>
                    (p -> HDF5.h5open(f -> HDF5.create_group(HDF5.create_group(f, "turn_modulation"), "2"), p, "r+"),
                     ["ip"], (; turn_modulation=entries, turn_modulation_columns=columns),
                     "/turn_modulation/2 already exists"),
            )
            @test !isempty(Octopus._RA_PREPARE_CHECKS)
            for check in Octopus._RA_PREPARE_CHECKS
                @testset let refusal_step = nameof(check)
                    @test haskey(fixtures, check)
                    if haskey(fixtures, check)
                        corrupt!, labels, kw, fragment = fixtures[check]
                        p = joinpath(dir, "table_" * String(nameof(check)) * ".h5")
                        build(p)
                        corrupt!(p)
                        before = read(p)
                        art = RunArtifact(p; append=true)
                        err, msg = refusal(() -> Octopus.prepare_run_artifact!(art, labels, 50, 10;
                                                                                task_kind="suite", kw...))
                        @test err isa ArgumentError && occursin(fragment, msg)
                        @test read(p) == before
                        @test art.file === nothing && !isfile(p * ".lock")
                    end
                end
            end
            # (c) The two structural facts the table rests on, read from the
            # source by its package path: the prepare runs the table in one loop
            # after the open and before its first ledger write, and no by-name
            # refusal of an OPEN file lives outside the table.
            lines = split(read(joinpath(pkgdir(Octopus), "src", "tasks", "RunArtifact.jl"), String), '\n')
            start = findfirst(l -> startswith(l, "function prepare_run_artifact!("), lines)
            stop = findnext(==("end"), lines, start)
            body = lines[start:stop]
            open_at = findfirst(l -> occursin("HDF5.h5open(art.path", l), body)
            loop_at = findfirst(l -> occursin("for check in _RA_PREPARE_CHECKS", l), body)
            mutate_at = findfirst(l -> occursin("HDF5.set_extent_dims(d, (n + 1,))", l), body)
            @test open_at !== nothing && loop_at !== nothing && mutate_at !== nothing
            @test open_at < loop_at < mutate_at
            @test !any(l -> occursin("throw(ArgumentError(", l), body[(open_at + 1):end])
        end

        @testset "F-58: every probe bind is validated before any group is truncated or created" begin
            mkrep() = Phase6DRep([1.0e-4, -2.0e-4], zeros(2), [3.0e-5, 0.0], zeros(2), [1.0e-2, -1.0e-2], zeros(2))
            pE = joinpath(dir, "e1_bind.h5")
            line1 = (DriftSpec(L=1.0), ScheduledObserver(MomentObserver(; name="m1", orders=1)),
                     ScheduledObserver(MomentObserver(; name="m2", orders=1)))
            execute!(TrackingTask(line1; artifact=RunArtifact(pE; append=true)), mkrep(); turns=10)
            @test probe_rows(pE, "moments", "m1") == 10 && probe_rows(pE, "moments", "m2") == 10
            # Window 2 replays from turn 5 with m2's columns CHANGED (orders 1:2)
            # and a new probe m3 bound before it: m2's bind is refused. Before
            # the fix m1 was already cut back to 5 rows and m3's empty group
            # created; the refused window keeps only its ledger row.
            line2 = (DriftSpec(L=1.0), ScheduledObserver(MomentObserver(; name="m1", orders=1)),
                     ScheduledObserver(MomentObserver(; name="m3", orders=1)),
                     ScheduledObserver(MomentObserver(; name="m2", orders=1:2)))
            t2 = TrackingTask(line2; artifact=RunArtifact(pE; append=true))
            err, msg = quiet(() -> refusal(() -> execute!(t2, mkrep(); turns=5, start_turn=5)))
            @test err isa ArgumentError && occursin("the probe group /moments/m2 at " * pE * " carries columns", msg)
            @test probe_rows(pE, "moments", "m1") == 10 && probe_rows(pE, "moments", "m2") == 10
            @test !HDF5.h5open(f -> haskey(f["moments"], "m3"), pE, "r")
            @test t2.artifact.file === nothing && !isfile(pE * ".lock")
            @test ex_rows(pE) == 2
            # Positive control: the same continuation with m2's columns unchanged
            # replays both probes from turn 5 and creates m3 at the commit.
            line3 = (DriftSpec(L=1.0), ScheduledObserver(MomentObserver(; name="m1", orders=1)),
                     ScheduledObserver(MomentObserver(; name="m3", orders=1)),
                     ScheduledObserver(MomentObserver(; name="m2", orders=1)))
            quiet(() -> execute!(TrackingTask(line3; artifact=RunArtifact(pE; append=true)), mkrep(); turns=5, start_turn=5))
            for (name, turns) in (("m1", 0:9), ("m2", 0:9), ("m3", 5:9))
                @test Int.(read(TaskOutput(pE), :moments; name=name).turn) == collect(turns)
            end
            # Through the writer's API: a bind refused after the prepare leaves
            # the luminosity channel untruncated too -- the replay rule is
            # applied only by the commit, after the last bind -- and a refused
            # window finalizes as found.
            pB = joinpath(dir, "bind_lum.h5"); build(pB)
            artB = RunArtifact(pB; append=true)
            quiet(() -> Octopus.prepare_run_artifact!(artB, ["ip"], 50, 10; task_kind="suite"))
            errB, msgB = refusal(() -> Octopus._ra_bind_probe!(artB, "moments", "m", ["turn", "y"], 50))
            @test errB isa ArgumentError && occursin("carries columns", msgB)
            @test lum_rows(pB) == 100 && probe_rows(pB, "moments", "m") == 100
            Octopus.finalize_run_artifact!(artB)
            @test lum_rows(pB) == 100 && lum_cursor(pB) == 99 && probe_rows(pB, "moments", "m") == 100
            # Rows cannot arrive before the commit (refused by name, never
            # silently appended beyond stale rows); the commit truncates every
            # group at once; it runs once, and no probe binds after it.
            artC = RunArtifact(pB; append=true)
            quiet(() -> Octopus.prepare_run_artifact!(artC, ["ip"], 50, 10; task_kind="suite"))
            keyC = Octopus._ra_bind_probe!(artC, "moments", "m", ["turn", "x"], 50)
            errR, msgR = refusal(() -> Octopus.push_luminosity!(artC, "ip", 50, 1.0))
            @test errR isa ErrorException && occursin("commit_run_artifact!", msgR)
            errP, msgP = refusal(() -> Octopus._ra_push_probe_rows!(artC, keyC, [50.0 1.0]))
            @test errP isa ErrorException && occursin("commit_run_artifact!", msgP)
            @test lum_rows(pB) == 100 && probe_rows(pB, "moments", "m") == 100
            Octopus.commit_run_artifact!(artC)
            @test lum_rows(pB) == 50 && lum_cursor(pB) == 49 && probe_rows(pB, "moments", "m") == 50
            @test refusal(() -> Octopus.commit_run_artifact!(artC))[1] isa ErrorException
            @test refusal(() -> Octopus._ra_bind_probe!(artC, "moments", "late", ["turn"], 50))[1] isa ArgumentError
            Octopus.push_luminosity!(artC, "ip", 50, 1.0)
            Octopus._ra_push_probe_rows!(artC, keyC, [50.0 1.0])
            Octopus.finalize_run_artifact!(artC)
            @test lum_rows(pB) == 51 && lum_cursor(pB) == 50 && probe_rows(pB, "moments", "m") == 51
        end

        @testset "F-57: /losses follows the replay rule across windows and a new-task restart" begin
            line(name="COLL") = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name=name), DriftSpec(L=0.5))
            lossy() = Phase6DRep([1.0e-3, 5.0e-3], zeros(2), [0.0, 1.0e-4], zeros(2), zeros(2), zeros(2))
            clean() = Phase6DRep([1.0e-4, -1.0e-4], zeros(2), zeros(2), zeros(2), zeros(2), zeros(2))
            pL = joinpath(dir, "losses_restart.h5")
            losses() = read(TaskOutput(pL), :losses)
            run!(task, rep; kw...) = quiet(() -> allow_lost_particles(() -> execute!(task, rep; kw...); enabled=true))
            # Window 1 (task A): particle 2 is outside the aperture and lost at turn 0.
            tA = TrackingTask(line(); artifact=RunArtifact(pL; append=true))
            run!(tA, lossy(); turns=3)
            l1 = losses()
            @test l1.turn == [0.0] && l1.particle_id == [2.0] && l1.aperture_counts == [1] && l1.summary.dead == 1
            # Window 2 (the same task, a FRESH beam object, so the record -- the
            # beam's -- is reallocated): particle 2 is lost again, at turn 3.
            # The file keeps window 1's row beside it; before the fix the whole
            # rewrite from the new record left one row at turn 3.
            run!(tA, lossy(); turns=3)
            l2 = losses()
            @test l2.turn == [0.0, 3.0] && l2.particle_id == [2.0, 2.0] && l2.element_id == [1.0, 1.0]
            @test l2.aperture_counts == [2] && l2.summary.dead == 1 && l2.summary.logged == 1
            # Window 3 (a process restart: a NEW task object continues the file):
            # nothing is lost and the earlier windows' rows and counts survive.
            # Before the fix: 0 rows, counts [0], dead 0, three ledger rows.
            tB = TrackingTask(line(); artifact=RunArtifact(pL; append=true))
            run!(tB, clean(); turns=3, start_turn=6)
            l3 = losses()
            @test l3.turn == [0.0, 3.0] && l3.aperture_counts == [2]
            @test l3.summary.dead == 0 && l3.summary.logged == 0 && l3.summary.particles == 2
            @test read(TaskOutput(pL), :execution).start_turn == [0, 3, 6]
            # Window 4 replays turns 3..5 with a new task and a lossy beam: window
            # 2's row at turn 3 is dropped by the replay rule and re-recorded,
            # window 1's row stays, and the counts follow the rows.
            tC = TrackingTask(line(); artifact=RunArtifact(pL; append=true))
            run!(tC, lossy(); turns=3, start_turn=3)
            l4 = losses()
            @test l4.turn == [0.0, 3.0] && l4.particle_id == [2.0, 2.0] && l4.aperture_counts == [2]
            @test l4.summary.dead == 1 && l4.summary.logged == 1
            HDF5.h5open(pL, "r") do f
                g = f["losses"]
                @test read(HDF5.attributes(g)["record_count"]) == 2
                @test read(HDF5.attributes(g)["summary_folded"]) == 1
            end
            # The same beam continuing in one process (the chunked run) stays
            # idempotent: the record's earlier rows ARE the file's earlier rows,
            # kept once.
            pS = joinpath(dir, "losses_split.h5")
            tS = TrackingTask(line(); artifact=RunArtifact(pS; append=true))
            beam = lossy()
            run!(tS, beam; turns=2)
            run!(tS, beam; turns=3)
            lS = read(TaskOutput(pS), :losses)
            @test lS.turn == [0.0] && lS.particle_id == [2.0] && lS.aperture_counts == [1] && lS.summary.logged == 1
            # A continued file whose /losses names other apertures -- or a line
            # with no aperture at all -- is refused at prepare, as found: the
            # rows' element ids are interpreted under the file's names.
            before = read(pL)
            for (task_line, label) in ((line("OTHER"), "renamed"), ((DriftSpec(L=1.0),), "none"))
                @testset let apertures = label
                    tD = TrackingTask(task_line; artifact=RunArtifact(pL; append=true))
                    errD, msgD = refusal(() -> quiet(() -> execute!(tD, clean(); turns=1, start_turn=9)))
                    @test errD isa ArgumentError && occursin("the /losses group at " * pL, msgD) && occursin("COLL", msgD)
                    @test read(pL) == before && !isfile(pL * ".lock") && tD.artifact.file === nothing
                end
            end
        end

        @testset "every task kind commits the window it prepared" begin
            # Derived from the tree: each src/ file with a `prepare_run_artifact!`
            # call site also calls `commit_run_artifact!` (the existing tripwire
            # pins the two call sites and their task_kind).
            srcfiles = String[]
            for (d, _, fs) in walkdir(joinpath(pkgdir(Octopus), "src")), f in fs
                endswith(f, ".jl") && push!(srcfiles, joinpath(d, f))
            end
            callsites = [f for f in srcfiles if occursin(r"^\s+prepare_run_artifact!\("m, read(f, String))]
            @test length(callsites) == 2
            @test all(f -> occursin(r"^\s+.*commit_run_artifact!\("m, read(f, String)), callsites)
        end
    end
end
@testset "The path registry warns for a writer still open, not for a finished writer's path continued" begin
    # 2026-08-05_b audit, U7-10: two live standalone observers writing one
    # path ended self-consistent and wrong, so a process-wide registry (weak
    # identity) warned at the second's initialization. Re-homed on the run
    # artifact when the standalone writers retired (2026-08-18). Since the
    # sidecar lock (2026-10-16) a second writer on an OPEN path is refused
    # before the registry sees it, so the warning had exactly one way left to
    # fire -- a NEW artifact object continuing or rewriting a path whose
    # previous writer had finished and closed, the legitimate sequential case
    # -- with wording about observers that interleave (comprehensive audit
    # 2026-10-18, F-85; fix batch 3, unit G). The registry asks now whether
    # the earlier artifact still holds its file OPEN (a lock removed by hand
    # is the one way two open writers can meet) and says so in artifact
    # terms; a finished writer's path is silent.
    mkp() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)
    registry_warnings(lg) = count(l -> l.level >= Logging.Warn && occursin("still holds open", string(l.message)), lg)
    old_wording(lg) = count(l -> occursin("second live observer", string(l.message)), lg)
    p = tempname() * ".h5"
    t1 = TrackingTask(dline; artifact=RunArtifact(p; append=true))
    lg, _ = Test.collect_test_logs() do
        execute!(t1, mkp(); turns=3)
        execute!(t1, mkp(); turns=4, start_turn=3)
    end
    @test registry_warnings(lg) == 0 && old_wording(lg) == 0        # the same task continuing: documented, silent
    t2 = TrackingTask(dline; artifact=RunArtifact(p; append=true))   # a new object; t1 finished, closed, still alive
    lg2, _ = Test.collect_test_logs() do
        execute!(t2, mkp(); turns=2, start_turn=7)
    end
    @test t1.artifact.file === nothing
    @test registry_warnings(lg2) == 0 && old_wording(lg2) == 0       # was 1: "a second live observer is initializing ..."
    @test read(TaskOutput(p), :execution).start_turn == [0, 3, 7]
    # the one reachable collision: an earlier artifact whose writer still
    # holds the file open, asked of the registry directly (end to end the lock
    # refuses it first, by design)
    p3 = tempname() * ".h5"
    open_art = RunArtifact(p3)
    Octopus.prepare_run_artifact!(open_art, String[], 0, 1)
    try
        @test open_art.file !== nothing
        lg3, _ = Test.collect_test_logs() do
            Octopus._register_observer_path!(RunArtifact(p3; append=true), p3)
        end
        @test registry_warnings(lg3) == 1
        @test occursin("run artifact", string(lg3[1].message)) && !occursin("observer", string(lg3[1].message))
    finally
        Octopus.finalize_run_artifact!(open_art)
    end
    lg4, _ = Test.collect_test_logs() do
        Octopus._register_observer_path!(RunArtifact(p3; append=true), p3)   # the writer closed: silent
    end
    @test registry_warnings(lg4) == 0
    rm(p; force=true)
    rm(p3; force=true)
end
@testset "BPM reads a device number, not the truth" begin
    line = (QuadrupoleSpec(L=0.4, k1=1.7, nst=4), DriftSpec(L=0.6),
            QuadrupoleSpec(L=0.4, k1=-1.7, nst=4), DriftSpec(L=0.6))
    mkrep() = Phase6DRep([1.0e-3, 2.0e-3, -1.0e-3], [1.0e-4, -2.0e-4, 0.5e-4],
                         [0.5e-3, -1.5e-3, 2.0e-3], [2.0e-4, 1.0e-4, -1.0e-4],
                         [0.0, 0.0, 0.0], [1.0e-3, -1.0e-3, 0.0])

    # The reason a BPM is an observer and not an element: a zero-length element
    # cannot carry a reading offset. The entrance and exit frames cancel, so a
    # misaligned marker is the identity TO ROUNDING -- the machinery runs and
    # the map returns each coordinate within one ulp: `(x - dx) + dx == x` is
    # not an IEEE identity, it holds or misses by one ulp with the operands'
    # exponents (bitwise on this fixture, one ulp off on 6884 of 20000 random
    # coordinate sets; 2026-10-18 audit F-218/U35-3, the former `==` rested on
    # this fixture's rounding). Documented in
    # docs/theory/bpm_measurement_model.md Sec. 2.
    let u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
        plain = compile_runtime(MarkerSpec())
        moved = compile_runtime(MarkerSpec(x_offset=1.0e-3, y_offset=-8.0e-4))
        @test moved isa MisalignedElement          # the wrap really is applied
        @test all(abs(a - b) <= eps(abs(b)) for (a, b) in zip(moved(u...), plain(u...)))   # and does nothing, to one ulp
    end

    # Zero errors must return the centroid itself, which is what ties the new
    # readout path to the already-validated moment reduction.
    let bpm = BPMObserver("b1"), rep = mkrep()
        execute!(TrackingTask(line; hooks=(ScheduledObserver(bpm),)), rep; turns=3)
        turns, xs, ys = readings(bpm)
        st = beam_statistics(rep)
        @test turns == [0, 1, 2]
        @test xs[end] == st.mean[1]
        @test ys[end] == st.mean[3]
    end

    # A BPM is passive: tracking must be bit-identical with and without one.
    let r1 = mkrep(), r2 = mkrep()
        execute!(TrackingTask(line), r1; turns=3)
        execute!(TrackingTask(line; hooks=(ScheduledObserver(BPMObserver("b2")),)), r2; turns=3)
        @test collect(r1[1]) == collect(r2[1])
    end

    # The model reduces exactly to MAD-X's `reading = (1+MSCAL)*true + MRE`.
    let m = BPMObserver("madx"; x_gain=0.5, x_readout=1.0e-4, y_gain=-0.3, y_readout=-2.0e-5)
        rx, ry = bpm_reading(m, 2.0e-3, 1.0e-3, 0)
        @test rx == 1.5 * 2.0e-3 + 1.0e-4
        @test ry == 0.7 * 1.0e-3 - 2.0e-5
    end

    # Signs and geometry. The offset is a body position and SUBTRACTS (Bmad),
    # unlike MAD-X's MREX which is a reading bias and is x_readout here.
    @test bpm_reading(BPMObserver("o"; x_offset=1.0e-3), 0.0, 0.0, 0)[1] == -1.0e-3
    @test bpm_reading(BPMObserver("b"; x_readout=1.0e-3), 0.0, 0.0, 0)[1] == +1.0e-3
    let (rx, ry) = bpm_reading(BPMObserver("r"; tilt=pi / 2), 1.0e-3, 0.0, 0)
        @test abs(rx) < 1.0e-18
        @test ry ≈ -1.0e-3 atol = 1.0e-18
    end

    # Every error term has to reach the reading, in the spirit of the element
    # parameter effectiveness contract -- the misaligned marker above is the
    # cautionary tale for what a silently-inert parameter looks like.
    for kw in (:x_offset, :y_offset, :tilt, :x_gain, :y_gain,
               :x_readout, :y_readout, :x_noise, :y_noise)
        base = bpm_reading(BPMObserver("z"), 1.3e-3, -0.7e-3, 1)
        moved = bpm_reading(BPMObserver("z"; (kw => 3.7e-3,)...), 1.3e-3, -0.7e-3, 1)
        @test moved != base
    end

    # Noise is a counter-RNG draw keyed by turn and rng_id, so it reproduces
    # across chunked execution -- the invariant the tracking RNG already holds.
    let
        set_global_rng!(seed=999)
        a = BPMObserver("c"; x_noise=1.0e-5, rng_id=42)
        ra = mkrep()
        execute!(TrackingTask(line; hooks=(ScheduledObserver(a),)), ra; turns=4)
        set_global_rng!(seed=999)
        b = BPMObserver("c"; x_noise=1.0e-5, rng_id=42)
        rb = mkrep()
        task = TrackingTask(line; hooks=(ScheduledObserver(b),))
        execute!(task, rb; turns=2)
        execute!(task, rb; turns=2)
        @test readings(b)[1] == [0, 1, 2, 3]
        @test readings(a)[2] == readings(b)[2]
    end

    # Noise of the requested width, and two BPMs must not share a stream.
    let bpm = BPMObserver("n"; x_noise=2.0e-5, rng_id=5)
        s = [bpm_reading(bpm, 0.0, 0.0, t)[1] for t in 1:4000]
        @test abs(sum(s) / length(s)) < 3.0e-6
        @test 1.8e-5 < sqrt(sum(abs2, s) / length(s)) < 2.2e-5
        other = BPMObserver("n2"; x_noise=2.0e-5, rng_id=6)
        @test bpm_reading(bpm, 0.0, 0.0, 1)[1] != bpm_reading(other, 0.0, 0.0, 1)[1]
    end

    @test_throws ArgumentError BPMObserver("bad"; x_noise=-1.0)
    @test_throws ArgumentError BPMObserver("bad"; y_noise=-1.0)
end
@testset "A Float32 beam's BPM centroid accumulates in Float64, as the moment observer does" begin
    # Fix batch 3 (2026-10-21), unit G: comprehensive audit F-88. `_mean(v)`
    # is `sum(v)/length(v)` in the array's element type, so a Float32 beam's
    # BPM centroid was a Float32 (2.64e-11 m from the Float64-accumulated
    # moment, 1.2e8 Float64 ulps, probe p5) while the moment observer
    # promotes every term -- one centroid, two accumulation precisions. The
    # BPM accumulates in Float64 on both its paths now; Float64 readings do
    # not move (`sum(Float64, v) === sum(v)` on Float64 data: the same
    # pairwise reduction, measured on 100,003 terms).
    rng = MersenneTwister(88)
    n = 100_000
    mk(T) = T.(1.0e-3 .+ 1.0e-3 .* randn(rng, n))
    ctx = TrackingContext(turn=0)
    r64 = Phase6DRep((mk(Float64) for _ in 1:6)...)
    @test Octopus._bpm_centroid(r64) === (Octopus._mean(r64.x), Octopus._mean(r64.y))   # Float64 unmoved, bitwise
    r32 = Phase6DRep((mk(Float32) for _ in 1:6)...)
    xb, yb = Octopus._bpm_centroid(r32)
    @test xb isa Float64 && yb isa Float64                                              # was Float32
    row = Octopus._moment_observer_row(ctx, r32, (Moment(x=1), Moment(y=1)))
    # the two accumulations now differ only by pairwise-vs-serial roundoff,
    # of order sqrt(n) eps = 316 eps at n = 1e5 (measured 17 ulp on Float64
    # data, p5); 4096 ulp is thirteen such sigmas and 3e4 times under the
    # Float32 accumulation's 1.2e8
    @test abs(xb - row[2]) <= 4096 * eps(row[2]) && abs(yb - row[3]) <= 4096 * eps(row[3])   # was 1.2e8 ulp
    @test xb == sum(Float64, r32.x) / n
    # the masked path: Float64 accumulation over the survivors, exactly the serial sum
    for i in (5, 500, 99_999), a in coordinate_arrays(r32)
        a[i] = NaN32
    end
    xm, ym = allow_lost_particles(() -> Octopus._bpm_centroid(r32); enabled=true)
    live = [Octopus.is_live(r32, i) for i in 1:n]
    serial(v) = (s = 0.0; for i in 1:n; live[i] && (s += v[i]); end; s / count(live))
    @test xm isa Float64 && xm == serial(r32.x) && ym == serial(r32.y)
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        h = Phase6DRep((mk(Float32) for _ in 1:6)...)
        g = Phase6DRep((Octopus.CUDA.CuArray(a) for a in coordinate_arrays(h))...)
        gx, gy = Octopus._bpm_centroid(g)
        @test gx isa Float64 && gy isa Float64                                          # was Float32
        @test abs(gx - sum(Float64, h.x) / n) <= 4096 * eps(gx) && abs(gy - sum(Float64, h.y) / n) <= 4096 * eps(gy)
    else
        @test_skip "CUDA device not available: the device-side Float64 accumulation is not exercised"
    end
end
# A no-op observer for the repeated-placement refusal below and the fused-row
# baseline later in the file (unit G, fix batch 3). Defined HERE, before its first
# use: the suite runs top to bottom, and the definition sat 2,000 lines below this
# testset until the batch's second gate attempt errored on it (2026-10-22); every
# stage-runner preamble had supplied it, which is why no cut block saw the gap.
struct _FixGNoopObserver <: Octopus.AbstractBeamObserver end
Octopus.observe!(::_FixGNoopObserver, ::Octopus.TrackingContext, rep) = nothing
@testset "One observer placed twice in a line is refused by name in artifact mode and still read twice in memory mode" begin
    # Fix batch 3 (2026-10-21), unit G: comprehensive audit F-89. One
    # BPMObserver placed twice -- the "read twice in one turn" pattern its
    # occurrence counter exists for, which works in memory mode -- was refused
    # in artifact mode as `duplicate probe name`: a message about a NAME two
    # objects share, when the user placed one object twice (and one `s`
    # attribute could not have represented two positions). The prepare walks
    # count placements by object identity now, and an observer that binds one
    # artifact group (MomentObserver, CoordinateSnapshotObserver, a BPM with
    # artifact=true) is refused by its cause before any bind; a memory-mode
    # BPM may be placed as often as the lattice has pickups for it.
    rep1() = Phase6DRep([1.0e-4, 3.0e-4], [0.0, 0.0], [2.0e-4, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0])
    @test Octopus._observer_binds_one_group(MomentObserver(name="m"))
    @test Octopus._observer_binds_one_group(CoordinateSnapshotObserver(name="s"))
    @test Octopus._observer_binds_one_group(BPMObserver("b"; artifact=true))
    @test !Octopus._observer_binds_one_group(BPMObserver("b"))
    @test !Octopus._observer_binds_one_group(_FixGNoopObserver())
    # memory mode, twice: two readings per turn with distinct noise (the T9 pattern)
    let b = BPMObserver("twice"; x_noise=1.0e-6)
        execute!(TrackingTask((DriftSpec(L=0.5), ScheduledObserver(b), DriftSpec(L=0.5), ScheduledObserver(b))), rep1(); turns=2)
        tu, x, _ = readings(b)
        @test tu == [0, 0, 1, 1] && x[1] != x[2] && x[3] != x[4]
    end
    mktempdir() do dir
        msg(f) = try
            f()
            "did not throw"
        catch e
            e isa ArgumentError ? sprint(showerror, e) : rethrow()
        end
        # artifact mode, the same object twice in the line: refused by its cause
        b = BPMObserver("twice"; x_noise=1.0e-6, artifact=true)
        t = TrackingTask((DriftSpec(L=0.5), ScheduledObserver(b), DriftSpec(L=0.5), ScheduledObserver(b));
                         artifact=RunArtifact(joinpath(dir, "twice.h5")))
        m1 = msg(() -> execute!(t, rep1(); turns=2))
        @test occursin("BPMObserver", m1) && occursin("twice", m1) && occursin("placed 2 times", m1)   # was "duplicate probe name"
        @test !occursin("duplicate probe name", m1)
        @test t.artifact.file === nothing                                   # the refusal closed the artifact
        # the same MomentObserver object twice among the task hooks
        m = MomentObserver(name="m"; orders=1)
        t2 = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(m), ScheduledObserver(m)),
                          artifact=RunArtifact(joinpath(dir, "hooks.h5")))
        m2 = msg(() -> execute!(t2, rep1(); turns=2))
        @test occursin("MomentObserver", m2) && occursin("placed 2 times", m2)
        # two DISTINCT objects sharing a name are still the artifact's refusal
        t3 = TrackingTask((DriftSpec(L=1.0),);
                          hooks=(ScheduledObserver(MomentObserver(name="m"; orders=1)),
                                 ScheduledObserver(MomentObserver(name="m"; orders=1))),
                          artifact=RunArtifact(joinpath(dir, "distinct.h5")))
        @test occursin("duplicate probe name", msg(() -> execute!(t3, rep1(); turns=2)))
        # one object, one placement: records at its arc position as before
        b1 = BPMObserver("once"; artifact=true)
        t4 = TrackingTask((DriftSpec(L=0.5), ScheduledObserver(b1), DriftSpec(L=0.5)); artifact=RunArtifact(joinpath(dir, "once.h5")))
        execute!(t4, rep1(); turns=2)
        out = read(TaskOutput(joinpath(dir, "once.h5")), :bpm; name="once")
        @test out.turn == [0, 1] && out.s == 0.5
    end
end
@testset "The BPM device model is on record: the :bpm_reading receipt and the /bpm attributes" begin
    # Fix batch 3 (2026-10-21), unit G: comprehensive audit F-90. The nine
    # device-model options declare the consumer `:bpm_reading`, under which
    # no receipt was ever recorded, and `/bpm/<name>` carried `name`, `s` and
    # the cursor only: a run with `x_offset = 1e-4` and one with `x_offset =
    # 0` were indistinguishable from their receipts and from the file.
    # `bpm_reading` records a `:bpm_reading` receipt per reading now, carrying
    # every option the schema names under that consumer with the value it
    # applied, and the bind stamps the model on the group as attributes the
    # public reader returns under `attrs`. The pairing below is DERIVED from
    # the schema, so an option added without its receipt field or attribute
    # fails here by name.
    rep1() = Phase6DRep([1.0e-4, 3.0e-4], [0.0, 0.0], [2.0e-4, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0])
    schema = observer_option_schema(BPMObserver)
    model_keys = [k for (k, m) in pairs(schema) if m.consumer === :bpm_reading]
    @test :x_offset in model_keys && :rng_id in model_keys && !(:artifact in model_keys)
    rid = Octopus._unheld_rng_id(next_rng_id!() + 4_000_000)
    kw = (x_offset=1.0e-4, y_offset=-2.0e-4, tilt=0.01, x_gain=0.02, y_gain=-0.03,
          x_readout=5.0e-6, y_readout=-7.0e-6, x_noise=1.0e-6, y_noise=2.0e-6)
    mktempdir() do dir
        p = joinpath(dir, "model.h5")
        bpm = BPMObserver("ipbpm"; kw..., rng_id=rid, artifact=true)
        for (k, m) in pairs(schema)
            k === :name && continue
            @test getproperty(bpm, k) != m.default            # the carries-every-option rule
        end
        audit = with_execution_audit() do
            execute!(TrackingTask((DriftSpec(L=0.5), ScheduledObserver(bpm), DriftSpec(L=0.5),
                                   ScheduledObserver(MomentObserver(name="m"; orders=1)));
                                  artifact=RunArtifact(p)), rep1(); turns=3)
        end
        rs = [r for r in execution_receipts(audit) if r.consumer === :bpm_reading]
        @test length(rs) == 3                                               # was 0: no site recorded the consumer
        for k in model_keys, r in rs
            @testset let option = k, turn = r.values.turn
                @test haskey(r.values, k)
                if k === :name
                    @test String(r.values.name) == "ipbpm"
                else
                    @test r.values[k] == getproperty(bpm, k)
                end
            end
        end
        @test [r.values.turn for r in rs] == [0, 1, 2]
        @test all(r.values.noise_drawn === true && r.values.occurrence == 0 for r in rs)
        # the file: the model as attributes beside `name` and `s` ...
        HDF5 = Octopus.HDF5
        attrs = HDF5.h5open(p, "r") do f
            a = HDF5.attributes(f["bpm/ipbpm"])
            Dict(String(k) => read(a[k]) for k in keys(a))
        end
        for k in model_keys
            k === :name && continue
            @testset let attribute = k
                @test haskey(attrs, String(k)) && attrs[String(k)] == getproperty(bpm, k)   # was absent
            end
        end
        @test attrs["name"] == "ipbpm" && attrs["s"] == 0.5
        # ... read back by the public reader under `attrs`, empty for a group
        # that stamps none
        out = read(TaskOutput(p), :bpm; name="ipbpm")
        @test out.s == 0.5 && out.turn == [0, 1, 2]
        @test haskey(out, :attrs) && out.attrs.x_offset == 1.0e-4 && out.attrs.rng_id == rid
        @test Set(keys(out.attrs)) == Set(k for k in model_keys if k !== :name)
        @test read(TaskOutput(p), :moments; name="m").attrs == (;)
        # a noiseless BPM draws nothing and its receipt says so
        quiet = BPMObserver("quiet"; x_offset=1.0e-4)
        audit2 = with_execution_audit() do
            observe!(quiet, TrackingContext(turn=4), rep1())
        end
        r2 = only(r for r in execution_receipts(audit2) if r.consumer === :bpm_reading)
        @test r2.values.noise_drawn === false && r2.values.occurrence === nothing && r2.values.x_noise == 0.0
        @test r2.values.x_offset == 1.0e-4 && r2.values.turn == 4
    end
    @test validate_configuration_metadata()
end
@testset "BPM memory arrays and the /bpm group agree under append=true and diverge by design under append=false" begin
    # Fix batch 3 (2026-10-21), unit G: comprehensive audit F-86. The BPM
    # docstring said "the memory arrays and the artifact cannot disagree" --
    # true under `append=true`, where the bind truncates the group to the
    # same boundary the memory discard keeps, and false under the default
    # `append=false`, which recreates the FILE per execute!: after two
    # execute!(turns=3) the group holds turns 3:5 and memory 0:5 (probe p1,
    # block D). The text states the condition now; this pins both behaviours
    # and the text.
    rep1() = Phase6DRep([1.0e-4], [0.0], [2.0e-4], [0.0], [0.0], [0.0])
    mktempdir() do dir
        for (append, want_file) in ((true, 0:5), (false, 3:5))
            b = BPMObserver("b"; artifact=true)
            p = joinpath(dir, "append_$(append).h5")
            t = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(b),),
                             artifact=RunArtifact(p; append=append, capacity=3))
            r = rep1()
            execute!(t, r; turns=3)
            execute!(t, r; turns=3)
            @testset let append = append
                @test readings(b)[1] == collect(0:5)
                @test Int.(read(TaskOutput(p), :bpm; name="b").turn) == collect(want_file)
            end
        end
    end
    doc = string(Base.Docs.doc(Base.Docs.Binding(Octopus, :BPMObserver)))
    @test occursin("append=true", doc) && occursin("append=false", doc)     # was: an unconditional "cannot disagree"
    @test !occursin("cannot disagree", doc)
end
@testset "MomentObserver task reuse" begin
    path = tempname() * ".h5"
    try
        observer = MomentObserver(; name="reuse", orders=1)
        hook = ScheduledObserver(observer)
        task = TrackingTask((hook,); artifact=path)
        rep = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])

        execute!(task, rep; turns=1)
        @test observer.record_count == 1
        @test !observer.initialized
        execute!(task, rep; turns=2)
        @test observer.record_count == 2
        @test !observer.initialized
    finally
        rm(path; force=true)
    end
end
@testset "The coordinate snapshot copies npart particles, not the beam" begin
    # Fix batch 3 (2026-10-21), unit G: comprehensive audit F-79. `observe!`
    # built each column as `Array(col)[1:nlocal]` -- the WHOLE array copied (a
    # full device-to-host transfer on CUDA: 122.9 MB and 29.4 ms per fire at
    # N = 2.56e6 for npart = 16) and then sliced -- so the `npart` knob the
    # docstring offers for controlling snapshot volume controlled nothing of
    # the cost. The block is built from `view(col, 1:nlocal)` now: nlocal
    # elements moved, on either backend.
    rng = MersenneTwister(79)
    n = 200_000
    r = Phase6DRep((randn(rng, n) .* 1.0e-4 for _ in 1:6)...)
    # (a) the block builder: the leading particles bit for bit, and an
    # allocation of the block's own size (8 x npart Float64 plus the six
    # view copies), not the beam's
    block = Octopus._snapshot_block(r, 0, 16, 7)
    @test size(block) == (16, 8) && block[:, 1] == fill(7.0, 16) && block[:, 2] == 1.0:16.0
    @test all(block[:, 2 + j] == coordinate_arrays(r)[j][1:16] for j in 1:6)
    @test (@allocated Octopus._snapshot_block(r, 0, 16, 7)) < 16 * 8 * 8 * 4 + 4096      # was 6 x 8 x N = 9.6 MB
    # a shard offset: particle ids are global, the rows this rank's part of 1:npart
    shard = Octopus._snapshot_block(r, 100, 3, 2)
    @test shard[:, 2] == [101.0, 102.0, 103.0] && shard[:, 3] == r.x[1:3]
    @test size(Octopus._snapshot_block(r, 0, 0, 2)) == (0, 8)
    # (b) through the task loop: the fire's own allocation -- the 16-row block
    # and the artifact push -- against a no-op observer's turn, bounded at an
    # eighth of the six copies it used to make (6 x 8 x N / 8 = 1.2 MB at
    # N = 2e5; the fixed fire measured well under that, unit G's report)
    mktempdir() do dir
        alloc_turn(task, rep) = (execute!(task, rep; turns=2); (@allocated execute!(task, rep; turns=10)) / 10)
        base = alloc_turn(TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(_FixGNoopObserver()),),
                                       artifact=RunArtifact(joinpath(dir, "noop.h5"))), r)
        with = alloc_turn(TrackingTask((DriftSpec(L=1.0),);
                                       hooks=(ScheduledObserver(CoordinateSnapshotObserver(name="s"; npart=16)),),
                                       artifact=RunArtifact(joinpath(dir, "snap.h5"))), r)
        @testset let per_fire_bytes = with - base
            @test per_fire_bytes < 6 * n * 8 ÷ 8                 # was about 9.6 MB plus the push
        end
        rows = read(TaskOutput(joinpath(dir, "snap.h5")), :snapshot; name="s")
        @test length(rows.turn) == 10 * 16 && rows.particle_id[1:16] == 1.0:16.0
    end
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        # `r` has been tracked by the task loop above: compare against a
        # fresh host block of the same state, not the pre-loop `block`
        g = Phase6DRep((Octopus.CUDA.CuArray(a) for a in coordinate_arrays(r))...)
        @test Octopus._snapshot_block(g, 0, 16, 7) == Octopus._snapshot_block(r, 0, 16, 7)   # the same particles, through device views
        Octopus._snapshot_block(g, 0, 16, 7)
        @test (@allocated Octopus._snapshot_block(g, 0, 16, 7)) < 1_048_576   # was 6 x 8 x N = 9.6 MB of host copies
    else
        @test_skip "CUDA device not available: the snapshot's device-to-host view copy is not exercised"
    end
end
