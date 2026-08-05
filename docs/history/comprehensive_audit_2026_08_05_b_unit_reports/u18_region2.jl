using Test
using Octopus
using LinearAlgebra
# Test-only: Octopus takes no runtime dependency on any AD package.
using ForwardDiff
# Test-only: loading Symbolics activates the OctopusSymbolicsExt weak-dep
# extension, so the suite exercises the adapter the way a user reaches it.
# Before the extension existed the adapter was dead in package mode and the
# round-trip test silently took its unavailable branch forever (part 6, R3).
using Symbolics

const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
println("CUDA_TESTS_ACTIVE = ", CUDA_TESTS_ACTIVE)
# Deliberate mid-run failure for the crashed-execute! tests below.
struct FailAtTurnAction <: Octopus.AbstractBeamAction
    at::Int64
end
Octopus.apply_action!(a::FailAtTurnAction, ctx, rep) =
    (ctx.turn == a.at && error("deliberate failure at turn $(ctx.turn)"); nothing)

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

@testset "Every example script runs against the current interface" begin
    # Examples are the precedents agents and users imitate (AGENTS.md), and
    # none was executed by this suite -- which is how a refactor that renamed
    # an internal broke examples/knob_control.jl silently through six green
    # suite runs. Each script runs in a subprocess at its small config
    # defaults (the weak-strong pair at 2 turns / 10k macroparticles;
    # knob_control at 1 turn / 4 particles; strong-strong at 200/beam —
    # all CPU policy), so this also
    # enforces "update examples when public APIs change". Costs one package
    # load per script; exit 0 is the assertion, with the output tail
    # surfaced on failure.
    root = "/cfs/ad/dxu/Library/Julia/Octopus"
    scripts = vcat(
        [joinpath(root, "examples", f) for f in
         ("knob_control.jl", "weak_strong_tracking.jl", "strong_strong_tracking.jl")],
        [joinpath(root, "test", "examples", f) for f in
         ("weak_strong_tracking.jl", "strong_strong_tracking.jl")])
    for script in scripts
        buf = IOBuffer()
        p = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$(root) $(script)`,
                         stdout=buf, stderr=buf); wait=false)
        wait(p)
        ok = success(p)
        if !ok
            text = String(take!(buf))
            @info "example script failed" script last(text, 2000)
        end
        @test ok
    end
    # The clean examples write into repo-root result/ by their documented
    # config (gitignored, but every Pkg.test left the artifacts behind;
    # 2026-08-05 audit, U18-3). Remove exactly the files these runs create,
    # in both output directories, and leave anything else in result/ alone.
    for dir in (joinpath(root, "result"), joinpath(root, "test", "result")),
        name in ("weak_strong.lum", "weak_strong_moments.h5",
                 "pic_hcc.lum", "pic_hcc.ele.h5", "pic_hcc.pro.h5")

        rm(joinpath(dir, name); force=true)
    end
end

@testset "Every export is documented" begin
    # 76 of 335 exports lacked documentation when the 2026-08-05 audit swept
    # them (U13-5); the sweep also found ten exports whose complete
    # docstrings had silently DETACHED because a comment line sat between
    # the docstring and the definition — on this Julia that attaches the
    # docs to nothing, with no warning. This keeps both classes closed: a
    # new undocumented export and a docstring detached by a later comment
    # both land here by name.
    undocumented = [n for n in names(Octopus)
                    if n !== :Octopus && occursin("No documentation found",
                        string(Base.Docs.doc(Base.Docs.Binding(Octopus, n))))]
    @test isempty(undocumented)
end

@testset "The module precompiles without overwriting its own methods" begin
    # Part 6 §8.7: a same-signature method silently overwrote another, PASSED
    # the full suite (both methods behaved identically), and was caught only
    # by accident when an unrelated verification happened to load the package
    # in a fresh process. This guard makes that check deliberate. Two
    # subtleties bought by measurement: a plain runtime `include` is SILENT
    # about overwrites on this Julia, so the guard must force an actual
    # precompile (`Base.compilecache` is unconditional); and the driver can
    # exit 0 even when the worker reports the collision, so the assertion is
    # on the message, not the exit code. Costs one full precompile (~1 min).
    prog = "Base.compilecache(Base.identify_package(\"Octopus\"))"
    err = IOBuffer()
    p = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=/cfs/ad/dxu/Library/Julia/Octopus -e $prog`,
                     stderr=err, stdout=devnull); wait=false)
    wait(p)
    text = String(take!(err))
    @test success(p)
    @test !occursin("Method overwriting is not permitted", text)
    @test !occursin(r"Method definition .* overwritten", text)
end

