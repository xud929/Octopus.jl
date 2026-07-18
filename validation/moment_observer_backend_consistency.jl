#=
Compare the CPU and CUDA reduction paths used by MomentObserver. This is a
diagnostic implementation check; it does not exercise or change tracking.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Random
import CUDA

CUDA.functional() || error("CUDA is required for moment observer backend consistency")

n = parse(Int, get(ENV, "OCTOPUS_MOMENT_CONSISTENCY_N", "100000"))
rtol = parse(Float64, get(ENV, "OCTOPUS_MOMENT_CONSISTENCY_RTOL", "5e-12"))
rng = MersenneTwister(0x4f63746f707573)
scales = (9.5e-5, 1.2e-4, 8.5e-6, 1.2e-4, 6.0e-2, 6.6e-4)
offsets = (2.0e-6, -3.0e-7, 1.0e-7, 4.0e-8, -2.0e-3, 8.0e-6)
arrays = ntuple(i -> offsets[i] .+ scales[i] .* randn(rng, n), 6)
cpu_rep = Phase6DRep(arrays...)
gpu_rep = Phase6DRep(map(CUDA.CuArray, arrays)...)
cpu_observer = MomentObserver(tempname() * ".h5")
gpu_observer = MomentObserver(tempname() * ".h5")
ctx = TrackingContext(turn=17)

cpu_row = Octopus._moment_observer_row(ctx, cpu_rep, cpu_observer.moments, cpu_observer)
gpu_row = Octopus._moment_observer_row(ctx, gpu_rep, gpu_observer.moments, gpu_observer)
absolute_error = abs.(gpu_row .- cpu_row)
relative_error = absolute_error ./ max.(abs.(cpu_row), eps(Float64))
max_abs = maximum(absolute_error)
max_rel = maximum(relative_error)
passed = all(isapprox.(gpu_row, cpu_row; rtol=rtol, atol=1e-18))

println("MomentObserver CPU/CUDA reduction consistency")
println("particles = ", n)
println("columns = ", length(cpu_row))
println("max_abs_error = ", max_abs)
println("max_rel_error = ", max_rel)
println("rtol = ", rtol)
println("passed = ", passed)
passed || error("MomentObserver CPU/CUDA reduction consistency failed")
