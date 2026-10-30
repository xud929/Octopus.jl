# U1 targeted particle-tune neighbour-audit reproducer, 2026-10-30.
# See U1.md for the measured red/green result and scope.
using Octopus, Test

mutable struct U1AxesGate
    enabled::Bool
    arrived::Channel{Nothing}
    release::Channel{Nothing}
end
mutable struct U1GateVector{T} <: AbstractVector{T}
    data::Vector{T}
    gate::U1AxesGate
    first_coordinate::Bool
end
Base.IndexStyle(::Type{<:U1GateVector}) = IndexLinear()
Base.size(v::U1GateVector) = size(v.data)
Base.length(v::U1GateVector) = length(v.data)
Base.getindex(v::U1GateVector,i::Int) = v.data[i]
Base.setindex!(v::U1GateVector,x,i::Int) = (v.data[i] = x)
function Base.axes(v::U1GateVector)
    if v.first_coordinate && v.gate.enabled
        put!(v.gate.arrived,nothing)
        take!(v.gate.release)
    end
    return axes(v.data)
end

function main()
    Threads.nthreads() >= 2 || error("U1 concurrent witness requires at least two default threads")
    gate = U1AxesGate(false,Channel{Nothing}(2),Channel{Nothing}(2))
    rep = Phase6DRep(ntuple(k -> U1GateVector(fill(0.001k,8),gate,k == 1),6)...)
    spec = Linear6DSpec(beta1=(1.,1.,1.),dmu=(0.3,0.4,-0.05),particle_tunes=(nux=0.21,))
    task = TrackingTask((spec,);policy=CPUThreadsExecutionPolicy(threads=1),loss_report=false)
    execute!(task,rep;turns=1)
    gate.enabled = true
    finished = Channel{Any}(2)
    jobs = [Threads.@spawn begin
        result = try
            execute!(task,rep;turns=1)
            (ok=true,error="")
        catch err
            (ok=false,error=sprint(showerror,err))
        end
        put!(finished,result)
    end for _ in 1:2]
    arrived = 0
    results = Any[]
    deadline = time()+10
    while arrived+length(results) < 2 && time() < deadline
        while isready(gate.arrived)
            take!(gate.arrived)
            arrived += 1
        end
        while isready(finished)
            push!(results,take!(finished))
        end
        sleep(0.01)
    end
    # A fixed admission guard lets one job reach axes and rejects its peer.
    # The initial Bool implementation lets BOTH jobs cross its check before
    # either may set running=true. Release exactly the arrivals in either case.
    gate.enabled = false
    for _ in 1:arrived
        put!(gate.release,nothing)
    end
    status = timedwait(() -> all(istaskdone,jobs),10;pollint=0.01)
    status === :ok || error("U1 worker did not finish after bounded barrier release")
    foreach(fetch,jobs)
    while isready(finished)
        push!(results,take!(finished))
    end
    println("U1-CONCURRENT-ADMISSION arrived=",arrived,
            " accepted=",count(r -> r.ok,results)," refused=",count(r -> !r.ok,results))
    for result in results
        println("U1-CONCURRENT-RESULT ",result)
    end
    @test length(results) == 2
    @test count(r -> r.ok,results) == 1
    @test count(r -> !r.ok && occursin("concurrently or recursively",r.error),results) == 1
end
main()