@testset "Metadata queries and the validator check declarations, not themselves" begin
    # Audit part 7, K2/K3/K5/K6/K8.

    # K2: the three named-strength thin constructors build bit-identical
    # runtimes to the PTC-validated ThinMultipoleSpec spellings, which is what
    # justifies their PTCConsistencyContract declaration transitively -- the
    # PTC table exercises thin_multipole, and these are the same runtime.
    same(x, y) = typeof(x) == typeof(y) &&
        all(getfield(x, f) == getfield(y, f) for f in fieldnames(typeof(x)))
    let a = 0.037
        @test same(compile_runtime(ThinDipoleSpec(k0l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(a,))))
        @test same(compile_runtime(ThinDipoleSpec(k0sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(a,))))
        @test same(compile_runtime(ThinQuadrupoleSpec(k1l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(0.0, a))))
        @test same(compile_runtime(ThinQuadrupoleSpec(k1sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(0.0, a))))
        @test same(compile_runtime(ThinSextupoleSpec(k2l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(0.0, 0.0, a))))
        @test same(compile_runtime(ThinSextupoleSpec(k2sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(0.0, 0.0, a))))
    end

    # K5: list-returning queries hand out copies; mutating one must not
    # corrupt the registry.
    let c = required_contracts(ElementSpec{:sbend})
        push!(c, Int64)
        @test !(Int64 in required_contracts(ElementSpec{:sbend}))
        @test validate_element_metadata().passed
    end

    # K8: a line has no tracking method of its own; an explicit request is
    # rejected rather than silently discarded.
    let line = BeamLine("L", DriftSpec(L=1.0))
        @test compile_runtime(line) isa Octopus.CompositeLine
        @test_throws ArgumentError compile_runtime(line, Symplectic6DMap())
    end

    # K3/K6: probe metas registered temporarily, removed afterwards so the
    # snapshot test still sees only the real registry.
    try
        # K6: friendly_constructor = nothing is permitted metadata and must
        # be reported, not crash snapshot generation.
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:k6_probe, spec_type=ElementSpec{:k6_probe},
            friendly_constructor=nothing,
            example=ElementSpec{:k6_probe}(Dict{Symbol,Any}())))
        @test occursin("(no friendly constructor)", registry_snapshot_markdown())

        # K3: the injected-defect scenario that used to validate clean -- a
        # meta whose contract is not a contract, whose analysis is not an
        # analysis, and whose example cannot compile -- must now FAIL.
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:k3_liar, spec_type=ElementSpec{:k3_liar},
            tracking_methods=[Symplectic6DMap], runtime_type=Octopus.LatticeMagnet,
            contracts=[Int64], analyses=[String],
            example=ElementSpec{:k3_liar}(Dict{Symbol,Any}())))
        r = validate_element_metadata()
        @test !r.passed
        @test any(e -> occursin("k3_liar", e) && occursin("not an AbstractContract", e), r.errors)
        @test any(e -> occursin("k3_liar", e) && occursin("not an AbstractAnalysis", e), r.errors)
        @test any(e -> occursin("k3_liar", e) && occursin("does not compile", e), r.errors)
    finally
        for k in (:k6_probe, :k3_liar)
            delete!(Octopus.ELEMENT_META_BY_KIND, k)
            T = ElementSpec{k}
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
            filter!(t -> t !== T, Octopus.REGISTERED_ELEMENT_SPECS)
        end
    end
    @test validate_element_metadata().passed      # registry restored
end

@testset "StrongStrongTask luminosity_append continues one file" begin
    # Companion to MomentObserver append: with the default the .lum file is
    # rewritten per execute!; with luminosity_append=true it is continued,
    # replayed windows drop their stale rows, and a mismatched header is
    # refused. Together they make the injection swap-out workflow (a new
    # beam passed to the same task) produce continuous single files with no
    # driver-side stitching.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    ip = StrongStrongCollision(:ip)
    lines() = ((ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))),
               (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))))
    lum_turns(path) = [parse(Int, first(split(l))) for l in readlines(path)[2:end]]

    # default: replaced per execute! (historical behaviour, pinned)
    p1 = tempname() * ".lum"
    l1, l2 = lines()
    t1 = StrongStrongTask(l1, l2; luminosity_path=p1)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    @test lum_turns(p1) == [3, 4, 5]

    # append: continued across execute! calls and across a beam swap
    p2 = tempname() * ".lum"
    t2 = StrongStrongTask(l1, l2; luminosity_path=p2, luminosity_append=true)
    b1, b2 = beams(); execute!(t2, b1, b2; turns=3)
    b1new, b2same = beams(); execute!(t2, b1new, b2same; turns=4)
    @test lum_turns(p2) == collect(0:6)
    @test count(l -> startswith(l, "turn"), readlines(p2)) == 1     # one header

    # rewind idempotence: replaying from turn 3 drops the stale rows
    b1, b2 = beams(); execute!(t2, b1, b2; turns=2, start_turn=3)
    @test lum_turns(p2) == collect(0:4)

    # a mismatched header is refused, not silently mixed
    p3 = tempname() * ".lum"
    open(p3, "w") do io
        println(io, "turn\tother_ip")
        println(io, "0\t1.0")
    end
    t3 = StrongStrongTask(l1, l2; luminosity_path=p3, luminosity_append=true)
    b1, b2 = beams()
    @test_throws ArgumentError execute!(t3, b1, b2; turns=1)

    foreach(p -> rm(p; force=true), (p1, p2, p3))
end

@testset "Mixed-IP schedule rows drop loudly; solver equality is by configuration" begin
    # Two U4 observations (2026-08-05 audit §7). (1) A .lum row must carry
    # one value per collision column, and NaN already means "evaluated and
    # failed", so a turn where per-IP luminosity schedules disagree cannot
    # be written without corrupting one meaning or the other — the row is
    # dropped whole, and that loss is now loud. (2) _collision_solver
    # compared the two lines' solvers by identity, refusing structurally
    # identical objects built independently; solvers are immutable
    # configuration records, so equality is by type + resolved configuration.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    l6a = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
    l6b = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))
    mkpic(; kw...) = PICPoissonSolver(; kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, grid=(16, 16),
        slicing=LongitudinalSlicing(nslices=2, method=:equal_count), kw...)

    # (2) same configuration, distinct objects: accepted (threw
    # "different Poisson solver objects" before); a genuinely different
    # configuration still throws.
    t_eq = StrongStrongTask(
        (StrongStrongCollision(:ip; poisson_solver=mkpic()), l6a),
        (StrongStrongCollision(:ip; poisson_solver=mkpic()), l6b))
    b1, b2 = beams()
    @test (execute!(t_eq, b1, b2; turns=1); true)
    t_ne = StrongStrongTask(
        (StrongStrongCollision(:ip; poisson_solver=mkpic()), l6a),
        (StrongStrongCollision(:ip; poisson_solver=mkpic(grid=(24, 24))), l6b))
    b1, b2 = beams()
    @test_throws ArgumentError execute!(t_ne, b1, b2; turns=1)

    # (1) IP2 evaluates luminosity only at turn 0: turn 0 writes a complete
    # row, turn 1 is partial — dropped whole, loudly, and the file carries
    # exactly the complete rows.
    p = tempname() * ".lum"
    ip1 = StrongStrongCollision(:ip1; poisson_solver=mkpic())
    ip2 = StrongStrongCollision(:ip2;
        poisson_solver=mkpic(luminosity_schedule=AtTurns([0])))
    t = StrongStrongTask((ip1, l6a, ip2), (ip1, l6b, ip2); luminosity_path=p)
    b1, b2 = beams()
    @test_logs (:warn, r"luminosity row dropped") match_mode = :any execute!(
        t, b1, b2; turns=2)
    @test [parse(Int, first(split(l))) for l in readlines(p)[2:end]] == [0]
    rm(p; force=true)
