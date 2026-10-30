using Octopus, Test, Profile

crabN(N) = ThinCrabCavitySpec{N}(394.0e6;
    strengthX=ntuple(_ -> 2.0e-3, N), strengthY=ntuple(_ -> 5.0e-4, N),
    phase=ntuple(_ -> 0.1, N))
rep4() = Phase6DRep(collect(range(-1.0e-3, 1.0e-3; length=4)),
    zeros(4), zeros(4), zeros(4), zeros(4), zeros(4))
function measured(f)
    f(); f()
    return minimum([@allocated f() for _ in 1:3])
end
function profile_allocations(task, rep, label)
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate=1 execute!(task, rep; turns=1)
    allocations = Profile.Allocs.fetch().allocs
    bysite = Dict{String,Tuple{Int,Int}}()
    for allocation in allocations
        frame = findfirst(allocation.stacktrace) do f
            occursin("/Octopus/src/", String(f.file))
        end
        key = if frame === nothing
            "non-Octopus"
        else
            f = allocation.stacktrace[frame]
            string(f.func, " ", basename(String(f.file)), ":", f.line, " ", allocation.type)
        end
        previous = get(bysite, key, (0, 0))
        bysite[key] = (previous[1] + allocation.size, previous[2] + 1)
    end
    println("PROFILE ", label, " total=", sum(a.size for a in allocations),
            " allocations=", length(allocations))
    for (key, counts) in first(sort!(collect(bysite); by=x -> -last(x)[1]), min(18, length(bysite)))
        println("  ", counts, " ", key)
    end
    flush(stdout)
end
function main()
    hetero = Tuple(crabN(mod1(i, 8)) for i in 1:40)
    task_f = TrackingTask(hetero)
    task_g = TrackingTask(hetero; observers=(BPMObserver("walks"),))
    rf, rg = rep4(), rep4()
    for _ in 1:3
        execute!(task_f, rf; turns=1)
        execute!(task_g, rg; turns=1)
    end
    fast = measured(() -> execute!(task_f, rf; turns=1))
    general = measured(() -> execute!(task_g, rg; turns=1))
    entries = Octopus._runtime_entries(task_f, rf)
    elems = Octopus._physics_line(entries)
    has_reset = measured(() -> Octopus._has_phase_space_reset(entries))
    requires_task = measured(() -> Octopus._requires_tracking_task(elems))
    internal_fast = measured(() -> Octopus._execute_tracking_window!(task_f, rf; turns=1))
    internal_general = measured(() -> Octopus._execute_tracking_window!(task_g, rg; turns=1))
    println("ALLOC fast=", fast, " general=", general,
            " has_reset=", has_reset, " requires_task=", requires_task,
            " internal_fast=", internal_fast, " internal_general=", internal_general)
    println("FINGERPRINT fast=", Tuple(map(a -> Tuple(a), coordinate_arrays(rf))),
            " general=", Tuple(map(a -> Tuple(a), coordinate_arrays(rg))))
    flush(stdout)
    profile_allocations(task_f, rf, "fast")
    profile_allocations(task_g, rg, "general")
    @testset "Non-reset execution allocation regression" begin
        @test fast < 400_000
        @test general < 400_000
        @test has_reset <= 256
        @test requires_task <= 256
    end
end
main()
