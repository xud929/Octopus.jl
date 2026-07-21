using Test
using Octopus

@testset "Architecture integrity" begin
    metadata = validate_element_metadata(; throw_on_error=true)
    @test metadata.passed
    @test validate_configuration_metadata()

    snapshot_path = joinpath(pkgdir(Octopus), "docs", "registry_snapshot.md")
    @test registry_snapshot_markdown() == read(snapshot_path, String)
end

@testset "Counter RNG smoke tests" begin
    philox1 = [counter_normal(0x12345678, 3, 9, i, 1, Float64) for i in 1:1000]
    philox2 = [counter_normal(0x12345678, 3, 9, i, 1, Float64) for i in 1:1000]
    another_component = [
        counter_normal(0x12345678, 3, 9, i, 2, Float64) for i in 1:1000
    ]
    uniforms = [counter_uniform01(0x12345678, 3, 9, i, 1, Float64) for i in 1:1000]

    @test philox1 == philox2
    @test philox1 != another_component
    @test all(isfinite, philox1)
    @test all(value -> 0.0 < value < 1.0, uniforms)
end

struct TestNoopObserver <: Octopus.AbstractBeamObserver end
Octopus.observe!(::TestNoopObserver, ctx::Octopus.TrackingContext, rep) = nothing

function run_turn_signal_smoke(hooks)
    spec = ThinStrongBeamSpec(;
        kbb=1.0e-4,
        beta=(1.0, 1.0),
        sigma=(1.0e-3, 1.0e-3),
        centroid_signal=LinearTurnSignal((0.0, 0.0), (1.0e-3, 0.0)),
    )
    rep = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])
    execute!(TrackingTask((spec,); hooks=hooks), rep; turns=2)
    return rep[1]
end

@testset "TrackingTask smoke test" begin
    initial = (1.0e-3, 0.0, 2.0e-3, 0.0, 0.0, 0.0)
    fast = run_turn_signal_smoke(())
    planned = run_turn_signal_smoke((TestNoopObserver(),))

    @test fast == planned
    @test fast != initial
end

@testset "Configuration rejection" begin
    @test_throws ArgumentError CPUThreadsExecutionPolicy(threads=0)
    @test_throws ArgumentError CUDALaunchConfig(threads=0)
    @test_throws ArgumentError CUDAExecutionPolicy(device=-1)
end