end

@testset "MomentObserver append mode continues one table across executions" begin
    # append=false is the documented replace-per-execution behaviour (pinned
    # first); append=true creates a chunked/extendible HDF5 table whose
    # continuation state lives in the FILE, so chunked runs, injection
    # swap-outs, path-sharing tasks, and process restarts all produce one
    # table with continuous absolute turns. Replayed windows drop their stale
    # rows (the BPM idempotence rule), and a replace-mode file refuses to be
    # continued rather than corrupt.
    turns_in(path) = Octopus.HDF5.h5open(path) do f
        n = Int(read(f["record_count"])[1])
        Int.(f["data"][1:n, 1])
    end
    mk1() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)

    p1 = tempname() * ".h5"
    t1 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p1; capacity=2)),))
    execute!(t1, mk1(); turns=3)
    execute!(t1, mk1(); turns=3)
    @test turns_in(p1) == [3, 4, 5]                    # replace default, as documented

    p2 = tempname() * ".h5"
    obs = MomentObserver(p2; capacity=2, append=true)
    t2 = TrackingTask(dline; hooks=(ScheduledObserver(obs),))
    execute!(t2, mk1(); turns=3)
    execute!(t2, mk1(); turns=3)
    @test turns_in(p2) == collect(0:5)                 # one file, contiguous

    obs_restart = MomentObserver(p2; capacity=2, append=true)
    t3 = TrackingTask(dline; hooks=(ScheduledObserver(obs_restart),))
    execute!(t3, mk1(); turns=2, start_turn=6)
    @test turns_in(p2) == collect(0:7)                 # fresh object, same file: restart works

    p3 = tempname() * ".h5"
    obs3 = MomentObserver(p3; capacity=1, append=true)
    t4 = TrackingTask(dline; hooks=(ScheduledObserver(obs3),
                                    ScheduledAction(FailAtTurnAction(3))))
    @test_throws ErrorException execute!(t4, mk1(); turns=5)
    @test turns_in(p3) == [0, 1, 2]
    t5 = TrackingTask(dline; hooks=(ScheduledObserver(obs3),))
    execute!(t5, mk1(); turns=5)
    @test turns_in(p3) == collect(0:4)                 # retry replays without duplicates

    p4 = tempname() * ".h5"
    t6 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p4; capacity=2)),))
    execute!(t6, mk1(); turns=2)
    t7 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p4; capacity=2, append=true)),))
    @test_throws ArgumentError execute!(t7, mk1(); turns=2)   # fixed-size file refused

    t8 = TrackingTask(dline; hooks=(ScheduledObserver(
        MomentObserver(p2; capacity=2, append=true, orders=1:1)),))
    @test_throws ArgumentError execute!(t8, mk1(); turns=2)   # column mismatch refused

    foreach(p -> rm(p; force=true), (p1, p2, p3, p4))
end

@testset "Nested lines have length, reflection keeps state, folded sugar is rejected everywhere" begin
    # 2026-08-05 audit open-queue U11-1/2/3/4/8. An own-state sub-line
    # (cryostat) counted as ZERO length in every arc-length walker;
    # reverse() rebuilt positionally and dropped the line's own state; the
    # folded-strength override guard missed every thin kind; the same sugar
    # was assignable (stored-never-read) at spec level; and an aperture
    # inside a kept-whole line silently vanished from loss accounting.
    cryo = BeamLine("CRYO", QuadrupoleSpec(L=0.4, k1=1.0, nst=2),
                    DriftSpec(L=1.0); x_offset=2.0e-4)
    arc = BeamLine("ARC", cryo, DriftSpec(L=1.0))
    @test s_positions(arc) == [0.0, 1.4]
    @test Octopus.total_length(arc) == 2.4
    @test Octopus._aperture_s_positions(
        (cryo, DriftSpec(L=1.0), ApertureSpec(x_limit=1.0e-3, name="END"))) == [2.4]

    rev = reverse(cryo)
    @test getparam(rev, :x_offset, nothing) == 2.0e-4
    @test getparam(reverse(rev), :x_offset, nothing) == 2.0e-4

    tq = ThinQuadrupoleSpec(k1l=0.05)
    entry = line_entries(BeamLine("L", tq, DriftSpec(L=1.0)))[1]
    @test_throws ArgumentError entry.k1l = 999.0
    q = QuadrupoleSpec(L=0.3, k1=1.2, nst=2)
    @test_throws ArgumentError q.k1 = 999.0

    hidden = BeamLine("CRYO2", ApertureSpec(x_limit=1.0e-3, name="HIDDEN"),
                      DriftSpec(L=0.5); x_offset=1.0e-4)
    @test_logs (:warn, r"outside loss accounting") match_mode = :any TrackingTask(
        (hidden, DriftSpec(L=1.0)))
    @test_logs TrackingTask((ApertureSpec(x_limit=1.0e-3, name="OPEN"),
                             DriftSpec(L=1.0)))
end

@testset "Unknown spec keys warn, placement keys bind, set_param! bumps the epoch" begin
    # 2026-08-05 audit open-queue U3-10/U13-1/U13-2. Every friendly
    # constructor documents open keyword storage, so unknown keys stay LEGAL
    # — but a typo of a physics parameter looked identical and tracked
    # silently (an out-of-schema e1=0.2 on a quadrupole shifts tracking by
    # 7.7e-7); construction now warns once naming the keys. The placement
    # keys compile_runtime consumes for EVERY kind (offsets, pitches, tilt,
    # ref_tilt, misalign_convention) are exempt and are now accepted by the
    # documented `spec.key = value` binding path, which used to reject them
    # on 17 of 30 kinds while compiling them happily. set_param! is the
    # deliberate-metadata door that bumps the recompile epoch the raw
    # params-Dict write skips.
    @test_logs (:warn, r"unknown parameter") match_mode = :any QuadrupoleSpec(
        L=0.3, k1=1.2, this_keyword_does_not_exist=1.0)
    # The offending key travels in the structured kwargs, which @test_logs
    # regexes do not inspect — match the message and check the kwarg below.
    @test_logs (:warn, r"unknown parameter") match_mode = :any ElementSpec{:quadrupole}(; bogus=2.0)
    @test_logs DriftSpec(L=0.5, x_offset=1.0e-3)          # placement: silent
    d = DriftSpec(L=0.5)
    d.x_offset = 1.0e-3
    @test compile_runtime(d) isa Octopus.MisalignedElement
    e0 = Octopus._spec_epoch()
    set_param!(d, :my_note, "hello")
    @test Octopus._spec_epoch() == e0 + 1
    @test d.params[:my_note] == "hello"
