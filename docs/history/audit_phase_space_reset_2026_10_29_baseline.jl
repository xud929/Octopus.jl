# Reproduce the ordinary-path fingerprints in audit_phase_space_reset_2026_10_29.md.
# Run: julia --project=. --threads=4 docs/history/audit_phase_space_reset_2026_10_29_baseline.jl
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
