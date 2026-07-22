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

    @test Octopus._uniform_open01(UInt64(0), Float64) == 2.0^-53
    @test Octopus._uniform_open01(typemax(UInt64), Float64) == prevfloat(1.0)
    @test Octopus._uniform_open01(UInt64(0), Float32) == 2.0f0^-24
    @test Octopus._uniform_open01(typemax(UInt64), Float32) == prevfloat(1.0f0)
    @test all(UInt64(0):(UInt64(1) << 23) - UInt64(1)) do bits
        value = Octopus._uniform_open01(bits << 41, Float32)
        0.0f0 < value < 1.0f0
    end
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

if Octopus._HAS_CUDA && Octopus.CUDA.functional()
    function test_gpu_beam(x, y)
        n = length(x)
        rep = Phase6DRep(
            Octopus.CUDA.CuArray(x), Octopus.CUDA.zeros(Float64, n),
            Octopus.CUDA.CuArray(y), Octopus.CUDA.zeros(Float64, n),
            Octopus.CUDA.zeros(Float64, n), Octopus.CUDA.zeros(Float64, n),
        )
        params = BeamParams{Float64}(
            charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n,
        )
        return Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
    end

    @testset "CUDA zero-width PIC routes remain finite" begin
        n = 16
        x = collect(range(-1.0e-3, 1.0e-3; length=n))
        y = reverse(copy(x))
        configurations = (
            (batch_mode=:sequential, cuda_indexed_wavefront=true),
            (batch_mode=:wavefront, cuda_indexed_wavefront=false),
            (batch_mode=:wavefront, cuda_indexed_wavefront=true),
        )
        for configuration in configurations
            beam1 = test_gpu_beam(x, y)
            beam2 = test_gpu_beam(y, x)
            solver = PICPoissonSolver(
                kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
                grid=(16, 16), green_cache=:none, longitudinal_kick=true,
                slicing=LongitudinalSlicing(nslices=1, method=:equal_count);
                configuration...,
            )
            luminosity = collide!(solver, beam1, beam2, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            @test isfinite(luminosity)
            @test all(array -> all(isfinite, Array(array)), coordinate_arrays(beam1))
            @test all(array -> all(isfinite, Array(array)), coordinate_arrays(beam2))
        end

        one_particle = test_gpu_beam([0.0], [0.0])
        slices = Octopus._cuda_longitudinal_slices(
            one_particle.rep, LongitudinalSlicing(nslices=3, method=:equal_count),
        )
        @test sum(length, slices.indices) == 1
        @test issorted(slices.boundary)
    end
end

@testset "Strong-strong physical parameter validation" begin
    rep1 = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    rep2 = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    beam1 = test_beam(rep1)
    beam2 = test_beam(rep2)
    solver = GaussianPoissonSolver(kbb1=0.0, kbb2=0.0)
    @test isfinite(collide!(solver, beam1, beam2, CPUThreadsBackend))

    zero_energy = BeamParams{Float64}(
        charge=1.0, mc2=1.0, E0=0.0, r0=1.0, npart=1.0,
    )
    invalid_beam = Beam{CPUThreadsBackend,typeof(zero_energy),typeof(rep1)}(zero_energy, rep1)
    @test_throws ArgumentError collide!(GaussianPoissonSolver(), invalid_beam, beam2, CPUThreadsBackend)
end

@testset "CODATA 2022 constants" begin
    @test RE == 2.8179403205e-15
    @test EMASS_EV == 0.51099895069e6
    @test ME0 === EMASS_EV
    @test PMASS_EV == 938.27208943e6
end