end

@testset "Contract coverage guards: declared kinds, solver tree, broken baselines, unrun contracts" begin
    # 2026-08-05 audit open-queue items U3-3/4/6/7. The symplecticity case
    # list now carries the solenoid (the one kind that DECLARES the
    # contract) and a declaration↔case tripwire; the configuration-metadata
    # validator derives solver/observer completeness from the type trees;
    # the effectiveness contract fails a probe-less solver; a throwing
    # baseline is a reported failure, not a silent skip; and the contracts
    # nothing used to execute run here.
    r = validate(SymplecticityContract())
    @test r.passed
    @test r.metrics[:kinds_declaring_without_case] == 0
    @test haskey(r.metrics, :Solenoid_residual)
    @test haskey(r.metrics, :SolenoidCurvedMultipole_residual)

    # Tripwire control: a temporarily registered kind declaring the contract
    # with an uncovered runtime type must FAIL the contract by name.
    try
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:symp_liar, spec_type=ElementSpec{:symp_liar},
            contracts=[SymplecticityContract], runtime_type=Base.RefValue))
        rl = validate(SymplecticityContract())
        @test !rl.passed
        @test occursin("symp_liar", rl.message)
    finally
        delete!(Octopus.ELEMENT_META_BY_KIND, :symp_liar)
        delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, ElementSpec{:symp_liar})
        filter!(t -> t !== ElementSpec{:symp_liar}, Octopus.REGISTERED_ELEMENT_SPECS)
    end
    @test validate(SymplecticityContract()).passed        # registry restored

    # Broken-baseline control (U3-7): a probe whose baseline throws must fail
    # the parameter contract naming the kind, not vanish into the skip count.
    let probes = copy(Octopus.DEFAULT_ELEMENT_PARAM_PROBES)
        probes[:quadrupole] = (L="not a length",)
        rb = validate(ElementParameterEffectivenessContract(probes=probes))
        @test rb.status === :failed
        @test occursin("quadrupole", rb.message)
        @test rb.metrics[:broken_kinds] == 1
    end

    # Probe-less-solver control (U3-4 sibling): the sweep must refuse to run
    # with a solver missing from its probe table.
    let probes = copy(Octopus._default_solver_option_probes())
        delete!(probes, :SpectralPoissonSolver)
        rs = validate(SolverOptionEffectivenessContract(probes=probes))
        @test rs.status === :failed
        @test occursin("SpectralPoissonSolver", rs.message)
    end

    # U3-6/U21-13: these contracts were executed by no test and no CI.
    rp = validate(PublicConfigurationEffectivenessContract())
    rp.status === :passed ||
        @info "public-configuration contract result" rp.status rp.message rp.metrics
    @test rp.status === :passed || (rp.status === :skipped && !CUDA_TESTS_ACTIVE)
    if CUDA_TESTS_ACTIVE
        @test validate(StrongStrongPICBackendConsistencyContract()).passed
        @test validate(StrongStrongGaussianBackendConsistencyContract()).passed
    else
        @test_skip "CUDA device not available"
    end
end

@testset "The elliptical strong-beam kick differentiates" begin
    # 2026-08-05 audit open-queue U7-1: the η≠0 Bassetti-Erskine kick threw
    # under ForwardDiff — the near-round precision calibration rejected dual
    # number types outright, and the exact CPU Faddeeva route had no dual
    # method. The OctopusForwardDiffExt rules (shared verbatim with script
    # mode) supply the holomorphic Faddeeva derivative w′(z) = −2zw(z) + 2i/√π
    # and the calibration pass-through. Correctness is pinned by the
    # symplecticity of the dual-computed Jacobian, which needs every entry
    # jointly right (central-difference cross-check at build: 6.8e-5, the FD
    # floor); pre-fix this testset errors instead of failing a tolerance.
    el = compile_runtime(ThinStrongBeamSpec{Float64}(kbb=1.0e-4, beta=(1.0, 1.0),
                                                     sigma=(106.0e-6, 9.5e-6)))
    u0 = [0.8e-4, 1.0e-5, 0.4e-4, -2.0e-5, 1.0e-3, 1.0e-4]
    J = ForwardDiff.jacobian(u -> collect(el(u...)), u0)
    S6 = zeros(6, 6)
    for (q, p) in ((1, 2), (3, 4), (5, 6))
        S6[q, p] = 1.0
        S6[p, q] = -1.0
    end
    @test maximum(abs, J' * S6 * J - S6) < 1.0e-10
end

@testset "Every continuing observer drops its replayed window" begin
    # 2026-08-05 audit open-queue U6-2: only MomentObserver and the task-level
    # .lum path followed the drop-at-first_turn idempotence rule; the
    # Luminosity, JLD2, binary-moment, and coordinate-snapshot observers
    # duplicated turn labels on a crashed-execute! retry or an explicit rewind
    # (measured [0,1,2,0,1,2,3,4,5]). All four now discard rows/records at or
    # beyond the incoming window's first turn; snapshots use the observer's
    # (turn → byte offset) map, since their record format carries no turn
    # label.
    mk1() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)

    p1 = tempname() * ".tsv"
    t1 = TrackingTask(dline; hooks=(ScheduledObserver(LuminosityObserver(p1)),))
    execute!(t1, mk1(); turns=3)
    execute!(t1, mk1(); turns=4, start_turn=1)
    @test [parse(Int, first(split(l, '\t'))) for l in readlines(p1)] == collect(0:4)

    p2 = tempname() * ".jld2"
    t2 = TrackingTask(dline; hooks=(ScheduledObserver(JLD2BeamMomentObserver(p2; capacity=1)),))
    execute!(t2, mk1(); turns=3)
    execute!(t2, mk1(); turns=4, start_turn=1)
    jturns = Octopus.JLD2.jldopen(p2, "r") do f
        Int.(f["data"][:, 1])
    end
    @test jturns == collect(0:4)

    p3 = tempname() * ".dat"
    t3 = TrackingTask(dline; hooks=(ScheduledObserver(BeamMomentObserver(p3; capacity=1)),))
    execute!(t3, mk1(); turns=3)
    execute!(t3, mk1(); turns=4, start_turn=1)
    bturns = open(p3, "r") do io
        n = Int(read(io, Int32))
        fl = Int(read(io, Int32))
        fmt = String(read(io, fl))
        ncols = count(==(','), fmt) + 1
        [(seek(io, 8 + fl + (i - 1) * ncols * 8); Int(read(io, Float64))) for i in 1:n]
    end
    @test bturns == collect(0:4)

    p4 = tempname() * ".dat"
    t4 = TrackingTask(dline; hooks=(ScheduledObserver(CoordinateSnapshotObserver(p4; append=false)),))
    execute!(t4, mk1(); turns=3)
    execute!(t4, mk1(); turns=2, start_turn=1)
    nrec = open(p4, "r") do io
        c = 0
        while !eof(io)
            n = Int(read(io, UInt32))
            skip(io, 6 * n * 8)
            c += 1
        end
        c
    end
    @test nrec == 3

    foreach(p -> rm(p; force=true), (p1, p2, p3, p4))
