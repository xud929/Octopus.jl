# Ordinary-path numerical and allocation baseline; run from the project root with Julia --project=. --threads=4.
using Octopus, SHA
const cuda = Octopus.CUDA
cuda.functional() || error("baseline requires CUDA")
println("hardware=", cuda.name(cuda.device()), " threads=", Threads.nthreads())
for T in (Float32, Float64), backend in (CPUThreadsBackend, CUDABackend)
    n = 257
    rep = Phase6DRep(T.(range(-0.003, 0.003; length=n)), fill(T(1e-5), n),
        T.(range(-0.001, 0.001; length=n)), fill(T(-2e-5), n),
        T.(range(-0.02, 0.02; length=n)), zeros(T, n))
    rep = Octopus._rep_on_backend(backend, rep)
    line = (ThinCrabCavitySpec{1,T}(394e6; strengthX=(T(0.002),),
               phase_noise=(TurnTable(T[0.01, -0.02, 0.03]),)),
            DriftSpec{T}(L=T(0.5)), ApertureSpec{T}(x_limit=T(0.002), name="test"))
    task = TrackingTask(line; loss_report=false)
    allow_lost_particles(; enabled=true) do
        execute!(task, rep; turns=3)
    end
    coords = reduce(vcat, Array.(coordinate_arrays(rep)))
    println("BASELINE type=", T, " backend=", backend,
        " sha256=", bytes2hex(sha256(reinterpret(UInt8, coords))),
        " counts=", loss_counts(loss_record(task)), " next_turn=", task.next_turn[])
end
for T in (Float32, Float64), backend in (CPUThreadsBackend, CUDABackend)
    rep = Octopus._rep_on_backend(backend, Phase6DRep(ntuple(k -> T.(range(-0.001*k,0.002*k; length=257)), 6)...))
    lm = Linear6DSpec{T}(beta1=T[2,3,4], beta2=T[3,5,2], alpha1=T[.2,-.3,.1], alpha2=T[-.1,.4,.2], dmu=T[.7,1.1,-.2], zeta1=T[.01,.02,-.01,.03], zeta2=T[-.02,.01,.04,.02], eta1=T[.03,-.02,.01,.04], eta2=T[.02,.01,-.02,.03], R1=T[.01,.02,-.03,.01], R2=T[-.02,.01,.03,.02])
    execute!(TrackingTask((lm,); loss_report=false),rep;turns=3)
    coords=reduce(vcat,Array.(coordinate_arrays(rep)))
    println("LINEAR_BASELINE type=",T," backend=",backend," sha256=",bytes2hex(sha256(reinterpret(UInt8,coords))))
end
using Octopus, Test
include(joinpath(pkgdir(Octopus), "test", "phase_space_reset_probe.jl"))
const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
ip = StrongStrongCollision(:ip)
suite = read(joinpath(pkgdir(Octopus), "test", "runtests.jl"), String)
function run_testset(title)
    marker = "@testset \"" * title * "\" begin"
    start = findfirst(marker, suite)
    start === nothing && error("missing testset " * title)
    expression, _ = Meta.parse(suite, first(start))
    Core.eval(Main, expression)
end
run_testset("(e) once-per-execute! walks")
run_testset("Phase-space reset: lifecycle, ownership, exact restoration and refusals")
run_testset("No method grows a Core.Box outside the argued allowlist")
println("ALLOCATION_AND_CORE_BOX_PASSED")

