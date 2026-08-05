# Minimal prelude reproducing test/runtests.jl's environment for region 6600-8759.
using Test
using Octopus
using LinearAlgebra
using ForwardDiff
using Symbolics

const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()

function test_beam(rep)
    params = BeamParams{Float64}(
        charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=length(rep),
    )
    return Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end

function nonfinite_test_rep(n; poison=nothing, value=NaN)
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    coords = Dict(
        :x => s(1.0e-4, 0.0), :px => s(1.0e-5, 0.3),
        :y => s(1.0e-4, 0.9), :py => s(1.0e-5, 1.2),
        :z => s(1.0e-2, 2.0), :pz => s(1.0e-4, 2.5),
    )
    poison === nothing || (coords[poison][5] = value)
    return Phase6DRep(coords[:x], coords[:px], coords[:y], coords[:py],
                      coords[:z], coords[:pz])
end

function expect_nonfinite_error(f)
    err = try
        f()
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test err isa ArgumentError && occursin("non-finite", err.msg)
    return nothing
end