end

@testset "Philox4x32-10 matches the Random123 known-answer vectors" begin
    # 2026-08-05 audit (U15-1/U19-5): the RNG validation script measures only
    # moments and correlations, and PASSED a Philox with the Weyl key bump
    # removed and a 3-round variant. These are the upstream Random123
    # kat_vectors for philox4x32-10, driven exactly as counter_philox4x32
    # drives the round loop; they pin the implementation, not its statistics.
    philox10(c0, c1, c2, c3, k0, k1) = begin
        for _ in 1:Octopus.PHILOX4X32_ROUNDS
            c0, c1, c2, c3 = Octopus._philox4x32_round(c0, c1, c2, c3, k0, k1)
            k0 += Octopus.PHILOX4X32_W0
            k1 += Octopus.PHILOX4X32_W1
        end
        (c0, c1, c2, c3)
    end
    @test Octopus.PHILOX4X32_ROUNDS == 10
    @test philox10(0x00000000, 0x00000000, 0x00000000, 0x00000000,
                   0x00000000, 0x00000000) ==
          (0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8)
    @test philox10(0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
                   0xffffffff, 0xffffffff) ==
          (0x408f276d, 0x41c83b0e, 0xa20bc7c6, 0x6d5451fd)
    @test philox10(0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344,
                   0xa4093822, 0x299f31d0) ==
          (0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1)
end

@testset "Wrapped stochastic elements keep their context, shared streams warn, unbound apertures cannot corrupt" begin
    # 2026-08-05 audit F13/F14/F15. F13: MisalignedElement/RefTilted/
    # CompositeLine defined no context-aware call, so the generic
    # AbstractTrackOp fallback dropped ctx and a wrapped LumpedRad fell back
    # to its stateful contextless RNG — measured |dx| = 1.4e-4 between two
    # identical executions. F14: LumpedRadSpec auto-assigns one rng_id per
    # spec OBJECT, so placing one spec twice draws identical noise at both
    # placements (two kicks measured exactly 2x one; variance 4x not 2x) —
    # now warned at task construction. F15: a loss_record bump with an
    # unbound element_id=0 was a silent @inbounds out-of-bounds write.
    rad = LumpedRadSpec(
        damping_turns=(20.0, 25.0, 30.0),
        beta=(0.7, 0.9, 1.1),
        alpha=(0.2, -0.1, 0.05),
        sigma=(1.2e-3, 0.8e-3, 2.0e-3),
        rng_id=0x77,
        x_offset=1.0e-4)
    mk() = Phase6DRep([1.0e-3], [1.0e-4], [-0.5e-3], [2.0e-4], [1.0e-3], [1.0e-4])
    run_once() = begin
        set_global_rng!(seed=99, method=:philox)
        rep = mk()
        execute!(TrackingTask((rad,)), rep; turns=3)
        collect(coordinate_arrays(rep)[1])
    end
    @test compile_runtime(rad) isa Octopus.MisalignedElement
    @test run_once() == run_once()          # F13: bit-repeatable through the wrapper

    plain = LumpedRadSpec(damping_turns=(20.0, 25.0, 30.0), beta=(0.7, 0.9, 1.1),
                          alpha=(0.2, -0.1, 0.05), sigma=(1.2e-3, 0.8e-3, 2.0e-3),
                          rng_id=0x78)
    @test_logs (:warn, r"share an rng_id") match_mode = :any TrackingTask(
        (plain, DriftSpec(L=1.0), plain))   # F14: duplicate placement warns
    @test_logs TrackingTask((plain, DriftSpec(L=1.0)))  # single placement silent

    # F15: an unbound (element_id=0) recording aperture kills the particle but
    # leaves counts untouched and the loss unattributed — defined behavior,
    # where the unguarded write was memory corruption.
    counts = zeros(Int32, 1)
    Octopus._aperture_bump!(counts, 0)
    Octopus._aperture_bump!(counts, 2)
    Octopus._aperture_bump!(counts, 1)
    @test counts == Int32[1]
end

@testset "Append continuation: torn writes dropped, corruption refused, wipes loud" begin
    # 2026-08-05 audit (F1, U4-1/U4-2, U6-1, A-5): a hard-killed run leaves a
    # partial last line whose truncated turn field ("1" of "12") parses under
    # the idempotence drop rule and used to survive the retry as a duplicate
    # turn label; a fresh task with no start_turn used to wipe the whole
    # append file silently; a zero-byte HDF5 leftover used to fail with a raw
    # HDF5 open error. Now: torn last lines are dropped with a warning,
    # mid-file corruption is refused, total replacement warns naming the
    # start_turn remedy, and the zero-byte leftover initializes fresh.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    ip = StrongStrongCollision(:ip)
    l1 = (ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069)))
    l2 = (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)))
    lum_turns(path) = [parse(Int, first(split(l, '\t'))) for l in readlines(path)[2:end]]

    # A torn last line is dropped with a warning and cannot become a
    # duplicate turn label on the retry.
    p1 = tempname() * ".lum"
    t1 = StrongStrongTask(l1, l2; luminosity_path=p1, luminosity_append=true)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    open(io -> print(io, "1"), p1, "a")            # torn first byte of a "12..." row
    t1b = StrongStrongTask(l1, l2; luminosity_path=p1, luminosity_append=true)
    b1, b2 = beams()
    @test_logs (:warn, r"torn partial last line") match_mode = :any execute!(
        t1b, b1, b2; turns=1, start_turn=3)
    @test lum_turns(p1) == [0, 1, 2, 3]

    # A malformed row that is NOT last cannot come from a torn final write:
    # refused, and refused BEFORE any companion observer is truncated (U4-4).
    open(p1, "a") do io
        println(io, "garbage\trow")
        println(io, "9\t1.0")
    end
    t1c = StrongStrongTask(l1, l2; luminosity_path=p1, luminosity_append=true)
    b1, b2 = beams()
    @test_throws ArgumentError execute!(t1c, b1, b2; turns=1, start_turn=10)

    # Total replacement (fresh task, no start_turn) is loud, naming the remedy.
    p2 = tempname() * ".lum"
    t2 = StrongStrongTask(l1, l2; luminosity_path=p2, luminosity_append=true)
    b1, b2 = beams(); execute!(t2, b1, b2; turns=3)
    t2b = StrongStrongTask(l1, l2; luminosity_path=p2, luminosity_append=true)
    b1, b2 = beams()
    @test_logs (:warn, r"replacing the entire existing luminosity") match_mode = :any execute!(
        t2b, b1, b2; turns=2)
    @test lum_turns(p2) == [0, 1]

    # MomentObserver twin: loud wipe, and a zero-byte leftover initializes fresh.
    turns_in(path) = Octopus.HDF5.h5open(path) do f
        n = Int(read(f["record_count"])[1])
        Int.(f["data"][1:n, 1])
    end
    mk1() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)
    p3 = tempname() * ".h5"
    t3 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p3; capacity=2, append=true)),))
    execute!(t3, mk1(); turns=3)
    t3b = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p3; capacity=2, append=true)),))
    @test_logs (:warn, r"replacing the entire existing moment table") match_mode = :any execute!(
        t3b, mk1(); turns=2)
    @test turns_in(p3) == [0, 1]

    p4 = tempname() * ".h5"
    touch(p4)                                      # crash-at-create leftover
    t4 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p4; capacity=2, append=true)),))
    execute!(t4, mk1(); turns=2)
    @test turns_in(p4) == [0, 1]

    foreach(p -> rm(p; force=true), (p1, p2, p3, p4))
end

@testset "A task re-run on the other backend reallocates its loss record" begin
    # Audit part 7, T2: the `fits` test compared shape only, against its own
    # docstring's "shape or backend" -- a CPU-built record handed to a CUDA
    # kernel is a KernelError, and a device record handed to the CPU bump is a
    # MethodError.
    if CUDA_TESTS_ACTIVE
        line = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name="C"),
                DriftSpec(L=0.5))
        mk() = Phase6DRep([1.0e-3, 5.0e-3, 0.0, 0.0], zeros(4),
                          [0.0, 0.0, 1.0e-4, 0.0], zeros(4), zeros(4), zeros(4))
        task = TrackingTask(line)
        allow_lost_particles(; enabled=true) do
            execute!(task, mk(); turns=1)
            @test loss_counts(loss_record(task)) == [1]
            device = Phase6DRep((Octopus.CUDA.CuArray(a)
                                 for a in coordinate_arrays(mk()))...)
            execute!(task, device; turns=1)
            @test loss_record(task).counts isa Octopus.CUDA.CuArray
            @test loss_counts(loss_record(task)) == [1]
            execute!(task, mk(); turns=1)      # and back
            @test loss_record(task).counts isa Array
            @test loss_counts(loss_record(task)) == [1]
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "BPM reads a device number, not the truth" begin
    line = (QuadrupoleSpec(L=0.4, k1=1.7, nst=4), DriftSpec(L=0.6),
            QuadrupoleSpec(L=0.4, k1=-1.7, nst=4), DriftSpec(L=0.6))
    mkrep() = Phase6DRep([1.0e-3, 2.0e-3, -1.0e-3], [1.0e-4, -2.0e-4, 0.5e-4],
                         [0.5e-3, -1.5e-3, 2.0e-3], [2.0e-4, 1.0e-4, -1.0e-4],
                         [0.0, 0.0, 0.0], [1.0e-3, -1.0e-3, 0.0])

    # The reason a BPM is an observer and not an element: a zero-length element
    # cannot carry a reading offset. The entrance and exit frames cancel, so a
    # misaligned marker is the identity -- the machinery runs and the map is
    # bit-identical. Documented in docs/theory/bpm_measurement_model.md Sec. 2.
    let u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
        plain = compile_runtime(MarkerSpec())
        moved = compile_runtime(MarkerSpec(x_offset=1.0e-3, y_offset=-8.0e-4))
        @test moved isa MisalignedElement          # the wrap really is applied
        @test collect(moved(u...)) == collect(plain(u...))   # and does nothing
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

@testset "PTC consistency" begin
    # Compares LatticeMagnet against a committed PTC reference table generated
    # by validation/generate_ptc_reference.jl. Skips cleanly when the table is
    # absent; MAD-X is never needed at test time.
    result = validate(PTCConsistencyContract())
    @test result.status in (:passed, :skipped)
    if result.status === :passed
        @test result.metrics[:cases] >= 36
        @test haskey(result.metrics, :madx_version)
        # Fringe and pole-face cases. These are what pin the PTC behaviours a
        # source comparison turned up: the MAD8 quadrupole-in-wedge kick
        # (cfbend_edge), the HIGHEST_FRINGE=2 cap (multipole_fringe), the
        # NMUL<=1 skip (sbend_fringe) and the BN(1) drop (cfbend_fringe).
        for k in (:dev_quadrupole_fringe, :dev_multipole_fringe, :dev_sbend_fringe,
                  :dev_cfbend_fringe, :dev_sbend_edge, :dev_cfbend_edge, :dev_sbend_fint,
                  :dev_quad_mis_dx, :dev_quad_mis_dy, :dev_quad_mis_ds,
                  :dev_quad_mis_dtheta, :dev_quad_mis_dphi, :dev_quad_mis_dpsi,
                  :dev_sext_mis_dx, :dev_quad_mis_all,
                  :dev_cfbend_mis_dx, :dev_cfbend_mis_all,
                  :dev_rbend, :dev_rbend_k1, :dev_thin_multipole,
                  :dev_thin_multipole_skew,
                  # ref_tilt: the design-orbit roll MAD-X spells `tilt` on the
                  # bend itself. The last two carry a roll AND a misalignment,
                  # which is the only way the frame the error is quoted in
                  # becomes observable -- with the wrong choice they land at
                  # 2.0e-4 and 3.5e-4 rather than here.
                  :dev_sbend_reftilt, :dev_sbend_reftilt_vertical,
                  :dev_cfbend_reftilt, :dev_cfbend_reftilt_mis_dx,
                  :dev_cfbend_reftilt_mis_all,
                  # The same through RBEND, which reaches the sector map via
                  # the angle/2 face conversion the roll has to survive.
                  :dev_rbend_reftilt, :dev_rbend_reftilt_vertical,
                  :dev_rbend_k1_reftilt_mis_all,
                  # A spread of roll angles: negative, cos = sin, cos < 0, the
                  # full flip, and the near-identity regime. Our map has no
                  # quadrant logic, so these mostly pin that MAD-X has none
                  # either -- it neither normalises nor special-cases `tilt`.
                  :dev_sbend_reftilt_neg, :dev_cfbend_reftilt_quarter,
                  :dev_sbend_reftilt_obtuse, :dev_sbend_reftilt_pi,
                  :dev_sbend_reftilt_small,
                  # The ordering case at a NEGATIVE roll: a sign slip in the
                  # R_z(-psi) conjugation survives every positive-angle case.
                  :dev_cfbend_reftilt_neg_mis_all)
            @test result.metrics[k] < 1.0e-11
        end
        # Straight elements should agree to MAD-X's printed precision. The bend
        # is looser and deliberately so -- see the contract docstring.
        # Every element type, including combined-function bends, agrees with
        # PTC to MAD-X's printed precision.
        @test result.metrics[:max_deviation] < 1.0e-11
        for k in (:dev_drift, :dev_quadrupole_m2_n1, :dev_quadrupole_m4_n3,
                  :dev_sextupole_m4_n2, :dev_octupole_m2_n4,
                  :dev_sbend_m2_n4, :dev_cfbend_m2_n4, :dev_cfbend_m4_n2,
                  :dev_multipole_m2_n4, :dev_multipole_m4_n2)
            @test result.metrics[k] < 1.0e-11
        end
    end
end

@testset "Lattice cells track and stay symplectic" begin
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    track(cell, u) = foldl((c, e) -> e(c...), cell; init=u)
    function jac(cell, u0)
        J = zeros(6, 6)
        for j in 1:6
            u = ComplexF64[u0...]
            u[j] += 1e-30im
            J[:, j] = imag.(collect(track(cell, Tuple(u)))) ./ 1e-30
        end
        return J
    end
    q(k, L=0.3) = compile_runtime(QuadrupoleSpec(L=L, kn=(0.0, k), nst=4, integrator_order=4))
    d(L) = compile_runtime(DriftSpec(L=L))
    b(L, ang) = compile_runtime(SBendSpec(L=L, h=ang / L, b0=ang / L, nst=4, integrator_order=4))
    sx(k2) = compile_runtime(SextupoleSpec(L=0.2, kn=(0.0, 0.0, k2), nst=4, integrator_order=4))

    fodo = (q(1.6), d(1.2), q(-1.6), d(1.2))
    dba = (q(-1.1, 0.25), d(0.6), b(1.0, 0.20), d(0.6), q(1.5, 0.35),
           d(0.6), b(1.0, 0.20), d(0.6), q(-1.1, 0.25))
    tba = (q(-1.0, 0.25), d(0.5), b(0.9, 0.14), d(0.5), q(0.9), d(0.5), b(0.9, 0.14),
           d(0.5), q(0.9), d(0.5), b(0.9, 0.14), d(0.5), q(-1.0, 0.25))

    u0 = (1.0e-4, 2.0e-5, -0.8e-4, -1.5e-5, 0.0, 0.0)
    for (name, cell) in (("FODO", fodo), ("DBA", dba), ("TBA", tba),
                         ("FODO+sext", (fodo..., sx(8.0))),
                         ("DBA+sext", (dba..., sx(8.0))),
                         ("TBA+sext", (tba..., sx(8.0))))
        J = jac(cell, u0)
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-12
        # Linearly stable in both planes, i.e. a usable cell rather than an
        # arbitrary sequence of elements.
        @test abs(J[1, 1] + J[2, 2]) < 2
        @test abs(J[3, 3] + J[4, 4]) < 2
        # Bounded over many turns.
        u = u0
        for _ in 1:200
            u = track(cell, u)
        end
        @test all(isfinite, u)
        @test maximum(abs, collect(u)[1:4]) < 1.0e-2
    end

    # Composed lines must be backend-consistent, not just single elements.
    for (name, cell) in (("FODO", fodo), ("DBA+sext", (dba..., sx(8.0))))
        r = validate(ElementTrackingBackendConsistencyContract(;
            line=cell, n_particles=512, turns=2,
            backend_a=CPUThreadsBackend, backend_b=CPUThreadsBackend,
            atol=1.0e-12, rtol=1.0e-12))
        @test passed(r)
        gpu = validate(ElementTrackingBackendConsistencyContract(;
            line=cell, n_particles=512, turns=2,
            backend_a=CPUThreadsBackend, backend_b=CUDABackend,
            atol=1.0e-10, rtol=1.0e-10))
        @test gpu.status in (:passed, :skipped)
    end

    # A counter-RNG element must COMPILE in the fused CUDA kernel. Every
    # stochastic draw funnels through octopus_uint64, whose unknown-method
    # throw as first written (2026-08-05 hygiene sweep, U15-4) interpolated
    # the code into the message — a heap string, invalid device IR — so any
    # line containing a stochastic element failed cuda_track_kernel!
    # compilation outright, and nothing here tracked one to notice. Caught by
    # the U21-5 validation-line extension; the message is static now, and
    # this pins the whole class: compile, run, and agree with the CPU.
    lumped = LumpedRadSpec{Float64}(;
        damping_turns=(4000.0, 4000.0, 2000.0), beta=(0.8, 0.072, 90.0),
        alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), rng_id=103)
    stochastic_gpu = validate(ElementTrackingBackendConsistencyContract(;
        line=(lumped,), n_particles=256, turns=2,
        backend_a=CPUThreadsBackend, backend_b=CUDABackend,
        atol=1.0e-10, rtol=1.0e-10))
    @test stochastic_gpu.status in (:passed, :skipped)
end

@testset "Configuration rejection" begin
    @test_throws ArgumentError CPUThreadsExecutionPolicy(threads=0)
    @test_throws ArgumentError CUDALaunchConfig(threads=0)
    @test_throws ArgumentError CUDAExecutionPolicy(device=-1)
end

@testset "Phase-space and element boundary validation" begin
    @test_throws ArgumentError Phase6DRep(
        zeros(2), zeros(1), zeros(2), zeros(2), zeros(2), zeros(2),
    )
    empty_rep = Phase6DRep(ntuple(_ -> Float64[], 6)...)
    @test length(empty_rep) == 0
    @test_throws ArgumentError Beam(0, CPUThreadsBackend)
    @test_throws ArgumentError longitudinal_slices(
        empty_rep, LongitudinalSlicing(method=:equal_count),
    )

    @test_throws ArgumentError ThinCrabCavity{1}(0.0)
    @test_throws ArgumentError ThinCrabCavitySpec{1}(Inf)
    @test_throws ArgumentError ThinCrabCavitySpec{1}(NaN)
end

@testset "Equal-count slicing permits empty slices" begin
    rep = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    slices = longitudinal_slices(rep, LongitudinalSlicing(nslices=3, method=:equal_count))
    @test length(slices.center) == 3
    @test sum(length, slices.indices) == 1
    @test issorted(slices.boundary)
    @test all(isfinite, slices.boundary)
end

@testset "MomentObserver task reuse" begin
    path = tempname() * ".h5"
    try
        observer = MomentObserver(path; orders=1, capacity=1)
        hook = ScheduledObserver(observer)
        task = TrackingTask((hook,))
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

function test_beam(rep)
    params = BeamParams{Float64}(
        charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=length(rep),
    )
    return Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end

@testset "StrongStrongTask chunking preserves stochastic physics" begin
    n = 128
    phase = range(0.0, 2pi; length=n + 1)[1:n]
    rep1 = Phase6DRep(
        1.0e-3 .* sin.(phase), 2.0e-4 .* cos.(phase),
        0.7e-3 .* cos.(phase), 1.0e-4 .* sin.(2 .* phase),
        collect(range(-2.0e-3, 2.0e-3; length=n)),
        3.0e-4 .* cos.(2 .* phase),
    )
    rep2 = Phase6DRep(
        reverse(copy(rep1.x)), reverse(copy(rep1.px)),
        reverse(copy(rep1.y)), reverse(copy(rep1.py)),
        reverse(copy(rep1.z)), reverse(copy(rep1.pz)),
    )
    initial1, initial2 = test_beam(rep1), test_beam(rep2)
    radiation1 = LumpedRadSpec(
        damping_turns=(30.0, 35.0, 40.0),
        beta=(0.8, 1.1, 1.2), sigma=(1.0e-3, 0.8e-3, 2.0e-3),
        rng_id=0x201,
    )
    radiation2 = LumpedRadSpec(
        damping_turns=(32.0, 37.0, 42.0),
        beta=(0.9, 1.0, 1.3), sigma=(0.9e-3, 0.7e-3, 2.2e-3),
        rng_id=0x202,
    )
    solver = GaussianPoissonSolver(
        kbb1=1.0e-5, kbb2=-8.0e-6, luminosity_scale=1.0,
        slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
    )
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    task() = StrongStrongTask((radiation1, ip), (radiation2, ip))

    continuous1, continuous2 = deepcopy(initial1), deepcopy(initial2)
    chunked1, chunked2 = deepcopy(initial1), deepcopy(initial2)
    set_global_rng!(seed=0x51a7, method=:philox)
    execute!(task(), continuous1, continuous2; turns=6)
    set_global_rng!(seed=0x51a7, method=:philox)
    chunked_task = task()
    execute!(chunked_task, chunked1, chunked2; turns=2)
    execute!(chunked_task, chunked1, chunked2; turns=4)
    for (expected_beam, actual_beam) in (
            (continuous1, chunked1), (continuous2, chunked2))
        for (expected, actual) in zip(
                coordinate_arrays(expected_beam), coordinate_arrays(actual_beam))
            @test actual == expected
        end
    end
end

@testset "Zero-width PIC slice remains finite" begin
    n = 16
    x = collect(range(-1.0e-3, 1.0e-3; length=n))
    y = reverse(copy(x))
    beam1 = test_beam(Phase6DRep(copy(x), zeros(n), copy(y), zeros(n), zeros(n), zeros(n)))
    beam2 = test_beam(Phase6DRep(copy(y), zeros(n), copy(x), zeros(n), zeros(n), zeros(n)))
    solver = PICPoissonSolver(
        kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, longitudinal_kick=true,
        slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
    )

    luminosity = collide!(solver, beam1, beam2, CPUThreadsBackend)
    @test isfinite(luminosity)
    @test all(array -> all(isfinite, array), coordinate_arrays(beam1))
    @test all(array -> all(isfinite, array), coordinate_arrays(beam2))
end
